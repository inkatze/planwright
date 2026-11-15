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
#       EPERM case, or procfs where ps has no -p) — a per-pid query, never a
#       scraped process LISTING, which is exactly the truncation-prone source the incident
#       implicates. <pid> is a positive integer, no leading zero, <=10 digits.
#   tmux-window <session> <window>
#       Three probes, all against the caller's tmux server: `ls` (server
#       health — an unreachable server is unknown, never dead), `has-session`
#       (a healthy server is authoritative for its sessions: absent -> dead),
#       `list-windows` (window absent from the authoritative listing -> dead;
#       <window> matches either the #{window_id} or #{window_name} field
#       exactly). A <window> shaped like an id (`@<n>`) is looked up across
#       every session instead, by id or name, with no session probe: an id
#       names its window for the server's lifetime, so a renamed session cannot
#       read as its death. Session/window tokens are validated against a conservative
#       subset of the orchestrate-relay.sh tmux charset (no `:` or `/`: the
#       relay validates combined session:window targets, while the separate
#       per-token arguments here need neither) before any `-t` interpolation,
#       and targets use the exact-match `=` prefix. With --in-session the
#       session probe decides for an id too: a handle written before the
#       server pin below may name an id a restarted server reissued.
#   tmux-window <session> <window> <server> <name>
#       A handle pinned to the server that issued its id (`<pid>.<start
#       time>`, scripts/tmux-identity-lib.sh) and to the window's name. Dead
#       once the running server is another, or the id is absent, or it
#       carries another name; alive only when all three hold. The session is
#       not consulted, so a renamed session still reads alive.
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

# Builtins only up to the probes: a PATH without the tools must still reach
# the no-tmux verdict.
case $0 in
  */*) script_dir=${0%/*} ;;
  *) script_dir=. ;;
esac
script_dir=$(cd "$script_dir" && pwd) || exit 2
if [ ! -r "$script_dir/tmux-identity-lib.sh" ]; then
  echo "fleet-death-evidence: tmux-identity-lib.sh is missing or unreadable (broken install)" >&2
  exit 2
fi
# shellcheck source=scripts/tmux-identity-lib.sh
. "$script_dir/tmux-identity-lib.sh"

usage() {
  echo "usage: fleet-death-evidence.sh process <pid> | tmux-window [--in-session] <session> <window> | tmux-window <session> <window> <server> <name>" >&2
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
    printf '%s\n' "fleet-death-evidence: '$class' is not positive evidence of death (REQ-A1.7): a timeout or silent heartbeat proves lost observability, not death — refusing" >&2
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
    # tools it reaches. The refused token is never echoed — it is raw argv and
    # can carry control bytes (the tmux-token refusals below set the style).
    case "$pid" in
      "" | *[!0-9]* | 0*)
        echo "fleet-death-evidence: refusing malformed pid token (a positive integer, no leading zero)" >&2
        exit 2
        ;;
    esac
    if [ "${#pid}" -gt 10 ]; then
      echo "fleet-death-evidence: refusing over-length pid token" >&2
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
    # busybox ps has no -p and exits 1 on the option alone, the same status
    # as not-found; it rejects this shell's own pid too, which is how it is
    # told apart. There procfs answers, and with no procfs nothing can.
    if [ "$ps_rc" = 1 ] && ! ps -p "$$" >/dev/null 2>&1; then
      if [ -d "/proc/$$" ]; then
        [ -d "/proc/$pid" ] && ps_rc=0
      else
        printf '%s\n' "fleet-death-evidence: ps has no -p and there is no procfs to ask — lost observability, refusing to report death" >&2
        verdict unknown
      fi
    fi
    case "$ps_rc" in
      0) verdict alive ;;
      1) verdict dead ;;
      *)
        printf '%s\n' "fleet-death-evidence: ps -p exited $ps_rc — lost observability, refusing to report death" >&2
        verdict unknown
        ;;
    esac
    ;;
  tmux-window)
    # --in-session: a handle recorded before the server pin, whose id may
    # have been reissued by a restarted server, is judged in its recorded
    # session only.
    in_session=0
    if [ "${1:-}" = --in-session ]; then
      in_session=1
      shift
    fi
    session="${1:-}"
    window="${2:-}"
    server=''
    wname=''
    case $# in
      2) ;;
      4)
        server=$3
        wname=$4
        ;;
      *)
        usage
        exit 2
        ;;
    esac
    # The orchestrate-relay.sh tmux handle discipline (charset narrowed to
    # single-name tokens; see the header): empty, a leading dash (option
    # injection), over-length, or anything outside the conservative charset
    # is refused before the token reaches a `-t` target.
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
    if [ "$#" -eq 4 ]; then
      if [ "$in_session" = 1 ] || ! tmux_valid_server "$server" || ! tmux_valid_name "$wname"; then
        echo "fleet-death-evidence: refusing a malformed tmux server pin" >&2
        exit 2
      fi
      case $window in
        @*[!0-9]* | @ | [!@]*)
          echo "fleet-death-evidence: a pinned handle names its window by id" >&2
          exit 2
          ;;
      esac
    fi
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
    # A pinned handle: the server that issued the id, the id, and the name it
    # gave the window must all still hold. A server started since issued
    # nothing this handle names.
    if [ "$#" -eq 4 ]; then
      now=$(tmux_server_id) || {
        echo "fleet-death-evidence: tmux did not say which server answers — refusing to report death" >&2
        verdict unknown
      }
      if [ "$now" != "$server" ]; then
        printf '%s\n' "fleet-death-evidence: $window was issued by an earlier tmux server" >&2
        verdict dead
      fi
      pr_rc=0
      tmux_pin_read window "$window" || pr_rc=$?
      case $pr_rc in
        0)
          if [ "$TP_NOW" = "$server/$window/$wname" ]; then
            verdict alive
          fi
          printf '%s\n' "fleet-death-evidence: $window no longer carries the server and name it was recorded with" >&2
          verdict dead
          ;;
        1)
          if tmux ls >/dev/null 2>&1; then
            verdict dead
          fi
          ;;
      esac
      printf '%s\n' "fleet-death-evidence: tmux did not answer for $window — refusing to report death" >&2
      verdict unknown
    fi
    # A window id (`@<n>`) names one window for the server's lifetime, wherever
    # it lives: a renamed session, or the window moved to another, leaves the
    # recorded session name absent while the window runs on. So an id is
    # looked up across the server, and the session probe below, which would
    # read that rename as death, is not consulted for it. A window may also be
    # NAMED `@<n>`, so the token matches a name as well as an id; a match
    # anywhere only ever reads as alive, never as a death. Under --in-session
    # the session probe decides instead.
    case $in_session:$window in
      1:* | *:@*[!0-9]* | *:@) ;;
      *:@*)
        listing=$(tmux list-windows -a -F '#{window_id} #{window_name}' 2>/dev/null) || {
          echo "fleet-death-evidence: tmux list-windows failed after the server answered — refusing to report death" >&2
          verdict unknown
        }
        old_ifs=$IFS
        IFS='
'
        for line in $listing; do
          if [ "${line%% *}" = "$window" ] || [ "${line#* }" = "$window" ]; then
            IFS=$old_ifs
            verdict alive
          fi
        done
        IFS=$old_ifs
        if tmux ls >/dev/null 2>&1; then
          verdict dead
        fi
        echo "fleet-death-evidence: tmux server lost between probes — lost observability, refusing to report death" >&2
        verdict unknown
        ;;
    esac
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
    listing=$(tmux list-windows -t "=$session" -F '#{window_id} #{window_name}' 2>/dev/null) || {
      echo "fleet-death-evidence: tmux list-windows failed after has-session succeeded — refusing to report death" >&2
      verdict unknown
    }
    found=0
    old_ifs=$IFS
    IFS='
'
    for line in $listing; do
      wid=${line%% *}
      lname=${line#* }
      if [ "$window" = "$wid" ] || [ "$window" = "$lname" ]; then
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
