#!/bin/bash
# Tests for scripts/refresh-test-durations-ci.sh, read offline through --from:
# each run's shard reports merge into one whole-suite source, a run missing a
# shard or holding a mismatched set is skipped, and the table takes each
# file's median over the usable runs.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/refresh-test-durations-ci.sh"

failures=0
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (missing '$2' in: $3)" >&2
      failures=$((failures + 1))
      ;;
  esac
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-refresh-ci.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

suite="$tmp/suite"
mkdir -p "$suite"
for n in a b c; do
  printf '#!/bin/bash\nexit 0\n' >"$suite/test-$n.sh"
done

# shard <run> <i>/<N> <name>=<seconds>... — one shard's report, laid out as
# `gh run download` leaves it.
shard() {
  _d="$tmp/runs/$1/timing-report-${2%/*}"
  mkdir -p "$_d"
  {
    printf 'planwright-test-timing\t2\tclock=fixture\tjobs=4\tpool=4\tshard=%s\n' "$2"
    shift 2
    for _e in "$@"; do
      printf 'file\t%s\t%s\t0.000\n' "${_e%%=*}" "${_e#*=}"
    done
    printf 'suite\twall\t5\n'
  } >"$_d/timing-report.tsv"
}

run() {
  /bin/bash "$SCRIPT" --from "$tmp/runs" --suite "$suite" --out "$tmp/table.tsv" >"$tmp/out" 2>&1
  echo "$?" >"$tmp/rc"
}
row() { awk -F'\t' -v n="$1" '$1 == n { print $2 }' "$tmp/table.tsv"; }

# 1. Three runs, two shards each, with different shard counts across runs:
#    every file takes its median.
shard 101 1/2 test-a.sh=10 test-b.sh=1
shard 101 2/2 test-c.sh=4
shard 102 1/3 test-a.sh=12
shard 102 2/3 test-b.sh=3
shard 102 3/3 test-c.sh=2
shard 103 1/2 test-a.sh=20 test-c.sh=6
shard 103 2/2 test-b.sh=2
run
assert_eq "three complete runs refresh the table" 0 "$(cat "$tmp/rc")"
assert_contains "the refresh names its source count" "from 3 sources" "$(cat "$tmp/out")"
assert_eq "test-a.sh takes its median" 12 "$(row test-a.sh)"
assert_eq "test-b.sh takes its median" 2 "$(row test-b.sh)"
assert_eq "test-c.sh takes its median" 4 "$(row test-c.sh)"

# 2. A run missing a shard, or naming one twice, or mixing shard counts, is
#    skipped with its reason; the rest still refresh.
shard 104 1/3 test-a.sh=99
shard 104 3/3 test-c.sh=99 test-b.sh=99
shard 105 1/2 test-a.sh=99
shard 105 2/3 test-b.sh=99 test-c.sh=99
mkdir -p "$tmp/runs/106"
shard 107 1/2 test-a.sh=99
shard 107 2/2 test-b.sh=99 test-c.sh=99
mkdir -p "$tmp/runs/107/timing-report-1b"
cp "$tmp/runs/107/timing-report-1/timing-report.tsv" "$tmp/runs/107/timing-report-1b/"
run
assert_eq "bad runs do not stop the refresh" 0 "$(cat "$tmp/rc")"
assert_contains "a missing shard is named" "run 104: shard 2 of 3 is missing, skipped" "$(cat "$tmp/out")"
assert_contains "mixed shard counts are named" "run 105: its reports disagree on the shard count, skipped" "$(cat "$tmp/out")"
assert_contains "a run without reports is named" "run 106: no timing reports, skipped" "$(cat "$tmp/out")"
assert_contains "a repeated shard is named" "run 107: shard 1 appears twice, skipped" "$(cat "$tmp/out")"
assert_eq "a skipped run moves no median" 12 "$(row test-a.sh)"

# 3. A report without a shard header is not one shard of a run.
rm -rf "$tmp/runs"
shard 201 1/1 test-a.sh=1 test-b.sh=1 test-c.sh=1
r="$tmp/runs/201/timing-report-1/timing-report.tsv"
awk -F'\t' -v OFS='\t' 'NR == 1 { NF = 5 } { print }' "$r" >"$r.new" && mv "$r.new" "$r"
run
assert_eq "no usable run fails" 2 "$(cat "$tmp/rc")"
assert_contains "the unsharded report is named" "not a version 2 shard report" "$(cat "$tmp/out")"
assert_contains "the failure says no run was usable" "no run with a complete set of shard reports" "$(cat "$tmp/out")"

# 4. Without --from, through a stub gh: a run whose shard jobs did not all
#    pass, or that has none, is never downloaded, and the scan stops once it
#    has --runs green runs.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$GH_LOG"
case "$1 $2" in
  'run list') printf '301\n302\n303\n304\n305\n' ;;
  'run view')
    case "$3" in
      302) echo red ;;
      303) echo none ;;
      *) echo green ;;
    esac
    ;;
  'run download')
    id="$3"
    d=""
    while [ "$#" -gt 0 ]; do
      [ "$1" = --dir ] && d="$2"
      shift
    done
    mkdir -p "$d/timing-report-1"
    printf 'planwright-test-timing\t2\tshard=1/1\nfile\ttest-a.sh\t7\t0\nfile\ttest-b.sh\t%s\t0\nfile\ttest-c.sh\t7\t0\nsuite\twall\t9\n' "${id#30}" \
      >"$d/timing-report-1/timing-report.tsv"
    ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/gh"
: >"$tmp/gh.log"
GH_LOG="$tmp/gh.log" PATH="$tmp/bin:$PATH" /bin/bash "$SCRIPT" --runs 2 --suite "$suite" --out "$tmp/table.tsv" >"$tmp/out" 2>&1
assert_eq "the gh path refreshes the table" 0 "$?"
assert_eq "the gh path asks for four times --runs" 1 "$(grep -c -- '--limit 8' "$tmp/gh.log")"
assert_eq "only green runs are downloaded, up to --runs" "301 304" \
  "$(awk '$1 == "run" && $2 == "download" { printf "%s%s", sep, $3; sep = " " }' "$tmp/gh.log")"
assert_eq "the scan stops at --runs" 0 "$(grep -c '^run view 305' "$tmp/gh.log")"
assert_eq "the table takes the downloaded times" 7 "$(row test-a.sh | awk '{ print $1 + 0 }')"
assert_eq "a full sample does not warn" 0 "$(grep -c 'requested runs' "$tmp/out")"
# Asking for more green runs than the scan finds still refreshes, and says so.
GH_LOG="$tmp/gh.log" PATH="$tmp/bin:$PATH" /bin/bash "$SCRIPT" --runs 5 --suite "$suite" --out "$tmp/table.tsv" >"$tmp/out" 2>&1
assert_eq "a short sample still refreshes the table" 0 "$?"
assert_contains "a short sample warns with its count" "3 of the 5 requested runs" "$(cat "$tmp/out")"

# 5. Usage.
/bin/bash "$SCRIPT" --runs 0 --from "$tmp/runs" >/dev/null 2>&1
assert_eq "--runs 0 is a usage error" 2 "$?"
/bin/bash "$SCRIPT" --from "$tmp/no-such-dir" >/dev/null 2>&1
assert_eq "a missing --from directory fails" 2 "$?"
/bin/bash "$SCRIPT" --bogus >/dev/null 2>&1
assert_eq "an unknown argument is a usage error" 2 "$?"

if [ "$failures" -gt 0 ]; then
  echo "$failures assertion(s) failed" >&2
  exit 1
fi
echo "all refresh-test-durations-ci assertions passed"
