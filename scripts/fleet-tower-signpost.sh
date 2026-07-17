#!/bin/sh
# fleet-tower-signpost.sh — the SessionStart (`source: "startup"`) crash-
# recovery signpost for interactively-led towers (Task 3: D-4, REQ-A1.6).
#
# WHY A SIGNPOST, NOT A RELAUNCH. An interactively-led tower's value is the
# human's actual in-progress conversation, which no disk rebuild recovers —
# but `claude --resume <session-id>` does, even after a hard crash. Only the
# human can meaningfully continue that conversation, so this hook SURFACES
# the exact resume command and stops: it never auto-resumes and never
# discards the marker (the human chooses; a cleared marker is the human's
# act, via `scripts/fleet-tower-marker.sh clear <spec>`). The unattended
# arm of D-4 (cron relaunch) is fleet-tower-watchdog.sh's; the marker's
# mode field keeps the two mutually exclusive (kickoff risk row 7): this
# hook acts on `interactive` markers only.
#
# WHEN IT FIRES. Wired in hooks/hooks.json under SessionStart with matcher
# "startup" (a fresh `claude` start in a directory — exactly when a human
# is back at a checkout whose previous tower may have died with the
# terminal). It re-checks a provided stdin `source` field defensively and
# stays silent for non-startup sources. `claude --resume` must run from the
# directory the dead session started in (confirmed against the sessions
# doc), so markers are matched by canonical checkout path equality with the
# starting session's project dir.
#
# WHAT COUNTS AS ORPHANED. Only a marker whose recorded pid is POSITIVELY
# dead per the shared D-5 predicate (fleet-death-evidence.sh). An alive pid
# is a running tower; an `unknown` verdict is lost observability — in both
# cases the hook stays silent rather than signposting a session that may
# still be live (REQ-A1.7's fail-closed posture, applied to a read-only
# surface).
#
# OUTPUT DISCIPLINE (risk row 22; REQ-A1.6 artifact hygiene). Plain stdout
# (added to the session's context per the hooks doc — no jq dependency).
# Every surfaced field is re-validated on the way OUT: the session id must
# match the strict UUID shape or no resume command is printed (a surfaced
# command must never carry a token matching no real session), and text
# fields pass the echo-safety sanitizer, so a hand-corrupted store row can
# neither drive the terminal nor smuggle shell text into context.
#
# HOOK SAFETY. Always exits 0 and stays silent on any resolution failure: a
# broken fleet home must never break somebody's session startup. Not gated
# by fleet_daemon_pause: the gate pauses daemon ACTIONS (cleanup, restart,
# throttle); this hook performs none — pausing it would hide the one
# recovery breadcrumb exactly when an operator is debugging.
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling). No
# eval, no jq (REQ-K1.5). All input is data. Pathname expansion is disabled
# (set -f) except around the explicit marker-store glob.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 0

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" 2>/dev/null || exit 0

# Defensive source check: the hooks.json matcher already filters to
# "startup", but a provided stdin payload naming another source wins. The
# probe is a crude no-jq scan; an absent or unrecognizable payload proceeds
# (the matcher is the authority).
if [ ! -t 0 ]; then
  stdin_payload=$(cat 2>/dev/null || printf '')
  case "$stdin_payload" in
    *'"source"'*)
      case "$stdin_payload" in
        *'"startup"'*) ;;
        *) exit 0 ;;
      esac
      ;;
  esac
fi

cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
cwd=$(cd "$cwd" 2>/dev/null && pwd -P) || exit 0

root=$("$script_dir/fleet-state.sh" root 2>/dev/null) || exit 0
towers_dir="$root/towers"
[ -d "$towers_dir" ] || exit 0

FDE="$script_dir/fleet-death-evidence.sh"
[ -x "$FDE" ] || exit 0
TAB=$(printf '\t')

valid_session_id() {
  vsi_v=$1
  [ "${#vsi_v}" -eq 36 ] || return 1
  case $vsi_v in
    *[!0-9a-fA-F-]*) return 1 ;;
  esac
  vsi_rest=$vsi_v
  vsi_shape=""
  while [ -n "$vsi_rest" ]; do
    vsi_c=${vsi_rest%"${vsi_rest#?}"}
    vsi_rest=${vsi_rest#?}
    case $vsi_c in
      -) vsi_shape="$vsi_shape-" ;;
      *) vsi_shape="${vsi_shape}x" ;;
    esac
  done
  [ "$vsi_shape" = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" ]
}

# The marker-store scan needs one glob.
set +f
for marker in "$towers_dir"/*; do
  set -f
  [ -f "$marker" ] || continue
  # The backoff records share the dir under a suffix the spec-id grammar
  # cannot produce; field count keeps them (and any stray file) out too.
  case "$marker" in
    *.backoff) continue ;;
  esac
  row=$(cat "$marker" 2>/dev/null) || continue
  old_ifs=$IFS
  IFS=$TAB
  # shellcheck disable=SC2086
  set -- $row
  IFS=$old_ifs
  [ "$#" -eq 7 ] || continue
  m_spec=$1
  m_mode=$2
  m_pid=$3
  m_sid=$4
  m_checkout=$6
  [ "$m_mode" = interactive ] || continue
  [ "$m_checkout" = "$cwd" ] || continue
  # Re-validate stored fields on the way out (the store is shared; a
  # corrupt row is skipped as data, never surfaced).
  case "$m_spec" in
    "" | -* | *[!a-z0-9-]*) continue ;;
  esac
  case "$m_pid" in
    "" | *[!0-9]* | 0*) continue ;;
  esac
  ev_rc=0
  "$FDE" process "$m_pid" >/dev/null 2>&1 || ev_rc=$?
  [ "$ev_rc" -eq 0 ] || continue
  if ! valid_session_id "$m_sid"; then
    echo "fleet-tower-signpost: an orphaned interactive-tower marker for spec '$(sanitize_printable "$m_spec" "(spec)")' carries no valid session id; repair or clear it with scripts/fleet-tower-marker.sh" >&2
    continue
  fi
  printf 'planwright: an interactively-led tower for spec %s appears to have died (pid %s: positive evidence, no live process). Resume that conversation with:\n\n    claude --resume %s\n\n(run it from %s). Nothing was auto-resumed and the marker was kept; after resuming or abandoning it, clear it with: scripts/fleet-tower-marker.sh clear %s\n' \
    "$(sanitize_printable "$m_spec" "(spec)")" \
    "$m_pid" \
    "$m_sid" \
    "$(sanitize_printable "$cwd" "(checkout)")" \
    "$(sanitize_printable "$m_spec" "(spec)")"
done
set -f

exit 0
