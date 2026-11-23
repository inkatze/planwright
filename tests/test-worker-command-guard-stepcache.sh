#!/bin/bash
# Tests for scripts/worker-command-guard.sh: the step scripts pass only in the
# forms that leave a record's times to the scripts and keep to the session's
# own step cache (REQ-F1.12). A hand-timed write (every write but a
# --completion one, and any write carrying --start or --end) defers however it
# is spelled; every other call passes only on the recorded worktree, in the
# verbs the requirement lists. Each row runs under every policy value. The
# rows run in the corpus sandbox (tests/lib/worker-guard-corpus.sh): a linked
# worktree with one session record per policy column.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"
# shellcheck source=tests/lib/worker-guard-corpus.sh
. "$REPO_ROOT/tests/lib/worker-guard-corpus.sh"

corpus_sandbox "$SANDBOX/box" "$REPO_ROOT" || {
  echo "FAIL: could not build the corpus sandbox" >&2
  exit 1
}
WT=$CORPUS_WORKTREE
SCR=$CORPUS_SCRATCH
OUT_DIR=$CORPUS_OUTSIDE
OTHER_WT=$CORPUS_BOX/other
STATE=$CORPUS_BOX/state
B=$CORPUS_UNIT_BRANCH
GIT_ISO=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1")
# The guard's own root is an installed planwright root it trusts.
SREC=$REPO_ROOT/scripts/step-record.sh
SRUN=$REPO_ROOT/scripts/step-run.sh
printf 'x\n' >"$WT/out.log"
printf 'x\n' >"$SCR/out.log"
mkdir -p "$WT/nested"
: >"$WT/nested/.git"
ln -s "$OUT_DIR/x" "$WT/outside-link"

POLICIES=("" "own-branch" "scratch" "own-branch scratch")
T=2026-11-22T10:00:00Z

# no_wt <col>: the column's record with its worktree_root dropped.
no_wt() {
  grep -v '^worktree_root=' "$STATE/record.$1" >"$STATE/nowt.$1"
  printf '%s\n' "$STATE/nowt.$1"
}

# each <assert> <label> <command> [cwd]: the assertion under every policy
# value's record.
each() {
  local col
  for col in 1 2 3 4; do
    HOOK_ENV=("${GIT_ISO[@]}" "TMPDIR=$SCR" "PLANWRIGHT_WORKER_SESSION_RECORD=$STATE/record.$col")
    "$1" "F1.12 [${POLICIES[col - 1]}]: $2" "$3" Bash "${4:-$WT}"
  done
}
# one <assert> <label> <command> [cwd]: the assertion under the empty policy
# alone, for a spelling whose verdict no arm reaches: the step-script rule is
# read before any arm, so the four columns above already show it holds at
# every value.
one() {
  HOOK_ENV=("${GIT_ISO[@]}" "TMPDIR=$SCR" "PLANWRIGHT_WORKER_SESSION_RECORD=$STATE/record.1")
  "$1" "F1.12 []: $2" "$3" Bash "${4:-$WT}"
}
# each_nowt <assert> <label> <command>: the same under records naming no
# worktree.
each_nowt() {
  local col
  for col in 1 2 3 4; do
    HOOK_ENV=("${GIT_ISO[@]}" "TMPDIR=$SCR" "PLANWRIGHT_WORKER_SESSION_RECORD=$(no_wt "$col")")
    "$1" "F1.12 [${POLICIES[col - 1]}, no worktree]: $2" "$3" Bash "$WT"
  done
}
one_nowt() {
  HOOK_ENV=("${GIT_ISO[@]}" "TMPDIR=$SCR" "PLANWRIGHT_WORKER_SESSION_RECORD=$(no_wt 1)")
  "$1" "F1.12 [, no worktree]: $2" "$3" Bash "$WT"
}

echo "### REQ-F1.12 — a hand-timed write defers in every spelling"
HAND=(
  "a step write|write --run 000001 --point convergence --step polish --kind skill --target polish --hosting isolated --backend headless --start $T --end $T --outcome passed"
  "a re-fire write|write --run 000001 --point post-pr --step polish --kind skill --target polish --hosting isolated --backend headless --start $T --outcome passed --refire-of pre-pr"
  "a full-suite write|write --full-suite --run 000001 --pool gate --wait 0 --wait-outcome passed --start $T --end $T"
  "a step write with no times|write --run 000001 --point pre-pr --step x --outcome passed"
  "a completion write carrying --start|write --completion --run 000001 --point pre-pr --start $T"
  "a completion write carrying --end|write --completion --run 000001 --point pre-pr --end $T"
  "a completion write carrying --start=|write --completion --run 000001 --point pre-pr --start=$T"
  "a completion write carrying --end=|write --completion --run 000001 --point pre-pr --end=$T"
)
for h in "${HAND[@]}"; do
  label=${h%%|*}
  args=${h#*|}
  each assert_defer "$label, alone" "$SREC $args"
  each assert_defer "$label, behind a step-context prefix" "PLANWRIGHT_STEP_WORKTREE=$WT PLANWRIGHT_STEP_BRANCH=$B $SREC $args"
  each assert_defer "$label, after an export" "export PLANWRIGHT_STEP_WORKTREE=$WT PLANWRIGHT_STEP_BRANCH=$B && $SREC $args"
  each assert_defer "$label, before an own-unit push" "$SREC $args && git push origin $B"
  one assert_defer "$label, with --worktree naming the own worktree" "$SREC --worktree $WT $args"
  one assert_defer "$label, run by sh" "sh $SREC $args"
  one assert_defer "$label, under a timeout" "timeout 60 $SREC $args"
done
one assert_defer "a step write, behind env and a step-context prefix" "env PLANWRIGHT_STEP_WORKTREE=$WT $SREC write --run 000001 --point pre-pr --step x --start $T --outcome passed"
# The wrappers pass a passing verb, so the rows above defer for the write.
one assert_allow "new-run, behind env and a step-context prefix" "env PLANWRIGHT_STEP_WORKTREE=$WT $SREC new-run"
one assert_allow "new-run, under a timeout" "timeout 60 $SREC new-run"
one assert_allow "new-run, with --worktree naming the own worktree" "$SREC --worktree $WT new-run"
# A declared check command never approves a step-script call the rule refuses.
HOOK_ENV=("${GIT_ISO[@]}" "TMPDIR=$SCR" "PLANWRIGHT_WORKER_SESSION_RECORD=$STATE/declared.record")
{
  cat "$STATE/record.1"
  printf 'check_commands=%s\n' "$SREC write --run <word> --point <word> --step <word> --start <word> --outcome <word>"
} >"$STATE/declared.record"
assert_defer "F1.12 []: a step write a check command declares" "$SREC write --run 000001 --point pre-pr --step x --start $T --outcome passed" Bash "$WT"
each assert_defer "--start reached through a tracked assignment" "X=--start && $SREC write --completion --run 000001 --point pre-pr \$X $T"
each assert_defer "an untracked word in a completion write" "$SREC write --completion --run 000001 --point pre-pr \$X"
each assert_defer "a substitution in a completion write" "$SREC write --completion --run \$(cat run) --point pre-pr"
each assert_defer "a glob in a completion write" "$SREC write --completion --run 0* --point pre-pr"
each assert_defer "a supersede without --source" "$SREC supersede --record 000001:pre-pr:1 --start $T"
one assert_defer "--start spliced from quoted parts" "$SREC write --completion --run 000001 --point pre-pr --st''art $T"
one assert_defer "--start reached through a brace expansion" "$SREC write --completion --run 000001 --point pre-pr --{start,x} $T"
one assert_defer "--completion reached through a brace expansion" "$SREC write --{completion,x} --run 000001 --point pre-pr"
one assert_defer "--start quoted whole" "$SREC write --completion --run 000001 --point pre-pr \"--start\" $T"

echo "### REQ-F1.12 — the reading: one two-word --worktree, then the verb"
each assert_defer "--worktree=<dir>" "$SREC --worktree=$WT new-run"
each assert_defer "a doubled --worktree" "$SREC --worktree $WT --worktree $WT new-run"
each assert_defer "a relative --worktree" "$SREC --worktree . new-run"
each assert_defer "a --worktree through a dot-dot" "$SREC --worktree $WT/../other new-run"
each assert_defer "a --worktree through a dot-dot back to the own worktree" "$SREC --worktree $WT/../$(basename "$WT") new-run"
each assert_defer "a --worktree with a dot segment" "$SREC --worktree $WT/. new-run"
each assert_defer "a --worktree with a doubled slash and a dot" "$SREC --worktree $WT//. new-run"
each assert_defer "a --worktree with no value" "$SREC --worktree"
each assert_defer "a --worktree through an untracked variable" "$SREC --worktree \$W new-run"
each assert_defer "another leading word" "$SREC --help"
each assert_defer "an option before the verb" "$SREC -x new-run"
each assert_defer "an unknown step-record verb" "$SREC frobnicate"
each assert_defer "an unknown step-run verb" "$SRUN write --run 000001"
each assert_defer "a step-record verb given to step-run" "$SRUN render"
each assert_defer "no verb" "$SREC"

echo "### REQ-F1.12 — the own-cache rule"
PASSING=(
  "$SREC write --completion --run 000001 --point pre-pr"
  "$SREC supersede --record 000001:pre-pr:1 --start $T --source session:abc"
  "$SREC render --run 000001"
  "$SREC list --effective"
  "$SREC lookup resume --run 000001 --point pre-pr"
  "$SREC heads --run 000001 --point pre-pr"
  "$SREC untrue"
  "$SREC fingerprint --paths scripts"
  "$SREC new-run"
  "$SREC regenerate --base origin/main --head HEAD --checklist-only"
  "$SREC status --point pre-ready-flip --repo o/r"
  "$SRUN resolve --run 000001 pre-pr --unattended"
  "$SRUN audit --through pre-pr"
  "$SRUN command --run 000001 --point pre-ci --step wire-githooks"
  "$SRUN begin --run 000001 --point pre-ci --step x --owner 123"
  "$SRUN end --run 000001 --point pre-ci --step x --exit 0"
  "$SRUN resume --run 000002 --from 000001:pre-pr"
  "$SRUN refire --run 000001"
)
for p in "${PASSING[@]}"; do
  script=${p%% *}
  rest=${p#* }
  name="${script##*/} ${rest%% *}"
  each assert_allow "$name, --worktree absent" "$p"
  each assert_allow "$name, --worktree naming the own worktree" "$script --worktree $WT $rest"
  one assert_defer "$name, --worktree naming another worktree" "$script --worktree $OTHER_WT $rest"
  one assert_defer "$name, from another worktree" "$p" "$OTHER_WT"
  one_nowt assert_defer "$name" "$p"
done
# The rest of the own-cache spellings, on one call of each script: the rule
# is read before the verb, so it holds for every verb above alike.
for p in "$SREC new-run" "$SREC write --completion --run 000001 --point pre-pr" "$SRUN audit --through pre-pr"; do
  script=${p%% *}
  rest=${p#* }
  name="${script##*/} ${rest%% *}"
  each assert_defer "$name, --worktree naming another worktree" "$script --worktree $OTHER_WT $rest"
  each assert_defer "$name, --worktree naming a directory outside" "$script --worktree $OUT_DIR $rest"
  each assert_defer "$name, from outside every worktree" "$p" "$OUT_DIR"
  each assert_defer "$name, from a nested repository" "$p" "$WT/nested"
  each assert_defer "$name, behind a step context naming another worktree" "PLANWRIGHT_STEP_WORKTREE=$OTHER_WT $p"
  each_nowt assert_defer "$name" "$p"
  each_nowt assert_defer "$name, --worktree naming it" "$script --worktree $WT $rest"
  one assert_allow "$name, from a subdirectory" "$p" "$WT/sub"
  one assert_allow "$name, behind the own step context" "PLANWRIGHT_STEP_WORKTREE=$WT $p"
  one assert_allow "$name, after an export" "export PLANWRIGHT_STEP_WORKTREE=$WT && $p"
  one assert_allow "$name, run by sh" "sh $p"
  one assert_allow "$name, run by bash" "bash $p"
  one assert_defer "$name, run by sh from another worktree" "sh $p" "$OTHER_WT"
done
each assert_allow "a chain of passing calls with an own-unit push" "$SREC write --completion --run 000001 --point post-pr && $SRUN audit --through post-pr && git push origin $B"

echo "### REQ-F1.12 — excerpt reads a worktree or scratch file only"
each assert_allow "excerpt of a worktree file" "$SREC excerpt out.log"
one assert_allow "excerpt of a worktree file by absolute path" "$SREC excerpt $WT/out.log"
each assert_allow "excerpt of a scratch file" "$SREC excerpt $SCR/out.log"
each assert_allow "excerpt with --worktree naming the own worktree" "$SREC --worktree $WT excerpt out.log"
each assert_defer "excerpt of a file outside" "$SREC excerpt $OUT_DIR/x"
one assert_defer "excerpt through a dot-dot out of the worktree" "$SREC excerpt ../$(basename "$OUT_DIR")/x"
one assert_defer "excerpt through a symlink out of the worktree" "$SREC excerpt outside-link"
one assert_defer "excerpt through a symlink out of the scratch root" "$SREC excerpt $SCR/escape"
one assert_defer "excerpt of the worktree's parent through a dot-dot leaf" "$SREC excerpt $WT/.."
one assert_defer "excerpt through a symlinked directory out of the worktree" "$SREC excerpt outlink/x"
one assert_allow "excerpt of a scratch file with --worktree naming the own worktree" "$SREC --worktree $WT excerpt $SCR/out.log"
one assert_allow "excerpt from a subdirectory" "$SREC excerpt ../out.log" "$WT/sub"
one assert_defer "excerpt of two files" "$SREC excerpt out.log out.log"
one assert_defer "excerpt with no file" "$SREC excerpt"
one assert_defer "excerpt from another worktree" "$SREC excerpt $WT/out.log" "$OTHER_WT"
one_nowt assert_defer "excerpt of a worktree file" "$SREC excerpt $WT/out.log"

echo "### REQ-F1.12 — args-digest passes as it did, no worktree needed"
each assert_allow "args-digest" "$SREC args-digest x"
each assert_allow "args-digest with --worktree naming the own worktree" "$SREC --worktree $WT args-digest x"
one assert_allow "args-digest from outside every worktree" "$SREC args-digest x" "$OUT_DIR"
one assert_allow "args-digest with --worktree naming another worktree" "$SREC --worktree $OTHER_WT args-digest x"
one assert_defer "args-digest after an unresolved --worktree" "$SREC --worktree \$W args-digest x"
each_nowt assert_allow "args-digest" "$SREC args-digest x"
one assert_defer "args-digest with a substitution" "$SREC args-digest \$(cat out.log)"

finish_suite worker-command-guard-stepcache
