#!/bin/sh
# Unit tests for scripts/spec-validate.sh — the status-aware spec validator
# defined by doctrine/spec-format.md's validator-enforceable invariants
# (REQ-A2.1, REQ-A2.2, REQ-A1.8, REQ-A3.2, D-25, D-34).
#
# Properties verified, one numbered section per validator check:
#   1.  A valid bundle passes (Draft and Active), with a 0/0 summary line.
#   2.  The same structural gap warns (exit 0) on Draft and errors (exit 1)
#       on Active; terminal statuses (Retired/Superseded) warn.
#   3.  Four-file presence: a missing file is a status-scoped finding.
#   4.  Header block: missing Status warns and defaults to Draft; an unknown
#       status is an error; Superseded requires `Superseded-by:`; status
#       mirrors across the four files are checked. One of the six statuses
#       (Draft, Ready, Active, Done, Retired, Superseded) is recognized.
#   5.  Format-version keying: missing version is a gap; an undeclared
#       (unsupported) version is a clear error, never silently re-keyed.
#   6.  REQ convention: prose-only bullets flagged; citation per live REQ
#       (superseded records exempt); duplicate REQ-IDs rejected.
#   7.  D-ID structure: Decision / Alternatives considered / Chosen because
#       all required; duplicate D-IDs rejected; malformed D- headings flagged.
#   8.  Task structure: five definition fields per block; malformed task ids
#       flagged; duplicate task ids rejected.
#   9.  REQ↔test-spec coverage with exact-id matching (REQ-X1.1 is not
#       covered by an entry that only names REQ-X1.10).
#   10. Stable-ID discipline: a supersede (new ID + `Superseded-by` on the
#       old) passes; a renumbered/vanished ID against the baseline is
#       flagged.
#   11. Terminal-state discipline: a transition out of Retired/Superseded
#       (vs the baseline) is an error; the Done→Draft reopen cycle is not.
#   12. Spec-identifier charset (REQ-A1.8): hostile directory names error;
#       underscore accumulators are skipped as bundles but name-screened;
#       symlinked directories in the root are a hard error, not a skip;
#       --check-id validates proposed identifier strings full-string.
#   13. Changelog-on-supersede (REQ-A3.3): a supersede newly introduced since
#       the baseline must be named in a dated Changelog entry (status-scoped:
#       error on Active, warning on Draft); a supersede already in the
#       baseline, or one named in the changelog, is not flagged.
#   14. Ready status (REQ-B1.2): a Ready bundle is recognized (not flagged
#       unknown-status); its findings are errors that block execution, like
#       Active and Done; the Draft path stays warnings.
#   15. Ready transitions (REQ-B1.3): Draft→Ready, Ready→Active, Ready→Done,
#       Active→Done, and Done→Draft are accepted; a transition out of a
#       terminal status (Retired/Superseded) is still rejected.
#   16. Format-version 2 (REQ-C1.5, REQ-D1.1): a compliant v2 bundle passes
#       (Draft and Ready), including one with a valid reference bullet.
#   17. v2 banned placement headings: Forward plan / In progress / Completed
#       each error on Ready and warn on Draft, per-token fixtures.
#   18. v2 banned state annotations: Status / Last activity / Dispatch
#       bullets in a task block each error on Ready and warn on Draft.
#   19. v2 restricted stored status: Active and Done headers fail (derived,
#       never stored); an unknown status stays a hard error.
#   20. v2 pointer line (D-5): a missing or non-canonical
#       `**Execution:**` line fails; fixed vocabulary, per file.
#   21. v2 reference-bullet integrity (D-3, REQ-C1.9): unknown task id,
#       duplicate bullet (same or cross-section), and a grammar-violating
#       id each fail; Draft warns.
#   22. Fail-closed version keying (REQ-C1.8): a missing or unparseable
#       Format-version errors at every status; an unsupported numeric
#       version stays a hard error.
#   23. v2 echo discipline (REQ-C1.9): escape bytes in reference-bullet ids
#       and header values never reach the output raw.
#   24. Fenced illustration (REQ-C1.2, D-5): fenced mock REQ bullets, D-ID
#       headings, and task blocks are documentation, not content — and the
#       rule does not fail open either (a fenced test-spec entry does not
#       satisfy coverage, a fenced pointer line does not satisfy the v2
#       header check).
#   25. Unbalanced column-0 fence (REQ-D1.11): flagged status-scoped; an
#       unclosed INDENTED fence is ordinary content and is not flagged.
#   26. Changelog-named task-retirement escape (REQ-D1.6, D-12): a dated
#       entry naming the retired id authorizes the removal; an unnamed one,
#       a different id, a grammar-failing token, an undated entry, a bare
#       number, and a fenced entry all leave the removal an error.
#   27. Baseline-side fence-awareness (REQ-C1.2): both halves of the
#       stable-ID diff parse the same grammar, so a fenced mock id present
#       in both revisions is not read as an id that vanished.
#   28. An unbalanced baseline fence never hides a removal: the baseline is
#       compared raw, with a finding naming the malformed revision.
#   29. Duplicate in-header declarations (format-grammar REQ-D1.9) error at
#       Draft and Ready alike, in the authoritative file and in a mirror.
#   30. Cited-but-empty requirement bullets (REQ-D1.2): status-scoped; a
#       wrapped annotation is still only an annotation; prose on a
#       continuation line counts; a superseded record is exempt.
#   31. Malformed decision shapes (REQ-D1.5): an H2 `D-<n>` heading and a
#       period-labelled field are named as such, once.
#   32. Canonical task-heading enforcement (REQ-D1.7): every separator or
#       title deviation is flagged; the dotted canonical form passes.
#   33. v2 Awaiting-input purity (REQ-D1.1): any non-reference column-0
#       bullet there is flagged; the other payload sections and v1 are not.
#   34. Citation range (REQ-D1.3, D-13): an undefined `D-<n>`, `REQ-<id>`,
#       or `Task <id>` token warns at every status unless a sibling-spec
#       qualifier is in reach (line, bullet or paragraph, H3 block);
#       `## Changelog` and fenced illustration are not scanned.
#   35. Coverage-based dead-path check (REQ-D1.8, D-14): a changed REQ with
#       an unchanged test-spec entry warns; citation-only, position, and
#       whitespace changes do not; a superseded REQ is exempt.
#   36. Review-pass regressions over sections 30-35 (block identity of the
#       H3 scope, source line numbers, every occurrence named, CRLF,
#       bounded citation strip, group prose, baseline fence handling).
#
# Runs standalone: ./tests/test-spec-validate.sh
set -eu

# Pin the C locale: charset checks and awk ranges must not vary by host
# locale collation.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes the destination into the command substitution
# below, corrupting the derived script path (house pattern, see sibling tests).
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
validator="$here/../scripts/spec-validate.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$validator" ] || fail "scripts/spec-validate.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# run_v <expected-exit> <args...> — runs the validator, captures combined
# output in $out, fails the suite if the exit code differs.
out=
run_v() {
  expect=$1
  shift
  rc=0
  out=$("$validator" "$@" 2>&1) || rc=$?
  [ "$rc" -eq "$expect" ] \
    || fail "expected exit $expect, got $rc for: $* — output: $out"
}

has() {
  case $out in
    *"$1"*) ;;
    *) fail "output lacks \"$1\": $out" ;;
  esac
}

lacks() {
  case $out in
    *"$1"*) fail "output unexpectedly contains \"$1\": $out" ;;
  esac
}

# write_bundle <dir> <status> — a minimal conforming bundle. Two REQs (one
# verified [test], one [manual]), one decision, one task, full coverage.
write_bundle() {
  d=$1
  s=$2
  mkdir -p "$d"
  cat >"$d/requirements.md" <<EOF
# Fixture — Requirements

**Status:** $s
**Last reviewed:** 2026-06-12
**Format-version:** 1

## Goal

A fixture bundle.

## REQ-X — fixture group

- **REQ-X1.1** The widget SHALL exist.
  *(Cites: D-1.)*
- **REQ-X1.2** The gadget SHALL exist.
  *(Cites: D-1.)*

## Changelog

- 2026-06-12 — created.

## Sources

- the fixture seed.
EOF
  cat >"$d/design.md" <<EOF
# Fixture — Design

**Status:** $s
**Last reviewed:** 2026-06-12
**Format-version:** 1

## Decision log

### D-1: Widgets are good  (N)

**Decision:** Build widgets.

**Alternatives considered:**
- No widgets. Rejected because: nothing would exist.

**Chosen because:** widgets are the fixture's point.
EOF
  cat >"$d/tasks.md" <<EOF
# Fixture — Tasks

**Status:** $s
**Last reviewed:** 2026-06-12
**Format-version:** 1

## Forward plan

### Task 1 — Build the widget

- **Deliverables:** A widget.
- **Done when:** The widget exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-X1.1
- **Estimated effort:** half day

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
  cat >"$d/test-spec.md" <<EOF
# Fixture — Test Spec

**Status:** $s
**Last reviewed:** 2026-06-12
**Format-version:** 1

Coverage is a fixture mix.

### REQ-X1.1 — widget exists [test]

The widget fixture passes.

### REQ-X1.2 — gadget exists [manual]

The gadget is exercised by hand.
EOF
}

# write_bundle_v2 <dir> <status> — a minimal conforming format-version 2
# bundle (invariant ledger): single `## Tasks` section plus the three
# human-payload sections, the `**Execution:**` pointer line in every file,
# no placement sections, no state annotations. Two tasks so reference
# bullets can name a real id.
write_bundle_v2() {
  d=$1
  s=$2
  mkdir -p "$d"
  cat >"$d/requirements.md" <<EOF
# Fixture — Requirements

**Status:** $s
**Last reviewed:** 2026-07-15
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

A fixture bundle.

## REQ-X — fixture group

- **REQ-X1.1** The widget SHALL exist.
  *(Cites: D-1.)*
- **REQ-X1.2** The gadget SHALL exist.
  *(Cites: D-1.)*

## Changelog

- 2026-07-15 — created.

## Sources

- the fixture seed.
EOF
  cat >"$d/design.md" <<EOF
# Fixture — Design

**Status:** $s
**Last reviewed:** 2026-07-15
**Format-version:** 2
**Execution:** derived — see the status render

## Decision log

### D-1: Widgets are good  (N)

**Decision:** Build widgets.

**Alternatives considered:**
- No widgets. Rejected because: nothing would exist.

**Chosen because:** widgets are the fixture's point.
EOF
  cat >"$d/tasks.md" <<EOF
# Fixture — Tasks

**Status:** $s
**Last reviewed:** 2026-07-15
**Format-version:** 2
**Execution:** derived — see the status render

## Tasks

### Task 1 — Build the widget

- **Deliverables:** A widget.
- **Done when:** The widget exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-X1.1
- **Estimated effort:** half day

### Task 2 — Build the gadget

- **Deliverables:** A gadget.
- **Done when:** The gadget exists.
- **Dependencies:** 1
- **Citations:** D-1 · REQ-X1.2
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
  cat >"$d/test-spec.md" <<EOF
# Fixture — Test Spec

**Status:** $s
**Last reviewed:** 2026-07-15
**Format-version:** 2
**Execution:** derived — see the status render

Coverage is a fixture mix.

### REQ-X1.1 — widget exists [test]

The widget fixture passes.

### REQ-X1.2 — gadget exists [manual]

The gadget is exercised by hand.
EOF
}

# park <dir> <section> <bullet> — replace <section>'s `(none yet)`
# placeholder in a v2 fixture's tasks.md with a bullet line, or append the
# bullet under the section when the placeholder was already consumed.
park() {
  pd=$1
  psec=$2
  pb=$3
  awk -v sec="## $psec" -v bullet="$pb" '
    $0 == sec { insec = 1; print; next }
    /^## /    { insec = 0 }
    insec && $0 == "(none yet)" && !done { print bullet; done = 1; next }
    insec && /^- / && !appended { print bullet; appended = 1; done = 1 }
    { print }
  ' "$pd/tasks.md" >"$pd/tasks.md.new"
  mv "$pd/tasks.md.new" "$pd/tasks.md"
}

# in-place sed without BSD/GNU -i divergence
edit() {
  f=$1
  shift
  sed "$@" "$f" >"$f.new"
  mv "$f.new" "$f"
}

# --- 1. A valid bundle passes, both as a bundle dir and from the root ---
root="$tmp/specs"
write_bundle "$root/fixture" Draft
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"
run_v 0 "$root"
has "0 error(s), 0 warning(s)"

write_bundle "$root/fixture" Active
run_v 0 "$root"
has "0 error(s), 0 warning(s)"

# --- 2. Same gap: warning on Draft (exit 0), error on Active (exit 1) ---
write_bundle "$root/fixture" Draft
edit "$root/fixture/tasks.md" '/^- \*\*Done when:\*\*/d'
run_v 0 "$root"
has "WARN"
has "Done when"
lacks "ERROR"

write_bundle "$root/fixture" Active
edit "$root/fixture/tasks.md" '/^- \*\*Done when:\*\*/d'
run_v 1 "$root"
has "ERROR"
has "Done when"

# Done is signed-off live content: errors like Active.
write_bundle "$root/fixture" Done
edit "$root/fixture/tasks.md" '/^- \*\*Done when:\*\*/d'
run_v 1 "$root"
has "ERROR"

# Terminal statuses are frozen records: gaps warn, not block.
write_bundle "$root/fixture" Retired
edit "$root/fixture/tasks.md" '/^- \*\*Done when:\*\*/d'
run_v 0 "$root"
has "WARN"

# --- 3. Four-file presence ---
write_bundle "$root/fixture" Draft
rm "$root/fixture/design.md"
run_v 0 "$root"
has "WARN"
has "design.md"

write_bundle "$root/fixture" Active
rm "$root/fixture/design.md"
run_v 1 "$root"
has "ERROR"
has "design.md"

# Deleting requirements.md must not downgrade an Active bundle's errors to
# warnings: the severity status is derived from the sibling mirrors when
# the authoritative file is absent.
write_bundle "$root/fixture" Active
rm "$root/fixture/requirements.md"
run_v 1 "$root"
has "ERROR"
has "missing file: requirements.md"

# --- 4. Header block: Status ---
# Missing Status warns and defaults to Draft: a structural gap in the same
# bundle stays a warning.
write_bundle "$root/fixture" Active
edit "$root/fixture/requirements.md" '/^\*\*Status:\*\*/d'
edit "$root/fixture/tasks.md" '/^- \*\*Done when:\*\*/d'
run_v 0 "$root/fixture"
has "Status"
has "WARN"
lacks "ERROR"

# A missing Status still mirrors: the defaulted Draft is compared against
# the other files' declared statuses, so an explicit Active mirror cannot
# hide behind an absent authoritative header.
write_bundle "$root/fixture" Active
edit "$root/fixture/requirements.md" '/^\*\*Status:\*\*/d'
run_v 0 "$root/fixture"
has "WARN"
has "mirror"
lacks "ERROR"

# Unknown status is an error.
write_bundle "$root/fixture" Banana
run_v 1 "$root/fixture"
has "ERROR"
has "unknown status"

# Superseded requires the Superseded-by pointer.
write_bundle "$root/fixture" Superseded
run_v 1 "$root/fixture"
has "ERROR"
has "Superseded-by"

write_bundle "$root/fixture" Superseded
edit "$root/fixture/requirements.md" \
  's|^\*\*Status:\*\* Superseded$|**Status:** Superseded\
**Superseded-by:** specs/other/|'
run_v 0 "$root/fixture"
has "0 error(s)"

# Status mirror drift across the four files is a finding.
write_bundle "$root/fixture" Active
edit "$root/fixture/tasks.md" 's/^\*\*Status:\*\* Active$/**Status:** Draft/'
run_v 1 "$root/fixture"
has "ERROR"
has "mirror"

# --- 5. Format-version keying ---
# A missing Format-version is fail-closed (REQ-C1.8): the rules to apply
# cannot be selected without a declared version, so it errors even on Draft.
write_bundle "$root/fixture" Draft
edit "$root/fixture/requirements.md" '/^\*\*Format-version:\*\*/d'
run_v 1 "$root/fixture"
has "ERROR"
has "missing or empty Format-version"

# Format-version mirrors are checked like Status mirrors: a sibling that
# omits or diverges from requirements.md's declared version is flagged.
write_bundle "$root/fixture" Draft
edit "$root/fixture/tasks.md" 's/^\*\*Format-version:\*\* 1$/**Format-version:** 2/'
run_v 0 "$root/fixture"
has "tasks.md: Format-version mirror mismatch"

write_bundle "$root/fixture" Draft
edit "$root/fixture/design.md" '/^\*\*Format-version:\*\*/d'
run_v 0 "$root/fixture"
has "design.md: missing Format-version"

write_bundle "$root/fixture" Draft
edit "$root/fixture/requirements.md" \
  's/^\*\*Format-version:\*\* 1$/**Format-version:** 3/'
run_v 1 "$root/fixture"
has "ERROR"
has "unsupported format-version"

# --- 6. REQ convention ---
# A prose-only top-level bullet inside a REQ group section is flagged.
write_bundle "$root/fixture" Draft
edit "$root/fixture/requirements.md" \
  's/^- \*\*REQ-X1.2\*\*/- A prose-only requirement without an ID.\
- **REQ-X1.2**/'
run_v 0 "$root/fixture"
has "WARN"
has "prose-only"

# A live REQ without a citation is flagged.
write_bundle "$root/fixture" Draft
edit "$root/fixture/requirements.md" '/\*(Cites: D-1.)\*/d'
run_v 0 "$root/fixture"
has "WARN"
has "citation"
has "REQ-X1.1"

# A multi-letter group is not a conforming REQ-ID (meta-spec: <Group> is a
# single capital letter): the bullet is flagged, not silently accepted.
write_bundle "$root/fixture" Draft
edit "$root/fixture/requirements.md" 's/^- \*\*REQ-X1.2\*\*/- **REQ-XY1.2**/'
run_v 0 "$root/fixture"
has "conforming REQ-ID"

# A reused (duplicate) REQ-ID is rejected even on Draft.
write_bundle "$root/fixture" Draft
cat >>"$root/fixture/requirements.md" <<'EOF'

## REQ-Y — duplicate group

- **REQ-X1.1** A reused ID.
  *(Cites: D-1.)*
EOF
run_v 1 "$root/fixture"
has "ERROR"
has "duplicate"
has "REQ-X1.1"

# --- 7. D-ID structure ---
write_bundle "$root/fixture" Draft
edit "$root/fixture/design.md" '/^\*\*Chosen because:\*\*/d'
run_v 0 "$root/fixture"
has "WARN"
has "Chosen because"
has "D-1"

write_bundle "$root/fixture" Draft
cat >>"$root/fixture/design.md" <<'EOF'

### D-1: A reused decision id  (N)

**Decision:** Reuse.

**Alternatives considered:**
- Not reusing. Rejected because: this fixture must trip the check.

**Chosen because:** duplicate ids are the point.
EOF
run_v 1 "$root/fixture"
has "ERROR"
has "duplicate"
has "D-1"

# A non-D-ID H3 section terminates the preceding decision and its own
# field-shaped lines are not attributed to it (mirror of the spec-anchor
# suite's non-task-H3 property).
write_bundle "$root/fixture" Draft
cat >>"$root/fixture/design.md" <<'EOF'

### Implementation notes

**Decision:** prose that must not join D-1's record.
EOF
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# A malformed decision heading (D- prefix without the <n>: shape) is
# flagged, not silently skipped as ordinary prose.
write_bundle "$root/fixture" Draft
cat >>"$root/fixture/design.md" <<'EOF'

### D-2 Missing colon

**Decision:** orphan that must be surfaced.
EOF
run_v 0 "$root/fixture"
has "malformed decision heading"

# Same for a non-numeric D id: the colon alone does not make it well-formed.
write_bundle "$root/fixture" Draft
cat >>"$root/fixture/design.md" <<'EOF'

### D-abc: Non-numeric id

**Decision:** also surfaced.
EOF
run_v 0 "$root/fixture"
has "malformed decision heading"

# --- 8. Task structure ---
# Missing definition fields are flagged per field, each of the five
# independently named.
write_bundle "$root/fixture" Draft
edit "$root/fixture/tasks.md" '/^- \*\*Deliverables:\*\*/d'
edit "$root/fixture/tasks.md" '/^- \*\*Dependencies:\*\*/d'
edit "$root/fixture/tasks.md" '/^- \*\*Citations:\*\*/d'
edit "$root/fixture/tasks.md" '/^- \*\*Estimated effort:\*\*/d'
run_v 0 "$root/fixture"
has "Deliverables"
has "Dependencies"
has "Citations"
has "Estimated effort"

# A malformed task id is flagged.
write_bundle "$root/fixture" Draft
cat >>"$root/fixture/tasks.md" <<'EOF'

### Task 3..5 — Malformed id

- **Deliverables:** Nothing.
- **Done when:** Never.
- **Dependencies:** none
- **Citations:** D-1
- **Estimated effort:** half day
EOF
run_v 0 "$root/fixture"
has "malformed task id"

# A dependency sitting AFTER a parenthetical is named. The shared extraction
# discards the parenthetical and everything after it (so a trailing cross-spec
# clause cannot contribute a phantom edge), which silently costs a real dep
# written past it — the validator says so rather than letting the edge vanish.
write_bundle "$root/fixture" Draft
cat >>"$root/fixture/tasks.md" <<'EOF'

### Task 4 — Dep written after a parenthetical

- **Deliverables:** Nothing.
- **Done when:** Never.
- **Dependencies:** Task 1 (blocked on review), Task 2
- **Citations:** D-1
- **Estimated effort:** half day
EOF
run_v 0 "$root/fixture"
has "after a parenthetical"
has "dependency 2"

# The forms the in-repo bundles actually use put the parenthetical LAST, where
# nothing is lost — those must stay quiet, or the check is unusable noise.
write_bundle "$root/fixture" Draft
cat >>"$root/fixture/tasks.md" <<'EOF'

### Task 4 — Parenthetical last

- **Deliverables:** Nothing.
- **Done when:** Never.
- **Dependencies:** Task 1 (REQ-A1.8 / D-9 — the producer is elsewhere)
- **Citations:** D-1
- **Estimated effort:** half day

### Task 5 — Cross-spec clause last

- **Deliverables:** Nothing.
- **Done when:** Never.
- **Dependencies:** Task 1; plus cross-spec (hard): orchestration-concurrency
- **Citations:** D-1
- **Estimated effort:** half day
EOF
run_v 0 "$root/fixture"
lacks "after a parenthetical"

# An id INSIDE the qualifier is dropped on purpose — naming a cross-spec
# reference there is what the parenthetical is for — so it must stay quiet
# whether or not a comma puts it on its own token boundary. Both spellings
# below flagged before the scan learned to step past the closing paren.
write_bundle "$root/fixture" Draft
cat >>"$root/fixture/tasks.md" <<'EOF'

### Task 4 — Id inside the qualifier, comma-separated

- **Deliverables:** Nothing.
- **Done when:** Never.
- **Dependencies:** Task 1 (waiting on 2, pending)
- **Citations:** D-1
- **Estimated effort:** half day

### Task 5 — Id inside the qualifier, at the close

- **Deliverables:** Nothing.
- **Done when:** Never.
- **Dependencies:** Task 1 (blocked by 2)
- **Citations:** D-1
- **Estimated effort:** half day
EOF
run_v 0 "$root/fixture"
lacks "after a parenthetical"

# An UNCLOSED qualifier has no interior to protect: everything past the open
# paren is discarded prose, so a dep written there is still named.
write_bundle "$root/fixture" Draft
cat >>"$root/fixture/tasks.md" <<'EOF'

### Task 4 — Unclosed qualifier

- **Deliverables:** Nothing.
- **Done when:** Never.
- **Dependencies:** Task 1 (blocked, Task 2
- **Citations:** D-1
- **Estimated effort:** half day
EOF
run_v 0 "$root/fixture"
has "after a parenthetical"
has "dependency 2"

# Known bound, pinned rather than fixed: the scan steps past ONE closing paren,
# so a second or nested qualifier can still put an id in range and draw a
# spurious warning. No in-repo bundle carries either shape. This test exists to
# make the bound visible — if it starts failing, the scan learned to count
# depth and the warning below is no longer expected.
write_bundle "$root/fixture" Draft
cat >>"$root/fixture/tasks.md" <<'EOF'

### Task 4 — Second qualifier holds a spaced id

- **Deliverables:** Nothing.
- **Done when:** Never.
- **Dependencies:** Task 1 (foo) ( 2 )
- **Citations:** D-1
- **Estimated effort:** half day
EOF
run_v 0 "$root/fixture"
has "after a parenthetical"

# Duplicate task ids are rejected even on Draft (the anchor extraction
# fails closed on them too).
write_bundle "$root/fixture" Draft
cat >>"$root/fixture/tasks.md" <<'EOF'

### Task 1 — Reused id

- **Deliverables:** Nothing.
- **Done when:** Never.
- **Dependencies:** none
- **Citations:** D-1
- **Estimated effort:** half day
EOF
run_v 1 "$root/fixture"
has "ERROR"
has "duplicate"
has "Task 1"

# --- 9. REQ↔test-spec coverage, exact-id matching ---
write_bundle "$root/fixture" Draft
edit "$root/fixture/test-spec.md" 's/^### REQ-X1.2 — gadget exists \[manual\]$/### REQ-X1.20 — gadget exists [manual]/'
run_v 0 "$root/fixture"
has "WARN"
has "REQ-X1.2 "
has "test-spec"

# Exactness the other way: REQ-X1.1 covered only by a REQ-X1.10 heading is
# NOT coverage (substring matching is non-conforming).
write_bundle "$root/fixture" Draft
edit "$root/fixture/test-spec.md" 's/^### REQ-X1.1 — widget exists \[test\]$/### REQ-X1.10 — widget exists [test]/'
run_v 0 "$root/fixture"
has "REQ-X1.1 "

# --- 10. Stable-ID discipline: supersede passes, renumber is flagged ---
# A superseded REQ (new ID + Superseded-by on the old) passes on Active:
# the old record needs no citation and no test-spec coverage.
write_bundle "$root/fixture" Active
cat >"$root/fixture/requirements.md" <<'EOF'
# Fixture — Requirements

**Status:** Active
**Last reviewed:** 2026-06-12
**Format-version:** 1

## Goal

A fixture bundle.

## REQ-X — fixture group

- **REQ-X1.1** The widget SHALL exist.
  *(Cites: D-1.)*
- **REQ-X1.2** The gadget SHALL exist. **Superseded-by: REQ-X1.3** (2026-06-12)
- **REQ-X1.3** (supersedes REQ-X1.2) The gadget SHALL exist and hum.
  *(Cites: D-1.)*

## Changelog

- 2026-06-12 — created; X1.2 superseded by X1.3.

## Sources

- the fixture seed.
EOF
edit "$root/fixture/test-spec.md" 's/^### REQ-X1.2 — gadget exists \[manual\]$/### REQ-X1.3 — gadget hums [manual]/'
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# Renumbering against the baseline is flagged: REQ-X1.2 vanishes.
repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q
write_bundle "$repo/specs/myspec" Active
git -C "$repo" add -A
git -C "$repo" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm fixture
edit "$repo/specs/myspec/requirements.md" 's/REQ-X1\.2/REQ-X1.9/g'
edit "$repo/specs/myspec/test-spec.md" 's/REQ-X1\.2/REQ-X1.9/g'
run_v 1 --baseline HEAD "$repo/specs"
has "ERROR"
has "REQ-X1.2"
has "renumbered or removed"

# --- 11. Terminal-state discipline ---
# Retired → Active (vs baseline) is an error.
write_bundle "$repo/specs/myspec" Retired
git -C "$repo" add -A
git -C "$repo" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm retired
edit "$repo/specs/myspec/requirements.md" 's/^\*\*Status:\*\* Retired$/**Status:** Active/'
edit "$repo/specs/myspec/design.md" 's/^\*\*Status:\*\* Retired$/**Status:** Active/'
edit "$repo/specs/myspec/tasks.md" 's/^\*\*Status:\*\* Retired$/**Status:** Active/'
edit "$repo/specs/myspec/test-spec.md" 's/^\*\*Status:\*\* Retired$/**Status:** Active/'
run_v 1 --baseline HEAD "$repo/specs"
has "ERROR"
has "terminal"

# The Done→Draft reopen cycle is accepted.
write_bundle "$repo/specs/myspec" Done
git -C "$repo" add -A
git -C "$repo" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm "done"
edit "$repo/specs/myspec/requirements.md" 's/^\*\*Status:\*\* Done$/**Status:** Draft/'
edit "$repo/specs/myspec/design.md" 's/^\*\*Status:\*\* Done$/**Status:** Draft/'
edit "$repo/specs/myspec/tasks.md" 's/^\*\*Status:\*\* Done$/**Status:** Draft/'
edit "$repo/specs/myspec/test-spec.md" 's/^\*\*Status:\*\* Done$/**Status:** Draft/'
run_v 0 --baseline HEAD "$repo/specs"
has "0 error(s), 0 warning(s)"

# --- 12. Spec-identifier charset (REQ-A1.8) ---
# A directory failing the charset is an error and is not validated as a
# bundle (no four-file findings for it).
root2="$tmp/specs2"
write_bundle "$root2/good-name" Draft
mkdir -p "$root2/Bad_Name"
run_v 1 "$root2"
has "ERROR"
has "identifier"
lacks "Bad_Name: missing"

# A 65-character identifier exceeds the length bound.
longname=$(printf 'a%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 \
  21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 \
  46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65)
rm -rf "$root2/Bad_Name"
mkdir -p "$root2/$longname"
run_v 1 "$root2"
has "ERROR"
rm -rf "${root2:?}/$longname"

# Underscore accumulators are skipped as bundles but name-screened.
mkdir -p "$root2/_observations"
echo "- 2026-06-12 [fixture] an observation." >"$root2/_observations/opportunities.md"
run_v 0 "$root2"
has "0 error(s), 0 warning(s)"

mkdir -p "$root2/_foo;rm"
run_v 1 "$root2"
has "ERROR"
has "accumulator"
rm -rf "$root2/_foo;rm"

# A glob-metacharacter directory name must be screened literally, not
# pathname-expanded into its siblings (an unguarded expansion would make
# "[g]" disappear into the existing "g" and evade REQ-A1.8 screening).
mkdir -p "$root2/g"
write_bundle "$root2/g" Draft
mkdir -p "$root2/[g]"
run_v 1 "$root2"
has "ERROR"
has "identifier"
rm -rf "$root2/[g]" "$root2/g"

# The same literal screening covers accumulator names: "_[g]" must fail the
# accumulator charset, not glob-expand into a sibling "_g".
mkdir -p "$root2/_g" "$root2/_[g]"
run_v 1 "$root2"
has "ERROR _[g]: accumulator"
has "1 error(s)"
rm -rf "$root2/_[g]" "$root2/_g"

# A hostile directory name with control bytes is flagged without the raw
# bytes reaching the output (REQ-H1.3 echo discipline applied to names).
mkdir -p "$root2/$(printf 'bad\033[31mname')"
run_v 1 "$root2"
has "ERROR"
lacks "$(printf '\033')"
rm -rf "${root2:?}/$(printf 'bad\033[31mname')"

# A newline inside a directory name must stay one entry: line-splitting
# enumeration would fragment it into charset-valid phantom names ("one",
# "two") that produce warnings instead of the identifier error.
mkdir -p "$root2/$(printf 'one\ntwo')"
run_v 1 "$root2"
has "identifier"
lacks "phantom"
lacks "WARN one"
rm -rf "${root2:?}/$(printf 'one\ntwo')"

# Hidden directories are tooling artifacts (like the root's dotfiles), not
# candidate bundles: ignored, not flagged.
mkdir -p "$root2/.cache"
run_v 0 "$root2"
has "0 error(s), 0 warning(s)"
rm -rf "${root2:?}/.cache"

# A symlinked directory under the specs root is a hard error (fail closed:
# a silently skipped bundle would be one CI never checks), while plain
# files and symlinks to files stay ignored like any other non-directory.
write_bundle "$root2/real" Draft
ln -s real "$root2/linked"
run_v 1 "$root2"
has "ERROR linked: symlinked"
rm "$root2/linked"
rm -rf "$root2/real"

# --check-id validates a proposed identifier string, full-string, before
# any path is formed.
run_v 0 --check-id good-name
run_v 1 --check-id "good-name/../escape"
run_v 1 --check-id "foo;rm"
run_v 1 --check-id "Foo"
run_v 1 --check-id ""
run_v 1 --check-id "-leading-hyphen"
run_v 0 --check-id "$(printf 'a%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 \
  17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 \
  42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64)"

# The default-baseline quiet skip stays quiet even when the ref exists but
# fails the commit peel (a blob-pointing origin/main): git's --quiet covers
# missing refs but not peel failures, which leak "error: ... expected
# commit type" unless stderr is silenced at the probe.
repo2="$tmp/repo2"
mkdir -p "$repo2"
git -C "$repo2" init -q
write_bundle "$repo2/specs/ok" Draft
git -C "$repo2" add -A
git -C "$repo2" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm fixture
git -C "$repo2" update-ref refs/remotes/origin/main \
  "$(git -C "$repo2" rev-parse HEAD:specs/ok/requirements.md)"
run_v 0 "$repo2/specs"
has "0 error(s), 0 warning(s)"
lacks "expected commit type"

# --- explicit-baseline fatal paths (REQ-K1.7: explicit prerequisites fail
# closed with exit 2, unlike the default baseline's quiet skip) ---
write_bundle "$tmp/nogit/specs/myspec" Draft
run_v 2 --baseline HEAD "$tmp/nogit/specs"
has "not in a git work tree"

run_v 2 --baseline no-such-ref "$repo/specs"
has "baseline ref does not resolve"

# --- 13. Changelog-on-supersede (REQ-A3.3) ---
# A supersede newly introduced since the baseline must be accompanied by a
# dated Changelog entry naming the superseded ID; absent one it is flagged,
# status-scoped (error on Active, warning on Draft). A supersede already
# present in the baseline is not re-flagged.
repo3="$tmp/repo3"
mkdir -p "$repo3"
git -C "$repo3" init -q
write_bundle "$repo3/specs/myspec" Active
git -C "$repo3" add -A
git -C "$repo3" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm base

# Supersede REQ-X1.2 with REQ-X1.3, leaving the Changelog at "created." — no
# entry names the supersede.
cat >"$repo3/specs/myspec/requirements.md" <<'EOF'
# Fixture — Requirements

**Status:** Active
**Last reviewed:** 2026-06-12
**Format-version:** 1

## Goal

A fixture bundle.

## REQ-X — fixture group

- **REQ-X1.1** The widget SHALL exist.
  *(Cites: D-1.)*
- **REQ-X1.2** The gadget SHALL exist. **Superseded-by: REQ-X1.3** (2026-06-12)
- **REQ-X1.3** (supersedes REQ-X1.2) The gadget SHALL exist and hum.
  *(Cites: D-1.)*

## Changelog

- 2026-06-12 — created.

## Sources

- the fixture seed.
EOF
edit "$repo3/specs/myspec/test-spec.md" 's/^### REQ-X1.2 — gadget exists \[manual\]$/### REQ-X1.3 — gadget hums [manual]/'
run_v 1 --baseline HEAD "$repo3/specs"
has "ERROR"
has "REQ-X1.2"
has "Changelog"

# The same un-logged supersede on Draft warns rather than blocks.
edit "$repo3/specs/myspec/requirements.md" 's/^\*\*Status:\*\* Active$/**Status:** Draft/'
edit "$repo3/specs/myspec/design.md" 's/^\*\*Status:\*\* Active$/**Status:** Draft/'
edit "$repo3/specs/myspec/tasks.md" 's/^\*\*Status:\*\* Active$/**Status:** Draft/'
edit "$repo3/specs/myspec/test-spec.md" 's/^\*\*Status:\*\* Active$/**Status:** Draft/'
run_v 0 --baseline HEAD "$repo3/specs"
has "WARN"
has "Changelog"

# Adding a dated Changelog entry naming the supersede clears the finding
# (back on Active).
edit "$repo3/specs/myspec/requirements.md" 's/^\*\*Status:\*\* Draft$/**Status:** Active/'
edit "$repo3/specs/myspec/design.md" 's/^\*\*Status:\*\* Draft$/**Status:** Active/'
edit "$repo3/specs/myspec/tasks.md" 's/^\*\*Status:\*\* Draft$/**Status:** Active/'
edit "$repo3/specs/myspec/test-spec.md" 's/^\*\*Status:\*\* Draft$/**Status:** Active/'
edit "$repo3/specs/myspec/requirements.md" 's|^- 2026-06-12 — created\.$|- 2026-06-12 — created.\
- 2026-06-12 — REQ-X1.2 superseded by REQ-X1.3.|'
run_v 0 --baseline HEAD "$repo3/specs"
has "0 error(s), 0 warning(s)"

# A supersede already present in the baseline is not re-flagged (only newly
# introduced supersedes require a fresh Changelog entry).
git -C "$repo3" add -A
git -C "$repo3" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm superseded
edit "$repo3/specs/myspec/requirements.md" 's/^- 2026-06-12 — REQ-X1.2 superseded by REQ-X1.3\.$//'
run_v 0 --baseline HEAD "$repo3/specs"
has "0 error(s), 0 warning(s)"

# Deleting requirements.md while the baseline still has it must not crash the
# changelog-on-supersede check: the current-file reads are guarded, so the
# run degrades gracefully (the missing-file gap is reported, no raw awk
# "can't open" leaks to stderr, and the summary line is still printed) rather
# than aborting under set -eu (REQ-K1.7).
repo4="$tmp/repo4"
mkdir -p "$repo4"
git -C "$repo4" init -q
write_bundle "$repo4/specs/myspec" Active
git -C "$repo4" add -A
git -C "$repo4" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm base
rm "$repo4/specs/myspec/requirements.md"
run_v 1 --baseline HEAD "$repo4/specs"
has "missing file: requirements.md"
has "error(s)"
lacks "can't open"

# The matcher names the superseded id as a whole token: a changelog that only
# mentions a longer dotted token ("X1.2.alpha") does not count as naming
# REQ-X1.2, so an un-logged supersede is still flagged.
repo5="$tmp/repo5"
mkdir -p "$repo5"
git -C "$repo5" init -q
write_bundle "$repo5/specs/myspec" Active
git -C "$repo5" add -A
git -C "$repo5" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm base
cat >"$repo5/specs/myspec/requirements.md" <<'EOF'
# Fixture — Requirements

**Status:** Active
**Last reviewed:** 2026-06-12
**Format-version:** 1

## Goal

A fixture bundle.

## REQ-X — fixture group

- **REQ-X1.1** The widget SHALL exist.
  *(Cites: D-1.)*
- **REQ-X1.2** The gadget SHALL exist. **Superseded-by: REQ-X1.3** (2026-06-12)
- **REQ-X1.3** (supersedes REQ-X1.2) The gadget SHALL exist and hum.
  *(Cites: D-1.)*

## Changelog

- 2026-06-12 — created.
- 2026-06-12 — renamed the X1.2.alpha prototype flag.

## Sources

- the fixture seed.
EOF
edit "$repo5/specs/myspec/test-spec.md" 's/^### REQ-X1.2 — gadget exists \[manual\]$/### REQ-X1.3 — gadget hums [manual]/'
run_v 1 --baseline HEAD "$repo5/specs"
has "REQ-X1.2"
has "Changelog"

# A sentence-final mention ("superseded REQ-X1.2.") still counts as naming it
# (the trailing period is not part of the id), so the finding clears.
edit "$repo5/specs/myspec/requirements.md" 's|^- 2026-06-12 — created\.$|- 2026-06-12 — created.\
- 2026-06-12 — superseded REQ-X1.2.|'
run_v 0 --baseline HEAD "$repo5/specs"
has "0 error(s), 0 warning(s)"

# The mention must live in a DATED changelog entry (REQ-A3.3). An undated
# bullet that names the id does not satisfy the check; a dated entry whose
# continuation line names it does (entries span multiple lines).
repo6="$tmp/repo6"
mkdir -p "$repo6"
git -C "$repo6" init -q
write_bundle "$repo6/specs/myspec" Active
git -C "$repo6" add -A
git -C "$repo6" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm base
cat >"$repo6/specs/myspec/requirements.md" <<'EOF'
# Fixture — Requirements

**Status:** Active
**Last reviewed:** 2026-06-12
**Format-version:** 1

## Goal

A fixture bundle.

## REQ-X — fixture group

- **REQ-X1.1** The widget SHALL exist.
  *(Cites: D-1.)*
- **REQ-X1.2** The gadget SHALL exist. **Superseded-by: REQ-X1.3** (2026-06-12)
- **REQ-X1.3** (supersedes REQ-X1.2) The gadget SHALL exist and hum.
  *(Cites: D-1.)*

## Changelog

- 2026-06-12 — created.
- REQ-X1.2 placeholder, undated.

## Sources

- the fixture seed.
EOF
edit "$repo6/specs/myspec/test-spec.md" 's/^### REQ-X1.2 — gadget exists \[manual\]$/### REQ-X1.3 — gadget hums [manual]/'
run_v 1 --baseline HEAD "$repo6/specs"
has "REQ-X1.2"
has "Changelog"

# A dated entry naming the supersede on its continuation line clears it.
edit "$repo6/specs/myspec/requirements.md" 's|^- REQ-X1.2 placeholder, undated\.$|- 2026-06-12 — supersession note:\
  retired REQ-X1.2 in favor of REQ-X1.3.|'
run_v 0 --baseline HEAD "$repo6/specs"
has "0 error(s), 0 warning(s)"

# --- 14. Ready status: recognized, errors-block like Active (REQ-B1.2) ---
# A clean Ready bundle passes: Ready is a known status, not flagged unknown.
write_bundle "$root/fixture" Ready
run_v 0 "$root"
has "0 error(s), 0 warning(s)"

# The same structural gap that only warns on Draft is an error on Ready,
# exactly as on Active: Ready is signed-off live content (D-25 severity). The
# unknown-status finding must not appear (Ready is recognized).
write_bundle "$root/fixture" Ready
edit "$root/fixture/tasks.md" '/^- \*\*Done when:\*\*/d'
run_v 1 "$root"
has "ERROR fixture: Task 1 missing field: Done when"
lacks "unknown status"

# The Draft path is unchanged: the same gap stays a warning.
write_bundle "$root/fixture" Draft
edit "$root/fixture/tasks.md" '/^- \*\*Done when:\*\*/d'
run_v 0 "$root"
has "WARN"
has "Done when"
lacks "ERROR"

# --- 15. Status transitions involving Ready (REQ-B1.3) ---
# Draft→Ready, Ready→Active, Ready→Done, Active→Done, and Done→Draft are all
# accepted (no positive transition is rejected); terminal-state discipline is
# preserved. Each case is a baseline-diff over a throwaway repo: commit the
# `from` status, edit the four files to the `to` status, validate against the
# committed baseline.
treq="$tmp/repo-trans"
# Fresh repo per case: consecutive cases can share a `from` status, so a
# reused repo would commit an identical baseline twice and abort on the
# nothing-to-commit no-op. Isolation keeps each baseline self-contained.
transition() {
  from=$1
  to=$2
  expect=$3
  rm -rf "$treq"
  mkdir -p "$treq"
  git -C "$treq" init -q
  write_bundle "$treq/specs/myspec" "$from"
  git -C "$treq" add -A
  git -C "$treq" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm "$from"
  for f in requirements design tasks test-spec; do
    edit "$treq/specs/myspec/$f.md" "s/^\\*\\*Status:\\*\\* $from\$/**Status:** $to/"
  done
  run_v "$expect" --baseline HEAD "$treq/specs"
}

transition Draft Ready 0
has "0 error(s), 0 warning(s)"
transition Ready Active 0
has "0 error(s), 0 warning(s)"
transition Ready Done 0
has "0 error(s), 0 warning(s)"
transition Active Done 0
has "0 error(s), 0 warning(s)"
transition Done Draft 0
has "0 error(s), 0 warning(s)"

# Terminal-state discipline is preserved: a transition out of either terminal
# status (Superseded or Retired) into Ready is still a hard error, even with
# Ready now in the lifecycle. Both terminal statuses share one case arm, so
# covering each guards against the arm being narrowed to only one of them.
transition Superseded Ready 1
has "ERROR"
has "terminal"
transition Retired Ready 1
has "ERROR"
has "terminal"

# --- 16. Format-version 2: a compliant v2 bundle passes ---
write_bundle_v2 "$root/fixture" Draft
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

write_bundle_v2 "$root/fixture" Ready
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# A valid reference bullet (existing task id, one section) is conforming.
write_bundle_v2 "$root/fixture" Ready
park "$root/fixture" "Awaiting input" "- **Task 2** blocked on the palette decision."
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# Plain non-task bullets in Deferred / Out of scope never count as
# reference bullets and stay conforming.
write_bundle_v2 "$root/fixture" Ready
park "$root/fixture" "Deferred" "- **Gizmo retirement.** Not yet. Confidence: high. **Gate:** GATE(when: never). Citations: D-1."
park "$root/fixture" "Out of scope" "- Painting the widget."
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# --- 17. v2 banned placement headings (REQ-C1.5), per-token fixtures ---
for ph in "Forward plan" "In progress" "Completed"; do
  write_bundle_v2 "$root/fixture" Ready
  printf '\n## %s\n\n(none yet)\n' "$ph" >>"$root/fixture/tasks.md"
  run_v 1 "$root/fixture"
  has "ERROR"
  has "placement section \"## $ph\""

  # The same violation warns rather than errors on Draft.
  write_bundle_v2 "$root/fixture" Draft
  printf '\n## %s\n\n(none yet)\n' "$ph" >>"$root/fixture/tasks.md"
  run_v 0 "$root/fixture"
  has "WARN"
  has "placement section \"## $ph\""
  lacks "ERROR"
done

# A trailing-space variant of a banned heading is still caught (a guard
# that exact-matches would fail open on sloppy hand edits).
write_bundle_v2 "$root/fixture" Ready
printf '\n## In progress \n\n(none yet)\n' >>"$root/fixture/tasks.md"
run_v 1 "$root/fixture"
has "ERROR"
has "placement section \"## In progress\""

# A CRLF-terminated banned heading is caught too: the parser strips a
# trailing CR before matching, so line endings cannot fail the ban open.
write_bundle_v2 "$root/fixture" Ready
printf '\r\n## Completed\r\n\r\n(none yet)\r\n' >>"$root/fixture/tasks.md"
run_v 1 "$root/fixture"
has "ERROR"
has "placement section \"## Completed\""

# --- 18. v2 banned state annotations (REQ-C1.5), per-token fixtures ---
# Values vary per token; the finding names the token itself.
annot_value() {
  case $1 in
    Status) echo "implementing" ;;
    "Last activity") echo "2026-07-15" ;;
    Dispatch) echo "backend=tmux · window=w1 · dispatched 2026-07-15T00:00:00Z" ;;
  esac
}
for tok in "Status" "Last activity" "Dispatch"; do
  write_bundle_v2 "$root/fixture" Ready
  edit "$root/fixture/tasks.md" \
    "s/^- \\*\\*Done when:\\*\\* The gadget exists\\.\$/&\\
- **$tok:** $(annot_value "$tok")/"
  run_v 1 "$root/fixture"
  has "ERROR"
  has "state annotation bullet \"$tok\""
  has "Task 2"

  write_bundle_v2 "$root/fixture" Draft
  edit "$root/fixture/tasks.md" \
    "s/^- \\*\\*Done when:\\*\\* The gadget exists\\.\$/&\\
- **$tok:** $(annot_value "$tok")/"
  run_v 0 "$root/fixture"
  has "WARN"
  has "state annotation bullet \"$tok\""
  lacks "ERROR"
done

# --- 19. v2 restricted stored status (D-4): Active/Done are derived ---
write_bundle_v2 "$root/fixture" Active
run_v 1 "$root/fixture"
has "ERROR"
has "stored status Active"

write_bundle_v2 "$root/fixture" Done
run_v 1 "$root/fixture"
has "ERROR"
has "stored status Done"

# Retired/Superseded stay stored terminal declarations (Superseded needs
# its pointer, same as v1).
write_bundle_v2 "$root/fixture" Retired
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# Terminal statuses keep the D-25 frozen-record severity for v2-invariant
# violations: a Retired v2 bundle with a banned placement section warns
# and does not block CI (the carried-over severity model; REQ-C1.5's
# "non-Draft" reads as the signed-off live statuses).
write_bundle_v2 "$root/fixture" Retired
printf '\n## Completed\n\n(none yet)\n' >>"$root/fixture/tasks.md"
run_v 0 "$root/fixture"
has "WARN"
has "placement section"
lacks "ERROR"

# An unknown status is still a hard error on v2.
write_bundle_v2 "$root/fixture" Banana
run_v 1 "$root/fixture"
has "ERROR"
has "unknown status"

# --- 20. v2 pointer line (D-5): fixed vocabulary, per file ---
write_bundle_v2 "$root/fixture" Ready
edit "$root/fixture/requirements.md" '/^\*\*Execution:\*\*/d'
run_v 1 "$root/fixture"
has "ERROR"
has "requirements.md: missing **Execution:** pointer line"

write_bundle_v2 "$root/fixture" Ready
edit "$root/fixture/tasks.md" \
  's/^\*\*Execution:\*\* derived — see the status render$/**Execution:** derived — see docs/'
run_v 1 "$root/fixture"
has "ERROR"
has "tasks.md: non-canonical **Execution:** pointer line"

# Draft warns on the same violations, non-canonical included.
write_bundle_v2 "$root/fixture" Draft
edit "$root/fixture/requirements.md" '/^\*\*Execution:\*\*/d'
run_v 0 "$root/fixture"
has "WARN"
has "missing **Execution:** pointer line"
lacks "ERROR"

write_bundle_v2 "$root/fixture" Draft
edit "$root/fixture/tasks.md" \
  's/^\*\*Execution:\*\* derived — see the status render$/**Execution:** derived — see docs/'
run_v 0 "$root/fixture"
has "WARN"
has "non-canonical **Execution:** pointer line"
lacks "ERROR"

# --- 21. v2 reference-bullet integrity (D-3, REQ-C1.9) ---
# A bullet naming a task id with no matching block fails.
write_bundle_v2 "$root/fixture" Ready
park "$root/fixture" "Awaiting input" "- **Task 9** where did this come from?"
run_v 1 "$root/fixture"
has "ERROR"
has "unknown task id 9"

# Two bullets naming the same task in one section fail, and the message
# names the section once, not "X and X".
write_bundle_v2 "$root/fixture" Ready
park "$root/fixture" "Awaiting input" "- **Task 2** first question."
park "$root/fixture" "Awaiting input" "- **Task 2** second question."
run_v 1 "$root/fixture"
has "ERROR"
has "more than one reference bullet"
has "twice in Awaiting input"

# The same task named in two human-payload sections fails (a task is
# parked in one section at a time).
write_bundle_v2 "$root/fixture" Ready
park "$root/fixture" "Awaiting input" "- **Task 2** open question."
park "$root/fixture" "Deferred" "- **Task 2** also deferred?"
run_v 1 "$root/fixture"
has "ERROR"
has "one section at a time"

# A grammar-violating reference-bullet id is rejected (REQ-C1.9).
write_bundle_v2 "$root/fixture" Ready
park "$root/fixture" "Awaiting input" '- **Task 2;rm-rf** hostile id.'
run_v 1 "$root/fixture"
has "ERROR"
has "fails the task-id grammar"

# A plain prose bullet whose bold lead happens to start with the word
# "Task " is NOT a reference bullet (the doctrine allows plain non-task
# bullets in Deferred / Out of scope): inner whitespace in the bold lead
# marks it prose, so it is not rejected as a grammar violation.
write_bundle_v2 "$root/fixture" Ready
park "$root/fixture" "Deferred" "- **Task force assembled.** deferred until the team exists."
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# An unterminated bold lead (no closing **) is not a reference bullet
# either; malformed emphasis is markdown lint's beat, not the parser's. Under
# Awaiting input that leaves it a non-reference bullet (REQ-D1.1); in
# Deferred it is tolerated prose.
write_bundle_v2 "$root/fixture" Ready
park "$root/fixture" "Awaiting input" "- **Task 2 unterminated bold"
run_v 1 "$root/fixture"
has "non-reference bullet"
lacks "fails the task-id grammar"

write_bundle_v2 "$root/fixture" Ready
park "$root/fixture" "Deferred" "- **Task 2 unterminated bold"
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# The classification boundary is pinned from the hostile side too: a
# whitespace-bearing bold lead is prose even when it looks like an
# injection attempt — treated as data, never a grammar rejection, and
# nothing of it is echoed (the purity finding names only the line).
write_bundle_v2 "$root/fixture" Ready
park "$root/fixture" "Awaiting input" '- **Task ;rm -rf /** hostile prose lead.'
run_v 1 "$root/fixture"
has "non-reference bullet"
lacks "fails the task-id grammar"
lacks "rm -rf"

write_bundle_v2 "$root/fixture" Ready
park "$root/fixture" "Deferred" '- **Task ;rm -rf /** hostile prose lead.'
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# A payload-section heading with a trailing space still scopes the
# integrity checks (exact-match section tracking would fail open).
write_bundle_v2 "$root/fixture" Ready
edit "$root/fixture/tasks.md" 's/^## Deferred$/## Deferred /'
edit "$root/fixture/tasks.md" \
  '/^## Deferred /,/^## Out of scope$/s/^(none yet)$/- **Task 9** parked under a sloppy heading./'
run_v 1 "$root/fixture"
has "ERROR"
has "unknown task id 9"

# Draft warns on the same violations (unknown id, duplicate,
# cross-section, grammar).
write_bundle_v2 "$root/fixture" Draft
park "$root/fixture" "Awaiting input" "- **Task 9** where did this come from?"
run_v 0 "$root/fixture"
has "WARN"
has "unknown task id 9"
lacks "ERROR"

write_bundle_v2 "$root/fixture" Draft
park "$root/fixture" "Awaiting input" "- **Task 2** first question."
park "$root/fixture" "Awaiting input" "- **Task 2** second question."
run_v 0 "$root/fixture"
has "WARN"
has "more than one reference bullet"
lacks "ERROR"

write_bundle_v2 "$root/fixture" Draft
park "$root/fixture" "Awaiting input" "- **Task 2** open question."
park "$root/fixture" "Deferred" "- **Task 2** also deferred?"
run_v 0 "$root/fixture"
has "WARN"
has "one section at a time"
lacks "ERROR"

write_bundle_v2 "$root/fixture" Draft
park "$root/fixture" "Awaiting input" '- **Task 2;rm-rf** hostile id.'
run_v 0 "$root/fixture"
has "WARN"
has "fails the task-id grammar"
lacks "ERROR"

# --- 22. Fail-closed version keying (REQ-C1.8) at every status ---
# Unparseable Format-version errors on Draft and Ready alike; mirror-drift
# warnings may accompany it, but the version finding itself is hard.
write_bundle "$root/fixture" Draft
edit "$root/fixture/requirements.md" \
  's/^\*\*Format-version:\*\* 1$/**Format-version:** banana/'
run_v 1 "$root/fixture"
has "ERROR"
has "unparseable format-version"

write_bundle "$root/fixture" Ready
edit "$root/fixture/requirements.md" \
  's/^\*\*Format-version:\*\* 1$/**Format-version:** banana/'
# Fail-closed means no write: the spec directory's content digest is
# unchanged by the failing invocation (REQ-C1.8).
digest_before=$(cat "$root/fixture"/*.md | cksum)
run_v 1 "$root/fixture"
has "ERROR"
has "unparseable format-version"
digest_after=$(cat "$root/fixture"/*.md | cksum)
[ "$digest_before" = "$digest_after" ] \
  || fail "validator wrote into the spec directory on a fail-closed run"

# A parseable-but-undeclared numeric version stays the unsupported error.
write_bundle_v2 "$root/fixture" Draft
edit "$root/fixture/requirements.md" \
  's/^\*\*Format-version:\*\* 2$/**Format-version:** 7/'
run_v 1 "$root/fixture"
has "ERROR"
has "unsupported format-version"

# An absent requirements.md must not skip version keying: the version is
# derived from the first sibling mirror that declares one (same fallback
# the Status severity derivation uses), so a v2 bundle's invariants still
# fire — deleting the authoritative file cannot fail the v2 rules open.
write_bundle_v2 "$root/fixture" Ready
printf '\n## In progress\n\n(none yet)\n' >>"$root/fixture/tasks.md"
edit "$root/fixture/tasks.md" \
  "s/^- \\*\\*Done when:\\*\\* The gadget exists\\.\$/&\\
- **Status:** implementing/"
rm "$root/fixture/requirements.md"
run_v 1 "$root/fixture"
has "missing file: requirements.md"
has "placement section \"## In progress\""
has "state annotation bullet \"Status\""

# With no Format-version declaration anywhere, the hard fail-closed error
# still fires (missing requirements.md and no declaring sibling).
write_bundle_v2 "$root/fixture" Ready
rm "$root/fixture/requirements.md"
for bf in design tasks test-spec; do
  edit "$root/fixture/$bf.md" '/^\*\*Format-version:\*\*/d'
done
run_v 1 "$root/fixture"
has "missing or empty Format-version"

# Conflicting sibling declarations with requirements.md absent fail
# closed: the fallback must not silently resolve to whichever file comes
# first (a drifted lower sibling would skip the v2 invariants).
write_bundle_v2 "$root/fixture" Ready
rm "$root/fixture/requirements.md"
edit "$root/fixture/design.md" \
  's/^\*\*Format-version:\*\* 2$/**Format-version:** 1/'
printf '\n## In progress\n\n(none yet)\n' >>"$root/fixture/tasks.md"
run_v 1 "$root/fixture"
has "conflicting Format-version declarations"

# A charset-valid but spec-file-less child directory under a specs root
# is a broken bundle, not a silent pass: the missing-file gaps plus the
# hard version error surface it (fail-closed; previously four
# Draft-severity warnings).
rm -rf "$root/fixture"
mkdir -p "$root/fixture"
run_v 1 "$root"
has "missing or empty Format-version"

# --- 23. v2 echo discipline (REQ-C1.9): escape bytes never reach output ---
esc=$(printf '\033')
write_bundle_v2 "$root/fixture" Ready
park "$root/fixture" "Awaiting input" "- **Task 4${esc}[31m** hostile bullet."
run_v 1 "$root/fixture"
has "fails the task-id grammar"
lacks "$esc"

# A header value carrying escape bytes (the pointer line) is sanitized in
# the non-canonical finding.
write_bundle_v2 "$root/fixture" Ready
edit "$root/fixture/requirements.md" \
  "s/^\\*\\*Execution:\\*\\* derived — see the status render\$/**Execution:** derived ${esc}[31mevil/"
run_v 1 "$root/fixture"
has "non-canonical"
lacks "$esc"

# An unknown-status header value with escape bytes is sanitized too.
write_bundle_v2 "$root/fixture" "Ban${esc}ana"
run_v 1 "$root/fixture"
has "unknown status"
lacks "$esc"

# --- 24. Fenced illustration (REQ-C1.2, D-5) ---
# doctrine/spec-format.md, *Fenced illustration*: no line inside a column-0
# fence parses as any element of the format. The validator is a parser of spec
# bundles like any other, so a bundle that documents its own conventions in a
# fence must not have that documentation validated as content.
write_bundle "$root/fixture" Active

# The reproduced defect: a fenced mock REQ bullet read as a real one, colliding
# with the id it illustrates and firing a false duplicate-REQ error. The fence
# sits INSIDE the REQ group, where the requirements parse is actually looking.
cat >"$root/fixture/requirements.md" <<'EOF'
# Fixture — Requirements

**Status:** Active
**Last reviewed:** 2026-06-12
**Format-version:** 1

## Goal

A fixture bundle.

## REQ-X — fixture group

- **REQ-X1.1** The widget SHALL exist.
  *(Cites: D-1.)*
- **REQ-X1.2** The gadget SHALL exist.
  *(Cites: D-1.)*

A requirement bullet is written like this:

```markdown
- **REQ-X1.1** The widget SHALL exist.
  *(Cites: D-1.)*
- **REQ-X9.9** A prose-only bullet with no citation at all
```

## Changelog

- 2026-06-12 — created.

## Sources

- the fixture seed.
EOF
run_v 0 "$root/fixture"
lacks "duplicate REQ-ID"
has "0 error(s), 0 warning(s)"

# The same for a fenced decision heading and a fenced task block: neither
# duplicates the real record it illustrates, and the fenced task's ABSENT
# definition fields raise no missing-field gaps.
write_bundle "$root/fixture" Active
cat >>"$root/fixture/design.md" <<'EOF'

## Conventions

```markdown
### D-1: Widgets are good  (N)
```
EOF
cat >>"$root/fixture/tasks.md" <<'EOF'

## Notes

```markdown
### Task 1 — Build the widget
```
EOF
run_v 0 "$root/fixture"
lacks "duplicate D-ID"
lacks "duplicate task id"
lacks "missing field"

# Fence-awareness must not become a fail-OPEN either: a fenced test-spec entry
# is illustration, so it cannot satisfy REQ↔test-spec coverage for a REQ that
# has no real entry.
write_bundle "$root/fixture" Active
edit "$root/fixture/test-spec.md" 's/^### REQ-X1.2 — gadget exists \[manual\]$/### REQ-X9.9 — unrelated [manual]/'
cat >>"$root/fixture/test-spec.md" <<'EOF'

## Conventions

```markdown
### REQ-X1.2 — gadget exists [manual]
```
EOF
run_v 1 "$root/fixture"
has "REQ-X1.2 has no test-spec entry"

# The v2 invariant-ledger scan takes the same lexer: a v2 bundle documenting
# what version 1 looked like is showing an example, not reintroducing the
# placement sections and state annotations version 2 banned.
write_bundle_v2 "$root/fixture" Ready
cat >>"$root/fixture/tasks.md" <<'EOF'

## Notes

Version 1 kept execution state in the file:

```markdown
## Forward plan

### Task 1 — Build the widget

- **Status:** implementing
- **Last activity:** 2026-06-12
- **Dispatch:** backend=tmux
```
EOF
run_v 0 "$root/fixture"
lacks "does not exist in format-version 2"

# The v2 pointer line is a header line, so a fenced copy of it does not satisfy
# the check either.
write_bundle_v2 "$root/fixture" Ready
edit "$root/fixture/design.md" \
  's/^\*\*Execution:\*\* derived — see the status render$//'
cat >>"$root/fixture/design.md" <<'EOF'

## Conventions

```markdown
**Execution:** derived — see the status render
```
EOF
run_v 1 "$root/fixture"
has "design.md: missing **Execution:** pointer line"

# --- 25. Unbalanced column-0 fence flagged (REQ-D1.11, D-5) ---
# An unterminated fence would otherwise silently swallow the remainder of the
# file as illustration, dropping content from every parser with no signal.
write_bundle "$root/fixture" Active
printf '\n```\nan unterminated fence\n' >>"$root/fixture/requirements.md"
run_v 1 "$root/fixture"
has "unclosed column-0 code fence"
has "requirements.md"

# Status-scoped like the rest of the D-25 severity model: a warning on Draft.
write_bundle "$root/fixture" Draft
printf '\n```\nan unterminated fence\n' >>"$root/fixture/tasks.md"
run_v 0 "$root/fixture"
has "WARN"
has "unclosed column-0 code fence"

# An unclosed INDENTED fence is ordinary content, not a toggle, so it is not
# flagged: only column-0 fences open illustration mode.
write_bundle "$root/fixture" Active
printf '\n    ```\nan indented fence that never closes\n' >>"$root/fixture/design.md"
run_v 0 "$root/fixture"
lacks "unclosed column-0 code fence"

# A balanced fence passes untouched.
write_bundle "$root/fixture" Active
# shellcheck disable=SC2016 # a literal fence pair, never expanded
printf '\n```\nbalanced\n```\n' >>"$root/fixture/test-spec.md"
run_v 0 "$root/fixture"
lacks "unclosed column-0 code fence"
has "0 error(s), 0 warning(s)"

# A file the probe cannot lex at all (NUL-bearing: awk truncates records at
# NUL, so fenced illustration could not be told from content) fails closed AND
# carries the reason, rather than a generic "could not read" that sends the
# reader looking at file permissions.
write_bundle "$root/fixture" Active
printf 'x\000y\n' >>"$root/fixture/design.md"
run_v 1 "$root/fixture"
# Asserted as one span, not two `has` calls: the sibling header-block check
# reports "NUL byte" too, so a split assertion would pass on its finding while
# this one still said nothing useful.
has "cannot be told from content (fail closed): spec-parse: NUL byte"

# --- 26. Changelog-named task-retirement escape (REQ-D1.6, D-12) ---
# The escape REQ supersession already has, extended to task blocks: where a
# block genuinely must leave the file, a dated Changelog entry naming the
# retired id authorizes the removal, and nothing else does.
repo6="$tmp/repo6"
mkdir -p "$repo6"
git -C "$repo6" init -q
write_bundle "$repo6/specs/myspec" Active
# A second task, so the baseline has an id that can be retired without
# emptying the file.
cat >>"$repo6/specs/myspec/tasks.md" <<'EOF'

### Task 7 — Build the gadget

- **Deliverables:** A gadget.
- **Done when:** The gadget exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-X1.2
- **Estimated effort:** half day
EOF
git -C "$repo6" add -A
git -C "$repo6" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm base

# retire <changelog-line> — drop Task 7's block and append the given line
# (empty for none) to the Changelog.
retire() {
  awk '/^### Task 7 — /{ skip = 1 } /^## /{ skip = 0 } !skip' \
    "$repo6/specs/myspec/tasks.md.orig" >"$repo6/specs/myspec/tasks.md"
  cp "$repo6/specs/myspec/requirements.md.orig" "$repo6/specs/myspec/requirements.md"
  [ -z "$1" ] || edit "$repo6/specs/myspec/requirements.md" \
    "s|^- 2026-06-12 — created\\.\$|- 2026-06-12 — created.\\
$1|"
}
cp "$repo6/specs/myspec/tasks.md" "$repo6/specs/myspec/tasks.md.orig"
cp "$repo6/specs/myspec/requirements.md" "$repo6/specs/myspec/requirements.md.orig"

# An unnamed removal errors.
retire ''
run_v 1 --baseline HEAD "$repo6/specs"
has "Task 7 renumbered or removed"

# A dated entry naming the retired id authorizes it.
retire '- 2026-06-13 — Task 7 retired: folded into Task 1.'
run_v 0 --baseline HEAD "$repo6/specs"
has "0 error(s), 0 warning(s)"

# A token that fails the task-id grammar does not activate the escape.
retire '- 2026-06-13 — Task 7a retired: folded into Task 1.'
run_v 1 --baseline HEAD "$repo6/specs"
has "Task 7 renumbered or removed"

# A valid but DIFFERENT id does not activate it either: the escape matches the
# id that actually left, not any named id.
retire '- 2026-06-13 — Task 8 retired: folded into Task 1.'
run_v 1 --baseline HEAD "$repo6/specs"
has "Task 7 renumbered or removed"

# An UNDATED entry naming the retired id does not activate it: the dated form
# is what makes the removal auditable.
retire '- Task 7 retired: folded into Task 1.'
run_v 1 --baseline HEAD "$repo6/specs"
has "Task 7 renumbered or removed"

# A bare number that happens to match the retired id does not activate the
# escape: an unqualified digit is indistinguishable from a date component or
# any other number in prose, so the escape reads the `Task <id>` citation form.
retire '- 2026-06-13 — dropped 7 stale references.'
run_v 1 --baseline HEAD "$repo6/specs"
has "Task 7 renumbered or removed"

# A dotted id retires the same way, and the trailing-period form counts: the
# escape matches the id as a whole token, not as a prefix.
retire '- 2026-06-13 — Task 7 retired, folded into Task 1.'
run_v 0 --baseline HEAD "$repo6/specs"
has "0 error(s), 0 warning(s)"

# ...but a longer id it only prefixes does not match.
retire '- 2026-06-13 — Task 70 retired: folded into Task 1.'
run_v 1 --baseline HEAD "$repo6/specs"
has "Task 7 renumbered or removed"

# A fenced changelog entry is illustration, not an authorization.
retire ''
cat >>"$repo6/specs/myspec/requirements.md" <<'EOF'

## Conventions

```markdown
- 2026-06-13 — Task 7 retired: folded into Task 1.
```
EOF
run_v 1 --baseline HEAD "$repo6/specs"
has "Task 7 renumbered or removed"

# A citation split across a hard wrap still authorizes: changelog entries are
# prose wrapped by hand, so `Task` and its id land on separate lines sooner or
# later. The escape reads the whole dated entry, not one line of it — otherwise
# a correctly-written entry is rejected purely for where the author wrapped, and
# the remedy message names the exact text already sitting in the file.
retire '- 2026-06-13 — retired as redundant, folded into Task\
  7 during the cleanup.'
run_v 0 --baseline HEAD "$repo6/specs"
has "0 error(s), 0 warning(s)"

# The wrap tolerance does not reach across entries: a dated entry ending in
# `Task` and a SEPARATE later bullet starting with the id is two records, not a
# citation, so joining them would invent an authorization nobody wrote.
retire '- 2026-06-13 — nothing to do with Task\
- 2026-06-14 — 7 stale references dropped.'
run_v 1 --baseline HEAD "$repo6/specs"
has "Task 7 renumbered or removed"

# --- 27. Baseline-side fence-awareness (REQ-C1.2) ---
# The baseline half of the stable-ID check parses the same grammar as the
# current half. If only one side were fence-aware they would disagree about
# what the baseline defined, and a fenced mock id present in BOTH revisions
# would read as an id that vanished.
repo7="$tmp/repo7"
mkdir -p "$repo7"
git -C "$repo7" init -q
write_bundle "$repo7/specs/myspec" Active
cat >>"$repo7/specs/myspec/requirements.md" <<'EOF'

## Conventions

```markdown
- **REQ-X9.9** A mock requirement that is documentation, not a requirement.
```
EOF
cat >>"$repo7/specs/myspec/design.md" <<'EOF'

## Conventions

```markdown
### D-9: A mock decision
```
EOF
cat >>"$repo7/specs/myspec/tasks.md" <<'EOF'

## Notes

```markdown
### Task 9 — A mock task
```
EOF
git -C "$repo7" add -A
git -C "$repo7" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm base
run_v 0 --baseline HEAD "$repo7/specs"
lacks "REQ-X9.9 renumbered or removed"
lacks "D-9 renumbered or removed"
lacks "Task 9 renumbered or removed"
has "0 error(s), 0 warning(s)"

# --- 28. An UNBALANCED baseline fence never hides a removal (REQ-C1.2, REQ-D1.11) ---
# Fence-stripping the baseline (27) must not become the fail-OPEN direction of
# the same guard. `defence` on an unbalanced source emits only what sits above
# the open fence, and the REQ-D1.11 flag reads the working tree, not the git
# object — so an unbalanced BASELINE would drop ids from the comparison with
# nothing to explain the silence, and a genuinely removed id would pass. The
# baseline is balance-checked in its own right and falls back to the raw blob.
repo8="$tmp/repo8"
mkdir -p "$repo8"
git -C "$repo8" init -q
write_bundle "$repo8/specs/myspec" Active
# The baseline: a fence opened and never closed, with a REAL task below it.
cat >>"$repo8/specs/myspec/tasks.md" <<'EOF'

Someone opened a fence and forgot to close it:

```

### Task 7 — Build the gadget

- **Deliverables:** A gadget.
- **Done when:** The gadget exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-X1.2
- **Estimated effort:** half day
EOF
git -C "$repo8" add -A
git -C "$repo8" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm base
# The current revision closes the fence and drops Task 7 with no retirement
# entry: a stable-ID violation the fence-stripped baseline would not have seen.
write_bundle "$repo8/specs/myspec" Active
run_v 1 --baseline HEAD "$repo8/specs"
has "Task 7 renumbered or removed"
has "unclosed column-0 code fence"

# --- 29. Duplicate in-header declarations error at every status (REQ-D1.9) ---
# A second in-header `Format-version:` or `Status:` line has no honest
# positional winner: the declaration is unparseable, and that is a hard
# finding on Draft and Ready alike (format-grammar D-6, D-9).
for st in Draft Ready; do
  write_bundle "$root/fixture" "$st"
  edit "$root/fixture/requirements.md" \
    "s/^\\*\\*Format-version:\\*\\* 1\$/&\\
**Format-version:** 1/"
  run_v 1 "$root/fixture"
  has "ERROR"
  has "unparseable Format-version: declaration"

  write_bundle "$root/fixture" "$st"
  edit "$root/fixture/requirements.md" \
    "s/^\\*\\*Status:\\*\\* $st\$/&\\
**Status:** $st/"
  run_v 1 "$root/fixture"
  has "ERROR"
  has "unparseable Status: declaration"
done

# The same duplicate in a sibling mirror is caught there too.
write_bundle "$root/fixture" Ready
edit "$root/fixture/design.md" \
  "s/^\\*\\*Status:\\*\\* Ready\$/&\\
**Status:** Ready/"
run_v 1 "$root/fixture"
has "ERROR"
has "design.md: unparseable Status: declaration"

# --- 30. Cited-but-empty requirement bullet (REQ-D1.2) ---
# A live bullet that carries its citation and nothing else has no normative
# text to implement or verify: status-scoped.
write_bundle "$root/fixture" Draft
edit "$root/fixture/requirements.md" \
  's/^- \*\*REQ-X1.2\*\* The gadget SHALL exist\.$/- **REQ-X1.2** *(Cites: D-1.)*/'
edit "$root/fixture/requirements.md" '/^- \*\*REQ-X1.2\*\*/{n;d;}'
run_v 0 "$root/fixture"
has "WARN"
has "REQ-X1.2 has no normative prose"
lacks "REQ-X1.1 has no normative prose"

write_bundle "$root/fixture" Ready
edit "$root/fixture/requirements.md" \
  's/^- \*\*REQ-X1.2\*\* The gadget SHALL exist\.$/- **REQ-X1.2** *(Cites: D-1.)*/'
edit "$root/fixture/requirements.md" '/^- \*\*REQ-X1.2\*\*/{n;d;}'
run_v 1 "$root/fixture"
has "ERROR"
has "REQ-X1.2 has no normative prose"

# A citation annotation wrapped over continuation lines is still only a
# citation: the bullet has no prose before it and none after it.
write_bundle "$root/fixture" Draft
edit "$root/fixture/requirements.md" \
  's/^- \*\*REQ-X1.2\*\* The gadget SHALL exist\.$/- **REQ-X1.2**/'
edit "$root/fixture/requirements.md" \
  's/^  \*(Cites: D-1\.)\*$/  *(Cites: D-1, the fixture\
  seed (Sources).)*/'
run_v 0 "$root/fixture"
has "REQ-X1.2 has no normative prose"

# Prose on a continuation line counts as prose.
write_bundle "$root/fixture" Draft
edit "$root/fixture/requirements.md" \
  's/^- \*\*REQ-X1.2\*\* The gadget SHALL exist\.$/- **REQ-X1.2**\
  The gadget SHALL exist./'
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# A superseded (non-live) record is exempt: its body is frozen history.
write_bundle "$root/fixture" Ready
edit "$root/fixture/requirements.md" \
  's/^- \*\*REQ-X1.2\*\* The gadget SHALL exist\.$/- **REQ-X1.2** **Superseded-by: REQ-X1.1** (2026-06-12)/'
edit "$root/fixture/requirements.md" '/^- \*\*REQ-X1.2\*\*/{n;d;}'
run_v 0 "$root/fixture"
lacks "no normative prose"

# --- 31. Malformed decision shapes (REQ-D1.5) ---
# An H2 `D-<n>` heading is a decision written at the wrong level: flagged as
# malformed rather than read as an ordinary section.
write_bundle "$root/fixture" Draft
cat >>"$root/fixture/design.md" <<'EOF'

## D-2: A decision at the wrong heading level

**Decision:** Level two.

**Alternatives considered:**
- Level three. Rejected because: this fixture must trip the check.

**Chosen because:** the heading is the defect.
EOF
run_v 0 "$root/fixture"
has "WARN"
has "decision heading at H2"
has "design.md:"

write_bundle "$root/fixture" Ready
cat >>"$root/fixture/design.md" <<'EOF'

## D-2 no colon either
EOF
run_v 1 "$root/fixture"
has "ERROR"
has "decision heading at H2"

# A period-labelled field (`**Decision.**`) is named as such, once — not
# reported a second time as the field being missing.
write_bundle "$root/fixture" Draft
edit "$root/fixture/design.md" 's/^\*\*Decision:\*\*/**Decision.**/'
edit "$root/fixture/design.md" 's/^\*\*Chosen because:\*\*/**Chosen because.**/'
run_v 0 "$root/fixture"
has "WARN"
has "period-labelled"
has "Decision."
has "Chosen because."
lacks "missing field"

write_bundle "$root/fixture" Ready
edit "$root/fixture/design.md" 's/^\*\*Alternatives considered:\*\*/**Alternatives considered.**/'
run_v 1 "$root/fixture"
has "ERROR"
has "period-labelled"
has "Alternatives considered."

# --- 32. Canonical task-heading enforcement (REQ-D1.7) ---
# `### Task <id> — <title>` with the em dash is the only recognized form;
# every deviation is flagged, never silently parsed into a wrong id.
deviant() {
  write_bundle "$root/fixture" "$1"
  printf '\n%s\n\n- **Deliverables:** Nothing.\n- **Done when:** Never.\n- **Dependencies:** none\n- **Citations:** D-1\n- **Estimated effort:** half day\n' "$2" \
    >>"$root/fixture/tasks.md"
}
deviant Draft '### Task 2: Colon separator'
run_v 0 "$root/fixture"
has "WARN"
has "malformed task id"
has "### Task <id> — <title>"

deviant Draft '### Task 2 - Hyphen separator'
run_v 0 "$root/fixture"
has "WARN"
has "non-canonical task heading"
has "tasks.md:"

deviant Draft '### Task 2 – En dash separator'
run_v 0 "$root/fixture"
has "non-canonical task heading"

deviant Draft '### Task 2'
run_v 0 "$root/fixture"
has "non-canonical task heading"

deviant Draft '### Task 2 —'
run_v 0 "$root/fixture"
has "non-canonical task heading"

deviant Draft '### Task 2 Missing separator'
run_v 0 "$root/fixture"
has "non-canonical task heading"

deviant Ready '### Task 2 - Hyphen separator'
run_v 1 "$root/fixture"
has "ERROR"
has "non-canonical task heading"

# The canonical form, dotted id included, passes.
deviant Ready '### Task 1.5 — Canonical dotted id'
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# --- 33. v2 Awaiting-input purity (REQ-D1.1) ---
# `## Awaiting input` holds reference bullets only; any other bullet there is
# flagged, status-scoped. A v1 bundle is outside the rule.
write_bundle_v2 "$root/fixture" Draft
park "$root/fixture" "Awaiting input" "- a plain prose question with no task reference."
run_v 0 "$root/fixture"
has "WARN"
has "non-reference bullet"
has "Awaiting input"
lacks "ERROR"

write_bundle_v2 "$root/fixture" Ready
park "$root/fixture" "Awaiting input" "- a plain prose question with no task reference."
run_v 1 "$root/fixture"
has "ERROR"
has "non-reference bullet"

# The bulleted placeholder form is a non-reference bullet too (the rollout
# corrected two in-repo bundles carrying it).
write_bundle_v2 "$root/fixture" Ready
park "$root/fixture" "Awaiting input" "- (none yet)"
run_v 1 "$root/fixture"
has "non-reference bullet"

# The other two payload sections keep allowing plain bullets.
write_bundle_v2 "$root/fixture" Ready
park "$root/fixture" "Deferred" "- a plain deferral note."
park "$root/fixture" "Out of scope" "- a plain exclusion."
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# A reference bullet passes; a fenced example under the section is
# illustration, not a bullet.
write_bundle_v2 "$root/fixture" Ready
park "$root/fixture" "Awaiting input" "- **Task 2** which widget colour?"
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

write_bundle_v2 "$root/fixture" Ready
awk '
  $0 == "## Awaiting input" { print; print ""; print "```markdown"; print "- a fenced example bullet"; print "```"; next }
  { print }
' "$root/fixture/tasks.md" >"$root/fixture/tasks.md.new"
mv "$root/fixture/tasks.md.new" "$root/fixture/tasks.md"
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# v1: the same prose bullet under Awaiting input is not this rule's concern.
write_bundle "$root/fixture" Ready
edit "$root/fixture/tasks.md" \
  '/^## Awaiting input$/,/^## Completed$/s/^(none yet)$/- a plain prose question./'
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# --- 34. Out-of-range unqualified citation tokens (REQ-D1.3, D-13) ---
# A `D-<n>`, `REQ-<id>`, or `Task <id>` token the bundle does not define, with
# no sibling-spec qualifier on the line or in the enclosing block, warns at
# EVERY status (a heuristic never blocks). The fixture root gains a sibling
# bundle directory so a directory name can act as a qualifier.
mkdir -p "$root/bootstrap"
cite() {
  write_bundle "$root/fixture" "$1"
  printf '\n%s\n' "$2" >>"$root/fixture/design.md"
}
cite Ready 'Widgets follow the severity model D-45 describes.'
run_v 0 "$root/fixture"
has "WARN"
has "D-45"
has "not defined in this bundle"
lacks "ERROR"

cite Ready 'Widgets follow REQ-Z9.9 and the plan in Task 7.'
run_v 0 "$root/fixture"
has "REQ-Z9.9"
has "Task 7"
has "not defined in this bundle"

# A sibling-directory name on the same line qualifies every token on it.
cite Ready 'Widgets follow the bootstrap D-45 severity model and its REQ-Z9.9.'
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# A hyphenated foreign namespace that is not a directory counts only when it
# immediately precedes an id token; it then reaches the whole line (both
# directions), the enclosing bullet or paragraph, and the enclosing H3 block.
cite Ready 'Widgets follow the pair-flow D-45 severity model and REQ-Z9.9.'
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# ...but an ordinary hyphenated word that precedes no id does not qualify.
cite Ready 'The widget-level plan follows D-45.'
run_v 0 "$root/fixture"
has "D-45"
has "not defined in this bundle"

# A possessive qualifier still counts.
cite Ready "Widgets follow bootstrap's D-45 severity model."
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# The qualifier reaches the enclosing bullet's continuation lines and the
# enclosing H3 block.
write_bundle "$root/fixture" Ready
cat >>"$root/fixture/design.md" <<'EOF'

### Carried context

- Carried from bootstrap: the severity model
  (D-45) and the identifier discipline
  (REQ-Z9.9).

The same block later leans on D-46 without repeating the name.
EOF
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# ...but not across H3 blocks.
write_bundle "$root/fixture" Ready
cat >>"$root/fixture/design.md" <<'EOF'

### Carried context

Carried from bootstrap: D-45.

### Unrelated section

Leans on D-46 with no name in reach.
EOF
run_v 0 "$root/fixture"
has "D-46"
lacks "D-45"

# In-range tokens pass (the base fixture cites D-1 and REQ-X1.1 throughout).
# The `## Changelog` section is history and is not scanned; fenced
# illustration is not scanned either.
write_bundle "$root/fixture" Ready
edit "$root/fixture/requirements.md" \
  's/^- 2026-06-12 — created\.$/&\
- 2026-06-13 — retired Task 7 and folded D-45 into D-1./'
cat >>"$root/fixture/design.md" <<'EOF'

```markdown
### D-45: An illustrated decision
```
EOF
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# The rule applies in every file and at Draft too.
write_bundle "$root/fixture" Draft
printf '\nSee also D-45.\n' >>"$root/fixture/test-spec.md"
run_v 0 "$root/fixture"
has "WARN"
has "test-spec.md:"
has "D-45"
rm -rf "$root/bootstrap"

# --- 35. Coverage-based dead-path check (REQ-D1.8, D-14) ---
# A live REQ whose bullet text changed since the baseline while its test-spec
# entry did not warns at every status; the comparison is content-based.
dp="$tmp/deadpath"
rm -rf "$dp"
mkdir -p "$dp"
git -C "$dp" init -q
write_bundle "$dp/specs/myspec" Active
git -C "$dp" add -A
git -C "$dp" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm fixture

edit "$dp/specs/myspec/requirements.md" \
  's/^- \*\*REQ-X1.1\*\* The widget SHALL exist\.$/- **REQ-X1.1** The widget SHALL exist and glow./'
run_v 0 --baseline HEAD "$dp/specs"
has "WARN"
has "REQ-X1.1 changed since HEAD"
has "test-spec entry did not"
lacks "REQ-X1.2 changed"
lacks "ERROR"

# Pairing the edit with a test-spec edit clears it.
edit "$dp/specs/myspec/test-spec.md" 's/^The widget fixture passes\.$/The widget fixture passes and glows./'
run_v 0 --baseline HEAD "$dp/specs"
has "0 error(s), 0 warning(s)"

# A citation-only change is provenance, not a changed requirement.
git -C "$dp" checkout -q -- specs
edit "$dp/specs/myspec/requirements.md" \
  '/^- \*\*REQ-X1.1\*\*/{n;s/^  \*(Cites: D-1\.)\*$/  *(Cites: D-1, the fixture seed (Sources).)*/;}'
run_v 0 --baseline HEAD "$dp/specs"
has "0 error(s), 0 warning(s)"

# A position shift with unchanged text is not a change: insert a new REQ
# above the existing ones (with its own entry).
git -C "$dp" checkout -q -- specs
edit "$dp/specs/myspec/requirements.md" \
  's/^- \*\*REQ-X1.1\*\* The widget SHALL exist\.$/- **REQ-X1.3** The sprocket SHALL exist.\
  *(Cites: D-1.)*\
&/'
printf '\n### REQ-X1.3 — sprocket exists [test]\n\nThe sprocket fixture passes.\n' \
  >>"$dp/specs/myspec/test-spec.md"
run_v 0 --baseline HEAD "$dp/specs"
has "0 error(s), 0 warning(s)"

# A REQ superseded since the baseline, its test-spec entry removed per the
# tombstone rule, does not warn: the record is no longer live.
git -C "$dp" checkout -q -- specs
edit "$dp/specs/myspec/requirements.md" \
  's/^- \*\*REQ-X1.2\*\* The gadget SHALL exist\.$/- **REQ-X1.2** The gadget SHALL exist. **Superseded-by: REQ-X1.3** (2026-06-13)\
- **REQ-X1.3** The gadget SHALL exist and hum./'
edit "$dp/specs/myspec/requirements.md" \
  's/^- 2026-06-12 — created\.$/&\
- 2026-06-13 — REQ-X1.2 superseded by REQ-X1.3./'
edit "$dp/specs/myspec/test-spec.md" 's/^### REQ-X1.2 — gadget exists \[manual\]$/### REQ-X1.3 — gadget hums [manual]/'
run_v 0 --baseline HEAD "$dp/specs"
lacks "REQ-X1.2 changed"
lacks "REQ-X1.3 changed"

# Whitespace-only reflow is not a change either.
git -C "$dp" checkout -q -- specs
edit "$dp/specs/myspec/requirements.md" \
  's/^- \*\*REQ-X1.1\*\* The widget SHALL exist\.$/- **REQ-X1.1** The widget\
  SHALL exist./'
run_v 0 --baseline HEAD "$dp/specs"
has "0 error(s), 0 warning(s)"

# --- 36. Review-pass regressions over the hardening rules ---
# Each case below pins a defect the self-review pass reproduced against the
# first landing of rules 16-21; the fixture fails on that landing and passes
# on the fix.

# 36a. The H3 qualifier scope is a block identity, not a per-section ordinal:
# a qualifier in the first H3 block of one section must not reach the first
# H3 block of a later section.
mkdir -p "$root/bootstrap"
write_bundle "$root/fixture" Ready
cat >>"$root/fixture/design.md" <<'EOF'

Carried from bootstrap: D-45.

## Another section

### First block here

Leans on D-46 with no name in reach.
EOF
run_v 0 "$root/fixture"
has "D-46"
lacks "D-45"

# 36b. The enclosing bullet reaches its continuation lines even with no H3
# block around it (the unit scope, isolated from the H3 scope).
write_bundle "$root/fixture" Ready
cat >>"$root/fixture/design.md" <<'EOF'

## Carried context

- Carried from bootstrap: the severity model
  (D-45) and the identifier discipline
  (REQ-Z9.9).

A separate paragraph leaning on D-46.
EOF
run_v 0 "$root/fixture"
has "D-46"
lacks "D-45"
lacks "REQ-Z9.9"

# 36c. A hyphenated namespace's possessive still qualifies the token it
# precedes (the sibling-directory possessive is qualified by membership
# alone, so this is the case that needs the possessive strip).
cite Ready "Widgets follow pair-flow's D-45 severity model."
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# 36d. Every occurrence is reported, not the first per file: a fix-what-is-
# reported loop must converge in one pass.
write_bundle "$root/fixture" Ready
printf '\nFirst mention of D-45 here.\n\nSecond mention of D-45 there.\n' >>"$root/fixture/design.md"
run_v 0 "$root/fixture"
has "D-45 at design.md:18"
has "D-45 at design.md:20"

# 36e. Line numbers cite the source file, not the fence-stripped view.
write_bundle "$root/fixture" Ready
cat >>"$root/fixture/design.md" <<'EOF'

```markdown
### D-9: an illustrated decision
one
two
```

Leans on D-45 after the fence.
EOF
run_v 0 "$root/fixture"
has "D-45 at design.md:24"

# 36f. Trips land in requirements.md and tasks.md too, and a dotted
# `Task <id>` token is read as one citation.
write_bundle "$root/fixture" Ready
edit "$root/fixture/requirements.md" \
  's/^- \*\*REQ-X1.2\*\* The gadget SHALL exist\.$/- **REQ-X1.2** The gadget SHALL exist per D-45./'
edit "$root/fixture/tasks.md" \
  's/^- \*\*Done when:\*\* The widget exists\.$/- **Done when:** The widget exists and Task 7.2 agrees./'
run_v 0 "$root/fixture"
has "D-45 at requirements.md:"
has "Task 7.2 at tasks.md:"

# 36g. A missing defining file does not turn every in-bundle id into a
# foreign one: the missing-file finding is the whole story.
write_bundle "$root/fixture" Ready
rm "$root/fixture/design.md"
run_v 1 "$root/fixture"
has "missing file: design.md"
lacks "not defined in this bundle"

# 36h. A relative bundle path sees the same siblings as an absolute one.
cite Ready 'Widgets follow the bootstrap D-45 severity model.'
rc=0
out=$(cd "$root" && "$validator" fixture 2>&1) || rc=$?
[ "$rc" -eq 0 ] || fail "validating by relative path failed: $out"
has "0 error(s), 0 warning(s)"
rm -rf "$root/bootstrap"

# 36i. The cited-but-empty rule reads a CRLF bullet the same as an LF one.
write_bundle "$root/fixture" Ready
edit "$root/fixture/requirements.md" \
  's/^- \*\*REQ-X1.2\*\* The gadget SHALL exist\.$/- **REQ-X1.2** *(Cites: D-1.)*/'
edit "$root/fixture/requirements.md" '/^- \*\*REQ-X1.2\*\*/{n;d;}'
awk '{ printf "%s\r\n", $0 }' "$root/fixture/requirements.md" >"$root/fixture/requirements.md.new"
mv "$root/fixture/requirements.md.new" "$root/fixture/requirements.md"
run_v 1 "$root/fixture"
has "REQ-X1.2 has no normative prose"

# 36j. The citation annotation is stripped as a bounded span: prose after it,
# and an emphasized parenthetical after it, are still prose.
write_bundle "$root/fixture" Ready
edit "$root/fixture/requirements.md" \
  's/^- \*\*REQ-X1.2\*\* The gadget SHALL exist\.$/- **REQ-X1.2** *(Cites: D-1.)* The gadget SHALL exist *(emphasis added)*./'
edit "$root/fixture/requirements.md" '/^- \*\*REQ-X1.2\*\*/{n;d;}'
run_v 0 "$root/fixture"
has "0 error(s), 0 warning(s)"

# 36k. Dead-path: the same bounded strip keeps an edit after the annotation
# visible; a heading naming two REQs covers both; a superseded REQ that keeps
# an unchanged entry is exempt; a duplicate id warns once; an unbalanced
# baseline fence is named rather than silently disabling the check.
dp2="$tmp/deadpath2"
rm -rf "$dp2"
mkdir -p "$dp2"
git -C "$dp2" init -q
write_bundle "$dp2/specs/myspec" Active
edit "$dp2/specs/myspec/requirements.md" \
  's/^- \*\*REQ-X1.2\*\* The gadget SHALL exist\.$/- **REQ-X1.2** *(Cites: D-1.)* The gadget SHALL exist *(emphasis added)*./'
edit "$dp2/specs/myspec/requirements.md" '/^- \*\*REQ-X1.2\*\*/{n;d;}'
edit "$dp2/specs/myspec/test-spec.md" \
  's/^### REQ-X1.2 — gadget exists \[manual\]$/### REQ-X1.1 and REQ-X1.2 — both exist [manual]/'
edit "$dp2/specs/myspec/test-spec.md" '/^### REQ-X1.1 — widget exists \[test\]$/,/^$/d'
git -C "$dp2" add -A
git -C "$dp2" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm fixture
run_v 0 --baseline HEAD "$dp2/specs"
has "0 error(s), 0 warning(s)"

edit "$dp2/specs/myspec/requirements.md" 's/The gadget SHALL exist \*(emphasis added)\*\./The gadget SHALL hum *(emphasis added)*./'
run_v 0 --baseline HEAD "$dp2/specs"
has "REQ-X1.2 changed since HEAD"

git -C "$dp2" checkout -q -- specs
edit "$dp2/specs/myspec/requirements.md" \
  's/^- \*\*REQ-X1.1\*\* The widget SHALL exist\.$/- **REQ-X1.1** The widget SHALL exist and glow./'
run_v 0 --baseline HEAD "$dp2/specs"
has "REQ-X1.1 changed since HEAD"

git -C "$dp2" checkout -q -- specs
edit "$dp2/specs/myspec/requirements.md" \
  's/^- \*\*REQ-X1.1\*\* The widget SHALL exist\.$/- **REQ-X1.1** The widget SHALL exist. **Superseded-by: REQ-X1.2** (2026-06-13)/'
edit "$dp2/specs/myspec/requirements.md" \
  's/^- 2026-06-12 — created\.$/&\
- 2026-06-13 — REQ-X1.1 superseded by REQ-X1.2./'
run_v 0 --baseline HEAD "$dp2/specs"
lacks "REQ-X1.1 changed"

git -C "$dp2" checkout -q -- specs
edit "$dp2/specs/myspec/requirements.md" \
  's/^- \*\*REQ-X1.1\*\* The widget SHALL exist\.$/- **REQ-X1.1** The widget SHALL exist and glow.\
  *(Cites: D-1.)*\
- **REQ-X1.1** The widget SHALL exist and glow./'
run_v 1 --baseline HEAD "$dp2/specs"
n=$(printf '%s\n' "$out" | grep -c 'REQ-X1.1 changed since HEAD') || n=0
[ "$n" -eq 1 ] || fail "duplicate id produced $n dead-path warnings: $out"

git -C "$dp2" checkout -q -- specs
edit "$dp2/specs/myspec/test-spec.md" 's/^Coverage is a fixture mix\.$/&\
\
```markdown/'
git -C "$dp2" add -A
git -C "$dp2" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm unbalanced
edit "$dp2/specs/myspec/test-spec.md" '/^```markdown$/d'
edit "$dp2/specs/myspec/requirements.md" \
  's/^- \*\*REQ-X1.1\*\* The widget SHALL exist\.$/- **REQ-X1.1** The widget SHALL exist and glow./'
run_v 1 --baseline HEAD "$dp2/specs"
has "unclosed column-0 code fence in the HEAD baseline"
has "REQ-X1.1 changed since HEAD"

# 36l. The colon-less H3 decision heading errors on Ready like its siblings.
write_bundle "$root/fixture" Ready
cat >>"$root/fixture/design.md" <<'EOF'

### D-2 Missing colon

**Decision:** orphan that must be surfaced.
EOF
run_v 1 "$root/fixture"
has "ERROR"
has "malformed decision heading"

# 36m. Deviant dotted task headings are flagged on the trip side too.
deviant Draft '### Task 1.5 - Hyphen with a dotted id'
run_v 0 "$root/fixture"
has "non-canonical task heading"
deviant Draft '### Task 1.5'
run_v 0 "$root/fixture"
has "non-canonical task heading"

# --- usage errors ---
run_v 2
run_v 2 "$tmp/does-not-exist"

echo "PASS: test-spec-validate"
