#!/bin/bash
# Tests for the `mise run release` wrapper (autopilot-reflex Task 7; D-8;
# REQ-F1.3). A repo-local ergonomics wrapper over scripts/release-publish.sh;
# the script itself has no mise dependency (REQ-D1.9), so this is a definition
# assertion over mise.toml — it needs no mise binary and runs in plain CI.
#
# Contract under test:
#   - mise.toml defines a `release` task;
#   - that task's `run` invokes scripts/release-publish.sh.
#
# When the `mise` binary is available the test additionally confirms `mise tasks`
# lists `release` (the test-spec's `[test]` surface), but never depends on it.
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

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "PASS: test-release-mise-task.sh"
