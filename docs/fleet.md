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
[options reference](options-reference.md)) to `tmux-popup`, `os-notify`, or
`editor-toast` to match your persona. The channel is style; the queue is the
capability.

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
for real pending input. planwright removes the ambiguity at the source: every
fleet-launched session goes through `scripts/fleet-dispatch-env.sh`, which pins
`CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` into the launched process's
environment (D-10, REQ-D1.1). This is prevention, not detection — an official
disable switch applied at launch beats a per-capture heuristic every time.

A **backspace-probe** disambiguation check — send a backspace to the pane and
diff it before and after to tell real input from a rendered suggestion — stays
documented as a defense-in-depth fallback but is deliberately **not** built or
dispatched (REQ-D1.2). Its gate: it is implemented only if a concrete case where
`CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` fails to prevent the ambiguity is
observed in the drain loop (for example, a future Claude Code surface that
renders suggestions somewhere the env var does not reach). Until then no required
code path depends on it.

## Resource governance: models, throttling, and the auto-mode line

Three deterministic mechanisms govern what a dispatched unit costs and what it
is allowed to run as (REQ-E1.1–REQ-E1.4). All three are script logic — never
in-context model judgment (D-18), never a confidence-calibrated routing
cascade (D-11).

**Model, effort, and command come from a rule table.**
`scripts/fleet-resource-select.sh select <task-type>` resolves one
model/effort/command row per task type — `execution` (the `/execute-task`
workhorse: strong model, high effort), `bookkeeping` (the reconcile/drain
sweep: mid tier), `drain` (the read-only gate pass: light tier). The model
column is overlay-tunable per type (`fleet_model_execution`,
`fleet_model_bookkeeping`, `fleet_model_drain` — the stable Claude Code
aliases `fable | opus | sonnet | haiku`); effort and command are fixed table
cells. The selectable command set is disjoint from `review_sequence`'s
nestable-review-skill set by cross-checked construction (REQ-E1.2), so the
dispatch table and the convergence knob can never both claim the same skill.

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
**max** under the fleet lock — the conservative direction. A signal whose
reset time cannot be parsed (the prompt is version-sensitive UI text)
degrades to the bounded `fleet_throttle_default_hold` with a warning — never
an indefinite pause, never an immediate resume. Engagement is a daemon
action: kill-switch-gated (`fleet_daemon_pause`) and audit-logged
(`fleet-audit.sh`, mechanism `throttle`), so Task 8's stats can render
throttle-engaged state from the trail. An operator ends a hold early with
`scripts/fleet-throttle.sh clear` — the manual-resume lever: audit-logged
like every state change, but not gate-checked, because the kill-switch
pauses autonomous actions, never the operator's own lever.

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
| `notification_channel` | The notification seam (the decision queue itself is always on; this knob only selects what is pushed) | Which channel pushes at you | `none` — pull-only, dependency-free, nothing fires until you opt in |
| `fleet_model_execution` / `fleet_model_bookkeeping` / `fleet_model_drain` | The task-type-keyed model/effort/command rule table | Which model each dispatch tier runs | `opus` / `sonnet` / `sonnet` — judgment-heavy work on the strong tier, mechanical work cheaper |
| `fleet_throttle_default_hold` | Reactive rate-limit throttling with a bounded degrade | The fallback hold when a reset time cannot be parsed | `300` — bounded and short; a real signal re-fires and re-engages if the limit still holds |

Style values never gate capability: every knob's default keeps the full
pipeline functional, and raising richness (a richer backend, a push channel,
more parallelism) is always an explicit, reversible overlay edit.
