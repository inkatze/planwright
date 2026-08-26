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

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# 1. The real repo files pass (Done-when: every option in the default config
#    has an options-reference entry).
/bin/bash "$CHECKER" >/dev/null
assert "repo defaults are fully documented" 0 $?

# 1b. The `commit_on_state_move` row carries the v1-only note (invariant-tasks
#     Task 8, REQ-E1.3 — the option is vacuous under format-version 2, where no
#     execution-state edit touches the committed file, so its reference row must
#     say so). This asserts the note's content is present in that specific row,
#     not merely that the option is documented.
REFERENCE="$REPO_ROOT/docs/options-reference.md"
# shellcheck disable=SC2016 # the backtick is literal markdown, not expansion
state_move_row="$(sed -n 's/^[[:space:]]*|[[:space:]]*`commit_on_state_move`[[:space:]]*|.*/&/p' "$REFERENCE")"
case "$state_move_row" in
  *v1-only*)
    echo "ok: commit_on_state_move row carries the v1-only note (REQ-E1.3)"
    ;;
  *)
    echo "FAIL: commit_on_state_move row lacks the v1-only note (REQ-E1.3): $state_move_row" >&2
    failures=$((failures + 1))
    ;;
esac

# 2. Fixture: a documented option passes.
cat >"$tmp/config.yml" <<'EOF'
# comment line
documented_option: true
EOF
cat >"$tmp/reference.md" <<'EOF'
| Option | Default | Effect | Consumed by |
| --- | --- | --- | --- |
| `documented_option` | `true` | Does a thing. | `/example` |
EOF
/bin/bash "$CHECKER" "$tmp/config.yml" "$tmp/reference.md" >/dev/null
assert "documented option passes" 0 $?

# 2b. Fixture: cosmetic cell padding in the reference table does not break
#     recognition (the checker tests coverage, not whitespace style).
cat >"$tmp/reference-padded.md" <<'EOF'
| Option | Default | Effect | Consumed by |
| --- | --- | --- | --- |
|  `documented_option`  | `true` | Padded row. | `/example` |
EOF
/bin/bash "$CHECKER" "$tmp/config.yml" "$tmp/reference-padded.md" >/dev/null 2>&1
assert "padded reference row is recognized" 0 $?

# 2c. Fixture: a table row indented per markdown's allowance (up to three
#     leading spaces) is still recognized.
cat >"$tmp/reference-indented.md" <<'EOF'
| Option | Default | Effect | Consumed by |
| --- | --- | --- | --- |
  | `documented_option` | `true` | Indented row. | `/example` |
EOF
/bin/bash "$CHECKER" "$tmp/config.yml" "$tmp/reference-indented.md" >/dev/null 2>&1
assert "indented reference row is recognized" 0 $?

# 2d. Fixture: a config that parses to zero option keys is a fail-closed
#     error, not a silent pass (a reformatted defaults.yml must not turn the
#     CI drift check into a no-op). The error must be the checker's own
#     diagnostic, not an incidental failure.
: >"$tmp/config-empty.yml"
out="$(/bin/bash "$CHECKER" "$tmp/config-empty.yml" "$tmp/reference.md" 2>&1)"
assert "zero-key config fails closed" 2 $?
case "$out" in
  *"no option keys"*) echo "ok: zero-key failure is the checker's diagnostic" ;;
  *)
    echo "FAIL: zero-key message unclear: $out" >&2
    failures=$((failures + 1))
    ;;
esac

# 3. Fixture: a seeded undocumented option fails and is named in the output
#    (the REQ-K1.8 seeded-violation fixture).
cat >"$tmp/config-bad.yml" <<'EOF'
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
cat >"$tmp/reference-extra.md" <<'EOF'
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

# 4b. A hostile CDPATH must not corrupt the script's repo-root derivation
#     (cd resolving through CDPATH echoes the path into the substitution).
mkdir -p "$tmp/decoy/scripts" "$tmp/work/docs"
cp -R "$REPO_ROOT/scripts" "$tmp/work/"
cp -R "$REPO_ROOT/config" "$tmp/work/"
cp "$REPO_ROOT/docs/options-reference.md" "$REPO_ROOT/docs/fleet.md" "$tmp/work/docs/"
(cd "$tmp/work" && CDPATH="$tmp/decoy" /bin/bash scripts/check-options-reference.sh >/dev/null 2>&1)
assert "CDPATH does not corrupt root derivation" 0 $?

# 5. Missing files are a clear error, not a silent pass.
/bin/bash "$CHECKER" "$tmp/no-such-config.yml" "$tmp/reference.md" >/dev/null 2>&1
assert "missing config file is an error" 2 $?
/bin/bash "$CHECKER" "$tmp/config.yml" "$tmp/no-such-reference.md" >/dev/null 2>&1
assert "missing reference file is an error" 2 $?

# ===========================================================================
# The fleet-knobs tether (guard-coverage Task 9; REQ-F1.3, REQ-H1.3, D-10).
#
# docs/fleet.md's knobs table restates each fleet knob's default value in
# prose. The checker is widened to compare those restated defaults against
# config/defaults.yml, so a default changed in the config without the doc edit
# fails. The zero-argument (CI) form always engages the arm; a fixture
# invocation engages it by passing the fleet doc as a third argument.
# ===========================================================================

assert_contains() {
  case "$2" in
    *"$3"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (output did not mention '$3'): $2" >&2
      failures=$((failures + 1))
      ;;
  esac
}

FLEET_DOC="$REPO_ROOT/docs/fleet.md"
CONFIG="$REPO_ROOT/config/defaults.yml"
REFERENCE_DOC="$REPO_ROOT/docs/options-reference.md"

# 6. The zero-argument form — the one `mise run check` runs — engages the
#    fleet arm and passes on the current tree. Asserting the count is reported
#    keeps the arm from silently disappearing into a no-op.
out="$(/bin/bash "$CHECKER" 2>&1)"
assert "the CI form passes on the current tree" 0 $?
assert_contains "the CI form reports the fleet knobs it tethered" "$out" "fleet knob"

# 6b. Independently of the checker's own parse, the shipped fleet knobs table
#     must yield knobs at all — otherwise every per-knob case below would
#     vacuously pass.
fleet_knobs="$(awk '
  {
    line = $0; sub(/^[ \t]+/, "", line)
    if (line !~ /^\|/) { intbl = 0; next }
    n = split(line, c, "|")
    if (!intbl) { if (c[2] ~ /^[ \t]*Knob[ \t]*$/) intbl = 1; next }
    if (line ~ /^\|[ \t]*:?-+:?[ \t]*\|/) next
    cell = c[2]
    while (match(cell, /`[a-z0-9_]+`/)) {
      print substr(cell, RSTART + 1, RLENGTH - 2)
      cell = substr(cell, RSTART + RLENGTH)
    }
  }
' "$FLEET_DOC")"
knob_count="$(printf '%s\n' "$fleet_knobs" | grep -c .)"
if [ "$knob_count" -gt 0 ]; then
  echo "ok: the shipped fleet knobs table names $knob_count knobs"
else
  echo "FAIL: no knobs parsed from the shipped fleet knobs table" >&2
  failures=$((failures + 1))
fi

# 7. Per-knob divergence: EVERY knob the fleet table documents is individually
#    tethered. Each iteration drifts exactly one config default and asserts the
#    check goes red naming that knob, so a tether covering only some of the
#    table's knobs cannot pass this loop.
for knob in $fleet_knobs; do
  sed "s/^$knob: .*/$knob: pw-drifted-fixture-value/" "$CONFIG" >"$tmp/config-$knob.yml"
  if cmp -s "$tmp/config-$knob.yml" "$CONFIG"; then
    echo "FAIL: fleet knob '$knob' has no flat entry in $CONFIG to drift" >&2
    failures=$((failures + 1))
    continue
  fi
  out="$(/bin/bash "$CHECKER" "$tmp/config-$knob.yml" "$REFERENCE_DOC" "$FLEET_DOC" 2>&1)"
  st=$?
  if [ "$st" -eq 1 ]; then
    case "$out" in
      *"$knob"*) echo "ok: fleet knob '$knob' is individually tethered" ;;
      *)
        echo "FAIL: drifting '$knob' failed without naming it: $out" >&2
        failures=$((failures + 1))
        ;;
    esac
  else
    echo "FAIL: drifting fleet knob '$knob' did not fail the check (exit $st)" >&2
    failures=$((failures + 1))
  fi
done

# 8. Fixture: an agreeing knobs table passes, and the row shape the real doc
#    uses (a multi-knob row paired with a multi-value default cell, trailing
#    prose after an em dash) is understood.
cat >"$tmp/fleet-config.yml" <<'EOF'
simple_knob: per-step
first_knob: opus
second_knob: sonnet
EOF
cat >"$tmp/fleet-reference.md" <<'EOF'
| Option | Default | Effect | Consumed by |
| --- | --- | --- | --- |
| `simple_knob` | `per-step` | Does a thing. | `/example` |
| `first_knob` | `opus` | Does a thing. | `/example` |
| `second_knob` | `sonnet` | Does a thing. | `/example` |
EOF
cat >"$tmp/fleet-ok.md" <<'EOF'
# Fixture fleet doc

| Knob | The capability (core) | The value (yours) | Default, and why it is the safe one |
| --- | --- | --- | --- |
| `simple_knob` | A capability | A value | `per-step` — because it is the safe direction |
| `first_knob` / `second_knob` | A capability | A value | `opus` / `sonnet` — judgment-heavy work on the strong tier |
EOF
/bin/bash "$CHECKER" "$tmp/fleet-config.yml" "$tmp/fleet-reference.md" "$tmp/fleet-ok.md" >/dev/null 2>&1
assert "an agreeing fleet knobs table passes" 0 $?

# 8b. A drifted value in the second half of a multi-knob row is caught, so the
#     positional pairing is not just checking the first column.
cat >"$tmp/fleet-multi-drift.md" <<'EOF'
# Fixture fleet doc

| Knob | The capability (core) | The value (yours) | Default, and why it is the safe one |
| --- | --- | --- | --- |
| `simple_knob` | A capability | A value | `per-step` — because it is the safe direction |
| `first_knob` / `second_knob` | A capability | A value | `opus` / `haiku` — judgment-heavy work on the strong tier |
EOF
out="$(/bin/bash "$CHECKER" "$tmp/fleet-config.yml" "$tmp/fleet-reference.md" "$tmp/fleet-multi-drift.md" 2>&1)"
assert "a drifted value inside a multi-knob row fails" 1 $?
assert_contains "the multi-knob failure names the knob" "$out" "second_knob"

# 8c. A knob documented in the fleet table but absent from the config is a
#     failure, not a warning: the fleet table restates config defaults, so a
#     name it carries that the config does not have is a broken restatement.
cat >"$tmp/fleet-ghost.md" <<'EOF'
# Fixture fleet doc

| Knob | The capability (core) | The value (yours) | Default, and why it is the safe one |
| --- | --- | --- | --- |
| `simple_knob` | A capability | A value | `per-step` — because it is the safe direction |
| `ghost_knob` | A capability | A value | `on` — because it is the safe direction |
EOF
out="$(/bin/bash "$CHECKER" "$tmp/fleet-config.yml" "$tmp/fleet-reference.md" "$tmp/fleet-ghost.md" 2>&1)"
assert "a fleet knob absent from the config fails" 1 $?
assert_contains "the absent-knob failure names the knob" "$out" "ghost_knob"

# 9. Fail-closed, symmetric with the config side: a knobs table that parses to
#    zero rows is an error, not a vacuous pass (REQ-H1.3).
cat >"$tmp/fleet-zero.md" <<'EOF'
# Fixture fleet doc

| Knob | The capability (core) | The value (yours) | Default, and why it is the safe one |
| --- | --- | --- | --- |

Prose after an empty table.
EOF
out="$(/bin/bash "$CHECKER" "$tmp/fleet-config.yml" "$tmp/fleet-reference.md" "$tmp/fleet-zero.md" 2>&1)"
assert "a zero-row knobs table fails closed" 2 $?
assert_contains "the zero-row knobs diagnostic names the surface" "$out" "knobs table"

cat >"$tmp/fleet-noheader.md" <<'EOF'
# Fixture fleet doc

No knobs table at all.
EOF
out="$(/bin/bash "$CHECKER" "$tmp/fleet-config.yml" "$tmp/fleet-reference.md" "$tmp/fleet-noheader.md" 2>&1)"
assert "an unparseable knobs table fails closed" 2 $?

# 9b. A row whose knob-name count and default-value count disagree cannot be
#     paired, so it fails closed rather than pairing the first N silently.
cat >"$tmp/fleet-unpaired.md" <<'EOF'
# Fixture fleet doc

| Knob | The capability (core) | The value (yours) | Default, and why it is the safe one |
| --- | --- | --- | --- |
| `first_knob` / `second_knob` | A capability | A value | `opus` — one value for two knobs |
EOF
out="$(/bin/bash "$CHECKER" "$tmp/fleet-config.yml" "$tmp/fleet-reference.md" "$tmp/fleet-unpaired.md" 2>&1)"
assert "an unpairable knobs row fails closed" 2 $?
assert_contains "the unpairable-row diagnostic names the knob" "$out" "first_knob"

# 9c. A row with no backticked default at all is unparseable, not a free pass.
cat >"$tmp/fleet-novalue.md" <<'EOF'
# Fixture fleet doc

| Knob | The capability (core) | The value (yours) | Default, and why it is the safe one |
| --- | --- | --- | --- |
| `simple_knob` | A capability | A value | it depends on the host |
EOF
/bin/bash "$CHECKER" "$tmp/fleet-config.yml" "$tmp/fleet-reference.md" "$tmp/fleet-novalue.md" >/dev/null 2>&1
assert "a knobs row with no backticked default fails closed" 2 $?

# 9d. A quoted config value compares on the value, not on its YAML spelling —
#     both quote styles, as the parser's own comment claims.
cat >"$tmp/fleet-config-quoted.yml" <<'EOF'
simple_knob: "per-step"
first_knob: 'opus'
second_knob: sonnet
EOF
/bin/bash "$CHECKER" "$tmp/fleet-config-quoted.yml" "$tmp/fleet-reference.md" "$tmp/fleet-ok.md" >/dev/null 2>&1
assert "quoted config values compare on the value" 0 $?

# 9e. Skipping the fleet arm is never silent: a two-argument invocation says
#     so on stderr, so a caller cannot believe a tether ran that did not.
err="$(/bin/bash "$CHECKER" "$tmp/fleet-config.yml" "$tmp/fleet-reference.md" 2>&1 >/dev/null)"
assert "a two-argument invocation still succeeds" 0 $?
assert_contains "the skipped fleet arm is announced" "$err" "fleet-knob tether skipped"

# 9f. The checker must not depend on writing a scratch file into TMPDIR (a
#     predictable name in a world-writable directory is a symlink-following
#     write; the repo's convention is mktemp templates). Proven by behaviour:
#     with TMPDIR unwritable, the malformed-table diagnostic still comes
#     through intact.
mkdir -p "$tmp/readonly-tmp"
chmod 500 "$tmp/readonly-tmp"
if [ -w "$tmp/readonly-tmp" ]; then
  # Root writes through mode 500, so the fixture cannot be built and the
  # failure mode is unobservable. Skip rather than fail, matching the
  # convention the sibling suites already use for permission fixtures
  # (test-config-get.sh, test-install-writer.sh, test-check-workflow-posture.sh).
  echo "skip: unwritable-TMPDIR case (running as root)"
else
  out="$(TMPDIR="$tmp/readonly-tmp" /bin/bash "$CHECKER" \
    "$tmp/fleet-config.yml" "$tmp/fleet-reference.md" "$tmp/fleet-unpaired.md" 2>&1)"
  assert "an unwritable TMPDIR does not degrade the diagnostic" 2 $?
  assert_contains "the diagnostic survives an unwritable TMPDIR" "$out" "first_knob"
fi
chmod 700 "$tmp/readonly-tmp"

# 10. A missing fleet doc is an error, matching the other two inputs.
/bin/bash "$CHECKER" "$tmp/fleet-config.yml" "$tmp/fleet-reference.md" "$tmp/no-such-fleet.md" >/dev/null 2>&1
assert "missing fleet doc is an error" 2 $?

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-options-reference tests passed"
