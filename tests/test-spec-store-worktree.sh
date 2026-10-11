#!/bin/bash
# scripts/spec-store-worktree.sh: with the spec root in a holder repository,
# the spec branch and the spec worktree are created in the holder, at
# <holder>/.claude/worktrees/<id>-spec on planwright/<id>/spec, and the work
# repository gains no commit or branch (custom-spec-location REQ-E1.2,
# REQ-B1.3, D-12). Every other posture is refused, so the caller keeps its
# own path for them.
set -u
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
S="$REPO_ROOT/scripts"

failures=0
ok() { echo "ok: $1"; }
fail() {
  printf 'FAIL: %s\n' "$1" | tr -d '\000-\010\013-\037\177' >&2
  failures=$((failures + 1))
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/spec-store-wt.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

inherited_unsets=$(env | sed -n 's/^\(PLANWRIGHT_[A-Za-z0-9_]*\)=.*/-u \1/p')
mkdir -p "$tmp/home"
hermetic() {
  # shellcheck disable=SC2086 # one `-u NAME` pair per word
  env $inherited_unsets -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR \
    HOME="$tmp/home" GIT_CEILING_DIRECTORIES="$tmp" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
    GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
    PLANWRIGHT_ROOT="$REPO_ROOT" "$@"
}
gitq() { hermetic git "$@" >/dev/null 2>&1; }
# sw <dir> <args...> — spec-store-worktree.sh from <dir>; sets out, err, rc.
sw() {
  s_dir=$1
  shift
  out=$(cd "$s_dir" && hermetic "$S/spec-store-worktree.sh" "$@" 2>"$tmp/err")
  rc=$?
  err=$(cat "$tmp/err")
}
field() { printf '%s\n' "$out" | sed -n "s/^$1	//p"; }

# work_repo <dir> — a work repository with one commit on main.
work_repo() {
  gitq -c init.defaultBranch=main init -q "$1"
  printf 'x\n' >"$1/file"
  gitq -C "$1" add -A && gitq -C "$1" commit -q -m init
}
# holder <dir> <default-branch> <rel-root> — a holder with a marked root at
# <dir>/<rel-root>, pushed to a bare origin whose HEAD names the branch.
holder() {
  gitq -c init.defaultBranch="$2" init -q --bare "$1-origin.git"
  gitq -c init.defaultBranch="$2" init -q "$1"
  mkdir -p "$1/$3"
  printf 'project: fixture\nlayout: 1\n' >"$1/$3/planwright-spec-root.yml"
  gitq -C "$1" add -A && gitq -C "$1" commit -q -m root
  gitq -C "$1" remote add origin "$1-origin.git"
  gitq -C "$1" push -q -u origin "$2"
  gitq -C "$1" remote set-head origin --auto
}
point() {
  mkdir -p "$1/.claude"
  printf 'spec_root: %s\n' "$2" >"$1/.claude/planwright.local.yml"
}
refs() { hermetic git -C "$1" for-each-ref --format='%(refname) %(objectname)'; }

# --- REQ-E1.2: the holder gets the branch and the worktree -----------------
W="$tmp/work"
H="$tmp/holder"
work_repo "$W"
holder "$H" trunk projects/demo-root
point "$W" "$H/projects/demo-root"
work_refs_before=$(refs "$W")

sw "$W" demo
if [ "$rc" -eq 0 ]; then ok "separate-repo: exits 0"; else fail "separate-repo: rc=$rc err=$err"; fi
wt="$H/.claude/worktrees/demo-spec"
if [ "$(field worktree)" = "$wt" ]; then ok "the worktree is <holder>/.claude/worktrees/<id>-spec"; else fail "worktree field: $out"; fi
if [ "$(field bundle)" = "$wt/projects/demo-root/demo" ]; then
  ok "the bundle path is the root's place inside the holder worktree"
else
  fail "bundle field: $out"
fi
if [ "$(field branch)" = "planwright/demo/spec" ]; then ok "the branch field names the spec branch"; else fail "branch field: $out"; fi
if [ "$(hermetic git -C "$wt" symbolic-ref -q --short HEAD 2>/dev/null)" = "planwright/demo/spec" ]; then
  ok "the holder worktree is on planwright/<id>/spec"
else
  fail "the holder worktree is not on the spec branch"
fi
if [ "$(hermetic git -C "$wt" rev-parse HEAD 2>/dev/null)" = "$(hermetic git -C "$H" rev-parse origin/trunk 2>/dev/null)" ]; then
  ok "the spec branch starts at the holder's default branch (not named main)"
else
  fail "the spec branch does not start at origin/trunk"
fi
if [ -z "$(hermetic git -C "$wt" config --get branch.planwright/demo/spec.remote 2>/dev/null)" ]; then
  ok "the spec branch tracks no upstream until it is pushed"
else
  fail "the spec branch was set to track its base"
fi
if [ "$(refs "$W")" = "$work_refs_before" ] && [ ! -e "$W/.claude/worktrees" ]; then
  ok "the work repository gains no commit, branch, or worktree"
else
  fail "the work repository changed"
fi

# Idempotent: a second run reuses the worktree.
head1=$(hermetic git -C "$wt" rev-parse HEAD)
printf 'draft\n' >"$wt/projects/demo-root/note"
sw "$W" demo
if [ "$rc" -eq 0 ] && [ "$(field worktree)" = "$wt" ] && [ -f "$wt/projects/demo-root/note" ] \
  && [ "$(hermetic git -C "$wt" rev-parse HEAD)" = "$head1" ]; then
  ok "a second run reuses the existing worktree untouched"
else
  fail "re-run: rc=$rc out=$out err=$err"
fi
rm -f "$wt/projects/demo-root/note"

# The alias form maps to the identifier, with one trailing slash.
sw "$W" specs/demo/
if [ "$rc" -eq 0 ] && [ "$(field worktree)" = "$wt" ]; then ok "the alias specs/<id>/ is accepted"; else fail "alias: rc=$rc err=$err"; fi

# A pruned worktree whose branch survives is recreated from the branch.
printf 'kept\n' >"$wt/kept"
gitq -C "$wt" add kept && gitq -C "$wt" commit -q -m kept
kept=$(hermetic git -C "$wt" rev-parse HEAD)
gitq -C "$H" worktree remove --force "$wt"
sw "$W" demo
if [ "$rc" -eq 0 ] && [ "$(hermetic git -C "$wt" rev-parse HEAD 2>/dev/null)" = "$kept" ]; then
  ok "a pruned worktree is recreated from the surviving branch"
else
  fail "recreate: rc=$rc err=$err"
fi

# A directory at the worktree path that is not the spec branch is refused.
mkdir -p "$H/.claude/worktrees/other-spec"
printf 'stray\n' >"$H/.claude/worktrees/other-spec/stray"
sw "$W" other
if [ "$rc" -eq 4 ] && [ -f "$H/.claude/worktrees/other-spec/stray" ]; then
  ok "a foreign directory at the worktree path is refused, left untouched"
else
  fail "foreign dir: rc=$rc err=$err"
fi

# A symlinked .claude in the holder is refused rather than followed.
H2="$tmp/holder2"
W2="$tmp/work2"
work_repo "$W2"
holder "$H2" main root
mkdir -p "$tmp/elsewhere"
ln -s "$tmp/elsewhere" "$H2/.claude"
point "$W2" "$H2/root"
sw "$W2" demo
if [ "$rc" -eq 4 ] && [ -z "$(ls -A "$tmp/elsewhere")" ]; then
  ok "a symlinked .claude in the holder is refused"
else
  fail "symlinked .claude: rc=$rc err=$err"
fi
rm "$H2/.claude"

# A .claude that is not a directory is refused before git creates a branch.
printf 'not a dir\n' >"$H2/.claude"
sw "$W2" demo
if [ "$rc" -eq 4 ] && ! hermetic git -C "$H2" show-ref --verify --quiet refs/heads/planwright/demo/spec; then
  ok "a non-directory .claude is refused, leaving no stray branch"
else
  fail "non-directory .claude: rc=$rc err=$err"
fi
rm "$H2/.claude"

# A holder with no remote branches from its own HEAD branch.
H3="$tmp/holder3"
W3="$tmp/work3"
work_repo "$W3"
gitq -c init.defaultBranch=develop init -q "$H3"
mkdir -p "$H3/r"
printf 'project: fixture\nlayout: 1\n' >"$H3/r/planwright-spec-root.yml"
gitq -C "$H3" add -A && gitq -C "$H3" commit -q -m root
point "$W3" "$H3/r"
sw "$W3" demo
if [ "$rc" -eq 0 ] && [ "$(hermetic git -C "$H3/.claude/worktrees/demo-spec" rev-parse HEAD 2>/dev/null)" = "$(hermetic git -C "$H3" rev-parse develop)" ]; then
  ok "with no remote, the branch starts at the holder's HEAD branch"
else
  fail "no remote: rc=$rc err=$err"
fi

# A recorded origin/HEAD whose target is gone falls back to the HEAD branch.
H6="$tmp/holder6"
W6="$tmp/work6"
work_repo "$W6"
holder "$H6" trunk r
gitq -C "$H6" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/gone
point "$W6" "$H6/r"
sw "$W6" demo
if [ "$rc" -eq 0 ] && [ "$(hermetic git -C "$H6/.claude/worktrees/demo-spec" rev-parse HEAD 2>/dev/null)" = "$(hermetic git -C "$H6" rev-parse trunk)" ]; then
  ok "a dangling origin/HEAD falls back to the holder's HEAD branch"
else
  fail "dangling origin/HEAD: rc=$rc err=$err"
fi

# A failed add names git's own reason: the spec branch checked out elsewhere.
gitq -C "$H6" branch planwright/busy/spec trunk
gitq -C "$H6" switch -q planwright/busy/spec
sw "$W6" busy
if [ "$rc" -eq 4 ] && printf '%s' "$err" | grep -q 'already'; then
  ok "a failed add passes git's reason through"
else
  fail "busy branch: rc=$rc err=$err"
fi
gitq -C "$H6" switch -q trunk

# A holder hook failing after git opened the worktree is not a failure.
printf '#!/bin/sh\nexit 1\n' >"$H6/.git/hooks/post-checkout"
chmod +x "$H6/.git/hooks/post-checkout"
sw "$W6" hooked
if [ "$rc" -eq 0 ] && [ "$(hermetic git -C "$H6/.claude/worktrees/hooked-spec" symbolic-ref -q --short HEAD 2>/dev/null)" = "planwright/hooked/spec" ]; then
  ok "an opened worktree is reported ready though a holder hook failed"
else
  fail "hook failure: rc=$rc err=$err"
fi
rm -f "$H6/.git/hooks/post-checkout"

# A spec branch that survives only on origin is picked up, not restarted.
gitq -C "$H6" switch -q -c planwright/remote/spec trunk
printf 'pushed\n' >"$H6/r/pushed" && gitq -C "$H6" add r/pushed && gitq -C "$H6" commit -q -m pushed
gitq -C "$H6" push -q origin planwright/remote/spec
pushed=$(hermetic git -C "$H6" rev-parse HEAD)
gitq -C "$H6" switch -q trunk
gitq -C "$H6" branch -q -D planwright/remote/spec
sw "$W6" remote
if [ "$rc" -eq 0 ] && [ "$(hermetic git -C "$H6/.claude/worktrees/remote-spec" rev-parse HEAD 2>/dev/null)" = "$pushed" ] \
  && [ "$(hermetic git -C "$H6" config --get branch.planwright/remote/spec.remote 2>/dev/null)" = origin ]; then
  ok "a spec branch only on origin is checked out tracking it"
else
  fail "remote-only branch: rc=$rc err=$err"
fi

# A root at the holder's top level puts the bundle at the worktree's top.
H8="$tmp/holder8"
W8="$tmp/work8"
work_repo "$W8"
holder "$H8" trunk .
point "$W8" "$H8"
# origin/HEAD wins over the branch the primary checkout has out.
gitq -C "$H8" switch -q -c feature
printf 'ahead\n' >"$H8/ahead" && gitq -C "$H8" add ahead && gitq -C "$H8" commit -q -m ahead
sw "$W8" demo
wt8="$H8/.claude/worktrees/demo-spec"
if [ "$rc" -eq 0 ] && [ "$(field bundle)" = "$wt8/demo" ]; then
  ok "a root at the holder's top level gives the bundle <worktree>/<id>"
else
  fail "top-level root: rc=$rc out=$out err=$err"
fi
if [ "$(hermetic git -C "$wt8" rev-parse HEAD 2>/dev/null)" = "$(hermetic git -C "$H8" rev-parse origin/trunk)" ] \
  && [ "$(hermetic git -C "$wt8" rev-parse HEAD 2>/dev/null)" != "$(hermetic git -C "$H8" rev-parse HEAD)" ]; then
  ok "the spec branch starts at origin/HEAD, not the checked-out branch"
else
  fail "base preference: the spec branch did not start at origin/trunk"
fi

# Reuse refuses a holder worktree on another branch, and a symlink to a
# valid spec worktree.
gitq -C "$H8" worktree add -q -b side "$H8/.claude/worktrees/x-spec" trunk
sw "$W8" x
if [ "$rc" -eq 4 ]; then ok "a holder worktree on another branch is refused"; else fail "wrong-branch worktree: rc=$rc"; fi
ln -s "$wt8" "$H8/.claude/worktrees/y-spec"
sw "$W8" y
if [ "$rc" -eq 4 ]; then ok "a symlink at the worktree path is refused"; else fail "symlinked worktree path: rc=$rc"; fi

# A symlinked .claude/worktrees in the holder is refused.
H9="$tmp/holder9"
W9="$tmp/work9"
work_repo "$W9"
holder "$H9" main r
mkdir -p "$H9/.claude" "$tmp/elsewhere9"
ln -s "$tmp/elsewhere9" "$H9/.claude/worktrees"
point "$W9" "$H9/r"
sw "$W9" demo
if [ "$rc" -eq 4 ] && [ -z "$(ls -A "$tmp/elsewhere9")" ]; then
  ok "a symlinked .claude/worktrees in the holder is refused"
else
  fail "symlinked .claude/worktrees: rc=$rc err=$err"
fi

# An unborn holder has no default branch to start from.
H10="$tmp/holder10"
W10="$tmp/work10"
work_repo "$W10"
gitq -c init.defaultBranch=main init -q "$H10"
mkdir -p "$H10/r"
printf 'project: fixture\nlayout: 1\n' >"$H10/r/planwright-spec-root.yml"
point "$W10" "$H10/r"
sw "$W10" demo
if [ "$rc" -eq 4 ] && [ ! -e "$H10/.claude/worktrees/demo-spec" ]; then
  ok "an unborn holder is refused with exit 4"
else
  fail "unborn holder: rc=$rc err=$err"
fi

# A spec root that does not resolve is exit 4, not a posture refusal.
W11="$tmp/work11"
work_repo "$W11"
point "$W11" "$tmp/no-such-root"
sw "$W11" demo
if [ "$rc" -eq 4 ] && [ -z "$out" ]; then ok "an unresolvable root exits 4"; else fail "unresolvable root: rc=$rc out=$out"; fi

# --- the printed bundle path never leaves the holder worktree --------------
# A symlink committed at the root's path on the spec branch.
sw "$W" sym
symwt="$H/.claude/worktrees/sym-spec"
mkdir -p "$tmp/outside"
rm -rf "$symwt/projects/demo-root"
ln -s "$tmp/outside" "$symwt/projects/demo-root"
gitq -C "$symwt" add -A && gitq -C "$symwt" commit -q -m swap
sw "$W" sym
if [ "$rc" -eq 4 ] && [ -z "$out" ] && printf '%s' "$err" | grep -q 'symlink'; then
  ok "a symlinked root path in the reused worktree is refused, no path printed"
else
  fail "symlinked root on reuse: rc=$rc out=$out err=$err"
fi
gitq -C "$H" worktree remove --force "$symwt"
sw "$W" sym
if [ "$rc" -eq 4 ] && [ -z "$out" ]; then
  ok "a symlinked root path on a recreated worktree is refused"
else
  fail "symlinked root on recreate: rc=$rc out=$out err=$err"
fi
# A symlink committed at the bundle directory itself.
sw "$W" symb
symbwt="$H/.claude/worktrees/symb-spec"
mkdir -p "$tmp/outside2"
ln -s "$tmp/outside2" "$symbwt/projects/demo-root/symb"
gitq -C "$symbwt" add -A && gitq -C "$symbwt" commit -q -m link
sw "$W" symb
if [ "$rc" -eq 4 ] && [ -z "$out" ] && [ -z "$(ls -A "$tmp/outside2")" ]; then
  ok "a symlinked bundle directory is refused"
else
  fail "symlinked bundle: rc=$rc out=$out err=$err"
fi

# A root path with a space and a glob byte is walked component by component:
# a committed symlink the glob would match must not be what gets checked.
H12="$tmp/holder12"
W12="$tmp/work12"
work_repo "$W12"
holder "$H12" main 'spec roots/a*'
ln -s "$tmp/outside" "$H12/spec roots/ab"
gitq -C "$H12" add -A && gitq -C "$H12" commit -q -m decoy && gitq -C "$H12" push -q origin main
point "$W12" "$H12/spec roots/a*"
sw "$W12" demo
if [ "$rc" -eq 0 ] && [ -L "$H12/.claude/worktrees/demo-spec/spec roots/ab" ] \
  && [ "$(field bundle)" = "$H12/.claude/worktrees/demo-spec/spec roots/a*/demo" ]; then
  ok "a root path with a space and a glob byte is printed as it is"
else
  fail "spaced root: rc=$rc out=$out err=$err"
fi

# --- one holder, two projects: a spec id is not shared across them ----------
HM="$tmp/multi"
WA="$tmp/work-a"
WB="$tmp/work-b"
work_repo "$WA"
work_repo "$WB"
holder "$HM" main projects/a
mkdir -p "$HM/projects/b"
printf 'project: other\nlayout: 1\n' >"$HM/projects/b/planwright-spec-root.yml"
gitq -C "$HM" add -A && gitq -C "$HM" commit -q -m b && gitq -C "$HM" push -q origin main
point "$WA" "$HM/projects/a"
point "$WB" "$HM/projects/b"
sw "$WA" shared
wta="$HM/.claude/worktrees/shared-spec"
mkdir -p "$wta/projects/a/shared"
printf '# a\n' >"$wta/projects/a/shared/requirements.md"
gitq -C "$wta" add -A && gitq -C "$wta" commit -q -m "draft a"
sw "$WA" shared
if [ "$rc" -eq 0 ] && [ "$(field worktree)" = "$wta" ]; then
  ok "the owning project reuses its own spec branch"
else
  fail "owner reuse: rc=$rc err=$err"
fi
sw "$WB" shared
if [ "$rc" -eq 4 ] && [ -z "$out" ] && printf '%s' "$err" | grep -q 'projects/a/shared'; then
  ok "another project's spec branch with the same id is refused, naming its bundle"
else
  fail "cross-project reuse: rc=$rc out=$out err=$err"
fi
out=$(cd "$WB" && hermetic env GIT_LITERAL_PATHSPECS=1 "$S/spec-store-worktree.sh" shared 2>/dev/null)
rc=$?
if [ "$rc" -eq 4 ] && [ -z "$out" ]; then
  ok "an inherited GIT_LITERAL_PATHSPECS does not switch the refusal off"
else
  fail "literal pathspecs env: rc=$rc out=$out"
fi
gitq -C "$HM" worktree remove --force "$wta"
sw "$WB" shared
if [ "$rc" -eq 4 ] && [ -z "$out" ] && [ ! -e "$wta" ]; then
  ok "the refusal holds when only the branch survives"
else
  fail "cross-project recreate: rc=$rc out=$out err=$err"
fi
gitq -C "$HM" push -q origin planwright/shared/spec
gitq -C "$HM" branch -D planwright/shared/spec
sw "$WB" shared
if [ "$rc" -eq 4 ] && [ -z "$out" ] && ! hermetic git -C "$HM" show-ref --verify --quiet refs/heads/planwright/shared/spec; then
  ok "the refusal holds when the branch survives only on origin"
else
  fail "cross-project origin: rc=$rc out=$out err=$err"
fi
sw "$WA" shared
if [ "$rc" -eq 0 ]; then ok "the owning project still recreates from origin"; else fail "owner origin: rc=$rc err=$err"; fi
# A draft not yet committed is owned all the same.
sw "$WA" fresh
wtf="$HM/.claude/worktrees/fresh-spec"
mkdir -p "$wtf/projects/a/fresh"
printf '# a\n' >"$wtf/projects/a/fresh/requirements.md"
sw "$WB" fresh
if [ "$rc" -eq 4 ] && [ -z "$out" ] && printf '%s' "$err" | grep -q 'projects/a/fresh'; then
  ok "another project's uncommitted draft in the worktree is refused"
else
  fail "uncommitted cross-project reuse: rc=$rc out=$out err=$err"
fi
sw "$WA" fresh
if [ "$rc" -eq 0 ]; then ok "the owner reuses its worktree holding an uncommitted draft"; else fail "owner uncommitted: rc=$rc err=$err"; fi
# The root's own content other than the bundle never reads as foreign, even
# when the identifier names a directory on its path or under it.
for own_id in projects archive; do
  sw "$WA" "$own_id"
  wto="$HM/.claude/worktrees/$own_id-spec"
  mkdir -p "$wto/projects/a/$own_id" "$wto/projects/a/_observations/archive"
  printf '# a\n' >"$wto/projects/a/$own_id/requirements.md"
  printf 'n\n' >"$wto/projects/a/$own_id/note \"q\".md"
  printf 'obs\n' >"$wto/projects/a/_observations/archive/x.md"
  gitq -C "$wto" add -A && gitq -C "$wto" commit -q -m "draft $own_id"
  sw "$WA" "$own_id"
  if [ "$rc" -eq 0 ]; then
    ok "the owner's own branch is not foreign: id $own_id"
  else
    fail "own branch refused: id $own_id rc=$rc err=$err"
  fi
done
# A spec branch sharing no history with the default branch names git's reason.
gitq -C "$HM" switch -q --orphan planwright/orph/spec
printf 'o\n' >"$HM/o" && gitq -C "$HM" add o && gitq -C "$HM" commit -q -m orphan
gitq -C "$HM" switch -q -f main
sw "$WA" orph
if [ "$rc" -eq 4 ] && printf '%s' "$err" | grep -qi 'merge base'; then
  ok "a spec branch with no merge base is refused with git's reason"
else
  fail "orphan spec branch: rc=$rc err=$err"
fi

# --- other postures and bad identifiers are refused -----------------------
W4="$tmp/work4"
work_repo "$W4"
sw "$W4" demo
if [ "$rc" -eq 3 ] && [ -z "$out" ] && printf '%s' "$err" | grep -q 'same-repo'; then
  ok "same-repo is refused with exit 3, naming the posture"
else
  fail "same-repo: rc=$rc out=$out err=$err"
fi
mkdir -p "$tmp/plain"
printf 'project: fixture\nlayout: 1\n' >"$tmp/plain/planwright-spec-root.yml"
W5="$tmp/work5"
work_repo "$W5"
point "$W5" "$tmp/plain"
sw "$W5" demo
plain_entries=$(cd "$tmp/plain" && find . -mindepth 1 ! -name planwright-spec-root.yml)
if [ "$rc" -eq 3 ] && [ -z "$plain_entries" ] && printf '%s' "$err" | grep -q 'plain'; then
  ok "plain is refused with exit 3 and nothing written"
else
  fail "plain: rc=$rc err=$err"
fi
for good in specs/demo demo/; do
  sw "$W" "$good"
  if [ "$rc" -eq 0 ] && [ "$(field worktree)" = "$wt" ]; then ok "identifier form accepted: $good"; else fail "identifier form refused: $good rc=$rc"; fi
done
long=$(printf '%065d' 0 | tr 0 a)
for bad in 'Demo' 'flight' 'a/b' 'specs/demo/requirements.md' '../x' '' "$(printf 'a\nb')" '-x' "$long"; do
  sw "$W" "$bad"
  if [ "$rc" -eq 2 ] && [ -z "$out" ]; then
    ok "identifier refused: $(printf '%s' "$bad" | tr '\n' '?')"
  else
    fail "identifier accepted: $(printf '%s' "$bad" | tr '\n' '?') rc=$rc"
  fi
done
sw "$W"
if [ "$rc" -eq 2 ]; then ok "a missing argument is a usage error"; else fail "no argument: rc=$rc"; fi

if [ "$failures" -ne 0 ]; then
  echo "FAIL: test-spec-store-worktree.sh ($failures failure(s))" >&2
  exit 1
fi
echo "PASS: test-spec-store-worktree.sh"
