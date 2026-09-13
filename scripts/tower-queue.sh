#!/bin/sh
# tower-queue.sh — the operator queue's script (tower-comms). This revision
# ships the event log and the scorecard: the `log` verb every queue writer,
# the tower loop, and the prompt-submit hook append through, and the `report`
# verb that computes the operator's load from that log alone (D-14, D-15;
# REQ-G1.1, REQ-G1.2, REQ-G1.5 to REQ-G1.8). The queue verbs land beside them.
#
# THE LOG. One flat JSON object per line under a 0700 sub-surface of the
# cross-spec fleet home (`fleet-state.sh root`): `<home>/tower-comms/`, holding
# `events.log`, the sequence counter `events.seq`, and `events.dropped`, one
# line per log line dropped at a lock-wait expiry. Every value is a string or
# a number and never a nested object or array, so the script's own awk reads
# it back with no JSON tool on the host (REQ-G1.7). Every line carries the schema version, a
# monotonic sequence read and bumped from the counter file inside the same
# critical section, the timestamp, and the event kind; `reply`, `acknowledged`,
# `delivered`, `knocked` and `tick` lines carry the writing tower's identity,
# without which two towers' lines are indistinguishable (REQ-G1.6).
#
#   log <kind> [--tower <id>] [--now <epoch>] [<key>=<value> ...]
#
# Kinds: born settled merged knocked delivered acknowledged shelved pushed
# session tick reply dropped unavailable refused. A `tick` needs `live=<n>`
# (the live-worker count) and coalesces with the previous line when that is a
# tick from the same tower with the same count within `tower_tick_gap_max`:
# the previous line's `until` advances instead of a new line landing, so a
# steady fleet costs one line per count change and a gap in the tick stream
# stays visible to the report. A `session` needs `event=start|rebuild`.
#
# Field grammar: keys match ^[a-z][a-z0-9_]{0,31}$ and are not one of the
# reserved names (v seq ts kind tower until); a value is at most 4096 bytes,
# carries no C0 control byte or DEL (a multi-line text is the caller's to
# flatten), and is refused when it is shaped like a JSON object or array. A
# value matching the JSON number grammar is written as a number, anything
# else as a string with `"` and `\` escaped. Every string value passes the
# secret-shaped redaction below before it is written, whatever the kind, so
# the hook and `capture` reuse this one helper instead of carrying their own
# (REQ-G1.8, REQ-H1.3).
#
# The lock wait is bounded by `tower_hook_lock_wait` (sub-second values are
# legal). On expiry nothing is written unlocked: the verb reports the expiry
# on stderr, appends one line to `events.dropped`, and exits 3, so the
# prompt-submit hook never delays the operator's turn on a busy lock and the
# drop is still counted. Rotation by age runs inside the same critical
# section: lines older than the larger of `tower_log_rotate_age` and
# `tower_report_window` are removed, the second being the floor that keeps
# the experiment's own sessions readable whatever the age is set to. It
# removes only what it can positively judge as old — a line it parses, whose
# header it reads, stamped behind the cutoff — so a torn line, a line from a
# writer on a schema version it does not know, and every line at all when the
# cutoff sits past the whole log (a stepped clock) survive it.
#
# THE SCORECARD.
#
#   report [--log <path>] [--now <epoch>] [--window <duration>]
#          [--tick-gap-max <duration>]
#
# Reads the log lock-free (a torn or malformed line is counted and skipped,
# never fatal), keeps the lines inside the `tower_report_window` window, and
# prints `<measure><TAB><value>` lines. The headline is the operator's load:
# items that reached the operator per hour of fleet work, against items
# settled without them. Fleet hours are wall-clock with at least one live
# worker, computed per tower from its own tick stream (a tick's span counts
# while its count is above zero, and so does the stretch to the next tick
# when it is within `tower_tick_gap_max`; a longer stretch is excluded and
# reported as a gap), the per-tower intervals unioned so an hour two towers
# both tick through counts once. Secondary measures: blocked-worker wait
# (question items from birth to acknowledgement, an open one to the window
# end), turns carrying more than one ask, items delivered in prose with no
# queue record, friction (what-does-that-mean replies, and a request of three
# or more words repeated), jargon in delivered text (spec identifiers,
# internal names, and the terms listed in tower-jargon.txt beside this
# script), and items dropped at a rebuild. `--log` and `--now` exist for
# fixtures and tests. On demand only: `mise run tower:report`, never CI
# (REQ-G1.5).
#
# Exit: 0 done (a coalesced tick included); 1 `report` found no log to read;
#   2 usage or refused input; 3 the bounded lock wait expired (line dropped);
#   4 the sub-surface, the log, or a counter is not verifiably owner-only, or
#   a repo-tracked knob is malformed (the by-layer policy); 5 broken install;
#   6 an infrastructure failure — a directory, temp file, rename, append,
#   clock or helper fork that would not answer, so the event was NOT
#   recorded. A caller reading 3 as "expected drop, carry on" and 2 as "I
#   called it wrong" needs 6 to stay distinct from both: it is the code that
#   says the host, not the call, is what stopped the log.
#
# Plain portable shell, no model invocation anywhere (REQ-H1.4); bash 3.2 /
# BSD tooling floor. Pathname expansion is off (set -f): the mode checks
# word-split an `ls` line that ends in a path, and a `*` in the fleet home's
# path must not expand against the working directory there.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 6

# Guarded like the jargon list `report` checks for: an unguarded `.` exits
# with the shell's own status for a missing file, which says nothing about
# which dependency went missing.
if [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "tower-queue: scripts/echo-safety.sh is missing — broken install" >&2
  exit 5
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

FS="$script_dir/fleet-state.sh"
RCK="$script_dir/resolve-config-knob.sh"
JARGON="$script_dir/tower-jargon.txt"
SCHEMA=1
KINDS="born settled merged knocked delivered acknowledged shelved pushed session tick reply dropped unavailable refused"
TOWER_KINDS="reply acknowledged delivered knocked tick"
RESERVED="v seq ts kind tower until"

usage() {
  cat >&2 <<'EOF'
usage: tower-queue.sh log <kind> [--tower <id>] [--now <epoch>] [<key>=<value> ...]
       tower-queue.sh report [--log <path>] [--now <epoch>] [--window <duration>] [--tick-gap-max <duration>]
EOF
  exit 2
}

err() {
  printf '%s\n' "tower-queue: $1" >&2
}

is_epoch() {
  case "$1" in
    "" | *[!0-9]* | 0?*) return 1 ;;
  esac
  [ "${#1}" -le 12 ]
}

# A tower identity: the presence surface's UUID or composite form, or the
# session-scoped fallback the queue verbs mint; a single path-safe token.
is_tower() {
  case "$1" in
    "" | *[!A-Za-z0-9._-]* | .* | -*) return 1 ;;
  esac
  [ "${#1}" -le 128 ]
}

is_key() {
  case "$1" in
    "" | *[!a-z0-9_]*) return 1 ;;
    [a-z]*) ;;
    *) return 1 ;;
  esac
  [ "${#1}" -le 32 ] || return 1
  for _r in $RESERVED; do
    [ "$1" != "$_r" ] || return 1
  done
  return 0
}

is_number() {
  case "$1" in
    -*) _nv=${1#-} ;;
    *) _nv=$1 ;;
  esac
  case "$_nv" in
    "" | *[!0-9.]* | .* | *. | *.*.*) return 1 ;;
    0?*)
      case "$_nv" in
        0.*) ;;
        *) return 1 ;;
      esac
      ;;
  esac
  [ "${#1}" -le 20 ]
}

is_count() {
  case "$1" in
    "" | *[!0-9]* | 0?*) return 1 ;;
  esac
  [ "${#1}" -le 15 ]
}

# The span grammar resolve-config-knob.sh's `duration` type defines, applied
# to the CLI flags and re-applied to whatever that resolver hands back. Kept
# in step with it: a value one accepts and the other refuses is a knob that
# behaves differently depending on whether it came from a flag or a layer.
is_duration() {
  _dv=$1
  case "$_dv" in
    *ms) _dv=${_dv%ms} ;;
    *[smhd]) _dv=${_dv%?} ;;
  esac
  case "$_dv" in
    "" | *[!0-9.]* | .* | *. | *.*.*) return 1 ;;
  esac
  [ "${#_dv}" -le 16 ] || return 1
  _di=${_dv%%.*}
  _df=""
  case "$_dv" in
    *.*) _df=${_dv#*.} ;;
  esac
  case "$_di" in
    0) [ -n "$_df" ] || return 1 ;;
    0*) return 1 ;;
  esac
  [ "${#_df}" -le 6 ] || return 1
  case "$_dv" in
    *[1-9]*) return 0 ;;
  esac
  return 1
}

# duration_seconds <duration> — print the span in seconds (decimal), a bare
# number read as seconds.
duration_seconds() {
  case "$1" in
    *ms)
      _dn=${1%ms}
      _dm=0.001
      ;;
    *s)
      _dn=${1%s}
      _dm=1
      ;;
    *m)
      _dn=${1%m}
      _dm=60
      ;;
    *h)
      _dn=${1%h}
      _dm=3600
      ;;
    *d)
      _dn=${1%d}
      _dm=86400
      ;;
    *)
      _dn=$1
      _dm=1
      ;;
  esac
  awk -v n="$_dn" -v m="$_dm" 'BEGIN {
    v = n * m
    # A span the validator accepted must not arrive here as zero: the
    # validator checks the literal and this rounds to milliseconds, so
    # without the floor a sub-millisecond span switches its knob off — a zero
    # lock wait drops every line, a zero window reports an empty scorecard.
    if (v > 0 && v < 0.001) v = 0.001
    printf "%.3f\n", v }'
}

# knob <key> <fallback> — resolve one duration knob through the shared
# resolver into seconds. Exit 4 and 5 (a malformed team-shared value, a
# broken install) propagate as this script's own exit.
knob() {
  _kv=$("$RCK" --key "$1" --type duration --fallback "$2")
  _krc=$?
  if [ "$_krc" -ne 0 ]; then
    err "cannot resolve the '$1' knob (resolve-config-knob exit $_krc)"
    exit "$_krc"
  fi
  check_duration "$1" "$_kv"
  duration_seconds "$_kv"
}

# check_duration <key> <value> — the resolver's output is re-checked before it
# is converted, the way the CLI spans are. duration_seconds reads anything
# non-numeric as 0.000, and a zero lock wait drops every line while a zero
# rotation span deletes the log, so an unexpected value must stop the verb
# rather than quietly become one of those.
check_duration() {
  is_duration "$2" || {
    err "the '$1' knob resolved to '$(sanitize_printable "$2" "(unprintable value)")', which is not a positive span"
    exit 4
  }
}

# resolve_log_knobs — the four knobs `log` reads, resolved side by side into
# lock_wait, gap_max, rotate_age and window (seconds). Each resolution is a
# chain of forks costing a third of a second on the support bar, and this
# verb runs on every operator prompt from the hook and on every tower-loop
# pass, so the four run concurrently and the wall clock pays for one. Each
# resolver's exit and value land in its own file; stderr is replayed in
# order so a degrade warning is never lost, and the first non-zero exit is
# this script's exit, the same contract as `knob`.
resolve_log_knobs() {
  _kd=$(mktemp -d 2>/dev/null) || {
    err "cannot create a scratch dir for the knob reads"
    exit 6
  }
  KNOB_DIR=$_kd
  for _ks in "tower_hook_lock_wait 2s" "tower_tick_gap_max 10m" "tower_log_rotate_age 30d" "tower_report_window 7d"; do
    (
      _kn=${_ks%% *}
      _kf=${_ks#* }
      _kv=$("$RCK" --key "$_kn" --type duration --fallback "$_kf" 2>"$_kd/$_kn.err")
      _krc=$?
      printf '%s\n%s\n' "$_krc" "$_kv" >"$_kd/$_kn"
    ) &
  done
  wait
  for _kn in tower_hook_lock_wait tower_tick_gap_max tower_log_rotate_age tower_report_window; do
    [ ! -s "$_kd/$_kn.err" ] || cat "$_kd/$_kn.err" >&2
    _krc=$(sed -n 1p "$_kd/$_kn" 2>/dev/null)
    _kv=$(sed -n 2p "$_kd/$_kn" 2>/dev/null)
    case "$_krc" in
      0) ;;
      "" | *[!0-9]*)
        err "cannot resolve the '$_kn' knob (no result from resolve-config-knob)"
        exit 6
        ;;
      *)
        err "cannot resolve the '$_kn' knob (resolve-config-knob exit $_krc)"
        exit "$_krc"
        ;;
    esac
    check_duration "$_kn" "$_kv"
    _ksec=$(duration_seconds "$_kv")
    case "$_kn" in
      tower_hook_lock_wait) lock_wait=$_ksec ;;
      tower_tick_gap_max) gap_max=$_ksec ;;
      tower_log_rotate_age) rotate_age=$_ksec ;;
      tower_report_window) window=$_ksec ;;
    esac
  done
  rm -rf "$_kd"
  KNOB_DIR=""
}

# redact <value> [<key>] — the one secret-shaped redaction helper (REQ-G1.8).
# The rules mirror inception-secret-screen.sh's built-in screen; a match is
# replaced by `[redacted:<rule>]`, the text around it kept. `#` delimits the
# sed expressions because `/` appears inside a bracket expression.
#
# The key is screened with the value because the log's own CLI shape puts the
# assignment's left half OUTSIDE the value: `password=<opaque>` as an argument
# and `password=<opaque>` inside a sentence are the same secret, but only the
# second one has the `key<sep>value` run the opaque-assignment rule needs. So
# for a secret-shaped key, an opaque run at the head of the value is that
# assignment's right half and goes the same way.
redact() {
  _rv=$1
  case "${2:-}" in
    *api_key* | *apikey* | *api-key* | *secret* | *token* | *password* | *passwd*)
      _rv=$(printf '%s' "$_rv" | sed -E 's#^[A-Za-z0-9/+=_-]{20,}#[redacted:opaque-assignment]#')
      ;;
  esac
  printf '%s' "$_rv" | sed -E \
    -e 's#-----BEGIN ([A-Z]+ )?PRIVATE KEY-----#[redacted:private-key-block]#g' \
    -e 's#(AKIA|ASIA)[0-9A-Z]{16}#[redacted:aws-access-key-id]#g' \
    -e 's#gh[pousr]_[A-Za-z0-9]{36,}#[redacted:github-token]#g' \
    -e 's#xox[abpsr]-[A-Za-z0-9-]{16,}#[redacted:slack-token]#g' \
    -e 's#sk-[A-Za-z0-9_-]{24,}#[redacted:provider-api-key]#g' \
    -e "s#(api[_-]?key|secret|token|password|passwd)['\"]?[[:blank:]]*[:=][[:blank:]]*['\"]?[A-Za-z0-9/+=_-]{20,}#[redacted:opaque-assignment]#g"
}

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# The awk parser both verbs share: parse(line, F, T) fills F[key] = value and
# T[key] = "s" | "n" and returns 1 for a well-formed flat object of string
# and number values, 0 for anything else (a nested value included).
AWK_PARSE='
function parse(line, F, T,    s, n, i, c, c2, key, val, k) {
  split("", F); split("", T)
  if (substr(line, 1, 1) != "{" || substr(line, length(line), 1) != "}") return 0
  s = substr(line, 2, length(line) - 2)
  n = length(s); i = 1; k = 0
  while (i <= n) {
    if (k > 0) { if (substr(s, i, 1) != ",") return 0; i++ }
    if (substr(s, i, 1) != "\"") return 0
    i++; key = ""
    while (i <= n && substr(s, i, 1) != "\"") {
      c = substr(s, i, 1)
      if (c == "\\") return 0
      key = key c; i++
    }
    if (i > n || key == "" || (key in F)) return 0
    i++
    if (substr(s, i, 1) != ":") return 0
    i++
    c = substr(s, i, 1)
    if (c == "\"") {
      i++; val = ""
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\\") {
          c2 = substr(s, i + 1, 1)
          if (c2 != "\"" && c2 != "\\") return 0
          val = val c2; i += 2; continue
        }
        if (c == "\"") break
        val = val c; i++
      }
      if (i > n) return 0
      i++
      F[key] = val; T[key] = "s"
    } else if (c ~ /[-0-9]/) {
      val = ""
      while (i <= n && substr(s, i, 1) ~ /[-0-9.]/) { val = val substr(s, i, 1); i++ }
      if (val !~ /^-?(0|[1-9][0-9]*)(\.[0-9]+)?$/) return 0
      F[key] = val; T[key] = "n"
    } else return 0
    k++
  }
  return k > 0
}
function header_ok(F, T) {
  if (!("v" in F) || !("seq" in F) || !("ts" in F) || !("kind" in F)) return 0
  if (T["v"] != "n" || T["seq"] != "n" || T["ts"] != "n" || T["kind"] != "s") return 0
  if (F["v"] != 1) return 0
  return 1
}
'

# ---------------------------------------------------------------------------
# Surface: verify-or-refuse, never chmod-narrowed (REQ-A1.4)
# ---------------------------------------------------------------------------

my_uid=""
check_private_dir() {
  _cd=$1
  if [ -L "$_cd" ]; then
    err "security: $(sanitize_printable "$_cd" "(unprintable path)") is a symlink — refusing to write through a redirect; investigate and remove it yourself"
    exit 4
  fi
  # shellcheck disable=SC2012
  _cl=$(ls -ldn "$_cd" 2>/dev/null) || _cl=""
  if [ -z "$_cl" ]; then
    err "the sub-surface $(sanitize_printable "$_cd" "(unprintable path)") vanished while being verified"
    exit 4
  fi
  # shellcheck disable=SC2086
  set -- $_cl
  # The group and other columns must carry no permission at all, but the
  # EXECUTE column of each also spells the setgid and sticky bits: a setgid
  # fleet home makes every mkdir under it inherit the bit, so a sub-surface
  # this script just created at 0700 lists as `drwx--S---`. Nothing widened
  # there, and refusing it would hard-fail every write with advice ("chmod
  # 700 it") that a fresh mkdir undoes.
  case "${1:-}" in
    d???--[-S]--[-T] | d???--[-S]--[-T][@.]*) ;;
    *)
      err "security: the sub-surface is not verifiably owner-only (mode ${1:-unreadable}); chmod 700 it yourself after finding out how it widened"
      exit 4
      ;;
  esac
  if [ "${3:-}" != "$my_uid" ]; then
    err "security: the sub-surface is owned by uid ${3:-?}, not this user; refusing it"
    exit 4
  fi
}

check_private_file() {
  _cf=$1
  [ -e "$_cf" ] || [ -L "$_cf" ] || return 0
  if [ -L "$_cf" ]; then
    err "security: $(sanitize_printable "$_cf" "(unprintable path)") is a symlink — refusing to write through a redirect"
    exit 4
  fi
  # shellcheck disable=SC2012
  _cl=$(ls -ln "$_cf" 2>/dev/null) || _cl=""
  # shellcheck disable=SC2086
  set -- $_cl
  case "${1:-}" in
    -???------ | -???------[@.]*) ;;
    *)
      err "security: $(sanitize_printable "$_cf" "(unprintable path)") is not owner-only (mode ${1:-unreadable}); chmod 600 it yourself after finding out how it widened"
      exit 4
      ;;
  esac
  if [ "${3:-}" != "$my_uid" ]; then
    err "security: $(sanitize_printable "$_cf" "(unprintable path)") is owned by uid ${3:-?}, not this user; refusing it"
    exit 4
  fi
}

resolve_surface() {
  home=$("$FS" root 2>/dev/null) || {
    err "cannot resolve the fleet home (fleet-state.sh root failed)"
    exit 6
  }
  my_uid=$(id -u 2>/dev/null) || {
    err "cannot resolve the current uid"
    exit 6
  }
  # fleet-state.sh owns this name; it is read here only to check the link's
  # target against the token this process holds, never to create the lock.
  LOCK_PATH="$home/.fleet.lock"
  surface="$home/tower-comms"
  log_file="$surface/events.log"
  seq_file="$surface/events.seq"
  dropped_file="$surface/events.dropped"
}

# The fleet home is fleet-state's surface, not this script's: created here
# only when absent, and otherwise verified rather than narrowed (REQ-A1.4).
# It is verified at all because the 0700 sub-surface below it is only as
# private as the directory that holds it — a home anyone but its owner can
# write to is one where the sub-surface can be moved aside and replaced
# between the checks below and the write they guard.
check_home() {
  if [ -L "$home" ]; then
    err "security: the fleet home $(sanitize_printable "$home" "(unprintable path)") is a symlink — refusing to write through a redirect"
    exit 4
  fi
  # shellcheck disable=SC2012
  _hl=$(ls -ldn "$home" 2>/dev/null) || _hl=""
  if [ -z "$_hl" ]; then
    err "the fleet home $(sanitize_printable "$home" "(unprintable path)") vanished while being verified"
    exit 4
  fi
  # shellcheck disable=SC2086
  set -- $_hl
  # Only the two WRITE columns: a home readable or traversable by others is
  # the ordinary shape (fleet-state creates it under the caller's umask), and
  # narrowing someone else's surface is not this script's call.
  case "${1:-}" in
    d????-??-? | d????-??-?[@.]*) ;;
    *)
      err "security: the fleet home is writable beyond its owner (mode ${1:-unreadable}); the private surface under it is only as private as the home, so chmod go-w it yourself after finding out how it widened"
      exit 4
      ;;
  esac
  if [ "${3:-}" != "$my_uid" ]; then
    err "security: the fleet home is owned by uid ${3:-?}, not this user; refusing it"
    exit 4
  fi
}

ensure_surface() {
  if [ ! -d "$home" ]; then
    mkdir -p "$home" 2>/dev/null || {
      err "cannot create the fleet home $(sanitize_printable "$home" "(unprintable path)")"
      exit 6
    }
    chmod 0700 "$home" 2>/dev/null || {
      err "cannot narrow the fleet home $(sanitize_printable "$home" "(unprintable path)") to 0700"
      exit 6
    }
  fi
  if [ -L "$surface" ]; then
    err "security: the sub-surface $(sanitize_printable "$surface" "(unprintable path)") is a symlink — refusing to write through a redirect"
    exit 4
  fi
  if [ ! -d "$surface" ]; then
    mkdir "$surface" 2>/dev/null || true
  fi
  if [ ! -d "$surface" ]; then
    err "cannot create the sub-surface $(sanitize_printable "$surface" "(unprintable path)")"
    exit 6
  fi
  verify_surface
}

# Every check the write path makes, in one place so it can be repeated: the
# checks below and the writes they guard are separated by the whole bounded
# lock wait, plus rotation and coalescing, so a surface tested once before the
# wait says nothing about the surface being written afterwards. Re-tested
# under the lock for the same reason fleet-presence keeps its symlink test
# adjacent to the mode read it guards.
verify_surface() {
  check_home
  check_private_dir "$surface"
  check_private_file "$log_file"
  check_private_file "$seq_file"
  check_private_file "$dropped_file"
}

# ---------------------------------------------------------------------------
# The fleet lock, bounded
# ---------------------------------------------------------------------------

HOLD_LOCK=0
LOCK_PATH=""
LOCK_TOKEN=""
LOCK_CHILD=""
PENDING_TMP=""
WORK_TMP=""
KNOB_DIR=""
# fleet-state disowns the lock its `lock` verb takes to this caller, and its
# `unlock` is an unconditional `rm -f` its own header calls out as able to
# delete a successor's lock. What closes both is the discipline try_acquire
# documents: claim ownership BEFORE anything can publish the link, and unlink
# only while the link is still ours. The claim here is the pid of the forked
# child, which is the `<pid>-<epoch>` owner token fleet-state writes, recorded
# before that child can be waited on; the check is the link's target read back.
# So a signal inside the acquire window still releases a lock this process
# took, and a lock broken as stale and retaken by a peer reads back a foreign
# target and is left standing.
release_lock() {
  [ "$HOLD_LOCK" = 1 ] || return 0
  HOLD_LOCK=0
  [ -n "$LOCK_PATH" ] || return 0
  _lt=$(readlink "$LOCK_PATH" 2>/dev/null) || _lt=""
  [ -n "$_lt" ] || return 0
  if [ "$_lt" = "$LOCK_TOKEN" ] || { [ -n "$LOCK_CHILD" ] && [ "${_lt%%-*}" = "$LOCK_CHILD" ]; }; then
    rm -f "$LOCK_PATH" 2>/dev/null || true
  fi
}
# Every scratch path this script mints is tracked, because each one is
# created inside the 0700 sub-surface: a signal between `mktemp` and the
# rename that consumes it would otherwise leave a full copy of the event log
# behind, one per interruption.
cleanup() {
  release_lock
  [ -z "$PENDING_TMP" ] || rm -f "$PENDING_TMP" 2>/dev/null || true
  [ -z "$WORK_TMP" ] || rm -f "$WORK_TMP" 2>/dev/null || true
  [ -z "$KNOB_DIR" ] || rm -rf "$KNOB_DIR" 2>/dev/null || true
}
trap 'cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# clock_s — the time as seconds with millisecond decimals when `date +%N`
# yields a real nanosecond field (GNU and BSD date both do), else whole
# seconds. A sub-second lock wait needs a sub-second deadline; on a
# whole-second clock the wait can overshoot by up to a second and says so.
clock_s() {
  _t=$(date '+%s %N' 2>/dev/null)
  case "$_t" in
    [0-9]*' '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9])
      _ns=${_t##* }
      printf '%s.%.3s\n' "${_t%% *}" "$_ns"
      ;;
    *) date +%s ;;
  esac
}

# wait_tries <seconds> — the attempt budget that stands in for the deadline
# when the clock will not answer. Each attempt costs a fork plus the sleep
# below, so a budget scaled to the sleep keeps the wait near the configured
# bound; without it the deadline comparison reads `0 >= w`, which is never
# true, and the prompt-submit hook's caller waits forever.
wait_tries() {
  awk -v w="$1" 'BEGIN {
    n = int(w / 0.02)
    if (n > 100000) n = 100000
    printf "%d\n", n + 25 }'
}

# acquire_lock <seconds> — take fleet-state's one-shot lock, retrying a busy
# holder until the wall-clock deadline (every attempt is a fork, so the bound
# is a deadline, not a try count) or, with no readable clock, until the
# attempt budget runs out. 0 held; 1 the wait expired; 2 a real error.
acquire_lock() {
  _deadline=$(clock_s)
  if [ -n "$_deadline" ]; then
    _deadline=$(awk -v s="$_deadline" -v w="$1" 'BEGIN { printf "%.3f\n", s + w }')
    _tries=0
  else
    _tries=$(wait_tries "$1")
  fi
  while :; do
    # Forked rather than run in the foreground so the pid inside the owner
    # token is this process's knowledge BEFORE the child can publish the link.
    LOCK_TOKEN=""
    "$FS" lock >/dev/null 2>&1 &
    LOCK_CHILD=$!
    HOLD_LOCK=1
    wait "$LOCK_CHILD"
    _rc=$?
    case $_rc in
      0)
        LOCK_TOKEN=$(readlink "$LOCK_PATH" 2>/dev/null) || LOCK_TOKEN=""
        return 0
        ;;
      1) HOLD_LOCK=0 ;;
      *)
        HOLD_LOCK=0
        err "cannot acquire the fleet lock (fleet-state exit $_rc)"
        return 2
        ;;
    esac
    if [ -n "$_deadline" ]; then
      _cnow=$(clock_s)
      if [ -z "$_cnow" ]; then
        _deadline=""
        _tries=$(wait_tries "$1")
      elif awk -v now="$_cnow" -v dl="$_deadline" 'BEGIN { exit (now >= dl) ? 0 : 1 }'; then
        return 1
      fi
    fi
    if [ -z "$_deadline" ]; then
      _tries=$((_tries - 1))
      [ "$_tries" -gt 0 ] || return 1
    fi
    sleep 0.02
  done
}

# read_counter <file> — the integer at <file>, or 0 when absent or malformed
# (a leading zero included: this script only writes canonical decimals).
read_counter() {
  _cv=$(cat "$1" 2>/dev/null) || _cv=""
  case $_cv in
    "" | *[!0-9]* | 0?*) printf '0\n' ;;
    *) printf '%s\n' "$_cv" ;;
  esac
}

# last_logged_seq — the highest sequence carried by the log's own last lines,
# or 0. The counter file is a cache of this: every line records the sequence
# it was given, so a counter that went missing or malformed is recoverable
# rather than a reason to restart at 1 against a log holding higher values,
# which is how two lines end up sharing one number. The tail is the window
# that matters, the log being append-ordered.
last_logged_seq() {
  [ -s "$log_file" ] || {
    printf '0\n'
    return 0
  }
  tail -n 20 "$log_file" 2>/dev/null | awk "$AWK_PARSE"'
    { if (!parse($0, F, T) || !header_ok(F, T)) next
      s = F["seq"] + 0
      if (s > m) m = s }
    END { printf "%d\n", m + 0 }'
}

# write_counter <n> — the counter, replaced through a same-dir temp. 0 written,
# 1 the surface refused it.
write_counter() {
  PENDING_TMP=$(mktemp "$surface/.seq.XXXXXX" 2>/dev/null) || return 1
  printf '%s\n' "$1" >"$PENDING_TMP" 2>/dev/null || return 1
  mv -f "$PENDING_TMP" "$seq_file" 2>/dev/null || return 1
  PENDING_TMP=""
  return 0
}

# rewrite_log — replace the log's contents with the file at $1 via a
# same-dir temp and rename, so a lock-free reader never sees a torn file.
rewrite_log() {
  PENDING_TMP=$(mktemp "$surface/.events.XXXXXX" 2>/dev/null) || return 1
  cat "$1" >"$PENDING_TMP" 2>/dev/null || return 1
  mv -f "$PENDING_TMP" "$log_file" 2>/dev/null || return 1
  PENDING_TMP=""
  return 0
}

# ---------------------------------------------------------------------------
# log
# ---------------------------------------------------------------------------

cmd_log() {
  [ "$#" -ge 1 ] || usage
  kind=$1
  shift
  found=0
  for _k in $KINDS; do
    [ "$kind" != "$_k" ] || found=1
  done
  if [ "$found" -ne 1 ]; then
    err "unknown event kind '$(sanitize_printable "$kind" "(unprintable kind)")'"
    exit 2
  fi
  tower=""
  now=""
  now_set=0
  payload=""
  keys=""
  live=""
  event=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tower)
        [ "$#" -ge 2 ] || usage
        tower=$2
        shift 2
        ;;
      --now)
        [ "$#" -ge 2 ] || usage
        now=$2
        now_set=1
        shift 2
        ;;
      --*)
        usage
        ;;
      *=*)
        key=${1%%=*}
        val=${1#*=}
        shift
        if ! is_key "$key"; then
          err "refusing field '$(sanitize_printable "$key" "(unprintable key)")': keys match ^[a-z][a-z0-9_]{0,31}\$ and are none of: $RESERVED"
          exit 2
        fi
        for _k in $keys; do
          if [ "$_k" = "$key" ]; then
            err "refusing field '$key': given twice"
            exit 2
          fi
        done
        if [ "${#val}" -gt 4096 ]; then
          err "refusing field '$key': value longer than 4096 bytes"
          exit 2
        fi
        if [ "$(printf '%s' "$val" | tr -d '\000-\037\177')" != "$val" ]; then
          err "refusing field '$key': the value carries a control byte (flatten the text first)"
          exit 2
        fi
        case "$val" in
          '{'*'}' | '['*']')
            err "refusing field '$key': a nested JSON value; the log holds strings and numbers only"
            exit 2
            ;;
        esac
        keys="$keys $key"
        [ "$key" != live ] || live=$val
        [ "$key" != event ] || event=$val
        if is_number "$val"; then
          payload="$payload,\"$key\":$val"
        else
          payload="$payload,\"$key\":\"$(json_escape "$(redact "$val" "$key")")\""
        fi
        ;;
      *)
        err "refusing argument '$(sanitize_printable "$1" "(unprintable argument)")': expected <key>=<value>"
        exit 2
        ;;
    esac
  done
  if [ -n "$tower" ] && ! is_tower "$tower"; then
    err "refusing tower identity '$(sanitize_printable "$tower" "(unprintable identity)")'"
    exit 2
  fi
  for _k in $TOWER_KINDS; do
    if [ "$kind" = "$_k" ] && [ -z "$tower" ]; then
      err "a '$kind' event needs --tower <id>: every $_k line carries the writing tower's identity"
      exit 2
    fi
  done
  if [ "$kind" = tick ] && ! is_count "$live"; then
    err "a tick needs live=<n>, the live-worker count as a non-negative integer"
    exit 2
  fi
  if [ "$kind" = session ]; then
    case "$event" in
      start | rebuild) ;;
      *)
        err "a session event needs event=start or event=rebuild"
        exit 2
        ;;
    esac
  fi
  # `[ -n "$now" ]` here would make `--now ""` a silent no-op, which reads as
  # the caller's own timestamp being honoured when it was in fact discarded.
  if [ "$now_set" = 1 ]; then
    if ! is_epoch "$now"; then
      err "refusing --now '$(sanitize_printable "$now" "(unprintable epoch)")': an epoch is a canonical positive integer"
      exit 2
    fi
  else
    now=$(date +%s 2>/dev/null) || now=""
    is_epoch "$now" || {
      err "cannot read the clock (date +%s failed)"
      exit 6
    }
  fi

  lock_wait=""
  gap_max=""
  rotate_age=""
  window=""
  resolve_log_knobs

  resolve_surface
  umask 077
  ensure_surface

  acquire_lock "$lock_wait"
  case $? in
    0) ;;
    1)
      err "the fleet lock stayed busy for the whole tower_hook_lock_wait; dropping this '$kind' line rather than writing unlocked (counted in events.dropped)"
      (printf '%s\t%s\n' "$now" "$kind") 2>/dev/null >>"$dropped_file" \
        || err "the dropped line could not be counted either: events.dropped would not take it"
      exit 3
      ;;
    *) exit 6 ;;
  esac

  # Under the lock now, so the surface is re-verified adjacent to the writes
  # that follow rather than trusted from before the wait.
  verify_surface

  # Rotation removes only what it can positively judge as old: a line this
  # script parses, whose header it reads, carrying a timestamp behind the
  # cutoff. Everything else stays. A line it cannot parse is the only evidence
  # that a write tore, and report's `malformed` count is what carries that
  # evidence to the operator; a line carrying a schema version this script does
  # not know belongs to another writer, and deleting it is how two writers
  # sharing a fleet home would destroy each other's history.
  #
  # Judged on the first JUDGEABLE line: the log is append-ordered, so when the
  # oldest line it can read is inside the cutoff nothing older can follow.
  if [ -s "$log_file" ]; then
    cutoff=$(awk -v now="$now" -v a="$rotate_age" -v w="$window" 'BEGIN { f = (a > w) ? a : w; printf "%.3f\n", now - f }')
    needs=$(awk -v cutoff="$cutoff" "$AWK_PARSE"'
      { if (!parse($0, F, T) || !header_ok(F, T)) next
        t = F["ts"] + 0
        if (F["kind"] == "tick" && ("until" in F)) t = F["until"] + 0
        print (t < cutoff) ? "yes" : "no"; exit }' "$log_file") || needs=no
    if [ "$needs" = yes ]; then
      rot_tmp=$(mktemp "$surface/.rotate.XXXXXX" 2>/dev/null) || {
        err "cannot create a scratch file for rotation"
        exit 6
      }
      WORK_TMP=$rot_tmp
      awk -v cutoff="$cutoff" "$AWK_PARSE"'
        { if (!parse($0, F, T) || !header_ok(F, T)) { print; next }
          t = F["ts"] + 0
          if (F["kind"] == "tick" && ("until" in F)) t = F["until"] + 0
          if (t >= cutoff) print }' "$log_file" >"$rot_tmp" 2>/dev/null || {
        err "rotation failed while filtering the log"
        exit 6
      }
      # A filter that keeps nothing is the signature of a clock that stepped
      # forward, not of a log that is entirely stale: one future-stamped write
      # puts the cutoff past every real line at once. Refuse it. The genuinely
      # idle case costs one write of delay — this write's own line lands, and
      # the next rotation then keeps it and removes the rest — while a clock
      # step costs nothing at all.
      if [ ! -s "$rot_tmp" ]; then
        err "refusing a rotation that would empty the event log; the cutoff is past every line, which is a stepped clock more often than a wholly stale log"
      else
        rewrite_log "$rot_tmp" || {
          err "rotation failed while replacing the log"
          exit 6
        }
      fi
      rm -f "$rot_tmp"
      WORK_TMP=""
    fi
  fi

  # A tick coalesces with the last line when that is this tower's tick at the
  # same count and the stretch since its `until` is within the gap bound.
  if [ "$kind" = tick ] && [ -s "$log_file" ]; then
    last=$(tail -n 1 "$log_file")
    merged=$(printf '%s\n' "$last" | awk -v tower="$tower" -v live="$live" -v now="$now" -v gap="$gap_max" "$AWK_PARSE"'
      { if (!parse($0, F, T) || !header_ok(F, T)) exit
        if (F["kind"] != "tick" || F["tower"] != tower || (F["live"] + 0) != (live + 0)) exit
        u = ("until" in F) ? F["until"] + 0 : F["ts"] + 0
        if (now < u || now - u > gap) exit
        sub(/,"until":[-0-9.]+}$/, "", $0)
        sub(/}$/, "", $0)
        print $0 ",\"until\":" now "}" }')
    if [ -n "$merged" ]; then
      co_tmp=$(mktemp "$surface/.coalesce.XXXXXX" 2>/dev/null) || {
        err "cannot create a scratch file for the tick"
        exit 6
      }
      WORK_TMP=$co_tmp
      {
        # Everything but the last record. A line count would disagree with
        # `tail -n 1` above whenever the final line is unterminated — the
        # count sees terminated lines, tail sees records — and the rewrite
        # would then drop a good line along with the one it means to replace.
        awk 'NR > 1 { print prev } { prev = $0 }' "$log_file"
        printf '%s\n' "$merged"
      } >"$co_tmp" 2>/dev/null || {
        err "coalescing failed while rewriting the log"
        exit 6
      }
      rewrite_log "$co_tmp" || {
        err "coalescing failed while replacing the log"
        exit 6
      }
      rm -f "$co_tmp"
      WORK_TMP=""
      exit 0
    fi
  fi

  seq=$(read_counter "$seq_file")
  logged=$(last_logged_seq)
  case $logged in
    "" | *[!0-9]*) logged=0 ;;
  esac
  if [ "$logged" -gt "$seq" ]; then
    err "the sequence counter is behind the event log (counter $seq, log $logged); continuing from the log's own last sequence"
    seq=$logged
  fi
  seq=$((seq + 1))

  line="{\"v\":$SCHEMA,\"seq\":$seq,\"ts\":$now,\"kind\":\"$kind\""
  # The identity is a string value like any other: its grammar admits
  # exactly the shape of an access key id or an opaque bearer token, and the
  # header promises every string value is screened whatever the kind.
  [ -z "$tower" ] || line="$line,\"tower\":\"$(json_escape "$(redact "$tower")")\""
  line="$line$payload"
  [ "$kind" != tick ] || line="$line,\"until\":$now"
  line="$line}"
  # A final line left unterminated by an earlier torn write has no newline to
  # end it, so a bare append lands INSIDE it and one tear costs two events.
  # Close the tear first: the torn line stays whole enough for report to count
  # it as malformed, and this line lands on its own.
  torn=0
  if [ -s "$log_file" ] && [ -n "$(tail -c 1 "$log_file" 2>/dev/null)" ]; then
    torn=1
    err "the event log's last line is unterminated (a torn write); closing it so this line lands whole"
  fi
  # The subshell keeps a failed redirect's raw shell diagnostic (which names
  # a line number and a bare path) off stderr: what reaches the operator is
  # this script's own sanitized line and nothing else. The stderr redirect
  # comes FIRST — redirections apply left to right, and a failing append
  # reports itself against whatever stderr is at that moment.
  (
    [ "$torn" = 0 ] || printf '\n'
    printf '%s\n' "$line"
  ) 2>/dev/null >>"$log_file" || {
    err "cannot append to the event log"
    exit 6
  }
  # After the line it numbers, never before: a counter bumped first burns a
  # sequence number on an append that then fails, and the hole that leaves is
  # indistinguishable from a rotated-away line, which is the one thing the
  # sequence exists to tell apart. A counter that does not land is repaired by
  # the next write, which reads the log.
  write_counter "$seq" \
    || err "the line landed but the sequence counter did not; the next write repairs it from the log"
  exit 0
}

# ---------------------------------------------------------------------------
# report
# ---------------------------------------------------------------------------

cmd_report() {
  log_path=""
  now=""
  now_set=0
  window_arg=""
  gap_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --log)
        [ "$#" -ge 2 ] || usage
        log_path=$2
        shift 2
        ;;
      --now)
        [ "$#" -ge 2 ] || usage
        now=$2
        now_set=1
        shift 2
        ;;
      --window)
        [ "$#" -ge 2 ] || usage
        window_arg=$2
        shift 2
        ;;
      --tick-gap-max)
        [ "$#" -ge 2 ] || usage
        gap_arg=$2
        shift 2
        ;;
      *) usage ;;
    esac
  done
  if [ "$now_set" = 1 ]; then
    is_epoch "$now" || {
      err "refusing --now '$(sanitize_printable "$now" "(unprintable epoch)")': an epoch is a canonical positive integer"
      exit 2
    }
  else
    # Checked exactly as `log` checks it: an unread clock here prints a
    # window ending at the epoch and a fleet_hours of zero, which is
    # indistinguishable from a genuinely idle fleet.
    now=$(date +%s 2>/dev/null) || now=""
    is_epoch "$now" || {
      err "cannot read the clock (date +%s failed)"
      exit 6
    }
  fi
  if [ -n "$window_arg" ]; then
    is_duration "$window_arg" || {
      err "refusing --window '$(sanitize_printable "$window_arg" "(unprintable duration)")': a positive span such as 90m, 2h or 7d"
      exit 2
    }
    window=$(duration_seconds "$window_arg")
  else
    window=$(knob tower_report_window 7d) || exit $?
  fi
  if [ -n "$gap_arg" ]; then
    is_duration "$gap_arg" || {
      err "refusing --tick-gap-max '$(sanitize_printable "$gap_arg" "(unprintable duration)")': a positive span such as 10m"
      exit 2
    }
    gap_max=$(duration_seconds "$gap_arg")
  else
    gap_max=$(knob tower_tick_gap_max 10m) || exit $?
  fi
  if [ -z "$log_path" ]; then
    resolve_surface
    # The verify-or-refuse gate is the read path's too (REQ-A1.4). A
    # redirected or foreign-owned log feeds the scorecard whatever it points
    # at, and a fabricated scorecard printed at exit 0 reads exactly like a
    # real one. `--log` stays unverified: it is the fixture and test hatch,
    # and its path came from the caller rather than from the fleet home.
    if [ -d "$surface" ] || [ -L "$surface" ]; then
      check_home
      check_private_dir "$surface"
      check_private_file "$log_file"
    fi
    log_path=$log_file
  fi
  if [ ! -f "$log_path" ] || [ ! -r "$log_path" ]; then
    err "no event log to read at $(sanitize_printable "$log_path" "(unprintable path)")"
    exit 1
  fi
  [ -r "$JARGON" ] || {
    err "the jargon word list $JARGON is missing — broken install"
    exit 5
  }

  awk -v now="$now" -v window="$window" -v gap_max="$gap_max" -v jargon_file="$JARGON" -v q="'" "$AWK_PARSE"'
  function norm_text(s) {
    s = tolower(s)
    gsub(/[^a-z0-9]+/, " ", s)
    sub(/^ /, "", s); sub(/ $/, "", s)
    return s
  }
  function count_phrase(hay, needle,    c, p, rest) {
    c = 0; rest = hay
    while ((p = index(rest, needle)) > 0) { c++; rest = substr(rest, p + length(needle)) }
    return c
  }
  function strip_punct(t) {
    sub(/[.,;:!?)]+$/, "", t); sub(/^[("]+/, "", t)
    return t
  }
  function jargon(text,    padded, i, ntok, tok, t) {
    padded = " " norm_text(text) " "
    for (i = 1; i <= nterms; i++) terms_hit += count_phrase(padded, " " terms[i] " ")
    t = text
    gsub(/[^A-Za-z0-9.:_\/-]+/, " ", t)
    ntok = split(t, tok, " ")
    for (i = 1; i <= ntok; i++) {
      w = strip_punct(tok[i])
      if (w ~ /^REQ-[A-Z]+[0-9]+(\.[0-9]+)?$/ || w ~ /^D-[0-9]+$/ || w ~ /^obs:[0-9a-f]+$/) ident_hit++
      else if (w ~ /^[a-z0-9]+([._-][a-z0-9]+)*\.(sh|md|yml|yaml|json|txt|toml)$/ || w ~ /^[a-z][a-z0-9]*(_[a-z0-9]+)+$/) internal_hit++
    }
  }
  BEGIN {
    nterms = 0
    while ((getline l < jargon_file) > 0) {
      sub(/#.*/, "", l)
      l = norm_text(l)
      if (l != "") terms[++nterms] = l
    }
    close(jargon_file)
    re_what = "[^a-z]what(" q "s| is| are| does| do)[^a-z]"
    ws = now - window; we = now + 0
    lines = 0; malformed = 0; nticks = 0; nint = 0
    delivered_prose = 0; multi_ask = 0; friction_meaning = 0; friction_repeat = 0
    terms_hit = 0; ident_hit = 0; internal_hit = 0; lost = 0
  }
  {
    if (!parse($0, F, T) || !header_ok(F, T)) { malformed++; next }
    kind = F["kind"]; ts = F["ts"] + 0
    inwin = (ts >= ws)
    if (kind == "tick") {
      u = ("until" in F) ? F["until"] + 0 : ts
      if (u >= ws) inwin = 1
    }
    if (!inwin) next
    lines++
    if ("tower" in F) towers[F["tower"]] = 1
    if (kind == "tick") {
      if (!("live" in F) || T["live"] != "n") next
      nticks++
      tk_tower[nticks] = ("tower" in F) ? F["tower"] : ""
      tk_ts[nticks] = ts
      tk_until[nticks] = ("until" in F) ? F["until"] + 0 : ts
      tk_live[nticks] = F["live"] + 0
    } else if (kind == "delivered") {
      if ("item" in F) delivered_items[F["item"]] = 1
      else delivered_prose++
      if (("asks" in F) && (F["asks"] + 0) > 1) multi_ask++
      if ("text" in F) jargon(F["text"])
    } else if (kind == "settled") {
      if ("item" in F) settled_items[F["item"]] = 1
    } else if (kind == "born") {
      if (("item" in F) && ("item_kind" in F) && F["item_kind"] == "question" && !(F["item"] in born_ts)) born_ts[F["item"]] = ts
    } else if (kind == "acknowledged") {
      if (("item" in F) && !(F["item"] in ack_ts)) ack_ts[F["item"]] = ts
    } else if (kind == "reply") {
      if ("text" in F) {
        low = " " tolower(F["text"]) " "
        if (low ~ re_what || low ~ /[^a-z]mean(s|ing)?[^a-z]/) friction_meaning++
        nt = norm_text(F["text"])
        if (split(nt, dummy, " ") >= 3) { if (nt in seen_reply) friction_repeat++; seen_reply[nt] = 1 }
      }
    } else if (kind == "dropped") {
      if (("reason" in F) && F["reason"] == "rebuild") lost++
    }
  }
  function add_interval(a, b) {
    if (a < ws) a = ws
    if (b > we) b = we
    if (b <= a) return
    nint++; ia[nint] = a; ib[nint] = b
  }
  END {
    # Per tower: order its ticks by ts, count live spans and bridged stretches.
    gaps = 0; gap_seconds = 0
    for (i = 1; i <= nticks; i++) if (!(tk_tower[i] in tick_towers)) tick_towers[tk_tower[i]] = 1
    for (tw in tick_towers) {
      m = 0
      for (i = 1; i <= nticks; i++) if (tk_tower[i] == tw) {
        # insertion by ts
        j = m
        while (j >= 1 && tk_ts[ord[j]] > tk_ts[i]) { ord[j + 1] = ord[j]; j-- }
        ord[j + 1] = i; m++
      }
      for (j = 1; j <= m; j++) {
        i = ord[j]
        if (tk_live[i] > 0) add_interval(tk_ts[i], tk_until[i])
        if (j < m) {
          nx = ord[j + 1]
          stretch = tk_ts[nx] - tk_until[i]
          if (stretch > gap_max) { gaps++; gap_seconds += stretch }
          else if (stretch > 0 && tk_live[i] > 0) add_interval(tk_until[i], tk_ts[nx])
        }
      }
      split("", ord)
    }
    # Union of the intervals, sorted by start.
    for (i = 1; i <= nint; i++) sidx[i] = i
    for (i = 2; i <= nint; i++) { v = sidx[i]; j = i - 1; while (j >= 1 && ia[sidx[j]] > ia[v]) { sidx[j + 1] = sidx[j]; j-- } sidx[j + 1] = v }
    total = 0; cur_a = 0; cur_b = -1; have = 0
    for (k = 1; k <= nint; k++) {
      i = sidx[k]
      if (!have) { cur_a = ia[i]; cur_b = ib[i]; have = 1; continue }
      if (ia[i] <= cur_b) { if (ib[i] > cur_b) cur_b = ib[i] }
      else { total += cur_b - cur_a; cur_a = ia[i]; cur_b = ib[i] }
    }
    if (have) total += cur_b - cur_a
    hours = total / 3600
    ndel = delivered_prose; for (x in delivered_items) ndel++
    nset = 0; for (x in settled_items) nset++
    wait_total = 0; wait_max = 0; wait_open = 0
    for (x in born_ts) {
      if ((x in ack_ts) && ack_ts[x] >= born_ts[x]) w = ack_ts[x] - born_ts[x]
      else { w = we - born_ts[x]; wait_open++ }
      if (w < 0) w = 0
      wait_total += w; if (w > wait_max) wait_max = w
    }
    ntow = 0; for (x in towers) ntow++
    printf "window_start\t%d\n", ws
    printf "window_end\t%d\n", we
    printf "lines\t%d\n", lines
    printf "malformed\t%d\n", malformed
    printf "towers\t%d\n", ntow
    printf "fleet_hours\t%.2f\n", hours
    printf "tick_gaps\t%d\n", gaps
    printf "tick_gap_seconds\t%d\n", gap_seconds
    printf "delivered_items\t%d\n", ndel
    if (hours > 0) printf "delivered_per_fleet_hour\t%.2f\n", ndel / hours; else print "delivered_per_fleet_hour\tn/a"
    printf "settled_items\t%d\n", nset
    if (hours > 0) printf "settled_per_fleet_hour\t%.2f\n", nset / hours; else print "settled_per_fleet_hour\tn/a"
    printf "blocked_wait_seconds\t%d\n", wait_total
    printf "blocked_wait_max_seconds\t%d\n", wait_max
    printf "blocked_open\t%d\n", wait_open
    printf "multi_ask_turns\t%d\n", multi_ask
    printf "prose_deliveries\t%d\n", delivered_prose
    printf "friction_meaning\t%d\n", friction_meaning
    printf "friction_repeat\t%d\n", friction_repeat
    printf "jargon_identifiers\t%d\n", ident_hit
    printf "jargon_internal\t%d\n", internal_hit
    printf "jargon_terms\t%d\n", terms_hit
    printf "lost_across_restart\t%d\n", lost
  }' "$log_path"
}

cmd=${1:-}
[ -n "$cmd" ] || usage
shift
case "$cmd" in
  log) cmd_log "$@" ;;
  report) cmd_report "$@" ;;
  *)
    err "unknown command '$(sanitize_printable "$cmd" "(unprintable command)")' (log | report)"
    exit 2
    ;;
esac
