#!/bin/bash
# Refresh config/test-durations.tsv from the timing reports the ci workflow's
# shard jobs upload, over the last K main runs whose shard jobs all passed.
# The check job's own verdict is not required: a run the timing gate failed
# still timed a green suite.
#
# One run's shard reports are merged into one whole-suite report before
# scripts/refresh-test-durations.sh sees it, which refuses a lone shard's. A
# run is skipped, and says why, unless its reports are shards 1..N of one N,
# each exactly once. The refresh then takes each file's median over the runs.
#
# Usage: refresh-test-durations-ci.sh [--runs <K>] [--from <dir>]
#                                     [--suite <dir>] [--out <path>]
#   --runs   main runs to use (default 5)
#   --from   read runs already downloaded instead of calling gh: one
#            subdirectory per run, laid out as `gh run download` leaves it
#            (timing-report-<i>/timing-report.tsv)
#   --suite, --out   passed through to refresh-test-durations.sh
# Exit: 0 written · 2 usage, gh failure, no usable run, or a refused refresh
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

self_dir="$(cd "$(dirname "$0")" && pwd -P)"

die() {
  printf 'refresh-test-durations-ci: %s\n' "$1" >&2
  exit 2
}

runs=5
from=""
pass=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --runs | --from | --suite | --out)
      [ "$#" -ge 2 ] || die "$1 needs a value"
      case "$1" in
        --runs) runs="$2" ;;
        --from) from="$2" ;;
        *) pass+=("$1" "$2") ;;
      esac
      shift 2
      ;;
    --help | -h)
      sed -n '2,/^set -u$/{/^set -u$/d;s/^# \{0,1\}//;p;}' "$0"
      exit 0
      ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done
case "$runs" in
  '' | *[!0-9]* | 0*) die "--runs must be a positive whole number" ;;
esac

work="$(mktemp -d "${TMPDIR:-/tmp}/refresh-test-durations-ci.XXXXXX")" \
  || die "could not create a temporary directory"
trap 'rm -rf "$work"' EXIT

if [ -z "$from" ]; then
  command -v gh >/dev/null 2>&1 || die "gh is required (or pass --from)"
  from="$work/runs"
  mkdir -p "$from"
  # Cancelled and in-progress runs carry no complete set of reports, so the
  # scan reads past them, up to a bound.
  ids="$(gh run list --workflow ci.yml --branch main --event push --status completed \
    --limit "$((runs * 4))" --json databaseId --jq '.[].databaseId')" \
    || die "gh run list failed"
  got=0
  for id in $ids; do
    [ "$got" -lt "$runs" ] || break
    case "$id" in
      '' | *[!0-9]*) continue ;;
    esac
    verdicts="$(gh run view "$id" --json jobs \
      --jq '[.jobs[] | select(.name | startswith("test (shard ")) | .conclusion] | if length == 0 then "none" elif all(. == "success") then "green" else "red" end')" \
      || die "gh run view $id failed"
    [ "$verdicts" = green ] || continue
    gh run download "$id" --pattern 'timing-report-*' --dir "$from/$id" >/dev/null \
      || die "gh run download $id failed"
    got=$((got + 1))
  done
fi
[ -d "$from" ] || die "not a directory: $from"

srcs=()
n=0
for run in "$from"/*/; do
  [ -d "$run" ] || continue
  run="${run%/}"
  name="${run##*/}"
  n=$((n + 1))
  merged="$work/merged-$n.tsv"
  set -- "$run"/timing-report-*/timing-report.tsv
  if [ ! -f "$1" ]; then
    echo "refresh-test-durations-ci: run $name: no timing reports, skipped" >&2
    continue
  fi
  if why="$(RD_MERGED="$merged" awk -F'\t' '
    FNR == 1 {
      sh = ""
      for (i = 3; i <= NF; i++) if ($i ~ /^shard=[0-9]+\/[0-9]+$/) sh = substr($i, 7)
      if ($1 != "planwright-test-timing" || $2 != "2" || sh == "") { print "a report is not a version 2 shard report"; bad = 1; exit }
      split(sh, p, "/")
      if (total == "") total = p[2]
      if (p[2] != total) { print "its reports disagree on the shard count"; bad = 1; exit }
      if (p[1] in seen) { print "shard " p[1] " appears twice"; bad = 1; exit }
      seen[p[1]] = 1
      next
    }
    $1 == "file" { rows = rows $0 "\n"; next }
    $1 == "suite" && $2 == "wall" { wall += $3 }
    END {
      if (bad) exit 1
      for (s = 1; s <= total; s++) if (!(s in seen)) { print "shard " s " of " total " is missing"; exit 1 }
      printf "planwright-test-timing\t2\tmerged=%s\n%ssuite\twall\t%.3f\n", total, rows, wall > ENVIRON["RD_MERGED"]
    }
  ' "$@" 2>&1)"; then
    srcs+=("$merged")
  else
    echo "refresh-test-durations-ci: run $name: ${why:-its reports could not be read}, skipped" >&2
  fi
done
[ "${#srcs[@]}" -gt 0 ] || die "no run with a complete set of shard reports"

/bin/bash "$self_dir/refresh-test-durations.sh" ${pass[@]+"${pass[@]}"} "${srcs[@]}"
