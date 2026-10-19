#!/bin/bash
# Tests for scripts/worker-command-guard.sh: declared command step lines
# (custom-steps REQ-G1.3), including one inside a command substitution
# (REQ-E1.3), and the bounded-runtime rows (REQ-B1.7).
# tests/test-worker-command-guard.sh holds the suite's overview; all its files
# source tests/lib/worker-command-guard-harness.sh, which states the contract.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"

echo "### custom-steps REQ-G1.3 — declared command step lines"
# A fixture overlay stack for scripts/resolve-steps.sh: a core root whose
# defaults leave every point empty, a repo-tracked layer declaring command
# steps and naming them from two points, and an adopter layer declaring a
# traversal target (malformed there, so dropped with a warning). The hook
# resolves these itself; nothing here tells it what is declared.
FX="$(cd "$SANDBOX" && pwd -P)/steps-fx"
mkdir -p "$FX/core/config" "$FX/adopter/catalogs" "$FX/repo/.claude/catalogs" \
  "$FX/repo/tools" "$FX/bin" "$FX/claude"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$FX/repo"
cp "$REPO_ROOT/config/steps.yaml" "$FX/core/config/steps.yaml"
{
  printf 'dispatch_isolation: per-unit\n'
  for p in pre-implementation pre-ci convergence pre-pr post-pr pre-ready-flip \
    pre-spec-ready-flip spec-drafted kickoff-signed-off unit-selected pre-dispatch \
    post-dispatch unit-halted post-merge orchestrator-idle; do
    printf 'steps_%s: []\n' "${p//-/_}"
  done
} >"$FX/core/config/defaults.yml"
for t in declared.sh other.sh undeclared.sh pooled.sh; do
  printf '#!/bin/sh\nexit 0\n' >"$FX/repo/tools/$t"
  chmod +x "$FX/repo/tools/$t"
done
printf '#!/bin/sh\nexit 0\n' >"$FX/bin/fixture-tool"
chmod +x "$FX/bin/fixture-tool"
DECLARED="$FX/repo/tools/declared.sh"
OTHER="$FX/repo/tools/other.sh"
POOLED="$FX/repo/tools/pooled.sh"
cat >"$FX/repo/.claude/catalogs/steps.yaml" <<YAML
steps:
  - id: declared
    kind: command
    target: $DECLARED
    args: --mode strict
  - id: bare
    kind: command
    target: fixture-tool
    args: --x
  - id: noargs
    kind: command
    target: $OTHER
  - id: unlisted
    kind: command
    target: $FX/repo/tools/undeclared.sh
    args: --mode strict
  - id: rel
    kind: command
    target: tools/declared.sh
    args: --rel
  - id: pooled
    kind: command
    target: $POOLED
    args: --mode strict
    pool: gate
  - id: reserved
    kind: command
    target: $FX/repo/tools/gh
YAML
printf 'steps_pre_ci: [declared, bare, rel, pooled]\nsteps_post_pr: [noargs]\n' >"$FX/repo/.claude/planwright.yml"
cat >"$FX/adopter/catalogs/steps.yaml" <<YAML
steps:
  - id: traversal
    kind: command
    target: $FX/repo/tools/../tools/declared.sh
    args: --mode strict
YAML
printf 'steps_pre_pr: [traversal]\n' >"$FX/adopter/planwright.yml"
# These functional rows lift the resolution deadline so a loaded host cannot
# turn an approval into a deferral; one row below and the bound rows keep the
# default.
FX_ENV=("PLANWRIGHT_ROOT=$FX/core" "CLAUDE_PLUGIN_ROOT=$FX/core"
  "PLANWRIGHT_CONFIG_DEFAULTS=$FX/core/config/defaults.yml"
  "PLANWRIGHT_ADOPTER_OVERLAY=$FX/adopter" "PLANWRIGHT_REPO_ROOT=$FX/repo"
  "PLANWRIGHT_LOCAL_CONFIG=" "CLAUDE_DIR=$FX/claude" "PATH=$FX/bin:$PATH")
HOOK_ENV=("${FX_ENV[@]}" "PLANWRIGHT_GUARD_STEPS_DEADLINE=60")
FXC="$FX/repo"
# The runner's own spelling: the context prefix, then the location and args,
# each single-quoted, exactly as resolve-steps.sh --line renders it.
RUNNER_LINE="$(env PLANWRIGHT_STEP_SPEC=custom-steps PLANWRIGHT_STEP_TASK_IDS=7 \
  PLANWRIGHT_STEP_UNIT_KIND=task PLANWRIGHT_STEP_BRANCH=planwright/custom-steps/task-7 \
  PLANWRIGHT_STEP_BASE_BRANCH=main PLANWRIGHT_STEP_WORKTREE="$FXC" PLANWRIGHT_STEP_PR_NUMBER= \
  PLANWRIGHT_STEP_ID=declared PLANWRIGHT_STEP_PREV_RECORD= \
  /bin/bash "$REPO_ROOT/scripts/resolve-steps.sh" pre-ci --line "$DECLARED" --mode strict)"
assert_allow "declared line approved" "$DECLARED --mode strict" Bash "$FXC"
assert_allow "declared line with the context assignments prefixed approved" "$RUNNER_LINE" Bash "$FXC"
assert_allow "word-identical respelling approved" "'$DECLARED' \"--mode\" strict" Bash "$FXC"
assert_allow "bare target's resolved location approved" "$FX/bin/fixture-tool --x" Bash "$FXC"
assert_allow "declared line with no args approved" "$OTHER" Bash "$FXC"
assert_allow "declared line chained with a known-safe segment approved" \
  "$DECLARED --mode strict && git status" Bash "$FXC"
# The declarations resolve from the payload cwd, so after a `cd` a declared
# line's relative args would name other files than the ones declared.
# Regression-only here: this catalog's relative step already fails to resolve
# from the subdirectory.
assert_defer "REQ-A1.12: a declared line after a cd defers" "cd tools && $DECLARED --mode strict" Bash "$FXC"
assert_defer "bare target instead of its resolved location deferred" "fixture-tool --x" Bash "$FXC"
assert_defer "segment sharing only the first word deferred" "$DECLARED --mode lax" Bash "$FXC"
assert_defer "declared line plus an extra arg deferred" "$DECLARED --mode strict --extra" Bash "$FXC"
assert_defer "declared location without its args deferred" "$DECLARED" Bash "$FXC"
assert_defer "declared no-args line given an arg deferred" "$OTHER extra" Bash "$FXC"
assert_defer "non-declared command deferred" "$FX/repo/tools/undeclared.sh --mode strict" Bash "$FXC"
assert_defer "path target with a traversal segment deferred" \
  "$FX/repo/tools/../tools/declared.sh --mode strict" Bash "$FXC"
assert_defer "declared line chained with an unsafe segment deferred" \
  "$DECLARED --mode strict; rm -rf x" Bash "$FXC"
assert_defer "declared line with a write redirect deferred" "$DECLARED --mode strict > out" Bash "$FXC"
assert_defer "declared line behind a non-context assignment deferred" \
  "LD_PRELOAD=/x.so $DECLARED --mode strict" Bash "$FXC"
assert_defer "declared line behind a context assignment carrying an expansion deferred" \
  "PLANWRIGHT_STEP_SPEC=\"\$HOME\" $DECLARED --mode strict" Bash "$FXC"
assert_defer "declared line behind a quoted-name assignment deferred" \
  "'PLANWRIGHT_STEP_SPEC=x' $DECLARED --mode strict" Bash "$FXC"
assert_defer "declared words split across a quoted word deferred" "'$DECLARED --mode' strict" Bash "$FXC"
assert_defer "declared line behind a context assignment carrying a backtick substitution deferred" \
  "PLANWRIGHT_STEP_SPEC=\`id\` $DECLARED --mode strict" Bash "$FXC"
assert_defer "declared line behind an unknown PLANWRIGHT_STEP_ name deferred" \
  "PLANWRIGHT_STEP_OTHER=x $DECLARED --mode strict" Bash "$FXC"
assert_defer "declared line followed by an unsafe command on the next line deferred" \
  "$DECLARED --mode strict
rm -rf x" Bash "$FXC"
assert_defer "declared line with a glob in an arg deferred" "$DECLARED --mode stric*" Bash "$FXC"
case $RUNNER_LINE in
  "PLANWRIGHT_STEP_SPEC='custom-steps' "*) pass "the runner's line carries the context prefix" ;;
  *) fail "the runner's line lost its context prefix: $RUNNER_LINE" ;;
esac
# ctx_prefix <unit-kind> <task-ids> <pr> <point> [<prev-head> <new-head>]: the
# twelve context assignments in the resolver's order, with the given values
# for the validated fields.
ctx_prefix() {
  printf "PLANWRIGHT_STEP_SPEC='s' PLANWRIGHT_STEP_TASK_IDS='%s' PLANWRIGHT_STEP_UNIT_KIND='%s' PLANWRIGHT_STEP_BRANCH='b' PLANWRIGHT_STEP_BASE_BRANCH='main' PLANWRIGHT_STEP_WORKTREE='%s' PLANWRIGHT_STEP_PR_NUMBER='%s' PLANWRIGHT_STEP_POINT='%s' PLANWRIGHT_STEP_ID='declared' PLANWRIGHT_STEP_PREV_RECORD='' PLANWRIGHT_STEP_PREV_HEAD='%s' PLANWRIGHT_STEP_NEW_HEAD='%s'" \
    "$2" "$1" "$FXC" "$3" "$4" "${5:-}" "${6:-}"
}
assert_allow "hand-written full context prefix approved" \
  "$(ctx_prefix task '7 8.1' 12 pre-ci) $DECLARED --mode strict" Bash "$FXC"
assert_allow "full context prefix with double-quoted and bare values approved" \
  "PLANWRIGHT_STEP_SPEC=\"s\" PLANWRIGHT_STEP_TASK_IDS= PLANWRIGHT_STEP_UNIT_KIND= PLANWRIGHT_STEP_BRANCH=b PLANWRIGHT_STEP_BASE_BRANCH=main PLANWRIGHT_STEP_WORKTREE=/w PLANWRIGHT_STEP_PR_NUMBER= PLANWRIGHT_STEP_POINT=pre-ci PLANWRIGHT_STEP_ID=x PLANWRIGHT_STEP_PREV_RECORD= PLANWRIGHT_STEP_PREV_HEAD= PLANWRIGHT_STEP_NEW_HEAD= $DECLARED --mode strict" Bash "$FXC"
# The head fields carry a full commit id (40 or 64 lowercase hex) or nothing.
H40=0123456789abcdef0123456789abcdef01234567
H64=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
assert_allow "a context prefix carrying both head fields approved" \
  "$(ctx_prefix task 7 12 post-pr "$H40" "$H64") $DECLARED --mode strict" Bash "$FXC"
assert_defer "a context prefix with a short head deferred" \
  "$(ctx_prefix task 7 12 post-pr "${H40%?}" "$H40") $DECLARED --mode strict" Bash "$FXC"
assert_defer "a context prefix with an uppercase head deferred" \
  "$(ctx_prefix task 7 12 post-pr "$H40" "$(printf '%s' "$H40" | tr a-f A-F)") $DECLARED --mode strict" Bash "$FXC"
assert_defer "a context prefix with a non-hex head deferred" \
  "$(ctx_prefix task 7 12 post-pr "$(printf 'g%.0s' $(seq 1 40))" '') $DECLARED --mode strict" Bash "$FXC"
assert_defer "the ten-field prefix without the head fields deferred" \
  "$(ctx_prefix task 7 12 pre-ci | sed "s/ PLANWRIGHT_STEP_PREV_HEAD='' PLANWRIGHT_STEP_NEW_HEAD=''//") $DECLARED --mode strict" Bash "$FXC"
# The hold mark: one optional trailing assignment after the twelve, as the
# resolver renders it for a pooled step, and only for the pool that step
# declares.
POOLED_LINE="$(env PLANWRIGHT_STEP_SPEC=custom-steps PLANWRIGHT_STEP_TASK_IDS=7 \
  PLANWRIGHT_STEP_UNIT_KIND=task PLANWRIGHT_STEP_BRANCH=planwright/custom-steps/task-7 \
  PLANWRIGHT_STEP_BASE_BRANCH=main PLANWRIGHT_STEP_WORKTREE="$FXC" PLANWRIGHT_STEP_PR_NUMBER= \
  PLANWRIGHT_STEP_ID=pooled PLANWRIGHT_STEP_PREV_RECORD= PLANWRIGHT_STEP_PREV_HEAD= PLANWRIGHT_STEP_NEW_HEAD= \
  /bin/bash "$REPO_ROOT/scripts/resolve-steps.sh" pre-ci --pool gate --owner 4242 --line "$POOLED" --mode strict)"
case $POOLED_LINE in
  *" PLANWRIGHT_STEP_POOL_HOLD='gate:4242' '$POOLED' "*) pass "the runner's pooled line carries the hold mark before the location" ;;
  *) fail "the runner's pooled line lost its hold mark: $POOLED_LINE" ;;
esac
assert_allow "REQ-I1.2: a pooled step's line under the twelve-field prefix and its pool's hold mark approved" "$POOLED_LINE" Bash "$FXC"
assert_allow "REQ-I1.2: a hand-written prefix with an unquoted mark naming the step's pool approved" \
  "$(ctx_prefix task 7 '' pre-ci) PLANWRIGHT_STEP_POOL_HOLD=gate:1 $POOLED --mode strict" Bash "$FXC"
assert_allow "REQ-I1.2: a pooled step's line without a mark approved" \
  "$(ctx_prefix task 7 '' pre-ci) $POOLED --mode strict" Bash "$FXC"
assert_defer "REQ-I1.2: a mark naming another pool than the step's deferred" \
  "$(ctx_prefix task 7 '' pre-ci) PLANWRIGHT_STEP_POOL_HOLD=host-gate:1 $POOLED --mode strict" Bash "$FXC"
assert_defer "REQ-I1.2: a mark on a step that declares no pool deferred" \
  "$(ctx_prefix task 7 '' pre-ci) PLANWRIGHT_STEP_POOL_HOLD=gate:1 $DECLARED --mode strict" Bash "$FXC"
# shellcheck disable=SC2016 # the last mark carries a literal, unexpanded $PPID
for m in 'gate:abc' 'Gate:12' 'gate:' ':12' 'gate:0' 'gate:012' 'gate' 'gate:1:2' 'ga.te:12' 'gate:12345678901' 'gate:$PPID'; do
  assert_defer "REQ-I1.2: a hold mark '$m' deferred" \
    "$(ctx_prefix task 7 '' pre-ci) PLANWRIGHT_STEP_POOL_HOLD='$m' $POOLED --mode strict" Bash "$FXC"
done
assert_defer "a hold mark before the twelve fields deferred" \
  "PLANWRIGHT_STEP_POOL_HOLD=gate:12 $(ctx_prefix task 7 '' pre-ci) $POOLED --mode strict" Bash "$FXC"
assert_defer "a hold mark with no context prefix deferred" \
  "PLANWRIGHT_STEP_POOL_HOLD=gate:12 $POOLED --mode strict" Bash "$FXC"
assert_defer "two hold marks deferred" \
  "$(ctx_prefix task 7 '' pre-ci) PLANWRIGHT_STEP_POOL_HOLD=gate:12 PLANWRIGHT_STEP_POOL_HOLD=gate:12 $POOLED --mode strict" Bash "$FXC"
assert_defer "a hold mark with the quote at the equals sign deferred" \
  "$(ctx_prefix task 7 '' pre-ci) PLANWRIGHT_STEP_POOL_HOLD\"=gate:12\" $POOLED --mode strict" Bash "$FXC"
assert_defer "a partial context prefix deferred" \
  "PLANWRIGHT_STEP_SPEC=x $DECLARED --mode strict" Bash "$FXC"
assert_defer "a reordered context prefix deferred" \
  "$(ctx_prefix task 7 '' pre-ci | sed 's/^\(PLANWRIGHT_STEP_SPEC=[^ ]*\) \(PLANWRIGHT_STEP_TASK_IDS=[^ ]*\)/\2 \1/') $DECLARED --mode strict" Bash "$FXC"
assert_defer "a context prefix with a repeated name deferred" \
  "PLANWRIGHT_STEP_SPEC=x $(ctx_prefix task 7 '' pre-ci) $DECLARED --mode strict" Bash "$FXC"
assert_defer "a context prefix with a unit kind the resolver refuses deferred" \
  "$(ctx_prefix bogus 7 '' pre-ci) $DECLARED --mode strict" Bash "$FXC"
assert_defer "a context prefix with task ids outside the grammar deferred" \
  "$(ctx_prefix task '7..1' '' pre-ci) $DECLARED --mode strict" Bash "$FXC"
# The hook's own directory holds a file the glob would match.
mkdir -p "$FX/globdir"
: >"$FX/globdir/7.1"
fx_pwd=$PWD
cd "$FX/globdir" || exit 1
assert_defer "a context prefix with task ids carrying a glob deferred" \
  "$(ctx_prefix task '7*' '' pre-ci) $DECLARED --mode strict" Bash "$FXC"
cd "$fx_pwd" || exit 1
assert_defer "a context prefix with a non-numeric PR number deferred" \
  "$(ctx_prefix task 7 12a pre-ci) $DECLARED --mode strict" Bash "$FXC"
assert_defer "a context prefix naming two points deferred" \
  "$(ctx_prefix task 7 '' 'pre-ci convergence') $DECLARED --mode strict" Bash "$FXC"
assert_defer "a context prefix naming an unwired point deferred" \
  "$(ctx_prefix task 7 '' post-merge) $DECLARED --mode strict" Bash "$FXC"
assert_defer "a context prefix value carrying a control byte deferred" \
  "$(ctx_prefix task 7 '' pre-ci | sed "s/BRANCH='b'/BRANCH='b$(printf '\001')'/") $DECLARED --mode strict" Bash "$FXC"
assert_defer "a context prefix with the quote at the equals sign deferred" \
  "$(ctx_prefix task 7 '' pre-ci | sed "s/PLANWRIGHT_STEP_SPEC='s'/PLANWRIGHT_STEP_SPEC\"=s\"/") $DECLARED --mode strict" Bash "$FXC"
assert_defer "a context prefix with no command deferred" "$(ctx_prefix task 7 '' pre-ci)" Bash "$FXC"
assert_allow "relative target's location, joined to the working directory, approved" \
  "$FXC/tools/declared.sh --rel" Bash "$FXC"
assert_defer "relative target's location from another working directory deferred" \
  "$FXC/tools/declared.sh --rel" Bash "$FXC/tools"
assert_allow "declared line inside fish -c approved" "fish -c '$DECLARED --mode strict'" Bash "$FXC"
assert_defer "changed declared line inside fish -c deferred" "fish -c '$DECLARED --mode lax'" Bash "$FXC"
HOOK_ENV=()
assert_defer "declared line with no declaring overlay deferred" "$DECLARED --mode strict" Bash "$FXC"

# The guard's own location checks, independent of what the resolver refuses:
# a copy of the hook beside a stub resolver that prints the location given,
# with the overlay-root helpers the guard's catalog check runs.
stub_scripts() {
  mkdir -p "$1/scripts" "$1/config"
  cp "$REAL_HOOK" "$1/scripts/worker-command-guard.sh"
  cp "$REPO_ROOT/config/worker-settings.json" "$1/config/"
  cp "$REPO_ROOT/scripts/resolve-overlay-root.sh" "$REPO_ROOT/scripts/resolve-root.sh" "$1/scripts/"
}
stub_root() {
  local root=$1 location=$2 target=$3
  stub_scripts "$root"
  cat >"$root/scripts/resolve-steps.sh" <<STUB
#!/bin/bash
case " \$* " in *" pre-ci "*) ;; *) exit 0 ;; esac
printf 'run\tx\tpre-ci\trepo-tracked\trepo-tracked\t%s\tin-session\tcommand\t-\thalt\t-\t-\t%s\t-\t-\t-\n' '$target' '$location'
STUB
}
REAL_HOOK=$HOOK
stub_root "$FX/stub-ok" "$DECLARED" "$DECLARED"
HOOK="$FX/stub-ok/scripts/worker-command-guard.sh"
HOOK_ENV=("${FX_ENV[@]}" "PLANWRIGHT_GUARD_STEPS_DEADLINE=60")
assert_allow "stub: a clean printed location approved" "$DECLARED" Bash "$FXC"
# A leading zero reads as decimal, not as an octal operand that aborts the hook.
HOOK_ENV=("${FX_ENV[@]}" "PLANWRIGHT_GUARD_STEPS_DEADLINE=09")
assert_allow "stub: a zero-led deadline override reads as decimal" "$DECLARED" Bash "$FXC"
HOOK_ENV=("${FX_ENV[@]}" "PLANWRIGHT_GUARD_STEPS_DEADLINE=60")
# A declared line a deny rule of the profile matches is refused before the
# declared steps are consulted (REQ-A1.11): the floor holds for every category.
stub_root "$FX/stub-denied" "$DECLARED" "$DECLARED"
jq --arg r "Bash($DECLARED:*)" '.permissions.deny += [$r]' "$REPO_ROOT/config/worker-settings.json" \
  >"$FX/stub-denied/config/worker-settings.json"
HOOK="$FX/stub-denied/scripts/worker-command-guard.sh"
assert_defer "REQ-A1.11: a declared line a deny rule matches deferred" "$DECLARED" Bash "$FXC"
# And a declared line that is a reserved act defers, the program named by
# absolute path as a declared step names it (REQ-F1.5); the read-only form
# of the same program still approves, so the refusal is the floor's.
cp "$DECLARED" "$FX/repo/tools/gh"
stub_reserved() {
  stub_scripts "$1"
  cat >"$1/scripts/resolve-steps.sh" <<STUB
#!/bin/bash
case " \$* " in *" pre-ci "*) ;; *) exit 0 ;; esac
printf 'run\tx\tpre-ci\trepo-tracked\trepo-tracked\t%s\tin-session\tcommand\t%s\thalt\t-\t-\t%s\t-\t-\t-\n' '$FX/repo/tools/gh' '$2' '$FX/repo/tools/gh'
STUB
  HOOK="$1/scripts/worker-command-guard.sh"
}
stub_reserved "$FX/stub-reserved" "pr merge 5"
assert_defer "REQ-F1.5: a declared line that is a reserved act deferred" "$FX/repo/tools/gh pr merge 5" Bash "$FXC"
stub_reserved "$FX/stub-reserved-ro" "pr view 5"
assert_allow "REQ-F1.5: the same program's read-only declared line approved" "$FX/repo/tools/gh pr view 5" Bash "$FXC"
stub_root "$FX/stub-dotdot" "$FX/repo/tools/../tools/declared.sh" "$FX/repo/tools/../tools/declared.sh"
HOOK="$FX/stub-dotdot/scripts/worker-command-guard.sh"
assert_defer "stub: a printed path location with a traversal segment deferred" \
  "$FX/repo/tools/../tools/declared.sh" Bash "$FXC"
stub_root "$FX/stub-dot" "$FX/repo/tools/./declared.sh" "$FX/repo/tools/./declared.sh"
HOOK="$FX/stub-dot/scripts/worker-command-guard.sh"
assert_defer "stub: a printed path location with a dot segment deferred" \
  "$FX/repo/tools/./declared.sh" Bash "$FXC"
cp "$DECLARED" "$FX/repo/tools/til~de.sh"
stub_root "$FX/stub-charset" "$FX/repo/tools/til~de.sh" "$FX/repo/tools/til~de.sh"
HOOK="$FX/stub-charset/scripts/worker-command-guard.sh"
assert_defer "stub: a segment outside the location charset deferred" \
  "'$FX/repo/tools/til~de.sh'" Bash "$FXC"
stub_root "$FX/stub-missing" "$FX/repo/nodir/declared.sh" "$FX/repo/nodir/declared.sh"
HOOK="$FX/stub-missing/scripts/worker-command-guard.sh"
assert_defer "stub: a printed path location that does not canonicalize deferred" \
  "$FX/repo/nodir/declared.sh" Bash "$FXC"
stub_root "$FX/stub-relative" "tools/declared.sh" "tools/declared.sh"
HOOK="$FX/stub-relative/scripts/worker-command-guard.sh"
assert_defer "stub: a segment whose first word is not absolute deferred" "tools/declared.sh" Bash "$FXC"

# stub_line <root> <decision> <kind> <exit>: a stub resolver printing one
# pre-ci line for $DECLARED with the given decision and kind, then exiting
# with <exit>, and recording each call's arguments in <root>/calls.
stub_line() {
  local root=$1 dec=$2 kind=$3 rc=$4
  stub_scripts "$root"
  cat >"$root/scripts/resolve-steps.sh" <<STUB
#!/bin/bash
echo "\$*" >>'$root/calls'
case " \$* " in *" pre-ci "*) ;; *) exit 0 ;; esac
printf '%s\tx\tpre-ci\trepo-tracked\trepo-tracked\t%s\tin-session\t%s\t-\thalt\t-\t-\t%s\tgate\t. tests\tpost-pr\n' '$dec' '$DECLARED' '$kind' '$DECLARED'
exit $rc
STUB
  HOOK="$root/scripts/worker-command-guard.sh"
}
stub_line "$FX/stub-run" run command 0
assert_allow "stub: a run command line approved" "$DECLARED" Bash "$FXC"
for d in skip park ask; do
  stub_line "$FX/stub-$d" "$d" command 0
  assert_defer "stub: a $d decision deferred" "$DECLARED" Bash "$FXC"
done
# One run covers every point, so a park at another point exits non-zero
# without touching this point's run row.
stub_line "$FX/stub-rc" run command 1
assert_allow "stub: a run row from a run another point parked approved" "$DECLARED" Bash "$FXC"
stub_line "$FX/stub-skill" run skill 0
assert_defer "stub: a skill step's location deferred" "$DECLARED" Bash "$FXC"
stub_line "$FX/stub-calls" run command 0
assert_allow "stub: a known-safe segment approved" "git status" Bash "$FXC"
assert_defer "stub: a segment without a declared line's shape deferred" "foo bar" Bash "$FXC"
printf '#!/bin/sh\nexit 0\n' >"$FX/bin/zz-uncataloged"
chmod +x "$FX/bin/zz-uncataloged"
assert_defer "stub: a declared line's shape whose file name no catalog carries deferred" \
  "$FX/bin/zz-uncataloged --mode strict" Bash "$FXC"
# The catalog check matches a target's last path component, not any text.
for t in clared.sh unlisted; do
  printf '#!/bin/sh\nexit 0\n' >"$FX/bin/$t"
  chmod +x "$FX/bin/$t"
done
assert_defer "stub: a file name found only inside a cataloged target's name deferred" \
  "$FX/bin/clared.sh --mode strict" Bash "$FXC"
assert_defer "stub: a file name found only as a catalog id deferred" "$FX/bin/unlisted" Bash "$FXC"
if [ -e "$FX/stub-calls/calls" ]; then
  fail "the resolver ran for a known-safe, non-declared-shape, or uncataloged segment"
else
  pass "the resolver never runs for a known-safe, non-declared-shape, or uncataloged segment"
fi
assert_allow "stub: two declared segments approved" "$DECLARED && $DECLARED" Bash "$FXC"
step_points=$(sed -n "s/^readonly STEP_POINTS='\(.*\)'\$/\1/p" "$REAL_HOOK")
wired_points=$(sed -n 's/^WIRED_POINTS="\(.*\)"$/\1/p' "$REPO_ROOT/scripts/resolve-steps.sh")
# The catalog check's per-layer files, in core, adopter, repo-tracked,
# machine-local order, are the ones resolve-catalog.sh reads.
# shellcheck disable=SC2016 # the pattern matches a literal $name
want_rels=$(sed -n -E 's/^(core|adopter|repo|local)_rel="(.*)\$name\.yaml"$/\2steps.yaml/p' "$REPO_ROOT/scripts/resolve-catalog.sh")
got_rels=$(sed -n 's/.*files\[\${#files\[@\]}\]=\$r\/\(.*steps\.yaml\)$/\1/p' "$REAL_HOOK")
[ "$(printf '%s\n' "$want_rels" | grep -c .)" = 4 ] && [ "$got_rels" = "$want_rels" ] \
  || fail "the guard's catalog files ('$(printf '%s' "$got_rels" | tr '\n' ' ')') differ from resolve-catalog.sh's ('$(printf '%s' "$want_rels" | tr '\n' ' ')')"
[ -n "$step_points" ] && [ "$step_points" = "$wired_points" ] \
  || fail "the guard's STEP_POINTS ('$step_points') differ from resolve-steps.sh's WIRED_POINTS ('$wired_points')"
if [ -n "$step_points" ] && [ "$(cat "$FX/stub-calls/calls")" = "$step_points --explain --unattended" ]; then
  pass "the resolver runs once per hook call, over every wired point"
else
  fail "the resolver calls in one hook call: $(tr '\n' '|' <"$FX/stub-calls/calls")"
fi
# The catalog check finds a target in the core, adopter, and machine-local
# files, quoted or not, and reads a `.` in the name as itself.
cp "$FX/adopter/catalogs/steps.yaml" "$FX/adopter-steps.saved"
mkdir -p "$FX/repo/.claude/catalogs.local"
for t in core-tool adopter-tool local-tool quoted-tool dot.name; do
  printf '#!/bin/sh\nexit 0\n' >"$FX/bin/$t"
  chmod +x "$FX/bin/$t"
done
printf '  - id: adopter-only\n    kind: command\n    target: %s\n' "$FX/bin/adopter-tool" >>"$FX/adopter/catalogs/steps.yaml"
printf 'steps:\n  - id: local-only\n    kind: command\n    target: %s\n  - id: quoted\n    kind: command\n    target: "%s"\n  - id: dotted\n    kind: command\n    target: %s\n' \
  "$FX/bin/local-tool" "$FX/bin/quoted-tool" "$FX/bin/dotXname" >"$FX/repo/.claude/catalogs.local/steps.yaml"
for t in core-tool adopter-tool local-tool quoted-tool; do
  stub_line "$FX/stub-hit-$t" run command 0
  # The fixture's core arms hold no doctrine/ or scripts/, so the core root
  # is the stub's own install.
  if [ "$t" = core-tool ]; then
    mkdir -p "$FX/stub-hit-$t/config"
    printf 'steps:\n  - id: core-only\n    kind: command\n    target: %s\n' "$FX/bin/core-tool" >"$FX/stub-hit-$t/config/steps.yaml"
  fi
  run_hook "$FX/bin/$t" Bash "$FXC"
  check_invariants "the catalog check finds $t's target" || continue
  if [ -s "$FX/stub-hit-$t/calls" ]; then
    pass "the catalog check finds $t's target"
  else
    fail "the catalog check missed $t's target"
  fi
done
stub_line "$FX/stub-dot-name" run command 0
assert_defer "stub: a file name matching a cataloged one only through a regex dot deferred" \
  "$FX/bin/dot.name" Bash "$FXC"
if [ -e "$FX/stub-dot-name/calls" ]; then
  fail "the catalog check read a dot in the name as a regex operator"
else
  pass "the catalog check reads a dot in the name as itself"
fi
rm -f "$FX/repo/.claude/catalogs.local/steps.yaml"
rmdir "$FX/repo/.claude/catalogs.local"
mv "$FX/adopter-steps.saved" "$FX/adopter/catalogs/steps.yaml"
HOOK=$REAL_HOOK
# A declared step is a command like any other inside a substitution (REQ-E1.3).
HOOK_ENV=("${FX_ENV[@]}" "PLANWRIGHT_GUARD_STEPS_DEADLINE=60")
assert_defer "REQ-E1.3: a declared step inside a substitution" "echo \$($DECLARED --mode strict)" Bash "$FXC"
HOOK_ENV=()

# At the default deadline, on the host running the suite, the resolution of
# every wired point fits: a declared line is approved with no override.
# A loaded runner gets one retry; a resolution that never fits still fails.
HOOK_ENV=("${FX_ENV[@]}")
run_hook "$DECLARED --mode strict" Bash "$FXC"
is_allow || run_hook "$DECLARED --mode strict" Bash "$FXC"
if ! check_invariants "declared line approved within the default deadline"; then
  :
elif is_allow; then
  pass "declared line approved within the default deadline"
else
  fail "declared line approved within the default deadline — expected ALLOW on one of two tries, got defer"
fi
HOOK_ENV=()

echo "### REQ-B1.7 — bounded runtime on pathological input"
big="$(head -c 200000 /dev/zero | tr '\0' 'a')"
run_hook "echo $big"
if [ "$CODE" -eq 0 ]; then pass "pathological large input terminates with exit 0"; else fail "pathological input — exit $CODE (expected 0)"; fi
# A command past MAX_CMD_LEN (8 KiB) defers WITHOUT spending O(n^2) tokenizer
# time on it — the length cap short-circuits before tokenizing. Assert it both
# defers and returns quickly (well under the multi-second hang the high cap
# allowed).
over="$(head -c 20000 /dev/zero | tr '\0' 'a')"
# Bash's SECONDS is monotonic within the shell and needs no external `date`.
SECONDS=0
run_hook "echo $over"
elapsed=$SECONDS
if [ "$CODE" -eq 0 ] && is_empty && [ "$elapsed" -le 2 ]; then
  pass "over-cap command defers quickly (length short-circuit)"
else
  fail "over-cap command — code=$CODE empty=$(is_empty && echo y || echo n) secs=$elapsed"
fi
# defers_quickly <label> <command>: the command defers within the scan
# budget's time bound. A loaded host gets one retry, as the declared-line
# deadline row does; a command that outruns the bound twice still fails.
defers_quickly() {
  local label=$1 try elapsed=0
  for try in 1 2; do
    SECONDS=0
    run_hook "$2"
    elapsed=$SECONDS
    [ "$CODE" -eq 0 ] && is_empty && [ "$elapsed" -le 8 ] && break
  done
  if [ "$CODE" -eq 0 ] && is_empty && [ "$elapsed" -le 8 ]; then
    pass "$label"
  else
    fail "$label — code=$CODE empty=$(is_empty && echo y || echo n) secs=$elapsed (tries=$try)"
  fi
}
# A loop re-walks its body once per head word, so a long word in the body (a
# command substitution's text, or plain words) multiplies the walk: the scan
# budget defers such a command quickly instead of outrunning the hook timeout.
long_words="$(for i in $(seq 1150); do printf 'ab%d ' "$i"; done)"
defers_quickly "a subst loop over long words defers quickly (scan budget)" \
  "for f in $(seq -s ' ' 16); do echo \$(echo $long_words); done"
defers_quickly "a nested loop over long words defers quickly (scan budget)" \
  "for a in $(seq -s ' ' 7); do for b in $(seq -s ' ' 8); do echo \$(echo $long_words); done; done"
defers_quickly "a plain loop over long words defers quickly (scan budget)" \
  "for f in $(seq -s ' ' 16); do echo $long_words; done"
assert_allow "one long command substitution still allows within the scan budget" "echo \$(echo $long_words)"
# The budget leaves room for an ordinary loop: sixteen passes over a body of
# about a hundred and fifty pattern words.
mid_words="$(for i in $(seq 150); do printf 'p%d ' "$i"; done)"
assert_allow "a sixteen-pass loop over an ordinary body stays within the scan budget" \
  "for f in $(seq -s ' ' 16); do grep -n x $mid_words; done"
# Each `$` costs a pass over the rest of its word, so a word dense with them
# is charged for that and defers before the per-`$` work runs.
# shellcheck disable=SC2016 # a literal `$a`, the shape under test
dense_word="$(for i in $(seq 4050); do printf '$a'; done)"
defers_quickly "a plain word dense with \$ defers quickly (scan budget)" "echo \"$dense_word\""
defers_quickly "a subst word dense with \$ defers quickly (scan budget)" "echo \$(git log -1) \"$dense_word\""
# The same bound with the fixture catalog present: the declared steps are
# consulted only for a segment not already known-safe, and an over-cap
# command never reaches a segment.
HOOK_ENV=("${FX_ENV[@]}")
SECONDS=0
run_hook "echo $over" Bash "$FXC"
elapsed=$SECONDS
if [ "$CODE" -eq 0 ] && is_empty && [ "$elapsed" -le 2 ]; then
  pass "over-cap command defers quickly with a declaring catalog present"
else
  fail "over-cap command with a declaring catalog — code=$CODE empty=$(is_empty && echo y || echo n) secs=$elapsed"
fi
HOOK_ENV=()
# A resolver that never returns cannot hold the hook past its resolution
# deadline: the segment defers once the default deadline passes, and the
# resolver and the child it started are killed with their process group.
REAL_HOOK=$HOOK
stub_scripts "$FX/stub-slow"
cat >"$FX/stub-slow/scripts/resolve-steps.sh" <<STUB
#!/bin/bash
echo \$\$ >'$FX/stub-slow/self'
sleep 30 &
echo \$! >'$FX/stub-slow/child'
wait
STUB
HOOK="$FX/stub-slow/scripts/worker-command-guard.sh"
HOOK_ENV=("${FX_ENV[@]}")
SECONDS=0
run_hook "$DECLARED --mode strict" Bash "$FXC"
elapsed=$SECONDS
HOOK=$REAL_HOOK
HOOK_ENV=()
if [ "$CODE" -eq 0 ] && is_empty && [ -s "$FX/stub-slow/child" ] && [ "$elapsed" -ge 1 ] && [ "$elapsed" -le 4 ]; then
  pass "a resolver past the deadline defers within the bound"
else
  fail "slow resolver — code=$CODE empty=$(is_empty && echo y || echo n) secs=$elapsed"
fi
alive=''
for f in self child; do
  pid=$(cat "$FX/stub-slow/$f" 2>/dev/null) || continue
  n=0
  while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 20 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  ! kill -0 "$pid" 2>/dev/null || alive="$alive $f:$pid"
done
if [ -s "$FX/stub-slow/self" ] && [ -z "$alive" ]; then
  pass "a resolver past the deadline leaves no process of its group running"
else
  fail "slow resolver left processes running:$alive"
  for f in self child; do
    pid=$(cat "$FX/stub-slow/$f" 2>/dev/null) && kill "$pid" 2>/dev/null
  done
fi

# no_survivors <dir>: 0 when neither pid the stub in <dir> recorded is alive
# within a short grace.
# A missing pid file (the stub never ran) fails too, and every survivor is
# killed before returning, so none leaks into later rows.
no_survivors() {
  local f pid n rc=0
  for f in self child; do
    pid=$(cat "$1/$f" 2>/dev/null) || {
      rc=1
      continue
    }
    n=0
    while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 20 ]; do
      sleep 0.1
      n=$((n + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
      rc=1
    fi
  done
  return "$rc"
}
# A run that printed a declared line before overrunning contributes nothing.
stub_scripts "$FX/stub-partial"
cat >"$FX/stub-partial/scripts/resolve-steps.sh" <<STUB
#!/bin/bash
echo \$\$ >'$FX/stub-partial/self'
printf 'run\tx\tpre-ci\trepo-tracked\trepo-tracked\t%s\tin-session\tcommand\t--mode strict\thalt\t-\t-\t%s\t-\t-\t-\n' '$DECLARED' '$DECLARED'
sleep 30 &
echo \$! >'$FX/stub-partial/child'
wait
STUB
HOOK="$FX/stub-partial/scripts/worker-command-guard.sh"
HOOK_ENV=("${FX_ENV[@]}" "PLANWRIGHT_GUARD_STEPS_DEADLINE=2")
payload="$(jq -n --arg c "$DECLARED --mode strict" --arg w "$FXC" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}')"
OUT="$(printf '%s' "$payload" | env -u CLAUDE_DIR HOME="$SANDBOX/no-home" "${HOOK_ENV[@]}" /bin/bash "$HOOK" 2>"$FX/stub-partial/err")"
CODE=$?
if [ "$CODE" -eq 0 ] && is_empty && no_survivors "$FX/stub-partial" && [ ! -s "$FX/stub-partial/err" ]; then
  pass "a run that overran after printing a declared line defers, quietly, leaving nothing running"
else
  fail "partial overrun — code=$CODE empty=$(is_empty && echo y || echo n) err='$(cat "$FX/stub-partial/err")'"
fi
# A run that finishes but leaves a read it started still running takes that
# read with it and keeps its rows: the same row the overrun discarded
# approves here.
stub_scripts "$FX/stub-straggler"
cat >"$FX/stub-straggler/scripts/resolve-steps.sh" <<STUB
#!/bin/bash
echo \$\$ >'$FX/stub-straggler/self'
printf 'run\tx\tpre-ci\trepo-tracked\trepo-tracked\t%s\tin-session\tcommand\t--mode strict\thalt\t-\t-\t%s\t-\t-\t-\n' '$DECLARED' '$DECLARED'
sleep 30 </dev/null >/dev/null 2>&1 &
echo \$! >'$FX/stub-straggler/child'
exit 0
STUB
HOOK="$FX/stub-straggler/scripts/worker-command-guard.sh"
HOOK_ENV=("${FX_ENV[@]}" "PLANWRIGHT_GUARD_STEPS_DEADLINE=60")
run_hook "$DECLARED --mode strict" Bash "$FXC"
if [ "$CODE" -eq 0 ] && is_allow && no_survivors "$FX/stub-straggler"; then
  pass "a finished run keeps its rows and leaves no read it started running"
else
  fail "finished run: allow=$(is_allow && echo y || echo n), child=$(cat "$FX/stub-straggler/child" 2>/dev/null)"
fi
HOOK="$FX/stub-partial/scripts/worker-command-guard.sh"
# A hook signalled mid-resolution takes the run's whole group with it.
rm -f "$FX/stub-partial/self" "$FX/stub-partial/child"
HOOK_ENV=("${FX_ENV[@]}" "PLANWRIGHT_GUARD_STEPS_DEADLINE=60")
printf '%s' "$payload" | env -u CLAUDE_DIR HOME="$SANDBOX/no-home" "${HOOK_ENV[@]}" /bin/bash "$HOOK" >/dev/null 2>&1 &
hook_pid=$!
n=0
while [ ! -s "$FX/stub-partial/child" ] && [ "$n" -lt 100 ]; do
  sleep 0.1
  n=$((n + 1))
done
kill -TERM "$hook_pid" 2>/dev/null
wait "$hook_pid"
hook_rc=$?
if [ -s "$FX/stub-partial/child" ] && [ "$hook_rc" -eq 0 ] && no_survivors "$FX/stub-partial"; then
  pass "a hook terminated mid-resolution exits 0 and leaves nothing of the run running"
else
  fail "terminated hook — rc=$hook_rc child=$(cat "$FX/stub-partial/child" 2>/dev/null)"
fi
HOOK=$REAL_HOOK
HOOK_ENV=()

finish_suite worker-command-guard-steps
