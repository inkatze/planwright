#!/bin/bash
# Tests for scripts/flight-id.sh — the flight-id grammar and the never-reuse
# rule (tower-front-door Task 3; REQ-C1.1 · D-11).
#
# A flight id is `<slug>-<uid>`: a kebab slug in the spec-identifier charset
# plus an eight-character lowercase-hex uid, at most 64 characters in all. The
# derived names are the flight branch `planwright/flight/<flight-id>` and the
# worktree suffix `flight-<flight-id>`.
#
# Properties verified:
#   1. `check` accepts exactly the grammar and refuses everything else with
#      exit 1, never echoing the candidate back.
#   2. `new <slug>` mints a grammar-valid id from the slug and refuses an
#      off-grammar or over-long slug (exit 2) without minting.
#   3. Never-reuse: `new` skips a uid whose id already has durable evidence —
#      a local flight branch, a remote-tracking flight branch, a record file in
#      the working tree or on main, or a placed worktree — and `taken` names
#      the evidence class. Exhausting every candidate is exit 3 with nothing
#      on stdout.
#   4. Two ids minted from the default (random) source differ.
#   5. `branch` and `suffix` derive the names from a checked id only.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

here=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$here/../scripts/flight-id.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SCRIPT" ] || fail "scripts/flight-id.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

gitc() {
  _r=$1
  shift
  git -C "$_r" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# run <expected-rc> <args...> — sets OUT (stdout) and ERR (stderr).
run() {
  expect=$1
  shift
  rc=0
  OUT=$("$SCRIPT" "$@" 2>"$tmp/err") || rc=$?
  ERR=$(cat "$tmp/err")
  [ "$rc" -eq "$expect" ] \
    || fail "expected exit $expect, got $rc for: $* — stdout: $OUT — stderr: $ERR"
}

# 1. The grammar, full-string.
run 0 check demo-0123abcd
run 0 check a-00000000
run 0 check two-words-ffffffff
long_slug=$(printf 'a%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 \
  21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 \
  46 47 48 49 50 51 52 53 54 55)
run 0 check "$long_slug-0123abcd"
for bad in \
  demo \
  demo- \
  -0123abcd \
  demo-0123ABCD \
  Demo-0123abcd \
  demo-0123abc \
  demo-0123abcd9 \
  demo-0123abcg \
  -x-0123abcd \
  'demo/../x-0123abcd' \
  'demo 0123abcd' \
  'demo_x-0123abcd' \
  "${long_slug}a-0123abcd" \
  ''; do
  run 1 check "$bad"
  case $OUT$ERR in
    *"$bad"*) [ -z "$bad" ] || fail "check echoed the refused candidate back: $bad" ;;
  esac
done
run 1 check "$(printf 'demo-0123abcd\nrm -rf x')"
echo "ok: check accepts the flight-id grammar and refuses the rest without echoing"

# 2. new mints from a slug; off-grammar slugs are refused without minting.
printf '0123abcd\n' >"$tmp/uids"
export PLANWRIGHT_FLIGHT_UID_SOURCE="$tmp/uids"
repo=$tmp/repo
git -c init.defaultBranch=main init -q "$repo"
gitc "$repo" commit -q --allow-empty -m init
run 0 new demo --repo-root "$repo"
[ "$OUT" = demo-0123abcd ] || fail "new: expected demo-0123abcd, got [$OUT]"
run 0 check "$OUT"
for bad in Demo 'de mo' 'de/mo' '' -demo "${long_slug}a"; do
  run 2 new "$bad" --repo-root "$repo"
  [ -z "$OUT" ] || fail "new refused slug [$bad] but still printed [$OUT]"
done
echo "ok: new mints <slug>-<uid> and refuses an off-grammar slug"

# 3. Never-reuse against durable evidence.
printf '0123abcd\n89abcdef\nfedcba98\n' >"$tmp/uids"
origin=$tmp/origin.git
git -c init.defaultBranch=main init -q --bare "$origin"
gitc "$repo" remote add origin "$origin"
gitc "$repo" push -q origin main

# 3a. A local flight branch takes its id.
gitc "$repo" branch planwright/flight/demo-0123abcd
run 0 new demo --repo-root "$repo"
[ "$OUT" = demo-89abcdef ] || fail "never-reuse (local branch): expected demo-89abcdef, got [$OUT]"
run 0 taken demo-0123abcd --repo-root "$repo"
case $OUT in
  *"branch"*"refs/heads/planwright/flight/demo-0123abcd"*) ;;
  *) fail "taken (local branch): evidence not named, got [$OUT]" ;;
esac
run 1 taken demo-89abcdef --repo-root "$repo"
[ -z "$OUT" ] || fail "taken on a free id printed evidence: [$OUT]"

# 3b. A remote-tracking flight branch alone (local deleted) still takes it.
gitc "$repo" push -q origin planwright/flight/demo-0123abcd
gitc "$repo" branch -D -q planwright/flight/demo-0123abcd
run 0 taken demo-0123abcd --repo-root "$repo"
case $OUT in
  *"branch"*"refs/remotes/origin/planwright/flight/demo-0123abcd"*) ;;
  *) fail "taken (remote-tracking branch): evidence not named, got [$OUT]" ;;
esac
run 0 new demo --repo-root "$repo"
[ "$OUT" = demo-89abcdef ] || fail "never-reuse (remote-tracking): expected demo-89abcdef, got [$OUT]"

# 3c. A record file in the working tree takes its id.
mkdir -p "$repo/specs/_flights"
: >"$repo/specs/_flights/demo-89abcdef.md"
run 0 taken demo-89abcdef --repo-root "$repo"
case $OUT in
  *"record"*"specs/_flights/demo-89abcdef.md"*) ;;
  *) fail "taken (working-tree record): evidence not named, got [$OUT]" ;;
esac
run 0 new demo --repo-root "$repo"
[ "$OUT" = demo-fedcba98 ] || fail "never-reuse (record file): expected demo-fedcba98, got [$OUT]"

# 3d. A record file committed on main is evidence from a checkout that lacks
#     it (a flight branch cut before the record merged).
gitc "$repo" add specs/_flights/demo-89abcdef.md
gitc "$repo" commit -q -m "record"
gitc "$repo" push -q origin main
wt=$tmp/wt
gitc "$repo" worktree add -q "$wt" -b other "$(gitc "$repo" rev-parse main~1)"
[ ! -e "$wt/specs/_flights/demo-89abcdef.md" ] || fail "fixture: the worktree should lack the record"
run 0 taken demo-89abcdef --repo-root "$wt"
case $OUT in
  *"record"*"main:specs/_flights/demo-89abcdef.md"*) ;;
  *) fail "taken (record on main): evidence not named, got [$OUT]" ;;
esac

# 3d'. A record merged only on the remote's default branch (local main behind)
#      is evidence, and the local copy is not misreported.
clone2=$tmp/clone2
git clone -q "$origin" "$clone2" 2>/dev/null
mkdir -p "$clone2/specs/_flights"
: >"$clone2/specs/_flights/demo-0badf00d.md"
gitc "$clone2" add -A
gitc "$clone2" commit -q -m "remote record"
gitc "$clone2" push -q origin main
gitc "$repo" fetch -q origin
run 0 taken demo-0badf00d --repo-root "$repo"
printf '%s' "$OUT" | grep -q "^evidence	record	origin/main:specs/_flights/demo-0badf00d.md$" \
  || fail "taken (record on origin/main only): evidence not named, got [$OUT]"
printf '%s' "$OUT" | grep -q "^evidence	record	main:" \
  && fail "taken (record on origin/main only): local main misreported, got [$OUT]"

# 3d''. A default branch that is not called main is still consulted, through
#       the remote's HEAD.
gitc "$clone2" branch -m main trunk
gitc "$clone2" push -q origin trunk
git -C "$origin" symbolic-ref HEAD refs/heads/trunk
gitc "$repo" fetch -q origin
gitc "$repo" remote set-head origin -a >/dev/null 2>&1
gitc "$repo" push -q origin :main
gitc "$repo" fetch -q --prune origin
gitc "$repo" branch -m main not-main
run 0 taken demo-0badf00d --repo-root "$repo"
printf '%s' "$OUT" | grep -q "^evidence	record	origin/trunk:specs/_flights/demo-0badf00d.md$" \
  || fail "taken (record on origin/trunk via origin/HEAD): evidence not named, got [$OUT]"
gitc "$repo" branch -m not-main main
gitc "$repo" push -q origin main
git -C "$origin" symbolic-ref HEAD refs/heads/main
gitc "$repo" remote set-head origin -a >/dev/null 2>&1
gitc "$repo" push -q origin :trunk
gitc "$repo" fetch -q --prune origin

# 3e. A placed worktree takes its id even with no branch and no record.
mkdir -p "$repo/.claude/worktrees/flight-demo-fedcba98"
run 0 taken demo-fedcba98 --repo-root "$repo"
case $OUT in
  *"worktree"*"flight-demo-fedcba98"*) ;;
  *) fail "taken (worktree dir): evidence not named, got [$OUT]" ;;
esac

# 3e'. A dangling symlink at a record or worktree path still occupies the id.
ln -s /nonexistent-target "$repo/specs/_flights/demo-0123abcd.md"
run 0 taken demo-0123abcd --repo-root "$repo"
case $OUT in
  *"record"*"specs/_flights/demo-0123abcd.md"*) ;;
  *) fail "taken (dangling record symlink): evidence not named, got [$OUT]" ;;
esac
rm "$repo/specs/_flights/demo-0123abcd.md"
ln -s /nonexistent-target "$repo/.claude/worktrees/flight-demo-0123abcd"
run 0 taken demo-0123abcd --repo-root "$repo"
case $OUT in
  *"worktree"*"flight-demo-0123abcd"*) ;;
  *) fail "taken (dangling worktree symlink): evidence not named, got [$OUT]" ;;
esac
rm "$repo/.claude/worktrees/flight-demo-0123abcd"

# 3e''. --repo-root names a subdirectory: the working-tree record is still
#       found from the work-tree top. A bare repository is refused.
run 0 taken demo-89abcdef --repo-root "$repo/specs"
case $OUT in
  *"record"*"specs/_flights/demo-89abcdef.md"*) ;;
  *) fail "taken (subdirectory --repo-root): record not found, got [$OUT]" ;;
esac
run 2 taken demo-89abcdef --repo-root "$origin"
[ -z "$OUT" ] || fail "a bare --repo-root printed [$OUT]"
run 2 new demo --repo-root "$origin"
[ -z "$OUT" ] || fail "a bare --repo-root minted [$OUT]"

# 3f. Every candidate taken: exit 3, nothing minted.
run 3 new demo --repo-root "$repo"
[ -z "$OUT" ] || fail "exhausted candidates still printed [$OUT]"
echo "ok: never-reuse holds against branches, record files, and worktrees"

# 3f'. A git failure during the probe is never "no evidence": the id is not
#      judged (exit 5) and nothing is minted over a branch the probe could not
#      read.
gitc "$repo" branch planwright/flight/demo-0123abcd
gitc "$repo" pack-refs --all
chmod 000 "$repo/.git/packed-refs"
if [ -r "$repo/.git/packed-refs" ]; then
  echo "skip: packed-refs stays readable here (root?), the probe-failure case is not exercised" >&2
else
  run 5 taken demo-0123abcd --repo-root "$repo"
  [ -z "$OUT" ] || fail "probe failure still printed evidence: [$OUT]"
  printf '0123abcd\n' >"$tmp/uids"
  run 5 new demo --repo-root "$repo"
  [ -z "$OUT" ] || fail "probe failure still minted [$OUT]"
fi
chmod 644 "$repo/.git/packed-refs"
gitc "$repo" branch -D -q planwright/flight/demo-0123abcd
printf '0123abcd\n89abcdef\nfedcba98\n' >"$tmp/uids"
echo "ok: a git error in the evidence probe fails closed"

# 3g. A different slug with the same uid is a different id: not taken.
run 0 new other --repo-root "$repo"
[ "$OUT" = other-0123abcd ] || fail "slug isolation: expected other-0123abcd, got [$OUT]"
echo "ok: evidence is keyed by the whole id, not the uid alone"

# 4. The default source mints distinct, grammar-valid ids.
unset PLANWRIGHT_FLIGHT_UID_SOURCE
run 0 new demo --repo-root "$repo"
first=$OUT
run 0 check "$first"
run 0 new demo --repo-root "$repo"
[ "$first" != "$OUT" ] || fail "two random mints collided: $first"
run 0 check "$OUT"
echo "ok: the default uid source mints distinct grammar-valid ids"

# 5. Derived names come only from a checked id.
run 0 branch demo-0123abcd
[ "$OUT" = planwright/flight/demo-0123abcd ] || fail "branch: got [$OUT]"
run 0 suffix demo-0123abcd
[ "$OUT" = flight-demo-0123abcd ] || fail "suffix: got [$OUT]"
run 1 branch 'demo-0123abcd/../x'
[ -z "$OUT" ] || fail "branch on a refused id printed [$OUT]"
run 1 suffix Demo-0123abcd
[ -z "$OUT" ] || fail "suffix on a refused id printed [$OUT]"
echo "ok: branch and suffix derive from a checked id only"

# 6. The uid source's own failure modes carry their documented exit codes.
run 2 taken 'demo-0123abcd/../x' --repo-root "$repo"
[ -z "$OUT" ] || fail "taken on a malformed id printed [$OUT]"
export PLANWRIGHT_FLIGHT_UID_SOURCE="$tmp/does-not-exist"
run 4 new demo --repo-root "$repo"
[ -z "$OUT" ] || fail "a missing uid source still minted [$OUT]"
: >"$tmp/empty-uids"
export PLANWRIGHT_FLIGHT_UID_SOURCE="$tmp/empty-uids"
run 4 new demo --repo-root "$repo"
[ -z "$OUT" ] || fail "an empty uid source still minted [$OUT]"
printf 'zzzzzzzz\n' >"$tmp/bad-uids"
export PLANWRIGHT_FLIGHT_UID_SOURCE="$tmp/bad-uids"
run 2 new demo --repo-root "$repo"
[ -z "$OUT" ] || fail "a malformed uid line still minted [$OUT]"
# A blank line is a malformed line, not the end of the source: the candidate
# after it is never silently skipped.
printf '0123abcd\n\n89abcdef\n' >"$tmp/blank-uids"
export PLANWRIGHT_FLIGHT_UID_SOURCE="$tmp/blank-uids"
gitc "$repo" branch planwright/flight/demo-0123abcd
run 2 new demo --repo-root "$repo"
[ -z "$OUT" ] || fail "a blank uid line was skipped over: minted [$OUT]"
gitc "$repo" branch -D -q planwright/flight/demo-0123abcd
unset PLANWRIGHT_FLIGHT_UID_SOURCE
echo "ok: the uid source's failure modes are told apart by exit code"

# 7. Usage errors.
run 2
run 2 bogus demo-0123abcd
run 2 new
run 2 check
run 2 check demo-0123abcd --repo-root "$repo"
run 2 new demo --repo-root

echo "PASS: test-flight-id"
