#!/bin/bash
# Pin-checks for the docs inversion (tower-front-door Task 12; REQ-H1.3,
# REQ-H1.4; D-2, D-3).
#
# The README leads with /tower; the newcomer path (the README's lead, Install
# and Quickstart, and getting-started's intro and first-ask section) names no
# pipeline machinery; the demoted commands live in the README only under its
# under-the-hood section, nowhere in getting-started, and all of them in the
# architecture doc; the front-facing commands stay in the README's Commands
# table; no skill is renamed; the controls are restated on both flight rules,
# citing human-gates; and every user doc that names the flight rules glosses
# the analogy at first use. The gloss and machinery screens are run against
# known-bad fixtures first, so a screen that matches nothing cannot pass.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
README="$REPO_ROOT/README.md"
GUIDE="$REPO_ROOT/docs/getting-started.md"
ARCH="$REPO_ROOT/docs/architecture.md"

for doc in "$README" "$GUIDE" "$ARCH"; do
  if [ ! -f "$doc" ]; then
    echo "FAIL: doc surface missing at $doc" >&2
    exit 1
  fi
done

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_contains() {
  case "$3" in
    *"$2"*) ok "$1" ;;
    *) fail "$1 (expected to find '$2')" ;;
  esac
}

# flatten: one space-separated line, so a needle a rewrap splits still matches.
flatten() { tr '\n' ' ' | tr -s ' '; }

# lead <file>: from the title to the first `## ` heading, badge lines dropped.
lead() {
  awk 'NR > 1 && /^## / { exit } /^\[!\[/ { next } { print }' "$1"
}

# section <file> <heading-prefix>: one section whose heading line starts with
# the prefix, up to the next heading of the same or a higher level.
section() {
  awk -v h="$2" '
    !on && index($0, h) == 1 { on = 1; lvl = index($0, " "); next }
    on && /^#+ / && index($0, " ") <= lvl { exit }
    on { print }
  ' "$1"
}

TOWER_CMD="\`/tower\`"
DEMOTED="/(orchestrate|execute-task|resume|offload)([^[:alnum:]_-]|$)"
MACHINERY="$DEMOTED|scripts/|worktree|branch|config/|\\.ya?ml|\\.json|\`[a-z]+_[a-z_]+\`|(^|[ \`])--[a-z]"

# machinery <text>: the lines of a newcomer-path block naming pipeline
# machinery (the demoted commands, scripts, config knobs and files, branch and
# worktree plumbing, command-line flags).
machinery() { printf '%s\n' "$1" | grep -n -i -E "$MACHINERY"; }

# gloss_missing <file>: prints the file when it names the flight rules and the
# paragraph of their first mention lacks the analogy's gloss.
gloss_missing() {
  awk '
    BEGIN { RS = "" }
    {
      p = tolower($0)
      gsub(/[ \t\n]+/, " ", p)
      if (p ~ /visual flight|instrument flight|flight rules/) {
        if (index(p, "conditions are clear") == 0 || index(p, "trust the gauges") == 0) bad = 1
        found = 1
        exit
      }
    }
    END { if (bad) print FILENAME; if (!found) exit 3 }
  ' "$1"
}

# Screens refuse known-bad input before they are trusted.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf '# X\n\nRoute work by visual flight or instrument flight.\n' >"$tmp/bad.md"
printf '# X\n\nThe flight rules are visual flight and instrument flight: visual rules\nwhen conditions are clear, instrument rules when you trust the gauges.\n' >"$tmp/good.md"
if [ -n "$(gloss_missing "$tmp/bad.md")" ]; then ok "the gloss screen refuses an unglossed first use"; else fail "the gloss screen passed an unglossed first use"; fi
if [ -z "$(gloss_missing "$tmp/good.md")" ]; then ok "the gloss screen passes a glossed first use"; else fail "the gloss screen refused a glossed first use"; fi
bad_lines=$(machinery "\`/orchestrate\` runs it
see scripts/x.sh
set \`max_parallel_units\`
in its own worktree
run with --fleet
then /execute-task builds it" | grep -c .)
if [ "$bad_lines" -eq 6 ]; then ok "the machinery screen fires on known-bad lines"; else fail "the machinery screen fired on $bad_lines of 6 known-bad lines"; fi

# README lead (REQ-H1.3).
readme_lead=$(lead "$README")
assert_contains "the README's lead names /tower" "$TOWER_CMD" "$readme_lead"
first_cmd=$(grep -o -E '`/[a-z][a-z-]*' "$README" | head -n 1)
if [ "$first_cmd" = '`/tower' ]; then ok "/tower is the first command the README names"; else fail "the README names $first_cmd before /tower"; fi
assert_contains "the README's Quickstart starts with /tower" "$TOWER_CMD" "$(section "$README" "## Quickstart")"
assert_contains "getting-started's intro names /tower" "$TOWER_CMD" "$(lead "$GUIDE")"

# The newcomer path names no pipeline machinery (REQ-A1.1, REQ-H1.3).
newcomer_guide=$(section "$GUIDE" "## 3. Start with the tower")
if [ -z "$newcomer_guide" ]; then fail "getting-started has no 'Start with the tower' section"; fi
for part in "README lead:$readme_lead" \
  "README Install:$(section "$README" "## Install")" \
  "README Quickstart:$(section "$README" "## Quickstart")" \
  "getting-started intro:$(lead "$GUIDE")" \
  "getting-started first ask:$newcomer_guide"; do
  name=${part%%:*}
  hits=$(machinery "${part#*:}")
  if [ -z "$hits" ]; then ok "$name names no pipeline machinery"; else fail "$name names pipeline machinery:
$hits"; fi
done

# Demotion placement (REQ-H1.3): the README names a demoted command only under
# its under-the-hood section; getting-started names none; the architecture doc
# names every one.
outside=$(awk '
  /^## / { hood = (index($0, "## Under the hood") == 1) }
  !hood { print }
' "$README" | grep -n -E "$DEMOTED")
if [ -z "$outside" ]; then ok "the README names demoted commands only under the hood"; else fail "the README names a demoted command outside its under-the-hood section:
$outside"; fi
hood=$(section "$README" "## Under the hood")
in_guide=$(grep -n -E "$DEMOTED" "$GUIDE")
if [ -z "$in_guide" ]; then ok "getting-started names no demoted command"; else fail "getting-started names a demoted command:
$in_guide"; fi
assert_contains "the README's under-the-hood section links the architecture doc" "(docs/architecture.md)" "$hood"
for cmd in orchestrate execute-task resume offload; do
  assert_contains "the README's under-the-hood section names /$cmd" "\`/$cmd" "$hood"
  assert_contains "the architecture doc names /$cmd" "\`/$cmd" "$(cat "$ARCH")"
done

# The front-facing set stays in the README's Commands table, the demoted set
# out of it; /self-review and /polish stay in place.
commands=$(section "$README" "## Commands")
for cmd in tower spec-draft spec-kickoff spec-walkthrough drain builder self-review polish; do
  assert_contains "the Commands table names /$cmd" "| \`/$cmd\` |" "$commands"
done
if printf '%s\n' "$commands" | grep -q -E "$DEMOTED"; then fail "the Commands table names a demoted command"; else ok "the Commands table names no demoted command"; fi

# No skill is renamed (D-2).
for s in tower orchestrate execute-task resume offload spec-draft spec-kickoff \
  spec-walkthrough drain builder self-review polish inception; do
  f="$REPO_ROOT/skills/$s/SKILL.md"
  if [ -f "$f" ] && grep -q -x "name: $s" "$f"; then ok "skill $s keeps its name"; else fail "skill $s is missing or renamed"; fi
done

# The controls restated on both flight rules, citing the doc that owns them.
for part in "README:$(section "$README" "### The controls you keep")" \
  "getting-started:$(section "$GUIDE" "## 4. The controls you keep")" \
  "architecture:$(section "$ARCH" "## The controls you keep")"; do
  name=${part%%:*}
  text=$(printf '%s\n' "${part#*:}" | flatten)
  if [ -z "$text" ]; then
    fail "$name has no controls section"
    continue
  fi
  for needle in "both flight rules" "visual flight" "instrument flight" "draft→ready flip" "merge" "sign-off" "human-gates.md"; do
    assert_contains "$name's controls restatement names '$needle'" "$needle" "$text"
  done
done

# Every user doc naming the flight rules glosses them at first use (REQ-H1.4).
glossed=0
for f in "$README" "$REPO_ROOT"/docs/*.md; do
  missing=$(gloss_missing "$f")
  rc=$?
  [ "$rc" -eq 3 ] && continue
  glossed=$((glossed + 1))
  if [ -z "$missing" ]; then ok "${f#"$REPO_ROOT"/} glosses the flight rules at first use"; else fail "${f#"$REPO_ROOT"/} names the flight rules without the gloss at first use"; fi
done
if [ "$glossed" -ge 3 ]; then ok "the gloss check ran over $glossed doc surfaces"; else fail "the gloss check ran over only $glossed doc surfaces"; fi

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all docs-inversion pin checks passed"
