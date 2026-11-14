#!/bin/bash
# Structural guard over /resume's tower mode (tower-front-door Task 8; D-9,
# REQ-F1.4).
#
# Both reconstruction surfaces, the tower's start sweep and /resume's tower
# mode, must render from the one shared sweep (scripts/flight-sweep.sh), so the
# two cannot drift. The skills are procedure the agent reads, so the call sites
# are asserted over their text. The sweep's own behaviour, --no-write included,
# is tests/test-flight-sweep.sh's.
#
# Asserted properties:
#   - /resume has a tower mode, selected by its `tower` argument and advertised
#     in its argument hint;
#   - the mode renders through `scripts/flight-sweep.sh sweep --no-write`, the
#     form that writes nothing, since /resume is read-only;
#   - the tower's bring-up and its flight status read the same script;
#   - the mode carries no second derivation path: none of the reads the sweep
#     itself makes (flight branches, worktrees, PRs, record files, the
#     registry's liveness, the decision queue), so a failed sweep degrades
#     rather than falling back to its own derivation;
#   - the mode is covered by the skill's read-only invariants.
#
# Each pattern that could pass with the property absent is probed at the end
# against a deliberately violating string.

set -u
LC_ALL=C
export LC_ALL
set -f
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
resume="$REPO_ROOT/skills/resume/SKILL.md"
tower="$REPO_ROOT/skills/tower/SKILL.md"

failures=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

ok() {
  printf 'ok: %s\n' "$1"
}

flat() {
  tr '\n' ' ' | tr -s ' '
}

for f in "$resume" "$tower"; do
  if [ ! -f "$f" ]; then
    fail "missing: $f"
    printf '%s failure(s)\n' "$failures" >&2
    exit 1
  fi
done

frontmatter=$(awk 'NR==1{next} $0=="---"{exit} {print}' "$resume")
mode=$(awk '/^## Tower mode/ { on = 1; next } on && /^## / { exit } on' "$resume" | flat)
invariants=$(awk '/^## Invariants/ { on = 1; next } on && /^## / { exit } on' "$resume" | flat)
tower_bringup=$(awk '/^2\. \*\*Reconstruct/ { on = 1 } /^3\. \*\*The first turn/ { on = 0 } on' "$tower" | flat)
tower_status=$(awk '/^## Status on demand/ { on = 1; next } on && /^## / { exit } on' "$tower" | flat)

sweep_cmd='scripts/flight-sweep.sh sweep --no-write'
# The reads the sweep makes for itself; any of them in the mode is a second
# derivation path beside it.
second_path_re='git branch --list|planwright/flight/\*|gh pr (list|view)|git worktree list|git cat-file|_flights/|fleet-attention\.sh queue|fleet-death-evidence|fleet-registry'

if [ -z "$mode" ]; then
  fail "/resume has no '## Tower mode' section"
else
  ok "/resume has a tower mode section"
fi

if printf '%s\n' "$frontmatter" | grep -qE '^argument-hint:.*tower'; then
  ok "the argument hint advertises the tower mode"
else
  fail "the argument hint does not name the tower mode"
fi

# shellcheck disable=SC2016
case $mode in
  *'`/resume tower`'*) ok "the mode is selected by the tower argument" ;;
  *) fail "the mode does not say it is selected by '/resume tower'" ;;
esac

case $mode in
  *"$sweep_cmd"*) ok "the mode renders through the shared sweep's no-write form" ;;
  *) fail "the mode does not invoke '$sweep_cmd'" ;;
esac

# A forge skipped for want of gh or a timeout is a degraded read, as the
# tower's bring-up treats it; only no-flights and no-origin are clean skips.
# shellcheck disable=SC2016
case $mode in
  *'`forge`, `registry`, or `queue` row other than `ok`'*'`no-flights` or `no-origin`'*)
    ok "the mode names every degraded read a partial load, as the tower does"
    ;;
  *) fail "the mode does not tie partial load to any non-ok forge, registry, or queue row" ;;
esac

case $tower_bringup in
  *'scripts/flight-sweep.sh'*) ok "the tower's bring-up reads the same sweep" ;;
  *) fail "the tower's bring-up does not read scripts/flight-sweep.sh" ;;
esac
case $tower_status in
  *'scripts/flight-sweep.sh sweep'*) ok "the tower's flight status reads the same sweep" ;;
  *) fail "the tower's flight status does not read scripts/flight-sweep.sh sweep" ;;
esac

if printf '%s\n' "$mode" | grep -qE -- "$second_path_re"; then
  fail "the mode carries a second derivation path beside the sweep: $(printf '%s\n' "$mode" | grep -oE -- "$second_path_re" | head -1)"
else
  ok "the mode carries no second derivation path"
fi

case $invariants in
  *'tower mode'*) ok "the read-only invariants cover the tower mode" ;;
  *) fail "the invariants do not name the tower mode" ;;
esac

# --- Probes: each pattern catches the violation it guards against ----------
probe_mode="Run \`/resume tower\`; on a failed sweep, list \`git branch --list 'planwright/flight/*'\` and \`gh pr list --head <branch>\`."
if printf '%s\n' "$probe_mode" | grep -qE -- "$second_path_re"; then
  ok "probe: a fallback derivation in the mode is caught"
else
  fail "probe: a fallback derivation escapes the second-path pattern"
fi
# shellcheck disable=SC2016
probe_mode='Read `scripts/fleet-attention.sh queue` for parked flights.'
if printf '%s\n' "$probe_mode" | grep -qE -- "$second_path_re"; then
  ok "probe: a separate queue read in the mode is caught"
else
  fail "probe: a separate queue read escapes the second-path pattern"
fi
probe_mode='run scripts/flight-sweep.sh sweep and render it'
case $probe_mode in
  *"$sweep_cmd"*) fail "probe: a writing sweep passes as the no-write form" ;;
  *) ok "probe: a writing sweep is not taken for the no-write form" ;;
esac

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
printf '%s\n' "all resume tower-mode tests passed"
