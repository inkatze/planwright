#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: what git configuration and plumbing do to a read or a stage of the kickoff script.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"
# shellcheck source=tests/lib/policy-guard-clones.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-clones.sh"

# With no filter program configured (a filter.<driver>.required key alone runs
# nothing), the everyday stages and reads of the script still defer, even with
# .gitattributes mapping it.
NOFD="$SANDBOX/nofilter"
NLW=$'\n'
SPL=$'\\\n'
# The three filter clones the cases below name by path: a filter of sh mapped to
# the script by .gitattributes, one per filter key.
for key in clean smudge process; do
  FLTD="$SANDBOX/filter-$key"
  clone_on "$FLTD" planwright/demo/task-1 1
  gitq -C "$FLTD" config "filter.y.$key" sh
  printf 'scripts/kickoff-spec-push.sh filter=y\n' >"$FLTD/.gitattributes"
done
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
  'git annotate scripts/kickoff-spec-push.sh' \
  'git ls-files --modified scripts/kickoff-spec-push.sh' \
  'git add scripts/kickoff-spec-push.sh;' \
  'git add scripts/kickoff-spec-push.sh &' \
  'git add scripts/kickoff-spec-push.sh # stage it' \
  "git add scripts/kickoff-spec-push.sh${NLW}" \
  "git -C $NOFD add scripts/kickoff-spec-push.sh" \
  'git -C . status scripts/kickoff-spec-push.sh' \
  'git -C /some/repo add scripts/kickoff-spec-push.sh' \
  "git -C $SANDBOX/empty add scripts/kickoff-spec-push.sh" \
  'git log --oneline -- scripts/kickoff-spec-push.sh; cd ..' \
  'git log -p -- scripts/kickoff-spec-push.sh; git config filter.z.clean sh' \
  'git config user.name t && git cat-file -p HEAD:scripts/kickoff-spec-push.sh' \
  'git cat-file -p HEAD:scripts/kickoff-spec-push.sh | head -5' \
  'cat scripts/kickoff-spec-push.sh && git show HEAD:scripts/kickoff-spec-push.sh' \
  'git add scripts/other.sh && git commit -m x' \
  'git commit -m x && git log -1'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$NOFD" "$NOFD"
    expect defer "[$tier, task-1] with no filter program configured, a stage or read of the script defers: $cmd"
  done
done
# A git step that can run a filter program on the script must be the only
# command in its line, so nothing beside it can set a filter program first.
# Every compound shape is refused, a one-line add and commit included, and the
# reason names the step.
for cmd in 'git add scripts/kickoff-spec-push.sh && git commit -m x' \
  'git add scripts/kickoff-spec-push.sh; git commit -m x' \
  'git add scripts/kickoff-spec-push.sh || true' \
  "git add scripts/kickoff-spec-push.sh${NLW}git commit -m x" \
  'git status scripts/kickoff-spec-push.sh | cat' \
  'echo x | git add scripts/kickoff-spec-push.sh' \
  '( git add scripts/kickoff-spec-push.sh )' \
  '{ git add scripts/kickoff-spec-push.sh; }' \
  'if git status scripts/kickoff-spec-push.sh; then true; fi' \
  'cd . && git add scripts/kickoff-spec-push.sh' \
  "cd $SANDBOX/nofilter && git add scripts/kickoff-spec-push.sh" \
  'true && git restore scripts/kickoff-spec-push.sh' \
  'git diff scripts/kickoff-spec-push.sh; echo done' \
  'git rm --cached scripts/kickoff-spec-push.sh && git commit -m x' \
  'git commit -m x scripts/kickoff-spec-push.sh && git log -1' \
  'git blame scripts/kickoff-spec-push.sh | head -5' \
  'git annotate scripts/kickoff-spec-push.sh; true' \
  'git ls-files -m scripts/kickoff-spec-push.sh | wc -l' \
  'git config user.name t && git add scripts/kickoff-spec-push.sh' \
  'git config filter.y.required false && git add scripts/kickoff-spec-push.sh' \
  'git config --get-regexp filter && git add scripts/kickoff-spec-push.sh' \
  'git remote add o u; git status scripts/kickoff-spec-push.sh' \
  'git status scripts/kickoff-spec-push.sh; git config user.name t' \
  'git config -a user.name && git add scripts/kickoff-spec-push.sh' \
  'git config core.autocrlf false && git add scripts/kickoff-spec-push.sh' \
  'git remote add o u; git add scripts/kickoff-spec-push.sh' \
  "git add scripts/kickoff-spec-push.sh; ls ${SPL}-l" \
  "git diff scripts/kickoff-spec-push.sh; echo a${SPL}b" \
  'git switch -c b && git add scripts/kickoff-spec-push.sh' \
  'git remote add o u && git add scripts/kickoff-spec-push.sh' \
  'bash tests/test-kickoff-spec-push.sh && git add scripts/kickoff-spec-push.sh' \
  'for i in 1 2; do git add scripts/kickoff-spec-push.sh; git switch -c b; done'; do
  for tier in worker tower; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg "$tier" "$cmd" "$NOFD" "$NOFD"
    expect deny "[$tier, task-1] a filter-capable git step on the script must stand alone: $cmd"
  done
done
for cmd in 'git add scripts/kickoff-spec-push.sh && git commit -m x' \
  'git status scripts/kickoff-spec-push.sh | cat' \
  'git ls-files -m scripts/kickoff-spec-push.sh | wc -l'; do
  PLANWRIGHT_WORKER_SCOPE=task-1 pg worker "$cmd" "$NOFD" "$NOFD"
  reason_has 'must be the only command in its line' "[worker, task-1] the stand-alone refusal says why: $cmd"
done
PLANWRIGHT_WORKER_SCOPE=task-1 pg worker 'git add scripts/kickoff-spec-push.sh && git commit -m x' "$NOFD" "$NOFD"
reason_has 'separate commands, with git add on scripts/kickoff-spec-push.sh as a command of its own' "[worker, task-1] the stand-alone refusal names the step to split out"
PLANWRIGHT_WORKER_SCOPE=task-1 pg worker 'git ls-files -m scripts/kickoff-spec-push.sh | wc -l' "$NOFD" "$NOFD"
reason_has 'with git ls-files on scripts/kickoff-spec-push.sh as a command of its own' "[worker, task-1] the stand-alone refusal names an ls-files -m step"
# Deliberate over-blocks: cat-file --filters is refused whatever is
# configured. A git config write or read that names a filter key, a filter
# section rename, an include, an editor or a word the shell may still expand;
# any clone or init; an alias or other non-builtin git subcommand; a cd or
# git -C target the guard cannot read; and a missing git -C directory in a
# command with other segments (which may make it) all count as a filter set,
# even when the segment that may set one comes after the stage (a loop or a
# background job can run it first), as do a GIT_ variable assigned or
# exported beside the stage and a cd, pushd or popd after it.
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
  'git config --rename-section foo filter.a.required && git add scripts/kickoff-spec-push.sh' \
  'git config --ren foo filter.a.required && git add scripts/kickoff-spec-push.sh' \
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
  'git add scripts/kickoff-spec-push.sh && pushd ..' \
  'git add scripts/kickoff-spec-push.sh && popd' \
  'readonly GIT_DIR=/x; git add scripts/kickoff-spec-push.sh' \
  'typeset -x HOME=/tmp/h; git status scripts/kickoff-spec-push.sh' \
  'for i in 1 2; do git add scripts/kickoff-spec-push.sh; export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=filter.z.clean GIT_CONFIG_VALUE_0=sh; done' \
  'while git status scripts/kickoff-spec-push.sh; do GIT_DIR=/tmp/q/.git; done' \
  'git add scripts/kickoff-spec-push.sh & GIT_CONFIG_COUNT=1' \
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
for dir in "$NOFD" "$INCD"; do
  for cmd in 'git switch -c b && git log -p -- scripts/kickoff-spec-push.sh' \
    'git remote add o u && git cat-file -p HEAD:scripts/kickoff-spec-push.sh'; do
    PLANWRIGHT_WORKER_SCOPE=task-1 pg worker "$cmd" "$dir" "$dir"
    expect defer "[worker, task-1] a read no filter reaches defers beside a branch or remote change, include or not: $cmd"
  done
done
# The refusals ahead of the stand-alone one keep their own reason where they
# decide: a change after the stage (a setter before it already makes the stage
# no read).
PLANWRIGHT_WORKER_SCOPE=task-1 pg worker 'git add scripts/kickoff-spec-push.sh && git switch -c b' "$INCD" "$INCD"
reason_has 'conditional include' "[worker, task-1] a branch change after a stage under an include names the include"
PLANWRIGHT_WORKER_SCOPE=task-1 pg worker 'git commit -m x scripts/kickoff-spec-push.sh' "$INCD" "$INCD"
reason_has 'conditional include' "[worker, task-1] a lone commit of the script under an include is refused for the include"
PLANWRIGHT_WORKER_SCOPE=task-1 pg worker 'git add scripts/kickoff-spec-push.sh; git config filter.z.clean sh' "$NOFD" "$NOFD"
reason_has 'Run that change as its own command' "[worker, task-1] a filter set after a stage names the configuration change"
PLANWRIGHT_WORKER_SCOPE=task-1 pg worker 'git add scripts/kickoff-spec-push.sh && cd ..' "$NOFD" "$NOFD"
reason_has 'changes directory after it' "[worker, task-1] a cd after a stage names the directory change"
PAGD="$SANDBOX/pager"
clone_on "$PAGD" planwright/demo/task-1 1
gitq -C "$PAGD" config core.pager sh
gitq -C "$PAGD" config diff.algorithm patience
for cmd in "bash tests/test-kickoff-spec-${SPL}push.sh" \
  "cat scripts/kickoff-spec-push.sh; echo a${SPL}b" \
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
  'git config core.autocrlf false && git cat-file -p HEAD:scripts/kickoff-spec-push.sh' \
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
