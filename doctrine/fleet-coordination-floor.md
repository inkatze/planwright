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
REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-D1.3 ·
fleet-lifecycle-closure D-1, D-2.

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
noticed (obs:b63a8778). Detection failed in the same shape: a monitor
sampling a worker's last pane line reported eleven identical heartbeats for a
frozen worker, because the line was stable *precisely because* it was stuck.

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
fenced-but-unfinished unit is surfaced for the operator, "never auto-probed
and auto-reclaimed". That rule governs *work*; this one governs *processes*,
and the two must not be collapsed — the fence decides who may work a unit, the
reaper decides what processes exist. The audit rule is one line: **if the act
would change what a future dispatch sees, it is not a reap.**

### The class contract

Each class's three parts and the mechanism of record for each. The close verbs
and the four-state detector are instantiated by the `fleet-lifecycle-closure`
bundle (its REQ-B and REQ-C groups); this table is the contract they satisfy,
not a second specification of them.

| Resource class | Open | Close | Detector |
| --- | --- | --- | --- |
| Process tree | the rung's launch, recording the supervisor and worker pids under the worker's state directory and the registry record written at the dispatch seam | the rung's `stop` — SIGTERM then SIGKILL after a bounded grace, matched on the worker's state-directory path and never a bare process name; autonomously, `fleet-cleanup.sh process` | `scripts/fleet-death-evidence.sh`'s positive verdict, feeding the four-state classifier (`working` / `waiting-on-a-human` / `finished-but-unreaped` / `dead`) |
| tmux window | the tmux dispatch seam creates the named window and records its `#{window_id}` as the handle (`scripts/offload-dispatch.sh`; the tower's own `new-window` on the `/orchestrate` path) | `stop` as part of the release set; autonomously `fleet-cleanup.sh window`, under its self-targeting guard, kill-switch gate, and audit trail | every pane dead (`#{pane_dead}`), the positive evidence the cleanup actuator already demands |
| Locks | `scripts/fleet-state.sh lock` for the cross-spec store; the supervisor's own atomic `mkdir` elections (`journal.lock`, `recover.lock`) | released by the holder on the normal path; on the abnormal path a stale-age break at a documented bound, so a killed holder cannot wedge the verb permanently | the lock directory's age against that same bound |
| Scratch temp | created under the worker's state directory at launch: the stdio fifos, the journal and init temp files, the captured result | removed with the process tree by `stop` | residue under the state directory of a worker whose session has ended |
| Attention record | `scripts/fleet-attention.sh heartbeat` / `decide` / `fork` / `park`, one row per worker | `scripts/fleet-attention.sh clear`, invoked by the close verb | the row's own state field, which is script-readable; a terminal row (`merged`, `done`) still present is the residue signal |

### The rungs, crossed with the classes

Every rung in `backend-capability-contract.md` against every class above. A
cell is that rung's instance of the class's three parts: **per contract** means
the class row applies unchanged, and **—** means the rung structurally does not
acquire the class. No cell is ever left blank: a class a rung acquires without
one of the three parts is written `gap: <what is missing>`, so a gap is
declared where the reader looks for it and never inferred from white space. A
rung present in the capability contract and absent here is the omission
REQ-A1.5 exists to catch.

| Rung | Process tree | tmux window | Locks | Scratch temp | Attention record |
| --- | --- | --- | --- | --- | --- |
| `tmux` | per contract | per contract | per contract | per contract | per contract |
| `stream-json-persistent` | per contract; the close covers the supervisor *and* its children | — no window | per contract, plus the supervisor's own `journal.lock` / `recover.lock` | per contract; the stdio fifos are in the release set | per contract |
| `headless-oneshot` | per contract; a detached one-shot, closed the same way | — no window | per contract (store locks only) | per contract; includes the captured result | per contract |
| `subagent` | trivial — in-harness, no separate OS process; it dies with the tower | — | per contract — it runs the same scripts, so it takes the same store locks and is subject to the same stale-break | trivial — no worker state directory | trivial — the tower owns the row |
| `print` | deferred → the human who runs the printed command; `print` units are exempt from the orphan/liveness predicate for exactly this reason | deferred → human | deferred → human | deferred → human | deferred → human |
| `in-session` | n/a — no separate worker at all; every class is the tower's own | n/a | n/a | n/a | n/a |

The bottom three rows are the point of the cross, not filler: `subagent`
acquires store locks and nothing else, and owes the contract for them;
`in-session` acquires nothing separate at all; `print` defers all three parts
and names to whom. None of them is silently exempt, and a rung added to the
capability contract states its cell for every class it acquires before it is
adopted (REQ-A1.5, `backend-capability-contract.md`).

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
