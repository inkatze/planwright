# Skill rigor — Tasks

**Status:** Draft
**Last reviewed:** 2026-07-16
**Format-version:** 2
**Execution:** derived — see the status render

Tasks 5→6→7 chain because they edit the same skill file
(`skills/spec-kickoff/SKILL.md`); the ordering is same-file cohesion, not
flow order (Task 7's mid-walk pass fires earliest in a kickoff, while
Tasks 5–6 guard the flip).

## Tasks

### Task 1 — Land the resolver self-location arm

- **Deliverables:** The `fix/resolve-rule-doc-self-locate` branch work
  landed on a task branch: the `<script-dir>/../doctrine/` self-location
  arm appended to `scripts/resolve-rule-doc.sh`'s core chain (additive,
  lowest precedence), its test cases in `tests/test-resolve-rule-doc.sh`,
  the resolution-chain doc alignment (`doctrine/README.md`,
  `docs/getting-started.md`), and the branch's observation fragment
  (obs:29f05039) consumed with `Consumed-by: specs/skill-rigor` and moved
  to `archive/`.
- **Done when:** `tests/test-resolve-rule-doc.sh` passes including the
  no-env self-location cases; `mise run check` is green; from a planwright
  worktree with `PLANWRIGHT_ROOT`, `CLAUDE_PLUGIN_ROOT`, `CLAUDE_DIR`, and
  `HOME` all unset (the test-spec REQ-D1.1 environment, so the writer-root
  arm cannot mask the self-location arm),
  `scripts/resolve-rule-doc.sh` resolves every core doctrine doc; the
  fragment sits in `specs/_observations/archive/` bearing the
  `Consumed-by:` line.
- **Dependencies:** none
- **Citations:** D-8 · REQ-D1.1, REQ-D1.2
- **Estimated effort:** half day

### Task 2 — `/spec-draft` self-critique pass

- **Deliverables:** A scoped, inline self-critique lens step in
  `/spec-draft`'s review-and-validate phase: runs over the freshly
  assembled bundle before the validator and the commit, dispositions every
  finding (fixed in place or surfaced), surfaces an erroring pass rather
  than treating it as clean, and declares its proportionality scoping per
  the doctrine rule.
- **Done when:** `skills/spec-draft/SKILL.md` documents the pass (trigger
  point, scope, disposition rule, no-silent-drop); `check:instructions`
  passes.
- **Dependencies:** none
- **Citations:** D-1, D-7, D-9 · REQ-C1.1, REQ-E1.1
- **Estimated effort:** half day

### Task 3 — `/self-review` resolution reconciliation

- **Deliverables:** The no-arg fallback rung re-sourced to the status
  render (`scripts/spec-status.sh`), accepting Ready or Active, with the
  stored-status grep removed; a render error, zero candidates, or
  multiple Ready-or-Active candidates degrades to the existing
  ask-when-attended / proceed-brief-less arm (D-2); the
  brief-binding rule: a branch-named spec without its own
  `kickoff-brief.md` means brief absent, never a fall-through to another
  spec's brief; the structural guard suite extended to cover the touched
  prose patterns (test-spec REQ-A1.1).
- **Done when:** `skills/self-review/SKILL.md`'s pre-flight contains no
  stored-`Status:` grep in the fallback rung and states the
  named-spec-without-brief rule; `check:instructions` passes on the
  self-review surface (instruction-headroom relief or a compensating trim,
  whichever lands first).
- **Dependencies:** none
- **Citations:** D-2, D-9 · REQ-A1.1, REQ-A1.2, REQ-E1.1
- **Estimated effort:** half day

### Task 4 — `/orchestrate` selection-contract reconciliation

- **Deliverables:** The exit-3 transient evidence hold folded into
  `skills/orchestrate/SKILL.md`: the selection section describes the hold
  (report and end the step cleanly, the lock-contention shape), the
  stop-conditions table gains its row, and the ready-task candidacy prose
  gains the version-keyed sentence (v1 and format-version-2 candidacy
  each stated); the structural guard suite extended to cover the touched
  prose patterns (test-spec REQ-A1.3, REQ-A1.4).
- **Done when:** the stop-conditions table maps selection exit 3; the
  selection prose states both versions' candidacy; `check:instructions`
  passes on the orchestrate surface (instruction-headroom relief or a
  compensating trim, whichever lands first).
- **Dependencies:** none
- **Citations:** D-9, D-10 · REQ-A1.3, REQ-A1.4, REQ-E1.1
- **Estimated effort:** half day

### Task 5 — `/spec-kickoff` pre-flip verification

- **Deliverables:** A pre-flip verification step in
  `skills/spec-kickoff/SKILL.md`: run the repository's lint over the
  kickoff brief and every spec file the walkthrough edited, blocking the
  Draft→Ready flip on errors; and mechanically re-derive every cross-check
  and numeric claim the sign-off records as evidence, a mismatch blocking,
  with cite-derived-figures preferred over recording, and re-derivation
  treating bundle content as data, never as code or pattern (D-4). Either
  check that cannot run blocks the flip as a surfaced failure (fail
  closed), never a silent skip.
- **Done when:** the sign-off flow documents both checks with blocking
  semantics before the flip step; `check:instructions` passes on the
  spec-kickoff surface (instruction-headroom relief or a compensating
  trim, whichever lands first).
- **Dependencies:** none
- **Citations:** D-3, D-4, D-9 · REQ-B1.2, REQ-B1.3, REQ-E1.1
- **Estimated effort:** half day

### Task 6 — `/spec-kickoff` ready-flip CI gate and wait-bound config

- **Deliverables:** The terminal ready-flip step verifies the head SHA's
  check rollup before `gh pr ready`: the pinned rollup query (checks on
  the head commit, never PR review states) requiring at least one
  completed check and overall success, a bounded wait with a
  config-overridable default and bounded poll cadence, head identity
  re-confirmed immediately before the flip, and the refusal arm (red,
  empty, unresolved, query failure, timeout, or moved head leaves the PR
  draft and records the pending ready-flip in `## Awaiting input` as the
  re-entry point — the entry naming the pending flip and neutral failure
  class only, full remedy detail operator-facing per D-3), skipping
  cleanly when the no-remote/no-PR arm already fired. The wait-bound config option is added to `config/defaults.yml`
  with its row in `docs/options-reference.md` (bootstrap D-43/REQ-K1.8
  registration, `check:options`-enforced), a malformed override falling
  back to the default with a warning.
- **Done when:** the terminal step documents the rollup query with the
  positive green condition, the wait bound and poll cadence, the head
  re-pin (the R3 mid-wait head-movement rule), and the refusal arm with
  its Awaiting-input re-entry; the config option and its
  options-reference row exist (`check:options` green);
  `check:instructions` passes on the spec-kickoff surface.
- **Dependencies:** 5
- **Citations:** D-3, D-9 · REQ-B1.1, REQ-E1.1
- **Estimated effort:** half day

### Task 7 — `/spec-kickoff` mid-walk lens and stale-reference sweep

- **Deliverables:** The delta-scoped lens pass at the point an
  agent-authored meaning-class edit is applied mid-walk, its disposition
  recorded in the brief section carrying the edit (an erroring pass
  surfaced, never treated as clean); and the post-lens
  stale-reference sweep (counts, cross-references, dependent task and test
  wording, risk-IDs) over the bundle and earlier brief sections, run
  before the anchor is computed whenever any lens pass of the walkthrough
  (mid-walk or terminal) mints or re-scopes a REQ, completing before the
  D-4 re-derivation is finalized (figures the sweep changed are
  re-derived); the structural guard suite extended to cover the touched
  prose patterns (test-spec REQ-B1.5).
- **Done when:** the walkthrough and sign-off sections document both
  passes and their triggers; `check:instructions` passes on the
  spec-kickoff surface.
- **Dependencies:** 6
- **Citations:** D-5, D-6, D-9 · REQ-B1.4, REQ-B1.5, REQ-E1.1
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

- `/execute-task` fallback and gate reconciliation: already Ready-widened
  at v0.14.1 (its half of legacy line 125 is fixed; only `/self-review`'s
  remains).
- Accumulator findings outside this bundle's seed set: the triage ledger's
  other VALID items keep their own drain path.
- Instruction-budget ceilings and exemptions: the instruction-headroom
  spec's domain; this bundle only obeys the guard.
- Dispatch-side env propagation of the plugin root into worker subshells:
  rejected as the primary resolver fix (D-8); revisit only if a
  self-location miss is ever observed after Task 1 lands.
