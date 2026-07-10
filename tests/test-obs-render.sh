#!/bin/sh
# Unit test for scripts/obs-render.sh — the derived chronological view of the
# observation fragment store (observation-recording Task 3, REQ-C1.4, REQ-B1.3,
# REQ-D1.3; D-1, D-4, D-7). Order and empty-state semantics are normative in
# specs/observation-recording/{requirements,design}.md.
#
# Properties verified (numbered to match the body's check sections):
#   1. Total order (REQ-C1.4), byte-matched against a golden file: entries
#      render by date; within one date the frozen legacy lines (file order)
#      precede the fragments (by UID); a same-date legacy-line-plus-fragment
#      pair renders legacy-first; a consumed-but-unmoved fragment is excluded
#      from the live view; the frozen legacy file's unconsumed lines interleave
#      chronologically; a grammar-invalid file is skipped-and-warned (stderr,
#      excluded from stdout), never silently corrupting the view.
#   2. The --archived flag adds the archive/ fragments into the same order;
#      archive.md is never a render source.
#   3. Pure function (REQ-B1.3): two runs over one fragment set are
#      byte-identical, and the render writes only to stdout (the tree is
#      untouched).
#   4. Empty state: no live entries yields an empty view (no stdout) and exit 0;
#      absent observations root / entries dir / legacy file are all null-safe.
#   5. Content is data only (REQ-D1.3, D-7): a fragment and a legacy line whose
#      content carries shell metacharacters and control bytes render with the
#      non-printables stripped, the metacharacters preserved verbatim as text,
#      and no expansion side effect (no canary file created).
#   6. Exit-code / usage contract: an unknown flag and a flag without its value
#      are usage errors (exit 2); an empty or hyphen-leading --obs-dir refuses.
#
# Runs standalone under /bin/sh and the /bin/bash 3.2 floor.
set -eu

# Pin the C locale: range patterns and the sort order are collation-dependent
# under UTF-8 (house pattern, see sibling tests).
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes the destination into command substitutions,
# corrupting the derived script path.
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REN="$here/../scripts/obs-render.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$REN" ] || fail "scripts/obs-render.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# frag <dir> <name> <line> — write a one-line entry-form fragment.
frag() {
  printf -- '%s\n' "$3" >"$1/$2"
}

# --- 1. Total order, byte-matched against a golden file ------------------

o="$tmp/o1"
mkdir -p "$o/entries" "$o/archive"

# Two same-date fragments (ordered by UID: 22.. before 33..), an earlier
# fragment, and a stuck consume (Consumed-by present, must be excluded).
frag "$o/entries" 2026-06-15-alpha-11111111.md '- 2026-06-15 [planwright] entry A'
frag "$o/entries" 2026-07-01-bravo-22222222.md '- 2026-07-01 [planwright] entry B'
frag "$o/entries" 2026-07-01-charlie-33333333.md '- 2026-07-01 [planwright] entry C'
printf -- '- 2026-06-20 [planwright] stuck consume\nConsumed-by: specs/foo (2026-07-01)\n' \
  >"$o/entries/2026-06-20-delta-44444444.md"
# A grammar-invalid file name: skipped-and-warned, excluded from the view.
frag "$o/entries" not-a-fragment.md '- 2026-06-01 [planwright] should be skipped'
# An archive fragment (only surfaces under --archived).
printf -- '- 2026-05-10 [planwright] archived entry E\nConsumed-by: specs/bar (2026-06-01)\n' \
  >"$o/archive/2026-05-10-echo-55555555.md"
# Frozen legacy file: a same-date line (must precede the same-date fragments),
# a standalone unconsumed line, and a consumed line (excluded). The freeze
# header and blank lines are never entries.
printf '%s\n' '# Observations log' '' \
  '- 2026-07-01 [planwright] legacy same-date line' \
  '- 2026-06-10 [planwright] legacy standalone line' \
  '- 2026-06-05 [planwright] legacy consumed — consumed-by: specs/x (2026-07-01)' \
  >"$o/opportunities.md"

before=$(find "$o" -type f -exec cksum {} + | sort)

"$REN" --obs-dir "$o" >"$tmp/out1" 2>"$tmp/err1" \
  || fail "1: render exited non-zero"

cat >"$tmp/golden1" <<'EOF'
- 2026-06-10 [planwright] legacy standalone line
- 2026-06-15 [planwright] entry A
- 2026-07-01 [planwright] legacy same-date line
- 2026-07-01 [planwright] entry B
- 2026-07-01 [planwright] entry C
EOF
cmp -s "$tmp/out1" "$tmp/golden1" \
  || fail "1: render output does not byte-match the golden view:
$(diff "$tmp/golden1" "$tmp/out1" || true)"
# The invalid file is skip-and-warned on stderr, not in the view.
grep -F 'not-a-fragment.md' "$tmp/err1" >/dev/null \
  || fail "1: grammar-invalid file was not skip-and-warned on stderr"
grep -F 'should be skipped' "$tmp/out1" >/dev/null \
  && fail "1: a grammar-invalid file leaked into the rendered view"
# The stuck consume never appears in the live view.
grep -F 'stuck consume' "$tmp/out1" >/dev/null \
  && fail "1: a consumed-but-unmoved fragment leaked into the live view"
echo "ok 1: total order byte-matches the golden; invalid/stuck/consumed excluded"

# --- 2. --archived adds archive/ fragments in order ----------------------

"$REN" --obs-dir "$o" --archived >"$tmp/out2" 2>/dev/null \
  || fail "2: --archived render exited non-zero"
cat >"$tmp/golden2" <<'EOF'
- 2026-05-10 [planwright] archived entry E
- 2026-06-10 [planwright] legacy standalone line
- 2026-06-15 [planwright] entry A
- 2026-07-01 [planwright] legacy same-date line
- 2026-07-01 [planwright] entry B
- 2026-07-01 [planwright] entry C
EOF
cmp -s "$tmp/out2" "$tmp/golden2" \
  || fail "2: --archived output does not byte-match the golden view:
$(diff "$tmp/golden2" "$tmp/out2" || true)"
echo "ok 2: --archived interleaves archive/ fragments in the total order"

# --- 3. Pure function: two runs identical, tree untouched ----------------

"$REN" --obs-dir "$o" >"$tmp/out1b" 2>/dev/null || fail "3: second render failed"
cmp -s "$tmp/out1" "$tmp/out1b" \
  || fail "3: two renders over one fragment set are not byte-identical"
after=$(find "$o" -type f -exec cksum {} + | sort)
[ "$before" = "$after" ] || fail "3: render modified the fragment tree"
echo "ok 3: render is a pure function (byte-stable, stdout-only)"

# --- 4. Empty state and null-safety --------------------------------------

# An observations dir with empty entries/ and no legacy file: empty view.
oe="$tmp/o4empty"
mkdir -p "$oe/entries"
"$REN" --obs-dir "$oe" >"$tmp/oute" 2>/dev/null || fail "4: empty render exited non-zero"
[ ! -s "$tmp/oute" ] || fail "4: an empty fragment set must render nothing"
# A tree whose only live fragment is a stuck consume also renders empty.
os="$tmp/o4stuck"
mkdir -p "$os/entries"
printf -- '- 2026-06-01 [planwright] only a stuck consume\nConsumed-by: specs/x (2026-06-02)\n' \
  >"$os/entries/2026-06-01-only-abcdabcd.md"
"$REN" --obs-dir "$os" >"$tmp/outs" 2>/dev/null || fail "4: stuck-only render exited non-zero"
[ ! -s "$tmp/outs" ] || fail "4: a stuck-only tree must render an empty live view"
# A wholly absent observations root is null-safe (empty, exit 0).
"$REN" --obs-dir "$tmp/o4absent" >"$tmp/outa" 2>/dev/null \
  || fail "4: an absent observations root must be null-safe"
[ ! -s "$tmp/outa" ] || fail "4: an absent observations root must render nothing"
echo "ok 4: empty and null-safe states render an empty view, exit 0"

# --- 5. Content is data only (REQ-D1.3, D-7) -----------------------------

oh="$tmp/o5"
mkdir -p "$oh/entries"
# A fragment and a legacy line carrying $(...), backticks, an ESC sequence, and
# a BEL. The metacharacters must survive as literal text; the control bytes must
# be stripped; and nothing may be evaluated (no canary created).
# shellcheck disable=SC2016 # the unexpanded $(...)/backticks ARE the fixture
printf -- '- 2026-08-01 [planwright] frag $(touch %s/CANARY1) `touch %s/CANARY2` \033[31m tail\n' \
  "$tmp" "$tmp" >"$oh/entries/2026-08-01-hostile-deadbeef.md"
# shellcheck disable=SC2016
printf -- '# Observations log\n- 2026-08-02 [planwright] legacy $(touch %s/CANARY3) \007 end\n' \
  "$tmp" >"$oh/opportunities.md"
# A third fragment carrying a legitimate UTF-8 em-dash (0xE2 0x80 0x94): its
# 0x80/0x94 bytes fall in the C1 range but are valid content, so render must
# preserve them byte-for-byte (obs-record.sh accepts them at write time). This
# is the fidelity side of the security posture: strip C0/DEL, keep UTF-8.
emdash=$(printf 'before \342\200\224 after')
printf -- '- 2026-08-03 [planwright] utf8 %s\n' "$emdash" \
  >"$oh/entries/2026-08-03-utf8prose-cafef00d.md"
"$REN" --obs-dir "$oh" >"$tmp/outh" 2>/dev/null || fail "5: hostile-content render failed"
for canary in CANARY1 CANARY2 CANARY3; do
  find "$tmp" -name "$canary" | grep . >/dev/null \
    && fail "5: hostile content was evaluated: $canary created"
done
# No C0 control byte (except the line-structure newlines) or DEL survived to
# stdout. tr -cd keeps ONLY those bytes, so a non-empty result means one leaked;
# the UTF-8 em-dash (0x80/0x94) is outside this set and correctly ignored.
ctl=$(tr -cd '\000-\011\013-\037\177' <"$tmp/outh" | wc -c | tr -d ' ')
[ "$ctl" -eq 0 ] || fail "5: C0/DEL control bytes leaked into the rendered view"
# The legitimate UTF-8 em-dash is preserved verbatim (not stripped as C1).
grep -F "$emdash" "$tmp/outh" >/dev/null \
  || fail "5: a legitimate UTF-8 em-dash was corrupted in the rendered view"
# The shell metacharacters are preserved verbatim as text (data, not evaluated).
# shellcheck disable=SC2016 # asserting the literal $(...) text survived as data
grep -F '$(touch' "$tmp/outh" >/dev/null \
  || fail "5: literal \$(...) text was not preserved in the rendered view"
grep -F 'touch' "$tmp/outh" | grep -F '`' >/dev/null \
  || fail "5: literal backtick text was not preserved in the rendered view"
# All three live entries still render (data is surfaced, just sanitized).
[ "$(grep -c '^- ' "$tmp/outh")" -eq 3 ] \
  || fail "5: hostile-but-valid entries were not all rendered"
echo "ok 5: content is data only — C0/DEL stripped, UTF-8 kept, never evaluated"

# --- 6. Usage / exit-code contract ---------------------------------------

rc=0
"$REN" --bogus >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "6: an unknown flag must be a usage error (exit 2), got $rc"
rc=0
"$REN" --obs-dir >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "6: --obs-dir without a value must be a usage error, got $rc"
rc=0
"$REN" --obs-dir '' >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "6: an empty --obs-dir must refuse (exit 2), got $rc"
rc=0
"$REN" --obs-dir - >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "6: a hyphen-leading --obs-dir must refuse (exit 2), got $rc"
"$REN" --help >/dev/null 2>&1 || fail "6: --help must exit 0"
echo "ok 6: usage and exit-code contract holds"

echo "PASS: test-obs-render.sh"
