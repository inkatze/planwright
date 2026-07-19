#!/bin/bash
# Tests for scripts/check-instructions.sh — the instruction-hygiene size guard
# and audit tool (prompt-hygiene Task 2; REQ-A1.1, REQ-A1.3, REQ-A1.4,
# REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5, REQ-B1.6, REQ-B1.7,
# REQ-B1.8, REQ-B1.9; instruction-headroom Task 2: REQ-A1.1, REQ-A1.4, REQ-D1.1,
# REQ-D1.6). The guard measures word/line counts for every instruction file,
# computes manifest-derived start-load and closure per skill, scans
# hooks.json-registered injected-context hooks statically, enforces the budgets
# with four suppression forms (exempt / pending-diet / declared-exception /
# raise), enforces per-surface headroom floors with floor-breach and below-target
# warnings and a raise-rationale rule, and emits a ranked --audit report with
# margin columns (section 15).
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

make_doc() {
  # make_doc <root> <name> <words>; wc -w of the doc equals <words> exactly.
  root="$1"
  name="$2"
  {
    words "$3"
    echo
  } >"$root/doctrine/$name.md"
}

# raise the doctrine per-file budget in a fixture so a large run-start/point-of-use
# doc does not trip its own per-file budget — isolating the start-load/closure
# budget under test. Raising a budget knob above its core default now requires a
# recorded rationale (instruction-headroom REQ-A1.4/D-12), so the raise| entries
# are appended to the exemptions file; callers that also write their own
# exemptions must APPEND (`>>`) after this runs, so both survive.
lift_doctrine_floor() {
  mkdir -p "$1/.claude"
  cat >>"$1/.claude/planwright.local.yml" <<'EOF'
instruction_budget_doctrine_warn: 99999
instruction_budget_doctrine_error: 99999
EOF
  cat >>"$1/config/instruction-budget-exemptions.txt" <<'EOF'
raise|instruction_budget_doctrine_warn|99999|fixture: lift the doctrine per-file budget to isolate the start-load/closure budget under test
raise|instruction_budget_doctrine_error|99999|fixture: lift the doctrine per-file budget to isolate the start-load/closure budget under test
EOF
}

tmproot="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmproot"' EXIT

########################################################################
# 0. Real repo passes the guard with no transitional allowances remaining
#    (Task 2 Done-when: `mise run check` passes on the repo; post-Task-7.5
#    the only suppression is the permanent spec-format exemption).
########################################################################
out="$(/bin/bash "$CHECKER" 2>&1)"
assert_exit "real repo passes the guard (no transitional allowances remain)" 0 $?

# Post-Task-7.5 the audit carries no transitional allowance anywhere: the
# Task 3-seeded start-load carries were shed by their diet tasks (REQ-B1.3b;
# the closeout direction REQ-D1.4 forbids any lingering `pending-diet` entry).
aud="$(/bin/bash "$CHECKER" --audit 2>&1)"
assert_contains "audit lists orchestrate SKILL.md" "skills/orchestrate/SKILL.md" "$aud"
assert_absent "audit carries no pending-diet allowance (Task 7.5)" "pending-diet" "$aud"
sl="${aud##*Offender shortlist}"
# Post-Task-5/6/7 the dieted /orchestrate, /execute-task, and /spec-kickoff
# bodies pass with no suppression of their own (REQ-D1.1), so all three are off
# the per-file shortlist; post-Task-7.5 the /spec-kickoff and /spec-draft
# start-load carries are shed too (point-of-use reclassification), so no
# start-load offender remains; spec-format stays on the shortlist as a
# permanent exempt offender (suppression governs the exit code, not offender
# status).
assert_absent "shortlist no longer names the dieted orchestrate" "skills/orchestrate/SKILL.md" "$sl"
assert_absent "shortlist no longer names the dieted execute-task" "skills/execute-task/SKILL.md" "$sl"
assert_absent "shortlist no longer names the dieted spec-kickoff body" "skills/spec-kickoff/SKILL.md" "$sl"
assert_absent "shortlist no longer names the spec-kickoff start-load carry" "start-load spec-kickoff" "$sl"
assert_absent "shortlist no longer names the spec-draft start-load carry" "start-load spec-draft" "$sl"
assert_contains "shortlist names spec-format offender" "doctrine/spec-format.md" "$sl"
sf_row="$(printf '%s\n' "$sl" | grep -F 'doctrine/spec-format.md')"
assert_contains "spec-format offender is tagged exempt" "[exempt]" "$sf_row"

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

# 4c. Interpolation detection covers shell special and positional parameters
#     ($?, $@, $#, $1, ...): such a line is runtime-expanded, so it is EXCLUDED
#     from the static count (REQ-A1.4). Two 5-word prose lines (=10) bracket a
#     `$?` line that must not be counted; a naive `$[A-Za-z_]`-only interp test
#     would miscount it as 4 static words (static=14).
t4c="$tmproot/t4c"
scaffold "$t4c"
# fully-quoted outer heredoc: the hook is written verbatim (never expanded at
# fixture-build time and never executed by the guard, only read statically).
cat >"$t4c/hooks/inject.sh" <<'EOF'
#!/bin/sh
payload=$(cat <<'BODY'
one two three four five
exit status code $?
six seven eight nine ten
BODY
)
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
  "$(printf '%s' "$payload" | jq -Rs .)"
EOF
chmod +x "$t4c/hooks/inject.sh"
cat >"$t4c/hooks/hooks.json" <<'EOF'
{ "hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/inject.sh" }
] } ] } }
EOF
aud="$(/bin/bash "$CHECKER" --audit --root "$t4c" 2>&1)"
assert_exit "special-param interpolation scan does not fail the check" 0 $?
assert_contains "special-param interpolation line excluded from static count" "hooks/inject.sh static=10" "$aud"

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
cat >>"$t7/config/instruction-budget-exemptions.txt" <<'EOF'
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
cat >>"$t7c/config/instruction-budget-exemptions.txt" <<'EOF'
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
cat >>"$t7d/config/instruction-budget-exemptions.txt" <<'EOF'
pending-diet|closure|wide|Task 9|content diet pending
EOF
out="$(/bin/bash "$CHECKER" --root "$t7d" 2>&1)"
assert_exit "closure pending-diet allowance lets the check pass" 0 $?
aud="$(/bin/bash "$CHECKER" --audit --root "$t7d" 2>&1)"
sl="${aud##*Offender shortlist}"
assert_contains "shortlist names the closure offender" "closure wide" "$sl"

########################################################################
# 7e. Closeout mode (REQ-D1.4, Task 8): `--closeout` forbids ANY lingering
#     transitional `pending-diet` allowance (per-file, start-load, or closure).
#     A start-load or closure offender can only be carried by such an allowance
#     (REQ-B1.3b), so this catches a lingering start-load/closure offender, not
#     just per-file ones. Permanent exemptions (REQ-B1.3a) are unaffected. The
#     default mode still honors the transitional mechanism (regression: the 7pf
#     /7c/7d cases above pass an allowance and exit 0 WITHOUT --closeout).
########################################################################
# per-file allowance: passes the default guard, fails under --closeout.
t7e="$tmproot/t7e"
scaffold "$t7e"
make_skill "$t7e" toofat 5000
cat >"$t7e/config/instruction-budget-exemptions.txt" <<'EOF'
pending-diet|file|skills/toofat/SKILL.md|Task 9|dieted in Task 9
EOF
out="$(/bin/bash "$CHECKER" --root "$t7e" 2>&1)"
assert_exit "closeout: per-file allowance still passes the default guard" 0 $?
out="$(/bin/bash "$CHECKER" --closeout --root "$t7e" 2>&1)"
assert_exit "closeout: per-file pending-diet allowance fails --closeout" 1 $?
assert_contains "closeout: failure names the offending target" "skills/toofat/SKILL.md" "$out"
assert_contains "closeout: failure cites the closeout direction" "closeout" "$out"

# start-load allowance: fails under --closeout.
t7e2="$tmproot/t7e2"
scaffold "$t7e2"
make_doc "$t7e2" bigdoc 9999
make_skill "$t7e2" heavy 500 "Doctrine: run-start bigdoc"
lift_doctrine_floor "$t7e2"
cat >>"$t7e2/config/instruction-budget-exemptions.txt" <<'EOF'
pending-diet|start-load|heavy|Task 7.5|reclassified to point-of-use in Task 7.5
EOF
out="$(/bin/bash "$CHECKER" --closeout --root "$t7e2" 2>&1)"
assert_exit "closeout: start-load pending-diet allowance fails --closeout" 1 $?
assert_contains "closeout: failure names the start-load target" "heavy" "$out"

# closure allowance: fails under --closeout.
t7e3="$tmproot/t7e3"
scaffold "$t7e3"
make_doc "$t7e3" rs 9000
make_doc "$t7e3" pu 11000
make_skill "$t7e3" wide 500 \
  "Doctrine: run-start rs" \
  "Doctrine: point-of-use pu (at a rare branch)"
lift_doctrine_floor "$t7e3"
cat >>"$t7e3/config/instruction-budget-exemptions.txt" <<'EOF'
pending-diet|closure|wide|Task 9|content diet pending
EOF
out="$(/bin/bash "$CHECKER" --closeout --root "$t7e3" 2>&1)"
assert_exit "closeout: closure pending-diet allowance fails --closeout" 1 $?
assert_contains "closeout: failure names the closure target" "wide" "$out"

# a permanent exemption is NOT a pending-diet allowance: --closeout tolerates it
# (the per-file floor stays suppressed; no closeout error on its account).
t7e4="$tmproot/t7e4"
scaffold "$t7e4"
make_skill "$t7e4" kept 5000
cat >"$t7e4/config/instruction-budget-exemptions.txt" <<'EOF'
exempt|skills/kept/SKILL.md|standing rationale: kept large on purpose
EOF
out="$(/bin/bash "$CHECKER" --closeout --root "$t7e4" 2>&1)"
assert_exit "closeout: a permanent exemption alone passes --closeout" 0 $?
assert_absent "closeout: permanent exemption raises no closeout error" "closeout" "$out"

# the real repo (post-Task-7.5, only the permanent spec-format exemption)
# passes --closeout: the closeout direction holds on the shipped corpus.
out="$(/bin/bash "$CHECKER" --closeout 2>&1)"
assert_exit "closeout: the real repo passes --closeout (no lingering allowance)" 0 $?

# the mise `check:instructions` task wires the guard in closeout mode so the
# aggregate `check` permanently enforces the Task-8 closeout direction.
assert_contains "check:instructions task runs the guard in --closeout mode" \
  "check-instructions.sh --closeout" "$mise_txt"

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

########################################################################
# 13. Fenced Doctrine examples are documentation, not live manifest entries.
#     The manifest parser tracks the fence CHARACTER (``` vs ~~~) so a
#     different-type fence shown as content inside a block does not close the
#     block early and expose the enclosed Doctrine: example as a real entry —
#     which would raise a false malformed-manifest error (or inflate start-load)
#     on a SKILL.md that merely documents the manifest format.
########################################################################
# 13a. a malformed Doctrine EXAMPLE inside a ```-block wrapped in a ~~~ block
#      must NOT be parsed (no false error, exit 0).
t13="$tmproot/t13"
scaffold "$t13"
mkdir -p "$t13/skills/fenced"
{
  words 100
  echo
  echo '~~~markdown'
  # shellcheck disable=SC2016 # a literal fenced example, never expanded
  echo '```'
  echo 'Doctrine: sometime not-a-real-class'
  # shellcheck disable=SC2016
  echo '```'
  echo '~~~'
} >"$t13/skills/fenced/SKILL.md"
out="$(/bin/bash "$CHECKER" --root "$t13" 2>&1)"
assert_exit "nested-fenced Doctrine example is not parsed as a live entry" 0 $?
assert_absent "fenced example raises no manifest error" "manifest" "$out"

# 13b. a well-formed Doctrine EXAMPLE inside the same nesting must NOT inflate
#      start-load: the skill is scored body-only (the fenced example doc, though
#      large, is documentation and is never loaded). start-load = the SKILL.md's
#      own wc -w (which includes the fenced lines as body prose), NOT + 9000.
t13b="$tmproot/t13b"
scaffold "$t13b"
make_doc "$t13b" bigexample 9000 # would blow start-load if wrongly counted
mkdir -p "$t13b/skills/docskill"
{
  words 100
  echo
  echo '~~~markdown'
  # shellcheck disable=SC2016 # a literal fenced example, never expanded
  echo '```'
  echo 'Doctrine: run-start bigexample'
  # shellcheck disable=SC2016
  echo '```'
  echo '~~~'
} >"$t13b/skills/docskill/SKILL.md"
lift_doctrine_floor "$t13b"
body_b=$(wc -w <"$t13b/skills/docskill/SKILL.md" | tr -d ' ')
out="$(/bin/bash "$CHECKER" --audit --root "$t13b" 2>&1)"
assert_exit "well-formed fenced example does not inflate start-load (exit 0)" 0 $?
assert_contains "fenced example skill scored body-only" "docskill start-load=$body_b" "$out"

# 13c. a REAL (unfenced, column-zero) manifest entry is still parsed after the
#      fence-tracking change — the fix must not stop reading genuine manifests.
t13c="$tmproot/t13c"
scaffold "$t13c"
make_doc "$t13c" realdoc 200
make_skill "$t13c" realmani 100 "Doctrine: run-start realdoc"
sw_c=$(wc -w <"$t13c/skills/realmani/SKILL.md" | tr -d ' ')
exp_c=$((sw_c + 200))
out="$(/bin/bash "$CHECKER" --audit --root "$t13c" 2>&1)"
assert_contains "a genuine unfenced manifest entry is still counted" "realmani start-load=$exp_c" "$out"

########################################################################
# 14. Manifest-completeness assertion (REQ-A1.2). A separate corpus-wide check
#     wired in at Task 3: every skills/*/SKILL.md must declare a doctrine
#     manifest. It is gated by the boolean knob
#     instruction_manifest_completeness_required (config/defaults.yml, true in
#     the shipped repo); absent in every layer it defaults OFF (an adopter not
#     yet on the manifest convention is not forced into it). Distinct from the
#     scoring rule (a manifest-less skill still scores body-only, REQ-A1.2) and
#     from the malformed-manifest error (REQ-B1.8).
########################################################################
# helper: append the completeness knob to a fixture's scaffolded defaults.
set_completeness() {
  # set_completeness <root> <true|false>
  printf 'instruction_manifest_completeness_required: %s\n' "$2" >>"$1/config/defaults.yml"
}

# 14a. assertion ON + a manifest-less skill -> error, naming the skill.
t14="$tmproot/t14"
scaffold "$t14"
set_completeness "$t14" true
make_skill "$t14" nomani 100 # no manifest lines
make_doc "$t14" somedoc 200
make_skill "$t14" hasmani 100 "Doctrine: run-start somedoc"
out="$(/bin/bash "$CHECKER" --root "$t14" 2>&1)"
assert_exit "manifest-completeness ON: a manifest-less skill errors" 1 $?
assert_contains "completeness error names the manifest-less skill" "nomani" "$out"
assert_absent "completeness error does not flag the skill that has a manifest" \
  "hasmani" "$out"

# 14b. same tree, assertion OFF (absent knob) -> body-only score, exit 0.
t14b="$tmproot/t14b"
scaffold "$t14b" # no completeness knob written -> default OFF
make_skill "$t14b" nomani 100
out="$(/bin/bash "$CHECKER" --audit --root "$t14b" 2>&1)"
assert_exit "manifest-completeness absent-knob defaults OFF: no error" 0 $?
assert_contains "manifest-less skill still scored body-only when OFF" \
  "nomani start-load=100" "$out"

# 14c. assertion explicitly false -> manifest-less skill passes.
t14c="$tmproot/t14c"
scaffold "$t14c"
set_completeness "$t14c" false
make_skill "$t14c" nomani 100
out="$(/bin/bash "$CHECKER" --root "$t14c" 2>&1)"
assert_exit "manifest-completeness explicitly OFF: manifest-less skill passes" 0 $?

# 14d. assertion ON + every skill declares a manifest -> passes.
t14d="$tmproot/t14d"
scaffold "$t14d"
set_completeness "$t14d" true
make_doc "$t14d" somedoc 200
make_skill "$t14d" a 100 "Doctrine: run-start somedoc"
make_skill "$t14d" b 100 "Doctrine: point-of-use somedoc (at the step)"
out="$(/bin/bash "$CHECKER" --root "$t14d" 2>&1)"
assert_exit "manifest-completeness ON with all manifests present passes" 0 $?

# 14e. a present-but-non-boolean knob is fail-loud (REQ-B1.8).
t14e="$tmproot/t14e"
scaffold "$t14e"
set_completeness "$t14e" maybe
make_skill "$t14e" nomani 100
out="$(/bin/bash "$CHECKER" --root "$t14e" 2>&1)"
assert_exit "non-boolean completeness knob is a fail-loud error" 1 $?

# 14f. a skill with only a MALFORMED manifest entry has still 'declared' a
#      manifest (it carries a Doctrine: line): the completeness assertion does
#      not additionally flag it manifest-less (its malformed error stands alone).
t14f="$tmproot/t14f"
scaffold "$t14f"
set_completeness "$t14f" true
make_skill "$t14f" garbled 100 "Doctrine: sometime somedoc"
out="$(/bin/bash "$CHECKER" --root "$t14f" 2>&1)"
assert_exit "malformed-manifest skill errors" 1 $?
assert_absent "completeness assertion does not double-flag a malformed-manifest skill" \
  "declares no doctrine manifest" "$out"

########################################################################
# 15. Headroom floors, margins, declared exceptions, and raise rationale
#     (instruction-headroom Task 2: REQ-A1.1, REQ-A1.4, REQ-D1.1, REQ-D1.6).
########################################################################
# 15a. floor-breach: a surface whose margin is strictly below its floor warns on
#      every run (named), never errors. Skill error 4250, floor 250 -> margin 150
#      at 4100 words; 4100 < 4250 so the per-file budget itself does NOT error.
t15a="$tmproot/t15a"
scaffold "$t15a"
make_skill "$t15a" breachy 4100
out="$(/bin/bash "$CHECKER" --root "$t15a" 2>&1)"
assert_exit "floor-breach is a warning, not an error" 0 $?
assert_contains "floor-breach warning fires and names the surface" \
  "floor-breach: skills/breachy/SKILL.md" "$out"

# 15b. compliance (silent): a surface with margin >= 2*floor emits no headroom
#      warning at all.
t15b="$tmproot/t15b"
scaffold "$t15b"
make_skill "$t15b" roomy 100
out="$(/bin/bash "$CHECKER" --root "$t15b" 2>&1)"
assert_absent "a compliant surface emits no floor-breach" "floor-breach" "$out"
assert_absent "a compliant surface emits no below-target" "below-target" "$out"

# 15c. at-floor boundary: margin EXACTLY at the floor is compliant (breach is
#      strict, margin < floor). Skill error 4250, floor 250 -> margin 250 at 4000.
#      It is below the 2*floor target (500), so a below-target warning DOES fire.
t15c="$tmproot/t15c"
scaffold "$t15c"
make_skill "$t15c" atfloor 4000
out="$(/bin/bash "$CHECKER" --root "$t15c" 2>&1)"
assert_exit "at-floor boundary does not error" 0 $?
assert_absent "margin exactly at the floor is not a floor-breach" \
  "floor-breach: skills/atfloor/SKILL.md" "$out"
assert_contains "at-floor margin below target still warns below-target" \
  "below-target: skills/atfloor/SKILL.md" "$out"

# 15d. below-target with and without a declared exception. Skill error 4250,
#      floor 250, target 500 -> margin 350 at 3900 (floor<=margin<target).
t15d="$tmproot/t15d"
scaffold "$t15d"
make_skill "$t15d" bt 3900
out="$(/bin/bash "$CHECKER" --root "$t15d" 2>&1)"
assert_contains "below-target warning fires and names the surface" \
  "below-target: skills/bt/SKILL.md" "$out"
cat >"$t15d/config/instruction-budget-exemptions.txt" <<'EOF'
declared-exception|skills/bt/SKILL.md|accepted: this body is intentionally near its budget
EOF
out="$(/bin/bash "$CHECKER" --root "$t15d" 2>&1)"
assert_exit "a matching declared-exception keeps the guard green" 0 $?
assert_absent "declared-exception silences the below-target warning it names" \
  "below-target: skills/bt/SKILL.md" "$out"
assert_absent "a USED declared-exception is not reported stale" \
  "declared-exception cleanup" "$out"

# 15e. a declared-exception NEVER silences a floor-breach warning (D-11). Same
#      surface at 4100 (margin 150 < floor) with a declared-exception entry.
t15e="$tmproot/t15e"
scaffold "$t15e"
make_skill "$t15e" bt 4100
cat >"$t15e/config/instruction-budget-exemptions.txt" <<'EOF'
declared-exception|skills/bt/SKILL.md|attempting (and failing) to excuse a floor-breach
EOF
out="$(/bin/bash "$CHECKER" --root "$t15e" 2>&1)"
assert_contains "a declared-exception cannot silence a floor-breach" \
  "floor-breach: skills/bt/SKILL.md" "$out"
# the entry did not match a live below-target/use-site warning, so it is stale.
assert_contains "a declared-exception naming only a floor-breach is stale" \
  "declared-exception cleanup" "$out"

# 15f. a stale declared-exception (its surface has no live warning) is a cleanup
#      WARNING, never an error.
t15f="$tmproot/t15f"
scaffold "$t15f"
make_skill "$t15f" small 100
cat >"$t15f/config/instruction-budget-exemptions.txt" <<'EOF'
declared-exception|skills/nowhere/SKILL.md|nothing here warns
EOF
out="$(/bin/bash "$CHECKER" --root "$t15f" 2>&1)"
assert_exit "a stale declared-exception does not fail the guard" 0 $?
assert_contains "a stale declared-exception yields a cleanup warning" \
  "declared-exception cleanup" "$out"

# 15g. a reason-less declared-exception is an error.
t15g="$tmproot/t15g"
scaffold "$t15g"
make_skill "$t15g" small 100
cat >"$t15g/config/instruction-budget-exemptions.txt" <<'EOF'
declared-exception|skills/small/SKILL.md|
EOF
out="$(/bin/bash "$CHECKER" --root "$t15g" 2>&1)"
assert_exit "a reason-less declared-exception is an error" 1 $?
assert_contains "reason-less declared-exception is diagnosed" "reason" "$out"

# 15h. aggregate floor-breach: a skill whose START-LOAD margin is below its floor
#      warns naming the aggregate surface. start-load error 10000, floor 500 ->
#      margin 400 at 9600 (body 100 + run-start doc 9500), still under 10000.
t15h="$tmproot/t15h"
scaffold "$t15h"
make_doc "$t15h" rsdoc 9500
make_skill "$t15h" aggskill 100 "Doctrine: run-start rsdoc"
lift_doctrine_floor "$t15h"
out="$(/bin/bash "$CHECKER" --root "$t15h" 2>&1)"
assert_exit "aggregate floor-breach is a warning, not an error" 0 $?
assert_contains "start-load floor-breach names the aggregate surface" \
  "floor-breach: start-load:aggskill" "$out"

# 15i. raise rationale: an effective budget knob above its core default needs a
#      matching raise| entry. Overlay raises skill_error to 5000.
t15i="$tmproot/t15i"
scaffold "$t15i"
make_skill "$t15i" small 100
mkdir -p "$t15i/.claude"
cat >"$t15i/.claude/planwright.local.yml" <<'EOF'
instruction_budget_skill_error: 5000
EOF
out="$(/bin/bash "$CHECKER" --root "$t15i" 2>&1)"
assert_exit "a raise with no recorded rationale fails the guard's config parsing" 1 $?
assert_contains "silent raise is diagnosed" "raise-rationale" "$out"
cat >"$t15i/config/instruction-budget-exemptions.txt" <<'EOF'
raise|instruction_budget_skill_error|5000|team policy: this repo's SKILL bodies run larger
EOF
out="$(/bin/bash "$CHECKER" --root "$t15i" 2>&1)"
assert_exit "the same raise WITH a matching rationale passes" 0 $?

# 15j. a raised FLOOR knob trips nothing (out of scope by suffix — protective).
t15j="$tmproot/t15j"
scaffold "$t15j"
make_skill "$t15j" small 100
mkdir -p "$t15j/.claude"
cat >"$t15j/.claude/planwright.local.yml" <<'EOF'
instruction_budget_skill_floor: 500
EOF
out="$(/bin/bash "$CHECKER" --root "$t15j" 2>&1)"
assert_exit "raising a floor knob needs no rationale (protective, by suffix)" 0 $?
assert_absent "raising a floor knob triggers no raise-rationale error" \
  "raise-rationale" "$out"

# 15k. a stale raise| entry (its knob at or below its core default) is an error;
#      so is one naming an unknown knob.
t15k="$tmproot/t15k"
scaffold "$t15k"
make_skill "$t15k" small 100
cat >"$t15k/config/instruction-budget-exemptions.txt" <<'EOF'
raise|instruction_budget_skill_error|9999|the knob is not actually raised here
EOF
out="$(/bin/bash "$CHECKER" --root "$t15k" 2>&1)"
assert_exit "a stale raise| entry (knob not raised) is an error" 1 $?
assert_contains "stale raise entry is diagnosed" "stale raise" "$out"

t15k2="$tmproot/t15k2"
scaffold "$t15k2"
make_skill "$t15k2" small 100
cat >"$t15k2/config/instruction-budget-exemptions.txt" <<'EOF'
raise|instruction_budget_not_a_knob|9999|names a knob that is not raisable
EOF
out="$(/bin/bash "$CHECKER" --root "$t15k2" 2>&1)"
assert_exit "a raise| entry naming an unknown knob is an error" 1 $?
assert_contains "unknown-knob raise entry is diagnosed" "unknown knob" "$out"

# 15l. a reason-less raise entry is an error.
t15l="$tmproot/t15l"
scaffold "$t15l"
make_skill "$t15l" small 100
printf 'raise|instruction_budget_skill_error|5000|\n' \
  >"$t15l/config/instruction-budget-exemptions.txt"
out="$(/bin/bash "$CHECKER" --root "$t15l" 2>&1)"
assert_exit "a reason-less raise entry is an error" 1 $?
assert_contains "reason-less raise is diagnosed" "reason" "$out"

# 15m. an absent core-default baseline for a raisable knob is fail-closed: the
#      knob is present only via overlay, so it cannot be validated against a core
#      default.
t15m="$tmproot/t15m"
scaffold "$t15m"
make_skill "$t15m" small 100
cat >"$t15m/config/defaults.yml" <<'EOF'
instruction_budget_skill_warn: 3000
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
mkdir -p "$t15m/.claude"
cat >"$t15m/.claude/planwright.local.yml" <<'EOF'
instruction_budget_skill_error: 4250
EOF
out="$(/bin/bash "$CHECKER" --root "$t15m" 2>&1)"
assert_exit "an absent core-default baseline is fail-closed" 1 $?
assert_contains "absent-baseline failure is diagnosed" "baseline" "$out"

# 15n. a missing floor knob is fail-loud, exactly like a missing budget knob.
t15n="$tmproot/t15n"
scaffold "$t15n"
make_skill "$t15n" small 100
grep -v '^instruction_budget_closure_floor:' \
  "$t15n/config/defaults.yml" >"$t15n/config/defaults.yml.tmp"
mv "$t15n/config/defaults.yml.tmp" "$t15n/config/defaults.yml"
out="$(/bin/bash "$CHECKER" --root "$t15n" 2>&1)"
assert_exit "a missing floor knob is a fail-loud error" 1 $?

# 15o. a permanently exempt doc over its per-file threshold produces NO
#      floor-breach row — it carries no headroom floor (REQ-D1.1); its existing
#      exempt over-budget notice stands.
t15o="$tmproot/t15o"
scaffold "$t15o"
make_doc "$t15o" bigexempt 4500 # over the doctrine per-file error (4000)
cat >"$t15o/config/instruction-budget-exemptions.txt" <<'EOF'
exempt|doctrine/bigexempt.md|standing rationale: kept large on purpose
EOF
out="$(/bin/bash "$CHECKER" --root "$t15o" 2>&1)"
assert_exit "an exempt over-budget doc keeps the guard green" 0 $?
assert_absent "an exempt doc produces no floor-breach row" \
  "floor-breach: doctrine/bigexempt.md" "$out"
assert_contains "the exempt over-budget notice still stands" \
  "permanently exempt" "$out"

# 15p. --audit reports margin-to-warn and margin-to-error for the floored classes
#      (per-file and per-skill aggregate), so headroom is verifiable from the one
#      report (D-8, REQ-D1.1).
t15p="$tmproot/t15p"
scaffold "$t15p"
make_doc "$t15p" rdoc 200
make_skill "$t15p" mskill 100 "Doctrine: run-start rdoc"
aud="$(/bin/bash "$CHECKER" --audit --root "$t15p" 2>&1)"
assert_contains "audit shows per-file margin-to-warn" "margin-to-warn=" "$aud"
assert_contains "audit shows per-file margin-to-error" "margin-to-error=" "$aud"
# per-skill load line carries both aggregate margins on its start-load side.
sk_row="$(printf '%s\n' "$aud" | grep -F 'mskill start-load=')"
assert_contains "audit shows the start-load margin on the per-skill line" \
  "margin-to-warn=" "$sk_row"

# 15q. echo discipline (cross-cutting): a control byte in a declared-exception
#      rationale is stripped before the cleanup warning reaches the terminal.
t15q="$tmproot/t15q"
scaffold "$t15q"
make_skill "$t15q" small 100
esc="$(printf '\033')"
printf 'declared-exception|skills/ghost/SKILL.md|stale%swith a control byte\n' "$esc" \
  >"$t15q/config/instruction-budget-exemptions.txt"
out="$(/bin/bash "$CHECKER" --root "$t15q" 2>&1)"
assert_exit "a control-byte rationale does not fail the guard" 0 $?
assert_contains "the stale entry still yields a cleanup warning" \
  "declared-exception cleanup" "$out"
assert_absent "the control byte is stripped from the echoed rationale" "$esc" "$out"

# 15r. echo discipline on the PARSE-ERROR path (regression): a control byte in a
#      malformed declared-exception / raise entry is stripped before the error
#      message reaches the terminal, matching the sanitized warn/cleanup paths.
t15r="$tmproot/t15r"
scaffold "$t15r"
make_skill "$t15r" small 100
esc="$(printf '\033')"
# a malformed raise entry (only one field after `raise`) whose field carries a
# control byte -> the parse error echoes the offending line sanitized.
printf 'raise|onefield%s\n' "$esc" >"$t15r/config/instruction-budget-exemptions.txt"
out="$(/bin/bash "$CHECKER" --root "$t15r" 2>&1)"
assert_exit "a malformed raise entry is an error" 1 $?
assert_contains "the malformed raise entry is diagnosed" "malformed raise" "$out"
assert_absent "control byte stripped from the raise parse-error message" "$esc" "$out"
# a reason-less declared-exception whose surface carries a control byte -> the
# parse error echoes the surface sanitized.
printf 'declared-exception|surf%s|\n' "$esc" \
  >"$t15r/config/instruction-budget-exemptions.txt"
out="$(/bin/bash "$CHECKER" --root "$t15r" 2>&1)"
assert_exit "a reason-less declared-exception is an error" 1 $?
assert_absent "control byte stripped from the declared-exception parse error" "$esc" "$out"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-instructions tests passed"
