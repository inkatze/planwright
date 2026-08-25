# Decision-Domains Catalog

The model already holds most staff-engineering knowledge latently; the
failure mode is not ignorance but failing to stop and apply it at the
moment a decision is being made. This catalog turns that judgment into
triggers: an extensible, data-driven list of stake-bearing decision
domains, each entry naming what signals the domain, the questions a
senior practitioner of that domain asks before deciding, and what the agent
does with the answer. It is the trigger list behind the no-flattening rule in
[engineering-decisions.md](engineering-decisions.md).

The catalog spans engineering and non-engineering domains. Engineering
entries ask what a principal engineer asks; product-strategy, pricing,
domain-knowledge, org-design, and IP entries ask what a senior practitioner
of *that* discipline asks, and most of them escalate rather than recommend,
because the call belongs to a human authority the agent cannot stand in for.

Citations: REQ-G1.8, REQ-G1.4 · D-39, D-16 · inception REQ-I1.2 ·
inception D-17.

## Entry format

The prose entries below are the catalog's normative home. Their machine view
for overlay merging is [`config/decision-domains.yaml`](../config/decision-domains.yaml)
(the seed domains below, keyed by stable id), the core seed
[`scripts/resolve-catalog.sh`](../scripts/resolve-catalog.sh) unions with
adopter / team / machine-local overlays — see *Growth and adopter extension*.
The doc/yaml split mirrors [guard-catalog.md](guard-catalog.md) /
`config/guard-catalog.yaml`.

Every entry, seed or added later, carries exactly three fields:

- **Trigger.** What spec language or code change signals that the domain
  is being crossed. Triggers fire on the decision moment, not on the
  domain's vocabulary appearing in prose.
- **Considerations.** The checklist of questions a principal engineer asks
  before deciding in this domain. The checklist is what gets walked, and
  cited, when the trigger fires.
- **Disposition.** What the agent does once the considerations are walked,
  specializing the shared disposition rule below.

**The shared disposition rule.** When a trigger fires: if the spec or
kickoff brief already decides the question, proceed, citing the decision.
If it does not, research per [Research Rigor](research-rigor.md), then
recommend or escalate per stake — low-stake, reversible calls proceed as a
recommendation with the considerations recorded; load-bearing calls
escalate per the no-flattening rule. Domains overlapping the
hard-disqualifier zones of
[finding-categorization.md](finding-categorization.md) always escalate.
Per-entry dispositions below state which side of that line the domain
usually sits on, and why.

## Lifecycle wiring

The catalog is consulted at three points (REQ-G1.4, D-39):

- **`/spec-draft`, design phase.** Entries whose triggers match the
  feature being drafted are surfaced so the spec decides them instead of
  inheriting defaults silently.
- **`/spec-kickoff`, gap check.** Catalogued domains the spec touches but
  never decides are flagged into the kickoff brief's risk register, so the
  gap is a recorded risk rather than a surprise mid-execution.
- **`/execute-task`, drift triggers.** An implementation about to cross a
  catalogued domain the brief did not decide trips the trigger: halt or
  research per stake, per the shared disposition rule.

## Growth and adopter extension

The catalog is data, not code: an entry is added by writing it in the
format above, with no edits to the skills that consume it. Two growth
paths:

- **Through the drain loop.** Execution hitting a domain decision the
  catalog does not cover records an observation fragment through the shared
  helper (`scripts/obs-record.sh`; the fragment lands under
  `specs/_observations/entries/`). Recurring observations are the evidence
  a domain has earned an entry; the entry is added when the accumulator is
  mined.
- **By the adopter.** Projects with domains this seed list does not cover
  (payments, ML model lifecycle, firmware rollout) add their own entries in the
  same format through the overlay mechanism, leaving this shipped doc unedited.
  An adopter, team, or machine-local overlay places a
  `catalogs/decision-domains.yaml` (or, for the machine-local layer,
  `catalogs.local/decision-domains.yaml`) under its overlay root, and
  [`scripts/resolve-catalog.sh`](../scripts/resolve-catalog.sh) unions the
  layers onto the core seed by **append/union with supersede-by-id** — the same
  merge contract the [guard catalog](guard-catalog.md) uses (REQ-B1.3, D-5; the
  contract is documented there). The core seed list below is planwright's,
  authored in full prose here; adopters extend it without editing this doc.

## Seed catalog

### 1. Data storage & modeling

- **Trigger.** Introducing a persistent store; adding a table, collection,
  or schema; changing the shape, type, or meaning of stored data.
- **Considerations.** Access patterns before structure (what reads and
  writes this, how often, filtered by what); normalization versus
  duplication and who reconciles the duplicate; consistency needs;
  indexing for the actual queries; growth rate and retention; how the
  shape migrates when it changes, and what reads old rows mid-migration.
- **Disposition.** Additive changes the brief already decides proceed,
  citing it. New stores and shape changes to existing data escalate: the
  storage model outlives the feature that introduced it, and migrations
  sit in a hard-disqualifier zone.

### 2. Caching

- **Trigger.** Adding any cache: in-process memoization, HTTP cache
  headers, a CDN rule, a cache service layer; or setting a TTL.
- **Considerations.** Invalidation story (what writes make the entry
  stale, and what notices); the product's actual staleness tolerance; key
  design and collision/tenancy scope; cold-start and eviction behavior;
  stampede protection; memory bounds.
- **Disposition.** A cache the brief decides proceeds, citing it.
  Otherwise the staleness-tolerance question dominates: research and
  recommend when tolerance is documented or derivable; escalate when "how
  stale is acceptable" is a product call. A correctness bug shipped as a
  cache is still a correctness bug.

### 3. Queues & async work

- **Trigger.** Moving work out of the request path; introducing a job, a
  queue, a scheduled task, or a background worker.
- **Considerations.** Delivery semantics (at-least-once versus
  at-most-once, and which the handler actually assumes); handler
  idempotency under redelivery; ordering guarantees needed versus
  provided; retry policy and where dead letters go; visibility of silent
  failures; backpressure when producers outrun consumers.
- **Disposition.** Research the platform's actual delivery guarantees
  rather than assuming them. Proceed with a recommendation when the work
  is internal and idempotent; escalate when delivery semantics change
  user-visible outcomes (double-send, lost work) or when ordering is
  load-bearing.

### 4. API surface design

- **Trigger.** Adding or changing anything external callers depend on: a
  public endpoint, an exported signature, a CLI flag, an event or webhook
  schema, an error contract.
- **Considerations.** Versioning and backward compatibility; the error
  contract as part of the surface; naming and shape consistency with the
  existing surface; pagination, limits, and timeouts as contract;
  deprecation path for what this replaces; how much surface is actually
  needed (smallest contract that serves the caller).
- **Disposition.** Public surface is contract: changes to existing surface
  are at minimum sign-off class, and new public surface escalates as a
  design decision. Internal-only surface follows the idiom rung of the
  decision process.

### 5. Authentication & authorization

- **Trigger.** Anything touching login, sessions, tokens, credentials,
  permissions, roles, or tenancy boundaries.
- **Considerations.** Identity source (owned credentials versus delegated
  identity); session mechanics (lifetime, revocation, storage); where
  authorization is enforced and whether the model is roles, relationships,
  or attributes; tenancy isolation; secret and token handling; recovery
  flows, which are part of the auth surface and a classic bypass.
- **Disposition.** Always escalated, never auto-defaulted — this is the
  canonical no-flattening example (REQ-G1.3, D-16): "add auth" looks like
  a scaffolding checkbox, but the choices underneath are
  architecture-defining and often business differentiators. Auth is a
  hard-disqualifier zone; the agent's job is to frame the alternatives,
  not pick one.

### 6. Secrets & configuration

- **Trigger.** Introducing a secret or credential; adding a config option
  or environment variable; changing where configuration is read from.
- **Considerations.** Where the secret lives (never in committed artifacts
  — the data-hygiene rule of [security-posture.md](security-posture.md));
  rotation without a deploy; per-environment variance and safe defaults
  (the default an operator never reads must be the safe one); whether the
  option is documented where options are documented; blast radius on
  leak.
- **Disposition.** Secrets handling is a hard-disqualifier zone: escalate.
  Plain configuration additions proceed when they follow the project's
  config conventions and every added option is documented; an option that
  exists only in code is a finding, not a feature.

### 7. Concurrency

- **Trigger.** Introducing shared mutable state, parallel execution,
  locks, or a read-modify-write across any boundary (memory, file,
  database row, external API).
- **Considerations.** Where the race windows are; idempotency under
  retry; lock granularity and ordering (deadlock); contention on the hot
  path; crash mid-critical-section and who cleans up; whether the
  platform's memory or isolation model actually guarantees what the code
  assumes.
- **Disposition.** First preference is the design that removes the shared
  state (the composability default). Where concurrency is genuine,
  research the stack's idiomatic primitives rather than hand-rolling, and
  proceed with the considerations recorded. Escalate when correctness
  depends on ordering or isolation guarantees the platform does not
  document.

### 8. Observability

- **Trigger.** Adding a failure mode that can fail invisibly (a new
  external call, background path, or fallback); or adding logging,
  metrics, or tracing infrastructure.
- **Considerations.** What signal exists when this breaks, and who sees
  it; log level discipline and noise budget; metric cardinality cost;
  sensitive data in logs (the data-hygiene rule again); correlation
  across the async boundaries the change introduces.
- **Disposition.** Instrumenting along existing project conventions is
  mechanical: proceed. New observability infrastructure (a new telemetry
  stack, a new alerting channel) escalates — it is platform surface every
  later change inherits.

### 9. Deploy & migration strategy

- **Trigger.** A change that cannot be rolled out or rolled back
  atomically: a schema migration, a data backfill, a config flip with
  fleet-wide effect, a multi-service ordering dependency.
- **Considerations.** Rollback story, honestly assessed (a backfill is not
  rolled back by re-running it); compatibility in both directions while
  old and new code coexist; the irreversible step and what is verified
  before it; data-loss windows; whether a flag can decouple deploy from
  release.
- **Disposition.** Migrations and destructive operations are a
  hard-disqualifier zone: the rollout plan itself escalates, every time. The agent prepares
  the migration, states the ordering and rollback plan, and stops; a
  human directs the irreversible step.

### 10. Dependency adoption

- **Trigger.** Adding a library, service, or tool the project does not
  already use (the same moment Research Rigor's new-dependency trigger
  fires).
- **Considerations.** The dependency-adoption checklist in
  [engineering-decisions.md](engineering-decisions.md): supply chain,
  maintenance status, license, transitive weight — plus the prior
  question: does the standard library or an existing dependency already
  cover this well enough.
- **Disposition.** Stake-escalated per the checklist's own rule: dev-only
  tooling proceeds with the checklist recorded in the risk register;
  runtime dependencies, anything in a hard-disqualifier zone (auth,
  crypto, secrets), and anything parsing untrusted input escalate the
  adoption as a design decision.

### 11. Versioning scheme

- **Trigger.** Choosing or changing how a shipped artifact is versioned:
  cutting a project's first release, picking the tag or version-string
  format, or switching an already-released artifact's scheme.
- **Considerations.** The artifact type decides more than taste does. Is
  this a **compatibility-signaling** artifact — a library, a plugin, a
  public API — whose consumers (and any marketplace or dependency resolver)
  reason about breaking changes? Or a **continuously-shipped application**
  where "when did this ship" carries more information than "what broke"?
  Then: what does an existing version lineage already commit you to; what do
  the ecosystem's tooling and consumers expect to parse; how loud is a
  breaking change for the people downstream.
- **Disposition.** Artifact type is the heuristic: a compatibility-bearing
  artifact takes **SemVer** (`vX.Y.Z`, so a major bump *is* the
  break signal consumers key on); a continuously-shipped application takes
  **CalVer** (`YYYY.MINOR.PATCH`, where ship date is the salient axis); an
  internal-only artifact nobody else depends on may stay **unversioned**.
  Picking a scheme for a fresh artifact is a low-stake, reversible call that
  proceeds with the reasoning recorded; **switching** the scheme of an
  already-released artifact escalates — it breaks the lineage consumers and
  tooling have been reading. *Worked example (D-9):* planwright versions its
  plugin by SemVer precisely because a plugin is a compatibility-bearing
  artifact — the marketplace and adopters reason about breaking changes,
  which SemVer signals and CalVer does not — while the author's
  continuously-shipped application repo uses CalVer, the same heuristic
  landing on the opposite answer for the opposite artifact type.

### 12. Product strategy

- **Trigger.** Naming a segment, choosing the problem or wedge to enter on,
  setting a positioning claim, sequencing what ships first, or declaring the
  success metric the work is steered by.
- **Considerations.** Which segment feels this sharply enough to change
  behavior; what their alternative today (including doing nothing) already
  gives them; what would have to be true, stated falsifiably per
  [evidence-quality.md](evidence-quality.md); what is deliberately *not*
  being built; which metric moves if this is right, and which if it is
  wrong.
- **Disposition.** Escalate. The agent frames the options and their
  evidence; it does not pick the segment, the wedge, or the positioning —
  those are the venture's identity, not an implementation detail. A brief
  that already records the call is cited and proceeds.

### 13. Packaging & pricing

- **Trigger.** Introducing or changing how value is packaged and charged
  for: tiers, entitlements, quotas, seat-versus-usage metering, a free-tier
  or trial boundary, or the metric the price attaches to.
- **Considerations.** The value metric (what the customer consumes more of
  as they get more value) and whether the system can meter it honestly; the
  fence between tiers and what enforces it in code; the grade of the
  willingness-to-pay evidence ([evidence-quality.md](evidence-quality.md))
  versus a number someone liked; grandfathering; the entitlement checks the
  change silently creates downstream.
- **Disposition.** Always escalated: a published price is a contractual and
  reputational commitment close to a one-way door. The agent may model the
  options and name the metering required; the human sets the number and the
  fence.

### 14. Domain & knowledge engineering

- **Trigger.** Encoding domain knowledge durably: a taxonomy or ontology, a
  controlled vocabulary, an eligibility or rules engine, a canonical entity
  model, a glossary the code and the prose both key on.
- **Considerations.** Who the domain authority is, and whether they have
  seen the encoding; where ground truth lives and how the encoding drifts
  from it; the edges the experts themselves dispute; whether the model is
  descriptive (records what practitioners do) or prescriptive (tells them
  what to do), which changes who owns it; what happens to stored data when a
  term's meaning changes.
- **Disposition.** Escalate. A domain model outlives the feature that
  introduced it — the same reason data storage escalates — and downstream
  data is already written in its terms, so a mis-encoding is expensive to
  unwind. The agent drafts and names the ambiguities; a domain authority
  ratifies.

### 15. Organization design

- **Trigger.** Deciding who does the work and how it is divided: which team
  or role owns a surface, an on-call or escalation path, a cross-discipline
  handoff, a decision-rights assignment, or a process step that adds a
  required human.
- **Considerations.** Who is accountable versus consulted versus informed,
  named rather than implied; whether the org boundary matches the system
  boundary (a handoff cutting across a module buys coordination cost
  forever); what the arrangement costs the people who did not choose it;
  whether the added step is the smallest one that closes the gap.
- **Disposition.** Always escalated, never inferred: assigning work to
  people is human authority no technical justification overrides. The agent
  may surface a boundary's coordination cost and propose alternatives; it
  never assigns an owner, an on-call, or an approver.

### 16. IP posture

- **Trigger.** Affecting what is owned, disclosed, or licensed: choosing or
  changing an outbound license, publishing something previously private,
  ingesting third-party or model-generated content whose provenance matters,
  naming or branding an artifact.
- **Considerations.** Provenance of every input, and whether its license
  permits this use *and* this distribution; whether the outbound obligations
  compose with the inbound ones; what disclosure forecloses (publication can
  bar a patent; a public repo cannot be un-published); confidentiality
  obligations already in force; trademark collision.
- **Disposition.** Always escalated: a legal posture, not an engineering
  preference, and the agent is not a source of legal advice. It gathers the
  provenance facts and states the question precisely so a human — with
  counsel where the stake warrants — decides. High rot: re-verify licenses
  and platform terms against current text, never model memory
  ([research-rigor.md](research-rigor.md)).

### 17. LLM output quality & evaluation gates

- **Trigger.** Making model output load-bearing: adding a generation,
  extraction, classification, or judging step something downstream depends
  on; setting its acceptance bar; or changing a prompt, model, or retrieval
  path already sitting under one.
- **Considerations.** What "correct" means here, and whether it is checkable
  mechanically or only by a human read; the eval set — held-out, versioned,
  representative, not the examples the prompt was written against; the gate
  (a scored threshold, a qualified-response set, a criterion-by-criterion
  read), pre-committed rather than fitted after; non-determinism, and how
  many samples the number rests on; who re-runs it when the model version
  moves underneath.
- **Disposition.** A step behind an existing, passing gate proceeds.
  Introducing the gate, moving its threshold, or making model output
  load-bearing where it was not escalates: the acceptance bar is a product
  judgment about tolerable wrongness, not a tuning constant. A load-bearing
  LLM step with no eval set is a finding, not a feature.

### 18. Human comprehension & information UX

- **Trigger.** Rendering, presenting, or visualizing information for a human
  reader: a generated artifact someone reads (a PR body, a report, a
  rendered view, a status line, a walkthrough), or any new human-facing
  presentation surface.
- **Considerations.** Who reads this, with how much context, under what time
  pressure; what belongs above the fold versus behind progressive
  disclosure; whether the format serves the reader or the writer (a flat
  dump, hard-wrapped machine output, or an unsummarized log serves the
  writer); prior art from fields where a misread is expensive; the
  comprehension evidence behind the presentation rather than taste;
  accessibility.
- **Disposition.** Rendering along an existing convention proceeds. A novel
  human-read surface — and any surface where the presentation *is* the
  product — escalates, and researches first per
  [research-rigor.md](research-rigor.md): the research trigger fires here
  even when no code-shaped risk does. Reviewing the artifact itself selects
  lenses by artifact class ([artifact-lenses.md](artifact-lenses.md)).

### 19. Existing-seam reuse

- **Trigger.** Minting a new mechanism — a config path, a state store, an
  extension point, a dispatch path, a notification channel, a deferral
  list — for something a core seam already covers.
- **Considerations.** Which core seam is nearest: the **four-layer overlay**
  behind config, doctrine, and catalog resolution; the **config-knob seam**
  (`config/defaults.yml` plus the knob's options-reference row); the
  **catalog seam** (this catalog and the guard catalog); the **rule-doc
  seam** (law resolved by basename); the **execution-backend seam**; the
  **attention / notification seam**; the **accumulator seam** (observation
  fragments and `GATE(when:)` deferrals); and the **machine-local state
  home** (`CLAUDE_PLUGIN_DATA`). Each has its own doc in
  [README.md](README.md). Then: what does that seam not do; is that a
  missing capability *in* it (extend) or a different concern (mint, and say
  why); what does a parallel mechanism cost every later change that now has
  two places to look.
- **Disposition.** Reuse is the default; extending a seam proceeds. Minting
  is the exception, and proceeds only with a recorded note naming the
  nearest seam and why it does not fit — in the spec's design decision, or
  in the kickoff brief's risk register when it surfaces mid-execution.
  Minting a parallel seam without that record is a finding.
