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
# either; malformed emphasis is markdown lint's beat, not the parser's.
write_bundle_v2 "$root/fixture" Ready
park "$root/fixture" "Awaiting input" "- **Task 2 unterminated bold"
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

# --- usage errors ---
run_v 2
run_v 2 "$tmp/does-not-exist"

echo "PASS: test-spec-validate"
