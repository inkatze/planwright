#!/bin/sh
# Tests for what a launched session derives instead of needing hand exports:
# the adopter overlay location from the installed plugin (any shell, no
# CLAUDE_PLUGIN_DATA), and the step context from git (step-run.sh and
# step-record.sh with no PLANWRIGHT_STEP_* set), with a disagreeing exported
# value refused naming both. The per-call value overlays stay scrubbed by the
# launcher.
#
#   ./tests/test-session-derived-context.sh
# shellcheck disable=SC2319,SC2154 # verdicts judge the condition just before; the fixture sets wt and bin
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
umask 077

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
RUN="$repo_root/scripts/step-run.sh"
SR="$repo_root/scripts/step-record.sh"
SP="$repo_root/scripts/step-pool.sh"
TAB=$(printf '\t')
# shellcheck source=tests/lib/step-run-fixture.sh
. "$here/lib/step-run-fixture.sh"

# --- the adopter overlay is derived from the installed plugin -----------------------------
cdir="$tmp/cdir"
data="$cdir/plugins/data/planwright-mkt"
mkdir -p "$cdir/plugins/cache/mkt/planwright/1.0.0/scripts" "$data/overlay"
cat >"$data/overlay/planwright.yml" <<'EOF'
mission_control_programs: [gamma]
program_gamma_repositories: [~/work/gamma]
program_gamma_spec_root: ~/work/gamma/specs
EOF
bare() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT \
    -u PLANWRIGHT_REPO_ROOT_CHECKED -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS \
    -u PLANWRIGHT_CONFIG_STRICT_OVERLAYS -u PLANWRIGHT_ROOT \
    CLAUDE_DIR="$cdir" HOME="$tmp/home" "$@"
}
got=$(bare /bin/bash "$repo_root/scripts/resolve-overlay-root.sh" adopter)
[ "$got" = "$data/overlay" ]
verdict $? "with no CLAUDE_PLUGIN_DATA the adopter root is the installed plugin's data overlay" "got: $got"
got=$(bare PLANWRIGHT_ADOPTER_OVERLAY="$tmp/explicit" /bin/bash "$repo_root/scripts/resolve-overlay-root.sh" adopter)
[ "$got" = "$tmp/explicit" ]
verdict $? "an explicit adopter override still wins over the derived one" "got: $got"
got=$(bare CLAUDE_PLUGIN_DATA="$tmp/envdata" /bin/bash "$repo_root/scripts/resolve-overlay-root.sh" adopter)
[ "$got" = "$tmp/envdata/overlay" ]
verdict $? "an exported CLAUDE_PLUGIN_DATA still wins over the derived one" "got: $got"
rm -rf "$data/overlay"
got=$(bare /bin/bash "$repo_root/scripts/resolve-overlay-root.sh" adopter)
[ -z "$got" ]
verdict $? "a data directory with no overlay is not guessed at" "got: $got"
mkdir -p "$data/overlay"
cat >"$data/overlay/planwright.yml" <<'EOF'
mission_control_programs: [gamma]
program_gamma_repositories: [~/work/gamma]
program_gamma_spec_root: ~/work/gamma/specs
EOF
got=$(cd "$tmp" && bare PLANWRIGHT_REPO_ROOT=none /bin/bash "$repo_root/scripts/mc-program.sh" list 2>"$tmp/err")
[ "$got" = gamma ]
verdict $? "mc-program.sh lists the adopter-layer programs in a session with nothing exported" "got: $got err: $(cat "$tmp/err")"
got=$(cd "$tmp" && bare PLANWRIGHT_REPO_ROOT=none /bin/bash "$repo_root/scripts/config-get.sh" mission_control_programs 2>"$tmp/err")
case $got in *gamma*) ok "config-get.sh reads the adopter layer in a session with nothing exported" ;; *) fail "config-get got: $got err: $(cat "$tmp/err")" ;; esac

# The launcher hands on location variables and scrubs the per-call value overlays only.
scrub=$(sed -n "s/^  scrub='\(.*\)'\$/\1/p" "$repo_root/scripts/mission-control-launch.sh")
for v in PLANWRIGHT_LOCAL_CONFIG PLANWRIGHT_CONFIG_DEFAULTS PLANWRIGHT_ADOPTER_OVERLAY PLANWRIGHT_CONFIG_STRICT_OVERLAYS; do
  case $scrub in *"-u $v"*) ok "the launch scrub still removes $v" ;; *) fail "the launch scrub no longer removes $v: $scrub" ;; esac
done
case $scrub in *CLAUDE_PLUGIN_DATA* | *CLAUDE_PLUGIN_ROOT* | *PLANWRIGHT_REPO_ROOT*) fail "the launch scrub removes a location variable: $scrub" ;; *) ok "the launch scrub leaves the location variables alone" ;; esac

# --- the step context is derived from git when nothing is exported --------------------------
fresh
catalog "show|kind: command|target: $bin/show.sh"
config 'steps_pre_pr: [show]'
wtp=$(cd -P "$wt" && pwd -P)
bare_ctx() {
  env_run env -u PLANWRIGHT_STEP_SPEC -u PLANWRIGHT_STEP_TASK_IDS -u PLANWRIGHT_STEP_UNIT_KIND \
    -u PLANWRIGHT_STEP_BRANCH -u PLANWRIGHT_STEP_BASE_BRANCH -u PLANWRIGHT_STEP_WORKTREE \
    -u PLANWRIGHT_STEP_PR_NUMBER "$@"
}
hosted_show() { # hosted_show <run> [env assignments...]: resolve and host `show` with no context exported
  _r=$1
  shift
  rm -f "$tmp/show.show.env"
  bare_ctx env "$@" "$RUN" --worktree "$wt" resolve --run "$_r" pre-pr --unattended >"$tmp/rows" 2>"$tmp/err"
  bare_ctx env "$@" "$RUN" --worktree "$wt" command --run "$_r" --point pre-pr --step show >"$tmp/out" 2>>"$tmp/err"
  HRC=$?
}
r=$(sr new-run)
hosted_show "$r"
grep -qx "PLANWRIGHT_STEP_WORKTREE=$wtp" "$tmp/show.show.env" \
  && grep -qx 'PLANWRIGHT_STEP_BRANCH=planwright/demo/task-1' "$tmp/show.show.env" \
  && grep -qx 'PLANWRIGHT_STEP_BASE_BRANCH=main' "$tmp/show.show.env" \
  && grep -qx 'PLANWRIGHT_STEP_UNIT_KIND=task' "$tmp/show.show.env" \
  && grep -qx 'PLANWRIGHT_STEP_SPEC=' "$tmp/show.show.env"
verdict $? "step-run.sh with nothing exported derives the worktree, branch, base and a task kind" \
  "env: $(cat "$tmp/show.show.env" 2>&1) err: $(cat "$tmp/err")"
git -C "$wt" branch -m planwright/flight/demo-0123abcd
r=$(sr new-run)
hosted_show "$r"
grep -qx 'PLANWRIGHT_STEP_UNIT_KIND=flight' "$tmp/show.show.env" \
  && grep -qx 'PLANWRIGHT_STEP_BRANCH=planwright/flight/demo-0123abcd' "$tmp/show.show.env"
verdict $? "a planwright/flight/ branch derives the flight kind" "env: $(cat "$tmp/show.show.env" 2>&1)"
git -C "$wt" branch -m scratch-branch
r=$(sr new-run)
hosted_show "$r"
grep -qx 'PLANWRIGHT_STEP_UNIT_KIND=' "$tmp/show.show.env" && grep -qx 'PLANWRIGHT_STEP_BRANCH=scratch-branch' "$tmp/show.show.env"
verdict $? "a branch outside the planwright namespace derives no kind, and the branch itself" "env: $(cat "$tmp/show.show.env" 2>&1)"
git -C "$wt" branch -m planwright/flight/demo-0123abcd

# An exported value that disagrees with git is refused, naming both.
r=$(sr new-run)
hosted_show "$r" PLANWRIGHT_STEP_BRANCH=planwright/other/task-9
[ "$HRC" -eq 2 ] && grep -q 'planwright/other/task-9' "$tmp/err" && grep -q 'planwright/flight/demo-0123abcd' "$tmp/err" && [ ! -e "$tmp/show.show.env" ]
verdict $? "a branch that disagrees with git is refused naming both, and the step does not run" "rc $HRC err: $(cat "$tmp/err")"
r=$(sr new-run)
# shellcheck disable=SC2016 # the literal text $PWD is the point
hosted_show "$r" 'PLANWRIGHT_STEP_WORKTREE=$PWD'
# shellcheck disable=SC2016
[ "$HRC" -eq 2 ] && grep -qF '$PWD' "$tmp/err" && grep -qF "$wtp" "$tmp/err"
verdict $? "a non-literal worktree (\$PWD) is refused naming it and the derived path" "rc $HRC err: $(cat "$tmp/err")"
r=$(sr new-run)
hosted_show "$r" PLANWRIGHT_STEP_UNIT_KIND=task
[ "$HRC" -eq 2 ] && grep -q 'task' "$tmp/err" && grep -q 'flight' "$tmp/err"
verdict $? "a kind that disagrees with the branch namespace is refused naming both" "rc $HRC err: $(cat "$tmp/err")"
r=$(sr new-run)
hosted_show "$r" PLANWRIGHT_STEP_BASE_BRANCH=develop PLANWRIGHT_STEP_SPEC=demo PLANWRIGHT_STEP_TASK_IDS=1 PLANWRIGHT_STEP_PR_NUMBER=5
grep -qx 'PLANWRIGHT_STEP_BASE_BRANCH=develop' "$tmp/show.show.env" && grep -qx 'PLANWRIGHT_STEP_SPEC=demo' "$tmp/show.show.env" \
  && grep -qx 'PLANWRIGHT_STEP_PR_NUMBER=5' "$tmp/show.show.env"
verdict $? "a base, spec, task ids and PR number git cannot know are taken as exported" "env: $(cat "$tmp/show.show.env" 2>&1)"

# step-record.sh derives the same context and refuses the same disagreement.
srec() { bare_ctx "$SR" --worktree "$wt" "$@"; }
r=$(srec new-run 2>"$tmp/err")
[ "${#r}" -eq 6 ]
verdict $? "step-record.sh new-run works with no PLANWRIGHT_STEP_* set" "got: $r err: $(cat "$tmp/err")"
bare_ctx env PLANWRIGHT_STEP_BRANCH=planwright/other/task-9 "$SR" --worktree "$wt" new-run >"$tmp/out" 2>"$tmp/err"
rc=$?
[ "$rc" -eq 2 ] && grep -q 'planwright/other/task-9' "$tmp/err" && grep -q 'planwright/flight/demo-0123abcd' "$tmp/err"
verdict $? "step-record.sh refuses an exported branch that disagrees with git, naming both" "rc $rc err: $(cat "$tmp/err")"
bare_ctx env PLANWRIGHT_STEP_WORKTREE=/nonexistent/elsewhere "$SR" --worktree "$wt" new-run >"$tmp/out" 2>"$tmp/err"
rc=$?
[ "$rc" -eq 2 ] && grep -q '/nonexistent/elsewhere' "$tmp/err" && grep -qF "$wtp" "$tmp/err"
verdict $? "step-record.sh refuses an exported worktree that disagrees with git, naming both" "rc $rc err: $(cat "$tmp/err")"

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "all session-derived-context tests passed"
