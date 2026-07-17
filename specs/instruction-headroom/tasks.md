# Instruction-budget headroom — Tasks

**Status:** Draft
**Last reviewed:** 2026-07-16
**Format-version:** 2
**Execution:** derived — see the status render

Task blocks below sit in dependency order. The guard tasks (2–5) precede
every restoration pass deliberately: a diet is unverifiable until margin
reporting and the capped charge exist.

## Tasks

### Task 1 — Headroom policy doctrine

- **Deliverables:** An amendment to `doctrine/instruction-hygiene.md`
  defining the headroom floors and their default values, the 2×-floor
  restoration targets with the declared-exception path, the four-rung
  restoration ladder with rung-entry conditions, the capped-charge law for
  permanently exempt docs, the raise/exemption recorded-rationale
  discipline, and the safety-floor constraint on every rung.
- **Done when:** The amended doc states floors, targets, ladder, cap, and
  rationale discipline; `check-instructions` stays green on the amended doc
  (it sits well under its per-file warn and no skill front-loads it);
  `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-1, D-2, D-3, D-4, D-5 · REQ-A1.1, REQ-A1.2, REQ-A1.3,
  REQ-A1.4, REQ-A1.5, REQ-B1.1, REQ-B1.2
- **Estimated effort:** half day

### Task 2 — Guard floors and margin reporting

- **Deliverables:** Four headroom-floor knobs in `config/defaults.yml`
  (250/250/500/1,000, following the `instruction_budget_*` naming pattern);
  a named floor-breach warning in every guard run for any surface whose
  margin to its error threshold is below its floor; margin-to-warn and
  margin-to-error values in `--audit` output; fixture tests covering breach
  (warns) and compliance (silent).
- **Done when:** The fixtures pass in `tests/test-check-instructions.sh`;
  a real-corpus run reports margins and emits breach warnings for today's
  saturated surfaces; `mise run check` passes.
- **Dependencies:** 1
- **Citations:** D-2, D-8 · REQ-A1.1, REQ-D1.1
- **Estimated effort:** half day

### Task 3 — Guard capped charge for exempt docs

- **Deliverables:** Aggregate enforcement (start-load and closure) charging
  permanently exempt docs at min(actual, per-file error threshold);
  charged-vs-actual printed in `--audit` for capped docs; the spec-format
  exemption rationale rewritten to state the capped-charge semantics and
  drop the superseded "dominant run-start load" claim; fixture tests for
  the cap on both aggregates.
- **Done when:** Fixtures pass; the real-corpus audit shows the orchestrate
  closure and execute-task start-load charged with `spec-format.md` at
  4,000 while its actual 5,125 stays printed; `mise run check` passes.
- **Dependencies:** 1
- **Citations:** D-4 · REQ-B1.1, REQ-B1.2, REQ-D1.5
- **Estimated effort:** half day

### Task 4 — Guard test-surface fixes

- **Deliverables:** The pending-diet allowance's Task field emitted in the
  audit shortlist and ranked report; the test suite's real-corpus
  offender-shortlist expectations derived from the suppression list instead
  of hardcoded file names; a fixture proving a Task retag is visible in
  output.
- **Done when:** A fixture allowance's Task retag changes the asserted
  output; adding a fixture exemption changes derived expectations without
  editing test name lists; `mise run check` passes.
- **Dependencies:** 2, 3
- **Citations:** D-8 · REQ-D1.2, REQ-D1.4
- **Estimated effort:** half day

### Task 5 — Guard reverse use-site check

- **Deliverables:** A per-skill check that every point-of-use manifest doc
  is named in body prose outside the manifest block and fenced code, at
  warning severity, with fixtures for both the missing and the named case;
  any existing corpus misses it surfaces are either fixed in-body or
  recorded for their owning skill.
- **Done when:** Fixtures pass; the real corpus runs warning-free or each
  remaining warning has a recorded disposition; `mise run check` passes.
- **Dependencies:** 2
- **Citations:** D-7 · REQ-D1.3
- **Estimated effort:** half day

### Task 6 — gate-wiring.md diet

- **Deliverables:** A ~500-word diet of `doctrine/gate-wiring.md` bringing
  it under its 2,500-word per-file warn, relieving the self-review and
  polish start-loads and the orchestrate and execute-task closures; law
  preserved verbatim in meaning.
- **Done when:** gate-wiring.md is below 2,500 words; the content-pinned
  structural tests pass in the same PR; pinned lists and grepped phrases
  remain unbroken on one line; no floor-breach warning names gate-wiring.md;
  `mise run check` passes.
- **Dependencies:** 2, 3, 4
- **Citations:** D-6, D-10 · REQ-C1.1, REQ-C1.2
- **Estimated effort:** half day

### Task 7 — execute-task body diet

- **Deliverables:** A ~500-word diet of `skills/execute-task/SKILL.md` to
  at most 3,750 words (the 2×-floor body target), including the duplicated
  no-Status rationale identified at prompt-hygiene Task 6 closeout; law
  preserved verbatim in meaning.
- **Done when:** The body is ≤3,750 words; the content-pinned structural
  tests (including `tests/test-execute-task-status-write.sh`) pass in the
  same PR; execute-task's start-load and closure margins meet their
  targets under the Task 3 cap; `mise run check` passes.
- **Dependencies:** 2, 3, 4
- **Citations:** D-6, D-10 · REQ-C1.1, REQ-C1.2
- **Estimated effort:** half day

### Task 8 — spec-kickoff body diet

- **Deliverables:** A ~500-word diet of `skills/spec-kickoff/SKILL.md` to
  at most 3,750 words; law preserved verbatim in meaning.
- **Done when:** The body is ≤3,750 words; the content-pinned structural
  tests pass in the same PR; no floor-breach warning names spec-kickoff's
  body; `mise run check` passes.
- **Dependencies:** 2, 3, 4
- **Citations:** D-6, D-10 · REQ-C1.1, REQ-C1.2
- **Estimated effort:** half day

### Task 9 — orchestrate body diet

- **Deliverables:** A ~450-word diet of `skills/orchestrate/SKILL.md` to at
  most 3,750 words; combined with the Task 3 cap and Task 6 diet this
  brings the orchestrate closure to its 2,000-word restoration target; law
  preserved verbatim in meaning.
- **Done when:** The body is ≤3,750 words; the content-pinned structural
  tests pass in the same PR; the orchestrate closure margin is ≥2,000 in
  the audit; `mise run check` passes.
- **Dependencies:** 2, 3, 4
- **Citations:** D-6, D-10 · REQ-C1.1, REQ-C1.2
- **Estimated effort:** half day

### Task 10 — research-rigor reclassification in self-review and polish

- **Deliverables:** `research-rigor` moved run-start → point-of-use in the
  self-review and polish manifests (site: the finding-validation step where
  its triggers fire), with the doc named at that in-body step and a
  recorded safety-floor analysis (trigger-fired law, not permission-gating;
  execute-task precedent).
- **Done when:** Both manifests parse; the Task 5 use-site check passes for
  both skills; both start-loads meet the 1,000-word restoration target in
  the audit (with the Task 6 diet landed; a small body trim tops up if
  needed); `mise run check` passes.
- **Dependencies:** 2, 5, 6
- **Citations:** D-6 · REQ-C1.1, REQ-C1.3
- **Estimated effort:** half day

### Task 11 — Closing verification and guidance re-land

- **Deliverables:** A real-corpus verification that every budgeted surface
  meets its floor with margin at or above its restoration target (or
  carries a declared exception), from the guard's margin report in CI; the
  ~80-word `migrate-format-version.sh` guidance re-landed in
  `doctrine/spec-format.md`'s versioning section; `--closeout` clean (no
  pending-diet allowance remains).
- **Done when:** `check-instructions` runs breach-warning-free on the real
  corpus (or every remaining warning has a declared exception recorded);
  the guidance is present in spec-format.md and the guard stays green;
  `check-instructions --closeout` exits zero; `mise run check` passes.
- **Dependencies:** 6, 7, 8, 9, 10
- **Citations:** D-3, D-9 · REQ-C1.1, REQ-C1.4
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

- **format-grammar's meta-spec wording.** The sibling spec spends the
  headroom this spec creates; its fragment 94f03e6c is deliberately not
  consumed here. Citations: D-4, requirements Out of scope.
- **Measurement-unit or guard-architecture changes.** Words stay the unit;
  the guard stays plain POSIX shell with data-only inputs. Citations:
  requirements Out of scope.
