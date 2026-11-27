#!/bin/bash
# Tests for scripts/ci-reuse.sh and the ci.yml steps that call it: a ready
# flip reuses a prior run's suite jobs only when that run tested the same
# head, the same base and the same workflow file, with every suite job
# (the Linux test shards, the Alpine shards, the macOS shards and the macOS
# smoke) succeeded. Anything else runs every job.
#
# The plan job's lookup step, its mac step and the check job's gate step are
# read out of the real ci.yml and run here, against a stub gh serving fixture
# run, artifact and job lists, so the wiring under test is the workflow's own.
# No case reaches the real Actions API.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
# shellcheck source=tests/lib/hermetic-env.sh
. "$REPO_ROOT/tests/lib/hermetic-env.sh"
SCRIPT="$REPO_ROOT/scripts/ci-reuse.sh"
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"

failures=0
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (missing '$2' in: $3)" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_lacks() {
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (unexpected '$2' in: $3)" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-ci-reuse.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

# --- a stub gh -------------------------------------------------------------
# It answers `gh api <path>` from $STUB_DIR: the run list from runs.json, a
# run's artifacts from artifacts-<id>.json and its jobs from jobs-<id>.json.
# A missing file, or STUB_FAIL=1, is a failed call; STUB_SLEEP holds it.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_DIR/calls"
[ -z "${STUB_SLEEP:-}" ] || sleep "$STUB_SLEEP"
[ "${STUB_FAIL:-}" != 1 ] || { echo "gh: HTTP 502" >&2; exit 1; }
[ "$1" = api ] || exit 1
case $2 in
  */actions/workflows/*/runs\?*) f=runs.json ;;
  */actions/runs/*/artifacts\?*) f=${2#*/actions/runs/}; f=artifacts-${f%%/*}.json ;;
  */actions/runs/*/jobs\?*) f=${2#*/actions/runs/}; f=jobs-${f%%/*}.json ;;
  *) exit 1 ;;
esac
[ -f "$STUB_DIR/$f" ] || { echo "gh: HTTP 404" >&2; exit 1; }
cat "$STUB_DIR/$f"
EOF
chmod +x "$tmp/bin/gh"

HEAD_SHA=1111111111111111111111111111111111111111
BASE_SHA=2222222222222222222222222222222222222222
BLOB_SHA=3333333333333333333333333333333333333333
OTHER=4444444444444444444444444444444444444444
EVIDENCE="ci-evidence-$BASE_SHA-$HEAD_SHA-$BLOB_SHA"
SELF=5000

# run_json <id> <head> <conclusion> [created] [path]: one run-list entry.
run_json() {
  printf '{"id":%s,"event":"pull_request","status":"completed","conclusion":"%s","head_sha":"%s","path":"%s","created_at":"%s"}' \
    "$1" "$3" "$2" "${5:-.github/workflows/ci.yml}" "${4:-2026-11-14T10:00:00Z}"
}
write_runs() { # write_runs <entry>...: the run list
  _r=""
  for _e in "$@"; do _r="${_r:+$_r,}$_e"; done
  printf '{"total_count":%s,"workflow_runs":[%s]}' "$#" "$_r" >"$STUB_DIR/runs.json"
}
write_artifacts() { # write_artifacts <id> <name>...: that run's artifact list
  _id=$1
  shift
  _a=""
  for _n in "$@"; do _a="${_a:+$_a,}{\"name\":\"$_n\",\"expired\":false}"; done
  printf '{"total_count":%s,"artifacts":[%s]}' "$#" "$_a" >"$STUB_DIR/artifacts-$_id.json"
}
job() { printf '{"name":"%s","status":"completed","conclusion":"%s"}' "$1" "$2"; }
# jobs_with [<name>=<conclusion>|<name>=-]...: every job of a full run, each
# succeeded unless an argument gives its name another conclusion or drops it.
jobs_with() {
  _names="lint plan"
  for _i in 1 2 3; do _names="$_names|test (shard $_i/3)|alpine-suite (shard $_i/3)"; done
  for _i in 1 2 3 4; do _names="$_names|macos-suite (shard $_i/4)"; done
  _names="$_names|macos-smoke|alpine-smoke|check"
  _j=""
  _ifs=$IFS
  IFS='|'
  for _n in $_names; do
    IFS=$_ifs
    _c=success
    for _o in "$@"; do
      [ "${_o%=*}" = "$_n" ] && _c=${_o##*=}
    done
    [ "$_c" = - ] || _j="${_j:+$_j,}$(job "$_n" "$_c")"
    IFS='|'
  done
  IFS=$_ifs
  for _o in "$@"; do
    case $_o in
      +*) _j="$_j,$(job "${_o#+}" skipped)" ;;
    esac
  done
  printf '%s' "$_j"
}
write_jobs() { # write_jobs <id> <entries>: that run's job list
  printf '{"total_count":%s,"jobs":[%s]}' "$(printf '[%s]' "$2" | jq length)" "$2" >"$STUB_DIR/jobs-$1.json"
}

new_case() {
  STUB_DIR="$tmp/case-$1"
  mkdir -p "$STUB_DIR"
  : >"$STUB_DIR/calls"
  export STUB_DIR
}

# --- reading the real workflow's steps -------------------------------------
# step_body <id>: the `run: |` body of the step whose first line is
# `      - id: <id>`, dedented, as GitHub hands it to the shell. The indents
# are ci.yml's own; a re-indent empties the body, which fails below.
step_body() {
  awk -v id="$1" '
    $0 == "      - id: " id { in_step = 1; next }
    in_step && /^      - / { exit }
    in_step && /^  [a-z]/ { exit }
    in_step && $0 == "        run: |" { in_run = 1; next }
    in_run {
      if ($0 != "" && $0 !~ /^          /) exit
      print substr($0, 11)
    }
  ' "$CI_YML"
}
for s in reuse mac gate; do
  step_body "$s" >"$tmp/step-$s.sh"
  [ -s "$tmp/step-$s.sh" ] || {
    echo "FAIL: ci.yml has no \`- id: $s\` step with a \`run: |\` body" >&2
    failures=$((failures + 1))
  }
done

# run_lookup <event> <action> [evidence]: run the plan job's reuse step from
# the repository root, as the checkout leaves it; its outputs land in
# $out_file.
run_lookup() {
  out_file="$STUB_DIR/output"
  : >"$out_file"
  (
    cd "$REPO_ROOT" || exit 1
    PATH="$tmp/bin:$PATH" EVENT="$1" ACTION="$2" EVIDENCE="${3-$EVIDENCE}" \
      GITHUB_REPOSITORY=acme/widgets GITHUB_RUN_ID=$SELF GH_TOKEN=fixture \
      GITHUB_OUTPUT="$out_file" bash -e "$tmp/step-reuse.sh"
  ) >"$STUB_DIR/log" 2>&1
  lookup_rc=$?
}
output() { sed -n "s/^$1=//p" "$out_file"; }

# mac_step [REUSE_RUN] [DRAFT]: the plan job's mac step, by default for a
# ready pull request.
mac_step() {
  : >"$STUB_DIR/mac-output"
  EVENT=pull_request DRAFT="${2:-false}" LABELLED=false HEAD_REPO=acme/widgets \
    SWITCH=self-hosted REUSE_RUN="${1:-}" GITHUB_REPOSITORY=acme/widgets \
    GITHUB_OUTPUT="$STUB_DIR/mac-output" GITHUB_STEP_SUMMARY="$STUB_DIR/summary" \
    bash -e "$tmp/step-mac.sh" >"$STUB_DIR/mac-log" 2>&1
  mac_rc=$?
}

# gate <REUSE_RUN> <MAC_RUN> <test> <alpine> <macos-suite> <macos-smoke>
# [<alpine-smoke>]: the check job's gate step, lint and plan succeeded unless
# GATE_LINT or GATE_PLAN says otherwise; the Alpine smoke takes the Alpine
# suite's result unless given its own.
gate() {
  LINT_RESULT="${GATE_LINT-success}" PLAN_RESULT="${GATE_PLAN-success}" REUSE_RUN="$1" MAC_RUN="$2" \
    TEST_RESULT="$3" ALPINE_RESULT="$4" MACOS_RESULT="$5" MACOS_SMOKE_RESULT="$6" \
    ALPINE_SMOKE_RESULT="${7-$4}" \
    GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=acme/widgets \
    GITHUB_STEP_SUMMARY="$STUB_DIR/gate-summary" \
    bash -e "$tmp/step-gate.sh" >"$STUB_DIR/gate-log" 2>&1
  gate_rc=$?
}

# A fully green prior run with this run's evidence.
green_prior() {
  write_runs "$(run_json 900 "$HEAD_SHA" success)"
  write_artifacts 900 timing-report-1 "$EVIDENCE"
  write_jobs 900 "$(jobs_with)"
}

# ---------------------------------------------------------------------------
# The skip row: a ready flip with a fully green prior run on the same
# evidence skips every suite job, and the gate passes naming that run.
# ---------------------------------------------------------------------------
new_case skip
green_prior
run_lookup pull_request ready_for_review
assert_eq "skip: the lookup step succeeds" 0 "$lookup_rc"
assert_eq "skip: the lookup names the prior run" 900 "$(output reuse_run)"
assert_eq "skip: the suite jobs do not run" false "$(output suite_run)"
mac_step "$(output reuse_run)"
assert_eq "skip: the mac step succeeds" 0 "$mac_rc"
assert_contains "skip: the macOS jobs do not run" "run=false" "$(cat "$STUB_DIR/mac-output")"
assert_contains "skip: the mac step names the reused run" 900 "$(cat "$STUB_DIR/mac-log")"
gate 900 false skipped skipped skipped skipped
assert_eq "skip: the gate passes on the reused evidence" 0 "$gate_rc"
assert_contains "skip: the gate names the reused run" "actions/runs/900" "$(cat "$STUB_DIR/gate-log")"
assert_contains "skip: the gate's summary names the reused run" "actions/runs/900" "$(cat "$STUB_DIR/gate-summary" 2>/dev/null)"

# A reused run never covers a suite job that ran, and stands only on every
# suite job skipped.
gate 900 false failure skipped skipped skipped
assert_eq "skip: a failed test job still fails the gate" 1 "$gate_rc"
gate 900 false skipped failure skipped skipped
assert_eq "skip: a failed Alpine job still fails the gate" 1 "$gate_rc"
gate 900 false skipped skipped failure skipped
assert_eq "skip: a failed macOS suite still fails the gate" 1 "$gate_rc"
gate 900 false skipped skipped skipped failure
assert_eq "skip: a failed macOS smoke still fails the gate" 1 "$gate_rc"
gate 900 false skipped skipped success success
assert_eq "skip: a partial skip does not stand on the reused run" 1 "$gate_rc"
gate 900 false skipped skipped skipped skipped failure
assert_eq "skip: a failed Alpine smoke still fails the gate" 1 "$gate_rc"
gate 900 false skipped skipped skipped skipped success
assert_eq "skip: an Alpine smoke that ran does not stand on the reused run" 1 "$gate_rc"
# Without a reused run, a skipped Linux or Alpine suite job fails the gate.
gate "" false skipped skipped skipped skipped
assert_eq "no reuse: every suite job skipped fails the gate" 1 "$gate_rc"
gate "" false skipped success skipped skipped
assert_eq "no reuse: a skipped test job fails the gate" 1 "$gate_rc"
gate "" false success skipped skipped skipped
assert_eq "no reuse: a skipped Alpine job fails the gate" 1 "$gate_rc"
gate "" false success success skipped skipped skipped
assert_eq "no reuse: a skipped Alpine smoke fails the gate" 1 "$gate_rc"
gate "" true success success skipped skipped
assert_eq "no reuse: a skipped macOS job the plan meant to run fails the gate" 1 "$gate_rc"
gate "" true success success success success
assert_eq "no reuse: every job green passes the gate" 0 "$gate_rc"
assert_lacks "no reuse: the gate names no reused run" "actions/runs/" "$(cat "$STUB_DIR/gate-log")"
gate "" false success success skipped skipped
assert_eq "no reuse: a draft's macOS skip still passes the gate" 0 "$gate_rc"

# The newest qualifying run wins; one that does not qualify is passed over.
new_case newest
write_runs "$(run_json 902 "$HEAD_SHA" success 2026-11-14T12:00:00Z)" "$(run_json 901 "$HEAD_SHA" success 2026-11-14T11:00:00Z)"
write_artifacts 902 "ci-evidence-$OTHER-$HEAD_SHA-$BLOB_SHA"
write_jobs 902 "$(jobs_with)"
write_artifacts 901 "$EVIDENCE"
write_jobs 901 "$(jobs_with)"
run_lookup pull_request ready_for_review
assert_eq "newest: a run on another base is passed over for an older match" 901 "$(output reuse_run)"

new_case artifacts-failed-then-match
write_runs "$(run_json 902 "$HEAD_SHA" success 2026-11-14T12:00:00Z)" "$(run_json 901 "$HEAD_SHA" success 2026-11-14T11:00:00Z)"
write_artifacts 901 "$EVIDENCE"
write_jobs 901 "$(jobs_with)"
run_lookup pull_request ready_for_review
assert_eq "a run whose artifact read fails is passed over for an older match" 901 "$(output reuse_run)"

# However many newer runs fail to qualify (each skipped run re-reads its
# head), the match behind them is still found.
new_case many
entries=""
for i in 1 2 3 4 5 6 7; do
  entries="$entries $(run_json "91$i" "$HEAD_SHA" success "2026-11-14T1$i:00:00Z")"
  write_artifacts "91$i" "$EVIDENCE"
  write_jobs "91$i" "$(jobs_with "macos-smoke=skipped")"
done
write_jobs 911 "$(jobs_with)"
# shellcheck disable=SC2086 # one run-list entry per word
write_runs $entries
run_lookup pull_request ready_for_review
assert_eq "many: the oldest run is reached past six that do not qualify" 911 "$(output reuse_run)"

new_case bad-budget
green_prior
PLANWRIGHT_CI_REUSE_BUDGET=1m run_lookup pull_request ready_for_review
assert_eq "a malformed budget leaves the lookup step green" 0 "$lookup_rc"
assert_eq "a malformed budget falls back to the default and still reuses" 900 "$(output reuse_run)"

# ---------------------------------------------------------------------------
# Every other shape runs everything: reuse_run empty, suite_run true.
# ---------------------------------------------------------------------------
assert_no_reuse() { # assert_no_reuse <label>: the outputs, then the mac step on them
  assert_eq "$1: the lookup step succeeds" 0 "$lookup_rc"
  assert_eq "$1: no run is reused" "" "$(output reuse_run)"
  assert_eq "$1: the suite jobs run" true "$(output suite_run)"
  mac_step "$(output reuse_run)"
  assert_contains "$1: the macOS jobs run" "run=true" "$(cat "$STUB_DIR/mac-output")"
}

new_case other-head
write_runs "$(run_json 900 "$OTHER" success)"
write_artifacts 900 "ci-evidence-$BASE_SHA-$OTHER-$BLOB_SHA"
write_jobs 900 "$(jobs_with)"
run_lookup pull_request ready_for_review
assert_no_reuse "a different head"

new_case other-head-same-name
green_prior
write_runs "$(run_json 900 "$OTHER" success)"
run_lookup pull_request ready_for_review
assert_no_reuse "a run at another head carrying this run's evidence name"

new_case other-workflow
green_prior
write_runs "$(run_json 900 "$HEAD_SHA" success 2026-11-14T10:00:00Z .github/workflows/other.yml)"
run_lookup pull_request ready_for_review
assert_no_reuse "a run of another workflow file"

new_case moved-base
green_prior
write_artifacts 900 timing-report-1 "ci-evidence-$OTHER-$HEAD_SHA-$BLOB_SHA"
run_lookup pull_request ready_for_review
assert_no_reuse "a moved base"

new_case changed-workflow
green_prior
write_artifacts 900 "ci-evidence-$BASE_SHA-$HEAD_SHA-$OTHER"
run_lookup pull_request ready_for_review
assert_no_reuse "a changed workflow"

new_case no-evidence
green_prior
write_artifacts 900 timing-report-1
run_lookup pull_request ready_for_review
assert_no_reuse "a prior run with no evidence artifact"

new_case artifacts-truncated
green_prior
printf '{"total_count":120,"artifacts":[{"name":"%s","expired":false}]}' "$EVIDENCE" >"$STUB_DIR/artifacts-900.json"
run_lookup pull_request ready_for_review
assert_no_reuse "a truncated artifact list"

# shellcheck disable=SC2016 # the literal name GitHub reports for a skipped matrix job
unexpanded='macos-suite (shard ${{ matrix.shard }}/${{ strategy.job-total }})'
new_case mac-skipped
green_prior
write_jobs 900 "$(jobs_with "macos-suite (shard 1/4)=-" "macos-suite (shard 2/4)=-" \
  "macos-suite (shard 3/4)=-" "macos-suite (shard 4/4)=-" "macos-smoke=skipped" "+$unexpanded")"
run_lookup pull_request ready_for_review
assert_no_reuse "a prior run with macOS skipped"

new_case mac-suite-skipped-smoke-green
green_prior
write_jobs 900 "$(jobs_with "macos-suite (shard 1/4)=-" "macos-suite (shard 2/4)=-" \
  "macos-suite (shard 3/4)=-" "macos-suite (shard 4/4)=-" "+$unexpanded")"
run_lookup pull_request ready_for_review
assert_no_reuse "a prior run with the macOS shards skipped and the smoke green"

new_case mac-shard-red
green_prior
write_jobs 900 "$(jobs_with "macos-suite (shard 2/4)=failure")"
run_lookup pull_request ready_for_review
assert_no_reuse "a prior run with a failed macOS shard"

new_case mac-shard-missing
green_prior
write_jobs 900 "$(jobs_with "macos-suite (shard 4/4)=-")"
run_lookup pull_request ready_for_review
assert_no_reuse "a prior run missing a macOS shard"

new_case smoke-skipped
green_prior
write_jobs 900 "$(jobs_with "macos-smoke=skipped")"
run_lookup pull_request ready_for_review
assert_no_reuse "a prior run with only the macOS smoke skipped"

new_case alpine-smoke-skipped
green_prior
write_jobs 900 "$(jobs_with "alpine-smoke=skipped")"
run_lookup pull_request ready_for_review
assert_no_reuse "a prior run with only the Alpine smoke skipped"

new_case alpine-smoke-red
green_prior
write_jobs 900 "$(jobs_with "alpine-smoke=failure")"
run_lookup pull_request ready_for_review
assert_no_reuse "a prior run whose Alpine smoke failed"

# Every run from before the smoke had its own job.
new_case alpine-smoke-missing
green_prior
write_jobs 900 "$(jobs_with "alpine-smoke=-")"
run_lookup pull_request ready_for_review
assert_no_reuse "a prior run with no Alpine smoke job"

new_case missing-shard
green_prior
write_jobs 900 "$(jobs_with "test (shard 2/3)=-")"
run_lookup pull_request ready_for_review
assert_no_reuse "a prior run missing a test shard"

new_case shard-counts
green_prior
write_jobs 900 "$(jobs_with "test (shard 3/3)=-"),$(job "test (shard 3/4)" success)"
run_lookup pull_request ready_for_review
assert_no_reuse "a prior run whose test shards disagree on their count"

new_case alpine-red
green_prior
write_jobs 900 "$(jobs_with "alpine-suite (shard 3/3)=failure")"
run_lookup pull_request ready_for_review
assert_no_reuse "a prior run with a failed Alpine shard"

new_case red
green_prior
write_runs "$(run_json 900 "$HEAD_SHA" failure)"
run_lookup pull_request ready_for_review
assert_no_reuse "a prior red run"

new_case cancelled
green_prior
write_runs "$(run_json 900 "$HEAD_SHA" cancelled)"
run_lookup pull_request ready_for_review
assert_no_reuse "a prior cancelled run"

new_case self
green_prior
write_runs "$(run_json $SELF "$HEAD_SHA" success)"
write_artifacts $SELF "$EVIDENCE"
write_jobs $SELF "$(jobs_with)"
run_lookup pull_request ready_for_review
assert_no_reuse "the current run itself"

new_case lookup-failed
green_prior
STUB_FAIL=1 run_lookup pull_request ready_for_review
assert_no_reuse "a failed run lookup"

new_case jobs-failed
green_prior
rm -f "$STUB_DIR/jobs-900.json"
run_lookup pull_request ready_for_review
assert_no_reuse "a failed job lookup"

new_case garbled
green_prior
printf 'not json' >"$STUB_DIR/runs.json"
run_lookup pull_request ready_for_review
assert_no_reuse "an unreadable run list"

new_case truncated
green_prior
printf '{"total_count":120,"jobs":[%s]}' "$(jobs_with)" >"$STUB_DIR/jobs-900.json"
run_lookup pull_request ready_for_review
assert_no_reuse "a truncated job list"

new_case timeout
green_prior
SECONDS=0
STUB_SLEEP=20 PLANWRIGHT_CI_REUSE_BUDGET=1 run_lookup pull_request ready_for_review
elapsed=$SECONDS
assert_no_reuse "a lookup past its time budget"
timeout_rc=1
[ "$elapsed" -lt 15 ] && timeout_rc=0
assert_eq "a lookup past its time budget is cut short (${elapsed}s)" 0 "$timeout_rc"

new_case empty-evidence
green_prior
run_lookup pull_request ready_for_review ""
assert_no_reuse "a run with no evidence of its own"
assert_eq "a run with no evidence of its own reads nothing" "" "$(cat "$STUB_DIR/calls")"

# A non-ready_for_review event is unchanged: no lookup, every job runs.
for ev in "pull_request synchronize" "pull_request opened" "pull_request labeled" "push "; do
  new_case "event-${ev% *}-${ev#* }"
  green_prior
  # shellcheck disable=SC2086 # the event and its action, word-split on purpose
  run_lookup ${ev% *} "${ev#* }"
  assert_no_reuse "a ${ev% *} ${ev#* } event"
  assert_eq "a ${ev% *} ${ev#* } event reads nothing" "" "$(cat "$STUB_DIR/calls")"
done
new_case draft
mac_step "" true
assert_contains "a draft without the label still skips macOS" "run=false" "$(cat "$STUB_DIR/mac-output")"

# ---------------------------------------------------------------------------
# A superseded run. A newer run on the same ref cancels this one, so every job
# still waiting on its needs ends cancelled. The check job must end that way
# too rather than run and fail beside the live run, while a need that failed
# or timed out (a timeout reads as cancelled in `needs`) in a run nobody
# cancelled still fails it.
# ---------------------------------------------------------------------------
# check_job_if: the check job's own `if:`, as ci.yml writes it.
check_job_if() {
  awk '
    $0 == "  check:" { in_job = 1; next }
    in_job && /^  [a-z]/ { exit }
    in_job && /^    if: / { sub(/^    if: /, ""); print; exit }
  ' "$CI_YML"
}
# check_outcome <job if> <run cancelled> <lint> <plan> <test> <alpine>
# <macos-suite> <macos-smoke>: the check job's conclusion. A job whose `if:`
# is false when its run is cancelled ends cancelled, as the waiting jobs of a
# cancelled run do; one that runs takes its gate step's result.
check_outcome() {
  case "$1:$2" in
    "\${{ always() }}:"*) ;;
    "\${{ !cancelled() }}:false") ;;
    "\${{ !cancelled() }}:true")
      echo cancelled
      return
      ;;
    *)
      echo "unmodelled if: $1"
      return
      ;;
  esac
  GATE_LINT="$3" GATE_PLAN="$4" gate "" true "$5" "$6" "$7" "$8"
  if [ "$gate_rc" -eq 0 ]; then echo success; else echo failure; fi
}
CHECK_IF="$(check_job_if)"
# shellcheck disable=SC2016 # literal GitHub expressions
OLD_IF='${{ always() }}'
superseded="true cancelled cancelled cancelled cancelled cancelled cancelled"
# shellcheck disable=SC2086 # the case's results, one word each
{
  assert_eq "superseded: under always() the check job runs and fails beside the live run" \
    failure "$(check_outcome "$OLD_IF" $superseded)"
  assert_eq "superseded: ci.yml's check job ends cancelled, not red" \
    cancelled "$(check_outcome "$CHECK_IF" $superseded)"
}
for job_if in "$OLD_IF" "$CHECK_IF"; do
  assert_eq "live run under $job_if: a failed test job fails the check" \
    failure "$(check_outcome "$job_if" false success success failure success success success)"
  assert_eq "live run under $job_if: a timed-out test job fails the check" \
    failure "$(check_outcome "$job_if" false success success cancelled success success success)"
  assert_eq "live run under $job_if: a cancelled plan fails the check" \
    failure "$(check_outcome "$job_if" false success cancelled skipped skipped skipped skipped)"
  assert_eq "live run under $job_if: every job green passes the check" \
    success "$(check_outcome "$job_if" false success success success success success success)"
done

# ---------------------------------------------------------------------------
# The workflow's own wiring around those steps.
# ---------------------------------------------------------------------------
# The jobs the reuse step names are exactly the jobs the plan's suite_run or
# mac_run verdict can skip, so a suite job added later cannot be skipped
# without the lookup requiring it green.
gated=$(awk '
  /^  [a-z][a-z0-9-]*:$/ { j = substr($0, 3, length($0) - 3) }
  /^    if: \$\{\{ needs\.plan\.outputs\.(suite_run|mac_run) == .true. \}\}$/ { print j }
' "$CI_YML" | sort | tr '\n' ' ')
named=$(tr ' ' '\n' <"$tmp/step-reuse.sh" | awk 'f { print; f = 0 } /^--(matrix-)?job$/ { f = 1 }' | sort | tr '\n' ' ')
assert_eq "the reuse step names every job the plan can skip" "alpine-smoke alpine-suite macos-smoke macos-suite test " "$gated"
assert_eq "the reuse step requires exactly those jobs" "$gated" "$named"
# shellcheck disable=SC2016 # literal GitHub expressions
{
  grep -qF 'reuse_run: ${{ steps.reuse.outputs.reuse_run }}' "$CI_YML"
  assert_eq "the plan job exports the reused run" 0 $?
  grep -qF 'suite_run: ${{ steps.reuse.outputs.suite_run }}' "$CI_YML"
  assert_eq "the plan job exports the suite verdict" 0 $?
  grep -qF 'evidence: ${{ steps.evidence.outputs.name }}' "$CI_YML"
  assert_eq "the plan job exports its evidence name" 0 $?
  grep -qF 'REUSE_RUN: ${{ needs.plan.outputs.reuse_run }}' "$CI_YML"
  assert_eq "the check job reads the reused run" 0 $?
  grep -qF 'REUSE_RUN: ${{ steps.reuse.outputs.reuse_run }}' "$CI_YML"
  assert_eq "the mac step reads the reused run" 0 $?
  grep -qF 'name: ${{ needs.plan.outputs.evidence }}' "$CI_YML"
  assert_eq "the evidence job uploads under the evidence name" 0 $?
}
# Every step of the check job after the gate (the timing gate's checkout,
# download and run) runs only without a reused run.
check_steps=$(awk '
  /^  check:$/ { in_job = 1; next }
  in_job && /^  [a-z]/ { exit }
  in_job && /^      - / { n++; first = 1 }
  in_job && n > 1 && first { first = 0; total++; if ($0 ~ /needs\.plan\.outputs\.reuse_run == .. /) gated++ }
  END { printf "%d/%d", gated, total }
' "$CI_YML")
assert_eq "the check job's steps after the gate skip on a reused run" "3/3" "$check_steps"

# ---------------------------------------------------------------------------
# The evidence verb, on a real merge commit and a shallow clone of it.
# ---------------------------------------------------------------------------
repo="$tmp/repo"
g() { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$repo" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
mkdir -p "$repo"
g init -q -b main
mkdir -p "$repo/.github/workflows"
printf 'name: ci\n' >"$repo/.github/workflows/ci.yml"
g add . && g commit -q -m base
g checkout -q -b topic
printf 'x\n' >"$repo/x" && g add x && g commit -q -m head
head=$(g rev-parse HEAD)
g checkout -q main
printf 'y\n' >"$repo/y" && g add y && g commit -q -m moved
base=$(g rev-parse HEAD)
g merge -q --no-ff --no-edit topic
blob=$(g rev-parse HEAD:.github/workflows/ci.yml)
out=$(cd "$repo" && /bin/sh "$SCRIPT" evidence --head "$head" 2>&1)
assert_eq "evidence: the merge commit's base, head and workflow blob" "ci-evidence-$base-$head-$blob" "$out"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git clone -q --depth 1 "file://$repo" "$tmp/shallow"
out=$(cd "$tmp/shallow" && /bin/sh "$SCRIPT" evidence --head "$head" 2>&1)
assert_eq "evidence: a depth-1 clone, as actions/checkout leaves it, names the same" "ci-evidence-$base-$head-$blob" "$out"
(cd "$repo" && /bin/sh "$SCRIPT" evidence --head "$base" >/dev/null 2>&1)
assert_eq "evidence: a head that is not the merge's second parent is refused" 1 $?
g checkout -q topic
(cd "$repo" && /bin/sh "$SCRIPT" evidence --head "$head" >/dev/null 2>&1)
assert_eq "evidence: a commit that is not a merge is refused" 1 $?

/bin/sh "$SCRIPT" lookup --repo acme/widgets >/dev/null 2>&1
assert_eq "lookup: a missing argument is a usage error" 2 $?
/bin/sh "$SCRIPT" nonsense >/dev/null 2>&1
assert_eq "an unknown verb is a usage error" 2 $?

if [ "$failures" -gt 0 ]; then
  echo "test-ci-reuse: $failures failure(s)" >&2
  exit 1
fi
echo "test-ci-reuse: all passed"
