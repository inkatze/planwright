#!/bin/sh
# fleet-dispatch-guard.sh — the dispatch-time guard proving a fleet worker
# session is never launched under Claude Code's `auto` permission mode
# (fleet-autonomy Task 7; D-19, REQ-E1.4; kickoff risk rows 19, 20).
#
# WHY. `auto` mode's approval classifier is LLM-based and judgment-driven —
# against the D-18 no-LLM-daemon-mechanics floor for the single most
# security-sensitive decision a dispatched session makes, and Claude Code's
# own documentation cautions it is not for security-critical work without
# human review, which is exactly what worker dispatch is. The
# human-reviewed, human-installed `config/worker-settings.json` allowlist
# remains the sole permission-approval mechanism for dispatched workers
# (D-19/REQ-E1.4); it pins `defaultMode` to a non-auto value.
#
# TWO DISPATCH SHAPES, TWO CHECKS.
#   check-launch <cmd> [args...]  — a LAUNCHED process (tmux / print /
#     headless): the guard lints the launch argv BEFORE the backend spawns
#     it. Refusals: any `--permission-mode auto` (either spelling, any
#     position); a `--settings` fragment that itself pins `defaultMode` to
#     auto; a `--settings` path that cannot be read (fail closed — an
#     unverifiable mode source is no mode source). And per risk row 20 the
#     argv must carry an EXPLICIT non-auto mode source — an explicit
#     non-auto `--permission-mode`, or a readable `--settings` fragment
#     pinning a non-auto `defaultMode` (the standard worker-settings
#     profile) — because absence of the auto flag proves nothing: Claude
#     Code honors `defaultMode: "auto"` from the operator's own user
#     settings, so a bare launch could silently inherit it.
#   check-inherited — an IN-PROCESS worker (the subagent backend, a Task-
#     tool invocation): no launch argv exists and the worker inherits the
#     hosting session's effective mode (risk row 19). The deterministic,
#     checkable proxy for that ambient inheritance is the one surface D-19
#     documents as able to set it: the operator's own user settings
#     (`$CLAUDE_DIR`/`~/.claude`/settings.json). A `defaultMode` of auto
#     there refuses in-process dispatch; a non-auto pin, no pin, or no
#     settings file passes (Claude Code's own built-in default mode is
#     `default`, which prompts).
#
# The guard is a LINT: it inspects, never launches, and never modifies the
# argv. A refusal (exit 1) is a dispatch stop condition the tower surfaces —
# never bypassed, never downgraded to a warning. The JSON peek at a settings
# fragment is a grep-shaped read (no jq on the support bar, REQ-K1.5):
# it finds the first `"defaultMode": "<value>"` pair anywhere in the file,
# which is exactly the flat shape Claude Code settings fragments use.
#
# Usage:
#   fleet-dispatch-guard.sh check-launch <cmd> [args...]
#   fleet-dispatch-guard.sh check-inherited
#
# Exit codes: 0 pass (dispatch may proceed); 1 refused (auto mode present,
# an unverifiable mode source, or no explicit non-auto mode source);
# 2 usage error. Never mutates any file.
#
# POSIX sh on the macOS + Linux support bar (bash 3.2 / BSD tooling). No
# eval, no jq; every argv token and file value is data (REQ-K1.5).
# Pathname expansion is disabled (set -f).
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# The canonical echo-discipline sanitizer (doctrine/security-posture.md):
# argv tokens and settings-file values are untrusted and are stripped of
# control bytes before any diagnostic (risk 23's sibling discipline).
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

usage() {
  echo "usage: fleet-dispatch-guard.sh check-launch <cmd> [args...] | check-inherited" >&2
}

# settings_default_mode <path>: print the first "defaultMode" string value
# in the fragment, empty when none. Returns 1 when the file cannot be read.
settings_default_mode() {
  [ -f "$1" ] && [ -r "$1" ] || return 1
  # First "defaultMode" : "<value>" pair; the value is captured between the
  # closing quote pair. tr strips newlines first so the pair may wrap.
  sdm_v=$(tr '\n' ' ' <"$1" \
    | sed -n 's/.*"defaultMode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1)
  printf '%s' "$sdm_v"
}

[ "$#" -ge 1 ] || {
  usage
  exit 2
}
cmd=$1
shift

case "$cmd" in
  check-launch)
    [ "$#" -ge 1 ] || {
      usage
      exit 2
    }
    launch_cmd=$1
    mode_source="" # the explicit non-auto mode source found, if any

    # Walk the argv. Tokens are data: matched, never executed or expanded.
    while [ "$#" -gt 0 ]; do
      tok=$1
      shift
      flag_value=""
      case "$tok" in
        --permission-mode)
          if [ "$#" -eq 0 ]; then
            # A trailing bare flag has no value; Claude Code would reject
            # the launch anyway, but an unverifiable mode is refused here.
            echo "fleet-dispatch-guard: refusing launch of '$(sanitize_printable "$launch_cmd" "(unprintable cmd)")': --permission-mode has no value" >&2
            exit 1
          fi
          flag_value=$1
          shift
          ;;
        --permission-mode=*)
          flag_value=${tok#--permission-mode=}
          ;;
        --settings | --settings=*)
          if [ "$tok" = --settings ]; then
            if [ "$#" -eq 0 ]; then
              echo "fleet-dispatch-guard: refusing launch of '$(sanitize_printable "$launch_cmd" "(unprintable cmd)")': --settings has no value" >&2
              exit 1
            fi
            settings_path=$1
            shift
          else
            settings_path=${tok#--settings=}
          fi
          if ! pinned=$(settings_default_mode "$settings_path"); then
            # Fail closed: a mode source the guard cannot read proves
            # nothing about the mode the worker would run under.
            echo "fleet-dispatch-guard: refusing launch of '$(sanitize_printable "$launch_cmd" "(unprintable cmd)")': settings fragment '$(sanitize_printable "$settings_path" "(unprintable path)")' is missing or unreadable (D-19: the mode source must be verifiable)" >&2
            exit 1
          fi
          if [ "$pinned" = auto ]; then
            echo "fleet-dispatch-guard: refusing launch of '$(sanitize_printable "$launch_cmd" "(unprintable cmd)")': settings fragment '$(sanitize_printable "$settings_path" "(unprintable path)")' pins defaultMode to auto (REQ-E1.4/D-19)" >&2
            exit 1
          fi
          if [ -n "$pinned" ]; then
            mode_source="settings fragment pins defaultMode=$pinned"
          fi
          continue
          ;;
        *)
          continue
          ;;
      esac
      # A --permission-mode value (either spelling) landed here.
      if [ "$flag_value" = auto ]; then
        echo "fleet-dispatch-guard: refusing launch of '$(sanitize_printable "$launch_cmd" "(unprintable cmd)")': --permission-mode auto is never used for fleet workers (REQ-E1.4/D-19; the worker-settings allowlist is the sole approval mechanism)" >&2
        exit 1
      fi
      mode_source="explicit --permission-mode $flag_value"
    done

    # Risk row 20: no auto flag found is NOT a pass — demand the explicit
    # non-auto mode source, so an ambient user-settings auto default can
    # never leak into a worker.
    if [ -z "$mode_source" ]; then
      echo "fleet-dispatch-guard: refusing launch of '$(sanitize_printable "$launch_cmd" "(unprintable cmd)")': no explicit non-auto permission-mode source in the argv (risk 20 — pass --permission-mode <mode> or --settings <worker-settings fragment>; absence of the auto flag is not a mode)" >&2
      exit 1
    fi
    exit 0
    ;;

  check-inherited)
    [ "$#" -eq 0 ] || {
      usage
      exit 2
    }
    claude_dir=${CLAUDE_DIR:-${HOME:-}/.claude}
    user_settings="$claude_dir/settings.json"
    if [ ! -f "$user_settings" ]; then
      # No user settings: Claude Code's built-in default mode is `default`
      # (prompting), a non-auto mode. Nothing ambient to inherit.
      exit 0
    fi
    if ! ambient=$(settings_default_mode "$user_settings"); then
      # Present but unreadable: fail closed, same as an unverifiable
      # launch-time mode source.
      echo "fleet-dispatch-guard: refusing in-process dispatch: user settings '$(sanitize_printable "$user_settings" "(unprintable path)")' exist but cannot be read (unverifiable inherited mode)" >&2
      exit 1
    fi
    if [ "$ambient" = auto ]; then
      echo "fleet-dispatch-guard: refusing in-process dispatch: the hosting session inherits defaultMode auto from '$(sanitize_printable "$user_settings" "(unprintable path)")' (risk 19 — an in-process worker would run under it; REQ-E1.4/D-19)" >&2
      exit 1
    fi
    exit 0
    ;;

  *)
    usage
    exit 2
    ;;
esac
