#!/usr/bin/env bash
# release-bookkeeping.sh — the belt-and-suspenders release surface for
# `/orchestrate --bookkeeping` (autopilot-reflex Task 7; D-7, D-8; REQ-F1.2).
#
# Surfacing is layered per reflex step 4 (D-7): the standing release PR is the
# push, the untagged-window lock is the forcing-function, and this bookkeeping
# report is the third, deliberately-redundant layer. It is NOT the primary
# surface — a release must never depend on someone running an out-of-session
# sweep — so it only ever *reports*: it mutates nothing and, being on a
# non-dispatch path, it never breaks the bookkeeping run it is folded into.
#
# It reads the single shared definition of "pending" (release-pending.sh, the
# comparator both this and the untagged-window lock call, REQ-D1.8) and:
#   - in the untagged window (comparator says `pending<TAB><version>`) prints a
#     one-line report naming the pending version and the publish command, so a
#     human/orchestrator sees the ceremony still owes a publish;
#   - outside the window (comparator says `none`) prints nothing — the surface
#     stays silent on releases (Task 7 Done-when);
#   - on any comparator trouble (absent, non-executable, or a non-zero exit on a
#     malformed version-of-truth) degrades with a diagnostic on stderr and exits
#     0, printing nothing on stdout. Belt-and-suspenders is a redundant reminder,
#     never a gate, so it must not fail an --bookkeeping pass (the skill's
#     "missing prerequisites degrade with a message" contract).
#
# Output (stdout): a single report line when a release is pending; empty otherwise.
# Exit: 0 always (a report or a silent/degraded no-op); this surface never blocks.
#
# Usage: release-bookkeeping.sh
#   Run inside the repo. Delegates the version-of-truth resolution and the
#   pending decision entirely to release-pending.sh.

set -u
LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

# The publish command this repo documents everywhere the release flow is named
# (release-please PR body, docs/options-reference.md): the portable script is the
# canonical command; `mise run release` is this repo's ergonomic shortcut (REQ-F1.3).
PUBLISH_CMD='scripts/release-publish.sh'
PUBLISH_SHORTCUT='mise run release'

comparator="$script_dir/release-pending.sh"
if [ ! -x "$comparator" ]; then
  echo "release-bookkeeping: comparator scripts/release-pending.sh is missing or not executable; skipping the release report" >&2
  exit 0
fi

# Run the shared comparator. On a non-zero exit (e.g. a malformed version of
# truth) it has already written its own diagnostic to stderr; add one line of
# our own context and degrade to a silent no-op rather than propagating failure.
if ! report=$("$comparator"); then
  echo "release-bookkeeping: release-pending.sh reported an error; skipping the release report" >&2
  exit 0
fi

# `none` (or empty) → nothing pending; stay silent on releases.
case "$report" in
  none | "")
    exit 0
    ;;
esac

# Otherwise the comparator emitted `pending<TAB><version>`. Split on the tab and
# validate the shape defensively; anything unexpected degrades silently.
tab=$(printf '\t')
state=${report%%"$tab"*}
version=${report#*"$tab"}
if [ "$state" != "pending" ] || [ "$version" = "$report" ] || [ -z "$version" ]; then
  echo "release-bookkeeping: unexpected comparator output; skipping the release report" >&2
  exit 0
fi

# The version came from release-pending.sh, which validated it against the SemVer
# grammar before emitting it; sanitize on the way to the terminal anyway (echo
# discipline, defense in depth).
safe_version=$(sanitize_printable "$version" "<unreadable>")
# The backticks in the format string are literal (a code-span convention for the
# terminal report), not command substitution — the values are passed as %s args.
# shellcheck disable=SC2016
printf 'release: v%s is pending. Run `%s` to sign and publish the annotated tag (repo shortcut: `%s`).\n' \
  "$safe_version" "$PUBLISH_CMD" "$PUBLISH_SHORTCUT"
exit 0
