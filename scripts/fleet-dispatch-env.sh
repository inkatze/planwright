#!/bin/sh
# fleet-dispatch-env.sh — the dispatch-time environment-hardening wrapper
# (fleet-autonomy Task 6; D-10, REQ-D1.1).
#
# Every fleet-launched Claude Code session that another session reads via pane
# capture — a dispatched worker, and any subordinate tower a meta-tower
# observes — is launched THROUGH this wrapper. The wrapper pins
# CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false into the launched process's
# environment, disabling input-line ghost-text (prompt suggestions) at the
# source so a pane capture is never ambiguous between real input and a rendered
# suggestion (D-10). This is prevention at the launch environment — the tower
# already controls the launch environment of every session it dispatches — not
# a runtime detection heuristic. The backspace-probe disambiguation (REQ-D1.2)
# stays a documented, undispatched defense-in-depth fallback (see docs/fleet.md);
# no required code path depends on it.
#
# The pin is unconditional: an inherited `...=true` in the parent environment is
# overridden to `false`, so prevention cannot be defeated by an outer value.
#
# Usage:
#   fleet-dispatch-env.sh <cmd> [args...]   exec <cmd> with the hardened
#                                           environment (the normal path: a
#                                           backend spawns the session through
#                                           this)
#   fleet-dispatch-env.sh --print           print the KEY=VALUE assignment,
#                                           one per line, for a launcher that
#                                           cannot wrap the exec (e.g. a tmux
#                                           relay that prepends it to the
#                                           launch command)
#
# The command is exec'd directly (exec "$@") — no shell, no eval — so arguments
# pass through unmangled and there is no injection surface; the wrapper only
# adds one fixed literal assignment and hands control to the operator-supplied
# command.
#
# Exit: execs <cmd> (adopting its exit status); a failed exec follows the
# shell's convention (127 not-found / 126 not-executable); --print exits 0; a
# no-command or otherwise malformed invocation is a usage error, exit 2.
set -u

# Pin C for byte-stable behavior, consistent with the sibling scripts. A
# CDPATH-resolved cd would echo its destination into a command substitution.
LC_ALL=C
export LC_ALL
unset CDPATH

# The single hardened assignment this wrapper applies. Fixed literal, not a
# config knob: D-10/REQ-D1.1 pin the value, so it is never overlay-tunable.
GHOST_TEXT_KEY=CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION
GHOST_TEXT_VALUE=false

usage() {
  echo "usage: fleet-dispatch-env.sh <cmd> [args...]   (exec <cmd> with the hardened dispatch env)" >&2
  echo "       fleet-dispatch-env.sh --print           (print the KEY=VALUE assignment(s), one per line)" >&2
  exit 2
}

if [ "$#" -eq 0 ]; then
  usage
fi

if [ "$1" = "--print" ]; then
  [ "$#" -eq 1 ] || usage
  printf '%s=%s\n' "$GHOST_TEXT_KEY" "$GHOST_TEXT_VALUE"
  exit 0
fi

# Normal path: pin the hardened environment, then hand control to the launch
# command. `export` makes the value visible to the launched session and every
# descendant it spawns; the unconditional set overrides any inherited value.
export "$GHOST_TEXT_KEY=$GHOST_TEXT_VALUE"
exec "$@"
