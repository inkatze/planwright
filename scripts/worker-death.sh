#!/bin/sh
# worker-death.sh — how did a supervised Claude worker's run end? A worker
# killed by an API error still finishes the protocol (a result frame, a zero
# exit), so neither the exit code nor the result subtype says it died: the
# error signal and the error text do. This reads them from a stream-json event
# stream or a headless one-shot's `result.json`, and for a rate-limit death
# records the hold and engages the dispatch throttle. docs/quota.md describes
# the hold and the throttle this feeds; the completion readers
# (scripts/fleet-streamjson.sh, scripts/fleet-dispatch-headless.sh,
# scripts/fleet-stuck-detector.sh) are the callers.
#
# Usage:
#   worker-death.sh classify (--events <file> | --result-json <file>) [--now <epoch>]
#   worker-death.sh record --unit <unit> (--events <file> | --result-json <file>)
#       [--now <epoch>]
#     --events       a stream-json capture; only its last turn is read (the
#                    lines after the result frame before the final one, or
#                    after the final one when the run ended without one)
#     --result-json  a headless `--output-format json` result
#     --now          the clock for the reset-time check, in epoch seconds
#     --unit         the held unit: the fleet-state field grammar
#
# The error signal is a result frame flagging `"is_error":true`, or, in an event
# stream, the synthetic assistant frame Claude Code writes for an API error
# (model `<synthetic>` with an `error` key). A turn that ends with a result
# frame is read by that frame alone: an unflagged one is clean, whatever error
# the turn met and recovered from. Only those lines are the error
# text: a tool result quoting a refusal is the worker's content, not its death.
#
# Prints one tab-separated line:
#   clean                                     no error signal
#   failed<TAB><cause>                        an error that is not a limit
#   limited<TAB>claude<TAB><recognizer><TAB><reset|->
# The error text is matched against the `claude` adapter's recognizers by
# scripts/classify-limit.sh. <cause> names the error, first found of: the API
# status (`api-error-529`), the error kind a synthetic frame carries, the
# result's terminal reason or subtype, else `is-error`; one token of [a-z0-9-],
# at most 24 bytes, so a reader's bounded detail never cuts it.
#
# `record` prints the same line, and for `limited` first appends the refusal
# to the claude ledger, then holds <unit> at step `worker`
# (scripts/quota-hold.sh, which pushes the attention event), then engages the
# throttle: `fleet-throttle.sh engage --until <reset>` with a stated reset
# time, else `observe` over the recognizer id and the error text, so its own
# parse or its degraded default sets the hold.
#
# Exit: 0 classified (and, for record, every act done) · 2 usage · 3 record
# only: classified and printed, but an act failed (named on stderr) · 6 a
# runtime failure (unreadable input, no scratch space, a classifier failure).
#
# POSIX sh + awk; bash 3.2 / BSD tooling floor. No eval; every read value is
# data.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
umask 077

prog=worker-death
TAB=$(printf '\t')

usage() {
  printf '%s\n' "usage: worker-death.sh classify (--events <file> | --result-json <file>) [--now <epoch>]" \
    "       worker-death.sh record --unit <unit> (--events <file> | --result-json <file>) [--now <epoch>]" >&2
  exit 2
}
die() {
  printf '%s: %s\n' "$prog" "$2" >&2
  exit "$1"
}
warn() {
  printf '%s: warning: %s\n' "$prog" "$1" >&2
}

[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
  classify | record) ;;
  *) usage ;;
esac

src_kind=""
src=""
unit=""
unit_set=0
now=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case $1 in
    --events | --result-json)
      [ -z "$src_kind" ] || usage
      src_kind=${1#--}
      src=$2
      ;;
    --unit)
      [ "$verb" = record ] || usage
      unit=$2
      unit_set=1
      ;;
    --now) now=$2 ;;
    *) usage ;;
  esac
  shift 2
done
[ -n "$src_kind" ] || usage
[ -n "$src" ] || die 2 "the input path is empty"
if [ "$verb" = record ]; then
  [ "$unit_set" = 1 ] || usage
  case $unit in
    "" | . | .. | *[!A-Za-z0-9._=@:-]*) die 2 "--unit is outside the fleet-state field grammar" ;;
  esac
  [ "${#unit}" -le 128 ] || die 2 "--unit is outside the fleet-state field grammar"
fi
if [ -n "$now" ]; then
  case $now in *[!0-9]*) die 2 "--now is not epoch seconds" ;; esac
  [ "${#now}" -le 15 ] || die 2 "--now is not epoch seconds"
fi

[ -f "$src" ] && [ -r "$src" ] || die 6 "the input is not a readable file"

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 6
work=$(mktemp -d "${TMPDIR:-/tmp}/worker-death.XXXXXX") || die 6 "cannot create a temporary directory"
trap 'rm -rf "$work"' EXIT
trap 'exit 6' HUP INT TERM

# A headless result is one JSON object whose flag comes early, so it is read
# from the start; an event stream's last turn is at its end, and the tail bound
# keeps a long capture's read cheap, a line it cuts being the oldest. Read and
# sanitize are separate steps so a failed read is never classified.
if [ "$src_kind" = result-json ]; then
  head -c 16777216 "$src" >"$work/raw" 2>/dev/null || die 6 "cannot read the input"
else
  tail -c 4194304 "$src" >"$work/raw" 2>/dev/null || die 6 "cannot read the input"
fi
tr -d '\000' <"$work/raw" >"$work/in" || die 6 "cannot read the input"

# Writes the error lines to err, the human-readable error text to text, and
# prints the cause token, or nothing when there is no error signal.
WD_ERR="$work/err" WD_TEXT="$work/text" awk -v kind="$src_kind" '
  BEGIN { errf = ENVIRON["WD_ERR"]; textf = ENVIRON["WD_TEXT"] }
  function is_result(s) { return index(s, "\"type\":\"result\"") > 0 }
  # JSON allows blanks around the colon; Claude Code writes none.
  function flagged(s) { return s ~ /"is_error"[ \t]*:[ \t]*true/ }
  function is_err_line(s) {
    if (is_result(s)) return flagged(s)
    return index(s, "\"type\":\"assistant\"") && index(s, "\"model\":\"<synthetic>\"") && index(s, "\"error\":\"")
  }
  # str_after <s> <key>: the JSON string value after "<key>":", unescaped
  # enough to read, cut to 400 bytes; "" when the key is absent.
  function str_after(s, key,   i, rest, out, j, c) {
    i = index(s, "\"" key "\":\"")
    if (i == 0) return ""
    rest = substr(s, i + length(key) + 4)
    out = ""
    for (j = 1; j <= length(rest) && length(out) < 400; j++) {
      c = substr(rest, j, 1)
      if (c == "\\") { j++; c = substr(rest, j, 1); if (c == "n" || c == "t" || c == "r") c = " "; out = out c; continue }
      if (c == "\"") break
      out = out c
    }
    return out
  }
  function token(s) {
    s = tolower(s)
    gsub(/_/, "-", s)
    gsub(/[^a-z0-9-]/, "", s)
    return substr(s, 1, 24)
  }
  { line[++n] = $0 }
  END {
    last = n
    while (last > 0 && line[last] !~ /}[ \t\r]*$/) last--
    start = 1
    if (kind == "events") {
      r1 = 0; r0 = 0
      for (i = 1; i <= last; i++) if (is_result(line[i])) { r0 = r1; r1 = i }
      start = (r1 == last) ? r0 + 1 : r1 + 1
      if (r1 == last && last > 0 && !flagged(line[last])) exit 0
    }
    ne = 0
    for (i = start; i <= last; i++) {
      if (kind == "events" && !is_err_line(line[i])) continue
      if (kind == "result-json" && !flagged(line[i])) continue
      el[++ne] = line[i]
    }
    if (kind == "result-json" && ne > 0) {
      ne = 0
      for (i = 1; i <= last; i++) el[++ne] = line[i]
    }
    if (ne == 0) exit 0
    cause = ""
    for (i = 1; i <= ne && cause == ""; i++) {
      if ((p = index(el[i], "\"api_error_status\":")) > 0) {
        rest = substr(el[i], p + 19)
        if (match(rest, /^[0-9]+/)) cause = "api-error-" substr(rest, 1, RLENGTH)
      }
    }
    for (i = 1; i <= ne && cause == ""; i++) {
      if ((p = index(el[i], "API Error: ")) > 0) {
        rest = substr(el[i], p + 11)
        if (match(rest, /^[0-9]+/)) cause = "api-error-" substr(rest, 1, RLENGTH)
      }
    }
    for (i = 1; i <= ne && cause == ""; i++)
      if (!is_result(el[i]) && (k = token(str_after(el[i], "error"))) != "") cause = "api-error-" k
    for (i = 1; i <= ne && cause == ""; i++)
      if ((k = token(str_after(el[i], "terminal_reason"))) != "" && k != "completed") cause = k
    for (i = 1; i <= ne && cause == ""; i++)
      if ((k = token(str_after(el[i], "subtype"))) != "" && k != "success") cause = k
    if (cause == "") cause = "is-error"
    for (i = 1; i <= ne; i++) {
      print el[i] > errf
      if ((t = str_after(el[i], "result")) != "") print t > textf
      if ((t = str_after(el[i], "text")) != "") print t > textf
    }
    print substr(cause, 1, 24)
  }
' "$work/in" >"$work/cause" || die 6 "cannot read the error signal"
cause=$(cat "$work/cause")

if [ -z "$cause" ]; then
  printf 'clean\n'
  exit 0
fi

rc=0
if [ -n "$now" ]; then
  /bin/sh "$script_dir/classify-limit.sh" --vendor claude --input "$work/err" --now "$now" >"$work/limit" 2>"$work/limit.err" || rc=$?
else
  /bin/sh "$script_dir/classify-limit.sh" --vendor claude --input "$work/err" >"$work/limit" 2>"$work/limit.err" || rc=$?
fi
case $rc in
  0) ;;
  1)
    printf 'failed\t%s\n' "$cause"
    exit 0
    ;;
  *)
    # An unclassifiable death is still a death: name what is known rather than
    # guess either way about the limit.
    tr -d '\000-\011\013-\037\177' <"$work/limit.err" >&2
    printf 'failed\t%s\n' "$cause"
    die 6 "the limit classifier failed (exit $rc)"
    ;;
esac

recognizer=$(sed -n "s/^recognizer$TAB//p" "$work/limit")
reset=$(sed -n "s/^reset$TAB//p" "$work/limit")
excerpt=$(sed -n "s/^excerpt$TAB//p" "$work/limit" | tr '\n' ' ')
printf 'limited\tclaude\t%s\t%s\n' "$recognizer" "${reset:--}"
[ "$verb" = record ] || exit 0

[ -n "$excerpt" ] || excerpt="worker ended on a claude limit ($recognizer)"
QH="$script_dir/quota-hold.sh"
set -- --vendor claude --unit "$unit" --recognizer "$recognizer" --reason "$excerpt"
[ -z "$now" ] || set -- "$@" --now "$now"
act=0
/bin/sh "$QH" record --event refusal "$@" >/dev/null || {
  warn "the claude ledger did not record the refusal"
  act=3
}
[ -z "$reset" ] || set -- "$@" --reset "$reset"
/bin/sh "$QH" hold --step worker "$@" >/dev/null || {
  warn "the claude hold for $unit was not recorded in full"
  act=3
}

FT="$script_dir/fleet-throttle.sh"
if [ -n "$reset" ]; then
  /bin/sh "$FT" engage --until "$reset" --trigger "worker limited ($recognizer)" >/dev/null || {
    warn "the throttle did not engage until $reset"
    act=3
  }
else
  # The step-record screen bounds the worker-authored text before the
  # throttle's audit trigger can carry any of it.
  /bin/sh "$script_dir/step-record.sh" excerpt "$work/text" >"$work/screened" 2>/dev/null || : >"$work/screened"
  t_rc=0
  {
    printf '%s\n' "$recognizer"
    cat "$work/screened"
  } | /bin/sh "$FT" observe >/dev/null || t_rc=$?
  [ "$t_rc" = 0 ] || {
    warn "the throttle did not engage from the error text (exit $t_rc)"
    act=3
  }
fi
exit "$act"
