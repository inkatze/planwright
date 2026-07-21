---
name: self-review
description: >
  Gate-wired review pass of the current feature branch: Discovery Rigor
  fan-out, multi-pass validation, act-then-review dispositions per the finding
  categorization, full audit record (lens-coverage table, four bucket tables,
  declined log, pending-sign-off checklist). Standalone runs push and open or
  update a draft PR; pass --nested to stay local and return the audit record
  to the invoking skill.
argument-hint: "[--nested]"
---

# /self-review

One complete review pass of the feature branch against its base, wired into
planwright's act-then-review autonomy gate (REQ-E2.1, D-12): Discovery Rigor
produces the finding list, Validation Rigor confirms it, the finding
categorization routes each confirmed finding to a disposition, and the gate
wiring's audit record is the handoff. `/polish` iterates it to convergence;
this skill is the single pass.

## Doctrine

This skill is procedure, not doctrine. Resolve these rule docs via
the rule-doc resolution convention
(`scripts/resolve-rule-doc.sh <doc-name>` under the resolved planwright root,
or the documented `PLANWRIGHT_ROOT`/`CLAUDE_PLUGIN_ROOT` chain); their
definitions govern wherever this skill names a concept:

- `discovery-rigor` — lens checklist, lens-coverage table, tool-grounded
  discovery, fan-out, self-critique pass
- `validation-rigor` — the three identification passes plus the adversarial
  bi-directional re-validation; solution validation, including the altitude
  check; surface-relative whole-system end-to-end reproduction preferred
- `finding-categorization` — the four buckets, their predicates, hard
  pauses and the hard-disqualifier zones, declined-with-rationale, the
  resolution ladder
- `gate-wiring` — routing order, commit discipline, checklist and audit
  formats, ladder procedure, pause protocol, loop-end handoff, PR-body
  assembly
- `research-rigor` (point-of-use), `refactor-instinct` (review mode),
  `security-posture` (artifact data-hygiene), `proportionality` (declared
  scoping)

If a rule doc does not resolve, halt with a clear message naming the missing
doc and the resolution chain consulted.

Doctrine manifest (the reading model above in machine-parseable form, per
`doctrine/instruction-hygiene.md`; `run-start` docs load before work begins,
`point-of-use` at the named step):

Doctrine: run-start discovery-rigor
Doctrine: run-start validation-rigor
Doctrine: run-start finding-categorization
Doctrine: run-start gate-wiring
Doctrine: point-of-use research-rigor (the Validation step, where research triggers fire)
Doctrine: run-start refactor-instinct
Doctrine: run-start security-posture
Doctrine: run-start proportionality

## Invocation modes

Read the literal flag `--nested` from `$ARGUMENTS` at the start of the run:

- **Standalone** (no flag): the pass ends by pushing the branch and creating
  or updating a draft PR carrying the audit record (see "Publishing the audit
  record").
- **Nested** (`--nested`): another planwright skill (typically `/polish`)
  invoked this pass and owns everything after it. Skip push and PR handling;
  hand the audit record back to the invoking skill. It may pass its loop
  ledger of already-dispositioned findings: a re-discovered finding that
  already carries a disposition is reported in the audit record but never
  re-routed, re-applied, or re-paused. One exception: surface a
  re-discovered finding whose ledger disposition is any on-branch
  application (applied, resolved, or applied pending sign-off) prominently
  in the handed-back record; it signals the fix did not hold and feeds the
  invoking skill's loop detection.

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
   (REQ-K1.7), since a stale local base inflates the diff with already-merged
   commits. In nested mode, skip the fetch and reuse the base the invoking
   skill recorded at its own pre-flight; the parent owns remote interaction.
   Not a git repository, or no commits to diff: surface a clear message and
   stop; there is nothing to review.
3. **Require a clean working tree.** The gate's commit discipline (one commit
   per Needs-sign-off finding, batched action commits) needs unambiguous
   boundaries. If `git status --porcelain` is non-empty, surface the dirty
   state and ask before proceeding (dispatched or unattended: record the
   unit to `tasks.md` Awaiting input and end the step, the pause protocol's
   dispatched arm); never stash or discard.
4. **Run the project's tooling once.** Whatever the project ships: linters,
   formatters, type-checkers, static analyzers, security scanners. Discover
   them via the project's task runner and config files, CI workflow
   definitions, and the tool-discovery summary when a SessionStart hook has
   injected one. Capture the output; it is shared input for every lens. A
   tool whose runner itself errors out (as opposed to reporting rule
   violations) is surfaced in the pass summary as degraded grounding for the
   lenses that rely on it; never treat a crashed tool as a clean pass.
5. **Detect the active kickoff brief.** Walk in order, stopping at the first
   unambiguous match: the branch convention `planwright/<spec>/task-<ids>`
   names the spec, so the brief is `specs/<spec>/kickoff-brief.md` (validate
   the parsed `<spec>` segment against the spec-identifier discipline,
   `^[a-z0-9][a-z0-9-]*$` and at most 64 characters per REQ-A1.8, before
   forming the path; a failing segment is treated as no match, never
   interpolated); a branch-named spec whose own `kickoff-brief.md` is absent
   means the brief is absent for this pass, never a fall-through to another
   spec's brief. Otherwise resolve through the status render
   (`scripts/spec-status.sh` / `mise run status`; invariant-tasks D-6),
   accepting a `specs/*/` bundle whose derived status is Ready or Active — so
   a format-version-2 bundle with work in flight (stored Ready, derived
   Active) resolves, not only a stored-`Active` v1 spec. When exactly one such
   candidate exists, take its sibling `kickoff-brief.md`. A render error, zero
   candidates, or multiple Ready-or-Active candidates is not an unambiguous
   match: degrade to the existing arm — ask when attended, proceed brief-less
   when unattended or dispatched (D-2). With
   no active brief, the Agent-resolvable bucket is unavailable for this pass
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
  labels.
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
candidates alike. A soft-floor spot-check (drop clear false positives) is
sufficient for findings that will only be declined or queued as judgment
forks, since the human finishes validation when deciding those. Findings
whose passes do not converge are never applied; they are dropped, declined
with the divergence recorded, or routed to Needs human judgment per the
categorization.

When a finding turns on an external fact (an API contract, spec compliance, a
deprecated pattern or security claim, library behavior), the outside-in pass
reads `research-rigor` point-of-use here — source hierarchy, recency
discipline, antipattern check.

## Routing and dispositions

Route every validated finding through the `gate-wiring` doc's routing order:
zone screen first, then bucket assignment per the `finding-categorization`
predicates, then disposition by bucket. The wiring doc governs the mechanics
this skill executes:

- Auto-applicable and Agent-resolvable items are applied or resolved with
  their audit and evidence rows, and committed per the wiring doc's commit
  discipline (batched into the pass's action commit); their fixes get
  solution validation per `validation-rigor` (targeted check, wider project
  suite, altitude check).
  Regression tests for Agent-resolvable items are written first and confirmed
  to fail for the finding's exact reason before the fix.
- Needs-sign-off items are applied on the branch, one commit per finding
  with the `[pending-sign-off]` subject marker, and entered in the
  pending-sign-off checklist. Before committing, self-lint the subject by
  piping it in —
  `printf '%s\n' "$subject" | scripts/check-commit-msgs.sh --marker subject --stdin`
  (under the resolved planwright root) — so the marker sits at the canonical
  end-of-subject position (`gate-wiring`) and a mis-placed one is reworded
  before it reaches history.
- Needs-human-judgment candidates climb the resolution ladder; every
  consulted rung is recorded. Only irreducible forks queue, with bespoke
  options.
- Declined-with-rationale is available at any step after validation;
  rationale rows are mandatory.
- A hard-disqualifier zone or a blocking irreducible fork triggers the pause
  protocol; nothing else interrupts the pass.

If any applied fix breaks the wider project suite and the breakage cannot be
resolved within the finding's own scope, revert that finding's change (new
commit, never history rewrite) and surface the failure in the pass summary.
The reverted finding's terminal disposition is declined-with-rationale
("fix attempted, broke the wider suite, reverted"), recorded in the
declined log, where it stays visible and re-raisable without re-entering the
routing order.

## The audit record

The pass produces, in this order (the wiring doc's loop-end handoff,
extended with the lens-coverage table at the front and the pass summary at
the end):

1. The lens-coverage table.
2. The four bucket tables in fixed order, an empty bucket as a single `none`
   row, columns per the wiring doc's formats.
3. The declined log.
4. The pending-sign-off checklist, regenerated from the
   `[pending-sign-off]` commits ahead of the base per the wiring doc (an
   empty checklist emits with a single `none` row).
5. Queued irreducible forks with their bespoke options; in an attended
   standalone run these are the only questions presented to the human.
6. The pass summary: resolved mode, base used, tooling and wider-suite
   results, and any reverts or surfaced failures.

Table content lands in a committed PR body: apply `security-posture` artifact
data-hygiene before emitting (no secrets, credentials, or sensitive detail
in finding text or captured output).

## Publishing the audit record (standalone only)

Skipped entirely in nested mode; the invoking skill owns push and PR.
Publishing is the pass's final action: the Observations and Maintenance
steps below run first, so their chore commits land before the push.

1. **Push:** `git push origin <branch>` (with `-u` on first push). Never
   force-push. On push or authentication failure, degrade gracefully
   (REQ-K1.6, REQ-K1.7): the local work is committed; surface what failed
   and stop.
2. **Draft PR:** if a PR already exists for the branch, update its body;
   otherwise `gh pr create --draft` with an explicit `--title` and `--body`
   (headless `gh` prompts or fails without them). Assemble the body per the
   **PR-body assembly** section of the `gate-wiring` doctrine (summary first,
   the audit record collapsed in `<details>`, prose never hard-wrapped, the
   structure preserved on updates) — the single normative home for the layout
   (D-2). The collapsed audit record is this pass's own (the sequence in **The
   audit record** above). On update, regenerate the generated sections in
   place rather than appending, and never overwrite body content outside them
   (handwritten notes survive); re-runs never duplicate entries. The PR is
   always a draft; never mark it ready and never merge (the draft→ready flip
   is the human's call).

## Observations

When the repository has adopted planwright (a `specs/` directory with at
least one spec bundle exists), record anything noticed during the pass that
is outside the branch's scope (complexity growth, outdated patterns, tooling
gaps, doctrine gaps) as one fragment per observation through the shared
helper: `scripts/obs-record.sh --slug <topic> --scope <repo> --text
'<observation>'` (resolved under the planwright root; it writes one fragment
file under the host repo's `specs/_observations/entries/`). Commit the
fragment within the pass (the action commit, or its own chore commit when
nothing else landed); never leave the tree dirty at a pass boundary, and
surface a non-zero helper exit rather than silently dropping the
observation. Do not act on observations during the pass; they are seed
material for `/spec-draft` (REQ-E2.1, REQ-H1.6).

## Maintenance

After the pass completes (or halts), compare these instructions against the
resolved doctrine docs listed above (REQ-B3.2, D-42). If a concept this skill
names has changed meaning, gained or lost a step, or moved between docs,
record a drift observation through the shared helper (`scripts/obs-record.sh
--slug skill-drift --scope <repo> --text 'skill-drift(self-review): <what>'`
— the entry text keeps the `skill-drift(...)` prefix; in repositories
without `specs/`, surface the drift to the user instead of recording it),
commit the fragment as its own chore commit, tell the user what drifted, and
surface a non-zero helper exit rather than silently dropping the observation.
Do not edit this skill or the doctrine docs to resolve the drift; `/spec-draft`
owns folding drift into spec amendments.
