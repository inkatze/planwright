#!/bin/sh
# Shared fixture for the step-run suites (tests/test-step-run.sh,
# tests/test-step-run-resume.sh): fixture worktrees with a bare origin, a
# private pools root, adopter-layer catalog and config writers, fixture
# command steps that log the context they saw, and the runner-call helpers
# that sequence a point the way /execute-task does.
#
# The sourcing suite sets repo_root, RUN, SR, SP, and TAB first.
# shellcheck disable=SC2034,SC2154 # the suites set repo_root and use wt, GATE, and the helpers
# Inherited git variables (a hook's) would point the fixture's git calls at the
# caller's repository.
unset CDPATH GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
ok() { printf 'ok: %s\n' "$1"; }
# verdict <status> <ok-message> <fail-detail>: callers pass $? first, since
# bash sets $? from any command substitution in the later arguments.
verdict() {
  if [ "$1" -eq 0 ]; then
    ok "$2"
  else
    fail "$3"
  fi
}

tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-step-run.XXXXXX")" && pwd -P)" || exit 1
owners="$tmp/owners"
cleanup() {
  [ -f "$owners" ] && while read -r _p; do kill "$_p" 2>/dev/null; done <"$owners"
  rm -rf "$tmp"
}
trap cleanup EXIT

PLANWRIGHT_SECRET_SCREEN_TOOL=none
export PLANWRIGHT_SECRET_SCREEN_TOOL
adopter="$tmp/adopter"
bin="$tmp/bin"
mkdir -p "$adopter/catalogs" "$bin" "$tmp/home" "$tmp/claude"

# The fixture steps. check.sh logs one line per run (point, hold mark, previous
# record, head move, start and end stamps) to $tmp/check.log, fails while
# $tmp/fail exists, sleeps while $tmp/slow holds a number, and takes its own
# pool again when $tmp/nest exists. edit.sh commits a change under <path> and,
# given `push`, pushes it. show.sh logs the context it saw.
cat >"$bin/check.sh" <<'EOF'
#!/bin/sh
t=$(dirname "$0")/..
start=$(date +%s)
[ ! -e "$t/nest" ] || "$SP_UNDER_TEST" take gate "$$" --step inner >"$t/nest.out" 2>&1 || exit 9
[ ! -s "$t/slow" ] || sleep "$(cat "$t/slow")"
printf 'point=%s hold=%s prev=%s ph=%s nh=%s start=%s end=%s wt=%s\n' "$PLANWRIGHT_STEP_POINT" \
  "${PLANWRIGHT_STEP_POOL_HOLD-}" "$PLANWRIGHT_STEP_PREV_RECORD" "$PLANWRIGHT_STEP_PREV_HEAD" \
  "$PLANWRIGHT_STEP_NEW_HEAD" "$start" "$(date +%s)" "$PLANWRIGHT_STEP_WORKTREE" >>"$t/check.log"
[ ! -e "$t/fail" ] || exit 3
exit 0
EOF
cat >"$bin/edit.sh" <<'EOF'
#!/bin/sh
mkdir -p "$1"
printf '%s %s\n' "$$" "$(date +%s)" >>"$1/f.txt"
git add "$1/f.txt" && git commit -q -m "fix: edit $1" || exit 5
[ "${2:-}" != push ] || git push -q origin HEAD 2>/dev/null || exit 6
EOF
cat >"$bin/show.sh" <<'EOF'
#!/bin/sh
t=$(dirname "$0")/..
env | grep '^PLANWRIGHT_STEP_' | sort >"$t/show.$PLANWRIGHT_STEP_ID.env"
printf 'host=%s\n' "${HOST_SENTINEL-<unset>}" >>"$t/show.$PLANWRIGHT_STEP_ID.env"
EOF
# grand.sh starts a grandchild that would outlive a kill of its parent alone.
cat >"$bin/grand.sh" <<'EOF'
#!/bin/sh
t=$(dirname "$0")/..
sleep 60 &
printf '%s\n' "$!" >"$t/grand.pid"
printf '%s\n' "$$" >"$t/parent.pid"
sleep 60
EOF
# stubborn.sh ignores TERM, so only a KILL ends it.
cat >"$bin/stubborn.sh" <<'EOF'
#!/bin/sh
t=$(dirname "$0")/..
trap '' TERM
printf '%s\n' "$$" >"$t/parent.pid"
sleep 60
EOF
chmod +x "$bin/check.sh" "$bin/edit.sh" "$bin/show.sh" "$bin/grand.sh" "$bin/stubborn.sh"

n=0
# fresh: a new fixture worktree ($wt) with a bare origin and one commit.
fresh() {
  n=$((n + 1))
  wt="$tmp/wt$n"
  git init -q --bare "$tmp/origin$n.git"
  git init -q -b planwright/demo/task-1 "$wt"
  git -C "$wt" config user.name Fixture
  git -C "$wt" config user.email fixture@example.invalid
  git -C "$wt" config commit.gpgsign false
  mkdir -p "$wt/src" "$wt/docs"
  printf 'a\n' >"$wt/src/a.txt"
  printf 'd\n' >"$wt/docs/d.txt"
  printf '.claude/steps/\n' >"$wt/.gitignore"
  git -C "$wt" add -A && git -C "$wt" commit -q -m "chore: base"
  git -C "$wt" remote add origin "$tmp/origin$n.git"
  git -C "$wt" push -q origin HEAD 2>/dev/null
  rm -f "$tmp/check.log" "$tmp/fail" "$tmp/slow" "$tmp/nest" "$tmp"/show.*.env "$tmp/grand.pid" "$tmp/parent.pid"
}

# catalog <entry>...: the adopter steps catalog, one `id|field: value|...`
# argument per entry; config <line>...: the adopter config.
catalog() {
  printf 'steps:\n' >"$adopter/catalogs/steps.yaml"
  for e in "$@"; do
    printf '%s\n' "$e" | awk -F '|' '{ printf "  - id: %s\n", $1; for (i = 2; i <= NF; i++) printf "    %s\n", $i }' \
      >>"$adopter/catalogs/steps.yaml"
  done
}
config() {
  : >"$adopter/planwright.yml"
  for l in "$@"; do printf '%s\n' "$l" >>"$adopter/planwright.yml"; done
}

env_run() {
  PLANWRIGHT_ROOT="$repo_root" PLANWRIGHT_CONFIG_DEFAULTS="$repo_root/config/defaults.yml" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" PLANWRIGHT_REPO_ROOT="$wt" PLANWRIGHT_LOCAL_CONFIG="" \
    PLANWRIGHT_POOL_DIR="$tmp/pools" CLAUDE_DIR="$tmp/claude" HOME="$tmp/home" \
    SP_UNDER_TEST="$SP" HOST_SENTINEL=kept PLANWRIGHT_STEP_SPEC=demo PLANWRIGHT_STEP_TASK_IDS=1 \
    PLANWRIGHT_STEP_UNIT_KIND=task PLANWRIGHT_STEP_BRANCH=planwright/demo/task-1 \
    PLANWRIGHT_STEP_BASE_BRANCH=main PLANWRIGHT_STEP_WORKTREE="$wt" PLANWRIGHT_STEP_PR_NUMBER="${PR-7}" \
    "$@"
}
srun() { env_run "$RUN" --worktree "$wt" "$@"; }
sr() { "$SR" --worktree "$wt" "$@"; }
sp() { env_run "$SP" "$@"; }
recs() { sr list --run "$1" ${2:+--point "$2"}; }
head_of() { git -C "$wt" rev-parse HEAD; }
owner() {
  sleep 120 >/dev/null 2>&1 &
  _o=$!
  printf '%s\n' "$_o" >>"$owners"
  printf '%s' "$_o"
}

# point_run <run> <point> [--refire-of ...]: resolve the point, host each of
# its command steps, write its completion. Records every result line.
point_run() {
  _r=$1 _p=$2
  srun resolve --run "$_r" "$_p" --unattended >"$tmp/rows" 2>"$tmp/resolve.err"
  while IFS=$TAB read -r _d _id _rest; do
    [ "$_d" = run ] || continue
    srun command --run "$_r" --point "$_p" --step "$_id" >>"$tmp/results" 2>>"$tmp/err"
  done <"$tmp/rows"
}
point_done() { sr write --completion --run "$1" --point "$2" >/dev/null; }
# refire_pass <run>: the plan, then each planned step at post-pr.
refire_pass() {
  srun refire --run "$1" >"$tmp/plan"
  while IFS=$TAB read -r _ _id _decl _; do
    srun command --run "$1" --point post-pr --step "$_id" --refire-of "$_decl" >>"$tmp/results" 2>>"$tmp/err"
  done <"$tmp/plan"
}
# unit <run>: a unit run's pre-pr and post-pr points with the re-fire pass.
unit() {
  point_run "$1" pre-pr
  point_done "$1" pre-pr
  point_run "$1" post-pr
  refire_pass "$1"
  point_done "$1" post-pr
}

GATE="gate|kind: command|target: $bin/check.sh|pool: gate|paths: src|refire: post-pr"
