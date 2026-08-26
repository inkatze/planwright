#!/bin/bash
# Tests for scripts/check-doctrine-index.sh — the doctrine-index bijection
# tether (guard-coverage Task 9; REQ-F1.1, REQ-H1.3, D-10).
#
# The guard asserts that doctrine/*.md (minus README.md) and the index rows in
# doctrine/README.md are in bijection: every doc has a row AND every row maps
# to an existing doc, so a stale row left behind by a deleted or renamed doc
# fails just as loudly as a missing one. The fail-closed arm (REQ-H1.3) covers
# a missing README, an index table that cannot be parsed, and an empty
# doctrine-doc set — each must exit non-zero rather than pass vacuously.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-doctrine-index.sh"

failures=0
assert() {
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}

assert_contains() {
  case "$2" in
    *"$3"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (output did not mention '$3'): $2" >&2
      failures=$((failures + 1))
      ;;
  esac
}

if [ ! -f "$CHECKER" ]; then
  echo "FAIL: checker script missing at $CHECKER" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# Build a fixture doctrine directory: $1 = dir, remaining args = doc basenames.
# The README indexes exactly the docs named, in the repo's row shape.
make_fixture() {
  fx_dir="$1"
  shift
  mkdir -p "$fx_dir"
  {
    echo "# Fixture Doctrine"
    echo
    echo "| Doc | Covers | Primary citations |"
    echo "| --- | --- | --- |"
    for fx_doc in "$@"; do
      echo "| [$fx_doc.md]($fx_doc.md) | Something | REQ-X1.1 |"
      : >"$fx_dir/$fx_doc.md"
    done
  } >"$fx_dir/README.md"
}

# ---------------------------------------------------------------------------
# 1. The real tree passes: every shipped doctrine doc is indexed and every
#    index row maps to a shipped doc.
# ---------------------------------------------------------------------------
/bin/bash "$CHECKER" >/dev/null
assert "the repo's doctrine index is a bijection" 0 $?

# ---------------------------------------------------------------------------
# 2. A fixture whose index matches its doc set passes.
# ---------------------------------------------------------------------------
make_fixture "$tmp/good" alpha beta
/bin/bash "$CHECKER" "$tmp/good" >/dev/null
assert "matching fixture index passes" 0 $?

# ---------------------------------------------------------------------------
# 3. Direction one: a doctrine doc with no index row fails and is named.
# ---------------------------------------------------------------------------
make_fixture "$tmp/unindexed" alpha beta
: >"$tmp/unindexed/gamma.md"
out="$(/bin/bash "$CHECKER" "$tmp/unindexed" 2>&1)"
assert "an unindexed doctrine doc fails" 1 $?
assert_contains "the unindexed failure names the doc" "$out" "gamma.md"

# ---------------------------------------------------------------------------
# 4. Direction two: a stale index row for a removed doc fails and is named.
#    This is the direction a one-way "every doc has a row" check would miss.
# ---------------------------------------------------------------------------
make_fixture "$tmp/stale" alpha beta
rm "$tmp/stale/beta.md"
out="$(/bin/bash "$CHECKER" "$tmp/stale" 2>&1)"
assert "a stale index row for a removed doc fails" 1 $?
assert_contains "the stale-row failure names the row target" "$out" "beta.md"

# ---------------------------------------------------------------------------
# 4b. A renamed doc fails on both directions at once: the old row is stale and
#     the new file is unindexed. Both must be reported, not just the first.
# ---------------------------------------------------------------------------
make_fixture "$tmp/renamed" alpha beta
mv "$tmp/renamed/beta.md" "$tmp/renamed/beta-renamed.md"
out="$(/bin/bash "$CHECKER" "$tmp/renamed" 2>&1)"
assert "a renamed doc fails" 1 $?
assert_contains "the rename reports the stale row" "$out" "beta.md"
assert_contains "the rename reports the unindexed doc" "$out" "beta-renamed.md"

# ---------------------------------------------------------------------------
# 5. A duplicate index row for one doc breaks the bijection.
# ---------------------------------------------------------------------------
make_fixture "$tmp/dupe" alpha beta
echo "| [alpha.md](alpha.md) | Duplicated | REQ-X1.1 |" >>"$tmp/dupe/README.md"
out="$(/bin/bash "$CHECKER" "$tmp/dupe" 2>&1)"
assert "a duplicate index row fails" 1 $?
assert_contains "the duplicate failure names the doc" "$out" "alpha.md"

# ---------------------------------------------------------------------------
# 6. Fail-closed: a missing README is an error, never a vacuous pass
#    (REQ-H1.3).
# ---------------------------------------------------------------------------
mkdir -p "$tmp/no-readme"
: >"$tmp/no-readme/alpha.md"
out="$(/bin/bash "$CHECKER" "$tmp/no-readme" 2>&1)"
assert "a missing README fails closed" 2 $?
assert_contains "the missing-README failure is the checker's diagnostic" "$out" "README.md"

# ---------------------------------------------------------------------------
# 7. Fail-closed: a README whose index table cannot be parsed (no recognizable
#    header row) is an error. A silently-zero row set must not read as clean.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/unparseable"
: >"$tmp/unparseable/alpha.md"
cat >"$tmp/unparseable/README.md" <<'EOF'
# Fixture Doctrine

No index table here at all.
EOF
out="$(/bin/bash "$CHECKER" "$tmp/unparseable" 2>&1)"
assert "an unparseable index table fails closed" 2 $?
assert_contains "the unparseable failure is the checker's diagnostic" "$out" "index table"

# ---------------------------------------------------------------------------
# 7b. Fail-closed: an index table header that parses but yields zero rows is
#     also an error (the table shape survived, the content did not).
# ---------------------------------------------------------------------------
mkdir -p "$tmp/zero-rows"
: >"$tmp/zero-rows/alpha.md"
cat >"$tmp/zero-rows/README.md" <<'EOF'
# Fixture Doctrine

| Doc | Covers | Primary citations |
| --- | --- | --- |

Prose after an empty table.
EOF
out="$(/bin/bash "$CHECKER" "$tmp/zero-rows" 2>&1)"
assert "a zero-row index table fails closed" 2 $?
assert_contains "the zero-row failure is the checker's diagnostic" "$out" "index"

# ---------------------------------------------------------------------------
# 8. Fail-closed: an empty doctrine-doc set is an error. A doctrine directory
#    that globs to nothing means a broken enumeration, not a clean tree.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/no-docs"
cat >"$tmp/no-docs/README.md" <<'EOF'
# Fixture Doctrine

| Doc | Covers | Primary citations |
| --- | --- | --- |
| [alpha.md](alpha.md) | Something | REQ-X1.1 |
EOF
out="$(/bin/bash "$CHECKER" "$tmp/no-docs" 2>&1)"
assert "an empty doctrine-doc set fails closed" 2 $?
assert_contains "the empty-doc-set failure is the checker's diagnostic" "$out" "no doctrine docs"

# ---------------------------------------------------------------------------
# 9. Fail-closed: a missing doctrine directory is a usage error.
# ---------------------------------------------------------------------------
/bin/bash "$CHECKER" "$tmp/no-such-dir" >/dev/null 2>&1
assert "a missing doctrine directory is an error" 2 $?

# ---------------------------------------------------------------------------
# 10. Fail-closed: an index row whose target is not a bare doctrine-doc
#     basename (a path, a fragment, a non-.md target) is a parse error rather
#     than a silently-dropped row.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/bad-target"
: >"$tmp/bad-target/alpha.md"
cat >"$tmp/bad-target/README.md" <<'EOF'
# Fixture Doctrine

| Doc | Covers | Primary citations |
| --- | --- | --- |
| [alpha.md](alpha.md) | Something | REQ-X1.1 |
| [elsewhere](../docs/elsewhere.md) | Something | REQ-X1.2 |
EOF
out="$(/bin/bash "$CHECKER" "$tmp/bad-target" 2>&1)"
assert "a non-basename index row target fails closed" 2 $?
assert_contains "the bad-target failure names the target" "$out" "../docs/elsewhere.md"

# ---------------------------------------------------------------------------
# 10b. Fail-closed: a doctrine file whose basename is outside the identifier
#      grammar (REQ-A1.8) is an error naming the file. The doc set travels as
#      a word-split list, so an unvalidated name with a space would silently
#      become two bogus entries and produce a failure nobody can act on.
# ---------------------------------------------------------------------------
make_fixture "$tmp/bad-basename" alpha
: >"$tmp/bad-basename/my doc.md"
out="$(/bin/bash "$CHECKER" "$tmp/bad-basename" 2>&1)"
assert "a doctrine filename outside the identifier grammar fails closed" 2 $?
assert_contains "the bad-basename failure names the file" "$out" "my doc.md"

# ---------------------------------------------------------------------------
# 11. Done-when, on the real corpus: removing a single README row from a copy
#     of the shipped doctrine directory turns the check red. This is the
#     property that makes `mise run check` fail on a local row removal.
# ---------------------------------------------------------------------------
cp -R "$REPO_ROOT/doctrine" "$tmp/real-copy"
# shellcheck disable=SC2016 # the backtick-free pattern is literal markdown
victim="$(sed -n 's/^|[[:space:]]*\[\([a-z0-9-]*\.md\)\](.*/\1/p' "$tmp/real-copy/README.md" | head -1)"
if [ -z "$victim" ]; then
  echo "FAIL: could not pick a real index row to remove" >&2
  failures=$((failures + 1))
else
  grep -vF "| [$victim](" "$tmp/real-copy/README.md" >"$tmp/real-copy/README.new" \
    && mv "$tmp/real-copy/README.new" "$tmp/real-copy/README.md"
  out="$(/bin/bash "$CHECKER" "$tmp/real-copy" 2>&1)"
  assert "removing a real README row turns the check red" 1 $?
  assert_contains "the red run names the de-indexed doc" "$out" "$victim"
fi

# ---------------------------------------------------------------------------
# 12. The guard is wired into the `check` aggregate, so the red run above is
#     reachable from `mise run check` rather than only by direct invocation.
# ---------------------------------------------------------------------------
if grep -q '^\[tasks\."check:doctrine-index"\]' "$REPO_ROOT/mise.toml"; then
  echo "ok: check:doctrine-index is defined as a mise task"
else
  echo "FAIL: mise.toml defines no check:doctrine-index task" >&2
  failures=$((failures + 1))
fi
if grep -q '^  "check:doctrine-index",' "$REPO_ROOT/mise.toml"; then
  echo "ok: check:doctrine-index is wired into the check aggregate"
else
  echo "FAIL: check:doctrine-index is not in the check aggregate's depends list" >&2
  failures=$((failures + 1))
fi

# ---------------------------------------------------------------------------
# 13. A hostile CDPATH must not corrupt the script's repo-root derivation.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/decoy/scripts" "$tmp/work"
cp -R "$REPO_ROOT/scripts" "$tmp/work/"
cp -R "$REPO_ROOT/doctrine" "$tmp/work/"
(cd "$tmp/work" && CDPATH="$tmp/decoy" /bin/bash scripts/check-doctrine-index.sh >/dev/null 2>&1)
assert "CDPATH does not corrupt root derivation" 0 $?

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-doctrine-index tests passed"
