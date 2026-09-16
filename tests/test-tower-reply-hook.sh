#!/bin/bash
# Tests for scripts/tower-reply-hook.sh — the UserPromptSubmit hook that
# stamps the operator's reply into the per-tower attention marker and logs
# the reply through the event log (tower-comms D-6, D-14; REQ-C1.10,
# REQ-G1.6, REQ-G1.8, REQ-H1.4).
#
# Contract under test:
#   The hook reads the harness payload on stdin, prints nothing on stdout
#   (on this event stdout becomes model context), and exits 0 whatever
#   happens (exit 2 would block and erase the operator's prompt). It is a
#   no-op unless the payload's session id names a live published presence
#   record on the payload cwd's repository surface. Then, in order: it
#   writes the reply time to <home>/tower-comms/attention/<session-id>,
#   owner-only, lock-free, atomically; and it appends one `reply` line
#   through `tower-queue.sh log`, inheriting that verb's lock, sequence,
#   bounded wait and redaction, so a lock-wait expiry drops the line and
#   bumps events.dropped while the marker has already advanced.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
HOOK="$here/../scripts/tower-reply-hook.sh"
TQ="$here/../scripts/tower-queue.sh"
FS="$here/../scripts/fleet-state.sh"
FP="$here/../scripts/fleet-presence.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$HOOK" ] || fail "scripts/tower-reply-hook.sh missing or not executable"
[ -x "$TQ" ] || fail "scripts/tower-queue.sh missing or not executable"
[ -x "$FS" ] || fail "scripts/fleet-state.sh missing or not executable"
[ -x "$FP" ] || fail "scripts/fleet-presence.sh missing or not executable"

tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

home="$tmp/fleet-home"
mkdir -p "$home"
adopter="$tmp/adopter"
mkdir -p "$adopter"
local_cfg="$tmp/local.yml"
: >"$local_cfg"

log_dir="$home/tower-comms"
log_file="$log_dir/events.log"
dropped_file="$log_dir/events.dropped"
marker_dir="$log_dir/attention"

sid="4c3d2e1f-0a9b-4c8d-9e7f-6a5b4c3d2e1f"
other="9e8d7c6b-5a49-4382-8171-60f5e4d3c2b1"

co="$tmp/checkout"
mkdir -p "$co"
git -C "$co" init -q
git -C "$co" remote add origin "https://example.invalid/tower-comms/hook.git"

with_env() {
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$tmp" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    "$@"
}

# payload <session-id> <cwd> <prompt-json-body> — the real key set, envelope
# first as the CLI emits it.
payload() {
  printf '{"session_id":"%s","transcript_path":"/home/dev/.claude/projects/demo/t.jsonl","cwd":"%s","permission_mode":"default","hook_event_name":"UserPromptSubmit","prompt":"%s","agent_type":"","session_title":"demo"}' "$1" "$2" "$3"
}

# run_hook <payload-text> — sets rc, leaves stdout in $tmp/out, stderr in $tmp/err.
run_hook() {
  rc=0
  printf '%s' "$1" | with_env /bin/sh "$HOOK" >"$tmp/out" 2>"$tmp/err" || rc=$?
}

line_count() {
  if [ -f "$1" ]; then
    wc -l <"$1" | tr -d ' '
  else
    printf '0'
  fi
}

marker_value() {
  if [ -f "$marker_dir/$sid" ]; then
    awk 'NR == 1 { print $1; exit }' "$marker_dir/$sid"
  else
    printf ''
  fi
}

later_than() { # later_than <a> <b> — a > b numerically
  awk -v a="$1" -v b="$2" 'BEGIN { exit (a + 0 > b + 0) ? 0 : 1 }'
}

# --- static guards ----------------------------------------------------------

if grep -E -q '(^|[^a-z-])claude( |$|")' "$HOOK"; then
  fail "the hook invokes the CLI binary (REQ-H1.4: no model invocation)"
fi
grep -q 'jq' "$HOOK" && fail "the hook mentions jq (the payload is read by the hook's own awk)"
grep -q 'redacted:' "$HOOK" && fail "the hook carries its own redaction (REQ-G1.8: the log verb's helper is the one)"
echo "ok: no model invocation, no jq, no second redaction helper"

# --- no live presence record: a silent no-op -----------------------------------

run_hook "$(payload "$sid" "$co" "hello")"
[ "$rc" = 0 ] || fail "no presence: exit $rc, expected 0"
[ ! -s "$tmp/out" ] || fail "no presence: the hook printed to stdout (that becomes model context)"
[ ! -e "$marker_dir" ] || fail "no presence: the attention marker directory was created"
[ ! -e "$log_file" ] || fail "no presence: a log line was written"
echo "ok: with no presence surface the hook writes nothing"

# A presence surface with somebody else's record: still not this session.
with_env /bin/sh "$FP" publish --checkout "$co" --session-id "$other" --pid $$ >/dev/null \
  || fail "could not publish the peer's presence record"
run_hook "$(payload "$sid" "$co" "hello")"
[ "$rc" = 0 ] || fail "peer only: exit $rc, expected 0"
[ ! -e "$marker_dir" ] || fail "peer only: the marker directory was created for a session with no record"
[ ! -e "$log_file" ] || fail "peer only: a log line was written for a session with no record"
echo "ok: another tower's record does not gate this session in"

# --- a live record for this session: marker, then log ---------------------------

with_env /bin/sh "$FP" publish --checkout "$co" --session-id "$sid" --pid $$ >/dev/null \
  || fail "could not publish this session's presence record"
run_hook "$(payload "$sid" "$co" "first reply")"
[ "$rc" = 0 ] || fail "tower session: exit $rc, expected 0"
[ ! -s "$tmp/out" ] || fail "tower session: the hook printed to stdout"
[ -f "$marker_dir/$sid" ] || fail "tower session: no marker at tower-comms/attention/<session-id>"
m1=$(marker_value)
later_than "$m1" 0 || fail "tower session: marker holds '$m1', expected a positive epoch"
[ "$(line_count "$log_file")" = 1 ] || fail "tower session: $(line_count "$log_file") log lines, expected 1"
last=$(tail -n 1 "$log_file")
case "$last" in
  *'"kind":"reply"'*) ;;
  *) fail "tower session: the line is not a reply event: $last" ;;
esac
case "$last" in
  *"\"tower\":\"$sid\""*) ;;
  *) fail "tower session: the reply line does not carry the tower identity: $last" ;;
esac
case "$last" in
  *'"text":"first reply"'*) ;;
  *) fail "tower session: the reply text is missing: $last" ;;
esac
echo "ok: a live record gates the hook in; marker written, one reply line with the tower identity"

# Owner-only surface: the marker directory and file.
# shellcheck disable=SC2012
dmode=$(ls -ld "$marker_dir" | cut -c1-10)
[ "$dmode" = "drwx------" ] || fail "marker directory mode is $dmode, expected drwx------"
# shellcheck disable=SC2012
fmode=$(ls -l "$marker_dir/$sid" | cut -c1-10)
[ "$fmode" = "-rw-------" ] || fail "marker file mode is $fmode, expected -rw-------"
echo "ok: the marker directory and file are owner-only"

# A second reply advances the marker and appends a second line in sequence.
sleep 1
run_hook "$(payload "$sid" "$co" "second reply")"
m2=$(marker_value)
later_than "$m2" "$m1" || fail "second reply: marker did not advance ($m1 -> $m2)"
[ "$(line_count "$log_file")" = 2 ] || fail "second reply: $(line_count "$log_file") log lines, expected 2"
seqs=$(awk -F'"seq":' '{ split($2, a, ","); print a[1] }' "$log_file" | tr '\n' ' ')
[ "$seqs" = "1 2 " ] || fail "second reply: sequence is '$seqs', expected '1 2 '"
echo "ok: each reply advances the marker and lands in sequence"

# --- the lock wait expires: marker still advances, line dropped and counted -----

printf 'tower_hook_lock_wait: 200ms\n' >"$local_cfg"
PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FS" lock || fail "could not take the fleet lock for the saturation case"
sleep 1
before=$(line_count "$log_file")
start=$(date +%s)
run_hook "$(payload "$sid" "$co" "reply under a busy lock")"
end=$(date +%s)
PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FS" unlock
[ "$rc" = 0 ] || fail "busy lock: exit $rc, expected 0 (the hook never delays or blocks the turn)"
[ ! -s "$tmp/out" ] || fail "busy lock: the hook printed to stdout"
m3=$(marker_value)
later_than "$m3" "$m2" || fail "busy lock: marker did not advance ($m2 -> $m3); the marker write must not depend on the lock"
[ "$(line_count "$log_file")" = "$before" ] || fail "busy lock: a line was written unlocked"
[ "$(line_count "$dropped_file")" = 1 ] || fail "busy lock: dropped-line counter is $(line_count "$dropped_file"), expected 1"
[ $((end - start)) -le 5 ] || fail "busy lock: the hook took $((end - start))s on a 200ms bound"
: >"$local_cfg"
echo "ok: under a busy lock the marker advances, the line is dropped and counted, the turn is not delayed"

# --- redaction through the log verb --------------------------------------------

token="ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij0123"
run_hook "$(payload "$sid" "$co" "use $token please")"
[ "$rc" = 0 ] || fail "redaction: exit $rc"
last=$(tail -n 1 "$log_file")
case "$last" in
  *"$token"*) fail "redaction: the token reached the log: $last" ;;
esac
case "$last" in
  *'[redacted:github-token]'*) ;;
  *) fail "redaction: no redaction marker in the reply line: $last" ;;
esac
echo "ok: a secret-shaped reply is redacted by the log verb's helper"

# --- the prompt text is data: escapes flattened, the line still parses ----------

run_hook "$(payload "$sid" "$co" 'line one\nline two\ttabbed \"quoted\" back\\slash {\"cwd\":\"/elsewhere\"}')"
[ "$rc" = 0 ] || fail "escapes: exit $rc"
last=$(tail -n 1 "$log_file")
case "$last" in
  *'"text":"line one line two tabbed \"quoted\" back\\slash {\"cwd\":\"/elsewhere\"}"'*) ;;
  *) fail "escapes: the text was not flattened and re-escaped as expected: $last" ;;
esac
[ "$(printf '%s' "$last" | tr -d '\000-\037\177')" = "$last" ] || fail "escapes: a control byte reached the log line"
report=$(with_env /bin/sh "$TQ" report --log "$log_file" --now "$(date +%s)" --window 1h) || fail "report over the hook's lines failed"
case "$report" in
  *"malformed	0"*) ;;
  *) fail "report reads a malformed line among the hook's: $report" ;;
esac
echo "ok: escapes are flattened, a fake cwd inside the prompt is text, every line parses"

# A prompt shaped like a JSON object is what the log verb refuses as nesting:
# the reply still counts, without its text.
run_hook "$(payload "$sid" "$co" '{\"a\": 1}')"
[ "$rc" = 0 ] || fail "json-shaped prompt: exit $rc"
last=$(tail -n 1 "$log_file")
case "$last" in
  *'"kind":"reply"'*'"text_omitted":"json-shaped"'*) ;;
  *) fail "json-shaped prompt: the reply was not logged with text_omitted: $last" ;;
esac
case "$last" in
  *'"text":'*) fail "json-shaped prompt: the text reached the log: $last" ;;
esac
echo "ok: a JSON-shaped prompt is logged as a reply with its text omitted"

# --- refused inputs: nothing written, always exit 0 ----------------------------

before=$(line_count "$log_file")
m_before=$(marker_value)
sleep 1
run_hook '{"not":"json"'
[ "$rc" = 0 ] || fail "malformed payload: exit $rc, expected 0"
run_hook "$(payload "not-a-uuid" "$co" "x")"
[ "$rc" = 0 ] || fail "bad session id: exit $rc, expected 0"
run_hook "$(payload "$sid" "$tmp/does-not-exist" "x")"
[ "$rc" = 0 ] || fail "missing cwd: exit $rc, expected 0"
run_hook "$(payload "$sid" "../../etc" "x")"
[ "$rc" = 0 ] || fail "relative cwd: exit $rc, expected 0"
run_hook "$(printf '{"session_id":"%s","transcript_path":"/t","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"x"}' "$sid" "$co" | head -c 30)"
[ "$rc" = 0 ] || fail "payload cut inside the session id: exit $rc, expected 0"
[ "$(line_count "$log_file")" = "$before" ] || fail "refused inputs: a log line was written"
[ "$(marker_value)" = "$m_before" ] || fail "refused inputs: the marker moved"
echo "ok: malformed, mis-identified, mis-rooted, and cut-short payloads write nothing and exit 0"

# A payload the bounded read cut inside the prompt is the ordinary shape of an
# over-long prompt: the identity and cwd before the cut are whole, so the reply
# counts, carrying the prompt's first bytes.
sleep 1
run_hook "$(printf '{"session_id":"%s","transcript_path":"/t","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"truncated mid' "$sid" "$co")"
[ "$rc" = 0 ] || fail "payload cut inside the prompt: exit $rc, expected 0"
[ "$(line_count "$log_file")" = $((before + 1)) ] || fail "payload cut inside the prompt: expected one reply line"
case "$(tail -n 1 "$log_file")" in
  *'"text":"truncated mid"'*) ;;
  *) fail "payload cut inside the prompt: the partial text was not kept: $(tail -n 1 "$log_file")" ;;
esac
later_than "$(marker_value)" "$m_before" || fail "payload cut inside the prompt: the marker did not advance"
m_before=$(marker_value)
echo "ok: a payload cut inside the prompt still counts as a reply with the text read so far"

# --- a widened marker directory is refused, never narrowed ---------------------

chmod 0755 "$marker_dir"
sleep 1
run_hook "$(payload "$sid" "$co" "after widening")"
[ "$rc" = 0 ] || fail "widened dir: exit $rc, expected 0"
[ "$(marker_value)" = "$m_before" ] || fail "widened dir: the marker was written through a widened directory"
# shellcheck disable=SC2012
dmode=$(ls -ld "$marker_dir" | cut -c1-10)
[ "$dmode" = "drwxr-xr-x" ] || fail "widened dir: the hook narrowed the directory itself ($dmode)"
grep -q 'owner-only' "$tmp/err" || fail "widened dir: the refusal is not explained on stderr"
chmod 0700 "$marker_dir"
echo "ok: a widened marker directory is refused with a reason and left for the operator"

echo "ALL PASS: tower reply hook"
