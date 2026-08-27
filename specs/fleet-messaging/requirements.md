# Fleet Messaging — Requirements

**Status:** Draft
**Last reviewed:** 2026-08-27
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright's fleet signals — worker→tower attention and decision forks,
tower→worker steering and answers, completion notices — ride mechanisms built
before the harness had any native inter-session channel: `capture-pane`
screen-scraping, tmux buffer-paste, and a file store that doubles as durable
record *and* signaling bus, so every signal pays a store write under a
contended lock and every consumer polls. Claude Code now ships cross-session
messaging (`ListAgents`/`SendMessage`, per-session inbox sockets, one-shot
idle notices): attributed and non-impersonating by construction, delivered
mid-turn without polling. This bundle adopts it as the fleet's preferred
**signal transport** where available, and takes the accompanying **store-load
diet**: retire store reads and poll cadences that exist only for signaling,
while every durable record stays file/git-based and level-triggered. It is a
transport layer, not a state-store replacement (the altitude call is D-1).
Every messaging path degrades to today's mechanism when the feature is absent
(version, provider, feature flags), and no signal is ever correctness-critical.

## Scope

### In scope

- Deterministic availability probing, and per-rung advertisement of the
  messaging capability through the backend capability contract's property
  mechanism.
- Deterministic session identity: fleet-launched sessions named from the
  existing handle grammar so they are addressable peers.
- Downward delivery (tower→worker steer and decision answers) over messaging,
  messaging-first on every rung that accepts it, with the existing attributed
  buffer-paste path as fallback.
- Upward signals (worker→tower attention, decision forks, completion): the
  store row remains the record; a hook-posted doorbell or an idle notice
  replaces the tower's signal-polling.
- The store-load diet: demoting signal-purpose poll cadences to a documented
  low-cadence reconcile floor wherever a push path is advertised and wired.
- Settings and profile wiring: worker inbound-message acceptance, tower
  profiles, the `messaging_discipline` knob, and the cross-machine opt-in.
- Tower↔tower advisory messages (the hand-relay replacement), bound by the
  nothing-on-the-correctness-path rule.
- A doctrine statement (`doctrine/messaging-transport.md`) making the
  signal-vs-record rule and the discipline ladder citable.

### Out of scope

- **Moving any state of record onto messages.** Messages are lossy, ephemeral,
  and model-turn-bound; the registry, fences, audit trail, and ledger stay
  file/git-based (D-1).
- **Fixing the store's lost-append and lock-race defects.** This bundle only
  reduces the store's signal-rate load; store hardening remains its own spec,
  and the relevant observations stay live for it.
- **The operator-facing merge-ready push.** `merge-currency-guard` owns it. A
  message delivered to a *tower* is still an LLM path and never satisfies the
  deterministic-attention floor.
- **Reopening `concurrent-orchestrator-coordination`'s signed design.** Its
  file-based presence surface and origin fences stay authoritative; this
  bundle adds an advisory layer only.
- **LLM-in-daemon mechanics.** Daemons are not sessions and receive nothing;
  the no-LLM-daemon-mechanics floor carries unchanged.
- **Observe-in-flight.** Messaging carries signals, not live worker output;
  screen/stream observation keeps its existing mechanisms.
- **Cross-machine fleets as a default posture.** Cross-machine messaging
  exists only behind the opt-in knob and per-send operator approval (D-5);
  remote sessions are not fleet peers for presence, liveness, or dispatch.
- **Agent teams and workflows.** The Claude-Code-primitives-only principle
  carries; this bundle adopts the messaging primitive alone.

## REQ-A — Availability & advertisement

- **REQ-A1.1** Messaging availability SHALL be determined by a deterministic
  probe (inbox-socket environment presence plus CLI version comparison), never
  assumed from configuration or memory.
  *(Cites: D-6, D-11.)*
- **REQ-A1.2** The capability SHALL be advertised per backend rung through the
  backend capability contract's property mechanism; an unknown, unprobeable,
  or malformed advertisement reads as absent (fail-safe), and rungs with no
  session socket (in-harness subagents, `in-session`) are structurally
  without it.
  *(Cites: D-6.)*
- **REQ-A1.3** Where the capability is absent, every consumer SHALL behave
  exactly as it does today: adoption changes no behavior for a host, provider,
  or session without messaging.
  *(Cites: D-1, D-6.)*
- **REQ-A1.4** The platform contract this bundle consumes (environment
  variables, socket protocol, tool semantics, version gates) SHALL be pinned
  to a verified CLI version per task and guarded by fixture tests, so contract
  drift fails visibly, never as a silent no-op.
  *(Cites: D-11, obs:16facd5b, research: Claude Code cross-session messaging
  docs (Sources).)*

## REQ-B — Addressable identity

- **REQ-B1.1** Fleet-launched sessions (workers and towers) SHALL be named
  deterministically from the existing fleet handle grammar via the launch
  `--name` mechanism, so every fleet peer is addressable without listing
  round-trips.
  *(Cites: D-8, obs:d4d66281.)*
- **REQ-B1.2** The actual post-launch name SHALL be read back and recorded in
  the worker/scope registry (the CLI renames collisions to variants; the
  recorded name is the observed one, never the requested one assumed).
  *(Cites: D-8.)*
- **REQ-B1.3** Names and addresses SHALL be validated against their declared
  grammar as data before any use in addressing, paths, or echoed output.
  *(Cites: D-8; the security-posture doctrine.)*

## REQ-C — Downward delivery

- **REQ-C1.1** Tower→worker steer and decision-answer delivery SHALL prefer
  messaging on every rung that advertises and accepts it, tmux included, with
  the fallback ladder: messaging → the rung's existing attributed delivery →
  park for the operator.
  *(Cites: D-3, obs:b7618838.)*
- **REQ-C1.2** A decision answer SHALL be claimed under the store lock and its
  answer artifact persisted before any delivery attempt; a failed delivery
  never re-opens or re-claims the fork.
  *(Cites: D-9, obs:efe0b752.)*
- **REQ-C1.3** The sender SHALL consume the harness's delivery outcomes (held,
  refused, dropped, expired) and take the next fallback rung rather than
  assume delivery; an unconfirmed delivery is surfaced, never silently
  presumed successful.
  *(Cites: D-9.)*
- **REQ-C1.4** Delivery SHALL never impersonate the worker's input and never
  answer a worker's permission prompt; message text is data end to end, with
  no eval or expansion path.
  *(Cites: D-3; carried orchestration-fleet relay doctrine.)*

## REQ-D — Upward signals

- **REQ-D1.1** Routine worker→tower signals (attention rows, decision forks,
  parks) SHALL be pushed by deterministic hook-posted doorbells — a script
  posting to the tower's inbox socket — with no model turn on the routine
  path.
  *(Cites: D-7.)*
- **REQ-D1.2** A doorbell SHALL carry only a minimal, grammar-validated
  pointer payload; the receiver acts on a store re-read, never on doorbell
  content.
  *(Cites: D-2, D-7.)*
- **REQ-D1.3** Completion and idle signaling SHALL use the harness's one-shot
  idle-notice subscription where both sessions accept it, as a supplement
  only: positive-evidence-of-death liveness is unchanged, and the absence of
  a notice is never read as a signal.
  *(Cites: D-10, obs:67861aa6.)*
- **REQ-D1.4** A lost, held, or dropped signal SHALL be healed by the retained
  level-triggered reconcile; no messaging signal is correctness-critical.
  *(Cites: D-2.)*
- **REQ-D1.5** The tower's inbox address SHALL reach dispatched workers
  deterministically — set in the dispatch environment at launch, with the
  tower's registry/marker record as the fallback — and be validated before
  use (an existing socket owned by the invoking user); a missing or invalid
  address degrades the doorbell path to the reconcile floor, never an error
  loop.
  *(Cites: D-7.)*

## REQ-E — Store-load diet

- **REQ-E1.1** Wherever a push path is advertised and wired, signal-purpose
  polling (attention-store watches, status/dashboard signal reads) SHALL
  demote to a documented low-cadence reconcile floor.
  *(Cites: D-2, obs:8b694bdb.)*
- **REQ-E1.2** The reconcile poll SHALL never be removed: the channel is lossy
  by contract, so level-triggered derivation from ground truth remains the
  healing path at every discipline mode.
  *(Cites: D-2.)*
- **REQ-E1.3** The diet SHALL NOT change record semantics: no store write is
  removed and no record moves; only signal-purpose reads and cadences change.
  *(Cites: D-1, D-2.)*

## REQ-F — Settings & discipline

- **REQ-F1.1** Dispatched worker settings SHALL enable unattended inbound
  acceptance (`crossSessionInbound: accept`) through a mechanism verified to
  apply in that rung's session type, and delivering those settings to the
  worker is part of the dispatch seam, not operator memory.
  *(Cites: D-3, obs:eea622de, obs:58aa232e.)*
- **REQ-F1.2** Message discipline SHALL be a config knob
  (`messaging_discipline`), laddered `doorbell` < `tiered` < `open`, default
  `tiered`, resolved through the standard overlay layers.
  *(Cites: D-4; the customization-boundary doctrine.)*
- **REQ-F1.3** The discipline SHALL be direction-aware: worker→tower stays one
  rung more permissive than tower→worker at the same setting, because towers
  absorb interrupts and workers need focus.
  *(Cites: D-4.)*
- **REQ-F1.4** The effective mode SHALL be evaluated at send time by
  deterministic script logic over the existing budget/usage monitors — one
  rung down under reported pressure, restored when pressure clears, logged
  each time — with no stored mode state and no LLM in the demotion decision.
  *(Cites: D-4.)*
- **REQ-F1.5** A cross-machine send SHALL require both the opt-in config knob
  and per-send operator approval; fleet profiles recommend
  `isolatePeerMachines: true` so nothing leaves the machine silently.
  *(Cites: D-5.)*

## REQ-G — Degradation & carried floors

- **REQ-G1.1** Every messaging path SHALL name its deterministic fallback —
  the pre-messaging mechanism it replaces — and reach it on absence, refusal,
  or failure without operator intervention.
  *(Cites: D-1, D-3, D-6.)*
- **REQ-G1.2** No state of record SHALL ride the messaging layer; a message
  that must survive a crash was mis-sent, and the record it points at is the
  durable artifact.
  *(Cites: D-1, D-2.)*
- **REQ-G1.3** The existing floors carry unchanged: no LLM in daemon
  mechanics, never-impersonate, the tower non-authoring boundary, no
  auto-merge, and the deterministic-attention floor — a message to a tower
  never substitutes for the operator-facing deterministic push.
  *(Cites: D-1; the fleet-coordination-floor doctrine.)*
- **REQ-G1.4** Tower↔tower messages SHALL be advisory only: a message never
  claims, releases, or resolves a unit of work — the origin fence and the
  presence surface stay the sole authorities on division of work.
  *(Cites: D-14.)*
- **REQ-G1.5** The signal-vs-record rule, the fallback obligation, and the
  discipline ladder SHALL ship as a doctrine document
  (`doctrine/messaging-transport.md`) that skills and scripts cite, rather
  than living only inside this bundle.
  *(Cites: D-13.)*

## REQ-H — Security & hygiene

- **REQ-H1.1** Inbound message and doorbell content SHALL be treated as
  untrusted input: the inbox socket is writable by any same-OS-user process,
  so receivers grammar-screen, length-bound, and echo-sanitize the content
  and act only on what the store or git ground truth re-validates.
  *(Cites: D-7; the security-posture doctrine; obs:b47b3043, obs:404d3b7b.)*
- **REQ-H1.2** Message text SHALL carry no secrets, credentials, or sensitive
  operational detail; cross-machine messages transit third-party
  infrastructure and are held to committed-artifact hygiene.
  *(Cites: D-5; the security-posture doctrine.)*

## Changelog

- 2026-08-27 — Initial draft elicited via `/spec-draft`: goal, scope,
  REQ-A–H, D-1–D-14, tasks 1–8, and test-spec coverage. Altitude resolved at
  drafting (transport + store-load diet, not state replacement; D-1).

## Sources

- **The invocation seed (operator, 2026-08-27).** "Can we implement
  [cross-session messaging] to communicate with other sessions so that we use
  this instead of serialized JSON persistent? Could we manage state with it
  better?" — carries the pinned altitude claim *"instead of serialized JSON
  persistent"*, an altitude assertion reconciled at drafting: resolved to
  transport + store-load diet, recorded as D-1.
- **research: Claude Code cross-session messaging docs**
  (code.claude.com/docs/en/cross-session-messaging, read 2026-08-27; CLI
  2.1.247 verified on the drafting host, inbox socket bound). Establishes:
  plain-text-only messages; hold/refuse/expire/drop semantics with sender-side
  notices; burst and loop throttling; per-session inbox sockets restricted to
  the OS user, postable by scripts; `notify_when_idle` one-shot notices
  (same-machine, main-conversation subscriber only, 12-hour expiry, no tokens
  spent in the watched session); inbound-control classes keyed on permission
  modes; `-p` sessions bind inboxes, bare mode does not; provider and
  feature-flag availability gating; messages cannot approve permissions, run
  commands, or change configuration.
- **obs:efe0b752** — decision channel closes the fork before delivery is
  confirmed (the delivery-ACK gap REQ-C1.2/D-9 narrows).
- **obs:b7618838** — tower command-guard defers the attributed tmux relay
  send shape (friction the messaging-first ladder removes).
- **obs:eea622de** — worker-settings delivery gap: dispatched workers sat
  ~8 hours on unanswered prompts because no step delivered their settings
  profile (REQ-F1.1 folds delivery into the dispatch seam).
- **obs:d4d66281** — worker identity env never wired at dispatch, leaving
  workers on the capture-pane fallback (REQ-B names identity at launch).
- **obs:8b694bdb** — dashboard polling pays an uncached 2–10s oracle probe
  per tick (the diet's motivating duty-cycle evidence, REQ-E1.1).
- **obs:67861aa6** — long-running work stalls unnoticed because completion
  signaling relies on polling (REQ-D1.3's idle-notice case).
- **obs:58aa232e** — hooks in a `--settings` file never register in `-p`
  sessions; the verified working pattern constrains REQ-F1.1's wiring.
- **Cited, not consumed** (evidence for decisions here, but their defects
  remain live for their own specs): obs:16facd5b (harness hook-contract
  drift, the WorktreeCreate incident behind D-11), obs:b47b3043 and
  obs:404d3b7b (same-user-writable trust surfaces behind REQ-H1.1),
  obs:bfc6faf0 (push-over-poll incident owned by `merge-currency-guard`).
- **Pending note `specs/_pending/merge-currency-guard-amendment.md`** —
  the deterministic PR-ready push seed; stays pending for
  `merge-currency-guard`, cross-referenced by the out-of-scope entry above.
- **Prior bundles:** `orchestration-fleet` (relay doctrine, capability
  contract), `concurrent-orchestrator-coordination` (presence, fences,
  single-host posture), `fleet-hardening` (decision channel, attention push),
  `fleet-autonomy` (attention store, monitors, D-18 floor),
  `execution-backends` (contract extension precedent, launch pinning).
