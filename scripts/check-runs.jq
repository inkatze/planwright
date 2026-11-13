# check-runs.jq — the one selection of a pull request's check runs that
# scripts/ready-guard.sh, scripts/ready-flip.sh and scripts/mc-readiness.sh
# judge readiness by. Each prepends this file to its own program, so a fix here
# reaches all three.
#
# A check run listed in $base_state as <workflow>/<name> is left out first.
# Only the latest run of each check context counts: a re-run supersedes the
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

# A skipped matrix job is reported under its unexpanded name, which a later
# run's expanded shard names never supersede; so a skipped macOS entry is
# dropped when a shard of the same job (the name up to the first space) passed.
def mac_family: (.name // "") | split(" ")[0];

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
def bypassed_check_runs: [.[] | select(base_state_check)] | to_entries
  | group_by(.value | check_context)
  | map(max_by([(.value | check_started), .key]))
  | sort_by(.key) | map(.value) | map(select(check_passed | not));

# An array of rollup entries in, the latest run of each context out, in the
# order the rollup listed them. A check run naming no workflow (one an app
# posts) is its own context: two such checks sharing a name may come from
# different apps, so neither may supersede the other.
def latest_check_runs: map(select(base_state_check | not)) | to_entries
  | group_by(if .value.context == null and (.value.workflowName // "") == "" then ["solo", .key] else (.value | check_context) end)
  | map(max_by([(.value | check_started), (if .value | check_passed then 0 else 1 end), .key]))
  | sort_by(.key) | map(.value)
  | (map(select((.conclusion // "") == "SUCCESS" and ((.name // "") | startswith("macos-"))) | mac_family)) as $ok
  | map(select((((.conclusion // "") == "SKIPPED" and ((.name // "") | startswith("macos-")) and (mac_family as $f | $ok | index($f) != null))) | not));
