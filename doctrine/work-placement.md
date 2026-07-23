# Work Placement

Where should a unit of work run: inline in the tower's own context, or offloaded
to a worker — and if offloaded, on which rung? planwright answers with two
axioms. They are rules about how a tower *thinks*, not about what backends *are*
(that is the [backend capability contract](backend-capability-contract.md)), and
they have two consumers: the `/offload` skill — the sole home of adaptive
backend selection — and the tower's own inline-vs-offload judgment during
orchestration.

Citations: execution-backends D-1 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4,
REQ-C1.5 · obs:3414579b.

## The tower-frugality axiom

The tower's context window is its scarcest resource: every byte ingested inline
is paid for on every subsequent turn. The axiom bounds what stays inline to
exactly two classes:

- **Pure reasoning over existing context.** Thinking about what is already in
  the window — planning, weighing a decision, composing a reply — ingests
  nothing new and gains nothing from a worker.
- **The operational heartbeat.** Bounded small-result state checks and the
  reserved decision-maker actions. A sub-1KB lookup (a status probe, a lock
  check, an anchor compare) is negative-ROI to offload: the dispatch overhead
  exceeds the context it saves. And decision-critical verification evidence
  stays first-hand — the tower verifies with its own read what it is about to
  act on, because a relayed claim is not evidence.

**Everything with large or unpredictable context ingestion offloads.** Reading
a diff of unknown size, sweeping many files, running a review pass, research,
log analysis: if the tower cannot bound what the work will pull into context,
the work does not belong in the tower. The failure mode this prevents is the
tower silently filling its own window with ingestion a worker could have
absorbed, then losing the orchestration state it exists to hold.

## The smallest-sufficient-rung axiom

Offloaded work picks the cheapest rung that is *sufficient*, never the richest
available: **subagent unless the work must survive the tower, be
human-attachable, or run beyond the session.**

The three escalation predicates are exactly the properties the in-harness
subagent rung lacks (its advertised set in the contract):

- **Survive the tower.** A subagent shares the tower's lifecycle. Work that
  must keep running if the tower dies or retires needs a session-grade rung.
- **Human-attachable.** Work the operator may want to step into live needs an
  interactive rung; no non-interactive rung becomes attachable later.
- **Run beyond the session.** Work that outlives this session (a long
  background run, a watch loop) needs a rung whose worker is a separate
  top-level session.

When none of the three holds, the subagent rung is sufficient: isolated
context, parallel, completion-notifies, at `light` overhead. The contract's
`overhead` property is the cost input to this choice — work that does not need
a full session should not pay for one — and the advertised capability sets, not
backend names, are what sufficiency is evaluated against. The cost class
informs the choice; it never overrides a safety property.

## Never silent at the boundary

Both axioms have an ask-not-guess edge, owned by `/offload` (REQ-C1.4):

- A petition that **under-determines** the escalation predicates is asked
  about, never guessed at. Rung choice encodes what the work must survive;
  guessing wrong strands or overpays silently.
- A determined sufficient rung that is **not advertised present** on the host
  is surfaced, never silently substituted: dispatch to an insufficient rung is
  never silent. The operator chooses — degrade knowingly, pick another rung, or
  abort.

And every dispatch reports: the worker's handle plus how to observe or attach
to it as the selected backend advertises (a rung with no observe surface
reports that fact), and a failed dispatch is reported with its failure, never
silently dropped (REQ-C1.5).

## Placement, not policy

These axioms govern *placement* of a given piece of work. They do not choose
the fleet's configured `dispatch_backend` (operator policy, resolved through
the config overlays), do not reorder the degradation ladder, and do not touch
the unattended-selection safety rules — an unattended tower still never
silently selects an interactive backend, and degradation degrades capability,
never safety. Where the axioms and a safety rule would conflict, the safety
rule wins.
