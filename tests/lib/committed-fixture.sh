# shellcheck shell=sh
# committed-fixture.sh — sourced, never executed. The worker command guard
# trusts a repository script only as a commit holds it (the base, in the
# worktree a session record names; HEAD elsewhere), so a fixture repository
# whose scripts a suite expects approved commits them, and points its base at
# that commit when a record names it (fixture_base).
#
# fixture_git <args>: git with the host's config out of reach, so a signing or
# hook setting on the machine running the suite cannot fail a fixture commit,
# and with no repository a git hook running the suite exported, so a fixture
# commit never lands in the repository under test.
fixture_git() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -c user.name=fixture \
    -c user.email=fixture@example.invalid -c commit.gpgsign=false \
    -c core.hooksPath=/dev/null "$@"
}

# fixture_commit <repo> <path>...: make <repo> a git repository of its own (a
# bare `.git` marker file is replaced, an empty `.git` directory filled, and an
# existing repository reinitialized, which keeps its history), then commit the
# paths, relative to <repo>.
fixture_commit() {
  fc_repo=$1
  shift
  [ -d "$fc_repo/.git" ] || rm -f "$fc_repo/.git"
  fixture_git init -q "$fc_repo" || return 1
  fixture_git -C "$fc_repo" add -- "$@" && fixture_git -C "$fc_repo" commit -q -m fixture
}

# fixture_base <repo>: point <repo>'s refs/remotes/origin/main at its HEAD, so
# a session record naming <repo> as its worktree with pr_base=origin/main finds
# what HEAD commits in the base, the only commit the guard trusts there.
fixture_base() {
  fixture_git -C "$1" update-ref refs/remotes/origin/main HEAD
}
