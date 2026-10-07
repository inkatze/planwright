#!/bin/bash
# Tests for scripts/fleet-attention-reconcile.sh — the level-triggered clear of
# attention rows a dead or finished earlier tower left behind, and the guarded
# `fleet-attention.sh clear --if-row` it clears through.
#
# Coverage:
#   g1: a guarded clear removes the row only while it carries the judged
#       scope, state and stamp; a changed or missing row is refused with
#       exit 3.
#   c1: a row whose spec unit derives completed is cleared, in both scope
#       spellings (`<spec>:task-<id>` and `<spec>:<id>`), with no registry
#       record behind it (a dead earlier tower's window-id handle).
#   c2: a bundle-range scope clears only when every task in the range derives
#       completed.
#   d1: a working row whose registry death handle is a gone tmux window is
#       cleared; a listed window keeps it.
#   d2: a working row whose death handle is an exited process is cleared.
#   u1: an unreachable tmux server (lost observability) keeps the row.
#   e1: unknown death evidence keeps the row even when its unit derived
#       completed; e2: so does a live worker; e3: an unreadable registry keeps
#       every row it might hold evidence for, and degrades the pass.
#   m1: a row whose state no writer produces, or whose scope is longer than
#       the store's field grammar allows, is kept as malformed; m2: a
#       handle with two rows is kept and degrades the pass; m3: a clear that
#       fails keeps the row under its own reason and degrades the pass.
#   w1: the unit rule derives from --repo even when the caller sits elsewhere
#       and PLANWRIGHT_REPO_ROOT names another directory, and a --repo that
#       is no repository is refused.
#   r1: a row its worker rewrote between the verdict and the clear survives.
#   u2: a row with no registry record and an unfinished unit is kept.
#   a1: an awaiting-input row is kept whatever its unit or worker evidence.
#   p1: a pr-ready row with a dead worker and an unfinished unit is kept.
#   x1: a completed unit whose worker record lives in another checkout, or
#       climbs out of this one through `..`, is not cleared on this
#       checkout's derivation.
#   i1: every clear is audited, and a second pass clears nothing.
#   k1: the kill-switch pauses the pass before it clears anything; k2: one
#       set mid-pass stops every clear after it.
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
  has-session)
    [ -f "$tmp/race" ] && /bin/sh "$tmp/race"
    awk -v s="\${3#=}" '\$1 == s { f = 1 } END { exit !f }' "$tmp/tmux-windows" ;;
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
# fresh — a new fleet home for one case.
fresh() {
  n=$((n + 1))
  home="$tmp/home$n"
  mkdir -p "$home/attention"
  : >"$home/attention/state"
  rm -f "$tmp/race"
}
fenv() {
  PATH="$fakebin:$PATH" PLANWRIGHT_FLEET_STATE_DIR="$home" "$@"
}
# Rows are seeded in the store's own layouts rather than through the writers,
# which cost a lock round trip each; g1 exercises the real writer.
# seed <worker> <scope> <state> [<stamp>]
seed() {
  printf '%s\t%s\t%s\t%s\t\t\t\t\n' "$1" "$2" "$3" "${4:-1700000000}" >>"$home/attention/state"
}
# seed_decision <worker> <scope>
seed_decision() {
  printf '%s\t%s\tawaiting-input\t1700000000\tnormal\tmerge or hold?\tmerge\tmerge|hold\n' \
    "$1" "$2" >>"$home/attention/state"
}
# reg <worker> <scope> <backend> <state-dir> <death-handle>
reg() {
  printf '1700000000\t%s\t%s\t-\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >>"$home/registry"
}
# reconcile <case> — one pass; its output in $out, its stderr in $tmp/err.
reconcile() {
  out=$(cd "$repo" && fenv /bin/sh "$REC" --repo "$repo" 2>"$tmp/err") \
    || fail "$1: reconcile exited non-zero: $(cat "$tmp/err")"
}
# clean <case> — the pass ran undegraded and warned nothing.
clean() {
  printf '%s\n' "$out" | grep -q "^summary${TAB}.*${TAB}status=ok$" \
    || fail "$1: the pass was degraded: $out"
  [ ! -s "$tmp/err" ] || fail "$1: the pass warned: $(cat "$tmp/err")"
}
# says <case> <verb> <worker> <reason> — the pass printed that line.
says() {
  printf '%s\n' "$out" | grep -q "^$2${TAB}$3${TAB}$4$" || fail "$1: no '$2 $3 $4' line: $out"
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
fenv /bin/sh "$FA" clear w1 --if-row demo:task-2 working "$((stamp + 1))" || g_rc=$?
[ "$g_rc" = 3 ] || fail "g1: a stale stamp exited $g_rc, expected 3"
has_row w1 || fail "g1: a stale stamp removed the row"
g_rc=0
fenv /bin/sh "$FA" clear w1 --if-row demo:task-2 idle "$stamp" || g_rc=$?
[ "$g_rc" = 3 ] || fail "g1: a changed state exited $g_rc, expected 3"
g_rc=0
fenv /bin/sh "$FA" clear w1 --if-row demo:task-4 working "$stamp" || g_rc=$?
[ "$g_rc" = 3 ] || fail "g1: a changed scope exited $g_rc, expected 3"
g_rc=0
fenv /bin/sh "$FA" clear w1 --if-row demo:task-2 working "$stamp" || g_rc=$?
[ "$g_rc" = 0 ] || fail "g1: the judged row exited $g_rc, expected 0"
has_row w1 && fail "g1: the judged row survived"
g_rc=0
fenv /bin/sh "$FA" clear w1 --if-row demo:task-2 working "$stamp" || g_rc=$?
[ "$g_rc" = 3 ] || fail "g1: a missing row exited $g_rc, expected 3"
g_rc=0
fenv /bin/sh "$FA" clear w1 --if-row demo:task-2 bogus 1 2>/dev/null || g_rc=$?
[ "$g_rc" = 2 ] || fail "g1: a malformed state exited $g_rc, expected 2"
echo "ok: g1 guarded clear"

# --- c1, c2, u2, a1: unit derivation ---------------------------------------
fresh
seed @145 demo:task-1 working
seed @159 demo:3 idle
seed @160 demo:task-5-6 merged
seed @162 demo:task-1-3 merged
seed @161 demo:task-3-4 working
seed @166 demo:task-2 working
seed_decision @170 demo:task-1
reconcile c1
clean c1
has_row @145 && fail "c1: a completed task-<id> scope was kept"
has_row @159 && fail "c1: a completed bare-id scope was kept"
has_row @160 && fail "c2: a fully completed range was kept"
has_row @161 || fail "c2: a range with an unfinished end was cleared"
has_row @162 || fail "c2: a range with an unfinished interior task was cleared"
has_row @166 || fail "u2: an unfinished unit with no record was cleared"
[ "$(row_of @170)" = awaiting-input ] || fail "a1: a queued decision was cleared"
says c1 clear @145 unit-completed
says a1 keep @170 awaiting-input
echo "ok: c1 c2 u2 a1 unit derivation"

# --- d1, d2, p1, x1: worker evidence ---------------------------------------
fresh
printf 'sess-a @1\n' >"$tmp/tmux-windows"
reg tmux-demo-task-2 demo:task-2 tmux "$repo/.claude/worktrees/demo-2" "tmux-window sess-a @9"
reg tmux-demo-task-4 demo:task-4 tmux "$repo/.claude/worktrees/demo-4" "tmux-window sess-a @1"
reg proc-demo-task-2b demo:task-2 headless "$repo/specs/demo/.orchestrate/headless/2" "process $dead_pid"
reg pr-demo-task-4 demo:task-4 tmux "$repo/.claude/worktrees/demo-4b" "tmux-window sess-gone @3"
reg far-demo-task-1 demo:task-1 tmux "$other/wt" "tmux-window sess-a @1"
seed tmux-demo-task-2 demo:task-2 working
seed tmux-demo-task-4 demo:task-4 working
seed proc-demo-task-2b demo:task-2 hung
seed pr-demo-task-4 demo:task-4 pr-ready
seed far-demo-task-1 demo:task-1 pr-ready
reg dot-demo-task-1 demo:task-1 tmux "$repo/../elsewhere/wt" "tmux-window sess-a @1"
seed dot-demo-task-1 demo:task-1 pr-ready
reconcile d1
clean d1
has_row tmux-demo-task-2 && fail "d1: a gone tmux window kept its row"
has_row tmux-demo-task-4 || fail "d1: a listed tmux window lost its row"
has_row proc-demo-task-2b && fail "d2: an exited process kept its row"
has_row pr-demo-task-4 || fail "p1: a pr-ready row with an unfinished unit was cleared"
has_row far-demo-task-1 || fail "x1: another checkout's worker was cleared on this derivation"
has_row dot-demo-task-1 || fail "x1: a state dir climbing out of this checkout counted as this checkout's"
says d1 clear tmux-demo-task-2 tmux-window-dead
says d1 keep tmux-demo-task-4 alive
says d2 clear proc-demo-task-2b process-dead
says p1 keep pr-demo-task-4 in-flight
echo "ok: d1 d2 p1 x1 worker evidence"

# --- u1: lost observability ------------------------------------------------
fresh
reg tmux-demo-task-2 demo:task-2 tmux "$repo/.claude/worktrees/demo-2" "tmux-window sess-a @9"
seed tmux-demo-task-2 demo:task-2 working
printf 'down\n' >"$tmp/tmux-mode"
reconcile u1
printf 'up\n' >"$tmp/tmux-mode"
has_row tmux-demo-task-2 || fail "u1: an unreachable tmux server cleared the row"
says u1 keep tmux-demo-task-2 evidence-unknown
echo "ok: u1 unknown evidence keeps the row"

# --- e1, e2, e3: a worker that may still run keeps its row ------------------
# Even on a completed unit: only positive death, or no worker on record at
# all, lets the unit decide.
fresh
printf 'sess-a @1\n' >"$tmp/tmux-windows"
reg tmux-demo-task-1 demo:task-1 tmux "$repo/.claude/worktrees/demo-1" "tmux-window sess-a @1"
seed tmux-demo-task-1 demo:task-1 working
reconcile e2
clean e2
says e2 keep tmux-demo-task-1 alive
printf 'down\n' >"$tmp/tmux-mode"
reconcile e1
printf 'up\n' >"$tmp/tmux-mode"
has_row tmux-demo-task-1 || fail "e1: unknown evidence on a completed unit cleared the row"
says e1 keep tmux-demo-task-1 evidence-unknown
fresh
seed @145 demo:task-1 working
reg tmux-demo-task-1 demo:task-1 tmux "$other/wt" "tmux-window sess-a @1"
chmod 000 "$home/registry"
reconcile e3
chmod 600 "$home/registry"
has_row @145 || fail "e3: an unreadable registry let a row be judged without its worker evidence"
says e3 keep @145 evidence-unknown
printf '%s\n' "$out" | grep -q "status=degraded$" || fail "e3: an unreadable registry did not degrade the pass: $out"
echo "ok: e1 e2 e3 a worker that may still run keeps its row"

# --- m1, m2, m3: rows the pass cannot act on ------------------------------
fresh
seed wz demo:task-1 bogus
long=$(printf 'x%.0s' $(seq 1 130))
reg wlong "demo:$long" headless "$repo/specs/demo/.orchestrate/headless/9" "process $dead_pid"
seed wlong "demo:$long" working
reconcile m1
clean m1
says m1 keep wz malformed
says m1 keep wlong malformed
fresh
seed w8 demo:task-1 working 1700000000
seed w8 demo:task-1 working 1700000005
reconcile m2
has_row w8 || fail "m2: a duplicated handle lost its rows"
says m2 keep w8 duplicate
printf '%s\n' "$out" | grep -q "status=degraded$" || fail "m2: a duplicated handle did not degrade the pass: $out"
fresh
seed @145 demo:task-1 working
chmod 555 "$home/attention"
reconcile m3
chmod 755 "$home/attention"
has_row @145 || fail "m3: a failed clear removed the row"
says m3 keep @145 clear-failed
printf '%s\n' "$out" | grep -q "status=degraded$" || fail "m3: a failed clear did not degrade the pass: $out"
echo "ok: m1 m2 m3 rows the pass cannot act on"

# --- w1: the derivation reads --repo, whatever the caller's directory ------
fresh
seed @145 demo:task-1 working
out=$(cd / && fenv env PLANWRIGHT_REPO_ROOT="$other" /bin/sh "$REC" --repo "$repo" 2>"$tmp/err") \
  || fail "w1: reconcile exited non-zero: $(cat "$tmp/err")"
clean w1
says w1 clear @145 unit-completed
n_rc=0
(cd / && fenv /bin/sh "$REC" --repo "$other" >/dev/null 2>&1) || n_rc=$?
[ "$n_rc" = 2 ] || fail "w1: a --repo outside any repository exited $n_rc, expected 2"
echo "ok: w1 the derivation reads the named checkout"

# --- r1: a worker writing between the verdict and the clear -----------------
# The fake tmux runs $tmp/race on its session probe: the worker's heartbeat
# lands after the snapshot the verdict was reached on.
fresh
printf 'sess-a @1\n' >"$tmp/tmux-windows"
reg tmux-demo-task-2 demo:task-2 tmux "$repo/.claude/worktrees/demo-2" "tmux-window sess-a @9"
seed tmux-demo-task-2 demo:task-2 working 1700000000
printf '%s\n' \
  "awk -F '\\t' 'BEGIN { OFS = \"\\t\" } \$1 == \"tmux-demo-task-2\" { \$4 = 1700000009 } { print }' \"$home/attention/state\" >\"$home/attention/state.new\"" \
  "mv -f \"$home/attention/state.new\" \"$home/attention/state\"" >"$tmp/race"
reconcile r1
clean r1
rm -f "$tmp/race"
has_row tmux-demo-task-2 || fail "r1: a row rewritten after its verdict was cleared"
says r1 keep tmux-demo-task-2 changed
echo "ok: r1 a row rewritten since its verdict survives"

# --- i1: audit and idempotence ---------------------------------------------
fresh
seed @145 demo:task-1 working
reconcile i1
fenv /bin/sh "$S/fleet-audit.sh" query --mechanism attention-reconcile 2>/dev/null \
  | grep "${TAB}clear-row${TAB}" | grep -q 'worker=@145 scope=demo:task-1 state=working evidence=unit-completed' \
  || fail "i1: the clear was not audited"
reconcile i1
clean i1
printf '%s\n' "$out" | grep -q "^clear" && fail "i1: a second pass cleared again: $out"
says i1 summary rows=0 "cleared=0${TAB}kept=0${TAB}status=ok"
echo "ok: i1 audited and idempotent"

# --- k1: kill-switch -------------------------------------------------------
fresh
seed @145 demo:task-1 working
printf 'fleet_daemon_pause: true\n' >"$tmp/pause.yml"
k_rc=0
(cd "$repo" && fenv env PLANWRIGHT_LOCAL_CONFIG="$tmp/pause.yml" /bin/sh "$REC" --repo "$repo" >/dev/null 2>&1) || k_rc=$?
[ "$k_rc" = 4 ] || fail "k1: a paused pass exited $k_rc, expected 4"
has_row @145 || fail "k1: a paused pass cleared a row"
echo "ok: k1 kill-switch pauses the pass"

# --- k2: a kill-switch set mid-pass stops the clears that follow -----------
fresh
printf 'sess-a @1\n' >"$tmp/tmux-windows"
reg tmux-demo-task-2 demo:task-2 tmux "$repo/.claude/worktrees/demo-2" "tmux-window sess-a @9"
seed tmux-demo-task-2 demo:task-2 working
printf 'fleet_daemon_pause: false\n' >"$tmp/pause.yml"
printf '%s\n' "printf 'fleet_daemon_pause: true\\n' >\"$tmp/pause.yml\"" >"$tmp/race"
out=$(cd "$repo" && fenv env PLANWRIGHT_LOCAL_CONFIG="$tmp/pause.yml" /bin/sh "$REC" --repo "$repo" 2>"$tmp/err") \
  || fail "k2: a pass paused mid-way exited non-zero: $(cat "$tmp/err")"
rm -f "$tmp/race"
has_row tmux-demo-task-2 || fail "k2: a clear ran after the kill-switch was set"
printf '%s\n' "$out" | grep -q "^paused${TAB}-$" || fail "k2: no paused line: $out"
printf '%s\n' "$out" | grep -q "status=paused$" || fail "k2: no paused status: $out"
echo "ok: k2 a kill-switch set mid-pass stops the clears"

[ "$rc" = 0 ] || {
  echo "FAIL: $rc case(s) failed" >&2
  exit 1
}
echo "PASS: fleet-attention-reconcile"
