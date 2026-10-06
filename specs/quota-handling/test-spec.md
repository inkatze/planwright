# Quota handling — Test Spec

**Status:** Ready
**Last reviewed:** 2026-10-05
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` where automation is honest, which is nearly
everything. Script logic (the catalog resolver and validator, the
classifier, the hold store and ledger, the completion readers, the frame
reader, and the review-request command against a stubbed GitHub client)
runs under `scripts/run-tests.sh` through `mise run check` and the
repository CI. Runner behaviour (the on-limit postures, holding a unit,
the resume skip, the head-moved signal, and the end-to-end order) belongs
to the session hosting the unit, not to a script, so its `[test]` entries
run as fixture overlays on the terminal rung, recorded in the PR body, as
custom-steps verified its runner. `[Gherkin]` marks the scenarios those
fixtures must produce. `[manual]`
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

Scenario, per reader (stream-json result frame, stream-json exit
fallback, headless result): given a fixture worker whose event stream
(or, headless, whose `result.json` with `is_error` set) ends with a 529
error and exit zero, the status and the stuck detector both report a
failure naming the cause; given one ending with a rate-limit error, both
report `limited` against `claude` and the throttle is engaged. No fixture
yields a clean completion.

### REQ-A1.5 — The limited record's fields [test]

A `limited` record carries the vendor id, the recognizer id, an excerpt
screened by `scripts/step-record.sh`'s canonical sanitizer, secret screen,
and excerpt bound, and the reset time when the adapter's locator finds one
in an accepted form; it omits the reset time when the locator finds none,
or finds an unparseable, past, or beyond-ceiling value.

## REQ-B — Holding and resuming

### REQ-B1.1 — Hold records the unit and pushes [test + Gherkin]

Scenario: given a unit whose post-pr bot step is classified `limited` with
posture `hold`, then the hold store records the unit with the vendor, the
step, the reason, and the reset time; selection does not dispatch it; the
status render shows it held; `tasks.md` is unchanged; and the attention
store holds an event naming the vendor, the reason, the reset time, and
the resume command. A release leaves the branch's commit list unchanged.

### REQ-B1.2 — The on-limit postures [test]

Fixtures cover `continue` recording `limited` and running the next step,
`alternate` running the named step once with its outcome standing, and
resolution refusing an alternate bound to the same vendor, an alternate
declaring its own alternate, and a missing alternate id; an alternate
classified `limited` takes `hold`; a post-pr step recorded `limited` with
posture `continue` refuses the later flip on that head.

### REQ-B1.3 — Vendor-wide hold [test + Gherkin]

Scenario: given vendor V held by unit 1, when unit 2 reaches a step bound
to V, then unit 2 takes its posture with outcome `limited`, and the
stubbed client records no request from unit 2.

### REQ-B1.4 — Evidence-only automatic resume [test + Gherkin]

Scenarios: a `claude` hold whose stated reset time has passed, with no
reading received after the hold began, stays held after the sweep; a hold
whose only post-hold reading covers the weekly window stays held; the same
hold with post-hold readings for every governed window below their
lowest-rung descend thresholds is released; a hold on a `none`-evidence
vendor is never released by the sweep.

### REQ-B1.5 — Operator resume [test + design-level]

The resume verb releases a held vendor in stages: the longest-held unit
first, the others once its first vendor request ends other than
`limited`, none of them after a renewed refusal;
`docs/quota.md` documents the command.

### REQ-B1.6 — Resume continues the point [test + Gherkin]

Scenario: given a run recording steps 1 and 2 `passed` with recorded head
H (the head after each step) and step 3 held, when resumed on head H, then
steps 1 and 2 are recorded `skipped` and step 3 runs; when resumed after
the head moved, every step runs.

### REQ-B1.7 — No retry [test]

A refusal renewed on resume renews the hold, and the stubbed client
records exactly one request per resume however many units were held;
nothing re-requests without a resume.

## REQ-C — Vendor adapters

### REQ-C1.1 — Adapter fields [test]

The validator accepts a complete entry and rejects each missing or
malformed field (id, recognizers, evidence kind, controls, bot login) with
a named reason, including a comment body mentioning a handle other than
the bot login or carrying an issue or URL reference, an oversized body,
and a CLI argument outside the plain-word grammar.

### REQ-C1.2 — No common vocabulary [test + design-level]

A step naming `<vendor>:<control>` resolves to that vendor's declared
invocation; a control name declared only by another vendor does not
resolve. D-10 records that core defines no shared control names.

### REQ-C1.3 — History-keyed control choice [test]

With a choice rule of first-review then follow-up controls, an empty
ledger for the PR selects the first, a ledger holding only a refused or
unanswered request selects the first, and a ledger with an answered request
selects the second.

### REQ-C1.4 — Unknown vendor or control is a non-resolving step [test]

A step bound to an undeclared vendor, or an undeclared control of a known
vendor, is a non-resolving step: the resolver prints custom-steps'
missing-step matrix token for its layer and attendance (`ask` attended;
`park` unattended from the repo-tracked layer; `skip` unattended from the
adopter or machine-local layer).

### REQ-C1.5 — Adapters are inert data [test]

Recognizers carrying regular-expression metacharacters, shell
metacharacters, and command substitutions match only as literal text and
cause no execution; a CLI argument carrying a shell operator or an option
injection is refused by the validator; hostile vendor ids are refused
before any path use.

### REQ-C1.6 — Core ships Claude only [test + design-level]

The resolved core layer holds exactly one vendor, `claude`; the examples
in `docs/quota.md` name only invented placeholder vendors.

## REQ-D — The head-moved signal

### REQ-D1.1 — Signal after a head move [test + Gherkin]

Scenario: given a post-pr list whose first step pushes, the second step's
context carries the previous and new heads, and the first step's record
carries both; with no push, neither appears.

### REQ-D1.2 — Requested head recorded [test]

After a review request, the vendor's ledger holds a request line with the
PR and the head asked about.

### REQ-D1.3 — Same-head skip [test]

A second request for the same PR and head after an answered one sends
nothing and records `skipped` naming the head; after a refused request, or
one that timed out without a reply, a request on the same head is sent.

### REQ-D1.4 — Final-head ordering [test]

Resolution refuses a list placing a `final-head` step before a
`moves-head` step, naming both, and accepts the reverse order; it accepts
a `moves-head` step after a `final-head` step when its `drains` names that
step, and refuses a `drains` naming a missing or non-final-head step.

### REQ-D1.5 — Bots only [test]

With the stubbed client reporting the declared login as a user account,
the command refuses and posts nothing; with a bot account it posts. A
human comment carrying refusal text, and a bot comment older than the
request, are ignored: no answer, refusal, or hold is written for them.

## REQ-E — Usage accounting

### REQ-E1.1 — The ledger and its retention [test]

Requests, answers, refusals, holds, and resumes each append a line with
its time and, where the event has them, its PR and head; pruning removes
lines older than the retention knob (90 days when unset) and keeps the
rest byte for byte; a line failing the field grammar is skipped on read;
a check confirms the fleet home is outside the repository's tracked
tree.

### REQ-E1.2 — Vendor view on the fleet status surface [test]

`scripts/fleet-stats.sh render` shows, per vendor, hold state with its
reason and counts over the retention period, from a fixture ledger.

### REQ-E1.3 — The frame reader and staleness rule [test + Gherkin]

Scenarios: a dead worker's window reading with a passed reset time is
ignored; of two live frames, the reading with the furthest-future reset is
used for each window independently; clearance is reported only when every
governed window has a post-hold reading below its lowest-rung descend
threshold, and refused when the session window is low but the weekly is
not; the usage gate's cached signal is unchanged by any frame.

### REQ-E1.4 — Account-wide, never attributed [test]

`scripts/fleet-stats.sh render`, the `claude-frames` evidence output, and
the hold's attention push each carry the account-wide label, and none
attributes utilization to the fleet's own workers.

### REQ-E1.5 — Unmeasured backends [test]

A fleet whose live workers all run on a frameless backend, and a fleet
with no live frame, both report unmeasured, never headroom.

### REQ-E1.6 — The throttle engages on a Claude limit [test]

A rate-limit death with a stated reset time engages the throttle through
`engage --until`, and the throttle's state carries that time; one with no
stated reset time engages it through `observe` with its degraded default.

## REQ-F — Acceptance

### REQ-F1.1 — The order is expressible [test]

The overlay example in `docs/quota.md` resolves with
`scripts/resolve-steps.sh` using shipped scripts and catalog entries plus
overlay entries naming the panel and drain commands (stubbed on PATH, so
the missing-step rule does not fire), printing the order
with provenance; the bot review step resolves to the shipped
review-request command, declared `final-head`, with the drain declared
`moves-head` and draining it.

### REQ-F1.2 — A clean hold on bot quota [test + manual]

End-to-end fixture: the acceptance order runs against a stubbed bot that
replies to its first request with a quota refusal; the run holds at the
bot step with no `failed` outcome and no second request before the
resume, the PR stays a draft, the flip point is not reached, an attention
event carries the reason, and an operator resume re-sends the full-review
request on the same head and completes the order. Manual: a quota cannot
be exhausted on demand, so once the operator has enabled a bot adapter in
their overlay, the first real quota refusal met after Task 10 lands is
checked against the same outcomes by the operator and recorded as an
observation in shape only (no account, plan, or billing detail, the
excerpt passed through the secret screen).
