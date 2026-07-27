#!/bin/bash
# Tests for scripts/check-instructions.sh — the CORPUS PASS and the core
# measurement surfaces: ranked report, start-load/closure arithmetic, offender
# shortlist, injected-context measurement, check-aggregate wiring, and the
# budget/threshold knobs (prompt-hygiene Task 2; REQ-A1.1, REQ-A1.2, REQ-A1.3,
# REQ-A1.4, REQ-B1.1, REQ-B1.2; instruction-headroom Task 4: REQ-D1.4 —
# suppression-derived present-offender expectations in section 0).
#
# Split into seven files (guard-coverage Task 6, REQ-E1.2, D-9): at 342s locally
# this was the suite's wall-clock floor, and its cost is ~3.5s per guard
# invocation, so the sections are now grouped into seven files of comparable
# invocation count that the runner's tests/*.sh discovery runs in parallel. The
# siblings, in the pre-split section order:
#   tests/test-check-instructions-exemptions.sh       §7  suppression forms
#   tests/test-check-instructions-resolution.sh       §§8–11 resolution, floors,
#                                                     fail-loud, untrusted input
#   tests/test-check-instructions-manifest.sh         §§12–14 unreadable files,
#                                                     fenced examples,
#                                                     manifest completeness
#   tests/test-check-instructions-headroom.sh         §15a–15j headroom floors
#   tests/test-check-instructions-headroom-knobs.sh   §15k–15x knob rationale
#   tests/test-check-instructions-suppression.sh      §§16–19 capped charge,
#                                                     pending-diet, reverse
#                                                     use-site
# Section numbers are kept from the pre-split file so the spec's references
# still land, and no assertion changed in the split; each file rebuilds the
# fixtures it needs so it still runs standalone.
#
# The guard measures word/line counts for every instruction file, computes
# manifest-derived start-load and closure per skill, scans hooks.json-registered
# injected-context hooks statically, enforces the budgets with four suppression
# forms (exempt / pending-diet / declared-exception / raise), enforces
# per-surface headroom floors, and emits a ranked --audit report with margin
# columns.
#
# Fixtures below build minimal instruction trees with known word counts so the
# arithmetic is assertable. Every input the guard reads (manifest entries,
# exemption text, rule-doc names, hook scripts) is PR-controllable and is
# treated as untrusted data.
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

# Derive the present-offender expectations from a suppression list instead of
# hardcoding file names (instruction-headroom REQ-D1.4, D-8). Every `exempt` and
# `pending-diet` entry names a surface that must still appear on the offender
# shortlist, tagged with its suppression; the emitted "<shortlist-target>\t<tag>"
# records track the config that defines the corpus's sanctioned state, so adding
# an exemption grows the expectations with no test edit. The dieted-clean
# absent-checks are structurally underivable and stay an explicit list.
derive_present_offenders() {
  # derive_present_offenders <exemptions-file>
  awk -F '|' '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    $1 == "exempt" { print $2 "\t[exempt]"; next }
    $1 == "pending-diet" {
      if      ($2 == "file")       print $3 "\t[pending-diet]"
      else if ($2 == "start-load") print "start-load " $3 "\t[pending-diet]"
      else if ($2 == "closure")    print "closure " $3 "\t[pending-diet]"
      next
    }
  ' "$1"
}

tmproot="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmproot"' EXIT

########################################################################
# 0. Real repo passes the guard with no transitional allowances remaining
#    (Task 2 Done-when: `mise run check` passes on the repo; post-Task-7.5 no
#    transitional pending-diet allowance remains — the standing suppressions are
#    the permanent spec-format per-file exemption plus the two /orchestrate
#    below-target declared exceptions from the fleet-hardening #271 collision).
########################################################################
out="$(/bin/bash "$CHECKER" 2>&1)"
assert_exit "real repo passes the guard (no transitional allowances remain)" 0 $?

# 0a. Closing-gate assertions (instruction-headroom Task 11, REQ-C1.1, D-11;
#     the closure-margin target assertions relocated from Tasks 7 and 9 per
#     kickoff §6). The restoration campaign is complete: every budgeted surface
#     sits at or above its restoration target (twice its floor) or carries a
#     declared-exception, so the real-corpus guard run emits none of the D-11
#     margin warnings and measures every surface. The floor-breach / below-target
#     / use-site machinery itself is proven by the fixtures below (15c/15d/15t/
#     15x/16*); this asserts the *shipped corpus* is in the restored end state,
#     keeping the closing gate permanently enforced in CI (the diets rewrite the
#     very bodies the use-site check scans, so this re-checks them on the whole).
# Match the warn() emission prefix ("WARN: <type>:") rather than the bare type
# name: the guard also prints a "declared-exception cleanup: no live below-target
# or use-site warning ..." notice that contains those type names (and, for a
# stale use-site entry, the "use-site:<surface>" key), so a bare-substring gate
# could false-fail on a future stale exception with no actual warning of that
# type.
assert_absent "closing gate: no floor-breach warning on the real corpus" "WARN: floor-breach:" "$out"
assert_absent "closing gate: no unexcepted below-target warning on the real corpus" "WARN: below-target:" "$out"
assert_absent "closing gate: no use-site warning on the real corpus" "WARN: use-site:" "$out"
# A single --audit capture serves both the unmeasured closing-gate check and the
# transitional-allowance assertions. "unmeasured" is an --audit-only surface
# state: the Per-skill load section renders it for a skill whose manifest is
# malformed or unresolved (the state never reaches the default run's output), so
# that absence is asserted against the audit render, confirming every floored
# aggregate on the real corpus is actually measured. Guard the capture's exit so
# a non-rendering crash is caught rather than masked into a false-passing absence
# check. Post-Task-7.5 the audit also carries no transitional allowance anywhere:
# the Task 3-seeded start-load carries were shed by their diet tasks (REQ-B1.3b;
# the closeout direction REQ-D1.4 forbids any lingering `pending-diet` entry).
aud="$(/bin/bash "$CHECKER" --audit 2>&1)"
assert_exit "closing gate: the --audit render exits zero (guards the checks below)" 0 $?
assert_absent "closing gate: no unmeasured surface on the real corpus" "unmeasured" "$aud"
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
# Present-offender expectations are DERIVED from the shipped suppression list
# (REQ-D1.4, D-8), not hardcoded: every exempt / pending-diet entry names an
# offender that must still appear on the shortlist, tagged with its suppression
# (suppression governs the exit code, not offender status). Today the corpus
# carries exactly the permanent spec-format exemption, so this derives the
# doctrine/spec-format.md [exempt] row that was previously asserted by name;
# adding an exemption grows the set with no edit here.
while IFS="$(printf '\t')" read -r tgt tag; do
  [ -n "$tgt" ] || continue
  row="$(printf '%s\n' "$sl" | grep -F "$tgt" | head -n1)"
  assert_contains "shortlist names derived offender '$tgt'" "$tgt" "$sl"
  assert_contains "derived offender '$tgt' is tagged $tag" "$tag" "$row"
done <<EOF
$(derive_present_offenders "$REPO_ROOT/config/instruction-budget-exemptions.txt")
EOF

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

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-instructions corpus/measurement tests passed"
