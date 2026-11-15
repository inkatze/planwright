#!/bin/sh
# ci-reuse.sh — let a ready flip reuse a prior CI run's suite jobs instead of
# running them again (ci.yml's plan job calls it). A pull_request run tests
# its head merged into its base under the ci.yml that merge carries, so two
# runs hold the same evidence only when all three match. Anything short of a
# prior run with exactly this evidence and every named job succeeded (skipped
# is not success), a failed or slow lookup included, reuses nothing.
#
# Usage:
#   ci-reuse.sh evidence --head <sha> [--workflow <path>]
#       In a checkout of a pull request's merge commit, print the evidence
#       name ci-evidence-<first parent>-<head>-<workflow blob>; exit 1 when
#       HEAD is no merge whose second parent is <sha>, or lacks <path>.
#   ci-reuse.sh lookup --repo <owner/name> --run-id <current run>
#       --event <name> --action <name> --evidence <name> [--workflow <path>]
#       (--matrix-job <name> | --job <name>)...
#       On a pull_request ready_for_review only, print `reuse_run=<id>` and
#       `suite_run=false` for the newest prior run carrying an artifact of that
#       name whose every --matrix-job ran each `<name> (shard i/N)` once and
#       every --job once, all succeeded; else `reuse_run=` and
#       `suite_run=true`. Reasons go to stderr; GH_TOKEN must read Actions.
#       PLANWRIGHT_CI_REUSE_BUDGET: whole seconds for every gh call together
#       (default 60, at most 240).
# Exit: 0 on a verdict, reuse or not; 1 `evidence` named none; 2 usage.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

prog=ci-reuse
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
default_workflow=.github/workflows/ci.yml
prefix=ci-evidence-

usage() {
  printf '%s\n' "usage: $prog evidence --head <sha> [--workflow <path>]" \
    "       $prog lookup --repo <owner/name> --run-id <id> --event <name> --action <name>" \
    "              --evidence <name> [--workflow <path>] (--matrix-job <name> | --job <name>)..." >&2
  exit 2
}
need() { [ "$1" -ge 2 ] || usage; }
warn() { printf '%s\n' "$prog: $*" >&2; }
die() {
  warn "$@"
  exit 1
}

is_sha() {
  case $1 in
    '' | *[!0-9a-f]*) return 1 ;;
  esac
  [ "${#1}" -eq 40 ] || [ "${#1}" -eq 64 ]
}

evidence() {
  head=""
  workflow=$default_workflow
  while [ $# -gt 0 ]; do
    case $1 in
      --head) need $# && head=$2 && shift 2 ;;
      --workflow) need $# && workflow=$2 && shift 2 ;;
      *) usage ;;
    esac
  done
  is_sha "$head" || usage
  # The raw object keeps its parent lines even in a shallow clone.
  raw=$(git cat-file commit HEAD) || die "HEAD is no readable commit"
  parents=$(printf '%s\n' "$raw" | sed -n -e '/^$/q' -e 's/^parent //p')
  # shellcheck disable=SC2086 # split into the parent ids on purpose
  set -- $parents
  [ $# -eq 2 ] || die "HEAD has $# parent(s), not the two of a pull request's merge commit"
  [ "$2" = "$head" ] || die "the merge's second parent $2 is not the head $head"
  blob=$(git rev-parse --verify -q "HEAD:$workflow") || die "HEAD holds no $workflow"
  printf '%s%s-%s-%s\n' "$prefix" "$1" "$2" "$blob"
}

# --- lookup ------------------------------------------------------------------

no_reuse() {
  warn "$1; every job runs"
  printf 'reuse_run=\nsuite_run=true\n'
  exit 0
}

# gh_read <path>: one bounded `gh api` read, refused once the budget is spent.
gh_read() {
  left=$((deadline - $(date +%s)))
  [ "$left" -gt 0 ] || return 124
  /bin/sh "$script_dir/bounded-run.sh" -k 2 "$left" gh api "$1"
}

# The prior runs worth reading, newest first: this workflow's completed,
# succeeded pull_request runs at this head, the current run left out.
# shellcheck disable=SC2016 # jq program text
jq_runs='
  .workflow_runs
  | if type != "array" then error("no run list") else . end
  | map(select(.event == "pull_request" and .status == "completed"
      and .conclusion == "success" and .head_sha == $head
      and .path == $path and (.id | tostring) != $self))
  | sort_by(.created_at) | reverse | .[] | .id | tostring'

# "ok" when the run carries an artifact of exactly this evidence's name.
# shellcheck disable=SC2016 # jq program text
jq_artifacts='
  if (.artifacts | type) != "array" then error("no artifact list")
  elif (.total_count // 0) > (.artifacts | length) then "its artifact list is truncated"
  elif any(.artifacts[]; .name == $name) then "ok"
  else "no artifact names this head, base and workflow" end'

# "ok", or the first reason the run's suite jobs are no evidence.
# shellcheck disable=SC2016 # jq program text
jq_jobs='
  def green: .status == "completed" and .conclusion == "success";
  if (.jobs | type) != "array" then error("no job list")
  elif (.total_count // 0) > (.jobs | length) then "its job list is truncated"
  else .jobs as $jobs
  | [ ($matrix[] as $m
        | [$jobs[] | select(.name == $m or (.name | startswith($m + " ")))] as $g
        | [$g[] | [.name | capture("^" + $m + " \\(shard (?<i>[0-9]+)/(?<n>[0-9]+)\\)$")] | .[0]] as $c
        | if ($g | length) == 0 then "\($m) did not run"
          elif any($c[]; . == null) then "\($m) has a job outside its shards (a skip keeps the unexpanded name)"
          elif ($c | map(.n) | unique | length) != 1 then "the \($m) shards disagree on their count"
          elif ($c | map(.i | tonumber) | sort) != [range(1; ($c[0].n | tonumber) + 1)] then "\($m) did not run each shard once"
          elif any($g[]; green | not) then "\($m) did not succeed on every shard"
          else empty end),
      ($single[] as $s
        | [$jobs[] | select(.name == $s)] as $g
        | if ($g | length) != 1 then "\($s) did not run once"
          elif ($g[0] | green | not) then "\($s) did not succeed"
          else empty end)
    ] | first(.[]) // "ok"
  end'

json_list() { # json_list <word>...: a JSON array of the words
  out="["
  sep=""
  for w in "$@"; do
    out="$out$sep\"$w\""
    sep=,
  done
  printf '%s]' "$out"
}

# run_verdict <id>: "ok" when the prior run is this run's evidence, else why not.
run_verdict() {
  json=$(gh_read "repos/$repo/actions/runs/$1/artifacts?per_page=100") || {
    echo "its artifact lookup failed or ran out of time"
    return
  }
  v=$(printf '%s' "$json" | jq -r --arg name "$evidence_name" "$jq_artifacts") || v="its artifact list did not read as one"
  [ "$v" = ok ] || {
    printf '%s\n' "$v"
    return
  }
  json=$(gh_read "repos/$repo/actions/runs/$1/jobs?filter=latest&per_page=100") || {
    echo "its job lookup failed or ran out of time"
    return
  }
  v=$(printf '%s' "$json" | jq -r --argjson matrix "$matrix_json" --argjson single "$single_json" "$jq_jobs") \
    || v="its job list did not read as one"
  printf '%s\n' "$v"
}

lookup() {
  repo="" run_id="" event="" action="" evidence_name="" workflow=$default_workflow
  have_event="" have_action="" have_evidence=""
  matrix="" single=""
  while [ $# -gt 0 ]; do
    case $1 in
      --repo) need $# && repo=$2 && shift 2 ;;
      --run-id) need $# && run_id=$2 && shift 2 ;;
      --event) need $# && event=$2 && have_event=1 && shift 2 ;;
      --action) need $# && action=$2 && have_action=1 && shift 2 ;;
      --evidence) need $# && evidence_name=$2 && have_evidence=1 && shift 2 ;;
      --workflow) need $# && workflow=$2 && shift 2 ;;
      --matrix-job | --job)
        need $#
        case $2 in
          '' | *[!A-Za-z0-9_-]*) usage ;;
        esac
        if [ "$1" = --job ]; then single="$single $2"; else matrix="$matrix $2"; fi
        shift 2
        ;;
      *) usage ;;
    esac
  done
  case $repo in
    */*/* | /* | */ | '' | *[!A-Za-z0-9_./-]*) usage ;;
    */*) ;;
    *) usage ;;
  esac
  case $run_id in
    '' | *[!0-9]*) usage ;;
  esac
  [ -n "$have_event" ] && [ -n "$have_action" ] && [ -n "$have_evidence" ] || usage
  [ -n "$matrix$single" ] || usage
  case $workflow in
    .github/workflows/*.yml | .github/workflows/*.yaml) ;;
    *) usage ;;
  esac

  [ "$event" = pull_request ] && [ "$action" = ready_for_review ] \
    || no_reuse "a ${event:-?} ${action:-?} event reuses nothing"
  case $evidence_name in
    "$prefix"*-*-*) ;;
    *) no_reuse "this run has no evidence of its own to match" ;;
  esac
  rest=${evidence_name#"$prefix"}
  base=${rest%%-*}
  rest=${rest#*-}
  head=${rest%%-*}
  blob=${rest#*-}
  if ! is_sha "$base" || ! is_sha "$head" || ! is_sha "$blob"; then
    no_reuse "the evidence name '$evidence_name' is not base-head-blob"
  fi

  # A malformed budget must not turn the run red, and none may outlast the
  # plan job's own timeout.
  budget=${PLANWRIGHT_CI_REUSE_BUDGET:-60}
  case $budget in
    '' | 0 | *[!0-9]* | 0*) budget=60 ;;
  esac
  if [ "${#budget}" -gt 3 ] || [ "$budget" -gt 240 ]; then budget=240; fi
  deadline=$(($(date +%s) + budget))
  # shellcheck disable=SC2086 # the job names, validated words, split on purpose
  matrix_json=$(json_list $matrix) && single_json=$(json_list $single)

  runs=$(gh_read "repos/$repo/actions/workflows/${workflow##*/}/runs?event=pull_request&status=success&head_sha=$head&per_page=100") \
    || no_reuse "the run lookup failed or ran out of time"
  ids=$(printf '%s' "$runs" | jq -r --arg head "$head" --arg path "$workflow" --arg self "$run_id" "$jq_runs") \
    || no_reuse "the run list did not read as one"
  [ -n "$ids" ] || no_reuse "no prior run succeeded at $head"
  for id in $ids; do
    verdict=$(run_verdict "$id")
    if [ "$verdict" = ok ]; then
      warn "run $id tested this head, base and workflow with every suite job green; reusing it"
      printf 'reuse_run=%s\nsuite_run=false\n' "$id"
      exit 0
    fi
    warn "run $id: $verdict"
  done
  no_reuse "no prior run tested this head, base and workflow with every suite job green"
}

[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
  evidence) evidence "$@" ;;
  lookup) lookup "$@" ;;
  *) usage ;;
esac
