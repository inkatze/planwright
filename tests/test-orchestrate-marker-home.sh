#!/bin/bash
# Tests for the dispatch-marker home (scripts/orchestrate-marker-home.sh) and
# its writer and readers: a marker dropped from one worktree of a repository
# counts as in flight from every other worktree of it.
#
# Contract under test:
#   - the writer drops each marker in the shared home under the repository's
#     common git dir and in the bundle's checkout-local legacy dir;
#   - the state engine, and through it the meta-tower's fleet in-flight count,
#     sees a marker written from another worktree, in either direction;
#   - markers at the old location are still read: the reader's own legacy dir,
#     and the primary checkout's, where an older writer running there left it;
#   - `clear` removes every copy it can list: the shared home, its own
#     checkout-local dir, and the primary checkout's (a copy in another linked
#     worktree ages out at the staleness threshold);
#   - PLANWRIGHT_ORCH_STATE_DIR stays the only dir when set, and a spec id
#     outside the identifier grammar falls back to the legacy dir alone.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH
unset PLANWRIGHT_ORCH_STATE_DIR PLANWRIGHT_REPO_ROOT GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR

here=$(cd "$(dirname "$0")" && pwd)
S="$here/../scripts"
HOME_HELPER="$S/orchestrate-marker-home.sh"
MARKER="$S/orchestrate-marker.sh"
STATE="$S/orchestrate-state.sh"
META="$S/orchestrate-meta-select.sh"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$HOME_HELPER" ] || fail "scripts/orchestrate-marker-home.sh missing or not executable"

gitc() {
  repo="$1"
  shift
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

state_of() {
  printf '%s\n' "$1" | awk -F"$TAB" -v i="$2" '$1=="task" && $2==i {print $3; exit}'
}

# state_in <checkout> <id>: task <id>'s derived state, read from <checkout>.
state_in() {
  out=$(cd "$1" && "$STATE" specs/demo) || fail "state engine exited non-zero in $1"
  state_of "$out" "$2"
}

tmp=$(mktemp -d)
tmp=$(cd "$tmp" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

# A primary checkout plus one linked worktree (the meta-tower's), each with
# the bundle at specs/demo, and two independent tasks.
make_fixture() {
  primary="$1"
  mkdir -p "$primary/specs/demo"
  git -C "$primary" -c init.defaultBranch=main init -q
  cat >"$primary/.gitignore" <<'EOF'
specs/*/.orchestrate.lock
specs/*/.orchestrate/
.claude/worktrees/
.claude/planwright.local.yml
EOF
  cat >"$primary/specs/demo/tasks.md" <<'EOF'
# Demo — Tasks

**Format-version:** 1

## Forward plan

### Task 1 — dispatched from the primary
- **Dependencies:** none

### Task 2 — dispatched from the worktree
- **Dependencies:** none
EOF
  gitc "$primary" add -A
  gitc "$primary" commit -q -m "base"
  gitc "$primary" worktree add -q "$primary/.claude/worktrees/meta" -b meta-tower
  gitc "$primary" branch planwright/demo/task-1
  gitc "$primary" branch planwright/demo/task-2
}

# ---------------------------------------------------------------------------
# 1. A marker written from the primary checkout counts in the other worktree,
#    in the state engine and in the meta-tower's fleet in-flight count.
# ---------------------------------------------------------------------------
P="$tmp/cross"
make_fixture "$P"
W="$P/.claude/worktrees/meta"
mkdir -p "$P/.claude"
printf 'fleet_max_parallel_units: 1\nmax_parallel_units: 2\n' >"$P/.claude/planwright.local.yml"

[ "$(state_in "$W" 1)" = ready ] || fail "cross: task 1 should start ready"
rc=0
(cd "$W" && "$META" specs/demo >/dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] || fail "cross: with nothing in flight the meta-tower should pick a unit (got $rc)"

(cd "$P" && "$MARKER" write specs/demo 1) || fail "cross: write from the primary failed"
[ "$(state_in "$W" 1)" = in-progress ] \
  || fail "cross: a marker written in the primary is not in flight from the worktree"
rc=0
(cd "$W" && "$META" specs/demo >/dev/null 2>&1) || rc=$?
[ "$rc" = 1 ] \
  || fail "cross: the meta-tower's fleet count missed the primary's marker (bound 1, got exit $rc)"
echo "ok: a marker written in the primary counts in flight from another worktree"

(cd "$W" && "$MARKER" write specs/demo 2) || fail "cross: write from the worktree failed"
[ "$(state_in "$P" 2)" = in-progress ] \
  || fail "cross: a marker written in the worktree is not in flight from the primary"
echo "ok: a marker written in a worktree counts in flight from the primary"

# The writer keeps the checkout-local copy for readers that know only it.
[ -f "$P/specs/demo/.orchestrate/markers/1" ] || fail "cross: no legacy copy in the primary"
[ -f "$W/specs/demo/.orchestrate/markers/2" ] || fail "cross: no legacy copy in the worktree"
[ -z "$(gitc "$P" status --porcelain)" ] || fail "cross: the write dirtied the primary"
[ -z "$(gitc "$W" status --porcelain)" ] || fail "cross: the write dirtied the worktree"
echo "ok: the writer also drops the checkout-local copy, with no tracked change"

# clear from the other side removes every copy.
(cd "$W" && "$MARKER" clear specs/demo 1) || fail "cross: clear failed"
[ "$(state_in "$P" 1)" = ready ] || fail "cross: task 1 still in flight after clear"
[ "$(state_in "$W" 1)" = ready ] || fail "cross: task 1 still in flight from the worktree after clear"
[ ! -e "$P/specs/demo/.orchestrate/markers/1" ] || fail "cross: clear left the primary's legacy copy"
echo "ok: clear from another worktree removes every copy"

# ---------------------------------------------------------------------------
# 2. Old-location markers are still read: the reader's own legacy dir, and the
#    primary checkout's legacy dir read from a linked worktree.
# ---------------------------------------------------------------------------
P="$tmp/legacy"
make_fixture "$P"
W="$P/.claude/worktrees/meta"
mkdir -p "$W/specs/demo/.orchestrate/markers" "$P/specs/demo/.orchestrate/markers"
date +%s >"$W/specs/demo/.orchestrate/markers/1"
date +%s >"$P/specs/demo/.orchestrate/markers/2"
[ "$(state_in "$W" 1)" = in-progress ] || fail "legacy: the worktree's own old-location marker was not read"
[ "$(state_in "$W" 2)" = in-progress ] \
  || fail "legacy: the primary's old-location marker was not read from the worktree"
[ "$(state_in "$P" 2)" = in-progress ] || fail "legacy: the primary's own old-location marker was not read"
echo "ok: markers at the old location are still read, the primary's included"

# A stale old-location marker holds nothing even beside an absent shared one.
echo 100 >"$P/specs/demo/.orchestrate/markers/2"
[ "$(state_in "$W" 2)" = ready ] || fail "legacy: a stale old-location marker still held the task"
echo "ok: a stale old-location marker holds nothing"

# ---------------------------------------------------------------------------
# 3. The home helper: write and read lists, the override, and the fallbacks.
# ---------------------------------------------------------------------------
common=$(cd "$P" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
wlist=$(cd "$W" && "$HOME_HELPER" write specs/demo)
rlist=$(cd "$W" && "$HOME_HELPER" read specs/demo)
[ "$(printf '%s\n' "$wlist" | sed -n 1p)" = "$common/planwright/orchestrate/demo/markers" ] \
  || fail "helper: the shared home is not first in the write list: $wlist"
[ "$(printf '%s\n' "$wlist" | wc -l | tr -d ' ')" = 2 ] || fail "helper: write list is not shared + legacy: $wlist"
printf '%s\n' "$rlist" | grep -Fxq "$P/specs/demo/.orchestrate/markers" \
  || fail "helper: the read list from a worktree misses the primary's legacy dir: $rlist"
[ "$(printf '%s\n' "$rlist" | wc -l | tr -d ' ')" = 3 ] || fail "helper: read list from a worktree is not 3 dirs: $rlist"
plist=$(cd "$P" && "$HOME_HELPER" read specs/demo)
[ "$(printf '%s\n' "$plist" | wc -l | tr -d ' ')" = 2 ] \
  || fail "helper: the primary's read list should not repeat its own legacy dir: $plist"
olist=$(cd "$W" && PLANWRIGHT_ORCH_STATE_DIR="$tmp/alt" "$HOME_HELPER" read specs/demo)
[ "$olist" = "$tmp/alt" ] || fail "helper: the override is not the only dir: $olist"
echo "ok: the helper lists the shared home first, adds the primary's legacy dir on read, honors the override"

# A bundle whose basename is outside the identifier grammar has no shared home.
mkdir -p "$P/specs/Bad_Id"
blist=$(cd "$P" && "$HOME_HELPER" write specs/Bad_Id)
[ "$blist" = "$P/specs/Bad_Id/.orchestrate/markers" ] || fail "helper: a bad spec id kept a shared home: $blist"
# A bundle in no repository keeps the legacy dir alone.
mkdir -p "$tmp/norepo/demo"
nlist=$(cd "$tmp/norepo" && "$HOME_HELPER" write demo)
[ "$nlist" = "$tmp/norepo/demo/.orchestrate/markers" ] || fail "helper: a bundle in no repository: $nlist"
# The flight segment and an over-long id are outside the grammar too.
mkdir -p "$P/specs/flight" "$P/specs/$(printf 'a%.0s' $(seq 1 65))"
[ "$(cd "$P" && "$HOME_HELPER" write specs/flight | wc -l | tr -d ' ')" = 1 ] \
  || fail "helper: the reserved id 'flight' kept a shared home"
[ "$(cd "$P" && "$HOME_HELPER" write "specs/$(printf 'a%.0s' $(seq 1 65))" | wc -l | tr -d ' ')" = 1 ] \
  || fail "helper: a 65-character id kept a shared home"
# The shared home does not depend on the caller's working directory.
here_list=$(cd "$W" && "$HOME_HELPER" write specs/demo | sed -n 1p)
away_list=$(cd "$tmp" && "$HOME_HELPER" write "$W/specs/demo" | sed -n 1p)
[ "$here_list" = "$away_list" ] || fail "helper: the shared home moved with the cwd: $here_list vs $away_list"
# A symlinked bundle keys by the name it is addressed by, as its branches do.
ln -s "$P/specs/demo" "$P/specs/alias"
[ "$(cd "$P" && "$HOME_HELPER" write specs/alias | sed -n 1p)" = "$common/planwright/orchestrate/alias/markers" ] \
  || fail "helper: a symlinked bundle keyed by its target's name"
# A bundle dir named `-` is that dir, never OLDPWD.
mkdir -p "$P/specs/-"
dlist=$(cd "$P/specs" && OLDPWD=/ "$HOME_HELPER" write -)
[ "$(printf '%s\n' "$dlist" | tail -n 1)" = "$P/specs/-/.orchestrate/markers" ] \
  || fail "helper: a dir named '-' resolved elsewhere: $dlist"
# An override carrying a newline cannot be one line of the list.
rc=0
(cd "$P" && PLANWRIGHT_ORCH_STATE_DIR="$tmp/a
b" "$HOME_HELPER" read specs/demo >/dev/null 2>&1) || rc=$?
[ "$rc" = 2 ] || fail "helper: an override with a newline returned $rc, expected 2"
# `.`, a trailing `/.`, and repeated slashes still name the bundle.
for form in . demo/. demo//; do
  case "$form" in .) at="$P/specs/demo" ;; *) at="$P/specs" ;; esac
  [ "$(cd "$at" && "$HOME_HELPER" write "$form" | sed -n 1p)" = "$common/planwright/orchestrate/demo/markers" ] \
    || fail "helper: the operand '$form' lost the shared home"
done
echo "ok: the helper keys by the addressed name, ignores the cwd, and refuses an unlistable override"

# A bare repository's linked worktrees share one home too.
B="$tmp/bare"
mkdir -p "$B/seed/specs/demo"
git -C "$B/seed" -c init.defaultBranch=main init -q
printf '# t\n' >"$B/seed/specs/demo/tasks.md"
gitc "$B/seed" add -A
gitc "$B/seed" commit -q -m base
git clone -q --bare "$B/seed" "$B/repo.git"
gitc "$B/repo.git" worktree add -q "$B/w1" main
gitc "$B/repo.git" worktree add -q -b other "$B/w2" main
b1=$("$HOME_HELPER" write "$B/w1/specs/demo" | sed -n 1p)
b2=$("$HOME_HELPER" write "$B/w2/specs/demo" | sed -n 1p)
bare_common=$(cd "$B/repo.git" && pwd -P)
[ "$b1" = "$bare_common/planwright/orchestrate/demo/markers" ] && [ "$b1" = "$b2" ] \
  || fail "helper: a bare repository's worktrees do not share a home: $b1 vs $b2"
[ "$("$HOME_HELPER" read "$B/w1/specs/demo" | wc -l | tr -d ' ')" = 2 ] \
  || fail "helper: a bare repository has no primary checkout to read"
echo "ok: the linked worktrees of a bare repository share one home"

# A bundle that is itself the repository root still reads the primary's copy.
R="$tmp/rootbundle"
mkdir -p "$R/demo"
git -C "$R/demo" -c init.defaultBranch=main init -q
printf '# t\n' >"$R/demo/tasks.md"
gitc "$R/demo" add -A
gitc "$R/demo" commit -q -m base
gitc "$R/demo" worktree add -q -b side "$R/side"
root_primary=$(cd "$R/demo" && pwd -P)
"$HOME_HELPER" read "$R/side" | grep -Fxq "$root_primary/.orchestrate/markers" \
  || fail "helper: a bundle at the repository root lost the primary checkout's copy"
echo "ok: a bundle at the repository root reads the primary checkout's copy"

# A primary checkout made with --separate-git-dir is unknown to git from a
# linked worktree; the read list names no stand-in for it.
G="$tmp/sepgit"
mkdir -p "$G/main/specs/demo"
git -C "$G/main" -c init.defaultBranch=main init -q --separate-git-dir "$G/gitdir"
printf '# t\n' >"$G/main/specs/demo/tasks.md"
gitc "$G/main" add -A
gitc "$G/main" commit -q -m base
gitc "$G/main" worktree add -q -b side "$G/side"
sep_gitdir=$(cd "$G/gitdir" && pwd -P)
"$HOME_HELPER" read "$G/side/specs/demo" | grep -Fq "$sep_gitdir/specs/" \
  && fail "helper: the git dir was taken for a separate-git-dir primary checkout"
[ "$("$HOME_HELPER" read "$G/side/specs/demo" | sed -n 1p)" = "$sep_gitdir/planwright/orchestrate/demo/markers" ] \
  || fail "helper: a separate-git-dir repository lost its shared home"
# A primary whose .git is a symlink to a git dir elsewhere is the same case.
Y="$tmp/symgit"
mkdir -p "$Y/main/specs/demo"
git -C "$Y/main" -c init.defaultBranch=main init -q
printf '# t\n' >"$Y/main/specs/demo/tasks.md"
gitc "$Y/main" add -A
gitc "$Y/main" commit -q -m base
mv "$Y/main/.git" "$Y/store.git"
ln -s "$Y/store.git" "$Y/main/.git"
gitc "$Y/main" worktree add -q -b side "$Y/side"
store_real=$(cd "$Y/store.git" && pwd -P)
ylist=$("$HOME_HELPER" read "$Y/side/specs/demo")
printf '%s\n' "$ylist" | grep -Fq "$store_real/specs/" \
  && fail "helper: the git dir was taken for a primary whose .git is a symlink"
[ "$(printf '%s\n' "$ylist" | sed -n 1p)" = "$store_real/planwright/orchestrate/demo/markers" ] \
  || fail "helper: a repository whose .git is a symlink lost its shared home: $ylist"
echo "ok: a separate-git-dir repository shares its home, with no stand-in for its primary"

# A repository path carrying a newline cannot be split safely: no shared home.
N="$tmp/nl"
mkdir -p "$N/a" "$N/a
b/specs/demo"
git -C "$N/a
b" -c init.defaultBranch=main init -q
printf '# t\n' >"$N/a
b/specs/demo/tasks.md"
gitc "$N/a
b" add -A
gitc "$N/a
b" commit -q -m base
gitc "$N/a
b" worktree add -q -b side "$N/wt"
nl_list=$("$HOME_HELPER" write "$N/wt/specs/demo")
case "$nl_list" in
  *"$N/a/planwright"*) fail "helper: a newline in the common dir sent the shared home outside the repository" ;;
esac
[ "$nl_list" = "$N/wt/specs/demo/.orchestrate/markers" ] \
  || fail "helper: a newline in the common dir: $nl_list"
echo "ok: a common dir carrying a newline drops the shared home, never splits it"

# ---------------------------------------------------------------------------
# 4. The writer: a shared home it cannot use never costs the marker, nothing is
#    written or cleared through a symlinked dir, and a refusal leaves no strays.
# ---------------------------------------------------------------------------
P="$tmp/writer"
make_fixture "$P"
W="$P/.claude/worktrees/meta"
gcommon=$(cd "$P" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
shared="$gcommon/planwright/orchestrate/demo/markers"

# A file where the shared home's parent belongs: the write keeps its local copy.
: >"$gcommon/planwright"
werr=$( (cd "$P" && "$MARKER" write specs/demo 1) 2>&1) \
  || fail "writer: an unusable shared home failed the write: $werr"
[ -f "$P/specs/demo/.orchestrate/markers/1" ] || fail "writer: no local marker beside an unusable shared home"
case "$werr" in *"skipping the shared marker dir"*"is not a directory"*) ;; *) fail "writer: the skipped shared home was not reported with its reason: $werr" ;; esac
rm -f "$gcommon/planwright" "$P/specs/demo/.orchestrate/markers/1"
# An existing shared home the writer cannot write to is skipped the same way.
if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$shared"
  chmod 555 "$shared"
  werr=$( (cd "$P" && "$MARKER" write specs/demo 1) 2>&1) || {
    chmod 755 "$shared"
    fail "writer: an unwritable shared home failed the write: $werr"
  }
  chmod 755 "$shared"
  [ -f "$P/specs/demo/.orchestrate/markers/1" ] || fail "writer: no local marker beside an unwritable shared home"
  case "$werr" in *"not writable"*) ;; *) fail "writer: the unwritable shared home was not reported: $werr" ;; esac
  rm -rf "$P/specs/demo/.orchestrate/markers/1" "$gcommon/planwright"
fi
echo "ok: a shared home the writer cannot create or write is skipped with a warning, the local marker kept"

# A symlink planted at the shared home's parent is never followed.
elsewhere="$tmp/elsewhere"
mkdir -p "$elsewhere"
ln -s "$elsewhere" "$gcommon/planwright"
(cd "$P" && "$MARKER" write specs/demo 1 2>/dev/null) || fail "writer: a symlinked shared home failed the write"
[ -z "$(find "$elsewhere" -mindepth 1 | head -n 1)" ] || fail "writer: the write followed a symlinked shared home"
[ -f "$P/specs/demo/.orchestrate/markers/1" ] || fail "writer: no local marker beside a symlinked shared home"
date +%s >"$elsewhere/2"
mkdir -p "$elsewhere/orchestrate/demo/markers"
date +%s >"$elsewhere/orchestrate/demo/markers/2"
[ "$(state_in "$P" 2)" = ready ] || fail "reader: a marker reached through a symlinked shared home was counted"
rm -f "$gcommon/planwright" "$P/specs/demo/.orchestrate/markers/1"
echo "ok: a symlinked shared home is neither written nor read through"

# A symlink at a marker path in the shared home drops that home, not the marker.
mkdir -p "$shared"
ln -s "$tmp/fresh-target" "$shared/4"
werr=$( (cd "$P" && "$MARKER" write specs/demo 4) 2>&1) \
  || fail "writer: a symlink at a shared marker path failed the write: $werr"
[ -f "$P/specs/demo/.orchestrate/markers/4" ] || fail "writer: no local marker beside a symlinked shared marker path"
[ -L "$shared/4" ] || fail "writer: the symlink at the shared marker path was written through or replaced"
case "$werr" in *"skipping the shared marker dir"*"symlink sits at the marker path"*) ;; *) fail "writer: the skip was not reported: $werr" ;; esac
rm -f "$shared/4" "$P/specs/demo/.orchestrate/markers/4"
echo "ok: a symlink at a shared marker path skips the shared home, the local marker kept"

# A refusal at the local marker path rolls back the copy staged in the shared home.
mkdir -p "$P/specs/demo/.orchestrate/markers"
ln -s "$tmp/target" "$P/specs/demo/.orchestrate/markers/1"
rc=0
(cd "$P" && "$MARKER" write specs/demo 1 2>/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "writer: a symlink at the local marker path returned $rc, expected 2"
[ -z "$(ls -A "$shared" 2>/dev/null)" ] || fail "writer: the refused write left files in the shared home: $(ls -A "$shared")"
rm -f "$P/specs/demo/.orchestrate/markers/1"
echo "ok: a refused write leaves no marker, temp, or manifest in the shared home"

# A checkout-local .orchestrate that is a symlink keeps the tolerance it always
# had: written, read, and cleared through, beside the shared home.
store="$tmp/store"
mkdir -p "$store"
rm -rf "$P/specs/demo/.orchestrate"
ln -s "$store" "$P/specs/demo/.orchestrate"
(cd "$P" && "$MARKER" write specs/demo 1) || fail "writer: a symlinked checkout-local .orchestrate failed the write"
[ -f "$store/markers/1" ] && [ -f "$shared/1" ] || fail "writer: a symlinked checkout-local .orchestrate lost a copy"
rm -f "$shared/1"
[ "$(state_in "$P" 1)" = in-progress ] || fail "reader: a marker under a symlinked checkout-local .orchestrate was not read"
(cd "$P" && "$MARKER" clear specs/demo 1) || fail "writer: clear failed through a symlinked checkout-local .orchestrate"
[ ! -e "$store/markers/1" ] || fail "writer: clear left the marker under a symlinked checkout-local .orchestrate"
rm -f "$P/specs/demo/.orchestrate"
echo "ok: a symlinked checkout-local .orchestrate is written, read, and cleared as before"

# A clear that fails in one dir still clears the others.
if [ "$(id -u)" -ne 0 ]; then
  (cd "$P" && "$MARKER" write specs/demo 1) || fail "writer: setup write failed"
  chmod 555 "$P/specs/demo/.orchestrate/markers"
  rc=0
  (cd "$P" && "$MARKER" clear specs/demo 1 2>/dev/null) || rc=$?
  chmod 755 "$P/specs/demo/.orchestrate/markers"
  [ "$rc" = 2 ] || fail "writer: a partial clear returned $rc, expected 2"
  [ ! -e "$shared/1" ] || fail "writer: a failed local removal stranded the shared copy"
  echo "ok: a clear failing in one dir still clears the shared home"
fi

# An override path carrying a tab still round-trips through the manifest.
tabdir="$tmp/state${TAB}dir"
(cd "$P" && PLANWRIGHT_ORCH_STATE_DIR="$tabdir" "$MARKER" write specs/demo 3) \
  || fail "writer: an override path carrying a tab failed the write"
[ -f "$tabdir/3" ] || fail "writer: no marker in an override path carrying a tab"
echo "ok: a dir path carrying a tab survives the staging manifest"

rc=0
"$HOME_HELPER" write "$tmp/missing" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "helper: a missing spec dir returned $rc, expected 2"
rc=0
"$HOME_HELPER" frob specs/demo >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "helper: an unknown subcommand returned $rc, expected 2"
echo "ok: the helper falls back to the legacy dir and fails closed on usage"

echo "PASS: test-orchestrate-marker-home.sh"
