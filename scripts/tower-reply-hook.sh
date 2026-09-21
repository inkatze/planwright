#!/bin/sh
# tower-reply-hook.sh — the UserPromptSubmit hook that turns an operator reply
# into the two records the operator queue and the scorecard read (tower-comms
# D-6, D-14; REQ-C1.10, REQ-G1.6, REQ-G1.8, REQ-H1.4).
#
# WHAT IT WRITES, IN ORDER.
#   1. The attention marker: <fleet-home>/tower-comms/attention/<tower-id>, one
#      line holding the epoch of this reply in whole seconds, owner-only,
#      replaced by rename, written under NO shared lock so it is never
#      dropped. The queue's `next` verb, once it lands, hands over nothing
#      until this marker shows a reply later than its own last knock and
#      hand-over, so the marker is the only thing that confirms attention and
#      the log line below is not (D-6). Whole seconds, not finer: the times
#      it is compared against are whole seconds, so a finer reply time would
#      read as later than a hand-over stamped in the same second even when it
#      came first, and a tie must read as not yet confirmed. Each write keeps
#      the later of the value on disk and now, so a clock stepped back leaves
#      the later value in place. That is the whole of the guarantee: the read
#      and the rename are not one step, so two invocations racing on one
#      session both read before either renames and the later RENAME wins
#      rather than the later value, which can step the stamp back by about a
#      second. The harness submits one prompt at a time per session, so it
#      does not produce that interleaving; and a stamp a second early reads
#      as a reply that did not answer the last hand-over, which knocks again
#      rather than losing the reply. Verify-or-refuse before the write, down
#      the whole path (REQ-A1.4): the fleet home, the `tower-comms`
#      sub-surface, the `attention` directory and the marker file itself are
#      each held to the bar `tower-queue.sh` holds them to, and none of them
#      is ever repaired here. Any refusal skips the marker, says why on
#      stderr, and names itself on the reply line below; the turn is never
#      refused over it (see HOOK DISCIPLINE).
#   2. The `reply` event, appended through `tower-queue.sh log`, which owns
#      the fleet lock, the sequence, the bounded lock wait and the
#      secret-shaped redaction: this hook parses no secrets and redacts
#      nothing itself (REQ-G1.8). A lock wait past `tower_hook_lock_wait`
#      drops the line into events.dropped (the verb's exit 3) and the turn
#      proceeds; the marker has already advanced. The line carries the
#      payload's prompt id when it has one, and a `marker` field naming the
#      outcome whenever the marker was not written, so the durable record
#      says when the two halves disagree.
#
# THE GATE (kickoff risk row 5). The plugin registers this hook in every
# session it is loaded in. It is a no-op unless the payload's session id names
# a published presence record on the payload cwd's repository surface —
# `fleet-presence.sh liveness` answering `self` — never a prose or env test a
# session could satisfy by accident. A session id is unique to its session,
# so a record by that name is this session's own, published by its own tower
# loop; the process asking is running, which is what makes the record live. A
# worker session, an operator's ordinary session, a session in a checkout
# with no origin, and a tower that published its presence by `--pid` rather
# than `--session-id` (the composite identity this hook cannot derive) all
# write nothing. Two fork-free tests run before the presence query: the fleet
# home must hold a presence surface, and that surface must hold a record
# named by this session id under some repository; only then does the
# authoritative, repo-scoped query run.
#
# HOOK DISCIPLINE. On this event the harness ADDS plain stdout to the model's
# context and reads exit 2 as "block and erase the prompt" (the hooks
# reference, consulted 2026-09-15), so this hook prints nothing on stdout,
# exits 0 on every path it controls (the hangup, interrupt, quit, pipe and
# termination signals included), and says what it declined on stderr only.
# The payload is read as a bounded prefix, the rest drained so the writer is
# never broken, and walked by the hook's own awk (no JSON tool, REQ-K1.5):
# every string is data, and the values it uses — session id, cwd, prompt,
# prompt id — are validated against their grammars before anything is done
# with them. A prompt is flattened to one line of printable bytes and bounded
# to the log's value cap; one shaped like a JSON object or array (which the
# log verb refuses as nesting) or one that flattens to nothing is logged
# without text and marked `text_omitted`, so the reply still counts.
#
# Plain portable shell, no model invocation (REQ-H1.4); bash 3.2 / BSD floor.
# Pathname expansion is off (set -f) except at the one marked record glob:
# the mode checks word-split an `ls` line.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

# Every exit is 0: a hook exit code is a verdict on the operator's prompt, and
# this hook has none to give.
trap 'exit 0' INT TERM HUP QUIT PIPE

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
tab=$(printf '\t')
# The log verb's value cap, restated here because the text is cut before the
# verb sees it; the verb refuses an over-long value rather than truncating.
VALUE_CAP=4096

PENDING_TMP=""
cleanup() {
  [ -z "$PENDING_TMP" ] || rm -f "$PENDING_TMP" 2>/dev/null || true
}
trap 'cleanup' EXIT

warn() {
  printf '%s\n' "tower-reply-hook: $1" >&2
}

# The session-id UUID shape (8-4-4-4-12 hex), as fleet-presence.sh reads it.
# The glob's `?` also admits `-`, so the residue check is what refuses a
# dash-heavy non-UUID: 32 hex characters once the separators are removed.
is_uuid() {
  [ "${#1}" -eq 36 ] || return 1
  case "$1" in
    ????????-????-????-????-????????????) ;;
    *) return 1 ;;
  esac
  _hex=$(printf '%s' "$1" | tr -d -- '-')
  [ "${#_hex}" -eq 32 ] || return 1
  case "$_hex" in
    *[!0-9a-fA-F]*) return 1 ;;
  esac
  return 0
}

# The private-surface checks tower-queue.sh keeps (its check_private_dir and
# check_private_file, kept in step: the mode globs are one invariant), with
# `return 1` in place of its exit so a refused marker still lets the reply
# reach the log. The execute column of the group and other triples also
# spells setgid/sticky, which a setgid fleet home makes every fresh mkdir
# inherit, so those two letters are not a widening. A refusal names the path
# and is never repaired here (REQ-A1.4: verify-or-refuse, never narrowed).
my_uid=""
check_private_dir() {
  _p=$1
  if [ -L "$_p" ]; then
    warn "security: $(sanitize_printable "$_p" "(unprintable path)") is a symlink — refusing to write through a redirect"
    return 1
  fi
  [ -d "$_p" ] || mkdir "$_p" 2>/dev/null || [ -d "$_p" ] || {
    warn "cannot create $(sanitize_printable "$_p" "(unprintable path)")"
    return 1
  }
  # shellcheck disable=SC2012
  _l=$(ls -ldn "$_p" 2>/dev/null) || _l=""
  # shellcheck disable=SC2086
  set -- $_l
  case "${1:-}" in
    d???--[-S]--[-T] | d???--[-S]--[-T][@.]*) ;;
    *)
      warn "security: $(sanitize_printable "$_p" "(unprintable path)") is not verifiably owner-only (mode ${1:-unreadable}); chmod 700 it yourself after finding out how it widened"
      return 1
      ;;
  esac
  [ "${3:-}" = "$my_uid" ] || {
    warn "security: $(sanitize_printable "$_p" "(unprintable path)") is owned by uid ${3:-?}, not this user; refusing it"
    return 1
  }
  return 0
}

# check_home — the same verification tower-queue.sh's check_home makes, for
# the same reason: the 0700 sub-surface below is only as private as the home
# that holds it, so a home anyone else can write to, or one redirected by a
# symlink, is one where the marker directory can be moved aside and replaced
# between the checks below and the write they guard.
check_home() {
  if [ -L "$home" ]; then
    warn "security: the fleet home $(sanitize_printable "$home" "(unprintable path)") is a symlink — refusing to write through a redirect"
    return 1
  fi
  # shellcheck disable=SC2012
  _hl=$(ls -ldn "$home" 2>/dev/null) || _hl=""
  if [ -z "$_hl" ]; then
    warn "the fleet home $(sanitize_printable "$home" "(unprintable path)") vanished while being verified"
    return 1
  fi
  # shellcheck disable=SC2086
  set -- $_hl
  case "${1:-}" in
    d*) ;;
    *)
      warn "security: the fleet home $(sanitize_printable "$home" "(unprintable path)") is not a directory (mode ${1:-unreadable}); refusing it"
      return 1
      ;;
  esac
  # Only the two WRITE columns, as tower-queue.sh has it: a home readable or
  # traversable by others is the ordinary shape (fleet-state creates it under
  # the caller's umask), and narrowing someone else's surface is not this
  # hook's call.
  case "${1:-}" in
    d????-??-? | d????-??-?[@.]*) ;;
    *)
      warn "security: the fleet home $(sanitize_printable "$home" "(unprintable path)") is writable beyond its owner (mode ${1:-unreadable}); chmod go-w it yourself after finding out how it widened"
      return 1
      ;;
  esac
  [ "${3:-}" = "$my_uid" ] || {
    warn "security: the fleet home $(sanitize_printable "$home" "(unprintable path)") is owned by uid ${3:-?}, not this user; refusing it"
    return 1
  }
  return 0
}

check_private_file() {
  _p=$1
  [ -e "$_p" ] || [ -L "$_p" ] || return 0
  if [ -L "$_p" ]; then
    warn "security: $(sanitize_printable "$_p" "(unprintable path)") is a symlink — refusing to write through a redirect"
    return 1
  fi
  # shellcheck disable=SC2012
  _l=$(ls -ln "$_p" 2>/dev/null) || _l=""
  # shellcheck disable=SC2086
  set -- $_l
  case "${1:-}" in
    -???------ | -???------[@.]*) ;;
    *)
      warn "security: $(sanitize_printable "$_p" "(unprintable path)") is not owner-only (mode ${1:-unreadable}); chmod 600 it yourself after finding out how it widened"
      return 1
      ;;
  esac
  [ "${3:-}" = "$my_uid" ] || {
    warn "security: $(sanitize_printable "$_p" "(unprintable path)") is owned by uid ${3:-?}, not this user; refusing it"
    return 1
  }
  return 0
}

# field <key> — the value the payload walker printed for <key>, or nothing.
field() {
  printf '%s\n' "$fields" | awk -F'\t' -v k="$1" '$1 == k { sub(/^[^\t]*\t/, ""); print; exit }'
}

# --- the payload -----------------------------------------------------------

# A bounded prefix, the remainder drained: a prompt past the bound must not
# break the harness's write with a closed pipe.
payload=$({
  head -c 65536
  cat >/dev/null 2>&1
} 2>/dev/null) || payload=""
[ -n "$payload" ] || exit 0

# The cheap gate first, before any fork the ordinary session would pay for:
# the session id read by one regex (the envelope leads the payload, so the
# first match is the harness's), then a fork-free test for a presence record
# by that name. The full walk below re-reads the session id and the two must
# agree.
sid=$(printf '%s\n' "$payload" | awk '
  match($0, /"session_id"[ \t\r\n]*:[ \t\r\n]*"[^"]*"/) {
    seg = substr($0, RSTART, RLENGTH)
    sub(/^"session_id"[ \t\r\n]*:[ \t\r\n]*"/, "", seg)
    sub(/"$/, "", seg)
    print seg
    exit
  }')
is_uuid "$sid" || exit 0
home=$("$FS" root 2>/dev/null) || exit 0
[ -d "$home/presence" ] || exit 0
# The one glob: the session id is validated above, so no pattern character
# reaches it, and a miss leaves the literal pattern, which does not exist.
set +f
set -- "$home"/presence/*/"$sid"
set -f
[ -e "$1" ] || exit 0

# One walk over the top-level object, printing `<key><TAB><value>` for the
# keys this hook reads, in payload order, first occurrence only. Strings are
# read with their escapes resolved (an escaped control character becomes a
# space; a `\u` escape becomes a space), by segment between escapes rather
# than byte by byte, so a long prompt costs one pass; nested values are
# skipped with string-aware bracket counting; an unterminated string means
# the bounded read cut the payload, and nothing after the cut is read. Tabs
# and newlines are replaced inside every printed value so the tag split
# below cannot be forged.
fields=$(printf '%s\n' "$payload" | awk '
  function skipws() { while (i <= n && substr(s, i, 1) ~ /[ \t\r\n]/) i++ }
  function readstr(    rest, j, c, e) {
    val = ""; i++
    while (i <= n) {
      rest = substr(s, i)
      j = match(rest, /["\\]/)
      if (j == 0) { val = val rest; i = n + 1; return 0 }
      val = val substr(rest, 1, j - 1)
      i += j - 1
      c = substr(s, i, 1)
      if (c == "\"") { i++; return 1 }
      e = substr(s, i + 1, 1)
      if (e == "\"" || e == "\\" || e == "/") val = val e
      else if (e == "u") { val = val " "; i += 4 }
      else val = val " "
      i += 2
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
  function emit(key) {
    if (!(key in seen) && (key == "session_id" || key == "cwd" || key == "prompt" || key == "prompt_id")) {
      seen[key] = 1
      gsub(/[\t\r\n]/, " ", val)
      print key "\t" val
    }
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
          if (key == "prompt") emit(key)
          exit
        }
        emit(key)
      } else if (!skipvalue()) exit
    }
  }')

walked_sid=$(field session_id | tr -d '\000-\037\177')
[ "$walked_sid" = "$sid" ] || exit 0
cwd=$(field cwd | tr -d '\000-\037\177')
case "$cwd" in
  /*) ;;
  *) exit 0 ;;
esac
[ -d "$cwd" ] || exit 0
prompt_id=$(field prompt_id | tr -d '\000-\037\177')
is_uuid "$prompt_id" || prompt_id=""

# --- the gate ---------------------------------------------------------------

verdict=$("$FP" liveness --checkout "$cwd" --session-id "$sid" "$sid" 2>/dev/null) || exit 0
case "$verdict" in
  "tower${tab}${sid}${tab}self") ;;
  *) exit 0 ;;
esac

# --- the attention marker, lock-free, before anything that can wait ----------

umask 077
surface="$home/tower-comms"
marker_dir="$surface/attention"
marker="$marker_dir/$sid"
marker_state=written
my_uid=$(id -u 2>/dev/null) || my_uid=""
if [ -z "$my_uid" ]; then
  warn "cannot resolve the current uid; the attention marker was not advanced"
  marker_state=refused
elif ! check_home || ! check_private_dir "$surface" || ! check_private_dir "$marker_dir" || ! check_private_file "$marker"; then
  marker_state=refused
else
  now=$(date +%s 2>/dev/null) || now=""
  case "$now" in
    "" | *[!0-9]* | 0*) now="" ;;
  esac
  if [ -z "$now" ]; then
    warn "cannot read the clock; the attention marker was not advanced"
    marker_state=failed
  else
    # The later of the value on disk and now, so a stepped-back clock leaves
    # the later value. Read then rename, not a lock: two invocations racing
    # on one session can still leave the earlier read (see the header).
    if [ -f "$marker" ]; then
      now=$(awk -v now="$now" 'NR == 1 { v = $1 + 0; if (v > now) now = v } END { printf "%d\n", now }' "$marker" 2>/dev/null) || now=""
    fi
    PENDING_TMP=$(mktemp "$marker_dir/.$sid.XXXXXX" 2>/dev/null) || PENDING_TMP=""
    if [ -n "$now" ] && [ -n "$PENDING_TMP" ] && printf '%s\n' "$now" >"$PENDING_TMP" 2>/dev/null && mv -f "$PENDING_TMP" "$marker" 2>/dev/null; then
      PENDING_TMP=""
    else
      warn "cannot write the attention marker; the queue will not see this reply"
      [ -z "$PENDING_TMP" ] || rm -f "$PENDING_TMP" 2>/dev/null || true
      PENDING_TMP=""
      marker_state=failed
    fi
  fi
fi

# --- the reply line, through the log verb -----------------------------------

# Flatten, bound, trim: every control byte becomes a space, the text is cut
# at the value cap with any multi-byte character the cut split dropped, and
# the edges are trimmed.
text=$(field prompt | tr '\000-\037\177' ' ' | head -c "$VALUE_CAP" | awk '
  BEGIN { for (b = 0; b < 256; b++) ord[sprintf("%c", b)] = b }
  {
    t = $0
    L = length(t)
    k = L
    while (k >= 1 && k > L - 4 && ord[substr(t, k, 1)] >= 128 && ord[substr(t, k, 1)] < 192) k--
    if (k >= 1) {
      lead = ord[substr(t, k, 1)]
      need = (lead >= 240) ? 3 : (lead >= 224) ? 2 : (lead >= 192) ? 1 : 0
      if (need > L - k) t = substr(t, 1, k - 1)
    }
    print t
    exit
  }' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
set -- log reply --tower "$sid"
[ -z "$prompt_id" ] || set -- "$@" "prompt_id=$prompt_id"
case "$text" in
  "") set -- "$@" text_omitted=empty ;;
  '{'*'}' | '['*']') set -- "$@" text_omitted=json-shaped ;;
  *) set -- "$@" "text=$text" ;;
esac
[ "$marker_state" = written ] || set -- "$@" "marker=$marker_state"
# The verb's exit is not this hook's: 3 is a counted drop, 4 and 6 are said on
# stderr, and none of them is a verdict on the prompt.
"$TQ" "$@" >/dev/null || true
