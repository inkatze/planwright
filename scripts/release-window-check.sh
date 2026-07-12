#!/usr/bin/env bash
# release-window-check.sh — the untagged-window lock (autopilot-reflex Task 6;
# D-7; REQ-E1.1, REQ-E1.2). A required CI check that FAILS while the version of
# truth is ahead of the latest release tag (the untagged window) and PASSES
# otherwise, so that after a release PR merges no further merge can land until
# the tag is published (autopilot-reflex step 4: surface by forcing-function,
# never by pull). The failure names the publish command, so the only structural
# path forward is to publish.
#
# It reuses the ONE shared definition of "pending" (REQ-D1.8) that the
# bookkeeping surface (Task 7) also shares, so the lock and the surfacing never
# drift on what counts as a pending release: with no --ref it delegates to
# scripts/release-pending.sh verbatim; with --ref it evaluates the same
# comparison (scripts/release-lib.sh's rl_* — the functions release-pending.sh
# is itself built on) against a git ref. This script adds only the pass/fail
# translation and the actionable message; it computes no version logic of its
# own.
#
# The lock is a property of `main`. In CI the SCRIPT must run from the PR
# checkout (so this file exists), while the STATE evaluated must be `main`'s —
# so CI passes `--ref origin/main`. Evaluating the PR head's version instead
# would re-create the chicken-and-egg D-7 rejects: the release PR bumps the
# version, so a head read would fail (and block) the very PR that opens — and is
# about to close — the window. Reading a ref (not checking `main` out wholesale)
# also means the check never depends on this script already living on `main`,
# which it does not on the PR that introduces it.
#
# Exit status:
#   0  no open window — the version of truth is not ahead of the latest release
#      tag (equal, or no bump). Merges may proceed.
#   1  open window — a release is pending; publish before merging. The message
#      names scripts/release-publish.sh.
#   2  usage error, or the comparator failed (FAIL CLOSED — an unreadable or
#      malformed version of truth blocks rather than silently passing; the lock
#      never lets a merge through on a state it could not determine).
#
# Usage: release-window-check.sh [--ref <gitref>]
#   (no --ref)  evaluate the current checkout's version of truth (the working
#               tree); delegates to release-pending.sh.
#   --ref R     evaluate ref R's version of truth (CI base-reading: run the PR's
#               script, judge main's state — pass `--ref origin/main`).

set -u
LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

# The human-gated, signed publish step (Task 4). Named in the block message so
# the forcing function is actionable, not just obstructive.
publish_cmd="scripts/release-publish.sh"

usage() {
  echo "release-window-check: usage: release-window-check.sh [--ref <gitref>]" >&2
  exit 2
}

ref=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ref)
      [ "$#" -ge 2 ] || usage
      ref="$2"
      [ -n "$ref" ] || usage
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if [ -z "$ref" ]; then
  # Working-tree path: reuse release-pending.sh verbatim (REQ-D1.8). It prints
  # `pending<TAB><version>` or `none` on exit 0, exit 2 on a malformed/unreadable
  # version of truth. A non-zero exit is a comparator failure — fail closed.
  pending_script="$script_dir/release-pending.sh"
  if [ ! -x "$pending_script" ]; then
    echo "release-window-check: scripts/release-pending.sh missing or not executable" >&2
    exit 2
  fi
  if ! status_line=$("$pending_script"); then
    echo "release-window-check: release comparator failed; cannot determine the release state (failing closed)" >&2
    exit 2
  fi
else
  # Ref path: the same shared definition (release-lib.sh), version sourced from
  # <ref> instead of the working tree, so CI can run the PR's script yet judge
  # main's state.
  # shellcheck source=scripts/release-lib.sh
  . "$script_dir/release-lib.sh"

  # The version_file LOCATION (path + selector) is resolved from this checkout's
  # config; the version VALUE is read from <ref> below. For the release lock
  # this asymmetry is intended — run the PR's config, judge main's version. The
  # lock guards forgetting to publish, not a merge-capable actor swapping the
  # version_file knob (a reviewed, human-merged config change with bigger levers
  # available to it anyway).
  IFS=$(printf '\t')
  read -r vf_path vf_sel < <(rl_resolve_version_file "$script_dir")
  unset IFS

  # Path guards mirror release-pending.sh: the version_file selector is
  # repo-relative data, never an absolute path or a `..` traversal.
  case "$vf_path" in
    /* | "")
      echo "release-window-check: version_file must be a non-empty repo-relative path: '$(sanitize_printable "$vf_path")'" >&2
      exit 2
      ;;
  esac
  case "/$vf_path/" in
    */../*)
      echo "release-window-check: version_file must not use a '..' path component: '$(sanitize_printable "$vf_path")'" >&2
      exit 2
      ;;
  esac

  if ! blob=$(git show "$ref:$vf_path" 2>/dev/null); then
    echo "release-window-check: cannot read version_file '$(sanitize_printable "$vf_path")' at ref '$(sanitize_printable "$ref")' (failing closed)" >&2
    exit 2
  fi
  if ! vot=$(printf '%s' "$blob" | rl_extract_version "$vf_sel"); then
    echo "release-window-check: could not extract the version of truth at ref '$(sanitize_printable "$ref")' (failing closed)" >&2
    exit 2
  fi
  if [ -z "$vot" ] || ! rl_valid_semver "$vot"; then
    echo "release-window-check: version of truth at ref '$(sanitize_printable "$ref")' is not valid SemVer: '$(sanitize_printable "$vot")' (failing closed)" >&2
    exit 2
  fi

  latest=$(rl_latest_release_tag)
  if [ -z "$latest" ] || rl_version_gt "$vot" "${latest#v}"; then
    status_line=$(printf 'pending\t%s' "$vot")
  else
    status_line="none"
  fi
fi

tab=$(printf '\t')
state=${status_line%%"$tab"*}

case "$state" in
  pending)
    version=${status_line#*"$tab"}
    {
      printf 'release-window-check: untagged window OPEN — version of truth %s is ahead of the latest release tag.\n' \
        "$(sanitize_printable "$version" '<unprintable>')"
      echo "release-window-check: a release is pending; no further merge should land until the signed tag is published."
      printf 'release-window-check: publish the signed tag with: %s\n' "$publish_cmd"
    } >&2
    exit 1
    ;;
  none)
    echo "release-window-check: no open untagged window — nothing to publish; merges may proceed."
    exit 0
    ;;
  *)
    printf 'release-window-check: unexpected comparator output: %s (failing closed)\n' \
      "$(sanitize_printable "$status_line" '<unprintable>')" >&2
    exit 2
    ;;
esac
