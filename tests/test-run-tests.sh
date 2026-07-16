#!/bin/bash
# Tests for scripts/run-tests.sh — the bounded-parallel shell-test runner
# behind `mise run test`. The runner must divide suite wall-clock by the
# core count without weakening the gate: any single failing file still
# fails the run, is named, and has its captured output printed at the end
# (no interleaved garbage, no silently skipped siblings).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/run-tests.sh"

failures=0
assert() {
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (missing '$2' in output)" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_not_contains() {
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (unexpected '$2' in output)" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -f "$RUNNER" ]; then
  echo "FAIL: runner script missing at $RUNNER" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# Fixture suite A: all tests pass.
mkdir -p "$tmp/pass"
cat >"$tmp/pass/test-alpha.sh" <<'EOF'
#!/bin/bash
echo "alpha ran"
EOF
cat >"$tmp/pass/test-beta.sh" <<'EOF'
#!/bin/bash
echo "beta ran"
EOF

# Fixture suite B: one multi-line failure among passers, plus an exit-255
# test (the xargs abort code — the runner must not let it cancel siblings).
mkdir -p "$tmp/mixed"
cp "$tmp/pass/test-alpha.sh" "$tmp/mixed/test-alpha.sh"
cat >"$tmp/mixed/test-boom.sh" <<'EOF'
#!/bin/bash
echo "boom-line-one"
echo "boom-line-two" >&2
exit 3
EOF
cat >"$tmp/mixed/test-vanish.sh" <<'EOF'
#!/bin/bash
echo "vanish-detail"
exit 255
EOF

# 1. All-pass suite exits 0 and reports each file.
out="$(/bin/bash "$RUNNER" "$tmp/pass" 2>&1)"
assert "all-pass suite exits 0" 0 $?
assert_contains "passing file alpha reported" "test-alpha.sh" "$out"
assert_contains "passing file beta reported" "test-beta.sh" "$out"

# 2. A failing file fails the gate, is NAMED, and its captured stdout+stderr
#    both appear at the end; siblings still run to completion.
out="$(/bin/bash "$RUNNER" "$tmp/mixed" 2>&1)"
assert "mixed suite exits 1" 1 $?
assert_contains "failing file is named" "test-boom.sh" "$out"
assert_contains "failure log stdout is printed" "boom-line-one" "$out"
assert_contains "failure log stderr is printed" "boom-line-two" "$out"
assert_contains "exit-255 file is named (did not cancel the run)" \
  "test-vanish.sh" "$out"
assert_contains "exit-255 file's log is printed" "vanish-detail" "$out"
assert_contains "passing sibling still ran" "test-alpha.sh" "$out"

# 3. The serial degrade path preserves the same contract.
out="$(PLANWRIGHT_TEST_FORCE_SERIAL=1 /bin/bash "$RUNNER" "$tmp/mixed" 2>&1)"
assert "serial fallback: mixed suite exits 1" 1 $?
assert_contains "serial fallback: failing file named" "test-boom.sh" "$out"
assert_contains "serial fallback: failure log printed" "boom-line-one" "$out"
assert_contains "serial fallback: sibling still ran" "test-alpha.sh" "$out"
out="$(PLANWRIGHT_TEST_FORCE_SERIAL=1 /bin/bash "$RUNNER" "$tmp/pass" 2>&1)"
assert "serial fallback: all-pass suite exits 0" 0 $?

# 4. PLANWRIGHT_TEST_JOBS bounds the pool; a garbage value degrades to a
#    sane default instead of breaking the run.
out="$(PLANWRIGHT_TEST_JOBS=1 /bin/bash "$RUNNER" "$tmp/pass" 2>&1)"
assert "explicit jobs=1 passes" 0 $?
out="$(PLANWRIGHT_TEST_JOBS=banana /bin/bash "$RUNNER" "$tmp/pass" 2>&1)"
assert "non-numeric jobs value degrades sanely" 0 $?

# 5. An empty suite directory is a loud usage error, not a silent green.
mkdir -p "$tmp/empty"
/bin/bash "$RUNNER" "$tmp/empty" >/dev/null 2>&1
assert "empty suite dir is a usage error" 2 $?

# 6. A missing suite directory is the same usage error.
/bin/bash "$RUNNER" "$tmp/no-such-dir" >/dev/null 2>&1
assert "missing suite dir is a usage error" 2 $?

# 7. Concurrent output stays per-file: two chatty passers each keep their
#    own line intact (no split/interleaved fragments of the marker lines).
mkdir -p "$tmp/chatty"
i=1
while [ "$i" -le 6 ]; do
  cat >"$tmp/chatty/test-chat$i.sh" <<EOF
#!/bin/bash
j=1
while [ "\$j" -le 50 ]; do
  echo "chat$i-marker-\$j"
  j=\$((j + 1))
done
EOF
  i=$((i + 1))
done
out="$(/bin/bash "$RUNNER" "$tmp/chatty" 2>&1)"
assert "chatty concurrent suite exits 0" 0 $?
# A passing file's noise stays in its log, not on the runner's stream.
assert_not_contains "passing files' raw output is not interleaved" \
  "chat1-marker-25" "$out"

# 8. A filename with a space survives dispatch intact.
mkdir -p "$tmp/space"
cat >"$tmp/space/test with space.sh" <<'EOF'
#!/bin/bash
echo "space ran"
exit 4
EOF
out="$(/bin/bash "$RUNNER" "$tmp/space" 2>&1)"
assert "spaced filename failure fails the gate" 1 $?
assert_contains "spaced filename is named" "test with space.sh" "$out"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all run-tests tests passed"
