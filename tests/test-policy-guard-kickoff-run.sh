#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: the kickoff push matched as a run, not as any mention.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"
# shellcheck source=tests/lib/policy-guard-clones.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-clones.sh"

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
  'bash tests/test-kickoff-spec-push.sh && git cat-file -p HEAD:scripts/kickoff-spec-push.sh' \
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

no_gh_calls
finish
