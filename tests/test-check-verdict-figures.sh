#!/bin/bash
# Tests for scripts/check-verdict-figures.sh — every figure in a verdict
# decision's rationale names a field of its committed bake-off report and
# equals that field's value (universal-binary REQ-C1.5).
#
# The report the fixture verdicts cite is the harness's own output over the
# committed stub bake-off, so a figure absent from a stub report is a real one.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-check-verdict-figures.sh
# shellcheck disable=SC2016 # the fixture verdicts carry literal Markdown backticks
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
CV="$REPO_ROOT/scripts/check-verdict-figures.sh"
SB="$REPO_ROOT/scripts/substrate-bakeoff.sh"

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

[ -x "$CV" ] || {
  echo "FAIL: scripts/check-verdict-figures.sh missing or not executable" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-check-verdict-figures.XXXXXX") || exit 1
[ -n "$tmp" ] && [ -d "$tmp" ] || exit 1
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/root/docs/substrate" "$tmp/out"
"$SB" run --bakeoff "$REPO_ROOT/tests/fixtures/substrate-bakeoff/stub" --out-dir "$tmp/out" --run-id fig --platform test >/dev/null 2>&1 \
  || {
    echo "FAIL: the stub bake-off did not run" >&2
    exit 1
  }
REPORT=docs/substrate/bakeoff-stub-2026-11-01.tsv
cp "$tmp/out/report.tsv" "$tmp/root/$REPORT"
field() { awk -F '\t' -v c="$1" -v f="$2" 'NR == 1 { for (i = 1; i <= NF; i++) k[$i] = i; next } $k["candidate"] == c { print $k[f] }' "$tmp/root/$REPORT"; }
LAT=$(field stub-full latency_median_ms)
BYTES=$(field stub-full source_bytes)

# bundle <name> <decision body>: a four-file bundle whose design.md carries
# one ordinary decision and the given verdict body under D-2.
bundle() {
  b=$tmp/$1
  mkdir -p "$b"
  for f in requirements.md tasks.md test-spec.md; do printf '# %s\n' "$f" >"$b/$f"; done
  {
    printf '# Design\n\n### D-1: An ordinary decision\n\n**Decision:** pick 3 of the 4 options.\n\n**Chosen because:** 2 reasons.\n\n'
    printf '### D-2: The library tier verdict\n\n'
    cat
    printf '\n### D-3: After\n\n**Decision:** 9 things.\n'
  } >"$b/design.md"
}
check() { # <label> <bundle> <want rc> [<message part>]
  out=$("$CV" --bundle "$tmp/$2" --root "$tmp/root" 2>&1)
  rc=$?
  check_eq "$1: exit $3" "$3" "$rc"
  [ "$#" -ge 4 ] && check_has "$1: says why" "$out" "$4"
}

bundle good <<EOF
**Decision:** the stub wins.

**Report:** \`$REPORT\`

**Chosen because:** its median of $LAT ms (\`stub-full.latency_median_ms\`) over
the stated runs, with 2 (\`stub-full.tests_passed\`) fixtures green, settles it
by D-7 and REQ-C1.4 on 2026-11-01 for Task 6.

**Measurements:**

- source size $BYTES bytes (\`stub-full.source_bytes\`)
  - one spawn: 1 (\`stub-full.spawns_per_invocation\`)

**Cost-benefit:** 12 commits a month, a figure from the cost baseline.
EOF
check "every figure cited and equal" good 0

bundle norm <<EOF
**Report:** \`$REPORT\`

**Chosen because:** 2.00 (\`stub-full.tests_passed\`) passed.
EOF
check "figures compare as numbers" norm 0

bundle uncited <<EOF
**Report:** \`$REPORT\`

**Chosen because:** it passed 2 fixtures.
EOF
check "an uncited figure" uncited 1 "design.md:13: figure 2 in D-2's rationale names no report field"

bundle measure <<EOF
**Report:** \`$REPORT\`

**Measurement:** the median was 14 ms.
EOF
check "an uncited figure on a measurement line" measure 1 "figure 14 in D-2's rationale names no report field"

bundle wrong <<EOF
**Report:** \`$REPORT\`

**Chosen because:** 7 (\`stub-full.tests_passed\`) passed.
EOF
check "a figure differing from its field" wrong 1 "figure 7 cites stub-full.tests_passed, whose value is 2"

bundle absent <<EOF
**Report:** \`$REPORT\`

**Chosen because:** a cold start of 3 ms (\`stub-full.cold_start_median_ms\`).
EOF
check "a figure the stub report does not carry" absent 1 "stub-full.cold_start_median_ms carries no value"

bundle nofield <<EOF
**Report:** \`$REPORT\`

**Chosen because:** 2 (\`stub-full.speed_score\`).
EOF
check "a citation naming no field" nofield 1 "stub-full.speed_score names no field of"

bundle nocand <<EOF
**Report:** \`$REPORT\`

**Chosen because:** 2 (\`zig.tests_passed\`).
EOF
check "a citation naming no candidate" nocand 1 "zig.tests_passed names no candidate row of"

bundle noreport <<'EOF'
**Measurement:** 2 (`stub-full.tests_passed`).
EOF
check "figures with no report line" noreport 1 "D-2 cites figures but carries no **Report:** line"

bundle missing <<'EOF'
**Report:** `docs/substrate/none.tsv`

**Chosen because:** 2 (`stub-full.tests_passed`).
EOF
check "a report path that does not exist" missing 1 "report docs/substrate/none.tsv is missing"

bundle outside <<'EOF'
**Report:** `../escape.tsv`

**Chosen because:** 2 (`stub-full.tests_passed`).
EOF
check "a report path outside the root" outside 1 "is not a plain repository-relative path"

bundle costonly <<EOF
**Report:** \`$REPORT\`

**Cost-benefit:** 12 commits a month and 40 hours.
EOF
check "the cost-benefit line is out of scope" costonly 0

bundle listend <<EOF
**Report:** \`$REPORT\`

- **Measurement:** 2 (\`stub-full.tests_passed\`)
- **Decision note:** 99 others.
EOF
check "a sibling list item ends the measurement" listend 0

bundle refs <<EOF
**Report:** \`$REPORT\`

**Chosen because:** Task 6 and Tasks 7 and 8 under D-7, REQ-C1.4, \`obs:0087f433\` and 2026-11-01.
EOF
check "references are not figures" refs 0

out=$("$CV" 2>&1)
check_eq "the default run over the real bundle passes" 0 "$?"

out=$("$CV" --bundle "$tmp/nowhere" --root "$tmp/root" 2>&1)
check_eq "a missing bundle fails closed" 5 "$?"
"$CV" --bogus >/dev/null 2>&1
check_eq "an unknown flag is a usage error" 2 "$?"

if [ "$failures" -gt 0 ]; then
  echo "test-check-verdict-figures: $failures failure(s)" >&2
  exit 1
fi
echo "test-check-verdict-figures: all passed"
