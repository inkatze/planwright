#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: the command shapes around a
# run of scripts/worker-branch-sync.sh. Only the helper's own run, alone or
# after one plain cd, by the installed copy, is admitted; every wrapper,
# chain, copy, link and hidden spelling is refused, so is any setting of the
# session-record variable, and a mention that runs nothing passes to the
# ordinary rules.
#
# Split from tests/test-policy-guard-branch-sync.sh to keep each file under the
# per-file test time budget; the fixture is tests/lib/policy-guard-branch-sync.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"
# shellcheck source=tests/lib/policy-guard-clones.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-clones.sh"
# shellcheck source=tests/lib/policy-guard-branch-sync.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-branch-sync.sh"

echo "# the shape of the command"
for c in "PLANWRIGHT_WORKER_SESSION_RECORD=/tmp/x.record $PUSH" "GIT_DIR=/x $PUSH" \
  "env $PUSH" "bash $PUSH" "sh $PUSH" "nohup $PUSH" "command $PUSH" "exec $PUSH" "time $PUSH" "! $PUSH" \
  "$PUSH; git status" "$PUSH && echo done" "git status && $PUSH" "true || $PUSH" "$PUSH &" \
  "$PUSH > $SANDBOX/out" "$PUSH 2>&1" "$PUSH | cat" "echo \$($PUSH)" "bash -c '$PUSH'" \
  "cd \"$UNIT\"; $PUSH" "cd \"$UNIT\" || $PUSH" "false && cd \"$UNIT\" && $PUSH" \
  "if true; then $PUSH; fi" "for i in 1; do $PUSH; done" "x=1 && $PUSH" \
  "cd -P \"$UNIT\" && $PUSH" "cd \"$SANDBOX/nope\" && $PUSH" "cd \$D && $PUSH" "cd \"$UNIT\" && cd . && $PUSH" \
  "$H push --force-with-lease=$B:\$SHA --force-if-includes" "$H ff \"\$X\"" \
  "$S/worker-branch-\\
sync.sh ff $SHA; git status" "${H//worker/WORKER} ff $SHA" "x=\$(true) $PUSH" \
  "find . -name x -exec $H ff $SHA ;" "$S/\"worker-branch-sync.sh\" ff $SHA; true"; do
  sync "$c"
  expect deny "[worker] the shape '$(printf '%s' "$c" | tr '\n' ' ' | cut -c1-80)' denies"
done

echo "# the copy that runs"
mkdir -p "$UNIT/scripts" "$SANDBOX/elsewhere"
cp "$H" "$UNIT/scripts/"
cp "$H" "$SANDBOX/elsewhere/"
sync "$UNIT/scripts/worker-branch-sync.sh ff $SHA"
expect deny "[worker] a copy inside the worktree denies"
reason_has 'not the installed' "[worker] the worktree-copy refusal says it is not the installed copy"
sync "scripts/worker-branch-sync.sh ff $SHA"
expect deny "[worker] a relative path denies"
sync "$SANDBOX/elsewhere/worker-branch-sync.sh ff $SHA"
expect deny "[worker] a copy outside every installed root denies"
sync '"$ROOT"/scripts/worker-branch-sync.sh ff '"$SHA"
expect deny "[worker] another variable root denies"
rm -rf "${UNIT:?}/scripts"
mkdir -p "$UNIT/scripts" "$SANDBOX/linked"
ln -s "$H" "$UNIT/scripts/worker-branch-sync.sh"
sync "$UNIT/scripts/worker-branch-sync.sh ff $SHA"
expect deny "[worker] a symbolic link to the installed helper denies"
ln "$H" "$SANDBOX/linked/worker-branch-sync.sh"
sync "$SANDBOX/linked/worker-branch-sync.sh ff $SHA"
expect deny "[worker] a second hard link to the installed helper, in another directory, denies"
rm -rf "${UNIT:?}/scripts" "$SANDBOX/linked"

echo "# spellings that hide the run"
for c in "sh -c '$S/worker-branch-s\\ync.sh ff $SHA'" "bash -c 'cd /tmp && $S/worker-branch-sync.sh ff $SHA'" \
  "bash -c '$S/worker-branch-sync.sh ff /tmp/x'" "env X=1 $S/worker-branch-s\\ync.sh ff $SHA" \
  "bash <<'EOF'
$PUSH
EOF" "printf '%s\\n' '$PUSH' | bash" "cat $SANDBOX/x | sh # worker-branch-sync" \
  "timeout 60 $H ff $SHA" "bash -o posix $H ff $SHA" "source $H" "nice -n 5 $H ff $SHA" \
  "find . -name x -execdir $H ff $SHA ;" "sh -e $H ff $SHA" \
  "env bash $H ff $SHA" "timeout 60 bash $H ff $SHA" "busybox sh $H ff $SHA" "nohup sh $H ff $SHA" \
  "timeout -s KILL 10 $H ff $SHA" "env -u FOO $H ff $SHA" "flock /tmp/l $H ff $SHA" "ssh host $H ff $SHA" \
  "bash -eo pipefail $H ff $SHA" "trap $H EXIT" "eval $H" \
  "find . -exec bash $H {} ;" "find . -exec env $H {} ;" "find . -exec timeout 5 $H ;" \
  "echo $H | env bash" "echo $H | timeout 5 sh" "echo $H | busybox sh" "taskset -c 0 $H ff $SHA" \
  "find . -exec cat {} \\; -exec $H ff $SHA \\;" "nice find . -exec wc {} + -exec $H ff $SHA \\;" \
  "find . -exec grep x {} \\; -exec bash -c '$H ff $SHA' \\;"; do
  sync "$c"
  expect deny "[worker] the hidden run '$(printf '%s' "$c" | tr '\n' ' ' | cut -c1-70)' denies"
done
sync "$S/worker-branch-s\\ync.sh ff $SHA"
expect deny "[worker] a backslash inside the path is no plain literal, and denies"

echo "# the record variable"
for c in "PLANWRIGHT_WORKER_SESSION_RECORD=/tmp/x.record $S/worker-branch-\$'sync'.sh ff $SHA" \
  "export PLANWRIGHT_WORKER_SESSION_RECORD=/tmp/x.record" "unset PLANWRIGHT_WORKER_SESSION_RECORD" \
  "env PLANWRIGHT_WORKER_SESSION_RECORD=/tmp/x.record true" "declare -x PLANWRIGHT_WORKER_SESSION_RECORD=/x" \
  "read PLANWRIGHT_WORKER_SESSION_RECORD </tmp/x" "PLANWRIGHT_WORKER_SESSION_RECORD=/x" \
  "true && PLANWRIGHT_WORKER_SESSION_RECORD+=x true" "printf -v PLANWRIGHT_WORKER_SESSION_RECORD %s /x" \
  "typeset PLANWRIGHT_WORKER_SESSION_RECORD=/x" "readonly PLANWRIGHT_WORKER_SESSION_RECORD" \
  "echo \$(true) && export PLANWRIGHT_WORKER_SESSION_RECORD=/x"; do
  sync "$c"
  expect deny "[worker] '$c' denies"
  reason_has 'sets or clears PLANWRIGHT_WORKER_SESSION_RECORD' "[worker] '$c' is refused by the record-variable screen"
done
long=$(printf 'x%.0s' $(seq 1 17000))
sync "echo PLANWRIGHT_WORKER_SESSION_RECORD $long"
expect deny "[worker] an over-long command naming the record variable denies without a parse"
reason_has 'too long' "[worker] the over-long refusal says why"
for c in "printenv PLANWRIGHT_WORKER_SESSION_RECORD" "grep -n 'PLANWRIGHT_WORKER_SESSION_RECORD=' scripts/policy-guard.sh" \
  "echo \"\$PLANWRIGHT_WORKER_SESSION_RECORD\""; do
  sync "$c"
  expect defer "[worker] the read '$c' defers"
done

echo "# mentions that run nothing"
for c in "grep -n lease $H" "cat $H" "shellcheck scripts/worker-branch-sync.sh" \
  "git commit -m 'fix(worker-branch-sync): a; b | c & d'" "grep -rn 'x;worker-branch-sync' docs" \
  "bash -n scripts/worker-branch-sync.sh" "sh -n $H" "find . -name worker-branch-sync.sh" \
  "timeout 60 shellcheck scripts/worker-branch-sync.sh" "awk 1 scripts/worker-branch-sync.sh" \
  "xargs wc -l scripts/worker-branch-sync.sh" "find -name worker-branch-sync.sh" \
  "find -iname 'worker-branch-sync*' -print" "timeout 30 git diff $H" "env -u X git diff $H" \
  "timeout 5 sed -n 1,5p $H" "timeout 5 find . -name worker-branch-sync.sh" "env bash -n $H" \
  "timeout 60 bash -n $H" "env -u FOO grep x $H" "timeout -s KILL 10 shellcheck $H" \
  "flock /tmp/l shellcheck $H" "ssh host cat $H" "find . -name worker-branch-sync.sh -exec cat {} \\;" \
  "bash tests/test-worker-branch-sync.sh" "git log --oneline -- scripts/worker-branch-sync.sh" \
  "git add scripts/worker-branch-sync.sh" "sed -n 1,20p scripts/worker-branch-sync.sh"; do
  sync "$c"
  expect defer "[worker] the mention '$c' defers"
  reads none "[worker] the mention '$c' is not read as a run"
  pg tower "$c"
  expect defer "[tower] the mention '$c' defers"
done

finish
