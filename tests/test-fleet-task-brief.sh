#!/bin/bash
# Tests for scripts/fleet-task-brief.sh — the task worker's launch-time brief
# (fleet-messaging Task 4.5; D-25 · REQ-C1.6, REQ-H1.6, REQ-D1.9, REQ-F1.7).
#
# Properties verified:
#   1. REQ-H1.6: render fills the shipped template with validated fields only;
#      its output with and without a tower name matches the committed
#      fixtures byte for byte, the named one carrying the name, "fork", and
#      "effective-mode", the unnamed one none of the three.
#   2. REQ-H1.6: a spec identifier, task id, or tower name failing its grammar
#      (the name screen: printable ASCII, no path separator, at most 128
#      bytes) is refused and nothing is written.
#   3. REQ-H1.6: the brief is owner-only under directories only the user can
#      write, and lands by rename: a symlink or hard link planted at the
#      target is replaced, never followed or truncated.
#   4. REQ-H1.6: retire removes a task brief whose unit's worktree is gone and
#      keeps one whose worktree exists, a young one, and another checkout's;
#      fleet-sweep.sh's residue pass carries it, audited.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
unset CLAUDE_PLUGIN_DATA CLAUDE_PLUGIN_ROOT PLANWRIGHT_ROOT PLANWRIGHT_ADOPTER_OVERLAY \
  PLANWRIGHT_LOCAL_CONFIG PLANWRIGHT_CONFIG_DEFAULTS PLANWRIGHT_SKILLS_ROOT \
  PLANWRIGHT_WORKER_HANDLE PLANWRIGHT_WORKER_SCOPE PLANWRIGHT_TOWER_ID CLAUDE_PROJECT_DIR

here=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$here/.." && pwd -P)
SCRIPT="$ROOT/scripts/fleet-task-brief.sh"
FIX="$here/fixtures/task-brief"
TAB=$(printf '\t')

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}

[ -x "$SCRIPT" ] || {
  echo "FAIL: scripts/fleet-task-brief.sh missing or not executable" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P)
umask 022

gitc() {
  _r=$1
  shift
  git -C "$_r" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

repo="$tmp/primary"
git -c init.defaultBranch=main init -q "$repo"
gitc "$repo" commit -q --allow-empty -m init

# fresh_home — a new, empty fleet home for one case.
n=0
fresh_home() {
  n=$((n + 1))
  export PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet$n"
}

mode_of() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

render() {
  OUT=$("$SCRIPT" render "$@" --repo-root "$repo" </dev/null 2>"$tmp/err")
  RC=$?
  ERR=$(cat "$tmp/err")
}

# 1. Output against the fixtures.
fresh_home
render demo 4.5
[ "$RC" -eq 0 ] || fail "render without a name exited $RC: $ERR"
brief="$PLANWRIGHT_FLEET_STATE_DIR/tasks/demo/4.5/brief.md"
[ "$OUT" = "brief${TAB}$brief" ] || fail "render must print the brief's canonical path, got: $OUT"
cmp -s "$brief" "$FIX/unnamed.md" || fail "the unnamed brief differs from its fixture"
for w in tower-alpha fork effective-mode; do
  ! grep -q -e "$w" "$FIX/unnamed.md" || fail "the unnamed fixture carries '$w'"
done
render demo 4.5 --tower tower-alpha
[ "$RC" -eq 0 ] || fail "render with a name exited $RC: $ERR"
cmp -s "$brief" "$FIX/named.md" || fail "the named brief differs from its fixture"
for w in tower-alpha fork effective-mode; do
  grep -q -e "$w" "$FIX/named.md" || fail "the named fixture lacks '$w'"
done
# The `specs/<spec>` alias names the same unit.
render specs/demo 4.5
[ "$RC" -eq 0 ] && [ "$OUT" = "brief${TAB}$brief" ] || fail "the specs/<spec> alias must render the same unit, got $RC: $OUT"

# 3. Owner-only, private directories, landed by rename.
[ "$(mode_of "$brief")" = 600 ] || fail "the brief is mode $(mode_of "$brief"), not owner-only"
for d in "$PLANWRIGHT_FLEET_STATE_DIR/tasks" "$PLANWRIGHT_FLEET_STATE_DIR/tasks/demo" \
  "$PLANWRIGHT_FLEET_STATE_DIR/tasks/demo/4.5"; do
  [ "$(mode_of "$d")" = 700 ] || fail "$d is mode $(mode_of "$d"), not private"
done
printf 'victim\n' >"$tmp/victim"
rm -f "$brief"
ln -s "$tmp/victim" "$brief"
render demo 4.5
[ "$RC" -eq 0 ] || fail "render over a planted symlink exited $RC: $ERR"
if [ -L "$brief" ] || ! cmp -s "$brief" "$FIX/unnamed.md"; then
  fail "a symlink planted at the target must be replaced"
fi
[ "$(cat "$tmp/victim")" = victim ] || fail "render followed a symlink planted at the target"
rm -f "$brief"
ln "$tmp/victim" "$brief"
render demo 4.5
[ "$RC" -eq 0 ] || fail "render over a planted hard link exited $RC: $ERR"
[ "$(cat "$tmp/victim")" = victim ] || fail "render truncated a hard link planted at the target (no rename)"
[ -z "$(find "$PLANWRIGHT_FLEET_STATE_DIR/tasks/demo/4.5" -name '*.tmp*' 2>/dev/null)" ] \
  || fail "render left a temp file beside the brief"

# A failed write is exit 4 with no path printed, so a dispatch never takes a
# stale brief left from an earlier render.
rm -f "$brief"
mkdir "$brief"
render demo 4.5
[ "$RC" -eq 4 ] && [ -z "$OUT" ] || fail "a brief that cannot land must exit 4 printing nothing, got $RC: $OUT"
rmdir "$brief"
fresh_home
mkdir -p "$PLANWRIGHT_FLEET_STATE_DIR/tasks/demo/4.5/checkout"
chmod 700 "$PLANWRIGHT_FLEET_STATE_DIR" "$PLANWRIGHT_FLEET_STATE_DIR/tasks" \
  "$PLANWRIGHT_FLEET_STATE_DIR/tasks/demo" "$PLANWRIGHT_FLEET_STATE_DIR/tasks/demo/4.5"
render demo 4.5
[ "$RC" -eq 4 ] && [ -z "$OUT" ] || fail "a checkout record that cannot land must exit 4 printing nothing, got $RC: $OUT"
[ ! -e "$PLANWRIGHT_FLEET_STATE_DIR/tasks/demo/4.5/brief.md" ] \
  || fail "a brief must not land without its checkout record, which retire keys on"

# A fleet home or a directory others can write is refused, nothing written.
fresh_home
mkdir -p "$PLANWRIGHT_FLEET_STATE_DIR/tasks"
chmod 777 "$PLANWRIGHT_FLEET_STATE_DIR/tasks"
render demo 4.5
[ "$RC" -ne 0 ] || fail "render must refuse a tasks directory others can write"
[ ! -e "$PLANWRIGHT_FLEET_STATE_DIR/tasks/demo" ] || fail "a refused render created the unit's directory"
fresh_home
mkdir -p "$PLANWRIGHT_FLEET_STATE_DIR/tasks"
chmod 700 "$PLANWRIGHT_FLEET_STATE_DIR"
chmod 770 "$PLANWRIGHT_FLEET_STATE_DIR/tasks"
render demo 4.5
[ "$RC" -ne 0 ] || fail "render must refuse a tasks directory its group can write"
[ ! -e "$PLANWRIGHT_FLEET_STATE_DIR/tasks/demo" ] || fail "a refused render created the unit's directory (group-writable)"
fresh_home
mkdir -p "$tmp/elsewhere" "$PLANWRIGHT_FLEET_STATE_DIR/tasks"
chmod 700 "$PLANWRIGHT_FLEET_STATE_DIR" "$PLANWRIGHT_FLEET_STATE_DIR/tasks" "$tmp/elsewhere"
ln -s "$tmp/elsewhere" "$PLANWRIGHT_FLEET_STATE_DIR/tasks/demo"
render demo 4.5
[ "$RC" -ne 0 ] || fail "render must refuse a symlinked spec directory"
[ -z "$(ls -A "$tmp/elsewhere")" ] || fail "render wrote through a symlinked spec directory"

# 2. Grammar refusals write nothing.
long_name=$(printf 'a%.0s' $(seq 1 129))
max_name=$(printf 'a%.0s' $(seq 1 128))
long_spec=$(printf 'a%.0s' $(seq 1 65))
nl_name=$(printf 'tower\nx')
tab_name=$(printf 'tower\tx')
del_name=$(printf 'tower\177x')
for args in "UPPER|4.5" "flight|4.5" "a/b|4.5" "..|4.5" "-x|4.5" "$long_spec|4.5" \
  "demo|4.x" "demo|../1" "demo|" "demo|4.5.6" "demo|-1" "|4.5"; do
  fresh_home
  render "${args%%|*}" "${args#*|}"
  [ "$RC" -eq 2 ] || fail "render must refuse spec/id '$args' (exit 2), got $RC"
  [ ! -e "$PLANWRIGHT_FLEET_STATE_DIR" ] || fail "a refused render ('$args') created the fleet home"
done
for name in "a/b" 'a\b' 'tow`er' "$nl_name" "$tab_name" "$del_name" "$long_name" "-tower" "" "$(printf 'caf\303\251')"; do
  fresh_home
  render demo 4.5 --tower "$name"
  [ "$RC" -eq 2 ] || fail "render must refuse the tower name '$name' (exit 2), got $RC"
  [ ! -e "$PLANWRIGHT_FLEET_STATE_DIR" ] || fail "a refused name ('$name') created the fleet home"
done
fresh_home
render demo 4.5 --tower "$max_name"
[ "$RC" -eq 0 ] || fail "a 128-byte name must be accepted, got $RC: $ERR"
render demo 4.5 --tower 'tower & co @@ID@@ \1'
[ "$RC" -eq 2 ] || fail "a name with a backslash must be refused, got $RC"
render demo 4.5 --tower 'tower & co @@ID@@'
[ "$RC" -eq 0 ] || fail "a printable name must be accepted, got $RC: $ERR"
grep -qF 'tower & co @@ID@@' "$PLANWRIGHT_FLEET_STATE_DIR/tasks/demo/4.5/brief.md" \
  || fail "the name must land as data, unexpanded"
"$SCRIPT" render demo 4.5 --tower </dev/null >/dev/null 2>&1
[ "$?" -eq 2 ] || fail "a --tower with no value must be a usage error"
"$SCRIPT" render demo 4.5 extra </dev/null >/dev/null 2>&1
[ "$?" -eq 2 ] || fail "an extra operand must be a usage error"

# 4. Retire.
fresh_home
wt_root="$repo/.claude/worktrees"
mkdir -p "$wt_root/demo-task-1"
for id in 1 2 3; do
  render demo "$id"
  [ "$RC" -eq 0 ] || fail "retire fixture: render demo $id exited $RC: $ERR"
done
home=$PLANWRIGHT_FLEET_STATE_DIR
touch -t 202001010000 "$home/tasks/demo/1" "$home/tasks/demo/2"
# Another checkout's brief, old and with no worktree.
other="$tmp/other"
git -c init.defaultBranch=main init -q "$other"
gitc "$other" commit -q --allow-empty -m init
OUT=$("$SCRIPT" render demo 9 --repo-root "$other" 2>&1) || fail "retire fixture: other checkout render: $OUT"
touch -t 202001010000 "$home/tasks/demo/9"
OUT=$("$SCRIPT" retire --repo-root "$repo" 2>&1)
RC=$?
[ "$RC" -eq 0 ] || fail "retire exited $RC: $OUT"
[ "$OUT" = "retired${TAB}demo/2" ] || fail "retire must report exactly demo/2, got: $OUT"
[ ! -e "$home/tasks/demo/2" ] || fail "retire must remove a brief whose worktree is gone"
[ -f "$home/tasks/demo/1/brief.md" ] || fail "retire must keep a brief whose worktree exists"
[ -f "$home/tasks/demo/3/brief.md" ] || fail "retire must keep a brief inside its grace"
[ -f "$home/tasks/demo/9/brief.md" ] || fail "retire must keep another checkout's brief"
# No fleet home yet is a clean no-op.
OUT=$(PLANWRIGHT_FLEET_STATE_DIR="$tmp/absent" "$SCRIPT" retire --repo-root "$repo" 2>&1)
RC=$?
[ "$RC" -eq 0 ] && [ -z "$OUT" ] || fail "retire with no fleet home must exit 0 silently, got $RC: $OUT"
[ ! -e "$tmp/absent" ] || fail "retire created a fleet home"

# The fleet sweep's residue pass carries the retire, audited.
rm -rf "$wt_root/demo-task-1"
mkdir -p "$wt_root/demo-task-4"
render demo 4
[ "$RC" -eq 0 ] || fail "sweep fixture: render demo 4 exited $RC: $ERR"
touch -t 202001010000 "$home/tasks/demo/4"
"$ROOT/scripts/fleet-sweep.sh" --repo "$repo" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "the fleet sweep exited $rc"
[ ! -e "$home/tasks/demo/1" ] || fail "the fleet sweep must retire a task brief whose worktree is gone"
[ -f "$home/tasks/demo/3/brief.md" ] || fail "the fleet sweep must keep a young task brief"
[ -f "$home/tasks/demo/4/brief.md" ] || fail "the fleet sweep must keep a task brief whose worktree exists"
"$ROOT/scripts/fleet-audit.sh" query --mechanism housekeeping-sweep 2>/dev/null | grep -q 'task-brief-retire' \
  || fail "the fleet sweep must audit the task-brief retire"

# Retire run from a linked worktree judges the primary's units.
fresh_home
home=$PLANWRIGHT_FLEET_STATE_DIR
gitc "$repo" worktree add -q --detach "$tmp/linked" 2>/dev/null || fail "fixture: linked worktree"
render demo 5
touch -t 202001010000 "$home/tasks/demo/5"
OUT=$("$SCRIPT" retire --repo-root "$tmp/linked" 2>&1)
[ "$OUT" = "retired${TAB}demo/5" ] || fail "retire from a linked worktree must judge the primary's units, got: $OUT"

# A unit another checkout recorded, with its worktree there, is never
# overwritten; once that worktree is gone the render takes it.
OUT=$("$SCRIPT" render demo 9 --repo-root "$other" 2>&1) || fail "fixture: other checkout render: $OUT"
mkdir -p "$other/.claude/worktrees/demo-task-9"
render demo 9
[ "$RC" -eq 4 ] || fail "render must refuse a unit another checkout's live worktree holds (exit 4), got $RC"
[ "$(cat "$home/tasks/demo/9/checkout")" = "$other" ] || fail "a refused render rewrote another checkout's record"
rm -rf "$other/.claude/worktrees/demo-task-9"
render demo 9
[ "$RC" -eq 0 ] && [ "$(cat "$home/tasks/demo/9/checkout")" = "$repo" ] \
  || fail "render must take a unit whose other checkout's worktree is gone, got $RC: $ERR"

# A brief whose checkout no longer exists is retired by any checkout's sweep.
gone="$tmp/gone"
git -c init.defaultBranch=main init -q "$gone"
gitc "$gone" commit -q --allow-empty -m init
OUT=$("$SCRIPT" render demo 7 --repo-root "$gone" 2>&1) || fail "fixture: gone checkout render: $OUT"
rm -rf "$gone"
touch -t 202001010000 "$home/tasks/demo/7" "$home/tasks/demo/9"
OUT=$("$SCRIPT" retire --repo-root "$repo" 2>&1)
case $OUT in
  *"retired${TAB}demo/7"*) ;;
  *) fail "retire must take a brief whose checkout is gone, got: $OUT" ;;
esac

# A retire never runs while a render holds the tasks lock.
render demo 8
touch -t 202001010000 "$home/tasks/demo/8"
OUT=$(
  # shellcheck source=scripts/lock-lib.sh
  . "$ROOT/scripts/lock-lib.sh"
  pw_lock_try "$home/tasks/.brief.lock" || echo "fixture: lock not taken"
  "$SCRIPT" retire --repo-root "$repo" 2>&1
  echo "rc=$?"
  pw_lock_release "$home/tasks/.brief.lock"
)
[ "$OUT" = "rc=0" ] || fail "retire under a held lock must be a silent no-op, got: $OUT"
[ -f "$home/tasks/demo/8/brief.md" ] || fail "retire removed a brief while the lock was held"

# An unreadable spec directory is named and skipped; the rest still retire.
if [ "$(id -u)" -ne 0 ]; then
  OUT=$("$SCRIPT" render other 1 --repo-root "$repo" 2>&1) || fail "fixture: other spec render: $OUT"
  chmod 000 "$home/tasks/other"
  OUT=$("$SCRIPT" retire --repo-root "$repo" 2>&1)
  RC=$?
  chmod 700 "$home/tasks/other"
  [ "$RC" -eq 4 ] || fail "retire past an unreadable entry must exit 4, got $RC"
  case $OUT in
    *"retired${TAB}demo/8"*"could not be listed"* | *"could not be listed"*"retired${TAB}demo/8"*) ;;
    *) fail "retire must name the unreadable entry and still retire the rest, got: $OUT" ;;
  esac
fi

# 5. REQ-C1.6's prose arms: /orchestrate's tmux dispatch step renders the
# brief and passes --brief; docs/fleet.md carries the --brief task row and the
# task brief's path.
tmux_step=$(awk '/^- \*\*tmux\*\* \(opt-in\)/ {on = 1} on && /^- \*\*print\*\*/ {exit} on' \
  "$ROOT/skills/orchestrate/SKILL.md" | tr '\n' ' ')
case $tmux_step in
  *"scripts/fleet-task-brief.sh render"*) ;;
  *) fail "the /orchestrate tmux dispatch step must call the task brief renderer" ;;
esac
case $tmux_step in
  *"--brief"*) ;;
  *) fail "the /orchestrate tmux dispatch step must pass --brief" ;;
esac
# shellcheck disable=SC2016 # literal backticks, matched as written
grep -qF '| `fleet-dispatch-worktree.sh dispatch <spec> <id> --brief <abs-file>` |' "$ROOT/docs/fleet.md" \
  || fail "docs/fleet.md must carry the --brief task row"
# shellcheck disable=SC2016 # literal backticks, matched as written
grep -qF '`<fleet-home>/tasks/<spec>/<id>/brief.md`' "$ROOT/docs/fleet.md" \
  || fail "docs/fleet.md must carry the task brief's path"
# REQ-D1.9's audit: the template is no scripts/*.sh file, and no shipped
# script names the messaging tools.
! grep -l -e SendMessage -e ListAgents "$ROOT"/scripts/*.sh >/dev/null 2>&1 \
  || fail "a scripts/*.sh file names SendMessage or ListAgents"

if [ "$fails" -gt 0 ]; then
  echo "test-fleet-task-brief: $fails failure(s)" >&2
  exit 1
fi
echo "test-fleet-task-brief: all checks passed"
