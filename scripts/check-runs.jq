# check-runs.jq — the one selection of a pull request's check runs that
# scripts/ready-guard.sh, scripts/ready-flip.sh and scripts/mc-readiness.sh
# judge readiness by. Each prepends this file to its own program, so a fix here
# reaches all three. Some other readers of a head's checks apply none of it:
# the release gate (rl_ci_state in scripts/release-lib.sh), beyond its own
# window-lock and flip-point exclusions, judges every check, and others read
# the combined rollup state or the raw rollup (obs:f3adc102).
#
# A matrix job cancelled under its unexpanded name is dropped first once
# another run of its workflow passed, starting no earlier, a shard it fits
# (drop_superseded_cancels, below, has the exact rule). Then a check run listed in
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

# The id of the workflow run a check run belongs to, from its details URL;
# null for a status context or a check run with no such URL.
def check_run_id: if .context != null then null
  else ((.detailsUrl // "") | capture("/actions/runs/(?<id>[0-9]+)")? | .id) // null end;

def check_cancelled: .context == null and (.status // "COMPLETED") == "COMPLETED" and (.conclusion // "") == "CANCELLED";

# Unlike check_passed, a skip is no success here: it ran nothing.
def check_succeeded: .context == null and (.status // "COMPLETED") == "COMPLETED"
  and ((.conclusion // "") as $c | $c == "SUCCESS" or $c == "NEUTRAL");

# The longest name, the most expressions, and the most cancelled placeholders
# a match considers. Check names come from the workflow a pull request
# carries, and ready-guard.sh runs this selection inside a hook with no time
# bound on jq, so past any bound a name is never matched and its cancellation
# keeps counting. At these bounds a 99-entry rollup built to fail every match
# late costs well under a second.
def placeholder_name_max: 128;
def placeholder_expressions_max: 4;
def placeholder_rows_max: 16;

# A matrix job cancelled before it expanded keeps `${{ … }}` in its name. Its
# fixed parts, the text around each expression, are what an expanded name of
# that job must keep: `test (shard 1/2)` fits
# `test (shard ${{ matrix.shard }}/${{ strategy.job-total }})`. A name with no
# expression, or past the bounds above, has none. An expression is taken to
# end at its first `}}`, so one holding `}}` in a string fits nothing.
def placeholder_parts:
  if contains("${{") and length <= placeholder_name_max
  then [splits("\\$\\{\\{.*?\\}\\}")] | if length - 1 <= placeholder_expressions_max then . else null end
  else null end;

# Whether a name fits a placeholder's parts: it starts with the first, ends
# with the last, and holds every middle part in order, with at least one
# character in place of each expression. Plain string matching with no
# backtracking, so jq and gojq agree; the bounds above keep it cheap. A
# placeholder that starts or ends with an expression fits nothing, since a
# bare prefix or suffix would let unrelated jobs fit it. An expression's
# stand-in may itself hold fixed text, so a sibling job shaped like a shard
# can fit; the later run's own entries for the job still count.
def fits_parts($parts):
  . as $name | ($parts | length) as $k
  | $k >= 2 and $parts[0] != "" and $parts[$k - 1] != "" and ($name | length) <= placeholder_name_max
    and ($name | startswith($parts[0])) and ($name | endswith($parts[$k - 1]))
    and (reduce $parts[1:$k - 1][] as $part ({at: (($parts[0] | length) + 1)};
        if .at == null then .
        elif $part == "" then {at: (.at + 1)}
        else ($name[.at:] | split($part)) as $pieces
          | if ($pieces | length) < 2 then {at: null}
            else {at: (.at + ($pieces[0] | length) + ($part | length) + 1)} end
        end)
      | .at != null and .at <= ($name | length) - ($parts[$k - 1] | length));

# When a newer run on the head cancels an older run of its workflow, the older
# run's checks end CANCELLED. Under the same name the newer run's check simply
# supersedes them, as the latest run of their context: a successor's jobs
# start after the run it cancelled has finished cancelling. A matrix job
# cancelled before it expanded is reported under its unexpanded placeholder,
# though, which the newer run's shard names never replace. So a finished
# CANCELLED placeholder with a known time is dropped when another workflow run
# of the same workflow has a check that succeeded (SUCCESS or NEUTRAL, a skip
# running nothing), started no earlier, under a name its parts fit. Nothing
# else is dropped: a failure, a check still running and a pass never are, and
# a same-name cancellation keeps the latest-run rule, a tie going to it, so a
# timed-out job reported cancelled cannot hide behind a same-second pass. A
# placeholder with no such successor still counts.
def drop_superseded_cancels:
  if any(.[]; check_cancelled and ((.name // "" | tostring) | contains("${{"))) | not then . else
    (reduce (.[] | check_cancelled and ((.name // "" | tostring) | contains("${{"))) as $p
      ({n: 0, ok: []}; .ok += [$p and .n < placeholder_rows_max] | .n += (if $p then 1 else 0 end))
      | .ok) as $placeholder_ok
    | [to_entries[] | .key as $i | .value
      | {entry: ., run_id: check_run_id, workflow: (.workflowName // ""), name: (.name // "" | tostring),
         started: check_started, succeeded: check_succeeded,
         parts: (if $placeholder_ok[$i] then (.name // "" | tostring | placeholder_parts) else null end)}] as $rows
    | [$rows[] | select(.succeeded and .run_id != null and .workflow != "")] as $successes
    | [$rows[]
        | . as $row
        | ($row.parts != null and $row.run_id != null and $row.started != ""
            and any($successes[]; .run_id != $row.run_id and .workflow == $row.workflow
              and .started >= $row.started and (.name | fits_parts($row.parts)))) as $superseded
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
