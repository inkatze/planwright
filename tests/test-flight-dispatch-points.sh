#!/bin/bash
# shellcheck disable=SC2016 # backticks in the patterns are Markdown code spans
# Tests for the in-run points on a visual flight: scripts/flight-dispatch.sh's
# point check and the brief's points section (tower-front-door Task 14;
# D-16, D-17, D-18 · REQ-C1.7, REQ-C1.8, REQ-C1.9, REQ-C1.11, REQ-C1.12).
#
# Properties verified:
#   1. The brief names, in order, exactly the points /execute-task's
#      pre-flight point check names, less the conditional pre-ready-flip
#      (REQ-C1.7); the report names them and the steps each will run.
#   2. Lists carrying skill, prompt, and command steps at every in-run point
#      place the flight (REQ-C1.8); the brief points at the *Points*
#      procedure under the pinned root, pins the resolver there, states
#      --unattended, and maps the pause protocol to the flight park.
#   3. The convergence point keeps its main sync where the flight has a
#      remote and records it not run, with the reason, where it has none.
#   4. post-pr fires after the draft PR with the PR number in context, then
#      /execute-task's after-post-pr sequence by reference, less the ready
#      flip, re-emitting only through flight-record.sh render and parking on
#      a non-draft PR (REQ-C1.11, REQ-C1.12); the file home never fires it.
#   5. Degrade like a task, refuse like a task (REQ-C1.9): an adopter or
#      machine-local list naming an undefined step places the flight with
#      that step named as skipped in the report and the brief; a malformed
#      entry at any layer, a malformed overlay, or an unresolvable skill
#      target refuses, naming the point and step id, and places nothing.
#   6. Under root skew the check runs against the root the brief pins.
#   7. The pin-check: the *Points* heading the brief names exists in
#      /execute-task's skill, and the check fails once it is renamed.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
unset CDPATH
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib/flight-dispatch-fixture.sh
. "$here/lib/flight-dispatch-fixture.sh"

SKILL="$ROOT/skills/execute-task/SKILL.md"

# preflight_points — the points /execute-task's pre-flight check names, read
# from the skill's check command, one per line.
preflight_points() {
  tr '\n' ' ' <"$SKILL" | tr -s ' ' \
    | sed -n 's/.*`scripts\/resolve-steps\.sh \([a-z -]*\) --explain --check --unattended`.*/\1/p' \
    | tr ' ' '\n' | grep -v '^$'
}

# brief_points <brief> — the points the brief's numbered list names, in order.
brief_points() {
  awk '/^The points, in order:$/ {on=1; next} on && /^Skipped at dispatch/ {exit}
    on && /^[0-9]+\. `/ { s = $0; sub(/^[0-9]+\. `/, "", s); sub(/`.*/, "", s); print s }' "$1"
}

# points_pin <skill> — the heading flight-dispatch.sh sends the worker to
# exists in the skill.
points_pin() {
  _h=$(sed -n 's/^POINTS_HEADING=//p' "$ROOT/scripts/flight-dispatch.sh")
  [ -n "$_h" ] && grep -Eq "^## $_h( |$)" "$1"
}

# --- 1. the brief names the pre-flight check's points, in order --------------
want=$(preflight_points | grep -vx pre-ready-flip)
[ "$(printf '%s\n' "$want" | grep -c .)" -ge 5 ] \
  || fail "fixture: the pre-flight check parse found too few points: '$want'"
new_case
dispatch_print
[ "$RC" -eq 0 ] || fail "a default dispatch exited $RC: $ERR"
brief=$(field "$OUT" brief)
[ "$(brief_points "$brief")" = "$want" ] \
  || fail "the brief must name exactly the pre-flight check's points in order; got '$(brief_points "$brief" | tr '\n' ' ')', want '$(printf '%s' "$want" | tr '\n' ' ')'"
[ "$(field "$OUT" points)" = "$(printf '%s' "$want" | tr '\n' ' ')" ] \
  || fail "the report must name the in-run points in order, got '$(field "$OUT" points)'"
printf '%s\n' "$OUT" | grep -qx "steps${TAB}convergence${TAB}polish" \
  || fail "the report must name the convergence point's default step (out: $OUT)"
printf '%s\n' "$OUT" | grep -qx "steps${TAB}pre-ci${TAB}" \
  || fail "the report must name an empty point with no steps (out: $OUT)"
grep -q '^None\.$' "$brief" || fail "a dispatch that skipped nothing must say so in the brief"
grep -q 'pre-ready-flip' "$brief" && fail "the brief must not name the flip point"
grep -Eq 'gh pr (ready|merge)' "$brief" && fail "the brief must never carry a ready flip or merge"

# --- 2. every step kind at every point; the procedure and its mappings -------
new_case
mkdir -p "$c/adopter/catalogs" "$c/primary/.claude"
printf '#!/bin/sh\nexit 0\n' >"$c/lint"
chmod +x "$c/lint"
cat >"$c/adopter/catalogs/steps.yaml" <<EOF
steps:
  - id: lint
    kind: command
    target: $c/lint
    args: --quiet
  - id: reread
    kind: prompt
    target: Re-read the diff once more.
EOF
cat >"$c/primary/.claude/planwright.local.yml" <<'EOF'
steps_pre_implementation: [reread]
steps_pre_ci: [lint]
steps_convergence: [polish, lint, reread]
steps_pre_pr: [self-review]
steps_post_pr: [reread, lint]
EOF
dispatch_print
[ "$RC" -eq 0 ] || fail "skill, prompt, and command steps at every point must place the flight (rc $RC: $ERR)"
[ "$(flight_branches)" -eq 1 ] || fail "a flight with every step kind was not placed"
for pair in "pre-implementation${TAB}reread" "pre-ci${TAB}lint" "convergence${TAB}polish lint reread" \
  "pre-pr${TAB}self-review" "post-pr${TAB}reread lint"; do
  printf '%s\n' "$OUT" | grep -qx "steps${TAB}$pair" || fail "the report must carry 'steps $pair' (out: $OUT)"
done
b=$(cat "$(field "$OUT" brief)")
printf '%s\n' "$b" | grep -qF "*Points*" || fail "the brief must name /execute-task's *Points* procedure"
printf '%s\n' "$b" | grep -qF "\`$ROOT/skills/execute-task/SKILL.md\`" \
  || fail "the brief must read the procedure from the pinned root's skill"
printf '%s\n' "$b" | grep -qF "PLANWRIGHT_ROOT='$ROOT' PLANWRIGHT_SKILLS_ROOT='$ROOT/skills' '$ROOT/scripts/resolve-steps.sh' <point> --explain --unattended" \
  || fail "the brief must pin the resolver to the root it names"
printf '%s\n' "$b" | grep -q 'never `--attended`' || fail "the brief must resolve every point unattended"
printf '%s\n' "$b" | grep -qF 'PLANWRIGHT_STEP_UNIT_KIND=flight' || fail "the brief must set unit kind flight"
printf '%s\n' "$b" | grep -q 'park the flight instead' || fail "the brief must map the pause protocol to the flight park"
printf '%s\n' "$b" | grep -q 'write nothing to any `tasks.md`' || fail "the flight park must write no spec state"
# The worker resolves at point time: the brief lists no pre-resolved step.
printf '%s\n' "$b" | grep -q '/planwright:polish' && fail "the brief must not pre-render a resolved step"
printf '%s\n' "$b" | grep -q 'skill steps only' && fail "the brief must not keep the skill-only rule"
grep -v '^[[:space:]]*#' "$ROOT/scripts/flight-dispatch.sh" | grep -q 'skill steps only' \
  && fail "flight-dispatch.sh must not refuse a step for its kind"

# --- 3 + 4. the pr home: main sync, post-pr, the after-post-pr sequence ------
printf '%s\n' "$b" | grep -qF "'$ROOT/scripts/converge-sync-main.sh'" \
  || fail "a flight with a remote must run the convergence main sync"
printf '%s\n' "$b" | grep -q 'main sync not run' && fail "a flight with a remote must not record the sync as not run"
post=$(printf '%s\n' "$b" | awk '/^Now the draft PR exists/ {on=1} on')
[ -n "$post" ] || fail "the pr-home landing must fire post-pr once the draft PR exists"
pr_line=$(printf '%s\n' "$b" | grep -n 'gh pr create --draft' | head -n 1 | cut -d: -f1)
post_line=$(printf '%s\n' "$b" | grep -n '^Now the draft PR exists: fire `post-pr`' | cut -d: -f1)
[ -n "$pr_line" ] && [ -n "$post_line" ] && [ "$pr_line" -lt "$post_line" ] \
  || fail "post-pr must fire after the draft PR is opened"
printf '%s\n' "$post" | grep -qF 'PLANWRIGHT_STEP_PR_NUMBER' || fail "post-pr must carry the PR number in its context"
printf '%s\n' "$post" | tr '\n' ' ' | grep -q 'run the sequence `/execute-task` runs after its own `post-pr` list' \
  || fail "the brief must reference /execute-task's after-post-pr sequence"
printf '%s\n' "$post" | tr '\n' ' ' | grep -q 'less the unit-PR ready flip' \
  || fail "the after-post-pr sequence must drop the unit-PR ready flip"
printf '%s\n' "$post" | tr '\n' ' ' | grep -q 're-running the render line above, with the same inputs' \
  || fail "the re-emit must go only through flight-record.sh render with the same inputs"
printf '%s\n' "$post" | grep -qF -- "--body-file '$(dirname "$(field "$OUT" brief)")/record/body.md'" \
  || fail "the re-emit must replace the PR body with the re-rendered record"
printf '%s\n' "$post" | grep -qF 'isDraft' || fail "the brief must verify the PR is still a draft"
printf '%s\n' "$post" | tr '\n' ' ' | grep -q 'on anything else, park the flight' \
  || fail "a PR no longer a draft must park the flight"
for heading in 'Steps at' 'render --run <id> --point <point>' 'demoted to `####`'; do
  printf '%s\n' "$b" | grep -qF "$heading" || fail "the brief's audit inputs must name the step tables ('$heading')"
done

# The file home with no remote: no sync, and post-pr never fires.
new_case
gitc "$c/primary" remote remove origin
dispatch_print
[ "$RC" -eq 0 ] || fail "a no-remote dispatch exited $RC: $ERR"
b=$(cat "$(field "$OUT" brief)")
printf '%s\n' "$b" | grep -q 'converge-sync-main' && fail "a flight with no remote must not run the main sync"
printf '%s\n' "$b" | tr '\n' ' ' | grep -q "\`--warning 'main sync not run: the flight has no origin remote'\`" \
  || fail "a flight with no remote must record the main sync as not run, with the reason"
printf '%s\n' "$b" | tr '\n' ' ' | grep -q '`post-pr`: never fires on this flight' \
  || fail "the file home must say post-pr never fires"
printf '%s\n' "$b" | grep -q 'not-fired `post-pr` row' || fail "the file home must leave the not-fired row to the renderer"
printf '%s\n' "$b" | grep -q 'gh pr' && fail "the file home must carry no gh pr command"
[ "$(brief_points "$(field "$OUT" brief)")" = "$want" ] || fail "the file home must still name every in-run point"

# --- 5. degrade like a task, refuse like a task -------------------------------
for layer in adopter machine-local; do
  new_case
  mkdir -p "$c/primary/.claude"
  if [ "$layer" = adopter ]; then
    printf 'steps_pre_ci: [no-such-step]\n' >>"$c/adopter/planwright.yml"
  else
    printf 'steps_pre_ci: [no-such-step]\n' >"$c/primary/.claude/planwright.local.yml"
  fi
  dispatch_print
  [ "$RC" -eq 0 ] || fail "$layer: an undefined step id must degrade to a skip, not refuse (rc $RC: $ERR)"
  printf '%s\n' "$OUT" | grep -qx "skipped${TAB}pre-ci${TAB}no-such-step" \
    || fail "$layer: the report must name the skipped step and its point (out: $OUT)"
  grep -qx -- '- `pre-ci`: `no-such-step`' "$(field "$OUT" brief)" \
    || fail "$layer: the brief must name the skipped step and its point"
  case $ERR in *"pre-ci: skip: step 'no-such-step'"*) ;; *) fail "$layer: the resolver's skip warning must be relayed: $ERR" ;; esac
done

# refused <label> — the dispatch was refused with nothing placed, naming $1.
refused() {
  [ "$RC" -eq 4 ] || fail "$label: must refuse with exit 4 (rc $RC: $ERR)"
  case $ERR in *"$1"*) ;; *) fail "$label: the refusal must name '$1': $ERR" ;; esac
  case $ERR in *"nothing was placed"*) ;; *) fail "$label: the refusal must say nothing was placed: $ERR" ;; esac
  [ "$(flight_branches)" -eq 0 ] || fail "$label: placed a flight"
  [ "$(briefs)" -eq 0 ] || fail "$label: left a brief"
}
bad_entry='steps:\n  - id: bad\n    kind: skill\n    target: polish\n    bogus: 1\n'
for layer in adopter repo-tracked machine-local; do
  new_case
  mkdir -p "$c/adopter/catalogs" "$c/primary/.claude/catalogs" "$c/primary/.claude/catalogs.local"
  case $layer in
    adopter) dest="$c/adopter/catalogs/steps.yaml" ;;
    repo-tracked) dest="$c/primary/.claude/catalogs/steps.yaml" ;;
    machine-local) dest="$c/primary/.claude/catalogs.local/steps.yaml" ;;
  esac
  # shellcheck disable=SC2059 # the entry carries its own \n escapes
  printf "$bad_entry" >"$dest"
  printf 'steps_pre_pr: [bad]\n' >"$c/primary/.claude/planwright.local.yml"
  dispatch_print
  label="a malformed $layer entry"
  if [ "$layer" = repo-tracked ]; then
    refused "malformed entry 'bad'"
  else
    refused "pre-pr: step 'bad'"
  fi
done
# A malformed overlay degrades a task unit's check too.
new_case
mkdir -p "$c/primary/.claude"
printf 'steps_pre_ci:\n  nested: 1\n' >"$c/primary/.claude/planwright.local.yml"
dispatch_print
label="a malformed machine-local overlay"
refused "pre-ci"
# An unresolvable skill target is a step no worker can run.
new_case
mkdir -p "$c/adopter/catalogs" "$c/primary/.claude"
printf 'steps:\n  - id: ghost\n    kind: skill\n    target: no-such-skill\n' >"$c/adopter/catalogs/steps.yaml"
printf 'steps_post_pr: [ghost]\n' >"$c/primary/.claude/planwright.local.yml"
dispatch_print
label="an unresolvable skill target"
refused "post-pr: step 'ghost'"

# --- 6. root skew: the check runs under the pinned root ----------------------
# install_root <version> — a full installed copy of this plugin the worker
# root resolves to; prints its path.
install_root() {
  _inst="$c/claude/plugins/cache/mk/planwright/$1"
  mkdir -p "$_inst"
  cp -R "$ROOT/scripts" "$ROOT/skills" "$ROOT/config" "$ROOT/doctrine" "$ROOT/.claude-plugin" "$_inst/"
  printf '{"name":"planwright","version":"%s"}\n' "$1" >"$_inst/.claude-plugin/plugin.json"
  printf '%s' "$_inst"
}
new_case
inst=$(install_root 0.0.1-skew)
sed 's/^steps_pre_pr:.*/steps_pre_pr: [skew-only-step]/' "$ROOT/config/defaults.yml" >"$inst/config/defaults.yml"
dispatch_print
label="a step only the pinned root's core list names"
refused "pre-pr: step 'skew-only-step'"
new_case
inst=$(install_root 0.0.1-skew)
sed 's/^steps_convergence:.*/steps_convergence: [self-review]/' "$ROOT/config/defaults.yml" >"$inst/config/defaults.yml"
dispatch_print
[ "$RC" -eq 0 ] || fail "a skewed worker root must place the flight (rc $RC: $ERR)"
[ "$(field "$OUT" root-skew)" = yes ] || fail "the fixture must read as skewed (out: $OUT)"
printf '%s\n' "$OUT" | grep -qx "steps${TAB}convergence${TAB}self-review" \
  || fail "the check must resolve the pinned root's core list, not the tower's (out: $OUT)"
grep -qF "PLANWRIGHT_ROOT='$inst' PLANWRIGHT_SKILLS_ROOT='$inst/skills' '$inst/scripts/resolve-steps.sh'" "$(field "$OUT" brief)" \
  || fail "the brief must pin the worker's root for the resolver"
new_case
inst="$c/claude/plugins/cache/mk/planwright/0.0.2-bare"
mkdir -p "$inst/.claude-plugin"
printf '{"name":"planwright","version":"0.0.2-bare"}\n' >"$inst/.claude-plugin/plugin.json"
dispatch_print
label="a pinned root with no resolver"
refused "no step resolver"

# --- 7. the pin-check ---------------------------------------------------------
points_pin "$SKILL" || fail "the *Points* heading the brief names is missing from /execute-task's skill"
sed 's/^## Points /## Point runner /' "$SKILL" >"$tmp/renamed-skill.md"
points_pin "$tmp/renamed-skill.md" && fail "the pin-check must fail once the heading is renamed"

finish test-flight-dispatch-points
