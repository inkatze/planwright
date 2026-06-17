# Spec Comprehension Walkthrough — Tasks

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

The `Dependencies:` lines below are the authoritative graph. Derived build-order
note (regenerate if dependencies change): the independence core is the MVP
slice — Task 1 → Task 2 → Task 3 → {Task 4, Task 5} → Task 6 produces the first
usable walkthrough (one-pager plus teach-back in a self-contained HTML
artifact). Tasks 4 and 5 parallelize off Task 3. The effort-weighted critical
path runs Task 1 → Task 2 → Task 3 → Task 5 → Task 6 → Task 7 → Task 11
(≈12.5 days), through Task 5 (the heavier of Task 6's two predecessors), out to
the heaviest post-core view (Task 7), and on to the tests/coverage gate
(Task 11) that depends on it. The dependency-graph, decision-map, and partial-scope
views (Tasks 7, 8, 9) and the sibling touchpoints (Task 10) layer on after the
core ships; the tests/coverage gate (Task 11) and docs (Task 12) depend on the
view tasks they cover.

## Forward plan

### Task 1 — Command scaffold

- **Deliverables:** the `/spec-walkthrough` skill entry point; argument and flag
  parsing (spec path, scope selector, reveal flag); spec-identifier charset
  validation and path containment check; read-only and status-agnostic bundle
  loading; graceful degradation on a missing, malformed, or partial bundle.
- **Done when:** invoking the command on a valid bundle path loads it in any
  status without writing anything; a hostile or malformed path is refused
  cleanly; a missing or partial bundle yields a clear message naming what is
  absent.
- **Dependencies:** none
- **Citations:** D-1, D-10 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-A1.6, REQ-B1.4
- **Estimated effort:** 1 day

### Task 2 — Bundle reader model

- **Deliverables:** a parser that reads the four files into a normalized
  in-memory model preserving every identifier as a hidden back-pointer (the
  substrate every view renders from), reusing the existing format parsers where
  practical; the task-graph edges and the decision and requirement records
  exposed to downstream views.
- **Done when:** the model round-trips a real bundle (bootstrap or
  customization-overlay) with every REQ, decision, task, and dependency edge
  reachable and each carrying its source identifier as a back-pointer.
- **Dependencies:** 1
- **Citations:** D-2 · REQ-C1.1, REQ-D1.3, REQ-B1.2
- **Estimated effort:** 2 days

### Task 3 — Plain-language translation layer

- **Deliverables:** the lossless layered-view translator (plain rendering with
  retained back-pointers), the precision-preservation guardrail that never
  softens a normative token, and the reveal mapping that exposes identifiers and
  restores softened tokens on demand.
- **Done when:** a bundle renders to plain audience-neutral text with no
  internal vocabulary by default; every normative token (MUST/SHALL/SHALL NOT,
  thresholds, enumerated states) survives verbatim; the reveal mapping resolves
  each plain sentence back to its source element.
- **Dependencies:** 2
- **Citations:** D-2 · REQ-C1.1, REQ-C1.7, REQ-D1.3
- **Estimated effort:** 2 days

### Task 4 — Spec-at-a-glance one-pager renderer

- **Deliverables:** the narrative one-pager view (prose, length-bounded), each
  load-bearing claim carrying its back-pointer, with the load-bearing "killer
  items" foregrounded.
- **Done when:** the one-pager renders a real bundle as bounded narrative prose
  in which every claim resolves to a source element and the killer items are
  visually distinct from routine content.
- **Dependencies:** 3
- **Citations:** D-2 · REQ-C1.2
- **Estimated effort:** 1 day

### Task 5 — Teach-back challenge

- **Deliverables:** claim extraction from the bundle's own assertions; the
  in-artifact agree / disagree / unsure self-paced checklist; the optional
  in-session walk through the same claims; response recording that never
  supplies the answer and surfaces restatement divergences for the human to
  adjudicate.
- **Done when:** the teach-back presents the spec's claims section by section,
  records the human's own responses, supplies no verdict, and the in-artifact
  and in-session paths cover the same claim set.
- **Dependencies:** 3
- **Citations:** D-3, D-9 · REQ-C1.5, REQ-D1.1, REQ-D1.4
- **Estimated effort:** 1.5 days

### Task 6 — HTML assembly and styling

- **Deliverables:** assembly of the rendered views into one self-contained HTML
  artifact; MIT-licensed styling (Tailwind CSS plus DaisyUI) with only used CSS
  inlined and the MIT notice included; the reveal toggle; the silent-read-first
  ordering; the gitignored `.claude/walkthroughs/<spec>/` location with a
  `.gitignore` entry; the bundle-and-commit provenance stamp; HTML/SVG-escaping
  (or sanitization) of all rendered bundle content so no bundle text can inject
  executable or structural markup into the artifact.
- **Done when:** running the command produces one HTML file that opens offline
  in a browser with no installed dependency, defaults to the no-identifier view
  with a working reveal toggle, presents the full read before any prompt, is
  gitignored, is stamped with the bundle and commit, and escapes/sanitizes all
  rendered bundle content (markup in bundle text displays as literal, never
  executes).
- **Dependencies:** 4, 5
- **Citations:** D-3, D-4, D-7, D-8 · REQ-C1.6, REQ-D1.2, REQ-D1.3, REQ-E1.1, REQ-E1.2, REQ-E1.4, REQ-E1.5, REQ-E1.6, REQ-E1.7
- **Estimated effort:** 2 days

### Task 7 — Dependency-graph and critical-path view

- **Deliverables:** the drawn dependency-graph view as inline SVG with the
  critical path and parallelism visible and plain labels, reusing
  `scripts/orchestrate-select.sh`'s critical-path computation; the optional
  Graphviz enhancement via runtime probe with clean degradation and an
  in-artifact note; the diagram integrated with its explaining text.
- **Done when:** the graph renders as inline SVG (not ASCII) with the critical
  path highlighted, matches the reused critical-path computation, renders the
  same offline whether or not Graphviz is present, and sits adjacent to its
  explaining text.
- **Dependencies:** 2, 6
- **Citations:** D-4, D-5, D-6 · REQ-C1.3, REQ-C1.6, REQ-E1.3
- **Estimated effort:** 2 days

### Task 8 — Decision-map view

- **Deliverables:** the ADR-shaped decision-map view rendering each decision as
  Context → Decision → Alternative-rejected → Consequence in plain language,
  surfacing the rejected alternative and the cost.
- **Done when:** every decision in a real bundle renders in the four-beat shape
  with the rejected alternative and consequence present, in plain language by
  default.
- **Dependencies:** 3, 6
- **Citations:** D-2 · REQ-C1.4
- **Estimated effort:** 1 day

### Task 9 — Scope selection and stage-aware framing

- **Deliverables:** the whole-bundle default plus partial selectors (one file,
  one requirement group, the decision set, the task graph, a single decision's
  blast radius); status-auto-detected framing for Draft, Active, Done, and
  terminal statuses.
- **Done when:** each partial selector renders only its scope; a single
  decision's view shows its blast radius; and the framing changes with the
  bundle's status without the human specifying it.
- **Dependencies:** 2, 6
- **Citations:** D-11 · REQ-B1.1, REQ-B1.2, REQ-B1.3
- **Estimated effort:** 1.5 days

### Task 10 — Sibling discoverability touchpoints

- **Deliverables:** suggest-only lines added to `/spec-draft`'s handoff,
  `/spec-kickoff`'s pre-flight, and `/resume`, each recommending
  `/spec-walkthrough` as an independent human step, none auto-invoking it.
- **Done when:** the three sibling skills each surface the recommendation in the
  right place, none invokes the command, and the wording frames it as an
  optional independent pass.
- **Dependencies:** 6
- **Citations:** D-11 · REQ-F1.1, REQ-F1.2
- **Estimated effort:** half day

### Task 11 — Tests and test-spec coverage

- **Deliverables:** automated fixtures across the views (model, translation,
  one-pager, teach-back, graph, decision-map, scope); an offline
  self-containment check (the artifact opens with no network and no installed
  dependency); a data-hygiene check; a content-escaping / injection-safety check
  (a markup-bearing fixture renders escaped, never executable); CI wiring under
  `mise run check`.
- **Done when:** the fixtures run green in CI, the self-containment and
  data-hygiene checks pass, and every REQ with a `[test]` path in `test-spec.md`
  has an executing test.
- **Dependencies:** 6, 7, 8, 9
- **Citations:** D-4 · REQ-E1.2, REQ-E1.4, REQ-E1.7, REQ-C1.7, REQ-D1.1
- **Estimated effort:** 2 days

### Task 12 — Docs and maintenance

- **Deliverables:** command documentation (invocation, scope selectors, reveal
  flag, the optional Graphviz enhancement); any options-reference rows for new
  config; the completion-time doctrine drift-observation wiring.
- **Done when:** the command is documented for an adopter, any new config option
  has an options-reference row, and the skill appends a drift observation on
  completion like its siblings.
- **Dependencies:** 6, 7, 9
- **Citations:** D-5 · REQ-F1.4, REQ-E1.3
- **Estimated effort:** half day

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

(none yet)

## Deferred

- **Redline / amendment-diff view.** A plain-language diff between two versions
  or anchors of a bundle, for the Active/amendment stage. Confidence: high.
  **Gate:** GATE(when: the v1 walkthrough has shipped and an amendment-heavy
  bundle motivates a diff view). Citations: REQ scope (Out of scope); D-1.
- **Markdown + Mermaid companion artifact.** A second output path that renders
  natively for engineers on GitHub and VS Code and keeps diagram source as
  diffable text. Confidence: high. **Gate:** GATE(when: the HTML artifact has
  shipped and an engineer-facing diffable companion is requested). Citations:
  D-4.

## Out of scope

- Editing, authoring, or signing off a bundle (owned by `/spec-draft` and
  `/spec-kickoff`).
- Any verdict, score, or quality assessment the tool produces on its own behalf
  (the independence firewall, REQ-D1.1).
- Hard dependencies on a browser engine or an uncommon binary (REQ-E1.3).
