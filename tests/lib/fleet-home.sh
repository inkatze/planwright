# shellcheck shell=bash
# fleet-home.sh — keep a suite's fleet writes inside its own fixture home
# (sourced, never executed). The fleet home resolves through an inherited
# chain (scripts/fleet-state.sh resolve_root): a suite run from a fleet
# worker inherits the operator's PLANWRIGHT_FLEET_STATE_DIR, so a case that
# registers a worker without pinning the home writes the operator's real
# registry.
#
#   fleet_home_pin <dir>      point every arm of the chain at <dir>, an
#                             absolute path it can create (else it fails and
#                             pins nothing): the override at <dir>/fleet, the
#                             plugin-data arm at <dir>/plugin-data, the writer
#                             arm at <dir>/claude. The first call of any verb
#                             here remembers the home the inherited
#                             environment resolved to, so later pins (one per
#                             case) never mistake a fixture for the inherited
#                             home
#   fleet_home_leaked <path>  succeeds when the inherited registry names
#                             <path>; pass the suite's own mktemp root, which
#                             no real record can carry, so a concurrent real
#                             fleet write is never read as this suite's leak.
#                             The records are read through fleet-state.sh's
#                             own registry verb, so the check follows wherever
#                             that store keeps them
#   fleet_home_inherited      print the inherited fleet home (empty when the
#                             inherited environment resolved none)

_fh_lib_dir=${BASH_SOURCE[0]%/*}
_fh_home=""
_fh_resolved=0

# The inherited home is captured once, before any pin rewrites the chain, by
# whichever verb runs first.
_fh_capture() {
  [ "$_fh_resolved" -eq 0 ] || return 0
  _fh_home=$(/bin/sh "$_fh_lib_dir/../../scripts/fleet-state.sh" root 2>/dev/null) || _fh_home=""
  _fh_resolved=1
}

fleet_home_pin() {
  _fh_capture
  case $1 in
    /*) ;;
    *) return 1 ;;
  esac
  mkdir -p "$1" || return 1
  export PLANWRIGHT_FLEET_STATE_DIR="$1/fleet"
  export CLAUDE_PLUGIN_DATA="$1/plugin-data"
  export CLAUDE_DIR="$1/claude"
}

# The -d guard keeps the read from creating a home that does not exist: the
# registry verb makes the home it resolves, and this one is the caller's.
fleet_home_leaked() {
  _fh_capture
  [ -n "$_fh_home" ] && [ -d "$_fh_home" ] || return 1
  _fh_records=$(PLANWRIGHT_FLEET_STATE_DIR="$_fh_home" /bin/sh "$_fh_lib_dir/../../scripts/fleet-state.sh" registry 2>/dev/null) || return 1
  case $_fh_records in
    *"$1"*) return 0 ;;
  esac
  return 1
}

fleet_home_inherited() {
  _fh_capture
  printf '%s\n' "$_fh_home"
}
