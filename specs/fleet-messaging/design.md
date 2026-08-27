# Fleet Messaging — Design

**Status:** Draft
**Last reviewed:** 2026-08-27
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new decision minted in this bundle's drafting session
(2026-08-27).

## Decision log

### D-1: Altitude — a signal transport plus a store-load diet, not a state-store replacement  (N)

**Decision:** Cross-session messaging enters planwright as the fleet's
preferred *signal transport* plus the *store-load diet* it enables. Durable
state (worker/scope registry, origin fences, audit trail, task ledger) stays
file/git-based and level-triggered. This is the altitude record for the
pinned seed claim ("use this instead of serialized JSON persistent"), cited
from the bundle's goal.

**Alternatives considered:**
- Full state replacement (the seed's literal reading). Rejected because:
  messages are lossy and ephemeral (held/refused/expired/dropped, nothing
  persisted), every delivery lands as a model turn — colliding with the
  no-LLM-daemon-mechanics floor for anything mechanical — and availability is
  gated by version, provider, and feature flags, so state would need a file
  fallback anyway.
- Transport only, no diet. Rejected because: it leaves the seed's "manage
  state better" half unrealized — the store's contention is amplified by
  signal-rate reads and polls that a push path makes unnecessary.

**Chosen because:** the honest capability boundary — the platform channel is
built for signals, planwright's floors are built on durable level-triggered
ground truth, and the diet is where messaging actually improves state
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

### D-3: Delivery ladder — messaging-first everywhere it is accepted, existing mechanism as fallback  (N)

**Decision:** Tower→worker steer and decision-answer delivery prefer
messaging on every rung that advertises and accepts it, tmux included. The
fallback ladder is messaging → the rung's existing attributed delivery
(tmux buffer-paste) → park for the operator.

**Alternatives considered:**
- Paste-first on tmux, messaging only elsewhere. Rejected because: it keeps
  two primary delivery paths alive, retains the tower-guard friction on the
  attributed send shape (obs:b7618838), and forfeits the harness-attributed
  channel on the richest rung.
- Messaging only where no steer exists today. Rejected because: smallest
  blast radius but no diet and no friction removal on the rungs operators
  actually run.

**Chosen because:** the platform channel provides by construction the exact
properties the relay contract exists to enforce — attribution, no
impersonation, no permission-prompt answering — so one uniform channel with
a documented fallback beats two live paths.

### D-4: Message discipline — a laddered knob with direction asymmetry and send-time pressure demotion  (N)

**Decision:** `messaging_discipline` is a config knob, values
`doorbell` < `tiered` < `open`, shipped default `tiered`, resolved through
the standard overlay layers. It is direction-aware (worker→tower one rung
more permissive than tower→worker at the same setting). The *effective* mode
is evaluated at send time by deterministic script logic reading the existing
context-budget and usage monitors: reported pressure steps the effective
mode down one rung, logged; clearing restores it. No stored mode state, no
daemon flip, no LLM in the decision.

**Alternatives considered:**
- A fixed tiered rule for everyone. Rejected because: the operator's desired
  posture is a style value, not a general law — the capability (a discipline
  ladder) belongs in core, the chosen rung in an overlay.
- A fixed open rule. Rejected because: token cost and interrupt noise scale
  with fleet size and nothing planwright-side would bound them.
- A stored effective-mode file flipped by a daemon. Rejected because: stores
  derived state (the invariant-ledger lesson) and adds a writer; send-time
  evaluation is level-triggered and cannot go stale.

**Chosen because:** it dissolves the capability-vs-style tension per the
customization boundary, protects workers (the focus-bearing side) more than
towers (the interrupt-absorbing side), and degrades autonomously under
measured pressure instead of relying on operator vigilance.

### D-5: Cross-machine — opt-in knob plus per-send operator approval, never a default  (N)

**Decision:** Same-machine messaging is the default and the only unattended
posture. A cross-machine send requires an opt-in config knob *and* per-send
operator approval; fleet profiles recommend `isolatePeerMachines: true`.
Remote sessions are not fleet peers: presence, liveness, and dispatch stay
single-host.

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

### D-7: Deterministic doorbells — worker-side hooks post to the tower's inbox socket, content untrusted  (N)

**Decision:** Routine upward signals are posted by deterministic hook
scripts writing one grammar-validated line to the tower's inbox socket —
no worker-model turn on the routine path. Because the socket accepts
connections from any same-OS-user process, doorbell content is untrusted:
the tower acts only on the store re-read (D-2), and receivers
grammar-screen, length-bound, and echo-sanitize before any use. Send
visibility goes to the per-worker debug log, not the audit trail.

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

**Chosen because:** scripts posting one line are cheap, auditable, and
LLM-free; untrusted-content-plus-store-re-read makes spoofing a latency
nuisance rather than a correctness attack.

### D-8: Identity — deterministic session names from the handle grammar, read back and recorded  (N)

**Decision:** Every fleet-launched session is named at launch via `--name`
using the existing fleet handle grammar; the actual name is read back after
launch (the CLI renames collisions to variants) and recorded in the
worker/scope registry. Names are validated as data before addressing, path
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
arbiter: claim under the store lock, persist the answer artifact, then
attempt delivery (messaging-first per D-3), then check sender-side delivery
outcomes (held/refused/dropped/expired notices) and descend the fallback
ladder on failure. A failed delivery never re-opens or re-claims the fork;
the persisted artifact is the recovery source.

**Alternatives considered:**
- Two-phase claim-then-confirm (fork stays open until delivery ACK).
  Rejected because: reintroduces a second writer window on the fork record
  and the platform provides no positive delivery ACK to close on — only
  negative notices.
- Status quo (claim closes the fork before any delivery attempt, exit-4 on
  failure). Rejected as the sole behavior because: it is exactly the
  fork-closed-but-undelivered gap observed live (obs:efe0b752); the notice
  check plus fallback ladder narrows it substantially.

**Chosen because:** it keeps the store's concurrency contract untouched
while consuming every delivery signal the platform actually provides.

### D-10: Idle notices — completion supplement only, liveness unchanged  (N)

**Decision:** `notify_when_idle` subscriptions are used for completion and
idle signaling where both sessions accept them (same-machine,
main-conversation subscriber, one-shot, 12-hour expiry). They supplement the
completion path only: positive-evidence-of-death liveness is unchanged, and
the absence of a notice is never read as a signal.

**Alternatives considered:**
- Using idle notices as a liveness input. Rejected because: silence is never
  a signal — an expired or dropped subscription is indistinguishable from a
  busy worker, which is the exact conflation the death-evidence predicate
  exists to prevent.

**Chosen because:** a notice is positive evidence of idle at zero token cost
in the watched session; treating it as anything more would re-open the
stuck-detector failure shape.

### D-11: Platform-contract posture — pin, probe, fixture-test; drift fails visibly  (N)

**Decision:** The messaging contract surface this bundle consumes
(environment variables, socket line protocol, tool semantics, version
gates) is treated as a version-sensitive external contract: each task
records the CLI version it verified against (the launch-pin precedent),
runtime behavior goes through the deterministic probe (D-6), and parsing is
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
`probe`, `effective-mode`, `send`, `doorbell` — mirroring the relay's
one-audited-place pattern. `orchestrate-relay.sh` gains a messaging arm and
`fleet-decision.sh` delivers through it by delegation; neither grows
parallel messaging code.

**Alternatives considered:**
- Inline messaging logic in each consumer. Rejected because: re-derives
  validation and fallback logic per caller — the exact scatter the relay
  script was created to end.

**Chosen because:** the security-critical properties (validation, data-only
handling, discipline enforcement) live in one testable place.

### D-13: Doctrine home — a new `doctrine/messaging-transport.md`  (N)

**Decision:** The durable rule — messages are ephemeral signals, files/git
are the record; push-first, reconcile-backed; discipline is laddered and
pressure-demoted — ships as its own doctrine document, cited by the skills
and scripts that apply it. `fleet-coordination-floor.md` is not amended.

**Alternatives considered:**
- A sixth floor in `fleet-coordination-floor.md`. Rejected because: that
  document's citations belong to three other signed bundles; amending it
  from here couples their lifecycles.
- No doctrine doc (rule stated only in this bundle). Rejected because:
  future skills would cite a spec bundle rather than doctrine, which is not
  how the other floors are consumed.

**Chosen because:** the backend-capability-contract precedent — a transport
contract earns its own citable doctrine document.

### D-14: Tower↔tower advisory — sanctioned, and never on the correctness path  (N)

**Decision:** Tower↔tower messages are sanctioned for the advisory layer
operators hand-relay today ("main advanced", "I'm draining spec X"), under
a hard rule: a message never claims, releases, or resolves a unit of work.
The origin fence and the presence surface remain the sole authorities on
division of work.

**Alternatives considered:**
- Out of scope until `concurrent-orchestrator-coordination` executes.
  Rejected because: the advisory layer touches nothing that bundle owns,
  and hand-relay friction is a present cost.
- Advisory plus coordination semantics. Rejected because: it would put a
  lossy channel on the correctness path and reopen a signed design.

**Chosen because:** it replaces exactly the manual relay burden while
leaving every authoritative surface untouched.
