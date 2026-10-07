#!/bin/bash
# Tests for scripts/fleet-attention-reconcile.sh — the level-triggered clear of
# attention rows a dead or finished earlier tower left behind, and the guarded
# `fleet-attention.sh clear --if-row` it clears through.
#
# Coverage:
#   g1: a guarded clear removes the row only while it is exactly the judged
#       one; a changed or missing row is refused with exit 3.
#   c1: a row whose spec unit derives completed is cleared, in both scope
#       spellings (`<spec>:task-<id>` and `<spec>:<id>`), with no registry
#       record behind it (a dead earlier tower's window-id handle).
#   c2: a bundle-range scope clears only when every task in the range derives
#       completed.
#   d1: a working row whose registry death handle is a gone tmux window is
#       cleared; a listed window keeps it.
#   d2: a working row whose death handle is an exited process is cleared.
#   u1: an unreachable tmux server (lost observability) keeps the row.
#   u2: a row with no registry record and an unfinished unit is kept.
#   a1: an awaiting-input row is kept whatever its unit or worker evidence.
#   p1: a pr-ready row with a dead worker and an unfinished unit is kept.
#   x1: a completed unit whose worker record lives in another checkout is not
#       cleared on this checkout's derivation.
#   i1: every clear is audited, and a second pass clears nothing.
#   k1: the kill-switch pauses the pass before it clears anything.
#
# Hermetic: every case pins its own fleet home and fake tmux. Runs standalone
# under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-attention-reconcile.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
unset PLANWRIGHT_BASE_REF PLANWRIGHT_ORCH_STATE_DIR PLANWRIGHT_LOCAL_CONFIG

here=$(cd "$(dirname "$0")" && pwd)
S="$here/../scripts"
REC="$S/fleet-attention-reconcile.sh"
FA="$S/fleet-attention.sh"
FS="$S/fleet-state.sh"
TAB=$(printf '\t')

rc=0
fail() {
  echo "not ok: $1"
  echo "FAIL: $1" >&2
  rc=$((rc + 1))
}

[ -x "$REC" ] || {
  echo "FAIL: scripts/fleet-attention-reconcile.sh missing or not executable" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

gitc() {
  g_repo=$1
  shift
  git -C "$g_repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# The checkout: spec `demo` with tasks 1, 3, 5 and 6 completed by trailer on
# main, tasks 2 and 4 unfinished.
repo="$tmp/repo"
mkdir -p "$repo/specs/demo"
gitc "$repo" init -q
cat >"$repo/specs/demo/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1 — done
- **Dependencies:** none
### Task 2 — open
- **Dependencies:** none
### Task 3 — done
- **Dependencies:** none
### Task 4 — open
- **Dependencies:** none
### Task 5 — done
- **Dependencies:** none
### Task 6 — done
- **Dependencies:** none
EOF
gitc "$repo" add -A
gitc "$repo" commit -q -m "base" -m "Planwright-Task: demo/1"
gitc "$repo" commit -q --allow-empty -m "three" -m "Planwright-Task: demo/3"
gitc "$repo" commit -q --allow-empty -m "five" -m "Planwright-Task: demo/5"
gitc "$repo" commit -q --allow-empty -m "six" -m "Planwright-Task: demo/6"
repo=$(cd "$repo" && pwd -P)
other="$tmp/elsewhere"
mkdir -p "$other"

# A fake tmux: `ls` health from a mode file, sessions and their windows from a
# listing file (`<session> <window-id>` per line).
fakebin="$tmp/bin"
mkdir -p "$fakebin"
cat >"$fakebin/tmux" <<EOF
#!/bin/sh
mode=\$(cat "$tmp/tmux-mode" 2>/dev/null)
[ "\$mode" = down ] && exit 1
case \$1 in
  ls) exit 0 ;;
  has-session) awk -v s="\${3#=}" '\$1 == s { f = 1 } END { exit !f }' "$tmp/tmux-windows" ;;
  list-windows) awk -v s="\${3#=}" '\$1 == s { printf "%s\tname\n", \$2 }' "$tmp/tmux-windows" ;;
esac
EOF
chmod +x "$fakebin/tmux"
: >"$tmp/tmux-windows"
printf 'up\n' >"$tmp/tmux-mode"

# A pid that is gone.
sleep 0 &
dead_pid=$!
wait "$dead_pid" 2>/dev/null

n=0
# fresh — a new fleet home for one case, exported for the helpers below.
fresh() {
  n=$((n + 1))
  home="$tmp/home$n"
  mkdir -p "$home"
}
fenv() {
  PATH="$fakebin:$PATH" PLANWRIGHT_FLEET_STATE_DIR="$home" "$@"
}
reconcile() {
  (cd "$repo" && fenv /bin/sh "$REC" --repo "$repo" 2>"$tmp/err")
}
row_of() {
  awk -F "$TAB" -v w="$1" '$1 == w { print $3; exit }' "$home/attention/state" 2>/dev/null
}
has_row() {
  [ -n "$(row_of "$1")" ]
}

# --- g1: the guarded clear -------------------------------------------------
fresh
fenv /bin/sh "$FA" heartbeat w1 demo:task-2 working
stamp=$(awk -F "$TAB" '$1 == "w1" { print $4 }' "$home/attention/state")
g_rc=0
fenv /bin/sh "$FA" clear w1 --if-row working "$((stamp + 1))" || g_rc=$?
[ "$g_rc" = 3 ] || fail "g1: a stale stamp exited $g_rc, expected 3"
has_row w1 || fail "g1: a stale stamp removed the row"
g_rc=0
fenv /bin/sh "$FA" clear w1 --if-row idle "$stamp" || g_rc=$?
[ "$g_rc" = 3 ] || fail "g1: a changed state exited $g_rc, expected 3"
g_rc=0
fenv /bin/sh "$FA" clear w1 --if-row working "$stamp" || g_rc=$?
[ "$g_rc" = 0 ] || fail "g1: the judged row exited $g_rc, expected 0"
has_row w1 && fail "g1: the judged row survived"
g_rc=0
fenv /bin/sh "$FA" clear w1 --if-row working "$stamp" || g_rc=$?
[ "$g_rc" = 3 ] || fail "g1: a missing row exited $g_rc, expected 3"
g_rc=0
fenv /bin/sh "$FA" clear w1 --if-row bogus 1 2>/dev/null || g_rc=$?
[ "$g_rc" = 2 ] || fail "g1: a malformed state exited $g_rc, expected 2"
echo "ok: g1 guarded clear"

# --- c1, c2, u2, a1: unit derivation ---------------------------------------
fresh
fenv /bin/sh "$FA" heartbeat @145 demo:task-1 working
fenv /bin/sh "$FA" heartbeat @159 demo:3 idle
fenv /bin/sh "$FA" heartbeat @160 demo:task-5-6 merged
fenv /bin/sh "$FA" heartbeat @162 demo:task-1-3 merged
fenv /bin/sh "$FA" heartbeat @161 demo:task-3-4 working
fenv /bin/sh "$FA" heartbeat @166 demo:task-2 working
fenv /bin/sh "$FA" decide @170 demo:task-1 "merge or hold?" merge "merge|hold"
out=$(reconcile) || fail "c1: reconcile exited non-zero: $(cat "$tmp/err")"
has_row @145 && fail "c1: a completed task-<id> scope was kept"
has_row @159 && fail "c1: a completed bare-id scope was kept"
has_row @160 && fail "c2: a fully completed range was kept"
has_row @161 || fail "c2: a range with an unfinished end was cleared"
has_row @162 || fail "c2: a range with an unfinished interior task was cleared"
has_row @166 || fail "u2: an unfinished unit with no record was cleared"
[ "$(row_of @170)" = awaiting-input ] || fail "a1: a queued decision was cleared"
printf '%s\n' "$out" | grep -q "^clear${TAB}@145${TAB}unit-completed$" \
  || fail "c1: no clear line for @145: $out"
printf '%s\n' "$out" | grep -q "^keep${TAB}@170${TAB}awaiting-input$" \
  || fail "a1: no keep line for @170: $out"
echo "ok: c1 c2 u2 a1 unit derivation"

# --- d1, d2, u1, p1, x1: worker evidence -----------------------------------
fresh
printf 'sess-a @1\n' >"$tmp/tmux-windows"
reg() {
  fenv /bin/sh "$FS" register "$1" "$2" --backend "$3" --state-dir "$4" --death-handle "$5" >/dev/null \
    || fail "setup: register $1"
}
reg tmux-demo-task-2 demo:task-2 tmux "$repo/.claude/worktrees/demo-2" "tmux-window sess-a @9"
reg tmux-demo-task-4 demo:task-4 tmux "$repo/.claude/worktrees/demo-4" "tmux-window sess-a @1"
reg proc-demo-task-2b demo:task-2 headless "$repo/specs/demo/.orchestrate/headless/2" "process $dead_pid"
reg pr-demo-task-4 demo:task-4 tmux "$repo/.claude/worktrees/demo-4b" "tmux-window sess-gone @3"
reg far-demo-task-1 demo:task-1 tmux "$other/wt" "tmux-window sess-a @1"
fenv /bin/sh "$FA" heartbeat tmux-demo-task-2 demo:task-2 working
fenv /bin/sh "$FA" heartbeat tmux-demo-task-4 demo:task-4 working
fenv /bin/sh "$FA" heartbeat proc-demo-task-2b demo:task-2 hung
fenv /bin/sh "$FA" heartbeat pr-demo-task-4 demo:task-4 pr-ready
fenv /bin/sh "$FA" heartbeat far-demo-task-1 demo:task-1 pr-ready
out=$(reconcile) || fail "d1: reconcile exited non-zero: $(cat "$tmp/err")"
has_row tmux-demo-task-2 && fail "d1: a gone tmux window kept its row"
has_row tmux-demo-task-4 || fail "d1: a listed tmux window lost its row"
has_row proc-demo-task-2b && fail "d2: an exited process kept its row"
has_row pr-demo-task-4 || fail "p1: a pr-ready row with an unfinished unit was cleared"
has_row far-demo-task-1 || fail "x1: another checkout's worker was cleared on this derivation"
printf '%s\n' "$out" | grep -q "^clear${TAB}tmux-demo-task-2${TAB}tmux-window-dead$" \
  || fail "d1: no clear line naming the evidence: $out"
printf '%s\n' "$out" | grep -q "^clear${TAB}proc-demo-task-2b${TAB}process-dead$" \
  || fail "d2: no clear line naming the evidence: $out"
echo "ok: d1 d2 p1 x1 worker evidence"

fresh
reg tmux-demo-task-2 demo:task-2 tmux "$repo/.claude/worktrees/demo-2" "tmux-window sess-a @9"
fenv /bin/sh "$FA" heartbeat tmux-demo-task-2 demo:task-2 working
printf 'down\n' >"$tmp/tmux-mode"
out=$(reconcile) || fail "u1: reconcile exited non-zero: $(cat "$tmp/err")"
printf 'up\n' >"$tmp/tmux-mode"
has_row tmux-demo-task-2 || fail "u1: an unreachable tmux server cleared the row"
printf '%s\n' "$out" | grep -q "^keep${TAB}tmux-demo-task-2${TAB}evidence-unknown$" \
  || fail "u1: no evidence-unknown keep line: $out"
echo "ok: u1 unknown evidence keeps the row"

# --- i1: audit and idempotence ---------------------------------------------
fresh
fenv /bin/sh "$FA" heartbeat @145 demo:task-1 working
reconcile >/dev/null || fail "i1: first pass exited non-zero"
fenv /bin/sh "$S/fleet-audit.sh" query --mechanism attention-reconcile 2>/dev/null | grep -q '@145' \
  || fail "i1: the clear was not audited"
out=$(reconcile) || fail "i1: second pass exited non-zero"
printf '%s\n' "$out" | grep -q "^clear" && fail "i1: a second pass cleared again: $out"
printf '%s\n' "$out" | grep -q "^summary${TAB}rows=0${TAB}cleared=0${TAB}kept=0${TAB}status=ok$" \
  || fail "i1: unexpected summary: $out"
echo "ok: i1 audited and idempotent"

# --- k1: kill-switch -------------------------------------------------------
fresh
fenv /bin/sh "$FA" heartbeat @145 demo:task-1 working
printf 'fleet_daemon_pause: true\n' >"$tmp/pause.yml"
k_rc=0
(cd "$repo" && fenv env PLANWRIGHT_LOCAL_CONFIG="$tmp/pause.yml" /bin/sh "$REC" --repo "$repo" >/dev/null 2>&1) || k_rc=$?
[ "$k_rc" = 4 ] || fail "k1: a paused pass exited $k_rc, expected 4"
has_row @145 || fail "k1: a paused pass cleared a row"
echo "ok: k1 kill-switch pauses the pass"

[ "$rc" = 0 ] || {
  echo "FAIL: $rc case(s) failed" >&2
  exit 1
}
echo "PASS: fleet-attention-reconcile"
