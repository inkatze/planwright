#!/bin/bash
# Tests for the githooks/ backstop layer, its wire step, and its detection
# check (guard-coverage Task 2; D-2, D-3; REQ-A1.2, REQ-A1.3).
#
# Contract under test:
#   - the four tracked, extensionless portable-shell hooks reject, in a wired
#     fixture repo: amend (the positions the client hook can detect: bare
#     `--amend`, and the `-c`/`-C HEAD` message-reuse forms — the `--amend
#     -m`/`-F` family reaches prepare-commit-msg as source `message` and is
#     covered at the glob layer per REQ-A1.1, not here), squash!/fixup!/amend!
#     subjects in any flag position, rebase (`git rebase` and `git pull
#     --rebase`), and every enumerated `main`-push spelling — while normal
#     commits and feature-branch pushes succeed (REQ-A1.2);
#   - `pre-push` fails closed on an unparseable stdin refspec, including the
#     missing-trailing-newline last line (the A1.2 arm of REQ-H1.3's
#     vacuous-input coverage);
#   - the documented deliberate-bypass semantics hold (githooks(5)):
#     --no-verify skips commit-msg and pre-push but NOT prepare-commit-msg,
#     and `git rebase --no-verify` skips pre-rebase (c10);
#   - the wire step is idempotent, and the detection check DETECTS ONLY: it
#     fails on a clone with `core.hooksPath` unset, pointing elsewhere, or
#     with missing/non-executable hook files; passes only on a fully wired
#     clone; and fails (never silently skips) outside a git work tree
#     (REQ-A1.3);
#   - the CI wiring is pinned decidable: ci.yml runs the wire step before
#     `mise run check`, and check:githooks is a member of the `check`
#     aggregate (wire-then-verify, never a silent skip; D-3);
#   - hooks no-op cleanly on a wired clone whose checkout lacks githooks/
#     (the clone-global blast-radius arm of D-3).
#
# Every expected rejection asserts the hook's own "planwright githooks" stderr
# marker, so a failure for an unrelated fixture reason cannot masquerade as a
# hook rejection (fails-for-the-right-reason discipline).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

# Isolate fixtures from the host's global/system git config (autosetuprebase,
# commit signing, a global core.hooksPath would all corrupt the fixtures),
# and pin a no-op editor so editor-opening spellings (-c, --squash,
# --fixup=amend:) run headless.
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_SYSTEM=/dev/null
GIT_EDITOR=true
export GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_EDITOR

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
HOOKS_SRC="$repo_root/githooks"
WIRE="$repo_root/scripts/wire-githooks.sh"
CHECK="$repo_root/scripts/check-githooks.sh"
HOOK_NAMES="pre-push pre-rebase prepare-commit-msg commit-msg"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# ---- fixture-setup assertions: the deliverables this suite copies from must
# ---- exist before any scenario runs (Done-when setup-succeeded floor).
[ -d "$HOOKS_SRC" ] || fail "githooks/ directory missing"
for h in $HOOK_NAMES; do
  [ -f "$HOOKS_SRC/$h" ] || fail "githooks/$h missing"
  [ -x "$HOOKS_SRC/$h" ] || fail "githooks/$h not executable"
done
[ -x "$WIRE" ] || fail "scripts/wire-githooks.sh missing or not executable"
[ -x "$CHECK" ] || fail "scripts/check-githooks.sh missing or not executable"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/githooks-test.XXXXXX") || fail "mktemp failed"
trap 'rm -rf "$tmp"' EXIT

# git with a deterministic, signing-free identity (a stray global
# commit.gpgsign or autosetuprebase must not break fixtures).
gitc() {
  repo="$1"
  shift
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# Expected-rejection helper: the command must fail AND the failure must carry
# the hook layer's own stderr marker (not some unrelated fixture error).
expect_hook_reject() {
  desc="$1"
  shift
  err="$tmp/stderr.capture"
  if "$@" >/dev/null 2>"$err"; then
    fail "$desc: expected the hook to reject, but the command succeeded"
  fi
  grep -q "planwright githooks" "$err" \
    || fail "$desc: command failed, but not by the hook (stderr: $(cat "$err"))"
}

# ---------------------------------------------------------------------------
# Fixture: an origin bare repo seeded with two main commits, and a wired
# work clone. Origin seeding happens BEFORE wiring (post-wire, the hooks
# themselves forbid advancing origin/main — by design).
# ---------------------------------------------------------------------------
origin="$tmp/origin.git"
r="$tmp/work"
git -c init.defaultBranch=main init -q --bare "$origin"
mkdir -p "$r"
gitc "$r" init -q
echo one >"$r/file"
gitc "$r" add file
gitc "$r" commit -qm "chore: seed one"
gitc "$r" remote add origin "$origin"
gitc "$r" push -q origin main
echo two >>"$r/file"
gitc "$r" commit -qam "chore: seed two"
gitc "$r" push -q origin main
# Install the tracked hooks into the fixture and wire it via the wire step.
# Hard-link the repo's own hook inodes where possible: macOS Gatekeeper
# assesses a freshly created script inode on its first execve (tens of
# seconds under load), and links share the already-assessed inodes so the
# suite does not stall once per copy. cp is the cross-volume fallback.
mkdir "$r/githooks"
for h in $HOOK_NAMES; do
  # chmod only the cp fallback: a chmod on a hard link would mutate the
  # repo's own hook file modes (shared inode).
  if ! ln "$HOOKS_SRC/$h" "$r/githooks/$h" 2>/dev/null; then
    cp "$HOOKS_SRC/$h" "$r/githooks/$h"
    chmod +x "$r/githooks/$h"
  fi
done
# Absorb any remaining first-exec assessment in one bounded place, so a
# Gatekeeper stall reads as slow setup, never as a hung git command.
(cd "$r" && printf '' | ./githooks/pre-push origin "file://$origin" >/dev/null 2>&1) || :
(cd "$r" && ./githooks/pre-rebase >/dev/null 2>&1) || :
(cd "$r" && ./githooks/prepare-commit-msg /dev/null message >/dev/null 2>&1) || :
echo warm >"$tmp/warm.msg"
(cd "$r" && ./githooks/commit-msg "$tmp/warm.msg" >/dev/null 2>&1) || :
gitc "$r" add githooks
gitc "$r" commit -qm "chore: track hooks"
(cd "$r" && /bin/sh "$WIRE" >/dev/null) || fail "wire step failed on the fixture clone"
[ "$(gitc "$r" config --get core.hooksPath)" = "githooks" ] \
  || fail "wire step did not set core.hooksPath=githooks"
# Idempotency: a second run succeeds and leaves the same value.
(cd "$r" && /bin/sh "$WIRE" >/dev/null) || fail "wire step not idempotent (second run failed)"
[ "$(gitc "$r" config --get core.hooksPath)" = "githooks" ] \
  || fail "wire step second run changed core.hooksPath"
echo "ok: wire step wires and is idempotent"

# Wire step outside any git repo fails. GIT_CEILING_DIRECTORIES pins the
# not-a-repo premise even when TMPDIR itself sits inside some git work tree.
mkdir "$tmp/notrepo"
if (cd "$tmp/notrepo" && GIT_CEILING_DIRECTORIES="$tmp" /bin/sh "$WIRE" >/dev/null 2>&1); then
  fail "wire step outside a git repo: expected failure, got success"
fi
echo "ok: wire step fails outside a git repo"

# ---------------------------------------------------------------------------
# c1. Normal commits succeed under the wired hooks (main and feature branch).
# ---------------------------------------------------------------------------
echo three >>"$r/file"
gitc "$r" commit -qam "feat: legit change on main" \
  || fail "c1: normal commit on main rejected by the hooks"
gitc "$r" checkout -q -b feat
echo feat >"$r/feat-file"
gitc "$r" add feat-file
gitc "$r" commit -qm "feat: legit change on feature branch" \
  || fail "c1: normal commit on a feature branch rejected by the hooks"
# Diverge main past feat's branch point, so c4's `git rebase main` has real
# work to do (an up-to-date rebase exits before pre-rebase ever runs) —
# and this is itself the second normal-commit-succeeds assertion.
gitc "$r" checkout -q main
echo four >>"$r/file"
gitc "$r" commit -qam "feat: divergent change on main" \
  || fail "c1: second normal commit on main rejected by the hooks"
gitc "$r" checkout -q feat
echo "ok: c1 normal commits succeed"

# ---------------------------------------------------------------------------
# c2. Amend positions the client hook can detect are rejected; repo state is
#     untouched by the aborted attempts.
# ---------------------------------------------------------------------------
head_before=$(gitc "$r" rev-parse HEAD)
expect_hook_reject "c2 --amend" gitc "$r" commit --amend --no-edit
expect_hook_reject "c2 --amend (flag last)" gitc "$r" commit --no-edit --amend
echo staged >>"$r/feat-file"
gitc "$r" add feat-file
expect_hook_reject "c2 -C HEAD message reuse" gitc "$r" commit -C HEAD
expect_hook_reject "c2 -c HEAD message reuse (editor form)" gitc "$r" commit -c HEAD
[ "$(gitc "$r" rev-parse HEAD)" = "$head_before" ] || fail "c2: an amend attempt moved HEAD"
echo "ok: c2 amend spellings rejected"

# ---------------------------------------------------------------------------
# c3. squash!/fixup!/amend! subjects are rejected in any flag position,
#     both via the generating flags and via a literal -m subject.
# ---------------------------------------------------------------------------
expect_hook_reject "c3 --fixup=HEAD" gitc "$r" commit --fixup=HEAD
expect_hook_reject "c3 --squash=HEAD" gitc "$r" commit --squash=HEAD
expect_hook_reject "c3 --fixup=amend:HEAD" gitc "$r" commit --fixup=amend:HEAD
expect_hook_reject "c3 -a --fixup=HEAD (flag position)" gitc "$r" commit -a --fixup=HEAD
expect_hook_reject "c3 -m squash!" gitc "$r" commit -m "squash! anything"
expect_hook_reject "c3 -m fixup!" gitc "$r" commit -m "fixup! anything"
expect_hook_reject "c3 -m amend!" gitc "$r" commit -m "amend! anything"
# git strips comment lines AFTER commit-msg runs: a comment-first file must
# not shadow the real subject.
printf '# a comment line\nfixup! smuggled subject\n' >"$tmp/comment-first.msg"
expect_hook_reject "c3 comment-first -F file" gitc "$r" commit --cleanup=strip -F "$tmp/comment-first.msg"
echo "ok: c3 squash!/fixup!/amend! subjects rejected"

# ---------------------------------------------------------------------------
# c4. `git rebase` is rejected (main diverged past feat's branch point in c1,
#     so this is a real rebase — an up-to-date one never reaches the hook).
#     The `git pull --rebase` spelling is c5b, after c5 freezes origin/main.
# ---------------------------------------------------------------------------
# Consume the staged change so the rebase fixture starts clean.
gitc "$r" commit -qm "feat: second legit change" || fail "c4: staged legit commit rejected"
expect_hook_reject "c4 git rebase" gitc "$r" rebase main
echo "ok: c4 git rebase rejected"

# ---------------------------------------------------------------------------
# c5. Every enumerated main-push spelling is rejected and origin/main never
#     moves; a feature-branch push succeeds.
# ---------------------------------------------------------------------------
origin_main_before=$(git -C "$origin" rev-parse main)
expect_hook_reject "c5 HEAD:refs/heads/main" gitc "$r" push origin HEAD:refs/heads/main
expect_hook_reject "c5 HEAD:main" gitc "$r" push origin HEAD:main
expect_hook_reject "c5 +refs/heads/main" gitc "$r" push origin +refs/heads/main
gitc "$r" branch -q --set-upstream-to=origin/main feat
expect_hook_reject "c5 upstream-is-main bare push" gitc "$r" -c push.default=upstream push
gitc "$r" checkout -q main
expect_hook_reject "c5 HEAD while on main" gitc "$r" push origin HEAD
[ "$(git -C "$origin" rev-parse main)" = "$origin_main_before" ] \
  || fail "c5: a rejected push spelling still moved origin/main"
gitc "$r" push -q origin feat:refs/heads/feature-x \
  || fail "c5: feature-branch push rejected by the hooks"
echo "ok: c5 main-push spellings rejected, feature push succeeds"

# ---------------------------------------------------------------------------
# c5b. `git pull --rebase` is rejected. origin/main is first advanced from an
#      unwired helper clone (the hooks are client-side; an unwired clone can
#      push — which is why REQ-B1.1's CI-side range scan exists for that
#      vector), so feat genuinely diverges and the pull must rebase.
# ---------------------------------------------------------------------------
helper="$tmp/helper"
git clone -q "$origin" "$helper"
gitc "$helper" checkout -q main
echo upstream >>"$helper/file"
gitc "$helper" commit -qam "chore: upstream advance"
gitc "$helper" push -q origin main || fail "c5b: unwired helper clone could not seed origin/main"
gitc "$r" checkout -q feat
expect_hook_reject "c5b git pull --rebase" gitc "$r" pull --rebase -q origin main
echo "ok: c5b git pull --rebase rejected"

# ---------------------------------------------------------------------------
# c6. pre-push fails closed on unparseable stdin (direct invocation), and
#     accepts a well-formed non-main line. Includes the no-trailing-newline
#     last line.
# ---------------------------------------------------------------------------
zeros=0000000000000000000000000000000000000000
pp="$r/githooks/pre-push"
run_pre_push() { (cd "$r" && "$pp" origin "file://$origin"); }
printf 'garbage\n' | run_pre_push >/dev/null 2>&1 \
  && fail "c6: one-token stdin line accepted (must fail closed)"
printf 'a b c\n' | run_pre_push >/dev/null 2>&1 \
  && fail "c6: three-field stdin line accepted (must fail closed)"
printf 'refs/heads/x %s refs/heads/main %s extra\n' "$zeros" "$zeros" | run_pre_push >/dev/null 2>&1 \
  && fail "c6: five-field stdin line accepted (must fail closed)"
printf 'refs/heads/x %s refs/heads/main %s' "$zeros" "$zeros" | run_pre_push >/dev/null 2>&1 \
  && fail "c6: main refspec without trailing newline accepted (must reject)"
printf 'refs/heads/x %s refs/heads/feature-x %s\n' "$zeros" "$zeros" | run_pre_push >/dev/null 2>&1 \
  || fail "c6: well-formed feature refspec line rejected"
printf 'refs/heads/x %s refs/heads/feature-x %s' "$zeros" "$zeros" | run_pre_push >/dev/null 2>&1 \
  || fail "c6: well-formed feature refspec without trailing newline rejected (must accept)"
printf '' | run_pre_push >/dev/null 2>&1 \
  || fail "c6: empty stdin (nothing to push) rejected"
echo "ok: c6 pre-push stdin fail-closed behavior"

# ---------------------------------------------------------------------------
# c7. Detection check: passes only on the fully wired clone; fails on unset,
#     elsewhere-pointing, missing-file, and non-executable half-wired states;
#     fails (never skips) outside a git work tree.
# ---------------------------------------------------------------------------
(cd "$r" && /bin/sh "$CHECK" >/dev/null) || fail "c7: check failed on a fully wired clone"

# This fixture's hooks are only ever stat'd by the check, never executed, so
# plain copies are fine — and REQUIRED: c7 mutates permissions, which on a
# hard link would strip the exec bit from the repo's own hook file.
d="$tmp/unwired"
mkdir -p "$d"
gitc "$d" init -q
mkdir "$d/githooks"
cp "$HOOKS_SRC"/* "$d/githooks/"
chmod +x "$d"/githooks/*
(cd "$d" && /bin/sh "$CHECK" >/dev/null 2>&1) \
  && fail "c7: check passed with core.hooksPath unset"
gitc "$d" config core.hooksPath .git/hooks
(cd "$d" && /bin/sh "$CHECK" >/dev/null 2>&1) \
  && fail "c7: check passed with core.hooksPath pointing elsewhere"
gitc "$d" config core.hooksPath githooks
(cd "$d" && /bin/sh "$CHECK" >/dev/null) || fail "c7: check failed on a wired second clone"
rm "$d/githooks/pre-rebase"
(cd "$d" && /bin/sh "$CHECK" >/dev/null 2>&1) \
  && fail "c7: check passed with a hook file missing"
cp "$HOOKS_SRC/pre-rebase" "$d/githooks/"
chmod +x "$d/githooks/pre-rebase"
chmod -x "$d/githooks/commit-msg"
(cd "$d" && /bin/sh "$CHECK" >/dev/null 2>&1) \
  && fail "c7: check passed with a non-executable hook (git silently skips those)"
chmod +x "$d/githooks/commit-msg"
if (cd "$tmp/notrepo" && GIT_CEILING_DIRECTORIES="$tmp" /bin/sh "$CHECK" >/dev/null 2>&1); then
  fail "c7: check outside a git work tree must fail, not silently skip"
fi
echo "ok: c7 detection check fail/pass matrix"

# ---------------------------------------------------------------------------
# c8. CI wiring is pinned decidable: ci.yml wires before `mise run check`,
#     and check:githooks is in the `check` aggregate (wire-then-verify).
# ---------------------------------------------------------------------------
ci="$repo_root/.github/workflows/ci.yml"
wire_line=$(grep -n "wire-githooks.sh" "$ci" | grep -v "^ *[0-9]*: *#" | head -n 1 | cut -d: -f1)
check_line=$(grep -n "mise run check" "$ci" | grep -v "^ *[0-9]*: *#" | head -n 1 | cut -d: -f1)
[ -n "$wire_line" ] || fail "c8: ci.yml has no wire-githooks.sh step"
[ -n "$check_line" ] || fail "c8: ci.yml has no 'mise run check' step"
[ "$wire_line" -lt "$check_line" ] || fail "c8: ci.yml wire step does not precede 'mise run check'"
# Scope the membership assertion to the [tasks.check] depends block: a bare
# whole-file grep would match the task's own definition header and pass
# vacuously with the aggregate entry deleted.
sed -n '/^\[tasks\.check\]$/,/^\[tasks/p' "$repo_root/mise.toml" | grep -q '"check:githooks"' \
  || fail "c8: check:githooks is not in the check aggregate's depends list"
echo "ok: c8 CI wire-then-verify pinned"

# ---------------------------------------------------------------------------
# c9. Hooks no-op cleanly on a wired clone whose checkout lacks githooks/
#     (clone-global blast radius: a branch without the files must not break).
# ---------------------------------------------------------------------------
b="$tmp/bare-branch"
mkdir -p "$b"
gitc "$b" init -q
gitc "$b" config core.hooksPath githooks
echo x >"$b/f"
gitc "$b" add f
gitc "$b" commit -qm "chore: commit with hooks dir absent" \
  || fail "c9: commit failed on a wired clone without githooks/ files"
gitc "$b" remote add origin "$origin"
gitc "$b" push -q origin HEAD:refs/heads/no-hooks-branch \
  || fail "c9: feature push failed on a wired clone without githooks/ files"
echo "ok: c9 hooks no-op when the files are absent"

# ---------------------------------------------------------------------------
# c10. The documented bypass semantics are pinned empirically (githooks(5)):
#      --no-verify skips commit-msg and pre-push, does NOT suppress
#      prepare-commit-msg, and `git rebase --no-verify` skips pre-rebase.
#      The doc claims corrected by the polish pass live or die by these.
# ---------------------------------------------------------------------------
# Rebase bypass first, on a throwaway branch cut before any fixup!-subject
# commit exists (so a replayed subject can never fail the rebase for an
# unrelated reason).
gitc "$r" checkout -q -b nv-rebase feat
gitc "$r" rebase --no-verify main >/dev/null 2>&1 \
  || fail "c10: git rebase --no-verify did not bypass pre-rebase"
gitc "$r" checkout -q feat
echo nv >>"$r/feat-file"
gitc "$r" add feat-file
gitc "$r" commit -q --no-verify -m "fixup! deliberate human bypass" \
  || fail "c10: --no-verify did not bypass commit-msg"
expect_hook_reject "c10 --amend --no-verify still rejected" \
  gitc "$r" commit --amend --no-edit --no-verify
origin_main_save=$(git -C "$origin" rev-parse main)
gitc "$r" checkout -q main
gitc "$r" push -q --no-verify origin +refs/heads/main \
  || fail "c10: push --no-verify did not bypass pre-push"
git -C "$origin" update-ref refs/heads/main "$origin_main_save" \
  || fail "c10: could not restore fixture origin/main"
echo "ok: c10 no-verify bypass semantics pinned"

echo "PASS: test-githooks.sh"
