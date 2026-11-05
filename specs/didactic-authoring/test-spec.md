# Didactic authoring — Test spec

**Status:** Draft
**Last reviewed:** 2026-11-04
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: the check, the store, and the wording check are `[test]`, run by
`mise run check` in CI; turn quality beyond structure is `[manual]`, rated by
the operator in Task 6; the no-weakening rules are `[design-level]` plus the
existing sign-off and anchor tests, which must stay green.

**Fixtures for the question check.** *Steered back:* a question whose stem
packs five areas as full paragraphs into one question, well past the length
default. *Rewritten, passes:* "Do these five areas cover what you meant?"
followed by five list lines of at most about fifteen words each, with three
options each carrying a one-line description. Both shapes come from this spec's
own drafting session, where mission control steered the first back.

## REQ-A — Plain by construction

### REQ-A1.1 — Teaching action, no audit verbs [test + manual]

`tests/test-check-didactic-wording.sh`: the wording check passes on both
reworded skills and fails on the pre-change kickoff text. Manual: Task 6's
rating confirms the walk reads as teaching.

### REQ-A1.2 — Plain first turn [manual]

Task 6: the first turn of each rated session states situation, problem, and
recommendation with no identifier and no rule-reading fork.

### REQ-A1.3 — Plain language leads [test + manual]

The question check (REQ-C1.2) enforces it for every question; Task 6 rates
non-question turns.

### REQ-A1.4 — Every question says what, why, and what changes [manual]

Task 6's operator rating, one drafting session and one kickoff.

### REQ-A1.5 — Consequences for an operator-authored bundle [manual]

Task 6's kickoff is of a bundle the operator drafted; the rating confirms the
walk taught consequences rather than posing gaps as rulings.

### REQ-A1.6 — One question per turn [test + manual]

`tests/test-check-didactic-wording.sh` asserts the reworded ceiling sentence
in both doctrine docs no longer reads as a per-turn allowance (a pinned
phrase check); Task 6 rates the live turns.

### REQ-A1.7 — The static wording check [test]

`tests/test-check-didactic-wording.sh`: a fixture step carrying a banned verb
fails the check; the check is listed in `mise run check`'s depends.

## REQ-B — The operator's level

### REQ-B1.1 — Plain with no store [test + manual]

`tests/test-operator-level.sh`: no store reads as plain. Task 6 runs one
session on a machine with the store reset.

### REQ-B1.2 — Deepen on uptake, fall back on confusion [manual]

Task 6's rating notes whether depth followed the operator's answers.

### REQ-B1.3 — Remembered per machine, outside the repository [test]

`tests/test-operator-level.sh`: writes persist across invocations and land
under the plugin data directory, never inside the working tree.

### REQ-B1.4 — "Simpler" and "more detail" [test + manual]

`tests/test-operator-level.sh`: raise and lower persist. Task 6: the operator
says one of them mid-session and the next turn changes.

### REQ-B1.5 — Coarse, losable store [test]

`tests/test-operator-level.sh`: a write of any field beyond level and concept
names is refused; a malformed store reads as plain with no operator-facing
error.

## REQ-C — The live question check

### REQ-C1.1 — Every question checked, failures returned with a reason [test]

`tests/test-question-check.sh`: a failing question yields a deny decision whose
reason names the rule and the fix; `check:hook-contracts` accepts the wiring.

### REQ-C1.2 — The three structural rules [test]

`tests/test-question-check.sh`: identifier in stem or label fails, in a
description or preview passes; over-length stem fails; missing description
fails; the steered-back fixture fails and the rewritten fixture passes.

### REQ-C1.3 — Knobs and the off switch [test]

`tests/test-question-check.sh`: the switch off passes everything; an overridden
length limit changes the outcome; both knobs appear in
`docs/options-reference.md`.

### REQ-C1.4 — Fail open [test]

`tests/test-question-check.sh`: malformed input and a missing `jq` each pass
the question.

### REQ-C1.5 — Never stall [test]

`tests/test-question-check.sh`: at the cap the next question passes with a
misfire note; a passing question resets the count.

### REQ-C1.6 — Untrusted payload [test]

`tests/test-question-check.sh`: a payload carrying command substitution and
shell metacharacters is checked as text and never executed (a sentinel file
stays absent).

## REQ-D — Mission control's relay

### REQ-D1.1 — Pass through unchanged [design-level + manual]

The mission-control skill states the rule (Task 5). Task 6's drafting session
runs relayed and the operator confirms the question arrived as written.

### REQ-D1.2 — Steer back, never rewrite [design-level + manual]

The mission-control skill states it (Task 5); Task 6 notes any steer-back seen.

### REQ-D1.3 — Drafting sessions covered [design-level]

The mission-control skill's relay rule names drafting sessions (Task 5).

## REQ-E — Nothing weakens

### REQ-E1.1 — No gate or artifact weakened [design-level + test]

Tasks 3 and 4 state their diffs are wording-only on sign-off, anchor, lens,
bundle-write, and commit steps; the existing sign-off and anchor tests stay
green in `mise run check`.

### REQ-E1.2 — Instruction budget [test]

`check:instructions` passes on every PR, and Tasks 3 and 4 record the
before-and-after charged closure of their skill.
