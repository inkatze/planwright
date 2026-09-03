# Prose disposition — Tasks

**Status:** Draft
**Last reviewed:** 2026-09-03
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order. The ordering is the bundle's load-bearing claim
(D-13): no cleanup task is dispatchable before the doctrine amendments and
the skill instantiation have merged, and the guard exists before the first
cleanup PR so the cleanup can be measured by it.

## Tasks

### Task 1 — Doctrine amendments: lens defect class, prose classification, batching

- **Deliverables:** the Documentation lens in `doctrine/discovery-rigor.md`
  scoped to its three defect classes, with the defect class carried in the
  coverage row's Notes cell so the canonical table keeps its columns;
  the cross-set improvable-is-not-a-finding sentence in
  `doctrine/artifact-lenses.md`; the prose classification, grounding,
  external-contract definition, and PR-introduced-surface rule in
  `doctrine/finding-categorization.md`; the batching rule, manifest form,
  batched checklist rendering, and per-finding audit rows in
  `doctrine/gate-wiring.md`, with its example updated and a diet applied to
  keep the doc under its warn threshold.
- **Done when:** each rule REQ-A, REQ-B, and REQ-C states appears in the
  named doc; the four routing scenarios in `test-spec.md` (REQ-B1.2,
  REQ-B1.4, REQ-B1.5, REQ-C1.1) walk against the amended text and reach
  the stated disposition; `check:links`, `check:doctrine-index`, and
  `check:instructions` pass with no new `raise` entry and no floor-breach
  warning.
- **Dependencies:** none
- **Citations:** D-2, D-3, D-4, D-5 · REQ-A1.1, REQ-A1.2, REQ-A1.3,
  REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5, REQ-C1.1, REQ-C1.2,
  REQ-C1.3, REQ-C1.4, REQ-D1.3
- **Estimated effort:** 1 day

### Task 2 — Skill instantiation and straggler sweep

- **Deliverables:** `skills/self-review/SKILL.md`, `skills/polish/SKILL.md`,
  and the convergence prose of `skills/execute-task/SKILL.md` citing the
  amended sections for lens scoping, prose classification, the
  PR-introduced-surface rule, and the batched commit discipline; a
  surface-pattern sweep over `skills/`, `doctrine/`, and `docs/` for the
  superseded wording, with every straggler fixed in the same change and the
  patterns searched listed in the PR body.
- **Done when:** a repository grep for the superseded one-commit-per-finding
  phrasing and the unscoped Documentation lens phrasing returns hits only in
  spec changelogs and observation fragments; each of the three skills names
  the governing section rather than restating it; `check:instructions`
  passes with no new `raise` entry.
- **Dependencies:** 1
- **Citations:** D-6 · REQ-D1.1, REQ-D1.2, REQ-D1.3
- **Estimated effort:** half day

### Task 3 — The comment-hygiene rule doc

- **Deliverables:** `doctrine/comment-hygiene.md` stating what a comment is
  for, the no-provenance rule with the replacement link (commit trailer and
  bundle deliverables) and the deliverables-gap rule, the five-reason
  disposition taxonomy with each reason's destination, and the comment-block
  budget model; its row in `doctrine/README.md`.
- **Done when:** the doc states all five things REQ-E names; the index row
  exists and `check:doctrine-index` passes; `check:links` and
  `check:instructions` pass; the doc is in no skill's manifest and states
  that it is the guard's normative home.
- **Dependencies:** none
- **Citations:** D-7, D-8, D-9, D-14 · REQ-E1.1, REQ-E1.2, REQ-E1.3,
  REQ-E1.4, REQ-E1.5
- **Estimated effort:** half day

### Task 4 — The comment-block budget guard

- **Deliverables:** `scripts/check-comment-budget.sh` with the largest-block
  measurement, the warn and error comparison, the `--audit` inventory with
  its per-block evidence classification, the `--code-invariant <ref>` mode,
  and the `--closeout` flag; the
  `comment_block_warn` and `comment_block_error` knobs in
  `config/defaults.yml` with their options-reference rows;
  `config/comment-budget-exemptions.txt` with the two suppression forms
  documented in its header and the generated `pending-cleanup` baseline
  naming Tasks 5 through 8; the `check:comment-budget` task inside
  `mise run check`; a staged-path-scoped pre-commit job in `lefthook.yml`;
  tests under `tests/` covering REQ-F1.9's list; a guard header that cites
  the rule doc and fits the budget it enforces.
- **Done when:** the tests pass; `mise run check` is green with the baseline
  in place; `--audit` run against the `v0.36.0` tree reproduces the
  headline figures in Sources; `--code-invariant` fails on a
  fixture with a changed code line and passes on a comment-only change;
  `check:options` passes with the new rows; the guard's own largest block is
  under the error threshold.
- **Dependencies:** 3
- **Citations:** D-9, D-10, D-11, D-12 · REQ-F1.1, REQ-F1.2, REQ-F1.3,
  REQ-F1.4, REQ-F1.5, REQ-F1.6, REQ-F1.7, REQ-F1.8, REQ-F1.9, REQ-F1.10,
  REQ-E1.4
- **Estimated effort:** 2 days

### Task 5 — Cleanup Phase A: evidence-free blocks

- **Deliverables:** every evidence-free block across the guard's surface
  dispositioned under the taxonomy (deleted where the code carries the
  information, kept beside the code where it names a why or a warning);
  `pending-cleanup` entries removed for every file that no longer trips the
  error threshold; the PR body carrying the `--audit` figures before and
  after, the evidence-free count remaining, and the `--code-invariant`
  result.
- **Done when:** `--code-invariant` against the PR base passes for every
  touched file; `lint:shell` and `lint:fmt` pass; the PR body carries both
  audit figures; no surviving evidence-free block restates code or narrates
  structure, spot-checked by the independent reading pass on a sample the
  PR names.
- **Dependencies:** 2, 4
- **Citations:** D-8, D-12, D-13 · REQ-G1.1, REQ-G1.2, REQ-G1.4
- **Estimated effort:** 2 days

### Task 6 — Cleanup Phase B: the fleet family

- **Deliverables:** every block at or above the error threshold in the
  `scripts/fleet-*.sh` family read and dispositioned block by block under
  the taxonomy; provenance removed; cross-file protocol text (liveness store
  precedence, presence, fence semantics, usage gating, stream-json
  contracts) relocated to its owning doctrine doc or a `docs/design/` page
  with a pointer; own-surface usage sections kept bounded or given an
  `exempt` entry with its reason; the family's `pending-cleanup` entries
  removed; the deliverables gap closed for the family's scripts named in
  Sources as reachable through neither trailer nor deliverables, via
  expression-only amendments to their owning bundles; the independent
  verification record in the PR body.
- **Done when:** `--code-invariant` passes; every surviving block in the
  family names its taxonomy reason in the verification record; every removed
  line is confirmed recoverable by the independent pass, with disagreements
  dispositioned in the PR; each owning bundle amended carries its changelog
  entry and self-re-anchor and `check:anchor-freshness` passes; no
  `pending-cleanup` entry for the family remains.
- **Dependencies:** 5
- **Citations:** D-8, D-12, D-13, D-14 · REQ-G1.3, REQ-G1.4, REQ-G1.5,
  REQ-G1.6
- **Estimated effort:** 3 days

### Task 7 — Cleanup Phase B: orchestration, allocation, spec, and release families

- **Deliverables:** the same disposition, relocation, provenance removal,
  exemption, deliverables-gap closure, and verification record as Task 6,
  over `scripts/orchestrate-*.sh`, `scripts/allocation-*.sh`,
  `scripts/spec-*.sh`, `scripts/release-*.sh`, `scripts/tasks-pr-sync.sh`,
  `scripts/main-currency.sh`, `scripts/converge-sync-main.sh`,
  `scripts/dispatch-fetch.sh`, and `scripts/offload-dispatch.sh`.
- **Done when:** the Task 6 conditions hold for this family.
- **Dependencies:** 5
- **Citations:** D-8, D-12, D-13, D-14 · REQ-G1.3, REQ-G1.4, REQ-G1.5,
  REQ-G1.6
- **Estimated effort:** 3 days

### Task 8 — Cleanup Phase B: guards, resolvers, and the remaining surfaces

- **Deliverables:** the same disposition, relocation, provenance removal,
  exemption, deliverables-gap closure, and verification record as Task 6,
  over the `scripts/check-*.sh` and `scripts/resolve-*.sh` families, every
  remaining script, `tests/`, `githooks/`, `hooks/`, and the `config/` YAML
  files (the `defaults.yml` per-knob paragraphs collapse to what the options
  reference does not already carry).
- **Done when:** the Task 6 conditions hold for this surface, and the
  options reference remains the single documented home of every knob
  (`check:options` passes).
- **Dependencies:** 5
- **Citations:** D-8, D-10, D-12, D-13, D-14 · REQ-G1.3, REQ-G1.4, REQ-G1.5,
  REQ-G1.6
- **Estimated effort:** 2 days

### Task 9 — Closeout

- **Deliverables:** `--closeout` passed by planwright's `check:comment-budget`
  task; the exemptions file reviewed so every remaining `exempt` entry
  carries a standing reason; the final `--audit` figures recorded beside the
  2026-09-03 baseline in the PR body; a completeness check that every
  script in Sources' 28-script list is now named in an owning bundle's
  deliverables.
- **Done when:** `mise run check` passes with `--closeout` and zero
  `pending-cleanup` entries; the final and baseline figures are both in the
  PR body; the 28-script list is empty when recomputed.
- **Dependencies:** 6, 7, 8
- **Citations:** D-11, D-12, D-13 · REQ-G1.7, REQ-F1.7
- **Estimated effort:** half day

## Awaiting input

- (none yet)

## Deferred

- **Adopter guard-catalog enrollment.** The comment-block budget is a
  general capability, but its thresholds are one repo's values and no
  adopter has asked for it yet; the customization boundary tilts an unproven
  preference to stay local until evidence shows it generalizes.
  Confidence: medium.
  **Gate:** a recorded observation from a second repository or overlay
  context wanting the comment budget (surfaced free-text condition,
  evaluated at drain).
  Citations: D-9 · customization-boundary (Sources).
- **Word-based block measurement.** Lines are what the operator measured and
  the visible shape of a block; a reflowed block evading the line threshold
  is possible but unobserved. Confidence: medium.
  **Gate:** an `--audit` run shows a block whose words-per-line stands out
  as a reflow of a previously flagged block (surfaced free-text condition,
  evaluated at drain).
  Citations: D-9.

## Out of scope

- The sign-off marker's carrier and the merge-as-approval semantics
  (planwright issue #384); this bundle names the marker abstractly and
  records the sequencing risk in D-5.
- Lifecycle hooks (planwright issue #383) and checklist-regeneration
  ownership under a bare nested polish (obs:ff5ca260).
- Prose inside spec bundles and doctrine bodies as a budgeted surface
  (instruction-hygiene's and the anchor machinery's concern).
- JSON `_about` strings, the skill restatement detector, and the
  directive-density metric (obs:b75dc6d2, obs:ff8f7659, obs:79a5adbc).
- A fifth finding bucket.
- The operator's personal copies of the rigor sections outside this
  repository.
