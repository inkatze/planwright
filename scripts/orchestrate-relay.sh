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
#       tmux: the `deliver` invocation below, by this script's literal path.
#       It is the fallback for a target that is not a Claude Code peer the
#       tower can message directly (doctrine/inter-orchestrator-coordination.md).
#       <handle> is an explicit handle: one the operator names, or a live
#       peer's published tmux-window from fleet-presence.sh, never "the active
#       pane" of some window, which can be a closing session. The message is
#       DATA in every form: the emitted command names the message FILE, never
#       inlines its content, so message text is never spliced into the
#       command as code (REQ-B1.7: worker/tower output is
#       data, no eval/expansion path). stream-json: the sanctioned unattended
#       path — prints the `fleet-streamjson.sh steer` invocation, which writes
#       the attributed message as a user turn on the worker's own stdin (a
#       real submit, journaled in the worker's state dir) and never touches an
#       input box. subagent: harness-native — there is no screen-scrape
#       surface at all; empty stdout, exit 0 (the tower relays via its own prompt
#       queue). Exit 2 on an invalid handle, a missing/unsafe message file, an
#       unknown backend, or usage.
#
#   deliver tmux <handle> <message-file>
#       Run the tmux buffer-paste (`load-buffer`/`paste-buffer`) — NEVER a
#       `send-keys` path (REQ-D1.3: no impersonation of the worker's input) —
#       refusing first and confirming after, never assuming. The pasted payload
#       is EXACTLY ONE LINE, a pointer: a per-delivery `(#<id>)` tag, the
#       attribution header naming the tower origin and target, then `read
#       <absolute message-file>`. The message body itself is never pasted.
#       Measured on Claude Code 2.1.270: a multi-line paste lands in the input
#       box as a "[Pasted text #N +M lines]" placeholder that nothing submits,
#       and once the box holds one every later paste is stuck behind it. The line is
#       loaded with NO trailing newline, so a paste always STAGES the relay and
#       one Enter from the receiving human submits it (measured on 2.1.289; a
#       trailing newline either submitted a short line on its own or, for a
#       long one, left a hidden newline that swallowed the first Enter).
#       Before pasting it reads the pane and refuses while a selection prompt
#       is open (a paste would answer that dialog), a paste placeholder is
#       staged, or an earlier relay sits unsubmitted in the input box (this
#       one would join it on one line), using the TUI vocabulary in
#       fleet-pane-vocabulary.sh. After pasting it re-reads the pane until the
#       `(#<id>)` tag shows. Exit 0: staged and seen. Exit 2: usage, an
#       invalid handle, an unsafe message file. Exit 3: refused, nothing
#       pasted (dialog open, placeholder or relay staged, pane unreadable,
#       buffer load failed). Exit 4: the paste ran, or deliver was interrupted
#       around it, but the tag never showed; observe the pane before any
#       re-send, which would stage a duplicate. PLANWRIGHT_RELAY_CONFIRM_TRIES
#       (default 5, at most 20) and PLANWRIGHT_RELAY_CONFIRM_SLEEP (seconds,
#       default 1, at most 3) bound the confirmation wait to under a minute.
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
pane_vocabulary="$script_dir/fleet-pane-vocabulary.sh"
# echo-safety.sh is sourced (not executed), so require it READABLE and fail closed
# (exit 2) when a broken install omits it — rather than a raw dot-source error. It
# sanitizes every untrusted value (message-file paths, backend names) before it
# reaches operator-facing stderr (echo discipline, doctrine/security-posture.md —
# the same posture every sibling in-scope script applies at each such site).
if [ ! -f "$echo_safety" ] || [ ! -r "$echo_safety" ]; then
  printf '%s\n' "$me: required helper echo-safety.sh missing or not readable" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$echo_safety"
if [ ! -r "$pane_vocabulary" ]; then
  printf '%s\n' "$me: required helper $pane_vocabulary missing or not readable" >&2
  exit 2
fi
# shellcheck source=scripts/fleet-pane-vocabulary.sh
. "$pane_vocabulary"

# A literal newline, for the message-file path safety check below.
nl='
'

usage() {
  printf '%s\n' "$me: usage: $me <validate-handle|relay-command|deliver|observe-command> <backend> <handle> [<message-file>]" >&2
  printf '%s\n' "$me: <handle> is explicit (operator-named, or a live peer's handle from fleet-presence.sh), never the active pane" >&2
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
# required because the receiver reads the file the relay points it at.
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

# absolute_msgfile <path> — print the message path made absolute (the receiver
# reads the file itself and its cwd is not the tower's), re-checked after
# canonicalization since the first check ran on the spelling the tower gave.
absolute_msgfile() {
  am_dir=$(cd -- "$(dirname -- "$1")" 2>/dev/null && pwd -P) || return 1
  am_abs="$am_dir/$(basename -- "$1")"
  valid_msgfile "$am_abs" || return 1
  printf '%s\n' "$am_abs"
}

# bounded_int <value> <default> <max> — the value when it is a plain integer
# no larger than max, else the default.
bounded_int() {
  case "$1" in
    '' | *[!0-9]*) printf '%s\n' "$2" ;;
    *) if [ "$1" -le "$3" ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi ;;
  esac
}

# pane_tail <handle> — the bottom of the target's visible pane, where an open
# dialog and the input box render. Fails only when the capture does; a blank
# pane is readable.
pane_tail() {
  pt_text=$(tmux capture-pane -p -t "$1" 2>/dev/null) || return 1
  printf '%s\n' "$pt_text" | tail -n 24
}

# staged_relay_present <window-text> — 0 iff an earlier relay sits unsubmitted
# on the input box's first row, the one right under the box's top rule. A
# submitted relay moves up into the transcript, away from that rule.
staged_relay_present() {
  printf '%s\n' "$1" | awk '
    prev ~ /^[[:space:]]*─/ && /❯.*\[planwright tower relay -> / { found = 1 }
    { prev = $0 }
    END { exit !found }'
}

reject_handle() {
  printf '%s\n' "$me: refusing invalid $1 handle (REQ-B1.7: validated before use)" >&2
  exit 2
}

# require_tmux_target <handle> <message-file> — exit 2 unless both are safe to
# target and emit; sets msg_abs to the message path made absolute.
require_tmux_target() {
  valid_handle tmux "$1" || reject_handle tmux
  valid_msgfile "$2" || {
    printf '%s\n' "$me: message file missing or path unsafe to relay: $(sanitize_printable "$2" "(unprintable path)")" >&2
    exit 2
  }
  msg_abs=$(absolute_msgfile "$2") || {
    printf '%s\n' "$me: message file path unsafe to relay once made absolute: $(sanitize_printable "$2" "(unprintable path)")" >&2
    exit 2
  }
}

# require_safe_script_dir — exit 2 when the install path cannot sit inside a
# single-quoted literal in an emitted command.
require_safe_script_dir() {
  case "$script_dir" in
    *"'"* | *"$nl"*)
      printf '%s\n' "$me: install path unsafe to emit inside a single-quoted command" >&2
      exit 2
      ;;
  esac
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
        require_tmux_target "$handle" "$msg"
        require_safe_script_dir
        # The emitted line runs this script by its literal path (the shape the
        # tower command-guard approves), so the refusal and the confirmation
        # below travel with every relay instead of depending on the caller.
        printf '%s\n' "'$script_dir/orchestrate-relay.sh' deliver tmux '$handle' '$msg_abs'"
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
        require_safe_script_dir
        printf '%s\n' "'$script_dir/fleet-streamjson.sh' steer '$handle' --message-file '$msg'"
        exit 0
        ;;
      subagent)
        valid_handle subagent "$handle" || reject_handle subagent
        printf '%s\n' "$me: subagent is harness-native; relay via the tower's prompt queue, no shell command" >&2
        exit 0
        ;;
      *)
        printf '%s\n' "$me: unknown backend '$(sanitize_printable "$backend" "(unprintable backend)")' (no relay mechanism)" >&2
        exit 2
        ;;
    esac
    ;;

  deliver)
    [ "$#" -eq 3 ] || {
      usage
      exit 2
    }
    [ "$1" = tmux ] || {
      printf '%s\n' "$me: deliver runs only the tmux paste; backend '$(sanitize_printable "$1" "(unprintable backend)")' relays through relay-command" >&2
      exit 2
    }
    handle=$2
    require_tmux_target "$handle" "$3"
    tries=$(bounded_int "${PLANWRIGHT_RELAY_CONFIRM_TRIES:-}" 5 20)
    [ "$tries" -ge 1 ] || tries=5
    pause=$(bounded_int "${PLANWRIGHT_RELAY_CONFIRM_SLEEP:-}" 1 3)
    # Captured pane text is DATA: matched as substrings, never evaluated.
    before=$(pane_tail "$handle") || {
      printf '%s\n' "$me: refused, nothing pasted: cannot read target pane $handle" >&2
      exit 3
    }
    if selection_prompt_present "$before"; then
      printf '%s\n' "$me: refused, nothing pasted: $handle shows an open selection prompt, which a paste would answer" >&2
      exit 3
    fi
    if staged_paste_present "$before"; then
      printf '%s\n' "$me: refused, nothing pasted: $handle holds a staged paste placeholder that would block this one" >&2
      exit 3
    fi
    if staged_relay_present "$before"; then
      printf '%s\n' "$me: refused, nothing pasted: $handle holds an unsubmitted relay this paste would join onto one line" >&2
      exit 3
    fi
    # tmux named buffers are server-global, so a fixed buffer name lets two
    # relays on one server interleave (A load, B load, A paste) and paste the
    # wrong payload to the wrong target. The PID uniquifies it per invocation.
    buf="planwright-relay-$$"
    # The tag is what the confirmation looks for. It leads the line so it sits
    # whole at the start of the input box's first row however narrowly the box
    # wraps, and it is fresh, so an earlier relay of the same file still on
    # screen cannot pass for this one. Its digits map to letters: a dialog
    # that opens between the check above and the paste takes the paste's
    # first keys, and a digit there would pick a numbered option.
    tag="#$(printf '%s-%s' "$$" "$(date +%s)" | tr '0-9' 'a-j')"
    # A kill between the load and the paste would leave the buffer, holding
    # the relay line, on the shared server under a name a reused PID can meet.
    trap 'tmux delete-buffer -b "$buf" 2>/dev/null; exit 4' INT TERM HUP
    if ! printf '%s' "($tag) [planwright tower relay -> $handle] read $msg_abs" | tmux load-buffer -b "$buf" - 2>/dev/null; then
      printf '%s\n' "$me: refused, nothing pasted: tmux load-buffer failed" >&2
      exit 3
    fi
    if ! tmux paste-buffer -b "$buf" -t "$handle" -d 2>/dev/null; then
      tmux delete-buffer -b "$buf" 2>/dev/null || :
      printf '%s\n' "$me: not confirmed: tmux paste-buffer to $handle failed; observe the pane before re-sending" >&2
      exit 4
    fi
    trap - INT TERM HUP
    i=0
    while [ "$i" -lt "$tries" ]; do
      i=$((i + 1))
      case "$(pane_tail "$handle")" in
        *"($tag)"*)
          printf '%s\n' "staged $handle ($tag): one Enter in that session submits it"
          exit 0
          ;;
      esac
      [ "$i" -lt "$tries" ] && sleep "$pause"
    done
    printf '%s\n' "$me: not confirmed: pasted to $handle but ($tag) never showed in the pane; observe it before re-sending, which would stage a duplicate" >&2
    exit 4
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
        require_safe_script_dir
        printf '%s\n' "'$script_dir/fleet-streamjson.sh' status '$handle'"
        exit 0
        ;;
      subagent)
        valid_handle subagent "$handle" || reject_handle subagent
        printf '%s\n' "$me: subagent is harness-native; observe via completion/notification, no shell command" >&2
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
