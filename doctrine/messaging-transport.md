# Messaging Transport

Claude Code's cross-session messaging (per-session inbox sockets, the
`SendMessage` and `ListAgents` tools, one-shot idle notices) is the fleet's
preferred **signal transport** where a session has it. It is a transport, never
a state store: files and git stay the record, every messaging path keeps a
deterministic fallback, and no signal is ever correctness-critical. One audited
script, `scripts/fleet-messaging.sh`, carries every script-side post and check;
the relay and the decision channel deliver through it. The paths land in
stages: until a path's script ships, that path runs as its fallback.

Citations: fleet-messaging REQ-G1.1, REQ-G1.2, REQ-G1.3, REQ-G1.4, REQ-G1.5,
REQ-G1.6, REQ-A1.1, REQ-A1.6, REQ-E1.1, REQ-E1.2, REQ-F1.2, REQ-F1.4, REQ-F1.6,
REQ-F1.7, REQ-H1.2, REQ-H1.4, REQ-D1.9, REQ-G1.8 · fleet-messaging D-1, D-3, D-4, D-5, D-9, D-13,
D-14, D-16, D-17, D-26.

## Signal versus record

**A message is a signal; the record is a file.** Messages are lossy, held,
expired, and model-turn-bound, so nothing that must survive a crash rides one: a
message that had to survive was mis-sent, and the record it points at is the
durable artifact.

- **Upward** (worker to tower), the signal is the harness's one-shot idle
  notice the tower subscribed to at dispatch. Its status line is instruction
  text, never a record: the store row the worker wrote before it stopped is the
  record, and the tower acts only on what the store re-read returns. **Only a
  stop that ends the worker's turn fires a notice** (a fork or park the worker
  halts on, or completion). A mid-turn suspension, such as a permission or
  elicitation dialog, ends no turn and fires nothing; it is the healing sweep's
  case, surfacing there as a stale heartbeat. Beside the notice, the
  **question message** is the one model-composed upward path: one per recorded
  fork (a halt needing a decision is one), never resent, from a worker whose
  task brief names its tower. The fork is recorded first (the `fork` verb), so
  the row and notice stay the record and the push; a park sends none, and the
  message never carries completion or status.
- **Downward** (tower to worker), a steer or a decision answer is an
  instruction addressed to a session and carries its text; for an answer, the
  persisted answer artifact is the recovery source, never a second record.
- **Between towers**, the advisory rule: an advisory is instruction data
  that never claims, releases, or resolves a unit of work; authority over the
  division of work stays where the
  [Fleet Coordination Floor](fleet-coordination-floor.md)'s
  assume-multiplicity floor places it.

Inbound content is untrusted: an inbox socket is writable by any process of the
same OS user, so every receiver grammar-screens, length-bounds, and
echo-sanitizes it. A notice drives action only through what the store re-read
returns; steer, answer, and advisory text is instruction data the receiving
session treats as advisory, never as authority over fences, presence, or the
`tasks.md` record.
The floors carry unchanged; a message to a tower never substitutes for the
deterministic-attention floor's operator-facing push.

## The fallback obligation

**Every messaging path names its deterministic fallback, the pre-messaging
mechanism it replaces, and reaches it on absence, refusal, or any observable
failure with no operator step to select it.** The terminal operator handoff is
itself today's mechanism, not an intervention. What a script cannot observe (a
dropped or expired message) is the healing sweep's case, never this rule's.
A held post is not a failure: it is reported unconfirmed and left queued, never
descended, since descending would deliver twice, and an accepted post is no
proof of delivery. Where a status frame reports an answer dropped, expired, or
refused, the tower redelivers it once through the fallback
(`fleet-decision.sh redeliver`); with no frame, the healing sweep's
answered-undelivered surfacing recovers it. Push is first and the sweep is the
backstop: the healing sweep is never removed, at any discipline value, because
the channel is lossy by contract.

The **healing sweep is `fleet-attention-watch.sh watch`'s level-triggered pass,
the reconcile sweep is `/orchestrate`'s tower step that rebuilds in-flight state
from disk, and `fleet-attention-watch.sh reconcile` is that script's own
deep-reconcile verb.** Push is live while the tower's own probe reads
available and at least one in-flight worker carries a recorded `inbox` value,
re-read each pass; there the healing sweep demotes to one overlay-resolved
cadence, `messaging_heal_cadence_seconds`, shared by every
demoted consumer; operator-facing cadences keep today's intervals.

## The per-path fallback table

The fixed path set, plus the question row. A path a session cannot use (probe
absent, rung ineligible) takes its fallback column from the start, and a rung
the Fallback column gives a path of its own (a `stream-json-persistent` decision answer, a
`headless-oneshot` worker) takes it whether or not messaging is available.

| Path | With messaging | Fallback |
| --- | --- | --- |
| Tower→worker steer | `fleet-messaging.sh send --to-worker`, through the relay's messaging arm | per rung: on `tmux` the attributed buffer-paste, then operator handoff; on `stream-json-persistent` operator handoff, no attributed steer delivery existing there; on `headless-oneshot` none, the rung advertising no steer-in-flight |
| Decision answer | claimed and persisted, then `fleet-messaging.sh send --to-worker` from `fleet-decision.sh` | per rung: on `tmux` the attributed buffer-paste, then operator handoff (today's undelivered-answer surfacing); on `stream-json-persistent` never a message, the supervisor's control response (`fleet-streamjson.sh answer`) being the path; on `headless-oneshot` none, the rung holding no fork to answer |
| Worker→tower idle notice | the harness's one-shot notice, subscribed by the tower | the healing sweep, which reads the row the worker already wrote |
| Worker→tower question message | composed by a briefed worker's model, one per recorded fork | the fork's own row and idle notice, with no step to select it |
| The tower's own wake | a `--watch` step ends its turn and is woken by an idle notice, a peer message, or the harness's scheduled wakeup | today's metronome |
| Poll cadence: the attention watcher's healing sweep | demoted to `messaging_heal_cadence_seconds` | its retained cadence; it is never removed |
| Poll cadence: the dashboard's projection refresh | not demoted: it faces the operator | its retained cadence |
| Tower↔tower advisory | composed by the tower's model through the harness's message tool, addressed by session name | not sent, the status quo; an advisory is never on the correctness path |

The task worker's opening turn rides the launch and is not a messaging path.

## The discipline ladder

`messaging_discipline` gates **model-composed** messages only. Deterministic
script sends (a script-delivered answer or steer) and the harness's idle notices
ride at every value.

- **Values**, ordered `script` < `tiered` < `open`, default `tiered`:
  `script` sends no model-composed message in any direction; `tiered` admits
  model-composed messages on the paths this doctrine's fallback table names and
  no others; `open` lets the model compose freely.
- **`off`** sits outside the ladder: it is the per-fleet kill switch, making the
  probe read absent so every consumer takes its fallback, and it sends no
  model-composed message either. An unknown value reads the same way.
- **Three directions** read the knob differently: worker→tower at the knob
  value, tower→worker one value stricter (workers bear the focus cost),
  tower↔tower at the knob value (towers absorb interrupts).
- **Send-time pressure demotion**: when the usage gate's rung is at or above
  `reduce-concurrency`, every direction steps one value further down.
  Both offsets saturate, so
  `effective = max(script, knob − direction offset − pressure demotion)`,
  evaluated by script logic at send time (`fleet-messaging.sh effective-mode`,
  the oracle a sending prose consults), with one stderr notice per send that
  runs demoted by pressure (the direction offset alone is no demotion) and no
  stored discipline state.

## The per-session probe

Availability is a fact about one session, read inside it; eligibility is a
fact about the rung, derived from the
[Backend Capability Contract](backend-capability-contract.md)'s `Session-grade`
column. A session's probe reads **available** only when all four hold:

1. `CLAUDE_CODE_MESSAGING_SOCKET` is set and names an existing socket owned by
   the invoking user;
2. the CLI version, compared numerically per dotted component, is at or above
   2.1.248 (the documented minimum's stricter arm, applied unconditionally, so
   no provider detection);
3. the session's effective `crossSessionInbound` resolves to `accept`, read
   by awk (never jq or `eval`) from the CLI's settings files in their
   precedence order, or from
   `PLANWRIGHT_MESSAGING_INBOUND=accept`, which a fleet launch seam exports
   beside the `--settings` profile it passes and which outranks every file;
4. `messaging_discipline` resolves to a ladder value, never `off`.

Anything else reads **absent**: a missing or malformed variable, a socket
failing the owner check, an older CLI, a parse failure, an inbound value other
than `accept`. Managed policy is out of scope, and availability is never
inferred from configuration alone: the socket and version conjuncts are
observed facts, so configuration can force messaging off, never on. A send is
possible when the sending session's probe reads available and the target
worker has a recorded inbox socket basename.

## Cross-machine transit

Script paths post to a local socket and are same-machine by construction. Only
a model-composed send can leave the machine, and both shipped settings profiles
must carry `isolatePeerMachines: true`, so the harness asks the operator before
every one; `messaging_cross_machine` is the documented cue to relax that
setting, never an enforcement point. Because a cross-machine message transits
third-party infrastructure, all message text is held to committed-artifact
hygiene: no secrets, credentials, internal hostnames, or sensitive operational
detail ([Security Posture](security-posture.md)). The two script send paths
answer for it at their `--message-file` call sites; a model-composed message is
the sending prose's own responsibility.

## The fleet-runtime version rule

Mixed CLI versions across a fleet are fine. The probe runs per session and
fails safe, so a session below the minimum reads absent and takes its
fallbacks while its peers message.

## Resource classes

Messaging acquires **no resource class beyond the inbox socket**, the one class
it adds to the [Fleet Coordination Floor](fleet-coordination-floor.md)'s
lifecycle-closure contract (opened by the harness, closed with the session,
detected by the session's own death evidence). The rest rides existing
lifecycles:

- the idle-notice subscription is tower-side, outside the floor's worker scope,
  and self-closing: it fires once or expires;
- the tower's session name rides the tower marker's lifecycle;
- the worker's socket basename rides the worker registry's `inbox` column and
  that registry's lifecycle.

## Glossary

Three ladders, each with its own step noun:

- **Fallback ladder** (the two downward paths): messaging, then the rung's
  attributed steer delivery, then operator handoff. Its positions are
  **steps**; every other path's fallback is the single step its table row
  names.
- **Discipline ladder** (`messaging_discipline`): `script` < `tiered` <
  `open`, with `off` outside it. Its positions are **values**.
- **The usage gate's rung ladder** (`fleet-usage-gate.sh rung`): `normal`,
  `downshift`, `reduce-concurrency`, `defer-heavy`, `defer-all`. Its positions
  are **rungs**, the word backends also use; a discipline value is never called
  a rung.

## How this relates

The [Inter-Orchestrator Coordination](inter-orchestrator-coordination.md)
doctrine states the relay this transport fronts and the never-impersonate rule
it keeps. The [Backend Capability Contract](backend-capability-contract.md)
owns the `Session-grade` column eligibility reads. The
[Customization Boundary](customization-boundary.md) is why the discipline is a
knob with a core default and an overlay value.
