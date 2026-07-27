#!/bin/sh
# Unit test for scripts/obs-consume.sh — the LEGACY frozen-log arm
# (observation-recording Task 4, REQ-C1.2, REQ-D1.1, REQ-D1.3; D-3, D-7).
# Consumption semantics are normative in
# specs/observation-recording/{requirements,design}.md.
#
# Split out of tests/test-obs-consume.sh (guard-coverage Task 6, REQ-E1.2,
# D-9): that file was a wall-clock straggler, so its three cohesive arms now
# run as three files. The fragment arm lives in tests/test-obs-consume.sh and
# the git/cross-guard integration cases in tests/test-obs-consume-git.sh; the
# assertions here are unchanged from the pre-split file.
#
# Properties verified (numbered to match the body's check sections, which keep
# the original file's numbering so the spec's section references still land):
#  12. Legacy in-place annotation (REQ-C1.2): consuming a frozen-log line appends
#      `— consumed-by: specs/<spec> (<date>)` to exactly that line, reorders
#      nothing, and moves no file; a byte-identical duplicate line is
#      independently consumable (first consume annotates the first match, a
#      second consume the next); a same-spec re-run on a later date is a no-op.
#  12b. Legacy `--line` content is data (REQ-D1.3): shell and regex
#      metacharacters are matched as a fixed string, and no neighbour line is
#      altered.
#  12c. Not-found and empty-line refusals: an absent frozen file and an absent
#      line exit 3; an empty `--line` refuses (exit 1) without annotating the
#      blank header line.
#  12d. A CRLF-saved frozen log stays consumable; the annotation lands
#      LF-terminated and pass-through neighbours keep their bytes.
#  12e. A line already consumed by a *different* spec is a not-found refusal
#      (exit 3) — the accepted fragment/legacy asymmetry, pinned against drift.
#  12f. An awk runtime error in either legacy pass is a filesystem refusal
#      (exit 1), never misread as not-found (exit 3).
#  12g. A symlinked frozen `opportunities.md` refuses (exit 1), dangling or
#      live, and the target is never annotated through the link.
#
# Exit codes asserted throughout: 1 refusal (grammar/containment/content/symlink/
# fs), 2 usage, 3 not found (no matching legacy line) — the header contract of
# scripts/obs-consume.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor) and /bin/sh.
set -eu

# Pin the C locale: range patterns are collation-dependent under UTF-8.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes the destination into command substitutions,
# corrupting derived paths (house pattern, see sibling tests).
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
CONSUME="$here/../scripts/obs-consume.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$CONSUME" ] || fail "scripts/obs-consume.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# new_obs <dir> — a fresh observations dir with empty entries/ + archive/.
new_obs() {
  mkdir -p "$1/entries" "$1/archive"
  printf '%s' "$1"
}

# make_awk_stub <dir> <code1> [<code2> ...] — an `awk` on PATH that exits with
# the given codes in call order (the last code repeats for further calls), used
# to fault-inject an awk runtime error (exit >1) into the legacy arm's two awk
# passes. It ignores the program and file arguments and produces no output — the
# script must not publish on an error exit, so the empty temp is discarded.
make_awk_stub() {
  _d=$1
  shift
  mkdir -p "$_d"
  : >"$_d/codes"
  for _c in "$@"; do printf '%s\n' "$_c" >>"$_d/codes"; done
  printf '0\n' >"$_d/an"
  cat >"$_d/awk" <<EOF
#!/bin/sh
n=\$(cat "$_d/an" 2>/dev/null || echo 0)
n=\$((n + 1))
echo "\$n" >"$_d/an"
code=\$(sed -n "\${n}p" "$_d/codes")
[ -n "\$code" ] || code=\$(tail -n 1 "$_d/codes")
exit "\$code"
EOF
  chmod +x "$_d/awk"
}

# frag_count <dir> — number of *.md fragments under a directory (null-safe).
frag_count() {
  _c=0
  for _f in "$1"/*.md; do
    [ -e "$_f" ] && _c=$((_c + 1))
  done
  echo "$_c"
}

# --- 12. Legacy in-place annotation --------------------------------------

o=$(new_obs "$tmp/o12")
LINE1='- 2026-06-10 [planwright] a unique legacy observation'
DUP='- 2026-06-11 [planwright] a duplicated legacy line'
cat >"$o/opportunities.md" <<EOF
# Observations — frozen legacy log

$LINE1
$DUP
- 2026-06-12 [planwright] another line
$DUP
EOF
before_count=$(wc -l <"$o/opportunities.md")
"$CONSUME" --obs-dir "$o" --legacy --line "$LINE1" --spec my-spec --today 2026-07-10 \
  || fail "12: legacy consume exited non-zero"
grep -Fxq -e "$LINE1 — consumed-by: specs/my-spec (2026-07-10)" "$o/opportunities.md" \
  || fail "12: legacy line not annotated in place"
[ "$(wc -l <"$o/opportunities.md")" -eq "$before_count" ] \
  || fail "12: legacy annotation changed the line count (reordered/added lines)"
[ "$(frag_count "$o/entries")" -eq 0 ] && [ "$(frag_count "$o/archive")" -eq 0 ] \
  || fail "12: legacy consume created a fragment"
# Duplicate-identical line: first consume annotates one, second the other.
"$CONSUME" --obs-dir "$o" --legacy --line "$DUP" --spec my-spec --today 2026-07-10 \
  || fail "12: first duplicate-line consume exited non-zero"
"$CONSUME" --obs-dir "$o" --legacy --line "$DUP" --spec my-spec --today 2026-07-10 \
  || fail "12: second duplicate-line consume exited non-zero"
n=$(grep -Fc -e "$DUP — consumed-by: specs/my-spec (2026-07-10)" "$o/opportunities.md")
[ "$n" -eq 2 ] || fail "12: expected 2 annotated duplicates, got $n"
# A third consume with both already annotated is a clean no-op.
"$CONSUME" --obs-dir "$o" --legacy --line "$DUP" --spec my-spec --today 2026-07-10 \
  || fail "12: exhausted duplicate-line consume must be a clean no-op"
n=$(grep -Fc -e "$DUP — consumed-by: specs/my-spec (2026-07-10)" "$o/opportunities.md")
[ "$n" -eq 2 ] || fail "12: no-op re-run annotated a third time (got $n)"
# A same-spec re-run on a LATER date is a clean no-op too (date-insensitive,
# mirroring the fragment arm) — not a spurious not-found.
"$CONSUME" --obs-dir "$o" --legacy --line "$LINE1" --spec my-spec --today 2026-08-01 \
  || fail "12: same-spec cross-date re-run must be a clean no-op (exit 0)"
[ "$(grep -Fc -e "$LINE1 — consumed-by:" "$o/opportunities.md")" -eq 1 ] \
  || fail "12: cross-date re-run added a second annotation"
echo "ok 12: legacy lines annotate in place, duplicates independently consumable"

# --- 12b. Legacy line content is data (metacharacters matched literally) ---

o=$(new_obs "$tmp/o12b")
# shellcheck disable=SC2016 # the metacharacters are literal legacy-line data, must NOT expand
META='- 2026-06-13 [planwright] awk & regex .* [x] %s `id` $(touch z) end'
cat >"$o/opportunities.md" <<EOF
# frozen

$META
- 2026-06-14 [planwright] untouched neighbor
EOF
"$CONSUME" --obs-dir "$o" --legacy --line "$META" --spec my-spec --today 2026-07-10 \
  || fail "12b: legacy consume of a metacharacter line exited non-zero"
grep -Fxq -e "$META — consumed-by: specs/my-spec (2026-07-10)" "$o/opportunities.md" \
  || fail "12b: metacharacter line not matched/annotated literally"
grep -Fxq -e '- 2026-06-14 [planwright] untouched neighbor' "$o/opportunities.md" \
  || fail "12b: a neighbor line was altered (content used as a pattern?)"
echo "ok 12b: legacy --line content is matched as fixed-string data, not a pattern"

# --- 12c. Legacy not-found refusals (exit 3) ------------------------------

o=$(new_obs "$tmp/o12c")
rc=0
"$CONSUME" --obs-dir "$o" --legacy --line 'anything' --spec my-spec --today 2026-07-10 \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 3 ] || fail "12c: absent frozen file expected exit 3, got $rc"
printf '%s\n' '# frozen' '' '- 2026-06-10 [planwright] present' >"$o/opportunities.md"
rc=0
"$CONSUME" --obs-dir "$o" --legacy --line '- 2026-06-10 [planwright] ABSENT' \
  --spec my-spec --today 2026-07-10 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 3 ] || fail "12c: an absent legacy line expected exit 3, got $rc"
# An empty --line is refused, never allowed to annotate the blank header line.
rc=0
"$CONSUME" --obs-dir "$o" --legacy --line '' --spec my-spec --today 2026-07-10 \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "12c: an empty --line expected refusal exit 1, got $rc"
# Nothing was annotated (the blank header line in particular is untouched).
if grep -q 'consumed-by' "$o/opportunities.md"; then
  fail "12c: an empty --line annotated a line"
fi
echo "ok 12c: legacy not-found / empty-line inputs refuse cleanly"

# --- 12d. CRLF frozen log: a present line stays consumable -----------------
# A frozen legacy file saved with CRLF endings (a merge/editor artifact — the
# exact case check-obs.sh / check-ledger.sh / drain-gates.sh strip `\r$` for)
# must still match by content: the comparison is CR-insensitive, so the line is
# consumed, not misreported as absent. The annotation lands LF-terminated and
# untouched neighbor lines keep their bytes (CR included).

o=$(new_obs "$tmp/o12d")
cr=$(printf '\r')
CRLINE='- 2026-06-10 [planwright] crlf saved line'
NEIGH='- 2026-06-11 [planwright] crlf neighbor'
printf '# frozen\r\n\r\n%s\r\n%s\r\n' "$CRLINE" "$NEIGH" >"$o/opportunities.md"
"$CONSUME" --obs-dir "$o" --legacy --line "$CRLINE" --spec my-spec --today 2026-07-10 \
  || fail "12d: a CRLF-saved legacy line must stay consumable (not exit 3)"
# The annotation lands LF-terminated (no stray CR carried into the consumed line).
grep -Fxq -e "$CRLINE — consumed-by: specs/my-spec (2026-07-10)" "$o/opportunities.md" \
  || fail "12d: the CRLF line was not annotated (or the annotation kept a CR)"
# The untouched neighbor keeps its original trailing CR (pass-through is verbatim).
grep -Fxq -e "$NEIGH$cr" "$o/opportunities.md" \
  || fail "12d: a neighbor line lost its CR (pass-through lines must stay verbatim)"
echo "ok 12d: a CRLF-saved legacy line stays consumable, neighbors verbatim"

# --- 12e. Legacy line already consumed by another spec → not found (exit 3) -
# Pins the accepted fragment/legacy asymmetry recorded in this spec's
# opportunities.md observation: a frozen line carries no bare copy once
# annotated, so a *different* spec consuming it exits 3 (not-found) rather than
# unioning a second `— consumed-by:` citation the way the fragment arm does for
# an already-archived fragment (§11c). Locks the behavior against silent drift.

o=$(new_obs "$tmp/o12e")
BASE='- 2026-06-10 [planwright] a cross-spec legacy line'
printf '%s\n' '# frozen' '' "$BASE — consumed-by: specs/spec-one (2026-07-09)" \
  >"$o/opportunities.md"
before=$(cat "$o/opportunities.md")
rc=0
"$CONSUME" --obs-dir "$o" --legacy --line "$BASE" --spec spec-two --today 2026-07-10 \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 3 ] || fail "12e: a line consumed by another spec expected exit 3, got $rc"
[ "$(cat "$o/opportunities.md")" = "$before" ] \
  || fail "12e: the cross-spec refusal mutated the frozen log"
echo "ok 12e: a legacy line consumed by another spec is a not-found refusal (exit 3)"

# --- 12f. A legacy-arm awk runtime error is a filesystem refusal (exit 1) --
# The two awk passes exit 0 (matched), 1 (no match), or >1 (runtime/read error).
# An error exit must map to the header's filesystem-error refusal (exit 1), not
# be misread as not-found (exit 3). Fault-inject via an `awk` PATH stub.

o=$(new_obs "$tmp/o12f")
printf '%s\n' '# frozen' '' '- 2026-06-10 [planwright] present' >"$o/opportunities.md"

# (a) The rewrite awk errors (exit 2) → exit 1, not 3.
stub="$tmp/awkstub-a"
make_awk_stub "$stub" 2
rc=0
PATH="$stub:$PATH" "$CONSUME" --obs-dir "$o" --legacy --line '- 2026-06-10 [planwright] present' \
  --spec my-spec --today 2026-07-10 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "12f: a rewrite-awk runtime error expected exit 1, got $rc"

# (b) The rewrite awk reports no match (exit 1) but the no-op probe awk errors
# (exit 2) → exit 1, not 3.
stub="$tmp/awkstub-b"
make_awk_stub "$stub" 1 2
rc=0
PATH="$stub:$PATH" "$CONSUME" --obs-dir "$o" --legacy --line '- 2026-06-10 [planwright] present' \
  --spec my-spec --today 2026-07-10 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "12f: a probe-awk runtime error expected exit 1, got $rc"
echo "ok 12f: a legacy-arm awk runtime error is a filesystem refusal (exit 1)"

# --- 12g. A symlinked frozen legacy file is a symlink refusal (exit 1) -----
# The frozen `opportunities.md` is a containment surface like the fragment dirs:
# a symlinked frozen file must refuse (exit 1), never be followed. A *dangling*
# symlink must not slip through the existence probe as a benign "no frozen file"
# (exit 3) — the symlink check has to precede `[ -e ]`, mirroring the obs-dir
# root guard.

o=$(new_obs "$tmp/o12g")
ln -s "$tmp/o12g-frozen-nonexistent" "$o/opportunities.md"
rc=0
"$CONSUME" --obs-dir "$o" --legacy --line '- 2026-06-10 [planwright] x' \
  --spec my-spec --today 2026-07-10 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "12g: a dangling-symlink frozen file expected exit 1, got $rc"

# A live symlink to a real frozen file is refused too, and the target is never
# annotated through the link.
real="$tmp/o12g-real-frozen"
printf '%s\n' '# frozen' '' '- 2026-06-10 [planwright] present' >"$real"
before=$(cat "$real")
rm -f "$o/opportunities.md"
ln -s "$real" "$o/opportunities.md"
rc=0
"$CONSUME" --obs-dir "$o" --legacy --line '- 2026-06-10 [planwright] present' \
  --spec my-spec --today 2026-07-10 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "12g: a live-symlink frozen file expected exit 1, got $rc"
[ "$(cat "$real")" = "$before" ] \
  || fail "12g: the frozen symlink target was annotated through the link"
echo "ok 12g: a symlinked frozen legacy file refuses (exit 1), target untouched"
echo "PASS: all obs-consume legacy-arm checks"
