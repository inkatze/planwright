# Fleet Messaging — Design

**Status:** Draft
**Last reviewed:** 2026-09-02
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new decision minted in this bundle's drafting session
(2026-08-27); `R` = minted in the 2026-09-02 revision of the halted kickoff's
worklist (brief §8).

## Decision log

### D-1: Altitude — a signal transport plus a store-load reduction, not a state-store replacement  (N)

**Decision:** Cross-session messaging enters planwright as the fleet's
preferred *signal transport* plus the *store-load reduction* it enables.
Durable state (worker registry, origin fences, audit trail, the `tasks.md`
record) stays file/git-based and level-triggered. This is the altitude record
for the pinned seed claim ("use this instead of serialized JSON persistent"),
cited from the bundle's goal.

**Alternatives considered:**
- Full state replacement (the seed's literal reading). Rejected because:
  messages are lossy and ephemeral (held/refused/expired/dropped, nothing
  persisted), every delivery lands as a model turn — colliding with the
  no-LLM-daemon-mechanics floor for anything mechanical — and availability is
  gated by version, provider, and feature flags, so state would need a file
  fallback anyway.
- Transport only, no reduction. Rejected because: it leaves the seed's
  "manage state better" half unrealized — the store's contention is amplified
  by signal-rate reads and polls that a push path makes unnecessary.

**Chosen because:** the honest capability boundary — the platform channel is
built for signals, planwright's floors are built on durable level-triggered
ground truth, and the reduction is where messaging actually improves state
management.

### D-2: Signal vs record — doorbell-only payload, push-first, reconcile-backed  (N)

**Decision:** A push signal carries only a minimal pointer ("worker X has a
new attention row"); the store row is the authoritative content, written
before the signal. The level-triggered reconcile is retained at every
discipline mode, demoted to a documented low-cadence floor where push is
live. This generalizes the push-first-reconcile-backed pattern the worktree
tracker established.

**Alternatives considered:**
- Full payload in the message. Rejected because: a dropped or held message
  then loses content, and the message becomes a second copy of the record
  that can diverge from the store.
- Payload plus store as backstop. Rejected because: duplicates content on
  every signal for a hot-path gain the doorbell-plus-read already delivers
  at fleet scale.

**Chosen because:** doorbells are loss-tolerant by construction — a lost
signal costs latency, never correctness — and the store remains the single
source of truth.

**Superseded-by: D-16** (2026-09-02) — the rejected "payload plus store as
backstop" shape is exactly what D-9 adopts for decision answers, so the
pointer-only rule is scoped to upward signals, where it was always the
motivating case.

### D-16: Signal vs record — upward signals are pointer-only, push-first, healing-sweep-backed  (R, supersedes D-2)

**Decision:** An upward signal (worker→tower) carries only a minimal pointer
("worker X has a new attention row"); the store row is the authoritative
content, written before the signal. Downward deliveries (steer, decision
answers) are instructions addressed to a session, not signals: they carry
their text, and for a decision answer the persisted answer artifact (D-9) is
the recovery source, never a second record. The level-triggered healing
sweep is retained at every discipline value, demoted to a documented
low-cadence sweep where push is live. This generalizes the
push-first-reconcile-backed pattern fleet-autonomy D-1 established and its
worktree tracker (fleet-autonomy D-7) applied.

**Alternatives considered:**
- Full payload in every upward message. Rejected because: a dropped or held
  message then loses content, and the message becomes a second copy of the
  record that can diverge from the store.
- Pointer-only in both directions (a decision answer delivered as "fork X is
  answered; read the artifact"). Rejected because: today's attributed paste
  delivers the answer text, and a pointer would add a worker-side file read
  to every answer for no loss-tolerance gain the persisted artifact does not
  already give.

**Chosen because:** upward doorbells are loss-tolerant by construction — a
lost signal costs latency, never correctness — and the store remains the
single source of truth; downward text is what a session acts on, with the
artifact behind it.

### D-3: Delivery ladder — messaging-first on every steer-advertising rung, existing mechanism as fallback  (N)

**Decision:** Tower→worker steer and decision-answer delivery prefer
messaging on every rung that advertises steer-in-flight and is eligible
(D-17), `tmux` included. The fallback ladder is messaging → the rung's
existing attributed steer delivery (tmux buffer-paste; the backend's
equivalent elsewhere) → operator handoff (today's undelivered-answer
surfacing). A rung whose contract row lacks steer-in-flight
(`headless-oneshot`: no pend path, ambiguity routes to the queue) receives
no downward delivery.
*(Amended at revision 2026-09-02: rung set pinned to steer-advertising
rungs; the contract row is not flipped.)*

**Alternatives considered:**
- Paste-first on tmux, messaging only elsewhere. Rejected because: it keeps
  two primary delivery paths alive, retains the tower command-guard friction
  on the attributed send shape (obs:b7618838), and forfeits the
  harness-attributed channel on the richest rung.
- Messaging only where no steer exists today. Rejected because: smallest
  blast radius but no reduction and no friction removal on the rungs
  operators actually run.
- Flipping `headless-oneshot`'s steer row to `true` when messaging is
  present. Rejected because: it makes a static contract row
  availability-dependent, which the table, the registry, and the drift tether
  cannot express, and the rung has no fork to answer.

**Chosen because:** the platform channel provides by construction the exact
properties the relay contract exists to enforce — attribution, no
impersonation, no permission-prompt answering — so one uniform channel with
a documented fallback beats two live paths.

### D-4: Messaging discipline — a laddered knob with direction asymmetry and send-time pressure demotion  (N)

**Decision:** `messaging_discipline` is a config knob, values
`doorbell` < `tiered` < `open`, shipped default `tiered`, resolved through
the standard overlay layers. The knob value names the worker→tower value;
tower→worker resolves one value stricter. The *effective* value is evaluated
at send time by deterministic script logic reading the existing usage
monitor: reported pressure steps the effective value down one, and clearing
restores it. Both offsets saturate at `doorbell`, so the composition is
`effective = max(doorbell, knob − direction offset − pressure demotion)` and
their order is immaterial. The ladder gates model-composed traffic only;
deterministic script sends (doorbell posts upward, script-posted answers and
steers downward) ride at every value. Every send that runs demoted writes
one log line; no stored mode state, no daemon flip, no LLM in the decision.
*(Amended at revision 2026-09-02: direction anchoring, saturating floor,
order-free composition, and per-send logging stated, from the kickoff §2–3
intent.)*

**Alternatives considered:**
- A fixed tiered rule for everyone. Rejected because: the operator's desired
  posture is a style value, not a general law — the capability (a discipline
  ladder) belongs in core, the chosen value in an overlay
  (the customization-boundary doctrine).
- A fixed open rule. Rejected because: token cost and interrupt noise scale
  with fleet size and nothing planwright-side would bound them.
- A stored effective-value file flipped by a daemon. Rejected because: stores
  derived state (the invariant-ledger lesson, invariant-tasks D-2) and adds a
  writer; send-time evaluation is level-triggered and cannot go stale.
- A `silent` value below `doorbell` as the pressure floor. Rejected because:
  deterministic doorbells are the cheapest signal there is, and stopping them
  buys nothing but healing-sweep latency.

**Chosen because:** it dissolves the capability-vs-style tension per the
customization boundary, protects workers (the focus-bearing side) more than
towers (the interrupt-absorbing side), and degrades autonomously under
measured pressure instead of relying on operator vigilance.

### D-5: Cross-machine — opt-in knob plus per-send operator approval, never a default  (N)

**Decision:** Same-machine messaging is the default and the only unattended
posture. A cross-machine send requires an opt-in config knob *and* per-send
operator approval. Only a model-composed send can be cross-machine: script
paths post to a local inbox socket path and are same-machine by
construction, so the approval gate is the harness's own tool-call prompt.
The shipped settings profiles carry `isolatePeerMachines: true`; the knob's
documented effect is that turning it on is the operator's cue to relax that
setting, so nothing leaves the machine silently. Remote sessions are not
fleet peers: presence, liveness, and dispatch stay single-host.
*(Amended at revision 2026-09-02: scoped to model-composed sends; the
knob-to-setting relation stated.)*

**Alternatives considered:**
- Out of scope entirely. Rejected because: the operator explicitly wants a
  deliberate path to reach off-host sessions (a cloud session, another
  machine) without waiting for a follow-on spec.
- Full cross-machine fleet peering. Rejected because: host-local death
  evidence and presence cannot classify a remote peer, and off-host
  messages transit third-party infrastructure — amending the signed
  single-host coordination floor is not this bundle's business.

**Chosen because:** capability without silent egress — the knob plus the
harness's own approval gate makes every off-host send a conscious act.

### D-6: Advertisement — extend the backend capability contract in place with a peer-messaging property  (N)

**Decision:** Messaging reach is advertised per backend rung as a contract
property (the `hook_registration` shape): tmux and both `-p` rungs can bind
inboxes; in-harness subagents and `in-session` are structurally without it;
`print` defers to the human-launched session. A host-level deterministic
probe (inbox-socket environment presence plus CLI version) gates the whole
capability; unknown or malformed reads as absent, fail-safe. Consumers key
on the property, never on backend names.

**Alternatives considered:**
- A standalone availability registry outside the contract. Rejected because:
  duplicates the contract's advertisement mechanism and re-creates the
  N×M backend×skill surface the contract collapsed.
- Probing ad hoc at each call site. Rejected because: scatters
  version/provider logic across consumers and guarantees drift.

**Chosen because:** the contract was built to absorb exactly this — a
capability that varies by substrate — and extending it in place is the
established precedent.

**Superseded-by: D-17** (2026-09-02) — socket-env presence is a per-session
fact, so a host-level gate probed from a socket-less rung reads everything
absent; and the rung set D-6 enumerates coincides exactly with the
contract's existing session-grade column, so no new property is needed.

### D-17: Availability — eligibility derived from session-grade, availability probed per session  (R, supersedes D-6)

**Decision:** Messaging availability has two parts. *Eligibility* is a
property of the rung, derived from the backend capability contract's
existing session-grade column: `yes` rungs can bind an inbox socket, `no`
and `deferred` rungs cannot, and an unknown or malformed value reads as
ineligible. No column is added to the contract table and the adapter line
grammar keeps its arity; the contract doc gains only the derivation rule.
*Availability* is a property of a session, read by a deterministic probe
run inside that session: its own inbox-socket environment presence plus CLI
version comparison. A send is possible when the sending session's probe
reads available and the target has a recorded address. Consumers key on the
derived eligibility and the probe, never on backend names.

**Alternatives considered:**
- A new `peer_messaging` contract column and a 9-field adapter grammar (the
  D-6 shape). Rejected because: it restates the session-grade column under a
  second name, changes the adapter grammar guard-coverage's triangle tether
  pins, and still cannot carry the per-session socket fact.
- A doc-only column in the prose table. Rejected because: pluggable adapters
  cannot advertise it, so consumers would fail-safe absent on every pluggable
  rung for a fact the session-grade field already carries.
- A standalone availability registry outside the contract. Rejected because:
  duplicates the contract's advertisement mechanism and re-creates the N×M
  backend×skill surface the contract collapsed.

**Chosen because:** it uses the contract field that already encodes the
substrate fact and puts the per-session fact where it is observable, with no
grammar change and no second registry.

### D-7: Deterministic doorbells — worker-side hooks post to the tower's inbox socket, content untrusted  (N)

**Decision:** Routine upward signals are posted by deterministic hook
scripts writing one grammar-validated line to the tower's inbox socket —
no worker-model turn on the routine path. Because the socket accepts
connections from any same-OS-user process, doorbell content is untrusted:
the tower session receives it as a message, and its only sanctioned action
is the deterministic store re-read verb (`fleet-messaging.sh doorbell-read`,
D-12), which validates the pointer as data and returns store truth (D-16);
receivers grammar-screen, length-bound, and echo-sanitize before any use.
Send visibility goes to the per-worker debug log, not the audit trail.
*(Amended at revision 2026-09-02: the receiver named and the re-read bound
to a script verb.)*

**Alternatives considered:**
- Worker-model `SendMessage` for routine signals. Rejected because: spends a
  worker model turn per signal and makes a deterministic event depend on
  model behavior.
- Trusting doorbell content on arrival. Rejected because: the same-user
  socket is a spoofable surface — the same trust shape as the
  worker-writable marker store (obs:b47b3043) and the sid-join spoof
  (obs:404d3b7b).
- Recording sends in the fleet audit trail. Rejected because: per-append
  day-file copies inside the fleet lock amplify lock hold with volume — the
  write-amplification failure already observed.
- A tower-side harness hook as a deterministic receiver. Rejected because:
  the platform documents no inbound-message hook; binding the receiver to
  one would rest on unverified behavior.

**Chosen because:** scripts posting one line are cheap, auditable, and
LLM-free; untrusted-content-plus-store-re-read makes spoofing a latency
nuisance rather than a correctness attack.

### D-8: Identity — deterministic session names from the handle grammar, read back and recorded  (N)

**Decision:** Every fleet-launched session is named at launch via `--name`
using the existing fleet handle grammar; the actual name is read back after
launch (the CLI renames collisions to variants) and recorded in the
worker registry. Names are validated as data before addressing, path
use, or echo.

**Alternatives considered:**
- Relying on harness-generated names plus listing round-trips. Rejected
  because: non-deterministic addressing, and the listing is a bounded read
  the fleet would repeat per signal.
- Trusting the requested name without read-back. Rejected because: collision
  renames make the requested name silently wrong — the identity-on-the-wire
  gap in a new coat.

**Chosen because:** deterministic identity at the dispatch seam is what the
worker-identity observation (obs:d4d66281) asked for, and read-back makes
the registry record match observed reality.

### D-9: Decision-channel ordering — claim, persist, deliver, verify; never re-claim  (N)

**Decision:** Answering a fork keeps the store's first-answer-wins claim as
arbiter: claim under the fleet lock, persist the answer artifact, then
attempt delivery (messaging-first per D-3, as a script post to the worker's
inbox socket through D-12), then consume the outcome the post returns
synchronously — accepted, held, or refused, or a failed post — and descend
the fallback ladder on refused or a failed post. Held is surfaced as
unconfirmed and left queued (descending on it would double-deliver);
accepted is not proof of delivery. Dropped and expired are unobservable to a
script and are healed by the healing sweep. A failed delivery never re-opens
or re-claims the fork; the persisted artifact is the recovery source.
*(Amended at revision 2026-09-02: the send bound to a script post with
synchronous outcomes; held surfaced only.)*

**Alternatives considered:**
- Two-phase claim-then-confirm (fork stays open until delivery ACK).
  Rejected because: reintroduces a second writer window on the fork record
  and the platform provides no positive delivery ACK to close on — only
  negative notices.
- Status quo (claim closes the fork before any delivery attempt, exit-4 on
  failure). Rejected as the sole behavior because: it is exactly the
  fork-closed-but-undelivered gap observed live (obs:efe0b752); the outcome
  check plus fallback ladder narrows it substantially.
- Descending the ladder on held as well. Rejected because: a held message
  stays queued at the receiver and is delivered when its inbound control
  relaxes, so a fallback paste duplicates it.
- Model-tool sends with prose-side notice consumption. Rejected because:
  every decision answer would cost a tower model turn, and the consumption
  step would be unenforceable and untestable.

**Chosen because:** it keeps the store's concurrency contract untouched
while consuming every delivery signal a script-posted send can actually
observe.

### D-10: Idle notices — completion supplement only, liveness unchanged  (N)

**Decision:** `notify_when_idle` subscriptions are used for completion and
idle signaling where both sessions accept them (same-machine,
main-conversation subscriber, one-shot, 12-hour expiry). The subscriber is
the tower session's main conversation: it subscribes as an `/orchestrate`
prose step immediately after the dispatch step and re-arms after every
steer or answer it delivers (a delivery wakes the worker, so the prior
one-shot has fired or will). No daemon or script subscribes; an expired
subscription is not renewed. They supplement the completion path only:
positive-evidence-of-death liveness is unchanged, and the absence of a
notice is never read as a signal.
*(Amended at revision 2026-09-02: subscriber and re-arm policy stated.)*

**Alternatives considered:**
- Using idle notices as a liveness input. Rejected because: silence is never
  a signal — an expired or dropped subscription is indistinguishable from a
  busy worker, which is the exact conflation the death-evidence predicate
  exists to prevent.
- Subscribing once at dispatch and never re-arming. Rejected because: a
  worker that idles on a fork burns its one notice early, and its completion
  then reaches the tower by the healing sweep alone.
- Re-arming on every `--watch` iteration. Rejected because: it needs either
  stored armed-state, which this bundle's posture rejects, or an idempotent
  re-subscribe the platform does not document.

**Chosen because:** a notice is positive evidence of idle at zero token cost
in the watched session; treating it as anything more would re-open the
stuck-detector failure shape.

### D-11: Platform-contract posture — pin, probe, fixture-test; drift fails visibly  (N)

**Decision:** The messaging contract surface this bundle consumes
(environment variables, socket line protocol, tool semantics, version
gates) is treated as a version-sensitive external contract: each task
records the CLI version it verified against (the launch-pin precedent),
runtime behavior goes through the deterministic probe (D-17), and parsing is
fixture-tested so a harness-side change fails a visible test or probe,
never a silent no-op.

**Alternatives considered:**
- Trusting documented behavior without per-version verification. Rejected
  because: the WorktreeCreate incident (obs:16facd5b) shows a mis-assumed
  hook contract silently no-op'ing a core mechanism fleet-wide.

**Chosen because:** planwright already learned this lesson twice (the
non-`--bare` pin, the hook-contract correction); paying the pin-and-probe
cost up front is cheaper than a silent fleet-wide outage.

### D-12: One enforcement point — `fleet-messaging.sh`; relay and decision channel delegate  (N)

**Decision:** A single audited script owns the messaging mechanics —
`probe`, `effective-mode`, `send`, `doorbell`, `doorbell-read` — mirroring
the relay's one-audited-place pattern. `send` and `doorbell` post directly
to a target inbox socket and return the outcome the post yields
synchronously; `doorbell-read` is the receiver's store re-read verb (D-7).
`orchestrate-relay.sh` gains a messaging arm and `fleet-decision.sh`
delivers through it by delegation; neither grows parallel messaging code.
*(Amended at revision 2026-09-02: the subcommand set and the script-post
shape stated.)*

**Alternatives considered:**
- Inline messaging logic in each consumer. Rejected because: re-derives
  validation and fallback logic per caller — the exact scatter the relay
  script was created to end.

**Chosen because:** the security-critical properties (validation, data-only
handling, discipline enforcement) live in one testable place.

### D-13: Doctrine home — a new messaging-transport doctrine  (N)

**Decision:** The durable rule — messages are ephemeral signals, files/git
are the record; push-first, healing-sweep-backed; discipline is laddered and
pressure-demoted — ships as its own doctrine document, cited by the skills
and scripts that apply it. The fleet-coordination-floor doctrine is not
amended.

**Alternatives considered:**
- A sixth floor in the fleet-coordination-floor doctrine. Rejected because:
  that document's citations belong to three other signed bundles; amending
  it from here couples their lifecycles.
- No doctrine doc (rule stated only in this bundle). Rejected because:
  future skills would cite a spec bundle rather than doctrine, which is not
  how the other floors are consumed.

**Chosen because:** the backend-capability-contract precedent — a transport
contract earns its own citable doctrine document.

### D-14: Tower↔tower advisory — sanctioned, and never on the correctness path  (N)

**Decision:** Tower↔tower messages are sanctioned for the advisory layer
operators hand-relay today ("main advanced", "I'm draining spec X"), under
a hard rule: a message never claims, releases, or resolves a unit of work.
Authority over the division of work stays exactly where the
fleet-coordination-floor doctrine's assume-multiplicity floor places it;
this bundle restates none of it.
*(Amended at revision 2026-09-02: the restated authority list replaced by a
citation of the floor.)*

**Alternatives considered:**
- Out of scope until `concurrent-orchestrator-coordination` executes.
  Rejected because: the advisory layer touches nothing that bundle owns,
  and hand-relay friction is a present cost.
- Advisory plus coordination semantics. Rejected because: it would put a
  lossy channel on the correctness path and reopen a signed design.

**Chosen because:** it replaces exactly the manual relay burden while
leaving every authoritative surface untouched.
