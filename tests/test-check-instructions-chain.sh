#!/bin/bash
# Tests for scripts/check-instructions.sh — the COMPOSED-CHAIN charge
# (review-effectiveness REQ-G1.2, D-12). /polish runs /self-review nested in
# its own session, so the guard charges the two bodies plus the union of the
# doctrine both manifests load as one closure, against its own error knob,
# instruction_budget_chain_closure_error. §20i also pins the real corpus's
# diet (REQ-G1.1): both members load the methodology docs point-of-use.
#
# Added after the guard-coverage split; tests/test-check-instructions.sh names
# the other siblings and carries the guard's full contract.
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

words() {
  awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) printf "w "; printf "\n" }'
}

# scaffold <root> [chain-error]: the production knob set, plus the chain knob
# unless the second argument is `none`.
scaffold() {
  root="$1"
  chain="${2:-20000}"
  mkdir -p "$root/skills" "$root/doctrine" "$root/hooks" "$root/config"
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$root"
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
  if [ "$chain" != none ]; then
    printf 'instruction_budget_chain_closure_error: %s\n' "$chain" >>"$root/config/defaults.yml"
  fi
  : >"$root/config/instruction-budget-exemptions.txt"
  cat >"$root/hooks/hooks.json" <<'EOF'
{ "hooks": {} }
EOF
}

# make_skill <root> <name> <body-words> [manifest lines...]; the point-of-use
# docs are named in the body so the reverse use-site check stays quiet.
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

# chain_fixture <root> <chain-error>: polish (100 words) and self-review (200)
# share run-start doc `shared` (300); each has its own point-of-use doc (polish
# `alpha` 400, self-review `beta` 500). Each skill names its point-of-use doc in
# a body line. Chain closure = 108 + 208 + 300 + 400 + 500 = 1516, the shared
# doc charged once (wc -w of a body counts its naming and manifest lines).
chain_fixture() {
  scaffold "$1" "$2"
  make_doc "$1" shared 300
  make_doc "$1" alpha 400
  make_doc "$1" beta 500
  make_skill "$1" polish 100 \
    "alpha" \
    "Doctrine: run-start shared" \
    "Doctrine: point-of-use alpha (iteration)"
  make_skill "$1" self-review 200 \
    "beta" \
    "Doctrine: run-start shared" \
    "Doctrine: point-of-use beta (validation)"
}

tmproot="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmproot"' EXIT

########################################################################
# 20. The composed-chain charge (review-effectiveness REQ-G1.2, D-12).
########################################################################
# 20a. REQ-G1.2: the chain is charged as one closure, a shared doc counted once,
#      and the plain run reports it with its threshold.
t20a="$tmproot/t20a"
chain_fixture "$t20a" 20000
out="$(/bin/bash "$CHECKER" --root "$t20a" 2>&1)"
assert_exit "REQ-G1.2: a chain under its threshold keeps the guard green" 0 $?
assert_contains "REQ-G1.2: the plain run reports the chain closure and its threshold" \
  "chain closure: polish+self-review 1516 words (error threshold 20000)" "$out"
out="$(/bin/bash "$CHECKER" --root "$t20a" --audit 2>&1)"
assert_contains "REQ-G1.2: the audit carries the chain line with its margin" \
  "chain polish+self-review closure=1516 (ok) margin-to-error=18484" "$out"

# 20b. REQ-G1.2: at its error threshold (boundary-inclusive) the chain is an
#      error, though each skill's own closure is far under its budget.
t20b="$tmproot/t20b"
chain_fixture "$t20b" 1516
out="$(/bin/bash "$CHECKER" --root "$t20b" 2>&1)"
assert_exit "REQ-G1.2: a chain at its error threshold fails the guard" 1 $?
assert_contains "REQ-G1.2: the chain error names the chain and the knob value" \
  "chain closure over budget: polish+self-review (1516 words >= 1516)" "$out"
assert_absent "REQ-G1.2: neither member's own closure is in error" \
  "ERROR: closure over budget" "$out"
out="$(/bin/bash "$CHECKER" --root "$t20b" --audit 2>&1)"
assert_contains "REQ-G1.2: an over-budget chain is on the audit's offender shortlist" \
  "chain polish+self-review (1516 words >= 1516 chain budget) [unsuppressed]" "$out"

# 20c. REQ-G1.2: the chain's headroom is floored like a closure, and a
#      declared-exception on the chain surface excuses its below-target warning.
t20c="$tmproot/t20c"
chain_fixture "$t20c" 3200
out="$(/bin/bash "$CHECKER" --root "$t20c" 2>&1)"
assert_contains "REQ-G1.2: a chain under its restoration target warns on its surface" \
  "below-target: chain:polish+self-review margin=1684" "$out"
cat >>"$t20c/config/instruction-budget-exemptions.txt" <<'EOF'
declared-exception|chain:polish+self-review|margin=1684|fixture: the chain sits below target by design
EOF
out="$(/bin/bash "$CHECKER" --root "$t20c" 2>&1)"
assert_exit "REQ-G1.2: a chain declared-exception keeps the guard green" 0 $?
assert_absent "REQ-G1.2: the declared-exception silences the chain warning" \
  "below-target: chain:" "$out"
assert_absent "REQ-G1.2: a used chain declared-exception is not stale" \
  "declared-exception cleanup" "$out"

# 20d. REQ-G1.2: with both chain skills present, a missing chain knob is
#      fail-loud rather than assumed.
t20d="$tmproot/t20d"
chain_fixture "$t20d" none
out="$(/bin/bash "$CHECKER" --root "$t20d" 2>&1)"
assert_exit "REQ-G1.2: a missing chain knob aborts the guard" 1 $?
assert_contains "REQ-G1.2: the abort names the chain knob" \
  "instruction_budget_chain_closure_error" "$out"
assert_contains "REQ-G1.2: a missing chain knob is the fail-loud knob abort" \
  "aborting — threshold knobs could not be read" "$out"
assert_absent "REQ-G1.2: no chain figure is scored without its knob" \
  "chain closure:" "$out"

# 20e. REQ-G1.2: a tree without the chain needs no chain knob and prints no
#      chain line.
for member in polish self-review; do
  t20e="$tmproot/t20e-$member"
  scaffold "$t20e" none
  make_skill "$t20e" "$member" 100
  out="$(/bin/bash "$CHECKER" --root "$t20e" 2>&1)"
  assert_exit "REQ-G1.2: a tree with only $member needs no chain knob" 0 $?
  assert_absent "REQ-G1.2: no chain line with only $member" "chain closure" "$out"
done

# 20f. REQ-G1.2: the chain knob is raise-governed like every other error knob.
t20f="$tmproot/t20f"
chain_fixture "$t20f" 20000
mkdir -p "$t20f/.claude"
echo "instruction_budget_chain_closure_error: 25000" >"$t20f/.claude/planwright.local.yml"
out="$(/bin/bash "$CHECKER" --root "$t20f" 2>&1)"
assert_exit "REQ-G1.2: a silent raise of the chain knob is an error" 1 $?
assert_contains "REQ-G1.2: the silent raise names the chain knob" \
  "'instruction_budget_chain_closure_error' effective value 25000" "$out"
echo "raise|instruction_budget_chain_closure_error|25000|fixture: a recorded raise" \
  >>"$t20f/config/instruction-budget-exemptions.txt"
out="$(/bin/bash "$CHECKER" --root "$t20f" 2>&1)"
assert_exit "REQ-G1.2: a recorded raise of the chain knob is accepted" 0 $?

# 20g. REQ-G1.2: a member whose manifest cannot be trusted leaves the chain
#      unmeasured, never scored under budget.
t20g="$tmproot/t20g"
chain_fixture "$t20g" 20000
make_skill "$t20g" self-review 200 "Doctrine: run-start missing-doc"
out="$(/bin/bash "$CHECKER" --root "$t20g" 2>&1)"
assert_exit "REQ-G1.2: an unresolvable member manifest fails the guard" 1 $?
assert_contains "REQ-G1.2: the chain is reported unmeasured" \
  "chain closure: polish+self-review unmeasured" "$out"
out="$(/bin/bash "$CHECKER" --root "$t20g" --audit 2>&1)"
assert_contains "REQ-G1.2: the audit reports the unmeasured chain" \
  "chain polish+self-review closure=unmeasured" "$out"

# 20h. REQ-G1.2: a permanently exempt doc is charged at its cap in the chain
#      figure, and the audit prints the honest actual beside it. The `big` doc
#      (5000) caps at the doctrine error threshold (4000); polish gains five
#      words naming and loading it: charged 1516 + 5 + 4000, actual + 5000.
t20h="$tmproot/t20h"
chain_fixture "$t20h" 20000
make_doc "$t20h" big 5000
echo "exempt|doctrine/big.md|fixture: kept large on purpose" \
  >>"$t20h/config/instruction-budget-exemptions.txt"
make_skill "$t20h" polish 100 \
  "alpha" \
  "big" \
  "Doctrine: run-start shared" \
  "Doctrine: point-of-use alpha (iteration)" \
  "Doctrine: point-of-use big (iteration)"
out="$(/bin/bash "$CHECKER" --root "$t20h" 2>&1)"
assert_exit "REQ-G1.2: a capped exempt doc keeps the chain green" 0 $?
assert_contains "REQ-G1.2: the chain charges an exempt doc at its cap" \
  "chain closure: polish+self-review 5521 words" "$out"
out="$(/bin/bash "$CHECKER" --root "$t20h" --audit 2>&1)"
assert_contains "REQ-G1.2: the audit prints the chain's honest actual" \
  "chain polish+self-review closure=5521 (ok) (actual 6521) margin-to-error=14479" "$out"

# 20i. REQ-G1.1: on the real corpus, both review skills load the methodology
#      docs point-of-use and their start-loads sit below the warn line.
for member in polish self-review; do
  for doc in discovery-rigor validation-rigor proportionality; do
    if grep -q "^Doctrine: point-of-use $doc " "$REPO_ROOT/skills/$member/SKILL.md"; then
      echo "ok: REQ-G1.1: $member loads $doc point-of-use"
    else
      echo "FAIL: REQ-G1.1: $member does not load $doc point-of-use" >&2
      failures=$((failures + 1))
    fi
  done
done
out="$(/bin/bash "$CHECKER" --root "$REPO_ROOT" --audit 2>&1)"
for member in polish self-review; do
  state="$(printf '%s\n' "$out" | awk -v m="$member" '$1 == m && $2 ~ /^start-load=/ { print $3; exit }')"
  assert_exit "REQ-G1.1: $member start-load is classed ok" 0 "$([ "$state" = "(ok)" ] && echo 0 || echo 1)"
done

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-instructions chain tests passed"
