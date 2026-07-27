#!/bin/bash
# Tests for scripts/check-instructions.sh — MANIFEST RESOLUTION, the
# injected-context warn floor, fail-loud handling of malformed input, boundary
# semantics, and untrusted-input safety (prompt-hygiene Task 2; REQ-B1.6,
# REQ-B1.7, REQ-B1.8, REQ-B1.9). Sections 8–11 of the pre-split file, numbering
# kept.
#
# Split out of tests/test-check-instructions.sh (guard-coverage Task 6,
# REQ-E1.2, D-9); that file's header carries the guard's full contract and names
# all seven siblings. No assertion changed in the split.
#
# Every input the guard reads here (manifest entries, rule-doc names, hook
# scripts) is PR-controllable and is treated as untrusted data: the hostile-input
# fixtures prove no shell evaluation and no path traversal.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-instructions.sh"

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
      echo "FAIL: $1 (missing '$2')" >&2
      echo "----- output -----" >&2
      printf '%s\n' "$3" >&2
      echo "------------------" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_absent() {
  # assert_absent <label> <needle> <haystack>
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (unexpected '$2')" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -f "$CHECKER" ]; then
  echo "FAIL: checker script missing at $CHECKER" >&2
  exit 1
fi

# make N words of filler prose (N space-separated tokens) on one line. awk
# keeps this O(n) — a shell concat loop is O(n^2) and times out on big fixtures.
words() {
  awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) printf "w "; printf "\n" }'
}

# Build a minimal instruction tree under $1 with the instruction_budget_* knobs
# at their production defaults. Individual tests then add skills/docs/hooks.
scaffold() {
  root="$1"
  mkdir -p "$root/skills" "$root/doctrine" "$root/hooks" "$root/config"
  cat >"$root/config/defaults.yml" <<'EOF'
instruction_budget_skill_warn: 3000
instruction_budget_skill_error: 4250
instruction_budget_doctrine_warn: 2500
instruction_budget_doctrine_error: 4000
instruction_budget_startload_warn: 8000
instruction_budget_startload_error: 10000
instruction_budget_closure_warn: 15000
instruction_budget_closure_error: 20000
instruction_budget_skill_floor: 250
instruction_budget_doctrine_floor: 250
instruction_budget_startload_floor: 500
instruction_budget_closure_floor: 1000
instruction_budget_injected_warn: 200
EOF
  : >"$root/config/instruction-budget-exemptions.txt"
  # An empty hooks.json so the injected-context scan is a clean no-op unless a
  # test registers a hook.
  cat >"$root/hooks/hooks.json" <<'EOF'
{ "hooks": {} }
EOF
}

# make a skill SKILL.md of a given body word-count, with optional manifest lines
# passed as remaining args (each a full "Doctrine: ..." line). No heading is
# written, so a no-manifest SKILL.md's wc -w equals body_words exactly (keeps
# the boundary-threshold fixtures deterministic).
make_skill() {
  root="$1"
  name="$2"
  body_words="$3"
  shift 3
  mkdir -p "$root/skills/$name"
  {
    words "$body_words"
    echo
    for line in "$@"; do
      printf '%s\n' "$line"
    done
  } >"$root/skills/$name/SKILL.md"
}

tmproot="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmproot"' EXIT

########################################################################
# 8. Resolution check (REQ-B1.6): a manifest naming a nonexistent doc fails,
#    naming the doc; point-of-use entries checked identically to run-start.
########################################################################
t8="$tmproot/t8"
scaffold "$t8"
make_skill "$t8" refskill 100 "Doctrine: run-start ghostdoc"
out="$(/bin/bash "$CHECKER" --root "$t8" 2>&1)"
assert_exit "unresolvable run-start reference fails" 1 $?
assert_contains "resolution failure names the missing doc" "ghostdoc" "$out"

t8b="$tmproot/t8b"
scaffold "$t8b"
make_skill "$t8b" refskill 100 "Doctrine: point-of-use ghostpou (somewhere)"
out="$(/bin/bash "$CHECKER" --root "$t8b" 2>&1)"
assert_exit "unresolvable point-of-use reference fails identically" 1 $?
assert_contains "point-of-use resolution failure names the missing doc" "ghostpou" "$out"

########################################################################
# 9. Injected-context warn floor (REQ-B1.7).
########################################################################
# 9a. payload at/over floor warns but exits zero; under-floor still gets a row.
t9="$tmproot/t9"
scaffold "$t9"
# floor is 200 by default; make a 250-word static heredoc payload.
big="$(words 250)"
cat >"$t9/hooks/inject.sh" <<EOF
#!/bin/sh
payload=\$(cat <<'BODY'
$big
BODY
)
printf '{"hookSpecificOutput":{"additionalContext":%s}}\n' "\$(printf '%s' "\$payload" | jq -Rs .)"
EOF
cat >"$t9/hooks/hooks.json" <<'EOF'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/inject.sh" }
] } ] } }
EOF
out="$(/bin/bash "$CHECKER" --root "$t9" 2>&1)"
assert_exit "over-floor injected payload never fails the check" 0 $?
assert_contains "over-floor injected payload warns" "WARN" "$out"

# 9b. a hook whose static prose cannot be extracted is a parse-failure WARNING,
#     never a hard error.
t9b="$tmproot/t9b"
scaffold "$t9b"
cat >"$t9b/hooks/inject.sh" <<'EOF'
#!/bin/sh
msg="hi"; printf '{"hookSpecificOutput":{"additionalContext":"%s"}}' "$msg"
EOF
cat >"$t9b/hooks/hooks.json" <<'EOF'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/inject.sh" }
] } ] } }
EOF
out="$(/bin/bash "$CHECKER" --root "$t9b" 2>&1)"
assert_exit "unextractable injected hook never hard-fails" 0 $?
assert_contains "unextractable injected hook is a parse-failure warning" "parse-failure" "$out"

# 9c. floor override via local.yml moves the warn boundary.
t9c="$tmproot/t9c"
scaffold "$t9c"
mid="$(words 150)" # below the default 200 floor
cat >"$t9c/hooks/inject.sh" <<EOF
#!/bin/sh
payload=\$(cat <<'BODY'
$mid
BODY
)
printf '{"hookSpecificOutput":{"additionalContext":%s}}\n' "\$(printf '%s' "\$payload" | jq -Rs .)"
EOF
cat >"$t9c/hooks/hooks.json" <<'EOF'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/inject.sh" }
] } ] } }
EOF
out="$(/bin/bash "$CHECKER" --root "$t9c" 2>&1)"
assert_absent "under-floor injected payload does not warn" "WARN" "$out"
mkdir -p "$t9c/.claude"
cat >"$t9c/.claude/planwright.local.yml" <<'EOF'
instruction_budget_injected_warn: 100
EOF
out="$(/bin/bash "$CHECKER" --root "$t9c" 2>&1)"
assert_contains "lowered injected floor now warns on the same payload" "WARN" "$out"

########################################################################
# 10. Fail-loud on malformed input + boundary semantics (REQ-B1.8).
########################################################################
# 10a. malformed manifest entry (bad class token) -> error.
t10="$tmproot/t10"
scaffold "$t10"
make_skill "$t10" bad 100 "Doctrine: sometime somedoc"
out="$(/bin/bash "$CHECKER" --root "$t10" 2>&1)"
assert_exit "malformed manifest entry is an error" 1 $?
assert_contains "malformed manifest is diagnosed" "manifest" "$out"

# 10b. malformed exemption entry (unknown form token) -> error.
t10b="$tmproot/t10b"
scaffold "$t10b"
make_skill "$t10b" ok 100
cat >"$t10b/config/instruction-budget-exemptions.txt" <<'EOF'
bogusform|skills/ok/SKILL.md|reason
EOF
out="$(/bin/bash "$CHECKER" --root "$t10b" 2>&1)"
assert_exit "malformed exemption entry is an error" 1 $?

# 10c. missing / non-numeric threshold knob -> error (fail-loud, never a pass).
t10c="$tmproot/t10c"
scaffold "$t10c"
make_skill "$t10c" ok 100
cat >"$t10c/config/defaults.yml" <<'EOF'
instruction_budget_skill_warn: 3000
instruction_budget_skill_error: not-a-number
instruction_budget_doctrine_warn: 2500
instruction_budget_doctrine_error: 4000
instruction_budget_startload_warn: 8000
instruction_budget_startload_error: 10000
instruction_budget_closure_warn: 15000
instruction_budget_closure_error: 20000
instruction_budget_skill_floor: 250
instruction_budget_doctrine_floor: 250
instruction_budget_startload_floor: 500
instruction_budget_closure_floor: 1000
instruction_budget_injected_warn: 200
EOF
out="$(/bin/bash "$CHECKER" --root "$t10c" 2>&1)"
assert_exit "non-numeric threshold knob is a fail-loud error" 1 $?

# 10d. boundary: a body EXACTLY at the error threshold errors (>=).
t10d="$tmproot/t10d"
scaffold "$t10d"
# skill body words: the SKILL.md body count = the filler words only (heading
# and blank line are not words). Put exactly 4250 filler words.
make_skill "$t10d" boundary 4250
out="$(/bin/bash "$CHECKER" --root "$t10d" 2>&1)"
assert_exit "count exactly at the error threshold errors (>=)" 1 $?

# 10e. boundary: a body exactly at the warn threshold warns (>=), exits zero.
t10e="$tmproot/t10e"
scaffold "$t10e"
make_skill "$t10e" boundary 3000
out="$(/bin/bash "$CHECKER" --root "$t10e" 2>&1)"
assert_exit "count exactly at the warn threshold does not fail" 0 $?
assert_contains "count exactly at the warn threshold warns (>=)" "WARN" "$out"

########################################################################
# 11. Untrusted-input safety (REQ-B1.9).
########################################################################
# 11a. a manifest doc-name with shell metacharacters / traversal is rejected as
#      malformed (name validated before any path is formed), never evaluated.
t11="$tmproot/t11"
scaffold "$t11"
probe="$t11/PWNED"
make_skill "$t11" evil 100 "Doctrine: run-start ../../etc/passwd"
out="$(/bin/bash "$CHECKER" --root "$t11" 2>&1)"
assert_exit "traversal doc-name is rejected (malformed), not resolved" 1 $?
assert_absent "traversal doc-name did not escape the doctrine root" "root:/etc/passwd" "$out"

t11b="$tmproot/t11b"
scaffold "$t11b"
# shellcheck disable=SC2016 # the $(touch ...) is a hostile literal, must NOT expand
make_skill "$t11b" evil 100 'Doctrine: run-start $(touch '"$probe"')'
out="$(/bin/bash "$CHECKER" --root "$t11b" 2>&1)"
rc=$?
if [ -e "$probe" ]; then
  echo "FAIL: manifest doc-name was shell-evaluated (probe created)" >&2
  failures=$((failures + 1))
else
  echo "ok: hostile manifest doc-name is data, never evaluated"
fi
assert_exit "metacharacter doc-name is malformed, not evaluated" 1 "$rc"

# 11b. an exemption reason full of metacharacters is echoed as data, never run.
t11c="$tmproot/t11c"
scaffold "$t11c"
probe2="$t11c/PWNED2"
make_skill "$t11c" fat 5000
# shellcheck disable=SC2016 # the $(touch ...) is a hostile literal, must NOT expand
printf 'exempt|skills/fat/SKILL.md|$(touch %s) reason\n' "$probe2" \
  >"$t11c/config/instruction-budget-exemptions.txt"
out="$(/bin/bash "$CHECKER" --root "$t11c" 2>&1)"
if [ -e "$probe2" ]; then
  echo "FAIL: exemption reason was shell-evaluated (probe created)" >&2
  failures=$((failures + 1))
else
  echo "ok: hostile exemption reason is data, never evaluated"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-instructions resolution/fail-loud tests passed"
