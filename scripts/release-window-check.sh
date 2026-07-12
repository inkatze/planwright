#!/usr/bin/env bash
# release-window-check.sh — the untagged-window lock (autopilot-reflex Task 6;
# D-7; REQ-E1.1, REQ-E1.2). A required CI check that FAILS while the version of
# truth is ahead of the latest release tag (the untagged window) and PASSES
# otherwise, so that after a release PR merges no further merge can land until
# the tag is published (autopilot-reflex step 4: surface by forcing-function,
# never by pull). The failure names the publish command, so the only structural
# path forward is to publish.
#
# It reuses scripts/release-pending.sh — the ONE definition of "pending"
# (REQ-D1.8) that the bookkeeping surface (Task 7) also shares — so the lock and
# the surfacing never drift on what counts as a pending release. This script
# adds only the pass/fail translation and the actionable message; it computes no
# version logic of its own.
#
# The lock is a property of `main`. In CI, run it against `main`'s state: on a
# push to `main` that is the checkout; on a pull_request or a merge_group,
# check out the base branch (`main`) first — see the workflow templates. Reading
# the release-PR head instead would re-create the chicken-and-egg D-7 rejects:
# the release PR bumps the version, so a head read would fail (and block) the
# very PR that opens — and is about to close — the window.
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
# Usage: release-window-check.sh   (run inside the repo; no arguments)

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

if [ "$#" -gt 0 ]; then
  echo "release-window-check: usage: release-window-check.sh (no arguments)" >&2
  exit 2
fi

pending_script="$script_dir/release-pending.sh"
if [ ! -x "$pending_script" ]; then
  echo "release-window-check: scripts/release-pending.sh missing or not executable" >&2
  exit 2
fi

# Reuse the shared comparator (REQ-D1.8): `pending<TAB><version>` or `none` on
# exit 0, exit 2 on a malformed/unreadable version of truth. A non-zero exit is
# a comparator failure — fail closed, never pass on an indeterminate state.
if ! status_line=$("$pending_script"); then
  echo "release-window-check: release comparator failed; cannot determine the release state (failing closed)" >&2
  exit 2
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
