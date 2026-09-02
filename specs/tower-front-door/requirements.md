# Tower front door — Requirements

**Status:** Ready
**Last reviewed:** 2026-09-01
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright's only entrance today is a spec bundle: every piece of work,
however small, pays the four-file ceremony before anything runs, and small
work routes around the tool entirely. This spec inverts the entrance. A
single standing conversational session — the `/tower` skill — becomes the
framework's front door: it converses (context-frugal), delegates everything
real to isolated workers through the existing backend seam — repo-mutating
work as flights in their own worktrees, converging through review and
landing as draft PRs; read-only work as plain offloads returning to the
conversation (REQ-C1.6) — and escalates big or risky work into the
existing spec pipeline. The spec stops being the entry fee and becomes
what the tower escalates into; the audit record, not the spec, is the trust
differentiator that travels with every piece of work. Routing between the
two flight rules — visual flight (specless: no spec bundle is authored,
and the audit record carries the trust) and instrument flight (the spec
pipeline) — is the proportionality doctrine operationalized one level up:
stake and reversibility decide, per request, with the decision and its
grounds always stated. The deliverable sits at capability-plus-doctrine
altitude (D-1): the routing rule and the vocabulary land as doctrine, the
existing seams are consumed rather than re-owned, and the `/tower` skill is
the mechanism filling the entrance seam.
*(Cites: D-1, D-2, the tower-front-door seed (Sources).)*

## Scope

### In scope

- The `/tower` entry skill: a standing conversational session under the
  tower permission posture.
- The per-request flight-rules router with declared criteria, stated
  grounds, and a trivial two-way override.
- Visual-flight execution: isolated worktree per flight on its own branch
  segment, dispatch through the existing backend seam and `/offload`
  placement logic, review convergence, always a draft PR carrying the
  audit record.
- Instrument-flight handoff: escalation drafts or extends a spec via the
  existing `/spec-draft` machinery, presents the case for filing, and
  offers — never starts — `/spec-kickoff`.
- Attention and interruption semantics: decision-queue posture,
  deterministic lifecycle pushes, reconstruction after tower death,
  dead-worker policy.
- The audit-and-trust guarantees for specless work.
- The staged vocabulary inversion: glossary supersession and definitional
  sites in v1, the pervasive prose sweep deferred behind a gate.
- Docs inversion: README leads with `/tower`; the adopted demotion list;
  the two-controls story (the draft→ready flip and the merge) restated as
  unchanged on both paths.

### Out of scope

- User-history / trust-ramp routing (deferred with a gate; see `tasks.md`).
- Multi-repo or cross-repo tower: one tower per repo checkout, as today's
  conventions assume.
- Fleet-mode integration beyond seam reuse: the tower supervises no
  spec-mode orchestrators and does not fold into `--meta`; a chat front
  door onto a running fleet is its own feature.
- Renames of existing skills (deferred behind the pending marketplace
  review; see `tasks.md`).
- Bootstrapping un-scaffolded repositories (no `specs/`, or no git
  repository): the inception spec's entrance seam owns the
  start-from-nothing case; `/tower` may point the user there.
- Persistent memory of past flights beyond the audit trail (preference
  learning, style adaptation).
- Any change to sign-off or merge semantics.

## REQ-A — The entrance

- **REQ-A1.1** A single entry skill, `/tower`, SHALL provide a standing
  conversational session as the framework's front door, and the happy path
  SHALL require no framework vocabulary or machinery knowledge from the
  user; the flight-rule names with their REQ-H1.4 first-use gloss are not
  framework vocabulary for this purpose — pipeline machinery terms are.
  *(Cites: D-2, the tower-front-door seed (Sources).)*
- **REQ-A1.2** The tower session SHALL obey the tower-frugality axiom:
  inline work is bounded to pure reasoning over existing context and the
  operational heartbeat; everything with large or unpredictable context
  ingestion SHALL be offloaded.
  *(Cites: D-1, work-placement doctrine (Sources).)*
- **REQ-A1.3** The tower SHALL run under the tower permission posture
  (`config/tower-settings.json` or an extension of it); an extension MAY
  add tower-oriented allow shapes and SHALL NOT weaken the deny floor.
  *(Cites: D-14, the tower-front-door seed (Sources).)*
- **REQ-A1.4** The feature SHALL be built from Claude Code primitives only
  (skills, hooks, subagents, slash commands, file-based state): no second
  agent framework, and no daemon beyond what the fleet layer already
  defines.
  *(Cites: the tower-front-door seed (Sources), the legacy observations
  log line 102 (Sources).)*
- **REQ-A1.5** The tower SHALL remain the operator's conversational window
  onto all planwright work, spec-mode included: status on demand for any
  spec or flight, rendered from durable evidence through the existing
  status surfaces, and reserved-control relays on explicit request
  (today's enumerated relay: the post-sign-off go, REQ-D1.4). It
  SHALL NOT supervise or poll spec-mode execution; spec-mode pushes stay
  on the existing fleet surfaces.
  *(Cites: kickoff §3 (2026-09-01), REQ-D1.4.)*

## REQ-B — The router

- **REQ-B1.1** The tower SHALL choose flight rules per request — visual
  flight (specless) or instrument flight (the spec pipeline) — and flight
  rules SHALL never be a user-selected mode, flag, or persistent setting.
  *(Cites: D-3, the tower-front-door seed (Sources).)*
- **REQ-B1.2** Work centered in a hard-disqualifier zone, or otherwise not
  one-revert-from-undone (published interfaces, data deletion, external
  side effects), SHALL escalate to instrument flight automatically;
  ambiguity — the tower cannot state a Done-when the user would agree
  with — SHALL escalate by declared judgment; size proxies SHALL be
  advisory only and never decisive.
  *(Cites: D-4, proportionality doctrine (Sources), finding-categorization
  doctrine (Sources).)*
- **REQ-B1.3** The routing decision and its grounds SHALL be stated to the
  user at routing time; routing SHALL never be silent.
  *(Cites: D-4, proportionality doctrine (Sources).)*
- **REQ-B1.4** A one-sentence override SHALL force either flight rule in
  either direction; when an override crosses an automatic escalation
  trigger the tower SHALL state its reservation and comply; no override
  SHALL cross a hard invariant (REQ-G).
  *(Cites: D-5.)*
- **REQ-B1.5** Routing is preventive, not enforcement: the gate-wiring
  hard pauses SHALL remain in force in every worker regardless of the
  route chosen.
  *(Cites: D-4, finding-categorization doctrine (Sources).)*
- **REQ-B1.6** The router's judgment SHALL be gated by behavioral-eval
  fixtures derived from the acceptance scenarios before any user-facing
  doc surface (the Task 12 set) claims the routing behavior as
  demonstrated; doctrine and skill text state the routing rule as law,
  never as demonstrated behavior.
  *(Cites: D-13, kickoff lens review (2026-09-01).)*

## REQ-C — Visual flight

- **REQ-C1.1** Each visual flight SHALL run in its own isolated worktree
  on branch `planwright/flight/<flight-id>`; `flight` SHALL be a reserved
  segment no spec may claim; flight ids SHALL be collision-free across
  concurrent flights and never reused against durable evidence (branches,
  record files).
  *(Cites: D-11, obs:96261531, obs:5001e9f4.)*
- **REQ-C1.2** Flight dispatch SHALL route through the existing backend
  seam and `/offload`'s placement axioms; no parallel placement or rung
  selection logic SHALL be introduced.
  *(Cites: the tower-front-door seed (Sources), work-placement doctrine
  (Sources), the fold-detection scan (Sources).)*
- **REQ-C1.3** Flight workers SHALL load full doctrine and converge
  through the one configured `review_sequence`; proportionality MAY scope
  rigor inside that sequence, and any scoping actually applied SHALL be
  declared in the flight's audit record.
  *(Cites: D-7.)*
- **REQ-C1.4** Every visual flight SHALL land as a draft PR where a remote
  and `gh` are available (its branch plus committed record otherwise, per
  REQ-E1.2); the draft-to-ready flip SHALL remain the human's.
  *(Cites: D-6, the tower-front-door seed (Sources).)*
- **REQ-C1.5** Concurrent flights SHALL be governed at dispatch time: the
  dispatch path SHALL count the checkout's live flights against the
  existing `max_parallel_units` value and decline, with a stated re-ask
  path, any flight beyond it; no durable flight queue, new store, or new
  knob SHALL be introduced, and visual flight SHALL NOT introduce an
  ungoverned parallel worker pool.
  *(Cites: drafting-session decision (2026-08-27), kickoff §3 REQ-C
  (2026-09-01).)*
- **REQ-C1.6** A flight is a unit of repo-mutating specless work;
  "instrument flight" names only the route, never a flight unit. A
  read-only ask exceeding the inline bound SHALL be offloaded through the
  existing work-placement axioms without flight identity — no flight
  branch, worktree, draft PR, or flight record — with the result returned
  to the conversation. A mutation need surfaced mid-offload SHALL return
  as a new routed request — a read-only worker never converts in place.
  An ask MAY decompose into several flights, one per coherent unit, each
  routed with stated grounds.
  *(Cites: kickoff §3 REQ-C (2026-08-28), work-placement doctrine
  (Sources).)*

## REQ-D — Instrument flight

- **REQ-D1.1** Escalation SHALL produce the spec bundle via the existing
  `/spec-draft` machinery, fold-detection against existing specs included.
  *(Cites: D-4, the tower-front-door seed (Sources).)*
- **REQ-D1.2** At escalation the tower SHALL present a one-page case for
  why the ask files a flight plan.
  *(Cites: the tower-front-door seed (Sources).)*
- **REQ-D1.3** The tower SHALL offer `/spec-kickoff` and SHALL NOT start
  it; sign-off remains a reserved human control, unchanged.
  *(Cites: the tower-front-door seed (Sources).)*
- **REQ-D1.4** After sign-off the tower MAY dispatch orchestration of the
  signed spec only on an explicit per-request user go; it SHALL NOT
  self-start orchestration on sign-off completion or on the spec PR's
  merge.
  *(Cites: D-15.)*

## REQ-E — The audit record

- **REQ-E1.1** Every visual flight's audit record SHALL carry: the quoted
  ask, the routing decision and its grounds, the convergence audit tables
  the review skills produce (lens coverage, the four buckets, the declined
  log, the pending-sign-off checklist), any rigor scoping applied
  (REQ-C1.3), the worker handle, and the revert path. The flight worker
  authors and lands the record.
  *(Cites: D-6, the tower-front-door seed (Sources).)*
- **REQ-E1.2** The record's authoritative home SHALL be adaptive,
  determined and declared at routing time: the draft PR body where a
  remote and `gh` are available; a committed per-flight record file at
  `specs/_flights/<flight-id>.md` riding the flight's own branch
  otherwise.
  *(Cites: D-6, obs:fcc5f742, obs:2bea1358.)*
- **REQ-E1.3** The local flight index SHALL be derived, regenerable from
  durable evidence, and never committed; it is a cache, not an
  accumulator — it owes no drain ritual and SHALL NOT become a second
  source of truth.
  *(Cites: D-6.)*
- **REQ-E1.4** Specless traceability is defined as: the ask, the route and
  its grounds, the evidence, and the revert path, cited in the record;
  REQ-level traceability is precisely what escalation to instrument flight
  buys.
  *(Cites: D-6, the tower-front-door seed (Sources).)*
- **REQ-E1.5** The record SHALL render human-first in both homes: a lead a
  human PR author would write — what changed, why, and how it was
  verified, with no restated prompt and no filler — followed by the full
  REQ-E1.1 contract in a collapsed section, the quoted ask sanitized per
  the security-posture data-hygiene rule and markup-neutralized (escaped
  or fenced) so embedded markup cannot alter the record's structure or
  its downstream parsing.
  *(Cites: kickoff §3 REQ-E (2026-09-01), security-posture doctrine
  (Sources).)*

## REQ-F — Attention and survival

- **REQ-F1.1** The tower's push surface SHALL be the decision queue:
  workers blocked on a human decision, plus deterministic flight lifecycle
  events (dispatch, awaiting-decision, completion; crash-policy
  escalations per REQ-F1.5); everything else SHALL be status on demand,
  with each flight reporting its landing reference on completion (the
  draft-PR link, or the branch and record path on the no-remote arm).
  *(Cites: D-8, obs:bfc6faf0.)*
- **REQ-F1.2** Flight lifecycle events SHALL reach the attention store
  by deterministic push (hooks and scripts); tower polling SHALL be
  fallback only, never the sole mechanism.
  *(Cites: D-8, obs:bfc6faf0.)*
- **REQ-F1.3** Work SHALL survive the tower by construction: flights run
  on rungs that outlive the tower session that dispatched them, and
  worktrees and branches are durable. The guarantee is stated in the
  REQ-F1.6 bounded-or-surfaced form: a killed tower leaves every residue
  bounded and swept, or durably surfaced — never silently lost.
  *(Cites: D-9, the tower-front-door seed (Sources).)*
- **REQ-F1.4** A fresh tower session SHALL reconstruct in-flight state
  (the flight sweep's scope; spec-mode state renders on demand per
  REQ-A1.5) from durable evidence at session start, and `/resume` SHALL
  gain a tower-level sweep mode; both surfaces SHALL consume one shared
  sweep implementation.
  *(Cites: D-9, obs:c6107c38.)*
- **REQ-F1.5** Dead flight workers SHALL inherit the fleet crash-loop
  policy (the fleet worker crash knobs, not the tower-relaunch family):
  bounded backoff relaunch resuming the flight's own worktree and branch,
  then escalation to the human at the disable threshold.
  *(Cites: D-10.)*
- **REQ-F1.6** Survival and cleanup guarantees SHALL be stated
  bounded-or-surfaced, never absolute: every residue is bounded and swept,
  or durably surfaced to the operator — never silent.
  *(Cites: D-10, obs:7d475b1e.)*

## REQ-G — Hard invariants

- **REQ-G1.1** planwright SHALL never auto-merge; merge is a reserved
  human action, permanently, on both flight rules.
  *(Cites: the tower-front-door seed (Sources).)*
- **REQ-G1.2** Sign-off SHALL stay reserved for specs: the specless path
  SHALL NOT invent a shadow sign-off, the spec path SHALL NOT lose its
  real one, and no bypass flag for the non-signed-spec refusal SHALL
  exist or be added. (Forbidden is any named sign-off ritual gating a
  flight's landing; the worker hard pauses and the record's
  pending-sign-off checklist are not a sign-off.)
  *(Cites: the tower-front-door seed (Sources), kickoff lens review
  (2026-09-01).)*
- **REQ-G1.3** No force-push, amend, squash, or rebase, on either flight
  rule: new commits only.
  *(Cites: the tower-front-door seed (Sources).)*
- **REQ-G1.4** PRs SHALL always open as drafts; the human's draft-to-ready
  flip is the universal review gate, and the one existing exception
  (`/spec-kickoff`'s spec-PR ready flip) is untouched.
  *(Cites: the tower-front-door seed (Sources).)*
- **REQ-G1.5** The named existing seams SHALL be reused, and no parallel
  machinery SHALL be built: worktree conventions, the backend seam and
  placement axioms, `review_sequence` convergence, the fleet attention
  surface, and the tower permission posture.
  *(Cites: the tower-front-door seed (Sources), the fold-detection scan
  (Sources).)*

## REQ-H — Vocabulary and docs

- **REQ-H1.1** The glossary SHALL be superseded so that **Tower** names
  the standing conversational front-door session and **Orchestrator** is
  minted for the dispatching `/orchestrate` session, with a transitional
  note that older prose may use "tower" for the orchestrator until the
  sweep completes and that tower-named scripts and config may serve
  either session until renames land; the Orchestrator entry SHALL carry
  a one-line distinction from Operator, the human.
  *(Cites: D-2, kickoff §3 REQ-H (2026-09-01).)*
- **REQ-H1.2** v1 SHALL update only the definitional sites (the
  spec-format glossary, work-placement's consumer naming, the fleet doc's
  opening vocabulary, and the `/orchestrate` skill description's "control
  tower" line); the pervasive prose sweep is deferred behind its gate.
  *(Cites: D-2, kickoff lens review (2026-09-01).)*
- **REQ-H1.3** The README SHALL lead with `/tower` as the entrance;
  `/orchestrate`, `/execute-task`, `/resume`, and `/offload` SHALL move to
  advanced/architecture documentation under their existing names;
  `/spec-kickoff`, `/spec-draft`, `/spec-walkthrough`, `/drain`, and
  `/builder` SHALL stay front-facing; `/self-review` and `/polish` stay
  where they are, unchanged in place; and the two permanent human
  controls — the draft→ready flip and the merge, held on both paths, with
  sign-off the spec path's additional reserved control — SHALL be
  restated as unchanged.
  *(Cites: D-2, drafting-session decision (2026-08-27), kickoff lens
  review (2026-09-01).)*
- **REQ-H1.4** The flight rules SHALL be named **visual flight** and
  **instrument flight**, with a one-sentence gloss of the analogy at first
  use on each doc surface.
  *(Cites: D-3.)*

## Changelog

- 2026-08-27 — Initial draft: bundle elicited from the tower-front-door
  seed document; all seven decision forks and the eight operator questions
  resolved or explicitly gated during the drafting session.
- 2026-08-28 — Kickoff walkthrough edits (meaning-class, applied in
  Draft): REQ-C1.6 minted — the flight boundary (a flight is
  repo-mutating work; read-only offloads carry no flight identity);
  un-scaffolded-repository bootstrapping declared out of scope (the
  inception seam).
- 2026-09-01 — Kickoff walkthrough edits (meaning-class, applied in
  Draft): REQ-E1.5 minted — human-first record rendering (human lead, no
  restated prompt, full audit contract collapsed below, quoted ask
  sanitized); Task 1 gains the mid-offload re-route rule and the
  one-ask-many-flights decomposition rule (both later folded up into
  REQ-C1.6 by the lens-review batch below); security-posture added to the
  consulted-doctrine sources; REQ-A1.5 minted — the tower stays the
  operator's window onto all planwright work (status on demand,
  reserved-control relays) while never supervising or polling spec-mode
  execution; REQ-H1.1 extended with two transition guardrails (the
  transitional note covers tower-named scripts/config, the Orchestrator
  glossary entry distinguishes itself from Operator). Files touched
  across the two walkthrough batches: `requirements.md`, `tasks.md`
  (Task 1/2/4/5/6 deliverables and citations), `test-spec.md` (paired
  entries for REQ-C1.6, REQ-A1.5, REQ-E1.5).
- 2026-09-01 — Kickoff lens-review batch (meaning-class, applied in
  Draft, operator-approved as clusters A1–A14 plus two fork resolutions;
  full disposition record in `kickoff-brief.md` §8): one PR-arm predicate
  (remote and `gh`) across REQ-C1.4/E1.2 with adaptive landing references
  (REQ-F1.1); flight noun pinned and REQ-C1.6 extended (re-route,
  decomposition); REQ-C1.5 re-decided as the dispatch-time check against
  `max_parallel_units` with conversational deferral; REQ-E1.1 scoped to
  visual flights, gains the rigor-scoping element and worker authorship;
  REQ-E1.5 gains markup neutralization; REQ-F1.1–F1.5 precision pins;
  REQ-F1.3 restated bounded-or-surfaced; REQ-B1.6 rescoped to user-facing
  docs; REQ-G1.2 boundary parenthetical; REQ-H1.2 gains the fourth
  definitional site; REQ-H1.3 names the two controls and the
  unchanged-in-place skills; REQ-A1.1 vocabulary boundary; REQ-A1.5
  relay enumeration; Sources corrections (obs glosses, line-144 entry,
  obs:7f0b4274 added); `tasks.md` ownership sweep, Done-when hardening,
  Task 13 (acceptance demo script) added; `test-spec.md` entries aligned
  and E-group reordered.

## Sources

- **The tower-front-door seed document** (2026-08-27, session-provided
  self-contained drafting seed): thesis, hard constraints, the flight-rules
  taxonomy, seven decision forks with leanings, candidate requirement
  areas, five acceptance scenarios, the v1 cut, and the external category
  evidence (spec-ceremony criticism of Kiro and GitHub Spec Kit; the
  superpowers doctrine-without-pipeline counter-evidence).
- **Pinned altitude seed claims** (from the seed, per the autopilot-reflex
  seed-claim trigger): "progressive disclosure… the Rails-like front
  door"; "the routing principle already exists" (proportionality
  operationalized one level up); "the two paths are flight rules… never
  user-selected modes".
- **obs:bfc6faf0** — PR-ready reached the human only via tower polling,
  which failed live; deterministic events must push, tower polling is
  fallback.
- **obs:c6107c38** — derivation ignored live backend liveness evidence and
  re-offered an in-flight unit; reconstruction must consult durable
  runtime evidence.
- **obs:fcc5f742** — the shared fleet-audit trail is unfit as a per-unit
  record store (no row identity, silent truncation, lock contention).
- **obs:2bea1358** — audit-store write amplification inside the fleet
  lock; per-request volume is the load it warns about.
- **obs:7d475b1e** — the bounded-or-surfaced guarantee shape, re-derived
  across four kickoff halts.
- **obs:96261531** — the sanctioned dispatch path accepts only a single
  spec task id; no dispatch or naming path exists for a non-spec unit of
  work.
- **obs:5001e9f4** — the worktree suffix grammar collides across specs
  (two specs sharing a task number); ad-hoc units need their own
  collision-free segment.
- **obs:7f0b4274** — the fix-location rule: whether a finding is zone work
  is governed by where the fix lands; surfaced as an unconsumed
  observation and adopted by D-4's first recorded refinement.
- **The legacy observations log line 39** (2026-06-12, consumed in place):
  the emulated-orchestrator protocol; a standing control session's
  instructions double as its handover document.
- **The legacy observations log line 102** (2026-06-23, consumed in
  place): Claude Code dynamic workflows are user-initiated only and cannot
  pause for human input; the portable primitives are subagents, hooks,
  agent teams, and skills. (REQ-A1.4's enumerated list is this bundle's
  own: it adds slash commands and file-based state and folds agent teams
  into subagents, deliberately.)
- **The legacy observations log line 144** (cited by D-2, left unconsumed
  for its own drain): an unresolved dual-registry naming confusion whose
  candidate remedy is naming the two layers distinctly — cited as the
  precedent *problem* motivating distinct layer names, not as a resolved
  precedent.
- **Doctrine consulted:** proportionality (the routing principle),
  security-posture (artifact data-hygiene, consulted at kickoff for the
  record's quoted-ask handling),
  work-placement (tower-frugality, the escalation predicates),
  finding-categorization (the four buckets, hard-disqualifier zones, hard
  pauses), spec-format (lifecycle, glossary, branch grammar),
  autopilot-reflex (altitude triggers, push-not-pull),
  customization-boundary (the zero-new-knobs call), engineering-decisions
  and the decision-domains catalog (the design-phase walk).
- **The fold-detection scan** (2026-08-27, 27 bundles): no bundle owns the
  entrance; the owned seams recorded as reuse constraints —
  execution-backends (`/offload`, backend contract), orchestration-fleet
  (entry command, decision queue), fleet-autonomy (watchdog, crash
  policy), operator-dialogue (attended-dialogue disciplines), inception
  (the upstream no-repo entrance), concurrent-orchestrator-coordination
  (multiplicity discipline), fleet-lifecycle-closure (worker lifecycle),
  model-allocation (tier resolution at every launch point).
- **Drafting-session decisions** (2026-08-27): the operator walk recorded
  in this bundle's D-IDs and the fork resolutions cited as
  drafting-session decisions.
