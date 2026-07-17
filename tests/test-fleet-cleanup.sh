#!/bin/bash
# Tests for scripts/fleet-cleanup.sh — the deterministic stale-resource cleanup
# actuator with an explicit self-targeting guard (Task 4: D-6, D-5, D-15, D-16;
# REQ-B1.1).
#
# The mechanism reclaims a stale tmux window (its worker pane exited) or a stale
# git worktree (nothing would be lost), NEVER in-context model judgment, and
# refuses outright to target its OWN hosting session/worktree — the
# anthropics/claude-code#29787 failure mode where an LLM-driven cleanup issued
# `tmux kill-session` against its own pane and destroyed the whole session.
#
# Exit-code contract (documented in the script header):
#   0 = acted (resource reclaimed) or a clean no-op (target already gone)
#   2 = usage / refused malformed token
#   3 = refused by the self-targeting guard (target is, or cannot be proven not
#       to be, the caller's own hosting session/worktree) — the #29787 block
#   4 = refused: the fleet_daemon_pause kill-switch is set
#   5 = refused: no positive evidence the target is reclaimable (a live pane /
#       an unpushed-or-dirty worktree — acting would kill live work)
#
# What is covered:
#   - the self-targeting guard refuses (exit 3) and kills nothing when the
#     target window resolves to the caller's own window (#29787 reproduced);
#   - a genuinely stale, non-self window (all panes dead) is reclaimed (exit 0,
#     the kill happens, the action is audited);
#   - a live target window (a pane still running) is refused (exit 5), unkilled;
#   - an already-absent window is a clean no-op (exit 0, no kill, no audit);
#   - the kill-switch pauses the cleanup (exit 4, nothing killed);
#   - self-identity that cannot be resolved fails closed (exit 3);
#   - a stale, clean, non-self worktree is removed (exit 0, audited);
#   - a worktree with uncommitted OR unpushed work is refused (exit 5);
#   - the caller's own worktree is refused by the self-guard (exit 3);
#   - hostile tmux/path tokens are refused (exit 2);
#   - every reclaim and every self-block writes a fleet-audit row.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-cleanup.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

# Isolate git fully from the host's global/system config: signing
# (commit.gpgsign + a 1Password/GPG signer that blocks non-interactively) and
# branch.autosetuprebase would otherwise hang or reshape the fixture commits.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

here=$(cd "$(dirname "$0")" && pwd)
FC="$here/../scripts/fleet-cleanup.sh"
FA="$here/../scripts/fleet-audit.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FC" ] || fail "scripts/fleet-cleanup.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- config layers so the kill-switch resolver has a real core default.
core_cfg="$tmp/core-defaults.yml"
repo="$tmp/repo"
mkdir -p "$repo/.claude"
printf 'fleet_daemon_pause: false\n' >"$core_cfg"
mlocal_cfg="$repo/.claude/planwright.local.yml"

fleet_home="$tmp/fleet"

# --- a fake tmux on PATH (the death-evidence test's pattern): deterministic,
#     no live server. Behaviour is driven by env the runner sets per case.
#       FAKE_SELF   TAB-joined "session<TAB>window_id<TAB>window_name" the
#                   caller's own pane resolves to (empty => display-message fails
#                   => self unresolvable).
#       FAKE_PANES  newline list of pane_dead values for the target window
#                   ("absent" => the window is gone => list-panes exits 1).
#       FAKE_KILLED file every kill-window target is appended to.
fakebin="$tmp/bin"
mkdir -p "$fakebin"
cat >"$fakebin/tmux" <<'EOF'
#!/bin/sh
sub=$1
shift
case "$sub" in
  display-message)
    [ -n "${FAKE_SELF:-}" ] || exit 1
    printf '%s\n' "$FAKE_SELF"
    ;;
  list-panes)
    # find the -t target for the killed-target echo parity; the pane data is
    # global to the case, so just emit FAKE_PANES (or fail when absent).
    [ "${FAKE_PANES:-absent}" = absent ] && exit 1
    printf '%s\n' "$FAKE_PANES"
    ;;
  kill-window)
    tgt=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -t)
          tgt=$2
          shift 2
          ;;
        *) shift ;;
      esac
    done
    printf '%s\n' "$tgt" >>"$FAKE_KILLED"
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$fakebin/tmux"

killed="$tmp/killed"

# run_window <self> <panes> <session> <window> — invoke the window cleanup with
# the fake tmux frontmost and a controlled self-identity + pane state.
run_window() {
  _self=$1
  _panes=$2
  shift 2
  : >"$killed"
  PATH="$fakebin:$PATH" \
    TMUX="fake,1,0" TMUX_PANE="%0" \
    FAKE_SELF="$_self" FAKE_PANES="$_panes" FAKE_KILLED="$killed" \
    PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$FC" window "$@"
}

audit_rows() {
  PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$FA" query "$@" 2>/dev/null
}

# 1. Self-targeting guard: target window == the caller's own window (matched by
#    id). The #29787 reproduction — refuse (exit 3), kill nothing.
rm -rf "$fleet_home"
rc=0
run_window "towerA	@5	worker-1" "1" towerA @5 "stale window" "worker exited" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "self-target (by id): exit $rc, expected 3 (self-guard)"
[ ! -s "$killed" ] || fail "self-target: a window was killed despite the guard"
echo "ok: the self-targeting guard refuses to kill the caller's own window (by id)"

# 1b. Same, but the target names the window by NAME rather than id.
rc=0
run_window "towerA	@5	worker-1" "1" towerA worker-1 "stale window" "worker exited" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "self-target (by name): exit $rc, expected 3"
[ ! -s "$killed" ] || fail "self-target (by name): a window was killed"
echo "ok: the self-targeting guard refuses by window name too"

# 1c. The self-block is recorded in the audit trail (the guard firing is a
#     notable safety event, not routine noise).
rows=$(audit_rows --mechanism window-cleanup)
case $rows in
  *refuse-self*) ;;
  *) fail "self-target: no refuse-self audit row (got: '$rows')" ;;
esac
echo "ok: the self-block is written to the audit trail"

# 2. A genuinely stale, non-self window (all panes dead) is reclaimed.
rm -rf "$fleet_home"
rc=0
run_window "towerA	@5	worker-1" "1" towerA @9 "stale window" "worker pane dead" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "stale non-self window: exit $rc, expected 0 (reclaimed)"
grep -q '=towerA:@9' "$killed" || fail "stale window was not killed (killed: '$(cat "$killed")')"
rows=$(audit_rows --mechanism window-cleanup)
case $rows in
  *cleanup*) ;;
  *) fail "stale window: no cleanup audit row (got: '$rows')" ;;
esac
echo "ok: a stale, non-self window is reclaimed and audited"

# 3. A live target window (a pane still running: pane_dead 0) is refused — no
#    positive evidence it is reclaimable.
rm -rf "$fleet_home"
rc=0
run_window "towerA	@5	worker-1" "1
0" towerA @9 "maybe stale" "checking" >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "live window: exit $rc, expected 5 (not reclaimable)"
[ ! -s "$killed" ] || fail "live window: a window with a live pane was killed"
echo "ok: a window with a live pane is refused (exit 5)"

# 4. An already-absent window is a clean no-op.
rm -rf "$fleet_home"
rc=0
run_window "towerA	@5	worker-1" "absent" towerA @9 "gone" "already reclaimed" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "absent window: exit $rc, expected 0 (clean no-op)"
[ ! -s "$killed" ] || fail "absent window: a kill was issued for a gone window"
echo "ok: an already-absent window is a clean no-op"

# 5. Self-identity unresolvable (display-message fails) fails closed: refuse.
rm -rf "$fleet_home"
rc=0
run_window "" "1" towerA @9 "stale" "worker exited" >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "unresolvable self: exit $rc, expected 3 (fail closed)"
[ ! -s "$killed" ] || fail "unresolvable self: a window was killed"
echo "ok: an unresolvable self-identity fails closed (exit 3)"

# 6. The kill-switch pauses the cleanup.
rm -rf "$fleet_home"
printf 'fleet_daemon_pause: true\n' >"$mlocal_cfg"
rc=0
run_window "towerA	@5	worker-1" "1" towerA @9 "stale" "worker exited" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "kill-switch: exit $rc, expected 4 (paused)"
[ ! -s "$killed" ] || fail "kill-switch: a window was killed while paused"
rm -f "$mlocal_cfg"
echo "ok: the kill-switch pauses the cleanup (exit 4)"

# 7. Hostile tmux tokens are refused before any tmux call.
rm -rf "$fleet_home"
for bad in 'a b' '-x' '../x' 'a:b'; do
  rc=0
  run_window "towerA	@5	worker-1" "1" "$bad" @9 "t" "r" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "hostile session '$bad': exit $rc, expected 2"
done
echo "ok: hostile tmux tokens are refused (exit 2)"

# --- worktree cleanup, against a real git repo with a real linked worktree.
git_env() {
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t "$@"
}
main_repo="$tmp/main"
git_env git init -q -b main "$main_repo"
(cd "$main_repo" && echo seed >f && git_env git add f && git_env git commit -qm seed)
# A bare "remote" so a branch can be genuinely pushed / left unpushed.
remote="$tmp/remote.git"
git_env git init -q --bare "$remote"
(cd "$main_repo" && git_env git remote add origin "$remote" && git_env git push -q -u origin main)

run_worktree() {
  _cwd=$1
  shift
  : >"$killed"
  PATH="$fakebin:$PATH" \
    PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    sh -c 'cd "$1" && shift && exec /bin/bash "$0" "$@"' "$FC" "$_cwd" worktree "$@"
}

# 8. A clean, fully-pushed, non-self worktree is reclaimable.
wt_clean="$tmp/wt-clean"
(cd "$main_repo" && git_env git worktree add -q -b feat-clean "$wt_clean" >/dev/null 2>&1)
(cd "$wt_clean" && git_env git push -q -u origin feat-clean)
rm -rf "$fleet_home"
rc=0
run_worktree "$main_repo" "$wt_clean" "merged branch" "reclaiming clean worktree" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "clean worktree: exit $rc, expected 0 (reclaimed)"
[ ! -d "$wt_clean" ] || fail "clean worktree: directory still present after remove"
rows=$(audit_rows --mechanism worktree-cleanup)
case $rows in
  *cleanup*) ;;
  *) fail "clean worktree: no cleanup audit row (got: '$rows')" ;;
esac
echo "ok: a clean, pushed, non-self worktree is removed and audited"

# 9. A worktree with uncommitted work is refused (would lose work).
wt_dirty="$tmp/wt-dirty"
(cd "$main_repo" && git_env git worktree add -q -b feat-dirty "$wt_dirty" >/dev/null 2>&1)
(cd "$wt_dirty" && echo scratch >dirty.txt)
rm -rf "$fleet_home"
rc=0
run_worktree "$main_repo" "$wt_dirty" "candidate" "checking dirty" >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "dirty worktree: exit $rc, expected 5 (would lose work)"
[ -d "$wt_dirty" ] || fail "dirty worktree: directory was removed despite dirt"
echo "ok: a worktree with uncommitted work is refused (exit 5)"

# 9b. A worktree with a committed-but-unpushed change is refused too.
wt_unpushed="$tmp/wt-unpushed"
(cd "$main_repo" && git_env git worktree add -q -b feat-unpushed "$wt_unpushed" >/dev/null 2>&1)
(cd "$wt_unpushed" && echo more >>f && git_env git add f && git_env git commit -qm local)
rm -rf "$fleet_home"
rc=0
run_worktree "$main_repo" "$wt_unpushed" "candidate" "checking unpushed" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "unpushed worktree: exit $rc, expected 5"
[ -d "$wt_unpushed" ] || fail "unpushed worktree: removed despite unpushed commits"
echo "ok: a worktree with unpushed commits is refused (exit 5)"

# 10. The caller's own worktree is refused by the self-guard.
wt_self="$tmp/wt-self"
(cd "$main_repo" && git_env git worktree add -q -b feat-self "$wt_self" >/dev/null 2>&1)
(cd "$wt_self" && git_env git push -q -u origin feat-self)
rm -rf "$fleet_home"
rc=0
run_worktree "$wt_self" "$wt_self" "self" "self target" >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "self worktree: exit $rc, expected 3 (self-guard)"
[ -d "$wt_self" ] || fail "self worktree: the caller's own worktree was removed"
echo "ok: the caller's own worktree is refused by the self-guard (exit 3)"

echo "ALL PASS: fleet-cleanup"
