# shellcheck shell=bash
# worker-branch-sync-fixture.sh — the shared fixture for the suites of
# scripts/worker-branch-sync.sh (sourced, never executed):
# tests/test-worker-branch-sync.sh (reset, ff, the record and the shared
# checks) and tests/test-worker-branch-sync-push.sh (the leased push).
#
# A bare origin the primary reaches through a GitHub-shaped ssh URL, served
# by an ssh stub (GIT_SSH_COMMAND) from a local directory, so the push verb
# can name the repository to gh with no URL rewrite; a gh stub that
# answers the two pull-request reads from STUB_HEADS and STUB_BASES and logs
# every call; a fleet home whose session records sit at each worktree's own
# path (scripts/worker-session-record.sh path); and the primary's
# machine-local config, the one layer the protected set reads here.
#
# Sourcing runs setup and installs the only EXIT trap.
set -euf
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_NAMESPACE GIT_PREFIX \
  PLANWRIGHT_WORKER_SESSION_RECORD GH_REPO GH_HOST

fx_here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/lib/hermetic-env.sh
. "$fx_here/lib/hermetic-env.sh"
SCRIPT="$fx_here/../scripts/worker-branch-sync.sh"

passes=0
fail() {
  printf '%s\n' "FAIL: $1" >&2
  exit 1
}
pass() {
  printf '%s\n' "ok: $1"
  passes=$((passes + 1))
}

[ -x "$SCRIPT" ] || fail "scripts/worker-branch-sync.sh missing or not executable"
command -v jq >/dev/null 2>&1 || fail "jq is required to run this suite"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-worker-branch-sync.XXXXXX") || fail "could not create a scratch directory"
tmp=$(cd "$tmp" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home" "$tmp/xdg" "$tmp/bin"
mkdir -m 700 "$tmp/fleet" "$tmp/fleet/session-records" "$tmp/fleet/allow-audit"
HOME="$tmp/home"
XDG_CONFIG_HOME="$tmp/xdg"
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet"
GHLOG="$tmp/gh.log"
PATH="$tmp/bin:$PATH"
# The ssh stub runs the git service it is handed (its last argument) in the
# directory standing in for github.com.
GIT_SSH_COMMAND="$tmp/bin/fake-ssh"
GIT_SSH_VARIANT=simple
FAKE_SSH_ROOT="$tmp/remotes"
export HOME XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM PLANWRIGHT_FLEET_STATE_DIR GHLOG PATH \
  GIT_SSH_COMMAND GIT_SSH_VARIANT FAKE_SSH_ROOT
mkdir -p "$FAKE_SSH_ROOT/acme"
cat >"$tmp/bin/fake-ssh" <<'EOF'
#!/bin/sh
for last in "$@"; do :; done
cd "$FAKE_SSH_ROOT" || exit 1
exec sh -c "$last"
EOF
chmod +x "$tmp/bin/fake-ssh"

cat >"$tmp/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$GHLOG"
[ -z "${STUB_GH_FAIL:-}" ] || exit 1
case " $* " in
  *" --head "*) printf '%s\n' "${STUB_HEADS:-[]}" ;;
  *" --base "*) printf '%s\n' "${STUB_BASES:-[]}" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"

g() {
  git -c init.defaultBranch=main -c user.name=t -c user.email=t@example.invalid -c commit.gpgSign=false "$@"
}

origin="$FAKE_SSH_ROOT/acme/demo.git"
URL=git@github.com:acme/demo.git
seed="$tmp/seed"
g init -q --bare "$origin"
g init -q "$seed"
g -C "$seed" commit -q --allow-empty -m base
g -C "$seed" remote add origin "$origin"
g -C "$seed" push -q origin main
for b in planwright/flight/demo planwright/flight/other planwright/flight/prot planwright/demo/spec; do
  g -C "$seed" switch -q -c "$b" main
  g -C "$seed" commit -q --allow-empty -m "pushed on $b"
  g -C "$seed" push -q origin "$b"
done

primary="$tmp/primary"
g clone -q "$origin" "$primary"
g -C "$primary" config user.name t
g -C "$primary" config user.email t@example.invalid
g -C "$primary" config commit.gpgSign false
g -C "$primary" remote set-url origin "$URL"
g -C "$primary" remote set-head origin main
mkdir -p "$primary/.claude"
LOCAL_CFG="$primary/.claude/planwright.local.yml"
printf 'protected_branches: planwright/flight/prot\n' >"$LOCAL_CFG"

# worktree <dir> <branch> — a linked worktree of the primary on <branch>.
worktree() {
  g -C "$primary" branch -q --track "$2" "origin/$2" 2>/dev/null || :
  g -C "$primary" worktree add -q "$1" "$2"
}

# rec_path <worktree> — the worktree's own record path.
rec_path() {
  printf '%s/session-records/%s.record\n' "$PLANWRIGHT_FLEET_STATE_DIR" "$(printf '%s' "$1" | git hash-object --stdin)"
}

# record <worktree> <unit branch> [<line>...] — the worktree's own session
# record as the launcher writes one, with any extra key=value lines.
record() {
  local w=$1 b=$2 f k
  shift 2
  f=$(rec_path "$w")
  k=$(basename "$f" .record)
  {
    printf 'policy=own-branch\nunit_branch=%s\nworktree_root=%s\npr_base=origin/main\n' "$b" "$w"
    printf 'audit_log_home=%s\n' "$PLANWRIGHT_FLEET_STATE_DIR/allow-audit"
    printf 'author=t <t@example.invalid>\n'
    printf 'record_key=session-%s\n' "$k"
    [ "$#" = 0 ] || printf '%s\n' "$@"
  } >"$f"
  chmod 600 "$f"
}

# run <dir> <args...> — the helper in <dir>; sets RC and OUT (stdout and
# stderr together).
run() {
  local d=$1
  shift
  RC=0
  OUT=$(cd "$d" && "$SCRIPT" "$@" 2>&1) || RC=$?
}
refused() { # <label> — the last run refused (exit 1)
  [ "$RC" = 1 ] || fail "$1: expected a refusal (exit 1), got exit $RC: $OUT"
}
has() { # <ERE> <label>
  printf '%s' "$OUT" | grep -Eq -- "$1" || fail "$2: the output does not match /$1/: $OUT"
}
remote_tip() { g -C "$origin" rev-parse "$1"; }

B=planwright/flight/demo
wt="$tmp/wt"
worktree "$wt" "$B"
