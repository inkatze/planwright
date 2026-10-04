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
#   - `clear` removes every copy;
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

rc=0
"$HOME_HELPER" write "$tmp/missing" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "helper: a missing spec dir returned $rc, expected 2"
rc=0
"$HOME_HELPER" frob specs/demo >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "helper: an unknown subcommand returned $rc, expected 2"
echo "ok: the helper falls back to the legacy dir and fails closed on usage"

echo "PASS: test-orchestrate-marker-home.sh"
