#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: the shapes that ran the kickoff push past the matching, and the git filter programs.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"
# shellcheck source=tests/lib/policy-guard-clones.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-clones.sh"

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
# --e and --ex are refused as abbreviations of --ext-diff, and any --filter
# spelling as one of cat-file's --filters, on every subcommand: git 2.53
# rejects them outside cat-file, so this over-blocks only spellings that fail.
for cmd in 'git diff --e scripts/kickoff-spec-push.sh' \
  'git diff --ex scripts/kickoff-spec-push.sh' \
  'git log -p --ex -- scripts/kickoff-spec-push.sh' \
  'git show --e HEAD:scripts/kickoff-spec-push.sh' \
  'git show --filter=blob:none HEAD:scripts/kickoff-spec-push.sh' \
  'git log --filters -- scripts/kickoff-spec-push.sh' \
  'git diff --filter scripts/kickoff-spec-push.sh' \
  'git cat-file --filter=blob:none HEAD:scripts/kickoff-spec-push.sh'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd"
    expect deny "[$tier, task-1] an ext-diff or filter abbreviation is refused beside the script: $cmd"
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

no_gh_calls
finish
