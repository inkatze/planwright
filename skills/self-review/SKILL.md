---
name: self-review
description: >
  Gate-wired review pass of the current feature branch: Discovery Rigor
  fan-out, three-pass validation, act-then-review dispositions per the finding
  categorization, full audit record (lens-coverage table, four bucket tables,
  declined log, pending-sign-off checklist). Standalone runs push and open or
  update a draft PR; pass --nested to stay local and return the audit record
  to the invoking skill.
argument-hint: "[--nested]"
---

# /self-review

One complete review pass of the feature branch against its base, wired into
planwright's act-then-review autonomy gate (REQ-E2.1, D-12). Discovery Rigor
produces the finding list, Validation Rigor confirms it, the finding
categorization routes every confirmed finding to a disposition, and the gate
wiring's audit record is what the pass hands over. `/polish` iterates this
pass to convergence; this skill is the single pass.

## Doctrine

This skill is procedure, not doctrine. Resolve and read these rule docs at
run start via the rule-doc resolution convention
(`scripts/resolve-rule-doc.sh <doc-name>` under the resolved planwright root,
or the documented `PLANWRIGHT_ROOT`/`CLAUDE_PLUGIN_ROOT` chain); their
definitions govern wherever this skill names a concept:

- `discovery-rigor` — lens checklist, lens-coverage table, tool-grounded
  discovery, fan-out, self-critique pass
- `validation-rigor` — the three validation passes; solution validation,
  including the altitude check
- `finding-categorization` — the four buckets, their predicates, hard-pause
  zones, declined-with-rationale, the resolution ladder
- `gate-wiring` — routing order, commit discipline, checklist and audit
  formats, ladder procedure, pause protocol, loop-end handoff
- `refactor-instinct` (review mode), `security-posture` (artifact
  data-hygiene), `proportionality` (declared scoping)

If a rule doc does not resolve, halt with a clear message naming the missing
doc and the resolution chain consulted. The docs are the rules this skill
applies; reviewing without them would silently substitute improvisation for
doctrine.

## Invocation modes

Read the literal flag `--nested` from `$ARGUMENTS` at the start of the run:

- **Standalone** (no flag): the pass ends by pushing the branch and creating
  or updating a draft PR carrying the audit record (see "Publishing the audit
  record").
- **Nested** (`--nested`): another planwright skill (typically `/polish`)
  invoked this pass in the same session and owns everything after it. Skip
  pushing and PR handling entirely; end by handing the audit record back to
  the invoking skill.

Nested invocation is in-session skill composition (REQ-E2.2, D-13): the pass
runs in the invoking skill's session and context, and hooks fire once per
actual tool call, not once per skill layer. Record the resolved mode in the
pass summary.

## Pre-flight

1. **Resolve the doctrine docs** (above). Halt with a clear message on a
   resolution failure.
2. **Identify the base and capture the diff.** Fetch first, then diff against
   the remote-tracking base: `git fetch origin` and
   `git diff origin/main...HEAD` (substitute the repository's actual default
   branch). Fall back to the local base only when no remote is configured
   (REQ-K1.7); a stale local base in a long-lived worktree inflates the diff
   with already-merged commits. Not a git repository, or no commits to diff:
   surface a clear message and stop; there is nothing to review.
3. **Require a clean working tree.** The gate's commit discipline (one commit
   per Needs-sign-off finding, batched action commits) needs unambiguous
   boundaries. If `git status --porcelain` is non-empty, surface the dirty
   state and ask before proceeding; never stash or discard.
4. **Run the project's tooling once.** Whatever the project ships: linters,
   formatters, type-checkers, static analyzers, security scanners. Discover
   them via the project's task runner and config files, CI workflow
   definitions, and the tool-discovery summary when a SessionStart hook has
   injected one. Capture the output; it is shared input for every lens.
5. **Detect the active kickoff brief.** Walk in order, stopping at the first
   unambiguous match: the branch convention `planwright/<spec>/task-<ids>`
   names the spec, so the brief is `specs/<spec>/kickoff-brief.md` (validate
   the parsed `<spec>` segment against the spec-identifier discipline,
   `^[a-z0-9][a-z0-9-]*$` and at most 64 characters per REQ-A1.8, before
   forming the path; a failing segment is treated as no match, never
   interpolated); otherwise
   a single Active spec (`specs/*/requirements.md` with `Status: Active`)
   with a sibling `kickoff-brief.md`; otherwise ask when attended. With no
   active brief, the Agent-resolvable bucket is unavailable for this pass
   (its predicate requires brief alignment); record that and proceed with
   the remaining buckets.

## Discovery

Apply the `discovery-rigor` doc against the diff:

- **Fan out by default.** Spawn one read-only sub-agent per canonical lens
  for any non-trivial diff, each with the diff slice, the shared tooling
  output, and a single-lens brief that forbids severity pruning. Walk the
  lenses inline only when the diff is small and narrow (a few files, mostly
  prose or config, a few hundred changed lines at most); inline walking
  waives no other invariant. Declare which path was taken.
- **Merge and dedupe.** A finding hitting two lenses gets one row with both
  lens labels.
- **Filter refactor flags in review mode** per `refactor-instinct`: anchored
  in tool output or made worse by this branch, otherwise dropped.
- **Emit the canonical lens-coverage table** before any per-finding output:
  one row per lens, empty lenses as `none` or `n/a` with a one-line reason.
- **Run the mandatory self-critique pass**: assume the list is incomplete,
  re-scan for what is under-represented, add what surfaces.

## Validation

Apply the `validation-rigor` doc to every candidate finding. Declared scoping
(per `proportionality`): the full three passes are mandatory for any finding
that could be **applied on the branch** in this pass, which under
act-then-review means Auto-applicable, Agent-resolvable, and Needs-sign-off
candidates alike (the human sees Needs-sign-off fixes only after application,
at PR review). A soft-floor spot-check (drop clear false positives) is
sufficient for findings that will only be declined or queued as judgment
forks, since the human finishes validation when deciding those. Findings
whose passes do not converge are never applied; they are dropped, declined
with the divergence recorded, or routed to Needs human judgment per the
categorization.

## Routing and dispositions

Route every validated finding through the `gate-wiring` doc's routing order:
zone screen first, then bucket assignment per the `finding-categorization`
predicates, then disposition by bucket. The wiring doc governs the mechanics
this skill executes:

- Auto-applicable and Agent-resolvable items are applied or resolved with
  their audit and evidence rows; their fixes get solution validation per
  `validation-rigor` (targeted check, wider project suite, altitude check).
  Regression tests for Agent-resolvable items are written first and confirmed
  to fail for the finding's exact reason before the fix.
- Needs-sign-off items are applied on the branch, one commit per finding
  with the `[pending-sign-off]` subject marker, and entered in the
  pending-sign-off checklist.
- Needs-human-judgment candidates climb the resolution ladder; every
  consulted rung is recorded. Only irreducible forks queue, with bespoke
  options.
- Declined-with-rationale is available at any step after validation;
  rationale rows are mandatory.
- A hard-disqualifier zone or a blocking irreducible fork triggers the pause
  protocol; nothing else interrupts the pass.

If any applied fix breaks the wider project suite and the breakage cannot be
resolved within the finding's own scope, revert that finding's change (new
commit, never history rewrite), record the outcome in its row, and surface
the failure in the pass summary.

## The audit record

The pass produces, in this order (the wiring doc's loop-end handoff):

1. The lens-coverage table.
2. The four bucket tables in fixed order, an empty bucket as a single `none`
   row, columns per the wiring doc's formats.
3. The declined log.
4. The pending-sign-off checklist, regenerated from the
   `[pending-sign-off]` commits ahead of the base per the wiring doc (an
   empty checklist emits with a single `none` row).
5. Queued irreducible forks with their bespoke options; in an attended
   standalone run these are presented to the human now, as the only
   questions the pass asks.

Table content lands in a committed PR body: apply `security-posture` artifact
data-hygiene before emitting (no secrets, credentials, or sensitive
operational detail in finding text or captured output).

## Publishing the audit record (standalone only)

Skipped entirely in nested mode; the invoking skill owns push and PR.

1. **Push:** `git push origin <branch>` (with `-u` on first push). Never
   force-push. On push or authentication failure, degrade gracefully
   (REQ-K1.6, REQ-K1.7): the local work is intact and committed; surface
   what failed and stop.
2. **Draft PR:** if a PR already exists for the branch, update its body;
   otherwise `gh pr create --draft`. The body carries the audit record:
   the four tables, the declined log, and the pending-sign-off checklist.
   Regenerate the checklist section in place rather than appending, so
   re-runs never duplicate entries. The PR is always a draft; never mark it
   ready and never merge (the draft→ready flip is the human's universal
   review gate).

## Observations

When the repository has adopted planwright (a `specs/` directory with at
least one spec bundle exists), append anything noticed during the pass that
is outside the branch's scope (complexity growth, outdated patterns, tooling
gaps, doctrine gaps) to `specs/_observations/opportunities.md`, one line per
observation: `- <YYYY-MM-DD> [<repo>] <observation>`. Do not act on
observations during the pass; they are seed material for `/spec-draft`
(REQ-E2.1, REQ-H1.6). Skip this step entirely in repositories without
`specs/`.

## Maintenance

After the pass completes (or halts), compare these instructions against the
resolved doctrine docs listed above (REQ-B3.2, D-42). If a concept this skill
names has changed meaning, gained or lost a step, or moved between docs,
append a drift observation to `specs/_observations/opportunities.md` (format
above, prefixed `skill-drift(self-review):`) and tell the user what drifted.
Do not edit this skill or the doctrine docs to resolve the drift; the
observation log's reader owns folding drift into spec amendments.
