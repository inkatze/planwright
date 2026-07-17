#!/bin/sh
# fleet-death-evidence.sh — the thin wrapper exposing the backend capability
# contract's positive-evidence-of-death predicate
# (doctrine/backend-capability-contract.md, orchestration-fleet D-2) for reuse
# by every kill/cleanup/restart mechanism in the fleet-autonomy bundle
# (Task 1: D-5, REQ-A1.7).
#
# THE PREDICATE. A destructive mechanism may act only on POSITIVE evidence of
# death: the handle, window, or process is demonstrably gone from an
# authoritative, demonstrably-healthy source. Silence is not evidence. The
# 2026-06-12 incident this encodes: a dead tmux socket plus a truncated
# process listing mimicked dead workers that were in fact alive, because the
# sweep did not distinguish lost observability from observed death. So:
#   - "dead" requires the query mechanism itself to respond healthily AND to
#     report the target absent;
#   - a query mechanism that cannot be reached is "unknown" — the caller must
#     REFUSE to act and leave the resource alone;
#   - a timeout, heartbeat age, or silence is not admissible input at all:
#     there is no such evidence class, and naming one is refused explicitly.
#
# Verdict contract — fail-closed for `if fleet-death-evidence.sh ...; then act`:
#   exit 0 = dead      positive evidence; destructive action authorized
#   exit 1 = alive     the target demonstrably exists
#   exit 3 = unknown   lost observability; refuse to act
#   exit 2 = usage / refused input (pseudo-evidence classes included)
# The verdict word (dead|alive|unknown) is also printed on stdout, so a
# transcript shows what was decided; any failure of this script itself is
# non-zero and therefore never authorizes action.
#
# Evidence classes:
#   process <pid>
#       Queries the pid directly (kill -0, then a targeted `ps -p` for the
#       EPERM case) — a per-pid syscall-backed query, never a scraped process
#       LISTING, which is exactly the truncation-prone source the incident
#       implicates. <pid> is a positive integer, no leading zero, <=10 digits.
#   tmux-window <session> <window>
#       Three probes, all against the caller's tmux server: `ls` (server
#       health — an unreachable server is unknown, never dead), `has-session`
#       (a healthy server is authoritative for its sessions: absent -> dead),
#       `list-windows` (window absent from the authoritative listing -> dead;
#       <window> matches either the #{window_id} or #{window_name} field
#       exactly). Session/window tokens are validated against the
#       orchestrate-relay.sh tmux charset before any `-t` interpolation, and
#       targets use the exact-match `=` prefix.
#
# Adding an evidence class for a new backend extends this wrapper; per-
# mechanism staleness heuristics stay forbidden (D-5).
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling). All
# input is data; no eval (REQ-K1.5). Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

usage() {
  echo "usage: fleet-death-evidence.sh process <pid> | tmux-window <session> <window>" >&2
}

verdict() {
  printf '%s\n' "$1"
  case "$1" in
    dead) exit 0 ;;
    alive) exit 1 ;;
    unknown) exit 3 ;;
  esac
}

class="${1:-}"
case "$class" in
  process | tmux-window) ;;
  timeout | silence | stale | staleness | heartbeat | heartbeat-age | idle-time)
    echo "fleet-death-evidence: '$class' is not positive evidence of death (REQ-A1.7): a timeout or silent heartbeat proves lost observability, not death — refusing" >&2
    exit 2
    ;;
  *)
    usage
    exit 2
    ;;
esac
shift

case "$class" in
  process)
    pid="${1:-}"
    if [ "$#" -ne 1 ]; then
      usage
      exit 2
    fi
    # A positive integer, no leading zero (kill -0 0 would signal the whole
    # process group), bounded to 10 digits so the token can never overflow the
    # tools it reaches.
    case "$pid" in
      "" | *[!0-9]* | 0*)
        echo "fleet-death-evidence: invalid pid '$pid' (a positive integer, no leading zero)" >&2
        exit 2
        ;;
    esac
    if [ "${#pid}" -gt 10 ]; then
      echo "fleet-death-evidence: invalid pid '$pid' (too long)" >&2
      exit 2
    fi
    # kill -0 succeeds when the process exists and is signalable: alive.
    if kill -0 "$pid" 2>/dev/null; then
      verdict alive
    fi
    # kill -0 can also fail with EPERM on a live process owned by another
    # user; disambiguate with a TARGETED ps query (0 = found, 1 = not found —
    # a per-pid lookup, not a listing scan). Any other ps outcome is a broken
    # query mechanism: unknown, never dead.
    ps_rc=0
    ps -p "$pid" >/dev/null 2>&1 || ps_rc=$?
    case "$ps_rc" in
      0) verdict alive ;;
      1) verdict dead ;;
      *)
        echo "fleet-death-evidence: ps -p exited $ps_rc — lost observability, refusing to report death" >&2
        verdict unknown
        ;;
    esac
    ;;
  tmux-window)
    session="${1:-}"
    window="${2:-}"
    if [ "$#" -ne 2 ]; then
      usage
      exit 2
    fi
    # The orchestrate-relay.sh tmux handle discipline: empty, a leading dash
    # (option injection), over-length, or anything outside the conservative
    # charset is refused before the token reaches a `-t` target.
    for tok in "$session" "$window"; do
      case "$tok" in
        "" | -*)
          echo "fleet-death-evidence: refusing malformed tmux token" >&2
          exit 2
          ;;
        *[!A-Za-z0-9_@%.-]*)
          echo "fleet-death-evidence: refusing malformed tmux token" >&2
          exit 2
          ;;
      esac
      if [ "${#tok}" -gt 128 ]; then
        echo "fleet-death-evidence: refusing over-length tmux token" >&2
        exit 2
      fi
    done
    if ! command -v tmux >/dev/null 2>&1; then
      echo "fleet-death-evidence: no tmux binary on PATH — lost observability, refusing to report death" >&2
      verdict unknown
    fi
    # Probe 1: server health. An unreachable server (dead or wrong socket) is
    # the 2026-06-12 scenario — lost observability, never dead.
    if ! tmux ls >/dev/null 2>&1; then
      echo "fleet-death-evidence: tmux server unreachable — lost observability, refusing to report death" >&2
      verdict unknown
    fi
    # Probe 2: session presence. A healthy server is authoritative for its
    # own sessions — but `has-session` exits non-zero identically for
    # "session absent" and "no server reachable", and the server can die
    # between probe 1 and this call (the same mid-sequence race the
    # 2026-06-12 incident encodes). So a has-session failure is positive
    # evidence only if the server is STILL healthy when re-verified;
    # otherwise observability was lost mid-sequence: unknown, never dead.
    if ! tmux has-session -t "=$session" >/dev/null 2>&1; then
      if tmux ls >/dev/null 2>&1; then
        verdict dead
      fi
      echo "fleet-death-evidence: tmux server lost between probes — lost observability, refusing to report death" >&2
      verdict unknown
    fi
    # Probe 3: the window in the authoritative listing, matched exactly
    # against the id or name field. A listing failure after the session probe
    # succeeded is a race or a broken query: unknown, never dead.
    listing=$(tmux list-windows -t "=$session" -F '#{window_id}	#{window_name}' 2>/dev/null) || {
      echo "fleet-death-evidence: tmux list-windows failed after has-session succeeded — refusing to report death" >&2
      verdict unknown
    }
    found=0
    old_ifs=$IFS
    IFS='
'
    for line in $listing; do
      wid=${line%%	*}
      wname=${line#*	}
      if [ "$window" = "$wid" ] || [ "$window" = "$wname" ]; then
        found=1
        break
      fi
    done
    IFS=$old_ifs
    if [ "$found" -eq 1 ]; then
      verdict alive
    fi
    verdict dead
    ;;
esac
