#!/bin/sh
# prompt-eval.sh — the kept prompt-eval runner (prompt-hygiene Task 4; REQ-C1.4,
# REQ-C1.6, REQ-D1.3; D-6, D-7, D-8, D-12). A dependency-free POSIX-sh harness
# that drives a skill headlessly through `claude -p`, hermetically via
# `--bare --plugin-dir`, verifies the plugin loaded from the `system/init` event
# before grading, grades observable outcomes with jq, and gates pass^k (all of k
# runs pass). It is on-demand only — never wired into `mise run check` or CI
# (D-8; scripts/check-no-ci-evals.sh enforces that).
#
# Isolation & re-runnability (risk R8): each run gets a uniquely-named disposable
# working tree; stale trees for the fixture are pruned before a run so a crashed
# prior run cannot poison a re-run; `--bare` skips the project's hooks so an eval
# never fires tasks-pr-sync against a real checkout; teardown removes the tree
# and a teardown failure is surfaced fail-closed, never swallowed. A baseline can
# be bound to a specific pre-diet commit with --expect-plugin-commit.
# Known limitation: the prune-first reaps EVERY tree for the fixture id, so a
# single runner invocation per fixture is assumed. Two concurrent runs of the
# SAME fixture are unsupported — the second's prune would reap the first's
# in-flight tree. The on-demand runner never does this; it is a deliberate
# tradeoff (crash-recovery pruning over concurrency safety), not a defect.
#
# Bounded cost (risk R11): per-run caps (--max-budget-usd, --max-turns) plus a
# suite-level ceiling (--suite-budget-usd) that aborts fail-closed once crossed;
# pass^k early-exits on the first failing run, so a doomed fixture never burns
# its remaining runs.
#
# Fail-closed eval-side dispositions (risk R12, the analogue of the guard's
# fail-loud): a run that never loaded the plugin is INVALID (exit 3), not a
# graded failure; a budget-cap-hit run counts as a failing run in the pass^k
# tally; a missing result line or an unparseable / non-numeric cost aborts
# fail-closed (exit 4); a teardown or prune failure aborts fail-closed (exit 5);
# crossing the suite ceiling aborts fail-closed (exit 6). Nothing is ever
# silently treated as a pass.
#
# Artifact hygiene (REQ-C1.6): a recorded result carries the fixture identifier,
# the graded outcome, and cost — and nothing more. It is built by allowlist from
# scalars only (no transcript text, no paths, no session ids ever enter it) and
# then re-verified to contain only the allowed keys and no machine-local
# substring before it is written.
#
# Usage:
#   prompt-eval.sh [options] <fixture-dir> [<fixture-dir>...]
#   prompt-eval.sh [options] --suite <fixtures-root>
# Options:
#   --plugin-dir <path>          plugin pinned via --bare --plugin-dir
#                                (default: this repo root — the code under diet)
#   --k <n>                      runs per fixture for pass^k (default 3;
#                                a fixture.conf `k` overrides per fixture)
#   --record <dir>               write a scrubbed <id>.json result per fixture
#   --suite <root>               run every immediate subdir of <root> as a fixture
#   --suite-budget-usd <amt>     abort once cumulative cost crosses <amt>
#   --expect-plugin-commit <sha> require the plugin dir's HEAD to equal <sha>
#   -h, --help                   this help
#
# Test seams (env): PROMPT_EVAL_CLAUDE overrides the `claude` binary;
# PROMPT_EVAL_WORKBASE overrides the disposable-tree base dir.
#
# Exit: 0 every fixture passed pass^k; 1 a fixture graded fail; 2 usage; 3 an
# invalid run (plugin not loaded); 4 fail-closed harness error (missing result /
# bad cost); 5 teardown/prune failure; 6 suite ceiling exceeded.
#
# Portable POSIX sh + jq + git; bash 3.2 / BSD tooling. No eval; every fixture
# input is treated as data. C locale pinned for stable matching.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"

CLAUDE_BIN="${PROMPT_EVAL_CLAUDE:-claude}"
WORKBASE="${PROMPT_EVAL_WORKBASE:-${TMPDIR:-/tmp}/planwright-prompt-eval}"

plugin_dir="$REPO_ROOT"
default_k=3
record_dir=""
suite_root=""
suite_budget=""
expect_commit=""

die_usage() {
  echo "prompt-eval: $1" >&2
  echo "run 'prompt-eval.sh --help' for usage" >&2
  exit 2
}

print_help() {
  sed -n '2,63p' "$0" | sed 's/^# \{0,1\}//'
}

# ---- argument parsing --------------------------------------------------------
fixtures=""
while [ $# -gt 0 ]; do
  case "$1" in
    --plugin-dir)
      [ $# -ge 2 ] || die_usage "--plugin-dir needs a value"
      plugin_dir="$2"
      shift 2
      ;;
    --k)
      [ $# -ge 2 ] || die_usage "--k needs a value"
      case "$2" in
        '' | *[!0-9]*) die_usage "--k must be a positive integer" ;;
      esac
      [ "$2" -ge 1 ] || die_usage "--k must be >= 1"
      default_k="$2"
      shift 2
      ;;
    --record)
      [ $# -ge 2 ] || die_usage "--record needs a value"
      record_dir="$2"
      shift 2
      ;;
    --suite)
      [ $# -ge 2 ] || die_usage "--suite needs a value"
      suite_root="$2"
      shift 2
      ;;
    --suite-budget-usd)
      [ $# -ge 2 ] || die_usage "--suite-budget-usd needs a value"
      suite_budget="$2"
      shift 2
      ;;
    --expect-plugin-commit)
      [ $# -ge 2 ] || die_usage "--expect-plugin-commit needs a value"
      expect_commit="$2"
      shift 2
      ;;
    -h | --help)
      print_help
      exit 0
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do
        fixtures="$fixtures$1
"
        shift
      done
      ;;
    -*)
      die_usage "unknown option: $1"
      ;;
    *)
      fixtures="$fixtures$1
"
      shift
      ;;
  esac
done

if [ -n "$suite_root" ]; then
  [ -d "$suite_root" ] || die_usage "suite root not a directory: $suite_root"
  for d in "$suite_root"/*/; do
    [ -d "$d" ] || continue
    fixtures="$fixtures${d%/}
"
  done
fi

[ -n "$fixtures" ] || die_usage "no fixtures given (pass a fixture dir or --suite)"

# ---- environment checks ------------------------------------------------------
command -v jq >/dev/null 2>&1 || {
  echo "prompt-eval: jq is required but not on PATH" >&2
  exit 4
}

[ -f "$plugin_dir/.claude-plugin/plugin.json" ] || {
  echo "prompt-eval: --plugin-dir '$plugin_dir' is not a plugin (no .claude-plugin/plugin.json)" >&2
  exit 2
}
plugin_dir="$(cd "$plugin_dir" && pwd)"
# A fixture's setup.sh / probe.sh may need the plugin's own scripts (e.g.
# spec-anchor.sh to seed a gate-valid bundle); hand them the resolved path.
export PROMPT_EVAL_PLUGIN_DIR="$plugin_dir"

if [ -n "$expect_commit" ]; then
  head_sha="$(git -C "$plugin_dir" rev-parse HEAD 2>/dev/null || true)"
  if [ "$head_sha" != "$expect_commit" ]; then
    echo "prompt-eval: plugin dir HEAD '$head_sha' != expected '$expect_commit'" >&2
    echo "the baseline must be captured against the pre-diet commit (R8)" >&2
    exit 4
  fi
fi

if [ -n "$record_dir" ]; then
  mkdir -p "$record_dir" || {
    echo "prompt-eval: cannot create record dir '$record_dir'" >&2
    exit 5
  }
fi

mkdir -p "$WORKBASE" || {
  echo "prompt-eval: cannot create work base '$WORKBASE'" >&2
  exit 5
}

# ---- helpers -----------------------------------------------------------------

# read_conf <fixture-dir> <key> — echo the value of an allowlisted key from
# fixture.conf, or nothing. Parsed as data: split on first '=', no sourcing.
read_conf() {
  cf="$1/fixture.conf"
  [ -f "$cf" ] || return 0
  while IFS= read -r rawline || [ -n "$rawline" ]; do
    case "$rawline" in
      '' | '#'*) continue ;;
    esac
    key="${rawline%%=*}"
    val="${rawline#*=}"
    [ "$key" = "$2" ] && printf '%s' "$val" && return 0
  done <"$cf"
  return 0
}

# is_number <str> — true for a non-negative integer or decimal, with an optional
# exponent. The exponent form matters: jq renders a `total_cost_usd` below 1e-6
# in scientific notation (e.g. "5E-7"), which a bare `[0-9.]` test would reject
# and mis-abort as an unparseable cost. Rejects a lone "." and multi-dot input.
is_number() {
  printf '%s' "$1" | grep -Eq '^[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$'
}

# machine_local_re — the artifact-hygiene leak pattern (used case-insensitively,
# grep -Eqi, so an upper-hex session UUID cannot slip past). Covers the common
# absolute home/temp roots (/Users, /home, /root, /opt, and macOS's /private/var)
# plus the session-id UUID shape. Defense in depth: the artifact is already built
# by allowlist from scalars, so nothing machine-local should reach this check at
# all — it is the backstop for a future edit that widens the allowlist.
machine_local_re='/(Users|home|root|opt)/|/private/var/|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

# cumulative suite cost (integer micro-dollars, to avoid float arithmetic in sh)
suite_micros=0
budget_micros=""
if [ -n "$suite_budget" ]; then
  is_number "$suite_budget" || die_usage "--suite-budget-usd must be a number"
  # The budget is the ceiling itself, so floor it: the effective cap must never
  # sit ABOVE the value the operator asked for. A sub-micro budget floors to 0,
  # which — with run costs rounded up (see to_micros) — still fires on the first
  # real spend. The awk truncation ("%d" of a float) is that floor.
  budget_micros="$(printf '%s' "$suite_budget" | awk '{printf "%d", $1 * 1000000}')"
fi

# to_micros <decimal-usd> — dollars to integer micro-dollars, rounded UP. Costs
# feed a spend ceiling, so rounding up is fail-closed: a run below 1e-6 (which
# is_number deliberately accepts, jq renders it as e.g. 5E-7) must count as at
# least 1 micro rather than truncate to 0 and vanish from the totals / budget.
# The 1e-9 epsilon absorbs float noise (v*1e6 landing at N.0000000001) so a value
# that is already an exact integer number of micros is not spuriously bumped up.
to_micros() {
  printf '%s' "$1" | awk '{v = $1 * 1000000; c = int(v); if (v - c > 1e-9) c++; printf "%d", c}'
}

overall_rc=0
note_fail() { [ "$overall_rc" -eq 0 ] && overall_rc=1; }

# Interrupt-safe cleanup (R8 re-runnability): a run in flight tracks its work
# tree so an INT/TERM/normal EXIT never leaves it (or its transcript) behind.
# The per-fixture prune-first is the crash-recovery backstop; this is the clean
# path. Cleared after each teardown so a stale path is never re-removed.
current_work=""
# shellcheck disable=SC2329  # invoked indirectly via the traps below
cleanup() {
  [ -n "$current_work" ] && rm -rf "$current_work" "$current_work.jsonl" 2>/dev/null
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# ---- per-fixture evaluation --------------------------------------------------
run_fixture() {
  fx_dir="$1"
  [ -d "$fx_dir" ] || {
    echo "prompt-eval: fixture dir not found: $fx_dir" >&2
    return 2
  }

  fx_id="$(read_conf "$fx_dir" id)"
  [ -n "$fx_id" ] || fx_id="$(basename "$fx_dir")"
  case "$fx_id" in
    '' | *[!a-zA-Z0-9._-]*)
      echo "prompt-eval: fixture id '$fx_id' has unsafe characters" >&2
      return 2
      ;;
  esac

  # A zero-byte prompt.txt would invoke the skill with no scenario and then
  # grade the empty run as a skill failure — a fixture-authoring defect, not a
  # skill result. Require it non-empty (usage error, not a graded fail).
  [ -s "$fx_dir/prompt.txt" ] || {
    echo "prompt-eval: fixture '$fx_id' has a missing or empty prompt.txt" >&2
    return 2
  }
  [ -f "$fx_dir/assert.jq" ] || {
    echo "prompt-eval: fixture '$fx_id' has no assert.jq" >&2
    return 2
  }

  k="$(read_conf "$fx_dir" k)"
  case "$k" in
    '' | *[!0-9]*) k="$default_k" ;;
  esac
  [ "$k" -ge 1 ] || k="$default_k"

  max_budget="$(read_conf "$fx_dir" max_budget_usd)"
  is_number "$max_budget" || max_budget="0.50"
  max_turns="$(read_conf "$fx_dir" max_turns)"
  case "$max_turns" in
    '' | *[!0-9]*) max_turns="30" ;;
  esac

  # Prune-first (R8): clear any stale disposable trees for this fixture id.
  for stale in "$WORKBASE/$fx_id".*; do
    [ -e "$stale" ] || continue
    rm -rf "$stale" 2>/dev/null || {
      echo "prompt-eval: cannot prune stale tree '$stale'" >&2
      return 5
    }
  done

  fx_pass=1
  fx_micros=0
  per_run_costs=""
  run=1
  while [ "$run" -le "$k" ]; do
    work="$WORKBASE/$fx_id.$$.$run"
    raw="$WORKBASE/$fx_id.$$.$run.jsonl"
    rm -rf "$work"
    mkdir -p "$work" || {
      echo "prompt-eval: cannot create work tree '$work'" >&2
      return 5
    }
    current_work="$work" # armed for the interrupt-safe cleanup trap

    if [ -f "$fx_dir/setup.sh" ]; then
      # Capture setup.sh stderr rather than discarding it: a failing seed is a
      # fixture-authoring error, and its diagnostics are what the human needs to
      # fix it. Terminal-only, never recorded, so artifact hygiene is unaffected
      # (mirrors the probe.sh handling below). stdout stays discarded as noise.
      setup_err="$work.setup-err"
      if ! (cd "$work" && sh "$fx_dir/setup.sh" "$work") >/dev/null 2>"$setup_err"; then
        echo "prompt-eval: [$fx_id run $run] setup.sh failed" >&2
        if [ -s "$setup_err" ]; then
          echo "prompt-eval: [$fx_id run $run] setup.sh stderr:" >&2
          sed 's/^/  /' "$setup_err" >&2
        fi
        rm -rf "$work" "$raw" "$setup_err"
        return 4
      fi
      rm -f "$setup_err"
    fi

    # The graded run: headless, hermetic, budget-capped. Failures of the binary
    # itself surface below as a missing/invalid transcript, not a crash here.
    (cd "$work" && "$CLAUDE_BIN" -p \
      --bare --plugin-dir "$plugin_dir" \
      --output-format stream-json --verbose \
      --max-budget-usd "$max_budget" --max-turns "$max_turns") \
      <"$fx_dir/prompt.txt" >"$raw" 2>/dev/null || true

    # Plugin-load verification (doctrine): a run that never loaded the plugin is
    # INVALID — the harness/env is broken, not the skill. Abort, do not grade.
    init="$(jq -c 'select(.type=="system" and .subtype=="init")' "$raw" 2>/dev/null | head -n1)"
    loaded="false"
    [ -n "$init" ] && loaded="$(printf '%s' "$init" | jq -r 'any(.plugins[]?; .name=="planwright") // false' 2>/dev/null)"
    if [ "$loaded" != "true" ]; then
      echo "prompt-eval: [$fx_id run $run] INVALID — planwright plugin not loaded from system/init" >&2
      rm -rf "$work" "$raw"
      return 3
    fi

    # Result line + cost. Missing result or non-numeric cost is fail-closed.
    result="$(jq -c 'select(.type=="result")' "$raw" 2>/dev/null | tail -n1)"
    if [ -z "$result" ]; then
      echo "prompt-eval: [$fx_id run $run] fail-closed — no result event in transcript" >&2
      rm -rf "$work" "$raw"
      return 4
    fi
    cost="$(printf '%s' "$result" | jq -r '.total_cost_usd // empty' 2>/dev/null)"
    if ! is_number "$cost"; then
      echo "prompt-eval: [$fx_id run $run] fail-closed — missing/unparseable total_cost_usd" >&2
      rm -rf "$work" "$raw"
      return 4
    fi

    run_micros="$(to_micros "$cost")"
    fx_micros=$((fx_micros + run_micros))
    suite_micros=$((suite_micros + run_micros))
    per_run_costs="$per_run_costs$cost
"

    # Suite ceiling (R11): abort fail-closed once cumulative cost crosses it.
    if [ -n "$budget_micros" ] && [ "$suite_micros" -gt "$budget_micros" ]; then
      echo "prompt-eval: [$fx_id run $run] suite budget ceiling \$$suite_budget exceeded" >&2
      rm -rf "$work" "$raw"
      return 6
    fi

    subtype="$(printf '%s' "$result" | jq -r '.subtype // ""' 2>/dev/null)"

    run_pass=0
    if [ "$subtype" = "error_max_budget_usd" ]; then
      # Budget-cap-hit (R12): the run could not complete → a failing run.
      echo "prompt-eval: [$fx_id run $run] budget cap hit (\$$max_budget) — counts as a fail" >&2
      run_pass=1
    else
      # Filesystem/side-effect probe (optional), merged into the outcome jq sees.
      # A probe that exits non-zero or emits non-JSON is a harness/authoring
      # error, not a "no side effect" result: fail-closed (R12), never silently
      # degrade to {} — that would spuriously fail a positive assert or, worse,
      # silently pass a `not`-style absence assert on a probe that never ran.
      probe="{}"
      if [ -f "$fx_dir/probe.sh" ]; then
        # Capture the probe's stderr rather than discarding it: a failing probe
        # is a fixture-authoring error, and its diagnostics are what the human
        # needs to fix it. The capture goes to the operator's terminal only,
        # never to the recorded artifact, so it does not weaken artifact hygiene.
        probe_err="$work.probe-err"
        if probe_out="$(cd "$work" && sh "$fx_dir/probe.sh" "$work" 2>"$probe_err")" \
          && printf '%s' "$probe_out" | jq -e . >/dev/null 2>&1; then
          probe="$probe_out"
          rm -f "$probe_err"
        else
          echo "prompt-eval: [$fx_id run $run] fail-closed — probe.sh failed or emitted invalid JSON" >&2
          if [ -s "$probe_err" ]; then
            echo "prompt-eval: [$fx_id run $run] probe.sh stderr:" >&2
            sed 's/^/  /' "$probe_err" >&2
          fi
          rm -rf "$work" "$raw" "$probe_err"
          current_work=""
          return 4
        fi
      fi
      base="$(printf '%s' "$result" | jq -c '{is_error, subtype, result, num_turns, plugin_loaded: true, cost_usd: .total_cost_usd}' 2>/dev/null)"
      outcome="$(jq -cn --argjson b "$base" --argjson p "$probe" '$b + $p' 2>/dev/null)"
      if [ -z "$outcome" ]; then
        echo "prompt-eval: [$fx_id run $run] fail-closed — could not build the outcome to grade" >&2
        rm -rf "$work" "$raw"
        current_work=""
        return 4
      fi
      # Grade, distinguishing a genuine false (graded fail) from a broken
      # assert.jq. jq -e exits 0 (truthy → pass), 1 (false or null → graded
      # fail), 2 (usage), 3 (compile error), 4 (valid program but no output), or
      # 5 (runtime error). A grading assert MUST yield a boolean verdict, so
      # everything but 0/1 is a harness/authoring error → fail-closed (R12), not
      # silently a graded fail. Exit 4 (empty output) lands here deliberately: a
      # select-style assert that yields nothing has no verdict to grade.
      printf '%s' "$outcome" | jq -e -f "$fx_dir/assert.jq" >/dev/null 2>&1
      grade_rc=$?
      case "$grade_rc" in
        0) run_pass=0 ;;
        1) run_pass=1 ;;
        *)
          echo "prompt-eval: [$fx_id run $run] fail-closed — assert.jq error (jq exit $grade_rc)" >&2
          rm -rf "$work" "$raw"
          current_work=""
          return 4
          ;;
      esac
    fi

    # Teardown (R8): remove the tree; a teardown failure is a re-runnability
    # hazard and is surfaced fail-closed.
    if ! rm -rf "$work" "$raw"; then
      echo "prompt-eval: [$fx_id run $run] fail-closed — teardown failed for '$work'" >&2
      return 5
    fi
    current_work="" # disarmed: the tree is gone

    if [ "$run_pass" -ne 0 ]; then
      fx_pass=0
      echo "prompt-eval: [$fx_id] run $run/$k FAILED — pass^$k not met, early-exit" >&2
      break
    fi
    echo "prompt-eval: [$fx_id] run $run/$k passed (cost \$$cost)"
    run=$((run + 1))
  done

  fx_cost="$(printf '%s' "$fx_micros" | awk '{printf "%.6f", $1 / 1000000}')"
  if [ "$fx_pass" -eq 1 ]; then
    outcome_label="pass"
    echo "prompt-eval: [$fx_id] PASS (pass^$k) — total cost \$$fx_cost"
  else
    outcome_label="fail"
    note_fail
    echo "prompt-eval: [$fx_id] FAIL — total cost \$$fx_cost"
  fi

  if [ -n "$record_dir" ]; then
    record_result "$fx_id" "$outcome_label" "$fx_cost" "$per_run_costs" || return 4
  fi
  return 0
}

# record_result <id> <pass|fail> <total-cost> <per-run-cost-lines>
# Builds the scrubbed artifact by allowlist (fixture, outcome, cost only), then
# re-verifies it carries only the allowed keys and no machine-local substring.
record_result() {
  r_id="$1"
  r_outcome="$2"
  r_cost="$3"
  r_runs="$4"
  # Encode the captured per-run costs (each already validated by is_number
  # before capture) as a JSON array. No runs -> an empty array is correct; but
  # if runs WERE captured and encoding still yields nothing, that is a
  # jq/environment failure — fail closed rather than silently writing an
  # artifact whose empty per_run_cost_usd masks the loss.
  if [ -n "$r_runs" ]; then
    runs_json="$(printf '%s' "$r_runs" | jq -R 'select(length>0) | tonumber' 2>/dev/null | jq -sc . 2>/dev/null)"
    if [ -z "$runs_json" ]; then
      echo "prompt-eval: [$r_id] fail-closed — could not encode captured per-run costs" >&2
      return 1
    fi
  else
    runs_json="[]"
  fi
  artifact="$(jq -n \
    --arg fx "$r_id" \
    --arg oc "$r_outcome" \
    --argjson cost "$r_cost" \
    --argjson runs "$runs_json" \
    '{fixture: $fx, outcome: $oc, cost_usd: $cost, per_run_cost_usd: $runs}' 2>/dev/null)"
  if [ -z "$artifact" ]; then
    echo "prompt-eval: [$r_id] fail-closed — could not build result artifact" >&2
    return 1
  fi
  # Hygiene re-verification: only the allowed keys, and no machine-local leak.
  extra_keys="$(printf '%s' "$artifact" | jq -r 'keys - ["fixture","outcome","cost_usd","per_run_cost_usd"] | .[]' 2>/dev/null)"
  if [ -n "$extra_keys" ]; then
    echo "prompt-eval: [$r_id] fail-closed — artifact carries disallowed keys: $extra_keys" >&2
    return 1
  fi
  if printf '%s' "$artifact" | grep -Eqi "$machine_local_re"; then
    echo "prompt-eval: [$r_id] fail-closed — artifact contains a machine-local substring" >&2
    return 1
  fi
  printf '%s\n' "$artifact" >"$record_dir/$r_id.json" || {
    echo "prompt-eval: [$r_id] cannot write artifact to '$record_dir'" >&2
    return 1
  }
  echo "prompt-eval: [$r_id] recorded scrubbed result -> $record_dir/$r_id.json"
  return 0
}

# ---- drive every fixture -----------------------------------------------------
# A here-doc (not a pipe) so the loop body runs in this shell — run_fixture must
# mutate overall_rc and the cumulative suite cost, which a pipe's subshell would
# discard.
while IFS= read -r fx; do
  [ -n "$fx" ] || continue
  run_fixture "$fx"
  rc=$?
  # run_fixture records a graded fixture failure itself (via note_fail, which
  # sets overall_rc) and returns 0; any non-zero rc is a fatal harness error
  # (setup, JSON, or record failure) that aborts the whole suite.
  case "$rc" in
    0) : ;;
    *) exit "$rc" ;;
  esac
done <<EOF
$fixtures
EOF

exit "$overall_rc"
