# Format grammar & parser unification — Tasks

**Status:** Draft
**Last reviewed:** 2026-07-16
**Format-version:** 2
**Execution:** derived — see the status render

Blocks are listed in dependency order. Task 5 (the doctrine amendments) is
parked in `## Awaiting input` on the instruction-headroom condition
(REQ-G1.1, D-16); Task 6 and Task 8 sit behind it via dependency edges.

## Tasks

### Task 1 — Founding shared spec-parse lib + extract_tasks re-point

- **Deliverables:** A sourceable POSIX-sh library in `scripts/` (working
  name `spec-parse.sh`) exposing a stream-emitting canonical `tasks.md`
  definition extraction; `scripts/spec-anchor.sh`,
  `scripts/migrate-format-version.sh`, and the migration test oracle
  re-pointed to it; unit tests for the lib; an anchor-stability proof
  (recomputed anchors for every in-repo bundle, byte-identical before and
  after).
- **Done when:** All three former copies source the lib and their own test
  suites pass; `scripts/spec-anchor.sh` output is unchanged for every
  bundle under `specs/` (a one-shot landing proof; the standing suite keeps
  the fixture-corpus tests); shell lint and the full test suite pass.
- **Dependencies:** none
- **Citations:** D-3, D-4 · REQ-B1.1, REQ-B1.2, REQ-B1.6
- **Estimated effort:** 2 days

### Task 2 — Parked-map and Format-version parses into the lib; v2 posture alignment

- **Deliverables:** The header-block-scoped `Format-version:` parse and the
  parked-map/reference-bullet parse added to the lib (duplicate in-header
  declaration fails closed); `orchestrate-select.sh`, `drain-gates.sh`,
  `spec-status.sh`, `spec-validate.sh` re-pointed for the parked-map parse
  and all eight version-parse consumers (`spec-status.sh`, the
  `tasks-pr-sync` hook, `check-ledger.sh`, `spec-validate.sh`,
  `orchestrate-select.sh`, `drain-gates.sh`, `migrate-format-version.sh`,
  `spec-graph.sh`) for the version parse per REQ-B1.3; the single posture
  (fence guard citing this bundle's D-5 until the Task 5 amendment lands,
  CRLF trim, `**Task <token>**` discrimination, prose-bullet tolerance)
  applied uniformly, fixing `spec-status.sh`'s
  Awaiting-input-cannot-block-Done defect on CRLF checkouts.
- **Done when:** All four v2 parsers produce identical parked-map
  classifications over a shared fixture corpus (fence, CRLF, prose-bullet,
  and whitespace-token cases); a body-line `Format-version:` literal no
  longer masks a missing header declaration; duplicate-declaration fixtures
  fail closed in every consumer; a grep sweep finds no remaining private
  version-parse copy; full test suite passes.
- **Dependencies:** 1
- **Citations:** D-6, D-7, D-8 · REQ-B1.3, REQ-B1.4, REQ-B1.6, REQ-C1.1,
  REQ-C1.3, REQ-D1.9
- **Estimated effort:** 2 days

### Task 3 — Doctrine-grounded validator hardening

- **Deliverables:** New `spec-validate.sh` rules with per-rule fixtures:
  cited-but-empty REQ bullets; malformed decision shapes (H2 `D-<n>`
  headings, period-labelled fields); non-canonical `### Task` heading
  forms; out-of-range unqualified `D-<n>`/`REQ-<id>` token warnings; v2
  Awaiting-input section purity; the changed-REQ/unchanged-test-spec
  baseline warning; the duplicate in-header `Format-version:` error at
  every status (REQ-D1.9's validator half, grounded in the
  already-normative unparseable-declaration rule — the lib parse it
  consumes lands in Task 2). Each rule verified against every in-repo
  bundle per the D-9 rollout contract (violations fixed in-task, riding
  the expression-only self-re-anchor ritual on signed bundles; release
  notes updated).
- **Done when:** Every new rule has trip and pass fixtures; all in-repo
  bundles validate with no new findings (or carry in-task fixes); full test
  suite passes.
- **Dependencies:** 2
- **Citations:** D-9, D-13, D-14 · REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.5,
  REQ-D1.7, REQ-D1.8, REQ-D1.9, REQ-D1.10
- **Estimated effort:** 2 days

### Task 4 — Gate and drain script reconciliation

- **Deliverables:** `ready` added to both of `drain-gates.sh`'s
  stored-status whitelists — the shell `case` list and the awk `VALID`
  map — (citing the meta-spec's six-status table per D-10); the drain
  report's free-text-form hint on a `GATE(when:)` condition matching no
  recognized atom (hint output echo-safety-sanitized);
  `orchestrate-meta-select.sh` unexpected-selector-exit and
  unparseable-output fail-closed handling; the invariant-tasks
  expression-only amendment — the Deferred entry rewritten to the
  free-text-gate form AND the REQ-C1.5 severity phrasing clarification
  (REQ-A1.9) — as one dated changelog entry plus one marked
  self-re-anchor entry; the `/drain` per-spec `[manual]` test-spec
  inventory.
- **Done when:** A sweep over a stored-Ready fixture emits no
  unrecognized-status note; the invariant-tasks entry no longer reports
  MALFORMED on a real sweep; the rewritten gate evaluates to the same
  verdict as before the rewrite; the marked self-re-anchor entry is
  present and parses as execution-valid; a crashing selector fixture fails
  closed; the drain output lists `[manual]` entries per live spec; full
  test suite passes.
- **Dependencies:** none
- **Citations:** D-10, D-15 · REQ-A1.9, REQ-E1.1, REQ-E1.2, REQ-E1.3,
  REQ-E1.5, REQ-E1.6
- **Estimated effort:** 1.5 days

### Task 5 — The doctrine amendments (budget-gated)

- **Deliverables:** The meaning-class `doctrine/spec-format.md` amendment:
  the normative fence/illustration grammar including the unclosed-fence
  disposition (REQ-A1.1), the duplicate-`Format-version:` rule, the
  header-block extent definition, the `## Tasks` ordering reword, the
  superseded/retired task-block home plus the changelog-named retirement
  escape and test-spec tombstone handling, the test-spec H2 grouping
  requirement, the completed-semantics asymmetry sentence (with the
  accepted concurrent-disagreement consequence), and the D-13 kickoff
  lens-checklist item for qualified cross-spec citations. The
  `doctrine/accumulator-taxonomy.md` delta: `ready` in the status-atom
  grammar, the normative free-text-gate form, the multi-read/digest-bracket
  correction, the unresolved lane annotation. Fence-provenance citations in
  the Task 2/6 parsers flipped from this bundle's D-5 to the landed
  meta-spec rule.
- **Done when:** `scripts/check-instructions.sh` passes with the amendments
  applied (the REQ-G1.1 unpark condition); `mise run check` doc gates pass;
  the amendment text cites the shipped parser behavior it ratifies; each
  deliverable named above is present in the amended text (completeness
  checklist reviewed at PR).
- **Dependencies:** none
- **Citations:** D-1, D-5, D-6, D-7, D-10, D-11, D-12, D-13 · REQ-A1.1,
  REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-A1.6, REQ-A1.7, REQ-A1.8,
  REQ-A1.10, REQ-D1.4, REQ-E1.1, REQ-E1.2, REQ-E1.4, REQ-G1.1
- **Estimated effort:** 2 days

### Task 6 — Grammar-keyed parser and validator landing

- **Deliverables:** v1 fence-awareness in lockstep with the landed
  amendment: `spec-validate.sh` and `spec-anchor.sh`'s canonical extraction
  consume the lib's fence-aware lexer; the unbalanced-fence validator flag
  (REQ-D1.11); the changelog-named task-retirement escape in the stable-ID
  check (changelog-extracted ids grammar-validated); an expression-only
  re-anchor sweep over any bundle whose anchor moves (REQ-C1.4).
- **Done when:** A fenced column-0 mock heading/bullet fixture produces no
  false duplicate-REQ error and no phantom task block in the anchor
  extraction; a synthetic trip fixture (a bundle with fenced task-shaped
  lines) proves anchor movement produces the paired re-anchor entry; an
  unclosed-fence fixture is flagged; a retirement fixture with a dated
  changelog entry passes while an unnamed removal still errors; recomputed
  anchors for EVERY bundle under `specs/` are each either unchanged or
  carrying a re-anchor entry, with the sweep failing closed on any
  anchor-tool error; the migration suite (whose oracle consumes the same
  now-fence-aware extraction) passes; full test suite passes.
- **Dependencies:** 2, 5
- **Citations:** D-5, D-9, D-12 · REQ-C1.2, REQ-C1.4, REQ-D1.6, REQ-D1.11
- **Estimated effort:** 2 days

### Task 7 — Kickoff verification homes

- **Deliverables:** Fixture tests and this bundle's test-spec entries for
  the three thin `/spec-kickoff` behaviors: pre-flight amendment-mode
  routing (fixture where scriptable, otherwise a documented manual
  scenario), expression-only anchor-entry production (the fixture captures
  a real skill-produced entry — e.g. the one Task 4 writes into
  invariant-tasks — and asserts it parses as execution-valid, rather than
  a hand-authored golden), and gap-check degradation with the
  decision-domains catalog absent (the script half is the fixture; the
  skill's proceed decision is the manual half).
- **Done when:** Each behavior has a named verification home that runs (or
  a documented manual scenario with its exercise steps); full test suite
  passes.
- **Dependencies:** none
- **Citations:** D-17 · REQ-F1.1, REQ-F1.2, REQ-F1.3
- **Estimated effort:** 1 day

### Task 8 — Line-80 grammar migration onto the lib

- **Deliverables:** `spec-validate.sh`'s parse_requirements / parse_design /
  parse_tasks, `orchestrate-select.sh`'s task/deps/effort awk, and
  `spec-model.sh`'s bundle-reader grammar re-pointed to the lib's REQ
  bullet, D-heading, task-heading, and `Dependencies:`/`Citations:` token
  parsing; the back-reference comments replaced by source lines.
- **Done when:** No consumer retains a private copy of a grammar the lib
  implements (grep-verifiable); validator, selector, and model outputs are
  unchanged over the fixture corpus and all in-repo bundles (a one-shot
  landing proof; the standing suite keeps the fixture-corpus tests);
  recomputed anchors for every bundle under `specs/` are unchanged; full
  test suite passes.
- **Dependencies:** 6
- **Citations:** D-4 · REQ-B1.5, REQ-B1.6
- **Estimated effort:** 3 days

## Awaiting input

- **Task 5** Blocked on instruction-headroom relief: the orchestrate
  reachable-closure budget stands at 19,997/20,000 words and
  `doctrine/spec-format.md` plus `doctrine/accumulator-taxonomy.md` growth
  fails `scripts/check-instructions.sh` today. Unpark when the sibling
  instruction-headroom work lands enough relief that the closure check
  passes with this task's amendments applied (REQ-G1.1, D-16).

## Deferred

- (none yet)

## Out of scope

- The `/spec-walkthrough` scope grammar unification (legacy line 96):
  comprehension-domain selector language, not spec-format grammar; left in
  the frozen log for a later vehicle (D-4).
- Instruction-budget relief mechanisms: owned by the sibling
  instruction-headroom spec (REQ-G1.1 gates on it, never delivers it).
- A semantic cross-spec citation index (D-13: lens item instead).
- v1-bundle migration to v2, derivation-engine semantics changes, and gate
  *evaluation* semantics beyond the grammar additions (requirements Out of
  scope).
