# check-runs.jq — the one selection of a pull request's check runs that
# scripts/ready-guard.sh, scripts/ready-flip.sh and scripts/mc-readiness.sh
# judge readiness by. Each prepends this file to its own program, so a fix here
# reaches all three.
#
# A check named in $base_state is left out first.
# Only the latest run of each check context counts: a re-run supersedes the
# runs before it, and a run not yet completed is the newest (gh reports an
# unset time as 0001-01-01). Two runs of one context started in the same
# second (gh reports whole seconds) are told apart by outcome, the one that did
# not pass winning, so a tie never lets a failure hide behind a success.

def check_context: if .context != null then ["status", .context] else ["run", .workflowName // "", .name // "-"] end;

def check_started: if (.status // "COMPLETED") != "COMPLETED" then "~"
  else first(([.startedAt, .createdAt, .completedAt][] | select(. != null and (tostring | startswith("0001-") | not))), "") end | tostring;

def check_passed: if .context != null then .state == "SUCCESS"
  else (.status // "COMPLETED") == "COMPLETED" and ((.conclusion // "") as $c | $c == "SUCCESS" or $c == "NEUTRAL" or $c == "SKIPPED") end;

# A check run whose "<workflow>/<name>" is in $base_state (scripts/base-state-checks.sh) describes the
# base branch, not the pull request, so it is no flip condition. The caller
# passes the array with --argjson base_state; a status context is never one.
def base_state_check: .context == null and (((.workflowName // "") + "/" + (.name // "")) as $id | any($base_state[]; . == $id));

# An array of rollup entries in, the latest run of each context out, in the
# order the rollup listed them. A check run naming no workflow (one an app
# posts) is its own context: two such checks sharing a name may come from
# different apps, so neither may supersede the other.
def latest_check_runs: map(select(base_state_check | not)) | to_entries
  | group_by(if .value.context == null and (.value.workflowName // "") == "" then ["solo", .key] else (.value | check_context) end)
  | map(max_by([(.value | check_started), (if .value | check_passed then 0 else 1 end), .key]))
  | sort_by(.key) | map(.value);
