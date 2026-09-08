# Fleet Messaging — Requirements

**Status:** Ready
**Last reviewed:** 2026-09-07
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright's fleet signals — worker→tower attention and decision forks,
tower→worker steering and answers, completion notices — ride mechanisms built
before the harness had any native inter-session channel: `capture-pane`
screen-scraping, `tmux` buffer-paste, and a file store that doubles as durable
record *and* signaling bus, so every signal pays a store write under a
contended lock and every consumer polls. Claude Code now ships cross-session
messaging (`ListAgents`/`SendMessage`, per-session inbox sockets, one-shot
idle notices): attributed and non-impersonating, delivered without
polling — a message is read mid-turn, an idle notice wakes an idle session.
This bundle adopts it as the fleet's preferred
**signal transport** where available, and takes the accompanying **store-load
reduction**: tower-facing signal-purpose store reads and poll cadences
demote to a
documented low-cadence healing sweep wherever push is live, while every
durable record stays file/git-based and level-triggered and no sweep is ever
removed. It is a transport layer, not a state-store replacement (the altitude
call is D-1). Every messaging path degrades to today's mechanism when the
feature is absent (version, provider, feature flags), and no signal is ever
correctness-critical.

## Scope

### In scope

- Deterministic, per-session availability probing, and per-rung messaging
  eligibility derived from the backend capability contract's existing
  `Session-grade` column for non-`--bare` launches.
- Deterministic session identity: fleet-launched sessions (workers, and
  towers launched by the meta-tower or the watchdog) named from the existing
  handle grammar so they are addressable peers.
- Downward delivery (tower→worker steer and decision answers) over messaging,
  messaging-first on every steer-advertising rung that is eligible, with the
  rung's existing attributed steer delivery as fallback.
- Upward signals (worker→tower attention, decision forks, completion): the
  store row remains the record; the harness's one-shot idle notice pushes
  "the worker stopped" to the tower and supplements the tower's
  signal-polling, which demotes to the healing sweep; no worker-side
  messaging post exists.
- The store-load reduction: demoting tower-facing signal-purpose poll
  cadences to a
  documented low-cadence healing sweep wherever a push path is live.
- Settings and profile wiring: worker inbound-message acceptance, tower
  acceptance, and the three knobs (`messaging_discipline`,
  `messaging_cross_machine`, `messaging_heal_cadence_seconds`) with their
  config, options-reference, and fleet-doc rows.
- Tower↔tower advisory messages (replacing operator hand-relay), bound by the
  nothing-on-the-correctness-path rule.
- A doctrine statement (the messaging-transport doctrine) making the
  signal-vs-record rule and the discipline ladder citable, and the amendment
  of the inter-orchestrator-coordination doctrine whose steer-in-flight
  mechanism of record this bundle changes.

### Out of scope

- **Moving any state of record onto messages.** Messages are lossy, ephemeral,
  and model-turn-bound; the registry, fences, audit trail, and the `tasks.md`
  record stay file/git-based (D-1).
- **Fixing the store's lost-append and lock-race defects.** This bundle only
  reduces the store's signal-rate load; store hardening remains its own spec,
  and the relevant observations stay live for it.
- **The operator-facing merge-ready push.** Its ownership lives in the
  fleet-coordination-floor doctrine's assignment to `merge-currency-guard`
  and in that bundle's pending amendment note (Sources); that bundle's
  signed scope does not carry it yet. A message delivered to a *tower* is
  still an LLM path and never satisfies the deterministic-attention floor.
- **The general worker-settings-profile delivery mechanism and the dead
  `--settings` hook fix.** Owned by the `worker-permission-ergonomics`
  amendment (its pending note, Sources). This bundle wires only the
  messaging settings, through the shipped profiles and `--settings` (the
  route the platform documents for `crossSessionInbound` and obs:58aa232e
  observed working for permission-class keys), and adopts the mechanism
  when it lands (REQ-F1.1).
- **Reopening `concurrent-orchestrator-coordination`'s signed design.** Its
  file-based presence surface and origin fences stay as that bundle and the
  fleet-coordination-floor doctrine place them; this bundle adds an advisory
  layer only.
- **LLM-in-daemon mechanics.** Daemons are not sessions and receive nothing;
  the no-LLM-daemon-mechanics floor carries unchanged.
- **Observe-in-flight.** Messaging carries signals, not live worker output;
  screen/stream observation keeps its existing mechanisms.
- **Cross-machine fleets as a default posture.** Cross-machine messaging
  exists only behind the harness's per-send approval prompt
  (`isolatePeerMachines: true` in both shipped profiles), with
  `messaging_cross_machine` as the documented operator cue to relax it
  (D-5); remote sessions are not fleet peers for presence, liveness, or
  dispatch.
- **Agent teams and workflows.** The Claude-Code-primitives-only principle
  carries; this bundle adopts the messaging primitive alone.

## REQ-A — Availability & eligibility

- **REQ-A1.1** Messaging availability SHALL be determined per session by a
  deterministic probe — `CLAUDE_CODE_MESSAGING_SOCKET` set in the invoking
  session's environment and naming an existing socket owned by the invoking
  user, plus the CLI version compared numerically per dotted component
  against the documented messaging minimum (REQ-A1.4; the probe compares
  against the stricter 2.1.248 unconditionally and performs no provider
  detection, the fail-safe reading of the two-valued minimum), plus the
  session's effective `crossSessionInbound` resolving to `accept` — a
  top-level settings key, read from the CLI's settings files by the
  awk-based parsing the fleet's scripts use (no jq, no eval; REQ-K1.5), or
  from `PLANWRIGHT_MESSAGING_INBOUND=accept`, which a fleet launch seam
  exports beside the `--settings` profile it passes: the variable stands
  for that command-line `--settings` layer and outranks every settings
  file, the files not showing it. An operator-launched
  tower whose profile was never merged reads absent rather than silently
  losing every notice, and managed policy is out of scope: availability is
  never inferred from configuration alone, the socket and version conjuncts
  being observed facts (configuration may force messaging off,
  `messaging_discipline: off` reading absent by design, never on). A
  version below the
  minimum, a
  missing or malformed variable, a socket that fails the predicate, a
  settings parse failure, an effective `crossSessionInbound` other than
  `accept`, and a `messaging_discipline` resolving to `off` or to a value
  the ladder does not name all read absent.
  *(Cites: D-17, D-11.)*
  *(Amended at revision 2026-09-02: probe scoped to the invoking session;
  the host-level gate is gone with D-6; the version threshold is the pin.)*
  *(Amended at kickoff 2026-09-02 (resumed): the variable and predicate
  named; the threshold is the documented minimum, not the last-verified
  pin.)*
  *(Amended at kickoff 2026-09-07 (resumed): the inbound-acceptance conjunct
  added; the exported layer's precedence over the settings files, the
  top-level key and its awk parse, and the complete absent list.)*
- **REQ-A1.2** The capability SHALL be advertised per backend rung through the
  backend capability contract's property mechanism; an unknown, unprobeable,
  or malformed advertisement reads as absent (fail-safe), and rungs with no
  session socket (in-harness subagents, `in-session`) are structurally
  without it.
  *(Cites: D-6.)*
  **Superseded-by: REQ-A1.6** (2026-09-02) — socket presence is a per-session
  fact, so a per-rung contract property cannot carry it; eligibility is
  derived from the contract's existing `Session-grade` column instead
  (D-17).
- **REQ-A1.6** (supersedes REQ-A1.2) Per-rung messaging eligibility SHALL be
  derived from the backend capability contract's existing `Session-grade`
  column — a rung whose session-grade is `yes` and whose launch is
  non-`--bare` (the launch pin, execution-backends D-12; a `--bare` session
  binds no inbox) can bind an inbox socket, `no` and `deferred` rungs
  cannot — with no new contract column or adapter field. Messaging
  eligibility is distinct from the contract's dispatch eligibility (the
  candidate rung set), though both read the same column. A send is possible
  when the per-session probe (REQ-A1.1) reads available in the sending
  session and the target worker has a recorded inbox socket basename
  (REQ-B1.2). An unknown or
  malformed session-grade value reads as ineligible (fail-safe).
  *(Cites: D-17.)*
  *(Amended at kickoff 2026-09-02 (resumed): the non-`--bare` conjunct
  added; messaging eligibility distinguished from dispatch eligibility.)*
- **REQ-A1.3** Where the capability is absent, every consumer SHALL behave
  exactly as it does today: adoption changes no behavior for a host, provider,
  or session without messaging.
  *(Cites: D-1, D-6.)*
  **Superseded-by: REQ-A1.5** (2026-09-02) — the unconditional dispatch-seam
  preparation REQ-B1.1 and REQ-F1.1 require (launch naming, inbound settings)
  is a behavior change on every host, so the no-change rule is scoped to the
  signal paths.
- **REQ-A1.5** (supersedes REQ-A1.3) Where messaging is unavailable in the
  session or the rung is ineligible (REQ-A1.1, REQ-A1.6), every consumer of
  the signal transport (downward delivery, idle notices, the demoted
  sweeps) SHALL take exactly today's code path; the
  dispatch-seam preparation that makes a session addressable and accepting
  (REQ-B1.1, REQ-F1.1) is unconditional on eligible rungs — independent of
  the per-session probe, not of REQ-A1.6 — and inert without messaging.
  *(Cites: D-1, D-17.)*
  *(Amended at kickoff 2026-09-02 (resumed): "unconditional" scoped to
  eligible rungs.)*
  *(Amended at kickoff 2026-09-04 (resumed): the consumer list restated for the
  idle-notice path.)*
- **REQ-A1.4** The platform contract this bundle consumes (environment
  variables, socket protocol, tool semantics, version gates) SHALL be pinned
  to two recorded versions: the **documented messaging minimum** (2.1.224;
  2.1.248 on non-Anthropic providers or with feature-flag fetching off),
  which the probe compares against, and the **last-verified pin** (initially
  2.1.259, the highest version observed in a tower session), held in the
  drift guard's fixture. The fixture tests prove
  planwright's own parsers and probe match the frozen contract assumptions,
  failing with a diagnostic naming the assumption when a repo-side change
  breaks one; the platform moving is caught by the live re-verification
  every task that touches the platform surface performs against the running
  CLI — once Task 7 has landed, by running the fleet smoke runner
  (REQ-A1.7), and before then by the task's own manual arm —
  recording the observed version in the task PR and raising the pin,
  never lowering it — a running CLI below the pin halts the task. No task
  carries its own copy.
  *(Cites: D-11, obs:16facd5b, research: Claude Code cross-session messaging
  docs (Sources).)*
  *(Amended at revision 2026-09-02: one pin of record, re-verified per task,
  replacing a per-task pin.)*
  *(Amended at kickoff 2026-09-02 (resumed): the minimum and the
  last-verified pin split, with initial values and the raise-only rule.)*
  *(Amended at kickoff 2026-09-07 (resumed): the initial pin's basis
  restated as a tower-session observation; the smoke runner's onset tied to
  Task 7 landing.)*
- **REQ-A1.7** A local-only fleet smoke runner (`mise run smoke:fleet`,
  whose live circuit never runs in CI, the evals-never-in-CI posture, while
  its dry-run mode over the post seam runs in the shell suite) SHALL drive
  the full circuit
  on a host with a messaging-capable CLI — dispatch a worker, let it park,
  observe the tower act on the park, answer, observe the worker resume —
  printing the observed latencies and the before/after duty cycle (store
  reads per worker-minute over one runner pass), and
  exiting non-zero on any missed step. The notice-wake step (the notice
  waking the tower rather than the tower finding the park) and the
  duty-cycle figure need the event-driven loop Task 6 holds behind its
  Deferred gate, and join that entry's gated set; before the gate the
  circuit passes when the metronome tower acts on the park on its next
  iteration, and the figure is the watcher's rather than the tower's.
  Task 7 ships it and runs it once as
  its capstone; from then on it is the standing platform-drift check every
  platform-touching change reruns in place of ad-hoc re-verification.
  *(Cites: D-23, D-11.)*
  *(Amended at kickoff 2026-09-07 (resumed): the notice-wake step and the
  duty-cycle figure gated with Task 6's loop change, the pre-gate circuit
  stated, the duty cycle defined, and the CI exclusion scoped to the live
  circuit.)*

## REQ-B — Addressable identity

- **REQ-B1.1** Fleet-launched sessions (workers, and towers launched on a
  session-grade rung by the watchdog, the meta-tower, or the
  continue-as-new handover) SHALL be named
  deterministically from the per-backend fleet handle grammar
  `orchestrate-relay.sh` owns (`validate-handle`), via the launch `--name`
  mechanism, so every
  fleet-launched peer is addressable without listing round-trips. A
  subordinate tower hosted on `subagent` or `in-session` is not a messaging
  peer. An operator-launched tower is not fleet-launched: it is addressed by
  a listing round-trip on the low-rate advisory path only. The fleet tower
  launches are the watchdog's relaunch, the meta-tower's subordinate, and
  the continue-as-new handover; a custom `PLANWRIGHT_TOWER_LAUNCHER` is out
  of scope. The watchdog's relaunch already goes through a script; the
  subordinate and the handover launch through
  `scripts/fleet-tower-launch.sh`, so all three are script launch lines the
  tower command-guard approves wholesale rather than prose Bash strings
  carrying a `--settings` flag the guard defers on.
  The worker dispatch seams SHALL export the worker identity
  environment (`PLANWRIGHT_WORKER_HANDLE`, `PLANWRIGHT_WORKER_SCOPE`) on
  every session-grade rung — today only the
  `headless-oneshot` seam does (obs:fbb701bc) — so the hooks that write
  attention rows run for every worker a tower can be woken about.
  *(Cites: D-8, obs:d4d66281, obs:fbb701bc.)*
  *(Amended at revision 2026-09-02: the tower launch seams named and the
  operator-launched carve-out stated.)*
  *(Amended at kickoff 2026-09-02 (resumed): tower naming scoped to
  session-grade launches; the grammar's owner named.)*
  *(Amended at kickoff 2026-09-07 (resumed): the identity environment export at
  every session-grade seam, the precondition for attention rows; the
  handover named among the launchers, and the subordinate and handover
  launches moved behind `fleet-tower-launch.sh`.)*
- **REQ-B1.2** The actual post-launch name SHALL be recorded, together
  with the session's inbox socket basename, by the session itself: its
  SessionStart hook runs `fleet-messaging.sh self-register`, which reads the
  session's own per-session record (`~/.claude/sessions/$CLAUDE_PID.json`,
  an undocumented surface the drift guard freezes, D-11) and, for a worker,
  amends its registry row's two added columns `name` and `inbox` (written
  as the store's `-` sentinel at registration, filled by the hook through
  `fleet-state.sh amend` via `fleet-register.sh`'s per-field degrade; the
  scripts that parse the registry file, re-derived by grep at Task 4 (today
  `fleet-status.sh`), plus the readers this bundle adds, tolerate rows of
  three, seven, and nine columns). For a tower `self-register` writes
  nothing: the `--watch` loop records the tower marker's one added field at
  loop start, with the name the new `fleet-messaging.sh self-name` verb
  reads from that same session record (a tower's socket path is never
  recorded; nothing posts to a
  tower by script). No seam reads anything back: a worker whose hook never
  runs keeps the sentinels, is unaddressable (downward delivery falls
  back), and is never subscribed. Both columns hold bare values, not
  `key=value` tokens, and `amend` and `send --to-worker` bind a worker's
  last registry record, the append log's existing last-record-wins
  convention. The registry's own write grammar is the narrowest of the name
  screens this path crosses: an observed name that passes the screen but
  fails that grammar leaves the row's sentinel in place and the worker
  unaddressable, exactly as an unrun hook does.
  Neither value carries a path separator,
  so the registry's field grammar stays as it is; the socket directory is
  the tower's own socket's directory, one user on one machine. The CLI
  renames an interactive collision to a variant; the recorded name is the
  observed one, never the requested one assumed.
  *(Cites: D-8.)*
  *(Amended at revision 2026-09-02: the tower marker named as the tower-side
  record.)*
  *(Amended at kickoff 2026-09-02 (resumed): the worker-side record is a
  registry basename field; the marker gains two fields; the writer and
  readers named.)*
  *(Amended at kickoff 2026-09-04 (resumed): the marker gains the name
  only; the registry gains the observed name as well; the read-back
  source named.)*
  *(Amended at kickoff 2026-09-07 (resumed): recorded by the session's own
  SessionStart hook from its own record; no seam read-back, no retry
  window; the registry amend verb; the marker back at loop start, written
  by the loop from `self-name`; the reader set re-derived and its three
  arities; bare column values, last-record-wins, and the registry write
  grammar as the narrowest screen.)*
- **REQ-B1.3** Names and addresses SHALL be validated against their declared
  grammar as data before any use in addressing, paths, or echoed output.
  *(Cites: D-8; the security-posture doctrine.)*

## REQ-C — Downward delivery

- **REQ-C1.1** Tower→worker steer and decision-answer delivery SHALL prefer
  messaging on every rung that advertises steer-in-flight and is eligible
  (REQ-A1.6), `tmux` included, with the fallback ladder: messaging → the
  rung's existing attributed steer delivery → operator handoff. A rung
  without steer-in-flight receives no downward delivery: it holds no fork to
  answer. On `stream-json-persistent` the decision channel is not the
  answer path at all: the tower obtains the pending control request's full
  id from `fleet-streamjson.sh status <worker>`, the `decide` row carrying
  only a truncated prefix inside its question text, and answers with the
  supervisor's own verb
  (`fleet-streamjson.sh answer <worker> <request id> …`), and
  `fleet-decision.sh answer` refuses that rung with a diagnostic naming
  it — a message cannot resolve a pending control request, and a closed
  fork over a pending request is a deadlock. The fork is still claimed
  under the fleet lock and its answer artifact still persisted before the
  control response is written, so REQ-C1.2's ordering and REQ-C1.5's
  answered-undelivered surfacing hold on that rung too. Messaging carries
  free-text
  steers only on that rung, with operator handoff as their fallback (no
  attributed steer delivery exists there today).
  *(Cites: D-3, obs:b7618838.)*
  *(Amended at revision 2026-09-02: rung set pinned to steer-advertising
  eligible rungs; `headless-oneshot` is excluded by its contract row.)*
  *(Amended at kickoff 2026-09-07 (resumed): the `stream-json-persistent`
  carve-out for decision answers, its request-id source, and the
  claim-and-persist ordering it keeps.)*
- **REQ-C1.2** A decision answer SHALL be claimed under the fleet lock and its
  answer artifact persisted before any delivery attempt; a failed delivery
  never re-opens or re-claims the fork.
  *(Cites: D-9, obs:efe0b752.)*
- **REQ-C1.3** The sender SHALL consume the harness's delivery outcomes (held,
  refused, dropped, expired) and take the next fallback rung rather than
  assume delivery; an unconfirmed delivery is surfaced, never silently
  presumed successful.
  *(Cites: D-9.)*
  **Superseded-by: REQ-C1.5** (2026-09-02) — a held message stays queued at
  the receiver, so descending on it double-delivers; and a script-posted send
  observes only the outcomes the socket returns synchronously.
- **REQ-C1.5** (supersedes REQ-C1.3) The send path SHALL consume every
  delivery outcome the post returns synchronously (accepted, held, refused)
  plus a failed post: refused and a failed post take the next step of the
  fallback ladder; held is surfaced as unconfirmed (one stderr notice, no
  store row) and left queued, never re-sent; accepted is not proof of
  delivery. That a raw socket post returns those outcomes is an unverified
  platform premise (D-12): Task 2 verifies it first against the running
  CLI, and where the post returns nothing, write success or failure is the
  only observed outcome and the same rules apply to it. Outcomes a script
  cannot observe on the connection (dropped, expired) are made observable
  another way: the post carries the tower's own inbox socket as its reply
  address, so the harness's status frames for that message reach the
  tower's inbox and its model as a notice; `send` mints the message id
  itself (a UUID), writes it into the frame beside the reply address,
  posts no auth line, and prints it on stdout for every post that was
  written, held included, and the decision channel records it in one
  metadata sibling of the answer artifact
  (`<fleet-home>/attention/answers/<worker>.meta`, one line per fork
  instance id — the attention store's fork discriminator —
  `<instance>\t<message id>\t<epoch>`; a second fork for the same worker
  adds a second record, and `redeliver` refuses an id whose fork is not
  the artifact's current fork;
  never inside the artifact, whose whole content is what the attributed
  steer delivery carries), so a frame names a fork; a drop, expiry, or
  refused frame runs `redeliver` first, the tower's
  prose performing exactly one deliberate fallback delivery
  (`fleet-decision.sh redeliver --message-id <id>`: it emits the
  attributed steer delivery command only, never a second messaging post,
  never a re-claim, and records `redelivered` in that sibling as the
  once-per-fork record); a held frame runs the step's own first action
  instead, its recovery being the answered-undelivered surfacing below;
  a frame received mid-turn is handled after the
  step's own work, never interleaved. The decision channel's exit codes:
  0 when the post was accepted or the fallback delivery command was
  emitted, 5 when held, 4 for the terminal operator handoff — keeping
  today's meaning (delivery not completed after a successful claim) and
  both of today's sub-cases, the artifact persisted and the artifact
  lost — today's 2 and
  3 unchanged; the relay's messaging arm reports held the same way. An
  inbound status frame the tower holds or never receives leaves the
  surfacing below as the recovery. That the
  frames are emitted for a raw post is unverified until Task 2's wire step;
  where they are not, the parked worker is surfaced instead: the tower's
  healing sweep shows it as an undelivered answer for the operator handoff
  (the attention view marks a parked worker whose fork carries a persisted
  answer artifact as answered-undelivered), the persisted artifact is the
  recovery source, and no other re-delivery is attempted (the surfacing
  rule lives here; REQ-D1.4 governs upward signals). No unconfirmed
  delivery is ever presumed successful.
  *(Cites: D-9, D-12.)*
  *(Amended at kickoff 2026-09-02 (resumed): the synchronous premise marked
  unverified with its fallback; the dropped/expired recovery stated.)*
  *(Amended at kickoff 2026-09-04 (resumed): the reply address and the
  one-shot fallback re-delivery on a drop or expiry frame added, with
  surface-only as the unverified-frame fallback.)*
  *(Amended at kickoff 2026-09-07 (resumed): the message id minted by `send`
  and recorded in a per-fork metadata sibling, with no auth line posted;
  held's exit code and exit 4's kept meaning; the drop, expiry, refused,
  and held frame cases.)*
- **REQ-C1.4** Delivery SHALL never impersonate the worker's input and never
  answer a worker's permission prompt; message text is data end to end, with
  no eval or expansion path.
  *(Cites: D-3; the inter-orchestrator-coordination doctrine.)*

## REQ-D — Upward signals

- **REQ-D1.1** Routine worker→tower signals (attention rows, decision forks,
  parks) SHALL be pushed by deterministic script-posted doorbells — the
  attention store's write verbs (`fleet-attention.sh heartbeat`, `decide`,
  `fork`, `park`) delegating to `fleet-messaging.sh doorbell`, with no
  harness hook entry — with no worker-model turn on the routine path; the
  receiving
  tower spends one model turn per doorbell (D-4).
  *(Cites: D-7.)*
  *(Amended at kickoff 2026-09-02 (resumed): the posting verbs named;
  "no model turn" scoped to the worker side.)*
  **Superseded-by: REQ-D1.6** (2026-09-04, resumed kickoff) — the
  experiments in brief §8 showed a script post observes nothing but write
  success and that the harness's idle notice reaches the tower within a
  second of a worker stopping, carrying its closing line; the worker-side
  doorbell bought only mid-turn rows at the cost of socket propagation, a
  spoofable surface, and a tower turn per signal.
- **REQ-D1.2** A doorbell SHALL carry only a minimal, grammar-validated
  pointer payload. The receiver is the tower session, and its only sanctioned
  action on a doorbell is the deterministic store re-read verb, which
  validates the pointer as data and returns store truth; doorbell content
  itself is never acted on. The payload's field set and bounds are the wire
  grammar D-15 fixes.
  *(Cites: D-15, D-16, D-7, D-12.)*
  *(Amended at revision 2026-09-02: receiver named (the tower session) and
  the re-read bound to a script verb.)*
  **Superseded-by: REQ-D1.7** (2026-09-04, resumed kickoff) — no doorbell
  exists to carry a pointer; the notice's status line takes its place as
  the untrusted input the store re-read guards.
- **REQ-D1.3** Completion and idle signaling SHALL use the harness's one-shot
  idle-notice subscription where both sessions accept it — the watched
  worker's rung is eligible and its shipped profile carries
  `crossSessionInbound: accept`, and the subscribing tower's settings carry
  the same key (the tower profile at fleet tower launches, the operator's
  own settings otherwise) — as a supplement only: the tower session
  subscribes after dispatch, conditioned on its own probe reading
  available, and re-subscribes after each downward delivery it makes,
  unconditionally (a duplicate or expired prior subscription is harmless,
  because a notice is only a supplement); positive-evidence-of-death
  liveness is unchanged, and the absence of a notice is never read as a
  signal.
  *(Cites: D-10.)*
  *(Amended at revision 2026-09-02: subscriber and re-arm policy stated;
  the obs:67861aa6 citation dropped, its subject being CI wall-clock
  against the tool-call ceiling, not completion signaling.)*
  *(Amended at kickoff 2026-09-02 (resumed): "accept" defined for both
  sessions; the probe condition; one unconditional re-subscribe rule.)*
  **Superseded-by: REQ-D1.7** (2026-09-04, resumed kickoff) — the idle
  notice is the upward push path, not a completion supplement.
- **REQ-D1.4** A missed, expired, or turn-boundary-delayed idle notice, and
  every attention row
  written while a worker is still running, SHALL be healed by the retained
  level-triggered healing sweep; no messaging signal is
  correctness-critical.
  *(Cites: D-16.)*
  *(Amended at kickoff 2026-09-02 (resumed): the outcome set aligned with
  REQ-C1.5 — held stays queued and is not the sweep's case.)*
  *(Amended at kickoff 2026-09-04 (resumed): the healed set restated for
  the idle-notice path.)*
- **REQ-D1.5** The tower's inbox socket path SHALL reach dispatched workers
  deterministically — set in the dispatch environment at launch as
  `PLANWRIGHT_TOWER_INBOX_SOCKET` (the seam obtains it from
  `fleet-messaging.sh self-socket`, the single reader of the tower's own
  socket variable), with the tower's marker record as the fallback (every
  tower writes its observed name and socket path into its marker at
  `/orchestrate` step start; the worker reads the marker of its own spec,
  the spec half of `PLANWRIGHT_WORKER_SCOPE`; a meta-tower is never a
  doorbell target) — and be validated before use through
  `fleet-messaging.sh`'s owner predicate (an existing socket owned by the
  invoking user); a missing or invalid path degrades the doorbell path to
  the healing sweep with one stderr notice and no retry, never an error
  loop.
  *(Cites: D-7.)*
  *(Amended at kickoff 2026-09-02 (resumed): the dispatch variable and its
  source named; the marker written by every tower at step start; the
  lookup key, the predicate's home, and the notice named.)*

  **Superseded-by: REQ-D1.6** (2026-09-04, resumed kickoff) — no worker
  ever posts to the tower, so no tower socket path reaches a worker;
  retired without a replacement mechanism.
- **REQ-D1.6** (supersedes REQ-D1.1, REQ-D1.5) Routine worker→tower
  signals SHALL reach the tower by exactly two paths: the harness's
  one-shot idle notice when the worker stops — a fork or park at which the
  worker ends its turn awaiting a decision, or completion, and the notice,
  enqueued at the tower within seconds, carries the worker's closing line;
  a mid-turn suspension (a permission or elicitation dialog, obs:4c25e743)
  ends no turn and is the sweep's case, surfacing there as a stale
  heartbeat past the watcher's liveness max-age and never as an attention
  row (whether the notice fires
  before a `headless-oneshot` worker's process exits is unverified; Task
  6's live check records the outcome, and the sweep carries the case
  either way) — and the retained level-triggered healing sweep for
  everything else, attention rows written mid-turn included. No
  worker-side messaging post exists: a worker never learns or holds a
  tower socket path, no planwright-defined upward wire grammar exists, and
  `fleet-attention.sh`'s write verbs are unchanged.
  *(Cites: D-20; the platform experiments (brief §8).)*
  *(Amended at kickoff 2026-09-07 (resumed): only a turn-ending stop fires a
  notice; mid-turn suspensions named as the sweep's case, surfacing there
  as a stale heartbeat.)*
- **REQ-D1.7** (supersedes REQ-D1.2, REQ-D1.3) The tower session SHALL
  subscribe to each dispatched worker's idle notice immediately after
  dispatch, conditioned on its own probe reading available, and
  re-subscribe after each downward delivery it makes, unconditional on any
  prior subscription (a duplicate or expired one is harmless; the
  subscribe step's probe condition still applies). A notice's status line
  is untrusted instruction data the tower's prose reads only the quoted
  session name from: the tower's only sanctioned action on a notice is the
  deterministic store re-read verb (`fleet-messaging.sh notice-read
  <session name>`), which screens the name as data (printable ASCII, no
  path separator, at most 128 bytes), matches it against the registry's
  `name` column, and returns store truth; the status line itself is never
  acted on, and in `--watch` mode no fleet read in that iteration precedes
  the re-read; that iteration presupposes the event-driven loop Task 6
  holds behind its Deferred gate, so the notice-consumption criterion joins
  that entry's gated set, a notice merely being enqueued at the tower
  before it. The sanction is a standing instruction the skill states
  once, so it persists in the session after a step exits. Both sessions
  accept a notice when the worker's rung is eligible and its shipped
  profile carries `crossSessionInbound: accept`, and the subscribing
  tower's own probe reads available (which includes that key, REQ-A1.1).
  The tower also
  subscribes over the reconcile sweep's in-flight worker set at its start
  (a fresh tower after a restart or a handover holds no subscriptions),
  addresses every subscription by the registry's recorded `name` column
  (skipping a worker with none), refuses an ambiguous name match, treats an
  empty
  `notice-read` result as a no-op, and runs the re-read before any other
  fleet read in any notice-driven turn; a single-step tower whose session
  ends with the step takes no subscription. Notices push; they
  never replace
  the sweep: positive-evidence-of-death liveness is unchanged, and the
  absence of a notice is never read as a signal.
  *(Cites: D-21, D-12.)*

  *(Amended at kickoff 2026-09-07 (resumed): the start-of-tower subscribe pass,
  addressing by recorded name, the ambiguous and empty cases, the
  ordering rule for every notice-driven turn, and that rule's gating with
  Task 6's loop change.)*
- **REQ-D1.8** Where the tower's own probe reads available and its session
  type survives a turn end (an interactive session; a `-p` tower, the
  continue-as-new handover included, keeps today's metronome), the
  `--watch` loop SHALL end its turn after each step and be woken for the
  next by a worker's idle notice, by a peer message (a status frame, an
  advisory), or by the timer — the harness's scheduled wakeup requested at
  step end, at the healing cadence where REQ-E1.1's demotion trigger holds
  and at today's metronome interval otherwise, whose availability per
  session type
  Task 2 records (D-11, either outcome recorded: where that step finds no
  scheduled wakeup for a session type, the metronome-retention clause below
  is what stands in its place). Where the wakeup is unavailable, or a step ends
  with neither a live subscription nor an available wakeup, the loop keeps
  today's metronome for that step (REQ-A1.5); the subagent backend's
  existing event-driven arm stands. A notice-driven turn runs
  `notice-read` first, a drop, expiry, or refused status-frame turn
  `redeliver` first (REQ-C1.5, a held frame taking the step's own first
  action), a
  timer-driven turn the reconcile sweep first, an advisory turn the step's
  own first action; where more than one wake source is pending the order is
  `notice-read`, then `redeliver`, then the reconcile sweep, then the
  step's own first action, and the start-of-tower subscribe pass precedes
  all of them on a tower's first turn. All stay inside the step's own rules
  for dispatching,
  claiming, and writing. Selector exit 1 (no ready unit) ends the turn
  awaiting a wake while a subscription is live — the same recorded proxy
  REQ-E1.1's trigger reads, at least one in-flight worker carrying a
  recorded `inbox` value — and ends the watch
  otherwise. The continue-as-new handover seed carries the sanction
  sentence only; the subscribe pass derives the in-flight set from disk.
  The metronome this retires is bootstrap D-38's: the pending note (Sources)
  names the `/spec-draft --extend bootstrap` invocation that drafts the
  amendment for real, and Task 6's loop change carries a Deferred gate on
  that amendment being signed off, so two signed designs never contradict
  each other in flight; the rest of Task 6 is not gated.
  *(Cites: D-22, D-21.)*
  *(Amended at kickoff 2026-09-07 (resumed): the timer's cadence made
  conditional with either outcome recorded; the wake-source precedence
  order; the status-frame arm split by frame kind; a live subscription
  defined as REQ-E1.1's recorded proxy.)*

## REQ-E — Store-load reduction

- **REQ-E1.1** Wherever the tower's own probe reads available and at least
  one in-flight worker carries a recorded `inbox` value (the
  dispatch-time proxy for the tower's subscription, which is prose-side and
  deliberately unrecorded, D-21; a recorded value already means a bound
  inbox, so rung eligibility is not a second conjunct; re-evaluated each
  pass), tower-facing
  signal polling SHALL demote: the `--watch` loop's own store reads become
  wake-driven (REQ-D1.8) — that half rides Task 6's loop change and is
  gated with it, so this requirement's coverage is complete only at that
  gate — and `fleet-attention-watch.sh watch`, when run
  tower-facing (without an operator `--on-change` callback; its bring-up is
  documented in `docs/fleet.md`, the script having no shipped caller
  today), demotes to a documented low-cadence healing sweep whose cadence
  is one overlay-resolved knob (`messaging_heal_cadence_seconds`) applied
  to every demoted consumer, never a per-consumer value, with its deep
  reconcile period recomputed as
  `reconcile_every = max(1, round(300 / cadence))`, so that period is at
  least the pre-demotion period and within one demoted interval of it. The
  knob is
  validated at or below the watcher's default liveness max-age, which is
  what keeps the liveness stamp alive across a demoted interval; no further
  `--max-age` comparison is made. Operator-facing cadences — the watcher
  with a callback, the dashboard's refresh — keep today's intervals:
  nothing pushes to the human. The knob replaces the demoted consumer's
  default interval; an explicit `--interval` stays authoritative, and the
  attention watcher's event-driven branch (where the interval is a
  timeout, not a poll) is unchanged.
  *(Cites: D-16, D-22, obs:8b694bdb.)*
  *(Amended at revision 2026-09-02: the cadence knob named, singular.)*
  *(Amended at kickoff 2026-09-02 (resumed): the consumers named by path;
  the demotion trigger and the interval precedence stated.)*
  *(Amended at kickoff 2026-09-07 (resumed): the trigger rests on recorded
  facts only, without the eligibility conjunct; the tower's own reads are
  wake-driven and gated with Task 6's loop change; the watcher's
  reconcile period preserved by a stated recompute; operator-facing
  cadences excluded; the `--max-age` refusal dropped for the knob's own
  bound.)*
- **REQ-E1.2** The healing sweep SHALL never be removed: the channel is lossy
  by contract, so level-triggered derivation from ground truth remains the
  healing path at every discipline value. The three sweeps are distinct:
  the healing sweep is `fleet-attention-watch.sh watch`'s level-triggered
  pass, the reconcile sweep is `/orchestrate`'s tower step that rebuilds
  in-flight state from disk, and `fleet-attention-watch.sh reconcile` is
  that script's own deep-reconcile verb.
  *(Cites: D-16.)*
- **REQ-E1.3** The reduction SHALL NOT change record semantics: no store write
  is removed and no record moves; only signal-purpose reads and cadences
  change.
  *(Cites: D-1, D-16.)*

## REQ-F — Settings & discipline

- **REQ-F1.1** Dispatched worker settings SHALL enable unattended inbound
  acceptance (`crossSessionInbound: accept`) through a mechanism verified to
  apply in that rung's session type, and delivering those settings to the
  worker is part of the dispatch seam, not operator memory. The messaging
  keys ride the shipped settings profiles: the worker profile
  (`config/worker-settings.json`) delivered with `--settings` at the worker
  dispatch seam, the tower profile (`config/tower-settings.json`) delivered
  the same way at the fleet tower-launch seams and applied by the operator's
  own settings for an operator-launched tower. The platform documents
  `crossSessionInbound: accept` as deliverable through a `-p` session's
  `--settings` value, and obs:58aa232e observed permission-class keys
  applying that way while hook definitions do not; the hook-only
  `settings.local.json` workaround that observation records is not needed
  here. The interactive `tmux` rung's `--settings` behavior is unverified
  and Task 4's live check is its verification. The general profile-delivery
  mechanism is owned by the `worker-permission-ergonomics` amendment
  (Sources); Task 4 migrates onto it when it lands without changing the
  settings content.
  *(Cites: D-19, obs:eea622de, obs:58aa232e.)*
  *(Amended at revision 2026-09-02: backed by D-18, since superseded;
  ownership of the general delivery mechanism cross-referenced.)*
  *(Amended at kickoff 2026-09-02 (resumed): the `--settings` route stated;
  backed by D-19.)*
  *(Amended at kickoff 2026-09-07 (resumed): the live check and the
  migration named as Task 4's, matching the tasks and the test spec.)*
- **REQ-F1.2** Messaging discipline SHALL be a config knob
  (`messaging_discipline`), laddered `script` < `tiered` < `open`, default
  `tiered`, resolved through the standard overlay layers, plus the switch
  value `off` outside the ladder: `off` makes the probe read absent, so
  every consumer takes the messaging-absent code path (REQ-A1.5) — the
  per-fleet kill switch, overlay-resolvable like any knob, that needs no
  harness setting touched. The direction and pressure offsets apply to the
  three ladder values only. At `off` no model-composed message is sent in
  any direction either: `effective-mode` refuses a knob resolving to `off`,
  and that refusal is the oracle's "do not send". An unknown knob value
  reads absent the same way, fail-safe.
  *(Cites: D-4; the customization-boundary doctrine.)*
  *(Amended at kickoff 2026-09-04 (resumed): the floor value renamed from
  `doorbell` to `script`, its referent having been retired by REQ-D1.6.)*
  *(Amended at kickoff 2026-09-07 (resumed): the `off` switch value, what it
  means for model-composed sends, and the unknown-value reading.)*
- **REQ-F1.3** The discipline SHALL be direction-aware: the knob value names
  the worker→tower value, tower→worker resolves one value stricter,
  saturating at `script`, because towers absorb interrupts and workers need
  focus, and tower↔tower advisory traffic resolves at the knob value
  (offset zero). The worker→tower value is the ladder's anchor; no shipped
  path carries worker→tower traffic (REQ-D1.6), so it constrains only an
  operator-prompted model-composed send. The ladder gates model-composed
  traffic only; deterministic script sends and idle notices ride at every
  value.
  *(Cites: D-4.)*
  *(Amended at revision 2026-09-02: knob-to-direction anchoring and the
  saturating floor stated, from the kickoff §3 intent.)*
  *(Amended at kickoff 2026-09-02 (resumed): the third direction stated.)*
  *(Amended at kickoff 2026-09-04 (resumed): the floor value renamed `script`;
  the anchor direction's scope stated.)*
- **REQ-F1.4** The effective value SHALL be evaluated at send time by
  deterministic script logic over the existing usage gate — one value down
  under reported pressure in every direction, saturating at `script`,
  restored when pressure clears, with one stderr notice per send that runs
  demoted by pressure (the direction offset alone is not demotion) — with no
  stored discipline state and no LLM in the demotion decision. Reported
  pressure means the usage gate's audit-derived rung at
  or above `reduce-concurrency`, read the same way in every direction; the
  context-budget monitor is not a pressure input.
  *(Cites: D-4.)*
  *(Amended at revision 2026-09-02: logging is per demoted send, not per
  transition; the floor and the pressure signal are stated.)*
  *(Amended at kickoff 2026-09-02 (resumed): the notice's destination
  named; every direction demotes.)*
  *(Amended at kickoff 2026-09-04 (resumed): the floor value renamed `script`.)*
- **REQ-F1.5** A cross-machine send SHALL require both the opt-in config knob
  (`messaging_cross_machine`, default off) and per-send operator approval.
  Only a model-composed send can be
  cross-machine (script paths post to a local socket path and are
  same-machine by construction), so the approval gate is the harness's own
  tool-call prompt; the shipped settings profiles carry
  `isolatePeerMachines: true`, and the knob's documented effect is that
  turning it on is the operator's cue to relax that setting.
  *(Cites: D-5.)*
  *(Amended at revision 2026-09-02: scoped to model-composed sends; the
  knob-to-setting relation stated.)*
  **Superseded-by: REQ-F1.6** (2026-09-03, resumed kickoff) — the knob is a
  SHALL on a path no shipped code reads (only model-composed sends can be
  cross-machine, and they bypass `fleet-messaging.sh`), so the requirement
  is restated around the setting that actually enforces.
- **REQ-F1.6** (supersedes REQ-F1.5) A cross-machine send SHALL be gated by
  the harness's own approval prompt: both shipped settings profiles carry
  `isolatePeerMachines: true` (a `true` from any scope wins, even in bypass
  mode), so every model-composed cross-machine send prompts the operator;
  script paths post to a local socket path and are same-machine by
  construction. `messaging_cross_machine` (default off) is a documented
  operator cue, not an enforcement point: turning it on is the recorded
  decision to relax that setting for a fleet, and planwright's scripts
  refuse nothing on a path they never carry.
  *(Cites: D-5.)*

## REQ-G — Degradation & carried floors

- **REQ-G1.1** Every messaging path SHALL name its deterministic fallback —
  the pre-messaging mechanism it replaces — and reach it on absence,
  refusal, or any observable failure with no operator step to select it; the
  ladder's terminal operator handoff is itself today's mechanism, not an
  intervention. Outcomes a script cannot observe are the healing sweep's
  case (REQ-C1.5, REQ-D1.4), not this rule's. The paths are the set D-13
  enumerates.
  *(Cites: D-1, D-3, D-17.)*
  *(Amended at revision 2026-09-02: "without operator intervention"
  clarified as no operator step to select the fallback.)*
  *(Amended at kickoff 2026-09-02 (resumed): scoped to observable failure;
  the path set pointed at D-13.)*
- **REQ-G1.2** No state of record SHALL ride the messaging layer; a message
  that must survive a crash was mis-sent, and the record it points at is the
  durable artifact.
  *(Cites: D-1, D-16.)*
- **REQ-G1.3** The existing floors carry unchanged: every floor the
  fleet-coordination-floor doctrine states, the never-impersonate rule the
  inter-orchestrator-coordination doctrine states, and the never-auto-merge
  invariant — a message to a tower never substitutes for the
  deterministic-attention floor's operator-facing push, and no floor is
  restated here.
  *(Cites: D-1; the fleet-coordination-floor doctrine; the
  inter-orchestrator-coordination doctrine; the autonomous-safe-decision
  doctrine.)*
  *(Amended at revision 2026-09-02: the copied floor list, which matched
  neither doctrine, replaced by citations.)*
  *(Amended at kickoff 2026-09-02 (resumed): the never-auto-merge home
  cited.)*
- **REQ-G1.4** Tower↔tower messages SHALL be advisory only: a message never
  claims, releases, or resolves a unit of work; authority over the division
  of work stays exactly where the fleet-coordination-floor doctrine's
  assume-multiplicity floor places it. An advisory is composed and sent by
  the tower's model through the harness's message tool, addressed by
  session name (the marker name of a fleet-launched tower, a listing for
  an operator-launched one); no script carries the advisory path, and its
  fallback is not-sent.
  *(Cites: D-14; the fleet-coordination-floor doctrine.)*
  *(Amended at revision 2026-09-02: the restated authority list replaced by
  a citation of the floor.)*
  *(Amended at kickoff 2026-09-04 (resumed): the advisory stated as
  model-composed; its fallback named.)*
- **REQ-G1.5** The signal-vs-record rule, the fallback obligation, and the
  discipline ladder SHALL ship as a doctrine document
  (`doctrine/messaging-transport.md`, the messaging-transport doctrine) that
  skills cite through their `Doctrine:` manifest lines and the scripts
  carrying a messaging delivery or read path (the six the test spec names)
  cite in their headers, identity and settings seams not, rather than
  living only inside this bundle. The doctrine
  carries the per-path fallback table REQ-G1.1 requires over the path set
  D-13 enumerates, the per-session probe definition (D-17), the
  cross-machine transit note REQ-H1.2 requires, one sentence distinguishing
  the healing sweep from `/orchestrate`'s reconcile sweep and from
  `fleet-attention-watch.sh reconcile`, and a short glossary naming the
  fallback ladder, the discipline ladder, and the usage gate's rung ladder
  with their step nouns, and the fleet-runtime version rule (mixed CLI
  versions are fine: the probe is per session and fail-safe) — nine
  contents, plus the resource-class
  declaration REQ-G1.6 places here.
  *(Cites: D-13.)*
  *(Amended at revision 2026-09-02: the fallback table and transit note
  placed in the doctrine.)*
  *(Amended at kickoff 2026-09-02 (resumed): the file name, the manifest
  mechanism, and the remaining contents named.)*
  *(Amended at kickoff 2026-09-07 (resumed): the fleet-runtime version rule
  added, nine contents; the header-citation obligation bounded to the six
  scripts the test spec names.)*
- **REQ-G1.6** Messaging SHALL add exactly one class to the
  fleet-coordination-floor doctrine's lifecycle-closure contract — the inbox
  socket: opened by the harness at session start, closed with the session,
  detector: the session's own death evidence — as one row in the class
  contract table and one column in the rungs-by-classes table with every
  cell filled (the table's no-blank-cell rule); and the messaging-transport
  doctrine SHALL declare that no other resource class is acquired: the
  idle-notice subscription is tower-side (outside the floor's worker scope)
  and self-closing (it fires once or expires); the tower's name rides the
  tower marker's existing lifecycle; the worker's socket basename rides
  the worker registry's existing lifecycle.
  *(Cites: D-13; the fleet-coordination-floor doctrine.)*
  *(Amended at kickoff 2026-09-02 (resumed): one class added to the floor's
  single-home contract, row and column, instead of a declaration elsewhere
  alone; the ride-along records named.)*
  *(Amended at kickoff 2026-09-04 (resumed): the ride-along records restated:
  the tower's name and the worker's registry fields.)*
- **REQ-G1.7** The inter-orchestrator-coordination doctrine SHALL be amended
  in the same delivery as the messaging-transport doctrine: its
  steer-in-flight section, heading included, becomes messaging-first with
  attributed buffer-paste as the fallback; its "one audited script"
  sentence and its
  `relay-command` description name `fleet-messaging.sh` as the messaging
  enforcement point the relay delegates to; and its tower-to-tower clause
  (in the *Attributed, non-impersonating relay* section) cross-references
  the advisory rule (REQ-G1.4), so the mechanism of record it pins does not
  contradict this bundle.
  *(Cites: D-13.)*
  *(Amended at kickoff 2026-09-02 (resumed): the two further sentences the
  amendment covers named; the clause located.)*

## REQ-H — Security & hygiene

- **REQ-H1.1** Inbound message and doorbell content SHALL be treated as
  untrusted input: the inbox socket is writable by any same-OS-user process,
  so receivers grammar-screen, length-bound, and echo-sanitize the content
  and act only on what the store or git ground truth re-validates.
  *(Cites: D-7; the security-posture doctrine; obs:b47b3043, obs:404d3b7b.)*
  **Superseded-by: REQ-H1.4** (2026-09-02) — steer text and tower↔tower
  advisories have no artifact to re-validate, so the re-validation clause is
  scoped to upward pointers while the hygiene clause stays universal.
- **REQ-H1.4** (supersedes REQ-H1.1) Inbound message and idle-notice
  content SHALL be treated as untrusted input: the inbox socket is writable
  by any same-OS-user process, so every receiver grammar-screens,
  length-bounds, and echo-sanitizes the content. A notice's status line
  drives action only through what the store re-read returns
  (`notice-read`, REQ-D1.7); steer, answer, and advisory text is
  instruction data the receiving session treats as advisory and never as
  authority over fences, presence, or the `tasks.md` record.
  *(Cites: D-21; the security-posture doctrine; obs:b47b3043,
  obs:404d3b7b.)*
  *(Amended at kickoff 2026-09-04 (resumed): the doorbell clause restated
  for the idle-notice path.)*
- **REQ-H1.2** Message text SHALL carry no secrets, credentials, or sensitive
  operational detail; cross-machine messages transit third-party
  infrastructure and are held to committed-artifact hygiene. The
  obligation is bounded to the two script-carried send paths and their
  `--message-file` call sites; model-composed text is the sending prose's
  own responsibility, reviewed design-level.
  *(Cites: D-5; the security-posture doctrine.)*
  *(Amended at kickoff 2026-09-07 (resumed): the obligation bounded to the
  script send paths.)*
- **REQ-H1.3** All messaging mechanics SHALL live in one audited script
  (`fleet-messaging.sh`): the relay and the decision channel deliver by
  delegation, and no other shipped script posts to an inbox socket or acts
  on an idle notice other than through `notice-read`, so validation and
  data-only handling have exactly one home. The audit is literal — no file
  matching `scripts/*.sh` other than
  `fleet-messaging.sh` contains the `CLAUDE_CODE_MESSAGING_SOCKET` name,
  the platform-contract drift guard's fixture living under `tests/` rather
  than `scripts/` and so outside that match set —
  and the socket owner/existence predicate is a `fleet-messaging.sh` verb
  the send path applies to its target socket.
  Discipline is not enforced here: the ladder gates model-composed traffic
  only (REQ-F1.3), and `effective-mode` is the oracle the sending prose
  consults.
  *(Cites: D-12.)*
  *(Amended at kickoff 2026-09-02 (resumed): the audit's match set made
  literal; discipline enforcement dropped from the one-home claim.)*
  *(Amended at kickoff 2026-09-04 (resumed): the doorbell tag and the
  `self-socket` verb retired with REQ-D1.6.)*
  *(Amended at kickoff 2026-09-07 (resumed): the drift-guard fixture placed
  under `tests/`, outside the audit's match set.)*
- **REQ-H1.5** Every test-only seam in a shipped script — `probe
  --cli-version`, the owner predicate's `--owner-uid` and `--socket-type`,
  and the `PLANWRIGHT_MESSAGING_POST` post override —
  SHALL be refused with a diagnostic unless `PLANWRIGHT_TEST_SEAM=1` is set
  in the environment, so a seam that bypasses a validation cannot be reached
  in production by accident.
  *(Cites: D-11; the security-posture doctrine.)*

## Changelog

- 2026-08-27 — Initial draft elicited via `/spec-draft`: goal, scope,
  REQ-A–H, D-1–D-14, tasks 1–8, and test-spec coverage. Altitude resolved at
  drafting (transport + store-load reduction, not state replacement; D-1).
- 2026-09-02 — Revision, cluster A of the halted kickoff's worklist
  (meaning-class; contradictions resolved by operator picklist, brief §8).
  Supersedes REQ-A1.2 → REQ-A1.6 (eligibility derived from session-grade,
  no contract column), REQ-A1.3 → REQ-A1.5 (no-change rule scoped to signal
  paths), REQ-C1.3 → REQ-C1.5 (held surfaced only; synchronous outcomes),
  REQ-H1.1 → REQ-H1.4 (re-validation scoped to upward pointers), D-2 → D-16
  (pointer-only scoped to upward signals), D-6 → D-17 (per-session probe).
  Amended in place: REQ-A1.1, C1.1 (steer-advertising rungs only), D1.2
  (tower session receives; script verb re-reads), D1.3 (subscriber and
  re-arm), F1.3/F1.4 (saturating floor; per-send logging), F1.5
  (model-composed sends only), G1.1, G1.4 (cite the floor); D-3, D-4, D-5,
  D-7, D-9, D-10, D-12, D-14. Goal and scope aligned on demotion (nothing
  removed). Status stays Draft; the re-kickoff walks this revision as its
  delta.
- 2026-09-02 — Revision, clusters B and C of the worklist (meaning-class
  additions; proposals signed off by cluster). New: REQ-H1.3 (single
  enforcement point, from D-12), REQ-G1.6 (no new lifecycle resource class),
  REQ-G1.7 (inter-orchestrator-coordination doctrine amended), D-15
  (doorbell wire grammar). Named: `messaging_cross_machine`,
  `messaging_heal_cadence_seconds`. Amended in place: REQ-A1.1 (version
  threshold is the pin of record), A1.4 (one pin, re-verified per task),
  B1.1/B1.2 (fleet-launched towers named; tower marker as their record),
  D1.2 (cites D-15), E1.1 (the cadence knob), F1.4 (pressure defined as
  the usage gate's rung ≥ `reduce-concurrency`), G1.5; D-4, D-8, D-11,
  D-13, D-16. Tasks: orphan REQs wired (G1.1–G1.3, H1.2), every deliverable
  gated by a Done-when clause, Task 4 gains the tower launch seams, Task 8
  depends on Task 4 (invalidating the brief's 8↛4 non-edge, for the
  re-kickoff), Task 7 gains the injected-clock seam.
- 2026-09-02 — Revision, cluster D of the worklist (expression-only:
  verification-path repairs consistent with the A/B/C decisions). Tags
  corrected (A1.4 test + manual with its CI arm stated as
  self-referential; D1.2 and H1.4 gain the manual arm for model behavior;
  F1.5 manual + design-level; G1.4 test + manual + design-level; C1.4 and
  E1.3 split their platform-guarantee and diff-review clauses out of the
  test arm). Baselines named (A1.5's frozen pre-messaging fixtures, E1.1's
  frozen pre-reduction intervals, Task 6's unmodified liveness tests).
  Unreachable branches repaired (the idle-notice expired case dropped as
  indistinguishable from absent by D-10; the wrong-owner socket branch
  fixture-driven through a test-only owner override; the probe's positive
  branch through a test-only version override). Vacuous Done-when clauses
  replaced by evaluable criteria in Tasks 2, 3, 4, 5, 6, 8; D-8 states the
  collision-rename behavior as unverified with the recorded-outcome rule.
- 2026-09-02 — Revision, cluster E of the worklist (evidence hygiene;
  meaning-class for D-18, expression-only otherwise). Observation state
  restored to what the bundle mined: obs:67861aa6, obs:8b694bdb,
  obs:eea622de, obs:58aa232e moved back to live entries with their
  Consumed-by lines removed; the last three become cited-not-consumed and
  obs:67861aa6 is no longer cited (mischaracterized at drafting). New
  D-18 backs REQ-F1.1; D-7 extended in place with the socket path
  propagation mechanism behind REQ-D1.5 and cites obs:2bea1358. Citation
  repairs: REQ-C1.4 cites the inter-orchestrator-coordination doctrine;
  REQ-G1.3's copied floor list replaced by citations; D-8 and D-11 name
  their precedents. Ownership: the merge-ready push entry softened to the
  doctrine's assignment plus the pending note; a new out-of-scope entry
  routes general profile delivery to the `worker-permission-ergonomics`
  amendment, cross-referenced from REQ-F1.1 and Sources.
- 2026-09-02 — Revision, cluster F of the worklist (expression-only, one
  terminology sweep; this entry is the record, no per-record annotations).
  Term mapping applied across all four files: "capability"/"property" for
  messaging → "availability" (per session) and "eligibility" (per rung);
  "peer-messaging" → "cross-session messaging"; ladder "rung" → "value"
  (rung is reserved for backends and the usage gate); "message discipline"
  → "messaging discipline"; "reconcile floor/poll" → "healing sweep" and
  "healing cadence"; "store-load diet" → "store-load reduction"; ladder
  "park" → "operator handoff"; doctrine references by doctrine name;
  "tower-guard" → "tower command-guard"; "bare mode" → "interactive
  (non-`-p`)"; rung-generic ladder statements say "attributed steer
  delivery", not "paste"; "fleet profiles" → the shipped settings
  profiles by file name; "worker/scope registry" → "worker registry";
  "task ledger" → "the `tasks.md` record"; "store lock" → "fleet lock";
  "mode state" → "discipline state"; contract rung ids backticked; the
  delivery-outcome set written in one order (accepted, held, refused,
  dropped, expired); "inbox address" → "inbox socket path". Superseded
  records keep their original wording.
- 2026-09-03 — Revision at the resumed kickoff (worklist 2, brief §8;
  meaning-class, dispositioned by operator picklist; record annotations
  carry the event label "kickoff 2026-09-02 (resumed)", the session's start
  date, while supersession pointers and the `R2` origin tag carry this
  entry's date). The cluster-F sweep's "bare mode" → "interactive (non-`-p`)"
  substitution is reverted: only `--bare` sessions bind no inbox (docs
  re-read; REQ-A1.6/D-17 gain the non-`--bare` conjunct). Supersedes
  REQ-F1.5 → REQ-F1.6 (cross-machine enforcement is `isolatePeerMachines`;
  the knob is a documented cue) and D-18 → D-19 (messaging keys ride the
  shipped profiles via `--settings`). New: REQ-H1.5 (test-only seams
  refused without `PLANWRIGHT_TEST_SEAM=1`). Amended in place: REQ-A1.1
  (variable, predicate, numeric comparison against the documented
  minimum), A1.4 (minimum vs last-verified pin, with initial values and the
  raise-only rule), A1.5, A1.6, B1.1 (session-grade tower launches), B1.2
  (per-worker state file; marker readers), C1.5 (the synchronous outcome
  premise marked unverified with a write-success fallback; dropped/expired
  downward recovery is surface-only), D1.1 (posting verbs; no worker-model
  turn), D1.3 (accept defined; one re-subscribe rule), D1.4
  (lost/dropped/expired), D1.5 (every tower's marker; lookup key;
  predicate home; notice), E1.1 (consumers by path; trigger; interval
  precedence), F1.1, F1.3 (tower↔tower direction), F1.4 (stderr notice),
  G1.1 (observable failures; D-13's path set), G1.3 (never-auto-merge
  cited), G1.5 (file name, manifest lines, contents), G1.6 (one row in the
  floor's class table), G1.7 (two more sentences), H1.3 (literal audit;
  discipline enforcement dropped); D-1, D-3 (title), D-4, D-5, D-7, D-8,
  D-9, D-10, D-11, D-12, D-13, D-14, D-15, D-16, D-17. Tasks and test-spec
  re-paired with every change; Done-when clauses gate every deliverable;
  `[manual]` carried inline. Second terminology sweep and citation repairs
  as the brief lists (clusters I and J). The mid-walk lens over these
  edits (brief §8) then corrected: the attention store's write verbs are
  `heartbeat`, `decide`, `fork`, `park`; the handle grammar's owner is
  `orchestrate-relay.sh`; the worker's socket record is a registry basename
  field and the per-worker messaging log is dropped (notices to stderr); the
  marker gains two fields with its writer and readers named; the probe
  compares against 2.1.248 unconditionally; the initial pin is 2.1.259; the
  `--now` seam is dropped (the sweep's pass reads no clock) and
  `--socket-type` added; `PLANWRIGHT_TOWER_INBOX_SOCKET` and `self-socket`
  named; the doorbell and `effective-mode` signatures and the post seam's
  contract pinned; the floor amendment is a row and a column; the
  steer-in-flight heading is amended; the escalation pin in
  `fleet-dispatch-worktree.sh` is re-scoped for the profile path; the
  fallback table is re-verified by Tasks 7 and 8 both. Status stays Draft
  until this kickoff's sign-off.
- 2026-09-04 — Revision at the resumed kickoff, section 3 walk
  (meaning-class; operator decision on the platform experiments recorded
  in brief §8). The upward path is the harness's idle notice plus the
  sweep; worker-side doorbells are retired. Supersedes REQ-D1.1 and
  REQ-D1.5 → REQ-D1.6, REQ-D1.2 and REQ-D1.3 → REQ-D1.7, D-7 → D-20, D-10
  → D-21, D-15 (no replacement grammar; the wire is the harness's).
  Amended in place: the upward scope bullet, REQ-A1.5 (consumer list),
  B1.2 (the marker gains the name only; no tower socket path is ever
  recorded), D1.4, E1.1 (subscribed, not wired), F1.2/F1.3/F1.4 (the
  floor value renamed `doorbell` → `script`), G1.6, H1.3 (the doorbell
  tag and `self-socket` retired), H1.4; D-4, D-8, D-11, D-12
  (`notice-read` replaces `doorbell` / `doorbell-read` / `self-socket`),
  D-13 (the path set), D-16. Tasks and test-spec re-paired. The
  experiments are recorded under Sources. The mid-walk lens over this
  edit then corrected: the registry records the observed session name
  beside the socket basename, both read from `~/.claude/sessions/<pid>.json`;
  `send` gains `--to-worker` (the basename resolved inside
  `fleet-messaging.sh`) and carries the tower→worker direction only; the
  tower↔tower advisory is model-composed (REQ-G1.4, D-14); notice timing
  is stated at enqueue with model visibility at the next turn boundary;
  the `notice-read` name grammar, the `--watch` scoping of the sanction,
  the `inbox=` proxy in REQ-E1.1, the `headless-oneshot` unknown, and the
  turn-boundary delay in REQ-D1.4 are stated; annotations added where the
  changelog named an amendment. At the section-3 walk's failure bite the
  operator chose to make lost downward answers observable: the post carries
  the tower's own inbox socket as its reply address, a drop or expiry
  status frame is handled by exactly one `fleet-decision.sh redeliver`
  (REQ-C1.5, D-9, D-12, Task 5, test-spec C1.5/H1.4), and surface-only
  stands where Task 2's wire step finds no such frame.
- 2026-09-07 — Revision at the resumed kickoff, sections 4–5 walk and the
  terminal sign-off lens pass (meaning-class; operator decisions recorded
  in brief §8). At the section-4
  sanity check (two reviewers; experiment E4) the operator chose the
  event-driven watch loop: new REQ-D1.8 and D-22 (turn per step, woken by
  notices, messages, or a timer; an amendment `bootstrap`'s D-38
  must accept); amended in place REQ-A1.1 (inbound-acceptance conjunct),
  B1.1 (identity env at every session-grade seam), B1.2 (read-back by
  checkout path, bounded retry), C1.1 (`stream-json-persistent` answers
  via the control-response verb), C1.5 (message id in the answer artifact,
  held's exit code), D1.6 (mid-turn suspensions are the sweep's), D1.7
  (start-of-tower subscribe pass, recorded-name addressing, ambiguous and
  empty cases, ordering), E1.1 (live-subscriber trigger, operator-facing
  cadences kept, cadence bounded), G1.5; D-3, D-8, D-9, D-11, D-12, D-13,
  D-19, D-20,
  D-21; the goal's delivery wording. The mid-walk lens over that edit
  (two Opus reviewers) then corrected: the watchdog cannot stand in for
  the timer (it exits on an interactive marker and posts nothing), so the
  timer is the harness's scheduled wakeup alone, with the metronome kept
  where it is unavailable, where the probe reads absent, for a `-p`
  tower, and for a step with no wake source; workers record their own
  name and socket basename from their own session record through a
  SessionStart hook (`self-register`, `fleet-state.sh amend`), no seam
  read-back; the marker is written at loop start again; the message id
  and the `redelivered` mark live in a per-fork metadata sibling, never
  in the delivered artifact; the decision channel refuses
  `stream-json-persistent`, whose supervisor verb answers from the decide
  row's request id; the two guard re-scopes are dropped (the seam builds
  its own launch line and the guard auto-approves planwright scripts);
  Task 3 keeps the profiles and gates `check:hook-contracts`, the seam
  wiring moves to Task 4; REQ-E1.1's trigger rests on recorded facts,
  the watcher's reconcile period is preserved, its bring-up documented;
  the D-38 amendment is `bootstrap`'s; REQ-A1.1 gains the seam-exported
  inbound layer; D-17 and D-16 annotated; `R4` tags D-22. At the section-5
  walk the operator adopted three long-term forms: a local-only fleet smoke
  runner as the standing drift check (new REQ-A1.7, D-23; Task 7 ships it
  and runs it as its capstone), the `off` switch value of
  `messaging_discipline` as the per-fleet kill switch (REQ-F1.2, REQ-A1.1,
  D-4), and a Deferred gate on Task 6's loop change until bootstrap's D-38
  amendment, drafted through `/spec-draft --extend bootstrap`, is signed
  (REQ-D1.8, D-22). The terminal sign-off lens pass (four Opus lenses over
  the full bundle: contract and ambiguity, citations and cross-file, dead
  verification paths and testability, glossary and drift; dispositioned by
  operator picklist) then corrected: Task 7's capstone notice-wake step,
  its duty-cycle figure, REQ-D1.7's notice-consumption criterion, and
  REQ-E1.1's loop-reads half join Task 6's Deferred gate, the pre-gate
  circuit passing when the metronome tower acts on the park;
  `scripts/fleet-tower-launch.sh` carries the meta-tower's subordinate and
  the continue-as-new handover so the tower command-guard approves them
  wholesale; `send` mints the message id itself and posts no auth line;
  the metadata sibling is one `answers/<worker>.meta` holding a record per
  fork instance id; the deep-reconcile recompute is
  `max(1, round(300 / cadence))` and the `--max-age` refusal is dropped;
  the registry reader set is re-derived by grep and its columns hold bare
  values under last-record-wins; `self-register` writes nothing for a
  tower and a new `self-name` verb reads the loop's marker name; a drop,
  expiry, or refused frame runs `redeliver` while a held frame runs the
  step's own action; the wake-source order and the exported inbound
  layer's precedence are stated; the `stream-json-persistent` tower reads
  its request id from `fleet-streamjson.sh status`; `off` stops every
  model-composed send and an unknown value reads absent; exit 4 keeps both
  of today's sub-cases; a mid-turn suspension surfaces as a stale
  heartbeat; the drift guard's fixture lives under `tests/`; header
  citations are the six scripts the test spec names; the live smoke
  circuit alone is kept out of CI; and the `--settings` live check and
  migration are Task 4's. Amended in place: REQ-A1.1, A1.4, A1.7, B1.1,
  B1.2, C1.1, C1.5, D1.6, D1.7, D1.8, E1.1, F1.1, F1.2, G1.5, H1.2, H1.3;
  D-3, D-4, D-8, D-9, D-11, D-12, D-16, D-19, D-20, D-22, D-23. Wording:
  the retired
  read-back in D-8's title and rationale, D-16's title, D-11's six
  wire-step behaviors, D-13's contents split, the `name` and `inbox`
  columns, "the attributed steer delivery" for "paste" in rung-generic
  sentences, the sanction sentence, the sweep-name distinction stated in
  REQ-E1.2, annotation order and placement, the Sources observation
  grouping, and `orchestrate-backends.sh caps`.

## Sources

- **The invocation seed (operator, 2026-08-27).** "Can we implement
  [cross-session messaging] to communicate with other sessions so that we use
  this instead of serialized JSON persistent? Could we manage state with it
  better?" — carries the pinned altitude claim *"instead of serialized JSON
  persistent"*, an altitude assertion reconciled at drafting: resolved to
  transport + store-load reduction, recorded as D-1.
- **research: Claude Code cross-session messaging docs**
  (code.claude.com/docs/en/cross-session-messaging, read 2026-08-27 and
  re-read 2026-09-02; CLI 2.1.247 verified on the drafting host and 2.1.259
  on the kickoff host, both interactive sessions with the inbox socket
  bound, and 2.1.261 on the `-p` worker the platform experiments launched
  on the kickoff host, which bound one too). Establishes:
  plain-text-only messages; accepted, held, refused,
  dropped, and expired semantics with sender-side notices (shown when the
  sender is an interactive session; no response line to a raw socket post
  is documented, D-12); burst and loop throttling; per-session inbox
  sockets restricted to the OS user, postable by scripts as one complete
  line within 30 s with an optional auth line, the path and token exported
  as `CLAUDE_CODE_MESSAGING_SOCKET` / `CLAUDE_CODE_MESSAGING_TOKEN`;
  `notify_when_idle` one-shot notices (same-machine, main-conversation
  subscriber only, 12-hour expiry, no tokens spent in the watched session;
  CLI 2.1.236 in both sessions); inbound-control classes keyed on
  permission modes, with `crossSessionInbound: accept` deliverable through
  a `-p` session's `--settings` value; interactive and `-p` sessions bind
  inboxes alike, `--bare` sessions bind none; the feature floor is CLI
  2.1.224 (2.1.248 on non-Anthropic providers or with feature-flag fetching
  off); `isolatePeerMachines: true` from any scope prompts before every
  cross-machine send, even in bypass mode; an interactive start, resume, or
  rename onto a used name is renamed to a variant (`-p --name` collisions
  are not stated); messages cannot approve permissions, run commands, or
  change configuration.
- **obs:efe0b752** — decision channel closes the fork before delivery is
  confirmed (the delivery-ACK gap REQ-C1.2/D-9 narrows).
- **obs:b7618838** — tower command-guard defers the attributed `tmux` relay
  send shape (friction the messaging-first ladder removes).
- **obs:d4d66281** — worker identity env never wired at dispatch, leaving
  workers on the capture-pane fallback (REQ-B names identity at launch).
- **Cited, still live** (evidence for decisions here, and their defects
  remain live for their own specs): obs:16facd5b (harness hook-contract
  drift, the WorktreeCreate incident behind D-11), obs:b47b3043 and
  obs:404d3b7b (same-user-writable trust surfaces behind REQ-H1.4),
  obs:8b694bdb (the
  uncached dashboard oracle probe: the duty-cycle evidence behind
  REQ-E1.1, whose stated fix — source-reader caching — is outside the
  reduction's scope), obs:eea622de, obs:a4a4fa59, and obs:58aa232e (the
  worker-settings
  delivery gap, the dead `--settings` hook path, and the permission-class
  keys that do apply that way: they constrain
  REQ-F1.1's wiring, and the `worker-permission-ergonomics` amendment owns
  their fix), obs:fbb701bc (the identity environment exported only on the
  `headless-oneshot` seam, the precondition REQ-B1.1 closes).
- **Cited, consumed elsewhere** (evidence for decisions here, already
  consumed by another bundle): obs:bfc6faf0 (the push-over-poll incident,
  consumed by `tower-front-door`; the merge-ready push it seeds is
  `merge-currency-guard`'s), obs:2bea1358 (audit-trail write amplification
  under the fleet lock, consumed by `tower-front-door`, the
  reason D-12 keeps send visibility out of the audit trail), obs:4c25e743
  (a worker blocked at a deferred prompt is indistinguishable from a
  working one, consumed by `fleet-lifecycle-closure`: mid-turn suspensions
  are the sweep's case, REQ-D1.6). The
  2026-08-27 draft had consumed obs:8b694bdb, obs:eea622de, obs:58aa232e,
  and obs:67861aa6; the 2026-09-02 revision restored all four to live, and
  obs:67861aa6 (CI wall-clock against the tool-call ceiling) is no longer
  cited: none of its asks appear in this bundle.
- **Pending note `specs/_pending/merge-currency-guard-amendment.md`** —
  the deterministic PR-ready push seed; stays pending for
  `merge-currency-guard`, cross-referenced by the out-of-scope entry above.
- **Pending note
  `specs/_pending/worker-permission-ergonomics-amendment.md`** — routes
  profile delivery at dispatch (obs:eea622de) and the dead `--settings`
  hook (obs:a4a4fa59) to that bundle's amendment; cross-referenced by the
  out-of-scope entry and REQ-F1.1 above. The `--settings` observation
  behind Task 3's wiring is obs:58aa232e, not this note.
- **Platform experiments (kickoff host, 2026-09-04; brief §8, "Platform
  experiments").** E1: a raw `nc -N -U` post to a session's own inbox was
  delivered in about 100 ms and the connection returned nothing. E2: a
  `claude -p` worker launched with `--settings {crossSessionInbound:
  accept}` and `--name` appeared in the listing within 2 s and read a
  `SendMessage` mid-turn; a raw post from its Bash to the tower session was
  delivered, not held, in about 1 s, returning nothing. E3: the
  `notify_when_idle` notice was enqueued at the tower 1 s after the
  worker's turn ended, carrying its closing line, and reached the tower's
  model at its next turn boundary (a peer message is read between tool
  calls; an idle notice at turn start). Its rendered line:
  `[Cross-session idle notice] "<name>", which you asked to be notified
  about, is idle now — it finished a turn at HH:MM. Its harness reports:
  «<closing line>»`. The CLI also keeps a per-session record at
  `~/.claude/sessions/<pid>.json` (observed fields: `name`, `nameSource`,
  `kind`, `status`, `cwd`, `messagingSocketPath`, beside a `.key` auth
  file), which is the record `self-register` reads, D-8; both are
  undocumented
  surfaces the drift guard freezes. E4 (2026-09-07): an interactive `claude`
  in a tmux window, named and set to accept, was woken from idle by a peer
  message and, separately, by an idle notice — each started a new turn
  within seconds; a busy session reads a message between tool calls and a
  notice only at its next turn boundary (E3). The CLI binary's own strings
  give the
  wire format (JSON lines: optional auth, then a `type: user` message) and
  show held / refused / dropped as status frames addressed to the sender's
  reply address, not the posting connection. `inotifywait` and `fswatch`
  are absent on the kickoff host.
- **Pending note `specs/_pending/bootstrap-amendment.md`** (Task 6 ships
  it) — routes the retirement of bootstrap D-38's `--watch` metronome, the
  event-driven loop REQ-D1.8/D-22 replaces it with, to that bundle's
  amendment.
- **Observed on the kickoff host (2026-09-07):** a session's own process
  id is exported to its Bash tool as `CLAUDE_PID` and names its
  per-session record; that record carries no inbound-control field. The
  plugin already registers a SessionStart hook, and obs:58aa232e observed
  plugin SessionStart hooks firing in `-p` sessions.
- **Prior bundles:** `bootstrap` (D-38, the control-tower dispatch loop
  this bundle's D-22 amends), `orchestration-fleet` (the
  inter-orchestrator-coordination
  doctrine and the backend capability contract),
  `concurrent-orchestrator-coordination` (presence, fences,
  single-host posture), `fleet-hardening` (decision channel, attention push),
  `fleet-autonomy` (attention store, monitors, the no-LLM-daemon-mechanics
  floor its D-18 records),
  `execution-backends` (contract extension precedent, launch pinning).
