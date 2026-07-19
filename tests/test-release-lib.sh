#!/bin/bash
# Tests for scripts/release-lib.sh — the version comparator rl_version_gt, the
# layer below the release "pending" definition (release-hardening Task 1; D-6;
# REQ-E1.1, REQ-E1.2).
#
# Contract under test (semver.org 2.0.0 §11 precedence, the surface the
# `pending` comparator never reaches — `pending` only ever compares
# release-vs-release, so a prerelease-ordering regression ships silently
# without this suite):
#   - two prereleases: `-rc.1 < -rc.2` (numeric identifiers compared
#     numerically);
#   - a numeric identifier ranks BELOW an alphanumeric one (`-1 < -alpha`);
#   - fewer prerelease fields rank lower when the shared prefix is equal
#     (`-alpha < -alpha.1`);
#   - a prerelease ranks below its associated release (`1.0.0-rc.1 < 1.0.0`);
#   - build metadata is accepted and ignored for precedence
#     (`1.0.0+build == 1.0.0`).
# Plus a boundary case at a safe, non-overflowing numeric-identifier width
# (REQ-E1.2): the 64-bit overflow is a documented in-code limit, not guarded,
# so this asserts current ranking well within the signed-64-bit range rather
# than probing the overflow itself.
#
# This unit adds no behavior: D-6 mandates no change to the comparator's
# arithmetic. These assertions pin the currently-correct precedence surface so
# a future regression is caught; each was validated non-vacuous by mutation
# injection during development (a deliberately broken comparator turns the
# matching assertion red).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
LIB="$here/../scripts/release-lib.sh"
failures=0

[ -r "$LIB" ] || {
  echo "FAIL: scripts/release-lib.sh missing or not readable" >&2
  exit 1
}

# shellcheck source=/dev/null
. "$LIB"

# assert_gt <desc> <a> <b> — expect rl_version_gt <a> <b> to succeed (a > b).
assert_gt() {
  if rl_version_gt "$2" "$3"; then
    echo "ok: $1"
  else
    echo "FAIL: $1 — expected [$2] > [$3]" >&2
    failures=$((failures + 1))
  fi
}

# assert_not_gt <desc> <a> <b> — expect rl_version_gt <a> <b> to fail (a !> b).
assert_not_gt() {
  if rl_version_gt "$2" "$3"; then
    echo "FAIL: $1 — expected [$2] NOT > [$3]" >&2
    failures=$((failures + 1))
  else
    echo "ok: $1"
  fi
}

# assert_lt <desc> <lower> <higher> — assert <lower> ranks strictly below
# <higher>: the higher IS greater, and the lower is NOT greater (both
# directions, so a comparator that returned 0 unconditionally cannot pass).
assert_lt() {
  assert_gt "$1 — higher > lower" "$3" "$2"
  assert_not_gt "$1 — lower !> higher" "$2" "$3"
}

# assert_eq_prec <desc> <a> <b> — assert equal precedence: neither is greater.
assert_eq_prec() {
  assert_not_gt "$1 — a !> b" "$2" "$3"
  assert_not_gt "$1 — b !> a" "$3" "$2"
}

# --- Case 1: two prereleases, -rc.1 < -rc.2 (numeric identifiers numerically).
assert_lt "rc.1 < rc.2 (numeric prerelease identifiers compared numerically)" \
  "1.0.0-rc.1" "1.0.0-rc.2"
# Numeric, not lexical: 11 > 2 numerically (a lexical compare would rank "11"
# below "2").
assert_lt "beta.2 < beta.11 (numeric, not lexical, ordering)" \
  "1.0.0-beta.2" "1.0.0-beta.11"

# --- Case 2: a numeric identifier ranks BELOW an alphanumeric one.
assert_lt "numeric identifier ranks below alphanumeric (1 < alpha)" \
  "1.0.0-1" "1.0.0-alpha"

# --- Case 3: fewer prerelease fields rank lower (shared prefix equal).
assert_lt "fewer fields rank lower (alpha < alpha.1)" \
  "1.0.0-alpha" "1.0.0-alpha.1"

# --- Case 4: a prerelease ranks below its associated release.
assert_lt "prerelease ranks below its release (1.0.0-rc.1 < 1.0.0)" \
  "1.0.0-rc.1" "1.0.0"

# The full semver.org §11 worked example, as a chain, to lock the ordering
# these individual cases compose into.
assert_lt "chain: alpha < alpha.1" "1.0.0-alpha" "1.0.0-alpha.1"
assert_lt "chain: alpha.1 < alpha.beta" "1.0.0-alpha.1" "1.0.0-alpha.beta"
assert_lt "chain: alpha.beta < beta" "1.0.0-alpha.beta" "1.0.0-beta"
assert_lt "chain: beta < beta.2" "1.0.0-beta" "1.0.0-beta.2"
assert_lt "chain: beta.2 < beta.11" "1.0.0-beta.2" "1.0.0-beta.11"
assert_lt "chain: beta.11 < rc.1" "1.0.0-beta.11" "1.0.0-rc.1"
assert_lt "chain: rc.1 < 1.0.0" "1.0.0-rc.1" "1.0.0"

# --- Case 5: build metadata is accepted and ignored for precedence.
assert_eq_prec "build metadata ignored (1.0.0+build.99 == 1.0.0)" \
  "1.0.0+build.99" "1.0.0"
assert_eq_prec "differing build metadata compares equal (1.0.0+a == 1.0.0+b)" \
  "1.0.0+a" "1.0.0+b"
assert_eq_prec "build metadata does not leak into prerelease compare" \
  "1.0.0-rc.1+build" "1.0.0-rc.1"
# Accepted: a build-metadata-bearing version still ranks by its core.
assert_lt "build metadata accepted, core still ranks (1.0.0+b < 1.0.1+b)" \
  "1.0.0+b" "1.0.1+b"

# --- Core major/minor/patch precedence (the numeric arithmetic path).
assert_lt "patch ordering (1.0.0 < 1.0.1)" "1.0.0" "1.0.1"
assert_lt "minor ordering (1.0.9 < 1.1.0)" "1.0.9" "1.1.0"
assert_lt "major ordering (1.9.9 < 2.0.0)" "1.9.9" "2.0.0"
# Numeric, not lexical, on the core too (10 > 2 numerically).
assert_lt "minor numeric not lexical (0.2.0 < 0.10.0)" "0.2.0" "0.10.0"
assert_eq_prec "identical releases are equal (1.2.3 == 1.2.3)" "1.2.3" "1.2.3"

# --- Case 6 (REQ-E1.2): boundary at a safe, non-overflowing numeric width.
# 18-digit numeric prerelease identifiers sit well inside the signed 64-bit
# range (max 9223372036854775807, 19 digits), so the comparator's `10#`
# arithmetic ranks them correctly. This asserts current behavior below the
# documented overflow limit; it does NOT probe the overflow, which is an
# unguarded documented limit (D-6, and the in-code comment on rl_version_gt).
assert_lt "safe wide numeric prerelease width (18 digits, below 2^63)" \
  "1.0.0-rc.999999999999999998" "1.0.0-rc.999999999999999999"
# Same safe-width comparison on the core numeric (major) path.
assert_lt "safe wide numeric core width (18 digits, below 2^63)" \
  "999999999999999998.0.0" "999999999999999999.0.0"

# --- rl_ci_state: canonical CI verdict + workflow-scoped exclusion (Task 3) ---
# (D-4, D-8; REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4.)
#
# rl_ci_state <sha> is the single CI-verdict primitive both release-publish.sh
# (its ci gate) and release-arm.sh (its release-gating verdict) call, so the two
# never drift on what counts as release-gating CI (REQ-C1.2). It reads the
# GitHub statusCheckRollup, judges each check, excludes the untagged-window lock
# SCOPED to its owning workflow (a CheckRun named window-lock AND whose
# checkSuite.workflowRun.workflow.name is release-window — REQ-C1.3), folds the
# remainder to one canonical verdict (green|failing|pending|none|too-many —
# REQ-C1.1), and returns a distinct status (2, empty stdout) on a gh/query
# failure so an infra outage is never misreported as a red verdict.
#
# rl_ci_state calls `gh repo view` and `gh api graphql`; stub gh on PATH with a
# rollup driven by env, mirroring tests/test-release-arm.sh's stub shape. Each
# assertion was validated non-vacuous during development (a bare-name exclusion,
# or a query-failure folded to a verdict, turns the matching assertion red).
ci_tmp=$(mktemp -d)
trap 'rm -rf "$ci_tmp"' EXIT
cat >"$ci_tmp/gh" <<'STUB'
#!/bin/sh
case "$1" in
  repo) printf 'testowner/testrepo\n'; exit 0 ;;
  api)
    # A gh/query failure: exit non-zero with nothing on stdout.
    [ "${CI_QUERY_FAIL:-0}" = 1 ] && { echo "gh: query failed" >&2; exit 1; }
    printf '%s\n' "${CI_ROLLUP_JSON:-}"
    exit 0 ;;
esac
exit 0
STUB
chmod +x "$ci_tmp/gh"

# Node builders (canonical rollup JSON fragments).
#   cr_check <state>  — a quality `ci` CheckRun (ci workflow): green|failing|pending|neutral
cr_check() {
  case "$1" in
    green) printf '{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS","checkSuite":{"workflowRun":{"workflow":{"name":"ci"}}}}' ;;
    failing) printf '{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"FAILURE","checkSuite":{"workflowRun":{"workflow":{"name":"ci"}}}}' ;;
    pending) printf '{"__typename":"CheckRun","name":"ci","status":"IN_PROGRESS","conclusion":null,"checkSuite":{"workflowRun":{"workflow":{"name":"ci"}}}}' ;;
    neutral) printf '{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"NEUTRAL","checkSuite":{"workflowRun":{"workflow":{"name":"ci"}}}}' ;;
  esac
}
#   wl_check <workflow-json> [conclusion] — a `window-lock` CheckRun.
#   <workflow-json> is the value of checkSuite.workflowRun: the real lock's
#   `{"workflow":{"name":"release-window"}}`, a foreign workflow's
#   `{"workflow":{"name":"other"}}`, or `null` (a non-Actions app check with no
#   workflowRun). [conclusion] defaults to FAILURE (red BY DESIGN during the
#   untagged window); pass SUCCESS to model a window-lock that has itself gone
#   green (outside the window).
wl_check() {
  printf '{"__typename":"CheckRun","name":"window-lock","status":"COMPLETED","conclusion":"%s","checkSuite":{"workflowRun":%s}}' "${2:-FAILURE}" "$1"
}
#   sc_check <state> [context] — a legacy commit-status (StatusContext). It carries
#   no workflow, so it can NEVER be the excluded lock (the exclusion is
#   CheckRun-only). state → SUCCESS(green) | PENDING/EXPECTED(pending) | other(failing).
sc_check() {
  printf '{"__typename":"StatusContext","context":"%s","state":"%s"}' "${2:-legacy-ci}" "$1"
}
#   rollup <hasNextPage> <node>... — assemble a full statusCheckRollup response.
rollup() {
  local hnp="$1" nodes="" n
  shift
  for n in "$@"; do [ -z "$nodes" ] && nodes="$n" || nodes="$nodes,$n"; done
  printf '{"data":{"repository":{"object":{"statusCheckRollup":{"contexts":{"pageInfo":{"hasNextPage":%s},"nodes":[%s]}}}}}}' "$hnp" "$nodes"
}
NULL_ROLLUP='{"data":{"repository":{"object":{"statusCheckRollup":null}}}}'

# Put the gh stub first on PATH and mark the stub's env inputs exported ONCE, in
# this (non-subshell) scope, so each rl_ci_state call below reassigns them in the
# current shell rather than inside a command-substitution subshell (which the
# linter's SC2030/SC2031 would flag as a lost modification). PATH stays exported
# by the reassignment, so the child gh stub is found and inherits it.
CI_ROLLUP_JSON=""
CI_QUERY_FAIL=0
export PATH="$ci_tmp:$PATH" CI_ROLLUP_JSON CI_QUERY_FAIL

# assert_ci_state <desc> <rollup-json> <expected-verdict> — drive rl_ci_state
# with the stub returning <rollup-json>, expect verdict on stdout and rc 0.
assert_ci_state() {
  local desc="$1" json="$2" exp="$3" out rc=0
  CI_ROLLUP_JSON="$json"
  CI_QUERY_FAIL=0
  out=$(rl_ci_state deadbeef 2>/dev/null) || rc=$?
  if [ "$out" = "$exp" ] && [ "$rc" -eq 0 ]; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc — expected verdict [$exp] rc [0], got verdict [$out] rc [$rc]" >&2
    failures=$((failures + 1))
  fi
}

# REQ-C1.1 — each canonical verdict.
assert_ci_state "verdict green (a succeeding check, none bad)" \
  "$(rollup false "$(cr_check green)")" "green"
assert_ci_state "verdict failing (a failing check dominates)" \
  "$(rollup false "$(cr_check green)" "$(cr_check failing)")" "failing"
assert_ci_state "verdict pending (a running check, none failing)" \
  "$(rollup false "$(cr_check green)" "$(cr_check pending)")" "pending"
assert_ci_state "verdict none (no checks at all)" \
  "$(rollup false)" "none"
assert_ci_state "verdict none (null rollup)" \
  "$NULL_ROLLUP" "none"
assert_ci_state "verdict none (only NEUTRAL/SKIPPED — no positive confirmation)" \
  "$(rollup false "$(cr_check neutral)")" "none"
assert_ci_state "verdict too-many (a second page could hide a red check)" \
  "$(rollup true "$(cr_check green)")" "too-many"

# REQ-C1.1 — a gh/query failure is a DISTINCT status (2, empty stdout), never a
# verdict: an infra outage must not be misreported as red CI.
CI_QUERY_FAIL=1
qf_rc=0
qf_out=$(rl_ci_state deadbeef 2>/dev/null) || qf_rc=$?
CI_QUERY_FAIL=0
if [ -z "$qf_out" ] && [ "$qf_rc" -eq 2 ]; then
  echo "ok: query failure returns status 2 with empty stdout (distinct from a red verdict)"
else
  echo "FAIL: query failure — expected empty stdout + rc 2, got [$qf_out] rc [$qf_rc]" >&2
  failures=$((failures + 1))
fi

# REQ-C1.3 — the window-lock exclusion is WORKFLOW-SCOPED.
# The REAL release-window lock (red by design) is excluded, so a green quality
# check yields green — the untagged-window deadlock the carve-out exists to avoid
# (REQ-C1.4, autopilot-reflex REQ-D1.3).
assert_ci_state "excl: real release-window window-lock is excluded (green quality wins)" \
  "$(rollup false "$(cr_check green)" "$(wl_check '{"workflow":{"name":"release-window"}}')")" "green"
# The real lock ALONE (nothing else) folds to none, not green — a release gate
# still requires a positive confirming check.
assert_ci_state "excl: the excluded lock alone is not positive confirmation (none)" \
  "$(rollup false "$(wl_check '{"workflow":{"name":"release-window"}}')")" "none"
# A same-named window-lock from ANOTHER workflow is JUDGED, not dropped: its
# FAILURE makes the verdict failing (the fail-open surface REQ-C1.3 closes).
assert_ci_state "excl: foreign-workflow window-lock namesake is judged (failing)" \
  "$(rollup false "$(cr_check green)" "$(wl_check '{"workflow":{"name":"other"}}')")" "failing"
# A null-workflowRun namesake (a non-Actions app check) fails the release-window
# test and is JUDGED too, never silently excluded.
assert_ci_state "excl: null-workflowRun window-lock namesake is judged (failing)" \
  "$(rollup false "$(cr_check green)" "$(wl_check null)")" "failing"
# A CheckRun with checkSuite ENTIRELY ABSENT (not just null workflowRun): the
# exclusion path still coalesces the missing workflow name to "" and judges it.
assert_ci_state "excl: window-lock CheckRun with absent checkSuite is judged (failing)" \
  "$(rollup false "$(cr_check green)" '{"__typename":"CheckRun","name":"window-lock","status":"COMPLETED","conclusion":"FAILURE"}')" "failing"

# REQ-C1.1 — fold precedence and the neutral fold, ISOLATED so each case
# discriminates.
# failing outranks pending with NO green node present (the green+failing/pending
# cases above always carried a green, so this pins failing>pending on its own).
assert_ci_state "fold: failing outranks pending with no green node" \
  "$(rollup false "$(cr_check failing)" "$(cr_check pending)")" "failing"
# A window-lock that is itself SUCCESS is still excluded (exclusion keys off
# name+workflow, not conclusion): only the real lock's workflow matters, so a
# lone green lock is excluded → none, not green.
assert_ci_state "excl: a SUCCESS release-window lock is still excluded (none, not green)" \
  "$(rollup false "$(wl_check '{"workflow":{"name":"release-window"}}' SUCCESS)")" "none"

# REQ-C1.1 — legacy StatusContext (commit-status) mapping, asserted directly on
# the primitive: SUCCESS→green, EXPECTED/PENDING→pending, other→failing; and a
# StatusContext named window-lock is JUDGED (never excluded — it carries no
# workflow), so a red one blocks.
assert_ci_state "statusctx: a SUCCESS commit-status confirms green" \
  "$(rollup false "$(sc_check SUCCESS)")" "green"
assert_ci_state "statusctx: an EXPECTED commit-status is pending" \
  "$(rollup false "$(sc_check SUCCESS)" "$(sc_check EXPECTED)")" "pending"
assert_ci_state "statusctx: a legacy window-lock-named commit-status is judged (failing)" \
  "$(rollup false "$(cr_check green)" "$(sc_check FAILURE window-lock)")" "failing"

# REQ-C1.1 — a malformed / non-JSON rollup fails CLOSED: jq errors, so rl_ci_state
# returns status 2 with empty stdout, NEVER an empty or garbage verdict at rc 0.
# (Drives the `| jq ... || return 2` branch that CI_QUERY_FAIL cannot reach — gh
# there exits nonzero before jq runs.)
CI_QUERY_FAIL=0
CI_ROLLUP_JSON='}{ this is not json'
mj_rc=0
mj_out=$(rl_ci_state deadbeef 2>/dev/null) || mj_rc=$?
CI_ROLLUP_JSON=""
if [ -z "$mj_out" ] && [ "$mj_rc" -eq 2 ]; then
  echo "ok: a malformed (non-JSON) rollup fails closed (status 2, empty stdout), not a spurious verdict"
else
  echo "FAIL: malformed rollup — expected empty stdout + rc 2, got [$mj_out] rc [$mj_rc]" >&2
  failures=$((failures + 1))
fi

# REQ-C1.2 — publish and arm resolve to the SAME verdict for the same SHA because
# both are thin callers of this one primitive; the duplicated inline evaluators
# are removed. Structural single-source check: the statusCheckRollup GraphQL query
# lives ONLY in release-lib.sh. The inline CI-rollup evaluator is keyed by its
# `gh api graphql` call (whitespace-robust: a re-inlined query MUST re-introduce
# that call, whatever its internal spacing — unlike a bare `statusCheckRollup`
# substring which prose also matches). And both callers must genuinely INVOKE the
# primitive — matched by the call form `rl_ci_state "$` (a call with a shell-var
# argument), NOT a bare-name mention that also matches the descriptive comments,
# so deleting a real call cannot pass this check on comment prose alone.
grep_count() { grep -cF "$1" "$2" 2>/dev/null || true; }
PUB="$here/../scripts/release-publish.sh"
ARM="$here/../scripts/release-arm.sh"
LIBSH="$here/../scripts/release-lib.sh"
if [ "$(grep_count 'gh api graphql' "$LIBSH")" -ge 1 ] \
  && [ "$(grep_count 'gh api graphql' "$PUB")" -eq 0 ] \
  && [ "$(grep_count 'gh api graphql' "$ARM")" -eq 0 ]; then
  echo "ok: the statusCheckRollup query lives only in release-lib.sh (inline evaluators removed)"
else
  echo "FAIL: a CI-rollup query (gh api graphql) is duplicated outside release-lib.sh (publish/arm still inline)" >&2
  failures=$((failures + 1))
fi
# `rl_ci_state "$` matches only a real invocation (call + shell-var argument),
# never the comment mentions of the name.
if [ "$(grep_count 'rl_ci_state "$' "$PUB")" -ge 1 ] && [ "$(grep_count 'rl_ci_state "$' "$ARM")" -ge 1 ]; then
  echo "ok: both release-publish.sh and release-arm.sh call rl_ci_state (one verdict source, so the same SHA yields the same verdict — REQ-C1.2)"
else
  echo "FAIL: a caller does not invoke rl_ci_state (verdict sources can drift)" >&2
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "PASS: test-release-lib.sh"
