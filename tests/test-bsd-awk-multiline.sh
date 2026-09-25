#!/bin/sh
# Regression tests for multi-line values reaching awk under one-true-awk (the
# BSD awk macOS ships as /usr/bin/awk). That awk rejects a newline inside a
# `-v name=value` assignment ("awk: newline in string ..."), exiting 2 before
# the program runs, where gawk and mawk accept it. A script that hands awk a
# newline-separated list through -v therefore works on Linux and fails on
# every Mac; such values travel through the environment (ENVIRON) instead.
#
# Properties verified, with a one-true-awk pinned first on PATH:
#   1. spec-validate.sh validates a conforming bundle clean: the citation-range
#      pass hands awk the bundle's newline-separated defined-id list.
#   2. fleet-attention.sh `queue --except` narrows by one and by two workers:
#      the hand-over list is newline-separated even for a single worker.
#
# Skips when no one-true-awk that rejects a newline in -v is installed (the
# Linux CI runners), since the failure mode cannot be reproduced there.
# PLANWRIGHT_TEST_BSD_AWK names a one-true-awk elsewhere (default /usr/bin/awk);
# PLANWRIGHT_TEST_REQUIRE_BSD_AWK=1 turns the skip into a failure, so a runner
# expected to carry that awk cannot go silently green without it.
#
# Runs standalone: ./tests/test-bsd-awk-multiline.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
validator="$here/../scripts/spec-validate.sh"
FA="$here/../scripts/fleet-attention.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$validator" ] || fail "scripts/spec-validate.sh missing or not executable"
[ -x "$FA" ] || fail "scripts/fleet-attention.sh missing or not executable"

skip() {
  [ "${PLANWRIGHT_TEST_REQUIRE_BSD_AWK:-0}" != 1 ] || fail "setup: $1 (PLANWRIGHT_TEST_REQUIRE_BSD_AWK=1 forbids the skip)"
  echo "skip: $1"
  exit 0
}

bsd_awk=${PLANWRIGHT_TEST_BSD_AWK:-/usr/bin/awk}
case "$("$bsd_awk" --version 2>/dev/null || :)" in
  "awk version "*) ;;
  *) skip "no one-true-awk at $bsd_awk (the newline-in-assignment failure is BSD-awk-only)" ;;
esac
if "$bsd_awk" -v x="a
b" 'BEGIN { exit 0 }' 2>/dev/null; then
  skip "$bsd_awk accepts a newline in -v, so the failure mode cannot be reproduced here"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir "$tmp/bin"
ln -s "$bsd_awk" "$tmp/bin/awk"
PATH="$tmp/bin:$PATH"
export PATH
[ "$(command -v awk)" = "$tmp/bin/awk" ] || fail "setup: the pinned awk is not first on PATH"

# ---------------------------------------------------------------------------
# 1. The validator's citation-range pass survives a multi-id bundle.
# ---------------------------------------------------------------------------
b="$tmp/specs/fixture"
mkdir -p "$b"
cat >"$b/requirements.md" <<'EOF'
# Fixture — Requirements

**Status:** Draft
**Last reviewed:** 2026-06-12
**Format-version:** 1

## Goal

A fixture bundle.

## REQ-X — fixture group

- **REQ-X1.1** The widget SHALL exist.
  *(Cites: D-1.)*
- **REQ-X1.2** The gadget SHALL exist.
  *(Cites: D-1.)*

## Changelog

- 2026-06-12 — created.

## Sources

- the fixture seed.
EOF
cat >"$b/design.md" <<'EOF'
# Fixture — Design

**Status:** Draft
**Last reviewed:** 2026-06-12
**Format-version:** 1

## Decision log

### D-1: Widgets are good  (N)

**Decision:** Build widgets.

**Alternatives considered:**
- No widgets. Rejected because: nothing would exist.

**Chosen because:** widgets are the fixture's point.
EOF
cat >"$b/tasks.md" <<'EOF'
# Fixture — Tasks

**Status:** Draft
**Last reviewed:** 2026-06-12
**Format-version:** 1

## Forward plan

### Task 1 — Build the widget

- **Deliverables:** A widget.
- **Done when:** The widget exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-X1.1
- **Estimated effort:** half day

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
cat >"$b/test-spec.md" <<'EOF'
# Fixture — Test Spec

**Status:** Draft
**Last reviewed:** 2026-06-12
**Format-version:** 1

Coverage is a fixture mix.

### REQ-X1.1 — widget exists [test]

The widget fixture passes, per D-1 and Task 1.

### REQ-X1.2 — gadget exists [manual]

The gadget is exercised by hand.
EOF

rc=0
out=$("$validator" "$b" 2>&1) || rc=$?
case $out in *"newline in string"*) fail "1: awk rejected a multi-line -v value: $out" ;; esac
[ "$rc" -eq 0 ] || fail "1: expected exit 0, got $rc: $out"
case $out in *"is not defined in this bundle"*) fail "1: a defined id was reported undefined (the id list did not reach awk): $out" ;; esac
echo "ok: spec-validate.sh validates a multi-id bundle under one-true-awk"

# ---------------------------------------------------------------------------
# 2. fleet-attention's --except list survives one and two hand-overs.
# ---------------------------------------------------------------------------
aenv() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT \
    -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS \
    PLANWRIGHT_FLEET_STATE_DIR="$tmp/qhome" /bin/sh "$FA" "$@"
}
aenv decide "worker=a" "spec-one:3" "Ship it?" "yes" "yes|no" || fail "2 setup: decide a"
aenv decide "worker=b" "spec-two:5" "Rebase?" "no" "yes|no" || fail "2 setup: decide b"
aenv decide "worker=c" "spec-three:1" "Retry?" "no" "yes|no" || fail "2 setup: decide c"

out=$(aenv queue --except "worker=a" 2>&1) || fail "2: queue --except one worker exited non-zero: $out"
case $out in *"Ship it?"*) fail "2: --except did not drop worker=a (got: $out)" ;; esac
case $out in *"Rebase?"*"Retry?"* | *"Retry?"*"Rebase?"*) ;; *) fail "2: --except one worker lost another decision (got: $out)" ;; esac

out=$(aenv queue --except "worker=a" --except "worker=b" 2>&1) || fail "2: queue --except two workers exited non-zero: $out"
case $out in *"Ship it?"* | *"Rebase?"*) fail "2: --except did not drop both workers (got: $out)" ;; esac
case $out in *"Retry?"*) ;; *) fail "2: --except two workers lost the remaining decision (got: $out)" ;; esac
echo "ok: fleet-attention.sh queue --except narrows by one and by two workers under one-true-awk"
