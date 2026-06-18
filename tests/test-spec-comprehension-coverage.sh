#!/bin/bash
# Cross-cutting test-coverage gate for specs/spec-comprehension (Task 11 of
# specs/spec-comprehension; D-4 · REQ-E1.2, REQ-E1.4, REQ-E1.7, REQ-C1.7,
# REQ-D1.1).
#
# Task 11's "Done when" requires that every REQ carrying a [test] verification
# path in specs/spec-comprehension/test-spec.md has an executing automated test.
# The per-view tasks (Tasks 1-10) each shipped their own test-first suites; this
# gate is the cross-cutting assertion that the corpus, taken together, leaves no
# [test] REQ uncovered, and stays that way as the spec grows. A future [test]
# REQ added without a covering test fails here, in CI under `mise run test`,
# rather than silently slipping through a one-time manual audit.
#
# Why a SCOPED file set rather than a grep over all of tests/: REQ ids are
# per-spec, not global. customization-overlay, bootstrap, and other bundles each
# define their own REQ-E1.4, REQ-A1.1, and so on. A blind `grep REQ-E1.4 tests/`
# would match another spec's identically-numbered requirement and report false
# coverage. The gate therefore searches only the spec-comprehension test files
# (the suites for this spec's scripts plus the sibling-touchpoints guard), where
# a REQ id unambiguously denotes this spec's requirement.
#
# This is a [test]-path coverage gate, not a behavioural test: it asserts the
# label-to-test linkage exists, leaving each suite to assert its own behaviour.
# The linkage is by REQ id appearing in a covering suite. Task 11 added the one
# label this gate first surfaced as missing (REQ-F1.3 in test-spec-walkthrough.sh,
# whose read-only assertion already proved the behaviour under its REQ-A1.3 /
# REQ-E1.1 labels).
#
# Runs standalone: ./tests/test-spec-comprehension-coverage.sh
set -u
# Pin the C locale so awk/grep ranges do not vary by host collation (REQ-K1.5).
LC_ALL=C
export LC_ALL
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_SPEC="$REPO_ROOT/specs/spec-comprehension/test-spec.md"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() {
  echo "ok: $1"
}

# The spec-comprehension test-file set: the suites for this spec's scripts plus
# the sibling-touchpoints structural guard. This is the collision-safe search
# scope (see header). Keep it in lockstep with the scripts the spec ships; a
# missing entry is flagged below so the scope cannot silently shrink.
sc_tests=(
  test-spec-walkthrough.sh
  test-spec-model.sh
  test-spec-translate.sh
  test-spec-onepager.sh
  test-spec-teachback.sh
  test-spec-assemble.sh
  test-spec-graph.sh
  test-spec-decisionmap.sh
  test-spec-scope.sh
  test-sibling-touchpoints.sh
)

# 1. test-spec.md, the coverage contract, must exist.
if [ ! -f "$TEST_SPEC" ]; then
  echo "FAIL: test-spec.md absent at $TEST_SPEC" >&2
  echo "1 failure(s)" >&2
  exit 1
fi

# 2. Every declared coverage source must exist and be executable: a renamed or
#    deleted suite must not silently shrink the search scope into a false pass.
present_tests=()
for t in "${sc_tests[@]}"; do
  p="$REPO_ROOT/tests/$t"
  if [ ! -f "$p" ]; then
    fail "coverage source missing: tests/$t (the gate's search scope is incomplete)"
    continue
  fi
  if [ ! -x "$p" ]; then
    fail "coverage source not executable: tests/$t"
  fi
  present_tests+=("$p")
done

# 3. Extract the [test]-tagged REQ ids from test-spec.md. A heading is a [test]
#    path when its tag is exactly "[test]" or a "[test + ...]" compound
#    ([test + manual], [test + design-level]); the precise forms reject a
#    near-miss label like [testing] that a bare "[test" substring would catch.
#    [manual]/[design-level]/[Gherkin]-only paths carry no [test] tag and are
#    excluded.
test_reqs="$(awk '/^### REQ-/ { if ($0 ~ /\[test\]/ || $0 ~ /\[test \+/) print $2 }' "$TEST_SPEC")"

if [ -z "$test_reqs" ]; then
  fail "no [test]-tagged REQ found in test-spec.md (parse error or empty spec?)"
fi

# 4. Each [test] REQ must be labelled in at least one coverage source. The id is
#    matched with its literal dots and a trailing boundary that excludes both a
#    digit and a dot, so REQ-F1.3 is satisfied by neither a longer id
#    (REQ-F1.30) nor a sub-id (a hypothetical REQ-F1.3.0); the boundary stays
#    within the portable BSD-grep floor (no \b word boundary).
n_reqs=0
while IFS= read -r req; do
  [ -n "$req" ] || continue
  n_reqs=$((n_reqs + 1))
  esc="$(printf '%s' "$req" | sed 's/[.]/\\./g')"
  if [ "${#present_tests[@]}" -gt 0 ] \
    && grep -Eq -- "${esc}([^0-9.]|\$)" "${present_tests[@]}" 2>/dev/null; then
    ok "$req covered"
  else
    fail "$req has a [test] path in test-spec.md but no spec-comprehension test labels it"
  fi
done <<EOF
$test_reqs
EOF

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all $n_reqs [test]-tagged REQ(s) covered across ${#present_tests[@]} spec-comprehension test file(s)"
