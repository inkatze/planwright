#!/bin/bash
# Tests for scripts/review-backtest.sh — the replay harness — offline against
# the reviewer-stub seam and a local bare remote (review-effectiveness
# REQ-H1.2, REQ-H1.3, REQ-H1.1, REQ-C1.1, D-7, D-9).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS="$REPO_ROOT/scripts/review-backtest.sh"

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_exit() {
  if [ "$2" -eq "$3" ]; then ok "$1"; else fail "$1 (expected exit $2, got $3)"; fi
}
assert_contains() {
  case "$3" in
    *"$2"*) ok "$1" ;;
    *) fail "$1 (missing '$2' in: $3)" ;;
  esac
}
assert_lacks() {
  case "$3" in
    *"$2"*) fail "$1 (unexpectedly contains '$2')" ;;
    *) ok "$1" ;;
  esac
}

T=$(mktemp -d "${TMPDIR:-/tmp}/rbh.XXXXXX")
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
export TMPDIR="$T/tmp"
export PLANWRIGHT_BACKTEST_RETRY_WAIT=0
mkdir -p "$TMPDIR"
git config --global user.email t@example.invalid
git config --global user.name t
git config --global init.defaultBranch main

# --- the remote: main, and two PR branches forked from it ---
src="$T/src"
git init -q "$src"
seq 1 80 >"$src/a.sh"
seq 1 80 >"$src/b.sh"
git -C "$src" add a.sh b.sh
git -C "$src" commit -qm base
git -C "$src" checkout -qb pr1
printf 'x\n' >>"$src/a.sh"
git -C "$src" commit -qam pr1
P1=$(git -C "$src" rev-parse HEAD)
git -C "$src" checkout -q main
git -C "$src" checkout -qb pr2
printf 'y\n' >>"$src/b.sh"
git -C "$src" commit -qam pr2
P2=$(git -C "$src" rev-parse HEAD)
git -C "$src" checkout -q main
remote="$T/remote.git"
git clone -q --bare "$src" "$remote"
git -C "$remote" update-ref refs/pull/1/head "$P1"
git -C "$remote" update-ref refs/pull/2/head "$P2"

HDR='id	pr	commit	path	line	category	reason	replayable	label_source	gist	dismissal'
corpus_dir="$T/corpus/v1"
mkdir -p "$corpus_dir"
{
  printf '%s\n' "$HDR"
  printf 'r0001\t1\t%s\ta.sh\t50\tcorrectness\truntime-tracing\tyes\tmodel\tthe loop exits zero on failure\t-\n' "$P1"
  printf 'r0002\t1\t%s\ta.sh\t50\tcorrectness\truntime-tracing\tyes\tmodel\ta second trace miss\t-\n' "$P1"
  printf 'r0003\t2\t%s\tb.sh\t20\tdocs\tclaim-vs-code\tyes\tmodel\tthe header claims fail-closed\t-\n' "$P2"
  printf 'r0004\t2\t%s\tb.sh\t30\tportability\tdeclined\tyes\tdeclined-log\ta GNU-only flag\tthe pass judged it portable\n' "$P2"
  printf 'r0005\t2\t%s\tb.sh\t40\tstyle\tlintable\tno\tmodel\tunreplayable lint row\t-\n' "$P2"
  printf 'r0006\t1\t%s\ta.sh\t9\tcorrectness\toutside-diff\tno\tmodel\ta caller outside the diff\t-\n' "$P1"
} >"$corpus_dir/corpus.tsv"

# Stub findings: r0001 caught at exactly 10 lines away, r0002 missed at 11,
# r0003 missed (another file), r0004 caught.
stub="$T/stub.tsv"
printf 'r0001\ta.sh\t60\nr0002\ta.sh\t39\nr0003\ta.sh\t20\nr0004\tb.sh\t31\n' >"$stub"

base_args() { printf '%s\n' --corpus "$corpus_dir" --remote "$remote"; }
run() {
  # shellcheck disable=SC2046
  "$HARNESS" $(base_args) "$@"
}

# --- a stub replay over the full sample ---
out=$(run --reviewer-stub "$stub" --model stub-model-1 --seed 7 --classes runtime-tracing,claim-vs-code,declined --out "$T/base.tsv" 2>&1)
rc=$?
assert_exit "a stub replay over targeted classes succeeds" 0 "$rc"
assert_contains "prints the cap it used" "cap: 5" "$out"
assert_contains "prints the seed it used" "seed: 7" "$out"
assert_contains "reports recall per class (10 lines away is caught, 11 is missed)" "runtime-tracing: 1/2" "$out"
assert_contains "a finding in another file misses" "claim-vs-code: 0/1" "$out"
assert_contains "the declined row is caught" "declined: 1/1" "$out"
if grep -q '^model	stub-model-1$' "$T/base.tsv"; then ok "the result records its model"; else fail "result lacks the model"; fi
if grep -q '^corpus	v1$' "$T/base.tsv"; then ok "the result records its corpus version"; else fail "result lacks the corpus version"; fi
if grep -q '^plugin_commit	[0-9a-f]\{40\}$' "$T/base.tsv"; then ok "the result records the plugin commit"; else fail "result lacks the plugin commit"; fi
if grep -q '^row	r0001	runtime-tracing	caught$' "$T/base.tsv"; then ok "a row 10 lines away is caught"; else fail "r0001 not caught"; fi
if grep -q '^row	r0002	runtime-tracing	missed$' "$T/base.tsv"; then ok "a row 11 lines away is missed"; else fail "r0002 not missed"; fi

# --- unreplayable rows are excluded and counted ---
out=$(run --reviewer-stub "$stub" --model stub-model-1 --seed 7 --out "$T/full.tsv" 2>&1)
assert_contains "reports the excluded unreplayable count" "excluded unreplayable: 2" "$out"
assert_lacks "an unreplayable row is never replayed" "r0005" "$(grep '^row' "$T/full.tsv")"
assert_contains "a class with only unreplayable rows is reported, not sampled" "class lintable has no replayable rows" "$out"

# --- the zero-row refusals, after exclusion ---
out=$(run --reviewer-stub "$stub" --model stub-model-1 --seed 7 --classes lintable 2>&1)
assert_exit "a targeted class with zero replayable rows is refused" 2 $?
assert_contains "names the empty class" "lintable" "$out"
mkdir -p "$T/corpus/v2"
awk -F '\t' 'BEGIN { OFS = "\t" } NR == 1 { print; next } { $8 = "no"; print }' "$corpus_dir/corpus.tsv" >"$T/corpus/v2/corpus.tsv"
out=$("$HARNESS" --corpus "$T/corpus/v2" --remote "$remote" --reviewer-stub "$stub" --model stub-model-1 --seed 7 2>&1)
assert_exit "a sample with zero replayable rows overall is refused" 2 $?
assert_contains "names the zero-row refusal" "zero replayable rows" "$out"

# --- the gate against a baseline, reusing its seed and cap ---
out=$(run --reviewer-stub "$stub" --model stub-model-1 --baseline "$T/base.tsv" --classes runtime-tracing 2>&1)
assert_exit "matching the baseline passes the gate" 0 $?
assert_contains "reuses the baseline's seed" "seed: 7" "$out"
printf 'r0002\ta.sh\t39\n' >"$T/worse.tsv"
out=$(run --reviewer-stub "$T/worse.tsv" --model stub-model-1 --baseline "$T/base.tsv" --classes runtime-tracing 2>&1)
assert_exit "a targeted class catching fewer rows than the baseline fails" 1 $?
assert_contains "names the dropped class" "runtime-tracing caught 0 < baseline 1" "$out"
out=$(run --reviewer-stub "$stub" --model other-model-2 --baseline "$T/base.tsv" 2>&1)
assert_exit "a baseline from another model is refused" 3 $?
assert_contains "names the model mismatch" "another model" "$out"
cp "$corpus_dir/corpus.tsv" "$T/corpus/v2/corpus.tsv"
out=$("$HARNESS" --corpus "$T/corpus/v2" --remote "$remote" --reviewer-stub "$stub" --model stub-model-1 --baseline "$T/base.tsv" 2>&1)
assert_exit "a baseline from another corpus version is refused" 3 $?
out=$(run --reviewer-stub "$stub" --model stub-model-1 --baseline "$T/base.tsv" --seed 8 2>&1)
assert_exit "a new seed against a baseline is refused" 2 $?

# --- the sample is seeded and per-class: same seed, same rows ---
printf 'r0001\ta.sh\t50\nr0002\ta.sh\t50\n' >"$T/all.tsv"
a=$(run --reviewer-stub "$T/all.tsv" --model m-1 --seed 3 --cap 1 --classes runtime-tracing --out "$T/s1.tsv" >/dev/null 2>&1 && grep '^row' "$T/s1.tsv")
b=$(run --reviewer-stub "$T/all.tsv" --model m-1 --seed 3 --cap 1 --out "$T/s2.tsv" >/dev/null 2>&1 && grep '^row	[^	]*	runtime-tracing' "$T/s2.tsv")
if [ -n "$a" ] && [ "$a" = "$b" ]; then ok "a class's sample does not depend on the other classes targeted"; else fail "per-class sample differs ($a vs $b)"; fi
if grep -c '^row	[^	]*	runtime-tracing' "$T/s2.tsv" | grep -qx 1; then ok "the cap bounds each class"; else fail "cap not applied"; fi

# --- the isolated copy: the reviewer runs in a fresh clone, never here ---
rev="$T/reviewer.sh"
cat >"$rev" <<'EOF'
#!/bin/sh
{
  printf 'row=%s\n' "$BACKTEST_ROW"
  printf 'pwd=%s\n' "$(pwd -P)"
  printf 'head=%s\n' "$(git rev-parse HEAD)"
  printf 'base=%s\n' "$BACKTEST_BASE"
  printf 'remotes=%s\n' "$(git remote | tr '\n' ' ')"
  printf 'home=%s\n' "$BACKTEST_HOME"
  printf 'state=%s\n' "$BACKTEST_STATE_HOME"
  printf 'ledger=%s\n' "${BACKTEST_LEDGER:-none}"
  printf 'diff=%s\n' "$(grep -c '^+' "$BACKTEST_DIFF")"
  if [ "$BACKTEST_HOME" = "$HOME" ]; then echo homesame=yes; else echo homesame=no; fi
  [ -n "${BACKTEST_LEDGER:-}" ] && cat "$BACKTEST_LEDGER"
} >>"$REVIEWER_LOG"
printf 'a.sh\t50\n'
EOF
chmod +x "$rev"
export REVIEWER_LOG="$T/reviewer.log"
before=$(git -C "$REPO_ROOT" status --porcelain | cksum)
run --reviewer "$rev" --model m-1 --seed 7 --classes runtime-tracing,declined >/dev/null 2>&1
assert_exit "a replay through a reviewer command succeeds" 0 $?
log=$(cat "$REVIEWER_LOG")
assert_lacks "the reviewer never runs in the live checkout" "pwd=$REPO_ROOT" "$log"
assert_contains "the reviewer runs at the row's pre-fix commit" "head=$P1" "$log"
assert_contains "the reviewer gets the change as a diff file" "diff=2" "$log"
assert_lacks "no reviewer gets an empty diff" "diff=0" "$log"
assert_contains "the copy has no remote to push to" "remotes=
" "$log"
case "$log" in *"home=$T/tmp/"*) ok "the redirected home is under the run's temporary root" ;; *) fail "home not redirected under a temp root" ;; esac
assert_contains "the redirected home is never the session's own home" "homesame=no" "$log"
assert_lacks "no row hands the reviewer its own home as the redirected one" "homesame=yes" "$log"
assert_contains "a declined row seeds its dismissal into the coordinator's ledger" "the pass judged it portable" "$log"
n_ledger=$(grep -c '^ledger=none' "$REVIEWER_LOG")
if [ "$n_ledger" -eq 2 ]; then ok "rows of other classes get no ledger"; else fail "expected 2 ledger-less rows, got $n_ledger"; fi
if [ "$(git -C "$REPO_ROOT" status --porcelain | cksum)" = "$before" ]; then ok "the live worktree is unchanged"; else fail "live worktree changed"; fi
copies=$(sed -n 's/^pwd=//p' "$REVIEWER_LOG" | while read -r d; do [ -e "$d" ] && echo "$d"; done)
if [ -z "$copies" ]; then ok "every isolated copy is removed on exit"; else fail "copies left behind: $copies"; fi

# --- a failing reviewer is retried once, then the row is an error ---
cat >"$T/broken.sh" <<'EOF'
#!/bin/sh
echo x >>"$REVIEWER_LOG.broken"
exit 3
EOF
chmod +x "$T/broken.sh"
out=$(run --reviewer "$T/broken.sh" --model m-1 --seed 7 --classes claim-vs-code 2>&1)
assert_exit "a reviewer failing twice makes the run exit 4" 4 $?
if [ "$(wc -l <"$REVIEWER_LOG.broken" | tr -d ' ')" -eq 2 ]; then ok "a failing reviewer is retried once"; else fail "retry count wrong"; fi

# --- a corpus failing the schema screen never reaches git ---
mkdir -p "$T/corpus/v3"
{
  printf '%s\n' "$HDR"
  printf 'r0001\t1\t--upload-pack=x\ta.sh\t50\tcorrectness\truntime-tracing\tyes\tmodel\ta hostile commit field\t-\n'
} >"$T/corpus/v3/corpus.tsv"
: >"$REVIEWER_LOG"
out=$("$HARNESS" --corpus "$T/corpus/v3" --remote "$remote" --reviewer "$rev" --model m-1 --seed 7 2>&1)
assert_exit "a corpus failing the screen is refused" 2 $?
assert_contains "names the screen refusal" "screen" "$out"
if [ ! -s "$REVIEWER_LOG" ]; then ok "no row of a refused corpus is replayed"; else fail "a refused corpus reached the reviewer"; fi

# --- a row whose commit shares no history with main is an error, not a pass ---
git -C "$src" checkout -q --orphan unrelated
git -C "$src" rm -rqf .
printf 'z\n' >"$src/c.sh"
git -C "$src" add c.sh
git -C "$src" commit -qm unrelated
P3=$(git -C "$src" rev-parse HEAD)
git -C "$src" checkout -q main
git -C "$src" push -q "$remote" "$P3:refs/pull/3/head"
mkdir -p "$T/corpus/v4"
{
  printf '%s\n' "$HDR"
  printf 'r0001\t3\t%s\tc.sh\t1\tcorrectness\truntime-tracing\tyes\tmodel\tan unrelated-history row\t-\n' "$P3"
} >"$T/corpus/v4/corpus.tsv"
: >"$REVIEWER_LOG"
out=$("$HARNESS" --corpus "$T/corpus/v4" --remote "$remote" --reviewer "$rev" --model m-1 --seed 7 2>&1)
assert_exit "a row with no merge base on main makes the run exit 4" 4 $?
assert_contains "names the missing merge base" "no merge base" "$out"
if [ ! -s "$REVIEWER_LOG" ]; then ok "the reviewer is not run without a base"; else fail "the reviewer ran without a base"; fi

# --- the plugin commit is the one the run started from ---
pw="$T/pw"
mkdir -p "$pw/scripts"
cp "$REPO_ROOT"/scripts/review-backtest.sh "$REPO_ROOT"/scripts/review-backtest-lib.sh "$REPO_ROOT"/scripts/review-corpus-screen.sh "$pw/scripts/"
git -C "$pw" init -q
git -C "$pw" add scripts
git -C "$pw" commit -qm start
pw_start=$(git -C "$pw" rev-parse HEAD)
cat >"$T/moving.sh" <<EOF
#!/bin/sh
git -C "$pw" commit -q --allow-empty -m moved
printf 'a.sh\t50\n'
EOF
chmod +x "$T/moving.sh"
"$pw/scripts/review-backtest.sh" --corpus "$corpus_dir" --remote "$remote" --reviewer "$T/moving.sh" \
  --model m-1 --seed 7 --classes claim-vs-code --out "$T/moving.tsv" >/dev/null 2>&1
if grep -q "^plugin_commit	$pw_start\$" "$T/moving.tsv"; then ok "the recorded plugin commit is the run's starting head"; else fail "plugin commit moved with the checkout"; fi

# --- the replay holds under concurrency, a relative reviewer, and any default branch ---
: >"$REVIEWER_LOG"
run --reviewer "$rev" --model m-1 --seed 7 --classes runtime-tracing,declined --jobs 2 --out "$T/jobs2.tsv" >/dev/null 2>&1
assert_exit "a replay with --jobs 2 succeeds" 0 $?
if [ "$(grep -c '^row	' "$T/jobs2.tsv")" -eq 3 ]; then ok "--jobs 2 scores every sampled row"; else fail "--jobs 2 lost a row"; fi
cp "$rev" "$T/tmp/rel-reviewer.sh"
(cd "$T/tmp" && "$HARNESS" --corpus "$corpus_dir" --remote "$remote" --reviewer ./rel-reviewer.sh --model m-1 --seed 7 --classes claim-vs-code >/dev/null 2>&1)
assert_exit "a relative --reviewer path resolves from the caller, not the copy" 0 $?
git config --global init.defaultBranch master
: >"$REVIEWER_LOG"
run --reviewer "$rev" --model m-1 --seed 7 --classes claim-vs-code >/dev/null 2>&1
assert_exit "a host whose default branch is not main still replays" 0 $?
git config --global init.defaultBranch main

# --- a row whose job dies is an error, never a silent drop ---
cat >"$T/dying.sh" <<'EOF'
#!/bin/sh
kill -9 $PPID
EOF
chmod +x "$T/dying.sh"
run --reviewer "$T/dying.sh" --model m-1 --seed 7 --classes claim-vs-code --out "$T/dying.tsv" >/dev/null 2>&1
assert_exit "a row whose replay job dies makes the run exit 4" 4 $?
if grep -q '^row	r0003	claim-vs-code	error$' "$T/dying.tsv"; then ok "the dead row is recorded as an error"; else fail "the dead row vanished"; fi

if grep -q '^class	claim-vs-code	0	0$' "$T/dying.tsv"; then ok "an error row stays out of its class's counts"; else fail "an error row was scored"; fi
run --reviewer-stub "$stub" --model m-1 --baseline "$T/dying.tsv" >/dev/null 2>&1
assert_exit "a baseline holding error rows is refused" 2 $?

# --- stopping the harness stops the reviewer it started ---
cat >"$T/slow.sh" <<EOF
#!/bin/sh
: >"$T/slow.started"
sleep 4
: >"$T/slow.finished"
EOF
chmod +x "$T/slow.sh"
rm -f "$T/slow.started" "$T/slow.finished"
"$HARNESS" --corpus "$corpus_dir" --remote "$remote" --reviewer "$T/slow.sh" --model m-1 --seed 7 --classes claim-vs-code >/dev/null 2>&1 &
hpid=$!
n=0
until [ -e "$T/slow.started" ] || [ "$n" -ge 200 ]; do
  sleep 0.1
  n=$((n + 1))
done
kill -TERM "$hpid"
hrc=0
wait "$hpid" 2>/dev/null || hrc=$?
assert_exit "the harness exits 143 on TERM" 143 "$hrc"
sleep 5
if [ -e "$T/slow.started" ] && [ ! -e "$T/slow.finished" ]; then ok "TERM to the harness ends the running reviewer"; else fail "the reviewer outlived the harness"; fi

# --- refusals that would otherwise let a gate pass on nothing ---
run --reviewer-stub "$stub" --model stub-model-1 --seed 7 --classes , >/dev/null 2>&1
assert_exit "an empty --classes is refused" 2 $?
run --reviewer-stub "$stub" --model stub-model-1 --seed 7 --classes claim-vs-code,claim-vs-code --out "$T/dup.tsv" >/dev/null 2>&1
if [ "$(grep -c '^class	claim-vs-code	' "$T/dup.tsv")" -eq 1 ]; then ok "a repeated class is sampled once"; else fail "a repeated class was sampled twice"; fi
grep -v '^seed	' "$T/base.tsv" >"$T/noseed.tsv"
run --reviewer-stub "$stub" --model stub-model-1 --baseline "$T/noseed.tsv" >/dev/null 2>&1
assert_exit "a baseline without its seed is refused, never re-rolled" 2 $?
sed 's/^class	runtime-tracing	2	1$/class	runtime-tracing	2	1x/' "$T/base.tsv" >"$T/badcount.tsv"
run --reviewer-stub "$stub" --model stub-model-1 --baseline "$T/badcount.tsv" >/dev/null 2>&1
assert_exit "a baseline with a non-integer count is refused" 2 $?
cp "$T/base.tsv" "$T/same.tsv"
run --reviewer-stub "$T/worse.tsv" --model stub-model-1 --baseline "$T/same.tsv" --out "$T/same.tsv" --classes runtime-tracing >/dev/null 2>&1
assert_exit "a worse run fails the gate even when --out is the baseline file" 1 $?
out=$(run --reviewer-stub "$stub" --model stub-model-1 --seed 7 --out "$T/absent-dir/r.tsv" 2>&1)
assert_exit "an unwritable --out is a usage error, not a gate failure" 2 $?
assert_lacks "an unwritable --out is refused before any row replays" "sampled:" "$out"
run --reviewer-stub "$stub" --model stub-model-1 --baseline "$T/base.tsv" --cap 3 >/dev/null 2>&1
assert_exit "a new cap against a baseline is refused" 2 $?

# --- a baseline's cap is reused, not the default ---
sed 's/^cap	5$/cap	1/' "$T/base.tsv" | awk -F '\t' 'BEGIN { OFS = "\t" } $1 == "class" { $3 = ($3 > 1 ? 1 : $3); if ($4 > $3) $4 = $3 } { print }' >"$T/cap1.tsv"
out=$(run --reviewer-stub "$stub" --model stub-model-1 --baseline "$T/cap1.tsv" --classes runtime-tracing 2>&1)
assert_contains "the baseline's cap is reused" "cap: 1" "$out"
assert_contains "the reused cap bounds the sample" "sampled: 1" "$out"

# --- findings written as ./path are still caught ---
printf 'r0003\t./b.sh\t20\nr0003\tb.sh\tabc\n' >"$T/stub-dot.tsv"
out=$(run --reviewer-stub "$T/stub-dot.tsv" --model m-1 --seed 7 --classes claim-vs-code 2>&1)
assert_contains "a ./-prefixed stub finding catches its row" "claim-vs-code: 1/1" "$out"
cat >"$T/dotslash.sh" <<'EOF'
#!/bin/sh
printf './b.sh\t20\n'
EOF
chmod +x "$T/dotslash.sh"
out=$(run --reviewer "$T/dotslash.sh" --model m-1 --seed 7 --classes claim-vs-code 2>&1)
assert_contains "a ./-prefixed finding path catches its row" "claim-vs-code: 1/1" "$out"

# --- a PR head the remote lacks is a row error, not a stopped replay ---
mkdir -p "$T/corpus/v5"
{
  printf '%s\n' "$HDR"
  printf 'r0001\t1\t%s\ta.sh\t50\tcorrectness\truntime-tracing\tyes\tmodel\tpresent\t-\n' "$P1"
  printf 'r0002\t99\t%s\ta.sh\t50\tcorrectness\truntime-tracing\tyes\tmodel\tits PR head is gone\t-\n' "$(printf 'e%.0s' $(seq 1 40))"
} >"$T/corpus/v5/corpus.tsv"
"$HARNESS" --corpus "$T/corpus/v5" --remote "$remote" --reviewer "$rev" --model m-1 --seed 7 --out "$T/v5.tsv" >/dev/null 2>&1
assert_exit "a sampled PR the remote lacks makes the run exit 4, not 2" 4 $?
if grep -q '^row	r0001	runtime-tracing	caught$' "$T/v5.tsv"; then ok "the other rows still replay"; else fail "a missing PR head stopped the other rows"; fi

# --- usage refusals ---
run --reviewer-stub "$stub" --model opus >/dev/null 2>&1
assert_exit "a model alias is refused" 2 $?
"$HARNESS" --corpus "$corpus_dir" --remote "$remote" --reviewer-stub "$stub" >/dev/null 2>&1
assert_exit "a replay without --model is refused" 2 $?
"$HARNESS" --corpus "$T/corpus" --remote "$remote" --reviewer-stub "$stub" --model m-1 >/dev/null 2>&1
assert_exit "a corpus directory not named v<N> is refused" 2 $?
run --reviewer-stub "$stub" --model m-1 --classes nonsense >/dev/null 2>&1
assert_exit "an unknown class is refused" 2 $?

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all review-backtest tests passed"
