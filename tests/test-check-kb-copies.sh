#!/bin/bash
# Tests for scripts/check-kb-copies.sh — the copied-section lint over a
# knowledge base: specs are cited, never copied (mission-control REQ-K1.4).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-check-kb-copies.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
lint=$repo_root/scripts/check-kb-copies.sh

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$lint" ] || {
  echo "FAIL: scripts/check-kb-copies.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
trap 'rm -rf "$tmp"' EXIT

run() { # run <args...>: sets RC, OUT, ERR
  OUT=$(/bin/bash "$lint" "$@" 2>"$tmp/err")
  RC=$?
  ERR=$(cat "$tmp/err")
}

mkdir -p "$tmp/specs/demo" "$tmp/specs/_observations" "$tmp/kb/duty"
cat >"$tmp/specs/demo/design.md" <<'EOF'
# Demo design

### D-1: A decision

**Decision:** Every automated act appends an entry naming the act and its
one-step reversal, so a reviewer can undo it from the entry alone.
EOF
printf '%s\n' "An observation fragment line long enough to be compared by the lint here." \
  >"$tmp/specs/_observations/entry.md"
cat >"$tmp/kb/duty/notes.md" <<'EOF'
# Notes

The undo design is cited at its source: [D-1](specs/demo/design.md).
EOF

# ---------------------------------------------------------------------------
# The shipped fixtures lint clean, as CI runs them.
# ---------------------------------------------------------------------------
run
if [ "$RC" -eq 0 ]; then ok "the shipped knowledge-base fixtures copy no spec line"; else fail "the shipped fixtures fail the lint: $OUT $ERR"; fi

run --kb "$tmp/kb" --specs "$tmp/specs"
if [ "$RC" -eq 0 ]; then ok "a knowledge base that cites passes"; else fail "a citing knowledge base failed (exit $RC): $OUT $ERR"; fi

# ---------------------------------------------------------------------------
# A seeded copy is flagged, whitespace differences notwithstanding.
# ---------------------------------------------------------------------------
cat >>"$tmp/kb/duty/notes.md" <<'EOF'

  **Decision:**   Every automated act appends an entry naming the act and its
EOF
run --kb "$tmp/kb" --specs "$tmp/specs"
if [ "$RC" -eq 1 ]; then ok "a seeded copied line fails the lint"; else fail "a seeded copy passed (exit $RC)"; fi
case $OUT in
  *"notes.md:5: copies "*"design.md"*) ok "the finding names the file, the line and the spec copied" ;;
  *) fail "the finding lacks file, line or source: $OUT" ;;
esac

# ---------------------------------------------------------------------------
# Short lines and reserved directories never match.
# ---------------------------------------------------------------------------
printf '%s\n' "# Notes" "### D-1: A decision" >"$tmp/kb/duty/notes.md"
run --kb "$tmp/kb" --specs "$tmp/specs"
if [ "$RC" -eq 0 ]; then ok "a short shared line is not a copy"; else fail "a short line was flagged: $OUT"; fi
printf '%s\n' "An observation fragment line long enough to be compared by the lint here." \
  >"$tmp/kb/duty/notes.md"
run --kb "$tmp/kb" --specs "$tmp/specs"
if [ "$RC" -eq 0 ]; then ok "an underscore-prefixed reserved directory is not spec text"; else fail "a reserved-directory line was flagged: $OUT"; fi

# ---------------------------------------------------------------------------
# Inputs that would narrow the scan fail closed.
# ---------------------------------------------------------------------------
run --kb "$tmp/absent" --specs "$tmp/specs"
if [ "$RC" -eq 2 ]; then ok "a missing knowledge base fails closed"; else fail "a missing knowledge base exited $RC"; fi
mkdir -p "$tmp/empty"
run --kb "$tmp/empty" --specs "$tmp/specs"
if [ "$RC" -eq 2 ]; then ok "a knowledge base with no Markdown file fails closed"; else fail "an empty knowledge base exited $RC"; fi
run --kb "$tmp/kb" --specs "$tmp/empty"
if [ "$RC" -eq 2 ]; then ok "a spec root with no Markdown file fails closed"; else fail "an empty spec root exited $RC"; fi
run --bogus
if [ "$RC" -eq 2 ]; then ok "an unknown argument is a usage error"; else fail "an unknown argument exited $RC"; fi

if [ "$failures" -ne 0 ]; then
  echo "test-check-kb-copies: $failures failure(s)" >&2
  exit 1
fi
echo "test-check-kb-copies: all passed"
