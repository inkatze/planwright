#!/bin/sh
# fleet-tower-marker.sh — the mode-aware tower runtime marker store (Task 3:
# D-4, REQ-A1.5, REQ-A1.6).
#
# D-4 recovers an ungracefully-dead tower differently by MODE: an unattended
# (`--watch`) tower is relaunched fresh by the external cron watchdog
# (fleet-tower-watchdog.sh); an interactively-led tower is signposted to the
# human as an exact `claude --resume <session-id>` command at the next
# `SessionStart` (fleet-tower-signpost.sh). Both mechanisms key off ONE
# durable record — this marker — because the mode split is only as reliable
# as its record: a missing or ambiguous marker means NEITHER recovery path
# may fire (kickoff risk row 7 — the marker is itself subject to the
# REQ-A1.7 fail-closed posture, so two recovery actors can never both act on
# one dead tower).
#
# STORAGE. One single-row TSV file per spec under the cross-spec fleet home
# (fleet-state.sh root, orchestration-fleet D-11): <fleet-home>/towers/<spec>
#   <spec>\t<mode>\t<pid>\t<session_id>\t<tmux_session>\t<checkout>\t<epoch>
# `session_id` and `tmux_session` are `-` when unknown. Writes serialize
# through fleet-state.sh's existing cross-spec advisory lock (no second lock
# primitive, REQ-G1.3) and land via temp+RENAME, so a lockless reader (the
# SessionStart signpost hook) always sees a complete row, never a torn one.
# The epoch is stamped under the lock (the fleet-state register discipline).
#
# WHO WRITES. The tower itself records at `--watch` loop start (and its
# continue-as-new successor re-records); the watchdog re-records after a
# relaunch; the human (or a graceful tower exit) clears. The signpost NEVER
# clears (REQ-A1.6: no auto-discard — the human chooses).
#
# INPUT HYGIENE (REQ-F1.1; kickoff risk row 22). Workers share the fleet
# state area, so every field is validated BEFORE write: the spec id against
# the overlay identifier grammar, the pid as a bounded positive integer, the
# session id against the UUID shape `claude --resume` accepts (a surfaced
# resume command must never carry a token that matches no real session), the
# tmux session name against the death-evidence tmux charset, and the
# checkout as an existing absolute directory free of control bytes. A
# refused field is never echoed raw.
#
# Usage:
#   fleet-tower-marker.sh record <spec> --mode unattended|interactive
#       --pid <pid> --checkout <dir> [--session-id <uuid>]
#       [--tmux-session <name>]
#   fleet-tower-marker.sh read <spec>     print the row; exit 1 when absent.
#   fleet-tower-marker.sh clear <spec>    remove the marker (idempotent).
#
# Exit codes: 0 success; 1 read-absent; 2 usage error, unresolvable home,
#   refused hostile input, or a filesystem/lock error (fail closed).
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling): `date
# +%s`, mktemp, a fractional `sleep` (the lock retry, as the sibling fleet
# scripts use). No eval, no jq (REQ-K1.5). All input is data. Pathname
# expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# The canonical echo-discipline sanitizer (doctrine/security-posture.md),
# sourced as the sibling fleet scripts do; a missing helper is a broken
# install.
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

FS="$script_dir/fleet-state.sh"

usage() {
  echo "usage: fleet-tower-marker.sh record <spec> --mode unattended|interactive --pid <pid> --checkout <dir> [--session-id <uuid>] [--tmux-session <name>] | read <spec> | clear <spec>" >&2
}

# The overlay identifier grammar (fleet-state.sh valid_identifier): a kebab
# token, no uppercase, no traversal segments, no leading dash, at most 64
# chars — the spec id reaches a path, so this is load-bearing containment.
valid_spec() {
  vs_v=$1
  case $vs_v in
    "" | -* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#vs_v}" -le 64 ]
}

# A positive integer, no leading zero, <=10 digits (the
# fleet-death-evidence.sh pid grammar — this pid feeds that predicate).
valid_pid() {
  vp_v=$1
  case $vp_v in
    "" | *[!0-9]* | 0*) return 1 ;;
  esac
  [ "${#vp_v}" -le 10 ]
}

# The session-id shape `claude --resume` accepts: a UUID (8-4-4-4-12 hex).
# Strict on purpose (kickoff risk row 22): a marker field that fails this
# never reaches a surfaced resume command.
valid_session_id() {
  vsi_v=$1
  case $vsi_v in
    *[!0-9a-fA-F-]*) return 1 ;;
    ????????-????-????-????-????????????) ;;
    *) return 1 ;;
  esac
  # The glob pins length 36 and dashes at the four UUID positions; ? admits
  # '-' too, so require exactly 32 non-dash (hex, per the charset case) chars.
  [ "$(printf '%s' "$vsi_v" | tr -d - | wc -c | tr -d ' ')" -eq 32 ]
}

# The tmux session-name charset fleet-death-evidence.sh validates before a
# `-t` interpolation: no leading dash, conservative token set, <=128.
valid_tmux_session() {
  vts_v=$1
  case $vts_v in
    "" | -* | *[!A-Za-z0-9_@%.-]*) return 1 ;;
  esac
  [ "${#vts_v}" -le 128 ]
}

# The control-free text grammar (fleet-attention.sh valid_text): non-empty,
# <=512 bytes, no C0/DEL/C1 — applied to the checkout path on top of its
# absolute-existing-directory requirement, so a marker row can neither tear
# (tab/newline) nor drive a terminal at render time.
valid_text() {
  vt_v=$1
  [ -n "$vt_v" ] || return 1
  [ "${#vt_v}" -le 512 ] || return 1
  [ "$(sanitize_printable "$vt_v")" = "$vt_v" ]
}

resolve_home() {
  rh_root=$("$FS" root) || return 2
  printf '%s' "$rh_root"
}

HOLD_LOCK=0
# Release on ANY exit, signals included (the fleet-attention.sh trap
# discipline): a SIGINT/SIGTERM mid-critical-section must not leave the
# shared cross-spec lock held until the stale-break threshold.
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
        echo "fleet-tower-marker: cannot acquire the fleet lock (fleet-state exit $al_rc)" >&2
        return 2
        ;;
    esac
    al_tries=$((al_tries + 1))
    sleep 0.02
  done
  echo "fleet-tower-marker: gave up acquiring the fleet lock after contention" >&2
  return 2
}
release_lock() {
  if [ "$HOLD_LOCK" = 1 ]; then
    "$FS" unlock >/dev/null 2>&1 || true
    HOLD_LOCK=0
  fi
}

if [ "$#" -lt 2 ]; then
  usage
  exit 2
fi
cmd=$1
spec=$2
shift 2

if ! valid_spec "$spec"; then
  echo "fleet-tower-marker: refusing malformed spec id '$(sanitize_printable "$spec" "(unprintable spec)")'" >&2
  exit 2
fi

case "$cmd" in
  record)
    mode=""
    pid=""
    checkout=""
    session_id="-"
    tmux_session="-"
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --mode)
          mode="${2:-}"
          shift 2 || {
            usage
            exit 2
          }
          ;;
        --pid)
          pid="${2:-}"
          shift 2 || {
            usage
            exit 2
          }
          ;;
        --checkout)
          checkout="${2:-}"
          shift 2 || {
            usage
            exit 2
          }
          ;;
        --session-id)
          session_id="${2:-}"
          shift 2 || {
            usage
            exit 2
          }
          ;;
        --tmux-session)
          tmux_session="${2:-}"
          shift 2 || {
            usage
            exit 2
          }
          ;;
        *)
          usage
          exit 2
          ;;
      esac
    done
    case "$mode" in
      unattended | interactive) ;;
      *)
        echo "fleet-tower-marker: refusing mode '$(sanitize_printable "$mode" "(unprintable mode)")' — the D-4 recovery split admits only 'unattended' or 'interactive'" >&2
        exit 2
        ;;
    esac
    if ! valid_pid "$pid"; then
      echo "fleet-tower-marker: refusing malformed pid token (a positive integer, no leading zero)" >&2
      exit 2
    fi
    if [ "$session_id" != "-" ] && ! valid_session_id "$session_id"; then
      echo "fleet-tower-marker: refusing malformed session id (a UUID, or omit the flag)" >&2
      exit 2
    fi
    if [ "$tmux_session" != "-" ] && ! valid_tmux_session "$tmux_session"; then
      echo "fleet-tower-marker: refusing malformed tmux session name" >&2
      exit 2
    fi
    case "$checkout" in
      /*) ;;
      *)
        echo "fleet-tower-marker: refusing checkout path (an absolute path to an existing directory)" >&2
        exit 2
        ;;
    esac
    if ! valid_text "$checkout"; then
      echo "fleet-tower-marker: refusing checkout path (<=512 bytes, no control characters)" >&2
      exit 2
    fi
    # Canonicalize (symlink-resolved) so the signpost's cwd comparison is a
    # byte comparison of two canonical paths; a nonexistent dir is refused
    # here rather than surfacing later as a resume command pointing nowhere.
    checkout=$(cd "$checkout" 2>/dev/null && pwd -P) || {
      echo "fleet-tower-marker: refusing checkout path (an absolute path to an existing directory)" >&2
      exit 2
    }
    if ! valid_text "$checkout"; then
      echo "fleet-tower-marker: refusing checkout path (canonical form carries a control byte or exceeds 512 bytes)" >&2
      exit 2
    fi
    root=$(resolve_home) || exit 2
    towers_dir="$root/towers"
    # Idempotent, order-independent: created BEFORE the lock to keep the
    # contended critical section short (the fleet-audit discipline).
    if ! mkdir -p "$towers_dir" 2>/dev/null; then
      echo "fleet-tower-marker: cannot create the towers dir $towers_dir" >&2
      exit 2
    fi
    acquire_lock || exit 2
    # Epoch stamped UNDER the lock (commit time, not invocation time).
    ts=$(date +%s)
    case $ts in
      "" | *[!0-9]*)
        echo "fleet-tower-marker: cannot read the clock" >&2
        exit 2
        ;;
    esac
    tmpfile=$(mktemp "$towers_dir/.marker.XXXXXX") || {
      echo "fleet-tower-marker: cannot create a temp file in $towers_dir" >&2
      exit 2
    }
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$spec" "$mode" "$pid" "$session_id" "$tmux_session" "$checkout" "$ts" \
      >"$tmpfile" || {
      rm -f "$tmpfile"
      echo "fleet-tower-marker: cannot write the marker row" >&2
      exit 2
    }
    if ! mv -f "$tmpfile" "$towers_dir/$spec" 2>/dev/null; then
      rm -f "$tmpfile"
      echo "fleet-tower-marker: cannot install the marker row" >&2
      exit 2
    fi
    release_lock
    exit 0
    ;;
  read)
    if [ "$#" -ne 0 ]; then
      usage
      exit 2
    fi
    root=$(resolve_home) || exit 2
    marker="$root/towers/$spec"
    # Lockless read is safe: every write lands via rename, so this either
    # sees the complete old row or the complete new one.
    [ -f "$marker" ] || exit 1
    cat "$marker" || exit 2
    exit 0
    ;;
  clear)
    if [ "$#" -ne 0 ]; then
      usage
      exit 2
    fi
    root=$(resolve_home) || exit 2
    marker="$root/towers/$spec"
    [ -e "$marker" ] || exit 0
    acquire_lock || exit 2
    rm -f "$marker" || {
      echo "fleet-tower-marker: cannot remove the marker" >&2
      exit 2
    }
    release_lock
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
esac
