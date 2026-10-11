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
for bad in 'Demo' 'flight' 'a/b' 'specs/demo/requirements.md' '../x' '' "$(printf 'a\nb')"; do
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
