# The Fleet Coordination Floor

Two floors constrain every fleet mechanism planwright runs — the towers that
dispatch and the daemon layer that self-maintains. They are doctrine, not
mechanism: each was mined from a real incident or a real bootstrapping
constraint, and every fleet skill, hook, and daemon script operates under
them. The fleet-autonomy bundle carries the requirements; this document is
the doctrine statement those requirements cite into force.

Citations: fleet-autonomy REQ-G1.1, fleet-autonomy REQ-G1.2 ·
fleet-autonomy D-17, fleet-autonomy D-18.

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
