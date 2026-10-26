# shellcheck shell=bash
# hermetic-env.sh — the one list of configuration and root variables a suite
# must not inherit, and the helpers that clear or pin them (sourced, never
# executed). A suite run by hand inherits the operator's shell, and a suite
# run from a fleet worker inherits the worker's: a root variable pointing at an
# installed plugin, an overlay path, or the operator's real fleet home then
# decides what the code under test reads, so the test passes or fails on the
# host rather than on the code.
#
# Sourcing clears every cleared variable, so a suite conforms by sourcing this
# file before it reads or sets one. The pinned variables (the fleet home's
# resolution chain) are left in place: clearing them would fall through to the
# operator's default home, so a suite that writes fleet state pins them per
# case with fleet_home_pin instead.
#
# The list is the single source scripts/run-tests.sh pins per file,
# scripts/check-test-hermeticity.sh checks suites against, and the perturbed
# CI run sets decoys for. Add a variable here, never in a suite.
#
#   hermetic_env_names        print every listed variable, one per line
#   hermetic_env_clear        unset the cleared variables (sourcing runs it)
#   hermetic_env_sentinel <dir>
#                             point the pinned variables at arms under <dir>:
#                             the fleet override always, the plugin-data and
#                             writer arms only when set, so a file sees the
#                             set/unset shape it would have seen without it;
#                             fails when a pinned variable has no arm
#   hermetic_env_sentinel_written <dir>
#                             succeed when anything exists at a pinned arm
#                             under <dir>: a write that would have landed in
#                             the inherited home. A pinned variable with no
#                             arm also succeeds, since it cannot be checked
#   fleet_home_pin <dir>      point every arm of the fleet chain at <dir>, an
#                             absolute path it can create (else it fails and
#                             pins nothing): the override at <dir>/fleet, the
#                             plugin-data arm at <dir>/plugin-data, the writer
#                             arm at <dir>/claude. The first call of any
#                             fleet_home verb remembers the home the inherited
#                             environment resolved to, so later pins (one per
#                             case) never mistake a fixture for the inherited
#                             home
#   fleet_home_leaked <path>  succeed when the inherited registry names <path>;
#                             pass the suite's own mktemp root, which no real
#                             record can carry, so a concurrent real fleet
#                             write is never read as this suite's leak. The
#                             records are read through fleet-state.sh's own
#                             registry verb, so the check follows wherever
#                             that store keeps them. A check that cannot run
#                             (no fleet-state.sh to reach, or its registry
#                             verb failing) also succeeds, naming why on
#                             stderr
#   fleet_home_inherited      print the inherited fleet home (empty when the
#                             inherited environment resolved none)
#   hermetic_access_denied <r|w> <path>
#                             succeed when the running user is actually denied
#                             that access. Root, or a capability override,
#                             reads and writes what the mode bits forbid, so a
#                             mode-bit fixture probes this before asserting a
#                             refusal and skips by name when it fails
#
# A shell that needs the list without clearing its own environment (the
# runner, which clears per file and can be told not to) sets
# _hermetic_env_defer=1 before sourcing.

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
  mkdir -p "$1" || return 1
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
