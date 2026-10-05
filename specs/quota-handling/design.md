# Quota handling — Design

**Status:** Draft
**Last reviewed:** 2026-10-05
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` new in this bundle; `C, <namespace> <id>` carried from
another bundle's decision.

## Decision log

### D-1: Altitude — mechanism-primary, no new doctrine  (N)

**Decision:** The rules this bundle states (hold by default, resume only on
evidence, never retry into a refusal, no spend control for a non-Claude
vendor) live in this bundle's requirements and decisions and are enforced
by deterministic scripts: the classifier, the hold store, the step runner,
and the review-request command. The adapter contract is documented in a
reference document under `docs/`, and `doctrine/custom-steps.md` gains
only a pointer line where it lists outcomes. Vendor-specific values
(recognizer strings, bot logins, control invocations) live in overlays.

**Alternatives considered:**
- A new doctrine document stating an external-limits posture. Rejected
  because: every rule here is mechanically checkable, and autopilot-reflex
  step 5 prefers a mechanical tool to an instruction an LLM follows; a
  doctrine document would add instruction-budget load to every skill that
  cites it.
- A quota section in `doctrine/custom-steps.md`. Rejected because: that
  document is in the protected, budget-checked set, and Claude's
  worker-death handling is not a steps concern.
- Deferring the call to kickoff. Rejected because: an altitude trigger
  fired mid-flow (the requirements acquired doctrine-shaped rules), and
  the autopilot-reflex doctrine requires resolving it before design.

**Chosen because:** The trigger was a mechanism acquiring rules that read
like doctrine; the resolution is that the rules are mechanism-enforced
invariants of this capability, not a way of thinking a skill must follow.

### D-2: A new bundle consuming three owners as contracts  (N)

**Decision:** Spin `quota-handling` as its own bundle. custom-steps,
fleet-autonomy, and model-allocation are consumed as contracts; the one
change to a signed contract (D-3) travels as a custom-steps amendment
through that bundle's own ritual.

**Alternatives considered:**
- Extend custom-steps. Rejected because: custom-steps excludes wrappers
  for external review tools and owns no usage accounting or worker-death
  classification; folding the vendor adapter in would push it past one
  feature a reader holds in their head.
- Extend fleet-autonomy. Rejected because: it is Done and Claude-only by
  construction, and step outcomes are not its domain.

**Chosen because:** The per-vendor adapter is a new external interface
whose decisions are orthogonal to each owner's domain, which is a spin-new
trigger under the fold-detection rule.

### D-3: `limited` is a sixth step outcome, via a custom-steps amendment  (N)

**Decision:** Add `limited` to the step outcome set by amending
custom-steps: supersede its REQ-D1.1 to widen the set, and add the step
catalog fields this bundle needs (`vendor`, `control`, `on-limit`,
`moves-head`, `final-head`) plus the resume-continuation rule of D-8. The
amendment is drafted with `/spec-draft --extend custom-steps` and signed
in a delta kickoff. This bundle's tasks that write the new outcome or read
the new fields wait on it landing.

**Alternatives considered:**
- Record a limit as `halted` with a cause token. Rejected because:
  custom-steps REQ-D1.2 binds `halted` to the on-failure posture, which
  ends the point, so on-limit and on-failure would both key on `halted`
  and every reader would have to inspect the cause to tell a hold from a
  stop.
- Supersede custom-steps REQ-D1.1 from this bundle directly. Rejected
  because: custom-steps would then cite a supersession it never signed,
  and its kickoff brief would go stale silently.

**Chosen because:** It keeps every signed contract signed by its owner,
and a distinct outcome lets the record table, the PR-body fold, and the
flip-point status treat a hold as neither success nor failure.

### D-4: Fixed-string recognizers; unknown stays as classified  (N)

**Decision:** A vendor-bound step's captured output (a command step's
stdout and stderr, a skill or prompt step's handoff excerpt, the
review-request command's printed bot reply, a worker's event stream) is
matched against the adapter's recognizers as fixed, case-sensitive
substrings by a core classifier script. A match yields `limited` with the
matching recognizer's id, a screened excerpt, and a reset time when the
adapter declares where one appears; no match leaves the custom-steps
classification untouched.

**Alternatives considered:**
- Anchored regular expressions. Rejected because: a pattern from overlay
  data carries backtracking and injection risk that security-posture
  rules out for parsed input.
- Classifying by model judgment. Rejected because: fleet-autonomy D-18
  forbids an LLM in routine control-plane decisions, and a judged hold
  cannot be reproduced.

**Chosen because:** Fixed strings are the least expressive form that
covers every refusal observed so far, and they fail toward the existing
behavior (a visible failure) rather than toward a silent hold.

### D-5: Hold by default, with a declarable on-limit posture  (N)

**Decision:** A step's `on-limit` field takes `hold` (default),
`continue`, or `alternate <step-id>`. `hold` parks the unit (D-7).
`continue` records `limited` and runs the rest of the point; at a flip
point a `limited` record refuses the flip whatever its posture, as a
`halted` one does. `alternate` runs the named step once in the held
step's place; resolution refuses an alternate bound to the same vendor,
an alternate that itself declares `alternate`, and a missing id.

**Alternatives considered:**
- Hold only, fixed. Rejected because: a monthly quota would stall a unit
  for a month unless the operator intervened by hand.
- Hold the step and run the rest of the point. Rejected because: later
  steps would run on a head the held step never reviewed, breaking the
  declared order.

**Chosen because:** The operator chose a declarable posture with hold as
the default; the flip-point rule keeps `continue` from becoming a path to
ready-flipping past an unreviewed head.

### D-6: A host-wide vendor hold store  (N)

**Decision:** Holds live in the fleet home under one directory per vendor,
written under the existing lock library, and every vendor-bound step
checks it before sending a request. A step that finds its vendor held
takes its posture with outcome `limited` and the hold's recorded reason,
sending nothing. The store is per host; a second host learns of a limit
by meeting it.

**Alternatives considered:**
- Per-unit holds. Rejected because: every other unit would spend one
  request, metered or refused, to learn what the host already knows.
- A cross-host store. Rejected because: the fleet home is the host's
  durable state, and no cross-host state channel exists to build on.

**Chosen because:** It makes "no further requests to a held vendor" a
property of the host rather than of each run, reusing the fleet home and
lock library already trusted for fleet state.

### D-7: Evidence-only automatic resume, operator resume, push surfacing  (N)

**Decision:** A hold records its vendor, reason, stated reset time,
holding units, and the time it began, and pushes an attention event
through the existing attention store. Automatic resume is attempted only
by a sweep the attention watcher's reconcile pass already runs: for each
held vendor it asks the vendor's evidence kind whether the limit cleared,
and releases on a positive answer. Evidence kinds are a closed core set
(D-9). The operator's resume command releases a vendor unconditionally.
Release unparks every unit held on the vendor and re-dispatches it through
the normal selection path.

**Alternatives considered:**
- Resume when the stated reset time passes. Rejected because: the clock
  passing says nothing about the new window, and resuming on it alone
  dispatched blind in the incident obs:c24a01af records.
- A dedicated resume daemon. Rejected because: the attention watcher
  already runs a periodic reconcile, and a second daemon adds a liveness
  surface to watch.

**Chosen because:** The operator chose evidence-only resume; reusing the
attention store and watcher keeps surfacing push-based, never a status
command the operator must remember to poll.

### D-8: Resume continues the point from the held step  (N)

**Decision:** A resumed unit starts a new run, as custom-steps defines.
The runner reads the interrupted run's records and skips a step recorded
`passed` or `applied` on the same head, starting real work at the held
step. If the head moved while the unit was held, nothing is skipped.

**Alternatives considered:**
- Restart the held step's whole point. Rejected because: it re-spends the
  earlier steps' cost (polish, an external-model panel) for no new
  information.

**Chosen because:** Same-head records are exactly the evidence that a
step's work still holds; a moved head invalidates that evidence, so the
rule degrades to a full re-run where it must. Skipping is part of the
custom-steps amendment (D-3) because it changes "the chain that runs is
the chain declared".

### D-9: Adapters are a data catalog with a closed set of evidence kinds  (N)

**Decision:** A `vendors` catalog, merged by `scripts/resolve-catalog.sh`
across the overlay layers as the steps catalog is. Each entry declares:
`id`; `recognizers` (a list of fixed strings, each with an id, plus an
optional reset-time locator naming a fixed prefix after which a timestamp
appears); `evidence` (one of the core kinds); `bot-login` (for a
PR-comment vendor); and `controls` (each a name in the vendor's
vocabulary mapped to its invocation: a comment body for a PR-comment
vendor, an argument list for a CLI vendor). Core implements the evidence
kinds `claude-frames` (D-14) and `none`; adding a kind is a core change.
Core ships the `claude` entry; example entries for the review bot and the
external CLI observed so far are documented in the reference document,
never active by default. Malformed entries follow the catalog's by-layer
policy.

**Alternatives considered:**
- Executables on PATH that answer adapter verbs, mirroring the backend
  seam. Rejected because: overlay-supplied code would run on every
  classification, contradicting REQ-C1.5.
- A data catalog plus an operator-declared probe command as an evidence
  kind. Rejected because: it widens the trusted surface to an overlay
  command; it remains available later as a new core evidence kind with
  its own review.

**Chosen because:** The steps catalog already proves this merge path, and
data-only adapters keep every vendor's contribution inspectable and inert.

### D-10: Controls in vendor vocabulary, with a history-keyed choice  (N)

**Decision:** A step names a control as `<vendor>:<control>`, or names a
choice rule the adapter declares. A choice rule is an ordered list of
`(condition, control)` pairs over a closed condition set the ledger can
answer for the current PR (`no-prior-request`, `prior-request`); the first
matching pair wins. Core never translates between vendors' controls.

**Alternatives considered:**
- A common vocabulary (`full`, `incremental`, `effort:<n>`) that adapters
  map onto. Rejected because: the operator directed that vendors' options
  do not map one to one and the spec must not assume they do.

**Chosen because:** The closed condition set is the least needed to
express "full first, incremental after", and every other choice stays in
the vendor's own terms.

### D-11: One vendor-agnostic review-request command  (N)

**Decision:** Core ships a command step script that, given a vendor and a
control or choice rule, checks the hold store, checks the ledger for a
request already made on the current head (skipping when found), confirms
the adapter's `bot-login` is a bot account on GitHub, posts the control's
comment body to the PR from a file (never interpolated into a command
line), records the request with its head, then waits within the step's
timeout for the bot's next comment and prints it screened for the
classifier. No reply before the timeout is `failed`, per the custom-steps
timeout rule. Posting to an automated reviewer is outside the
messages-to-people confirmation the operator's conventions require.

**Alternatives considered:**
- The operator's own command or skill surfaces the reply. Rejected
  because: REQ-F1.1 then rests on unshipped operator code.
- A new `bot` step kind. Rejected because: it widens the custom-steps
  kind set, a second cross-bundle amendment, for behavior a command step
  already hosts.

**Chosen because:** Every vendor-specific string stays in the overlay
adapter, so the command is a capability rather than a vendor wrapper, and
the bot-account check makes it structurally unable to message a person.

### D-12: Head-moved signal and final-head ordering  (N)

**Decision:** After each post-pr step, the runner compares the PR head to
the head before the step; on a change it records both SHAs in the step
record and adds them to the fixed step context of every later step at
that point. Steps gain `moves-head: true` (the step may push) and
`final-head: true` (the step runs only after every head-moving step at its
point); resolution refuses a list placing a `final-head` step before a
`moves-head` step. Both fields travel in the custom-steps amendment (D-3).

**Alternatives considered:**
- Ordering by documentation only. Rejected because: a misplaced bot step
  would silently review a stale head and spend quota on it.
- Carrying the signal across runs. Rejected because: the ledger's
  per-PR request history already answers what the next run needs (D-10).

**Chosen because:** A declared, checkable ordering is cheaper than
discovering a stale-head review after the quota is spent.

### D-13: A machine-local per-vendor ledger  (N)

**Decision:** One append-only line-oriented file per vendor under the
fleet home records requests, refusals, holds, and resumes with time, PR,
head, and recognizer id; never committed. A retention knob prunes lines
older than its value. The status surface gains a vendor view rendering
hold state, its reason, and counts over a window.

**Alternatives considered:**
- Committing usage records. Rejected because: they are host- and
  account-specific operational detail, which artifact data-hygiene keeps
  out of committed artifacts.

**Chosen because:** The fleet home is already the durable machine-local
home of fleet state, and line files keep the ledger readable by the
portable shell tooling the repository is built from.

### D-14: The Claude usage producer from worker rate-limit frames  (N)

**Decision:** The stream-json supervisor persists each worker's newest
rate-limit frame in the fleet home beside the worker's other runtime
state. The `claude-frames` evidence kind, and the usage gate's capture
path, read across those files: ignore every frame whose reset time has
passed, take the frame with the furthest-future reset, and report
headroom recovered only when its utilization is below the gate's lowest
restriction rung for that window (an existing knob, so no new threshold).
The reading is labelled account-wide wherever it is rendered. A backend
emitting no frames, and a fleet with no live frame, report unmeasured.

**Alternatives considered:**
- Scraping the interactive usage view. Rejected because: driving a TUI is
  forbidden to the tower, and obs:7e67fe74 found no producer for it.
- Deriving a percentage from transcript token counts. Rejected because:
  the window's denominator is unpublished, so every threshold would need
  re-deriving.

**Chosen because:** The frames already carry the exact percentage and
reset time the gate wants; the staleness rule is the one verified on
2026-09-02 (obs:c24a01af).

### D-15: Worker-death classification on every rung, and the throttle  (N)

**Decision:** Every completion reader (the stream-json status, its exit
fallback, the headless rung's result file, and the stuck detector) reads
the error signal and the event-stream error text, never only an exit code
or a result subtype. A rate-limit error classifies the death `limited`
against the `claude` vendor, records a hold, and engages fleet-autonomy's
throttle with the stated reset time through its existing verb; any other
API error is a failure naming its cause.

**Alternatives considered:**
- Classifying only on the stream-json rung. Rejected because: the same
  false clean completion recurs one rung over (obs:f0b55c65,
  obs:d9681390).

**Chosen because:** A worker's death is the Claude vendor's step-level
refusal, so it takes the same classification and hold as any other, and
the throttle's existing `observe` verb finally gets a caller.

### D-16: The boundary — no retry, no spend, prediction deferred  (N)

**Decision:** Never retry into a limit refusal; never offer a spend,
upgrade, or overage control for a non-Claude vendor; defer forecasting a
non-Claude quota until a vendor offers a supported readout.

**Alternatives considered:**
- Bounded retry with backoff. Rejected because: each retry against a
  metered bot spends or wastes a request, the cost the seed names.
- Quota forecasting now. Rejected because: no observed vendor offers a
  supported readout, so there is nothing to build on.

**Chosen because:** The operator adopted this boundary; the spend floor
mirrors fleet-autonomy REQ-E1.11's decline-by-default posture.

## Cross-cutting concerns

- **Security.** Adapter fields, bot replies, and event-stream text are
  untrusted: matched as fixed strings, printed with `printf` after the
  canonical sanitizer, and never interpolated into a command. The comment
  body is posted from a file. Vendor and step ids are validated against
  their grammar before any path use.
- **Concurrency.** The hold store and ledger are written under the lock
  library, since several units on a host can meet the same limit at once.
- **Research.** No new dependency is adopted. The Claude frame shape and
  the staleness rule come from recorded observations (obs:c24a01af); the
  review bot's refusal text and its full and incremental commands come
  from the operator's invocation and stay in overlay examples, where a
  vendor's wording change is the operator's edit.
