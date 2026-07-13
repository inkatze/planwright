#!/bin/bash
# Tests for scripts/prompt-eval.sh — the kept prompt-eval runner (prompt-hygiene
# Task 4; REQ-C1.4, REQ-C1.6, REQ-D1.3). The runner drives a skill through
# `claude -p` hermetically and grades pass^k. Here a STUB `claude` (an env
# override, PROMPT_EVAL_CLAUDE) emits deterministic stream-json so every branch
# of the runner's logic — pass^k aggregation, plugin-load verification, budget
# caps, the fail-closed dispositions (R12), teardown, cost capture, and the
# artifact-hygiene scrub (REQ-C1.6) — is exercised without any network, API key,
# or spend. The unstubbed path is Task 4's real baseline run ([manual], D-8).
#
# The stub is directive-driven: STUB_PLAN names a file with one directive per
# claude invocation (ok | fail | budget | noplugin | noresult | badcost); the
# stub advances STUB_COUNTER across invocations so pass^k sequences like
# "run 1 ok, run 2 fail" are expressible. Every fixture input the runner reads is
# treated as data; these fixtures prove the logic, not any live model behavior.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/prompt-eval.sh"

failures=0
assert_exit() {
  # assert_exit <label> <expected> <actual>
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (missing '$2')" >&2
      printf '%s\n' "----- output -----" "$3" "------------------" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_absent() {
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (unexpected '$2')" >&2
      printf '%s\n' "----- output -----" "$3" "------------------" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -f "$RUNNER" ]; then
  echo "FAIL: runner missing at $RUNNER" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- the stub `claude` -------------------------------------------------------
STUB="$TMP/claude-stub.sh"
cat >"$STUB" <<'STUB_EOF'
#!/bin/sh
# Deterministic stub for `claude -p ...`. Reads a per-invocation directive and
# emits stream-json (init + assistant + result). Controlled entirely by env.
set -u
# Drain stdin (the prompt) so the caller's redirect never blocks.
cat >/dev/null 2>&1 || true

n=1
if [ -n "${STUB_COUNTER:-}" ]; then
  [ -f "$STUB_COUNTER" ] && n="$(cat "$STUB_COUNTER")"
  echo "$((n + 1))" >"$STUB_COUNTER"
fi

directive="ok"
if [ -n "${STUB_PLAN:-}" ] && [ -f "$STUB_PLAN" ]; then
  d="$(sed -n "${n}p" "$STUB_PLAN")"
  [ -n "$d" ] && directive="$d"
fi

cost="${STUB_COST:-0.010000}"
sid="11111111-2222-3333-4444-555555555555"

# init event: include planwright unless the directive suppresses it.
if [ "$directive" = "noplugin" ]; then
  printf '{"type":"system","subtype":"init","plugins":[{"name":"other","path":"/x"}],"session_id":"%s"}\n' "$sid"
else
  printf '{"type":"system","subtype":"init","plugins":[{"name":"planwright","path":"/some/path"},{"name":"lsp","path":"/y"}],"session_id":"%s"}\n' "$sid"
fi

# On an ok directive, optionally simulate a side effect (a marker file).
if [ "$directive" = "ok" ] && [ -n "${STUB_MARKER:-}" ]; then
  mkdir -p "$(dirname "$STUB_MARKER")" 2>/dev/null || true
  echo "1700000000" >"$STUB_MARKER" 2>/dev/null || true
fi

result_text="did the thing"
if [ -n "${STUB_LEAK:-}" ]; then
  # Machine-local detail that must NEVER reach the recorded artifact.
  result_text="ran in /Users/secretuser/project session ${sid}"
fi

printf '{"type":"assistant","subtype":null}\n'

case "$directive" in
  noresult)
    : # emit no result line at all
    ;;
  budget)
    printf '{"type":"result","subtype":"error_max_budget_usd","is_error":true,"num_turns":1,"total_cost_usd":%s,"session_id":"%s","result":"%s"}\n' "$cost" "$sid" "$result_text"
    ;;
  badcost)
    printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":"not-a-number","session_id":"%s","result":"%s"}\n' "$sid" "$result_text"
    ;;
  fail)
    printf '{"type":"result","subtype":"success","is_error":true,"num_turns":1,"total_cost_usd":%s,"session_id":"%s","result":"%s"}\n' "$cost" "$sid" "$result_text"
    ;;
  *)
    printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":%s,"session_id":"%s","result":"%s"}\n' "$cost" "$sid" "$result_text"
    ;;
esac
STUB_EOF
chmod +x "$STUB"

export PROMPT_EVAL_CLAUDE="$STUB"
export PROMPT_EVAL_WORKBASE="$TMP/work"

# ---- fixture builder ---------------------------------------------------------
# mk_fixture <name> <assert-jq-body> [extra:setup|probe|conf=...]
mk_fixture() {
  fdir="$TMP/fx/$1"
  mkdir -p "$fdir"
  echo "drive the skill" >"$fdir/prompt.txt"
  printf '%s\n' "$2" >"$fdir/assert.jq"
  echo "$fdir"
}

reset_counter() { echo 1 >"$TMP/counter"; }
export STUB_COUNTER="$TMP/counter"

# ---- 1. pass^3: 3-of-3 ok passes --------------------------------------------
fx="$(mk_fixture ok3 '.is_error == false')"
reset_counter
: >"$TMP/plan"
printf 'ok\nok\nok\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" "$RUNNER" --plugin-dir "$REPO_ROOT" "$fx" 2>&1)"
rc=$?
assert_exit "3-of-3 ok passes pass^3" 0 "$rc"
assert_contains "reports PASS" "PASS (pass^3)" "$out"

# ---- 2. pass^3: 2-of-3 (run 2 fails) fails, early-exits ----------------------
fx="$(mk_fixture fail2 '.is_error == false')"
reset_counter
printf 'ok\nfail\nok\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" "$RUNNER" --plugin-dir "$REPO_ROOT" "$fx" 2>&1)"
rc=$?
assert_exit "2-of-3 fails pass^3" 1 "$rc"
assert_contains "early-exits on the failing run" "run 2/3 FAILED" "$out"
assert_absent "did not run the 3rd run after failure" "run 3/3" "$out"

# ---- 3. budget-cap-hit counts as a failing run (R12) -------------------------
fx="$(mk_fixture budgetcap '.is_error == false')"
reset_counter
printf 'budget\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" "$RUNNER" --plugin-dir "$REPO_ROOT" --k 1 "$fx" 2>&1)"
rc=$?
assert_exit "budget cap hit counts as fail" 1 "$rc"
assert_contains "names the budget-cap disposition" "budget cap hit" "$out"

# ---- 4. plugin not loaded is INVALID (exit 3), not a graded fail -------------
fx="$(mk_fixture noplug '.is_error == false')"
reset_counter
printf 'noplugin\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" "$RUNNER" --plugin-dir "$REPO_ROOT" --k 1 "$fx" 2>&1)"
rc=$?
assert_exit "plugin not loaded is INVALID (exit 3)" 3 "$rc"
assert_contains "names the invalid disposition" "INVALID" "$out"

# ---- 5. missing result line is fail-closed (exit 4) --------------------------
fx="$(mk_fixture nores '.is_error == false')"
reset_counter
printf 'noresult\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" "$RUNNER" --plugin-dir "$REPO_ROOT" --k 1 "$fx" 2>&1)"
rc=$?
assert_exit "missing result is fail-closed (exit 4)" 4 "$rc"
assert_contains "names the missing-result disposition" "no result event" "$out"

# ---- 6. malformed cost is fail-closed (exit 4) -------------------------------
fx="$(mk_fixture badcost '.is_error == false')"
reset_counter
printf 'badcost\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" "$RUNNER" --plugin-dir "$REPO_ROOT" --k 1 "$fx" 2>&1)"
rc=$?
assert_exit "malformed cost is fail-closed (exit 4)" 4 "$rc"
assert_contains "names the cost disposition" "unparseable total_cost_usd" "$out"

# ---- 7. probe.sh + assert.jq grade a filesystem side effect ------------------
# The stub creates a marker file (relative to its CWD = the run's work tree) on
# an ok directive; probe.sh reports whether it landed; assert.jq grades on it.
fx2="$(mk_fixture marker2 '.marker_written == true')"
cat >"$fx2/setup.sh" <<'EOF'
#!/bin/sh
mkdir -p "$1/specs/demo/.orchestrate/markers"
EOF
cat >"$fx2/probe.sh" <<'EOF'
#!/bin/sh
test -f "$1/marker-dropped" && echo '{"marker_written": true}' || echo '{"marker_written": false}'
EOF
# Point STUB_MARKER at a path the stub resolves relative to its CWD (work tree).
reset_counter
printf 'ok\nok\nok\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" STUB_MARKER="marker-dropped" \
  "$RUNNER" --plugin-dir "$REPO_ROOT" "$fx2" 2>&1)"
rc=$?
assert_exit "probe+assert grade a filesystem side effect (pass)" 0 "$rc"

# negative: no marker created -> assert fails
fx3="$(mk_fixture marker3 '.marker_written == true')"
cp "$fx2/probe.sh" "$fx3/probe.sh"
reset_counter
printf 'ok\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" "$RUNNER" --plugin-dir "$REPO_ROOT" --k 1 "$fx3" 2>&1)"
rc=$?
assert_exit "probe+assert grade a missing side effect (fail)" 1 "$rc"

# ---- 8. artifact hygiene: recorded result is scrubbed (REQ-C1.6) -------------
fx="$(mk_fixture record '.is_error == false')"
reset_counter
printf 'ok\nok\nok\n' >"$TMP/plan"
mkdir -p "$TMP/results"
out="$(STUB_PLAN="$TMP/plan" STUB_LEAK=1 STUB_COST="0.030000" \
  "$RUNNER" --plugin-dir "$REPO_ROOT" --record "$TMP/results" "$fx" 2>&1)"
rc=$?
assert_exit "record run passes" 0 "$rc"
artifact="$(cat "$TMP/results/record.json" 2>/dev/null)"
assert_contains "artifact carries the fixture identifier" '"fixture": "record"' "$artifact"
assert_contains "artifact carries the graded outcome" '"outcome": "pass"' "$artifact"
assert_contains "artifact carries cost" '"cost_usd"' "$artifact"
assert_absent "artifact scrubbed of machine-local path" "/Users/secretuser" "$artifact"
assert_absent "artifact scrubbed of username" "secretuser" "$artifact"
assert_absent "artifact scrubbed of session id" "11111111-2222-3333-4444-555555555555" "$artifact"
assert_absent "artifact carries no raw result text" "did the thing" "$artifact"
# only the four allowed top-level keys
keys="$(printf '%s' "$artifact" | jq -r 'keys | join(",")' 2>/dev/null)"
assert_contains "artifact keys are exactly the allowlist" "cost_usd,fixture,outcome,per_run_cost_usd" "$keys"

# ---- 9. suite-level budget ceiling aborts fail-closed (R11) ------------------
fx="$(mk_fixture pricey '.is_error == false')"
reset_counter
printf 'ok\nok\nok\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" STUB_COST="0.500000" \
  "$RUNNER" --plugin-dir "$REPO_ROOT" --suite-budget-usd 0.6 "$fx" 2>&1)"
rc=$?
assert_exit "suite budget ceiling aborts fail-closed (exit 6)" 6 "$rc"
assert_contains "names the suite ceiling" "suite budget ceiling" "$out"

# ---- 10. --k override and default -------------------------------------------
fx="$(mk_fixture k2 '.is_error == false')"
reset_counter
printf 'ok\nok\nok\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" "$RUNNER" --plugin-dir "$REPO_ROOT" --k 2 "$fx" 2>&1)"
rc=$?
assert_exit "--k 2 passes with 2 ok runs" 0 "$rc"
assert_contains "honors k=2" "PASS (pass^2)" "$out"

# ---- 11. --suite runs every fixture under a root -----------------------------
mkdir -p "$TMP/suite"
for name in a b; do
  d="$TMP/suite/$name"
  mkdir -p "$d"
  echo "go" >"$d/prompt.txt"
  echo '.is_error == false' >"$d/assert.jq"
done
reset_counter
printf 'ok\nok\nok\nok\nok\nok\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" "$RUNNER" --plugin-dir "$REPO_ROOT" --suite "$TMP/suite" 2>&1)"
rc=$?
assert_exit "--suite runs every fixture" 0 "$rc"
assert_contains "suite ran fixture a" "[a] PASS" "$out"
assert_contains "suite ran fixture b" "[b] PASS" "$out"

# ---- 12. teardown leaves no work trees behind --------------------------------
leftovers="$(find "$PROMPT_EVAL_WORKBASE" -maxdepth 1 -type d ! -path "$PROMPT_EVAL_WORKBASE" 2>/dev/null | wc -l | tr -d ' ')"
assert_exit "no disposable work trees leaked after teardown" 0 "$leftovers"

# ---- 13. usage errors --------------------------------------------------------
out="$("$RUNNER" 2>&1)"
assert_exit "no fixtures is a usage error" 2 $?
out="$("$RUNNER" --plugin-dir "$REPO_ROOT" --k 0 "$TMP/fx/ok3" 2>&1)"
assert_exit "--k 0 is a usage error" 2 $?

# ---- 14. --plugin-dir that is not a plugin is a usage error (exit 2) ---------
out="$("$RUNNER" --plugin-dir "$TMP" "$TMP/fx/ok3" 2>&1)"
rc=$?
assert_exit "--plugin-dir without plugin.json is a usage error" 2 "$rc"
assert_contains "names the not-a-plugin cause" "not a plugin" "$out"

# ---- 15. multi-fixture run where one fixture fails: exit 1, others still run --
mkdir -p "$TMP/mixed/good1" "$TMP/mixed/bad" "$TMP/mixed/good2"
for n in good1 bad good2; do
  echo "go" >"$TMP/mixed/$n/prompt.txt"
  echo '.is_error == false' >"$TMP/mixed/$n/assert.jq"
done
reset_counter
# Fixtures run in glob (alphabetical) order: bad, good1, good2. Plan: bad
# ok,fail (early-exit, 2 invocations) · good1 ok,ok,ok · good2 ok,ok,ok.
printf 'ok\nfail\nok\nok\nok\nok\nok\nok\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" "$RUNNER" --plugin-dir "$REPO_ROOT" --suite "$TMP/mixed" 2>&1)"
rc=$?
assert_exit "a failing fixture makes the suite exit 1" 1 "$rc"
assert_contains "the failing fixture is reported" "[bad] FAIL" "$out"
assert_contains "a later fixture still runs after an earlier fail" "[good1] PASS" "$out"
assert_contains "the last fixture still runs too" "[good2] PASS" "$out"

# ---- 16. --record per-run cost array has the right length and values ---------
fx="$(mk_fixture costs '.is_error == false')"
reset_counter
printf 'ok\nok\nok\n' >"$TMP/plan"
mkdir -p "$TMP/costres"
out="$(STUB_PLAN="$TMP/plan" STUB_COST="0.020000" \
  "$RUNNER" --plugin-dir "$REPO_ROOT" --record "$TMP/costres" "$fx" 2>&1)"
# jq 1.7+ preserves the number literal, so 0.020000 stays as written.
arr="$(jq -c '.per_run_cost_usd | length' "$TMP/costres/costs.json" 2>/dev/null)"
assert_contains "per-run cost array has all k entries" "3" "$arr"
firstcost="$(jq -r '.per_run_cost_usd[0]' "$TMP/costres/costs.json" 2>/dev/null)"
assert_contains "per-run cost value is the stub cost" "0.02" "$firstcost"
total="$(jq -r '.cost_usd' "$TMP/costres/costs.json" 2>/dev/null)"
assert_contains "total cost sums the runs" "0.06" "$total"

# ---- 17. --expect-plugin-commit: match proceeds, mismatch aborts fail-closed -
head_sha="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)"
fx="$(mk_fixture commitok '.is_error == false')"
reset_counter
printf 'ok\nok\nok\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" \
  "$RUNNER" --plugin-dir "$REPO_ROOT" --expect-plugin-commit "$head_sha" "$fx" 2>&1)"
assert_exit "matching --expect-plugin-commit proceeds" 0 $?
out="$(STUB_PLAN="$TMP/plan" \
  "$RUNNER" --plugin-dir "$REPO_ROOT" --expect-plugin-commit "deadbeefdeadbeef" "$fx" 2>&1)"
rc=$?
assert_exit "mismatching --expect-plugin-commit aborts fail-closed (exit 4)" 4 "$rc"
assert_contains "names the pre-diet-commit binding" "pre-diet commit" "$out"

# ---- 18. setup.sh failure is fail-closed (exit 4) ----------------------------
fx="$(mk_fixture setupfail '.is_error == false')"
cat >"$fx/setup.sh" <<'EOF'
#!/bin/sh
echo "seed exploded" >&2
exit 1
EOF
reset_counter
printf 'ok\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" "$RUNNER" --plugin-dir "$REPO_ROOT" --k 1 "$fx" 2>&1)"
rc=$?
assert_exit "setup.sh failure is fail-closed (exit 4)" 4 "$rc"
assert_contains "names the setup failure" "setup.sh failed" "$out"

# ---- 19. probe.sh emitting invalid JSON is fail-closed (exit 4), not silent --
fx="$(mk_fixture badprobe '.marker_written == true')"
cat >"$fx/probe.sh" <<'EOF'
#!/bin/sh
echo "this is not json"
EOF
reset_counter
printf 'ok\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" "$RUNNER" --plugin-dir "$REPO_ROOT" --k 1 "$fx" 2>&1)"
rc=$?
assert_exit "invalid probe JSON is fail-closed (exit 4)" 4 "$rc"
assert_contains "names the probe disposition" "probe.sh failed or emitted invalid JSON" "$out"

# ---- 20. probe.sh exiting non-zero is fail-closed (exit 4) -------------------
fx="$(mk_fixture crashprobe '.marker_written == true')"
cat >"$fx/probe.sh" <<'EOF'
#!/bin/sh
echo '{"marker_written": false}'
exit 7
EOF
reset_counter
printf 'ok\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" "$RUNNER" --plugin-dir "$REPO_ROOT" --k 1 "$fx" 2>&1)"
rc=$?
assert_exit "probe non-zero exit is fail-closed (exit 4)" 4 "$rc"

# ---- 21. a broken assert.jq (compile error) is fail-closed, not a graded fail-
fx="$(mk_fixture badassert 'this is (not valid jq')"
reset_counter
printf 'ok\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" "$RUNNER" --plugin-dir "$REPO_ROOT" --k 1 "$fx" 2>&1)"
rc=$?
assert_exit "broken assert.jq is fail-closed (exit 4), not a graded fail" 4 "$rc"
assert_contains "names the assert.jq error" "assert.jq error" "$out"

# ---- 22. a zero-byte prompt.txt is a usage error (exit 2) --------------------
fx="$TMP/fx/emptyprompt"
mkdir -p "$fx"
: >"$fx/prompt.txt"
echo '.is_error == false' >"$fx/assert.jq"
out="$("$RUNNER" --plugin-dir "$REPO_ROOT" --k 1 "$fx" 2>&1)"
rc=$?
assert_exit "empty prompt.txt is a usage error (exit 2)" 2 "$rc"

# ---- 23. a scientific-notation cost is parsed, not mis-aborted ----------------
fx="$(mk_fixture scicost '.is_error == false')"
reset_counter
printf 'ok\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" STUB_COST="5E-7" \
  "$RUNNER" --plugin-dir "$REPO_ROOT" --k 1 "$fx" 2>&1)"
rc=$?
assert_exit "scientific-notation cost parses (not fail-closed)" 0 "$rc"

# ---- 24. artifact-hygiene scrubber catches machine-local leaks ---------------
# The recorded artifact is built by allowlist from scalars, so a leak can only
# arise from a future edit that widens the allowlist. Guard that backstop by
# exercising the runner's OWN pattern (extracted here so the test cannot drift
# from the script): every common home/temp root plus a session UUID in either
# case must be caught, and benign artifact content must not false-positive.
scrub_re="$(sed -n "s/^machine_local_re='\(.*\)'\$/\1/p" "$RUNNER")"
assert_contains "scrubber pattern is defined in the runner" "private/var" "$scrub_re"
scrub_hits() { printf '%s' "$1" | grep -Eqi "$scrub_re"; }
for leak in \
  "/Users/diego/x" "/home/diego/x" "/root/x" "/opt/x" "/private/var/folders/xy/z" \
  "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE" "11111111-2222-3333-4444-555555555555"; do
  if scrub_hits "$leak"; then
    echo "ok: scrubber catches machine-local leak '$leak'"
  else
    echo "FAIL: scrubber missed machine-local leak '$leak'" >&2
    failures=$((failures + 1))
  fi
done
for clean in \
  '{"fixture":"orchestrate-print-ready","outcome":"pass","cost_usd":0.06}' \
  "0.020000" "pass"; do
  if scrub_hits "$clean"; then
    echo "FAIL: scrubber false-positived on benign content '$clean'" >&2
    failures=$((failures + 1))
  else
    echo "ok: scrubber passes benign content '$clean'"
  fi
done

# ---- 25. a failing probe's stderr is surfaced for debuggability --------------
fx="$(mk_fixture noisyprobe '.marker_written == true')"
cat >"$fx/probe.sh" <<'EOF'
#!/bin/sh
echo "probe diagnostic: could not find the branch" >&2
echo "not valid json either"
exit 3
EOF
reset_counter
printf 'ok\n' >"$TMP/plan"
out="$(STUB_PLAN="$TMP/plan" "$RUNNER" --plugin-dir "$REPO_ROOT" --k 1 "$fx" 2>&1)"
rc=$?
assert_exit "noisy failing probe is fail-closed (exit 4)" 4 "$rc"
assert_contains "surfaces the probe.sh stderr header" "probe.sh stderr:" "$out"
assert_contains "surfaces the probe's diagnostic message" \
  "probe diagnostic: could not find the branch" "$out"

# ---- 26. --help prints only the comment header, no leaked code lines ---------
# print_help slices the header comment block out of the script; an off-by-one in
# the line range leaks the first line(s) of actual code (`set -u`, `LC_ALL=C`)
# into the usage output. Assert the help text stays within the comment block.
out="$("$RUNNER" --help 2>&1)"
rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help shows the usage synopsis" "Usage:" "$out"
assert_absent "--help does not leak the 'set -u' code line" "set -u" "$out"
assert_absent "--help does not leak the 'LC_ALL=C' code line" "LC_ALL=C" "$out"

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed" >&2
  exit 1
fi
echo "all prompt-eval runner tests passed"
