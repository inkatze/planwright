#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: the kickoff sign-off push.
#
# Split from tests/test-policy-guard.sh to keep each file under the per-file test
# time budget; the harness and the clones are shared through tests/lib.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"
# shellcheck source=tests/lib/policy-guard-clones.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-clones.sh"

# --- the kickoff sign-off push (kickoff-spec-push.sh) ------------------------

echo "# the kickoff sign-off push"
KICKOFF_PUSH='"$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh demo'
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker "$KICKOFF_PUSH" "$SPEC" "$SPEC"
expect defer "[worker, kickoff-demo] the kickoff push on its spec branch defers to the script"
reads none "[worker, kickoff-demo] the kickoff push reads no knob"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker "bash \"\$CLAUDE_PLUGIN_ROOT/scripts/kickoff-spec-push.sh\" demo" "$SPEC" "$SPEC"
expect defer "[worker, kickoff-demo] the shell-run kickoff push defers"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker "$KICKOFF_PUSH" "$UNIT" "$UNIT"
expect deny "[worker, kickoff-demo] the kickoff push on another branch denies"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker "false && cd \"$SPEC\"; $KICKOFF_PUSH" "$UNIT" "$UNIT"
expect deny "[worker, kickoff-demo] the kickoff push after a cd the shell may skip denies"
reason_has 'cannot place it' "[worker, kickoff-demo] the unplaced kickoff push names why"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker "cd \"$SPEC\" && $KICKOFF_PUSH" "$UNIT" "$UNIT"
expect defer "[worker, kickoff-demo] the kickoff push after a cd sure to run follows it"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker '"$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh other' "$SPEC" "$SPEC"
expect deny "[worker, kickoff-demo] a kickoff push naming another spec denies"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker '"$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh demo --force' "$SPEC" "$SPEC"
expect deny "[worker, kickoff-demo] a kickoff push with an extra argument denies"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker '"$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh main' "$SPEC" "$SPEC"
expect deny "[worker, kickoff-demo] a kickoff push naming main denies"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker "$KICKOFF_PUSH && git push origin main" "$SPEC" "$SPEC"
expect deny "[worker, kickoff-demo] a chained push to main beside the kickoff push denies"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker 'git push origin planwright/demo/spec' "$SPEC" "$SPEC"
expect deny "[worker, kickoff-demo] a raw push to the spec branch still denies"
reason_has 'protected branch' "[worker, kickoff-demo] the raw spec-branch deny keeps today's text"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker 'git push -u origin planwright/demo/spec' "$SPEC" "$SPEC"
expect deny "[worker, kickoff-demo] a raw first push of the spec branch still denies"
AMEND="$SANDBOX/amend"
gitq clone "$ORIGIN" "$AMEND"
gitq -C "$AMEND" switch -c planwright/demo/amendment-2
AMEND_OTHER="$SANDBOX/amend-other"
gitq clone "$ORIGIN" "$AMEND_OTHER"
gitq -C "$AMEND_OTHER" switch -c planwright/other/amendment-2
AMEND_BAD="$SANDBOX/amend-bad"
gitq clone "$ORIGIN" "$AMEND_BAD"
gitq -C "$AMEND_BAD" switch -c planwright/demo/amendment-2b
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker "$KICKOFF_PUSH" "$AMEND" "$AMEND"
expect defer "[worker, kickoff-demo] the kickoff push on its own spec's amendment branch defers to the script"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker "$KICKOFF_PUSH" "$AMEND_OTHER" "$AMEND_OTHER"
expect deny "[worker, kickoff-demo] another spec's amendment branch denies"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker "$KICKOFF_PUSH" "$AMEND_BAD" "$AMEND_BAD"
expect deny "[worker, kickoff-demo] a non-digit amendment suffix denies"
for bad in amendment- amendment-3-1; do
  AMEND_BAD2="$SANDBOX/amend-bad-$bad"
  gitq clone "$ORIGIN" "$AMEND_BAD2"
  gitq -C "$AMEND_BAD2" switch -c "planwright/demo/$bad"
  PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker "$KICKOFF_PUSH" "$AMEND_BAD2" "$AMEND_BAD2"
  expect deny "[worker, kickoff-demo] the amendment suffix in $bad denies"
  reason_has 'amendment branches' "[worker, kickoff-demo] the $bad refusal is the wrong-branch text"
done
PLANWRIGHT_WORKER_SCOPE=task-1 pg worker "$KICKOFF_PUSH" "$AMEND" "$AMEND"
expect deny "[worker, task-1] a different scope on the amendment branch denies"
reason_has 'not the kickoff for demo' "[worker, task-1] the amendment-branch refusal says the session is not the kickoff"
reason_has "planwright/demo/amendment-2 checked out" "[worker, task-1] the amendment-branch refusal names the branch checked out"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg tower "$KICKOFF_PUSH" "$AMEND" "$AMEND"
expect deny "[tower, kickoff-demo] a non-worker tier on the amendment branch denies"
reason_has 'not the kickoff for demo' "[tower, kickoff-demo] the non-worker amendment-branch refusal says the session is not the kickoff"
reason_has "planwright/demo/amendment-2 checked out" "[tower, kickoff-demo] the non-worker amendment-branch refusal names the branch checked out"

# An amendment kickoff on a branch that tracks its origin branch and is ahead
# of it, the way a relayed amendment kickoff finds it after a first push. The
# launcher derives a session's name from its scope, so a relaunched or relayed
# kickoff takes a fresh scope: kickoff-<spec>-a<n>, then a letter or a -<word>.
AMEND_UP="$SANDBOX/amend-up"
gitq clone "$ORIGIN" "$AMEND_UP"
gitq -C "$AMEND_UP" switch -c planwright/demo/amendment-2 main
gitq -C "$AMEND_UP" commit --allow-empty -m "amendment sign-off"
gitq -C "$AMEND_UP" push -u origin planwright/demo/amendment-2
gitq -C "$AMEND_UP" commit --allow-empty -m "delta 1"
gitq -C "$AMEND_UP" commit --allow-empty -m "delta 2"
AMEND_STALE="$SANDBOX/amend-stale"
gitq clone "$ORIGIN" "$AMEND_STALE"
gitq -C "$AMEND_STALE" branch planwright/demo/spec main
gitq -C "$AMEND_STALE" switch -c planwright/demo/amendment-2 origin/planwright/demo/amendment-2
gitq -C "$AMEND_STALE" commit --allow-empty -m "delta 1"
gitq -C "$AMEND_STALE" commit --allow-empty -m "delta 2"
for scope in kickoff-demo kickoff-demo-a2 kickoff-demo-a2b kickoff-demo-a2-delta; do
  for d in "$AMEND_UP" "$AMEND_STALE"; do
    PLANWRIGHT_WORKER_SCOPE=$scope pg worker "$KICKOFF_PUSH" "$d" "$d"
    expect defer "[worker, $scope] the kickoff push on an amendment branch ahead of its origin branch defers (${d##*/})"
  done
done
for scope in kickoff-demo-a2 kickoff-demo-a2-delta; do
  PLANWRIGHT_WORKER_SCOPE=$scope pg worker "$KICKOFF_PUSH" "$SPEC" "$SPEC"
  expect deny "[worker, $scope] an amendment kickoff's push from the spec branch denies"
  reason_has 'protected branch' "[worker, $scope] the spec-branch refusal keeps today's protected-branch text"
  PLANWRIGHT_WORKER_SCOPE=$scope pg worker 'git push origin HEAD:planwright/demo/spec' "$AMEND_UP" "$AMEND_UP"
  expect deny "[worker, $scope] a raw push of the amendment onto the spec branch denies"
  reason_has 'protected branch' "[worker, $scope] the raw spec-branch refusal keeps today's text"
done
for scope in kickoff-demo-a3 kickoff-demo-a3-delta kickoff-demo-a22; do
  n=${scope#kickoff-demo-a}
  n=${n%%[!0-9]*}
  PLANWRIGHT_WORKER_SCOPE=$scope pg worker "$KICKOFF_PUSH" "$AMEND_UP" "$AMEND_UP"
  expect deny "[worker, $scope] another amendment's kickoff denies on amendment-2"
  reason_has "amendment $n's kickoff for demo pushes only planwright/demo/amendment-$n," "[worker, $scope] the refusal names the one branch that kickoff pushes"
  reason_has 'planwright/demo/amendment-2 checked out' "[worker, $scope] the refusal names the branch checked out"
  reason_has 'CLAUDE_PLUGIN_ROOT.?/scripts/kickoff-spec-push[.]sh <spec>' "[worker, $scope] the wrong-branch refusal names the accepted form"
done
for scope in kickoff-demo-a kickoff-demo-a2- \
  kickoff-demo-a2-Delta kickoff-demo-a2-x-y kickoff-demo-a2bc kickoff-demo-x kickoff-demox-a2 \
  kickoff-demo-2 kickoff-other-a2 kickoff-push-target xkickoff-demo-a2 kickoff-demo-a2_x task-1; do
  PLANWRIGHT_WORKER_SCOPE=$scope pg worker "$KICKOFF_PUSH" "$AMEND_UP" "$AMEND_UP"
  expect deny "[worker, $scope] a session that is not amendment 2's kickoff denies on amendment-2"
  reason_has 'not the kickoff for demo' "[worker, $scope] the refusal says the session is not the kickoff"
  reason_has 'planwright/demo/amendment-2 checked out' "[worker, $scope] the refusal names the branch checked out"
  if printf '%s' "$REASON" | grep -q 'targets a protected branch'; then
    fail "[worker, $scope] the refusal claims a protected target the push would not reach: $REASON"
  else
    pass "[worker, $scope] the refusal claims no protected target"
  fi
done
for scope in kickoff-demo-a2-d3 kickoff-demo-a2-9; do
  PLANWRIGHT_WORKER_SCOPE=$scope pg worker "$KICKOFF_PUSH" "$AMEND_UP" "$AMEND_UP"
  expect defer "[worker, $scope] a -<word> of lowercase letters and digits is an amendment kickoff's scope"
done
for scope in kickoff-demo-a2B kickoff-demo-a2--x; do
  PLANWRIGHT_WORKER_SCOPE=$scope pg worker "$KICKOFF_PUSH" "$AMEND_UP" "$AMEND_UP"
  expect deny "[worker, $scope] a suffix outside the amendment scope grammar denies"
  reason_has 'not the kickoff for demo' "[worker, $scope] the out-of-grammar refusal says the session is not the kickoff"
done
for d in "$UNIT" "$AMEND_OTHER"; do
  PLANWRIGHT_WORKER_SCOPE=kickoff-demo-a2 pg worker "$KICKOFF_PUSH" "$d" "$d"
  expect deny "[worker, kickoff-demo-a2] an amendment kickoff off its amendment branch denies (${d##*/})"
  reason_has "amendment 2's kickoff for demo pushes only planwright/demo/amendment-2," "[worker, kickoff-demo-a2] the off-branch refusal names the one branch it pushes (${d##*/})"
done
PLANWRIGHT_WORKER_SCOPE=kickoff-demo-a2 pg worker "false && cd \"$AMEND_UP\"; $KICKOFF_PUSH" "$UNIT" "$UNIT"
expect deny "[worker, kickoff-demo-a2] an amendment kickoff push the guard cannot place denies"
reason_has 'cannot place it' "[worker, kickoff-demo-a2] the unplaced amendment kickoff push names why"
# The guard reads the branch before the command runs, so a git command earlier
# in the same command that may move HEAD leaves the push unplaceable.
for pre in 'git switch -c planwright/demo/amendment-9 &&' 'git checkout planwright/demo/spec ;' \
  'git checkout -b planwright/demo/amendment-9 ;' 'git -C . switch planwright/demo/spec &&' \
  'git branch -m planwright/demo/amendment-9 &&' 'git symbolic-ref HEAD refs/heads/planwright/demo/amendment-9 &&' \
  'git update-ref --no-deref HEAD HEAD &&' 'git worktree add ../w9 planwright/demo/amendment-9 &&' \
  'env git switch planwright/demo/spec &&' 'git co planwright/demo/spec &&' \
  'git branch -fm planwright/demo/amendment-9 &&' 'git branch --move planwright/demo/amendment-9 &&' \
  'git branch -M planwright/demo/amendment-9 &&' 'GIT switch planwright/demo/spec &&' \
  'git rebase main planwright/demo/spec ;' 'git bisect reset planwright/demo/spec &&' \
  'git stash branch planwright/demo/amendment-9 &&' 'printf x | git update-ref --stdin &&'; do
  PLANWRIGHT_WORKER_SCOPE=kickoff-demo-a2 pg worker "$pre $KICKOFF_PUSH" "$AMEND_UP" "$AMEND_UP"
  expect deny "[worker, kickoff-demo-a2] a kickoff push after a git command that may move HEAD denies: $pre"
  reason_has 'cannot place it' "[worker, kickoff-demo-a2] the refusal after a HEAD move names why: $pre"
done
for pre in 'git switch -c planwright/demo/amendment-9 &&' 'git checkout planwright/demo/spec ;'; do
  PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker "$pre $KICKOFF_PUSH" "$AMEND_UP" "$AMEND_UP"
  expect deny "[worker, kickoff-demo] a kickoff push after a git command that may move HEAD denies: $pre"
  reason_has 'cannot place it' "[worker, kickoff-demo] the refusal after a HEAD move names why: $pre"
  PLANWRIGHT_WORKER_SCOPE=task-1 pg worker "$pre $KICKOFF_PUSH" "$AMEND_UP" "$AMEND_UP"
  expect deny "[worker, task-1] a non-kickoff push after a git command that may move HEAD denies: $pre"
  reason_has 'not the kickoff for demo' "[worker, task-1] the non-kickoff refusal after a HEAD move says so: $pre"
done
# The shell drops the quotes and backslashes that split the name, so the
# HEAD-move scan reads the command the way the shell will.
for kp in '"$CLAUDE_PLUGIN_ROOT"/scripts/kick""off-spec-push.sh demo' '"$CLAUDE_PLUGIN_ROOT"/scripts/kick\off-spec-push.sh demo'; do
  PLANWRIGHT_WORKER_SCOPE=kickoff-demo-a2 pg worker "git switch planwright/demo/spec; $kp" "$AMEND_UP" "$AMEND_UP"
  expect deny "[worker, kickoff-demo-a2] a split spelling of the push after a HEAD move denies: $kp"
  reason_has 'cannot place it' "[worker, kickoff-demo-a2] the split-spelling refusal after a HEAD move names why: $kp"
done
PLANWRIGHT_WORKER_SCOPE=kickoff-demo-a2 pg worker "git \$SUB planwright/demo/spec && $KICKOFF_PUSH" "$AMEND_UP" "$AMEND_UP"
expect deny "[worker, kickoff-demo-a2] a kickoff push after a git subcommand the guard cannot read denies"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo-a2 pg worker "git symbolic-ref HEAD && $KICKOFF_PUSH" "$AMEND_UP" "$AMEND_UP"
expect deny "[worker, kickoff-demo-a2] a symbolic-ref read before the push stays refused (fail closed)"
reason_has 'cannot place it' "[worker, kickoff-demo-a2] the symbolic-ref refusal is the unplaceable one"
for pre in 'git status &&' 'git log -1 ;' 'git branch --show-current &&' 'git diff --stat HEAD &&' 'git stash list &&' \
  'git --version &&' 'git -h ;' 'git --exec-path &&'; do
  PLANWRIGHT_WORKER_SCOPE=kickoff-demo-a2 pg worker "$pre $KICKOFF_PUSH" "$AMEND_UP" "$AMEND_UP"
  expect defer "[worker, kickoff-demo-a2] a kickoff push after a git read still defers: $pre"
done
PLANWRIGHT_WORKER_SCOPE=kickoff-demo-a2 pg worker "$KICKOFF_PUSH && git switch planwright/demo/spec" "$AMEND_UP" "$AMEND_UP"
expect deny "[worker, kickoff-demo-a2] a HEAD move after the kickoff push denies, as anything but cd or a read beside it does"
reason_has 'on its own, or after cd only' "[worker, kickoff-demo-a2] the trailing-move refusal says how to run it"
# The helper reads the launch scope and the branch when it runs, so anything
# beside the push but a cd or a read could change either after the guard's
# read: a scope rewrite, a move the guard cannot see, or a loop back edge.
for c in "PLANWRIGHT_WORKER_SCOPE=kickoff-demo $KICKOFF_PUSH" \
  "export PLANWRIGHT_WORKER_SCOPE=kickoff-demo; $KICKOFF_PUSH" \
  "unset PLANWRIGHT_WORKER_SCOPE; $KICKOFF_PUSH" \
  "PLANWRIGHT_WORKER_SCOPE= $KICKOFF_PUSH" \
  "PLANWRIGHT_WORKER_SCOPE=kickoff-demo; $KICKOFF_PUSH" \
  "declare -x PLANWRIGHT_WORKER_SCOPE=kickoff-demo; $KICKOFF_PUSH" \
  "printf -v PLANWRIGHT_WORKER_SCOPE kickoff-demo; $KICKOFF_PUSH" \
  "X=1 $KICKOFF_PUSH" \
  "sh -c 'git symbolic-ref HEAD refs/heads/planwright/demo/spec'; export PLANWRIGHT_WORKER_SCOPE=kickoff-demo; $KICKOFF_PUSH" \
  "true && $KICKOFF_PUSH" \
  "$KICKOFF_PUSH; git checkout planwright/demo/spec" \
  "for i in 1 2; do $KICKOFF_PUSH; git checkout planwright/demo/spec; done"; do
  for scope in kickoff-demo-a2 kickoff-demo; do
    PLANWRIGHT_WORKER_SCOPE=$scope pg worker "$c" "$AMEND_UP" "$AMEND_UP"
    expect deny "[worker, $scope] a kickoff push beside a command that is neither cd nor a read denies: $c"
    reason_has 'on its own, or after cd only' "[worker, $scope] the refusal says how to run it: $c"
  done
done
# printf, test and [ never stand beside the push (printf -v assigns, and test
# -v evaluates an expansion in a subscript), nor does any word holding $ or a
# backtick, quoted or not.
for c in "printf -vPLANWRIGHT_WORKER_SCOPE %s kickoff-demo; $KICKOFF_PUSH" \
  "printf -bvX %s y; $KICKOFF_PUSH" \
  "printf '%s\\n' ok; $KICKOFF_PUSH" \
  "[ -v 'a[\$(git switch planwright/demo/spec)]' ]; $KICKOFF_PUSH" \
  "test -v 'a[\$(git switch planwright/demo/spec)]'; $KICKOFF_PUSH" \
  "test -v 'a[\`git switch planwright/demo/spec\`]'; $KICKOFF_PUSH" \
  "test -f README.md && $KICKOFF_PUSH" \
  "[ -d . ] && $KICKOFF_PUSH" \
  "echo 'a\$(git switch planwright/demo/spec)'; $KICKOFF_PUSH" \
  "git log --format='\$(x)' -1; $KICKOFF_PUSH" \
  "sh -c 'git switch planwright/demo/spec'; $KICKOFF_PUSH" \
  "[ -v 'a[\$(git switch planwright/demo/spec)]' ]; printf -vPLANWRIGHT_WORKER_SCOPE %s kickoff-demo; $KICKOFF_PUSH"; do
  PLANWRIGHT_WORKER_SCOPE=kickoff-demo-a2 pg worker "$c" "$AMEND_UP" "$AMEND_UP"
  expect deny "[worker, kickoff-demo-a2] a kickoff push beside printf, test, [ or a word holding \$ or a backtick denies: $c"
  reason_has 'on its own, or after cd only' "[worker, kickoff-demo-a2] the refusal says how to run it: $c"
done
for pre in 'echo ok;' 'git log --format=%H -1 &&'; do
  PLANWRIGHT_WORKER_SCOPE=kickoff-demo-a2 pg worker "$pre $KICKOFF_PUSH" "$AMEND_UP" "$AMEND_UP"
  expect defer "[worker, kickoff-demo-a2] a kickoff push after a plain read defers: $pre"
done
for scope in kickoff-demo-a2 kickoff-demo-a2-delta kickoff-demo; do
  PLANWRIGHT_WORKER_SCOPE=$scope pg worker "cd \"$AMEND_UP\" && $KICKOFF_PUSH" "$UNIT" "$UNIT"
  expect defer "[worker, $scope] the kickoff push after cd alone defers"
  PLANWRIGHT_WORKER_SCOPE=$scope pg worker "$KICKOFF_PUSH && git status" "$AMEND_UP" "$AMEND_UP"
  expect defer "[worker, $scope] the kickoff push followed by a read defers"
done
PLANWRIGHT_WORKER_SCOPE=task-1 pg worker "export PLANWRIGHT_WORKER_SCOPE=kickoff-demo; $KICKOFF_PUSH" "$AMEND_UP" "$AMEND_UP"
expect deny "[worker, task-1] a non-kickoff session rewriting its scope stays refused"
reason_has 'not the kickoff for demo' "[worker, task-1] the scope-rewrite refusal for a non-kickoff session says it is not the kickoff"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo-a2-delta pg worker "$KICKOFF_PUSH" "$AMEND_STALE" "$AMEND_STALE"
expect defer "[worker, kickoff-demo-a2-delta] a stale local spec branch beside the amendment does not move the decision"
PLANWRIGHT_WORKER_SCOPE=task-1 pg worker "$KICKOFF_PUSH" "$AMEND_STALE" "$AMEND_STALE"
reason_has 'planwright/demo/amendment-2 checked out' "[worker, task-1] with a stale local spec branch, the refusal names the amendment branch"
PLANWRIGHT_WORKER_SCOPE=task-1 pg worker "$KICKOFF_PUSH" "$UNIT" "$UNIT"
expect deny "[worker, task-1] a non-kickoff session on a unit branch denies"
reason_has 'not the kickoff for demo' "[worker, task-1] the unit-branch refusal says the session is not the kickoff"
reason_has 'planwright/demo/task-1 checked out' "[worker, task-1] the unit-branch refusal names the branch checked out"
for tier in tower mission-control; do
  PLANWRIGHT_WORKER_SCOPE=kickoff-demo-a2-delta pg "$tier" "$KICKOFF_PUSH" "$AMEND_UP" "$AMEND_UP"
  expect deny "[$tier, kickoff-demo-a2-delta] a non-worker tier never runs an amendment kickoff push"
  reason_has 'not the kickoff for demo' "[$tier, kickoff-demo-a2-delta] the refusal says the session is not the kickoff"
  if printf '%s' "$REASON" | grep -q 'targets a protected branch'; then
    fail "[$tier, kickoff-demo-a2-delta] the refusal claims a protected target the push would not reach: $REASON"
  else
    pass "[$tier, kickoff-demo-a2-delta] the refusal claims no protected target"
  fi
done

# A relayed amendment kickoff in a linked worktree with the
# amendment branch checked out directly (no flight branch, no local spec
# branch), tracking its origin branch and ahead of it.
MC_PRIMARY="$SANDBOX/mc-primary"
gitq clone "$ORIGIN" "$MC_PRIMARY"
gitq -C "$MC_PRIMARY" switch -c planwright/mission-control/amendment-16 main
gitq -C "$MC_PRIMARY" commit --allow-empty -m "amendment 16 sign-off"
gitq -C "$MC_PRIMARY" push -u origin planwright/mission-control/amendment-16
gitq -C "$MC_PRIMARY" switch main
MC_A16="$SANDBOX/mc-a16"
gitq -C "$MC_PRIMARY" worktree add "$MC_A16" planwright/mission-control/amendment-16
gitq -C "$MC_A16" commit --allow-empty -m "delta 1"
gitq -C "$MC_A16" commit --allow-empty -m "delta 2"
MC_A17="$SANDBOX/mc-a17"
gitq -C "$MC_PRIMARY" worktree add -b planwright/mission-control/amendment-17 "$MC_A17" main
MC_A1="$SANDBOX/mc-a1"
gitq -C "$MC_PRIMARY" worktree add -b planwright/mission-control/amendment-1 "$MC_A1" main
KICK_MC='${CLAUDE_PLUGIN_ROOT}/scripts/kickoff-spec-push.sh mission-control'
PLANWRIGHT_WORKER_SCOPE=kickoff-mission-control-a16-delta pg worker "$KICK_MC" "$MC_A16" "$MC_A16"
expect defer "[worker, kickoff-mission-control-a16-delta] relayed amendment case: the relayed amendment-16 kickoff push is admitted"
reads none "[worker, kickoff-mission-control-a16-delta] relayed amendment case: the admitted push reads no knob"
PLANWRIGHT_WORKER_SCOPE=kickoff-mission-control-a16-delta pg worker "$KICK_MC" "$MC_A17" "$MC_A17"
expect deny "[worker, kickoff-mission-control-a16-delta] relayed amendment case: the a16 scope on amendment-17 denies"
reason_has 'planwright/mission-control/amendment-17 checked out' "[worker, kickoff-mission-control-a16-delta] relayed amendment case: the amendment-17 refusal names the branch checked out"
reason_has "amendment 16's kickoff for mission-control pushes only planwright/mission-control/amendment-16," "[worker, kickoff-mission-control-a16-delta] relayed amendment case: the amendment-17 refusal names the one branch amendment 16's kickoff pushes"
for scope in kickoff-mission-control-a1 kickoff-mission-control-a160; do
  PLANWRIGHT_WORKER_SCOPE=$scope pg worker "$KICK_MC" "$MC_A16" "$MC_A16"
  expect deny "[worker, $scope] another amendment number's scope denies on amendment-16"
  reason_has "amendment ${scope#kickoff-mission-control-a}'s kickoff for mission-control pushes only" "[worker, $scope] the refusal names that scope's own amendment"
done
PLANWRIGHT_WORKER_SCOPE=kickoff-mission-control-a16-delta pg worker "$KICK_MC" "$MC_A1" "$MC_A1"
expect deny "[worker, kickoff-mission-control-a16-delta] an a16 scope denies on amendment-1"
reason_has 'planwright/mission-control/amendment-1 checked out' "[worker, kickoff-mission-control-a16-delta] the amendment-1 refusal names the branch checked out"
PLANWRIGHT_WORKER_SCOPE=kickoff-mission-control-a10b pg worker "$KICK_MC" "$MC_A16" "$MC_A16"
expect deny "[worker, kickoff-mission-control-a10b] amendment 10's relaunch scope denies on amendment-16"
reason_has "amendment 10's kickoff for mission-control pushes only" "[worker, kickoff-mission-control-a10b] the refusal reads the relaunch scope as amendment 10's"
PLANWRIGHT_WORKER_SCOPE=kickoff-mission-control-a16-delta pg worker "git rebase main planwright/mission-control/amendment-17 ; $KICK_MC" "$MC_A16" "$MC_A16"
expect deny "[worker, kickoff-mission-control-a16-delta] a kickoff push after a two-argument rebase in a linked worktree denies"
reason_has 'cannot place it' "[worker, kickoff-mission-control-a16-delta] the refusal after a rebase that checks out a branch names why"
mkdir -p "$MC_A16/specs/mission-control"
PLANWRIGHT_WORKER_SCOPE=kickoff-mission-control-a16-delta pg worker "$KICK_MC" "$MC_A16" "$MC_A16"
expect defer "[worker, kickoff-mission-control-a16-delta] relayed amendment case: admitted with its own spec under the spec root and no colliding one"

# An amendment kickoff's scope that is also another spec's kickoff scope: a
# spec named <spec>-a<n> (or the scope's whole tail) under the spec root.
AMEND_COL="$SANDBOX/amend-col"
gitq clone "$ORIGIN" "$AMEND_COL"
gitq -C "$AMEND_COL" switch -c planwright/demo/amendment-2 main
mkdir -p "$AMEND_COL/specs/demo" "$AMEND_COL/specs/demo-a2" "$AMEND_COL/specs/demo-a2b"
for scope in kickoff-demo-a2 kickoff-demo-a2-a3 kickoff-demo-a2b; do
  PLANWRIGHT_WORKER_SCOPE=$scope pg worker "$KICKOFF_PUSH" "$AMEND_COL" "$AMEND_COL"
  expect deny "[worker, $scope] an amendment scope another spec's kickoff can share denies"
  reason_has "reads as amendment 2's kickoff for demo, but a spec named demo-a2b? exists" "[worker, $scope] the collision refusal names the other spec"
  reason_has 'Relaunch the kickoff with a scope no other spec' "[worker, $scope] the collision refusal's remedy is a fresh scope"
done
# A scope that also reads as an amendment kickoff of a shorter spec: demo's
# amendment 1 with the word a2 is also demo-a1's amendment 2.
AMEND_PRE="$SANDBOX/amend-pre"
gitq clone "$ORIGIN" "$AMEND_PRE"
gitq -C "$AMEND_PRE" switch -c planwright/demo-a1/amendment-2 main
mkdir -p "$AMEND_PRE/specs/demo-a1"
KICK_PRE='"$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh demo-a1'
for scope in kickoff-demo-a1-a2 kickoff-demo-a1-a2b; do
  PLANWRIGHT_WORKER_SCOPE=$scope pg worker "$KICK_PRE" "$AMEND_PRE" "$AMEND_PRE"
  expect defer "[worker, $scope] with no shorter spec it could belong to, the amendment kickoff push defers"
done
mkdir -p "$AMEND_PRE/specs/demo"
for scope in kickoff-demo-a1-a2 kickoff-demo-a1-a2b; do
  PLANWRIGHT_WORKER_SCOPE=$scope pg worker "$KICK_PRE" "$AMEND_PRE" "$AMEND_PRE"
  expect deny "[worker, $scope] a scope a shorter spec's amendment kickoff can share denies"
  reason_has "reads as amendment 2's kickoff for demo-a1, but a spec named demo exists, whose amendment 1 kickoff that scope is" "[worker, $scope] the shorter-spec collision names that spec and its amendment"
  reason_has 'Relaunch the kickoff with a scope no other spec' "[worker, $scope] the shorter-spec collision's remedy is a fresh scope"
done
PLANWRIGHT_WORKER_SCOPE=kickoff-demo-a1-a2-x pg worker "$KICK_PRE" "$AMEND_PRE" "$AMEND_PRE"
expect defer "[worker, kickoff-demo-a1-a2-x] a scope outside the shorter spec's amendment grammar still defers"
# A colliding bundle the worktree does not hold but the primary checkout does.
mkdir -p "$MC_PRIMARY/specs/mission-control-a16-delta"
PLANWRIGHT_WORKER_SCOPE=kickoff-mission-control-a16-delta pg worker "$KICK_MC" "$MC_A16" "$MC_A16"
expect deny "[worker, kickoff-mission-control-a16-delta] a colliding bundle only in the primary checkout denies"
reason_has 'a spec named mission-control-a16-delta exists' "[worker, kickoff-mission-control-a16-delta] the primary-only collision names the other spec"
rmdir "$MC_PRIMARY/specs/mission-control-a16-delta"
PLANWRIGHT_WORKER_SCOPE=kickoff-mission-control-a16-delta pg worker "$KICK_MC" "$MC_A16" "$MC_A16"
expect defer "[worker, kickoff-mission-control-a16-delta] admitted again once the primary holds no colliding bundle"
# The resolver's own failures each name their own remedy, never a relaunch.
STUB_ROOT=empty PLANWRIGHT_WORKER_SCOPE=kickoff-mission-control-a16-delta pg worker "$KICK_MC" "$MC_A16" "$MC_A16"
expect deny "[worker, kickoff-mission-control-a16-delta] an empty spec-root answer denies"
reason_has 'spec root could not be resolved' "[worker, kickoff-mission-control-a16-delta] the empty-answer refusal says why"
reason_has 'Repair spec_root' "[worker, kickoff-mission-control-a16-delta] the empty-answer refusal's remedy is the spec_root repair"
STUB_ROOT=hang PG_TIMEOUT=1 PLANWRIGHT_WORKER_SCOPE=kickoff-mission-control-a16-delta pg worker "$KICK_MC" "$MC_A16" "$MC_A16"
expect deny "[worker, kickoff-mission-control-a16-delta] a spec-root read past its bound denies"
reason_has 'did not finish within 1s' "[worker, kickoff-mission-control-a16-delta] the timeout refusal names the bound"
reason_has 'retry' "[worker, kickoff-mission-control-a16-delta] the timeout refusal's remedy is a retry"
mv "$S/resolve-root.sh" "$S/resolve-root.sh.away"
PLANWRIGHT_WORKER_SCOPE=kickoff-mission-control-a16-delta pg worker "$KICK_MC" "$MC_A16" "$MC_A16"
expect deny "[worker, kickoff-mission-control-a16-delta] a missing spec-root resolver denies"
reason_has 'resolver is missing beside this guard' "[worker, kickoff-mission-control-a16-delta] the missing-resolver refusal says why"
reason_has 'Reinstall planwright' "[worker, kickoff-mission-control-a16-delta] the missing-resolver refusal's remedy is a reinstall"
mv "$S/resolve-root.sh.away" "$S/resolve-root.sh"
for r in empty hang; do
  STUB_ROOT=$r PG_TIMEOUT=1 PLANWRIGHT_WORKER_SCOPE=kickoff-mission-control-a16-delta pg worker "$KICK_MC" "$MC_A16" "$MC_A16"
  if printf '%s' "$REASON" | grep -q 'Relaunch'; then
    fail "[worker, kickoff-mission-control-a16-delta] a resolver failure ($r) prescribes a relaunch: $REASON"
  else
    pass "[worker, kickoff-mission-control-a16-delta] a resolver failure ($r) prescribes no relaunch"
  fi
done
PLANWRIGHT_WORKER_SCOPE=kickoff-demo-a2-delta pg worker "$KICKOFF_PUSH" "$AMEND_COL" "$AMEND_COL"
expect defer "[worker, kickoff-demo-a2-delta] a scope no existing spec's kickoff shares is admitted beside a demo-a2 spec"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker "$KICKOFF_PUSH" "$AMEND_COL" "$AMEND_COL"
expect defer "[worker, kickoff-demo] the spec's own kickoff scope is admitted beside a demo-a2 spec"
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: allow' 'unpushed_rewrite: allow' "spec_root: $SANDBOX/no-such-spec-root"
PLANWRIGHT_WORKER_SCOPE=kickoff-mission-control-a16-delta pg worker "$KICK_MC" "$MC_A16" "$MC_A16"
expect deny "[worker, kickoff-mission-control-a16-delta] an amendment scope denies when the spec root cannot be resolved"
reason_has 'spec root could not be resolved' "[worker, kickoff-mission-control-a16-delta] the unresolvable-root refusal says why"
reason_has 'Repair spec_root' "[worker, kickoff-mission-control-a16-delta] the unresolvable-root refusal's remedy is the spec_root repair"
PLANWRIGHT_WORKER_SCOPE=kickoff-mission-control pg worker "$KICK_MC" "$MC_A16" "$MC_A16"
expect defer "[worker, kickoff-mission-control] the spec's own kickoff scope reads no spec root"
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: allow' 'unpushed_rewrite: allow'
PLANWRIGHT_WORKER_SCOPE=task-1 pg worker 'PLANWRIGHT_WORKER_SCOPE=kickoff-demo-a2 "$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh demo' "$AMEND_UP" "$AMEND_UP"
expect deny "[worker, task-1] an inline amendment-kickoff scope does not admit the push"
PLANWRIGHT_WORKER_SCOPE=task-1 pg worker "false && cd \"$AMEND_UP\"; $KICKOFF_PUSH" "$UNIT" "$UNIT"
expect deny "[worker, task-1] a non-kickoff push the guard cannot place denies"
reason_has 'not the kickoff for demo' "[worker, task-1] the unplaced non-kickoff refusal says the session is not the kickoff"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker "$KICKOFF_PUSH" "$UNIT" "$UNIT"
reason_has 'CLAUDE_PLUGIN_ROOT.?/scripts/kickoff-spec-push[.]sh <spec>' "[worker, kickoff-demo] the wrong-branch refusal names the accepted form"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker './kickoff-spec-push.sh demo' "$SPEC" "$SPEC"
reason_has 'CLAUDE_PLUGIN_ROOT.?/scripts/kickoff-spec-push[.]sh <spec>' "[worker, kickoff-demo] the unreadable-form refusal names the accepted form"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker 'echo "kickoff-spec-push" demo' "$SPEC" "$SPEC"
reason_has 'CLAUDE_PLUGIN_ROOT.?/scripts/kickoff-spec-push[.]sh <spec>' "[worker, kickoff-demo] the unreadable-spelling refusal names the accepted form"
PLANWRIGHT_WORKER_SCOPE=task-1 pg worker "$KICKOFF_PUSH" "$SPEC" "$SPEC"
expect deny "[worker, task-1] a non-kickoff worker's kickoff-push denies"
reason_has 'protected branch' "[worker, task-1] the refusal keeps today's text"
PLANWRIGHT_WORKER_SCOPE='' pg worker "$KICKOFF_PUSH" "$SPEC" "$SPEC"
expect deny "[worker, no scope] a worker with no scope denies the kickoff push"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg tower "$KICKOFF_PUSH" "$SPEC" "$SPEC"
expect deny "[tower, kickoff-demo] the tower never runs the kickoff push"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg mission-control "$KICKOFF_PUSH" "$SPEC" "$SPEC"
expect deny "[mission-control, kickoff-demo] mission control never runs the kickoff push"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg '' "$KICKOFF_PUSH" "$SPEC" "$SPEC"
expect defer "[no tier, kickoff-demo] outside jurisdiction, so the guard defers"
for cmd in '"$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh' \
  'sh "$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh' \
  'bash -c '"'"'"$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh demo'"'"'' \
  'sh -s demo < "$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh' \
  'env "$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh demo' \
  '"$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh demo; "$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh other' \
  'X=kickoff-spec-push.sh; "$CLAUDE_PLUGIN_ROOT"/scripts/$X demo' \
  'echo "kickoff-spec-push" demo'; do
  PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker "$cmd" "$SPEC" "$SPEC"
  expect deny "[worker, kickoff-demo] an unreadable kickoff spelling denies: $cmd"
done
# A command the tokenizer refuses never reaches kickoff_segment, so naming the
# kickoff push there is refused at every tier.
for cmd in "{ $KICKOFF_PUSH; }" "($KICKOFF_PUSH)" "x=\$(true); $KICKOFF_PUSH" "cat <<E
x
E\\

$KICKOFF_PUSH
E"; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$SPEC" "$SPEC"
    expect deny "[$tier, task-1] a kickoff push in a command the guard cannot parse denies: ${cmd//$'\n'/ \\n }"
    reason_has 'will not analyze' "[$tier, task-1] the deny names the unparsed construct: ${cmd//$'\n'/ \\n }"
  done
done
# An empty expansion splices the name back together for the shell, so the name
# check reads the command with those splices removed.
for cmd in 'kic$()koff-spec-push.sh demo' 'kic``koff-spec-push.sh demo' 'kic${}koff-spec-push.sh demo' \
  'kic$""koff-spec-push.sh demo' 'KIC$()KOFF-SPEC-PUSH.SH demo'; do
  PLANWRIGHT_WORKER_SCOPE=task-1 pg worker "$cmd" "$SPEC" "$SPEC"
  expect deny "[worker, task-1] a kickoff push spliced with an empty expansion denies: $cmd"
  reason_has 'will not analyze|cannot read' "[worker, task-1] the spliced kickoff push names the unparsed construct: $cmd"
done
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker '"$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh demo && git status' "$SPEC" "$SPEC"
expect defer "[worker, kickoff-demo] a kickoff push chained with a read defers"
PLANWRIGHT_WORKER_SCOPE=task-1 pg worker 'PLANWRIGHT_WORKER_SCOPE=kickoff-demo "$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh demo' "$SPEC" "$SPEC"
expect deny "[worker, task-1] an inline scope assignment does not admit the kickoff push"
PLANWRIGHT_WORKER_SCOPE=task-1 pg worker 'sh /opt/planwright/scripts/kickoff-spec-push.sh demo' "$SPEC" "$SPEC"
expect deny "[worker, task-1] a literal-path kickoff push without a git word still denies"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker 'sh "$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh demo' "$SPEC" "$SPEC"
expect defer "[worker, kickoff-demo] a shell-run kickoff push through the plugin root defers to the script"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker 'sh /opt/planwright/scripts/kickoff-spec-push.sh demo' "$SPEC" "$SPEC"
expect deny "[worker, kickoff-demo] a literal absolute path to the script is refused (a checkout copy could be named the same)"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker 'GIT_DIR=/other/repo/.git "$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh demo' "$SPEC" "$SPEC"
expect deny "[worker, kickoff-demo] a kickoff push with a GIT_ variable set denies"
reason_has 'GIT_' "[worker, kickoff-demo] the GIT_ refusal says why"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker 'export GIT_INDEX_FILE=/x; "$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh demo' "$SPEC" "$SPEC"
expect deny "[worker, kickoff-demo] a kickoff push after an exported GIT_ variable denies"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker '"$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh flight' "$SPEC" "$SPEC"
expect deny "[worker, kickoff-demo] a kickoff push naming the flight namespace denies"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker "\"\$CLAUDE_PLUGIN_ROOT\"/scripts/kickoff-spec-push.sh $(printf 'a%.0s' $(seq 1 65))" "$SPEC" "$SPEC"
expect deny "[worker, kickoff-demo] a kickoff push naming a spec over 64 characters denies"
PLANWRIGHT_WORKER_SCOPE=task-1 pg worker '"$CLAUDE_PLUGIN_ROOT"/scripts/kickoff-spec-push.sh kickoff-spec-push' "$SPEC" "$SPEC"
expect deny "[worker, task-1] a spec named like the script is not a kickoff push, and its refusal is the kickoff decision's text"
reason_has 'not the kickoff for kickoff-spec-push ' "[worker, task-1] the spec-named-like-the-script refusal is the not-the-kickoff text for that spec, not a spelling refusal"
if printf '%s' "$REASON" | grep -q 'spelling'; then
  fail "[worker, task-1] the spec-named-like-the-script refusal is a spelling refusal: $REASON"
else
  pass "[worker, task-1] the spec-named-like-the-script refusal is no spelling refusal"
fi
for cmd in './kickoff-spec-push.sh demo' '/tmp/evil/kickoff-spec-push.sh demo' 'bash ./kickoff-spec-push.sh demo'; do
  PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker "$cmd" "$SPEC" "$SPEC"
  expect deny "[worker, kickoff-demo] a same-named file outside scripts/ is not the kickoff script: $cmd"
done

# The script is matched as a command word (a run of it), not as any word that
# contains its name: its test file, a read or a stage of it, and a note that
# mentions it pass to the ordinary rules.
echo "# the kickoff push is matched as a run, not as any mention"
for cmd in 'bash tests/test-kickoff-spec-push.sh' \
  'git add scripts/kickoff-spec-push.sh' \
  'git add scripts/kickoff-spec-push.sh tests/test-kickoff-spec-push.sh' \
  'git -C /some/worktree add scripts/kickoff-spec-push.sh' \
  'git diff scripts/kickoff-spec-push.sh' \
  'git diff --stat -- scripts/kickoff-spec-push.sh' \
  'git show HEAD:scripts/kickoff-spec-push.sh' \
  'git log --oneline -- scripts/kickoff-spec-push.sh' \
  'git commit -m "fix: kickoff-spec-push.sh quoting"' \
  'grep -rln kickoff-spec-push hooks scripts' \
  'grep -n foo scripts/kickoff-spec-push.sh' \
  'grep -rn "kickoff-spec-push.sh" scripts tests' \
  'cat scripts/kickoff-spec-push.sh' \
  'cat scripts/kickoff-spec-push.sh | head -5' \
  'shellcheck scripts/kickoff-spec-push.sh' \
  'wc -l scripts/kickoff-spec-push.sh tests/test-kickoff-spec-push.sh' \
  'timeout 500 bash tests/test-kickoff-spec-push.sh' \
  'bash tests/test-kickoff-spec-push.sh && git add scripts/kickoff-spec-push.sh' \
  'fleet-remote.sh --host mac compute --worktree /some/worktree --test tests/test-kickoff-spec-push.sh --timeout 540' \
  'git log --oneline fix/kickoff-spec-push-quoting' \
  'bash tests/kickoff-spec-push-helpers.sh' \
  'git status scripts/kickoff-spec-push.sh' \
  'git grep foo -- scripts/kickoff-spec-push.sh' \
  'git rm --cached scripts/kickoff-spec-push.sh' \
  'rg foo scripts/kickoff-spec-push.sh' \
  'ls -l scripts/kickoff-spec-push.sh' \
  '[ -f scripts/kickoff-spec-push.sh ]' \
  'test -x scripts/kickoff-spec-push.sh' \
  'git add scripts/kickoff-spec-push.sh scripts/kickoff-spec-push.sh' \
  'cat scripts/kickoff-spec-push.sh | cat | wc -l' \
  "printf '%s\\n' 'note: scripts/kickoff-spec-push.sh needs a fix'" \
  'echo "see scripts/kickoff-spec-push.sh for the push"' \
  'find scripts -name kickoff-spec-push.sh' \
  'find scripts -type f -name kickoff-spec-push.sh -print' \
  'sed -n 1,5p scripts/kickoff-spec-push.sh' \
  'sed -n 3p scripts/kickoff-spec-push.sh' \
  'chmod +x scripts/kickoff-spec-push.sh' \
  'chmod 755 scripts/kickoff-spec-push.sh' \
  'chmod u+x,g-w scripts/kickoff-spec-push.sh' \
  'git log --oneline --grep=kickoff-spec-push.sh' \
  'git log --oneline --grep kickoff-spec-push.sh' \
  'cat scripts/kickoff-spec-push.sh | git diff --no-index --stat -- - scripts/other.sh' \
  'cat scripts/kickoff-spec-push.sh | grep -c foo' \
  'sed -n 2,$p scripts/kickoff-spec-push.sh' \
  'shellcheck scripts/*.sh tests/*.sh' \
  'bash tests/test-*.sh' \
  'ls scripts/kickoff-spec-p*' \
  'git add scripts/kick*.sh' \
  'bash scripts/mykickoff-spec-push.sh.bak demo' \
  'grep -rn --xkickoff-spec-push.sh .' \
  'cat scripts/kickoff-spec-push.sh | A=1; make test' \
  'cat scripts/kick{off,x}-spec-push.sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd"
    expect defer "[$tier, task-1] a mention of the kickoff push that is no run of it defers: $cmd"
  done
done
# Every form that runs the script stays refused, wherever the guard can read
# it and where it cannot.
for cmd in 'scripts/kickoff-spec-push.sh demo' \
  './scripts/kickoff-spec-push.sh demo' \
  '/opt/planwright/scripts/kickoff-spec-push.sh demo' \
  '"$ROOT"/scripts/kickoff-spec-push.sh demo' \
  'bash scripts/kickoff-spec-push.sh demo' \
  'sh -x scripts/kickoff-spec-push.sh demo' \
  'bash -c "scripts/kickoff-spec-push.sh demo"' \
  'env X=1 scripts/kickoff-spec-push.sh demo' \
  'exec scripts/kickoff-spec-push.sh demo' \
  'timeout 5 scripts/kickoff-spec-push.sh demo' \
  'nohup scripts/kickoff-spec-push.sh demo' \
  'find . -exec scripts/kickoff-spec-push.sh demo {} +' \
  'true; scripts/kickoff-spec-push.sh demo' \
  'true && scripts/kickoff-spec-push.sh demo' \
  'false || scripts/kickoff-spec-push.sh demo' \
  'echo x | scripts/kickoff-spec-push.sh demo' \
  'cat scripts/kickoff-spec-push.sh | sh' \
  'grep -n foo scripts/kickoff-spec-push.sh | bash' \
  "printf 'scripts/kickoff-spec-push.sh demo\\n' | sh" \
  'echo scripts/kickoff-spec-push.sh | xargs bash' \
  'sh -s demo < scripts/kickoff-spec-push.sh' \
  'git -c core.pager=scripts/kickoff-spec-push.sh diff' \
  'git -c alias.x="!scripts/kickoff-spec-push.sh demo" x' \
  'git grep -Oscripts/kickoff-spec-push.sh foo' \
  'rg --pre scripts/kickoff-spec-push.sh foo .' \
  'bash scripts/kickoff-spec-push.s? demo' \
  'bash scripts/kickoff-spec-push.* demo' \
  'bash scripts/kickoff-spec-push[.]sh demo' \
  "find scripts -name 'kickoff-spec-push*' -exec bash {} demo \\;" \
  'bash scripts/$1kickoff-spec-push.sh demo' \
  'env X=1 scripts/$1kickoff-spec-push.sh demo' \
  'bash kickoff-spec-push demo' \
  'echo scripts/kickoff-spec-push.sh' \
  "printf '%s\\n' scripts/kickoff-spec-push.sh" \
  'cat scripts/kickoff-spec-push.sh | cat | sh' \
  'cat scripts/kickoff-spec-push.sh | tr -d x | bash' \
  'cat scripts/kickoff-spec-push.sh |& sh' \
  'git add scripts/kickoff-spec-push.sh && scripts/kickoff-spec-push.sh demo' \
  "echo 'scripts/kickoff-spec-push.sh demo' > wrapper.sh" \
  'cat scripts/kickoff-spec-push.sh > copy.sh' \
  'cat < scripts/kickoff-spec-push.sh' \
  'git show HEAD:scripts/kickoff-spec-push.sh > copy.sh' \
  'git mv scripts/kickoff-spec-push.sh scripts/other.sh' \
  'git grep -Obash foo scripts/kickoff-spec-push.sh' \
  'git grep --open-files-in-pager=bash foo -- scripts/kickoff-spec-push.sh' \
  'git grep -nObash foo scripts/kickoff-spec-push.sh' \
  'git grep --open=bash foo scripts/kickoff-spec-push.sh' \
  'git show HEAD:scripts/kickoff-spec-push.sh --output=copy.sh' \
  'uniq scripts/kickoff-spec-push.sh copy.sh' \
  'bash scripts/kickoff-spec-push.sh.bak' \
  "S=/; bash scripts\$S'kickoff-spec-push.sh' demo" \
  'git bisect run scripts/kickoff-spec-push.sh' \
  'git rebase -x scripts/kickoff-spec-push.sh' \
  'GIT_EXTERNAL_DIFF=bash git diff scripts/kickoff-spec-push.sh' \
  'source scripts/kickoff-spec-push.sh' \
  '. scripts/kickoff-spec-push.sh' \
  'eval "$(cat scripts/kickoff-spec-push.sh)"' \
  'Scripts/KICKOFF-SPEC-PUSH.SH demo' \
  'GIT_EXTERNAL_DIFF=scripts/kickoff-spec-push.sh git diff HEAD~1' \
  'PAGER=scripts/kickoff-spec-push.sh git log' \
  'cat <<E
scripts/kickoff-spec-push.sh demo
E' \
  'X=scripts/kickoff-spec-push.sh; $X demo' \
  'S=kickoff-spec-push.sh; scripts/$S demo' \
  '(scripts/kickoff-spec-push.sh demo)' \
  '$(scripts/kickoff-spec-push.sh demo)' \
  '`scripts/kickoff-spec-push.sh demo`' \
  "cat scripts/kickoff-spec-push.sh | git -c alias.x='!sh' x" \
  'cat scripts/kickoff-spec-push.sh | git -c core.pager=sh log' \
  'cat scripts/kickoff-spec-push.sh | git grep -Obash foo' \
  'cat scripts/kickoff-spec-push.sh | cat > copy.sh' \
  'cat scripts/kickoff-spec-push.sh | tee copy.sh' \
  'cat scripts/kickoff-spec-push.sh | wc -c > copy.sh' \
  'cat scripts/kickoff-spec-push.sh | GIT_EXTERNAL_DIFF=bash git diff' \
  'cat scripts/kickoff-spec-push.sh | rg --pre bash foo' \
  'cat scripts/kickoff-spec-push.sh | /bin/sh' \
  'git grep -Okickoff-spec-push.sh -e pat' \
  'git grep -nOkickoff-spec-push.sh -e pat' \
  "git grep -O'kickoff-spec-push.sh' -e pat" \
  'git grep -Oscripts/kickoff-spec-push.sh -e pat' \
  'git grep -Okickoff-spec-push.sh -e pat -- scripts' \
  "bash scripts/kickoff-spec-'push.sh' demo" \
  "bash scripts/kick'off-spec-push.sh' demo" \
  'bash scripts/"kickoff-spec-push".sh demo' \
  'bash scripts/kickoff-spec-\push.sh demo' \
  '/bin/bash scripts/kickoff-spec-push.sh demo' \
  '/usr/bin/env scripts/kickoff-spec-push.sh demo' \
  '/usr/bin/timeout 5 scripts/kickoff-spec-push.sh demo' \
  '/usr/bin/git add scripts/kickoff-spec-push.sh && /bin/sh scripts/kickoff-spec-push.sh demo' \
  '/bin/cat scripts/kickoff-spec-push.sh | /bin/sh' \
  'rg --pre bash foo scripts/kickoff-spec-push.sh' \
  'rg --pre=bash foo scripts/kickoff-spec-push.sh' \
  'rg --hostname-bin bash foo scripts/kickoff-spec-push.sh' \
  'find scripts -name kickoff-spec-push.sh -exec bash {} demo \;' \
  'find scripts -name kickoff-spec-push.sh -execdir bash {} demo \;' \
  'find scripts -name kickoff-spec-push.sh -ok bash {} \;' \
  'find scripts -name kickoff-spec-push.sh -delete' \
  'find scripts -name kickoff-spec-push.sh -fprint copy.sh' \
  'find scripts -name kickoff-spec-push.sh -fls copy.sh' \
  'sed -n 1,5w copy.sh scripts/kickoff-spec-push.sh' \
  'sed -i s/a/b/ scripts/kickoff-spec-push.sh' \
  'sed -n 1,5p scripts/kickoff-spec-push.sh > copy.sh' \
  'sed -n e scripts/kickoff-spec-push.sh' \
  'chmod +x scripts/kickoff-spec-push.sh && scripts/kickoff-spec-push.sh demo' \
  'chmod --reference=scripts/kickoff-spec-push.sh copy.sh' \
  'chmod -R +x scripts/kickoff-spec-push.sh' \
  'git log --grep=kickoff-spec-push.sh --output=copy.sh' \
  'git -c core.pager=sh log --grep=kickoff-spec-push.sh' \
  'git grep -5Okickoff-spec-push.sh foo' \
  'git grep -n5Okickoff-spec-push.sh foo' \
  'git grep -e foo -5Okickoff-spec-push.sh .' \
  'cat scripts/kickoff-spec-push.sh | > copy.sh' \
  'cat scripts/kickoff-spec-push.sh |& > copy.sh' \
  'cat scripts/kickoff-spec-push.sh | git apply' \
  'sed -n 1,5p scripts/kickoff-spec-push.sh -i' \
  'chmod +x copy.sh --reference=scripts/kickoff-spec-push.sh' \
  'bash scripts/kick[o]ff-spec-push.sh spec' \
  'bash scripts/k*-spec-push.sh spec' \
  'sh scripts/kickoff-spec-p*.sh spec' \
  'bash scripts/kickoff-spec-p?sh.sh spec' \
  'timeout 5 bash scripts/ki*off-spec-push.sh spec' \
  'cp scripts/k*ff-spec-push.sh c.sh' \
  'cat x > scripts/kickoff-spec-p*.sh' \
  '. scripts/kic${E}koff-spec-push.sh' \
  'source scripts/kic${E}koff-spec-push.sh spec' \
  'nohup bash scripts/kic${E}koff-spec-push.sh spec' \
  'rg --grep=kickoff-spec-push.sh foo' \
  'echo --grep=kickoff-spec-push.sh' \
  'find scripts/kickoff-spec-push.sh -ex${Z}ec bash {} \;' \
  'sed -n 1p scripts/kickoff-spec-push.sh ${Z}-e x' \
  'rg ${Z}--pre bash x scripts/kickoff-spec-push.sh' \
  'git grep ${Z}-Obash . scripts/kickoff-spec-push.sh' \
  'git show HEAD:scripts/kickoff-spec-push.sh ${Z}--output=w.sh' \
  "echo 'run scripts/kickoff-spec-push.sh demo' | if ls; then sh; fi" \
  "echo 'run scripts/kickoff-spec-push.sh demo' | while ls; do sh; done" \
  'env scripts/kick{off,x}-spec-push.sh myspec' \
  'env scripts/kick{,}off-spec-push.sh myspec' \
  'env scripts/kickoff-spec-pus{h,}.sh myspec' \
  'export GIT_EXTERNAL_DIFF=bash; git diff scripts/kickoff-spec-push.sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd"
    expect deny "[$tier, task-1] a run of the kickoff push stays refused: $cmd"
  done
done

# Four shapes that ran the script past the matching above. Each is refused, and
# the nearest forms that run nothing still defer.
echo "# the kickoff push: a line splice, a variable, a short glob, a persisted config"
SPL=$'\\\n'
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg worker "printf -v x 'scripts/kickoff-spec-push.sh'; eval \"\$x\"" "$SPEC" "$SPEC"
expect deny "[worker, kickoff-demo] a variable-held kickoff name denies"
reason_has 'CLAUDE_PLUGIN_ROOT.?/scripts/kickoff-spec-push[.]sh <spec>' "[worker, kickoff-demo] the variable-held refusal names the accepted form"
for cmd in "bash scripts/kickoff-spec-${SPL}push.sh demo; cat scripts/kickoff-spec-push.sh" \
  "cat scripts/kickoff-spec-push.sh; bash scripts/kickoff-spec-${SPL}push.sh demo" \
  "git add scripts/kickoff-spec-push.sh && sh scripts/kick${SPL}off-spec-push.sh demo" \
  "cat scripts/kickoff-spec-push.sh | grep -c x; bash scripts/kickoff-${SPL}spec-push.sh demo" \
  "bash scripts/kickoff-spec-${SPL}push.sh demo" \
  "printf -v x 'scripts/kickoff-spec-push.sh'; eval \"\$x\"" \
  "printf -v x 'scripts/kickoff-spec-push.sh demo'; eval \"\$x\"" \
  "printf -vx 'scripts/kickoff-spec-push.sh demo'; eval \$x" \
  "printf -v x 'scripts/kickoff-spec-push.sh demo'; true; eval \"\$x\"" \
  "printf -v x 'scripts/kickoff-spec-push.sh demo' && bash -c \"\$x\"" \
  "printf -v x 'scripts/kickoff-spec-push.sh demo'; source \"\$x\"" \
  "printf -v x 'scripts/kickoff-spec-push.sh demo'; . \"\$x\"" \
  "printf -v x 'bash scripts/kickoff-spec-push.sh demo'; env \$x" \
  "printf -v x 'bash scripts/kickoff-spec-push.sh demo'; nice eval \"\$x\"" \
  "printf -v x 'bash scripts/kickoff-spec-push.sh demo'; sudo sh -c \"\$x\"" \
  "printf -v x 'bash scripts/kickoff-spec-push.sh demo'; fish -c \"\$x\"" \
  "printf -v x 'bash scripts/kickoff-spec-push.sh demo'; trap \"\$x\" EXIT" \
  "printf -v x 'bash scripts/kickoff-spec-push.sh demo'; setsid \$x" \
  "printf -v x 'scripts/kickoff-spec-push.sh demo'; find . -maxdepth 0 -exec \$x \\;" \
  "printf -v x 'scripts/kickoff-spec-push.sh demo'; git -c core.pager=\$x log -1" \
  "printf -v x 'scripts/kickoff-spec-push.sh demo'; rg --pre \$x foo" \
  "printf -v x 'bash scripts/kickoff-spec-push.sh demo'; sh <<<\"\$x\"" \
  "printf -v x 'bash scripts/kickoff-spec-push.sh demo'; echo \"\$x\" | sh" \
  'bash scripts/?????????????????.sh demo' \
  "bash -c \"scripts/kickoff-spec-${SPL}push.sh demo\"; cat scripts/kickoff-spec-push.sh" \
  "cat scripts/kickoff-spec-push.sh; sh -c \"scripts/kickoff-spec-${SPL}push.sh demo\"" \
  "cat scripts/kickoff-spec-push.sh; eval \"scripts/kickoff-${SPL}spec-push.sh demo\"" \
  'bash scripts/k*.sh demo' \
  'bash scripts/k*h demo' \
  'sh scripts/k?*.sh demo' \
  'bash scripts/?*.sh demo' \
  'bash scripts/*?.sh demo' \
  'bash scripts/?*? demo' \
  'env scripts/?*.sh demo' \
  'cp scripts/?*.sh copy.sh' \
  'bash scripts/k${E}.sh demo' \
  'bash scripts/${E}k*.sh demo' \
  'env scripts/*k*.sh demo' \
  'exec scripts/k*.sh demo' \
  'cp scripts/k*.sh copy.sh' \
  'git diff --ext-diff scripts/kickoff-spec-push.sh' \
  'git diff --ext scripts/kickoff-spec-push.sh' \
  'git log -p --ext-diff -- scripts/kickoff-spec-push.sh' \
  'git show --ext-diff HEAD:scripts/kickoff-spec-push.sh' \
  'git config diff.external sh; git diff scripts/kickoff-spec-push.sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd"
    expect deny "[$tier, task-1] a hidden run of the kickoff push is refused: $cmd"
  done
done
EXTD="$SANDBOX/extdiff"
clone_on "$EXTD" planwright/demo/task-1 1
gitq -C "$EXTD" config diff.external sh
for cmd in 'git diff scripts/kickoff-spec-push.sh' \
  'git diff --stat -- scripts/kickoff-spec-push.sh' \
  'git diff --no-ext-diff --ext-diff scripts/kickoff-spec-push.sh' \
  'git diff -- --no-ext-diff scripts/kickoff-spec-push.sh' \
  'git diff scripts/kickoff-spec-push.sh -- --no-ext-diff' \
  'git -C /some/repo diff --stat scripts/kickoff-spec-push.sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$EXTD" "$EXTD"
    expect deny "[$tier, task-1] a git diff with diff.external set runs it on the file: $cmd"
  done
done
for cmd in 'git diff --no-ext-diff scripts/kickoff-spec-push.sh' \
  'git log -p -- scripts/kickoff-spec-push.sh' \
  'git add scripts/kickoff-spec-push.sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$EXTD" "$EXTD"
    expect defer "[$tier, task-1] diff.external runs only for git diff without --no-ext-diff: $cmd"
  done
done
DRVD="$SANDBOX/driver"
clone_on "$DRVD" planwright/demo/task-1 1
gitq -C "$DRVD" config diff.x.textconv sh
gitq -C "$DRVD" config diff.y.command sh
for cmd in 'git diff --no-ext-diff scripts/kickoff-spec-push.sh' \
  'git diff --no-textconv scripts/kickoff-spec-push.sh' \
  'git log -p scripts/kickoff-spec-push.sh' \
  'git show HEAD -- scripts/kickoff-spec-push.sh' \
  'git cat-file --textconv HEAD:a scripts/kickoff-spec-push.sh' \
  'git grep --textconv foo -- scripts/kickoff-spec-push.sh' \
  'git blame scripts/kickoff-spec-push.sh' \
  'git show -L1:x scripts/kickoff-spec-push.sh' \
  'git show -L1:x HEAD:scripts/kickoff-spec-push.sh' \
  'git show -U1:x scripts/kickoff-spec-push.sh' \
  "git show --author '.:*' scripts/kickoff-spec-push.sh" \
  'git show --grep a:b scripts/kickoff-spec-push.sh' \
  'git show --author a:b -- scripts/kickoff-spec-push.sh' \
  'git show HEAD:a scripts/kickoff-spec-push.sh' \
  'git show :/two: :scripts/kickoff-spec-push.sh' \
  'git show HEAD^{/one:} :scripts/kickoff-spec-push.sh' \
  'git show HEAD@{12:00} :scripts/kickoff-spec-push.sh' \
  'git log -U1 -- scripts/kickoff-spec-push.sh' \
  'git log -nU1 -- scripts/kickoff-spec-push.sh' \
  'git log --unified=1 -- scripts/kickoff-spec-push.sh' \
  'git log --binary -- scripts/kickoff-spec-push.sh' \
  'git log --remerge-diff -- scripts/kickoff-spec-push.sh' \
  'git log --dd -- scripts/kickoff-spec-push.sh' \
  'git cat-file --t HEAD:scripts/kickoff-spec-push.sh' \
  'git cat-file --te HEAD:scripts/kickoff-spec-push.sh' \
  'git cat-file --tex HEAD:scripts/kickoff-spec-push.sh' \
  'git cat-file --text HEAD:scripts/kickoff-spec-push.sh' \
  'git annotate scripts/kickoff-spec-push.sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$DRVD" "$DRVD"
    expect deny "[$tier, task-1] a diff driver command or textconv filter runs on the file: $cmd"
  done
done
for cmd in 'git show main@{1}:scripts/kickoff-spec-push.sh' \
  'git show HEAD^{commit}:scripts/kickoff-spec-push.sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$DRVD" "$DRVD"
    expect deny "[$tier, task-1] a blob named through a braced revision is refused, as a commit's name can hold a colon too: $cmd"
  done
done
for cmd in 'git diff --no-ext-diff --no-textconv scripts/kickoff-spec-push.sh' \
  'git log -p --no-textconv -- scripts/kickoff-spec-push.sh' \
  'git add scripts/kickoff-spec-push.sh' \
  'git log --oneline -- scripts/kickoff-spec-push.sh' \
  'git log --follow -- scripts/kickoff-spec-push.sh' \
  'git show HEAD:scripts/kickoff-spec-push.sh' \
  'git show :scripts/kickoff-spec-push.sh' \
  'git show HEAD:scripts/kickoff-spec-push.sh --' \
  'git show -q:x HEAD:scripts/kickoff-spec-push.sh' \
  'git status scripts/kickoff-spec-push.sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$DRVD" "$DRVD"
    expect defer "[$tier, task-1] a driver's filters stopped, or never reached, defer: $cmd"
  done
done
# A filter program (filter.<driver>.clean, smudge or process) runs on the
# file's content when git stages, commits, restores, compares, removes, blames
# or lists it as modified, and cat-file --filters runs one on a blob, so a
# filter of sh mapped to the script by .gitattributes runs the script.
for key in clean smudge process; do
  FLTD="$SANDBOX/filter-$key"
  clone_on "$FLTD" planwright/demo/task-1 1
  gitq -C "$FLTD" config "filter.y.$key" sh
  printf 'scripts/kickoff-spec-push.sh filter=y\n' >"$FLTD/.gitattributes"
  for cmd in 'git add scripts/kickoff-spec-push.sh' \
    'git add -n scripts/kickoff-spec-push.sh' \
    'git add --chmod=+x -- scripts/kickoff-spec-push.sh' \
    'git add scripts/kickoff-spec-push.sh*' \
    "git add ':(glob)scripts/kickoff-spec-push.sh'" \
    'git add scripts/k*.sh' \
    'git cat-file --filters HEAD:scripts/kickoff-spec-push.sh' \
    'git cat-file --filte HEAD:scripts/kickoff-spec-push.sh' \
    'git cat-file --filt HEAD:scripts/kickoff-spec-push.sh' \
    'git cat-file --fil HEAD:scripts/kickoff-spec-push.sh' \
    'git cat-file --fi HEAD:scripts/kickoff-spec-push.sh' \
    'git restore scripts/kickoff-spec-push.sh' \
    'git restore -s HEAD~1 -- scripts/kickoff-spec-push.sh' \
    'git restore --staged --worktree scripts/kickoff-spec-push.sh' \
    'git diff scripts/kickoff-spec-push.sh' \
    'git diff --no-ext-diff --no-textconv scripts/kickoff-spec-push.sh' \
    'git diff --stat -- scripts/kickoff-spec-push.sh' \
    'git diff --name-only scripts/kickoff-spec-push.sh' \
    'git diff --no-index scripts/kickoff-spec-push.sh scripts/other.sh' \
    'git status scripts/kickoff-spec-push.sh' \
    'git status -s -- scripts/kickoff-spec-push.sh' \
    'git rm --cached scripts/kickoff-spec-push.sh' \
    'git rm -n scripts/kickoff-spec-push.sh' \
    'git commit -m x scripts/kickoff-spec-push.sh' \
    'git commit -m x -- scripts/kickoff-spec-push.sh' \
    'git blame scripts/kickoff-spec-push.sh' \
    'git annotate scripts/kickoff-spec-push.sh' \
    'git ls-files -m scripts/kickoff-spec-push.sh' \
    'git ls-files -tm scripts/kickoff-spec-push.sh' \
    'git ls-files --modified scripts/kickoff-spec-push.sh' \
    'git ls-files --mod scripts/kickoff-spec-push.sh' \
    'git ls-files --modi scripts/kickoff-spec-push.sh' \
    'git ls-files --m scripts/kickoff-spec-push.sh' \
    'git checkout -- scripts/kickoff-spec-push.sh' \
    'git checkout HEAD -- scripts/kickoff-spec-push.sh' \
    'git stash push scripts/kickoff-spec-push.sh' \
    'git reset --hard -- scripts/kickoff-spec-push.sh' \
    'git hash-object scripts/kickoff-spec-push.sh' \
    'git archive HEAD scripts/kickoff-spec-push.sh' \
    'git add scripts/other.sh scripts/kickoff-spec-push.sh' \
    "git -C $FLTD add scripts/kickoff-spec-push.sh"; do
    for tier in worker tower; do
      PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$FLTD" "$FLTD"
      expect deny "[$tier, task-1] a filter.y.$key program runs on the file: $cmd"
    done
  done
  for cmd in 'git add scripts/other.sh' \
    'git add -- scripts/other.sh' \
    'git status scripts/other.sh' \
    'git restore scripts/other.sh' \
    'git diff scripts/other.sh' \
    'git rm --cached scripts/other.sh' \
    'git commit -m x scripts/other.sh' \
    'git ls-files -m scripts/other.sh' \
    'git cat-file -p HEAD:scripts/other.sh' \
    'git log -p -- scripts/kickoff-spec-push.sh' \
    'git log --oneline -- scripts/kickoff-spec-push.sh' \
    'git show HEAD:scripts/kickoff-spec-push.sh' \
    'git show HEAD -- scripts/kickoff-spec-push.sh' \
    'git diff-tree -p HEAD scripts/kickoff-spec-push.sh' \
    'git cat-file -p HEAD:scripts/kickoff-spec-push.sh' \
    'git cat-file -s HEAD:scripts/kickoff-spec-push.sh' \
    'git ls-files scripts/kickoff-spec-push.sh' \
    "git ls-files -s '--format=%(objectmode)' scripts/kickoff-spec-push.sh" \
    'git ls-tree HEAD scripts/kickoff-spec-push.sh' \
    'git grep foo -- scripts/kickoff-spec-push.sh' \
    'git check-ignore scripts/kickoff-spec-push.sh' \
    'git log --first-parent --find-renames -- scripts/kickoff-spec-push.sh' \
    'cat scripts/kickoff-spec-push.sh'; do
    for tier in worker tower; do
      PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$FLTD" "$FLTD"
      expect defer "[$tier, task-1] with filter.y.$key set, what never filters the script defers: $cmd"
    done
  done
done
# With no filter program configured (a filter.<driver>.required key alone runs
# nothing), the everyday stages and reads of the script still defer, even with
# .gitattributes mapping it.
NOFD="$SANDBOX/nofilter"
clone_on "$NOFD" planwright/demo/task-1 1
gitq -C "$NOFD" config filter.y.required true
printf 'scripts/kickoff-spec-push.sh filter=y\n' >"$NOFD/.gitattributes"
# An existing empty directory a clone or init writes a repository into, and a
# template directory whose config would be copied there.
mkdir "$SANDBOX/empty" "$SANDBOX/tpl"
for cmd in 'git add scripts/kickoff-spec-push.sh' \
  'git status scripts/kickoff-spec-push.sh' \
  'git restore scripts/kickoff-spec-push.sh' \
  'git restore --staged scripts/kickoff-spec-push.sh' \
  'git diff scripts/kickoff-spec-push.sh' \
  'git rm --cached scripts/kickoff-spec-push.sh' \
  'git commit -m x scripts/kickoff-spec-push.sh' \
  'git blame scripts/kickoff-spec-push.sh' \
  'git ls-files -m scripts/kickoff-spec-push.sh' \
  'git cat-file -p HEAD:scripts/kickoff-spec-push.sh' \
  'git config user.name t && git add scripts/kickoff-spec-push.sh' \
  'git config filter.y.required false && git add scripts/kickoff-spec-push.sh' \
  'git config --get-regexp filter && git add scripts/kickoff-spec-push.sh' \
  'git remote add o u; git status scripts/kickoff-spec-push.sh' \
  "git -C $NOFD add scripts/kickoff-spec-push.sh" \
  'git -C . status scripts/kickoff-spec-push.sh' \
  'git -C /some/repo add scripts/kickoff-spec-push.sh' \
  "git -C $SANDBOX/empty add scripts/kickoff-spec-push.sh" \
  'git status scripts/kickoff-spec-push.sh; git config user.name t' \
  'git config -a user.name && git add scripts/kickoff-spec-push.sh' \
  "cd $SANDBOX/nofilter && git add scripts/kickoff-spec-push.sh" \
  'git log -p -- scripts/kickoff-spec-push.sh; git config filter.z.clean sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$NOFD" "$NOFD"
    expect defer "[$tier, task-1] with no filter program configured, a stage or read of the script defers: $cmd"
  done
done
# Deliberate over-blocks: cat-file --filters is refused whatever is
# configured. A git config write or read that names a filter key, a filter
# section rename, an include, an editor or a word the shell may still expand;
# any clone or init; an alias or other non-builtin git subcommand; a cd or
# git -C target the guard cannot read; and a missing git -C directory in a
# command with other segments (which may make it) all count as a filter set,
# even when the segment that may set one comes after the stage (a loop or a
# background job can run it first).
for cmd in 'git cat-file --filters HEAD:scripts/kickoff-spec-push.sh' \
  'git cat-file --filt HEAD:scripts/kickoff-spec-push.sh' \
  'git cat-file --batch --filters scripts/kickoff-spec-push.sh' \
  'git config filter.z.clean sh && git add scripts/kickoff-spec-push.sh' \
  'git config Filter.Z.Smudge sh; git restore scripts/kickoff-spec-push.sh' \
  'git config set filter.z.process sh && git status scripts/kickoff-spec-push.sh' \
  'git config --add filter.z.clean sh && git diff scripts/kickoff-spec-push.sh' \
  'git config include.path ../x && git add scripts/kickoff-spec-push.sh' \
  'git config --rename-section z filter.z && git rm --cached scripts/kickoff-spec-push.sh' \
  'git config $K sh && git add scripts/kickoff-spec-push.sh' \
  'git config filter.z.clean sh && git commit -m x scripts/kickoff-spec-push.sh' \
  "git -C $SANDBOX/filter-clean add scripts/kickoff-spec-push.sh" \
  'git -C ../filter-smudge restore scripts/kickoff-spec-push.sh' \
  'git -C . -C ../filter-process status scripts/kickoff-spec-push.sh' \
  'git -C $D add scripts/kickoff-spec-push.sh' \
  'true; git -C /some/repo add scripts/kickoff-spec-push.sh' \
  'ls && git -C /some/repo status scripts/kickoff-spec-push.sh' \
  'git -C /some/repo add scripts/kickoff-spec-push.sh & git init /some/repo' \
  'while git -C /some/repo add scripts/kickoff-spec-push.sh; do mkdir -p /some/repo; done' \
  'git -C ~/x add scripts/kickoff-spec-push.sh' \
  'git -C ../filter-c* add scripts/kickoff-spec-push.sh' \
  'cd $X && git add scripts/kickoff-spec-push.sh' \
  'git config --add filter.z.clean sh && git status scripts/kickoff-spec-push.sh' \
  'git config filter.z.clean sh list && git add scripts/kickoff-spec-push.sh' \
  'git config --comment list filter.z.clean sh && git add scripts/kickoff-spec-push.sh' \
  'git config filter.z.clean sh -v && git restore scripts/kickoff-spec-push.sh' \
  'git config --rename-section foo.a.b filter.a.b && git add scripts/kickoff-spec-push.sh' \
  'git config rename-section foo filter.a.required && git add scripts/kickoff-spec-push.sh' \
  'git config --edit && git add scripts/kickoff-spec-push.sh' \
  'git config -e; git status scripts/kickoff-spec-push.sh' \
  'git config --get filter.z.clean && git add scripts/kickoff-spec-push.sh' \
  "git clone -c filter.z.clean=sh $SANDBOX/origin.git $SANDBOX/empty && git -C $SANDBOX/empty add scripts/kickoff-spec-push.sh" \
  "git clone --config=filter.z.clean=sh $SANDBOX/origin.git $SANDBOX/empty && git -C $SANDBOX/empty status scripts/kickoff-spec-push.sh" \
  "git clone -qc filter.z.clean=sh $SANDBOX/origin.git $SANDBOX/empty && git -C $SANDBOX/empty add scripts/kickoff-spec-push.sh" \
  "git init --template=$SANDBOX/tpl $SANDBOX/empty && git -C $SANDBOX/empty add scripts/kickoff-spec-push.sh" \
  "git clone -qcfilter.z.clean=sh $SANDBOX/origin.git $SANDBOX/empty && git -C $SANDBOX/empty add scripts/kickoff-spec-push.sh" \
  "git clone -cuser.name=t $SANDBOX/origin.git $SANDBOX/empty && git -C $SANDBOX/empty add scripts/kickoff-spec-push.sh" \
  "git -c init.templateDir=$SANDBOX/tpl init $SANDBOX/empty && git -C $SANDBOX/empty add scripts/kickoff-spec-push.sh" \
  "git init --t=$SANDBOX/tpl $SANDBOX/empty && git -C $SANDBOX/empty add scripts/kickoff-spec-push.sh" \
  "git init $SANDBOX/empty && git -C $SANDBOX/empty add scripts/kickoff-spec-push.sh" \
  'git config --ed && git add scripts/kickoff-spec-push.sh' \
  'git config -ae && git add scripts/kickoff-spec-push.sh' \
  'git config -ef x && git add scripts/kickoff-spec-push.sh' \
  'git config edit && git add scripts/kickoff-spec-push.sh' \
  'git config --local edit && git status scripts/kickoff-spec-push.sh' \
  'git config fil{t..t}er.z.clean sh && git add scripts/kickoff-spec-push.sh' \
  'git zz && git add scripts/kickoff-spec-push.sh' \
  'git Config filter.z.clean sh && git status scripts/kickoff-spec-push.sh' \
  'for i in 1 2; do git add scripts/kickoff-spec-push.sh; git config filter.z.clean sh; done' \
  'while git status scripts/kickoff-spec-push.sh; do git config filter.z.clean sh; done' \
  'git add scripts/kickoff-spec-push.sh & git config filter.z.clean sh' \
  'git add scripts/k*.sh; git config filter.z.clean sh' \
  'git restore scripts/kickoff-spec-push.sh; git init x' \
  "for i in 1 2; do git add scripts/kickoff-spec-push.sh; cd $SANDBOX/filter-clean; done" \
  'git status scripts/kickoff-spec-push.sh; cd ..' \
  'git config -aef && git add scripts/kickoff-spec-push.sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$NOFD" "$NOFD"
    expect deny "[$tier, task-1] a filter the guard cannot rule out could run on the file: $cmd"
  done
done
# A configuration the guard cannot read is no proof that no filter is set.
BADD="$SANDBOX/badconfig"
clone_on "$BADD" planwright/demo/task-1 1
gitq -C "$BADD" config filter.y.clean sh
printf '[core\n' >>"$BADD/.git/config"
for cmd in "git -C $BADD add scripts/kickoff-spec-push.sh" \
  "git -C $BADD status scripts/kickoff-spec-push.sh"; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$NOFD" "$NOFD"
    expect deny "[$tier, task-1] an unreadable configuration counts as a filter set: $cmd"
  done
done
for cmd in 'git log -p -- scripts/kickoff-spec-push.sh' \
  'git show HEAD -- scripts/kickoff-spec-push.sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$BADD" "$BADD"
    expect deny "[$tier, task-1] an unreadable configuration counts as a textconv filter set: $cmd"
  done
done
for cmd in 'git log --oneline -- scripts/kickoff-spec-push.sh' \
  'git show HEAD:scripts/kickoff-spec-push.sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$BADD" "$BADD"
    expect defer "[$tier, task-1] a read no filter reaches defers whatever the configuration: $cmd"
  done
done
# git can read configuration the guard does not: a global one under another
# HOME or XDG_CONFIG_HOME, or a conditional include that starts to apply once
# another segment, before the stage or after it in a loop or a background
# job, changes the branch, the remotes or the commit.
INCD="$SANDBOX/include"
clone_on "$INCD" planwright/demo/task-1 1
gitq -C "$INCD" config includeIf.onbranch:b.path "$SANDBOX/inc.cfg"
for cmd in 'HOME=/tmp/h git add scripts/kickoff-spec-push.sh' \
  'export HOME=/tmp/h; git add scripts/kickoff-spec-push.sh' \
  'XDG_CONFIG_HOME=/tmp/h; git status scripts/kickoff-spec-push.sh' \
  'declare -x XDG_CONFIG_HOME=/tmp/h; git restore scripts/kickoff-spec-push.sh' \
  'HOME+=/../../tmp/h git add scripts/kickoff-spec-push.sh' \
  'XDG_CONFIG_HOME+=/x; git status scripts/kickoff-spec-push.sh' \
  'HOME=/tmp/h git log -p -- scripts/kickoff-spec-push.sh' \
  'export XDG_CONFIG_HOME=/tmp/h; git show HEAD -- scripts/kickoff-spec-push.sh' \
  "git clone $SANDBOX/origin.git $SANDBOX/empty && cd $SANDBOX/empty && git log -p -- scripts/kickoff-spec-push.sh" \
  'git zz && git log -p -- scripts/kickoff-spec-push.sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$NOFD" "$NOFD"
    expect deny "[$tier, task-1] another global configuration could set a filter: $cmd"
  done
done
for cmd in 'git switch -c b && git add scripts/kickoff-spec-push.sh' \
  'git remote add o u && git add scripts/kickoff-spec-push.sh' \
  'git commit -m x && git status scripts/kickoff-spec-push.sh' \
  'for i in 1 2; do git add scripts/kickoff-spec-push.sh; git switch -c b; done' \
  'git add scripts/kickoff-spec-push.sh & git remote add o u' \
  'while git status scripts/kickoff-spec-push.sh; do git commit -m x; done' \
  'git add scripts/k*.sh; git switch -c b'; do
  # The tower refuses a branch change or a commit on its own.
  PLANWRIGHT_WORKER_SCOPE=task-1 pg worker "$cmd" "$INCD" "$INCD"
  expect deny "[worker, task-1] a conditional include may start to apply: $cmd"
done
for cmd in 'git add scripts/kickoff-spec-push.sh' \
  'LANG=C git add scripts/kickoff-spec-push.sh' \
  'LANG=C git log -p -- scripts/kickoff-spec-push.sh' \
  'HOME=/tmp/h git log --oneline -- scripts/kickoff-spec-push.sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$INCD" "$INCD"
    expect defer "[$tier, task-1] with the branch and remotes unchanged, an include defers: $cmd"
  done
done
for cmd in 'git switch -c b && git add scripts/kickoff-spec-push.sh' \
  'git remote add o u && git add scripts/kickoff-spec-push.sh' \
  'git add scripts/kickoff-spec-push.sh && git commit -m x' \
  'for i in 1 2; do git add scripts/kickoff-spec-push.sh; git switch -c b; done'; do
  PLANWRIGHT_WORKER_SCOPE=task-1 pg worker "$cmd" "$NOFD" "$NOFD"
  expect defer "[worker, task-1] with no conditional include, a branch or remote change defers: $cmd"
done
PAGD="$SANDBOX/pager"
clone_on "$PAGD" planwright/demo/task-1 1
gitq -C "$PAGD" config core.pager sh
gitq -C "$PAGD" config diff.algorithm patience
for cmd in "bash tests/test-kickoff-spec-${SPL}push.sh" \
  "cat scripts/kickoff-spec-push.sh; echo a${SPL}b" \
  "git add scripts/kickoff-spec-push.sh; ls ${SPL}-l" \
  "git diff scripts/kickoff-spec-push.sh; echo a${SPL}b" \
  "printf -v x 'scripts/kickoff-spec-push.sh demo'" \
  "printf -v x 'scripts/kickoff-spec-push.sh demo'; echo \"\$x\"" \
  "printf -v x 'scripts/kickoff-spec-push.sh demo'; cat \"\$x\"" \
  "printf -v x 'scripts/kickoff-spec-push.sh demo'; ls; true" \
  "cat scripts/kickoff-spec-push.sh; bash -c \"echo a${SPL}b\"" \
  "printf -v x 'other.sh'; eval \"\$x\"" \
  "printf -v x 'scripts/other.sh' && bash -c \"\$x\"" \
  "cat scripts/kickoff-spec-push.sh; eval ls" \
  'bash scripts/t*.sh' \
  'bash tests/test-*.sh' \
  'ls scripts/k*.sh' \
  'cat scripts/k*.sh' \
  'shellcheck scripts/k*.sh' \
  'git add scripts/k*.sh' \
  'for f in scripts/*.sh; do shellcheck "$f"; done' \
  'env scripts/*.sh' \
  'cp scripts/*.sh copy.sh' \
  'cp scripts/*.sh* copy.sh' \
  'cp scripts/?.sh copy.sh' \
  'env scripts/??.sh' \
  'git diff --no-ext-diff scripts/kickoff-spec-push.sh' \
  'git diff scripts/other.sh' \
  'git config core.autocrlf false && git add scripts/kickoff-spec-push.sh' \
  'git remote add o u; git add scripts/kickoff-spec-push.sh' \
  'git diff --ext-diff scripts/other.sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd"
    expect defer "[$tier, task-1] a near miss of the hidden runs defers: $cmd"
  done
done
for cmd in 'git diff scripts/kickoff-spec-push.sh' \
  'git log -p -- scripts/kickoff-spec-push.sh' \
  'git diff --stat scripts/kickoff-spec-push.sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$PAGD" "$PAGD"
    expect defer "[$tier, task-1] core.pager and an unrelated key never run without a terminal, so a read defers: $cmd"
  done
done

no_gh_calls
finish
