#!/bin/bash
# Tests for scripts/config-get.sh — the shared config reader behind
# /orchestrate's threshold/backend/toggle reads (Task 13, D-33, REQ-K1.1).
#
# Properties verified (the defaults + local-override precedence model):
#   1. A key present only in the tracked defaults reads from the defaults.
#   2. A local override wins over the tracked default for the same key.
#   3. A key absent from both exits 3 (caller picks its own fallback).
#   4. Comments and surrounding quotes are stripped from the printed value.
#   5. The local file is consulted via PLANWRIGHT_LOCAL_CONFIG; an absent
#      local file degrades to the default (no error).
#   6. An invalid key (path/metachar) is rejected (exit 2) before any use.
#
# Runs standalone under /bin/bash (the bash 3.2 floor): ./tests/test-config-get.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
CG="$here/../scripts/config-get.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$CG" ] || fail "scripts/config-get.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

defaults="$tmp/defaults.yml"
cat >"$defaults" <<'EOF'
---
# planwright defaults fixture
commit_on_state_move: true
dispatch_backend: subagent
max_parallel_units: 3
stale_lock_threshold: 15m
EOF

local_cfg="$tmp/planwright.local.yml"

run() { # key -> stdout, with the fixtures wired via env
  PLANWRIGHT_CONFIG_DEFAULTS="$defaults" PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/bash "$CG" "$1"
}

# 1. Key present only in defaults.
: >"$local_cfg"
[ "$(run dispatch_backend)" = subagent ] \
  || fail "default-only key did not read from defaults"
echo "ok: default-only key reads from the tracked defaults"

# 2. Local override wins.
printf 'dispatch_backend: tmux\n' >"$local_cfg"
[ "$(run dispatch_backend)" = tmux ] \
  || fail "local override did not win over the default"
echo "ok: local override wins over the tracked default"

# 3. Absent key exits 3.
: >"$local_cfg"
if run no_such_option >/dev/null 2>&1; then
  fail "absent key did not exit non-zero"
fi
rc=0
run no_such_option >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "absent key exit was $rc, expected 3"
echo "ok: a key absent from both files exits 3"

# 4. Comments and quotes are stripped.
printf 'dispatch_backend: "print"  # forced for this repo\n' >"$local_cfg"
[ "$(run dispatch_backend)" = print ] \
  || fail "trailing comment / quotes not stripped"
echo "ok: comments and surrounding quotes are stripped"

# 5. An absent local file degrades to the default (no error).
PLANWRIGHT_CONFIG_DEFAULTS="$defaults" PLANWRIGHT_LOCAL_CONFIG="$tmp/nope.yml" \
  /bin/bash "$CG" max_parallel_units >/dev/null \
  || fail "absent local file did not degrade to the default"
[ "$(PLANWRIGHT_CONFIG_DEFAULTS="$defaults" PLANWRIGHT_LOCAL_CONFIG="$tmp/nope.yml" \
  /bin/bash "$CG" max_parallel_units)" = 3 ] \
  || fail "absent local file: wrong default value"
echo "ok: an absent local override file degrades to the default"

# 6. Invalid key rejected before use.
for bad in '../etc' 'a b' 'key;rm' 'Key' ''; do
  rc=0
  PLANWRIGHT_CONFIG_DEFAULTS="$defaults" PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/bash "$CG" "$bad" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "invalid key '$bad' not rejected (exit $rc)"
done
echo "ok: invalid keys are rejected with exit 2"

echo "PASS: config-get"
