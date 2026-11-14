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
reason_has 'protected branch' "[worker, task-1] the amendment-branch refusal keeps today's protected-branch text"
PLANWRIGHT_WORKER_SCOPE=kickoff-demo pg tower "$KICKOFF_PUSH" "$AMEND" "$AMEND"
expect deny "[tower, kickoff-demo] a non-worker tier on the amendment branch denies"
reason_has 'protected branch' "[tower, kickoff-demo] the non-worker amendment-branch refusal keeps today's protected-branch text"
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
expect deny "[worker, task-1] a spec named like the script is not a kickoff push, and its refusal keeps today's text"
reason_has 'protected branch' "[worker, task-1] the spec-named-like-the-script refusal is the protected-branch text, not a spelling refusal"
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
  'git annotate scripts/kickoff-spec-push.sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$DRVD" "$DRVD"
    expect deny "[$tier, task-1] a diff driver command or textconv filter runs on the file: $cmd"
  done
done
for cmd in 'git diff --no-ext-diff --no-textconv scripts/kickoff-spec-push.sh' \
  'git log -p --no-textconv -- scripts/kickoff-spec-push.sh' \
  'git add scripts/kickoff-spec-push.sh' \
  'git log --oneline -- scripts/kickoff-spec-push.sh' \
  'git log --follow -- scripts/kickoff-spec-push.sh' \
  'git show HEAD:scripts/kickoff-spec-push.sh' \
  'git status scripts/kickoff-spec-push.sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$DRVD" "$DRVD"
    expect defer "[$tier, task-1] a driver's filters stopped, or never reached, defer: $cmd"
  done
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
