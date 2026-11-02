#!/bin/bash
# Tests for scripts/substrate-bakeoff.sh — the bake-off harness and its
# report self-test (universal-binary REQ-B1.5, REQ-C1.1, REQ-C1.4, REQ-C1.5,
# REQ-C1.6, REQ-G1.3).
#
# Runs the committed stub bake-off (one full candidate, one comparison
# point) and a hook-tier copy of it, then tampers with the produced reports in
# the ways the validator must reject. Run-time refusals, failure values and
# isolation are in tests/test-substrate-bakeoff-runs.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-substrate-bakeoff.sh
# shellcheck disable=SC2016 # expected Markdown carries literal backticks
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
SB="$REPO_ROOT/scripts/substrate-bakeoff.sh"
STUB="$REPO_ROOT/tests/fixtures/substrate-bakeoff/stub"

failures=0
ok() { echo "ok: $1"; }
bad() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
check_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi
}
check_has() {
  case "$2" in
    *"$3"*) ok "$1" ;;
    *) bad "$1 (missing [$3] in: $2)" ;;
  esac
}

[ -x "$SB" ] || {
  echo "FAIL: scripts/substrate-bakeoff.sh missing or not executable" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-substrate-bakeoff.XXXXXX") || exit 1
[ -n "$tmp" ] && [ -d "$tmp" ] || exit 1
trap 'rm -rf "$tmp"' EXIT

# get <report> <candidate> <field>
get() {
  awk -F '\t' -v c="$2" -v f="$3" 'NR == 1 { for (i = 1; i <= NF; i++) k[$i] = i; next } $k["candidate"] == c { print $k[f] }' "$1"
}
# set_field <report> <candidate> <field> <value> <out>
set_field() {
  awk -F '\t' -v OFS='\t' -v c="$2" -v f="$3" -v v="$4" 'NR == 1 { for (i = 1; i <= NF; i++) k[$i] = i; print; next } $k["candidate"] == c { $k[f] = v } { print }' "$1" >"$5"
}
# drop_column <report> <field> <out>
drop_column() {
  awk -F '\t' -v OFS='\t' -v f="$2" 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == f) d = i } { s = ""; n = 0; for (i = 1; i <= NF; i++) if (i != d) s = s (n++ ? "\t" : "") $i; print s }' "$1" >"$3"
}
variant() {
  rm -rf "${tmp:?}/$1"
  cp -R "$STUB" "$tmp/$1"
}
run_into() {
  rm -rf "$tmp/out-$1"
  mkdir "$tmp/out-$1"
  out=$("$SB" run --bakeoff "$2" --out-dir "$tmp/out-$1" --run-id "run-$1" --platform test 2>&1)
  rc=$?
}

# --- the stub bake-off: one command, the full report and the view ----------

run_into stub "$STUB"
check_eq "the stub run succeeds" 0 "$rc"
R=$tmp/out-stub/report.tsv
if [ -s "$R" ]; then ok "the report is written"; else bad "the report is written"; fi
if [ -s "$tmp/out-stub/view.md" ]; then ok "the view is written"; else bad "the view is written"; fi
check_eq "one row per candidate" 3 "$(awk 'END { print NR }' "$R")"
check_eq "full: both fixtures passed" 2 "$(get "$R" stub-full tests_passed)"
check_eq "full: none failed" 0 "$(get "$R" stub-full tests_failed)"
check_eq "full: every fixture executed" 2 "$(get "$R" stub-full fixtures_executed)"
check_eq "full: per-fixture results" "echo-line/basic:pass,echo-line/empty:pass" "$(get "$R" stub-full fixture_results)"
check_eq "full: one spawn per invocation (cat through PATH)" 1 "$(get "$R" stub-full spawns_per_invocation)"
check_eq "full: one distinct external command" 1 "$(get "$R" stub-full distinct_commands)"
check_eq "full: a shell candidate's dependencies are its spawned commands" 1 "$(get "$R" stub-full dependency_count)"
check_eq "full: the dependency listing names them" "cat,system,-,-" "$(get "$R" stub-full dependency_listing)"
check_eq "full: a one-word executable invocation is a literal path" yes "$(get "$R" stub-full literal_path)"
check_eq "full: the call site replays offline" yes "$(get "$R" stub-full offline_replay)"
bytes=$(wc -c <"$STUB/candidates/stub-full/bin/echo-line" | tr -d ' ')
check_eq "full: source bytes" "$bytes" "$(get "$R" stub-full source_bytes)"
check_eq "full: implementation minutes from the log" 90.0 "$(get "$R" stub-full implementation_minutes)"
check_eq "full: review runs" 1 "$(get "$R" stub-full review_runs)"
check_eq "full: review findings" 3 "$(get "$R" stub-full review_findings)"
check_eq "full: a single convergence run is unqualified" unqualified "$(get "$R" stub-full review_qualification)"
want=$(awk -v b="$bytes" 'BEGIN { printf "%.3f %.3f\n", 3 / (b / 1024), 90 / (b / 1024) }')
check_eq "full: findings per KiB and porting rate" "$want" "$(get "$R" stub-full review_findings_per_kib) $(get "$R" stub-full porting_rate_min_per_kib)"
case $(get "$R" stub-full latency_median_ms) in [0-9]*.[0-9][0-9][0-9]) ok "full: a latency median in ms" ;; *) bad "full: a latency median in ms" ;; esac
case $(get "$R" stub-full latency_spread_ms) in [0-9]*.[0-9][0-9][0-9]) ok "full: a latency spread in ms" ;; *) bad "full: a latency spread in ms" ;; esac
check_eq "full: both delivery modes" "pass pass" "$(get "$R" stub-full delivery_marketplace) $(get "$R" stub-full delivery_writer)"
check_eq "full: platform result" pass "$(get "$R" stub-full platform_result)"
check_eq "full: no trivial-program field" - "$(get "$R" stub-full cold_start_median_ms)"
check_eq "comparison: the trivial program passes" pass "$(get "$R" stub-comparison trivial_result)"
size=$(wc -c <"$STUB/candidates/stub-comparison/bin/hello" | tr -d ' ')
check_eq "comparison: binary size" "$size" "$(get "$R" stub-comparison binary_size_bytes)"
check_eq "comparison: dependencies from its listing" "1 stub-runtime,MIT,2026-01-01,none" "$(get "$R" stub-comparison dependency_count) $(get "$R" stub-comparison dependency_listing)"
for f in tests_passed fixture_results implementation_minutes latency_median_ms literal_path; do
  check_eq "comparison: no primitive field $f" - "$(get "$R" stub-comparison "$f")"
done
for c in stub-full stub-comparison; do
  check_eq "$c: the run id in the row" run-stub "$(get "$R" "$c" run_id)"
  check_eq "$c: the timeout in the row" 10 "$(get "$R" "$c" timeout_s)"
done
"$SB" validate "$R" >/dev/null 2>&1
check_eq "the produced report validates" 0 "$?"
V=$(cat "$tmp/out-stub/view.md")
check_has "view: full candidates first" "$V" "## Full candidates"
check_has "view: comparison points" "$V" "## Comparison points"
check_has "view: the full field set behind" "$V" "## Every field"
check_has "view: the run named" "$V" 'Run `run-stub` on `test`'
rendered=$("$SB" render "$R" 2>&1)
check_eq "render reproduces the view" "$V" "$rendered"

# Two runs on the same stubs carry the same schema and field set (REQ-C1.5).
run_into again "$STUB"
check_eq "a second run succeeds" 0 "$rc"
check_eq "both runs share the header" "$(head -1 "$R")" "$(head -1 "$tmp/out-again/report.tsv")"
fieldset() { awk -F '\t' 'NR > 1 { s = $8 ":"; for (i = 1; i <= NF; i++) s = s ($i == "-" ? "-" : "v"); print s }' "$1"; }
check_eq "both runs fill the same fields" "$(fieldset "$R")" "$(fieldset "$tmp/out-again/report.tsv")"

# --- the self-test rejections over the report ------------------------------

reject() { # <label> <report> <expected message part>
  out=$("$SB" validate "$2" 2>&1)
  rc=$?
  check_eq "$1: rejected" 1 "$rc"
  check_has "$1: names the defect" "$out" "$3"
}

drop_column "$R" implementation_minutes "$tmp/r1"
reject "a report missing a schema field" "$tmp/r1" 'the schema needs "implementation_minutes"'
set_field "$R" stub-full review_findings - "$tmp/r2"
reject "a full row missing a log field" "$tmp/r2" "the full class requires review_findings"
set_field "$R" stub-full implementation_minutes - "$tmp/r2b"
reject "a full row missing the implementation time" "$tmp/r2b" "the full class requires implementation_minutes"
set_field "$R" stub-comparison binary_size_bytes - "$tmp/r3"
reject "a comparison row missing a trivial-program field" "$tmp/r3" "the comparison class requires binary_size_bytes"
set_field "$R" stub-comparison tests_passed 2 "$tmp/r4"
reject "a comparison row carrying a primitive field" "$tmp/r4" "a comparison point carries the primitive field tests_passed"
set_field "$R" stub-full fixtures_executed 1 "$tmp/r5"
reject "a run that did not execute every fixture" "$tmp/r5" "executed 1 of the 2 production differential fixtures"
set_field "$R" stub-full fixture_results echo-line/basic:pass "$tmp/r6"
reject "per-fixture results short of the set" "$tmp/r6" "fixture_results records 1 of the 2"
set_field "$R" stub-full run_id other "$tmp/r7"
reject "rows from two runs" "$tmp/r7" "differs from the first row"
set_field "$R" stub-full review_qualification qualified "$tmp/r8"
reject "a single run recorded as qualified" "$tmp/r8" "review_qualification must be unqualified"
set_field "$R" stub-full fixture_results echo-line/basic:pass,echo-line/basic:pass "$tmp/r11"
reject "a repeated per-fixture result" "$tmp/r11" "fixture_results repeats echo-line/basic"
set_field "$R" stub-full fixture_results echo-line/basic:pass,echo-line/empty:fail "$tmp/r12"
reject "per-fixture results disagreeing with the counts" "$tmp/r12" "fixture_results records 1 passing fixtures, tests_passed 2"
awk -F '\t' -v OFS='\t' 'NR == 1 { for (i = 1; i <= NF; i++) k[$i] = i; print; next } { $k["runs"] = 0; print }' "$R" >"$tmp/r13"
reject "a run count below one" "$tmp/r13" "run field runs is not a whole number of at least one"
set_field "$R" stub-full review_runs 0 "$tmp/r14"
reject "a review run count below one" "$tmp/r14" "review_runs is not a whole number of at least one"
set_field "$R" stub-full baseline_run_id run-stub "$tmp/r10a"
set_field "$tmp/r10a" stub-full hook_budget within "$tmp/r10"
reject "a budget without the shell latency columns" "$tmp/r10" "hook_budget is set exactly when the shell latency columns are"
awk -F '\t' -v OFS='\t' '{ print $0, (NR == 1 ? "later_field" : "x") }' "$R" >"$tmp/r9"
"$SB" validate "$tmp/r9" >/dev/null 2>&1
check_eq "an appended field keeps the report valid (add-only)" 0 "$?"

# --- the hook tier: shell and candidate latency from one run ---------------

variant hook
sed 's/^tier=library$/tier=hook/' "$STUB/bakeoff.conf" >"$tmp/hook/bakeoff.conf"
cp -R "$tmp/hook/candidates/stub-full" "$tmp/hook/candidates/shell"
printf 'shell\t2026-10-01T09:00:00Z\t2026-10-01T09:30:00Z\n' >>"$tmp/hook/implementation-time.tsv"
printf 'shell\t1\t0\n' >>"$tmp/hook/review-findings.tsv"
run_into hook "$tmp/hook"
check_eq "a hook-tier run succeeds" 0 "$rc"
H=$tmp/out-hook/report.tsv
check_eq "hook: the baseline run is this run" run-hook "$(get "$H" stub-full baseline_run_id)"
check_eq "hook: the baseline median is the shell row's" "$(get "$H" shell latency_median_ms)" "$(get "$H" stub-full baseline_latency_median_ms)"
check_eq "hook: the baseline spread is the shell row's" "$(get "$H" shell latency_spread_ms)" "$(get "$H" stub-full baseline_latency_spread_ms)"
case $(get "$H" stub-full hook_budget) in within | over) ok "hook: the budget judged" ;; *) bad "hook: the budget judged" ;; esac
check_eq "hook: a comparison point has no baseline" - "$(get "$H" stub-comparison baseline_run_id)"
set_field "$H" stub-full baseline_run_id other-run "$tmp/h1"
reject "a hook report whose shell latency comes from another run" "$tmp/h1" "carry run other-run"
set_field "$H" stub-full baseline_latency_median_ms - "$tmp/h2"
reject "a hook report missing the shell latency columns" "$tmp/h2" "needs the shell latency columns"
drop_column "$H" baseline_latency_spread_ms "$tmp/h3"
reject "a hook report without the shell spread column" "$tmp/h3" 'the schema needs "baseline_latency_spread_ms"'
set_field "$R" stub-full tier hook "$tmp/h4"
set_field "$tmp/h4" stub-comparison tier hook "$tmp/h5"
reject "a hook report with no shell row" "$tmp/h5" "needs the shell candidate"

# --- more validator rejections ---------------------------------------------

awk -F '\t' -v OFS='\t' 'NR == 2 { $0 = $0 "\textra" } { print }' "$R" >"$tmp/v1"
reject "a row with a different field count" "$tmp/v1" "fields, the header"
set_field "$R" stub-full schema other "$tmp/v2"
reject "a foreign schema name" "$tmp/v2" "schema is not substrate-bakeoff"
awk 'NR == 3 { print; sub(/stub-full/, "stub-full") } { print }' "$R" >"$tmp/v3"
reject "a candidate appearing twice" "$tmp/v3" "candidate appears twice"
set_field "$R" stub-full source_bytes many "$tmp/v4"
reject "a non-numeric numeric field" "$tmp/v4" "source_bytes is not a number"
set_field "$R" stub-full dependency_count 1.5 "$tmp/v4b"
reject "a fractional count field" "$tmp/v4b" "dependency_count is not a whole number"
set_field "$R" stub-comparison binary_size_bytes 10.5 "$tmp/v4c"
reject "a fractional comparison count field" "$tmp/v4c" "binary_size_bytes is not a whole number"
set_field "$R" stub-full fixture_results "echo-line/basic:ok,echo-line/empty:pass" "$tmp/v5"
reject "a malformed per-fixture entry" "$tmp/v5" "is not <primitive>/<case>:pass|fail"
set_field "$R" stub-full tests_failed 1 "$tmp/v6"
reject "pass and fail counts that do not add up" "$tmp/v6" "tests_passed plus tests_failed"
set_field "$R" stub-full literal_path maybe "$tmp/v7"
reject "a literal-path value other than yes or no" "$tmp/v7" "literal_path and offline_replay are yes or no"
set_field "$R" stub-full class partial "$tmp/v8"
reject "an unknown class" "$tmp/v8" "not full or comparison"
set_field "$R" stub-full delivery_writer maybe "$tmp/v9"
reject "a delivery value other than pass or fail" "$tmp/v9" "delivery_writer is pass or fail"
set_field "$R" stub-full tier weekly "$tmp/v10a"
set_field "$tmp/v10a" stub-comparison tier weekly "$tmp/v10"
reject "an unknown tier" "$tmp/v10" "tier is not hook"
set_field "$R" stub-comparison trivial_result maybe "$tmp/v11"
reject "a trivial result other than pass or fail" "$tmp/v11" "trivial_result is pass or fail"
set_field "$H" stub-full hook_budget fast "$tmp/v12"
reject "a hook budget other than within or over" "$tmp/v12" "hook_budget is within or over"
set_field "$H" stub-full hook_budget over "$tmp/v12b"
if [ "$(get "$H" stub-full hook_budget)" = over ]; then set_field "$H" stub-full hook_budget within "$tmp/v12b"; fi
reject "a hook budget that does not follow from the latencies" "$tmp/v12b" "does not follow from its median"
set_field "$R" stub-full hook_budget within "$tmp/v12c"
reject "a hook budget with no shell baseline" "$tmp/v12c" "set exactly when the shell latency columns are"
set_field "$H" stub-full baseline_latency_median_ms 999.999 "$tmp/v13"
reject "shell latency columns that differ from the shell row" "$tmp/v13" "differ from the shell row"
set_field "$H" stub-full latency_median_ms - "$tmp/v14"
reject "a hook report missing the candidate latency" "$tmp/v14" "the full class requires latency_median_ms"
drop_column "$R" tier "$tmp/v15"
out=$("$SB" validate "$tmp/v15" 2>&1)
case $out in *"no candidate row"*) bad "a header failure reports only the header" ;; *) ok "a header failure reports only the header" ;; esac

view=$("$SB" render "$tmp/r1" 2>/dev/null)
check_eq "render refuses an invalid report" 1 "$?"
check_eq "render prints no view of an invalid report" "" "$view"
if [ "$failures" -gt 0 ]; then
  echo "test-substrate-bakeoff: $failures failure(s)" >&2
  exit 1
fi
echo "test-substrate-bakeoff: all passed"
