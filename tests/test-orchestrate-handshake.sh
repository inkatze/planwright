#!/bin/bash
# Structural guard over skills/orchestrate/SKILL.md's use of the session
# mark's activation handshake (fleet-hardening Task 15; D-18; REQ-I1.4): the
# skill runs the orchestrate spelling, the original `activate`, and never the
# tower one, since a /tower mark is sticky and an orchestrate run must not
# claim the front door. The tower skill's counterpart is
# tests/test-tower-skill.sh.
#
# Runs standalone: ./tests/test-orchestrate-handshake.sh
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
ok() { printf 'ok: %s\n' "$1"; }

[ -f "$skill" ] || {
  fail "orchestrate SKILL.md missing at $skill"
  exit 1
}

flat=$(tr '\n' ' ' <"$skill" | tr -s ' ')

# runs_orchestrate_spelling <text>: `tower-session.sh activate` ending the
# command, so neither a tower argument nor any other follows it.
runs_orchestrate_spelling() { printf '%s' "$1" | grep -qE 'scripts/tower-session\.sh activate([^ A-Za-z0-9]|$)'; }
runs_tower_spelling() { printf '%s' "$1" | grep -qE 'tower-session\.sh activate +tower'; }

if runs_orchestrate_spelling "$flat"; then
  ok "the skill runs the orchestrate handshake spelling"
else
  fail "the skill does not run 'scripts/tower-session.sh activate'"
fi
if runs_tower_spelling "$flat"; then
  fail "the skill runs the tower handshake spelling"
else
  ok "the skill runs no tower handshake spelling"
fi

if runs_orchestrate_spelling 'run scripts/tower-session.sh activate tower now'; then
  fail "probe: the tower spelling is accepted as the orchestrate one"
else
  ok "probe: the tower spelling is not the orchestrate one"
fi
if runs_tower_spelling 'run scripts/tower-session.sh activate tower now'; then
  ok "probe: a tower spelling is caught"
else
  fail "probe: a tower spelling is missed"
fi

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
printf '%s\n' "all orchestrate-handshake structural tests passed"
