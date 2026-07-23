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
Extended in place by execution-backends (its D-2): the `overhead` and
`hook_registration` properties, the `stream-json-persistent` and
`headless-oneshot` rows, the pinned ladder ordering, the non-`--bare` pinning
rule, and the 6→8 adapter grammar (execution-backends D-3, D-5, D-6, D-7,
D-8, D-12, D-13 · REQ-A1.1–A1.9).

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
  the worker keep running and can it still produce signed commits on its branch —
  **or**, for a supervised session, is the session *recoverable*: it persists a
  `session_id` and survives supervisor death via `--resume`, losing no
  session-grade property (execution-backends D-5)? Session-grade-as-recoverable
  is the same yes: the session outlives the process that watches it.

Named-addressable-units and liveness are the baseline expectations any real
execution backend must meet. Observe-in-flight, steer-in-flight, and
session-grade spawn are the three that genuinely vary across substrates:
observe and steer are foregrounded as advertised booleans below, while
session-grade is a distinct quality property tracked per backend (the
degradation ladder and the backend table order backends partly by it).

The contract also names two advertised **properties** (execution-backends
REQ-A1.1), each with an evaluable definition like the capabilities above:

- **`overhead`** — the backend's fixed per-dispatch cost class
  (execution-backends D-6): a small qualitative enum, not a latency
  measurement. The pinned classes (execution-backends REQ-A1.8), cheapest to
  most expensive:
  `none` | `light` | `full-session` | `full-session+supervisor`.
  *Evaluable:* what does one dispatch cost before the worker does any work —
  `none` (no new process: the printed command or the tower's own session),
  `light` (an in-harness worker inside an existing session), `full-session` (a
  new top-level CLI session), or `full-session+supervisor` (a new session plus
  a supervisor process planwright runs alongside it)? "Most conservative" — the
  legacy-adapter default below (execution-backends D-13) — is the **highest**
  class, `full-session+supervisor`.
- **`hook_registration`** — whether the backend's dispatched worker process
  registers planwright's plugin hooks and can push liveness/attention events
  (execution-backends D-7). *Evaluable:* does dispatching a worker on this
  backend launch a process that loads the harness surface (SessionStart and
  the session-lifecycle hooks) under planwright's dispatch env, so hook pushes
  fire and reach the fleet state? Consumers read this field —
  `fleet-liveness.sh push-capable` selects the push mechanism from it — and
  never key on backend names.

## The advertisement set

A backend self-describes with an advertised capability set — the five booleans:

```yaml
{ interactive, can_observe, can_steer_inflight, provides_attention_surface, supports_parallel }
```

plus the three per-backend quality/cost properties recorded in the table below:
session-grade, `overhead`, and `hook_registration`.

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
recorded per backend in the table below and orders the degradation ladder,
alongside the `overhead` and `hook_registration` properties defined above.

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
- **`hook_registration: false`** → the worker's process fires no planwright
  hooks, so liveness uses the observation path; `true` → hook-push liveness.
  `fleet-liveness.sh push-capable` reads this field from the contract — never
  a backend-name case — so a new backend gets the right liveness mechanism
  with no fleet-liveness edit (execution-backends D-7).
- **`overhead`** → an input to smallest-sufficient-rung placement: work that
  does not need a full session should not pay for one. The class informs the
  choice; it never overrides a safety property.

## The backends, by advertised set

The shipped `dispatch_backend` values (bootstrap D-38, extended by
execution-backends D-3) described by their advertised capability sets, in the
pinned ladder order below. `n/a` marks a capability that is structurally
inapplicable (there is no separate worker to observe or steer), distinct from
`false` (a separate worker exists but the capability is absent).

| Backend | `interactive` | `can_observe` | `can_steer_inflight` | `provides_attention_surface` | `supports_parallel` | Session-grade | `overhead` | `hook_registration` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `tmux` | true | true | true | false | true | yes | `full-session` | true |
| `stream-json-persistent` | false | true | true | false | true | yes | `full-session+supervisor` | true |
| `headless-oneshot` | false | false | false | false | true | yes | `full-session` | true |
| `subagent` | false | false | false | false | true | no | `light` | false |
| `print` | false | false | false | false | n/a | deferred | `none` | false |
| `in-session` | false | n/a | n/a | false | false | no | `none` | false |

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
- **`stream-json-persistent`.** A supervisor-owned persistent `claude -p`
  worker driving the same binary and harness as an interactive session
  (SessionStart hooks fire under `-p`; execution-backends REQ-A1.3): the
  supervisor owns the worker's stdio, the event stream provides a structured
  observe-in-flight surface, and message-in provides steer-in-flight. Its
  session-grade is the *recoverable* arm of the evaluable definition
  (execution-backends D-5): the worker persists a `session_id` and survives
  supervisor death via `--resume`. Ambiguity and permission asks route to the
  decision queue, never auto-answered. Overhead is
  `full-session+supervisor` — the full session plus the supervisor process.
- **`headless-oneshot`.** A detached one-shot `claude -p` worker
  (execution-backends REQ-A1.2): its own full context window and harness
  surface (non-`--bare`, per the pinning rule below), commits as a principal,
  survives the tower, and its session persists and is resumable — session-grade
  **yes**. No mid-flight observe or steer: the tower acts on the completion
  signal plus positive-evidence-of-death liveness, and ambiguity routes to the
  queue. To dispatch: create the unit's worktree with
  `scripts/fleet-dispatch-worktree.sh dispatch <spec> <id> --no-attach`, then
  `scripts/fleet-dispatch-headless.sh launch <spec> <id> --worktree <dir>`
  with the worker's brief on stdin (passed as data, REQ-A1.9); consume
  `fleet-dispatch-headless.sh status <spec> <id>` (`completed <rc>` /
  `running` / `died` / `unknown` / `absent` — death only on the
  death-evidence predicate's positive verdict) and the unit's captured
  `result.json`. The one-shot never attaches a permission prompt tool: an
  unauthorized ask fails under `--print`'s non-interactive default and lands
  visibly in the result and completion signal — there is no pend path.
- **`subagent`** (the shipped `dispatch_backend` default). A background worker
  with isolated context and a
  native worktree, whose completion notifies the tower. It is parallel and
  addressable, but **in-harness**: it shares the tower's lifecycle and does not
  survive the tower's death, so it is **not session-grade** (execution-backends
  REQ-A1.4), and it exposes no live mid-task read (no observe) and no live
  message-in of a *busy* worker. It **is steerable via resume-with-context** —
  the tower can continue a completed-turn subagent with its context intact and
  a course-correcting message — which is a between-turns steer, not
  steer-in-flight, so `can_steer_inflight` stays false. Its gaps are
  session-grade spawn, observe, and in-flight steer.
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

A contract row ships in the contract and registry ahead of its dispatch
support: until the dispatch rung lands, host autodetection reports it absent
by default, so the unattended pick does not select a rung the tower cannot
yet drive. `headless-oneshot`'s dispatch support landed with
execution-backends Task 3 (`scripts/fleet-dispatch-headless.sh`: detached
launch, completion signal, positive-evidence-of-death liveness), so its
presence default is the installed-CLI probe; `stream-json-persistent` still
defaults absent until its dispatch support lands (execution-backends
Task 4). (The `PLANWRIGHT_BACKEND_*` presence overrides are a deliberate
test/early-adopter escape hatch that bypasses these defaults; forcing a row
present makes it selectable before its dispatch wiring exists.)

## The pinned degradation ladder

The degradation ladder (D-3, `/orchestrate`) orders backends richest-to-safest
by their advertised sets. With the execution-backends rows the ordering is
**pinned** (execution-backends REQ-A1.8, D-8):

`tmux` > `stream-json-persistent` > `headless-oneshot` > `subagent` > `print`/`in-session`

and the `overhead` enum is pinned to exactly the classes
`none` | `light` | `full-session` | `full-session+supervisor`, with "most
conservative" (the legacy-adapter default, execution-backends D-13) defined as
the highest class. Ladder position never overrides a safety property: an
unattended tower still never silently selects an interactive backend, and the
manual `print` rung is never an autonomous descent target.

## The non-`--bare` launch pin

Every headless and stream-json **worker dispatch** launch invocation
planwright emits — every `-p`-family worker launch site — **pins non-`--bare`
behavior explicitly** (execution-backends REQ-A1.5, D-12), so a future CLI
default flip cannot silently strip SessionStart hooks and harness surface from
every headless worker at once. At the verified CLI version there is no
explicit inverse flag: pinning means **never passing `--bare`** at any worker
launch site, enforced by the launch-pin guard (the `-p`-family site scan in
`tests/test-dispatch-launch-pin.sh`; worker launch sites use the statically
greppable long `--print` form) and per-task
re-verification against the running CLI (execution-backends D-4). A future CLI
that ships an explicit non-bare flag flips the pin to passing that flag at
every worker launch site. The pin scopes to worker dispatch only: a
non-dispatch `-p` harness that deliberately excludes the operator's surface is
exempt, not a violation — the prompt-eval harness
(`scripts/prompt-eval.sh`) passes `--bare --plugin-dir` precisely because a
hermetic eval must not load the operator's settings, hooks, or CLAUDE.md.

## Adding a backend

A new terminal or multiplexer becomes a backend by **implementing and
advertising** the contract — no edit to the consuming skills. Backend selection
stays in the `dispatch_backend` config option (see
`docs/options-reference.md`), resolved through
the four overlay layers; `/orchestrate` autodetects candidates, reads each
advertised set, and adapts as above. planwright stays declarative — a backend is
a small adapter that answers the contract, not an arbitrary-code extension host —
so the capability set, not a hardcoded enum, is what a new substrate must
satisfy.

A backend adapter is an executable named `planwright-backend-<name>` on `PATH`
that answers `advertise` by printing its capability set as one
whitespace-separated line of **eight fields**, in contract order
(execution-backends D-13, REQ-A1.7):

```text
interactive can_observe can_steer_inflight provides_attention_surface supports_parallel session_grade overhead hook_registration
```

The first five are the advertised booleans (each `true`, `false`, or `na` for a
structurally-inapplicable capability); the sixth carries session-grade (`yes`,
`no`, or `deferred`); the seventh is the `overhead` class (one of the pinned
enum above); the eighth is the `hook_registration` boolean (`true` or `false`).
A pluggable backend advertises these in the line because — unlike the shipped
backends — it has no row in the table above for planwright to read them from.

The grammar is **6→8 back-compatible**: a legacy **six-field** line remains
valid, taken with fail-safe defaults — `hook_registration=false` and `overhead`
treated as the most conservative class, `full-session+supervisor`. Any other
arity (seven, nine or more) is **malformed**, and a malformed line fails closed
with a **visible diagnostic** on stderr — the backend is never selected, and
the refusal is never a silent absence. Advertise lines are treated as untrusted
input (execution-backends REQ-A1.9): the first line is length-bounded (512
bytes) and stripped of control bytes (the echo-safety C0/DEL/C1 range)
**before** any parse, use, or echo, and no diagnostic reproduces line content.
`/orchestrate` reports an adapter absent (the fail-safe: a backend whose
capabilities are unknown is never selected) when `advertise` is missing or its
output is not a well-formed six- or eight-field set.
