# Fleet Messaging — Design

**Status:** Ready
**Last reviewed:** 2026-09-07
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new decision minted in this bundle's drafting session
(2026-08-27); `R` = minted in the 2026-09-02 revision of the halted kickoff's
worklist (brief §8); `R2` = minted at the resumed kickoff's revision of
worklist 2 (2026-09-03, brief §8); `R3` = minted at the resumed kickoff's
section-3 walk after the platform experiments (2026-09-04, brief §8);
`R4` = minted at the resumed kickoff's section-4 sanity check and section-5
walk (2026-09-07, brief §8).

## Decision log

### D-1: Altitude — a signal transport plus a store-load reduction, not a state-store replacement  (N)

**Decision:** Cross-session messaging enters planwright as the fleet's
preferred *signal transport* plus the *store-load reduction* it enables.
Durable state (worker registry, origin fences, audit trail, the `tasks.md`
record) stays file/git-based and level-triggered. This is the altitude record
for the pinned seed claim ("use this instead of serialized JSON persistent"),
cited from the bundle's goal.
*(Amended at kickoff 2026-09-02 (resumed): terminology only.)*

**Alternatives considered:**
- Full state replacement (the seed's literal reading). Rejected because:
  messages are lossy and ephemeral (held, refused, dropped, expired; nothing
  persisted), every delivery lands as a model turn — colliding with the
  no-LLM-daemon-mechanics floor for anything mechanical — and availability is
  gated by version, provider, and feature flags, so state would need a file
  fallback anyway.
- Transport only, no reduction. Rejected because: it leaves the seed's
  "manage state better" half unrealized — the store's contention is amplified
  by signal-rate reads and polls that a push path makes unnecessary.

**Chosen because:** the honest availability boundary — the platform channel is
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

### D-16: Signal vs record — upward signals carry no record, push-first, healing-sweep-backed  (R, supersedes D-2)

**Decision:** An upward signal (worker→tower) is the harness's one-shot
idle notice (D-20), whose status line is instruction text and never a
record; the store row is the authoritative content, written before the
worker stops. Downward deliveries (steer, decision
answers) are instructions addressed to a session, not signals: they carry
their text, and for a decision answer the persisted answer artifact (D-9) is
the recovery source, never a second record. The level-triggered healing
sweep is retained at every discipline value, demoted where push is live to
one documented cadence (`messaging_heal_cadence_seconds`, shipped default
300, overlay-resolved, validated at or below the attention watcher's
default liveness max-age) shared by every demoted consumer, the watcher's
deep-reconcile count recomputed as
`reconcile_every = max(1, round(300 / cadence))` so its wall-clock period
is at least today's and within one demoted interval of it; the demotion
is tower-facing only — operator-facing cadences keep today's intervals,
nothing pushing to the human (REQ-E1.1). This generalizes
the push-first, sweep-backed pattern fleet-autonomy D-1 established and
its worktree tracker (fleet-autonomy D-7) applied on the push side.
*(Amended at revision 2026-09-02: the cadence knob and its default named.)*
*(Amended at kickoff 2026-09-02 (resumed): terminology only.)*
*(Amended at kickoff 2026-09-04 (resumed): the upward signal is the idle
notice, not a doorbell.)*
*(Amended at kickoff 2026-09-07 (resumed): the cadence bound and the
tower-facing scope; at the terminal lens pass, the deep-reconcile
recompute and its preservation bound.)*

**Alternatives considered:**
- Full payload in every upward message. Rejected because: a dropped or held
  message then loses content, and the message becomes a second copy of the
  record that can diverge from the store.
- Pointer-only in both directions (a decision answer delivered as "fork X is
  answered; read the artifact"). Rejected because: today's attributed steer
  delivery carries the answer text, and a pointer would add a worker-side
  file read to every answer for no loss-tolerance gain the persisted
  artifact does not already give.

**Chosen because:** upward notices are loss-tolerant by construction — a
lost signal costs latency, never correctness — and the store remains the
single source of truth; downward text is what a session acts on, with the
artifact behind it.

### D-3: Fallback ladder — messaging-first on every steer-advertising rung, existing mechanism as fallback  (N)

**Decision:** Tower→worker steer and decision-answer delivery prefer
messaging on every rung that advertises steer-in-flight and is eligible
(D-17), `tmux` included. The fallback ladder is messaging → the rung's
existing attributed steer delivery (`tmux` buffer-paste; the backend's
equivalent elsewhere) → operator handoff (today's undelivered-answer
surfacing). A rung whose contract row lacks steer-in-flight
(`headless-oneshot`: no pend path, ambiguity routes to the queue) receives
no downward delivery. On `stream-json-persistent` a decision answer is a
control response the supervisor writes (`fleet-streamjson.sh answer`),
never a message: the worker is blocked on a pending control request that
only that path resolves, and answering it by message would close the fork
over a pend that never clears; `fleet-decision.sh answer` refuses that rung
with a diagnostic naming the supervisor verb, and the tower obtains the
request id the verb needs from `fleet-streamjson.sh status <worker>`, the
`decide` row carrying only a truncated prefix in its question text. The
fork is still claimed under the fleet lock and its answer artifact still
persisted before the control response is written, so D-9's ordering and the
answered-undelivered surfacing hold on that rung too. Messaging carries
free-text
steers only on that rung, and their fallback is operator handoff, no
attributed steer delivery existing there today.
*(Amended at revision 2026-09-02: rung set pinned to steer-advertising
rungs; the contract row is not flipped.)*
*(Amended at kickoff 2026-09-02 (resumed): title terminology only.)*
*(Amended at kickoff 2026-09-07 (resumed): the `stream-json-persistent`
carve-out, its request-id source, and the claim-and-persist ordering it
keeps.)*

**Alternatives considered:**
- Paste-first on `tmux`, messaging only elsewhere. Rejected because: it keeps
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
`script` < `tiered` < `open`, shipped default `tiered`, resolved through
the standard overlay layers, plus the switch value `off` outside the
ladder: it makes the probe read absent, so every consumer takes the
messaging-absent path (REQ-A1.5) — the per-fleet kill switch, one knob
away, touching no harness setting; at `off` no model-composed message is
sent in any direction either, `effective-mode`'s refusal being the
oracle's "do not send", and an unknown value reads absent the same way;
the offsets below apply to the three
ladder values only. The knob value names the worker→tower value;
tower→worker resolves one value stricter. The *effective* value is evaluated
at send time by deterministic script logic reading the existing usage gate
(`fleet-usage-gate.sh`, whose rung is derived from the audit trail):
pressure means a rung at or above `reduce-concurrency`, read the same way in
every direction, and it steps the effective value down one; clearing
restores it. The context-budget monitor is not a pressure input: it is a
tower-only context-handoff trigger with three states (`near-limit`, `ok`,
`disabled`), none of which is a fleet pressure signal. Three directions
carry an offset: worker→tower at the knob value (offset zero; the anchor —
no shipped path carries worker→tower traffic, D-20, so it constrains only an
operator-prompted model-composed send), tower→worker one value stricter,
tower↔tower advisory at the knob value (offset zero — towers are the
interrupt-absorbing side). Both offsets saturate at
`script`, so the composition is
`effective = max(script, knob − direction offset − pressure demotion)` and
their order is immaterial. The ladder gates model-composed traffic only;
deterministic script sends (script-posted answers and steers downward) and
the harness's idle notices ride at every value. Every send that runs
demoted writes
one stderr notice; no stored discipline state, no daemon flip, no LLM in the
decision. The recorded trade: each idle notice that reaches the tower costs one
tower model turn (D-1), so at `script` under maximum pressure the
reduction has exchanged cheap tower polls for per-stop tower turns; that
is accepted because notices arrive once per worker stop, not at the poll
rate, and the healing sweep bounds the loss if a tower holds them.
*(Amended at revision 2026-09-02: direction anchoring, saturating floor,
order-free composition, per-send logging, and the pressure signal stated,
from the kickoff §2–3 intent.)*
*(Amended at kickoff 2026-09-02 (resumed): the third direction, the
notice's destination, the monitor's states, and the tower-turn trade
recorded; the derived-state precedent re-cited.)*
*(Amended at kickoff 2026-09-04 (resumed): the floor value renamed to
`script`; the trade restated for idle notices.)*
*(Amended at kickoff 2026-09-07 (resumed): the `off` switch value; at the
terminal lens pass, `off` stops model-composed sends in every direction
and an unknown value reads absent.)*

**Alternatives considered:**
- A fixed `tiered` rule for everyone. Rejected because: the operator's desired
  posture is a style value, not a general law — the capability (a discipline
  ladder) belongs in core, the chosen value in an overlay
  (the customization-boundary doctrine).
- A fixed `open` rule. Rejected because: token cost and interrupt noise scale
  with fleet size and nothing planwright-side would bound them.
- A stored effective-value file flipped by a daemon. Rejected because: stores
  derived state (the no-replacement-cache lesson, invariant-tasks D-12, on
  the derived-projection principle of orchestration-concurrency D-1) and
  adds a writer; send-time evaluation is level-triggered and cannot go stale.
- A value below `script` that also stops script-posted answers and idle
  notices under pressure. Rejected because: those are the cheapest signals
  there are, and a parked worker must still receive its answer.

**Chosen because:** it dissolves the capability-vs-style tension per the
customization boundary, protects workers (the focus-bearing side) more than
towers (the interrupt-absorbing side), and degrades autonomously under
measured pressure instead of relying on operator vigilance.

### D-5: Cross-machine — opt-in knob plus per-send operator approval, never a default  (N)

**Decision:** Same-machine messaging is the default and the only unattended
posture. A cross-machine send is gated by the harness's own approval
prompt: both shipped settings profiles carry `isolatePeerMachines: true`
(a `true` from any scope wins, even in bypass mode), so every
model-composed cross-machine send prompts the operator. Only a
model-composed send can be cross-machine: script paths post to a local
inbox socket path and are same-machine by construction, and no planwright
script carries the cross-machine path, so planwright enforces nothing on it
itself. The opt-in config knob `messaging_cross_machine` (default off) is
the documented operator cue: turning it on is the recorded decision to
relax that setting for a fleet. Nothing leaves the machine silently. Remote
sessions are not fleet peers: presence, liveness, and dispatch stay
single-host.
*(Amended at revision 2026-09-02: scoped to model-composed sends; the
knob-to-setting relation stated.)*
*(Amended at kickoff 2026-09-02 (resumed): the enforcement point is the
harness setting; the knob named and stated as a cue only.)*

**Alternatives considered:**
- Out of scope entirely. Rejected because: the operator explicitly wants a
  deliberate path to reach off-host sessions (a cloud session, another
  machine) without waiting for a follow-on spec.
- Full cross-machine fleet peering. Rejected because: host-local death
  evidence and presence cannot classify a remote peer, and off-host
  messages transit third-party infrastructure — amending the signed
  single-host coordination floor is not this bundle's business.

**Chosen because:** availability without silent egress — the harness's own
approval gate, with the knob as the recorded cue, makes every off-host send
a conscious act.

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

**Decision:** Messaging reach has two parts. *Messaging eligibility* is a
fact about the rung, derived from the backend capability contract's
existing `Session-grade` column: `yes` rungs launched non-`--bare` (the
launch pin, execution-backends D-12) can bind an inbox socket — interactive
and `-p` sessions alike; only a `--bare` session binds none — `no` and
`deferred` rungs cannot, and an unknown or malformed value reads as
ineligible. It is distinct from the contract's *dispatch* eligibility (the
candidate rung set the ladder selects from), though both read the same
column. No column is added to the contract table and the adapter line
grammar keeps its arity; the contract doc gains only the derivation rule,
and the per-session probe is defined in the messaging-transport doctrine
(D-13). *Availability* is a fact about a session, read by a deterministic
probe run inside that session: `CLAUDE_CODE_MESSAGING_SOCKET` set and
naming an existing socket owned by the invoking user, plus the CLI version
compared numerically against the documented minimum, the stricter 2.1.248
unconditionally (D-11), plus the session's effective `crossSessionInbound`
resolving to `accept` from the CLI's settings files or from the
`PLANWRIGHT_MESSAGING_INBOUND` layer a fleet launch seam exports beside
its `--settings` profile. A send is
possible when the sending session's probe reads available and the target
worker has a recorded inbox socket basename (D-8). Consumers key on the
derived eligibility
and the probe, never on backend names.
*(Amended at kickoff 2026-09-02 (resumed): the non-`--bare` conjunct, the
distinction from dispatch eligibility, the probe's predicate, and the probe
definition's home stated.)*
*(Amended at kickoff 2026-09-07 (resumed): the inbound-acceptance
conjunct.)*

**Alternatives considered:**
- A new messaging contract column and a 9-field adapter grammar (the
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

### D-7: Deterministic doorbells — worker-side scripts post to the tower's inbox socket, content untrusted  (N)

**Decision:** Routine upward signals are posted by deterministic script
verbs writing one grammar-validated line to the tower's inbox socket —
no worker-model turn on the routine path. Because the socket accepts
connections from any same-OS-user process, doorbell content is untrusted:
the tower session receives it as a message, and its only sanctioned action
is the deterministic store re-read verb (`fleet-messaging.sh doorbell-read`,
D-12), which validates the pointer as data and returns store truth (D-16);
receivers grammar-screen, length-bound, and echo-sanitize before any use.
The posting verbs are the attention store's own write verbs
(`fleet-attention.sh heartbeat`, `decide`, `fork`, `park`) delegating to
`fleet-messaging.sh doorbell`; no harness hook entry is added. Send
visibility goes to stderr — captured by whatever launched the poster (the
dispatch seam's stderr capture, the harness's hook output) — never to the
audit trail (obs:2bea1358) and never to a per-worker file. The tower's
inbox socket path reaches a worker deterministically: the dispatch seam
sets `PLANWRIGHT_TOWER_INBOX_SOCKET` in the worker's launch environment
(the `fleet-dispatch-env.sh` precedent), obtaining the value from
`fleet-messaging.sh self-socket`, the single reader of the tower's own
`CLAUDE_CODE_MESSAGING_SOCKET`; the tower marker record every tower writes
at `/orchestrate` step start (D-8) is the fallback read — keyed by the
spec half of `PLANWRIGHT_WORKER_SCOPE`; a meta-tower is never a doorbell
target — and the caller validates the path through `fleet-messaging.sh`'s
owner predicate before any post (an existing socket whose owner is the
invoking user), so a missing or invalid path degrades the doorbell to the
healing sweep with one stderr notice and no retry.
*(Amended at revision 2026-09-02: the receiver named, the re-read bound to
a script verb, the socket path propagation mechanism stated, the
write-amplification evidence cited.)*
*(Amended at kickoff 2026-09-02 (resumed): the posting verbs, the stderr
destination, the dispatch variable and its source, the marker's writer and
lookup key, and the predicate's home stated.)*

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

**Chosen because:** script verbs posting one line are cheap, auditable, and
LLM-free; untrusted-content-plus-store-re-read makes spoofing a latency
nuisance rather than a correctness attack.

**Superseded-by: D-20** (2026-09-04, resumed kickoff) — the platform
experiments (brief §8) showed the harness's idle notice reaches the tower
within a second of a worker stopping, with its closing line, and that a
script post observes nothing but write success; the worker-side doorbell
bought only mid-turn rows at the cost of socket propagation, a spoofable
surface, and a tower turn per signal.

### D-8: Identity — deterministic session names from the handle grammar, self-registered and recorded  (N)

**Decision:** Every fleet-launched session is named at launch via `--name`
using the per-backend fleet handle grammar `orchestrate-relay.sh` owns
(`validate-handle`); the actual name is recorded by the session itself.
Its SessionStart hook runs `fleet-messaging.sh self-register`, which reads
the session's own per-session record (`~/.claude/sessions/$CLAUDE_PID.json`,
an undocumented surface the drift guard freezes, D-11; `CLAUDE_PID` is
exported to the session's tools and hooks) and, for a worker, amends its
registry row's two added columns `name` and `inbox` (the socket basename;
both written as the store's `-` sentinel at registration and filled by
the hook through a new `fleet-state.sh amend` verb, reached via
`fleet-register.sh`'s per-field degrade and taken under the fleet lock like
every registry write; the scripts that parse the registry file, re-derived
by grep at Task 4 (today `fleet-status.sh`), plus the readers this bundle
adds, tolerate rows of three, seven, and nine columns). For a tower
`self-register` writes nothing: the `--watch` loop records the
tower marker's one added field (`--name`) at loop start, with the name a
new `fleet-messaging.sh self-name` verb reads from that same session
record, cleared with the
marker on graceful exit (a single-step tower writes no marker and is
addressed by listing; a tower's socket path is never recorded, nothing
posting to a tower by script). No seam reads anything back and no retry
window exists: a worker whose hook never runs keeps the sentinels, is
unaddressable (downward delivery falls back), and is never subscribed.
Neither value carries a path separator, so the registry's field grammar
stays as it is; the socket directory is the tower's own socket's
directory, one user on one machine. The worker dispatch seams export the
worker identity environment on every session-grade rung, today only the
`headless-oneshot` seam's doing (obs:fbb701bc), so the hooks that write
attention rows — and the registering hook — run for every worker.
Fleet-launched towers are the
watchdog's `tmux` relaunches, the
continue-as-new handover, and any meta-tower subordinate launched on a
session-grade rung (a custom `PLANWRIGHT_TOWER_LAUNCHER` is out of
scope); a subordinate
hosted on `subagent` or `in-session` is not a messaging peer. An
operator-launched tower is not fleet-launched and is addressed by a listing
round-trip on the tower↔tower advisory path alone, whose rate is low enough
that the per-signal cost rejected below does not apply. Names are validated
as data before addressing, path use, or echo. The collision-rename behavior
is documented for interactive sessions and not stated for `-p --name`:
Task 4's live collision check records whichever outcome the CLI produces
(rename, refusal, or duplicate) into this decision's amendment note and the
task PR, `self-register` records that outcome, a refusal or duplicate
surfaces as
a dispatch failure rather than being assumed away, and a non-rename outcome
amends this decision.
*(Amended at revision 2026-09-02: the tower launch seams, the tower marker
as their record, the operator-launched carve-out, and the unverified
collision behavior stated.)*
*(Amended at kickoff 2026-09-02 (resumed): the worker-side record is a
registry basename field, the marker gains two fields with its writer and
readers named, every tower writes its marker at step start, tower naming
scoped to session-grade launches, the grammar's owner corrected, the
collision outcome recorded here.)*
*(Amended at kickoff 2026-09-04 (resumed): the marker field is the name
only; no tower socket path is recorded; the registry gains the observed
name; the read-back source named.)*
*(Amended at kickoff 2026-09-07 (resumed): the record written by the
session's own SessionStart hook from its own record, no seam read-back;
the registry amend verb and the reader set re-derived with its three
arities; the marker at loop start, written by the loop from a new
`self-name` verb;
the identity environment exported at every worker seam; the handover
launch named; a custom launcher out of scope.)*

**Alternatives considered:**
- Relying on harness-generated names plus listing round-trips. Rejected
  because: non-deterministic addressing, and the listing is a bounded read
  the fleet would repeat per signal.
- Trusting the requested name without self-registration. Rejected because:
  collision renames make the requested name silently wrong — the
  identity-on-the-wire gap obs:d4d66281 recorded, in a new coat.

**Chosen because:** deterministic identity at the dispatch seam is what the
worker-identity observation (obs:d4d66281) asked for, and self-registration
from the session's own record makes the registry match observed reality.

### D-9: Decision-channel ordering — claim, persist, deliver, verify; never re-claim  (N)

**Decision:** Answering a fork keeps the store's first-answer-wins claim as
arbiter: claim under the fleet lock, persist the answer artifact, then
attempt delivery (messaging-first per D-3, as a script post to the worker's
inbox socket through D-12), then consume the outcome the post returns
synchronously — accepted, held, or refused, or a failed post — and descend
the fallback ladder on refused or a failed post. Held is surfaced as
unconfirmed (one stderr notice, no store row) and left queued (descending
on it would double-deliver); accepted is not proof of delivery. That the
post returns those outcomes is an unverified platform premise (D-12); where
it returns nothing, write success or failure is the only observed outcome.
Dropped and expired are unobservable on the connection, so the post carries
the tower's own inbox socket as its reply address: the harness's status
frames for that message (the binary reports held, refused, dropped, and
expired this way, correlated by message id) reach the tower's inbox and its
model as a notice; `send` mints the message id itself (a UUID), writes it
into the frame beside the reply address, posts no auth line, and prints it
on stdout for every post that was written, held included, and
`fleet-decision.sh`
records it in one metadata sibling of the answer artifact
(`<fleet-home>/attention/answers/<worker>.meta`, one line per fork instance
id — the attention store's fork discriminator —
`<instance>\t<message id>\t<epoch>`; a second fork for the same worker adds
a second record, and `redeliver` refuses an id whose fork is not the
artifact's current fork; never inside the
artifact, whose whole content the attributed steer delivery carries into
the worker), so a
frame names a fork; on a drop, expiry, or refused frame the tower's prose
runs
`fleet-decision.sh redeliver --message-id <id>` exactly once — it emits
the attributed steer delivery command only, never a second post, never a
re-claim — and the once-per-fork record is a `redelivered` mark in that
sibling (no new record class: the sibling rides the artifact's
lifecycle); a held frame runs the step's own first action instead, its
recovery being the answered-undelivered surfacing below. A frame received
mid-turn is handled after the step's own
work, never interleaved. Exit codes: 0 when the post was accepted or the
fallback delivery command was emitted (the script emits, the tower runs
it — the script cannot see the delivery land), 5 when held, 4 for the
terminal operator handoff, which keeps today's meaning (delivery not
completed after a successful claim) and both of today's sub-cases, the
artifact persisted and the artifact lost; today's 2 and 3 unchanged; the
relay's
messaging arm reports held the same way. An inbound status frame the
tower holds or never receives leaves the surfacing below as the recovery.
Whether the frames are
emitted for a raw post is unverified until
Task 2's wire step; where they are not, the worker stays parked, the tower's
healing sweep surfaces it as an undelivered answer for the operator handoff
(the attention view marks a parked worker whose fork carries a persisted
answer artifact as answered-undelivered), and no other re-delivery is
attempted. A failed delivery
never re-opens or re-claims the fork; the
persisted artifact is the recovery source.
*(Amended at revision 2026-09-02: the send bound to a script post with
synchronous outcomes; held surfaced only.)*
*(Amended at kickoff 2026-09-02 (resumed): the premise marked unverified;
the unobservable-outcome recovery stated as surface-only.)*
*(Amended at kickoff 2026-09-04 (resumed): the reply address and the
one-shot `redeliver` on a drop or expiry frame; surface-only kept as the
unverified-frame fallback.)*
*(Amended at kickoff 2026-09-07 (resumed): the message id minted by `send`
with no auth line, and the `redelivered` mark, in a per-fork metadata
sibling; the exit-code table with exit 4's kept meaning;
the mid-turn frame rule; the drop, expiry, refused, and held frame
cases.)*

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
  relaxes, so a fallback delivery duplicates it.
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
prose step immediately after the dispatch step, conditioned on the tower's
own probe reading available, and re-subscribes after every steer or answer
it delivers, unconditionally — a duplicate or expired prior subscription is
harmless, because a notice is only a supplement. Both sessions accept a
notice when the watched worker's rung is eligible and its shipped profile
carries `crossSessionInbound: accept`, and the subscribing tower's settings
carry the same key (the tower profile at fleet tower launches, the
operator's own settings otherwise). No daemon or script subscribes. They
supplement the completion path only:
positive-evidence-of-death liveness is unchanged, and the absence of a
notice is never read as a signal.
*(Amended at revision 2026-09-02: subscriber and re-arm policy stated.)*
*(Amended at kickoff 2026-09-02 (resumed): one unconditional re-subscribe
rule; "accept" defined.)*

**Alternatives considered:**
- Using idle notices as a liveness input. Rejected because: silence is never
  a signal — an expired or dropped subscription is indistinguishable from a
  busy worker, which is the exact conflation the death-evidence predicate
  exists to prevent.
- Subscribing once at dispatch and never re-arming. Rejected because: a
  worker that idles on a fork burns its one notice early, and its completion
  then reaches the tower by the healing sweep alone.
- Re-arming on every `--watch` iteration. Rejected because: it needs stored
  armed-state, which this bundle's posture rejects; re-subscribing on
  delivery needs none.

**Chosen because:** a notice is positive evidence of idle at zero token cost
in the watched session; treating it as anything more would re-open the
stuck-detector failure shape.

**Superseded-by: D-21** (2026-09-04, resumed kickoff) — the idle notice is
the upward push path, not a completion supplement, once worker-side
doorbells are retired (D-20).

### D-11: Platform-contract posture — pin, probe, fixture-test; drift fails visibly  (N)

**Decision:** The messaging contract surface this bundle consumes
(environment variables, socket line protocol, tool semantics, version
gates) is treated as a version-sensitive external contract with two
recorded versions. The **documented messaging minimum** (2.1.224; 2.1.248
on non-Anthropic providers or with feature-flag fetching off) is what the
probe compares against, numerically per dotted component — against the
stricter 2.1.248 unconditionally, with no provider detection, the
fail-safe reading. The **last-verified pin** (initially 2.1.259, the
highest version observed in a tower session) is held in the
drift guard's fixture, which freezes the contract assumptions
(`CLAUDE_CODE_MESSAGING_SOCKET` and `CLAUDE_CODE_MESSAGING_TOKEN`, the
post's line framing and whatever response Task 2 observes, D-12, the
reply-address field and the status frames it draws, D-9, the
rendered shape of the idle-notice line the tower's prose reads the session
name from, D-21, and the per-session record `~/.claude/sessions/<pid>.json`
`self-register` consumes, D-8 — the last two undocumented — plus six
behaviors Task 2's wire step records before any task relies on them:
whether `crossSessionInbound: hold` or `refuse` gates an idle notice,
what a second `notify_when_idle` on a live subscription does, whether
`--name` applies beside `--worktree --tmux=classic`, whether `CLAUDE_PID`
reaches a SessionStart hook's environment, in which session types the
harness's scheduled wakeup is available, and whether a held message is
released when the receiver relaxes to `accept` — each with a stated
observable:
the transcript line, the hook's captured environment, a turn started
at the requested instant, or the delivery a relaxed receiver shows; the
wakeup and held-release arms record whichever outcome the CLI produces,
both outcomes passing); every
platform-touching task re-verifies
against the running CLI, records the observed version in its PR, and raises
the pin, never lowers it — a running CLI below the pin halts the task (the
version-pin-and-re-verify precedent, execution-backends D-4; the sibling
launch pin is D-12). Runtime behavior goes through the deterministic probe
(D-17), and parsing is fixture-tested so a repo-side change fails a visible
test, while the platform moving is caught by the live re-verification. The
test-only seams the fixtures need (`probe --cli-version`, the predicate's
`--owner-uid` and `--socket-type`, `PLANWRIGHT_MESSAGING_POST`) are
refused unless `PLANWRIGHT_TEST_SEAM=1` is set (REQ-H1.5), so a seam that
bypasses a validation cannot be reached in production by accident.
*(Amended at revision 2026-09-02: one pin of record replaces a per-task
record; it is also the probe's version threshold.)*
*(Amended at kickoff 2026-09-02 (resumed): the minimum and the
last-verified pin split with initial values and the raise-only rule; the
frozen assumptions named; the test-seam guard; the precedent labels
corrected.)*
*(Amended at kickoff 2026-09-07 (resumed): the wire-step behaviors and
their observables added, six of them with the held-release arm and its two
admissible outcomes; the initial pin's basis restated as a tower-session
observation.)*

**Alternatives considered:**
- Trusting documented behavior without per-version verification. Rejected
  because: the WorktreeCreate incident (obs:16facd5b) shows a mis-assumed
  hook contract silently no-op'ing a core mechanism fleet-wide.

**Chosen because:** planwright already learned this lesson twice (the
non-`--bare` launch pin, execution-backends D-12; the hook-contract
correction, obs:16facd5b); paying the pin-and-probe cost up front is
cheaper than a silent fleet-wide outage.

### D-12: One enforcement point — `fleet-messaging.sh`; relay and decision channel delegate  (N)

**Decision:** A single audited script owns the messaging mechanics —
`probe`, `eligible`, `effective-mode`, `send`, `notice-read`,
`self-register`, `self-name`, and the socket owner/existence predicate —
mirroring the
relay's one-audited-place pattern (`effective-mode` keeps its name although
the ladder's levels are "values": it is the verb's name, not the
concept's). The signatures: `probe` (test seam `--cli-version`);
`eligible <rung> --launch <bare|normal>` reads
`orchestrate-backends.sh caps` and applies the D-17 derivation;
`effective-mode --direction <worker-to-tower | tower-to-worker |
tower-to-tower>` (the oracle covers all three; only tower→worker is a
script-carried path — upward traffic is the harness's idle notice, D-20,
and the tower↔tower advisory is model-composed, D-14); `send --to <socket
path> | --to-worker <handle> --message-file <path>` reads the body from
the file and posts it as data, never interpolated into a command string,
where `--to-worker` names the registry's `worker` field (never the relay's
per-backend handle, which only the fallback step uses) and resolves its
`inbox` column's basename against the invoking session's own socket
directory
(this script is the single reader of `CLAUDE_CODE_MESSAGING_SOCKET`);
`send` mints the message id itself (a UUID), writes it into the frame
beside the reply address, posts no auth line
(`CLAUDE_CODE_MESSAGING_TOKEN` is frozen as a drift assumption only), and
prints the id on stdout for every post that was written, held included;
`notice-read <session name>` takes the
name the tower's prose reads from an idle notice, screens it as data
(printable ASCII, no path separator, at most 128 bytes — planwright's own
screen, a different, path-safe one from `validate-handle`'s handle grammar
rather than a stricter one), matches it against the registry's `name`
column, and
delegates to `fleet-attention.sh render --worker <handle>` (a
worker-selecting arity this bundle adds to `render`) for that row; the
predicate verb (test seams `--owner-uid`, `--socket-type`), which `send`
applies to its target socket. `send` returns the outcome the post yields
synchronously. Send visibility goes to stderr, never to the fleet audit
trail (obs:2bea1358). `send` writes the invoking session's own inbox
socket into the message frame as its reply address, so the harness's
status frames for that message come back to the tower (D-9); `fleet-decision.sh
redeliver --message-id <id>` is the one re-delivery verb, emitting the
attributed steer delivery command for a persisted answer whose metadata
sibling carries that id (Task 5). `self-register` reads the invoking
session's own per-session record and, for a worker, records its name and
socket basename
(D-8); it runs from the SessionStart hook, never from a seam, and writes
nothing for a tower. `self-name` prints the session's observed name from
that same record and exits non-zero when the record is absent or carries
no name; `self-register` calls it, and so does the `--watch` loop when it
records the tower marker. Every settings and session-record read on these
paths is awk-based, with no jq and no eval (REQ-K1.5);
`crossSessionInbound` is a top-level settings key, and a parse failure
reads absent. **The wire
contract is an unverified platform
premise:** the
docs state no request-line format and no response line for a raw socket
post, so Task 2's first step verifies both against the running CLI and
freezes what it observes in the drift guard; where the post returns
nothing, write success or failure is the only observed outcome (REQ-C1.5).
The post itself sits behind one test-only seam, `PLANWRIGHT_MESSAGING_POST`
(guarded per REQ-H1.5), because the CI toolchain binds no socket; its
contract: the variable names an executable invoked with the real post's
argv and the body on stdin, which appends one record per call (argv and
body) to `$PLANWRIGHT_MESSAGING_POST_LOG`, prints the outcome line on
stdout or nothing, and exits with the write result — so a fixture reads
call counts and payloads from the log, and an empty stdout exercises the
write-success fallback. `orchestrate-relay.sh` gains a messaging arm and
`fleet-decision.sh` delivers through it by delegation — both scripts
*perform* the messaging post in-process (their headers and
`fleet-decision.sh`'s exit-code table change accordingly, Task 5) and keep
their print-the-command contract for the fallback step; neither grows
parallel messaging code. The single-enforcement audit is literal: no file
matching `scripts/*.sh` other than this one contains the
`CLAUDE_CODE_MESSAGING_SOCKET` name, and this script's own `claude`
invocations are exactly one, the probe's version read. Discipline is not
enforced here — the ladder gates
model-composed traffic, which never passes through this script — so
`effective-mode` is the oracle the sending prose consults.
*(Amended at revision 2026-09-02: the subcommand set and the script-post
shape stated.)*
*(Amended at kickoff 2026-09-02 (resumed): the signatures, the unverified
wire contract, the post seam, the actor contract change, the literal
audit, and the oracle role stated.)*
*(Amended at kickoff 2026-09-04 (resumed): `notice-read` replaces the
doorbell verbs and `self-socket`; the doorbell tag leaves the audit;
`send --to-worker` and the name grammar added; the stderr rule carried
over from D-7.)*
*(Amended at kickoff 2026-09-07 (resumed): `redeliver --message-id`;
`self-register` and `self-name` added, with the tower arm writing nothing;
the message id minted by `send` and no auth line posted; the awk parse
rule and the top-level settings key; the name screen restated as
planwright's own.)*

**Alternatives considered:**
- Inline messaging logic in each consumer. Rejected because: re-derives
  validation and fallback logic per caller — the exact scatter the relay
  script was created to end.

**Chosen because:** the security-critical properties (validation, data-only
handling) live in one testable place.

### D-13: Doctrine home — a new messaging-transport doctrine  (N)

**Decision:** The durable rule — messages are ephemeral signals, files/git
are the record; every messaging path names and reaches its deterministic
fallback; push-first, healing-sweep-backed; discipline is laddered and
pressure-demoted — ships as its own doctrine document,
`doctrine/messaging-transport.md`, cited by the skills that apply it through
their `Doctrine:` manifest lines (`/orchestrate` for the tower side,
`/execute-task` for the worker side) and by the scripts in their headers.
It also carries: the per-path fallback table (REQ-G1.1) over the fixed path
set — tower→worker steer, decision answer, the worker→tower idle notice,
the tower's own wake (fallback: today's metronome, REQ-D1.8), the two
poll cadences (the attention watcher's healing sweep, which demotes, and
the dashboard's projection refresh, which does not, REQ-E1.1),
tower↔tower advisory — which Task 1 gates
against and Tasks 7 and 8 each re-verify when they land; the per-session
probe definition (D-17); the cross-machine transit note (REQ-H1.2); one
sentence distinguishing the healing sweep from
`/orchestrate`'s reconcile sweep and from `fleet-attention-watch.sh
reconcile`; and a short glossary of the three ladders (fallback,
discipline, the usage gate's rungs) and their step nouns; and the
fleet-runtime version rule (mixed CLI versions across a fleet are fine:
the probe is per session and fail-safe, D-17) — plus the
declaration that messaging acquires no resource class beyond the one class
it adds to the fleet-coordination-floor doctrine's lifecycle-closure
contract (REQ-G1.6: the inbox socket, harness-owned, closed with the
session, detector: the session's own death evidence — one row in the class
contract table and one column in the rungs-by-classes table, every cell
filled). The
fleet-coordination-floor doctrine is amended by exactly that one class. The
inter-orchestrator-coordination doctrine is amended in the same delivery
(REQ-G1.7): it pins attributed buffer-paste as the steer-in-flight mechanism
of record (section heading included), names the relay as the one audited
script, describes `relay-command` as printing a paste command, and already
sanctions tower-to-tower paste between co-located towers — all of which
this bundle changes — so leaving it unamended would have two doctrine
documents contradicting each other.
*(Amended at revision 2026-09-02: the doctrine's extra contents and the
inter-orchestrator-coordination amendment stated.)*
*(Amended at kickoff 2026-09-02 (resumed): the file name, the manifest
citations, the enumerated path set, the floor row, and the two further
amended sentences stated.)*
*(Amended at kickoff 2026-09-07 (resumed): the wake path and its
fallback; the dashboard not demoted; the runtime version rule.)*

**Alternatives considered:**
- A sixth floor in the fleet-coordination-floor doctrine. Rejected because:
  that document's citations belong to three other signed bundles; amending
  it from here beyond the one class couples their lifecycles.
- No doctrine doc (rule stated only in this bundle). Rejected because:
  future skills would cite a spec bundle rather than doctrine, which is not
  how the other floors are consumed.

**Chosen because:** the backend-capability-contract precedent — a transport
contract earns its own citable doctrine document.

### D-14: Tower↔tower advisory — sanctioned, and never on the correctness path  (N)

**Decision:** Tower↔tower messages are sanctioned for the advisory layer
operators hand-relay today, or paste between co-located towers ("main
advanced", "I'm draining spec X"), under a hard rule: a message never
claims, releases, or resolves a unit of work.
Authority over the division of work stays exactly where the
fleet-coordination-floor doctrine's assume-multiplicity floor places it;
this bundle restates none of it. An advisory is composed and sent by the
tower's model through the harness's message tool, addressed by session
name — the marker name of a fleet-launched tower (D-8), a listing for an
operator-launched one; no script carries the path, and its fallback is
not-sent.
*(Amended at revision 2026-09-02: the restated authority list replaced by a
citation of the floor.)*
*(Amended at kickoff 2026-09-02 (resumed): the status quo named as
hand-relay or co-located paste.)*
*(Amended at kickoff 2026-09-04 (resumed): the advisory stated as
model-composed with its fallback.)*

**Alternatives considered:**
- Out of scope until `concurrent-orchestrator-coordination` executes.
  Rejected because: the advisory layer touches nothing that bundle owns,
  and the relay burden is a present cost.
- Advisory plus coordination semantics. Rejected because: it would put a
  lossy channel on the correctness path and reopen a signed design.

**Chosen because:** it replaces exactly the manual relay burden while
leaving every authoritative surface untouched.

### D-15: Doorbell wire grammar — one bounded ASCII line, five fields, receiver uses only the worker id  (R)

**Decision:** A doorbell is exactly one line: `<tag> <version> <kind>
<worker> <instance>`, space-separated, printable ASCII only, the whole line
bounded at 256 bytes with no control bytes. `<tag>` is the fixed protocol
tag (`planwright-doorbell`), `<version>` the grammar version (`1`),
`<kind>` one of `attention`, `fork`, `park` (completion rides the idle
notice, REQ-D1.3, and has no doorbell kind), `<worker>` is in the
per-backend fleet handle grammar `orchestrate-relay.sh` owns
(`validate-handle`), and `<instance>` is the fork instance id (the
attention store's fork discriminator) for `fork`, and the literal `-` for
the other kinds. The producer (`fleet-messaging.sh doorbell`) validates
`<worker>` against the backend it is posting for and refuses to emit
anything else; the receiver verb (`doorbell-read`), which carries no
backend, screens `<worker>` against the union charset of the per-backend
grammars, uses only `<worker>` — to select the store row it re-reads,
which is where the value is re-validated — and never echoes an unvalidated
field. Any line failing the grammar is refused with a sanitized diagnostic
and drives nothing.
*(Amended at kickoff 2026-09-02 (resumed): the `complete` kind dropped;
`<instance>` defined per kind; the grammar's owner corrected; the
receiver-side screening stated.)*

**Alternatives considered:**
- A structured (JSON) payload. Rejected because: it invites content the
  pointer-only rule (D-16) forbids, needs a parser on a socket any same-user
  process can write to, and buys nothing the five fields do not.
- Free-text with a worker id somewhere in it. Rejected because: an
  unanchored grammar cannot be length-bounded or screened by shape, which is
  the whole defense the untrusted-socket posture (D-7) rests on.

**Chosen because:** a fixed-arity line is the cheapest thing a doorbell
caller can emit and the easiest thing a receiver can refuse; the producer
and receiver share one definition, so Task 2 and Task 6 cannot drift apart.

**Superseded-by: D-20** (2026-09-04, resumed kickoff) — no planwright
doorbell is posted; the upward wire is the harness's own idle notice, whose
shape planwright parses but does not define. No replacement grammar.

### D-18: Inbound acceptance wiring — the messaging settings ride the verified interim pattern until the owned delivery mechanism lands  (R)

**Decision:** Worker inbound acceptance (`crossSessionInbound: accept`) and
tower acceptance are settings content this bundle owns; the mechanism that
delivers a settings profile to a dispatched worker is owned by the
`worker-permission-ergonomics` amendment (its pending note). Until that
lands, the messaging settings are wired through the pattern obs:58aa232e
verified end to end — `.claude/settings.local.json` at the checkout root,
gated on the dispatch env so interactive sessions see a no-op — because
`--settings`-file hooks do not register in `-p` sessions while its
permission keys do apply. Delivery is part of the dispatch seam and fails
visibly, never silently (obs:eea622de). When the owned mechanism lands,
Task 3's wiring migrates onto it without changing the settings content.

**Alternatives considered:**
- Owning general profile delivery here. Rejected because: the pending note
  already routes that work to `worker-permission-ergonomics`, whose guard
  the profile carries; two bundles claiming one seam is the drift the
  observation log exists to prevent.
- Waiting for the amendment before wiring anything. Rejected because: the
  messaging settings are one key, the interim pattern is verified, and
  blocking downward delivery on another bundle's schedule buys nothing.

**Chosen because:** it separates what this bundle owns (the settings
content and its visible-failure delivery obligation) from what a sibling
owns (the delivery mechanism), with a verified interim path and a named
migration.

**Superseded-by: D-19** (2026-09-03, resumed kickoff) — the rationale
inverted obs:58aa232e: that observation found `--settings`-file *hooks*
fail to register in `-p` sessions while its permission-class keys do
apply, and the platform documents `crossSessionInbound: accept` as
deliverable through a `-p` session's `--settings` value; the
`settings.local.json` workaround is a hook-only pattern this bundle does
not need.

### D-19: Inbound acceptance wiring — the messaging keys ride the shipped profiles via `--settings`; the general delivery mechanism stays with its owner  (R2, supersedes D-18)

**Decision:** Worker inbound acceptance (`crossSessionInbound: accept`),
tower acceptance, and `isolatePeerMachines: true` are settings keys this
bundle owns, carried in the two shipped profiles
(`config/worker-settings.json`, `config/tower-settings.json`). The worker
dispatch seams pass the worker profile with `--settings` at every
session-grade launch, and the fleet tower-launch seams (the watchdog's
relaunch, a meta-tower subordinate on a session-grade rung) pass the tower
profile the same way; an operator-launched tower carries the tower profile
through the operator's own settings scope, as `docs/fleet.md`'s bring-up
already describes. This is the route the platform documents for a `-p`
worker taking messages unattended, and the one obs:58aa232e observed
applying for permission-class keys (only hook definitions fail to register
that way); the interactive `tmux` rung's `--settings` behavior is
unverified, and Task 4's live check is its verification. No guard is
re-scoped for the script seams: each seam builds its own launch line after
validating any
caller-supplied extras, so `fleet-dispatch-worktree.sh`'s launch-argument
pin never sees the profile flag, and the tower command-guard
auto-approves planwright's own scripts wholesale, so it never sees the
launch either. The meta-tower's subordinate and the continue-as-new
handover are prose launches today, and the tower command-guard defers any
`--settings` it sees in a Bash string, so both move behind
`scripts/fleet-tower-launch.sh` (Task 4, the same shape as
`fleet-dispatch-worktree.sh`): it passes the tower profile with
`--settings`, exports `PLANWRIGHT_MESSAGING_INBOUND=accept`, and is
approved wholesale like every other planwright script.
The seam exports `PLANWRIGHT_MESSAGING_INBOUND=accept`
beside the profile it passes, the layer the probe reads for a `--settings`
launch (D-17). The profiles' own guard hooks stay dead under `--settings`
until `worker-permission-ergonomics` lands (obs:a4a4fa59); the messaging
keys apply regardless, and both profile headers say so — the worker
profile's `_about` and the tower profile's, each rewritten for the routes
that profile now takes, with the same dead-hook note and
`check:hook-contracts` still
passing. Delivery is part of the dispatch seam and fails visibly, never
silently (obs:eea622de): a seam that cannot pass the profile exits
non-zero naming it. The fleet tower launches that pass the tower profile
are the watchdog's relaunch, the meta-tower's subordinate, and the
continue-as-new handover. The general
profile-delivery mechanism (a `worker_settings` knob appended to the attach
plan, per the `worker-permission-ergonomics` pending note) stays with that
bundle; when it lands, Task 4's wiring migrates onto it without changing
the settings content.
*(Amended at kickoff 2026-09-07 (resumed): the guard re-scopes dropped
as unnecessary for the script seams, with the two prose launches moved
behind `fleet-tower-launch.sh`; the exported inbound layer; the handover
launch; both profile headers and `check:hook-contracts`; the migration
named as Task 4's.)*

**Alternatives considered:**
- The `.claude/settings.local.json` + env-gate pattern (the D-18 shape).
  Rejected because: it is the workaround for hooks that `--settings` cannot
  register, and none of this bundle's settings are hooks; it would also
  write into every checkout root for a key `--settings` already carries.
- Owning general profile delivery here. Rejected because: the pending note
  already routes that work to `worker-permission-ergonomics`; two bundles
  claiming one seam is the drift the observation log exists to prevent.
- Waiting for the amendment before wiring anything. Rejected because: the
  messaging settings are three keys, the `--settings` route is documented
  and observed, and blocking downward delivery on another bundle's schedule
  buys nothing.

**Chosen because:** it uses the route the platform documents for exactly
this key, keeps the profile files as the single home of the settings
content, touches no guard, and leaves the delivery mechanism with the
bundle that owns it.

### D-20: Upward signalling — the harness's idle notice is the push path; the sweep heals; no worker-side post  (R3, supersedes D-7, D-15)

**Decision:** A worker never posts to the tower. When a worker stops — it
parks on a fork, parks for attention, or completes — its turn ends and the
harness's one-shot idle notice, which the tower subscribed to at dispatch,
is enqueued at the tower within about a second carrying the worker's
closing line (observed: brief §8, E3) and reaches the tower's model at its
next turn boundary (D-21) — or wakes it, when the tower is idle between
event-driven steps (D-22). Only a stop that ends the worker's turn fires
a notice: a fork or park at which the worker halts awaiting a decision,
or completion; a mid-turn suspension (a permission or elicitation dialog,
obs:4c25e743) ends no turn and is the sweep's case, surfacing there as a
stale heartbeat past the watcher's liveness max-age and never as an
attention row. Whether the notice
fires before a `headless-oneshot` worker's process exits is unverified:
Task 6's live check records the outcome, the sweep carries the case
either way; on that rung the notice duplicates the completion record the
runner already writes, and the subscription stays (one rule for every
worker) because it costs the worker nothing.
Attention rows written while a worker is still
running reach the tower on the retained healing sweep. Workers therefore
learn no tower socket path, no planwright-defined upward wire grammar
exists, and
`fleet-attention.sh`'s write verbs are unchanged. The inbox socket a worker
binds serves the downward direction only (D-3).
*(Amended at kickoff 2026-09-07 (resumed): the wake-on-idle sentence;
turn-ending stops only, with a mid-turn suspension surfacing as a stale
heartbeat; the Stop-hook alternative; one subscription rule
for every rung.)*

**Alternatives considered:**
- Worker-side doorbells posted by the store's write verbs (the D-7 shape).
  Rejected because: the experiments showed a script post observes only
  write success, so the doorbell's outcome handling was fiction; it needs
  the tower's socket path propagated to every worker with an owner check, a
  spoofable same-user surface with a re-read discipline to neutralize it,
  and a tower model turn per signal — all to gain mid-turn rows the sweep
  already carries.
- A tower-side watcher posting an own-child doorbell from the attention
  store's inotify branch. Rejected because: `inotifywait` and `fswatch` are
  absent on the kickoff host, so the branch degrades to polling — today's
  cadence, not push — and a watcher process is a new tower-side lifecycle
  to close.
- Worker-model `SendMessage` for routine signals. Rejected because: a worker
  model turn per signal, and a deterministic event made to depend on model
  behavior.
- The worker's existing Stop hook as the push. Considered because: it
  already records the stop in the store deterministically at the same
  instant, with no subscription and no expiry. Not chosen because: the
  store row is where the fact lives either way; what the notice adds is
  waking the tower, which a hook can only do by posting to it — the
  worker-side post rejected above.

**Chosen because:** the mechanism was watched working end to end at the
kickoff, costs the worker nothing, adds no surface to secure, and leaves
the worker-side code untouched; what it does not carry, the sweep does.

### D-21: Idle notices — subscribe at dispatch, re-subscribe after every delivery, act only through the store re-read  (R3, supersedes D-10)

**Decision:** The subscriber is the tower session's main conversation. It
subscribes as an `/orchestrate` prose step immediately after the dispatch
step, conditioned on its own probe reading available, and re-subscribes
after every steer or answer it delivers, unconditional on any prior
subscription — a duplicate or expired one is harmless; the subscribe
step's probe condition still applies. Both sessions accept a notice when
the watched worker's rung is eligible and its shipped profile carries
`crossSessionInbound: accept`, and the subscribing tower's settings carry
the same key (the tower profile at fleet tower launches, the operator's own
settings otherwise). A notice's status line is untrusted instruction data:
the tower's only sanctioned action is `fleet-messaging.sh notice-read
<session name>` (D-12), which screens the quoted name the prose reads from
the notice, matches it against the registry's `name` column, and returns
store truth; the line itself is never acted on, and in `--watch` mode no
fleet read in that iteration precedes the re-read. The sanction is a
standing instruction the skill states once, so it persists in the
session after a step exits. No daemon or script subscribes. A notice is
enqueued at the tower
within about a second of the worker stopping but reaches the tower's model
at its next turn boundary (observed at the kickoff: a peer message is read
between tool calls, an idle notice at turn start), so a tower mid-turn sees
it when that turn ends; the sweep bounds the delay — and an event-driven
tower (D-22) is idle between steps, so the notice wakes it. The tower also
subscribes over the reconcile sweep's in-flight set at its start (a fresh
tower after a watchdog relaunch or a continue-as-new handover holds no
subscriptions; the demotion trigger otherwise fires with no live
subscriber); every subscription is addressed by the registry's recorded
`name` column, a worker with none is skipped, an ambiguous match is
refused, an
empty `notice-read` result is a no-op, and the re-read precedes any other
fleet read in every notice-driven turn. A single-step tower whose session
ends with the step subscribes to nothing. The sanction sentence rides the
continue-as-new handover seed; the in-flight set is never carried, the
subscribe pass deriving it from disk. Notices push
and never replace the sweep: positive-evidence-of-death liveness is
unchanged, and the absence of a notice is never read as a signal.
*(Amended at kickoff 2026-09-07 (resumed): the start-of-tower subscribe
pass, recorded-name addressing, the ambiguous and empty cases, the
ordering rule, the wake-on-idle sentence, the seed carrying the sanction
only.)*

**Alternatives considered:**
- Using idle notices as a liveness input. Rejected because: silence is never
  a signal — an expired or held subscription is indistinguishable from a
  busy worker, the exact conflation the death-evidence predicate exists to
  prevent.
- Subscribing once at dispatch and never re-subscribing. Rejected because: a
  worker that idles on a fork burns its one notice early, and its later stops
  reach the tower by the sweep alone.
- Acting on the status line directly. Rejected because: the line is composed
  by another session and delivered over a same-user surface; the store row
  is the only ground truth.

**Chosen because:** it keeps the one mechanism the experiments showed to be
prompt and cheap on a leash the fleet already holds — the store re-read —
and spends the tower turn a notice costs on exactly one deterministic verb.

### D-22: The tower is event-driven — the watch loop ends its turn per step and is woken by notices, messages, or a timer  (R4)

**Decision:** Where the tower's own probe reads available and its session
type survives a turn end (an interactive session — a `-p` tower, the
continue-as-new handover included, keeps today's metronome),
`/orchestrate --watch` no longer sleeps inside one long turn. Each step ends
the tower's turn; the harness wakes the tower for the next step on a
worker's idle notice (D-21), on a peer message (a status frame, D-9; an
advisory, D-14), or on the timer — the harness's scheduled wakeup requested
at step end, at the healing cadence where REQ-E1.1's demotion trigger holds
and at today's metronome interval otherwise, whose availability per session
type
Task 2 records before any task relies on it (D-11, either outcome
recorded). Where the wakeup is
unavailable, or a step ends with neither a live subscription nor an
available wakeup, the loop keeps today's metronome for that step (REQ-A1.5);
the subagent backend's existing event-driven arm stands. A notice-driven
turn runs `notice-read` first, a drop, expiry, or refused status-frame turn
`redeliver` first (a held frame taking the step's own first action), a
timer-driven turn the reconcile sweep first, an advisory turn the step's
own first action, all inside the step's own rules for dispatching,
claiming, and writing; where more than one wake source is pending the order
is `notice-read`, then `redeliver`, then the reconcile sweep, then the
step's own first action, and the start-of-tower subscribe pass precedes all
of them on a tower's first turn; a status frame read mid-turn is handled
after the
step's work. Selector exit 1 ends the turn awaiting a wake while a
subscription is live — the same recorded proxy REQ-E1.1's trigger reads,
at least one in-flight worker carrying a recorded `inbox` value — and ends
the watch otherwise. This is what makes the
store-load reduction real for the tower itself: it reads the store when
woken, not on a metronome. It amends bootstrap D-38's dispatch loop: the
pending note (Sources) names the `/spec-draft --extend bootstrap`
invocation that drafts the amendment for real, and Task 6's loop change
carries a Deferred gate until that amendment is signed off, so two signed
designs never contradict each other in flight. The smoke runner's
notice-wake step and duty-cycle figure (REQ-A1.7, D-23), REQ-D1.7's
notice-consumption criterion, and REQ-E1.1's loop-reads half ride that same
gate; before it the metronome tower acts on the park and those circuits
pass there. It is also the
reason the continue-as-new handover seed carries the sanction sentence
(and nothing else: the subscribe pass derives the in-flight set from disk).
*(Amended at kickoff 2026-09-07 (resumed): the timer's cadence made
conditional with either outcome recorded; the wake-source precedence
order; the status-frame arm split by frame kind; a live subscription
defined as REQ-E1.1's recorded proxy; the gated set named.)*

**Alternatives considered:**
- Keep the metronome and add a worker-side peer message from the Stop hook,
  found by name in the per-session record. Rejected because: it revives the
  worker-side post (a spoofable same-user surface, a tower turn per stop,
  the untrusted-content discipline) to work around the tower's own posture.
- Keep the metronome and start a tower-side helper that polls the store at
  today's cadence and posts an own-child message on change. Rejected
  because: a new tower-side process to close, and the helper polls exactly
  as the tower does today; the reduction would shrink to the model not
  reading the store.
- The fleet watchdog's tick as the timer, posting a wake line to the
  tower. Rejected because: the watchdog exits on an interactive marker, its
  tick is one recorded action, and it runs only where an operator scheduled
  it — the operator-launched `--watch` tower it would have to serve is the
  one it cannot.
- Keep the metronome as is. Rejected because: E3 showed a notice waits for
  the receiving turn to end, so a tower inside its loop is the one posture
  the push never reaches, and that is the posture the watchdog launches.

**Chosen because:** E4 observed both wake paths on this host — an idle
interactive session started a new turn within seconds of a message and,
separately, of an idle notice — so the harness already provides the
event loop; the tower only has to stop pretending it is a daemon, and to
keep the metronome exactly where the evidence does not reach.

### D-23: The fleet smoke runner — one local-only script is the standing platform-drift check  (R4)

**Decision:** Task 7 ships `scripts/fleet-smoke.sh` behind `mise run
smoke:fleet`, a runner whose live circuit never runs in CI (the
evals-never-in-CI posture) while its dry-run mode over the post seam runs
in the shell suite, and
that drives the full circuit on a host with a messaging-capable CLI —
dispatch a worker, let it park, observe the tower act on the park, answer,
observe the worker resume — printing the observed latencies and the
before/after duty cycle (store reads per worker-minute over one runner
pass) and exiting non-zero on any missed step. The notice-wake step and
the duty-cycle figure need Task 6's event-driven loop and ride its
Deferred gate; before that gate the metronome tower picks the park up on
its next iteration and the circuit passes there, the figure being the
watcher's rather than the tower's. It runs
once as Task 7's capstone, and from then on it is what "re-verify against
the running CLI" means: every later platform-touching change reruns it
instead of an ad-hoc manual arm (REQ-A1.4, REQ-A1.7). Its findings are
recorded the way the kickoff's experiments were, in the PR that ran it.
*(Amended at kickoff 2026-09-07 (resumed): the notice-wake step and the
duty-cycle figure gated with Task 6's loop change, the pre-gate circuit
stated, the duty cycle defined, and the CI exclusion scoped to the live
circuit.)*

**Alternatives considered:**
- Per-task manual re-verification only (the shape before this decision).
  Rejected because: each task proves its own piece and nothing ever runs
  the circuit end to end, so integration seams surface in production, and
  every future platform change re-invents the checklist.
- A live arm in CI. Rejected because: CI has no messaging-capable session
  and its CLI sits below the messaging floor; the evals-never-in-CI posture
  exists for exactly this class.
- A behavioral eval. Rejected because: the eval harness drives one session
  and cannot back a two-session flow.

**Chosen because:** a repeatable script turns the kickoff's one-off
experiments into a standing check, costs one run per platform-touching
change, and is the only verification that exercises the seams between the
tasks.
