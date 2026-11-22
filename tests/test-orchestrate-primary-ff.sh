#!/bin/bash
# Tests for scripts/orchestrate-primary-ff.sh, /orchestrate's opt-in
# pre-flight fast-forward of a lagging primary checkout.
#
# What is covered:
#   - knob on, a clean primary on its default branch strictly behind origin:
#     fetched and fast-forwarded, the old and new heads printed and recorded;
#   - knob on, already current: nothing moves;
#   - knob on, uncommitted tracked changes: refused, tree and branch untouched;
#   - knob on, another branch checked out: refused, nothing moves;
#   - knob on, local history origin lacks (diverged): refused, nothing moves;
#   - knob off (absent, false, or malformed): nothing runs against the
#     checkout, not even a fetch;
#   - across every case, no rebase, reset, pull, amend or push is invoked.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-orchestrate-primary-ff.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_TERMINAL_PROMPT=0

here=$(cd "$(dirname "$0")" && pwd)
OPF="$here/../scripts/orchestrate-primary-ff.sh"
# shellcheck source=tests/lib/hermetic-env.sh
. "$here/lib/hermetic-env.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$OPF" ] || fail "scripts/orchestrate-primary-ff.sh missing or not executable"

REAL_GIT=$(command -v git) || fail "git not on PATH"

tmp=$(mktemp -d)
tmp=$(cd -P -- "$tmp" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

shim_dir="$tmp/shim"
mkdir -p "$shim_dir" "$tmp/adopter"
cat >"$shim_dir/git" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"\$PW_GIT_LOG"
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$shim_dir/git"

PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter"
export PLANWRIGHT_ADOPTER_OVERLAY

knob_on="$tmp/knob-on.yml"
printf 'orchestrate_fast_forward_primary: true\n' >"$knob_on"
knob_false="$tmp/knob-false.yml"
printf 'orchestrate_fast_forward_primary: false\n' >"$knob_false"
knob_bad="$tmp/knob-bad.yml"
printf 'orchestrate_fast_forward_primary: yes-please\n' >"$knob_bad"
knob_none="$tmp/knob-none.yml"
: >"$knob_none"

# A bare origin, a primary clone of it, and origin one commit ahead.
new_fixture() {
  nf_root="$tmp/$1"
  mkdir -p "$nf_root"
  "$REAL_GIT" init --quiet --bare --initial-branch=main "$nf_root/origin.git"
  "$REAL_GIT" init --quiet --initial-branch=main "$nf_root/seed"
  (
    cd "$nf_root/seed"
    "$REAL_GIT" config user.email t@example.invalid
    "$REAL_GIT" config user.name Tester
    "$REAL_GIT" config commit.gpgsign false
    "$REAL_GIT" remote add origin "$nf_root/origin.git"
    echo one >spec.md
    "$REAL_GIT" add spec.md
    "$REAL_GIT" commit --quiet -m seed
    "$REAL_GIT" push --quiet origin main
  )
  "$REAL_GIT" clone --quiet "$nf_root/origin.git" "$nf_root/primary"
  "$REAL_GIT" -C "$nf_root/primary" config user.email t@example.invalid
  "$REAL_GIT" -C "$nf_root/primary" config user.name Tester
  "$REAL_GIT" -C "$nf_root/primary" config commit.gpgsign false
  (
    cd "$nf_root/seed"
    echo two >>spec.md
    "$REAL_GIT" commit --quiet -am advance
    "$REAL_GIT" push --quiet origin main
  )
  printf '%s\n' "$nf_root"
}

# opf <knob-file> <case> [args...] — run the wrapper with the recording shim,
# capturing out (stdout), errout (stderr) and rc.
opf() {
  opf_cfg=$1
  PW_GIT_LOG="$tmp/git-$2.log"
  export PW_GIT_LOG
  : >"$PW_GIT_LOG"
  shift 2
  set +e
  out=$(PLANWRIGHT_LOCAL_CONFIG="$opf_cfg" PLANWRIGHT_WORKER_HANDLE=opf-test PATH="$shim_dir:$PATH" \
    /bin/sh "$OPF" "$@" 2>"$tmp/stderr")
  rc=$?
  set -e
  errout=$(cat "$tmp/stderr")
}

assert_no_rewrite() {
  for bad in '(^| )rebase( |$)' '(^| )pull( |$)' '(^| )reset( |$)' 'commit .*--amend' '(^| )push( |$)'; do
    if grep -Eq "$bad" "$PW_GIT_LOG"; then
      fail "$1: invoked a forbidden git operation matching '$bad'"
    fi
  done
}

head_of() { "$REAL_GIT" -C "$1" rev-parse "$2"; }

# 1. Knob on, clean and lagging: fetched and fast-forwarded.
root=$(new_fixture ok)
old=$(head_of "$root/primary" main)
new=$(head_of "$root/origin.git" main)
opf "$knob_on" 1 --checkout "$root/primary"
[ "$rc" -eq 0 ] || fail "1: a clean lagging primary was not fast-forwarded (exit $rc): $out $errout"
[ "$(head_of "$root/primary" main)" = "$new" ] || fail "1: main is not at origin/main"
printf '%s\n' "$out" | grep -qx "primary-ff	fast-forward	main	$old	$new" \
  || fail "1: the verdict does not carry the branch and both heads: $out"
printf '%s\n' "$errout" | grep -q "from $old to $new" || fail "1: the old and new heads were not logged: $errout"
grep -q "ff-primary	$root/primary	main	$old	$new	opf-test$" \
  "$root/primary/.git/planwright/main-currency.log" \
  || fail "1: the move was not recorded with both heads"
grep -Eq '(^| )merge .*--ff-only' "$PW_GIT_LOG" || fail "1: the move was not a --ff-only merge"
assert_no_rewrite 1

# 2. Knob on, already current: nothing moves, no merge runs.
opf "$knob_on" 2 --checkout "$root/primary"
[ "$rc" -eq 0 ] || fail "2: a current primary was refused (exit $rc): $errout"
printf '%s\n' "$out" | grep -qx "primary-ff	up-to-date	main	$new" || fail "2: no up-to-date verdict: $out"
if grep -Eq '(^| )merge( |$)' "$PW_GIT_LOG"; then
  fail "2: a merge ran on a current primary"
fi
assert_no_rewrite 2

# 3. Knob on, dirty: refused, the change and the branch left as they were.
root=$(new_fixture dirty)
old=$(head_of "$root/primary" main)
echo local-edit >>"$root/primary/spec.md"
opf "$knob_on" 3 --checkout "$root/primary"
[ "$rc" -eq 4 ] || fail "3: a dirty primary was not refused with exit 4 (exit $rc): $out $errout"
printf '%s\n' "$out" | grep -qx 'primary-ff	refused' || fail "3: no refused verdict: $out"
printf '%s\n' "$errout" | grep -q 'uncommitted changes' || fail "3: the refusal does not say why: $errout"
[ "$(head_of "$root/primary" main)" = "$old" ] || fail "3: main moved under a dirty tree"
grep -q local-edit "$root/primary/spec.md" || fail "3: the uncommitted change was lost"
[ ! -s "$root/primary/.git/planwright/main-currency.log" ] || fail "3: a refusal wrote a record"
assert_no_rewrite 3

# 4. Knob on, another branch checked out: refused, nothing moves.
root=$(new_fixture off-main)
old=$(head_of "$root/primary" main)
"$REAL_GIT" -C "$root/primary" checkout --quiet -b feature
opf "$knob_on" 4 --checkout "$root/primary"
[ "$rc" -eq 4 ] || fail "4: a primary off main was not refused with exit 4 (exit $rc): $out $errout"
printf '%s\n' "$out" | grep -qx 'primary-ff	refused' || fail "4: no refused verdict: $out"
printf '%s\n' "$errout" | grep -q 'feature' || fail "4: the refusal does not name the branch: $errout"
[ "$(head_of "$root/primary" main)" = "$old" ] || fail "4: main moved while another branch was checked out"
[ "$("$REAL_GIT" -C "$root/primary" symbolic-ref --short HEAD)" = feature ] || fail "4: the checkout switched branches"
assert_no_rewrite 4

# 5. Knob on, diverged: local main carries a commit origin lacks.
root=$(new_fixture diverged)
echo local >"$root/primary/local.md"
"$REAL_GIT" -C "$root/primary" add local.md
"$REAL_GIT" -C "$root/primary" commit --quiet -m local
old=$(head_of "$root/primary" main)
opf "$knob_on" 5 --checkout "$root/primary"
[ "$rc" -eq 4 ] || fail "5: a diverged primary was not refused with exit 4 (exit $rc): $out $errout"
printf '%s\n' "$out" | grep -qx 'primary-ff	refused' || fail "5: no refused verdict: $out"
printf '%s\n' "$errout" | grep -q 'not a pure fast-forward' || fail "5: the refusal does not say why: $errout"
[ "$(head_of "$root/primary" main)" = "$old" ] || fail "5: a diverged main moved"
assert_no_rewrite 5

# 6. Knob off, whether absent, false or malformed: nothing runs against the
#    checkout, not even a fetch, and a lagging main stays where it is.
root=$(new_fixture knob-off)
old=$(head_of "$root/primary" main)
for cfg in "$knob_none" "$knob_false" "$knob_bad"; do
  opf "$cfg" 6 --checkout "$root/primary"
  [ "$rc" -eq 0 ] || fail "6: knob off exited $rc ($cfg): $errout"
  printf '%s\n' "$out" | grep -qx 'primary-ff	disabled' || fail "6: no disabled verdict ($cfg): $out"
  [ "$(head_of "$root/primary" main)" = "$old" ] || fail "6: main moved with the knob off ($cfg)"
  if grep -Eq '(^| )(fetch|merge|ls-remote)( |$)' "$PW_GIT_LOG"; then
    fail "6: the knob off still reached origin or the branch ($cfg): $(cat "$PW_GIT_LOG")"
  fi
  [ ! -e "$root/primary/.git/planwright" ] || fail "6: the knob off wrote state ($cfg)"
done
printf '%s\n' "$errout" | grep -q 'yes-please' || fail "6: a malformed knob value was not warned about: $errout"

# 8. From a linked worktree with no --checkout, the knob is read from the
#    primary's own machine-local layer and the primary, not the worktree,
#    moves.
root=$(new_fixture from-worktree)
"$REAL_GIT" -C "$root/primary" worktree add --quiet -b planwright/flight/x "$root/wt" 2>"$tmp/wt.err" \
  || fail "8: fixture worktree add failed: $(cat "$tmp/wt.err")"
mkdir -p "$root/primary/.claude"
printf 'orchestrate_fast_forward_primary: true\n' >"$root/primary/.claude/planwright.local.yml"
wt_head=$(head_of "$root/wt" HEAD)
new=$(head_of "$root/origin.git" main)
opf_cwd() (cd "$root/wt" && opf "" 8 && printf '%s\n%s\n' "$rc" "$out")
res=$(opf_cwd)
[ "$(printf '%s\n' "$res" | sed -n 1p)" = 0 ] || fail "8: run from a worktree failed: $res"
printf '%s\n' "$res" | grep -q "^primary-ff	fast-forward	main	" \
  || fail "8: the primary's knob was not read from the worktree: $res"
[ "$(head_of "$root/primary" main)" = "$new" ] || fail "8: the primary's main did not move"
[ "$(head_of "$root/wt" HEAD)" = "$wt_head" ] || fail "8: the worktree's branch moved"

# 7. Usage: an unknown argument is refused before anything runs.
opf "$knob_on" 7 --bogus
[ "$rc" -eq 2 ] || fail "7: an unknown argument was not a usage error (exit $rc)"
[ ! -s "$PW_GIT_LOG" ] || fail "7: git ran on a usage error"

echo "PASS: test-orchestrate-primary-ff.sh"
