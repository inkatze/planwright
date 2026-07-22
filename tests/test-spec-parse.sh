#!/bin/sh
# test-spec-parse.sh — unit tests for scripts/spec-parse.sh, the shared
# spec-parse grammar library (format-grammar Task 1; REQ-B1.1, REQ-B1.2,
# REQ-B1.6 · D-3, D-4).
#
# Properties verified:
#   1. The lib sources cleanly under POSIX sh and exposes the
#      spec_parse_extract_tasks entry point (REQ-B1.1).
#   2. The extraction emits the canonical definition-content stream: task
#      heading plus the five definition field bullets with continuation
#      lines, records sorted numerically by task id, annotations and
#      non-task content excluded — pinned by a hand-written golden stream
#      (REQ-B1.2).
#   3. Zero task blocks emit an empty stream with a zero exit.
#   4. Failure modes fail closed with a non-zero exit, a clear stderr
#      message, and no partial stream on stdout: duplicate task ids,
#      NUL-bearing input (REQ-B1.6d), a missing or unreadable file.
#   5. Consumers fail closed when the lib is missing or syntax-erroring
#      (REQ-B1.6a): scripts/spec-anchor.sh and
#      scripts/migrate-format-version.sh refuse to run rather than fall
#      back to a private copy, and no anchor reaches stdout.
#
# POSIX sh (matching the sourced lib's `# shellcheck shell=sh`); the `test`
# mise task also runs every tests/*.sh under /bin/bash, the bash 3.2 floor.
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
lib="$here/../scripts/spec-parse.sh"
scripts_dir="$here/../scripts"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

# ---------------------------------------------------------------------------
# Property 1: the lib exists, sources cleanly, and exposes the entry point.
# ---------------------------------------------------------------------------
[ -f "$lib" ] || fail "scripts/spec-parse.sh missing (the shared grammar lib, REQ-B1.1)"
[ -r "$lib" ] || fail "scripts/spec-parse.sh unreadable"
# shellcheck source=scripts/spec-parse.sh
. "$lib" || fail "sourcing scripts/spec-parse.sh failed"
command -v spec_parse_extract_tasks >/dev/null 2>&1 \
  || fail "spec_parse_extract_tasks entry point missing after sourcing"
echo "ok: lib sources cleanly and exposes spec_parse_extract_tasks"

# ---------------------------------------------------------------------------
# Property 2: golden extraction stream. Fixture exercises: numeric id
# sorting (1 < 2 < 2.5 < 10, document order shuffled), a wrapped
# continuation line, all three known annotation bullets plus an unknown
# one (excluded, with continuations), intro prose, section headings,
# a non-task H3 whose definition-like bullet must not leak, and a
# Deferred bullet (all excluded).
# ---------------------------------------------------------------------------
cat >"$tmp/tasks.md" <<'EOF'
# Fixture — Tasks

**Status:** Active

Intro prose that is not task-definition content.

## In progress

### Task 10 — Tenth thing

- **Deliverables:** A doohickey.
- **Done when:** The doohickey exists.
- **Dependencies:** 2.5
- **Citations:** D-4 · REQ-X1.4
- **Estimated effort:** 1 day
- **Status:** implementing
- **Last activity:** 2026-07-22
- **Dispatch:** backend=tmux · window=`fixture` · dispatched 2026-07-22T00:00Z ·
  branch `planwright/fixture/task-10` · worktree `.claude/worktrees/task-10`

## Forward plan

### Task 2.5 — Inserted thing

- **Deliverables:** A gizmo.
- **Done when:** The gizmo exists.
- **Dependencies:** 2
- **Citations:** D-3 · REQ-X1.3
- **Estimated effort:** half day
- **Reviewed-by:** an annotation kind this version does not know, with a
  continuation line that must stay excluded too.

### Task 2 — Second thing

- **Deliverables:** A gadget.
- **Done when:** The gadget exists.
- **Dependencies:** 1
- **Citations:** D-2 · REQ-X1.2
- **Estimated effort:** 1 day

### Notes

- **Done when:** sneaky bullet under a non-task H3; must not join a record

## Completed

### Task 1 — First thing

- **Deliverables:** A widget; plus a wrapped deliverable line that
  continues onto a second line.
- **Done when:** The widget exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-X1.1
- **Estimated effort:** half day
- **Status:** merged in PR #7

## Deferred

- **A deferral bullet.** Not task-definition content. **Gate:** never.
EOF

cat >"$tmp/golden" <<'EOF'
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

spec_parse_extract_tasks "$tmp/tasks.md" >"$tmp/out" \
  || fail "extraction failed on the golden fixture"
cmp -s "$tmp/golden" "$tmp/out" \
  || fail "extraction deviates from the golden stream: $(diff "$tmp/golden" "$tmp/out" | head -5)"
echo "ok: extraction matches the golden definition-content stream (REQ-B1.2)"

# Determinism: same bytes on recomputation.
spec_parse_extract_tasks "$tmp/tasks.md" >"$tmp/out2"
cmp -s "$tmp/out" "$tmp/out2" || fail "extraction is non-deterministic"
echo "ok: extraction is deterministic"

# ---------------------------------------------------------------------------
# Property 3: zero task blocks emit an empty stream, exit 0.
# ---------------------------------------------------------------------------
cat >"$tmp/zero.md" <<'EOF'
# Fixture — Tasks

**Status:** Active

## Forward plan

(none yet)
EOF
spec_parse_extract_tasks "$tmp/zero.md" >"$tmp/zero.out" \
  || fail "extraction failed on a zero-task file"
[ ! -s "$tmp/zero.out" ] || fail "zero-task extraction emitted content"
echo "ok: zero task blocks emit an empty stream"

# ---------------------------------------------------------------------------
# Property 4a: duplicate task ids fail closed — non-zero exit, a clear
# message, and NO partial stream on stdout (a truncated stream consumed as
# complete is the named fail-open, REQ-B1.6f).
# ---------------------------------------------------------------------------
cat >"$tmp/dup.md" <<'EOF'
## Forward plan

### Task 2 — Second thing

- **Done when:** The gadget exists.

### Task 2 — Second thing again

- **Done when:** Never; this input is invalid.
EOF
if err=$(spec_parse_extract_tasks "$tmp/dup.md" 2>&1 >"$tmp/dup.out"); then
  fail "duplicate task id did not fail"
fi
case $err in
  *"duplicate task id"*) ;;
  *) fail "duplicate-id failure lacks a clear message: $err" ;;
esac
[ ! -s "$tmp/dup.out" ] || fail "duplicate-id failure emitted a partial stream"
echo "ok: duplicate task ids fail closed with no partial stream"

# ---------------------------------------------------------------------------
# Property 4b: NUL-bearing input is malformed and fails closed (REQ-B1.6d,
# generalizing the drain-gates.sh screen — awk truncates records at NUL,
# which would silently hide definition lines from the stream).
# ---------------------------------------------------------------------------
{
  printf '### Task 1 — First thing\n'
  printf -- '- **Done when:** truncated after a NUL \000 byte hides the rest\n'
} >"$tmp/nul.md"
if err=$(spec_parse_extract_tasks "$tmp/nul.md" 2>&1 >"$tmp/nul.out"); then
  fail "NUL-bearing input did not fail"
fi
case $err in
  *NUL*) ;;
  *) fail "NUL failure lacks a clear message: $err" ;;
esac
[ ! -s "$tmp/nul.out" ] || fail "NUL failure emitted a partial stream"
echo "ok: NUL-bearing input fails closed (REQ-B1.6d)"

# ---------------------------------------------------------------------------
# Property 4c: a missing file fails closed with a clear message.
# ---------------------------------------------------------------------------
if err=$(spec_parse_extract_tasks "$tmp/no-such-file.md" 2>&1 >/dev/null); then
  fail "missing file did not fail"
fi
case $err in
  *"missing or unreadable"*) ;;
  *) fail "missing-file failure lacks a clear message: $err" ;;
esac
echo "ok: a missing file fails closed"

# Unreadable file (skipped under uid 0: root reads mode-000 files).
if [ "$(id -u)" -ne 0 ]; then
  cp "$tmp/zero.md" "$tmp/unreadable.md"
  chmod 000 "$tmp/unreadable.md"
  if err=$(spec_parse_extract_tasks "$tmp/unreadable.md" 2>&1 >/dev/null); then
    chmod 644 "$tmp/unreadable.md"
    fail "unreadable file did not fail"
  fi
  chmod 644 "$tmp/unreadable.md"
  case $err in
    *"missing or unreadable"*) ;;
    *) fail "unreadable-file failure lacks a clear message: $err" ;;
  esac
  echo "ok: an unreadable file fails closed"
fi

# ---------------------------------------------------------------------------
# Property 5: consumers fail closed when the lib cannot be sourced
# (REQ-B1.6a — a bare POSIX `.` of a missing file continuing fail-open is
# forbidden). A scripts-dir copy with the lib removed must make
# spec-anchor.sh and migrate-format-version.sh refuse with a clear
# message, emitting no anchor.
# ---------------------------------------------------------------------------
# Only the consumers under test and their own sourced/checked siblings are
# copied (not the whole scripts dir): spec-anchor.sh sources the lib;
# migrate-format-version.sh additionally sources echo-safety.sh and
# pre-checks spec-anchor.sh and orchestrate-lock.sh.
mkdir "$tmp/scripts-nolib"
for s in spec-anchor.sh migrate-format-version.sh echo-safety.sh orchestrate-lock.sh; do
  cp "$scripts_dir/$s" "$tmp/scripts-nolib/"
done

mkdir "$tmp/spec"
printf '%s\n' '# F — Requirements' '' '**Status:** Draft' >"$tmp/spec/requirements.md"
printf '%s\n' '# F — Design' >"$tmp/spec/design.md"
printf '%s\n' '# F — Test Spec' >"$tmp/spec/test-spec.md"
cp "$tmp/zero.md" "$tmp/spec/tasks.md"

# Consumers are invoked via `sh <script>` rather than direct exec: a fresh
# executable in a temp dir trips macOS Gatekeeper's first-exec assessment
# (tens of seconds of wall clock); reading it as data does not.
if out=$(sh "$tmp/scripts-nolib/spec-anchor.sh" "$tmp/spec" 2>"$tmp/anchor.err"); then
  fail "spec-anchor.sh succeeded without the lib (fail-open, REQ-B1.6a)"
fi
[ -z "$out" ] || fail "spec-anchor.sh emitted output without the lib: $out"
grep -q "spec-parse.sh" "$tmp/anchor.err" \
  || fail "spec-anchor.sh missing-lib refusal does not name the lib: $(cat "$tmp/anchor.err")"
echo "ok: spec-anchor.sh fails closed when the lib is missing (REQ-B1.6a)"

if sh "$tmp/scripts-nolib/migrate-format-version.sh" "$tmp/spec" >/dev/null 2>"$tmp/migrate.err"; then
  fail "migrate-format-version.sh succeeded without the lib (fail-open, REQ-B1.6a)"
fi
grep -q "spec-parse.sh" "$tmp/migrate.err" \
  || fail "migrate-format-version.sh missing-lib refusal does not name the lib: $(cat "$tmp/migrate.err")"
echo "ok: migrate-format-version.sh fails closed when the lib is missing (REQ-B1.6a)"

# A syntax-erroring lib copy must also refuse (either the guard fires or
# the sourcing shell aborts — both are fail-closed, non-zero, no anchor).
mkdir "$tmp/scripts-badlib"
cp "$scripts_dir/spec-anchor.sh" "$tmp/scripts-badlib/"
printf '%s\n' 'if then fi (((' >"$tmp/scripts-badlib/spec-parse.sh"
if out=$(sh "$tmp/scripts-badlib/spec-anchor.sh" "$tmp/spec" 2>/dev/null); then
  fail "spec-anchor.sh succeeded with a syntax-erroring lib (fail-open, REQ-B1.6a)"
fi
[ -z "$out" ] || fail "spec-anchor.sh emitted output with a syntax-erroring lib: $out"
echo "ok: spec-anchor.sh fails closed on a syntax-erroring lib (REQ-B1.6a)"

echo "PASS: test-spec-parse.sh"
