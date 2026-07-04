#!/bin/sh
# orchestrate-relay.sh — inter-orchestrator COORDINATION relay/observe mechanics
# for /orchestrate and the meta-tower (orchestration-fleet Task 7; D-7,
# REQ-D1.2, REQ-D1.3, REQ-B1.7, REQ-A1.6).
#
# This is the scripts-level enforcement point behind
# doctrine/inter-orchestrator-coordination.md: the security-critical relay
# boundary productized from tribal tmux operator knowledge into a first-class,
# testable capability. A tower that needs to steer or observe a live, busy
# worker asks this script for the exact command to run, rather than
# hand-constructing one — so the never-impersonate discipline is enforced in one
# audited place instead of re-derived per relay.
#
# Subcommands:
#   validate-handle <backend> <handle>
#       Validate a worker/tower handle against the declared per-backend grammar
#       BEFORE it is ever used to target a worker (REQ-B1.7: handles parsed for
#       targeting are validated before use). Exit 0 valid, exit 2
#       invalid/hostile/usage. No stdout. The handle is DATA — validated by
#       case-glob, never evaluated — so a shell metacharacter, command
#       substitution, whitespace, an option-injection leading dash, or an
#       over-length token is refused, never interpolated.
#
#   relay-command <backend> <handle> <message-file>
#       Print the ATTRIBUTED, non-impersonating relay command for a live worker.
#       tmux: a buffer-paste delivery (`load-buffer`/`paste-buffer`) — NEVER a
#       `send-keys` path (REQ-D1.3: no impersonation of the worker's input). The
#       message is DATA: the emitted command reads the message FILE (`cat`),
#       never inlines its content, so message text is never spliced into the
#       command as code (REQ-B1.7: worker/tower output is data, no eval/expansion
#       path). The relay carries a fixed attribution header naming the tower
#       origin and target. subagent: harness-native — there is no screen-scrape
#       surface at all; empty stdout, exit 0 (the tower relays via its own prompt
#       queue). Exit 2 on an invalid handle, a missing/unsafe message file, an
#       unknown backend, or usage.
#
#   observe-command <backend> <handle>
#       Print the observe-in-flight status-read command (REQ-D1.3). tmux:
#       `capture-pane -p` — a read, never a write; the handle is validated first.
#       subagent: harness-native (completion/notification is the surface); empty
#       stdout, exit 0. Exit 2 on an invalid handle, an unknown backend, or usage.
#
# What this script NEVER does, by construction (REQ-B1.7, REQ-D1.3, D-7): it
# never emits a `send-keys` impersonation path, never answers a worker's harness
# permission prompt (it emits relay/observe commands only, never a
# prompt-answer), and never evaluates a handle or message. The tower owns
# `tasks.md` reconcile / dispatch / merged-worker cleanup; the relay never edits
# another tower's or a worker's branch state (REQ-D1.2 division of labor).
#
# Portable POSIX sh + coreutils (bash 3.2 / BSD compatible): no eval, no bashisms,
# input treated as data only (REQ-K1.5).
set -u

# Pin the C locale so the charset checks below mean exactly their ASCII range on
# every host (defensive; mirrors the sibling scripts).
LC_ALL=C
export LC_ALL
unset CDPATH

me=orchestrate-relay

# A literal newline, for the message-file path safety check below.
nl='
'

usage() {
  echo "$me: usage: $me <validate-handle|relay-command|observe-command> <backend> <handle> [<message-file>]" >&2
}

# Per-backend handle grammar. Input is DATA: a case-glob whitelist, evaluated by
# the shell's pattern matcher, never by `eval`. Common refusals first (empty,
# leading dash → option injection, over-length), then the per-backend charset.
# The tmux charset admits id sigils (@window, %pane), a numeric index, and
# session:window names over a conservative set; subagent is a stricter identifier
# (no sigils, colon, or slash). Every excluded character — whitespace, quotes,
# `$`, backtick, `;` `|` `&`, parentheses, redirects, glob metacharacters, and
# the newline — is thereby refused before the handle reaches a `-t` target.
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

# A message file must exist as a regular file and its path must be safe to place
# inside a single-quoted shell literal in the emitted command (no single quote,
# no newline). The tower writes the message to a temp file it controls; this
# guards the emission boundary regardless.
valid_msgfile() {
  [ -f "$1" ] || return 1
  case "$1" in
    *"'"*) return 1 ;;
    *"$nl"*) return 1 ;;
  esac
  return 0
}

reject_handle() {
  echo "$me: refusing invalid $1 handle (REQ-B1.7: validated before use)" >&2
  exit 2
}

sub=${1:-}
[ -n "$sub" ] || {
  usage
  exit 2
}
shift

case "$sub" in
  validate-handle)
    [ "$#" -eq 2 ] || {
      usage
      exit 2
    }
    valid_handle "$1" "$2" || exit 2
    exit 0
    ;;

  relay-command)
    [ "$#" -eq 3 ] || {
      usage
      exit 2
    }
    backend=$1
    handle=$2
    msg=$3
    case "$backend" in
      tmux)
        valid_handle tmux "$handle" || reject_handle tmux
        valid_msgfile "$msg" || {
          echo "$me: message file missing or path unsafe to relay: $msg" >&2
          exit 2
        }
        # Attributed buffer-paste delivery. The header is a fixed literal (tower
        # origin + target); the message body is `cat`'d from the file, so its
        # content is DATA and never enters the command as code. NEVER send-keys.
        printf '%s\n' "{ printf '%s\\n' '[planwright tower relay -> $handle]'; cat -- '$msg'; } | tmux load-buffer -b planwright-relay -"
        printf '%s\n' "tmux paste-buffer -b planwright-relay -t '$handle' -d"
        exit 0
        ;;
      subagent)
        valid_handle subagent "$handle" || reject_handle subagent
        echo "$me: subagent is harness-native; relay via the tower's prompt queue, no shell command" >&2
        exit 0
        ;;
      *)
        echo "$me: unknown backend '$backend' (no relay mechanism)" >&2
        exit 2
        ;;
    esac
    ;;

  observe-command)
    [ "$#" -eq 2 ] || {
      usage
      exit 2
    }
    backend=$1
    handle=$2
    case "$backend" in
      tmux)
        valid_handle tmux "$handle" || reject_handle tmux
        # Observe-in-flight: a read, never a write. capture-pane -p prints the
        # pane to stdout for the tower to classify as DATA.
        printf '%s\n' "tmux capture-pane -p -t '$handle'"
        exit 0
        ;;
      subagent)
        valid_handle subagent "$handle" || reject_handle subagent
        echo "$me: subagent is harness-native; observe via completion/notification, no shell command" >&2
        exit 0
        ;;
      *)
        echo "$me: unknown backend '$backend' (no observe mechanism)" >&2
        exit 2
        ;;
    esac
    ;;

  *)
    usage
    exit 2
    ;;
esac
