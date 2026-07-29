#!/bin/sh
# test-spec-parse.sh — unit tests for scripts/spec-parse.sh, the shared
# spec-parse grammar library (format-grammar Tasks 1 and 2; REQ-B1.1,
# REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.6, REQ-C1.1 · D-3, D-4, D-5, D-6,
# D-7, D-8).
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
#   6. spec_parse_header_value implements the header-block-scoped
#      declaration parse (REQ-B1.3, REQ-A1.3, D-7): a declaration inside the
#      leading header block is parsed, a column-0 body literal is inert (so
#      it can no longer mask a MISSING declaration), CRLF and hard-break
#      whitespace are trimmed, and a DUPLICATE in-header `Format-version:`
#      or `Status:` declaration fails closed (REQ-A1.2, REQ-D1.9, D-6) while
#      a non-load-bearing key keeps first-match-wins. Its batched sibling
#      spec_parse_header_block (D-3) agrees with it byte for byte on every
#      fixture, and a duplicated load-bearing key emits ONLY the `hdrdup`
#      record — never a positional-winner value a consumer could read.
#   7. spec_parse_parked_map implements the parked-map/reference-bullet parse
#      in the single v2 posture (REQ-B1.4, REQ-C1.1, D-8): column-0 fences
#      are illustration (doctrine/spec-format.md, *Fenced illustration*),
#      section headings are matched CRLF-tolerantly,
#      a reference is a complete `**Task <token>**` lead with a
#      whitespace-free token, plain prose bullets are tolerated, near-miss
#      leads are rejected loudly, and end-of-file inside an open fence is
#      malformed input that fails closed with no partial stream.
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
# Property 2b: the lib's working variables stay in the spec_parse__
# namespace. POSIX sh has no locals, so a sourced lib's assignments land in
# the sourcing consumer's global scope: generic names would silently
# clobber consumer state on every call. Sentinels are checked after both a
# success path and an error path (the error path is what exercises
# spec_parse__printable), called directly — not inside a command
# substitution, whose subshell would hide the clobber.
# ---------------------------------------------------------------------------
sp_total='caller-total'
sp_kept='caller-kept'
sp_p='caller-p'
spec_parse_extract_tasks "$tmp/tasks.md" >/dev/null \
  || fail "extraction failed during the namespace check"
if spec_parse_extract_tasks "$tmp/no-such-file.md" >/dev/null 2>&1; then
  fail "missing file unexpectedly succeeded during the namespace check"
fi
[ "$sp_total" = 'caller-total' ] || fail "lib clobbered the caller variable sp_total"
[ "$sp_kept" = 'caller-kept' ] || fail "lib clobbered the caller variable sp_kept"
[ "$sp_p" = 'caller-p' ] || fail "lib clobbered the caller variable sp_p"
unset sp_total sp_kept sp_p
echo "ok: lib working variables stay in the spec_parse__ namespace"

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

# The guard diagnostic sanitizes the echoed lib path (the REQ-B1.6c posture
# extended to the consumers' own guards): a checkout directory name carrying
# ESC/BEL bytes must not reach stderr raw, while the refusal still names
# spec-parse.sh.
evil_scripts="$tmp/$(printf 'esc\033]0;owned\007')-scripts"
mkdir "$evil_scripts"
for s in spec-anchor.sh migrate-format-version.sh echo-safety.sh orchestrate-lock.sh; do
  cp "$scripts_dir/$s" "$evil_scripts/"
done
if out=$(sh "$evil_scripts/spec-anchor.sh" "$tmp/spec" 2>"$tmp/evil-anchor.err"); then
  fail "spec-anchor.sh succeeded without the lib (hostile-dir guard)"
fi
[ -z "$out" ] || fail "spec-anchor.sh emitted output without the lib (hostile dir): $out"
if LC_ALL=C grep -q "$(printf '\033')" "$tmp/evil-anchor.err" \
  || LC_ALL=C grep -q "$(printf '\007')" "$tmp/evil-anchor.err"; then
  fail "raw ESC/BEL reached stderr through spec-anchor.sh's guard path echo: $(od -c "$tmp/evil-anchor.err" | head -2)"
fi
grep -q "spec-parse.sh" "$tmp/evil-anchor.err" \
  || fail "spec-anchor.sh sanitized guard refusal no longer names the lib: $(cat "$tmp/evil-anchor.err")"
if sh "$evil_scripts/migrate-format-version.sh" "$tmp/spec" >/dev/null 2>"$tmp/evil-migrate.err"; then
  fail "migrate-format-version.sh succeeded without the lib (hostile-dir guard)"
fi
if LC_ALL=C grep -q "$(printf '\033')" "$tmp/evil-migrate.err" \
  || LC_ALL=C grep -q "$(printf '\007')" "$tmp/evil-migrate.err"; then
  fail "raw ESC/BEL reached stderr through migrate-format-version.sh's guard path echo: $(od -c "$tmp/evil-migrate.err" | head -2)"
fi
grep -q "spec-parse.sh" "$tmp/evil-migrate.err" \
  || fail "migrate-format-version.sh sanitized guard refusal no longer names the lib: $(cat "$tmp/evil-migrate.err")"
echo "ok: both consumers sanitize the guard's echoed lib path"

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

# ---------------------------------------------------------------------------
# Property 5b: the SIX consumers the header-declaration and parked-map
# re-points added also fail closed when the lib is absent (REQ-B1.6a). Without
# this, a broken install would leave each of them calling an undefined function
# — under `set -u` without `set -e` that is the named fail-open, since an
# unchecked capture reads "command not found" as an absent declaration.
#
# tasks-pr-sync.sh is asserted separately below: it is a PostToolUse hook whose
# contract is fail-SOFT (exit 0, no write, a diagnostic), so "fail closed" there
# means no write rather than a non-zero exit.
# ---------------------------------------------------------------------------
mkdir "$tmp/scripts-nolib2"
for s in spec-status.sh orchestrate-select.sh drain-gates.sh spec-validate.sh \
  check-ledger.sh tasks-pr-sync.sh echo-safety.sh orchestrate-lock.sh \
  orchestrate-state.sh; do
  cp "$scripts_dir/$s" "$tmp/scripts-nolib2/"
done

mkdir -p "$tmp/nolib-root/corpus"
{
  printf '# C — Requirements\n\n**Status:** Ready\n**Format-version:** 2\n'
} >"$tmp/nolib-root/corpus/requirements.md"
printf '# C — Design\n\n**Status:** Ready\n**Format-version:** 2\n' >"$tmp/nolib-root/corpus/design.md"
printf '# C — Test spec\n\n**Status:** Ready\n**Format-version:** 2\n' >"$tmp/nolib-root/corpus/test-spec.md"
{
  printf '# C — Tasks\n\n**Status:** Ready\n**Format-version:** 2\n\n## Tasks\n\n'
  printf '### Task 1 — Thing\n\n'
  printf -- '- **Done when:** done.\n'
} >"$tmp/nolib-root/corpus/tasks.md"

# nolib_refuses <label> <script> [args...] — the script must exit non-zero and
# name the missing lib on stderr, with nothing usable on stdout.
nolib_refuses() {
  nr_label=$1
  shift
  if nr_out=$(sh "$@" 2>"$tmp/nolib.err"); then
    fail "$nr_label succeeded without the lib (fail-open, REQ-B1.6a)"
  fi
  [ -z "$nr_out" ] \
    || fail "$nr_label emitted output without the lib (a partial answer is the fail-open): $nr_out"
  grep -q "spec-parse.sh" "$tmp/nolib.err" \
    || fail "$nr_label missing-lib refusal does not name the lib: $(cat "$tmp/nolib.err")"
  echo "ok: $nr_label fails closed when the lib is missing (REQ-B1.6a)"
}

nolib_refuses "spec-status.sh" "$tmp/scripts-nolib2/spec-status.sh" "$tmp/nolib-root/corpus"
nolib_refuses "orchestrate-select.sh" "$tmp/scripts-nolib2/orchestrate-select.sh" "$tmp/nolib-root/corpus"
nolib_refuses "drain-gates.sh" "$tmp/scripts-nolib2/drain-gates.sh" "$tmp/nolib-root"
nolib_refuses "spec-validate.sh" "$tmp/scripts-nolib2/spec-validate.sh" "$tmp/nolib-root/corpus"
nolib_refuses "check-ledger.sh" "$tmp/scripts-nolib2/check-ledger.sh" "$tmp/nolib-root/corpus/tasks.md"

# tasks-pr-sync.sh, CLI arm: fail-closed exit 2 (the closed policy).
if sh "$tmp/scripts-nolib2/tasks-pr-sync.sh" reconcile-status "$tmp/nolib-root/corpus" \
  >/dev/null 2>"$tmp/nolib-sync.err"; then
  fail "tasks-pr-sync.sh reconcile-status succeeded without the lib (fail-open, REQ-B1.6a)"
fi
grep -q "spec-parse.sh" "$tmp/nolib-sync.err" \
  || fail "tasks-pr-sync.sh CLI missing-lib refusal does not name the lib: $(cat "$tmp/nolib-sync.err")"
echo "ok: tasks-pr-sync.sh CLI fails closed when the lib is missing (REQ-B1.6a)"

# tasks-pr-sync.sh, HOOK arm: fail-SOFT (exit 0) but writes nothing — the
# PostToolUse contract. The diagnostic still names the lib.
#
# Unlike the CLI arm above, the hook arm takes NO spec argument: it derives the
# spec id from `git rev-parse --abbrev-ref HEAD` in the ambient checkout and
# writes under that checkout's primary specs/. So it must run against a
# purpose-built fixture repo with a `planwright/<spec>/task-<n>` branch checked
# out, never against whatever branch happens to be current. Two ways the
# ambient form was wrong: on a detached HEAD (what actions/checkout leaves for
# a `pull_request` event) `--abbrev-ref` yields the literal `HEAD`, the
# convention-branch guard misses, and the hook no-ops with an empty stderr
# before ever reaching the require_spec_parse gate this pins; and where the
# branch DID match, the spec dir resolved into the real repo's specs/, so the
# no-write assertion compared a file the hook never targeted. The fixture
# mirrors make_repo / run_hook in tests/test-tasks-pr-sync.sh.
nolib_repo=$tmp/nolib-repo
mkdir -p "$nolib_repo/specs/corpus"
cp "$tmp/nolib-root/corpus/"*.md "$nolib_repo/specs/corpus/"
git -C "$nolib_repo" init -q -b main
git -C "$nolib_repo" config user.email test@example.com
git -C "$nolib_repo" config user.name test
git -C "$nolib_repo" config commit.gpgsign false
git -C "$nolib_repo" add -A
git -C "$nolib_repo" commit -qm "chore: fixture"
git -C "$nolib_repo" checkout -q -b planwright/corpus/task-1

cp "$nolib_repo/specs/corpus/tasks.md" "$tmp/nolib-pristine.md"
if ! (
  cd "$nolib_repo" \
    && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh pr create --draft"},"tool_response":{"stdout":"https://github.com/o/r/pull/1","stderr":""}}' \
    | sh "$tmp/scripts-nolib2/tasks-pr-sync.sh"
) >/dev/null 2>"$tmp/nolib-hook.err"; then
  fail "tasks-pr-sync.sh hook arm exited non-zero without the lib (the hook contract is fail-soft)"
fi
cmp -s "$tmp/nolib-pristine.md" "$nolib_repo/specs/corpus/tasks.md" \
  || fail "tasks-pr-sync.sh hook arm wrote without the lib (fail-open, REQ-B1.6a)"
# The diagnostic must name the LIB, not a downstream symptom. Without the
# explicit require_spec_parse gate the write is still refused (the version gate
# catches the undefined function further in), so the no-write assertion alone
# passes either way; this assertion is what pins the gate itself, so a broken
# install reports the real cause instead of a bogus "unparseable Format-version".
grep -q "spec-parse.sh" "$tmp/nolib-hook.err" \
  || fail "tasks-pr-sync.sh hook missing-lib diagnostic does not name the lib: $(cat "$tmp/nolib-hook.err")"
echo "ok: tasks-pr-sync.sh hook arm degrades fail-soft, writes nothing, and names the lib (REQ-B1.6a)"

# ---------------------------------------------------------------------------
# Property 6: spec_parse_header_value — the header-block-scoped declaration
# parse (REQ-B1.3; REQ-A1.2, REQ-A1.3 · D-6, D-7).
# ---------------------------------------------------------------------------
command -v spec_parse_header_value >/dev/null 2>&1 \
  || fail "spec_parse_header_value entry point missing after sourcing (REQ-B1.3)"

hv() { spec_parse_header_value "$@"; }

# 6a. Canonical header block: both load-bearing keys parse.
cat >"$tmp/hdr-ok.md" <<'EOF'
# Fixture — Requirements

**Status:** Ready
**Last reviewed:** 2026-07-24
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

Prose body.
EOF
got=$(hv "$tmp/hdr-ok.md" Format-version) || fail "header parse failed on the canonical block"
[ "$got" = 2 ] || fail "Format-version parsed as '$got', want '2'"
got=$(hv "$tmp/hdr-ok.md" Status) || fail "Status parse failed on the canonical block"
[ "$got" = Ready ] || fail "Status parsed as '$got', want 'Ready'"
echo "ok: header-block declarations parse for both load-bearing keys (REQ-B1.3)"

# 6b. A column-0 BODY literal is inert: it must not mask a MISSING header
# declaration (obs:89cf2853 — the latent bug the header scope closes).
cat >"$tmp/hdr-body-only.md" <<'EOF'
# Fixture — Tasks

**Status:** Ready

## Notes

**Format-version:** 1
EOF
got=$(hv "$tmp/hdr-body-only.md" Format-version) \
  || fail "body-literal fixture failed instead of reporting the declaration absent"
[ -z "$got" ] \
  || fail "a column-0 body **Format-version:** literal masked the missing header declaration (got '$got'; REQ-A1.3)"
echo "ok: a body-line declaration is inert and cannot mask a missing header one (REQ-A1.3)"

# The same for Status, and with a real header declaration present the body
# literal neither wins nor counts toward the duplicate rule.
cat >"$tmp/hdr-body-dup.md" <<'EOF'
# Fixture — Requirements

**Status:** Draft
**Format-version:** 2

## Body

**Status:** Done
**Format-version:** 1
EOF
got=$(hv "$tmp/hdr-body-dup.md" Status) || fail "body-literal Status fixture failed"
[ "$got" = Draft ] || fail "body Status literal changed the parsed value (got '$got')"
got=$(hv "$tmp/hdr-body-dup.md" Format-version) || fail "body-literal version fixture failed"
[ "$got" = 2 ] || fail "body version literal changed the parsed value (got '$got')"
echo "ok: body literals count toward neither the value nor the duplicate rule"

# 6c. A DUPLICATE in-header declaration is unparseable and fails closed, for
# both load-bearing keys, with nothing on stdout (REQ-A1.2, REQ-D1.9, D-6).
for key in Format-version Status; do
  {
    printf '# Fixture — Requirements\n\n'
    printf '**Status:** Ready\n'
    printf '**Format-version:** 2\n'
    printf '**%s:** 1\n\n' "$key"
    printf '## Goal\n'
  } >"$tmp/hdr-dup.md"
  if err=$(hv "$tmp/hdr-dup.md" "$key" 2>&1 >"$tmp/hdr-dup.out"); then
    fail "duplicate in-header $key: did not fail closed (REQ-A1.2)"
  fi
  [ ! -s "$tmp/hdr-dup.out" ] || fail "duplicate $key emitted a value: $(cat "$tmp/hdr-dup.out")"
  case $err in
    *duplicate*"$key"* | *"$key"*duplicate*) ;;
    *) fail "duplicate $key diagnostic does not name the key and the defect: $err" ;;
  esac
done
echo "ok: a duplicate in-header Format-version:/Status: declaration fails closed (REQ-A1.2, REQ-D1.9)"

# The other key still parses out of the same file: the fail-closed posture is
# per-declaration, not a whole-file refusal.
{
  printf '# Fixture — Requirements\n\n'
  printf '**Status:** Ready\n'
  printf '**Format-version:** 2\n'
  printf '**Format-version:** 1\n\n'
  printf '## Goal\n'
} >"$tmp/hdr-dup-fv.md"
got=$(hv "$tmp/hdr-dup-fv.md" Status) || fail "Status parse failed on a duplicate-version file"
[ "$got" = Ready ] || fail "Status parse disturbed by the duplicate version (got '$got')"
echo "ok: the fail-closed posture is scoped to the duplicated declaration"

# 6d. A non-load-bearing key keeps first-match-wins: D-6 scopes the
# fail-closed rule to the two load-bearing header keys, so a duplicate
# `Execution:` pointer line still resolves (the validator owns that finding).
cat >"$tmp/hdr-dup-other.md" <<'EOF'
# Fixture — Requirements

**Status:** Ready
**Format-version:** 2
**Execution:** derived — see the status render
**Execution:** something else

## Goal
EOF
got=$(hv "$tmp/hdr-dup-other.md" Execution) \
  || fail "a duplicate non-load-bearing key must not fail closed (D-6 scope)"
case $got in
  'derived'*) ;;
  *) fail "duplicate Execution: did not resolve first-match-wins (got '$got')" ;;
esac
echo "ok: the duplicate rule is scoped to Format-version:/Status: (D-6)"

# 6e. CRLF checkout: the value's trailing CR is trimmed AND a CR-only blank
# line does not end the header block (the defect that makes a CRLF bundle
# read as version-less).
{
  printf '# Fixture — Requirements\r\n'
  printf '\r\n'
  printf '**Status:** Ready\r\n'
  printf '**Format-version:** 2\r\n'
  printf '\r\n'
  printf '## Goal\r\n'
} >"$tmp/hdr-crlf.md"
got=$(hv "$tmp/hdr-crlf.md" Format-version) || fail "CRLF header parse failed"
[ "$got" = 2 ] || fail "CRLF Format-version parsed as '$got' (want '2'; trailing CR untrimmed?)"
got=$(hv "$tmp/hdr-crlf.md" Status) || fail "CRLF Status parse failed"
[ "$got" = Ready ] || fail "CRLF Status parsed as '$got'"
echo "ok: CRLF header blocks parse with the CR trimmed"

# A Markdown hard break (two trailing spaces) is trimmed too.
{
  printf '# Fixture — Requirements\n\n'
  printf '**Format-version:** 2  \n\n'
  printf '## Goal\n'
} >"$tmp/hdr-hardbreak.md"
got=$(hv "$tmp/hdr-hardbreak.md" Format-version) || fail "hard-break header parse failed"
[ "$got" = 2 ] || fail "hard-break Format-version parsed as '$got'"
echo "ok: trailing hard-break whitespace is trimmed"

# 6f. The header block ends at the first line that is neither blank, the H1,
# nor a bolded header line — so a declaration after prose is body content.
cat >"$tmp/hdr-after-prose.md" <<'EOF'
# Fixture — Requirements

Some prose that closes the header block.

**Format-version:** 2
EOF
got=$(hv "$tmp/hdr-after-prose.md" Format-version) || fail "post-prose fixture failed"
[ -z "$got" ] || fail "a declaration after prose was parsed as a header declaration (got '$got'; D-7)"
echo "ok: prose closes the header block (D-7)"

# A column-0 fence closes the block too, so a fenced example declaration is
# already outside every recognized block (the fence rule needs no separate
# guard here).
{
  printf '# Fixture — Requirements\n\n'
  printf '```\n'
  printf '**Format-version:** 1\n'
  printf '```\n\n'
  printf '**Format-version:** 2\n'
} >"$tmp/hdr-fenced.md"
got=$(hv "$tmp/hdr-fenced.md" Format-version) || fail "fenced-example fixture failed"
[ -z "$got" ] \
  || fail "a fenced example declaration was parsed as the header declaration (got '$got')"
echo "ok: a column-0 fence closes the header block, so fenced examples are inert"

# 6g. The H1 is optional: header-only fixtures and partial files legitimately
# open with the declarations.
printf '**Format-version:** 2\n**Status:** Ready\n\n## Tasks\n' >"$tmp/hdr-noh1.md"
got=$(hv "$tmp/hdr-noh1.md" Format-version) || fail "H1-less header parse failed"
[ "$got" = 2 ] || fail "H1-less Format-version parsed as '$got'"
echo "ok: the leading header block does not require an H1"

# 6h. Failure modes: missing file, NUL-bearing input, invalid key.
if err=$(hv "$tmp/no-such-file.md" Status 2>&1 >/dev/null); then
  fail "header parse of a missing file did not fail"
fi
case $err in
  *"missing or unreadable"*) ;;
  *) fail "missing-file header failure lacks a clear message: $err" ;;
esac
{
  printf '# F\n\n'
  printf '**Format-version:** 2\000 hidden\n'
} >"$tmp/hdr-nul.md"
if err=$(hv "$tmp/hdr-nul.md" Format-version 2>&1 >"$tmp/hdr-nul.out"); then
  fail "NUL-bearing header input did not fail closed (REQ-B1.6d)"
fi
case $err in
  *NUL*) ;;
  *) fail "NUL header failure lacks a clear message: $err" ;;
esac
[ ! -s "$tmp/hdr-nul.out" ] || fail "NUL header failure emitted a value"
if hv "$tmp/hdr-ok.md" 'Bad Key!' >/dev/null 2>&1; then
  fail "an invalid header key was accepted (identifier discipline)"
fi
echo "ok: header parse fails closed on a missing file, NUL input, and a bad key"

# 6i. `-` reads the caller's snapshot from stdin (the single-snapshot
# consumers own their own NUL screen; consumer contract clause (g)).
got=$(hv - Format-version <"$tmp/hdr-ok.md") || fail "stdin header parse failed"
[ "$got" = 2 ] || fail "stdin Format-version parsed as '$got'"
echo "ok: the header parse reads a caller snapshot from stdin"

# 6j. Namespace hygiene on both the success and the fail-closed paths.
sp_hv_key='caller-key'
sp_hv_strict='caller-strict'
hv "$tmp/hdr-ok.md" Status >/dev/null || fail "header parse failed during the namespace check"
hv "$tmp/no-such-file.md" Status >/dev/null 2>&1 || :
[ "$sp_hv_key" = 'caller-key' ] || fail "lib clobbered the caller variable sp_hv_key"
[ "$sp_hv_strict" = 'caller-strict' ] || fail "lib clobbered the caller variable sp_hv_strict"
unset sp_hv_key sp_hv_strict
echo "ok: header-parse working variables stay in the spec_parse__ namespace"

# 6k. spec_parse_header_block — the same parse, batched (D-3 batchability).
# Its records must AGREE with the single-key form byte for byte, since one awk
# program serves both; and the fail-closed duplicate posture must survive
# batching by construction (a duplicated load-bearing key emits no value at all,
# only `hdrdup`, so a forgetful consumer finds nothing to read).
command -v spec_parse_header_block >/dev/null 2>&1 \
  || fail "spec_parse_header_block entry point missing after sourcing (D-3)"

spec_parse_header_block "$tmp/hdr-ok.md" >"$tmp/hb.out" \
  || fail "batched header parse failed on the canonical block"
# Built with printf rather than a heredoc so the tab-separated expectations are
# unambiguous: one record per declaration, in file order, values raw.
{
  printf 'hdr\tStatus\tReady\n'
  printf 'hdr\tFormat-version\t2\n'
  printf 'hdr\tExecution\tderived — see the status render\n'
} >"$tmp/hb.golden"
# `Last reviewed` carries a space, so it fails the header-key grammar and emits
# no record — a malformed key cannot forge one.
grep -q 'Last reviewed' "$tmp/hb.out" \
  && fail "a space-bearing key emitted a record (header-key grammar not screened)"
cmp -s "$tmp/hb.golden" "$tmp/hb.out" \
  || fail "batched header stream deviates from the golden: $(diff "$tmp/hb.golden" "$tmp/hb.out" | head -6)"
echo "ok: the batched header parse emits one raw record per conforming declaration (D-3)"

# Agreement with the single-key form over every fixture written above.
for f in hdr-ok.md hdr-body-only.md hdr-body-dup.md hdr-crlf.md hdr-hardbreak.md \
  hdr-after-prose.md hdr-fenced.md hdr-noh1.md hdr-dup-other.md; do
  for key in Status Format-version Execution; do
    single=$(hv "$tmp/$f" "$key") || continue # exit 3 has no single-key value
    # The value is everything after the SECOND tab, computed positionally: an
    # index($0, $3) search would misfire on an empty value (index returns 0) or
    # on one whose bytes also appear in the key.
    batched=$(spec_parse_header_block "$tmp/$f" \
      | awk -v k="$key" '
          {
            p = index($0, "\t")
            q = index(substr($0, p + 1), "\t")
            if (substr($0, 1, p - 1) != "hdr") next
            if (substr($0, p + 1, q - 1) != k) next
            print substr($0, p + q + 1)
            exit
          }')
    [ "$single" = "$batched" ] \
      || fail "batched and single-key forms disagree on $key in $f: single [$single] vs batched [$batched]"
  done
done
echo "ok: the batched and single-key header forms agree on every fixture"

# A duplicated load-bearing key emits ONLY hdrdup — no value to fall open on.
spec_parse_header_block "$tmp/hdr-dup-fv.md" >"$tmp/hb-dup.out" \
  || fail "batched header parse failed on the duplicate-version fixture"
grep -q '^hdrdup	Format-version	2$' "$tmp/hb-dup.out" \
  || fail "a duplicated Format-version: emitted no hdrdup record: $(cat "$tmp/hb-dup.out")"
awk -F'\t' '$1 == "hdr" && $2 == "Format-version" { found = 1 } END { exit !found }' "$tmp/hb-dup.out" \
  && fail "a duplicated Format-version: still emitted a positional-winner value (fail-open)"
grep -q '^hdr	Status	Ready$' "$tmp/hb-dup.out" \
  || fail "the duplicate refusal swallowed the sibling Status: declaration"
echo "ok: a duplicated load-bearing key emits only hdrdup, never a positional winner"

# A duplicated NON-load-bearing key keeps first-match-wins (D-6 scope).
spec_parse_header_block "$tmp/hdr-dup-other.md" >"$tmp/hb-other.out" \
  || fail "batched header parse failed on the duplicate-Execution fixture"
refute_hdrdup=$(awk -F'\t' '$1 == "hdrdup" { print $2 }' "$tmp/hb-other.out")
[ -z "$refute_hdrdup" ] \
  || fail "a duplicated non-load-bearing key emitted hdrdup: $refute_hdrdup (D-6 scopes the rule)"
echo "ok: the batched form scopes the duplicate rule to the load-bearing keys (D-6)"

# Failure modes and the stdin form.
if err=$(spec_parse_header_block "$tmp/hdr-nul.md" 2>&1 >"$tmp/hb-nul.out"); then
  fail "NUL-bearing batched input did not fail closed (REQ-B1.6d)"
fi
case $err in
  *NUL*) ;;
  *) fail "batched NUL failure lacks a clear message: $err" ;;
esac
[ ! -s "$tmp/hb-nul.out" ] || fail "batched NUL failure emitted records"
spec_parse_header_block - <"$tmp/hdr-ok.md" >"$tmp/hb-stdin.out" \
  || fail "batched header parse failed on stdin"
cmp -s "$tmp/hb.golden" "$tmp/hb-stdin.out" \
  || fail "batched stdin stream differs from the file parse"
echo "ok: the batched header parse fails closed on NUL input and reads stdin"

# ---------------------------------------------------------------------------
# Property 7: spec_parse_parked_map — the parked-map/reference-bullet parse
# in the single v2 posture (REQ-B1.4, REQ-C1.1 · D-8, and the meta-spec's
# *Fenced illustration* rule).
#
# Record framing (fixed-position fields, variable-length payload last):
#   ref<TAB><id><TAB><class><TAB><line><TAB><payload>
#   refbad<TAB><raw-token><TAB><class><TAB><line>
# ---------------------------------------------------------------------------
command -v spec_parse_parked_map >/dev/null 2>&1 \
  || fail "spec_parse_parked_map entry point missing after sourcing (REQ-B1.4)"

# 7a. The posture corpus, one fixture exercising every rule at once.
cat >"$tmp/parked.md" <<'EOF'
# Fixture — Tasks

**Format-version:** 2

## Tasks

### Task 1 — A thing

- **Deliverables:** stuff.

## Awaiting input

- **Task 1** Blocked on a human decision.
- **Task 2** Blocked too.

## Deferred

- **Task force assembled.** Plain prose the format allows here.
- A plain bullet with no bold lead at all.
- **Task 3** Deferred with a reason.
- **Task 3** A second bullet naming the same task.

## Out of scope

- **Task abc** A token that violates the task-id grammar.
- **Task 4 ** A near-miss: the trimmed remainder is a valid id.
- **Task 4 5** A near-miss: only digits, dots, and whitespace.
- **Task 5 Unterminated bold lead
- **Task 6** Out of scope for a reason.
EOF
cat >"$tmp/parked.golden" <<'EOF'
ref	1	awaiting-input	13	Blocked on a human decision.
ref	2	awaiting-input	14	Blocked too.
ref	3	deferred	20	Deferred with a reason.
ref	3	deferred	21	A second bullet naming the same task.
refbad	abc	out-of-scope	25
refbad	4 	out-of-scope	26
refbad	4 5	out-of-scope	27
ref	6	out-of-scope	29	Out of scope for a reason.
EOF
spec_parse_parked_map "$tmp/parked.md" >"$tmp/parked.out" \
  || fail "parked-map parse failed on the posture corpus"
cmp -s "$tmp/parked.golden" "$tmp/parked.out" \
  || fail "parked-map stream deviates from the golden posture stream: $(diff "$tmp/parked.golden" "$tmp/parked.out" | head -12)"
echo "ok: the parked-map stream matches the golden posture corpus (REQ-B1.4, REQ-C1.1)"

# Every duplicate reference bullet is emitted (the validator needs both to
# report a task parked twice); de-duplication is the consumer's choice.
[ "$(awk -F'\t' '$1 == "ref" && $2 == "3"' "$tmp/parked.out" | wc -l | tr -d ' ')" = 2 ] \
  || fail "the parked map de-duplicated a task named by two reference bullets"
echo "ok: duplicate reference bullets are both emitted, not de-duplicated"

# 7b. Column-0 fences are illustration (meta-spec *Fenced illustration*):
# neither a fenced section
# heading nor a fenced reference bullet parses as anything.
cat >"$tmp/parked-fence.md" <<'EOF'
# Fixture — Tasks

**Format-version:** 2

## Deferred

- **Task 1** A real park.

## Notes

```
## Awaiting input

- **Task 9** A fenced mock park that must parse as illustration.
```

Prose after the fence.
EOF
spec_parse_parked_map "$tmp/parked-fence.md" >"$tmp/parked-fence.out" \
  || fail "parked-map parse failed on the fence fixture"
printf 'ref\t1\tdeferred\t7\tA real park.\n' >"$tmp/parked-fence.golden"
cmp -s "$tmp/parked-fence.golden" "$tmp/parked-fence.out" \
  || fail "fenced lines leaked into the parked map: $(cat "$tmp/parked-fence.out")"
echo "ok: fenced section headings and reference bullets parse as illustration"

# An INDENTED fence does not toggle illustration mode (only column-0 does).
cat >"$tmp/parked-indented-fence.md" <<'EOF'
# Fixture — Tasks

## Awaiting input

  ```
- **Task 1** Still a real park: the fence above is indented.
EOF
spec_parse_parked_map "$tmp/parked-indented-fence.md" >"$tmp/pif.out" \
  || fail "parked-map parse failed on the indented-fence fixture"
grep -q "^ref	1	awaiting-input" "$tmp/pif.out" \
  || fail "an indented fence toggled illustration mode: $(cat "$tmp/pif.out")"
echo "ok: only column-0 fences toggle illustration mode"

# 7c. CRLF checkout: a payload-section heading and its reference bullet are
# still recognized — the defect that let a live Awaiting-input bullet stop
# blocking derived Done (REQ-C1.3).
{
  printf '# Fixture — Tasks\r\n\r\n'
  printf '## Awaiting input\r\n\r\n'
  printf -- '- **Task 1** Blocked on a human decision.\r\n'
} >"$tmp/parked-crlf.md"
spec_parse_parked_map "$tmp/parked-crlf.md" >"$tmp/parked-crlf.out" \
  || fail "parked-map parse failed on the CRLF fixture"
printf 'ref\t1\tawaiting-input\t5\tBlocked on a human decision.\n' >"$tmp/parked-crlf.golden"
cmp -s "$tmp/parked-crlf.golden" "$tmp/parked-crlf.out" \
  || fail "a CRLF checkout lost the Awaiting-input park: $(cat "$tmp/parked-crlf.out")"
echo "ok: CRLF payload sections and reference bullets are recognized (REQ-C1.3)"

# A payload-section heading with trailing whitespace is still the section.
printf '## Deferred \n\n- **Task 1** Parked.\n' >"$tmp/parked-ws-head.md"
spec_parse_parked_map "$tmp/parked-ws-head.md" >"$tmp/pwh.out" \
  || fail "parked-map parse failed on the trailing-whitespace heading fixture"
grep -q "^ref	1	deferred" "$tmp/pwh.out" \
  || fail "a trailing-whitespace section heading was not recognized: $(cat "$tmp/pwh.out")"
echo "ok: section headings are matched with trailing-whitespace tolerance"

# 7d. Bullets outside the three human-payload sections park nothing.
cat >"$tmp/parked-outside.md" <<'EOF'
# Fixture — Tasks

## Tasks

- **Task 1** Not a payload section.

## Completed

- **Task 2** Not a payload section either.
EOF
spec_parse_parked_map "$tmp/parked-outside.md" >"$tmp/po.out" \
  || fail "parked-map parse failed on the outside-sections fixture"
[ ! -s "$tmp/po.out" ] || fail "a bullet outside the payload sections parked a task: $(cat "$tmp/po.out")"
echo "ok: only the three human-payload sections park tasks"

# 7e. Tabs inside a payload are folded so they cannot split a record.
printf '## Deferred\n\n- **Task 1** payload\twith\ttabs\n' >"$tmp/parked-tab.md"
spec_parse_parked_map "$tmp/parked-tab.md" >"$tmp/pt.out" \
  || fail "parked-map parse failed on the tab-payload fixture"
[ "$(awk -F'\t' 'NR == 1 { print NF }' "$tmp/pt.out")" = 5 ] \
  || fail "payload tabs split the record into extra fields: $(cat "$tmp/pt.out")"
grep -q 'payload with tabs$' "$tmp/pt.out" \
  || fail "payload tabs were not folded to spaces: $(cat "$tmp/pt.out")"
echo "ok: payload tabs are folded, so a record cannot be split (REQ-B1.6b)"

# 7f. End-of-file inside an open column-0 fence is malformed input: an
# unterminated fence would otherwise swallow the rest of the file silently
# (REQ-A1.1's lib half). Fails closed with NO partial stream.
cat >"$tmp/parked-open-fence.md" <<'EOF'
# Fixture — Tasks

## Deferred

- **Task 1** A real park before the fence.

```
## Awaiting input

- **Task 2** Swallowed by the unterminated fence.
EOF
if err=$(spec_parse_parked_map "$tmp/parked-open-fence.md" 2>&1 >"$tmp/pof.out"); then
  fail "end-of-file inside an open fence did not fail closed (REQ-A1.1)"
fi
[ ! -s "$tmp/pof.out" ] \
  || fail "open-fence failure emitted a partial stream: $(cat "$tmp/pof.out")"
case $err in
  *fence*) ;;
  *) fail "open-fence failure lacks a clear message: $err" ;;
esac
echo "ok: end-of-file inside an open fence fails closed with no partial stream (REQ-A1.1)"

# 7g. NUL-bearing input and a missing file fail closed (REQ-B1.6d).
{
  printf '## Deferred\n\n'
  printf -- '- **Task 1** payload \000 truncated\n'
} >"$tmp/parked-nul.md"
if err=$(spec_parse_parked_map "$tmp/parked-nul.md" 2>&1 >"$tmp/pn.out"); then
  fail "NUL-bearing parked-map input did not fail closed (REQ-B1.6d)"
fi
case $err in
  *NUL*) ;;
  *) fail "NUL parked-map failure lacks a clear message: $err" ;;
esac
[ ! -s "$tmp/pn.out" ] || fail "NUL parked-map failure emitted a partial stream"
if err=$(spec_parse_parked_map "$tmp/no-such-file.md" 2>&1 >/dev/null); then
  fail "parked-map parse of a missing file did not fail"
fi
case $err in
  *"missing or unreadable"*) ;;
  *) fail "missing-file parked-map failure lacks a clear message: $err" ;;
esac
echo "ok: the parked map fails closed on NUL input and a missing file"

# 7h. `-` reads the caller's snapshot from stdin.
spec_parse_parked_map - <"$tmp/parked-crlf.md" >"$tmp/ps.out" \
  || fail "stdin parked-map parse failed"
cmp -s "$tmp/parked-crlf.golden" "$tmp/ps.out" \
  || fail "stdin parked-map stream differs from the file parse: $(cat "$tmp/ps.out")"
echo "ok: the parked map reads a caller snapshot from stdin"

# 7i. The lib emits RAW bytes: sanitization is the caller's output-site job
# (REQ-B1.6c — anchor stability forbids lib-side mutation).
printf '## Deferred\n\n- **Task 1\033x** hostile token\n' >"$tmp/parked-esc.md"
spec_parse_parked_map "$tmp/parked-esc.md" >"$tmp/pe.out" \
  || fail "parked-map parse failed on the hostile-token fixture"
LC_ALL=C grep -q "$(printf '\033')" "$tmp/pe.out" \
  || fail "the lib mutated the emitted bytes (REQ-B1.6c pins raw emission)"
grep -q '^refbad	' "$tmp/pe.out" \
  || fail "a hostile token was not classified as a rejected reference: $(cat "$tmp/pe.out")"
echo "ok: the lib emits raw bytes and classifies a hostile token as rejected (REQ-B1.6c)"

echo "PASS: test-spec-parse.sh"
