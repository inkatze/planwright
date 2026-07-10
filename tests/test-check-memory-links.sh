#!/bin/bash
# Tests for scripts/check-memory-links.sh — the standing machine-local
# reference guard (output-hygiene Task 6, REQ-D1.1, D-4). A committed spec
# file must not carry a `[[name]]` memory-link token: those resolve only
# against the authoring session's memory store, never for a reader of the
# committed bundle. The guard is the CI backstop behind /spec-draft's
# neutralization step (REQ-D1.2), so a future writer that skips neutralization
# fails CI rather than silently reintroducing the violation.
#
# Two matching rules under test:
#   - Code-span-aware: a `[[...]]` inside an inline code span (backticks) is a
#     documentation mention of the token syntax, not a live link, and passes.
#     A bare `[[slug]]` is a live link and fails.
#   - Non-terminal-scoped: the guard enforces on Draft/Ready/Active bundles.
#     Terminal bundles (Done/Retired/Superseded) are frozen — changing them
#     needs a Done->Draft reopen (spec-format) — so they are skipped; the
#     guard re-engages the moment such a bundle reopens.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-memory-links.sh"

failures=0
assert() {
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}

if [ ! -f "$CHECKER" ]; then
  echo "FAIL: checker script missing at $CHECKER" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# mkbundle <dir> <status> — write a minimal four-file bundle with the given
# Status; callers overwrite individual files to plant fixtures.
mkbundle() {
  mkdir -p "$1"
  printf '# R\n\n**Status:** %s\n**Format-version:** 1\n' "$2" >"$1/requirements.md"
  printf '# D\n\n**Status:** %s\n' "$2" >"$1/design.md"
  printf '# T\n\n**Status:** %s\n' "$2" >"$1/tasks.md"
  printf '# TS\n\n**Status:** %s\n' "$2" >"$1/test-spec.md"
}

# 1. The real repo's spec bundles pass the default scan (output-hygiene clean
#    after this task's edits; the Done orchestration-fleet bundle skipped).
/bin/bash "$CHECKER" >/dev/null
assert "repo spec bundles pass the default scan" 0 $?

# 2. A non-terminal bundle with a bare [[foo]] token in a spec file fails, and
#    the output names the file and the offending token.
mkbundle "$tmp/dirty" "Draft"
printf '# T\n\n**Status:** Draft\n\nSee [[foo]] for details.\n' >"$tmp/dirty/tasks.md"
out="$(/bin/bash "$CHECKER" "$tmp/dirty" 2>&1)"
assert "bare [[foo]] in a Draft bundle fails" 1 $?
case "$out" in
  *tasks.md*'[[foo]]'*) echo "ok: failure names the file and token" ;;
  *)
    echo "FAIL: output does not name file and token: $out" >&2
    failures=$((failures + 1))
    ;;
esac

# 3. A clean non-terminal bundle whose only [[...]] occurrences are inside
#    inline code spans (documentation mentions) passes.
mkbundle "$tmp/clean" "Ready"
# Quoted heredoc: the body is literal, so the backticks are inline code spans in
# the fixture, not shell command substitution.
cat >"$tmp/clean/requirements.md" <<'EOF'
# R

**Status:** Ready

The `[[name]]` rule and the `[[foo]]` example and `[[…]]`.
EOF
/bin/bash "$CHECKER" "$tmp/clean" >/dev/null 2>&1
assert "backtick-wrapped [[...]] mentions pass (code-span-aware)" 0 $?

# 4. A terminal (Done) bundle carrying a bare [[slug]] link is skipped, so it
#    passes — a frozen bundle is not enforced until it reopens.
mkbundle "$tmp/frozen" "Done"
printf '# D\n\n**Status:** Done\n\nSee [[workflows-not-plugin-invocable]] and the stance.\n' >"$tmp/frozen/design.md"
out="$(/bin/bash "$CHECKER" "$tmp/frozen" 2>&1)"
assert "Done bundle with a bare link is skipped (passes)" 0 $?
case "$out" in
  *skip*Done* | *Done*skip*) echo "ok: skip of the terminal bundle is reported" ;;
  *) echo "note: skip not explicitly reported (acceptable): $out" ;;
esac

# 5. Each of the four spec files is scanned: a bare token in test-spec.md is
#    caught (not just tasks.md).
mkbundle "$tmp/ts" "Active"
printf '# TS\n\n**Status:** Active\n\nA bare [[bar]] link.\n' >"$tmp/ts/test-spec.md"
/bin/bash "$CHECKER" "$tmp/ts" >/dev/null 2>&1
assert "bare token in test-spec.md is caught" 1 $?

# 6. The four-file scope is exact: a [[slug]] in the kickoff-brief (append-only,
#    out of the standing guard's scope per REQ-D1.1) does not fail an otherwise
#    clean bundle.
mkbundle "$tmp/brief" "Draft"
printf '# Brief\n\nSee [[some-memory]] in the brief body.\n' >"$tmp/brief/kickoff-brief.md"
/bin/bash "$CHECKER" "$tmp/brief" >/dev/null 2>&1
assert "kickoff-brief [[slug]] is out of scope (bundle passes)" 0 $?

# 7. A bundle directory missing requirements.md is skipped with a notice, not a
#    hard failure (the validator owns structural completeness, REQ-K1.7).
mkdir -p "$tmp/broken"
printf '# T\n\nSee [[x]].\n' >"$tmp/broken/tasks.md"
/bin/bash "$CHECKER" "$tmp/broken" >/dev/null 2>&1
assert "bundle missing requirements.md is skipped, not failed" 0 $?

# 8. Usage error on a non-existent path (exit 2, distinct from a lint failure).
/bin/bash "$CHECKER" "$tmp/does-not-exist" >/dev/null 2>&1
assert "non-existent bundle path is a usage error" 2 $?

# 9. An unreadable spec file is a usage error, not a silent clean pass: a file
#    the guard cannot scan must not be reported as free of memory links
#    (fail-closed parity with check-doc-links.sh). Skipped under root, where
#    mode 000 is still readable.
if [ "$(id -u)" -ne 0 ]; then
  mkbundle "$tmp/unreadable" "Draft"
  printf '# T\n\n**Status:** Draft\n\nSee [[hidden]].\n' >"$tmp/unreadable/tasks.md"
  chmod 000 "$tmp/unreadable/tasks.md"
  /bin/bash "$CHECKER" "$tmp/unreadable" >/dev/null 2>&1
  assert "unreadable spec file is a usage error (fail-closed)" 2 $?
  chmod 644 "$tmp/unreadable/tasks.md"
fi

# 10. A bare token sharing a line with an inline code span is still caught: the
#     code span is stripped, the bare token remains.
mkbundle "$tmp/mixed" "Draft"
cat >"$tmp/mixed/tasks.md" <<'EOF'
# T

**Status:** Draft

The `[[ok]]` mention and a bare [[live]] link.
EOF
out="$(/bin/bash "$CHECKER" "$tmp/mixed" 2>&1)"
assert "bare token beside a code span is caught" 1 $?
case "$out" in
  *'[[live]]'*) echo "ok: the bare token, not the code-span mention, is flagged" ;;
  *)
    echo "FAIL: expected [[live]] flagged (not [[ok]]): $out" >&2
    failures=$((failures + 1))
    ;;
esac

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-memory-links tests passed"
