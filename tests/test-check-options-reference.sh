#!/bin/bash
# Tests for scripts/check-options-reference.sh — the canonical options
# reference coverage check (REQ-K1.8, D-43). Task 2 wires this script into CI;
# the check itself is part of the config-model skeleton.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-options-reference.sh"

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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 1. The real repo files pass (Done-when: every option in the default config
#    has an options-reference entry).
/bin/bash "$CHECKER" >/dev/null
assert "repo defaults are fully documented" 0 $?

# 2. Fixture: a documented option passes.
cat > "$tmp/config.yml" <<'EOF'
# comment line
documented_option: true
EOF
cat > "$tmp/reference.md" <<'EOF'
| Option | Default | Effect | Consumed by |
| --- | --- | --- | --- |
| `documented_option` | `true` | Does a thing. | `/example` |
EOF
/bin/bash "$CHECKER" "$tmp/config.yml" "$tmp/reference.md" >/dev/null
assert "documented option passes" 0 $?

# 2b. Fixture: cosmetic cell padding in the reference table does not break
#     recognition (the checker tests coverage, not whitespace style).
cat > "$tmp/reference-padded.md" <<'EOF'
| Option | Default | Effect | Consumed by |
| --- | --- | --- | --- |
|  `documented_option`  | `true` | Padded row. | `/example` |
EOF
/bin/bash "$CHECKER" "$tmp/config.yml" "$tmp/reference-padded.md" >/dev/null 2>&1
assert "padded reference row is recognized" 0 $?

# 3. Fixture: a seeded undocumented option fails and is named in the output
#    (the REQ-K1.8 seeded-violation fixture).
cat > "$tmp/config-bad.yml" <<'EOF'
documented_option: true
bogus_option: 42
EOF
out="$(/bin/bash "$CHECKER" "$tmp/config-bad.yml" "$tmp/reference.md" 2>&1)"
assert "undocumented option fails" 1 $?
case "$out" in
  *bogus_option*) echo "ok: failure names the undocumented option" ;;
  *)
    echo "FAIL: output does not name bogus_option: $out" >&2
    failures=$((failures + 1))
    ;;
esac

# 4. Fixture: a reference row with no matching config option is a warning,
#    not a failure (stale docs surface without blocking). The redirect order
#    below ("2>&1 >/dev/null") captures stderr only: warnings go to stderr,
#    and stdout is deliberately discarded.
cat > "$tmp/reference-extra.md" <<'EOF'
| Option | Default | Effect | Consumed by |
| --- | --- | --- | --- |
| `documented_option` | `true` | Does a thing. | `/example` |
| `ghost_option` | `x` | Documented but not in config. | `/example` |
EOF
err="$(/bin/bash "$CHECKER" "$tmp/config.yml" "$tmp/reference-extra.md" 2>&1 >/dev/null)"
assert "stale reference row is not a failure" 0 $?
case "$err" in
  *ghost_option*) echo "ok: stale row surfaced as a warning" ;;
  *)
    echo "FAIL: stale row not surfaced: $err" >&2
    failures=$((failures + 1))
    ;;
esac

# 2c. Fixture: a table row indented per markdown's allowance (up to three
#     leading spaces) is still recognized.
cat > "$tmp/reference-indented.md" <<'EOF'
| Option | Default | Effect | Consumed by |
| --- | --- | --- | --- |
  | `documented_option` | `true` | Indented row. | `/example` |
EOF
/bin/bash "$CHECKER" "$tmp/config.yml" "$tmp/reference-indented.md" >/dev/null 2>&1
assert "indented reference row is recognized" 0 $?

# 2d. Fixture: a config that parses to zero option keys is a fail-closed
#     error, not a silent pass (a reformatted defaults.yml must not turn the
#     CI drift check into a no-op).
: > "$tmp/config-empty.yml"
/bin/bash "$CHECKER" "$tmp/config-empty.yml" "$tmp/reference.md" >/dev/null 2>&1
assert "zero-key config fails closed" 2 $?

# 4b. A hostile CDPATH must not corrupt the script's repo-root derivation
#     (cd resolving through CDPATH echoes the path into the substitution).
mkdir -p "$tmp/decoy/scripts" "$tmp/work/docs"
cp -R "$REPO_ROOT/scripts" "$tmp/work/"
cp -R "$REPO_ROOT/config" "$tmp/work/"
cp "$REPO_ROOT/docs/options-reference.md" "$tmp/work/docs/"
(cd "$tmp/work" && CDPATH="$tmp/decoy" /bin/bash scripts/check-options-reference.sh >/dev/null 2>&1)
assert "CDPATH does not corrupt root derivation" 0 $?

# 5. Missing files are a clear error, not a silent pass.
/bin/bash "$CHECKER" "$tmp/no-such-config.yml" "$tmp/reference.md" >/dev/null 2>&1
assert "missing config file is an error" 2 $?
/bin/bash "$CHECKER" "$tmp/config.yml" "$tmp/no-such-reference.md" >/dev/null 2>&1
assert "missing reference file is an error" 2 $?

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-options-reference tests passed"
