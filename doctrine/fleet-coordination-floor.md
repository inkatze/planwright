# The Fleet Coordination Floor

Four floors constrain every fleet mechanism planwright runs — the towers that
dispatch and the daemon layer that self-maintains. They are doctrine, not
mechanism: each was mined from a real incident or a real bootstrapping
constraint, and every fleet skill, hook, and daemon script operates under
them. The fleet-autonomy and concurrent-orchestrator-coordination bundles
carry the requirements; this document is the doctrine statement those
requirements cite into force.

Citations: fleet-autonomy REQ-G1.1, REQ-G1.2 · fleet-autonomy D-17, D-18 ·
concurrent-orchestrator-coordination REQ-A1.1, REQ-D1.3, REQ-D1.6 ·
concurrent-orchestrator-coordination D-1, D-6.

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
