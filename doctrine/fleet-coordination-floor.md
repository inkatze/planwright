# The Fleet Coordination Floor

Five floors constrain every fleet mechanism planwright runs — the towers that
dispatch and the daemon layer that self-maintains. They are doctrine, not
mechanism: each was mined from a real incident or a real bootstrapping
constraint, and every fleet skill, hook, and daemon script operates under
them. The fleet-autonomy, concurrent-orchestrator-coordination, and
fleet-lifecycle-closure bundles carry the requirements; this document is the
doctrine statement those requirements cite into force.

Citations: fleet-autonomy REQ-G1.1, REQ-G1.2 · fleet-autonomy D-17, D-18 ·
concurrent-orchestrator-coordination REQ-A1.1, REQ-D1.3, REQ-D1.6 ·
concurrent-orchestrator-coordination D-1, D-6 · fleet-lifecycle-closure
REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-B1.4, REQ-C1.1,
REQ-C1.7, REQ-D1.3 · fleet-lifecycle-closure D-1, D-2, D-3.

## The tower non-authoring boundary

**A tower dispatches, monitors, and reconciles; it does not author repo,
config, or content changes itself.** The narrow exception: an
explicitly-flagged change surfaced as a Needs-human-judgment fork — never as
the default response to a "quick change" request (fleet-autonomy REQ-G1.1,
D-17).

The boundary was mined from a logged incident, not invented: on a loose
request, a tower directly reversed a rationale-documented decision (disabling
a markdownlint rule) and opened its own PR, instead of surfacing the
decision-reversal as a fork or routing the edit as a worker chore. Nothing in
doctrine said that was out of bounds, so nothing stopped it — the classic
unstated-floor failure. This statement closes the gap at its source.

What the boundary means in practice:

- **Dispatch, monitor, reconcile are the tower's verbs.** Selecting a ready
  unit, creating the dispatch record, relaying to a worker, sweeping PR and
  branch state, healing derived state — all in bounds. These writes are
  orchestration state, not authored content.
- **Repo, config, and content edits route to workers.** A code fix, a config
  tweak, a doc change — however small — is a worker's task, carried on a task
  branch through the normal review pipeline. "It's just one line" is exactly
  the rationalization the incident logged.
- **A decision-reversal is a fork, not an edit.** When a request would undo a
  decision whose rationale is documented (a design D-ID, a config comment, a
  review disposition), the tower surfaces the alternatives as a
  Needs-human-judgment fork per the finding-categorization gate; it never
  picks a side by editing.
- **The exception is flagged, never silent.** Where an edit by the tower is
  genuinely warranted, it is surfaced first as an explicit fork naming what
  would be changed and why the tower (not a worker) would change it — the
  human routes it.

## The no-LLM-daemon-mechanics invariant

**No daemon, hook, or cron mechanism invokes an LLM to make a routine
mechanical decision.** A liveness check, a cleanup, a throttle decision —
every such mechanism is deterministic script logic operating on structured
signals: files, process IDs, git state, pattern-matched known text. LLM
invocation stays reserved for the tower and worker sessions doing the actual
task work (fleet-autonomy REQ-G1.2, D-18).

Two independent reasons hold the floor:

- **The bootstrapping absurdity.** The daemon layer exists in part to manage
  rate-limit and cost pressure on the fleet's model usage. A fleet-mechanics
  decision that itself requires an LLM call becomes subject to the exact
  resource problem it exists to manage: the throttle that cannot run because
  it is being throttled.
- **Destructive actions need deterministic evidence.** A kill, cleanup, or
  restart decision made by model judgment over ambiguous signals is the
  failure mode the positive-evidence-of-death predicate
  (`scripts/fleet-death-evidence.sh`, backend-capability-contract) exists to
  prevent. A daemon acts on a positive, structured signal or it does not act.

The line this draws: *mechanics* are deterministic, *work* is agentic.
Workers remain full session-grade Claude Code sessions, and towers remain
sessions that exercise judgment about dispatch and escalation — but the
machinery that watches, cleans, throttles, and audits them is plain script,
auditable line by line (`scripts/fleet-daemon-gate.sh`,
`scripts/fleet-audit.sh`), pausable by one operator switch
(`fleet_daemon_pause`), and incapable of quietly spending model budget.

## The assume-multiplicity floor

**A tower assumes multiplicity, not solitude: it keeps tabs on the other
live towers operating on the same repository and coordinates a disjoint
division of work, rather than behaving as the sole orchestrator**
(concurrent-orchestrator-coordination REQ-A1.1; the altitude call is
recorded as concurrent-orchestrator-coordination D-1).

This floor too was mined from a real gap, not invented: concurrently-started
towers advanced work against one checkout with no awareness of each other —
in the operator's framing, "orchestrators don't seem to keep tabs … in case
there are other orchs running or just other work the towers are not aware
of." Nothing in doctrine said a tower should look, so none did — the same
unstated-floor failure shape as the non-authoring boundary above.

What the floor means in practice:

- **Awareness is discovered, never assumed.** A tower discovers live peers
  from a deterministic presence signal at startup and on a heartbeat
  thereafter. An empty, broken, or unreadable awareness surface degrades
  awareness and is surfaced; it never licenses the solitude assumption.
- **Division has one authoritative floor.** No unit is dispatched by more
  than one tower; the guarantee is authoritative in the per-unit `origin`
  fence (concurrent-orchestrator-coordination REQ-C1.1), with the presence
  surface used for attribution only, never on the correctness path.
- **Residue is surfaced, never silent.** A dead owner's unfinished work is
  surfaced to the operator for a reserved reclaim decision, not
  auto-recovered on a guess and never silently dropped.
- **The existing floors carry unchanged** (concurrent-orchestrator-coordination
  REQ-D1.3). Every discovery, attribution, or reclaim-surfacing decision is
  deterministic script logic on structured signals, bound by the
  no-LLM-daemon-mechanics invariant above and by positive evidence of death
  (`scripts/fleet-death-evidence.sh`) — and nothing about assuming
  multiplicity re-opens auto-merge, autonomous PR-ready marking, or the
  tower non-authoring boundary.

## The deterministic-attention floor

**A reserved-human moment — a merge-ready PR — reaches the operator by a
deterministic push; an LLM tower polling GitHub is the fallback, never the
sole path** (concurrent-orchestrator-coordination REQ-D1.6, D-1).

The companion of assume-multiplicity on the tower→human axis: the same
"don't rely on a single fragile actor" discipline, applied to attention
rather than coordination. It is likewise incident-mined — merge-ready PRs
sat un-surfaced because the tower that could have noticed did not poll in
time, the live proof that model-side polling as the sole attention path
fails exactly when attention matters.

This is a doctrine line only. The mechanism that realizes it — the hook
mapping a worker's ready-flip to a record on the attention surface, and the
reclassification of that surface's `pr-ready` state from non-actionable to
actionable — is owned by the planned `merge-currency-guard` spec and is
cross-referenced, not implemented, by the bundle that records this floor
(concurrent-orchestrator-coordination D-6, REQ-D1.6).

## The lifecycle-closure floor

**Every resource class a worker acquires owes three deterministic things: an
open that starts the phase and records that it started, a close that ends it
and releases the resource, and a script-readable stuck-detector. A class
missing any of the three is a defect, not a gap for operator vigilance to
cover** (fleet-lifecycle-closure REQ-A1.1–REQ-A1.5; the altitude call is
recorded as fleet-lifecycle-closure D-1).

Incident-mined like the floors above, and unstated in the same way. Every
session-grade rung shipped a launch verb and no stop. A worker that reaches
SessionEnd exits cleanly, so the common path looks tidy; only workers
abandoned mid-flight or hard-killed leak, and they leak silently. Roughly 95
cumulative hours of leaked worker time accumulated that way before anyone
noticed (obs:b63a8778). Detection failed in the
same shape: a monitor sampling a worker's last pane line reported eleven
identical heartbeats for a frozen worker, because the line was stable
*precisely because* it was stuck (obs:50eac4ac).

What the floor means in practice:

- **A lifecycle phase is a resource class, not a stage of the work.** A worker
  acquires its process tree, its tmux window, the locks it holds, its scratch
  temp, and its attention record independently, so each owes the three parts
  in its own right (REQ-A1.1). How far along its unit a worker is rides a
  separate axis with its own name, `stage` (REQ-C1.7).
- **Silence is never a signal.** All three parts are deterministic script
  logic over structured signals — files, process ids, git state, positively
  matched known text. Elapsed time, an unchanging pane, and "the tower should
  notice" are none of those; the detector enumerates its states positively,
  each from its own signal (REQ-A1.2, REQ-C1.1, and the
  no-LLM-daemon-mechanics invariant above).
- **A partial close reports as partial.** A close enumerates every class it
  releases and names any it could not release. A release that did not complete
  is never reported as success (REQ-A1.3).
- **A backend declares all three for every class it acquires.** A rung with no
  separate worker satisfies the close trivially and says so explicitly; a rung
  whose worker exists only after a human acts declares which parts it defers
  and to whom. An absent row is the omission this floor exists to make visible
  (REQ-A1.5).

### Reaping releases processes, never units

**A close releases the OS process and its runtime resources. It never
releases, moves, or resolves the unit of work** (fleet-lifecycle-closure D-2,
REQ-D1.3, REQ-B1.4). The per-unit `origin` fence, the branch, and the worktree
are left untouched, and a strand is still surfaced for the operator's reserved
reclaim decision.

This is the boundary against the assume-multiplicity floor's reclaim rule, not
an exception to it. `concurrent-orchestrator-coordination` puts automatic
reclaim of a dead tower's in-flight unit explicitly out of scope: a
fenced-but-unfinished unit is surfaced, "never auto-probed and
auto-reclaimed". That rule governs *work*; this one governs *processes*. The
fence decides who may work a unit, the reaper decides what processes exist,
and the audit rule keeping them apart is one line: **if the act would change
what a future dispatch sees, it is not a reap.**

### An open that can refuse is never registered for observation

**Before registering a hook on a lifecycle event, establish what that event
reads SILENCE as. Where a registered hook replaces the native operation, a
hook that says nothing has refused it, and only that operation's implementer
may be registered there** (fleet-lifecycle-closure REQ-H1.1–REQ-H1.4, D-11).

The floor above is about closing what a worker opened. This is about the open
itself being correct, and it is mined from planwright doing the opposite.
`WorktreeCreate` was registered to a passive tracker. The tracker read
`worktree_path` from a payload that carries `name`, found nothing, echoed
nothing, and exited 0 — and because that event reads silence as refusal,
worktree creation broke on every installed machine. Nothing failed until a
human hand-probed the hook (obs:f51f6b6e).

The corrected contract, verified against the CLI's own payload construction
across 2.1.226 / 2.1.237 / 2.1.239 / 2.1.241 rather than the published docs,
which omit it: **`WorktreeCreate` supplies a worktree `name`, and a registered
hook is the creator — expected to produce the worktree and report its path.
`WorktreeRemove` supplies a `worktree_path`, because there the worktree already
exists.** The two are not variants of one shape. The earlier reading, that a
hook echoes an inbound `worktree_path` unchanged, back-filled remove onto
create and is superseded (obs:a6f5511b, superseded by obs:46886617).

What this means in practice:

- **Classify by what silence does, not by whether the event can block.**
  `PreToolUse` and `Stop` can both block, yet a quiet hook on either leaves the
  operation untouched; registering an observer there is free. `WorktreeCreate`
  is the other kind. Only the second kind constrains registration (REQ-H1.2).
- **Wanting observation is not a reason to register.** planwright wanted
  worktree tracking and that event grants no passive mode, so planwright
  registers no `WorktreeCreate` hook at all. Tracking rides the two paths that
  cannot refuse anything: a `record-create` at the dispatch seam and the `scan`
  reconcile.
- **A refusal is stated on a channel the operator sees.** Hook stderr is
  discarded on most events, so a reason left there is indistinguishable from an
  unexplained platform failure — the property that turned a one-line bug into a
  binary inspection. Refusals go out as `systemMessage` or the event's decision
  field (REQ-H1.3, REQ-K1.1).
- **The contract is pinned, not remembered.** Every registered event has a
  payload fixture holding its real key set, and
  `scripts/check-hook-contracts.sh` enforces all of the above in `mise run
  check`, so the next schema divergence fails a test rather than the fleet
  (REQ-H1.1).

### The class contract

Each class's three parts and the mechanism of record for each. The mechanisms
named here are instantiated by the `fleet-lifecycle-closure` bundle; this table
is the contract they satisfy, not a second specification of them.

| Resource class | Open | Close | Detector |
| --- | --- | --- | --- |
| Process tree | the rung's launch, recording the supervisor and worker pids under the worker's state directory and the worker-registry record written at the dispatch seam | the rung's `stop` — SIGTERM then SIGKILL after a bounded grace, matched on the worker's state-directory path and on the pids that directory records, never a bare process name; the pid half is only as good as the pid files: a pid recorded before a crash and since reused is signalled, and as a root of the descendant walk it costs that process its whole subtree — a close clears the files afterwards, which bounds how long the exposure lasts but does not prevent the signal, and binding a recorded pid to its worker is open work; autonomously, gap: no process actuator ships yet — the planned `process` mode of `scripts/fleet-cleanup.sh` carries the same self-targeting guard, kill-switch gate, and audit trail when it lands | `scripts/fleet-death-evidence.sh`'s positive verdict, feeding the four-state classifier (`working` / `waiting-on-a-human` / `finished-but-unreaped` / `dead`) |
| tmux window | the tmux dispatch seam creates the named window and records its `#{window_id}` as the handle (`scripts/offload-dispatch.sh`; the tower's own `new-window` on the `/orchestrate` path) | `stop` as part of the release set; autonomously `scripts/fleet-cleanup.sh window`, under its self-targeting guard, kill-switch gate, and audit trail | every pane dead (`#{pane_dead}`), the positive evidence the cleanup actuator already demands |
| Locks | `scripts/fleet-state.sh lock` for the cross-spec store; the supervisor's own atomic `mkdir` elections (`journal.lock`, `recover.lock`, `launch.lock`) | released by the holder on the normal path; on the abnormal path a break at a documented bound — positive evidence that the recorded holder is gone where an election records one, a stale age otherwise — so a killed holder cannot wedge the verb permanently; the rung's `stop` releases the whole class as a second close | the recorded holder's liveness, else the lock directory's age against that same bound |
| Scratch temp | created under the worker's state directory across its life: the stdio fifos, the staging temps each writer makes beside its target, and the residue a stale lock-break renames aside | its own class in the rung's `stop`, released after the process tree rather than with it, so a tree that will not close does not cost a live worker its channel; the captured result is durable record and is kept | residue under the state directory of a worker whose session has ended |
| Attention record | `scripts/fleet-attention.sh heartbeat` / `decide` / `fork` / `park`, one row per worker | `scripts/fleet-attention.sh clear`, invoked by the close verb | the row's own state field, which is script-readable; a terminal row (`merged`, `done`) still present is the residue signal |

### The rungs, crossed with the classes

Every rung in `backend-capability-contract.md` against every class above. A
cell is that rung's instance of the class's three parts: **per contract** means
the class row applies unchanged, **—** means the rung structurally does not
acquire the class, and **n/a** means the rung runs no separate worker at all,
so the class is the tower's own rather than a worker's. No cell is ever left
blank: a class a rung acquires without one of the three parts is written
`gap: <what is missing>`, so a gap is declared where the reader looks for it
and never inferred from white space. A rung present in the capability contract
and absent here is the omission REQ-A1.5 exists to catch.

| Rung | Process tree | tmux window | Locks | Scratch temp | Attention record |
| --- | --- | --- | --- | --- | --- |
| `tmux` | no supervisor and no pidfile: `tmux new-window -d` spawns the worker and its `#{window_id}` is the whole record, so the tree is released by killing the window rather than by a rung `stop`, and its death evidence is `scripts/fleet-death-evidence.sh`'s `tmux-window` class, never its `process` class | per contract, minus the `stop` arm — `scripts/fleet-cleanup.sh window` is the only close | per contract — it runs the same scripts, so it takes the same store locks | — no worker state directory; the dispatch seam's own stderr capture is trap-cleaned in process | per contract |
| `stream-json-persistent` | per contract; the close covers the supervisor *and* its children | — no window | per contract, plus the supervisor's own `journal.lock` / `recover.lock` / `launch.lock` | per contract; the stdio fifos and the staging temps are in the release set, while the captured result is durable record on this rung and is kept | per contract |
| `headless-oneshot` | per contract; a detached one-shot, closed the same way; gap: the `stop` arm does not ship yet — `scripts/fleet-dispatch-headless.sh` advertises `launch` only, and the close is a later task in this bundle | — no window | per contract (store locks only) | per contract; when the close lands, the captured result is durable record here too and is kept — REQ-B1.4's release set does not name it, and on this rung it is the whole point of the run | per contract |
| `subagent` | trivial — in-harness, no separate OS process; it dies with the tower | — no window | per contract — it runs the same scripts, so it takes the same store locks and is subject to the same stale-break | trivial — no worker state directory | trivial — the tower owns the row |
| `print` | deferred → the human who runs the printed command; `print` units are exempt from the orphan/liveness predicate for exactly this reason | deferred → human | deferred → human | deferred → human | deferred → human |
| `in-session` | n/a — no separate worker at all; every class is the tower's own | n/a | n/a | n/a | n/a |

The bottom three rows are the point of the cross, not filler: `subagent`
acquires store locks and nothing else, and owes the contract for them; `print`
defers every part to the human; `in-session` acquires nothing separate at all.
None of the three is exempt by silence (REQ-A1.5).

## Scope boundary: adjacent mechanisms keep their own owners

The floors above constrain every fleet mechanism; they deliberately absorb
none of the adjacent mechanisms. Each stays in its own bundle with a single
owner (concurrent-orchestrator-coordination D-6):

- **Usage and quota governance** — `fleet-autonomy`, which owns the
  reactive rate-limit throttle and the proactive shared-usage governance.
- **The inter-tower relay** — `orchestration-fleet`, whose attributed,
  non-impersonating relay is consumed as a contract, never forked.
- **The deterministic PR-ready-push mechanism** — the planned
  `merge-currency-guard` spec, which owns the ready-surface interception
  that mechanism shares with its stale-flip guard.
- **Worktree reclamation** — `scripts/fleet-cleanup.sh worktree` and its
  positive-evidence checks. The worktree is deliberately not a class in the
  lifecycle floor's release set: every class there is reproducible, and the
  worktree is the only one holding work that cannot be recovered
  (fleet-lifecycle-closure D-3).
