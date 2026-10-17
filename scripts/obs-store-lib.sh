# shellcheck shell=sh
# obs-store-lib.sh — the observation store's default location (sourced, never
# executed), so each observation script defaults its store the same way
# (custom-spec-location D-17, REQ-F1.1).
#
# obs_default_store <script-dir> — print the store, _observations under the
# spec root's checkout-local view (scripts/resolve-root.sh spec beside the
# caller). A store below the working directory is printed relative to it, so
# a run from the checkout's top names the paths it always named. Returns
# non-zero, printing nothing, when the root does not resolve: the resolver has
# said why on stderr, and the caller refuses rather than compose a path.
obs_default_store() {
  ods_root=$(/bin/sh "$1/resolve-root.sh" spec) || return 1
  [ -n "$ods_root" ] || return 1
  ods_here=$(pwd -P) || return 1
  case $ods_root in
    "$ods_here"/*) printf '%s/_observations\n' "${ods_root#"$ods_here"/}" ;;
    *) printf '%s/_observations\n' "$ods_root" ;;
  esac
}
