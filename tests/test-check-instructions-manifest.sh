#!/bin/bash
# Tests for scripts/check-instructions.sh — UNREADABLE instruction files, fenced
# Doctrine examples, and the manifest-completeness assertion (prompt-hygiene
# Task 2; REQ-A1.2, REQ-B1.8). Sections 12–14 of the pre-split file, numbering
# kept.
#
# Split out of tests/test-check-instructions.sh (guard-coverage Task 6,
# REQ-E1.2, D-9); that file's header carries the guard's full contract and names
# all seven siblings. No assertion changed in the split.
#
# The through-line: what the guard must NOT silently absorb. An unreadable file
# is never scored 0, a ```-fenced `Doctrine:` line is documentation rather than a
# live manifest entry, and — when the completeness knob is on — a skill that
# names a rule doc only in prose is a failure, not a pass.
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
lift_doctrine_budget() {
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
lift_doctrine_budget "$t13b"
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

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-instructions manifest/fenced-example tests passed"
