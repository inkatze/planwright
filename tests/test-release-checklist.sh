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
  # Gate (a): framework intelligence inlined into planwright's own doctrine —
  # one representative doc per category the gate names (a rigor doc, finding
  # categorization, the engineering doctrine).
  echo "# validation rigor" >"$d/doctrine/validation-rigor.md"
  echo "# finding categorization" >"$d/doctrine/finding-categorization.md"
  echo "# engineering decisions" >"$d/doctrine/engineering-decisions.md"
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
#    is named as the outstanding human attestation. The needle is specific
#    ("work-repo run", not the generic "work" which also matches "working
#    tree") so the assertion cannot pass for the wrong row.
out="$("$fx/scripts/release-checklist.sh" "$fx" 2>&1)"
rc=$?
assert_exit "unattested work-repo run blocks release" 1 "$rc"
assert_contains "unattested run is named" "work-repo run" "$out"
assert_contains "unattested run asks for attestation" "HUMAN ATTESTATION" "$out"

# 3b. Condition (c) is equally attestable via the environment variable, not
#     only the flag.
out="$(RELEASE_WORKREPO_RUN_CONFIRMED=1 "$fx/scripts/release-checklist.sh" "$fx" 2>&1)"
rc=$?
assert_exit "env-var attestation is honored" 0 "$rc"
assert_contains "env-var attestation reaches READY" "READY FOR PUBLIC RELEASE" "$out"

# 3b-i. The attestation accepts only an explicit "1": a falsy
#       RELEASE_WORKREPO_RUN_CONFIRMED (0, false, "") must NOT register as
#       attested, so a mis-set env var cannot silently clear the human gate.
out="$(RELEASE_WORKREPO_RUN_CONFIRMED=0 "$fx/scripts/release-checklist.sh" "$fx" 2>&1)"
rc=$?
assert_exit "falsy RELEASE_WORKREPO_RUN_CONFIRMED=0 does not attest" 1 "$rc"
assert_contains "falsy =0 still asks for attestation" "HUMAN ATTESTATION" "$out"
out="$(RELEASE_WORKREPO_RUN_CONFIRMED=false "$fx/scripts/release-checklist.sh" "$fx" 2>&1)"
rc=$?
assert_exit "falsy RELEASE_WORKREPO_RUN_CONFIRMED=false does not attest" 1 "$rc"

# 3c. Gate (a) requires the engineering-doctrine doc too: removing it BLOCKS and
#     the gate is named (the gate is a faithful proxy for all three doc
#     categories it documents, not just two).
fxa="$tmp/noeng"
make_fixture "$fxa"
rm "$fxa/doctrine/engineering-decisions.md"
git -C "$fxa" add -A
git -C "$fxa" commit -qm "drop engineering doctrine"
out="$("$fxa/scripts/release-checklist.sh" --confirm-workrepo-run "$fxa" 2>&1)"
rc=$?
assert_exit "missing engineering doctrine blocks gate (a)" 1 "$rc"
assert_contains "missing engineering doctrine is named" "engineering-decisions.md" "$out"

# 3d. Gate (a) treats an empty (0-byte) rule doc as not-inlined (BLOCK), not a
#     pass — presence alone is not enough.
fxe="$tmp/emptydoc"
make_fixture "$fxe"
: >"$fxe/doctrine/validation-rigor.md"
git -C "$fxe" add -A
git -C "$fxe" commit -qm "empty a rule doc" --allow-empty
out="$("$fxe/scripts/release-checklist.sh" --confirm-workrepo-run "$fxe" 2>&1)"
rc=$?
assert_exit "empty rule doc blocks gate (a)" 1 "$rc"
assert_contains "empty rule doc is named" "validation-rigor.md" "$out"

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
echo "# e" >"$fx4/doctrine/engineering-decisions.md"
echo "# s" >"$fx4/doctrine/spec-format.md"
out="$("$fx4/scripts/release-checklist.sh" --confirm-workrepo-run "$fx4" 2>&1)"
rc=$?
assert_exit "non-git target does not pass blind" 1 "$rc"
assert_contains "non-git target says so clearly" "not a git repository" "$out"

# 7. Usage errors exit 2 (distinct from "not ready", exit 1), so a
#    mis-invocation is never mistaken for a clean release verdict.
"$SCRIPT" --bogus-flag >/dev/null 2>&1
assert_exit "unknown flag is a usage error" 2 $?

"$SCRIPT" "$REPO_ROOT" "$REPO_ROOT" >/dev/null 2>&1
assert_exit "a second positional is a usage error" 2 $?

# A second positional after the -- separator must be rejected too (not
# silently dropped) — the -- arm shares the one-repo-dir contract.
"$SCRIPT" -- "$REPO_ROOT" extra >/dev/null 2>&1
assert_exit "extra positional after -- is a usage error" 2 $?

# A lone repo-dir after -- is still accepted (the separator itself is fine).
"$SCRIPT" -- "$REPO_ROOT" >/dev/null 2>&1
assert_exit "single positional after -- is accepted (exit 1, not ready)" 1 $?

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all release-checklist tests passed"
