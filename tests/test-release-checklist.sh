#!/bin/bash
# Tests for scripts/release-checklist.sh — the public-release readiness gate
# (Task 19; REQ-J1.5, REQ-J1.4, D-27). The checklist VERIFIES the gate
# conditions and the release-blocking gated Deferred entry (the reference/
# history purge); it never performs the purge.
#
# Coverage:
#   - the real repo today is NOT ready (reference/ still present) — the gate
#     fails for the right reason;
#   - a fully-satisfied fixture (gates a/b met, reference/ purged from tree AND
#     history, condition (c) attested) reports READY (exit 0);
#   - condition (c) is human-attested: without the attestation the gate blocks
#     and names it;
#   - a missing meta-spec (gate b) blocks and is named;
#   - reference/ surviving in HISTORY (but absent from the tree) blocks — the
#     history check has teeth beyond the working-tree check;
#   - a non-git target degrades with a clear message rather than passing blind.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/release-checklist.sh"

failures=0
assert_exit() {
  # assert_exit <label> <expected-exit> <actual-exit>
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  # assert_contains <label> <needle> <haystack>
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (output missing '$2')" >&2
      echo "----- output -----" >&2
      echo "$3" >&2
      echo "------------------" >&2
      failures=$((failures + 1))
      ;;
  esac
}

if [ ! -f "$SCRIPT" ]; then
  echo "FAIL: release-checklist script missing at $SCRIPT" >&2
  exit 1
fi

# 1. The real repo today is NOT release-ready: reference/ is still tracked, so
#    the purge gate fails. This is the correct not-ready signal.
out="$("$SCRIPT" "$REPO_ROOT" 2>&1)"
rc=$?
assert_exit "real repo is not release-ready" 1 "$rc"
assert_contains "real repo names the reference/ purge as outstanding" "reference/" "$out"
assert_contains "real repo reports NOT READY" "NOT READY" "$out"

# Fixture builder: a self-contained git repo that satisfies the mechanical
# gates. Caller plants/omits pieces to exercise each branch.
make_fixture() {
  # make_fixture <dir>
  d="$1"
  mkdir -p "$d/scripts" "$d/doctrine"
  cp "$SCRIPT" "$d/scripts/release-checklist.sh"
  # Gate (a): framework intelligence inlined into planwright's own doctrine.
  echo "# validation rigor" >"$d/doctrine/validation-rigor.md"
  echo "# finding categorization" >"$d/doctrine/finding-categorization.md"
  # Gate (b): the four-file format meta-spec.
  echo "# spec format meta-spec" >"$d/doctrine/spec-format.md"
  git -C "$d" init -q
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  git -C "$d" add -A
  git -C "$d" commit -qm "fixture: built planwright (no reference/)"
}

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# 2. Fully-satisfied fixture with condition (c) attested → READY (exit 0).
fx="$tmp/ready"
make_fixture "$fx"
out="$("$fx/scripts/release-checklist.sh" --confirm-workrepo-run "$fx" 2>&1)"
rc=$?
assert_exit "satisfied + attested fixture is READY" 0 "$rc"
assert_contains "READY output says READY" "READY FOR PUBLIC RELEASE" "$out"

# 3. Same fixture, condition (c) NOT attested → blocked, and the work-repo run
#    is named as the outstanding human attestation.
out="$("$fx/scripts/release-checklist.sh" "$fx" 2>&1)"
rc=$?
assert_exit "unattested work-repo run blocks release" 1 "$rc"
assert_contains "unattested run is named" "work" "$out"

# 4. Missing meta-spec (gate b) blocks and is named.
fx2="$tmp/nometa"
make_fixture "$fx2"
rm "$fx2/doctrine/spec-format.md"
git -C "$fx2" add -A
git -C "$fx2" commit -qm "drop meta-spec"
out="$("$fx2/scripts/release-checklist.sh" --confirm-workrepo-run "$fx2" 2>&1)"
rc=$?
assert_exit "missing meta-spec blocks release" 1 "$rc"
assert_contains "missing meta-spec is named" "meta-spec" "$out"

# 5. reference/ purged from the working tree but SURVIVING in history → the
#    history check must still fail (the purge requires a history rewrite, not a
#    plain delete commit). This is the regression guard that distinguishes a
#    real purge from `git rm`.
fx3="$tmp/historyleak"
make_fixture "$fx3"
mkdir -p "$fx3/reference"
echo "transient migration source" >"$fx3/reference/leak.md"
git -C "$fx3" add -A
git -C "$fx3" commit -qm "add reference/ (will be deleted but not purged)"
git -C "$fx3" rm -qr reference
git -C "$fx3" commit -qm "delete reference/ from the tree (history still has it)"
out="$("$fx3/scripts/release-checklist.sh" --confirm-workrepo-run "$fx3" 2>&1)"
rc=$?
assert_exit "reference/ in history blocks release" 1 "$rc"
assert_contains "history leak is reported" "history" "$out"

# 6. Non-git target degrades clearly (REQ-K1.7) rather than passing blind.
fx4="$tmp/notgit"
mkdir -p "$fx4/scripts" "$fx4/doctrine"
cp "$SCRIPT" "$fx4/scripts/release-checklist.sh"
echo "# v" >"$fx4/doctrine/validation-rigor.md"
echo "# f" >"$fx4/doctrine/finding-categorization.md"
echo "# s" >"$fx4/doctrine/spec-format.md"
out="$("$fx4/scripts/release-checklist.sh" --confirm-workrepo-run "$fx4" 2>&1)"
rc=$?
assert_exit "non-git target does not pass blind" 1 "$rc"
assert_contains "non-git target says so clearly" "not a git repository" "$out"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all release-checklist tests passed"
