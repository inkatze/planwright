# Seed brief: make cross-spec dependency edges gate selection

Captured 2026-10-29 at the `invariant-tasks` kickoff delta re-walkthrough,
where that bundle's Task 11 gained a `cross-spec, hard` edge on
`custom-spec-location` Task 11 and the review found that no part of the
pipeline enforces such an edge.

Suggested invocation, from a fresh session in the planwright repo:

    /spec-draft

Fold-detection may route it to an extension of `orchestration-concurrency`
or `invariant-tasks`; follow its recommendation.

## The gap

A `Dependencies:` line can name a task in another bundle (the form
`specs/kickoff-lifecycle/tasks.md` uses, and now `invariant-tasks` Task
11), but the edge is advisory only:

- The shared dependency tokenizer in `scripts/spec-parse.sh`
  (`spec_parse_dep_ids`, the `sub(/\(.*/, "", s)` step) drops everything
  from the first `(` onward, so a cross-spec clause never reaches the
  selector's graph.
- The derivation engine (`scripts/orchestrate-state.sh`, the dependency
  token loop) reads the raw line and splits only on commas and whitespace.
  A cross-spec clause written outside a parenthetical leaks its foreign id
  in as a local dependency (a `Task 11` clause on Task 11 becomes a
  self-edge), and a token ending in `;` is dropped as malformed.
- `scripts/spec-validate.sh` errors when a task id follows a parenthetical
  on the line, which is why the edge has to sit inside one.

So a task whose cross-spec prerequisite has not merged is dispatchable,
and the only guard is prose in its `Done when:`.

## What it needs

- A grammar for a cross-spec edge that every tokenizer reads the same way
  (spec name plus task id).
- Selection that resolves the foreign task's derived state and withholds
  the dependent until it is Completed, failing closed when the foreign
  bundle cannot be read.
- The engine's tokenizer brought onto the shared one, so the two cannot
  disagree about an edge.

## Questions for the drafter

- Does a cross-spec edge resolve against the foreign bundle's derivation
  in the same repository only, or through the work-repository registry as
  well?
- Hard versus soft: does a soft edge rank without gating?
- Migration of the existing prose-form edges.
