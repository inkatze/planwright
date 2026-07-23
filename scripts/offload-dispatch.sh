#!/bin/sh
# offload-dispatch.sh — the /offload dispatch primitive (execution-backends
# Task 6; D-1, REQ-C1.5).
#
# /offload (skills/offload/SKILL.md) selects a rung per the work-placement
# axioms (doctrine/work-placement.md) and dispatches through the backend seam.
# This script is the seam's shell-drivable half: it performs the dispatch for
# the rungs a script can drive and emits the standardized WORKER REPORT — the
# handle plus an observe/attach hint appropriate to the selected backend, per
# its advertised set in the capability contract
# (doctrine/backend-capability-contract.md). A rung with no observe surface
# reports that FACT (act on the completion signal), never an invented hint;
# a failed dispatch produces a visible failure report and a nonzero exit,
# never a silent drop (REQ-C1.5).
#
# Subcommands:
#   dispatch <backend> <prompt-file>
#       Dispatch the petition in <prompt-file> to <backend> and emit the
#       report. Drivable rungs:
#         tmux   — `tmux new-window -d` running an interactive `claude` worker
#                  in the caller's cwd; the window id is the handle. The
#                  petition travels as a FILE READ inside the spawned shell
#                  (`cat` of a fixed argv path), never spliced into the
#                  command line, and no send-keys path exists here (the
#                  never-impersonate discipline, orchestrate-relay.sh).
#         print  — spawn deferred to the human: print the exact launch
#                  command; no process exists until the human runs it.
#       Visibly refused (exit 2, diagnostic on stderr): `subagent` (harness-
#       native — the skill dispatches via its harness Agent tool, then calls
#       `report`), `in-session` (inline work, nothing to dispatch), and the
#       not-yet-drivable contract rows `stream-json-persistent` /
#       `headless-oneshot` (their dispatch support lands with execution-
#       backends Tasks 3-4).
#
#   report <backend> <handle>
#       Emit the standardized report for an already-dispatched worker (the
#       harness-native rungs, or a re-report of a known handle). Backends:
#       tmux, subagent.
#
# Report shape: TAB-separated `key<TAB>value` lines —
#   status    dispatched | prepared | failed
#   backend   <name>
#   handle    <handle>  (or the no-process fact for `print`)
#   observe   <read command, or the no-observe-surface fact>
#   attach    <attach hint, or the not-attachable fact>
#   launch    <exact command>            (print only)
#   reason    <failure reason>           (failed only)
#
# The interactive `claude` launches here are not `-p`-family sites, so the
# non-`--bare` launch pin (REQ-A1.5, D-12) does not apply to this script.
#
# Exit codes: 0 success; 1 dispatch failed (failure report emitted); 2 usage /
# hostile input / refused backend / unsafe prompt file.
#
# Portable POSIX sh + coreutils (bash 3.2 / BSD compatible): no eval, input
# treated as data only (REQ-K1.5). Pathname expansion is disabled (set -f) so
# a token like `*` is taken literally and refused by the grammar, never
# expanded.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=offload-dispatch

# Resolve this script's directory so the sibling echo-safety helper is found
# regardless of the caller's working directory.
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
echo_safety="$script_dir/echo-safety.sh"
if [ ! -r "$echo_safety" ]; then
  echo "$me: required helper $echo_safety missing or not readable" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$echo_safety"

# A literal newline, for the prompt-file path safety check below.
nl='
'

usage() {
  echo "$me: usage: $me <dispatch <backend> <prompt-file> | report <backend> <handle>>" >&2
}

# Per-backend handle grammar, mirroring orchestrate-relay.sh: input is DATA —
# a case-glob whitelist, never evaluated. Empty, leading-dash (option
# injection), and over-length tokens are refused first; then the per-backend
# charset, which excludes whitespace, quotes, `$`, backtick, `;` `|` `&`,
# parentheses, redirects, glob metacharacters, and the newline.
valid_handle() {
  case "$2" in
    '') return 1 ;;
    -*) return 1 ;;
  esac
  [ "${#2}" -le 128 ] || return 1
  case "$1" in
    tmux)
      case "$2" in
        *[!A-Za-z0-9_@%:./-]*) return 1 ;;
      esac
      ;;
    subagent)
      case "$2" in
        *[!A-Za-z0-9_.-]*) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
  return 0
}

# A prompt file must be a readable, non-empty regular file whose path is safe
# to place inside a single-quoted shell literal in an emitted command (no
# single quote, no newline, no control byte) — mirroring orchestrate-relay's
# message-file check. The skill writes the petition to a temp file it
# controls; this guards the emission boundary regardless.
valid_promptfile() {
  [ -f "$1" ] || return 1
  [ -r "$1" ] || return 1
  [ -s "$1" ] || return 1
  case "$1" in
    *"'"*) return 1 ;;
    *"$nl"*) return 1 ;;
  esac
  [ "$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237')" = "$1" ] || return 1
  return 0
}

reject_handle() {
  echo "$me: refusing invalid $1 handle (validated before use, never interpolated)" >&2
  exit 2
}

# Emit the observe/attach hint pair for a backend, per its advertised set in
# the capability contract: tmux advertises can_observe=true and
# interactive=true; subagent advertises neither, so its report carries the
# facts, not invented hints.
emit_hints() {
  case "$1" in
    tmux)
      printf 'observe\ttmux capture-pane -p -t %s\n' "$2"
      printf 'attach\ttmux select-window -t %s  (from outside tmux: tmux attach)\n' "$2"
      ;;
    subagent)
      printf 'observe\tnone: no observe surface on this rung; act on the completion signal\n'
      printf 'attach\tnone: in-harness worker, not human-attachable\n'
      ;;
  esac
}

cmd_report() {
  backend=$1
  handle=$2
  case "$backend" in
    tmux | subagent) ;;
    *)
      echo "$me: report: unknown backend '$(sanitize_printable "$backend" "(unprintable)")'" >&2
      exit 2
      ;;
  esac
  valid_handle "$backend" "$handle" || reject_handle "$backend"
  printf 'status\tdispatched\n'
  printf 'backend\t%s\n' "$backend"
  printf 'handle\t%s\n' "$handle"
  emit_hints "$backend" "$handle"
}

cmd_dispatch() {
  backend=$1
  promptfile=$2
  case "$backend" in
    tmux | print) ;;
    subagent)
      echo "$me: dispatch: subagent is harness-native — dispatch via the harness Agent tool, then run: $me report subagent <handle>" >&2
      exit 2
      ;;
    in-session)
      echo "$me: dispatch: in-session is inline work in the caller's own session — nothing to dispatch" >&2
      exit 2
      ;;
    stream-json-persistent | headless-oneshot)
      echo "$me: dispatch: '$backend' is not yet drivable — its dispatch support lands with execution-backends Tasks 3-4" >&2
      exit 2
      ;;
    *)
      echo "$me: dispatch: unknown backend '$(sanitize_printable "$backend" "(unprintable)")'" >&2
      exit 2
      ;;
  esac
  if ! valid_promptfile "$promptfile"; then
    echo "$me: dispatch: prompt file missing, empty, unreadable, or unsafe: '$(sanitize_printable "$promptfile" "(unprintable)")'" >&2
    exit 2
  fi

  case "$backend" in
    print)
      printf 'status\tprepared\n'
      printf 'backend\tprint\n'
      printf 'handle\tnone: no process exists until the human runs the launch command\n'
      printf "launch\tclaude \"\$(cat -- '%s')\"\n" "$promptfile"
      printf 'observe\tnone: spawn deferred to the human\n'
      printf 'attach\trun the launch command in your own terminal\n'
      return 0
      ;;
  esac

  # tmux: spawn a detached window running an interactive claude worker in the
  # caller's cwd. The petition is read from the prompt file INSIDE the spawned
  # shell via a fixed argv path — the content never appears on this command
  # line — and the printed window id is the stable handle.
  # shellcheck disable=SC2016 # single quotes are deliberate: $1 expands in the
  # SPAWNED shell (argv-passed prompt path), never here — no content splicing.
  handle=$(tmux new-window -d -P -F '#{window_id}' -n offload -c "$PWD" \
    /bin/sh -c 'exec claude "$(cat -- "$1")"' offload-worker "$promptfile" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'status\tfailed\n'
    printf 'backend\ttmux\n'
    printf 'reason\ttmux new-window exited %s: %s\n' "$rc" "$(sanitize_printable "$handle" "(unprintable)")"
    echo "$me: dispatch failed: tmux new-window exited $rc" >&2
    exit 1
  fi
  if ! valid_handle tmux "$handle"; then
    printf 'status\tfailed\n'
    printf 'backend\ttmux\n'
    printf 'reason\ttmux returned an unusable window id\n'
    echo "$me: dispatch failed: tmux returned an unusable window id: '$(sanitize_printable "$handle" "(unprintable)")'" >&2
    exit 1
  fi
  printf 'status\tdispatched\n'
  printf 'backend\ttmux\n'
  printf 'handle\t%s\n' "$handle"
  emit_hints tmux "$handle"
}

[ "$#" -ge 1 ] || {
  usage
  exit 2
}
sub=$1
shift
case "$sub" in
  dispatch)
    [ "$#" -eq 2 ] || {
      usage
      exit 2
    }
    cmd_dispatch "$1" "$2"
    ;;
  report)
    [ "$#" -eq 2 ] || {
      usage
      exit 2
    }
    cmd_report "$1" "$2"
    ;;
  *)
    usage
    exit 2
    ;;
esac
