# Fleet Messaging — Requirements

**Status:** Draft
**Last reviewed:** 2026-09-02
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
idle notices): attributed and non-impersonating by construction, delivered
mid-turn without polling. This bundle adopts it as the fleet's preferred
**signal transport** where available, and takes the accompanying **store-load
reduction**: signal-purpose store reads and poll cadences demote to a
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
  session-grade property.
- Deterministic session identity: fleet-launched sessions (workers, and
  towers launched by the meta-tower or the watchdog) named from the existing
  handle grammar so they are addressable peers.
- Downward delivery (tower→worker steer and decision answers) over messaging,
  messaging-first on every steer-advertising rung that is eligible, with the
  rung's existing attributed steer delivery as fallback.
- Upward signals (worker→tower attention, decision forks, completion): the
  store row remains the record; a hook-posted doorbell or an idle notice
  supplements the tower's signal-polling, which demotes to the healing sweep.
- The store-load reduction: demoting signal-purpose poll cadences to a
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
  messaging settings, through the interim pattern that note also records,
  and adopts the mechanism when it lands (REQ-F1.1).
- **Reopening `concurrent-orchestrator-coordination`'s signed design.** Its
  file-based presence surface and origin fences stay as that bundle and the
  fleet-coordination-floor doctrine place them; this bundle adds an advisory
  layer only.
- **LLM-in-daemon mechanics.** Daemons are not sessions and receive nothing;
  the no-LLM-daemon-mechanics floor carries unchanged.
- **Observe-in-flight.** Messaging carries signals, not live worker output;
  screen/stream observation keeps its existing mechanisms.
- **Cross-machine fleets as a default posture.** Cross-machine messaging
  exists only behind the opt-in knob (`messaging_cross_machine`) and per-send
  operator approval (D-5); remote sessions are not fleet peers for presence,
  liveness, or dispatch.
- **Agent teams and workflows.** The Claude-Code-primitives-only principle
  carries; this bundle adopts the messaging primitive alone.

## REQ-A — Availability & advertisement

- **REQ-A1.1** Messaging availability SHALL be determined per session by a
  deterministic probe (the invoking session's inbox-socket environment
  presence plus CLI version comparison against the pin of record, REQ-A1.4),
  never assumed from configuration or memory; a version below the pin reads
  absent.
  *(Cites: D-17, D-11.)*
  *(Amended at revision 2026-09-02: probe scoped to the invoking session;
  the host-level gate is gone with D-6; the version threshold is the pin.)*
- **REQ-A1.2** The capability SHALL be advertised per backend rung through the
  backend capability contract's property mechanism; an unknown, unprobeable,
  or malformed advertisement reads as absent (fail-safe), and rungs with no
  session socket (in-harness subagents, `in-session`) are structurally
  without it.
  *(Cites: D-6.)*
  **Superseded-by: REQ-A1.6** (2026-09-02) — socket presence is a per-session
  fact, so a per-rung contract property cannot carry it; eligibility is
  derived from the contract's existing session-grade property instead (D-17).
- **REQ-A1.6** (supersedes REQ-A1.2) Per-rung messaging eligibility SHALL be
  derived from the backend capability contract's existing session-grade
  property — a rung whose session-grade is `yes` can bind an inbox socket,
  `no` and `deferred` rungs cannot — with no new contract column or adapter
  field; availability for any send is the per-session probe (REQ-A1.1) in the
  sending session plus a recorded inbox socket path for the target. An unknown or
  malformed session-grade value reads as ineligible (fail-safe).
  *(Cites: D-17.)*
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
  the signal transport (downward delivery, doorbells and idle
  notices, the demoted sweeps) SHALL take exactly today's code path; the
  dispatch-seam preparation that makes a session addressable and accepting
  (REQ-B1.1, REQ-F1.1) is unconditional and inert without messaging.
  *(Cites: D-1, D-17.)*
- **REQ-A1.4** The platform contract this bundle consumes (environment
  variables, socket protocol, tool semantics, version gates) SHALL be pinned
  to one verified CLI version — the pin of record, held in the drift guard's
  fixture — and guarded by fixture tests, so contract drift fails visibly,
  never as a silent no-op. Every task that touches the platform surface
  re-verifies against the running CLI and updates the pin; no task carries
  its own copy.
  *(Cites: D-11, obs:16facd5b, research: Claude Code cross-session messaging
  docs (Sources).)*
  *(Amended at revision 2026-09-02: one pin of record, re-verified per task,
  replacing a per-task pin.)*

## REQ-B — Addressable identity

- **REQ-B1.1** Fleet-launched sessions (workers, and towers launched by the
  meta-tower or the watchdog) SHALL be named deterministically from the
  existing fleet handle grammar via the launch `--name` mechanism, so every
  fleet-launched peer is addressable without listing round-trips. An
  operator-launched tower is not fleet-launched: it is addressed by a
  listing round-trip on the low-rate advisory path only.
  *(Cites: D-8, obs:d4d66281.)*
  *(Amended at revision 2026-09-02: the tower launch seams named and the
  operator-launched carve-out stated.)*
- **REQ-B1.2** The actual post-launch name SHALL be read back and recorded —
  in the worker registry for a worker, in the tower marker for a tower,
  together with the session's inbox socket path (the CLI renames collisions
  to variants; the recorded name is the observed one, never the requested
  one assumed).
  *(Cites: D-8.)*
  *(Amended at revision 2026-09-02: the tower marker named as the tower-side
  record.)*
- **REQ-B1.3** Names and addresses SHALL be validated against their declared
  grammar as data before any use in addressing, paths, or echoed output.
  *(Cites: D-8; the security-posture doctrine.)*

## REQ-C — Downward delivery

- **REQ-C1.1** Tower→worker steer and decision-answer delivery SHALL prefer
  messaging on every rung that advertises steer-in-flight and is eligible
  (REQ-A1.6), `tmux` included, with the fallback ladder: messaging → the
  rung's existing attributed steer delivery → operator handoff. A rung
  without steer-in-flight receives no downward delivery: it holds no fork to
  answer.
  *(Cites: D-3, obs:b7618838.)*
  *(Amended at revision 2026-09-02: rung set pinned to steer-advertising
  eligible rungs; `headless-oneshot` is excluded by its contract row.)*
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
  plus a failed post: refused and a failed post take the next fallback rung;
  held is surfaced as unconfirmed and left queued, never re-sent; accepted
  is not proof of delivery. Outcomes a script cannot observe (dropped,
  expired) are healed by the level-triggered healing sweep (REQ-D1.4), and
  no unconfirmed delivery is ever presumed successful.
  *(Cites: D-9, D-12.)*
- **REQ-C1.4** Delivery SHALL never impersonate the worker's input and never
  answer a worker's permission prompt; message text is data end to end, with
  no eval or expansion path.
  *(Cites: D-3; the inter-orchestrator-coordination doctrine.)*

## REQ-D — Upward signals

- **REQ-D1.1** Routine worker→tower signals (attention rows, decision forks,
  parks) SHALL be pushed by deterministic hook-posted doorbells — a script
  posting to the tower's inbox socket — with no model turn on the routine
  path.
  *(Cites: D-7.)*
- **REQ-D1.2** A doorbell SHALL carry only a minimal, grammar-validated
  pointer payload. The receiver is the tower session, and its only sanctioned
  action on a doorbell is the deterministic store re-read verb, which
  validates the pointer as data and returns store truth; doorbell content
  itself is never acted on. The payload's field set and bounds are the wire
  grammar D-15 fixes.
  *(Cites: D-15, D-16, D-7, D-12.)*
  *(Amended at revision 2026-09-02: receiver named (the tower session) and
  the re-read bound to a script verb.)*
- **REQ-D1.3** Completion and idle signaling SHALL use the harness's one-shot
  idle-notice subscription where both sessions accept it, as a supplement
  only: the tower session subscribes after dispatch and re-arms after each
  downward delivery it makes; positive-evidence-of-death liveness is
  unchanged, and the absence of a notice is never read as a signal.
  *(Cites: D-10.)*
  *(Amended at revision 2026-09-02: subscriber and re-arm policy stated;
  the obs:67861aa6 citation dropped, its subject being CI wall-clock
  against the tool-call ceiling, not completion signaling.)*
- **REQ-D1.4** A lost, held, or dropped signal SHALL be healed by the retained
  level-triggered healing sweep; no messaging signal is correctness-critical.
  *(Cites: D-16.)*
- **REQ-D1.5** The tower's inbox socket path SHALL reach dispatched workers
  deterministically — set in the dispatch environment at launch, with the
  tower's marker record as the fallback — and be validated before use (an
  existing socket owned by the invoking user); a missing or invalid path
  degrades the doorbell path to the healing sweep, never an error loop.
  *(Cites: D-7.)*

## REQ-E — Store-load reduction

- **REQ-E1.1** Wherever a push path is advertised and wired, signal-purpose
  polling (attention-store watches, status/dashboard signal reads) SHALL
  demote to a documented low-cadence healing sweep whose cadence is one
  overlay-resolved knob (`messaging_heal_cadence_seconds`) applied to every
  demoted consumer, never a per-consumer value.
  *(Cites: D-16, obs:8b694bdb.)*
  *(Amended at revision 2026-09-02: the cadence knob named, singular.)*
- **REQ-E1.2** The healing sweep SHALL never be removed: the channel is lossy
  by contract, so level-triggered derivation from ground truth remains the
  healing path at every discipline value.
  *(Cites: D-16.)*
- **REQ-E1.3** The reduction SHALL NOT change record semantics: no store write
  is removed and no record moves; only signal-purpose reads and cadences
  change.
  *(Cites: D-1, D-16.)*

## REQ-F — Settings & discipline

- **REQ-F1.1** Dispatched worker settings SHALL enable unattended inbound
  acceptance (`crossSessionInbound: accept`) through a mechanism verified to
  apply in that rung's session type, and delivering those settings to the
  worker is part of the dispatch seam, not operator memory. The general
  profile-delivery mechanism is owned by the `worker-permission-ergonomics`
  amendment (Sources); this bundle wires the messaging settings through the
  currently verified interim pattern and adopts that mechanism when it
  lands.
  *(Cites: D-18, obs:eea622de, obs:58aa232e.)*
  *(Amended at revision 2026-09-02: backed by D-18; ownership of the
  general delivery mechanism cross-referenced.)*
- **REQ-F1.2** Messaging discipline SHALL be a config knob
  (`messaging_discipline`), laddered `doorbell` < `tiered` < `open`, default
  `tiered`, resolved through the standard overlay layers.
  *(Cites: D-4; the customization-boundary doctrine.)*
- **REQ-F1.3** The discipline SHALL be direction-aware: the knob value names
  the worker→tower value, and tower→worker resolves one value stricter,
  saturating at `doorbell`, because towers absorb interrupts and workers need
  focus. The ladder gates model-composed traffic only; deterministic script
  sends ride at every value.
  *(Cites: D-4.)*
  *(Amended at revision 2026-09-02: knob-to-direction anchoring and the
  saturating floor stated, from the kickoff §3 intent.)*
- **REQ-F1.4** The effective value SHALL be evaluated at send time by
  deterministic script logic over the existing usage gate — one value down
  under reported pressure, saturating at `doorbell`, restored when pressure
  clears, with one log line per send that runs demoted — with no stored
  discipline state and no LLM in the demotion decision. Reported pressure means the
  usage gate's audit-derived rung at or above `reduce-concurrency`, read the
  same way in both directions; the context-budget monitor is not a pressure
  input.
  *(Cites: D-4.)*
  *(Amended at revision 2026-09-02: logging is per demoted send, not per
  transition; the floor and the pressure signal are stated.)*
- **REQ-F1.5** A cross-machine send SHALL require both the opt-in config knob
  (`messaging_cross_machine`, default off) and per-send operator approval. Only a model-composed send can be
  cross-machine (script paths post to a local socket path and are
  same-machine by construction), so the approval gate is the harness's own
  tool-call prompt; the shipped settings profiles carry
  `isolatePeerMachines: true`, and the knob's documented effect is that
  turning it on is the operator's cue to relax that setting.
  *(Cites: D-5.)*
  *(Amended at revision 2026-09-02: scoped to model-composed sends; the
  knob-to-setting relation stated.)*

## REQ-G — Degradation & carried floors

- **REQ-G1.1** Every messaging path SHALL name its deterministic fallback —
  the pre-messaging mechanism it replaces — and reach it on absence, refusal,
  or failure with no operator step to select it; the ladder's terminal
  operator handoff is itself today's mechanism, not an intervention.
  *(Cites: D-1, D-3, D-17.)*
  *(Amended at revision 2026-09-02: "without operator intervention"
  clarified as no operator step to select the fallback.)*
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
  inter-orchestrator-coordination doctrine.)*
  *(Amended at revision 2026-09-02: the copied floor list, which matched
  neither doctrine, replaced by citations.)*
- **REQ-G1.4** Tower↔tower messages SHALL be advisory only: a message never
  claims, releases, or resolves a unit of work; authority over the division
  of work stays exactly where the fleet-coordination-floor doctrine's
  assume-multiplicity floor places it.
  *(Cites: D-14; the fleet-coordination-floor doctrine.)*
  *(Amended at revision 2026-09-02: the restated authority list replaced by
  a citation of the floor.)*
- **REQ-G1.5** The signal-vs-record rule, the fallback obligation, and the
  discipline ladder SHALL ship as a doctrine document
  (the messaging-transport doctrine) that skills and scripts cite, rather
  than living only inside this bundle. The doctrine carries the per-path
  fallback table REQ-G1.1 requires and the cross-machine transit note
  REQ-H1.2 requires.
  *(Cites: D-13.)*
  *(Amended at revision 2026-09-02: the fallback table and transit note
  placed in the doctrine.)*
- **REQ-G1.6** Messaging SHALL acquire no new worker-side resource class
  under the lifecycle-closure floor, and the doctrine document SHALL declare
  so: the inbox socket is harness-owned and closes with the session; the
  idle-notice subscription is tower-side and self-closing (it fires once or
  expires) and needs no detector because silence is never a signal; the
  tower's socket path record rides the tower marker's existing lifecycle.
  *(Cites: D-13; the fleet-coordination-floor doctrine.)*
- **REQ-G1.7** The inter-orchestrator-coordination doctrine SHALL be amended
  in the same delivery as the messaging-transport doctrine: its
  steer-in-flight section becomes messaging-first with attributed
  buffer-paste as the fallback, and its tower↔tower paragraph
  cross-references the advisory rule (REQ-G1.4), so the mechanism of record
  it pins does not contradict this bundle.
  *(Cites: D-13.)*

## REQ-H — Security & hygiene

- **REQ-H1.1** Inbound message and doorbell content SHALL be treated as
  untrusted input: the inbox socket is writable by any same-OS-user process,
  so receivers grammar-screen, length-bound, and echo-sanitize the content
  and act only on what the store or git ground truth re-validates.
  *(Cites: D-7; the security-posture doctrine; obs:b47b3043, obs:404d3b7b.)*
  **Superseded-by: REQ-H1.4** (2026-09-02) — steer text and tower↔tower
  advisories have no artifact to re-validate, so the re-validation clause is
  scoped to upward pointers while the hygiene clause stays universal.
- **REQ-H1.4** (supersedes REQ-H1.1) Inbound message and doorbell content
  SHALL be treated as untrusted input: the inbox socket is writable by any
  same-OS-user process, so every receiver grammar-screens, length-bounds, and
  echo-sanitizes the content. A doorbell or other upward pointer drives
  action only through what the store or git ground truth re-validates;
  steer, answer, and advisory text is instruction data the receiving session
  treats as advisory and never as authority over fences, presence, or the
  `tasks.md` record.
  *(Cites: D-7; the security-posture doctrine; obs:b47b3043, obs:404d3b7b.)*
- **REQ-H1.2** Message text SHALL carry no secrets, credentials, or sensitive
  operational detail; cross-machine messages transit third-party
  infrastructure and are held to committed-artifact hygiene.
  *(Cites: D-5; the security-posture doctrine.)*
- **REQ-H1.3** All messaging mechanics SHALL live in one audited script
  (`fleet-messaging.sh`): the relay and the decision channel deliver by
  delegation, and no other shipped script posts to an inbox socket or parses
  a doorbell, so validation, data-only handling, and discipline enforcement
  have exactly one home.
  *(Cites: D-12.)*

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

## Sources

- **The invocation seed (operator, 2026-08-27).** "Can we implement
  [cross-session messaging] to communicate with other sessions so that we use
  this instead of serialized JSON persistent? Could we manage state with it
  better?" — carries the pinned altitude claim *"instead of serialized JSON
  persistent"*, an altitude assertion reconciled at drafting: resolved to
  transport + store-load reduction, recorded as D-1.
- **research: Claude Code cross-session messaging docs**
  (code.claude.com/docs/en/cross-session-messaging, read 2026-08-27; CLI
  2.1.247 verified on the drafting host, inbox socket bound). Establishes:
  plain-text-only messages; hold/refuse/expire/drop semantics with sender-side
  notices; burst and loop throttling; per-session inbox sockets restricted to
  the OS user, postable by scripts; `notify_when_idle` one-shot notices
  (same-machine, main-conversation subscriber only, 12-hour expiry, no tokens
  spent in the watched session); inbound-control classes keyed on permission
  modes; `-p` sessions bind inboxes, interactive (non-`-p`) sessions do not;
  provider and feature-flag availability gating; messages cannot approve
  permissions, run commands, or change configuration.
- **obs:efe0b752** — decision channel closes the fork before delivery is
  confirmed (the delivery-ACK gap REQ-C1.2/D-9 narrows).
- **obs:b7618838** — tower command-guard defers the attributed tmux relay
  send shape (friction the messaging-first ladder removes).
- **obs:d4d66281** — worker identity env never wired at dispatch, leaving
  workers on the capture-pane fallback (REQ-B names identity at launch).
- **Cited, not consumed** (evidence for decisions here, but their defects
  remain live for their own specs): obs:16facd5b (harness hook-contract
  drift, the WorktreeCreate incident behind D-11), obs:b47b3043 and
  obs:404d3b7b (same-user-writable trust surfaces behind REQ-H1.4),
  obs:bfc6faf0 (push-over-poll incident owned by `merge-currency-guard`),
  obs:2bea1358 (audit-trail write amplification under the fleet lock, the
  reason D-7 keeps sends out of the audit trail), obs:8b694bdb (the
  uncached dashboard oracle probe: the duty-cycle evidence behind
  REQ-E1.1, whose stated fix — source-reader caching — is outside the
  reduction's scope), obs:eea622de and obs:58aa232e (the worker-settings
  delivery gap and the dead `--settings` hook path: they constrain
  REQ-F1.1's wiring, and the `worker-permission-ergonomics` amendment owns
  their fix). The 2026-08-27 draft had consumed the last three and
  obs:67861aa6; the 2026-09-02 revision restored all four to live, and
  obs:67861aa6 (CI wall-clock against the tool-call ceiling) is no longer
  cited: none of its asks appear in this bundle.
- **Pending note `specs/_pending/merge-currency-guard-amendment.md`** —
  the deterministic PR-ready push seed; stays pending for
  `merge-currency-guard`, cross-referenced by the out-of-scope entry above.
- **Pending note
  `specs/_pending/worker-permission-ergonomics-amendment.md`** — routes
  profile delivery at dispatch (obs:eea622de) and the dead `--settings`
  hook (obs:a4a4fa59) to that bundle's amendment; cross-referenced by the
  out-of-scope entry and REQ-F1.1 above, and the source of the interim
  wiring pattern Task 3 uses.
- **Prior bundles:** `orchestration-fleet` (relay doctrine, capability
  contract), `concurrent-orchestrator-coordination` (presence, fences,
  single-host posture), `fleet-hardening` (decision channel, attention push),
  `fleet-autonomy` (attention store, monitors, the no-LLM-daemon-mechanics
  floor its D-18 records),
  `execution-backends` (contract extension precedent, launch pinning).
