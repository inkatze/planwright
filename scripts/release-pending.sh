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
#   none                    the version of truth equals the latest release tag
# On a malformed version of truth or an unreadable version_file: a diagnostic on
# stderr and exit 2. Usage error: exit 2.
#
# Usage: release-pending.sh
#   Run inside the repo. The version_file knob (config-get.sh) selects the
#   version of truth; the default is `.claude-plugin/plugin.json#$.version`.

set -u
LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd)
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

if [ -z "$vf_path" ] || [ ! -f "$vf_path" ]; then
  echo "release-pending: version_file not found: ${vf_path:-<empty>}" >&2
  exit 2
fi

vot=$(rl_extract_version "$vf_sel" <"$vf_path") || exit 2
if [ -z "$vot" ] || ! rl_valid_semver "$vot"; then
  echo "release-pending: version of truth is not valid SemVer: '${vot}'" >&2
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
