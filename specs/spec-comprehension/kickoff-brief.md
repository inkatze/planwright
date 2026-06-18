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

### Task 1 — execution research & security pass (2026-06-16)

Appended by `/execute-task` (named-section brief write; not an anchor entry).

**Trigger.** Task 1 handles untrusted input (the spec-path argument) and path
handling (resolving `specs/<spec>`) — the `security-posture` write-time trigger
classes. Light research: the canonical in-repo posture, not a new pattern.

**Sources consulted.** `scripts/spec-validate.sh` (the canonical
framework-script: `check_spec_id`, the echo-discipline `first_header`,
C-locale pinning), the `security-posture` doctrine doc, and REQ-A1.6.

**Pass applied (no new risk surfaced).** Identifier charset-validated
(`^[a-z0-9][a-z0-9-]*$`, ≤64) **before** the string is ever used as a path;
the slash a multi-component or traversal path carries is outside the charset,
so the same check rejects `../x`, `a/b`, and `specs/a/b`. The resolved bundle
path is containment-checked against the real `specs/` tree (a symlink escaping
specs/ is refused). Hostile input is never echoed back and never becomes a
path (refusal is exit 2, distinct from content-level degradation at exit 1).
The scaffold writes nothing (read-only, REQ-A1.3). No risk beyond what the
register and REQ-A1.6 already anticipate; recorded for the audit trail.

### Task 2 — execution research & security pass (2026-06-17)

Appended by `/execute-task` (named-section brief write; not an anchor entry).

**Trigger.** Task 2 (the bundle reader model, `scripts/spec-model.sh`) reads
untrusted input (bundle file content) and produces a record stream downstream
views render into an HTML artifact — the `security-posture` write-time
untrusted-input and serialization trigger classes. Light pass: the in-repo
canonical posture, not a new pattern. No new dependency (the portability
envelope is unchanged: `/bin/sh` + `awk`).

**Sources consulted.** `scripts/spec-validate.sh` (the canonical format
parsers and the echo/locale discipline), `scripts/orchestrate-select.sh` (the
dependency-token extraction grammar), the `security-posture` doctrine doc, and
REQ-C1.7 / REQ-E1.7.

**Pass applied (no new risk surfaced).** The model treats all input as data:
no `eval`, no shell or path constructed from file *content* (only the four
fixed filenames under the already-gated spec directory are read), and the
identifier/path safety gate stays the command scaffold's job (REQ-A1.6). The
tab-separated record stream is hardened against content injecting phantom
columns or lines: every emitted field passes through `clean()`, which folds
control characters — including a literal tab (the delimiter) and any joined
continuation newline — to spaces under the pinned C locale, while bytes
≥ 0x80 are not `[[:cntrl:]]`, so multibyte UTF-8 (a `≤` threshold, an em dash)
survives verbatim (REQ-C1.7). The model carries text verbatim and does **not**
HTML/SVG-escape it: that is Task 6's artifact-assembly job (REQ-E1.7); the
model is the upstream substrate, and escaping at this layer would corrupt the
lossless text the reveal view restores. Read-only: the model writes nothing
(REQ-A1.3). The risk this adds to the register is the model↔validator grammar
drift recorded as a 2026-06-17 observation; no operational-data-hygiene risk
(the model emits no secrets — it echoes only bundle content, which the
artifact-layer data-hygiene check, REQ-E1.4, scans).

### Task 3 — execution research & security pass (2026-06-17)

Appended by `/execute-task` (named-section brief write; not an anchor entry).

**Trigger.** Task 3 (the plain-language translation layer,
`scripts/spec-translate.sh`) consumes untrusted input (the model record stream,
which carries bundle content) and re-serializes it into a tagged tab-separated
stream — the `security-posture` write-time untrusted-input and serialization
trigger classes. Light pass: the in-repo canonical posture, not a new pattern.
No new dependency (the portability envelope is unchanged: `/bin/sh` + `awk`,
the REQ-K1.5 floor); no new research trigger beyond the cross-audience
layered-view research already recorded under D-2 / §2.

**Sources consulted.** `scripts/spec-model.sh` (the upstream substrate and the
`clean()` / C-locale record-hygiene discipline this layer inherits),
`scripts/spec-walkthrough.sh` (the REQ-A1.6 identifier/path gate this layer
trusts rather than re-implements), the `security-posture` doctrine doc, and
REQ-C1.1 / REQ-C1.7 / REQ-D1.3 / REQ-E1.7.

**Pass applied (no new risk surfaced).** The translator treats all input as
data: no `eval`, and no shell or path is constructed from record *content* —
the only path it touches is its own sibling `spec-model.sh`, resolved from the
script's own directory (`dirname "$0"`), with the spec-directory argument
flowing through to the model unchanged (the identifier-charset and
path-containment gate stays the command scaffold's job, REQ-A1.6). In
`<spec-dir>` mode the model's exit code is captured and propagated so an
absent/unreadable bundle fails closed (exit 2), never a silent empty
translation. The TEXT/NORM stream stays tab-clean: the upstream model already
folded control bytes (including the delimiter) to spaces under the pinned C
locale, and this layer only removes identifier substrings and maps file names,
introducing no new tabs or newlines (the test asserts every TEXT record has
exactly five fields). The translator does **not** HTML/SVG-escape its text:
that is Task 6's artifact-assembly job (REQ-E1.7) downstream of this layer;
escaping here would corrupt the lossless verbatim text the reveal view restores
(D-2). Read-only: it writes nothing but its stdout stream (REQ-A1.3).

**Declared scoping (`proportionality`).** Two within-task scoping calls, both
low-stake and reversible, recorded rather than escalated:

- *Internal-vocabulary scrub (REQ-C1.1)* targets the contract's stated set —
  the four-file *names* and the REQ/D/task identifier *schemes* — not every
  filename or jargon term a bundle's prose may contain. Other artifact
  filenames a spec legitimately names (e.g. a doctrine doc) are content the
  `[manual]` readability half of REQ-C1.1 judges, not mechanical internal
  vocabulary. The test scopes its leak assertion to exactly the four bundle
  file names accordingly.
- *Normative-token marking (REQ-C1.7)* mechanically detects and marks the
  reliably-detectable classes: the RFC-2119 uppercase modals (MUST / SHALL /
  SHOULD / MAY, extended to `... NOT`) and a comparator-governed threshold
  (`≤ 64`). The *verbatim-survival* guarantee — the core guardrail — holds for
  **all** normative classes including enumerated states, because the
  conservative translation never softens text it does not scrub. The marking of
  the open-ended "enumerated state" class has no mechanical detector and is
  logged as an observation (below) for a future spec decision; it is a marking
  gap, not a verbatim-preservation gap.

### Task 4 — execution research & security pass (2026-06-17)

Appended by `/execute-task` (named-section brief write; not an anchor entry).

**Trigger.** Task 4 (the spec-at-a-glance one-pager view,
`scripts/spec-onepager.sh`) consumes untrusted input (the translate record
stream, which carries bundle content) and re-serializes a subset of it into a
tagged tab-separated stream — the `security-posture` write-time untrusted-input
and serialization trigger classes. Light pass: the in-repo canonical posture,
not a new pattern. No new dependency (the portability envelope is unchanged:
`/bin/sh` + `awk`, the REQ-K1.5 floor); no new research trigger beyond the
cross-audience layered-view and cold-read research already recorded under D-2 /
the one-pager→appendix sources in §2 (the "killer items" framing).

**Sources consulted.** `scripts/spec-translate.sh` (the upstream substrate and
the `clean()` / C-locale record-hygiene discipline this layer inherits, and the
sibling-script resolution pattern for `<spec-dir>` mode),
`scripts/spec-model.sh` (the REQ / REQCITE / TASKCITE record vocabulary the
load-bearing score reads), the `security-posture` doctrine doc, and REQ-C1.2 /
REQ-C1.1 / REQ-D1.3.

**Pass applied (no new risk surfaced).** The renderer treats all input as data:
no `eval`, and no shell or path is constructed from record *content* — the only
path it touches is its own sibling `spec-translate.sh`, resolved from the
script's own directory (`dirname "$0"`), with the spec-directory argument
flowing through to the upstream chain unchanged (the identifier-charset and
path-containment gate stays the command scaffold's job, REQ-A1.6). In
`<spec-dir>` mode the upstream exit code is captured and propagated so an
absent/unreadable bundle fails closed (exit 2), never a silent empty render.
The one-pager stream stays tab-clean: the plain and source columns are carried
verbatim from the upstream TEXT/REQ records, which the model already folded
control bytes (including the delimiter) to spaces under the pinned C locale;
this layer introduces no new tabs or newlines (the test asserts every ONEPAGER
record has exactly seven fields and the frame eight). The view does **not**
HTML/SVG-escape its text: that is Task 6's artifact-assembly job (REQ-E1.7)
downstream of this layer; escaping here would corrupt the lossless verbatim text
the reveal view restores (D-2). The default plain column carries the
translation layer's audience-neutral rendering (internal vocabulary scrubbed,
REQ-C1.1), with the verbatim source retained as the reveal seam (REQ-D1.3).
Read-only: it writes nothing but its stdout stream (REQ-A1.3).

**Declared scoping (`proportionality`).** Two within-task scoping calls, both
low-stake and reversible, recorded rather than escalated:

- *Killer-item selection (REQ-C1.2)* uses one declared heuristic — **inbound
  citation/dependency-edge count** as the load-bearing proxy: the more of the
  bundle's own `TASKCITE`/`REQCITE` edges point at a requirement, the more
  structurally load-bearing it is. On the real bundles this surfaces the right
  claims (spec-comprehension's top three are the reveal toggle REQ-D1.3, the
  scope/blast-radius REQ-B1.2, and the precision guardrail REQ-C1.7). The
  *quality* of the selection is the `[manual]` half of REQ-C1.2's verification;
  a richer killer-item signal is logged as a drain-loop observation. This is a
  decision in the uncatalogued human-comprehension / information-UX domain (the
  catalog gap already recorded 2026-06-16), so it is an observation, not an
  escalation.
- *The at-a-glance length bound (REQ-C1.2)* — `KILLER_MAX=3` foregrounded items,
  `SHOWN_MAX=9` total claims — is a sensible default, not a contract number:
  the brief (§2) records the bound as "deliberately unquantified, manual-judged."
  The frame surfaces `shown`-of-`live` so the omitted long tail is never a
  silent truncation. Claims are the bundle's *live* requirements; superseded
  requirements are not current claims, and decisions/tasks have their own views.

### Task 5 — execution research & security pass (2026-06-17)

Appended by `/execute-task` (named-section brief write; not an anchor entry).

**Trigger.** Task 5 (the teach-back challenge view, `scripts/spec-teachback.sh`)
consumes untrusted input (the translation record stream, which carries bundle
content), reads `requirements.md` from the spec directory for section labels,
and re-serializes a tagged tab-separated stream — the `security-posture`
write-time untrusted-input, path-handling, and serialization trigger classes.
Light pass: the in-repo canonical posture, not a new pattern. No new dependency
(the portability envelope is unchanged: `/bin/sh` + `awk`, the REQ-K1.5 floor);
no new research trigger beyond the teach-back evidence base (clinical
chunk-and-check) already recorded under D-3 / D-9 / §2.

**Sources consulted.** `scripts/spec-translate.sh` (the upstream layer this view
reads and the `printf '%s'` empty-in/empty-out stream discipline it inherits),
`scripts/spec-model.sh` (the `clean()` / C-locale record hygiene and the
trailing-slash + `readable_file` read gate this layer mirrors for its
`requirements.md` read), `scripts/spec-walkthrough.sh` (the REQ-A1.6
identifier/path gate this layer trusts rather than re-implements), the
`security-posture` doctrine doc, and REQ-C1.5 / REQ-D1.1 / REQ-D1.4 / REQ-E1.7.

**Pass applied (no new risk surfaced).** The view treats all input as data: no
`eval`, and no shell or path is constructed from record *content* — the only
paths it touches are its own sibling `spec-translate.sh` (resolved from
`dirname "$0"`) and the fixed `requirements.md` under the spec directory
(read only when it is a readable regular file, the model's gate), with the
spec-directory argument flowing through to translate/model unchanged (the
identifier-charset and path-containment gate stays the command scaffold's job,
REQ-A1.6). In `<spec-dir>` mode the translate chain's exit code is captured and
propagated so an absent/unreadable bundle fails closed (exit 2), never a silent
empty view. The emitted RESPONSE/SECTION/CLAIM stream stays tab-clean: every
text field is copied verbatim from the upstream layers, which already folded
control bytes (including the delimiter) to spaces under the pinned C locale, and
the group-title extraction folds control bytes and strips the leading separator
byte-wise; the view introduces no new tabs or newlines (the test asserts CLAIM
records have exactly six fields, SECTION four, RESPONSE two). The view does
**not** HTML/SVG-escape its text: that is Task 6's artifact-assembly job
(REQ-E1.7) downstream of this layer; escaping here would corrupt the lossless
verbatim source the reveal view restores (D-2). The independence firewall is
structural, not a check that could be bypassed: the view has no column where a
verdict, score, or "right answer" could live, so it cannot supply one (REQ-D1.1,
REQ-C1.5); the in-session divergence-surfacing hands the judgement to the human
(REQ-D1.4). Read-only: it writes nothing but its stdout stream (REQ-A1.3).

**Declared scoping (`proportionality`).** Two within-task scoping calls, both
low-stake and reversible, recorded rather than escalated, and consistent with
the accepted decisions (no decision-domains escalation):

- *Claim set definition (D-3, D-9; Done-when "claims").* A claim is a live
  requirement or a decision — the bundle's normative and design *assertions*,
  the things a reader agrees or disagrees with. Superseded requirements (history,
  not current claims), tasks (the execution plan, not assertions), and test-spec
  entries (verification paths) are deliberately not claims. This keeps the
  teach-back a comprehension check over what the spec *asserts*, complementing
  the one-pager's killer-item foregrounding (Task 4). The same single extractor
  feeds both the in-artifact checklist and the in-session walk, so the two paths
  cover the same claim set by construction (Done-when #4), independent of this
  scoping.
- *Section labels (REQ-C1.5 "section by section").* In `<spec-dir>` mode — the
  real pipeline path — section labels are the plain requirement-group heading
  titles read from `requirements.md` (audience-neutral by spec convention, no
  identifier scheme). In the composable stdin mode the headings are not in the
  stream, so labels fall back to a generic plain phrase; the *claim set* (the
  load-bearing contract) is identical in both modes, only the section labels
  differ. The split mirrors the in-artifact / in-session delivery split the
  brief §3 recorded for REQ-D1.4.

### Task 6 — execution research & security pass (2026-06-17)

Appended by `/execute-task` (named-section brief write; not an anchor entry).

**Trigger.** Task 6 (the HTML assembly layer, `scripts/spec-assemble.sh`, plus
the `scripts/spec-walkthrough.sh` artifact write) consumes untrusted input (the
one-pager and teach-back record streams, which carry bundle content), runs the
sibling view scripts as subprocesses, **serializes that content into an HTML/SVG
document**, and writes the document to a path — the `security-posture` write-time
untrusted-input, subprocess, serialization, and path-handling trigger classes
all at once. Unlike the upstream layers, Task 6 is the layer where the
output-encoding security work actually lands (REQ-E1.7 is its defining
requirement), so the pass here is focused, not light. No new dependency (the
portability envelope is unchanged: `/bin/sh` + `awk`, the REQ-K1.5 floor); the
styling primitives (Tailwind CSS, DaisyUI) are MIT-licensed and inlined, not a
runtime dependency.

**Sources consulted.** `scripts/spec-onepager.sh` and `scripts/spec-teachback.sh`
(the upstream views this layer assembles, and the documented contract that each
carries bundle text *verbatim* and defers escaping to this layer so the reveal
seam stays lossless, D-2), `scripts/spec-translate.sh` / `scripts/spec-model.sh`
(the `clean()` / C-locale record-hygiene discipline that folds control bytes —
including the tab delimiter — to spaces, so a tab-clean stream reaches this
layer), the `security-posture` doctrine doc, the canonical HTML output-encoding
guidance (the five-character context-aware escape set `& < > " '`, ampersand
first), and REQ-E1.7 / REQ-E1.4 / REQ-E1.1 / REQ-E1.2.

**Pass applied (the escaping is the security core — no residual risk surfaced).**
Output encoding is centralized at the assembly boundary: every bundle-derived
field — the one-pager plain/ref/source columns, the teach-back claim plain/ref/
source and section labels, and the head's spec/status/commit values — passes
through an `esc()` (HTML-escaping `&` first, then `< > " '`, with `\047` keeping
the apostrophe out of the single-quoted `awk` source) before it reaches the
document. The five-character set covers both contexts a bundle value can land
in: HTML text and double-quoted attribute values. Bytes ≥ 0x80 (a multibyte ≤
threshold, an em dash) are passed through escaping untouched under the pinned C
locale, so normative tokens survive verbatim (REQ-C1.7) while still displaying
as literal text. **Defense in depth:** the artifact ships **no executable
JavaScript** (the reveal toggle is a pure-CSS `:checked` sibling rule), so even a
hypothetical escape miss has no script-execution context to land in; and no
bundle content is ever interpolated as a `printf` format string (every dynamic
value is a `%s` argument, never the format) or into a shell/`eval`/path
constructed from content. The document references **no external network
resource** (no URL, no web font, no `@import`, no external stylesheet) — it is
offline and self-contained (REQ-E1.2). Artifact data-hygiene holds: the file
carries only bundle content and a short commit hash (no secrets, credentials, or
internal hostnames), is written to the gitignored `.claude/walkthroughs/<spec>/`
location (REQ-E1.1), and the test suite runs `gitleaks` directly over a
generated artifact (REQ-E1.4). The provenance commit is derived read-only
(`git rev-parse --short HEAD`, env-overridable for a deterministic stamp); the
sibling subprocesses receive only the already-gated spec-directory argument (the
identifier-charset and path-containment gate stays the command scaffold's job,
REQ-A1.6), and their fail-closed exit codes propagate so an absent/unreadable
bundle never yields a silent half-document.

**Declared scoping (`proportionality`).** Two within-task scoping calls, both
low-stake and reversible, recorded rather than escalated, and consistent with
the accepted decisions (no decision-domains escalation):

- *Escape-context coverage (REQ-E1.7).* The five-character escape covers the two
  contexts bundle content reaches today: HTML text and double-quoted attributes.
  No bundle content enters a CSS context (the stylesheet is static and curated)
  or a URL/`href` context (none is emitted from content). When the inline-SVG
  diagram views land (Task 7), bundle text rendered inside SVG sits in SVG text /
  attribute contexts, which the same five-character set covers; a dedicated SVG
  pass rides that task. The escaping is verified by a markup-bearing fixture
  (`<script>`, an `onerror` handler, raw `< & "`, the `<spec>` placeholder) that
  asserts the literal characters survive as entities and no live markup from
  bundle content appears in the output.
- *Artifact scope (D-4, REQ-E1.1).* The Task 6 MVP artifact is the whole-bundle
  one-pager plus teach-back; the drawn graph/decision-map views and partial-scope
  rendering layer onto this same assembly in later tasks. The scaffold writes the
  whole-bundle artifact on any successful load; scope-limited artifacts are the
  scope/stage task's job, recorded so the current whole-bundle behavior is not
  mistaken for a gap.

### Task 7 — execution research & security pass (2026-06-17)

Appended by `/execute-task` (named-section brief write; not an anchor entry).

**Trigger.** Task 7 (the dependency-graph view, `scripts/spec-graph.sh`, plus a
new `--critical-path` mode on `scripts/orchestrate-select.sh` and the inline-SVG
rendering in `scripts/spec-assemble.sh`) consumes untrusted input (bundle task
titles, which become SVG `<text>` labels), runs a sibling subprocess and the
**optional `dot` (Graphviz) binary**, serializes a record stream and an SVG
document, and probes the runtime for an external tool — the `security-posture`
write-time untrusted-input, subprocess, serialization, and path-handling trigger
classes. Focused pass, since this is the layer where the SVG output-encoding and
the runtime-probe degradation actually land (REQ-C1.3, REQ-C1.6, REQ-E1.3).

**Sources consulted.** `scripts/orchestrate-select.sh` (the effort-weighted
longest-dependent-chain `crit()`/`weight()` computation this task reuses rather
than recomputes, D-6; the existing selection mode is preserved byte-for-byte and
the critical-path mode is additive), `scripts/spec-model.sh` (the TASK / TASKDEP /
TASKFIELD-effort record vocabulary and the `clean()` / C-locale tab-hygiene the
graph view inherits), `scripts/spec-assemble.sh` (the `esc()` five-character
HTML/XML escape — `& < > " '`, ampersand first — which the same set covers in SVG
text/attribute contexts, per the Task 6 §7 scoping note that a dedicated SVG pass
rides this task), the `security-posture` doctrine doc, the Graphviz `dot -Tplain`
output format (the stable `node <name> <x> <y> …` line shape, coordinates in
inches, origin bottom-left — used read-only for layout only), and REQ-C1.3 /
REQ-C1.6 / REQ-E1.3 / REQ-E1.7 / REQ-C1.1.

**Pass applied (no new risk surfaced).** Output encoding stays centralized at the
assembly boundary: SVG node labels are bundle task titles carried verbatim
through the model and escaped by the assembler's `esc()` before they reach the
`<text>` element, exactly as the one-pager/teach-back fields are; the artifact
still ships **no executable JavaScript** and the SVG contains no `<script>` or
`<foreignObject>`, so there is no script-execution context even on a hypothetical
escape miss. **Graphviz is treated as untrusted and never load-bearing:** only the
numeric task ids (charset `^[0-9]+(\.[0-9]+)?$`) are passed to `dot` as node
names — never the free-text titles — so no bundle text can inject DOT syntax; the
graph view reads back only node *coordinates* from `dot -Tplain` and **validates
every coordinate is numeric** before use, discarding the whole `dot` result and
falling back to the built-in layout on any malformed/missing field, non-zero
exit, or absence (D-5: a failed invocation degrades identically to absence, and
`dot` is never on a path that can fail the render — REQ-E1.3). No shell, `eval`,
or path is constructed from record or `dot` content; the only paths touched are
the sibling scripts resolved from `dirname "$0"` and the already-gated
spec-directory argument flowing through to the model/selector (the
identifier-charset and path-containment gate stays the command scaffold's job,
REQ-A1.6). The record stream stays tab-clean (the model already folded control
bytes, including the delimiter, to spaces under the pinned C locale; coordinates
and the critical flag are numeric). Read-only: the graph view and the new
selector mode write nothing but their stdout streams (REQ-A1.3). Artifact
data-hygiene holds — the SVG carries only bundle task titles and computed
geometry, no secrets or hostnames — and the existing gitleaks-over-the-artifact
check (REQ-E1.4) covers it.

**Declared scoping (`proportionality`).** Two within-task scoping calls, both
low-stake and reversible, recorded rather than escalated, and consistent with the
accepted decisions (no decision-domains escalation):

- *Critical-path reuse semantics (D-6, REQ-C1.3).* The reused computation is
  `orchestrate-select.sh`'s `weight()`/`crit()` longest-dependent-chain logic,
  exposed through an additive `--critical-path` mode in the same file so there is
  a single source of truth (no parallel computation to drift). The mode computes
  the chain over the **full** task DAG (all sections), which is the structural
  critical path the bundle's own `tasks.md` build-order note describes
  (T1→T2→T3→T5→T6→T7→T11, ≈12.5 days); the selection mode's terminal-task
  exclusion is a "remaining work" filter specific to *dispatch*, deliberately not
  applied to the *visualization*. On a bundle with nothing completed the two
  coincide. The view highlights exactly the ids the mode emits, so REQ-C1.3's
  "matches the reused computation" holds by construction. This inherits
  `orchestrate-select.sh`'s known quirks (risk row 4), as the brief anticipated.
- *Graphviz enhancement depth (D-5).* `dot` enhances *layout only* (node
  coordinates); planwright always renders its own escaped, styled inline SVG, so
  the artifact is byte-for-byte self-contained and offline whether or not `dot`
  was present at generation time, with only the layout differing and a one-line
  in-artifact note recording which path was taken. `dot` is absent on this host
  and in CI, so the built-in layout is the exercised default; the `dot`-present
  success branch is `command -v dot`-gated in the tests (the gitleaks pattern),
  while the absent and present-but-failing degradation branches — the REQ-E1.3
  contract — are exercised deterministically via a stubbed PATH.

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

### 2026-06-16 — delta re-walkthrough (meaning)

**Trigger.** Freshness gate mismatch: the first-activation anchor
(`eaebcebe874c7d2aa981326e1cbf28f83476e3cc`) no longer matched the bundle.
Delta derived from the four spec files' git history since sign-off plus the
two deferred `/copilot-pairing` review threads on PR #26.

**Delta walked (scope confirmed with the human):**

- *Already committed, derived-prose / citation only (no requirement meaning
  changed):* the effort-weighted critical path extended `… → T7 (≈10.5d)` →
  `… → T7 → T11 (≈12.5d)` in `tasks.md` + brief (T11 depends on T7);
  the `REQ-F1.3` citation dropped from Task 10 (`tasks.md`: D-11 → REQ-F1.2
  per the decision-map ledger; REQ-F1.3 maps to D-10) — both from the
  `/panel-review` correction (`1f7ff2a`); and the `gitleaks` example in the
  `requirements.md` changelog corrected to the valid
  `gitleaks detect --no-git --source <path>` form (`/copilot-pairing` iter 2,
  `97819fd`).
- *Applied this re-walkthrough (meaning-class additions):* `test-spec.md`
  synced to two REQ meanings the first-activation lens pass had extended
  (brief findings F3, F2) but never mirrored into verification —
  **REQ-A1.5** now covers a charset-valid scope selector that resolves to
  nothing (clear message naming available scopes, never opaque/empty), and
  **REQ-E1.3** now covers a present-but-failing renderer (non-zero exit,
  timeout, or invalid output) degrading the same as absence. Bundle
  changelog entry recorded.

**Lens pass (delta-scoped, walked inline — small narrow delta).** Canonical
lens table emitted in the run; all dispositioned. Applied: 2 test-spec
coverage additions (REQ-A1.5, REQ-E1.3) + 1 changelog entry. Confirmed: the
three already-committed derived/citation corrections (critical-path
arithmetic 10.5+2=12.5 and Task 11 deps incl. 7 verified; REQ-F1.3 drop
internally consistent with the ledger). Dead-path sweep: all 32 defined REQs
have a `test-spec.md` entry; no remaining dead paths. No inconsistency halt.

**Validation.** Validator (Active enforcement): 0 errors, 0 warnings.
markdownlint: 0 errors. `Last reviewed:` already 2026-06-16 on all four files
(same-day re-walk).

Class: meaning
Lens-pass: recorded above (this entry), delta-scoped, findings dispositioned 2026-06-16.
Anchor: `613e19c554bda9704aa0b6878f65fc50d7d59d18` — computed as
`scripts/spec-anchor.sh specs/spec-comprehension`
