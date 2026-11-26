#!/bin/bash
# Tests for the purged-identifier guard's seeds and wiring (REQ-B1.2,
# REQ-H1.3): every vacuous seed file fails closed; the seeder,
# scripts/seed-purged-identifiers.sh, reads stdin only and never prints what it
# read; the COMMITTED seed is hash-only, meets its declared floor and is not
# merely the suites' test tokens; and the check sits in the `check` aggregate,
# ci.yml runs the range scan and the hook calls the scanner. The tree scan and
# the message screens have sibling suites sharing
# tests/lib/purged-identifiers-harness.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck source=tests/lib/purged-identifiers-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/purged-identifiers-harness.sh"

# ---------------------------------------------------------------------------
# Seed-file fail-closed posture (REQ-H1.3, REQ-B1.2). Each of these is a
# vacuous-input case that must exit non-zero rather than pass.
# ---------------------------------------------------------------------------

# bad_seed <label> <slug> <seed-file-content>
bad_seed() {
  r="$(new_repo "seed-$2")"
  printf 'clean tracked content\n' >"$r/doc.md"
  git -C "$r" add doc.md
  mkdir -p "$r/config"
  printf '%s' "$3" >"$r/config/purged-identifiers.seed"
  out="$(cd "$r" && "$SCAN" 2>&1)"
  assert_exit "fails closed: $1" 2 $?
  assert_contains "fails closed loudly: $1" "fails closed" "$out"
}

r="$(new_repo seed-missing)"
printf 'clean tracked content\n' >"$r/doc.md"
git -C "$r" add doc.md
out="$(cd "$r" && "$SCAN" 2>&1)"
assert_exit "fails closed: the seed file is missing" 2 $?
assert_contains "the missing-seed failure names the remedy" "seed-purged-identifiers.sh" "$out"

H1='1111111111111111111111111111111111111111111111111111111111111111'
H2='2222222222222222222222222222222222222222222222222222222222222222'

bad_seed "an empty seed file" empty ''
bad_seed "directives but zero hashes" zerohash 'min-seeds: 1
max-words: 2
'
bad_seed "a zero min-seeds floor" zerofloor "min-seeds: 0
max-words: 2
$H1
"
bad_seed "a hash count below the declared floor" belowfloor "min-seeds: 3
max-words: 2
$H1
$H2
"
bad_seed "a plaintext-shaped line" plaintext "min-seeds: 1
max-words: 2
$TOKEN
"
bad_seed "an uppercase hex hash" uppercase "min-seeds: 1
max-words: 2
1111111111111111111111111111111111111111111111111111111111111AAA
"
bad_seed "a truncated hash" short "min-seeds: 1
max-words: 2
1111
"
bad_seed "no min-seeds directive" nofloor "max-words: 2
$H1
"
bad_seed "no max-words directive" nowords "min-seeds: 1
$H1
"
bad_seed "a max-words above the window" wideword "min-seeds: 1
max-words: 9
$H1
"
bad_seed "a duplicated directive" dupe "min-seeds: 1
min-seeds: 2
max-words: 2
$H1
"
bad_seed "no min-max-words directive" nominmax "min-seeds: 1
max-words: 2
$H1
"
bad_seed "a duplicated min-max-words directive" dupeminmax "min-seeds: 1
max-words: 2
min-max-words: 2
min-max-words: 1
$H1
"
bad_seed "a min-max-words above the window" wideminmax "min-seeds: 1
max-words: 2
min-max-words: 9
$H1
"
# The tamper this floor exists for: narrow the window and leave everything
# else untouched, and every seed wider than the new window silently stops
# matching. The scanner has to refuse the file, not scan with it.
bad_seed "a max-words hand-lowered below its floor" narrowed "min-seeds: 1
max-words: 1
min-max-words: 3
$H1
"

# ---------------------------------------------------------------------------
# The provisioning path (REQ-B1.2): stdin only, never argv, never echoed.
# ---------------------------------------------------------------------------

r="$(new_repo seeder)"
mkdir -p "$r/config"
out="$(printf '%s\n%s\n' "$TOKEN" "$TOKEN2" | (cd "$r" && "$SEEDER" 2>&1))"
assert_exit "the seeder writes from stdin" 0 $?
assert_absent "the seeder never echoes the plaintext" "$TOKEN" "$out"
assert_absent "the seeder never echoes the normalized form" "$NORM" "$out"
assert_contains "the seeder reports the count it wrote" "2 seed hash(es)" "$out"
seedfile="$r/config/purged-identifiers.seed"
written="$(cat "$seedfile")"
assert_absent "the written seed file holds no plaintext" "$TOKEN" "$written"
assert_absent "the written seed file holds no normalized form" "$NORM" "$written"
assert_contains "the written seed file declares its floor" "min-seeds: 2" "$written"
assert_contains "the written seed file declares its window" "max-words: 4" "$written"
assert_contains "the written seed file declares the floor under that window" "min-max-words: 4" "$written"
stray="$(grep -cv -e '^#' -e '^$' -e '^min-seeds: [0-9]\{1,4\}$' -e '^max-words: [0-9]\{1,2\}$' -e '^min-max-words: [0-9]\{1,2\}$' -e '^[0-9a-f]\{64\}$' "$seedfile")"
assert_exit "every written seed line is a comment, a directive, or a bare hash" 0 "$stray"

out="$(printf '%s\n' "$TOKEN" | (cd "$r" && "$SEEDER" "$TOKEN" 2>&1))"
assert_exit "the seeder refuses an identifier passed as an argument" 2 $?
assert_contains "the argv refusal explains the stdin-only rule" "never from arguments" "$out"

out="$(printf '' | (cd "$r" && "$SEEDER" --seed-file "$TMP/nope.seed" 2>&1))"
assert_exit "the seeder refuses to write an empty seed file" 2 $?
assert_absent "the empty-input refusal writes nothing" "nope.seed" "$(ls "$TMP")"

out="$(printf 'ab\n' | (cd "$r" && "$SEEDER" --seed-file "$TMP/short.seed" 2>&1))"
assert_exit "the seeder refuses a too-short identifier" 2 $?
assert_contains "the too-short refusal reports the POSITION, not the value" "stdin line 1" "$out"

out="$(printf '///\n' | (cd "$r" && "$SEEDER" --seed-file "$TMP/nonword.seed" 2>&1))"
assert_exit "the seeder refuses a line with nothing to normalize" 2 $?

# The write goes through an exclusive temp file and a rename, so neither the
# destination nor anything it points at is written through, and no predictable
# temp name is left for a symlink to be planted at.
r="$(new_repo seeder-symlink)"
mkdir -p "$r/config"
printf 'DO NOT CLOBBER\n' >"$TMP/seed-victim.txt"
ln -s "$TMP/seed-victim.txt" "$r/config/purged-identifiers.seed"
printf '%s\n' "$TOKEN" | (cd "$r" && "$SEEDER" >/dev/null 2>&1)
assert_exit "the seeder writes over a symlinked destination" 0 $?
assert_contains "a symlinked destination is not written through" "DO NOT CLOBBER" \
  "$(cat "$TMP/seed-victim.txt")"
if [ -L "$r/config/purged-identifiers.seed" ]; then
  echo "FAIL: the destination is still a symlink after seeding" >&2
  failures=$((failures + 1))
else
  echo "ok: the destination is replaced by a regular file"
fi
stray_tmp="$(find "$r/config" -name '*tmp*' -o -name '.purged-seed*' | wc -l)"
assert_exit "the seeder leaves no temp file behind" 0 "$stray_tmp"

# --add merges rather than replacing, and deduplicates.
r="$(new_repo seeder-add)"
mkdir -p "$r/config"
printf '%s\n' "$TOKEN" | (cd "$r" && "$SEEDER" >/dev/null 2>&1)
out="$(printf '%s\n%s\n' "$TOKEN" "$TOKEN2" | (cd "$r" && "$SEEDER" --add 2>&1))"
assert_exit "--add merges into the existing seeds" 0 $?
assert_contains "--add deduplicates the overlap" "2 seed hash(es)" "$out"
out="$(printf '%s\n' "$TOKEN" | (cd "$r" && "$SEEDER" --add --seed-file "$TMP/absent.seed" 2>&1))"
assert_exit "--add against a missing seed file is an error" 2 $?

# --add reads the existing file with EXACTLY the grammar the scanner enforces.
# A looser reader is how a guard goes quietly weak: carrying hashes forward
# under a narrower window than they were seeded with leaves them permanently
# unmatchable while the check still reports green.

# add_onto <slug> <existing-seed-body> — run --add over a planted seed file.
add_onto() {
  ar="$(new_repo "add-$1")"
  mkdir -p "$ar/config"
  printf '%s' "$2" >"$ar/config/purged-identifiers.seed"
  printf 'zzqsolo\n' | (cd "$ar" && "$SEEDER" --add 2>&1)
}

H3='3333333333333333333333333333333333333333333333333333333333333333'
H4='4444444444444444444444444444444444444444444444444444444444444444'

out="$(add_onto nowords "min-seeds: 1
$H3
")"
assert_exit "--add refuses an existing file with no max-words directive" 2 $?
assert_contains "the no-max-words refusal says what is wrong" "max-words" "$out"

out="$(add_onto widewords "min-seeds: 1
max-words: 12
$H3
")"
assert_exit "--add refuses an out-of-range max-words rather than carrying it" 2 $?

out="$(add_onto dupewords "min-seeds: 1
max-words: 2
max-words: 1
$H3
")"
assert_exit "--add refuses a duplicated max-words directive" 2 $?

out="$(add_onto dupefloor "min-seeds: 1
min-seeds: 2
max-words: 2
$H3
")"
assert_exit "--add refuses a duplicated min-seeds directive" 2 $?

# min-seeds carries semantics, not just a shape. Accepting a file the scanner
# fails closed on and rewriting it into one that passes is the guard being
# quietly repaired into a weaker working state: a floor of 5 against 2 hashes
# means three seeds went missing, and lowering the floor to match buries that.
out="$(add_onto zerofloor "min-seeds: 0
max-words: 2
$H3
")"
assert_exit "--add refuses a zero min-seeds floor" 2 $?

out="$(add_onto belowfloor "min-seeds: 5
max-words: 2
min-max-words: 2
$H3
$H4
")"
assert_exit "--add refuses a hash count below the declared floor" 2 $?
assert_contains "the below-floor refusal names both numbers" "below" "$out"

# min-max-words is the floor under the candidate WINDOW, the counterpart to
# min-seeds. Without it, narrowing max-words leaves every wider seed
# unmatchable with the hash count and the seed floor both untouched, and no
# check fires. Required rather than optional: a floor that applies only when
# its own line is present is removed by deleting that line.
out="$(add_onto nominmax "min-seeds: 1
max-words: 2
$H3
")"
assert_exit "--add refuses an existing file with no min-max-words directive" 2 $?

out="$(add_onto narrowed "min-seeds: 1
max-words: 1
min-max-words: 3
$H3
")"
assert_exit "--add refuses a max-words already below its own floor" 2 $?

out="$(add_onto dupeminmax "min-seeds: 1
max-words: 2
min-max-words: 2
min-max-words: 1
$H3
")"
assert_exit "--add refuses a duplicated min-max-words directive" 2 $?

# The window must never narrow below what the carried hashes were seeded with.
r2="$(new_repo add-window)"
mkdir -p "$r2/config"
printf 'zzq alpha beta gamma\n' | (cd "$r2" && "$SEEDER" >/dev/null 2>&1)
printf 'zzqsolo\n' | (cd "$r2" && "$SEEDER" --add >/dev/null 2>&1)
assert_contains "--add never narrows the window below the carried seeds" "max-words: 4" \
  "$(cat "$r2/config/purged-identifiers.seed")"

# The seeder and the scanner must agree on normalization: a seed provisioned
# in one spelling is caught in every other. This is the contract that keeps
# the two sides from drifting apart.
r="$(new_repo roundtrip)"
mkdir -p "$r/config"
printf 'ZZQ Planted SeedToken\n' | (cd "$r" && "$SEEDER" >/dev/null 2>&1)
printf 'prose naming %s here\n' "$TOKEN" >"$r/doc.md"
git -C "$r" add doc.md config
(cd "$r" && "$SCAN" >/dev/null 2>&1)
assert_exit "a seed provisioned space-separated is caught hyphenated" 1 $?

# ---------------------------------------------------------------------------
# The committed seed file and the wiring (REQ-B1.2, and decidable wiring).
# ---------------------------------------------------------------------------

if [ ! -f "$REAL_SEED" ]; then
  echo "FAIL: the committed seed file $REAL_SEED is missing — the guard would fail closed on every run" >&2
  failures=$((failures + 1))
else
  real_min="$(sed -n 's/^min-seeds: \([0-9]\{1,4\}\)$/\1/p' "$REAL_SEED")"
  real_words="$(sed -n 's/^max-words: \([0-9]\{1,2\}\)$/\1/p' "$REAL_SEED")"
  real_count="$(grep -c '^[0-9a-f]\{64\}$' "$REAL_SEED")"
  stray="$(grep -cv -e '^#' -e '^$' -e '^min-seeds: [0-9]\{1,4\}$' -e '^max-words: [0-9]\{1,2\}$' -e '^min-max-words: [0-9]\{1,2\}$' -e '^[0-9a-f]\{64\}$' "$REAL_SEED")"

  if [ "$stray" -ne 0 ]; then
    echo "FAIL: the committed seed file has $stray line(s) that are neither a comment, a directive, nor a bare hash" >&2
    failures=$((failures + 1))
  else
    echo "ok: the committed seed file is hash-only (no line of plaintext shape)"
  fi
  if [ -z "$real_min" ] || [ "$real_min" -lt 1 ]; then
    echo "FAIL: the committed seed file declares no usable min-seeds floor" >&2
    failures=$((failures + 1))
  elif [ "$real_count" -lt "$real_min" ]; then
    echo "FAIL: the committed seed file holds $real_count hash(es), below its declared floor of $real_min" >&2
    failures=$((failures + 1))
  else
    echo "ok: the committed seed file meets its declared minimum-seed floor ($real_count >= $real_min)"
  fi
  if [ -z "$real_words" ] || [ "$real_words" -lt 1 ]; then
    echo "FAIL: the committed seed file declares no usable max-words window" >&2
    failures=$((failures + 1))
  else
    echo "ok: the committed seed file declares a candidate window"
  fi

  # The vacuously-green failure mode: a seed list made of this suite's own
  # test tokens would pass every scenario in these suites and guard nothing real.
  planted="$(printf '%s\n%s\n' "$TOKEN" "$TOKEN2" \
    | perl -MDigest::SHA=sha256_hex -ne 'chomp; my @w = map { lc } (/([A-Za-z0-9]+)/g); print sha256_hex(join("", @w)), "\n"')"
  leaked=0
  for h in $planted; do
    if grep -qx "$h" "$REAL_SEED"; then leaked=1; fi
  done
  if [ "$leaked" -ne 0 ]; then
    echo "FAIL: the committed seed file contains this suite's test tokens — a test-only seed list guards nothing" >&2
    failures=$((failures + 1))
  else
    echo "ok: the committed seed file holds no test-only token"
  fi
fi

if grep -q '"check:purged-identifiers"' "$REPO_ROOT/mise.toml" \
  && grep -q '^  "check:purged-identifiers",$' "$REPO_ROOT/mise.toml"; then
  echo "ok: check:purged-identifiers is defined and a member of the check aggregate"
else
  echo "FAIL: check:purged-identifiers is not wired into the check aggregate in mise.toml" >&2
  failures=$((failures + 1))
fi

if grep -q 'check-purged-identifiers.sh --commit-range' "$REPO_ROOT/.github/workflows/ci.yml"; then
  echo "ok: ci.yml carries the commit-range scan"
else
  echo "FAIL: ci.yml does not run the commit-range scan — unwired clones and fork PRs stay uncovered" >&2
  failures=$((failures + 1))
fi

if grep -q 'check-purged-identifiers.sh' "$REPO_ROOT/githooks/commit-msg"; then
  echo "ok: githooks/commit-msg calls the scanner"
else
  echo "FAIL: githooks/commit-msg does not screen the message" >&2
  failures=$((failures + 1))
fi

# The repo's own tree against its own guard. Two states are legitimate right
# now, and the suite refuses to call either one a silent pass:
#
#   armed   - the committed seed carries min-max-words and the tree is clean;
#   pending - the seed predates that directive, so the guard fails closed until
#             an operator re-seeds. Provisioning needs the plaintext, which is
#             deliberately unavailable to anything but a human at a terminal,
#             so this suite cannot arm it and must not paper over it either.
#
# Anything else is a real failure. The pending arm disappears on the first
# re-seed, and this whole branch collapses back to a plain pass.
out="$(cd "$REPO_ROOT" && "$SCAN" 2>&1)"
rc=$?
if [ "$rc" -eq 0 ]; then
  echo "ok: the repo's own tracked tree passes its own guard (seed armed)"
elif [ "$rc" -eq 2 ] && [ -z "${out##*min-max-words*}" ]; then
  echo "ok: the committed seed predates min-max-words, so the guard fails closed pending an operator re-seed"
  echo "    remedy: scripts/seed-purged-identifiers.sh (reads the plaintext from stdin)"
else
  echo "FAIL: the repo's own tracked tree neither passes nor fails closed for the known pending reason (exit $rc)" >&2
  printf '%s\n' "$out" >&2
  failures=$((failures + 1))
fi

finish check-purged-identifiers-seeds
