#!/bin/bash
# Tests for scripts/fleet-resource-select.sh — the rule-based, task-type-keyed
# model/effort/command selection table (fleet-autonomy Task 7; D-11, REQ-E1.1,
# REQ-E1.2).
#
# Per-task selection of model, reasoning effort, and slash command is a
# DETERMINISTIC, task-type-keyed rule table — never a confidence-calibrated
# cascade and never an LLM call (D-11, the D-18 no-LLM-daemon-mechanics
# floor). The model column is overlay-tunable per task type through the
# shared knob resolver (D-22/REQ-G1.5); effort and command are fixed table
# cells. The selectable command set must stay disjoint from
# `resolve-review-sequence.sh`'s nestable-review-skill set, so the two
# mechanisms can never both claim the same skill (REQ-E1.2).
#
# What is covered:
#   - `select <type>` resolves one model/effort/command row for every shipped
#     task type, deterministically (same input, same output across repeated
#     runs — the REQ-E1.1 fixture);
#   - no outbound LLM/API call occurs during resolution: stub `claude`/`curl`/
#     `wget`/`gh` clients on PATH assert zero invocations (REQ-E1.1's stubbed
#     client);
#   - the selectable command set and the nestable-review-skill set are
#     disjoint, and the nestable predicate is proven non-vacuous against the
#     shipped `polish` skill (REQ-E1.2's cross-check);
#   - the model column resolves through the overlay layers (machine-local
#     override wins) with the customization-overlay REQ-E1.4 by-layer
#     malformed policy (repo-tracked
#     malformed hard-fails exit 4; adopter malformed degrades to core + warn);
#   - an unknown or hostile task type is refused (exit 2), never defaulted;
#   - output is one TSV row `<model>TAB<effort>TAB<command>`.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-resource-select.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FRS="$here/../scripts/fleet-resource-select.sh"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FRS" ] || fail "scripts/fleet-resource-select.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Isolated overlay layers so the host machine's real config never leaks in.
core_cfg="$tmp/core-defaults.yml"
adopter_root="$tmp/adopter"
repo="$tmp/repo"
mkdir -p "$adopter_root" "$repo/.claude"
adopter_cfg="$adopter_root/planwright.yml"
tracked_cfg="$repo/.claude/planwright.yml"
mlocal_cfg="$repo/.claude/planwright.local.yml"

# The shipped core defaults for the model knobs (kept in lockstep with
# config/defaults.yml — the repo-drift check below asserts the real file
# carries the same keys).
cat >"$core_cfg" <<'EOF'
fleet_model_execution: opus
fleet_model_bookkeeping: sonnet
fleet_model_drain: sonnet
EOF

# Stub outbound clients: any invocation is an LLM/API call in the resolution
# path, which D-11/REQ-E1.1 forbid. Each stub records its invocation.
stubbin="$tmp/stubbin"
mkdir -p "$stubbin"
for c in claude curl wget gh; do
  cat >"$stubbin/$c" <<EOF
#!/bin/sh
echo "$c" >>"$tmp/invocations"
exit 0
EOF
  chmod +x "$stubbin/$c"
done

run() {
  PATH="$stubbin:$PATH" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$FRS" "$@"
}

reset_layers() {
  rm -f "$adopter_cfg" "$tracked_cfg" "$mlocal_cfg" "$tmp/invocations"
}

# 1. Every shipped task type resolves one well-formed TSV row, and the shipped
#    defaults land where the table says (REQ-E1.1).
reset_layers
out=$(run select execution) || fail "select execution exited nonzero"
[ "$out" = "opus${TAB}high${TAB}execute-task" ] \
  || fail "select execution: expected 'opus<TAB>high<TAB>execute-task', got '$out'"
out=$(run select bookkeeping) || fail "select bookkeeping exited nonzero"
[ "$out" = "sonnet${TAB}medium${TAB}orchestrate" ] \
  || fail "select bookkeeping: expected 'sonnet<TAB>medium<TAB>orchestrate', got '$out'"
out=$(run select drain) || fail "select drain exited nonzero"
[ "$out" = "sonnet${TAB}low${TAB}drain" ] \
  || fail "select drain: expected 'sonnet<TAB>low<TAB>drain', got '$out'"
echo "ok: every shipped task type resolves its table row"

# 2. Determinism: repeated runs produce byte-identical output for each type
#    (REQ-E1.1 "same input, same output across repeated runs").
for t in execution bookkeeping drain; do
  first=$(run select "$t") || fail "determinism: select $t exited nonzero"
  for i in 2 3; do
    again=$(run select "$t") || fail "determinism: select $t run $i exited nonzero"
    [ "$again" = "$first" ] \
      || fail "determinism: select $t run $i gave '$again', expected '$first'"
  done
done
echo "ok: resolution is deterministic across repeated runs"

# 3. No LLM/API call in the resolution path: the stubbed clients were never
#    invoked by any of the runs above (REQ-E1.1's stubbed-client assertion).
[ ! -f "$tmp/invocations" ] \
  || fail "an outbound client was invoked during resolution: $(cat "$tmp/invocations" | sort -u | tr '\n' ' ')"
echo "ok: zero outbound client invocations during resolution"

# 4. `list` prints the full table, one row per task type, so callers and the
#    disjointness check below can enumerate the selectable command set.
reset_layers
listing=$(run list) || fail "list exited nonzero"
[ "$(printf '%s\n' "$listing" | wc -l | tr -d ' ')" = 3 ] \
  || fail "list: expected 3 rows, got: $listing"
printf '%s\n' "$listing" | grep -q "^execution${TAB}opus${TAB}high${TAB}execute-task$" \
  || fail "list: missing/incorrect execution row in: $listing"
printf '%s\n' "$listing" | grep -q "^bookkeeping${TAB}sonnet${TAB}medium${TAB}orchestrate$" \
  || fail "list: missing/incorrect bookkeeping row in: $listing"
printf '%s\n' "$listing" | grep -q "^drain${TAB}sonnet${TAB}low${TAB}drain$" \
  || fail "list: missing/incorrect drain row in: $listing"
echo "ok: list enumerates the full table"

# 5. REQ-E1.2 cross-check: the selectable command set is disjoint from
#    resolve-review-sequence.sh's nestable-review-skill set (the predicate:
#    skills/<name>/SKILL.md exists and its argument-hint declares --nested).
skills_root="$here/../skills"
[ -d "$skills_root" ] || fail "skills root not found at $skills_root"
# The predicate must not be vacuous: the shipped `polish` skill IS nestable.
grep -Eq '^argument-hint:.*--nested' "$skills_root/polish/SKILL.md" \
  || fail "cross-check sanity: the shipped polish skill no longer declares --nested (predicate drifted?)"
commands=$(printf '%s\n' "$listing" | cut -f4 | sort -u)
for c in $commands; do
  skill_md="$skills_root/$c/SKILL.md"
  if [ -f "$skill_md" ] && grep -Eq '^argument-hint:.*--nested' "$skill_md"; then
    fail "REQ-E1.2 violation: selectable command '$c' is a nestable review skill (review_sequence's scope)"
  fi
done
echo "ok: the selectable command set is disjoint from the nestable-review-skill set"

# 6. The model column is overlay-tunable per task type: a machine-local
#    override wins (D-22/REQ-G1.5), and only the targeted type changes.
reset_layers
printf 'fleet_model_execution: fable\n' >"$mlocal_cfg"
out=$(run select execution 2>/dev/null) || fail "overlay: select execution exited nonzero"
[ "$out" = "fable${TAB}high${TAB}execute-task" ] \
  || fail "overlay: expected the machine-local 'fable' to win, got '$out'"
out=$(run select bookkeeping 2>/dev/null) || fail "overlay: select bookkeeping exited nonzero"
[ "$out" = "sonnet${TAB}medium${TAB}orchestrate" ] \
  || fail "overlay: bookkeeping must be unaffected by the execution override, got '$out'"
echo "ok: machine-local model override wins for the targeted type only"

# 7. By-layer malformed policy (customization-overlay REQ-E1.4 shape, via
#    the shared resolver):
#    repo-tracked malformed hard-fails exit 4; adopter malformed degrades to
#    the core default with a warning.
reset_layers
printf 'fleet_model_execution: gpt-5\n' >"$tracked_cfg"
rc=0
run select execution >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "malformed repo-tracked model: exit $rc, expected 4 (hard-fail)"
reset_layers
printf 'fleet_model_execution: gpt-5\n' >"$adopter_cfg"
rc=0
out=$(run select execution 2>"$tmp/warn") || rc=$?
[ "$rc" = 0 ] || fail "malformed adopter model: exit $rc, expected 0 (degrade)"
[ "$out" = "opus${TAB}high${TAB}execute-task" ] \
  || fail "malformed adopter model: expected degrade to the core 'opus', got '$out'"
grep -qi "malformed" "$tmp/warn" \
  || fail "malformed adopter model: expected a degrade warning on stderr"
echo "ok: by-layer malformed policy holds for the model knobs"

# 8. An unknown task type is refused (exit 2), never silently defaulted, and
#    a hostile token cannot drive the terminal (diagnostic is sanitized).
reset_layers
rc=0
run select no-such-type >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "unknown task type: exit $rc, expected 2"
rc=0
err=$(run select "$(printf 'evil\033[2Jtype')" 2>&1 >/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "hostile task type: exit $rc, expected 2"
case $err in
  *$(printf '\033')*) fail "hostile task type: diagnostic carries a raw escape byte" ;;
esac
echo "ok: unknown/hostile task types are refused with sanitized diagnostics"

# 9. Usage errors: no subcommand / unknown subcommand / missing type.
for args in "" "bogus" "select"; do
  rc=0
  # shellcheck disable=SC2086
  run $args >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "usage error for '$args': exit $rc, expected 2"
done
echo "ok: usage errors exit 2"

# 10. Repo-drift check: the real config/defaults.yml ships the three model
#     knobs with the table's defaults, so the isolated core fixture above
#     cannot silently diverge from the shipped file.
real_defaults="$here/../config/defaults.yml"
for kv in "fleet_model_execution: opus" "fleet_model_bookkeeping: sonnet" "fleet_model_drain: sonnet"; do
  grep -q "^$kv" "$real_defaults" \
    || fail "config/defaults.yml does not ship '$kv' (table and shipped defaults drifted)"
done
echo "ok: shipped defaults match the table"

# 11. `list` is all-or-nothing: a later-row resolver hard-fail must not
#     leave partial output on stdout (the fail-before-emitting posture
#     fleet-audit's query path holds).
reset_layers
printf 'fleet_model_bookkeeping: gpt-5\n' >"$tracked_cfg"
rc=0
out=$(run list 2>/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "list with a malformed repo-tracked bookkeeping model: exit $rc, expected 4"
[ -z "$out" ] || fail "list must emit nothing on a hard-fail, got partial output: $out"
echo "ok: list emits nothing on a resolver hard-fail"

# 12. Broken install (missing shared resolver) is exit 5, never a proceed
#     with a garbage model: run a copy of the script from a tree without
#     resolve-config-knob.sh.
broken="$tmp/broken-tree"
mkdir -p "$broken"
cp "$FRS" "$broken/fleet-resource-select.sh"
cp "$here/../scripts/echo-safety.sh" "$broken/echo-safety.sh"
rc=0
PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" /bin/bash "$broken/fleet-resource-select.sh" select execution >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "missing resolver: exit $rc, expected 5 (broken install)"
echo "ok: a missing shared resolver is broken-install exit 5"

# 13. Positive control for the zero-invocation stub: the stub IS reachable
#     on the prefixed PATH, so test 3's zero-invocation assertion is not
#     vacuous.
rm -f "$tmp/invocations"
PATH="$stubbin:$PATH" claude >/dev/null 2>&1 || true
[ -f "$tmp/invocations" ] || fail "stub positive control failed (stub not reachable on PATH)"
rm -f "$tmp/invocations"
echo "ok: the no-LLM stub is verified reachable"

# 14. Remaining usage arms are refused (exit 2): extra args on select/list.
for args in "select execution extra" "list extra"; do
  rc=0
  # shellcheck disable=SC2086
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" /bin/bash "$FRS" $args >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "usage error for '$args': exit $rc, expected 2"
done
echo "ok: extra-arg usage errors exit 2"

echo "ALL PASS: fleet-resource-select"
