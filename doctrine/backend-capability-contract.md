# Backend Capability Contract

A dispatch backend is how `/orchestrate` hosts an execution worker: a tmux
window, a background subagent, a printed launch command, the tower's own
session. planwright used to name these backends one by one and special-case
each in the dispatch skills. This doc replaces that with a **capability
contract** — the named things a backend can do — plus **advertisement**: each
backend declares which capabilities it has, LSP/DAP-style, and the orchestrator
adapts to what is advertised rather than branching on the backend's name.

The contract is the shared **vocabulary**; advertisement is the **negotiation**.
Naming the capabilities turns "which backends exist" into "what a backend must
do and declare", so tmux, subagents, a headless pool, and a future terminal are
all just advertised capability sets. This collapses the N×M backend×skill
integration surface to N+M (the LSP/DAP lesson) and is the seam the
graceful-degradation ladder and the approachability facet build on.

The load-bearing move is splitting **observe-in-flight** and **steer-in-flight**
out of a generic "relay": those two properties — not tmux — are what made the
emergent fleet good, so the contract makes them first-class capabilities a
backend either has or lacks, never folded together.

Citations: REQ-B1.1, REQ-B1.2, REQ-B1.3 · D-2 (extends bootstrap D-38).

## The capabilities

The contract names five capabilities. Each has an **evaluable definition** — a
question with a yes/no answer for any concrete backend — so "does this backend
provide capability X" is decidable, not a matter of taste.

- **Named, addressable units.** Every dispatched worker has a stable handle the
  tower can name across steps and target an operation at. *Evaluable:* can the
  tower refer to one specific in-flight worker unambiguously (a tmux window id, a
  subagent handle) and address a later read or message at exactly that worker?
- **Observe-in-flight.** The tower can read a *running* worker's current state
  mid-task, not only its final output. First-class, never folded into a generic
  relay. *Evaluable:* is there a non-destructive read that returns a busy
  worker's live state while it keeps working (a `capture-pane` scrape), without
  interrupting or ending it?
- **Steer-in-flight.** The tower can deliver a clearly-attributed message into a
  *running, busy* worker to course-correct or answer, without killing and
  restarting it. First-class and distinct from observe. *Evaluable:* can a
  message reach a busy worker and be consumed by it, attributed to the tower,
  with no restart and **no impersonation** of the worker's own input line (no
  `send-keys`-style keystroke injection)?
- **Positive-evidence-of-death liveness.** Worker death is decided by *positive
  evidence* — the handle, window, or process is demonstrably gone — never by mere
  silence (the bootstrap REQ-F1.1 liveness predicate). *Evaluable:* does the
  backend expose a liveness check that returns "dead" only on positive evidence
  of death, and never conflates "quiet" with "dead"?
- **Session-grade spawn.** A worker is launched as a **separate top-level
  session**: full context window and harness surface, commits as a principal, and
  **survives the tower's death**. Its antithesis is a context-sharing in-harness
  subagent that dies with the tower. *Evaluable:* if the tower process dies, does
  the worker keep running and can it still produce signed commits on its branch?

Named-addressable-units and liveness are the baseline expectations any real
execution backend must meet. Observe-in-flight, steer-in-flight, and
session-grade spawn are the three that genuinely vary across substrates:
observe and steer are foregrounded as advertised booleans below, while
session-grade is a distinct quality property tracked per backend (the
degradation ladder and the backend table order backends partly by it).

## The advertisement set

A backend self-describes with an advertised capability set — at minimum these
five booleans:

```yaml
{ interactive, can_observe, can_steer_inflight, provides_attention_surface, supports_parallel }
```

- **`interactive`** — the backend hosts a session a human could attach to and
  drive directly (tmux). This governs unattended selection: an unattended tower
  must **never silently pick an interactive backend** (it would strand the run
  waiting on a human); it degrades down the ladder instead.
- **`can_observe`** — the backend provides **observe-in-flight** (above). When
  false, the tower has no live mid-task read and relies on completion signals
  plus positive-evidence-of-death liveness.
- **`can_steer_inflight`** — the backend provides **steer-in-flight** (above).
  When false, a worker that drifts off-path cannot be nudged live.
- **`provides_attention_surface`** — the backend supplies its own
  attention/decision surface (a cmux-class tool that renders the operator's
  queue itself). When true, planwright **suppresses its own** decision-queue
  rendering and defers to that backend's surface.
- **`supports_parallel`** — the backend can host multiple workers concurrently.
  When false, units run one at a time (the synchronous terminal rung) and the
  effective `max_parallel_units` is 1.

`can_observe` and `can_steer_inflight` map directly onto the observe/steer
capabilities. Named units and liveness are contract baselines rather than
per-backend toggles: a backend that cannot meet *those two* is the
manual/synchronous escape hatch, described in its row below. Session-grade spawn
is the third varying property; it is not one of the advertised booleans but is
recorded per backend in the table below and orders the degradation ladder.

## Orchestrator adaptation

The orchestrator reads the advertised set and adapts its behavior — it does not
branch on the backend's name:

- **`can_steer_inflight: false`** → the tower cannot nudge a worker once it is
  off-path, so ambiguity and decisions **route to the decision queue** for the
  human rather than a live steer. Such a backend is not a quality-equivalent
  middle rung on the degradation ladder.
- **`provides_attention_surface: true`** → planwright **does not render its own**
  decision queue; it defers to the backend's surface, so the operator sees one
  attention surface, not two.
- **`interactive: true`** in unattended mode → never selected silently; unattended
  selection reads config and degrades a missing rich backend down the ladder,
  never to a silently-chosen interactive backend.
- **`can_observe: false`** → the tower does not attempt a live state read; it acts
  on completion signals and the positive-evidence-of-death liveness check only.
- **`supports_parallel: false`** → the tower runs ready units sequentially (one
  worker at a time), the synchronous-terminal-rung behavior.

## Existing backends, by advertised set

The four shipped `dispatch_backend` values (bootstrap D-38) re-described by their
advertised capability sets. `n/a` marks a capability that is structurally
inapplicable (there is no separate worker to observe or steer), distinct from
`false` (a separate worker exists but the capability is absent).

| Backend | `interactive` | `can_observe` | `can_steer_inflight` | `provides_attention_surface` | `supports_parallel` | Session-grade |
| --- | --- | --- | --- | --- | --- | --- |
| `tmux` | true | true | true | false | true | yes |
| `subagent` (default) | false | false | false | false | true | no |
| `print` | false | false | false | false | n/a | deferred |
| `in-session` | false | n/a | n/a | false | false | no |

The `Session-grade` column appears because session-grade genuinely varies across
backends. The two baseline capabilities — named-addressable units and
positive-evidence-of-death liveness — get no column because every shipped backend
that hosts a separate worker satisfies them; the backends that do not (`print`
and `in-session`) are the manual/synchronous escape hatch called out in their
rows below.

- **`tmux`.** The richest backend: an interactive `claude --worktree` worker in a
  named window. `capture-pane` provides observe-in-flight; attributed
  `load-buffer`/`paste-buffer` provides steer-in-flight (never `send-keys`
  impersonation); a window id is the stable handle; the session is session-grade
  and survives the tower. Its cost is tmux fluency and installation — an
  *approachability* gap the attention-surface facet addresses, not a capability
  gap.
- **`subagent` (default).** A background worker with isolated context and a
  native worktree, whose completion notifies the tower. It is parallel and
  addressable, but **in-harness**: it shares the tower's lifecycle and does not
  survive the tower's death, so it is **not session-grade**, and it exposes no
  live mid-task read (no observe) and no live message-in (no steer). Its gaps are
  session-grade spawn, observe, and steer.
- **`print`.** Prepares the unit, prints the exact launch command, and exits —
  zero-dependency manual dispatch. The tower spawns no process, so observe,
  steer, and liveness are all absent (`print`-backend units are exempt from the
  orphan/liveness predicate for exactly this reason); session-grade is
  *deferred* to the human, who runs the printed `claude --worktree` command.
- **`in-session`.** Runs `/execute-task` in the tower's own session, with no
  separate worker. Observe and steer are `n/a` — there is nothing separate to
  observe or steer — and it is single-stream (no parallelism) and not a spawn at
  all. This is the substrate of the ladder's synchronous terminal rung: it needs
  no external tool and therefore always works.

The degradation ladder (D-3, `/orchestrate`) orders these richest-to-safest by
their advertised sets and anticipates further backends — for example a headless
`claude -p` pool advertising `{ interactive: false, can_observe: false,
can_steer_inflight: false, supports_parallel: true }` that is session-grade but
cannot be steered, so its ambiguity routes to the queue.

## Adding a backend

A new terminal or multiplexer becomes a backend by **implementing and
advertising** the contract — no edit to the consuming skills. Backend selection
stays in the `dispatch_backend` config option (see
[`docs/options-reference.md`](../docs/options-reference.md)), resolved through
the four overlay layers; `/orchestrate` autodetects candidates, reads each
advertised set, and adapts as above. planwright stays declarative — a backend is
a small adapter that answers the contract, not an arbitrary-code extension host —
so the capability set, not a hardcoded enum, is what a new substrate must
satisfy.

A backend adapter is an executable named `planwright-backend-<name>` on `PATH`
that answers `advertise` by printing its capability set as one
whitespace-separated line of **six fields**, in contract order:

```text
interactive can_observe can_steer_inflight provides_attention_surface supports_parallel session_grade
```

The first five are the advertised booleans (each `true`, `false`, or `na` for a
structurally-inapplicable capability); the sixth carries session-grade (`yes`,
`no`, or `deferred`). A pluggable backend advertises session-grade in this line
because — unlike the four shipped backends — it has no row in the table above for
planwright to read it from. `/orchestrate` reports an adapter absent (the
fail-safe: a backend whose capabilities are unknown is never selected) when
`advertise` is missing or its output is not a well-formed six-field set.
