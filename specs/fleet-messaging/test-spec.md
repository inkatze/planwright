# Fleet Messaging — Test Spec

**Status:** Draft
**Last reviewed:** 2026-08-27
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: script-level behavior (probe parsing, grammar validation,
mode resolution, ordering, doorbell framing against a test-bound socket) is
`[test]` and runs in the repo's shell suite in CI. Live two-session flows
(real message delivery, held/refused outcomes, idle notices) are `[manual]`,
optionally exercised by a local behavioral eval that never runs in CI (the
evals-never-in-CI guard). Doctrine and contract deliverables are
`[design-level]`.

## REQ-A — Availability & advertisement

### REQ-A1.1 — deterministic availability probe [test]

`fleet-messaging.sh probe` fixture tests: socket env present + version
sufficient reads available; env absent, version short, or malformed input
reads absent; no configuration value can force available without the probe.

### REQ-A1.2 — per-rung advertisement, fail-safe [test + design-level]

Contract-table review for every shipped rung (design-level), plus tests
that an unknown, unprobeable, or malformed advertisement resolves to
absent and that socket-less rungs (subagent, in-session) never advertise it.

### REQ-A1.3 — absence changes nothing [test]

With the probe forced absent, delivery, doorbell, and diet consumers take
exactly today's code paths (fixture-diffed behavior in the suite).

### REQ-A1.4 — platform-contract drift guard [test]

The drift-guard fixtures assert the pinned contract assumptions (env-var
names, socket line framing, version gates) and fail visibly when violated;
the verified CLI version is recorded and asserted present in the task's
deliverable.

## REQ-B — Addressable identity

### REQ-B1.1 — deterministic launch names [test + manual]

Grammar tests for name derivation per rung; a live dispatch per
session-grade rung shows the worker under its derived name in the listing.

### REQ-B1.2 — read-back and registry record [test + manual]

Tests that the recorded name is the observed one; a manual collision check
(two same-named launches) records the CLI's variant, not the request.

### REQ-B1.3 — names validated as data [test]

Hostile-name fixtures (control bytes, traversal, over-length, shell
metacharacters) are refused before addressing, path use, or echo.

## REQ-C — Downward delivery

### REQ-C1.1 — messaging-first with fallback ladder [test + manual]

Fixture-forced refusal/absence walks messaging → paste → park in order; a
live tmux check delivers a steer via messaging end to end.

### REQ-C1.2 — claim, persist, then deliver; never re-claim [test]

Ordering tests against the decision-channel store: the answer artifact
exists before any delivery attempt; induced delivery failure leaves the
fork closed and the artifact recoverable; no code path re-claims.

### REQ-C1.3 — delivery outcomes consumed [test + manual]

Sender-side notice handling tests (held/refused/dropped/expired fixtures)
trigger the fallback; a live held-message check (receiver holding inbound)
is surfaced, never presumed delivered.

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

Doorbell grammar tests (minimal fields, validation, length bounds); a
spoofed doorbell whose content contradicts the store cannot drive tower
action past the re-read in the handling tests.

### REQ-D1.3 — idle notices as supplement [manual]

A live two-session check: subscription at dispatch, notice on worker idle;
liveness classification verified unchanged when notices are absent or
expired.

### REQ-D1.4 — lost signals healed by reconcile [test]

With doorbells suppressed, the retained reconcile surfaces the store row
within the documented floor interval (same fixture as REQ-E1.2).

### REQ-D1.5 — tower address propagation [test]

Dispatch-env fixtures: the address is present at worker launch and the
fallback record read works when it is not; a missing, dangling, or
wrong-owner socket path degrades the doorbell path cleanly to the reconcile
floor with a single logged notice, never a retry loop.

## REQ-E — Store-load diet

### REQ-E1.1 — cadence demotion where push is live [test]

Each demoted consumer reads the advertised capability: push present demotes
to the documented floor; push absent keeps today's cadence (fixture-forced
both ways).

### REQ-E1.2 — reconcile never removed [test]

Suppressed-push healing test (shared with REQ-D1.4): the reconcile floor
recovers the signal at every discipline mode, including `open`.

### REQ-E1.3 — record semantics untouched [test + design-level]

Diff-review of the diet changes (design-level: reads and cadences only)
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

`effective-mode` tests: at each setting, worker→tower resolves one rung
more permissive than tower→worker.

### REQ-F1.4 — send-time pressure demotion [test]

Monitor-output fixtures: pressure reported demotes one rung and logs;
pressure cleared restores; no mode state file exists after any sequence;
the decision path is script-only.

### REQ-F1.5 — cross-machine double gate [manual]

Live checks: a cross-machine send without the knob is refused; with the
knob it still prompts for approval; fleet profiles carry the
`isolatePeerMachines` recommendation (design-level review of the profile).

## REQ-G — Degradation & carried floors

### REQ-G1.1 — named fallback per path [test + design-level]

Each messaging path's header names its fallback (design-level review);
fixture-forced absence reaches it without operator intervention (shared
with REQ-A1.3).

### REQ-G1.2 — no state of record on messages [design-level]

Bundle and implementation review: every message payload is a pointer or
advisory; no consumer treats message content as durable state.

### REQ-G1.3 — carried floors unchanged [design-level]

Review against the fleet-coordination floors: no LLM in daemon mechanics,
never-impersonate, non-authoring, no auto-merge, and the
deterministic-attention floor's operator push left to `merge-currency-guard`.

### REQ-G1.4 — advisory-only tower↔tower [test + manual]

Prose and guard review that no advisory path writes fence, presence, or
ledger state; a live advisory message check confirms delivery with no
correctness side effect.

### REQ-G1.5 — the doctrine document [design-level]

`doctrine/messaging-transport.md` exists, resolves through the rule-doc
chain, states the signal-vs-record rule, the fallback obligation, and the
discipline ladder, and is cited by the shipped scripts and prose.

## REQ-H — Security & hygiene

### REQ-H1.1 — inbound content untrusted [test]

Hostile doorbell/message fixtures (control bytes, over-length, forged
worker ids, contradicting content) are screened, sanitized before echo,
and cannot drive action past the store re-read.

### REQ-H1.2 — message hygiene [test + design-level]

Echo-sanitization tests on every message-derived output; design-level
review that no shipped path places secrets or sensitive operational detail
in message text, with the cross-machine transit note in the doctrine doc.
