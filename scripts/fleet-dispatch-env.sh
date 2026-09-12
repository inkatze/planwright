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
#   fleet-dispatch-env.sh --emit-launch <launch-argv...>
#                                           print the pin-carrying WRAPPED launch
#                                           command line — this wrapper's own
#                                           resolved path followed by the launch
#                                           argv — so the dispatch primitive
#                                           CONSTRUCTS the launch as a code path
#                                           (fleet-hardening Task 5; D-5,
#                                           REQ-B1.1, REQ-B1.2). The emitted
#                                           prefix is the mechanism of record for
#                                           applying the pin: the pin is a
#                                           structural property of dispatch, not a
#                                           SKILL-prose step the model must
#                                           remember, and the emitted verb is the
#                                           repo-contained scripts/*.sh the
#                                           worker-command-guard auto-approves
#                                           (REQ-A1.10), so the launch never
#                                           floods and never falls back to the
#                                           2026-07-19 bare launch that dropped
#                                           the pin.
#
# The command is exec'd directly (exec "$@") — no shell, no eval — so arguments
# pass through unmangled and there is no injection surface; the wrapper only
# adds one fixed literal assignment and hands control to the operator-supplied
# command. `--emit-launch` is pure string construction (no exec, no model/API
# call — REQ-E1.3): it prints the launch line for a backend to run, the wrapper
# prefix applying the pin only when that emitted line is later exec'd. Its tokens
# are single-quote-wrapped, so a repo path or dispatch token carrying a space or
# shell metacharacter survives re-splitting and adds no injection surface — the
# same argument-boundary safety the exec path gets from `exec "$@"` — while
# staying accepted by the worker-command-guard tokenizer. An embedded single
# quote uses the backslash-free `'"'"'` concatenation form the guard accepts (so
# an apostrophe in the checkout path still auto-approves); only a newline, which
# cannot sit in a single-line launch, is refused (exit 2).
#
# Exit: execs <cmd> (adopting its exit status); a failed exec follows the
# shell's not-found/not-executable convention (typically 127/126, but
# shell-dependent — a bash acting as /bin/sh reports 126 for a missing file);
# --print and --emit-launch exit 0; a no-command or otherwise malformed
# invocation is a usage error, exit 2.
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
  echo "usage: fleet-dispatch-env.sh <cmd> [args...]           (exec <cmd> with the hardened dispatch env)" >&2
  echo "       fleet-dispatch-env.sh --print                   (print the KEY=VALUE assignment(s), one per line)" >&2
  echo "       fleet-dispatch-env.sh --emit-launch <argv...>   (print the pin-carrying wrapped launch command line)" >&2
  exit 2
}

# resolve_self — print this wrapper's absolute path.
#
# For a bare name (no directory component), resolve it via PATH first so we have
# a path to absolutize — never `dirname`-of-a-bare-name (`.`), which would
# fabricate a CWD-relative "/<cwd>/<name>". `command -v` may itself return a
# RELATIVE path when PATH holds a relative element (e.g. `PATH=scripts:...`), so
# its result is absolutized below rather than trusted as-is. If a directory
# cannot be resolved, the value is kept rather than collapsed to a broken
# "/<basename>".
resolve_self() {
  rs_self=$0
  case $rs_self in
    */*) ;;
    *)
      rs_found=$(command -v "$rs_self" 2>/dev/null) || rs_found=
      [ -n "$rs_found" ] && rs_self=$rs_found
      ;;
  esac
  case $rs_self in
    /*) ;;
    */*)
      rs_dir=$(cd "$(dirname "$rs_self")" 2>/dev/null && pwd) || rs_dir=
      [ -n "$rs_dir" ] && rs_self="$rs_dir/$(basename "$rs_self")"
      ;;
  esac
  printf '%s\n' "$rs_self"
}

# planwright_root — print the installation root this wrapper belongs to, derived
# from its own location (<root>/scripts/fleet-dispatch-env.sh). Self-location is
# what makes it survive a plugin update: a captured version-bearing path, or a
# symlink pointing at one, goes stale the moment the version changes, which is
# exactly the ephemeral-value capture the machine-local-environment rule forbids.
# Prints nothing when the parent cannot be resolved.
planwright_root() {
  pr_self=$(resolve_self)
  case $pr_self in
    */*) (cd "$(dirname "$pr_self")/.." 2>/dev/null && pwd -P) ;;
  esac
}

# export_root_vars — publish the resolved root as the two variables the guard's
# own resolution chain reads (worker-command-guard.sh: $PLANWRIGHT_ROOT, then
# $CLAUDE_PLUGIN_ROOT, then <claude-dir>/planwright).
#
# Claude Code exports CLAUDE_PLUGIN_ROOT only for a hook it delivers from plugin
# context; a hook arriving through a `--settings` fragment gets no such context,
# so without this the fragment's hook command resolves against an empty value and
# never runs — every dispatched worker then prompts on every routine command.
#
# Unlike the ghost-text pin, these do NOT override an inherited value: both are
# documented operator overrides (tests, adopters pointing at a checkout), and the
# wrapper must not silently outrank a root the operator chose.
export_root_vars() {
  er_root=$(planwright_root)
  [ -n "$er_root" ] || return 0
  [ -n "${PLANWRIGHT_ROOT:-}" ] || {
    PLANWRIGHT_ROOT=$er_root
    export PLANWRIGHT_ROOT
  }
  [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || {
    CLAUDE_PLUGIN_ROOT=$er_root
    export CLAUDE_PLUGIN_ROOT
  }
}

if [ "$#" -eq 0 ]; then
  usage
fi

if [ "$1" = "--print" ]; then
  [ "$#" -eq 1 ] || usage
  printf '%s=%s\n' "$GHOST_TEXT_KEY" "$GHOST_TEXT_VALUE"
  _root=$(planwright_root)
  if [ -n "$_root" ]; then
    printf 'PLANWRIGHT_ROOT=%s\n' "${PLANWRIGHT_ROOT:-$_root}"
    printf 'CLAUDE_PLUGIN_ROOT=%s\n' "${CLAUDE_PLUGIN_ROOT:-$_root}"
  fi
  exit 0
fi

if [ "$1" = "--emit-launch" ]; then
  shift
  [ "$#" -ge 1 ] || usage
  # Resolve this wrapper's own absolute path. The emitted launch verb must be the
  # repo-contained scripts/*.sh path the worker-command-guard trusts (REQ-A1.10
  # of worker-permission-ergonomics), so the constructed launch is auto-approved
  # without a permission flood (D-5, REQ-B1.2).
  # A value that is still a bare name after resolution means `command -v` found
  # nothing; the guard then resolves it against the launch cwd — the honest
  # fallback, not a fabrication.
  self=$(resolve_self)
  # Construct the launch line: the wrapper prefix (which applies the pin when the
  # line is exec'd) followed by the caller-supplied launch argv. The prefix is
  # emitted by CODE — the pin is a structural property of dispatch, never a prose
  # step the model must remember (REQ-B1.1). Every token is single-quote-wrapped:
  # a single-quoted token is inert to the shell (spaces and metacharacters
  # included), preserving the argument-boundary safety the exec path gets from
  # `exec "$@"`, AND it is accepted by the worker-command-guard tokenizer, so the
  # emitted line stays deterministically auto-approved (D-5, REQ-B1.2).
  #
  # An embedded single quote is emitted with the CONCATENATION form `'"'"'` (close
  # quote, a double-quoted quote, reopen quote) — NOT the `'\''` backslash form,
  # which the guard deliberately DEFERS on. The `'"'"'` form carries no backslash,
  # so the guard tokenizes it cleanly (verified) and a wrapper path or argument
  # containing an apostrophe (e.g. a checkout under /Users/O'Connor) still yields
  # an auto-approved launch. A newline is the one thing that cannot sit in a
  # single-line launch command, so a token containing one is refused (exit 2)
  # before anything is emitted; it is not a valid dispatch token. The message
  # never echoes the token content (mirrors the guard's never-reflect discipline).
  nl=$(printf '\nx')
  nl=${nl%x}
  for _tok in "$self" "$@"; do
    case $_tok in
      *"$nl"*)
        echo "fleet-dispatch-env.sh: --emit-launch: a launch token contains a newline, which cannot be emitted as a single-line launch" >&2
        exit 2
        ;;
    esac
  done
  emit_token() {
    # Single-quote-wrap; an embedded single quote becomes the backslash-free
    # concatenation `'"'"'` the guard accepts. The sed runs only for a token that
    # actually contains a quote (rare — an apostrophe in the checkout path).
    case $1 in
      *\'*) printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\"'\"'/g")" ;;
      *) printf "'%s'" "$1" ;;
    esac
  }
  emit_token "$self"
  for _arg in "$@"; do
    printf ' '
    emit_token "$_arg"
  done
  printf '\n'
  exit 0
fi

# Normal path: pin the hardened environment, then hand control to the launch
# command. `export` makes the value visible to the launched session and every
# descendant it spawns; the unconditional set overrides any inherited value.
export "$GHOST_TEXT_KEY=$GHOST_TEXT_VALUE"
export_root_vars
exec "$@"
