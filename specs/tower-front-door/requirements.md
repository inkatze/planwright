# Tower front door — Requirements

**Status:** Draft
**Last reviewed:** 2026-08-27
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright's only entrance today is a spec bundle: every piece of work,
however small, pays the four-file ceremony before anything runs, and small
work routes around the tool entirely. This spec inverts the entrance. A
single standing conversational session — the `/tower` skill — becomes the
framework's front door: it converses (context-frugal), delegates everything
real to isolated worktree workers through the existing backend seam with
full review convergence and draft PRs, and escalates big or risky work into
the existing spec pipeline. The spec stops being the entry fee and becomes
what the tower escalates into; the audit record, not the spec, is the trust
differentiator that travels with every piece of work. Routing between the
two flight rules — visual flight (specless) and instrument flight (the spec
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
  the two-controls story restated as unchanged on both paths.

### Out of scope

- User-history / trust-ramp routing (deferred with a gate; see `tasks.md`).
- Multi-repo or cross-repo tower: one tower per repo checkout, as today's
  conventions assume.
- Fleet-mode integration beyond seam reuse: the tower supervises no
  spec-mode orchestrators and does not fold into `--meta`; a chat front
  door onto a running fleet is its own feature.
- Renames of existing skills (deferred behind the pending marketplace
  review; see `tasks.md`).
- Persistent memory of past flights beyond the audit trail (preference
  learning, style adaptation).
- Any change to sign-off or merge semantics.

## REQ-A — The entrance

- **REQ-A1.1** A single entry skill, `/tower`, SHALL provide a standing
  conversational session as the framework's front door, and the happy path
  SHALL require no framework vocabulary or machinery knowledge from the
  user.
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
  fixtures derived from the acceptance scenarios before any doc surface
  claims the routing behavior.
  *(Cites: D-13.)*

## REQ-C — Visual flight

- **REQ-C1.1** Each visual flight SHALL run in its own isolated worktree
  on branch `planwright/flight/<flight-id>`; `flight` SHALL be a reserved
  segment no spec may claim; flight ids SHALL be collision-free across
  concurrent flights.
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
  exists (its branch plus committed record otherwise, per REQ-E1.2); the
  draft-to-ready flip SHALL remain the human's.
  *(Cites: D-6, the tower-front-door seed (Sources).)*
- **REQ-C1.5** Concurrent flights SHALL count against the fleet's existing
  parallel-unit governance (the fleet concurrency knobs); visual flight
  SHALL NOT introduce an ungoverned parallel worker pool.
  *(Cites: drafting-session decision (2026-08-27), the fold-detection scan
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

- **REQ-E1.1** Every flight's audit record SHALL carry: the quoted ask,
  the routing decision and its grounds, the convergence audit tables the
  review skills produce (lens coverage, the four buckets, the declined
  log, the pending-sign-off checklist), the worker handle, and the revert
  path.
  *(Cites: D-6, the tower-front-door seed (Sources).)*
- **REQ-E1.2** The record's authoritative home SHALL be adaptive and
  declared at routing time: the draft PR body where a remote and `gh` are
  available; a committed per-flight record file at
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

## REQ-F — Attention and survival

- **REQ-F1.1** The tower's push surface SHALL be the decision queue:
  workers blocked on a human decision, plus deterministic flight lifecycle
  events; everything else SHALL be status on demand, with each flight
  reporting its draft-PR link on completion.
  *(Cites: D-8, obs:bfc6faf0.)*
- **REQ-F1.2** Flight lifecycle events SHALL reach the attention surface
  by deterministic push (hooks and scripts); tower polling SHALL be
  fallback only, never the sole mechanism.
  *(Cites: D-8, obs:bfc6faf0.)*
- **REQ-F1.3** Work SHALL survive the tower by construction: flights run
  on rungs that outlive the dispatching session, and worktrees and
  branches are durable; a killed tower SHALL lose no work.
  *(Cites: D-9, the tower-front-door seed (Sources).)*
- **REQ-F1.4** A fresh tower session SHALL reconstruct in-flight state
  from durable evidence at session start, and `/resume` SHALL gain a
  tower-level sweep mode; both surfaces SHALL consume one shared sweep
  implementation.
  *(Cites: D-9, obs:c6107c38.)*
- **REQ-F1.5** Dead flight workers SHALL inherit the fleet crash-loop
  policy: bounded backoff relaunch, then escalation to the human at the
  disable threshold.
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
  exist or be added.
  *(Cites: the tower-front-door seed (Sources).)*
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
  sweep completes.
  *(Cites: D-2.)*
- **REQ-H1.2** v1 SHALL update only the definitional sites (the
  spec-format glossary, work-placement's consumer naming, the fleet doc's
  opening vocabulary); the pervasive prose sweep is deferred behind its
  gate.
  *(Cites: D-2.)*
- **REQ-H1.3** The README SHALL lead with `/tower` as the entrance;
  `/orchestrate`, `/execute-task`, `/resume`, and `/offload` SHALL move to
  advanced/architecture documentation under their existing names;
  `/spec-kickoff`, `/spec-draft`, `/spec-walkthrough`, `/drain`, and
  `/builder` SHALL stay front-facing; and the two permanent human controls
  SHALL be restated as unchanged on both paths.
  *(Cites: D-2, drafting-session decision (2026-08-27).)*
- **REQ-H1.4** The flight rules SHALL be named **visual flight** and
  **instrument flight**, with a one-sentence gloss of the analogy at first
  use on each doc surface.
  *(Cites: D-3.)*

## Changelog

- 2026-08-27 — Initial draft: bundle elicited from the tower-front-door
  seed document; all seven decision forks and the eight operator questions
  resolved or explicitly gated during the drafting session.

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
- **obs:96261531** — no dispatch or naming path exists for a non-spec unit
  of work.
- **obs:5001e9f4** — the worktree suffix grammar collides across specs;
  ad-hoc units need their own collision-free segment.
- **The legacy observations log line 39** (2026-06-12, consumed in place):
  the emulated-orchestrator protocol; a standing control session's
  instructions double as its handover document.
- **The legacy observations log line 102** (2026-06-23, consumed in
  place): Claude Code dynamic workflows are user-initiated only and cannot
  pause for human input; the portable primitives are subagents, hooks,
  agent teams, and skills.
- **Doctrine consulted:** proportionality (the routing principle),
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
