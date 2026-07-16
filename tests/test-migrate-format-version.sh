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

# The canonical tasks.md definition-content extraction (doctrine/
# spec-format.md), byte-identical to scripts/spec-anchor.sh's: the invariant
# under test is that this stream — heading plus the five definition field
# bullets with continuations, records sorted by task id — survives migration
# byte-for-byte (REQ-A1.4, REQ-D1.2).
extract_tasks() {
  awk '
    function sortkey(id,    parts, n, major, minor) {
      n = split(id, parts, "\\.")
      major = parts[1] + 0
      minor = (n > 1) ? parts[2] + 0 : 0
      return sprintf("%08d.%08d", major, minor)
    }
    /^## /  { in_task = 0; keep = 0; next }
    /^### Task [0-9]/ {
      in_task = 1
      keep = 0
      key = sortkey($3)
      nkeys++
      keys[nkeys] = key
      buf[key] = $0 "\n"
      cur = key
      next
    }
    /^### / { in_task = 0; keep = 0; next }
    !in_task { next }
    /^- \*\*(Deliverables|Done when|Dependencies|Citations|Estimated effort):\*\*/ {
      keep = 1
      buf[cur] = buf[cur] $0 "\n"
      next
    }
    /^- /      { keep = 0; next }
    /^[ \t]+[^ \t]/ {
      if (keep) buf[cur] = buf[cur] $0 "\n"
      next
    }
    { keep = 0 }
    END {
      for (i = 2; i <= nkeys; i++) {
        v = keys[i]
        j = i - 1
        while (j >= 1 && keys[j] > v) { keys[j + 1] = keys[j]; j-- }
        keys[j + 1] = v
      }
      for (i = 1; i <= nkeys; i++) printf "%s", buf[keys[i]]
    }
  ' "$1"
}

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

### Task 4 — Delta

- **Deliverables:** Delta output.
- **Done when:** Delta done.
- **Dependencies:** 1
- **Citations:** REQ-A1.2
- **Estimated effort:** half day
- **Status:** awaiting input — which flavor should Delta use?

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
extract_tasks "$repo/specs/seeded/tasks.md" >"$before_extract"
[ -s "$before_extract" ] || fail "precondition: seeded fixture extraction is empty"
draft_extract_before=$tmp/draft.extract.before
extract_tasks "$repo/specs/draft-spec/tasks.md" >"$draft_extract_before"

done_snap=$tmp/done.snap
snapshot "$repo/specs/done-spec" "$done_snap"
retired_snap=$tmp/retired.snap
snapshot "$repo/specs/retired-spec" "$retired_snap"
born_snap=$tmp/born.snap
snapshot "$bornv2" "$born_snap"

# --- Run 1: sweep the corpus ----------------------------------------------

out=$(cd "$repo" && "$MIGRATE" specs 2>"$tmp/run1.err") \
  || fail "sweep over a clean live corpus exited non-zero: $(cat "$tmp/run1.err")"

# The extraction digest is unchanged: definition lines survive byte-for-byte
# (REQ-A1.4, REQ-D1.2).
after_extract=$tmp/seeded.extract.after
extract_tasks "$repo/specs/seeded/tasks.md" >"$after_extract"
cmp -s "$before_extract" "$after_extract" \
  || fail "REQ-A1.4: seeded extraction changed across migration ($(diff "$before_extract" "$after_extract" | head -5))"
d_before=$(git hash-object --stdin <"$before_extract")
d_after=$(git hash-object --stdin <"$after_extract")
[ "$d_before" = "$d_after" ] || fail "REQ-A1.4: extraction digest moved"
echo "ok: the canonical extraction digest is unchanged across migration (REQ-A1.4, REQ-D1.2)"

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
echo "ok: a signed bundle gains the dated Changelog entry and a valid expression-only re-anchor (REQ-D1.2)"

# Draft bundle: same byte-stable transform, no changelog entry, no brief.
draft_extract_after=$tmp/draft.extract.after
extract_tasks "$repo/specs/draft-spec/tasks.md" >"$draft_extract_after"
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
assert_same_tree "$bornv2" "$born_snap" "born-v2 bundle rewritten"
case "$out" in
  *_observations*) fail "underscore accumulator treated as a bundle" ;;
esac
echo "ok: Done/terminal bundles stay byte-identical; born-v2 is a clean no-op (REQ-D1.3, D-10)"

# --- Run 2: idempotence — a second sweep is a byte-level no-op. -----------

specs_snap=$tmp/specs.snap
snapshot "$repo/specs" "$specs_snap"
out2=$(cd "$repo" && "$MIGRATE" specs 2>/dev/null) || fail "second sweep exited non-zero"
assert_same_tree "$repo/specs" "$specs_snap" "idempotence"
case "$out2" in
  *"0 migrated"*) ;;
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

(cd "$repo2" && "$MIGRATE" specs >/dev/null 2>"$tmp/run3.err") \
  || fail "partial-run completion exited non-zero: $(cat "$tmp/run3.err")"
grep -q 'self-re-anchor' "$repo2/specs/partial/kickoff-brief.md" \
  || fail "REQ-D1.2: a re-run did not complete the missing re-anchor entry"
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
if (cd "$repo3" && "$MIGRATE" specs/missing-fv >/dev/null 2>&1); then
  fail "REQ-C1.8: a missing Format-version was not refused"
fi
echo "ok: a missing Format-version is refused fail-closed (REQ-C1.8)"

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
awk '/^- \*\*The Maximal variant/,/^- \*\*[^T]|^## /' "$occ" >"$tmp/maximal" || true
grep -q 'Maximal variant' "$tmp/maximal" || fail "Maximal variant Deferred entry not found"
grep -qi 'closed' "$tmp/maximal" || fail "REQ-E1.4: Maximal variant entry carries no closure annotation"
grep -q 'invariant-tasks' "$tmp/maximal" \
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
