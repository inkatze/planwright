#!/bin/sh
# Unit test for scripts/drain-gates.sh — the shared gate parser/evaluator
# behind /drain and /orchestrate --bookkeeping (Task 10, REQ-H1.3, REQ-H1.4,
# D-17, D-31). Grammar and lane semantics are normative in
# doctrine/accumulator-taxonomy.md.
#
# Properties verified (numbered to match the body's check sections):
#   1. A satisfied condition gate (task atom, and-of-atoms, spec-status
#      atom) re-surfaces its item as SATISFIED; an unmet one is PENDING
#      with only the unmet atoms named.
#   2. Date gates are surface-only: reached dates (inclusive of the named
#      day) SURFACED, unreached DORMANT, never SATISFIED, never an error
#      (REQ-H1.3).
#   3. Free-text gates surface verbatim without evaluation.
#   4. Hostile gates (shell metacharacters, $(…), backticks) are never
#      evaluated: parse is pattern-match only, gate content is data.
#   5. Control characters — C0, DEL (0x7F), and the C1 range 0x80-0x9F —
#      are stripped from the report.
#   6. Malformed gates (unknown task/spec, bad combinator, unterminated,
#      empty condition, trailing content after the closing parenthesis,
#      calendar-invalid date) are drain-report-level errors: reported,
#      never silently skipped, and the pass completes (exit 0). (6b) A
#      gate split from its bullet by a blank line still parses; a gate
#      line outside any bullet is MALFORMED; a title-less bullet reports
#      as (untitled).
#   7. Nothing is auto-resolved or auto-dropped: the sweep never writes to
#      any file under the swept root (REQ-H1.4).
#   8. The report surfaces the observations log's unmined count and
#      oldest-entry age (REQ-H1.4).
#   9. Low-confidence items resurface first within a category, independent
#      of file order; a Confidence token must be the entry's own field,
#      not a substring ("Confidence: lowest") or gate-text content
#      (REQ-H1.5).
#  10. Underscore accumulator directories are not swept for gates; a
#      bundle with no gates is reported as such; the summary tallies every
#      lane plus the errors count.
#  11. Exit-code contract: 0 sweep completed, 1 unusable root (missing or
#      non-searchable), 2 usage error (bad flag count, out-of-range or
#      calendar-invalid --today).
#  12. The /drain skill is wired to this exact evaluator path.
#  13. Future-dated observation entries never yield a negative age.
#  14. Permission failures are surfaced and counted, not conflated with
#      missing files (unreadable tasks.md, unreadable requirements.md).
#  15. Skipped-directory notes are visible for non-conforming and
#      over-length spec identifiers.
#  16. A hostile Status field cannot forge another spec's status (the
#      whitelist rejects non-lifecycle values before awk -v).
#  17. Fenced code blocks are illustration: no gate rows, no task ids.
#  18. CRLF line endings parse like LF.
#  19. Calendar-invalid observation dates count as unmined but never
#      become the oldest entry.
#  20. NUL bytes in tasks.md are flagged as an error, never silently
#      truncating a gate away.
#  21. The torn-read digest detector fires deterministically (cksum stub),
#      is counted, and the sweep still completes with exit 0.
#  22. An unreadable observations log is surfaced and counted.
#  23. A bundle without requirements.md leaves a note explaining why its
#      status atoms cannot evaluate (missing, unreadable, and
#      unrecognized are all noted, never silent).
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

**Format-version:** 1

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
  printf -- '  **Gate:** wait for \033[31mred\007\233\177 alert. Citations: REQ-X.\n'
  printf -- '\n'
  printf -- '**Gate:** GATE(when: task 1 completed). Citations: REQ-X.\n'
} >>"$root/alpha/tasks.md"

# beta: a bundle with no gates at all.
cat >"$root/beta/tasks.md" <<'EOF'
# Beta — Tasks

**Format-version:** 1

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

# 8. Observations stats: the reworked line names the legacy surface, the count,
#    and the oldest-entry age (2026-06-01 → 11 days). has() is a grep -F
#    substring match; asserting the full line as a fixed string is specific
#    enough that `unmined: 30` cannot satisfy it, since the trailing
#    ` (legacy: 3) - oldest: ...` disambiguates the count.
has 'unmined: 3 (legacy: 3) - oldest: 2026-06-01 (11 days)'

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
has 'gates: 25 - satisfied: 6 - surfaced: 2 - pending: 2 - dormant: 2 - free-text: 3 - malformed: 10 - errors: 0'

# 11. Exit-code contract.
"$drain" >/dev/null 2>&1 && fail "no arguments must be a usage error"
rc=0
"$drain" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "no arguments: expected exit 2, got $rc"
rc=0
"$drain" --today 2026-13-01 "$root" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "out-of-range --today: expected exit 2, got $rc"
rc=0
"$drain" --today 2026-02-30 "$root" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "calendar-invalid --today: expected exit 2, got $rc"
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
printf '%s\n' "$out2" | grep -F 'unmined: 1 (legacy: 1) - oldest: 2027-01-01 (0 days)' >/dev/null \
  || fail "future-dated observation age not clamped at zero"

# 14. Permission failures are surfaced, not silently skipped (skipped when
#     running as root, which bypasses permission bits).
if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$tmp/specs3/gamma"
  printf '%s\n' '# G' '' '**Status:** Active' \
    >"$tmp/specs3/gamma/requirements.md"
  printf '%s\n' '# G — Tasks' '' '**Format-version:** 1' >"$tmp/specs3/gamma/tasks.md"
  chmod 000 "$tmp/specs3/gamma/tasks.md"
  out3=$("$drain" --today 2026-06-12 "$tmp/specs3") \
    || fail "unreadable tasks.md must not abort the sweep"
  chmod 644 "$tmp/specs3/gamma/tasks.md"
  printf '%s\n' "$out3" | grep -i 'unreadable' >/dev/null \
    || fail "unreadable tasks.md not surfaced as unreadable"
  printf '%s\n' "$out3" | grep -F '(no tasks.md)' >/dev/null \
    && fail "unreadable tasks.md conflated with a missing one"
  printf '%s\n' "$out3" | grep -F 'errors: 1' >/dev/null \
    || fail "unreadable tasks.md not counted in the summary errors tally"

  mkdir -p "$tmp/specs3/epsilon"
  printf '%s\n' '# E' '' '**Status:** Active' \
    >"$tmp/specs3/epsilon/requirements.md"
  printf '%s\n' '# E — Tasks' '' '**Format-version:** 1' >"$tmp/specs3/epsilon/tasks.md"
  chmod 000 "$tmp/specs3/epsilon/requirements.md"
  out3b=$("$drain" --today 2026-06-12 "$tmp/specs3") \
    || fail "unreadable requirements.md must not abort the sweep"
  chmod 644 "$tmp/specs3/epsilon/requirements.md"
  printf '%s\n' "$out3b" | grep -F 'requirements.md unreadable' >/dev/null \
    || fail "unreadable requirements.md not noted"

  mkdir -p "$tmp/specs4/delta"
  chmod 444 "$tmp/specs4"
  rc=0
  "$drain" "$tmp/specs4" >/dev/null 2>&1 || rc=$?
  chmod 755 "$tmp/specs4"
  [ "$rc" -eq 1 ] || fail "non-searchable root: expected exit 1, got $rc"
fi

# 15. Skipped-directory notes are visible: a non-conforming name and an
#     over-length name each leave a note rather than vanishing.
mkdir -p "$tmp/specs5/ok" "$tmp/specs5/Bad_Name" \
  "$tmp/specs5/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
printf '%s\n' '# Ok — Tasks' '' '**Format-version:** 1' >"$tmp/specs5/ok/tasks.md"
out5=$("$drain" --today 2026-06-12 "$tmp/specs5") \
  || fail "skipped-directory fixtures broke the sweep"
printf '%s\n' "$out5" | grep -F 'non-conforming spec identifier' >/dev/null \
  || fail "non-conforming directory skip not noted"
printf '%s\n' "$out5" | grep -F 'over-length spec identifier' >/dev/null \
  || fail "over-length directory skip not noted"

# 16. A hostile Status field cannot forge another spec's status: awk -v
#     processes C escapes, so a literal backslash-t in requirements.md
#     could smuggle a whitespace-split "victim=done" token into the status
#     map. The status whitelist must reject it (and note it) instead.
mkdir -p "$tmp/specs6/victim" "$tmp/specs6/zhostile"
printf '%s\n' '# V' '' '**Status:** Active' \
  >"$tmp/specs6/victim/requirements.md"
printf '%s\n' '# V — Tasks' '' '**Format-version:** 1' '' '## Deferred' '' \
  '- **Forge target.** Satisfied only if victim reads as done.' \
  '  **Gate:** GATE(when: spec victim done). Citations: REQ-X.' \
  >"$tmp/specs6/victim/tasks.md"
printf '%s\n' '# Z' '' '**Status:** active\tvictim=done' \
  >"$tmp/specs6/zhostile/requirements.md"
printf '%s\n' '# Z — Tasks' '' '**Format-version:** 1' >"$tmp/specs6/zhostile/tasks.md"
out6=$("$drain" --today 2026-06-12 "$tmp/specs6") \
  || fail "status-forgery fixture broke the sweep"
printf '%s\n' "$out6" | grep '^SATISFIED' | grep -F 'Forge target' >/dev/null \
  && fail "hostile Status field forged another spec's status to SATISFIED"
printf '%s\n' "$out6" | grep -F 'unrecognized status' >/dev/null \
  || fail "non-whitelisted status value not noted"

# 17. Fenced code blocks are illustration, not live content: an example
#     gate inside a fence must not produce a report row, and fenced task
#     headings must not enter the task-id universe (a real gate referencing
#     a fence-only task id is an unknown-task MALFORMED).
mkdir -p "$tmp/specs7/eta"
printf '%s\n' '# H' '' '**Status:** Active' >"$tmp/specs7/eta/requirements.md"
cat >"$tmp/specs7/eta/tasks.md" <<'EOF'
# Eta — Tasks

**Format-version:** 1

## Forward plan

```markdown
## Completed

### Task 99 — Fenced example task

- **Fenced example.** Not a real deferral.
  **Gate:** GATE(when: task 99 completed). Citations: REQ-X.
```

## Deferred

- **Real reference.** Points at an id that exists only inside the fence.
  **Gate:** GATE(when: task 99 completed). Citations: REQ-X.
EOF
out7=$("$drain" --today 2026-06-12 "$tmp/specs7") \
  || fail "fence fixture broke the sweep"
printf '%s\n' "$out7" | grep -F 'Fenced example' >/dev/null \
  && fail "a gate inside a fenced code block produced a report row"
printf '%s\n' "$out7" | grep '^MALFORMED' | grep -F 'Real reference' >/dev/null \
  || fail "fence-only task id leaked into the task-id universe"

# 18. CRLF line endings are tolerated: the canonical entry layout saved
#     with CRLF endings parses identically to its LF form.
mkdir -p "$tmp/specs8/theta"
printf '%s\n' '# T' '' '**Status:** Active' \
  >"$tmp/specs8/theta/requirements.md"
printf '%s\r\n' '# Theta — Tasks' '' '**Format-version:** 1' '' '## Completed' '' \
  '### Task 1 — Landed' '' '- **Done when:** done.' '' '## Deferred' '' \
  '- **Crlf entry.** Canonical layout, CRLF file.' \
  '  **Gate:** GATE(when: task 1 completed).' \
  '  Citations: REQ-X.' \
  >"$tmp/specs8/theta/tasks.md"
out8=$("$drain" --today 2026-06-12 "$tmp/specs8") \
  || fail "CRLF fixture broke the sweep"
printf '%s\n' "$out8" | grep '^SATISFIED' | grep -F 'Crlf entry' >/dev/null \
  || fail "CRLF line endings falsely malform a canonical gate"

# 19. Observations entries with calendar-invalid dates count as unmined
#     but never become the oldest entry (no fabricated age).
mkdir -p "$tmp/specs9/_observations"
printf '%s\n' '- 2026-00-00 [demo] Invalid date.' \
  '- 2026-06-10 [demo] Real entry.' \
  >"$tmp/specs9/_observations/opportunities.md"
out9=$("$drain" --today 2026-06-12 "$tmp/specs9") \
  || fail "invalid-date observation broke the sweep"
printf '%s\n' "$out9" | grep -F 'unmined: 2 (legacy: 2) - oldest: 2026-06-10 (2 days)' >/dev/null \
  || fail "invalid-dated legacy line: expected count-2 with the valid date as oldest"

# 20. A NUL byte in tasks.md cannot silently hide a gate: awk truncates
#     records at NUL, so the file is flagged as an error instead of
#     trusted (REQ-H1.3: never silently skipped).
mkdir -p "$tmp/specs10/iota"
printf '%s\n' '# I' '' '**Status:** Active' \
  >"$tmp/specs10/iota/requirements.md"
{
  printf '%s\n' '# Iota — Tasks' '' '**Format-version:** 1' '' '## Completed' '' '### Task 1 — Done' \
    '' '- **Done when:** done.' '' '## Deferred' ''
  printf -- '- **Hid\000den.** NUL before the marker. **Gate:** GATE(when: task 1 completed).\n'
} >"$tmp/specs10/iota/tasks.md"
out10=$("$drain" --today 2026-06-12 "$tmp/specs10") \
  || fail "NUL fixture broke the sweep"
printf '%s\n' "$out10" | grep -i 'NUL' >/dev/null \
  || fail "NUL bytes in tasks.md not surfaced as an error"
printf '%s\n' "$out10" | grep -F 'errors: 1' >/dev/null \
  || fail "NUL-byte error not counted in the summary tally"

# 21. The torn-read detector is exercised deterministically: a cksum stub
#     returning a fresh digest per call forces every pre/post comparison
#     to mismatch; the sweep must surface the error, count it, complete,
#     and exit 0.
stub="$tmp/stub"
mkdir -p "$stub"
cat >"$stub/cksum" <<EOF
#!/bin/sh
cat >/dev/null
n=\$(cat "$stub/n" 2>/dev/null || echo 0)
n=\$((n + 1))
echo "\$n" >"$stub/n"
echo "\$n \$n"
EOF
chmod +x "$stub/cksum"
rm -f "$stub/n"
out11=$(PATH="$stub:$PATH" "$drain" --today 2026-06-12 "$root") \
  || fail "digest-mismatch stub run must still exit 0"
printf '%s\n' "$out11" | grep -F 'changed during the sweep' >/dev/null \
  || fail "digest mismatch not surfaced as a torn-read error"
printf '%s\n' "$out11" | grep -F '== summary ==' >/dev/null \
  || fail "torn-read error prevented the report from completing"

# 22. Permission failure on the observations log is surfaced and counted
#     (skipped as root, which bypasses permission bits).
if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$tmp/specs11/_observations"
  printf '%s\n' '- 2026-06-10 [demo] Entry.' \
    >"$tmp/specs11/_observations/opportunities.md"
  chmod 000 "$tmp/specs11/_observations/opportunities.md"
  out12=$("$drain" --today 2026-06-12 "$tmp/specs11") \
    || fail "unreadable observations log must not abort the sweep"
  chmod 644 "$tmp/specs11/_observations/opportunities.md"
  printf '%s\n' "$out12" | grep -F 'observations log unreadable' >/dev/null \
    || fail "unreadable observations log not surfaced"
  printf '%s\n' "$out12" | grep -F 'errors: 1' >/dev/null \
    || fail "unreadable observations log not counted in the errors tally"
fi

# 23. A bundle with no requirements.md at all: status atoms referencing it
#     fail as unknown, and a note explains the missing status file.
mkdir -p "$tmp/specs12/kappa" "$tmp/specs12/lam"
printf '%s\n' '# K — Tasks' '' '**Format-version:** 1' >"$tmp/specs12/kappa/tasks.md"
printf '%s\n' '# L' '' '**Status:** Active' \
  >"$tmp/specs12/lam/requirements.md"
printf '%s\n' '# L — Tasks' '' '**Format-version:** 1' '' '## Deferred' '' \
  '- **Needs kappa.** Blocks on a spec with no requirements.md.' \
  '  **Gate:** GATE(when: spec kappa done). Citations: REQ-X.' \
  >"$tmp/specs12/lam/tasks.md"
out13=$("$drain" --today 2026-06-12 "$tmp/specs12") \
  || fail "missing-requirements fixture broke the sweep"
printf '%s\n' "$out13" | grep -F 'requirements.md missing' >/dev/null \
  || fail "missing requirements.md not noted"
printf '%s\n' "$out13" | grep '^MALFORMED' | grep -F 'Needs kappa' >/dev/null \
  || fail "status atom against a status-less spec must stay malformed"

# 24. Observation surfacing derives from the fragment store plus the frozen
#     legacy file's unconsumed lines (REQ-C1.3, D-4): the count is N+M, the
#     oldest age spans both surfaces (here the oldest is a legacy line), and
#     both surfaces are named while the legacy file still holds entries.
mkdir -p "$tmp/specs20/_observations/entries"
printf -- '- 2026-06-10 [planwright] first live fragment\n' \
  >"$tmp/specs20/_observations/entries/2026-06-10-alpha-11111111.md"
printf -- '- 2026-06-20 [planwright] second live fragment\n' \
  >"$tmp/specs20/_observations/entries/2026-06-20-beta-22222222.md"
printf '%s\n' '# Observations log' '' \
  '- 2026-06-01 [planwright] oldest legacy line.' \
  '- 2026-06-05 [planwright] middle legacy line.' \
  '- 2026-06-08 [planwright] newest legacy line.' \
  >"$tmp/specs20/_observations/opportunities.md"
out20=$("$drain" --today 2026-07-01 "$tmp/specs20") \
  || fail "fragment+legacy surfacing broke the sweep"
printf '%s\n' "$out20" | grep -F 'unmined: 5 (fragments: 2, legacy: 3)' >/dev/null \
  || fail "combined count/surfaces not reported: $(printf '%s\n' "$out20" | grep -F unmined)"
printf '%s\n' "$out20" | grep -F 'oldest: 2026-06-01 (30 days)' >/dev/null \
  || fail "oldest age across both surfaces incorrect"

# 25. Skip-and-warn and stuck consumes (REQ-C1.3, REQ-C1.2): a grammar-invalid
#     name and a shape-invalid fragment are excluded from the count and named;
#     a consumed-but-unmoved fragment (Consumed-by present in entries/) is
#     excluded and surfaced as a stuck consume; the freeze header and non-entry
#     prose are never counted.
mkdir -p "$tmp/specs21/_observations/entries"
printf -- '- 2026-06-15 [planwright] the one live fragment\n' \
  >"$tmp/specs21/_observations/entries/2026-06-15-live-aaaaaaaa.md"
printf -- '- 2026-06-10 [planwright] annotated but not moved\nConsumed-by: specs/foo (2026-07-01)\n' \
  >"$tmp/specs21/_observations/entries/2026-06-10-stuck-bbbbbbbb.md"
printf -- '- 2026-06-12 [planwright] fine text\n' \
  >"$tmp/specs21/_observations/entries/not-a-valid-fragment-name.md"
printf 'this first line is not the entry form\n' \
  >"$tmp/specs21/_observations/entries/2026-06-13-shape-cccccccc.md"
printf '%s\n' '# Observations log' '' \
  'This is prose, not an entry, and must never be counted.' '' \
  '- 2026-06-04 [planwright] the one unconsumed legacy line.' \
  >"$tmp/specs21/_observations/opportunities.md"
out21=$("$drain" --today 2026-07-01 "$tmp/specs21") \
  || fail "skip-and-warn fixture broke the sweep"
printf '%s\n' "$out21" | grep -F 'unmined: 2 (fragments: 1, legacy: 1)' >/dev/null \
  || fail "invalid/stuck fragments or prose leaked into the count: $(printf '%s\n' "$out21" | grep -F unmined)"
printf '%s\n' "$out21" | grep -F 'stuck consume' | grep -F '2026-06-10-stuck-bbbbbbbb.md' >/dev/null \
  || fail "stuck consume not surfaced and named"
printf '%s\n' "$out21" | grep -F 'skipped invalid fragment' | grep -F 'not-a-valid-fragment-name.md' >/dev/null \
  || fail "grammar-invalid fragment not named as skipped"
printf '%s\n' "$out21" | grep -F 'skipped invalid fragment' | grep -F '2026-06-13-shape-cccccccc.md' >/dev/null \
  || fail "shape-invalid fragment not named as skipped"

# 26. Fragments-only surfacing, zero state, and null-safety (REQ-C1.3): a fully
#     consumed legacy file leaves only the fragment surface named; a tree with
#     zero unmined entries reports the zero count with no age line; and an
#     observations root with neither fragments nor a legacy file is null-safe.
mkdir -p "$tmp/specs22a/_observations/entries"
printf -- '- 2026-06-01 [planwright] the only live fragment\n' \
  >"$tmp/specs22a/_observations/entries/2026-06-01-solo-11112222.md"
printf '%s\n' \
  '- 2026-05-15 [planwright] fully consumed — consumed-by: specs/x (2026-06-01)' \
  >"$tmp/specs22a/_observations/opportunities.md"
out22a=$("$drain" --today 2026-07-01 "$tmp/specs22a") \
  || fail "fragments-only fixture broke the sweep"
printf '%s\n' "$out22a" | grep -F 'unmined: 1 (fragments: 1)' >/dev/null \
  || fail "consumed legacy should leave fragments-only surfacing"
printf '%s\n' "$out22a" | grep '^unmined:' | grep -F 'legacy:' >/dev/null \
  && fail "a fully consumed legacy file must not be named as a surface"

mkdir -p "$tmp/specs22b/_observations/entries"
printf '%s\n' \
  '- 2026-05-15 [planwright] consumed — consumed-by: specs/x (2026-06-01)' \
  >"$tmp/specs22b/_observations/opportunities.md"
out22b=$("$drain" --today 2026-07-01 "$tmp/specs22b") \
  || fail "zero-unmined fixture broke the sweep"
zline=$(printf '%s\n' "$out22b" | grep '^unmined:') \
  || fail "zero-unmined fixture printed no unmined line"
[ "$zline" = "unmined: 0" ] || fail "zero unmined must be a bare 'unmined: 0', got: $zline"
printf '%s\n' "$out22b" | grep -F 'oldest:' >/dev/null \
  && fail "zero unmined must omit the age line"

mkdir -p "$tmp/specs22c/_observations"
out22c=$("$drain" --today 2026-07-01 "$tmp/specs22c") \
  || fail "null-safe observations fixture broke the sweep"
printf '%s\n' "$out22c" | grep -F 'unmined: 0' >/dev/null \
  || fail "an observations root with no fragments and no legacy file is not null-safe"

# 27. Content is data only (REQ-D1.3, D-7): a fragment and a legacy line whose
#     content carries shell metacharacters and control bytes are read as data —
#     never evaluated (no canary is created) — the live fragment is still
#     counted, and the report carries no non-printable bytes.
mkdir -p "$tmp/specs23/_observations/entries"
# shellcheck disable=SC2016 # the unexpanded $(...)/backticks ARE the fixture
printf -- '- 2026-06-01 [planwright] hostile $(touch %s/CANARYD) `touch %s/CANARYE` \033[31m x\n' \
  "$tmp" "$tmp" >"$tmp/specs23/_observations/entries/2026-06-01-hostile-deadbeef.md"
# shellcheck disable=SC2016
printf -- '- 2026-06-02 [planwright] legacy hostile $(touch %s/CANARYG) \007 end\n' \
  "$tmp" >"$tmp/specs23/_observations/opportunities.md"
out23=$("$drain" --today 2026-07-01 "$tmp/specs23") \
  || fail "hostile-content fixture broke the sweep"
for canary in CANARYD CANARYE CANARYG; do
  find "$tmp" -name "$canary" | grep . >/dev/null \
    && fail "hostile observation content was evaluated: $canary created"
done
printf '%s\n' "$out23" | grep -F 'unmined: 2 (fragments: 1, legacy: 1)' >/dev/null \
  || fail "hostile-but-valid fragment/legacy line not counted as data"
printf '%s' "$out23" | tr -d '\012' | LC_ALL=C grep '[^ -~]' >/dev/null \
  && fail "hostile observation content leaked non-printable bytes into the report"

# 28. Oldest age can come from the FRAGMENT surface (REQ-C1.3): a fragment
#     older than every legacy line becomes the reported oldest, exercising the
#     fragment-date age derivation and the cross-surface min branch (the other
#     obs fixtures all take their oldest from the legacy surface).
mkdir -p "$tmp/specs24/_observations/entries"
printf -- '- 2026-05-01 [planwright] the oldest, a fragment\n' \
  >"$tmp/specs24/_observations/entries/2026-05-01-old-11112222.md"
printf '%s\n' '# Observations log' '' \
  '- 2026-06-01 [planwright] a newer legacy line.' \
  >"$tmp/specs24/_observations/opportunities.md"
out24=$("$drain" --today 2026-07-01 "$tmp/specs24") \
  || fail "fragment-oldest fixture broke the sweep"
printf '%s\n' "$out24" | grep -F 'unmined: 2 (fragments: 1, legacy: 1) - oldest: 2026-05-01 (61 days)' >/dev/null \
  || fail "oldest age not derived from the older fragment surface: $(printf '%s\n' "$out24" | grep unmined)"

# 29. obs_safe strips control bytes — including a NEWLINE — from a fragment name
#     before it is surfaced (REQ-D1.3, D-7). A newline is the byte the final
#     report strip keeps (for structure), so only obs_safe guards it: an
#     invalid fragment name carrying an embedded newline must surface as ONE
#     row, never forging a second, and the report must carry no non-printables.
mkdir -p "$tmp/specs25/_observations/entries"
forged=$(printf '2026-01-01-a\nFORGEDROW-deadbeef.md')
: >"$tmp/specs25/_observations/entries/$forged"
out25=$("$drain" --today 2026-07-01 "$tmp/specs25") \
  || fail "control-byte-name fixture broke the sweep"
rows=$(printf '%s\n' "$out25" | grep -c 'skipped invalid fragment')
[ "$rows" -eq 1 ] \
  || fail "obs_safe did not strip the newline; the name forged $rows rows"
printf '%s\n' "$out25" | grep -F 'FORGEDROW' | grep -qv 'skipped invalid fragment' \
  && fail "the post-newline name fragment surfaced as its own forged row"
printf '%s' "$out25" | tr -d '\012' | LC_ALL=C grep '[^ -~]' >/dev/null \
  && fail "a control byte in a fragment name leaked into the report"

# 30. Drain and render agree on which legacy lines are entries: a malformed
#     `- <date> [scope` (no closing bracket) is an entry to neither surface, so
#     drain must not count it (the entry-form recognition is shared).
mkdir -p "$tmp/specs26/_observations"
printf '%s\n' '# Observations log' '' \
  '- 2026-06-01 [planwright] a real entry line.' \
  '- 2026-06-02 [malformed-no-close' \
  >"$tmp/specs26/_observations/opportunities.md"
out26=$("$drain" --today 2026-07-01 "$tmp/specs26") \
  || fail "malformed-legacy fixture broke the sweep"
printf '%s\n' "$out26" | grep -F 'unmined: 1 (legacy: 1)' >/dev/null \
  || fail "a malformed legacy line (no closing bracket) was miscounted as an entry"

# 31. A symlinked observations root is not traversed (D-7): the sweep notes it
#     and reports zero rather than reading the store through the symlink.
if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$tmp/specs27real/entries"
  printf -- '- 2020-01-01 [planwright] would leak if traversed\n' \
    >"$tmp/specs27real/entries/2020-01-01-leak-abcdabcd.md"
  mkdir -p "$tmp/specs27"
  ln -s "$tmp/specs27real" "$tmp/specs27/_observations"
  out27=$("$drain" --today 2026-07-01 "$tmp/specs27") \
    || fail "symlinked observations root broke the sweep"
  printf '%s\n' "$out27" | grep -F 'observations root is a symlink' >/dev/null \
    || fail "a symlinked observations root was not noted"
  printf '%s\n' "$out27" | grep -F '2020-01-01' >/dev/null \
    && fail "the sweep read the store through a symlinked observations root"
fi

# 32. An unreadable fragment is excluded and named, never an abort (REQ-C1.3,
#     D-4). Regression (F1): the fragment loop lacked an -r guard, so the read
#     open failed; under a strict-POSIX /bin/sh (dash, the CI shell) that
#     aborts the whole sweep under set -e - no report emitted. Skip runs as
#     root (mode 000 is still readable). The sweep must still report, count
#     only the readable fragment, and name the unreadable one.
if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$tmp/specs28/_observations/entries"
  printf -- '- 2026-09-01 [planwright] readable and counted\n' \
    >"$tmp/specs28/_observations/entries/2026-09-01-good-aaaaaaaa.md"
  printf -- '- 2026-09-02 [planwright] cannot be read\n' \
    >"$tmp/specs28/_observations/entries/2026-09-02-noread-bbbbbbbb.md"
  chmod 000 "$tmp/specs28/_observations/entries/2026-09-02-noread-bbbbbbbb.md"
  drc=0
  out28=$("$drain" --today 2026-09-10 "$tmp/specs28") || drc=$?
  chmod 644 "$tmp/specs28/_observations/entries/2026-09-02-noread-bbbbbbbb.md"
  [ "$drc" -eq 0 ] \
    || fail "an unreadable fragment aborted the whole drain sweep (exit $drc)"
  printf '%s\n' "$out28" | grep -F 'unmined: 1 (fragments: 1)' >/dev/null \
    || fail "an unreadable fragment was counted, or the readable one was lost: $(printf '%s\n' "$out28" | grep -F unmined)"
  printf '%s\n' "$out28" | grep -F 'unreadable fragment' | grep -F '2026-09-02-noread-bbbbbbbb.md' >/dev/null \
    || fail "the unreadable fragment was not named in the report"

  # Lock the CI-shell portability regression directly under dash.
  if command -v dash >/dev/null 2>&1; then
    chmod 000 "$tmp/specs28/_observations/entries/2026-09-02-noread-bbbbbbbb.md"
    drc=0
    dash "$drain" --today 2026-09-10 "$tmp/specs28" >/dev/null 2>&1 || drc=$?
    chmod 644 "$tmp/specs28/_observations/entries/2026-09-02-noread-bbbbbbbb.md"
    [ "$drc" -eq 0 ] \
      || fail "an unreadable fragment aborts the drain sweep under dash (exit $drc)"
  fi
fi

# 33. A dangling symlink fragment (target missing) is named as invalid, not
#     silently skipped (D-7). `-e` is false for a broken symlink, so the
#     enumeration must treat it as present (`|| -L`) to name it, matching
#     check-obs.sh and scripts/obs-render.sh.
mkdir -p "$tmp/specs29/_observations/entries"
printf -- '- 2026-09-05 [planwright] a real live fragment\n' \
  >"$tmp/specs29/_observations/entries/2026-09-05-live-aaaaaaaa.md"
ln -s "$tmp/specs29-missing-target.md" \
  "$tmp/specs29/_observations/entries/2026-09-06-dangle-bbbbbbbb.md"
out29=$("$drain" --today 2026-09-10 "$tmp/specs29") \
  || fail "dangling-symlink fixture broke the sweep"
printf '%s\n' "$out29" | grep -F 'unmined: 1 (fragments: 1)' >/dev/null \
  || fail "a dangling symlink was counted, or the live fragment was lost: $(printf '%s\n' "$out29" | grep -F unmined)"
printf '%s\n' "$out29" | grep -F 'skipped invalid fragment' | grep -F '2026-09-06-dangle-bbbbbbbb.md' >/dev/null \
  || fail "a dangling symlink fragment was silently skipped instead of named"

# 34. A symlinked entries/ directory is surfaced as a note, not silently
#     treated as "no fragments" (D-7). obs-render.sh already warns on a
#     symlinked fragment directory and drain already notes a symlinked root,
#     so drain must note a symlinked entries/ too rather than hiding a
#     misconfigured store behind unmined: 0.
if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$tmp/specs30/_observations" "$tmp/specs30-realentries"
  printf -- '- 2020-01-01 [planwright] would leak if traversed\n' \
    >"$tmp/specs30-realentries/2020-01-01-leak-abcdabcd.md"
  ln -s "$tmp/specs30-realentries" "$tmp/specs30/_observations/entries"
  out30=$("$drain" --today 2026-09-10 "$tmp/specs30") \
    || fail "symlinked-entries fixture broke the sweep"
  printf '%s\n' "$out30" | grep -F 'entries/ is a symlink' >/dev/null \
    || fail "a symlinked entries/ directory was not surfaced as a note"
  printf '%s\n' "$out30" | grep -F '2020-01-01' >/dev/null \
    && fail "the sweep read the store through a symlinked entries/ directory"
fi

# ---------------------------------------------------------------------------
# 35–38. Format-version 2 (invariant-tasks Task 5; D-8, D-3; REQ-C1.3,
# REQ-B1.4, REQ-B1.5, REQ-C1.8, REQ-C1.9): task-completion atoms resolve
# through the derivation engine, not `## Completed` membership. v2 fixtures are
# real git repos with trailer evidence (the engine needs a work tree).
# ---------------------------------------------------------------------------

# git with a deterministic, signing-free identity (mirrors the engine test).
gitc() {
  _gr="$1"
  shift
  git -C "$_gr" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# 35. REQ-C1.3 — on a v2 bundle with NO ## Completed section, a task-completion
#     atom resolves met from merged evidence (a reachable Planwright-Task
#     trailer) and unmet for a task with no evidence.
v2r="$tmp/v2repo"
mkdir -p "$v2r/specs/omega"
git -C "$v2r" -c init.defaultBranch=main init -q
printf '%s\n' '# Omega' '' '**Status:** Ready' \
  >"$v2r/specs/omega/requirements.md"
cat >"$v2r/specs/omega/tasks.md" <<'EOF'
# Omega — Tasks

**Format-version:** 2

## Tasks

### Task 1 — landed work

- **Done when:** done.

### Task 2 — future work

- **Done when:** later.

## Awaiting input

(none yet)

## Deferred

- **Landed dep.** Its dependency merged.
  **Gate:** GATE(when: task 1 completed). Citations: REQ-X.
- **Waiting dep.** Blocks on unfinished work.
  **Gate:** GATE(when: task 2 completed). Citations: REQ-X.

## Out of scope

(none yet)
EOF
gitc "$v2r" add -A
gitc "$v2r" commit -q -m "base: v2 bundle"
gitc "$v2r" commit -q --allow-empty -m "task 1 done" -m "Planwright-Task: omega/1"
outv2=$("$drain" --today 2026-07-15 "$v2r/specs") \
  || fail "v2 fixture broke the sweep"
printf '%s\n' "$outv2" | grep '^SATISFIED' | grep -F 'Landed dep' >/dev/null \
  || fail "v2 task-completion atom not resolved via the derivation engine: $(printf '%s\n' "$outv2" | grep -F 'Landed dep')"
printf '%s\n' "$outv2" | grep '^PENDING' | grep -F 'Waiting dep' >/dev/null \
  || fail "v2 evidence-less task atom must stay PENDING"
echo "ok: v2 completion atoms resolve through the derivation engine (REQ-C1.3)"

# 36. REQ-B1.4 + REQ-C1.9 — a live reference bullet outranks git evidence (a
#     parked task never resolves completed), and a bullet whose task id
#     violates the grammar is rejected with a note, never used.
v2p="$tmp/v2parked"
mkdir -p "$v2p/specs/sigma"
git -C "$v2p" -c init.defaultBranch=main init -q
printf '%s\n' '# Sigma' '' '**Status:** Ready' \
  >"$v2p/specs/sigma/requirements.md"
{
  cat <<'EOF'
# Sigma — Tasks

**Format-version:** 2

## Tasks

### Task 1 — merged but re-parked

- **Done when:** done.

## Awaiting input

(none yet)

## Deferred

- **Task 1** parked for a rethink despite the merge.
- **Parked dep.** Bullet authority: task 1 must not resolve completed.
  **Gate:** GATE(when: task 1 completed). Citations: REQ-X.

## Out of scope

EOF
  # A grammar-violating bullet id (raw ESC byte embedded): rejected, sanitized.
  printf -- '- **Task 9\033[31mx** hostile bullet id.\n'
} >"$v2p/specs/sigma/tasks.md"
gitc "$v2p" add -A
gitc "$v2p" commit -q -m "base: v2 parked bundle"
gitc "$v2p" commit -q --allow-empty -m "task 1 done" -m "Planwright-Task: sigma/1"
outv2p=$("$drain" --today 2026-07-15 "$v2p/specs") \
  || fail "v2 parked fixture broke the sweep"
printf '%s\n' "$outv2p" | grep '^SATISFIED' | grep -F 'Parked dep' >/dev/null \
  && fail "bullet authority violated: a parked task resolved completed"
printf '%s\n' "$outv2p" | grep '^PENDING' | grep -F 'Parked dep' >/dev/null \
  || fail "the parked-task gate must stay PENDING (bullet authority, REQ-B1.4)"
printf '%s\n' "$outv2p" | grep -F 'reference bullet rejected' >/dev/null \
  || fail "grammar-violating bullet id not surfaced as rejected (REQ-C1.9)"
printf '%s' "$outv2p" | tr -d '\012' | LC_ALL=C grep '[^ -~]' >/dev/null \
  && fail "hostile bullet id leaked non-printable bytes into the report"
echo "ok: v2 bullet authority holds and hostile bullet ids are rejected (REQ-B1.4, REQ-C1.9)"

# 37. REQ-B1.5 — transient evidence failure on a v2 bundle: with a remote
#     configured and gh failing, task-completion atoms resolve as UNRESOLVED
#     (never satisfied from partial evidence), the failure is surfaced and
#     counted, and the sweep still completes with exit 0.
ghstub="$tmp/ghstub"
mkdir -p "$ghstub"
printf '#!/bin/sh\necho "gh: simulated failure" >&2\nexit 1\n' >"$ghstub/gh"
chmod +x "$ghstub/gh"
gitc "$v2r" remote add origin https://example.invalid/demo.git
outv2d=$(PATH="$ghstub:$PATH" "$drain" --today 2026-07-15 "$v2r/specs") \
  || fail "v2 failing-remote sweep must still exit 0"
gitc "$v2r" remote remove origin
printf '%s\n' "$outv2d" | grep -F 'transient evidence failure' >/dev/null \
  || fail "v2 transient evidence failure not surfaced (REQ-B1.5)"
printf '%s\n' "$outv2d" | grep '^SATISFIED' | grep -F 'Landed dep' >/dev/null \
  && fail "partial evidence presented as status: a task atom resolved met during a transient failure"
printf '%s\n' "$outv2d" | grep '^PENDING' | grep -F 'Landed dep' \
  | grep -F 'unresolved (completion evidence unavailable): task 1 completed' >/dev/null \
  || fail "the PENDING row must name the unresolved atom during a transient failure: $(printf '%s\n' "$outv2d" | grep -F 'Landed dep')"
printf '%s\n' "$outv2d" | grep -F 'errors: 1' >/dev/null \
  || fail "the transient failure must be counted exactly once (errors: 1): $(printf '%s\n' "$outv2d" | grep -F 'errors:')"
echo "ok: v2 transient evidence failure leaves completion atoms unresolved (REQ-B1.5)"

# 38. REQ-C1.8 — a missing or unparseable Format-version: line fails closed
#     per spec: the error is reported, no gate row is produced for that spec
#     (never evaluated under guessed rules), and the sweep completes.
mkdir -p "$tmp/specs31/nofv" "$tmp/specs31/badfv"
printf '%s\n' '# N' '' '**Status:** Active' >"$tmp/specs31/nofv/requirements.md"
printf '%s\n' '# N — Tasks' '' '## Completed' '' '### Task 1 — Done' '' \
  '- **Done when:** done.' '' '## Deferred' '' \
  '- **Fv gap.** Must not be evaluated without a parsed version.' \
  '  **Gate:** GATE(when: task 1 completed). Citations: REQ-X.' \
  >"$tmp/specs31/nofv/tasks.md"
printf '%s\n' '# B' '' '**Status:** Active' >"$tmp/specs31/badfv/requirements.md"
printf '%s\n' '# B — Tasks' '' '**Format-version:** 3beta' '' '## Completed' '' \
  '### Task 1 — Done' '' '- **Done when:** done.' '' '## Deferred' '' \
  '- **Fv bogus.** Must not be evaluated under guessed rules.' \
  '  **Gate:** GATE(when: task 1 completed). Citations: REQ-X.' \
  >"$tmp/specs31/badfv/tasks.md"
out31=$("$drain" --today 2026-07-15 "$tmp/specs31") \
  || fail "Format-version fixtures broke the sweep"
printf '%s\n' "$out31" | grep -F 'Format-version' >/dev/null \
  || fail "missing/unparseable Format-version not surfaced (REQ-C1.8)"
printf '%s\n' "$out31" | grep -F 'Fv gap' >/dev/null \
  && fail "a gate was evaluated in a bundle with no Format-version (fell open)"
printf '%s\n' "$out31" | grep -F 'Fv bogus' >/dev/null \
  && fail "a gate was evaluated under an unparseable Format-version (fell open)"
printf '%s\n' "$out31" | grep -F 'errors: 2' >/dev/null \
  || fail "Format-version fail-closed errors not counted (expected errors: 2)"
echo "ok: a missing/unparseable Format-version fails closed per spec (REQ-C1.8)"

# 39. Unresolved atoms are marked at ROW level (REQ-B1.5): under a failing
#     remote, a bullet-parked task's gate stays un-satisfied and every affected
#     row names the unresolved atom — the pure task gate as PENDING, a mixed
#     date+task gate as DORMANT with the marker (never silently dropped) — and
#     the failure is counted exactly once for the spec.
v2m="$tmp/v2marked"
mkdir -p "$v2m/specs/rho"
git -C "$v2m" -c init.defaultBranch=main init -q
printf '%s\n' '# Rho' '' '**Status:** Ready' >"$v2m/specs/rho/requirements.md"
cat >"$v2m/specs/rho/tasks.md" <<'EOF'
# Rho — Tasks

**Format-version:** 2

## Tasks

### Task 1 — merged but parked

- **Done when:** done.

## Awaiting input

(none yet)

## Deferred

- **Task 1** parked pending a rethink.
- **Parked landed.** Bullet authority plus evidence failure.
  **Gate:** GATE(when: task 1 completed). Citations: REQ-X.
- **Mixed date.** Date reached, task atom unresolvable.
  **Gate:** GATE(when: after 2020-01-01 and task 1 completed).
  Citations: REQ-X.

## Out of scope

(none yet)
EOF
gitc "$v2m" add -A
gitc "$v2m" commit -q -m "base: v2 marked bundle"
gitc "$v2m" commit -q --allow-empty -m "task 1 done" -m "Planwright-Task: rho/1"
gitc "$v2m" remote add origin https://example.invalid/demo.git
out39=$(PATH="$ghstub:$PATH" "$drain" --today 2026-07-15 "$v2m/specs") \
  || fail "v2 marked-unresolved sweep must still exit 0"
printf '%s\n' "$out39" | grep '^PENDING' | grep -F 'Parked landed' \
  | grep -F 'unresolved (completion evidence unavailable): task 1 completed' >/dev/null \
  || fail "PENDING row must name the unresolved atom: $(printf '%s\n' "$out39" | grep -F 'Parked landed')"
printf '%s\n' "$out39" | grep '^DORMANT' | grep -F 'Mixed date' \
  | grep -F 'unresolved (completion evidence unavailable): task 1 completed' >/dev/null \
  || fail "DORMANT row must carry the unresolved marker too: $(printf '%s\n' "$out39" | grep -F 'Mixed date')"
printf '%s\n' "$out39" | grep '^SATISFIED' >/dev/null \
  && fail "no gate may resolve SATISFIED during a transient evidence failure"
printf '%s\n' "$out39" | grep -F 'errors: 1' >/dev/null \
  || fail "the transient failure must be counted exactly once (expected errors: 1)"
echo "ok: unresolved atoms are marked in PENDING and DORMANT rows (REQ-B1.5)"

# 40. Mixed v1+v2 sweep root (REQ-D1.1 coexistence): one sweep resolves a v1
#     spec via ## Completed membership and a v2 spec via the derivation engine,
#     with per-spec version keying isolated (the v2 evidence state must not
#     bleed into the v1 spec's evaluation or vice versa).
v2x="$tmp/v2mixed"
mkdir -p "$v2x/specs/vone" "$v2x/specs/vtwo"
git -C "$v2x" -c init.defaultBranch=main init -q
printf '%s\n' '# V1' '' '**Status:** Active' >"$v2x/specs/vone/requirements.md"
printf '%s\n' '# V1 — Tasks' '' '**Format-version:** 1' '' '## Completed' '' \
  '### Task 1 — Landed' '' '- **Done when:** done.' '' '## Deferred' '' \
  '- **Vone landed.** Resolved by section membership.' \
  '  **Gate:** GATE(when: task 1 completed). Citations: REQ-X.' \
  >"$v2x/specs/vone/tasks.md"
printf '%s\n' '# V2' '' '**Status:** Ready' >"$v2x/specs/vtwo/requirements.md"
printf '%s\n' '# V2 — Tasks' '' '**Format-version:** 2' '' '## Tasks' '' \
  '### Task 1 — Landed' '' '- **Done when:** done.' '' \
  '## Awaiting input' '' '(none yet)' '' '## Deferred' '' \
  '- **Vtwo landed.** Resolved by the derivation engine.' \
  '  **Gate:** GATE(when: task 1 completed). Citations: REQ-X.' '' \
  '## Out of scope' '' '(none yet)' \
  >"$v2x/specs/vtwo/tasks.md"
gitc "$v2x" add -A
gitc "$v2x" commit -q -m "base: mixed root"
gitc "$v2x" commit -q --allow-empty -m "task 1 done" -m "Planwright-Task: vtwo/1"
out40=$("$drain" --today 2026-07-15 "$v2x/specs") \
  || fail "mixed v1+v2 sweep broke"
printf '%s\n' "$out40" | grep '^SATISFIED' | grep -F 'Vone landed' >/dev/null \
  || fail "v1 spec in a mixed root must resolve via section membership"
printf '%s\n' "$out40" | grep '^SATISFIED' | grep -F 'Vtwo landed' >/dev/null \
  || fail "v2 spec in a mixed root must resolve via the derivation engine"
printf '%s\n' "$out40" | grep -F 'errors: 0' >/dev/null \
  || fail "mixed root must sweep cleanly (errors: 0)"
echo "ok: v1 and v2 specs coexist in one sweep with isolated version keying (REQ-D1.1)"

# 41. A missing derivation engine fails closed per spec: task atoms resolve as
#     unresolved with an error row, and the sweep completes. (Exercised by
#     running a copy of drain-gates.sh from a directory with no sibling
#     orchestrate-state.sh.)
lonedir="$tmp/lonedrain"
mkdir -p "$lonedir"
cp "$drain" "$lonedir/drain-gates.sh"
chmod +x "$lonedir/drain-gates.sh"
out41=$("$lonedir/drain-gates.sh" --today 2026-07-15 "$v2r/specs") \
  || fail "missing-engine sweep must still exit 0"
printf '%s\n' "$out41" | grep -F 'derivation engine unavailable' >/dev/null \
  || fail "a missing derivation engine must be surfaced as an error row"
printf '%s\n' "$out41" | grep '^SATISFIED' | grep -F 'Landed dep' >/dev/null \
  && fail "task atoms must not resolve met without the engine"
echo "ok: a missing derivation engine fails closed to unresolved atoms"

# 42. Engine-consult gating: a v2 bundle with tasks but no gates never consults
#     the engine (no spurious error in a non-git root), and a v2 bundle whose
#     only task heading and only gate marker sit inside a fence is illustration
#     — no engine consult, no error.
mkdir -p "$tmp/specs32/quiet" "$tmp/specs32/fenced"
printf '%s\n' '# Q' '' '**Status:** Ready' >"$tmp/specs32/quiet/requirements.md"
printf '%s\n' '# Q — Tasks' '' '**Format-version:** 2' '' '## Tasks' '' \
  '### Task 1 — work' '' '- **Done when:** done.' '' \
  '## Awaiting input' '' '(none yet)' '' '## Deferred' '' '(none yet)' '' \
  '## Out of scope' '' '(none yet)' \
  >"$tmp/specs32/quiet/tasks.md"
printf '%s\n' '# F' '' '**Status:** Ready' >"$tmp/specs32/fenced/requirements.md"
printf '%s\n' '# F — Tasks' '' '**Format-version:** 2' '' '## Tasks' '' \
  '```markdown' '### Task 9 — an illustration, not a task' '' \
  '- **Illustrative.** Not a real deferral.' \
  '  **Gate:** GATE(when: task 9 completed).' '```' '' \
  '## Awaiting input' '' '(none yet)' '' '## Deferred' '' '(none yet)' '' \
  '## Out of scope' '' '(none yet)' \
  >"$tmp/specs32/fenced/tasks.md"
out42=$("$drain" --today 2026-07-15 "$tmp/specs32") \
  || fail "engine-gating fixtures broke the sweep"
printf '%s\n' "$out42" | grep -F 'derivation failed' >/dev/null \
  && fail "a gate-less or fenced-only v2 bundle must not consult the engine (spurious derivation error)"
printf '%s\n' "$out42" | grep -F 'errors: 0' >/dev/null \
  || fail "engine-gating fixtures must sweep cleanly (errors: 0): $(printf '%s\n' "$out42" | grep -F errors:)"
echo "ok: the engine is consulted only when unfenced task atoms could need it"

# 43. Prose-bullet tolerance (validator parity): a plain prose bullet whose
#     bold lead starts with "Task " plus inner whitespace is never warned about
#     as a rejected reference and parks nothing.
v2q="$tmp/v2prose"
mkdir -p "$v2q/specs/tau"
git -C "$v2q" -c init.defaultBranch=main init -q
printf '%s\n' '# Tau' '' '**Status:** Ready' >"$v2q/specs/tau/requirements.md"
printf '%s\n' '# Tau — Tasks' '' '**Format-version:** 2' '' '## Tasks' '' \
  '### Task 1 — Landed' '' '- **Done when:** done.' '' \
  '## Awaiting input' '' '(none yet)' '' '## Deferred' '' \
  '- **Task force assembled.** A plain prose bullet, not a reference.' \
  '- **Landed anyway.** The prose bullet parks nothing.' \
  '  **Gate:** GATE(when: task 1 completed). Citations: REQ-X.' '' \
  '## Out of scope' '' '(none yet)' \
  >"$v2q/specs/tau/tasks.md"
gitc "$v2q" add -A
gitc "$v2q" commit -q -m "base: prose bullet bundle"
gitc "$v2q" commit -q --allow-empty -m "task 1 done" -m "Planwright-Task: tau/1"
out43=$("$drain" --today 2026-07-15 "$v2q/specs") \
  || fail "prose-bullet fixture broke the sweep"
printf '%s\n' "$out43" | grep -F 'reference bullet rejected' >/dev/null \
  && fail "a plain prose bullet must not be reported as a rejected reference"
printf '%s\n' "$out43" | grep '^SATISFIED' | grep -F 'Landed anyway' >/dev/null \
  || fail "a prose bullet must park nothing (task 1 stays completed)"
echo "ok: prose bullets with inner whitespace are tolerated silently (validator parity)"

echo "PASS: test-drain-gates.sh"
