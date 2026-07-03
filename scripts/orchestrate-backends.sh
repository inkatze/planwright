#!/bin/sh
# orchestrate-backends.sh — host-backend AUTODETECTION and unattended
# SELECTION for /orchestrate (orchestration-fleet Task 2; D-3, REQ-B1.4).
#
# This is the scripts-level realization of the Task 1 backend capability
# contract's advertisement mechanism (doctrine/backend-capability-contract.md,
# D-2): it reports which dispatch backends are actually PRESENT on the host,
# each with its advertised capability set, and makes the autonomous (no human
# to ask) backend pick in unattended mode. The attended present-and-ask flow
# lives in the /orchestrate skill, which calls `detect` for the candidate set
# and asks the operator — this script never silently picks for an attended run.
#
# Subcommands:
#   detect [pluggable-name...]
#       Print one TSV row per PRESENT backend, richest rung first:
#         backend<TAB>interactive<TAB>can_observe<TAB>can_steer_inflight<TAB>\
#         provides_attention_surface<TAB>supports_parallel<TAB>session_grade
#       The five advertised booleans are true|false|na (na = a capability that
#       is structurally inapplicable, distinct from an absent one); session_grade
#       is yes|no|deferred. `in-session` and `print` are always present;
#       `subagent` is present by default (the harness-native runtime); `tmux` is
#       present iff it resolves on PATH. subagent/tmux presence is overridable
#       with PLANWRIGHT_BACKEND_{SUBAGENT,TMUX} (1/0) so a host or test can force
#       it. Each pluggable-name arg is present iff a `planwright-backend-<name>`
#       adapter on PATH answers `advertise` with a well-formed capability set;
#       an absent or malformed adapter is reported absent (fail-safe — a backend
#       whose capabilities are unknown is never advertised). A pluggable arg
#       naming a shipped backend, or a hostile/invalid name, is skipped.
#
#   select-unattended <configured>
#       Print the backend the tower should use with NO human to ask: the
#       configured backend when it is present AND unattended-eligible
#       (advertised interactive=false AND session_grade!=deferred), else DEGRADE
#       down the shipped autonomous chain (subagent -> in-session, the
#       always-present terminal rung). It NEVER selects an interactive backend
#       (REQ-B1.4) and never the manual `print` rung. A degrade prints a NOTE to
#       stderr and still exits 0 with the selection on stdout. Runtime failover,
#       the full richest-to-safest ladder, and the degrade-capability-never-
#       safety abort are Task 3; this is the selection-time autonomous pick only.
#
# Every backend token is treated as DATA: a pluggable name is validated against
# the anchored identifier charset before it is ever spliced into the
# `planwright-backend-<name>` command, so a hostile name is refused, never run.
#
# Exit codes: 0 success (including every degrade — an absent, malformed, or
# ineligible configured backend degrades to a shipped rung and still exits 0);
# 2 usage error (no/unknown subcommand, or a select-unattended configured
# argument that is empty or fails the identifier charset). No subcommand
# mutates any file.
#
# Portable POSIX sh + coreutils (bash 3.2 / BSD compatible): no eval, no gawk
# extensions, input treated as data only (REQ-K1.5).
set -u

# Pin the C locale so the charset checks below mean exactly their ASCII range
# on every host (defensive; mirrors the sibling scripts).
LC_ALL=C
export LC_ALL
unset CDPATH

# An invalid backend name is untrusted DATA: it must be stripped of non-printable
# bytes before it reaches a diagnostic, so an embedded escape sequence cannot
# drive the operator's terminal (doctrine/security-posture.md, "Echo
# discipline"). Sourced like the other framework callers (spec-validate.sh).
# shellcheck source=scripts/echo-safety.sh
. "$(dirname "$0")/echo-safety.sh"

# ---------------------------------------------------------------------------
# The advertised capability set of each shipped backend, verbatim from the
# Task 1 contract table (doctrine/backend-capability-contract.md). Fields, in
# order: interactive can_observe can_steer_inflight provides_attention_surface
# supports_parallel session_grade. Keep in lockstep with that table.
# ---------------------------------------------------------------------------
caps_for() {
  case "$1" in
    tmux) echo "true true true false true yes" ;;
    subagent) echo "false false false false true no" ;;
    print) echo "false false false false na deferred" ;;
    in-session) echo "false na na false false no" ;;
    *) return 1 ;;
  esac
}

# A backend name that names one of the shipped four.
is_known() {
  case "$1" in
    tmux | subagent | print | in-session) return 0 ;;
    *) return 1 ;;
  esac
}

# Anchored identifier charset for a pluggable backend name: lowercase alnum and
# hyphen, must start alnum, <=64 chars (mirrors the spec-id grammar). This runs
# BEFORE the name is used to build the adapter command, so a traversal, glob, or
# shell metacharacter is refused rather than interpolated.
valid_name() {
  case "$1" in
    '') return 1 ;;
    [!a-z0-9]*) return 1 ;;
    *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

# Resolve an env override to presence. $1 = raw env value (possibly empty);
# $2 = default action when the value is empty/unrecognized:
#   yes -> present, no -> absent, tmux -> `command -v tmux`.
env_present() {
  case "$1" in
    1 | true | TRUE | on | yes | YES) return 0 ;;
    0 | false | FALSE | off | no | NO) return 1 ;;
  esac
  case "$2" in
    yes) return 0 ;;
    no) return 1 ;;
    tmux) command -v tmux >/dev/null 2>&1 ;;
  esac
}

# Is a shipped backend present on this host?
is_present() {
  case "$1" in
    in-session | print) return 0 ;;
    subagent) env_present "${PLANWRIGHT_BACKEND_SUBAGENT-}" yes ;;
    tmux) env_present "${PLANWRIGHT_BACKEND_TMUX-}" tmux ;;
    *) return 1 ;;
  esac
}

# The advertised set of a pluggable backend, obtained from its adapter. Echoes
# the six validated fields, or returns 1 when there is no adapter on PATH or its
# output is not a well-formed capability set (the fail-safe absent case).
adapter_caps() {
  ac_cmd="planwright-backend-$1"
  command -v "$ac_cmd" >/dev/null 2>&1 || return 1
  ac_raw=$("$ac_cmd" advertise 2>/dev/null) || return 1
  # First line only; default IFS splits on space/tab. A well-formed set is
  # exactly six known tokens (rest must be empty). The read targets are
  # `f_`-prefixed so this helper never clobbers a caller's loop variable
  # (`p`, `rung`) — sh has no lexical scope.
  f_i='' f_o='' f_s='' f_a='' f_p='' f_g='' f_rest=''
  read -r f_i f_o f_s f_a f_p f_g f_rest <<EOF
$ac_raw
EOF
  [ -z "$f_rest" ] || return 1
  for f in "$f_i" "$f_o" "$f_s" "$f_a" "$f_p"; do
    case "$f" in
      true | false | na) ;;
      *) return 1 ;;
    esac
  done
  case "$f_g" in
    yes | no | deferred) ;;
    *) return 1 ;;
  esac
  echo "$f_i $f_o $f_s $f_a $f_p $f_g"
}

# Echo the advertised set of a backend IF it is present, else return 1. Handles
# both shipped backends (presence probe + static caps) and pluggable ones
# (adapter presence IS backend presence).
resolve_caps() {
  if is_known "$1"; then
    is_present "$1" || return 1
    caps_for "$1"
  else
    valid_name "$1" || return 1
    adapter_caps "$1"
  fi
}

# Unattended-eligible: an autonomous tower may silently pick it. True iff the
# advertised set has interactive=false (never strand a run waiting on a human)
# AND session_grade!=deferred (excludes the manual `print` rung, whose spawn is
# deferred to a human). Reads the six-field caps string on $1.
eligible() {
  f_i='' f_g='' f_rest=''
  read -r f_i f_o f_s f_a f_p f_g f_rest <<EOF
$1
EOF
  [ "$f_i" = false ] && [ "$f_g" != deferred ]
}

# Print one detect TSV row: $1 backend, $2 six-field caps string. Read targets
# are `f_`-prefixed so this helper never clobbers a caller's loop variable.
emit_row() {
  er_b=$1
  read -r f_i f_o f_s f_a f_p f_g f_rest <<EOF
$2
EOF
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$er_b" "$f_i" "$f_o" "$f_s" "$f_a" "$f_p" "$f_g"
}

cmd_detect() {
  # Richest rung first: tmux, then advertised pluggables (arg order), then the
  # shipped autonomous rung, the terminal rung, and the manual rung.
  is_present tmux && emit_row tmux "$(caps_for tmux)"
  seen=' '
  for p in "$@"; do
    is_known "$p" && continue
    if ! valid_name "$p"; then
      printf '%s\n' "orchestrate-backends: ignoring invalid backend name: $(sanitize_printable "$p" "(unprintable name)")" >&2
      continue
    fi
    case "$seen" in
      *" $p "*) continue ;;
    esac
    seen="$seen$p "
    if ! caps=$(adapter_caps "$p"); then
      echo "orchestrate-backends: no usable adapter for pluggable backend: $p" >&2
      continue
    fi
    emit_row "$p" "$caps"
  done
  is_present subagent && emit_row subagent "$(caps_for subagent)"
  emit_row in-session "$(caps_for in-session)"
  emit_row print "$(caps_for print)"
  return 0
}

cmd_select_unattended() {
  configured=${1-}
  if [ -z "$configured" ]; then
    echo "usage: orchestrate-backends.sh select-unattended <configured>" >&2
    return 2
  fi
  # A pluggable configured name must be a valid identifier before it reaches the
  # adapter command; a hostile name is a usage error, not a silent degrade.
  if ! is_known "$configured" && ! valid_name "$configured"; then
    printf '%s\n' "orchestrate-backends: invalid backend name: $(sanitize_printable "$configured" "(unprintable name)")" >&2
    return 2
  fi

  # 1. The configured backend, when present and autonomously selectable, wins.
  if caps=$(resolve_caps "$configured") && eligible "$caps"; then
    printf '%s\n' "$configured"
    return 0
  fi

  # 2. Degrade down the shipped autonomous chain: subagent, then the always-
  #    present in-session terminal rung. Never interactive, never manual `print`.
  for rung in subagent in-session; do
    if caps=$(resolve_caps "$rung") && eligible "$caps"; then
      echo "NOTE: unattended backend '$configured' is unavailable or not autonomously selectable; degraded to '$rung' (never an interactive backend)." >&2
      printf '%s\n' "$rung"
      return 0
    fi
  done

  # in-session is always present and eligible, so the loop always returns; this
  # is an unreachable fail-closed guard.
  echo "orchestrate-backends: no eligible backend (the in-session terminal rung was unavailable)" >&2
  return 1
}

sub=${1-}
[ "$#" -gt 0 ] && shift
case "$sub" in
  detect) cmd_detect "$@" ;;
  select-unattended) cmd_select_unattended "$@" ;;
  '' | help | -h | --help)
    echo "usage: orchestrate-backends.sh {detect [pluggable-name...] | select-unattended <configured>}" >&2
    exit 2
    ;;
  *)
    echo "orchestrate-backends: unknown subcommand: $sub" >&2
    exit 2
    ;;
esac
