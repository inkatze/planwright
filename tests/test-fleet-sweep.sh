#!/bin/bash
# Tests for scripts/fleet-sweep.sh — the periodic dirty-tree sweep that also
# doubles as the REQ-A1.8 reconcile-from-ground-truth backstop for missed pushes
# (Task 4: D-8, D-1; REQ-B1.3, REQ-A1.8).
#
# DIRTY-TREE SWEEP (REQ-B1.3, D-8). Every working tree the fleet tracks — every
# registered worker worktree AND the tower's own checkout, whatever branch — is
# checked for uncommitted OR unpushed diffs. A tree that has been dirty past a
# configured grace threshold is ESCALATED to the decision queue
# (fleet-attention.sh decide), never silently left. The dirty/clean state is
# re-verified immediately before escalating, and a tree that cannot be inspected
# (git-lock contention, not a repo) is escalated as "could not inspect" rather
# than misread as clean (kickoff risk 10).
#
# RECONCILE BACKSTOP (REQ-A1.8, D-1). The same sweep re-runs the level-triggered
# tasks.md reconcile (tasks-pr-sync.sh reconcile) for every spec bundle in the
# tower's checkout, so a dropped `gh pr create`/`merge` hook event self-heals
# from git ground truth on the next cycle — without a second push.
#
# KILL-SWITCH + AUDIT. The sweep is a daemon action: it gates through
# fleet-daemon-gate.sh (paused => no sweep) and audits each escalation, and each
# reconcile that actually corrected drift, through fleet-audit.sh.
#
# Covered: clean+pushed tree (no false escalation); uncommitted and unpushed
# escalations; a registered worker-worktree stale diff (risk 36); TWO dirty trees
# in one sweep (risks 12/17); an un-inspectable tree escalated not skipped (risk
# 10); the grace threshold (a just-dirty tree waits, an aged one escalates); a
# leading-zero threshold and a corrupt leading-zero grace marker both rejected as
# octal rather than mis-parsed; a self-healed tree's escalation auto-cleared from
# the decision queue; the kill-switch pausing the whole sweep; and the reconcile
# backstop correcting a drifted tasks.md snapshot.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-sweep.sh
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
SWEEP="$here/../scripts/fleet-sweep.sh"
FA="$here/../scripts/fleet-audit.sh"
WT="$here/../scripts/fleet-worktree-track.sh"
ATTN="$here/../scripts/fleet-attention.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SWEEP" ] || fail "scripts/fleet-sweep.sh missing or not executable"
command -v jq >/dev/null 2>&1 || fail "jq required to run this suite (reconcile backstop)"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- config layers: kill-switch off, dirty-tree grace threshold 0 (escalate on
#     first detection) unless a case overrides the core file.
core_cfg="$tmp/core-defaults.yml"
repo_cfg_root="$tmp/cfgrepo"
mkdir -p "$repo_cfg_root/.claude"
write_core() { # $1 = threshold token (e.g. 0m, 60m)
  printf 'fleet_daemon_pause: false\nfleet_dirty_tree_threshold: %s\n' "$1" >"$core_cfg"
}
write_core 0m

fleet_home="$tmp/fleet"

git_env() {
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t "$@"
}

# --- gh stub (borrowed from test-tasks-pr-sync): deterministic, no network.
stub="$tmp/bin"
mkdir -p "$stub"
cat >"$stub/gh" <<'EOF'
#!/bin/sh
# Minimal gh: `pr list` returns nothing (no open/merged PRs); everything else
# is a benign empty success.
exit 0
EOF
chmod +x "$stub/gh"

# make_pushed_repo <dir> — a git repo with an origin remote, clean and pushed.
make_pushed_repo() {
  git_env git init -q -b main "$1"
  (cd "$1" && echo seed >f && git_env git add f && git_env git commit -qm seed)
  git_env git init -q --bare "$1.git"
  (cd "$1" && git_env git remote add origin "$1.git" && git_env git push -q -u origin main)
}

run_sweep() {
  PATH="$stub:$PATH" \
    PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_REPO_ROOT="$repo_cfg_root" \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$SWEEP" "$@"
}

queue_count() {
  PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$ATTN" queue --count 2>/dev/null
}
audit_rows() {
  PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$FA" query "$@" 2>/dev/null
}
track() {
  PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" /bin/bash "$WT" "$@"
}

# 1. A clean, fully-pushed tower checkout: no escalation.
rm -rf "$fleet_home"
clean="$tmp/clean"
make_pushed_repo "$clean"
run_sweep --repo "$clean" >/dev/null 2>&1 || fail "sweep (clean) non-zero exit"
[ "$(queue_count)" = 0 ] || fail "clean tree escalated a false positive (queue=$(queue_count))"
echo "ok: a clean, pushed tower checkout is not escalated"

# 2. Uncommitted changes on the tower checkout are escalated (REQ-B1.3, D-8).
rm -rf "$fleet_home"
dirty="$tmp/dirty"
make_pushed_repo "$dirty"
(cd "$dirty" && echo scratch >stale.txt)
run_sweep --repo "$dirty" >/dev/null 2>&1 || fail "sweep (dirty) non-zero exit"
[ "$(queue_count)" -ge 1 ] || fail "uncommitted diff was NOT escalated (queue=$(queue_count))"
case $(audit_rows --mechanism housekeeping-sweep) in
  *escalate*) ;;
  *) fail "dirty tree: no escalate audit row" ;;
esac
echo "ok: an uncommitted diff on the tower's own checkout is escalated and audited"

# 3. Committed-but-unpushed changes are escalated too.
rm -rf "$fleet_home"
unpushed="$tmp/unpushed"
make_pushed_repo "$unpushed"
(cd "$unpushed" && echo more >>f && git_env git add f && git_env git commit -qm local)
run_sweep --repo "$unpushed" >/dev/null 2>&1 || fail "sweep (unpushed) non-zero exit"
[ "$(queue_count)" -ge 1 ] || fail "unpushed commit was NOT escalated"
echo "ok: an unpushed commit is escalated"

# 4. A registered WORKER worktree with a stale diff is escalated (risk 36), even
#    when the tower's own checkout is clean.
rm -rf "$fleet_home"
main_repo="$tmp/wmain"
make_pushed_repo "$main_repo"
worker_wt="$tmp/worker-wt"
(cd "$main_repo" && git_env git worktree add -q -b feat "$worker_wt" >/dev/null 2>&1)
(cd "$worker_wt" && echo wip >wip.txt)
track record-create "$(cd "$worker_wt" && pwd -P)" >/dev/null
run_sweep --repo "$main_repo" >/dev/null 2>&1 || fail "sweep (worker wt) non-zero exit"
[ "$(queue_count)" -ge 1 ] || fail "a stale worker-worktree diff was NOT escalated"
echo "ok: a registered worker worktree's stale diff is escalated"

# 5. TWO dirty trees in one sweep produce two distinct escalations (risks 12/17).
rm -rf "$fleet_home"
m2="$tmp/m2"
make_pushed_repo "$m2"
wtA="$tmp/wtA"
wtB="$tmp/wtB"
(cd "$m2" && git_env git worktree add -q -b fa "$wtA" >/dev/null 2>&1)
(cd "$m2" && git_env git worktree add -q -b fb "$wtB" >/dev/null 2>&1)
(cd "$wtA" && echo a >a.txt)
(cd "$wtB" && echo b >b.txt)
track record-create "$(cd "$wtA" && pwd -P)" >/dev/null
track record-create "$(cd "$wtB" && pwd -P)" >/dev/null
run_sweep --repo "$m2" >/dev/null 2>&1 || fail "sweep (two wt) non-zero exit"
[ "$(queue_count)" -ge 2 ] || fail "two dirty trees did not yield >=2 escalations (queue=$(queue_count))"
echo "ok: a multi-worktree sweep escalates each dirty tree distinctly"

# 6. An un-inspectable registered tree (exists, not a git repo) is escalated as
#    "could not inspect", never silently skipped (risk 10).
rm -rf "$fleet_home"
c6="$tmp/c6"
make_pushed_repo "$c6"
notrepo="$tmp/not-a-repo"
mkdir -p "$notrepo"
echo x >"$notrepo/x"
track record-create "$notrepo" >/dev/null
run_sweep --repo "$c6" >/dev/null 2>&1 || fail "sweep (uninspectable) non-zero exit"
[ "$(queue_count)" -ge 1 ] || fail "an un-inspectable tree was silently skipped"
case $(audit_rows --mechanism housekeeping-sweep) in
  *escalate*) ;;
  *) fail "uninspectable tree: no escalate audit row" ;;
esac
echo "ok: an un-inspectable tree is escalated, not silently skipped"

# 6b. A registered tree that EXISTS but cannot be `cd`'d into (a regular file,
#     not a directory — e.g. a worktree path clobbered by a file, or a dir with
#     search permission stripped) must NOT be silently dropped by the tree-list
#     builder's realpath step; it flows through as-is so inspect_tree escalates
#     it as "could not inspect" (risk 10). Regression: the builder used
#     `cd ... || continue`, which dropped an existing-but-unreadable tree before
#     inspect_tree ever saw it — inconsistent with `scan`'s own prune, which
#     keeps an existing-but-unreadable path as-is.
rm -rf "$fleet_home"
c6b="$tmp/c6b"
make_pushed_repo "$c6b"
notcd="$tmp/not-cd-able"
echo x >"$notcd" # a regular FILE: `-e` is true but `cd` into it fails
track record-create "$notcd" >/dev/null
run_sweep --repo "$c6b" >/dev/null 2>&1 || fail "sweep (not-cd-able) non-zero exit"
[ "$(queue_count)" -ge 1 ] || fail "an existing-but-not-cd-able tree was silently dropped, not escalated"
case $(audit_rows --mechanism housekeeping-sweep) in
  *escalate*) ;;
  *) fail "not-cd-able tree: no escalate audit row" ;;
esac
echo "ok: an existing-but-not-cd-able tree is escalated as uninspectable, not silently dropped"

# 7. Grace threshold: a just-became-dirty tree waits (not escalated on the first
#    sweep) under a non-zero threshold; an aged one (dirty-since older than the
#    threshold) escalates.
rm -rf "$fleet_home"
write_core 60m
g="$tmp/grace"
make_pushed_repo "$g"
(cd "$g" && echo new >new.txt)
run_sweep --repo "$g" >/dev/null 2>&1 || fail "sweep (grace, first) non-zero exit"
[ "$(queue_count)" = 0 ] || fail "grace: a just-dirty tree escalated before the threshold"
# Back-date the dirty-since marker so the tree now reads as sitting past 60m.
since_dir="$fleet_home/worktrees/dirty-since"
[ -d "$since_dir" ] || fail "grace: no dirty-since marker recorded on first detection"
old=$(($(date +%s) - 5000))
for mk in "$since_dir"/*; do
  [ -e "$mk" ] || continue
  printf '%s\n' "$old" >"$mk"
done
run_sweep --repo "$g" >/dev/null 2>&1 || fail "sweep (grace, aged) non-zero exit"
[ "$(queue_count)" -ge 1 ] || fail "grace: an aged dirty tree did not escalate"
write_core 0m
echo "ok: the grace threshold defers a fresh dirty tree and escalates an aged one"

# 7b. A leading-zero threshold (`08m`) must NOT be read as octal (which would
#     blow up the arithmetic and empty THRESHOLD); it parses as 8 minutes. A
#     fresh dirty tree waits (8m grace), an aged one escalates — proving the
#     threshold was a real positive number, not a broken/empty one.
rm -rf "$fleet_home"
write_core 08m
oz="$tmp/octal"
make_pushed_repo "$oz"
(cd "$oz" && echo new >new.txt)
run_sweep --repo "$oz" >/dev/null 2>&1 || fail "sweep (octal threshold) non-zero exit"
[ "$(queue_count)" = 0 ] || fail "octal threshold: 08m did not parse as an 8m grace (fresh tree escalated)"
since_dir="$fleet_home/worktrees/dirty-since"
old=$(($(date +%s) - 5000))
for mk in "$since_dir"/*; do
  [ -e "$mk" ] || continue
  printf '%s\n' "$old" >"$mk"
done
run_sweep --repo "$oz" >/dev/null 2>&1 || fail "sweep (octal threshold, aged) non-zero exit"
[ "$(queue_count)" -ge 1 ] || fail "octal threshold: an aged tree did not escalate under 08m"
write_core 0m
echo "ok: a leading-zero threshold (08m) parses as 8 minutes, not octal"

# 7c. A CORRUPT leading-zero dirty-since marker (e.g. `0900000000`) must NOT be
#     read as octal by the grace arithmetic: under the dash `/bin/sh` floor that
#     is a fatal error that aborts the whole sweep mid-loop (Pass 2 reconcile
#     never runs); under bash it mis-parses. The marker read must reject it
#     (matching threshold_seconds and the sibling integer-reads) so the grace
#     clock re-plants and the tree keeps deferring instead of escalating on a
#     garbage age (regression for the octal-since bug).
rm -rf "$fleet_home"
write_core 60m
cz="$tmp/corruptzero"
make_pushed_repo "$cz"
(cd "$cz" && echo new >new.txt)
run_sweep --repo "$cz" >/dev/null 2>&1 || fail "sweep (corrupt-marker, first) non-zero exit"
[ "$(queue_count)" = 0 ] || fail "corrupt-marker: fresh dirty tree escalated before the threshold"
since_dir="$fleet_home/worktrees/dirty-since"
[ -d "$since_dir" ] || fail "corrupt-marker: no dirty-since marker recorded on first detection"
for mk in "$since_dir"/*; do
  [ -e "$mk" ] || continue
  printf '%s\n' "0900000000" >"$mk"
done
# The buggy (unguarded) read leaks the marker straight into `age=$((now - since))`,
# which emits an octal arithmetic error ("value too great for base" under bash,
# "Illegal number" and a FATAL sweep abort under dash) and leaves the corrupt
# marker in place. The guarded read rejects the leading-zero token and re-plants a
# fresh clock, so no arithmetic error escapes and the marker becomes a valid epoch.
cm_err=$(run_sweep --repo "$cz" 2>&1 1>/dev/null) || fail "sweep (corrupt-marker) aborted or non-zero — a leading-zero marker was not guarded against octal"
case $cm_err in
  *"value too great"* | *"Illegal number"* | *"integer expression"*)
    fail "corrupt-marker: a leading-zero grace marker leaked into the arithmetic (octal error): $cm_err"
    ;;
esac
[ "$(queue_count)" = 0 ] || fail "corrupt-marker: a leading-zero grace marker was octal-misread and escalated"
cm_after=$(cat "$since_dir"/* 2>/dev/null)
case $cm_after in
  "" | *[!0-9]* | 0?*) fail "corrupt-marker: the grace clock was not re-planted to a valid epoch (still '$cm_after')" ;;
esac
write_core 0m
echo "ok: a corrupt leading-zero dirty-since marker is rejected, not read as octal"

# 7d. Auto-clear on self-heal: an escalated tree that becomes clean+pushed has
#     its decision-queue entry retracted on the next sweep, so a resolved
#     condition does not leave a standing false alarm (keyed on the same
#     `sweep-<tree-id>` handle the escalation used).
rm -rf "$fleet_home"
write_core 0m
sh_repo="$tmp/selfheal"
make_pushed_repo "$sh_repo"
(cd "$sh_repo" && echo wip >wip.txt)
run_sweep --repo "$sh_repo" >/dev/null 2>&1 || fail "sweep (self-heal, escalate) non-zero exit"
[ "$(queue_count)" -ge 1 ] || fail "self-heal: the dirty tree was not escalated first (queue=$(queue_count))"
# Resolve the underlying condition: commit and push so the tree is clean+pushed.
(cd "$sh_repo" && git_env git add wip.txt && git_env git commit -qm wip && git_env git push -q origin main)
run_sweep --repo "$sh_repo" >/dev/null 2>&1 || fail "sweep (self-heal, cleared) non-zero exit"
[ "$(queue_count)" = 0 ] || fail "self-heal: the escalation was not retracted after the tree became clean (queue=$(queue_count))"
echo "ok: a self-healed tree's escalation is auto-cleared from the decision queue"

# 8. The kill-switch pauses the whole sweep.
rm -rf "$fleet_home"
k="$tmp/kill"
make_pushed_repo "$k"
(cd "$k" && echo scratch >stale.txt)
printf 'fleet_daemon_pause: true\nfleet_dirty_tree_threshold: 0m\n' >"$core_cfg"
rc=0
run_sweep --repo "$k" >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "kill-switch: sweep exit $rc, expected 4 (paused)"
[ "$(queue_count)" = 0 ] || fail "kill-switch: the sweep escalated while paused"
write_core 0m
echo "ok: the kill-switch pauses the whole sweep (exit 4)"

# 9. Reconcile backstop (REQ-A1.8): a spec bundle whose tasks.md snapshot lags
#    git ground truth (a dropped reconcile hook) is corrected on the sweep — a
#    task derived Completed via its Planwright-Task trailer, still parked in
#    ## Forward plan, is moved to ## Completed. No second push.
rm -rf "$fleet_home"
rr="$tmp/reconcile-repo"
git_env git init -q -b main "$rr"
mkdir -p "$rr/specs/demo"
printf '%s\n' '# Demo — Requirements' '' '**Status:** Active' >"$rr/specs/demo/requirements.md"
printf '%s\n' '# Demo — Design' >"$rr/specs/demo/design.md"
printf '%s\n' '# Demo — Test Spec' >"$rr/specs/demo/test-spec.md"
cat >"$rr/specs/demo/tasks.md" <<'EOF'
# Demo — Tasks

**Status:** Active
**Last reviewed:** 2026-07-17
**Format-version:** 1

Intro prose.

## Forward plan

### Task 1 — Widget core

- **Deliverables:** A widget core.
- **Done when:** Widgets exist.
- **Dependencies:** none
- **Citations:** REQ-X1.1
- **Estimated effort:** 1 day

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

(none yet)

## Deferred

(none yet)

## Out of scope

(none)
EOF
git_env git -C "$rr" add -A
git_env git -C "$rr" commit -qm "chore: fixture"
# Task 1 derives Completed: a commit carrying its Planwright-Task trailer.
git_env git -C "$rr" commit -q --allow-empty -m "feat: task 1 done

Planwright-Task: demo/1"

section_of() { # $1 = tasks.md, $2 = id -> section
  awk -v id="$2" '/^## /{sec=substr($0,4)} index($0,"### Task " id " ")==1{print sec; exit}' "$1"
}
before=$(section_of "$rr/specs/demo/tasks.md" 1)
[ "$before" = "Forward plan" ] || fail "reconcile fixture: Task 1 not initially in Forward plan (got '$before')"

run_sweep --repo "$rr" >/dev/null 2>&1 || fail "sweep (reconcile) non-zero exit"
after=$(section_of "$rr/specs/demo/tasks.md" 1)
[ "$after" = "Completed" ] || fail "reconcile backstop did not correct drift: Task 1 in '$after', expected Completed"
case $(audit_rows --mechanism housekeeping-sweep) in
  *reconcile*) ;;
  *) fail "reconcile backstop: no reconcile audit row" ;;
esac
echo "ok: the reconcile backstop corrects a drifted tasks.md snapshot on the sweep"

echo "ALL PASS: fleet-sweep"
