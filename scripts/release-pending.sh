#!/usr/bin/env bash
# release-pending.sh — the release comparator (autopilot-reflex Task 4; D-7, D-8;
# REQ-D1.8). Answers one question mechanically: is a release pending? It reads
# the version of truth (the `version_file` knob) from the current checkout and
# compares it to the latest release tag.
#
# This is the ONE definition of "pending" the untagged-window lock (Task 6) and
# the bookkeeping surface (Task 7) both call, so the two never drift on what
# counts as a pending release (REQ-D1.8). It is read-only: it inspects git and a
# file, mutates nothing.
#
# Output (stdout, exit 0):
#   pending<TAB><version>   the version of truth is ahead of the latest release
#                           tag, or there is no release tag yet (first release)
#   none                    the version of truth is NOT ahead of the latest
#                           release tag (equal — nothing to release; a version of
#                           truth strictly behind the latest tag is also `none`,
#                           since there is likewise nothing to cut)
# On a malformed version of truth or an unreadable version_file: a diagnostic on
# stderr and exit 2. Usage error: exit 2.
#
# Usage: release-pending.sh
#   Run inside the repo. The version_file knob (config-get.sh) selects the
#   version of truth; the default is `.claude-plugin/plugin.json::$.version`.

set -u
LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"
# shellcheck source=scripts/release-lib.sh
. "$script_dir/release-lib.sh"

if [ "$#" -gt 0 ]; then
  echo "release-pending: usage: release-pending.sh (no arguments)" >&2
  exit 2
fi

# Resolve where the version of truth lives (path + selector), through the knob.
IFS=$(printf '\t')
read -r vf_path vf_sel < <(rl_resolve_version_file "$script_dir")
unset IFS

# Guard path access (security-posture.md): the parsed version_file path must be
# repo-relative — an absolute path or a `..` path component (traversal) is a clean
# refusal. The `..` test is on a COMPONENT (`/../`), so a legitimate filename that
# merely contains two dots (e.g. `v..x`) is not falsely rejected.
case "$vf_path" in
  /* | "")
    echo "release-pending: version_file must be a non-empty repo-relative path: '$(sanitize_printable "$vf_path")'" >&2
    exit 2
    ;;
esac
case "/$vf_path/" in
  */../*)
    echo "release-pending: version_file must not use a '..' path component: '$(sanitize_printable "$vf_path")'" >&2
    exit 2
    ;;
esac

# Canonicalize the version_file path (resolving symlinks in EVERY component,
# including the leaf `version_file` itself) and confirm it stays within the repo
# root, then read the canonicalized real path — never the original $vf_path,
# which a leaf symlink could re-defeat (REQ-D1.1, D-5, security-posture.md). A
# path escaping the tree, or an unresolvable one (dangling symlink / loop), is a
# clean refusal here. The absolute-path and `..`-component checks above stay as
# the cheap pre-filters.
if ! vf_real=$(rl_canonical_contained_path "$vf_path"); then
  echo "release-pending: version_file resolves outside the repository or cannot be canonicalized: '$(sanitize_printable "$vf_path")'" >&2
  exit 2
fi

if [ ! -f "$vf_real" ]; then
  echo "release-pending: version_file not found: $(sanitize_printable "$vf_path")" >&2
  exit 2
fi

vot=$(rl_extract_version "$vf_sel" <"$vf_real") || exit 2
if [ -z "$vot" ] || ! rl_valid_semver "$vot"; then
  echo "release-pending: version of truth is not valid SemVer: '$(sanitize_printable "$vot")'" >&2
  exit 2
fi

latest=$(rl_latest_release_tag)
if [ -z "$latest" ]; then
  # No release tags yet — the first release is always pending.
  printf 'pending\t%s\n' "$vot"
  exit 0
fi

if rl_version_gt "$vot" "${latest#v}"; then
  printf 'pending\t%s\n' "$vot"
else
  printf 'none\n'
fi
exit 0
