#!/bin/bash
# Tests for scripts/substrate-baseline.sh — the maintenance-cost baseline
# (universal-binary REQ-G1.1).
#
# A fixture repository with known history (commits dated by hand, fix-typed
# and not, inside and outside the script layer, one past the as-of date),
# fixture fragments and frozen-log lines, a wall-clock capture and a
# hand-back record; the snapshot's fields are asserted against the counts the
# fixture was built to have. A `gh` stub on PATH drives the capture mode.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-substrate-baseline.sh
set -u
# The fixture repository must never see a git context a hook exports.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)

failures=0
ok() { echo "ok: $1"; }
bad() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
check_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi
}
check_has() {
  case "$2" in
    *"$3"*) ok "$1" ;;
    *) bad "$1 (missing [$3] in: $2)" ;;
  esac
}

[ -x "$REPO_ROOT/scripts/substrate-baseline.sh" ] || {
  echo "FAIL: scripts/substrate-baseline.sh missing or not executable" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-substrate-baseline.XXXXXX") || exit 1
[ -n "$tmp" ] && [ -d "$tmp" ] || exit 1
# The script prints physical paths, and macOS's TMPDIR is a symlinked one
# ending in a slash.
tmp=$(cd -P "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# The baseline runs from its own copy so the fixture repo is its parent and
# the class map comes from the attribution script beside it.
fx=$tmp/repo
rec=$tmp/records
mkdir -p "$rec"
mkdir -p "$fx/scripts" "$fx/githooks" "$fx/docs" "$fx/bundles/demo" \
  "$fx/bundles/_observations/entries" "$fx/bundles/_observations/archive"
cp "$REPO_ROOT/scripts/substrate-baseline.sh" "$REPO_ROOT/scripts/substrate-attribute.sh" "$fx/scripts/"
SB=$fx/scripts/substrate-baseline.sh

cat >"$fx/bundles/demo/requirements.md" <<'EOF'
# Demo

## Sources

- **Observations, test-flakiness class:** obs:aaaaaaa1, obs:aaaaaaa2.
- **Observations, lock and concurrency class:** obs:aaaaaaa2, obs:aaaaaaa3.
EOF
o=$fx/bundles/_observations
printf -- '- 2026-07-03 [demo] a flake handed back.\n' >"$o/entries/2026-07-03-flake-aaaaaaa1.md"
printf -- '- 2026-08-10 [demo] a lock flake.\n' >"$o/archive/2026-08-10-lockflake-aaaaaaa2.md"
printf -- '- 2026-08-11 [demo] a lock.\n' >"$o/entries/2026-08-11-lock-aaaaaaa3.md"
printf -- '- 2026-08-12 [demo] unmined.\n' >"$o/entries/2026-08-12-other-bbbbbbb1.md"
printf -- '- 2026-11-01 [demo] after the as-of date.\n' >"$o/entries/2026-11-01-late-bbbbbbb2.md"
cat >"$o/opportunities.md" <<'EOF'
# Observations log

- 2026-06-20 [demo] a legacy portability line.
- 2026-06-21 [demo] another legacy line.
EOF
cat >"$fx/legacy.tsv" <<'EOF'
legacy:2026-06-20:port	portability	legacy portability line
EOF
cat >"$rec/hand-backs.tsv" <<'EOF'
# id	runs	reason
obs:aaaaaaa1	2	two runs handed back
obs:aaaaaaa2	1	one run handed back
EOF
sha=0123456789abcdef0123456789abcdef01234567
cat >"$rec/wc.tsv" <<EOF
# run	created	sha	seconds
3	2026-10-03T00:00:00Z	$sha	300
2	2026-10-02T00:00:00Z	$sha	500
1	2026-10-01T00:00:00Z	$sha	400
EOF

commit() { # commit <iso-date> <path> <subject>
  printf '%s\n' "$3" >>"$fx/$2"
  git -C "$fx" add -- "$2" >/dev/null
  GIT_AUTHOR_DATE=$1 GIT_COMMITTER_DATE=$1 git -C "$fx" -c core.hooksPath=/dev/null commit -q -m "$3" >/dev/null
}
git -C "$fx" init -q
git -C "$fx" config user.email t@example.invalid
git -C "$fx" config user.name t
git -C "$fx" config commit.gpgsign false
git -C "$fx" add -- bundles legacy.tsv >/dev/null
GIT_AUTHOR_DATE=2026-05-01T10:00:00Z GIT_COMMITTER_DATE=2026-05-01T10:00:00Z \
  git -C "$fx" -c core.hooksPath=/dev/null commit -q -m "docs: fixture inputs" >/dev/null
commit 2026-06-05T10:00:00Z scripts/a.sh "feat: add a"
commit 2026-06-06T10:00:00Z scripts/a.sh "fix(a): repair a"
commit 2026-06-07T10:00:00Z docs/x.md "fix: docs only"
commit 2026-08-01T10:00:00Z githooks/pre-commit "fix!: hook"
commit 2026-08-02T10:00:00Z scripts/a.sh "refactor: fixup wording"
commit 2026-08-03T10:00:00Z scripts/a.sh "fixes: not a type"
commit 2026-11-02T10:00:00Z scripts/a.sh "fix: after the as-of date"
commit 2025-12-30T10:00:00Z scripts/a.sh "fix: across the year"
commit 2026-08-20T10:00:00Z scripts/a.sh "fix: after a mid-month cutoff"
# On the month's last day, late in UTC: a non-UTC month would move it.
commit 2026-09-30T23:30:00Z scripts/a.sh "fix: late on the last day"
# Authored in June, committed in July: the committer month counts.
printf 'b\n' >"$fx/scripts/b.sh"
git -C "$fx" add -- scripts/b.sh >/dev/null
GIT_AUTHOR_DATE=2026-06-20T10:00:00Z GIT_COMMITTER_DATE=2026-07-05T10:00:00Z \
  git -C "$fx" -c core.hooksPath=/dev/null commit -q -m "fix(b): authored earlier" >/dev/null
# A merge commit touching the layer never counts; the commit it merges does.
trunk=$(git -C "$fx" symbolic-ref --short HEAD)
git -C "$fx" checkout -q -b side
commit 2026-10-05T10:00:00Z scripts/c.sh "feat: on a side branch"
git -C "$fx" checkout -q "$trunk"
GIT_AUTHOR_DATE=2026-10-06T10:00:00Z GIT_COMMITTER_DATE=2026-10-06T10:00:00Z \
  git -C "$fx" -c core.hooksPath=/dev/null merge -q --no-ff -m "fix: a merge commit" side >/dev/null

run() { # run [<wall-clock capture>]
  out=$(TZ=Pacific/Kiritimati "$SB" --as-of 2026-10-31 --spec "$fx/bundles/demo" --legacy "$fx/legacy.tsv" \
    --wallclock "${1:-$rec/wc.tsv}" --hand-backs "$rec/hand-backs.tsv" 2>"$tmp/err")
  rc=$?
  err=$(cat "$tmp/err")
}

run
check_eq "baseline exits zero" 0 "$rc"
check_has "snapshot is dated" "$out" "# Substrate maintenance-cost baseline, as of 2026-10-31"
# REQ-G1.1: fix rate per month, layer commits only, up to the as-of date.
check_has "June: two layer commits, one fix-typed, no hand-backs" "$out" "| 2026-06 | 2 | 1 | 0 |"
check_has "July: the commit authored in June, two hand-backs" "$out" "| 2026-07 | 1 | 1 | 2 |"
check_has "August: four layer commits, two fix-typed (fix! included), one hand-back" "$out" "| 2026-08 | 4 | 2 | 1 |"
check_has "September: the late UTC commit stays in its month" "$out" "| 2026-09 | 1 | 1 | 0 |"
check_has "October: the merged commit, not the merge" "$out" "| 2026-10 | 1 | 0 | 0 |"
check_has "the range opens in the earlier year" "$out" "| 2025-12 | 1 | 1 | 0 |"
check_has "the month after December is January" "$out" "| 2026-01 | 0 | 0 | 0 |"
check_eq "nothing after the as-of date" "" "$(printf '%s\n' "$out" | grep '2026-11')"
# Inflow: June has two legacy lines (one mined, portability); August has three
# fragments (two mined: one flaky lock, one lock) and one outside the set.
check_has "June inflow" "$out" "| 2026-06 | 2 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |"
check_has "July inflow" "$out" "| 2026-07 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |"
check_has "August inflow" "$out" "| 2026-08 | 3 | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |"
check_has "wall-clock median present and non-zero" "$out" "| median of 3 runs | 400 |"
check_has "wall-clock fastest" "$out" "| fastest | 300 |"
check_has "wall-clock slowest" "$out" "| slowest | 500 |"
check_has "a per-run row" "$out" "| 2 | 2026-10-02T00:00:00Z | $sha | 500 |"
first=$out
run
check_eq "snapshot regenerates byte-identically" "$first" "$out"

cp "$rec/hand-backs.tsv" "$tmp/hb.keep"
printf 'obs:aaaaaaa3\t1\tnot flaky\n' >>"$rec/hand-backs.tsv"
run
check_eq "a hand-back outside test-flakiness fails closed" 5 "$rc"
check_has "the row is named" "$err" "obs:aaaaaaa3"
cp "$tmp/hb.keep" "$rec/hand-backs.tsv"
printf 'obs:aaaaaaa1\t1\tagain\n' >>"$rec/hand-backs.tsv"
run
check_eq "a repeated hand-back row fails closed" 5 "$rc"
cp "$tmp/hb.keep" "$rec/hand-backs.tsv"

printf 'obs:bbbbbbb1\t1\tunmined\n' >>"$rec/hand-backs.tsv"
run
check_eq "a hand-back outside the mined set fails closed" 5 "$rc"
cp "$tmp/hb.keep" "$rec/hand-backs.tsv"
printf 'obs:aaaaaaa1\tmany\tnot a count\n' >>"$rec/hand-backs.tsv"
run
check_eq "a malformed hand-back row fails closed" 5 "$rc"
cp "$tmp/hb.keep" "$rec/hand-backs.tsv"

printf '4\t2026-10-04T00:00:00Z\t%s\t100\n3\t2026-10-03T00:00:00Z\t%s\t401\n2\t2026-10-02T00:00:00Z\t%s\t200\n1\t2026-10-01T00:00:00Z\t%s\t301\n' \
  "$sha" "$sha" "$sha" "$sha" >"$tmp/wc-four.tsv"
run "$tmp/wc-four.tsv"
check_has "an even run count averages the middle pair" "$out" "| median of 4 runs | 250.5 |"
check_has "the slowest of four" "$out" "| slowest | 401 |"

printf '1\t2026-08-01T00:00:00Z\t%s\t300\n' "$sha" >"$tmp/wc-aug.tsv"
out=$("$SB" --as-of 2026-08-11 --spec "$fx/bundles/demo" --legacy "$fx/legacy.tsv" \
  --wallclock "$tmp/wc-aug.tsv" --hand-backs "$rec/hand-backs.tsv" 2>&1)
check_eq "a mid-month cutoff runs" 0 "$?"
check_has "commits after a mid-month cutoff drop out" "$out" "| 2026-08 | 3 | 1 | 1 |"
check_has "observations after a mid-month cutoff drop out" "$out" "| 2026-08 | 2 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |"

printf '# only a comment\n' >"$tmp/wc-empty.tsv"
run "$tmp/wc-empty.tsv"
check_eq "an empty capture fails closed" 5 "$rc"
printf '1\t2026-10-01T00:00:00Z\t%s\t0\n' "$sha" >"$tmp/wc-zero.tsv"
run "$tmp/wc-zero.tsv"
check_eq "a zero wall-clock fails closed" 5 "$rc"
printf '1|x\t2026-10-01T00:00:00Z\t%s\t5\n' "$sha" >"$tmp/wc-bad.tsv"
run "$tmp/wc-bad.tsv"
check_eq "a malformed capture row fails closed" 5 "$rc"

printf -- '- 2026-08-13 [demo] untracked.\n' >"$o/entries/2026-08-13-untracked-ccccccc1.md"
run
check_eq "an uncommitted fragment fails closed" 5 "$rc"
rm "$o/entries/2026-08-13-untracked-ccccccc1.md"

run
check_eq "the clean fixture still passes" 0 "$rc"
out=$("$SB" --as-of 2026-10-31 --spec "$fx/bundles/demo" --legacy "$fx/legacy.tsv" \
  --wallclock "$rec/wc.tsv" --hand-backs "$rec/hand-backs.tsv" --out "$tmp/cb.md" 2>&1)
check_eq "--out writes the snapshot" "$first" "$(cat "$tmp/cb.md")"
printf 'kept\n' >"$tmp/keep.md"
"$SB" --as-of 2026-10-31 --spec "$fx/bundles/demo" --legacy "$fx/legacy.tsv" \
  --wallclock "$tmp/wc-zero.tsv" --hand-backs "$rec/hand-backs.tsv" --out "$tmp/keep.md" 2>/dev/null
check_eq "a failed run leaves --out untouched" "kept" "$(cat "$tmp/keep.md")"

# The baseline's own inputs inside the repository must match HEAD too.
cp "$rec/hand-backs.tsv" "$fx/hb-in-repo.tsv"
out=$(cd "$fx" && TZ=UTC "$SB" --as-of 2026-10-31 --spec bundles/demo --legacy legacy.tsv \
  --wallclock "$rec/wc.tsv" --hand-backs hb-in-repo.tsv 2>&1)
check_eq "an untracked hand-back record fails closed through a relative path" 5 "$?"
rm "$fx/hb-in-repo.tsv"

out=$("$SB" --as-of 2026-10-31 --spec "$fx/bundles/demo" --legacy "$fx/legacy.tsv" \
  --wallclock "$rec/wc.tsv" --hand-backs "$rec/hand-backs.tsv" 2>&1)
check_has "the snapshot names the capture it read" "$out" "wall-clock from \`$rec/wc.tsv\`"

ctl=$(printf '\033')
cp "$rec/wc.tsv" "$tmp/wc${ctl}x.tsv"
out=$("$SB" --as-of 2026-10-31 --spec "$fx/bundles/demo" --legacy "$fx/legacy.tsv" \
  --wallclock "$tmp/wc${ctl}x.tsv" --hand-backs "$rec/hand-backs.tsv" 2>&1)
check_eq "a control byte in a capture path still renders" 0 "$?"
check_has "the cleaned path is printed" "$out" "wall-clock from \`$tmp/wcx.tsv\`"
case $out in
  *"$ctl"*) bad "a control byte in a path reached the snapshot" ;;
  *) ok "a control byte in a path never reaches the snapshot" ;;
esac

printf '1\t2026-02-30T00:00:00Z\t%s\t5\n' "$sha" >"$tmp/wc-feb.tsv"
run "$tmp/wc-feb.tsv"
check_eq "a wall-clock run on an impossible date fails closed" 5 "$rc"
out=$("$SB" --as-of 2026-02-31 --spec "$fx/bundles/demo" 2>&1)
check_eq "an impossible as-of date is a usage error" 2 "$?"
out=$(cd "$fx" && GIT_DIR=/nonexistent "$SB" --as-of 2026-10-31 --spec "$fx/bundles/demo" --legacy "$fx/legacy.tsv" \
  --wallclock "$rec/wc.tsv" --hand-backs "$rec/hand-backs.tsv" 2>&1)
check_eq "an inherited git environment is ignored" 0 "$?"

printf '1\t2026-10-01T00:00:00Z\t%s\t5\n1\t2026-10-02T00:00:00Z\t%s\t6\n' "$sha" "$sha" >"$tmp/wc-dup.tsv"
run "$tmp/wc-dup.tsv"
check_eq "a repeated wall-clock run fails closed" 5 "$rc"
printf '1\t2026-11-01T00:00:00Z\t%s\t5\n' "$sha" >"$tmp/wc-late.tsv"
run "$tmp/wc-late.tsv"
check_eq "a wall-clock run after the as-of date fails closed" 5 "$rc"

mkdir "$tmp/outdir"
out=$("$SB" --as-of 2026-10-31 --spec "$fx/bundles/demo" --legacy "$fx/legacy.tsv" \
  --wallclock "$rec/wc.tsv" --hand-backs "$rec/hand-backs.tsv" --out "$tmp/outdir" 2>&1)
check_eq "--out naming a directory fails closed" 5 "$?"

# Each case below commits its change so only the change itself can fail it.
fxcommit() {
  git -C "$fx" add -A -- bundles >/dev/null
  GIT_AUTHOR_DATE=2026-05-02T10:00:00Z GIT_COMMITTER_DATE=2026-05-02T10:00:00Z \
    git -C "$fx" -c core.hooksPath=/dev/null commit -q -m "docs: $1" >/dev/null
}
printf -- '- 2025-13-05 [demo] an impossible month.\n' >>"$o/opportunities.md"
fxcommit "bad month"
run
check_eq "an impossible date fails closed" 5 "$rc"
git -C "$fx" -c core.hooksPath=/dev/null revert --no-edit HEAD >/dev/null
printf -- '- undated.\n' >"$o/entries/notes-ddddddd1.md"
fxcommit "undated fragment"
run
check_eq "an undated fragment name fails closed" 5 "$rc"
git -C "$fx" -c core.hooksPath=/dev/null revert --no-edit HEAD >/dev/null
run
check_eq "the fixture is clean again" 0 "$rc"

shallow=$tmp/shallow
git clone -q --depth 1 "file://$fx" "$shallow" 2>/dev/null
cp "$fx/scripts/substrate-baseline.sh" "$fx/scripts/substrate-attribute.sh" "$shallow/scripts/"
out=$("$shallow/scripts/substrate-baseline.sh" --as-of 2026-10-31 --spec "$shallow/bundles/demo" \
  --legacy "$shallow/legacy.tsv" --wallclock "$rec/wc.tsv" --hand-backs "$rec/hand-backs.tsv" 2>&1)
check_eq "a shallow clone fails closed" 5 "$?"

# Capture: the newest runs on or before the as-of date, timed from the step.
stub=$tmp/bin
mkdir -p "$stub"
cat >"$stub/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "run list")
    printf '%s\n' '[{"databaseId":7,"createdAt":"2026-10-30T01:00:00Z","headSha":"7777777777777777777777777777777777777777"},{"databaseId":9,"createdAt":"2026-11-02T01:00:00Z","headSha":"9999999999999999999999999999999999999999"},{"databaseId":8,"createdAt":"2026-10-31T23:00:00Z","headSha":"8888888888888888888888888888888888888888"},{"databaseId":6,"createdAt":"2026-10-29T01:00:00Z","headSha":"6666666666666666666666666666666666666666"}]'
    ;;
  "run view")
    # Each run its own duration, so a capture reading the wrong run shows.
    end=$((10 + $3))
    jq -r "$7" <<JSON
{"jobs":[{"name":"other","steps":[]},{"name":"check","steps":[{"name":"Run mise run check","startedAt":"2026-10-30T01:00:00Z","completedAt":"2026-10-30T01:10:${end}Z"}]}]}
JSON
    ;;
  *) exit 9 ;;
esac
EOF
chmod +x "$stub/gh"
out=$(PATH="$stub:$PATH" "$SB" --capture-wallclock --as-of 2026-10-31 --runs 2 2>"$tmp/err")
check_eq "capture exits zero" 0 "$?"
check_eq "capture keeps the newest runs on or before the date, each with its own time" "8	2026-10-31T23:00:00Z	8888888888888888888888888888888888888888	618
7	2026-10-30T01:00:00Z	7777777777777777777777777777777777777777	617" "$(printf '%s\n' "$out" | grep -v '^#')"
out=$(PATH="$stub:$PATH" "$SB" --capture-wallclock --as-of 2026-10-31 --runs 5 2>/dev/null)
check_eq "a capture short of --runs fails closed" 5 "$?"
cp "$stub/gh" "$tmp/gh.keep"
sed 's/"headSha":"8888888888888888888888888888888888888888"/"headSha":"s8"/' "$tmp/gh.keep" >"$stub/gh"
out=$(PATH="$stub:$PATH" "$SB" --capture-wallclock --as-of 2026-10-31 --runs 2 2>/dev/null)
check_eq "a capture with a malformed head fails closed" 5 "$?"
sed 's/"databaseId":8,/"databaseId":"8x",/' "$tmp/gh.keep" >"$stub/gh"
out=$(PATH="$stub:$PATH" "$SB" --capture-wallclock --as-of 2026-10-31 --runs 2 2>/dev/null)
check_eq "a capture with a non-numeric run id fails closed" 5 "$?"
sed 's/"name":"Run mise run check"/"name":"Run something else"/' "$tmp/gh.keep" >"$stub/gh"
out=$(PATH="$stub:$PATH" "$SB" --capture-wallclock --as-of 2026-10-31 --runs 2 2>/dev/null)
check_eq "a run with no timed check step fails closed" 5 "$?"
cp "$tmp/gh.keep" "$stub/gh"

sed 's/^    jq -r .*/    exit 1/' "$stub/gh" >"$stub/gh.new" && mv "$stub/gh.new" "$stub/gh" && chmod +x "$stub/gh"
out=$(PATH="$stub:$PATH" "$SB" --capture-wallclock --as-of 2026-10-31 --runs 2 2>/dev/null)
check_eq "a run gh cannot read fails the capture" 5 "$?"
check_eq "a failed capture prints nothing" "" "$out"

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all substrate-baseline tests passed"
