# Inception — Tasks

**Status:** Ready
**Last reviewed:** 2026-07-13
**Format-version:** 1

Sequencing intent (derived view; the `Dependencies:` lines are authoritative): the
**walking-skeleton arc** ships a minimal usable `/inception` first — Task 1 → Task 2 → Task 7 →
Task 8 with the Task 12 stub — so real ventures can dogfood plain elicitation + bundle + repo
while the persona layer (Tasks 4–6, 9) and surfaces (Tasks 12–13) build behind it. Task 17
(dogfood) starts as soon as the skeleton stands and runs continuously, not last. Guard
infrastructure leads: the format doctrine and validator gate everything that writes bundles.

## Forward plan

### Task 1 — inception-format doctrine

- **Deliverables:** `doctrine/inception-format.md`: bundle file set and grammar, frame template,
  A-ID/T-ID/decision-ID grammars, venture lifecycle (including Abandoned and On-hold), kill
  criteria and structured machine-readable gate-record forms, the MADR decision fields, the
  assumption evidence-ladder + fail-condition + synthetic-grade format, plan-task time/cost caps
  and constraint-ordering, the sources register and stakeholder/decision-rights map grammars,
  minimum core, and format-version rules (additive-within-major evolution + reader version-gating
  with a fail-closed non-zero exit).
- **Done when:** the doc defines every structure REQ-C names; `check-doc-links` passes; the
  doctrine README indexes it.
- **Dependencies:** none
- **Citations:** D-1, D-18 · REQ-C1.1–C1.11, REQ-I1.1
- **Estimated effort:** 2 days

### Task 2 — inception validator & venture hygiene scaffold

- **Deliverables:** `scripts/inception-validate.sh` (minimum core, ID grammar and uniqueness,
  register and gate-record integrity, `Format-version:` gating with fail-closed on unsupported
  versions, the new register fields; seeded-violation fixtures under `tests/`, including an
  unsupported-version fixture); the venture repo scaffold (`.gitignore`, commit-time secret
  screening hook-in, pre-commit export-regeneration step — Task 2 ships a dashboard-fields-only stub
  renderer that satisfies this step until Task 12 replaces it — remote-rung secret-scan CI
  template); rung-scaled wiring notes.
- **Done when:** validator fixtures pass under `mise run test`; each enforced rule has a
  seeded-violation fixture; scaffold files are emitted by a tested helper.
- **Dependencies:** 1
- **Citations:** D-12 · REQ-A1.9, REQ-C1.7, REQ-C1.8, REQ-G1.1, REQ-G1.5
- **Estimated effort:** 2 days

### Task 3 — doctrine extensions: domains, lenses, evidence, storage classes

- **Deliverables:** decision-domains additions (product strategy, packaging/pricing, domain and
  knowledge engineering, org design, IP posture, LLM-output quality, human-comprehension, and the
  existing-seam-reuse domain); the non-code lens set selected by artifact class; the
  evidence-quality doctrine (believe/verify/measure/right-if falsifiability format, pre-committed
  thresholds expressible as fail conditions, the commitment-weighted evidence ladder with a named
  synthetic-evidence grade excluded from desirability Graduate thresholds); the storage-classes
  rule.
- **Done when:** each doc resolves via the rule-doc chain; the seam-reuse domain names the core
  seams; the lens-selection rule states when code lenses do not apply.
- **Dependencies:** none
- **Citations:** D-1, D-17 · REQ-I1.2–I1.5
- **Estimated effort:** 3 days

### Task 4 — card schema doctrine, authoring recipe, product-strategy card

- **Deliverables:** the card schema and register rules as doctrine (including the out-of-scope
  line, documented blind spots, conflict/deference rules, the own-discipline independence note (a
  seat cannot self-validate), optional stance axis, named knowledge-sources, ordered framework
  sequence, and the typed escalation-trigger taxonomy); the card-authoring recipe (research-grounded
  distillation method); the product-strategy card (from the worked example, primary sources
  re-verified).
- **Done when:** the card lints against its own schema; the recipe is followable without this
  spec's session context; anti-authority styling rules are explicit.
- **Dependencies:** 3
- **Citations:** D-3, D-4 · REQ-P1.1, REQ-P1.2, REQ-P1.10
- **Estimated effort:** 2 days

### Task 7 — /inception skill core (walking skeleton)

- **Deliverables:** the `/inception` skill: pre-flight (identifier derivation and validation,
  ventures_root resolution, ask-once home selection, ladder detection, ephemeral-env arm, repo
  creation with scaffold), phased elicitation (seed intake, discipline-catalog walk, reframing
  checkpoint, proportionality with skip-with-reason), bundle writing, resume; the skill refuses an
  unsupported `Format-version:` rather than parsing it (REQ-C1.7).
- **Done when:** a scripted dry run produces a validator-clean bundle in a fresh venture repo on
  both home arms; every degradation is reported at pre-flight and handoff.
- **Dependencies:** 1, 2, 3
- **Citations:** D-5, D-19 · REQ-A1.1–A1.5, REQ-A1.8–A1.9, REQ-B1.1–B1.7, REQ-H1.1–H1.5
- **Estimated effort:** 4 days

### Task 8 — registry, telemetry, feedback drop, portfolio view

- **Deliverables:** plugin-data helpers for the venture registry (atomic write-temp-then-rename
  mutations, and scan-rebuild recovery from `ventures_root` per REQ-A1.6), catalog telemetry, and
  the pending-observations drop; the per-venture in-session status view (gate readiness, blockers,
  kill dates) and the no-arg portfolio listing with attention flags and catalog-health notes;
  overlap-scan wiring into pre-flight.
- **Done when:** helper round-trip tests pass; the portfolio view renders fixture registries;
  drop entries are read by a planwright-repo seed-gathering probe with neutralization.
- **Dependencies:** 1
- **Citations:** D-8 · REQ-A1.6–A1.7, REQ-H1.6, REQ-J1.4, REQ-J1.7–J1.8
- **Estimated effort:** 2 days

### Task 12 — renderer: dashboard + pitch modes

- **Deliverables:** the inception renderer (POSIX shell, self-contained escaped HTML; shared
  escaper helper), dashboard and pitch-narrative modes, regenerate-on-commit wiring via the
  scaffolded pre-commit step (every rung), the offered Artifact publish step with the per-venture
  auto-republish knob (default off); the renderer refuses an unsupported `Format-version:` rather
  than rendering it (REQ-C1.7). The dashboard-fields-only stub renderer shipped by Task 2 is
  replaced here.
- **Done when:** determinism and escaping fixtures pass; dashboard reflects fixture registers;
  publish is offer-only in a scripted run.
- **Dependencies:** 1
- **Citations:** D-9 · REQ-G1.1–G1.4, REQ-G1.9
- **Estimated effort:** 2 days

### Task 5 — remaining six core cards

- **Deliverables:** pricing/packaging, domain and knowledge engineering, org design, IP, AI/agent
  architecture, and software engineering cards, authored per the recipe from the research
  distillations, primary sources re-verified (IP and AI-arch flagged high-rot).
- **Done when:** all cards lint; each carries tier placements with per-activity exceptions and
  staleness metadata.
- **Dependencies:** 4
- **Citations:** D-3, D-4, D-17 · REQ-P1.1, REQ-P1.2, REQ-P1.10
- **Estimated effort:** 3 days

### Task 6 — ML/LLM engineering & evals card

- **Deliverables:** the commissioned eighth card, research-grounded per the recipe (model
  selection, fine-tuning vs retrieval, eval-gate design, criteria drift).
- **Done when:** card lints; tier placements and staleness metadata present; recipe citations
  recorded.
- **Dependencies:** 4
- **Citations:** D-17 · REQ-P1.11
- **Estimated effort:** 2 days

### Task 9 — persona fan-out

- **Deliverables:** frame authoring per the normative template; seat dispatch through the backend
  capability contract (card-to-brief compilation, stake-scored seat-count triage where the signal
  is cheap, per-seat model override where the backend advertises it, Gate 1 staffing and cost
  disclosure); the synthesis writer working blind on anonymized, order-shuffled seat inputs
  (agreements/tensions/open-questions table, claim-type-annotated convergence marks with named
  outliers) with the orchestrator re-attaching seat attribution into the table; the persona-free
  challenge pass; Gate 2 mechanics with typed human-power choices; staffing-table honesty with
  unstaffed-risk auto-filing and the zero-seat collapse row.
- **Done when:** one full fan-out completes on the subagent rung and one on the tmux rung against
  a fixture venture; every seat artifact ends with the mandatory escalation section; gates are
  main-thread structured choices; the synthesis writer's input carries no seat identity or
  ordering cue, and attribution is re-attached only in the final table.
- **Dependencies:** 4, 7
- **Citations:** D-2, D-6, D-7, D-18 · REQ-P1.3–P1.9, REQ-B1.3
- **Estimated effort:** 4 days

### Task 10 — venture-task contract in /execute-task

- **Deliverables:** the venture-task execution path: kind-keyed contract (spike / research /
  analysis / demand-signal / alignment), PR-less findings commits, human acceptance, atomic
  register updates, `spikes/` discipline, external-interaction ban.
- **Done when:** a dispatched fixture task lands findings plus register update in one change;
  acceptance is required before the update; kinds parse per the format doctrine.
- **Dependencies:** 1, 7
- **Citations:** D-7, D-13 · REQ-D1.1–D1.7, REQ-J1.3
- **Estimated effort:** 2 days

### Task 11 — gate & graduation

- **Deliverables:** the gate move (minimum-core evaluation, completeness check, kill-criteria
  trip surfacing, four outcomes, dated structured machine-readable gate records with decider from
  the stakeholder map, evidence cited, and thresholds evaluated); the graduation seed package
  (prepared for the human to invoke `/spec-draft`; graduation never auto-chains downstream,
  REQ-J1.6); bidirectional lineage records; kill/abandon archival with post-mortem note and
  registry update.
- **Done when:** gate fixtures cover all four outcomes and the completeness check; a graduated
  fixture seed is consumed by `/spec-draft` seed-gathering in a probe run.
- **Dependencies:** 7, 10
- **Citations:** D-14, D-15 · REQ-E1.1–E1.6, REQ-F1.1–F1.4, REQ-J1.5, REQ-J1.6
- **Estimated effort:** 2 days

### Task 13 — adapter seam & Notion reference adapter

- **Deliverables:** the adapter seam contract (one-way-per-cycle, untrusted-input triage,
  section-granularity re-import, ID and gate-record protection); the Notion adapter
  (pinned-API-version markdown export via the Markdown Content API, unresolved-comment harvest with
  the repo triage ledger as the only disposition record, per-item triage, attributed commits).
- **Done when:** harvest parser fixtures pass on canned API payloads; one full cycle runs against
  a sandbox workspace; no code path applies feedback without human triage.
- **Dependencies:** 12
- **Citations:** D-10 · REQ-G1.6, REQ-G1.7
- **Estimated effort:** 3 days

### Task 14 — Cowork bridge & environment detection

- **Deliverables:** the sync-protocol instructions file emitted into venture repos (also imported
  from the venture root `CLAUDE.md`, with graceful egress-blocked-push/pull degradation);
  pre-flight capability detection (git present, plugin loaded, ephemeral filesystem); the
  "planwright loads in Cowork" validation run with findings recorded; a build-time re-verification
  step for the fast-rotting platform claims (Cowork behavior, web-sandbox persistence, Notion API)
  per the design's staleness concern.
- **Done when:** detection selects the right rung under env stubs; the Cowork validation is
  performed on a real Cowork install and its outcome logged (pass or documented blockers).
- **Dependencies:** 7
- **Citations:** D-5, D-11 · REQ-G1.8, REQ-H1.4
- **Estimated effort:** 1 day

### Task 15 — /spec-draft integration

- **Deliverables:** venture-seed consumption in `/spec-draft` seed-gathering; the upward altitude
  routing check (recommend-only); the feedback-drop reader in seed-gathering and bookkeeping.
- **Done when:** a graduated fixture seed surfaces in a `/spec-draft` probe with citations
  preserved; a pitch-shaped fixture input triggers the recommendation and declining proceeds
  normally.
- **Dependencies:** 8, 11
- **Citations:** D-15, D-16 · REQ-J1.1, REQ-J1.2, REQ-J1.8
- **Estimated effort:** 2 days

### Task 16 — adopter docs & options reference

- **Deliverables:** adopter documentation (venture lifecycle, non-engineer and expert modes,
  stakeholder surfaces, persona layer and its boundaries); options-reference rows for every new
  knob (`ventures_root`, auto-republish, adapter and backend notes).
- **Done when:** `check-options-reference` passes; docs link-check clean; the capability-vs-style
  classification of each knob is stated.
- **Dependencies:** 7, 9, 12
- **Citations:** D-5, D-9, D-17 · REQ-I1.6
- **Estimated effort:** 1 day

### Task 17 — continuous dogfood validation

- **Deliverables:** an end-to-end run of `/inception` on a real venture starting at the
  walking-skeleton milestone and continuing as layers land (elicitation, personas, tasks, gate,
  export); observations filed per run; format amendments proposed where friction recurs.
- **Done when:** at least one real venture has traversed idea → bundle → validation tasks → gate
  outcome using the shipped skill; telemetry and observations from the runs are recorded; format
  amendments are filed or explicitly found unnecessary.
- **Dependencies:** 7, 8, 12 to start; its completion criteria additionally exercise 9, 10, 11 as
  those layers land (the dogfood runs continuously, not as a terminal gate)
- **Citations:** D-17 · REQ-P1.11, REQ-J1.8
- **Estimated effort:** 2 days

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

(none yet)

## Deferred

- **Google Docs review-cycle adapter.** Richest comment model of the surveyed tools (resolved
  status, anchors, API resolve); auth is lighter than first assumed — the `drive.file` scope covers
  app-created files with no CASA assessment for the export-then-harvest cycle (a GCP project +
  OAuth consent screen still required). Strong v2 candidate. Confidence: medium.
  **Gate:** a venture whose stakeholders are Docs-native requests a two-way review cycle.
  Citations: D-10.
- **Outline review-cycle adapter.** The only surveyed tool with markdown round-trip, resolve-via-API,
  and text-anchored comments; self-hostable, fitting the own-your-truth posture. Limited reach:
  stakeholders live in Notion/Docs, not Outline. Confidence: medium.
  **Gate:** a venture whose stakeholders already use a shared Outline instance.
  Citations: D-10.
- **UX-research and GTM discipline cards.** Named parked candidates; no logged demand evidence
  yet. Confidence: high.
  **Gate:** unstaffed-discipline telemetry names either discipline in a real venture run.
  Citations: D-17, REQ-P1.11.
- **Content anchors for venture bundles.** Gate records are the v1 audit trail. Confidence:
  medium.
  **Gate:** orchestrated multi-session venture work demonstrates drift the gate records cannot
  catch.
  Citations: D-14.
- **SharePoint/OneDrive one-way export adapter.** Enterprise read copy only; save-fidelity
  unverified. Confidence: medium.
  **Gate:** an enterprise-audience venture needs a SharePoint reading surface.
  Citations: D-10.
- **claude.ai chat operator support (Agent-Skill repackaging plus a non-git truth rung).**
  A distribution effort, not a storage knob. Confidence: low.
  **Gate:** demand from chat-only operators plus a packaging design for skills outside Claude
  Code.
  Citations: D-5.

## Out of scope

- Symmetric two-way file synchronization with any external tool (documented failure mode).
- Auto-chaining into `/spec-draft`, `/spec-kickoff`, or `/orchestrate`; auto-merge at any tier.
- Deciding human-authority calls (price commitments, legal or tax interpretations, org decisions
  affecting people, one-way doors).
- Identity personas: backstories, credentials, seniority styling.
- Cross-repo and multi-target observation routing (`observation-routing`'s domain; the plugin-data
  drop is interim and re-anchors there).
- Concurrent multi-operator operation of a single venture (v1 is single-operator; a follow-on
  rides `orchestration-concurrency` patterns if demand appears).
- A Coda adapter (no comments API, lossy exports, no prior art; now rebranded under Superhuman).
- Generating the pitch itself; the skill structures ideas, it does not invent them.
