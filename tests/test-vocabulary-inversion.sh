#!/bin/bash
# Pin-check for the Tower / Orchestrator vocabulary inversion at its
# definitional sites (tower-front-door Task 2; REQ-H1.1, REQ-H1.2; D-2).
#
# The spec-format glossary is the vocabulary's home: **Tower** names the
# standing conversational front-door session, **Orchestrator** is minted for
# the dispatching /orchestrate session and carries a one-line distinction from
# Operator (the human), and a transitional note covers both older prose that
# still says "tower" for the orchestrator and the tower-named scripts and
# config that serve either session until renames land. The other three
# definitional sites (work-placement's consumer naming, the fleet doc's
# opening, the /orchestrate skill description) must use the new vocabulary;
# the pervasive prose sweep is deferred behind its gate, so nothing here
# asserts on prose beyond those sites. The meta-spec's own versioning section
# records the supersession as a dated no-version-bump entry.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC_FORMAT="$REPO_ROOT/doctrine/spec-format.md"
WORK_PLACEMENT="$REPO_ROOT/doctrine/work-placement.md"
FLEET_DOC="$REPO_ROOT/docs/fleet.md"
ORCHESTRATE_SKILL="$REPO_ROOT/skills/orchestrate/SKILL.md"

TOWER_CMD="\`/tower\`"
ORCHESTRATE_CMD="\`/orchestrate\`"

failures=0
assert_contains() {
  # assert_contains <description> <needle> <haystack>
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (expected to find '$2')" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_lacks() {
  # assert_lacks <description> <needle> <haystack>
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (did not expect to find '$2')" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

for doc in "$SPEC_FORMAT" "$WORK_PLACEMENT" "$FLEET_DOC" "$ORCHESTRATE_SKILL"; do
  if [ ! -f "$doc" ]; then
    echo "FAIL: definitional site missing at $doc" >&2
    exit 1
  fi
done

# section <file> <heading-line>: the body of one `## ` section, up to the next.
section() {
  awk -v h="$2" '
    $0 == h { on = 1; next }
    on && /^## / { exit }
    on { print }
  ' "$1"
}

# entry <glossary-text> <term>: one glossary bullet (`- **<term>** — ...`)
# through the line before the next bullet.
entry() {
  printf '%s\n' "$1" | awk -v t="- **$2** —" '
    index($0, t) == 1 { on = 1; print; next }
    on && /^- / { exit }
    on { print }
  '
}

glossary="$(section "$SPEC_FORMAT" "## Glossary")"
versioning="$(section "$SPEC_FORMAT" "## Versioning of this meta-spec")"

# --- Tower: superseded to the front-door session ---------------------------
tower="$(entry "$glossary" "Tower")"
assert_contains "glossary has a Tower entry" "- **Tower** —" "$tower"
assert_contains "Tower names the /tower session" "$TOWER_CMD" "$tower"
assert_contains "Tower is the conversational front-door session" "front-door" "$tower"
assert_contains "Tower entry says conversational" "conversational" "$tower"
assert_lacks "Tower no longer names the dispatching session" \
  '**Tower** — the dispatching' "$tower"

# --- Orchestrator: minted, with the Operator distinction --------------------
orch="$(entry "$glossary" "Orchestrator")"
assert_contains "glossary has an Orchestrator entry" "- **Orchestrator** —" "$orch"
assert_contains "Orchestrator names the /orchestrate session" "$ORCHESTRATE_CMD" "$orch"
assert_contains "Orchestrator entry says dispatching" "dispatching" "$orch"
assert_contains "Orchestrator entry distinguishes Operator" "Operator" "$orch"
assert_contains "the Operator distinction names the human" "human" "$orch"

# --- Transitional note: older prose AND tower-named scripts/config ----------
note="$(printf '%s\n' "$glossary" | awk '
  /^- \*\*Transitional note/ { on = 1; print; next }
  on && /^- / { exit }
  on { print }
')"
assert_contains "glossary carries a transitional note" "Transitional note" "$note"
assert_contains "transitional note covers older prose" "older prose" "$note"
assert_contains "transitional note covers tower-named scripts" "tower-named scripts" "$note"
assert_contains "transitional note covers tower-named config" "config" "$note"
assert_contains "transitional note ends at the renames" "renames land" "$note"
assert_contains "transitional note cites its decision" "D-2" "$note"

# --- Versioning: a dated entry, no version bump -----------------------------
assert_contains "meta-spec version line is unchanged" \
  "This document is format-version 2 and defines versions 1 and 2." "$versioning"
supersession_entry="$(printf '%s\n' "$versioning" | awk '
  /^- 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] — / { on = 0 }
  /^- 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] — .*(Glossary|glossary).*(supersession|superseded)/ { on = 1 }
  on { print }
')"
assert_contains "versioning records the glossary supersession" "Orchestrator" "$supersession_entry"
assert_contains "the supersession entry declares no version bump" \
  "No version bump" "$supersession_entry"
assert_contains "the supersession entry cites its decision" "D-2" "$supersession_entry"

# --- work-placement: consumer naming --------------------------------------
wp_head="$(awk '/^## / { exit } { print }' "$WORK_PLACEMENT")"
assert_contains "work-placement consumers name the /tower session" "$TOWER_CMD" "$wp_head"
assert_contains "work-placement consumers name the orchestrator" "orchestrator" "$wp_head"

# --- fleet doc: opening vocabulary ----------------------------------------
fleet_open="$(awk '/^## The two seams/ { exit } { print }' "$FLEET_DOC")"
assert_contains "fleet opening names the orchestrator" "orchestrator" "$fleet_open"
assert_contains "fleet opening names the /tower session" "$TOWER_CMD" "$fleet_open"
assert_lacks "fleet opening no longer says meta-tower" "meta-tower" "$fleet_open"

# --- /orchestrate description: the control-tower line re-termed -----------
desc="$(awk '
  NR == 1 && /^---$/ { fm = 1; next }
  fm && /^---$/ { exit }
  fm { print }
' "$ORCHESTRATE_SKILL")"
assert_lacks "/orchestrate description drops control tower" "control tower" "$desc"
assert_contains "/orchestrate description says orchestrator" "orchestrator" "$desc"

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all vocabulary-inversion pin checks passed"
