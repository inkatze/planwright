# Didactic authoring — Tasks

**Status:** Draft
**Last reviewed:** 2026-11-04
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order. Task 1 adds a hook to the plugin's wiring and takes
the hook-and-guard review its PR presents; Task 6 is the operator's own rating
and cannot be dispatched to an agent alone.

## Tasks

### Task 1 — The live question check

- **Deliverables:** a recorded probe of the question tool's `PreToolUse` input
  shape (a captured, sanitized sample committed as a test fixture); a new
  `scripts/question-check.sh` implementing REQ-C1.2's rules, the fail-open
  paths, and the per-session consecutive-return cap (state under the plugin
  data directory); its `PreToolUse` wiring in `hooks/hooks.json`; the switch
  and length knobs in `config/defaults.yml` and `docs/options-reference.md`;
  `tests/test-question-check.sh` with fixtures.
- **Done when:** the test passes in `mise run check`, covering: an identifier
  in question text or a label returns the question with a reason naming the
  rule and the fix; an identifier only in a description or preview passes; an
  over-length stem returns; an option with no description returns; the
  steered-back and rewritten fixtures in `test-spec.md` fail and pass
  respectively; malformed input, a missing `jq`, and the switch off each pass
  silently; the cap passes the next question with a misfire note and a passing
  question resets the count; payload text carrying shell metacharacters is
  never executed. `check:hook-contracts` accepts the new wiring.
- **Dependencies:** none
- **Citations:** D-4, D-5, D-6 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4,
  REQ-C1.5, REQ-C1.6
- **Estimated effort:** 1 day

### Task 2 — The operator level store

- **Deliverables:** `scripts/operator-level.sh` with read, raise, lower, mark a
  concept held, and reset verbs over a small store under the plugin data
  directory; `tests/test-operator-level.sh`.
- **Done when:** the test passes in `mise run check`, covering: no store reads
  as plain; a raise, a lower, and a held concept persist across invocations;
  a malformed or unreadable store reads as plain with nothing on stderr meant
  for the operator; the store holds only the level and concept names (a write
  of any other field is refused); reset removes it.
- **Dependencies:** none
- **Citations:** D-3 · REQ-B1.1, REQ-B1.3, REQ-B1.4, REQ-B1.5
- **Estimated effort:** half day

### Task 3 — Kickoff teaches at the point of action

- **Deliverables:** `skills/spec-kickoff/SKILL.md`'s operator-facing steps
  reworded per D-8 (teaching action then one question, plain first turn,
  consequence-first walk for an operator-authored bundle), reading the level
  store at start and writing it at end, honoring "simpler" and "more detail";
  the two doctrine repairs in `doctrine/kickoff-dialogue.md` and
  `doctrine/interaction-style.md` (D-3's stored-starting-point clause, D-9's
  per-pass ceiling wording); a new static check `scripts/check-didactic-wording.sh`
  owning the banned-verb list, wired into `mise run check`, with its test.
- **Done when:** the wording check passes on the reworded kickoff skill and
  fails on its pre-change text (the test pins both); the test also pins that
  neither doctrine doc's per-pass ceiling sentence reads as a per-turn
  allowance; `check:instructions`
  passes and the kickoff skill's charged closure is no larger than before;
  every sign-off, anchor, and lens-pass step reads as before apart from wording
  (the PR states the diff is wording-only on those steps).
- **Dependencies:** Task 2
- **Citations:** D-3, D-8, D-9 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4,
  REQ-A1.5, REQ-A1.6, REQ-A1.7, REQ-B1.2, REQ-E1.1, REQ-E1.2
- **Estimated effort:** 1 day

### Task 4 — Drafting teaches at the point of action

- **Deliverables:** `skills/spec-draft/SKILL.md`'s operator-facing steps
  reworded per D-8 (each elicitation phase opens plain, asks one question,
  carries identifiers only after the plain statement), reading and writing the
  level store as Task 3 does; the wording check's coverage extended to it.
- **Done when:** the wording check covers and passes on the drafting skill;
  `check:instructions` passes and the drafting skill's charged closure is no
  larger than before; the bundle-write, validator, and commit steps read as
  before apart from wording.
- **Dependencies:** Task 2, Task 3
- **Citations:** D-3, D-8, D-9 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4,
  REQ-A1.6, REQ-A1.7, REQ-B1.2, REQ-E1.1, REQ-E1.2
- **Estimated effort:** 1 day

### Task 5 — Mission control relays and steers

- **Deliverables:** `skills/mission-control/SKILL.md`'s kickoff relay rule
  widened to drafting sessions, stating pass-through-unchanged with source and
  progress only, and steer-back with what to change when a relayed question
  still reads cryptic or heavy, never a rewrite.
- **Done when:** the skill text states all three rules; `check:instructions`
  passes; the PR names `mission-control` as the owning spec of the edited
  skill.
- **Dependencies:** Task 1
- **Citations:** D-7 · REQ-D1.1, REQ-D1.2, REQ-D1.3
- **Estimated effort:** half day

### Task 6 — Operator acceptance rating

- **Deliverables:** an observation fragment, recorded through
  `scripts/obs-record.sh`, carrying the operator's rating of one real drafting
  session and one real kickoff run on the shipped surfaces, against the manual
  entries in `test-spec.md`.
- **Done when:** the fragment names both sessions and the operator's rating of
  each, with any "still heavy" finding stated so the next amendment can mine
  it.
- **Dependencies:** Task 1, Task 3, Task 4, Task 5
- **Citations:** D-1 · REQ-A1.2, REQ-A1.4, REQ-B1.1, REQ-D1.2
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
