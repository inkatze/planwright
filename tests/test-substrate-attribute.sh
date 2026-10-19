#!/bin/bash
# Tests for scripts/substrate-attribute.sh — observation attribution to tiers
# and defect classes (universal-binary REQ-A1.2).
#
# One fixture bundle cites fragments naming a script in each tier, by each
# naming form, plus a fragment naming none (attributed by the manual file)
# and two legacy-log lines. Copies vary one input each: a fragment with no
# manual row, a stale manual row, an unknown group label, a missing fragment,
# an ambiguous legacy match.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-substrate-attribute.sh
# shellcheck disable=SC2016 # fixture fragments carry literal Markdown backticks, never a substitution
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
SA="$REPO_ROOT/scripts/substrate-attribute.sh"

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

[ -x "$SA" ] || {
  echo "FAIL: scripts/substrate-attribute.sh missing or not executable" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-substrate-attribute.XXXXXX") || exit 1
[ -n "$tmp" ] && [ -d "$tmp" ] || exit 1
trap 'rm -rf "$tmp"' EXIT

build() {
  fx=$1
  mkdir -p "$fx/bundles/demo" "$fx/bundles/_observations/entries" "$fx/bundles/_observations/archive"
  cat >"$fx/bundles/demo/requirements.md" <<'EOF'
# Demo

## Goal

Cites obs:99999999 outside the Sources, which is not the mined set.

## Sources

- **Observations, lock and concurrency class:** obs:aaaaaaa1, obs:aaaaaaa3.
  More prose.
- **Observations, parser-fragility class:** obs:aaaaaaa2,
  obs:aaaaaaa3, obs:aaaaaaa6.
- **Observations, auditability and keep-shell evidence:** obs:aaaaaaa4,
  obs:aaaaaaa5.
- **Some other source.** No citations here.

## After

obs:88888888 is past the Sources.
EOF
  o=$fx/bundles/_observations
  printf '%s\n' '- 2026-07-12 [demo] `scripts/hooked.sh` loses a lock.' >"$o/entries/2026-07-12-hooked-aaaaaaa1.md"
  printf '%s\n' '- 2026-07-13 [demo] tests/test-skilled.sh parses by hand.' >"$o/entries/2026-07-13-skilled-aaaaaaa2.md"
  printf '%s\n' '- 2026-08-01 [demo] the `libbed` reader duplicates a lock.' >"$o/entries/2026-08-01-libbed-aaaaaaa3.md"
  printf '%s\n' '- 2026-08-02 [demo] devtool.sh and gone.sh read alike.' >"$o/entries/2026-08-02-devtool-aaaaaaa4.md"
  printf '%s\n' '- 2026-08-03 [demo] githooks/pre-commit was replayed offline.' >"$o/archive/2026-08-03-hook-aaaaaaa5.md"
  printf '%s\n' '- 2026-08-04 [demo] the ready-flip step and testonly prose name no script.' >"$o/entries/2026-08-04-none-aaaaaaa6.md"
  cat >"$o/opportunities.md" <<'EOF'
# Observations log

- 2026-06-11 [demo] range globs differ by locale in devtool.sh.
- 2026-06-12 [demo] the double chain runs twice, naming nothing.
- 2026-06-13 [demo] the double chain again.
EOF
  cat >"$fx/legacy.tsv" <<'EOF'
# id	classes	match
legacy:2026-06-11:range-globs	portability	range globs differ
legacy:2026-06-12:double-chain	perf-spawn-cost,duplicated-primitive	double chain
EOF
  cat >"$fx/manual.tsv" <<'EOF'
# id	tiers	reason
obs:aaaaaaa6	tests-only,library	names the testonly helper in prose
legacy:2026-06-12:double-chain	skill-called	the chain a skill runs
EOF
  cat >"$fx/partition.tsv" <<'EOF'
path	tier	flag	callers	mutation	profile	unresolved
githooks/pre-commit	hook	-	git	-	-	-
scripts/devtool.sh	dev-check	-	task	-	-	-
scripts/hooked.sh	hook	-	hook	-	-	-
scripts/libbed.sh	library	-	script	-	-	-
scripts/skilled.sh	skill-called	-	skill	-	-	-
scripts/testonly.sh	tests-only	no-live-caller	test	-	-	-
EOF
}

run() { # run <fixture> <extra args...>; sets out, err, rc
  fx=$1
  shift
  out=$("$SA" --as-of 2026-09-30 --spec "$fx/bundles/demo" --partition "$fx/partition.tsv" \
    --legacy "$fx/legacy.tsv" --manual "$fx/manual.tsv" "$@" 2>"$tmp/err")
  rc=$?
  err=$(cat "$tmp/err")
}

base=$tmp/base
build "$base"

# REQ-A1.2: every fragment and line maps to its tier and class; the
# script-less ones through the manual file.
run "$base" --rows
check_eq "rows exit zero" 0 "$rc"
expected='legacy:2026-06-11:range-globs	2026-06-11	dev-check	portability	script	scripts/devtool.sh
legacy:2026-06-12:double-chain	2026-06-12	skill-called	duplicated-primitive,perf-spawn-cost	manual	-
obs:aaaaaaa1	2026-07-12	hook	lock-concurrency	script	scripts/hooked.sh
obs:aaaaaaa2	2026-07-13	skill-called	parser-fragility	script	scripts/skilled.sh
obs:aaaaaaa3	2026-08-01	library	lock-concurrency,parser-fragility	script	scripts/libbed.sh
obs:aaaaaaa4	2026-08-02	dev-check	auditability	script	scripts/devtool.sh,not-in-layer:gone.sh
obs:aaaaaaa5	2026-08-03	hook	auditability	script	githooks/pre-commit
obs:aaaaaaa6	2026-08-04	tests-only,library	parser-fragility	manual	-'
check_eq "each item lands in its tier and class" "$expected" "$out"

run "$base" --class-map
check_eq "class map exit zero" 0 "$rc"
check_has "class map carries a legacy line's classes" "$out" "legacy:2026-06-12:double-chain	2026-06-12	duplicated-primitive,perf-spawn-cost"
check_has "class map carries a two-group fragment" "$out" "obs:aaaaaaa3	2026-08-01	lock-concurrency,parser-fragility"

run "$base"
check_eq "snapshot exit zero" 0 "$rc"
first=$out
check_has "snapshot is dated" "$out" "# Substrate pain matrix, as of 2026-09-30"
check_has "matrix hook row" "$out" "| hook | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 2 |"
check_has "matrix library row counts both classes" "$out" "| library | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2 |"
check_has "matrix tests-only row from the manual file" "$out" "| tests-only | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 |"
check_has "manual count" "$out" "| attributed by the manual file | 2 |"
run "$base"
check_eq "snapshot regenerates byte-identically" "$first" "$out"

# A script-less fragment without a manual row is reported, never dropped.
v=$tmp/needs
build "$v"
grep -v '^obs:aaaaaaa6' "$v/manual.tsv" >"$v/m" && mv "$v/m" "$v/manual.tsv"
run "$v"
check_eq "needs-manual exits 1" 1 "$rc"
check_has "needs-manual names the fragment" "$err" "needs-manual	obs:aaaaaaa6"
check_eq "needs-manual writes no snapshot" "" "$out"

v=$tmp/stale
build "$v"
printf 'obs:aaaaaaa1\thook\tredundant\n' >>"$v/manual.tsv"
run "$v"
check_eq "stale manual row exits 1" 1 "$rc"
check_has "stale manual row is named" "$err" "stale-manual	obs:aaaaaaa1"

v=$tmp/orphan
build "$v"
printf 'obs:bbbbbbb1\thook\tnot mined\n' >>"$v/manual.tsv"
run "$v"
check_eq "orphan manual row exits 1" 1 "$rc"
check_has "orphan manual row is named" "$err" "orphan-manual	obs:bbbbbbb1"

v=$tmp/badtier
build "$v"
printf 'obs:bbbbbbb2\tkernel\tno such tier\n' >>"$v/manual.tsv"
run "$v"
check_eq "unknown manual tier fails closed" 5 "$rc"

v=$tmp/label
build "$v"
sed 's/parser-fragility class/parsing woes class/' "$v/bundles/demo/requirements.md" >"$v/r" && mv "$v/r" "$v/bundles/demo/requirements.md"
run "$v"
check_eq "a group label naming no class fails closed" 5 "$rc"
check_has "the label is named" "$err" "parsing woes"

v=$tmp/badclass
build "$v"
printf 'legacy:2026-06-13:again\tnew-class\tchain again\n' >>"$v/legacy.tsv"
run "$v"
check_eq "a legacy class outside the fixed set fails closed" 5 "$rc"

v=$tmp/missing
build "$v"
rm "$v/bundles/_observations/archive/2026-08-03-hook-aaaaaaa5.md"
run "$v"
check_eq "a cited UID with no fragment fails closed" 5 "$rc"
check_has "the UID is named" "$err" "obs:aaaaaaa5"

v=$tmp/twice
build "$v"
cp "$v/bundles/_observations/entries/2026-07-12-hooked-aaaaaaa1.md" "$v/bundles/_observations/archive/2026-07-12-hooked-aaaaaaa1.md"
run "$v"
check_eq "a UID resolving to two fragments fails closed" 5 "$rc"

v=$tmp/ambiguous
build "$v"
printf 'legacy:2026-06-12:chain\tportability\tchain\n' >>"$v/legacy.tsv"
printf -- '- 2026-06-12 [demo] another chain.\n' >>"$v/bundles/_observations/opportunities.md"
run "$v"
check_eq "a legacy match on two lines fails closed" 5 "$rc"

run "$base" --as-of 2026-9-30
check_eq "a malformed date is a usage error" 2 "$rc"

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all substrate-attribute tests passed"
