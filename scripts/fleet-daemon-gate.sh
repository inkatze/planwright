#!/bin/sh
# fleet-daemon-gate.sh — the operator kill-switch check every autonomous
# daemon mechanism calls BEFORE acting (Task 1: D-15, REQ-F1.3).
#
# The `fleet_daemon_pause` knob is the one lever that pauses every autonomous
# daemon action the fleet-autonomy bundle introduces (cleanup, restart,
# throttle) without disabling fleet operation entirely — an operator debugging
# something unusual flips one switch instead of N per-mechanism knobs, and
# flips one back afterward. Task work (towers dispatching, workers executing)
# is unaffected; only the autonomous daemon layer pauses.
#
# The knob resolves through the shared knob resolver (resolve-config-knob.sh
# -> config-get, D-22/REQ-G1.5): four overlay layers, last-layer-wins, the
# REQ-E1.4 by-layer malformed policy. WRITE AUTHORIZATION (kickoff risk row
# 21): the layers that can flip this switch are human-owned surfaces — the
# repo-tracked overlay is committed, PR-reviewed config, and the
# adopter/machine-local overlays are operator-machine files outside any
# dispatched worker's allowlisted write set — the same human-reviewed,
# human-installed posture config/worker-settings.json has (D-19). A worker's
# permission allowlist must not be widened to cover these paths.
#
# Answer is the exit code — FAIL CLOSED: only exit 0 authorizes proceeding,
# so a gate that cannot resolve its own switch blocks the daemon action
# (degrade capability, never safety). The fallback handed to the resolver is
# `true` (paused), so a switch absent from every config layer — a broken or
# partial install — lands on the paused arm rather than silently proceeding:
#   exit 0 = proceed (switch false)
#   exit 1 = paused (switch true, or unresolvable-from-any-layer per the
#            fail-safe fallback) — the caller must short-circuit
#   exit 2 = usage / refused mechanism token
#   exit 4 = the team-shared overlay is malformed (resolver hard-fail):
#            blocked, never run under unknown shared configuration
#   exit 5 = broken install (the resolver cannot run at all, or the core
#            default itself is malformed/unresolvable): blocked
#
# The gate gates ENTRY: it is a one-shot check at the moment the daemon
# action starts, not a lease over its duration. A switch flipped mid-action
# does not interrupt an action already past the gate; a long-running or
# multi-resource mechanism (Tasks 2-7) should re-check the gate at its own
# internal step boundaries (e.g. once per resource in a sweep).
#
# Usage: fleet-daemon-gate.sh [<mechanism>]
#   <mechanism> (optional) names the calling daemon mechanism in the paused
#   note, validated against the fleet field grammar before it reaches any
#   diagnostic surface.
#
# POSIX sh on the macOS + Linux support bar. All input is data (REQ-K1.5).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

if [ "$#" -gt 1 ]; then
  echo "usage: fleet-daemon-gate.sh [<mechanism>]" >&2
  exit 2
fi

mechanism="${1:-}"
if [ -n "$mechanism" ]; then
  # The fleet field grammar (fleet-state.sh valid_field): no path separators,
  # whitespace, or control/shell metacharacters; bounded to 128 chars.
  case "$mechanism" in
    *[!A-Za-z0-9._=@:-]*)
      echo "fleet-daemon-gate: refusing malformed mechanism token" >&2
      exit 2
      ;;
  esac
  if [ "${#mechanism}" -gt 128 ]; then
    echo "fleet-daemon-gate: refusing over-length mechanism token" >&2
    exit 2
  fi
fi

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
resolver="$script_dir/resolve-config-knob.sh"
if [ ! -x "$resolver" ]; then
  echo "fleet-daemon-gate: knob resolver '$resolver' is missing or not executable — blocking the daemon action (fail closed)" >&2
  exit 5
fi

# --fallback true is the fail-safe direction: it is emitted only when NO
# layer resolves the knob (the shipped core defaults carry it, so that means
# a broken/partial install), and pausing the daemon layer is the safe answer
# there (fail closed; a daemon pause costs convenience, never safety).
value=""
rc=0
value=$("$resolver" --key fleet_daemon_pause --type enum --values 'true false' --fallback true) || rc=$?
if [ "$rc" -ne 0 ]; then
  # The resolver already named the failure on stderr (a malformed team-shared
  # value is exit 4, a broken install exit 5). Any resolution failure blocks
  # the daemon action: never act under unknown kill-switch state.
  echo "fleet-daemon-gate: could not resolve fleet_daemon_pause (exit $rc) — blocking the daemon action (fail closed)" >&2
  exit "$rc"
fi

if [ "$value" = true ]; then
  if [ -n "$mechanism" ]; then
    echo "fleet-daemon-gate: fleet_daemon_pause is set — pausing daemon action '$mechanism' (unset the knob to resume)" >&2
  else
    echo "fleet-daemon-gate: fleet_daemon_pause is set — pausing the daemon action (unset the knob to resume)" >&2
  fi
  exit 1
fi
exit 0
