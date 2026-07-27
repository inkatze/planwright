#!/bin/bash
# Tests for scripts/check-instructions.sh — the SUPPRESSION FORMS: permanent
# exemptions, transitional pending-diet allowances, and closeout mode
# (prompt-hygiene Task 2; REQ-B1.3, REQ-B1.4, REQ-B1.5; instruction-headroom
# Task 4: REQ-D1.4). Section 7 of the pre-split file, numbering kept.
#
# Split out of tests/test-check-instructions.sh (guard-coverage Task 6,
# REQ-E1.2, D-9); that file's header carries the guard's full contract and names
# all seven siblings. No assertion changed in the split.
#
# Fixtures build minimal instruction trees with known word counts so the
# arithmetic is assertable. Every input the guard reads (manifest entries,
# exemption text, rule-doc names) is PR-controllable and is treated as
# untrusted data.
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

# The pre-split file read mise.toml once in §5 (check-aggregate wiring); §7e's
# closing assertion reads it back to prove the `check:instructions` task wires
# --closeout. Each file stands alone, so it is re-read here.
mise_txt="$(cat "$REPO_ROOT/mise.toml")"

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
lift_doctrine_budget "$t7"
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
lift_doctrine_budget "$t7c"
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
lift_doctrine_budget "$t7d"
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
lift_doctrine_budget "$t7e2"
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
lift_doctrine_budget "$t7e3"
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

# the real repo passes --closeout (post-Task-7.5 no transitional pending-diet
# allowance remains; the standing spec-format exemption and the two /orchestrate
# declared exceptions are permanent, so the closeout direction holds on the
# shipped corpus).
out="$(/bin/bash "$CHECKER" --closeout 2>&1)"
assert_exit "closeout: the real repo passes --closeout (no lingering allowance)" 0 $?

# the mise `check:instructions` task wires the guard in closeout mode so the
# aggregate `check` permanently enforces the Task-8 closeout direction.
assert_contains "check:instructions task runs the guard in --closeout mode" \
  "check-instructions.sh --closeout" "$mise_txt"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-instructions suppression-form tests passed"
