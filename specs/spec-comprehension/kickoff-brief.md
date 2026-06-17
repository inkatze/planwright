# Spec Comprehension Walkthrough — Kickoff Brief

## 1. Header

- **Spec path:** `specs/spec-comprehension`
- **Spec commit at walkthrough start:** `d4ba72f854ee3a6d8a8742125e3b522e3c9ced8e`
- **Walkthrough date:** 2026-06-16
- **Mode:** first activation
- **Validator outcome (pre-flight, Draft):** 0 errors, 0 warnings (clean)
- **Config:** `commit_on_kickoff: true` (default; not overridden by local)
- **Rule docs resolved:** spec-format, discovery-rigor, validation-rigor,
  security-posture, decision-domains, interaction-style (all present)

## 2. Goal & glossary

**Goal (agent restatement).** `/spec-walkthrough` is a standalone, read-only
command that renders a spec bundle (or a chosen slice) into a visual, didactic,
plain-English artifact a human reads and **judges for themselves**. It lowers
the cost of absorbing a dense bundle (dozens of decisions, a dependency graph,
layered REQs) so a human can independently evaluate it at any lifecycle stage:
an unaided cold read before kickoff sign-off, re-orientation mid-execution, or
onboarding to a finished/abandoned spec. It is the unaided complement to
`/spec-kickoff`'s guided dialogue, not embedded in it.

**Two load-bearing properties** (everything else serves these):
1. **Plain, audience-neutral language by default** — never surfaces planwright's
   internal vocabulary (four-file structure, REQ/D/task ID schemes) in default
   form, so any reader from product to engineering can read it.
2. **Presents and structures; the human judges** (the independence firewall) —
   never delivers a verdict, score, or assessment of its own; the moment the
   agent performs the comprehension, independent review collapses into "the
   authoring agent reviewed its own spec."

**Rules out.** Editing/authoring (`/spec-draft`), sign-off (`/spec-kickoff`),
any self-issued verdict/score/quality assessment, pipeline mutation or
auto-chaining, heavyweight runtimes or hard browser-engine/uncommon-binary
dependencies. v1 is HTML-only (Markdown+Mermaid companion and redline/diff view
deferred).

**Assumes.** The bundle exists and is parseable enough to render; a
self-contained single HTML file (offline, any browser, nothing installed) fits
the cross-functional, shareable audience; critical-path truth is reused from
`scripts/orchestrate-select.sh`, not recomputed.

**Glossary (implicit terms surfaced and resolved):**
- **Killer items** (REQ-C1.2) — from aviation checklist philosophy: the small
  set of load-bearing claims where being wrong is catastrophic, foregrounded
  above routine content.
- **Blast radius** of a decision (REQ-B1.2) — the requirements, tasks, and
  other decisions that cite or depend on the selected D-ID (what the decision
  affects). Confirmed reading.
- **Layered view / lossless** (D-2, REQ-C1.7) — the plain rendering is a view
  *over* the ID-bearing substrate with back-pointers retained and normative
  tokens preserved verbatim; "lossless" = a disagreeing reader can always reach
  the exact source element and the exact normative token.
- **Normative token** (REQ-C1.7) — MUST / SHALL / SHALL NOT, a threshold, or an
  enumerated state; preserved verbatim, marked toggle-anchored.
- **Teach-back** (REQ-C1.5, D-9) — from clinical practice: the reader restates
  claims in their own words and marks agree/disagree/unsure section by section;
  the tool records, never supplies the "right" answer.

**Resolutions:**
- The one-pager's "length-bounded" is deliberately unquantified (manual-judged),
  confirmed intentional, not an omission.
- **Accessibility of the visual artifact** (screen-reader text for inline SVG;
  the critical-path highlight not conveyed by color alone) is **not decided** in
  the bundle. Disposition: recorded as a risk-register row (§7); v1 ships
  without an accessibility requirement, the gap stays visible and tracked.

Signed off: 2026-06-16

## 3. Requirements walkthrough

**Per-group outcomes** (intent restated and confirmed):
- **REQ-A — command surface.** Standalone command: spec-path + optional scope
  selector + optional off-by-default reveal flag; strictly read-only (only
  writes are generated artifacts); renders any status; identifier-charset +
  path-containment check before any read. Degrade-vs-refuse boundary confirmed
  coherent: a valid path with broken content degrades (render present, name
  missing); a charset/traversal violation is a clean refusal that never becomes
  a path.
- **REQ-B — scope & stage.** Whole-bundle default; partials (one file, one REQ
  group, the decision set, the task graph, one decision + blast radius);
  status-auto-detected framing; deliberately not gated on Active.
- **REQ-C — didactic rendering.** Plain audience-neutral default, no internal
  vocabulary; one-pager bounded narrative with per-claim back-pointers + killer
  items; dependency graph drawn (not ASCII) with critical path + parallelism,
  integrated with text; decision map four-beat; teach-back section by section;
  all diagrams drawn; normative tokens verbatim + toggle-anchored.
- **REQ-D — independence firewall.** Present/structure only, no verdict/score;
  full unaided read before any prompt; reveal toggle off by default; teach-back
  records without supplying answers.
- **REQ-E — artifact & hygiene.** Self-contained HTML, inlined SVG, gitignored
  `.claude/walkthroughs/<spec>/`; offline no-dep; no hard renderer dependency
  (Graphviz optional, degrades); data hygiene; provenance stamp; MIT-licensed
  inlined styling.
- **REQ-F — lifecycle.** Complements not replaces kickoff; suggest-only
  touchpoints; no mutation/chaining; completion-time drift observation.

**Decisions / recorded readings:**
- **REQ-C1.1 vs REQ-C1.2 tension resolved by D-2.** The per-claim back-pointer
  is *hidden* structure (the reveal toggle is the seam); it is present but not
  visible text in the default view, so "no ID schemes by default" and "every
  claim is traceable" hold simultaneously. No edit.
- **REQ-C1.4 four-beat sourcing** — the 'Consequence' beat has no source field
  in the three-field D-ID structure (Decision / Alternatives / Chosen because).
  Resolution: implementation detail — the renderer derives Context from the
  decision's framing and Consequence from 'Chosen because'. The four-beat is a
  presentation mapping over the three-field substrate. No edit.
- **REQ-D1.4 divergence-surfacing is the in-session path only.** The static
  offline HTML artifact offers agree/disagree/unsure and records responses; it
  has no free-text comparison engine. 'MAY surface divergences' is the optional
  in-session capability. Recorded so Task 5 builds to the split; no edit.

**Consolidated spec-edit list:** none from the requirements walk. (One edit
landed in the design walk, §4.)

Signed off: 2026-06-16

## 4. Design walkthrough

**Reconciled ledger — all eleven decisions accounted for:**

| D-ID | Disposition | Note |
| --- | --- | --- |
| D-1 Standalone command | Confirmed | matches REQ-A1.1, REQ-F1.1 |
| D-2 Lossless layered view | Confirmed | matches REQ-C1.1/C1.7/D1.3; resolves C1.1↔C1.2 |
| D-3 Render→read→teach-back | Confirmed | matches REQ-D1.1, REQ-D1.2 |
| D-4 Self-contained HTML + inlined SVG | Confirmed | matches REQ-E1.1, REQ-C1.6 |
| D-5 Self-contained renderer + optional Graphviz | Confirmed | matches REQ-E1.3 |
| D-6 Reuse `orchestrate-select.sh` critical path | Confirmed (carried, bootstrap) | matches REQ-C1.3 |
| D-7 MIT-licensed inlined styling | Amended (clarified) | see edit below; matches REQ-E1.6 |
| D-8 Artifact location + provenance stamp | Confirmed | matches REQ-E1.1, REQ-E1.5 |
| D-9 Teach-back in-artifact + in-session | Confirmed | matches REQ-C1.5, REQ-D1.4 (+ §3 split) |
| D-10 Read-only + status-agnostic | Confirmed | matches REQ-A1.3/A1.4/B1.4/F1.3 |
| D-11 Suggest-only touchpoints | Confirmed | matches REQ-F1.2 |

**No design decision contradicts a walked requirement; no inconsistency halt.**
Cross-cutting concerns (independence through-line; portability/offline
self-containment) hold.

**Spec edit applied (Draft, in place):**
- **D-7 clarified.** Pinned the "used CSS" subset to plugin-ship-time curation
  (a static stylesheet committed to the plugin, inlined at render), resolving
  the feasibility tension with D-5 / REQ-E1.3 (no adopter runtime build step).
  Recorded as a dated Changelog entry in `requirements.md`. No requirement
  meaning changed; this is an expression-level clarification of D-7's rationale.

Signed off: 2026-06-16

## 5. Verification approach

**Coverage mix (confirmed):**
- **`[test]` in CI** (`mise run check`): REQ-A group, REQ-B1.1/B1.2/B1.4, C1.4,
  C1.6, C1.7, D1.3, E1.1–E1.6, F1.3, plus the `[test]` halves of mixed entries.
- **`[manual]`** (human-exercised, not CI-gated): B1.3 framing fitness, C1.1
  readability, C1.2 narrative clarity, C1.3 legibility, C1.5 didactic quality,
  D1.1 no-assessment-implied, D1.4 human-adjudication, E1.2 browser open, F1.2
  wording.
- **`[design-level]`**: D1.2 silent-read flow, F1.1 complements-kickoff, F1.4
  drift-maintenance, E1.6 styling-choice record.
- **`[Gherkin]`**: B1.3 stage scenarios.

**Verification ownership:**
- `[test]` paths owned by Task 11, wired under `mise run check`, run in CI on
  every PR.
- `[manual]` paths are **not CI-gated**; exercised by the human at PR review and
  first real use. No automated sweep claims them — stated so they are not
  assumed covered by CI.
- `[design-level]` paths confirmed at PR review against the skill flow.

**Dead-path check:**
- **REQ-E1.4 (fixed).** Was a latent dead path: the artifact is gitignored and
  CI-absent, so the repo-wide gitleaks scan never sees it. Test-spec entry
  sharpened to generate an artifact and scan that path directly
  (`gitleaks detect --no-git --source <path>`); Changelog entry recorded. Binds Task 11.
- **REQ-C1.1 (note, not dead).** The "no internal vocabulary" test must scope to
  the *default* (non-revealed) view; the reveal view legitimately contains IDs.
  Recorded for Task 3 / Task 11.
- **REQ-D1.1 (note, not dead).** The `[test]` half is a proxy (absence of known
  verdict tokens); the real verification lives in the `[manual]` half. Acceptable
  by design (independence "presents not judges" is a judged property).
- No other REQ has a verification path that cannot run.

Signed off: 2026-06-16

## 6. Task graph

**Reconstructed from the authoritative `Dependencies:` lines (post-edit):**

```
T1 (none, 1d)
└─ T2 (2d)
   └─ T3 (2d)
      ├─ T4 one-pager (1d) ─┐
      └─ T5 teach-back (1.5d) ┴─ T6 HTML assembly (2d)
                                 ├─ T7 graph view (deps 2,6; 2d)
                                 ├─ T8 decision-map (deps 3,6; 1d)
                                 ├─ T9 scope/stage (deps 2,6; 1.5d)
                                 ├─ T10 touchpoints (dep 6; 0.5d)
                                 ├─ T11 tests/coverage gate (deps 6,7,8,9; 2d)
                                 └─ T12 docs (deps 6,7,9; 0.5d)
```

- **Effort-weighted critical path:** T1 → T2 → T3 → **T5** → T6 → **T7** →
  **T11** ≈ **12.5 days** (through T5, the heavier predecessor of T6, out to the
  heaviest post-core view T7, then the tests/coverage gate T11 that depends on
  it).
- **MVP slice:** T1 → T2 → T3 → {T4, T5} → T6 (first usable walkthrough).
- **Parallelism:** T4 ∥ T5 off T3; T7/T8/T9/T10/T11/T12 fan out after T6.

**Deliberate non-edges (recorded so nobody "fixes" them):**
- **T4 ⊥ T5** — one-pager and teach-back share no edge; both need only T3.
- **The explicit `2`/`3` deps on T7/T8/T9 over the transitive-through-T6 path**
  are intentional: they name the direct semantic dependency (T7/T9 → bundle
  model T2; T8 → translation layer T3) on top of the assembly dep T6. Not edges
  to prune.

**Spec edits applied (Draft, in place):**
- **T11 Dependencies 6 → 6,7,8,9** — the coverage gate asserts every `[test]`
  REQ has an executing test, including the graph (T7), decision-map (T8), and
  scope (T9) views; it cannot run before those exist. View tasks may still carry
  their own test-first tests; T11 remains the cross-cutting + coverage gate.
- **T12 Dependencies 6 → 6,7,9** — docs cover the Graphviz enhancement (T7) and
  scope selectors (T9), so docs are written against shipped behavior.
- **Derived build-order note tightened** — distinguishes the MVP slice (needs T4
  *and* T5 before T6) from the effort-weighted critical path; intro prose only,
  anchor-excluded.
- All recorded as a dated Changelog entry in `requirements.md`.

Signed off: 2026-06-16

## 7. Risk register

**Decision-domains gap check.** Walked all ten catalog domains against the spec.
Crossed-and-decided: API surface design (REQ-A, D-1), secrets/config — data
hygiene (REQ-E1.4), dependency adoption (D-5 Graphviz, D-7 Tailwind/DaisyUI).
Not crossed: data storage, caching, queues/async, auth/authz, concurrency,
observability, deploy/migration. **No catalogued domain is touched-but-undecided
→ the gap check produces no risk row.** Meta-note: the catalog lacks an entry
for this spec's central domain (human-facing comprehension / information-UX);
that catalog gap is already recorded in the observations log (2026-06-16) and is
not a defect of this bundle.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | Accessibility of the visual artifact — no requirement for SVG text alternatives or a non-color-only critical-path highlight; disabled/non-technical readers may be excluded. **Accepted for v1.** | Screen-reader + color-blind manual check; candidate fast-follow REQ. |
| 2 | Curated-CSS coverage gap — a class used by a view but missing from the ship-time subset (D-7) renders unstyled offline, no runtime build to regenerate. | CI check that the inlined CSS covers the classes the templates emit. |
| 3 | Decision-map "Consequence" inference — deriving the fourth beat from "Chosen because" is heuristic; a thin rationale yields a weak beat. | Decision-map review on a real bundle (bootstrap / customization-overlay). |
| 4 | Critical-path reuse coupling (D-6) — the view inherits `orchestrate-select.sh`'s known quirks (not fence-aware; deferred-task weighting, per obs log). | Compare rendered critical path to the human-readable note on a bundle with deferred tasks. |
| 5 | Plain-language precision loss — a softened normative token breaks reviewability (the risk the layered view exists to prevent). | REQ-C1.7 verbatim-preservation test + manual review. |
| 6 | Stale-artifact misread — a reader trusts an old artifact. Mitigation: provenance stamp (REQ-E1.5). | Stamp visible; staleness hint when the artifact's commit differs from current. |

No open questions remain unresolved.

Signed off: 2026-06-16

## 8. Sign-off

### Lens review pass (first activation — full bundle)

**Class:** meaning (first activation; additions count as meaning).
**Path:** parallel fan-out — one read-only sub-agent per canonical lens over the
full bundle (non-trivial delta per `discovery-rigor`), then `validation-rigor`
with the adversarial both-directions re-validation (falsify keeps, resurrect
declines).

**Canonical lens-coverage table:**

| Lens | Findings (validated) | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 1 kept, 3 declined | C1.7↔D1.3 wording (F5) kept; Task 8 dep "asymmetry" correct-by-design; D1.4 already in deliverables |
| Security | 1 kept (HIGH) | No HTML/SVG-escaping requirement (F1) |
| Error handling & failure modes | 2 kept | Graphviz-present-but-fails (F2); nonexistent well-formed scope (F3) |
| Performance | none | premature for small bundles; artifact-size already risk row 2 |
| Concurrency / state | none | single-user local read-only aid; out of threat model; atomic-write is impl guidance |
| Naming, readability, structure | none | review-mode high bar; no material worsening (Refactor Instinct) |
| Documentation / format | none | "(Sources)" descriptive refs are the sanctioned lightweight form; validator-clean |
| Tests / verification | 1 kept | C1.3 test weaker than Task 7 Done-when (F4); the "[manual] unfalsifiable" set misreads the firewall's judged-by-design properties |
| Cross-file consistency | none (returned clean) | REQ→task, REQ→test, D→REQ maps complete |

**Findings dispositioned (all, 2026-06-16):**

| # | Finding | Disposition |
| --- | --- | --- |
| F1 | No HTML/SVG-escaping requirement for rendered bundle content (security + correctness; even benign `<spec>` placeholders break) | **Applied** — added REQ-E1.7 + `[test]` entry, wired into Tasks 6, 11 |
| F2 | Graphviz present-but-failing not covered (D-5/REQ-E1.3 only cover absent) | **Applied** — REQ-E1.3 + D-5 clarified to degrade on failed invocation |
| F3 | Charset-valid but unresolvable scope selector undefined | **Applied** — REQ-A1.5 extended to degrade with a clear message naming available scopes |
| F4 | REQ-C1.3 test-spec weaker than Task 7 Done-when (no crit-path match) | **Applied** — test-spec entry asserts match to `orchestrate-select.sh` |
| F5 | REQ-C1.7↔REQ-D1.3 "softened token" ambiguity | **Applied** — REQ-D1.3 clarified: "softened" = non-normative rephrasing only |
| — | T12 changelog wording named T8 (decision-map) though T12 deps are 6,7,9 | **Applied** — changelog reworded (my own drafting error) |

**Declined (recorded with rationale):**
- **Task 8 dep `3,6` vs T4/T5 `3`** — correct by design: T4/T5 are inputs *assembled by* T6; T7/T8/T9 are views layered *on top of* T6. Not an asymmetry to fix.
- **Concurrency set** (write collision, atomicity, idempotency, TOCTOU) — the tool is a single-user, human-invoked, read-only aid; concurrent writers to one artifact path are out of the threat model. Atomic write-temp-rename is implementation guidance, not a v1 spec requirement.
- **Performance set** (size budgets, scalability, perf gates) — premature for the small real-bundle corpus; the meaningful artifact-size concern is already risk row 2.
- **Naming/structure nits** — review-mode high bar; the bundle does not materially worsen structure (Refactor Instinct review mode).
- **Documentation citation-form** ("the bootstrap … (Sources)") — the descriptive "(Sources)" reference is the sanctioned lightweight Source-citation form (`the bootstrap seed (Sources)` in spec-format); validator-clean.
- **Tests-lens "[manual] is unfalsifiable" set** (readability, didactic quality, framing fitness, etc.) — these are the independence firewall's deliberately human-judged properties; `[manual]`/`[design-level]` is the correct tag by design, matching the sibling-skill convention.
- **REQ-F1.4 "resolved doctrine" vague** — matches established sibling-skill drift-check language; no local ambiguity worth an edit.

No undispositioned findings remain.

### Sign-off record (first activation)

Status flipped Draft→Active on all four files; `Last reviewed:` is 2026-06-16 on
all four. Validator re-run under Active enforcement: 0 errors, 0 warnings.

Class: meaning
Lens-pass: recorded above (this section), full-bundle fan-out, findings dispositioned 2026-06-16.
Anchor: `eaebcebe874c7d2aa981326e1cbf28f83476e3cc` — computed as
`scripts/spec-anchor.sh specs/spec-comprehension`

## 9. Amendment log

(none yet)
