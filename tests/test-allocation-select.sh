#!/bin/bash
# Tests for scripts/allocation-select.sh — the surface-agnostic selection
# resolver (model-allocation Task 1; D-5, D-13, REQ-A1.1, REQ-A1.2, REQ-A1.3,
# REQ-A1.4, REQ-E1.1, REQ-E1.2).
#
# The resolver generalizes fleet-resource-select.sh's task-type-keyed table
# into one surface-agnostic table every launch point can call, covering all
# three columns (model, effort, command). Selection stays DETERMINISTIC table
# lookup plus config reads: no LLM call in the resolution path (REQ-A1.1).
#
# What is covered:
#   - golden-baseline equivalence (REQ-A1.2): with an empty config the three
#     fleet task types resolve to the CAPTURED fixture
#     (tests/fixtures/allocation-golden-baseline.tsv), never to the
#     implementation's own output, through both the generalized resolver and
#     the legacy fleet-resource-select.sh entry point;
#   - fallback precedence (REQ-A1.3): a set `allocation_*` knob wins over its
#     `fleet_*` counterpart, an unset one falls back to the legacy knob, and
#     with neither set the shipped default applies;
#   - the `inherit` sentinel (D-13): the shipped default at the three surfaces
#     that perform no selection today, resolving as inherit and refused at the
#     fleet task-type keys whose downstream contract has no ambient value;
#   - enum validation across all three columns and the by-layer malformed
#     policy (REQ-A1.4), including the command enum's closed set carrying
#     review-sequence disjointness by construction;
#   - determinism, zero outbound client invocations, all-or-nothing `list`,
#     broken-install exit 5, sanitized refusals, and repo-drift against the
#     shipped config/defaults.yml.
#
# The numeric-knob grammar (REQ-A1.4's `nonnegint`) lives in the shared knob
# resolver and is covered by tests/test-resolve-config-knob.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-allocation-select.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
AS="$here/../scripts/allocation-select.sh"
FRS="$here/../scripts/fleet-resource-select.sh"
GOLDEN="$here/fixtures/allocation-golden-baseline.tsv"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$AS" ] || fail "scripts/allocation-select.sh missing or not executable"
[ -x "$FRS" ] || fail "scripts/fleet-resource-select.sh missing or not executable"
[ -f "$GOLDEN" ] || fail "the golden-baseline fixture is missing at $GOLDEN"

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

# The shipped core defaults for the whole knob family, kept in lockstep with
# config/defaults.yml (test 11 asserts the real file carries the same rows).
# The nine fleet-keyed general knobs ship the `unset` sentinel, which is what
# arms the `fleet_*` fallback; the six non-fleet ones ship `inherit`.
cat >"$core_cfg" <<'EOF'
fleet_model_execution: opus
fleet_model_bookkeeping: sonnet
fleet_model_drain: sonnet
fleet_effort_execution: high
fleet_effort_bookkeeping: medium
fleet_effort_drain: low
fleet_command_execution: execute-task
fleet_command_bookkeeping: orchestrate
fleet_command_drain: drain
allocation_model_execution: unset
allocation_model_bookkeeping: unset
allocation_model_drain: unset
allocation_effort_execution: unset
allocation_effort_bookkeeping: unset
allocation_effort_drain: unset
allocation_command_execution: unset
allocation_command_bookkeeping: unset
allocation_command_drain: unset
allocation_model_orchestrate_dispatch: inherit
allocation_effort_orchestrate_dispatch: inherit
allocation_model_execute_step: inherit
allocation_effort_execute_step: inherit
allocation_model_offload: inherit
allocation_effort_offload: inherit
EOF

# Stub outbound clients: any invocation is an LLM/API call in the resolution
# path, which REQ-A1.1 forbids. Each stub records its invocation.
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
    /bin/bash "$AS" "$@"
}

run_legacy() {
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

# The captured baseline, comments and blank lines stripped. Read once so every
# equivalence assertion below compares against the fixture, never against a
# freshly-computed value (REQ-A1.2's "never against the implementation's own
# output").
golden=$(grep -v '^#' "$GOLDEN" | grep -v '^[[:space:]]*$')
[ "$(printf '%s\n' "$golden" | wc -l | tr -d ' ')" = 3 ] \
  || fail "the golden fixture should carry exactly 3 task-type rows, got: $golden"

golden_row() {
  printf '%s\n' "$golden" | awk -F'\t' -v k="$1" '$1 == k { print $2 "\t" $3 "\t" $4 }'
}

# 1. Golden-baseline equivalence (REQ-A1.2): with an empty config, every
#    existing task type resolves to the captured fixture row exactly.
reset_layers
for t in execution bookkeeping drain; do
  want=$(golden_row "$t")
  [ -n "$want" ] || fail "golden fixture has no row for task type '$t'"
  got=$(run select "$t") || fail "select $t exited nonzero"
  [ "$got" = "$want" ] \
    || fail "REQ-A1.2: select $t gave '$got', golden baseline says '$want'"
done
echo "ok: defaults reproduce the captured golden baseline for every task type"

# 1b. The legacy entry point is pinned to the same baseline, so generalizing
#     the table cannot move fleet dispatch's behavior (REQ-A1.2 at the wired
#     surface).
for t in execution bookkeeping drain; do
  want=$(golden_row "$t")
  got=$(run_legacy select "$t") || fail "fleet-resource-select select $t exited nonzero"
  [ "$got" = "$want" ] \
    || fail "REQ-A1.2: fleet-resource-select select $t gave '$got', golden says '$want'"
done
legacy_list=$(run_legacy list) || fail "fleet-resource-select list exited nonzero"
[ "$legacy_list" = "$golden" ] \
  || fail "REQ-A1.2: fleet-resource-select list drifted from the golden baseline"
echo "ok: the legacy fleet entry point still emits the golden baseline"

# 2. Determinism (REQ-A1.1): repeated runs are byte-identical.
for t in execution bookkeeping drain offload; do
  first=$(run select "$t") || fail "determinism: select $t exited nonzero"
  for i in 2 3; do
    again=$(run select "$t") || fail "determinism: select $t run $i exited nonzero"
    [ "$again" = "$first" ] \
      || fail "determinism: select $t run $i gave '$again', expected '$first'"
  done
done
echo "ok: resolution is deterministic across repeated runs"

# 3. No LLM/API call in the resolution path (REQ-A1.1): the stubbed clients
#    were never invoked by any run above.
[ ! -f "$tmp/invocations" ] \
  || fail "an outbound client was invoked during resolution: $(sort -u "$tmp/invocations" | tr '\n' ' ')"
echo "ok: zero outbound client invocations during resolution"

# 3b. The same property, guarded STRUCTURALLY (REQ-A1.1's design-level arm):
#     no network or model-invoking command appears in either resolver's call
#     surface. Test 3 only proves the clients were not reached on the paths it
#     exercised; this proves they are not written down at all, so a future
#     branch cannot quietly add one. Comment lines are stripped first: both
#     headers legitimately DISCUSS `claude --model` and the no-LLM floor.
#     Only WHOLE comment lines are stripped, never trailing ones: truncating
#     at the first `#` would also eat live code (`[ "$#" -ge 1 ]`) and could
#     hide a call sitting on such a line.
for surface in "$AS" "$FRS"; do
  code=$(grep -v '^[[:space:]]*#' "$surface" || true)
  [ -n "$code" ] || fail "structural guard: $(basename "$surface") stripped to nothing"
  for forbidden in claude curl wget gh nc ssh http https; do
    if printf '%s\n' "$code" | grep -qw -- "$forbidden"; then
      fail "REQ-A1.1: '$forbidden' appears in the call surface of $(basename "$surface")"
    fi
  done
done
#     Positive control, same discipline as the PATH stub below: plant a call
#     into a copy and confirm the guard catches it, so a grep that silently
#     stopped matching cannot read as a clean pass.
planted=$(printf '%s\ncurl https://example.invalid\n' "$(grep -v '^[[:space:]]*#' "$AS")")
caught=0
for forbidden in claude curl wget gh nc ssh http https; do
  if printf '%s\n' "$planted" | grep -qw -- "$forbidden"; then caught=1; fi
done
[ "$caught" = 1 ] || fail "structural guard positive control failed (a planted call went unseen)"
echo "ok: neither resolver's call surface names a network or model-invoking command"

# 4. Fallback precedence (REQ-A1.3), per column. `neither set` is test 1.
#    (b) legacy only: the `fleet_*` knob still decides — an existing overlay
#    keeps working untouched.
reset_layers
printf 'fleet_model_execution: haiku\nfleet_effort_execution: low\nfleet_command_execution: drain\n' >"$mlocal_cfg"
got=$(run select execution 2>/dev/null) || fail "fallback(b): select execution exited nonzero"
[ "$got" = "haiku${TAB}low${TAB}drain" ] \
  || fail "REQ-A1.3(b): an unset general knob must fall back to fleet_*, got '$got'"
#    (c) general only: the `allocation_*` knob decides.
reset_layers
printf 'allocation_model_execution: fable\nallocation_effort_execution: medium\nallocation_command_execution: orchestrate\n' >"$mlocal_cfg"
got=$(run select execution 2>/dev/null) || fail "fallback(c): select execution exited nonzero"
[ "$got" = "fable${TAB}medium${TAB}orchestrate" ] \
  || fail "REQ-A1.3(c): a set general knob must decide, got '$got'"
#    (d) both set: the general knob wins over the legacy one.
reset_layers
cat >"$mlocal_cfg" <<'EOF'
fleet_model_execution: haiku
fleet_effort_execution: low
fleet_command_execution: drain
allocation_model_execution: fable
allocation_effort_execution: medium
allocation_command_execution: orchestrate
EOF
got=$(run select execution 2>/dev/null) || fail "fallback(d): select execution exited nonzero"
[ "$got" = "fable${TAB}medium${TAB}orchestrate" ] \
  || fail "REQ-A1.3(d): the general knob must win over fleet_*, got '$got'"
#    Precedence is per column and per key: an untouched sibling is unmoved.
got=$(run select bookkeeping 2>/dev/null) || fail "fallback: select bookkeeping exited nonzero"
[ "$got" = "$(golden_row bookkeeping)" ] \
  || fail "REQ-A1.3: an execution-keyed override must not move bookkeeping, got '$got'"
echo "ok: allocation_* wins when set, falls back to fleet_* when unset, per column"

# 4b. The fallback is a pinned behavior, not only a doc claim: an explicit
#     `unset` general knob at an overlay layer re-arms the legacy fallback.
reset_layers
printf 'fleet_model_execution: haiku\nallocation_model_execution: unset\n' >"$mlocal_cfg"
got=$(run resolve execution model 2>/dev/null) || fail "explicit unset: resolve exited nonzero"
[ "$got" = haiku ] \
  || fail "REQ-A1.3: an explicit 'unset' must re-arm the fleet_* fallback, got '$got'"
echo "ok: the explicit 'unset' sentinel arms the legacy fallback"

# 5. The `inherit` sentinel (D-13) is the shipped default at the three
#    surfaces that perform no selection today, and resolves AS inherit.
reset_layers
for k in orchestrate_dispatch execute_step offload; do
  got=$(run resolve "$k" model) || fail "inherit: resolve $k model exited nonzero"
  [ "$got" = inherit ] || fail "D-13: $k model should ship 'inherit', got '$got'"
  got=$(run resolve "$k" effort) || fail "inherit: resolve $k effort exited nonzero"
  [ "$got" = inherit ] || fail "D-13: $k effort should ship 'inherit', got '$got'"
  got=$(run select "$k") || fail "inherit: select $k exited nonzero"
  [ "$got" = "inherit${TAB}inherit${TAB}-" ] \
    || fail "D-13: select $k should be 'inherit<TAB>inherit<TAB>-', got '$got'"
done
echo "ok: the inherit sentinel is the shipped default at the non-fleet surfaces"

# 5b. A non-fleet surface is still tunable: setting its general knob applies a
#     concrete tier instead of inheriting.
reset_layers
printf 'allocation_model_offload: haiku\n' >"$mlocal_cfg"
got=$(run resolve offload model 2>/dev/null) || fail "offload override exited nonzero"
[ "$got" = haiku ] || fail "a configured non-fleet model should win over inherit, got '$got'"
echo "ok: a non-fleet surface knob overrides the inherit default"

# 5c. `inherit` is NOT legal at the fleet task-type keys: fleet dispatch's
#     downstream contract (fleet-allocate.sh) validates the row against the
#     concrete enums and has no ambient value to fall back to, so the sentinel
#     is refused by the same by-layer policy as any other out-of-enum value
#     rather than emitted into a launch that cannot honor it.
for col in model effort; do
  reset_layers
  printf 'allocation_%s_execution: inherit\n' "$col" >"$tracked_cfg"
  rc=0
  run resolve execution "$col" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 4 ] \
    || fail "'inherit' on a fleet task-type $col knob must hard-fail exit 4, got $rc"
done
echo "ok: inherit is refused at the fleet task-type keys"

# 6. The command column is fleet-only (D-5): asking a non-fleet surface for it
#    is a refusal, not an empty string, and `select` marks it absent with `-`.
reset_layers
rc=0
err=$(run resolve offload command 2>&1 >/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "resolve offload command: exit $rc, expected 2"
printf '%s' "$err" | grep -q command \
  || fail "resolve offload command: the diagnostic should name the column, got '$err'"
echo "ok: the command column is refused at surfaces that do not consume it"

# 7. Enum validation across all three columns (REQ-A1.4): an out-of-enum
#    repo-tracked value hard-fails (exit 4), never resolves.
for kv in "allocation_model_execution: gpt-5" \
  "allocation_effort_execution: extreme" \
  "allocation_command_execution: polish"; do
  reset_layers
  printf '%s\n' "$kv" >"$tracked_cfg"
  rc=0
  run select execution >/dev/null 2>&1 || rc=$?
  [ "$rc" = 4 ] || fail "out-of-enum '$kv': exit $rc, expected 4 (hard-fail)"
done
echo "ok: every column's enum is validated under the by-layer policy"

# 7b. The command enum's closed set carries review-sequence disjointness by
#     CONSTRUCTION (REQ-A1.4): every command the generalized table can emit
#     fails the nestable-review-skill predicate, and the predicate is proven
#     non-vacuous against the shipped `polish` skill.
reset_layers
skills_root="$here/../skills"
[ -d "$skills_root" ] || fail "skills root not found at $skills_root"
grep -Eq '^argument-hint:.*--nested' "$skills_root/polish/SKILL.md" \
  || fail "cross-check sanity: the shipped polish skill no longer declares --nested (predicate drifted?)"
listing=$(run list) || fail "list exited nonzero"
commands=$(printf '%s\n' "$listing" | cut -f4 | grep -v '^-$' | sort -u)
[ -n "$commands" ] || fail "list emitted no command values to cross-check"
for c in $commands; do
  skill_md="$skills_root/$c/SKILL.md"
  if [ -f "$skill_md" ] && grep -Eq '^argument-hint:.*--nested' "$skill_md"; then
    fail "REQ-A1.4 violation: selectable command '$c' is a nestable review skill"
  fi
done
echo "ok: the selectable command set stays disjoint from the nestable-review set"

# 8. By-layer malformed policy (REQ-A1.4): an adopter-layer malformed value
#    degrades to the core default with a warning. Core ships `unset`, so the
#    degrade lands on the fleet_* fallback — the golden-baseline value.
reset_layers
printf 'allocation_model_execution: gpt-5\n' >"$adopter_cfg"
rc=0
got=$(run resolve execution model 2>"$tmp/warn") || rc=$?
[ "$rc" = 0 ] || fail "malformed adopter value: exit $rc, expected 0 (degrade)"
[ "$got" = "$(golden_row execution | cut -f1)" ] \
  || fail "malformed adopter value should degrade to the shipped baseline, got '$got'"
grep -qi malformed "$tmp/warn" \
  || fail "malformed adopter value: expected a degrade warning on stderr"
echo "ok: the by-layer malformed policy degrades adopter values to the baseline"

# 9. `list` enumerates every key, fleet and non-fleet, and its fleet rows are
#    the golden baseline.
reset_layers
listing=$(run list) || fail "list exited nonzero"
[ "$(printf '%s\n' "$listing" | wc -l | tr -d ' ')" = 6 ] \
  || fail "list: expected 6 rows (3 fleet + 3 non-fleet), got: $listing"
[ "$(printf '%s\n' "$listing" | head -3)" = "$golden" ] \
  || fail "list: the fleet rows drifted from the golden baseline: $listing"
for k in orchestrate_dispatch execute_step offload; do
  printf '%s\n' "$listing" | grep -q "^${k}${TAB}inherit${TAB}inherit${TAB}-$" \
    || fail "list: missing/incorrect $k row in: $listing"
done
echo "ok: list enumerates every selection key"

# 9b. `list` is all-or-nothing: a later-row hard-fail leaves no partial output.
reset_layers
printf 'allocation_model_offload: gpt-5\n' >"$tracked_cfg"
rc=0
out=$(run list 2>/dev/null) || rc=$?
[ "$rc" = 4 ] || fail "list with a malformed repo-tracked offload model: exit $rc, expected 4"
[ -z "$out" ] || fail "list must emit nothing on a hard-fail, got partial output: $out"
echo "ok: list emits nothing on a resolver hard-fail"

# 10. Unknown keys/columns and usage errors are refused (exit 2), never
#     silently defaulted, and a hostile token cannot drive the terminal.
reset_layers
for args in "" "bogus" "select" "resolve" "resolve execution" "select execution extra" "list extra" \
  "select no-such-key" "resolve no-such-key model" "resolve execution no-such-column"; do
  rc=0
  # shellcheck disable=SC2086
  run $args >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "usage/unknown '$args': exit $rc, expected 2"
done
rc=0
err=$(run select "$(printf 'evil\033[2Jkey')" 2>&1 >/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "hostile key: exit $rc, expected 2"
case $err in
  *$(printf '\033')*) fail "hostile key: diagnostic carries a raw escape byte" ;;
esac
echo "ok: unknown keys/columns and usage errors are refused with sanitized diagnostics"

# 11. Repo-drift: the real config/defaults.yml ships the whole knob family with
#     the values the isolated core fixture above assumes, so the fixture cannot
#     silently diverge from the shipped file.
real_defaults="$here/../config/defaults.yml"
fixture_knobs=$(grep '^allocation_' "$core_cfg")
# Guard the guard: an empty list would walk zero rows and report a clean pass,
# which is the one way this check can lie. Same non-vacuity discipline as the
# PATH stub's positive control.
[ "$(printf '%s\n' "$fixture_knobs" | wc -l | tr -d ' ')" = 15 ] \
  || fail "expected 15 allocation_* knobs in the core fixture, got: $fixture_knobs"
while IFS= read -r kv; do
  [ -n "$kv" ] || continue
  grep -q "^$kv\$" "$real_defaults" \
    || fail "config/defaults.yml does not ship '$kv' (fixture and shipped defaults drifted)"
done <<EOF
$fixture_knobs
EOF
echo "ok: shipped defaults carry the whole allocation_* family"

# 12. Broken install (missing shared knob resolver) is exit 5, never a proceed
#     with a garbage value.
broken="$tmp/broken-tree"
mkdir -p "$broken"
cp "$AS" "$broken/allocation-select.sh"
cp "$here/../scripts/echo-safety.sh" "$broken/echo-safety.sh"
rc=0
PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" /bin/bash "$broken/allocation-select.sh" select execution >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "missing shared resolver: exit $rc, expected 5 (broken install)"
echo "ok: a missing shared knob resolver is broken-install exit 5"

# 13. Positive control for the zero-invocation stub: the stub IS reachable on
#     the prefixed PATH, so test 3's assertion is not vacuous.
rm -f "$tmp/invocations"
PATH="$stubbin:$PATH" claude >/dev/null 2>&1 || true
[ -f "$tmp/invocations" ] || fail "stub positive control failed (stub not reachable on PATH)"
rm -f "$tmp/invocations"
echo "ok: the no-LLM stub is verified reachable"

echo "ALL PASS: allocation-select"
