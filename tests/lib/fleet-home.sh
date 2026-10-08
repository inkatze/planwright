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
#                             arm at <dir>/claude. The first call also
#                             remembers the registry the inherited environment
#                             resolved to, so later pins (one per case) never
#                             mistake a fixture for the inherited home
#   fleet_home_leaked <path>  succeeds when the inherited registry names
#                             <path>; pass the suite's own mktemp root, which
#                             no real record can carry, so a concurrent real
#                             fleet write is never read as this suite's leak
#   fleet_home_inherited      print the inherited registry path (empty when
#                             the inherited environment resolved no home)

_fh_lib_dir=${BASH_SOURCE[0]%/*}
_fh_inherited=""
_fh_resolved=0

fleet_home_pin() {
  if [ "$_fh_resolved" -eq 0 ]; then
    _fh_home=$(/bin/sh "$_fh_lib_dir/../../scripts/fleet-state.sh" root 2>/dev/null) || _fh_home=""
    [ -z "$_fh_home" ] || _fh_inherited="${_fh_home%/}/registry"
    _fh_resolved=1
  fi
  case $1 in
    /*) ;;
    *) return 1 ;;
  esac
  mkdir -p "$1" || return 1
  export PLANWRIGHT_FLEET_STATE_DIR="$1/fleet"
  export CLAUDE_PLUGIN_DATA="$1/plugin-data"
  export CLAUDE_DIR="$1/claude"
}

fleet_home_leaked() {
  [ -n "$_fh_inherited" ] && [ -f "$_fh_inherited" ] || return 1
  grep -qF -- "$1" "$_fh_inherited"
}

fleet_home_inherited() {
  printf '%s\n' "$_fh_inherited"
}
