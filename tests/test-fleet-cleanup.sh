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
#       a dirty worktree / one whose commits are not provably safe — acting
#       would kill live work)
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
#   - the --merged-pr evidence path: a clean worktree whose named PR is verified
#     MERGED at exactly this HEAD is reclaimed (the post-merge shape where the
#     forge auto-deleted the branch, so no upstream can ever exist), while a
#     non-MERGED PR, an oid mismatch, and an unusable `gh` each refuse (exit 5),
#     a malformed --merged-pr value or unknown flag is usage (exit 2), and the
#     no-upstream-no-flag default is still refused (the regression guard);
#   - the gh QUERY SHAPE itself: the PR number the caller named is what reached
#     gh, both --json fields are asked for in one query, template intact;
#   - the evidence path's remaining fail-closed branches: gh ABSENT (a PATH
#     mirrored without it, so the host's real gh is not reached), a non-hex head
#     oid, and a gh reply with no separator to split all refuse (exit 5);
#   - PRECEDENCE, both directions: upstream parity alone still reclaims with
#     --merged-pr also passed and gh broken (gh never consulted), and a verified
#     merged PR reclaims a worktree that is AHEAD of its upstream, which path A
#     refuses on its own;
#   - the clean check is a prerequisite of BOTH paths: a dirty worktree with a
#     perfect merged-PR proof is still refused, before gh is consulted at all;
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
#       FAKE_SELF   TAB-joined "session<TAB>window_id<TAB>window_name<TAB>index"
#                   the caller's own pane resolves to (empty => display-message
#                   fails => self unresolvable).
#       FAKE_PANES  newline list of pane_dead values for the target window
#                   ("absent" => the window is gone => list-panes exits 1).
#       FAKE_SERVER_DOWN  non-empty => `ls` and `list-panes` both fail (an
#                   unreachable server: lost observability, not "window gone").
#       FAKE_KILLED file every kill-window target is appended to.
fakebin="$tmp/bin"
mkdir -p "$fakebin"
cat >"$fakebin/tmux" <<'EOF'
#!/bin/sh
sub=$1
shift
case "$sub" in
  ls)
    [ -n "${FAKE_SERVER_DOWN:-}" ] && exit 1
    exit 0
    ;;
  display-message)
    [ -n "${FAKE_SELF:-}" ] || exit 1
    printf '%s\n' "$FAKE_SELF"
    ;;
  list-panes)
    # A downed server fails the query; otherwise emit FAKE_PANES (or fail when
    # the target window is absent).
    [ -n "${FAKE_SERVER_DOWN:-}" ] && exit 1
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

# A fake `gh` for the --merged-pr evidence path. FAKE_GH_STATE / FAKE_GH_OID
# drive the reported PR; FAKE_GH_FAIL makes the query fail (an unauthenticated
# or offline gh). gh being ABSENT is exercised by the no-gh PATH mirror at 9i,
# not by a knob — removing this stub alone would only expose the host's REAL gh.
#
# Every invocation appends its argv, one word per line, to $tmp/gh-args (the
# fake-binary call-recording pattern the sibling fleet suites use), so a test can
# assert the QUERY SHAPE and not merely the answer: which PR number reached gh,
# that both --json fields were asked for, and that the template is intact.
# Without that, a regression asking about a DIFFERENT PR — or dropping a field —
# passes the whole suite, because the stub answers the same either way.
#
# FAKE_GH_RAW replaces the whole reply with a verbatim string, for the shapes the
# state/oid pair cannot express: a malformed answer with no separator at all.
cat >"$fakebin/gh" <<EOF
#!/bin/sh
for a in "\$@"; do printf '%s\n' "\$a" >>"$tmp/gh-args"; done
[ -n "\${FAKE_GH_FAIL:-}" ] && exit 1
if [ -n "\${FAKE_GH_RAW:-}" ]; then
  printf '%s\n' "\${FAKE_GH_RAW}"
  exit 0
fi
printf '%s %s\n' "\${FAKE_GH_STATE:-MERGED}" "\${FAKE_GH_OID:-}"
EOF
chmod +x "$fakebin/gh"

killed="$tmp/killed"

# run_window <self> <panes> <session> <window> ... — invoke the window cleanup
# with the fake tmux frontmost and a controlled self-identity + pane state.
# Optional overrides via env: RW_TMUX_PANE (default %0), RW_SERVER_DOWN,
# RW_FLEET_HOME (default $fleet_home).
run_window() {
  _self=$1
  _panes=$2
  shift 2
  : >"$killed"
  PATH="$fakebin:$PATH" \
    TMUX="fake,1,0" TMUX_PANE="${RW_TMUX_PANE-%0}" \
    FAKE_SELF="$_self" FAKE_PANES="$_panes" FAKE_KILLED="$killed" \
    FAKE_SERVER_DOWN="${RW_SERVER_DOWN:-}" \
    PLANWRIGHT_FLEET_STATE_DIR="${RW_FLEET_HOME:-$fleet_home}" \
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

# 7b. A list-panes failure with the server UNREACHABLE is lost observability, not
#     proof of absence: refuse (exit 5), never a false "gone" no-op (the
#     2026-06-12 lesson).
rm -rf "$fleet_home"
rc=0
RW_SERVER_DOWN=1 run_window "towerA	@5	worker-1	3" "absent" towerA @9 "stale" "worker exited" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "server unreachable: exit $rc, expected 5 (lost observability, not gone)"
[ ! -s "$killed" ] || fail "server unreachable: a window was killed on lost observability"
echo "ok: an unreachable tmux server is refused (exit 5), not misread as gone"

# 7c. \$TMUX_PANE unset (but \$TMUX set) fails closed: self-identity is unreliable.
rm -rf "$fleet_home"
rc=0
RW_TMUX_PANE="" run_window "towerA	@5	worker-1	3" "1" towerA @9 "stale" "worker exited" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "empty TMUX_PANE: exit $rc, expected 3 (fail closed)"
[ ! -s "$killed" ] || fail "empty TMUX_PANE: a window was killed"
echo "ok: an unset \$TMUX_PANE fails closed (exit 3)"

# 7d. The self-targeting guard also refuses a target that addresses the caller's
#     own window by INDEX (not just id/name).
rm -rf "$fleet_home"
rc=0
run_window "towerA	@5	worker-1	3" "1" towerA 3 "stale" "worker exited" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "self-target by index: exit $rc, expected 3 (self-guard)"
[ ! -s "$killed" ] || fail "self-target by index: a window was killed"
echo "ok: the self-guard refuses the caller's own window addressed by index"

# 7e. A reclaim that SUCCEEDS but whose audit write fails returns exit 6 (acted
#     but unrecorded) — distinct from 2 (nothing happened). The fleet home is
#     pointed at an unwritable location so the audit write fails after the kill.
unwritable_home="$tmp/unwritable-home"
: >"$unwritable_home" # a FILE where a dir is expected
rm -f "$killed"
: >"$killed"
rc=0
RW_FLEET_HOME="$unwritable_home/fleet" \
  run_window "towerA	@5	worker-1	3" "1" towerA @9 "stale" "worker exited" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 6 ] || fail "audit-fail-after-kill: exit $rc, expected 6 (acted but unaudited)"
grep -q '=towerA:@9' "$killed" || fail "audit-fail-after-kill: the window was not actually killed"
echo "ok: a reclaim whose audit write fails returns exit 6 (acted but unrecorded)"

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
  # WT_PATH lets a case substitute the whole PATH (9i's no-gh mirror); every
  # other case gets the normal fake-bins-ahead-of-the-host arrangement.
  PATH="${WT_PATH:-$fakebin:$PATH}" \
    PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    FAKE_GH_STATE="${FAKE_GH_STATE:-}" \
    FAKE_GH_OID="${FAKE_GH_OID:-}" \
    FAKE_GH_FAIL="${FAKE_GH_FAIL:-}" \
    FAKE_GH_RAW="${FAKE_GH_RAW:-}" \
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

# --- 9c-9h. The --merged-pr evidence path: the post-merge shape where the forge
# auto-deleted the remote branch, so no upstream exists and upstream parity can
# never hold, although the commits are provably merged.
#
# make_merged_wt <name> — a clean worktree pushed and then severed from its
# upstream (remote branch deleted), exactly as a merged-and-auto-deleted PR
# leaves it. Echoes the worktree path.
make_merged_wt() {
  _n=$1
  _p="$tmp/$_n"
  (cd "$main_repo" && git_env git worktree add -q -b "$_n" "$_p" >/dev/null 2>&1)
  (cd "$_p" && git_env git push -q -u origin "$_n" >/dev/null 2>&1)
  # The forge deletes the merged branch: the upstream ref goes away.
  (cd "$main_repo" && git_env git push -q origin --delete "$_n" >/dev/null 2>&1)
  (cd "$_p" && git_env git fetch -q --prune origin >/dev/null 2>&1)
  printf '%s\n' "$_p"
}

# 9c. Verified MERGED PR whose head oid IS this worktree's HEAD -> reclaimed.
wt_merged=$(make_merged_wt wt-merged)
# Assert the fixture really models the shape, resolving the upstream exactly as
# the script does. NOTE the `|| up=""`: on failure `rev-parse --abbrev-ref` still
# echoes the literal "@{upstream}" on stdout, so only the EXIT CODE distinguishes
# "no upstream" from a branch literally named that. Testing stdout alone silently
# passes a fixture that does not model the shape.
up=$(cd "$wt_merged" && git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || up=""
[ -z "$up" ] || fail "merged-pr fixture: upstream still resolves ('$up'), fixture does not model the shape"
rm -rf "$fleet_home"
rm -f "$tmp/gh-args"
rc=0
FAKE_GH_STATE=MERGED FAKE_GH_OID=$(cd "$wt_merged" && git rev-parse HEAD) \
  run_worktree "$main_repo" "$wt_merged" "merged-pr-leftover" "pr merged, branch auto-deleted" \
  --merged-pr 320 >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "merged-pr worktree: exit $rc, expected 0 (reclaimed)"
[ ! -d "$wt_merged" ] || fail "merged-pr worktree: directory still present after remove"
rows=$(audit_rows --mechanism worktree-cleanup)
case $rows in
  *cleanup*) ;;
  *) fail "merged-pr worktree: no cleanup audit row (got: '$rows')" ;;
esac
# The QUERY SHAPE, not just its answer. `gh` must have been asked about the PR
# number the CALLER named (320) — a script that verified a different PR would be
# checking evidence for the wrong thing — and asked for both fields in one query
# with the template intact. Each arg is its own line, so -Fx matches exactly.
[ -f "$tmp/gh-args" ] || fail "merged-pr worktree: gh was never invoked at all"
grep -Fxq -- '320' "$tmp/gh-args" \
  || fail "merged-pr worktree: gh was not asked about the caller's PR 320 (argv: $(tr '\n' ' ' <"$tmp/gh-args"))"
grep -Fxq -- 'state,headRefOid' "$tmp/gh-args" \
  || fail "merged-pr worktree: gh was not asked for both state and headRefOid"
grep -Fxq -- '{{.state}} {{.headRefOid}}' "$tmp/gh-args" \
  || fail "merged-pr worktree: the state/oid pair template is not intact"
echo "ok: a clean worktree with a verified merged PR is removed and audited"
echo "ok: the gh query names the caller's PR and asks for both fields at once"

# 9d. The same worktree, but the PR is still OPEN -> refused.
wt_open=$(make_merged_wt wt-open)
rc=0
FAKE_GH_STATE=OPEN FAKE_GH_OID=$(cd "$wt_open" && git rev-parse HEAD) \
  run_worktree "$main_repo" "$wt_open" "candidate" "pr not merged" \
  --merged-pr 321 >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "open-pr worktree: exit $rc, expected 5"
[ -d "$wt_open" ] || fail "open-pr worktree: removed despite an unmerged PR"
echo "ok: --merged-pr naming a non-MERGED PR is refused (exit 5)"

# 9e. MERGED, but the PR's head oid is NOT this worktree's HEAD -> refused. This
# is the worktree that carries commits the PR never took.
wt_diverged=$(make_merged_wt wt-diverged)
rc=0
FAKE_GH_STATE=MERGED FAKE_GH_OID=0000000000000000000000000000000000000000 \
  run_worktree "$main_repo" "$wt_diverged" "candidate" "oid mismatch" \
  --merged-pr 322 >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "oid-mismatch worktree: exit $rc, expected 5"
[ -d "$wt_diverged" ] || fail "oid-mismatch worktree: removed despite an oid mismatch"
echo "ok: --merged-pr whose head oid differs from HEAD is refused (exit 5)"

# 9f. gh cannot answer (offline / unauthenticated) -> fail closed, refused.
wt_ghfail=$(make_merged_wt wt-ghfail)
rc=0
FAKE_GH_FAIL=1 \
  run_worktree "$main_repo" "$wt_ghfail" "candidate" "gh unavailable" \
  --merged-pr 323 >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "gh-failure worktree: exit $rc, expected 5"
[ -d "$wt_ghfail" ] || fail "gh-failure worktree: removed although gh could not verify"
echo "ok: --merged-pr with an unusable gh fails closed (exit 5)"

# 9g. REGRESSION GUARD: the default is unchanged. No upstream and no
# --merged-pr is still refused — the new flag widens the evidence class only
# when the caller explicitly supplies and the script verifies it.
wt_noev=$(make_merged_wt wt-noev)
rc=0
run_worktree "$main_repo" "$wt_noev" "candidate" "no evidence offered" \
  >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "no-evidence worktree: exit $rc, expected 5"
[ -d "$wt_noev" ] || fail "no-evidence worktree: removed with no evidence at all"
echo "ok: no upstream and no --merged-pr is still refused (exit 5)"

# 9h. A malformed --merged-pr value is a usage refusal (exit 2), NEVER a query —
# and the "never a query" half is asserted, not merely asserted in a comment:
# gh-args must still be absent afterwards. That is what proves validation runs
# strictly BEFORE the network call, so a hostile token is never handed to a
# subprocess at all; an exit-2 check alone would also pass if the script queried
# gh first and rejected the value afterwards.
wt_bad=$(make_merged_wt wt-bad)
rm -f "$tmp/gh-args"
for bad in "not-a-number" "-5" "0" "12x" "1234567890123" "" "\$(id)"; do
  rc=0
  run_worktree "$main_repo" "$wt_bad" "candidate" "hostile pr token" \
    --merged-pr "$bad" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "malformed --merged-pr '$bad': exit $rc, expected 2"
  [ ! -f "$tmp/gh-args" ] \
    || fail "malformed --merged-pr '$bad': gh was invoked before the value was rejected (argv: $(tr '\n' ' ' <"$tmp/gh-args"))"
done
[ -d "$wt_bad" ] || fail "malformed --merged-pr: worktree was removed"
# An unknown flag in the fourth slot is also a usage error.
rc=0
run_worktree "$main_repo" "$wt_bad" "candidate" "unknown flag" \
  --bogus 320 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "unknown worktree flag: exit $rc, expected 2"
[ ! -f "$tmp/gh-args" ] || fail "unknown worktree flag: gh was invoked despite a usage error"
echo "ok: a malformed --merged-pr value or unknown flag is a usage refusal (exit 2)"
echo "ok: a refused --merged-pr value never reaches gh at all"

# --- 9i-9l. The remaining fail-closed branches of the evidence path, plus the
# precedence between the two paths. Each of these was reachable only in
# principle: deleting the gh-absent guard, or the non-hex-oid guard, from the
# script left the suite fully green, so nothing observed them.

# 9i. `gh` ABSENT entirely, not merely failing: the `command -v gh` guard must
# fail closed. Deleting the stub is NOT enough — PATH still carries the host's
# real gh behind it, which would then be queried against real GitHub. Shadowing
# with a non-executable stub is no good either; `command -v` skips it and keeps
# looking. So PATH is replaced by a directory of symlinks holding the tools the
# worktree arm and its helpers need and NO gh.
#
# The list is deliberately curated rather than a mirror of the whole PATH: that
# is 3500-odd symlinks on a developer machine and cost this suite ~2 minutes.
# Under-provisioning it cannot produce a false pass — the case asserts the
# gh-absent guard's own message, which the script only reaches after the gate,
# the git probes, the self-guard and the clean check have all succeeded, so a
# missing tool fails the case loudly instead of quietly refusing for the wrong
# reason.
nogh="$tmp/nogh"
mkdir -p "$nogh"
for _n in sh bash env git awk sed grep tr cat cut head tail wc sort uniq date \
  mktemp mkdir rmdir mv cp rm ln ls id uname expr basename dirname find touch \
  stat sleep printf tmux; do
  _b=$(PATH="$fakebin:$PATH" command -v "$_n" 2>/dev/null) || continue
  [ -n "$_b" ] && [ -e "$nogh/$_n" ] || ln -s "$_b" "$nogh/$_n" 2>/dev/null || :
done
PATH="$nogh" command -v gh >/dev/null 2>&1 \
  && fail "no-gh PATH: gh still resolves, the fixture is wrong"
PATH="$nogh" command -v git >/dev/null 2>&1 \
  || fail "no-gh PATH: git does not resolve, the fixture is unusable"
# Each of 9i-9k asserts the RESPONSIBLE guard by its message, not just the exit
# code (the stderr-assertion pattern test-fleet-death-evidence.sh uses). These
# three guards are deliberately defence-in-depth: a downstream check refuses the
# same case anyway, so an exit-code-only assertion passes even with the guard
# deleted and would not hold it in place. Short message fragments, to pin the
# guard without coupling to a whole sentence.
wt_ghgone=$(make_merged_wt wt-ghgone)
rc=0
err=$(WT_PATH="$nogh" \
  run_worktree "$main_repo" "$wt_ghgone" "candidate" "no gh binary at all" \
  --merged-pr 324 2>&1 >/dev/null) || rc=$?
[ "$rc" = 5 ] || fail "gh-absent worktree: exit $rc, expected 5"
[ -d "$wt_ghgone" ] || fail "gh-absent worktree: removed although gh was absent"
case $err in
  *"no gh binary on PATH"*) ;;
  *) fail "gh-absent worktree: the gh-absent guard did not refuse it (stderr: $err)" ;;
esac
echo "ok: --merged-pr with no gh binary at all fails closed (exit 5)"

# 9j. gh answers, MERGED, but the head oid is not a plain hex oid -> refused
# before any comparison. The fixture is an UPPERCASE oid: a single token (so the
# shape check passes and this case reaches the hex guard it is here to pin) and a
# realistic drift, since git oids are lowercase and the byte class is matched
# under the pinned C locale. gh's `<no value>` placeholder for a field it cannot
# render is NOT used here — it contains a space, so the shape check catches it
# first; that shape is 9k/9k2's business.
wt_badoid=$(make_merged_wt wt-badoid)
rc=0
err=$(FAKE_GH_STATE=MERGED FAKE_GH_OID='FD581EFA99A3F52ADEC94CF1CEBBB35DEECDB66A' \
  run_worktree "$main_repo" "$wt_badoid" "candidate" "uppercase oid, not plain hex" \
  --merged-pr 325 2>&1 >/dev/null) || rc=$?
[ "$rc" = 5 ] || fail "non-hex-oid worktree: exit $rc, expected 5"
[ -d "$wt_badoid" ] || fail "non-hex-oid worktree: removed on a non-hex head oid"
case $err in
  *"not a plain hex oid"*) ;;
  *) fail "non-hex-oid worktree: the hex-oid guard did not refuse it (stderr: $err)" ;;
esac
echo "ok: --merged-pr whose head oid is not plain hex fails closed (exit 5)"

# 9k. gh exits 0 but its answer carries no separator at all, so the state/oid
# pair cannot be split -> refused, rather than misparsed into a bogus pair.
wt_nopair=$(make_merged_wt wt-nopair)
rc=0
err=$(FAKE_GH_RAW='MERGEDwithoutanyseparator' \
  run_worktree "$main_repo" "$wt_nopair" "candidate" "unsplittable reply" \
  --merged-pr 326 2>&1 >/dev/null) || rc=$?
[ "$rc" = 5 ] || fail "unsplittable-reply worktree: exit $rc, expected 5"
[ -d "$wt_nopair" ] || fail "unsplittable-reply worktree: removed on an unparseable gh reply"
case $err in
  *"could not read the PR's state and head oid"*) ;;
  *) fail "unsplittable-reply worktree: the pair-split guard did not refuse it (stderr: $err)" ;;
esac
echo "ok: --merged-pr with an unsplittable gh reply fails closed (exit 5)"

# 9k2. The OTHER malformed shape: a reply with EXTRA tokens between the two
# fields. Prefix/suffix expansion reads only the first and last word, so
# `MERGED <junk> <matching-oid>` yields exactly the state and oid the reclaim
# wants while silently discarding the middle — the one malformed shape that
# fails OPEN rather than closed. The script asks for a two-field template, so
# it must require exactly two fields and refuse anything else.
wt_extra=$(make_merged_wt wt-extra)
rc=0
err=$(FAKE_GH_RAW="MERGED ignored $(cd "$wt_extra" && git rev-parse HEAD)" \
  run_worktree "$main_repo" "$wt_extra" "candidate" "extra tokens in the reply" \
  --merged-pr 329 2>&1 >/dev/null) || rc=$?
[ "$rc" = 5 ] || fail "extra-token-reply worktree: exit $rc, expected 5 (a 3-field reply is not the 2-field contract)"
[ -d "$wt_extra" ] || fail "extra-token-reply worktree: REMOVED on a malformed reply whose middle field was discarded"
case $err in
  *"could not read the PR's state and head oid"*) ;;
  *) fail "extra-token-reply worktree: the pair-split guard did not refuse it (stderr: $err)" ;;
esac
echo "ok: --merged-pr with extra tokens in the gh reply fails closed (exit 5)"

# 9l. PRECEDENCE: the two evidence paths are independent and either suffices, so
# upstream parity alone reclaims even when --merged-pr is also passed AND gh is
# broken. gh must never be consulted once path A is satisfied — a reclaim that
# needed a working gh to clear an already-provable worktree would make the new
# flag a new dependency rather than a wider evidence class.
wt_both="$tmp/wt-both"
(cd "$main_repo" && git_env git worktree add -q -b feat-both "$wt_both" >/dev/null 2>&1)
(cd "$wt_both" && git_env git push -q -u origin feat-both)
rm -rf "$fleet_home"
rm -f "$tmp/gh-args"
rc=0
FAKE_GH_FAIL=1 \
  run_worktree "$main_repo" "$wt_both" "merged branch" "parity plus a redundant flag" \
  --merged-pr 327 >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "parity-wins worktree: exit $rc, expected 0 (upstream parity alone suffices)"
[ ! -d "$wt_both" ] || fail "parity-wins worktree: directory still present after remove"
[ ! -f "$tmp/gh-args" ] \
  || fail "parity-wins worktree: gh was consulted although upstream parity already held"
echo "ok: upstream parity alone reclaims and never consults gh (exit 0)"

# 9m. The other precedence direction: path B carrying a worktree path A REFUSES.
# The upstream exists and is AHEAD (unpushed commits — path A's own refusal), yet
# a verified merged PR at exactly this HEAD reclaims it. This is the shape a
# squash-merge leaves when the local tip is not what the upstream ref remembers:
# the oid match proves those commits are in the merged PR, so a stale upstream
# count does not veto the stronger proof. Untested until now, and it is the
# RECLAIM direction, so it needs pinning most.
wt_ahead="$tmp/wt-ahead"
(cd "$main_repo" && git_env git worktree add -q -b feat-ahead "$wt_ahead" >/dev/null 2>&1)
(cd "$wt_ahead" && git_env git push -q -u origin feat-ahead >/dev/null 2>&1)
(cd "$wt_ahead" && echo local >>f && git_env git add f && git_env git commit -qm "ahead of upstream")
rm -rf "$fleet_home"
rm -f "$tmp/gh-args"
rc=0
FAKE_GH_STATE=MERGED FAKE_GH_OID=$(cd "$wt_ahead" && git rev-parse HEAD) \
  run_worktree "$main_repo" "$wt_ahead" "merged-pr-leftover" "local tip ahead of a stale upstream" \
  --merged-pr 330 >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "ahead-with-merged-pr worktree: exit $rc, expected 0 (path B rescues an ahead worktree)"
[ ! -d "$wt_ahead" ] || fail "ahead-with-merged-pr worktree: directory still present after remove"
[ -f "$tmp/gh-args" ] || fail "ahead-with-merged-pr worktree: gh was never consulted, so path B did not run"
echo "ok: a verified merged PR reclaims a worktree ahead of its upstream (exit 0)"

# 9n. The clean check is a shared prerequisite of BOTH paths, not merely path A's.
# A DIRTY worktree with an otherwise perfect merged-PR proof is still refused --
# and gh is never consulted at all, because the clean check runs first. That
# ordering is the assertion: evidence, however strong, never buys a reclaim that
# would discard uncommitted work.
wt_dirtypr="$tmp/wt-dirtypr"
(cd "$main_repo" && git_env git worktree add -q -b feat-dirtypr "$wt_dirtypr" >/dev/null 2>&1)
(cd "$wt_dirtypr" && echo scratch >uncommitted.txt)
rm -rf "$fleet_home"
rm -f "$tmp/gh-args"
rc=0
FAKE_GH_STATE=MERGED FAKE_GH_OID=$(cd "$wt_dirtypr" && git rev-parse HEAD) \
  run_worktree "$main_repo" "$wt_dirtypr" "candidate" "dirty despite a merged pr" \
  --merged-pr 331 >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "dirty-with-merged-pr worktree: exit $rc, expected 5 (clean is required for both paths)"
[ -d "$wt_dirtypr" ] || fail "dirty-with-merged-pr worktree: removed despite uncommitted work"
[ ! -f "$tmp/gh-args" ] \
  || fail "dirty-with-merged-pr worktree: gh was consulted before the clean check refused it"
echo "ok: a dirty worktree is refused even with a verified merged PR (exit 5)"

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
