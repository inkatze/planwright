# Custom steps — Tasks

**Status:** Draft
**Last reviewed:** 2026-09-22
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order. The rule doc lands first so every mechanism
cites a stated contract; the resolver and the record helper land before
any skill is wired to them; the knob replacement lands with the resolver so
no commit on `main` reads a key that has no reader.

## Tasks

### Task 1 — The custom-steps rule doc

- **Deliverables:** `doctrine/custom-steps.md`: the point vocabulary (the
  seven wired points and the eight named, unwired ones), the moment each
  wired point fires per D-3, the step entry fields and their enums, the
  fixed context set and its two delivery channels, the three hosting modes
  and the dispatch-isolation default, the outcome set and the
  host-classification rule, the failure postures and the pause-protocol
  mapping, the missing-step matrix, the reserved controls and the
  no-recursion rule, and the record fields. The doctrine index row; the
  `customization-boundary` worked example reworded from the review-sequence
  knob to the convergence point's list; the `doctrine/gate-wiring.md`
  PR-body assembly gaining the per-point step tables inside the collapsed
  audit block.
- **Done when:** every rule REQ-A, REQ-B1.2, REQ-B1.4, REQ-C1.4, REQ-D, and
  REQ-E1.1 through REQ-E1.3 state appears in the named doc; `check:links`,
  `check:doctrine-index`, `lint:md`, and `check:instructions` pass with no
  new declared exception.
- **Dependencies:** none
- **Citations:** D-1, D-2, D-3, D-6, D-7, D-8, D-9, D-14, D-16, D-17 ·
  REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-D1.6, REQ-H1.5
- **Estimated effort:** 1 day

### Task 2 — The steps catalog and the resolver

- **Deliverables:** `config/steps.yaml`, the core seed carrying the `polish`
  and `self-review` entries as skill steps; `scripts/resolve-steps.sh
  <point> [--explain] [--check] [--attended|--unattended]`, which reads the
  point's list through `config-get`, the catalog through
  `resolve-catalog`, validates ids, fields, enums, targets, and `requires`
  per REQ-B and REQ-C, applies the missing-step matrix and prints the
  decision per step (`run`, `skip`, `park`, `ask`), prints the shadow
  warning, the stale `review_sequence` warning, and the unwired-point
  warning, refuses pipeline-entry targets and a first-position `continue`,
  and in check mode exits non-zero on any unresolvable step;
  `tests/test-resolve-steps.sh` covering each rule with layer fixtures.
- **Done when:** the default resolution of `convergence` prints the single
  `polish` step; every REQ-B and REQ-C rule has a passing fixture in the
  test, including the shadow warning, the matrix in both attendance modes,
  the stale-key warning at each layer, the by-layer malformed policy, the
  recursion refusal, and provenance output; `lint:shell` and
  `check:echo-safety` pass.
- **Dependencies:** 1
- **Citations:** D-4, D-5, D-6, D-10, D-17 · REQ-B1.1, REQ-B1.2, REQ-B1.3,
  REQ-B1.4, REQ-B1.5, REQ-B1.6, REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4,
  REQ-C1.5, REQ-C1.6, REQ-C1.7, REQ-C1.8, REQ-D1.8, REQ-D1.9, REQ-H1.3
- **Estimated effort:** 2 days

### Task 3 — Replace the review-sequence knob

- **Deliverables:** the `steps_<point>` keys REQ-B1.3 names in
  `config/defaults.yml` with the defaults it fixes, and `review_sequence`
  removed;
  `scripts/resolve-review-sequence.sh` and its test deleted; this
  repository's `.claude/planwright.yml` migrated to `steps_convergence`;
  every non-spec surface naming the old key updated (`docs/options-reference.md`
  rows, `docs/overlays.md` worked example B replaced by the steps example
  REQ-H1.2 describes, `docs/allocation.md`, `docs/fleet.md`,
  `docs/getting-started.md`, the allocation and knob-resolver script
  comments, the worker command guard's comment, the two skill bodies'
  references handled by Tasks 5 and 6).
- **Done when:** `check:options` passes with a row per new key; a grep for
  `review_sequence` over `scripts/`, `tests/`, `docs/`, `doctrine/`,
  `skills/`, `config/`, and `.claude/` returns only the stale-key warning
  site in the resolver; `mise run check` passes.
- **Dependencies:** 2
- **Citations:** D-10 · REQ-F1.1, REQ-F1.2, REQ-F1.3, REQ-F1.4, REQ-F1.5,
  REQ-H1.1, REQ-H1.2
- **Estimated effort:** 1 day

### Task 4 — Step records and the PR-body fold

- **Deliverables:** `scripts/step-record.sh` with `write`, `list`, and
  `render` verbs over the worktree cache directory, the record fields
  REQ-D1.5 names, the per-point table renderer the PR-body assembly
  consumes, and a `regenerate` verb that re-emits the audit record and
  pending-sign-off checklist from a base and head; `tests/test-step-record.sh`.
- **Done when:** a written record round-trips through `list` and `render`;
  the rendered table carries every field; `regenerate` over a fixture range
  reproduces the checklist the gate-wiring format defines; a record with a
  skip reason renders as skipped; `lint:shell` and `check:echo-safety`
  pass.
- **Dependencies:** 1
- **Citations:** D-12, D-16 · REQ-D1.5, REQ-E1.2, REQ-H1.3
- **Estimated effort:** 1 day

### Task 5 — Wire the unit points into /execute-task

- **Deliverables:** `/execute-task` invokes the resolver and runs the
  resolved steps at each in-run point per D-3, with the convergence
  section's review-sequence prose replaced by the point call (the
  compensating trim), the hosting modes realized through the per-step
  session launch and the recorded session id, the outcome classification
  and posture handling per REQ-D1.1 and REQ-D1.2, the timeout rule, the
  post-pr regeneration and draft verification, and the manifest line
  loading the rule doc at point of use; the dispatch brief guidance in
  `/orchestrate`'s dispatch prose cites the keys per REQ-E1.4 where it names
  the review sequence today.
- **Done when:** with the shipped defaults a unit runs exactly today's
  single polish convergence; with a fixture overlay declaring a command
  step at each in-run point, the step records show every such point fired
  once in order with the fixed context present in the command's
  environment; a
  `continue` step on the terminal rung records `failed`; a post-pr command
  step that pushes triggers the regeneration and the draft check;
  `check:instructions` passes with `/execute-task`'s margin at or above
  its declared figure; `check:doctrine-manifest` passes.
- **Dependencies:** 2, 3, 4
- **Citations:** D-3, D-7, D-8, D-9, D-12, D-14 · REQ-A1.1, REQ-A1.4,
  REQ-A1.5, REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-D1.7, REQ-E1.1,
  REQ-E1.2, REQ-E1.4, REQ-G1.1, REQ-H1.4, REQ-H1.5
- **Estimated effort:** 2 days

### Task 6 — Wire the spec-PR flip point into /spec-kickoff

- **Deliverables:** `/spec-kickoff` runs `steps_pre_spec_ready_flip`
  through the resolver after its push and PR step and before the terminal
  CI gate, refusing the flip on a halted or failed step and recording the
  pending flip to Awaiting input as the gate already does; a compensating
  trim in the same change.
- **Done when:** with the default empty list the kickoff flow is unchanged;
  with a fixture overlay declaring a failing command step the flip is
  refused and the Awaiting-input entry names the step; the existing kickoff
  ready-flip test passes; `check:instructions` passes with `/spec-kickoff`'s
  per-file and closure margins at or above their declared figures.
- **Dependencies:** 2, 3, 4
- **Citations:** D-3, D-9, D-13 · REQ-A1.2, REQ-E1.3, REQ-H1.4
- **Estimated effort:** half day

### Task 7 — The worker guard approves declared command targets

- **Deliverables:** `scripts/worker-command-guard.sh` resolves the declared
  command steps for the wired points at hook time and approves a command
  whose first token equals a resolved target after its charset and
  containment checks, allow-only; fixture rows in the permission-matcher
  test for an approved declared target, a non-declared command, and a
  hostile target that fails containment; `docs/overlays.md` section 9
  documents the manual allow entry as the degraded-path fallback and
  states that a worker cannot write catalogs or lists.
- **Done when:** the three fixture rows pass; a declared target with a
  traversal segment is not approved; `check:guard-wiring` and
  `check:hook-contracts` pass.
- **Dependencies:** 2
- **Citations:** D-11 · REQ-G1.2, REQ-G1.3, REQ-G1.4
- **Estimated effort:** 1 day

### Task 8 — The check:steps guard

- **Deliverables:** a `check:steps` task in `mise.toml`, wired into
  `check`, that runs the resolver in check mode for every wired point
  against this repository's own configuration; a fixture showing it fails
  on an unresolvable step.
- **Done when:** `mise run check` runs the guard and passes on the migrated
  configuration; the failing fixture exits non-zero naming the step.
- **Dependencies:** 2, 3
- **Citations:** D-9 · REQ-H1.4
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

- **Orchestrator-side and pipeline-side points.** `spec-drafted`,
  `kickoff-signed-off`, `unit-selected`, `pre-dispatch`, `post-dispatch`,
  `unit-halted`, `post-merge`, and `orchestrator-idle` are named in the rule
  doc and not wired; `/orchestrate`'s instruction closure has no headroom
  and no seed records a need at those points. Confidence: high.
  **Gate:** a recorded observation naming a step an operator needed at one
  of these points, or the `/orchestrate` diet landing (surfaced free-text
  condition, evaluated at drain).
  Citations: D-2 · issue 383 (Sources).
- **Per-spec and per-task-type lists.** The overlay layers give per-user
  and per-project granularity; a per-spec map has a precedent
  (`dispatch_backend_per_spec`) and a per-task-type key would need a
  classification the format lacks. Confidence: medium.
  **Gate:** a recorded observation from a run where one spec needed a
  different chain than its siblings (surfaced free-text condition,
  evaluated at drain).
  Citations: D-4, D-5 · the review-gauntlet seed (Sources).
- **Parallel steps within a point.** Serial order is what `continue`
  hosting and the commit discipline assume. Confidence: medium.
  **Gate:** a recorded observation where two independent steps at one point
  dominated a unit's wall clock (surfaced free-text condition, evaluated at
  drain).
  Citations: D-18.

## Out of scope

- The ready-flip authorization policy (issue 379) and merge; this bundle
  provides the pre-ready-flip point and performs no flip.
- Plugin wrappers for external review tools; the operator's commands are
  named from an overlay.
- Machine-local configuration reaching worktrees; owned by
  customization-overlay.
- Re-running earlier points after a post-pr step moves the head; unit
  sizing and sync frugality are recorded in obs:36916a48 for a bundle that
  owns those rules.
