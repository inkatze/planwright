#!/bin/bash
# Tests for the dispatch-record reconcile: every dispatch seam leaves an
# on-disk dispatch marker beside its registry write, and the periodic sweep
# rebuilds a record whose write failed and retires the record of a worker
# with positive death evidence (fleet-lifecycle-closure D-15; REQ-E1.4,
# REQ-E1.5, REQ-K1.4, REQ-F1.3).
#
# Coverage:
#   h1 (REQ-E1.4): per dispatch seam, a suppressed registry write still leaves
#      the dispatch successful, warns, and leaves a marker; the next reconcile
#      rebuilds the record with exactly the fields the dispatch tried to write,
#      audits the heal, and a second reconcile changes nothing. The seam set is
#      read from the seam-coverage manifest test-fleet-registration.sh owns, and
#      every manifest seam must be exercised here.
#   r1 (REQ-E1.5): a closed worker's record is marked closed (appended, never
#      deleted), its marker removed, the retirement audited; the record stays
#      readable, and inventory reads stop listing it.
#   r2 (REQ-E1.5): an alive, unknown, or errored verdict keeps the record live.
#   r3 (REQ-E1.5): a print unit retires on its worktree's removal and not
#      before; one with no worktree recorded never retires.
#   r4 (REQ-E1.5): a record with no marker survives a sweep byte for byte.
#   r5: a re-dispatch of a retired handle is a live record again.
#   r6: a retirement whose record changed under it retires nothing.
#   c1 (REQ-E1.4): N concurrent reconciles over K missing records heal each
#      exactly once.
#   c2 (REQ-E1.4): a reconcile racing the dispatch's own write leaves exactly
#      one record.
#   c3 (REQ-E1.5): N concurrent reconciles retire a dead worker once.
#   x1 (REQ-K1.4): a marker failing the store's grammar is refused, audited
#      once, never stored.
#   x2 (REQ-K1.4): a marker outside its root (a symlink, or a symlinked marker
#      directory) is refused and its target left alone.
#   s1 (REQ-F1.3): the sweep runs the reconcile, in either reap mode, and the
#      kill-switch pauses it.
#   w1: no dispatch seam still says that no reconcile exists.
#
# Hermetic: every case pins its own fleet home under a temp root. Runs
# standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-dispatch-reconcile.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd -P)
S="$REPO_ROOT/scripts"
REC="$S/fleet-registry-reconcile.sh"

rc=0
fail() {
  echo "not ok: $1"
  echo "FAIL: $1" >&2
  rc=$((rc + 1))
}
case_rc=0
ok() {
  [ "$rc" = "$case_rc" ] && echo "ok $1: $2"
  case_rc=$rc
}

[ -f "$REC" ] || {
  echo "FAIL: scripts/fleet-registry-reconcile.sh missing" >&2
  exit 1
}

tmp=$(cd "$(mktemp -d)" && pwd -P)
cleanup() {
  set +e
  for p in $(jobs -p); do
    kill -9 "$p" 2>/dev/null
  done
  cl_snap=$(ps -A -ww -o pid=,args= 2>/dev/null) || cl_snap=''
  while read -r p a; do
    case $a in
      *"$tmp"*) [ "$p" = "$$" ] || kill -9 "$p" 2>/dev/null ;;
    esac
  done <<EOF
$cl_snap
EOF
  chmod -R u+rwx "$tmp" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
tab=$(printf '\t')

# No case may reach the host's tmux server: the death-evidence probes would
# ask the operator's own sessions about fixture windows. Every case sees a tmux
# that cannot be reached unless it puts its own stub first.
mkdir -p "$tmp/bin-notmux"
printf '#!/bin/sh\nexit 1\n' >"$tmp/bin-notmux/tmux"
chmod +x "$tmp/bin-notmux/tmux"
export PATH="$tmp/bin-notmux:$PATH"

core_cfg="$tmp/core-defaults.yml"
cp "$REPO_ROOT/config/defaults.yml" "$core_cfg"
repo_cfg="$tmp/cfg-repo"
mkdir -p "$repo_cfg/.claude"
mlocal_cfg="$repo_cfg/.claude/planwright.local.yml"

owner=p4242.t99.c17

env_scrub=(
  -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME
  -u PLANWRIGHT_ROOT -u PLANWRIGHT_TOWER_ID -u PLANWRIGHT_TOWER_SESSION_ID
  -u PLANWRIGHT_TOWER_PID -u PLANWRIGHT_TOWER_CHECKOUT
  -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE
  -u PLANWRIGHT_FLEET_LOCK_HELD -u PLANWRIGHT_ORCH_STATE_DIR
  -u PLANWRIGHT_HEADLESS_STATE_DIR -u PLANWRIGHT_SKILLS_ROOT
  -u TMUX -u TMUX_PANE
)

# The per-case fleet home.
home() {
  h="$tmp/fleet-$1"
  mkdir -p "$h"
  printf '%s\n' "$h"
}

# at <home> <tree> [VAR=val...] -- <script> <args...> — a script from <tree>
# against <home>, hermetic against the host's fleet state and configuration.
at() {
  at_home=$1
  at_tree=$2
  shift 2
  at_pre=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    at_pre+=("$1")
    shift
  done
  shift
  at_s=$1
  shift
  env "${env_scrub[@]}" \
    PLANWRIGHT_FLEET_STATE_DIR="$at_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_REPO_ROOT="$repo_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    ${at_pre[@]+"${at_pre[@]}"} /bin/sh "$at_tree/$at_s" "$@"
}

# reconcile <home> [tree] — one reconcile pass. Sets out, err, st.
reconcile() {
  st=0
  at "$1" "${2:-$S}" -- fleet-registry-reconcile.sh >"$tmp/out" 2>"$tmp/err" || st=$?
  out=$(cat "$tmp/out")
  err=$(cat "$tmp/err")
}

registry() {
  cat "$1/registry" 2>/dev/null || :
}

# rows <home> <handle> — every registry row for <handle>.
rows() {
  registry "$1" | awk -F'\t' -v w="$2" '($2 "") == (w "")'
}

# fields <row> — columns 2..7 of a registry row, the record minus its stamp.
fields() {
  printf '%s\n' "$1" | cut -f2-7
}

audits() {
  at "$1" "$S" -- fleet-audit.sh query --mechanism registry-reconcile 2>/dev/null || :
}

audit_count() {
  audits "$1" | awk -F'\t' -v a="$2" '$4 == a' | grep -c . || :
}

marker() {
  printf '%s/dispatch-markers/%s\n' "$1" "$2"
}

# register <home> <handle> <args...> — a dispatch through the register seam.
register() {
  r_home=$1
  r_h=$2
  shift 2
  at "$r_home" "$S" PLANWRIGHT_TOWER_ID="$owner" -- fleet-register.sh --handle "$r_h" "$@" >/dev/null 2>&1
}

dead_pid() {
  sleep 0 &
  dp=$!
  wait "$dp" 2>/dev/null
  printf '%s\n' "$dp"
}

# ===========================================================================
# h1 — every seam heals a suppressed registry write from its marker.
# ===========================================================================

# The suppressed tree: the store refuses every `register`, recording the
# fields the seam tried to write, and passes everything else to the real one.
sup="$tmp/sup"
mkdir -p "$sup"
cp -R "$REPO_ROOT/scripts" "$REPO_ROOT/config" "$REPO_ROOT/hooks" "$REPO_ROOT/skills" \
  "$REPO_ROOT/doctrine" "$REPO_ROOT/.claude-plugin" "$sup/"
mv "$sup/scripts/fleet-state.sh" "$sup/scripts/fleet-state-real.sh"
cat >"$sup/scripts/fleet-state.sh" <<'STUB'
#!/bin/sh
d=$(cd "$(dirname "$0")" && pwd)
if [ "${1:-}" = register ]; then
  { for a; do printf '%s\t' "$a"; done; printf '\n'; } >>"$SUPPRESS_LOG"
  exit 2
fi
exec /bin/sh "$d/fleet-state-real.sh" "$@"
STUB
chmod +x "$sup/scripts/"*.sh
SUPS="$sup/scripts"

# attempted <log> — the six record fields of the LAST register the seam tried,
# in store column order, `-` for an unsupplied optional field.
attempted() {
  tail -n 1 "$1" | awk -F'\t' '
    {
      pos = 0; o = "-"; b = "-"; sd = "-"; dh = "-"
      for (i = 2; i <= NF; i++) {
        a = $i
        if (a == "") continue
        if (a == "--owner") { o = $(++i); continue }
        if (a == "--backend") { b = $(++i); continue }
        if (a == "--state-dir") { sd = $(++i); continue }
        if (a == "--death-handle") { dh = $(++i); continue }
        if (a ~ /^--/) continue
        pos++
        if (pos == 1) w = a
        if (pos == 2) s = a
      }
      printf "%s\t%s\t%s\t%s\t%s\t%s\n", w, s, o, b, sd, dh
    }'
}

# heal_case <id> <home> <log> <dispatch-rc> <stderr-file> — the shared
# assertions once a seam dispatched against the suppressed tree.
heal_case() {
  hc_id=$1
  hc_home=$2
  hc_log=$3
  [ "$4" = 0 ] || fail "$hc_id: the dispatch failed when only its registry write did (exit $4)"
  grep -q 'the next sweep rebuilds the record from its dispatch marker' "$5" \
    || fail "$hc_id: the failed registry write was not warned visibly: $(cat "$5")"
  if [ ! -s "$hc_log" ]; then
    fail "$hc_id: the seam never tried to register"
    return
  fi
  hc_want=$(attempted "$hc_log")
  hc_h=${hc_want%%"$tab"*}
  [ -z "$(rows "$hc_home" "$hc_h")" ] || fail "$hc_id: the suppressed write reached the registry anyway"
  hc_m=$(marker "$hc_home" "$hc_h")
  if [ -f "$hc_m" ]; then
    [ "$(cat "$hc_m")" = "$hc_want" ] \
      || fail "$hc_id: the marker does not carry the record's fields: '$(cat "$hc_m")' vs '$hc_want'"
  else
    fail "$hc_id: the seam left no dispatch marker for $hc_h"
  fi
  reconcile "$hc_home"
  [ "$st" = 0 ] || fail "$hc_id: the reconcile exited $st ($err)"
  hc_rows=$(rows "$hc_home" "$hc_h")
  [ "$(printf '%s\n' "$hc_rows" | grep -c .)" = 1 ] \
    || fail "$hc_id: expected one healed record, got: $hc_rows"
  [ "$(fields "$hc_rows")" = "$hc_want" ] \
    || fail "$hc_id: the healed record differs from what the dispatch would have written: '$(fields "$hc_rows")' vs '$hc_want'"
  printf '%s\n' "$out" | grep -q "^heal${tab}$hc_h${tab}" \
    || fail "$hc_id: the reconcile did not report the heal: $out"
  [ "$(audit_count "$hc_home" heal)" = 1 ] || fail "$hc_id: the heal was not audited once: $(audits "$hc_home")"
  # A second pass heals nothing more. It may retire the record: a seam whose
  # fixture worker has already exited has positive death evidence by now.
  reconcile "$hc_home"
  [ "$(rows "$hc_home" "$hc_h" | awk -F'\t' 'NF == 7' | grep -c .)" = 1 ] \
    || fail "$hc_id: a second reconcile wrote another live record: $(rows "$hc_home" "$hc_h")"
  [ "$(audit_count "$hc_home" heal)" = 1 ] || fail "$hc_id: a second reconcile audited another heal"
  printf '%s\n' "$hc_id" >>"$tmp/seams-healed"
}

: >"$tmp/seams-healed"

# The fake CLI every launch seam runs: read the prompt and exit.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/fake-claude" <<'EOF'
#!/bin/sh
cat >/dev/null
exit 0
EOF
chmod +x "$tmp/bin/fake-claude"

# --- fleet-dispatch-headless.sh ---------------------------------------------
h=$(home h-headless)
log="$tmp/h-headless.log"
: >"$log"
mkdir -p "$tmp/wt-headless"
d_rc=0
printf 'do the thing\n' | at "$h" "$SUPS" SUPPRESS_LOG="$log" PLANWRIGHT_TOWER_ID="$owner" \
  PLANWRIGHT_HEADLESS_CLAUDE="$tmp/bin/fake-claude" \
  PLANWRIGHT_HEADLESS_STATE_DIR="$tmp/state-headless" -- \
  fleet-dispatch-headless.sh launch spec-h 3 --worktree "$tmp/wt-headless" >/dev/null 2>"$tmp/h-headless.err" || d_rc=$?
heal_case "fleet-dispatch-headless.sh" "$h" "$log" "$d_rc" "$tmp/h-headless.err"

# --- fleet-streamjson.sh ----------------------------------------------------
h=$(home h-sj)
log="$tmp/h-sj.log"
: >"$log"
printf 'do the thing\n' >"$tmp/prompt"
d_rc=0
at "$h" "$SUPS" SUPPRESS_LOG="$log" PLANWRIGHT_TOWER_ID="$owner" \
  PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/fake-claude" -- \
  fleet-streamjson.sh launch w-sj spec-sj:1 --prompt-file "$tmp/prompt" >/dev/null 2>"$tmp/h-sj.err" || d_rc=$?
heal_case "fleet-streamjson.sh" "$h" "$log" "$d_rc" "$tmp/h-sj.err"
for pf in "$h/streamjson/w-sj/supervisor.pid" "$h/streamjson/w-sj/worker.pid"; do
  p=$(cat "$pf" 2>/dev/null) || continue
  case $p in '' | *[!0-9]*) continue ;; esac
  case $(ps -o command= -p "$p" 2>/dev/null) in
    *"$tmp"* | *fleet-streamjson.sh*) kill -9 "$p" 2>/dev/null ;;
  esac
done
rm -f "$h/streamjson/w-sj/supervisor.pid" "$h/streamjson/w-sj/worker.pid"

# --- offload-dispatch.sh: print, tmux, and the subagent report --------------
h=$(home h-offload-print)
log="$tmp/h-offload-print.log"
: >"$log"
d_rc=0
at "$h" "$SUPS" SUPPRESS_LOG="$log" PLANWRIGHT_TOWER_ID="$owner" -- \
  offload-dispatch.sh dispatch print "$tmp/prompt" >/dev/null 2>"$tmp/h-op.err" || d_rc=$?
heal_case "offload-dispatch.sh" "$h" "$log" "$d_rc" "$tmp/h-op.err"

stub_tmux="$tmp/bin-offload-tmux"
mkdir -p "$stub_tmux"
cat >"$stub_tmux/tmux" <<'EOF'
#!/bin/sh
case "$1" in
  new-window) printf '@31\n' ;;
  display-message) printf 'offload-sess\n' ;;
esac
exit 0
EOF
chmod +x "$stub_tmux/tmux"
h=$(home h-offload-tmux)
log="$tmp/h-offload-tmux.log"
: >"$log"
d_rc=0
PATH="$stub_tmux:$PATH" at "$h" "$SUPS" SUPPRESS_LOG="$log" PLANWRIGHT_TOWER_ID="$owner" -- \
  offload-dispatch.sh dispatch tmux "$tmp/prompt" >/dev/null 2>"$tmp/h-ot.err" || d_rc=$?
heal_case "offload-dispatch.sh tmux" "$h" "$log" "$d_rc" "$tmp/h-ot.err"

h=$(home h-offload-subagent)
log="$tmp/h-offload-subagent.log"
: >"$log"
d_rc=0
at "$h" "$SUPS" SUPPRESS_LOG="$log" PLANWRIGHT_TOWER_ID="$owner" -- \
  offload-dispatch.sh report subagent agent-7 >/dev/null 2>"$tmp/h-os.err" || d_rc=$?
heal_case "offload-dispatch.sh subagent" "$h" "$log" "$d_rc" "$tmp/h-os.err"

# --- fleet-dispatch-worktree.sh (the /orchestrate tmux rung) ----------------
gitc() {
  gc_r=$1
  shift
  git -C "$gc_r" -c user.name=t -c user.email=t@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}
wrepo="$tmp/repo-wt"
mkdir -p "$wrepo/specs/spec-w"
gitc "$wrepo" init -q -b main >/dev/null 2>&1
printf 'x\n' >"$wrepo/specs/spec-w/requirements.md"
gitc "$wrepo" add -A >/dev/null 2>&1
gitc "$wrepo" commit -qm init >/dev/null 2>&1
stub_w="$tmp/bin-wt"
mkdir -p "$stub_w"
printf '#!/bin/sh\nexit 0\n' >"$stub_w/claude"
wtpath="$wrepo/.claude/worktrees/spec-w-task-1"
cat >"$stub_w/tmux" <<EOF
#!/bin/sh
case "\$1" in
  list-panes) printf '%s\tworker-session\t@42\t%s\n' "\$(date +%s)" "$wtpath" ;;
esac
exit 0
EOF
chmod +x "$stub_w/claude" "$stub_w/tmux"
h=$(home h-worktree)
log="$tmp/h-worktree.log"
: >"$log"
d_rc=0
PATH="$stub_w:$PATH" at "$h" "$SUPS" SUPPRESS_LOG="$log" PLANWRIGHT_TOWER_ID="$owner" \
  PLANWRIGHT_DISPATCH_LIVENESS_SKIP_TMUX=1 -- \
  fleet-dispatch-worktree.sh dispatch spec-w 1 --repo-root "$wrepo" >/dev/null 2>"$tmp/h-wt.err" || d_rc=$?
heal_case "fleet-dispatch-worktree.sh" "$h" "$log" "$d_rc" "$tmp/h-wt.err"

# --- flight-dispatch.sh (the visual-flight print rung) ----------------------
fc="$tmp/flight"
mkdir -p "$fc"
git -c init.defaultBranch=main init -q --bare "$fc/origin.git"
git clone -q "$fc/origin.git" "$fc/primary" 2>/dev/null
printf 'x\n' >"$fc/primary/README.md"
gitc "$fc/primary" add -A
gitc "$fc/primary" commit -q -m init
gitc "$fc/primary" branch -M main
gitc "$fc/primary" push -q origin main
mkdir -p "$fc/bin" "$fc/adopter"
printf '#!/bin/sh\nexit 0\n' >"$fc/bin/gh"
chmod +x "$fc/bin/gh"
printf 'Fix the typo in the README heading.\n' >"$fc/ask.txt"
printf 'visual flight: a one-line wording change, one revert from undone\n' >"$fc/grounds.txt"
h=$(home h-flight)
log="$tmp/h-flight.log"
: >"$log"
d_rc=0
PATH="$fc/bin:$PATH" env "${env_scrub[@]}" \
  -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS \
  PLANWRIGHT_FLEET_STATE_DIR="$h" \
  PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$fc/fstate" \
  PLANWRIGHT_DISPATCH_LIVENESS_SKIP_TMUX=1 \
  PLANWRIGHT_REPO_ROOT="$fc/primary" \
  PLANWRIGHT_ADOPTER_OVERLAY="$fc/adopter" \
  CLAUDE_DIR="$fc/claude" \
  SUPPRESS_LOG="$log" PLANWRIGHT_TOWER_ID="$owner" \
  /bin/sh "$SUPS/flight-dispatch.sh" dispatch readme-typo --backend print \
  --ask-file "$fc/ask.txt" --grounds-file "$fc/grounds.txt" --repo-root "$fc/primary" \
  </dev/null >"$tmp/h-flight.out" 2>"$tmp/h-flight.err" || d_rc=$?
[ "$d_rc" = 0 ] || echo "# flight dispatch stderr: $(cat "$tmp/h-flight.err")"
heal_case "flight-dispatch.sh" "$h" "$log" "$d_rc" "$tmp/h-flight.err"

# Every seam the seam-coverage manifest names was exercised here.
manifest=$(awk '/^manifest="/ { on = 1; sub(/^manifest="/, "") } on { line = $0; done = sub(/"$/, "", line); print line; if (done) exit }' \
  "$here/test-fleet-registration.sh")
[ -n "$manifest" ] || fail "h1: could not read the seam-coverage manifest from test-fleet-registration.sh"
for seam in $manifest; do
  grep -q "^$seam\( \|\$\)" "$tmp/seams-healed" \
    || fail "h1: the manifest seam $seam has no heal case here"
done
ok h1 "every dispatch seam leaves a marker the next reconcile heals a suppressed write from, once"

# ===========================================================================
# r1 — a closed worker's record retires: marked closed, marker gone, audited.
# ===========================================================================
h=$(home r1)
dp=$(dead_pid)
register "$h" w-r1 --scope spec-r:1 --backend headless-oneshot \
  --state-dir "$tmp/unit-r1" --death-handle "process $dp" \
  || fail "r1: the dispatch did not register"
[ -f "$(marker "$h" w-r1)" ] || fail "r1: a registered dispatch left no marker"
live_row=$(rows "$h" w-r1)
reconcile "$h"
[ "$st" = 0 ] || fail "r1: the reconcile exited $st ($err)"
r1_rows=$(rows "$h" w-r1)
[ "$(printf '%s\n' "$r1_rows" | grep -c .)" = 2 ] || fail "r1: expected the live row plus a closed one: $r1_rows"
[ "$(printf '%s\n' "$r1_rows" | head -n 1)" = "$live_row" ] || fail "r1: the live row was rewritten or deleted"
last=$(printf '%s\n' "$r1_rows" | tail -n 1)
[ "$(printf '%s\n' "$last" | awk -F'\t' '{ print NF }')" = 8 ] || fail "r1: the closed row is not eight columns: $last"
[ "$(printf '%s\n' "$last" | cut -f8)" = closed ] || fail "r1: the closed row is not marked closed: $last"
[ "$(fields "$last")" = "$(fields "$live_row")" ] || fail "r1: the closed row does not carry the record's fields"
[ ! -e "$(marker "$h" w-r1)" ] || fail "r1: the retired record's marker is still there"
printf '%s\n' "$out" | grep -q "^retire${tab}w-r1${tab}" || fail "r1: the retirement was not reported: $out"
[ "$(audit_count "$h" retire)" = 1 ] || fail "r1: the retirement was not audited once: $(audits "$h")"
# Readable, but no longer in the live inventory.
cls=$(at "$h" "$S" -- fleet-stuck-detector.sh classify w-r1 --tower-id "$owner" 2>/dev/null)
printf '%s\n' "$cls" | grep -q "^evidence${tab}w-r1${tab}registry${tab}present$" \
  || fail "r1: a retired record is no longer readable per handle: $cls"
# A live worker beside it is the positive control: the readers must list it.
register "$h" w-r1-live --scope spec-r:1b --backend tmux --death-handle "tmux-window x @1" \
  || fail "r1: could not register the live control"
scan_rc=0
scan=$(at "$h" "$S" -- fleet-stuck-detector.sh scan --tower-id "$owner" 2>/dev/null) || scan_rc=$?
[ "$scan_rc" = 0 ] || fail "r1: the detector's scan exited $scan_rc"
printf '%s\n' "$scan" | grep -q "^worker${tab}w-r1-live${tab}" || fail "r1: the scan does not list the live control: $scan"
printf '%s\n' "$scan" | grep -q "^worker${tab}w-r1${tab}" && fail "r1: the detector's scan still lists a retired worker"
status_rc=0
status=$(at "$h" "$S" -- fleet-status.sh render 2>/dev/null) || status_rc=$?
[ "$status_rc" = 0 ] || fail "r1: the status render exited $status_rc"
printf '%s\n' "$status" | grep -q 'w-r1-live' || fail "r1: the status render does not list the live control"
printf '%s\n' "$status" | grep -qE 'w-r1([^-]|$)' && fail "r1: the status render still lists a retired worker"
before=$(registry "$h")
reconcile "$h"
[ "$(registry "$h")" = "$before" ] || fail "r1: a second reconcile wrote to a retired record"
[ "$(audit_count "$h" retire)" = 1 ] || fail "r1: a second reconcile audited another retirement"
ok r1 "a dead worker's record is marked closed, never deleted, its marker gone, the retirement audited once"

# ===========================================================================
# r2 — alive, unknown and errored verdicts keep the record live.
# ===========================================================================
h=$(home r2)
sleep 300 &
alive_pid=$!
register "$h" w-alive --scope spec-r:2 --backend headless-oneshot --death-handle "process $alive_pid"
register "$h" w-unknown --scope spec-r:3 --backend tmux --death-handle "tmux-window nosuch @9"
stub_dead_tmux="$tmp/bin-unreachable-tmux"
mkdir -p "$stub_dead_tmux"
printf '#!/bin/sh\nexit 1\n' >"$stub_dead_tmux/tmux"
chmod +x "$stub_dead_tmux/tmux"
before=$(registry "$h")
st=0
PATH="$stub_dead_tmux:$PATH" at "$h" "$S" -- fleet-registry-reconcile.sh >"$tmp/out" 2>"$tmp/err" || st=$?
out=$(cat "$tmp/out")
[ "$st" = 0 ] || fail "r2: the reconcile exited $st"
[ "$(registry "$h")" = "$before" ] || fail "r2: an alive or unknown verdict changed the registry"
[ -f "$(marker "$h" w-alive)" ] && [ -f "$(marker "$h" w-unknown)" ] || fail "r2: a live record lost its marker"
printf '%s\n' "$out" | grep -q "^keep${tab}w-unknown${tab}" || fail "r2: an unknown verdict was not reported: $out"
# An errored predicate is not evidence either.
ert="$tmp/err-tree"
mkdir -p "$ert"
cp -R "$S" "$ert/"
printf '#!/bin/sh\nexit 2\n' >"$ert/scripts/fleet-death-evidence.sh"
chmod +x "$ert/scripts/fleet-death-evidence.sh"
dp=$(dead_pid)
register "$h" w-errored --scope spec-r:4 --backend headless-oneshot --death-handle "process $dp"
before=$(registry "$h")
reconcile "$h" "$ert/scripts"
[ "$(registry "$h")" = "$before" ] || fail "r2: an errored verdict retired a record"
printf '%s\n' "$out" | grep -q "^keep${tab}w-errored${tab}" || fail "r2: an errored verdict was not reported: $out"
[ "$(audit_count "$h" retire)" = 0 ] || fail "r2: a kept record was audited as retired"
kill "$alive_pid" 2>/dev/null
wait "$alive_pid" 2>/dev/null
ok r2 "alive, unknown and errored death evidence keep the record live"

# ===========================================================================
# r3 — a print unit retires on its worktree's removal, and not before.
# ===========================================================================
h=$(home r3)
mkdir -p "$tmp/print-wt"
register "$h" print-flight-1 --scope flight:1 --backend print --state-dir "$tmp/print-wt" --death-handle none
register "$h" print-offload-1 --scope offload --backend print --death-handle none
before=$(registry "$h")
reconcile "$h"
[ "$(registry "$h")" = "$before" ] || fail "r3: a print unit retired while its worktree stands"
rmdir "$tmp/print-wt"
reconcile "$h"
last=$(rows "$h" print-flight-1 | tail -n 1)
[ "$(printf '%s\n' "$last" | cut -f8)" = closed ] || fail "r3: a removed print worktree did not retire its record"
printf '%s\n' "$out" | grep -q "^retire${tab}print-flight-1${tab}worktree-removed" \
  || fail "r3: the print retirement does not name its evidence: $out"
[ "$(rows "$h" print-offload-1 | grep -c .)" = 1 ] || fail "r3: a print unit with no worktree recorded was retired"
ok r3 "a print unit retires once its worktree is gone; one with no worktree never does"

# ===========================================================================
# r4 — a record that predates markers survives a sweep unchanged.
# ===========================================================================
h=$(home r4)
dp=$(dead_pid)
at "$h" "$S" -- fleet-state.sh register w-pre spec-r:5 --owner "$owner" --backend headless-oneshot \
  --death-handle "process $dp" >/dev/null 2>&1 || fail "r4: could not seed a pre-marker record"
printf '%s\tw-legacy\tspec-r:6\n' "$(date +%s)" >>"$h/registry"
before=$(registry "$h")
reconcile "$h"
[ "$st" = 0 ] || fail "r4: the reconcile exited $st"
[ "$(registry "$h")" = "$before" ] || fail "r4: a record with no marker was altered"
ok r4 "a record with no marker survives the reconcile byte for byte"

# ===========================================================================
# r5 — a re-dispatch of a retired handle is a live record again.
# ===========================================================================
h=$(home r5)
dp=$(dead_pid)
register "$h" w-r5 --scope spec-r:7 --backend headless-oneshot --death-handle "process $dp"
reconcile "$h"
[ "$(rows "$h" w-r5 | tail -n 1 | cut -f8)" = closed ] || fail "r5: fixture: the first worker did not retire"
sleep 300 &
p5=$!
register "$h" w-r5 --scope spec-r:7 --backend headless-oneshot --death-handle "process $p5"
last=$(rows "$h" w-r5 | tail -n 1)
[ "$(printf '%s\n' "$last" | awk -F'\t' '{ print NF }')" = 7 ] || fail "r5: the re-dispatch did not append a live record"
[ -f "$(marker "$h" w-r5)" ] || fail "r5: the re-dispatch left no marker"
kill "$p5" 2>/dev/null
wait "$p5" 2>/dev/null
ok r5 "a re-dispatch after retirement is live again"

# ===========================================================================
# r6 — a retirement whose record changed under it retires nothing.
# ===========================================================================
h=$(home r6)
dp=$(dead_pid)
register "$h" w-r6 --scope spec-r:8 --backend headless-oneshot --death-handle "process $dp"
cp "$(marker "$h" w-r6)" "$tmp/r6-old-marker"
sleep 300 &
p6=$!
register "$h" w-r6 --scope spec-r:8 --backend headless-oneshot --death-handle "process $p6"
# The reconcile judged the old record dead; a re-dispatch rewrote the marker
# and the record before the retirement ran. It retires the fields it judged,
# which are no longer live, so it closes nothing and leaves the new marker.
new_marker=$(cat "$(marker "$h" w-r6)")
before=$(registry "$h")
r6_rc=0
at "$h" "$S" -- fleet-register.sh --retire-marker "$(marker "$h" w-r6)" \
  --expect "$(cat "$tmp/r6-old-marker")" >/dev/null 2>&1 || r6_rc=$?
[ "$r6_rc" = 3 ] || fail "r6: a stale retirement did not report a no-op (exit $r6_rc)"
[ "$(registry "$h")" = "$before" ] || fail "r6: a stale retirement closed the live re-dispatch"
[ "$(cat "$(marker "$h" w-r6)" 2>/dev/null)" = "$new_marker" ] || fail "r6: a stale retirement removed the re-dispatch's marker"
kill "$p6" 2>/dev/null
wait "$p6" 2>/dev/null
ok r6 "a retirement against a record that moved on closes nothing and keeps the new marker"

# ===========================================================================
# r7 — a field the store compares may carry a backslash: an unchanged
#      re-registration writes nothing, and the record still retires.
# ===========================================================================
h=$(home r7)
dp=$(dead_pid)
for _ in 1 2; do
  register "$h" w-r7 --scope spec-r:9 --backend headless-oneshot \
    --state-dir '/w/a\nb' --death-handle "process $dp"
done
[ "$(rows "$h" w-r7 | grep -c .)" = 1 ] || fail "r7: an unchanged re-registration with a backslash appended a duplicate"
reconcile "$h"
[ "$(rows "$h" w-r7 | tail -n 1 | cut -f8)" = closed ] || fail "r7: a record with a backslash in a field never retires"
[ ! -e "$(marker "$h" w-r7)" ] || fail "r7: the retired record's marker stayed"
ok r7 "a backslash in a stored field compares as itself"

# ===========================================================================
# r8 — a record that disagrees with its marker (a superseding write that
#      failed) is judged on its own fields; once it retires, the marker heals.
# ===========================================================================
h=$(home r8)
dp=$(dead_pid)
register "$h" w-r8 --scope spec-r:10 --backend headless-oneshot --death-handle "process $dp"
sleep 300 &
p8=$!
printf 'w-r8\tspec-r:10\t%s\theadless-oneshot\t-\tprocess %s\n' "$owner" "$p8" >"$(marker "$h" w-r8)"
reconcile "$h"
printf '%s\n' "$out" | grep -q "^retire${tab}w-r8${tab}process-dead" || fail "r8: the dead record was not retired: $out"
[ -f "$(marker "$h" w-r8)" ] || fail "r8: the newer marker went with the record it does not describe"
reconcile "$h"
last=$(rows "$h" w-r8 | tail -n 1)
[ "$(fields "$last")" = "$(cat "$(marker "$h" w-r8)")" ] && [ "$(printf '%s\n' "$last" | awk -F'\t' '{ print NF }')" = 7 ] \
  || fail "r8: the newer marker was not healed into a live record: $last"
# Alive and disagreeing: kept, and said so.
h=$(home r8b)
register "$h" w-r8b --scope spec-r:11 --backend headless-oneshot --death-handle "process $p8"
printf 'w-r8b\tspec-r:11\t%s\theadless-oneshot\t/x\tprocess %s\n' "$owner" "$p8" >"$(marker "$h" w-r8b)"
reconcile "$h"
printf '%s\n' "$out" | grep -q "^keep${tab}w-r8b${tab}marker-diverged" || fail "r8: a diverged live record was not reported: $out"
kill "$p8" 2>/dev/null
wait "$p8" 2>/dev/null
ok r8 "a record its marker no longer describes retires on its own evidence, then the marker heals"

# ===========================================================================
# r9 — a record with no evidence source is counted, never retired.
# ===========================================================================
h=$(home r9)
register "$h" agent-9 --scope offload --backend subagent --death-handle none
reconcile "$h"
printf '%s\n' "$out" | grep -q "unjudged=1" || fail "r9: a record with no evidence source was not counted: $out"
[ "$(rows "$h" agent-9 | grep -c .)" = 1 ] || fail "r9: a record with no evidence source was altered"
ok r9 "a record with no evidence source is counted as unjudged and left live"

# ===========================================================================
# r10 — an alive worker whose marker matches its record is counted, so the
#       summary accounts for the steady-state marker.
# ===========================================================================
h=$(home r10)
sleep 300 &
p10=$!
register "$h" w-r10 --scope spec-r:12 --backend headless-oneshot --death-handle "process $p10"
reconcile "$h"
printf '%s\n' "$out" | grep -q "${tab}live=1${tab}" || fail "r10: an alive, current record was not counted live: $out"
kill "$p10" 2>/dev/null
wait "$p10" 2>/dev/null
ok r10 "an alive record its marker matches is counted live"

# ===========================================================================
# r11 — a registry that cannot be read degrades the pass rather than reading
#       as an empty one.
# ===========================================================================
h=$(home r11)
register "$h" w-r11 --scope spec-r:13 --backend headless-oneshot --death-handle none
chmod 000 "$h/registry"
reconcile "$h"
chmod 600 "$h/registry"
printf '%s\n' "$out" | grep -q "status=degraded" || fail "r11: an unreadable registry did not degrade the pass: $out"
printf '%s\n' "$out" | grep -q "^heal${tab}" && fail "r11: an unreadable registry was read as empty and healed from"
printf '%s\n' "$err" | grep -q 'could not read the registry' || fail "r11: the pass did not say the registry was unreadable: $err"
ok r11 "an unreadable registry degrades the pass instead of reading as empty"

# ===========================================================================
# c1 — N concurrent reconciles heal each missing record exactly once.
# ===========================================================================
h=$(home c1)
mkdir -p "$h/dispatch-markers"
k=0
for i in 1 2 3 4 5; do
  printf 'w-c1-%s\tspec-c:%s\t%s\theadless-oneshot\t-\t-\n' "$i" "$i" "$owner" >"$h/dispatch-markers/w-c1-$i"
  k=$((k + 1))
done
pids=''
for _ in 1 2 3 4 5 6 7 8; do
  at "$h" "$S" -- fleet-registry-reconcile.sh >/dev/null 2>&1 &
  pids="$pids $!"
done
for p in $pids; do wait "$p" 2>/dev/null; done
for i in 1 2 3 4 5; do
  n=$(rows "$h" "w-c1-$i" | grep -c .)
  [ "$n" = 1 ] || fail "c1: w-c1-$i has $n records after 8 concurrent reconciles"
done
[ "$(audit_count "$h" heal)" = "$k" ] || fail "c1: $(audit_count "$h" heal) heal audits for $k heals"
ok c1 "eight concurrent reconciles heal five records exactly once each"

# ===========================================================================
# c2 — a reconcile racing the dispatch's own write leaves exactly one record.
# ===========================================================================
h=$(home c2)
for i in 1 2 3 4 5 6 7 8 9 10; do
  register "$h" "w-c2-$i" --scope "spec-c2:$i" --backend headless-oneshot &
  rp=$!
  at "$h" "$S" -- fleet-registry-reconcile.sh >/dev/null 2>&1 &
  cp2=$!
  wait "$rp" 2>/dev/null
  wait "$cp2" 2>/dev/null
  n=$(rows "$h" "w-c2-$i" | grep -c .)
  [ "$n" = 1 ] || fail "c2: round $i left $n records for one dispatch"
done
# The same race forced: the store write is held back until the reconcile has
# healed from the marker, so the dispatch's own write lands second.
slow="$tmp/slow-store"
mkdir -p "$slow"
cp -R "$S" "$slow/"
mv "$slow/scripts/fleet-state.sh" "$slow/scripts/fleet-state-real.sh"
cat >"$slow/scripts/fleet-state.sh" <<STUB
#!/bin/sh
d=\$(cd "\$(dirname "\$0")" && pwd)
if [ "\${1:-}" = register ] && [ -e "$tmp/hold-store" ]; then
  : >"$tmp/store-held"
  while [ -e "$tmp/hold-store" ]; do sleep 0.05; done
fi
exec /bin/sh "\$d/fleet-state-real.sh" "\$@"
STUB
chmod +x "$slow/scripts/fleet-state.sh"
h=$(home c2b)
: >"$tmp/hold-store"
rm -f "$tmp/store-held"
at "$h" "$slow/scripts" PLANWRIGHT_TOWER_ID="$owner" -- fleet-register.sh --handle w-c2b \
  --scope spec-c2:b --backend headless-oneshot >/dev/null 2>&1 &
rp=$!
c2_n=0
until [ -e "$tmp/store-held" ] || [ "$c2_n" -ge 200 ]; do
  sleep 0.05
  c2_n=$((c2_n + 1))
done
[ -e "$tmp/store-held" ] || fail "c2: fixture: the dispatch never reached its store write"
reconcile "$h"
printf '%s\n' "$out" | grep -q "^heal${tab}w-c2b${tab}" || fail "c2: the reconcile did not heal ahead of the dispatch's write: $out"
rm -f "$tmp/hold-store"
wait "$rp" 2>/dev/null
[ "$(rows "$h" w-c2b | grep -c .)" = 1 ] || fail "c2: a heal ahead of the dispatch's own write left $(rows "$h" w-c2b | grep -c .) records"
ok c2 "a reconcile racing a dispatch's own write neither duplicates nor loses its record"

# ===========================================================================
# c3 — N concurrent reconciles retire a dead worker once.
# ===========================================================================
h=$(home c3)
dp=$(dead_pid)
register "$h" w-c3 --scope spec-c3:1 --backend headless-oneshot --death-handle "process $dp"
pids=''
for _ in 1 2 3 4 5 6 7 8; do
  at "$h" "$S" -- fleet-registry-reconcile.sh >/dev/null 2>&1 &
  pids="$pids $!"
done
for p in $pids; do wait "$p" 2>/dev/null; done
[ "$(rows "$h" w-c3 | awk -F'\t' '$8 == "closed"' | grep -c .)" = 1 ] \
  || fail "c3: concurrent reconciles closed the record $(rows "$h" w-c3 | awk -F'\t' '$8 == "closed"' | grep -c .) times"
[ "$(audit_count "$h" retire)" = 1 ] || fail "c3: $(audit_count "$h" retire) retirement audits for one retirement"
ok c3 "eight concurrent reconciles retire a dead worker exactly once"

# ===========================================================================
# x1 — a marker failing the store's grammar is refused, audited once, never
#      stored.
# ===========================================================================
h=$(home x1)
md="$h/dispatch-markers"
mkdir -p "$md"
esc=$(printf '\033')
printf 'w-x1a\tspec:1\t../evil\theadless-oneshot\t-\t-\n' >"$md/w-x1a"
printf 'w-x1b\tspec:1\t%s\tBad\t-\t-\n' "$owner" >"$md/w-x1b"
printf 'w-x1c\tspec:1\t%s\ttmux\trelative/dir\t-\n' "$owner" >"$md/w-x1c"
printf 'w-x1d\tspec:1\t%s\ttmux\t-\ttimeout 30\n' "$owner" >"$md/w-x1d"
printf 'w-other\tspec:1\t%s\ttmux\t-\t-\n' "$owner" >"$md/w-x1e"
printf 'w-x1f\tspec:1\t%s\ttmux\n' "$owner" >"$md/w-x1f"
printf 'w-x1g\tspec%s:1\t%s\ttmux\t-\t-\n' "$esc" "$owner" >"$md/w-x1g"
printf 'w x1h\tspec:1\t%s\ttmux\t-\t-\n' "$owner" >"$md/w x1h"
reconcile "$h"
[ "$st" = 0 ] || fail "x1: the reconcile exited $st"
[ -z "$(registry "$h")" ] || fail "x1: a refused marker reached the registry: $(registry "$h")"
[ "$(printf '%s\n' "$out" | awk -F'\t' '$1 == "refuse"' | grep -c .)" = 8 ] \
  || fail "x1: expected eight refusals: $out"
case $out$err in
  *"$esc"*) fail "x1: a control byte from a marker reached the terminal" ;;
esac
[ "$(audit_count "$h" refuse-marker)" = 8 ] || fail "x1: $(audit_count "$h" refuse-marker) refusal audits for eight refusals"
reconcile "$h"
[ "$(audit_count "$h" refuse-marker)" = 8 ] || fail "x1: a refused marker was audited again on the next pass"
ok x1 "a marker failing the store's grammar is refused, audited once, and never stored"

# ===========================================================================
# x2 — a marker outside its root is refused, and its target left alone.
# ===========================================================================
h=$(home x2)
md="$h/dispatch-markers"
mkdir -p "$md"
outside="$tmp/outside-marker"
printf 'w-x2\tspec:1\t%s\ttmux\t-\t-\n' "$owner" >"$outside"
ln -s "$outside" "$md/w-x2"
reconcile "$h"
[ -z "$(registry "$h")" ] || fail "x2: a symlinked marker was healed"
[ -f "$outside" ] && [ "$(cat "$outside")" = "w-x2${tab}spec:1${tab}$owner${tab}tmux${tab}-${tab}-" ] \
  || fail "x2: the reconcile touched a file outside the marker root"
printf '%s\n' "$out" | grep -q "^refuse${tab}w-x2${tab}" || fail "x2: a symlinked marker was not refused: $out"
[ "$(audit_count "$h" refuse-marker)" = 1 ] || fail "x2: the symlinked marker was not audited"
h=$(home x2b)
mkdir -p "$tmp/elsewhere"
printf 'w-x2b\tspec:1\t%s\ttmux\t-\t-\n' "$owner" >"$tmp/elsewhere/w-x2b"
ln -s "$tmp/elsewhere" "$h/dispatch-markers"
reconcile "$h"
[ -z "$(registry "$h")" ] || fail "x2: a symlinked marker directory was healed from"
[ -f "$tmp/elsewhere/w-x2b" ] || fail "x2: the reconcile removed a file through a symlinked marker directory"
printf '%s\n' "$out" | grep -q "status=degraded" || fail "x2: a symlinked marker directory did not degrade the pass: $out"
# A link at the marker name of a worker whose record is live is refused and
# moved aside too, and so is a name that only reads as a handle through an
# escape.
h=$(home x2d)
sleep 300 &
px=$!
register "$h" w-x2d --scope spec:1 --backend headless-oneshot --death-handle "process $px"
register "$h" worker --scope spec:2 --backend headless-oneshot --death-handle "process $px"
printf 'w-x2d\tspec:1\t%s\theadless-oneshot\t-\tprocess %s\n' "$owner" "$px" >"$tmp/x2d-target"
rm -f "$(marker "$h" w-x2d)"
ln -s "$tmp/x2d-target" "$(marker "$h" w-x2d)"
cp "$(marker "$h" worker)" "$h/dispatch-markers/w\\157rker"
reconcile "$h"
printf '%s\n' "$out" | grep -q "^refuse${tab}w-x2d${tab}" || fail "x2: a link at a live worker's marker name was not refused: $out"
[ ! -L "$(marker "$h" w-x2d)" ] || fail "x2: the link stayed at the marker name"
[ -f "$tmp/x2d-target" ] || fail "x2: the link's target was touched"
printf '%s\n' "$out" | grep -q "^refuse${tab}w.157rker${tab}" || fail "x2: an escape-spelled marker name was not refused: $out"
kill "$px" 2>/dev/null
wait "$px" 2>/dev/null

# Named directly: a path outside the marker directory, one climbing out of it,
# and a directory inside it are each refused by the register seam itself.
h=$(home x2c)
mkdir -p "$h/dispatch-markers/w-dir" "$tmp/x2c"
printf 'w-out\tspec:1\t%s\ttmux\t-\t-\n' "$owner" >"$tmp/x2c/w-out"
for p in "$tmp/x2c/w-out" "$h/dispatch-markers/../w-out" "$h/dispatch-markers/w-dir"; do
  x_rc=0
  at "$h" "$S" -- fleet-register.sh --from-marker "$p" >/dev/null 2>&1 || x_rc=$?
  [ "$x_rc" = 4 ] || fail "x2: --from-marker '$p' was not refused (exit $x_rc)"
done
[ -z "$(registry "$h")" ] || fail "x2: a marker named outside its root reached the registry"
ok x2 "a marker or marker directory outside the root is refused and its target left alone"

# ===========================================================================
# s1 — the sweep runs the reconcile in either reap mode; the kill-switch
#      pauses it.
# ===========================================================================
srepo="$tmp/sweep-repo"
mkdir -p "$srepo"
gitc "$srepo" init -q -b main >/dev/null 2>&1
printf 'x\n' >"$srepo/f"
gitc "$srepo" add -A >/dev/null 2>&1
gitc "$srepo" commit -qm init >/dev/null 2>&1
for mode in observe terminate; do
  h=$(home "s1-$mode")
  mkdir -p "$h/dispatch-markers"
  printf 'w-s1\tspec-s:1\t%s\theadless-oneshot\t-\t-\n' "$owner" >"$h/dispatch-markers/w-s1"
  dp=$(dead_pid)
  register "$h" w-s1-dead --scope spec-s:2 --backend headless-oneshot --death-handle "process $dp"
  printf 'fleet_sweep_reap: %s\n' "$mode" >"$mlocal_cfg"
  st=0
  at "$h" "$S" PLANWRIGHT_LOCAL_CONFIG="$mlocal_cfg" -- fleet-sweep.sh --repo "$srepo" --tower-id "$owner" \
    >"$tmp/out" 2>"$tmp/err" || st=$?
  out=$(cat "$tmp/out")
  [ "$st" = 0 ] || fail "s1 ($mode): the sweep exited $st ($(cat "$tmp/err"))"
  # The knob was read: terminate is honored only as far as the sweep allows,
  # and says so, while observe is silent about it.
  if [ "$mode" = terminate ]; then
    grep -q 'fleet_sweep_reap: terminate' "$tmp/err" || fail "s1 (terminate): the sweep never read the terminate knob"
  fi
  [ "$(rows "$h" w-s1 | grep -c .)" = 1 ] || fail "s1 ($mode): the sweep did not heal the missing record"
  printf '%s\n' "$out" | grep -q "^registry${tab}heal${tab}w-s1${tab}" \
    || fail "s1 ($mode): the sweep did not report the heal: $out"
  printf '%s\n' "$out" | grep -q "^registry${tab}retire${tab}w-s1-dead${tab}" \
    || fail "s1 ($mode): the sweep did not retire the dead worker's record: $out"
  [ "$(audit_count "$h" heal)" = 1 ] || fail "s1 ($mode): the sweep's heal was not audited"
  [ "$(audit_count "$h" retire)" = 1 ] || fail "s1 ($mode): the sweep's retirement was not audited"
done
rm -f "$mlocal_cfg"
h=$(home s1-paused)
mkdir -p "$h/dispatch-markers"
printf 'w-s1\tspec-s:1\t%s\theadless-oneshot\t-\t-\n' "$owner" >"$h/dispatch-markers/w-s1"
printf 'fleet_daemon_pause: true\n' >"$mlocal_cfg"
st=0
at "$h" "$S" PLANWRIGHT_LOCAL_CONFIG="$mlocal_cfg" -- fleet-sweep.sh --repo "$srepo" --tower-id "$owner" \
  >/dev/null 2>&1 || st=$?
[ "$st" = 4 ] || fail "s1: a paused sweep exited $st"
[ -z "$(registry "$h")" ] || fail "s1: the kill-switch did not pause the reconcile"
st=0
at "$h" "$S" PLANWRIGHT_LOCAL_CONFIG="$mlocal_cfg" -- fleet-registry-reconcile.sh >/dev/null 2>&1 || st=$?
[ "$st" = 4 ] || fail "s1: a paused standalone reconcile exited $st"
[ -z "$(registry "$h")" ] || fail "s1: the kill-switch did not pause a standalone reconcile"
rm -f "$mlocal_cfg"
ok s1 "the sweep heals and audits in either reap mode, and the kill-switch pauses the reconcile"

# ===========================================================================
# s2 — a checkout the sweep cannot enter for the reconcile is reported as
#      that, not as a reconcile failure. The reap pass, which runs just before,
#      takes the checkout's search permission away through a stub detector.
# ===========================================================================
nocd="$tmp/nocd-tree"
mkdir -p "$nocd"
cp -R "$S" "$nocd/"
srepo2="$tmp/sweep-repo-2"
cp -R "$srepo" "$srepo2"
cat >"$nocd/scripts/fleet-stuck-detector.sh" <<STUB
#!/bin/sh
chmod 000 "$srepo2"
exit 0
STUB
chmod +x "$nocd/scripts/fleet-stuck-detector.sh"
h=$(home s2)
st=0
at "$h" "$nocd/scripts" -- fleet-sweep.sh --repo "$srepo2" --tower-id "$owner" >"$tmp/out" 2>"$tmp/err" || st=$?
chmod 755 "$srepo2"
out=$(cat "$tmp/out")
printf '%s\n' "$out" | grep -q "^registry${tab}failed${tab}no-checkout$" \
  || fail "s2: an unenterable checkout was not reported as such: $out"
grep -q 'could not enter the checkout' "$tmp/err" || fail "s2: the warning does not say the checkout could not be entered: $(cat "$tmp/err")"
ok s2 "a checkout the reconcile cannot enter is reported as that, not as a reconcile failure"

# ===========================================================================
# w1 — no seam still says no reconcile exists.
# ===========================================================================
hits=$(grep -rniE 'no reconcile exists|nothing reconciles (it|that record)|no reconcile (exists )?(yet|to add)|not yet self-healing' \
  "$REPO_ROOT/scripts" "$REPO_ROOT/docs" "$REPO_ROOT/doctrine" 2>/dev/null || :)
[ -z "$hits" ] || fail "w1: a seam or doc still says no reconcile exists: $hits"
ok w1 "no seam or doc still says no reconcile exists"

[ "$rc" = 0 ] || {
  echo "$rc assertion(s) failed" >&2
  exit 1
}
