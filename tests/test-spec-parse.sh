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

- **Deliverables:** A gadget, described further on a tab-indented
	continuation line that must be kept byte-for-byte.
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
- **Deliverables:** A gadget, described further on a tab-indented
	continuation line that must be kept byte-for-byte.
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

# A relative path with a valid identifier before an `=` must be read as a
# file, not swallowed by awk's operand-as-variable-assignment parsing —
# that misparse made awk read stdin and emit an empty stream with exit 0,
# the named fail-open (REQ-B1.6f). The lib feeds awk via redirection, so
# the extraction must succeed with the file's actual content.
mkdir "$tmp/eq"
printf '### Task 1 — Equals-bearing name\n\n- **Done when:** parsed as a file.\n' >"$tmp/eq/x=1.md"
eq_out=$(cd "$tmp/eq" && spec_parse_extract_tasks "x=1.md" </dev/null) \
  || fail "extraction failed on an =-bearing filename"
[ -n "$eq_out" ] || fail "=-bearing filename emitted an empty stream (awk assignment misparse fail-open)"
case $eq_out in
  *"Equals-bearing name"*) ;;
  *) fail "=-bearing filename extraction lost the task content: $eq_out" ;;
esac
echo "ok: an =-bearing filename is read as a file, not an awk assignment"

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

# Two distinct ids that collide onto one sort key are refused the same way
# (documented id-grammar bound: the key reads at most two numeric
# components, so a third component like 2.5.1 collides with 2.5).
cat >"$tmp/dup-key.md" <<'EOF'
## Forward plan

### Task 2.5 — Two-component id

- **Done when:** The gizmo exists.

### Task 2.5.1 — Colliding three-component id

- **Done when:** Never; the id grammar has no third component.
EOF
if err=$(spec_parse_extract_tasks "$tmp/dup-key.md" 2>&1 >"$tmp/dup-key.out"); then
  fail "colliding sort keys (2.5 vs 2.5.1) did not fail"
fi
case $err in
  *"duplicate task id"*) ;;
  *) fail "sort-key collision lacks the duplicate-id message: $err" ;;
esac
[ ! -s "$tmp/dup-key.out" ] || fail "sort-key collision emitted a partial stream"
echo "ok: ids colliding onto one sort key are refused as duplicates (id-grammar bound)"

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
# Property 4b2: the NUL screen fails CLOSED when its own tooling fails
# (REQ-B1.6d). A failing `wc` must not silently skip the screen and let awk
# parse a NUL-truncated stream with exit 0 — verified by stubbing wc as a
# shell function (function lookup precedes PATH in the lib's command
# substitutions, same shell).
# ---------------------------------------------------------------------------
if out=$(
  wc() { return 1; }
  spec_parse_extract_tasks "$tmp/nul.md" 2>/dev/null
); then
  fail "NUL screen fell open when wc failed (REQ-B1.6d fail-closed)"
fi
[ -z "$out" ] || fail "NUL-screen tool failure emitted a stream: $out"
echo "ok: NUL screen fails closed when its tooling fails (REQ-B1.6d)"

# Same property for the tr side. A failing tr is NOT caught by its `||`
# (the pipeline's exit status is wc's): it shortens the kept count instead,
# so the screen must refuse via the count mismatch — still fail-closed,
# with no stream on stdout.
if out=$(
  tr() { return 1; }
  spec_parse_extract_tasks "$tmp/nul.md" 2>/dev/null
); then
  fail "NUL screen fell open when tr failed (REQ-B1.6d fail-closed)"
fi
[ -z "$out" ] || fail "NUL-screen tr failure emitted a stream: $out"
echo "ok: NUL screen fails closed when tr fails (REQ-B1.6d)"

# ---------------------------------------------------------------------------
# Property 4b3: lib stderr diagnostics sanitize the echoed path (REQ-B1.6c).
# A hostile directory name carrying ESC/BEL bytes must not reach stderr raw
# (spec-anchor does not capture lib stderr; raw bytes would drive the
# operator's terminal).
# ---------------------------------------------------------------------------
evil_dir="$tmp/$(printf 'evil\033]0;owned\007dir')"
mkdir "$evil_dir"
cp "$tmp/nul.md" "$evil_dir/tasks.md"
if spec_parse_extract_tasks "$evil_dir/tasks.md" >/dev/null 2>"$tmp/esc.err"; then
  fail "NUL-bearing file in hostile dir did not fail"
fi
if LC_ALL=C grep -q "$(printf '\033')" "$tmp/esc.err" \
  || LC_ALL=C grep -q "$(printf '\007')" "$tmp/esc.err"; then
  fail "raw ESC/BEL bytes reached stderr through the path echo (REQ-B1.6c): $(od -c "$tmp/esc.err" | head -2)"
fi
grep -q "NUL byte" "$tmp/esc.err" || fail "hostile-path NUL failure lacks the NUL message"
echo "ok: lib stderr sanitizes hostile path bytes (REQ-B1.6c)"

# ---------------------------------------------------------------------------
# Property 4a2: the duplicate-id diagnostic sanitizes the echoed id
# (REQ-B1.6c). Two headings whose ids collide numerically, the second
# carrying an ESC byte inside the id token.
# ---------------------------------------------------------------------------
{
  printf '### Task 2 — First\n\n- **Done when:** a\n\n'
  printf '### Task 2\033x — Hostile duplicate\n\n- **Done when:** b\n'
} >"$tmp/dup-esc.md"
if spec_parse_extract_tasks "$tmp/dup-esc.md" >/dev/null 2>"$tmp/dup-esc.err"; then
  fail "escape-byte duplicate id did not fail"
fi
grep -q "duplicate task id" "$tmp/dup-esc.err" \
  || fail "escape-byte duplicate lacks the duplicate-id message: $(cat "$tmp/dup-esc.err")"
# The sanitizer must strip ONLY the hostile byte: the id's printable bytes
# survive, so an over-stripping regression (deleting the whole id) fails.
grep -q "duplicate task id 2x" "$tmp/dup-esc.err" \
  || fail "sanitized duplicate id lost its printable bytes: $(cat "$tmp/dup-esc.err")"
if LC_ALL=C grep -q "$(printf '\033')" "$tmp/dup-esc.err"; then
  fail "raw ESC byte reached stderr through the duplicate-id echo (REQ-B1.6c)"
fi
echo "ok: duplicate-id diagnostic sanitizes hostile id bytes (REQ-B1.6c)"

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
# the sourcing shell aborts — both are fail-closed, non-zero, no anchor)
# and must say *something* on stderr (a silent refusal is undiagnosable).
mkdir "$tmp/scripts-badlib"
cp "$scripts_dir/spec-anchor.sh" "$scripts_dir/migrate-format-version.sh" \
  "$scripts_dir/echo-safety.sh" "$scripts_dir/orchestrate-lock.sh" \
  "$tmp/scripts-badlib/"
printf '%s\n' 'if then fi (((' >"$tmp/scripts-badlib/spec-parse.sh"
if out=$(sh "$tmp/scripts-badlib/spec-anchor.sh" "$tmp/spec" 2>"$tmp/badlib.err"); then
  fail "spec-anchor.sh succeeded with a syntax-erroring lib (fail-open, REQ-B1.6a)"
fi
[ -z "$out" ] || fail "spec-anchor.sh emitted output with a syntax-erroring lib: $out"
[ -s "$tmp/badlib.err" ] || fail "spec-anchor.sh refused the syntax-erroring lib silently"
echo "ok: spec-anchor.sh fails closed on a syntax-erroring lib (REQ-B1.6a)"

if sh "$tmp/scripts-badlib/migrate-format-version.sh" "$tmp/spec" >/dev/null 2>"$tmp/badlib-m.err"; then
  fail "migrate-format-version.sh succeeded with a syntax-erroring lib (fail-open, REQ-B1.6a)"
fi
[ -s "$tmp/badlib-m.err" ] || fail "migrate-format-version.sh refused the syntax-erroring lib silently"
echo "ok: migrate-format-version.sh fails closed on a syntax-erroring lib (REQ-B1.6a)"

# An unreadable lib must trip the guards' [ -r ] branch in both consumers
# (skipped under uid 0: root reads mode-000 files).
if [ "$(id -u)" -ne 0 ]; then
  mkdir "$tmp/scripts-noread"
  cp "$scripts_dir/spec-anchor.sh" "$scripts_dir/migrate-format-version.sh" \
    "$scripts_dir/echo-safety.sh" "$scripts_dir/orchestrate-lock.sh" \
    "$scripts_dir/spec-parse.sh" "$tmp/scripts-noread/"
  chmod 000 "$tmp/scripts-noread/spec-parse.sh"
  if out=$(sh "$tmp/scripts-noread/spec-anchor.sh" "$tmp/spec" 2>"$tmp/noread.err"); then
    fail "spec-anchor.sh succeeded with an unreadable lib (fail-open, REQ-B1.6a)"
  fi
  [ -z "$out" ] || fail "spec-anchor.sh emitted output with an unreadable lib: $out"
  grep -q "spec-parse.sh" "$tmp/noread.err" \
    || fail "spec-anchor.sh unreadable-lib refusal does not name the lib: $(cat "$tmp/noread.err")"
  if sh "$tmp/scripts-noread/migrate-format-version.sh" "$tmp/spec" >/dev/null 2>"$tmp/noread-m.err"; then
    fail "migrate-format-version.sh succeeded with an unreadable lib (fail-open, REQ-B1.6a)"
  fi
  grep -q "spec-parse.sh" "$tmp/noread-m.err" \
    || fail "migrate-format-version.sh unreadable-lib refusal does not name the lib: $(cat "$tmp/noread-m.err")"
  chmod 644 "$tmp/scripts-noread/spec-parse.sh"
  echo "ok: both consumers fail closed on an unreadable lib (REQ-B1.6a)"
fi

echo "PASS: test-spec-parse.sh"
