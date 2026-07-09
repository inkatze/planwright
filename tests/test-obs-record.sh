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
#   3. Filename-grammar acceptance/rejection for every component (REQ-A1.2):
#      malformed date shape, well-shaped non-calendar date (2026-02-30),
#      uppercase slug, underscore slug, overlong slug (>40) all refuse; a
#      valid name passes.
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
#      control character is refused at write time, no path created.
#   8. Atomic exclusive publish (REQ-A1.6): a simulated failure between
#      temp-write and publish leaves no fragment and no temp residue under
#      entries/ (no reader ever sees a torn fragment).
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
#      materialized as a side effect).
#  11. Exit-code contract (REQ-A1.6, D-6): missing required flags, an unknown
#      flag, a flag without its value, and a trailing token all exit 2
#      (usage); an unusable observations dir exits 1; the default-date path
#      (no --today) mints the system date into the fragment name.
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
extra=$(comm -13 "$tmp/before1" "$tmp/after1" | grep -v "^$frag$" || true)
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
# A 40-char slug is accepted (boundary).
ok40=$(printf 'a%.0s' $(seq 1 40))
"$REC" --obs-dir "$o" --slug "$ok40" --scope planwright --text 'x' \
  --today 2026-07-09 >/dev/null || fail "3: a 40-char slug must be accepted"
echo "ok 3: composite-grammar rejections refuse and write no path"

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
if "$REC" --obs-dir "$o" --slug c --scope planwright --text "$nl" \
  --today 2026-07-09 >/dev/null 2>&1; then
  fail "7: entry text with a newline must be refused"
fi
[ "$(frag_count "$o/entries")" -eq 0 ] || fail "7: newline text created a path"
ctl=$(printf 'bell\007here')
if "$REC" --obs-dir "$o" --slug c --scope planwright --text "$ctl" \
  --today 2026-07-09 >/dev/null 2>&1; then
  fail "7: entry text with a control character must be refused"
fi
[ "$(frag_count "$o/entries")" -eq 0 ] || fail "7: control-char text created a path"
echo "ok 7: entry text with newlines or control chars is refused at write time"

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
echo "ok 11: usage errors, unusable obs-dir, and the default-date path are contract-correct"

echo "PASS: test-obs-record.sh"
