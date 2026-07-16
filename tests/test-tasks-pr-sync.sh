#!/bin/bash
# Tests for scripts/tasks-pr-sync.sh — the level-triggered, idempotent
# reconcile that is the SOLE writer of tasks.md section placement
# (orchestration-concurrency Task 4; D-1, D-3; REQ-B1.1, REQ-B1.2, REQ-B1.3,
# REQ-C1.3). The same script is wired as a PostToolUse(Bash) hook: a
# `gh pr create` / `gh pr merge` on a convention-named branch triggers a full
# reconcile of that spec rather than an edge-triggered single-block move.
#
# What "level-triggered placement reconcile" means here:
#   - placement is recomputed from scripts/orchestrate-state.sh (the Task 1
#     derivation engine), never from the prior tasks.md section assignment;
#   - completed → ## Completed, in-progress → ## In progress, ready/blocked →
#     ## Forward plan; the human-owned sections (Awaiting input, Deferred, Out
#     of scope) are sticky (bodies preserved without data loss — REQ-B1.3 —
#     never relocated by derivation; whitespace is canonicalized, content kept);
#   - a second run against unchanged truth is a byte-identical no-op (REQ-B1.2);
#   - a scrambled / flattened / conflict-marked snapshot reconciles to the SAME
#     canonical placement (REQ-B1.2 self-heal, REQ-B1.3 rebuild, REQ-C1.3
#     conflict regeneration — never ours/theirs/union);
#   - the write is atomic (write-temp-then-rename) and leaves no temp behind;
#   - definition content and the spec content anchor are invariant (REQ-B1.1
#     placement-vs-definition split; placement is anchor-excluded).
#
# Preserved from the hook's prior contract: it writes the PRIMARY checkout's
# tasks.md from inside a worktree (risk row 3); it acquires through the ONE
# shared lock primitive (REQ-D1.1, REQ-D1.2) and is fail-soft on a busy /
# missing lock; hostile branch/spec ids and out-of-tree spec dirs are clean
# no-ops (REQ-F1.1).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SYNC="$here/../scripts/tasks-pr-sync.sh"
ANCHOR="$here/../scripts/spec-anchor.sh"
STATE="$here/../scripts/orchestrate-state.sh"
LOCKSH="$here/../scripts/orchestrate-lock.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SYNC" ] || fail "scripts/tasks-pr-sync.sh missing or not executable"
[ -x "$ANCHOR" ] || fail "scripts/spec-anchor.sh missing (anchor invariance check needs it)"
[ -x "$STATE" ] || fail "scripts/orchestrate-state.sh missing (the derivation backbone)"
command -v jq >/dev/null 2>&1 || fail "jq required to run this suite"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- gh stub: deterministic, no network. Returns nothing for pr list by default
# (so the derivation falls back to git-only), but emits canned TSV lines from
# GH_PRLIST when set (the merged-PR evidence batch the Task 7 stamp reuses:
# headRef<TAB>state<TAB>number<TAB>mergedAt). It also answers headRefName so the
# merge hook can resolve a head ref from a non-convention branch.
stub=$tmp/bin
mkdir -p "$stub"
cat >"$stub/gh" <<'EOF'
#!/bin/sh
case "$*" in
  *"pr list"*)
    if [ -n "${GH_PRLIST:-}" ]; then printf '%s\n' "$GH_PRLIST"; fi
    exit 0 ;;
  *headRefName*)
    if [ -n "${GH_HEADREF:-}" ]; then printf '%s\n' "$GH_HEADREF"; exit 0; fi
    exit 1 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$stub/gh"

# A fixture spec with five tasks spanning all four derived states. Evidence is
# wired by make_repo below (a trailer for Task 1, a branch+commit for Task 2);
# Tasks 3 and 5 are ready (deps met / none), Task 4 is blocked (dep on the
# in-progress Task 2). All blocks start under ## Forward plan; reconcile sorts
# them. Definition content is deliberately varied (wrapped lines, a dotted id
# is exercised elsewhere) so "no data loss" is meaningful.
write_spec() { # $1 = spec dir
  mkdir -p "$1"
  printf '%s\n' '# Demo — Requirements' '' '**Status:** Active' >"$1/requirements.md"
  printf '%s\n' '# Demo — Design' >"$1/design.md"
  printf '%s\n' '# Demo — Test Spec' >"$1/test-spec.md"
  cat >"$1/tasks.md" <<'EOF'
# Demo — Tasks

**Status:** Active
**Last reviewed:** 2026-06-29
**Format-version:** 1

Intro prose is preserved verbatim across a reconcile. The dependency view is
derived; the `Dependencies:` lines are authoritative.

## Forward plan

### Task 1 — Widget core

- **Deliverables:** A widget core,
  wrapped onto a second line.
- **Done when:** Widgets exist.
- **Dependencies:** none
- **Citations:** REQ-X1.1
- **Estimated effort:** 1 day

### Task 2 — Widget parser

- **Deliverables:** A widget parser.
- **Done when:** Parses widgets.
- **Dependencies:** none
- **Citations:** REQ-X1.2
- **Estimated effort:** 1 day

### Task 3 — Widget polish

- **Deliverables:** Polish for widgets.
- **Done when:** Widgets shine.
- **Dependencies:** 1
- **Citations:** REQ-X1.3
- **Estimated effort:** half day

### Task 4 — Gadget integration

- **Deliverables:** Gadgets.
- **Done when:** Gadgets integrate.
- **Dependencies:** 2
- **Citations:** REQ-X1.4
- **Estimated effort:** 1 day

### Task 5 — Sprocket

- **Deliverables:** A sprocket.
- **Done when:** Sprocket spins.
- **Dependencies:** none
- **Citations:** REQ-X1.5
- **Estimated effort:** half day

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

(none yet)

## Deferred

- **A deferred idea.** Built later. **Gate:** when the moon is full.
  Confidence: low.

## Out of scope

- A permanent exclusion.
EOF
}

make_repo() { # $1 = repo dir
  mkdir -p "$1"
  git -C "$1" init -q -b main
  git -C "$1" config user.email test@example.com
  git -C "$1" config user.name test
  git -C "$1" config commit.gpgsign false
  write_spec "$1/specs/demo"
  git -C "$1" add -A
  git -C "$1" commit -qm "chore: fixture"
  # Task 1 completed: a base commit carrying its Planwright-Task trailer (D-2).
  git -C "$1" commit -q --allow-empty -m "feat: task 1 done

Planwright-Task: demo/1"
  # Task 2 in-progress: a task branch with a commit ahead of base.
  git -C "$1" branch planwright/demo/task-2
  git -C "$1" checkout -q planwright/demo/task-2
  git -C "$1" commit -q --allow-empty -m "wip: task 2"
  git -C "$1" checkout -q main
}

# reconcile <repo> <spec-dir-relative> : run the direct CLI form.
reconcile() {
  (cd "$1" && PATH="$stub:$PATH" "$SYNC" reconcile "$2")
}

run_hook() { # $1 = cwd, $2 = command, $3 = command stdout
  (
    cd "$1" \
      && printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"stdout":"%s","stderr":""}}' "$2" "$3" \
      | PATH="$stub:$PATH" "$SYNC"
  )
}

section_of() { # $1 = tasks.md, $2 = task id → section name (or empty)
  awk -v id="$2" '
    /^## / { sec = substr($0, 4) }
    index($0, "### Task " id " ") == 1 { print sec; exit }
  ' "$1"
}

block_of() { # $1 = tasks.md, $2 = task id → block lines
  awk -v id="$2" '
    found && (/^## / || /^### /) { exit }
    index($0, "### Task " id " ") == 1 { found = 1 }
    found { print }
  ' "$1"
}

# ===========================================================================
# 1. Placement from the derivation (REQ-B1.1, REQ-C1.1 consumed via Task 1).
repo=$tmp/r1
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
anchor_before=$("$ANCHOR" "$repo/specs/demo")

# Sanity: the derivation produces the states this suite assumes.
states=$(cd "$repo" && "$STATE" specs/demo | awk -F'\t' '$1=="task"{print $2"="$3}' | sort | tr '\n' ' ')
case "$states" in
  *"1=completed"*) ;; *) fail "derivation precondition: Task 1 not completed ($states)" ;;
esac
case "$states" in
  *"2=in-progress"*) ;; *) fail "derivation precondition: Task 2 not in-progress ($states)" ;;
esac
case "$states" in
  *"4=blocked"*) ;; *) fail "derivation precondition: Task 4 not blocked ($states)" ;;
esac

reconcile "$repo" specs/demo || fail "reconcile: non-zero exit"
[ "$(section_of "$tasks" 1)" = "Completed" ] || fail "placement: Task 1 not in Completed"
[ "$(section_of "$tasks" 2)" = "In progress" ] || fail "placement: Task 2 not in In progress"
[ "$(section_of "$tasks" 3)" = "Forward plan" ] || fail "placement: ready Task 3 not in Forward plan"
[ "$(section_of "$tasks" 4)" = "Forward plan" ] || fail "placement: blocked Task 4 not in Forward plan"
[ "$(section_of "$tasks" 5)" = "Forward plan" ] || fail "placement: ready Task 5 not in Forward plan"
# Definition content survives the move (no data loss).
block_of "$tasks" 1 | grep -q 'wrapped onto a second line\.' \
  || fail "no data loss: Task 1 wrapped continuation line lost"
block_of "$tasks" 4 | grep -q -- '- \*\*Done when:\*\* Gadgets integrate\.' \
  || fail "no data loss: Task 4 definition lost"
# Human-owned section bodies preserved without data loss (content kept).
grep -q 'A deferred idea\.' "$tasks" || fail "sticky: Deferred prose lost"
grep -q 'A permanent exclusion\.' "$tasks" || fail "sticky: Out of scope prose lost"
grep -q 'Intro prose is preserved verbatim' "$tasks" || fail "preamble: intro prose lost"
# Placement is anchor-excluded (REQ-B1.1 placement vs definition).
anchor_after=$("$ANCHOR" "$repo/specs/demo")
[ "$anchor_before" = "$anchor_after" ] || fail "anchor: reconcile changed the content anchor (REQ-B1.1 breakage)"
# Atomic write leaves no temp behind.
ls "$repo/specs/demo"/.tasks-pr-sync.* >/dev/null 2>&1 && fail "atomic write: temp file left behind"
echo "ok: reconcile places blocks by derived state; anchor + definition + human sections invariant"

# Capture the canonical reconciled form for the convergence assertions below.
canonical=$tmp/canonical.md
cp "$tasks" "$canonical"

# ===========================================================================
# 2. Idempotency: a second run against unchanged truth is a byte-identical
#    no-op (REQ-B1.2).
reconcile "$repo" specs/demo || fail "idempotent reconcile: non-zero exit"
cmp -s "$tasks" "$canonical" || fail "idempotent: second reconcile changed tasks.md (not a no-op)"
echo "ok: a second reconcile against unchanged truth is a byte-identical no-op"

# ===========================================================================
# 3. Self-heal from a scrambled snapshot (REQ-B1.2): place every block in the
#    WRONG section, then reconcile back to the canonical placement.
repo=$tmp/r2
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
# Scramble: move all blocks under ## Completed (a maximally wrong snapshot),
# leaving the other block-bearing sections with the (none yet) placeholder.
scr=$tmp/scrambled.md
awk '
  function flush_pre(){ for(i=1;i<=np;i++) print pre[i] }
  BEGIN{ inpre=1; np=0; nb=0; curblk="" }
  /^## / && inpre { inpre=0 }
  inpre { pre[++np]=$0; next }
  /^### Task [0-9]/ {
    if (curblk!="") blocks[++nb]=curblk
    curblk=$0 "\n"; capt=1; next
  }
  /^### / { if(curblk!=""){blocks[++nb]=curblk; curblk=""} capt=0; next }
  /^## /  { if(curblk!=""){blocks[++nb]=curblk; curblk=""} capt=0; next }
  capt { curblk=curblk $0 "\n"; next }
  { next }
  END{
    if(curblk!="") blocks[++nb]=curblk
    flush_pre()
    print "## Forward plan\n\n(none yet)\n"
    print "## In progress\n\n(none yet)\n"
    print "## Completed\n"
    for(i=1;i<=nb;i++){ printf "\n%s", blocks[i] }
  }
' "$tasks" >"$scr"
cp "$scr" "$tasks"
# Precondition: the scramble actually mis-placed the blocks (so the self-heal is
# not vacuous) — Task 2 derives in-progress but the scramble dumped it in Completed.
[ "$(section_of "$tasks" 2)" = "Completed" ] \
  || fail "self-heal precondition: scramble did not mis-place Task 2 (test would be vacuous)"
reconcile "$repo" specs/demo || fail "self-heal reconcile: non-zero exit"
[ "$(section_of "$tasks" 1)" = "Completed" ] || fail "self-heal: Task 1 not corrected to Completed"
[ "$(section_of "$tasks" 2)" = "In progress" ] || fail "self-heal: Task 2 not corrected to In progress"
[ "$(section_of "$tasks" 3)" = "Forward plan" ] || fail "self-heal: Task 3 not corrected to Forward plan"
[ "$(section_of "$tasks" 5)" = "Forward plan" ] || fail "self-heal: Task 5 not corrected to Forward plan"
echo "ok: a scrambled snapshot self-heals to correct placement (REQ-B1.2)"

# ===========================================================================
# 4. Rebuild from a deleted snapshot (REQ-B1.3): strip the block-bearing
#    section structure to a flat dump, reconcile, and assert it converges to
#    the same canonical placement with no data loss.
repo=$tmp/r3
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
ref=$tmp/ref3.md
reconcile "$repo" specs/demo || fail "rebuild ref reconcile: non-zero exit"
cp "$tasks" "$ref"
# Flatten: keep preamble + human sections, dump all task blocks under a single
# Forward plan, delete the In progress / Completed structure.
flat=$tmp/flat.md
awk '
  BEGIN{ inpre=1; np=0; nb=0; curblk=""; nh=0 }
  /^## / && inpre { inpre=0 }
  inpre { pre[++np]=$0; next }
  /^### Task [0-9]/ { if(curblk!="") blk[++nb]=curblk; curblk=$0 "\n"; capt=1; next }
  /^### / { if(curblk!=""){blk[++nb]=curblk; curblk=""} capt=0; sec=""; next }
  /^## / {
    if(curblk!=""){blk[++nb]=curblk; curblk=""}
    sec=substr($0,4); capt=0
    if(sec=="Deferred"||sec=="Out of scope"||sec=="Awaiting input"){ hold=1; human[++nh]=$0 } else hold=0
    next
  }
  hold { human[++nh]=$0; next }
  capt { curblk=curblk $0 "\n"; next }
  { next }
  END{
    if(curblk!="") blk[++nb]=curblk
    for(i=1;i<=np;i++) print pre[i]
    print "## Forward plan\n"
    for(i=1;i<=nb;i++){ printf "%s\n", blk[i] }
    for(i=1;i<=nh;i++) print human[i]
  }
' "$tasks" >"$flat"
cp "$flat" "$tasks"
# All five blocks must still be present after the flatten (no data loss going in).
for id in 1 2 3 4 5; do
  grep -q "### Task $id " "$tasks" || fail "rebuild precondition: Task $id lost in the flatten"
done
reconcile "$repo" specs/demo || fail "rebuild reconcile: non-zero exit"
cmp -s "$tasks" "$ref" || {
  diff "$ref" "$tasks" || true
  fail "rebuild: flattened snapshot did not converge to the canonical placement (REQ-B1.3)"
}
echo "ok: a deleted/flattened snapshot rebuilds identically from truth (REQ-B1.3)"

# ===========================================================================
# 5. Conflict regeneration (REQ-C1.3): a tasks.md carrying git conflict markers
#    (Task 1 under Forward plan on one side, Completed on the other — a crafted
#    interleave that union/ours/theirs would mis-resolve, with a ||||||| diff3
#    base section in the first hunk) regenerates placement from the derivation
#    and leaves no markers (all four: <<<<<<<, |||||||, =======, >>>>>>>).
repo=$tmp/r4
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
ref=$tmp/ref5.md
reconcile "$repo" specs/demo || fail "conflict ref reconcile: non-zero exit"
cp "$tasks" "$ref"
# Hand-craft a conflict: the same Task 1 block appears on both sides of a
# conflict hunk, in different sections. Both sides carry identical definition
# content (a placement-only conflict).
conf=$tmp/conflict.md
cat >"$conf" <<'EOF'
# Demo — Tasks

**Status:** Active
**Last reviewed:** 2026-06-29
**Format-version:** 1

Intro prose is preserved verbatim across a reconcile. The dependency view is
derived; the `Dependencies:` lines are authoritative.

## Forward plan

<<<<<<< ours
### Task 1 — Widget core

- **Deliverables:** A widget core,
  wrapped onto a second line.
- **Done when:** Widgets exist.
- **Dependencies:** none
- **Citations:** REQ-X1.1
- **Estimated effort:** 1 day

||||||| base
### Task 1 — Widget core

- **Deliverables:** A widget core,
  wrapped onto a second line.
- **Done when:** Widgets exist.
- **Dependencies:** none
- **Citations:** REQ-X1.1
- **Estimated effort:** 1 day

=======
>>>>>>> theirs
### Task 2 — Widget parser

- **Deliverables:** A widget parser.
- **Done when:** Parses widgets.
- **Dependencies:** none
- **Citations:** REQ-X1.2
- **Estimated effort:** 1 day

### Task 3 — Widget polish

- **Deliverables:** Polish for widgets.
- **Done when:** Widgets shine.
- **Dependencies:** 1
- **Citations:** REQ-X1.3
- **Estimated effort:** half day

### Task 4 — Gadget integration

- **Deliverables:** Gadgets.
- **Done when:** Gadgets integrate.
- **Dependencies:** 2
- **Citations:** REQ-X1.4
- **Estimated effort:** 1 day

### Task 5 — Sprocket

- **Deliverables:** A sprocket.
- **Done when:** Sprocket spins.
- **Dependencies:** none
- **Citations:** REQ-X1.5
- **Estimated effort:** half day

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

<<<<<<< ours
=======
### Task 1 — Widget core

- **Deliverables:** A widget core,
  wrapped onto a second line.
- **Done when:** Widgets exist.
- **Dependencies:** none
- **Citations:** REQ-X1.1
- **Estimated effort:** 1 day
>>>>>>> theirs

## Deferred

- **A deferred idea.** Built later. **Gate:** when the moon is full.
  Confidence: low.

## Out of scope

- A permanent exclusion.
EOF
cp "$conf" "$tasks"
reconcile "$repo" specs/demo || fail "conflict reconcile: non-zero exit"
grep -qE '^(<{7}|={7}|>{7}|\|{7})' "$tasks" && fail "conflict: markers remain after reconcile (incl. ||||||| base)"
[ "$(section_of "$tasks" 1)" = "Completed" ] || fail "conflict: Task 1 not regenerated to Completed from truth"
# Exactly one Task 1 block survives (the duplicate from the two sides is deduped).
[ "$(grep -c '^### Task 1 ' "$tasks")" = 1 ] || fail "conflict: Task 1 block duplicated (not deduped)"
cmp -s "$tasks" "$ref" || {
  diff "$ref" "$tasks" || true
  fail "conflict: did not regenerate the canonical placement"
}
echo "ok: a conflicted tasks.md regenerates placement from truth, no ours/theirs/union (REQ-C1.3)"

# ===========================================================================
# 6. Sticky human sections: a task parked in ## Awaiting input is NOT relocated
#    by the derivation even though it derives ready/blocked.
repo=$tmp/r5
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
# Move Task 5 (derives ready) into Awaiting input by hand.
awk '
  BEGIN{ inblk=0; blk=""; printed=0 }
  /^### Task 5 / { inblk=1; blk=$0 "\n"; next }
  inblk && (/^## / || /^### /) { inblk=0 }
  inblk { blk=blk $0 "\n"; next }
  /^## Awaiting input/ { print; print ""; printf "%s", blk; next }
  { print }
' "$tasks" >"$tasks.new" && mv "$tasks.new" "$tasks"
[ "$(section_of "$tasks" 5)" = "Awaiting input" ] || fail "sticky precondition: Task 5 not parked in Awaiting input"
reconcile "$repo" specs/demo || fail "sticky reconcile: non-zero exit"
[ "$(section_of "$tasks" 5)" = "Awaiting input" ] \
  || fail "sticky: derivation pulled an Awaiting-input task back into Forward plan (human decision clobbered)"
echo "ok: a task parked in Awaiting input is sticky (not relocated by derivation)"

# ===========================================================================
# 7. Hook trigger: a `gh pr merge` on a convention branch triggers a full
#    reconcile of that spec (placement recomputed from truth).
repo=$tmp/r6
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
git -C "$repo" checkout -q planwright/demo/task-2
run_hook "$repo" "gh pr create --draft --title t --body b" "https://github.com/o/r/pull/12" \
  || fail "hook create: non-zero exit"
[ "$(section_of "$tasks" 1)" = "Completed" ] \
  || fail "hook: gh pr create did not trigger a full reconcile (Task 1 still mis-placed)"
[ "$(section_of "$tasks" 2)" = "In progress" ] \
  || fail "hook: Task 2 not in In progress after reconcile"
echo "ok: a gh pr create/merge event triggers a full level-triggered reconcile"

# 7b. Unrelated Bash commands and non-Bash tools write nothing (dispatch path
#     and the steady state write no placement — REQ-B1.1 sole-writer).
repo=$tmp/r6b
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
pristine=$tmp/pristine6b.md
cp "$tasks" "$pristine"
git -C "$repo" checkout -q planwright/demo/task-2
run_hook "$repo" "echo gh pr create" "gh pr create" || fail "mention: non-zero exit"
cmp -s "$tasks" "$pristine" || fail "mention: a non-invocation mention rewrote tasks.md"
(cd "$repo" && printf '{"tool_name":"Read","tool_input":{}}' | PATH="$stub:$PATH" "$SYNC") \
  || fail "non-Bash: non-zero exit"
cmp -s "$tasks" "$pristine" || fail "non-Bash tool rewrote tasks.md"
echo "ok: unrelated commands / non-Bash tools write no placement"

# ===========================================================================
# 8. Worker sessions: a hook run inside a linked worktree reconciles the
#    PRIMARY checkout's tasks.md, not the worktree copy (risk row 3).
repo=$tmp/r7
make_repo "$repo"
wt=$repo/.claude/worktrees/task-2
git -C "$repo" worktree add -q "$wt" planwright/demo/task-2
cp "$wt/specs/demo/tasks.md" "$tmp/wt-pristine.md"
run_hook "$wt" "gh pr create --draft" "https://github.com/o/r/pull/12" \
  || fail "worktree: non-zero exit"
[ "$(section_of "$repo/specs/demo/tasks.md" 1)" = "Completed" ] \
  || fail "worktree: primary checkout tasks.md not reconciled"
cmp -s "$wt/specs/demo/tasks.md" "$tmp/wt-pristine.md" \
  || fail "worktree: hook wrote the worktree copy instead of the primary's"
echo "ok: a worktree run reconciles the primary checkout"

# ===========================================================================
# 9. Advisory lock (REQ-D1.1, REQ-D1.2): a lock held via the shared primitive
#    excludes the hook (clean no-op); the hook delegates to the one primitive
#    and carries no inline stale-break.
repo=$tmp/r8
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
pristine8=$tmp/pristine8.md
cp "$tasks" "$pristine8"
git -C "$repo" checkout -q planwright/demo/task-2
/bin/bash "$LOCKSH" acquire "$repo/specs/demo" || fail "exclusion: primitive acquire failed"
run_hook "$repo" "gh pr create --draft" "https://github.com/o/r/pull/12" \
  || fail "exclusion: hook non-zero while primitive holds the lock"
cmp -s "$tasks" "$pristine8" || fail "exclusion: hook reconciled while the lock was held"
/bin/bash "$LOCKSH" release "$repo/specs/demo"
grep -q 'orchestrate-lock.sh' "$SYNC" || fail "REQ-D1.1: script does not reference the shared lock primitive"
grep -Eq 'find[[:space:]].*-maxdepth 0 -mmin' "$SYNC" \
  && fail "REQ-D1.1: script still carries inline stale-break logic (duplication)"
echo "ok: a lock held via the shared primitive excludes the hook (REQ-D1.2); no inline lock"

# 9b. A busy (fresh) lock is a clean no-op; a stale lock is broken and the
#     reconcile proceeds.
repo=$tmp/r9
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
pristine9=$tmp/pristine9.md
cp "$tasks" "$pristine9"
git -C "$repo" checkout -q planwright/demo/task-2
mkdir "$repo/specs/demo/.orchestrate.lock"
run_hook "$repo" "gh pr create --draft" "https://github.com/o/r/pull/12" || fail "busy lock: non-zero exit"
cmp -s "$tasks" "$pristine9" || fail "busy lock: hook reconciled instead of skipping"
touch -t 202001010000 "$repo/specs/demo/.orchestrate.lock"
run_hook "$repo" "gh pr create --draft" "https://github.com/o/r/pull/12" || fail "stale lock: non-zero exit"
[ "$(section_of "$tasks" 1)" = "Completed" ] || fail "stale lock: not broken at the default threshold"
[ ! -d "$repo/specs/demo/.orchestrate.lock" ] || fail "stale lock: lock not released"
echo "ok: busy lock no-ops, stale lock breaks"

# 9c. Missing lock primitive beside the hook → clean fail-soft no-op (REQ-D1.1).
repo=$tmp/r10
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
pristine10=$tmp/pristine10.md
cp "$tasks" "$pristine10"
git -C "$repo" checkout -q planwright/demo/task-2
nolockdir=$tmp/nolock
mkdir -p "$nolockdir"
cp "$SYNC" "$nolockdir/tasks-pr-sync.sh"
chmod +x "$nolockdir/tasks-pr-sync.sh"
err=$(
  cd "$repo" \
    && printf '{"tool_name":"Bash","tool_input":{"command":"gh pr create --draft"},"tool_response":{"stdout":"https://github.com/o/r/pull/12","stderr":""}}' \
    | PATH="$stub:$PATH" "$nolockdir/tasks-pr-sync.sh" 2>&1 >/dev/null
) || fail "missing primitive: non-zero exit (should be a fail-soft no-op)"
cmp -s "$tasks" "$pristine10" || fail "missing primitive: hook reconciled without the lock"
case $err in
  *"missing or not executable"*) ;;
  *) fail "missing primitive: no broken-install diagnostic (got: $err)" ;;
esac
echo "ok: a missing lock primitive is a clean fail-soft no-op (REQ-D1.1)"

# ===========================================================================
# 10. Hostile / containment (REQ-F1.1): hostile branch names and an out-of-tree
#     (symlinked) spec dir are clean no-ops via both entry points.
repo=$tmp/r11
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
pristine11=$tmp/pristine11.md
cp "$tasks" "$pristine11"
for b in \
  main \
  planwright/Bad_Spec/task-2 \
  planwright/demo/task-.5 \
  "planwright/demo/task-2;x" \
  planwright/a/b/task-2 \
  planwright/demo/spec; do
  git -C "$repo" checkout -q main
  git -C "$repo" branch -q "$b" 2>/dev/null || true
  git -C "$repo" checkout -q "$b" 2>/dev/null || fail "fixture branch not creatable: $b"
  run_hook "$repo" "gh pr create --draft" "https://github.com/o/r/pull/12" \
    || fail "hostile branch $b: non-zero exit"
  cmp -s "$tasks" "$pristine11" || fail "hostile branch $b: tasks.md changed"
done
git -C "$repo" checkout -q main
echo "ok: hostile / reserved branch names are clean no-ops"

# 10b. Containment: a charset-clean spec whose directory symlinks outside
#      <primary>/specs/ is rejected by the direct CLI form.
outside=$tmp/outside
write_spec "$outside"
cp "$outside/tasks.md" "$tmp/outside-pristine.md"
ln -s "$outside" "$repo/specs/evil"
reconcile "$repo" specs/evil 2>/dev/null || true
cmp -s "$outside/tasks.md" "$tmp/outside-pristine.md" \
  || fail "containment: reconcile wrote through a symlinked spec dir"
echo "ok: a symlinked (out-of-tree) spec dir is containment-rejected"

# 10c. The direct CLI rejects a missing / non-spec dir (fail closed).
reconcile "$repo" specs/nope 2>/dev/null && fail "missing spec dir: reconcile should fail closed"
echo "ok: reconcile fails closed on a missing spec dir"

# 10d. The direct CLI fails closed on a hostile spec id (REQ-F1.1): the shared
#      lock primitive refuses a spec dir whose basename fails the grammar, so the
#      reconcile returns non-zero and never writes.
repo=$tmp/r11d
make_repo "$repo"
mkdir -p "$repo/specs/Bad_Spec"
cp "$repo/specs/demo/tasks.md" "$repo/specs/Bad_Spec/tasks.md"
cp "$repo/specs/Bad_Spec/tasks.md" "$tmp/bad-pristine.md"
reconcile "$repo" specs/Bad_Spec 2>/dev/null \
  && fail "hostile spec id: reconcile should fail closed (non-zero)"
cmp -s "$repo/specs/Bad_Spec/tasks.md" "$tmp/bad-pristine.md" \
  || fail "hostile spec id: reconcile wrote despite the grammar refusal"
echo "ok: CLI reconcile fails closed on a hostile spec id, writes nothing"

# 10e. The direct CLI fails closed on a symlinked tasks.md. The preflight uses
#      `-f` (which follows the link), and do_placement refuses the `-L` file and
#      returns 1 — but run_reconcile masks that with `|| true`, so without an
#      explicit CLI-side refusal the caller would see exit 0 (a silent skip)
#      despite the documented fail-closed contract. Assert non-zero + no write.
repo=$tmp/r11e
make_repo "$repo"
mv "$repo/specs/demo/tasks.md" "$repo/specs/demo/tasks.real.md"
ln -s tasks.real.md "$repo/specs/demo/tasks.md"
cp "$repo/specs/demo/tasks.real.md" "$tmp/symlink-pristine.md"
reconcile "$repo" specs/demo 2>/dev/null \
  && fail "symlinked tasks.md: CLI should fail closed (non-zero exit)"
cmp -s "$repo/specs/demo/tasks.real.md" "$tmp/symlink-pristine.md" \
  || fail "symlinked tasks.md: CLI wrote through the symlink target"
echo "ok: CLI reconcile fails closed on a symlinked tasks.md, writes nothing"

# ===========================================================================
# 11. Atomic write (REQ-B1.1): the write goes to a same-directory temp and is
#     renamed into place. The atomicity of rename-on-the-same-filesystem is a
#     property of mv; ground it with a source audit (the same shape as the
#     REQ-D1.1 inline-lock audit above) plus the no-leftover-temp check in test 1.
# shellcheck disable=SC2016 # the $-tokens are literal source strings to grep for, not expansions
grep -q 'mktemp "$dp_dir/.tasks-pr-sync' "$SYNC" \
  || fail "atomic write: the temp is not created in the spec dir (same-filesystem rename)"
# shellcheck disable=SC2016 # the $-tokens are literal source strings to grep for, not expansions
grep -q 'mv "$tmpf" "$dp_tasks"' "$SYNC" \
  || fail "atomic write: tasks.md is not written by renaming the temp into place"
echo "ok: the snapshot write is a same-dir temp renamed into place (REQ-B1.1 atomic)"

# 11b. The rename is failure-checked. Without set -e, a bare `mv` that fails
#      (read-only dir, ENOSPC at rename, etc.) would still log "reconciled" and
#      return 0 while leaking the temp — a silent failure-as-success. Same
#      source-audit shape as 11 (mv atomicity is a property of mv, grounded by
#      reading the source): assert the rename sits in a conditional, not a bare
#      statement.
# shellcheck disable=SC2016 # the $-tokens are literal source strings to grep for, not expansions
grep -q 'if mv "$tmpf" "$dp_tasks"' "$SYNC" \
  || fail "atomic write: the rename is unchecked (a failed mv would log success and leak the temp)"
echo "ok: the snapshot rename is failure-checked (REQ-B1.1)"

# ===========================================================================
# 12. Dotted task id (D-36 blessed: 2.5) is placed end-to-end by the reconcile
#     (the placement engine and the derivation both accept the dotted grammar).
repo=$tmp/r12
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
awk '
  /^## In progress/ && !done {
    print "### Task 2.5 — Dotted"
    print ""
    print "- **Deliverables:** Dotted thing."
    print "- **Done when:** Dotted done."
    print "- **Dependencies:** none"
    print "- **Citations:** REQ-X1.6"
    print "- **Estimated effort:** half day"
    print ""
    done = 1
  }
  { print }
' "$tasks" >"$tasks.n" && mv "$tasks.n" "$tasks"
git -C "$repo" commit -q --allow-empty -m "feat: 2.5

Planwright-Task: demo/2.5"
reconcile "$repo" specs/demo || fail "dotted reconcile: non-zero exit"
[ "$(section_of "$tasks" 2.5)" = "Completed" ] || fail "dotted: Task 2.5 not placed in Completed"
block_of "$tasks" 2.5 | grep -q -- '- \*\*Done when:\*\* Dotted done\.' \
  || fail "dotted: definition content lost in the move"
echo "ok: a dotted task id (2.5) is placed end-to-end by the reconcile"

# ===========================================================================
# 13. Derivation diagnostic records (refused / degraded / contradiction /
#     malformed-deps) are tolerated: the reconcile keeps only `task` records, so
#     a diagnostic record on the derivation stream never corrupts placement.
repo=$tmp/r13
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
# A hostile Planwright-Task trailer on base makes the derivation emit a `refused`
# record (the value is refused, never matched to a task).
git -C "$repo" commit -q --allow-empty -m "hostile trailer

Planwright-Task: ../evil/1"
# Capture the full stream to a file (rather than piping into grep -q, which would
# SIGPIPE the deriver mid-emit) so the precondition reads the whole record set.
(cd "$repo" && "$STATE" specs/demo) >"$tmp/state13.out" 2>/dev/null
grep -qE '^(refused|degraded|contradiction|malformed-deps)' "$tmp/state13.out" \
  || fail "diagnostic precondition: derivation emitted no diagnostic record"
reconcile "$repo" specs/demo || fail "diagnostic reconcile: non-zero exit"
[ "$(section_of "$tasks" 1)" = "Completed" ] || fail "diagnostic: a diagnostic record broke placement"
[ "$(section_of "$tasks" 2)" = "In progress" ] || fail "diagnostic: Task 2 mis-placed"
echo "ok: derivation diagnostic records are filtered out; placement unaffected"

# ===========================================================================
# 14. Sticky-under-completed: a task parked in ## Awaiting input with COMPLETED
#     evidence (its Planwright-Task trailer) stays put. The human-owned sections
#     are fully sticky — the derivation never overrides a human park, in any
#     state — so a completed-but-parked task is not yanked to ## Completed.
repo=$tmp/r14
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
awk '
  BEGIN { blk = ""; inblk = 0 }
  /^### Task 1 / { inblk = 1; blk = $0 "\n"; next }
  inblk && (/^## / || /^### /) { inblk = 0 }
  inblk { blk = blk $0 "\n"; next }
  /^## Awaiting input/ { print; print ""; printf "%s", blk; next }
  { print }
' "$tasks" >"$tasks.n" && mv "$tasks.n" "$tasks"
[ "$(section_of "$tasks" 1)" = "Awaiting input" ] \
  || fail "sticky-completed precondition: Task 1 not parked in Awaiting input"
reconcile "$repo" specs/demo || fail "sticky-completed reconcile: non-zero exit"
[ "$(section_of "$tasks" 1)" = "Awaiting input" ] \
  || fail "sticky-completed: a completed-evidence task was pulled out of Awaiting input"
echo "ok: Awaiting input is fully sticky even under completed evidence"

# ===========================================================================
# 15. Concurrent reconcile (REQ-B1.1 atomic write, Done-when "a racy stale
#     lock-break cannot tear tasks.md under concurrent reconcile"). Test 11
#     audits the atomic-write SOURCE; this is the behavioral complement: fire
#     several reconciles at the same spec at once and assert the settled file is
#     the canonical placement, byte-identical to a lone run, with no torn output
#     and no temp left behind. The per-spec lock serializes the writers and the
#     same-dir-temp-then-rename keeps every observer's view whole; because the
#     placement is idempotent, whichever writer wins, the final bytes are the
#     same — so the assertions on the settled state are deterministic, not racy.
repo=$tmp/r15
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
# Capture the un-reconciled fixture (every task under ## Forward plan, the human
# sections intact), then the lone-run canonical, then restore the fixture so the
# concurrent run has real convergence work rather than an instant no-op.
pristine15=$tmp/pristine15.md
cp "$tasks" "$pristine15"
ref15=$tmp/ref15.md
reconcile "$repo" specs/demo || fail "concurrent: reference reconcile non-zero"
cp "$tasks" "$ref15"
cmp -s "$pristine15" "$ref15" && fail "concurrent: fixture already canonical (test would be a vacuous no-op)"
cp "$pristine15" "$tasks"
# Fire N reconciles concurrently; wait for all to settle before asserting.
pids=""
for _ in 1 2 3 4 5 6; do
  (cd "$repo" && PATH="$stub:$PATH" "$SYNC" reconcile specs/demo >/dev/null 2>&1) &
  pids="$pids $!"
done
crc=0
for p in $pids; do
  wait "$p" || crc=1
done
[ "$crc" = 0 ] || fail "concurrent: a reconcile exited non-zero under contention"
cmp -s "$tasks" "$ref15" \
  || {
    diff "$ref15" "$tasks" || true
    fail "concurrent: settled tasks.md is not the canonical placement (torn or lost-update)"
  }
ls "$repo/specs/demo"/.tasks-pr-sync.* >/dev/null 2>&1 \
  && fail "concurrent: a temp file was left behind"
[ ! -d "$repo/specs/demo/.orchestrate.lock" ] || fail "concurrent: the advisory lock was not released"
echo "ok: concurrent reconciles settle on the canonical placement, no torn write, no temp/lock left"

# ===========================================================================
# 16. Unknown section preservation: a `## ` section the format does not define
#     (and any `### Task` block inside it) is preserved without data loss —
#     nothing is silently dropped or yanked into the triad. Exercises the
#     emit_human path for `oth[]` (unknown sections are sticky like the
#     human-owned ones), which no other case covers.
repo=$tmp/r16
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
# Inject an unknown ## Suspended section (with body) and an orphan Task 9 (no
# evidence anywhere, so the derivation emits no state for it).
awk '
  /^## Out of scope/ && !inj {
    print "## Suspended"
    print ""
    print "- A custom note the format does not define."
    print ""
    print "### Task 9 — Orphan with no derived state"
    print ""
    print "- **Deliverables:** An orphan."
    print "- **Done when:** Never (no evidence)."
    print "- **Dependencies:** none"
    print "- **Citations:** REQ-X9.9"
    print "- **Estimated effort:** half day"
    print ""
    inj = 1
  }
  { print }
' "$tasks" >"$tasks.n" && mv "$tasks.n" "$tasks"
reconcile "$repo" specs/demo || fail "unknown-section reconcile: non-zero exit"
grep -q '^## Suspended' "$tasks" || fail "unknown section: ## Suspended dropped"
grep -q 'A custom note the format does not define\.' "$tasks" \
  || fail "unknown section: body silently dropped"
# Task 9 lives inside ## Suspended (an unknown, body-preserved section), so the
# derivation never relocates it: assert it stays under Suspended with its
# definition intact rather than being pulled into a triad section.
section9=$(section_of "$tasks" 9)
[ "$section9" = "Suspended" ] \
  || fail "unknown section: orphan Task 9 not preserved under ## Suspended (got '$section9')"
block_of "$tasks" 9 | grep -q -- '- \*\*Done when:\*\* Never (no evidence)\.' \
  || fail "unknown section: orphan Task 9 definition lost"
echo "ok: an unknown ## section and its blocks are preserved without data loss, nothing dropped"

# ===========================================================================
# 17. Merge-from-non-convention-branch fallback: `gh pr merge <n>` often runs off
#     the head branch (e.g. on main), so the hook resolves the spec via the PR's
#     headRefName (scraped PR number → `gh pr view --json headRefName`). The gh
#     stub answers headRefName from GH_HEADREF; this drives that fallback end to
#     end and asserts the resolved spec reconciles. Without it, the branch-
#     resolution fallback (and its GH_HEADREF scaffolding) is dead, easy to
#     regress unnoticed.
repo=$tmp/r17
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
# Run on main (make_repo leaves HEAD there): the branch is non-convention, so the
# hook must fall back to the PR's headRefName to learn the spec. The merge payload
# carries a PR URL the hook scrapes for the number; the stub maps it to a
# convention branch via GH_HEADREF.
git -C "$repo" rev-parse --abbrev-ref HEAD | grep -qx main \
  || fail "fallback precondition: fixture HEAD is not on a non-convention branch"
export GH_HEADREF=planwright/demo/task-2
run_hook "$repo" "gh pr merge 12 --squash" "https://github.com/o/r/pull/12" \
  || fail "headRefName fallback: hook returned non-zero"
unset GH_HEADREF
# The fallback fired only if the spec was resolved and reconciled: Task 1
# (completed evidence) must have moved from its start section into ## Completed.
[ "$(section_of "$tasks" 1)" = "Completed" ] \
  || fail "headRefName fallback: spec not reconciled via GH_HEADREF (Task 1 not in Completed)"
# Negative guard: with no headRefName resolvable, the fallback yields no spec and
# the hook is a clean no-op (a fresh repo whose snapshot stays put).
repo=$tmp/r17b
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
cp "$tasks" "$tmp/r17b-pristine.md"
run_hook "$repo" "gh pr merge 12 --squash" "https://github.com/o/r/pull/12" \
  || fail "no-headRefName fallback: hook returned non-zero"
cmp -s "$tasks" "$tmp/r17b-pristine.md" \
  || fail "no-headRefName fallback: hook reconciled despite an unresolvable head ref"
echo "ok: gh pr merge off a non-convention branch reconciles the spec resolved via headRefName"

# ===========================================================================
# 18. Leading non-canonical section preserved IN PLACE. A `## ` section that
#     precedes the first canonical state-section (e.g. a top-of-file
#     `## Dependency graph`, as specs/bootstrap/tasks.md carries) is part of the
#     preamble: it must stay at the top, not be relocated to the end with the
#     other unknown sections (test 16 covers the after-the-canonical-set case).
repo=$tmp/r18
make_repo "$repo"
tasks=$repo/specs/demo/tasks.md
awk '
  /^## Forward plan/ && !inj {
    print "## Dependency graph"
    print ""
    print "- Task 2 blocks Task 4."
    print ""
    inj = 1
  }
  { print }
' "$tasks" >"$tasks.n" && mv "$tasks.n" "$tasks"
reconcile "$repo" specs/demo || fail "leading non-canonical: reconcile non-zero exit"
dg_line=$(grep -n '^## Dependency graph' "$tasks" | head -1 | cut -d: -f1)
fp_line=$(grep -n '^## Forward plan' "$tasks" | head -1 | cut -d: -f1)
[ -n "$dg_line" ] || fail "leading non-canonical: ## Dependency graph dropped"
[ -n "$fp_line" ] && [ "$dg_line" -lt "$fp_line" ] \
  || fail "leading non-canonical: ## Dependency graph relocated below the canonical sections (dg=$dg_line fp=$fp_line)"
grep -q 'Task 2 blocks Task 4\.' "$tasks" || fail "leading non-canonical: body lost"
# Placement still works for the real tasks below it.
[ "$(section_of "$tasks" 1)" = "Completed" ] || fail "leading non-canonical: Task 1 not placed in Completed"
echo "ok: a leading non-canonical section is preserved in place above the canonical set"

# ===========================================================================
# Task 6 (kickoff-lifecycle REQ-A1.5, REQ-C1.2): the reconcile derives and
# writes the bundle **Status:** header, mirrored across the four files. The
# derivation (Done > Active > Ready, all from task-state evidence):
#   * Active  iff at least one task derives In-progress or Completed;
#   * Ready   otherwise (signed off, no progress, startable work remains);
#   * Done    iff no Forward-plan / In-progress / Awaiting-input task remains
#             (every task is Completed, Deferred, or Out-of-scope, or there are
#             none) — Done takes precedence over Ready/Active.
# The reconcile is the sole writer of the *derived* header value and reconciles
# the {Ready, Active} set outright, plus Done only to complete a partially-applied
# Done mirror: the one-time Draft->Ready flip is the human-gated /spec-kickoff
# write (not derived, D-2/REQ-A1.4); Retired / Superseded are left untouched; and
# a stored-Done bundle is never reopened to Ready/Active by the reconcile (the
# reopen Done->Draft is the human's, REQ-A1.6).

# k6_init <repo>: a fresh git repo with deterministic identity.
k6_init() {
  mkdir -p "$1"
  git -C "$1" init -q -b main
  git -C "$1" config user.email t@example.com
  git -C "$1" config user.name t
  git -C "$1" config commit.gpgsign false
}
# k6_heads <spec-dir> <status>: write requirements/design/test-spec with the
# bundle Status mirrored across all three. tasks.md is written per-scenario.
k6_heads() {
  mkdir -p "$1"
  printf '%s\n' '# K6 — Requirements' '' "**Status:** $2" '**Format-version:** 1' >"$1/requirements.md"
  printf '%s\n' '# K6 — Design' '' "**Status:** $2" '**Format-version:** 1' >"$1/design.md"
  printf '%s\n' '# K6 — Test Spec' '' "**Status:** $2" '**Format-version:** 1' >"$1/test-spec.md"
}
k6_status_of() { awk '/^\*\*Status:\*\* / { print $2; exit }' "$1"; }
k6_assert_all() { # <spec-dir> <expected> <label>
  for f in requirements.md design.md tasks.md test-spec.md; do
    got=$(k6_status_of "$1/$f")
    [ "$got" = "$2" ] || fail "$3: $f Status=$got, expected $2"
  done
}
# A standard two-task tasks.md body (both under Forward plan). $1 = spec-dir,
# $2 = status, $3 = an extra annotation line for Task 1 (or empty).
k6_two_task_tasks() { # <spec-dir> <status> <task1-annotation>
  {
    printf '%s\n' '# K6 — Tasks' '' "**Status:** $2" '**Format-version:** 1' ''
    printf '%s\n' '## Forward plan' ''
    printf '%s\n' '### Task 1 — Alpha' ''
    [ -n "$3" ] && printf '%s\n' "$3"
    printf '%s\n' '- **Deliverables:** Alpha.' '- **Done when:** Alpha done.' \
      '- **Dependencies:** none' '- **Citations:** REQ-K1.1' '- **Estimated effort:** 1 day' ''
    printf '%s\n' '### Task 2 — Beta' ''
    printf '%s\n' '- **Deliverables:** Beta.' '- **Done when:** Beta done.' \
      '- **Dependencies:** none' '- **Citations:** REQ-K1.2' '- **Estimated effort:** 1 day' ''
    printf '%s\n' '## In progress' '' '(none yet)' ''
    printf '%s\n' '## Awaiting input' '' '(none yet)' ''
    printf '%s\n' '## Completed' '' '(none yet)'
  } >"$1/tasks.md"
}

# --- T-A: no progress, stored Ready -> stays Ready (REQ-A1.5 no-progress arm).
repo=$tmp/k6a
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Ready
k6_two_task_tasks "$sd" Ready ""
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
reconcile "$repo" specs/kl || fail "k6-A reconcile non-zero"
k6_assert_all "$sd" Ready "REQ-A1.5 no progress stays Ready"
echo "ok: reconcile keeps a signed-off bundle with no progress at Ready (REQ-A1.5)"

# --- T-B: one In-progress, stored Ready -> Active, mirrored to four files; the
# derivation engine (the /orchestrate read path) writes nothing (REQ-C1.2). A
# task-level `- **Status:**` annotation must survive the header rewrite.
repo=$tmp/k6b
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Ready
k6_two_task_tasks "$sd" Ready '- **Status:** implementing'
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
git -C "$repo" branch planwright/kl/task-1
git -C "$repo" checkout -q planwright/kl/task-1
git -C "$repo" commit -q --allow-empty -m "wip: task 1"
git -C "$repo" checkout -q main
before=$(k6_status_of "$sd/requirements.md")
(cd "$repo" && PATH="$stub:$PATH" "$STATE" specs/kl >/dev/null) || fail "k6-B derivation non-zero"
[ "$(k6_status_of "$sd/requirements.md")" = "$before" ] \
  || fail "REQ-C1.2: orchestrate-state.sh (the /orchestrate derivation path) wrote the Status header"
reconcile "$repo" specs/kl || fail "k6-B reconcile non-zero"
k6_assert_all "$sd" Active "REQ-C1.2 Ready->Active on first in-progress evidence"
grep -q -- '- \*\*Status:\*\* implementing' "$sd/tasks.md" \
  || fail "REQ-C1.2: header rewrite clobbered a task-level - **Status:** annotation"
echo "ok: reconcile derives Ready->Active on first in-progress evidence, mirrored across four files; /orchestrate's derivation path writes nothing; task annotations survive (REQ-C1.2)"

# --- T-C: one Completed (rest Forward), stored Active -> stays Active. Proves a
# Completed task alone counts as progress (REQ-A1.5).
repo=$tmp/k6c
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Active
k6_two_task_tasks "$sd" Active ""
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
git -C "$repo" commit -q --allow-empty -m "feat: task 1 done

Planwright-Task: kl/1"
reconcile "$repo" specs/kl || fail "k6-C reconcile non-zero"
k6_assert_all "$sd" Active "REQ-A1.5 one completed stays Active"
echo "ok: reconcile keeps Active when one task is completed and work remains (REQ-A1.5)"

# --- T-D: all Completed, stored Active -> Done; second run is a no-op on the
# header (idempotent, REQ-A1.5 Done precedence).
repo=$tmp/k6d
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Active
k6_two_task_tasks "$sd" Active ""
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
git -C "$repo" commit -q --allow-empty -m "feat: task 1 done

Planwright-Task: kl/1"
git -C "$repo" commit -q --allow-empty -m "feat: task 2 done

Planwright-Task: kl/2"
reconcile "$repo" specs/kl || fail "k6-D reconcile non-zero"
k6_assert_all "$sd" Done "REQ-A1.5 all completed -> Done"
# Idempotency is a four-file property (do_status mirrors all four): snapshot and
# cmp every file, so a second-run rewrite of any sibling (not just requirements.md)
# is caught.
snap=$tmp/k6d-snap
mkdir -p "$snap"
for f in requirements.md design.md tasks.md test-spec.md; do cp "$sd/$f" "$snap/$f"; done
reconcile "$repo" specs/kl || fail "k6-D second reconcile non-zero"
for f in requirements.md design.md tasks.md test-spec.md; do
  cmp -s "$sd/$f" "$snap/$f" || fail "REQ-A1.5: status reconcile not idempotent (second run rewrote $f)"
done
echo "ok: reconcile derives Active->Done when all tasks complete; idempotent across all four files (REQ-A1.5)"

# --- T-E: no startable tasks (only Deferred / Out of scope blocks), stored
# Ready -> Done (REQ-A1.5 "no startable work" arm, Done precedence).
repo=$tmp/k6e
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Ready
{
  printf '%s\n' '# K6 — Tasks' '' '**Status:** Ready' '**Format-version:** 1' ''
  printf '%s\n' '## Forward plan' '' '(none yet)' ''
  printf '%s\n' '## In progress' '' '(none yet)' ''
  printf '%s\n' '## Awaiting input' '' '(none yet)' ''
  printf '%s\n' '## Completed' '' '(none yet)' ''
  printf '%s\n' '## Deferred' ''
  printf '%s\n' '### Task 1 — Alpha' ''
  printf '%s\n' '- **Deliverables:** Alpha.' '- **Done when:** Alpha done.' \
    '- **Dependencies:** none' '- **Citations:** REQ-K1.1' '- **Estimated effort:** 1 day' ''
  printf '%s\n' '## Out of scope' ''
  printf '%s\n' '### Task 2 — Beta' ''
  printf '%s\n' '- **Deliverables:** Beta.' '- **Done when:** Beta done.' \
    '- **Dependencies:** none' '- **Citations:** REQ-K1.2' '- **Estimated effort:** 1 day'
} >"$sd/tasks.md"
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
reconcile "$repo" specs/kl || fail "k6-E reconcile non-zero"
k6_assert_all "$sd" Done "REQ-A1.5 no startable tasks -> Done"
echo "ok: reconcile derives Done for a signed-off bundle with no startable tasks (REQ-A1.5)"

# --- T-F: a task parked in Awaiting input counts as pending, stored Ready ->
# stays Ready (not Done). Distinguishes Awaiting-input from Deferred/Out-of-scope.
repo=$tmp/k6f
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Ready
{
  printf '%s\n' '# K6 — Tasks' '' '**Status:** Ready' '**Format-version:** 1' ''
  printf '%s\n' '## Forward plan' '' '(none yet)' ''
  printf '%s\n' '## In progress' '' '(none yet)' ''
  printf '%s\n' '## Awaiting input' ''
  printf '%s\n' '### Task 1 — Alpha' ''
  printf '%s\n' '- **Deliverables:** Alpha.' '- **Done when:** Alpha done.' \
    '- **Dependencies:** none' '- **Citations:** REQ-K1.1' '- **Estimated effort:** 1 day' ''
  printf '%s\n' '## Completed' '' '(none yet)'
} >"$sd/tasks.md"
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
reconcile "$repo" specs/kl || fail "k6-F reconcile non-zero"
k6_assert_all "$sd" Ready "REQ-A1.5 Awaiting-input task keeps Ready (pending, not Done)"
echo "ok: an Awaiting-input task is pending (keeps Ready), not parked like Deferred/Out-of-scope (REQ-A1.5)"

# --- T-G: owned-set guard. Stored Draft with in-progress evidence is NOT
# flipped (Draft->Ready is the human-gated kickoff write, never derived;
# D-2 / REQ-A1.4).
repo=$tmp/k6g
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Draft
k6_two_task_tasks "$sd" Draft ""
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
git -C "$repo" branch planwright/kl/task-1
git -C "$repo" checkout -q planwright/kl/task-1
git -C "$repo" commit -q --allow-empty -m "wip: task 1"
git -C "$repo" checkout -q main
reconcile "$repo" specs/kl || fail "k6-G reconcile non-zero"
k6_assert_all "$sd" Draft "REQ-A1.4 Draft is never derived to Active by the reconcile"
echo "ok: the reconcile never derives a Draft bundle's Status (Draft->Ready is human-gated, REQ-A1.4)"

# --- T-H: owned-set guard. Stored Superseded (terminal) and Done are left
# untouched even with reopening evidence (REQ-A1.5 / REQ-A1.6: the reopen is the
# human's Done->Draft, not a derived flip).
for st in Superseded Done; do
  repo=$tmp/k6h-$st
  k6_init "$repo"
  sd="$repo/specs/kl"
  k6_heads "$sd" "$st"
  k6_two_task_tasks "$sd" "$st" ""
  git -C "$repo" add -A
  git -C "$repo" commit -qm fixture
  git -C "$repo" branch planwright/kl/task-1
  git -C "$repo" checkout -q planwright/kl/task-1
  git -C "$repo" commit -q --allow-empty -m "wip: task 1"
  git -C "$repo" checkout -q main
  reconcile "$repo" specs/kl || fail "k6-H($st) reconcile non-zero"
  k6_assert_all "$sd" "$st" "REQ-A1.5 $st is left untouched by the reconcile"
done
echo "ok: the reconcile leaves Done and terminal (Superseded) bundles untouched (REQ-A1.5/A1.6)"

# --- T-I: single-writer code audit (REQ-A1.5). tasks-pr-sync.sh is the only
# script that EMITS a derived bundle Status header; spec-validate.sh only READS
# it, and the /orchestrate path (orchestrate-select / orchestrate-state) never
# writes it. One sanctioned exception: migrate-format-version.sh emits the
# stored header once at the v1→v2 migration (the Active → Ready restriction,
# invariant-tasks D-10, REQ-D1.2) — a one-shot human-gated restriction, not a
# derived reconcile value, and it cannot delegate to the single writer because
# that writer correctly no-ops on v2 bundles (invariant-tasks REQ-C1.1).
# Quote-agnostic on purpose: a print/printf/echo that emits the literal header
# string in EITHER single or double quotes counts as an emitter, so a future
# writer using `printf '**Status:** %s\n'` (single-quoted) cannot bypass the
# guard. Readers (`awk '/^**Status:** /{print $2}'`) are not matched because the
# quoted literal there precedes, not follows, the print token.
emit='\*\*Status:\*\* '
writers=""
for s in "$here"/../scripts/*.sh; do
  grep -qE "(print|printf|echo).*['\"]$emit" "$s" && writers="$writers $(basename "$s")"
done
writers=$(printf '%s' "$writers" | sed 's/^ //')
[ "$writers" = "migrate-format-version.sh tasks-pr-sync.sh" ] \
  || fail "single-writer audit: scripts emitting a Status header = '$writers', expected only migrate-format-version.sh (the one-shot v2 migration, D-10) and tasks-pr-sync.sh"
grep -q '\*\*Status:\*\*' "$here/../scripts/orchestrate-select.sh" \
  && fail "single-writer audit: orchestrate-select.sh references the Status header (should not touch it)"
echo "ok: tasks-pr-sync.sh is the sole writer of the bundle Status header (REQ-A1.5 single-writer)"

# --- T-J: write_status_header refuses a symlinked status file. A spec file
# symlinked elsewhere (here design.md) is refused by the status writer: its
# target is left untouched and a diagnostic is logged, while the other three
# files still mirror the derived value (the per-file write is best-effort, so one
# refused file does not abort the mirror). Complements the tasks.md symlink-
# refusal tests (10e) for the four status-header files specifically.
repo=$tmp/k6j
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Ready
k6_two_task_tasks "$sd" Ready ""
# design.md is a symlink to a real target carrying the (stale) Ready header.
mv "$sd/design.md" "$sd/design.real.md"
ln -s design.real.md "$sd/design.md"
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
# In-progress evidence flips the derivation Ready->Active.
git -C "$repo" branch planwright/kl/task-1
git -C "$repo" checkout -q planwright/kl/task-1
git -C "$repo" commit -q --allow-empty -m "wip: task 1"
git -C "$repo" checkout -q main
err=$(reconcile "$repo" specs/kl 2>&1) || fail "k6-J reconcile non-zero"
for f in requirements.md tasks.md test-spec.md; do
  [ "$(k6_status_of "$sd/$f")" = Active ] || fail "k6-J: $f not mirrored to Active around a refused symlink"
done
[ "$(k6_status_of "$sd/design.real.md")" = Ready ] \
  || fail "k6-J: write_status_header wrote through the symlinked design.md"
[ -L "$sd/design.md" ] || fail "k6-J: the design.md symlink was replaced (write went through the link)"
case $err in
  *"refusing symlinked"*) ;;
  *) fail "k6-J: no symlink-refusal diagnostic emitted (got: $err)" ;;
esac
echo "ok: write_status_header refuses a symlinked status file and mirrors the rest (best-effort)"

# --- T-K: a partial four-file Status mirror self-heals on the next reconcile.
# The mirror is not group-atomic (a per-file refusal/failure leaves dst_rc=1 and
# a de-synced file); the level-triggered reconcile converges every file on a
# subsequent run (REQ-A1.5 idempotent/self-healing, mirroring the placement
# self-heal). Here design.md is hand-desynced to Ready while the rest read
# Active; a reconcile that derives Active must pull design.md back into line.
repo=$tmp/k6k
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Active
k6_two_task_tasks "$sd" Active ""
# De-sync design.md to Ready (as if a prior mirror write to it had been refused).
awk '!d && /^\*\*Status:\*\* / { print "**Status:** Ready"; d = 1; next } { print }' \
  "$sd/design.md" >"$sd/design.tmp" && mv "$sd/design.tmp" "$sd/design.md"
[ "$(k6_status_of "$sd/design.md")" = Ready ] \
  || fail "k6-K precondition: design.md not de-synced to Ready (test would be vacuous)"
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
# In-progress evidence keeps the derived value Active, so the heal target is Active.
git -C "$repo" branch planwright/kl/task-1
git -C "$repo" checkout -q planwright/kl/task-1
git -C "$repo" commit -q --allow-empty -m "wip: task 1"
git -C "$repo" checkout -q main
reconcile "$repo" specs/kl || fail "k6-K reconcile non-zero"
k6_assert_all "$sd" Active "k6-K partial mirror self-heals to Active"
echo "ok: a partial four-file Status mirror self-heals on the next reconcile (REQ-A1.5)"

# --- T-L: a bundle file lacking the **Status:** header is skipped, not injected.
# requirements.md (the authoritative Status home) carries the header and gates the
# reconcile; a sibling file without one (here design.md) exercises
# write_status_header's no-header early return ([ -n "$wsh_cur" ] || return 0): the
# reconcile must leave it headerless rather than prepend a header, while the other
# three files still mirror the derived value. Guards the contract that the
# reconcile rewrites an existing header but never creates one.
repo=$tmp/k6l
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Ready
k6_two_task_tasks "$sd" Ready ""
# Strip the bundle Status header from design.md (a malformed-but-present sibling).
grep -v '^\*\*Status:\*\* ' "$sd/design.md" >"$sd/design.tmp" && mv "$sd/design.tmp" "$sd/design.md"
grep -q '^\*\*Status:\*\* ' "$sd/design.md" \
  && fail "k6-L precondition: design.md still has a Status header (test would be vacuous)"
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
# In-progress evidence flips the derivation Ready->Active.
git -C "$repo" branch planwright/kl/task-1
git -C "$repo" checkout -q planwright/kl/task-1
git -C "$repo" commit -q --allow-empty -m "wip: task 1"
git -C "$repo" checkout -q main
reconcile "$repo" specs/kl || fail "k6-L reconcile non-zero"
for f in requirements.md tasks.md test-spec.md; do
  [ "$(k6_status_of "$sd/$f")" = Active ] || fail "k6-L: $f not mirrored to Active around a headerless sibling"
done
grep -q '^\*\*Status:\*\* ' "$sd/design.md" \
  && fail "k6-L: write_status_header injected a Status header into a file that lacked one"
echo "ok: write_status_header skips a file with no Status header (no injection) and mirrors the rest (REQ-A1.5)"

# --- T-M: write_status_header refuses a symlink whose target is NOT a regular
# file (a broken symlink, or one pointing at a directory), not just a symlink to
# a real file (T-J). The refusal must be unconditional per the documented
# contract ("a symlinked file is refused"): ordering the `-L` test before the
# `-f` test is what makes a broken / non-regular-target symlink hit the refusal
# rather than the `[ -f ] || return 0` missing-file no-op (which would skip it
# silently with no diagnostic, hiding a partial-mirror problem). Each variant
# leaves its symlink untouched, emits the diagnostic, and the other three files
# still mirror the derived Active.
for k6m_variant in broken dir; do
  repo=$tmp/k6m-$k6m_variant
  k6_init "$repo"
  sd="$repo/specs/kl"
  k6_heads "$sd" Active
  k6_two_task_tasks "$sd" Active ""
  rm "$sd/design.md"
  case $k6m_variant in
    broken) ln -s design.gone.md "$sd/design.md" ;; # target never created -> broken
    dir)
      mkdir "$sd/design.d"
      ln -s design.d "$sd/design.md"
      ;; # points at a dir
  esac
  [ -L "$sd/design.md" ] || fail "k6-M/$k6m_variant precondition: design.md is not a symlink (test would be vacuous)"
  [ -f "$sd/design.md" ] && fail "k6-M/$k6m_variant precondition: design.md resolves to a regular file (covered by T-J, not this test)"
  git -C "$repo" add -A
  git -C "$repo" commit -qm fixture
  # In-progress evidence keeps the derived value Active, so the mirror target is Active.
  git -C "$repo" branch planwright/kl/task-1
  git -C "$repo" checkout -q planwright/kl/task-1
  git -C "$repo" commit -q --allow-empty -m "wip: task 1"
  git -C "$repo" checkout -q main
  err=$(reconcile "$repo" specs/kl 2>&1) || fail "k6-M/$k6m_variant reconcile non-zero"
  case $err in
    *"refusing symlinked"*) ;;
    *) fail "k6-M/$k6m_variant: no symlink-refusal diagnostic emitted (got: $err)" ;;
  esac
  [ -L "$sd/design.md" ] || fail "k6-M/$k6m_variant: the design.md symlink was replaced (write went through the link)"
  for f in requirements.md tasks.md test-spec.md; do
    [ "$(k6_status_of "$sd/$f")" = Active ] || fail "k6-M/$k6m_variant: $f not mirrored to Active around a refused non-regular symlink"
  done
done
echo "ok: write_status_header refuses broken / directory-target symlinks unconditionally, not just symlinks to regular files (REQ-A1.5)"

# --- T-N: a Done bundle with a partially-applied mirror self-heals; a Done
# bundle never auto-reopens (REQ-A1.5 Done mirror-completion + REQ-A1.6 no
# derived reopen). The reconcile gate keys off requirements.md, which reaches
# Done first (it is written first in the mirror loop); if a sibling write was
# refused during the ->Done transition, a naive "stop on any Done" gate would
# never revisit the sibling. The reconcile is therefore Done-owned solely to
# complete its own mirror (derived value still Done), and is NEVER allowed to
# flip a stored-Done bundle back to Active/Ready (that reopen is the human's).

# N1 (self-heal): design.md is symlinked during the ->Done transition so its
# mirror write is refused, leaving requirements.md=Done but design.md=Active.
# Removing the symlink and reconciling again must heal design.md to Done.
repo=$tmp/k6n1
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Active
k6_two_task_tasks "$sd" Active ""
# design.md is a symlink to a real target carrying the (stale) Active header, so
# write_status_header refuses it on the ->Done mirror.
mv "$sd/design.md" "$sd/design.real.md"
ln -s design.real.md "$sd/design.md"
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
# Both tasks complete -> derivation is Done.
git -C "$repo" commit -q --allow-empty -m "feat: task 1 done

Planwright-Task: kl/1"
git -C "$repo" commit -q --allow-empty -m "feat: task 2 done

Planwright-Task: kl/2"
reconcile "$repo" specs/kl || fail "k6-N1 first reconcile non-zero"
[ "$(k6_status_of "$sd/requirements.md")" = Done ] \
  || fail "k6-N1 precondition: requirements.md did not reach Done"
[ "$(k6_status_of "$sd/design.real.md")" = Active ] \
  || fail "k6-N1 precondition: the symlinked design.md was not left stale at Active"
# Clear the obstruction: design.md becomes a regular file still stale at Active.
rm "$sd/design.md"
mv "$sd/design.real.md" "$sd/design.md"
[ "$(k6_status_of "$sd/design.md")" = Active ] || fail "k6-N1 precondition: design.md not stale Active after unlink"
reconcile "$repo" specs/kl || fail "k6-N1 heal reconcile non-zero"
k6_assert_all "$sd" Done "REQ-A1.5 Done mirror self-heals after the obstruction clears"
echo "ok: a Done bundle with a partially-applied mirror self-heals on the next reconcile (REQ-A1.5)"

# N2 (no reopen): a stored-Done bundle with in-progress evidence (derivation
# Active) must stay Done — the reconcile never derives a reopen (REQ-A1.6).
repo=$tmp/k6n2
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Done
k6_two_task_tasks "$sd" Done ""
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
# In-progress evidence: derivation would be Active, but the bundle is stored Done.
git -C "$repo" branch planwright/kl/task-1
git -C "$repo" checkout -q planwright/kl/task-1
git -C "$repo" commit -q --allow-empty -m "wip: task 1"
git -C "$repo" checkout -q main
reconcile "$repo" specs/kl || fail "k6-N2 reconcile non-zero"
k6_assert_all "$sd" Done "REQ-A1.6 stored-Done never auto-reopens to Active"
echo "ok: a stored-Done bundle with in-progress evidence stays Done; the reconcile never derives a reopen (REQ-A1.6)"

# --- T-O: do_status refuses a symlinked requirements.md (the authoritative
# Status home) outright. Otherwise the gate reads ownership *through* the link
# and the mirror updates the three siblings while write_status_header refuses the
# symlinked authoritative file — a cross-file split. do_status must bow out
# entirely (log + non-zero) so no sibling is rewritten. Mirrors do_placement's
# existing symlinked-tasks.md refusal.
repo=$tmp/k6o
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Active
k6_two_task_tasks "$sd" Active ""
# requirements.md becomes a symlink to a real target carrying Active. No progress
# means the derivation is Ready, so a proceeding mirror WOULD move the siblings to
# Ready — making a partial mirror observable.
mv "$sd/requirements.md" "$sd/requirements.real.md"
ln -s requirements.real.md "$sd/requirements.md"
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
err=$(reconcile "$repo" specs/kl 2>&1) || fail "k6-O reconcile non-zero"
case $err in
  *"refusing symlinked"*) ;;
  *) fail "k6-O: no symlink-refusal diagnostic for requirements.md (got: $err)" ;;
esac
[ -L "$sd/requirements.md" ] || fail "k6-O: requirements.md symlink was replaced (write went through the link)"
[ "$(k6_status_of "$sd/requirements.real.md")" = Active ] \
  || fail "k6-O: requirements.md target was rewritten despite the refusal"
# The distinguishing assertion: the siblings must be untouched (no partial mirror).
for f in design.md tasks.md test-spec.md; do
  [ "$(k6_status_of "$sd/$f")" = Active ] \
    || fail "k6-O: sibling $f was rewritten while the authoritative requirements.md was refused (partial mirror)"
done
echo "ok: do_status refuses a symlinked requirements.md outright; no sibling is rewritten (no partial mirror)"

# ===========================================================================
# RS — the status-only reconcile arm (`reconcile-status`, do_status_only):
# kickoff-lifecycle Task 8 (REQ-A1.7, D-4). It reconciles the bundle **Status:**
# header across the four files exactly like the full reconcile (the same single
# writer, do_status) but WITHOUT the placement rewrite, so a one-time corpus
# migration sweep can flip Active-with-no-progress bundles to Ready while leaving
# task placement — including legacy bundles whose git evidence has aged out —
# untouched.
reconcile_status() { # <repo> <spec-dir-relative>
  (cd "$1" && PATH="$stub:$PATH" "$SYNC" reconcile-status "$2")
}

# --- RS-A: stored Active, no progress -> reconcile-status flips to Ready,
# mirrored across all four files; a second run is a byte-identical no-op.
repo=$tmp/rsa
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Active
k6_two_task_tasks "$sd" Active ""
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
reconcile_status "$repo" specs/kl || fail "RS-A reconcile-status non-zero"
k6_assert_all "$sd" Ready "REQ-A1.7 Active-with-no-progress migrates to Ready"
snap=$tmp/rsa-snap
for f in requirements.md design.md tasks.md test-spec.md; do cp "$sd/$f" "$snap.$f"; done
reconcile_status "$repo" specs/kl || fail "RS-A second reconcile-status non-zero"
for f in requirements.md design.md tasks.md test-spec.md; do
  cmp -s "$snap.$f" "$sd/$f" || fail "RS-A: $f changed on the idempotent second run"
done
echo "ok: reconcile-status migrates an Active-with-no-progress bundle to Ready, mirrored, idempotent (REQ-A1.7)"

# --- RS-B: stored Active, one task in-progress -> stays Active (a started bundle
# is not migrated).
repo=$tmp/rsb
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Active
k6_two_task_tasks "$sd" Active ""
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
git -C "$repo" branch planwright/kl/task-1
git -C "$repo" checkout -q planwright/kl/task-1
git -C "$repo" commit -q --allow-empty -m "wip: task 1"
git -C "$repo" checkout -q main
reconcile_status "$repo" specs/kl || fail "RS-B reconcile-status non-zero"
k6_assert_all "$sd" Active "REQ-A1.7 a started bundle stays Active"
echo "ok: reconcile-status leaves a bundle with in-flight work at Active (REQ-A1.7)"

# --- RS-C: the distinguishing property — status-only does NOT rewrite placement.
# A bundle with Task 2 mis-placed under ## In progress (but deriving `ready`, no
# branch) gets its Status flipped Active->Ready while Task 2 stays exactly where
# it was; the full reconcile would relocate it to Forward plan.
repo=$tmp/rsc
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Active
{
  printf '%s\n' '# K6 — Tasks' '' '**Status:** Active' '**Format-version:** 1' ''
  printf '%s\n' '## Forward plan' ''
  printf '%s\n' '### Task 1 — Alpha' ''
  printf '%s\n' '- **Deliverables:** Alpha.' '- **Done when:** Alpha done.' \
    '- **Dependencies:** none' '- **Citations:** REQ-K1.1' '- **Estimated effort:** 1 day' ''
  printf '%s\n' '## In progress' ''
  printf '%s\n' '### Task 2 — Beta' ''
  printf '%s\n' '- **Deliverables:** Beta.' '- **Done when:** Beta done.' \
    '- **Dependencies:** none' '- **Citations:** REQ-K1.2' '- **Estimated effort:** 1 day' ''
  printf '%s\n' '## Awaiting input' '' '(none yet)' ''
  printf '%s\n' '## Completed' '' '(none yet)'
} >"$sd/tasks.md"
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
[ "$(section_of "$sd/tasks.md" 2)" = "In progress" ] || fail "RS-C precondition: Task 2 not pre-placed in In progress"
reconcile_status "$repo" specs/kl || fail "RS-C reconcile-status non-zero"
k6_assert_all "$sd" Ready "REQ-A1.7 status flips on a status-only reconcile"
[ "$(section_of "$sd/tasks.md" 2)" = "In progress" ] \
  || fail "RS-C: reconcile-status relocated Task 2 (placement must be untouched)"
[ "$(section_of "$sd/tasks.md" 1)" = "Forward plan" ] \
  || fail "RS-C: reconcile-status relocated Task 1 (placement must be untouched)"
# Contrast: the full placement reconcile WOULD move the mis-placed ready Task 2.
reconcile "$repo" specs/kl || fail "RS-C contrast reconcile non-zero"
[ "$(section_of "$sd/tasks.md" 2)" = "Forward plan" ] \
  || fail "RS-C contrast: full reconcile did not relocate the ready Task 2 to Forward plan"
echo "ok: reconcile-status mirrors the Status header but never rewrites task placement (REQ-A1.7, D-4)"

# --- RS-D: a stored-Done bundle is never reopened by the status-only arm (the
# stored-Done guard in do_status holds for both arms).
repo=$tmp/rsd
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Done
k6_two_task_tasks "$sd" Done ""
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
reconcile_status "$repo" specs/kl || fail "RS-D reconcile-status non-zero"
k6_assert_all "$sd" Done "REQ-A1.6 stored-Done never reopened by reconcile-status"
echo "ok: reconcile-status never reopens a stored-Done bundle (REQ-A1.6)"

# --- RS-E: a Draft bundle's header is left untouched (Draft->Ready is the
# human-gated /spec-kickoff write, never derived).
repo=$tmp/rse
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Draft
k6_two_task_tasks "$sd" Draft ""
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
reconcile_status "$repo" specs/kl || fail "RS-E reconcile-status non-zero"
k6_assert_all "$sd" Draft "REQ-A1.4 Draft is never derived to Ready by reconcile-status"
echo "ok: reconcile-status leaves a Draft bundle untouched (REQ-A1.4)"

# --- RS-F: fail-closed CLI validation mirrors `reconcile` (missing arg / missing
# tasks.md -> exit 2 specifically, not merely non-zero and not a silent skip).
# Assert the exact code: this bundle added an in-writer failure arm that exits 1
# (the status+closed propagation), so a regression that made input validation exit
# 1 instead of 2 must NOT pass as "fails closed". (`(cmd) || rc=$?` keeps the
# failing command out of `set -e`'s reach while capturing its code.)
rc=0
("$SYNC" reconcile-status >/dev/null 2>&1) || rc=$?
[ "$rc" = 2 ] || fail "RS-F: missing-arg reconcile-status exit=$rc, expected 2"
nodir=$tmp/rsf-empty
mkdir -p "$nodir"
rc=0
("$SYNC" reconcile-status "$nodir" >/dev/null 2>&1) || rc=$?
[ "$rc" = 2 ] || fail "RS-F: reconcile-status on a dir with no tasks.md exit=$rc, expected 2"
echo "ok: reconcile-status fails closed on missing arg / missing tasks.md (exit 2)"

# --- RS-G: a partial mirror (a symlinked sibling the writer refuses) makes the
# status-only arm fail closed under the CLI (closed) policy — do_status returns
# non-zero, and reconcile-status propagates it rather than masking with `|| true`
# — so a migration sweep records a real skip instead of a false "unchanged". The
# full placement reconcile keeps its best-effort return-0 contract (k6-O), so only
# the status arm propagates.
repo=$tmp/rsg
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Active
k6_two_task_tasks "$sd" Active ""
# design.md becomes a symlink: write_status_header refuses it, do_status returns 1.
# (A symlinked requirements.md/tasks.md would exit 2 at the CLI pre-check instead;
# a sibling exercises the in-writer failure path the migration relies on.)
mv "$sd/design.md" "$sd/design.real.md"
ln -s design.real.md "$sd/design.md"
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
err=$(reconcile_status "$repo" specs/kl 2>&1) \
  && fail "RS-G: reconcile-status did not fail closed on a refused symlinked sibling"
case $err in
  *"refusing symlinked"*) ;;
  *) fail "RS-G: no symlink-refusal diagnostic on stderr (got: $err)" ;;
esac
# The non-symlinked siblings are still mirrored (the partial mirror is real; a
# re-run heals once the symlink is fixed).
[ "$(k6_status_of "$sd/requirements.md")" = Ready ] \
  || fail "RS-G: requirements.md not mirrored to Ready"
# Contrast: the full reconcile keeps returning 0 on the same partial mirror.
reconcile "$repo" specs/kl \
  || fail "RS-G contrast: full reconcile must keep its best-effort return-0 contract"
echo "ok: reconcile-status fails closed on a partial mirror; full reconcile stays best-effort (REQ-A1.7)"

# --- RS-H: a present-but-taskless tasks.md (well-formed sections, no `### Task`
# blocks) has no state to derive from. The CLI pre-check passes (the file exists
# and is a regular file), so this exercises the in-writer derivation guard inside
# do_status_only — distinct from RS-F's missing-file guard — which returns
# non-zero. reconcile-status propagates it (fail closed) and the stored header is
# left untouched (no partial flip on a failed derivation).
repo=$tmp/rsh
k6_init "$repo"
sd="$repo/specs/kl"
k6_heads "$sd" Active
{
  printf '%s\n' '# K6 — Tasks' '' '**Status:** Active' '**Format-version:** 1' ''
  printf '%s\n' '## Forward plan' '' '(none yet)' ''
  printf '%s\n' '## In progress' '' '(none yet)' ''
  printf '%s\n' '## Completed' '' '(none yet)'
} >"$sd/tasks.md"
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
reconcile_status "$repo" specs/kl >/dev/null 2>&1 \
  && fail "RS-H: reconcile-status on a taskless tasks.md did not fail closed"
k6_assert_all "$sd" Active "REQ-A1.7 taskless bundle's header left untouched on a failed derivation"
echo "ok: reconcile-status fails closed on a present-but-taskless tasks.md; header untouched (REQ-A1.7)"

# ===========================================================================
# T7 — Organic completion-annotation stamping (output-hygiene REQ-E1.2, D-5).
# When the reconcile places a completion-evidenced block in ## Completed it stamps
# the canonical `- **Status:** Completed · PR #<n> merged <YYYY-MM-DD>`, reusing
# the derivation's merged-PR evidence batch (no new per-task lookups). With no
# remote it degrades to the pinned date-only form `Completed · merged
# <YYYY-MM-DD>` (branch evidence) or leaves the annotation untouched — never an
# invented PR number, never a third variant, never a downgrade of an existing
# full stamp. Non-completion annotations and the content anchor stay invariant.
t7_init() { # $1 = repo dir
  mkdir -p "$1"
  git -C "$1" init -q -b main
  git -C "$1" config user.email t7@example.com
  git -C "$1" config user.name t7
  git -C "$1" config commit.gpgsign false
}
t7_heads() { # $1 = spec dir
  mkdir -p "$1"
  printf '%s\n' '# T7 — Requirements' '' '**Status:** Active' >"$1/requirements.md"
  printf '%s\n' '# T7 — Design' >"$1/design.md"
  printf '%s\n' '# T7 — Test Spec' >"$1/test-spec.md"
}

# --- T7-A: canonical PR stamp from the merged-PR evidence batch. Task 1 is
# completed via a gh MERGED PR (number + mergedAt from the batch); Task 2 is a
# gh-OPEN in-progress task carrying a `- **Status:** implementing` annotation
# that must survive byte-for-byte (it is not a completion block). The stamp is
# anchor-excluded and idempotent.
repo=$tmp/t7a
t7_init "$repo"
sd=$repo/specs/demo
t7_heads "$sd"
cat >"$sd/tasks.md" <<'EOF'
# T7 — Tasks

**Status:** Active
**Format-version:** 1

## Forward plan

### Task 1 — Merged via PR

- **Deliverables:** A thing.
- **Done when:** Done.
- **Dependencies:** none
- **Citations:** REQ-T1.1
- **Estimated effort:** 1 day

### Task 2 — In flight

- **Status:** implementing
- **Deliverables:** Another thing.
- **Done when:** Done.
- **Dependencies:** none
- **Citations:** REQ-T1.2
- **Estimated effort:** 1 day

## In progress

(none yet)

## Completed

(none yet)
EOF
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
git -C "$repo" remote add origin https://example.invalid/demo.git
anchor_before=$("$ANCHOR" "$sd")
GH_PRLIST=$(printf 'planwright/demo/task-1\tMERGED\t42\t2026-07-01T12:00:00Z\nplanwright/demo/task-2\tOPEN\t43\t')
export GH_PRLIST
reconcile "$repo" specs/demo || fail "T7-A reconcile non-zero"
[ "$(section_of "$sd/tasks.md" 1)" = "Completed" ] || fail "T7-A: Task 1 not placed in Completed"
block_of "$sd/tasks.md" 1 | grep -qF -- '- **Status:** Completed · PR #42 merged 2026-07-01' \
  || fail "T7-A: canonical PR completion stamp not written on the moved block"
[ "$(section_of "$sd/tasks.md" 2)" = "In progress" ] || fail "T7-A: Task 2 not in In progress"
# Byte-for-byte (exact line equality, not a substring): a preserved non-completion
# annotation must be left verbatim, with no trailing mutation.
t7a_t2status=$(block_of "$sd/tasks.md" 2 | grep -F -- '- **Status:**')
[ "$t7a_t2status" = '- **Status:** implementing' ] \
  || fail "T7-A: a non-completion Status annotation was not preserved byte-for-byte (got '$t7a_t2status')"
anchor_after=$("$ANCHOR" "$sd")
[ "$anchor_before" = "$anchor_after" ] || fail "T7-A: the completion stamp changed the content anchor (must be anchor-excluded)"
# The stamped snapshot must satisfy the committed-ledger corruption guard: the
# canonical stamp is recognized as a completion Status by check-ledger's
# classify(), so the Completed-section placement is consistent (cross-file
# consistency: the stamp format and the ledger recognizer stay in lockstep).
/bin/bash "$here/../scripts/check-ledger.sh" "$sd/tasks.md" \
  || fail "T7-A: the canonical stamp is not recognized as a completion Status by check-ledger"
snap=$tmp/t7a-snap.md
cp "$sd/tasks.md" "$snap"
reconcile "$repo" specs/demo || fail "T7-A second reconcile non-zero"
cmp -s "$sd/tasks.md" "$snap" || fail "T7-A: the stamp is not idempotent (second reconcile changed tasks.md)"
unset GH_PRLIST
echo "ok: reconcile stamps the canonical PR completion annotation; anchor + non-completion annotations invariant; idempotent; ledger-consistent (REQ-E1.2)"

# --- T7-B: degraded date-only stamp from branch evidence with no remote. Task 1
# is merged locally with its branch kept (branch-merged evidence) and no gh, so
# the stamp is the pinned `Completed · merged <date>` with NO invented PR number.
repo=$tmp/t7b
t7_init "$repo"
sd=$repo/specs/demo
t7_heads "$sd"
cat >"$sd/tasks.md" <<'EOF'
# T7 — Tasks

**Status:** Active
**Format-version:** 1

## Forward plan

### Task 1 — Merged locally, branch kept

- **Deliverables:** A thing.
- **Done when:** Done.
- **Dependencies:** none
- **Citations:** REQ-T1.1
- **Estimated effort:** 1 day

### Task 2 — Still ahead

- **Deliverables:** Another thing.
- **Done when:** Done.
- **Dependencies:** none
- **Citations:** REQ-T1.2
- **Estimated effort:** 1 day

## Completed

(none yet)
EOF
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
git -C "$repo" branch planwright/demo/task-1
git -C "$repo" checkout -q planwright/demo/task-1
git -C "$repo" commit -q --allow-empty -m "task 1 work"
git -C "$repo" checkout -q main
git -C "$repo" merge -q --no-ff -m "merge task 1" planwright/demo/task-1
# Task 2 stays in Forward plan so the derived bundle Status stays Active (a flip
# would change the anchor via the not-yet-excluded bundle Status header, which is
# a separate known effect from the completion stamp under test).
anchor_before=$("$ANCHOR" "$sd")
expected_date=$(git -C "$repo" log -1 --format=%cs planwright/demo/task-1)
reconcile "$repo" specs/demo || fail "T7-B reconcile non-zero"
[ "$(section_of "$sd/tasks.md" 1)" = "Completed" ] || fail "T7-B: Task 1 not placed in Completed"
block_of "$sd/tasks.md" 1 | grep -qF -- "- **Status:** Completed · merged $expected_date" \
  || fail "T7-B: degraded date-only stamp not written (expected 'merged $expected_date')"
block_of "$sd/tasks.md" 1 | grep -qF 'PR #' \
  && fail "T7-B: the degraded stamp invented a PR number"
anchor_after=$("$ANCHOR" "$sd")
[ "$anchor_before" = "$anchor_after" ] || fail "T7-B: the degraded stamp changed the content anchor"
# The degraded stamp is also a valid completion Status for the ledger guard.
/bin/bash "$here/../scripts/check-ledger.sh" "$sd/tasks.md" \
  || fail "T7-B: the degraded stamp is not recognized as a completion Status by check-ledger"
# Idempotent: the degraded path is NOT covered by the no-downgrade guard (it
# overwrites its own date-only line each run), so its byte-stability across
# repeated reconciles must be asserted directly.
snapb=$tmp/t7b-snap.md
cp "$sd/tasks.md" "$snapb"
reconcile "$repo" specs/demo || fail "T7-B second reconcile non-zero"
cmp -s "$sd/tasks.md" "$snapb" || fail "T7-B: the degraded stamp is not idempotent (second reconcile changed tasks.md)"
echo "ok: no-remote branch evidence yields the pinned date-only stamp, no invented PR number, idempotent, ledger-consistent (REQ-E1.2)"

# --- T7-C: no evidence for a date (trailer-only completion, branch gone, no
# remote) leaves the annotation untouched rather than inventing a bare stamp.
repo=$tmp/t7c
t7_init "$repo"
sd=$repo/specs/demo
t7_heads "$sd"
cat >"$sd/tasks.md" <<'EOF'
# T7 — Tasks

**Status:** Active
**Format-version:** 1

## Forward plan

### Task 1 — Merged, branch gone

- **Deliverables:** A thing.
- **Done when:** Done.
- **Dependencies:** none
- **Citations:** REQ-T1.1
- **Estimated effort:** 1 day

## Completed

(none yet)
EOF
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
git -C "$repo" commit -q --allow-empty -m "task 1 done

Planwright-Task: demo/1"
reconcile "$repo" specs/demo || fail "T7-C reconcile non-zero"
[ "$(section_of "$sd/tasks.md" 1)" = "Completed" ] || fail "T7-C: Task 1 not placed in Completed"
block_of "$sd/tasks.md" 1 | grep -qF -- '- **Status:**' \
  && fail "T7-C: a stamp was invented with neither a PR number nor a date (must leave the annotation untouched)"
# Idempotent: a second reconcile over the untouched-completion state is a no-op.
snapc=$tmp/t7c-snap.md
cp "$sd/tasks.md" "$snapc"
reconcile "$repo" specs/demo || fail "T7-C second reconcile non-zero"
cmp -s "$sd/tasks.md" "$snapc" || fail "T7-C: the untouched path is not idempotent (second reconcile changed tasks.md)"
echo "ok: trailer-only completion with no remote and no branch leaves the annotation untouched, idempotent (REQ-E1.2)"

# --- T7-D: no downgrade. A block already carrying a full canonical PR stamp is
# reconciled under degraded (no-remote) evidence whose best output is date-only;
# the reconcile must keep the richer existing stamp, never dropping the PR number.
repo=$tmp/t7d
t7_init "$repo"
sd=$repo/specs/demo
t7_heads "$sd"
cat >"$sd/tasks.md" <<'EOF'
# T7 — Tasks

**Status:** Active
**Format-version:** 1

## Completed

### Task 1 — Already stamped

- **Status:** Completed · PR #99 merged 2026-06-01
- **Deliverables:** A thing.
- **Done when:** Done.
- **Dependencies:** none
- **Citations:** REQ-T1.1
- **Estimated effort:** 1 day

## Forward plan

(none yet)
EOF
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
git -C "$repo" branch planwright/demo/task-1
git -C "$repo" checkout -q planwright/demo/task-1
git -C "$repo" commit -q --allow-empty -m "task 1 work"
git -C "$repo" checkout -q main
git -C "$repo" merge -q --no-ff -m "merge task 1" planwright/demo/task-1
reconcile "$repo" specs/demo || fail "T7-D reconcile non-zero"
block_of "$sd/tasks.md" 1 | grep -qF -- '- **Status:** Completed · PR #99 merged 2026-06-01' \
  || fail "T7-D: a degraded reconcile downgraded an existing full PR stamp (lost the PR number)"
echo "ok: a degraded reconcile never downgrades an existing full PR completion stamp (REQ-E1.2)"

# --- T7-E: a MERGED PR whose mergedAt is absent must NOT fabricate a full stamp
# by pairing the PR number with a local branch date (that date is not the merge
# date). The honest output is the degraded date-only form (branch evidence) with
# no PR number, or untouched — never `PR #<n> merged <branch-date>`.
repo=$tmp/t7e
t7_init "$repo"
sd=$repo/specs/demo
t7_heads "$sd"
cat >"$sd/tasks.md" <<'EOF'
# T7 — Tasks

**Status:** Active
**Format-version:** 1

## Forward plan

### Task 1 — Merged PR, no mergedAt

- **Deliverables:** A thing.
- **Done when:** Done.
- **Dependencies:** none
- **Citations:** REQ-T1.1
- **Estimated effort:** 1 day

### Task 2 — Still ahead

- **Deliverables:** Another thing.
- **Done when:** Done.
- **Dependencies:** none
- **Citations:** REQ-T1.2
- **Estimated effort:** 1 day

## Completed

(none yet)
EOF
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
git -C "$repo" remote add origin https://example.invalid/demo.git
# Branch kept (a local branch-tip date is available) AND a MERGED PR whose
# mergedAt column is empty (null in gh) — the exact null-mergedAt edge.
git -C "$repo" branch planwright/demo/task-1
git -C "$repo" checkout -q planwright/demo/task-1
git -C "$repo" commit -q --allow-empty -m "task 1 work"
git -C "$repo" checkout -q main
git -C "$repo" merge -q --no-ff -m "merge task 1" planwright/demo/task-1
branch_date=$(git -C "$repo" log -1 --format=%cs planwright/demo/task-1)
GH_PRLIST=$(printf 'planwright/demo/task-1\tMERGED\t42\t')
export GH_PRLIST
reconcile "$repo" specs/demo || fail "T7-E reconcile non-zero"
unset GH_PRLIST
[ "$(section_of "$sd/tasks.md" 1)" = "Completed" ] || fail "T7-E: Task 1 not placed in Completed"
block_of "$sd/tasks.md" 1 | grep -qF 'PR #' \
  && fail "T7-E: fabricated a full 'PR #<n> merged <date>' stamp from a branch date (mergedAt was absent)"
block_of "$sd/tasks.md" 1 | grep -qF -- "- **Status:** Completed · merged $branch_date" \
  || fail "T7-E: expected the honest degraded date-only stamp from branch evidence"
echo "ok: a MERGED PR with no mergedAt degrades to the honest date-only stamp, never a fabricated merge date (REQ-E1.2)"

# --- T7-F: sibling annotations (Last activity / Dispatch) on a block that MOVES
# to ## Completed ride along untouched while the completion stamp replaces only
# the Status line (the corrected implementation comment's promise).
repo=$tmp/t7f
t7_init "$repo"
sd=$repo/specs/demo
t7_heads "$sd"
cat >"$sd/tasks.md" <<'EOF'
# T7 — Tasks

**Status:** Active
**Format-version:** 1

## Forward plan

### Task 1 — Merged via PR

- **Status:** implementing
- **Last activity:** 2026-06-30
- **Dispatch:** worker-7
- **Deliverables:** A thing.
- **Done when:** Done.
- **Dependencies:** none
- **Citations:** REQ-T1.1
- **Estimated effort:** 1 day

### Task 2 — Still ahead

- **Deliverables:** Another thing.
- **Done when:** Done.
- **Dependencies:** none
- **Citations:** REQ-T1.2
- **Estimated effort:** 1 day

## Completed

(none yet)
EOF
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
git -C "$repo" remote add origin https://example.invalid/demo.git
GH_PRLIST=$(printf 'planwright/demo/task-1\tMERGED\t42\t2026-07-01T12:00:00Z')
export GH_PRLIST
reconcile "$repo" specs/demo || fail "T7-F reconcile non-zero"
unset GH_PRLIST
[ "$(section_of "$sd/tasks.md" 1)" = "Completed" ] || fail "T7-F: Task 1 not placed in Completed"
# The stale Status is replaced by the canonical stamp (in place)...
block_of "$sd/tasks.md" 1 | grep -qF -- '- **Status:** Completed · PR #42 merged 2026-07-01' \
  || fail "T7-F: the stale Status was not replaced by the canonical stamp"
block_of "$sd/tasks.md" 1 | grep -qF -- '- **Status:** implementing' \
  && fail "T7-F: the stale 'implementing' Status survived alongside the stamp"
# ...and only one Status line remains (the ledger's >1-Status lint).
[ "$(block_of "$sd/tasks.md" 1 | grep -cF -- '- **Status:**')" = 1 ] \
  || fail "T7-F: the stamp did not replace the Status line in place (duplicate Status)"
# ...while the sibling annotations survive byte-for-byte.
t7f_la=$(block_of "$sd/tasks.md" 1 | grep -F -- '- **Last activity:**')
[ "$t7f_la" = '- **Last activity:** 2026-06-30' ] \
  || fail "T7-F: the Last activity annotation was not preserved byte-for-byte (got '$t7f_la')"
t7f_dp=$(block_of "$sd/tasks.md" 1 | grep -F -- '- **Dispatch:**')
[ "$t7f_dp" = '- **Dispatch:** worker-7' ] \
  || fail "T7-F: the Dispatch annotation was not preserved byte-for-byte (got '$t7f_dp')"
echo "ok: sibling annotations survive on a stamped Completed block; the stamp replaces only the Status line (REQ-E1.2)"

# --- T7-G: the no-downgrade guard recognizes ONLY the exact canonical stamp. A
# block carrying a MALFORMED near-canonical Status (a PR number with a non-ISO
# date, e.g. slashes — a shape this reconcile never writes, so a foreign/human
# edit) reconciled under degraded (no-remote) evidence must NOT be preserved as
# if canonical: the guard is a strict `Completed · PR #<n> merged <YYYY-MM-DD>`
# recognizer, so the malformed stamp is regenerated to the honest degraded
# date-only form rather than silently kept. Mirrors the function's own
# defense-in-depth posture (only an ISO date is trusted at the write boundary).
repo=$tmp/t7g
t7_init "$repo"
sd=$repo/specs/demo
t7_heads "$sd"
cat >"$sd/tasks.md" <<'EOF'
# T7 — Tasks

**Status:** Active
**Format-version:** 1

## Completed

### Task 1 — Malformed existing stamp

- **Status:** Completed · PR #99 merged 2026/06/01
- **Deliverables:** A thing.
- **Done when:** Done.
- **Dependencies:** none
- **Citations:** REQ-T1.1
- **Estimated effort:** 1 day

## Forward plan

(none yet)
EOF
git -C "$repo" add -A
git -C "$repo" commit -qm fixture
git -C "$repo" branch planwright/demo/task-1
git -C "$repo" checkout -q planwright/demo/task-1
git -C "$repo" commit -q --allow-empty -m "task 1 work"
git -C "$repo" checkout -q main
git -C "$repo" merge -q --no-ff -m "merge task 1" planwright/demo/task-1
expected_date=$(git -C "$repo" log -1 --format=%cs planwright/demo/task-1)
reconcile "$repo" specs/demo || fail "T7-G reconcile non-zero"
block_of "$sd/tasks.md" 1 | grep -qF -- '2026/06/01' \
  && fail "T7-G: a malformed non-canonical stamp was preserved by the no-downgrade guard (must not match the canonical recognizer)"
block_of "$sd/tasks.md" 1 | grep -qF -- "- **Status:** Completed · merged $expected_date" \
  || fail "T7-G: the malformed stamp was not regenerated to the honest degraded date-only form (expected 'merged $expected_date')"
/bin/bash "$here/../scripts/check-ledger.sh" "$sd/tasks.md" \
  || fail "T7-G: the regenerated degraded stamp is not recognized as a completion Status by check-ledger"
echo "ok: the no-downgrade guard preserves ONLY the exact canonical stamp; a malformed near-canonical stamp is regenerated under degraded evidence (REQ-E1.2)"

# ===========================================================================
# V2 — format-version 2 invariant-ledger arms (invariant-tasks Task 4; D-7,
# REQ-C1.1, REQ-C1.8, REQ-A1.2). The writer is version-keyed off the bundle's
# tasks.md `**Format-version:**` declaration: v1 bundles keep every reconcile
# behavior above unchanged; on a v2 bundle the writer performs NO placement,
# annotation, or derived-header writes (a clean no-op, both CLI arms and the
# hook); a missing or unparseable declaration fails closed — no write, error
# reported (CLI exit 2; the hook stays fail-soft but writes nothing) — never
# falling open to the v1 write path.

# A v2 fixture bundle: restricted stored header + pointer line, a single
# ## Tasks section holding every block (no placement sections), human-payload
# sections, and no state annotations.
write_v2_spec() { # $1 = spec dir, $2 = stored status
  mkdir -p "$1"
  cat >"$1/requirements.md" <<EOF
# Demo2 — Requirements

**Status:** $2
**Last reviewed:** 2026-07-15
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

Fixture.
EOF
  for v2f in design.md test-spec.md; do
    printf '%s\n' "# Demo2 — ${v2f%.md}" '' "**Status:** $2" \
      '**Last reviewed:** 2026-07-15' '**Format-version:** 2' \
      '**Execution:** derived — see the status render' >"$1/$v2f"
  done
  cat >"$1/tasks.md" <<EOF
# Demo2 — Tasks

**Status:** $2
**Last reviewed:** 2026-07-15
**Format-version:** 2
**Execution:** derived — see the status render

## Tasks

### Task 1 — Alpha

- **Deliverables:** Alpha.
- **Done when:** Alpha done.
- **Dependencies:** none
- **Citations:** REQ-V2.1
- **Estimated effort:** 1 day

### Task 2 — Beta

- **Deliverables:** Beta.
- **Done when:** Beta done.
- **Dependencies:** 1
- **Citations:** REQ-V2.2
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
}

# Content digest of everything under specs/ (the "no write" oracle: the
# REQ-C1.1 test-spec entry's directory digest).
specs_digest() { # $1 = repo dir
  (cd "$1" && find specs -type f | LC_ALL=C sort | xargs git hash-object | git hash-object --stdin)
}

# A v2 repo whose git evidence WOULD relocate blocks and flip headers under the
# v1 reconcile: Task 1 completed (trailer), Task 2 in-progress (branch ahead),
# stored status Ready — so a falling-open writer would visibly rewrite both
# tasks.md placement and the four Status headers.
make_v2_repo() { # $1 = repo dir
  mkdir -p "$1"
  git -C "$1" init -q -b main
  git -C "$1" config user.email test@example.com
  git -C "$1" config user.name test
  git -C "$1" config commit.gpgsign false
  write_v2_spec "$1/specs/demo2" Ready
  git -C "$1" add -A
  git -C "$1" commit -qm "chore: fixture"
  git -C "$1" commit -q --allow-empty -m "feat: task 1 done

Planwright-Task: demo2/1"
  git -C "$1" branch planwright/demo2/task-2
  git -C "$1" checkout -q planwright/demo2/task-2
  git -C "$1" commit -q --allow-empty -m "wip: task 2"
  git -C "$1" checkout -q main
}

# --- V2-A: CLI `reconcile` on a v2 bundle is a clean no-op (REQ-C1.1) --------
repo=$tmp/v2a
make_v2_repo "$repo"
d_before=$(specs_digest "$repo")
reconcile "$repo" specs/demo2 || fail "V2-A: reconcile on a v2 bundle should exit 0 (clean no-op), got non-zero"
d_after=$(specs_digest "$repo")
[ "$d_before" = "$d_after" ] || fail "V2-A: reconcile wrote into a v2 bundle (specs digest changed; REQ-C1.1)"
grep -q '^## Tasks$' "$repo/specs/demo2/tasks.md" || fail "V2-A: v2 tasks.md shape lost"
echo "ok: V2-A CLI reconcile on a v2 bundle writes nothing (REQ-C1.1)"

# --- V2-B: the hook fires harmlessly on a v2 bundle --------------------------
repo=$tmp/v2b
make_v2_repo "$repo"
git -C "$repo" checkout -q planwright/demo2/task-2
d_before=$(specs_digest "$repo")
run_hook "$repo" "gh pr create --draft" "https://github.com/x/y/pull/7" \
  || fail "V2-B: hook on a v2 bundle should exit 0 (fail-soft), got non-zero"
d_after=$(specs_digest "$repo")
[ "$d_before" = "$d_after" ] || fail "V2-B: the hook wrote into a v2 bundle (specs digest changed)"
git -C "$repo" checkout -q main
echo "ok: V2-B hook fires harmlessly on a v2 bundle (no write)"

# --- V2-C: `reconcile-status` on a v2 bundle leaves every header untouched ---
repo=$tmp/v2c
make_v2_repo "$repo"
d_before=$(specs_digest "$repo")
(cd "$repo" && PATH="$stub:$PATH" "$SYNC" reconcile-status specs/demo2) \
  || fail "V2-C: reconcile-status on a v2 bundle should exit 0 (clean no-op), got non-zero"
d_after=$(specs_digest "$repo")
[ "$d_before" = "$d_after" ] || fail "V2-C: reconcile-status wrote into a v2 bundle (derived-header write; REQ-C1.1)"
grep -q '^\*\*Status:\*\* Ready$' "$repo/specs/demo2/requirements.md" \
  || fail "V2-C: stored Ready header was rewritten (Active/Done are derived, never stored)"
echo "ok: V2-C reconcile-status on a v2 bundle writes no derived header (REQ-C1.1)"

# --- V2-D: missing Format-version fails closed (REQ-C1.8) --------------------
repo=$tmp/v2d
make_v2_repo "$repo"
grep -v '^\*\*Format-version:\*\*' "$repo/specs/demo2/tasks.md" >"$repo/specs/demo2/tasks.md.new"
mv "$repo/specs/demo2/tasks.md.new" "$repo/specs/demo2/tasks.md"
git -C "$repo" add -A && git -C "$repo" commit -qm "fixture: strip version"
d_before=$(specs_digest "$repo")
rc=0
err=$( (cd "$repo" && PATH="$stub:$PATH" "$SYNC" reconcile specs/demo2) 2>&1 >/dev/null) || rc=$?
[ "$rc" -eq 2 ] || fail "V2-D: reconcile on a missing Format-version should fail closed (exit 2), got $rc"
case "$err" in *Format-version*) ;; *) fail "V2-D: fail-closed error does not name Format-version: $err" ;; esac
d_after=$(specs_digest "$repo")
[ "$d_before" = "$d_after" ] || fail "V2-D: a missing Format-version still reached the write path (REQ-C1.8)"
rc=0
(cd "$repo" && PATH="$stub:$PATH" "$SYNC" reconcile-status specs/demo2) >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "V2-D: reconcile-status on a missing Format-version should fail closed (exit 2), got $rc"
[ "$d_before" = "$(specs_digest "$repo")" ] || fail "V2-D: reconcile-status wrote despite a missing Format-version"
echo "ok: V2-D missing Format-version fails closed on both CLI arms (no write, error reported; REQ-C1.8)"

# --- V2-E: unparseable Format-version fails closed (REQ-C1.8) ----------------
repo=$tmp/v2e
make_v2_repo "$repo"
sed 's/^\*\*Format-version:\*\* 2$/**Format-version:** banana/' "$repo/specs/demo2/tasks.md" \
  >"$repo/specs/demo2/tasks.md.new"
mv "$repo/specs/demo2/tasks.md.new" "$repo/specs/demo2/tasks.md"
git -C "$repo" add -A && git -C "$repo" commit -qm "fixture: unparseable version"
d_before=$(specs_digest "$repo")
rc=0
err=$( (cd "$repo" && PATH="$stub:$PATH" "$SYNC" reconcile specs/demo2) 2>&1 >/dev/null) || rc=$?
[ "$rc" -eq 2 ] || fail "V2-E: reconcile on an unparseable Format-version should fail closed (exit 2), got $rc"
case "$err" in *Format-version*) ;; *) fail "V2-E: fail-closed error does not name Format-version (the 'error reported' half of REQ-C1.8): $err" ;; esac
[ "$d_before" = "$(specs_digest "$repo")" ] || fail "V2-E: an unparseable Format-version still reached the write path (REQ-C1.8)"
echo "ok: V2-E unparseable Format-version fails closed (no write, error reported; REQ-C1.8)"

# --- V2-F: the hook stays fail-soft on a bad declaration but writes nothing --
repo=$tmp/v2f
make_v2_repo "$repo"
sed 's/^\*\*Format-version:\*\* 2$/**Format-version:** banana/' "$repo/specs/demo2/tasks.md" \
  >"$repo/specs/demo2/tasks.md.new"
mv "$repo/specs/demo2/tasks.md.new" "$repo/specs/demo2/tasks.md"
git -C "$repo" add -A && git -C "$repo" commit -qm "fixture: unparseable version"
git -C "$repo" checkout -q planwright/demo2/task-2
d_before=$(specs_digest "$repo")
run_hook "$repo" "gh pr create --draft" "https://github.com/x/y/pull/8" \
  || fail "V2-F: hook must stay fail-soft (exit 0) on an unparseable Format-version"
[ "$d_before" = "$(specs_digest "$repo")" ] || fail "V2-F: the hook wrote despite an unparseable Format-version (REQ-C1.8)"
git -C "$repo" checkout -q main
echo "ok: V2-F hook is fail-soft on an unparseable Format-version and writes nothing (REQ-C1.8)"

# --- V2-G: a torn bundle (requirements.md declares 2, tasks.md declares 1)
# fails closed on every arm (REQ-C1.8: no script falls open to the v1 write
# path). requirements.md is the authoritative version home, and do_status
# mirrors derived Status headers into requirements.md itself — so keying on
# tasks.md alone would write v1 derived state into a bundle whose
# authoritative file declares v2 (a half-migrated bundle; the validator flags
# the mirror mismatch, and the writer must refuse it too).
repo=$tmp/v2g
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
git -C "$repo" config commit.gpgsign false
sd=$repo/specs/demo
mkdir -p "$sd"
printf '%s\n' '# Demo — Requirements' '' '**Status:** Active' \
  '**Format-version:** 2' '**Execution:** derived — see the status render' \
  >"$sd/requirements.md"
printf '%s\n' '# Demo — Design' '' '**Status:** Active' >"$sd/design.md"
printf '%s\n' '# Demo — Test Spec' '' '**Status:** Active' >"$sd/test-spec.md"
cat >"$sd/tasks.md" <<'EOF'
# Demo — Tasks

**Status:** Active
**Format-version:** 1

## Forward plan

### Task 1 — Alpha

- **Deliverables:** Alpha.
- **Done when:** Alpha done.
- **Dependencies:** none
- **Citations:** REQ-V2.1
- **Estimated effort:** 1 day

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

(none yet)
EOF
git -C "$repo" add -A
git -C "$repo" commit -qm "fixture: torn bundle"
# Precondition: without the conflict, the v1 path WOULD write (stored Active,
# no progress -> derived Ready header flip), so the no-write assertions below
# are non-vacuous.
d_before=$(specs_digest "$repo")
rc=0
err=$( (cd "$repo" && PATH="$stub:$PATH" "$SYNC" reconcile specs/demo) 2>&1 >/dev/null) || rc=$?
[ "$rc" -eq 2 ] || fail "V2-G: reconcile on a torn bundle should fail closed (exit 2), got $rc"
case "$err" in *Format-version*) ;; *) fail "V2-G: torn-bundle error does not name Format-version: $err" ;; esac
[ "$d_before" = "$(specs_digest "$repo")" ] || fail "V2-G: reconcile wrote into a torn bundle (v1 write path fell open; REQ-C1.8)"
rc=0
(cd "$repo" && PATH="$stub:$PATH" "$SYNC" reconcile-status specs/demo) >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "V2-G: reconcile-status on a torn bundle should fail closed (exit 2), got $rc"
[ "$d_before" = "$(specs_digest "$repo")" ] || fail "V2-G: reconcile-status wrote into a torn bundle (derived-header write; REQ-C1.8)"
git -C "$repo" branch planwright/demo/task-1
git -C "$repo" checkout -q planwright/demo/task-1
git -C "$repo" commit -q --allow-empty -m "wip: task 1"
run_hook "$repo" "gh pr create --draft" "https://github.com/x/y/pull/9" \
  || fail "V2-G: hook must stay fail-soft (exit 0) on a torn bundle"
[ "$d_before" = "$(specs_digest "$repo")" ] || fail "V2-G: the hook wrote into a torn bundle (REQ-C1.8)"
git -C "$repo" checkout -q main
grep -q '^\*\*Status:\*\* Active$' "$sd/requirements.md" \
  || fail "V2-G: the torn bundle's authoritative Status header was rewritten"
echo "ok: V2-G a torn bundle (requirements v2, tasks v1) fails closed on every arm (REQ-C1.8)"

echo "PASS: all tasks-pr-sync tests passed"
