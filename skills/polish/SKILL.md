---
name: polish
description: >
  Autonomous act-then-review convergence loop: iterate /self-review passes,
  draining every action disposition (Auto-applicable and Agent-resolvable
  applied, Needs-sign-off applied on the branch) until only irreducible
  Needs-human-judgment forks remain, then hand off the full audit record. Local-only: never pushes, never
  creates a PR. Pass --nested when invoked from a parent skill (such as
  /execute-task) that owns the handoff.
argument-hint: "[--nested]"
---

# /polish

The autonomous act-then-review loop (REQ-E2.1, D-12): repeat the `/self-review`
pass against the feature branch until it drains every action disposition and
only irreducible Needs-human-judgment forks (if any) remain, then hand off the
audit record. Polish is **local-only** per the invariants below; after the
read-only fetch that pins the base at pre-flight, iterations never touch the
remote (nested `/self-review` passes reuse the pinned base without
fetching). The pending-sign-off
checklist it emits reaches the draft PR through whichever skill owns PR
creation (`/execute-task` per REQ-E1.5, or a standalone `/self-review`).

## Doctrine

Resolve and read the same rule docs as `/self-review`, listed in the manifest
below, via the rule-doc resolution convention
(`scripts/resolve-rule-doc.sh <doc-name>` or the documented
`PLANWRIGHT_ROOT`/`CLAUDE_PLUGIN_ROOT` chain). Their definitions govern
wherever this skill names a concept. If a rule doc does not resolve, halt with
a clear message naming the missing doc and the chain consulted.

Doctrine manifest (per `doctrine/instruction-hygiene.md`; `run-start` docs
load before work begins, `point-of-use` at the named step):

Doctrine: run-start discovery-rigor
Doctrine: run-start validation-rigor
Doctrine: run-start finding-categorization
Doctrine: run-start gate-wiring
Doctrine: point-of-use research-rigor (the nested /self-review pass's finding-validation)
Doctrine: run-start refactor-instinct
Doctrine: run-start security-posture
Doctrine: run-start proportionality

## Invocation modes

Read the literal flag `--nested` from `$ARGUMENTS` at the start of the run:

- **Standalone** (no flag): on exit, present the handoff to the human.
- **Nested** (`--nested`): a parent skill (typically `/execute-task`, which
  runs Polish as its convergence step per REQ-E1.4) invoked the loop
  in-session and receives the handoff; the parent owns the PR body the audit
  record lands in.

The loop behaves identically in both modes. Nested
invocation is in-session skill composition (REQ-E2.2, D-13): one session, one
context, hooks fire once per actual tool call, not once per skill layer.
Record the resolved mode in every iteration summary.

## Pre-flight

1. **Resolve the doctrine docs** (above).
2. **Require a clean working tree.** `git status --porcelain` must be empty;
   the loop's commit boundaries (per the `gate-wiring` commit discipline) are
   the audit trail, and uncommitted changes make them ambiguous. Dirty tree:
   stop and ask the human to commit or stash first (dispatched or
   unattended: record the unit to `tasks.md` Awaiting input and end the
   step, the pause protocol's dispatched arm); never stash or discard
   yourself.
3. **Identify the base and the active kickoff brief** exactly as
   `/self-review` pre-flight does. Record both; with no active brief the
   Agent-resolvable bucket is unavailable for the whole run.
4. **Initialize the loop ledger**: an iteration counter at zero, plus the
   record of every finding the loop has already dispositioned (applied,
   resolved, applied pending sign-off, declined, queued).

## Iteration loop

Each iteration:

1. **Run a `/self-review` pass, nested.** Invoke `/self-review --nested`
   in-session. The pass does its own discovery, validation, routing, and
   dispositions per the gate wiring, and returns the audit record; its
   finding-validation is where `research-rigor` loads point-of-use. Pass the
   loop ledger in: findings already dispositioned in a previous iteration are
   not re-routed (a declined finding stays declined; a queued fork stays
   queued), with one deliberate exception: a re-discovered finding whose
   ledger disposition is any on-branch application (applied, resolved, or
   applied pending sign-off) means the fix did not hold, and it counts
   toward the Loop detection safety condition instead of being suppressed.
   The signal never re-opens the item itself: a re-discovered
   pending-sign-off item keeps its checklist entry and its PR-review
   decision, and only the did-the-fix-hold signal escapes suppression.
2. **Fold the pass into the ledger.** Add every new disposition. Count the
   iteration's **new dispositions** of any kind: findings newly applied
   (Auto-applicable), resolved with evidence (Agent-resolvable), applied
   pending sign-off, declined with rationale, or queued. "New" means not
   already in the ledger: a re-discovered, already-dispositioned finding
   never counts, however it was dispositioned. ("Action dispositions"
   elsewhere in this skill means only the three applied-on-branch kinds;
   the convergence counter deliberately counts all five.)
3. **Check the safety conditions** (below). Any trigger: stop per its row.
4. **Converged?** If the pass produced zero new dispositions (everything
   found was already in the ledger, or nothing was found), the loop is
   drained: exit to the handoff. Otherwise
   print the iteration summary (iteration number, mode, brief path, new
   dispositions by bucket, commits created, tooling result), increment the
   iteration counter, and loop.

Finding fixes commit inside the pass per the `gate-wiring` commit
discipline, including the marked-subject self-lint the pass performs
(loop-level writes, such as observation fragment writes, take their own chore
commit at the iteration boundary). Polish never
amends, squashes, rebases, or force-pushes; each iteration's commits stand as
the per-iteration audit trail.

**Signed-bundle edits.** Each iteration's nested pass runs the stale-anchor
pre-flight before its first edit to each Ready or Active bundle's anchored content, per
the meta-spec's writer prose (`doctrine/spec-format.md`, *Sign-off records and
content anchors*): a mismatch, an absent or unparseable entry, and a failed
recompute block that edit alike, and the loop repairs none of them: the
blocked finding queues as an irreducible fork whose route is the anchor
repair, and the iteration drains its remaining findings normally. An
expression-only fix carries its dated Changelog entry and the marked
`Class: expression-only` self-re-anchor entry citing that entry, in the same
commit as the edit, so the ritual never spans an iteration boundary. A
meaning-class fix stays unapplied and queued for a `/spec-kickoff` delta
re-walkthrough; the ledger keeps it queued rather than re-routing it on a
later iteration.

## Safety conditions (mandatory handoff)

The doctrine's two pause triggers interrupt mid-iteration and follow the
`gate-wiring` pause protocol. Everything else below stops the loop at an
iteration boundary (the
dirty-tree check runs at pre-flight, before iteration one; its handoff
emits empty `none` tables):

| Condition | Trigger |
| --- | --- |
| Wider-suite failure | The project's full test/lint/type-check suite fails after an iteration's fixes and the failure cannot be resolved within the findings' own scope. |
| Loop detection | A finding the ledger records as applied on the branch (applied, resolved, or applied pending sign-off) is re-discovered in a later iteration (same location, same rule or description; the ledger exception above). |
| Iteration cap | Ten iterations completed without convergence. |
| Dirty tree | Pre-flight found uncommitted changes (stops before iteration one). |

On any safety stop: emit the latest audit record, name the condition, and
hand off. Work already committed stays committed, each item undone by the
revert its checklist entry names; a stop never resets, stashes, or rewrites
prior dispositions.

## Handoff

On exit (converged or safety-stopped), emit the loop-end handoff in the
`gate-wiring` order, accumulated across all iterations:

1. The lens-coverage table from the final pass.
2. In the wiring doc's formats: the four bucket tables, the declined log, and
   the pending-sign-off checklist regenerated from the `[pending-sign-off]`
   commits ahead of the base.
3. The queued irreducible forks with their bespoke options: the only items
   that ask the human a question.
4. The final iteration's pass summary (the per-iteration summaries cover
   the rest).

Standalone, present all of it to the human and put the queued forks to them
directly. Nested, hand the record to the parent skill, which folds it into the draft PR
body it owns and surfaces the forks. Apply `security-posture` artifact data-hygiene to
everything emitted; the record is bound for a committed PR body.

## Local-only invariants

These hold at every step, in both modes:

- **Never** push, create a PR, or write to any remote. Remote interaction is
  limited to the single read-only base-pinning fetch at pre-flight. Polish
  converges the branch; publishing it is the owning skill's job.
- **Never** mark any PR ready for review, and never merge. The draft→ready
  flip and merge are the human's reserved controls.
- **Never** force-push, amend, squash, or rebase; new commits only.
- **Never** apply a finding in a hard-disqualifier zone without the pause
  protocol's human direction, however clear the fix looks.
- **Never** silently drop a finding: every routed finding ends in one of the
  five terminal dispositions, on the record.

## Observations

When the repository has adopted planwright (a `specs/` directory with at
least one spec bundle exists), record anything the loop surfaced that is
outside the branch's scope (recurring tooling gaps, doctrine gaps, complexity
trends) as one fragment per observation through the shared helper:
`scripts/obs-record.sh --slug <topic> --scope <repo> --text '<observation>'`
(resolved under the planwright root; it composes the one-line entry form and
writes one file under the host repo's `specs/_observations/entries/`)
(REQ-E2.1, REQ-H1.6). Commit fragments within the iteration that produced
them (its action commit, or a chore commit), so the tree returns to clean at
every iteration boundary; surface a non-zero helper exit rather than
silently dropping the observation. Skip this step entirely in repositories
without `specs/`.

## Maintenance

After the loop exits (converged or stopped), compare these instructions
against the resolved doctrine docs listed above (REQ-B3.2, D-42). If a
concept this skill names has changed meaning, gained or lost a step, or moved
between docs, record a drift observation through the shared helper
(`scripts/obs-record.sh --slug skill-drift --scope <repo> --text
'skill-drift(polish): <what>'` — the entry text keeps the `skill-drift(...)`
prefix; in repositories without `specs/`, surface the drift to the user
instead of recording it), commit the fragment (its own chore commit), and
tell the user what drifted; surface a non-zero helper exit rather than
silently dropping the observation. Do not edit this skill or the doctrine
docs to resolve the drift; the accumulator's canonical reader
(`/spec-draft`) owns folding drift into spec amendments.
