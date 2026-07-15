---
name: drain
description: >-
  Run the on-demand drain pass over every spec bundle's Gate deferral
  entries: evaluate structured GATE(when:) conditions, surface date and
  free-text gates, report malformed ones, and surface the observations log's
  unmined state. Read-only; nothing is auto-resolved or auto-dropped.
---

# /drain — on-demand gate drain pass

`/drain` is the on-demand entry point to the shared gate evaluator
(REQ-H1.4, D-17, D-31). It sweeps every spec bundle's `tasks.md` for
`**Gate:**` deferral entries, evaluates the structured `GATE(when: …)` ones
against the closed grammar (free-text gates surface unevaluated), and
presents the drain report. The scheduled entry point to the same
evaluator is `/orchestrate --bookkeeping`; neither may parse gates on its
own. Normative semantics (accumulator classes, grammar productions, lanes,
data-only handling) live in the `accumulator-taxonomy` doctrine doc — read
it via the rule-doc resolution path before interpreting the report.

Doctrine manifest (machine-parseable, per `doctrine/instruction-hygiene.md`;
`run-start` loads before work begins):

Doctrine: run-start accumulator-taxonomy

## Procedure

### 1. Resolve the evaluator and the specs root

Resolve the planwright root via the standard chain
(`PLANWRIGHT_ROOT` → `CLAUDE_PLUGIN_ROOT` → `<claude-dir>/planwright`); the
evaluator is `<root>/scripts/drain-gates.sh`. The specs root is the current
repository's `specs/` directory. If there is no `specs/` directory, report
that there is nothing to drain and stop (this is a read-only authoring-path
move: degrade gracefully, REQ-K1.7).

### 2. Run the evaluator

```sh
<planwright-root>/scripts/drain-gates.sh specs/
```

The evaluator resolves task-completion atoms through the derivation engine
(`scripts/orchestrate-state.sh`), which on a format-version 2 bundle is the
only completion source — no `## Completed` section exists (invariant-tasks
D-8); v1 bundles keep the v1 read. Version keying reads the declared
`Format-version:`; unparseable fails closed, never the v1 arm (D-7).
Exit 0 means the sweep completed — malformed gates are report content, not
failures. A non-zero exit means the evaluator could not run or could not
complete the sweep; surface the error verbatim and stop. A complete report
always ends with the `== summary ==` section; treat a report missing it as
a failed sweep, not a result.

### 3. Present the report

Relay the report grouped by what the human should do with each lane, in
this order:

1. **MALFORMED** — drain-report-level errors. For each, show the file:line,
   the reason, and the offending gate text, and propose the corrected entry
   (restate the condition in the closed grammar, or reword it as a free-text
   gate if it cannot be said in the grammar). Never evaluate or guess around
   a malformed gate.
2. **SATISFIED** — condition gates whose atoms all hold: these items have
   re-surfaced and are actionable now.
3. **SURFACED** — date gates whose date has been reached (reminders, not
   proof; a human judges whether the world caught up with the date).
4. **FREE-TEXT** — gates the machine never evaluates; list them so the
   human can judge each condition.
5. **PENDING / DORMANT** — not yet actionable; summarize counts, with
   detail on request.
6. **Observations** — the unmined count and oldest-entry age, derived from
   the fragment store (`entries/`) and the frozen legacy file's unconsumed
   lines and naming both surfaces, plus any stuck consumes (fragments
   annotated `Consumed-by:` but not yet moved to `archive/`) and skipped
   invalid fragments; the reminder that its canonical reader is `/spec-draft`
   (mining happens there, not here).

Items within each lane of each spec's section arrive ordered
low-confidence first (REQ-H1.5); when merging lanes across specs, re-sort
by the `[confidence]` tag so low still comes first.

### 4. Disposition (human-reserved)

The sweep never auto-resolves and never auto-drops (REQ-H1.4) — and neither
does this skill. For each re-surfaced or malformed item, ask the human what
to do (un-defer the work, record the decision, re-gate with a new condition,
fix the malformed entry, or leave it) and apply only what they choose. Edits
to `tasks.md` follow the normal state-move commit discipline
(`commit_on_state_move`) on v1 bundles; on a format-version 2 bundle the
edit is a human-payload write (a Deferred entry or reference bullet — the
task block never moves) and `commit_on_state_move` does not apply
(invariant-tasks D-2, D-7).

## Maintenance

After each run, compare these instructions against the doctrine and spec
they implement: the `accumulator-taxonomy` doctrine doc (lanes, grammar,
drain-pass contract) and REQ-H1.3/REQ-H1.4/REQ-H1.5. If the evaluator's
report format, lanes, or grammar have drifted from what this skill
describes, record a one-line drift observation through the shared helper
(`scripts/obs-record.sh --slug skill-drift --scope <repo> --text
'skill-drift(drain): <what>'` — the entry text keeps the `skill-drift(...)`
prefix) and commit the fragment as its own chore commit, per REQ-B3.2 /
D-42; surface a non-zero helper exit rather than silently dropping the
observation. In repositories without `specs/`, surface the drift to the
user instead of recording it. Do not edit this skill or the doctrine docs
to resolve the drift; the accumulator's canonical reader (`/spec-draft`)
owns folding drift into spec amendments.
