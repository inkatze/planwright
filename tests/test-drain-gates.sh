#!/bin/sh
# Unit test for scripts/drain-gates.sh — the shared gate parser/evaluator
# behind /drain and /orchestrate --bookkeeping (Task 10, REQ-H1.3, REQ-H1.4,
# D-17, D-31). Grammar and lane semantics are normative in
# doctrine/accumulator-taxonomy.md.
#
# Properties verified:
#   1. A satisfied condition gate (task atom, and-of-atoms, spec-status
#      atom) re-surfaces its item as SATISFIED; an unmet one is PENDING
#      with only the unmet atoms named.
#   2. Date gates are surface-only: reached dates (inclusive of the named
#      day) SURFACED, unreached DORMANT, never SATISFIED, never an error
#      (REQ-H1.3).
#   3. Free-text gates surface verbatim without evaluation.
#   4. Hostile gates (shell metacharacters, $(…), backticks) are never
#      evaluated: parse is pattern-match only, gate content is data.
#   5. Control characters — C0, DEL, and the C1 range 0x80-0x9F — are
#      stripped from the report.
#   6. Malformed gates (unknown task/spec, bad combinator, unterminated,
#      empty condition, trailing content after the closing parenthesis,
#      calendar-invalid date, gate outside a bullet) are drain-report-level
#      errors: reported, never silently skipped, and the pass completes
#      (exit 0). A gate split from its bullet by a blank line still parses.
#   7. Nothing is auto-resolved or auto-dropped: the sweep never writes to
#      any file under the swept root (REQ-H1.4).
#   8. The report surfaces the observations log's unmined count and
#      oldest-entry age, clamped at zero for future-dated entries
#      (REQ-H1.4).
#   9. Low-confidence items resurface first within a category, independent
#      of file order; a Confidence token must be the entry's own field,
#      not a substring ("Confidence: lowest") or gate-text content
#      (REQ-H1.5).
#  10. Underscore accumulator directories are not swept for gates; a
#      bundle with no gates is reported as such.
#  11. Exit-code contract: 0 sweep completed, 1 unusable root (missing or
#      non-searchable), 2 usage error (bad flag count, invalid --today).
#  12. The /drain skill is wired to this exact evaluator path.
#  13. An unreadable tasks.md is surfaced as an error, not conflated with
#      a missing one.
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
# lane live in its Deferred section. The lone low-confidence entry sits
# AFTER the unspecified-confidence satisfied entries so the low-first
# report ordering cannot be satisfied by file order alone.
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

- **Conjunction satisfied.** Both atoms hold.
  **Gate:** GATE(when: task 1 completed and task 2.5 completed).
  Citations: REQ-X.
- **Status satisfied.** The beta spec reached Done.
  **Gate:** GATE(when: spec beta done). Citations: REQ-X.
- **Single satisfied.** A deferral whose dependency landed. Confidence: low.
  **Gate:** GATE(when: task 1 completed). Citations: REQ-X.
- **Confidence noise.** Confidence: lowest is not a confidence field.
  **Gate:** GATE(when: task 1 completed). Citations: REQ-X.
- **Still pending.** Blocks on unfinished work. Confidence: high.
  **Gate:** GATE(when: task 3 completed). Citations: REQ-X.
- **Partially met.** One atom met, one not.
  **Gate:** GATE(when: task 1 completed and task 3 completed).
  Citations: REQ-X.
- **Date reached.** A reminder whose date passed.
  **Gate:** GATE(when: after 2026-01-01). Citations: REQ-X.
- **Date boundary.** Reached on the named day itself (inclusive).
  **Gate:** GATE(when: after 2026-06-12). Citations: REQ-X.
- **Date future.** A reminder for later.
  **Gate:** GATE(when: after 2027-01-01). Citations: REQ-X.
- **Mixed dormant.** Condition met, date not reached.
  **Gate:** GATE(when: task 1 completed and after 2027-01-01).
  Citations: REQ-X.
- **Free text.** Not machine-checkable by design.
  **Gate:** wait until Confidence: low entries are mined and any public
  release happened. Citations: REQ-X.
- **Hostile structured.** Must never be evaluated.
  **Gate:** GATE(when: task $(touch CANARY1) completed). Citations: REQ-X.
- **Unknown task.** References a task id that does not exist.
  **Gate:** GATE(when: task 99 completed). Citations: REQ-X.
- **Unknown spec.** References a spec with no status to read.
  **Gate:** GATE(when: spec nosuch done). Citations: REQ-X.
- **Bad combinator.** Uses a combinator outside the grammar.
  **Gate:** GATE(when: task 1 completed or task 3 completed).
  Citations: REQ-X.
- **Unterminated.** Structured form without a closing parenthesis.
  **Gate:** GATE(when: task 1 completed. Citations: REQ-X.
- **Empty condition.** Nothing between the parentheses.
  **Gate:** GATE(when: ). Citations: REQ-X.
- **Trailing junk.** Grammar ends at the closing parenthesis.
  **Gate:** GATE(when: task 1 completed) and task 99 completed.
  Citations: REQ-X.
- **Bad calendar date.** February has no thirtieth.
  **Gate:** GATE(when: after 2026-02-30). Citations: REQ-X.
- **Two bad atoms.** Both defects must be named in one pass.
  **Gate:** GATE(when: task 99 completed and bogus thing).
  Citations: REQ-X.
- **Blank gap.** A loose bullet: blank line before the gate paragraph.

  **Gate:** GATE(when: task 1 completed). Citations: REQ-X.
- **Gate:** GATE(when: task 2.5 completed). Citations: REQ-X.
EOF

# Hostile free-text gate with backticks/metacharacters; a control-char gate
# (ESC + BEL + raw C1 CSI 0x9B injected, appended raw so the bytes land
# literally); and an orphan gate line outside any bullet.
# shellcheck disable=SC2016 # the unexpanded $(...) IS the fixture
{
  printf -- '- **Hostile free text.** Surfaced, never run.\n'
  printf -- '  **Gate:** run `touch CANARY2` && $(touch CANARY3) when ready.\n'
  printf -- '  Citations: REQ-X.\n'
  printf -- '- **Noisy.** Control characters in the gate text.\n'
  printf -- '  **Gate:** wait for \033[31mred\007\233 alert. Citations: REQ-X.\n'
  printf -- '\n'
  printf -- '**Gate:** GATE(when: task 1 completed). Citations: REQ-X.\n'
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

snapshot() {
  find "$root" -type f -exec cksum {} + | sort
}

before=$(snapshot)

cd "$tmp"
out=$("$drain" --today 2026-06-12 "$root") || fail "evaluator exited non-zero"
cd "$here"

after=$(snapshot)

has() {
  printf '%s\n' "$out" | grep -F -- "$1" >/dev/null \
    || fail "report missing: $1"
}

lacks() {
  printf '%s\n' "$out" | grep -F -- "$1" >/dev/null \
    && fail "report must not contain: $1"
  return 0
}

lane_has() {
  printf '%s\n' "$out" | grep "^$1" | grep -F -- "$2" >/dev/null \
    || fail "no $1 line containing: $2"
}

lane_lacks() {
  printf '%s\n' "$out" | grep "^$1" | grep -F -- "$2" >/dev/null \
    && fail "unexpected $1 line containing: $2"
  return 0
}

# 1. Condition gates evaluate: satisfied items re-surface, unmet stay
#    pending with only the unmet atoms named.
lane_has SATISFIED 'Single satisfied'
lane_has SATISFIED 'Conjunction satisfied'
lane_has SATISFIED 'Status satisfied'
lane_has PENDING 'Still pending'
lane_has PENDING 'unmet: task 3 completed'
pmline=$(printf '%s\n' "$out" | grep '^PENDING' | grep -F 'Partially met') \
  || fail "partially met conjunction is not PENDING"
case $pmline in
  *'unmet: task 3 completed'*) : ;;
  *) fail "PENDING line does not name the unmet atom: $pmline" ;;
esac
case $pmline in
  *'unmet: task 1'*) fail "PENDING unmet list names a met atom: $pmline" ;;
esac

# 2. Date gates surface only — never SATISFIED, never an error; the named
#    day itself counts as reached (inclusive boundary).
lane_has SURFACED 'Date reached'
lane_has SURFACED 'Date boundary'
lane_has DORMANT 'Date future'
lane_has DORMANT 'Mixed dormant'
lane_lacks SATISFIED 'Date'
lane_lacks MALFORMED 'Date reached'
lane_lacks MALFORMED 'Date future'

# 3. Free-text gates surface without evaluation.
lane_has FREE-TEXT 'Free text'

# 4. Hostile gates are never evaluated: no canary file may exist anywhere.
for canary in CANARY1 CANARY2 CANARY3; do
  find "$tmp" -name "$canary" | grep . >/dev/null \
    && fail "hostile gate was evaluated: $canary created"
done
lane_has MALFORMED 'Hostile structured'
lane_has FREE-TEXT 'Hostile free text'

# 5. Control characters are stripped from the echoed report — C0 (ESC,
#    BEL), DEL, and C1 (the raw 0x9B CSI byte). The report template is
#    ASCII-only and every fixture byte outside the injected controls is
#    printable, so any non-printable byte in the output means a control
#    character leaked through.
printf '%s' "$out" | tr -d '\012' | LC_ALL=C grep '[^ -~]' >/dev/null \
  && fail "report contains non-printable bytes"
has 'red'
has 'alert'

# 6. Malformed gates are drain-report-level errors; the pass completes.
lane_has MALFORMED 'Unknown task'
lane_has MALFORMED 'Unknown spec'
lane_has MALFORMED 'Bad combinator'
lane_has MALFORMED 'Unterminated'
lane_has MALFORMED 'Empty condition'
lane_has MALFORMED 'Trailing junk'
lane_lacks SATISFIED 'Trailing junk'
lane_has MALFORMED 'Bad calendar date'
lane_lacks SURFACED 'Bad calendar date'
twobad=$(printf '%s\n' "$out" | grep '^MALFORMED' | grep -F 'Two bad atoms') \
  || fail "two-bad-atom gate not reported MALFORMED"
case $twobad in
  *'task 99 completed'*) : ;;
  *) fail "first bad atom not named: $twobad" ;;
esac
case $twobad in
  *'bogus thing'*) : ;;
  *) fail "second bad atom not named: $twobad" ;;
esac

# 6b. Gates the buffering could lose are still reported: a loose bullet
#     (blank line inside the entry) parses; a gate line outside any bullet
#     is MALFORMED, never silently dropped; a title-less bullet whose
#     first bold span is the gate marker is labeled (untitled), not
#     mistitled "Gate:".
lane_has SATISFIED 'Blank gap'
lane_has MALFORMED 'outside'
lane_has SATISFIED '(untitled)'
lane_lacks SATISFIED '- Gate: -'

# 7. The sweep is read-only over everything under the root.
[ "$before" = "$after" ] || fail "evaluator modified a swept file"

# 8. Observations stats: count and oldest-entry age (2026-06-01 → 11 days).
has 'unmined: 3'
has 'oldest: 2026-06-01 (11 days)'

# 9. Low-confidence first within a lane, independent of file order (the
#    [low] entry is third in the file); substring and gate-text matches
#    must not count as the entry's confidence.
sat=$(printf '%s\n' "$out" | grep '^SATISFIED')
first=$(printf '%s\n' "$sat" | head -1)
case $first in
  *'[low]'*) : ;;
  *) fail "low-confidence item does not resurface first: $first" ;;
esac
printf '%s\n' "$out" | grep '^SATISFIED' | grep -F 'Confidence noise' \
  | grep -F '[-]' >/dev/null \
  || fail "'Confidence: lowest' was misread as a confidence field"
printf '%s\n' "$out" | grep '^FREE-TEXT' | grep -F 'Free text' \
  | grep -F '[-]' >/dev/null \
  || fail "confidence token inside gate text was misread as the entry field"

# 10. A bundle with no gates is reported as such; accumulator dirs are not
#     swept; the summary tallies every lane.
has '(no gates)'
lacks '_pending'
lacks 'Planted'
has 'gates: 25 - satisfied: 6 - surfaced: 2 - pending: 2 - dormant: 2 - free-text: 3 - malformed: 10'

# 11. Exit-code contract.
"$drain" >/dev/null 2>&1 && fail "no arguments must be a usage error"
rc=0
"$drain" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "no arguments: expected exit 2, got $rc"
rc=0
"$drain" --today 2026-13-01 "$root" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "out-of-range --today: expected exit 2, got $rc"
rc=0
"$drain" "$tmp/nonexistent" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "missing root: expected exit 1, got $rc"

# 12. The /drain skill fronts this exact evaluator path (the bookkeeping
#     side joins when /orchestrate lands; this pins the skill wiring).
grep -F 'scripts/drain-gates.sh' "$here/../skills/drain/SKILL.md" >/dev/null \
  || fail "skills/drain/SKILL.md does not reference scripts/drain-gates.sh"

# 13. Future-dated observations never report a negative age.
mkdir -p "$tmp/specs2/_observations"
printf '%s\n' '- 2027-01-01 [demo] From the future.' \
  >"$tmp/specs2/_observations/opportunities.md"
out2=$("$drain" --today 2026-06-12 "$tmp/specs2") \
  || fail "future-dated observations broke the sweep"
printf '%s\n' "$out2" | grep -F 'oldest: 2027-01-01 (0 days)' >/dev/null \
  || fail "future-dated observation age not clamped at zero"

# 14. Permission failures are surfaced, not silently skipped (skipped when
#     running as root, which bypasses permission bits).
if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$tmp/specs3/gamma"
  printf '%s\n' '# G' '' '**Status:** Active' \
    >"$tmp/specs3/gamma/requirements.md"
  printf '%s\n' '# G — Tasks' >"$tmp/specs3/gamma/tasks.md"
  chmod 000 "$tmp/specs3/gamma/tasks.md"
  out3=$("$drain" --today 2026-06-12 "$tmp/specs3") \
    || fail "unreadable tasks.md must not abort the sweep"
  chmod 644 "$tmp/specs3/gamma/tasks.md"
  printf '%s\n' "$out3" | grep -i 'unreadable' >/dev/null \
    || fail "unreadable tasks.md not surfaced as unreadable"
  printf '%s\n' "$out3" | grep -F '(no tasks.md)' >/dev/null \
    && fail "unreadable tasks.md conflated with a missing one"

  mkdir -p "$tmp/specs4/delta"
  chmod 444 "$tmp/specs4"
  rc=0
  "$drain" "$tmp/specs4" >/dev/null 2>&1 || rc=$?
  chmod 755 "$tmp/specs4"
  [ "$rc" -eq 1 ] || fail "non-searchable root: expected exit 1, got $rc"
fi

echo "PASS: test-drain-gates.sh"
