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
#       pasted payload is EXACTLY ONE LINE, a pointer: the attribution header
#       naming the tower origin and target, then `read <message-file>`. The
#       message body itself is never pasted. Measured on Claude Code 2.1.270:
#       a multi-line paste lands in the input box as a "[Pasted text #N +M
#       lines]" placeholder that nothing submits, and once the box holds
#       multi-line text every later paste is stuck behind it; a short single
#       line is what the CLI can submit on its own trailing newline. Even that
#       submission is timing-dependent (the same one-line paste submitted in
#       some runs and sat in the box in others), so a paste STAGES a relay and
#       the tower confirms delivery through observe-command — it never assumes
#       it. The message is DATA in both forms: the emitted command names the
#       message FILE, never inlines its content, so message text is never
#       spliced into the command as code (REQ-B1.7: worker/tower output is
#       data, no eval/expansion path). stream-json: the sanctioned unattended
#       path — prints the `fleet-streamjson.sh steer` invocation, which writes
#       the attributed message as a user turn on the worker's own stdin (a
#       real submit, journaled in the worker's state dir) and never touches an
#       input box. subagent: harness-native — there is no screen-scrape
#       surface at all; empty stdout, exit 0 (the tower relays via its own prompt
#       queue). Exit 2 on an invalid handle, a missing/unsafe message file, an
#       unknown backend, or usage.
#
#   observe-command <backend> <handle>
#       Print the observe-in-flight status-read command (REQ-D1.3). tmux:
#       `capture-pane -p` — a read, never a write; the handle is validated first.
#       stream-json: `fleet-streamjson.sh status <handle>` (running,
#       awaiting-input, completed, ended, dead, unknown). subagent:
#       harness-native (completion/notification is the surface); empty stdout,
#       exit 0. Exit 2 on an invalid handle, an unknown backend, or usage.
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

# Resolve this script's directory so the sibling echo-safety helper is found
# regardless of the caller's working directory.
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
echo_safety="$script_dir/echo-safety.sh"
# echo-safety.sh is sourced (not executed), so require it READABLE and fail closed
# (exit 2) when a broken install omits it — rather than a raw dot-source error. It
# sanitizes every untrusted value (message-file paths, backend names) before it
# reaches operator-facing stderr (echo discipline, doctrine/security-posture.md —
# the same posture every sibling in-scope script applies at each such site).
if [ ! -r "$echo_safety" ]; then
  echo "$me: required helper $echo_safety missing or not readable" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$echo_safety"

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
    stream-json)
      # The supervisor's own worker-handle grammar (fleet-streamjson.sh
      # valid_field), minus `=` and `:`, which a handle never needs and which
      # would otherwise ride into the emitted single-quoted argument.
      case "$2" in
        *[!A-Za-z0-9_.@-]*) return 1 ;;
        . | ..) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
  return 0
}

# A message file must exist as a readable regular file and its path must be safe
# to place inside a single-quoted shell literal in the emitted command (no single
# quote, no newline, no control byte). The tower writes the message to a temp file
# it controls; this guards the emission boundary regardless. Readability is
# required because the emitted `cat -- '<path>'` would otherwise fail at runtime.
valid_msgfile() {
  [ -f "$1" ] || return 1
  [ -r "$1" ] || return 1
  case "$1" in
    *"'"*) return 1 ;;
    *"$nl"*) return 1 ;;
  esac
  # Reject C0/DEL/C1 control bytes in the path (the exact range echo-safety.sh
  # strips): the path is bound into the emitted relay command and echoed in the
  # reject diagnostic, so a raw escape byte would drive the operator's terminal.
  # A path bound into an emitted command is refused outright, not sanitized.
  [ "$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237')" = "$1" ] || return 1
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
          printf '%s\n' "$me: message file missing or path unsafe to relay: $(sanitize_printable "$msg" "(unprintable path)")" >&2
          exit 2
        }
        # tmux named buffers are server-global, so a fixed buffer name lets two
        # relays on one server interleave (A load, B load, A paste) and paste the
        # wrong payload to the wrong target — a live risk here, where multiple
        # towers coordinate over one server. Uniquify the buffer per invocation
        # with this relay process's PID: computed once, so the load and paste
        # lines below name the SAME buffer, while two concurrent invocations
        # (distinct live PIDs) never collide. It is a DATA-free literal (digits).
        buf="planwright-relay-$$"
        # The pasted payload is a single pointer line, never the body (see the
        # header: a multi-line paste is a placeholder the CLI never submits and
        # it poisons the box for every later paste). The worker reads the file
        # itself, so the path is made absolute here — its cwd is not the
        # tower's — and re-checked after canonicalization, since the check
        # above ran on the spelling the tower gave, not on the one emitted.
        msg_abs=$(cd -- "$(dirname -- "$msg")" 2>/dev/null && pwd -P) || msg_abs=''
        [ -n "$msg_abs" ] && msg_abs="$msg_abs/$(basename -- "$msg")"
        valid_msgfile "$msg_abs" || {
          printf '%s\n' "$me: message file path unsafe to relay once made absolute: $(sanitize_printable "$msg" "(unprintable path)")" >&2
          exit 2
        }
        # Attributed buffer-paste delivery. The header is a fixed literal (tower
        # origin + target); the pointer names the message FILE, so its content
        # is DATA and never enters the command as code. NEVER send-keys.
        printf '%s\n' "printf '%s\\n' '[planwright tower relay -> $handle] read $msg_abs' | tmux load-buffer -b $buf -"
        printf '%s\n' "tmux paste-buffer -b $buf -t '$handle' -d"
        exit 0
        ;;
      stream-json)
        valid_handle stream-json "$handle" || reject_handle stream-json
        valid_msgfile "$msg" || {
          printf '%s\n' "$me: message file missing or path unsafe to relay: $(sanitize_printable "$msg" "(unprintable path)")" >&2
          exit 2
        }
        # The supervisor writes the attributed message onto the worker's own
        # stdin as a user turn: a submit that needs no input box and leaves a
        # receipt in the worker's state dir. The sibling script is named by the
        # literal path next to this one (the shape the tower command-guard
        # approves), never through a variable. The install path is bound into
        # a single-quoted literal the same way the message path is, so it gets
        # the same refusal on a quote or newline.
        case "$script_dir" in
          *"'"* | *"$nl"*)
            echo "$me: install path unsafe to emit inside a single-quoted command" >&2
            exit 2
            ;;
        esac
        printf '%s\n' "'$script_dir/fleet-streamjson.sh' steer '$handle' --message-file '$msg'"
        exit 0
        ;;
      subagent)
        valid_handle subagent "$handle" || reject_handle subagent
        echo "$me: subagent is harness-native; relay via the tower's prompt queue, no shell command" >&2
        exit 0
        ;;
      *)
        printf '%s\n' "$me: unknown backend '$(sanitize_printable "$backend" "(unprintable backend)")' (no relay mechanism)" >&2
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
      stream-json)
        valid_handle stream-json "$handle" || reject_handle stream-json
        case "$script_dir" in
          *"'"* | *"$nl"*)
            echo "$me: install path unsafe to emit inside a single-quoted command" >&2
            exit 2
            ;;
        esac
        printf '%s\n' "'$script_dir/fleet-streamjson.sh' status '$handle'"
        exit 0
        ;;
      subagent)
        valid_handle subagent "$handle" || reject_handle subagent
        echo "$me: subagent is harness-native; observe via completion/notification, no shell command" >&2
        exit 0
        ;;
      *)
        printf '%s\n' "$me: unknown backend '$(sanitize_printable "$backend" "(unprintable backend)")' (no observe mechanism)" >&2
        exit 2
        ;;
    esac
    ;;

  *)
    usage
    exit 2
    ;;
esac
