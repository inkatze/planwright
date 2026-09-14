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

# run4 wires all four layers via env and pins PLANWRIGHT_LOCAL_CONFIG empty (not
# merely unset, so an ambient value in the runner's environment cannot leak in)
# so the machine-local file is derived through the Task 2 primitive (the real path).
run4() {
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
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
got=$(run4 dispatch_backend)
[ "$got" = local_v ] \
  || fail "four layers set: machine-local did not win (got '$got')"
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
[ "$rc" = 4 ] \
  || fail "malformed repo-tracked: exit $rc, expected 4 (documented hard-fail code)"
case $err in
  *repo-tracked*) ;;
  *) fail "malformed repo-tracked: stderr does not name the layer (got: '$err')" ;;
esac
echo "ok: malformed repo-tracked overlay hard-fails with exit 4 (no silent degrade)"

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

# E1.4 — a YAML document marker may carry a trailing comment (`--- # note`,
# `... # done`), which is well-formed YAML the flat reader tolerates the same as
# a comment on any other line. It must NOT be classified malformed (which for a
# repo-tracked overlay would spuriously hard-fail a whole team with exit 4).
reset_layers
printf 'dispatch_backend: core_v\n' >"$core_cfg"
printf -- '--- # config doc\ndispatch_backend: repo_v\n' >"$tracked_cfg"
rc=0
got=$(run4 dispatch_backend 2>/dev/null) || rc=$?
[ "$rc" = 0 ] \
  || fail "doc marker with trailing comment in repo-tracked: exit $rc, expected 0 (not malformed)"
[ "$got" = repo_v ] \
  || fail "doc marker with trailing comment: expected repo_v, got '$got' (spurious hard-fail?)"
echo "ok: a document marker with a trailing comment is not treated as malformed"

# E1.4 — a top-level YAML sequence item (`- key: value`, a list-of-maps) makes
# the document a sequence, not the flat mapping this reader requires; it must be
# malformed even though the line carries a colon (REQ-E1.4: a mapping, not a
# sequence). For a repo-tracked overlay that means the exit-4 hard-fail.
reset_layers
printf 'dispatch_backend: core_v\n' >"$core_cfg"
printf 'dispatch_backend: local_v\n' >"$mlocal_cfg"
printf -- '- key: value\n' >"$tracked_cfg"
rc=0
err=$(run4 dispatch_backend 2>&1 >/dev/null) || rc=$?
[ "$rc" = 4 ] \
  || fail "top-level list item in repo-tracked: exit $rc, expected 4 (sequence, not flat mapping)"
case $err in
  *repo-tracked*) ;;
  *) fail "top-level list item: stderr does not name the repo-tracked layer (got: '$err')" ;;
esac
echo "ok: a top-level YAML sequence item is treated as malformed (not a flat mapping)"

# E1.4 — but an INLINE (flow) list value stays well-formed (REQ-E1.4 explicitly:
# a list-valued option such as review_sequence is well-formed). The block form is
# what is malformed; the inline form is a normal flat key: value line.
reset_layers
printf 'dispatch_backend: core_v\n' >"$core_cfg"
printf 'review_sequence: [polish, panel]\ndispatch_backend: repo_v\n' >"$tracked_cfg"
rc=0
got=$(run4 dispatch_backend 2>/dev/null) || rc=$?
[ "$rc" = 0 ] \
  || fail "inline list value in repo-tracked: exit $rc, expected 0 (inline list is well-formed)"
[ "$got" = repo_v ] \
  || fail "inline list value: expected repo_v, got '$got' (spurious hard-fail on a flow list?)"
echo "ok: an inline (flow) list value is well-formed, not malformed"

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

# E1.4 — a path that EXISTS at the overlay location but is not a regular file
# (e.g. a directory, a botched mkdir, a merge artifact) is "present but not
# parseable as flat key: value YAML" — malformed for the kind, not absent. The
# by-layer policy applies: repo-tracked hard-fails (exit 4, the team-shared
# blast radius is never silently degraded), adopter and machine-local
# degrade+warn. The earlier `-f` gate routed these to "absent", silently
# bypassing the policy; the gate is now `-e`.
reset_layers
printf 'dispatch_backend: core_v\n' >"$core_cfg"
printf 'dispatch_backend: local_v\n' >"$mlocal_cfg"
mkdir "$tracked_cfg"
rc=0
err=$(run4 dispatch_backend 2>&1 >/dev/null) || rc=$?
rmdir "$tracked_cfg"
[ "$rc" = 4 ] \
  || fail "directory at repo-tracked path: exit $rc, expected 4 (hard-fail, not silent absent)"
case $err in
  *repo-tracked*) ;;
  *) fail "directory at repo-tracked path: stderr does not name the layer (got: '$err')" ;;
esac
echo "ok: a non-regular-file (directory) at the repo-tracked path hard-fails (exit 4)"

reset_layers
printf 'dispatch_backend: core_v\n' >"$core_cfg"
mkdir "$mlocal_cfg"
rc=0
err=$(run4 dispatch_backend 2>&1 >/dev/null) || rc=$?
out=$(run4 dispatch_backend 2>/dev/null)
rmdir "$mlocal_cfg"
[ "$rc" = 0 ] || fail "directory at machine-local path: exit $rc, expected 0 (degrade)"
[ "$out" = core_v ] || fail "directory at machine-local path: did not degrade to core"
case $err in
  *machine-local*malformed* | *malformed*machine-local*) ;;
  *) fail "directory at machine-local path: no degrade+warn (got: '$err')" ;;
esac
echo "ok: a non-regular-file (directory) at the machine-local path degrades+warns"

reset_layers
printf 'dispatch_backend: core_v\n' >"$core_cfg"
mkdir "$adopter_cfg"
rc=0
err=$(run4 dispatch_backend 2>&1 >/dev/null) || rc=$?
out=$(run4 dispatch_backend 2>/dev/null)
rmdir "$adopter_cfg"
[ "$rc" = 0 ] || fail "directory at adopter path: exit $rc, expected 0 (degrade)"
[ "$out" = core_v ] || fail "directory at adopter path: did not degrade to core"
case $err in
  *adopter*malformed* | *malformed*adopter*) ;;
  *) fail "directory at adopter path: no degrade+warn (got: '$err')" ;;
esac
echo "ok: a non-regular-file (directory) at the adopter path degrades+warns"

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

# F9/REQ-E1.2 — the reader must not swallow the Task 2 primitive's stderr. The
# primitive can emit a legitimate warning while still resolving exit 0 (here, a
# plugin manifest whose `name` is not a valid identifier degrades the adopter
# layer with a stderr warning). A blanket 2>/dev/null on the overlay_root helper
# would hide that warning (and would equally mask a missing/non-executable
# primitive as "every overlay absent"), defeating the reader's "never fails
# opaquely" contract. Drive writer-mode adopter resolution hermetically: no
# PLANWRIGHT_ADOPTER_OVERLAY / CLAUDE_PLUGIN_DATA, CLAUDE_DIR pointing at an
# invalid-manifest fixture, repo-side layers pinned absent so only the adopter
# layer drives stderr. The adopter layer must still degrade to core (exit 0).
reset_layers
printf 'dispatch_backend: core_v\n' >"$core_cfg"
wm_claude=$(mktemp -d)
mkdir -p "$wm_claude/planwright"
printf '{"name": "Bad Name!"}\n' >"$wm_claude/planwright/plugin.json"
run_wm() {
  env -u PLANWRIGHT_ADOPTER_OVERLAY -u CLAUDE_PLUGIN_DATA \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    CLAUDE_DIR="$wm_claude" \
    /bin/bash "$CG" "$@"
}
rc=0
err=$(run_wm dispatch_backend 2>&1 >/dev/null) || rc=$?
out=$(run_wm dispatch_backend 2>/dev/null)
rm -rf "$wm_claude"
[ "$rc" = 0 ] || fail "primitive-warning passthrough: exit $rc, expected 0 (adopter degrades)"
[ "$out" = core_v ] \
  || fail "primitive-warning passthrough: did not degrade to core (got '$out')"
case $err in
  *"not a valid identifier"*) ;;
  *) fail "primitive-warning passthrough: reader swallowed the primitive's stderr (got: '$err')" ;;
esac
echo "ok: the reader surfaces the Task 2 primitive's stderr (no blanket 2>/dev/null)"

# REQ-K1.6 — the Task 2 overlay resolver is required infrastructure. A missing
# or non-executable resolver (a broken/partial install) is reported ONCE and
# degrades to core defaults, not once per overlay layer (three overlay_root
# calls would otherwise each emit the same shell error). Mirrors the warn-once
# `-x` guard in resolve-rule-doc.sh. Run a copy of the reader from a scripts dir
# whose resolver is present-but-non-executable so the `-x` guard fires.
bin=$(mktemp -d)
mkdir -p "$bin/scripts"
cp "$CG" "$bin/scripts/config-get.sh"
printf '#!/bin/sh\nprintf "%%s\\n" stub\n' >"$bin/scripts/resolve-overlay-root.sh"
chmod 644 "$bin/scripts/resolve-overlay-root.sh"
reset_layers
printf 'dispatch_backend: core_v\n' >"$core_cfg"
run_broken() {
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$bin/scripts/config-get.sh" "$@"
}
rc=0
err=$(run_broken dispatch_backend 2>&1 >/dev/null) || rc=$?
out=$(run_broken dispatch_backend 2>/dev/null)
nwarn=$(printf '%s\n' "$err" | grep -c 'overlay resolver' || true)
[ "$rc" = 0 ] || fail "broken resolver: exit $rc, expected 0 (degrade to core)"
[ "$out" = core_v ] || fail "broken resolver: did not degrade to core (got '$out')"
[ "$nwarn" = 1 ] \
  || fail "broken resolver: expected exactly 1 'overlay resolver' warning, got $nwarn (per-call noise?)"
echo "ok: a missing/non-executable overlay resolver warns once and degrades to core"

# REQ-K1.6 — the warn-once message claims only the *resolver-derived* layers are
# unavailable; the legacy PLANWRIGHT_LOCAL_CONFIG override is an explicit path
# that never goes through the resolver, so it must still be honored when the
# resolver is missing. (Guards against a future "fix" that disables the override
# to make the older, broader wording true.)
legacy_local="$ov/legacy-local.yml"
printf 'dispatch_backend: legacy_v\n' >"$legacy_local"
run_broken_legacy() {
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="$legacy_local" \
    /bin/bash "$bin/scripts/config-get.sh" "$@"
}
got=$(run_broken_legacy dispatch_backend 2>/dev/null)
rm -f "$legacy_local"
rm -rf "$bin"
[ "$got" = legacy_v ] \
  || fail "broken resolver + PLANWRIGHT_LOCAL_CONFIG: legacy override not honored (got '$got', expected legacy_v)"
echo "ok: a missing resolver still honors an explicit PLANWRIGHT_LOCAL_CONFIG override"

echo "PASS: config-get"
