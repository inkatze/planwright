#!/bin/sh
# Unit test for scripts/spec-anchor.sh — the canonical content-anchor
# computation defined in doctrine/spec-format.md (REQ-F1.9).
#
# Properties verified:
#   1. An orchestration state move (section change across In progress /
#      Awaiting input / Completed, plus Status / Last activity / Dispatch and
#      unknown annotation bullets) does NOT change the anchor.
#   2. An edited Done-when (or any non-tasks spec file edit) DOES change it.
#   3. Recomputation is deterministic and emits a 40-hex digest.
#   4. Records sort numerically by task id (1 < 2 < 2.5 < 10), pinned by an
#      independently computed golden manifest.
#   5. A non-task H3 section never leaks into the preceding task's record.
#   6. Failure modes fail closed with a clear stderr message: missing or
#      unreadable file, duplicate task ids, unemittable output.
#   7. Fenced illustration contributes nothing (format-grammar Task 6,
#      REQ-C1.2): documenting the task-block format inside a fence does not
#      move the anchor, and an unclosed fence fails closed rather than
#      anchoring over a silently truncated extraction.
#   8. The header-block `**Status:**` line is excluded from the
#      requirements / design / test-spec digests, so every sanctioned
#      lifecycle flip is anchor-invariant across all four files' mirrors, on
#      both format versions (anchor-integrity REQ-A1.1).
#   9. That exclusion is bounded to the single leading header block: a
#      `**Status:**` line in body prose or inside a fence stays anchored, and a
#      malformed, unterminated, or duplicate-Status header block fails closed
#      (anchor-integrity REQ-A1.2).
#
# Runs standalone: ./tests/test-spec-anchor.sh
# (Joins the Task 2 shell test runner's suite when that lands.)
set -eu

# Pin the C locale: the [!0-9a-f] case glob below is collation-dependent for
# the letter range under UTF-8 locales.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes the destination into the command substitution
# below, corrupting the derived script path (house pattern, see sibling tests).
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
anchor="$here/../scripts/spec-anchor.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

is_hex40() {
  case $1 in
    *[!0-9a-f]*) return 1 ;;
  esac
  [ ${#1} -eq 40 ]
}

[ -x "$anchor" ] || fail "scripts/spec-anchor.sh missing or not executable"

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
spec="$tmp/spec"
mkdir "$spec"

# Every one of the three whole-content files carries a header block AND body
# content: a header block that runs to end of file with no body after it is
# malformed input the anchor now refuses (REQ-A1.2), so a header-only stub is
# not a usable fixture.
printf '%s\n' '# Fixture — Requirements' '' '**Status:** Active' '' '## Goal' '' 'A requirement body.' >"$spec/requirements.md"
printf '%s\n' '# Fixture — Design' '' '**Status:** Active' '' '## D-1' '' 'A design body.' >"$spec/design.md"
printf '%s\n' '# Fixture — Test Spec' '' '**Status:** Active' '' '## REQ-X1.1' '' 'A test-spec body.' >"$spec/test-spec.md"

# Baseline: four tasks in Forward plan, with a dotted id, an id >= 10, and a
# wrapped continuation line.
cat >"$spec/tasks.md" <<'EOF'
# Fixture — Tasks

**Status:** Active

Intro prose that is not task-definition content.

## Forward plan

### Task 1 — First thing

- **Deliverables:** A widget; plus a wrapped deliverable line that
  continues onto a second line.
- **Done when:** The widget exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-X1.1
- **Estimated effort:** half day

### Task 2 — Second thing

- **Deliverables:** A gadget.
- **Done when:** The gadget exists.
- **Dependencies:** 1
- **Citations:** D-2 · REQ-X1.2
- **Estimated effort:** 1 day

### Task 2.5 — Inserted thing

- **Deliverables:** A gizmo.
- **Done when:** The gizmo exists.
- **Dependencies:** 2
- **Citations:** D-3 · REQ-X1.3
- **Estimated effort:** half day

### Task 10 — Tenth thing

- **Deliverables:** A doohickey.
- **Done when:** The doohickey exists.
- **Dependencies:** 2.5
- **Citations:** D-4 · REQ-X1.4
- **Estimated effort:** 1 day

## In progress

(none yet)

## Completed

(none yet)
EOF

a_base=$("$anchor" "$spec") || fail "anchor computation failed on baseline"
is_hex40 "$a_base" || fail "anchor is not a 40-hex digest: $a_base"

# --- Property 3: determinism ---
a_again=$("$anchor" "$spec")
[ "$a_base" = "$a_again" ] || fail "non-deterministic: $a_base vs $a_again"

# --- Property 4: golden manifest pins the normative record order ---
# Computed independently of the script: extraction bytes written by hand in
# numeric id order (a lexicographic sort would place Task 10 between Task 1
# and Task 2), hashed and folded into the manifest per the meta-spec.
cat >"$tmp/expected-extraction" <<'EOF'
### Task 1 — First thing
- **Deliverables:** A widget; plus a wrapped deliverable line that
  continues onto a second line.
- **Done when:** The widget exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-X1.1
- **Estimated effort:** half day
### Task 2 — Second thing
- **Deliverables:** A gadget.
- **Done when:** The gadget exists.
- **Dependencies:** 1
- **Citations:** D-2 · REQ-X1.2
- **Estimated effort:** 1 day
### Task 2.5 — Inserted thing
- **Deliverables:** A gizmo.
- **Done when:** The gizmo exists.
- **Dependencies:** 2
- **Citations:** D-3 · REQ-X1.3
- **Estimated effort:** half day
### Task 10 — Tenth thing
- **Deliverables:** A doohickey.
- **Done when:** The doohickey exists.
- **Dependencies:** 2.5
- **Citations:** D-4 · REQ-X1.4
- **Estimated effort:** 1 day
EOF
# The three whole-content files each contribute their content MINUS the
# header-block **Status:** line, dropped with its line terminator so the bytes
# around it join unchanged (REQ-A1.1). Written out by hand here, independently
# of the script, so the golden manifest pins the reduced scope too.
printf '%s\n' '# Fixture — Requirements' '' '' '## Goal' '' 'A requirement body.' >"$tmp/expected-requirements"
printf '%s\n' '# Fixture — Design' '' '' '## D-1' '' 'A design body.' >"$tmp/expected-design"
printf '%s\n' '# Fixture — Test Spec' '' '' '## REQ-X1.1' '' 'A test-spec body.' >"$tmp/expected-test-spec"
exp_anchor=$(printf '%s\n%s\n%s\n%s\n' \
  "$(git hash-object "$tmp/expected-requirements")" \
  "$(git hash-object "$tmp/expected-design")" \
  "$(git hash-object "$tmp/expected-extraction")" \
  "$(git hash-object "$tmp/expected-test-spec")" | git hash-object --stdin)
[ "$a_base" = "$exp_anchor" ] \
  || fail "anchor deviates from the independently computed golden manifest: $a_base vs $exp_anchor"

# --- Property 1: state moves are anchor-invariant ---
# Task 1 completes, Task 2 dispatches, Task 2.5 awaits input; document order
# shuffles; annotations appear, including an unknown future annotation bullet.
cat >"$spec/tasks.md" <<'EOF'
# Fixture — Tasks

**Status:** Active

Intro prose that is not task-definition content.

## In progress

### Task 2 — Second thing

- **Deliverables:** A gadget.
- **Done when:** The gadget exists.
- **Dependencies:** 1
- **Citations:** D-2 · REQ-X1.2
- **Estimated effort:** 1 day
- **Status:** implementing
- **Last activity:** 2026-06-11
- **Reviewed-by:** an annotation kind this version does not know
- **Dispatch:** backend=tmux · window=`fixture-task-2` · dispatched 2026-06-11T00:00Z ·
  branch `planwright/fixture/task-2` · worktree `.claude/worktrees/task-2`

## Awaiting input

### Task 2.5 — Inserted thing

- **Deliverables:** A gizmo.
- **Done when:** The gizmo exists.
- **Dependencies:** 2
- **Citations:** D-3 · REQ-X1.3
- **Estimated effort:** half day
- **Status:** awaiting input — which color should the gizmo be?

## Forward plan

### Task 10 — Tenth thing

- **Deliverables:** A doohickey.
- **Done when:** The doohickey exists.
- **Dependencies:** 2.5
- **Citations:** D-4 · REQ-X1.4
- **Estimated effort:** 1 day

## Completed

### Task 1 — First thing

- **Deliverables:** A widget; plus a wrapped deliverable line that
  continues onto a second line.
- **Done when:** The widget exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-X1.1
- **Estimated effort:** half day
- **Status:** merged in PR #7
- **Last activity:** 2026-06-11
EOF

a_moved=$("$anchor" "$spec") || fail "anchor computation failed after state moves"
[ "$a_base" = "$a_moved" ] || fail "state moves changed the anchor: $a_base vs $a_moved"

# --- Property 2: a meaning edit changes the anchor ---
sed 's/The gizmo exists./The gizmo exists and is documented./' "$spec/tasks.md" >"$spec/tasks.md.new"
mv "$spec/tasks.md.new" "$spec/tasks.md"
a_edited=$("$anchor" "$spec") || fail "anchor computation failed after Done-when edit"
[ "$a_base" != "$a_edited" ] || fail "Done-when edit did not change the anchor"

# --- Property 2b: an edit to a non-tasks file changes the anchor ---
printf '%s\n' '# Fixture — Design' '' '**Status:** Active' '' '## D-1' '' 'New decision text.' >"$spec/design.md"
a_design=$("$anchor" "$spec")
[ "$a_edited" != "$a_design" ] || fail "design.md edit did not change the anchor"

# --- Property 5: a non-task H3 section is excluded from the extraction ---
# A task block ends at the next H2/H3 heading (doctrine/spec-format.md);
# definition-like bullets under a non-task H3 directly following a task block
# must not leak into that task's record.
cp "$spec/tasks.md" "$spec/tasks.md.bak"
cat >>"$spec/tasks.md" <<'EOF'

### Task 9 — Tail thing

- **Done when:** the tail task exists.
EOF
a_tail=$("$anchor" "$spec") || fail "anchor computation failed with tail task"
cat >>"$spec/tasks.md" <<'EOF'

### Notes

- **Done when:** sneaky bullet that must not join the preceding task block
EOF
a_notes=$("$anchor" "$spec") || fail "anchor computation failed with non-task H3 section"
mv "$spec/tasks.md.bak" "$spec/tasks.md"
[ "$a_tail" = "$a_notes" ] || fail "non-task H3 section content leaked into the anchor: $a_tail vs $a_notes"

# --- Zero task blocks: succeeds, deterministic, well-formed ---
cat >"$spec/tasks.md" <<'EOF'
# Fixture — Tasks

**Status:** Active

## Forward plan

(none yet)

## Completed

(none yet)
EOF
a_zero=$("$anchor" "$spec") || fail "anchor computation failed on zero-task fixture"
is_hex40 "$a_zero" || fail "zero-task anchor is not a 40-hex digest: $a_zero"
a_zero2=$("$anchor" "$spec")
[ "$a_zero" = "$a_zero2" ] || fail "zero-task anchor non-deterministic"

# --- Duplicate task ids fail closed, with a clear message ---
cat >"$spec/tasks.md" <<'EOF'
## Forward plan

### Task 2 — Second thing

- **Done when:** The gadget exists.

### Task 2 — Second thing again

- **Done when:** Never; this input is invalid.
EOF
if err=$("$anchor" "$spec" 2>&1 >/dev/null); then
  fail "duplicate task id did not fail"
fi
case $err in
  *"duplicate task id"*) ;;
  *) fail "duplicate-id failure lacks a clear message: $err" ;;
esac

# Restore a valid tasks.md for the remaining cases.
cat >"$spec/tasks.md" <<'EOF'
## Forward plan

### Task 1 — First thing

- **Done when:** The widget exists.
EOF

# --- Unreadable tasks.md fails closed ---
# An awk open failure inside the extraction must not degrade into a
# successful exit with an anchor over an empty task stream. Skipped under
# uid 0: the kernel lets root read mode-000 files, so the case cannot be
# exercised there.
if [ "$(id -u)" -ne 0 ]; then
  chmod 000 "$spec/tasks.md"
  if err=$("$anchor" "$spec" 2>&1 >/dev/null); then
    chmod 644 "$spec/tasks.md"
    fail "unreadable tasks.md did not fail"
  fi
  chmod 644 "$spec/tasks.md"
  case $err in
    *"missing or unreadable"*) ;;
    *) fail "unreadable-file failure lacks a clear message: $err" ;;
  esac
fi

# --- 7. Fenced illustration does not move the anchor (REQ-C1.2) ---
# A bundle that documents the task-block format in a fence is anchoring on its
# real blocks alone: the fenced mock heading and its mock definition fields are
# example text, so appending them leaves the anchor exactly where it was.
fspec="$tmp/fenced"
mkdir "$fspec"
for f in requirements.md design.md tasks.md test-spec.md; do
  cp "$spec/$f" "$fspec/$f"
done
before=$("$anchor" "$fspec") || fail "anchoring the fenced fixture's baseline failed"
cat >>"$fspec/tasks.md" <<'EOF'

## Notes

A task block is written like this:

```markdown
### Task 99 — A mock block that is documentation, not a task

- **Deliverables:** Nothing real.
- **Done when:** Never.
- **Dependencies:** none
- **Citations:** D-99
- **Estimated effort:** 1 day
```
EOF
after=$("$anchor" "$fspec") || fail "anchoring the fenced fixture failed"
[ "$before" = "$after" ] \
  || fail "a fenced mock task block moved the anchor (REQ-C1.2): $before -> $after"

# An unclosed column-0 fence is malformed input: the anchor tool refuses rather
# than anchoring over an extraction the fence silently truncated.
printf '\n```\nan unterminated fence\n' >>"$fspec/tasks.md"
if err=$("$anchor" "$fspec" 2>&1 >/dev/null); then
  fail "an unclosed fence still produced an anchor"
fi
case $err in
  *"open column-0 code fence"*) ;;
  *) fail "the unclosed-fence refusal lacks a clear message: $err" ;;
esac

# --- Unwritable stdout fails closed ---
# git hash-object ignores a failed write to a closed stdout and still exits 0;
# the script must not report success when it could not emit the anchor.
if "$anchor" "$spec" >&- 2>/dev/null; then
  fail "closed stdout did not fail"
fi

# --- Missing file fails closed, with a clear message ---
rm "$spec/test-spec.md"
if err=$("$anchor" "$spec" 2>&1 >/dev/null); then
  fail "missing test-spec.md did not fail"
fi
case $err in
  *"missing or unreadable"*) ;;
  *) fail "missing-file failure lacks a clear message: $err" ;;
esac

# ---------------------------------------------------------------------------
# Property 8: the header-block **Status:** line is excluded from the
# requirements / design / test-spec digests, so every sanctioned lifecycle
# flip is anchor-invariant (anchor-integrity REQ-A1.1, D-2).
# ---------------------------------------------------------------------------

# write_bundle <dir> <format-version> <status> — a complete four-file bundle
# whose ONLY variable is the header `**Status:**` value, mirrored across all
# four files exactly as a real flip writes it. `Last reviewed:` is deliberately
# held constant: it is anchored content that moves in the same rituals that
# re-anchor anyway, so letting it vary here would confound the property.
write_bundle() {
  wb_dir=$1
  wb_ver=$2
  wb_status=$3
  mkdir -p "$wb_dir"

  printf '%s\n' '# Flip Fixture — Requirements' '' \
    "**Status:** $wb_status" '**Last reviewed:** 2026-07-17' \
    "**Format-version:** $wb_ver" '' \
    '## Goal' '' '- **REQ-X1.1** The bundle SHALL exist.' >"$wb_dir/requirements.md"

  printf '%s\n' '# Flip Fixture — Design' '' \
    "**Status:** $wb_status" '**Last reviewed:** 2026-07-17' \
    "**Format-version:** $wb_ver" '' \
    '### D-1: A decision  (N)' '' '**Decision:** The bundle exists.' >"$wb_dir/design.md"

  printf '%s\n' '# Flip Fixture — Test Spec' '' \
    "**Status:** $wb_status" '**Last reviewed:** 2026-07-17' \
    "**Format-version:** $wb_ver" '' \
    '### REQ-X1.1 — existence [test]' '' 'Verified by this suite.' >"$wb_dir/test-spec.md"

  if [ "$wb_ver" -eq 2 ]; then
    printf '%s\n' '# Flip Fixture — Tasks' '' \
      "**Status:** $wb_status" '**Last reviewed:** 2026-07-17' \
      '**Format-version:** 2' '**Execution:** derived — see the status render' '' \
      '## Tasks' '' '### Task 1 — Exist' '' \
      '- **Deliverables:** A bundle.' \
      '- **Done when:** It exists.' \
      '- **Dependencies:** none' \
      '- **Citations:** D-1 · REQ-X1.1' \
      '- **Estimated effort:** half day' >"$wb_dir/tasks.md"
  else
    printf '%s\n' '# Flip Fixture — Tasks' '' \
      "**Status:** $wb_status" '**Last reviewed:** 2026-07-17' \
      '**Format-version:** 1' '' \
      '## Forward plan' '' '### Task 1 — Exist' '' \
      '- **Deliverables:** A bundle.' \
      '- **Done when:** It exists.' \
      '- **Dependencies:** none' \
      '- **Citations:** D-1 · REQ-X1.1' \
      '- **Estimated effort:** half day' >"$wb_dir/tasks.md"
  fi
}

# 8a. format-version 1: the full stored lifecycle set, terminal values
# included, plus the derived Ready<->Active flip the sync hook mirrors.
flip="$tmp/flip"
write_bundle "$flip" 1 Draft
a_flip=$("$anchor" "$flip") || fail "anchor failed on the v1 flip fixture (Draft)"
for st in Ready Active Done Retired Superseded Draft; do
  write_bundle "$flip" 1 "$st"
  a_st=$("$anchor" "$flip") || fail "anchor failed on the v1 flip fixture ($st)"
  [ "$a_flip" = "$a_st" ] \
    || fail "v1 header Status flip to $st moved the anchor ($a_flip -> $a_st; REQ-A1.1)"
done
echo "ok: v1 lifecycle Status flips are anchor-invariant across all four mirrors (REQ-A1.1)"

# 8b. The exclusion is universal, not version-keyed: format-version 2's
# restricted stored set (Draft<->Ready) is invariant under the same rule.
flip2="$tmp/flip2"
write_bundle "$flip2" 2 Draft
a_flip2=$("$anchor" "$flip2") || fail "anchor failed on the v2 flip fixture (Draft)"
for st in Ready Draft; do
  write_bundle "$flip2" 2 "$st"
  a_st=$("$anchor" "$flip2") || fail "anchor failed on the v2 flip fixture ($st)"
  [ "$a_flip2" = "$a_st" ] \
    || fail "v2 header Status flip to $st moved the anchor ($a_flip2 -> $a_st; REQ-A1.1)"
done
echo "ok: the exclusion is universal — v2's stored set flips are anchor-invariant too (REQ-A1.1)"

# 8c. Nothing beyond that one line is excluded: a REQ body edit and a header
# `Format-version:` bump both still move the anchor (REQ-A1.3's "no exclusion
# is performed that the documentation does not state", pinned as behavior).
write_bundle "$flip" 1 Ready
a_ready=$("$anchor" "$flip") || fail "anchor failed on the v1 flip fixture (Ready)"

sed 's/The bundle SHALL exist./The bundle SHALL exist and be documented./' \
  "$flip/requirements.md" >"$flip/requirements.md.new"
mv "$flip/requirements.md.new" "$flip/requirements.md"
a_meaning=$("$anchor" "$flip") || fail "anchor failed after a REQ body edit"
[ "$a_ready" != "$a_meaning" ] || fail "a REQ body edit did not change the anchor"

write_bundle "$flip" 1 Ready
sed 's/^\*\*Format-version:\*\* 1$/**Format-version:** 2/' \
  "$flip/requirements.md" >"$flip/requirements.md.new"
mv "$flip/requirements.md.new" "$flip/requirements.md"
a_ver=$("$anchor" "$flip") || fail "anchor failed after a Format-version bump"
[ "$a_ready" != "$a_ver" ] \
  || fail "a header Format-version bump did not change the anchor (only Status: is excluded; REQ-A1.1)"
echo "ok: meaning edits and the rest of the header block stay anchored (REQ-A1.1, REQ-A1.3)"

# ---------------------------------------------------------------------------
# Property 9: the exclusion is bounded to the single leading header block, and
# a block the extent definition calls malformed fails closed (REQ-A1.2, D-2).
# ---------------------------------------------------------------------------

# 9a. A `**Status:**` line in BODY prose is ordinary anchored content.
write_bundle "$flip" 1 Ready
a_plain=$("$anchor" "$flip") || fail "anchor failed on the bounding baseline"
{ cat "$flip/design.md" && printf '%s\n' '' '**Status:** Draft'; } >"$flip/design.md.new"
mv "$flip/design.md.new" "$flip/design.md"
a_body1=$("$anchor" "$flip") || fail "anchor failed with a body-prose Status line"
[ "$a_plain" != "$a_body1" ] \
  || fail "a body-prose **Status:** line was excluded from the anchor (REQ-A1.2)"
sed 's/^\*\*Status:\*\* Draft$/**Status:** Done/' "$flip/design.md" >"$flip/design.md.new"
mv "$flip/design.md.new" "$flip/design.md"
a_body2=$("$anchor" "$flip") || fail "anchor failed after editing the body-prose Status line"
[ "$a_body1" != "$a_body2" ] \
  || fail "editing a body-prose **Status:** line did not move the anchor (REQ-A1.2)"
echo "ok: a body-prose **Status:** line stays anchored (REQ-A1.2)"

# 9b. Same for a FENCED one: a column-0 fence is outside every header block.
write_bundle "$flip" 1 Ready
{ cat "$flip/test-spec.md" && printf '%s\n' '' '```markdown' '**Status:** Draft' '```'; } \
  >"$flip/test-spec.md.new"
mv "$flip/test-spec.md.new" "$flip/test-spec.md"
a_fence1=$("$anchor" "$flip") || fail "anchor failed with a fenced Status line"
sed 's/^\*\*Status:\*\* Draft$/**Status:** Done/' "$flip/test-spec.md" >"$flip/test-spec.md.new"
mv "$flip/test-spec.md.new" "$flip/test-spec.md"
a_fence2=$("$anchor" "$flip") || fail "anchor failed after editing the fenced Status line"
[ "$a_fence1" != "$a_fence2" ] \
  || fail "editing a fenced **Status:** line did not move the anchor (REQ-A1.2)"
echo "ok: a fenced **Status:** line stays anchored (REQ-A1.2)"

# 9c. The one benign case: a well-formed block declaring no `**Status:**`
# excludes nothing and hashes the whole file. Pinned from both sides — adding
# the declaration to such a block must leave the anchor where it was.
write_bundle "$flip" 1 Ready
printf '%s\n' '# Flip Fixture — Design' '' \
  '**Last reviewed:** 2026-07-17' '**Format-version:** 1' '' \
  '### D-1: A decision  (N)' '' '**Decision:** The bundle exists.' >"$flip/design.md"
a_nostatus=$("$anchor" "$flip") \
  || fail "a header block declaring no **Status:** must not fail closed (REQ-A1.2)"
is_hex40 "$a_nostatus" || fail "no-Status anchor is not a 40-hex digest: $a_nostatus"
printf '%s\n' '# Flip Fixture — Design' '' \
  '**Status:** Ready' '**Last reviewed:** 2026-07-17' '**Format-version:** 1' '' \
  '### D-1: A decision  (N)' '' '**Decision:** The bundle exists.' >"$flip/design.md"
a_added=$("$anchor" "$flip") || fail "anchor failed after adding the header Status declaration"
[ "$a_nostatus" = "$a_added" ] \
  || fail "adding a header **Status:** line to a block that declared none moved the anchor (REQ-A1.2)"
echo "ok: a block declaring no **Status:** excludes nothing, from both sides (REQ-A1.2)"

# 8c-bis. The three byte-level shapes the digest's "byte-exact by construction"
# claim rests on: a declaration on line 1 (the H1-less block the extent
# definition admits, and the only input with no preceding lines to keep), a
# CRLF checkout, and a file with no final newline.
#
# Each is pinned by the same equality, which needs no second implementation of
# the manifest: hashing a file WITH a header `**Status:**` line must equal
# hashing the hand-written file with that line already gone — a file whose
# block declares no Status, so it takes the exclude-nothing path and is hashed
# whole. Any byte the slice adds, drops, or rewrites (a normalized CRLF, an
# appended final newline) breaks the equality; a self-consistent regression in
# both paths cannot hide, because only one of them slices.
exact="$tmp/exact"
byte_exact() { # <label> <file-with-status> <file-without-status>
  write_bundle "$exact" 1 Ready
  cp "$3" "$exact/requirements.md"
  be_without=$("$anchor" "$exact") || fail "$1: anchor failed on the hand-reduced fixture"
  cp "$2" "$exact/requirements.md"
  be_with=$("$anchor" "$exact") || fail "$1: anchor failed on the fixture"
  [ "$be_with" = "$be_without" ] \
    || fail "$1: the slice is not byte-exact ($be_with != the hand-reduced $be_without)"
}

# The variants are written with printf, never through a variable: command
# substitution strips trailing newlines, which is exactly the byte these cases
# are here to pin.
printf '**Status:** Ready\n**Format-version:** 1\n\n## Goal\n\nBody.\n' >"$tmp/x-line1-with"
printf '**Format-version:** 1\n\n## Goal\n\nBody.\n' >"$tmp/x-line1-without"
byte_exact "Status on line 1 (no H1)" "$tmp/x-line1-with" "$tmp/x-line1-without"

printf '# R\r\n\r\n**Status:** Ready\r\n\r\n## Goal\r\n\r\nBody.\r\n' >"$tmp/x-crlf-with"
printf '# R\r\n\r\n\r\n## Goal\r\n\r\nBody.\r\n' >"$tmp/x-crlf-without"
byte_exact "CRLF line endings" "$tmp/x-crlf-with" "$tmp/x-crlf-without"

printf '# R\n\n**Status:** Ready\n\n## Goal\n\nNo trailing newline.' >"$tmp/x-nonl-with"
printf '# R\n\n\n## Goal\n\nNo trailing newline.' >"$tmp/x-nonl-without"
byte_exact "no final newline" "$tmp/x-nonl-with" "$tmp/x-nonl-without"
echo "ok: the slice is byte-exact on a line-1 declaration, CRLF, and a missing final newline (REQ-A1.1)"

# 8d. Malformed, unterminated, and duplicate-Status header blocks fail closed:
# non-zero exit, nothing on stdout, a clear stderr message. Never a silent
# fallback to hashing the whole file.
# The refusal must also NAME the offending file: three files run through the
# same digest helper, so a message that only states the grammar fault leaves the
# operator to bisect the bundle by hand.
# The refusal must also carry the lib's DISTINCT exit code out to the caller.
# The digest helper runs inside a command substitution, so its `exit` leaves a
# subshell and reaches the script through the assignment's status under
# `set -e`; a later refactor to `return`, or a call site moved out of the
# substitution, would collapse every refusal to a single generic status with
# the substring assertions above still green.
expect_fail_closed() {
  # <label> <bundle-dir> <stderr-substring> <offending-file> <expected-exit-code>
  ef_rc=0
  ef_out=$("$anchor" "$2" 2>"$tmp/anchor.err") || ef_rc=$?
  if [ "$ef_rc" -eq 0 ]; then
    fail "$1: anchor exited 0 (printed '$ef_out') where it must fail closed (REQ-A1.2)"
  fi
  [ -z "$ef_out" ] || fail "$1: anchor printed '$ef_out' on a fail-closed path (REQ-A1.2)"
  grep -qF "$3" "$tmp/anchor.err" \
    || fail "$1: stderr lacks '$3': $(cat "$tmp/anchor.err")"
  grep -qF "$4" "$tmp/anchor.err" \
    || fail "$1: stderr does not name the offending file '$4': $(cat "$tmp/anchor.err")"
  [ "$ef_rc" -eq "$5" ] \
    || fail "$1: anchor exited $ef_rc, expected the lib's $5 (REQ-A1.2)"
}

broken="$tmp/broken"

write_bundle "$broken" 1 Ready
printf '%s\n' '# Flip Fixture — Requirements' '' \
  '**Status:** Ready' '**Status:** Active' '' \
  '## Goal' '' '- **REQ-X1.1** The bundle SHALL exist.' >"$broken/requirements.md"
expect_fail_closed "duplicate in-header Status" "$broken" "Status: declarations" "requirements.md" 3

write_bundle "$broken" 1 Ready
printf '%s\n' '# Flip Fixture — Requirements' '' \
  '**Status:** Ready' '**Format-version:** 1' >"$broken/requirements.md"
expect_fail_closed "header block with no body content" "$broken" "no body content" "requirements.md" 4

write_bundle "$broken" 1 Ready
printf '%s\n' 'Prose before anything else.' '' \
  '**Status:** Ready' '' '### D-1: A decision  (N)' >"$broken/design.md"
expect_fail_closed "no leading header block" "$broken" "no leading header block" "design.md" 4

echo "ok: malformed, unterminated, and duplicate-Status header blocks fail closed, naming the file and its exit code (REQ-A1.2)"

echo "PASS: test-spec-anchor"
