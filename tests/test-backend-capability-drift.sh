#!/bin/bash
# Tests for scripts/check-backend-capability-drift.sh — the backend-capability
# triangle tether (guard-coverage Task 9; REQ-F1.2, REQ-H1.3, D-10).
#
# Three surfaces restate the same capability facts: the prose table in
# doctrine/backend-capability-contract.md (the direction of truth — a registry
# change requires the doc edit first), the `caps_for()` registry in
# scripts/orchestrate-backends.sh, and the operator-facing backend table in
# docs/fleet.md. This suite drives the checker that keeps them in agreement:
# green on today's agreeing triple, red on a divergence seeded in ANY of the
# three, and fail-closed when a side parses to zero rows.
#
# The suite runs under the `test` task, which the `check` aggregate depends on
# (REQ-F1.2's "run via the suite within the check aggregate" wiring).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-backend-capability-drift.sh"

failures=0
assert() {
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}

assert_contains() {
  case "$2" in
    *"$3"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (output did not mention '$3'): $2" >&2
      failures=$((failures + 1))
      ;;
  esac
}

if [ ! -f "$CHECKER" ]; then
  echo "FAIL: checker script missing at $CHECKER" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# ---------------------------------------------------------------------------
# Fixture trio. make_trio writes the agreeing baseline; a case then rewrites
# exactly one surface with its own heredoc, so what diverges is visible in the
# case rather than encoded in a substitution.
# ---------------------------------------------------------------------------
write_contract() {
  cat >"$1/contract.md"
}
write_registry() {
  cat >"$1/backends.sh"
}
write_fleet() {
  cat >"$1/fleet.md"
}

make_trio() {
  mkdir -p "$1"
  write_contract "$1" <<'EOF'
# Fixture Backend Capability Contract

| Backend | `interactive` | `can_observe` | `can_steer_inflight` | `provides_attention_surface` | `supports_parallel` | Session-grade | `overhead` | `hook_registration` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `alpha` | true | true | true | false | true | yes | `full-session` | true |
| `beta` | false | false | false | false | n/a | deferred | `none` | false |
EOF
  write_registry "$1" <<'EOF'
#!/bin/sh
# Fixture registry.
caps_for() {
  case "$1" in
    alpha) echo "true true true false true yes full-session true" ;;
    beta) echo "false false false false na deferred none false" ;;
    *) return 1 ;;
  esac
}
EOF
  write_fleet "$1" <<'EOF'
# Fixture fleet doc

| Backend | What it is | Observe / steer | Session-grade |
| --- | --- | --- | --- |
| `alpha` | Something | yes / yes | yes |
| `beta` | Something else | no / no | deferred to you |
EOF
}

run_trio() {
  /bin/bash "$CHECKER" "$1/contract.md" "$1/backends.sh" "$1/fleet.md" 2>&1
}

# ---------------------------------------------------------------------------
# 1. The real trio agrees. This is the green baseline the guard has to hold on
#    the shipped tree.
# ---------------------------------------------------------------------------
out="$(/bin/bash "$CHECKER" 2>&1)"
assert "the shipped contract, caps_for(), and fleet table agree" 0 $?
assert_contains "the green run reports how many backends it compared" "$out" "backends"

# ---------------------------------------------------------------------------
# 2. The agreeing fixture trio passes.
# ---------------------------------------------------------------------------
make_trio "$tmp/base"
out="$(run_trio "$tmp/base")"
assert "an agreeing fixture trio passes" 0 $?

# ---------------------------------------------------------------------------
# 3. Divergence seeded in surface 1 (the prose contract) is caught.
# ---------------------------------------------------------------------------
make_trio "$tmp/contract-drift"
write_contract "$tmp/contract-drift" <<'EOF'
# Fixture Backend Capability Contract

| Backend | `interactive` | `can_observe` | `can_steer_inflight` | `provides_attention_surface` | `supports_parallel` | Session-grade | `overhead` | `hook_registration` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `alpha` | true | false | true | false | true | yes | `full-session` | true |
| `beta` | false | false | false | false | n/a | deferred | `none` | false |
EOF
out="$(run_trio "$tmp/contract-drift")"
assert "a drifted prose-contract row fails" 1 $?
assert_contains "the prose-contract failure names the backend" "$out" "alpha"
assert_contains "the prose-contract failure names the field" "$out" "can_observe"

# ---------------------------------------------------------------------------
# 4. Divergence seeded in surface 2 (`caps_for()`) is caught.
# ---------------------------------------------------------------------------
make_trio "$tmp/registry-drift"
write_registry "$tmp/registry-drift" <<'EOF'
#!/bin/sh
caps_for() {
  case "$1" in
    alpha) echo "true true true false true yes light true" ;;
    beta) echo "false false false false na deferred none false" ;;
    *) return 1 ;;
  esac
}
EOF
out="$(run_trio "$tmp/registry-drift")"
assert "a drifted caps_for() value fails" 1 $?
assert_contains "the caps_for() failure names the field" "$out" "overhead"

# ---------------------------------------------------------------------------
# 5. Divergence seeded in surface 3 (the fleet table) is caught, on both the
#    observe/steer column and the session-grade column.
# ---------------------------------------------------------------------------
make_trio "$tmp/fleet-drift"
write_fleet "$tmp/fleet-drift" <<'EOF'
# Fixture fleet doc

| Backend | What it is | Observe / steer | Session-grade |
| --- | --- | --- | --- |
| `alpha` | Something | yes / no | yes |
| `beta` | Something else | no / no | deferred to you |
EOF
out="$(run_trio "$tmp/fleet-drift")"
assert "a drifted fleet observe/steer cell fails" 1 $?
assert_contains "the fleet observe/steer failure names the field" "$out" "can_steer_inflight"

make_trio "$tmp/fleet-grade-drift"
write_fleet "$tmp/fleet-grade-drift" <<'EOF'
# Fixture fleet doc

| Backend | What it is | Observe / steer | Session-grade |
| --- | --- | --- | --- |
| `alpha` | Something | yes / yes | yes |
| `beta` | Something else | no / no | no |
EOF
out="$(run_trio "$tmp/fleet-grade-drift")"
assert "a drifted fleet session-grade cell fails" 1 $?
assert_contains "the fleet session-grade failure names the field" "$out" "session_grade"

# ---------------------------------------------------------------------------
# 6. The normalization contract holds, so the guard fires only on real
#    divergence: `n/a` in prose equals `na` in the registry, backticks and
#    emphasis are stripped, and a trailing annotation on a fleet cell
#    ("yes (recoverable via --resume)", "deferred to you") is not a mismatch.
# ---------------------------------------------------------------------------
make_trio "$tmp/normalized"
write_fleet "$tmp/normalized" <<'EOF'
# Fixture fleet doc

| Backend | What it is | Observe / steer | Session-grade |
| --- | --- | --- | --- |
| `alpha` | Something | yes / yes | yes (recoverable via `--resume`) |
| `beta` (manual) | Something else | *no* / `no` | deferred to you |
EOF
out="$(run_trio "$tmp/normalized")"
assert "annotations, emphasis, and backticks normalize away" 0 $?

make_trio "$tmp/na-spelling"
write_contract "$tmp/na-spelling" <<'EOF'
# Fixture Backend Capability Contract

| Backend | `interactive` | `can_observe` | `can_steer_inflight` | `provides_attention_surface` | `supports_parallel` | Session-grade | `overhead` | `hook_registration` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `alpha` | true | true | true | false | true | yes | `full-session` | true |
| `beta` | false | n/a | n/a | false | n/a | deferred | `none` | false |
EOF
write_registry "$tmp/na-spelling" <<'EOF'
#!/bin/sh
caps_for() {
  case "$1" in
    alpha) echo "true true true false true yes full-session true" ;;
    beta) echo "false na na false na deferred none false" ;;
    *) return 1 ;;
  esac
}
EOF
write_fleet "$tmp/na-spelling" <<'EOF'
# Fixture fleet doc

| Backend | What it is | Observe / steer | Session-grade |
| --- | --- | --- | --- |
| `alpha` | Something | yes / yes | yes |
| `beta` | Something else | n/a | deferred to you |
EOF
out="$(run_trio "$tmp/na-spelling")"
assert "prose 'n/a' and registry 'na' are the same value" 0 $?

# A single observe/steer cell applies to BOTH capabilities, so an `n/a` there
# against a false/false contract row is still a divergence.
make_trio "$tmp/na-half"
write_fleet "$tmp/na-half" <<'EOF'
# Fixture fleet doc

| Backend | What it is | Observe / steer | Session-grade |
| --- | --- | --- | --- |
| `alpha` | Something | yes / yes | yes |
| `beta` | Something else | n/a | deferred to you |
EOF
out="$(run_trio "$tmp/na-half")"
assert "a single-value observe/steer cell is compared against both fields" 1 $?

# ---------------------------------------------------------------------------
# 7. Backend-set divergence is caught in both directions between the prose
#    contract and the registry.
# ---------------------------------------------------------------------------
make_trio "$tmp/extra-prose"
write_contract "$tmp/extra-prose" <<'EOF'
# Fixture Backend Capability Contract

| Backend | `interactive` | `can_observe` | `can_steer_inflight` | `provides_attention_surface` | `supports_parallel` | Session-grade | `overhead` | `hook_registration` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `alpha` | true | true | true | false | true | yes | `full-session` | true |
| `beta` | false | false | false | false | n/a | deferred | `none` | false |
| `gamma` | false | false | false | false | true | no | `light` | false |
EOF
out="$(run_trio "$tmp/extra-prose")"
assert "a prose backend absent from caps_for() fails" 1 $?
assert_contains "the missing-registry-arm failure names the backend" "$out" "gamma"

make_trio "$tmp/extra-registry"
write_registry "$tmp/extra-registry" <<'EOF'
#!/bin/sh
caps_for() {
  case "$1" in
    alpha) echo "true true true false true yes full-session true" ;;
    beta) echo "false false false false na deferred none false" ;;
    gamma) echo "false false false false true no light false" ;;
    *) return 1 ;;
  esac
}
EOF
out="$(run_trio "$tmp/extra-registry")"
assert "a caps_for() backend absent from the prose contract fails" 1 $?
assert_contains "the missing-prose-arm failure names the backend" "$out" "gamma"

# ---------------------------------------------------------------------------
# 8. Fleet-table set divergence: a contract backend with no fleet row, and a
#    fleet row for a backend the contract does not define.
# ---------------------------------------------------------------------------
make_trio "$tmp/fleet-missing"
write_fleet "$tmp/fleet-missing" <<'EOF'
# Fixture fleet doc

| Backend | What it is | Observe / steer | Session-grade |
| --- | --- | --- | --- |
| `alpha` | Something | yes / yes | yes |
EOF
out="$(run_trio "$tmp/fleet-missing")"
assert "a contract backend missing from the fleet table fails" 1 $?
assert_contains "the missing-fleet-row failure names the backend" "$out" "beta"

make_trio "$tmp/fleet-unknown"
write_fleet "$tmp/fleet-unknown" <<'EOF'
# Fixture fleet doc

| Backend | What it is | Observe / steer | Session-grade |
| --- | --- | --- | --- |
| `alpha` | Something | yes / yes | yes |
| `beta` | Something else | no / no | deferred to you |
| `gamma` | Undocumented elsewhere | no / no | no |
EOF
out="$(run_trio "$tmp/fleet-unknown")"
assert "a fleet row for an unknown backend fails" 1 $?
assert_contains "the unknown-fleet-row failure names the row" "$out" "gamma"

# ---------------------------------------------------------------------------
# 8b. The fleet table's `full-session` row is a semantic value, not a backend,
#     and is exempt by name rather than by accident.
# ---------------------------------------------------------------------------
make_trio "$tmp/semantic"
write_fleet "$tmp/semantic" <<'EOF'
# Fixture fleet doc

| Backend | What it is | Observe / steer | Session-grade |
| --- | --- | --- | --- |
| `full-session` (default) | Not a backend but a **semantic value** | per resolution | yes, when an *eligible* rung is present |
| `alpha` | Something | yes / yes | yes |
| `beta` | Something else | no / no | deferred to you |
EOF
out="$(run_trio "$tmp/semantic")"
assert "the full-session semantic row is exempt from the comparison" 0 $?

# ---------------------------------------------------------------------------
# 9. Fail-closed: each of the three surfaces parsing to zero rows is an error
#    (REQ-H1.3). A vacuous parse must never read as agreement.
# ---------------------------------------------------------------------------
make_trio "$tmp/zero-contract"
write_contract "$tmp/zero-contract" <<'EOF'
# Fixture contract with no capability table
EOF
out="$(run_trio "$tmp/zero-contract")"
assert "a zero-row prose contract fails closed" 2 $?
assert_contains "the zero-row prose diagnostic names the surface" "$out" "capability table"

make_trio "$tmp/zero-registry"
write_registry "$tmp/zero-registry" <<'EOF'
#!/bin/sh
# No caps_for() here.
EOF
out="$(run_trio "$tmp/zero-registry")"
assert "a zero-row caps_for() registry fails closed" 2 $?
assert_contains "the zero-row registry diagnostic names the surface" "$out" "caps_for"

make_trio "$tmp/zero-fleet"
write_fleet "$tmp/zero-fleet" <<'EOF'
# Fixture fleet doc with no backend table
EOF
out="$(run_trio "$tmp/zero-fleet")"
assert "a zero-row fleet table fails closed" 2 $?
assert_contains "the zero-row fleet diagnostic names the surface" "$out" "backend table"

# ---------------------------------------------------------------------------
# 10. Fail-closed: an unrecognized capability token is a parse error, not a
#     silent mismatch or a silent pass.
# ---------------------------------------------------------------------------
make_trio "$tmp/bad-token"
write_contract "$tmp/bad-token" <<'EOF'
# Fixture Backend Capability Contract

| Backend | `interactive` | `can_observe` | `can_steer_inflight` | `provides_attention_surface` | `supports_parallel` | Session-grade | `overhead` | `hook_registration` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `alpha` | true | maybe | true | false | true | yes | `full-session` | true |
| `beta` | false | false | false | false | n/a | deferred | `none` | false |
EOF
out="$(run_trio "$tmp/bad-token")"
assert "an unrecognized capability token fails closed" 2 $?
assert_contains "the bad-token diagnostic names the value" "$out" "maybe"

# 10b. A caps_for() arm with the wrong field count is a parse error too.
make_trio "$tmp/short-arm"
write_registry "$tmp/short-arm" <<'EOF'
#!/bin/sh
caps_for() {
  case "$1" in
    alpha) echo "true true true false true yes full-session" ;;
    beta) echo "false false false false na deferred none false" ;;
    *) return 1 ;;
  esac
}
EOF
out="$(run_trio "$tmp/short-arm")"
assert "a short caps_for() arm fails closed" 2 $?
assert_contains "the short-arm diagnostic names the backend" "$out" "alpha"

# 10b-i. The same arity guard on the prose side. A row missing a trailing
#        column used to emit only the fields it carried, and the comparison
#        loop skips a field the contract has no fact for — so a truncated row
#        in the surface the contract calls the direction of truth read as
#        agreement and exited 0. The registry arm above has always been held
#        to its field count; the prose table now is too.
make_trio "$tmp/short-row"
write_contract "$tmp/short-row" <<'EOF'
# Fixture Backend Capability Contract

| Backend | `interactive` | `can_observe` | `can_steer_inflight` | `provides_attention_surface` | `supports_parallel` | Session-grade | `overhead` | `hook_registration` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `alpha` | true | true | true | false | true | yes | `full-session` |
| `beta` | false | false | false | false | n/a | deferred | `none` | false |
EOF
out="$(run_trio "$tmp/short-row")"
assert "a short prose contract row fails closed" 2 $?
assert_contains "the short-row diagnostic names the backend" "$out" "alpha"

# 10c. A backend name outside the identifier grammar `caps_for()`'s own
#      valid_name() enforces is a parse error. Left unvalidated, a name
#      carrying a regex metacharacter would also make the set comparison match
#      an unrelated backend.
make_trio "$tmp/bad-name"
write_contract "$tmp/bad-name" <<'EOF'
# Fixture Backend Capability Contract

| Backend | `interactive` | `can_observe` | `can_steer_inflight` | `provides_attention_surface` | `supports_parallel` | Session-grade | `overhead` | `hook_registration` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `a.b` | true | true | true | false | true | yes | `full-session` | true |
| `beta` | false | false | false | false | n/a | deferred | `none` | false |
EOF
out="$(run_trio "$tmp/bad-name")"
assert "a backend name outside the identifier grammar fails closed" 2 $?
assert_contains "the bad-name diagnostic names the offending value" "$out" "a.b"

# 10d. The same grammar applies to the other two surfaces, so a malformed name
#      cannot slip in through the registry or the operator doc either.
make_trio "$tmp/bad-name-fleet"
write_fleet "$tmp/bad-name-fleet" <<'EOF'
# Fixture fleet doc

| Backend | What it is | Observe / steer | Session-grade |
| --- | --- | --- | --- |
| `alpha` | Something | yes / yes | yes |
| `Beta!` | Something else | no / no | deferred to you |
EOF
out="$(run_trio "$tmp/bad-name-fleet")"
assert "a malformed fleet backend name fails closed" 2 $?

# 10e. A duplicate row for one backend breaks the one-row-per-backend contract.
#      Left undetected, the field comparison would compare a two-line value
#      against a one-line one and report a mismatch nobody can act on.
make_trio "$tmp/dupe-backend"
write_contract "$tmp/dupe-backend" <<'EOF'
# Fixture Backend Capability Contract

| Backend | `interactive` | `can_observe` | `can_steer_inflight` | `provides_attention_surface` | `supports_parallel` | Session-grade | `overhead` | `hook_registration` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `alpha` | true | true | true | false | true | yes | `full-session` | true |
| `alpha` | true | true | true | false | true | yes | `full-session` | true |
| `beta` | false | false | false | false | n/a | deferred | `none` | false |
EOF
out="$(run_trio "$tmp/dupe-backend")"
assert "a duplicate backend row fails closed" 2 $?
assert_contains "the duplicate-row diagnostic names the backend" "$out" "alpha"

# 10f. The checker must not depend on writing a scratch file into TMPDIR: a
#      predictable name in a world-writable directory is a symlink-following
#      write waiting to happen, and the repo's convention is mktemp templates
#      (scripts/classify-ci-failure.sh, scripts/builder-guards.sh). Proving it
#      by behaviour rather than by inspection: with TMPDIR unwritable, the
#      malformed-input diagnostic must still come through intact.
mkdir -p "$tmp/readonly-tmp"
chmod 500 "$tmp/readonly-tmp"
if [ -w "$tmp/readonly-tmp" ]; then
  # Root writes through mode 500, so the fixture cannot be built and the
  # failure mode is unobservable. Skip rather than fail, matching the
  # convention the sibling suites already use for permission fixtures
  # (test-config-get.sh, test-install-writer.sh, test-check-workflow-posture.sh).
  echo "skip: unwritable-TMPDIR case (running as root)"
else
  out="$(TMPDIR="$tmp/readonly-tmp" run_trio "$tmp/short-arm")"
  assert "an unwritable TMPDIR does not degrade the diagnostic" 2 $?
  assert_contains "the diagnostic survives an unwritable TMPDIR" "$out" "alpha"
fi
chmod 700 "$tmp/readonly-tmp"

# ---------------------------------------------------------------------------
# 11. Fail-closed: a missing input file is an error.
# ---------------------------------------------------------------------------
/bin/bash "$CHECKER" "$tmp/nope.md" "$tmp/base/backends.sh" "$tmp/base/fleet.md" >/dev/null 2>&1
assert "a missing prose contract is an error" 2 $?
/bin/bash "$CHECKER" "$tmp/base/contract.md" "$tmp/nope.sh" "$tmp/base/fleet.md" >/dev/null 2>&1
assert "a missing registry script is an error" 2 $?
/bin/bash "$CHECKER" "$tmp/base/contract.md" "$tmp/base/backends.sh" "$tmp/nope.md" >/dev/null 2>&1
assert "a missing fleet doc is an error" 2 $?

# ---------------------------------------------------------------------------
# 12. Done-when, on the real corpus: editing one `caps_for()` value in a copy
#     of the shipped registry turns the check red.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/real"
sed 's/^    subagent) echo "false false false false true no light false" ;;/    subagent) echo "false true false false true no light false" ;;/' \
  "$REPO_ROOT/scripts/orchestrate-backends.sh" >"$tmp/real/backends.sh"
if cmp -s "$tmp/real/backends.sh" "$REPO_ROOT/scripts/orchestrate-backends.sh"; then
  echo "FAIL: the caps_for() edit fixture matched nothing (the registry's row shape moved)" >&2
  failures=$((failures + 1))
else
  out="$(/bin/bash "$CHECKER" \
    "$REPO_ROOT/doctrine/backend-capability-contract.md" \
    "$tmp/real/backends.sh" \
    "$REPO_ROOT/docs/fleet.md" 2>&1)"
  assert "editing a real caps_for() value turns the check red" 1 $?
  assert_contains "the red run names the edited backend" "$out" "subagent"
fi

# ---------------------------------------------------------------------------
# 13. A hostile CDPATH must not corrupt the script's repo-root derivation.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/decoy/scripts" "$tmp/work/docs"
cp -R "$REPO_ROOT/scripts" "$tmp/work/"
cp -R "$REPO_ROOT/doctrine" "$tmp/work/"
cp "$REPO_ROOT/docs/fleet.md" "$tmp/work/docs/"
(cd "$tmp/work" && CDPATH="$tmp/decoy" /bin/bash scripts/check-backend-capability-drift.sh >/dev/null 2>&1)
assert "CDPATH does not corrupt root derivation" 0 $?

# ---------------------------------------------------------------------------
# 14. Each surface contributes its FIRST matching table only. A later table
#     carrying the same header is a neighbouring table, not a continuation of
#     the registry: merging it invents backends the surface never defined (or,
#     for an identical copy, a duplicate-row parse error) out of prose that is
#     illustrative rather than normative.
# ---------------------------------------------------------------------------
make_trio "$tmp/second-contract-table"
write_contract "$tmp/second-contract-table" <<'EOF'
# Fixture Backend Capability Contract

| Backend | `interactive` | `can_observe` | `can_steer_inflight` | `provides_attention_surface` | `supports_parallel` | Session-grade | `overhead` | `hook_registration` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `alpha` | true | true | true | false | true | yes | `full-session` | true |
| `beta` | false | false | false | false | n/a | deferred | `none` | false |

## An illustrative table, not the registry

| Backend | `interactive` | `can_observe` | `can_steer_inflight` | `provides_attention_surface` | `supports_parallel` | Session-grade | `overhead` | `hook_registration` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `hypothetical` | true | true | true | false | true | yes | `light` | true |
EOF
out="$(run_trio "$tmp/second-contract-table")"
assert "a later capability table in the prose contract is not merged" 0 $?

make_trio "$tmp/second-fleet-table"
write_fleet "$tmp/second-fleet-table" <<'EOF'
# Fixture fleet doc

| Backend | What it is | Observe / steer | Session-grade |
| --- | --- | --- | --- |
| `alpha` | Something | yes / yes | yes |
| `beta` | Something else | no / no | deferred to you |

## An illustrative table, not the backend registry

| Backend | What it is | Observe / steer | Session-grade |
| --- | --- | --- | --- |
| `hypothetical` | An example | yes / no | yes |
EOF
out="$(run_trio "$tmp/second-fleet-table")"
assert "a later backend table in the fleet doc is not merged" 0 $?

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all backend-capability-drift tests passed"
