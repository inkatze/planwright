# Spec Comprehension Walkthrough — Requirements

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

## Goal

planwright invests in making a spec correct before any code is written, but the
densest artifacts a spec produces — dozens of design decisions, a task
dependency graph, layered requirements — are brutal to absorb as raw text, and
most people comprehend visually. `/spec-walkthrough` renders a spec bundle, or
selected parts of it, into a digestible, visual, didactic artifact in plain,
audience-neutral language, so a human can understand and **independently
evaluate** it at any lifecycle stage: an unaided cold read before
`/spec-kickoff` sign-off, re-orientation mid-execution, or onboarding to a
finished or abandoned spec.

Two properties are load-bearing. First, the rendering speaks plain English and
never surfaces planwright's internal vocabulary (the four-file structure, the
requirement/decision/task ID schemes) in its default form, so anyone with the
context — from product to engineering — can read it. Second, the aid **presents
and structures; the human judges.** It never delivers its own verdict, score, or
assessment, because the moment the agent performs the comprehension, an
independent review collapses back into "the authoring agent reviewed its own
spec" and the independence firewall is lost.

`/spec-walkthrough` is the didactic complement to `/spec-kickoff`'s guided
dialogue: kickoff is the collaborative pass that produces the signed brief;
the walkthrough is the unaided human pass that kickoff, and every other reader,
builds on. It is read-only and never advances the pipeline.

## Scope

### In scope

- A standalone `/spec-walkthrough` command that renders an existing bundle
  didactically and read-only.
- Whole-bundle and partial views (one source file, one requirement group, the
  decision set, the task graph, a single decision and its blast radius).
- Stage-aware framing across every status (Draft, Active, Done, Retired,
  Superseded).
- Four didactic views: a spec-at-a-glance one-pager, a dependency graph with
  critical path, an ADR-shaped decision map, and a teach-back challenge.
- Plain-language translation as a lossless layered view, with an opt-in reveal
  toggle for ID/artifact traceability and a precision-preservation guardrail.
- A self-contained, shareable, offline-openable HTML artifact persisted to a
  gitignored location.
- Suggest-only discoverability touchpoints in `/spec-draft`, `/spec-kickoff`,
  and `/resume`.

### Out of scope

- Editing or authoring a bundle (that is `/spec-draft`) and sign-off (that is
  `/spec-kickoff`).
- A redline / amendment-diff view comparing two versions of a bundle — a
  fast-follow (it couples to anchor and sign-off history).
- A Markdown + Mermaid companion artifact — deferred; v1 ships the HTML
  artifact only.
- Any verdict, score, pass/fail, or quality assessment of the spec the tool
  produces on its own behalf.
- Heavyweight rendering runtimes or hard dependencies on a browser engine or an
  uncommon binary.
- Auto-invoking the walkthrough from any sibling command, or chaining it into
  any other skill.

## REQ-A — Command surface & invocation

- **REQ-A1.1** planwright SHALL provide a standalone `/spec-walkthrough` command
  that renders an existing spec bundle, or selected parts of it, into a
  didactic comprehension artifact for independent human evaluation.
  *(Cites: D-1; comprehension-aid seed (Sources); drafting-session decision (2026-06-16).)*
- **REQ-A1.2** The command SHALL accept a spec-path argument, an optional scope
  selector naming which part to render, and an optional off-by-default reveal
  flag that exposes the underlying identifiers.
  *(Cites: D-1, REQ-B1.2, REQ-D1.3.)*
- **REQ-A1.3** The command SHALL operate strictly read-only: it SHALL NOT modify
  any bundle file, commit, push, change a status, or write the kickoff brief.
  Its only writes SHALL be generated artifacts to the gitignored location of
  REQ-E1.1. *(Cites: D-10; the bootstrap invariants (Sources).)*
- **REQ-A1.4** The command SHALL render bundles in any status — Draft, Active,
  Done, Retired, or Superseded — because rendering is read-only and terminal
  bundles remain valuable for archaeology. *(Cites: D-10.)*
- **REQ-A1.5** The command SHALL degrade gracefully on a missing, malformed, or
  partial bundle: a clear message, rendering what is present and naming what is
  missing, rather than halting opaquely. A charset-valid scope selector that
  resolves to no part of the bundle (a requirement group, decision, or file not
  present) SHALL likewise yield a clear message naming the available scopes,
  never an opaque failure or a silent empty render.
  *(Cites: the bootstrap graceful-degradation posture (Sources); kickoff sign-off lens pass (2026-06-16).)*
- **REQ-A1.6** The command SHALL validate the spec identifier and path against
  the identifier charset and containment-check the resolved path before any
  read. Hostile input SHALL be a clean refusal, never a path.
  *(Cites: the security-posture framework-script rules (Sources).)*

## REQ-B — Scope selection & stage awareness

- **REQ-B1.1** The command SHALL render a whole-bundle view as its default
  scope. *(Cites: D-1; comprehension-aid seed (Sources).)*
- **REQ-B1.2** The command SHALL support partial views selecting one source
  file, one requirement group, the decision set, the task graph, or a single
  decision together with its blast radius (what the decision affects).
  *(Cites: D-1; comprehension-aid seed (Sources).)*
- **REQ-B1.3** The rendering SHALL adapt its framing to the bundle's status,
  auto-detected: a pre-sign-off cold read for Draft, orientation plus progress
  for Active, and onboarding or archaeology for Done and terminal statuses.
  *(Cites: D-11.)*
- **REQ-B1.4** The command SHALL NOT require Active status, in deliberate
  contrast with the execution skills' non-Active refusal. *(Cites: D-10.)*

## REQ-C — Didactic rendering

- **REQ-C1.1** The default rendering SHALL use plain, audience-neutral language
  and SHALL NOT surface planwright's internal vocabulary — the four-file
  structure or the requirement, decision, and task ID schemes — so a
  cross-functional reader from product to engineering can read it.
  *(Cites: D-2; cross-audience research (Sources); drafting-session decision (2026-06-16).)*
- **REQ-C1.2** The spec-at-a-glance view SHALL be a length-bounded narrative
  (prose, not a bullet dump) in which every load-bearing claim carries a
  traceable back-pointer to its source element, and which foregrounds the small
  set of load-bearing "killer items."
  *(Cites: D-2; cross-audience research (Sources); cold-read research (Sources).)*
- **REQ-C1.3** The dependency-graph view SHALL draw the work items as an actual
  graphic (not ASCII) with the critical path and parallelism visible and plain
  labels, and SHALL physically integrate each diagram with its explaining text
  rather than splitting them.
  *(Cites: D-4, D-5, D-6; cognitive-science research (Sources).)*
- **REQ-C1.4** The decision-map view SHALL render each decision as Context →
  Decision → Alternative-rejected → Consequence, surfacing the rejected
  alternative and the cost, not only the chosen path.
  *(Cites: D-2; cross-audience research (Sources).)*
- **REQ-C1.5** The teach-back view SHALL present the spec's own claims as
  restate-in-your-own-words and agree / disagree / unsure prompts that elicit
  the human's judgment, proceeding section by section rather than as one final
  gate.
  *(Cites: D-3, D-9; cold-read research (Sources); cognitive-science research (Sources).)*
- **REQ-C1.6** Every diagrammatic view SHALL render as a drawn graphic in the
  artifact, never as ASCII art. *(Cites: D-4; comprehension-aid seed (Sources).)*
- **REQ-C1.7** The plain-language translation SHALL NOT soften a normative token
  — MUST, SHALL, SHALL NOT, a threshold, or an enumerated state — into vague
  prose; such tokens SHALL be preserved verbatim and marked as toggle-anchored.
  *(Cites: D-2; cross-audience research (Sources).)*

## REQ-D — Independence firewall

- **REQ-D1.1** The aid SHALL present and structure only; it SHALL NOT deliver a
  verdict, score, pass/fail, or any assessment of the spec's quality or
  correctness on its own behalf.
  *(Cites: D-3; comprehension-aid seed (Sources).)*
- **REQ-D1.2** The command SHALL present the full rendering for an unaided
  end-to-end read before offering any prompt, analysis, or teach-back, so the
  human's first read is unanchored by the tool.
  *(Cites: D-3; cold-read research (Sources).)*
- **REQ-D1.3** An off-by-default reveal toggle SHALL surface the underlying
  identifiers and artifact mapping; the default output SHALL NOT show them. The
  three rendered categories are distinct: identifiers are *hidden* by default
  and shown on reveal; normative tokens (REQ-C1.7) are *never* softened — they
  appear verbatim in both views, with reveal surfacing their toggle-anchored
  source mapping; and any non-normative precise phrasing the plain view
  *rephrased* SHALL be restorable to its source wording on reveal. "Softened"
  refers only to that last category, never to normative tokens.
  *(Cites: D-2, REQ-C1.7; cross-audience research (Sources); kickoff sign-off lens pass (2026-06-16).)*
- **REQ-D1.4** The teach-back SHALL record the human's own responses without
  supplying the "right" answer; it MAY surface divergences between a
  restatement and the spec text, but adjudication SHALL stay with the human.
  *(Cites: D-3, D-9; cold-read research (Sources).)*

## REQ-E — Artifact output & hygiene

- **REQ-E1.1** The command SHALL persist a self-contained HTML artifact, with
  any diagrams inlined as SVG, to a gitignored location under
  `.claude/walkthroughs/<spec>/`.
  *(Cites: D-4, D-8; rendering research (Sources).)*
- **REQ-E1.2** The artifact SHALL be openable by a non-technical reader with no
  installed dependencies — offline, in any browser.
  *(Cites: D-4; rendering research (Sources).)*
- **REQ-E1.3** Artifact generation SHALL NOT require a heavyweight runtime or a
  hard dependency on a browser engine or an uncommon binary; an optional
  renderer that is absent — or that is present but fails to execute (non-zero
  exit, timeout, or invalid output) — SHALL degrade cleanly to the
  self-contained path.
  *(Cites: D-5; rendering research (Sources); kickoff sign-off lens pass (2026-06-16).)*
- **REQ-E1.4** The artifact SHALL carry no secrets, credentials, or sensitive
  operational detail, and SHALL remain gitignored regardless of content.
  *(Cites: the security-posture data-hygiene rule (Sources).)*
- **REQ-E1.5** The artifact SHALL be stamped with the bundle it rendered and the
  commit it was generated from, so a reader can tell whether it is stale.
  *(Cites: D-8.)*
- **REQ-E1.6** The styling SHALL use only redistributable, MIT-licensed
  primitives, inlined for offline rendering, so the generated artifact ships
  cleanly under planwright's installed-by-adopters model.
  *(Cites: D-7; the engineering dependency-adoption license check (Sources).)*
- **REQ-E1.7** All bundle content rendered into the artifact SHALL be HTML- and
  SVG-escaped (or sanitized) so that no bundle content — including the
  angle-bracket placeholder convention (`<spec>`, `<id>`), ampersands, code
  fences, or authored markup — can inject executable script or structural markup
  into the artifact, and so that such characters display as their literal text.
  *(Cites: D-4; the security-posture data-hygiene rule (Sources); kickoff sign-off lens pass (2026-06-16).)*

## REQ-F — Lifecycle & pipeline integration

- **REQ-F1.1** `/spec-walkthrough` SHALL complement `/spec-kickoff` and SHALL
  NOT replace it: the walkthrough is the unaided independent pass; kickoff is
  the guided dialogue producing the signed brief.
  *(Cites: D-1; comprehension-aid seed (Sources).)*
- **REQ-F1.2** `/spec-draft`'s handoff, `/spec-kickoff`'s pre-flight, and
  `/resume` SHALL surface `/spec-walkthrough` as a recommended independent
  human step, and SHALL NOT auto-invoke it.
  *(Cites: D-11; the bootstrap no-auto-chain invariant (Sources).)*
- **REQ-F1.3** The command SHALL NOT mutate any pipeline state or chain into
  another skill. *(Cites: D-10, D-11; the bootstrap invariants (Sources).)*
- **REQ-F1.4** On completion the skill SHALL compare itself against the resolved
  doctrine and append a drift observation to the observations log when a named
  concept has changed, like its sibling skills.
  *(Cites: the maintenance convention (Sources).)*

## Changelog

- 2026-06-16: `/panel-review` correction. Corrected the derived effort-weighted
  critical path in the build-order note (`tasks.md`) and the kickoff brief to run
  through Task 11 (≈12.5 days): Task 11 depends on Task 7, so the prior note
  stopping at Task 7 (≈10.5 days) was inconsistent with the authoritative
  dependency graph and with Task 7's reused `orchestrate-select.sh` critical-path
  computation. Dropped the REQ-F1.3 citation from Task 10 (D-11 → REQ-F1.2 per
  the brief ledger; REQ-F1.3 maps to D-10). Derived prose and citations only; no
  requirement meaning changed.
- 2026-06-16: `/spec-kickoff` first-activation sign-off lens pass. Added
  REQ-E1.7 (all rendered bundle content HTML/SVG-escaped/sanitized, so bundle
  text — including the angle-bracket placeholder convention — cannot inject
  markup), with a `[test]` entry and wiring into Tasks 6 and 11 (meaning-class
  addition). Clarified REQ-A1.5 (a well-formed but unresolvable scope selector
  degrades with a clear message), REQ-E1.3 + D-5 (a present-but-failing Graphviz
  probe degrades like absence), REQ-D1.3 (the "softened" category is
  non-normative rephrasing only; normative tokens are never softened), and the
  REQ-C1.3 test-spec entry (assert the highlighted critical path matches the
  reused `orchestrate-select.sh` computation).
- 2026-06-16: `/spec-kickoff` first-activation walkthrough. Completed task
  dependencies: Task 11 (coverage gate) now depends on 6,7,8,9 (it tests the
  graph/decision-map/scope views T7/T8/T9) and Task 12 (docs) on 6,7,9 (it
  documents the Graphviz enhancement T7 and scope selectors T9); these did not
  previously appear in their dependency lines. Tightened the derived build-order
  note (MVP slice vs effort-weighted critical path). No requirement meaning
  changed.
- 2026-06-16: `/spec-kickoff` first-activation walkthrough. Sharpened the
  REQ-E1.4 test-spec entry to scan the generated artifact directly
  (`gitleaks --no-git <path>`), since the gitignored artifact is invisible to
  the repo-wide scan (was a latent dead path). No requirement meaning changed.
- 2026-06-16: `/spec-kickoff` first-activation walkthrough. Clarified D-7: the
  "used CSS" subset is curated/built at plugin-ship time and inlined as a static
  stylesheet at render (no adopter runtime build), resolving the D-7 vs
  D-5/REQ-E1.3 feasibility tension. No requirement meaning changed.
- 2026-06-16: Bundle drafted at Status Draft via `/spec-draft`. Spun as a new
  bundle (no fold against `bootstrap` or `customization-overlay`). Design
  decisions D-1 through D-11 recorded; four didactic views, the independence
  firewall, plain-language layered-view translation, and a self-contained HTML
  artifact established. Research consulted and recorded in Sources.

## Sources

- **comprehension-aid seed** — `specs/_pending/comprehension-aid.md`, captured
  2026-06-09 during the bootstrap drafting session: the cold-start comprehension
  aid idea, the independence firewall constraint, and the candidate didactic
  forms. Consumed and archived by this draft.
- **the bootstrap spec** — `specs/bootstrap/`: the carried invariants
  (never auto-merge, never act on a non-Active spec, never auto-chain, never
  force-push/amend/squash/rebase, draft PRs only), the read-only and
  graceful-degradation postures, the portable-runtime constraint, the
  security-posture framework-script and data-hygiene rules, the maintenance
  drift-observation convention, and `scripts/orchestrate-select.sh`'s
  critical-path computation reused by REQ-C1.3 / D-6.
- **cold-read research** — high-stakes cold-read practices that stay fast while
  preserving independent judgment: aviation challenge-response checklists and
  "killer items" ([code7700 checklist philosophy](https://www.code7700.com/checklist_philosophy.htm),
  [SKYbrary checklists](https://skybrary.aero/articles/checklists-purpose-and-use)),
  clinical teach-back ([AHRQ Tool 5](https://www.ahrq.gov/health-literacy/improve/precautions/tool5.html)),
  the Amazon PR-FAQ / six-pager narrative and silent-reading meeting
  ([Working Backwards PR-FAQ](https://workingbackwards.com/concepts/working-backwards-pr-faq-process/)),
  and legal redlining plus plain-language clause summaries
  ([Juro contract redlining](https://juro.com/learn/contract-redlining)).
- **cognitive-science research** — dual-coding theory
  ([Clark & Paivio](https://link.springer.com/article/10.1007/BF01320076)),
  cognitive load and the split-attention effect
  ([split-attention effect](https://en.wikipedia.org/wiki/Split_attention_effect),
  [Chandler & Sweller 1992](https://bpspsychub.onlinelibrary.wiley.com/doi/abs/10.1111/j.2044-8279.1992.tb01017.x)),
  the testing effect
  ([retrieval-based learning](https://files.eric.ed.gov/fulltext/ED599273.pdf)),
  and the self-explanation effect
  ([Chi et al. 1994](https://onlinelibrary.wiley.com/doi/10.1207/s15516709cog1803_3)).
- **rendering research** — the spec-tool landscape (AWS Kiro, GitHub Spec Kit)
  emits no shareable visual comprehension artifact; portable rendering options
  ([Mermaid](https://github.com/mermaid-js/mermaid),
  [Graphviz SVG output](https://graphviz.org/docs/outputs/svg/)) and the
  self-contained single-HTML medium as the only zero-reader-dependency,
  offline, non-technical-openable choice.
- **cross-audience research** — making a spec evaluable by product through
  engineering from one artifact, with a readable surface over a precise
  traceable substrate: Amazon PR-FAQ, the
  [C4 model](https://c4model.info/), Architecture Decision Records
  ([Nygard ADRs](https://www.cognitect.com/blog/2011/11/15/documenting-architecture-decisions)),
  the plain-language one-pager, and the precision-loss risk of stripping
  jargon and identifiers.
- **engineering dependency-adoption license check** — the styling system was
  selected for MIT-license redistribution compatibility with planwright's
  public-release model
  ([Tailwind CSS MIT](https://github.com/tailwindlabs/tailwindcss/blob/main/LICENSE),
  [DaisyUI MIT](https://github.com/saadeghi/daisyui/blob/master/LICENSE)).
- **drafting-session decision (2026-06-16)** — choices made live in this
  `/spec-draft` session that minted no D-ID: the spec identifier
  `spec-comprehension`, the command name `/spec-walkthrough`, the broad
  any-stage scope, and the independence firewall as a hard constraint.
