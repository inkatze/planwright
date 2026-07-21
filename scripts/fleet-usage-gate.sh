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
# DEGRADATION (REQ-E1.5). When no window signal is available, governance falls
# back to the reactive backstop: `evaluate` reports unavailable and takes NO
# proactive rung transition (no block, no guessed number). Sustained
# unavailability — the signal unavailable across an overlay-configurable number
# of consecutive read cadences — raises a REQUIRED operator surface (a warning
# escalating to an Awaiting-input hold via fleet-attention.sh), so a permanently
# broken `/usage` parse (the D-23 version-drift fragility) is never silent. An
# outstanding hold is cleared when the kill-switch is engaged (the operator has
# assumed control; the hold no longer applies).
#
# Usage:
#   fleet-usage-gate.sh capture
#       Read a captured /usage render on stdin, parse both windows, cache the
#       signal, and print it as two lines:
#         session<TAB><percent|unavailable>
#         weekly<TAB><percent|unavailable>
#       Exit 0 (a per-window unavailable is a normal state, not an error);
#       exit 2 on a usage or I/O error.
#   fleet-usage-gate.sh evaluate
#       The proactive gate. Read the cached signal (absent or stale-beyond-TTL
#       => unavailable), compute the target rung (per-window thresholds via the
#       overlay, more-restrictive-wins, session capped at defer-heavy), derive
#       the current rung from the audit trail, and — on a change — record an
#       edge-triggered transition under the advisory lock. Prints
#       `rung<TAB><name><TAB>session<TAB><s><TAB>weekly<TAB><w>`. Exit 0; exit 1
#       when the kill-switch pauses the gate; exit 2/4/5 on error (see below).
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
#   error (fail closed); 4 malformed team-shared config (a non-monotonic or
#   out-of-range repo-tracked threshold, or a resolver hard-fail); 5 broken
#   install (a resolver or helper is unavailable or its core default is
#   itself malformed). Never fails opaquely.
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
# nested fleet-audit record runs with PLANWRIGHT_FLEET_LOCK_HELD=1 to skip the
# re-acquire that would deadlock on this same non-reentrant primitive.
HOLD_LOCK=0
# Release on ANY exit, signals included (the fleet-audit.sh trap discipline): a
# SIGINT/SIGTERM mid-critical-section must not leave the shared cross-spec lock
# held until the stale-break threshold. INT/TERM route through EXIT via explicit
# exits with the conventional codes.
trap 'release_lock' EXIT
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
# parse_usage: read the captured render on stdin, print two lines
# `session <value>` and `weekly <value>` where <value> is a plausible 0-100
# integer or the literal `unavailable`. Control/escape bytes are stripped
# BEFORE parsing (a CSI sequence removed whole, then any residual non-print
# byte), so a smuggled escape cannot survive into the output or forge a value.
# Each window is found BY LABEL (`session` / `week`) with a bounded lookahead
# to the percentage — the render puts the percent on the label line or the
# next — and by-label means window ORDER does not matter. A percentage that is
# absent near its label, or present but outside 0-100, yields `unavailable`.
parse_usage() {
  head -c 262144 | awk '
    {
      line = $0
      # Remove whole ANSI CSI sequences (ESC [ ... final-byte), then strip any
      # residual non-printable byte — the echo-discipline awk form. A color
      # code cannot leave a bracket-number fragment that forges "NN%".
      gsub(/\033\[[0-9;?]*[ -\/]*[@-~]/, "", line)
      gsub(/[^[:print:]]/, "", line)
      n++
      lines[n] = line
      lower[n] = tolower(line)
    }
    function pct_near(kw,    i, j, s, num) {
      # First line whose lowercased text mentions the keyword; then scan that
      # line and up to three following lines for the first NN% token.
      for (i = 1; i <= n; i++) {
        if (index(lower[i], kw) == 0) continue
        for (j = i; j <= n && j <= i + 3; j++) {
          s = lines[j]
          if (match(s, /[0-9]+%/)) {
            num = substr(s, RSTART, RLENGTH - 1) + 0
            if (num >= 0 && num <= 100) return num
            return -1 # present but implausible -> unavailable, never guessed
          }
        }
        return -1 # labelled window with no plausible percentage nearby
      }
      return -2 # window label absent
    }
    END {
      sv = pct_near("session")
      wv = pct_near("week")
      printf "session %s\n", (sv < 0 ? "unavailable" : sv)
      printf "weekly %s\n", (wv < 0 ? "unavailable" : wv)
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
  rs_session=$(sed -n '2p' "$rs_file" 2>/dev/null | awk '{print $2}')
  rs_weekly=$(sed -n '3p' "$rs_file" 2>/dev/null | awk '{print $2}')
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
  if [ $((rs_now - rs_epoch)) -gt "$rs_ttl" ]; then
    # Staler than the TTL: the whole reading is unavailable, never acted on.
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
# validate 0-100 and strict monotone ordering per window (REQ-E1.6). A
# malformed set is a fail-closed config error (exit 4) — the ladder must never
# run on non-monotonic thresholds. Sets the S_* and W_* globals.
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
# derive_rung: print the current rung — the action of the most recent
# usage-gate audit row (D-28: state derived, not stored). No rows -> normal. An
# unreadable trail is a hard error (never a silent `normal`, which would mask a
# corrupt store and let the ladder re-degrade from scratch).
derive_rung() {
  dr_out=$("$AUDIT" query --mechanism "$MECHANISM" 2>/dev/null) || {
    echo "fleet-usage-gate: cannot read the audit trail to derive the current rung" >&2
    return 2
  }
  dr_last=$(printf '%s\n' "$dr_out" | awk -F "$TAB" -v m="$MECHANISM" 'NF >= 4 && $3 == m { a = $4 } END { print a }')
  case $dr_last in
    normal | downshift | reduce-concurrency | defer-heavy | defer-all) printf '%s' "$dr_last" ;;
    "") printf 'normal' ;;
    *) printf 'normal' ;;
  esac
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
    r_session=$(printf '%s\n' "$parsed" | awk '/^session /{print $2; exit}')
    r_weekly=$(printf '%s\n' "$parsed" | awk '/^weekly /{print $2; exit}')
    [ -n "$r_session" ] || r_session=unavailable
    [ -n "$r_weekly" ] || r_weekly=unavailable
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
    chmod 600 "$r_tmp" 2>/dev/null || true
    printf '%s\nsession %s\nweekly %s\n' "$r_now" "$r_session" "$r_weekly" >"$r_tmp" || {
      echo "fleet-usage-gate: cannot write the signal cache" >&2
      rm -f "$r_tmp"
      exit 2
    }
    mv -f "$r_tmp" "$r_file" || {
      echo "fleet-usage-gate: cannot commit the signal cache" >&2
      rm -f "$r_tmp"
      exit 2
    }
    printf 'session\t%s\nweekly\t%s\n' "$r_session" "$r_weekly"
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
      printf 'rung\t%s\tsession\tunavailable\tweekly\tunavailable\n' "$cur"
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
      printf 'rung\t%s\tsession\t%s\tweekly\t%s\n' "$cur" "$sess" "$week"
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
      release_lock
      printf 'rung\t%s\tsession\t%s\tweekly\t%s\n' "$cur" "$sess" "$week"
      exit 0
    fi
    # Defer INT/TERM across the commit span so a signal cannot land a rung
    # change with a half-written trail; the lock is released on the way out.
    trap '' INT TERM
    reasoning="usage gate: session=$sess% weekly=$week% -> rung $target (was $cur)"
    PLANWRIGHT_FLEET_LOCK_HELD=1 "$AUDIT" record "$MECHANISM" "$target" \
      "proactive usage gate rung transition" "$reasoning" || {
      release_lock
      echo "fleet-usage-gate: the audit trail refused the rung-transition record — surfacing, not swallowing" >&2
      exit 2
    }
    release_lock
    printf 'rung\t%s\tsession\t%s\tweekly\t%s\n' "$target" "$sess" "$week"
    exit 0
    ;;

  *)
    usage
    exit 2
    ;;
esac
