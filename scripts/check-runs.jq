# check-runs.jq — the one selection of a pull request's check runs that
# scripts/ready-guard.sh, scripts/ready-flip.sh and scripts/mc-readiness.sh
# judge readiness by. Each prepends this file to its own program, so a fix here
# reaches all three. The release gate (rl_ci_state in scripts/release-lib.sh)
# reads no selection: it judges every check on the commit, strictly.
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

# A job's family is its name up to the first space: a matrix job's shards and
# the unexpanded name it is reported under when skipped or cancelled share it.
def check_family: (.name // "") | split(" ")[0];

# A skipped matrix job is reported under its unexpanded name, which a later
# run's expanded shard names never supersede; so a skipped macOS entry is
# dropped when a shard of the same job passed.
def mac_family: check_family;

# The workflow run a check run belongs to, from its details URL; null for a
# status context or a check run with no such URL.
def workflow_run: if .context != null then null
  else ((.detailsUrl // "") | capture("/actions/runs/(?<id>[0-9]+)")? | .id) // null end;

# When a newer run on the head cancels an older run of its workflow, the older
# run's checks end CANCELLED and the newer run never replaces them: a matrix
# job's are named by its unexpanded placeholder, and the rest tie the newer
# run's start to the second, where a tie goes to the check that did not pass.
# So a finished CANCELLED check is dropped when another workflow run of the
# same workflow has a check of the same family that passed and started no
# earlier. Only cancellations go: a failure, a check still running, and a pass
# are never dropped, whatever ran after them, so a later failing re-run and a
# reused run's earlier macOS passes count as before. A cancellation with no
# such successor still counts.
def drop_superseded_cancels:
  [.[] | {entry: ., run: workflow_run, family: check_family, started: check_started, passed: check_passed}] as $rows
  | [$rows[]
      | . as $row
      | select(($row.run != null and ($row.entry.workflowName // "") != ""
          and ($row.entry.status // "COMPLETED") == "COMPLETED" and ($row.entry.conclusion // "") == "CANCELLED"
          and any($rows[]; .run != null and .run != $row.run and .passed
            and (.entry.workflowName // "") == $row.entry.workflowName
            and .family == $row.family and .started >= $row.started)) | not)
      | .entry];

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
# ready report.
def bypassed_check_runs: drop_superseded_cancels | [.[] | select(base_state_check)] | to_entries
  | group_by(.value | check_context)
  | map(max_by([(.value | check_started), .key]))
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
