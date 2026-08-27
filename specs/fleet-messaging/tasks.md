# Fleet Messaging — Tasks

**Status:** Draft
**Last reviewed:** 2026-08-27
**Format-version:** 2
**Execution:** derived — see the status render

## Tasks

### Task 1 — Doctrine and contract layer

- **Deliverables:** `doctrine/messaging-transport.md` (signal-vs-record rule,
  fallback obligation, discipline ladder with direction asymmetry and
  pressure demotion); the backend capability contract extended in place with
  the per-rung peer-messaging property and the host-level probe definition;
  options-reference entries for `messaging_discipline` and the cross-machine
  opt-in knob; the doctrine index updated.
- **Done when:** the doctrine doc resolves through the rule-doc chain; the
  contract table carries the property for every shipped rung with an
  evaluable definition; both knobs are documented in the options reference
  with defaults; `mise run check` doc guards pass.
- **Dependencies:** none
- **Citations:** D-2, D-4, D-6, D-13 · REQ-A1.2, REQ-F1.2, REQ-G1.5
- **Estimated effort:** 1 day

### Task 2 — The enforcement point: `fleet-messaging.sh`

- **Deliverables:** `scripts/fleet-messaging.sh` with subcommands `probe`
  (host + session availability from socket env and CLI version),
  `effective-mode` (knob resolution through the overlay layers, direction
  argument, send-time pressure demotion from the budget/usage monitors,
  logged), `send` (discipline-checked message emit with delivery-notice
  consumption guidance), and `doorbell` (grammar-validated one-line pointer
  post to a target inbox socket); fixture tests for probe parsing, grammar
  refusal, mode resolution, and doorbell framing against a test-bound
  socket; the platform-contract drift guard (fixture-tested contract
  assumptions with the verified CLI version recorded).
- **Done when:** the test suite covers accept/refuse paths for every
  subcommand including hostile input (control bytes, over-length, traversal
  tokens) and the demotion rungs; probe reads absent on a host without the
  feature; the drift guard fails visibly when a pinned contract assumption
  is violated; shell lint and secret scan pass.
- **Dependencies:** 1
- **Citations:** D-4, D-6, D-7, D-11, D-12 · REQ-A1.1, REQ-A1.3, REQ-A1.4,
  REQ-F1.4, REQ-H1.1
- **Estimated effort:** 2 days

### Task 3 — Settings and profile wiring

- **Deliverables:** worker settings carrying `crossSessionInbound: accept`
  through the mechanism verified to apply per rung (the
  `settings.local.json` + env-gate pattern where `--settings` does not
  register); settings delivery folded into the dispatch seam for every
  session-grade rung; tower profile acceptance of worker messages;
  `isolatePeerMachines: true` recommended in fleet profiles; the
  cross-machine opt-in knob wired to per-send operator approval.
- **Done when:** a dispatched worker on each session-grade rung accepts an
  inbound message unattended in a live check; the dispatch seam fails
  visibly (not silently) when settings delivery fails; a cross-machine send
  without the knob is refused and with the knob still prompts.
- **Dependencies:** 1
- **Citations:** D-3, D-5 · REQ-F1.1, REQ-F1.5 · obs:eea622de, obs:58aa232e
- **Estimated effort:** 1 day

### Task 4 — Addressable identity at the dispatch seams

- **Deliverables:** `--name` derivation from the fleet handle grammar at
  every dispatch seam (tmux, stream-json-persistent, headless-oneshot);
  post-launch name read-back; the worker/scope registry record extended
  with the observed name (additive field); validation of names as data
  before addressing, path use, or echo.
- **Done when:** a dispatched worker on each rung appears in the sender-side
  listing under its derived name; a collision-renamed variant is recorded as
  observed; hostile name input is refused by grammar tests.
- **Dependencies:** 2
- **Citations:** D-8 · REQ-B1.1, REQ-B1.2, REQ-B1.3 · obs:d4d66281
- **Estimated effort:** 1 day

### Task 5 — Downward delivery: steer and decision answers

- **Deliverables:** a messaging arm in `orchestrate-relay.sh` delegating to
  `fleet-messaging.sh send`; `fleet-decision.sh` delivery reordered to
  claim → persist artifact → deliver messaging-first → consume delivery
  notices → descend the fallback ladder (existing attributed paste → park);
  never re-claim; tower-guard allow rules covering the new delivery shape.
- **Done when:** delivery prefers messaging when advertised and falls back
  cleanly when refused or absent (fixture-forced); the fork record is never
  re-opened on delivery failure and the persisted artifact recovers the
  answer; the no-impersonation and no-permission-answer properties hold by
  construction in tests; a live tmux check delivers an answer end to end.
- **Dependencies:** 2, 3, 4
- **Citations:** D-3, D-9, D-12 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4 ·
  obs:efe0b752, obs:b7618838
- **Estimated effort:** 2 days

### Task 6 — Upward signals: doorbells and idle notices

- **Deliverables:** worker-side hook doorbell posts (attention rows,
  decision forks, parks) to the tower's inbox socket via
  `fleet-messaging.sh doorbell`; tower-side handling guidance that acts only
  on the store re-read; `notify_when_idle` subscription at the dispatch or
  watch step for accepting rungs, as a completion supplement; per-worker
  debug-log send visibility (never the audit trail); tower inbox-address
  propagation at the dispatch seam (dispatch env with a registry/marker
  fallback, validated before use).
- **Done when:** a worker hook event produces a doorbell on a test-bound
  socket with a grammar-valid payload and no model turn; spoofed doorbell
  content cannot drive tower action past the store re-read in tests; an
  idle notice arrives in a live two-session check; liveness classification
  is unchanged with notices absent.
- **Dependencies:** 2, 3, 4
- **Citations:** D-2, D-7, D-10 · REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4,
  REQ-D1.5, REQ-H1.1 · obs:67861aa6
- **Estimated effort:** 2 days

### Task 7 — The store-load diet

- **Deliverables:** signal-purpose poll cadences in the status, dashboard,
  and watch consumers demoted to a documented low-cadence reconcile floor
  wherever the push path is advertised and wired; the retained reconcile
  floor documented in the doctrine doc and the consumers' headers; a
  before/after duty-cycle note recorded as an observation.
- **Done when:** each demoted consumer reads the advertised capability and
  keeps today's cadence when it is absent; the reconcile floor is exercised
  by tests (a suppressed doorbell is healed within the floor interval); no
  record write or store schema changed.
- **Dependencies:** 2, 6
- **Citations:** D-2 · REQ-E1.1, REQ-E1.2, REQ-E1.3 · obs:8b694bdb
- **Estimated effort:** 1 day

### Task 8 — Tower↔tower advisory and skill-prose integration

- **Deliverables:** skill-prose integration for `/orchestrate` (and the
  worker brief template) sanctioning advisory tower↔tower messages under the
  nothing-on-the-correctness-path rule and the discipline knob, within the
  instruction word budgets; discipline prose for when a session model may
  compose a message at each rung of the ladder.
- **Done when:** the prose lands under `scripts/check-instructions.sh`
  budgets; the advisory rule states that fences and the presence surface
  stay authoritative; a live tower↔tower advisory message check passes; the
  behavioral guidance is exercised by a local (never-CI) behavioral eval or
  recorded as a manual check.
- **Dependencies:** 2, 3
- **Citations:** D-4, D-14 · REQ-F1.2, REQ-F1.3, REQ-G1.4
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
