#!/bin/bash
# Tests for scripts/check-instructions.sh — HEADROOM FLOORS, margins, and
# declared exceptions (instruction-headroom Task 2: REQ-A1.1, REQ-A1.4,
# REQ-D1.1, REQ-D1.6). Sections 15a–15j of the pre-split file, numbering kept;
# the knob-rationale half (15k–15x) lives in
# tests/test-check-instructions-headroom-knobs.sh.
#
# Split out of tests/test-check-instructions.sh (guard-coverage Task 6,
# REQ-E1.2, D-9); that file's header carries the guard's full contract and names
# all seven siblings. No assertion changed in the split.
#
# The contract under test: a margin strictly below its floor warns on every run
# and never errors; a margin at or above the floor is compliant; a declared
# exception silences a below-target warning but NEVER a floor breach (D-11); a
# stale or reason-less exception is an error; and the aggregate surfaces
# (start-load, closure) breach by the same rules as per-file ones.
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
assert_contains "reason-less declared-exception is diagnosed" "has no reason" "$out"

# 15h. aggregate floor-breach: a skill whose START-LOAD margin is below its floor
#      warns naming the aggregate surface. start-load error 10000, floor 500 ->
#      margin 400 at 9600 (body 100 + run-start doc 9500), still under 10000.
t15h="$tmproot/t15h"
scaffold "$t15h"
make_doc "$t15h" rsdoc 9500
make_skill "$t15h" aggskill 100 "Doctrine: run-start rsdoc"
lift_doctrine_budget "$t15h"
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

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-instructions headroom-floor tests passed"
