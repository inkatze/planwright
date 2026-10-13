#!/bin/sh
# review-backtest.sh — replay the review backtest corpus through one review
# pass and score its recall per class (review-effectiveness REQ-H1.2,
# REQ-H1.3, REQ-C1.1, D-7, D-9).
#
# ON DEMAND, NEVER CI: a real replay spends model tokens. It is registered as
# an `eval:` task so check:no-ci-evals keeps it out of CI; its mechanics are
# tested offline through the reviewer-stub seam.
#
# THE SAMPLE. Rows marked unreplayable are excluded first and counted. For
# each targeted class (a class is a row's miss reason; when --classes is
# absent, every class holding a replayable row, the others reported as not
# sampled) the replayable rows are ordered by the POSIX cksum of
# "<seed>:<id>" and the first <cap> taken, so a class's sample depends only on
# the seed, the cap, and the corpus, never on which other classes run. A
# sample with zero replayable rows overall, or in a targeted class, is
# refused. The cap (default 5) and seed are printed and recorded.
#
# ONE ROW, ONE PASS. Each sampled row's pre-fix commit is checked out into an
# isolated copy: a fresh clone of a temporary bare mirror of the remote, with
# no remote left to push to, removed on exit. The change under review, `git
# diff <base>...<commit>`, is written beside the copy. The reviewer runs with
# the copy as its working directory and is told, through the environment, the
# redirected home and state home any command it executes must use; the
# reviewing session itself keeps its own home and credentials. A
# `declined`-class row gets its recorded dismissal seeded into a coordinator
# ledger file (BACKTEST_LEDGER), the loop ledger a real pass would hold; no
# other row has one.
#
# A ROW ENDS IN ERROR, and the run exits 4, when its setup fails (the clone,
# the checkout, or a commit sharing no history with main, which leaves no base
# to diff against; the refresh marks such rows unreplayable) or when the
# reviewer exits non-zero twice, the retry waiting PLANWRIGHT_BACKTEST_RETRY_WAIT
# seconds (default 30) first. An error row is recorded as a row but left out of
# its class's counts, never scored as a miss and never dropped, and a result
# holding one cannot serve as a baseline. The corpus must pass review-corpus-screen.sh first.
#
# THE REVIEWER is an executable run once per row with these variables set:
#   BACKTEST_ROW         the row id
#   BACKTEST_HEAD        the pre-fix commit (the copy's HEAD)
#   BACKTEST_BASE        the merge base of that commit with the remote's main
#   BACKTEST_DIFF        the file holding the diff from the base to the head
#   BACKTEST_HOME        the redirected home for executed commands
#   BACKTEST_STATE_HOME  the redirected machine-local state home
#   BACKTEST_LEDGER      the coordinator ledger, declined rows only
#   BACKTEST_MODEL       the --model value
#   BACKTEST_PLANWRIGHT_ROOT  the planwright checkout whose doctrine is "today's"
#   BACKTEST_USAGE_FILE  where the reviewer may write the attempt's token count
# It prints one finding per line as `<path><TAB><line>[<TAB><anything>]`. The
# default is review-backtest-reviewer.sh beside this script. --reviewer-stub
# replaces it with recorded findings, `<row id><TAB><path><TAB><line>` per
# line, which is how the tests run offline.
#
# THE CATCH RULE. A row is caught when any finding cites its file within 10
# lines of its line (review-backtest-lib.sh holds the constant). Recall per
# class is caught over sampled.
#
# THE GATE. --baseline names an earlier result. Its corpus version and model
# must equal this run's, or the comparison is refused (exit 3) and the baseline
# must be re-run; its seed and cap are reused, and a different --seed or --cap
# is refused, since a failed gate is never re-rolled. A baseline whose seed,
# cap, class counts, or rows are malformed, or that holds an error row, is
# refused. The run exits 1 when any targeted class catches fewer sampled rows
# than the baseline did; a targeted class the baseline has no line for is
# named on stderr and not compared, since there is nothing to fall below.
#
# THE RESULT (--out) is tab-separated key lines: `review-backtest 1`, `corpus`,
# `model`, `seed`, `cap`, `plugin_commit`, `classes`, `excluded_unreplayable`,
# `tokens_total` (the sum the reviewer reported over every attempt, 0 for the
# stub), then `class <name> <sampled> <caught>` and `row <id> <class>
# caught|missed|error`. A result is also a baseline.
#
# Usage:
#   review-backtest.sh --corpus <dir>/v<N> --model <id>
#       [--reviewer <executable> | --reviewer-stub <file>]
#       [--classes <c1,c2,...>] [--cap <n>] [--seed <n>] [--baseline <file>]
#       [--remote <url-or-path>] [--out <file>] [--jobs <n>]
#
#   --remote  default: this checkout's origin URL
#   --jobs    rows replayed at once, default 1
#
# Exit codes: 0 replay done (gate passed when a baseline was given); 1 a
#   targeted class dropped below its baseline; 2 usage, a refused sample, or a
#   malformed baseline; 3 a baseline from another model or corpus version; 4 a
#   row ended in error.
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

prog=review-backtest
here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
# shellcheck source=scripts/review-backtest-lib.sh
. "$here/review-backtest-lib.sh"

usage() {
  cat >&2 <<EOF
usage: $prog --corpus <dir>/v<N> --model <id>
         [--reviewer <executable> | --reviewer-stub <file>]
         [--classes <c1,c2,...>] [--cap <n>] [--seed <n>] [--baseline <file>]
         [--remote <url-or-path>] [--out <file>] [--jobs <n>]
EOF
  exit 2
}
die() {
  printf '%s\n' "$prog: $2" >&2
  exit "$1"
}

corpus=
model=
reviewer=$here/review-backtest-reviewer.sh
stub=
classes=
cap=
seed=
baseline=
remote=
out=
jobs=1
while [ $# -gt 0 ]; do
  case $1 in
    --corpus | --model | --reviewer | --reviewer-stub | --classes | --cap | --seed | --baseline | --remote | --out | --jobs)
      [ $# -ge 2 ] || usage
      case $1 in
        --corpus) corpus=$2 ;;
        --model) model=$2 ;;
        --reviewer) reviewer=$2 ;;
        --reviewer-stub) stub=$2 ;;
        --classes) classes=$2 ;;
        --cap) cap=$2 ;;
        --seed) seed=$2 ;;
        --baseline) baseline=$2 ;;
        --remote) remote=$2 ;;
        --out) out=$2 ;;
        --jobs) jobs=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done

[ -n "$corpus" ] || usage
[ -n "$model" ] || die 2 "--model is required: a recall figure means nothing without the model that produced it"
case $model in
  *[!A-Za-z0-9._:-]*) die 2 "--model may hold only letters, digits, and . _ : -" ;;
  *[0-9]*) ;;
  *) die 2 "--model must be the full model id, never an alias a later model could answer to" ;;
esac
corpus=${corpus%/}
version=${corpus##*/}
case $version in
  v[1-9] | v[1-9]*[0-9]) rbt_is_uint "${version#v}" || die 2 "the corpus directory must be named v<N>" ;;
  *) die 2 "the corpus directory must be named v<N>" ;;
esac
[ -f "$corpus/corpus.tsv" ] || die 2 "no corpus.tsv in the corpus directory"
[ "$(sed -n 1p "$corpus/corpus.tsv")" = "$RBT_HEADER" ] || die 2 "the corpus header does not match the schema"
# Every field below reaches git or a reviewer, so a row the schema screen
# refuses (a commit that is not a 40-hex id, a path that escapes) stops the run.
"$here/review-corpus-screen.sh" "$corpus/corpus.tsv" >/dev/null 2>&1 \
  || die 2 "the corpus fails its schema screen; run review-corpus-screen.sh on it"
rbt_is_uint "$jobs" || die 2 "--jobs must be a positive integer"
retry_wait=${PLANWRIGHT_BACKTEST_RETRY_WAIT:-30}
case $retry_wait in '' | *[!0-9]*) die 2 "PLANWRIGHT_BACKTEST_RETRY_WAIT must be a whole number of seconds" ;; esac
if [ -n "$stub" ]; then
  [ -f "$stub" ] && [ -r "$stub" ] || die 2 "the reviewer stub is not readable"
else
  [ -x "$reviewer" ] && [ -f "$reviewer" ] || die 2 "the reviewer is not an executable file"
  # The reviewer runs from inside the copy, so a relative path must not be
  # resolved there.
  case $reviewer in
    /*) ;;
    *) reviewer=$(cd "$(dirname "$reviewer")" && pwd)/$(basename "$reviewer") ;;
  esac
fi
if [ -n "$out" ]; then
  out_dir=$(dirname "$out")
  [ -d "$out_dir" ] && [ -w "$out_dir" ] || die 2 "the --out directory does not exist or is not writable"
fi

# --- the baseline: its seed and cap are this run's ---------------------------

kv() { awk -F '\t' -v k="$1" '$1 == k { print $2; exit }' "$2"; }
if [ -n "$baseline" ]; then
  [ -f "$baseline" ] && [ -r "$baseline" ] || die 2 "the baseline is not readable"
  [ "$(kv review-backtest "$baseline")" = 1 ] || die 2 "the baseline is not a review-backtest result"
  b_corpus=$(kv corpus "$baseline")
  b_model=$(kv model "$baseline")
  b_seed=$(kv seed "$baseline")
  b_cap=$(kv cap "$baseline")
  case $b_seed in '' | *[!0-9]*) die 2 "the baseline's seed is missing or not a number" ;; esac
  rbt_is_uint "$b_cap" || die 2 "the baseline's cap is missing or not a positive integer"
  awk -F '\t' '$1 == "row" && $4 == "error" { exit 1 }' "$baseline" \
    || die 2 "the baseline holds error rows; re-run it until every row scores"
  awk -F '\t' '$1 == "class" { if (NF != 4 || $3 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/ || ($2 in seen)) bad = 1; seen[$2] = 1 }
    END { exit bad }' "$baseline" || die 2 "the baseline's class lines are malformed or repeated"
  [ "$b_corpus" = "$version" ] \
    || die 3 "the baseline was recorded on another corpus version; re-run the baseline on this one"
  [ "$b_model" = "$model" ] \
    || die 3 "the baseline was recorded on another model; a cross-model comparison is refused, re-run the baseline"
  if [ -n "$seed" ] && [ "$seed" != "$b_seed" ]; then
    die 2 "--seed differs from the baseline's; a gate is never re-rolled with a new seed"
  fi
  if [ -n "$cap" ] && [ "$cap" != "$b_cap" ]; then
    die 2 "--cap differs from the baseline's"
  fi
  seed=$b_seed
  cap=$b_cap
fi
[ -n "$cap" ] || cap=$RBT_DEFAULT_CAP
rbt_is_uint "$cap" || die 2 "--cap must be a positive integer"
if [ -z "$seed" ]; then
  seed=$(date +%s)
fi
case $seed in
  '' | *[!0-9]*) die 2 "--seed must be a non-negative integer" ;;
esac

# --- the targeted classes ----------------------------------------------------

present=$(awk -F '\t' 'NR > 1 && $0 != "" { print $7 }' "$corpus/corpus.tsv" | sort -u | tr '\n' ' ')
[ -n "$present" ] || die 2 "the corpus holds no rows"
if [ -n "$classes" ]; then
  targets=$(printf '%s\n' "$classes" | tr ',' '\n' | awk 'NF && !seen[$0]++' | tr '\n' ' ')
  [ -n "$targets" ] || die 2 "--classes names no class"
  for c in $targets; do
    rbt_in_list "$c" "$RBT_REASONS" || die 2 "unknown class (not a miss reason)"
  done
else
  # The full sample targets every class holding a replayable row; a class whose
  # rows are all unreplayable is reported, not sampled.
  targets=$(awk -F '\t' 'NR > 1 && $8 == "yes" { print $7 }' "$corpus/corpus.tsv" | sort -u | tr '\n' ' ')
  for c in $present; do
    rbt_in_list "$c" "$targets" || printf '%s\n' "$prog: class $c has no replayable rows; not sampled" >&2
  done
fi

# Read before any row runs: the checkout may move while a long replay is going.
plugin_commit=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null) || plugin_commit=unknown
tmp=$(mktemp -d "${TMPDIR:-/tmp}/rbt-replay.XXXXXX")
pids=
# Background row jobs ignore an interrupt in a non-interactive shell, so the
# trap sends them TERM, which each row passes on to its reviewer, before the
# directory they work in is removed.
trap 'rm -rf "$tmp"' EXIT
# shellcheck disable=SC2086 # pids is a list of integers
trap '[ -z "$pids" ] || { kill $pids 2>/dev/null; wait; }; exit 130' INT
# shellcheck disable=SC2086 # pids is a list of integers
trap '[ -z "$pids" ] || { kill $pids 2>/dev/null; wait; }; exit 143' TERM

excluded=$(awk -F '\t' 'NR > 1 && $8 == "no"' "$corpus/corpus.tsv" | wc -l | tr -d ' ')
replayable=$(awk -F '\t' 'NR > 1 && $8 == "yes"' "$corpus/corpus.tsv" | wc -l | tr -d ' ')
[ "$replayable" -gt 0 ] || die 2 "zero replayable rows in the corpus after excluding $excluded unreplayable; refused"

: >"$tmp/sample.tsv"
for c in $targets; do
  awk -F '\t' -v c="$c" 'NR > 1 && $7 == c && $8 == "yes"' "$corpus/corpus.tsv" >"$tmp/class.tsv"
  if [ ! -s "$tmp/class.tsv" ]; then
    die 2 "zero replayable rows in targeted class $c; refused"
  fi
  while IFS= read -r line; do
    id=${line%%"	"*}
    crc=$(printf '%s:%s' "$seed" "$id" | cksum | cut -d ' ' -f1)
    printf '%s\t%s\n' "$crc" "$line"
  done <"$tmp/class.tsv" | sort -t '	' -k1,1n -k2,2 | head -n "$cap" | cut -f2- >>"$tmp/sample.tsv"
done
sampled=$(wc -l <"$tmp/sample.tsv" | tr -d ' ')

printf '%s\n' "$prog: corpus $version, model $model"
printf '%s\n' "cap: $cap"
printf '%s\n' "seed: $seed"
printf '%s\n' "excluded unreplayable: $excluded"
printf '%s\n' "sampled: $sampled"

# --- the mirror: the remote's main plus every sampled PR head ----------------

if [ -z "$stub" ]; then
  if [ -z "$remote" ]; then
    remote=$(git -C "$repo_root" remote get-url origin 2>/dev/null) || die 2 "no --remote and no origin in this checkout"
  fi
  case $remote in -*) die 2 "--remote may not begin with a dash" ;; esac
  mirror=$tmp/mirror.git
  git init -q --bare "$mirror"
  # A clone then checks out main whatever the host's init.defaultBranch is.
  git -C "$mirror" symbolic-ref HEAD refs/heads/main
  git -C "$mirror" fetch -q --no-tags "$remote" "+refs/heads/main:refs/heads/main" \
    || die 2 "could not fetch main from the remote"
  # A PR head the remote no longer has leaves its rows to fail their checkout
  # as error rows rather than stopping the whole replay.
  git ls-remote "$remote" 'refs/pull/*/head' >"$tmp/heads.txt" 2>/dev/null || die 2 "git ls-remote failed against the remote"
  cut -f2 "$tmp/sample.tsv" | sort -un >"$tmp/prs.txt"
  refspecs=$(awk -F '\t' 'FILENAME == ARGV[1] { want[$1] = 1; next }
    { n = $2; sub(/^refs\/pull\//, "", n); sub(/\/head$/, "", n); if (n in want) printf "+refs/pull/%s/head:refs/backtest/pr/%s ", n, n }' \
    "$tmp/prs.txt" "$tmp/heads.txt")
  if [ -n "$refspecs" ]; then
    # shellcheck disable=SC2086 # refspecs are built from integers and fixed text
    git -C "$mirror" fetch -q --no-tags "$remote" $refspecs || die 2 "could not fetch the sampled PR heads from the remote"
  fi
fi

# --- replay -------------------------------------------------------------------

replay_row() {
  # replay_row <row line> — print `<id>\t<class>\t<verdict>\t<tokens>`.
  id=$(printf '%s\n' "$1" | cut -f1)
  commit=$(printf '%s\n' "$1" | cut -f3)
  path=$(printf '%s\n' "$1" | cut -f4)
  line=$(printf '%s\n' "$1" | cut -f5)
  class=$(printf '%s\n' "$1" | cut -f7)
  dismissal=$(printf '%s\n' "$1" | cut -f11)
  rdir=$tmp/rows/$id
  mkdir -p "$rdir"
  if [ -n "$stub" ]; then
    awk -F '\t' -v id="$id" 'BEGIN { OFS = "\t" } $1 == id && $3 ~ /^[1-9][0-9]*$/ { p = $2; sub(/^\.\//, "", p); print p, $3 }' "$stub" >"$rdir/findings.tsv"
  else
    if ! git clone -q --shared "$mirror" "$rdir/copy" 2>/dev/null \
      || ! git -C "$rdir/copy" remote remove origin \
      || ! git -C "$rdir/copy" -c advice.detachedHead=false checkout -q "$commit" 2>/dev/null; then
      printf '%s\n' "$prog: row $id: could not prepare its isolated copy" >&2
      printf '%s\t%s\terror\t0\n' "$id" "$class"
      return 0
    fi
    base=$(git -C "$rdir/copy" merge-base "$commit" main 2>/dev/null) || base=
    if [ -z "$base" ]; then
      printf '%s\n' "$prog: row $id: no merge base with main, so no change to review; mark it unreplayable" >&2
      printf '%s\t%s\terror\t0\n' "$id" "$class"
      return 0
    fi
    git -C "$rdir/copy" diff "$base...$commit" >"$rdir/change.diff"
    mkdir -p "$rdir/home" "$rdir/state"
    ledger=
    if [ "$class" = declined ]; then
      ledger=$rdir/ledger.tsv
      printf 'status\tpath\tline\treason\n' >"$ledger"
      printf 'declined\t%s\t%s\t%s\n' "$path" "$line" "$dismissal" >>"$ledger"
    fi
    rc=1
    for attempt in 1 2; do
      [ "$attempt" -eq 1 ] || sleep "$retry_wait"
      (cd "$rdir/copy" \
        && BACKTEST_ROW=$id BACKTEST_HEAD=$commit BACKTEST_BASE=$base \
          BACKTEST_DIFF=$rdir/change.diff \
          BACKTEST_HOME=$rdir/home BACKTEST_STATE_HOME=$rdir/state \
          BACKTEST_MODEL=$model BACKTEST_PLANWRIGHT_ROOT=$repo_root \
          BACKTEST_LEDGER=$ledger BACKTEST_USAGE_FILE=$rdir/usage.$attempt \
          exec "$reviewer" >"$rdir/findings.raw" 2>"$rdir/reviewer.err" </dev/null) &
      rpid=$!
      trap 'kill "$rpid" 2>/dev/null; exit 143' TERM
      arc=0
      wait "$rpid" || arc=$?
      trap - TERM
      if [ "$arc" -eq 0 ]; then
        rc=0
        break
      fi
    done
    tokens=$(cat "$rdir"/usage.* 2>/dev/null | awk '$1 ~ /^[0-9]+$/ { t += $1 } END { printf "%d", t }')
    if [ "$rc" -ne 0 ]; then
      printf '%s\n' "$prog: row $id: the reviewer failed twice" >&2
      printf '%s\t%s\terror\t%s\n' "$id" "$class" "$tokens"
      return 0
    fi
    awk -F '\t' 'BEGIN { OFS = "\t" } $2 ~ /^[1-9][0-9]*$/ { p = $1; sub(/^\.\//, "", p); print p, $2 }' "$rdir/findings.raw" >"$rdir/findings.tsv"
  fi
  verdict=$(awk -F '\t' -v p="$path" -v l="$line" -v k="$RBT_CATCH_LINES" '
    $1 == p { d = $2 - l; if (d < 0) d = -d; if (d <= k) hit = 1 }
    END { print (hit ? "caught" : "missed") }' "$rdir/findings.tsv")
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" "$verdict" "${tokens:-0}"
}

i=0
while IFS= read -r row; do
  i=$((i + 1))
  printf '%s\n' "$row" >"$tmp/row.$i"
  (replay_row "$row" >"$tmp/verdict.$i") &
  pids="$pids $!"
  if [ $((i % jobs)) -eq 0 ]; then
    wait
    pids=
  fi
done <"$tmp/sample.tsv"
wait
pids=
: >"$tmp/verdicts.tsv"
j=1
while [ "$j" -le "$i" ]; do
  # A row whose job died without a verdict is an error, never a silent drop.
  if [ -s "$tmp/verdict.$j" ]; then
    cat "$tmp/verdict.$j" >>"$tmp/verdicts.tsv"
  else
    printf '%s\n' "$prog: a row's replay ended without a verdict" >&2
    awk -F '\t' '{ printf "%s\t%s\terror\t0\n", $1, $7 }' "$tmp/row.$j" >>"$tmp/verdicts.tsv"
  fi
  j=$((j + 1))
done
rm -rf "$tmp/rows"

# --- score, gate, record ------------------------------------------------------

{
  printf 'review-backtest\t1\n'
  printf 'corpus\t%s\n' "$version"
  printf 'model\t%s\n' "$model"
  printf 'seed\t%s\n' "$seed"
  printf 'cap\t%s\n' "$cap"
  printf 'plugin_commit\t%s\n' "$plugin_commit"
  printf 'classes\t%s\n' "$(printf '%s' "$targets" | tr -s ' ' ',' | sed 's/,$//')"
  printf 'excluded_unreplayable\t%s\n' "$excluded"
  awk -F '\t' '{ t += $4 } END { printf "tokens_total\t%d\n", t }' "$tmp/verdicts.tsv"
  for c in $targets; do
    awk -F '\t' -v c="$c" '$2 == c && $3 != "error" { s++; if ($3 == "caught") k++ } END { printf "class\t%s\t%d\t%d\n", c, s, k }' "$tmp/verdicts.tsv"
  done
  awk -F '\t' '{ printf "row\t%s\t%s\t%s\n", $1, $2, $3 }' "$tmp/verdicts.tsv"
} >"$tmp/result.tsv"

awk -F '\t' '$1 == "class" { printf "%s: %d/%d\n", $2, $4, $3 }' "$tmp/result.tsv"

# The gate reads the baseline before --out is written: the two may be one file.
errors=$(awk -F '\t' '$3 == "error"' "$tmp/verdicts.tsv" | wc -l | tr -d ' ')
gate=0
if [ -n "$baseline" ]; then
  for c in $targets; do
    now=$(awk -F '\t' -v c="$c" '$1 == "class" && $2 == c { print $4 }' "$tmp/result.tsv")
    base_caught=$(awk -F '\t' -v c="$c" '$1 == "class" && $2 == c { print $4 }' "$baseline")
    if [ -z "$base_caught" ]; then
      printf '%s\n' "$prog: gate: class $c has no baseline row; not compared" >&2
      continue
    fi
    if [ "${now:-0}" -lt "$base_caught" ]; then
      printf '%s\n' "$prog: gate: $c caught ${now:-0} < baseline $base_caught" >&2
      gate=1
    fi
  done
  [ "$gate" -eq 0 ] && printf '%s\n' "gate: pass (no targeted class below its baseline)"
fi
if [ -n "$out" ]; then
  if ! cp "$tmp/result.tsv" "$out.partial.$$" || ! mv "$out.partial.$$" "$out"; then
    die 2 "could not write the result to --out"
  fi
fi
if [ "$errors" -gt 0 ]; then
  printf '%s\n' "$prog: $errors row(s) ended in error (a setup step or the reviewer failed); see the result's error rows" >&2
  exit 4
fi
exit "$gate"
