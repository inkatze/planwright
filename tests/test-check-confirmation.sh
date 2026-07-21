#!/bin/bash
# Tests for scripts/check-confirmation.sh — the reusable self-contained-
# confirmation structural check (operator-dialogue Task 2, REQ-E1.1, REQ-E1.2,
# REQ-E1.3, REQ-H1.2, D-7). The check asserts a confirmation option set is
# self-contained (every option restates its action and consequence), carries an
# explicit reject option, pre-selects no default, and uses no generic
# OK/Yes/No/Approve labels or stem.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-confirmation.sh"

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
  # assert_contains <label> <needle> <haystack>
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (output lacks '$2'): $3" >&2
      failures=$((failures + 1))
      ;;
  esac
}

if [ ! -f "$CHECKER" ]; then
  echo "FAIL: checker script missing at $CHECKER" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# A canonical self-contained confirmation: a restating stem, an action option
# and an explicit reject option, each with a consequence, no default.
cat >"$tmp/good.json" <<'EOF'
{
  "question": "Sign off the operator-dialogue kickoff brief and flip the spec to Ready?",
  "options": [
    { "label": "Sign off and open the draft PR",
      "description": "Records the sign-off, flips Draft to Ready, and opens a draft PR; execution can begin." },
    { "label": "Hold as Draft, do not sign off",
      "description": "Leaves the spec at Draft with no PR; nothing downstream changes.",
      "reject": true }
  ]
}
EOF

# 1. The canonical confirmation passes.
/bin/bash "$CHECKER" "$tmp/good.json" >/dev/null 2>&1
assert "self-contained confirmation passes" 0 $?

# 1b. stdin input works identically.
/bin/bash "$CHECKER" <"$tmp/good.json" >/dev/null 2>&1
assert "stdin input passes" 0 $?

# 1c. A grounded recommendation MAY be marked without being a pre-selected
#     default (recommendation != default; REQ-D1.4 / REQ-E1.2). It must pass.
cat >"$tmp/recommended.json" <<'EOF'
{
  "question": "Adopt the derived full-CI command `mise run check` for this unit?",
  "options": [
    { "label": "Use `mise run check`",
      "description": "Runs the repo's aggregate CI gate before convergence.",
      "recommended": true },
    { "label": "Pick a narrower command",
      "description": "Re-prompts for a specific command; the aggregate is skipped.",
      "reject": true }
  ]
}
EOF
/bin/bash "$CHECKER" "$tmp/recommended.json" >/dev/null 2>&1
assert "a marked (not pre-selected) recommendation passes" 0 $?

# 2. An option with no description is not self-contained (REQ-E1.1).
cat >"$tmp/no-consequence.json" <<'EOF'
{
  "question": "Sign off the kickoff brief and flip the spec to Ready?",
  "options": [
    { "label": "Sign off and open the draft PR" },
    { "label": "Hold as Draft, do not sign off",
      "description": "Leaves the spec at Draft.", "reject": true }
  ]
}
EOF
out="$(/bin/bash "$CHECKER" "$tmp/no-consequence.json" 2>&1)"
assert "option without a consequence fails" 1 $?
assert_contains "names NO_CONSEQUENCE" "NO_CONSEQUENCE" "$out"

# 3. A pre-selected default is rejected (REQ-E1.2).
cat >"$tmp/defaulted.json" <<'EOF'
{
  "question": "Sign off the kickoff brief and flip the spec to Ready?",
  "options": [
    { "label": "Sign off and open the draft PR",
      "description": "Records the sign-off and opens a draft PR.",
      "default": true },
    { "label": "Hold as Draft, do not sign off",
      "description": "Leaves the spec at Draft.", "reject": true }
  ]
}
EOF
out="$(/bin/bash "$CHECKER" "$tmp/defaulted.json" 2>&1)"
assert "pre-selected default fails" 1 $?
assert_contains "names DEFAULT_PRESELECTED" "DEFAULT_PRESELECTED" "$out"

# 3b. `preselected` and `selected` are treated as defaults too.
cat >"$tmp/preselected.json" <<'EOF'
{
  "question": "Sign off the kickoff brief and flip the spec to Ready?",
  "options": [
    { "label": "Sign off and open the draft PR",
      "description": "Records the sign-off.", "preselected": true },
    { "label": "Hold as Draft, do not sign off",
      "description": "Leaves the spec at Draft.", "reject": true }
  ]
}
EOF
/bin/bash "$CHECKER" "$tmp/preselected.json" >/dev/null 2>&1
assert "preselected flag fails" 1 $?

# 4. A confirmation with no reject option fails (REQ-E1.2).
cat >"$tmp/no-reject.json" <<'EOF'
{
  "question": "Sign off the kickoff brief and flip the spec to Ready?",
  "options": [
    { "label": "Sign off and open the draft PR",
      "description": "Records the sign-off and opens a draft PR." },
    { "label": "Sign off and hand back to orchestrate",
      "description": "Records the sign-off and returns control to the tower." }
  ]
}
EOF
out="$(/bin/bash "$CHECKER" "$tmp/no-reject.json" 2>&1)"
assert "missing reject option fails" 1 $?
assert_contains "names NO_REJECT" "NO_REJECT" "$out"

# 5. Generic option labels are flagged (REQ-E1.3).
cat >"$tmp/generic-label.json" <<'EOF'
{
  "question": "Sign off the kickoff brief and flip the spec to Ready?",
  "options": [
    { "label": "Yes", "description": "Records the sign-off and opens a draft PR." },
    { "label": "No", "description": "Leaves the spec at Draft.", "reject": true }
  ]
}
EOF
out="$(/bin/bash "$CHECKER" "$tmp/generic-label.json" 2>&1)"
assert "generic Yes/No labels fail" 1 $?
assert_contains "names GENERIC_LABEL" "GENERIC_LABEL" "$out"

# 6. A generic bare stem is flagged (REQ-E1.3).
cat >"$tmp/generic-stem.json" <<'EOF'
{
  "question": "Approve?",
  "options": [
    { "label": "Sign off and open the draft PR",
      "description": "Records the sign-off and opens a draft PR." },
    { "label": "Hold as Draft, do not sign off",
      "description": "Leaves the spec at Draft.", "reject": true }
  ]
}
EOF
out="$(/bin/bash "$CHECKER" "$tmp/generic-stem.json" 2>&1)"
assert "generic bare stem fails" 1 $?
assert_contains "names STEM_GENERIC" "STEM_GENERIC" "$out"

# 6b. A missing/empty stem fails (REQ-E1.1).
cat >"$tmp/no-stem.json" <<'EOF'
{
  "question": "   ",
  "options": [
    { "label": "Sign off and open the draft PR",
      "description": "Records the sign-off." },
    { "label": "Hold as Draft", "description": "Leaves the spec at Draft.", "reject": true }
  ]
}
EOF
out="$(/bin/bash "$CHECKER" "$tmp/no-stem.json" 2>&1)"
assert "empty stem fails" 1 $?
assert_contains "names STEM_MISSING" "STEM_MISSING" "$out"

# 7. Fewer than two options is not a real choice (REQ-E1.2).
cat >"$tmp/one-option.json" <<'EOF'
{
  "question": "Sign off the kickoff brief and flip the spec to Ready?",
  "options": [
    { "label": "Sign off and open the draft PR",
      "description": "Records the sign-off." }
  ]
}
EOF
out="$(/bin/bash "$CHECKER" "$tmp/one-option.json" 2>&1)"
assert "single-option confirmation fails" 1 $?
assert_contains "names OPTIONS_TOO_FEW" "OPTIONS_TOO_FEW" "$out"

# 8. An array of confirmations validates each; one bad entry fails the run and
#    the violation names the offending index.
cat >"$tmp/array-mixed.json" <<'EOF'
[
  {
    "question": "Sign off the kickoff brief and flip the spec to Ready?",
    "options": [
      { "label": "Sign off and open the draft PR", "description": "Records the sign-off." },
      { "label": "Hold as Draft", "description": "Leaves the spec at Draft.", "reject": true }
    ]
  },
  {
    "question": "OK?",
    "options": [
      { "label": "Yes", "description": "Proceeds." },
      { "label": "No", "description": "Stops.", "reject": true }
    ]
  }
]
EOF
out="$(/bin/bash "$CHECKER" "$tmp/array-mixed.json" 2>&1)"
assert "array with one bad confirmation fails" 1 $?
assert_contains "violation names confirmation #1" "confirmation #1" "$out"

# 8b. An all-good array passes.
cat >"$tmp/array-good.json" <<'EOF'
[
  {
    "question": "Sign off the kickoff brief and flip the spec to Ready?",
    "options": [
      { "label": "Sign off and open the draft PR", "description": "Records the sign-off." },
      { "label": "Hold as Draft", "description": "Leaves the spec at Draft.", "reject": true }
    ]
  },
  {
    "question": "Adopt `mise run check` as the CI command for this unit?",
    "options": [
      { "label": "Use `mise run check`", "description": "Runs the aggregate gate." },
      { "label": "Pick a narrower command", "description": "Re-prompts.", "reject": true }
    ]
  }
]
EOF
/bin/bash "$CHECKER" "$tmp/array-good.json" >/dev/null 2>&1
assert "all-good array passes" 0 $?

# 9. Invalid JSON is a usage error (exit 2), not a silent pass or an exit-1
#    violation.
printf '{ this is not json ' >"$tmp/bad.json"
/bin/bash "$CHECKER" "$tmp/bad.json" >/dev/null 2>&1
assert "invalid JSON is a usage error" 2 $?

# 10. Zero confirmations fails closed (a mis-fed check must not silently pass).
printf '[]' >"$tmp/empty.json"
out="$(/bin/bash "$CHECKER" "$tmp/empty.json" 2>&1)"
assert "empty confirmation set fails closed" 2 $?
assert_contains "empty set is the checker's diagnostic" "no confirmations" "$out"

# 11. A missing input file is a clear error, not a silent pass.
/bin/bash "$CHECKER" "$tmp/no-such-file.json" >/dev/null 2>&1
assert "missing input file is an error" 2 $?

# 11b. The file-not-found error must not echo the raw filename argument bytes:
#      a filename carrying a terminal escape sequence is sanitized before it
#      reaches stderr (echo discipline extends to the argv, not only the parsed
#      confirmation values).
esc="$(printf '\033')"
out="$(/bin/bash "$CHECKER" "${esc}[31m/no/such/file.json" 2>&1)"
assert "missing-file error is a usage error" 2 $?
case "$out" in
  *$'\033'*)
    echo "FAIL: raw escape byte from the filename argument reached stderr" >&2
    failures=$((failures + 1))
    ;;
  *) echo "ok: filename argument is sanitized before echo (echo discipline)" ;;
esac

# 12. A malformed (non-object) option is flagged, not crashed on.
cat >"$tmp/malformed-option.json" <<'EOF'
{
  "question": "Sign off the kickoff brief and flip the spec to Ready?",
  "options": [
    "Sign off and open the draft PR",
    { "label": "Hold as Draft", "description": "Leaves the spec at Draft.", "reject": true }
  ]
}
EOF
out="$(/bin/bash "$CHECKER" "$tmp/malformed-option.json" 2>&1)"
assert "malformed option fails" 1 $?
assert_contains "names MALFORMED_OPTION" "MALFORMED_OPTION" "$out"

# 13. The check emits no raw untrusted input bytes: a label carrying a terminal
#     escape sequence never reaches the output (echo discipline; the check
#     reports by index and static rule text only). The fixture is built with jq
#     so the raw ESC byte is emitted as a valid JSON unicode escape (a raw ESC in
#     a JSON string would be invalid JSON, which jq would reject as exit 2); jq
#     decodes it back to a raw ESC in the string value the checker sees.
esc="$(printf '\033')"
jq -n --arg lbl "${esc}[31mSign off${esc}[0m" '{
  question: "Sign off the kickoff brief and flip the spec to Ready?",
  options: [
    { label: $lbl, description: "" },
    { label: "Hold as Draft", description: "Stays at Draft.", reject: true }
  ]
}' >"$tmp/escape.json"
out="$(/bin/bash "$CHECKER" "$tmp/escape.json" 2>&1)"
assert "confirmation with an escape-laden label still fails" 1 $?
case "$out" in
  *$'\033'*)
    echo "FAIL: raw escape byte reached the output" >&2
    failures=$((failures + 1))
    ;;
  *) echo "ok: no raw escape byte in the output (echo discipline)" ;;
esac

# 14. `selected: true` is treated as a pre-selected default too (the third
#     default-marker alias alongside `default` and `preselected`, REQ-E1.2).
cat >"$tmp/selected.json" <<'EOF'
{
  "question": "Sign off the kickoff brief and flip the spec to Ready?",
  "options": [
    { "label": "Sign off and open the draft PR",
      "description": "Records the sign-off.", "selected": true },
    { "label": "Hold as Draft, do not sign off",
      "description": "Leaves the spec at Draft.", "reject": true }
  ]
}
EOF
out="$(/bin/bash "$CHECKER" "$tmp/selected.json" 2>&1)"
assert "selected flag fails" 1 $?
assert_contains "names DEFAULT_PRESELECTED for selected" "DEFAULT_PRESELECTED" "$out"

# 15. A non-string description (a boolean, number, or array) is NOT a self-
#     contained restatement; it must fire NO_CONSEQUENCE exactly as an absent
#     one does (REQ-E1.1). jq's `// ""` only replaces null/false, so a truthy
#     non-string would otherwise stringify and slip past the check — the same
#     string type-guard the stem carries must cover the option fields.
for bad in 'true' '123' '[]' '{"note":"x"}'; do
  printf '{"question":"Sign off the brief and flip the spec to Ready now?","options":[{"label":"Sign off and open the PR","description":%s},{"label":"Hold as Draft","description":"Leaves the spec at Draft.","reject":true}]}' "$bad" >"$tmp/nonstring-desc.json"
  out="$(/bin/bash "$CHECKER" "$tmp/nonstring-desc.json" 2>&1)"
  assert "non-string description ($bad) fails" 1 $?
  assert_contains "non-string description ($bad) names NO_CONSEQUENCE" "NO_CONSEQUENCE" "$out"
done

# 16. A non-string label is likewise not a valid action name; it must fire
#     NO_LABEL (REQ-E1.3), symmetric with the description guard above.
printf '{"question":"Sign off the brief and flip the spec to Ready now?","options":[{"label":true,"description":"Records the sign-off and opens the PR."},{"label":"Hold as Draft","description":"Leaves the spec at Draft.","reject":true}]}' >"$tmp/nonstring-label.json"
out="$(/bin/bash "$CHECKER" "$tmp/nonstring-label.json" 2>&1)"
assert "non-string label fails" 1 $?
assert_contains "non-string label names NO_LABEL" "NO_LABEL" "$out"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-confirmation tests passed"
