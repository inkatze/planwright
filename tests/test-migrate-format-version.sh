#!/bin/bash
# Tests for scripts/migrate-format-version.sh — the one-shot v1→v2 bundle
# migration (invariant-tasks Task 6; REQ-D1.2, REQ-D1.3, REQ-A1.4, REQ-C1.8,
# REQ-C1.9, REQ-E1.4 · D-10, D-3).
#
# The migration converts a live (Draft/Ready/Active) v1 bundle to
# format-version 2: placement sections collapse into a single `## Tasks`
# section sorted by task id, state annotation bullets are stripped, parked
# task blocks in any human-payload section convert to reference bullets, the
# stored header is restricted to the human-gated set (Active → Ready), the
# static `**Execution:**` pointer line is added, and `Format-version:` bumps
# to 2 on all four files — preserving task definition lines byte-for-byte so
# the canonical tasks.md extraction digest is unchanged. Signed bundles gain
# a dated Changelog entry plus the expression-only re-anchor entry in the
# kickoff brief that cites it; a Draft takes neither. Idempotent, per-bundle
# atomic, re-runnable after a partial run; hostile identifiers,
# out-of-containment paths, and an unparseable `Format-version:` are refused
# with a clean, sanitized error (fail closed).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
MIGRATE="$here/../scripts/migrate-format-version.sh"
ANCHOR="$here/../scripts/spec-anchor.sh"
VALIDATE="$here/../scripts/spec-validate.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$MIGRATE" ] || fail "scripts/migrate-format-version.sh missing or not executable"
[ -x "$ANCHOR" ] || fail "scripts/spec-anchor.sh missing (the re-anchor computation)"
[ -x "$VALIDATE" ] || fail "scripts/spec-validate.sh missing (the v2 result check)"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The canonical tasks.md definition-content extraction oracle comes from the
# shared spec-parse grammar lib (format-grammar D-3, REQ-B1.2) — the same
# stream the migration's own self-check and scripts/spec-anchor.sh consume,
# including the duplicate-id fail-closed guard. The invariant under test is
# that this stream — heading plus the five definition field bullets with
# continuations, records sorted by task id — survives migration
# byte-for-byte (REQ-A1.4, REQ-D1.2). The lib's own behavior is pinned
# independently by tests/test-spec-parse.sh (unit tests) and
# tests/test-spec-anchor.sh (a hand-written golden manifest), so a lib bug
# cannot pass both this suite and those silently.
# Guarded source per the lib's consumer contract (REQ-B1.6a): existence and
# readability checked before the `.` so a missing lib names itself instead
# of aborting with the shell's own diagnostic.
[ -f "$here/../scripts/spec-parse.sh" ] && [ -r "$here/../scripts/spec-parse.sh" ] \
  || fail "scripts/spec-parse.sh missing or unreadable (the extraction oracle)"
# shellcheck source=scripts/spec-parse.sh
. "$here/../scripts/spec-parse.sh" || fail "sourcing scripts/spec-parse.sh failed"

# section_content <file> <section> — the lines of one H2 section's body.
section_content() {
  awk -v want="## $2" '
    /^## / { on = ($0 == want); next }
    on
  ' "$1"
}

# headers_ok <spec-dir> <status> <label> — all four files carry the given
# Status, Format-version 2, and the pointer line in its fixed vocabulary.
headers_ok() {
  for f in requirements.md design.md tasks.md test-spec.md; do
    grep -q "^\*\*Status:\*\* $2\$" "$1/$f" || fail "$3: $f Status is not $2"
    grep -q '^\*\*Format-version:\*\* 2$' "$1/$f" || fail "$3: $f Format-version is not 2"
    grep -qxF '**Execution:** derived — see the status render' "$1/$f" \
      || fail "$3: $f missing the canonical pointer line"
  done
}

# snapshot <dir> <out-dir> — copy every file for byte-level comparison.
snapshot() {
  (cd "$1" && find . -type f | sort) | while read -r rel; do
    mkdir -p "$2/$(dirname "$rel")"
    cp "$1/$rel" "$2/$rel"
  done
}

# assert_same_tree <dir> <snap-dir> <label> — byte-identical file tree.
assert_same_tree() {
  (cd "$1" && find . -type f | sort) >"$tmp/tree.now"
  (cd "$2" && find . -type f | sort) >"$tmp/tree.snap"
  cmp -s "$tmp/tree.now" "$tmp/tree.snap" || fail "$3: file set changed"
  while read -r rel; do
    cmp -s "$1/$rel" "$2/$rel" || fail "$3: $rel changed"
  done <"$tmp/tree.now"
}

# --- Fixture corpus -------------------------------------------------------

# seeded_bundle <spec-dir> <status> — a fully valid v1 bundle exercising every
# transform arm: task blocks scattered over Forward plan / In progress /
# Completed (out of id order), state annotations of all three kinds, a parked
# block in each human-payload section, plain (non-task) payload bullets that
# must survive, intro prose, and wrapped definition-field continuation lines.
seeded_bundle() {
  sd=$1
  st=$2
  mkdir -p "$sd"
  cat >"$sd/requirements.md" <<EOF
# Seeded — Requirements

**Status:** $st
**Last reviewed:** 2026-07-01
**Format-version:** 1

## Goal

Exercise the v1 to v2 migration.

## Scope

### In scope

- Migration fixtures.

### Out of scope

- Everything else.

## REQ-A — fixtures

- **REQ-A1.1** The fixture SHALL exist.
  *(Cites: D-1.)*
- **REQ-A1.2** The fixture SHALL migrate.
  *(Cites: D-1.)*

## Changelog

- 2026-07-01 — Initial draft.

## Sources

- **Fixture seed.** Hand-authored for the migration suite.
EOF
  cat >"$sd/design.md" <<EOF
# Seeded — Design

**Status:** $st
**Last reviewed:** 2026-07-01
**Format-version:** 1

## Decision log

### D-1: One decision  (N)

**Decision:** Keep the fixture small.

**Alternatives considered:**
- A big fixture. Rejected because: slow.

**Chosen because:** small is enough.
EOF
  cat >"$sd/test-spec.md" <<EOF
# Seeded — Test Spec

**Status:** $st
**Last reviewed:** 2026-07-01
**Format-version:** 1

Coverage mix: all [test].

### REQ-A1.1 — existence [test]

The suite runs.

### REQ-A1.2 — migration [test]

This suite.
EOF
  cat >"$sd/tasks.md" <<EOF
# Seeded — Tasks

**Status:** $st
**Last reviewed:** 2026-07-01
**Format-version:** 1

Intro prose that must survive the migration byte-for-byte.

## Forward plan

### Task 2 — Beta

- **Deliverables:** Beta output with a wrapped continuation line that
  goes on and on to a second physical line.
- **Done when:** Beta done.
- **Dependencies:** 1
- **Citations:** REQ-A1.2
- **Estimated effort:** 1 day
- **Last activity:** 2026-07-02

## In progress

### Task 1 — Alpha

- **Deliverables:** Alpha output.
- **Done when:** Alpha done.
- **Dependencies:** none
- **Citations:** REQ-A1.1
- **Estimated effort:** 1 day
- **Status:** implementing
- **Last activity:** 2026-07-03
- **Dispatch:** backend=tmux · window=w1 · dispatched 2026-07-03T00:00:00Z ·
  branch planwright/seeded/task-1 · worktree .claude/worktrees/seeded-task-1

## Awaiting input

(none yet)

### Task 4 — Delta

- **Deliverables:** Delta output.
- **Done when:** Delta done.
- **Dependencies:** 1
- **Citations:** REQ-A1.2
- **Estimated effort:** half day
- **Status:** awaiting input — which flavor should Delta use?
  The options are vanilla or chocolate.

## Completed

### Task 3 — Gamma

- **Deliverables:** Gamma output.
- **Done when:** Gamma done.
- **Dependencies:** none
- **Citations:** REQ-A1.1
- **Estimated effort:** 1 day
- **Status:** Completed · PR #7 merged 2026-07-01
- **Last activity:** 2026-07-01

## Deferred

- **A plain deferral.** Not a task block; must survive. Confidence: high.
  **Gate:** GATE(when: never).
  Citations: D-1.

### Task 5 — Epsilon

- **Deliverables:** Epsilon output.
- **Done when:** Epsilon done.
- **Dependencies:** none
- **Citations:** REQ-A1.1
- **Estimated effort:** half day
- **Status:** deferred pending the gate

## Out of scope

- A plain exclusion bullet that must survive.

### Task 6 — Zeta

- **Deliverables:** Zeta output.
- **Done when:** Zeta done.
- **Dependencies:** none
- **Citations:** REQ-A1.1
- **Estimated effort:** half day
EOF
}

# signed_brief <spec-dir> <spec-rel> — a kickoff brief whose sign-off record
# ends with an anchor entry (the shape the migration appends after).
signed_brief() {
  cat >"$1/kickoff-brief.md" <<EOF
# Seeded — Kickoff Brief

## 1. Header

- **Spec:** \`$2\`

## 8. Sign-off

Signed off: 2026-07-01

Class: meaning
Lens-pass: recorded above, findings dispositioned 2026-07-01.
Anchor: \`0000000000000000000000000000000000000000\` — computed as
\`scripts/spec-anchor.sh $2\`

## 9. Amendment log

(none yet — this section receives future amendment and self-re-anchor
entries.)
EOF
}

repo=$tmp/corpus
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t
git -C "$repo" config commit.gpgsign false

seeded_bundle "$repo/specs/seeded" Active
signed_brief "$repo/specs/seeded" specs/seeded

seeded_bundle "$repo/specs/draft-spec" Draft

seeded_bundle "$repo/specs/done-spec" Done
signed_brief "$repo/specs/done-spec" specs/done-spec

seeded_bundle "$repo/specs/retired-spec" Retired
signed_brief "$repo/specs/retired-spec" specs/retired-spec

seeded_bundle "$repo/specs/superseded-spec" Superseded
signed_brief "$repo/specs/superseded-spec" specs/superseded-spec

# A signed bundle whose changelog is genuinely multi-entry ascending:
# exercises the first<last append arm of direction detection (the seeded
# bundle's single entry takes the first==last arm instead).
seeded_bundle "$repo/specs/asc-spec" Ready
signed_brief "$repo/specs/asc-spec" specs/asc-spec
awk '
  /^- 2026-07-01 — Initial draft\.$/ {
    print "- 2026-06-20 — Earlier entry."
    print "- 2026-07-01 — Initial draft."
    next
  }
  { print }
' "$repo/specs/asc-spec/requirements.md" >"$tmp/as" \
  && mv "$tmp/as" "$repo/specs/asc-spec/requirements.md"

# A stored-Ready signed bundle whose changelog is newest-first (descending):
# exercises Ready→Ready and the prepend arm of changelog-direction detection.
seeded_bundle "$repo/specs/ready-desc" Ready
signed_brief "$repo/specs/ready-desc" specs/ready-desc
awk '
  /^- 2026-07-01 — Initial draft\.$/ {
    print "- 2026-07-05 — Later entry."
    print "- 2026-07-01 — Initial draft."
    next
  }
  { print }
' "$repo/specs/ready-desc/requirements.md" >"$tmp/rd" \
  && mv "$tmp/rd" "$repo/specs/ready-desc/requirements.md"

# A Draft bundle whose human-payload sections are all empty placeholders:
# exercises the `(none yet)` preservation arm.
ep=$repo/specs/empty-payload
seeded_bundle "$ep" Draft
cat >"$ep/tasks.md" <<EOF
# Empty — Tasks

**Status:** Draft
**Last reviewed:** 2026-07-01
**Format-version:** 1

## Forward plan

### Task 1 — Alpha

- **Deliverables:** Alpha output.
- **Done when:** Alpha done.
- **Dependencies:** none
- **Citations:** REQ-A1.1
- **Estimated effort:** 1 day

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
EOF

# A born-v2 signed bundle: already format-version 2 with no migration
# artifacts. The sweep must leave it byte-identical — completing a "missing"
# re-anchor here would forge a migration that never happened.
bornv2=$repo/specs/born-v-two
mkdir -p "$bornv2"
for bf in requirements design test-spec; do
  cat >"$bornv2/$bf.md" <<EOF
# Born — ${bf}

**Status:** Ready
**Last reviewed:** 2026-07-01
**Format-version:** 2
**Execution:** derived — see the status render

## Placeholder

- **REQ-A1.1** Placeholder. *(Cites: D-1.)*
EOF
done
cat >"$bornv2/tasks.md" <<EOF
# Born — Tasks

**Status:** Ready
**Last reviewed:** 2026-07-01
**Format-version:** 2
**Execution:** derived — see the status render

## Tasks

### Task 1 — Only

- **Deliverables:** One.
- **Done when:** Done.
- **Dependencies:** none
- **Citations:** REQ-A1.1
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
signed_brief "$bornv2" specs/born-v-two

# An underscore accumulator the sweep must exclude entirely.
mkdir -p "$repo/specs/_observations"
printf '%s\n' '# Observations' 'not a bundle' >"$repo/specs/_observations/notes.md"

git -C "$repo" add -A
git -C "$repo" commit -qm fixture

before_extract=$tmp/seeded.extract.before
spec_parse_extract_tasks "$repo/specs/seeded/tasks.md" >"$before_extract"
[ -s "$before_extract" ] || fail "precondition: seeded fixture extraction is empty"
draft_extract_before=$tmp/draft.extract.before
spec_parse_extract_tasks "$repo/specs/draft-spec/tasks.md" >"$draft_extract_before"
cp "$repo/specs/seeded/tasks.md" "$tmp/seeded.tasks.v1"

done_snap=$tmp/done.snap
snapshot "$repo/specs/done-spec" "$done_snap"
retired_snap=$tmp/retired.snap
snapshot "$repo/specs/retired-spec" "$retired_snap"
superseded_snap=$tmp/superseded.snap
snapshot "$repo/specs/superseded-spec" "$superseded_snap"
born_snap=$tmp/born.snap
snapshot "$bornv2" "$born_snap"

# --- Run 1: sweep the corpus ----------------------------------------------

out=$(cd "$repo" && "$MIGRATE" specs 2>"$tmp/run1.err") \
  || fail "sweep over a clean live corpus exited non-zero: $(cat "$tmp/run1.err")"

# The extraction digest is unchanged: definition lines survive byte-for-byte
# (REQ-A1.4, REQ-D1.2).
after_extract=$tmp/seeded.extract.after
spec_parse_extract_tasks "$repo/specs/seeded/tasks.md" >"$after_extract"
cmp -s "$before_extract" "$after_extract" \
  || fail "REQ-A1.4: seeded extraction changed across migration ($(diff "$before_extract" "$after_extract" | head -5))"
d_before=$(git hash-object --stdin <"$before_extract")
d_after=$(git hash-object --stdin <"$after_extract")
[ "$d_before" = "$d_after" ] || fail "REQ-A1.4: extraction digest moved"
echo "ok: the canonical extraction digest is unchanged across migration (REQ-A1.4, REQ-D1.2)"

# REQ-D1.2's raw line-level diff, independent of the shared extraction
# algorithm (the digest check above and the script's own self-check use the
# same awk, so they cannot catch a corruption that algorithm is blind to).
# Sorted line multisets make block relocation cancel out, leaving exactly
# the lines the migration deleted: each must be a state annotation bullet
# (or one of the fixture's known annotation continuations), a placement
# heading, a consumed placeholder, or a restricted/bumped header line.
sort "$tmp/seeded.tasks.v1" >"$tmp/seeded.v1.sorted"
sort "$repo/specs/seeded/tasks.md" >"$tmp/seeded.v2.sorted"
comm -23 "$tmp/seeded.v1.sorted" "$tmp/seeded.v2.sorted" \
  | grep -v '^[ \t]*$' >"$tmp/seeded.dropped" || true
while IFS= read -r dropped; do
  case $dropped in
    '- **Status:**'* | '- **Last activity:**'* | '- **Dispatch:**'*) ;;
    '  branch planwright/seeded/task-1 · worktree .claude/worktrees/seeded-task-1') ;;
    '  The options are vanilla or chocolate.') ;;
    '## Forward plan' | '## In progress' | '## Completed') ;;
    '(none yet)' | '**Status:** Active' | '**Format-version:** 1') ;;
    *) fail "REQ-D1.2 raw diff: migration dropped a line outside the sanctioned set: '$dropped'" ;;
  esac
done <"$tmp/seeded.dropped"
echo "ok: the raw line-level diff drops only annotations, placement headings, and header lines (REQ-D1.2)"

# The migrated bundle is valid format-version 2 at errors-block severity.
"$VALIDATE" "$repo/specs/seeded" >"$tmp/val.out" 2>&1 \
  || fail "REQ-D1.2: migrated seeded bundle does not validate: $(cat "$tmp/val.out")"
grep -q '0 error(s)' "$tmp/val.out" || fail "REQ-D1.2: validator reported errors: $(cat "$tmp/val.out")"
echo "ok: the migrated bundle validates cleanly as format-version 2 (REQ-D1.2)"

# Structure: one ## Tasks section holding all six blocks in id order; no
# placement sections; no state annotation bullets; intro prose preserved.
tk=$repo/specs/seeded/tasks.md
grep -qE '^## (Forward plan|In progress|Completed)$' "$tk" \
  && fail "placement sections survived migration"
[ "$(grep -c '^### Task ' "$tk")" = 6 ] || fail "expected six task blocks, got $(grep -c '^### Task ' "$tk")"
section_content "$tk" Tasks | grep -c '^### Task ' >"$tmp/n" || true
[ "$(cat "$tmp/n")" = 6 ] || fail "expected all six blocks under ## Tasks, got $(cat "$tmp/n")"
ids=$(grep '^### Task ' "$tk" | awk '{ print $3 }' | tr '\n' ' ')
[ "$ids" = "1 2 3 4 5 6 " ] || fail "blocks not id-sorted: $ids"
grep -qE '^- \*\*(Status|Last activity|Dispatch):\*\*' "$tk" \
  && fail "state annotation bullets survived migration"
grep -q 'Intro prose that must survive' "$tk" || fail "intro prose dropped"
echo "ok: placement sections collapse into an id-sorted ## Tasks with annotations stripped (REQ-D1.2)"

# Parked blocks became reference bullets in their sections; plain payload
# bullets survive (D-3).
section_content "$tk" 'Awaiting input' | grep -q '^- \*\*Task 4\*\*' \
  || fail "Awaiting-input parked block did not convert to a reference bullet"
section_content "$tk" 'Deferred' | grep -q '^- \*\*Task 5\*\*' \
  || fail "Deferred parked block did not convert to a reference bullet"
section_content "$tk" 'Out of scope' | grep -q '^- \*\*Task 6\*\*' \
  || fail "Out-of-scope parked block did not convert to a reference bullet"
section_content "$tk" 'Deferred' | grep -q 'A plain deferral' || fail "plain deferral bullet dropped"
section_content "$tk" 'Out of scope' | grep -q 'plain exclusion bullet' || fail "plain exclusion bullet dropped"
echo "ok: parked blocks in every human-payload section convert to reference bullets (D-3, REQ-D1.2)"

# The reference bullet carries the v1 Status text as the human payload —
# including a wrapped continuation line — and a parked block with no Status
# annotation gets the fallback wording; the `(none yet)` placeholder drops
# when the first bullet lands (D-3, REQ-D1.2).
section_content "$tk" 'Awaiting input' \
  | grep -q 'which flavor should Delta use? The options are vanilla or chocolate\.' \
  || fail "reference bullet dropped the v1 Status payload (or its continuation line)"
section_content "$tk" 'Deferred' | grep -q 'Task 5\*\* — deferred pending the gate' \
  || fail "Deferred reference bullet dropped the v1 Status payload"
section_content "$tk" 'Out of scope' | grep -q 'Task 6\*\* — parked in the v1 "## Out of scope" section' \
  || fail "no-Status parked block missing the fallback payload wording"
section_content "$tk" 'Awaiting input' | grep -q '(none yet)' \
  && fail "Awaiting-input (none yet) placeholder survived alongside a reference bullet"
echo "ok: reference bullets carry the v1 Status payload; placeholders drop when bullets land (D-3)"

# Headers: Active restricts to Ready; format-version 2 and the pointer line
# on all four files.
headers_ok "$repo/specs/seeded" Ready "seeded"
echo "ok: the stored header restricts Active to Ready with the pointer line on all four files (D-4, D-5)"

# Signed bundle: a dated Changelog entry plus the brief's expression-only
# re-anchor entry citing it, whose anchor recomputes to the current value
# (REQ-D1.2).
today=$(date +%Y-%m-%d)
grep -q "^- $today — Migrated to format-version 2" "$repo/specs/seeded/requirements.md" \
  || fail "signed bundle missing the dated migration Changelog entry"
brief=$repo/specs/seeded/kickoff-brief.md
grep -q 'self-re-anchor' "$brief" || fail "signed bundle missing the re-anchor entry"
awk '/self-re-anchor/,0' "$brief" >"$tmp/entry"
grep -q '^Class: expression-only$' "$tmp/entry" || fail "re-anchor entry not marked Class: expression-only"
# shellcheck disable=SC2016 # the backticks are literal markdown, not expansions
rec=$(grep -o 'Anchor: `[0-9a-f]*`' "$tmp/entry" | sed 's/Anchor: `//; s/`//')
[ -n "$rec" ] || fail "re-anchor entry carries no anchor hash"
cur=$("$ANCHOR" "$repo/specs/seeded")
[ "$rec" = "$cur" ] || fail "recorded anchor $rec != recomputed $cur"
grep -q 'scripts/spec-anchor.sh specs/seeded' "$tmp/entry" \
  || fail "re-anchor entry does not record the sanctioned command with the bundle path"
grep -qi 'changelog' "$tmp/entry" || fail "re-anchor entry does not cite the changelog line"
grep -q '^(none yet' "$brief" \
  && fail "amendment-log (none yet) placeholder paragraph survived the entry append"
# Single-entry changelog (the first==last append arm): the migration entry
# is appended after the existing entry, keeping the changelog monotonic.
awk '/^## Changelog[ \t]*$/,/^## Sources[ \t]*$/' "$repo/specs/seeded/requirements.md" \
  | grep '^- 20' | head -1 | grep -q '2026-07-01' \
  || fail "single-entry changelog: migration entry was not appended after existing entries"
# The insert rides exactly one separator blank even when the section already
# ends blank: a doubled blank would trip markdownlint MD012 on the output.
awk 'blank && /^[ \t]*$/ { exit 1 } { blank = ($0 ~ /^[ \t]*$/) }' \
  "$repo/specs/seeded/requirements.md" \
  || fail "ascending changelog: migration introduced consecutive blank lines (MD012)"
echo "ok: a signed bundle gains the dated Changelog entry and a valid expression-only re-anchor (REQ-D1.2)"

# Ready→Ready: a stored-Ready signed bundle migrates in place, stays Ready,
# and its newest-first changelog gets the entry prepended (direction-aware).
headers_ok "$repo/specs/ready-desc" Ready "ready-desc"
awk '/^## Changelog[ \t]*$/,/^## Sources[ \t]*$/' "$repo/specs/ready-desc/requirements.md" \
  | grep '^- 20' | head -1 | grep -q "Migrated to format-version 2" \
  || fail "descending changelog: migration entry was not prepended"
awk 'blank && /^[ \t]*$/ { exit 1 } { blank = ($0 ~ /^[ \t]*$/) }' \
  "$repo/specs/ready-desc/requirements.md" \
  || fail "descending changelog: migration introduced consecutive blank lines (MD012)"
# shellcheck disable=SC2016 # the backticks are literal markdown, not expansions
rec_rd=$(awk '/self-re-anchor/,0' "$repo/specs/ready-desc/kickoff-brief.md" \
  | grep -o '`[0-9a-f]\{40\}`' | head -1 | tr -d '\140')
cur_rd=$("$ANCHOR" "$repo/specs/ready-desc")
[ "$rec_rd" = "$cur_rd" ] || fail "ready-desc recorded anchor $rec_rd != recomputed $cur_rd"
echo "ok: a stored-Ready bundle stays Ready and a newest-first changelog is prepended (REQ-D1.3, D-10)"

# True multi-entry ascending changelog: the migration entry is appended
# after the newest existing entry (the first<last append arm), never
# prepended between the heading and the oldest entry.
awk '/^## Changelog[ \t]*$/,/^## Sources[ \t]*$/' "$repo/specs/asc-spec/requirements.md" \
  | grep '^- 20' >"$tmp/asc.entries"
head -1 "$tmp/asc.entries" | grep -q '2026-06-20' \
  || fail "ascending changelog: oldest entry no longer first"
tail -1 "$tmp/asc.entries" | grep -q 'Migrated to format-version 2' \
  || fail "ascending changelog: migration entry was not appended last"
echo "ok: a multi-entry ascending changelog appends the migration entry last (D-10)"

# Empty human-payload sections keep their (none yet) placeholders.
for sec in 'Awaiting input' 'Deferred' 'Out of scope'; do
  section_content "$repo/specs/empty-payload/tasks.md" "$sec" | grep -q '(none yet)' \
    || fail "empty-payload: $sec lost its (none yet) placeholder"
done
echo "ok: empty human-payload sections keep their (none yet) placeholders (D-2)"

# Draft bundle: same byte-stable transform, no changelog entry, no brief.
draft_extract_after=$tmp/draft.extract.after
spec_parse_extract_tasks "$repo/specs/draft-spec/tasks.md" >"$draft_extract_after"
cmp -s "$draft_extract_before" "$draft_extract_after" || fail "draft extraction changed"
headers_ok "$repo/specs/draft-spec" Draft "draft-spec"
grep -q 'Migrated to format-version 2' "$repo/specs/draft-spec/requirements.md" \
  && fail "a Draft bundle must not gain a migration Changelog entry"
[ -f "$repo/specs/draft-spec/kickoff-brief.md" ] && fail "a Draft bundle must not gain a brief"
echo "ok: a Draft takes the byte-stable transform with no re-anchor and no changelog line (REQ-D1.3)"

# Done and terminal bundles are byte-identical; the born-v2 bundle is a
# clean no-op (never re-completed); the accumulator is excluded.
assert_same_tree "$repo/specs/done-spec" "$done_snap" "Done bundle rewritten"
assert_same_tree "$repo/specs/retired-spec" "$retired_snap" "Retired bundle rewritten"
assert_same_tree "$repo/specs/superseded-spec" "$superseded_snap" "Superseded bundle rewritten"
assert_same_tree "$bornv2" "$born_snap" "born-v2 bundle rewritten"
case "$out" in
  *_observations*) fail "underscore accumulator treated as a bundle" ;;
esac
grep -q '_observations' "$tmp/run1.err" \
  && fail "underscore accumulator surfaced on stderr (should be excluded silently)"
echo "ok: Done/terminal bundles stay byte-identical; born-v2 is a clean no-op (REQ-D1.3, D-10)"

# --- Run 2: idempotence — a second sweep is a byte-level no-op. -----------

specs_snap=$tmp/specs.snap
snapshot "$repo/specs" "$specs_snap"
out2=$(cd "$repo" && "$MIGRATE" specs 2>/dev/null) || fail "second sweep exited non-zero"
assert_same_tree "$repo/specs" "$specs_snap" "idempotence"
case "$out2" in
  *"0 migrated,"*) ;;
  *) fail "second sweep reported a migration: $out2" ;;
esac
echo "ok: a second run over a migrated corpus is a byte-level no-op (REQ-D1.2)"

# --- Partial run: files migrated, re-anchor entry missing → completed. ----

repo2=$tmp/corpus2
mkdir -p "$repo2/specs"
git -C "$repo2" init -q -b main
git -C "$repo2" config user.email t@example.com
git -C "$repo2" config user.name t
git -C "$repo2" config commit.gpgsign false
cp -R "$repo/specs/seeded" "$repo2/specs/partial"
# Rewrite the recorded bundle path in the copied brief, then truncate it at
# the migration entry: the four files read v2 and carry the changelog line,
# but the re-anchor entry is gone — the interrupted-run state.
sed 's|specs/seeded|specs/partial|g' "$repo2/specs/partial/kickoff-brief.md" >"$tmp/pb" \
  && awk '/self-re-anchor/ { exit } { print }' "$tmp/pb" >"$repo2/specs/partial/kickoff-brief.md"
sed 's|# Seeded|# Partial|' "$repo2/specs/partial/requirements.md" >"$tmp/pr" \
  && mv "$tmp/pr" "$repo2/specs/partial/requirements.md"
git -C "$repo2" add -A
git -C "$repo2" commit -qm fixture

(cd "$repo2" && "$MIGRATE" specs >"$tmp/run3.out" 2>"$tmp/run3.err") \
  || fail "partial-run completion exited non-zero: $(cat "$tmp/run3.err")"
grep -q 'self-re-anchor' "$repo2/specs/partial/kickoff-brief.md" \
  || fail "REQ-D1.2: a re-run did not complete the missing re-anchor entry"
# The completion is classified and counted as a repair, not a migration or
# a no-op: mis-bucketing would corrupt the summary tally.
grep -q '^repaired: partial' "$tmp/run3.out" \
  || fail "partial-run completion not classified as repaired: $(cat "$tmp/run3.out")"
grep -q '1 repaired' "$tmp/run3.out" \
  || fail "summary tally does not count the repair: $(cat "$tmp/run3.out")"
n_clog=$(grep -c 'Migrated to format-version 2' "$repo2/specs/partial/requirements.md" || true)
[ "$n_clog" = 1 ] || fail "changelog entry duplicated on completion ($n_clog)"
# shellcheck disable=SC2016 # the backticks are literal markdown, not expansions
rec3=$(awk '/self-re-anchor/,0' "$repo2/specs/partial/kickoff-brief.md" \
  | grep -o 'Anchor: `[0-9a-f]*`' | sed 's/Anchor: `//; s/`//')
cur3=$("$ANCHOR" "$repo2/specs/partial")
[ "$rec3" = "$cur3" ] || fail "completed re-anchor $rec3 != recomputed $cur3"
echo "ok: a re-run completes a missing re-anchor instead of no-oping past a v2 file (REQ-D1.2)"

# --- Fail-closed version keying (REQ-C1.8). -------------------------------

repo3=$tmp/corpus3
mkdir -p "$repo3/specs"
seeded_bundle "$repo3/specs/unparseable" Ready
sed 's/^\*\*Format-version:\*\* 1$/**Format-version:** wat/' \
  "$repo3/specs/unparseable/requirements.md" >"$tmp/ur" \
  && mv "$tmp/ur" "$repo3/specs/unparseable/requirements.md"
unp_snap=$tmp/unp.snap
snapshot "$repo3/specs/unparseable" "$unp_snap"
if (cd "$repo3" && "$MIGRATE" specs/unparseable >/dev/null 2>"$tmp/unp.err"); then
  fail "REQ-C1.8: an unparseable Format-version was not refused"
fi
assert_same_tree "$repo3/specs/unparseable" "$unp_snap" "unparseable-Format-version bundle written"
grep -qi 'format-version' "$tmp/unp.err" || fail "refusal does not name the Format-version failure"
echo "ok: an unparseable Format-version is refused fail-closed with no write (REQ-C1.8)"

seeded_bundle "$repo3/specs/missing-fv" Ready
grep -v '^\*\*Format-version:\*\*' "$repo3/specs/missing-fv/requirements.md" >"$tmp/mf" \
  && mv "$tmp/mf" "$repo3/specs/missing-fv/requirements.md"
mfv_snap=$tmp/mfv.snap
snapshot "$repo3/specs/missing-fv" "$mfv_snap"
if (cd "$repo3" && "$MIGRATE" specs/missing-fv >/dev/null 2>&1); then
  fail "REQ-C1.8: a missing Format-version was not refused"
fi
assert_same_tree "$repo3/specs/missing-fv" "$mfv_snap" "missing-Format-version bundle written"
echo "ok: a missing Format-version is refused fail-closed with no write (REQ-C1.8)"

# A numeric-but-unsupported Format-version (e.g. 3) takes its own refusal
# arm, distinct from unparseable: this migration implements exactly 1 → 2.
seeded_bundle "$repo3/specs/future-fv" Ready
sed 's/^\*\*Format-version:\*\* 1$/**Format-version:** 3/' \
  "$repo3/specs/future-fv/requirements.md" >"$tmp/ff" \
  && mv "$tmp/ff" "$repo3/specs/future-fv/requirements.md"
ffv_snap=$tmp/ffv.snap
snapshot "$repo3/specs/future-fv" "$ffv_snap"
if (cd "$repo3" && "$MIGRATE" specs/future-fv >/dev/null 2>"$tmp/ffv.err"); then
  fail "REQ-C1.8: an unsupported numeric Format-version was not refused"
fi
assert_same_tree "$repo3/specs/future-fv" "$ffv_snap" "unsupported-Format-version bundle written"
grep -q 'unsupported Format-version' "$tmp/ffv.err" \
  || fail "refusal does not name the unsupported version: $(cat "$tmp/ffv.err")"
echo "ok: a numeric unsupported Format-version is refused fail-closed with no write (REQ-C1.8)"

# An already-v2 bundle carrying the migration changelog marker but missing
# its kickoff brief cannot have its re-anchor completed: the repair arm must
# refuse (not no-op past it, not crash, not write anything).
mnb=$tmp/marker-no-brief
mkdir -p "$mnb/specs"
cp -R "$repo/specs/seeded" "$mnb/specs/poisoned"
rm "$mnb/specs/poisoned/kickoff-brief.md"
mnb_snap=$tmp/mnb.snap
snapshot "$mnb/specs/poisoned" "$mnb_snap"
if (cd "$mnb" && "$MIGRATE" specs/poisoned >/dev/null 2>"$tmp/mnb.err"); then
  fail "a marker-carrying v2 bundle with no brief was not refused"
fi
assert_same_tree "$mnb/specs/poisoned" "$mnb_snap" "marker-no-brief bundle written"
grep -q 'cannot complete the re-anchor' "$tmp/mnb.err" \
  || fail "marker-no-brief refusal not diagnosed: $(cat "$tmp/mnb.err")"
echo "ok: a v2 bundle with the migration marker but no brief is refused (REQ-D1.2)"

# Per-bundle isolation in a mixed sweep: a refused bundle must not stop the
# sweep — the valid sibling still migrates, the tally counts both, and the
# exit code reports the refusal (the script header's isolation contract).
mix=$tmp/mixed-corpus
mkdir -p "$mix/specs"
seeded_bundle "$mix/specs/bad" Draft
printf '%s\n' '' '## Backlog' '' '(nothing)' >>"$mix/specs/bad/tasks.md"
seeded_bundle "$mix/specs/good" Draft
bad_snap=$tmp/bad.snap
snapshot "$mix/specs/bad" "$bad_snap"
if mix_out=$(cd "$mix" && "$MIGRATE" specs 2>"$tmp/mix.err"); then
  fail "a mixed sweep with a refused bundle exited zero"
fi
assert_same_tree "$mix/specs/bad" "$bad_snap" "refused bundle written in a mixed sweep"
headers_ok "$mix/specs/good" Draft "mixed-sweep good bundle"
case "$mix_out" in
  *"1 migrated, 0 repaired, 0 unchanged, 1 refused"*) ;;
  *) fail "mixed-sweep tally wrong: $mix_out" ;;
esac
echo "ok: a refusal never aborts the sweep — the valid sibling migrates and the tally counts both (D-10)"

# An escape byte inside a header VALUE (not just a directory name) must be
# stripped before the value is compared or echoed: the unknown-status
# refusal fires with sanitized output (REQ-C1.9).
esv=$tmp/escape-value
mkdir -p "$esv/specs"
seeded_bundle "$esv/specs/poisoned" Ready
esc=$(printf '\033')
awk -v esc="$esc" '
  /^\*\*Status:\*\* Ready$/ && !done { print "**Status:** Rea" esc "[31mdy"; done = 1; next }
  { print }
' "$esv/specs/poisoned/requirements.md" >"$tmp/ev" \
  && mv "$tmp/ev" "$esv/specs/poisoned/requirements.md"
esv_snap=$tmp/esv.snap
snapshot "$esv/specs/poisoned" "$esv_snap"
if (cd "$esv" && "$MIGRATE" specs/poisoned >/dev/null 2>"$tmp/esv.err"); then
  fail "REQ-C1.9: an escape-byte header value was not refused"
fi
assert_same_tree "$esv/specs/poisoned" "$esv_snap" "escape-value bundle written"
if od -c "$tmp/esv.err" | grep -q '033'; then
  fail "REQ-C1.9: refusal echoed a raw escape byte from a header value"
fi
echo "ok: an escape byte in a header value is refused with sanitized output (REQ-C1.9)"

# --- Mechanical-or-refuse: every non-mechanical input is a clean refusal
# with no write (D-10, REQ-D1.2). Each case poisons a fresh Draft bundle
# (Draft needs no brief, and restructure/mirror checks run for Drafts too).
refusal_case() { # <slug> <label>
  rc_dir="$tmp/refuse-$1/specs/poisoned"
  rc_snap="$tmp/refuse-$1.snap"
  snapshot "$rc_dir" "$rc_snap"
  if (cd "$tmp/refuse-$1" && "$MIGRATE" specs/poisoned >/dev/null 2>"$tmp/refuse-$1.err"); then
    fail "$2: not refused"
  fi
  assert_same_tree "$rc_dir" "$rc_snap" "$2: bundle written despite refusal"
  echo "ok: $2 is refused with no write (D-10)"
}

mkrefusal() { # <slug> — fresh Draft seeded bundle at $tmp/refuse-<slug>/specs/poisoned
  mkdir -p "$tmp/refuse-$1/specs"
  seeded_bundle "$tmp/refuse-$1/specs/poisoned" Draft
}

mkrefusal dup-id
cat >>"$tmp/refuse-dup-id/specs/poisoned/tasks.md" <<EOF

### Task 2 — Beta again

- **Deliverables:** Dup.
- **Done when:** Never.
- **Dependencies:** none
- **Citations:** REQ-A1.1
- **Estimated effort:** half day
EOF
refusal_case dup-id "a duplicate task id"

mkrefusal unknown-h2
printf '%s\n' '' '## Backlog' '' '(nothing)' >>"$tmp/refuse-unknown-h2/specs/poisoned/tasks.md"
refusal_case unknown-h2 "an unrecognized H2 section"

mkrefusal non-task-h3
printf '%s\n' '' '### Notes' '' 'Some notes.' >>"$tmp/refuse-non-task-h3/specs/poisoned/tasks.md"
refusal_case non-task-h3 "a non-task H3 heading"

mkrefusal bad-id
printf '%s\n' '' '### Task x9 — Bad id' '' '- **Deliverables:** d' >>"$tmp/refuse-bad-id/specs/poisoned/tasks.md"
refusal_case bad-id "a malformed task id"

# NUL-bearing definition content: restructure_tasks has no NUL screen, so
# this must be caught by the lib's screen inside the extraction self-check —
# pinning the `if ! spec_parse_extract_tasks` refuse branch (REQ-B1.6f: an
# unchecked lib exit would consume a NUL-truncated stream as complete).
mkrefusal nul-bullet
nb_f="$tmp/refuse-nul-bullet/specs/poisoned/tasks.md"
nb_line=$(grep -n -- '- \*\*Deliverables:\*\* Beta output' "$nb_f" | head -1 | cut -d: -f1)
[ -n "$nb_line" ] || fail "nul-bullet fixture: seeded Deliverables line not found"
{
  head -n $((nb_line - 1)) "$nb_f"
  printf -- '- **Deliverables:** Beta \000 output, NUL-bearing.\n'
  tail -n +$((nb_line + 1)) "$nb_f"
} >"$tmp/nb" && mv "$tmp/nb" "$nb_f"
refusal_case nul-bullet "a NUL byte in tasks.md (lib screen via the self-check)"
grep -q "canonical extraction failed" "$tmp/refuse-nul-bullet.err" \
  || fail "NUL refusal did not come from the extraction self-check branch: $(cat "$tmp/refuse-nul-bullet.err")"

mkrefusal placement-prose
awk '/^## Forward plan$/ { print; print ""; print "Remember the spike work first."; next } { print }' \
  "$tmp/refuse-placement-prose/specs/poisoned/tasks.md" >"$tmp/pp" \
  && mv "$tmp/pp" "$tmp/refuse-placement-prose/specs/poisoned/tasks.md"
refusal_case placement-prose "prose in a placement section (silent-drop guard)"

mkrefusal ai-plain
awk '/^## Awaiting input$/ { print; print ""; print "- Waiting on legal sign-off (no task yet)."; next } { print }' \
  "$tmp/refuse-ai-plain/specs/poisoned/tasks.md" >"$tmp/ap" \
  && mv "$tmp/ap" "$tmp/refuse-ai-plain/specs/poisoned/tasks.md"
refusal_case ai-plain "a plain non-reference bullet in Awaiting input"

mkrefusal block-tail
cat >>"$tmp/refuse-block-tail/specs/poisoned/tasks.md" <<EOF
- A separate exclusion note trailing the parked block.
EOF
refusal_case block-tail "non-definition content inside a task block (relocation guard)"

mkrefusal mirror-mismatch
awk '/^\*\*Status:\*\* Draft$/ && !done { print "**Status:** Active"; done = 1; next } { print }' \
  "$tmp/refuse-mirror-mismatch/specs/poisoned/design.md" >"$tmp/mm" \
  && mv "$tmp/mm" "$tmp/refuse-mirror-mismatch/specs/poisoned/design.md"
refusal_case mirror-mismatch "a Status mirror mismatch"

mkrefusal missing-fv-mirror
grep -v '^\*\*Format-version:\*\*' "$tmp/refuse-missing-fv-mirror/specs/poisoned/design.md" >"$tmp/fm" \
  && mv "$tmp/fm" "$tmp/refuse-missing-fv-mirror/specs/poisoned/design.md"
refusal_case missing-fv-mirror "a missing Format-version mirror in a companion file"

mkrefusal symlinked-file
mv "$tmp/refuse-symlinked-file/specs/poisoned/tasks.md" "$tmp/refuse-symlinked-file/specs/poisoned/tasks.real.md"
ln -s tasks.real.md "$tmp/refuse-symlinked-file/specs/poisoned/tasks.md"
refusal_case symlinked-file "a symlinked spec file"

mkrefusal no-changelog
seeded_bundle "$tmp/refuse-no-changelog/specs/poisoned" Ready
signed_brief "$tmp/refuse-no-changelog/specs/poisoned" specs/poisoned
awk '/^## Changelog$/ { skip = 1; next } /^## Sources$/ { skip = 0 } !skip { print }' \
  "$tmp/refuse-no-changelog/specs/poisoned/requirements.md" >"$tmp/nc" \
  && mv "$tmp/nc" "$tmp/refuse-no-changelog/specs/poisoned/requirements.md"
refusal_case no-changelog "a signed bundle without a ## Changelog section"

mkdir -p "$tmp/refuse-no-brief/specs"
seeded_bundle "$tmp/refuse-no-brief/specs/poisoned" Ready
refusal_case no-brief "a signed bundle without a kickoff brief"

mkrefusal lock-busy
mkdir "$tmp/refuse-lock-busy/specs/poisoned/.orchestrate.lock"
refusal_case lock-busy "a live per-spec lock (single-writer serialization)"
rmdir "$tmp/refuse-lock-busy/specs/poisoned/.orchestrate.lock"

# Lock-before-read ordering (the TOCTOU guard): with the lock busy, the
# refusal must be the lock refusal, not a compute-phase diagnostic — the
# decision and the staged content must be computed under the same lock the
# write holds, or a concurrent locked writer landing between read and write
# is silently clobbered.
mkrefusal lock-order
printf '%s\n' '' '## Backlog' '' '(nothing)' >>"$tmp/refuse-lock-order/specs/poisoned/tasks.md"
mkdir "$tmp/refuse-lock-order/specs/poisoned/.orchestrate.lock"
refusal_case lock-order "a busy per-spec lock (checked before any compute-phase read)"
grep -q 'lock busy' "$tmp/refuse-lock-order.err" \
  || fail "lock ordering: busy-lock refusal reported '$(cat "$tmp/refuse-lock-order.err")' — the compute phase ran before the lock was checked (TOCTOU)"
rmdir "$tmp/refuse-lock-order/specs/poisoned/.orchestrate.lock"

# A lock ERROR is not lock contention: orchestrate-lock exits 2 (with a
# diagnostic) for environment/containment faults — e.g. a bundle dir not
# under a specs/ parent — and exits 1 only for a live holder. Masking an
# error as "busy, re-run when quiet" tells the operator to wait out a
# permanent refusal, the exact trap orchestrate-lock's own fail-closed
# comment warns against; the migration must surface the lock's diagnostic.
lockerr=$tmp/lockerr-corpus
mkdir -p "$lockerr/bundles"
seeded_bundle "$lockerr/bundles/poisoned" Draft
if (cd "$lockerr" && "$MIGRATE" bundles/poisoned >/dev/null 2>"$tmp/lockerr.err"); then
  fail "a lock environment error was not refused"
fi
grep -q 're-run when quiet' "$tmp/lockerr.err" \
  && fail "lock error/busy conflation: a permanent lock refusal was reported as transient contention: $(cat "$tmp/lockerr.err")"
grep -q 'specs/ parent' "$tmp/lockerr.err" \
  || fail "lock error refusal does not surface the lock's own diagnostic: $(cat "$tmp/lockerr.err")"
echo "ok: a lock environment error surfaces the lock's diagnostic instead of 're-run when quiet'"

# A task block before the first H2 has no deterministic v2 home: left alone
# it would ride the preserved head verbatim, keeping its state annotation
# bullets (the exact content the migration strips) in the migrated file.
mkrefusal pre-h2-task
awk '/^## Forward plan$/ && !done {
       print "### Task 9 — Stray pre-section block"
       print ""
       print "- **Deliverables:** Stray."
       print "- **Done when:** Never."
       print "- **Dependencies:** none"
       print "- **Citations:** REQ-A1.1"
       print "- **Estimated effort:** half day"
       print "- **Status:** implementing"
       print ""
       done = 1
     }
     { print }' "$tmp/refuse-pre-h2-task/specs/poisoned/tasks.md" >"$tmp/ph" \
  && mv "$tmp/ph" "$tmp/refuse-pre-h2-task/specs/poisoned/tasks.md"
refusal_case pre-h2-task "a task block before the first H2 section (head-relocation guard)"

# --- Single-bundle invocation success mode: migrating one bundle by its
# directory path (no sweep, no containment root) works end-to-end.
solo=$tmp/solo-corpus
mkdir -p "$solo/specs"
seeded_bundle "$solo/specs/solo" Draft
(cd "$solo" && "$MIGRATE" specs/solo >/dev/null 2>&1) \
  || fail "single-bundle invocation of a clean Draft bundle failed"
headers_ok "$solo/specs/solo" Draft "solo"
"$VALIDATE" "$solo/specs/solo" >/dev/null 2>&1 || fail "single-bundle migrated solo bundle does not validate"
echo "ok: single-bundle invocation migrates one bundle end-to-end (REQ-D1.2)"

# --- Header-grammar parity: a `**Status:**Active` line with no space after
# the colon parses identically everywhere else (header_value, the validator)
# and must not evade the Active → Ready restriction; the transform emits the
# canonical spaced form.
ns=$tmp/nospace-corpus
mkdir -p "$ns/specs"
seeded_bundle "$ns/specs/nospace" Active
signed_brief "$ns/specs/nospace" specs/nospace
for nf in requirements.md tasks.md; do
  sed 's/^\*\*Status:\*\* Active$/**Status:**Active/' "$ns/specs/nospace/$nf" >"$tmp/nsf" \
    && mv "$tmp/nsf" "$ns/specs/nospace/$nf"
done
(cd "$ns" && "$MIGRATE" specs/nospace >/dev/null 2>&1) \
  || fail "no-space Status header bundle failed to migrate"
headers_ok "$ns/specs/nospace" Ready "nospace"
"$VALIDATE" "$ns/specs/nospace" >"$tmp/ns.val" 2>&1 \
  || fail "no-space migrated bundle does not validate: $(cat "$tmp/ns.val")"
echo "ok: a no-space Status header cannot evade the Active → Ready restriction (parser parity)"

# --- Interrupted mid-write recovery: design.md already v2 while the other
# three files are back at v1 (an interruption before the requirements.md
# completion key landed). A re-run must finish the migration and must not
# duplicate the changelog entry or the brief's re-anchor entry.
rec=$tmp/recover-corpus
mkdir -p "$rec/specs"
git -C "$rec" init -q -b main
git -C "$rec" config user.email t@example.com
git -C "$rec" config user.name t
git -C "$rec" config commit.gpgsign false
seeded_bundle "$rec/specs/recover" Active
signed_brief "$rec/specs/recover" specs/recover
pre_snap=$tmp/recover-pre.snap
snapshot "$rec/specs/recover" "$pre_snap"
git -C "$rec" add -A && git -C "$rec" commit -qm fixture
(cd "$rec" && "$MIGRATE" specs/recover >/dev/null 2>&1) || fail "recovery fixture: first migration failed"
for f in requirements.md tasks.md test-spec.md; do
  cp "$pre_snap/$f" "$rec/specs/recover/$f"
done
(cd "$rec" && "$MIGRATE" specs/recover >/dev/null 2>&1) || fail "recovery fixture: re-run over a torn bundle failed"
headers_ok "$rec/specs/recover" Ready "recover"
"$VALIDATE" "$rec/specs/recover" >"$tmp/rec.val" 2>&1 || fail "recovered bundle does not validate: $(cat "$tmp/rec.val")"
n_marker=$(grep -c 'Migrated to format-version 2' "$rec/specs/recover/requirements.md" || true)
[ "$n_marker" = 1 ] || fail "recovery duplicated the changelog entry ($n_marker)"
n_entry=$(grep -c 'format-version 2 migration)' "$rec/specs/recover/kickoff-brief.md" || true)
[ "$n_entry" = 1 ] || fail "recovery duplicated the re-anchor entry ($n_entry)"
echo "ok: a re-run over a torn (part-v2) bundle completes it without duplicating artifacts (D-10, REQ-D1.2)"

# --- Hostile input is refused with a clean, sanitized error (REQ-C1.9). ---

repo4=$tmp/corpus4
mkdir -p "$repo4/specs"
seeded_bundle "$repo4/specs/UPPER_case" Ready
if (cd "$repo4" && "$MIGRATE" specs >/dev/null 2>"$tmp/host.err"); then
  fail "REQ-C1.9: a hostile spec identifier was not refused"
fi
grep -q 'identifier' "$tmp/host.err" || fail "hostile-identifier refusal not reported"
echo "ok: a hostile spec identifier is refused cleanly (REQ-C1.9)"

escname=$(printf 'bad\033name')
repo4b=$tmp/corpus4b
mkdir -p "$repo4b/specs/$escname"
seeded_bundle "$repo4b/specs/$escname" Ready
if (cd "$repo4b" && "$MIGRATE" specs >/dev/null 2>"$tmp/esc.err"); then
  fail "REQ-C1.9: an escape-byte spec identifier was not refused"
fi
if od -c "$tmp/esc.err" | grep -q '033'; then
  fail "REQ-C1.9: refusal echoed a raw escape byte"
fi
echo "ok: an escape-byte identifier is refused with sanitized output (REQ-C1.9)"

# Out-of-containment: a symlinked bundle directory pointing outside the
# specs root is refused, and the outside target is never written.
repo5=$tmp/corpus5
mkdir -p "$repo5/specs"
outside=$tmp/outside-bundle
seeded_bundle "$outside" Ready
ln -s "$outside" "$repo5/specs/linked"
out_snap=$tmp/outside.snap
snapshot "$outside" "$out_snap"
if (cd "$repo5" && "$MIGRATE" specs >/dev/null 2>"$tmp/link.err"); then
  fail "REQ-C1.9: an out-of-containment symlinked bundle was not refused"
fi
assert_same_tree "$outside" "$out_snap" "out-of-containment target written"
echo "ok: an out-of-containment path is refused with no write (REQ-C1.9)"

# --- Lineage closure (REQ-E1.4): the orchestration-concurrency Deferred ---
# "Maximal variant" entry carries the closure annotation citing this bundle.

occ="$here/../specs/orchestration-concurrency/tasks.md"
[ -f "$occ" ] || fail "specs/orchestration-concurrency/tasks.md missing"
# Capture exactly the Maximal entry: its bullet line plus continuations,
# stopping at the next top-level bullet or heading — a loose range could be
# satisfied by a neighboring entry's text.
awk '/^- \*\*The Maximal variant/ { on = 1; print; next }
     on && (/^- / || /^## /) { exit }
     on { print }' "$occ" >"$tmp/maximal"
grep -q 'Maximal variant' "$tmp/maximal" || fail "Maximal variant Deferred entry not found"
grep -q 'Closed 20[0-9][0-9]-' "$tmp/maximal" \
  || fail "REQ-E1.4: Maximal variant entry carries no dated closure annotation"
grep -q 'specs/invariant-tasks' "$tmp/maximal" \
  || fail "REQ-E1.4: closure annotation does not cite specs/invariant-tasks"
echo "ok: the Maximal-variant Deferred entry is annotated closed citing invariant-tasks (REQ-E1.4)"

# --- Own-repo migration state (REQ-D1.3): every live bundle reads v2. -----

for rq in "$here"/../specs/*/requirements.md; do
  sdir=$(dirname "$rq")
  base=$(basename "$sdir")
  case $base in _*) continue ;; esac
  st=$(awk '/^\*\*Status:\*\* / { print $2; exit }' "$rq")
  fv=$(awk '/^\*\*Format-version:\*\*/ { print $2; exit }' "$rq")
  case $st in
    Draft | Ready | Active)
      [ "$fv" = 2 ] || fail "REQ-D1.3: live bundle $base is not format-version 2 (Status $st, Format-version $fv)"
      ;;
  esac
done
echo "ok: every live bundle in this repo declares format-version 2 (REQ-D1.3)"

echo "PASS: all migrate-format-version tests passed"
