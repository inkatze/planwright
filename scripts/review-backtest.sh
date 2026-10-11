#!/bin/sh
# review-backtest.sh — replay the review backtest corpus through one review
# pass and score its recall per class (review-effectiveness REQ-H1.2,
# REQ-H1.3, REQ-C1.1, D-7, D-9).
#
# ON DEMAND, NEVER CI: a real replay spends model tokens. It is registered as
# an `eval:` task so check:no-ci-evals keeps it out of CI; its mechanics are
# tested offline through the reviewer-stub seam.
#
# THE SAMPLE. Rows marked unreplayable are excluded first and counted. For each
# targeted class (a class is a row's miss reason; when --classes is absent, every class
# holding a replayable row, the others reported as not sampled) the replayable rows are ordered by the POSIX cksum
# of "<seed>:<id>" and the first <cap> taken, so a class's sample depends only
# on the seed, the cap, and the corpus, never on which other classes run. A
# sample with zero replayable rows overall, or in a targeted class, is
# refused. The cap (default 5) and seed are printed and recorded.
#
# ONE ROW, ONE PASS. Each sampled row's pre-fix commit is checked out into an
# isolated copy: a fresh clone of a temporary bare mirror of the remote, with
# no remote left to push to, removed on exit. The reviewer runs with that copy
# as its working directory and is told, through the environment, the redirected
# home and state home every command it executes must use; the reviewing
# session itself keeps its own home and credentials. A `declined`-class row
# gets its recorded dismissal seeded into a coordinator ledger file
# (BACKTEST_LEDGER), the loop ledger a real pass would hold; no other row has
# one. A reviewer that exits non-zero is retried once; a second failure marks
# the row `error` and the run exits 4.
#
# THE REVIEWER is an executable run once per row with these variables set:
#   BACKTEST_ROW         the row id
#   BACKTEST_HEAD        the pre-fix commit (the copy's HEAD)
#   BACKTEST_BASE        the merge base of that commit with the remote's main
#   BACKTEST_HOME        the redirected home for executed commands
#   BACKTEST_STATE_HOME  the redirected machine-local state home
#   BACKTEST_LEDGER      the coordinator ledger, declined rows only
#   BACKTEST_MODEL       the --model value
#   BACKTEST_PLANWRIGHT_ROOT  the planwright checkout whose doctrine is "today's"
#   BACKTEST_USAGE_FILE  where the reviewer may write the row's token count
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
# is refused, since a failed gate is never re-rolled. The run exits 1 when any
# targeted class catches fewer sampled rows than the baseline did.
#
# THE RESULT (--out) is tab-separated key lines: `review-backtest 1`, `corpus`,
# `model`, `seed`, `cap`, `plugin_commit`, `classes`, `excluded_unreplayable`,
# `tokens_total` (the sum the reviewer reported, 0 for the stub),
# then `class <name> <sampled> <caught>` and `row <id> <class>
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
#   targeted class dropped below its baseline; 2 usage or a refused sample;
#   3 a baseline from another model or corpus version; 4 a reviewer failed on
#   a row twice.
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
esac
corpus=${corpus%/}
version=${corpus##*/}
case $version in
  v[1-9] | v[1-9]*[0-9]) rbt_is_uint "${version#v}" || die 2 "the corpus directory must be named v<N>" ;;
  *) die 2 "the corpus directory must be named v<N>" ;;
esac
[ -f "$corpus/corpus.tsv" ] || die 2 "no corpus.tsv in the corpus directory"
[ "$(sed -n 1p "$corpus/corpus.tsv")" = "$RBT_HEADER" ] || die 2 "the corpus header does not match the schema"
rbt_is_uint "$jobs" || die 2 "--jobs must be a positive integer"
if [ -n "$stub" ]; then
  [ -f "$stub" ] && [ -r "$stub" ] || die 2 "the reviewer stub is not readable"
else
  [ -x "$reviewer" ] || die 2 "the reviewer is not an executable file"
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
if [ -n "$classes" ]; then
  targets=$(printf '%s\n' "$classes" | tr ',' ' ')
  for c in $targets; do
    rbt_in_list "$c" "$RBT_REASONS" || die 2 "unknown class (not a miss reason)"
  done
else
  # The full sample targets every class holding a replayable row; a class whose
  # rows are all unreplayable is reported, not sampled.
  targets=$(awk -F '\t' 'NR > 1 && $8 == "yes" { print $7 }' "$corpus/corpus.tsv" | sort -u | tr '\n' ' ')
  for c in $present; do
    rbt_in_list "$c" "$targets" || printf '%s\n' "$prog: class $c has no replayable rows; not sampled" >&2 # trusted: class read from a screened corpus
  done
fi
[ -n "$present" ] || die 2 "the corpus holds no rows"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/rbt-replay.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

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

printf '%s\n' "$prog: corpus $version, model $model" # trusted: version and model are shape-checked above
printf '%s\n' "cap: $cap"                            # trusted: integer
printf '%s\n' "seed: $seed"                          # trusted: integer
printf '%s\n' "excluded unreplayable: $excluded"     # trusted: integer from wc
printf '%s\n' "sampled: $sampled"                    # trusted: integer from wc

# --- the mirror: the remote's main plus every sampled PR head ----------------

if [ -z "$stub" ]; then
  if [ -z "$remote" ]; then
    remote=$(git -C "$repo_root" remote get-url origin 2>/dev/null) || die 2 "no --remote and no origin in this checkout"
  fi
  mirror=$tmp/mirror.git
  git init -q --bare "$mirror"
  refspecs="+refs/heads/main:refs/heads/main"
  cut -f2 "$tmp/sample.tsv" | sort -un >"$tmp/prs.txt"
  while IFS= read -r n; do
    refspecs="$refspecs +refs/pull/$n/head:refs/backtest/pr/$n"
  done <"$tmp/prs.txt"
  # shellcheck disable=SC2086 # refspecs are built from integers and fixed text
  git -C "$mirror" fetch -q --no-tags "$remote" $refspecs || die 2 "could not fetch main and the sampled PR heads from the remote"
fi

# --- replay -------------------------------------------------------------------

replay_row() {
  # replay_row <row line> — print `<id>\t<class>\t<verdict>` for one row.
  id=$(printf '%s\n' "$1" | cut -f1)
  commit=$(printf '%s\n' "$1" | cut -f3)
  path=$(printf '%s\n' "$1" | cut -f4)
  line=$(printf '%s\n' "$1" | cut -f5)
  class=$(printf '%s\n' "$1" | cut -f7)
  dismissal=$(printf '%s\n' "$1" | cut -f11)
  rdir=$tmp/rows/$id
  mkdir -p "$rdir"
  if [ -n "$stub" ]; then
    awk -F '\t' -v id="$id" 'BEGIN { OFS = "\t" } $1 == id { print $2, $3 }' "$stub" >"$rdir/findings.tsv"
    rc=0
  else
    git clone -q --no-hardlinks "$mirror" "$rdir/copy" 2>/dev/null || {
      printf '%s\t%s\terror\n' "$id" "$class"
      return 0
    }
    git -C "$rdir/copy" remote remove origin
    if ! git -C "$rdir/copy" -c advice.detachedHead=false checkout -q "$commit" 2>/dev/null; then
      printf '%s\t%s\terror\n' "$id" "$class"
      return 0
    fi
    base=$(git -C "$rdir/copy" merge-base "$commit" main 2>/dev/null) || base=
    mkdir -p "$rdir/home" "$rdir/state"
    ledger=
    if [ "$class" = declined ]; then
      ledger=$rdir/ledger.tsv
      printf 'status\tpath\tline\treason\n' >"$ledger"
      printf 'declined\t%s\t%s\t%s\n' "$path" "$line" "$dismissal" >>"$ledger"
    fi
    rc=1
    for _attempt in 1 2; do
      if (cd "$rdir/copy" \
        && BACKTEST_ROW=$id BACKTEST_HEAD=$commit BACKTEST_BASE=$base \
          BACKTEST_HOME=$rdir/home BACKTEST_STATE_HOME=$rdir/state \
          BACKTEST_MODEL=$model BACKTEST_PLANWRIGHT_ROOT=$repo_root \
          BACKTEST_LEDGER=$ledger BACKTEST_USAGE_FILE=$rdir/usage \
          "$reviewer" >"$rdir/findings.raw" 2>"$rdir/reviewer.err" </dev/null); then
        rc=0
        break
      fi
    done
    awk -F '\t' 'BEGIN { OFS = "\t" } $2 ~ /^[1-9][0-9]*$/ { print $1, $2 }' "$rdir/findings.raw" >"$rdir/findings.tsv" 2>/dev/null || : >"$rdir/findings.tsv"
  fi
  if [ "$rc" -ne 0 ]; then
    printf '%s\t%s\terror\n' "$id" "$class"
    return 0
  fi
  verdict=$(awk -F '\t' -v p="$path" -v l="$line" -v k="$RBT_CATCH_LINES" '
    $1 == p { d = $2 - l; if (d < 0) d = -d; if (d <= k) hit = 1 }
    END { print (hit ? "caught" : "missed") }' "$rdir/findings.tsv")
  tokens=$(sed -n 1p "$rdir/usage" 2>/dev/null) || tokens=
  case $tokens in '' | *[!0-9]*) tokens=0 ;; esac
  printf '%s\t%s\t%s\t%s\n' "$id" "$class" "$verdict" "$tokens"
}

: >"$tmp/verdicts.tsv"
i=0
while IFS= read -r row; do
  i=$((i + 1))
  (replay_row "$row" >"$tmp/verdict.$i") &
  if [ $((i % jobs)) -eq 0 ]; then wait; fi
done <"$tmp/sample.tsv"
wait
j=1
while [ "$j" -le "$i" ]; do
  cat "$tmp/verdict.$j" >>"$tmp/verdicts.tsv"
  rm -rf "$tmp/rows/$(cut -f1 "$tmp/verdict.$j")"
  j=$((j + 1))
done

# --- score, record, gate ------------------------------------------------------

plugin_commit=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null) || plugin_commit=unknown
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
    awk -F '\t' -v c="$c" '$2 == c { s++; if ($3 == "caught") k++ } END { printf "class\t%s\t%d\t%d\n", c, s, k }' "$tmp/verdicts.tsv"
  done
  awk -F '\t' '{ printf "row\t%s\t%s\t%s\n", $1, $2, $3 }' "$tmp/verdicts.tsv"
} >"$tmp/result.tsv"

awk -F '\t' '$1 == "class" { printf "%s: %d/%d\n", $2, $4, $3 }' "$tmp/result.tsv"
[ -z "$out" ] || cp "$tmp/result.tsv" "$out"

errors=$(awk -F '\t' '$3 == "error"' "$tmp/verdicts.tsv" | wc -l | tr -d ' ')
gate=0
if [ -n "$baseline" ]; then
  for c in $targets; do
    now=$(awk -F '\t' -v c="$c" '$1 == "class" && $2 == c { print $4 }' "$tmp/result.tsv")
    then_=$(awk -F '\t' -v c="$c" '$1 == "class" && $2 == c { print $4 }' "$baseline")
    if [ -z "$then_" ]; then
      printf '%s\n' "$prog: gate: class $c has no baseline row; not compared" >&2 # trusted: class is vocabulary-checked
      continue
    fi
    if [ "${now:-0}" -lt "$then_" ]; then
      printf '%s\n' "$prog: gate: $c caught ${now:-0} < baseline $then_" >&2 # trusted: vocabulary and integers
      gate=1
    fi
  done
  [ "$gate" -eq 0 ] && printf '%s\n' "gate: pass (no targeted class below its baseline)"
fi
if [ "$errors" -gt 0 ]; then
  printf '%s\n' "$prog: $errors row(s) failed in the reviewer twice; see the result's error rows" >&2 # trusted: integer
  exit 4
fi
exit "$gate"
