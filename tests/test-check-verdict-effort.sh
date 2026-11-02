#!/bin/bash
# Tests for scripts/check-verdict-effort.sh — a verdict's migration effort
# cites the porting rate its bake-off logged, or carries the explicit
# absence token of a verdict settled by screen (universal-binary REQ-G1.3).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-check-verdict-effort.sh
# shellcheck disable=SC2016 # the fixture verdicts carry literal Markdown backticks
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$here/.." && pwd)
CE="$REPO_ROOT/scripts/check-verdict-effort.sh"
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

[ -x "$CE" ] || {
  echo "FAIL: scripts/check-verdict-effort.sh missing or not executable" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-check-verdict-effort.XXXXXX") || exit 1
[ -n "$tmp" ] && [ -d "$tmp" ] || exit 1
trap 'rm -rf "$tmp"' EXIT

# The cited reports are the harness's own output over the committed stub
# bake-off, recast with synthetic candidate names and porting rates; every
# one must still pass substrate-bakeoff.sh validate, as the guard requires.
mkdir -p "$tmp/root/docs/substrate" "$tmp/out"
"$SB" run --bakeoff "$REPO_ROOT/tests/fixtures/substrate-bakeoff/stub" --out-dir "$tmp/out" --run-id eff --platform test >/dev/null 2>&1 \
  || {
    echo "FAIL: the stub bake-off did not run" >&2
    exit 1
  }
# recast <full id> <rate> <comparison id or -> <report>: the stub report
# with its full candidate renamed and given the rate, and its comparison
# point renamed or (with -) dropped.
recast() {
  awk -F '\t' -v OFS='\t' -v full="$1" -v rate="$2" -v cmp="$3" '
NR == 1 { for (i = 1; i <= NF; i++) k[$i] = i; print; next }
$k["class"] == "full" { $k["candidate"] = full; $k["porting_rate_min_per_kib"] = rate; print; next }
cmp != "-" { $k["candidate"] = cmp; print }' "$tmp/out/report.tsv" >"$tmp/root/$4"
  "$SB" validate "$tmp/root/$4" >/dev/null 2>&1 || {
    echo "FAIL: the recast report $4 does not validate" >&2
    exit 1
  }
}
REPORT=docs/substrate/bakeoff-a-2026-11-01.tsv
INHERITED=docs/substrate/bakeoff-b-2026-11-02.tsv
recast go 0.800 zig "$REPORT"
recast rust 1.250 - "$INHERITED"
FULLZIG=docs/substrate/bakeoff-d-2026-11-03.tsv
recast zig 1.500 - "$FULLZIG"

bundle() {
  b=$tmp/$1
  mkdir -p "$b"
  for f in requirements.md tasks.md test-spec.md; do printf '# %s\n' "$f" >"$b/$f"; done
  {
    printf '# Design\n\n### D-1: An ordinary decision\n\n**Decision:** no effort line needed.\n\n'
    printf '### D-2: The library tier verdict\n\n'
    cat
    printf '\n### D-3: After\n\n**Decision:** nothing.\n'
  } >"$b/design.md"
}
check() { # <label> <bundle> <want rc> [<message part>]
  out=$("$CE" --bundle "$tmp/$2" --root "$tmp/root" 2>&1)
  rc=$?
  check_eq "$1: exit $3" "$3" "$rc"
  [ "$#" -ge 4 ] && check_has "$1: says why" "$out" "$4"
}

bundle cited <<EOF
**Report:** \`$REPORT\`

**Cost-benefit:**

- **Migration effort:** the tier's shell source at 0.8 min/KiB
  (\`go.porting_rate_min_per_kib\`), about 40 hours.
EOF
check "an effort citing the logged rate" cited 0

bundle inherited <<EOF
**Report:** \`$REPORT\` \`$INHERITED\`

**Cost-benefit:** - **Migration effort:** 1.25 min/KiB (\`rust.porting_rate_min_per_kib\`).
EOF
check "an effort citing an inherited bake-off's rate" inherited 0

bundle laterfull <<EOF
**Report:** \`$REPORT\` \`$FULLZIG\`

**Cost-benefit:** - **Migration effort:** 1.5 min/KiB (\`zig.porting_rate_min_per_kib\`).
EOF
check "a rate logged by a later report where an earlier one holds the candidate as a comparison point" laterfull 0

bundle screen <<'EOF'
**Cost-benefit:**

- **Migration effort:** none to extrapolate, `porting-rate: absent`, since the
  screen settled the tier.
EOF
check "the explicit absence token" screen 0

bundle neither <<EOF
**Report:** \`$REPORT\`

**Cost-benefit:**

- **Migration effort:** about 40 hours, judged from experience.
EOF
check "an effort with neither" neither 1 "D-2's migration effort neither cites a logged porting rate"

bundle none <<EOF
**Report:** \`$REPORT\`

**Cost-benefit:** 12 commits a month.
EOF
check "a verdict with no effort statement" none 1 "D-2 is a verdict without a **Migration effort:** statement"

bundle otherfield <<EOF
**Report:** \`$REPORT\`

**Cost-benefit:** - **Migration effort:** 0.8 (\`go.latency_median_ms\`).
EOF
check "a citation of another field" otherfield 1 "neither cites a logged porting rate"

bundle mismatch <<EOF
**Report:** \`$REPORT\`

**Cost-benefit:** - **Migration effort:** 0.9 min/KiB (\`go.porting_rate_min_per_kib\`).
EOF
check "a rate differing from the logged one" mismatch 1 "0.9 cites go.porting_rate_min_per_kib, whose logged value is 0.800"

bundle comparison <<EOF
**Report:** \`$REPORT\`

**Cost-benefit:** - **Migration effort:** 0 (\`zig.porting_rate_min_per_kib\`).
EOF
check "a comparison point has no porting rate" comparison 1 "zig.porting_rate_min_per_kib carries no logged rate"

bundle nocand <<EOF
**Report:** \`$REPORT\`

**Cost-benefit:** - **Migration effort:** 0.8 (\`rust.porting_rate_min_per_kib\`).
EOF
check "a rate from a report the verdict does not name" nocand 1 "rust.porting_rate_min_per_kib names no full candidate"

bundle unreported <<'EOF'
**Cost-benefit:** - **Migration effort:** 0.8 (`go.porting_rate_min_per_kib`).
EOF
check "a cited rate with no report line" unreported 1 "carries no **Report:** line"

awk -F '\t' -v OFS='\t' 'NR == 1 { for (i = 1; i <= NF; i++) k[$i] = i } $k["class"] == "comparison" { $k["porting_rate_min_per_kib"] = "0.500" } { print }' \
  "$tmp/root/$REPORT" >"$tmp/root/docs/substrate/bakeoff-c.tsv"
bundle cmprate <<'EOF'
**Report:** `docs/substrate/bakeoff-c.tsv`

**Cost-benefit:** - **Migration effort:** 0.5 (`zig.porting_rate_min_per_kib`).
EOF
check "a comparison point carrying a rate is an invalid report" cmprate 1 "a comparison point carries the primitive field porting_rate_min_per_kib"

printf 'schema\tcandidate\tclass\tporting_rate_min_per_kib\nsubstrate-bakeoff\tgo\tfull\t0.800\n' >"$tmp/root/docs/substrate/forged.tsv"
bundle forged <<'EOF'
**Report:** `docs/substrate/forged.tsv`

**Cost-benefit:** - **Migration effort:** 0.8 (`go.porting_rate_min_per_kib`).
EOF
check "a hand-made report is refused" forged 1 "report docs/substrate/forged.tsv is not a valid bake-off report"

bundle fencedreport <<'EOF'
**Decision:** an ordinary decision that shows a verdict as an example:

```markdown
**Report:** `docs/substrate/x.tsv`
```
EOF
check "a fenced example report line does not make a verdict" fencedreport 0

out=$("$CE" 2>&1)
check_eq "the shipped bundle passes vacuously" 0 "$?"

out=$("$CE" --bundle "$tmp/nowhere" --root "$tmp/root" 2>&1)
check_eq "a missing bundle fails closed" 5 "$?"
"$CE" --bogus >/dev/null 2>&1
check_eq "an unknown flag is a usage error" 2 "$?"

if [ "$failures" -gt 0 ]; then
  echo "test-check-verdict-effort: $failures failure(s)" >&2
  exit 1
fi
echo "test-check-verdict-effort: all passed"
