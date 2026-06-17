# Spec Comprehension Walkthrough — Design

**Status:** Active
**Last reviewed:** 2026-06-16
**Format-version:** 1

Origin-tag legend: `N` = new decision minted in this bundle; `C, <ref>` =
carried from a cited source.

## Decision log

### D-1: Standalone command, not a kickoff sub-stage  (N)

**Decision:** `/spec-walkthrough` is a standalone slash command that renders a
spec bundle on demand, at any lifecycle stage, rather than a pre-flight stage
embedded inside `/spec-kickoff`.

**Alternatives considered:**
- A pre-flight stage of `/spec-kickoff`. Rejected because: it would only serve
  the pre-sign-off moment, not mid-execution orientation or onboarding to a
  finished bundle, and embedding the comprehension pass inside the authoring
  dialogue erodes the independence the cold read exists to provide.
- A passive document generator with no command surface. Rejected because: the
  human needs to invoke it against a chosen bundle and scope on demand.

**Chosen because:** the seed's open question ("standalone move vs kickoff
stage") resolves to standalone the moment the scope is "any point, any stage":
a single command serves every scenario, and standing apart from kickoff is what
keeps the read independent.

### D-2: Plain language is a lossless layered view, never a rewrite  (N)

**Decision:** the plain, audience-neutral rendering is a *view* over the
ID-bearing bundle, not a rewrite of it. Every plain sentence keeps a hidden
back-pointer to its source element; the reveal toggle (D-3 / REQ-D1.3) is the
seam between the readable surface and the precise substrate; and normative
tokens are never softened (REQ-C1.7).

**Alternatives considered:**
- Summarize / paraphrase the bundle into new prose. Rejected because:
  summarization is lossy and breaks traceability — a reader who disagrees has
  no path back to the element to fix, and softened normative language becomes
  un-reviewable.
- Always show the identifiers. Rejected because: it fails the cross-functional
  goal — product readers should not have to parse REQ/D/task ID schemes.

**Chosen because:** every cross-audience source studied (Amazon PR-FAQ→FAQ, C4
zoom levels, ADRs, the one-pager→appendix) converges on one readable surface
over a precise traceable substrate joined by stable back-references. Layering,
not replacement, keeps the artifact readable for product and traceable for
engineering from a single source of truth.

### D-3: Independence flow — render, unaided read, then teach-back  (N)

**Decision:** the command renders the full artifact, presents it for an unaided
end-to-end read first, and only then offers teach-back prompts; the agent never
voices its own verdict, score, or assessment of the spec.

**Alternatives considered:**
- The agent narrates a summary or its own critique up front. Rejected because:
  it anchors the reader on the tool's framing and collapses the independent
  read into "the authoring agent reviewed its own spec."
- Gate comprehension once at the end. Rejected because: the teach-back evidence
  base (chunk-and-check) shows section-by-section confirmation surfaces gaps a
  single end gate misses.

**Chosen because:** silent-read-first (Amazon) plus teach-back (clinical) is the
mechanical expression of the independence firewall — the tool lowers reading
cost and surfaces load-bearing items; the human reaches the conclusion.

### D-4: Output medium — self-contained HTML with inlined SVG  (N)

**Decision:** v1 persists a single self-contained HTML file with any diagrams
inlined as SVG. The Markdown + Mermaid companion is deferred.

**Alternatives considered:**
- Terminal / ASCII rendering. Rejected because: the seed requires "drawn, not
  ASCII," and a terminal cannot serve a non-technical reader.
- Markdown + Mermaid as the sole artifact. Rejected because: it degrades to raw
  code fences in plain viewers and for non-technical readers — deferred to a
  companion, not the primary.
- A hosted or served app. Rejected because: it adds a runtime dependency and
  breaks the offline, zero-reader-dependency requirement.

**Chosen because:** a single self-contained HTML file is the only medium that
renders visually for *everyone* — offline, in any browser, with nothing
installed — which is exactly the cross-functional, shareable audience the goal
targets. It is also the gap no existing spec tool fills.

### D-5: Renderer — self-contained, with optional Graphviz enhancement  (N)

**Decision:** diagram generation requires no hard dependency. The skill emits
inline SVG it computes directly for the (small) task graphs; when `dot`
(Graphviz) is detected at runtime it is used for a richer layout; when absent —
or detected but failing to execute (non-zero exit, timeout, or invalid output) —
the built-in path renders and a one-line note in the artifact says so. The
runtime probe treats a failed invocation identically to absence; Graphviz is
never on a path that can fail the render.

**Alternatives considered:**
- Hard-depend on Graphviz, D2, or `mermaid-cli`. Rejected because: a required
  binary breaks portability (and `mermaid-cli` drags in headless Chromium), in
  tension with the portable-runtime constraint.
- Inline a full offline Mermaid runtime in every artifact. Rejected because: it
  bloats each artifact with a large JS blob; kept only as a possible later
  enhancement.

**Chosen because:** an optional, runtime-probed enhancement gives nicer graphs
where the tool exists without ever making it a precondition, satisfying both
fidelity and the no-hard-dependency rule. The optional binary is dev-tooling,
so the dependency-adoption check records it rather than escalating.

### D-6: Reuse the existing critical-path computation  (C, the bootstrap spec)

**Decision:** the dependency-graph view computes the critical path by reusing
`scripts/orchestrate-select.sh`'s effort-weighted longest-dependent-chain logic
rather than recomputing it.

**Alternatives considered:**
- Recompute the critical path in the new skill. Rejected because: it duplicates
  logic that already exists, is unit-tested, and was specifically introduced to
  make critical-path claims verifiable rather than hand-asserted.

**Chosen because:** the orchestrator already ships a verified critical-path
computation; a comprehension view that highlights the critical path should read
the same source of truth the orchestrator selects against, not a parallel one
that could disagree.

### D-7: Styling — distinctive, MIT-licensed primitives, inlined  (N)

**Decision:** the HTML artifact is styled with redistributable, MIT-licensed
primitives (Tailwind CSS plus DaisyUI), with only the used CSS inlined for
offline rendering and the MIT notice included in the artifact. The "used CSS"
subset is curated and built once at plugin-ship time and committed to the
plugin; the skill inlines that static stylesheet at render, so no adopter
runtime build step is required (staying within D-5 / REQ-E1.3). Concrete
theme/component curation happens at implementation.

**Alternatives considered:**
- Custom hand-crafted components on Tailwind CSS alone. Rejected because: more
  to build and maintain for a comparable result; kept as a fallback if DaisyUI
  proves unsuitable.
- A lightweight semantic CSS system (Open Props / Pico). Rejected because: a
  thinner component layer for a graph- and card-heavy artifact; viable but less
  suited to the view set.
- Generic unstyled or minimal CSS. Rejected because: it fails the explicit goal
  of a distinctive artifact that does not look like every other generated page.

**Chosen because:** an MIT-licensed system is the only option that is both
distinctive and cleanly redistributable in planwright's installed-by-adopters
model, and inlining keeps the artifact offline and self-contained. A licensing
constraint (a paid component library cannot be redistributed inside a tool
others install) ruled out any non-redistributable source.

### D-8: Artifact location and provenance stamp  (N)

**Decision:** generated artifacts are written to `.claude/walkthroughs/<spec>/`,
gitignored, and each is stamped with the bundle it rendered and the commit it
was generated from.

**Alternatives considered:**
- `specs/<spec>/.comprehension/` co-located with the bundle. Rejected because:
  it lives inside `specs/`, where tracked files live, raising the accidental
  commit risk, and the name diverged from the command verb.
- A system temp directory. Rejected because: it is not shareable or findable
  after the session.

**Chosen because:** `.claude/walkthroughs/<spec>/` mirrors the existing
`.claude/worktrees/` scratch convention, is clearly ephemeral, is guessable
from the command name, and the provenance stamp lets a reader tell whether the
artifact is stale relative to the bundle.

### D-9: Teach-back delivered both in-artifact and in-session  (N)

**Decision:** the teach-back is delivered as a self-paced agree / disagree /
unsure checklist embedded in the HTML artifact, plus an optional in-session
walk through the same claims; both record the human's responses without
supplying a "right" answer.

**Alternatives considered:**
- In-artifact only. Rejected because: some readers want a guided pass; the
  optional in-session walk serves them.
- In-session only. Rejected because: it is not self-paced or shareable, and the
  agent's live presence risks subtly steering judgment.

**Chosen because:** the artifact checklist preserves the unaided, self-paced,
shareable independent read, while the optional in-session walk adds guidance for
those who want it — without either path supplying the answer.

### D-10: Read-only and status-agnostic  (N)

**Decision:** the command reads bundles in any status, including terminal
Retired and Superseded, and never mutates a bundle, the pipeline, or git state.

**Alternatives considered:**
- Restrict to non-terminal status, mirroring the execution skills' non-Active
  refusal. Rejected because: those refusals exist to prevent *acting* on an
  unsigned or withdrawn spec; rendering is read-only, so the safety rationale
  does not apply, and terminal bundles are valuable for archaeology.

**Chosen because:** a pure reading aid has no reason to refuse any bundle;
read-only plus status-agnostic maximizes usefulness while staying clear of every
reserved control.

### D-11: Sibling touchpoints suggest, never auto-invoke  (N)

**Decision:** `/spec-draft`'s handoff, `/spec-kickoff`'s pre-flight, and
`/resume` surface `/spec-walkthrough` as a recommended independent human step;
none auto-invokes it.

**Alternatives considered:**
- Auto-run a comprehension pass inside `/spec-kickoff`. Rejected because: it
  collapses the independence firewall (the authoring flow would comprehend its
  own spec) and violates the never-auto-chain invariant.
- No sibling references at all. Rejected because: the seed's core scenario (the
  pre-kickoff cold read) only happens if people know to run it; discoverability
  matters.

**Chosen because:** suggest-only is the only design that buys discoverability
without crossing the firewall or the no-auto-chain invariant; the human always
chooses to run the independent pass.

## Cross-cutting concerns

- **Independence is the through-line.** D-1, D-2, D-3, D-9, and D-11 each defend
  the same property from a different angle (standing apart from authoring,
  layering not rewriting, reading before prompting, the human filling the
  checklist, suggesting not invoking). A change to any one is a change to the
  firewall and should be weighed as such.
- **Portability and offline self-containment** bind D-4, D-5, D-7, and E-group
  requirements: the artifact must render for anyone with no install and no
  network, which is what rules out served apps, hard renderer dependencies, CDN
  styling, and non-redistributable component sources.
