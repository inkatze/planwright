#!/bin/bash
# Structural guard over the /orchestrate skill's bring-up section: the
# classifier call and its response per tower_placement value, the refuse hold
# and unattended parking, once per invocation, the isolation probe, the
# activation handshake, the fallback, and the layers named. The live behavior
# (each knob value, the plugin hook wired, absent, unresolved) is the PR
# checklist's manual runs, not covered here.
#
# Runs standalone: ./tests/test-orchestrate-bringup.sh
# The patterns name backticked tokens literally, not command substitutions.
# shellcheck disable=SC2016
set -u
LC_ALL=C
export LC_ALL
set -f
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
skill="$REPO_ROOT/skills/orchestrate/SKILL.md"
failures=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

ok() {
  printf 'ok: %s\n' "$1"
}

if [ ! -f "$skill" ]; then
  fail "orchestrate SKILL.md missing at $skill"
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi

# section <heading-text>: the folded body of the `## ` section whose heading
# opens with the text.
section() {
  awk -v h="## $1" '
    index($0, h) == 1 {on=1; next}
    on && /^## / {exit}
    on {print}' "$skill" | tr '\n' ' ' | tr -s ' '
}

check() { # check <label> <text> <extended-regex>...: every regex must match
  local label=$1 text=$2 re
  shift 2
  for re in "$@"; do
    if ! printf '%s\n' "$text" | grep -qiE -- "$re"; then
      fail "$label: no match for /$re/"
      return
    fi
  done
  ok "$label"
}

bringup=$(section "Bring-up")
if [ -z "$bringup" ]; then
  fail "no '## Bring-up' section"
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
ok "skill has a Bring-up section"

check "the classifier is called and none counts as a main tree (REQ-B1.1)" "$bringup" \
  'scripts/tower-placement\.sh' '`none`[^.]*main tree'

check "the response follows tower_placement (REQ-B1.2)" "$bringup" \
  '`warn`[^.]*once' '`refuse` holds' '`allow` says nothing'

check "refuse holds dispatch, relay, and the bookkeeping push and PR (REQ-B1.2)" "$bringup" \
  'refuse[^.]*dispatch, relay' 'bookkeeping push and PR' 'status[^.]*continu'

check "an unattended run notifies and parks in Awaiting input (REQ-B1.2)" "$bringup" \
  'unattended[^.]*(notif|park)[^.]*Awaiting input'

check "the bring-up runs once per invocation, not per --watch step (REQ-B1.2, REQ-B1.5)" "$bringup" \
  'once per invocation' '--watch[^.]*(not|never)' 'on request'

check "the isolation probe warns once, names the supported launch, never blocks (REQ-B1.3)" "$bringup" \
  'isolation probe' 'warns? once' 'never blocks?'

check "the activation handshake re-marks the session (REQ-C1.8, REQ-C1.9)" "$bringup" \
  'scripts/tower-session\.sh activate' 'handshake' 'repeated on request'

check "enforcement counts active only on the ACTIVE refusal (REQ-B1.4)" "$bringup" \
  'ACTIVE' 'only[^.]*refus'

check "plugin enforcement meets the floor and the fallback holds the outward acts (REQ-B1.4)" "$bringup" \
  'plugin enforcement' 'missing or broken' 'holds? (its )?outward acts'

check "every layer read is named, the plugin hooks file included (REQ-B1.4)" "$bringup" \
  'names? every (settings )?layer' 'hooks/hooks\.json'

# Probes: the checks that could pass with the property absent fail against a
# deliberately violating string.
if printf '%s\n' 'the skill runs scripts/tower-placement.sh' | grep -qiE -- '`none`[^.]*main tree'; then
  fail "probe: a bring-up without the none rule passes the classifier check"
else
  ok "probe: the none rule is required"
fi

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
printf '%s\n' "all orchestrate bring-up structural tests passed"
