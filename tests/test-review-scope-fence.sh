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
  `--strict <mode>` or `--out=.claude/x`; the doctrine under
  `doctrine/status/`; every `tests/test-*.sh` it touches.
- **Done when:** the callers read the new code and `README.md` says so.

Prose after the field names `notes/prose.md`, which admits nothing.

```sh
# a fenced example naming `fenced/example.sh`
```
EOF
printf '%s\n' scripts/lib.sh doctrine/status/codes.md tests/test-lib.sh >"$T/inside.txt"

# --- inside the deliverables: silent ------------------------------------------
out=$("$FENCE" --changed "$T/inside.txt" --contract "$T/contract.md" 2>&1)
assert_exit "every file inside the deliverables passes" 0 $?
if [ -z "$out" ]; then ok "silent when nothing is outside"; else fail "silent when nothing is outside (got: $out)"; fi

# --- outside: one finding per file --------------------------------------------
printf '%s\n' scripts/lib.sh scripts/other.sh doctrine/statusx.md README.md \
  --out=.claude/x notes/prose.md fenced/example.sh >"$T/mixed.txt"
out=$("$FENCE" --changed "$T/mixed.txt" --contract "$T/contract.md" 2>/dev/null)
assert_exit "a file outside the deliverables is a finding" 1 $?
assert_contains "names the outside script" "outside	scripts/other.sh" "$out"
assert_contains "a directory prefix does not admit a sibling name" "outside	doctrine/statusx.md" "$out"
assert_contains "names the outside doc" "outside	README.md" "$out"
assert_lacks "an exact deliverable is not reported" "scripts/lib.sh" "$out"
assert_contains "an option in backticks is not a deliverable" "outside	--out=.claude/x" "$out"
assert_contains "a path in another field is not a deliverable" "outside	README.md" "$out"
assert_contains "prose after the field admits nothing" "outside	notes/prose.md" "$out"
assert_contains "a fenced example admits nothing" "outside	fenced/example.sh" "$out"

# --- a fence inside the field neither ends it nor admits ------------
cat >"$T/fenced-contract.md" <<'EOF'
### Task 3 — Fenced

- **Deliverables:** `scripts/a.sh`, used as
```sh
# not a heading, and `fenced/inside.sh` is no deliverable
```
  and `scripts/b.sh`.
EOF
printf '%s\n' scripts/a.sh scripts/b.sh fenced/inside.sh >"$T/ab.txt"
out=$("$FENCE" --changed "$T/ab.txt" --contract "$T/fenced-contract.md" 2>&1)
assert_exit "a fence inside the field is reported, not admitted" 1 $?
assert_lacks "a comment line in a fence does not end the field" "scripts/b.sh" "$out"
assert_contains "a path inside the fence is not a deliverable" "outside	fenced/inside.sh" "$out"

# --- --allow widens the fence; --deliverables replaces the contract -----------
out=$("$FENCE" --changed "$T/mixed.txt" --contract "$T/contract.md" \
  --allow scripts/other.sh --allow 'doctrine/*.md' --allow README.md \
  --allow '--out=.claude/x' --allow 'notes/*' --allow 'fenced/*' 2>&1)
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
cp "$T/contract.md" "$B/contract-base.md"
# The branch's own contract, widened to admit everything, is never read.
cat >"$B/contract.md" <<'EOF'
- **Deliverables:** `scripts/other.sh`, `*.*`, `scripts/`.
EOF
printf '%s\n' '"we\"ird.txt"' >"$B/skipped-files.txt"
out=$("$FENCE" --bundle "$B" 2>/dev/null)
assert_exit "a bundle's changed files and contract are fenced" 1 $?
assert_contains "bundle mode names the outside file" "outside	scripts/other.sh" "$out"
assert_contains "a path the builder refused is outside" 'outside	"we\"ird.txt"' "$out"
printf '%s\n' scripts/lib.sh >"$B/changed-files.txt"
out=$("$FENCE" --bundle "$B" 2>/dev/null)
assert_exit "a refused path alone fails the fence" 1 $?
rm "$B/skipped-files.txt"
out=$("$FENCE" --bundle "$B" 2>&1)
assert_exit "a bundle without skipped-files.txt is refused" 2 $?
: >"$B/skipped-files.txt"

# --- printed paths carry no control bytes ----------------------------------------
printf 'docs/a\033[31mb\233m.md\n' >"$T/ctl.txt"
out=$("$FENCE" --changed "$T/ctl.txt" --contract "$T/contract.md" 2>&1)
assert_exit "a control-byte path outside the fence is reported" 1 $?
if LC_ALL=C grep -q "$(printf '[\033\233]')" <<<"$out"; then
  fail "printed paths carry no control bytes"
else
  ok "printed paths carry no control bytes"
fi
printf -- '-a\233b.sh\n' >"$B/skipped-files.txt"
out=$("$FENCE" --bundle "$B" 2>&1)
if LC_ALL=C grep -q "$(printf '[\033\233]')" <<<"$out"; then
  fail "a refused path is printed without its control bytes"
else
  ok "a refused path is printed without its control bytes"
fi
: >"$B/skipped-files.txt"

# --- refused inputs -----------------------------------------------------------
out=$("$FENCE" --changed "$T/mixed.txt" 2>&1)
assert_exit "no deliverables source is a usage error" 2 $?
printf -- '- **Done when:** nothing listed.\n' >"$T/empty-contract.md"
out=$("$FENCE" --changed "$T/mixed.txt" --contract "$T/empty-contract.md" 2>&1)
assert_exit "a contract naming no deliverable path is refused" 2 $?
assert_contains "says why" "no deliverable" "$out"
rm "$B/contract-base.md"
out=$("$FENCE" --bundle "$B" 2>&1)
assert_exit "a bundle without a base contract is refused" 2 $?
out=$("$FENCE" --bundle "$T" 2>&1)
assert_exit "a directory that is not a bundle is refused" 2 $?

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all review-scope-fence tests passed"
