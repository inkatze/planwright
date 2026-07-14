# Orchestration Modes

The rare mode branches of `/orchestrate`, read at the branch that takes them:
the **degradation ladder and runtime failover** (a chosen backend dying or
proving unavailable), the **meta-tower** (`--meta`, supervising several specs
at once), and the **fleet entry** (`--fleet`, the one obvious command).
Every invariant in the skill's always-loaded core — never merge, never mark
ready, never loosen an invariant at any tier — holds unchanged in every mode
described here.

Citations: orchestration-fleet REQ-B1.5, REQ-B1.6, REQ-D1.1, REQ-D1.2,
REQ-D1.5, REQ-E1.1, REQ-E1.2, REQ-E1.5 · orchestration-fleet D-3, D-6, D-9,
D-12, D-13.

## Degradation ladder & runtime failover (REQ-B1.5, REQ-B1.6, D-3)

The four shipped backends are rungs of one **graceful-degradation ladder**,
ordered by their advertised capability set (not their name), richest to
safest: rung 1 interactive multiplexer **with** steer (`tmux`); rung 2
interactive **without** steer, or a headless `claude -p` pool (session-grade
and parallel but no live steer — its ambiguity routes to the decision queue,
so it is **not** a quality-equivalent middle rung and sits near the
fallback); rung 3 the in-harness `subagent`; rung 4 the synchronous
**in-session** terminal rung (no external substrate, so it **always works**).
The manual `print` backend is off the autonomous ladder — a human runs the
printed command, so planwright is not driving the worker.
`scripts/orchestrate-degrade.sh rung <backend|caps6>` reports a backend's
rung from its advertised set.

**The synchronous terminal rung.** With no rich backend present or selected,
ready units run **one at a time with a context clear between them** — the
bounded-context single-stream run. `scripts/orchestrate-degrade.sh
terminal-plan <id>...` prints the plan (a `run <id>` line per unit, a
`context-clear` between consecutive units, never after the last); execute
each unit, then issue the context clear before the next. (Per-*step*
isolation clears within a unit are `dispatch_isolation`'s job —
`scripts/resolve-dispatch-isolation.sh`; this is the per-*unit* plan.) This
rung needs no tmux or multiplexer, so ordinary single-spec execution is
always available (REQ-A1.4).

**Runtime failover.** When a chosen backend **dies or proves unavailable
mid-run**, descend one rung down the available ladder — never a silent
downgrade. Run `scripts/orchestrate-degrade.sh failover <spec-dir>
<current-backend> [candidate...]` (candidates = the backends detected
present, including any pluggable ones by name; omitted, it re-probes the
shipped set). It descends to the richest present, **guard-preserving**
backend strictly below the current rung (an absent intermediate rung is
skipped, so with every rung present this is the adjacent one), **records the
effective backend spec-locally** beside the sibling's `markers/` dir in its
dispatch-state root (`<spec-dir>/.orchestrate/` by default, relocatable via
`PLANWRIGHT_ORCH_STATE_DIR`; never in `tasks.md`, REQ-B1.6; read back with
`scripts/orchestrate-degrade.sh read <spec-dir>`), emits a `NOTE:` on stderr,
and prints an `## Awaiting input`-ready entry on stdout — **append that entry
to the spec's `## Awaiting input`** so the descent is one durable,
operator-visible signal (REQ-E1.3). Repeated failures descend one rung each
down to the terminal rung.

The governing rule is **degrade capability, never safety**: a descent
guard-preserving target is non-interactive (never strand an unattended run)
and not spawn-deferred (never the manual `print` rung) — the two advertised
properties whose loss would take the worker off planwright's driven, guarded
path and drop a named guard (worker-settings deny, never-auto-merge,
never-force-push, the freshness gate). When no safe rung remains below — the
terminal-rung fatal crash, or a descent whose only lower candidates would
drop a guard — `failover` **escalates** (exit 3) with the reason rather than
descending; a record-write failure likewise aborts (exit 3) rather than
proceeding unrecorded. Surface the escalation and stop; never auto-merge and
never drop a guard to keep a run alive.

## Meta-tower — tower of towers (REQ-D1.1, REQ-D1.5, D-6)

`--meta` supervises **several Ready/Active specs at once**, advancing one
unit across the whole fleet per step by launching **subordinate single-spec
towers**. It adds exactly one layer — *which spec advances next, under a
fleet-wide bound* — over the unchanged single-spec machinery: each
subordinate is an ordinary disposable step machine (the same skill without
`--meta`), owning exactly one spec, one lock, one dispatch record. The
meta-tower holds **no cross-spec state beyond the current step** (D-6): every
step recomputes the whole picture from the live cross-spec derivation, so it
is disposable and crash-safe exactly like a single tower.

**Resolve the supervised set.** Take the explicit `specs/<spec>` paths after
`--meta` when given; otherwise discover every `specs/*/` bundle whose
`Status:` is `Ready` or `Active` (underscore-prefixed accumulators are never
bundles). Run each supervised spec through pre-flight (Ready/Active,
validator, kickoff brief); a spec that fails is **dropped from supervision
with a one-line note** (and, when the failure is dispatch-blocking, an entry
in that spec's `## Awaiting input`) rather than halting the fleet — one
unsigned or erroring spec must not stall the others.

**The meta step.** One atomic step, mirroring the single-spec locked window
at the fleet tier:

1. **Acquire the fleet advisory lock** — `scripts/fleet-state.sh lock` (the
   named cross-spec concurrency primitive under `${CLAUDE_PLUGIN_DATA}`),
   serializing concurrent meta-towers: the cross-spec analogue of the
   per-spec lock. Exit 1 (another live meta-tower holds it) is a **clean
   no-op**: skip this step. Hold it only across the decision below, never
   across a subordinate's execution (the D-10 discipline at the fleet tier).
2. **Select across the fleet**, under the lock:
   `scripts/orchestrate-meta-select.sh specs/<a> specs/<b> …`. It reads each
   spec's **live derivation** (`orchestrate-state.sh` /
   `orchestrate-select.sh`, never the committed snapshot), sums fleet-wide
   in-flight units, and returns `<spec-dir>\t<id>` for the fewest-in-flight
   ready spec (FIFO on ties) **only when** the fleet is below
   `fleet_max_parallel_units` and that spec is below its own
   `max_parallel_units`. Exit 1 → nothing to dispatch this step: release the
   lock and, under `--watch`, idle until the next tick; a single step reports
   it and exits. Exit 2 → fail closed; halt. The **authoritative** bound is
   this live count: re-derived from disk every step, it rebuilds after any
   crash and cannot leak, and the fleet lock makes the check-then-launch
   atomic against another meta-tower — the cross-spec analogue of closing the
   double-dispatch race.
3. **Optionally reserve a same-instant slot.** For a backend whose dispatch
   marker becomes visible to the live count only after a lag, the atomic
   counter — `scripts/fleet-state.sh bound-incr
   "$(scripts/config-get.sh fleet_max_parallel_units)"` paired with
   `scripts/fleet-state.sh bound-decr` — can reserve the launch slot for the
   window between the subordinate's launch and its marker appearing. It is a
   reservation *over* the live count, never a substitute: a hard kill can
   leak a reserved slot and a disposable tower keeps no cross-step memory to
   pair a `bound-decr` to, so the leak-free live count — not the counter —
   remains what actually gates, and a leaked slot can never permanently
   narrow the effective bound. (The slot-leak limitation is tracked as an
   observation.)
4. **Release the fleet lock** before launching
   (`scripts/fleet-state.sh unlock`).
5. **Launch the subordinate tower** for the chosen spec: dispatch
   `/orchestrate <spec>` (one step) via the selected backend (the skill's
   backend-selection law applies unchanged). The subordinate runs its own
   pre-flight and freshness gate, takes its **own** per-spec lock, writes its
   **own** dispatch record, and dispatches its worker. The meta-tower passes
   it no in-memory state and **never** edits another tower's or a worker's
   branch state (REQ-D1.2 division of labor).

**Autonomy and the reserved controls hold unchanged at the meta tier.**
Unattended, the meta-tower honors the autonomous-safe-decision policy exactly
as a single tower does — no looser autonomy, no fleet-only decision category;
every escalation routes to the owning spec's `## Awaiting input`, the one
cross-spec decision queue a human drains. Never-auto-merge holds at every
tier (REQ-A1.2): the meta-tower and every subordinate create draft PRs only;
the draft→ready flip and the merge stay the human's two reserved controls.

## Fleet entry — the one obvious command (`--fleet`; D-9, D-12, REQ-E1.1, REQ-E1.2, REQ-E1.5)

`/orchestrate --fleet` is **the** documented way to start fleet operation: it
runs the meta-tower watch loop (`--meta --watch`, unchanged) with the
**attention surface wired in as the default watch surface**. An operator on a
normal editor and terminal types this one command and never needs multiplexer
knowledge; from a plain shell, the same entry is
`claude "/orchestrate --fleet"` (headless, e.g. under cron:
`claude -p "/orchestrate --fleet --unattended"` — the flag rides inside the
quoted command). The approachable path is the *default presentation* of fleet
operation, not a degraded fallback behind tmux: full execution quality
(session-grade, steerable workers) remains available underneath it, because
quality lives in the execution seam and what the human watches lives in the
attention seam, and the two do not trade off (D-12,
[attention/notification capability](attention-notification-capability.md)).
The fleet operation guide (`docs/fleet.md`) documents the entry command and
the **persona → (execution backend × attention surface)** mapping (REQ-E1.6)
for adopters.

**Starting up.** Backend selection is exactly the skill's backend-selection
step (REQ-B1.4): attended, pipe `detect` through `present` and ask — the
operator picks an *execution* backend from the two-seam presentation, told
explicitly that the pick does not change what they watch; unattended,
`select-unattended` picks from config. Never a silent pick.

**The multiplexer as detached background plumbing (REQ-E1.1).** When the
selected backend is an interactive multiplexer and the operator did not ask
to attach, the tower drives it **detached**: start the server headlessly (for
the shipped tmux backend, `tmux new-session -d -s <fleet-session>` — the
session name is the operator's style, overlay-owned per D-10) and address
every window by target id. Dispatch, capture-pane observation, and
`load-buffer`/`paste-buffer` relay work identically against a detached server
— nobody ever attaches, and the human sees only the attention surface below.
Attaching stays available at any time for a multiplexer-fluent operator (the
mapping's persona a); it is never required.

**The attention surface (the queue as default, D-13).** The fleet-entry loop
keeps the attention store current and renders it, through
`scripts/fleet-attention.sh` (on the cross-spec home):

- **At dispatch** (subordinate launch or worker dispatch):
  `scripts/fleet-attention.sh heartbeat <worker> <spec>:task-<ids> working` —
  `<worker>` is the backend's **stable unit handle** from the capability
  contract's named-addressable-units guarantee (the tmux window id, the
  subagent handle), so every later `heartbeat`/`decide`/`clear` for the unit
  keys the same store row. The handle and its scope (one spec/unit per
  worker, isolated worktree/context) use the store's field grammar
  (colon-separated scope; the grammar has no slash), so `render` presents
  **per-worker scope** legibly (REQ-E1.5).
- **On a halt → `## Awaiting input`**: mirror the entry as a structured
  decision — `scripts/fleet-attention.sh decide <worker> <scope> <question>
  <default> <options> [priority]` — so the queue's length tracks the
  `## Awaiting input` count, never the worker count. The `tasks.md` entry
  remains the durable record; the queue row is its projection.
- **On reconcile observations**: heartbeat `pr-ready` when a draft PR is up,
  `merged` on an observed merge, and `clear <worker>` at teardown
  (merged-window cleanup). The mirror is **level-triggered like the sweep
  itself**: each iteration reconciles the store to the observed state — write
  a row only on an observed *change* (an unchanged row keeps its commit-time
  stamp, preserving the queue's oldest-first order), re-issue a missing
  `decide` for a still-open `## Awaiting input` entry, and `clear` any row
  whose unit is no longer in flight or awaiting input — so a crash between an
  edge and its mirror, a lost write, or a late heartbeat self-heals within
  one iteration and stale workers do not linger on the surface.
- **Each watch iteration ends by rendering the surface**:
  `scripts/fleet-attention.sh render` (per-worker scope + state), then
  `scripts/fleet-attention.sh queue` (the ordered decision queue). When the
  selected backend **advertises** `provides_attention_surface=true`, pass
  `--surface-provided`: the queue defers to the backend's own surface while
  `render` stays available — adapt to the advertised set, never the name.

Attention calls are **best-effort surface maintenance**: a failed
`heartbeat`/`decide`/`clear` is reported and never halts the step — the
`tasks.md` entry stays the durable record, and the level-triggered mirror
repairs the surface on the next iteration.

The queue and renderer read plain files under the durable fleet home, so the
same surface is readable from a plain terminal, a popup over a detached
server, or an editor panel — a new surface is a renderer, not a new execution
model.

**Nothing else changes.** `--fleet` adds presentation, not autonomy: every
meta-tower rule (fleet lock, live-count bound, subordinate independence), the
autonomous-safe-decision policy, and the reserved controls hold exactly as
written above.
