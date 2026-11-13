#!/bin/bash
# Tests for the venture-task contract helper (inception Task 10; REQ-D1.1,
# REQ-D1.2, REQ-D1.3, REQ-D1.5, REQ-D1.6, REQ-D1.7, REQ-J1.3 · D-7, D-13).
#
# scripts/venture-task.sh runs a venture's plan.md tasks under the contract in
# doctrine/venture-task.md: kind-keyed findings documents, a PR-less delivery
# commit, human acceptance that lands the register updates with the findings
# in one change, the spikes/ discipline, and the per-commit atomicity check.
# The fixture is the golden bundle the other inception suites mutate; each
# venture below is a fresh git repository holding it.
#
# REQ-D1.4 (acceptance is human) is a [manual] dogfood entry: the helper can
# require a named acceptor and refuse to touch the registers before an
# acceptance, both asserted here, but not tell a human from an agent.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VT="$REPO_ROOT/scripts/venture-task.sh"
OFFLOAD="$REPO_ROOT/scripts/offload-dispatch.sh"
DOC="$REPO_ROOT/doctrine/venture-task.md"
EXEC_SKILL="$REPO_ROOT/skills/execute-task/SKILL.md"

# shellcheck source=tests/lib/inception-fixture.sh
. "$REPO_ROOT/tests/lib/inception-fixture.sh"
# shellcheck source=tests/lib/emitter-lint.sh
. "$REPO_ROOT/tests/lib/emitter-lint.sh"

failures=0
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (expected to find '$2' in: $3)" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_not_contains() {
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (did not expect '$2' in: $3)" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -x "$VT" ]; then
  echo "FAIL: $VT is missing or not executable" >&2
  exit 1
fi

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

assert_lint_md() {
  if lint_emitted markdown venture-task.sh "$2"; then
    echo "ok: $1: lint-clean markdown"
  else
    echo "FAIL: $1: fails the markdown lint" >&2
    failures=$((failures + 1))
  fi
}

export HOME="$tmp/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
export PLANWRIGHT_ROOT="$REPO_ROOT"
export PLANWRIGHT_INCEPTION_TODAY=2026-10-18
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

# vt <args...> — run the helper; sets out (stdout+stderr) and rc.
vt() {
  out=$("$VT" "$@" 2>&1)
  rc=$?
}

# new_venture <name> — a fresh git venture holding the golden bundle; prints
# its path.
new_venture() {
  _nv="$tmp/$1"
  inception_fixture_write "$_nv" || return 1
  git init -q "$_nv" || return 1
  git -C "$_nv" add -A && git -C "$_nv" commit -q -m "fixture" || return 1
  printf '%s\n' "$_nv"
}

# findings <venture> <task> <kind> <updates...> — write findings/<task>.md
# with one register-update line per remaining argument.
findings() {
  _fd=$1 _ft=$2 _fk=$3
  shift 3
  mkdir -p "$_fd/findings"
  {
    printf '# %s findings\n\n**Task:** %s\n**Kind:** %s\n' "$_ft" "$_ft" "$_fk"
    [ -n "${PERFORMED:-}" ] && printf '**Performed-by:** %s\n' "$PERFORMED"
    [ -n "${STAKEHOLDER:-}" ] && printf '**Stakeholder:** %s\n' "$STAKEHOLDER"
    printf '\n## Findings\n\nAll three sinks were written to with a canned incident.\n\n## Register updates\n\n'
    for _u in "$@"; do printf -- '- %s\n' "$_u"; done
  } >"$_fd/findings/$_ft.md"
}

commit_count() { git -C "$1" rev-list --count HEAD; }
head_files() { git -C "$1" show --name-only --format= HEAD | sort | tr '\n' ' '; }
field_of() { # field_of <file> <id> <field>
  awk -v id="$2" -v f="$3" '
    /^### / { cur = ($2 == id) }
    cur && index($0, "- **" f ":** ") == 1 { sub(/^- \*\*[^*]+:\*\* /, ""); print; exit }
  ' "$1"
}

# =========================================================================
# REQ-D1.2: the kind-keyed contract table
# =========================================================================

vt contract
assert_eq "D1.2 contract exits 0" 0 "$rc"
for k in spike research analysis demand-signal alignment; do
  assert_contains "D1.2 contract lists $k" "$(printf 'kind\t%s' "$k")" "$out"
done
vt contract alignment
assert_contains "D1.2 alignment is performed by a human" "$(printf 'performer\thuman')" "$out"
assert_contains "D1.2 alignment names the stakeholder requirement" "$(printf 'requires\tstakeholder')" "$out"
vt contract research
assert_contains "D1.2 research is performed by the agent" "$(printf 'performer\tagent')" "$out"
assert_contains "D1.2 research names its deliverable" "$(printf 'deliverable\t')" "$out"
assert_contains "D1.2 research names its acceptance shape" "$(printf 'acceptance\t')" "$out"
vt contract demand-signal
assert_contains "D1.7 demand-signal is performed by a human" "$(printf 'performer\thuman')" "$out"
vt contract spiky
assert_eq "D1.2 an unknown kind is refused" 2 "$rc"

# The kinds parse per the format doctrine: the contract, this doc's table, and
# the validator's enum name the same five, in the same order.
script_kinds=$("$VT" contract | awk -F'\t' '$1 == "kind" { printf "%s ", $2 }')
doc_kinds=$(awk -F'|' '/^\| `[a-z-]+` \|/ { k = $2; gsub(/[ `]/, "", k); printf "%s ", k }' "$DOC")
fmt_kinds=$(sed -n 's/^- \*\*Kind:\*\* <\(.*\)>$/\1/p' "$REPO_ROOT/doctrine/inception-format.md" | tr -d ' ' | tr '|' ' ')
assert_eq "D1.2 doctrine table kinds match the contract" "$script_kinds" "$doc_kinds"
assert_eq "D1.2 format-doctrine kinds match the contract" "$script_kinds" "$fmt_kinds "

# =========================================================================
# show: kinds parse, alignment resolves its stakeholder, ids are validated
# =========================================================================

v=$(new_venture show) || exit 1
vt show "$v" T-1
assert_eq "show exits 0" 0 "$rc"
assert_contains "show prints the kind" "$(printf 'kind\tspike')" "$out"
assert_contains "show prints the status" "$(printf 'status\trunning')" "$out"
assert_contains "show prints the linked ids" "$(printf 'tests\tA-1')" "$out"
vt show "$v" T-3
assert_contains "D1.2 alignment resolves its stakeholder from the map" "$(printf 'stakeholder\tDana Reyes')" "$out"
for bad in T-0 T-x 't-1' 'T-1/..' '../T-1' '-T-1'; do
  vt show "$v" "$bad"
  assert_eq "show refuses the task id '$bad'" 2 "$rc"
done
vt show "$v" T-9
assert_eq "show refuses a task the plan does not hold" 1 "$rc"

# A bare identifier resolves under ventures_root.
printf 'ventures_root: ~/ventures\n' >"$tmp/core-defaults.yml"
mkdir -p "$tmp/cfg-repo/.claude" "$HOME/ventures"
git init -q "$tmp/cfg-repo"
inception_fixture_write "$HOME/ventures/northwind" || exit 1
out=$(PLANWRIGHT_CONFIG_DEFAULTS="$tmp/core-defaults.yml" PLANWRIGHT_ADOPTER_OVERLAY="$tmp/no-adopter" \
  PLANWRIGHT_REPO_ROOT="$tmp/cfg-repo" PLANWRIGHT_LOCAL_CONFIG="" "$VT" show northwind T-1 2>&1)
rc=$?
assert_eq "a venture identifier resolves under ventures_root" 0 "$rc"
assert_contains "the resolved venture's task is read" "$(printf 'kind\tspike')" "$out"
vt show 'North_wind' T-1
assert_eq "an argument that is neither a path nor an identifier is refused" 2 "$rc"
vt show "$v" T-9
assert_eq "show refuses a task the plan does not hold" 1 "$rc"

sed 's/^- \*\*Target:\*\* venture direction/- **Target:** pricing/' "$v/plan.md" >"$tmp/plan.tmp" && mv "$tmp/plan.tmp" "$v/plan.md"
vt show "$v" T-3
assert_eq "D1.2 an alignment target naming no map row is refused" 1 "$rc"
assert_contains "D1.2 the refusal names the missing stakeholder" "stakeholder" "$out"
git -C "$v" checkout -q -- plan.md

# shellcheck disable=SC2016 # literal backtick fence, not an expansion
printf '\n```\n| pricing | Fenced Example | none | none |\n```\n' >>"$v/disciplines.md"
sed 's/^- \*\*Target:\*\* venture direction/- **Target:** pricing/' "$v/plan.md" >"$tmp/plan.tmp" && mv "$tmp/plan.tmp" "$v/plan.md"
vt show "$v" T-3
assert_eq "D1.2 a fenced example row is not a stakeholder" 1 "$rc"
git -C "$v" checkout -q -- plan.md disciplines.md

sed 's/^\*\*Format-version:\*\* 1.0/**Format-version:** 9.0/' "$v/plan.md" >"$tmp/plan.tmp" && mv "$tmp/plan.tmp" "$v/plan.md"
vt show "$v" T-1
assert_eq "an unsupported format version fails closed" 3 "$rc"
git -C "$v" checkout -q -- plan.md

# =========================================================================
# REQ-D1.6 / REQ-J1.3: dispatch through the standard backend seam
# =========================================================================

v=$(new_venture dispatch) || exit 1
brief_file="$tmp/brief.txt"
"$VT" brief "$v" T-2 >"$brief_file"
assert_eq "D1.6 brief exits 0" 0 "$?"
first=$(head -n 1 "$brief_file")
assert_eq "D1.6 the petition is an /execute-task invocation of the venture task" \
  "/planwright:execute-task T-2 $v" "$first"
assert_contains "D1.7 the petition carries the no-contact rule" "Never contact" "$(cat "$brief_file")"

sv="$tmp/spaced venture"
inception_fixture_write "$sv" || exit 1
vt brief "$sv" T-2
assert_eq "D1.6 a venture path that cannot travel as one argument is refused" 2 "$rc"

# The print rung prepares the launch without spawning; the subagent rung is
# harness-native and reported through the same seam. Dispatch resolves a launch
# tier through the allocation store, so it runs against this test's own fleet
# home and config, never the operator's.
mkdir -p "$tmp/fleet-home" "$tmp/adopter"
cp "$REPO_ROOT/config/defaults.yml" "$tmp/offload-defaults.yml" || exit 1
offload() {
  PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet-home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$tmp/offload-defaults.yml" \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" \
    PLANWRIGHT_REPO_ROOT=none \
    PLANWRIGHT_LOCAL_CONFIG="" \
    "$OFFLOAD" "$@"
}
out=$(offload dispatch print "$brief_file" 2>&1)
rc=$?
assert_eq "D1.6 the print rung takes the venture petition" 0 "$rc"
assert_contains "D1.6 the print rung prepares the launch" "$(printf 'status\tprepared')" "$out"
out=$(offload report subagent agent-venture-t2 2>&1)
rc=$?
assert_eq "D1.6 the subagent rung reports the venture worker" 0 "$rc"
assert_contains "D1.6 the subagent report names the backend" "$(printf 'backend\tsubagent')" "$out"

# J1.3: no parallel orchestration code path — the helper spawns no worker,
# drives no multiplexer, and reaches no network.
assert_eq "J1.3 the helper launches no worker or multiplexer" "" \
  "$(grep -nE '(^|[^a-z-])(claude|tmux|curl|wget|gh)( |$)' "$VT" | grep -v '^[0-9]*:#' | grep -v '"Bash(')"

# =========================================================================
# REQ-D1.1 / REQ-D1.3: the dispatched fixture task — a PR-less delivery
# commit, then findings plus register update in one accepted change
# =========================================================================

base=$(commit_count "$v")
findings "$v" T-2 research "A-2: validated — behavior"
vt deliver "$v" T-2
assert_eq "D1.3 delivering a validated update against a none threshold is refused" 1 "$rc"
assert_contains "D1.3 the refusal names the bundle finding" "ASM-EVIDENCE-REQUIRED" "$out"
assert_eq "D1.3 a refused delivery commits nothing" "$base" "$(commit_count "$v")"
assert_eq "D1.3 a refused delivery leaves the plan alone" "planned" "$(field_of "$v/plan.md" T-2 Status)"

# Give A-2 its pre-committed threshold, as an operator edit of its own.
sed 's/^- \*\*Threshold:\*\* none$/- **Threshold:** all three sinks accept a write without a manual step/' "$v/assumptions.md" \
  | awk 'BEGIN{n=0} /^- \*\*Threshold:\*\* all three/ { n++; if (n > 1) { print "- **Threshold:** none"; next } } { print }' >"$tmp/a.tmp"
mv "$tmp/a.tmp" "$v/assumptions.md"
git -C "$v" commit -q -am "set the A-2 threshold"
base=$(commit_count "$v")

vt deliver "$v" T-2
assert_eq "D1.1 deliver exits 0" 0 "$rc"
assert_eq "D1.1 delivery is one commit" "$((base + 1))" "$(commit_count "$v")"
assert_eq "D1.1 the delivery commit holds the findings and the plan only" "findings/T-2.md plan.md " "$(head_files "$v")"
assert_eq "D1.1 the task is delivered" "delivered" "$(field_of "$v/plan.md" T-2 Status)"
assert_eq "D1.4 delivery changes no register entry" "open" "$(field_of "$v/assumptions.md" A-2 Status)"
assert_eq "D1.1 nothing is left uncommitted" "" "$(git -C "$v" status --porcelain)"
vt check "$v"
assert_eq "D1.3 the delivery commit passes the check" 0 "$rc"

vt accept "$v" T-2
assert_eq "D1.4 accept without a named acceptor is refused" 2 "$rc"
vt accept --by "" "$v" T-2
assert_eq "D1.4 accept with an empty acceptor is refused" 2 "$rc"

sed 's/All three sinks/Two of the sinks/' "$v/findings/T-2.md" >"$tmp/f.tmp" && mv "$tmp/f.tmp" "$v/findings/T-2.md"
vt accept --by "Dana Reyes" "$v" T-2
assert_eq "D1.4 findings edited after delivery are not accepted" 1 "$rc"
git -C "$v" checkout -q -- findings/T-2.md

base=$(commit_count "$v")
vt accept --by "Dana Reyes" "$v" T-2
assert_eq "D1.3 accept exits 0" 0 "$rc"
assert_eq "D1.3 acceptance is one commit" "$((base + 1))" "$(commit_count "$v")"
assert_eq "D1.3 the accepted change holds findings and register update together" \
  "assumptions.md findings/T-2.md plan.md " "$(head_files "$v")"
assert_eq "D1.3 the assumption status flipped" "validated" "$(field_of "$v/assumptions.md" A-2 Status)"
assert_eq "D1.3 the evidence cites the findings with its grade" "behavior — T-2 findings" "$(field_of "$v/assumptions.md" A-2 Evidence)"
assert_eq "D1.3 the task is accepted" "accepted" "$(field_of "$v/plan.md" T-2 Status)"
assert_contains "D1.4 the findings carry the acceptance record" "Accepted-by: Dana Reyes" "$(cat "$v/findings/T-2.md")"
assert_lint_md "D1.4 the findings with the acceptance record" "$v/findings/T-2.md"
assert_eq "D1.3 Last reviewed is bumped on the changed register" "**Last reviewed:** 2026-10-18" "$(grep -m1 'Last reviewed' "$v/assumptions.md")"
assert_eq "D1.3 the untouched register keeps its date" "**Last reviewed:** 2026-08-20" "$(grep -m1 'Last reviewed' "$v/decisions.md")"
"$REPO_ROOT/scripts/inception-validate.sh" "$v" >/dev/null 2>&1
assert_eq "D1.3 the accepted bundle validates clean" 0 "$?"
vt check "$v"
assert_eq "D1.3 the acceptance commit passes the check" 0 "$rc"
vt accept --by "Dana Reyes" "$v" T-2
assert_eq "an accepted task cannot be accepted again" 1 "$rc"

# =========================================================================
# REQ-D1.3: the per-commit check catches the non-atomic shapes
# =========================================================================

v=$(new_venture check) || exit 1
# A findings-only completion: T-1 accepted with its findings, no register flip.
findings "$v" T-1 spike "A-1: validated — behavior"
sed '/^### T-1 /,/^### T-2 /s/^- \*\*Status:\*\* running/- **Status:** accepted/' "$v/plan.md" >"$tmp/p.tmp" && mv "$tmp/p.tmp" "$v/plan.md"
git -C "$v" add -A && git -C "$v" commit -q -m "findings only"
vt check "$v"
assert_eq "D1.3 a findings-only completion commit fails the check" 1 "$rc"
assert_contains "D1.3 the finding names the missing register update" "A-1" "$out"

v=$(new_venture check1b) || exit 1
# A Tests: field wrapped onto a continuation line still links both ids.
awk '/^### T-1 /{a=1} /^### T-2 /{a=0} a && /^- \*\*Tests:\*\*/ { print "- **Tests:** A-1,"; print "  A-2"; next } { print }' "$v/plan.md" >"$tmp/p.tmp" && mv "$tmp/p.tmp" "$v/plan.md"
git -C "$v" commit -q -am "T-1 also tests A-2"
findings "$v" T-1 spike "A-1: validated — behavior"
sed '/^### T-1 /,/^### T-2 /s/^- \*\*Status:\*\* running/- **Status:** accepted/' "$v/plan.md" >"$tmp/p.tmp" && mv "$tmp/p.tmp" "$v/plan.md"
awk '/^### A-1 /{a=1} /^### A-2 /{a=0} a && /^- \*\*Status:\*\*/ { print "- **Status:** validated"; next } { print }' "$v/assumptions.md" >"$tmp/a.tmp" && mv "$tmp/a.tmp" "$v/assumptions.md"
git -C "$v" add -A && git -C "$v" commit -q -m "accept without the A-2 update"
vt check "$v"
assert_eq "D1.3 a wrapped Tests id still needs its update in the acceptance" 1 "$rc"
assert_contains "D1.3 the finding names the wrapped id" "A-2 register update" "$out"

v=$(new_venture check2) || exit 1
# A register update before acceptance: A-2 cites T-2 findings, T-2 untouched.
awk '/^### A-2 /{a=1} /^### A-3 /{a=0} a && /^- \*\*Evidence:\*\*/ { print "- **Evidence:** behavior — T-2 findings"; next } { print }' "$v/assumptions.md" >"$tmp/a.tmp" && mv "$tmp/a.tmp" "$v/assumptions.md"
git -C "$v" commit -q -am "early update"
vt check "$v"
assert_eq "D1.3 a register update ahead of acceptance fails the check" 1 "$rc"
assert_contains "D1.3 the finding names the unaccepted task" "T-2" "$out"

v=$(new_venture check3) || exit 1
# Orphaned findings: a findings file committed with its task left planned.
findings "$v" T-2 research "A-2: testing — opinion"
git -C "$v" add -A && git -C "$v" commit -q -m "orphan"
vt check "$v"
assert_eq "D1.3 findings committed for an undelivered task fail the check" 1 "$rc"
vt check "$v" HEAD~1
assert_eq "the check reads a named commit" 0 "$rc"
vt check "$v" --all
assert_eq "the check refuses an option-shaped commit" 2 "$rc"

# =========================================================================
# deliver refusals: the findings document must match the task
# =========================================================================

v=$(new_venture refuse) || exit 1
vt deliver "$v" T-2
assert_eq "deliver without a findings document is refused" 1 "$rc"
findings "$v" T-2 research
vt deliver "$v" T-2
assert_eq "D1.3 deliver with no register update is refused" 1 "$rc"
findings "$v" T-2 research "A-2: testing — opinion" "A-1: testing — opinion"
vt deliver "$v" T-2
assert_eq "D1.3 an update to an id the task does not test is refused" 1 "$rc"
findings "$v" T-2 research "A-2: testing — hunch"
vt deliver "$v" T-2
assert_eq "an update off the evidence ladder is refused" 1 "$rc"
findings "$v" T-2 research "A-2: validated — none"
vt deliver "$v" T-2
assert_eq "a validated update without a grade is refused" 1 "$rc"
findings "$v" T-2 spike "A-2: testing — opinion"
vt deliver "$v" T-2
assert_eq "a findings kind that disagrees with the plan is refused" 1 "$rc"
findings "$v" T-2 research "A-2: testing — opinion"
printf '\n## Acceptance\n\nAccepted-by: Dana Reyes\nDate: 2026-10-18\n' >>"$v/findings/T-2.md"
vt deliver "$v" T-2
assert_eq "D1.4 findings that pre-record their own acceptance are refused" 1 "$rc"
findings "$v" T-2 research "$(printf 'A-2: testing — opinion\033[2J')"
vt deliver "$v" T-2
assert_eq "an update carrying a control character is refused" 1 "$rc"
assert_not_contains "the refusal does not echo the control character" "$(printf '\033')" "$out"
mv "$v/findings/T-2.md" "$tmp/real.md"
findings "$v" T-2 research "A-2: testing — opinion"
mv "$v/findings/T-2.md" "$tmp/real.md"
ln -s "$tmp/real.md" "$v/findings/T-2.md"
vt deliver "$v" T-2
assert_eq "a symlinked findings document is refused" 1 "$rc"
rm -f "$v/findings/T-2.md"
findings "$v" T-2 research "A-2: testing — opinion"
printf '\nedit in flight\n' >>"$v/plan.md"
vt deliver "$v" T-2
assert_eq "deliver over an uncommitted plan edit is refused" 1 "$rc"
git -C "$v" checkout -q -- plan.md
assert_eq "refusals commit nothing" 1 "$(commit_count "$v")"

# =========================================================================
# REQ-D1.2 / REQ-D1.7: alignment — a human performs it, with the named
# stakeholder; a one-way decision is accepted only by its decider
# =========================================================================

v=$(new_venture align) || exit 1
awk '/^### DEC-1 /{a=1} /^### DEC-2 /{a=0} a && /^- \*\*Door:\*\*/ { print "- **Door:** one-way"; next } { print }' "$v/decisions.md" >"$tmp/d.tmp" && mv "$tmp/d.tmp" "$v/decisions.md"
git -C "$v" commit -q -am "DEC-1 is one-way"
findings "$v" T-3 alignment "DEC-1: decided — end-of-shift handover only (2026-10-18)"
vt deliver "$v" T-3
assert_eq "D1.7 an alignment delivery without its human performer is refused" 1 "$rc"
assert_contains "D1.7 the refusal names the performer line" "Performed-by" "$out"
PERFORMED="Kim Alvarez" STAKEHOLDER="Kim Alvarez" findings "$v" T-3 alignment "DEC-1: decided — end-of-shift handover only (2026-10-18)"
vt deliver "$v" T-3
assert_eq "D1.2 an alignment delivery naming the wrong stakeholder is refused" 1 "$rc"
PERFORMED="Kim Alvarez" STAKEHOLDER="Dana Reyes" findings "$v" T-3 alignment "DEC-1: decided — end-of-shift handover only (2026-10-18)"
vt deliver "$v" T-3
assert_eq "D1.2 an alignment delivery with the target's decider is accepted for review" 0 "$rc"
vt accept --by "Kim Alvarez" "$v" T-3
assert_eq "a one-way decision is not accepted by a non-decider" 1 "$rc"
assert_eq "the refused acceptance leaves the decision open" "open" "$(field_of "$v/decisions.md" DEC-1 Status)"
vt accept --by "Dana Reyes" "$v" T-3
assert_eq "the decider accepts the one-way decision" 0 "$rc"
assert_eq "the decision status is recorded" "decided" "$(field_of "$v/decisions.md" DEC-1 Status)"
assert_eq "the decision outcome is recorded" "end-of-shift handover only (2026-10-18)" "$(field_of "$v/decisions.md" DEC-1 Outcome)"
assert_eq "the acceptance commit holds decisions, findings and plan" "decisions.md findings/T-3.md plan.md " "$(head_files "$v")"
assert_lint_md "the decision's findings with the acceptance record" "$v/findings/T-3.md"

# =========================================================================
# reject: the registers stay untouched; the task returns to running or drops
# =========================================================================

v=$(new_venture reject) || exit 1
findings "$v" T-2 research "A-2: testing — opinion"
vt deliver "$v" T-2
vt reject --by "Dana Reyes" "$v" T-2
assert_eq "reject without a reason is refused" 2 "$rc"
vt reject --by "Dana Reyes" --reason "the sinks were not the production ones" "$v" T-2
assert_eq "reject exits 0" 0 "$rc"
assert_eq "a rejected task returns to running" "running" "$(field_of "$v/plan.md" T-2 Status)"
assert_eq "a rejection touches no register" "findings/T-2.md plan.md " "$(head_files "$v")"
assert_contains "the findings carry the rejection record" "Rejected-by: Dana Reyes" "$(cat "$v/findings/T-2.md")"
assert_lint_md "rejected findings" "$v/findings/T-2.md"
vt check "$v"
assert_eq "D1.3 a rejection commit passes the check" 0 "$rc"
findings "$v" T-2 research "A-2: testing — opinion"
vt deliver "$v" T-2
assert_eq "a reworked task delivers again" 0 "$rc"
vt reject --by "Dana Reyes" --reason "superseded by a cheaper test" --drop "$v" T-2
assert_eq "a dropped task is dropped" "dropped" "$(field_of "$v/plan.md" T-2 Status)"

# =========================================================================
# REQ-D1.5: spikes are disposable and never graduate
# =========================================================================

v=$(new_venture spikes) || exit 1
vt spike-init "$v" T-1
assert_eq "spike-init exits 0" 0 "$rc"
marked=no
[ -f "$v/spikes/T-1/DISPOSABLE.md" ] && marked=yes
assert_eq "D1.5 spike-init marks the spike directory disposable" yes "$marked"
assert_lint_md "D1.5 DISPOSABLE.md" "$v/spikes/T-1/DISPOSABLE.md"
printf 'print("spike")\n' >"$v/spikes/T-1/main.py"
vt spikes "$v"
assert_eq "D1.5 a marked spike passes" 0 "$rc"
mkdir -p "$v/spikes/T-2"
printf 'x\n' >"$v/spikes/T-2/run.sh"
vt spikes "$v"
assert_eq "D1.5 an unmarked spike directory is flagged" 1 "$rc"
rm -rf "$v/spikes/T-2"
mkdir -p "$tmp/seed"
printf '# seed\n\nSee the measured share in the T-1 findings.\n' >"$tmp/seed/seed.md"
vt spikes "$v" "$tmp/seed"
assert_eq "D1.5 a seed without spike references passes" 0 "$rc"
printf 'Reuse spikes/T-1/main.py as the starting point.\n' >>"$tmp/seed/seed.md"
vt spikes "$v" "$tmp/seed"
assert_eq "D1.5 spike code referenced from a seed package is flagged" 1 "$rc"
assert_contains "D1.5 the finding names the seed file" "seed.md" "$out"

sv2=$(new_venture spikes-nodir) || exit 1
findings "$sv2" T-1 spike "A-1: testing — synthetic"
vt deliver "$sv2" T-1
assert_eq "D1.5 a spike delivery without its spike directory is refused" 1 "$rc"

findings "$v" T-1 spike "A-1: testing — synthetic"
mkdir -p "$v/spikes/T-1b"
rm -f "$v/spikes/T-1/DISPOSABLE.md"
vt deliver "$v" T-1
assert_eq "D1.5 a spike delivery with an unmarked spike directory is refused" 1 "$rc"
rm -rf "$v/spikes/T-1b"
vt spike-init "$v" T-1
vt deliver "$v" T-1
assert_eq "D1.5 a marked spike delivers" 0 "$rc"
assert_contains "D1.5 the spike code rides the delivery commit" "spikes/T-1/main.py" "$(head_files "$v")"

# =========================================================================
# plain rung: no git, the files are still written
# =========================================================================

pv="$tmp/plain"
inception_fixture_write "$pv" || exit 1
findings "$pv" T-2 research "A-2: testing — opinion"
vt deliver "$pv" T-2
assert_eq "plain rung: deliver exits 0" 0 "$rc"
assert_contains "plain rung: the save is reported as plain" "$(printf 'saved\tplain')" "$out"
vt accept --by "Dana Reyes" "$pv" T-2
assert_eq "plain rung: accept exits 0" 0 "$rc"
assert_eq "plain rung: the register is updated" "testing" "$(field_of "$pv/assumptions.md" A-2 Status)"
assert_eq "plain rung: the opinion grade is recorded" "opinion — T-2 findings" "$(field_of "$pv/assumptions.md" A-2 Evidence)"

# =========================================================================
# REQ-D1.7: the worker deny-list, and the /execute-task hook
# =========================================================================

vt worker-settings
assert_eq "D1.7 worker-settings exits 0" 0 "$rc"
assert_contains "D1.7 the settings deny outward channels" '"deny"' "$out"
assert_contains "D1.7 the settings deny issue and PR comments" 'Bash(gh pr comment:*)' "$out"
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$out" | jq -e '.permissions.deny | length > 0' >/dev/null
  assert_eq "D1.7 the settings are valid JSON" 0 "$?"
fi

assert_eq "J1.3 /execute-task routes a venture task to the contract" 1 \
  "$(grep -c '^Doctrine: point-of-use venture-task' "$EXEC_SKILL")"
assert_eq "J1.3 /execute-task names the venture task id form" 1 \
  "$(grep -c 'T-<n>' "$EXEC_SKILL")"

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all venture-task tests passed"
