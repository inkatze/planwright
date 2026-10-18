#!/bin/bash
# Tests for scripts/review-scope-fence.sh — the reviewer-basics scope fence:
# every touched file outside the unit's deliverables is reported
# (review-effectiveness REQ-A1.7, D-2).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FENCE="$REPO_ROOT/scripts/review-scope-fence.sh"

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_exit() {
  if [ "$2" -eq "$3" ]; then ok "$1"; else fail "$1 (expected exit $2, got $3)"; fi
}
assert_contains() {
  case "$3" in
    *"$2"*) ok "$1" ;;
    *) fail "$1 (missing '$2' in: $3)" ;;
  esac
}
assert_lacks() {
  case "$3" in
    *"$2"*) fail "$1 (unexpectedly contains '$2')" ;;
    *) ok "$1" ;;
  esac
}

T=$(mktemp -d "${TMPDIR:-/tmp}/rsf.XXXXXX")
trap 'rm -rf "$T"' EXIT

cat >"$T/contract.md" <<'EOF'
### Task 2 — Change the status contract

- **Deliverables:** `scripts/lib.sh` returning 2 on failure, run with
  `--strict <mode>`; the doctrine under `doctrine/status/`; every
  `tests/test-*.sh` it touches.
- **Done when:** the callers read the new code.
EOF
printf '%s\n' scripts/lib.sh doctrine/status/codes.md tests/test-lib.sh >"$T/inside.txt"

# --- inside the deliverables: silent ------------------------------------------
out=$("$FENCE" --changed "$T/inside.txt" --contract "$T/contract.md" 2>&1)
assert_exit "every file inside the deliverables passes" 0 $?
if [ -z "$out" ]; then ok "silent when nothing is outside"; else fail "silent when nothing is outside (got: $out)"; fi

# --- outside: one finding per file --------------------------------------------
printf '%s\n' scripts/lib.sh scripts/other.sh doctrine/statusx.md README.md >"$T/mixed.txt"
out=$("$FENCE" --changed "$T/mixed.txt" --contract "$T/contract.md" 2>/dev/null)
assert_exit "a file outside the deliverables is a finding" 1 $?
assert_contains "names the outside script" "outside	scripts/other.sh" "$out"
assert_contains "a directory prefix does not admit a sibling name" "outside	doctrine/statusx.md" "$out"
assert_contains "names the outside doc" "outside	README.md" "$out"
assert_lacks "an exact deliverable is not reported" "scripts/lib.sh" "$out"
assert_lacks "an option in backticks is not a deliverable" "strict" "$out"

# --- --allow widens the fence; --deliverables replaces the contract -----------
out=$("$FENCE" --changed "$T/mixed.txt" --contract "$T/contract.md" \
  --allow scripts/other.sh --allow 'doctrine/*.md' --allow README.md 2>&1)
assert_exit "allowed entries are inside" 0 $?
printf '%s\n' 'scripts/' >"$T/deliv.txt"
out=$("$FENCE" --changed "$T/mixed.txt" --deliverables "$T/deliv.txt" 2>/dev/null)
assert_exit "a deliverables list stands in for the contract" 1 $?
assert_lacks "a prefix entry admits its tree" "scripts/" "$out"
assert_contains "outside the listed prefix" "outside	README.md" "$out"

# --- a bundle supplies both inputs --------------------------------------------
B=$T/bundle
mkdir -p "$B"
printf 'review-handoff\t1\n' >"$B/MANIFEST"
cp "$T/mixed.txt" "$B/changed-files.txt"
cp "$T/contract.md" "$B/contract.md"
out=$("$FENCE" --bundle "$B" 2>/dev/null)
assert_exit "a bundle's changed files and contract are fenced" 1 $?
assert_contains "bundle mode names the outside file" "outside	scripts/other.sh" "$out"

# --- refused inputs -----------------------------------------------------------
out=$("$FENCE" --changed "$T/mixed.txt" 2>&1)
assert_exit "no deliverables source is a usage error" 2 $?
printf -- '- **Done when:** nothing listed.\n' >"$T/empty-contract.md"
out=$("$FENCE" --changed "$T/mixed.txt" --contract "$T/empty-contract.md" 2>&1)
assert_exit "a contract naming no deliverable path is refused" 2 $?
assert_contains "says why" "no deliverable" "$out"
rm "$B/contract.md"
out=$("$FENCE" --bundle "$B" 2>&1)
assert_exit "a bundle without a contract is refused" 2 $?
out=$("$FENCE" --bundle "$T" 2>&1)
assert_exit "a directory that is not a bundle is refused" 2 $?

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all review-scope-fence tests passed"
