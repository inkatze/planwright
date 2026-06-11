#!/bin/bash
# Tests for scripts/check-doc-links.sh — the doctrine cross-reference
# link-check (Task 2 deliverable, wired into CI). The doctrine docs
# cross-reference each other with relative markdown links; a renamed or
# deleted target must fail CI, not rot silently.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-doc-links.sh"

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

# 1. The real repo's default scan set passes (every doctrine/docs/README
#    cross-reference resolves).
/bin/bash "$CHECKER" >/dev/null
assert "repo cross-references all resolve" 0 $?

# 2. Fixture: a valid relative link resolves against the linking file's own
#    directory, not the invoker's cwd.
mkdir -p "$tmp/sub"
cat >"$tmp/sub/target.md" <<'EOF'
# Target
EOF
cat >"$tmp/sub/source.md" <<'EOF'
See [the target](target.md).
EOF
(cd / && /bin/bash "$CHECKER" "$tmp/sub/source.md" >/dev/null)
assert "valid relative link passes from any cwd" 0 $?

# 3. Fixture: a broken relative link fails and the output names both the
#    linking file and the missing target.
cat >"$tmp/sub/broken.md" <<'EOF'
See [gone](no-such-file.md).
EOF
out="$(/bin/bash "$CHECKER" "$tmp/sub/broken.md" 2>&1)"
assert "broken link fails" 1 $?
case "$out" in
  *broken.md*no-such-file.md* | *no-such-file.md*broken.md*)
    echo "ok: failure names source and target"
    ;;
  *)
    echo "FAIL: output does not name source and target: $out" >&2
    failures=$((failures + 1))
    ;;
esac

# 4. Fixture: external and non-file links are skipped, not resolved.
cat >"$tmp/sub/external.md" <<'EOF'
[web](https://example.com/page) and [plain](http://example.com) and
[mail](mailto:a@b.c) and [same-page section](#a-heading).
EOF
/bin/bash "$CHECKER" "$tmp/sub/external.md" >/dev/null
assert "external/mailto/fragment-only links are skipped" 0 $?

# 5. Fixture: a fragment on a file link is stripped before resolution.
cat >"$tmp/sub/fragment.md" <<'EOF'
See [a section](target.md#some-heading).
EOF
/bin/bash "$CHECKER" "$tmp/sub/fragment.md" >/dev/null
assert "file link with fragment resolves" 0 $?

# 6. Fixture: multiple links on one line are each checked (one broken among
#    valid ones still fails).
cat >"$tmp/sub/multi.md" <<'EOF'
[ok](target.md) then [bad](missing.md) then [web](https://example.com).
EOF
out="$(/bin/bash "$CHECKER" "$tmp/sub/multi.md" 2>&1)"
assert "one broken link among several fails" 1 $?
case "$out" in
  *missing.md*) echo "ok: the broken target is named" ;;
  *)
    echo "FAIL: broken target not named: $out" >&2
    failures=$((failures + 1))
    ;;
esac

# 6b. Fixture: a NUL byte in the file does not turn grep into binary mode and
#     emit a "Binary file ... matches" pseudo-target. The link still resolves.
printf '\000[ok](target.md)\000\n' >"$tmp/sub/withnul.md"
out="$(/bin/bash "$CHECKER" "$tmp/sub/withnul.md" 2>&1)"
assert "NUL byte does not produce a binary-mode pseudo-target" 0 $?
case "$out" in
  *"Binary file"*)
    echo "FAIL: binary-mode message leaked as a target: $out" >&2
    failures=$((failures + 1))
    ;;
  *) echo "ok: no binary-mode pseudo-target" ;;
esac

# 7. A directory target (e.g. a link to a folder) resolves if it exists.
cat >"$tmp/sub/dirlink.md" <<'EOF'
See [the directory](../sub).
EOF
/bin/bash "$CHECKER" "$tmp/sub/dirlink.md" >/dev/null
assert "existing directory target passes" 0 $?

# 8. A missing input file is a usage error (exit 2), distinct from a broken
#    link (exit 1).
/bin/bash "$CHECKER" "$tmp/no-such-input.md" >/dev/null 2>&1
assert "missing input file is a usage error" 2 $?

# 8b. An unreadable input file is also a usage error: a file the checker
#     could not scan must not be reported as "all targets resolve".
#     (Skipped under root, where mode 000 is still readable.)
if [ "$(id -u)" -ne 0 ]; then
  cat >"$tmp/unreadable.md" <<'EOF'
[link](target.md)
EOF
  chmod 000 "$tmp/unreadable.md"
  /bin/bash "$CHECKER" "$tmp/unreadable.md" >/dev/null 2>&1
  assert "unreadable input file is a usage error" 2 $?
  chmod 644 "$tmp/unreadable.md"
fi

# 9. A hostile CDPATH must not corrupt the default-set repo-root derivation
#    (mirrors the options-reference checker's guard).
mkdir -p "$tmp/decoy/scripts"
(CDPATH="$tmp/decoy" /bin/bash "$CHECKER" >/dev/null 2>&1)
assert "CDPATH does not corrupt root derivation" 0 $?

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-doc-links tests passed"
