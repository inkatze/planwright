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

v=$tmp/clean
build "$v"
run "$v"
check_eq "a clean bundle passes (metadata and dates are not figures)" 0 "$rc"

# REQ-A1.4: a snapshot figure copied into a requirement fails.
v=$tmp/req
build "$v"
sed 's/^- \*\*REQ-A1.1\*\* .*/&\n- **REQ-A1.2** Fix commits SHALL stay under 663 a month./' "$v/b/requirements.md" >"$v/r" && mv "$v/r" "$v/b/requirements.md"
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
sed 's/^\*\*Measurement:\*\* pending./**Measurement:** median 41.5 s against\nthe shell median, 663 commits (report field `x`)./' "$v/b/design.md" >"$v/d" && mv "$v/d" "$v/b/design.md"
run "$v"
check_eq "the figure in a verdict's measurement line passes" 0 "$rc"

v=$tmp/costbenefit
build "$v"
append "$v/b/design.md" "**Cost-benefit:** 663 fix commits a month at baseline."
run "$v"
check_eq "the figure in a verdict's cost-benefit line passes" 0 "$rc"

v=$tmp/afterverdict
build "$v"
sed 's/^\*\*Measurement:\*\* pending./**Measurement:** pending.\n\nThe body then says 663 again./' "$v/b/design.md" >"$v/d" && mv "$v/d" "$v/b/design.md"
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
