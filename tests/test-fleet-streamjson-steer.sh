#!/bin/bash
# Tests for the tower's steer path on the stream-json rung and for the write
# discipline every frame into a worker's stdin fifo goes through
# (scripts/fleet-streamjson.sh `steer`, the frame check, and the `answer` and
# launch writers that share it).
#
#   s1 (REQ-G1.1, REQ-G1.9): a steer reaches a live worker as one attributed user
#       turn, the message text verbatim and never evaluated, and the worker keeps
#       running and keeps reading: a second steer lands on the same process.
#   s2 (REQ-G1.2): the frame check refuses an unterminated frame, a multi-line
#       one, a raw control byte, and invalid JSON, including the shape that
#       killed two workers (an unterminated frame running into the next one).
#   s3 (REQ-G1.2): an answer body that would make an invalid or smuggling frame
#       is refused before the channel is touched, and writes no byte to a live
#       worker. The refusal inside frame_send itself cannot be reached through
#       a verb once that validation passes; s4's audit is its coverage.
#   s4 (REQ-G1.1, REQ-G1.3): source audits. No keystroke-impersonation path, every
#       fifo write goes through the checked writer, the steer header is the one
#       the buffer-paste relay carries, and the fleet docs name steer primary.
#   s5 (REQ-K1.3, REQ-K1.4): hostile handles and message paths are refused or
#       treated as data, and steer echoes nothing untrusted: no control byte
#       from a message ever reaches its output.
#   s6 (REQ-G1.2): an allow whose spliced tool input carries a raw DEL still
#       makes a frame the check accepts, with the input intact.
#
# Hermetic: the fleet home and the CLI seam are case-local, the CLI is a shim
# that records its stdin. Runs standalone under /bin/bash (bash 3.2).
# shellcheck disable=SC2016 # s4's audit patterns are literal source text, not expansions
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SJ="$here/../scripts/fleet-streamjson.sh"
RELAY="$here/../scripts/orchestrate-relay.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SJ" ] || fail "scripts/fleet-streamjson.sh missing or not executable"
command -v jq >/dev/null 2>&1 || fail "jq is required: the launch preflight runs the auto-approve hook"

tmp=$(mktemp -d)
tab=$(printf '\t')
live_pids=''
cleanup() {
  for cl_p in $live_pids; do
    kill "$cl_p" 2>/dev/null || :
  done
  rm -rf "$tmp"
}
trap cleanup EXIT

# The shim worker: records every stdin line, emits the event file once, then
# keeps reading until stdin closes or the watchdog fires.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
if [ -n "${SHIM_EVENTS:-}" ]; then
  cat "$SHIM_EVENTS"
fi
(sleep "${SHIM_WATCHDOG:-30}" && kill "$$" 2>/dev/null) &
while IFS= read -r line; do
  printf '%s\n' "$line" >>"$SHIM_RECORD_DIR/stdin"
done
SHIM
chmod +x "$tmp/bin/claude"

env_scrub=(
  -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME
  -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT
  -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS
  -u PLANWRIGHT_STREAMJSON_PENDING_AGE -u PLANWRIGHT_STREAMJSON_ALARM_TICK
  -u PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT
)

# senv <home> <record-dir> [VAR=val...] -- <args...>
senv() {
  se_home=$1
  se_rec=$2
  shift 2
  se_pre=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    se_pre+=("$1")
    shift
  done
  shift
  env "${env_scrub[@]}" \
    PLANWRIGHT_FLEET_STATE_DIR="$se_home" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" \
    SHIM_RECORD_DIR="$se_rec" \
    ${se_pre[@]+"${se_pre[@]}"} /bin/sh "$SJ" "$@"
}

wait_until() {
  wu_n=$1
  shift
  wu_i=0
  while [ "$wu_i" -lt "$wu_n" ]; do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
    wu_i=$((wu_i + 1))
  done
  return 1
}

lines_of() {
  if [ -f "$1" ]; then
    wc -l <"$1" | tr -d ' '
  else
    echo 0
  fi
}

# lines_cmp <file> <test-op> <n> — for wait_until, which re-runs its command:
# the count has to be taken inside it, not expanded once by the caller.
lines_cmp() {
  test "$(lines_of "$1")" "$2" "$3"
}

# start_worker <home> <rec> <handle> [VAR=val...] — a live foreground-supervised
# shim worker, waited on until the initial prompt has reached it.
start_worker() {
  sw_home=$1
  sw_rec=$2
  sw_h=$3
  shift 3
  mkdir -p "$sw_rec"
  printf 'begin\n' >"$tmp/prompt-$sw_h"
  senv "$sw_home" "$sw_rec" "$@" -- \
    launch "$sw_h" fleet-lifecycle-closure:9 --prompt-file "$tmp/prompt-$sw_h" --foreground \
    >/dev/null 2>&1 &
  live_pids="$live_pids $!"
  wait_until 100 grep -q '"type":"user"' "$sw_rec/stdin" \
    || fail "$sw_h: the worker never received its initial prompt"
}

sid='11111111-2222-3333-4444-555555555555'
req='aaaa1111-bbbb-cccc-dddd-eeee00000009'
line_init='{"type":"system","subtype":"init","cwd":"/x","session_id":"'$sid'","tools":[]}'
line_perm='{"type":"control_request","request_id":"'$req'","request":{"subtype":"can_use_tool","tool_name":"Write","input":{"file_path":"/x/y.txt","content":"hi"},"tool_use_id":"t1"}}'
printf '%s\n%s\n' "$line_init" "$line_perm" >"$tmp/ev-perm"

# ---------------------------------------------------------------------------
# s1 (REQ-G1.1, REQ-G1.9): attributed, verbatim, never evaluated, and the
#     worker keeps going.
# ---------------------------------------------------------------------------
home="$tmp/h1"
rec="$tmp/r1"
start_worker "$home" "$rec" sjs1
wdir="$home/streamjson/sjs1"
pid_before=$(cat "$wdir/worker.pid")
# Every shell metacharacter a splice would act on, a quote of each kind, a
# backslash, and a TAB (kept, as a JSON escape). `pwned` must never appear.
msg="stop after the gate: \$(touch $tmp/pwned) \`touch $tmp/pwned\` ; touch $tmp/pwned | & > < * ? ' \" \\ ${tab}end"
printf '%s\n' "$msg" >"$tmp/steer1"
out=$(senv "$home" "$rec" -- steer sjs1 --message-file "$tmp/steer1") \
  || fail "s1: steer exited non-zero: $out"
case $out in
  "steered sjs1 "[0-9]*) : ;;
  *) fail "s1: unexpected steer output: $out" ;;
esac
wait_until 100 lines_cmp "$rec/stdin" -ge 2 \
  || fail "s1: the steer never reached the worker's stdin"
sed -n 2p "$rec/stdin" >"$tmp/s1frame"
jq -e . "$tmp/s1frame" >/dev/null 2>&1 || fail "s1: the delivered frame is not valid JSON: $(cat "$tmp/s1frame")"
[ "$(jq -r '.type + "/" + .message.role' "$tmp/s1frame")" = "user/user" ] \
  || fail "s1: the steer must be a user turn"
got=$(jq -r '.message.content[0].text' "$tmp/s1frame")
want=$(printf '[planwright tower relay -> sjs1]\n%s' "$msg")
[ "$got" = "$want" ] || fail "s1: the message must arrive verbatim under the attribution header; got: $got"
[ -e "$tmp/pwned" ] && fail "s1: message text was evaluated as shell"
# The same worker process, still reading: a second steer lands on it.
printf 'second\n' >"$tmp/steer1b"
senv "$home" "$rec" -- steer sjs1 --message-file "$tmp/steer1b" >/dev/null \
  || fail "s1: the second steer exited non-zero"
wait_until 100 lines_cmp "$rec/stdin" -ge 3 \
  || fail "s1: the worker stopped consuming after the first steer"
[ "$(cat "$wdir/worker.pid")" = "$pid_before" ] || fail "s1: the worker was restarted by a steer"
kill -0 "$pid_before" 2>/dev/null || fail "s1: the worker died after being steered"
[ "$(lines_of "$wdir/steers")" = 2 ] || fail "s1: each steer should leave one receipt row"
echo "ok: s1 steer delivers an attributed, verbatim, unevaluated user turn to a live worker that keeps running (REQ-G1.1, REQ-G1.9)"

# ---------------------------------------------------------------------------
# s2 (REQ-G1.2): the frame check, fixture by fixture.
# ---------------------------------------------------------------------------
fc() {
  env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$tmp/h2" /bin/sh "$SJ" _frame-check "$1" 2>&1
}
accept() {
  printf '%s' "$2" >"$tmp/f"
  a_out=$(fc "$tmp/f")
  [ "$a_out" = "frame ok" ] || fail "s2: should accept $1, got: $a_out"
}
refuse() {
  printf '%s' "$2" >"$tmp/f"
  r_out=$(fc "$tmp/f")
  case $r_out in
    "frame refused: $3"*) : ;;
    *) fail "s2: should refuse $1 as '$3', got: $r_out" ;;
  esac
}
nl='
'
accept "a user frame" '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"a\nb \"q\" \\ \/ é"}]}}'"$nl"
accept "an empty object" "{}$nl"
accept "numbers, literals, nesting, and spaces" '{ "a" : [ -1.5e3 , 0 , 10 , true , false , null , { } , [ ] ] }'"$nl"
accept "raw UTF-8 in a string" '{"t":"caf'"$(printf '\303\251')"'"}'"$nl"
refuse "an unterminated frame" '{"type":"user"}' 'unterminated'
refuse "an empty file" '' 'unterminated'
refuse "two frames in one write" "{}$nl{}$nl" 'multi-line'
# obs:33c821b8: a frame written without its newline runs into the supervisor's
# next line, and the worker reads one line that is two objects.
refuse "an unterminated frame followed by the next one" '{"type":"user","message":{}}{"type":"control_response"}'"$nl" 'invalid JSON'
refuse "a raw TAB inside a string" "{\"t\":\"a$(printf '\t')b\"}$nl" 'raw control byte'
refuse "a raw ESC" "{\"t\":\"$(printf '\033')[2J\"}$nl" 'raw control byte'
refuse "a raw DEL" "{\"t\":\"a$(printf '\177')b\"}$nl" 'raw control byte'
refuse "a missing close brace" '{"a":1'"$nl" 'invalid JSON'
refuse "a trailing comma" '{"a":1,}'"$nl" 'invalid JSON'
refuse "a top-level array" "[]$nl" 'invalid JSON'
refuse "a top-level string" '"x"'"$nl" 'invalid JSON'
refuse "single quotes" "{'a':1}$nl" 'invalid JSON'
refuse "an unknown escape" '{"a":"\x"}'"$nl" 'invalid JSON'
refuse "a short unicode escape" '{"a":"\u12"}'"$nl" 'invalid JSON'
refuse "a leading zero" '{"a":01}'"$nl" 'invalid JSON'
refuse "a bare word" '{"a":undefined}'"$nl" 'invalid JSON'
refuse "a non-string key" '{1:2}'"$nl" 'invalid JSON'
refuse "a missing colon" '{"a" 1}'"$nl" 'invalid JSON'
refuse "adjacent values" '{"a":[1 2]}'"$nl" 'invalid JSON'
refuse "trailing garbage" '{"a":1} x'"$nl" 'invalid JSON'
deep=$(awk 'BEGIN { for (i = 0; i < 100; i++) printf "["; for (i = 0; i < 100; i++) printf "]" }')
refuse "nesting past the depth cap" "{\"a\":$deep}$nl" 'invalid JSON'
fc "$tmp/no-such-frame" | grep -q '^frame refused' || fail "s2: a missing frame file must be refused"
# A path shaped like an awk assignment is still the file to judge, never a
# cue to read stdin instead.
mkdir -p "$tmp/cwd2"
printf 'not json\n' >"$tmp/cwd2/k=v"
out=$(cd "$tmp/cwd2" && printf '{}\n' | env "${env_scrub[@]}" /bin/sh "$SJ" _frame-check 'k=v' 2>&1)
case $out in
  "frame refused: invalid JSON") : ;;
  *) fail "s2: a name=value path must be judged by its own content, got: $out" ;;
esac
echo "ok: s2 the frame check refuses unterminated, multi-line, control-byte, and invalid frames, including the run-together shape (REQ-G1.2)"

# ---------------------------------------------------------------------------
# s3 (REQ-G1.2): a refused frame writes nothing to a live worker's stdin.
# ---------------------------------------------------------------------------
home="$tmp/h3"
rec="$tmp/r3"
start_worker "$home" "$rec" sjs3 SHIM_EVENTS="$tmp/ev-perm"
wdir3="$home/streamjson/sjs3"
wait_until 100 grep -q "^$req" "$wdir3/journal" || fail "s3: the pending journal row never appeared"
before=$(lines_of "$rec/stdin")
printf '{"behavior":"allow"\n' >"$tmp/bad-resp"
senv "$home" "$rec" -- answer sjs3 "$req" --response-file "$tmp/bad-resp" >/dev/null 2>"$tmp/s3.err"
[ $? -eq 2 ] || fail "s3: an answer whose frame is invalid JSON must be refused (exit 2)"
grep -q 'refused' "$tmp/s3.err" || fail "s3: the refusal must say so, got: $(cat "$tmp/s3.err")"
grep -q "pending" "$wdir3/journal" || fail "s3: a refused answer must leave the request pending"
# A body that is not one object on its own, though the frame it makes parses.
printf '{"behavior":"allow"},"smuggled":{"k":1}\n' >"$tmp/splice-resp"
senv "$home" "$rec" -- answer sjs3 "$req" --response-file "$tmp/splice-resp" >/dev/null 2>&1
[ $? -eq 2 ] || fail "s3: a response body that closes the envelope early must be refused (exit 2)"
# A valid answer after it still delivers: the refusal left the channel usable.
senv "$home" "$rec" -- answer sjs3 "$req" --allow >/dev/null || fail "s3: the follow-up answer failed"
wait_until 100 grep -q control_response "$rec/stdin" || fail "s3: the follow-up answer never arrived"
[ "$(lines_of "$rec/stdin")" = $((before + 1)) ] \
  || fail "s3: exactly one frame should have reached the worker, stdin: $(cat "$rec/stdin")"
while IFS= read -r s3_line; do
  printf '%s\n' "$s3_line" | jq -e . >/dev/null 2>&1 || fail "s3: a line on the worker's stdin is not valid JSON: $s3_line"
done <"$rec/stdin"
echo "ok: s3 an answer body that would make a bad frame is refused before any byte reaches the worker, and the channel stays usable (REQ-G1.2)"

# ---------------------------------------------------------------------------
# s4 (REQ-G1.1, REQ-G1.3): source audits.
# ---------------------------------------------------------------------------
code=$(grep -v '^[[:space:]]*#' "$SJ")
printf '%s\n' "$code" | grep -nE 'send-keys|paste-buffer|load-buffer|tmux' \
  && fail "s4: fleet-streamjson.sh must carry no keystroke-impersonation path"
# Every line that names a worker's stdin fifo, or its held fd 3, is one of a
# known set: creating, removing, or opening it, testing it, and the two writes.
# Anything else naming it is a new writer, however it spells the redirect.
fifo_lines=$(printf '%s\n' "$code" | grep -E 'in\.fifo|>&3' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
want_lines=$(
  cat <<'LINES'
rm -f "$sv_dir/in.fifo" "$sv_dir/out.fifo"
mkfifo "$sv_dir/in.fifo" "$sv_dir/out.fifo" || return 2
"$@" <"$sv_dir/in.fifo" >"$sv_dir/out.fifo" 2>>"$sv_dir/stderr.log" &
exec 3>"$sv_dir/in.fifo"
cat "$sv_init" >&3 2>/dev/null &
[ -p "$1/in.fifo" ] || return 3
cat "$2" >>"$1/in.fifo" 2>/dev/null || return 1
scratch_patterns='in.fifo out.fifo .init.* .frame.* .journal.* .session.* .pid.* *.broken.*'
LINES
)
[ "$(printf '%s\n' "$fifo_lines" | sort)" = "$(printf '%s\n' "$want_lines" | sort)" ] || fail "s4: an unlisted line names the worker's stdin fifo: $fifo_lines"
# The launch frame's write is safe only because build_initial_msg checked it.
printf '%s\n' "$code" | grep -qF 'bi_why=$(frame_check "$2")' \
  || fail "s4: build_initial_msg must check the launch frame"
[ "$(printf '%s\n' "$code" | grep -cF 'frame_send "$dir" ')" = 2 ] \
  || fail "s4: answer and steer must each write through frame_send"
grep -qF '`steer` is the primary steer on the stream-json rung' "$here/../docs/fleet.md" \
  || fail "s4: docs/fleet.md must name steer as the primary steer for this rung"
grep -qF "[planwright tower relay -> \$handle]" "$RELAY" \
  || fail "s4: the buffer-paste relay's attribution header changed"
printf '%s\n' "$code" | grep -qF 'planwright tower relay -> %s]' \
  || fail "s4: steer must carry the buffer-paste relay's attribution header"
echo "ok: s4 no impersonation path, every fifo write is checked, and steer shares the relay's header (REQ-G1.1, REQ-G1.3)"

# ---------------------------------------------------------------------------
# s5 (REQ-K1.3, REQ-K1.4): hostile input at every entry point.
# ---------------------------------------------------------------------------
for h in '../sjs1' '-x' 'a;b' "a$(printf '\033')b" "$(awk 'BEGIN { for (i = 0; i < 129; i++) printf "a" }')" '..'; do
  senv "$tmp/h1" "$tmp/r1" -- steer "$h" --message-file "$tmp/steer1b" >/dev/null 2>&1
  [ $? -eq 2 ] || fail "s5: steer must refuse the hostile handle '$h'"
done
# A relative message path that looks like an option is still a file name.
mkdir -p "$tmp/cwd5"
printf 'from a dashed file\n' >"$tmp/cwd5/-n"
before=$(lines_of "$tmp/r1/stdin")
out=$(cd "$tmp/cwd5" && senv "$tmp/h1" "$tmp/r1" -- steer sjs1 --message-file -n 2>&1) \
  || fail "s5: a dash-leading message path must be read as a file, got: $out"
[ "$out" = "steered sjs1 $(wc -c <"$tmp/cwd5/-n" | tr -d ' ')" ] \
  || fail "s5: the dash-named file must be measured as a file, not parsed as an option: $out"
wait_until 100 lines_cmp "$tmp/r1/stdin" -gt "$before" \
  || fail "s5: the dash-named message never arrived"
tail -n 1 "$tmp/r1/stdin" | jq -r '.message.content[0].text' | grep -q 'from a dashed file' \
  || fail "s5: the dash-named file's content was not what arrived"
# Control bytes in the message reach the worker as data, never as terminal
# output: nothing steer prints carries one.
printf 'clear\033[2J\007 me\n' >"$tmp/steer5"
out=$(senv "$tmp/h1" "$tmp/r1" -- steer sjs1 --message-file "$tmp/steer5" 2>&1) \
  || fail "s5: a control-byte message should still deliver, got: $out"
[ "$(printf '%s' "$out" | LC_ALL=C tr -d '\000-\037\177')" = "$out" ] \
  || fail "s5: steer echoed a control byte"
wait_until 100 lines_cmp "$tmp/r1/stdin" -gt $((before + 1)) \
  || fail "s5: the control-byte message never arrived"
tail -n 1 "$tmp/r1/stdin" | jq -e . >/dev/null 2>&1 \
  || fail "s5: the control-byte message did not arrive as valid JSON"
echo "ok: s5 hostile handles are refused, a dashed path is data, and steer echoes nothing untrusted (REQ-K1.3, REQ-K1.4)"

# ---------------------------------------------------------------------------
# s6 (REQ-G1.2): `--allow` splices the worker's own tool input into the frame.
#     JSON allows a raw DEL in a string and the CLI emits it unescaped, so the
#     splice must still make a frame the check accepts, with the input intact.
# ---------------------------------------------------------------------------
home="$tmp/h6"
rec="$tmp/r6"
del=$(printf '\177')
req6='aaaa1111-bbbb-cccc-dddd-eeee00000006'
line_del='{"type":"control_request","request_id":"'$req6'","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"echo a'$del'b"},"tool_use_id":"t6"}}'
printf '%s\n%s\n' "$line_init" "$line_del" >"$tmp/ev-del"
start_worker "$home" "$rec" sjs6 SHIM_EVENTS="$tmp/ev-del"
wait_until 100 grep -q "^$req6" "$home/streamjson/sjs6/journal" || fail "s6: the pending journal row never appeared"
out=$(senv "$home" "$rec" -- answer sjs6 "$req6" --allow 2>&1) \
  || fail "s6: --allow over a tool input carrying DEL must deliver, got: $out"
wait_until 100 grep -q control_response "$rec/stdin" || fail "s6: the allow never reached the worker"
got=$(grep control_response "$rec/stdin" | jq -r '.response.response.updatedInput.command')
[ "$got" = "echo a${del}b" ] || fail "s6: the spliced input must decode to the original command, got: $got"
echo "ok: s6 --allow over a worker input carrying a raw DEL delivers it intact as a valid frame (REQ-G1.2)"

for sp in "$tmp/h1:sjs1" "$tmp/h3:sjs3" "$tmp/h6:sjs6"; do
  senv "${sp%%:*}" "$tmp/r1" -- stop "${sp##*:}" --grace 1 >/dev/null 2>&1 || :
done
echo "all fleet-streamjson-steer tests passed"
