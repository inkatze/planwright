# Quota handling — Test Spec

**Status:** Draft
**Last reviewed:** 2026-10-05
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` where automation is honest, which is nearly
everything, since every rule here is script logic: the catalog resolver and
validator, the classifier, the hold store and ledger, the runner's posture
and resume behavior, the completion readers, the frame reader, and the
review-request command against a stubbed GitHub client. All run under
`scripts/run-tests.sh` through `mise run check` and the repository CI.
`[Gherkin]` marks the scenarios those fixtures must produce. `[manual]`
covers checking the first real quota refusal against the acceptance
outcomes, which no stub can prove. `[design-level]` marks the rules whose presence in the
named document or decision is the verification.

## REQ-A — Classifying a refusal

### REQ-A1.1 — A limit refusal is `limited` [test + Gherkin]

Scenario: given a vendor adapter declaring a recognizer, when a command
step, a skill step's handoff, and a review-request reply each contain the
recognized text, then each step's record carries outcome `limited`, never
`failed` or `passed`.

### REQ-A1.2 — Deterministic classification [test]

The classifier is run twice on identical input and its output compared
byte for byte; a grep guard confirms it invokes no model or agent command.

### REQ-A1.3 — Unknown refusals keep their outcome [test]

A refusal text no recognizer matches leaves a command step `failed` on a
non-zero exit and a skill step at its handoff-derived outcome; no hold is
written.

### REQ-A1.4 — No clean completion after an API error [test + Gherkin]

Scenario, per rung (stream-json result frame, stream-json exit fallback,
headless): given a fixture worker whose event stream ends with a 529
error and exit zero, the status and the stuck detector both report a
failure naming the cause; given one ending with a rate-limit error, both
report `limited` against `claude`. No fixture yields a clean completion.

### REQ-A1.5 — The limited record's fields [test]

A `limited` record carries the vendor id, the recognizer id, an excerpt
with non-printable bytes stripped, and the reset time when the adapter's
locator finds one, and omits the reset time when it does not.

## REQ-B — Holding and resuming

### REQ-B1.1 — Hold parks the unit and pushes [test + Gherkin]

Scenario: given a unit whose post-pr bot step is classified `limited` with
posture `hold`, then the unit's Awaiting-input entry names the vendor, the
step, the reason, and the reset time, and the attention store holds an
event for it.

### REQ-B1.2 — The on-limit postures [test]

Fixtures cover `continue` recording `limited` and running the next step,
`alternate` running the named step once with its outcome standing, and
resolution refusing an alternate bound to the same vendor, an alternate
declaring its own alternate, and a missing alternate id; a `limited` step
with posture `continue` at a flip point still refuses the flip.

### REQ-B1.3 — Vendor-wide hold [test + Gherkin]

Scenario: given vendor V held by unit 1, when unit 2 reaches a step bound
to V, then unit 2 takes its posture with outcome `limited`, and the
stubbed client records no request from unit 2.

### REQ-B1.4 — Evidence-only automatic resume [test + Gherkin]

Scenarios: a `claude` hold whose stated reset time has passed and with no
fresh frame stays held after the sweep; the same hold with a fresh frame
below the lowest rung is released; a hold on a `none`-evidence vendor is
never released by the sweep.

### REQ-B1.5 — Operator resume [test + design-level]

The resume verb releases a held vendor and unparks every unit held on it;
`docs/quota.md` documents the command.

### REQ-B1.6 — Resume continues the point [test + Gherkin]

Scenario: given a run recording steps 1 and 2 `passed` on head H and step 3
held, when resumed on head H, then steps 1 and 2 are skipped and step 3
runs; when resumed after the head moved, every step runs.

### REQ-B1.7 — No retry [test]

A refusal renewed on resume renews the hold, and the stubbed client
records exactly one request per resume; nothing re-requests without a
resume.

## REQ-C — Vendor adapters

### REQ-C1.1 — Adapter fields [test]

The validator accepts a complete entry and rejects each missing or
malformed field (id, recognizers, evidence kind, controls) with a named
reason.

### REQ-C1.2 — No common vocabulary [test + design-level]

A step naming `<vendor>:<control>` resolves to that vendor's declared
invocation; a control name declared only by another vendor does not
resolve. D-10 records that core defines no shared control names.

### REQ-C1.3 — History-keyed control choice [test]

With a choice rule of first-review then follow-up controls, an empty
ledger for the PR selects the first and a ledger with a prior request
selects the second.

### REQ-C1.4 — Unknown vendor or control fails resolution [test]

A step bound to an undeclared vendor, or an undeclared control of a known
vendor, follows the custom-steps missing-step rule at resolution, before
any step runs.

### REQ-C1.5 — Adapters are inert data [test]

Recognizers carrying regular-expression metacharacters, shell
metacharacters, and command substitutions match only as literal text and
cause no execution; hostile vendor ids are refused before any path use.

### REQ-C1.6 — Core ships Claude only [test + design-level]

The resolved core layer holds exactly one active vendor entry, `claude`;
the third-party examples appear in `docs/quota.md` only.

## REQ-D — The head-moved signal

### REQ-D1.1 — Signal after a head move [test + Gherkin]

Scenario: given a post-pr list whose first step pushes, the second step's
context carries the previous and new heads, and the first step's record
carries both; with no push, neither appears.

### REQ-D1.2 — Requested head recorded [test]

After a review request, the vendor's ledger holds a request line with the
PR and the head asked about.

### REQ-D1.3 — Same-head skip [test]

A second request for the same PR and head sends nothing and records
`skipped` naming the head.

### REQ-D1.4 — Final-head ordering [test]

Resolution refuses a list placing a `final-head` step before a
`moves-head` step, naming both, and accepts the reverse order.

### REQ-D1.5 — Bots only [test]

With the stubbed client reporting the declared login as a user account,
the command refuses and posts nothing; with a bot account it posts.

## REQ-E — Usage accounting

### REQ-E1.1 — The ledger and its retention [test]

Requests, refusals, holds, and resumes each append a line with time, PR,
and head; pruning removes lines older than the retention knob and keeps
the rest byte for byte; a check confirms the fleet home is outside the
repository's tracked tree.

### REQ-E1.2 — Vendor view on the status surface [test]

The status surface renders, per vendor, hold state with its reason and
counts over a window, from a fixture ledger.

### REQ-E1.3 — The frame producer and staleness rule [test + Gherkin]

Scenarios: a dead worker's frame with a passed reset time is ignored; of
two live frames, the one with the furthest-future reset is used; recovery
is reported only below the lowest restriction rung; the gate's proactive
path reads the persisted frames.

### REQ-E1.4 — Account-wide, never attributed [test]

Every rendering of the Claude signal carries the account-wide label, and
no output attributes utilization to the fleet's own workers.

### REQ-E1.5 — Unmeasured backends [test]

A fleet whose live workers all run on a frameless backend, and a fleet
with no live frame, both report unmeasured, never headroom.

### REQ-E1.6 — The throttle engages on a Claude limit [test]

A rate-limit death engages the throttle through its existing verb, and the
throttle's state carries the stated reset time.

## REQ-F — Acceptance

### REQ-F1.1 — The order is expressible [test]

The overlay example in `docs/quota.md` resolves with
`scripts/resolve-steps.sh` using only shipped scripts and catalog entries,
printing the order with provenance.

### REQ-F1.2 — A clean hold on bot quota [test + manual]

End-to-end fixture: the acceptance order runs against a stubbed bot that
answers its first request with a quota refusal; the run holds at the bot
step with no `failed` outcome and no second request, the PR stays a
draft, the flip point is not reached, an attention event carries the
reason, and an operator resume completes the order. Manual: a quota can
not be exhausted on demand, so the first real quota refusal met after
Task 10 lands is checked against the same outcomes by the operator and
recorded as an observation.
