#!/bin/sh
# Unit test for scripts/obs-consume.sh — the FRAGMENT arm of the observation
# consumption + archival helper (observation-recording Task 4, REQ-A1.5,
# REQ-C1.2, REQ-D1.1, REQ-D1.3; D-3, D-7). Consumption semantics are normative
# in specs/observation-recording/{requirements,design}.md.
#
# Split into three files (guard-coverage Task 6, REQ-E1.2, D-9): this file was a
# wall-clock straggler, so its three cohesive arms now run as three files that
# the runner's tests/*.sh discovery picks up in parallel. The frozen-log arm
# (sections 12–12g) lives in tests/test-obs-consume-legacy.sh and the
# git-integration, usage-contract, and cross-guard cases (sections 13–15) in
# tests/test-obs-consume-git.sh. No assertion changed in the split.
#
# Properties verified (numbered to match the body's check sections):
#   1. Happy path (REQ-B1.2, REQ-C1.2): a live fragment consumed by UID lands in
#      archive/ with the filename (and UID) preserved, carries exactly one
#      `Consumed-by: specs/<spec> (<date>)` line, and leaves entries/ empty.
#   2. Slug rename then consume by UID (REQ-A1.5): renaming a fragment's slug in
#      entries/ does not break the consume — resolution keys on the UID and the
#      archived name preserves the (renamed) filename.
#   3. Content edit then consume by UID (REQ-A1.5): editing the fragment's entry
#      text does not break the consume — identity is never keyed on entry text.
#   4. Citation stability (REQ-A1.5): after the move, `obs:<uid>` greps to
#      exactly one file across entries/ + archive/.
#   5. Re-run idempotency (REQ-C1.2): a second consume of an already-archived
#      same-spec fragment is a clean no-op (exit 0, single annotation, no churn).
#   6. Crash-window completion (REQ-C1.2): a fragment already annotated but still
#      in entries/ (a crash between annotate and move) is completed idempotently —
#      moved to archive/ with exactly one Consumed-by line, never duplicated.
#   7. Unknown-UID refusal (REQ-C1.2): a UID present in neither directory refuses
#      non-zero and touches no path.
#   8. Duplicate-UID refusal (REQ-C1.2, D-2 window): two fragments sharing a UID
#      refuse non-zero, the message naming every match, with no path touched.
#   9. Hostile UID/spec refusals (REQ-D1.1): traversal, glob, newline, uppercase,
#      and wrong-length UID/spec arguments each refuse non-zero before any write —
#      no fragment moved, no Consumed-by line written, no message echoing the raw
#      value or a control byte.
#  10. Symlinked fragment refused (REQ-D1.1): a fragment that is a symlink is
#      refused before annotate or move (never read/written through a link).
#  11. Hostile fragment content is data (REQ-D1.3): a fragment whose entry text
#      carries shell metacharacters and control bytes is moved verbatim with no
#      expansion side effect.
#
# Exit codes asserted throughout: 1 refusal (grammar/containment/content/symlink/
# fs), 3 not found (unknown UID), 4 ambiguous (duplicate UID) — the header
# contract of scripts/obs-consume.sh. The usage arm (exit 2) is asserted in
# tests/test-obs-consume-git.sh.
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
REC="$here/../scripts/obs-record.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$CONSUME" ] || fail "scripts/obs-consume.sh missing or not executable"
[ -x "$REC" ] || fail "scripts/obs-record.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

NAME_RE='^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[a-z0-9][a-z0-9-]*-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]\.md$'

# new_obs <dir> — a fresh observations dir with empty entries/ + archive/.
new_obs() {
  mkdir -p "$1/entries" "$1/archive"
  printf '%s' "$1"
}

# make_od_stub <dir> <hex1> [<hex2> ...] — an `od` on PATH emitting the given
# UIDs in call order (the suite's usual command-stub seam; see
# tests/test-obs-record.sh), so a recorded fragment's UID is deterministic.
make_od_stub() {
  _d=$1
  shift
  mkdir -p "$_d"
  : >"$_d/seq"
  for _u in "$@"; do printf '%s\n' "$_u" >>"$_d/seq"; done
  printf '0\n' >"$_d/n"
  cat >"$_d/od" <<EOF
#!/bin/sh
n=\$(cat "$_d/n" 2>/dev/null || echo 0)
n=\$((n + 1))
echo "\$n" >"$_d/n"
line=\$(sed -n "\${n}p" "$_d/seq")
[ -n "\$line" ] || line=\$(tail -n 1 "$_d/seq")
printf '%s' "\$line"
EOF
  chmod +x "$_d/od"
}

# record <obs> <uid> <slug> <text> — record one fragment with a deterministic
# UID and a fixed date, echoing the created fragment's basename.
record() {
  _o=$1
  _uid=$2
  _slug=$3
  _text=$4
  _stub="$tmp/od-$_uid-$$-$(frag_count "$_o/entries")"
  make_od_stub "$_stub" "$_uid"
  PATH="$_stub:$PATH" "$REC" --obs-dir "$_o" --slug "$_slug" --scope planwright \
    --text "$_text" --today 2026-07-09 >/dev/null \
    || fail "record helper failed for uid $_uid"
  echo "2026-07-09-$_slug-$_uid.md"
}

# frag_count <dir> — number of *.md fragments under a directory (null-safe).
frag_count() {
  _c=0
  for _f in "$1"/*.md; do
    [ -e "$_f" ] && _c=$((_c + 1))
  done
  echo "$_c"
}

# consumed_count <file> — number of `Consumed-by:` metadata lines in a fragment.
# `grep -c` prints 0 and exits 1 on no match, so capture then default rather than
# piping a second `echo 0` that would emit a two-line count.
consumed_count() {
  _n=$(grep -c '^Consumed-by: ' "$1" 2>/dev/null) || _n=0
  printf '%s' "$_n"
}

# --- 1. Happy path -------------------------------------------------------

o=$(new_obs "$tmp/o1")
frag=$(record "$o" aaaa1111 topic-alpha 'a real observation')
"$CONSUME" --obs-dir "$o" --uid aaaa1111 --spec my-spec --today 2026-07-10 \
  || fail "1: happy-path consume exited non-zero"
[ ! -e "$o/entries/$frag" ] || fail "1: fragment still in entries/ after consume"
[ -f "$o/archive/$frag" ] || fail "1: fragment not in archive/ after consume"
echo "$frag" | grep -Eq "$NAME_RE" \
  || fail "1: archived name [$frag] no longer matches the grammar"
[ "$(consumed_count "$o/archive/$frag")" -eq 1 ] \
  || fail "1: archived fragment must carry exactly one Consumed-by line"
grep -Fxq -e '- 2026-07-09 [planwright] a real observation' "$o/archive/$frag" \
  || fail "1: original entry line not preserved verbatim"
grep -Fxq 'Consumed-by: specs/my-spec (2026-07-10)' "$o/archive/$frag" \
  || fail "1: Consumed-by annotation is not the expected form"
[ "$(frag_count "$o/entries")" -eq 0 ] || fail "1: entries/ must be empty"
echo "ok 1: a fragment consumed by UID moves to archive/ with one annotation"

# --- 2. Slug rename then consume by UID ----------------------------------

o=$(new_obs "$tmp/o2")
frag=$(record "$o" bbbb2222 old-slug 'renameable topic')
mv "$o/entries/$frag" "$o/entries/2026-07-09-new-slug-bbbb2222.md"
"$CONSUME" --obs-dir "$o" --uid bbbb2222 --spec my-spec --today 2026-07-10 \
  || fail "2: consume after slug rename exited non-zero"
[ -f "$o/archive/2026-07-09-new-slug-bbbb2222.md" ] \
  || fail "2: renamed fragment not archived under its (renamed) name"
[ "$(frag_count "$o/entries")" -eq 0 ] || fail "2: entries/ must be empty"
echo "ok 2: consume resolves by UID after a slug rename"

# --- 3. Content edit then consume by UID ---------------------------------

o=$(new_obs "$tmp/o3")
frag=$(record "$o" cccc3333 topic 'original text')
printf '%s\n' '- 2026-07-09 [planwright] EDITED text' >"$o/entries/$frag"
"$CONSUME" --obs-dir "$o" --uid cccc3333 --spec my-spec --today 2026-07-10 \
  || fail "3: consume after content edit exited non-zero"
[ -f "$o/archive/$frag" ] || fail "3: content-edited fragment not archived"
grep -Fxq -e '- 2026-07-09 [planwright] EDITED text' "$o/archive/$frag" \
  || fail "3: edited entry text not preserved"
echo "ok 3: consume resolves by UID after a content edit"

# --- 4. Citation stability (obs:<uid> → one file) ------------------------

o=$(new_obs "$tmp/o4")
frag=$(record "$o" dddd4444 topic 'cite me')
"$CONSUME" --obs-dir "$o" --uid dddd4444 --spec my-spec --today 2026-07-10 \
  || fail "4: consume exited non-zero"
hits=0
for d in "$o/entries" "$o/archive"; do
  for f in "$d"/*-dddd4444.md; do
    [ -e "$f" ] && hits=$((hits + 1))
  done
done
[ "$hits" -eq 1 ] || fail "4: obs:dddd4444 resolves to $hits files, expected 1"
echo "ok 4: obs:<uid> resolves to exactly one file after the move"

# --- 5. Re-run idempotency (already-archived same-spec = no-op) -----------

o=$(new_obs "$tmp/o5")
frag=$(record "$o" eeee5555 topic 'consume me twice')
"$CONSUME" --obs-dir "$o" --uid eeee5555 --spec my-spec --today 2026-07-10 \
  || fail "5: first consume exited non-zero"
before=$(cat "$o/archive/$frag")
"$CONSUME" --obs-dir "$o" --uid eeee5555 --spec my-spec --today 2026-07-11 \
  || fail "5: second consume (no-op) must exit 0"
after=$(cat "$o/archive/$frag")
[ "$before" = "$after" ] || fail "5: re-run changed the archived fragment"
[ "$(consumed_count "$o/archive/$frag")" -eq 1 ] \
  || fail "5: re-run duplicated the Consumed-by annotation"
echo "ok 5: a fully archived same-spec consume is a clean no-op"

# --- 6. Crash-window completion (annotated but unmoved) ------------------

o=$(new_obs "$tmp/o6")
frag=$(record "$o" ffff6666 topic 'crashed mid-consume')
# Simulate a crash between annotate and move: the annotation is present but the
# fragment is still in entries/.
printf 'Consumed-by: specs/my-spec (2026-07-10)\n' >>"$o/entries/$frag"
"$CONSUME" --obs-dir "$o" --uid ffff6666 --spec my-spec --today 2026-07-11 \
  || fail "6: crash-window completion exited non-zero"
[ ! -e "$o/entries/$frag" ] || fail "6: crashed fragment not moved out of entries/"
[ -f "$o/archive/$frag" ] || fail "6: crashed fragment not completed into archive/"
[ "$(consumed_count "$o/archive/$frag")" -eq 1 ] \
  || fail "6: crash completion duplicated the annotation"
grep -Fxq 'Consumed-by: specs/my-spec (2026-07-10)' "$o/archive/$frag" \
  || fail "6: crash completion did not preserve the original annotation date"
echo "ok 6: an annotated-but-unmoved fragment completes without duplicating"

# --- 7. Unknown-UID refusal ----------------------------------------------

o=$(new_obs "$tmp/o7")
record "$o" 11112222 topic 'present' >/dev/null
before=$(find "$o" | sort)
rc=0
"$CONSUME" --obs-dir "$o" --uid deadbeef --spec my-spec --today 2026-07-10 \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 3 ] || fail "7: unknown UID expected exit 3, got $rc"
after=$(find "$o" | sort)
[ "$before" = "$after" ] || fail "7: unknown-UID refusal touched a path"
echo "ok 7: an unknown UID is a clean not-found refusal (exit 3)"

# --- 7b. Absent observations directory is a not-found refusal (exit 3) -----
# Consume refuses when the store does not exist (fragments must have been
# recorded into it first) — unlike obs-record.sh, which creates it. Named in the
# header exit-code contract; distinct from the unknown-UID case above (there the
# dir exists) and from §12c's absent-frozen-file case (there --obs-dir exists).

rc=0
"$CONSUME" --obs-dir "$tmp/o7b-absent" --uid deadbeef --spec my-spec \
  --today 2026-07-10 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 3 ] || fail "7b: an absent obs-dir expected exit 3, got $rc"
[ ! -e "$tmp/o7b-absent" ] || fail "7b: consume created the absent obs-dir"
echo "ok 7b: an absent observations directory is a not-found refusal (exit 3)"

# --- 8. Duplicate-UID refusal --------------------------------------------

o=$(new_obs "$tmp/o8")
frag=$(record "$o" abcd0001 topic 'first copy')
# Seed a second fragment carrying the same UID (a merge/hand-edit artifact —
# the D-2 duplicate window): one in entries/, one already in archive/.
cp "$o/entries/$frag" "$o/archive/2026-07-09-other-abcd0001.md"
before=$(find "$o" | sort)
out=$("$CONSUME" --obs-dir "$o" --uid abcd0001 --spec my-spec --today 2026-07-10 \
  2>&1) && fail "8: duplicate UID must refuse non-zero" || rc=$?
[ "$rc" -eq 4 ] || fail "8: duplicate UID expected exit 4, got $rc"
printf '%s\n' "$out" | grep -q "2026-07-09-topic-abcd0001.md" \
  || fail "8: refusal must name the first match"
printf '%s\n' "$out" | grep -q "2026-07-09-other-abcd0001.md" \
  || fail "8: refusal must name the second match"
after=$(find "$o" | sort)
[ "$before" = "$after" ] || fail "8: duplicate-UID refusal touched a path"

# A duplicate-UID name that entered by hand/merge can carry control bytes; the
# exit-4 message reports on-disk names, so they must be sanitized (D-7 echo
# discipline) — no raw escape byte reaches the terminal / CI log.
o=$(new_obs "$tmp/o8b")
frag=$(record "$o" abcd0002 topic 'first copy')
esc=$(printf 'x\033]0;pwn\007y')
cp "$o/entries/$frag" "$o/archive/2026-07-09-$esc-abcd0002.md"
msg=$("$CONSUME" --obs-dir "$o" --uid abcd0002 --spec my-spec --today 2026-07-10 \
  2>&1) && fail "8: hostile duplicate name must refuse" || rc=$?
[ "$rc" -eq 4 ] || fail "8: hostile duplicate expected exit 4, got $rc"
printf '%s' "$msg" | LC_ALL=C tr -d '\040-\176\n' | grep -q . \
  && fail "8: duplicate-UID message carried a raw control byte"
echo "ok 8: a duplicate UID refuses (exit 4) naming every (sanitized) match"

# --- 9. Hostile UID / spec refusals --------------------------------------

o=$(new_obs "$tmp/o9")
frag=$(record "$o" 99990000 topic 'guarded')
before=$(find "$o" | sort)

# hostile_uid <label> <uid>
hostile_uid() {
  _rc=0
  _msg=$("$CONSUME" --obs-dir "$o" --uid "$2" --spec my-spec --today 2026-07-10 \
    2>&1) && fail "9: hostile UID [$1] must refuse" || _rc=$?
  [ "$_rc" -ne 0 ] || fail "9: hostile UID [$1] returned 0"
  # No control byte survives to the message.
  printf '%s' "$_msg" | LC_ALL=C tr -d '\040-\176\n' | grep -q . \
    && fail "9: hostile UID [$1] message carried a control byte"
  _now=$(find "$o" | sort)
  [ "$before" = "$_now" ] || fail "9: hostile UID [$1] touched a path"
}
hostile_uid traversal '../../../etc/passwd'
hostile_uid glob '*'
hostile_uid uppercase 'AAAA1111'
hostile_uid short 'aaa'
hostile_uid long 'aaaa11112'
hostile_uid newline 'aaaa
1111'

# hostile_spec <label> <spec>
hostile_spec() {
  _rc=0
  _msg=$("$CONSUME" --obs-dir "$o" --uid 99990000 --spec "$2" --today 2026-07-10 \
    2>&1) && fail "9: hostile spec [$1] must refuse" || _rc=$?
  [ "$_rc" -ne 0 ] || fail "9: hostile spec [$1] returned 0"
  # No control byte survives to the message (the newline-injection case in
  # particular must not reach the Consumed-by line or the terminal).
  printf '%s' "$_msg" | LC_ALL=C tr -d '\040-\176\n' | grep -q . \
    && fail "9: hostile spec [$1] message carried a control byte"
  # The fragment is never annotated or moved on a spec refusal.
  [ -f "$o/entries/$frag" ] || fail "9: hostile spec [$1] moved the fragment"
  [ "$(consumed_count "$o/entries/$frag")" -eq 0 ] \
    || fail "9: hostile spec [$1] wrote a Consumed-by line"
}
hostile_spec traversal '../../evil'
hostile_spec glob 'a*b'
hostile_spec uppercase 'My-Spec'
hostile_spec slash 'specs/my-spec'
hostile_spec newline 'a
b'
hostile_spec leadhyphen '-spec'
after=$(find "$o" | sort)
[ "$before" = "$after" ] || fail "9: a hostile refusal touched a path"
echo "ok 9: hostile UID/spec arguments refuse cleanly with no path touched"

# --- 10. Symlinked fragment refused --------------------------------------

o=$(new_obs "$tmp/o10")
printf '%s\n' '- 2026-07-09 [planwright] real target' >"$tmp/target10.md"
ln -s "$tmp/target10.md" "$o/entries/2026-07-09-topic-cafe0001.md"
rc=0
"$CONSUME" --obs-dir "$o" --uid cafe0001 --spec my-spec --today 2026-07-10 \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "10: a symlinked fragment expected exit 1, got $rc"
[ -L "$o/entries/2026-07-09-topic-cafe0001.md" ] \
  || fail "10: the symlink was moved/rewritten instead of refused"
[ ! -e "$o/archive/2026-07-09-topic-cafe0001.md" ] \
  || fail "10: a symlinked fragment reached archive/"
# The link target is never written through.
[ "$(consumed_count "$tmp/target10.md")" -eq 0 ] \
  || fail "10: the symlink target was annotated through the link"

# A symlinked fragment *directory* is an escape vector too — refuse before the
# glob reads through it.
realdir="$tmp/realentries10"
mkdir -p "$realdir"
printf '%s\n' '- 2026-07-09 [planwright] outside the tree' \
  >"$realdir/2026-07-09-topic-d00d0001.md"
odir=$(mktemp -d)/o
mkdir -p "$odir/archive"
ln -s "$realdir" "$odir/entries"
rc=0
"$CONSUME" --obs-dir "$odir" --uid d00d0001 --spec my-spec --today 2026-07-10 \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "10: a symlinked entries/ dir expected exit 1, got $rc"
[ "$(consumed_count "$realdir/2026-07-09-topic-d00d0001.md")" -eq 0 ] \
  || fail "10: a fragment was annotated through a symlinked directory"
echo "ok 10: a symlinked fragment (and fragment directory) is refused"

# --- 10b. A dangling-symlink --obs-dir is a symlink refusal (exit 1) -------
# The observations root is an escape vector: a symlinked root must refuse (exit
# 1), never be followed. A *dangling* symlink must not slip through the
# existence probe as a benign "does not exist" (exit 3) — the symlink check has
# to win so the escape vector reads as what it is.

odir="$tmp/o10b-link"
ln -s "$tmp/o10b-nonexistent-target" "$odir"
rc=0
"$CONSUME" --obs-dir "$odir" --uid cafe0002 --spec my-spec --today 2026-07-10 \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "10b: a dangling-symlink obs-dir expected exit 1, got $rc"
echo "ok 10b: a dangling-symlink obs-dir refuses as a symlink (exit 1)"

# --- 10c. obs-dir containment refusals (exit 1) ---------------------------
# The three remaining --obs-dir containment guards, each a validate/contain/
# refuse point (D-7): a leading-hyphen path (a bare '-' would make `cd` a `cd -`
# rerooting the store at $OLDPWD), a symlinked root pointing at a *real* dir (an
# escape vector), and a root that exists but is a plain file. Each refuses exit 1
# and touches nothing.

rc=0
"$CONSUME" --obs-dir '-notadir' --uid cafe0003 --spec my-spec --today 2026-07-10 \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "10c: a leading-hyphen obs-dir expected exit 1, got $rc"

realdir="$tmp/o10c-real"
mkdir -p "$realdir/entries" "$realdir/archive"
link="$tmp/o10c-link"
ln -s "$realdir" "$link"
rc=0
"$CONSUME" --obs-dir "$link" --uid cafe0004 --spec my-spec --today 2026-07-10 \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "10c: a symlinked (live) obs-dir expected exit 1, got $rc"

filedir="$tmp/o10c-file"
printf 'not a dir\n' >"$filedir"
rc=0
"$CONSUME" --obs-dir "$filedir" --uid cafe0005 --spec my-spec --today 2026-07-10 \
  >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "10c: a not-a-directory obs-dir expected exit 1, got $rc"
echo "ok 10c: leading-hyphen, symlinked, and non-directory obs-dir all refuse (exit 1)"

# --- 11. Hostile fragment content is data --------------------------------

o=$(new_obs "$tmp/o11")
frag=$(record "$o" beef0001 topic 'hostile below')
# Overwrite with content carrying shell metacharacters (as literal data). Guard
# marker file: if the consume ever *expands* the content, this file appears.
# shellcheck disable=SC2016 # the $(...)/`...` are literal hostile data, must NOT expand
printf '%s\n' '- 2026-07-09 [planwright] $(touch '"$tmp"'/PWNED) `id` && rm -rf x' \
  >"$o/entries/$frag"
"$CONSUME" --obs-dir "$o" --uid beef0001 --spec my-spec --today 2026-07-10 \
  || fail "11: consuming hostile content exited non-zero"
[ ! -e "$tmp/PWNED" ] || fail "11: fragment content was expanded (command ran)"
[ -f "$o/archive/$frag" ] || fail "11: hostile-content fragment not archived"
# shellcheck disable=SC2016 # matching the literal '$(touch' substring, not expanding it
grep -Fq '$(touch' "$o/archive/$frag" \
  || fail "11: hostile content not moved verbatim"

# Control bytes in the content are moved verbatim too (byte-exact), and the
# annotation lands on its own line rather than joining a non-newline-terminated
# body (the od-based trailing-newline probe).
o=$(new_obs "$tmp/o11b")
frag=$(record "$o" beef0002 topic 'ctrl below')
printf '%s\033[31m%s\n' '- 2026-07-09 [planwright] esc ' 'here' >"$o/entries/$frag"
body_before=$(od -An -tx1 "$o/entries/$frag" | tr -d ' \n')
"$CONSUME" --obs-dir "$o" --uid beef0002 --spec my-spec --today 2026-07-10 \
  || fail "11: consuming control-byte content exited non-zero"
# The archived file is the original bytes followed by exactly the annotation line.
annot=$(printf 'Consumed-by: specs/my-spec (2026-07-10)\n' | od -An -tx1 | tr -d ' \n')
body_after=$(od -An -tx1 "$o/archive/$frag" | tr -d ' \n')
[ "$body_after" = "$body_before$annot" ] \
  || fail "11: control-byte content not preserved byte-exact with annotation appended"
[ "$(consumed_count "$o/archive/$frag")" -eq 1 ] \
  || fail "11: annotation did not land on its own line"

# A fragment body WITHOUT a trailing newline must still get the annotation on
# its own line (exercises the ends_in_newline "add a separator" branch — the
# whole reason the od probe exists). `printf` with no \n leaves the last byte a
# non-newline.
o=$(new_obs "$tmp/o11d")
frag=$(record "$o" beef0004 topic 'placeholder')
printf '%s' '- 2026-07-09 [planwright] no trailing newline here' >"$o/entries/$frag"
[ "$(tail -c1 "$o/entries/$frag" | od -An -tx1 | tr -d ' \n')" != "0a" ] \
  || fail "11d: fixture unexpectedly ends in a newline"
"$CONSUME" --obs-dir "$o" --uid beef0004 --spec my-spec --today 2026-07-10 \
  || fail "11d: consume of a newline-less fragment exited non-zero"
[ "$(consumed_count "$o/archive/$frag")" -eq 1 ] \
  || fail "11d: annotation joined the last line (missing separator) — not on its own line"
grep -Fxq -e '- 2026-07-09 [planwright] no trailing newline here' "$o/archive/$frag" \
  || fail "11d: the original last line was mangled by the appended annotation"
echo "ok 11 (incl. 11d): fragment content moved verbatim; annotation always on its own line"

# --- 11c. Archived fragment consumed by a *different* spec unions the citation

o=$(new_obs "$tmp/o11c")
frag=$(record "$o" beef0003 topic 'archived by another')
# Simulate a fragment already consumed + archived by spec-one.
mv "$o/entries/$frag" "$o/archive/$frag"
printf 'Consumed-by: specs/spec-one (2026-07-09)\n' >>"$o/archive/$frag"
"$CONSUME" --obs-dir "$o" --uid beef0003 --spec spec-two --today 2026-07-10 \
  || fail "11c: consuming an already-archived fragment by a new spec exited non-zero"
[ -f "$o/archive/$frag" ] || fail "11c: fragment left archive/ (should stay, no move)"
[ ! -e "$o/entries/$frag" ] || fail "11c: fragment reappeared in entries/"
[ "$(consumed_count "$o/archive/$frag")" -eq 2 ] \
  || fail "11c: cross-spec consume did not union a second Consumed-by line"
grep -Fxq 'Consumed-by: specs/spec-one (2026-07-09)' "$o/archive/$frag" \
  || fail "11c: original spec-one citation lost"
grep -Fxq 'Consumed-by: specs/spec-two (2026-07-10)' "$o/archive/$frag" \
  || fail "11c: spec-two citation not added"
# A re-run by spec-two is now a clean no-op (single spec-two line).
"$CONSUME" --obs-dir "$o" --uid beef0003 --spec spec-two --today 2026-07-11 \
  || fail "11c: re-run by spec-two must be a clean no-op"
[ "$(consumed_count "$o/archive/$frag")" -eq 2 ] \
  || fail "11c: re-run duplicated the spec-two citation"
echo "ok 11c: an archived fragment consumed by a new spec unions the citation, idempotent"
echo "PASS: all obs-consume fragment-arm checks"
