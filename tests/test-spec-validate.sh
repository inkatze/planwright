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
#       mirrors across the four files are checked.
#   5.  Format-version keying: missing version is a gap; an undeclared
#       (unsupported) version is a clear error, never silently re-keyed.
#   6.  REQ convention: prose-only bullets flagged; citation per live REQ
#       (superseded records exempt); duplicate REQ-IDs rejected.
#   7.  D-ID structure: Decision / Alternatives considered / Chosen because
#       all required; duplicate D-IDs rejected.
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
#       --check-id validates proposed identifier strings full-string.
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
write_bundle "$root/fixture" Draft
edit "$root/fixture/requirements.md" '/^\*\*Format-version:\*\*/d'
run_v 0 "$root/fixture"
has "WARN"
has "Format-version"

write_bundle "$root/fixture" Draft
edit "$root/fixture/requirements.md" \
  's/^\*\*Format-version:\*\* 1$/**Format-version:** 2/'
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

# --- 8. Task structure ---
# Missing definition fields are flagged per field.
write_bundle "$root/fixture" Draft
edit "$root/fixture/tasks.md" '/^- \*\*Citations:\*\*/d'
edit "$root/fixture/tasks.md" '/^- \*\*Estimated effort:\*\*/d'
run_v 0 "$root/fixture"
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

# --- usage errors ---
run_v 2
run_v 2 "$tmp/does-not-exist"

echo "PASS: test-spec-validate"
