# shellcheck shell=sh
# obs-store-lib.sh — the observation store's default location (sourced, never
# executed), so each observation script defaults its store the same way
# (custom-spec-location D-17, REQ-F1.1).
#
# obs_default_store <script-dir> — print the store, _observations under the
# spec root's checkout-local view (scripts/resolve-root.sh spec beside the
# caller). A store below the working directory is printed relative to it, so
# a run from the checkout's top names the paths it always named; one opening
# with a hyphen gets a ./ so no caller reads it as an option. Returns
# non-zero, printing nothing, when the root does not resolve: the resolver has
# said why on stderr, and the caller refuses rather than compose a path.
#
# obs_default_store <script-dir> write — the same, for a caller about to write:
# returns 3, saying why, when a root other than the checkout's specs/ is absent
# from this checkout. Such a root is untracked or ignored here (a fresh
# worktree), so a store created in its place would be lost with the checkout.
obs_default_store() {
  ods_root=$(/bin/sh "$1/resolve-root.sh" spec) || return 1
  [ -n "$ods_root" ] || return 1
  if [ "${2:-}" = write ] && [ ! -d "$ods_root" ]; then
    ods_top=$(
      unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
        GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
      git rev-parse --show-toplevel 2>/dev/null
    ) || ods_top=""
    if [ -z "$ods_top" ] || [ "$ods_root" != "$ods_top/specs" ]; then
      printf 'planwright: the spec root %s is not present in this checkout, so a fragment written there would be lost with it\n' \
        "$(printf '%s' "$ods_root" | tr -d '\000-\037\177')" >&2
      return 3
    fi
  fi
  ods_here=$(pwd -P) || return 1
  case $ods_root in
    "$ods_here"/-*) printf './%s/_observations\n' "${ods_root#"$ods_here"/}" ;;
    "$ods_here"/*) printf '%s/_observations\n' "${ods_root#"$ods_here"/}" ;;
    *) printf '%s/_observations\n' "$ods_root" ;;
  esac
}
