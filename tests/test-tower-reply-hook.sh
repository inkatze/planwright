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
#   no-op unless the payload's session id names a published presence record
#   on the payload cwd's repository surface. Then, in order: it writes the
#   reply time in whole seconds to <home>/tower-comms/attention/<session-id>,
#   owner-only, lock-free, atomically, keeping the later of the value on disk
#   and now, and only after verifying the whole write path from the fleet home
#   down to the marker file; and it appends one `reply` line through
#   `tower-queue.sh log`, inheriting that verb's lock, sequence, bounded wait
#   and redaction, so a lock-wait expiry drops the line and bumps
#   events.dropped while the marker has already advanced. A marker the hook
#   could not write is named on the reply line.
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
stale="0f1e2d3c-4b5a-4968-8776-655443322110"
pid_uuid="7a6b5c4d-3e2f-4a1b-9c8d-7e6f5a4b3c2d"

co="$tmp/checkout"
mkdir -p "$co"
git -C "$co" init -q
git -C "$co" remote add origin "https://example.invalid/tower-comms/hook.git"
co2="$tmp/elsewhere"
mkdir -p "$co2"
git -C "$co2" init -q
git -C "$co2" remote add origin "https://example.invalid/tower-comms/other.git"

with_env() {
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$tmp" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    "$@"
}

# payload <session-id> <cwd> <prompt-json-body> [<prompt-id>] — the real key
# set, envelope first as the CLI emits it.
payload() {
  if [ "$#" -ge 4 ]; then
    printf '{"session_id":"%s","prompt_id":"%s","transcript_path":"/home/dev/.claude/projects/demo/t.jsonl","cwd":"%s","permission_mode":"default","hook_event_name":"UserPromptSubmit","prompt":"%s","agent_type":"","session_title":"demo"}' "$1" "$4" "$2" "$3"
  else
    printf '{"session_id":"%s","transcript_path":"/home/dev/.claude/projects/demo/t.jsonl","cwd":"%s","permission_mode":"default","hook_event_name":"UserPromptSubmit","prompt":"%s","agent_type":"","session_title":"demo"}' "$1" "$2" "$3"
  fi
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

marker_value() { # marker_value [<session-id>]
  _m="$marker_dir/${1:-$sid}"
  if [ -f "$_m" ]; then
    awk 'NR == 1 { print $1; exit }' "$_m"
  else
    printf ''
  fi
}

later_than() { # later_than <a> <b> — a > b numerically
  awk -v a="$1" -v b="$2" 'BEGIN { exit (a + 0 > b + 0) ? 0 : 1 }'
}

presence_dirs() {
  find "$home/presence" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '
}

# --- static guards ----------------------------------------------------------

if grep -E -q '(^|[^a-z-])claude( |$|")' "$HOOK"; then
  fail "the hook invokes the CLI binary (REQ-H1.4: no model invocation)"
fi
grep -q 'jq' "$HOOK" && fail "the hook mentions jq (the payload is read by the hook's own awk)"
grep -q 'redacted:' "$HOOK" && fail "the hook carries its own redaction (REQ-G1.8: the log verb's helper is the one)"
echo "ok: no model invocation, no jq, no second redaction helper"

# --- no presence record for this session: a silent no-op --------------------

run_hook "$(payload "$sid" "$co" "hello")"
[ "$rc" = 0 ] || fail "no presence: exit $rc, expected 0"
[ ! -s "$tmp/out" ] || fail "no presence: the hook printed to stdout (that becomes model context)"
[ ! -e "$marker_dir" ] || fail "no presence: the attention marker directory was created"
[ ! -e "$log_file" ] || fail "no presence: a log line was written"
[ ! -e "$home/presence" ] || fail "no presence: the hook bootstrapped a presence surface"
echo "ok: with no presence surface the hook writes nothing and bootstraps nothing"

# A presence surface with somebody else's record: still not this session, and
# a prompt from a checkout no tower published from leaves no trace either.
with_env /bin/sh "$FP" publish --checkout "$co" --session-id "$other" --pid $$ >/dev/null \
  || fail "could not publish the peer's presence record"
dirs_before=$(presence_dirs)
run_hook "$(payload "$sid" "$co" "hello")"
[ "$rc" = 0 ] || fail "peer only: exit $rc, expected 0"
[ ! -e "$marker_dir" ] || fail "peer only: the marker directory was created for a session with no record"
[ ! -e "$log_file" ] || fail "peer only: a log line was written for a session with no record"
run_hook "$(payload "$sid" "$co2" "hello from elsewhere")"
[ "$rc" = 0 ] || fail "unrelated checkout, no record: exit $rc"
[ "$(presence_dirs)" = "$dirs_before" ] || fail "a session with no record grew the presence surface by prompting from another checkout"
echo "ok: another tower's record does not gate this session in, and no presence state is created for it"

# --- a record for this session: marker, then log --------------------------------

with_env /bin/sh "$FP" publish --checkout "$co" --session-id "$sid" --pid $$ >/dev/null \
  || fail "could not publish this session's presence record"
run_hook "$(payload "$sid" "$co" "first reply")"
[ "$rc" = 0 ] || fail "tower session: exit $rc, expected 0"
[ ! -s "$tmp/out" ] || fail "tower session: the hook printed to stdout"
[ -f "$marker_dir/$sid" ] || fail "tower session: no marker at tower-comms/attention/<session-id>"
m1=$(marker_value)
later_than "$m1" 0 || fail "tower session: marker holds '$m1', expected a positive epoch"
case "$m1" in
  *[!0-9]*) fail "tower session: the marker is not whole seconds: '$m1'" ;;
esac
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
case "$last" in
  *'"marker"'*) fail "tower session: a written marker must not be named on the line: $last" ;;
esac
[ ! -e "$marker_dir/$other" ] || fail "tower session: the peer's marker moved on this session's reply"
[ -z "$(git -C "$co" status --porcelain)" ] || fail "tower session: the hook touched the checkout"
echo "ok: a record gates the hook in; whole-second marker, one reply line with the tower identity, the peer untouched"

# Owner-only surface: the marker directory and file.
# shellcheck disable=SC2012
dmode=$(ls -ld "$marker_dir" | cut -c1-10)
[ "$dmode" = "drwx------" ] || fail "marker directory mode is $dmode, expected drwx------"
# shellcheck disable=SC2012
fmode=$(ls -l "$marker_dir/$sid" | cut -c1-10)
[ "$fmode" = "-rw-------" ] || fail "marker file mode is $fmode, expected -rw-------"
echo "ok: the marker directory and file are owner-only"

# A second reply advances the marker and appends a second line in sequence,
# carrying the payload's prompt id.
sleep 1
run_hook "$(payload "$sid" "$co" "second reply" "$pid_uuid")"
m2=$(marker_value)
later_than "$m2" "$m1" || fail "second reply: marker did not advance ($m1 -> $m2)"
[ "$(line_count "$log_file")" = 2 ] || fail "second reply: $(line_count "$log_file") log lines, expected 2"
seqs=$(awk -F'"seq":' '{ split($2, a, ","); print a[1] }' "$log_file" | tr '\n' ' ')
[ "$seqs" = "1 2 " ] || fail "second reply: sequence is '$seqs', expected '1 2 '"
case "$(tail -n 1 "$log_file")" in
  *"\"prompt_id\":\"$pid_uuid\""*) ;;
  *) fail "second reply: the prompt id is missing: $(tail -n 1 "$log_file")" ;;
esac
echo "ok: each reply advances the marker and lands in sequence with its prompt id"

# Thirty-six bytes in the UUID's shape are not a UUID unless 32 hex characters
# remain once the separators are removed, the grammar fleet-presence.sh reads.
dashy="0$(printf '%035d' 0 | tr 0 -)"
sleep 1
run_hook "$(payload "$sid" "$co" "third reply" "$dashy")"
[ "$rc" = 0 ] || fail "dash-heavy prompt id: exit $rc"
case "$(tail -n 1 "$log_file")" in
  *'"prompt_id"'*) fail "dash-heavy prompt id: a non-UUID prompt id reached the log: $(tail -n 1 "$log_file")" ;;
  *'"text":"third reply"'*) ;;
  *) fail "dash-heavy prompt id: the reply itself was not logged: $(tail -n 1 "$log_file")" ;;
esac
echo "ok: a dash-heavy non-UUID prompt id is dropped and the reply still counts"

# A clock stepped back does not move the marker: a value already later than
# now stays. That is the whole claim; two invocations racing on one session
# can still leave the earlier read, which read-then-rename cannot prevent and
# the harness does not produce.
future=$(($(date +%s) + 1000))
printf '%s\n' "$future" >"$marker_dir/$sid"
run_hook "$(payload "$sid" "$co" "after a clock step")"
[ "$(marker_value)" = "$future" ] || fail "stepped-back clock: a later value was overwritten with $(marker_value)"
date +%s >"$marker_dir/$sid"
echo "ok: a value already later than now survives a stepped-back clock"

# The same record with a dead pid still gates in: a session id is unique to
# its session, so the record is this session's own, and the running hook is
# what makes it live.
with_env /bin/sh "$FP" publish --checkout "$co" --session-id "$stale" --pid 4194303 >/dev/null \
  || fail "could not publish the dead-pid record"
run_hook "$(payload "$stale" "$co" "from a record with a dead handle")"
[ "$rc" = 0 ] || fail "dead-pid record: exit $rc"
[ -f "$marker_dir/$stale" ] || fail "dead-pid record: the session's own record did not gate it in"
echo "ok: the session's own record gates it in whatever its death handle says"

# A record published by --pid (the composite identity) is one the hook cannot
# match, so a prompt naming that session writes nothing.
with_env /bin/sh "$FP" publish --checkout "$co" --pid $$ >/dev/null || fail "could not publish a composite record"
before=$(line_count "$log_file")
run_hook "$(payload "$pid_uuid" "$co" "from a composite-identity tower")"
[ "$rc" = 0 ] || fail "composite record: exit $rc"
[ "$(line_count "$log_file")" = "$before" ] || fail "composite record: a reply was logged for a session with no UUID record"
[ ! -e "$marker_dir/$pid_uuid" ] || fail "composite record: a marker was written"
echo "ok: a composite-identity presence record does not gate the hook in"

# The gate is repository-scoped: this session's record on one repository does
# not gate a prompt submitted from a checkout of another.
m_before=$(marker_value)
before=$(line_count "$log_file")
sleep 1
run_hook "$(payload "$sid" "$co2" "prompt from another repository")"
[ "$rc" = 0 ] || fail "other repository: exit $rc"
[ "$(line_count "$log_file")" = "$before" ] || fail "other repository: a reply was logged"
[ "$(marker_value)" = "$m_before" ] || fail "other repository: the marker moved"
echo "ok: the gate is scoped to the repository the tower published on"

# --- the marker does not depend on the lock ---------------------------------

# With the lock held and a long wait configured, the marker must advance
# while the hook is still waiting for the log: a marker written after the
# log call would not.
printf 'tower_hook_lock_wait: 30s\n' >"$local_cfg"
PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FS" lock || fail "could not take the fleet lock for the ordering case"
sleep 1
m_before=$(marker_value)
printf '%s' "$(payload "$sid" "$co" "reply while the lock is held")" \
  | with_env /bin/sh "$HOOK" >"$tmp/out" 2>"$tmp/err" &
hook_pid=$!
advanced=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if later_than "$(marker_value)" "$m_before"; then
    advanced=1
    break
  fi
  sleep 0.25
done
kill -0 "$hook_pid" 2>/dev/null || fail "ordering: the hook finished before the lock was released, so the wait was not exercised"
PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FS" unlock
wait "$hook_pid" || fail "ordering: the hook exited non-zero"
[ "$advanced" = 1 ] || fail "ordering: the marker did not advance while the hook waited for the lock"
: >"$local_cfg"
echo "ok: the marker advances before the hook waits for the lock"

# --- the lock wait expires: line dropped and counted, turn not delayed ---------

printf 'tower_hook_lock_wait: 200ms\n' >"$local_cfg"
PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FS" lock || fail "could not take the fleet lock for the saturation case"
sleep 1
before=$(line_count "$log_file")
m_before=$(marker_value)
start=$(date +%s)
run_hook "$(payload "$sid" "$co" "reply under a busy lock")"
end=$(date +%s)
PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FS" unlock
[ "$rc" = 0 ] || fail "busy lock: exit $rc, expected 0 (the hook never delays or blocks the turn)"
[ ! -s "$tmp/out" ] || fail "busy lock: the hook printed to stdout"
later_than "$(marker_value)" "$m_before" || fail "busy lock: marker did not advance ($m_before -> $(marker_value))"
[ "$(line_count "$log_file")" = "$before" ] || fail "busy lock: a line was written unlocked"
[ "$(line_count "$dropped_file")" = 1 ] || fail "busy lock: dropped-line counter is $(line_count "$dropped_file"), expected 1"
[ $((end - start)) -le 5 ] || fail "busy lock: the hook took $((end - start))s on a 200ms bound"
echo "ok: under a busy lock the marker advances, the line is dropped and counted, the turn is not delayed"

# The bound is the knob, not a constant: a longer wait is honoured.
printf 'tower_hook_lock_wait: 4s\n' >"$local_cfg"
PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FS" lock || fail "could not take the fleet lock for the bound case"
start=$(date +%s)
run_hook "$(payload "$sid" "$co" "reply under a longer bound")"
end=$(date +%s)
PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FS" unlock
[ $((end - start)) -ge 3 ] || fail "bound: the hook returned after $((end - start))s on a 4s bound, so the knob is not what bounds the wait"
[ $((end - start)) -le 8 ] || fail "bound: the hook took $((end - start))s on a 4s bound"
[ "$(line_count "$dropped_file")" = 2 ] || fail "bound: dropped-line counter is $(line_count "$dropped_file"), expected 2"
: >"$local_cfg"
echo "ok: the lock wait is bounded by tower_hook_lock_wait itself"

# --- redaction through the log verb --------------------------------------------

token="ghp_""ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij0123"
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
echo "ok: escapes are flattened and a fake cwd inside the prompt is text"

# A prompt shaped like a JSON object is what the log verb refuses as nesting,
# and an empty prompt has no text: both replies still count, marked.
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
run_hook "$(payload "$sid" "$co" '  \t ')"
[ "$rc" = 0 ] || fail "empty prompt: exit $rc"
case "$(tail -n 1 "$log_file")" in
  *'"text_omitted":"empty"'*) ;;
  *) fail "empty prompt: the reply was not marked empty: $(tail -n 1 "$log_file")" ;;
esac
echo "ok: a JSON-shaped or empty prompt is logged as a reply with its text omitted"

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
run_hook "$(printf '{"session_id":"%s","transcript_path":"/t","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"truncated mid' "$sid" "$co")"
[ "$rc" = 0 ] || fail "payload cut inside the prompt: exit $rc, expected 0"
[ "$(line_count "$log_file")" = $((before + 1)) ] || fail "payload cut inside the prompt: expected one reply line"
case "$(tail -n 1 "$log_file")" in
  *'"text":"truncated mid"'*) ;;
  *) fail "payload cut inside the prompt: the partial text was not kept: $(tail -n 1 "$log_file")" ;;
esac
later_than "$(marker_value)" "$m_before" || fail "payload cut inside the prompt: the marker did not advance"
echo "ok: a payload cut inside the prompt still counts as a reply with the text read so far"

# A payload far past the bound is drained, so the harness's write never
# breaks on a closed pipe.
big=$(payload "$sid" "$co" "$(awk 'BEGIN { for (i = 0; i < 40000; i++) printf "word "; }')")
# PIPESTATUS is rewritten by the next command, so it is captured before any test.
set +e
printf '%s' "$big" | with_env /bin/sh "$HOOK" >"$tmp/out" 2>"$tmp/err"
ws=("${PIPESTATUS[@]}")
set -e
[ "${ws[1]}" = 0 ] || fail "oversize payload: exit ${ws[1]}"
[ "${ws[0]}" = 0 ] || fail "oversize payload: the writer was broken (exit ${ws[0]})"
echo "ok: an oversize payload is drained rather than left to break the writer"

# --- a marker that cannot be written is named on the reply line ---------------

# A widened marker directory is refused, never narrowed, and the reply says so.
chmod 0755 "$marker_dir"
m_before=$(marker_value)
sleep 1
run_hook "$(payload "$sid" "$co" "after widening")"
[ "$rc" = 0 ] || fail "widened dir: exit $rc, expected 0"
[ "$(marker_value)" = "$m_before" ] || fail "widened dir: the marker was written through a widened directory"
# shellcheck disable=SC2012
dmode=$(ls -ld "$marker_dir" | cut -c1-10)
[ "$dmode" = "drwxr-xr-x" ] || fail "widened dir: the hook narrowed the directory itself ($dmode)"
grep -q 'owner-only' "$tmp/err" || fail "widened dir: the refusal is not explained on stderr"
grep -q "$marker_dir" "$tmp/err" || fail "widened dir: the refusal does not name the directory"
case "$(tail -n 1 "$log_file")" in
  *'"kind":"reply"'*'"marker":"refused"'*) ;;
  *) fail "widened dir: the reply line does not name the refused marker: $(tail -n 1 "$log_file")" ;;
esac
chmod 0700 "$marker_dir"
echo "ok: a widened marker directory is refused with a reason, and the reply line says so"

# --- the fleet home itself is verified before the marker is written ------------

# The 0700 checks above are only as strong as the home that holds them, so the
# home is held to the same bar. A redirected home is refused whatever it points
# at, even when it points at the sound one: the redirect is the finding.
home_link="$tmp/home-link"
ln -s "$home" "$home_link"
m_before=$(marker_value)
sleep 1
rc=0
printf '%s' "$(payload "$sid" "$co" "through a redirected home")" \
  | PLANWRIGHT_FLEET_STATE_DIR="$home_link" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$tmp" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/sh "$HOOK" >"$tmp/out" 2>"$tmp/err" || rc=$?
[ "$rc" = 0 ] || fail "symlinked home: exit $rc, expected 0"
[ ! -s "$tmp/out" ] || fail "symlinked home: the hook printed to stdout"
[ "$(marker_value)" = "$m_before" ] || fail "symlinked home: the marker was written through a redirected home"
grep -q 'tower-reply-hook: security: the fleet home .* is a symlink' "$tmp/err" \
  || fail "symlinked home: the hook did not say it refused a redirected home: $(cat "$tmp/err")"
rm -f "$home_link"
echo "ok: a fleet home that is a symlink is refused before the marker is written"

# A foreign-owned home, and a home that is not a directory at all, through an
# `ls` shim that answers for the home path only: both are states no unprivileged
# test can create, and both are what a home swapped under the hook looks like.
real_ls=$(command -v ls)
home_shim="$tmp/home-shim"
mkdir -p "$home_shim"
shim_home_mode() { # shim_home_mode <ls-line-prefix>
  cat >"$home_shim/ls" <<EOF
#!/bin/sh
case "\$*" in
  *"$home") echo "$1 1 0 Jan  1 00:00 $home" ;;
  *) exec "$real_ls" "\$@" ;;
esac
EOF
  chmod +x "$home_shim/ls"
}

for case_name in foreign-owner not-a-directory; do
  case "$case_name" in
    foreign-owner) shim_home_mode "drwx------ 1 99999 99999" ;;
    not-a-directory) shim_home_mode "-rw------- 1 $(id -u) $(id -u)" ;;
  esac
  m_before=$(marker_value)
  sleep 1
  rc=0
  printf '%s' "$(payload "$sid" "$co" "home is $case_name")" \
    | PATH="$home_shim:$PATH" with_env /bin/sh "$HOOK" >"$tmp/out" 2>"$tmp/err" || rc=$?
  [ "$rc" = 0 ] || fail "$case_name home: exit $rc, expected 0"
  [ ! -s "$tmp/out" ] || fail "$case_name home: the hook printed to stdout"
  [ "$(marker_value)" = "$m_before" ] || fail "$case_name home: the marker was written under a $case_name home"
  grep -q 'tower-reply-hook: security: the fleet home' "$tmp/err" \
    || fail "$case_name home: the hook did not say it refused the home: $(cat "$tmp/err")"
done
rm -f "$home_shim/ls"
echo "ok: a foreign-owned home and a home that is not a directory are both refused"

# The two write columns, the pair tests/test-tower-queue-log-lock.sh holds its
# own check_home to: a home anyone but its owner can write to is one where the
# 0700 surface below it can be swapped between the checks above and the write
# they guard, and a home others may merely read or traverse is the ordinary
# shape a default umask produces. A glob narrowed by one column would refuse
# every such home, so the 0755 half is the half that catches over-narrowing.
home_mode=$(stat -c '%a' "$home" 2>/dev/null || stat -f '%Lp' "$home")
chmod 0770 "$home"
m_before=$(marker_value)
sleep 1
run_hook "$(payload "$sid" "$co" "the home went group-writable")"
[ "$rc" = 0 ] || fail "group-writable home: exit $rc, expected 0"
[ ! -s "$tmp/out" ] || fail "group-writable home: the hook printed to stdout"
[ "$(marker_value)" = "$m_before" ] || fail "group-writable home: the marker was written under a group-writable home"
grep -q 'tower-reply-hook: security: the fleet home .* is writable beyond its owner' "$tmp/err" \
  || fail "group-writable home: the hook did not say it refused the home: $(cat "$tmp/err")"
chmod 0755 "$home"
before=$(line_count "$log_file")
sleep 1
run_hook "$(payload "$sid" "$co" "the home is readable by others")"
[ "$rc" = 0 ] || fail "0755 home: exit $rc, expected 0"
later_than "$(marker_value)" "$m_before" || fail "0755 home: a home others may only read was refused ($(cat "$tmp/err"))"
[ "$(line_count "$log_file")" = $((before + 1)) ] || fail "0755 home: the reply was not logged"
chmod "$home_mode" "$home"
echo "ok: a group-writable home is refused and a world-readable one is not"

# And the sound home still writes: the check refuses a bad home, not every home.
m_before=$(marker_value)
before=$(line_count "$log_file")
sleep 1
run_hook "$(payload "$sid" "$co" "the home is sound again")"
[ "$rc" = 0 ] || fail "sound home: exit $rc, expected 0"
later_than "$(marker_value)" "$m_before" || fail "sound home: the marker did not advance ($m_before -> $(marker_value))"
[ "$(line_count "$log_file")" = $((before + 1)) ] || fail "sound home: the reply was not logged"
case "$(tail -n 1 "$log_file")" in
  *'"marker"'*) fail "sound home: a written marker must not be named on the line: $(tail -n 1 "$log_file")" ;;
esac
echo "ok: a sound fleet home still gets the marker"

# A failed rename leaves no scratch file behind and is named on the line.
stub="$tmp/stub-bin"
mkdir -p "$stub"
printf '#!/bin/sh\nexit 1\n' >"$stub/mv"
chmod +x "$stub/mv"
rc=0
printf '%s' "$(payload "$sid" "$co" "write fails")" | PATH="$stub:$PATH" with_env /bin/sh "$HOOK" >"$tmp/out" 2>"$tmp/err" || rc=$?
[ "$rc" = 0 ] || fail "failed write: exit $rc"
[ -z "$(find "$marker_dir" -name ".$sid.*" 2>/dev/null)" ] || fail "failed write: a scratch file was left in the marker directory"
case "$(tail -n 1 "$log_file")" in
  *'"marker":"failed"'*) ;;
  *) fail "failed write: the reply line does not name the failed marker: $(tail -n 1 "$log_file")" ;;
esac
echo "ok: a failed marker write leaves no scratch file and is named on the reply line"

# --- the scorecard reads every line the hook wrote --------------------------------

report=$(with_env /bin/sh "$TQ" report --log "$log_file" --now "$(date +%s)" --window 1h) || fail "report over the hook's lines failed"
for want in "malformed	0" "dropped_lines	2"; do
  case "$report" in
    *"$want"*) ;;
    *) fail "report: expected '$want' in: $report" ;;
  esac
done
echo "ok: every line parses and the dropped lines reach the scorecard"

echo "ALL PASS: tower reply hook"
