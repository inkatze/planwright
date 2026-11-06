#!/bin/bash
# Structural guard over the /mission-control skill (mission-control D-1,
# D-2, D-14, D-18, D-19, D-21, D-23; REQ-A1.1 to REQ-A1.7, REQ-F1.6, REQ-F1.12,
# REQ-F1.13, REQ-G1.3, REQ-G1.4, REQ-H1.4, REQ-I1.1 to REQ-I1.6).
#
# The skill is procedure the agent reads, so its [design-level] halves are a
# structural guard over skills/mission-control/SKILL.md; the turn behaviour
# is the behavioral-eval harness's, on demand. The mechanics it names are
# tested in their scripts' suites (tests/test-mc-config.sh for the entry,
# the knobs and the first run's writes).
#
# Phrase assertions run over the body with newlines folded and space runs
# squeezed; each check that could pass with its property absent is probed
# at the end against a violating string.
#
# Runs standalone: ./tests/test-mission-control-skill.sh
set -u
LC_ALL=C
export LC_ALL
set -f
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
skill="$REPO_ROOT/skills/mission-control/SKILL.md"
tower="$REPO_ROOT/skills/tower/SKILL.md"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
ok() { printf 'ok: %s\n' "$1"; }

[ -f "$skill" ] || {
  fail "skills/mission-control/SKILL.md missing"
  exit 1
}

# body: the skill after its frontmatter, newlines folded, spaces squeezed.
body=$(awk 'f >= 2 { print } /^---$/ { f++ }' "$skill" | tr '\n' ' ' | tr -s ' ')
front=$(awk '/^---$/ { f++; next } f == 1 { print }' "$skill" | tr '\n' ' ' | tr -s ' ')

has() { # has <text> <needle>
  case $1 in *"$2"*) return 0 ;; esac
  return 1
}
need() { # need <label> <needle>
  if has "$body" "$2"; then ok "$1"; else fail "$1: the body lacks '$2'"; fi
}

# The frontmatter names the skill and reads as a selector.
if has "$front" "name: mission-control"; then ok "the skill is named mission-control"; else fail "the skill is not named mission-control"; fi
for n in "never edits a repository" "never merges" "never signs off a spec" "without their yes"; do
  if has "$front" "$n"; then ok "the description states the boundary: $n"; else fail "the description lacks the boundary '$n'"; fi
done
if has "$front" 'argument-hint: "[<program>]"'; then ok "REQ-A1.7: the program is the one optional argument"; else fail "REQ-A1.7: the argument hint is not the program"; fi

# Doctrine resolves at run start: the manifest's every doc resolves, and
# each point-of-use doc is named in the body.
manifest=$(grep -E '^Doctrine: (run-start|point-of-use) [a-z0-9-]+' "$skill")
run_start=$(printf '%s\n' "$manifest" | awk '$2 == "run-start" { print $3 }')
for d in interaction-style tower-comms human-gates; do
  if printf '%s\n' "$run_start" | grep -qx "$d"; then ok "run-start loads $d"; else fail "run-start does not load $d"; fi
done
while read -r _ phase doc _; do
  [ -n "$doc" ] || continue
  if [ -f "$REPO_ROOT/doctrine/$doc.md" ]; then ok "manifest doc $doc resolves"; else fail "manifest doc $doc does not resolve"; fi
  if [ "$phase" = point-of-use ]; then
    stripped=$(printf '%s\n' "$body" | sed 's/Doctrine: [a-z-]* [a-z0-9-]*//g')
    if has "$stripped" "$doc"; then ok "point-of-use $doc is named in the body"; else fail "point-of-use $doc is never named in the body"; fi
  fi
done <<EOF
$manifest
EOF
need "the run-start halt is stated" "A run-start doc that does not resolve halts the session"

# Plugin scripts by literal path, never variable-rooted.
need "the literal-path pointer is present" "resolved literal absolute path"
# shellcheck disable=SC2016 # the patterns name a literal $VAR, never expanded
if grep -nE '\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/scripts/' "$skill" | grep -vF 'never `$VAR/scripts/<name>.sh`' >/dev/null; then
  fail "a variable-rooted scripts/ invocation remains"
else
  ok "no variable-rooted scripts/ invocation"
fi

# Every script the skill names exists.
named=$(grep -oE 'scripts/[a-z0-9-]+\.sh' "$skill" | sort -u)
[ -n "$named" ] || fail "the skill names no script"
while IFS= read -r s; do
  [ -n "$s" ] || continue
  if [ -f "$REPO_ROOT/$s" ]; then ok "named script $s exists"; else fail "the skill names $s, which does not exist"; fi
done <<EOF
$named
EOF

# The contract by reference to the tower, the lifted limits stated (D-2).
need "D-2: the tower's contract is taken by reference" "skills/tower/SKILL.md"
for n in "Supervision." "Watchers and the failsafe tick." "A program spanning repositories" "The relayed kickoff" "The ready flip inside the configured policy"; do
  need "D-2: lifted limit stated: $n" "$n"
done
if grep -q '/mission-control' "$tower"; then ok "the tower carries the one-line pointer"; else fail "skills/tower/SKILL.md has no pointer to /mission-control"; fi

# Entry, bring-up and the first run.
need "REQ-A1.7: the entry decision is the script's" "scripts/mc-config.sh\`'s \`entry"
for n in "resume" "ask" "first-run"; do need "REQ-A1.7: the entry outcome $n is handled" "\`$n\`"; done
need "REQ-A1.1: the operator's ask is the resume" "scripts/mc-handover.sh\`'s \`resume"
need "REQ-A1.1: any other launch over a live holder is refused" "neither the operator's ask nor a live handover"
need "REQ-A1.2: bring-up from durable evidence only" "Never read a stored live-state file as truth"
need "REQ-A1.7: the first turn says what changed" "what changed since the operator last looked"
need "bring-up audits the setup it inherits" "scripts/mc-config.sh\`'s \`doctor"
need "planwright's defaults win over a predecessor's habits" "planwright's defaults win over the predecessor's habits"
need "REQ-F1.12: one objective at a time" "one objective at a time"
need "REQ-F1.13: the guidance knob sets the depth" "scripts/mc-config.sh\`'s \`mode guidance"
need "REQ-F1.13: a chosen level is remembered" "knob mission_control_guidance"
need "REQ-F1.12: the run ends with the program block written" "scripts/mc-config.sh\`'s \`add"
need "REQ-F1.12: and the knowledge-base skeleton" "scripts/mc-kb.sh\`'s \`init"
need "D-18: the state-source objective" "Where the program's state lives"
need "D-14: no duty enables itself through an omitted list" "always with \`--duties\`"
need "the runner starts detached, never in a turn's foreground" "under \`setsid\`"
need "REQ-I1.2: the readiness check runs before a flip" "scripts/mc-readiness.sh\`'s \`check"
need "REQ-D1.8: a PR is reported done only once the readiness check passes" "\`check\` passes on its head; until then report"
need "D-18: guidance never pre-selects" "pre-selects an option"

# The register and the source-naming rule.
need "D-19: skill names only when the operator runs one" "A skill name appears only when the operator must run it themselves"
need "D-19: no identifiers in items" "a spec, task or decision identifier never does"
need "REQ-H1.4: mode and age named" "its mode and age"
need "REQ-H1.4: a cited-only class is said so" "only a \`cited\` source"
need "REQ-F1.11: drafts go to the clipboard" "scripts/mc-inbox.sh\`'s \`draft"

# Acting on the operator's behalf, decisions and proposals.
need "REQ-A1.4: never a per-session step" "never hand the operator a per-session step"
need "REQ-A1.5: only the operator's own words count" "Only the operator's own words count"
need "REQ-F1.6: a question to the operator never blocks the turn" "never blocks its turn on a question to the operator"
need "REQ-F1.6: a question goes out as an item, not a blocking selector" "goes out as an item in the turn's text, never through a blocking question selector"
need "REQ-F1.4: the operator queue still decides when a question's item shows" "The operator queue still decides when the item shows"
need "REQ-F1.6: work continues while a question waits" "keeps vetting prompts and moving every other session"
need "REQ-A1.5: the reply is relayed in the operator's words" "relayed to that session in their words"
need "REQ-F1.6: a selector only for a present operator with nothing waiting" "only when the operator's own message is the turn being answered and nothing else waits on mission control"
need "REQ-B1.1: a stated decision enters at once" "scripts/mc-rules.sh\`'s \`add"
need "D-14: accepted non-rule proposals are applied" "scripts/mc-config.sh\`'s \`apply"
need "D-14: a settings change is handed over" "\`handover-operator\`"
need "D-14: a repository change is dispatched" "\`dispatch\`"
need "the duty catalog on request" "scripts/mc-duties.sh\`'s \`list"
need "duty enablement only on the yes" "scripts/mc-config.sh\`'s \`duty"

# Kickoffs and amendments (REQ-I1.5).
need "REQ-I1.5: never unasked" "Never open a kickoff or an amendment unasked"
need "REQ-I1.5: the mode knob decides relay or manual" "scripts/mc-config.sh\`'s \`mode kickoff"
need "REQ-I1.5: kickoff questions are operator-only" "Every kickoff question is operator-only"
need "REQ-I1.5: never settled from the record" "never settle it from the record"
need "REQ-I1.5: manual hands the command over" "\`manual\`"

# Denials, relays and the invariants.
need "REQ-G1.3: a denial reported verbatim" "reported with its exact text and never routed around"
need "D-23: message first, the pane relay only when unreachable" "only an unreachable one takes the pane relay"
need "REQ-I1.1: never merge" "**never** merge"
need "REQ-I1.2: the flip stays inside the policy" "only inside the configured \`ready_flip_policy\`"
need "REQ-I1.3: no send without the yes" "without the yes on the exact text and recipient"
need "REQ-I1.4: rewrite only on the same-turn request" "explicit request in the same turn"
need "REQ-I1.4: no protected push, no remote delete" "never delete a remote branch"
need "REQ-A1.3: never a git mutation" "edit a repository or run a git mutation: every change goes through a session it launches"
need "REQ-G1.4: never a settings edit" "edit a settings file or widen its own posture"
need "REQ-I1.6: the program home is never committed" "the program home is never committed"

# Probes: each need-check fails on a string without its property.
probe() { # probe <label> <text> <needle>
  if has "$2" "$3"; then fail "probe: $1 passed on a violating string"; else ok "probe: $1 caught"; fi
}
probe "a missing pointer" "the tower front door" "/mission-control"
probe "a kickoff settled from the record" "settle the kickoff question from the record" "never settle it from the record"
probe "a question relayed through a blocking selector" "relay the question to the operator through a blocking question selector" "never through a blocking question selector"
probe "a flip outside the policy" "flip a PR ready when asked" "only inside the configured \`ready_flip_policy\`"

[ "$failures" -eq 0 ] || {
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
}
echo "all mission-control skill structural tests passed"
