# Decision-Domains Catalog

The model already holds most staff-engineering knowledge latently; the
failure mode is not ignorance but failing to stop and apply it at the
moment a decision is being made. This catalog turns that judgment into
triggers: an extensible, data-driven list of stake-bearing decision
domains, each entry naming what signals the domain, the questions a
principal engineer asks before deciding, and what the agent does with the
answer. It is the trigger list behind the no-flattening rule in
[engineering-decisions.md](engineering-decisions.md).

Citations: REQ-G1.8, REQ-G1.4 · D-39, D-16.

## Entry format

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
  catalog does not cover writes an observation to the observations log
  (`specs/_observations/opportunities.md`). Recurring observations are the
  evidence a domain has earned an entry; the entry is added when the log
  is mined.
- **By the adopter.** Projects with domains this seed list does not cover
  (payments, ML model lifecycle, firmware rollout) add their own entries
  in the same format through project configuration, per the config model
  and options reference; the core seed list below is planwright's, and
  adopters extend it without editing this doc.

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
