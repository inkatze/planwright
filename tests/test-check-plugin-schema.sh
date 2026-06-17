#!/bin/bash
# Tests for scripts/check-plugin-schema.sh — schema-deep manifest validation
# that DEGRADES (exit 0, clear note) when the `claude` CLI is absent and
# ENFORCES (propagates a non-zero exit) when it is present and a manifest is
# schema-broken. `claude` is stubbed so the suite is hermetic: it never shells
# out to a real Claude Code install or the network. The script is invoked via
# `/bin/bash` (not its shebang) so the empty-PATH "absent claude" case does not
# trip over `/usr/bin/env bash` needing PATH to find bash.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-plugin-schema.sh"

failures=0
assert_exit() {
  # assert_exit <label> <expected-exit> <actual-exit>
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  # assert_contains <label> <needle> <haystack>
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (output missing '$2')" >&2
      printf '%s\n' "----- output -----" "$3" "------------------" >&2
      failures=$((failures + 1))
      ;;
  esac
}

if [ ! -f "$SCRIPT" ]; then
  echo "FAIL: check-plugin-schema script missing at $SCRIPT" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# Stub `claude` that PASSES: echoes its args, exits 0.
pass_bin="$tmp/pass"
mkdir -p "$pass_bin"
cat >"$pass_bin/claude" <<'EOF'
#!/bin/sh
echo "stub claude: $* -> Validation passed"
exit 0
EOF
chmod +x "$pass_bin/claude"

# Stub `claude` that FAILS schema validation: exits 1.
fail_bin="$tmp/fail"
mkdir -p "$fail_bin"
cat >"$fail_bin/claude" <<'EOF'
#!/bin/sh
echo "stub claude: $* -> schema error" >&2
exit 1
EOF
chmod +x "$fail_bin/claude"

# 1. claude present + the repo's real (valid) manifests → exit 0, and the
#    success line names that schema validation actually ran.
out="$(PATH="$pass_bin:$PATH" /bin/bash "$SCRIPT" "$REPO_ROOT" 2>&1)"
rc=$?
assert_exit "valid manifests with claude present pass" 0 "$rc"
assert_contains "success names the schema validation" "passed schema validation" "$out"

# 2. claude present + schema-broken (stub exits non-zero) → the gate fails and
#    names the failure (exit 1, distinct from the skip and usage paths).
out="$(PATH="$fail_bin:$PATH" /bin/bash "$SCRIPT" "$REPO_ROOT" 2>&1)"
rc=$?
assert_exit "schema-broken manifest fails the gate" 1 "$rc"
assert_contains "failure is named" "FAILED" "$out"

# 3. claude ABSENT → degrades: exit 0 with a clear skip note. This is the CI
#    shape (the runner has no Claude Code). Empty PATH removes claude; with an
#    explicit repo-dir arg the skip path needs no external command at all.
out="$(PATH='' /bin/bash "$SCRIPT" "$REPO_ROOT" 2>&1)"
rc=$?
assert_exit "absent claude degrades to a clean skip" 0 "$rc"
assert_contains "skip note names the missing CLI" "not on PATH" "$out"
assert_contains "skip note says it is skipping" "skipping schema validation" "$out"

# 4. A non-directory arg is a usage error (exit 2), distinct from a skip or a
#    schema failure, so a mis-invocation is never read as a clean gate.
out="$(PATH="$pass_bin:$PATH" /bin/bash "$SCRIPT" "$tmp/does-not-exist" 2>&1)"
rc=$?
assert_exit "missing repo-dir is a usage error" 2 "$rc"

# 5. Zero positional args → the repo defaults to dirname "$0"/.. (the repo the
#    script ships in). With claude present this validates the real manifests and
#    passes, proving the default-path fallback resolves rather than running
#    against an empty/garbage root.
out="$(PATH="$pass_bin:$PATH" /bin/bash "$SCRIPT" 2>&1)"
rc=$?
assert_exit "no-arg default path resolves and passes" 0 "$rc"
assert_contains "no-arg run reports schema validation ran" "passed schema validation" "$out"

# 6. claude present but the target has NO .claude-plugin manifests → the script
#    has nothing to validate and exits 0 with a clear note (distinct from both a
#    schema pass and the absent-claude skip). Guards the "validated=0" branch so
#    an empty target is never silently read as a clean schema gate.
nomanifest="$tmp/nomanifest"
mkdir -p "$nomanifest"
out="$(PATH="$pass_bin:$PATH" /bin/bash "$SCRIPT" "$nomanifest" 2>&1)"
rc=$?
assert_exit "manifest-less target with claude present exits 0" 0 "$rc"
assert_contains "manifest-less run says there is nothing to validate" "nothing to validate" "$out"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-plugin-schema tests passed"
