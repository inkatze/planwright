# Fleet Messaging — Test Spec

**Status:** Draft
**Last reviewed:** 2026-09-02
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: script-level behavior (probe parsing, grammar validation,
mode resolution, ordering, doorbell framing and post outcomes against a
test-bound socket speaking the pinned protocol) is `[test]` and runs in the
repo's shell suite in CI. Live two-session flows (real message delivery,
held/refused outcomes, idle notices) are `[manual]`, optionally exercised
by a local behavioral eval that never runs in CI (the evals-never-in-CI
guard). Doctrine and contract deliverables are `[design-level]`.

## REQ-A — Availability & advertisement

### REQ-A1.1 — deterministic availability probe [test]

`fleet-messaging.sh probe` fixture tests: the invoking session's socket env
present + version at or above the pin of record reads available; env
absent, version below the pin, or malformed input reads absent; no
configuration value can force available without the probe.

### REQ-A1.6 — eligibility derived from session-grade, fail-safe [test + design-level]

Contract-doc review that the derivation names the session-grade column as
its source and adds no column (design-level), plus tests that the derivation
maps `yes` to eligible and `no`, `deferred`, unknown, and malformed values to
ineligible for every shipped rung read from the registry, and that a send
needs both the sender's probe and a recorded target address.

### REQ-A1.5 — absence changes nothing on the signal paths [test]

With the probe forced absent, delivery, doorbell, idle-notice, and
demoted-sweep consumers take exactly today's code paths (fixture-diffed
behavior in the suite); launch naming and inbound settings are applied and
verified inert (fixture).

### REQ-A1.4 — platform-contract drift guard [test]

The drift-guard fixtures assert the pinned contract assumptions (env-var
names, socket line framing, version gates) and fail visibly when violated;
the verified CLI version is recorded and asserted present in the task's
deliverable.

## REQ-B — Addressable identity

### REQ-B1.1 — deterministic launch names [test + manual]

Grammar tests for name derivation per rung and for the tower launch seams;
a live dispatch per session-grade rung shows the worker under its derived
name in the listing, and a fleet-launched tower appears under its derived
name.

### REQ-B1.2 — read-back and registry record [test + manual]

Tests that the recorded name and socket path are the observed ones, in the
worker registry for a worker and in the tower marker for a tower; a manual
collision check (two same-named launches) records the CLI's variant, not
the request.

### REQ-B1.3 — names validated as data [test]

Hostile-name fixtures (control bytes, traversal, over-length, shell
metacharacters) are refused before addressing, path use, or echo.

## REQ-C — Downward delivery

### REQ-C1.1 — messaging-first with fallback ladder [test + manual]

Fixture-forced refusal/absence against a test-bound socket walks messaging
→ the rung's attributed steer delivery → operator handoff in order; a
steer-less rung (`headless-oneshot`) receives no delivery; a live tmux check
delivers a steer via messaging end to end.

### REQ-C1.2 — claim, persist, then deliver; never re-claim [test]

Ordering tests against the decision-channel store: the answer artifact
exists before any delivery attempt; induced delivery failure (socket absent
or refusing) leaves the fork closed and the artifact recoverable; no code
path re-claims.

### REQ-C1.5 — synchronous outcomes consumed; held surfaced only [test + manual]

Post-outcome tests against a test-bound socket speaking the pinned protocol:
refused and a failed post trigger the fallback; held is surfaced as
unconfirmed and never re-sent; accepted is not reported as delivered. A live
held-message check (receiver holding inbound) is surfaced, never presumed
delivered.

### REQ-C1.4 — no impersonation, no permission answering [test + design-level]

By-construction review of the delivery path (design-level) plus tests that
message text is handled as data (no eval/expansion path; a permission-park
record is never answered via the messaging arm).

## REQ-D — Upward signals

### REQ-D1.1 — hook-posted doorbells, no model turn [test]

A simulated worker hook event posts a doorbell to a test-bound socket via
the script path only; the test asserts no model invocation is present on
the routine path (script-level, statically greppable).

### REQ-D1.2 — pointer payload, store re-read [test]

Doorbell grammar tests against the D-15 line (the five fields, the kind
set, the handle grammar on worker and instance, the 256-byte bound, no
control bytes; producer and receiver share one fixture table);
`doorbell-read` refuses hostile pointers and, for a spoofed pointer whose
content contradicts the store, returns only store content, never the
message content.

### REQ-D1.3 — idle notices as supplement [manual]

A live two-session check: the tower session subscribes after dispatch and
re-arms after a delivered steer, a notice arrives on worker idle; liveness
classification verified unchanged when notices are absent.

### REQ-D1.4 — lost signals healed by the sweep [test]

With doorbells suppressed, the retained healing sweep surfaces the store row
within `messaging_heal_cadence_seconds`, driven by the injected `--now`
clock rather than wall time (same fixture as REQ-E1.2).

### REQ-D1.5 — tower socket path propagation [test]

Dispatch-env fixtures: the path is present at worker launch and the
fallback marker read works when it is not; a missing, dangling, or
wrong-owner socket path degrades the doorbell path cleanly to the healing
sweep with a single logged notice, never a retry loop.

## REQ-E — Store-load reduction

### REQ-E1.1 — cadence demotion where push is live [test]

Each demoted consumer reads the derived eligibility and the probe: push
present demotes to `messaging_heal_cadence_seconds` (one value, every
consumer); push absent keeps today's cadence (fixture-forced both ways).

### REQ-E1.2 — healing sweep never removed [test]

Suppressed-push healing test (shared with REQ-D1.4): the sweep recovers the
signal at every discipline value, including `open`.

### REQ-E1.3 — record semantics untouched [test + design-level]

Diff-review of the reduction changes (design-level: reads and cadences only)
plus store-schema tests asserting no write path or record shape changed.

## REQ-F — Settings & discipline

### REQ-F1.1 — worker inbound acceptance wired at dispatch [test + manual]

Dispatch-seam tests that the settings profile reaches the worker (visible
failure when it cannot); a live per-rung check that an unattended worker
accepts an inbound message.

### REQ-F1.2 — the discipline knob [test]

Knob resolution tests through the overlay layers: ladder values validated,
default `tiered`, unknown values refused with a visible diagnostic.

### REQ-F1.3 — direction asymmetry [test]

`effective-mode` tests: the knob value is the worker→tower value and
tower→worker resolves one value stricter, saturating at `doorbell`
(`doorbell` resolves `doorbell` in both directions).

### REQ-F1.4 — send-time pressure demotion [test]

Usage-gate rung fixtures: a rung at or above `reduce-concurrency` demotes
one value, saturating at `doorbell`, and writes one log line per demoted
send (none otherwise); a rung below it, or an unavailable gate, applies no
demotion; the context-budget monitor's output is ignored; no mode state
file exists after any sequence; the decision path is script-only.

### REQ-F1.5 — cross-machine double gate [manual]

Live checks: a cross-machine send with `messaging_cross_machine` off is
refused; with it on the send still prompts for approval; script paths post
to local socket paths only (fixture); both shipped settings profiles carry
`isolatePeerMachines: true` (design-level review of the profiles).

## REQ-G — Degradation & carried floors

### REQ-G1.1 — named fallback per path [test + design-level]

Each messaging path's header names its fallback (design-level review);
fixture-forced absence reaches it with no operator step to select it
(shared with REQ-A1.5).

### REQ-G1.2 — no state of record on messages [design-level]

Bundle and implementation review: every upward payload is a pointer and
every downward or advisory message is instruction text with its record
behind it; no consumer treats message content as durable state.

### REQ-G1.3 — carried floors unchanged [design-level]

Review against the fleet-coordination floors: no LLM in daemon mechanics,
never-impersonate, non-authoring, no auto-merge, and the
deterministic-attention floor's operator push left to `merge-currency-guard`.

### REQ-G1.4 — advisory-only tower↔tower [test + manual]

Prose and guard review that no advisory path writes fence, presence, or
`tasks.md` state and that the advisory rule cites the assume-multiplicity
floor rather than restating authority; a live advisory message check
confirms delivery with no correctness side effect.

### REQ-G1.5 — the doctrine document [design-level]

The messaging-transport doctrine exists, resolves through the rule-doc
chain, states the signal-vs-record rule, the fallback obligation (with the
per-path fallback table), the discipline ladder, and the cross-machine
transit note, and is cited by the shipped scripts and prose.

### REQ-G1.6 — no new lifecycle resource class [design-level]

Review of the doctrine doc's declaration against the lifecycle-closure
floor's class contract: the inbox socket, the idle-notice subscription, and
the tower socket path record are each accounted for as harness-owned,
self-closing, or riding an existing class, with the reason stated, so no
row is missing by omission.

### REQ-G1.7 — inter-orchestrator-coordination doctrine amended [design-level]

Review that the amended doctrine's steer-in-flight section names messaging
first and attributed buffer-paste as the fallback, that its tower↔tower
paragraph cross-references REQ-G1.4's advisory rule, and that
`mise run check:links` and `check:doctrine-index` pass on the amended doc.

## REQ-H — Security & hygiene

### REQ-H1.4 — inbound content untrusted [test]

Hostile doorbell/message fixtures (control bytes, over-length, forged
worker ids, contradicting content) are screened, sanitized before echo, and
a doorbell drives action only through `doorbell-read`'s store re-read;
steer and advisory text is screened and sanitized but never re-validated
against the store.

### REQ-H1.2 — message hygiene [test + design-level]

Echo-sanitization tests on every message-derived output; design-level
review that no shipped path places secrets or sensitive operational detail
in message text, with the cross-machine transit note in the doctrine doc.

### REQ-H1.3 — one enforcement point [test]

A source audit over the shipped scripts (statically greppable, the same
shape as the relay's send-keys audit): every inbox-socket post and every
doorbell parse lives in `fleet-messaging.sh`; `orchestrate-relay.sh` and
`fleet-decision.sh` reach it by delegation only; the audit fails on any
other script that opens a socket path or matches the D-15 tag.
