#!/bin/sh
# Unit test for scripts/drain-gates.sh — the shared gate parser/evaluator
# behind /drain and /orchestrate --bookkeeping (Task 10, REQ-H1.3, REQ-H1.4,
# D-17, D-31). Grammar and lane semantics are normative in
# doctrine/accumulator-taxonomy.md.
#
# Properties verified:
#   1. A satisfied condition gate (task atom, and-of-atoms, spec-status
#      atom) re-surfaces its item as SATISFIED; an unmet one is PENDING.
#   2. Date gates are surface-only: reached dates SURFACED, unreached
#      DORMANT, never SATISFIED, never an error (REQ-H1.3).
#   3. Free-text gates surface verbatim without evaluation.
#   4. Hostile gates (shell metacharacters, $(…), backticks) are never
#      evaluated: parse is pattern-match only, gate content is data.
#   5. Control characters in gate content are stripped from the report.
#   6. A malformed structured gate is a drain-report-level error: reported
#      MALFORMED, never silently skipped, and the pass completes (exit 0).
#   7. Nothing is auto-resolved or auto-dropped: the sweep never writes to
#      the swept files (REQ-H1.4).
#   8. The report surfaces the observations log's unmined count and
#      oldest-entry age (REQ-H1.4).
#   9. Low-confidence items resurface first within a category (REQ-H1.5).
#  10. Underscore accumulator directories are not swept for gates.
#
# Runs standalone: ./tests/test-drain-gates.sh
set -eu

# Pin the C locale: range patterns are collation-dependent under UTF-8.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes the destination into the command substitution
# below, corrupting the derived script path (house pattern, see sibling tests).
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
drain="$here/../scripts/drain-gates.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$drain" ] || fail "scripts/drain-gates.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
root="$tmp/specs"
mkdir -p "$root/alpha" "$root/beta" "$root/_pending" "$root/_observations"

# --- fixtures -------------------------------------------------------------

printf '%s\n' '# Alpha — Requirements' '' '**Status:** Active' \
  >"$root/alpha/requirements.md"
printf '%s\n' '# Beta — Requirements' '' '**Status:** Done' \
  >"$root/beta/requirements.md"

# alpha: tasks 1 and 2.5 completed, task 3 still forward. Gates of every
# lane live in its Deferred section.
cat >"$root/alpha/tasks.md" <<'EOF'
# Alpha — Tasks

## Forward plan

### Task 3 — Future work

- **Done when:** later.

## Completed

### Task 1 — Landed work

- **Done when:** done.

### Task 2.5 — Dotted landed work

- **Done when:** done.

## Deferred

- **Single satisfied.** A deferral whose dependency landed. Confidence: low.
  **Gate:** GATE(when: task 1 completed). Citations: REQ-X.
- **Conjunction satisfied.** Both atoms hold.
  **Gate:** GATE(when: task 1 completed and task 2.5 completed).
  Citations: REQ-X.
- **Status satisfied.** The beta spec reached Done.
  **Gate:** GATE(when: spec beta done). Citations: REQ-X.
- **Still pending.** Blocks on unfinished work. Confidence: high.
  **Gate:** GATE(when: task 3 completed). Citations: REQ-X.
- **Date reached.** A reminder whose date passed.
  **Gate:** GATE(when: after 2026-01-01). Citations: REQ-X.
- **Date future.** A reminder for later.
  **Gate:** GATE(when: after 2027-01-01). Citations: REQ-X.
- **Mixed dormant.** Condition met, date not reached.
  **Gate:** GATE(when: task 1 completed and after 2027-01-01).
  Citations: REQ-X.
- **Free text.** Not machine-checkable by design.
  **Gate:** all reference-citing tasks Completed and before any public
  release. Citations: REQ-X.
- **Hostile structured.** Must never be evaluated.
  **Gate:** GATE(when: task $(touch CANARY1) completed). Citations: REQ-X.
- **Unknown task.** References a task id that does not exist.
  **Gate:** GATE(when: task 99 completed). Citations: REQ-X.
- **Bad combinator.** Uses a combinator outside the grammar.
  **Gate:** GATE(when: task 1 completed or task 3 completed).
  Citations: REQ-X.
- **Unterminated.** Structured form without a closing parenthesis.
  **Gate:** GATE(when: task 1 completed. Citations: REQ-X.
EOF

# Hostile free-text gate with backticks/metacharacters, plus a control-char
# gate (ESC + BEL injected), appended raw so the bytes land literally.
# shellcheck disable=SC2016 # the unexpanded $(...) IS the fixture
{
  printf -- '- **Hostile free text.** Surfaced, never run.\n'
  printf -- '  **Gate:** run `touch CANARY2` && $(touch CANARY3) when ready.\n'
  printf -- '  Citations: REQ-X.\n'
  printf -- '- **Noisy.** Control characters in the gate text.\n'
  printf -- '  **Gate:** wait for \033[31mred\007 alert. Citations: REQ-X.\n'
} >>"$root/alpha/tasks.md"

# beta: a bundle with no gates at all.
cat >"$root/beta/tasks.md" <<'EOF'
# Beta — Tasks

## Completed

### Task 1 — Everything

- **Done when:** done.
EOF

# Underscore accumulators are never swept for gates; a gate planted in one
# must not appear in the report.
cat >"$root/_pending/tasks.md" <<'EOF'
- **Planted.** Should be invisible to the sweep.
  **Gate:** GATE(when: task 1 completed).
EOF

cat >"$root/_observations/opportunities.md" <<'EOF'
# Observations log

- 2026-06-01 [demo] Oldest entry.
- 2026-06-10 [demo] Middle entry.
- 2026-06-11 [demo] Newest entry.
EOF

# --- run ------------------------------------------------------------------

before=$(cksum "$root/alpha/tasks.md" "$root/beta/tasks.md")

cd "$tmp"
out=$("$drain" --today 2026-06-12 "$root") || fail "evaluator exited non-zero"
cd "$here"

after=$(cksum "$root/alpha/tasks.md" "$root/beta/tasks.md")

has() {
  printf '%s\n' "$out" | grep -F -- "$1" >/dev/null \
    || fail "report missing: $1"
}

lacks() {
  printf '%s\n' "$out" | grep -F -- "$1" >/dev/null \
    && fail "report must not contain: $1"
  return 0
}

# 1. Condition gates evaluate: satisfied items re-surface, unmet stay pending.
has 'SATISFIED [low]'
has 'Single satisfied'
printf '%s\n' "$out" | grep '^SATISFIED' | grep -F 'Conjunction satisfied' >/dev/null \
  || fail "and-of-atoms gate did not evaluate to SATISFIED"
printf '%s\n' "$out" | grep '^SATISFIED' | grep -F 'Status satisfied' >/dev/null \
  || fail "spec-status atom did not evaluate to SATISFIED"
printf '%s\n' "$out" | grep '^PENDING' | grep -F 'Still pending' >/dev/null \
  || fail "unmet condition gate is not PENDING"
printf '%s\n' "$out" | grep '^PENDING' | grep -F 'task 3 completed' >/dev/null \
  || fail "PENDING line does not name the unmet atom"

# 2. Date gates surface only — never SATISFIED, never an error.
printf '%s\n' "$out" | grep '^SURFACED' | grep -F 'Date reached' >/dev/null \
  || fail "reached date gate is not SURFACED"
printf '%s\n' "$out" | grep '^DORMANT' | grep -F 'Date future' >/dev/null \
  || fail "unreached date gate is not DORMANT"
printf '%s\n' "$out" | grep '^DORMANT' | grep -F 'Mixed dormant' >/dev/null \
  || fail "mixed gate with unreached date is not DORMANT"
printf '%s\n' "$out" | grep '^SATISFIED' | grep -F 'Date' >/dev/null \
  && fail "a date gate was marked SATISFIED (must only surface)"
printf '%s\n' "$out" | grep '^MALFORMED' | grep -F 'Date' >/dev/null \
  && fail "a well-formed date gate was reported MALFORMED"

# 3. Free-text gates surface without evaluation.
printf '%s\n' "$out" | grep '^FREE-TEXT' | grep -F 'Free text' >/dev/null \
  || fail "free-text gate did not surface"

# 4. Hostile gates are never evaluated: no canary file may exist anywhere.
for canary in CANARY1 CANARY2 CANARY3; do
  find "$tmp" -name "$canary" | grep . >/dev/null \
    && fail "hostile gate was evaluated: $canary created"
done
printf '%s\n' "$out" | grep '^MALFORMED' | grep -F 'Hostile structured' >/dev/null \
  || fail "hostile structured gate not reported MALFORMED"
printf '%s\n' "$out" | grep '^FREE-TEXT' | grep -F 'Hostile free text' >/dev/null \
  || fail "hostile free-text gate did not surface as FREE-TEXT"

# 5. Control characters are stripped from the echoed report. The report
#    template is ASCII-only and every fixture byte outside the injected
#    ESC/BEL is printable, so any non-printable byte in the output means a
#    control character leaked through.
printf '%s' "$out" | tr -d '\012' | LC_ALL=C grep '[^ -~]' >/dev/null \
  && fail "report contains non-printable bytes"
has 'red alert'

# 6. Malformed gates are drain-report-level errors; the pass completes.
printf '%s\n' "$out" | grep '^MALFORMED' | grep -F 'Unknown task' >/dev/null \
  || fail "unknown task reference not reported MALFORMED"
printf '%s\n' "$out" | grep '^MALFORMED' | grep -F 'Bad combinator' >/dev/null \
  || fail "or-combinator gate not reported MALFORMED"
printf '%s\n' "$out" | grep '^MALFORMED' | grep -F 'Unterminated' >/dev/null \
  || fail "unterminated gate not reported MALFORMED"

# 7. The sweep is read-only.
[ "$before" = "$after" ] || fail "evaluator modified a swept file"

# 8. Observations stats: count and oldest-entry age (2026-06-01 → 11 days).
has 'unmined: 3'
has 'oldest: 2026-06-01 (11 days)'

# 9. Low-confidence first: the [low] SATISFIED line precedes the
#    unspecified-confidence ones within the category.
sat=$(printf '%s\n' "$out" | grep '^SATISFIED')
first=$(printf '%s\n' "$sat" | head -1)
case $first in
  *'[low]'*) : ;;
  *) fail "low-confidence item does not resurface first: $first" ;;
esac

# 10. A bundle with no gates is reported as such; accumulator dirs are not
#     swept.
has '(no gates)'
lacks '_pending'
lacks 'Planted'

echo "PASS: test-drain-gates.sh"
