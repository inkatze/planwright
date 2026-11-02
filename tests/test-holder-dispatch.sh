#!/bin/bash
# Tests for dispatch from a holder: the holder arm of
# scripts/resolve-work-repo.sh (REQ-I1.5), derivation and selection from the
# holder, and scripts/orchestrate-meta-step.sh placing each unit in its task's
# work repository whichever repository it runs from (REQ-I1.6), over the
# shared two-repository fixture with the bundle under the holder's `hub`
# directory, which is not the holder's own spec root. Plain bash 3.2, inline
# asserts.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPTS=$REPO_ROOT/scripts
TAB=$(printf '\t')
# shellcheck source=tests/lib/two-repo-fixture.sh
. "$REPO_ROOT/tests/lib/two-repo-fixture.sh"
# shellcheck source=tests/lib/poll-until.sh
. "$REPO_ROOT/tests/lib/poll-until.sh"

failures=0
pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}
assert_has() {
  case $3 in
    *"$2"*) pass "$1" ;;
    *) fail "$1 (expected to contain '$2', got: $3)" ;;
  esac
}
assert_not() {
  case $3 in
    *"$2"*) fail "$1 (did not expect '$2' in: $3)" ;;
    *) pass "$1" ;;
  esac
}

trf_setup "$SCRIPTS" demo hub || {
  echo "FAIL: the two-repository fixture could not be built" >&2
  exit 1
}
trap trf_teardown EXIT
B=$TRF_ROOT/demo
HOLDER=$TRF/holder
ALPHA=$TRF/src/alpha
BETA=$TRF/src/beta

# Real remotes, so the dispatch path's fetch-before-gate has something to
# fetch. The registered aliases stay those the fixture's origins gave.
for r in alpha beta holder; do
  trf_git init -q --bare "$TRF/remotes/$r.git"
done
for r in alpha beta; do
  trf_git -C "$TRF/src/$r" remote set-url origin "$TRF/remotes/$r.git"
  trf_git -C "$TRF/src/$r" push -q origin main
done
trf_git -C "$HOLDER" remote add origin "$TRF/remotes/holder.git"
# The holder registers too, as a holder: never a dispatch candidate.
(cd "$HOLDER" && trf_env /bin/sh "$SCRIPTS/work-repo-registry.sh" register --root "$TRF_ROOT" >/dev/null 2>&1) \
  || fail "the holder could not register against its root"

block() {
  printf '### Task %s — %s\n\n- **Deliverables:** work.\n- **Done when:** done.\n- **Dependencies:** %s\n- **Citations:** REQ-X\n- **Estimated effort:** 1 day\n%s\n' \
    "$1" "$2" "$3" "$4"
}
# write_bundle <task 1 field> <task 2 field> [<task 3>] — Task 2 depends on
# Task 1; a third argument adds an independent Task 3 naming no repository.
write_bundle() {
  wb_three=""
  [ "$#" -lt 3 ] || wb_three=$(block 3 'Anywhere third' none '')
  trf_bundle "$(block 1 'Alpha first' none "$1")
$(block 2 'Beta second' 1 "$2")
$wb_three"
  printf '\nThe demo bundle.\n' >>"$B/requirements.md"
  for f in design test-spec; do
    printf '# Demo %s\n\n**Status:** Ready\n\nBody.\n' "$f" >"$B/$f.md"
  done
}
NAMED_1='- **Repository:** alpha'
NAMED_2='- **Repository:** beta'

# rwr <from> <args...> — resolve-work-repo.sh run from a checkout.
rwr() {
  rw_from=$1
  shift
  rw_rc=0
  rw_out=$(cd "$rw_from" && trf_env /bin/sh "$SCRIPTS/resolve-work-repo.sh" "$@" 2>"$TRF/rw.err") || rw_rc=$?
  rw_err=$(cat "$TRF/rw.err")
}
derive() {
  st_rc=0
  state=$(cd "$1" && trf_env /bin/sh "$SCRIPTS/orchestrate-state.sh" "$B" 2>"$TRF/st.err") || st_rc=$?
  st_err=$(cat "$TRF/st.err")
}
select_unit() {
  sel=$(cd "$1" && trf_env /bin/sh "$SCRIPTS/orchestrate-select.sh" "$B" 2>/dev/null) || sel=""
}
rec() {
  printf '%s\n' "$state" | awk -F"$TAB" -v t="$1" -v i="$2" \
    '$1 == t && $2 == i { sub("^[^\t]*\t[^\t]*\t", ""); print; exit }'
}

# --- REQ-I1.5: holder resolution ----------------------------------------------
write_bundle "$NAMED_1" "$NAMED_2"
rwr "$HOLDER" "$B" --task 1
assert_eq "I1.5 a task naming alpha resolves to alpha from the holder" "0 $ALPHA" "$rw_rc $rw_out"
rwr "$HOLDER" "$B" --task 2
assert_eq "I1.5 a task naming beta resolves to beta from the holder" "0 $BETA" "$rw_rc $rw_out"
rwr "$HOLDER" "$B"
assert_eq "I1.5 the bundle alone, two registered: resolves to nothing (exit)" 5 "$rw_rc"
assert_eq "I1.5 the bundle alone never prints the holder" "" "$rw_out"
assert_has "I1.5 the refusal names alpha" "alpha ($ALPHA)" "$rw_err"
assert_has "I1.5 the refusal names beta" "beta ($BETA)" "$rw_err"
assert_not "I1.5 the holder is no candidate" "holder (" "$rw_err"

write_bundle '' ''
rwr "$HOLDER" "$B" --task 1
assert_eq "I1.5 no field, two registered: the task resolves to nothing (exit)" 5 "$rw_rc"
assert_eq "I1.5 no field, two registered: nothing printed" "" "$rw_out"
assert_has "I1.5 no field, two registered: the refusal names both" "alpha ($ALPHA), beta ($BETA)" "$rw_err"
trf_unregister beta
rwr "$HOLDER" "$B" --task 1
assert_eq "I1.5 no field, one registered: the task resolves to it" "0 $ALPHA" "$rw_rc $rw_out"
rwr "$HOLDER" "$B"
assert_eq "I1.5 no field, one registered: the bundle resolves to it" "0 $ALPHA" "$rw_rc $rw_out"
trf_unregister alpha
rwr "$HOLDER" "$B" --task 1
assert_eq "I1.5 none registered: resolves to nothing (exit)" 5 "$rw_rc"
assert_has "I1.5 none registered: says so" "no work repository is registered" "$rw_err"
mv "$TRF/pdata/work-repos/registry.tsv" "$TRF/registry.away"
mkdir "$TRF/pdata/work-repos/registry.tsv"
rwr "$HOLDER" "$B" --task 1
assert_eq "I1.5 an unreadable registry resolves to nothing (exit)" 5 "$rw_rc"
assert_has "I1.5 an unreadable registry is named as such" "registry could not be read" "$rw_err"
rmdir "$TRF/pdata/work-repos/registry.tsv"
mv "$TRF/registry.away" "$TRF/pdata/work-repos/registry.tsv"
trf_register alpha
trf_register beta

write_bundle '- **Repository:** gamma' "$NAMED_2"
rwr "$HOLDER" "$B" --task 1
assert_eq "I1.5 an unregistered alias resolves to nothing (exit)" 5 "$rw_rc"
assert_eq "I1.5 an unregistered alias never prints the holder" "" "$rw_out"
assert_has "I1.5 an unregistered alias names the candidates" "alpha ($ALPHA), beta ($BETA)" "$rw_err"
write_bundle '- **Repository:** holder' "$NAMED_2"
rwr "$HOLDER" "$B" --task 1
assert_eq "I1.5 an alias naming the holder resolves to nothing (exit)" 5 "$rw_rc"
assert_eq "I1.5 an alias naming the holder never prints it" "" "$rw_out"
assert_has "I1.5 an alias naming the holder says so" "names a holder checkout" "$rw_err"
write_bundle '- **Repository:** acme/beta' "$NAMED_2"
rwr "$HOLDER" "$B" --task 1
assert_eq "I1.5 a malformed field resolves to nothing (exit)" 5 "$rw_rc"
rwr "$HOLDER" "$B" --task '1
2'
assert_eq "I1.5 a task id outside the grammar is a usage error" 2 "$rw_rc"

# A work-repository session: unchanged for a task with no field, and an alias
# naming another repository resolves there.
write_bundle '' ''
rwr "$ALPHA" "$B"
assert_eq "I1.6 from alpha, the bundle is alpha's as before" "0 $ALPHA" "$rw_rc $rw_out"
rwr "$ALPHA" "$B" --task 1
assert_eq "I1.6 from alpha, a task with no field is alpha's" "0 $ALPHA" "$rw_rc $rw_out"
write_bundle "$NAMED_1" "$NAMED_2"
rwr "$ALPHA" "$B" --task 2
assert_eq "I1.6 from alpha, a task naming beta resolves to beta" "0 $BETA" "$rw_rc $rw_out"

# --- REQ-I1.6: derivation and selection from the holder -----------------------
derive "$HOLDER"
assert_eq "I1.6 the holder derives the bundle (exit)" 0 "$st_rc"
assert_eq "I1.6 Task 1 is ready from the holder" "ready${TAB}deps-met" "$(rec task 1)"
assert_eq "I1.6 Task 2 is blocked behind it" "blocked${TAB}deps-unmet" "$(rec task 2)"
select_unit "$HOLDER"
assert_eq "I1.6 the selector picks Task 1 from the holder" 1 "$sel"
trf_pr alpha 1 MERGED 42
select_unit "$HOLDER"
assert_eq "I1.6 after Task 1 merges in alpha, the selector picks Task 2" 2 "$sel"
trf_reset_evidence

# A task naming no repository, beside one that does, with two registered.
write_bundle "$NAMED_1" ''
derive "$HOLDER"
assert_eq "I1.6 a named task still derives" "ready${TAB}deps-met" "$(rec task 1)"
assert_eq "I1.6 a task naming none is unresolved, never the holder's" \
  "repository-unresolved${TAB}work-repository-unresolved" "$(rec task 2)"
assert_has "I1.6 its reason names the candidates" "alpha ($ALPHA), beta ($BETA)" "$(rec repository-unresolved 2)"
write_bundle '' ''
derive "$HOLDER"
assert_eq "I1.6 a bundle naming no repository with two registered refuses (exit)" 2 "$st_rc"
assert_has "I1.6 that refusal names the candidates" "alpha ($ALPHA), beta ($BETA)" "$st_err"

# --- REQ-I1.6: the meta-step dispatches into the task's repository ------------
write_bundle "$NAMED_1" "$NAMED_2" three
anchor=$(trf_env /bin/sh "$SCRIPTS/spec-anchor.sh" "$B") || fail "spec-anchor.sh failed on the fixture"
# shellcheck disable=SC2016 # literal backticks: the record format
printf '# Kickoff brief\n\nClass: meaning\nLens-pass: §8\nAnchor: `%s` — computed as\n`scripts/spec-anchor.sh specs/demo`\n' \
  "$anchor" >"$B/kickoff-brief.md"
trf_git -C "$HOLDER" add -A
trf_git -C "$HOLDER" commit -q -m bundle
trf_git -C "$HOLDER" push -q origin main
printf '/planwright:execute-task demo 1\n' >"$TRF/prompt"
FAKE=$TRF/fake-claude
# shellcheck disable=SC2016 # the fake's own expansions
printf '#!/bin/sh\nprintf "%%s\\n" "${PLANWRIGHT_WORKER_SPEC_ROOT:-}" >>"%s"\nprintf "%%s\\n" "$PWD" >>"%s"\ncat >/dev/null\nexit 0\n' \
  "$TRF/zone" "$TRF/cwd" >"$FAKE"
chmod +x "$FAKE"

# meta <from> <id> — the meta-step from a checkout, isolated from the
# machine's fleet home.
meta() {
  m_rc=0
  m_out=$(cd "$1" && trf_env env -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    PLANWRIGHT_FLEET_STATE_DIR="$TRF/fleet" \
    PLANWRIGHT_DISPATCH_FETCH_STATE_DIR="$TRF/fstate" \
    PLANWRIGHT_DISPATCH_FETCH_RETRIES=0 \
    PLANWRIGHT_DISPATCH_LIVENESS_SKIP_TMUX=1 \
    PLANWRIGHT_HEADLESS_CLAUDE="$FAKE" \
    PLANWRIGHT_HEADLESS_STATE_DIR="$TRF/hstate" \
    /bin/sh "$SCRIPTS/orchestrate-meta-step.sh" dispatch "$B" "$2" \
    --backend headless-oneshot --prompt-file "$TRF/prompt" </dev/null 2>"$TRF/m.err") || m_rc=$?
  m_err=$(cat "$TRF/m.err")
}
mfield() { printf '%s\n' "$m_out" | awk -F"$TAB" -v k="$1" '$1 == "meta-step" && $2 == k { print $3; exit }'; }
has_branch() { trf_env git -C "$1" show-ref --verify --quiet "refs/heads/planwright/demo/task-$2"; }
markers() {
  md=$(trf_env git -C "$HOLDER" rev-parse --path-format=absolute --git-common-dir)/planwright/orchestrate/demo/markers
  find "$md" "$B/.orchestrate/markers" -type f 2>/dev/null | wc -l | tr -d ' '
}
# nothing_created <label> <id> — no branch, worktree, or marker anywhere.
nothing_created() {
  for r in "$HOLDER" "$ALPHA" "$BETA"; do
    if has_branch "$r" "$2"; then fail "$1: a task branch was created in ${r##*/}"; fi
    if [ -e "$r/.claude/worktrees/demo-task-$2" ]; then fail "$1: a worktree was created in ${r##*/}"; fi
  done
  assert_eq "$1: no dispatch marker" 0 "$(markers)"
}

# The meta-tower's selector supervises the holder's bundle from the holder.
ms_out=$(cd "$HOLDER" && trf_env /bin/sh "$SCRIPTS/orchestrate-meta-select.sh" "$B" 2>&1)
assert_eq "I1.6 the meta selector picks Task 1 from the holder" "$B${TAB}1" "$ms_out"

# The per-spec lock takes the holder's bundle, never a linked worktree's copy.
trf_git -C "$HOLDER" worktree add -q --detach "$HOLDER/.claude/worktrees/copy" main
lk() { (cd "$HOLDER" && trf_env /bin/sh "$SCRIPTS/orchestrate-lock.sh" "$@" >/dev/null 2>&1); }
if lk acquire "$HOLDER/.claude/worktrees/copy/hub/demo"; then
  fail "I1.6 the lock took a linked worktree's copy of the holder's bundle"
  lk release "$HOLDER/.claude/worktrees/copy/hub/demo"
else
  pass "I1.6 the lock refuses a linked worktree's copy of the holder's bundle"
fi
trf_repo "$HOLDER/nested"
mkdir -p "$HOLDER/nested/hub/demo"
printf 'project: hub\nlayout: 1\n' >"$HOLDER/nested/hub/planwright-spec-root.yml"
if lk acquire "$HOLDER/nested/hub/demo"; then
  fail "I1.6 the lock took a bundle in a repository nested in the holder"
  lk release "$HOLDER/nested/hub/demo"
else
  pass "I1.6 the lock refuses a bundle in a repository nested in the holder"
fi
rm -rf "$HOLDER/nested"
if lk acquire "$B"; then
  pass "I1.6 the lock takes the holder's bundle"
  lk release "$B"
else
  fail "I1.6 the lock refused the holder's bundle"
fi
# The copy still resolves through the registry the primary's root is keyed by.
rwr "$HOLDER" "$HOLDER/.claude/worktrees/copy/hub/demo" --task 1
assert_eq "I1.5 a linked worktree's copy resolves through the primary's root" "0 $ALPHA" "$rw_rc $rw_out"
trf_git -C "$HOLDER" worktree remove --force "$HOLDER/.claude/worktrees/copy"
rmdir "$HOLDER/.claude/worktrees" "$HOLDER/.claude"

# Refusals come before the lock and park the unit: nothing is created, in the
# holder or anywhere.
meta "$HOLDER" 3
assert_eq "I1.6 no field, two registered: the dispatch parks (exit)" 4 "$m_rc"
assert_has "I1.6 the park names its stage" "halt${TAB}work-repo" "$m_out"
assert_has "I1.6 the refusal names the candidates" "alpha ($ALPHA), beta ($BETA)" "$m_err"
nothing_created "I1.6 no field, two registered" 3
write_bundle "$NAMED_1" "$NAMED_2" three
sed 's/^\*\*Format-version:\*\* 3$/**Format-version:** three/' "$B/tasks.md" >"$TRF/tasks.tmp"
mv "$TRF/tasks.tmp" "$B/tasks.md"
meta "$HOLDER" 1
assert_eq "I1.6 unreadable Repository: fields: the dispatch is refused (exit)" 2 "$m_rc"
nothing_created "I1.6 unreadable Repository: fields" 1
write_bundle '- **Repository:** gamma' "$NAMED_2" three
meta "$HOLDER" 1
assert_eq "I1.6 an unregistered alias: the dispatch parks (exit)" 4 "$m_rc"
assert_has "I1.6 the refusal names the candidates" "alpha ($ALPHA), beta ($BETA)" "$m_err"
nothing_created "I1.6 an unregistered alias" 1
write_bundle "$NAMED_1" "$NAMED_2" three

meta "$HOLDER" 1
assert_eq "I1.6 from the holder, Task 1 dispatches (exit)" 0 "$m_rc"
[ "$m_rc" -eq 0 ] || echo "$m_out $m_err" >&2
assert_eq "I1.6 the work repository is alpha" "$ALPHA" "$(mfield work)"
assert_eq "I1.6 the worktree is alpha's" "$ALPHA/.claude/worktrees/demo-task-1" "$(mfield worktree)"
if has_branch "$ALPHA" 1; then pass "I1.6 the task branch is in alpha"; else fail "I1.6 no task branch in alpha"; fi
if has_branch "$HOLDER" 1; then fail "I1.6 a task branch was created in the holder"; else pass "I1.6 no task branch in the holder"; fi
if [ -e "$HOLDER/.claude/worktrees" ]; then fail "I1.6 a worktree was created in the holder"; else pass "I1.6 no worktree in the holder"; fi
cwd_is() { [ "$(head -1 "$TRF/cwd" 2>/dev/null)" = "$1" ]; }
if poll_until --what "the worker's working directory" cwd_is "$ALPHA/.claude/worktrees/demo-task-1"; then
  pass "I1.6 the worker runs in alpha's worktree"
else
  fail "I1.6 the worker ran in '$(head -1 "$TRF/cwd" 2>/dev/null)'"
fi
assert_eq "I1.6 the worker's write zone is the spec root" "$TRF_ROOT" "$(head -1 "$TRF/zone" 2>/dev/null)"
assert_eq "I1.6 the marker sits in the bundle's home in the holder" 2 "$(markers)"
derive "$ALPHA"
assert_eq "I1.6 the marker is in flight from alpha's session" in-progress "$(rec task 1 | cut -f1)"

trf_pr alpha 1 MERGED 42
: >"$TRF/cwd"
printf '/planwright:execute-task demo 2\n' >"$TRF/prompt"
meta "$ALPHA" 2
assert_eq "I1.6 from alpha, Task 2 dispatches (exit)" 0 "$m_rc"
[ "$m_rc" -eq 0 ] || echo "$m_out $m_err" >&2
assert_eq "I1.6 from alpha, the work repository is beta" "$BETA" "$(mfield work)"
assert_eq "I1.6 from alpha, the worktree is beta's" "$BETA/.claude/worktrees/demo-task-2" "$(mfield worktree)"
if has_branch "$BETA" 2; then pass "I1.6 Task 2's branch is in beta"; else fail "I1.6 no Task 2 branch in beta"; fi
if has_branch "$ALPHA" 2; then fail "I1.6 a Task 2 branch was created in alpha"; else pass "I1.6 no Task 2 branch in alpha"; fi
if [ -e "$ALPHA/.claude/worktrees/demo-task-2" ]; then fail "I1.6 a Task 2 worktree was created in alpha"; else pass "I1.6 no Task 2 worktree in alpha"; fi
if poll_until --what "the worker's working directory" cwd_is "$BETA/.claude/worktrees/demo-task-2"; then
  pass "I1.6 the worker runs in beta's worktree"
else
  fail "I1.6 the worker ran in '$(head -1 "$TRF/cwd" 2>/dev/null)'"
fi

# An uncommitted Repository: edit in the holder routes elsewhere than the
# committed bundle the gate checked: the dispatch parks, nothing created.
cp "$B/tasks.md" "$TRF/tasks.committed"
: >"$TRF/cwd"
printf '%s\n' "$NAMED_2" >>"$B/tasks.md"
printf '/planwright:execute-task demo 3\n' >"$TRF/prompt"
meta "$HOLDER" 3
assert_eq "I1.6 an uncommitted Repository: edit parks the dispatch (exit)" 4 "$m_rc"
assert_has "I1.6 the park names the uncommitted field" "halt${TAB}gate${TAB}repository-uncommitted" "$m_out"
assert_has "I1.6 the remedy says to commit or revert the edit" "commit or revert the Repository: edit" "$m_out"
for r in "$HOLDER" "$ALPHA" "$BETA"; do
  if has_branch "$r" 3; then fail "I1.6 an uncommitted edit created a Task 3 branch in ${r##*/}"; fi
  if [ -e "$r/.claude/worktrees/demo-task-3" ]; then fail "I1.6 an uncommitted edit created a Task 3 worktree in ${r##*/}"; fi
done
assert_eq "I1.6 an uncommitted edit launched no worker" "" "$(cat "$TRF/cwd")"
mv "$TRF/tasks.committed" "$B/tasks.md"

# A task naming no repository, with one work repository registered, dispatches
# there from the holder.
trf_unregister beta
: >"$TRF/cwd"
printf '/planwright:execute-task demo 3\n' >"$TRF/prompt"
meta "$HOLDER" 3
assert_eq "I1.6 no field, one registered: the dispatch succeeds (exit)" 0 "$m_rc"
[ "$m_rc" -eq 0 ] || echo "$m_out $m_err" >&2
assert_eq "I1.6 no field, one registered: the worktree is alpha's" "$ALPHA/.claude/worktrees/demo-task-3" "$(mfield worktree)"
if has_branch "$HOLDER" 3; then fail "I1.6 a Task 3 branch was created in the holder"; else pass "I1.6 no Task 3 branch in the holder"; fi
trf_register beta

echo
if [ "$failures" -eq 0 ]; then
  echo "all holder-dispatch tests passed"
else
  echo "$failures holder-dispatch test(s) failed"
  exit 1
fi
