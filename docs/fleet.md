# Fleet operation: the approachable path

planwright can run a **fleet**: several specs advancing at once, each unit
executed by its own isolated worker, supervised by a meta-tower. This guide is
the approachable path into that mode — one command, one surface to watch, no
multiplexer knowledge required. The approachable path is the *default*
presentation of fleet operation, not a simplified fallback: full execution
quality (session-grade, steerable, parallel workers, with the richest backend
your host offers) stays available underneath it — the surface never costs you
worker quality.

## The one command

From a Claude Code session, in a checkout whose `specs/` holds one or more
signed-off (Ready or Active) bundles:

```text
/orchestrate --fleet
```

From a plain shell, the same entry is:

```sh
claude "/orchestrate --fleet"
```

For a headless run (e.g. under cron), use headless mode with the flag inside
the quoted command: `claude -p "/orchestrate --fleet --unattended"`. The
command does three things, and asks before the one choice that is yours:

1. **Autodetects the execution backends** present on the host and presents
   them with their advertised capabilities; you pick one (attended runs never
   silently pick; unattended runs resolve `dispatch_backend` from config and
   degrade safely — see the
   [options reference](options-reference.md)).
2. **Starts the tower(s)**: a meta-tower supervising every Ready/Active spec,
   launching a subordinate tower per spec, each dispatching workers into
   isolated worktrees, all under the fleet concurrency bound.
3. **Renders the attention surface**: the decision queue plus a per-worker
   status view, re-rendered as the fleet advances.

## The two seams

The design splits fleet operation into two independent seams
(the [attention/notification capability](../doctrine/attention-notification-capability.md)
doctrine covers this in depth):

- The **execution substrate** — how workers are hosted, addressed, observed,
  and steered. This is where *quality* lives, and it is what the backend pick
  chooses. Backends advertise capabilities through the
  [backend capability contract](../doctrine/backend-capability-contract.md).
- The **attention surface** — what you watch. This is where *approachability*
  lives, and it defaults to the **decision queue** regardless of the backend
  pick.

The seams do not trade off: picking the richest execution backend never forces
a richer surface on you, and the legible default surface never costs you
worker quality. One hard invariant is carried at every tier: planwright
**never auto-merges**; the draft-to-ready flip and the merge stay yours.

## What you watch: the decision queue

Your load scales with the number of **actionable decisions**, not the number
of workers. The queue lists only workers blocked on a human decision, each as
a structured choice (scope, question, recommended default, concrete options),
ordered by priority and then by longest-waiting. Everything else — working,
PR-ready, merged, done — is status, visible in the per-worker view but never
queued.

Both views read plain files under the durable fleet home and render from any
normal terminal or editor:

```sh
scripts/fleet-attention.sh queue    # the ordered decision queue
scripts/fleet-attention.sh render   # per-worker scope + state
```

Per-worker scope stays legible without any multiplexer: each worker owns
exactly one spec/unit in its own worktree with isolated context, and the
status view names each worker's scope and state — the same clear-scopes model
a tmux power user gets from named windows, with no attaching.

## The multiplexer as background plumbing

If a multiplexer (tmux) is the selected execution backend, it does **not**
become your problem: the tower can drive it as a **detached background
server** nobody attaches to. Workers are hosted, observed, and steered in
detached windows; you keep watching the decision queue. Attaching remains
possible at any time — it is an option for multiplexer-fluent operators, never
a requirement.

## Personas: pick your combination of the two seams

Each kind of operator resolves as a combination of (execution backend ×
attention surface), not as a separate system:

| Persona | Execution backend | Attention surface | Steer affordance |
| --- | --- | --- | --- |
| a. Multiplexer user | tmux, attached — windows visible, capture/relay at hand | The queue, or the tool's own surface: a backend advertising `provides_attention_surface` owns the queue rendering and planwright defers to it | Direct: type into a worker window, or relay via buffers |
| b. Non-terminal user | tmux driven as a detached server, or the subagent backend (in-harness background workers) — invisible plumbing either way, nothing to attach to | The decision queue, read from any plain terminal or via the notification channel | Answer queue items; the tower relays to workers |
| c. Editor-feedback user | The same background plumbing as (b) | The editor renders the queue and diffs (an editor panel tails the same files; `editor-toast` is the matching notification channel) | An editor affordance submits the queue answer; the tower relays |

Two audit notes behind that table:

- **All durable fleet state is files** — the worker registry, the attention
  store, and the toasts under the cross-spec fleet home; the per-spec dispatch
  markers and locks next to each spec; and, for a format-version 1 bundle, the
  `tasks.md` snapshot in git (a format-version 2 bundle keeps no committed
  snapshot and reads status through the on-demand render — see
  [orchestration state](orchestration-state.md)). An editor surface is
  therefore a *renderer* over existing files, not a new execution model.
- **A concrete editor integration is a gated deferral**, built when a concrete
  adopter need appears. The persona-(c) row works today with the editor as a
  plain file viewer; the richer affordances are the deferred part.

## Choosing what gets pushed at you

The default notification channel is `none`: nothing pushes, you read the
queue on demand. Set `notification_channel` (an overlay value; see the
[options reference](options-reference.md)) to `tmux-popup`, `os-notify`,
`editor-toast`, or `statusline` to match your persona. The channel is style;
the queue is the capability.

### The statusline channel

`notification_channel: statusline` renders the derived fleet stats — the
last-cleanup time, the watchdog-trip count, and the throttle-engaged state —
natively at the bottom of your own Claude Code terminal via its
[statusLine](https://code.claude.com/docs/en/statusline) feature, alongside the
decision-queue depth. The stats are **derived on demand** from what the daemon
mechanisms already record (the shared audit trail and the live throttle state);
nothing is written to a new file for them.

The `queue` field shows the count of items awaiting a decision, `deferred` when a
backend owns the attention surface itself (so planwright suppresses its own
queue), or `?` if the queue genuinely cannot be read.

Unlike the other channels, `statusline` is *pull-shaped*: Claude Code invokes a
command on its own schedule rather than the fleet pushing at you. So wiring it up
is two steps — select the channel, and register the command in your own
`settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "<plugin-root>/scripts/fleet-statusline.sh"
  }
}
```

`fleet-statusline.sh` renders the stats line only while `notification_channel`
resolves to `statusline`; with any other value it prints nothing, so the command
is harmless to leave installed and switching the channel off silently returns
your status line. A one-off render is `scripts/fleet-stats.sh render` (the
multi-line view) or `scripts/fleet-stats.sh line` (the compact one). The
human-facing audit-trail view — queryable by mechanism and time range — is
`scripts/fleet-stats.sh audit [--mechanism <m>] [--since <epoch>] [--until <epoch>]`.

The rest of this guide is the execution-substrate side of the split: how a
backend is picked, what happens when the rich one is missing or dies, how you
plug in a backend of your own, how the towers manage their own context, how
multiple towers coordinate, and which decisions the fleet takes without you.
None of it requires tmux knowledge — tmux appears below only as one backend
among several.

## Picking an execution backend

A backend is not chosen by name; it is chosen by what it **advertises**. Every
backend self-describes against the
[backend capability contract](../doctrine/backend-capability-contract.md):
`interactive`, `can_observe` (read a running worker mid-task),
`can_steer_inflight` (deliver an attributed message into a busy worker),
`provides_attention_surface`, `supports_parallel`, plus whether its workers are
**session-grade** — launched as full top-level sessions that survive the
tower's death. Backend selection and the degradation ladder below key on this
advertised set, not on the backend's name; the per-backend dispatch wiring
itself is still name-keyed today, pending later wiring (see the
[options reference](options-reference.md)).

The shipped `dispatch_backend` values, by what they give you:

| Backend | What it is | Observe / steer | Session-grade |
| --- | --- | --- | --- |
| `tmux` | Interactive workers in multiplexer windows (attach optional, never required) | yes / yes | yes |
| `subagent` (default) | In-harness background workers with isolated context | no / no | no |
| `print` | Prints the launch command; you run the worker yourself | no / no | deferred to you |
| `in-session` | Runs the unit in the tower's own session, one at a time | n/a | no |

At dispatch, `/orchestrate` **autodetects** which backends are actually present
on the host and collects each one's advertised set. Attended, it presents the
detected set and asks — there is no silent pick. Unattended, it reads
`dispatch_backend` from config; if that backend is absent, it degrades down the
ladder below, and it never silently selects an interactive backend (an
unattended tower has no one at the keyboard to drive one).

## The degradation ladder: quality degrades, safety never

When the configured or richest backend is unavailable, the fleet descends a
richest-to-safest ladder ordered by advertised capability, not by name:

1. **Interactive multiplexer with steer** — session-grade, observable,
   steerable, parallel (tmux today).
2. **Interactive multiplexer without steer, or a headless `claude -p` pool** —
   session-grade and parallel, but ambiguity can no longer be steered away
   mid-flight, so it routes to the decision queue instead.
3. **In-harness background subagent** — parallel with isolated context, but
   in-harness: no observe, no steer, workers do not survive the tower.
4. **Synchronous in-session** — the terminal rung (below). No external
   substrate at all, so it always works.

`print` sits off the autonomous ladder: it defers the spawn to you, so
planwright is not driving the worker and never descends *to* it on its own.

Two properties hold on every rung:

- **Degrade capability, never safety.** A descent only ever costs execution
  richness (steer, observe, parallelism). A descent that would drop a *guard*
  is refused — the run aborts rather than trading safety for progress. The
  guards: the worker-settings deny profile (the restricted permission set
  workers run under — reviewed and installed by you, with sign-off, never
  applied by planwright itself), never-auto-merge, never-force-push, and the
  execution freshness gate (the pre-dispatch check that the spec is unchanged
  since its sign-off).
- **Never silent.** Every descent is logged and surfaced; you can always tell
  which rung you are on.

### Runtime failover

If the chosen backend dies mid-run (the multiplexer server goes away, the
harness loses the subagent runtime), the tower descends **one step** — to the
richest guard-preserving backend still present, skipping absent rungs —
and records the effective
backend spec-locally (in the spec's dispatch-state directory,
`<spec-dir>/.orchestrate/` by default — this effective-backend record never
lands in `tasks.md`, which stays a clean derived ledger), and surfaces the
downgrade:
a logged note, plus a human-facing entry in the spec's `## Awaiting input`
section of `tasks.md`, which the decision queue mirrors — so the downgrade
shows on the attention surface. A second failure descends
one more step, down to the floor. There is no silent downgrade path.

And there is no unsafe one: when nothing safe remains below (the floor itself
failed, or every remaining rung would drop a guard), or the downgrade record
cannot be written, the tower does not press on — it stops and escalates the
same way, an `## Awaiting input` entry asking for your decision. Fail-closed,
never unrecorded.

### The synchronous terminal rung

The floor of the ladder is a contract implementation, not an error state: units
run one at a time in the tower's own session, with a context clear between
units so each starts with bounded context. Slower, but fully functional — every
guard, gate, and review the rich backends run also runs here. A host with
nothing installed beyond Claude Code still operates the whole pipeline.

## Bringing your own backend

A new terminal or multiplexer plugs in by advertising the contract — no edit
to planwright's skills. You ship an executable `planwright-backend-<name>` on
`PATH` that answers `advertise` with one six-field capability line;
`/orchestrate` autodetects it, reads the set, places it on the ladder, and offers
it like any shipped backend. A backend whose advertisement is missing or
malformed is never selected (unknown capabilities fail safe). The exact adapter
protocol lives in
[the contract doctrine](../doctrine/backend-capability-contract.md#adding-a-backend).

## Self-management: bounded context, disposable towers

Long fleet runs manage their own context instead of quietly degrading:

- **Per-step isolation** (`dispatch_isolation: per-step`, the default): a
  unit's implementation and each configured review skill run in their own
  fresh session seeded by `/resume`, so context stays bounded and each
  review's perspective is uncontaminated by the step before it. Backends that
  cannot spawn fresh sessions approximate it with context clears. `per-unit`
  keeps the whole unit in one session for constrained hosts.
- **Context-budget auto-heal**: a tower tracks its completed-step count
  against `context_budget_threshold` and, on nearing it, performs the
  [continue-as-new handover](../doctrine/context-budget-autoheal.md): it
  launches a fresh tower that rebuilds the entire in-flight picture from
  durable state (the `tasks.md` snapshot, `gh`, branches, markers, the worker
  registry) and stops. Nothing in-memory is passed — which is also the crash
  story: a tower that dies without handing over is rebuilt from the same
  disk state by the next one.

## Tower crash recovery: the watchdog and the resume signpost

An *ungraceful* tower death (host reboot, killed terminal) never hands over.
Recovery is mode-aware (fleet-autonomy D-4), keyed off a durable **tower
marker** the tower records at watch-loop start
(`scripts/fleet-tower-marker.sh record <spec> --mode unattended|interactive
--pid <pid> --checkout <repo-root> [--session-id <uuid>]
[--tmux-session <name>]`) and clears on a graceful exit:

- **Unattended towers** are supervised by
  `scripts/fleet-tower-watchdog.sh <spec-dir>` — a deterministic,
  cron-scheduled dead-man's switch (never another tower, never an LLM). Each
  tick it checks the kill-switch gate, demands positive evidence of death
  (`fleet-death-evidence.sh` — a timeout is never evidence), confirms ready
  work by calling through to `/orchestrate`'s own selector, then relaunches a
  fresh memoryless tower from disk state alone into its **own** detached tmux
  session (`planwright-tower-<spec>`), under the existing per-spec advisory
  lock with death re-verified before acting, so overlapping ticks can never
  double-launch. Repeated failures back off on
  `tower_relaunch_backoff_base * 2^(n-1)` seconds and disable at
  `tower_relaunch_disable_threshold` with a decision-queue entry; a tower
  observed alive again re-arms it. Every action lands in the audit trail.
  Schedule it per supervised spec, e.g.:

  ```cron
  */5 * * * * cd /path/to/repo && scripts/fleet-tower-watchdog.sh specs/<spec>
  ```

  (ensure `claude` and `tmux` are on cron's `PATH`).
- **Interactively-led towers** hold the human's actual conversation, which
  only `claude --resume <session-id>` can restore — so nothing relaunches
  them. Instead the `SessionStart` (`startup`) hook
  `scripts/fleet-tower-signpost.sh` detects an orphaned interactive marker
  for the directory you just started `claude` in (recorded pid positively
  dead) and surfaces the exact resume command. It never auto-resumes and
  never discards the marker; after resuming or abandoning, clear it with
  `scripts/fleet-tower-marker.sh clear <spec>`.

An ambiguous or unparseable marker fails closed: neither path acts, and the
watchdog queues a repair decision instead of guessing.

## Scaling out: the meta-tower

`/orchestrate --fleet` supervises **all** Ready/Active specs by launching a
subordinate tower per spec — a tower of towers (the `--meta` mode, which
`--fleet` wraps with the watch loop and the default attention surface).
Fleet-wide load is capped by
`fleet_max_parallel_units` (in-flight units summed across every spec), enforced
against the live cross-spec derivation so the bound survives any crash;
`max_parallel_units` still caps each spec individually.

Concurrent towers and workers stay safe by a strict
[division of labor](../doctrine/inter-orchestrator-coordination.md): a tower
owns the ledger reconcile, dispatch, and merged-worker cleanup; a worker owns
its own branch — its conflict resolution, its post-merge sync. No tower ever
edits another tower's or worker's branch state. Messages *into* a live worker
go through the attributed relay: clearly marked as tower-origin, delivered by
a paste mechanism that cannot be mistaken for the worker typing, and **never**
answering a worker's harness permission prompt — a worker's authorization
gate belongs to the human at every tier.

## Ghost-text prevention: keeping pane captures unambiguous

Fleet supervision reads a worker's (or an observed tower's) input line by pane
capture. Claude Code can render a greyed-out *prompt suggestion* (ghost text) in
that line — text the operator never typed — which a naive capture could mistake
for real pending input. planwright removes the ambiguity at the source: the
dispatch primitive **constructs** every fleet-launched session through
`scripts/fleet-dispatch-env.sh` as a code path —
`scripts/fleet-dispatch-env.sh --emit-launch <launch-argv>` emits the
wrapper-prefixed launch command (it prints the line; it does not itself mutate
the environment). When that line runs, the wrapper prefix sets the pin
`CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` in the launched process's
environment — so the pin is guaranteed by the construction (the prefix is always
there), not by a prose step the model must remember (D-5, D-10, REQ-B1.1,
REQ-B1.2). This is prevention, not detection
— an official disable switch applied at launch beats a per-capture heuristic
every time.

The pin rides an **auto-approved launch shape** (D-5): the emitted verb is the
repo-contained `scripts/fleet-dispatch-env.sh` path the `worker-command-guard`
literal-path resolution auto-approves, so the pinned launch never floods the
worker and never falls back to the bare launch that once dropped the pin. The
allow rules that front it follow one discipline worth knowing when you add or
edit them: see the
[glob discipline](overlays.md#path-scoped-allow-rules-use-the-slash-star-glob).

A **backspace-probe** disambiguation check — send a backspace to the pane and
diff it before and after to tell real input from a rendered suggestion — stays
documented as a defense-in-depth fallback but is deliberately **not** built or
dispatched (REQ-D1.2). Its gate: it is implemented only if a concrete case where
`CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` fails to prevent the ambiguity is
observed in the drain loop (for example, a future Claude Code surface that
renders suggestions somewhere the env var does not reach). Until then no required
code path depends on it.

## Push-based worker liveness: events, the five states, crash backoff

Worker liveness is **pushed, not polled** (D-1, REQ-A1.1): the plugin registers
six hook events, and a dispatched worker's own session writes its state
transitions to the attention store the instant they happen, through
`scripts/fleet-liveness.sh`:

| Hook event | Transition pushed |
| --- | --- |
| `Stop` | working → `idle` (the turn ended). A **live fork-park is preserved**, not cleared — a turn-end is not a dead worker, so `Stop` never downgrades an awaiting-human fork-park (fleet-hardening Task 2 NS-4) |
| `PermissionRequest` | working → `awaiting-input`, queued, plus a pending-permission marker |
| `PostToolUse` | `awaiting-input` → working — when a live **decision marker** exists: a pending-permission marker (the human allowed the next tool use) or a fork-park marker (the worker resumed from a fork; fleet-hardening Task 2). Otherwise a fast no-op |
| `SessionEnd` | → `ended` (session termination) |
| `StopFailure` | → `hung` (a turn ended on an API error resembles a stopped-responding worker — the decided kickoff risk-row-27 mapping) |
| `Notification` | working → `awaiting-input` + a fork-park marker, for a genuine fork / input-wait `notification_type` only (fleet-hardening Task 2, D-2). The instant a worker parks at an `AskUserQuestion` fork it fires `Notification`; the arm gates on the payload reason (a permission-park, an auth / completion notification, or an unknown type push nothing) and pushes an `awaiting-human` record with the reason — no pane capture |

**The identity gate.** These hooks fire in *every* session the plugin is
enabled in; only a dispatched worker may write. The gate is a
dispatch-time env contract: a worker launched with `PLANWRIGHT_WORKER_HANDLE`
and `PLANWRIGHT_WORKER_SCOPE` in its environment (hook commands inherit the
launched process env) is the one whose transitions the handler records. With
*neither* var set the handler is a silent no-op; a *half-set or malformed*
identity (one var present, the other missing, or a value failing the field
grammar) is refused with a one-line stderr warning — still exit 0 and no write,
so a misconfigured dispatch is visible rather than silently dropped. **The
dispatch-side wiring that
exports these vars is not in place yet** — the per-backend dispatch adaptation
that sets them is a later task, so until it lands every session no-ops this
handler and the fleet stays on the existing observation path (a graceful
REQ-A1.1 degradation, no breakage). The hook payload is drained, never parsed,
for every event **except `Notification`**: identity comes from the env contract,
so no payload field is interpolated anywhere. The one exception is the
`Notification` arm (fleet-hardening Task 2), which reads a bounded payload prefix,
extracts `notification_type` with awk (never jq, REQ-K1.5), and strictly
validates it against a fixed allow-list before mapping it to a fixed reason
string — no raw payload text ever reaches a command or the store.

**Guards worth knowing.** A downgrade push (`Stop`/`SessionEnd`/`StopFailure`)
never overwrites an `awaiting-input` row that has no **decision marker**
(pending-permission or fork-park): that row is a queued human decision (a
flailing escalation, a crash-loop disable), and `fleet-autonomy` REQ-A1.3 forbids
auto-resolving it. A live decision marker is the exception — it means this handler queued the
row, so its own exit edge clears it with precedence. The permission and fork-park
flows differ on a plain `Stop`: a permission marker clears on a resume
(`PostToolUse`) or any terminal exit, but a fork-park clears on a resume or a
*genuine* termination (`SessionEnd`/`StopFailure`) while a plain `Stop`
**preserves** it — `Stop` fires on every turn-end (including a park-and-wait) and
races the asynchronous `Notification` with no guaranteed order, so a `Stop` on a
live fork-park means the worker is alive and waiting, not gone (fleet-hardening
Task 2 NS-4). A denied permission whose turn
then ends clears on the `Stop` push; anything beyond that heals on the periodic
ground-truth reconcile (`fleet-autonomy` REQ-A1.8, a later task), which stays the
correctness backstop for every missed or dropped push — push is a latency
optimization, never the source of truth. Precedence between push and reconcile
writes is last-write-wins by commit-time timestamp (the store stamps
heartbeats under the lock), so a reconcile that started before a fresher push
cannot overwrite it with stale state.

**Backend fallback** (`fleet-liveness.sh push-capable <backend>`): only
`tmux` launches a dispatch-controlled Claude Code process that inherits the
identity env and fires plugin hooks, so only `tmux` pushes. `subagent` runs
workers in-process, `in-session` shares the tower's own session, and `print`
spawns no process at all (the human runs the printed command, so the
dispatch env is never injected; the capability contract exempts
print-backend units from the liveness predicate) — all three keep the
existing observation path, and a fleet composed mostly of those backends
keeps pre-spec observation latency for that slice, degrading capability,
never safety.

**The five-state classifier** (`fleet-liveness.sh classify`, D-2, REQ-A1.2)
resolves exactly one of `working` / `idle` / `hung` / `awaiting-human` /
`flailing` from the store row plus observation evidence. The boundaries it
commits to: a freshly-dispatched worker with no row and no heartbeat evidence
is `working` (dispatch implies immediate activity); `ended` and the progress
states (`pr-ready`/`merged`/`done`) classify as `idle` (no in-flight turn, no
progress expected); `hung` means the heartbeat stopped
(`fleet_hung_heartbeat_seconds`), corroborated by the positive-evidence
predicate (`fleet-death-evidence.sh`) wherever a process/window handle exists
— an `unknown` verdict *refuses* the hung classification, because lost
observability is never death — while with no handle available, elapsed time
alone is the classifier's documented boundary (classification is inherently
time-based where no authoritative query exists); `flailing` means the
heartbeat continues but the progress token (e.g. the worker branch's HEAD sha)
is unchanged across `fleet_flailing_threshold` consecutive observations taken
while the worker was working — a stretch spent awaiting-input, idle, or ended
expects no progress and resets the streak, so a permission block never
inflates it into a spurious escalation on resume. A
`flailing` classification queues exactly one human decision ("this task may be
stuck") and records the escalation in the audit trail — there is no automatic
nudge or restart path at all (`fleet-autonomy` REQ-A1.3). Routine classification is *not*
audited: the trail records actions, not status noise. The classifier consumes
only grammar-validated tokens, never raw pane text — a capture-pane consumer
sanitizes before anything reaches it.

**Crash-loop backoff** (`crash-record` / `crash-check` / `crash-reset`, D-3,
REQ-A1.4): each consecutive crash doubles the relaunch delay from
`fleet_crash_backoff_base_seconds` (capped at 3600s); at
`fleet_crash_disable_threshold` consecutive failures the worker is disabled —
no further relaunch is authorized — and the disable is escalated as a
decision-queue entry. The disable is sticky (a later threshold raise never
silently re-enables a parked worker) and `crash-check` reports it ahead of
everything else — exit 3 even while the kill-switch is set, re-upserting the
disable's queue entry if it went missing — so the terminal state is never
masked. `crash-check` consults the operator kill-switch
(`fleet_daemon_pause`) before authorizing any relaunch; bookkeeping and
escalation are deliberately not gated (pausing the record of what happened
would hide problems). Backoff and disable actions log through the audit
trail; a human clears the streak with `crash-reset`.

## Resource governance: models, throttling, and the auto-mode line

Three deterministic mechanisms govern what a dispatched unit costs and what it
is allowed to run as (REQ-E1.1–REQ-E1.4). All three are script logic — never
in-context model judgment (D-18), never a confidence-calibrated routing
cascade (D-11).

**Model, effort, and command come from a rule table.**
`scripts/fleet-resource-select.sh select <task-type>` resolves one
model/effort/command row per task type — `execution` (the `/execute-task`
workhorse: strong model, high effort), `bookkeeping` (the reconcile/drain
sweep: mid tier), `drain` (the read-only gate pass: light tier). All three
columns are overlay-tunable per type (Task 10, REQ-E1.8): the model column
(`fleet_model_*` — the stable Claude Code aliases `fable | opus | sonnet |
haiku`), the effort column (`fleet_effort_*` — `low | medium | high`), and the
command column (`fleet_command_*` — the dispatch-entry set `execute-task |
orchestrate | drain`). The shipped defaults preserve today's table, so an
operator who configures nothing gets today's mapping. The selectable command
set is disjoint from `review_sequence`'s nestable-review-skill set by
construction — the `fleet_command_*` enum is exactly the non-nestable
dispatch-entry set, so an out-of-enum command is refused at every overlay layer
(REQ-E1.2), and the dispatch table and the convergence knob can never both claim
the same skill.

**Throttling is reactive, off Claude Code's own signal.** There is no
supported way to query account-level usage, so the fleet reacts to the one
authoritative signal that exists: the native rate-limit prompt a session
renders (D-12). `scripts/fleet-throttle.sh observe` is the reactive entry
point: a tower whose pane capture or worker output shows the prompt feeds
the captured text in, and observe sanitizes it, parses the signaled reset
time, and pauses **fleet-wide** dispatch until then; every tower consults
`fleet-throttle.sh check` before dispatching, so dispatch resumes at the
signaled reset with no daemon firing at the boundary.
Concurrent observations with different parsed reset times resolve to the
**max** under the fleet lock — the conservative direction. A relative reset
("in N minutes") anchors to an absolute time **once per prompt-event**:
re-observing the identical prompt while the anchor holds never recomputes or
ratchets it; only a changed excerpt or an elapsed anchor re-anchors. A
wall-clock reset observed at/just past its own stated minute is treated as
effectively now (a short grace hold, never a next-day jump). A signal whose
reset time cannot be parsed (the prompt is version-sensitive UI text)
degrades to the bounded `fleet_throttle_default_hold` with a warning — never
an indefinite pause, never an immediate resume. Engagement is a daemon
action: kill-switch-gated (`fleet_daemon_pause`) and audit-logged
(`fleet-audit.sh`, mechanism `throttle`), so Task 8's stats can render
throttle-engaged state from the trail. An operator ends a hold early with
`scripts/fleet-throttle.sh clear` — the manual-resume lever: audit-logged
like every state change, but not gate-checked, because the kill-switch
pauses autonomous actions, never the operator's own lever.

**Gating is proactive, off Claude Code's own `/usage`.** The reactive
throttle only fires at the wall; `scripts/fleet-usage-gate.sh` reads real
account-level usage *ahead* of it (D-23). `fleet-usage-gate.sh capture` takes
a captured `/usage` render on stdin (a throwaway-pane scrape, off the hot
path), strips control bytes, parses **both** windows Claude Code renders — the
session (~5-hour) and the weekly — **by label**, plausibility-checks each
(0–100 and the expected shape), and caches the extracted signal per-tower with
a read timestamp. `fleet-usage-gate.sh evaluate` maps each window's percentage
to a rung on one monotone restriction ladder —
`normal → downshift → reduce-concurrency → defer-heavy → defer-all` — by
deterministic `≥` comparison against the overlay-resolved per-window thresholds
(`fleet_usage_session_*`, `fleet_usage_weekly_*`; strictly ascending and in
1–100, validated). The **more restrictive** window governs; the session window
is **capped at `defer-heavy`** (a session spike never proactively halts the
fleet), while only the weekly window can reach `defer-all` (the weekly wall can
halt work for days). `fleet-usage-gate.sh admit <model>` answers the
dispatch-time question: at `defer-heavy` heavy tiers (`opus`, `fable`) wait
while cheaper ones dispatch; at `defer-all` everything waits. The ladder's live
state (current rung, last transition) is **derived from the shared audit
trail**, not stored (D-28), so a memoryless, cron-relaunched tower recovers the
fleet rung; each transition is taken under the same advisory lock, logged
**edge-triggered** (only on an actual rung change), and carries only the
extracted percentages and the rung decision — never the raw `/usage` render,
which can carry account or plan identifiers. Every rung transition is a
throttle-family daemon action: kill-switch-gated (`fleet_daemon_pause`) and
audit-logged (mechanism `usage-gate`), and the current rung folds into the
existing throttle line Task 8's stats already render (no new stat type). When
`/usage` cannot be captured, parsed, is implausible, or is stale beyond
`fleet_usage_signal_ttl_seconds`, the signal is reported **unavailable**:
governance falls back to the reactive throttle (the deterministic floor) with
no block and no guessed number, and unavailability sustained across
`fleet_usage_sustained_loss_count` consecutive read cadences raises the
required operator surface (a warning escalating to an Awaiting-input hold), so
a permanently broken parse is never silent. The proactive read is
**shared-aware by construction**: `/usage` is account-global, already
reflecting every concurrent tower, all workers, and unrelated same-account
work, so no per-orchestrator usage reservation is kept. Because the `/usage`
render is an undocumented, version-fragile surface (D-23), the parser carries a
`[manual]` drift check — the automatable core (parse, plausibility, hygiene,
ladder) is in CI; confirming the parser still matches a live `/usage` format is
the operator's periodic manual check.

Schedule the read + evaluation on the `fleet_usage_read_cadence_seconds`
cadence, off the dispatch hot path — the gate never scrapes `/usage`
synchronously per dispatch. The scrape mechanism (a throwaway-pane capture of
the live `/usage` TUI) is environment-specific; wire it as, e.g.:

```cron
*/5 * * * * cd /path/to/repo && <scrape-/usage> | scripts/fleet-usage-gate.sh capture && scripts/fleet-usage-gate.sh evaluate
```

Then at dispatch time a tower consults `scripts/fleet-usage-gate.sh admit
<model>` (a fast, audit-derived read — no scrape) to decide whether a unit of a
given tier may launch under the current rung.

**Transitions do not flap; a lost signal decays, it does not pin.** The rung
ladder applies **hysteresis** (Task 10, REQ-E1.10): a *climb* (more restrictive)
is immediate — restriction degrades capability only, so engaging it promptly is
always safe — but a *descend* (relaxing) is held until the rung has dwelt at
least `fleet_usage_rung_min_dwell_seconds` since its last transition, so a read
oscillating across a threshold cannot flap the ladder down-and-up
(fast-attack/slow-release). While the signal is **unavailable** the ladder
*holds* its last-known rung (a transient scrape failure must not relax
restriction), then **decays** to `normal` once `fleet_usage_unavailable_grace_seconds`
have elapsed since the last transition, so a persistently broken parse never
pins the fleet at a restrictive rung against a signal it can no longer read (the
reactive backstop remains the floor). Both windows measure from the
audit-derived last-transition timestamp (D-28), so a memoryless relaunch is
consistent, and the decay is edge-triggered and lock-serialized like any
transition.

**The rung VALUES and per-tier budget caps: `scripts/fleet-allocate.sh`.** The
gate above decides the *rung*; `fleet-allocate.sh resolve <task-type>
[--reserved]` decides what that rung *means* for a dispatch (Task 10, REQ-E1.9,
REQ-E1.10), reading the derived rung and the raw signal and emitting the
effective `admit / model / effort / command / concurrency / rung / reserved`.
At `downshift` and heavier it clamps a routine unit's model no more capable than
`fleet_downshift_model` and effort no higher than `fleet_downshift_effort`; at
`reduce-concurrency` and heavier it drops the worker limit from
`fleet_concurrency_normal` to `fleet_concurrency_reduced`. Independently,
**per-tier budget caps** (`fleet_cap_fable | fleet_cap_opus | fleet_cap_sonnet |
fleet_cap_haiku`) withdraw expensive tiers from **routine** units sooner: each
is a global-usage threshold (the more expensive a tier, the lower its threshold,
`opus < sonnet`), a stateless `≥` read against the more-restrictive available
window — never per-model accounting or a reservation ledger — and **inactive
when the signal is unavailable**. A unit dispatched **`--reserved`** (the
operator's "keep the most capable tier for the genuinely-hardest unit") is
exempt from `downshift`, `defer-heavy`, and the caps, but still yields at
`defer-all` and the reactive wall — a preference honored up to the
fleet-critical rung, not an inviolable floor; the shipped default reserves
nothing. Every degrade step degrades **capability only** — never below a full
session-grade worker, never relaxing the determinism floor (REQ-G1.2), never
engaging `--permission-mode auto` (REQ-E1.4); `fleet-allocate.sh guard <model>
[<permission-mode>]` is the explicit assertion of those invariants. When the
operator kill-switch (`fleet_daemon_pause`) is engaged, allocation reverts to the
un-degraded `normal` policy — the operator has assumed manual control, so the
ladder stops degrading rather than blocking dispatch. The whole path is
deterministic script logic with no LLM call.

**Credit-continuation defaults to decline-and-wait, never auto-spend.** The
rate-limit wall sometimes offers a *credit-continuation* prompt — "spend
credits / extra usage to continue past the limit".
`scripts/fleet-credit-continuation.sh decide`, invoked on the same captured wall
text the throttle reads, rides that reactive detection: it recognizes the
spend-to-continue offer (demanding both a spend-offer token and a continuation
token, so a plain wall or a garbled variant is never mistaken for one) and makes
a single deterministic
fleet policy decision. The shipped default is **decline and wait** for the
window to reset — the reactive backstop already gives "wait for reset" a
well-defined behavior to fall into, so declining costs no new mechanism, and
an unattended, unbounded money spend is exactly the irreversible act
planwright reserves for the operator (like merge). Spending credits to
continue requires explicit opt-in: set `fleet_credit_continuation_spend: true`.
The decision is a daemon action — kill-switch-gated (`fleet_daemon_pause`) and
audit-logged (`fleet-audit.sh`, mechanism `credit-continuation`, with only the
sanitized excerpt and the decline/spend decision recorded) — and, being a pure
recognizer-plus-config-read, it makes no session-launch decision and so can
never engage `auto` permission mode. An unrecognized wall variant is a clean
no-op that falls through to the plain reactive backstop above, so no accidental
spend is ever possible. This is a spend-*avoidance* default, distinct from a
dollar-spend accounting ceiling (out of scope): it neither meters nor caps
spend, it only refuses to incur it without opt-in.

**Workers never run in `auto` permission mode.** The
`config/worker-settings.json` allowlist — human-reviewed, human-installed,
pinning a non-auto `defaultMode` — is the sole permission-approval mechanism
for dispatched workers (D-19, REQ-E1.4). `scripts/fleet-dispatch-guard.sh`
is the dispatch-time lint: `check-launch <argv>` refuses any launch carrying
`--permission-mode auto` (either spelling) or a settings fragment pinning
auto, and — because absence of the flag proves nothing when an operator's own
user settings could set `defaultMode: "auto"` ambient — it also refuses a
launch with **no explicit non-auto mode source**. `check-inherited` covers
the in-process (subagent) shape, where a worker inherits the hosting
session's effective mode. A refusal is a dispatch stop condition, surfaced,
never bypassed.

**The tower runs under its own tested allow layer.** A tower's own
orchestration commands — tmux relay/observe, `claude --worktree` worker
launches, planwright scripts by resolved literal path — were being blocked
non-deterministically by the same `auto`-mode classifier, so the tower runs
under `config/tower-settings.json`, which wires `scripts/tower-command-guard.sh`
as a PreToolUse hook (D-8). It reuses the worker guard's pattern — allow-only,
fail-closed, no LLM in the decision path — but fronts a **distinct, tower-
oriented safe set**: it adds the tower-only shapes (tmux relay/observe, worker
launches) the worker guard defers, and omits the worker-only shapes (`bats`,
`tests/` scripts, `fish -c` recursion) a tower never runs. Coverage is at the
tmux-subcommand granularity: the guard pre-approves the individual relay/observe
verbs (`load-buffer`, `paste-buffer`, `capture-pane`), but not yet
`orchestrate-relay.sh`'s full attributed send shape, whose brace-grouped
`{ ...; } | tmux load-buffer` pipeline the inherited engine defers to the
classifier (see `specs/_observations` for the follow-up). Only the underlying
subcommands are deterministically covered. This consciously
**re-opens** the worker-only scoping `worker-permission-ergonomics` chose for a
blast-radius reason: the tower's radius is broader (it launches workers and
drives tmux), so it gets its own tested layer rather than the worker guard
silently widened. Because the guard is allow-only with no default-deny, the
profile's **deny block is the security floor**, effective regardless of guard
output: it denies the shell guardrails (merge, every force-push spelling, amend
/ squash / rebase, `gh pr merge`), default-branch and local-`main` mutation
(`git push …:main`, `reset --hard`, `branch -f`, `update-ref`), the equivalent
GitHub MCP tools (`merge_pull_request`, `update_pull_request`, `push_files` /
`create_or_update_file` / `delete_file` — denied wholesale by name because a
Bash-string guard cannot intercept an MCP call), and `gh pr ready`: a tower
**never** performs the draft→ready flip. The one sanctioned ready-flip
(kickoff-lifecycle D-6: `/spec-kickoff` marks the spec PR ready) runs in a
kickoff session under different settings, not under this tower profile, so the
deny does not block it. The guard's `claude --worktree` allow also **pins**
against launching a worker with its permission layer weakened: any
`--dangerously-*` or `--permission-*` flag, in any position, defers.

## What the fleet decides without you (and what it never does)

Unattended operation follows the
[autonomous-safe-decision policy](../doctrine/autonomous-safe-decision.md) —
the same act-then-review gate the review skills use, granted to towers with
nothing added:

- **May decide unattended:** Auto-applicable findings (tool-cited, mechanical,
  no observable change), Agent-resolvable findings (backed by a
  failing-then-passing regression test plus green CI), Needs-sign-off
  applications (the fix lands on the branch in its own commit; your approval
  happens at PR review by leaving or reverting it), and pre-approved
  operational hygiene (reclaiming merged workers, answering a worker's routine
  *question to the tower*).
- **Must escalate:** anything in a hard-disqualifier zone (security-sensitive
  code, migrations/destructive ops, CI config, lockfiles, secrets), and any
  fork still irreducible after citation, research, and convention — design
  forks, spec drift, decisions you reserved. These arrive as decision-queue
  items, not as silent defaults.
- **Never, on any rung, at any tier:** auto-merge. The draft-to-ready flip and
  the merge are yours, permanently.

## The knobs: capability in core, value in overlay

Every fleet preference splits on the capability-vs-style boundary: the
*mechanism* ships in core as a default-preserving knob; the *value* — which
backend, which channel, which numbers fit this machine — is yours, set through
the [overlay layers](overlays.md). Full resolution and malformed-value rules
are in the [options reference](options-reference.md).

| Knob | The capability (core) | The value (yours) | Default, and why it is the safe one |
| --- | --- | --- | --- |
| `dispatch_backend` | Backend seam: contract, advertisement, autodetect-and-ask | Which backend this host runs | `subagent` — works on any host, no external substrate, parallel with isolated context |
| `dispatch_isolation` | Per-step session isolation in `/execute-task` | Isolation mode for this machine | `per-step` — bounded context and uncontaminated reviews by construction |
| `context_budget_threshold` | Step-count monitor + continue-as-new handover | How long your towers run before handing over | `50` — hands over early; the handover is cheap and lossless, so early is the safe direction |
| `max_parallel_units` | Per-spec concurrency cap | Your per-spec load | `3` — bounded parallelism out of the box |
| `fleet_max_parallel_units` | Fleet-wide bound across all specs | Your total fleet load | `3` — enabling the meta-tower never multiplies load until you raise it |
| `notification_channel` | The notification seam (the decision queue itself is always on; this knob only selects what is pushed) | Which channel pushes at you (`none` / `tmux-popup` / `os-notify` / `editor-toast` / `statusline`) | `none` — pull-only, dependency-free, nothing fires until you opt in |
| `fleet_model_execution` / `fleet_model_bookkeeping` / `fleet_model_drain` | The task-type-keyed model/effort/command rule table | Which model each dispatch tier runs | `opus` / `sonnet` / `sonnet` — judgment-heavy work on the strong tier, mechanical work cheaper |
| `fleet_throttle_default_hold` | Reactive rate-limit throttling with a bounded degrade | The fallback hold when a reset time cannot be parsed | `300` — bounded and short; a real signal re-fires and re-engages if the limit still holds |

Style values never gate capability: every knob's default keeps the full
pipeline functional, and raising richness (a richer backend, a push channel,
more parallelism) is always an explicit, reversible overlay edit.
