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
  (`instruction_budget_<skill|doctrine|startload|closure>_floor`,
  250/250/500/1,000); a named floor-breach warning in every guard run for
  any floored surface whose margin is strictly below its floor, and a
  named below-target warning when margin is at or above the floor but
  below twice the floor (D-11),
  with a missing or non-numeric floor knob aborting fail-loud like the
  existing budget knobs; margin-to-warn and margin-to-error values in
  `--audit` output for the four floored classes; the
  `declared-exception|<surface>|<reason>` suppression form excusing
  exactly the warning it names — below-target, or use-site via the
  `use-site:` key; never floor-breach (D-11); raise-rationale enforcement
  per D-12
  (`raise|<knob>|<value>|<reason>` entries; an effective
  `instruction_budget_*_warn/_error` value above its shipped core default
  with no matching entry is a config error, failing closed on an absent
  or unreadable baseline or a stale `raise|` entry); reference rows for
  the new knobs in `docs/options-reference.md`; fixture tests covering breach (warns),
  compliance (silent), the at-floor boundary (compliant), below-target
  with and without a declared exception, the raise with and without
  rationale, and one control-byte echo-safety fixture (cross-cutting).
- **Done when:** The fixtures pass in `tests/test-check-instructions.sh`;
  a real-corpus run reports margins and emits breach warnings for today's
  saturated surfaces; a fixture raise without recorded rationale fails the
  guard's config parsing; `mise run check` passes.
- **Dependencies:** 1
- **Citations:** D-2, D-8, D-11, D-12 · REQ-A1.1, REQ-A1.4, REQ-D1.1,
  REQ-D1.6
- **Estimated effort:** 1 day

### Task 3 — Guard capped charge for exempt docs

- **Deliverables:** Aggregate enforcement (start-load and closure) charging
  permanently exempt docs at min(actual, per-file error threshold), applied
  only to an exempt doc that resolves and measures (a missing or
  unresolvable doc keeps the existing unmeasured/fail-loud path; a
  malformed `exempt|` entry forfeits the cap — fail-closed, per D-4);
  charged-vs-actual printed in `--audit` for capped docs; the spec-format
  exemption rationale in `config/instruction-budget-exemptions.txt`
  rewritten to state the capped-charge semantics, drop the superseded
  "dominant run-start load" claim, and refresh the stale trim-gap figures;
  a grep content-pin for the rewritten rationale in the test suite;
  fixture tests for the cap on both aggregates.
- **Done when:** Fixtures pass; the real-corpus audit shows the orchestrate
  closure and execute-task start-load charged with `spec-format.md` at its
  4,000 per-file error threshold while the larger actual count stays
  printed beside it; `mise run check` passes.
- **Dependencies:** 1
- **Citations:** D-4 · REQ-B1.1, REQ-B1.2, REQ-D1.5
- **Estimated effort:** half day

### Task 4 — Guard test-surface fixes

- **Deliverables:** The pending-diet allowance's Task field emitted in the
  audit shortlist and ranked report; the test suite's real-corpus
  offender-shortlist expectations derived from the suppression list instead
  of hardcoded file names (scoped to the present-offender assertions; the
  dieted-clean absent-checks remain an explicit, maintained name list); a
  fixture proving a Task retag is visible in output.
- **Done when:** A fixture allowance's Task retag changes the asserted
  output; adding a fixture exemption changes derived expectations without
  editing test name lists; `mise run check` passes.
- **Dependencies:** 2, 3
- **Citations:** D-8 · REQ-D1.2, REQ-D1.4
- **Estimated effort:** half day

### Task 5 — Guard reverse use-site check

- **Deliverables:** A per-skill check that every point-of-use manifest doc
  is named in body prose outside the manifest block and fenced code, at
  warning severity — matching each doc name as a fixed string over the
  charset-validated name (never a constructed pattern), reusing the
  existing per-skill parse pass (guard-performance invariant), and
  skipping a skill whose manifest failed to parse or resolve (its manifest
  error stands); fixtures for the missing case, the named case, the
  named-only-in-manifest-or-fenced-code case (still warns), and a
  `declared-exception|use-site:<skill>/<doc>` entry excusing a use-site
  warning and nothing else (REQ-D1.6); any misses the
  check surfaces in the existing corpus are either fixed in-body or
  recorded as `declared-exception|use-site:<skill>/<doc>|<reason>` entries
  (D-11).
- **Done when:** Fixtures pass; the real corpus runs warning-free or each
  remaining warning has a recorded declared-exception entry;
  `mise run check` passes.
- **Dependencies:** 2
- **Citations:** D-7, D-11 · REQ-D1.3
- **Estimated effort:** half day

### Task 6 — gate-wiring doctrine diet

- **Deliverables:** A diet of `doctrine/gate-wiring.md` shedding at least
  505 words (aim ~550), bringing it under its 2,500-word per-file warn and
  covering the self-review start-load's full shortfall without a Task 10
  body top-up (per the amended D-6 arithmetic); relieves the self-review
  and polish start-loads and the orchestrate and execute-task closures;
  law preserved verbatim in meaning.
- **Done when:** gate-wiring.md is below 2,500 words and at least 505
  words lighter than its pre-diet count; the content-pinned structural
  tests pass in the same PR; pinned lists and grepped phrases remain
  unbroken on one line; `mise run check` passes.
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
  same PR; pinned lists and grepped phrases remain unbroken on one line;
  execute-task's start-load margin meets its target under the Task 3 cap
  (the closure-margin target is verified at Task 11, kickoff §6);
  `mise run check` passes.
- **Dependencies:** 2, 3, 4
- **Citations:** D-6, D-10 · REQ-C1.1, REQ-C1.2
- **Estimated effort:** half day

### Task 8 — spec-kickoff body diet

- **Deliverables:** A ~500-word diet of `skills/spec-kickoff/SKILL.md` to
  at most 3,750 words; law preserved verbatim in meaning.
- **Done when:** The body is ≤3,750 words; the content-pinned structural
  tests pass in the same PR; pinned lists and grepped phrases remain
  unbroken on one line; no floor-breach warning names spec-kickoff's
  body; `mise run check` passes.
- **Dependencies:** 2, 3, 4
- **Citations:** D-6, D-10 · REQ-C1.1, REQ-C1.2
- **Estimated effort:** half day

### Task 9 — orchestrate body diet

- **Deliverables:** A ~450-word diet of `skills/orchestrate/SKILL.md` to at
  most 3,750 words; together with the Task 3 cap and Task 6 diet this sets
  up the orchestrate closure's 2,000-word restoration target (verified at
  Task 11, kickoff §6); law preserved verbatim in meaning.
- **Done when:** The body is ≤3,750 words; the content-pinned structural
  tests pass in the same PR; pinned lists and grepped phrases remain
  unbroken on one line; `mise run check` passes.
- **Dependencies:** 2, 3, 4
- **Citations:** D-6, D-10 · REQ-C1.1, REQ-C1.2
- **Estimated effort:** half day

### Task 10 — research-rigor reclassification in self-review and polish

- **Deliverables:** `research-rigor` moved run-start → point-of-use in the
  self-review and polish manifests (site: the finding-validation step where
  its triggers fire), with the doc named at that in-body step and a
  recorded safety-floor analysis (trigger-fired law, not permission-gating;
  execute-task precedent); if the start-load targets are not reached by
  the reclassification plus the Task 6 diet alone, a small body trim of
  the affected skill(s) in the same PR.
- **Done when:** Both manifests parse; the Task 5 use-site check passes for
  both skills; both start-loads meet the 1,000-word restoration target in
  the audit (with the Task 6 diet landed; a small body trim tops up if
  needed); `mise run check` passes.
- **Dependencies:** 2, 5, 6
- **Citations:** D-6 · REQ-C1.1, REQ-C1.3
- **Estimated effort:** half day

### Task 11 — Closing verification and guidance re-land

- **Deliverables:** A real-corpus verification that every budgeted surface
  has margin at or above its restoration target or carries a
  `declared-exception` entry (D-11), from the guard's margin report and
  below-target warnings in CI — including the closure-margin target
  assertions relocated from Tasks 7 and 9 (kickoff §6); the ~80-word
  `migrate-format-version.sh` guidance re-landed in
  `doctrine/spec-format.md`'s `## Versioning of this meta-spec` section;
  `--closeout` clean (no pending-diet allowance remains — kept as a cheap
  invariant assert against mid-campaign allowances).
- **Done when:** `check-instructions` exits zero on the real corpus with
  no unmeasured surfaces, no floor-breach warning, and no unexcepted
  below-target or use-site warning (the diets rewrite the very bodies the
  use-site check scans, so the closing gate re-checks it); the guidance
  is present in spec-format.md and the guard stays green;
  `check-instructions --closeout` exits zero; `mise run check` passes.
- **Dependencies:** 6, 7, 8, 9, 10
- **Citations:** D-3, D-9, D-11 · REQ-C1.1, REQ-C1.4
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

- **format-grammar's meta-spec wording.** The sibling spec spends the
  headroom this spec creates; its fragment 94f03e6c is deliberately not
  consumed here. Citations: D-4, requirements Out of scope.
- **Measurement-unit, prompt-eval-harness, or guard-architecture
  changes.** Words stay the unit; the guard stays plain POSIX shell with
  data-only inputs. Citations: requirements Out of scope.
- **Deferring gating law to hit a number.** The instruction-hygiene safety
  floor is inviolable in every reclassification (REQ-A1.3). Citations:
  requirements Out of scope.
- **Silent meaning changes during diets.** Law moves verbatim in meaning,
  never silently weakened (REQ-C1.2). Citations: requirements Out of
  scope.
