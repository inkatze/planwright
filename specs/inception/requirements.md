# Inception — Requirements

**Status:** Ready
**Last reviewed:** 2026-07-13
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright's pipeline starts at `/spec-draft`, which presumes an existing repo, a feature-sized
idea, and mostly-engineering decisions. Product-level ideas arrive earlier than that: a pitch or
gap analysis with no repo, several latent specs inside it, and open questions owned by disciplines
planwright's catalog does not cover. `/inception` is the pipeline stage upstream of `/spec-draft`,
and its core is a **discipline-persona table**: it convenes grounded, capability-honest,
senior-process judgment across the disciplines a fuzzy idea touches (product strategy, pricing,
domain knowledge engineering, org design, IP, AI architecture, engineering, and more), while being
explicit about which calls only a human authority can make. The substrate that makes that judgment
durable is the **inception bundle**: opportunity brief, discipline and stakeholder map, assumption
and risk register, decision backlog, and validation plan, stored in a venture git repo the skill
creates and wraps (invisible git for non-engineers, the standard workflow for experts), with
stakeholder-facing surfaces produced through an export seam. Validation work (spikes, research,
demand signals, alignment) runs PR-less under a lighter execution contract. A gate with four
outcomes (Graduate / Hold / Recycle / Kill) governs each track; graduation hands a seed package to
one or more `/spec-draft` runs. The skill never auto-chains downstream. Altitude: `/inception` sits
one level above `/spec-draft`, at the product / doctrine altitude, and its task decomposition leads
doctrine-first (D-20).

## Scope

### In scope

- The `/inception` skill: Socratic elicitation of a fuzzy idea into an inception bundle, plus
  resume, status, gate, export/publish, and no-arg portfolio modes.
- The inception bundle format (a sibling of the four-file spec format, normatively defined in
  doctrine) and its validator.
- The discipline-persona layer: discipline cards, persona fan-out over the dispatch backend
  contract, synthesis, one challenge pass, human gates, and coverage honesty.
- Venture repo creation and wrapping: ventures root, ask-once home selection, hygiene scaffold,
  truth-store degradation ladder, non-engineer and expert modes.
- The venture registry, catalog telemetry, and a machine-local feedback drop in the plugin data
  directory (interim, pending observation-routing).
- Validation-task execution under the venture-task contract (PR-less findings, human acceptance,
  atomic register updates), dispatchable through the standard machinery.
- Gates (four outcomes, pre-committed kill criteria, completeness check) and the graduation
  handoff seed contract into `/spec-draft`.
- Exports and stakeholder surfaces: deterministic renderer (dashboard and pitch modes), offered
  Artifact publish, documented GitHub web path with a CI guard, adapter seam with a Notion
  reference adapter, Cowork sync-protocol file.
- Doctrine and catalog extensions: inception-format, card schema and authoring recipe,
  evidence-quality standard, storage-classes rule, decision-domains additions (non-engineering
  domains plus the existing-seam-reuse domain), discipline-appropriate lens selection.
- `/spec-draft` integration: venture-seed consumption, upward altitude routing, feedback-drop
  reading.

### Out of scope

- Notion, Google Drive, or any non-git store as source of truth; they are export or review
  channels at most.
- Symmetric two-way file synchronization with any external tool (documented failure mode; the
  adapter seam is one-way per cycle).
- Auto-chaining: `/inception` never auto-invokes `/spec-draft`, `/spec-kickoff`, or
  `/orchestrate`; graduation, kill, and publish are human acts. Auto-merge stays forbidden at
  every tier (carried invariant).
- Generating the pitch itself: the skill consumes and structures an idea, it does not invent one.
- Deciding human-authority calls: price commitments, legal or tax interpretations, org decisions
  affecting people, one-way-door commitments. Personas structure these and route them to humans.
- Identity personas: backstories, credentials, or seniority styling in cards or outputs.
- Cross-repo and multi-target observation routing (the `observation-routing` draft's domain; the
  machine-local feedback drop is an interim mechanism recorded as re-anchoring there).
- Concurrent multi-operator ventures: v1 ventures are single-operator; concurrent operation of
  one venture is a follow-on that rides `orchestration-concurrency` patterns if demand appears.
- Replacing `/spec-draft` for ideas that already have a home repo. (Not a ban: a home-repo idea
  MAY still opt into a venture when the operator wants inception-grade orientation; the D-16
  routing heuristics stay recommend-only in both directions.)
- A Coda adapter (rejected on evidence: no comments API, lossy exports, no prior art).
- claude.ai chat as an operator surface (reader-only via published exports; an Agent-Skill
  repackaging is a separate effort).

## REQ-A — Venture identity & home

- **REQ-A1.1** The skill SHALL derive a kebab-case venture identifier from the idea, validated
  against the anchored pattern `^[a-z0-9][a-z0-9-]*$` (max 64) before any use in paths, branch
  names, or repository names; a non-conforming name yields a proposed variant the human confirms.
  *(Cites: D-5; bootstrap REQ-A1.8 (pattern precedent).)*
- **REQ-A1.2** Each venture SHALL live in its own repository, holding that venture's inception
  bundle and, optionally, its graduated specs until a product repo exists.
  *(Cites: D-5; drafting-session decision (2026-07-08).)*
- **REQ-A1.3** Venture repositories SHALL be created under a configurable `ventures_root`
  (default `~/ventures`), resolved through the standard config layers.
  *(Cites: D-5; drafting-session decision (2026-07-08).)*
- **REQ-A1.4** When no repo exists for an idea, the skill SHALL ask exactly once whether the
  venture home is a private remote repository or a local-only repository, and SHALL NOT push
  content off-machine by default.
  *(Cites: D-5; drafting-session decision (2026-07-07).)*
- **REQ-A1.5** On ephemeral environments (no durable local filesystem), the local-only arm SHALL
  be presented as session-only or unavailable, never silently offered; an operator who declines a
  durable home proceeds session-only-warned per the REQ-H1.1 ladder floor (bundle files in the
  session, explicit warning it does not persist), never a silent refusal.
  *(Cites: D-5; REQ-H1.1; research: Claude Code web sandbox persistence model (Sources).)*
- **REQ-A1.6** The skill SHALL maintain a venture registry in the plugin data directory
  recording each venture's identifier, path, and lifecycle status plus attention flags. Registry
  mutations SHALL be atomic (write-temp-then-rename) so a concurrent `/inception` session never
  reads a torn or partial registry; a lost update from two sessions racing is tolerated because the
  registry is rebuildable by scanning `ventures_root` for bundles, with every recovered identifier
  re-validated per REQ-A1.8 — that scan-rebuild is the recovery path for a corrupt, lost, or
  clobbered registry. The rebuild SHALL trigger automatically when a session detects a torn,
  missing, or unparseable registry at read time (scan `ventures_root`, re-validate each recovered
  identifier per REQ-A1.8, then proceed); no manual step is required.
  *(Cites: D-8; kickoff §3 REQ-A (2026-07-10); kickoff §7 R7 (2026-07-13).)*
- **REQ-A1.7** On invocation with a new idea, the skill SHALL scan registered ventures for
  semantic overlap and surface an extend-vs-new selector; it SHALL NOT silently fold or create a
  duplicate venture. Venture creation SHALL detect an existing unregistered directory at the
  target path and offer adopt-vs-rename; it SHALL NOT overwrite.
  *(Cites: D-8; bootstrap REQ-B1.3 (fold-detection precedent); kickoff §3 REQ-A (2026-07-10).)*
- **REQ-A1.8** Every identifier proposed by a seed, registry entry, or extend target SHALL be
  re-validated at consumption; registry contents are unscreened input.
  *(Cites: D-8; the security-posture doctrine (Sources).)*
- **REQ-A1.9** Venture repo creation SHALL scaffold hygiene guards scaled to the rung: a
  `.gitignore` covering machine-local files, commit-time secret screening by the skill, a
  pre-commit export-regeneration step so the HTML export stays current with out-of-session edits
  (REQ-G1.1) — it regenerates, stages the export on success, and warns without blocking the commit
  on a render failure (never dead-ending a wrapped-mode commit) — and a secret-scan CI guard where
  the venture has a remote with CI.
  *(Cites: D-9, D-12; drafting-session decision (2026-07-08, blind-spot sweep); kickoff §7
  (2026-07-13).)*

## REQ-B — The elicitation flow

- **REQ-B1.1** `/inception` SHALL conduct a phased Socratic elicitation governed by the
  interaction-style rules (progress indicator, progressive disclosure, recommended selectors,
  running summaries, small bites).
  *(Cites: D-19; the interaction-style doctrine (Sources).)*
- **REQ-B1.2** The skill SHALL accept seed material in any form (pitch documents, transcripts,
  ticket exports, freeform notes) and mine it before asking the human anything the seeds already
  answer.
  *(Cites: D-19; the inception drafting invocation (Sources).)*
- **REQ-B1.3** Elicitation SHALL walk the discipline catalog, flagging every decision the venture
  touches but does not decide and recording it in the discipline map.
  *(Cites: D-17; REQ-I1.2.)*
- **REQ-B1.4** The flow SHALL include an explicit problem-reframing checkpoint between evidence
  gathering and brief finalization.
  *(Cites: research: Design Council Double Diamond, via the prior-art report (Sources).)*
- **REQ-B1.5** Elicitation SHALL be proportional: inapplicable prompt areas are skipped with an
  explicit one-line reason, never silently; only the minimum core (REQ-C1.8) is mandatory; a
  small venture may run with zero persona seats.
  *(Cites: D-19; the proportionality doctrine (Sources).)*
- **REQ-B1.6** Seed-material hygiene SHALL be relative to the venture repo's visibility boundary:
  material may be stored verbatim when the repo's access matches its sensitivity, and SHALL be
  neutralized when it does not; anything flowing back into planwright's own artifacts is always
  neutralized. The sensitivity-vs-visibility call is human: the skill classifies conservatively
  and surfaces its judgment; the operator confirms verbatim storage once per seed source.
  *(Cites: D-8; drafting-session decision (2026-07-08, pitch dry-run); kickoff §3 REQ-B
  (2026-07-10).)*
- **REQ-B1.7** The skill SHALL resume an existing venture: pick up mid-elicitation, or re-enter
  later to update registers and re-run the gate.
  *(Cites: D-19.)*

## REQ-C — The inception bundle format

- **REQ-C1.1** The bundle SHALL comprise `brief.md`, `disciplines.md`, `assumptions.md`,
  `decisions.md`, and `plan.md`, plus `spikes/` and `exports/` directories, defined normatively
  by the inception-format doctrine.
  *(Cites: D-1; REQ-I1.1.)*
- **REQ-C1.2** `brief.md` SHALL carry: opportunity framing with evidence; who-hurts stated as a
  job-in-circumstance; a candidate success metric; appetite; no-gos and a rough solution sketch;
  existing-alternatives and landscape prompts; business-viability prompts (market, pricing,
  channels); a strategy-fit section (adjacent initiatives and inherited constraints); and the
  actor-to-behavior-change-to-goal chain.
  *(Cites: D-1; research: prior-art gaps list (Sources); drafting-session decision (2026-07-08).)*
- **REQ-C1.3** `assumptions.md` entries SHALL carry stable A-IDs with: a falsifiable statement
  (believe / verify / measure / right-if skeleton, per REQ-I1.4), a risk-if-wrong, a four-risk tag
  (value / usability / feasibility / viability), a pass/fail threshold defined before the test runs
  and expressible as a fail condition, a commitment-weighted evidence grade drawn from the named
  evidence ladder (REQ-I1.4), a blocking flag, a validation-task link, and a status. Synthetic or
  simulated evidence (persona-panel output) carries the named low grade and SHALL NOT satisfy a
  Graduate threshold on a value- or usability-tagged (desirability) assumption (REQ-E1.1, REQ-I1.4).
  *(Cites: D-1; REQ-I1.4; research: Strategyzer test/learning cards, Mom Test, pretotyping,
  Kromatic fail-conditions, synthetic-user evidence limits (Sources).)*
- **REQ-C1.4** `decisions.md` entries SHALL carry stable IDs with alternatives (considered
  options), an owning discipline, deciders, a status (open / decided / deferred), consequences, and
  a feed-forward note naming what future spec consumes the decision (MADR-shaped fields). On a
  remote-backed venture, merging the decision's change is its ratification.
  *(Cites: D-1; research: MADR decision-record schema (Sources).)*
- **REQ-C1.5** `plan.md` tasks SHALL carry stable T-IDs, a kind (spike / research / analysis /
  demand-signal / alignment), evaluable done-when conditions, a pre-committed time/cost cap
  alongside the threshold they test, and ordering by lowest-confidence, highest-blocking
  assumptions first, with the single limiting constraint (the one assumption gating the others) as
  the tie-breaker.
  *(Cites: D-1, D-13; research: assumption-mapping prioritization, budget-capped RATs,
  theory-of-constraints framing (Sources).)*
- **REQ-C1.6** The venture SHALL have a lifecycle status with Abandoned and On-hold as
  first-class states, pre-committed kill criteria as state-plus-date pairs, and a named gate
  decider drawn from the stakeholder map.
  *(Cites: D-1, D-14; research: Stage-Gate, venture-studio kill discipline, Duke kill criteria
  (Sources).)*
- **REQ-C1.7** All bundle IDs SHALL be stable and append-only with meta-spec-style supersession;
  the bundle format itself SHALL be format-versioned. The validator SHALL gate on the
  `Format-version:` header and fail closed with a plain-language message (a non-zero exit) on an
  unsupported version, never silently misparsing; the renderer and skill SHALL likewise refuse an
  unsupported version rather than parse it, deferring to the validator's check. The format SHALL
  evolve additively within a major version (new fields and sections optional, existing fields
  never renamed or repurposed), and a breaking change SHALL increment the major format-version and
  own its migration path.
  *(Cites: D-1, D-12; the spec-format meta-spec (Sources).)*
- **REQ-C1.8** The gate-enforced minimum core SHALL be: blocking assumptions enumerated, open
  forks recorded, kill criteria set, success metric named. All other fields are prompts,
  skippable with an explicit reason.
  *(Cites: D-1, D-14; REQ-B1.5.)*
- **REQ-C1.9** The bundle SHALL include a sources/evidence register listing the seed and evidence
  material the venture rests on, governed by the visibility-relative hygiene rule (REQ-B1.6).
  *(Cites: D-1; drafting-session decision (2026-07-08, pitch dry-run).)*
- **REQ-C1.10** The bundle SHALL include a stakeholder and decision-rights map: who decides, who
  must be aligned, who is informed, per decision area; the gate decider and alignment-task
  targets reference it.
  *(Cites: D-1; research: RAPID and named-gatekeeper prior art (Sources); drafting-session
  decision (2026-07-08, pitch dry-run).)*
- **REQ-C1.11** The bundle SHALL support optional track labels on assumptions, decisions, and
  plan tasks; a single-track venture requires none; gate records MAY carry per-track outcomes;
  partial graduation (REQ-F1.3) keys on track labels where present. The inception-format doctrine
  defines the label grammar.
  *(Cites: D-1; kickoff §2 (2026-07-10).)*

## REQ-D — Validation task execution

- **REQ-D1.1** `plan.md` tasks SHALL run under the venture-task contract: the deliverable is a
  findings or outcome document committed to the venture repo; no PR or CI gauntlet is required;
  PR-mediated review SHALL remain available on request for remote-backed ventures.
  *(Cites: D-13.)*
- **REQ-D1.2** Each task kind SHALL define its deliverable and acceptance shape; alignment tasks
  deliver the recorded outcome of a named-stakeholder interaction.
  *(Cites: D-13; drafting-session decision (2026-07-08, pitch dry-run).)*
- **REQ-D1.3** Completing a task SHALL update its linked register entries in the same change;
  assumption statuses flip with cited, graded evidence; no orphaned findings.
  *(Cites: D-13.)*
- **REQ-D1.4** Acceptance SHALL be human: findings are presented and accepted or rejected before
  register updates land.
  *(Cites: D-13.)*
- **REQ-D1.5** Spike code SHALL live in `spikes/` and be marked disposable; findings graduate,
  prototype code never does.
  *(Cites: D-13.)*
- **REQ-D1.6** Venture tasks SHALL be dispatchable through the standard dispatch machinery under
  the venture-task contract, and runnable inline in-session for light ventures.
  *(Cites: D-7, D-13; REQ-J1.3.)*
- **REQ-D1.7** Demand-signal and alignment tasks SHALL NOT be executed autonomously against
  external humans: the agent prepares materials; the human performs the interaction.
  *(Cites: D-13; the security-posture doctrine (Sources).)*

## REQ-E — Gates

- **REQ-E1.1** The gate SHALL evaluate the minimum core: every blocking assumption resolved with
  graded evidence or consciously waived with reason; load-bearing forks decided or deferred with
  reason; kill criteria and success metric present. Synthetic-grade evidence SHALL NOT satisfy a
  Graduate threshold on a value- or usability-tagged (desirability) assumption (REQ-I1.4).
  *(Cites: D-14; REQ-C1.8, REQ-I1.4.)*
- **REQ-E1.2** Gate outcomes SHALL be four first-class states: Graduate / Hold / Recycle / Kill,
  recorded with rationale by the named decider.
  *(Cites: D-14; research: Stage-Gate outcome vocabulary (Sources).)*
- **REQ-E1.3** Kill criteria SHALL be checked at every gate run and status view; a tripped
  criterion surfaces a kill-or-re-scope prompt and SHALL NOT auto-kill.
  *(Cites: D-14.)*
- **REQ-E1.4** The gate SHALL run a completeness check: every blocking assumption maps to a
  completed or planned task, and every task traces to an assumption or fork.
  *(Cites: D-14; research: MECE completeness discipline (Sources).)*
- **REQ-E1.5** Gate runs SHALL be recorded in the bundle as dated, structured machine-readable
  entries (outcome, date, decider, evidence cited, thresholds evaluated, rationale); these records
  are the venture's audit trail.
  *(Cites: D-14.)*
- **REQ-E1.6** A killed or abandoned venture SHALL be archived with a brief post-mortem note and
  a registry update; dead ventures feed the observation stream.
  *(Cites: D-8, D-14.)*

## REQ-F — Handoff

- **REQ-F1.1** Graduation SHALL package the track as a `/spec-draft` seed: goal and scope
  candidates from the brief, decided forks with alternatives preserved, validated assumptions as
  cited evidence, unresolved items as open questions.
  *(Cites: D-15.)*
- **REQ-F1.2** The human SHALL choose the destination (venture repo `specs/`, an existing product
  repo, or a new repo); the skill prepares the seed and the human invokes `/spec-draft`.
  *(Cites: D-15; REQ-J1.6.)*
- **REQ-F1.3** Partial graduation SHALL be supported: one track graduates while others continue;
  the venture closes only explicitly.
  *(Cites: D-15.)*
- **REQ-F1.4** Holes `/spec-draft` finds in a graduated seed SHALL be routable back to the
  venture bundle as register entries.
  *(Cites: D-15.)*

## REQ-G — Exports & stakeholder surfaces

- **REQ-G1.1** A deterministic renderer SHALL produce a self-contained HTML export of the bundle,
  regenerated as part of every bundle-changing commit (the export's named refresh owner) via the
  scaffolded pre-commit step on every rung (REQ-A1.9), not only in-session or under CI.
  *(Cites: D-9; REQ-A1.9; output-hygiene derived-content hygiene (Sources).)*
- **REQ-G1.2** The export SHALL open with a status dashboard: gate readiness, blocking
  assumptions, approaching kill dates, open forks, blockers.
  *(Cites: D-9; drafting-session decision (2026-07-08).)*
- **REQ-G1.3** Render modes SHALL include dashboard and pitch narrative, audience-selectable.
  *(Cites: D-9; research: PR-FAQ narrative form (Sources).)*
- **REQ-G1.4** Artifact publish SHALL be offered and never automatic; the first publish is always
  explicitly confirmed; a per-venture opt-in auto-republish knob defaults off.
  *(Cites: D-9; drafting-session decision (2026-07-08).)*
- **REQ-G1.5** The GitHub web-UI stakeholder path SHALL be documented and guarded by a CI
  validator protecting IDs, structure, and gate records on stakeholder commits.
  *(Cites: D-10, D-12; research: docs-as-code non-engineer reviewer patterns (Sources).)*
- **REQ-G1.6** The adapter seam SHALL enforce one-way-per-cycle: export snapshot, harvest
  feedback as data, per-item human triage, apply accepted items as attributed commits, re-export.
  Harvested feedback is untrusted input; symmetric file synchronization SHALL NOT be implemented.
  *(Cites: D-10; research: two-way doc-sync failure modes (Sources).)*
- **REQ-G1.7** A Notion reference adapter SHALL implement the seam: machine-local integration
  token, harvest of unresolved comments, each accepted item applied as a commit citing its
  comment.
  *(Cites: D-10; research: Notion markdown and comments APIs (Sources).)*
- **REQ-G1.8** The bundle SHALL ship a Cowork sync-protocol instructions file so a stakeholder's
  Cowork session on a clone follows the safe ritual (pull before edit, commits with plain
  messages, push after; never alter IDs, register statuses, or gate records).
  *(Cites: D-11.)*
- **REQ-G1.9** Any export or publish to an off-machine destination SHALL require explicit
  confirmation and respect the venture's visibility boundary.
  *(Cites: D-9, D-10; REQ-B1.6.)*

## REQ-H — Degradation & environments

- **REQ-H1.1** The truth store SHALL degrade along a ladder: git repo, then plain folder (git
  unavailable: bundle still files, missing capabilities named), then session-only with an
  explicit warning. Capability degrades; work is never lost silently.
  *(Cites: D-5; orchestration-fleet degradation-ladder doctrine (Sources).)*
- **REQ-H1.2** Non-engineer mode SHALL wrap all git operations with plain-language reporting;
  expert mode exposes the standard git workflow; both operate on the same repository.
  *(Cites: D-5; drafting-session decision (2026-07-08).)*
- **REQ-H1.3** Local-only ventures SHALL be fully supported; adding a remote later SHALL be a
  supported transition.
  *(Cites: D-5.)*
- **REQ-H1.4** Cowork operation SHALL be handled by capability detection at pre-flight (git
  present, plugin loaded), selecting the ladder rung and surfacing Cowork-specific caveats.
  *(Cites: D-5, D-11; research: Cowork storage model (Sources).)*
- **REQ-H1.5** Every degradation SHALL be reported at pre-flight and repeated in the handoff.
  *(Cites: D-5; bootstrap REQ-K1.7 (graceful-degradation precedent).)*
- **REQ-H1.6** A missing or unavailable registry SHALL degrade to skipping the cross-venture
  overlap scan with a notice; everything else proceeds. An overlap scan that fails mid-run (a
  corrupt registered brief, a timeout) SHALL likewise degrade to a notice and proceed, never
  blocking venture creation.
  *(Cites: D-8.)*

## REQ-I — Doctrine & catalog extensions

- **REQ-I1.1** The inception bundle format SHALL be defined in a normative doctrine doc
  (`inception-format`), the single source the validator, renderer, and skills parse.
  *(Cites: D-1.)*
- **REQ-I1.2** The decision-domains catalog SHALL gain the non-engineering domains the discipline
  map walks (product strategy, packaging/pricing, domain and knowledge engineering, org design,
  IP posture), the LLM-output-quality and human-comprehension domains, and an
  **existing-seam-reuse** domain requiring any newly minted mechanism to record why the existing
  core seams do not fit.
  *(Cites: D-17; observations log 2026-06-17 and 2026-07-07 (Sources); drafting-session decision
  (2026-07-08, backend-seam catch).)*
- **REQ-I1.3** Discovery and validation rigor SHALL gain a discipline-appropriate lens set for
  non-code artifacts, selected by artifact class; code-oriented lenses SHALL NOT be force-applied
  to inception artifacts.
  *(Cites: D-17; observations log 2026-06-16 (Sources).)*
- **REQ-I1.4** An evidence-quality doctrine SHALL define the falsifiability format (the
  believe / verify / measure / right-if skeleton), pre-committed thresholds expressible as fail
  conditions, and commitment-weighted evidence grades naming the evidence ladder
  (opinion → stated-intent → costly-signal → real-world behavior), that `assumptions.md` and the
  gate cite. The doctrine SHALL define desirability as the value-risk plus usability-risk tags
  (REQ-C1.3's four-risk set) so the exclusion below is programmatic. The ladder SHALL place a named
  low grade for synthetic / simulated evidence below real-human anecdote and above pure reasoning,
  excluded from a Graduate threshold on a value- or usability-tagged (desirability) assumption.
  *(Cites: D-1; research: Mom Test commitment currencies, Strategyzer test/learning cards, Savoia's
  skin-in-the-game point scale, Kromatic fail-conditions, synthetic-user evidence limits
  (Sources).)*
- **REQ-I1.5** A storage-classes doctrine rule SHALL distinguish framework config, framework
  runtime state, and user work products, assigning each its canonical home.
  *(Cites: D-8; drafting-session decision (2026-07-08).)*
- **REQ-I1.6** Every configuration introduced by this spec SHALL pass the capability-vs-style
  boundary test: seams and knobs in core, personal and team values in overlays.
  *(Cites: the customization-boundary doctrine (Sources).)*

## REQ-J — Pipeline & skill integration

- **REQ-J1.1** `/spec-draft` SHALL consume a graduated venture track as a first-class seed
  source, with citations preserved into the spawned bundle.
  *(Cites: D-15.)*
- **REQ-J1.2** `/spec-draft` SHALL detect pitch-shaped input (multiple independently-ownable
  tracks, no home repo, three or more discipline domains, pitch-form documents) and recommend
  routing up to `/inception`; it SHALL NOT auto-route.
  *(Cites: D-16.)*
- **REQ-J1.3** Venture validation tasks SHALL be executable through the standard dispatch
  machinery under the venture-task contract; no parallel orchestration system.
  *(Cites: D-7, D-13.)*
- **REQ-J1.4** `/inception` SHALL provide an in-session status view for any registered venture:
  gate readiness, blockers, kill dates.
  *(Cites: D-14, D-19.)*
- **REQ-J1.5** The graduation handoff SHALL record bidirectional lineage: the venture track cites
  the spawned spec and the spec's Sources cite the venture track.
  *(Cites: D-15.)*
- **REQ-J1.6** `/inception` SHALL NOT auto-invoke any downstream skill; graduation, like sign-off
  and merge, is a human act.
  *(Cites: D-15; the bootstrap hard invariants (Sources).)*
- **REQ-J1.7** Invoked with no arguments, `/inception` SHALL list registered ventures with
  attention flags (tripped or approaching kill dates, blocked items, age versus appetite) plus
  catalog-health notes (cards past review date, unstaffed-discipline frequency).
  *(Cites: D-8, D-17; drafting-session decision (2026-07-08, blind-spot sweep).)*
- **REQ-J1.8** Venture-side telemetry (frame-derived disciplines, unstaffed occurrences) and
  planwright-about observations surfaced during venture work SHALL be recorded in the
  machine-local plugin data drop; planwright-repo `/spec-draft` and bookkeeping read it as a seed
  source with neutralization before anything is committed. This mechanism is interim and
  re-anchors on the `observation-routing` effort when it revives.
  *(Cites: D-8; observation-recording Out-of-scope carve-out (Sources).)*

## REQ-P — The discipline-persona layer

- **REQ-P1.1** Discipline cards SHALL be task-framings, not identities: one operational role
  sentence, a mandate of three to seven first questions with no silent pruning (each answerable
  only against this venture's frame, not generically), named frameworks ordered into a working
  sequence with their misuse caveats, grounding requirements naming the concrete evidence sources
  the seat must consult, an artifact template with done-when, a capability boundary, an escalation
  contract, register rules, anti-patterns, documented blind spots, conflict / deference rules
  (whose view prevails on whose turf), an independence note (the seat cannot validate its own
  discipline's claims), an optional stance axis (e.g. optimist–skeptic) orthogonal to discipline,
  and staleness metadata. Backstories, credentials, and seniority styling SHALL NOT appear in cards
  or outputs.
  *(Cites: D-3; research: persona-null evidence and lever ranking, AI-board blind-spots/conflict
  rules, stance-axis decorrelation, named knowledge-sources, frame-specific lens questions
  (Sources).)*
- **REQ-P1.2** Each card SHALL carry a default capability tier (agent-senior / structure-only /
  human-authority) with per-activity exceptions and an explicit out-of-scope line (what this seat
  must not opine on); one-way-door decisions are always human-authority regardless of tier.
  *(Cites: D-4; research: jagged-frontier and professional-norms evidence, Model-Card
  out-of-scope-use field (Sources).)*
- **REQ-P1.3** Fan-out SHALL run seats as independent parallel units (read-only, same frame, no
  inter-seat communication), merged by a single synthesis writer producing a mandatory
  agreements / tensions / open-questions table with per-claim convergence marks. Seat outputs
  SHALL reach the synthesis writer anonymized and order-shuffled (no seat names or ordering cues);
  the orchestrator, not the synthesis writer, holds the stable seat↔label mapping and re-attaches
  seat attribution into the human-facing table after synthesis (the writer works blind, keying
  claims by anonymized label).
  *(Cites: D-2, D-7; research: topology evidence, identity-bias anonymization (Sources).)*
- **REQ-P1.4** Exactly one challenge pass SHALL follow synthesis: a premortem plus
  key-assumptions check, seeing synthesis and frame but not per-seat output; synthesis may amend
  once; no debate loop. The synthesis and challenge steps SHALL run persona-free (plain task
  instructions, no card role line): persona framing aids generative coverage but degrades
  discriminative judgment.
  *(Cites: D-2; research: premortem versus devil's-advocate evidence, generative-vs-discriminative
  persona effects (Sources).)*
- **REQ-P1.5** Every seat artifact SHALL end with a mandatory "Decisions I cannot make" section
  (decision, tier and reason, owning role, evidence needed); human-authority items reach the
  human as structured forced choices at the gate, never as disclaimers. Escalation triggers SHALL
  be typed, not prose (irreversibility / missing-domain-authority / confidence-floor /
  contract-policy-change), each naming the receiving human's power (disregard / override / reverse
  / halt). The seat's own-discipline independence (a seat cannot validate its own discipline's
  claims) is a card property (REQ-P1.1); the challenge pass runs persona-free (REQ-P1.4) and needs
  no per-discipline standing.
  *(Cites: D-4, D-6; research: forcing-function versus disclaimer evidence, EU AI Act Art. 14 typed
  human powers, typed escalation-trigger registers, SR 11-7 effective-challenge independence
  (Sources).)*
- **REQ-P1.6** The default seat count SHALL be small (three, capped near five) with a bench of
  on-call cards; a stake / reversibility-scored triage SHOULD inform the count within that band
  when the signal is cheap, defaulting to three otherwise; estimated cost and backend are surfaced
  at Gate 1 before any seat spawns; seats SHOULD vary model or effort where the backend already
  advertises the capability (model-family diversity is the strongest decorrelation lever), and when
  they cannot the lost decorrelation SHALL be reported as a degradation (REQ-H1.5).
  *(Cites: D-2, D-7; research: token economics and heterogeneity evidence, stake-scored panel
  sizing, model-family decorrelation (Sources).)*
- **REQ-P1.7** Human gates SHALL live in the main conversation: Gate 1 confirms frame and
  staffing; Gate 2 is the table read with proceed / park / kill / re-run-seat / pull-bench
  outcomes; seats route escalations through the orchestrator, never to the human directly.
  *(Cites: D-2, D-6, D-7.)*
- **REQ-P1.8** The staffing table SHALL record each touched discipline as agent-persona,
  named-human, or unstaffed; every unstaffed senior discipline SHALL auto-file as an
  assumption-register risk, including the no-card-exists case. A deliberate zero-seat run
  (REQ-B1.5) SHALL collapse the per-discipline auto-files into a single "personas waived
  (zero-seat); N disciplines unstaffed" risk row, preserving coverage honesty without flooding a
  small venture's register.
  *(Cites: D-17; REQ-B1.5; research: coverage-honesty prior art (Sources).)*
- **REQ-P1.9** Confidence SHALL be expressed only as convergence across independent seats or
  cited evidence, never verbalized self-confidence; structure-only output uses hypothesis
  grammar, human-authority-adjacent output uses briefing grammar. Convergence marks are a weak,
  inflation-prone signal: they SHALL be annotated by claim type (extractive / factual versus
  interpretive / evaluative), SHALL name outlier seats rather than averaging them away, and SHALL
  NOT be presented as a calibrated probability; grounding (checkable citations per claim) outranks
  the vote count as evidence.
  *(Cites: D-4; research: calibration and overreliance evidence, correlated-error and
  consensus-is-not-verification findings (Sources).)*
- **REQ-P1.10** Cards SHALL be overlay-extensible: the seven researched core cards ship in core;
  company-specific cards live in adopter or team overlays; RAPID letters are recorded per card
  and the human always holds the D.
  *(Cites: D-3, D-17; the customization-boundary doctrine (Sources).)*
- **REQ-P1.11** The catalog SHALL grow by recipe plus demand evidence: the card-authoring recipe
  ships as doctrine; new cards require research-grounded authoring per the recipe; telemetry
  (REQ-J1.8) supplies the demand signal; parked candidates are named, not built.
  *(Cites: D-17; drafting-session decision (2026-07-08, catalog epistemics).)*

## Changelog

- 2026-07-09 — Initial draft authored via `/spec-draft` (elicitation 2026-07-07 through
  2026-07-09), including two commissioned research passes (prior-art and bundle ergonomics;
  discipline-persona evidence), a pitch dry-run evaluation against a proprietary specimen
  (analyzed in-session only), and an operator blind-spot sweep.
- 2026-07-10 — Kickoff walkthrough edits (kickoff §2–§3): home-repo opt-in clarified in Out of
  scope; REQ-C1.11 (optional track labels) added; registry rebuild + creation collision check
  (REQ-A1.6/A1.7); operator-confirmed visibility-hygiene call (REQ-B1.6).
- 2026-07-13 — Kickoff walkthrough continued (§3–§7 + sign-off): SOTA re-check findings folded
  (evidence ladder + fail-conditions + Strategyzer skeleton, REQ-C1.3/I1.4; synthetic-evidence
  grade + Graduate exclusion, REQ-C1.3/E1.1; MADR decision fields, REQ-C1.4; plan.md caps +
  constraint ordering, REQ-C1.5; card-schema additions and persona-topology refinements,
  REQ-P1.1–P1.9; version-gating + additive evolution, REQ-C1.7); probe resolutions (pre-commit
  export regen, REQ-A1.9/G1.1; zero-seat collapse, REQ-P1.8; ephemeral session-only-warned,
  REQ-A1.5); atomic registry writes (REQ-A1.6, D-8). See `kickoff-brief.md` §3–§7 for the full
  disposition ledger.

- 2026-07-15 — Migrated to format-version 2 (invariant-tasks D-10, REQ-D1.3;
  one-shot `scripts/migrate-format-version.sh` run): placement sections
  collapsed into a single `## Tasks` section, state annotation bullets
  stripped, stored header restricted to the human-gated set, the
  `**Execution:**` pointer line added, `Format-version:` bumped to 2 on
  all four files. Task definition lines are preserved byte-for-byte (the
  canonical `tasks.md` extraction digest is unchanged), so the required
  re-anchor rides as expression-only: the kickoff brief's self-re-anchor
  entry cites this entry.

## Sources

- **The inception drafting invocation (2026-07-07)** — the operator's request to work one level
  of abstraction higher: orient on a new feature or product idea not tied to an existing
  project, product, or repo.
- **A proprietary multi-discipline product pitch (analyzed in-session, 2026-07-07/08)** — the
  specimen used to shape and dry-run the design; per operator instruction its content is not
  stored, quoted, or referenced beyond this generic descriptor.
- **Observations log 2026-06-16 (research-grounding under-fires for human-facing design)** —
  consumed; evidence the research-grounding step under-fires outside code domains.
- **Observations log 2026-06-16 (Discovery-Rigor lens set is code-oriented)** — consumed;
  evidence the canonical lenses over-fire on non-code artifacts.
- **Observations log 2026-06-17 (decision-domains catalog lacks LLM/model-output quality)** —
  consumed; catalog-gap evidence and the demand basis for the ML/LLM card commission.
- **Observations log 2026-06-17 (spike-to-production kickoffs inherit unchecked assumptions)** —
  consumed; the assumption-carryover evidence behind the register design.
- **Observations log 2026-07-07 (decision-domains catalog lacks human-comprehension /
  information-UX)** — consumed; catalog-gap evidence.
- **Session research report: prior-art and bundle ergonomics (2026-07-07)** — a two-track
  commissioned sweep (16 methodologies and 10 AI-era tools; 9 storage substrates with round-trip
  prior art); retained operator-side, not committed; its load-bearing findings are cited inline
  in `design.md` with their primary sources.
- **Session research report: discipline-persona evidence (2026-07-08)** — a four-track
  commissioned sweep (persona-prompting evidence, per-discipline senior practice, capability
  boundaries, orchestration patterns); retained operator-side, not committed; load-bearing
  findings cited inline in `design.md` with their primary sources.
- **The spec-format meta-spec, interaction-style, proportionality, customization-boundary, and
  security-posture doctrine docs** — the governing framework rules.
- **specs/observation-recording and the output-hygiene carve-out (2026-07-08)** — the fragment
  recording substrate and the cross-spec supersession ritual this bundle's interim feedback-drop
  mechanism is positioned against.
- **The bootstrap hard invariants** — never auto-merge, never auto-chain, sign-off and merge as
  reserved human controls; carried into every gate and handoff rule here.
- **Drafting-session decisions (2026-07-07 through 2026-07-09)** — operator choices recorded
  during elicitation, including the walking-skeleton sequencing, catalog epistemics, backend-seam
  catch, pitch dry-run amendments, and blind-spot sweep dispositions.
- **Session SOTA re-check (2026-07-10)** — three commissioned state-of-the-art sweeps run before
  the kickoff walkthrough (upstream-of-spec tooling and the D-1 adversarial check;
  discipline-persona topology, calibration, and card-schema prior art; storage/collaboration seams
  and the evidence doctrine); retained operator-side under `research/sota-*.md`, not committed. Its
  adopt/adapt findings are folded into the kickoff §3–§7 edits and cited inline here and in
  `design.md` with their primary sources.
- **Convergent agent-native discovery practice (pm-skills, discovery-pack, and peers)** — GitHub
  skill collections repackaging product-discovery practice as plain-markdown Claude Code skills;
  convergent evidence that the plain-text register / backlog / plan direction this bundle takes is
  where the field is moving, and that no standardized composed schema exists to adopt.
- **This kickoff walkthrough (`kickoff-brief.md`, 2026-07-10 / 2026-07-13)** — the durable contract
  this bundle was walked and signed off against, and the source for the `kickoff §…` citations
  above; its §3–§7 disposition ledger records the SOTA-fold and probe decisions.
