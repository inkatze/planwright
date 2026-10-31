#!/bin/bash
# Tests for scripts/mc-reclaim.sh — the worktree reclaim predicate and its
# verified backup into the program home (mission-control REQ-D1.6).
#
# Each predicate arm refuses from its own fixture; a failed copy or a hash
# mismatch refuses the removal; a complete fixture reclaims and leaves the
# knob's files under the program home's reclaim folder for that repository
# and branch with matching hashes. The forge is a gh stub reading a PR table.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).

# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
# A caller's git environment must not steer the fixture repositories.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$repo_root/scripts/mc-reclaim.sh" ] || {
  echo "FAIL: scripts/mc-reclaim.sh missing" >&2
  exit 1
}
command -v git >/dev/null 2>&1 || {
  echo "FAIL: git is required to run this suite" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/mc-reclaim.XXXXXX") || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
user_pid=''
cleanup() {
  [ -z "$user_pid" ] || kill "$user_pid" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"
reset_mc_fixture
mkdir -p "$repo/specs"
home="$tmp/mc-home/alpha"
proj="$tmp/work/proj"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo, $proj]
program_alpha_spec_root: $repo/specs
program_alpha_home: $home
EOF

g() { git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }

# A work repository with a remote, and a worktree per case.
git init -q --bare "$tmp/origin.git"
g clone -q "$tmp/origin.git" "$proj" 2>/dev/null
# The host's init.defaultBranch must not decide the fixture's branch name.
g -C "$proj" checkout -q -B main
printf '.claude/steps\n.claude/polish-audit.md\n.claude/handover.md\n' >"$proj/.gitignore"
g -C "$proj" add .gitignore
g -C "$proj" commit -qm init
g -C "$proj" push -q origin HEAD:main 2>/dev/null

# worktree <name> <branch>: a pushed worktree carrying audit files.
worktree() {
  wt="$tmp/work/$1"
  g -C "$proj" worktree add -q "$wt" -b "$2" main 2>/dev/null
  printf '%s\n' "$1" >"$wt/f"
  g -C "$wt" add f
  g -C "$wt" commit -qm "work $1"
  g -C "$wt" push -q -u origin "$2" 2>/dev/null
  mkdir -p "$wt/.claude/steps/000001"
  printf 'record of %s\n' "$1" >"$wt/.claude/steps/000001/001-done-pre-pr.rec"
  printf 'audit of %s\n' "$1" >"$wt/.claude/polish-audit.md"
}

# The gh stub: `pr list --head <b>` prints $GH_STUB/list.<b with / as _>;
# `pr view <n>` prints $GH_STUB/view.<n>.
mkdir -p "$tmp/bin" "$tmp/gh"
cat >"$tmp/bin/gh" <<'STUB'
#!/bin/sh
[ "$1" = pr ] || exit 1
case $2 in
  list)
    b=''
    while [ "$#" -gt 0 ]; do
      case $1 in --head) b=$2; shift 2 ;; *) shift ;; esac
    done
    f="$GH_STUB/list.$(printf '%s' "$b" | tr / _)"
    ;;
  view) f="$GH_STUB/view.$3" ;;
  *) exit 1 ;;
esac
[ -f "$f" ] || exit 0
cat "$f"
STUB
chmod +x "$tmp/bin/gh"
PATH="$tmp/bin:$PATH"
GH_STUB="$tmp/gh"
export PATH GH_STUB

# pr <branch> <number> <state> <oid> [<cross-repository>]: the forge's one PR
# for <branch>.
pr() {
  printf '%s %s %s %s\n' "$2" "$3" "$4" "${5:-false}" >"$GH_STUB/list.$(printf '%s' "$1" | tr / _)"
  printf '%s %s' "$3" "$4" >"$GH_STUB/view.$2"
}

reclaim() { mc_run mc-reclaim.sh "$@"; }
if command -v sha256sum >/dev/null 2>&1; then
  sha() { sha256sum "$1" | cut -c1-64; }
elif command -v shasum >/dev/null 2>&1; then
  sha() { shasum -a 256 "$1" | cut -c1-64; }
else
  echo "FAIL: no SHA-256 tool (sha256sum or shasum) to check the copies" >&2
  exit 1
fi

# --- each predicate arm refuses -------------------------------------------

worktree wt-open feat/open
pr feat/open 11 OPEN "$(git -C "$tmp/work/wt-open" rev-parse HEAD)"
reclaim reclaim --program alpha "$tmp/work/wt-open"
expect_rc "an open PR refuses the reclaim" 1
expect_out "the refusal names the PR arm" "pr-open"
[ -d "$tmp/work/wt-open" ] && ok "a refused reclaim leaves the worktree" || fail "a refused reclaim removed the worktree"

worktree wt-nopr feat/nopr
reclaim reclaim --program alpha "$tmp/work/wt-nopr"
expect_rc "a branch with no PR refuses the reclaim" 1
expect_out "the refusal says no PR was found" "no-pr"

worktree wt-dirty feat/dirty
pr feat/dirty 12 MERGED "$(git -C "$tmp/work/wt-dirty" rev-parse HEAD)"
printf 'stray\n' >"$tmp/work/wt-dirty/stray"
reclaim reclaim --program alpha "$tmp/work/wt-dirty"
expect_rc "an uncommitted file refuses the reclaim" 1
expect_out "the refusal names the uncommitted arm" "uncommitted"

worktree wt-ahead feat/ahead
pr feat/ahead 13 CLOSED "$(git -C "$tmp/work/wt-ahead" rev-parse HEAD)"
printf 'more\n' >>"$tmp/work/wt-ahead/f"
g -C "$tmp/work/wt-ahead" commit -qam more
reclaim reclaim --program alpha "$tmp/work/wt-ahead"
expect_rc "an unpushed commit refuses the reclaim" 1
expect_out "the refusal names the unpushed arm" "unpushed"

worktree wt-used feat/used
pr feat/used 14 MERGED "$(git -C "$tmp/work/wt-used" rev-parse HEAD)"
(cd "$tmp/work/wt-used" && exec sleep 600) &
user_pid=$!
reclaim reclaim --program alpha "$tmp/work/wt-used"
expect_rc "a live process in the worktree refuses the reclaim" 1
expect_out "the refusal names the live-user arm" "live-user"
kill "$user_pid" 2>/dev/null
wait "$user_pid" 2>/dev/null
user_pid=''

reclaim reclaim --program alpha "$proj"
expect_rc "the main checkout is never reclaimed" 1
expect_out "the refusal names the main checkout" "main-checkout"

worktree wt-hidden feat/hidden
pr feat/hidden 20 MERGED "$(git -C "$tmp/work/wt-hidden" rev-parse HEAD)"
g -C "$proj" config status.showUntrackedFiles no
printf 'stray\n' >"$tmp/work/wt-hidden/stray"
reclaim check --program alpha "$tmp/work/wt-hidden"
g -C "$proj" config --unset status.showUntrackedFiles
expect_rc "an untracked file the config hides from status still refuses" 1
expect_out "the hidden untracked file names the uncommitted arm" "uncommitted"

worktree wt-subdir feat/subdir
pr feat/subdir 21 MERGED "$(git -C "$tmp/work/wt-subdir" rev-parse HEAD)"
mkdir -p "$tmp/work/wt-subdir/.claude/steps/000001/deep"
(cd "$tmp/work/wt-subdir/.claude/steps/000001/deep" && exec sleep 600) &
user_pid=$!
reclaim check --program alpha "$tmp/work/wt-subdir"
expect_out "a process in a subdirectory refuses as a live user" "live-user"
kill "$user_pid" 2>/dev/null
wait "$user_pid" 2>/dev/null
user_pid=''

# A find without -lname, as busybox's, takes the per-process procfs walk.
worktree wt-nolname feat/nolname
pr feat/nolname 23 MERGED "$(git -C "$tmp/work/wt-nolname" rev-parse HEAD)"
mkdir -p "$tmp/nolname"
real_find=$(command -v find)
cat >"$tmp/nolname/find" <<STUB
#!/bin/sh
for a in "\$@"; do [ "\$a" = -lname ] && exit 1; done
exec '$real_find' "\$@"
STUB
chmod +x "$tmp/nolname/find"
(cd "$tmp/work/wt-nolname" && exec sleep 600) &
user_pid=$!
OUT=$(PATH="$tmp/nolname:$PATH" mc_env /bin/bash "$repo_root/scripts/mc-reclaim.sh" check --program alpha "$tmp/work/wt-nolname" 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "a find without -lname still refuses a live user" 1
expect_out "the -lname-less walk names the live-user arm" "live-user"
kill "$user_pid" 2>/dev/null
wait "$user_pid" 2>/dev/null
user_pid=''

worktree wt-mergedhead feat/mergedhead
printf 'local\n' >>"$tmp/work/wt-mergedhead/f"
g -C "$tmp/work/wt-mergedhead" commit -qam local
pr feat/mergedhead 22 MERGED "$(git -C "$tmp/work/wt-mergedhead" rev-parse HEAD)"
reclaim check --program alpha "$tmp/work/wt-mergedhead"
expect_rc "a commit the remote branch lacks passes when the PR merged at exactly HEAD" 0
pr feat/mergedhead 22 MERGED "$(git -C "$tmp/work/wt-mergedhead" rev-parse HEAD~1)"
reclaim check --program alpha "$tmp/work/wt-mergedhead"
expect_out "a PR merged at another head does not excuse an unpushed commit" "unpushed"

worktree wt-fork feat/fork
pr feat/fork 23 MERGED "$(git -C "$tmp/work/wt-fork" rev-parse HEAD)" true
reclaim check --program alpha "$tmp/work/wt-fork"
expect_out "a PR from a fork does not count for the branch" "no-pr"
pr feat/fork 23 DRAFTED "$(git -C "$tmp/work/wt-fork" rev-parse HEAD)"
reclaim check --program alpha "$tmp/work/wt-fork"
expect_out "a PR state the script does not know refuses" "pr-unreadable"

git init -q "$tmp/other"
g -C "$tmp/other" commit -q --allow-empty -m init
g -C "$tmp/other" worktree add -q "$tmp/work/wt-foreign" -b feat/foreign 2>/dev/null
reclaim check --program alpha "$tmp/work/wt-foreign"
expect_out "a worktree of a repository the program does not list is refused" "not-program-repo"

worktree wt-forged feat/forged
pr feat/forged 24 MERGED "$(git -C "$tmp/work/wt-forged" rev-parse HEAD)"
printf 'gitdir: %s\n' "$(git -C "$tmp/other" rev-parse --absolute-git-dir)" >"$tmp/work/wt-forged/.git"
reclaim check --program alpha "$tmp/work/wt-forged"
expect_out "a .git file pointing elsewhere is not trusted" "not-program-repo"

worktree wt-borrow feat/borrow
pr feat/borrow 27 MERGED "$(git -C "$tmp/work/wt-borrow" rev-parse HEAD)"
cp "$tmp/work/wt-open/.git" "$tmp/work/wt-borrow/.git"
reclaim check --program alpha "$tmp/work/wt-borrow"
expect_out "a .git file borrowing another worktree's git directory is not trusted" "not-program-repo"

worktree wt-noup feat/noup
g -C "$tmp/work/wt-noup" branch -q --unset-upstream
pr feat/noup 28 CLOSED "$(git -C "$tmp/work/wt-noup" rev-parse HEAD)"
reclaim check --program alpha "$tmp/work/wt-noup"
expect_out "no upstream and no PR merged at HEAD refuses as unpushed" "unpushed"

worktree wt-sub feat/sub
g -C "$tmp/work/wt-sub" update-index --add --cacheinfo "160000,$(git -C "$tmp/work/wt-sub" rev-parse HEAD),sub"
g -C "$tmp/work/wt-sub" commit -qm sub
g -C "$tmp/work/wt-sub" push -q 2>/dev/null
pr feat/sub 29 MERGED "$(git -C "$tmp/work/wt-sub" rev-parse HEAD)"
reclaim check --program alpha "$tmp/work/wt-sub"
expect_out "a worktree holding a submodule is refused" "submodule"

# --- the backup is verified before anything goes ----------------------------

worktree wt-cpfail feat/cpfail
pr feat/cpfail 15 MERGED "$(git -C "$tmp/work/wt-cpfail" rev-parse HEAD)"
mkdir -p "$tmp/badcp"
printf '#!/bin/sh\nexit 1\n' >"$tmp/badcp/cp"
chmod +x "$tmp/badcp/cp"
OUT=$(PATH="$tmp/badcp:$PATH" mc_env /bin/bash "$repo_root/scripts/mc-reclaim.sh" reclaim --program alpha "$tmp/work/wt-cpfail" 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "a failed backup refuses the reclaim" 1
expect_out "the refusal says the backup failed" "backup"
expect_out "the refusal says which copy failed" "the copy of .claude/"
[ -d "$tmp/work/wt-cpfail" ] && ok "a failed backup leaves the worktree" || fail "a failed backup removed the worktree"

worktree wt-link feat/link
pr feat/link 25 MERGED "$(git -C "$tmp/work/wt-link" rev-parse HEAD)"
printf 'outside secret\n' >"$tmp/outside.txt"
ln -s "$tmp/outside.txt" "$tmp/work/wt-link/.claude/steps/leak"
reclaim reclaim --program alpha "$tmp/work/wt-link"
expect_rc "a worktree holding a symbolic link still reclaims" 0
[ ! -e "$home/reclaimed/proj/feat/link/.claude/steps/leak" ] && ok "a symbolic link is never followed into the backup" \
  || fail "the backup followed a symbolic link out of the worktree"

worktree wt-clash feat/clash
pr feat/clash 26 MERGED "$(git -C "$tmp/work/wt-clash" rev-parse HEAD)"
mkdir -p "$home/reclaimed/proj/feat/clash/.claude"
printf 'an older audit\n' >"$home/reclaimed/proj/feat/clash/.claude/polish-audit.md"
reclaim reclaim --program alpha "$tmp/work/wt-clash"
expect_rc "a different file already in the reclaim folder refuses" 1
expect_out "the refusal names the clash" "already holds a different"
[ "$(cat "$home/reclaimed/proj/feat/clash/.claude/polish-audit.md")" = "an older audit" ] \
  && ok "the older file is kept" || fail "the older file was overwritten"
[ -d "$tmp/work/wt-clash" ] && ok "a clash leaves the worktree" || fail "a clash removed the worktree"

worktree wt-linkdir feat/linkdir
pr feat/linkdir 31 MERGED "$(git -C "$tmp/work/wt-linkdir" rev-parse HEAD)"
mkdir -p "$tmp/elsewhere" "$home/reclaimed/proj/feat/linkdir"
ln -s "$tmp/elsewhere" "$home/reclaimed/proj/feat/linkdir/.claude"
reclaim reclaim --program alpha "$tmp/work/wt-linkdir"
expect_out "a symbolic link on the way into the reclaim folder refuses" "is a symbolic link"
[ -z "$(find "$tmp/elsewhere" -type f)" ] && ok "nothing is copied through the link" || fail "a copy went through the link"
rm -f "$home/reclaimed/proj/feat/linkdir/.claude"

worktree wt-paused feat/paused
pr feat/paused 30 MERGED "$(git -C "$tmp/work/wt-paused" rev-parse HEAD)"
printf 'fleet_daemon_pause: true\n' >>"$tracked"
reclaim reclaim --program alpha "$tmp/work/wt-paused"
sed -i.bak '/^fleet_daemon_pause: true$/d' "$tracked" && rm -f "$tracked.bak"
expect_rc "a removal fleet-cleanup refuses refuses the reclaim" 1
expect_out "the refusal names the removal arm" "removal"
[ -d "$tmp/work/wt-paused" ] && ok "a refused removal leaves the worktree" || fail "a refused removal removed the worktree"
[ -f "$home/reclaimed/proj/feat/paused/.claude/polish-audit.md" ] && ok "a refused removal keeps the verified copies" \
  || fail "a refused removal took the copies back"

worktree wt-corrupt feat/corrupt
pr feat/corrupt 16 MERGED "$(git -C "$tmp/work/wt-corrupt" rev-parse HEAD)"
mkdir -p "$tmp/corruptcp"
# Same length, other bytes: only the hash can tell.
cat >"$tmp/corruptcp/cp" <<'EOF'
#!/bin/sh
for last; do :; done
tr 'a-z' 'b-za' <"$1" >"$last"
EOF
chmod +x "$tmp/corruptcp/cp"
OUT=$(PATH="$tmp/corruptcp:$PATH" mc_env /bin/bash "$repo_root/scripts/mc-reclaim.sh" reclaim --program alpha "$tmp/work/wt-corrupt" 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "a hash mismatch refuses the reclaim" 1
expect_out "the refusal names the hash mismatch" "hash mismatch"
[ -d "$tmp/work/wt-corrupt" ] && ok "a hash mismatch leaves the worktree" || fail "a hash mismatch removed the worktree"
[ ! -e "$home/reclaimed/proj/feat/corrupt" ] && ok "a refused backup takes its copies and folders back" \
  || fail "a refused backup left copies or folders in the reclaim folder"
OUT=$(PATH="$tmp/corruptcp:$PATH" mc_env /bin/bash "$repo_root/scripts/mc-reclaim.sh" reclaim --program alpha "$tmp/work/wt-corrupt" 2>"$tmp/stderr")
RC=$?
expect_out "a retry meets the mismatch again, not a leftover copy" "hash mismatch"

# --- check reports without acting ------------------------------------------

worktree wt-done feat/done
head=$(git -C "$tmp/work/wt-done" rev-parse HEAD)
pr feat/done 17 MERGED "$head"
reclaim check --program alpha "$tmp/work/wt-done"
expect_rc "check passes a reclaimable worktree" 0
expect_out "check names the landed PR" "merged"
[ -d "$tmp/work/wt-done" ] && ok "check removes nothing" || fail "check removed the worktree"
[ ! -e "$home/reclaimed/proj/feat/done" ] && ok "check copies nothing" || fail "check wrote into the program home"

# --- a complete reclaim -----------------------------------------------------

want_rec=$(sha "$tmp/work/wt-done/.claude/steps/000001/001-done-pre-pr.rec")
want_audit=$(sha "$tmp/work/wt-done/.claude/polish-audit.md")
reclaim reclaim --program alpha "$tmp/work/wt-done"
expect_rc "a complete fixture reclaims" 0
expect_out "the reclaim reports the folder" "$home/reclaimed/proj/feat/done"
[ ! -e "$tmp/work/wt-done" ] && ok "the worktree is gone" || fail "the worktree is still there"
dest="$home/reclaimed/proj/feat/done"
[ "$(sha "$dest/.claude/steps/000001/001-done-pre-pr.rec")" = "$want_rec" ] \
  && ok "the step record sits in the reclaim folder with its hash" || fail "the step record is missing or differs"
[ "$(sha "$dest/.claude/polish-audit.md")" = "$want_audit" ] \
  && ok "the polish audit sits in the reclaim folder with its hash" || fail "the polish audit is missing or differs"
[ ! -e "$dest/f" ] && ok "a tracked file is not copied" || fail "a tracked file was copied"

worktree wt-closed feat/closed
pr feat/closed 18 CLOSED "$(git -C "$tmp/work/wt-closed" rev-parse HEAD)"
reclaim reclaim --program alpha "$tmp/work/wt-closed"
expect_rc "a pushed worktree whose PR closed reclaims" 0
[ -f "$home/reclaimed/proj/feat/closed/.claude/polish-audit.md" ] && ok "the closed branch has its own folder" \
  || fail "the closed branch's files are missing"

# --- the file set is a knob --------------------------------------------------

printf 'mission_control_reclaim_files: [notes/*.log]\n' >>"$tracked"
worktree wt-knob feat/knob
printf 'notes/\n' >>"$(git -C "$tmp/work/wt-knob" rev-parse --git-common-dir)/info/exclude"
mkdir -p "$tmp/work/wt-knob/notes"
printf 'kept\n' >"$tmp/work/wt-knob/notes/run.log"
printf 'tracked\n' >"$tmp/work/wt-knob/notes/tracked.log"
g -C "$tmp/work/wt-knob" add -f notes/tracked.log
g -C "$tmp/work/wt-knob" commit -qm tracked
g -C "$tmp/work/wt-knob" push -q 2>/dev/null
pr feat/knob 19 MERGED "$(git -C "$tmp/work/wt-knob" rev-parse HEAD)"
reclaim reclaim --program alpha "$tmp/work/wt-knob"
expect_rc "a reclaim under a configured file set" 0
expect_out "the reclaim counts the files it backed up" "1 files"
[ -f "$home/reclaimed/proj/feat/knob/notes/run.log" ] && ok "the configured pattern is copied" || fail "the configured pattern was not copied"
[ ! -e "$home/reclaimed/proj/feat/knob/notes/tracked.log" ] && ok "a tracked file the pattern matches is not copied" \
  || fail "a tracked file was copied"
[ ! -e "$home/reclaimed/proj/feat/knob/.claude/polish-audit.md" ] && ok "the default set is replaced, not added to" \
  || fail "the default set was copied under a configured one"

# --- refusals ---------------------------------------------------------------

reclaim reclaim --program alpha relative/path
expect_rc "a relative path is refused" 2
reclaim reclaim --program gamma "$tmp/work/wt-open"
expect_rc "an unconfigured program is refused" 3

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mc-reclaim tests passed"
