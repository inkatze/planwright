#!/bin/sh
# tower-reply-hook.sh — the UserPromptSubmit hook that turns an operator reply
# into the two records the operator queue reads (tower-comms D-6, D-14;
# REQ-C1.10, REQ-G1.6, REQ-G1.8, REQ-H1.4).
#
# WHAT IT WRITES, IN ORDER.
#   1. The attention marker: <fleet-home>/tower-comms/attention/<tower-id>, one
#      line holding the epoch of this reply (millisecond decimals when the
#      clock has them), owner-only, replaced by rename, written under NO
#      shared lock so it is never dropped. `tower-queue.sh next` hands over
#      nothing until this marker shows a reply later than its own last
#      delivery, so the marker is the only thing that confirms attention and
#      the log line below is not (D-6).
#   2. The `reply` event, appended through `tower-queue.sh log`, which owns
#      the fleet lock, the sequence, the bounded lock wait and the
#      secret-shaped redaction: this hook parses no secrets and redacts
#      nothing itself (REQ-G1.8). A lock wait past `tower_hook_lock_wait`
#      drops the line into events.dropped (the verb's exit 3) and the turn
#      proceeds; the marker has already advanced.
#
# THE GATE (kickoff risk row 5). The plugin registers this hook in every
# session it is loaded in. It is a no-op unless the payload's session id names
# a LIVE published presence record on the payload cwd's repository surface —
# `fleet-presence.sh liveness` answering `self` — never a prose or env test a
# session could satisfy by accident. A worker session, an operator's ordinary
# session, and a session in a checkout with no origin all read `no-record` or
# a non-zero presence exit and write nothing. Before the presence query runs
# at all, a fleet home with no presence surface exits: no tower has ever
# published on this machine, so nothing here can be one.
#
# HOOK DISCIPLINE. On this event the harness ADDS plain stdout to the model's
# context and reads exit 2 as "block and erase the prompt" (the hooks
# reference, consulted 2026-09-15), so this hook prints nothing on stdout,
# exits 0 on every path, signals included, and says what it declined on stderr
# only. The payload is read as a bounded prefix and walked by the hook's own
# awk (no JSON tool, REQ-K1.5): every string is data, and the three values it uses —
# session id, cwd, prompt — are validated against their grammars before
# anything is done with them. A prompt is flattened to one line of printable
# bytes and bounded to the log's value cap; one shaped like a JSON object or
# array (which the log verb refuses as nesting) is logged without its text,
# marked `text_omitted`, so the reply still counts.
#
# Plain portable shell, no model invocation (REQ-H1.4); bash 3.2 / BSD floor.
# Pathname expansion is off (set -f): the mode checks word-split an `ls` line.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

# Every exit is 0: a hook exit code is a verdict on the operator's prompt, and
# this hook has none to give.
trap 'exit 0' INT TERM

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 0
if [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "tower-reply-hook: scripts/echo-safety.sh is missing — broken install; reply not recorded" >&2
  exit 0
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

FS="$script_dir/fleet-state.sh"
FP="$script_dir/fleet-presence.sh"
TQ="$script_dir/tower-queue.sh"

PENDING_TMP=""
cleanup() {
  [ -z "$PENDING_TMP" ] || rm -f "$PENDING_TMP" 2>/dev/null || true
}
trap 'cleanup' EXIT

decline() {
  printf '%s\n' "tower-reply-hook: $1" >&2
  exit 0
}

is_uuid() {
  [ "${#1}" -eq 36 ] || return 1
  case "$1" in
    ????????-????-????-????-????????????) ;;
    *) return 1 ;;
  esac
  _h=$(printf '%s' "$1" | tr -d -- '-')
  [ "${#_h}" -eq 32 ] || return 1
  case "$_h" in
    *[!0-9a-fA-F]*) return 1 ;;
  esac
  return 0
}

# --- the payload -----------------------------------------------------------

payload=$(head -c 65536 2>/dev/null) || payload=""
[ -n "$payload" ] || exit 0

# One walk over the top-level object, printing `<key><TAB><value>` for the
# three keys this hook reads, in payload order, first occurrence only. Strings
# are read with their escapes resolved (an escaped control character becomes a
# space; a `\u` escape becomes a space); nested values are skipped with
# string-aware bracket counting; an unterminated string means the bounded read
# cut the payload, and nothing after the cut is read. Tabs and newlines are
# replaced inside every printed value so the tag split below cannot be forged.
fields=$(printf '%s\n' "$payload" | awk '
  function skipws() { while (i <= n && substr(s, i, 1) ~ /[ \t\r\n]/) i++ }
  function readstr(    c, e) {
    val = ""; i++
    while (i <= n) {
      c = substr(s, i, 1)
      if (c == "\"") { i++; return 1 }
      if (c == "\\") {
        e = substr(s, i + 1, 1)
        if (e == "\"" || e == "\\" || e == "/") val = val e
        else if (e == "u") { val = val " "; i += 4 }
        else val = val " "
        i += 2
        continue
      }
      val = val c; i++
    }
    return 0
  }
  function skipvalue(    c, depth, instr) {
    c = substr(s, i, 1)
    if (c == "{" || c == "[") {
      depth = 0; instr = 0
      while (i <= n) {
        c = substr(s, i, 1)
        if (instr) {
          if (c == "\\") { i += 2; continue }
          if (c == "\"") instr = 0
        } else if (c == "\"") instr = 1
        else if (c == "{" || c == "[") depth++
        else if (c == "}" || c == "]") { depth--; if (depth == 0) { i++; return 1 } }
        i++
      }
      return 0
    }
    while (i <= n && substr(s, i, 1) !~ /[,}]/) i++
    return 1
  }
  { s = s $0 "\n" }
  END {
    n = length(s)
    i = index(s, "{")
    if (i == 0) exit
    i++
    while (i <= n) {
      skipws()
      c = substr(s, i, 1)
      if (c == "}") exit
      if (c == ",") { i++; continue }
      if (c != "\"") exit
      if (!readstr()) exit
      key = val
      skipws()
      if (substr(s, i, 1) != ":") exit
      i++
      skipws()
      if (substr(s, i, 1) == "\"") {
        if (!readstr()) {
          # Cut inside a string. The prompt is the one value worth keeping in
          # part (an over-long prompt is the ordinary way to reach the bound,
          # and the log keeps its first bytes anyway); a partial identity or
          # path is not one.
          if (key == "prompt" && !("prompt" in seen)) {
            gsub(/[\t\r\n]/, " ", val)
            print key "\t" val
          }
          exit
        }
        if ((key == "session_id" || key == "cwd" || key == "prompt") && !(key in seen)) {
          seen[key] = 1
          gsub(/[\t\r\n]/, " ", val)
          print key "\t" val
        }
      } else if (!skipvalue()) exit
    }
  }')

field() {
  printf '%s\n' "$fields" | awk -F'\t' -v k="$1" '$1 == k { sub(/^[^\t]*\t/, ""); print; exit }'
}

sid=$(field session_id | tr -d '\000-\037\177')
cwd=$(field cwd | tr -d '\000-\037\177')
is_uuid "$sid" || exit 0
case "$cwd" in
  /*) ;;
  *) exit 0 ;;
esac
[ -d "$cwd" ] || exit 0

# --- the gate ---------------------------------------------------------------

home=$("$FS" root 2>/dev/null) || exit 0
[ -d "$home/presence" ] || exit 0
verdict=$("$FP" liveness --checkout "$cwd" --session-id "$sid" "$sid" 2>/dev/null) || exit 0
[ "$verdict" = "$(printf 'tower\t%s\tself' "$sid")" ] || exit 0

# --- the attention marker, lock-free, before anything that can wait ----------

umask 077
my_uid=$(id -u 2>/dev/null) || decline "cannot resolve the current uid; reply not recorded"

# Verify-or-refuse (REQ-A1.4), the sub-surface discipline tower-queue.sh keeps:
# a symlink, a widened mode, or a foreign owner is refused and left for the
# operator, never narrowed here. The execute column of the group and other
# triples also spells setgid/sticky, which a setgid fleet home makes every
# fresh mkdir inherit, so those two letters are not a widening.
private_dir() {
  if [ -L "$1" ]; then
    printf '%s\n' "tower-reply-hook: security: $(sanitize_printable "$1" "(unprintable path)") is a symlink — refusing to write through a redirect" >&2
    return 1
  fi
  [ -d "$1" ] || mkdir "$1" 2>/dev/null || [ -d "$1" ] || {
    printf '%s\n' "tower-reply-hook: cannot create $(sanitize_printable "$1" "(unprintable path)")" >&2
    return 1
  }
  # shellcheck disable=SC2012
  _l=$(ls -ldn "$1" 2>/dev/null) || _l=""
  # shellcheck disable=SC2086
  set -- $_l
  case "${1:-}" in
    d???--[-S]--[-T] | d???--[-S]--[-T][@.]*) ;;
    *)
      printf '%s\n' "tower-reply-hook: security: the marker directory is not verifiably owner-only (mode ${1:-unreadable}); chmod 700 it yourself after finding out how it widened" >&2
      return 1
      ;;
  esac
  [ "${3:-}" = "$my_uid" ] || {
    printf '%s\n' "tower-reply-hook: security: the marker directory is owned by uid ${3:-?}, not this user; refusing it" >&2
    return 1
  }
  return 0
}

private_file_or_absent() {
  [ -e "$1" ] || [ -L "$1" ] || return 0
  if [ -L "$1" ]; then
    printf '%s\n' "tower-reply-hook: security: the marker is a symlink — refusing to write through a redirect" >&2
    return 1
  fi
  # shellcheck disable=SC2012
  _l=$(ls -ln "$1" 2>/dev/null) || _l=""
  # shellcheck disable=SC2086
  set -- $_l
  case "${1:-}" in
    -???------ | -???------[@.]*) ;;
    *)
      printf '%s\n' "tower-reply-hook: security: the marker is not owner-only (mode ${1:-unreadable}); chmod 600 it yourself after finding out how it widened" >&2
      return 1
      ;;
  esac
  [ "${3:-}" = "$my_uid" ] || {
    printf '%s\n' "tower-reply-hook: security: the marker is owned by uid ${3:-?}, not this user; refusing it" >&2
    return 1
  }
  return 0
}

# The reply time as seconds with millisecond decimals when `date +%N` yields a
# real nanosecond field, else whole seconds: a reply and the delivery it
# answers can share a second, and the queue compares the two.
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

surface="$home/tower-comms"
marker_dir="$surface/attention"
marker="$marker_dir/$sid"
if private_dir "$surface" && private_dir "$marker_dir" && private_file_or_absent "$marker"; then
  now=$(clock_s) || now=""
  case "$now" in
    [1-9]*) ;;
    *) now="" ;;
  esac
  if [ -z "$now" ]; then
    printf '%s\n' "tower-reply-hook: cannot read the clock; the attention marker was not advanced" >&2
  else
    PENDING_TMP=$(mktemp "$marker_dir/.$sid.XXXXXX" 2>/dev/null) || PENDING_TMP=""
    if [ -z "$PENDING_TMP" ] || ! printf '%s\n' "$now" >"$PENDING_TMP" 2>/dev/null || ! mv -f "$PENDING_TMP" "$marker" 2>/dev/null; then
      printf '%s\n' "tower-reply-hook: cannot write the attention marker; the queue will not see this reply" >&2
    fi
    PENDING_TMP=""
  fi
fi

# --- the reply line, through the log verb -----------------------------------

text=$(field prompt | tr '\000-\037\177' ' ' | head -c 4096 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
set -- log reply --tower "$sid"
case "$text" in
  "") ;;
  '{'*'}' | '['*']') set -- "$@" text_omitted=json-shaped ;;
  *) set -- "$@" "text=$text" ;;
esac
# The verb's exit is not this hook's: 3 is a counted drop, 4 and 6 are said on
# stderr, and none of them is a verdict on the prompt.
"$TQ" "$@" >/dev/null || true
