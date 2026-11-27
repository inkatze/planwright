# check-runs.jq — the one selection of a pull request's check runs that
# scripts/ready-guard.sh, scripts/ready-flip.sh and scripts/mc-readiness.sh
# judge readiness by. Each prepends this file to its own program, so a fix here
# reaches all three. Some other readers of a head's checks apply none of it:
# the release gate (rl_ci_state in scripts/release-lib.sh) judges every check
# strictly, and others read GitHub's combined rollup state (obs:f3adc102).
#
# A cancelled check that a newer run of its workflow made obsolete is dropped
# first (drop_superseded_cancels, below). Then a check run listed in
# $base_state as <workflow>/<name> is left out of the flip conditions, and
# only the latest run of each check context counts: a re-run supersedes the
# runs before it, and a run not yet completed is the newest (gh reports an
# unset time as 0001-01-01). Two runs of one context started in the same
# second (gh reports whole seconds) are told apart by outcome, the one that did
# not pass winning, so a tie never lets a failure hide behind a success.

def check_context: if .context != null then ["status", .context] else ["run", .workflowName // "", .name // "-"] end;

def check_started: if (.status // "COMPLETED") != "COMPLETED" then "~"
  else first(([.startedAt, .createdAt, .completedAt][] | select(. != null and (tostring | startswith("0001-") | not))), "") end | tostring;

# A macOS job (macos-suite, macos-smoke) is skipped on a draft pull request, so
# its skip is no pass: only SUCCESS or NEUTRAL counts for a `macos-` check.
def check_passed: if .context != null then .state == "SUCCESS"
  else (.status // "COMPLETED") == "COMPLETED"
    and ((.conclusion // "") as $c
      | $c == "SUCCESS" or $c == "NEUTRAL"
        or ($c == "SKIPPED" and ((.name // "") | startswith("macos-") | not))) end;

# A skip ran nothing, so a skipped macOS run never supersedes a run of its
# context that did run: a ready flip reusing a prior run's evidence skips the
# macOS jobs at a head where they already passed (or failed).
def mac_skip: .context == null and (.conclusion // "") == "SKIPPED" and ((.name // "") | startswith("macos-"));

# A skipped matrix job is reported under its unexpanded name, which a later
# run's expanded shard names never supersede; so a skipped macOS entry is
# dropped when a shard of the same job passed. This family key (the name up to
# the first space) is coarse and serves only that macOS rule; the cancellation
# drop below matches names exactly or by placeholder.
def mac_family: (.name // "") | split(" ")[0];

# The workflow run a check run belongs to, from its details URL; null for a
# status context or a check run with no such URL.
def check_workflow_run: if .context != null then null
  else ((.detailsUrl // "") | capture("/actions/runs/(?<id>[0-9]+)")? | .id) // null end;

def check_cancelled: .context == null and (.status // "COMPLETED") == "COMPLETED" and (.conclusion // "") == "CANCELLED";

# Unlike check_passed, a skip is no success here: it ran nothing.
def check_succeeded: .context == null and (.status // "COMPLETED") == "COMPLETED"
  and ((.conclusion // "") as $c | $c == "SUCCESS" or $c == "NEUTRAL");

def regex_quote: gsub("(?<c>[\\\\.^$*+?()\\[\\]{}|])"; "\\\(.c)");

# Whether a check name could be one an unexpanded placeholder name stands for:
# a matrix job cancelled before it expanded keeps `${{ … }}` in its name, so
# `test (shard 1/2)` fits `test (shard ${{ matrix.shard }}/…)`. Every fixed
# part of the placeholder must appear, in order, with something in place of
# each `${{ … }}`; a placeholder that starts or ends with `${{ … }}` fits
# nothing, since a bare prefix or suffix would let unrelated jobs fit it.
def fits_placeholder($placeholder):
  ($placeholder | [splits("\\$\\{\\{.*?\\}\\}")]) as $parts
  | $parts[0] != "" and ($parts | last) != ""
    and test("^" + ($parts | map(regex_quote) | join(".+")) + "$");

# When a newer run on the head cancels an older run of its workflow, the older
# run's checks end CANCELLED. A cancelled matrix job is reported under its
# unexpanded placeholder, which the newer run's shard names never replace, and
# a cancelled job can tie the newer run's start to the second, where a tie goes
# to the check that did not pass. So a finished CANCELLED check with a known
# time is dropped when another workflow run of the same workflow has a check
# that succeeded (SUCCESS or NEUTRAL, a skip running nothing) and started no
# earlier, with the same name, or for a placeholder, a name the placeholder
# fits. Only cancellations go: a failure, a check still running, and a pass
# are never dropped, whatever ran after them, so a later failing re-run and a
# reused run's earlier macOS passes count as before. A cancellation with no
# such successor still counts.
def drop_superseded_cancels:
  if any(.[]; check_cancelled) | not then . else
    [.[] | {entry: ., run_id: check_workflow_run, workflow: (.workflowName // ""), name: (.name // ""),
      started: check_started, cancelled: check_cancelled, succeeded: check_succeeded}] as $rows
    | [$rows[] | select(.succeeded and .run_id != null and .workflow != "")] as $successes
    | [$rows[]
        | . as $row
        | ($row.cancelled and $row.run_id != null and $row.started != ""
            and any($successes[]; .run_id != $row.run_id and .workflow == $row.workflow and .started >= $row.started
              and (.name == $row.name
                or (($row.name | contains("${{")) and (.name | fits_placeholder($row.name)))))) as $superseded
        | select($superseded | not)
        | .entry]
  end;

# A check run whose "<workflow>/<name>" is in $base_state (scripts/base-state-checks.sh) describes the
# base branch, not the pull request, so it is no flip condition. The caller
# passes the array with --argjson base_state; a status context is never one.
#
# One that has not finished is no exception: a queued or running base-state
# check still holds the flip, like any other, until it reports.
def base_state_check: .context == null and (.status // "COMPLETED") == "COMPLETED"
  and (((.workflowName // "") + "/" + (.name // "")) as $id | any($base_state[]; . == $id));

# An array of rollup entries in, the base-state checks whose latest finished run
# did not pass out: what the operator bypasses at merge, named by each reader's
# ready report. A tie in start goes to the run that did not pass, as below.
def bypassed_check_runs: drop_superseded_cancels | [.[] | select(base_state_check)] | to_entries
  | group_by(.value | check_context)
  | map(max_by([(.value | check_started), (if .value | check_passed then 0 else 1 end), .key]))
  | sort_by(.key) | map(.value) | map(select(check_passed | not));

# An array of rollup entries in, the latest run of each context out, in the
# order the rollup listed them. A check run naming no workflow (one an app
# posts) is its own context: two such checks sharing a name may come from
# different apps, so neither may supersede the other.
def latest_check_runs: drop_superseded_cancels | map(select(base_state_check | not)) | to_entries
  | group_by(if .value.context == null and (.value.workflowName // "") == "" then ["solo", .key] else (.value | check_context) end)
  | map(max_by([(if .value | mac_skip then 0 else 1 end), (.value | check_started), (if .value | check_passed then 0 else 1 end), .key]))
  | sort_by(.key) | map(.value)
  | (map(select((.conclusion // "") == "SUCCESS" and ((.name // "") | startswith("macos-"))) | mac_family)) as $ok
  | map(select((((.conclusion // "") == "SKIPPED" and ((.name // "") | startswith("macos-")) and (mac_family as $f | $ok | index($f) != null))) | not));
