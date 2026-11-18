#!/bin/bash
# Tests for the untrusted-checkout git reads (scripts/untrusted-git-lib.sh,
# the mc_untrusted_git wrappers in scripts/mc-lib.sh, and the fleet, flight
# and reclaim scripts that read a worker's worktree).
#
# A worker writes its checkout's configuration and attributes, so a git read
# of that checkout from another session must run none of the programs the
# configuration names: fsmonitor, filters (clean, process), diff drivers,
# textconv, external diff, signature programs. Every planted program here only
# touches a marker file under the test's own temp dir; a case passes when the
# marker is absent after the guarded read, and each case first proves its
# fixture is live by running the same read with plain git and requiring the
# marker (a check that cannot fail measures nothing).
#
# The repositories are throwaway, with the global config an empty file and the
# system config off, so no real configuration is read or written.
#
# Runs standalone under /bin/bash (the bash 3.2 floor); UNTRUSTED_GIT_SCRIPTS
# points it at another copy of scripts/ (the fail-first run against main):
#   ./tests/test-untrusted-git.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_EXTERNAL_DIFF

here=$(cd "$(dirname "$0")" && pwd)
scripts=${UNTRUSTED_GIT_SCRIPTS:-$here/../scripts}

failed=0
seen=0
fail() {
  echo "FAIL: $1" >&2
  failed=$((failed + 1))
  [ -n "${UNTRUSTED_GIT_KEEP_GOING:-}" ] || exit 1
}
# The fail-first run keeps going so every case reports; a group that failed
# says "not ok" in place of its ok line.
if [ -n "${UNTRUSTED_GIT_KEEP_GOING:-}" ]; then
  echo() {
    case ${1:-} in
      "ok: "*)
        if [ "$failed" -gt "$seen" ]; then
          seen=$failed
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
# the `mark` diff driver. Sets R (the checkout) and M (its marker directory).
# <scope> is where the drivers will be planted: local or worktree.
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

# plant <key> <value>: set one driver in the repository, in its scope.
plant() {
  git -C "$R" config "$SCOPE" "$1" "$2"
}

# stat_dirty: a file whose stat changed and whose content did not, the shape
# that makes status hash it through its clean filter.
stat_dirty() {
  sd_n=$((sd_n + 1))
  touch -t "2001010100$(printf '%02d' "$sd_n")" "$R/a.txt"
}
sd_n=0

# fired <marker>: true when the planted program ran.
fired() {
  [ -e "$M/$1" ]
}

# expect_fires <label> <marker> <git args...>: the control, plain git must run
# the planted program, so the guarded run's silence means something.
expect_fires() {
  ef_label=$1 ef_marker=$2
  shift 2
  rm -f "$M"/*
  git -C "$R" "$@" >/dev/null 2>&1 || :
  fired "$ef_marker" || fail "$ef_label: the control did not fire the planted program (fixture is not live)"
  rm -f "$M"/*
}

# expect_silent <label> <marker> <git args...>: the guarded run must not.
expect_silent() {
  es_label=$1 es_marker=$2
  shift 2
  mc_untrusted_git -C "$R" "$@" >/dev/null 2>&1 || :
  if fired "$es_marker"; then
    fail "$es_label: the guarded read ran the planted program"
  fi
}

for scope in worktree local; do
  # --- fsmonitor
  mkrepo "fsmon-$scope" "$scope"
  printf '#!/bin/sh\ntouch "%s/fsmon"\nexit 1\n' "$M" >"$tmp/fsmon-$scope.sh"
  chmod +x "$tmp/fsmon-$scope.sh"
  plant core.fsmonitor "$tmp/fsmon-$scope.sh"
  expect_fires "fsmonitor ($scope)" fsmon status --porcelain
  expect_silent "fsmonitor ($scope)" fsmon status --porcelain
  echo "ok: core.fsmonitor in $scope config does not run under a guarded status"

  # --- clean filter
  mkrepo "clean-$scope" "$scope"
  plant filter.mark.clean "touch $M/clean; cat"
  plant filter.mark.required true
  stat_dirty
  expect_fires "clean filter ($scope)" clean status --porcelain
  stat_dirty
  expect_silent "clean filter ($scope)" clean status --porcelain
  stat_dirty
  expect_silent "clean filter, diff-index ($scope)" clean diff --quiet --no-ext-diff --no-textconv HEAD
  stat_dirty
  expect_silent "clean filter, ls-files -m ($scope)" clean ls-files -m
  # The result survives: an unchanged file reads clean, a changed one dirty.
  [ -z "$(mc_untrusted_git -C "$R" status --porcelain)" ] \
    || fail "clean filter ($scope): an unchanged tree no longer reads clean"
  printf 'changed\n' >"$R/a.txt"
  [ "$(mc_untrusted_git -C "$R" status --porcelain)" = " M a.txt" ] \
    || fail "clean filter ($scope): a changed file no longer reads dirty"
  echo "ok: a clean filter in $scope config does not run, and status keeps its result"

  # --- process filter
  mkrepo "process-$scope" "$scope"
  plant filter.mark.process "touch $M/process"
  stat_dirty
  expect_fires "process filter ($scope)" process status --porcelain
  stat_dirty
  expect_silent "process filter ($scope)" process status --porcelain
  echo "ok: a process filter in $scope config does not run"

  # --- textconv, external diff, diff driver command (with no --no-* flags:
  #     the environment alone must hold)
  mkrepo "textconv-$scope" "$scope"
  plant diff.mark.textconv "touch $M/textconv; cat"
  printf 'changed\n' >"$R/a.txt"
  expect_fires "textconv ($scope)" textconv diff HEAD
  expect_silent "textconv ($scope)" textconv diff HEAD
  echo "ok: a textconv in $scope config does not run"

  mkrepo "extdiff-$scope" "$scope"
  plant diff.external "touch $M/extdiff; true"
  printf 'changed\n' >"$R/a.txt"
  expect_fires "diff.external ($scope)" extdiff diff HEAD
  expect_silent "diff.external ($scope)" extdiff diff HEAD
  echo "ok: diff.external in $scope config does not run"

  mkrepo "drvcmd-$scope" "$scope"
  plant diff.mark.command "touch $M/drvcmd; true"
  printf 'changed\n' >"$R/a.txt"
  expect_fires "diff driver command ($scope)" drvcmd diff HEAD
  expect_silent "diff driver command ($scope)" drvcmd diff HEAD
  echo "ok: a diff driver command in $scope config does not run"

  # --- signature program, asked for explicitly
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
  echo "ok: a signature program in $scope config does not run"
done

# --- the environment form reaches a git a called script runs, and a driver
#     name with dots in it is still blanked
mkrepo env-form worktree
plant filter.my.drv.v2.clean "touch $M/clean; cat"
printf '* filter=my.drv.v2\n' >"$R/.gitattributes"
stat_dirty
expect_fires "env form" clean status --porcelain
stat_dirty
(cd "$R" && mc_untrusted_git_env && /bin/sh -c 'git status --porcelain' >/dev/null 2>&1) || :
fired clean && fail "env form: a git started by a script ran the planted filter"
echo "ok: the exported environment guards a git a script runs, odd driver names included"

# --- a driver from the operator's global config is theirs, and stays
mkrepo global-kept local
printf '[filter "mark"]\n\tclean = touch %s/clean; cat\n' "$M" >"$tmp/gitconfig"
stat_dirty
rm -f "$M"/*
mc_untrusted_git -C "$R" status --porcelain >/dev/null 2>&1 || :
fired clean || fail "global config: the operator's own filter no longer runs"
: >"$tmp/gitconfig"
echo "ok: a driver from the operator's global config is left on"

# --- set -e callers (mc-radar exports the environment at top level) survive
#     a checkout with no drivers at all
mkrepo plain local
(cd "$R" && /bin/bash -c "set -e; prog=t; script_dir='$scripts'; . '$scripts/echo-safety.sh'; . '$scripts/mc-lib.sh'; mc_untrusted_git_env; echo reached") \
  | grep -qx reached || fail "mc_untrusted_git_env aborted a set -e caller on a driverless checkout"
echo "ok: the environment helper does not abort a set -e caller"

# --- a checkout whose configuration git cannot read fails closed: no git runs
mkdir "$tmp/broken"
git init -q "$tmp/broken"
printf '[filter "mark"\n' >>"$tmp/broken/.git/config"
if mc_untrusted_git -C "$tmp/broken" status --porcelain >/dev/null 2>&1; then
  fail "an unreadable checkout config let a guarded git run"
fi
echo "ok: an unreadable checkout configuration fails closed"

# --- the scripts that read a worker's worktree
# fleet-sweep's tree inspection, run from the real function text.
mkrepo sweep local
plant filter.mark.clean "touch $M/clean; cat"
git -C "$R" update-ref refs/remotes/origin/main HEAD
eval "$(awk '/^inspect_tree\(\) \{/,/^}/' "$scripts/fleet-sweep.sh")"
if ! command -v pw_untrusted_git >/dev/null 2>&1 && [ -r "$scripts/untrusted-git-lib.sh" ]; then
  # shellcheck source=scripts/untrusted-git-lib.sh
  . "$scripts/untrusted-git-lib.sh"
fi
stat_dirty
rm -f "$M"/*
verdict=$(inspect_tree "$R")
fired clean && fail "fleet-sweep inspect_tree ran the planted clean filter"
[ "$verdict" = clean ] || fail "fleet-sweep inspect_tree: a clean pushed tree read $verdict"
echo "ok: fleet-sweep's tree inspection runs no clean filter and keeps its verdict"

# fleet-stuck-detector's read-only query.
mkrepo detector local
plant filter.mark.clean "touch $M/clean; cat"
eval "$(awk '/^git_ro\(\) \{/,/^}/' "$scripts/fleet-stuck-detector.sh")"
stat_dirty
rm -f "$M"/*
git_ro "$R" ls-files -m >/dev/null 2>&1 || :
fired clean && fail "fleet-stuck-detector git_ro ran the planted clean filter"
echo "ok: fleet-stuck-detector's git reads run no clean filter"

# mc-reclaim's git against a proved worktree.
mkrepo reclaim local
printf '#!/bin/sh\ntouch "%s/fsmon"\nexit 1\n' "$M" >"$tmp/fsmon-reclaim.sh"
chmod +x "$tmp/fsmon-reclaim.sh"
plant core.fsmonitor "$tmp/fsmon-reclaim.sh"
plant filter.mark.clean "touch $M/clean; cat"
eval "$(awk '/^g\(\) \{/,/^}/' "$scripts/mc-reclaim.sh")"
# shellcheck disable=SC2034 # read by the extracted g()
WT=$R GITDIR=$R/.git
stat_dirty
rm -f "$M"/*
g status --porcelain >/dev/null 2>&1 || :
fired clean && fail "mc-reclaim g ran the planted clean filter"
fired fsmon && fail "mc-reclaim g ran the planted fsmonitor"
echo "ok: mc-reclaim's worktree reads run no clean filter or fsmonitor"

# step-record, reached through a caller's guarded environment: its own git
# wrapper used to clear the settings.
mkrepo steprec local
printf '#!/bin/sh\ntouch "%s/fsmon"\nexit 1\n' "$M" >"$tmp/fsmon-steprec.sh"
chmod +x "$tmp/fsmon-steprec.sh"
plant core.fsmonitor "$tmp/fsmon-steprec.sh"
plant filter.mark.clean "touch $M/clean; cat"
stat_dirty
rm -f "$M"/*
(mc_untrusted_git_env "$R" && /bin/bash "$scripts/step-record.sh" --worktree "$R" fingerprint --paths a.txt) >/dev/null 2>&1 || :
fired fsmon && fail "step-record, called guarded, ran the planted fsmonitor"
fired clean && fail "step-record, called guarded, ran the planted clean filter"
echo "ok: step-record keeps a guarded caller's environment"

# fleet-cleanup's reclaim checks and flight-record's record checks, run end
# to end in tests/test-fleet-cleanup.sh and tests/test-flight-record.sh.

[ "$failed" -eq 0 ] || exit 1
echo "all untrusted-git tests passed"
