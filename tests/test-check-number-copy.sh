#!/bin/bash
# Tests for scripts/check-number-copy.sh — the cite-don't-copy guard over a
# bundle's prose and the dated snapshots (universal-binary REQ-A1.4).
#
# One clean fixture bundle and snapshot directory; each case copies it and
# plants one figure where the guard must fire or must stay quiet.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-check-number-copy.sh
# shellcheck disable=SC2016 # sed scripts carry literal Markdown backticks, never a substitution
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
CN="$REPO_ROOT/scripts/check-number-copy.sh"

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

[ -x "$CN" ] || {
  echo "FAIL: scripts/check-number-copy.sh missing or not executable" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-check-number-copy.XXXXXX") || exit 1
[ -n "$tmp" ] && [ -d "$tmp" ] || exit 1
trap 'rm -rf "$tmp"' EXIT

build() {
  fx=$1
  mkdir -p "$fx/b" "$fx/snap"
  cat >"$fx/b/requirements.md" <<'EOF'
# Demo

**Format-version:** 2

## REQ-A

- **REQ-A1.1** The matrix SHALL be cited, never copied.

## Changelog

- 2026-09-09 — Draft.

## Sources

- Drafting counts: nothing yet.
EOF
  cat >"$fx/b/design.md" <<'EOF'
# Design

### D-1: A decision

**Decision:** cite the snapshot.

**Measurement:** pending.

### D-2: Another

**Decision:** also cite.
EOF
  cat >"$fx/b/tasks.md" <<'EOF'
# Tasks

### Task 1 — First

- **Dependencies:** none
- **Estimated effort:** 663 days
EOF
  printf '# Test spec\n\nNothing numeric.\n' >"$fx/b/test-spec.md"
  cat >"$fx/snap/baseline-2026-10-18.md" <<'EOF'
# Baseline

| month | commits |
| --- | ---: |
| 2026-07 | 663 |
| 2026-08 | 1234 |
| 2026-09 | 41.5 |
EOF
  printf '# file\tfigure\treason\n' >"$fx/exempt.tsv"
}

run() { # run <fixture>; sets out, rc
  out=$("$CN" --bundle "$1/b" --snapshots "$1/snap" --exempt "$1/exempt.tsv" 2>&1)
  rc=$?
}

append() { printf '%s\n' "$2" >>"$1"; }

# after <file> <ere> <line>...: insert the lines after the first line matching
# the pattern (awk, since BSD sed has no `\n` in a replacement).
after() {
  af_file=$1 af_re=$2
  shift 2
  # The pattern travels through the environment: gawk's -v would read its
  # backslashes as escapes.
  AF_RE=$af_re awk 'BEGIN { re = ENVIRON["AF_RE"]; for (i = 1; i < ARGC; i++) { add[i] = ARGV[i]; delete ARGV[i] }; n = ARGC - 1; ARGC = 1 }
    { print } !done && $0 ~ re { for (i = 1; i <= n; i++) print add[i]; done = 1 }' "$@" <"$af_file" >"$af_file.new" \
    && mv "$af_file.new" "$af_file"
}

v=$tmp/clean
build "$v"
run "$v"
check_eq "a clean bundle passes (metadata and dates are not figures)" 0 "$rc"

# REQ-A1.4: a snapshot figure copied into a requirement fails.
v=$tmp/req
build "$v"
after "$v/b/requirements.md" '^- \*\*REQ-A1\.1\*\* ' "- **REQ-A1.2** Fix commits SHALL stay under 663 a month."
run "$v"
check_eq "a copied figure in a requirement fails" 1 "$rc"
check_has "the finding names file, line and figure" "$out" "requirements.md:8: figure 663"

v=$tmp/sources
build "$v"
append "$v/b/requirements.md" "- Drafting baseline: 663 commits in July."
run "$v"
check_eq "the figure only under Sources passes" 0 "$rc"

v=$tmp/changelog
build "$v"
sed 's/- 2026-09-09 — Draft./- 2026-09-09 — Draft, 663 commits seen./' "$v/b/requirements.md" >"$v/r" && mv "$v/r" "$v/b/requirements.md"
run "$v"
check_eq "the figure only under Changelog passes" 0 "$rc"

v=$tmp/verdict
build "$v"
after "$v/b/design.md" '^\*\*Measurement:\*\* pending' 'and a median of 41.5 s against the shell median, 663 commits (report field `x`).'
run "$v"
check_eq "the figure in a verdict's measurement line passes" 0 "$rc"

v=$tmp/costbenefit
build "$v"
append "$v/b/design.md" "**Cost-benefit:** 663 fix commits a month at baseline."
run "$v"
check_eq "the figure in a verdict's cost-benefit line passes" 0 "$rc"

v=$tmp/afterverdict
build "$v"
after "$v/b/design.md" '^\*\*Measurement:\*\* pending' "" "The body then says 663 again."
run "$v"
check_eq "a paragraph after the measurement line is prose again" 1 "$rc"

v=$tmp/outsidedecision
build "$v"
printf '\n## Notes\n\n**Measurement:** 663 outside any decision.\n' >>"$v/b/design.md"
run "$v"
check_eq "a measurement label outside a decision is not exempt" 1 "$rc"

v=$tmp/refs
build "$v"
append "$v/b/tasks.md" "- **Deliverables:** see Task 663, Tasks 5, 663 and 1234, section 41.5."
run "$v"
check_eq "a numeral naming a task or section is a reference" 0 "$rc"

v=$tmp/ids
build "$v"
append "$v/b/test-spec.md" "REQ-A663, D-663, obs:663, v663x, 2026-08-663 and path/663 are identifiers."
run "$v"
check_eq "identifiers glued to a figure are not figures" 0 "$rc"

v=$tmp/commas
build "$v"
append "$v/b/test-spec.md" "There were 1,234 of them."
run "$v"
check_eq "a thousands-comma figure matches its plain form" 1 "$rc"
check_has "the comma figure is normalised" "$out" "figure 1234"

v=$tmp/decimal
build "$v"
append "$v/b/test-spec.md" "A median of 41.5 seconds."
run "$v"
check_eq "a decimal figure matches" 1 "$rc"

v=$tmp/other
build "$v"
append "$v/b/test-spec.md" "Twelve writers over 999 runs."
run "$v"
check_eq "a figure no snapshot carries does not fire" 0 "$rc"

v=$tmp/exempt
build "$v"
append "$v/b/test-spec.md" "A median of 41.5 seconds."
printf 'test-spec.md\t41.5\ta coincidence, documented\n' >>"$v/exempt.tsv"
run "$v"
check_eq "an exempted figure passes" 0 "$rc"

v=$tmp/stale
build "$v"
printf 'test-spec.md\t41.5\tno longer present\n' >>"$v/exempt.tsv"
run "$v"
check_eq "a stale exemption fails" 1 "$rc"
check_has "the stale exemption is named" "$out" "stale exemption: test-spec.md 41.5"

v=$tmp/reasonless
build "$v"
printf 'test-spec.md\t41.5\t\n' >>"$v/exempt.tsv"
run "$v"
check_eq "an exemption without a reason fails closed" 5 "$rc"

v=$tmp/indentmeta
build "$v"
append "$v/b/tasks.md" "  **Estimated effort:** 663 days"
run "$v"
check_eq "an indented metadata line is not prose" 0 "$rc"

v=$tmp/nested
build "$v"
append "$v/b/design.md" "- **Measurement:** the report fields:"
append "$v/b/design.md" "  - median 41.5 s"
append "$v/b/design.md" "    and 663 commits"
append "$v/b/design.md" "- A sibling bullet says 663 again."
run "$v"
check_eq "a measurement's sub-items belong to it; its sibling does not" 1 "$rc"
check_has "only the sibling fires" "$out" "design.md:15: figure 663"
check_eq "exactly one finding" 1 "$(printf '%s\n' "$out" | grep -c figure)"

v=$tmp/ranges
build "$v"
append "$v/b/tasks.md" "See Tasks 1 through 663, Tasks 1–663 and Waves 663."
run "$v"
check_eq "task ranges and capitalised waves are references" 0 "$rc"

v=$tmp/formats
build "$v"
append "$v/b/test-spec.md" "A median of 41.50 seconds and 0663 commits."
run "$v"
check_eq "trailing and leading zeros compare as the same figure" 1 "$rc"
check_eq "both variants fire" 2 "$(printf '%s\n' "$out" | grep -c figure)"

v=$tmp/commaexempt
build "$v"
append "$v/b/test-spec.md" "There were 1,234 of them."
printf 'test-spec.md\t1,234\ta coincidence\n' >>"$v/exempt.tsv"
run "$v"
check_eq "an exemption written with commas matches" 0 "$rc"

v=$tmp/dangling
build "$v"
ln -s "$v/missing.md" "$v/snap/gone.md"
run "$v"
check_eq "a dangling snapshot symlink fails closed" 5 "$rc"

v=$tmp/ctl
build "$v"
printf 'test-spec.md\0339\t41.5\tstale\n' | tr '9' '[' >>"$v/exempt.tsv"
run "$v"
check_eq "a stale exemption with a control byte in its file still fails" 1 "$rc"
check_has "the stale row is printed" "$out" "stale exemption: test-spec.md[ 41.5"
case $out in
  *"$(printf '\033')"*) bad "a control byte reached the output" ;;
  *) ok "no control byte reaches the output" ;;
esac

v=$tmp/refthenfigure
build "$v"
append "$v/b/tasks.md" "Task 3 adds 663 commits a month."
run "$v"
check_eq "a figure after a reference on the same line still fires" 1 "$rc"

v=$tmp/metavalues
build "$v"
sed 's/^\*\*Format-version:\*\* 2$/**Format-version:** 663/; s/^- \*\*Dependencies:\*\* none$/- **Dependencies:** 663/' \
  "$v/b/requirements.md" >"$v/r" && mv "$v/r" "$v/b/requirements.md"
sed 's/^- \*\*Dependencies:\*\* none$/- **Dependencies:** 663/' "$v/b/tasks.md" >"$v/t" && mv "$v/t" "$v/b/tasks.md"
run "$v"
check_eq "Format-version and Dependencies values are not figures" 0 "$rc"

v=$tmp/aftersources
build "$v"
printf '\n## Later\n\nThe body says 663 again.\n' >>"$v/b/requirements.md"
run "$v"
check_eq "prose after the Sources section is checked again" 1 "$rc"

v=$tmp/verdictends
build "$v"
append "$v/b/design.md" "- **Measurements:** 663 commits (report field x)."
append "$v/b/design.md" "- **Cost-benefit:** 663 a month."
append "$v/b/design.md" "- A sibling item says 41.5."
run "$v"
check_eq "a plural label and a list-form label are exempt; the next item is not" 1 "$rc"
check_eq "only the sibling item fires" 1 "$(printf '%s\n' "$out" | grep -c figure)"

v=$tmp/headingends
build "$v"
append "$v/b/design.md" "**Measurement:** 663 commits"
append "$v/b/design.md" "### D-3: Next"
append "$v/b/design.md" "Body 663."
run "$v"
check_eq "a heading ends a measurement paragraph" 1 "$rc"

v=$tmp/nondecision
build "$v"
printf '\n### Notes\n\n**Measurement:** 663 outside a decision heading.\n' >>"$v/b/design.md"
run "$v"
check_eq "a measurement label under a non-decision heading is not exempt" 1 "$rc"

v=$tmp/exemptfile
build "$v"
append "$v/b/test-spec.md" "A median of 41.5 seconds."
printf 'design.md\t41.5\tthe other file\n' >>"$v/exempt.tsv"
run "$v"
check_eq "an exemption covers its own file only" 1 "$rc"
check_has "the other file's row is stale" "$out" "stale exemption: design.md 41.5"

v=$tmp/tsvsnap
build "$v"
printf '9999\t9998\n' >"$v/snap/capture.tsv"
append "$v/b/test-spec.md" "A count of 9999."
run "$v"
check_eq "only Markdown snapshots carry figures" 0 "$rc"

v=$tmp/missing
build "$v"
out=$("$CN" --bundle "$v/b" --snapshots "$v/nosuch" --exempt "$v/exempt.tsv" 2>&1)
check_eq "a missing snapshot directory fails closed" 5 "$?"
out=$("$CN" --bundle "$v/b" --snapshots "$v/snap" --exempt "$v/nosuch.tsv" 2>&1)
check_eq "a missing exemption list fails closed" 5 "$?"

v=$tmp/singularcomma
build "$v"
append "$v/b/tasks.md" "After Task 3, 663 items remain."
run "$v"
check_eq "a singular reference's comma does not continue it" 1 "$rc"

v=$tmp/singularrange
build "$v"
append "$v/b/tasks.md" "Done in Task 3–663 and Task 1 through 663."
run "$v"
check_eq "the end of a singular's range is a reference" 0 "$rc"

v=$tmp/deepheading
build "$v"
append "$v/b/design.md" "**Measurement:** 663 measured."
append "$v/b/design.md" "#### Follow-up"
append "$v/b/design.md" "Then 663 more."
run "$v"
check_eq "a deeper heading ends a measurement paragraph" 1 "$rc"

v=$tmp/hashline
build "$v"
append "$v/b/design.md" "**Measurement:** 41.5 s median, as recorded in"
append "$v/b/design.md" "#408 and 663 commits."
run "$v"
check_eq "a line opening with #408 is not a heading" 0 "$rc"

v=$tmp/nofigure
build "$v"
printf '# Nothing numeric\n' >"$v/snap/baseline-2026-10-18.md"
run "$v"
check_eq "snapshots carrying no figure fail closed" 5 "$rc"

v=$tmp/badcomma
build "$v"
append "$v/b/test-spec.md" "A median of 41.5 seconds."
printf 'test-spec.md\t4,,1.5\tmalformed grouping\n' >>"$v/exempt.tsv"
run "$v"
check_eq "an exemption with malformed comma groups fails closed" 5 "$rc"

v=$tmp/badexempt
build "$v"
printf 'test-spec.md\tx\tnot a figure\n' >>"$v/exempt.tsv"
run "$v"
check_eq "an exemption whose figure is not a number fails closed" 5 "$rc"

# The default snapshot set, from a copy laid out like the repository.
v=$tmp/defaults
build "$v"
mkdir -p "$v/repo/scripts" "$v/repo/docs/substrate"
cp "$CN" "$REPO_ROOT/scripts/spec-parse.sh" "$v/repo/scripts/"
printf '# file\tfigure\treason\n' >"$v/repo/scripts/check-number-copy-exempt.tsv"
printf '# Screen\n\n4127 candidates.\n' >"$v/repo/docs/substrate-screen.md"
cp "$v/snap/baseline-2026-10-18.md" "$v/repo/docs/substrate/"
append "$v/b/test-spec.md" "Screened 4127 of them."
out=$("$v/repo/scripts/check-number-copy.sh" --bundle "$v/b" 2>&1)
check_eq "docs/substrate-*.md is a snapshot by default" 1 "$?"
check_has "the flat snapshot is named" "$out" "snapshot substrate-screen.md"

v=$tmp/nobundle
build "$v"
rm "$v/b/tasks.md"
run "$v"
check_eq "a missing bundle file fails closed" 5 "$rc"

v=$tmp/nosnap
build "$v"
rm "$v/snap/baseline-2026-10-18.md"
run "$v"
check_eq "an empty snapshot directory fails closed" 5 "$rc"

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-number-copy tests passed"
