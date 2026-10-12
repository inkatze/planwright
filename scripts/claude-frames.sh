#!/bin/sh
# claude-frames.sh — the `claude-frames` evidence kind: Claude's own
# rate-limit readings, taken from the frames stream-json workers emit, and
# whether they show a Claude hold cleared. docs/quota.md describes the
# evidence kinds; this header pins the stored frame, the output, and the exit
# codes.
#
# The readings are account-wide: every session on the account counts toward
# them, so they are a ceiling to respect and never the fleet's own spend. Every
# rendering says so. They feed no usage-gate producer: the gate's signal is
# its own `/usage` read, which nothing here writes.
#
# THE STORED FRAME. The stream-json supervisor (scripts/fleet-streamjson.sh)
# hands each rate_limit_event line to `persist`, which keeps the worker's
# newest readings in <worker-state-dir>/ratelimit, rewritten whole (temp +
# rename), one line:
#   frame  received  session-util  session-reset  weekly-util  weekly-reset  end
# The session window is the frame's five_hour window and the weekly its
# seven_day; a utilization is the frame's fraction (0 to 1, at most 16 bytes),
# a reset epoch seconds (at most 15 digits), and a window the frame did not
# carry in that grammar is `-` in both fields. `received` is the supervisor's
# clock when the frame arrived.
#
# Usage:
#   claude-frames.sh persist --dir <worker-state-dir> [--now <epoch>]
#     Read one frame line on stdin and store its readings. The directory and
#     an existing frame file must be a real directory and a regular file,
#     never a link.
#   claude-frames.sh read [--now <epoch>]
#   claude-frames.sh clearance --since <epoch> [--now <epoch>]
#     Read every stored frame under <fleet-home>/streamjson/*/ratelimit and
#     print:
#       scope<TAB>account-wide<TAB><label>
#       window<TAB>session|weekly<TAB><percent|-><TAB><reset|-><TAB><received|-><TAB><threshold><TAB><state>
#       verdict<TAB><verdict>
#     Per window, a reading whose reset has passed, or lies further out than
#     the throttle's hold ceiling (`fleet-throttle.sh ceiling`), is ignored,
#     and of the rest the one with the furthest-future reset is taken (the
#     later receipt on a tie), whichever worker sent it, a dead one's
#     included. A frame line out of grammar, or received after --now, is
#     skipped. The threshold is the window's lowest-rung descend threshold,
#     its usage-gate downshift knob (`fleet_usage_session_downshift`,
#     `fleet_usage_weekly_downshift`), and a reading is below it when its
#     percentage is strictly less. A state is `unmeasured` (no reading),
#     `above`, `pre-hold` (clearance only: received no later than --since),
#     or `below`. The read verdict is `measured` or `unmeasured`; the
#     clearance verdict is `cleared` only when both windows are `below`,
#     `unmeasured` when neither has a reading, and `held` otherwise. A
#     backend that emits no frames leaves no file, so a fleet running only
#     such workers reads unmeasured, never as headroom.
#   claude-frames.sh label
#     Print the account-wide label, for a rendering outside this script.
#
# Exit: 0 success, or clearance granted · 1 persist found no usable reading
# (nothing written), or clearance not granted · 2 usage · 4/5 propagated from
# the knob resolver, 5 also when the throttle's ceiling cannot be read or a
# threshold is outside 1-100 · 6 a runtime failure (no fleet home, no clock,
# a link or non-regular file where the frame goes, a write).
#
# POSIX sh + awk on the bash 3.2 / BSD tooling floor. No eval; frame text is
# data, parsed by awk and never interpolated into a command.
set -uf
LC_ALL=C
export LC_ALL
unset CDPATH
umask 077

prog=claude-frames
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 6
FS="$script_dir/fleet-state.sh"
RESOLVER="$script_dir/resolve-config-knob.sh"
TAB=$(printf '\t')
LABEL="account-wide (every session on the Claude account counts toward it)"
LINE_MAX=65536

CUR_TMP=""
trap '[ -z "$CUR_TMP" ] || rm -f "$CUR_TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

usage() {
  printf '%s\n' "usage: claude-frames.sh persist --dir <dir> | read | clearance --since <epoch> | label [--now <epoch>]" >&2
  exit 2
}
die() {
  printf '%s: %s\n' "$prog" "$2" >&2
  exit "$1"
}
valid_epoch() {
  case $1 in
    "" | *[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 15 ]
}

[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
  persist) allowed="dir now" ;;
  read) allowed="now" ;;
  clearance) allowed="since now" ;;
  label) allowed="" ;;
  *) usage ;;
esac

dir="" dir_set=0 since="" since_set=0 now="" now_set=0
while [ $# -gt 0 ]; do
  case $1 in
    --dir | --since | --now) ;;
    *) usage ;;
  esac
  flag=${1#--}
  case " $allowed " in
    *" $flag "*) ;;
    *) die 2 "$verb takes no --$flag" ;;
  esac
  [ $# -ge 2 ] || usage
  case $flag in
    dir) dir=$2 dir_set=1 ;;
    since) since=$2 since_set=1 ;;
    now) now=$2 now_set=1 ;;
  esac
  shift 2
done

if [ "$verb" = label ]; then
  printf '%s\n' "$LABEL"
  exit 0
fi
[ "$verb" != persist ] || [ "$dir_set" = 1 ] || die 2 "persist needs --dir"
[ "$verb" != clearance ] || [ "$since_set" = 1 ] || die 2 "clearance needs --since"
if [ "$since_set" = 1 ]; then
  valid_epoch "$since" || die 2 "--since is not epoch seconds"
fi
if [ "$now_set" = 1 ]; then
  valid_epoch "$now" || die 2 "--now is not epoch seconds"
else
  now=$(date +%s)
  valid_epoch "$now" || die 6 "cannot read the clock"
fi

if [ "$verb" = persist ]; then
  # A link would land the frame wherever it points.
  [ ! -L "$dir" ] && [ -d "$dir" ] || die 6 "--dir is not a directory"
  rf="$dir/ratelimit"
  [ ! -L "$rf" ] || die 6 "refusing a symlink where the frame goes"
  [ ! -e "$rf" ] || [ -f "$rf" ] || die 6 "the frame file is not a regular file"
  # The supervisor hands over the line unbounded.
  stored=$(head -c "$LINE_MAX" | awk -v now="$now" '
    function util_ok(s) { return s ~ /^[0-9]+(\.[0-9]+)?$/ && length(s) <= 16 && s + 0 <= 1 }
    function reset_ok(s) { return s ~ /^[1-9][0-9]*$/ && length(s) <= 15 }
    # The object a key opens inside obj, without its braces; the window
    # objects are flat, so the first closing brace ends one.
    function window(obj, key,   p, body, e, u, r) {
      p = index(obj, "\"" key "\":{")
      if (!p) return "-\t-"
      body = substr(obj, p + length(key) + 4)
      e = index(body, "}")
      if (!e) return "-\t-"
      body = substr(body, 1, e - 1)
      u = field(body, "utilization")
      r = field(body, "resetsAt")
      if (!util_ok(u) || !reset_ok(r)) return "-\t-"
      return u "\t" r
    }
    function field(body, key,   p, v, c) {
      p = index(body, "\"" key "\":")
      if (!p) return ""
      v = substr(body, p + length(key) + 3)
      c = index(v, ",")
      if (c) v = substr(v, 1, c - 1)
      return v
    }
    NR == 1 {
      if (index($0, "{\"type\":\"rate_limit_event\",") != 1) exit 1
      p = index($0, "\"unifiedWindows\":{")
      if (!p) exit 1
      # Bound the search to the unifiedWindows object, so a window key
      # elsewhere in the line is never read as one.
      rest = substr($0, p + 18)
      depth = 1
      for (i = 1; i <= length(rest) && depth > 0; i++) {
        ch = substr(rest, i, 1)
        if (ch == "{") depth++
        else if (ch == "}") depth--
      }
      if (depth) exit 1
      obj = substr(rest, 1, i - 2)
      s = window(obj, "five_hour")
      w = window(obj, "seven_day")
      if (s == "-\t-" && w == "-\t-") exit 1
      printf "frame\t%s\t%s\t%s\tend\n", now, s, w
      exit 0
    }
    END { if (NR == 0) exit 1 }') || exit 1
  [ -n "$stored" ] || exit 1
  CUR_TMP=$(mktemp "$dir/.ratelimit.XXXXXX") || die 6 "cannot create a write temp"
  printf '%s\n' "$stored" >"$CUR_TMP" || die 6 "cannot write the frame"
  mv -f "$CUR_TMP" "$rf" || die 6 "cannot commit the frame"
  CUR_TMP=""
  exit 0
fi

# read / clearance
threshold() {
  [ -x "$RESOLVER" ] || die 5 "the knob resolver is missing or not executable (broken install)"
  th_v=$("$RESOLVER" --key "$1" --type posint --fallback "$2") || exit $?
  case $th_v in "" | *[!0-9]*) die 5 "$1 did not resolve to a number" ;; esac
  { [ "${#th_v}" -le 3 ] && [ "$th_v" -ge 1 ] && [ "$th_v" -le 100 ]; } || die 5 "$1 is outside 1-100"
  printf '%s' "$th_v"
}
s_thr=$(threshold fleet_usage_session_downshift 50) || exit $?
w_thr=$(threshold fleet_usage_weekly_downshift 60) || exit $?
ceiling=$(/bin/sh "$script_dir/fleet-throttle.sh" ceiling) || die 5 "cannot read the throttle's hold ceiling (broken install)"
case $ceiling in "" | *[!0-9]*) die 5 "the throttle's hold ceiling is not a number (broken install)" ;; esac

root=$("$FS" root) || die 6 "cannot resolve the fleet home"
sj="$root/streamjson"
# find never follows a link, the starting point included, so a linked store,
# worker directory, or frame file contributes nothing. Each file's first line
# only, newline-terminated, so a torn file cannot join the next.
frames=""
if [ -d "$sj" ] && [ ! -L "$sj" ]; then
  frames=$(find "$sj" -mindepth 2 -maxdepth 2 -name ratelimit -type f -size -4k \
    -exec awk 'FNR == 1' {} + 2>/dev/null) || frames=""
fi

printf '%s\n' "$frames" | awk -F "$TAB" -v now="$now" -v ceiling="$ceiling" \
  -v since="$since" -v verb="$verb" -v sthr="$s_thr" -v wthr="$w_thr" -v label="$LABEL" '
  function util_ok(s) { return s ~ /^[0-9]+(\.[0-9]+)?$/ && length(s) <= 16 && s + 0 <= 1 }
  function reset_ok(s) { return s ~ /^[1-9][0-9]*$/ && length(s) <= 15 }
  function take(k, u, r, t) {
    if (u == "-" && r == "-") return
    if (r + 0 <= now + 0 || r + 0 > now + ceiling) return
    if (!(k in reset) || r + 0 > reset[k] + 0 || (r + 0 == reset[k] + 0 && t + 0 > recv[k] + 0)) {
      reset[k] = r; util[k] = u; recv[k] = t
    }
  }
  function state(k, thr) {
    if (!(k in reset)) return "unmeasured"
    # Against the threshold as a fraction: util * 100 rounds 0.57 to just
    # under 57, which would clear a reading sitting exactly at it.
    if (util[k] + 0 >= thr / 100) return "above"
    if (verb == "clearance" && recv[k] + 0 <= since + 0) return "pre-hold"
    return "below"
  }
  function show(k, name, thr,   st) {
    st = state(k, thr)
    if (st == "unmeasured") printf "window\t%s\t-\t-\t-\t%s\tunmeasured\n", name, thr
    else printf "window\t%s\t%g\t%s\t%s\t%s\t%s\n", name, util[k] * 100, reset[k], recv[k], thr, st
    return st
  }
  NF == 7 && $1 == "frame" && $7 == "end" && $2 ~ /^[0-9]+$/ && length($2) <= 15 && $2 + 0 <= now + 0 {
    if (!(($3 == "-" && $4 == "-") || (util_ok($3) && reset_ok($4)))) next
    if (!(($5 == "-" && $6 == "-") || (util_ok($5) && reset_ok($6)))) next
    take("s", $3, $4, $2)
    take("w", $5, $6, $2)
  }
  END {
    printf "scope\taccount-wide\t%s\n", label
    s = show("s", "session", sthr)
    w = show("w", "weekly", wthr)
    if (s == "unmeasured" && w == "unmeasured") v = "unmeasured"
    else if (verb == "read") v = "measured"
    else if (s == "below" && w == "below") v = "cleared"
    else v = "held"
    printf "verdict\t%s\n", v
    if (verb == "clearance" && v != "cleared") exit 1
  }'
