#!/bin/sh
# substrate-baseline.sh — the script layer's maintenance-cost baseline, as a
# dated snapshot regenerable from the tree.
# Emits: markdown
#
# FIELDS, each counted on or before the --as-of date (UTC):
#   commits     per calendar month, the non-merge commits reachable from HEAD
#               touching scripts/ or githooks/, and the fix-typed ones among
#               them (a subject `fix:`, `fix(<scope>):`, or either with `!`).
#               The month is the committer date's, so a squash merge counts
#               when it lands; an as-of date before a branch's own commits
#               keeps the count the same on the branch and after its merge.
#   inflow      per calendar month, the observations recorded: every fragment
#               under the accumulator's entries/ and archive/ by the date its
#               name opens with, plus every dated line of the frozen log. The
#               class columns count the mined set's items by the classes
#               scripts/substrate-attribute.sh assigns them (an item in two
#               classes counts in both). Only the mined set carries classes,
#               so later observations count as outside it, not as zero
#               inflow.
#   wall-clock  the check aggregate's wall-clock on recent successful pushes
#               to main: the ci workflow runs the gate as parallel jobs, the
#               lint job's `mise run check:non-test` step beside one
#               `mise run test -- --shard` step per test shard, so a run's
#               wall-clock is the slowest of those steps, the time the gate's
#               own work kept the `check` status waiting (runner setup and the
#               aggregate's report read excluded). Read from a committed
#               capture (below), as median, min and max seconds over the
#               captured runs. A capture taken before the suite was sharded
#               (its `#` line names the check job's `mise run check` step)
#               timed every gate in one serial step, so its seconds do not
#               compare with a sharded capture's.
#   hand-backs  worker runs ended by a human hand-back that a test-flakiness
#               observation attributes to a load-sensitive test failure,
#               bucketed by the month of that observation: the hand-back
#               record lists each such observation once with the runs it
#               records, and every listed observation must carry the
#               test-flakiness class.
#
# CAPTURE. `--capture-wallclock` prints the wall-clock capture instead: the
# newest --runs (default 10) successful push runs of the ci workflow on main
# created on or before the as-of date, one `run<TAB>created<TAB>sha<TAB>seconds`
# row each, read through `gh` (fewer runs than asked fails, and so does a run
# missing any of those steps, as every run from before the suite was sharded
# is, since its single check step times a different thing). The capture is the
# record of truth: committed, so the snapshot regenerates offline and
# byte-identically, while a later capture for the same date may differ (runs
# re-run or expire).
#
# INPUT FILES (tab-separated, `#` comment lines and blank lines skipped):
#   wall-clock capture   run  created  sha  seconds
#   hand-back record     id  runs  reason
# Inside a git work tree, an uncommitted, untracked or ignored change to the
# accumulator or either input file fails closed however its path is spelt (an
# input file that is a symlink fails closed too), and so does a shallow clone,
# whose history is cut. Every fragment name must open with a real date, and a
# fragment must be a regular file.
#
# Usage: substrate-baseline.sh --as-of <YYYY-MM-DD> [--repo-root <dir>]
#          [--spec <bundle-dir>] [--legacy <tsv>] [--wallclock <tsv>]
#          [--hand-backs <tsv>] [--out <file>]
#        substrate-baseline.sh --capture-wallclock --as-of <YYYY-MM-DD>
#          [--repo-root <dir>] [--runs <n>] [--out <file>]
# Defaults: the repo is this script's parent; the bundle, the accumulator and
# the legacy index are substrate-attribute.sh's defaults; the capture is
# docs/substrate/check-wallclock-<as-of>.tsv; the hand-back record is
# docs/substrate/hand-backs.tsv. --out writes the output to a file, replacing
# it only once the run succeeds.
# Exit codes: 0 written; 2 usage error; 5 fail-closed (an unreadable or
# uncommitted input, a shallow clone, a repo git cannot read, an attribution
# that fails, an empty or malformed capture, a malformed or repeated
# hand-back row or one naming an observation outside the test-flakiness
# class, a repeated wall-clock run or one after the as-of date, a capture
# short of --runs, an undated, impossibly dated or symlinked fragment,
# --out naming a directory, or a failed step); 128 plus the signal
# number on HUP, INT or TERM.
#
# POSIX sh on the macOS + Linux support bar. All input is data.
set -uf

LC_ALL=C
TZ=UTC
export LC_ALL TZ
unset CDPATH
# An inherited git environment (a hook exports it) would point every git call
# below at another repository, or inject configuration into it.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

me=substrate-baseline
script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
repo_root=$(cd "$script_dir/.." && pwd -P) || exit 2

usage() {
  printf '%s\n' "usage: substrate-baseline.sh [--capture-wallclock] --as-of <YYYY-MM-DD> [--repo-root <dir>] [--spec <bundle-dir>] [--legacy <tsv>] [--wallclock <tsv>] [--hand-backs <tsv>] [--runs <n>] [--out <file>]" >&2
  exit 2
}

as_of="" capture=0 spec="" legacy="" wallclock="" handbacks="" runs=10 out=""
while [ "$#" -gt 0 ]; do
  case $1 in
    --capture-wallclock) capture=1 && shift ;;
    --as-of | --repo-root | --spec | --legacy | --wallclock | --hand-backs | --runs | --out)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage
      case $1 in
        --as-of) as_of=$2 ;;
        --repo-root) repo_root=$2 ;;
        --spec) spec=$2 ;;
        --legacy) legacy=$2 ;;
        --wallclock) wallclock=$2 ;;
        --hand-backs) handbacks=$2 ;;
        --runs) runs=$2 ;;
        --out) out=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
# valid_date <YYYY-MM-DD>: a real calendar date (month lengths, leap years).
valid_date() {
  case $1 in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) return 1 ;;
  esac
  vd_y=${1%%-*} vd_m=${1#*-} vd_d=${1##*-}
  vd_m=${vd_m%-*}
  # A leading 1 keeps a zero-padded field from reading as octal.
  vd_y=$((1$vd_y - 10000)) vd_m=$((1$vd_m - 100)) vd_d=$((1$vd_d - 100))
  case $vd_m in
    1 | 3 | 5 | 7 | 8 | 10 | 12) vd_max=31 ;;
    4 | 6 | 9 | 11) vd_max=30 ;;
    2)
      vd_max=28
      if [ $((vd_y % 4)) -eq 0 ] && { [ $((vd_y % 100)) -ne 0 ] || [ $((vd_y % 400)) -eq 0 ]; }; then vd_max=29; fi
      ;;
    *) return 1 ;;
  esac
  [ "$vd_d" -ge 1 ] && [ "$vd_d" -le "$vd_max" ]
}

# A case pattern, unlike a line-wise grep, rejects a value carrying a second
# line or a trailing byte.
valid_date "$as_of" || usage
case $runs in
  [1-9] | [1-9][0-9]) ;;
  *) usage ;;
esac

fail_closed() {
  printf '%s\n' "$me: $1; failing closed rather than writing a baseline" >&2
  exit 5
}

case $repo_root in -*) repo_root=./$repo_root ;; esac
repo_root=$(cd "$repo_root" 2>/dev/null && pwd -P) || fail_closed "the repo root is not a readable directory"

work=$(mktemp -d "${TMPDIR:-/tmp}/substrate-baseline.XXXXXX") || fail_closed "mktemp -d failed"
[ -n "$work" ] && [ -d "$work" ] || fail_closed "mktemp -d produced no directory"
tmp_out=""
trap 'rm -rf "$work"; [ -z "$tmp_out" ] || rm -f "$tmp_out"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# write_out <file>: the finished output, to --out (replaced only now) or stdout.
write_out() {
  if [ -z "$out" ]; then
    cat "$1" || exit 5
    return
  fi
  case $out in -*) out=./$out ;; esac
  [ ! -d "$out" ] || fail_closed "--out names a directory"
  tmp_out=$(mktemp "$out.XXXXXX") || fail_closed "cannot create a file beside --out"
  # mktemp creates the file private; the snapshot gets the mode a plain
  # redirect would.
  if ! chmod "$(printf '%o' $((0666 & ~$(umask))))" "$tmp_out" || ! cat "$1" >"$tmp_out" || ! mv -f "$tmp_out" "$out"; then
    fail_closed "cannot write --out"
  fi
  tmp_out=""
}

if [ "$capture" -eq 1 ]; then
  for tool in gh jq; do
    command -v "$tool" >/dev/null 2>&1 || fail_closed "'$tool' is not on PATH"
  done
  list=$(cd "$repo_root" && gh run list --workflow ci.yml --branch main --event push --status success \
    --created "<=$as_of" --limit 100 --json databaseId,createdAt,headSha) || fail_closed "gh could not list the ci runs"
  picked=$(printf '%s\n' "$list" | jq -r --arg until "${as_of}T23:59:59Z" --argjson n "$runs" '
    [.[] | select(.createdAt <= $until)] | sort_by(.createdAt) | reverse | .[:$n][]
    | "\(.databaseId)\t\(.createdAt)\t\(.headSha)"') || fail_closed "the run list is not the JSON gh prints"
  [ "$(printf '%s\n' "$picked" | grep -c .)" -eq "$runs" ] \
    || fail_closed "fewer than $runs successful push runs of ci on main on or before $as_of"
  # The loop reads a here-document, not a pipe, so its fail_closed ends the
  # script rather than a subshell.
  tab=$(printf '\t')
  : >"$work/capture"
  while IFS=$tab read -r run created sha; do
    # Every gate step must be there: the lint job's one and each of the
    # N shard jobs' one, all N agreeing on N. Anything else, the pre-shard
    # layout's single check step included, prints nothing.
    # shellcheck disable=SC2016 # the $ names are jq variables, not expansions
    secs=$(cd "$repo_root" && gh run view "$run" --json jobs --jq '
      def secs: (.completedAt | fromdateiso8601) - (.startedAt | fromdateiso8601);
      [.jobs[] | select(.name == "lint") | .steps[] | select(.name == "Run mise run check:non-test") | secs] as $lint
      | [.jobs[] | select(.name | test("^test \\(shard [1-9][0-9]*/[1-9][0-9]*\\)$"))] as $shards
      | [$shards[] | .name | capture("/(?<n>[0-9]+)\\)$").n | tonumber] | unique as $ns
      | [$shards[] | [.steps[] | select(.name | startswith("Run mise run test ")) | secs]
         | select(length == 1) | .[0]] as $tests
      | if ($lint | length) == 1 and ($ns | length) == 1
          and ([$shards[] | .name] | unique | length) == $ns[0]
          and ($shards | length) == $ns[0] and ($tests | length) == $ns[0]
        then $lint + $tests | max else empty end') \
      || fail_closed "gh could not read run $run"
    case $run in *[!0-9]* | "") fail_closed "a run id is not numeric" ;; esac
    case $created in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
      *) fail_closed "run $run has a malformed creation time" ;;
    esac
    printf '%s\n' "$sha" | grep -Eq '^[0-9a-f]{40}$' || fail_closed "run $run has a malformed head"
    printf '%s\n' "$secs" | grep -Eq '^[1-9][0-9]*$' || fail_closed "run $run lacks the timed lint and test shard steps of the sharded ci layout"
    printf '%s\t%s\t%s\t%s\n' "$run" "$created" "$sha" "$secs" >>"$work/capture" || fail_closed "the capture could not be written"
  done <<EOF
$picked
EOF
  {
    # shellcheck disable=SC2016 # the backticks are literal Markdown, not a substitution
    printf '# ci workflow, slowest of the lint and test shard gate steps: successful pushes to main\n'
    printf '# run\tcreated\tsha\tseconds\n'
    cat "$work/capture"
  } >"$work/out" || fail_closed "the capture could not be written"
  write_out "$work/out"
  exit 0
fi

[ -n "$wallclock" ] || wallclock=$repo_root/docs/substrate/check-wallclock-$as_of.tsv
[ -n "$handbacks" ] || handbacks=$repo_root/docs/substrate/hand-backs.tsv
[ -r "$wallclock" ] || fail_closed "the wall-clock capture is unreadable"
[ -r "$handbacks" ] || fail_closed "the hand-back record is unreadable"
git -C "$repo_root" rev-parse --verify --quiet HEAD >/dev/null || fail_closed "git cannot read the repo's HEAD"
[ "$(git -C "$repo_root" rev-parse --is-shallow-repository)" = false ] || fail_closed "the clone is shallow"

set -- --as-of "$as_of" --repo-root "$repo_root"
[ -z "$spec" ] || set -- "$@" --spec "$spec"
obs_dir=$(/bin/sh "$script_dir/substrate-attribute.sh" "$@" --obs-dir) || fail_closed "the accumulator does not resolve"
# Resolved once: the class map below reuses the bundle the accumulator came from.
[ -n "$spec" ] || set -- "$@" --spec "$(dirname "$obs_dir")/universal-binary"
[ -z "$legacy" ] || set -- "$@" --legacy "$legacy"
/bin/sh "$script_dir/substrate-attribute.sh" "$@" --class-map >"$work/classes.tsv" || fail_closed "the attribution class map failed"
/bin/sh "$script_dir/substrate-attribute.sh" --classes >"$work/class-list" || fail_closed "the class list failed"

# canon <path>: the physical absolute path, so a relative input or one under
# a symlinked directory is still recognised as inside the repo. A file input
# that is itself a symlink does not resolve: its target could sit anywhere.
canon() {
  if [ -d "$1" ]; then
    (cd -P -- "$1" 2>/dev/null && pwd -P)
  else
    [ ! -h "$1" ] || return 1
    cn_dir=$(cd -P -- "$(dirname -- "$1")" 2>/dev/null && pwd -P) || return 1
    printf '%s/%s\n' "$cn_dir" "$(basename -- "$1")"
  fi
}

# rel <path>: the path as the snapshot prints it, relative to the repo when
# inside it.
rel() {
  case $1 in
    "$repo_root"/*) printf '%s\n' "${1#"$repo_root"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

wallclock=$(canon "$wallclock") || fail_closed "the wall-clock capture path is a symlink or does not resolve"
handbacks=$(canon "$handbacks") || fail_closed "the hand-back record path is a symlink or does not resolve"
for p in "$obs_dir" "$wallclock" "$handbacks"; do
  p=$(canon "$p") || fail_closed "an input path is a symlink or does not resolve"
  case $p in
    "$repo_root"/*)
      dirty=$(git --literal-pathspecs -C "$repo_root" status --porcelain --untracked-files=all --ignored=matching -- "$p") \
        || fail_closed "git cannot read the state of an input"
      [ -z "$dirty" ] || fail_closed "an input has uncommitted changes (commit it, then regenerate)"
      ;;
  esac
done

git -C "$repo_root" log --no-merges --no-show-signature --until="${as_of}T23:59:59Z" --date=format-local:%Y-%m \
  --format='%cd%x09%s' -- scripts githooks >"$work/commits.tsv" || fail_closed "git log failed"

# Every dated observation: fragments by file name, frozen-log lines by prefix.
: >"$work/dates"
set +f
for f in "$obs_dir"/entries/*.md "$obs_dir"/archive/*.md; do
  [ -e "$f" ] || [ -h "$f" ] || continue
  if [ -h "$f" ] || [ ! -f "$f" ]; then
    set -f
    fail_closed "a fragment is a symlink or not a regular file"
  fi
  b=${f##*/}
  case $b in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*) printf '%s\n' "${b%"${b#??????????}"}" >>"$work/dates" ;;
    *)
      set -f
      fail_closed "a fragment name opens with no date"
      ;;
  esac
done
set -f
[ ! -h "$obs_dir/opportunities.md" ] || fail_closed "the frozen log opportunities.md is a symlink"
grep -E '^- [0-9]{4}-[0-9]{2}-[0-9]{2} ' "$obs_dir/opportunities.md" >"$work/legacy-lines"
[ "$?" -le 1 ] || fail_closed "the frozen log could not be read"
cut -c3-12 "$work/legacy-lines" >>"$work/dates" || fail_closed "the frozen log dates could not be read"

grep -v '^#' "$wallclock" | grep -v '^[[:space:]]*$' >"$work/wc.tsv"
[ -s "$work/wc.tsv" ] || fail_closed "the wall-clock capture holds no runs"

SB_CLASSES=$work/classes.tsv SB_CLASS_LIST=$work/class-list SB_COMMITS=$work/commits.tsv
SB_DATES=$work/dates SB_HANDBACKS=$handbacks SB_WC=$work/wc.tsv
SB_WC_SHOWN=$(rel "$wallclock") SB_HB_SHOWN=$(rel "$handbacks")
export SB_CLASSES SB_CLASS_LIST SB_COMMITS SB_DATES SB_HANDBACKS SB_WC SB_WC_SHOWN SB_HB_SHOWN

awk -F'\t' -v asof="$as_of" '
  function clean(s) { gsub(/[^[:print:]]/, "", s); return s }
  function valid_date(d,   y, m, dd, mx) {
    if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
    y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
    if (m < 1 || m > 12 || dd < 1) return 0
    mx = (m == 4 || m == 6 || m == 9 || m == 11) ? 30 : 31
    if (m == 2) mx = ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0) ? 29 : 28
    return dd <= mx
  }
  function load(f, arr,   n, l, r) {
    while ((r = (getline l < f)) > 0) arr[++n] = l
    if (r < 0) { print "an intermediate file could not be read" > "/dev/stderr"; bad = 1 }
    return n
  }
  function note_earliest(m) { if (m < first) first = m }
  function next_month(m,   y, mo) {
    y = substr(m, 1, 4) + 0; mo = substr(m, 6, 2) + 1
    if (mo > 12) { mo = 1; y++ }
    return sprintf("%04d-%02d", y, mo)
  }
  BEGIN {
    nc = load(ENVIRON["SB_CLASS_LIST"], c)
    amonth = substr(asof, 1, 7); first = amonth
    n = load(ENVIRON["SB_CLASSES"], lines)
    for (i = 1; i <= n; i++) {
      split(lines[i], p, "\t"); if (p[2] > asof) continue
      m = substr(p[2], 1, 7); mined[m]++; note_earliest(m); idm[p[1]] = m; idc[p[1]] = p[3]
      k = split(p[3], kk, ",")
      for (j = 1; j <= k; j++) cell[m, kk[j]]++
    }
    n = load(ENVIRON["SB_COMMITS"], lines)
    for (i = 1; i <= n; i++) {
      split(lines[i], p, "\t"); m = p[1]; note_earliest(m); all[m]++
      if (p[2] ~ /^fix(\([^)]*\))?!?: /) fix[m]++
    }
    n = load(ENVIRON["SB_DATES"], lines)
    for (i = 1; i <= n; i++) {
      d = lines[i]
      if (!valid_date(d)) {
        print "an observation carries an impossible date: " clean(d) > "/dev/stderr"; bad = 1; break
      }
      if (d > asof) continue
      m = substr(d, 1, 7); note_earliest(m); obs[m]++
    }
    n = load(ENVIRON["SB_HANDBACKS"], lines)
    for (i = 1; i <= n; i++) {
      l = lines[i]
      if (l ~ /^#/ || l ~ /^[ \t]*$/) continue
      k = split(l, p, "\t")
      if (k != 3 || p[2] !~ /^[1-9][0-9]*$/ || p[3] == "") { print "malformed hand-back row: " clean(p[1]) > "/dev/stderr"; bad = 1; break }
      if (p[1] in seen) { print "repeated hand-back row: " clean(p[1]) > "/dev/stderr"; bad = 1; break }
      seen[p[1]] = 1
      if (!(p[1] in idm)) { print "hand-back row outside the mined set: " clean(p[1]) > "/dev/stderr"; bad = 1; break }
      if (("," idc[p[1]] ",") !~ /,test-flakiness,/) { print "hand-back row outside the test-flakiness class: " clean(p[1]) > "/dev/stderr"; bad = 1; break }
      hand[idm[p[1]]] += p[2]
    }
    nw = load(ENVIRON["SB_WC"], lines)
    for (i = 1; i <= nw; i++) {
      split(lines[i], p, "\t")
      if (split(lines[i], q, "\t") != 4 || p[1] !~ /^[0-9]+$/ || p[2] !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ || p[3] !~ /^[0-9a-f]+$/ || length(p[3]) != 40 || p[4] !~ /^[1-9][0-9]*$/) {
        print "malformed wall-clock row: " clean(p[1]) > "/dev/stderr"; bad = 1; break
      }
      if (p[1] in runseen) { print "repeated wall-clock run: " p[1] > "/dev/stderr"; bad = 1; break }
      runseen[p[1]] = 1
      if (!valid_date(substr(p[2], 1, 10))) { print "wall-clock run with an impossible date: " p[1] > "/dev/stderr"; bad = 1; break }
      if (substr(p[2], 1, 10) > asof) { print "wall-clock run after the as-of date: " p[1] > "/dev/stderr"; bad = 1; break }
      run[i] = p[1]; created[i] = p[2]; head[i] = p[3]; secs[i] = p[4] + 0; sorted[i] = p[4] + 0
    }
    if (bad) exit 5
    for (i = 2; i <= nw; i++) { x = sorted[i]; for (j = i - 1; j >= 1 && sorted[j] > x; j--) sorted[j + 1] = sorted[j]; sorted[j + 1] = x }
    med = (nw % 2) ? sorted[(nw + 1) / 2] : (sorted[nw / 2] + sorted[nw / 2 + 1]) / 2

    print "# Substrate maintenance-cost baseline, as of " asof
    print ""
    print "Generated by `scripts/substrate-baseline.sh`; do not edit by hand. Regenerate on an"
    print "unchanged tree with:"
    print ""
    print "```sh"
    print "/bin/sh scripts/substrate-baseline.sh --as-of " asof " --out docs/substrate/cost-baseline-" asof ".md"
    print "```"
    print ""
    print "Every count stops at the as-of date (UTC). The script header defines each field: the"
    print "commits touching `scripts/` or `githooks/`, the observations recorded (fragments and"
    print "frozen-log lines) split by the pain matrix'\''s classes, the check aggregate'\''s CI"
    print "wall-clock from `" clean(ENVIRON["SB_WC_SHOWN"]) "`, and the load-flake hand-backs from"
    print "`" clean(ENVIRON["SB_HB_SHOWN"]) "`. Only the pain matrix'\''s mined set"
    print "carries classes, so an observation recorded after it was mined counts as outside"
    print "the mined set: a zero class cell in a later month means unclassified, not no inflow."
    print "The drafting-session figures in the universal-binary bundle'\''s Sources were counted"
    print "under definitions the bundle does not record; this snapshot counts by the script"
    print "header'\''s definitions and supersedes them."
    print ""
    print "## Script-layer commits and hand-backs per month"
    print ""
    print "| month | commits | fix-typed | load-flake hand-backs |"
    print "| --- | ---: | ---: | ---: |"
    for (m = first; m <= amonth; m = next_month(m))
      print "| " m " | " (all[m] + 0) " | " (fix[m] + 0) " | " (hand[m] + 0) " |"
    print ""
    print "## Observation inflow by class per month"
    print ""
    h = "| month | recorded | outside the mined set |"; sp = "| --- | ---: | ---: |"
    for (j = 1; j <= nc; j++) { h = h " " c[j] " |"; sp = sp " ---: |" }
    print h; print sp
    for (m = first; m <= amonth; m = next_month(m)) {
      r = "| " m " | " (obs[m] + 0) " | " (obs[m] - mined[m]) " |"
      for (j = 1; j <= nc; j++) r = r " " (cell[m, c[j]] + 0) " |"
      print r
    }
    print ""
    print "## Check aggregate wall-clock"
    print ""
    print "| measure | seconds |"
    print "| --- | ---: |"
    printf "| median of %d runs | %g |\n", nw, med
    printf "| fastest | %d |\n", sorted[1]
    printf "| slowest | %d |\n", sorted[nw]
    print ""
    print "| run | created | head | seconds |"
    print "| --- | --- | --- | ---: |"
    for (i = 1; i <= nw; i++) print "| " run[i] " | " created[i] " | " head[i] " | " secs[i] " |"
  }
' >"$work/out" || fail_closed "an input file is malformed or the baseline could not be rendered"
write_out "$work/out"
