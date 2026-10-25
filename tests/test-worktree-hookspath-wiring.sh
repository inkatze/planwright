#!/bin/bash
# Fresh worktrees pass check:githooks whoever last wrote core.hooksPath
# (test-throughput REQ-E1.3, D-13). Each worktree-creation path planwright
# owns, run from a clone whose core.hooksPath was set absolute or cleared,
# leaves a worktree where scripts/check-githooks.sh passes; a repository that
# does not ship the hook backstop keeps its own value; the check itself still
# fails on an absolute value.
#
# Creation paths covered: scripts/fleet-dispatch-worktree.sh (every rung and
# the flight arm create through it; the create arm and the adopt-a-stale-branch
# arm are both exercised) and scripts/spec-store-worktree.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-worktree-hookspath-wiring.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
S="$REPO_ROOT/scripts"
TAB=$(printf '\t')
HOOKS="pre-push pre-rebase prepare-commit-msg commit-msg pre-commit"

fails=0
fail() {
  printf 'FAIL: %s\n' "$1" | tr -d '\000-\010\013-\037\177' >&2
  fails=$((fails + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/wt-hookspath.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

inherited_unsets=$(env | sed -n 's/^\(PLANWRIGHT_[A-Za-z0-9_]*\)=.*/-u \1/p')
mkdir -p "$tmp/home"
# hermetic <state-dir> <cmd...> — no machine git config, no machine fleet state,
# and no live-tmux liveness probe (a stray session would read as in flight).
hermetic() {
  _st=$1
  shift
  # shellcheck disable=SC2086 # one `-u NAME` pair per word
  env $inherited_unsets -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR \
    HOME="$tmp/home" GIT_CEILING_DIRECTORIES="$tmp" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
    GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
    PLANWRIGHT_ROOT="$REPO_ROOT" \
    PLANWRIGHT_FLEET_STATE_DIR="$_st/fleet" PLANWRIGHT_ORCH_STATE_DIR="$_st/markers" \
    PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$_st/fstate" PLANWRIGHT_DISPATCH_LIVENESS_SKIP_TMUX=1 \
    "$@"
}
gitq() { hermetic "$tmp" git -c commit.gpgsign=false "$@" >/dev/null 2>&1; }
hookspath() { hermetic "$tmp" git -C "$1" config --local --get core.hooksPath 2>/dev/null; }

# add_backstop <dir> — the tracked hook backstop: githooks/ and its wire step.
add_backstop() {
  mkdir -p "$1/githooks" "$1/scripts"
  for h in $HOOKS; do
    printf '#!/bin/sh\nexit 0\n' >"$1/githooks/$h"
    chmod +x "$1/githooks/$h"
  done
  cp "$S/wire-githooks.sh" "$1/scripts/wire-githooks.sh"
  chmod +x "$1/scripts/wire-githooks.sh"
}

# seed <dir> <backstop:yes|no> — a bare origin and a primary clone with a
# minimal spec bundle on main, pushed.
seed() {
  gitq -c init.defaultBranch=main init -q --bare "$1/origin.git"
  gitq clone -q "$1/origin.git" "$1/primary"
  mkdir -p "$1/primary/specs/demo"
  printf 'v1\n' >"$1/primary/specs/demo/requirements.md"
  [ "$2" = no ] || add_backstop "$1/primary"
  gitq -C "$1/primary" add -A
  gitq -C "$1/primary" commit -q -m seed
  gitq -C "$1/primary" branch -M main
  gitq -C "$1/primary" push -q origin main
}

# set_hookspath <clone> <absolute|cleared|value> — the drifted starting state.
set_hookspath() {
  case $2 in
    absolute) gitq -C "$1" config --local core.hooksPath "$1/githooks" ;;
    cleared) gitq -C "$1" config --local --unset-all core.hooksPath ;;
    *) gitq -C "$1" config --local core.hooksPath "$2" ;;
  esac
}

# check_in <worktree> — the check:githooks body, run inside the worktree.
check_in() {
  (cd "$1" && hermetic "$tmp" /bin/sh "$S/check-githooks.sh") >/dev/null 2>&1
}

# dispatch <case-dir> <id> — sets OUT (stdout) and RC.
dispatch() {
  OUT=$(hermetic "$1" "$S/fleet-dispatch-worktree.sh" dispatch demo "$2" \
    --repo-root "$1/primary" --no-attach </dev/null 2>"$1/err")
  RC=$?
}

# --- fleet-dispatch-worktree.sh, create arm, absolute and cleared ----------
for start in absolute cleared; do
  t="$tmp/dispatch-$start"
  mkdir -p "$t"
  seed "$t" yes
  set_hookspath "$t/primary" "$start"
  dispatch "$t" 10
  wt="$t/primary/.claude/worktrees/demo-task-10"
  if [ "$RC" -ne 0 ] || [ ! -d "$wt" ]; then
    fail "dispatch ($start): exited $RC, worktree present: $([ -d "$wt" ] && echo yes || echo no); $(cat "$t/err")"
    continue
  fi
  if check_in "$wt"; then
    ok "dispatch ($start): check:githooks passes in the new worktree"
  else
    fail "dispatch ($start): check:githooks fails in the new worktree (core.hooksPath='$(hookspath "$wt")')"
  fi
  # stdout stays the machine-read dispatch record; the wire step's note does not
  # land in it.
  if printf '%s\n' "$OUT" | grep -v "^dispatch$TAB" | grep -q .; then
    fail "dispatch ($start): stdout carries a non-record line: $OUT"
  else
    ok "dispatch ($start): stdout carries only the dispatch record"
  fi
  # A replaced or newly wired value is reported, so the change stays visible.
  case $start in
    absolute) want="replacing existing core.hooksPath '$t/primary/githooks'" ;;
    *) want="core.hooksPath was unset; wiring" ;;
  esac
  if grep -q "^fleet-dispatch-worktree: wire-githooks: note: $want" "$t/err"; then
    ok "dispatch ($start): the change is reported on stderr"
  else
    fail "dispatch ($start): the change was not reported: $(cat "$t/err")"
  fi
done

# --- a multi-valued core.hooksPath is still replaced -----------------------
t="$tmp/dispatch-multi"
mkdir -p "$t"
seed "$t" yes
gitq -C "$t/primary" config --local core.hooksPath "$t/primary/githooks"
gitq -C "$t/primary" config --local --add core.hooksPath /elsewhere
dispatch "$t" 10
wt="$t/primary/.claude/worktrees/demo-task-10"
if [ "$RC" -eq 0 ] && check_in "$wt" \
  && [ "$(hermetic "$tmp" git -C "$wt" config --local --get-all core.hooksPath)" = githooks ]; then
  ok "dispatch (multi-valued): every value is replaced by the one tracked value"
else
  fail "dispatch (multi-valued): exited $RC, values now: $(hermetic "$tmp" git -C "$wt" config --local --get-all core.hooksPath 2>&1); $(cat "$t/err")"
fi

# --- fleet-dispatch-worktree.sh, adopt-a-stale-branch arm ------------------
t="$tmp/dispatch-adopt"
mkdir -p "$t"
seed "$t" yes
gitq -C "$t/primary" checkout -q -b planwright/demo/task-11
printf 'work\n' >"$t/primary/specs/demo/work"
gitq -C "$t/primary" add -A
gitq -C "$t/primary" commit -q -m "stale work"
gitq -C "$t/primary" checkout -q main
set_hookspath "$t/primary" absolute
dispatch "$t" 11
wt="$t/primary/.claude/worktrees/demo-task-11"
if [ "$RC" -eq 0 ] && [ -f "$wt/specs/demo/work" ]; then
  if check_in "$wt"; then
    ok "dispatch (adopt): check:githooks passes in the adopted worktree"
  else
    fail "dispatch (adopt): check:githooks fails (core.hooksPath='$(hookspath "$wt")')"
  fi
else
  fail "dispatch (adopt): exited $RC or did not adopt the stale branch; $(cat "$t/err")"
fi

# --- a repository without the backstop keeps its own value -----------------
t="$tmp/dispatch-adopter"
mkdir -p "$t"
seed "$t" no
set_hookspath "$t/primary" .husky/_
dispatch "$t" 10
if [ "$RC" -eq 0 ] && [ "$(hookspath "$t/primary")" = ".husky/_" ]; then
  ok "dispatch (no backstop): the repository's own core.hooksPath is left alone"
else
  fail "dispatch (no backstop): exited $RC, core.hooksPath now '$(hookspath "$t/primary")'"
fi

# A githooks/ directory alone is not the backstop: without the wire step it
# may be the repository's own convention.
t="$tmp/dispatch-githooks-only"
mkdir -p "$t"
seed "$t" yes
gitq -C "$t/primary" rm -q scripts/wire-githooks.sh
gitq -C "$t/primary" commit -q -m "drop the wire step"
gitq -C "$t/primary" push -q origin main
set_hookspath "$t/primary" .husky/_
dispatch "$t" 10
if [ "$RC" -eq 0 ] && [ "$(hookspath "$t/primary")" = ".husky/_" ]; then
  ok "dispatch (githooks/ without the wire step): core.hooksPath is left alone"
else
  fail "dispatch (githooks/ without the wire step): exited $RC, core.hooksPath now '$(hookspath "$t/primary")'"
fi

# The backstop must be tracked, not merely present on disk.
t="$tmp/wire-untracked"
mkdir -p "$t"
seed "$t" no
add_backstop "$t/primary"
set_hookspath "$t/primary" .husky/_
rc=0
(cd "$t/primary" && hermetic "$tmp" /bin/sh "$S/wire-githooks.sh" --if-tracked >/dev/null 2>&1) || rc=$?
if [ "$rc" -eq 0 ] && [ "$(hookspath "$t/primary")" = ".husky/_" ]; then
  ok "wire --if-tracked (untracked backstop files): core.hooksPath is left alone"
else
  fail "wire --if-tracked (untracked backstop files): exited $rc, core.hooksPath now '$(hookspath "$t/primary")'"
fi

# --- spec-store-worktree.sh, absolute and cleared ---------------------------
for start in absolute cleared; do
  t="$tmp/store-$start"
  mkdir -p "$t"
  W="$t/work"
  H="$t/holder"
  gitq -c init.defaultBranch=main init -q "$W"
  printf 'x\n' >"$W/file"
  gitq -C "$W" add -A
  gitq -C "$W" commit -q -m init
  gitq -c init.defaultBranch=main init -q --bare "$H-origin.git"
  gitq -c init.defaultBranch=main init -q "$H"
  mkdir -p "$H/projects/demo-root"
  printf 'project: fixture\nlayout: 1\n' >"$H/projects/demo-root/planwright-spec-root.yml"
  add_backstop "$H"
  gitq -C "$H" add -A
  gitq -C "$H" commit -q -m root
  gitq -C "$H" remote add origin "$H-origin.git"
  gitq -C "$H" push -q -u origin main
  gitq -C "$H" remote set-head origin --auto
  mkdir -p "$W/.claude"
  printf 'spec_root: %s\n' "$H/projects/demo-root" >"$W/.claude/planwright.local.yml"
  set_hookspath "$H" "$start"
  out=$(cd "$W" && hermetic "$t" "$S/spec-store-worktree.sh" demo 2>"$t/err")
  rc=$?
  wt="$H/.claude/worktrees/demo-spec"
  if [ "$rc" -ne 0 ] || [ ! -d "$wt" ]; then
    fail "spec-store ($start): exited $rc; $(cat "$t/err")"
    continue
  fi
  if check_in "$wt"; then
    ok "spec-store ($start): check:githooks passes in the new holder worktree"
  else
    fail "spec-store ($start): check:githooks fails (core.hooksPath='$(hookspath "$wt")')"
  fi
  if printf '%s\n' "$out" | grep -Ev "^(worktree|bundle|branch)$TAB" | grep -q .; then
    fail "spec-store ($start): stdout carries a non-record line: $out"
  fi
  if [ "$start" = absolute ]; then
    if grep -q "^spec-store-worktree: wire-githooks: note: replacing existing core.hooksPath '$H/githooks'" "$t/err"; then
      ok "spec-store ($start): the replaced value is reported on stderr"
    else
      fail "spec-store ($start): the replaced value was not reported: $(cat "$t/err")"
    fi
    # Reusing the worktree creates nothing, so it wires nothing.
    set_hookspath "$H" absolute
    rc=0
    out=$(cd "$W" && hermetic "$t" "$S/spec-store-worktree.sh" demo 2>"$t/err") || rc=$?
    if [ "$rc" -eq 0 ] && [ "$(hookspath "$H")" = "$H/githooks" ]; then
      ok "spec-store (reuse): an existing worktree is not rewired"
    else
      fail "spec-store (reuse): core.hooksPath now '$(hookspath "$H")'; $(cat "$t/err")"
    fi
  fi
done

# --- the check stays detect-only: an absolute value still fails ------------
t="$tmp/dispatch-absolute"
wt="$t/primary/.claude/worktrees/demo-task-10"
if [ -d "$wt" ]; then
  set_hookspath "$t/primary" absolute
  if check_in "$wt"; then
    fail "check-githooks.sh passed on an absolute core.hooksPath"
  else
    ok "check-githooks.sh still fails on an absolute core.hooksPath"
  fi
  if [ "$(hookspath "$wt")" = "$t/primary/githooks" ]; then
    ok "check-githooks.sh did not rewrite the value it reported"
  else
    fail "check-githooks.sh changed core.hooksPath to '$(hookspath "$wt")'"
  fi
else
  fail "detect-only: no worktree from the absolute dispatch case to check in"
fi

if [ "$fails" -ne 0 ]; then
  echo "FAILED: $fails assertion(s)" >&2
  exit 1
fi
echo "PASS: all worktree hooksPath wiring cases"
