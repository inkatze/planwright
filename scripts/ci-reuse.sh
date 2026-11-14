#!/bin/sh
# ci-reuse.sh — let a ready flip reuse a prior CI run's suite jobs instead of
# running them again. ci.yml's plan job calls it; the check job then accepts
# the skipped suite jobs on the reused run's evidence and names that run.
#
# A pull_request run tests the merge of its head into its base, under the
# workflow file that merge carries. Two runs hold the same evidence only when
# all three match, so `evidence` names them and the plan job uploads an
# artifact under that name; `lookup` reuses a prior run only when it carries
# an artifact of exactly this run's name and every suite job it names
# succeeded there (skipped is not success). Anything else (another head, a
# moved base, a changed workflow, a red, cancelled, partial or macOS-skipped
# run, an unreadable answer, a call that fails or runs past the time budget)
# reuses nothing, so every job runs.
#
# Usage:
#   ci-reuse.sh evidence --head <sha> [--workflow <path>]
#       In a checkout of a pull request's merge commit, print
#       ci-evidence-<base>-<head>-<workflow blob>, the base being the merge's
#       first parent. Exit 1 when HEAD is no two-parent merge whose second
#       parent is <sha>, or holds no <path> (default .github/workflows/ci.yml).
#   ci-reuse.sh lookup --repo <owner/name> --run-id <id> --event <name>
#       --action <name> --evidence <name> [--workflow <path>]
#       (--matrix-job <name> | --job <name>)...
#       Print `run_id=<id>` and `suite_run=false` for the newest prior run of
#       <path> on this evidence whose every --matrix-job ran each of its
#       `<name> (shard i/N)` shards once and every --job ran once, all
#       succeeded; else `run_id=` and `suite_run=true`. Only a
#       pull_request ready_for_review event looks; the reason goes to stderr.
#       GH_TOKEN must allow reading Actions.
#
# PLANWRIGHT_CI_REUSE_BUDGET is the lookup's whole time budget in seconds
# (default 60), shared by every gh call it makes.
#
# Exit: 0 on a verdict, reuse or not; 1 `evidence` could not name one; 2 usage.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

prog=ci-reuse
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

usage() {
  printf '%s\n' "usage: $prog evidence --head <sha> [--workflow <path>]" \
    "       $prog lookup --repo <owner/name> --run-id <id> --event <name> --action <name>" \
    "              --evidence <name> [--workflow <path>] (--matrix-job <name> | --job <name>)..." >&2
  exit 2
}
need() { [ "$1" -ge 2 ] || usage; }

is_sha() {
  case $1 in
    '' | *[!0-9a-f]*) return 1 ;;
  esac
  [ "${#1}" -eq 40 ] || [ "${#1}" -eq 64 ]
}

evidence() {
  head=""
  workflow=.github/workflows/ci.yml
  while [ $# -gt 0 ]; do
    case $1 in
      --head) need $# && head=$2 && shift 2 ;;
      --workflow) need $# && workflow=$2 && shift 2 ;;
      *) usage ;;
    esac
  done
  is_sha "$head" || usage
  raw=$(git cat-file commit HEAD) || {
    printf '%s\n' "$prog: HEAD is no readable commit" >&2
    exit 1
  }
  # The header ends at the first empty line; only its parent lines count.
  parents=$(printf '%s\n' "$raw" | sed -n -e '/^$/q' -e 's/^parent //p')
  # shellcheck disable=SC2086 # split into the parent ids on purpose
  set -- $parents
  if [ $# -ne 2 ]; then
    printf '%s\n' "$prog: HEAD has $# parent(s), not the two of a pull request's merge commit" >&2
    exit 1
  fi
  if [ "$2" != "$head" ]; then
    printf '%s\n' "$prog: the merge's second parent $2 is not the head $head" >&2
    exit 1
  fi
  blob=$(git rev-parse --verify -q "HEAD:$workflow") || {
    printf '%s\n' "$prog: HEAD holds no $workflow" >&2
    exit 1
  }
  printf 'ci-evidence-%s-%s-%s\n' "$1" "$2" "$blob"
}

# --- lookup ------------------------------------------------------------------

no_reuse() {
  printf '%s\n' "$prog: $1; every job runs" >&2
  printf 'run_id=\nsuite_run=true\n'
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
  | sort_by(.created_at) | reverse | .[:5][] | .id | tostring'

# "yes" when the run carries an artifact of exactly this evidence's name.
# shellcheck disable=SC2016 # jq program text
jq_artifacts='
  if (.artifacts | type) != "array" then error("no artifact list")
  elif (.total_count // 0) > (.artifacts | length) then "truncated"
  elif any(.artifacts[]; .name == $name) then "yes" else "no" end'

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

lookup() {
  repo="" run_id="" event="" action="" evidence_name="" workflow=.github/workflows/ci.yml
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
    ci-evidence-*-*-*) ;;
    *) no_reuse "this run has no evidence of its own to match" ;;
  esac
  rest=${evidence_name#ci-evidence-}
  base=${rest%%-*}
  rest=${rest#*-}
  head=${rest%%-*}
  blob=${rest#*-}
  if ! is_sha "$base" || ! is_sha "$head" || ! is_sha "$blob"; then
    no_reuse "the evidence name '$evidence_name' is not base-head-blob"
  fi

  budget=${PLANWRIGHT_CI_REUSE_BUDGET:-60}
  case $budget in
    '' | 0 | *[!0-9]* | 0*) usage ;;
  esac
  deadline=$(($(date +%s) + budget))
  # shellcheck disable=SC2086 # the job names, validated words, split on purpose
  matrix_json=$(json_list $matrix) && single_json=$(json_list $single)

  runs=$(gh_read "repos/$repo/actions/workflows/${workflow##*/}/runs?event=pull_request&status=success&head_sha=$head&per_page=100") \
    || no_reuse "the run lookup failed or ran out of time"
  ids=$(printf '%s' "$runs" | jq -r --arg head "$head" --arg path "$workflow" --arg self "$run_id" "$jq_runs") \
    || no_reuse "the run list did not read as one"
  [ -n "$ids" ] || no_reuse "no prior run succeeded at $head"
  for id in $ids; do
    arts=$(gh_read "repos/$repo/actions/runs/$id/artifacts?per_page=100") || {
      printf '%s\n' "$prog: run $id: its artifact lookup failed or ran out of time" >&2
      continue
    }
    has=$(printf '%s' "$arts" | jq -r --arg name "$evidence_name" "$jq_artifacts") || has=unreadable
    if [ "$has" != yes ]; then
      printf '%s\n' "$prog: run $id: no artifact names this run's head, base and workflow ($has)" >&2
      continue
    fi
    jobs=$(gh_read "repos/$repo/actions/runs/$id/jobs?filter=latest&per_page=100") || {
      printf '%s\n' "$prog: run $id: its job lookup failed or ran out of time" >&2
      continue
    }
    verdict=$(printf '%s' "$jobs" | jq -r --argjson matrix "$matrix_json" --argjson single "$single_json" "$jq_jobs") \
      || verdict="its job list did not read as one"
    if [ "$verdict" != ok ]; then
      printf '%s\n' "$prog: run $id: $verdict" >&2
      continue
    fi
    printf '%s\n' "$prog: run $id tested this head, base and workflow with every suite job green; reusing it" >&2
    printf 'run_id=%s\nsuite_run=false\n' "$id"
    exit 0
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
