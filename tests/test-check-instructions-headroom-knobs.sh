#!/bin/bash
# Tests for scripts/check-instructions.sh — RAISE RATIONALE and knob hygiene
# around the headroom floors (instruction-headroom Task 2: REQ-A1.4, REQ-D1.1,
# REQ-D1.6). Sections 15k–15x of the pre-split file, numbering kept; the
# floors/margins half (15a–15j) lives in
# tests/test-check-instructions-headroom.sh.
#
# Split out of tests/test-check-instructions.sh (guard-coverage Task 6,
# REQ-E1.2, D-9); that file's header carries the guard's full contract and names
# all seven siblings. No assertion changed in the split.
#
# The contract under test: a `raise|` entry is required (with a reason) for an
# effective knob above its core default, is an error when stale or when it names
# an unknown knob, and is out of scope for protective floor knobs; a missing,
# non-numeric, or unreadable knob baseline is fail-loud rather than assumed; the
# floor knob VALUE drives the arithmetic instead of a hardcoded constant; and the
# echo-discipline cases pin that untrusted content never reaches the terminal as
# a live control byte, on the success path and the parse-error path alike.
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
# 15 (continued). Raise rationale and knob hygiene — the second half of the
#     pre-split file's section 15 (instruction-headroom Task 2: REQ-A1.4,
#     REQ-D1.1, REQ-D1.6). 15a–15j (floors, margins, declared exceptions) are
#     in tests/test-check-instructions-headroom.sh.
########################################################################
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
assert_contains "reason-less raise is diagnosed" "has no reason" "$out"

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

# 15s. a NON-NUMERIC floor knob is fail-loud, exactly like a non-numeric budget
#      knob (test-spec REQ-D1.1 lists missing AND non-numeric; 15n covers missing).
t15s="$tmproot/t15s"
scaffold "$t15s"
make_skill "$t15s" small 100
sed -e 's/^instruction_budget_skill_floor: .*/instruction_budget_skill_floor: not-a-number/' \
  "$t15s/config/defaults.yml" >"$t15s/config/defaults.yml.tmp"
mv "$t15s/config/defaults.yml.tmp" "$t15s/config/defaults.yml"
out="$(/bin/bash "$CHECKER" --root "$t15s" 2>&1)"
assert_exit "a non-numeric floor knob is a fail-loud error" 1 $?

# 15t. aggregate below-target + declared-exception round-trip on the documented
#      `start-load:<skill>` surface key (pins the aggregate key contract, not just
#      per-file). start-load error 10000, floor 500, target 1000 -> margin 700 at
#      start-load 9300 (body 100 + run-start doc 9200): below-target, not breach.
t15t="$tmproot/t15t"
scaffold "$t15t"
make_doc "$t15t" rsdoc 9200
make_skill "$t15t" aggbt 100 "Doctrine: run-start rsdoc"
lift_doctrine_budget "$t15t"
out="$(/bin/bash "$CHECKER" --root "$t15t" 2>&1)"
assert_contains "aggregate below-target names the start-load surface key" \
  "below-target: start-load:aggbt" "$out"
cat >>"$t15t/config/instruction-budget-exemptions.txt" <<'EOF'
declared-exception|start-load:aggbt|accepted: this start-load is intentionally near budget
EOF
out="$(/bin/bash "$CHECKER" --root "$t15t" 2>&1)"
assert_exit "an aggregate declared-exception keeps the guard green" 0 $?
assert_absent "declared-exception silences the aggregate below-target it names" \
  "below-target: start-load:aggbt" "$out"
assert_absent "a USED aggregate declared-exception is not reported stale" \
  "declared-exception cleanup" "$out"

# 15u. an UNREADABLE core-defaults file is fail-closed (test-spec REQ-A1.4 lists
#      absent AND unreadable; 15m covers the absent-key case).
t15u="$tmproot/t15u"
scaffold "$t15u"
make_skill "$t15u" small 100
chmod 000 "$t15u/config/defaults.yml"
out="$(/bin/bash "$CHECKER" --root "$t15u" 2>&1)"
rc=$?
chmod 644 "$t15u/config/defaults.yml" # restore so the trap's rm can clean up
assert_exit "an unreadable core-defaults file is fail-closed" 1 "$rc"

# 15v. the floor KNOB VALUE (not a hardcoded constant) drives the comparison: a
#      below-target that fires at the default floor disappears when the floor is
#      lowered via overlay so the same margin now clears the (lower) target.
t15v="$tmproot/t15v"
scaffold "$t15v"
make_skill "$t15v" fv 3900 # error 4250, floor 250, target 500 -> margin 350
out="$(/bin/bash "$CHECKER" --root "$t15v" 2>&1)"
assert_contains "below-target fires at the default skill floor" \
  "below-target: skills/fv/SKILL.md" "$out"
mkdir -p "$t15v/.claude"
cat >"$t15v/.claude/planwright.local.yml" <<'EOF'
instruction_budget_skill_floor: 100
EOF
out="$(/bin/bash "$CHECKER" --root "$t15v" 2>&1)"
assert_absent "lowering the floor knob clears the below-target (knob drives comparison)" \
  "below-target: skills/fv/SKILL.md" "$out"

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

# 15w. aggregate CLOSURE floor-breach names the `closure:<skill>` surface key
#      (the symmetric partner of 15h's start-load path; the closure aggregate
#      was otherwise unexercised). closure error 20000, floor 1000 -> margin 896
#      at closure 19104 (body 104 = 100 filler + the 4-word point-of-use manifest
#      line, plus point-of-use doc 19000), still under 20000, start-load compliant.
t15w="$tmproot/t15w"
scaffold "$t15w"
make_doc "$t15w" pudoc 19000
make_skill "$t15w" aggcl 100 "Doctrine: point-of-use pudoc (rare)"
lift_doctrine_budget "$t15w"
out="$(/bin/bash "$CHECKER" --root "$t15w" 2>&1)"
assert_exit "aggregate closure floor-breach is a warning, not an error" 0 $?
assert_contains "closure floor-breach names the aggregate surface key" \
  "floor-breach: closure:aggcl" "$out"

# 15x. aggregate CLOSURE below-target + declared-exception round-trip on the
#      documented `closure:<skill>` key (the symmetric partner of 15t's
#      start-load path). closure error 20000, floor 1000, target 2000 -> margin
#      1496 at closure 18504 (body 104 + point-of-use doc 18400): below-target,
#      not breach.
t15x="$tmproot/t15x"
scaffold "$t15x"
make_doc "$t15x" pudoc 18400
make_skill "$t15x" aggclbt 100 "Doctrine: point-of-use pudoc (rare)"
lift_doctrine_budget "$t15x"
out="$(/bin/bash "$CHECKER" --root "$t15x" 2>&1)"
assert_contains "aggregate below-target names the closure surface key" \
  "below-target: closure:aggclbt" "$out"
cat >>"$t15x/config/instruction-budget-exemptions.txt" <<'EOF'
declared-exception|closure:aggclbt|accepted: this closure is intentionally near budget
EOF
out="$(/bin/bash "$CHECKER" --root "$t15x" 2>&1)"
assert_exit "an aggregate closure declared-exception keeps the guard green" 0 $?
assert_absent "declared-exception silences the aggregate closure below-target it names" \
  "below-target: closure:aggclbt" "$out"
assert_absent "a USED aggregate closure declared-exception is not reported stale" \
  "declared-exception cleanup" "$out"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-instructions raise-rationale tests passed"
