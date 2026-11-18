#!/bin/bash
# Tests for git reads of a checkout the reader does not own: the
# untrusted-git-lib.sh helper, the mc_untrusted_git wrappers, and the fleet,
# flight and reclaim scripts that read a worker's worktree.
#
# A worker writes its checkout's configuration and attributes, so a read of
# it from another session must run none of the programs the configuration
# names. Every planted program only touches a marker file under the test's own
# temp dir. Each case first proves its fixture live (the same read with plain
# git must fire the marker), then asserts the guarded read leaves it absent.
# The repositories are throwaway, the global config an empty file, the system
# config off.
#
# UNTRUSTED_GIT_SCRIPTS points at another copy of scripts/ and
# UNTRUSTED_GIT_KEEP_GOING=1 reports every failing case instead of the first,
# to show the cases fail against code without the guard.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-untrusted-git.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_EXTERNAL_DIFF

here=$(cd "$(dirname "$0")" && pwd)
scripts=${UNTRUSTED_GIT_SCRIPTS:-$here/../scripts}

failed=0
reported=0
fail() {
  echo "FAIL: $1" >&2
  failed=$((failed + 1))
  [ -n "${UNTRUSTED_GIT_KEEP_GOING:-}" ] || exit 1
}
# Keep-going mode: a group that failed says "not ok" in place of its ok line.
if [ -n "${UNTRUSTED_GIT_KEEP_GOING:-}" ]; then
  echo() {
    case ${1:-} in
      "ok: "*)
        if [ "$failed" -gt "$reported" ]; then
          reported=$failed
          builtin echo "not ok: ${1#ok: }"
          return 0
        fi
        ;;
    esac
    builtin echo "$@"
  }
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/home"
: >"$tmp/gitconfig"
export HOME="$tmp/home" GIT_CONFIG_GLOBAL="$tmp/gitconfig" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

prog=test-untrusted-git
script_dir=$scripts
[ -r "$scripts/echo-safety.sh" ] || fail "echo-safety.sh is missing or unreadable"
# shellcheck source=scripts/echo-safety.sh
. "$scripts/echo-safety.sh"
# shellcheck source=scripts/mc-lib.sh
. "$scripts/mc-lib.sh"

# mkrepo <name> <scope>: a repository with a committed a.txt and b.dat, its
# attributes sending every file through the `mark` filter and *.txt through
# the `mark` diff driver. Sets R (the checkout) and M (its marker directory);
# <scope> is where plant puts the drivers: local or worktree.
mkrepo() {
  R="$tmp/$1"
  M="$tmp/m-$1"
  mkdir -p "$M"
  git init -q -b main "$R"
  printf 'one\n' >"$R/a.txt"
  printf 'two\n' >"$R/b.dat"
  git -C "$R" add a.txt b.dat
  git -C "$R" commit -qm seed
  printf '* filter=mark\n*.txt diff=mark\n' >"$R/.gitattributes"
  git -C "$R" add .gitattributes
  git -C "$R" commit -qm attrs
  if [ "$2" = worktree ]; then
    git -C "$R" config extensions.worktreeConfig true
  fi
  SCOPE=--$2
}

plant() {
  git -C "$R" config "$SCOPE" "$1" "$2"
}

# stat_dirty [<file>]: a file whose stat changed and whose content did not,
# the shape that makes status hash it through its clean filter. Each call
# stamps a new time, since a refresh by an earlier status resets the index.
stat_dirty() {
  sd_n=$((sd_n + 1))
  touch -t "2001010100$(printf '%02d' "$sd_n")" "${1:-$R/a.txt}"
}
sd_n=0

fired() {
  [ -e "$M/$1" ]
}

# expect_fires <label> <marker> <git args...>: the control. Plain git must run
# the planted program, or the guarded run's silence means nothing.
expect_fires() {
  ef_label=$1 ef_marker=$2
  shift 2
  rm -f "$M"/*
  git -C "$R" "$@" >/dev/null 2>&1 || :
  fired "$ef_marker" || fail "$ef_label: the control did not fire the planted program (fixture is not live)"
  rm -f "$M"/*
}

# expect_silent <label> <marker> <git args...>: the guarded run must not run
# it. The guarded git's status lands in ES_RC.
expect_silent() {
  es_label=$1 es_marker=$2
  shift 2
  ES_RC=0
  mc_untrusted_git -C "$R" "$@" >/dev/null 2>&1 || ES_RC=$?
  if fired "$es_marker"; then
    fail "$es_label: the guarded read ran the planted program"
  fi
}

# expect_ran <label>: the last guarded git ran and succeeded, so its silence
# was not a failure to start.
expect_ran() {
  [ "$ES_RC" -eq 0 ] || fail "$1: the guarded git exited $ES_RC"
}

for scope in worktree local; do
  mkrepo "fsmon-$scope" "$scope"
  printf '#!/bin/sh\ntouch "%s/fsmon"\nexit 1\n' "$M" >"$tmp/fsmon-$scope.sh"
  chmod +x "$tmp/fsmon-$scope.sh"
  plant core.fsmonitor "$tmp/fsmon-$scope.sh"
  expect_fires "fsmonitor ($scope)" fsmon status --porcelain
  expect_silent "fsmonitor ($scope)" fsmon status --porcelain
  expect_ran "fsmonitor ($scope)"
  echo "ok: core.fsmonitor in $scope config does not run under a guarded status"

  mkrepo "clean-$scope" "$scope"
  plant filter.mark.clean "touch $M/clean; cat"
  plant filter.mark.required true
  stat_dirty
  expect_fires "clean filter ($scope)" clean status --porcelain
  stat_dirty
  expect_silent "clean filter ($scope)" clean status --porcelain
  expect_ran "clean filter ($scope)"
  stat_dirty
  expect_silent "clean filter, diff --quiet ($scope)" clean diff --quiet --no-ext-diff --no-textconv HEAD
  expect_ran "clean filter, diff --quiet ($scope)"
  stat_dirty
  expect_silent "clean filter, ls-files -m ($scope)" clean ls-files -m
  expect_ran "clean filter, ls-files -m ($scope)"
  [ -z "$(mc_untrusted_git -C "$R" status --porcelain)" ] \
    || fail "clean filter ($scope): an unchanged tree no longer reads clean"
  printf 'changed\n' >"$R/a.txt"
  [ "$(mc_untrusted_git -C "$R" status --porcelain)" = " M a.txt" ] \
    || fail "clean filter ($scope): a changed file no longer reads dirty"
  echo "ok: a clean filter in $scope config does not run, and status keeps its result"

  mkrepo "process-$scope" "$scope"
  plant filter.mark.process "touch $M/process"
  stat_dirty
  expect_fires "process filter ($scope)" process status --porcelain
  stat_dirty
  expect_silent "process filter ($scope)" process status --porcelain
  expect_ran "process filter ($scope)"
  echo "ok: a process filter in $scope config does not run"

  # The environment alone must hold, with no --no-* flag; and the flags form
  # callers use must still run and succeed.
  mkrepo "textconv-$scope" "$scope"
  plant diff.mark.textconv "touch $M/textconv; cat"
  printf 'changed\n' >"$R/a.txt"
  expect_fires "textconv ($scope)" textconv diff HEAD
  expect_silent "textconv ($scope)" textconv diff HEAD
  expect_silent "textconv, flags ($scope)" textconv diff --no-ext-diff --no-textconv HEAD
  expect_ran "textconv, flags ($scope)"
  echo "ok: a textconv in $scope config does not run"

  mkrepo "extdiff-$scope" "$scope"
  plant diff.external "touch $M/extdiff; true"
  printf 'changed\n' >"$R/a.txt"
  expect_fires "diff.external ($scope)" extdiff diff HEAD
  expect_silent "diff.external ($scope)" extdiff diff HEAD
  expect_silent "diff.external, flags ($scope)" extdiff diff --no-ext-diff --no-textconv HEAD
  expect_ran "diff.external, flags ($scope)"
  echo "ok: diff.external in $scope config does not run"

  mkrepo "drvcmd-$scope" "$scope"
  plant diff.mark.command "touch $M/drvcmd; true"
  printf 'changed\n' >"$R/a.txt"
  expect_fires "diff driver command ($scope)" drvcmd diff HEAD
  expect_silent "diff driver command ($scope)" drvcmd diff HEAD
  expect_silent "diff driver command, flags ($scope)" drvcmd diff --no-ext-diff --no-textconv HEAD
  expect_ran "diff driver command, flags ($scope)"
  echo "ok: a diff driver command in $scope config does not run"

  mkrepo "gpg-$scope" "$scope"
  printf '#!/bin/sh\ntouch "%s/gpg"\nexit 1\n' "$M" >"$tmp/gpg-$scope.sh"
  chmod +x "$tmp/gpg-$scope.sh"
  plant gpg.program "$tmp/gpg-$scope.sh"
  git -C "$R" cat-file commit HEAD >"$tmp/commit-$scope.txt"
  awk 'BEGIN { done = 0 } { print } !done && /^committer / { print "gpgsig -----BEGIN PGP SIGNATURE-----"; print " "; print " x"; print " -----END PGP SIGNATURE-----"; done = 1 }' \
    "$tmp/commit-$scope.txt" >"$tmp/commit-signed-$scope.txt"
  signed=$(git -C "$R" hash-object -t commit -w --stdin <"$tmp/commit-signed-$scope.txt")
  git -C "$R" update-ref refs/heads/main "$signed"
  expect_fires "gpg.program ($scope)" gpg log -1 --show-signature
  expect_silent "gpg.program ($scope)" gpg log -1 --show-signature
  expect_ran "gpg.program ($scope)"
  echo "ok: a signature program in $scope config does not run"

  # merge-tree resolves a content conflict through the merge driver.
  mkrepo "merge-$scope" "$scope"
  git -C "$R" checkout -q -b side
  printf 'side\n' >"$R/a.txt"
  git -C "$R" commit -qam side
  git -C "$R" checkout -q main
  printf 'main\n' >"$R/a.txt"
  git -C "$R" commit -qam main
  printf 'a.txt merge=mark\n' >"$R/.git/info/attributes"
  plant merge.mark.driver "touch $M/merge; true"
  expect_fires "merge driver ($scope)" merge merge-tree --write-tree main side
  expect_silent "merge driver ($scope)" merge merge-tree --write-tree main side
  echo "ok: a merge driver in $scope config does not run"
done

# A filter that normalises content: a committed blob is the filtered form, so
# with the filter blanked an unchanged-but-touched file reads dirty, never
# falsely clean.
mkrepo normalise local
plant filter.mark.clean "tr a-z A-Z"
printf 'abc\n' >"$R/c.txt"
git -C "$R" add --renormalize .
git -C "$R" add c.txt
git -C "$R" commit -qm c
stat_dirty "$R/c.txt"
[ -z "$(git -C "$R" status --porcelain)" ] || fail "normalising filter: the control tree is not clean through its own filter"
stat_dirty "$R/c.txt"
[ "$(mc_untrusted_git -C "$R" status --porcelain)" = " M c.txt" ] \
  || fail "normalising filter: a file its filter would have normalised did not read dirty"
echo "ok: a normalising filter that is blanked reads dirty, never falsely clean"

# The plain diff.external variable and a driver named `external` share a
# prefix; both stay blanked in either order.
for order in variable-first driver-first; do
  mkrepo "collide-$order" local
  printf '*.txt diff=external\n' >"$R/.git/info/attributes"
  if [ "$order" = variable-first ]; then
    plant diff.external "touch $M/ext; true"
    plant diff.external.command "touch $M/drvcmd; true"
    plant diff.external.textconv "touch $M/textconv; cat"
  else
    plant diff.external.textconv "touch $M/textconv; cat"
    plant diff.external.command "touch $M/drvcmd; true"
    plant diff.external "touch $M/ext; true"
  fi
  printf 'changed\n' >"$R/a.txt"
  git -C "$R" diff HEAD >/dev/null 2>&1 || :
  { fired ext || fired drvcmd || fired textconv; } || fail "collision ($order): the control did not fire a planted program"
  rm -f "$M"/*
  mc_untrusted_git -C "$R" diff HEAD >/dev/null 2>&1 || :
  fired ext && fail "collision ($order): the guarded diff ran diff.external"
  fired drvcmd && fail "collision ($order): the guarded diff ran the driver command"
  fired textconv && fail "collision ($order): the guarded diff ran the driver's textconv"
  rm -f "$M"/*
  mc_untrusted_git -C "$R" diff --no-ext-diff HEAD >/dev/null 2>&1 || :
  fired textconv && fail "collision ($order): the textconv ran under --no-ext-diff"
done
echo "ok: diff.external and a driver named external are both blanked, in either order"

# The exported environment reaches a git a called script runs, and a driver
# name with dots in it is still blanked.
mkrepo env-form worktree
plant filter.my.drv.v2.clean "touch $M/clean; cat"
printf '* filter=my.drv.v2\n' >"$R/.gitattributes"
stat_dirty
expect_fires "env form" clean status --porcelain
stat_dirty
(cd "$R" && mc_untrusted_git_env && /bin/sh -c 'git status --porcelain' >/dev/null 2>&1) || :
fired clean && fail "env form: a git started by a script ran the planted filter"
echo "ok: the exported environment guards a git a script runs, odd driver names included"

# A driver from the operator's global config is theirs, and stays.
mkrepo global-kept local
printf '[filter "mark"]\n\tclean = touch %s/clean; cat\n' "$M" >"$tmp/gitconfig"
stat_dirty
rm -f "$M"/*
mc_untrusted_git -C "$R" status --porcelain >/dev/null 2>&1 || :
fired clean || fail "global config: the operator's own filter no longer runs"
: >"$tmp/gitconfig"
echo "ok: a driver from the operator's global config is left on"

# A set -e caller exporting the environment survives a driverless checkout.
mkrepo plain local
(cd "$R" && /bin/bash -c "set -e; prog=t; script_dir='$scripts'; . '$scripts/echo-safety.sh'; . '$scripts/mc-lib.sh'; mc_untrusted_git_env; echo reached") \
  | grep -qx reached || fail "mc_untrusted_git_env aborted a set -e caller on a driverless checkout"
echo "ok: the environment helper does not abort a set -e caller"

# An unreadable checkout configuration fails closed with git's error status,
# not the 1 a caller reads as "no", and sets nothing.
mkdir "$tmp/broken"
git init -q "$tmp/broken"
printf '[filter "mark"\n' >>"$tmp/broken/.git/config"
rc=0
(
  mc_untrusted_git_env "$tmp/broken" || exit $?
  exit 99
) || rc=$?
[ "$rc" -eq 128 ] || fail "an unreadable checkout config: the environment helper returned $rc, expected 128"
rc=0
(
  mc_untrusted_git_env "$tmp/broken" || :
  [ -z "${GIT_CONFIG_COUNT:-}" ]
) || rc=$?
[ "$rc" -eq 0 ] || fail "an unreadable checkout config: the helper still set GIT_CONFIG_COUNT"
rc=0
mc_untrusted_git -C "$tmp/broken" diff --cached --quiet >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 128 ] || fail "an unreadable checkout config: a guarded diff --quiet returned $rc, expected 128"
echo "ok: an unreadable checkout configuration fails closed with status 128"

# An inherited bad GIT_CONFIG_COUNT does not break the listing.
mkrepo inherited local
rc=0
GIT_CONFIG_COUNT=abc mc_untrusted_git -C "$R" rev-parse HEAD >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "an inherited bad GIT_CONFIG_COUNT broke a guarded git (exit $rc)"
echo "ok: an inherited GIT_CONFIG_COUNT is replaced, not read"

# extract <script> <function>: define a function from the real script's text,
# and fail loudly when it is not there.
extract() {
  eval "$(awk -v fn="$2" '$0 ~ "^" fn "\\(\\) \\{" { on = 1 } on { print } on && /^}/ { exit }' "$scripts/$1")"
  command -v "$2" >/dev/null 2>&1 || fail "$1: no function $2 to test"
}

# fleet-sweep's tree inspection.
mkrepo sweep local
plant filter.mark.clean "touch $M/clean; cat"
git -C "$R" update-ref refs/remotes/origin/main HEAD
extract fleet-sweep.sh inspect_tree
stat_dirty
expect_fires "fleet-sweep" clean status --porcelain
stat_dirty
verdict=$(inspect_tree "$R")
fired clean && fail "fleet-sweep inspect_tree ran the planted clean filter"
[ "$verdict" = clean ] || fail "fleet-sweep inspect_tree: a clean pushed tree read $verdict"
echo "ok: fleet-sweep's tree inspection runs no clean filter and keeps its verdict"

# fleet-stuck-detector's read-only query.
mkrepo detector local
plant filter.mark.clean "touch $M/clean; cat"
extract fleet-stuck-detector.sh git_ro
stat_dirty
expect_fires "fleet-stuck-detector" clean ls-files -m
stat_dirty
git_ro "$R" ls-files -m >/dev/null 2>&1 || fail "fleet-stuck-detector git_ro failed on a readable checkout"
fired clean && fail "fleet-stuck-detector git_ro ran the planted clean filter"
echo "ok: fleet-stuck-detector's git reads run no clean filter"

# mc-reclaim's git against a proved linked worktree, whose configuration is the
# repository's own plus the worktree's.
mkrepo reclaim local
printf '#!/bin/sh\ntouch "%s/fsmon"\nexit 1\n' "$M" >"$tmp/fsmon-reclaim.sh"
chmod +x "$tmp/fsmon-reclaim.sh"
plant core.fsmonitor "$tmp/fsmon-reclaim.sh"
plant filter.mark.clean "touch $M/clean; cat"
git -C "$R" worktree add -q -b reclaim-wt "$tmp/reclaim-wt"
# shellcheck disable=SC2034 # read by the extracted g()
WT=$tmp/reclaim-wt
# shellcheck disable=SC2034
GITDIR=$(git -C "$WT" rev-parse --absolute-git-dir)
extract mc-reclaim.sh g
stat_dirty "$WT/a.txt"
rm -f "$M"/*
git --git-dir="$GITDIR" --work-tree="$WT" status --porcelain >/dev/null 2>&1 || :
{ fired clean && fired fsmon; } || fail "mc-reclaim: the control did not fire both planted programs"
rm -f "$M"/*
stat_dirty "$WT/a.txt"
g status --porcelain >/dev/null 2>&1 || fail "mc-reclaim g failed on a readable worktree"
fired clean && fail "mc-reclaim g ran the planted clean filter"
fired fsmon && fail "mc-reclaim g ran the planted fsmonitor"
echo "ok: mc-reclaim's worktree reads run no clean filter or fsmonitor"

# step-record, reached through a caller's guarded environment.
mkrepo steprec local
printf '#!/bin/sh\ntouch "%s/fsmon"\nexit 1\n' "$M" >"$tmp/fsmon-steprec.sh"
chmod +x "$tmp/fsmon-steprec.sh"
plant core.fsmonitor "$tmp/fsmon-steprec.sh"
plant filter.mark.clean "touch $M/clean; cat"
stat_dirty
expect_fires "step-record" clean status --porcelain
git -C "$R" config --unset core.fsmonitor
git -C "$R" config core.fsmonitor "$tmp/fsmon-steprec.sh"
stat_dirty
(mc_untrusted_git_env "$R" && /bin/bash "$scripts/step-record.sh" --worktree "$R" fingerprint --paths a.txt) >/dev/null 2>&1 || :
fired fsmon && fail "step-record, called guarded, ran the planted fsmonitor"
fired clean && fail "step-record, called guarded, ran the planted clean filter"
echo "ok: step-record keeps a guarded caller's environment"

# fleet-cleanup's reclaim checks and flight-record's record checks run end to
# end in tests/test-fleet-cleanup.sh and tests/test-flight-record.sh.

[ "$failed" -eq 0 ] || exit 1
echo "all untrusted-git tests passed"
