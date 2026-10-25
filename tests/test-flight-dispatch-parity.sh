#!/bin/bash
# shellcheck disable=SC2016 # backticks in the patterns are Markdown code spans
# Tests for degradation parity between a visual flight and a task unit
# (tower-front-door D-16 · REQ-C1.9): at every overlay layer the resolver's
# missing-step matrix distinguishes (core, repo-tracked, adopter,
# machine-local), each kind of broken step entry is held against the task
# unit's own oracle, /execute-task's pre-flight point check run as a task
# worker runs it. scripts/flight-dispatch.sh places the flight exactly where
# that check passes, skipping exactly the steps it skips, and refuses,
# placing nothing, exactly where it stops a task unit, naming the point and
# the step id whenever the check's diagnostics name one.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
unset CDPATH
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib/flight-dispatch-fixture.sh
. "$here/lib/flight-dispatch-fixture.sh"

SKILL="$ROOT/skills/execute-task/SKILL.md"
LAYERS='core repo-tracked adopter machine-local'

# preflight_points — the points /execute-task's pre-flight check names, read
# from the skill's check command.
preflight_points() {
  tr '\n' ' ' <"$SKILL" | tr -s ' ' \
    | sed -n 's/.*`scripts\/resolve-steps\.sh \([a-z -]*\) --explain --check --unattended`.*/\1/p'
}
POINTS=$(preflight_points)
# shellcheck disable=SC2086 # the point list is split on purpose
[ "$(printf '%s\n' $POINTS | grep -c .)" -ge 5 ] \
  || fail "fixture: the pre-flight check parse found too few points: '$POINTS'"

# parity_case — a fresh case with a runnable plugin copy under the plugin
# cache, which dispatch pins as the worker's root; INST names it.
parity_case() {
  new_case
  INST="$c/claude/plugins/cache/mk/planwright/0.0.1-parity"
  install_plugin_copy "$INST" 0.0.1-parity
  mkdir -p "$c/adopter/catalogs" "$c/primary/.claude/catalogs" "$c/primary/.claude/catalogs.local"
}

# list_file <layer> / catalog_file <layer> — where that layer's point lists
# and steps catalog live in the case.
list_file() {
  case $1 in
    core) printf '%s' "$INST/config/defaults.yml" ;;
    repo-tracked) printf '%s' "$c/primary/.claude/planwright.yml" ;;
    adopter) printf '%s' "$c/adopter/planwright.yml" ;;
    machine-local) printf '%s' "$c/primary/.claude/planwright.local.yml" ;;
  esac
}
catalog_file() {
  case $1 in
    core) printf '%s' "$INST/config/steps.yaml" ;;
    repo-tracked) printf '%s' "$c/primary/.claude/catalogs/steps.yaml" ;;
    adopter) printf '%s' "$c/adopter/catalogs/steps.yaml" ;;
    machine-local) printf '%s' "$c/primary/.claude/catalogs.local/steps.yaml" ;;
  esac
}

# set_list <layer> <key> <value> — the layer's list for <key>. The core
# defaults replace their own line; an overlay appends one.
set_list() {
  _lf=$(list_file "$1")
  if [ "$1" = core ]; then
    sed "s/^$2:.*/$2: $3/" "$_lf" >"$_lf.new" && mv "$_lf.new" "$_lf"
  else
    printf '%s: %s\n' "$2" "$3" >>"$_lf"
  fi
}

# add_entry <layer> <entry-text> — append a catalog entry at the layer.
add_entry() {
  _cf=$(catalog_file "$1")
  [ -s "$_cf" ] || printf 'steps:\n' >"$_cf"
  printf '%s' "$2" >>"$_cf"
}

# oracle — /execute-task's pre-flight point check as a task worker runs it:
# from the repository, its launch pinning the plugin root, unit kind task.
# Sets ORC_RC and ORC_OUT (the --explain rows) and ORC_ERR.
oracle() {
  # shellcheck disable=SC2086 # the point list is split on purpose
  ORC_OUT=$(cd "$c/primary" && unset PLANWRIGHT_SKILLS_ROOT PLANWRIGHT_CONFIG_DEFAULTS \
    && PLANWRIGHT_ROOT="$INST" CLAUDE_PLUGIN_ROOT="$INST" PLANWRIGHT_STEP_UNIT_KIND=task \
      bash "$INST/scripts/resolve-steps.sh" $POINTS --explain --check --unattended </dev/null 2>"$tmp/orc.err")
  ORC_RC=$?
  ORC_ERR=$(cat "$tmp/orc.err")
}

# oracle_skips / dispatch_skips — the `<point> <id>` pairs each side skipped.
oracle_skips() {
  printf '%s\n' "$ORC_OUT" | awk -F"$TAB" '$1 == "skip" { print $3 " " $2 }' | sort -u
}
dispatch_skips() {
  printf '%s\n' "$OUT" | awk -F"$TAB" '$1 == "skipped" { print $2 " " $3 }' | sort -u
}

# oracle_named — the `<point>: step '<id>'` pairs the check's diagnostics
# blame for stopping it (a park, ask, or refuse, or a step placed or dropped
# as malformed), one per point.
oracle_named() {
  printf '%s\n' "$ORC_ERR" | awk '
    /^resolve-steps: [a-z,-]+: (park|ask|refuse): step '\''[a-z0-9-]+'\''/ ||
    (/^resolve-steps: [a-z,-]+: skip: step '\''[a-z0-9-]+'\''/ && /dropped as malformed/) ||
    /^resolve-steps: [a-z,-]+: .*places '\''[a-z0-9-]+'\'' malformed/ {
      p = $0; sub(/^resolve-steps: /, "", p); sub(/: .*/, "", p)
      s = $0; match(s, /'\''[a-z0-9-]+'\''/); id = substr(s, RSTART, RLENGTH)
      n = split(p, pts, ",")
      for (i = 1; i <= n; i++) print pts[i] ": step " id
    }' | sort -u
}

# check_parity <label> — the dispatch just run against the oracle just run.
check_parity() {
  _label=$1
  _line=$(printf '%s\n' "$ERR" | grep '^flight-dispatch: ')
  if [ "$ORC_RC" -eq 0 ]; then
    if [ "$RC" -eq 0 ] && [ "$(flight_branches)" -eq 1 ]; then
      :
    else
      fail "$_label: the task unit's check passes (rc 0), so the flight must be placed (rc $RC: $ERR)"
      return
    fi
    [ "$(dispatch_skips)" = "$(oracle_skips)" ] \
      || fail "$_label: the flight must skip exactly what the task check skips; task '$(oracle_skips | tr '\n' ';')', flight '$(dispatch_skips | tr '\n' ';')'"
    _brief=$(field "$OUT" brief)
    for _pair in $(oracle_skips | tr ' ' ':'); do
      grep -qx -- "- \`${_pair%%:*}\`: \`${_pair#*:}\`" "$_brief" \
        || fail "$_label: the brief must name the skipped step ${_pair#*:} at ${_pair%%:*}"
    done
  else
    [ "$RC" -eq 4 ] || fail "$_label: the task unit's check stops (rc $ORC_RC), so dispatch must refuse with exit 4 (rc $RC: $ERR)"
    [ "$(flight_branches)" -eq 0 ] || fail "$_label: a flight was placed where the task check stops"
    [ "$(briefs)" -eq 0 ] || fail "$_label: a brief was left where the task check stops"
    case $_line in *"nothing was placed"*) ;; *) fail "$_label: the refusal must say nothing was placed: $ERR" ;; esac
    _named=$(oracle_named)
    printf '%s\n' "$_named" | while IFS= read -r _n; do
      [ -n "$_n" ] || continue
      case $_line in *"$_n"*) ;; *) echo "$_n" ;; esac
    done >"$tmp/unnamed"
    [ ! -s "$tmp/unnamed" ] \
      || fail "$_label: the refusal must name each point and step the task check blames, missing '$(tr '\n' ';' <"$tmp/unnamed")': $_line"
  fi
}

# expect <label> <placed|refused> — the case's expected outcome, so a
# parity that holds only because both sides broke the same way still fails.
expect() {
  case $2 in
    placed) [ "$ORC_RC" -eq 0 ] || fail "$1: the task unit's check must pass here (rc $ORC_RC): $ORC_ERR" ;;
    refused) [ "$ORC_RC" -ne 0 ] || fail "$1: the task unit's check must stop here" ;;
  esac
}

# run_case <label> <expected> — the oracle, then the dispatch, then parity.
run_case() {
  oracle
  expect "$1" "$2"
  dispatch_print
  check_parity "$1"
}

ghost_skill='  - id: ghost\n    kind: skill\n    target: no-such-skill\n'
bad_entry='  - id: bad\n    kind: skill\n    target: polish\n    bogus: 1\n'
for layer in $LAYERS; do
  # The matrix row: a list naming a step id no catalog defines.
  case $layer in
    core | repo-tracked) want=refused ;;
    *) want=placed ;;
  esac
  parity_case
  set_list "$layer" steps_pre_ci '[no-such-step]'
  run_case "$layer: a list naming an undefined step" "$want"

  # A malformed catalog entry the layer's list names.
  parity_case
  # shellcheck disable=SC2059 # the entry carries its own \n escapes
  add_entry "$layer" "$(printf "$bad_entry")
"
  set_list "$layer" steps_pre_pr '[bad]'
  run_case "$layer: a malformed entry its list names" refused

  # A malformed list value.
  parity_case
  set_list "$layer" steps_post_pr '[Bad_Id]'
  run_case "$layer: a malformed list" refused

  # A step no worker can run: a skill target that resolves to no file.
  parity_case
  # shellcheck disable=SC2059 # the entry carries its own \n escapes
  add_entry "$layer" "$(printf "$ghost_skill")
"
  set_list "$layer" steps_convergence '[polish, ghost]'
  run_case "$layer: an unresolvable skill target" refused
done

# Two layers at once: an adopter skip beside a machine-local skip both pass,
# and both are skipped on the flight as on the task unit.
parity_case
set_list adopter steps_pre_ci '[no-such-step]'
set_list machine-local steps_pre_pr '[other-missing]'
run_case "adopter and machine-local skips together" placed
[ "$(dispatch_skips | grep -c .)" -eq 2 ] \
  || fail "each layer's skip must be named at its own point; got '$(dispatch_skips | tr '\n' ';')'"

# The oracle checks itself: its parse finds a skip and a blamed step, so an
# empty comparison is not the parse failing silently.
parity_case
set_list machine-local steps_pre_ci '[no-such-step]'
oracle
[ "$(oracle_skips)" = "pre-ci no-such-step" ] || fail "self-check: the oracle's skip parse found '$(oracle_skips)'"
parity_case
set_list repo-tracked steps_pre_ci '[no-such-step]'
oracle
[ "$(oracle_named)" = "pre-ci: step 'no-such-step'" ] || fail "self-check: the oracle's blame parse found '$(oracle_named)'"

finish test-flight-dispatch-parity
