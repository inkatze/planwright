#!/bin/sh
# fleet-usage-gate.sh — the proactive, shared-aware `/usage` budget gate and
# its restriction ladder (fleet-autonomy Task 9; D-23, D-28, D-12; REQ-E1.5,
# REQ-E1.6, REQ-E1.7, REQ-F1.3, REQ-F1.4, REQ-G1.2, REQ-G1.3, REQ-G1.5).
#
# Task 7's fleet-throttle.sh is REACTIVE — it pauses only once Claude Code
# renders its native rate-limit wall. This gate is PROACTIVE: it reads real
# account-level usage by capturing Claude Code's own `/usage` render, parses
# BOTH windows it shows — the session (~5-hour rolling) and the weekly — and
# maps each window's consumed percentage to a rung on a single monotone
# restriction ladder, gating dispatch ahead of the wall. Because `/usage` is
# account-global it is inherently shared-aware (it already reflects every
# concurrent tower, all workers, and unrelated same-account work), so no
# per-orchestrator reservation is kept — the shared figure is ground truth
# (D-23). The reactive throttle is RETAINED as the hard backstop the gate
# degrades to (REQ-E1.7): the common proactive range can at worst mis-throttle,
# never fully halt the fleet, so a best-effort read is safe to depend on.
#
# THE LADDER (REQ-E1.6). Rungs, lightest to heaviest:
#   normal -> downshift -> reduce-concurrency -> defer-heavy -> defer-all
# Each window carries overlay-resolved thresholds mapping its percentage to a
# target rung (deterministic `>=` comparison, REQ-G1.2 — never an LLM call).
# The EFFECTIVE rung is the MORE RESTRICTIVE of the two windows' targets. The
# shipped default is consequence-aware: the SESSION window is CAPPED at
# `defer-heavy` (a session spike never proactively halts the fleet; the
# reactive backstop catches a genuine session wall), while the WEEKLY window
# MAY reach `defer-all` (hitting it can halt work for days). A rung transition
# is a throttle-family daemon action: kill-switch-pausable (fleet-daemon-gate.sh,
# D-15/REQ-F1.3) and audited (fleet-audit.sh, D-16/REQ-F1.4). It introduces no
# new daemon-action TYPE and no new stat type — it reuses the throttle-family
# surfaces (fleet-stats renders the current rung on the existing throttle line).
# The `downshift`/`reduce-concurrency` rung VALUES (which model/effort/
# concurrency they map to) are Task 10's; this task ships the ladder mechanism,
# the threshold->rung mapping, and the `defer-heavy`/`defer-all` admission gate.
#
# STATE IS DERIVED, NOT STORED (D-28, REQ-E1.6). The ladder's live state — the
# current rung and the last-transition time — is DERIVED from the shared audit
# trail (the last usage-gate row's action IS the current rung), never held in
# tower memory or a separate rung-state file. A memoryless, cron-relaunched
# tower recovers the fleet rung by reading the trail; transitions are taken
# under `orchestration-concurrency`'s existing advisory lock (via fleet-audit /
# fleet-state, REQ-G1.3 — no second lock primitive) and logged EDGE-TRIGGERED
# (only on an actual rung change, never per evaluation).
#
# THE SIGNAL (REQ-E1.5). `capture` reads a `/usage` render on stdin (the live
# throwaway-pane scrape is the version-fragile `[manual]` half, D-23 — a frozen
# CI fixture cannot catch a live format change), strips control/escape bytes
# (untrusted terminal output; security-posture echo-discipline), parses each
# window BY LABEL (never by position), applies a plausibility check (0-100 and
# the expected render shape), and caches the extracted signal per-tower with a
# read timestamp. A window that cannot be captured, parsed, is implausible, or
# whose cache is staler than the TTL is reported UNAVAILABLE — never guessed.
# The cache is per-tower and LOCAL (default `<fleet-home>/usage/`, overridable
# via $PLANWRIGHT_USAGE_SIGNAL_DIR): each tower reads independently, the signal
# is point-in-time and advisory, so the cache needs NO cross-tower lock — the
# fleet-coherent state that DOES need serialization is the audit-derived rung.
# The gate NEVER invokes an LLM/API (REQ-G1.2): the whole path is sh/sed/awk.
#
# DEGRADATION (REQ-E1.5). When NO window signal is available, governance falls
# back to the reactive backstop: `evaluate` reports unavailable and takes NO
# proactive rung transition (no block, no guessed number). Sustained
# unavailability — the signal (BOTH windows) unavailable across an
# overlay-configurable number of consecutive `evaluate` cadences — raises a
# REQUIRED operator surface (a warning escalating to an Awaiting-input hold via
# fleet-attention.sh), so a permanently broken `/usage` parse that loses both
# windows (the D-23 version-drift fragility) is never silent. A partial break —
# one window still parsing while the other is lost — is NOT a silent gap: the
# surviving window still governs the ladder, and the `[manual]` `/usage` drift
# check (REQ-E1.5) owns catching a live-format change that breaks one window.
# The consecutive-unavailable counter is a per-tower LOCAL, advisory scalar
# (`evaluate` is the per-cadence daemon action, so consecutive invocations are
# consecutive cadences); it needs no lock because the fleet-coherent state is
# the audit-derived rung, not this counter. An outstanding hold is cleared when
# the kill-switch is engaged (the operator has assumed control; the hold no
# longer applies).
#
# Usage:
#   fleet-usage-gate.sh capture
#       Read a captured /usage render on stdin, parse both windows, cache the
#       signal, and print it as two TAB-separated lines:
#         session<TAB><percent|unavailable><TAB><reset-text|->
#         weekly<TAB><percent|unavailable><TAB><reset-text|->
#       The reset field is the window's reset-time text where the render shows
#       it (informational only; the gate acts on the percentage and never models
#       reset timing). Exit 0 (a per-window unavailable is a normal state, not an
#       error); exit 2 on a usage or I/O error.
#   fleet-usage-gate.sh evaluate
#       The proactive gate. Read the cached signal (absent or stale-beyond-TTL
#       => unavailable), compute the target rung (per-window thresholds via the
#       overlay, more-restrictive-wins, session capped at defer-heavy), derive
#       the current rung from the audit trail, and — on a change — record an
#       edge-triggered transition under the advisory lock. Prints
#       `rung<TAB><name><TAB>since<TAB><last-transition-epoch><TAB>session<TAB><s><TAB>weekly<TAB><w>`
#       (the `since` epoch, derived from the trail, is empty when no transition
#       has been recorded). Exit 0; exit 1 when the kill-switch pauses the gate;
#       exit 2/4/5 on error (see below).
#   fleet-usage-gate.sh rung
#       Print the current rung derived from the audit trail (a pure read: no
#       gate, no lock, no transition). `normal` when the trail has no rows.
#   fleet-usage-gate.sh admit <model>
#       Given the derived current rung, answer whether a unit running <model>
#       (a Claude Code alias: fable opus sonnet haiku) may dispatch. Heavy tiers
#       (opus, fable) are withheld at defer-heavy; every tier is withheld at
#       defer-all; lighter rungs admit all. Exit 0 admit, exit 1 withheld.
#
# Exit codes: 0 success; 1 kill-switch short-circuit (evaluate) or withheld
#   (admit); 2 usage error, corrupt state, refused input, or a filesystem/lock
#   error (fail closed) — this also covers a missing/unrunnable fleet-state.sh,
#   fleet-audit.sh, or fleet-attention.sh helper, whose failure surfaces through
#   its invocation's non-zero return and fails closed here (the same posture the
#   sibling fleet scripts carry; they are not pre-checked); 4 malformed
#   threshold/cadence configuration (a non-monotonic or out-of-range per-window
#   threshold set from ANY layer, or a read cadence >= the TTL) or a resolver
#   hard-fail on a team-shared value — the ladder is fail-closed, never run under
#   invalid configuration; 5 broken install, raised by the up-front executability
#   pre-checks on the two helpers this script calls a bare success/1/4/5 contract
#   on — the daemon gate (fleet-daemon-gate.sh) and the shared config resolver
#   (resolve-config-knob.sh) — or a malformed/unresolvable core default. The
#   sourced echo-safety.sh is a required sibling: under the /bin/sh target a
#   failed `.` of a missing special-builtin file aborts the shell immediately
#   (it never proceeds past the source), matching the whole fleet script family.
#   Never fails opaquely.
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling): awk,
# `date +%s`, a fractional sleep for the lock retry. No eval, no jq (REQ-K1.5).
# All input is data. Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

FS="$script_dir/fleet-state.sh"
GATE="$script_dir/fleet-daemon-gate.sh"
AUDIT="$script_dir/fleet-audit.sh"
ATTN="$script_dir/fleet-attention.sh"
RESOLVER="$script_dir/resolve-config-knob.sh"

MECHANISM=usage-gate
TAB=$(printf '\t')

# The ladder rungs, lightest to heaviest. The index is the restriction order:
# a higher index is more restrictive, so "more restrictive wins" is a numeric
# max and the session cap is a numeric clamp.
#   normal=0 downshift=1 reduce-concurrency=2 defer-heavy=3 defer-all=4
SESSION_CAP=3 # the session window never selects above defer-heavy (REQ-E1.6).

usage() {
  echo "usage: fleet-usage-gate.sh capture | evaluate | rung | admit <model>" >&2
}

# rung_name <index>: the ladder rung name for an index, for composing the
# transition decision from the numeric window comparisons below.
rung_name() {
  case $1 in
    0) printf normal ;;
    1) printf downshift ;;
    2) printf reduce-concurrency ;;
    3) printf defer-heavy ;;
    4) printf defer-all ;;
    *) printf '' ;;
  esac
}

now_epoch() {
  ne_v=$(date +%s)
  case $ne_v in
    "" | *[!0-9]*) return 1 ;;
  esac
  printf '%s' "$ne_v"
}

resolve_home() {
  rh_root=$("$FS" root) || return 2
  printf '%s' "$rh_root"
}

# The shared cross-spec advisory lock (fleet-state.sh — REQ-G1.3, no second
# lock primitive). The gate holds it across its derive-then-record critical
# section so concurrent towers cannot both record the same transition; the
# nested fleet-audit record runs with PLANWRIGHT_FLEET_LOCK_HELD set to this
# mechanism name (usage-gate) to skip the re-acquire that would deadlock on this
# same non-reentrant primitive — scoped to the mechanism so a stray env value
# never disables locking for an unrelated caller (fleet-audit header).
HOLD_LOCK=0
CUR_TMP=""
# Release the lock AND reap any in-flight cache write temp on ANY exit, signals
# included (the fleet-throttle.sh trap discipline): a SIGINT/SIGTERM
# mid-critical-section must not leave the shared cross-spec lock held until the
# stale-break threshold, nor litter the signal dir with a `.signal.XXXXXX`
# orphan. INT/TERM route through EXIT via explicit exits with the conventional
# codes. Inlined (not a named cleanup function) so the trap reference is visible
# to static analysis.
trap 'release_lock; [ -n "$CUR_TMP" ] && rm -f "$CUR_TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
acquire_lock() {
  al_tries=0
  while [ "$al_tries" -lt 1000 ]; do
    "$FS" lock >/dev/null 2>&1
    al_rc=$?
    case $al_rc in
      0)
        HOLD_LOCK=1
        return 0
        ;;
      1) ;; # a live holder has it — retry
      *)
        echo "fleet-usage-gate: cannot acquire the fleet lock (fleet-state exit $al_rc)" >&2
        return 2
        ;;
    esac
    al_tries=$((al_tries + 1))
    sleep 0.02
  done
  echo "fleet-usage-gate: gave up acquiring the fleet lock after contention" >&2
  return 2
}
release_lock() {
  if [ "$HOLD_LOCK" = 1 ]; then
    "$FS" unlock >/dev/null 2>&1 || true
    HOLD_LOCK=0
  fi
}

# signal_dir: the per-tower, local signal cache directory. Default under the
# cross-spec fleet home; $PLANWRIGHT_USAGE_SIGNAL_DIR isolates it per tower in a
# multi-tower deployment (each tower reads /usage independently — no shared
# cache file, no cross-tower write hazard; REQ-E1.5).
signal_dir() {
  if [ -n "${PLANWRIGHT_USAGE_SIGNAL_DIR:-}" ]; then
    printf '%s' "$PLANWRIGHT_USAGE_SIGNAL_DIR"
    return 0
  fi
  sd_root=$(resolve_home) || return 2
  printf '%s/usage' "$sd_root"
}

# resolve_posint <key> <fallback>: a bundle knob resolved through the shared
# four-layer resolver (D-22/REQ-G1.5). A resolver exit propagates verbatim
# (4 team-shared malformed, 5 broken install), so this gate honors the same
# by-layer policy `review_sequence` has, implemented once in the resolver.
resolve_posint() {
  if [ ! -x "$RESOLVER" ]; then
    echo "fleet-usage-gate: shared knob resolver '$RESOLVER' is missing or not executable — broken install" >&2
    exit 5
  fi
  rp_out=$("$RESOLVER" --key "$1" --type posint --fallback "$2") || exit $?
  printf '%s' "$rp_out"
}

# --- The /usage parser (capture) ------------------------------------------
#
# parse_usage: read the captured render on stdin, print two TAB-separated lines
# `session<TAB><pct><TAB><reset>` and `weekly<TAB><pct><TAB><reset>` where
# <pct> is a plausible 0-100 integer or the literal `unavailable`, and <reset>
# is the window's reset-time text where the render shows it, else `-` (captured
# for observability only; the gate acts on the percentage and NEVER models
# reset timing — REQ-E1.5). Control/escape bytes are stripped BEFORE parsing
# (a CSI sequence removed whole, then any residual non-print byte — the
# echo-discipline awk form), so a smuggled escape cannot survive into the
# output, the cache, or forge a value; the strip also removes any TAB, so the
# reset field can never tear the TAB-separated line.
#
# Each window is found BY LABEL, never by position: a single top-to-bottom pass
# tracks the most-recently-seen window label (`session` / `week`), and the first
# PLAUSIBLE (0-100) percentage AND the first reset phrase within a window's
# section are assigned to that window. "Most recent label owns the value" bounds
# each window to its own section — a percentage cannot bleed from one window into
# the other even when a label line carries no percentage of its own, and window
# ORDER does not matter. An implausible token (a garbled or decorative "999%") is
# skipped rather than locked in, so a stray leading token does not falsely mark a
# window unavailable when the real usage line follows. A window whose section has
# NO percentage, or whose only percentage is implausible, yields `unavailable` —
# no implausible value is ever recorded or acted on (REQ-E1.5).
parse_usage() {
  head -c 262144 | awk '
    BEGIN { TAB = sprintf("\t") }
    {
      line = $0
      # Remove whole ANSI CSI sequences (ESC [ ... final-byte), then strip any
      # residual non-printable byte (including TAB). A color code cannot leave a
      # bracket-number fragment that forges "NN%".
      gsub(/\033\[[0-9;?]*[ -\/]*[@-~]/, "", line)
      gsub(/[^[:print:]]/, "", line)
      n++
      lines[n] = line
      lower[n] = tolower(line)
    }
    END {
      cur = ""             # the most-recently-seen window: "s" | "w" | ""
      s_pct = -1; w_pct = -1   # -1 = no plausible value yet; else 0..100
      s_reset = ""; w_reset = ""
      for (i = 1; i <= n; i++) {
        # A line naming a window opens that window section. A legend line naming
        # both is transient: the real data label lines below re-open the correct
        # section, so the last label before a value owns it.
        if (index(lower[i], "session")) cur = "s"
        if (index(lower[i], "week")) cur = "w"
        if (cur == "") continue
        # Take the first PLAUSIBLE (0-100) percentage in a window section. An
        # implausible token (e.g. a garbled or decorative "999%") is skipped, not
        # locked in, so a stray leading token does not falsely mark the window
        # unavailable when the real usage line follows. A section whose only
        # percentage is implausible still yields unavailable (no plausible value
        # is ever recorded), so the REQ-E1.5 never-act-on-implausible rule holds.
        # The plausibility bound is the guard; a >100 number is never acted on.
        if (match(lines[i], /[0-9]+%/)) {
          num = substr(lines[i], RSTART, RLENGTH - 1) + 0
          if (num >= 0 && num <= 100) {
            if (cur == "s" && s_pct == -1) s_pct = num
            else if (cur == "w" && w_pct == -1) w_pct = num
          }
        }
        # The first reset phrase in a window section: informational only,
        # bounded to 100 chars, captured from the "reset" keyword to end of line.
        if (match(lower[i], /reset[a-z]*/)) {
          rt = substr(lines[i], RSTART, 100)
          if (cur == "s" && s_reset == "") s_reset = rt
          else if (cur == "w" && w_reset == "") w_reset = rt
        }
      }
      printf "session%s%s%s%s\n", TAB, (s_pct < 0 ? "unavailable" : s_pct), TAB, (s_reset == "" ? "-" : s_reset)
      printf "weekly%s%s%s%s\n", TAB, (w_pct < 0 ? "unavailable" : w_pct), TAB, (w_reset == "" ? "-" : w_reset)
    }'
}

# validate_value <token>: 0 when the token is `unavailable` or a plausible
# 0-100 integer. Defends the cache reader against a hand-corrupted signal file.
validate_value() {
  case $1 in
    unavailable) return 0 ;;
    "" | *[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 0 ] && [ "$1" -le 100 ]
}

# --- Cache read (evaluate) -------------------------------------------------
#
# read_signal: print `<session> <weekly>` from the cache, each a 0-100 int or
# `unavailable`. A cache absent, unreadable, corrupt, or staler than the TTL is
# reported as both-unavailable (never a guessed or fabricated number). The TTL
# is validated to exceed the read cadence (a stale-forever cadence is a config
# bug). A cache absent, unreadable, or corrupt reports both windows unavailable,
# which evaluate's both-unavailable arm treats as one lost read of the
# sustained-loss cadence.
read_signal() {
  rs_cadence=$(resolve_posint fleet_usage_read_cadence_seconds 300) || exit $?
  rs_ttl=$(resolve_posint fleet_usage_signal_ttl_seconds 900) || exit $?
  if [ "$rs_ttl" -le "$rs_cadence" ]; then
    echo "fleet-usage-gate: the signal TTL ($rs_ttl s) must exceed the read cadence ($rs_cadence s) — a stale-forever cadence is a config bug" >&2
    exit 4
  fi
  rs_dir=$(signal_dir) || exit 2
  rs_file="$rs_dir/signal"
  if [ ! -f "$rs_file" ]; then
    printf 'unavailable unavailable'
    return 0
  fi
  rs_epoch=$(sed -n '1p' "$rs_file" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  # Field 2 is the percentage (field 3 is the informational reset text); split on
  # TAB so a reset string starting with a digit can never be mistaken for the pct.
  rs_session=$(sed -n '2p' "$rs_file" 2>/dev/null | awk -F "$TAB" '{print $2}')
  rs_weekly=$(sed -n '3p' "$rs_file" 2>/dev/null | awk -F "$TAB" '{print $2}')
  case $rs_epoch in
    "" | *[!0-9]*)
      echo "fleet-usage-gate: signal cache '$rs_file' has a corrupt timestamp — treating as unavailable" >&2
      printf 'unavailable unavailable'
      return 0
      ;;
  esac
  if ! validate_value "$rs_session"; then rs_session=unavailable; fi
  if ! validate_value "$rs_weekly"; then rs_weekly=unavailable; fi
  rs_now=$(now_epoch) || {
    echo "fleet-usage-gate: cannot read the clock" >&2
    exit 2
  }
  # Reject BOTH a reading older than the TTL and a future-dated one (a backward
  # clock step or a corrupt future epoch yields a negative age that an
  # upper-bound-only test would accept as fresh forever). Either way the whole
  # reading is unavailable, never acted on.
  rs_age=$((rs_now - rs_epoch))
  if [ "$rs_age" -lt 0 ] || [ "$rs_age" -gt "$rs_ttl" ]; then
    rs_session=unavailable
    rs_weekly=unavailable
  fi
  printf '%s %s' "$rs_session" "$rs_weekly"
}

# --- Threshold resolution & the window->rung mapping (evaluate) ------------
#
# window_rung <percent> <t1> <t2> <t3> <t4|-> : map a percentage to a rung
# index by deterministic `>=` comparison against the ascending thresholds. A
# `-` fourth threshold means the window is capped below defer-all (the session
# window). An `unavailable` percentage contributes nothing (rung 0).
window_rung() {
  wr_pct=$1
  [ "$wr_pct" = unavailable ] && {
    printf 0
    return 0
  }
  wr_idx=0
  [ "$wr_pct" -ge "$2" ] && wr_idx=1
  [ "$wr_pct" -ge "$3" ] && wr_idx=2
  [ "$wr_pct" -ge "$4" ] && wr_idx=3
  if [ "$5" != "-" ] && [ "$wr_pct" -ge "$5" ]; then wr_idx=4; fi
  printf '%s' "$wr_idx"
}

# resolve_thresholds: resolve every per-window threshold through the overlay,
# validate 1-100 and strict monotone ordering per window (REQ-E1.6). Thresholds
# are positive integers (the shared resolver's `posint` type rejects 0), so the
# valid range is 1-100 — distinct from a usage PERCENTAGE, which may legitimately
# be 0. A malformed set is a fail-closed config error (exit 4) — the ladder must
# never run on out-of-range or non-monotonic thresholds. Sets the S_*/W_* globals.
resolve_thresholds() {
  S_DS=$(resolve_posint fleet_usage_session_downshift 50) || exit $?
  S_RC=$(resolve_posint fleet_usage_session_reduce_concurrency 70) || exit $?
  S_DH=$(resolve_posint fleet_usage_session_defer_heavy 85) || exit $?
  W_DS=$(resolve_posint fleet_usage_weekly_downshift 60) || exit $?
  W_RC=$(resolve_posint fleet_usage_weekly_reduce_concurrency 75) || exit $?
  W_DH=$(resolve_posint fleet_usage_weekly_defer_heavy 85) || exit $?
  W_DA=$(resolve_posint fleet_usage_weekly_defer_all 95) || exit $?
  for rt_v in "$S_DS" "$S_RC" "$S_DH" "$W_DS" "$W_RC" "$W_DH" "$W_DA"; do
    if [ "$rt_v" -lt 1 ] || [ "$rt_v" -gt 100 ]; then
      echo "fleet-usage-gate: a rung threshold ($rt_v) is outside 1-100 — refusing to run the ladder on an out-of-range threshold" >&2
      exit 4
    fi
  done
  if [ "$S_DS" -ge "$S_RC" ] || [ "$S_RC" -ge "$S_DH" ]; then
    echo "fleet-usage-gate: the session thresholds are not strictly ascending (downshift $S_DS < reduce-concurrency $S_RC < defer-heavy $S_DH) — refusing non-monotonic thresholds" >&2
    exit 4
  fi
  if [ "$W_DS" -ge "$W_RC" ] || [ "$W_RC" -ge "$W_DH" ] || [ "$W_DH" -ge "$W_DA" ]; then
    echo "fleet-usage-gate: the weekly thresholds are not strictly ascending (downshift $W_DS < reduce-concurrency $W_RC < defer-heavy $W_DH < defer-all $W_DA) — refusing non-monotonic thresholds" >&2
    exit 4
  fi
}

# --- Rung derivation from the audit trail (rung / evaluate) ----------------
#
# The ladder's state — the current rung AND its last-transition timestamp — is
# DERIVED from the most recent usage-gate audit row, never stored (D-28), so a
# memoryless relaunch recovers it. `derive_rung` reads the rung; the epoch of
# that same row is the last-transition timestamp (Task 10's hysteresis-dwell
# input), read by `last_transition_epoch`.
#
# derive_rung: print the current rung. No rows -> `normal`. An unreadable trail
# is a hard error (return 2), and a NON-empty but unrecognized last action is
# treated as corruption and also fails loud (never a silent `normal`, which
# would mask a corrupt store and silently drop the fleet from a restrictive rung
# to unrestricted).
derive_rung() {
  dr_out=$("$AUDIT" query --mechanism "$MECHANISM" 2>/dev/null) || {
    echo "fleet-usage-gate: cannot read the audit trail to derive the current rung" >&2
    return 2
  }
  dr_last=$(printf '%s\n' "$dr_out" | awk -F "$TAB" -v m="$MECHANISM" 'NF >= 4 && $3 == m { a = $4 } END { print a }')
  case $dr_last in
    normal | downshift | reduce-concurrency | defer-heavy | defer-all) printf '%s' "$dr_last" ;;
    "") printf 'normal' ;;
    *)
      echo "fleet-usage-gate: the last usage-gate audit action ('$(sanitize_printable "$dr_last" "(unprintable)")') is not a known rung — refusing to derive a silent 'normal' from a corrupt trail" >&2
      return 2
      ;;
  esac
}

# last_transition_epoch: print the epoch (field 1) of the most recent usage-gate
# row — the last-transition timestamp, derived from the same trail. Empty when
# the trail has no rows. An unreadable trail is a hard error (return 2).
last_transition_epoch() {
  lte_out=$("$AUDIT" query --mechanism "$MECHANISM" 2>/dev/null) || {
    echo "fleet-usage-gate: cannot read the audit trail to derive the last transition time" >&2
    return 2
  }
  printf '%s\n' "$lte_out" | awk -F "$TAB" -v m="$MECHANISM" 'NF >= 4 && $3 == m { e = $1 } END { printf "%s", e }'
}

# --- The sustained-loss counter (evaluate) ---------------------------------
#
# The consecutive-unavailable count is a per-tower LOCAL scalar beside the
# signal cache (advisory, no lock — the fleet-coherent state is the audit rung).
# bump_unavail returns the new count; reset_unavail zeroes it.
unavail_file() {
  uf_dir=$(signal_dir) || return 2
  printf '%s/unavail-count' "$uf_dir"
}
bump_unavail() {
  bu_file=$(unavail_file) || return 2
  bu_dir=$(dirname "$bu_file")
  mkdir -p "$bu_dir" 2>/dev/null || return 2
  bu_cur=$(sed -n '1p' "$bu_file" 2>/dev/null)
  case $bu_cur in
    "" | *[!0-9]*) bu_cur=0 ;;
  esac
  bu_new=$((bu_cur + 1))
  printf '%s\n' "$bu_new" >"$bu_file" || return 2
  printf '%s' "$bu_new"
}
reset_unavail() {
  ru_file=$(unavail_file) || return 0
  rm -f "$ru_file" 2>/dev/null || true
}

if [ "$#" -lt 1 ]; then
  usage
  exit 2
fi
cmd=$1
shift

case "$cmd" in
  capture)
    [ "$#" -eq 0 ] || {
      usage
      exit 2
    }
    parsed=$(parse_usage) || {
      echo "fleet-usage-gate: failed parsing the /usage render" >&2
      exit 2
    }
    r_session=$(printf '%s\n' "$parsed" | awk -F "$TAB" '$1 == "session" { print $2; exit }')
    r_sreset=$(printf '%s\n' "$parsed" | awk -F "$TAB" '$1 == "session" { print $3; exit }')
    r_weekly=$(printf '%s\n' "$parsed" | awk -F "$TAB" '$1 == "weekly" { print $2; exit }')
    r_wreset=$(printf '%s\n' "$parsed" | awk -F "$TAB" '$1 == "weekly" { print $3; exit }')
    [ -n "$r_session" ] || r_session=unavailable
    [ -n "$r_weekly" ] || r_weekly=unavailable
    [ -n "$r_sreset" ] || r_sreset="-"
    [ -n "$r_wreset" ] || r_wreset="-"
    r_dir=$(signal_dir) || exit 2
    r_file="$r_dir/signal"
    mkdir -p "$r_dir" || {
      echo "fleet-usage-gate: cannot create the signal cache dir '$r_dir'" >&2
      exit 2
    }
    r_now=$(now_epoch) || {
      echo "fleet-usage-gate: cannot read the clock" >&2
      exit 2
    }
    # Atomic write (temp + rename): the cache is lockless (per-tower, advisory),
    # so a concurrent reader must still never see a torn value. Restrict the
    # mode — the render's provenance is untrusted terminal output and the
    # cache is a transient capture artifact (REQ-E1.5 access-restriction).
    r_tmp=$(mktemp "$r_dir/.signal.XXXXXX") || {
      echo "fleet-usage-gate: cannot create a write temp under '$r_dir'" >&2
      exit 2
    }
    CUR_TMP=$r_tmp
    chmod 600 "$r_tmp" 2>/dev/null || true
    # Line 1 the read epoch; lines 2-3 `<window><TAB><pct><TAB><reset>`. The
    # reset field is informational (the gate reads only the percentage).
    printf '%s\nsession\t%s\t%s\nweekly\t%s\t%s\n' \
      "$r_now" "$r_session" "$r_sreset" "$r_weekly" "$r_wreset" >"$r_tmp" || {
      echo "fleet-usage-gate: cannot write the signal cache" >&2
      rm -f "$r_tmp"
      CUR_TMP=""
      exit 2
    }
    mv -f "$r_tmp" "$r_file" || {
      echo "fleet-usage-gate: cannot commit the signal cache" >&2
      rm -f "$r_tmp"
      CUR_TMP=""
      exit 2
    }
    CUR_TMP=""
    printf 'session\t%s\t%s\nweekly\t%s\t%s\n' "$r_session" "$r_sreset" "$r_weekly" "$r_wreset"
    exit 0
    ;;

  rung)
    [ "$#" -eq 0 ] || {
      usage
      exit 2
    }
    cur=$(derive_rung) || exit 2
    printf '%s\n' "$cur"
    exit 0
    ;;

  admit)
    [ "$#" -eq 1 ] || {
      usage
      exit 2
    }
    model=$1
    case $model in
      fable | opus) tier=heavy ;;
      sonnet | haiku) tier=cheap ;;
      *)
        echo "fleet-usage-gate: unknown model '$(sanitize_printable "$model" "(unprintable model)")' (fable opus sonnet haiku)" >&2
        exit 2
        ;;
    esac
    cur=$(derive_rung) || exit 2
    case $cur in
      defer-all)
        # Fleet-critical: admit no new dispatch, heavy or cheap.
        exit 1
        ;;
      defer-heavy)
        # Admit only cheaper units; heavy/opus units wait.
        [ "$tier" = heavy ] && exit 1
        exit 0
        ;;
      *)
        # normal / downshift / reduce-concurrency admit every tier (the
        # downshift/reduce-concurrency CONSEQUENCE — which model, how many
        # concurrent — is Task 10's; admission-wise they withhold nothing).
        exit 0
        ;;
    esac
    ;;

  evaluate)
    [ "$#" -eq 0 ] || {
      usage
      exit 2
    }
    # The gate gates ENTRY (D-15): one kill-switch check at the moment the
    # daemon action starts. A missing gate helper is a broken install.
    if [ ! -x "$GATE" ]; then
      echo "fleet-usage-gate: daemon gate '$GATE' is missing or not executable — broken install" >&2
      exit 5
    fi
    "$GATE" "$MECHANISM"
    gate_rc=$?
    if [ "$gate_rc" -eq 1 ]; then
      # Paused: the operator has assumed manual control, so the proactive gate
      # and the reactive throttle are paused with it (REQ-E1.7). Clear any
      # outstanding sustained-loss hold — it no longer applies (REQ-E1.5) — and
      # short-circuit before any transition.
      if [ -x "$ATTN" ]; then
        "$ATTN" clear "$MECHANISM" >/dev/null 2>&1 || true
      fi
      echo "fleet-usage-gate: the operator kill-switch is engaged; the usage gate is paused" >&2
      exit 1
    fi
    if [ "$gate_rc" -ne 0 ]; then
      # 4/5 from the gate's own resolver: propagate the fail-closed code.
      exit "$gate_rc"
    fi

    sig=$(read_signal) || exit $?
    sess=${sig% *}
    week=${sig#* }

    if [ "$sess" = unavailable ] && [ "$week" = unavailable ]; then
      # No window signal: fall back to the reactive backstop. Take NO proactive
      # rung transition (no block, no guessed number), and keep the
      # sustained-loss cadence.
      count=$(bump_unavail) || {
        echo "fleet-usage-gate: cannot update the sustained-loss counter" >&2
        exit 2
      }
      loss_limit=$(resolve_posint fleet_usage_sustained_loss_count 3) || exit $?
      cur=$(derive_rung) || exit 2
      if [ "$count" -ge "$loss_limit" ]; then
        # The REQUIRED operator surface: a warning escalating to an
        # Awaiting-input hold, so a permanently broken /usage parse is never
        # silent (D-23 version drift). park is atomic-unless-awaiting, so
        # re-firing across cadences preserves a pending decision.
        echo "fleet-usage-gate: warning: the /usage signal has been unavailable across $count consecutive reads (>= the sustained-loss threshold $loss_limit); raising an operator hold" >&2
        if [ -x "$ATTN" ]; then
          "$ATTN" park "$MECHANISM" fleet \
            "proactive /usage signal unavailable across $count consecutive reads; governance is on the reactive backstop only. Operator: choose a model, wait, or proceed." \
            >/dev/null 2>&1 || echo "fleet-usage-gate: warning: could not push the operator hold surface" >&2
        fi
      else
        echo "fleet-usage-gate: warning: the /usage signal is unavailable ($count of $loss_limit consecutive); deferring to the reactive backstop, no proactive rung change" >&2
      fi
      since=$(last_transition_epoch 2>/dev/null) || since=""
      printf 'rung\t%s\tsince\t%s\tsession\tunavailable\tweekly\tunavailable\n' "$cur" "$since"
      exit 0
    fi

    # At least one window is available: the sustained-loss cadence is broken.
    reset_unavail
    if [ -x "$ATTN" ]; then
      "$ATTN" clear "$MECHANISM" >/dev/null 2>&1 || true
    fi

    resolve_thresholds
    s_rung=$(window_rung "$sess" "$S_DS" "$S_RC" "$S_DH" "-")
    w_rung=$(window_rung "$week" "$W_DS" "$W_RC" "$W_DH" "$W_DA")
    # The session window is capped at defer-heavy (REQ-E1.6): a numeric clamp.
    [ "$s_rung" -gt "$SESSION_CAP" ] && s_rung=$SESSION_CAP
    # The more restrictive window governs: a numeric max of the two targets.
    target_idx=$s_rung
    [ "$w_rung" -gt "$target_idx" ] && target_idx=$w_rung
    target=$(rung_name "$target_idx")

    # Fast, lockless edge-trigger check: an unchanged rung records NO row (D-28)
    # and needs no lock. A concurrent transition in flight can at worst make this
    # read slightly stale, which the authoritative under-lock re-derive below
    # corrects before any write.
    cur=$(derive_rung) || exit 2
    if [ "$target" = "$cur" ]; then
      since=$(last_transition_epoch 2>/dev/null) || since=""
      printf 'rung\t%s\tsince\t%s\tsession\t%s\tweekly\t%s\n' "$cur" "$since" "$sess" "$week"
      exit 0
    fi

    # A real rung change: take the shared advisory lock (REQ-G1.3) and hold it
    # across the authoritative re-derive AND the audit write, so two racing
    # towers cannot both record the same transition — the second acquires the
    # lock only after the first's row is committed, re-derives the new rung, and
    # no-ops. The nested fleet-audit record runs with PLANWRIGHT_FLEET_LOCK_HELD
    # so it does not deadlock re-acquiring this same primitive. The reasoning
    # carries ONLY the extracted percentages and the rung decision, NEVER the
    # raw /usage render (which can carry account/plan identifiers; REQ-E1.5
    # artifact-hygiene).
    acquire_lock || exit 2
    cur=$(derive_rung) || {
      release_lock
      exit 2
    }
    if [ "$target" = "$cur" ]; then
      # Read `since` under the lock (as the transition path does) for a
      # consistent rung/since snapshot: while we hold the lock no other tower can
      # transition, so `since` is the epoch of the rung we are reporting.
      since=$(last_transition_epoch 2>/dev/null) || since=""
      release_lock
      printf 'rung\t%s\tsince\t%s\tsession\t%s\tweekly\t%s\n' "$cur" "$since" "$sess" "$week"
      exit 0
    fi
    # Defer INT/TERM across the commit span so a signal cannot land a rung
    # change with a half-written trail; the lock is released on the way out.
    trap '' INT TERM
    reasoning="usage gate: session=$sess% weekly=$week% -> rung $target (was $cur)"
    # Pass the mechanism name (not a bare 1) so fleet-audit skips its acquire
    # ONLY for this usage-gate record — a global flag could let an inherited env
    # var disable locking for an unrelated mechanism (fleet-audit header).
    PLANWRIGHT_FLEET_LOCK_HELD="$MECHANISM" "$AUDIT" record "$MECHANISM" "$target" \
      "proactive usage gate rung transition" "$reasoning" || {
      release_lock
      echo "fleet-usage-gate: the audit trail refused the rung-transition record — surfacing, not swallowing" >&2
      exit 2
    }
    # Read `since` while STILL holding the lock, so the printed rung/since pair is
    # a consistent snapshot: under the lock the last usage-gate row is the one we
    # just wrote (no other tower can transition), so `since` is this transition's
    # own epoch. Reading it after release would let a concurrent tower's later
    # transition land in between, pairing our rung with a stranger's timestamp.
    # last_transition_epoch does a lockless query, so it is safe to call here.
    since=$(last_transition_epoch 2>/dev/null) || since=""
    release_lock
    printf 'rung\t%s\tsince\t%s\tsession\t%s\tweekly\t%s\n' "$target" "$since" "$sess" "$week"
    exit 0
    ;;

  *)
    usage
    exit 2
    ;;
esac
