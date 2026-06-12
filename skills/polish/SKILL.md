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
audit record. Polish is **local-only**: it never pushes, never creates or
touches a PR, and never interacts with a remote. The pending-sign-off
checklist it emits reaches the draft PR through whichever skill owns PR
creation (`/execute-task` per REQ-E1.5, or a standalone `/self-review`).

## Doctrine

Resolve and read the same rule docs as `/self-review` at run start via the
rule-doc resolution convention (`scripts/resolve-rule-doc.sh <doc-name>` or
the documented `PLANWRIGHT_ROOT`/`CLAUDE_PLUGIN_ROOT` chain):
`discovery-rigor`, `validation-rigor`, `finding-categorization`,
`gate-wiring`, `refactor-instinct`, `security-posture`, `proportionality`.
Their definitions govern wherever this skill names a concept. If a rule doc
does not resolve, halt with a clear message naming the missing doc and the
chain consulted.

## Invocation modes

Read the literal flag `--nested` from `$ARGUMENTS` at the start of the run:

- **Standalone** (no flag): on exit, present the handoff to the human.
- **Nested** (`--nested`): a parent skill (typically `/execute-task`, which
  runs Polish as its convergence step per REQ-E1.4) invoked the loop
  in-session and receives the handoff; the parent owns the PR body the audit
  record lands in.

Either way the loop itself behaves identically and stays local-only. Nested
invocation is in-session skill composition (REQ-E2.2, D-13): one session, one
context, hooks fire once per actual tool call, not once per skill layer.
Record the resolved mode in every iteration summary.

## Pre-flight

1. **Resolve the doctrine docs** (above).
2. **Require a clean working tree.** `git status --porcelain` must be empty;
   the loop's commit boundaries (per the `gate-wiring` commit discipline) are
   the audit trail, and uncommitted changes make them ambiguous. Dirty tree:
   stop and ask the human to commit or stash first; never stash or discard
   yourself.
3. **Identify the base and the active kickoff brief** exactly as
   `/self-review` pre-flight does (remote-tracking base first; brief from the
   `planwright/<spec>/task-<ids>` branch convention, with the parsed `<spec>`
   segment validated against the REQ-A1.8 identifier discipline before any
   path is formed; else the single Active spec). Record both; with no active
   brief the Agent-resolvable bucket is unavailable for the whole run.
4. **Initialize the loop ledger**: an iteration counter at zero, plus the
   record of every finding the loop has already dispositioned (applied,
   resolved, applied pending sign-off, declined, queued). The loop ledger is
   what makes convergence and loop detection decidable.

## Iteration loop

Each iteration:

1. **Run a `/self-review` pass, nested.** Invoke `/self-review --nested`
   in-session. The pass does its own discovery, validation, routing, and
   dispositions per the gate wiring, and returns the audit record. Pass the
   loop ledger in: findings already dispositioned in a previous iteration are
   not re-routed (a declined finding stays declined; a queued fork stays
   queued); re-discovering one is expected, re-dispositioning it is not.
2. **Fold the pass into the ledger.** Add every new disposition. Count the
   iteration's **new action dispositions**: findings newly applied
   (Auto-applicable), resolved with evidence (Agent-resolvable), applied
   pending sign-off, or declined with rationale. "New" means not already in
   the ledger: a re-discovered, already-dispositioned finding never counts,
   however it was dispositioned.
3. **Check the safety conditions** (below). Any trigger: stop per its row.
4. **Converged?** If the pass produced zero new action dispositions and
   nothing newly queued (everything found was already in the ledger, or
   nothing was found), the loop is drained: exit to the handoff. Otherwise
   print the iteration summary (iteration number, mode, brief path, new
   dispositions by bucket, commits created, tooling result) and loop.

Commits happen inside the pass per the `gate-wiring` commit discipline:
Needs-sign-off items one commit per finding with the `[pending-sign-off]`
marker, action items batched per iteration, regression tests landing with the
fix they prove. Polish never amends, squashes, rebases, or force-pushes; each
iteration's commits stand as the per-iteration audit trail.

## Safety conditions (mandatory handoff)

Exactly two things interrupt mid-iteration, per the doctrine's pause
protocol: a hard-disqualifier zone finding, or an irreducible
Needs-human-judgment fork that blocks further progress. Both follow the `gate-wiring` pause protocol
(attended: stop and present; dispatched or unattended: record the unit to
`tasks.md` Awaiting input with the finding and recommended fix, end the
step). Everything else below stops the loop **between** iterations:

| Condition | Trigger |
| --- | --- |
| Wider-suite failure | The project's full test/lint/type-check suite fails after an iteration's fixes and the failure cannot be resolved within the findings' own scope. The branch may be broken; a human should look before anything else lands. |
| Loop detection | The same finding (same location, same rule or description) was dispositioned as applied in two consecutive iterations. The fix is not actually resolving it. |
| Iteration cap | Ten iterations completed without convergence. A drain that long means discovery keeps producing genuinely new findings; a human should look at why. |
| Dirty tree | Pre-flight found uncommitted changes (stops before iteration one). |

On any safety stop: emit the latest audit record, name the condition, and
hand off. Work already committed stays committed (each item one revert from
undone); a stop never resets, stashes, or rewrites prior dispositions.

## Handoff

On exit (converged or safety-stopped), emit the loop-end handoff in the
`gate-wiring` order, accumulated across all iterations:

1. The lens-coverage table from the final pass.
2. The four bucket tables in fixed order, an empty bucket as a single `none`
   row. These are audit, not a decision queue.
3. The declined log.
4. The pending-sign-off checklist, regenerated from the `[pending-sign-off]`
   commits ahead of the base (a single `none` row when empty).
5. The queued irreducible forks with their bespoke options: the only items
   that ask the human a question. Bespoke options are the actual decision
   branches, never timing labels, per the categorization doctrine.

Standalone, present all of it to the human and put the queued forks to them
directly. Nested, hand the record to the parent skill, which folds the
tables, declined log, and checklist into the draft PR body it owns and
surfaces the forks. Apply `security-posture` artifact data-hygiene to
everything emitted; the record is bound for a committed PR body.

## Local-only invariants

These hold at every step, in both modes:

- **Never** push, create a PR, or touch a remote. Polish converges the
  branch; publishing it is the owning skill's job.
- **Never** mark any PR ready for review, and never merge. The draft→ready
  flip and merge are the human's reserved controls.
- **Never** force-push, amend, squash, or rebase; new commits only.
- **Never** apply a finding in a hard-disqualifier zone without the pause
  protocol's human direction, however clear the fix looks.
- **Never** silently drop a finding: every routed finding ends in one of the
  five terminal dispositions, on the record.

## Observations

When the repository has adopted planwright (a `specs/` directory with at
least one spec bundle exists), append anything the loop surfaced that is
outside the branch's scope (recurring tooling gaps, doctrine gaps, complexity
trends) to `specs/_observations/opportunities.md`, one line per observation:
`- <YYYY-MM-DD> [<repo>] <observation>` (REQ-E2.1, REQ-H1.6). Skip this step
entirely in repositories without `specs/`.

## Maintenance

After the loop exits (converged or stopped), compare these instructions
against the resolved doctrine docs listed above (REQ-B3.2, D-42). If a
concept this skill names has changed meaning, gained or lost a step, or moved
between docs, append a drift observation to
`specs/_observations/opportunities.md` (format above, prefixed
`skill-drift(polish):`) and tell the user what drifted. Do not edit this
skill or the doctrine docs to resolve the drift; the observation log's reader
owns folding drift into spec amendments.
