# shellcheck shell=bash
# hermetic-env.sh — the one list of configuration and root variables a suite
# must not inherit, and the helpers that clear or pin them (sourced, never
# executed). An inherited root, overlay or fleet-home variable decides what the
# code under test reads, so the test passes or fails on the host.
#
# Sourcing clears the cleared variables. The pinned ones (the fleet home's
# chain) stay, since clearing them would fall through to the operator's home;
# a suite that writes fleet state pins them per case with fleet_home_pin.
# scripts/run-tests.sh pins the same list per file and
# scripts/check-test-hermeticity.sh checks suites against it: add a variable
# here, never in a suite. _hermetic_env_defer=1 before sourcing skips clearing.
#
#   hermetic_env_names, hermetic_env_clear   print / unset the listed variables
#   hermetic_env_sentinel <dir>    point the pinned ones under <dir>; fails when
#                                  one has no arm
#   hermetic_env_sentinel_written <dir>
#                                  succeed when anything exists at a pinned arm
#   fleet_home_pin <dir>           pin every arm of the chain under an absolute
#                                  <dir>; fleet_home_leaked <path> and
#                                  fleet_home_inherited read the inherited home
#   hermetic_access_denied <r|w> <path>
#                                  succeed when the user is really denied that
#                                  access (root is not)

hermetic_env_cleared='
  PLANWRIGHT_ROOT
  PLANWRIGHT_REPO_ROOT
  PLANWRIGHT_REPO_ROOT_CHECKED
  PLANWRIGHT_SKILLS_ROOT
  PLANWRIGHT_WORKER_SPEC_ROOT
  PLANWRIGHT_ORCH_STATE_DIR
  PLANWRIGHT_ADOPTER_OVERLAY
  PLANWRIGHT_LOCAL_CONFIG
  PLANWRIGHT_CONFIG_DEFAULTS
  PLANWRIGHT_CONFIG_STRICT_OVERLAYS
  PLANWRIGHT_GUARD_CATALOG
  CLAUDE_PLUGIN_ROOT
  CLAUDE_PROJECT_DIR
  CLAUDE_CONFIG_DIR
'
hermetic_env_pinned='
  PLANWRIGHT_FLEET_STATE_DIR
  CLAUDE_PLUGIN_DATA
  CLAUDE_DIR
'

# A POSIX sh caller has no way to name the sourced file, so the fleet_home
# verbs, which find scripts/ from here, need bash; the rest runs under sh.
# The directory is made absolute now, since a suite may cd before it calls one.
_he_lib_dir=""
if [ -n "${BASH_VERSION:-}" ]; then
  eval '_he_lib_dir=${BASH_SOURCE[0]}'
  case $_he_lib_dir in
    */*) _he_lib_dir=${_he_lib_dir%/*} ;;
    *) _he_lib_dir=. ;;
  esac
  case $_he_lib_dir in
    /*) ;;
    *) _he_lib_dir=$PWD/$_he_lib_dir ;;
  esac
fi
_fh_home=""
_fh_resolved=0
_fh_unresolvable=0

hermetic_env_names() {
  for _he_v in $hermetic_env_cleared $hermetic_env_pinned; do
    printf '%s\n' "$_he_v"
  done
}

hermetic_env_clear() {
  for _he_v in $hermetic_env_cleared; do
    unset "$_he_v"
  done
}

# _he_arm <name>: set _he_a to the arm a pinned variable is redirected to,
# under a sentinel or fixture home; fails for a name with no arm. It sets
# rather than prints, so the per-file pinning costs no subshell.
_he_arm() {
  case $1 in
    PLANWRIGHT_FLEET_STATE_DIR) _he_a=fleet ;;
    CLAUDE_PLUGIN_DATA) _he_a=plugin-data ;;
    CLAUDE_DIR) _he_a=claude ;;
    *) return 1 ;;
  esac
}

# The fleet override is pinned even when unset: the chain falls back to a
# home under HOME otherwise, and that is the operator's.
hermetic_env_sentinel() {
  for _he_v in $hermetic_env_pinned; do
    _he_arm "$_he_v" || return 1
    if [ "$_he_v" = PLANWRIGHT_FLEET_STATE_DIR ] || eval "[ -n \"\${$_he_v+set}\" ]"; then
      export "$_he_v=$1/$_he_a"
    fi
  done
}

# A name with no arm cannot be checked, so it reads as written: fail closed.
hermetic_env_sentinel_written() {
  for _he_v in $hermetic_env_pinned; do
    _he_arm "$_he_v" || return 0
    if [ -e "$1/$_he_a" ] || [ -L "$1/$_he_a" ]; then
      return 0
    fi
  done
  return 1
}

# The inherited home is captured once, before any pin rewrites the chain, by
# whichever fleet_home verb runs first.
_fh_capture() {
  [ "$_fh_resolved" -eq 0 ] || return 0
  _fh_resolved=1
  if [ -z "$_he_lib_dir" ] || [ ! -r "$_he_lib_dir/../../scripts/fleet-state.sh" ]; then
    _fh_unresolvable=1
    return 0
  fi
  _fh_home=$(/bin/sh "$_he_lib_dir/../../scripts/fleet-state.sh" root 2>/dev/null) || _fh_home=""
}

fleet_home_pin() {
  _fh_capture
  case $1 in
    /*) ;;
    *) return 1 ;;
  esac
  mkdir -p -- "$1" || return 1
  for _he_v in $hermetic_env_pinned; do
    _he_arm "$_he_v" || return 1
    export "$_he_v=$1/$_he_a"
  done
}

# The -d guard keeps the read from creating a home that does not exist: the
# registry verb makes the home it resolves, and this one is the caller's. A
# check that cannot run reports a leak, never a clean home.
fleet_home_leaked() {
  _fh_capture
  if [ "$_fh_unresolvable" -eq 1 ]; then
    printf '%s\n' "fleet_home_leaked: scripts/fleet-state.sh is not reachable from tests/lib (sourced outside bash?); reporting a leak rather than a check that never ran" >&2
    return 0
  fi
  [ -n "$_fh_home" ] && [ -d "$_fh_home" ] || return 1
  if ! _fh_records=$(PLANWRIGHT_FLEET_STATE_DIR="$_fh_home" /bin/sh "$_he_lib_dir/../../scripts/fleet-state.sh" registry 2>/dev/null); then
    printf '%s\n' "fleet_home_leaked: the registry verb failed on the inherited home; reporting a leak rather than a check that never ran" >&2
    return 0
  fi
  case $_fh_records in
    *"$1"*) return 0 ;;
  esac
  return 1
}

fleet_home_inherited() {
  _fh_capture
  printf '%s\n' "$_fh_home"
}

hermetic_access_denied() {
  case $1 in
    r) [ ! -r "$2" ] ;;
    w) [ ! -w "$2" ] ;;
    *) return 2 ;;
  esac
}

[ "${_hermetic_env_defer:-0}" = 1 ] || hermetic_env_clear
