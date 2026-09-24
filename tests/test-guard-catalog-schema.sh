#!/bin/bash
# Schema check over config/guard-catalog.yaml against doctrine/guard-catalog.md
# (REQ-H1.1, REQ-G1.5).
#
# Two tethers, both fail-closed on a zero-row parse:
#   - every catalog entry carries the required fields (id, category, tool,
#     detect; `core` on a guards: entry) and its category is one the doctrine's
#     "Guard categories" section names in backticks, or `breadth`;
#   - the guard classes this spec registered are present and declare both
#     their category and their core-vs-breadth placement.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-guard-catalog-schema.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
# The overrides exist for the self-check at the end of this file, which
# re-runs it over planted fixtures to prove each fail-closed path fails.
CATALOG="${GUARD_CATALOG_SCHEMA_YAML:-$REPO_ROOT/config/guard-catalog.yaml}"
DOCTRINE="${GUARD_CATALOG_SCHEMA_DOC:-$REPO_ROOT/doctrine/guard-catalog.md}"

failures=0
pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

[ -r "$CATALOG" ] || {
  echo "FAIL: catalog missing or unreadable at $CATALOG" >&2
  exit 1
}
[ -r "$DOCTRINE" ] || {
  echo "FAIL: doctrine missing or unreadable at $DOCTRINE" >&2
  exit 1
}

# The category enum is what the doctrine's "Guard categories" section declares:
# one bullet per category, its machine id in backticks right after the bold
# name (`- **Formatter** (\`formatter\`).`), so the enum has exactly one home
# and the yaml is judged against it. A section that yields nothing fails closed.
enum=$(awk '
  /^## Guard categories/ { on = 1; next }
  on && /^## /            { exit }
  on && /^- \*\*[^*]+\*\* \(`[a-z][a-z-]*`\)/ {
    sub(/^- \*\*[^*]+\*\* \(`/, ""); sub(/`\).*$/, ""); print
  }
' "$DOCTRINE" | sort -u)
[ -n "$enum" ] || {
  echo "FAIL: doctrine/guard-catalog.md §Guard categories declares no category id bullet — the enum parsed to zero rows" >&2
  exit 1
}
in_enum() { printf '%s\n' "$enum" | grep -qxF -- "$1"; }
for c in formatter linter type-checker test-runner security commit-hook ci; do
  if in_enum "$c"; then
    pass "doctrine enum names the founding category: $c"
  else
    fail "doctrine enum lost the founding category: $c"
  fi
done

# Same constrained reader shape scripts/builder-guards.sh uses (two-space list
# items, four-space fields): one record per entry, pipe-delimited.
records=$(awk '
  function val(line) {
    sub(/^[^:]*:[ \t]*/, "", line)
    gsub(/^[ \t]+|[ \t]+$/, "", line)
    sub(/^"/, "", line); sub(/"$/, "", line)
    return line
  }
  function flush() {
    if (have) printf "%s|%s|%s|%s|%s|%s\n", id, cat, tool, detect, core, section
    have = 0
  }
  /^guards:[ \t]*$/   { flush(); section = "guards";  next }
  /^breadth:[ \t]*$/  { flush(); section = "breadth"; next }
  /^[A-Za-z]/         { flush(); section = "" }
  section == ""       { next }
  /^[ \t]*#/          { next }
  /^  -[ \t]+id:/     { flush(); id = val($0); cat = tool = detect = core = ""; have = 1; next }
  have && /^    category:/ { cat = val($0); next }
  have && /^    tool:/     { tool = val($0); next }
  have && /^    detect:/   { detect = val($0); next }
  have && /^    core:/     { core = val($0); next }
  END { flush() }
' "$CATALOG")
[ -n "$records" ] || {
  echo "FAIL: config/guard-catalog.yaml parsed to zero entries" >&2
  exit 1
}
# Fail closed per section, not only on the whole: a guards: block whose items
# drift out of the reader's shape would otherwise vanish behind the breadth
# entries and the core catalog would go unchecked.
for section in guards breadth; do
  printf '%s\n' "$records" | awk -F'|' -v s="$section" '$6 == s { found = 1 } END { exit !found }' || {
    echo "FAIL: config/guard-catalog.yaml $section: section parsed to zero entries" >&2
    exit 1
  }
done

n=0
while IFS='|' read -r id cat tool detect core section; do
  [ -n "$id" ] || continue
  n=$((n + 1))
  [ -n "$cat" ] || fail "$id: no category"
  [ -n "$tool" ] || fail "$id: no tool"
  [ -n "$detect" ] || fail "$id: no detect"
  case "$section" in
    guards)
      case "$core" in
        true | false) : ;;
        *) fail "$id: a guards: entry must declare core: true or core: false (got '$core')" ;;
      esac
      ;;
    breadth)
      case "$core" in
        '' | false) : ;;
        *) fail "$id: a breadth: entry cannot be core: $core" ;;
      esac
      [ "$detect" = manual ] || fail "$id: a breadth: entry must be detect: manual (never auto-fires), got '$detect'"
      ;;
  esac
  if [ "$cat" = breadth ] || in_enum "$cat"; then
    :
  else
    fail "$id: category '$cat' is not in the doctrine's Guard categories enum"
  fi
done <<EOF
$records
EOF
[ "$n" -gt 0 ] || fail "zero entries walked"
[ "$failures" -eq 0 ] \
  && pass "every entry carries id, category, tool, detect and a placement, with a category the doctrine names ($n entries)"

# The categorized breadth entries each declare their category and placement
# explicitly, and the amended categories exist (REQ-H1.1).
# want_entry <id> <category> <section> <core>
want_entry() {
  before=$failures
  rec=$(printf '%s\n' "$records" | awk -F'|' -v id="$1" '$1 == id { print; exit }')
  [ -n "$rec" ] || {
    fail "catalog has no entry: $1"
    return
  }
  got_cat=$(printf '%s' "$rec" | cut -d'|' -f2)
  got_core=$(printf '%s' "$rec" | cut -d'|' -f5)
  got_sec=$(printf '%s' "$rec" | cut -d'|' -f6)
  [ "$got_cat" = "$2" ] || fail "$1: category is '$got_cat', expected '$2'"
  [ "$got_sec" = "$3" ] || fail "$1: placed under '$got_sec', expected '$3'"
  [ "$got_core" = "$4" ] || fail "$1: core is '$got_core', expected an explicit '$4'"
  [ "$failures" -eq "$before" ] && pass "$1 is catalogued as $2, $3 placement, core: $4"
}
want_entry pinned-action-freshness security breadth false
want_entry test-time-budget budget breadth false
want_entry cdpath-house-pattern house-pattern breadth false
for c in budget house-pattern; do
  if in_enum "$c"; then
    pass "doctrine enum names the amended category: $c"
  else
    fail "doctrine enum lacks the amended category: $c"
  fi
done

[ "$failures" -eq 0 ] || {
  echo "$failures guard-catalog-schema check(s) failed" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Self-check: every fail-closed path above must actually fail. A guard whose
# failure branches are never exercised is a green signal that measures
# nothing, so this file re-runs itself over planted fixtures (skipped when it
# is already the fixture run).
# ---------------------------------------------------------------------------
if [ -z "${GUARD_CATALOG_SCHEMA_YAML:-}${GUARD_CATALOG_SCHEMA_DOC:-}" ]; then
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-guard-catalog-schema.XXXXXX") || {
    echo "FAIL: mktemp -d failed" >&2
    exit 1
  }
  trap 'rm -rf "$tmp"' EXIT

  # mkcatalog <file> <category>
  #   A minimal catalog in the reader's shape: one guards: entry carrying the
  #   given category (an empty argument omits the field) plus the breadth
  #   entries the assertions above look for.
  mkcatalog() {
    {
      printf 'guards:\n  - id: format-shell\n'
      [ -n "$2" ] && printf '    category: %s\n' "$2"
      printf '    tool: shfmt\n    detect: "*.sh"\n    core: true\n\nbreadth:\n'
      printf '%s\n' "pinned-action-freshness security" "test-time-budget budget" "cdpath-house-pattern house-pattern" \
        | while read -r bid bcat; do
          printf '  - id: %s\n    category: %s\n    tool: advisory\n    detect: manual\n    core: false\n' "$bid" "$bcat"
        done
    } >"$1"
  }

  # expect_fail <label> <message-fragment> <yaml-override> <doc-override>
  expect_fail() {
    out=$(GUARD_CATALOG_SCHEMA_YAML="$3" GUARD_CATALOG_SCHEMA_DOC="$4" /bin/bash "$0" 2>&1)
    rc=$?
    if [ "$rc" -ne 1 ]; then
      echo "FAIL: self-check $1: expected exit 1, got $rc: $out" >&2
      exit 1
    fi
    printf '%s\n' "$out" | grep -qF -- "$2" || {
      echo "FAIL: self-check $1: exit 1 for the wrong reason (no '$2'): $out" >&2
      exit 1
    }
    pass "self-check $1 fails closed"
  }

  mkcatalog "$tmp/good.yaml" formatter
  out=$(GUARD_CATALOG_SCHEMA_YAML="$tmp/good.yaml" GUARD_CATALOG_SCHEMA_DOC="$DOCTRINE" /bin/bash "$0" 2>&1) || {
    echo "FAIL: self-check positive control: the minimal well-formed catalog should pass: $out" >&2
    exit 1
  }
  pass "self-check positive control: a minimal well-formed catalog passes"

  printf '## Guard categories\n\nProse without an id bullet.\n\n## Entry format\n' >"$tmp/no-enum.md"
  expect_fail "doctrine enum parses to zero rows" "enum parsed to zero rows" "$tmp/good.yaml" "$tmp/no-enum.md"

  printf 'guards:\n' >"$tmp/empty.yaml"
  expect_fail "catalog parses to zero entries" "parsed to zero entries" "$tmp/empty.yaml" "$DOCTRINE"

  {
    printf 'guards:\n    - id: format-shell\n      category: formatter\n      tool: shfmt\n      detect: "*.sh"\n      core: true\n\n'
    sed -n '/^breadth:/,$p' "$tmp/good.yaml"
  } >"$tmp/reflowed.yaml"
  expect_fail "guards: section parses to zero entries" "guards: section parsed to zero entries" "$tmp/reflowed.yaml" "$DOCTRINE"

  mkcatalog "$tmp/bogus.yaml" bogus
  expect_fail "unknown category" "is not in the doctrine's Guard categories enum" "$tmp/bogus.yaml" "$DOCTRINE"

  mkcatalog "$tmp/no-category.yaml" ""
  expect_fail "missing category field" "no category" "$tmp/no-category.yaml" "$DOCTRINE"
fi

echo "ALL PASS: guard-catalog-schema"
exit 0
