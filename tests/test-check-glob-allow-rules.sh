#!/bin/bash
# Tests for scripts/check-glob-allow-rules.sh — the correct-glob allow-rule
# discipline check (fleet-hardening Task 6, D-6, REQ-B1.3, REQ-E1.3).
#
# Two behaviours under test:
#   1. Footgun scan — flag a path-scoped `Bash(<dir>/:*)` allow/deny rule (the
#      word-boundary form that never matches `<dir>/<file>`), while passing the
#      correct `Bash(<dir>/*)` form and the legitimate command globs
#      (`Bash(git status:*)`, `Bash(mise run:*)`), which must NOT be flagged.
#   2. Doc-presence — the correct-form guidance exists and is cross-referenced
#      from the ghost-text (D-5) and, once it exists, the tower-guard (D-8) docs.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-glob-allow-rules.sh"

failures=0
assert() {
  # assert <name> <expected-exit> <actual-exit>
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

# --- 1. Footgun scan --------------------------------------------------------

# 1a. The real repo passes the full check (footgun scan over the shipped config
#     profiles + doc-presence): every shipped path-scoped rule is
#     `/*`, and the guidance + ghost-text cross-reference exist.
/bin/bash "$CHECKER" >/dev/null 2>&1
assert "real repo passes the full check (footgun + docs)" 0 $?

# 1b. A path-scoped `:*` rule is flagged (the never-match footgun).
cat >"$tmp/footgun.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(/abs/path/to/planwright/scripts/:*)"
    ]
  }
}
EOF
/bin/bash "$CHECKER" "$tmp/footgun.json" >/dev/null 2>&1
assert "path-scoped Bash(<dir>/:*) is flagged" 1 $?

# 1c. The correct `Bash(<dir>/*)` path form passes.
cat >"$tmp/correct.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(/abs/path/to/planwright/scripts/*)"
    ]
  }
}
EOF
/bin/bash "$CHECKER" "$tmp/correct.json" >/dev/null 2>&1
assert "correct Bash(<dir>/*) path form passes" 0 $?

# 1d. Legitimate command globs are NOT flagged (the false-positive guard):
#     `:*` after a command word is the correct command-boundary form.
cat >"$tmp/commands.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(mise run:*)",
      "Bash(gh pr view:*)"
    ],
    "deny": [
      "Bash(git push --force:*)",
      "Bash(git commit --amend:*)"
    ]
  }
}
EOF
/bin/bash "$CHECKER" "$tmp/commands.json" >/dev/null 2>&1
assert "legitimate command globs are not flagged" 0 $?

# 1e. A footgun in a deny array is flagged too (a path-scoped deny that never
#     matches is a silent guard hole).
cat >"$tmp/footgun-deny.json" <<'EOF'
{
  "permissions": {
    "deny": [
      "Bash(/etc/secret/:*)"
    ]
  }
}
EOF
/bin/bash "$CHECKER" "$tmp/footgun-deny.json" >/dev/null 2>&1
assert "path-scoped :* in a deny array is flagged" 1 $?

# 1f. A mixed fixture: the one footgun among correct rules is still caught.
cat >"$tmp/mixed.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(git status:*)",
      "Bash(/opt/tools/*)",
      "Bash(/opt/tools/:*)"
    ]
  }
}
EOF
/bin/bash "$CHECKER" "$tmp/mixed.json" >/dev/null 2>&1
assert "a footgun among correct rules is caught" 1 $?

# 1g. Prose that mentions the forbidden token (e.g. an `_about` field) is NOT a
#     rule entry and must not be flagged — only standalone array entries count.
cat >"$tmp/prose.json" <<'EOF'
{
  "_about": "Path-scoped allow entries use the trailing /* glob, never a directory :* form which never matches <dir>/<file>.",
  "permissions": {
    "allow": [
      "Bash(git status:*)",
      "Bash(/opt/tools/*)"
    ]
  }
}
EOF
/bin/bash "$CHECKER" "$tmp/prose.json" >/dev/null 2>&1
assert "a footgun-shaped token in prose (not an array entry) is not flagged" 0 $?

# 1h. An unreadable input file fails closed (never reported clean).
/bin/bash "$CHECKER" "$tmp/does-not-exist.json" >/dev/null 2>&1
assert "a missing input file fails closed (usage error)" 2 $?

# --- 2. Doc-presence --------------------------------------------------------

# 2a. Doc-presence passes against the real repo docs (guidance heading in
#     overlays.md, worker-settings note, ghost-text cross-reference in fleet.md;
#     tower-settings cross-ref deferred until config/tower-settings.json exists).
/bin/bash "$CHECKER" --docs >/dev/null 2>&1
assert "doc-presence passes against real repo docs" 0 $?

# 2b. Doc-presence fails when the guidance section is absent.
mkdir -p "$tmp/docs" "$tmp/config"
: >"$tmp/docs/overlays.md"
: >"$tmp/docs/fleet.md"
: >"$tmp/config/worker-settings.json"
GLOB_ALLOW_OVERLAYS="$tmp/docs/overlays.md" \
  GLOB_ALLOW_GHOST_DOC="$tmp/docs/fleet.md" \
  GLOB_ALLOW_WORKER_SETTINGS="$tmp/config/worker-settings.json" \
  GLOB_ALLOW_TOWER_SETTINGS="$tmp/config/tower-settings.json" \
  /bin/bash "$CHECKER" --docs >/dev/null 2>&1
assert "doc-presence fails when the guidance is missing" 1 $?

# 2c. Doc-presence passes with a minimal well-formed fixture doc set, and the
#     tower-settings cross-ref is required once config/tower-settings.json
#     exists (proving the conditional gate enforces Task 7's cross-reference).
GUIDE_HEADING="### Path-scoped allow rules use the slash-star glob"
GUIDE_LINK="overlays.md#path-scoped-allow-rules-use-the-slash-star-glob"
NOTE_MARKER="path-scoped allow entries use the trailing"

cat >"$tmp/docs/overlays.md" <<EOF
$GUIDE_HEADING

Use the trailing \`/*\` glob for a path-scoped allow rule.
EOF
cat >"$tmp/docs/fleet.md" <<EOF
## Ghost-text prevention

See the [glob discipline]($GUIDE_LINK) when adding allow rules.
EOF
cat >"$tmp/config/worker-settings.json" <<EOF
{ "_about": "$NOTE_MARKER /* glob." }
EOF
# No tower-settings.json yet: the tower cross-ref is deferred (vacuous pass).
GLOB_ALLOW_OVERLAYS="$tmp/docs/overlays.md" \
  GLOB_ALLOW_GHOST_DOC="$tmp/docs/fleet.md" \
  GLOB_ALLOW_WORKER_SETTINGS="$tmp/config/worker-settings.json" \
  GLOB_ALLOW_TOWER_SETTINGS="$tmp/config/tower-settings.json" \
  /bin/bash "$CHECKER" --docs >/dev/null 2>&1
assert "doc-presence passes with guidance + ghost-text ref, tower deferred" 0 $?

# Now the tower-settings doc exists but omits the note: enforced.
cat >"$tmp/config/tower-settings.json" <<EOF
{ "_about": "tower settings with no glob-discipline note" }
EOF
GLOB_ALLOW_OVERLAYS="$tmp/docs/overlays.md" \
  GLOB_ALLOW_GHOST_DOC="$tmp/docs/fleet.md" \
  GLOB_ALLOW_WORKER_SETTINGS="$tmp/config/worker-settings.json" \
  GLOB_ALLOW_TOWER_SETTINGS="$tmp/config/tower-settings.json" \
  /bin/bash "$CHECKER" --docs >/dev/null 2>&1
assert "tower-settings note required once the profile exists" 1 $?

# With the note present in the tower-settings doc, it passes.
cat >"$tmp/config/tower-settings.json" <<EOF
{ "_about": "$NOTE_MARKER /* glob (see docs/overlays.md)." }
EOF
GLOB_ALLOW_OVERLAYS="$tmp/docs/overlays.md" \
  GLOB_ALLOW_GHOST_DOC="$tmp/docs/fleet.md" \
  GLOB_ALLOW_WORKER_SETTINGS="$tmp/config/worker-settings.json" \
  GLOB_ALLOW_TOWER_SETTINGS="$tmp/config/tower-settings.json" \
  /bin/bash "$CHECKER" --docs >/dev/null 2>&1
assert "doc-presence passes once the tower-settings note is added" 0 $?

# --- 3. No LLM in the decision path (REQ-E1.3) ------------------------------

# 3. A negative assertion: the check's source invokes no model/API — no curl,
#    wget, claude, anthropic, or openai call in its decision path.
if grep -Eq '\b(curl|wget|claude|anthropic|openai)\b' "$CHECKER"; then
  echo "FAIL: checker references a network/model call in its decision path (REQ-E1.3)" >&2
  failures=$((failures + 1))
else
  echo "ok: no model/API call in the check's decision path (REQ-E1.3)"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed" >&2
  exit 1
fi
echo "all tests passed"
exit 0
