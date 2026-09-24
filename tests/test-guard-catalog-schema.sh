#!/bin/bash
# Schema check over config/guard-catalog.yaml against doctrine/guard-catalog.md
# (guard-coverage REQ-H1.1, D-13; bootstrap REQ-G1.5).
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
CATALOG="$REPO_ROOT/config/guard-catalog.yaml"
DOCTRINE="$REPO_ROOT/doctrine/guard-catalog.md"

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
pass "every entry carries id, category, tool, detect and a placement, with a category the doctrine names ($n entries)"

# The three guard classes guard-coverage registered (D-13). Each declares its
# category and its placement explicitly, and the two new categories exist.
want_entry() {
  # want_entry <id> <category> <section> <core>
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
  pass "$1 is catalogued as $2, $3 placement, core: $4"
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

if [ "$failures" -eq 0 ]; then
  echo "ALL PASS: guard-catalog-schema"
  exit 0
fi
echo "$failures guard-catalog-schema check(s) failed" >&2
exit 1
