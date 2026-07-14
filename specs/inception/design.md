# Inception — Design

**Status:** Ready
**Last reviewed:** 2026-07-13
**Format-version:** 1

Origin tags: `N` = new decision minted in this bundle. Research citations name the session
research reports (see `requirements.md` Sources) with the load-bearing primary sources inline.

## Decision log

### D-1: The inception bundle is a sibling format, not a reuse of the four-file spec format  (N)

**Decision:** The bundle (`brief.md`, `disciplines.md`, `assumptions.md`, `decisions.md`,
`plan.md`, plus `spikes/` and `exports/`) is defined normatively in a new `inception-format`
doctrine doc, format-versioned from birth, inheriting the meta-spec's conventions (stable IDs,
append-only supersession, status headers, changelog, sources register) without its files. The
format evolves additively within a major version (new fields and sections optional, existing
fields never renamed or repurposed); readers gate on the `Format-version:` header and fail closed
on an unsupported version (REQ-C1.7, enforced via D-12), so a bundle authored by one plugin
version is never silently misparsed by another, and a breaking change increments the major
version and owns its migration path.

**Alternatives considered:**
- Reuse `requirements/design/tasks/test-spec` with venture semantics bolted on. Rejected because:
  the decision shapes differ; falsifiable assumptions with thresholds and evidence grades, open
  forks with owners, and kill criteria do not map onto REQ/D-ID semantics without abuse.
- Freeform markdown per venture. Rejected because: nothing to validate, render, or gate against.

**Chosen because:** the prior-art sweep, re-checked adversarially (2026-07-10), found no existing
format that composes the triad as first-class artifacts — an evidence-graded assumption register, a
standalone decision *backlog* (open decisions, not just a log of taken ones), and a thresholded
validation plan — at venture scope and git-native. The nearest misses are feature-scoped or
partial: speckit-product-forge composes a discovery gate + decision *log* + hypothesis list but
keeps assumptions narrative and lives inside an existing codebase; GLIDR AI composes
hypotheses + experiments + success definitions but has no decision backlog and is a hosted SaaS
canvas. Sharing the meta-spec's conventions keeps validator and tooling patterns reusable while
keeping each format honest about its domain.

### D-2: Fan-out topology: parallel seats, single synthesis, one premortem challenge pass  (N)

**Decision:** Seats run independently in parallel over the same frame with no inter-seat
communication; a single synthesis writer merges with a mandatory agreements / tensions /
open-questions table and per-claim convergence marks; exactly one challenge pass follows
(premortem plus key-assumptions check, seeing synthesis and frame only); synthesis may amend once.
RAPID encoding: seats I, synthesizer R, challenger risk-scoped A, human D. Seat outputs reach the
synthesis writer anonymized and order-shuffled; the orchestrator (which holds the seat↔label map)
re-attaches attribution into the human-facing table after synthesis, the writer working blind. The
synthesis and challenge steps run persona-free (plain task instructions); persona framing aids
generative coverage but degrades discriminative judgment. Convergence marks are a weak,
inflation-prone signal — annotated by claim type (extractive versus interpretive), with outlier
seats named rather than averaged, never presented as a calibrated probability.

**Alternatives considered:**
- Live multi-round debate. Rejected because: debate homogenizes and fails to beat
  self-consistency at matched compute (Smit et al., ICML 2024,
  <https://proceedings.mlr.press/v235/smit24a.html>; convergent 2025 replications), with documented
  conformity failures.
- Sequential pipeline (each seat reads the prior seat). Rejected because: anchoring; the
  read-heavy regime is where parallel-then-synthesize is proven (Anthropic orchestrator-worker
  +90.2%, <https://www.anthropic.com/engineering/built-multi-agent-research-system>;
  Mixture-of-Agents, <https://arxiv.org/abs/2406.04692>).
- A standing devil's-advocate seat. Rejected because: assigned dissent triggers bolstering and
  human discounting (Nemeth et al. 2001); prospective hindsight is the evidenced skeptic format
  (Mitchell/Russo/Pennington 1989 via Klein).

**Chosen because:** the only topology every strong result supports; MASS
(<https://arxiv.org/abs/2502.02533>) shows seat-prompt quality dominates topology cleverness, so
the design invests in cards and keeps the topology simple. A 2026 result (arXiv:2606.02646,
re-verify at build time) adds convergent support: debate gains track re-evaluation more than peer
influence, and model-family diversity is the main lever that escapes saturation, so 3–5 diverse
seats plus one challenge-then-amend pass captures the available gain without a debate loop. Known
tension (revisit-when): a separate critic can add gains over 3–5 rounds; v1 caps at one amendment,
trading a small residual gain for loop-safety, and if that cap is revisited the evidenced shape is
confidence-gated escalation (debate only on low-confidence claims), not a fixed loop.

### D-3: Cards are task-framings compiled to dispatchable seat briefs  (N)

**Decision:** Card schema: name/description, one operational role sentence, mandate (3–7 first
questions, each answerable only against this venture's frame), frameworks ordered into a working
sequence with misuse caveats, grounding requirements naming the concrete evidence sources the seat
must consult, input subscription, artifact template with done-when, capability boundary (tier +
per-activity exceptions + an out-of-scope line), escalation contract, register rules, anti-patterns
for the synthesizer, documented blind spots, conflict / deference rules, an optional stance axis
(optimist–skeptic) orthogonal to discipline, RAPID letters, bench flag with pull-in triggers,
staleness metadata (reviewed date + rot rate), optional model/effort override. Explicitly
excluded: backstories, personalities, credentials, debate configuration, any auto-decide
authority.

**Alternatives considered:**
- Role/goal/backstory personas (CrewAI-style). Rejected because: identity personas show null
  objective-accuracy benefit on modern models (Zheng et al., <https://arxiv.org/abs/2311.10054>;
  Wharton replication, <https://arxiv.org/abs/2512.05858>) and authority styling increases
  uncritical human acceptance (Bansal et al., <https://arxiv.org/abs/2006.14779>).
- One mega-prompt per discipline without schema. Rejected because: specification defects are the
  dominant multi-agent failure class (MAST, <https://arxiv.org/html/2503.13657v2>); the schema
  fields each target a measured failure mode.

**Chosen because:** the evidence-ranked quality levers are grounding, tool access, and structured
decomposition, not persona framing; the card form follows Gawande's checklist prescription
(pause-point questions and refuse-without-data gates, not step-by-step scripts).

### D-4: Capability boundaries: three tiers, per-activity, enforced by output shape  (N)

**Decision:** Tiers agent-senior / structure-only / human-authority, defaulted per card with
per-activity exceptions; one-way-door decisions are always human ("agents may close two-way
doors; only humans close one-way doors"); enforcement is structural: mandatory "Decisions I
cannot make" sections, hypothesis/briefing grammar by tier, forced structured choices at the
human gate. Default placements: software engineering and AI-architecture agent-senior; product
strategy, pricing, org design structure-only; IP human-authority (the unauthorized-practice
line). The capability boundary carries an explicit out-of-scope negative line (what the seat must
not opine on); escalation triggers are typed, not prose (irreversibility / missing-domain-authority
/ confidence-floor / contract-policy-change), each naming the receiving human's power (disregard /
override / reverse / halt); a seat cannot validate its own discipline's claims (a card property),
and the persona-free challenge pass needs no per-discipline standing.

**Alternatives considered:**
- Per-discipline labels. Rejected because: the capability frontier is jagged within disciplines
  (Dell'Acqua et al., HBS WP 24-013: +40% quality inside the frontier, 19 points worse outside).
- Disclaimers and warnings. Rejected because: empirically decayed (medical warnings in model
  outputs fell from >26% to <1%, 2022–2025) and behaviorally weak; cognitive forcing functions
  are what measurably reduce overreliance (Buçinca et al., <https://arxiv.org/abs/2102.09692>).
- No boundary machinery. Rejected because: outside-frontier use degrades human decisions; an
  unbounded table is harmful, not merely imperfect.

**Chosen because:** the boundary is the feature's safety architecture; every regulated profession
converged on "AI drafts, a named human signs", and the spec records that the escalation-section
mechanism is extrapolated from that plus the forcing-function literature (no direct RCT).

### D-5: Git repo as sole truth with a three-rung degradation ladder  (N)

**Decision:** Venture truth lives in a git repository (created under `ventures_root`, ask-once
private-remote or local-only, hygiene-scaffolded); degradation ladder: repo → plain folder →
session-only-warned; git is fully wrapped in non-engineer mode and standard in expert mode.

**Alternatives considered:**
- Notion or Google Drive as native truth. Rejected because: forfeits IDs, history, diffs, CI, and
  orchestration; every surveyed round-trip tool degrades to git-canonical anyway.
- Hybrid dual-write mirror. Rejected because: documented failure trio — lossy conversion, phantom
  diffs, unresolvable concurrent edits.

**Chosen because:** the only substrate preserving planwright machinery; the ladder plus wrapping
answers the non-engineer adoption barrier without a second substrate; a git remote is the one
persistence mechanism working identically across Claude Code CLI, desktop, web, and Cowork.

### D-6: Human gates live in the main conversation  (N)

**Decision:** Gate 1 (frame + staffing confirmation, with cost and backend disclosed) and Gate 2
(silent-read table review, forks and human-authority items as structured forced choices) run in
the main thread; seats return escalations in their artifacts or via the orchestrator relay. Each
escalated human-authority item at Gate 2 names the human's available power over it (disregard /
override / reverse / halt), per the typed escalation contract (D-4).

**Alternatives considered:**
- Seats prompting the human directly. Rejected because: not available on the subagent rung
  (platform constraint) and undesirable everywhere (uncoordinated interruptions defeat the
  forcing-function design).
- No Gate 1. Rejected because: the frame is the specification every seat consumes; specification
  defects dominate multi-agent failures (MAST 41.8%).

**Chosen because:** platform constraint aligned with the evidence: concentrate decisions at gates
the human actively answers.

### D-7: Seats dispatch through the existing backend capability contract  (N)

**Decision:** Persona seats and venture tasks dispatch through the same backend capability
contract `/orchestrate` uses (tmux / subagent / in-session / print, capability advertisement,
degradation ladder). tmux-rung seats are full Claude Code instances (observable, steerable,
per-seat model/effort); subagent is the baseline; in-session approximates independence per the
dispatch-isolation doctrine; print emits seat briefs for manual execution. Relay is
orchestrator-to-seat only; inter-seat communication stays forbidden on every rung. Backend choice
is part of the Gate 1 disclosure. A stake / reversibility-scored triage SHOULD inform the seat
count within the 3–5 band when the signal is cheap (defaulting to three otherwise); per-seat
model/effort override is exercised where the backend already advertises it (model-family diversity
is the strongest decorrelation lever), and the lost decorrelation is reported as a degradation
where it cannot.

**Alternatives considered:**
- Hardcode subagents. Rejected because: forfeits heterogeneity, observability, and steering where
  the host offers them, and contradicts the advertised-capability doctrine.
- tmux only. Rejected because: breaks every host without a multiplexer; degrade capability, never
  safety.
- A bespoke seat-runner protocol. Rejected because: the backend contract exists so consuming
  skills do not mint parallel dispatch systems; the existing-seam-reuse rule this bundle adds to
  the catalog (REQ-I1.2) exists because this decision was nearly missed.

**Chosen because:** reuses a paid-for seam; upgrades seat quality exactly where evidence locates
quality (grounding tools, model heterogeneity); empirically validated by this bundle's own
drafting session (two research workers ran as tmux-hosted Claude instances).

### D-8: Registry, telemetry, and feedback drop live in the plugin data directory, interim  (N)

**Decision:** One machine-local home (`CLAUDE_PLUGIN_DATA`) holds the venture registry (id, path,
status, attention flags), catalog telemetry (frame-derived disciplines, unstaffed occurrences),
and a pending-observations drop for planwright-about learnings surfaced in venture repos;
planwright-repo `/spec-draft` and bookkeeping read the drop as a seed source with neutralization.
Registry mutations are atomic (write-temp-then-rename) so no session reads a torn registry; a lost
update from a rare concurrent race is tolerated because the scan-rebuild (REQ-A1.6) re-discovers
ventures from `ventures_root` — that scan is the recovery path for a corrupt, lost, or clobbered
registry. Recorded as interim: re-anchors on the `observation-routing` effort when it revives,
the same supersession ritual the output-hygiene carve-out demonstrated.

**Alternatives considered:**
- Cross-repo git routing now. Rejected because: that is `observation-routing`'s deferred domain;
  re-solving it from a corner would fork the design space observation-recording just cleaned up.
- No registry. Rejected because: no portfolio view, no overlap detection, no demand telemetry —
  and the catalog epistemics (REQ-P1.11) depend on the telemetry.
- Committed telemetry in the planwright repo. Rejected because: venture names and disciplines are
  potentially sensitive; machine-local only.

**Chosen because:** zero new substrate (`CLAUDE_PLUGIN_DATA` is the sanctioned cross-repo state
home), and the interim positioning is recorded rather than implicit.

### D-9: The renderer extends the spec-comprehension pattern  (N)

**Decision:** A deterministic POSIX-shell renderer (sibling of `spec-assemble.sh`, sharing
consolidated helpers such as the escaper) parses the inception format per its doctrine definition
and emits a self-contained, escaped, offline HTML export with two modes: dashboard-first status
view and pitch narrative. It is the export's named refresh owner, regenerated on every
bundle-changing commit via a scaffolded pre-commit step (REQ-A1.9) so out-of-session edits
(expert-mode manual commits, Cowork edits) refresh the export on every rung, not only in-session
or under CI; the hook stages the regenerated export on success and warns without blocking the
commit on a render failure, staging only the export path to avoid the git-add-in-hook
partial-commit trap. Artifact publish is a separate, always-confirmed step with a per-venture
opt-in auto-republish knob (default off).

**Alternatives considered:**
- LLM-written HTML per export. Rejected because: nondeterministic, token-costly, and can say
  things the bundle does not.
- Reusing `spec-assemble.sh` directly. Rejected because: it parses the four-file grammar, not
  this one; shared helpers only.
- A JS application artifact. Rejected because: violates the no-heavyweight-runtime precedent and
  the Artifact CSP.

**Chosen because:** proven pattern in-repo; determinism is what makes regenerate-on-commit and CI
verification honest.

### D-10: The adapter seam is one-way-per-cycle with human-triaged untrusted feedback  (N)

**Decision:** Cycle: export snapshot → harvest feedback as data (Notion unresolved comments via
REST, PR comments) → per-item human triage (apply / skip / modify) → agent implements accepted
items as attributed commits citing their source → re-export. Notion is the v1 reference adapter
(machine-local integration token). Re-import patches at section granularity; IDs and gate records
are untouchable. Notion's comment API is unresolved-only, with no resolved field, no text-range
anchor, and no resolve-via-API, so the repo triage ledger is the only record of item disposition;
the adapter pins a Notion API version (breaking version churn is documented) and uses the Notion
Markdown Content API to cut export lossiness (a platform claim re-verified at build time). Google Docs and SharePoint adapters are deferred (see
`tasks.md`), and Outline is added to the deferred list as the only surveyed tool with markdown
round-trip, resolve-via-API, and text anchors (self-hostable, limited stakeholder reach); Coda is
rejected outright (no comments API; also since rebranded under Superhuman).

**Alternatives considered:**
- Symmetric file synchronization. Rejected because: the surveyed failure trio (lossy conversion,
  phantom diffs, no concurrent-edit resolution) maps directly onto planwright's ID and anchor
  machinery.
- Auto-applying harvested feedback. Rejected because: stakeholder text is adversarial-capable
  untrusted input, and stakeholders are not authorities over the bundle.
- Google Docs as the reference adapter. Deferred for v1, not rejected: it has the richest comment
  model (resolved status, anchors, API resolve) and its auth is lighter than first assumed — the
  `drive.file` scope covers app-created files and needs no CASA assessment for the
  export-then-harvest cycle (a GCP project + OAuth consent screen is still required). Strong v2
  candidate; the seam keeps the per-venture choice open.

**Chosen because:** every surviving two-way tool in the wild degrades to exactly this shape; the
human-triage step matches the acceptance discipline everything else in the bundle uses.

### D-11: The Cowork bridge is an instructions file, not an integration  (N)

**Decision:** Venture repos ship a sync-protocol instructions file (the file Cowork's agent reads
in the folder): read freely; edits as commits with plain-language messages; pull before edit,
push after; never alter IDs, register statuses, or gate records — propose those as notes for the
operator. The scaffold also imports the protocol from the venture's root `CLAUDE.md` (the file
Cowork honors today), hedging against Cowork's undocumented filename contract; the protocol
instructs Cowork's own agent to degrade gracefully when egress blocks push/pull (commit locally,
tell the operator) — planwright cannot intercept Cowork's git client, so this stays advisory, with
the D-12 validator guard plus git history as the actual enforcement, not the instructions file.

**Alternatives considered:**
- Waiting for a Cowork orchestration API. Rejected because: none exists; the file costs nothing
  now and activates the stakeholder's-folder-is-a-clone future when Cowork's multi-user story
  matures.
- No bridge. Rejected because: a well-meaning Cowork session will otherwise mangle register IDs.

**Chosen because:** Cowork is the structurally correct long-term two-way path (the stakeholder's
copy IS the repo; zero conversion), and this is the cheapest forward-compatible step.

### D-12: One validator, rung-scaled enforcement  (N)

**Decision:** An inception-format validator (minimum core, ID grammar and uniqueness, register
and gate-record integrity, and `Format-version:` gating that fails closed on an unsupported version
per REQ-C1.7) ships plugin-side and runs everywhere: in-session at bundle writes on all rungs, as a
CI guard where the venture repo has CI, and as the stakeholder-commit guard. The
hygiene scaffold (`.gitignore`, commit-time secret screening, remote-rung secret-scan guard) is
created with the repo.

**Alternatives considered:**
- Validator only inside planwright's repo. Rejected because: ventures are where the format lives.
- Mandatory CI. Rejected because: breaks the local-only rung.
- No validator. Rejected because: the gate and the adapters both depend on structural integrity
  they would otherwise have to assume.

**Chosen because:** same guard, every surface; enforcement scales with what the rung can support.

### D-13: The venture-task contract is a lighter sibling of `/execute-task`, keyed on kind  (N)

**Decision:** Task kinds spike / research / analysis / demand-signal / alignment; deliverable is
a findings or outcome document committed directly (no PR, no CI gauntlet, no polish loop); each
task carries a pre-committed time/cost cap alongside the threshold it tests (making "Hold because
tests got expensive" a detectable state), and tasks order lowest-confidence-highest-blocking-first
with the single limiting constraint as the tie-breaker (REQ-C1.5);
demand-signal and alignment tasks produce prepared materials and a recorded outcome — the agent
never contacts external humans; acceptance is human; accepted changes update linked registers
atomically; spike code is disposable in `spikes/`. Venture task state lives in the bundle's
registers, not in the specs-`tasks.md` derivation machinery.

**Alternatives considered:**
- Full `/execute-task` ceremony. Rejected because: test-first plus draft-PR plus review gauntlet
  is shaped for production code and kills the economics of a two-hour spike.
- Freeform research without contract. Rejected because: no done-when, no register linkage;
  findings rot unconnected.

**Chosen because:** the contract preserves the acceptance and evidence discipline at a cost
proportional to exploratory work.

### D-14: The gate is an interactive move with four outcomes and no anchors in v1  (N)

**Decision:** Gate runs evaluate the minimum core plus the completeness check, surface tripped
kill criteria, and end in Graduate / Hold / Recycle / Kill recorded as dated, structured
machine-readable entries (outcome, date, decider from the stakeholder map, evidence cited,
thresholds evaluated, rationale) mirroring planwright's sign-off record, not prose only. No
content-anchor machinery in v1; gate records are the audit trail. Revisit-when: orchestrated
multi-session venture work demonstrates drift pain.

**Alternatives considered:**
- Kickoff-style sign-off with content anchors. Rejected for v1 because: anchors' false-halt cost
  is documented in this repo, and venture execution gating is lighter than spec execution.
- Automatic gate outcomes. Rejected because: the gate is the human's decision point; forcing
  functions require the human to actively answer.

**Chosen because:** four-outcome vocabulary and pre-declared criteria carry the Stage-Gate and
venture-studio evidence without importing spec-grade ceremony.

### D-15: Graduation ships a seed package, never a spec  (N)

**Decision:** Graduate writes a structured seed (brief extract, decided forks with alternatives,
validated assumptions with evidence grades, open questions, source citations) into the chosen
destination plus bidirectional lineage records; `/spec-draft` consumes it through normal
seed-gathering; holes found downstream route back as venture register entries. The seed stays
format-clean enough that a future adapter could emit a Spec Kit `/specify` input as readily as a
planwright `/spec-draft` seed (the upstream-of-spec slot is being actively colonized by Spec Kit
extensions); no v1 work, an interop constraint on the seed shape.

**Alternatives considered:**
- Auto-generating the four-file bundle from the venture. Rejected because: bypasses
  `/spec-draft`'s elicitation, where REQ correctness is made, and violates the never-auto-chain
  invariant in spirit.

**Chosen because:** keeps each stage's authority intact; the seed is exactly the input set
`/spec-draft`'s phases elicit.

### D-16: Altitude routing in `/spec-draft` is a recommend-only pre-flight check  (N)

**Decision:** Heuristics: multiple independently-ownable tracks, no candidate home repo, three or
more discipline domains, pitch-form input. On trigger, recommend `/inception` with one-line
reasoning; proceed as `/spec-draft` if the human declines.

**Alternatives considered:**
- Auto-routing. Rejected because: recommend-never-auto is the pipeline's standing rule.
- No detection. Rejected because: a pitch fed to `/spec-draft` today produces a mangled
  mega-spec; this bundle's origin story.

**Chosen because:** mirrors the existing altitude-gate pattern (autopilot-reflex) pointing the
other direction.

### D-17: The card catalog grows by recipe plus telemetry, with a staleness ritual  (N)

**Decision:** Seven researched core cards ship (product strategy; pricing/packaging; domain and
knowledge engineering; org design; IP; AI/agent architecture; software engineering); the
card-authoring recipe ships as doctrine (distill first questions, frameworks with caveats,
refuse-without-data gates, artifact template, tier placement — research-grounded per card); one
commissioned addition (ML/LLM engineering and evals, demand-evidenced by the consumed 2026-06-17
observation); UX research and GTM are parked named candidates. Cards carry reviewed/rot metadata;
catalog health surfaces in the portfolio view. Company-specific cards are overlay content.

**Alternatives considered:**
- A large catalog now. Rejected because: unresearched cards are vibes cards; card quality
  dominates outcomes, and stale cards are worse than an honest unstaffed flag.
- Demand-only with no commissions. Rejected because: the ML/LLM gap already has logged demand
  evidence.

**Chosen because:** the unstaffed-no-card mechanism plus telemetry makes an incomplete catalog
honest, and growth tracks reality rather than anticipation (the same graduation rule the
customization boundary uses).

### D-18: The frame document is normative  (N)

**Decision:** `inception-format` defines the frame: problem statement, evidence pointers,
constraints, door-classified decisions, discipline staffing table, current success-metric and
kill-criteria state. Gate 1 confirms it; seats consume it (plus their card's input subscription)
and nothing else.

**Alternatives considered:**
- Freeform frame prose. Rejected because: the frame is the specification all seats consume, and
  specification defects are the dominant measured multi-agent failure class.

**Chosen because:** format-level rigor at the single point of highest failure leverage.

### D-19: `/inception` is one skill with state-derived modes  (N)

**Decision:** New-idea, resume, status, gate, export/publish, and no-arg portfolio listing are
modes of one skill, dispatched on arguments plus registry and bundle state.

**Alternatives considered:**
- A skill family (`/venture-status`, `/venture-gate`, ...). Rejected because: the per-stage skill
  convention separates pipeline stages, not moves within one stage; non-engineer users get one
  word to remember.

**Chosen because:** matches the `/spec-draft` precedent (draft plus extend behind one entry) and
keeps the non-engineer surface minimal.

### D-20: `/inception` sits at the product / doctrine altitude, upstream of `/spec-draft`  (N)

**Decision:** The bundle is placed one altitude above `/spec-draft`: it orients a fuzzy,
multi-discipline, repo-less idea rather than specifying a feature, and its task decomposition leads
doctrine-first (inception-format, validator, card and evidence doctrine before the skill and
mechanism tasks). The altitude is cited from the Goal.

**Alternatives considered:**
- Leave the altitude implicit. Rejected because: a doctrine-first, product-level bundle with no
  recorded altitude is exactly the case the autopilot-reflex altitude gate exists to catch; the
  record is cheap insurance even though the decomposition already matches the claim.

**Chosen because:** the seed invocation was explicitly "work one level of abstraction higher", and
recording the altitude makes the doctrine-first sequencing auditable rather than incidental.

## Cross-cutting concerns

- **Evidence honesty.** Where a mechanism is extrapolated rather than measured (the escalation
  contract sections, D-4), the spec says so; verification tags in `test-spec.md` do not claim
  automation where the surface is human.
- **Cost discipline.** Multi-agent work is roughly an order of magnitude more tokens than
  single-session chat; Gate 1 discloses seats × backend × estimated cost, and the bench pattern
  keeps default runs small (REQ-P1.6).
- **Staleness.** The two fastest-rotting knowledge surfaces are the IP and AI-architecture cards
  and any platform-behavior claims (Cowork, web sandbox); each carries review metadata, and
  platform claims are re-verified at build time per research-rigor.
- **Data hygiene.** The proprietary specimen that seeded this design is analyzed in-session only;
  venture-side hygiene is visibility-relative (REQ-B1.6); everything crossing into planwright
  artifacts is neutralized.
