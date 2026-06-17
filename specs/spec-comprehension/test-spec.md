# Spec Comprehension Walkthrough — Test Spec

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

Coverage mix: the command surface, scope selection, artifact output, and the
structural rendering properties are automated `[test]` paths in CI; the
didactic-quality and independence-firewall properties (readability, "presents
not judges," silent-read-first) carry `[manual]` and `[design-level]` paths
because they are judged, not asserted; stage-aware scenarios use `[Gherkin]`.
Real bundles (`bootstrap`, `customization-overlay`) and small malformed
fixtures are the test corpus.

## REQ-A — Command surface & invocation

### REQ-A1.1 — Command renders a bundle [test]

Invoke `/spec-walkthrough` against a real bundle and assert a comprehension
artifact is produced for the requested scope.

### REQ-A1.2 — Argument and flag parsing [test]

Fixtures exercise the spec-path argument, each scope selector, and the reveal
flag; assert each parses to the intended render request and bad arguments are
rejected.

### REQ-A1.3 — Strictly read-only [test]

After a run, assert the bundle files and git state are unchanged and the only
new path is under the gitignored artifact location; assert no commit, push, or
status change occurred.

### REQ-A1.4 — Reads any status [test]

Fixtures in Draft, Active, Done, Retired, and Superseded each render without
refusal.

### REQ-A1.5 — Graceful degradation [test]

Missing-file, malformed-header, and partial-bundle fixtures each yield a clear
message that names what is absent and render what is present, with no opaque
halt.

### REQ-A1.6 — Identifier and path safety [test]

Hostile identifiers and traversal paths are refused cleanly before any read;
the resolved path is containment-checked.

## REQ-B — Scope selection & stage awareness

### REQ-B1.1 — Whole-bundle default [test]

Invoking with no scope selector renders the whole bundle.

### REQ-B1.2 — Partial views [test]

Each selector (one file, one requirement group, the decision set, the task
graph, a single decision with its blast radius) renders only its scope; the
single-decision view includes the elements the decision affects.

### REQ-B1.3 — Stage-aware framing [test + manual] [Gherkin]

Given a bundle in each status, when rendered, then the framing matches the stage
(Draft cold read, Active orientation plus progress, Done/terminal onboarding or
archaeology). Auto-detection is `[test]`; the framing's fitness is `[manual]`.

### REQ-B1.4 — No Active requirement [test]

A Draft bundle renders without the non-Active refusal the execution skills
apply.

## REQ-C — Didactic rendering

### REQ-C1.1 — Plain audience-neutral default [test + manual]

Assert the default output contains none of the internal vocabulary (four-file
names, REQ/D/task ID tokens) `[test]`; a cross-functional reader confirms
readability `[manual]`.

### REQ-C1.2 — Spec-at-a-glance one-pager [test + manual]

Assert the one-pager is bounded narrative prose, every claim resolves to a
source back-pointer, and killer items are marked `[test]`; the narrative's
clarity is `[manual]`.

### REQ-C1.3 — Dependency graph integrated, not ASCII [test + manual]

Assert the graph is inline SVG with the critical path highlighted, that the
highlighted path matches the reused `scripts/orchestrate-select.sh` critical-path
computation (D-6) for the same bundle, and that the diagram is adjacent to its
explaining text `[test]`; the visual legibility is `[manual]`.

### REQ-C1.4 — Decision map four-beat [test]

Assert every decision renders as Context → Decision → Alternative-rejected →
Consequence with the rejected alternative and consequence present.

### REQ-C1.5 — Teach-back prompts [test + manual]

Assert the teach-back presents claims section by section and supplies no answer
`[test]`; the prompts' didactic quality is `[manual]`.

### REQ-C1.6 — Drawn, not ASCII [test]

Assert every diagrammatic view is a drawn graphic (SVG), with no ASCII-art
fallback in the artifact.

### REQ-C1.7 — Precision-preservation guardrail [test]

For bundles whose text contains normative tokens (MUST/SHALL/SHALL NOT,
thresholds, enumerated states), assert each survives verbatim in the rendering
and is marked toggle-anchored.

## REQ-D — Independence firewall

### REQ-D1.1 — Presents, never judges [test + manual]

Assert the artifact and session output contain no verdict, score, or pass/fail
field `[test]`; a reviewer confirms no assessment is implied `[manual]`.

### REQ-D1.2 — Silent-read-first [manual] [design-level]

The interaction order (full render presented before any prompt or analysis) is
verified by design-level review of the skill flow and a manual exercise of a
run.

### REQ-D1.3 — Reveal toggle off by default [test]

Assert identifiers are absent by default and present only when the reveal flag
or toggle is engaged, and that softened tokens are restored on reveal.

### REQ-D1.4 — Teach-back keeps adjudication human [test + manual]

Assert responses are recorded without a supplied answer and divergences are
surfaced, not resolved `[test]`; a manual pass confirms the human adjudicates.

## REQ-E — Artifact output & hygiene

### REQ-E1.1 — Persisted to gitignored location [test]

Assert the artifact is written under `.claude/walkthroughs/<spec>/` and that the
path is gitignored.

### REQ-E1.2 — Offline, no installed dependency [test + manual]

Assert the HTML references no external network resource and opens with no
installed dependency `[test]`; a manual open in a browser confirms it renders
`[manual]`.

### REQ-E1.3 — No hard renderer dependency [test]

Run generation with Graphviz absent and assert the artifact still renders via
the self-contained path, with the degradation note present.

### REQ-E1.4 — Data hygiene [test]

The test generates an artifact and runs the secret scanner (gitleaks) directly
over that artifact path — `--no-git`, since the artifact is gitignored and
therefore invisible to the repo-wide scan — and asserts no secrets are found;
the artifact stays gitignored.

### REQ-E1.5 — Provenance stamp [test]

Assert the artifact records the bundle it rendered and the commit it was
generated from.

### REQ-E1.6 — MIT-licensed inlined styling [test + design-level]

Assert the artifact inlines its CSS (no external stylesheet reference) and
carries the MIT notice; the styling-system choice is recorded at design level.

### REQ-E1.7 — Content escaping / injection safety [test]

A fixture bundle whose text contains HTML/SVG metacharacters and markup (e.g.
`<script>`, `<img onerror=…>`, raw `<` and `&`, angle-bracket placeholders such
as `<spec>`) renders into the artifact escaped or sanitized; assert no
executable or structural markup originating from bundle content survives in the
output and that the literal characters display correctly.

## REQ-F — Lifecycle & pipeline integration

### REQ-F1.1 — Complements, not replaces, kickoff [design-level]

The complementary relationship (unaided pass vs guided dialogue) is verified by
design-level review against `/spec-kickoff`.

### REQ-F1.2 — Suggest-only touchpoints [test + manual]

Assert `/spec-draft`, `/spec-kickoff`, and `/resume` each contain the
recommendation and none contains an invocation of `/spec-walkthrough` `[test]`;
the wording is confirmed as suggest-only `[manual]`.

### REQ-F1.3 — No pipeline mutation [test]

Assert a run changes no `tasks.md` state, no lock, no status, and no other
pipeline artifact.

### REQ-F1.4 — Drift-observation maintenance [design-level]

The completion-time doctrine comparison and drift-observation append are
verified by design-level review of the skill, matching the sibling convention.
