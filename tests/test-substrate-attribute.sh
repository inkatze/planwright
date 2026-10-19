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
run "$base" --as-of 2026-13-01
check_eq "a month out of range is a usage error" 2 "$rc"
run "$base" --as-of "$(printf '2026-09-30\nX')"
check_eq "a date with a second line is a usage error" 2 "$rc"
run "$base" --as-of 2026-07-31
check_eq "an item dated after the as-of date fails closed" 5 "$rc"
check_has "the late item is named" "$err" "obs:aaaaaaa3"

out=$("$SA" --classes)
check_eq "the class list is printed in matrix order" "lock-concurrency" "$(printf '%s\n' "$out" | sed -n 1p)"
check_eq "the class list has eleven classes" 11 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"

run "$base" --out "$tmp/snap.md"
check_eq "--out exits zero" 0 "$rc"
check_eq "--out writes the snapshot" "$first" "$(cat "$tmp/snap.md")"
printf 'kept\n' >"$tmp/keep.md"
run "$tmp/ambiguous" --out "$tmp/keep.md"
check_eq "a failed run leaves --out untouched" "kept" "$(cat "$tmp/keep.md")"

v=$tmp/emptylegacy
build "$v"
: >"$v/legacy.tsv"
grep -v '^legacy:' "$v/manual.tsv" >"$v/m" && mv "$v/m" "$v/manual.tsv"
run "$v" --rows
check_eq "an empty legacy index is an empty set" 0 "$rc"

v=$tmp/noclasses
build "$v"
printf 'legacy:2026-06-13:again\t\tchain again\n' >>"$v/legacy.tsv"
run "$v"
check_eq "a legacy row with no classes fails closed" 5 "$rc"

v=$tmp/sameline
build "$v"
printf 'legacy:2026-06-11:dup\tportability\tdiffer by locale\n' >>"$v/legacy.tsv"
run "$v"
check_eq "two legacy rows on one line fail closed" 5 "$rc"

v=$tmp/notiers
build "$v"
sed 's/^obs:aaaaaaa6\ttests-only,library\t/obs:aaaaaaa6\t\t/' "$v/manual.tsv" >"$v/m" && mv "$v/m" "$v/manual.tsv"
run "$v"
check_eq "a manual row with no tiers fails closed" 5 "$rc"

v=$tmp/duptier
build "$v"
sed 's/^obs:aaaaaaa6\ttests-only,library\t/obs:aaaaaaa6\ttests-only,tests-only\t/' "$v/manual.tsv" >"$v/m" && mv "$v/m" "$v/manual.tsv"
run "$v" --rows
check_has "a repeated manual tier counts once" "$out" "obs:aaaaaaa6	2026-08-04	tests-only	parser-fragility	manual"

v=$tmp/badpart
build "$v"
printf 'scripts/odd.sh\tentry-point\t-\t-\t-\t-\t-\n' >>"$v/partition.tsv"
run "$v"
check_eq "a partition tier outside the fixed set fails closed" 5 "$rc"

v=$tmp/dupstem
build "$v"
printf 'scripts/pre-commit.sh\thook\t-\t-\t-\t-\t-\n' >>"$v/partition.tsv"
run "$v"
check_eq "two layer scripts sharing a stem fail closed" 5 "$rc"

v=$tmp/stray
build "$v"
awk '{ print } /^  obs:aaaaaaa3, obs:aaaaaaa6.$/ { print ""; print "A stray paragraph cites obs:aaaaaaa1." }' \
  "$v/bundles/demo/requirements.md" >"$v/r" && mv "$v/r" "$v/bundles/demo/requirements.md"
run "$v"
check_eq "a citation in a paragraph after a group fails closed" 5 "$rc"

v=$tmp/wordobs
build "$v"
awk '{ print } /^- \*\*Some other source/ { print "  CI jobs:deadbeef ran." }' \
  "$v/bundles/demo/requirements.md" >"$v/r" && mv "$v/r" "$v/bundles/demo/requirements.md"
run "$v" --rows
check_eq "obs: inside a word is no citation" 0 "$rc"

v=$tmp/suffix
build "$v"
printf -- '- 2026-08-04 [demo] the hooked.shim wrapper and scripts/libbed.md and scripts/libbed/x are prose.\n' \
  >"$v/bundles/_observations/entries/2026-08-04-none-aaaaaaa6.md"
run "$v" --rows
check_has "a longer extension or a nested path names no script" "$out" "obs:aaaaaaa6	2026-08-04	tests-only,library	parser-fragility	manual	-"

v=$tmp/nodate
build "$v"
mv "$v/bundles/_observations/entries/2026-07-12-hooked-aaaaaaa1.md" "$v/bundles/_observations/entries/x-hooked-aaaaaaa1.md"
run "$v"
check_eq "a fragment name opening with no date fails closed" 5 "$rc"

v=$tmp/symlink
build "$v"
mv "$v/bundles/_observations/entries/2026-07-12-hooked-aaaaaaa1.md" "$v/real.md"
ln -s "$v/real.md" "$v/bundles/_observations/entries/2026-07-12-hooked-aaaaaaa1.md"
run "$v"
check_eq "a symlinked fragment fails closed" 5 "$rc"

v=$tmp/ctl
build "$v"
printf 'obs:bbbbbbb1z\033[2J\thook\tbad id\n' >>"$v/manual.tsv"
run "$v"
check_eq "a malformed manual id fails closed" 5 "$rc"
check_has "the malformed id is named" "$err" "malformed manual row: obs:bbbbbbb1z[2J"
case $err in
  *"$(printf '\033')"*) bad "a control byte reached stderr" ;;
  *) ok "no control byte reaches stderr" ;;
esac

# Naming forms and tiers the base fixture reaches only through the manual file.
v=$tmp/forms
build "$v"
awk '{ print } /^- \*\*Observations, parser-fragility class:\*\*/ { print "  obs:aaaaaaa7, obs:aaaaaaa8." }' \
  "$v/bundles/demo/requirements.md" >"$v/r" && mv "$v/r" "$v/bundles/demo/requirements.md"
printf -- '- 2026-08-05 [demo] testonly.sh and scripts/hooked and `libbed` and hooked.sh again.\n' \
  >"$v/bundles/_observations/entries/2026-08-05-many-aaaaaaa7.md"
printf -- '- 2026-08-06 [demo] scripts/hooked without its suffix.\n' \
  >"$v/bundles/_observations/entries/2026-08-06-bare-aaaaaaa8.md"
run "$v" --rows
check_has "several scripts in several tiers, each once" "$out" "obs:aaaaaaa7	2026-08-05	tests-only,hook,library	parser-fragility	script	scripts/testonly.sh,scripts/hooked.sh,scripts/libbed.sh"
check_has "scripts/<stem> without a suffix names the script" "$out" "obs:aaaaaaa8	2026-08-06	hook	parser-fragility	script	scripts/hooked.sh"

# The whole snapshot of the base fixture, so every row, count and column is
# pinned, not only a sample.
run "$base"
expected_rows='| tier | lock-concurrency | parser-fragility | echo-sanitization | duplicated-primitive | perf-spawn-cost | portability | lint-gap | plugin-delivery | test-flakiness | instruction-headroom | auditability | items |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| hook | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 2 |
| skill-called | 0 | 1 | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 2 |
| library | 1 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2 |
| dev-check | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 1 | 2 |
| tests-only | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 |
| any tier | 2 | 3 | 0 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 2 | 8 |'
check_eq "the matrix table is exact" "$expected_rows" "$(printf '%s\n' "$out" | sed -n '/^| tier |/,/^| any tier |/p')"
check_has "named-script count" "$out" "| attributed through a named script | 6 |"
check_has "nothing unattributed" "$out" "| unattributed | 0 |"
check_has "the regeneration command" "$out" "mise run substrate:attribute -- --as-of 2026-09-30 --out docs/substrate/pain-matrix-2026-09-30.md"
check_has "an attribution row with every column" "$out" "| obs:aaaaaaa4 | 2026-08-02 | dev-check | auditability | script | scripts/devtool.sh, not-in-layer:gone.sh |"
out=$(LC_ALL=en_US.UTF-8 "$SA" --as-of 2026-09-30 --spec "$base/bundles/demo" --partition "$base/partition.tsv" \
  --legacy "$base/legacy.tsv" --manual "$base/manual.tsv" 2>/dev/null)
check_eq "the caller's locale does not change the snapshot" "$first" "$out"

# Fail-closed paths, each by exit 5 rather than 1.
v=$tmp/outside
build "$v"
sed 's/^- \*\*Some other source.\*\* No citations here.$/- **Some other source.** It cites obs:aaaaaaa1./' \
  "$v/bundles/demo/requirements.md" >"$v/r" && mv "$v/r" "$v/bundles/demo/requirements.md"
run "$v"
check_eq "a citation in another Sources bullet fails closed" 5 "$rc"

v=$tmp/nohdr
build "$v"
sed 1d "$v/partition.tsv" >"$v/p" && mv "$v/p" "$v/partition.tsv"
run "$v"
check_eq "a partition with no header fails closed" 5 "$rc"

v=$tmp/noline
build "$v"
printf 'legacy:2026-06-14:none\tportability\tnothing on that day\n' >>"$v/legacy.tsv"
run "$v"
check_eq "a legacy match on no line fails closed" 5 "$rc"

v=$tmp/duplegacy
build "$v"
printf 'legacy:2026-06-11:range-globs\tportability\tdevtool.sh\n' >>"$v/legacy.tsv"
run "$v"
check_eq "a duplicate legacy id fails closed" 5 "$rc"

v=$tmp/dupmanual
build "$v"
printf 'obs:aaaaaaa6\tlibrary\tagain\n' >>"$v/manual.tsv"
run "$v"
check_eq "a duplicate manual row fails closed" 5 "$rc"

v=$tmp/noreason
build "$v"
printf 'obs:bbbbbbb3\thook\t\n' >>"$v/manual.tsv"
run "$v"
check_eq "a manual row with no reason fails closed" 5 "$rc"

out=$("$SA" --as-of 2026-09-30 --spec "$base/bundles/demo" --legacy "$base/legacy.tsv" --manual "$base/manual.tsv" 2>&1)
check_eq "the snapshot needs a partition" 2 "$?"

v=$tmp/upper
build "$v"
sed 's/obs:aaaaaaa1, obs:aaaaaaa3\./obs:aaaaaaa1, obs:aaaaaaa3, obs:AAAAAAA9./' \
  "$v/bundles/demo/requirements.md" >"$v/r" && mv "$v/r" "$v/bundles/demo/requirements.md"
run "$v"
check_eq "a citation whose UID is not lowercase hex fails closed" 5 "$rc"

v=$tmp/edges
build "$v"
printf -- '- 2026-08-04 [demo] replays githooks/pre-commit. Also myscripts/libbed and hooked.sh-old.\n' \
  >"$v/bundles/_observations/entries/2026-08-04-none-aaaaaaa6.md"
grep -v '^obs:aaaaaaa6' "$v/manual.tsv" >"$v/m" && mv "$v/m" "$v/manual.tsv"
run "$v" --rows
check_has "a hook ending a sentence is named; a longer word and suffix are not" "$out" "obs:aaaaaaa6	2026-08-04	hook	parser-fragility	script	githooks/pre-commit"

# A working copy: inputs inside a git repository must match HEAD, however the
# path is spelt.
v=$tmp/gitrepo
build "$v"
mkdir -p "$v/scripts"
cp "$SA" "$v/scripts/"
git -C "$v" init -q
git -C "$v" add -A >/dev/null
git -C "$v" -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false -c core.hooksPath=/dev/null \
  commit -q -m "fixture" >/dev/null
gitrun() {
  out=$(cd "$v" && /bin/sh scripts/substrate-attribute.sh --as-of 2026-09-30 --partition partition.tsv \
    --legacy legacy.tsv --manual manual.tsv "$@" 2>&1)
  rc=$?
}
gitrun --spec bundles/demo --rows
check_eq "a clean repository runs" 0 "$rc"
printf -- '- 2026-08-09 [demo] untracked.\n' >"$v/bundles/_observations/entries/2026-08-09-new-ccccccc1.md"
gitrun --spec bundles/demo --rows
check_eq "an untracked fragment fails closed through a relative --spec" 5 "$rc"
gitrun --spec ./bundles/../bundles/demo --rows
check_eq "and through a non-canonical one" 5 "$rc"
rm "$v/bundles/_observations/entries/2026-08-09-new-ccccccc1.md"
printf 'manual.tsv\n' >"$v/.gitignore"
git -C "$v" add .gitignore >/dev/null
git -C "$v" rm -q --cached manual.tsv >/dev/null
git -C "$v" -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false -c core.hooksPath=/dev/null \
  commit -q -m "ignore" >/dev/null
gitrun --spec bundles/demo --rows
check_eq "an ignored, untracked input fails closed too" 5 "$rc"

git -C "$v" rm -q --cached legacy.tsv >/dev/null 2>&1 || :
ln -s "$v/legacy.tsv" "$tmp/link.tsv"
gitrun --spec bundles/demo --legacy "$tmp/link.tsv" --rows
check_eq "an input reached through a file symlink fails closed" 5 "$rc"
# Pathspec magic in a path is literal: a dirty sibling a glob would match
# does not taint a clean input.
mkdir -p "$v/in*" "$v/inx"
cp "$v/legacy.tsv" "$v/in*/legacy.tsv"
cp "$v/legacy.tsv" "$v/inx/legacy.tsv"
printf '!manual.tsv\n' >>"$v/.gitignore"
git -C "$v" add -A >/dev/null
git -C "$v" -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false -c core.hooksPath=/dev/null \
  commit -q -m "glob dirs" >/dev/null
printf '# dirty\n' >>"$v/inx/legacy.tsv"
gitrun --spec bundles/demo --legacy 'in*/legacy.tsv' --rows
check_eq "a glob character in an input path matches nothing else" 0 "$rc"

out=$(cd "$tmp" && "$SA" --obs-dir --repo-root "$REPO_ROOT")
check_eq "--repo-root resolves the default bundle from that repository" \
  "$(cd "$REPO_ROOT" && /bin/sh scripts/resolve-root.sh spec)/_observations" "$out"

mkdir "$tmp/outdir"
run "$base" --out "$tmp/outdir"
check_eq "--out naming a directory fails closed" 5 "$rc"
(umask 022 && "$SA" --as-of 2026-09-30 --spec "$base/bundles/demo" --partition "$base/partition.tsv" \
  --legacy "$base/legacy.tsv" --manual "$base/manual.tsv" --out "$tmp/mode.md") 2>/dev/null
case $(ls -l "$tmp/mode.md") in
  -rw-r--r--*) ok "--out writes the mode a redirect would" ;;
  *) bad "--out wrote $(ls -l "$tmp/mode.md")" ;;
esac

out=$("$SA" --obs-dir --spec "$base/bundles/demo")
check_eq "--obs-dir prints the accumulator beside the bundle" "$base/bundles/_observations" "$out"

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all substrate-attribute tests passed"
