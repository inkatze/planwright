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
#      procedure under the pinned root with no root-assignment prefix,
#      states --unattended, maps the pause protocol and the stop conditions
#      to the flight park, and re-fires on relaunch each point no run
#      completed cleanly, rendering each table from the run that did.
#   3. The convergence point keeps its main sync where the flight has a
#      remote and records it not run, with the reason, where it has none.
#   4. post-pr fires after the draft PR with the PR number in context, then
#      /execute-task's after-post-pr sequence by reference, less the ready
#      flip, re-emitting only through flight-record.sh render and parking on
#      a non-draft PR (REQ-C1.11, REQ-C1.12); the file home never fires it.
#      A relaunched worker finds an existing PR or committed record and never
#      pushes, creates, or lands twice.
#   5. Degrade like a task, refuse like a task (REQ-C1.9): an adopter or
#      machine-local list naming an undefined step places the flight with
#      that step named as skipped in the report and the brief; a malformed
#      entry or list at any layer, a malformed overlay, a repo-tracked list
#      naming an undefined step, an unresolvable skill target, or a broken or
#      too-old pinned install refuses and places nothing, naming the step and
#      its point, the malformed entry or layer and its points, the points a
#      malformed overlay failed, or the install, and never a step that passed.
#   6. Under root skew the check runs against the root the brief pins, and
#      both rungs' launches pin the worker to that root.
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
printf '%s\n' "$b" | grep -qF "\`'$ROOT/scripts/resolve-steps.sh' <point> --explain --unattended\`" \
  || fail "the brief must pin the resolver to the root it names"
printf '%s\n' "$b" | grep -q 'never `--attended`' || fail "the brief must resolve every point unattended"
printf '%s\n' "$b" | grep -qF 'PLANWRIGHT_STEP_UNIT_KIND=flight' || fail "the brief must set unit kind flight"
flat "$b" | grep -q 'ends, parks, or stops the unit (the pause protocol or a stop condition), park the flight instead' \
  || fail "the brief must map the pause protocol and the stop conditions to the flight park"
fid=$(field "$OUT" flight)
printf '%s\n' "$b" | grep -qF "launch tier takes the unit \`flight:$fid\`" \
  || fail "an isolated step's launch tier must take the flight's own unit"
# The guard defers an environment-assignment prefix, so the brief carries none:
# the launch pins the root instead.
printf '%s\n' "$b" | grep -q 'PLANWRIGHT_ROOT=\|PLANWRIGHT_SKILLS_ROOT=' \
  && fail "the brief must not prefix a command with a root assignment"
flat "$b" | grep -q "Relaunch: issue one run id per worker launch. A relaunched worker fires again, each at its moment below, every point no run of this flight completed without a halted, failed, or limited step (\`step-record.sh list\` across every run), running its whole list; it takes no \`resume\` skip within a point. Any \`reuse\` skip or re-fire pass the \*Points\* procedure runs applies as in any run, a re-fire pass taking the \`pre-ci\` and \`pre-pr\` lists as this launch resolves them, fired or not. It never fires a point this home never fires" \
  || fail "a relaunched worker must re-fire, at its moment, every point no run completed cleanly"
flat "$b" | grep -q 'If this branch already carries commits of yours, or `step-record.sh list` shows a run of this flight, you are a relaunched worker' \
  || fail "the brief must define a relaunch once, by the evidence its rules use"
flat "$b" | sed 's/takes no `resume` skip//' | grep -qi 'resum' && fail "the brief must not promise a resume the tooling lacks"
flat "$b" | grep -q 'each from the latest run holding that point.s completion record' \
  || fail "each step table must render from the latest run that completed its point"
case $(field "$OUT" launch) in
  *"fleet-dispatch-env.sh' '--root' '$ROOT' 'claude' '--worktree'"*) ;;
  *) fail "the print launch must pin the brief's root: $(field "$OUT" launch)" ;;
esac
flat "$b" | grep -q 'write nothing to any `tasks.md`' || fail "the flight park must write no spec state"
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
flat "$post" | grep -q 'run the sequence `/execute-task` runs after its own `post-pr` list' \
  || fail "the brief must reference /execute-task's after-post-pr sequence"
flat "$post" | grep -q 'less the unit-PR ready flip' \
  || fail "the after-post-pr sequence must drop the unit-PR ready flip"
record_dir="$(dirname "$(field "$OUT" brief)")/record"
printf '%s\n' "$post" | grep -qF "flight-record.sh' render --home pr --flight-id $fid " \
  || fail "the re-emit must go only through flight-record.sh render"
printf '%s\n' "$post" | grep -qF -- "> '$record_dir/body.new.md' && gh pr edit <number> --repo github.com/acme/widgets --body-file '$record_dir/body.new.md'" \
  || fail "the re-emit must render to its own file and only then replace the PR body"
printf '%s\n' "$post" | grep -F 'gh pr edit' | grep -q 'git push\|gh pr create\|pr-url' \
  && fail "the re-emit line must not push, create a PR, or touch pr-url again"
flat "$post" | grep -q 'with the same inputs, never by editing the PR body by hand' \
  || fail "the re-emit must keep the first render's inputs"
flat "$post" | grep -q 'A refusal of your own inputs is fixed and the re-emit re-run' \
  || fail "a refusal of the worker's own inputs must be fixed and re-run, not parked"
flat "$post" | grep -q 'any other non-zero exit from the render, or from the edit, parks the flight' \
  || fail "any other failed re-render or edit must park the flight"
flat "$post" | grep -q 'its `## Pending sign-off` heading demoted to `####`' \
  || fail "the regenerated checklist's heading must be demoted under the record's"
printf '%s\n' "$b" | grep -qF -- "> '$record_dir/pr-url.tmp' && mv '$record_dir/pr-url.tmp' '$record_dir/pr-url'" \
  || fail "a failed create must never empty pr-url"
flat "$b" | grep -q "It first runs \*Landing\*'s landed check; a flight that has landed fires again no point whose moment comes before landing, since such a point's commits could never reach the landed PR or record" \
  || fail "a relaunch must check landing first, and a landed flight must not re-fire a pre-landing point"
flat "$b" | grep -q 'A non-zero exit from the push or the create parks the flight' \
  || fail "a failed push or create must park the flight"
printf '%s\n' "$b" | grep -qF -- "gh pr list --repo github.com/acme/widgets --head planwright/flight/$fid --state open --json url,isCrossRepository,headRefOid --jq '.[] | select(.isCrossRepository | not) | .headRefOid + \" \" + .url' > '$record_dir/pr-url.found'" \
  || fail "a relaunched worker must look for the flight's own same-repository PR"
# flight-lifecycle.sh relaunches a landed flight only under a brief carrying
# this check, found by the phrase it greps for.
marker=$(sed -n "s/.*grep -q '\\(runs this landed check\\)'.*/\\1/p" "$ROOT/scripts/flight-lifecycle.sh")
[ "$marker" = "runs this landed check" ] || fail "flight-lifecycle.sh must recognize the landed-check brief by its phrase"
printf '%s\n' "$b" | grep -q "$marker" || fail "the brief must carry the phrase flight-lifecycle.sh recognizes"
flat "$b" | grep -q 'A relaunched worker runs this landed check before it fires any point' \
  || fail "a relaunched pr-home worker must check landing before it fires any point"
flat "$b" | grep -q 'A non-zero exit from the view or the list parks the flight: a failed lookup is never "no PR" or "not open"' \
  || fail "a failed PR lookup must park, never read as no PR"
flat "$b" | grep -q 'in this order. When `record/pr-url` exists, it is the flight.s own record of its PR:' \
  || fail "the flight's own recorded PR must decide first"
flat "$b" | grep -q 'must print `OPEN` for the flight to have landed, and anything else parks it. Otherwise it lists the open same-repository PRs on this branch' \
  || fail "a recorded PR lands the flight only while open; the lookup decides only without one"
flat "$b" | grep -q 'More than one line whose sha equals `git rev-parse HEAD` parks the flight; exactly one is the flight.s PR, and it has landed' \
  || fail "an ambiguous match at this branch's tip must park"
printf '%s\n' "$b" | grep -qF -- "awk -v h=\"\$(git rev-parse HEAD)\" '\$1 == h { print \$2 }' '$record_dir/pr-url.found' > '$record_dir/pr-url.tmp' && mv '$record_dir/pr-url.tmp' '$record_dir/pr-url'" \
  || fail "a found PR's URL must be recorded alone, through a temporary file"
flat "$b" | grep -q "With none, it has not landed: it fires the points \*Work and the points\*' Relaunch bullet says are still due and lands as above" \
  || fail "a relaunch that has not landed fires only the points still due"
printf '%s\n' "$b" | grep -qF "gh pr view <url> --repo github.com/acme/widgets --json state --jq .state" \
  || fail "a recorded PR must be checked open before it counts"
flat "$b" | grep -q 'A landed relaunch skips the push-and-create line, fires `post-pr` only if the Relaunch bullet says it is still due, and runs the sequence after it (re-emit, draft check, completion) either way' \
  || fail "a landed relaunch must skip the push and create, not re-fire a completed post-pr, yet still re-emit and check the draft"
flat "$post" | grep -q 'replace its Pending sign-off section with the regenerated checklist' \
  || fail "a moved head must carry the regenerated checklist into the re-emit"
printf '%s\n' "$post" | grep -qF 'isDraft' || fail "the brief must verify the PR is still a draft"
flat "$post" | grep -q 'on anything else, park the flight' \
  || fail "a PR no longer a draft must park the flight"
for phrase in 'Steps at' 'render --run <id> --point <point>' 'demoted to `####`'; do
  printf '%s\n' "$b" | grep -qF "$phrase" || fail "the brief's audit inputs must name the step tables ('$phrase')"
done

# The file home with no remote: no sync, and post-pr never fires.
new_case
gitc "$c/primary" remote remove origin
dispatch_print
[ "$RC" -eq 0 ] || fail "a no-remote dispatch exited $RC: $ERR"
b=$(cat "$(field "$OUT" brief)")
printf '%s\n' "$b" | grep -q 'converge-sync-main' && fail "a flight with no remote must not run the main sync"
flat "$b" | grep -q "\`--warning 'main sync not run: the flight has no origin remote'\`" \
  || fail "a flight with no remote must record the main sync as not run, with the reason"
flat "$b" | grep -q '`post-pr`: never fires on this flight' \
  || fail "the file home must say post-pr never fires"
printf '%s\n' "$b" | grep -q 'not-fired `post-pr` row' || fail "the file home must leave the not-fired row to the renderer"
printf '%s\n' "$b" | grep -q 'gh pr' && fail "the file home must carry no gh pr command"
fid=$(field "$OUT" flight)
flat "$b" | grep -qF "A relaunched worker runs this landed check before it fires any point. The flight has landed when \`git cat-file -e 'HEAD:specs/_flights/$fid.md'\` succeeds: it skips the land and pushes the completion" \
  || fail "a relaunched file-home worker must test the record against HEAD, before any point"
flat "$b" | grep -q "an interrupted land's leftover, which it clears at once, before any point can commit it" \
  || fail "an interrupted land's leftover must be cleared before a re-fired point can commit it"
flat "$b" | grep -q 'A non-zero exit from that line parks the flight, naming what the line printed' \
  || fail "a failed leftover cleanup must park the flight"
printf '%s\n' "$b" | grep -qF "git rm -q --cached --ignore-unmatch -- 'specs/_flights/$fid.md' && rm -f -- 'specs/_flights/$fid.md' 'specs/_flights'/.$fid.md.*" \
  || fail "a relaunched file-home worker must clear an interrupted land's record and temp link"
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

# reason — the refusal's reason: its text between the exit code and the
# pointer to the relayed diagnostics.
reason() {
  printf '%s\n' "$ERR" | grep '^flight-dispatch: ' | sed -n 's/.*(resolve-steps exit [0-9]*): \(.*\); the diagnostics above say why.*/\1/p'
}

# refused <expected-text> — the dispatch, described by the caller's $label, was
# refused with nothing placed, its own refusal line carrying <expected-text>.
refused() {
  _line=$(printf '%s\n' "$ERR" | grep '^flight-dispatch: ')
  [ "$RC" -eq 4 ] || fail "$label: must refuse with exit 4 (rc $RC: $ERR)"
  case $_line in *"$1"*) ;; *) fail "$label: the refusal must name '$1': $ERR" ;; esac
  case $_line in *"nothing was placed"*) ;; *) fail "$label: the refusal must say nothing was placed: $ERR" ;; esac
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
    refused "malformed entry 'bad' (at pre-implementation, pre-ci, convergence, pre-pr, post-pr)"
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
refused "the check failed at pre-implementation, pre-ci, convergence, pre-pr, post-pr"
# The same from the adopter layer.
new_case
printf 'steps_pre_ci:\n  nested: 1\n' >>"$c/adopter/planwright.yml"
dispatch_print
label="a malformed adopter overlay"
refused "the check failed at pre-implementation, pre-ci, convergence, pre-pr, post-pr"
# A skip that passes on its own is never blamed for a refusal.
new_case
mkdir -p "$c/primary/.claude"
printf 'steps_pre_ci: [no-such-step]\n' >>"$c/adopter/planwright.yml"
printf 'steps_convergence:\n  nested: 1\n' >"$c/primary/.claude/planwright.local.yml"
dispatch_print
label="a legal skip beside a malformed overlay"
refused "the check failed at pre-implementation, pre-ci, convergence, pre-pr, post-pr"
printf '%s\n' "$ERR" | grep '^flight-dispatch: ' | grep -q 'no-such-step' \
  && fail "a passing skip must not be named in the refusal: $ERR"
# An unresolvable skill target is a step no worker can run.
new_case
mkdir -p "$c/adopter/catalogs" "$c/primary/.claude"
printf 'steps:\n  - id: ghost\n    kind: skill\n    target: no-such-skill\n' >"$c/adopter/catalogs/steps.yaml"
printf 'steps_post_pr: [ghost]\n' >"$c/primary/.claude/planwright.local.yml"
dispatch_print
label="an unresolvable skill target"
refused "post-pr: step 'ghost'"
# A repo-tracked list naming an undefined step parks, so it refuses.
new_case
mkdir -p "$c/primary/.claude"
printf 'steps_pre_ci: [no-such-step]\n' >"$c/primary/.claude/planwright.yml"
dispatch_print
label="a repo-tracked list naming an undefined step"
refused "pre-ci: step 'no-such-step'"
# A malformed repo-tracked list, and a repo-tracked catalog malformed as a
# whole, name where they reached.
new_case
mkdir -p "$c/primary/.claude"
printf 'steps_pre_ci: [Bad_Id]\n' >"$c/primary/.claude/planwright.yml"
dispatch_print
label="a malformed repo-tracked list"
refused "the repo-tracked config or catalog is malformed (at pre-ci)"
new_case
mkdir -p "$c/primary/.claude/catalogs"
printf 'steps:\n  - kind: skill\n    target: polish\n' >"$c/primary/.claude/catalogs/steps.yaml"
dispatch_print
label="a repo-tracked catalog entry with no id"
refused "the repo-tracked config or catalog is malformed (at pre-implementation, pre-ci, convergence, pre-pr, post-pr)"
[ "$(reason)" = "the repo-tracked config or catalog is malformed (at pre-implementation, pre-ci, convergence, pre-pr, post-pr)" ] \
  || fail "$label: the refusal must name the catalog alone, got '$(reason)'"
# An entry id outside the id charset keeps its layer and id.
new_case
mkdir -p "$c/primary/.claude/catalogs"
printf 'steps:\n  - id: Foo!x\n    kind: skill\n    target: polish\n' >"$c/primary/.claude/catalogs/steps.yaml"
dispatch_print
label="a repo-tracked entry id outside the charset"
refused "malformed entry 'Foo?x' (at pre-implementation, pre-ci, convergence, pre-pr, post-pr)"
# A list or entry the resolver places malformed names its step.
new_case
mkdir -p "$c/primary/.claude/catalogs"
printf 'steps:\n  - id: rx\n    kind: command\n    target: scripts/x.sh\n    paths: src\n    refire: post-pr\n' \
  >"$c/primary/.claude/catalogs/steps.yaml"
printf 'steps_convergence: [rx]\n' >"$c/primary/.claude/planwright.yml"
dispatch_print
label="a step placed malformed"
refused "convergence: step 'rx'"
# A sibling reader's repo-tracked hard-fail is named by its key.
new_case
mkdir -p "$c/primary/.claude"
printf 'dispatch_isolation: weird\n' >"$c/primary/.claude/planwright.yml"
dispatch_print
label="a sibling reader's repo-tracked hard-fail"
refused "the repo-tracked config sets dispatch_isolation to a malformed value"
# A parked point prints every one of its steps; only the broken one is named.
new_case
mkdir -p "$c/adopter/catalogs" "$c/primary/.claude"
printf 'steps:\n  - id: ghost\n    kind: skill\n    target: no-such-skill\n' >"$c/adopter/catalogs/steps.yaml"
printf 'steps_convergence: [polish, ghost]\n' >"$c/primary/.claude/planwright.local.yml"
dispatch_print
label="a parked point with a healthy step"
refused "convergence: step 'ghost'"
printf '%s\n' "$ERR" | grep '^flight-dispatch: ' | grep -q "step 'polish'" \
  && fail "a healthy step at a parked point must not be named in the refusal: $ERR"

# --- 6. root skew: the check runs under the pinned root ----------------------
new_case
inst="$c/claude/plugins/cache/mk/planwright/0.0.1-skew"
install_plugin_copy "$inst" 0.0.1-skew
sed 's/^steps_pre_pr:.*/steps_pre_pr: [skew-only-step]/' "$ROOT/config/defaults.yml" >"$inst/config/defaults.yml"
dispatch_print
label="a step only the pinned root's core list names"
refused "pre-pr: step 'skew-only-step'"
new_case
inst="$c/claude/plugins/cache/mk/planwright/0.0.1-skew"
install_plugin_copy "$inst" 0.0.1-skew
sed 's/^steps_convergence:.*/steps_convergence: [self-review]/' "$ROOT/config/defaults.yml" >"$inst/config/defaults.yml"
dispatch_print
[ "$RC" -eq 0 ] || fail "a skewed worker root must place the flight (rc $RC: $ERR)"
[ "$(field "$OUT" root-skew)" = yes ] || fail "the fixture must read as skewed (out: $OUT)"
printf '%s\n' "$OUT" | grep -qx "steps${TAB}convergence${TAB}self-review" \
  || fail "the check must resolve the pinned root's core list, not the tower's (out: $OUT)"
skew_brief=$(field "$OUT" brief)
[ "$(cat "$(dirname "$skew_brief")/root")" = "$inst" ] \
  || fail "the brief directory must record the worker's pinned root, not the tower's"
grep -qF "\`'$inst/scripts/resolve-steps.sh' <point> --explain --unattended\`" "$skew_brief" \
  || fail "the brief must call the worker root's resolver"
case $(field "$OUT" launch) in
  *"'--root' '$inst' 'claude'"*) ;;
  *) fail "the print launch must pin the worker's root: $(field "$OUT" launch)" ;;
esac
grep -qF "\`$inst/skills/execute-task/SKILL.md\`" "$skew_brief" \
  || fail "the brief must read the procedure from the worker's root, not the tower's"
grep -qF "'$inst/scripts/converge-sync-main.sh'" "$skew_brief" \
  || fail "the brief must run the main sync from the worker's root"
run dispatch readme-typo --backend tmux --ask-file "$c/ask.txt" --grounds-file "$c/grounds.txt" \
  --repo-root "$c/primary" --attach-dry-run
[ "$RC" -eq 0 ] || fail "a skewed tmux dry run must place the flight (rc $RC: $ERR)"
plan=$(printf '%s\n' "$OUT" | awk -F"$TAB" '$1=="attach-plan" && $2=="launch"')
case $plan in
  *"fleet-dispatch-env.sh${TAB}"*"--root${TAB}$inst${TAB}"*) ;;
  *) fail "the tmux launch must pin the worker's root: $plan" ;;
esac
# A degraded list beside a parked point is named, not only the park.
new_case
inst="$c/claude/plugins/cache/mk/planwright/0.0.1-skew"
install_plugin_copy "$inst" 0.0.1-skew
sed 's/^steps_pre_ci:.*/steps_pre_ci: [ghost-core]/' "$ROOT/config/defaults.yml" >"$inst/config/defaults.yml"
mkdir -p "$c/primary/.claude"
printf 'steps_pre_ci: [Bad_Id]\n' >"$c/primary/.claude/planwright.local.yml"
dispatch_print
label="a degraded list beside a parked point"
refused "the machine-local steps_pre_ci list is malformed (at pre-ci)"
refused "pre-ci: step 'ghost-core'"
# A malformed core list is a broken install, named with the point it reached.
new_case
inst="$c/claude/plugins/cache/mk/planwright/0.0.1-skew"
install_plugin_copy "$inst" 0.0.1-skew
sed 's/^steps_pre_pr:.*/steps_pre_pr: [Bad_Id]/' "$ROOT/config/defaults.yml" >"$inst/config/defaults.yml"
dispatch_print
label="a malformed core list"
refused "the planwright install at $inst is broken"
printf '%s\n' "$ERR" | grep '^flight-dispatch: ' | grep -qF '(at pre-pr)' \
  || fail "$label: the refusal must name the point the core list reached: $ERR"
# A malformed entry in the pinned root's core catalog is a broken install.
new_case
inst="$c/claude/plugins/cache/mk/planwright/0.0.1-skew"
install_plugin_copy "$inst" 0.0.1-skew
printf '  - id: bad\n    kind: skill\n    target: polish\n    bogus: 1\n' >>"$inst/config/steps.yaml"
dispatch_print
label="a malformed core catalog entry"
refused "malformed entry 'bad' (at pre-implementation, pre-ci, convergence, pre-pr, post-pr); the planwright install at $inst is broken"
# A pinned root whose resolver predates the several-point check.
new_case
inst="$c/claude/plugins/cache/mk/planwright/0.0.1-old"
install_plugin_copy "$inst" 0.0.1-old
printf '#!/bin/sh\necho "usage: resolve-steps.sh <point>" >&2\nexit 2\n' >"$inst/scripts/resolve-steps.sh"
dispatch_print
label="a pinned root with an old resolver"
refused "update the planwright install at $inst"
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
