#!/bin/bash
# Tests for the `mise run release` and `mise run release-arm` wrappers
# (autopilot-reflex Task 7 / D-8 / REQ-F1.3 for `release`; release-hardening
# Task 7 / D-9 / REQ-F1.1 for `release-arm`). Repo-local ergonomics wrappers
# over scripts/release-publish.sh and scripts/release-arm.sh; the scripts
# themselves have no mise dependency (REQ-D1.9), so these are definition
# assertions over mise.toml — they need no mise binary and run in plain CI.
#
# Contract under test:
#   - mise.toml defines a `release` task whose `run` invokes
#     scripts/release-publish.sh;
#   - mise.toml defines a `release-arm` task whose `run` invokes
#     scripts/release-arm.sh and forwards the required <pr> argument;
#   - scripts/release-arm.sh carries no mise dependency (directly invokable).
#
# When the `mise` binary is available the test additionally confirms `mise tasks`
# lists each task (the test-spec's `[test]` surface), but never depends on it.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
MISE_TOML="$here/../mise.toml"
failures=0

[ -f "$MISE_TOML" ] || {
  echo "FAIL: mise.toml missing" >&2
  exit 1
}

assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 — expected [$3], got [$2]" >&2
    failures=$((failures + 1))
  fi
}

# Extract the `run` value(s) declared under the [tasks.release] table. The table
# header may be `[tasks.release]` or the quoted `[tasks."release"]` form; capture
# every line from the header until the next `[` section header and keep the ones
# assigning `run`.
release_run=$(awk '
  /^\[/ {
    in_release = ($0 == "[tasks.release]" || $0 == "[tasks.\"release\"]")
    next
  }
  in_release && /run[[:space:]]*=/ { print }
' "$MISE_TOML")

# 1. The release task exists.
if [ -n "$release_run" ]; then
  echo "ok: mise.toml defines a [tasks.release] task"
else
  echo "FAIL: mise.toml defines a [tasks.release] task — none found" >&2
  failures=$((failures + 1))
fi

# 2. Its run command invokes the publish script.
case "$release_run" in
  *scripts/release-publish.sh*) echo "ok: the release task invokes scripts/release-publish.sh" ;;
  *)
    echo "FAIL: the release task invokes scripts/release-publish.sh — got [$release_run]" >&2
    failures=$((failures + 1))
    ;;
esac

# 3. Bonus, only when a mise binary is present: `mise tasks` lists `release`.
if command -v mise >/dev/null 2>&1; then
  if (cd "$here/.." && mise tasks 2>/dev/null | grep -Eq '^release([[:space:]]|$)'); then
    echo "ok: mise tasks lists release"
  else
    echo "FAIL: mise tasks does not list release" >&2
    failures=$((failures + 1))
  fi
else
  echo "ok: mise binary absent — definition assertion only (no mise dependency)"
fi

# --- release-arm task (release-hardening REQ-F1.1, D-9) ----------------------
# The armed watch-and-publish wrapper, held to the same thin-wrapper contract as
# `release`: a [tasks.release-arm] table whose `run` invokes
# scripts/release-arm.sh and forwards the required <pr> argument, over a script
# that keeps no mise dependency.
#
# Argument forwarding is asserted structurally rather than by executing the
# script (running release-arm.sh with a real PR queries git/gh): mise appends a
# task's trailing CLI arguments to the last command of a bare `run`, so a run
# that is exactly the script invocation — with no baked-in positional argument
# to shadow it — forwards `mise run release-arm <pr>` through to
# `release-arm.sh <pr>`. A run carrying a fixed positional fails this assertion.

# Extract the `run` value under [tasks.release-arm] (bare or quoted header),
# stripping the surrounding single or double quotes.
arm_run=$(awk '
  /^\[/ {
    in_arm = ($0 == "[tasks.release-arm]" || $0 == "[tasks.\"release-arm\"]")
    next
  }
  in_arm && /run[[:space:]]*=/ {
    sub(/^[[:space:]]*run[[:space:]]*=[[:space:]]*/, "")
    sub(/^["'\'']/, "")
    sub(/["'\''][[:space:]]*$/, "")
    print
  }
' "$MISE_TOML")

# 4. The release-arm task exists.
if [ -n "$arm_run" ]; then
  echo "ok: mise.toml defines a [tasks.release-arm] task"
else
  echo "FAIL: mise.toml defines a [tasks.release-arm] task — none found" >&2
  failures=$((failures + 1))
fi

# 5. Its run command invokes the arm script.
case "$arm_run" in
  *scripts/release-arm.sh*) echo "ok: the release-arm task invokes scripts/release-arm.sh" ;;
  *)
    echo "FAIL: the release-arm task invokes scripts/release-arm.sh — got [$arm_run]" >&2
    failures=$((failures + 1))
    ;;
esac

# 6. It forwards <pr>: the run is exactly the bare script invocation, so mise's
#    trailing-argument append delivers <pr> to release-arm.sh unchanged.
assert_eq "the release-arm task forwards <pr> (bare thin wrapper, no fixed args)" "$arm_run" "scripts/release-arm.sh"

# 7. release-arm.sh itself carries no mise dependency (directly invokable,
#    portability floor). Grep non-comment lines for a `mise` invocation so a
#    comment merely mentioning mise does not trip it.
ARM_SCRIPT="$here/../scripts/release-arm.sh"
if [ -f "$ARM_SCRIPT" ]; then
  if grep -vE '^[[:space:]]*#' "$ARM_SCRIPT" | grep -Eq '(^|[^[:alnum:]_])mise([^[:alnum:]_]|$)'; then
    echo "FAIL: scripts/release-arm.sh must carry no mise dependency — a mise invocation was found" >&2
    failures=$((failures + 1))
  else
    echo "ok: scripts/release-arm.sh carries no mise dependency (directly invokable)"
  fi
else
  echo "FAIL: scripts/release-arm.sh missing" >&2
  failures=$((failures + 1))
fi

# 8. Bonus, only when a mise binary is present: `mise tasks` lists `release-arm`.
if command -v mise >/dev/null 2>&1; then
  if (cd "$here/.." && mise tasks 2>/dev/null | grep -Eq '^release-arm([[:space:]]|$)'); then
    echo "ok: mise tasks lists release-arm"
  else
    echo "FAIL: mise tasks does not list release-arm" >&2
    failures=$((failures + 1))
  fi
else
  echo "ok: mise binary absent — release-arm definition assertion only (no mise dependency)"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "PASS: test-release-mise-task.sh"
