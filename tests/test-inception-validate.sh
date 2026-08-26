#!/bin/bash
# Tests for the inception bundle validator (inception Task 2; REQ-A1.9,
# REQ-C1.7, REQ-C1.8, REQ-G1.1, REQ-G1.5 · D-12).
#
# Shape: one golden compliant bundle (tests/lib/inception-fixture.sh) that must
# validate clean, then one seeded violation per enforced rule. Every finding the
# validator emits carries a stable rule code in square brackets, and the last
# assertion here closes the loop both ways: every code `--rules` advertises is
# exercised by a fixture below, and every code a fixture expects is advertised.
# That is the task's "each enforced rule has a seeded-violation fixture"
# condition made mechanical rather than promised.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATE="$REPO_ROOT/scripts/inception-validate.sh"

# shellcheck source=tests/lib/inception-fixture.sh
. "$REPO_ROOT/tests/lib/inception-fixture.sh"

failures=0
exercised=""

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
      echo "FAIL: $1 (expected to find '$2' in output)" >&2
      echo "--- output ---" >&2
      printf '%s\n' "$3" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_not_contains() {
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (did not expect '$2' in output)" >&2
      echo "--- output ---" >&2
      printf '%s\n' "$3" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -x "$VALIDATE" ]; then
  echo "FAIL: validator missing or not executable at $VALIDATE" >&2
  exit 1
fi

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# fresh [tracked] — a private copy of the golden bundle; prints its path. Each
# call gets its own directory: the cases mutate in place, and a couple of them
# turn the copy into a git repo, so reuse would leak state across cases.
fresh() {
  d="$(mktemp -d "$tmp/bXXXXXX")" || exit 1
  inception_fixture_write "$d" "${1:-untracked}" || exit 1
  printf '%s' "$d"
}

# sed_i <file> <expr> — portable in-place sed (no GNU/BSD -i divergence).
sed_i() {
  sed "$2" "$1" >"$1.new" && mv "$1.new" "$1"
}

# del_line <file> <basic-regex> — drop every matching line. The address
# delimiter is `%` because several of the patterns below match table rows and
# carry literal `|`.
del_line() {
  sed "\\%$2%d" "$1" >"$1.new" && mv "$1.new" "$1"
}

# insert_after <file> <literal-line> <text-file> — splice <text-file>'s lines in
# after the first line equal to <literal-line>. Literal comparison, so em-dashes
# and regex metacharacters in the anchor need no escaping.
insert_after() {
  awk -v anchor="$2" -v ins="$3" '
    { print }
    !done && $0 == anchor { while ((getline l < ins) > 0) print l; done = 1 }
  ' "$1" >"$1.new" && mv "$1.new" "$1"
}

# expect <desc> <code> <expected-exit> <bundle-dir> [extra validator args...]
expect() {
  e_desc=$1
  e_code=$2
  e_exit=$3
  e_dir=$4
  shift 4
  e_out="$("$VALIDATE" "$@" "$e_dir" 2>&1)"
  e_rc=$?
  assert_eq "$e_desc: exit" "$e_exit" "$e_rc"
  assert_contains "$e_desc: reports [$e_code]" "[$e_code]" "$e_out"
  case " $exercised " in
    *" $e_code "*) ;;
    *) exercised="$exercised $e_code" ;;
  esac
}

# ---------------------------------------------------------------------------
# 0. The golden bundle validates clean, in both shapes.
# ---------------------------------------------------------------------------
b="$(fresh)"
out="$("$VALIDATE" "$b" 2>&1)"
rc=$?
assert_eq "compliant untracked bundle: exit 0" "0" "$rc"
assert_not_contains "compliant untracked bundle: no findings" "ERROR" "$out"

b="$(fresh tracked)"
out="$("$VALIDATE" "$b" 2>&1)"
rc=$?
assert_eq "compliant tracked bundle: exit 0" "0" "$rc"
assert_not_contains "compliant tracked bundle: no findings" "ERROR" "$out"

# A bundle path that is not a directory is an environment error, not a finding.
out="$("$VALIDATE" "$tmp/nope" 2>&1)"
rc=$?
assert_eq "missing bundle dir: exit 2" "2" "$rc"

# ---------------------------------------------------------------------------
# 1. Format-version gating — fail closed, and never parse on (REQ-C1.7).
# ---------------------------------------------------------------------------
b="$(fresh)"
del_line "$b/plan.md" '^\*\*Format-version:\*\* 1\.0$'
expect "format-version absent from a file" FMT-MISSING 3 "$b"

b="$(fresh)"
for f in brief disciplines assumptions decisions plan; do
  sed_i "$b/$f.md" 's|^\*\*Format-version:\*\* 1\.0$|**Format-version:** 2.0|'
done
out="$("$VALIDATE" "$b" 2>&1)"
rc=$?
assert_eq "unsupported major: exit 3" "3" "$rc"
assert_contains "unsupported major: reports [FMT-UNSUPPORTED]" "[FMT-UNSUPPORTED]" "$out"
assert_contains "unsupported major: names the found version" "2.0" "$out"
assert_contains "unsupported major: names the supported version" "1" "$out"
assert_not_contains "unsupported major: no other rule ran" "[ASM-" "$out"
exercised="$exercised FMT-UNSUPPORTED"

b="$(fresh)"
sed_i "$b/plan.md" 's|^\*\*Format-version:\*\* 1\.0$|**Format-version:** 1.1|'
expect "format-version mirrors disagree" FMT-MIRROR 1 "$b"

# The version gate is also available on its own, for the renderer and the skill
# (REQ-C1.7: they invoke the validator's check rather than re-implementing it).
b="$(fresh)"
out="$("$VALIDATE" --version-check "$b" 2>&1)"
rc=$?
assert_eq "--version-check on a supported bundle: exit 0" "0" "$rc"
b="$(fresh)"
sed_i "$b/brief.md" 's|^\*\*Format-version:\*\* 1\.0$|**Format-version:** 9.0|'
out="$("$VALIDATE" --version-check "$b" 2>&1)"
rc=$?
assert_eq "--version-check on an unsupported bundle: exit 3" "3" "$rc"
assert_contains "--version-check: plain-language refusal" "unsupported" "$out"
# The version-only gate must not report the rest of the bundle's findings.
b="$(fresh)"
del_line "$b/plan.md" '^- \*\*Cap:\*\*'
out="$("$VALIDATE" --version-check "$b" 2>&1)"
rc=$?
assert_eq "--version-check ignores non-version findings: exit 0" "0" "$rc"

# ---------------------------------------------------------------------------
# 2. File set and header block.
# ---------------------------------------------------------------------------
b="$(fresh)"
rm -f "$b/plan.md"
expect "an authored file is absent" FILE-MISSING 3 "$b"

# An open fence means the rest of the file lexed as documentation, so half a
# parse is refused rather than reported as content findings.
b="$(fresh)"
printf '%s\n' '' '```' 'an illustration nobody closed' >>"$b/decisions.md"
expect "a code fence is left open" FENCE-UNBALANCED 3 "$b"

# A closed fence is documentation: content inside it never satisfies a check
# and never raises one.
b="$(fresh)"
printf '%s\n' '' '```markdown' '### A-1 — a fenced illustration, not an entry' '```' >>"$b/assumptions.md"
out="$("$VALIDATE" "$b" 2>&1)"
rc=$?
assert_eq "fenced illustration is documentation: exit 0" "0" "$rc"

b="$(fresh)"
sed_i "$b/brief.md" '1s|.*|# Northwind Signals — Overview|'
expect "title role token is not the file's role" HDR-ROLE 1 "$b"

b="$(fresh)"
del_line "$b/plan.md" '^\*\*Status:\*\* Exploring$'
expect "status declaration absent" HDR-STATUS 1 "$b"

b="$(fresh)"
for f in brief disciplines assumptions decisions plan; do
  sed_i "$b/$f.md" 's|^\*\*Status:\*\* Exploring$|**Status:** Cruising|'
done
expect "status off the lifecycle enum" HDR-STATUS 1 "$b"

b="$(fresh)"
sed_i "$b/plan.md" 's|^\*\*Status:\*\* Exploring$|**Status:** On-hold|'
expect "status mirror disagrees with brief.md" HDR-STATUS-MIRROR 1 "$b"

b="$(fresh)"
sed_i "$b/plan.md" 's|^\*\*Last reviewed:\*\* 2026-08-20$|**Last reviewed:** Aug 20|'
expect "last-reviewed is not an ISO date" HDR-REVIEWED 1 "$b"

# ISO SHAPE is not the same as a date that exists. A day that never happened
# reaches the renderer, which turns it into a kill-criterion state.
b="$(fresh)"
sed_i "$b/plan.md" 's|^\*\*Last reviewed:\*\* 2026-08-20$|**Last reviewed:** 2026-02-30|'
expect "last-reviewed is a day that does not exist" HDR-REVIEWED 1 "$b"

# ---------------------------------------------------------------------------
# 3. ID grammar, uniqueness, supersession.
# ---------------------------------------------------------------------------
b="$(fresh)"
sed_i "$b/assumptions.md" 's|^### A-1 —|### A-one —|'
expect "register entry id off the grammar" ID-GRAMMAR 1 "$b"

b="$(fresh)"
printf '%s\n' '' '### A-2 — a re-used number' \
  '- **Statement:** believe x; verify y; measure z; right if w.' \
  '- **Risk-if-wrong:** none' '- **Risk-tag:** feasibility' '- **Threshold:** none' \
  '- **Evidence:** none' '- **Blocking:** no' '- **Tasks:** none' \
  '- **Status:** open' >>"$b/assumptions.md"
expect "two entries share an id" ID-DUPLICATE 1 "$b"

b="$(fresh)"
sed_i "$b/assumptions.md" 's|^- \*\*Superseded-by:\*\* A-4 (2026-08-10)$|- **Superseded-by:** A-9 (2026-08-10)|'
expect "supersession points at an id that does not exist" ID-SUPERSEDE-TARGET 1 "$b"

# ---------------------------------------------------------------------------
# 4. assumptions.md register fields (REQ-C1.3's sharpened set).
# ---------------------------------------------------------------------------
b="$(fresh)"
del_line "$b/assumptions.md" '^- \*\*Risk-if-wrong:\*\* the fan-out saves no time'
expect "assumption is missing a required field" ASM-FIELD-MISSING 1 "$b"

b="$(fresh)"
sed_i "$b/assumptions.md" 's|^- \*\*Statement:\*\* believe ops leads will file once instead of three times; verify with a two-week$|- **Statement:** ops leads will file once instead of three times, probably, and that|'
expect "statement skips the believe/verify/measure/right-if skeleton" ASM-STATEMENT-SKELETON 1 "$b"

b="$(fresh)"
sed_i "$b/assumptions.md" 's|^- \*\*Risk-tag:\*\* value$|- **Risk-tag:** delight|'
expect "risk tag off the four-risk enum" ASM-RISK-TAG 1 "$b"

b="$(fresh)"
sed_i "$b/assumptions.md" 's|^- \*\*Evidence:\*\* stated-intent — handover interviews$|- **Evidence:** hearsay — handover interviews|'
expect "evidence grade off the ladder" ASM-GRADE 1 "$b"

b="$(fresh)"
sed_i "$b/assumptions.md" 's|^- \*\*Blocking:\*\* yes$|- **Blocking:** probably|'
expect "blocking flag is not yes or no" ASM-BLOCKING 1 "$b"

b="$(fresh)"
sed_i "$b/assumptions.md" 's|^- \*\*Status:\*\* testing$|- **Status:** pondering|'
expect "assumption status off the enum" ASM-STATUS 1 "$b"

b="$(fresh)"
sed_i "$b/assumptions.md" 's|^- \*\*Status:\*\* open$|- **Status:** validated|'
expect "validated assumption still carries none for threshold and evidence" ASM-EVIDENCE-REQUIRED 1 "$b"

b="$(fresh)"
sed_i "$b/assumptions.md" 's|^- \*\*Status:\*\* waived — internal tool.*$|- **Status:** waived|'
expect "waived assumption records no reason" ASM-WAIVED-REASON 1 "$b"

b="$(fresh)"
sed_i "$b/assumptions.md" 's|^- \*\*Tasks:\*\* T-1$|- **Tasks:** T-9|'
expect "assumption links a task that does not exist" ASM-TASK-REF 1 "$b"

# ---------------------------------------------------------------------------
# 5. decisions.md register fields (REQ-C1.4's MADR set).
# ---------------------------------------------------------------------------
b="$(fresh)"
del_line "$b/decisions.md" '^- \*\*Feed-forward:\*\* the capture-surface spec'
expect "decision is missing a required field" DEC-FIELD-MISSING 1 "$b"

b="$(fresh)"
sed_i "$b/decisions.md" 's|^- \*\*Status:\*\* open$|- **Status:** pondering|'
expect "decision status off the enum" DEC-STATUS 1 "$b"

b="$(fresh)"
sed_i "$b/decisions.md" 's|^- \*\*Door:\*\* two-way$|- **Door:** revolving|'
expect "door class off the enum" DEC-DOOR 1 "$b"

b="$(fresh)"
del_line "$b/decisions.md" '^  - end-of-shift handover only'
del_line "$b/decisions.md" '^  - every incident close'
expect "decision lists no options" DEC-OPTIONS 1 "$b"

b="$(fresh)"
sed_i "$b/decisions.md" 's|^- \*\*Deciders:\*\* Dana Reyes$|- **Deciders:** Sam Okafor|'
expect "decider is not in a Decides cell" DEC-DECIDER-UNKNOWN 1 "$b"

b="$(fresh)"
sed_i "$b/decisions.md" 's|^- \*\*Discipline:\*\* product-strategy$|- **Discipline:** astrology|'
expect "owning discipline is not in the discipline map" DEC-DISCIPLINE-UNKNOWN 1 "$b"

# ---------------------------------------------------------------------------
# 6. plan.md task fields (REQ-C1.5's field set; ordering is Task 11's).
# ---------------------------------------------------------------------------
b="$(fresh)"
del_line "$b/plan.md" '^- \*\*Cap:\*\* two weeks of elapsed time'
expect "plan task is missing a required field" PLAN-FIELD-MISSING 1 "$b"

b="$(fresh)"
sed_i "$b/plan.md" 's|^- \*\*Kind:\*\* spike$|- **Kind:** vibes|'
expect "task kind off the enum" PLAN-KIND 1 "$b"

b="$(fresh)"
sed_i "$b/plan.md" 's|^- \*\*Status:\*\* planned$|- **Status:** pondering|'
expect "task status off the enum" PLAN-STATUS 1 "$b"

b="$(fresh)"
sed_i "$b/plan.md" 's|^- \*\*Tests:\*\* A-1$|- **Tests:** none|'
expect "task traces to nothing" PLAN-TESTS-EMPTY 1 "$b"

b="$(fresh)"
sed_i "$b/plan.md" 's|^- \*\*Tests:\*\* A-1$|- **Tests:** A-9|'
expect "task traces to an id that does not exist" PLAN-TESTS-REF 1 "$b"

b="$(fresh)"
del_line "$b/plan.md" '^- \*\*Target:\*\* venture direction$'
expect "alignment task carries no target" PLAN-TARGET 1 "$b"

b="$(fresh)"
printf '%s\n' '- **Target:** venture direction' >"$tmp/ins"
insert_after "$b/plan.md" '- **Kind:** spike' "$tmp/ins"
expect "non-alignment task carries a target" PLAN-TARGET 1 "$b"

b="$(fresh)"
sed_i "$b/plan.md" 's|^- \*\*Target:\*\* venture direction$|- **Target:** vibes alignment|'
expect "target names no stakeholder-map decision area" PLAN-TARGET 1 "$b"

# ---------------------------------------------------------------------------
# 7. brief.md structure, prompts, minimum core (REQ-C1.8).
# ---------------------------------------------------------------------------
b="$(fresh)"
sed_i "$b/brief.md" 's|^## Strategy fit$|## Strategy|'
expect "a required brief section is absent" BRIEF-SECTION-MISSING 1 "$b"

b="$(fresh)"
printf '%s\n' '' '## Sources' '' '- **early** — an out-of-order register — nowhere' >"$tmp/ins"
insert_after "$b/brief.md" '**Format-version:** 1.0' "$tmp/ins"
expect "required brief sections are out of order" BRIEF-SECTION-ORDER 1 "$b"

b="$(fresh)"
del_line "$b/brief.md" '^_Skipped: appetite is set at the portfolio level'
expect "a prompt section is empty with no stated reason" BRIEF-SKIP-FORM 1 "$b"

b="$(fresh)"
printf '%s\n' '' '_Skipped: no time._' >"$tmp/ins"
insert_after "$b/brief.md" '## Sources' "$tmp/ins"
expect "a non-prompt section carries the skip form" BRIEF-SKIP-FORM 1 "$b"

b="$(fresh)"
sed_i "$b/brief.md" 's|^Median incident-handover time drops below ten minutes within one quarter of adoption.$|_Skipped: not decided yet._|'
expect "success metric is skipped" BRIEF-METRIC-EMPTY 1 "$b"

b="$(fresh)"
del_line "$b/brief.md" '^- \*\*KC-'
expect "no kill criterion is set" KC-MISSING 1 "$b"

b="$(fresh)"
sed_i "$b/brief.md" 's|^- \*\*KC-2:\*\* the handover-time measurement pipeline reports weekly — by 2026-09-15$|- **KC-2:** the handover-time measurement pipeline reports weekly|'
expect "kill criterion carries no date" KC-FORM 1 "$b"

b="$(fresh)"
sed_i "$b/brief.md" 's|^- \*\*KC-2:\*\* the handover-time measurement pipeline reports weekly — by 2026-09-15$|- **KC-2:** the handover-time measurement pipeline reports weekly — by 2026-02-30|'
expect "kill-criterion date is a day that does not exist" KC-FORM 1 "$b"

b="$(fresh)"
del_line "$b/brief.md" '^\*\*Gate decider:\*\* Dana Reyes$'
expect "no gate decider is named" KC-DECIDER-MISSING 1 "$b"

b="$(fresh)"
sed_i "$b/brief.md" 's|^\*\*Gate decider:\*\* Dana Reyes$|**Gate decider:** Sam Okafor|'
expect "gate decider is not in a Decides cell" KC-DECIDER-UNKNOWN 1 "$b"

b="$(fresh)"
sed_i "$b/brief.md" 's|^- \*\*workflow audit\*\* — |- workflow audit — |'
expect "sources entry has no bold name lead" SRC-FORM 1 "$b"

# ---------------------------------------------------------------------------
# 8. disciplines.md: the three maps (REQ-C1.10).
# ---------------------------------------------------------------------------
b="$(fresh)"
sed_i "$b/disciplines.md" 's|^## Staffing table$|## Staffing|'
expect "a required disciplines section is absent" DIS-SECTION 1 "$b"

b="$(fresh)"
sed_i "$b/disciplines.md" 's:^| product-strategy | agent-persona | product-strategy |$:| product-strategy | robot | product-strategy |:'
expect "staffing token off the enum" DIS-STAFFING-TOKEN 1 "$b"

b="$(fresh)"
del_line "$b/disciplines.md" '^| org-design | unstaffed | none |$'
expect "a mapped discipline has no staffing row" DIS-STAFFING-COVERAGE 1 "$b"

b="$(fresh)"
sed_i "$b/disciplines.md" 's:| DEC-1 |$:| DEC-9 |:'
expect "discipline map cites a decision that does not exist" DIS-DECISION-REF 1 "$b"

b="$(fresh)"
sed_i "$b/disciplines.md" 's:^| venture direction | Dana Reyes | Kim Alvarez | ops leads |$:| venture direction | Dana Reyes, Kim Alvarez | Kim Alvarez | ops leads |:'
expect "a Decides cell holds more than one name" STK-DECIDES-SINGLE 1 "$b"

# ---------------------------------------------------------------------------
# 9. Track labels (REQ-C1.11).
# ---------------------------------------------------------------------------
b="$(fresh tracked)"
printf '%s\n' '- **Bad Label** — a track whose label is off the grammar' >"$tmp/ins"
insert_after "$b/brief.md" '- **measure** — the handover-time measurement pipeline' "$tmp/ins"
expect "track label off the grammar" TRK-LABEL 1 "$b"

b="$(fresh tracked)"
sed_i "$b/plan.md" 's|^- \*\*Track:\*\* measure$|- **Track:** shipping|'
expect "entry references an undeclared track" TRK-UNDECLARED 1 "$b"

b="$(fresh)"
printf '%s\n' '- **Track:** capture' >"$tmp/ins"
insert_after "$b/plan.md" '- **Status:** running' "$tmp/ins"
expect "track field in an untracked venture" TRK-UNTRACKED 1 "$b"

# ---------------------------------------------------------------------------
# 10. Gate records — the venture's audit trail (REQ-E1.5).
# ---------------------------------------------------------------------------
b="$(fresh)"
sed_i "$b/brief.md" 's|^### Gate 1 — 2026-08-18$|### Gate one — 2026-08-18|'
expect "gate heading off the grammar" GATE-HEADING 1 "$b"

b="$(fresh)"
sed_i "$b/brief.md" 's|^### Gate 1 — 2026-08-18$|### Gate 1 — 2026-02-30|'
sed_i "$b/brief.md" 's|^Date: 2026-08-18$|Date: 2026-02-30|'
expect "gate is dated a day that does not exist" GATE-HEADING 1 "$b"

b="$(fresh)"
printf '%s\n' '' '### Gate 3 — 2026-08-20' '' 'Outcome: Recycle' 'Date: 2026-08-20' \
  'Decider: Dana Reyes' 'Evidence: none' 'Thresholds: A-1 open, A-2 open' \
  'Kill-criteria: KC-1 clear, KC-2 clear' 'Rationale: still waiting.' >"$tmp/ins"
insert_after "$b/brief.md" 'Rationale: The capture-surface spike has not run yet; re-scope the plan and return.' "$tmp/ins"
expect "gate numbering skips a run" GATE-SEQUENCE 1 "$b"

b="$(fresh)"
del_line "$b/brief.md" '^Decider: Dana Reyes$'
expect "gate record is missing a required line" GATE-FIELD-MISSING 1 "$b"

b="$(fresh)"
sed_i "$b/brief.md" 's|^Date: 2026-08-18$|Date: 2026-08-19|'
expect "gate heading date and Date line disagree" GATE-DATE-MISMATCH 1 "$b"

b="$(fresh)"
sed_i "$b/brief.md" 's|^Outcome: Recycle$|Outcome: Maybe|'
expect "gate outcome off the enum" GATE-OUTCOME 1 "$b"

b="$(fresh)"
sed_i "$b/brief.md" 's|^Decider: Dana Reyes$|Decider: Kim Alvarez|'
expect "gate record decider is not the venture gate decider" GATE-DECIDER 1 "$b"

b="$(fresh)"
sed_i "$b/brief.md" 's|^Evidence: A-1 (stated-intent)$|Evidence: A-1 stated-intent|'
expect "gate evidence item off the form" GATE-EVIDENCE-FORM 1 "$b"

b="$(fresh)"
sed_i "$b/brief.md" 's|^Thresholds: A-1 open, A-2 open$|Thresholds: A-1 maybe, A-2 open|'
expect "threshold verdict off the enum" GATE-THRESHOLD-TOKEN 1 "$b"

b="$(fresh)"
sed_i "$b/brief.md" 's|^Thresholds: A-1 open, A-2 open$|Thresholds: A-1 open|'
expect "a live blocking assumption is missing from Thresholds" GATE-THRESHOLD-COVERAGE 1 "$b"

# The coverage rule has two halves: every live blocking assumption, PLUS any
# other assumption the same record cites as evidence.
b="$(fresh)"
sed_i "$b/brief.md" 's|^Evidence: A-1 (stated-intent)$|Evidence: A-1 (stated-intent), A-4 (opinion)|'
expect "an assumption cited as evidence is missing from Thresholds" GATE-THRESHOLD-COVERAGE 1 "$b"

b="$(fresh)"
sed_i "$b/brief.md" 's|^Kill-criteria: KC-1 clear, KC-2 clear$|Kill-criteria: KC-1 fine, KC-2 clear|'
expect "kill-criterion state off the enum" GATE-KC-TOKEN 1 "$b"

b="$(fresh)"
sed_i "$b/brief.md" 's|^Kill-criteria: KC-1 clear, KC-2 clear$|Kill-criteria: KC-1 clear|'
expect "a live kill criterion is missing from Kill-criteria" GATE-KC-COVERAGE 1 "$b"

b="$(fresh)"
printf '%s\n' 'Tracks: capture=Recycle' >"$tmp/ins"
insert_after "$b/brief.md" 'Kill-criteria: KC-1 clear, KC-2 clear' "$tmp/ins"
expect "Tracks line in an untracked venture" GATE-TRACKS-PRESENCE 1 "$b"

b="$(fresh tracked)"
del_line "$b/brief.md" '^Tracks: capture=Recycle, measure=Recycle$'
expect "Tracks line absent in a tracked venture" GATE-TRACKS-PRESENCE 1 "$b"

b="$(fresh tracked)"
sed_i "$b/brief.md" 's|^Tracks: capture=Recycle, measure=Recycle$|Tracks: capture=Recycle|'
expect "a live track is missing from Tracks" GATE-TRACKS-COVERAGE 1 "$b"

b="$(fresh)"
sed_i "$b/brief.md" 's|^Outcome: Recycle$|Outcome: Graduate|'
expect "Graduate over an unevaluated blocking assumption" GATE-GRADUATE-OPEN 1 "$b"

b="$(fresh tracked)"
sed_i "$b/brief.md" 's|^Outcome: Recycle$|Outcome: Graduate|'
sed_i "$b/brief.md" 's|^Thresholds: A-1 open, A-2 open$|Thresholds: A-1 pass, A-2 pass|'
sed_i "$b/brief.md" 's|^Tracks: capture=Recycle, measure=Recycle$|Tracks: capture=Graduate, measure=Recycle|'
sed_i "$b/brief.md" 's|^\*\*Status:\*\* Exploring$|**Status:** Graduated|'
expect "top-level Graduate leaves a live track" GATE-GRADUATE-LIVE-TRACK 1 "$b"

b="$(fresh)"
sed_i "$b/brief.md" 's|^Outcome: Recycle$|Outcome: Graduate|'
sed_i "$b/brief.md" 's|^Thresholds: A-1 open, A-2 open$|Thresholds: A-1 pass, A-2 pass|'
sed_i "$b/assumptions.md" 's|^- \*\*Evidence:\*\* stated-intent — handover interviews$|- **Evidence:** synthetic — handover interviews|'
expect "synthetic evidence passes a desirability assumption at Graduate" GATE-SYNTHETIC-DESIRABILITY 1 "$b"

b="$(fresh)"
sed_i "$b/brief.md" 's|^Outcome: Recycle$|Outcome: Kill|'
expect "status disagrees with the latest gate outcome" LIFE-STATUS-OUTCOME 1 "$b"

# ---------------------------------------------------------------------------
# 11. Baseline mode — the stakeholder-commit guard (REQ-G1.5). IDs and gate
#     records are untouchable through the review channel; prose is not.
# ---------------------------------------------------------------------------
git_bundle() {
  gb="$(fresh "${1:-untracked}")"
  (
    cd "$gb" || exit 1
    git init -q .
    git config user.email fixture@example.invalid
    git config user.name Fixture
    git config commit.gpgsign false
    git add -A
    git commit --no-verify -qm "venture bundle"
  ) >/dev/null 2>&1 || exit 1
  printf '%s' "$gb"
}

b="$(git_bundle)"
sed_i "$b/brief.md" 's|Runbook macros and a shared spreadsheet cover part of the fan-out; neither closes the loop.|Runbook macros cover part of the fan-out. They do not close the loop.|'
out="$("$VALIDATE" --baseline HEAD "$b" 2>&1)"
rc=$?
assert_eq "baseline: a clean prose edit passes" "0" "$rc"

# A prose SUBHEADING is prose too. brief.md's prose sections may carry `### `
# headings that are not register entries, and the id sweep has to route them the
# way the content pass does — by file and section — or rewording one reports the
# heading as a vanished id and the guard blocks the edits it exists to welcome.
b="$(git_bundle)"
printf '%s\n' '' '### Adjacent tools we looked at' '' 'Two internal scripts and a spreadsheet.' >"$tmp/ins"
insert_after "$b/brief.md" '## Existing alternatives' "$tmp/ins"
(cd "$b" && git add -A && git commit --no-verify -qm "add a prose subheading") >/dev/null 2>&1
out="$("$VALIDATE" "$b" 2>&1)"
rc=$?
assert_eq "baseline: a prose subheading is itself clean" "0" "$rc"
sed_i "$b/brief.md" 's|^### Adjacent tools we looked at$|### Adjacent tools|'
out="$("$VALIDATE" --baseline HEAD "$b" 2>&1)"
rc=$?
assert_eq "baseline: rewording a prose subheading passes" "0" "$rc"
assert_not_contains "baseline: no id is claimed to have vanished" "BASE-ID-VANISHED" "$out"

# brief.md reaches the tolerant path by carrying no id type at all; a REGISTER
# file reaches it by failing the typed grammar instead. Different branch, so it
# gets its own case — a heading the content pass already rejects on ID-GRAMMAR
# must not ALSO be tracked as an id that can then vanish.
# Reference lists are comma-separated, the same as every sibling list field and
# the same as doctrine/inception-format.md states. A semicolon is not a
# separator, so the whole run stays one token and fails the id grammar.
b="$(fresh)"
sed_i "$b/assumptions.md" 's|^- \*\*Tasks:\*\* T-1$|- **Tasks:** T-1; T-2|'
expect "assumption tasks: a semicolon is not a separator" ASM-TASK-REF 1 "$b"
b="$(fresh)"
sed_i "$b/plan.md" 's|^- \*\*Tests:\*\* A-1$|- **Tests:** A-1; A-2|'
expect "plan tests: a semicolon is not a separator" PLAN-TESTS-REF 1 "$b"
b="$(fresh)"
sed_i "$b/assumptions.md" 's|^- \*\*Tasks:\*\* T-1$|- **Tasks:** T-1, T-2|'
out="$("$VALIDATE" "$b" 2>&1)"
rc=$?
assert_eq "assumption tasks: a comma list still passes" "0" "$rc"

# Finding order is a fixed function of the bundle, not of the awk build: the
# emitting loops walk recorded document order rather than `for (k in arr)`,
# whose order POSIX leaves undefined. Asserting DOCUMENT order rather than
# comparing two runs, because a given awk build hashes the same keys the same
# way every time — two identical runs agree even when the order is arbitrary,
# so that comparison would pass without the property holding.
b="$(fresh)"
# Strip the Thresholds line so every live blocking assumption is uncovered, and
# the coverage rule emits one finding per assumption from the same loop.
sed_i "$b/brief.md" 's|^Thresholds: .*$|Thresholds: none|'
order="$("$VALIDATE" "$b" 2>&1 | grep -o 'live blocking assumption A-[0-9]*' | grep -o 'A-[0-9]*')"
expected="$(printf '%s\n' "$order" | sort -t- -k2 -n)"
assert_eq "finding order: blocking-assumption findings follow document order" "$expected" "$order"
if [ "$(printf '%s\n' "$order" | grep -c .)" -ge 2 ]; then
  echo "ok: finding order: the case exercises more than one assumption"
else
  echo "FAIL: finding order: fixture produced too few findings to order" >&2
  failures=$((failures + 1))
fi
b="$(git_bundle)"
printf '\n### Working notes\n\nScratch context for the ops leads.\n' >>"$b/plan.md"
(cd "$b" && git add -A && git commit --no-verify -qm "a heading in a register file") >/dev/null 2>&1
sed_i "$b/plan.md" 's|^### Working notes$|### Notes|'
out="$("$VALIDATE" --baseline HEAD "$b" 2>&1)"
assert_contains "baseline: a malformed register heading is still a grammar finding" "ID-GRAMMAR" "$out"
assert_not_contains "baseline: but it is not tracked as a vanishing id" "BASE-ID-VANISHED" "$out"

# The guard has to let the venture keep moving: appending a gate record and
# minting a new id are the normal way a bundle grows, and blocking either would
# make the stakeholder-commit guard useless in exactly the repos that need it.
b="$(git_bundle)"
printf '%s\n' '' '### Gate 2 — 2026-08-25' '' 'Outcome: Recycle' 'Date: 2026-08-25' \
  'Decider: Dana Reyes' 'Evidence: none' 'Thresholds: A-1 open, A-2 open' \
  'Kill-criteria: KC-1 clear, KC-2 clear' 'Rationale: the spike is still running.' >"$tmp/ins"
insert_after "$b/brief.md" 'Rationale: The capture-surface spike has not run yet; re-scope the plan and return.' "$tmp/ins"
printf '%s\n' '' '### A-5 — a newly minted assumption' \
  '- **Statement:** believe x; verify y; measure z; right if w.' \
  '- **Risk-if-wrong:** none' '- **Risk-tag:** feasibility' '- **Threshold:** none' \
  '- **Evidence:** none' '- **Blocking:** no' '- **Tasks:** none' \
  '- **Status:** open' >>"$b/assumptions.md"
out="$("$VALIDATE" --baseline HEAD "$b" 2>&1)"
rc=$?
assert_eq "baseline: appending a gate record and a new id passes" "0" "$rc"

b="$(git_bundle)"
sed_i "$b/assumptions.md" 's|^### A-2 —|### A-5 —|'
expect "baseline: a live id was renumbered" BASE-ID-VANISHED 1 "$b" --baseline HEAD

b="$(git_bundle)"
sed_i "$b/brief.md" 's|^Rationale: The capture-surface spike has not run yet; re-scope the plan and return.$|Rationale: Actually it went fine.|'
expect "baseline: a recorded gate run was edited" BASE-GATE-MUTATED 1 "$b" --baseline HEAD

b="$(fresh)"
for f in brief disciplines assumptions decisions plan; do
  sed_i "$b/$f.md" 's|^\*\*Status:\*\* Exploring$|**Status:** Killed|'
done
sed_i "$b/brief.md" 's|^Outcome: Recycle$|Outcome: Kill|'
(
  cd "$b" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
  git config commit.gpgsign false
  git add -A
  git commit --no-verify -qm "killed venture"
) >/dev/null 2>&1 || exit 1
for f in brief disciplines assumptions decisions plan; do
  sed_i "$b/$f.md" 's|^\*\*Status:\*\* Killed$|**Status:** Exploring|'
done
expect "baseline: revived out of a terminal status" BASE-STATUS-TRANSITION 1 "$b" --baseline HEAD

# --baseline outside a git work tree is an environment error, never a silent pass.
b="$(fresh)"
out="$("$VALIDATE" --baseline HEAD "$b" 2>&1)"
rc=$?
assert_eq "baseline outside a work tree: exit 2" "2" "$rc"

# ---------------------------------------------------------------------------
# 12. Coverage: the advertised rule set and the exercised rule set agree.
#     This is the task's "each enforced rule has a seeded-violation fixture"
#     condition; it fails the moment a rule lands without a fixture.
# ---------------------------------------------------------------------------
rules="$("$VALIDATE" --rules 2>&1)"
rc=$?
assert_eq "--rules: exit 0" "0" "$rc"

missing_fixture=
for code in $(printf '%s\n' "$rules" | awk 'NF { print $1 }'); do
  case " $exercised " in
    *" $code "*) ;;
    *) missing_fixture="$missing_fixture $code" ;;
  esac
done
assert_eq "every advertised rule has a seeded-violation fixture" "" "$missing_fixture"

unadvertised=
for code in $exercised; do
  if ! printf '%s\n' "$rules" | awk 'NF { print $1 }' | grep -qx -- "$code"; then
    unadvertised="$unadvertised $code"
  fi
done
assert_eq "every exercised rule is advertised by --rules" "" "$unadvertised"

if [ "$failures" -ne 0 ]; then
  echo "test-inception-validate: $failures assertion(s) failed" >&2
  exit 1
fi
echo "test-inception-validate: all assertions passed"
