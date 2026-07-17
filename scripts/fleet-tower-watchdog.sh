#!/bin/sh
# fleet-tower-watchdog.sh — the external, cron-scheduled unattended-tower
# liveness check (Task 3: D-4, D-20, D-21; REQ-A1.5, REQ-A1.7, REQ-A1.9,
# REQ-G1.3, REQ-G1.4).
#
# THE DEAD-MAN'S-SWITCH SHAPE (D-4). The outermost liveness check is a dumb,
# external, deterministic script — never another Claude Code tower watching
# the tower (unbounded regress), and never an LLM decision (the
# no-LLM-daemon-mechanics floor, D-18/REQ-G1.2). An operator schedules it
# from cron/launchd per supervised spec; each invocation is ONE atomic tick
# that either does nothing or performs exactly one recorded action.
#
# ONE TICK, in order — the first outcome wins (printed on stdout):
#   paused             the fleet_daemon_pause kill-switch is set (D-15)
#   no-marker          no tower marker for the spec: nothing is supervised
#   not-unattended     an interactively-led tower is the signpost's domain
#                      (REQ-A1.6) — the watchdog NEVER relaunches it
#   ambiguous-marker   the marker fails to parse (mode/pid): risk row 7 —
#                      the mode record is itself under the REQ-A1.7
#                      fail-closed posture, so NEITHER recovery path acts;
#                      a decision-queue entry asks the human to repair it
#   alive              the tower demonstrably lives (any backoff state is
#                      healed: a live tower re-arms a disabled watchdog)
#   unknown            lost observability — refuse to act (REQ-A1.7)
#   disabled           the REQ-A1.9 consecutive-failure threshold tripped;
#                      relaunching stays off until a human intervenes (the
#                      tower being observed alive again is that evidence)
#   no-ready-work      /orchestrate's own selector reports nothing ready —
#                      REQ-A1.5 relaunches only when ready work exists
#   ready-check-error  the selector failed: fail closed, no relaunch
#   backoff-wait       inside the escalating relaunch-delay window
#   lock-busy          another actor holds the per-spec advisory lock —
#                      overlapping cron ticks serialize here (risk row 1)
#   relaunched         a fresh, memoryless tower was launched
#   relaunch-failed    the launch attempt failed (counts toward backoff)
#   backoff-corrupt    the persisted backoff record fails to parse: recovery
#                      is halted until it is repaired, so unlike every other
#                      outcome this one exits 2 (a scheduler must see it)
#
# READY WORK is resolved by CALLING THROUGH to /orchestrate's own ready-task
# selector (orchestrate-select.sh), never by re-deriving readiness from
# tasks.md's committed shape (risk row 4) — the selection policy stays in
# one place and this check survives tasks.md format migrations.
#
# THE RELAUNCH is the continue-as-new auto-heal rebuild: a fresh tower
# seeded from durable disk state alone (nothing in this watchdog's memory is
# passed along — its only inputs to the launcher are the spec dir and the
# derived session name). It lands in its OWN tmux session
# (`planwright-tower-<spec>`, D-21/REQ-G1.4), started detached at the
# checkout root through fleet-dispatch-env.sh (D-10), never as a window
# inside a pre-existing session an operator may be using.
#
# CONCURRENCY (risk rows 1 and 6; D-20/REQ-G1.3). Two cron ticks close
# together must not both relaunch: every state write (backoff record,
# disable flip, marker re-record) and the launch itself happen only under
# the EXISTING per-spec advisory lock (orchestrate-lock.sh — no new lock
# primitive). Under the lock the tick re-reads BOTH records fresh — the
# backoff (so a sibling's increment is never overwritten) and the MARKER
# (so a sibling's relaunch, which re-points the marker at a new pid, is
# seen) — recomputes the clock, and re-verifies death against the marker's
# CURRENT pid before acting. A tower that came alive, or was replaced,
# between the first observation and the lock is left alone; a busy lock is
# a clean no-op tick. A crash between the launch and the marker/backoff
# writes can still leave a stale marker (the writes are not transactional):
# the healing path is the relaunched tower's own marker self-record at
# watch-loop start, with the session-collision refusal and the backoff
# delay window bounding the damage meanwhile.
#
# BACKOFF (REQ-A1.9, risk row 32). Consecutive failed relaunches wait
# base*2^(n-1) seconds between attempts and disable at the configured
# threshold, with a decision-queue entry recording the disable. The two
# knobs (`tower_relaunch_backoff_base`, `tower_relaunch_disable_threshold`)
# are the TOWER's own, resolved through the shared knob resolver
# (D-22/REQ-G1.5) — structurally identical to the worker crash-loop
# schedule (REQ-A1.4) but sharing no state or config with it (many workers,
# one tower per spec: a shared counter would cross-contaminate).
# The backoff record lives beside the marker
# (`<fleet-home>/towers/<spec>.backoff`:
# `<count>\t<last-attempt-epoch>\t<disabled>`); the spec-id grammar admits
# no dot, so the `.backoff` suffix can never collide with a marker name.
#
# AUDIT (D-16/REQ-F1.4). Every ACTION — relaunch, relaunch-failed, disable,
# reset-backoff — logs through fleet-audit.sh; routine classifications
# (alive/no-marker/backoff-wait ticks) deliberately do not (risk row 31:
# the trail records actions, not high-frequency status noise).
#
# Env seams (operator/test knobs, trusted verbatim like
# PLANWRIGHT_FLEET_STATE_DIR — they run with the caller's own authority):
#   PLANWRIGHT_TOWER_READY_CHECK   ready-work command, run as: $cmd <spec-dir>
#                                  (default: scripts/orchestrate-select.sh)
#   PLANWRIGHT_TOWER_EVIDENCE_CMD  death-evidence command, run as:
#                                  $cmd process <pid> (default:
#                                  scripts/fleet-death-evidence.sh)
#   PLANWRIGHT_TOWER_LAUNCHER      launcher command, run as: $cmd <spec-dir>
#                                  <session-name>; must print the fresh
#                                  tower's pid, and must itself refuse to
#                                  start a second tower when a prior launch
#                                  may still be live (the default launcher's
#                                  session-name collision refusal is that
#                                  guard; a custom launcher owns providing
#                                  an equivalent)
#
# Usage: fleet-tower-watchdog.sh <spec-dir>
# Exit codes: 0 tick completed (any outcome above except backoff-corrupt);
#   2 usage / refused hostile input / lock or filesystem error / corrupt
#   backoff record / a failed escalation write (fail closed, visibly); 4/5
#   propagate a config-resolver hard-fail (malformed team-shared overlay /
#   broken install) so a scheduler surfaces it as a real failure.
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling): `date
# +%s`, mktemp, tmux for the default launcher. No eval, no jq (REQ-K1.5).
# All input is data. Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

usage() {
  echo "usage: fleet-tower-watchdog.sh <spec-dir>" >&2
}

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

# --- spec-dir containment (the orchestrate-lock.sh discipline) ---------------
# Canonicalize, then validate the basename against the anchored identifier
# grammar and require the parent to be a `specs` dir — a hostile path never
# reaches a lock, a marker name, or a tmux session name.
spec_dir_raw=$1
spec_dir=$(cd "$spec_dir_raw" 2>/dev/null && pwd -P) || {
  echo "fleet-tower-watchdog: refusing spec dir (not an existing directory)" >&2
  exit 2
}
spec=$(basename "$spec_dir")
case "$spec" in
  "" | -* | *[!a-z0-9-]*)
    echo "fleet-tower-watchdog: refusing malformed spec id '$(sanitize_printable "$spec" "(unprintable)")'" >&2
    exit 2
    ;;
esac
if [ "${#spec}" -gt 64 ]; then
  echo "fleet-tower-watchdog: refusing over-length spec id" >&2
  exit 2
fi
specs_parent=$(dirname "$spec_dir")
case "$specs_parent" in
  */specs) ;;
  *)
    echo "fleet-tower-watchdog: refusing spec dir outside a specs/ parent" >&2
    exit 2
    ;;
esac
checkout=$(dirname "$specs_parent")
session_name="planwright-tower-$spec"

FTM="$script_dir/fleet-tower-marker.sh"
FAU="$script_dir/fleet-audit.sh"
FAT="$script_dir/fleet-attention.sh"
LOCK="$script_dir/orchestrate-lock.sh"
ready_cmd="${PLANWRIGHT_TOWER_READY_CHECK:-$script_dir/orchestrate-select.sh}"
evidence_cmd="${PLANWRIGHT_TOWER_EVIDENCE_CMD:-$script_dir/fleet-death-evidence.sh}"
launcher_cmd="${PLANWRIGHT_TOWER_LAUNCHER:-}"

outcome() {
  printf '%s\n' "$1"
  exit 0
}

# --- the operator kill-switch gates ENTRY (D-15) ------------------------------
gate_rc=0
"$script_dir/fleet-daemon-gate.sh" tower-watchdog || gate_rc=$?
case $gate_rc in
  0) ;;
  1) outcome paused ;;
  *) exit "$gate_rc" ;;
esac

# --- the tower's own backoff knobs (D-22, risk row 32) ------------------------
knob_rc=0
base=$("$script_dir/resolve-config-knob.sh" --key tower_relaunch_backoff_base \
  --type posint --fallback 60) || knob_rc=$?
[ "$knob_rc" -eq 0 ] || exit "$knob_rc"
threshold=$("$script_dir/resolve-config-knob.sh" --key tower_relaunch_disable_threshold \
  --type posint --fallback 3) || knob_rc=$?
[ "$knob_rc" -eq 0 ] || exit "$knob_rc"

# --- the marker is the mode gate (risk row 7) ---------------------------------
TAB=$(printf '\t')

escalate_ambiguous() {
  # An unrepaired ambiguous marker blocks BOTH recovery paths, so the human
  # breadcrumb is load-bearing: a failed decision-queue write is surfaced as
  # a hard tick failure (the helper's own stderr names the cause), never
  # swallowed — the caller contract every fleet daemon mechanism holds.
  "$FAT" decide "tower-watchdog:$spec" "$spec" \
    "Tower marker for spec '$spec' is ambiguous (unparseable mode or pid); crash recovery is refusing both the relaunch and signpost paths until it is repaired" \
    "repair-marker" \
    "repair-marker | clear-marker (scripts/fleet-tower-marker.sh clear $spec)" \
    high >/dev/null || {
    echo "fleet-tower-watchdog: could not queue the ambiguous-marker decision — failing the tick so the broken queue is visible" >&2
    printf 'ambiguous-marker\n'
    exit 2
  }
  outcome ambiguous-marker
}

# read_marker_state: (re)read and gate the marker. Sets m_mode/m_pid, or
# exits through the mode gate's terminal outcomes. Called once before the
# lock and again UNDER the lock (a sibling tick's relaunch re-points the
# marker at a new pid; acting on the pre-lock parse would re-verify a pid
# that can no longer come back to life — risk rows 1 and 6).
read_marker_state() {
  rms_rc=0
  rms_row=$("$FTM" read "$spec") || rms_rc=$?
  case $rms_rc in
    0) ;;
    1) outcome no-marker ;;
    *) exit 2 ;;
  esac
  rms_old_ifs=$IFS
  IFS=$TAB
  # shellcheck disable=SC2086
  set -- $rms_row
  IFS=$rms_old_ifs
  m_mode="${2:-}"
  m_pid="${3:-}"
  if [ "$#" -ne 7 ]; then
    escalate_ambiguous
  fi
  case "$m_pid" in
    "" | *[!0-9]* | 0*) escalate_ambiguous ;;
  esac
  case "$m_mode" in
    unattended) ;;
    interactive) outcome not-unattended ;;
    *) escalate_ambiguous ;;
  esac
}

read_marker_state

# --- backoff record helpers ---------------------------------------------------
towers_dir=""
resolve_towers_dir() {
  [ -n "$towers_dir" ] && return 0
  rt_root=$("$script_dir/fleet-state.sh" root) || return 1
  towers_dir="$rt_root/towers"
}
backoff_count=0
backoff_last=0
backoff_disabled=0
# Returns 0 (record read or absent), 1 (corrupt record), 2 (fleet home
# unresolvable) — two different failures that must not share a message.
read_backoff() {
  backoff_count=0
  backoff_last=0
  backoff_disabled=0
  resolve_towers_dir || return 2
  rb_file="$towers_dir/$spec.backoff"
  [ -f "$rb_file" ] || return 0
  # A record removed mid-read is the absent case (a human deleting the
  # backoff record IS the documented repair), never corruption — the same
  # cleared-mid-read distinction the marker reader draws.
  if ! rb_row=$(cat "$rb_file" 2>/dev/null); then
    [ -f "$rb_file" ] || return 0
    return 1
  fi
  rb_old_ifs=$IFS
  IFS=$TAB
  # shellcheck disable=SC2086
  set -- $rb_row
  IFS=$rb_old_ifs
  # Strict field count, mirroring the marker parser's `[ "$#" -ne 7 ]` gate: a
  # row with trailing junk (whose first three fields happen to parse) is
  # corrupt, not silently accepted — recovery must never run off it.
  [ "$#" -eq 3 ] || return 1
  rb_c="${1:-}"
  rb_l="${2:-}"
  rb_d="${3:-}"
  case "$rb_c" in "" | *[!0-9]*) return 1 ;; esac
  case "$rb_l" in "" | *[!0-9]*) return 1 ;; esac
  case "$rb_d" in 0 | 1) ;; *) return 1 ;; esac
  backoff_count=$rb_c
  backoff_last=$rb_l
  backoff_disabled=$rb_d
}
write_backoff() {
  # write_backoff <count> <last> <disabled> — temp+rename; callers hold the
  # per-spec advisory lock, the single-writer serialization for this record
  # (risk row 6: the read-modify-write is atomic under it). PENDING_TMP is
  # cleaned by the EXIT trap so a signal mid-write leaves no temp residue.
  resolve_towers_dir || return 1
  mkdir -p "$towers_dir" 2>/dev/null || return 1
  wb_tmp=$(mktemp "$towers_dir/.backoff.XXXXXX") || return 1
  PENDING_TMP=$wb_tmp
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >"$wb_tmp" || {
    rm -f "$wb_tmp"
    PENDING_TMP=""
    return 1
  }
  mv -f "$wb_tmp" "$towers_dir/$spec.backoff" 2>/dev/null || {
    rm -f "$wb_tmp"
    PENDING_TMP=""
    return 1
  }
  PENDING_TMP=""
}
# The escalating delay after n consecutive failures: base * 2^(n-1), capped
# after 29 doublings (<= base * 2^29 — an overflow guard far past any real
# schedule; the count is bounded by the disable threshold anyway).
delay_for() {
  df_n=$1
  df_delay=$base
  df_i=1
  while [ "$df_i" -lt "$df_n" ] && [ "$df_i" -lt 30 ]; do
    df_delay=$((df_delay * 2))
    df_i=$((df_i + 1))
  done
  printf '%s' "$df_delay"
}

# A corrupt persistent record halts crash recovery entirely, and an
# unresolvable fleet home means nothing about this tick can be trusted —
# both fail closed with exit 2 so a scheduler alerting on non-zero exits
# actually notices (a silent 0 here would hide a dead fleet).
read_backoff_or_die() {
  rbd_rc=0
  read_backoff || rbd_rc=$?
  case $rbd_rc in
    0) ;;
    1)
      echo "fleet-tower-watchdog: backoff record for '$spec' is corrupt — refusing to act; repair or remove it" >&2
      printf 'backoff-corrupt\n'
      exit 2
      ;;
    *)
      echo "fleet-tower-watchdog: cannot resolve the fleet home for the backoff record — refusing to act" >&2
      exit 2
      ;;
  esac
}

now_epoch() {
  ne_v=$(date +%s)
  case $ne_v in
    "" | *[!0-9]*) return 1 ;;
    *) printf '%s' "$ne_v" ;;
  esac
}

# --- per-spec advisory lock plumbing (D-20) -----------------------------------
HOLD_LOCK=0
PENDING_TMP=""
trap 'release_lock; [ -z "$PENDING_TMP" ] || rm -f "$PENDING_TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
release_lock() {
  if [ "$HOLD_LOCK" = 1 ]; then
    "$LOCK" release "$spec_dir" >/dev/null 2>&1 || true
    HOLD_LOCK=0
  fi
}
acquire_lock_or_busy() {
  al_rc=0
  "$LOCK" acquire "$spec_dir" >/dev/null 2>&1 || al_rc=$?
  case $al_rc in
    0)
      HOLD_LOCK=1
      return 0
      ;;
    1) outcome lock-busy ;;
    *)
      echo "fleet-tower-watchdog: cannot acquire the per-spec lock (exit $al_rc)" >&2
      exit 2
      ;;
  esac
}

reset_backoff_if_armed() {
  # A demonstrably-alive tower is the positive evidence that heals backoff
  # state — including a disable, whose re-enable path is exactly "a human
  # intervened and the tower runs again" (REQ-A1.9).
  if [ "$backoff_count" -gt 0 ] || [ "$backoff_disabled" = 1 ]; then
    acquire_lock_or_busy
    ev2=0
    "$evidence_cmd" process "$m_pid" >/dev/null 2>&1 || ev2=$?
    if [ "$ev2" -ne 1 ]; then
      # The locked re-check no longer sees the tower alive: this tick's
      # observation is ambiguous, so report that rather than an `alive` the
      # measurement just contradicted. The next tick resolves it.
      outcome unknown
    fi
    write_backoff 0 0 0 || {
      echo "fleet-tower-watchdog: cannot reset the backoff record" >&2
      exit 2
    }
    "$FAU" record tower-watchdog reset-backoff "tower-alive" \
      "tower for spec '$spec' observed alive; backoff state cleared and the watchdog re-armed" \
      || exit 2
    release_lock
  fi
  outcome alive
}

# --- first death observation --------------------------------------------------
read_backoff_or_die
ev_rc=0
"$evidence_cmd" process "$m_pid" >/dev/null 2>&1 || ev_rc=$?
case $ev_rc in
  0) ;; # positive evidence of death — continue
  1) reset_backoff_if_armed ;;
  *) outcome unknown ;;
esac

if [ "$backoff_disabled" = 1 ]; then
  outcome disabled
fi

# --- ready work, by call-through (risk row 4) ---------------------------------
ready_rc=0
"$ready_cmd" "$spec_dir" >/dev/null 2>&1 || ready_rc=$?
case $ready_rc in
  0) ;;
  1) outcome no-ready-work ;;
  *)
    echo "fleet-tower-watchdog: ready-task selection failed (exit $ready_rc) — refusing to relaunch" >&2
    outcome ready-check-error
    ;;
esac

# Threshold before delay: once the consecutive-failure threshold is reached
# the disable must land on the next tick, not after one more backoff window.
now=$(now_epoch) || {
  echo "fleet-tower-watchdog: cannot read the clock" >&2
  exit 2
}
if [ "$backoff_count" -lt "$threshold" ] && [ "$backoff_count" -gt 0 ]; then
  need=$(delay_for "$backoff_count")
  if [ $((now - backoff_last)) -lt "$need" ]; then
    outcome backoff-wait
  fi
fi

# --- act, under the existing per-spec advisory lock (D-20, risk rows 1/6) -----
acquire_lock_or_busy

# Re-read BOTH records fresh under the lock. The backoff re-read makes the
# read-modify-write atomic (a concurrent tick's increment is never
# overwritten, risk row 6). The marker re-read is what makes the death
# re-verification real (risk row 1): a sibling tick's relaunch re-points
# the marker at a new pid, and a pid that already returned positive death
# can never come back to life — re-verifying the pre-lock pid would be
# structurally incapable of noticing the tower that now exists.
read_backoff_or_die
if [ "$backoff_disabled" = 1 ]; then
  outcome disabled
fi
read_marker_state

ev_rc=0
"$evidence_cmd" process "$m_pid" >/dev/null 2>&1 || ev_rc=$?
case $ev_rc in
  0) ;;
  1)
    if [ "$backoff_count" -gt 0 ] || [ "$backoff_disabled" = 1 ]; then
      write_backoff 0 0 0 || {
        echo "fleet-tower-watchdog: cannot reset the backoff record" >&2
        exit 2
      }
      "$FAU" record tower-watchdog reset-backoff "tower-alive" \
        "tower for spec '$spec' observed alive on the locked re-check; backoff state cleared" \
        || exit 2
    fi
    outcome alive
    ;;
  *) outcome unknown ;;
esac

# The clock is re-read under the lock too: the pre-lock stamp could predate
# a sibling's entire critical section, making "elapsed since last attempt"
# negative or stale against the freshly re-read backoff_last.
now=$(now_epoch) || {
  echo "fleet-tower-watchdog: cannot read the clock" >&2
  exit 2
}

if [ "$backoff_count" -ge "$threshold" ]; then
  # The decision-queue breadcrumb lands BEFORE the disable flag persists: a
  # disabled watchdog whose only re-enable path is human intervention must
  # never exist without the entry that asks for that intervention. If the
  # decide write fails, the tick fails visibly and the next tick retries
  # both (the decide upsert is idempotent per worker key).
  "$FAT" decide "tower-watchdog:$spec" "$spec" \
    "Tower for spec '$spec' was relaunched $backoff_count consecutive times without surviving; the watchdog disabled itself (REQ-A1.9). Investigate, then relaunch manually: an observed-alive tower re-arms the watchdog" \
    "leave-disabled" \
    "investigate-and-relaunch | leave-disabled" \
    high >/dev/null || {
    echo "fleet-tower-watchdog: could not queue the disable decision — leaving the watchdog armed so the next tick retries" >&2
    exit 2
  }
  write_backoff "$backoff_count" "$backoff_last" 1 || {
    echo "fleet-tower-watchdog: cannot persist the disable" >&2
    exit 2
  }
  "$FAU" record tower-watchdog disable "consecutive-failure-threshold" \
    "relaunch for spec '$spec' disabled after $backoff_count consecutive failures (threshold $threshold); decision queued" \
    || exit 2
  outcome disabled
fi
if [ "$backoff_count" -gt 0 ]; then
  need=$(delay_for "$backoff_count")
  if [ $((now - backoff_last)) -lt "$need" ]; then
    outcome backoff-wait
  fi
fi

# --- the launch ---------------------------------------------------------------
# Default launcher: a fresh DETACHED tmux session of its own (D-21/REQ-G1.4)
# named planwright-tower-<spec>, started at the checkout root, wrapped in
# fleet-dispatch-env.sh (D-10 ghost-text hardening), waking /orchestrate in
# unattended watch mode. Prints the fresh tower's pane pid. A session-name
# collision is a refusal, never a window into an existing session.
launch_default() {
  if ! command -v tmux >/dev/null 2>&1; then
    echo "fleet-tower-watchdog: tmux is unavailable for the default launcher" >&2
    return 1
  fi
  if tmux has-session -t "=$session_name" 2>/dev/null; then
    echo "fleet-tower-watchdog: tmux session '$session_name' already exists — refusing to reuse it" >&2
    return 1
  fi
  tmux new-session -d -s "$session_name" -c "$checkout" \
    "$script_dir/fleet-dispatch-env.sh" claude \
    "/orchestrate --watch --unattended specs/$spec" 2>/dev/null || {
    echo "fleet-tower-watchdog: tmux new-session failed" >&2
    return 1
  }
  ld_pid=$(tmux list-panes -t "=$session_name" -F '#{pane_pid}' 2>/dev/null | head -n 1)
  case "$ld_pid" in
    "" | *[!0-9]* | 0*)
      echo "fleet-tower-watchdog: cannot read the fresh tower's pane pid" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$ld_pid"
}

launch_rc=0
if [ -n "$launcher_cmd" ]; then
  new_pid=$("$launcher_cmd" "$spec_dir" "$session_name") || launch_rc=$?
else
  new_pid=$(launch_default) || launch_rc=$?
fi
case "$new_pid" in
  "" | *[!0-9]* | 0*) launch_rc=1 ;;
esac
attempt=$((backoff_count + 1))

if [ "$launch_rc" -ne 0 ]; then
  write_backoff "$attempt" "$now" 0 || {
    echo "fleet-tower-watchdog: cannot persist the backoff record" >&2
    exit 2
  }
  "$FAU" record tower-watchdog relaunch-failed "tower-dead-ready-work" \
    "relaunch attempt $attempt for spec '$spec' failed to start a fresh tower" \
    || exit 2
  outcome relaunch-failed
fi

"$FTM" record "$spec" --mode unattended --pid "$new_pid" \
  --checkout "$checkout" --tmux-session "$session_name" || {
  echo "fleet-tower-watchdog: relaunched but could not re-record the marker" >&2
  exit 2
}
write_backoff "$attempt" "$now" 0 || {
  echo "fleet-tower-watchdog: cannot persist the backoff record" >&2
  exit 2
}
"$FAU" record tower-watchdog relaunch "tower-dead-ready-work" \
  "relaunched a fresh memoryless tower for spec '$spec' (attempt $attempt) into session '$session_name' from durable disk state" \
  || exit 2
outcome relaunched
