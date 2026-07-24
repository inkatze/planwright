#!/bin/sh
# Unit test for scripts/obs-consume.sh — the git-integration, usage-contract,
# and cross-guard cases (observation-recording Task 4, REQ-B1.2, REQ-C1.2;
# D-3, D-7). Consumption semantics are normative in
# specs/observation-recording/{requirements,design}.md.
#
# Split out of tests/test-obs-consume.sh (guard-coverage Task 6, REQ-E1.2,
# D-9): that file was a wall-clock straggler, so its three cohesive arms now
# run as three files. The fragment arm lives in tests/test-obs-consume.sh and
# the frozen-log arm in tests/test-obs-consume-legacy.sh; the assertions here
# are unchanged from the pre-split file.
#
# Properties verified (numbered to match the body's check sections, which keep
# the original file's numbering so the spec's section references still land):
#  13. Two-branch conflict-freedom (REQ-B1.2): one branch adds a fragment, another
#      consumes a *different* fragment — git merge is clean, the consumed fragment
#      exists only in archive/ (same filename), and the consume commit touched no
#      unrelated file; a same-fragment double-consume produces a conflict confined
#      to that one fragment.
#  14. Usage / exit-code contract: missing/empty required flags, an unknown flag,
#      a flag without its value, arm-mismatch (--uid with --legacy, --legacy
#      without --line), and a trailing token exit 2; -h/--help exits 0.
#  15. Cross-guard contract: the annotation obs-consume writes satisfies the
#      metadata whitelist check-obs.sh enforces, so a consumed/archived fragment
#      never fails CI, and no `.obs-consume.*` temp residue survives.
#
# Exit codes asserted throughout: 2 usage — plus the clean exits the merge and
# guard round-trips require — per the header contract of scripts/obs-consume.sh.
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

# gitc <repo> <args...> — git with fixture identity, no signing, main default.
gitc() {
  _r=$1
  shift
  git -C "$_r" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# --- 13. Two-branch conflict-freedom -------------------------------------

repo="$tmp/repo13"
mkdir -p "$repo"
gitc "$repo" init -q
o="$repo/specs/_observations"
mkdir -p "$o/entries" "$o/archive"
# Two live fragments on the base commit.
fa=$(record "$o" 1111aaaa alpha 'fragment A')
fb=$(record "$o" 2222bbbb beta 'fragment B')
printf '# base\n' >"$repo/README.md"
gitc "$repo" add -A
gitc "$repo" commit -q -m base

# Branch b1 adds a *new* fragment.
gitc "$repo" checkout -q -b b1
fc=$(record "$o" 3333cccc gamma 'fragment C added on b1')
gitc "$repo" add -A
gitc "$repo" commit -q -m add-C

# Branch b2 (from base) consumes a *different* fragment (A).
gitc "$repo" checkout -q main
gitc "$repo" checkout -q -b b2
"$CONSUME" --obs-dir "$o" --uid 1111aaaa --spec my-spec --today 2026-07-10 \
  || fail "13: consume on b2 failed"
gitc "$repo" add -A
gitc "$repo" commit -q -m consume-A
# The consume commit touched only fragment A's two paths, nothing unrelated.
changed=$(gitc "$repo" show --name-only --pretty=format: HEAD | sed '/^$/d' | sort)
expected=$(printf '%s\n%s\n' \
  "specs/_observations/archive/$fa" "specs/_observations/entries/$fa" | sort)
[ "$changed" = "$expected" ] \
  || fail "13: consume commit touched unexpected files:
$changed"

# Merge b2 into b1: add-vs-consume-different-fragment merges clean.
gitc "$repo" checkout -q b1
gitc "$repo" merge -q --no-edit b2 \
  || fail "13: add + consume-different merged with a conflict"
[ -f "$o/archive/$fa" ] || fail "13: consumed A missing from archive/ after merge"
[ ! -e "$o/entries/$fa" ] || fail "13: consumed A still in entries/ after merge"
[ -f "$o/entries/$fb" ] || fail "13: untouched B missing after merge"
[ -f "$o/entries/$fc" ] || fail "13: added C missing after merge"
echo "ok 13a: add + consume-different-fragment merges clean"

# Same-fragment double-consume: both branches consume B → conflict on that one.
repo="$tmp/repo13b"
mkdir -p "$repo"
gitc "$repo" init -q
o="$repo/specs/_observations"
mkdir -p "$o/entries" "$o/archive"
fb=$(record "$o" 4444dddd beta 'contested fragment')
gitc "$repo" add -A
gitc "$repo" commit -q -m base
gitc "$repo" checkout -q -b c1
"$CONSUME" --obs-dir "$o" --uid 4444dddd --spec spec-one --today 2026-07-10 >/dev/null
gitc "$repo" add -A
gitc "$repo" commit -q -m consume-c1
gitc "$repo" checkout -q main
gitc "$repo" checkout -q -b c2
"$CONSUME" --obs-dir "$o" --uid 4444dddd --spec spec-two --today 2026-07-11 >/dev/null
gitc "$repo" add -A
gitc "$repo" commit -q -m consume-c2
gitc "$repo" checkout -q c1
rc=0
gitc "$repo" merge -q --no-edit c2 >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "13b: same-fragment double-consume merged without conflict"
# The conflict is confined to that one fragment: every conflicted path must be
# that fragment's, and there must be at least one (REQ-B1.2 "confined to that
# one fragment").
conflicted=$(gitc "$repo" diff --name-only --diff-filter=U | sort)
[ -n "$conflicted" ] || fail "13b: no conflicted path reported"
outside=$(printf '%s\n' "$conflicted" | grep -v "/$fb\$" || :)
[ -z "$outside" ] \
  || fail "13b: conflict not confined to the contested fragment; also: $outside"
gitc "$repo" merge --abort 2>/dev/null || :
echo "ok 13b: same-fragment double-consume conflicts on that one fragment only"

# --- 14. Usage / exit-code contract --------------------------------------

o=$(new_obs "$tmp/o14")

usage_err() {
  _label=$1
  shift
  _rc=0
  "$CONSUME" "$@" >/dev/null 2>&1 && fail "14: [$_label] expected exit 2" || _rc=$?
  [ "$_rc" -eq 2 ] || fail "14: [$_label] expected exit 2, got $_rc"
}
usage_err "no args"
usage_err "uid without spec" --obs-dir "$o" --uid aaaa1111
usage_err "spec without arm" --obs-dir "$o" --spec my-spec
usage_err "uid missing value" --obs-dir "$o" --uid --spec my-spec
usage_err "spec missing value" --obs-dir "$o" --uid aaaa1111 --spec
usage_err "unknown flag" --obs-dir "$o" --uid aaaa1111 --spec my-spec --bogus
usage_err "trailing token" --obs-dir "$o" --uid aaaa1111 --spec my-spec extra
usage_err "uid with legacy" --obs-dir "$o" --legacy --uid aaaa1111 --spec my-spec --line x
usage_err "legacy without line" --obs-dir "$o" --legacy --spec my-spec
usage_err "line without legacy" --obs-dir "$o" --line x --spec my-spec

"$CONSUME" -h >/dev/null 2>&1 || fail "14: -h must exit 0"
"$CONSUME" --help >/dev/null 2>&1 || fail "14: --help must exit 0"
echo "ok 14: usage / exit-code contract holds"

# --- 15. A consumed fragment passes the check:obs CI guard ----------------
# Cross-script contract: the annotation obs-consume writes must satisfy the
# metadata whitelist check-obs.sh enforces, so a consumed/archived fragment
# never fails CI. Also asserts no `.obs-consume.*` temp residue is left behind
# (the cleanup trap).

GUARD="$here/../scripts/check-obs.sh"
if [ -x "$GUARD" ]; then
  o=$(new_obs "$tmp/o15")
  # The recorded basename went unused even pre-split; the call is here for its
  # side effect (a live fragment for the consume below).
  record "$o" ba5eba11 topic 'guard me' >/dev/null
  "$CONSUME" --obs-dir "$o" --uid ba5eba11 --spec my-spec --today 2026-07-10 \
    || fail "15: consume exited non-zero"
  # Seed a consumed legacy line too, so the guard sees both frozen files present.
  printf '%s\n' '# frozen' '' '- 2026-06-10 [planwright] legacy line' \
    >"$o/opportunities.md"
  : >"$o/archive.md"
  "$CONSUME" --obs-dir "$o" --legacy --line '- 2026-06-10 [planwright] legacy line' \
    --spec my-spec --today 2026-07-10 || fail "15: legacy consume exited non-zero"
  /bin/bash "$GUARD" --obs-dir "$o" \
    || fail "15: check-obs rejected a consumed/archived fragment (format drift)"
  # No temp residue anywhere under the observations dir.
  resid=$(find "$o" -name '.obs-consume.*' 2>/dev/null)
  [ -z "$resid" ] || fail "15: obs-consume left a temp file: $resid"
  echo "ok 15: a consumed fragment passes check:obs; no temp residue"
else
  echo "note 15: scripts/check-obs.sh absent; skipping the cross-guard check"
fi

echo "PASS: all obs-consume git/usage/cross-guard checks"
