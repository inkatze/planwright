#!/bin/bash
# Tests for the worker command guard's audit log of allow decisions
# (REQ-H1.4, REQ-B1.8): one hashed line per emitted allow in the per-session
# log under the audit-log home the session record names, no command text, an
# allow that survives a failed write, and no write arm without a usable home.
# The launcher's pruning of old logs is tested with the record writer in
# tests/test-worker-session-record.sh. The rows run in the corpus sandbox
# (tests/lib/worker-guard-corpus.sh).
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"
# shellcheck source=tests/lib/worker-guard-corpus.sh
. "$REPO_ROOT/tests/lib/worker-guard-corpus.sh"
# shellcheck source=tests/lib/hermetic-env.sh
. "$REPO_ROOT/tests/lib/hermetic-env.sh"

corpus_sandbox "$SANDBOX/box" "$REPO_ROOT" || {
  echo "FAIL: could not build the corpus sandbox" >&2
  exit 1
}
WT=$CORPUS_WORKTREE
SC=$CORPUS_SCRATCH
STATE=$CORPUS_BOX/state
GIT_ISO=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1")
NL=$'\n'
HOME_DIR=$(cd -P "$STATE" && pwd -P)/audit.test
mkdir -p "$HOME_DIR"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -d' ' -f1
  else
    printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
  fi
}

# under <record>: the hook reads this record, with TMPDIR at the scratch root.
under() {
  HOOK_ENV=("${GIT_ISO[@]}" "TMPDIR=$SC" "PLANWRIGHT_WORKER_SESSION_RECORD=$1")
}
# record_with <name> <policy> [<field=value>...]: the both-arms record with
# the policy replaced, the audit home pointed at HOME_DIR, and the named
# fields replaced or (with an empty value) dropped; prints its path.
record_with() {
  local f=$STATE/$1.record kv k
  shift
  {
    printf 'policy=%s\n' "$1"
    printf 'audit_log_home=%s\n' "$HOME_DIR"
    shift
    grep -Ev '^(policy|audit_log_home)=' "$STATE/record.4"
  } >"$f.tmp"
  for kv in "$@"; do
    k=${kv%%=*}
    grep -v "^$k=" "$f.tmp" >"$f.tmp2"
    [ -z "${kv#*=}" ] || printf '%s\n' "$kv" >>"$f.tmp2"
    mv "$f.tmp2" "$f.tmp"
  done
  mv "$f.tmp" "$f"
  printf '%s\n' "$f"
}

# run_session <command> <session-id>: run_hook with a session id in the
# payload, in the worktree.
run_session() {
  local payload
  payload=$(jq -n --arg c "$1" --arg w "$WT" --arg s "$2" \
    '{session_id:$s, tool_name:"Bash", tool_input:{command:$c}, cwd:$w}')
  OUT=$(printf '%s' "$payload" | env -u CLAUDE_DIR HOME="$SANDBOX/no-home" \
    ${HOOK_ENV[@]+"${HOOK_ENV[@]}"} /bin/bash "$HOOK" 2>/dev/null)
  CODE=$?
}

lines_of() {
  if [ -f "$1" ]; then
    wc -l <"$1" | tr -d ' '
  else
    echo 0
  fi
}

echo "### REQ-H1.4 — one hashed line per allow, never the command text"
OB=$(record_with ob 'own-branch scratch')
under "$OB"
LOG=$HOME_DIR/ob.log
cmd='touch build/audit-marker-7f3a'
run_session "$cmd" sess-a1
if [ "$CODE" = 0 ] && is_allow && [ "$(lines_of "$LOG")" = 1 ]; then
  pass "H1.4: an own-branch approval writes exactly one line"
else
  fail "H1.4: an own-branch approval writes exactly one line (allow=$(is_allow && echo y) lines=$(lines_of "$LOG"))"
fi
line=$(cat "$LOG" 2>/dev/null)
want="session=sess-a1 arm=own-branch cmd_sha256=$(sha256_of "$cmd")"
case $line in
  time=[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z" $want")
    pass "H1.4: the line carries the time, session, arm, and command hash"
    ;;
  *) fail "H1.4: the line carries the time, session, arm, and command hash (got: $line)" ;;
esac
case $line in
  *audit-marker* | *touch* | *build/*) fail "H1.4: the line carries no command text" ;;
  *) pass "H1.4: the line carries no command text" ;;
esac
if [ "$(find "$LOG" -perm 600 2>/dev/null)" = "$LOG" ]; then
  pass "H1.4: the log is owner-only"
else
  fail "H1.4: the log is owner-only"
fi

run_session 'git status' sess-a1
tail_line=$(tail -n 1 "$LOG" 2>/dev/null)
if is_allow && [ "$(lines_of "$LOG")" = 2 ]; then
  case $tail_line in
    *" arm=read-only cmd_sha256="*) pass "H1.4: a read-only approval is logged as read-only" ;;
    *) fail "H1.4: a read-only approval is logged as read-only (got: $tail_line)" ;;
  esac
else
  fail "H1.4: a read-only approval appends a second line (lines=$(lines_of "$LOG"))"
fi

run_session 'mktemp -d' sess-a1
case $(tail -n 1 "$LOG" 2>/dev/null) in
  *" arm=scratch cmd_sha256="*) pass "H1.4: a scratch approval is logged as scratch" ;;
  *) fail "H1.4: a scratch approval is logged as scratch" ;;
esac

run_session 'touch build/a && mktemp -d' sess-a1
case $(tail -n 1 "$LOG" 2>/dev/null) in
  *" arm=own-branch,scratch cmd_sha256="*) pass "H1.4: a command both arms approve names both" ;;
  *) fail "H1.4: a command both arms approve names both" ;;
esac

n=$(lines_of "$LOG")
run_session 'git push origin HEAD' sess-a1
if is_empty && [ "$(lines_of "$LOG")" = "$n" ]; then
  pass "H1.4: a deferred command writes no line"
else
  fail "H1.4: a deferred command writes no line"
fi

run_session 'git status' 'bad id/../x'
case $(tail -n 1 "$LOG" 2>/dev/null) in
  *" session=- arm=read-only "*) pass "H1.4: a session id outside its grammar is logged as -" ;;
  *) fail "H1.4: a session id outside its grammar is logged as -" ;;
esac

run_session 'git commit -m x' sess-a1
case $(tail -n 1 "$LOG" 2>/dev/null) in
  *" arm=own-branch cmd_sha256="*) pass "H1.4: a git act the own-branch arm approves is logged as own-branch" ;;
  *) fail "H1.4: a git act the own-branch arm approves is logged as own-branch" ;;
esac

run_session "ls \$TMPDIR" sess-a1
case $(tail -n 1 "$LOG" 2>/dev/null) in
  *" arm=scratch cmd_sha256="*) pass "H1.4: a command whose \$TMPDIR the scratch arm resolved is logged as scratch" ;;
  *) fail "H1.4: a command whose \$TMPDIR the scratch arm resolved is logged as scratch" ;;
esac

OUT=$(jq -n --arg w "$WT" '{tool_name:"Bash", tool_input:{command:"git status"}, cwd:$w}' \
  | env -u CLAUDE_DIR HOME="$SANDBOX/no-home" ${HOOK_ENV[@]+"${HOOK_ENV[@]}"} /bin/bash "$HOOK" 2>/dev/null)
case $(tail -n 1 "$LOG" 2>/dev/null) in
  *" session=- arm=read-only "*) pass "H1.4: a payload with no session id is logged as -" ;;
  *) fail "H1.4: a payload with no session id is logged as -" ;;
esac

run_session "git status$NL" sess-a1
case $(tail -n 1 "$LOG" 2>/dev/null) in
  *" cmd_sha256=$(sha256_of 'git status')") pass "H1.4: the hash is of the command with its trailing newlines removed" ;;
  *) fail "H1.4: the hash is of the command with its trailing newlines removed" ;;
esac

echo "### REQ-H1.4 — an unwritable log leaves the allow intact"
if [ "$(id -u)" = 0 ]; then
  echo "skip: H1.4: unwritable-log rows (running as root, permissions do not bind)"
else
  chmod 400 "$LOG"
  log_denied=0
  if hermetic_access_denied w "$LOG"; then log_denied=1; fi
  n=$(lines_of "$LOG")
  run_session 'touch build/after-ro' sess-a1
  if [ "$log_denied" -eq 0 ]; then
    echo "skip: H1.4: the running user still writes $LOG under mode 400"
  elif [ "$CODE" = 0 ] && is_allow && printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "allow"' >/dev/null 2>&1 \
    && [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ] && [ "$(lines_of "$LOG")" = "$n" ]; then
    pass "H1.4: an own-branch allow survives an unwritable log, well-formed"
  else
    fail "H1.4: an own-branch allow survives an unwritable log, well-formed"
  fi
  chmod 600 "$LOG"
fi

echo "### REQ-H1.4 / REQ-B1.8 — no usable log home, no write arm"
# no_home_rows <label> <record>: the write arms are off, read-only stands.
no_home_rows() {
  under "$2"
  assert_defer "H1.4: $1: no own-branch approval" "touch build/x" Bash "$WT"
  assert_defer "H1.4: $1: no scratch approval" "mktemp -d" Bash "$WT"
  assert_allow "H1.4: $1: read-only approvals proceed" "git status" Bash "$WT"
}
no_home_rows "a record with no log home" "$(record_with nohome 'own-branch scratch' audit_log_home=)"
no_home_rows "a relative log home" "$(record_with relhome 'own-branch scratch' audit_log_home=audit)"
no_home_rows "a missing log home" "$(record_with mishome 'own-branch scratch' "audit_log_home=$STATE/absent")"
ln -s "$HOME_DIR" "$STATE/audit.link"
no_home_rows "a log home through a symlink" "$(record_with linkhome 'own-branch scratch' "audit_log_home=$STATE/audit.link")"
mkdir -p "$WT/build/audit"
no_home_rows "a log home inside the worktree" "$(record_with wthome 'own-branch scratch' "audit_log_home=$WT/build/audit")"
mkdir -p "$SC/audit"
no_home_rows "a log home inside the scratch root" "$(record_with schome 'own-branch scratch' "audit_log_home=$SC/audit")"
: >"$STATE/audit.file"
no_home_rows "a log home that is a file" "$(record_with filehome 'own-branch scratch' "audit_log_home=$STATE/audit.file")"
f=$(record_with duphome 'own-branch scratch')
printf 'audit_log_home=%s\n' "$HOME_DIR" >>"$f"
no_home_rows "a repeated log home" "$f"
f=$(record_with fifolog 'own-branch scratch')
mkfifo "$HOME_DIR/fifolog.log"
no_home_rows "a log that is not a regular file" "$f"
f=$(record_with linklog 'own-branch scratch')
ln -s "$STATE/elsewhere.log" "$HOME_DIR/linklog.log"
no_home_rows "a log reached through a symlink" "$f"
if [ ! -e "$STATE/elsewhere.log" ]; then
  pass "H1.4: nothing is written through a symlinked log"
else
  fail "H1.4: nothing is written through a symlinked log"
fi
under "$(record_with nohome2 '' audit_log_home=)"
assert_allow "H1.4: the empty policy approves read-only shapes with no log home" "git status" Bash "$WT"

finish_suite worker-command-guard-audit
