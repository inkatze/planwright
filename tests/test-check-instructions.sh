#!/bin/bash
# Tests for scripts/check-instructions.sh — the instruction-hygiene size guard
# and audit tool (prompt-hygiene Task 2; REQ-A1.1, REQ-A1.3, REQ-A1.4,
# REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5, REQ-B1.6, REQ-B1.7,
# REQ-B1.8, REQ-B1.9). The guard measures word/line counts for every
# instruction file, computes manifest-derived start-load and closure per skill,
# scans hooks.json-registered injected-context hooks statically, enforces the
# budgets with two suppression forms, and emits a ranked --audit report.
#
# Fixtures below build minimal instruction trees with known word counts so the
# arithmetic is assertable. Every input the guard reads (manifest entries,
# exemption text, rule-doc names, hook scripts) is PR-controllable and is
# treated as untrusted data: the hostile-input fixtures prove no shell
# evaluation and no path traversal.
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

make_doc() {
  # make_doc <root> <name> <words>; wc -w of the doc equals <words> exactly.
  root="$1"
  name="$2"
  {
    words "$3"
    echo
  } >"$root/doctrine/$name.md"
}

# raise the doctrine per-file floor in a fixture so a large run-start/point-of-use
# doc does not trip its own per-file budget — isolating the start-load/closure
# budget under test.
lift_doctrine_floor() {
  mkdir -p "$1/.claude"
  cat >>"$1/.claude/planwright.local.yml" <<'EOF'
instruction_budget_doctrine_warn: 99999
instruction_budget_doctrine_error: 99999
EOF
}

tmproot="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmproot"' EXIT

########################################################################
# 0. Real repo passes with the seeded transitional per-file allowances in
#    place (Task 2 Done-when: `mise run check` passes on the repo).
########################################################################
out="$(/bin/bash "$CHECKER" 2>&1)"
assert_exit "real repo passes the guard (seeded allowances in place)" 0 $?

# The audit over the real repo names the seeded per-file offenders as
# pending-diet, not as hard failures.
aud="$(/bin/bash "$CHECKER" --audit 2>&1)"
assert_contains "audit lists orchestrate SKILL.md" "skills/orchestrate/SKILL.md" "$aud"
assert_contains "audit marks a seeded offender pending-diet" "pending-diet" "$aud"
# The offender shortlist names each seeded over-budget file even though a
# transitional allowance keeps CI green (suppression governs the exit code, not
# offender status — the shortlist drives the Task 5-7 diet plans, REQ-A1.3).
sl="${aud##*Offender shortlist}"
assert_contains "shortlist names orchestrate offender" "skills/orchestrate/SKILL.md" "$sl"
assert_contains "shortlist names spec-format offender" "doctrine/spec-format.md" "$sl"

########################################################################
# 1. Ranked report (REQ-A1.1): every file ranked by words, line counts present,
#    doctrine/README.md excluded from the per-file walk.
########################################################################
t1="$tmproot/t1"
scaffold "$t1"
make_skill "$t1" alpha 100
make_skill "$t1" beta 50
make_doc "$t1" ruleone 200
make_doc "$t1" README 9999     # index: must be EXCLUDED from the walk
: >"$t1/doctrine/emptyrule.md" # empty doc: still a row, 0 words (REQ-A1.1)
aud="$(/bin/bash "$CHECKER" --audit --root "$t1" 2>&1)"
assert_contains "ranked report includes a skill file" "skills/alpha/SKILL.md" "$aud"
assert_contains "ranked report includes a doctrine file" "doctrine/ruleone.md" "$aud"
assert_contains "ranked report shows word counts" "words=" "$aud"
assert_contains "ranked report shows line counts" "lines=" "$aud"
assert_absent "doctrine/README.md excluded from per-file walk" "doctrine/README.md" "$aud"
assert_contains "empty doctrine doc still appears as a 0-word row" "words=0 lines=0 doctrine/emptyrule.md" "$aud"
# An unsuppressed file must carry NO suppression tag: the kind column ([skill]/
# [doctrine]) must not leak into the tag slot for a file with no exemption.
assert_absent "unsuppressed skill carries no leaked [skill] tag" "[skill]" "$aud"
assert_absent "unsuppressed doc carries no leaked [doctrine] tag" "[doctrine]" "$aud"
# Ranked: alpha(100+) must appear before beta(50+) in the per-file section.
alpha_pos="${aud%%skills/alpha/SKILL.md*}"
beta_pos="${aud%%skills/beta/SKILL.md*}"
if [ "${#alpha_pos}" -lt "${#beta_pos}" ]; then
  echo "ok: per-file report is ranked by words (alpha before beta)"
else
  echo "FAIL: report not ranked by words" >&2
  failures=$((failures + 1))
fi

########################################################################
# 2. Start-load and closure computation (REQ-A1.2).
#    body=100, run-start doc=200, point-of-use doc=500.
#    start-load = 100 + 200 = 300 ; closure = 300 + 500 = 800.
########################################################################
t2="$tmproot/t2"
scaffold "$t2"
make_doc "$t2" runstartdoc 200
make_doc "$t2" pointuse 500
make_skill "$t2" gamma 100 \
  "Doctrine: run-start runstartdoc" \
  "Doctrine: point-of-use pointuse (at the widget step)"
# start-load = wc-w(SKILL.md) + wc-w(run-start doc); closure adds point-of-use.
sw=$(wc -w <"$t2/skills/gamma/SKILL.md" | tr -d ' ')
rs=$(wc -w <"$t2/doctrine/runstartdoc.md" | tr -d ' ')
pu=$(wc -w <"$t2/doctrine/pointuse.md" | tr -d ' ')
exp_start=$((sw + rs))
exp_close=$((exp_start + pu))
aud="$(/bin/bash "$CHECKER" --audit --root "$t2" 2>&1)"
assert_contains "start-load computed (body + run-start doc)" "gamma start-load=$exp_start" "$aud"
assert_contains "closure computed (start-load + point-of-use doc)" "closure=$exp_close" "$aud"

# A skill with NO manifest is scored body-only, no error (REQ-A1.2).
t2b="$tmproot/t2b"
scaffold "$t2b"
make_skill "$t2b" nomani 100
out="$(/bin/bash "$CHECKER" --audit --root "$t2b" 2>&1)"
assert_exit "no-manifest skill is not an error" 0 $?
assert_contains "no-manifest skill scored body-only" "nomani start-load=100" "$out"

# An empty (zero-word) SKILL.md is scored 0, not a crash under set -u.
t2c="$tmproot/t2c"
scaffold "$t2c"
mkdir -p "$t2c/skills/empty"
: >"$t2c/skills/empty/SKILL.md"
out="$(/bin/bash "$CHECKER" --audit --root "$t2c" 2>&1)"
assert_exit "empty skill file is handled without a crash" 0 $?
assert_contains "empty skill scored zero start-load" "empty start-load=0" "$out"

########################################################################
# 3. Offender shortlist (REQ-A1.3): contains exactly the over-threshold items.
########################################################################
t3="$tmproot/t3"
scaffold "$t3"
make_skill "$t3" fatskill 5000 # over skill error (4250)
make_skill "$t3" leanskill 100 # under everything
make_doc "$t3" fatdoc 4500     # over doctrine error (4000)
aud="$(/bin/bash "$CHECKER" --audit --root "$t3" 2>&1)"
# grab the shortlist section only
shortlist="${aud##*Offender shortlist}"
assert_contains "shortlist names the over-floor skill" "skills/fatskill/SKILL.md" "$shortlist"
assert_contains "shortlist names the over-floor doctrine file" "doctrine/fatdoc.md" "$shortlist"
assert_absent "shortlist omits the under-budget skill" "leanskill" "$shortlist"

########################################################################
# 4. Injected-context measurement (REQ-A1.4).
#    Hook script emits additionalContext via a quoted heredoc: two static prose
#    lines (5 words each = 10) plus one $(...) interpolation line (excluded).
#    The hook, if executed, would drop a sentinel — the guard must never run it.
########################################################################
t4="$tmproot/t4"
scaffold "$t4"
sentinel="$t4/EXECUTED"
cat >"$t4/hooks/inject.sh" <<EOF
#!/bin/sh
echo ran > "$sentinel"
payload=\$(cat <<'BODY'
one two three four five
dynamic \$(date) value here now
six seven eight nine ten
BODY
)
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \\
  "\$(printf '%s' "\$payload" | jq -Rs .)"
EOF
chmod +x "$t4/hooks/inject.sh"
cat >"$t4/hooks/hooks.json" <<'EOF'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/inject.sh" }
] } ] } }
EOF
aud="$(/bin/bash "$CHECKER" --audit --root "$t4" 2>&1)"
assert_exit "injected-context scan does not fail the check" 0 $?
assert_contains "injected-context hook reported with a class row" "hooks/inject.sh" "$aud"
assert_contains "injected static count excludes the interpolation line" "static=10" "$aud"
if [ -e "$sentinel" ]; then
  echo "FAIL: hook script was executed (sentinel exists)" >&2
  failures=$((failures + 1))
else
  echo "ok: hook script is read statically, never executed"
fi

# 4b. A hook command that passes CLI arguments still resolves to its script and
#     gets a row (REQ-A1.4: every registered injected hook is a row).
cat >"$t4/hooks/hooks.json" <<'EOF'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/inject.sh --session-start" }
] } ] } }
EOF
aud="$(/bin/bash "$CHECKER" --audit --root "$t4" 2>&1)"
assert_contains "hook registered with CLI args still gets a row" "hooks/inject.sh static=10" "$aud"

########################################################################
# 5. Check-aggregate wiring (REQ-B1.1): an over-error file fails; the task is
#    present in the mise.toml check aggregate.
########################################################################
t5="$tmproot/t5"
scaffold "$t5"
make_skill "$t5" toobig 5000
out="$(/bin/bash "$CHECKER" --root "$t5" 2>&1)"
assert_exit "over-error file fails the check" 1 $?
assert_contains "failure names the offending file" "skills/toobig/SKILL.md" "$out"

# mise.toml wiring: a check:instructions task exists and is in the aggregate.
mise_txt="$(cat "$REPO_ROOT/mise.toml")"
assert_contains "mise.toml defines check:instructions" 'tasks."check:instructions"' "$mise_txt"
assert_contains "check aggregate depends on check:instructions" '"check:instructions"' "$mise_txt"

########################################################################
# 6. Budgets, thresholds, and knob override (REQ-B1.2).
#    warn vs error vs pass across a budget class, then a local.yml override.
########################################################################
t6="$tmproot/t6"
scaffold "$t6"
make_skill "$t6" warnskill 3500 # >=3000 warn, <4250 error
out="$(/bin/bash "$CHECKER" --root "$t6" 2>&1)"
assert_exit "warn-level file does not fail" 0 $?
assert_contains "warn-level file is reported as a warning" "WARN" "$out"

# Override: lower the skill error threshold via machine-local config so the same
# 3500-word file now errors (config-get layering exercised).
mkdir -p "$t6/.claude"
cat >"$t6/.claude/planwright.local.yml" <<'EOF'
instruction_budget_skill_error: 3200
EOF
out="$(/bin/bash "$CHECKER" --root "$t6" 2>&1)"
assert_exit "local.yml threshold override flips warn->error" 1 $?

########################################################################
# 7. Exemptions and transitional allowances (REQ-B1.3).
########################################################################
# 7a. permanent exemption suppresses the per-file floor, echoes the reason, and
#     does NOT suppress start-load/closure.
t7="$tmproot/t7"
scaffold "$t7"
# doctrine docs big enough that a skill front-loading them blows BOTH the
# start-load and the closure budgets.
make_doc "$t7" bigdoc 9999  # run-start -> start-load 5000+ + 9999 > 10000 error
make_doc "$t7" widedoc 6000 # point-of-use -> closure > 20000 error
make_skill "$t7" heavy 5000 \
  "Doctrine: run-start bigdoc" \
  "Doctrine: point-of-use widedoc (rare branch)"
lift_doctrine_floor "$t7"
cat >"$t7/config/instruction-budget-exemptions.txt" <<'EOF'
exempt|skills/heavy/SKILL.md|standing rationale: kept large on purpose
EOF
out="$(/bin/bash "$CHECKER" --root "$t7" 2>&1)"
rc=$?
assert_contains "permanent exemption echoes its reason" "standing rationale" "$out"
# the per-file floor is suppressed, but a permanent exemption NEVER suppresses
# start-load or closure (REQ-B1.3a) -> both errors survive -> still exit 1.
assert_exit "permanent exemption does not suppress start-load/closure" 1 "$rc"
assert_contains "start-load error survives the permanent exemption" "start-load over budget" "$out"
assert_contains "closure error survives the permanent exemption" "closure over budget" "$out"

# 7b. reason-less exemption is an error (either form).
t7b="$tmproot/t7b"
scaffold "$t7b"
make_skill "$t7b" x 100
cat >"$t7b/config/instruction-budget-exemptions.txt" <<'EOF'
exempt|skills/x/SKILL.md|
EOF
out="$(/bin/bash "$CHECKER" --root "$t7b" 2>&1)"
assert_exit "reason-less exemption is an error" 1 $?
assert_contains "reason-less error is diagnosed" "reason" "$out"

# a reason-less pending-diet allowance is likewise an error (either form).
t7b2="$tmproot/t7b2"
scaffold "$t7b2"
make_skill "$t7b2" y 5000
printf 'pending-diet|file|skills/y/SKILL.md|Task 9|\n' \
  >"$t7b2/config/instruction-budget-exemptions.txt"
out="$(/bin/bash "$CHECKER" --root "$t7b2" 2>&1)"
assert_exit "reason-less pending-diet allowance is an error" 1 $?
assert_contains "reason-less pending-diet is diagnosed" "reason" "$out"

# 7b2. transitional pending-diet allowance on a PER-FILE offender lets the check
#      pass; removing it re-fails (the per-file transitional form).
t7pf="$tmproot/t7pf"
scaffold "$t7pf"
make_skill "$t7pf" toofat 5000 # over the per-file skill floor (4250)
out="$(/bin/bash "$CHECKER" --root "$t7pf" 2>&1)"
assert_exit "per-file offender fails without an allowance" 1 $?
cat >"$t7pf/config/instruction-budget-exemptions.txt" <<'EOF'
pending-diet|file|skills/toofat/SKILL.md|Task 9|dieted in Task 9
EOF
out="$(/bin/bash "$CHECKER" --root "$t7pf" 2>&1)"
assert_exit "per-file pending-diet allowance lets the check pass" 0 $?
: >"$t7pf/config/instruction-budget-exemptions.txt"
out="$(/bin/bash "$CHECKER" --root "$t7pf" 2>&1)"
assert_exit "removing the per-file allowance re-fails the offender" 1 $?

# 7c. transitional pending-diet allowance on a START-LOAD offender lets the
#     check pass; removing it re-fails.
t7c="$tmproot/t7c"
scaffold "$t7c"
make_doc "$t7c" bigdoc 9999
make_skill "$t7c" heavy 500 "Doctrine: run-start bigdoc"
lift_doctrine_floor "$t7c"
out="$(/bin/bash "$CHECKER" --root "$t7c" 2>&1)"
assert_exit "start-load offender fails without an allowance" 1 $?
cat >"$t7c/config/instruction-budget-exemptions.txt" <<'EOF'
pending-diet|start-load|heavy|Task 7.5|reclassified to point-of-use in Task 7.5
EOF
out="$(/bin/bash "$CHECKER" --root "$t7c" 2>&1)"
assert_exit "start-load pending-diet allowance lets the check pass" 0 $?
# The start-load offender still appears in the --audit shortlist even suppressed
# (REQ-A1.3: the shortlist targets skills over the start-load budget).
aud="$(/bin/bash "$CHECKER" --audit --root "$t7c" 2>&1)"
sl="${aud##*Offender shortlist}"
assert_contains "shortlist names the start-load offender" "start-load heavy" "$sl"

# 7d. transitional pending-diet allowance on a CLOSURE offender (symmetric fix).
t7d="$tmproot/t7d"
scaffold "$t7d"
# closure error is 20000: run-start 9000 + point-of-use 11000 -> closure 20000+.
make_doc "$t7d" rs 9000
make_doc "$t7d" pu 11000
make_skill "$t7d" wide 500 \
  "Doctrine: run-start rs" \
  "Doctrine: point-of-use pu (at a rare branch)"
lift_doctrine_floor "$t7d"
out="$(/bin/bash "$CHECKER" --root "$t7d" 2>&1)"
assert_exit "closure offender fails without an allowance" 1 $?
cat >"$t7d/config/instruction-budget-exemptions.txt" <<'EOF'
pending-diet|closure|wide|Task 9|content diet pending
EOF
out="$(/bin/bash "$CHECKER" --root "$t7d" 2>&1)"
assert_exit "closure pending-diet allowance lets the check pass" 0 $?
aud="$(/bin/bash "$CHECKER" --audit --root "$t7d" 2>&1)"
sl="${aud##*Offender shortlist}"
assert_contains "shortlist names the closure offender" "closure wide" "$sl"

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

########################################################################
# 12. Unreadable instruction file is fail-loud, never silently scored 0.
#     An input that cannot be measured is never counted as under budget
#     (REQ-B1.8), symmetric with the knob fail-loud path: an over-floor
#     SKILL.md that awk cannot open must hard-fail, not slip under the floor
#     because its unmeasured word count defaulted to 0.
########################################################################
t12="$tmproot/t12"
scaffold "$t12"
# a body well over the 4250 error floor; readable, it fails the guard.
make_skill "$t12" unreadable 5000
chmod 000 "$t12/skills/unreadable/SKILL.md"
out="$(/bin/bash "$CHECKER" --root "$t12" 2>&1)"
rc=$?
# restore read permission so the trap's `rm -rf` can clean the fixture up.
chmod 644 "$t12/skills/unreadable/SKILL.md"
assert_exit "unreadable instruction file is a fail-loud error" 1 "$rc"
assert_contains "unreadable-file failure is diagnosed" "could not be measured" "$out"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-instructions tests passed"
