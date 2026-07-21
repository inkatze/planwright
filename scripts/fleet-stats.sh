#!/bin/sh
# fleet-stats.sh — the on-demand DERIVED fleet-stats renderer and the
# human-facing audit-trail render (fleet-autonomy Task 8: D-13, D-14, D-16,
# REQ-F1.1, REQ-F1.2, REQ-F1.4).
#
# WHY DERIVED, NEVER STORED (D-13). Fleet health/activity statistics are
# computed on demand from state Tasks 2-4 and 7 ALREADY keep, never captured
# into a new shared-write accumulator file. A new append-only stats log would
# reopen the exact concurrent-write-conflict class observation-recording had to
# solve for its shared log (GitHub ignores `.gitattributes merge=union` on PR
# merges; nothing reconciles a shared file multiple PRs both append to and
# prune) — for no reason, since nothing here needs to be committed. So this
# script only READS its siblings and renders; it opens no store, holds no lock,
# and writes nothing. That is the design-level no-new-file floor (REQ-F1.1),
# enforced structurally: fleet-stats.sh never resolves the fleet home itself.
#
# THE THREE DERIVED STATS (tasks.md Task 8 Deliverables):
#   last cleanup    — the most recent reclaim in the shared audit trail
#                     (scripts/fleet-audit.sh): the newest row whose action is
#                     `cleanup` (Task 4's window-cleanup / worktree-cleanup
#                     reclaim actuator). Refuse-self blocks and housekeeping
#                     escalations are not reclaims and do not count.
#   watchdog trips  — how many times Task 3's tower-liveness watchdog TRIPPED:
#                     audit rows with mechanism `tower-watchdog` and action
#                     relaunch / relaunch-failed / disable (the watchdog acting
#                     on positive evidence of a dead tower). The healthy
#                     `reset-backoff` action (trigger tower-alive) is NOT a trip.
#   throttle        — Task 7's LIVE throttle state, read straight from
#                     scripts/fleet-throttle.sh check (engaged-until vs idle),
#                     never a stale audit row: the audit trail records the
#                     engage/clear EVENTS, but the current state is the throttle
#                     store, so a cleared throttle reads idle immediately.
#
# COMPOSES WITH fleet-attention.sh (D-14). `line` folds the decision-queue
# length (fleet-attention.sh queue --count) into a single compact line for the
# statusLine surface, so the operator sees stats and the actionable-queue depth
# together. The statusLine wiring itself is scripts/fleet-statusline.sh, gated on
# the `statusline` notification_channel value.
#
# THE AUDIT RENDER (REQ-F1.4). `audit` is the human-facing view of Task 1's
# audit trail: it wraps scripts/fleet-audit.sh query (passing --mechanism /
# --since / --until straight through, so it is queryable by mechanism and time
# range) and reformats each TSV row as `<utc>  <mechanism>/<action>  <trigger>
# :: <reasoning>` — legible, not a raw column dump.
#
# DEGRADE, NEVER HALT OPAQUELY. If a sibling read fails (a corrupted home, a
# broken install), a stat degrades to `unknown` with a warning on stderr rather
# than aborting the whole render — the same fail-visible posture the rest of the
# fleet takes. Every rendered field is run through the canonical echo-discipline
# sanitizer before it reaches the terminal, so even a hand-corrupted upstream
# store line can neither drive the terminal nor tear the output.
#
# Usage:
#   fleet-stats.sh render
#       The multi-line human-facing stats block (last cleanup, watchdog trips,
#       throttle state).
#   fleet-stats.sh line
#       The compact single-line render for a statusLine, folding in the
#       decision-queue length.
#   fleet-stats.sh audit [--mechanism <m>] [--since <epoch>] [--until <epoch>]
#       The human-facing audit-trail render, queryable by mechanism and time
#       range (the filters pass straight through to fleet-audit.sh query).
#
# Exit codes: 0 success; 2 usage error or a broken install (a required sibling
#   missing); a propagated non-zero from fleet-audit.sh query (`audit` only,
#   e.g. a malformed --since bound is refused with the helper's own exit).
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling): `date`,
# awk. No eval, no jq (REQ-K1.5). All input is data. Pathname expansion is
# disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# The canonical echo-discipline sanitizer (doctrine/security-posture.md), sourced
# as the sibling fleet scripts do; a missing helper is a broken install.
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

AUDIT="$script_dir/fleet-audit.sh"
THROTTLE="$script_dir/fleet-throttle.sh"
USAGE_GATE="$script_dir/fleet-usage-gate.sh"
ATTN="$script_dir/fleet-attention.sh"
TAB=$(printf '\t')

# utc_iso <epoch>: best-effort UTC rendering, byte-identical to
# fleet-throttle.sh's helper — BSD `date -u -r`, then GNU `date -u -d @`, then a
# bare `epoch N` fallback so a host with neither still renders something.
utc_iso() {
  ui_v=$(TZ=UTC date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) \
    || ui_v=$(TZ=UTC date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) \
    || ui_v="epoch $1"
  printf '%s' "$ui_v"
}

# derive_from_audit — read the whole audit trail ONCE and derive both the
# last-cleanup iso and the watchdog-trip count from it. Sets LAST_CLEANUP and
# WATCHDOG_TRIPS. A query failure (corrupted home / broken install) degrades
# both to `unknown` with a warning, never a silent zero.
#
# SCAN COST (kickoff risk 14, accepted). This scans the whole audit trail — but
# fleet-audit.sh already time-bounds the store into UTC daily files, so the cost
# is a small awk over at most one file per operating day, not an unbounded single
# log. At realistic fleet lifetimes that is negligible even on the high-frequency
# `line`/statusLine path. If the early signal risk 14 names ever fires (statusLine
# latency growing with operating history), the mitigation is to bound the query
# to a recent window (fleet-audit query already supports --since) or maintain
# lightweight incremental counters — still derived, no new shared-write file.
LAST_CLEANUP=""
WATCHDOG_TRIPS=""
derive_from_audit() {
  if [ ! -x "$AUDIT" ]; then
    echo "fleet-stats: audit helper '$AUDIT' is missing or not executable" >&2
    LAST_CLEANUP="unknown"
    WATCHDOG_TRIPS="unknown"
    return 0
  fi
  da_rc=0
  da_all=$("$AUDIT" query 2>/dev/null) || da_rc=$?
  if [ "$da_rc" != 0 ]; then
    echo "fleet-stats: could not read the audit trail (fleet-audit query exit $da_rc); cleanup/watchdog stats degraded to unknown" >&2
    LAST_CLEANUP="unknown"
    WATCHDOG_TRIPS="unknown"
    return 0
  fi
  # Newest `cleanup`-action row across every cleanup mechanism. The "" pins
  # string comparison for the action token; $1+0 forces numeric max so a row
  # order that is not strictly chronological still picks the latest epoch.
  LAST_CLEANUP=$(printf '%s\n' "$da_all" | awk -F "$TAB" '
    ($4 "") == "cleanup" { if ($1 + 0 > m + 0) { m = $1; iso = $2 } }
    END { print (iso == "" ? "never" : iso) }')
  # Trip = the watchdog acting on a dead tower. reset-backoff (tower-alive) is
  # the healthy path and is excluded.
  WATCHDOG_TRIPS=$(printf '%s\n' "$da_all" | awk -F "$TAB" '
    ($3 "") == "tower-watchdog" &&
    (($4 "") == "relaunch" || ($4 "") == "relaunch-failed" || ($4 "") == "disable") { n++ }
    END { print n + 0 }')
}

# derive_gate_rung — the proactive usage gate's current restriction rung (Task 9,
# D-23/D-28), DERIVED from the shared audit trail by fleet-usage-gate.sh. The gate
# is throttle-family, so its rung is folded into the existing throttle stat
# channel below rather than minting a new stat type (REQ-E1.6). Prints the rung
# name, or empty on any absence/error — a missing or failing gate must degrade
# the throttle line, never break it.
derive_gate_rung() {
  [ -x "$USAGE_GATE" ] || {
    printf ''
    return 0
  }
  dgr_out=$("$USAGE_GATE" rung 2>/dev/null) || {
    printf ''
    return 0
  }
  case $dgr_out in
    normal | downshift | reduce-concurrency | defer-heavy | defer-all)
      printf '%s' "$dgr_out"
      ;;
    *) printf '' ;;
  esac
}

# derive_throttle — Task 7's LIVE throttle state (never a stale audit row), then
# fold in Task 9's proactive usage-gate rung (the gate is throttle-family, so it
# reuses this channel — REQ-E1.6). Sets THROTTLE_STATE. `check` exits 0 when idle
# (nothing engaged), 1 with an `until\t<epoch>` line when engaged, and 2 on an
# error (degrade to unknown).
THROTTLE_STATE=""
derive_throttle() {
  if [ ! -x "$THROTTLE" ]; then
    echo "fleet-stats: throttle helper '$THROTTLE' is missing or not executable" >&2
    THROTTLE_STATE="unknown"
    return 0
  fi
  dt_rc=0
  dt_out=$("$THROTTLE" check 2>/dev/null) || dt_rc=$?
  case $dt_rc in
    0)
      THROTTLE_STATE="idle"
      ;;
    1)
      # Engaged: the line is `until<TAB><epoch>`; take the field after the tab.
      dt_epoch=${dt_out#*"$TAB"}
      case $dt_epoch in
        "" | *[!0-9]*)
          THROTTLE_STATE="engaged (until time unreadable)"
          ;;
        *)
          THROTTLE_STATE="engaged until $(utc_iso "$dt_epoch") (epoch $dt_epoch)"
          ;;
      esac
      ;;
    *)
      echo "fleet-stats: could not read the throttle state (fleet-throttle check exit $dt_rc); throttle stat degraded to unknown" >&2
      THROTTLE_STATE="unknown"
      ;;
  esac
  # Fold in the proactive gate's rung when it is engaged (non-normal). This
  # reuses the throttle-engaged channel (no new stat type): a normal rung, an
  # absent gate, or an unknown throttle state leaves the reactive line as-is.
  if [ "$THROTTLE_STATE" != "unknown" ]; then
    dt_rung=$(derive_gate_rung)
    if [ -n "$dt_rung" ] && [ "$dt_rung" != normal ]; then
      THROTTLE_STATE="$THROTTLE_STATE (usage-gate: $dt_rung)"
    fi
  fi
}

# queue_count — the decision-queue length via fleet-attention.sh (composition,
# D-14). Three outcomes, kept distinct:
#   `deferred` — a healthy exit-0 with EMPTY stdout: a backend advertises
#                provides_attention_surface (PLANWRIGHT_ATTENTION_SURFACE_PROVIDED
#                / --surface-provided), so planwright suppresses its own decision
#                queue and defers to that backend. This is NOT a read failure, so
#                it must not wear the `?` token. (The producer overloads exit-0 +
#                empty to mean deferral, forcing this inference; a durable
#                producer-side signal is tracked as a follow-up observation.)
#   `?`        — a genuine read failure: $ATTN missing/not executable, a non-zero
#                exit, or non-numeric/garbage output. Never a wrong number.
#   <n>        — the actual count (exit 0 with a numeric line).
queue_count() {
  if [ ! -x "$ATTN" ]; then
    printf '?'
    return 0
  fi
  qc_rc=0
  qc_n=$("$ATTN" queue --count 2>/dev/null) || qc_rc=$?
  if [ "$qc_rc" != 0 ]; then
    printf '?'
    return 0
  fi
  # Exit 0 from here: empty stdout is the deferred-to-backend signal; a numeric
  # line is the real count; anything else is malformed output (a read failure).
  case $qc_n in
    "") printf 'deferred' ;;
    *[!0-9]*) printf '?' ;;
    *) printf '%s' "$qc_n" ;;
  esac
}

cmd="${1:-}"
if [ -z "$cmd" ]; then
  echo "usage: fleet-stats.sh render | line | audit [--mechanism <m>] [--since <epoch>] [--until <epoch>]" >&2
  exit 2
fi
shift || true

case $cmd in
  render)
    [ "$#" -eq 0 ] || {
      echo "usage: fleet-stats.sh render" >&2
      exit 2
    }
    derive_from_audit
    derive_throttle
    s_cleanup=$(sanitize_printable "$LAST_CLEANUP" "?")
    s_trips=$(sanitize_printable "$WATCHDOG_TRIPS" "?")
    s_throttle=$(sanitize_printable "$THROTTLE_STATE" "?")
    printf 'fleet stats (derived on demand; no stored stats file)\n'
    printf '  last cleanup:   %s\n' "$s_cleanup"
    printf '  watchdog trips: %s\n' "$s_trips"
    printf '  throttle:       %s\n' "$s_throttle"
    exit 0
    ;;

  line)
    [ "$#" -eq 0 ] || {
      echo "usage: fleet-stats.sh line" >&2
      exit 2
    }
    derive_from_audit
    derive_throttle
    q=$(queue_count)
    # Compact fields: the cleanup DATE (or none/?), the trip count, an
    # engaged/idle throttle flag, and the queue depth — all on one control-free
    # line safe for a statusLine.
    case $LAST_CLEANUP in
      never) c=none ;;
      unknown) c='?' ;;
      *) c=${LAST_CLEANUP%%T*} ;;
    esac
    case $THROTTLE_STATE in
      idle) th=idle ;;
      unknown) th='?' ;;
      *) th=engaged ;;
    esac
    s_c=$(sanitize_printable "$c" "?")
    s_trips=$(sanitize_printable "$WATCHDOG_TRIPS" "?")
    s_th=$(sanitize_printable "$th" "?")
    s_q=$(sanitize_printable "$q" "?")
    printf 'planwright | cleanup %s | trips %s | throttle %s | queue %s\n' \
      "$s_c" "$s_trips" "$s_th" "$s_q"
    exit 0
    ;;

  audit)
    if [ ! -x "$AUDIT" ]; then
      echo "fleet-stats: audit helper '$AUDIT' is missing or not executable" >&2
      exit 2
    fi
    # Pass every flag straight through to fleet-audit.sh query — it owns the
    # --mechanism / --since / --until contract AND their validation (a malformed
    # bound is refused there with its own exit, propagated here). Capturing the
    # output lets us reformat only a clean, complete result set.
    ar_rc=0
    ar_raw=$("$AUDIT" query "$@") || ar_rc=$?
    if [ "$ar_rc" != 0 ]; then
      exit "$ar_rc"
    fi
    # Reformat each 6-field row as a legible line. NF != 6 rows are skipped
    # (fleet-audit query already warned about and re-sanitized them); the fields
    # it emits are printable ASCII, so no further sanitize is needed here.
    printf '%s\n' "$ar_raw" | awk -F "$TAB" '
      NF == 6 { printf "%s  %s/%s  %s :: %s\n", $2, $3, $4, $5, $6 }'
    exit 0
    ;;

  *)
    echo "fleet-stats: unknown command '$(sanitize_printable "$cmd" "(unprintable command)")' (render|line|audit)" >&2
    exit 2
    ;;
esac
