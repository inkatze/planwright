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

(add `--unattended` for a headless run, e.g. under cron). The command does
three things, and asks before the one choice that is yours:

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
PR-ready, merged — is status, visible in the per-worker view but never queued.

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

Each kind of operator resolves as a combination of (execution backend x
attention surface), not as a separate system:

| Persona | Execution backend | Attention surface | Steer affordance |
| --- | --- | --- | --- |
| a. Multiplexer user | tmux, attached — windows visible, capture/relay at hand | The queue, or the tool's own surface: a backend advertising `provides_attention_surface` owns the queue rendering and planwright defers to it | Direct: type into a worker window, or relay via buffers |
| b. Non-terminal user | tmux driven as a detached server, or the subagent backend (in-harness background workers) — invisible plumbing either way, nothing to attach to | The decision queue, read from any plain terminal or via the notification channel | Answer queue items; the tower relays to workers |
| c. Editor-feedback user | The same background plumbing as (b) | The editor renders the queue and diffs (an editor panel tails the same files; `editor-toast` is the matching notification channel) | An editor affordance submits the queue answer; the tower relays |

Two audit notes behind that table:

- **All durable fleet state is files** — the worker registry, the attention
  store, and the toasts under the cross-spec fleet home; the per-spec dispatch
  markers and locks next to each spec; the `tasks.md` snapshot in git (see
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
