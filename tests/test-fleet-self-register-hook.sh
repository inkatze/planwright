#!/bin/bash
# The worker's self-registration, end to end through the plugin's own
# SessionStart entry (fleet-messaging Task 4; D-8, D-12, REQ-B1.1, REQ-B1.2):
# the command hooks/hooks.json registers is run as registered, against a
# registry row the dispatch wrote and a captured per-session record.
#   s1  hooks.json registers `fleet-messaging.sh self-register` on SessionStart
#       for startup and resume
#   s2  with the worker identity and the record present, the row's name column
#       equals the record's name and its inbox column the basename of its
#       messagingSocketPath, both bare values
#   s3  with the hook never run, the row keeps both sentinels: send
#       --to-worker refuses that worker with an empty post log (under an
#       available probe), and no name-keyed read matches it (the sentinel is
#       never a name, which is what the start-of-tower subscribe pass keys on)
#   s4  a name the session-name screen admits but the registry charset refuses
#       leaves the name sentinel in place and still records the inbox
#   s4b a record with no usable socket path records the name alone (exit 2)
#   s5  in a tower session (no worker identity) the hook writes nothing
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$here/.." && pwd -P)
FS="$ROOT/scripts/fleet-state.sh"
FM="$ROOT/scripts/fleet-messaging.sh"

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}
ok() { echo "ok $1"; }

command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to read hooks/hooks.json" >&2
  exit 1
}

tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
TAB=$(printf '\t')
home="$tmp/home"
fleet="$tmp/fleet"
socks="$tmp/socks"
mkdir -p "$home/.claude/sessions" "$fleet" "$socks" "$tmp/repo"
chmod 700 "$fleet"

# --- s1 -----------------------------------------------------------------------
f0=$fails
for m in startup resume; do
  n=$(jq --arg m "$m" '[.hooks.SessionStart[] | select(.matcher == $m) | .hooks[].command
    | select(test("scripts/fleet-messaging\\.sh self-register$"))] | length' "$ROOT/hooks/hooks.json")
  [ "$n" = 1 ] || fail "s1: hooks.json registers self-register $n times for SessionStart '$m'"
done
cmd=$(jq -r '[.hooks.SessionStart[] | select(.matcher == "startup") | .hooks[].command
  | select(test("self-register"))][0]' "$ROOT/hooks/hooks.json")
[ "$fails" = "$f0" ] && ok "s1 the SessionStart entry runs self-register on startup and resume"

# hook <pid> [VAR=val...] — run the registered command as the harness would:
# through sh, the plugin root substituted from the environment, the
# SessionStart payload on stdin.
hook() {
  local pid=$1
  shift
  env -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE -u CLAUDE_CONFIG_DIR -u PLANWRIGHT_ROOT \
    CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$home" PLANWRIGHT_FLEET_STATE_DIR="$fleet" CLAUDE_PID="$pid" "$@" \
    sh -c "$cmd" <"$here/fixtures/hook-payloads/SessionStart.json"
}

record() {
  # record <pid> <name> <socket path>
  printf '{"pid":%s,"sessionId":"00000000-0000-4000-8000-000000000000","cwd":"/work","messagingSocketPath":"%s","name":"%s","nameSource":"derived","status":"idle"}\n' \
    "$1" "$3" "$2" >"$home/.claude/sessions/$1.json"
}

reg() { PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$FS" register "$1" demo:4 --backend tmux >/dev/null; }
last() { awk -F"$TAB" -v w="$1" '($2 "") == (w "") { l = $0 } END { print l }' "$fleet/registry"; }

# --- s2 -----------------------------------------------------------------------
f0=$fails
reg tmux-demo-task-4
record 4242 tmux-demo-task-4 "$socks/4242.sock"
hook 4242 PLANWRIGHT_WORKER_HANDLE=tmux-demo-task-4 PLANWRIGHT_WORKER_SCOPE=demo:4 2>"$tmp/err" \
  || fail "s2: the hook exited non-zero: $(cat "$tmp/err")"
row=$(last tmux-demo-task-4)
[ "$(printf '%s\n' "$row" | cut -f8)" = tmux-demo-task-4 ] || fail "s2: the name column is not the record's name: $row"
[ "$(printf '%s\n' "$row" | cut -f9)" = 4242.sock ] || fail "s2: the inbox column is not the socket basename: $row"
[ "$(printf '%s\n' "$row" | awk -F"$TAB" '{ print NF }')" = 9 ] || fail "s2: the amended row is not nine columns: $row"
[ "$fails" = "$f0" ] && ok "s2 the hook records the observed name and inbox basename as bare values"

# --- s3 -----------------------------------------------------------------------
f0=$fails
reg tmux-demo-task-5
row=$(last tmux-demo-task-5)
[ "$(printf '%s\n' "$row" | cut -f8-9)" = "-${TAB}-" ] || fail "s3: an unregistered session's row lost its sentinels: $row"
: >"$socks/tower.sock"
: >"$tmp/post.log"
cat >"$tmp/post-seam" <<'SEAM'
#!/bin/sh
printf 'CALL %s\n' "$*" >>"$PLANWRIGHT_MESSAGING_POST_LOG"
cat >>"$PLANWRIGHT_MESSAGING_POST_LOG"
SEAM
chmod +x "$tmp/post-seam"
printf 'hello\n' >"$tmp/msg"
mx() {
  env -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE -u CLAUDE_CONFIG_DIR -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT \
    HOME="$home" PLANWRIGHT_FLEET_STATE_DIR="$fleet" PLANWRIGHT_CONFIG_DEFAULTS="$ROOT/config/defaults.yml" \
    PLANWRIGHT_REPO_ROOT="$tmp/repo" PLANWRIGHT_ADOPTER_OVERLAY="$tmp/no-adopter" PLANWRIGHT_LOCAL_CONFIG="" \
    PLANWRIGHT_TEST_SEAM=1 PLANWRIGHT_MESSAGING_POST="$tmp/post-seam" PLANWRIGHT_MESSAGING_POST_LOG="$tmp/post.log" \
    CLAUDE_CODE_MESSAGING_SOCKET="$socks/tower.sock" PLANWRIGHT_MESSAGING_INBOUND=accept \
    /bin/sh "$FM" "$@"
}
got=$(mx probe --cli-version 2.1.296 --socket-type socket 2>"$tmp/err") || true
[ "$got" = available ] || fail "s3: the fixture's probe is not available ($got: $(cat "$tmp/err")), so the refusal below would prove nothing"
rc=0
mx send --to-worker tmux-demo-task-5 --message-file "$tmp/msg" --cli-version 2.1.296 --socket-type socket \
  >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 6 ] || fail "s3: send to a worker with no recorded inbox exited $rc, not 6"
grep -q "recorded no inbox" "$tmp/err" || fail "s3: the refusal does not say the inbox is unrecorded: $(cat "$tmp/err")"
[ ! -s "$tmp/post.log" ] || fail "s3: the refused send posted: $(cat "$tmp/post.log")"
rc=0
mx notice-read - >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "s3: the name sentinel matched a row (exit $rc)"
mx notice-read nobody-has-this-name >/dev/null 2>"$tmp/err"
grep -q "no registry row carries" "$tmp/err" || fail "s3: a name-keyed read did not reach the registry: $(cat "$tmp/err")"
[ "$fails" = "$f0" ] && ok "s3 a worker whose hook never ran keeps its sentinels and is unaddressable"

# --- s4 -----------------------------------------------------------------------
f0=$fails
reg tmux-demo-task-6
record 4246 "fleet task six" "$socks/4246.sock"
rc=0
hook 4246 PLANWRIGHT_WORKER_HANDLE=tmux-demo-task-6 PLANWRIGHT_WORKER_SCOPE=demo:6 2>"$tmp/err" || rc=$?
[ "$rc" != 0 ] || fail "s4: a dropped name still exited 0"
row=$(last tmux-demo-task-6)
[ "$(printf '%s\n' "$row" | cut -f8)" = - ] || fail "s4: a name the registry refuses replaced the sentinel: $row"
[ "$(printf '%s\n' "$row" | cut -f9)" = 4246.sock ] || fail "s4: the inbox was not recorded beside a dropped name: $row"
[ "$fails" = "$f0" ] && ok "s4 a name the registry charset refuses keeps the sentinel; the inbox still lands"

# --- s4b: no usable socket path ----------------------------------------------
f0=$fails
reg tmux-demo-task-7
record 4247 tmux-demo-task-7 "relative/4247.sock"
rc=0
hook 4247 PLANWRIGHT_WORKER_HANDLE=tmux-demo-task-7 PLANWRIGHT_WORKER_SCOPE=demo:7 2>"$tmp/err" || rc=$?
[ "$rc" = 2 ] || fail "s4b: a record with no usable socket exited $rc, not 2"
row=$(last tmux-demo-task-7)
[ "$(printf '%s\n' "$row" | cut -f8-9)" = "tmux-demo-task-7${TAB}-" ] \
  || fail "s4b: the name was not recorded alone beside an unusable socket: $row"
# A resumed session whose record names no socket clears the inbox an earlier
# session recorded, rather than leaving it pointing at a dead socket.
record 4248 tmux-demo-task-7 "$socks/4248.sock"
hook 4248 PLANWRIGHT_WORKER_HANDLE=tmux-demo-task-7 PLANWRIGHT_WORKER_SCOPE=demo:7 2>/dev/null \
  || fail "s4b: the resumed session's first registration failed"
[ "$(last tmux-demo-task-7 | cut -f9)" = 4248.sock ] || fail "s4b: fixture: the inbox was not recorded"
record 4249 tmux-demo-task-7 "relative/4249.sock"
hook 4249 PLANWRIGHT_WORKER_HANDLE=tmux-demo-task-7 PLANWRIGHT_WORKER_SCOPE=demo:7 2>/dev/null
[ "$(last tmux-demo-task-7 | cut -f9)" = - ] || fail "s4b: a session with no usable socket kept an earlier inbox: $(last tmux-demo-task-7)"
[ "$fails" = "$f0" ] && ok "s4b a record with no usable socket still records the name"

# --- s5 -----------------------------------------------------------------------
f0=$fails
before=$(cat "$fleet/registry")
record 4250 planwright-tower-demo "$socks/4250.sock"
hook 4250 2>"$tmp/err" || fail "s5: the hook in a tower session exited non-zero"
[ ! -s "$tmp/err" ] || fail "s5: the hook in a tower session wrote to stderr: $(cat "$tmp/err")"
[ "$(cat "$fleet/registry")" = "$before" ] || fail "s5: the hook in a tower session changed the registry"
[ "$fails" = "$f0" ] && ok "s5 a tower session's hook writes nothing"

if [ "$fails" -ne 0 ]; then
  echo "FAIL: test-fleet-self-register-hook.sh ($fails)" >&2
  exit 1
fi
echo "PASS: test-fleet-self-register-hook.sh"
