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
# SP and TAB are read by the sourced fixture.
SP="$repo_root/scripts/step-pool.sh"
TAB=$(printf '\t')
# shellcheck source=tests/lib/step-run-fixture.sh
. "$here/lib/step-run-fixture.sh"

# --- the adopter overlay is derived from the installed plugin -----------------------------
cdir="$tmp/cdir"
data="$cdir/plugins/data/planwright-mkt"
mkdir -p "$cdir/plugins/cache/mkt/planwright/1.0.0/scripts" "$data/overlay"
# The installed record names mkt's copy as current; a stale marketplace's
# cached copy and overlay stay on disk beside it.
jq -n --arg p "$cdir/plugins/cache/mkt/planwright/1.0.0" \
  '{plugins: {"planwright@mkt": [{installPath: $p, scope: "user"}]}}' >"$cdir/plugins/installed_plugins.json"
mkdir -p "$cdir/plugins/cache/aaa-stale/planwright/0.1.0/scripts" "$cdir/plugins/data/planwright-aaa-stale/overlay"
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
# A copy running from the cache takes its own marketplace's overlay, and no other.
cp "$repo_root/scripts/resolve-overlay-root.sh" "$cdir/plugins/cache/aaa-stale/planwright/0.1.0/scripts/"
got=$(bare /bin/bash "$cdir/plugins/cache/aaa-stale/planwright/0.1.0/scripts/resolve-overlay-root.sh" adopter)
[ "$got" = "$cdir/plugins/data/planwright-aaa-stale/overlay" ]
verdict $? "a cached copy takes its own marketplace's data overlay" "got: $got"
rm -rf "$cdir/plugins/data/planwright-aaa-stale/overlay"
got=$(bare /bin/bash "$cdir/plugins/cache/aaa-stale/planwright/0.1.0/scripts/resolve-overlay-root.sh" adopter)
[ -z "$got" ]
verdict $? "a cached copy whose marketplace has no overlay never reads another install's" "got: $got"
mkdir -p "$cdir/plugins/data/planwright-aaa-stale/overlay"
rm -rf "$data/overlay"
got=$(bare /bin/bash "$repo_root/scripts/resolve-overlay-root.sh" adopter)
[ -z "$got" ]
verdict $? "a copy outside the cache never falls back to a stale cached marketplace's overlay" "got: $got"
rm -rf "$cdir/plugins/data/planwright-aaa-stale/overlay"
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

# --- the launcher hands on location variables and scrubs the per-call value overlays only ---
scrub=$(sed -n "s/^  scrub='\(.*\)'\$/\1/p" "$repo_root/scripts/mission-control-launch.sh")
[ -n "$scrub" ] || fail "the launch scrub line was not found in mission-control-launch.sh"
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
git -C "$wt" branch -m planwright/demo/spec
r=$(sr new-run)
hosted_show "$r"
grep -qx 'PLANWRIGHT_STEP_UNIT_KIND=spec' "$tmp/show.show.env"
verdict $? "a planwright/<spec>/spec branch derives the spec kind" "env: $(cat "$tmp/show.show.env" 2>&1)"
git -C "$wt" checkout -q --detach
r=$(sr new-run)
hosted_show "$r" PLANWRIGHT_STEP_BRANCH=exported-name
grep -qx 'PLANWRIGHT_STEP_BRANCH=exported-name' "$tmp/show.show.env" && grep -qx 'PLANWRIGHT_STEP_UNIT_KIND=' "$tmp/show.show.env"
verdict $? "a detached HEAD derives no branch or kind, so an exported branch has nothing to disagree with" "rc $HRC err: $(cat "$tmp/err")"
git -C "$wt" checkout -q -B planwright/flight/demo-0123abcd

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

# audit and list do not refuse an exported context that disagrees with git.
env_run env PLANWRIGHT_STEP_BRANCH=planwright/other/task-9 "$RUN" --worktree "$wt" audit --through pre-pr >"$tmp/out" 2>"$tmp/err"
case $? in 0 | 1) ok "audit does not refuse an exported context that names another unit" ;; *) fail "audit refused: $(cat "$tmp/err")" ;; esac
env_run env PLANWRIGHT_STEP_BRANCH=planwright/other/task-9 "$SR" --worktree "$wt" list >"$tmp/out" 2>"$tmp/err"
verdict $? "step-record.sh list does not refuse an exported context that names another unit" "err: $(cat "$tmp/err")"

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
for v in write supersede regenerate status; do
  bare_ctx env PLANWRIGHT_STEP_BRANCH=planwright/other/task-9 "$SR" --worktree "$wt" "$v" >"$tmp/out" 2>"$tmp/err"
  rc=$?
  [ "$rc" -eq 2 ] && grep -q 'planwright/other/task-9' "$tmp/err" && grep -q 'planwright/flight/demo-0123abcd' "$tmp/err"
  verdict $? "step-record.sh $v refuses an exported branch that disagrees with git" "rc $rc err: $(cat "$tmp/err")"
done

# A tag sharing the branch's name does not change the derived branch.
git -C "$wt" tag planwright/flight/demo-0123abcd
r=$(sr new-run)
hosted_show "$r"
grep -qx 'PLANWRIGHT_STEP_BRANCH=planwright/flight/demo-0123abcd' "$tmp/show.show.env" \
  && grep -qx 'PLANWRIGHT_STEP_UNIT_KIND=flight' "$tmp/show.show.env"
verdict $? "a tag named like the branch leaves the derived branch and kind intact" "rc $HRC env: $(cat "$tmp/show.show.env" 2>&1) err: $(cat "$tmp/err")"
git -C "$wt" tag -d planwright/flight/demo-0123abcd >"$tmp/out"

# A directory inside the worktree is not its own top: git's answer there is
# another work tree's, so nothing is derived from it and nothing is refused.
mkdir -p "$wt/plain"
plain=$(cd -P "$wt/plain" && pwd -P)
# shellcheck disable=SC2016 # expanded by the inner shell
got=$(bare_ctx env PLANWRIGHT_STEP_BRANCH=elsewhere sh -c \
  '. "$1"; step_context_derive "$2" t; printf "%s|%s" "$PLANWRIGHT_STEP_BRANCH" "${PLANWRIGHT_STEP_UNIT_KIND:-}"' \
  sh "$repo_root/scripts/step-context.sh" "$plain" 2>"$tmp/err")
[ "$got" = 'elsewhere|' ]
verdict $? "a worktree that is not its own top derives no branch or kind" "got: $got err: $(cat "$tmp/err")"
rm -rf "$wt/plain"

# Kinds follow the guards' unit-branch grammar: one segment after the spec or
# flight, and planwright/flight/task-* no unit.
for nb in planwright/flight/task-1 planwright/a/b/spec planwright/a/b/task-1; do
  git -C "$wt" branch -m "$nb"
  r=$(sr new-run)
  hosted_show "$r"
  grep -qx 'PLANWRIGHT_STEP_UNIT_KIND=' "$tmp/show.show.env"
  verdict $? "$nb derives no unit kind" "rc $HRC env: $(cat "$tmp/show.show.env" 2>&1) err: $(cat "$tmp/err")"
done
git -C "$wt" branch -m planwright/flight/demo-0123abcd

# A step that moves the branch still gets its record, whole or between begin and end.
cat >"$bin/mover.sh" <<'EOF'
#!/bin/sh
git -C "$PLANWRIGHT_STEP_WORKTREE" branch -m planwright/flight/moved-0123abcd
EOF
chmod +x "$bin/mover.sh"
catalog "mover|kind: command|target: $bin/mover.sh" "held|kind: command|target: $bin/show.sh|hosting: in-session"
config 'steps_pre_pr: [mover, held]'
moved_ctx() { bare_ctx env PLANWRIGHT_STEP_BRANCH=planwright/flight/demo-0123abcd PLANWRIGHT_STEP_UNIT_KIND=flight "$@"; }
r=$(sr new-run)
moved_ctx "$RUN" --worktree "$wt" resolve --run "$r" pre-pr --unattended >"$tmp/rows" 2>"$tmp/err"
moved_ctx "$RUN" --worktree "$wt" command --run "$r" --point pre-pr --step mover >"$tmp/out" 2>>"$tmp/err"
rc=$?
[ "$rc" -eq 0 ] && grep -q '^passed' "$tmp/out" && [ -n "$(sr list --run "$r" --point pre-pr)" ]
verdict $? "a command step that renames the branch still gets its record" "rc $rc out: $(cat "$tmp/out") err: $(cat "$tmp/err")"
git -C "$wt" branch -m planwright/flight/demo-0123abcd
moved_ctx "$RUN" --worktree "$wt" begin --run "$r" --point pre-pr --step held --owner "$(owner)" >"$tmp/out" 2>"$tmp/err"
git -C "$wt" branch -m planwright/flight/moved-0123abcd
moved_ctx "$RUN" --worktree "$wt" end --run "$r" --point pre-pr --step held --exit 0 >"$tmp/out" 2>>"$tmp/err"
rc=$?
[ "$rc" -eq 0 ] && grep -q '^passed' "$tmp/out"
verdict $? "end records a step that renamed the branch after begin" "rc $rc out: $(cat "$tmp/out") err: $(cat "$tmp/err")"
git -C "$wt" branch -m planwright/flight/demo-0123abcd
catalog "show|kind: command|target: $bin/show.sh"
config 'steps_pre_pr: [show]'

# A session rendering a skill or prompt step's preamble with no worktree
# exported gets the context git knows; outside a work tree it stays empty.
RS="$repo_root/scripts/resolve-steps.sh"
got=$(cd "$wt" && bare_ctx "$RS" pre-pr --preamble 2>"$tmp/err")
printf '%s\n' "$got" | grep -qx "PLANWRIGHT_STEP_WORKTREE=$wtp" \
  && printf '%s\n' "$got" | grep -qx 'PLANWRIGHT_STEP_BRANCH=planwright/flight/demo-0123abcd' \
  && printf '%s\n' "$got" | grep -qx 'PLANWRIGHT_STEP_BASE_BRANCH=main' \
  && printf '%s\n' "$got" | grep -qx 'PLANWRIGHT_STEP_UNIT_KIND=flight'
verdict $? "the preamble with no worktree exported carries the worktree, branch, base and kind" "got: $got err: $(cat "$tmp/err")"
(cd "$wt" && bare_ctx env PLANWRIGHT_STEP_BRANCH=elsewhere "$RS" pre-pr --preamble >"$tmp/out" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 6 ] && grep -q elsewhere "$tmp/err" && grep -q 'planwright/flight/demo-0123abcd' "$tmp/err"
verdict $? "a preamble whose exported branch disagrees with git exits 6 naming both" "rc $rc err: $(cat "$tmp/err")"
got=$(cd "$wt" && bare_ctx "$RS" pre-pr --prefix 2>"$tmp/err")
printf '%s' "$got" | grep -qF "PLANWRIGHT_STEP_WORKTREE='' "
verdict $? "the prefix, which step-run.sh renders after deriving, derives nothing itself" "got: $got err: $(cat "$tmp/err")"
mkdir -p "$tmp/nogit"
got=$(cd "$tmp/nogit" && bare_ctx "$RS" pre-pr --preamble 2>"$tmp/err")
printf '%s\n' "$got" | grep -qx 'PLANWRIGHT_STEP_WORKTREE=' && printf '%s\n' "$got" | grep -qx 'PLANWRIGHT_STEP_BRANCH='
verdict $? "a preamble rendered outside a work tree leaves those fields empty" "got: $got err: $(cat "$tmp/err")"

# A refusal never prints a control byte an exported value carried.
esc=$(printf '\033')
bare_ctx env PLANWRIGHT_STEP_BRANCH="bad${esc}[31mname" "$SR" --worktree "$wt" new-run >"$tmp/out" 2>"$tmp/err"
rc=$?
[ "$rc" -eq 2 ] && ! grep -q "$esc" "$tmp/err" && grep -q 'bad\[31mname' "$tmp/err"
verdict $? "the disagreement message strips control bytes from the values it names" "rc $rc err: $(cat "$tmp/err")"

# An exported path that resolves to the worktree is accepted and replaced by it.
ln -s "$wt" "$tmp/wt-link"
r=$(sr new-run)
hosted_show "$r" PLANWRIGHT_STEP_WORKTREE="$tmp/wt-link"
[ "$HRC" -eq 0 ] && grep -qx "PLANWRIGHT_STEP_WORKTREE=$wtp" "$tmp/show.show.env"
verdict $? "an exported symlink to the worktree is accepted and exported as the worktree" "rc $HRC env: $(cat "$tmp/show.show.env" 2>&1) err: $(cat "$tmp/err")"

# An inherited GIT_DIR naming another repository does not lend its branch.
other="$tmp/other-repo"
git init -q -b planwright/other/task-9 "$other"
r=$(sr new-run)
hosted_show "$r" GIT_DIR="$other/.git"
grep -qx 'PLANWRIGHT_STEP_BRANCH=planwright/flight/demo-0123abcd' "$tmp/show.show.env"
verdict $? "an inherited GIT_DIR does not change the derived branch" "rc $HRC env: $(cat "$tmp/show.show.env" 2>&1) err: $(cat "$tmp/err")"

# Only the verbs that derive need step-context.sh: an install missing it still reads.
lone="$tmp/lone"
mkdir -p "$lone"
cp "$SR" "$repo_root/scripts/echo-safety.sh" "$repo_root/scripts/lock-lib.sh" "$lone/"
bare_ctx /bin/sh "$lone/step-record.sh" --worktree "$wt" list --run "$r" >"$tmp/out" 2>"$tmp/err"
verdict $? "step-record.sh list runs without step-context.sh" "err: $(cat "$tmp/err")"
bare_ctx /bin/sh "$lone/step-record.sh" --worktree "$wt" new-run >"$tmp/out" 2>"$tmp/err"
rc=$?
[ "$rc" -eq 1 ] && grep -q 'broken install' "$tmp/err"
verdict $? "step-record.sh new-run without step-context.sh exits 1 naming a broken install" "rc $rc err: $(cat "$tmp/err")"

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "all session-derived-context tests passed"
