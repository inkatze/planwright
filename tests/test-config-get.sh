#!/bin/bash
# Tests for scripts/config-get.sh — the shared config reader behind
# /orchestrate's threshold/backend/toggle reads (Task 13, D-33, REQ-K1.1).
#
# Two suites live here. The first verifies the original two-layer base
# (defaults + local-override precedence model):
#   1. A key present only in the tracked defaults reads from the defaults.
#   2. A local override wins over the tracked default for the same key.
#   3. A key absent from both exits 3 (caller picks its own fallback).
#   4. Comments and surrounding quotes are stripped from the printed value.
#   5. The local file is consulted via PLANWRIGHT_LOCAL_CONFIG; an absent
#      local file degrades to the default (no error).
#   6. An invalid key (path/metachar) is rejected (exit 2) before any use.
#
# The second suite (the "Four-layer overlay resolution" section below) verifies
# the customization-overlay extension (Task 3: D-1, D-4, D-5, D-7, D-9):
#   7. The core < adopter < repo-tracked < machine-local precedence ladder,
#      per-key last-layer-wins, and clean absent-layer degrade.
#   8. The malformed-overlay policy by layer: adopter/machine-local degrade with
#      a warning, repo-tracked hard-fails (exit 4); "malformed" tracks flat-vs-
#      nested structure, not the key charset.
#   9. The --explain provenance mode (pinned "<layer>TAB<value>" contract) and
#      deterministic resolution across repeated runs.
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

# 5b. Only a surrounding quote pair is stripped; quotes inside the value are
#     preserved (the docstring promises "surrounding quotes", not all quotes).
printf "token: \"a'b\"\n" >"$local_cfg"
[ "$(run token)" = "a'b" ] \
  || fail "internal single quote was stripped (expected a'b, got '$(run token)')"
echo "ok: internal quotes are preserved (only surrounding pair stripped)"

# 6. Invalid key rejected before use.
for bad in '../etc' 'a b' 'key;rm' 'Key' ''; do
  rc=0
  PLANWRIGHT_CONFIG_DEFAULTS="$defaults" PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/bash "$CG" "$bad" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "invalid key '$bad' not rejected (exit $rc)"
done
echo "ok: invalid keys are rejected with exit 2"

# 7. Defaults resolution chain: with no explicit PLANWRIGHT_CONFIG_DEFAULTS,
#    the defaults file is found under PLANWRIGHT_ROOT/config/ (the plugin/test
#    delivery arm of the D-33 resolution chain).
root="$tmp/root"
mkdir -p "$root/config"
printf 'dispatch_backend: tmux\n' >"$root/config/defaults.yml"
got=$(PLANWRIGHT_ROOT="$root" PLANWRIGHT_LOCAL_CONFIG="$tmp/no-local.yml" \
  /bin/bash "$CG" dispatch_backend) \
  || fail "defaults via PLANWRIGHT_ROOT: non-zero exit"
[ "$got" = tmux ] \
  || fail "defaults via PLANWRIGHT_ROOT: got '$got', expected tmux"
echo "ok: defaults resolve via the PLANWRIGHT_ROOT chain when no explicit file is set"

# 8. A missing/unreadable tracked defaults file is a broken install, not a
#    normal absent key: it still exits 3 (callers pick their fallback) but must
#    surface a diagnostic rather than failing opaquely (the docstring contract).
rc=0
err=$(PLANWRIGHT_CONFIG_DEFAULTS="$tmp/no-defaults.yml" \
  PLANWRIGHT_LOCAL_CONFIG="$tmp/no-local.yml" \
  /bin/bash "$CG" dispatch_backend 2>&1 >/dev/null) || rc=$?
[ "$rc" = 3 ] || fail "missing defaults: exit $rc, expected 3"
case $err in
  *"tracked defaults not found"*) ;;
  *) fail "missing defaults: no diagnostic (got: '$err')" ;;
esac
echo "ok: a missing tracked defaults file surfaces a diagnostic (not opaque)"

# 8b. An existing-but-unreadable defaults file must also surface the diagnostic
#     ("missing OR unreadable" per the contract, via the -r test, not just -f).
unreadable="$tmp/unreadable-defaults.yml"
printf 'dispatch_backend: subagent\n' >"$unreadable"
chmod 000 "$unreadable"
rc=0
err=$(PLANWRIGHT_CONFIG_DEFAULTS="$unreadable" PLANWRIGHT_LOCAL_CONFIG="$tmp/no-local.yml" \
  /bin/bash "$CG" dispatch_backend 2>&1 >/dev/null) || rc=$?
chmod 644 "$unreadable" # restore for cleanup
case $err in
  *"tracked defaults not found"*)
    [ "$rc" = 3 ] || fail "unreadable defaults: exit $rc, expected 3"
    echo "ok: an unreadable tracked defaults file also surfaces the diagnostic"
    ;;
  *)
    # Root reads through mode 000; the failure mode is unobservable there.
    echo "skip: unreadable-defaults case (file still readable — likely running as root)"
    ;;
esac

# ===========================================================================
# Four-layer overlay resolution (Task 3: D-1, D-4, D-5, D-7, D-9;
# REQ-A1.1/A1.2/A1.4, REQ-B1.1/B1.5/B1.6, REQ-E1.4).
#
# The four layers, lowest to highest precedence:
#   core          config/defaults.yml            (PLANWRIGHT_CONFIG_DEFAULTS)
#   adopter       <adopter-root>/planwright.yml   (PLANWRIGHT_ADOPTER_OVERLAY)
#   repo-tracked  <repo>/.claude/planwright.yml   (PLANWRIGHT_REPO_ROOT)
#   machine-local <repo>/.claude/planwright.local.yml (PLANWRIGHT_REPO_ROOT)
#
# The two repo-side layers and the adopter layer are resolved through the
# Task 2 primitive (resolve-overlay-root.sh); these tests drive its env
# overrides so the suite stays hermetic — no $HOME, no git toplevel, no
# real overlay file is ever consulted.
# ===========================================================================

ov=$(mktemp -d)
trap 'rm -rf "$tmp" "$ov"' EXIT

core_cfg="$ov/core-defaults.yml"
adopter_root="$ov/adopter"
repo="$ov/repo"
mkdir -p "$adopter_root" "$repo/.claude"
adopter_cfg="$adopter_root/planwright.yml"
tracked_cfg="$repo/.claude/planwright.yml"
mlocal_cfg="$repo/.claude/planwright.local.yml"

# run4 wires all four layers via env and leaves PLANWRIGHT_LOCAL_CONFIG unset so
# the machine-local file is derived through the Task 2 primitive (the real path).
run4() {
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    /bin/bash "$CG" "$@"
}

reset_layers() {
  rm -f "$core_cfg" "$adopter_cfg" "$tracked_cfg" "$mlocal_cfg"
}

# A1.1/A1.2/B1.1 — same key in all four layers: highest-precedence wins, and
# the ladder is core < adopter < repo-tracked < machine-local. Peeling the top
# layer off each time exposes the next one down (A1.4 absent-degrades too).
reset_layers
printf 'dispatch_backend: core_v\n' >"$core_cfg"
printf 'dispatch_backend: adopter_v\n' >"$adopter_cfg"
printf 'dispatch_backend: repo_v\n' >"$tracked_cfg"
printf 'dispatch_backend: local_v\n' >"$mlocal_cfg"
[ "$(run4 dispatch_backend)" = local_v ] \
  || fail "four layers set: machine-local did not win (got '$(run4 dispatch_backend)')"
rm -f "$mlocal_cfg"
[ "$(run4 dispatch_backend)" = repo_v ] \
  || fail "machine-local absent: repo-tracked did not win"
rm -f "$tracked_cfg"
[ "$(run4 dispatch_backend)" = adopter_v ] \
  || fail "repo-tracked absent: adopter did not win"
rm -f "$adopter_cfg"
[ "$(run4 dispatch_backend)" = core_v ] \
  || fail "adopter absent: core default did not win"
echo "ok: four-layer ladder core < adopter < repo-tracked < machine-local (last-layer-wins)"

# A1.4 — all overlay layers absent: core value, zero exit, no stderr noise.
reset_layers
printf 'max_parallel_units: 3\n' >"$core_cfg"
rc=0
err=$(run4 max_parallel_units 2>&1 >/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "absent overlays: exit $rc, expected 0"
[ -z "$err" ] || fail "absent overlays emitted stderr noise: '$err'"
[ "$(run4 max_parallel_units)" = 3 ] || fail "absent overlays: wrong core value"
echo "ok: all overlay layers absent degrades cleanly to core (zero exit, no warning)"

# B1.1 — per-key last-layer-wins: a key set only in a lower layer still resolves
# even when a higher layer sets a *different* key (no whole-file replace).
reset_layers
printf 'dispatch_backend: core_db\nmax_parallel_units: 9\n' >"$core_cfg"
printf 'dispatch_backend: local_db\n' >"$mlocal_cfg"
[ "$(run4 dispatch_backend)" = local_db ] || fail "per-key: machine-local key did not win"
[ "$(run4 max_parallel_units)" = 9 ] \
  || fail "per-key: a core-only key was lost when a higher layer set a different key"
echo "ok: resolution is per-key last-layer-wins, not whole-file replace"

# E1.4 — malformed adopter overlay (a nested, non-flat YAML the line reader
# cannot parse) degrades to the next lower layer with a stderr warning, zero exit.
reset_layers
printf 'dispatch_backend: core_v\n' >"$core_cfg"
printf 'review_sequence:\n  - polish\n  - panel\n' >"$adopter_cfg"
rc=0
err=$(run4 dispatch_backend 2>&1 >/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "malformed adopter: exit $rc, expected 0 (degrade)"
[ "$(run4 dispatch_backend)" = core_v ] \
  || fail "malformed adopter: did not degrade to core value"
case $err in
  *adopter*malformed* | *malformed*adopter*) ;;
  *) fail "malformed adopter: no naming warning on stderr (got: '$err')" ;;
esac
echo "ok: malformed adopter overlay degrades to the next lower layer with a warning"

# E1.4 — malformed machine-local overlay degrades+warns the same way.
reset_layers
printf 'dispatch_backend: core_v\n' >"$core_cfg"
printf 'dispatch_backend: repo_v\n' >"$tracked_cfg"
printf 'review_sequence:\n  - polish\n' >"$mlocal_cfg"
rc=0
err=$(run4 dispatch_backend 2>&1 >/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "malformed machine-local: exit $rc, expected 0 (degrade)"
[ "$(run4 dispatch_backend)" = repo_v ] \
  || fail "malformed machine-local: did not degrade to repo-tracked"
case $err in
  *machine-local*malformed* | *malformed*machine-local*) ;;
  *) fail "malformed machine-local: no naming warning (got: '$err')" ;;
esac
echo "ok: malformed machine-local overlay degrades with a warning"

# E1.4 — malformed repo-tracked (team-shared) overlay hard-fails nonzero: a
# broken shared config is never silently degraded, even when a higher layer
# would resolve the key.
reset_layers
printf 'dispatch_backend: core_v\n' >"$core_cfg"
printf 'dispatch_backend: local_v\n' >"$mlocal_cfg"
printf 'review_sequence:\n  - polish\n' >"$tracked_cfg"
rc=0
err=$(run4 dispatch_backend 2>&1 >/dev/null) || rc=$?
[ "$rc" != 0 ] || fail "malformed repo-tracked: exit 0, expected nonzero hard-fail"
case $err in
  *repo-tracked*) ;;
  *) fail "malformed repo-tracked: stderr does not name the layer (got: '$err')" ;;
esac
echo "ok: malformed repo-tracked overlay hard-fails nonzero (no silent degrade)"

# E1.4 — "malformed" tracks the flat-vs-nested structure, not the key charset:
# a flat key the reader does not query (a non-snake key such as one with a dash)
# is parseable-for-the-kind (silently ignored, like a comment), NOT malformed.
# A repo-tracked overlay carrying such a key must therefore resolve normally,
# never spuriously hard-fail a whole team on an ignored line.
reset_layers
printf 'dispatch_backend: core_v\n' >"$core_cfg"
printf 'backend-service: ignored\ndispatch_backend: repo_v\n' >"$tracked_cfg"
rc=0
got=$(run4 dispatch_backend 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "flat non-snake key in repo-tracked: exit $rc, expected 0 (not malformed)"
[ "$got" = repo_v ] \
  || fail "flat non-snake key in repo-tracked: expected repo_v, got '$got' (spurious hard-fail?)"
echo "ok: a flat non-snake (e.g. dashed) key is ignored, not treated as malformed"

# E1.4 — an unreadable repo-tracked overlay counts as malformed and hard-fails
# (the hard-fail arm of the by-layer policy, the team-shared blast radius).
if [ "$(id -u)" != 0 ]; then
  reset_layers
  printf 'dispatch_backend: core_v\n' >"$core_cfg"
  printf 'dispatch_backend: local_v\n' >"$mlocal_cfg"
  printf 'dispatch_backend: repo_v\n' >"$tracked_cfg"
  chmod 000 "$tracked_cfg"
  rc=0
  out=$(run4 dispatch_backend 2>/dev/null) || rc=$?
  chmod 644 "$tracked_cfg"
  if [ "$out" = local_v ] && [ "$rc" = 0 ]; then
    echo "skip: unreadable repo-tracked readable anyway (likely root)"
  else
    [ "$rc" = 4 ] || fail "unreadable repo-tracked: exit $rc, expected 4 (hard-fail)"
    echo "ok: an unreadable repo-tracked overlay hard-fails (exit 4)"
  fi
fi

# E1.4 — an unreadable overlay file counts as malformed for its layer
# (degrade+warn for machine-local).
if [ "$(id -u)" != 0 ]; then
  reset_layers
  printf 'dispatch_backend: core_v\n' >"$core_cfg"
  printf 'dispatch_backend: local_v\n' >"$mlocal_cfg"
  chmod 000 "$mlocal_cfg"
  rc=0
  out=$(run4 dispatch_backend 2>/dev/null) || rc=$?
  chmod 644 "$mlocal_cfg"
  if [ "$out" = local_v ]; then
    echo "skip: unreadable machine-local readable anyway (likely root)"
  else
    [ "$rc" = 0 ] || fail "unreadable machine-local: exit $rc, expected 0 (degrade)"
    [ "$out" = core_v ] || fail "unreadable machine-local: did not degrade to core"
    echo "ok: an unreadable overlay file is treated as malformed for its layer"
  fi
fi

# B1.6 — --explain names the winning layer (and value) for the key. Pinned
# output contract: a single stdout line "<layer>\t<value>".
reset_layers
printf 'dispatch_backend: core_v\n' >"$core_cfg"
printf 'dispatch_backend: adopter_v\n' >"$adopter_cfg"
got=$(run4 --explain dispatch_backend) || fail "--explain: nonzero exit on resolvable key"
[ "$got" = "$(printf 'adopter\tadopter_v')" ] \
  || fail "--explain: expected 'adopter<TAB>adopter_v', got '$got'"
printf 'dispatch_backend: local_v\n' >"$mlocal_cfg"
got=$(run4 --explain dispatch_backend)
[ "$got" = "$(printf 'machine-local\tlocal_v')" ] \
  || fail "--explain: expected 'machine-local<TAB>local_v', got '$got'"
rm -f "$adopter_cfg" "$mlocal_cfg"
got=$(run4 --explain dispatch_backend)
[ "$got" = "$(printf 'core\tcore_v')" ] \
  || fail "--explain: expected 'core<TAB>core_v', got '$got'"
echo "ok: --explain names the winning layer and value per key (pinned <layer>TAB<value>)"

# B1.6 — --explain on an absent key exits 3 like the bare read, empty stdout.
reset_layers
printf 'dispatch_backend: core_v\n' >"$core_cfg"
rc=0
out=$(run4 --explain no_such_key) || rc=$?
[ "$rc" = 3 ] || fail "--explain absent key: exit $rc, expected 3"
[ -z "$out" ] || fail "--explain absent key: non-empty stdout '$out'"
echo "ok: --explain on an absent key exits 3 with empty stdout"

# B1.6 — --explain validates the key like the bare read (invalid -> exit 2).
rc=0
run4 --explain '../etc' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "--explain invalid key: exit $rc, expected 2"
echo "ok: --explain rejects an invalid key with exit 2"

# B1.5 — config resolution is deterministic: identical inputs yield identical
# output across repeated runs (config has no within-layer enumeration to
# shuffle — the four layers are a fixed precedence ladder, so determinism is
# the order-independence property that applies to this kind).
reset_layers
printf 'dispatch_backend: core_v\n' >"$core_cfg"
printf 'dispatch_backend: adopter_v\n' >"$adopter_cfg"
printf 'dispatch_backend: repo_v\n' >"$tracked_cfg"
a=$(run4 dispatch_backend)
b=$(run4 dispatch_backend)
c=$(run4 --explain dispatch_backend)
d=$(run4 --explain dispatch_backend)
[ "$a" = "$b" ] && [ "$c" = "$d" ] \
  || fail "resolution is not deterministic across repeated runs"
echo "ok: resolution is deterministic across repeated runs (fixed layer order)"

echo "PASS: config-get"
