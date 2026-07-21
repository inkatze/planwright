# The selection contract

The mechanics of `/orchestrate`'s selection step — how `scripts/orchestrate-select.sh`
decides ready-task candidacy and what each of its exit codes means. The skill
names these at its point of use and follows the rules recorded here; lifting the
heavy mechanics out of the skill body keeps `skills/orchestrate/SKILL.md` within
its instruction budget (skill-rigor REQ-E1.1's compensating-trim path) while the
full contract stays authoritative in one place. The stop-conditions table and the
selection prose keep the lean report-and-end description inline; this doc carries
the reasons.

## Version-keyed candidacy (REQ-F1.2, REQ-C1.8, invariant-tasks D-8)

Completed / in-progress state is read from the **live derivation**
(`scripts/orchestrate-state.sh`: git + trailer + marker + gh evidence), not the
committed `tasks.md` snapshot (D-3, REQ-B1.2), so an already in-flight or completed
task is never re-dispatched. The dependency graph is still parsed from `tasks.md`;
per-block Status is advisory, not consulted.

A **ready** task is one the derivation reports neither completed nor in-progress,
every dependency completed, and not parked. Among ready tasks the selector returns
the head of the effort-weighted longest dependent chain, FIFO on ties.

Candidacy is **version-keyed** to the bundle's declared `Format-version:` — the
selector refuses a missing or unparseable one rather than guess (REQ-C1.8), because
the candidacy rules cannot be known without a parsed version:

- **version 1** — a task is a candidate while its block sits in `## Forward plan`;
  parking and completion move blocks between the placement sections.
- **format-version 2** — no placement section exists, so candidacy is purely
  derivational: parked-ness is a live reference bullet naming the task in
  `## Awaiting input`, `## Deferred`, or `## Out of scope` (a live bullet on the
  primary checkout's main view outranks git evidence).

## Exit contract

The selector's shipped exit codes (cross-read: `scripts/orchestrate-select.sh`):

- **Exit 0** with an id → that is the unit (subject to cohesion bundling).
- **Exit 1** (no ready unit) → nothing to dispatch this step. In `--watch` stop the
  loop; else report it and exit cleanly.
- **Exit 2** (missing/taskless `tasks.md`, or the derivation failed closed) → fail
  closed; halt with the message. Selecting against absent live truth would risk the
  double-dispatch the derivation exists to prevent.
- **Exit 3** (format-version 2 transient evidence hold) → a configured remote's
  evidence fetch failed (the engine's `degraded` record), so the derivation is
  partial. A format-version 2 bundle has no committed placement to cross-check, so
  selecting here could re-dispatch work whose completion evidence sits behind the
  failed fetch (REQ-B1.5). **Report the hold and end the step cleanly** — the same
  shape as lock contention, not a halt: the hold is transient by design (evidence
  settling), so a later step re-selects once it lands, and `--bookkeeping` needs no
  action. Version 1 selection keeps its documented degraded-but-proceed behavior
  (the record is forwarded to stderr) — v1 behavior unchanged.
