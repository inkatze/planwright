#!/bin/sh
# substrate-baseline.sh — the script layer's maintenance-cost baseline, as a
# dated snapshot regenerable from the tree (universal-binary REQ-G1.1).
#
# FIELDS, each counted on or before the --as-of date (UTC):
#   commits     per calendar month, the non-merge commits touching scripts/ or
#               githooks/, and the fix-typed ones among them (a subject
#               `fix:`, `fix(<scope>):`, or either with `!`). The month is
#               the committer date's, so a squash merge counts when it lands.
#   inflow      per calendar month, the observations recorded: every fragment
#               under the accumulator's entries/ and archive/ by the date its
#               name opens with, plus every dated line of the frozen log. The
#               class columns count the mined set's items by the classes
#               scripts/substrate-attribute.sh assigns them (an item in two
#               classes counts in both); the rest are outside the mined set.
#   wall-clock  the check aggregate's wall-clock: the `mise run check` step of
#               the ci workflow's check job on recent successful pushes to
#               main, read from a committed capture (below), as median, min
#               and max seconds over the captured runs.
#   hand-backs  per calendar month, worker runs ended by a human hand-back
#               that a test-flakiness observation attributes to a
#               load-sensitive test failure: the hand-back record lists each
#               such observation with the runs it records, and every listed
#               observation must carry the test-flakiness class.
#
# CAPTURE. `--capture-wallclock` prints the wall-clock capture instead: the
# newest --runs (default 10) successful push runs of the ci workflow on main
# created on or before the as-of date, one `run<TAB>created<TAB>sha<TAB>seconds`
# row each, read through `gh`. The capture is committed, so the snapshot
# regenerates offline and byte-identically.
#
# INPUT FILES (tab-separated, `#` comment lines and blank lines skipped):
#   wall-clock capture   run  created  sha  seconds
#   hand-back record     id  runs  reason
#
# Usage: substrate-baseline.sh --as-of <YYYY-MM-DD> [--repo-root <dir>]
#          [--spec <bundle-dir>] [--legacy <tsv>] [--wallclock <tsv>]
#          [--hand-backs <tsv>]
#        substrate-baseline.sh --capture-wallclock --as-of <YYYY-MM-DD>
#          [--repo-root <dir>] [--runs <n>]
# Defaults: the repo is this script's parent; the bundle, the accumulator and
# the legacy index are substrate-attribute.sh's defaults; the capture is
# docs/substrate/check-wallclock-<as-of>.tsv; the hand-back record is
# docs/substrate/hand-backs.tsv.
# Exit codes: 0 written; 2 usage error; 5 fail-closed (an unreadable input, a
# repo git cannot read, an attribution that fails, an empty or malformed
# capture, a hand-back row naming an observation outside the test-flakiness
# class, or a capture that finds no runs).
#
# POSIX sh on the macOS + Linux support bar. All input is data.
set -uf

LC_ALL=C
TZ=UTC
export LC_ALL TZ
unset CDPATH

me=substrate-baseline
script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
repo_root=$(cd "$script_dir/.." && pwd -P) || exit 2

usage() {
  printf '%s\n' "usage: substrate-baseline.sh [--capture-wallclock] --as-of <YYYY-MM-DD> [--repo-root <dir>] [--spec <bundle-dir>] [--legacy <tsv>] [--wallclock <tsv>] [--hand-backs <tsv>] [--runs <n>]" >&2
  exit 2
}

as_of="" capture=0 spec="" legacy="" wallclock="" handbacks="" runs=10
while [ "$#" -gt 0 ]; do
  case $1 in
    --capture-wallclock) capture=1 && shift ;;
    --as-of | --repo-root | --spec | --legacy | --wallclock | --hand-backs | --runs)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage
      case $1 in
        --as-of) as_of=$2 ;;
        --repo-root) repo_root=$2 ;;
        --spec) spec=$2 ;;
        --legacy) legacy=$2 ;;
        --wallclock) wallclock=$2 ;;
        --hand-backs) handbacks=$2 ;;
        --runs) runs=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
printf '%s\n' "$as_of" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || usage
printf '%s\n' "$runs" | grep -Eq '^[1-9][0-9]?$' || usage

fail_closed() {
  printf '%s\n' "$me: $1; failing closed rather than writing a baseline" >&2
  exit 5
}

case $repo_root in -*) repo_root=./$repo_root ;; esac
repo_root=$(cd "$repo_root" 2>/dev/null && pwd -P) || fail_closed "the repo root is not a readable directory"
command -v jq >/dev/null 2>&1 || fail_closed "'jq' is not on PATH"

if [ "$capture" -eq 1 ]; then
  command -v gh >/dev/null 2>&1 || fail_closed "'gh' is not on PATH"
  list=$(cd "$repo_root" && gh run list --workflow ci.yml --branch main --event push --status success \
    --limit 100 --json databaseId,createdAt,headSha) || fail_closed "gh could not list the ci runs"
  picked=$(printf '%s\n' "$list" | jq -r --arg until "${as_of}T23:59:59Z" --argjson n "$runs" '
    [.[] | select(.createdAt <= $until)] | sort_by(.createdAt) | reverse | .[:$n][]
    | "\(.databaseId)\t\(.createdAt)\t\(.headSha)"') || fail_closed "the run list is not the JSON gh prints"
  [ -n "$picked" ] || fail_closed "no successful push run of ci on main on or before $as_of"
  # Rows are collected before anything prints, so a failed run read leaves no
  # partial capture behind; the loop reads a here-document, not a pipe, so its
  # fail_closed ends the script rather than a subshell.
  rows=""
  tab=$(printf '\t')
  while IFS=$tab read -r run created sha; do
    secs=$(cd "$repo_root" && gh run view "$run" --json jobs --jq '
      [.jobs[] | select(.name == "check") | .steps[] | select(.name == "Run mise run check")
       | ((.completedAt | fromdateiso8601) - (.startedAt | fromdateiso8601))] | first // empty') \
      || fail_closed "gh could not read run $run"
    printf '%s\n' "$secs" | grep -Eq '^[0-9]+$' || fail_closed "run $run has no timed check step"
    rows="$rows$run$tab$created$tab$sha$tab$secs
"
  done <<EOF
$picked
EOF
  # shellcheck disable=SC2016 # the backticks are literal Markdown, not a substitution
  printf '# ci workflow, check job, `mise run check` step: successful pushes to main\n'
  printf '# run\tcreated\tsha\tseconds\n'
  printf '%s' "$rows"
  exit 0
fi

[ -n "$wallclock" ] || wallclock=$repo_root/docs/substrate/check-wallclock-$as_of.tsv
[ -n "$handbacks" ] || handbacks=$repo_root/docs/substrate/hand-backs.tsv
[ -r "$wallclock" ] || fail_closed "the wall-clock capture is unreadable"
[ -r "$handbacks" ] || fail_closed "the hand-back record is unreadable"
git -C "$repo_root" rev-parse --verify --quiet HEAD >/dev/null || fail_closed "git cannot read the repo's HEAD"

work=$(mktemp -d "${TMPDIR:-/tmp}/substrate-baseline.XXXXXX") || fail_closed "mktemp -d failed"
[ -n "$work" ] && [ -d "$work" ] || fail_closed "mktemp -d produced no directory"
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

set -- --as-of "$as_of" --repo-root "$repo_root" --class-map
[ -z "$spec" ] || set -- "$@" --spec "$spec"
[ -z "$legacy" ] || set -- "$@" --legacy "$legacy"
/bin/sh "$script_dir/substrate-attribute.sh" "$@" >"$work/classes.tsv" || fail_closed "the attribution class map failed"

if [ -z "$spec" ]; then
  spec_root=$(/bin/sh "$repo_root/scripts/resolve-root.sh" spec) || fail_closed "the spec root does not resolve"
  spec=$spec_root/universal-binary
fi
obs_dir=$(dirname "$spec")/_observations

git -C "$repo_root" log --no-merges --until="${as_of}T23:59:59Z" --date=format-local:%Y-%m \
  --format='%cd%x09%s' -- scripts githooks >"$work/commits.tsv" || fail_closed "git log failed"

# Every dated observation: fragments by file name, frozen-log lines by prefix.
{
  set +f
  for f in "$obs_dir"/entries/*.md "$obs_dir"/archive/*.md; do
    [ -f "$f" ] || continue
    basename "$f"
  done
  set -f
} | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}-' | cut -c1-10 >"$work/dates"
grep -E '^- [0-9]{4}-[0-9]{2}-[0-9]{2} ' "$obs_dir/opportunities.md" | cut -c3-12 >>"$work/dates"

awk -F'\t' -v asof="$as_of" -v classes="$work/classes.tsv" -v commits="$work/commits.tsv" \
  -v dates="$work/dates" -v wc="$work/wc" -v hb="$handbacks" '
  BEGIN {
    nc = split("lock-concurrency parser-fragility echo-sanitization duplicated-primitive perf-spawn-cost portability lint-gap plugin-delivery test-flakiness instruction-headroom auditability", c, " ")
    amonth = substr(asof, 1, 7); first = amonth
    while ((getline l < classes) > 0) {
      split(l, p, "\t"); if (p[2] > asof) continue
      m = substr(p[2], 1, 7); mined[m]++; month(m); idm[p[1]] = m; idc[p[1]] = p[3]
      k = split(p[3], kk, ",")
      for (i = 1; i <= k; i++) cell[m, kk[i]]++
    }
    while ((getline l < commits) > 0) {
      split(l, p, "\t"); m = p[1]; month(m); all[m]++
      if (p[2] ~ /^fix(\([^)]*\))?!?: /) fix[m]++
    }
    while ((getline d < dates) > 0) { if (d > asof) continue; m = substr(d, 1, 7); month(m); obs[m]++ }
    while ((getline l < hb) > 0) {
      if (l ~ /^#/ || l ~ /^[ \t]*$/) continue
      k = split(l, p, "\t")
      if (k != 3 || p[2] !~ /^[1-9][0-9]*$/ || p[3] == "") { print "malformed hand-back row: " p[1] > "/dev/stderr"; exit 5 }
      if (!(p[1] in idm)) { print "hand-back row outside the mined set: " p[1] > "/dev/stderr"; exit 5 }
      if (("," idc[p[1]] ",") !~ /,test-flakiness,/) { print "hand-back row outside the test-flakiness class: " p[1] > "/dev/stderr"; exit 5 }
      hand[idm[p[1]]] += p[2]
    }
  }
  function month(m) { if (m < first) first = m }
  function next_month(m,   y, mo) {
    y = substr(m, 1, 4) + 0; mo = substr(m, 6, 2) + 1
    if (mo > 12) { mo = 1; y++ }
    return sprintf("%04d-%02d", y, mo)
  }
  END {
    n = 0
    for (m = first; m <= amonth; m = next_month(m)) ms[++n] = m
    for (i = 1; i <= n; i++) {
      m = ms[i]
      r = m "\t" (all[m] + 0) "\t" (fix[m] + 0) "\t" (hand[m] + 0) "\t" (obs[m] + 0) "\t" (obs[m] - mined[m])
      for (j = 1; j <= nc; j++) r = r "\t" (cell[m, c[j]] + 0)
      print r
    }
  }
' </dev/null >"$work/months.tsv" || fail_closed "an input file is malformed"

grep -v '^#' "$wallclock" | grep -v '^[[:space:]]*$' >"$work/wc.tsv" || :
[ -s "$work/wc.tsv" ] || fail_closed "the wall-clock capture holds no runs"
awk -F'\t' 'NF != 4 || $4 !~ /^[0-9]+$/ || $4 == 0 { bad = 1 } END { exit bad ? 5 : 0 }' "$work/wc.tsv" \
  || fail_closed "the wall-clock capture has a malformed row"

awk -F'\t' -v asof="$as_of" -v wcf="$work/wc.tsv" '
  BEGIN {
    nc = split("lock-concurrency parser-fragility echo-sanitization duplicated-primitive perf-spawn-cost portability lint-gap plugin-delivery test-flakiness instruction-headroom auditability", c, " ")
    while ((getline l < wcf) > 0) { split(l, p, "\t"); run[++nw] = p[1]; cr[nw] = p[2]; sha[nw] = p[3]; s[nw] = p[4] + 0; v[nw] = p[4] + 0 }
    for (i = 2; i <= nw; i++) { x = v[i]; for (j = i - 1; j >= 1 && v[j] > x; j--) v[j + 1] = v[j]; v[j + 1] = x }
    med = (nw % 2) ? v[(nw + 1) / 2] : (v[nw / 2] + v[nw / 2 + 1]) / 2
  }
  { rows[++nr] = $0 }
  END {
    print "# Substrate maintenance-cost baseline, as of " asof
    print ""
    print "Generated by `scripts/substrate-baseline.sh`; do not edit by hand. Regenerate on an"
    print "unchanged tree with:"
    print ""
    print "```sh"
    print "/bin/sh scripts/substrate-baseline.sh --as-of " asof " >docs/substrate/cost-baseline-" asof ".md"
    print "```"
    print ""
    print "Every count stops at the as-of date (UTC). The script header defines each field: the"
    print "commits touching `scripts/` or `githooks/`, the observations recorded (fragments and"
    print "frozen-log lines) split by the pain matrix'\''s classes, the check aggregate'\''s CI"
    print "wall-clock from `docs/substrate/check-wallclock-" asof ".tsv`, and the load-flake"
    print "hand-backs from `docs/substrate/hand-backs.tsv`."
    print ""
    print "## Script-layer commits and hand-backs per month"
    print ""
    print "| month | commits | fix-typed | load-flake hand-backs |"
    print "| --- | ---: | ---: | ---: |"
    for (i = 1; i <= nr; i++) { split(rows[i], f, "\t"); print "| " f[1] " | " f[2] " | " f[3] " | " f[4] " |" }
    print ""
    print "## Observation inflow by class per month"
    print ""
    h = "| month | recorded | outside the mined set |"; sp = "| --- | ---: | ---: |"
    for (j = 1; j <= nc; j++) { h = h " " c[j] " |"; sp = sp " ---: |" }
    print h; print sp
    for (i = 1; i <= nr; i++) {
      split(rows[i], f, "\t")
      r = "| " f[1] " | " f[5] " | " f[6] " |"
      for (j = 1; j <= nc; j++) r = r " " f[6 + j] " |"
      print r
    }
    print ""
    print "## Check aggregate wall-clock"
    print ""
    print "| measure | seconds |"
    print "| --- | ---: |"
    printf "| median of %d runs | %g |\n", nw, med
    printf "| fastest | %d |\n", v[1]
    printf "| slowest | %d |\n", v[nw]
    print ""
    print "| run | created | head | seconds |"
    print "| --- | --- | --- | ---: |"
    for (i = 1; i <= nw; i++) print "| " run[i] " | " cr[i] " | " sha[i] " | " s[i] " |"
  }
' "$work/months.tsv"
