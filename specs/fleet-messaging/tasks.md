# Fleet Messaging — Tasks

**Status:** Draft
**Last reviewed:** 2026-09-02
**Format-version:** 2
**Execution:** derived — see the status render

## Tasks

### Task 1 — Doctrine and contract layer

- **Deliverables:** the messaging-transport doctrine (signal-vs-record rule,
  fallback obligation, discipline ladder with direction asymmetry and
  pressure demotion); the backend capability contract doc gaining the
  session-grade eligibility derivation and the per-session probe definition
  (no new column, no adapter-field change); options-reference entries for
  `messaging_discipline` and the cross-machine opt-in knob; the doctrine
  index updated.
- **Done when:** the doctrine doc resolves through the rule-doc chain; the
  contract doc states the derivation rule and names the eligible rungs by
  column reference; both knobs are documented in the options reference with
  defaults; `mise run check` doc guards pass.
- **Dependencies:** none
- **Citations:** D-4, D-13, D-16, D-17 · REQ-A1.6, REQ-F1.2, REQ-G1.5
- **Estimated effort:** 1 day

### Task 2 — The enforcement point: `fleet-messaging.sh`

- **Deliverables:** `scripts/fleet-messaging.sh` with subcommands `probe`
  (the invoking session's availability from its socket env and CLI version),
  `effective-mode` (knob resolution through the overlay layers, direction
  argument, send-time pressure demotion from the usage monitor, saturating
  at `doorbell`, one log line per demoted send), `send` (discipline-checked
  post to a target inbox socket returning the synchronous outcome:
  accepted, held, refused, or a failed post), `doorbell` (grammar-validated
  one-line pointer post to a target inbox socket), and `doorbell-read` (the
  receiver's store re-read verb: validates a doorbell pointer as data and
  returns store truth, never message content); fixture tests for probe
  parsing, grammar refusal, mode resolution, outcome handling, and doorbell
  framing against a test-bound socket; the platform-contract drift guard
  (fixture-tested contract assumptions with the verified CLI version
  recorded).
- **Done when:** the test suite covers accept/refuse paths for every
  subcommand including hostile input (control bytes, over-length, traversal
  tokens) and the demotion values; probe reads absent on a host without the
  feature; the drift guard fails visibly when a pinned contract assumption
  is violated; shell lint and secret scan pass.
- **Dependencies:** 1
- **Citations:** D-4, D-7, D-11, D-12, D-17 · REQ-A1.1, REQ-A1.4, REQ-A1.5,
  REQ-C1.5, REQ-D1.2, REQ-F1.4, REQ-H1.4
- **Estimated effort:** 2 days

### Task 3 — Settings and profile wiring

- **Deliverables:** worker settings carrying `crossSessionInbound: accept`
  through the mechanism verified to apply per rung (the
  `settings.local.json` + env-gate pattern where `--settings` does not
  register); settings delivery folded into the dispatch seam for every
  session-grade rung; tower profile acceptance of worker messages;
  `isolatePeerMachines: true` carried in both shipped settings profiles; the
  cross-machine opt-in knob, documented as the cue to relax that setting,
  with the harness tool-call prompt as the per-send approval.
- **Done when:** a dispatched worker on each session-grade rung accepts an
  inbound message unattended in a live check; the dispatch seam fails
  visibly (not silently) when settings delivery fails; a cross-machine send
  without the knob is refused and with the knob still prompts.
- **Dependencies:** 1
- **Citations:** D-3, D-5 · REQ-F1.1, REQ-F1.5 · obs:eea622de, obs:58aa232e
- **Estimated effort:** 1 day

### Task 4 — Addressable identity at the dispatch seams

- **Deliverables:** `--name` derivation from the fleet handle grammar at
  every dispatch seam (`tmux`, `stream-json-persistent`, `headless-oneshot`);
  post-launch name read-back; the worker registry record extended
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
  claim → persist artifact → deliver messaging-first → consume the
  synchronous post outcome (held surfaced, refused and a failed post fall
  back) → descend the fallback ladder (the rung's attributed steer delivery
  → operator handoff); never re-claim; tower command-guard allow rules
  covering the new delivery shape.
- **Done when:** delivery prefers messaging on steer-advertising eligible
  rungs and falls back cleanly when refused or absent (fixture-forced
  against a test-bound socket); a steer-less rung receives no delivery; the
  fork record is never re-opened on delivery failure and the persisted
  artifact recovers the answer; the no-impersonation and
  no-permission-answer properties hold by construction in tests; a live
  tmux check delivers an answer end to end.
- **Dependencies:** 2, 3, 4
- **Citations:** D-3, D-9, D-12 · REQ-C1.1, REQ-C1.2, REQ-C1.4, REQ-C1.5 ·
  obs:efe0b752, obs:b7618838
- **Estimated effort:** 2 days

### Task 6 — Upward signals: doorbells and idle notices

- **Deliverables:** worker-side hook doorbell posts (attention rows,
  decision forks, parks) to the tower's inbox socket via
  `fleet-messaging.sh doorbell`; tower-side handling bound to
  `fleet-messaging.sh doorbell-read`, with the `/orchestrate` prose naming
  it as the only sanctioned action on a doorbell; `notify_when_idle`
  subscription by the tower session after dispatch, re-armed after each
  downward delivery, for accepting rungs, as a completion supplement;
  per-worker debug-log send visibility (never the audit trail); tower inbox
  socket path propagation at the dispatch seam (dispatch env with the tower
  marker record as fallback, validated before use).
- **Done when:** a worker hook event produces a doorbell on a test-bound
  socket with a grammar-valid payload and no model turn; `doorbell-read`
  refuses every hostile fixture and returns only store content for a
  spoofed pointer; an idle notice arrives in a live two-session check;
  liveness classification is unchanged with notices absent.
- **Dependencies:** 2, 3, 4
- **Citations:** D-7, D-10, D-16 · REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4,
  REQ-D1.5, REQ-H1.4 · obs:67861aa6
- **Estimated effort:** 2 days

### Task 7 — The store-load reduction

- **Deliverables:** signal-purpose poll cadences in the status, dashboard,
  and watch consumers demoted to a documented low-cadence healing sweep
  wherever the push path is advertised and wired; the retained healing
  cadence documented in the doctrine doc and the consumers' headers; a
  before/after duty-cycle note recorded as an observation.
- **Done when:** each demoted consumer reads the derived eligibility and the
  probe and keeps today's cadence when either is absent; the healing sweep is
  exercised by tests (a suppressed doorbell is healed within the documented
  cadence); no record write or store schema changed.
- **Dependencies:** 2, 6
- **Citations:** D-16 · REQ-E1.1, REQ-E1.2, REQ-E1.3 · obs:8b694bdb
- **Estimated effort:** 1 day

### Task 8 — Tower↔tower advisory and skill-prose integration

- **Deliverables:** skill-prose integration for `/orchestrate` (and the
  worker brief template) sanctioning advisory tower↔tower messages under the
  nothing-on-the-correctness-path rule and the discipline knob, within the
  instruction word budgets; discipline prose for when a session model may
  compose a message at each value of the ladder.
- **Done when:** the prose lands under `scripts/check-instructions.sh`
  budgets; the advisory rule cites the assume-multiplicity floor for
  authority over the division of work; a live tower↔tower advisory message
  check passes; the behavioral guidance is exercised by a local (never-CI)
  behavioral eval or recorded as a manual check.
- **Dependencies:** 2, 3
- **Citations:** D-4, D-14 · REQ-F1.2, REQ-F1.3, REQ-G1.4
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
