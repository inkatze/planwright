#!/bin/sh
# Unit test for scripts/obs-record.sh — the single shared observation-recording
# helper (observation-recording Task 1, REQ-A1.1..A1.6, REQ-B1.1, REQ-D1.1;
# D-1, D-2, D-6, D-7). Grammar and identity semantics are normative in
# specs/observation-recording/{requirements,design}.md.
#
# Properties verified (numbered to match the body's check sections):
#   1. Happy path: one invocation writes exactly one grammar-valid fragment
#      under entries/, carrying the one-line entry form, and touches no other
#      path (before/after tree listing, REQ-A1.1, REQ-A1.4).
#   2. Two same-day, same-slug invocations produce distinct filenames and both
#      files survive (REQ-A1.1, REQ-A1.3, REQ-A1.5).
#   3. Filename/component-grammar acceptance/rejection (REQ-A1.2): malformed
#      date shape, non-calendar date (2026-02-30) and month (2026-13-01), and
#      leap discrimination (non-leap 2026-/1900-02-29 reject, leap 2024-/
#      2000-02-29 accept); slug rejects (uppercase, underscore, leading- and
#      doubled-hyphen, >40) and the scope-grammar rejects (whitespace,
#      non-alnum lead, bracket, >64); the 40-char slug and 64-char scope
#      boundaries accept.
#   4. UID minting is entropy-sourced and shape-checked (REQ-A1.2, REQ-A1.3):
#      a stubbed reader returning a non-hex / wrong-length value is a clean
#      refusal (entropy failure), never a written path.
#   5. Fail-on-exists collision retry (REQ-A1.3): a pre-created colliding
#      filename forces a fresh-UID retry with the original's bytes untouched;
#      a UID colliding only with an *archived* fragment forces the retry; a
#      same-directory collision under a *different slug* forces the retry
#      (the check keys on the UID, not the full filename).
#   6. Bounded retry exhaustion (REQ-A1.3): a stubbed entropy source returning
#      a constant already-present UID exhausts every retry; the helper exits
#      non-zero with no path created and the colliding file untouched (the
#      exclusive publish refuses an existing destination, never replaces it).
#   7. Entry-content refusal (REQ-A1.4): entry text carrying a newline or a
#      control character is refused at write time (exact exit 1), no path
#      created; legitimate C1/UTF-8 prose (an em-dash) is instead accepted.
#   8. Atomic exclusive publish (REQ-A1.6): a simulated failure between
#      temp-write and publish leaves no fragment and no temp residue under
#      entries/ (no reader ever sees a torn fragment). 8b: an ln failure whose
#      destination now exists is a racing-writer retry, not an fs-error refusal.
#      8c: a fatal signal (TERM) mid-publish terminates the loop (exit 143)
#      rather than running the cleanup trap and resuming into the publish.
#   9. Concurrent adds never conflict (REQ-B1.1): two branches from a common
#      base each record a same-day, same-slug observation; git merge completes
#      with no conflict and both fragments exist.
#  10. Validate / contain / refuse (REQ-D1.1): path-traversal slug or date,
#      absolute-path slug, control-character slug, and a locale-dependent
#      uppercase slug under a UTF-8 locale (asserting LC_ALL=C behavior) each
#      exit 1, create no path, and print a message carrying neither raw
#      control bytes nor the untrusted value echoed verbatim; plus direct
#      containment units — entries/ a symlink escaping to an existing dir, and
#      to a non-existent target (proving the escape target is never
#      materialized as a side effect), and the observations root itself a
#      symlink (the obs-dir guard, refused before canonicalization); plus a
#      hyphen-leading --obs-dir refused before mkdir/cd (a bare '-' would make
#      `cd "$obsdir"` a `cd -` that roots the store at $OLDPWD).
#  11. Exit-code contract (REQ-A1.6, D-6): missing required flags, an unknown
#      flag, a flag without its value, and a trailing token all exit 2
#      (usage); present-but-empty --slug/--scope exit 2 while empty --text is a
#      content refusal (exit 1); an unusable observations dir exits 1;
#      -h/--help prints usage and exits 0; the default-date path (no --today)
#      mints the system date into the fragment name.
#
# Exit codes asserted throughout: 1 refusal/fs-error, 2 usage, 3 collision
# exhaustion, 4 entropy failure — the header contract of scripts/obs-record.sh.
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
REC="$here/../scripts/obs-record.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$REC" ] || fail "scripts/obs-record.sh missing or not executable"

# Resolve the real `ln` once, now, while PATH is still unshadowed. Section 8b
# shadows `ln` on PATH with a failing stub, so the stub cannot reach the real
# `ln` by name (a bare `ln` would recurse into the stub) and a hard-coded
# /bin/ln is not portable (some environments ship ln only under /usr/bin or a
# store path). `command -v` finds it wherever this environment keeps it (house
# convention, see tests/test-tool-discovery.sh's `command -v git`).
REAL_LN=$(command -v ln) || fail "cannot locate 'ln' on PATH"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

NAME_RE='^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[a-z0-9][a-z0-9-]*-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]\.md$'

# new_obs <dir> — make a fresh observations dir with empty entries/ + archive/
# so a before/after diff isolates exactly what an invocation touches. Echoes
# the observations dir path.
new_obs() {
  mkdir -p "$1/entries" "$1/archive"
  printf '%s' "$1"
}

# make_od_stub <dir> <hex1> [<hex2> ...] — drop an `od` on PATH that emits the
# given UIDs in call order, one per invocation, repeating the last once the
# sequence is exhausted. This is the suite's usual command-stub seam: the
# helper mints via `od ... /dev/urandom | tr -d ' \n'`, so a stubbed `od`
# controls the minted UID deterministically (the 2^32 space cannot be
# pre-seeded).
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

# frag_count <dir> — number of *.md fragments under a directory (null-safe).
frag_count() {
  _c=0
  for _f in "$1"/*.md; do
    [ -e "$_f" ] && _c=$((_c + 1))
  done
  echo "$_c"
}

# gitc <repo> <args...> — git with fixture identity, no signing, main default.
gitc() {
  _r=$1
  shift
  git -C "$_r" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# --- 1. Happy path -------------------------------------------------------

o=$(new_obs "$tmp/o1")
before=$(find "$o" | sort)
out=$("$REC" --obs-dir "$o" --slug topic-alpha --scope planwright \
  --text 'a real observation' --today 2026-07-09) \
  || fail "1: happy-path invocation exited non-zero"
after=$(find "$o" | sort)
[ "$(frag_count "$o/entries")" -eq 1 ] \
  || fail "1: expected exactly one fragment under entries/"
[ "$(frag_count "$o/archive")" -eq 0 ] \
  || fail "1: archive/ must be untouched"
frag=$(echo "$o"/entries/*.md)
base=$(basename "$frag")
echo "$base" | grep -Eq "$NAME_RE" \
  || fail "1: fragment name [$base] does not match the composite grammar"
case "$base" in
  2026-07-09-topic-alpha-*) : ;;
  *) fail "1: fragment name [$base] missing the minted date/slug prefix" ;;
esac
# The one-line entry form is the fragment's content.
[ "$(cat "$frag")" = "- 2026-07-09 [planwright] a real observation" ] \
  || fail "1: fragment content is not the expected one-line entry form"
# The only paths added are entries/ contents (the dir pre-existed).
printf '%s\n' "$before" >"$tmp/before1"
printf '%s\n' "$after" >"$tmp/after1"
# Fixed-string, whole-line match: `$frag` is a path carrying `.` (and other
# regex metacharacters from the temp dir), so a regex `^$frag$` would also
# match near-miss lines and silently hide a genuinely unexpected path (the very
# thing this assertion guards). -Fx pins it to the literal fragment line.
extra=$(comm -13 "$tmp/before1" "$tmp/after1" | grep -Fxv -- "$frag" || true)
[ -z "$extra" ] || fail "1: invocation touched unexpected paths: $extra"
# The helper reports the created fragment path on stdout.
[ "$out" = "$frag" ] || fail "1: stdout [$out] is not the created fragment path [$frag]"
echo "ok 1: one invocation writes exactly one grammar-valid entry-form fragment"

# --- 2. Distinct filenames for same-day, same-slug -----------------------

o=$(new_obs "$tmp/o2")
"$REC" --obs-dir "$o" --slug dupe --scope planwright --text 'first' \
  --today 2026-07-09 >/dev/null || fail "2: first record failed"
"$REC" --obs-dir "$o" --slug dupe --scope planwright --text 'second' \
  --today 2026-07-09 >/dev/null || fail "2: second record failed"
[ "$(frag_count "$o/entries")" -eq 2 ] \
  || fail "2: two same-day same-slug records must yield two distinct files"
echo "ok 2: same-day same-slug invocations produce distinct surviving files"

# --- 3. Filename-grammar rejection ---------------------------------------

o=$(new_obs "$tmp/o3")
reject() {
  # reject <label> <extra-args...> — asserts a grammar refusal (exit 1) that
  # writes no path.
  _label=$1
  shift
  _rc=0
  "$REC" --obs-dir "$o" --scope planwright --text 'x' "$@" >/dev/null 2>&1 \
    || _rc=$?
  [ "$_rc" -eq 1 ] || fail "3: $_label expected exit 1, got $_rc"
  [ "$(frag_count "$o/entries")" -eq 0 ] \
    || fail "3: $_label created a path on refusal"
}
reject "malformed date shape" --slug ok --today 2026-7-9
reject "non-calendar date 2026-02-30" --slug ok --today 2026-02-30
reject "non-calendar month" --slug ok --today 2026-13-01
# Leap-year discrimination: 2026-02-30 above rejects whether _max is 28 or 29,
# so it cannot tell a broken leap rule from a working one. A non-leap Feb 29
# and a century-non-leap Feb 29 must reject (the accept side is asserted below).
reject "non-leap Feb 29 (2026)" --slug ok --today 2026-02-29
reject "century non-leap Feb 29 (1900)" --slug ok --today 1900-02-29
reject "uppercase slug" --slug BadSlug --today 2026-07-09
reject "underscore slug" --slug bad_slug --today 2026-07-09
reject "leading-hyphen slug" --slug -bad --today 2026-07-09
reject "double-hyphen slug" --slug a--b --today 2026-07-09
# Scope grammar rejection (the charset/leading-char guard, distinct from the
# slug grammar above): a scope with whitespace, one opening with a non-alnum,
# and an overlong (>64) scope each refuse. `reject` fixes --scope planwright,
# so drive these through a bespoke check with an explicit --scope.
scope_reject() {
  _label=$1
  shift
  _rc=0
  "$REC" --obs-dir "$o" --slug ok --text 'x' --today 2026-07-09 "$@" \
    >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 1 ] || fail "3: $_label expected exit 1, got $_rc"
  [ "$(frag_count "$o/entries")" -eq 0 ] \
    || fail "3: $_label created a path on refusal"
}
scope_reject "scope with whitespace" --scope 'bad scope'
scope_reject "scope opening with a dot" --scope .hidden
scope_reject "scope with a bracket" --scope 'a[b]'
longscope=$(printf 'a%.0s' $(seq 1 65))
scope_reject "overlong scope" --scope "$longscope"
# overlong slug: 41 chars
long=$(printf 'a%.0s' $(seq 1 41))
reject "overlong slug" --slug "$long" --today 2026-07-09
# Accept-side boundaries (kept after every reject above, since each writes a
# fragment and the reject helpers assert an empty entries/).
# A 40-char slug is accepted (boundary).
ok40=$(printf 'a%.0s' $(seq 1 40))
"$REC" --obs-dir "$o" --slug "$ok40" --scope planwright --text 'x' \
  --today 2026-07-09 >/dev/null || fail "3: a 40-char slug must be accepted"
# A 64-char scope is accepted (the scope-length boundary, mirroring the slug).
ok64=$(printf 'a%.0s' $(seq 1 64))
"$REC" --obs-dir "$o" --slug ok --scope "$ok64" --text 'x' \
  --today 2026-07-09 >/dev/null || fail "3: a 64-char scope must be accepted"
# Leap Feb 29 must be ACCEPTED for a /4-non-/100 year and a /400 year — the
# accept side of the same rule the non-leap rejects above guard.
"$REC" --obs-dir "$o" --slug ok --scope planwright --text 'x' \
  --today 2024-02-29 >/dev/null || fail "3: leap-year Feb 29 (2024) must be accepted"
"$REC" --obs-dir "$o" --slug ok --scope planwright --text 'x' \
  --today 2000-02-29 >/dev/null || fail "3: 400-year leap Feb 29 (2000) must be accepted"
echo "ok 3: composite-grammar rejects refuse (write no path); boundaries accept"

# --- 4. Entropy-source shape check ---------------------------------------

o=$(new_obs "$tmp/o4")
entropy_reject() {
  # entropy_reject <label> <stub-dir> <minted-value> — a minted UID that is
  # not exactly 8 hex is a clean entropy refusal (exit 4), never a path.
  _label=$1
  make_od_stub "$2" "$3"
  _rc=0
  PATH="$2:$PATH" "$REC" --obs-dir "$o" --slug e --scope planwright \
    --text 'x' --today 2026-07-09 >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 4 ] || fail "4: $_label expected exit 4 (entropy), got $_rc"
  [ "$(frag_count "$o/entries")" -eq 0 ] || fail "4: $_label created a path"
}
entropy_reject "non-hex UID" "$tmp/badentropy" "nothex01"
entropy_reject "short UID" "$tmp/shortentropy" "dead"
entropy_reject "over-length UID" "$tmp/longentropy" "deadbeef0"
echo "ok 4: a bad entropy read (non-hex, short, or over-length) is a clean refusal"

# --- 5. Fail-on-exists collision retry (keys on the UID) -----------------

# 5a. Pre-created colliding filename in entries/: first mint collides, retry
# mints fresh; the pre-existing file's bytes stay untouched.
o=$(new_obs "$tmp/o5a")
printf 'ORIGINAL\n' >"$o/entries/2026-07-09-dupe-deadbeef.md"
make_od_stub "$tmp/od5a" deadbeef feedface
PATH="$tmp/od5a:$PATH" "$REC" --obs-dir "$o" --slug dupe --scope planwright \
  --text 'retry' --today 2026-07-09 >/dev/null \
  || fail "5a: collision retry should succeed on a fresh UID"
[ "$(cat "$o/entries/2026-07-09-dupe-deadbeef.md")" = "ORIGINAL" ] \
  || fail "5a: the colliding file's bytes were modified"
[ -f "$o/entries/2026-07-09-dupe-feedface.md" ] \
  || fail "5a: the retry did not land under the fresh UID"

# 5b. UID colliding only with an *archived* fragment forces the retry.
o=$(new_obs "$tmp/o5b")
printf 'ARCHIVED\n' >"$o/archive/2026-01-01-old-deadbeef.md"
make_od_stub "$tmp/od5b" deadbeef feedface
PATH="$tmp/od5b:$PATH" "$REC" --obs-dir "$o" --slug new --scope planwright \
  --text 'x' --today 2026-07-09 >/dev/null \
  || fail "5b: an archived-UID collision should retry, not fail"
[ -f "$o/entries/2026-07-09-new-feedface.md" ] \
  || fail "5b: retry did not avoid the archived UID"
[ ! -f "$o/entries/2026-07-09-new-deadbeef.md" ] \
  || fail "5b: the archived UID was re-minted into entries/"

# 5c. Same-directory collision under a *different slug* forces the retry
# (the check keys on the UID, not the full filename).
o=$(new_obs "$tmp/o5c")
printf 'OTHER\n' >"$o/entries/2026-07-09-otherslug-deadbeef.md"
make_od_stub "$tmp/od5c" deadbeef feedface
PATH="$tmp/od5c:$PATH" "$REC" --obs-dir "$o" --slug myslug --scope planwright \
  --text 'x' --today 2026-07-09 >/dev/null \
  || fail "5c: a different-slug same-UID collision should retry"
[ -f "$o/entries/2026-07-09-myslug-feedface.md" ] \
  || fail "5c: retry did not land under the fresh UID"
[ ! -f "$o/entries/2026-07-09-myslug-deadbeef.md" ] \
  || fail "5c: the colliding UID was reused under a new slug"
echo "ok 5: collision retry keys on the UID across entries/ and archive/"

# --- 6. Bounded retry exhaustion / exclusive publish ---------------------

o=$(new_obs "$tmp/o6")
printf 'KEEP\n' >"$o/entries/2026-07-09-x-abadcafe.md"
make_od_stub "$tmp/od6" abadcafe
_rc=0
PATH="$tmp/od6:$PATH" "$REC" --obs-dir "$o" --slug x --scope planwright \
  --text 'x' --today 2026-07-09 >/dev/null 2>&1 || _rc=$?
[ "$_rc" -eq 3 ] || fail "6: constant-collision exhaustion expected exit 3, got $_rc"
[ "$(cat "$o/entries/2026-07-09-x-abadcafe.md")" = "KEEP" ] \
  || fail "6: the exclusive publish replaced an existing destination"
[ "$(frag_count "$o/entries")" -eq 1 ] \
  || fail "6: exhaustion left a stray fragment"
# No temp residue under entries/ (no dot-file left behind).
resid=$(find "$o/entries" -type f ! -name '*.md' | head -1 || true)
[ -z "$resid" ] || fail "6: temp residue left under entries/: $resid"
echo "ok 6: bounded retry exhausts cleanly; the publish never overwrites"

# --- 7. Entry-content refusal (newlines / control chars) -----------------

o=$(new_obs "$tmp/o7")
nl='line one
line two'
# Assert the exact content-refusal code (1), not merely non-zero: a regression
# exiting 2/3/4 or crashing under set -e must not pass as a content refusal.
_rc=0
"$REC" --obs-dir "$o" --slug c --scope planwright --text "$nl" \
  --today 2026-07-09 >/dev/null 2>&1 || _rc=$?
[ "$_rc" -eq 1 ] || fail "7: newline text expected exit 1 (content refusal), got $_rc"
[ "$(frag_count "$o/entries")" -eq 0 ] || fail "7: newline text created a path"
ctl=$(printf 'bell\007here')
_rc=0
"$REC" --obs-dir "$o" --slug c --scope planwright --text "$ctl" \
  --today 2026-07-09 >/dev/null 2>&1 || _rc=$?
[ "$_rc" -eq 1 ] || fail "7: control-char text expected exit 1 (content refusal), got $_rc"
[ "$(frag_count "$o/entries")" -eq 0 ] || fail "7: control-char text created a path"
# C1 bytes (0x80-0x9F) are the continuation bytes of legitimate UTF-8 prose
# (here an em-dash, 0xE2 0x80 0x94); the content filter refuses only C0 + DEL,
# so such prose is ACCEPTED and writes exactly one fragment (header contract).
oc=$(new_obs "$tmp/o7c")
emdash=$(printf 'before \342\200\224 after')
"$REC" --obs-dir "$oc" --slug c --scope planwright --text "$emdash" \
  --today 2026-07-09 >/dev/null || fail "7: UTF-8 em-dash prose must be accepted"
[ "$(frag_count "$oc/entries")" -eq 1 ] \
  || fail "7: accepted C1/UTF-8 text must write exactly one fragment"
echo "ok 7: C0/DEL text refused (exit 1); legitimate C1/UTF-8 prose accepted"

# --- 8. Atomic exclusive publish: no torn fragment, no residue -----------

# A stubbed `ln` that always fails simulates a failure between temp-write and
# publish. The destination never appears, so the helper classifies this as a
# filesystem failure (exit 1), not a collision exhaustion, and leaves no
# fragment and no temp residue under entries/.
o=$(new_obs "$tmp/o8")
lnstub="$tmp/lnstub"
mkdir -p "$lnstub"
printf '#!/bin/sh\nexit 1\n' >"$lnstub/ln"
chmod +x "$lnstub/ln"
_rc=0
PATH="$lnstub:$PATH" "$REC" --obs-dir "$o" --slug t --scope planwright \
  --text 'x' --today 2026-07-09 >/dev/null 2>&1 || _rc=$?
[ "$_rc" -eq 1 ] || fail "8: a broken publish expected exit 1 (fs error), got $_rc"
[ "$(frag_count "$o/entries")" -eq 0 ] || fail "8: a torn fragment was left behind"
resid=$(find "$o/entries" -type f | head -1 || true)
[ -z "$resid" ] || fail "8: temp residue left under entries/: $resid"
echo "ok 8: a broken publish exits fs-error (1) with no fragment and no residue"

# --- 8b. ln fails because the destination now exists -> retry, not fs-error --

# The publish distinguishes two ln failures: dest absent = filesystem failure
# (exit 1, section 8); dest present = a racing writer won the name, so retry
# with a fresh UID. Section 8 covers only the absent arm. A stateful ln stub
# fails its first call while creating the destination (simulating the race),
# then really links on its second call, driving the retry-to-success arm.
o=$(new_obs "$tmp/o8b")
lnstub2="$tmp/lnstub2"
mkdir -p "$lnstub2"
cat >"$lnstub2/ln" <<EOF
#!/bin/sh
# First call: simulate a racing writer that already created dest (\$2), then
# fail without -f. Later calls: perform the real link via an absolute path.
if [ -f "$lnstub2/called" ]; then
  exec "$REAL_LN" "\$@"
fi
: >"$lnstub2/called"
: >"\$2"
exit 1
EOF
chmod +x "$lnstub2/ln"
make_od_stub "$tmp/od8b" c0ffee11 c0ffee22
PATH="$lnstub2:$tmp/od8b:$PATH" "$REC" --obs-dir "$o" --slug race \
  --scope planwright --text 'x' --today 2026-07-09 >/dev/null \
  || fail "8b: a dest-exists ln failure must retry to success, not refuse"
[ -f "$o/entries/2026-07-09-race-c0ffee22.md" ] \
  || fail "8b: the retry did not land on the fresh UID"
echo "ok 8b: a dest-exists publish failure retries with a fresh UID"

# --- 8c. A fatal signal terminates the publish loop, it does not resume ---

# A cleanup-only INT/TERM trap runs its handler and then *resumes* the
# interrupted shell (a trapped signal does not itself exit in POSIX sh), so a
# Ctrl-C mid-publish would silently carry on. The helper instead re-`exit`s on
# INT/TERM (re-entering the EXIT cleanup). Assert the process ends on the TERM
# signal code (143), not a resumed clean exit (0). The `ln` stub blocks in the
# main control flow — not inside a command substitution, where the interruption
# point is masked by subshell teardown and cannot tell resume from exit.
o=$(new_obs "$tmp/o8c")
sigbin="$tmp/sigbin"
mkdir -p "$sigbin"
printf '#!/bin/sh\nprintf deadbeef\n' >"$sigbin/od"
chmod +x "$sigbin/od"
cat >"$sigbin/ln" <<EOF
#!/bin/sh
sleep 1
exec "$REAL_LN" "\$@"
EOF
chmod +x "$sigbin/ln"
PATH="$sigbin:$PATH" "$REC" --obs-dir "$o" --slug sig --scope planwright \
  --text 'x' --today 2026-07-09 >/dev/null 2>&1 &
_sigpid=$!
sleep 0.3
kill -TERM "$_sigpid" 2>/dev/null || true
_sigrc=0
wait "$_sigpid" || _sigrc=$?
[ "$_sigrc" -eq 143 ] \
  || fail "8c: TERM mid-publish expected exit 143 (signal), got $_sigrc (resumed?)"
echo "ok 8c: a fatal signal terminates the publish loop instead of resuming"

# --- 9. Concurrent adds never conflict -----------------------------------

repo="$tmp/repo9"
mkdir -p "$repo"
gitc "$repo" init -q
o="$repo/specs/_observations"
mkdir -p "$o/entries" "$o/archive"
printf '# base\n' >"$repo/README.md"
gitc "$repo" add -A
gitc "$repo" commit -q -m base
# Branch b1 records with a deterministic UID.
gitc "$repo" checkout -q -b b1
make_od_stub "$tmp/od9a" aaaa1111
PATH="$tmp/od9a:$PATH" "$REC" --obs-dir "$o" --slug shared --scope planwright \
  --text 'from b1' --today 2026-07-09 >/dev/null || fail "9: b1 record failed"
gitc "$repo" add -A
gitc "$repo" commit -q -m b1
# Branch b2 from the common base records the same day + slug, distinct UID.
gitc "$repo" checkout -q main
gitc "$repo" checkout -q -b b2
make_od_stub "$tmp/od9b" bbbb2222
PATH="$tmp/od9b:$PATH" "$REC" --obs-dir "$o" --slug shared --scope planwright \
  --text 'from b2' --today 2026-07-09 >/dev/null || fail "9: b2 record failed"
gitc "$repo" add -A
gitc "$repo" commit -q -m b2
# Merge b2 into b1: distinct filenames merge with no conflict.
gitc "$repo" checkout -q b1
gitc "$repo" merge -q --no-edit b2 || fail "9: concurrent adds produced a merge conflict"
[ -f "$o/entries/2026-07-09-shared-aaaa1111.md" ] || fail "9: b1 fragment missing after merge"
[ -f "$o/entries/2026-07-09-shared-bbbb2222.md" ] || fail "9: b2 fragment missing after merge"
echo "ok 9: concurrent same-day same-slug adds merge without conflict"

# --- 10. Validate / contain / refuse -------------------------------------

o=$(new_obs "$tmp/o10")
hostile() {
  # hostile <label> <sensitive-value> <extra-args...> — a clean refusal
  # (exit 1) that writes no path and whose message carries neither raw control
  # bytes nor the untrusted value echoed verbatim (the echo-discipline bar).
  _label=$1
  _val=$2
  shift 2
  _err="$tmp/err10"
  _rc=0
  "$REC" --obs-dir "$o" --scope planwright --text 'x' "$@" \
    >/dev/null 2>"$_err" || _rc=$?
  [ "$_rc" -eq 1 ] || fail "10: $_label expected exit 1, got $_rc"
  [ "$(frag_count "$o/entries")" -eq 0 ] || fail "10: $_label created a path"
  # No raw control bytes in the message.
  clean=$(tr -d '\000-\010\013\014\016-\037\177' <"$_err")
  [ "$clean" = "$(cat "$_err")" ] || fail "10: $_label emitted raw control bytes"
  # No verbatim echo of the untrusted value (catches a message that pastes the
  # raw slug/date back — printable input the control-byte check cannot see).
  if [ -n "$_val" ] && grep -qF -- "$_val" "$_err"; then
    fail "10: $_label echoed the raw untrusted value into its message"
  fi
}
hostile "traversal slug" "../evil" --slug ../evil --today 2026-07-09
hostile "absolute-path slug" "/etc/passwd" --slug /etc/passwd --today 2026-07-09
hostile "traversal date" "../../etc" --slug ok --today ../../etc
ctlslug=$(printf 'ev\011il')
hostile "control-char slug" "$ctlslug" --slug "$ctlslug" --today 2026-07-09

# Locale-dependent uppercase: under a UTF-8 locale the slug charset check must
# still reject an uppercase byte (asserting the helper pins LC_ALL=C). This
# guard is load-bearing only where collation is locale-sensitive (BSD/macOS);
# skip with a notice when the UTF-8 locale is absent so a C-fallback pass is
# never mistaken for proof of the pin.
if locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then
  _rc=0
  LC_ALL=en_US.UTF-8 LC_CTYPE=en_US.UTF-8 "$REC" --obs-dir "$o" --slug BADCASE \
    --scope planwright --text 'x' --today 2026-07-09 >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 1 ] \
    || fail "10: uppercase slug accepted under a UTF-8 locale (LC_ALL=C not pinned)"
  [ "$(frag_count "$o/entries")" -eq 0 ] || fail "10: uppercase-locale slug created a path"
else
  echo "note 10: en_US.UTF-8 unavailable; skipping the locale-pin assertion"
fi

# Direct containment unit: entries/ is a symlink escaping to an *existing*
# dir. A grammar-valid slug must still be refused, and no fragment lands in
# the escape target.
oc="$tmp/o10c"
escape="$tmp/escape10c"
mkdir -p "$oc" "$escape"
ln -s "$escape" "$oc/entries"
_rc=0
"$REC" --obs-dir "$oc" --slug ok --scope planwright --text 'x' \
  --today 2026-07-09 >/dev/null 2>&1 || _rc=$?
[ "$_rc" -eq 1 ] || fail "10: an escaping entries/ symlink expected exit 1, got $_rc"
[ "$(frag_count "$escape")" -eq 0 ] \
  || fail "10: a fragment escaped into the symlink target"

# entries/ a symlink to a *non-existent* target: refuse, create no fragment,
# and never materialize the escape target as a side effect (validate/contain
# runs before any mkdir).
od2="$tmp/o10d"
esc2="$tmp/escape10d-target"
mkdir -p "$od2"
ln -s "$esc2" "$od2/entries"
_rc=0
"$REC" --obs-dir "$od2" --slug ok --scope planwright --text 'x' \
  --today 2026-07-09 >/dev/null 2>&1 || _rc=$?
[ "$_rc" -eq 1 ] || fail "10: a dangling escaping entries/ symlink expected exit 1, got $_rc"
[ ! -e "$esc2" ] || fail "10: the escape target was materialized as a side effect"

# The observations root itself a symlink escaping to an *existing* dir: the
# obs-dir guard must refuse before canonicalization would resolve it to the
# target and root the store there, and no fragment lands in the escape target.
oe="$tmp/o10e"
escroot="$tmp/escape10e"
mkdir -p "$escroot"
ln -s "$escroot" "$oe"
_rc=0
"$REC" --obs-dir "$oe" --slug ok --scope planwright --text 'x' \
  --today 2026-07-09 >/dev/null 2>&1 || _rc=$?
[ "$_rc" -eq 1 ] || fail "10: a symlinked obs-dir root expected exit 1, got $_rc"
[ "$(frag_count "$escroot")" -eq 0 ] \
  || fail "10: a fragment escaped through the symlinked obs-dir root"

# Echo-discipline on the --obs-dir failure path: a mkdir that fails names the
# caller-supplied path on its own stderr, so the helper suppresses it (only the
# sanitized `refuse` message may reach the terminal). Force the failure with an
# obs-dir whose parent component is a regular file (mkdir -p: "Not a
# directory"); the marker in that component must not appear in stderr.
oleak="$tmp/o10f"
mkdir -p "$oleak"
: >"$oleak/LEAKMARKER"
_err="$tmp/err10f"
_rc=0
"$REC" --obs-dir "$oleak/LEAKMARKER/sub" --slug ok --scope planwright \
  --text 'x' --today 2026-07-09 >/dev/null 2>"$_err" || _rc=$?
[ "$_rc" -eq 1 ] || fail "10: an uncreatable obs-dir expected exit 1, got $_rc"
grep -qF 'LEAKMARKER' "$_err" \
  && fail "10: mkdir echoed the raw --obs-dir path into the terminal"
_clean=$(tr -d '\000-\010\013\014\016-\037\177' <"$_err")
[ "$_clean" = "$(cat "$_err")" ] || fail "10: obs-dir failure emitted raw control bytes"

# A hyphen-leading --obs-dir is refused before any mkdir/cd. A bare '-' makes
# `cd "$obsdir"` a `cd -` (switch to $OLDPWD), so the store would silently root
# outside the named directory (the fragment lands in $OLDPWD/entries while
# stdout still reports "-/entries/..."). A `--` terminator does not close this
# ('-' stays a special cd operand), so the helper refuses up front. Run in a
# subshell from a scratch cwd with OLDPWD set to a decoy: assert exit 1, that no
# '-' directory was created (the guard beat `mkdir -p`), and nothing escaped to
# $OLDPWD.
ohy="$tmp/o10hy"
mkdir -p "$ohy/cwd" "$ohy/oldpwd/entries"
_rc=0
(
  cd "$ohy/cwd" \
    && OLDPWD="$ohy/oldpwd" "$REC" --obs-dir - --slug ok --scope planwright \
      --text 'x' --today 2026-07-09 >/dev/null 2>&1
) || _rc=$?
[ "$_rc" -eq 1 ] || fail "10: a hyphen-leading --obs-dir expected exit 1, got $_rc"
[ ! -e "$ohy/cwd/-" ] || fail "10: a '-' directory was created (guard ran after mkdir)"
[ "$(frag_count "$ohy/oldpwd/entries")" -eq 0 ] \
  || fail "10: a fragment escaped to \$OLDPWD via cd -"

echo "ok 10: hostile input and containment escapes refuse cleanly (exit 1, no echo)"

# --- 11. Exit-code contract: usage errors, defaults, internal errors ------

o=$(new_obs "$tmp/o11")
usage_err() {
  # usage_err <label> <args...> — asserts an exit-2 usage error.
  _label=$1
  shift
  _rc=0
  "$REC" "$@" >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 2 ] || fail "11: $_label expected exit 2 (usage), got $_rc"
}
usage_err "missing --slug" --obs-dir "$o" --scope planwright --text x --today 2026-07-09
usage_err "missing --scope" --obs-dir "$o" --slug s --text x --today 2026-07-09
usage_err "missing --text" --obs-dir "$o" --slug s --scope planwright --today 2026-07-09
usage_err "unknown flag" --obs-dir "$o" --slug s --scope planwright --text x --bogus
usage_err "flag without value" --obs-dir "$o" --slug
usage_err "trailing token after --" --obs-dir "$o" --slug s --scope planwright \
  --text x --today 2026-07-09 -- extra
# Present-but-empty required flags: --slug/--scope carry the flag with an empty
# value, so the parse consumes them but the non-empty guard fails — a usage
# error (exit 2), distinct from the flag being absent above.
usage_err "empty --slug" --obs-dir "$o" --slug "" --scope planwright --text x --today 2026-07-09
usage_err "empty --scope" --obs-dir "$o" --slug s --scope "" --text x --today 2026-07-09
# Empty --text is a content refusal (exit 1), not a usage error: have_text is
# set, so the parse passes and the empty-text guard refuses at validation.
_rc=0
"$REC" --obs-dir "$o" --slug s --scope planwright --text "" --today 2026-07-09 \
  >/dev/null 2>&1 || _rc=$?
[ "$_rc" -eq 1 ] || fail "11: empty --text expected exit 1 (refusal), got $_rc"
[ "$(frag_count "$o/entries")" -eq 0 ] || fail "11: empty --text refusal created a path"

# Unusable obs-dir (a regular file): creating entries/ under it fails, a clean
# exit-1 filesystem refusal with no path.
notdir="$tmp/o11file"
: >"$notdir"
_rc=0
"$REC" --obs-dir "$notdir" --slug s --scope planwright --text x \
  --today 2026-07-09 >/dev/null 2>&1 || _rc=$?
[ "$_rc" -eq 1 ] || fail "11: an unusable obs-dir expected exit 1, got $_rc"

# Default-date path: with no --today the helper mints the system date. Bracket
# the invocation with two clock reads and accept either, so a midnight straddle
# between the helper's internal `date` and the test's cannot flake.
od=$(new_obs "$tmp/o11d")
d1=$(date +%F)
"$REC" --obs-dir "$od" --slug defdate --scope planwright --text 'x' \
  >/dev/null || fail "11: default-date invocation failed"
d2=$(date +%F)
defbase=$(basename "$(echo "$od"/entries/*.md)")
case "$defbase" in
  "$d1"-defdate-* | "$d2"-defdate-*) : ;;
  *) fail "11: default-date fragment [$defbase] lacks the system date ($d1/$d2)" ;;
esac

# -h/--help prints the usage synopsis and exits 0 — the sole exit-0 non-record
# path; a regression flipping it to a usage error (exit 2) would be invisible.
"$REC" --help >/dev/null 2>&1 || fail "11: --help must exit 0"
"$REC" -h >/dev/null 2>&1 || fail "11: -h must exit 0"
helpout=$("$REC" --help 2>&1 || true)
case "$helpout" in
  *"usage:"*) : ;;
  *) fail "11: --help must print the usage synopsis" ;;
esac
echo "ok 11: usage errors, unusable obs-dir, --help, and the default-date path are contract-correct"

echo "PASS: test-obs-record.sh"
