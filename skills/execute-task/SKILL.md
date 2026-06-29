---
name: execute-task
description: >
  Implement one task (or a cohesion bundle) from a signed-off, Active spec:
  recompute the execution freshness gate, write the verifying test first,
  implement to green, run the project's full CI with adaptive retry, converge
  via the configured review_sequence (default /polish --nested), then open a
  draft PR referencing the brief, task IDs,
  REQs, tests, and the pending-sign-off checklist. The execution workhorse of
  the planwright pipeline. Assumes the worktree already exists; never creates
  worktrees, never merges, never marks a PR ready.
argument-hint: "<task-id> [<task-id> …] [<spec-path>]"
---

# /execute-task

The execution layer of the planwright pipeline (REQ-E1.1–REQ-E1.5): take one
ready unit — a single task or a cohesion bundle — from an Active spec with a
signed-off kickoff brief, and carry it from a failing test to a draft PR
without further human keystrokes. `/orchestrate` dispatches this skill into a
prepared worktree; a human may also invoke it directly inside one. It operates
from the kickoff brief, the durable contract (D-3), not by re-reading the
spec from scratch.

This skill assumes the worktree already exists and the spec is signed off. It
**never** creates worktrees (that is `/orchestrate`'s job or the human's
manual step, D-37, D-44), **never** merges, and **never** marks a PR ready for
review — sign-off and merge are the human's two reserved controls.

## Doctrine

This skill is procedure, not doctrine. Resolve and read these rule docs at
run start via the rule-doc resolution convention
(`scripts/resolve-rule-doc.sh <doc-name>` under the resolved planwright root,
or the documented `PLANWRIGHT_ROOT`/`CLAUDE_PLUGIN_ROOT` chain); their
definitions govern wherever this skill names a concept:

- `spec-format` — the meta-spec: status lifecycle, the kickoff-brief
  structure, the amendment ritual, sign-off records, content anchors, and the
  sanctioned anchor command forms. This skill is a freshness-gate reader and
  the marked expression-only self-re-anchor writer the meta-spec names.
- `research-rigor` — pre-implementation triggers, source hierarchy, recency
  discipline, antipattern check, and risk-register recording.
- `security-posture` — write-time security triggers and artifact
  data-hygiene (the brief, risk register, and PR body are committed
  artifacts).
- `validation-rigor` — the solution-validation angles behind the test-first
  loop (targeted test, wider suite, altitude check).
- `finding-categorization` and `gate-wiring` — the buckets, hard-disqualifier
  zones, pending-sign-off checklist, and pause protocol the convergence step
  (the `review_sequence` knob, `/polish` by default) applies and this skill
  folds into the PR.
- `proportionality` — rigor and research depth scale with stake and
  reversibility; scoping is declared, never silent.

If any of those do not resolve, halt with a clear message naming the
missing doc and the resolution chain consulted. `/execute-task` runs only on a
dispatch path, where a missing prerequisite fails closed (REQ-K1.7):
implementing against a contract whose defining rules cannot be read is the
opaque failure. One doc resolves with graceful degradation instead:

- `decision-domains` — the catalog behind the drift triggers below. Absent
  (an adopter who has not installed the catalog, or a resolution failure):
  note the missing catalog in one line, skip the drift check, and rely on the
  engineering judgment the catalog would otherwise structure.

## Pre-flight

Run once per invocation, in order. Any halt records the unit to the spec's
`tasks.md` `## Awaiting input` section with the reason and ends the step (the
`gate-wiring` pause protocol's dispatched arm); in an attended session,
present the reason and wait instead.

1. **Parse `$ARGUMENTS`.** Extract one or more task IDs (`5`, `3.5`, or
   `5 6` for a bundle) and an optional spec path, given as either `specs/<spec>`
   or the bare `<spec>` (the same two forms `/spec-kickoff` accepts). Validate
   each `<id>` against the task-id grammar `^[0-9]+(\.[0-9]+)?$`, and extract
   the `<spec>` segment from whichever form was given and validate it against
   the anchored identifier pattern `^[a-z0-9][a-z0-9-]*$` (≤64 chars,
   REQ-A1.8) **before** it appears in any path or command; a failing token is
   never interpolated. No task ID: halt and ask which task to execute.
2. **Resolve the spec path**, trying in order: (a) an explicit spec-path
   argument (`specs/<spec>` or bare `<spec>`, validated in step 1);
   (b) the branch name parsed against `planwright/<spec>/task-<ids>` (D-36),
   giving `specs/<spec>/`; (c) the current checkout when it holds exactly one
   `specs/*/` bundle with `Status: Active`; (d) ask, listing the available
   bundles (underscore-prefixed accumulators are not bundles). Verify the
   directory holds `requirements.md`, `design.md`, `tasks.md`, and
   `test-spec.md`.
3. **Resolve the doctrine docs** (above). Halt on a core-doc resolution
   failure; note a degraded `decision-domains`.
4. **Verify the spec is Active** (REQ-J1.2, D-33). Read the `**Status:**`
   line in `requirements.md`. Not Active: halt. Suggest `/spec-kickoff` when
   the status is Draft; say plainly that a terminal (Retired/Superseded) or
   Done spec has nothing to execute. There is no bypass flag.
5. **Run the validator.** `scripts/spec-validate.sh specs/<spec>`. On this
   dispatch path a missing or non-executable validator fails closed and halts
   (REQ-K1.7, the K1.7 amendment: the fail-closed arm preserves the
   block-execution guarantee). An Active bundle's findings are errors:
   surface them and halt; an erroring spec is not executed.
6. **Verify the kickoff brief.** `specs/<spec>/kickoff-brief.md` must exist
   and carry a final sign-off record with an anchor line (D-36). Absent, or
   partial (sections signed but no sign-off record, or a record without its
   anchor line — the anchor-written-last ordering makes a killed kickoff
   indistinguishable from absent-anchor, by design): halt and prompt
   `/spec-kickoff`.
7. **Run the execution freshness gate** (REQ-F1.9, REQ-F1.10, D-45; the
   `spec-format` anchor rules). This stops execution against spec content that
   changed since the brief was last signed:
   - Read the brief's **most recent anchor entry** and the four spec files
     **from the primary checkout's main view** (not the possibly-ahead
     worktree copy): the gate's frame of reference is main, what
     `/orchestrate` and a merge see.
   - **Parse and validate the entry.** It is execution-valid only if it
     parses, uses a **sanctioned command form** (`scripts/spec-anchor.sh
     <spec-dir>`, or the interim whole-file form the meta-spec still
     sanctions), was written by a **sanctioned writer** (a `/spec-kickoff`
     sign-off for a meaning-class entry, or the marked `Class:
     expression-only` ritual), and — for a meaning-class entry — carries a
     dispositioned `Lens-pass:` reference.
   - **Recompute** the anchor with the exact command the entry records, and
     compare. **Match** → proceed. **Mismatch** (any anchored content changed,
     committed or not) → halt, remedy: a `/spec-kickoff` delta re-walkthrough.
     **No entry / unparseable / non-sanctioned command / non-sanctioned
     writer** → halt, remedy: complete or repair the sign-off record per
     REQ-F1.10. Every halt is to Awaiting input, naming its remedy. There is
     no bypass flag (same class as the non-Active refusal).
8. **Read the brief slice and task block(s).** From the brief: the signed-off
   goal restatement (it anchors every judgment call), the task-graph section,
   and the risk-register entries relevant to the unit. From `tasks.md`: each
   task block's `Deliverables`, `Done when`, `Dependencies`, and `Citations`.
   Confirm every listed dependency sits in `## Completed`; if one does not,
   halt naming the blocking dependency.
9. **Derive the full-CI command** (D-19). Inspect the project and pick the
   most comprehensive guard the repo ships, checking in order: a `mise.toml`
   aggregate task (planwright's own is `mise run check`); a `package.json`
   `ci`/`test` script; a `Makefile` `ci`/`test` target; a `lefthook.yml`
   `pre-commit` stack; a language toolchain's check (`mix ci`,
   `cargo test && cargo clippy -- -D warnings`, pytest+ruff+mypy from
   `pyproject.toml`). Prefer the aggregate over a bare test run. If none can
   be derived, ask. Record the command for the implementation phase.
10. **Update Last activity; write no placement or `Status`.** The dispatch record
    (the task branch + the runtime marker) created at dispatch already makes the
    unit derivable as In progress, so this skill writes **no** `tasks.md` section
    placement here, and **no** `Status` line either. Section placement is the
    `tasks-pr-sync` reconcile's sole job (REQ-B1.1, D-1); a block still sitting in
    `## Forward plan` while its branch is in flight is intentional snapshot lag,
    not corruption (REQ-B1.2). Writing a `Status` here would be the problem: an
    in-progress `Status` on a still-`Forward plan` block reads to the
    structural-corruption guard as a section/status contradiction (REQ-E1.1,
    REQ-E1.2, `scripts/check-ledger.sh`), and the placement is not yours to move.
    The only edit is the block's `- **Last activity:** <today>` annotation, which
    is anchor-excluded (`spec-format` canonical extraction) and is not a `Status`
    line, so it neither trips the gate that just ran nor the corruption guard. The
    reconcile relocates the block on the PR events this skill later triggers, and
    the `Status` annotation is written at PR creation (PR step 3), on the block
    the reconcile has by then placed in `## In progress`. Commit the Last-activity
    update when `commit_on_state_move` is true (read `config/defaults.yml`
    overridden by `<repo>/.claude/planwright.local.yml`, local wins;
    absent/malformed config falls back to the default with a one-line warning).

## Implementation

### Commit convention (REQ-C1.4, D-2)

Every commit this skill authors for the unit — the test-first action commits,
the observation chore commit, any in-flight expression-only amendment commit —
carries a `Planwright-Task: <spec>/<id>` footer trailer. It is the durable,
cross-flow completion anchor the orchestration-state derivation reads (via
git's native trailer mechanism), surviving branch deletion and solo
direct-to-`main` commits. Stamp it through the shared helper rather than
hand-typing the footer, so the trailer is grammar-validated and identical
everywhere:

```sh
printf '%s\n' "$message" \
  | scripts/planwright-commit-trailers.sh <spec>/<id> \
  | git commit -F -
```

For a **bundle**, pass one ref per task (`… <spec>/<id1> <spec>/<id2> …`); the
helper emits one trailer per task. The trailer is footer-only and additive: it
does not touch the subject line and does not introduce any Claude/co-author
attribution, so the no-attribution commit rule is unaffected.

### Test-first development (REQ-E1.1, `validation-rigor`)

Read `test-spec.md` for the unit's cited REQs first: each entry describes the
verification path — what to test, what behavior to check, which edge cases
matter. Then, for every piece of new behavior or bug fix the unit introduces:

1. **Write the test**, grounded in the `test-spec.md` entry and the
   `Done when:` conditions. It must be specific enough to fail for the
   intended reason and pass only when the implementation is correct.
2. **Run it and confirm it fails for the right reason** — the failure message
   corresponds to the behavior being implemented, not a syntax, import, or
   unrelated error. A test that passes immediately, or fails for the wrong
   reason and cannot be revised to isolate the intended behavior, is a stop
   condition.
3. **Implement** to make the test pass, consulting the brief's goal
   restatement and risk register to stay on contract.
4. **Confirm the test passes** — the same test, unchanged. Iterate on the
   implementation, never the test, until it does.

Validate the solution per `validation-rigor`: the targeted test, the wider
project suite (the CI step below), and the altitude check (fix the cause at
the right layer, not the symptom). For a unit that is purely configuration,
documentation, or infrastructure with no testable behavior per `test-spec.md`,
skip the test-first loop and note in the PR body why no test was added.

### Research Rigor (REQ-D1.5, `research-rigor`)

Research fires **before** implementation when a trigger holds — a new
dependency, an unfamiliar domain, a security-touching pattern, a
version-sensitive API, or a "how do mature projects do this" question.
Consult current sources down the hierarchy (official docs for the pinned
version first, then the library's own source and tests, then issues/RFCs),
honor recency over model memory, and run the antipattern check before adopting
a pattern. **Record** the findings, the tradeoffs weighed (performance,
security, system-wide implications), and the sources consulted in the brief's
**risk register**, appended to a named section — never overwriting existing
rows, and never as an anchor entry (execution-skill brief writes are confined
to named sections; the risk register is not the contract surface the gate
hashes). Declare the research depth's scoping per `proportionality`. If
research surfaces a significant risk the brief did not anticipate, that is a
stop condition: record it and hand off for a human decision.

### Write-time security pass (REQ-D1.6, `security-posture`)

When the diff touches a write-time trigger class — untrusted input,
subprocess or shell construction, path handling, authorization, crypto, or
serialization — run a focused security pass on that risk class before opening
the PR, distinct from the general review lens, with Research Rigor consulted
for current guidance. Apply artifact data-hygiene to everything committed
(the brief, risk register, observations log, and PR body): no secrets,
credentials, internal hostnames, or sensitive operational detail. Work in a
hard-disqualifier zone (security-sensitive code, migrations or destructive
ops, CI config, lockfiles, secrets files) follows the `gate-wiring` pause
protocol rather than landing autonomously.

### Decision-domains drift triggers (REQ-G1.8, `decision-domains`)

When implementation is about to cross a catalogued decision domain the brief
did not decide, the drift trigger fires: if the brief or spec already decides
the question, proceed citing the decision; otherwise research per stake, then
recommend (a low-stake, reversible call, with the considerations recorded) or
**escalate** (a load-bearing or hard-disqualifier-adjacent call) as a stop
condition rather than auto-defaulting. A decision in a domain the catalog
does not cover yet writes an **observation** (the catalog grows through the
drain loop). The catalogued domains are the prose seed (`decision-domains`, the
normative full text) unioned with any adopter/team/machine-local additions via
the merged path `scripts/resolve-catalog.sh decision-domains`, so overlay
domains trigger drift too rather than a single-layer read (REQ-D1.1). When
`decision-domains` did not resolve, note the skipped check and lean on
engineering judgment for the same calls.

### Run the full project CI (REQ-E1.2)

Run the command derived in pre-flight step 9. The full suite must pass before
convergence. Capture its output.

### Adaptive CI-failure handling (REQ-E1.2, D-25)

On a CI failure, classify it with `scripts/classify-ci-failure.sh` over the
captured output (it prints `transient` or `logic`; unknown patterns default
to `logic`, since escalating an unclassifiable failure beats burning retries):

- **`transient`** (network/DNS/connection errors, registry pull failures,
  service-unavailable, rate limits, gateway timeouts): retry the CI command up
  to twice, waiting 30 seconds before the first retry and 90 seconds before
  the second. Any retry that goes green proceeds normally; if both retries
  still fail, reclassify as logic and escalate.
- **`logic`** (assertion/expectation mismatches, type/compile/syntax errors,
  lint/format violations, test-runner failures): escalate immediately, no
  retry. Record the failure with the full CI output to `tasks.md` Awaiting
  input and halt (attended: surface and wait). A logic failure is never
  retried.

## Convergence (REQ-E1.4, REQ-D1.3, D-39, D-6)

After CI passes, run the **review sequence** as the convergence step. The
sequence is the `review_sequence` config knob (D-6, REQ-D1.3): an ordered list
of nestable review-skill names, resolved through the four-layer config overlay.
The default `review_sequence` is the single `polish`, so out of the box this is
exactly today's `/polish --nested` convergence; an adopter or repo overlay can
reorder or extend it (for example `[self-review, polish]`).

**Resolve the sequence.** Run `scripts/resolve-review-sequence.sh` (under the
resolved planwright root). It reads `review_sequence` *through* `config-get`
(no layer logic re-implemented, REQ-D1.1), validates each name against the
nestable-review-skill predicate, applies the REQ-E1.4 by-layer malformed
policy, and prints the validated ordered names, one per line. By exit code:

- **0** — the printed names are the review sequence, in order. A stderr warning may
  note that an adopter/machine-local overlay set a malformed value and was
  degraded to the core default; surface that warning but proceed.
- **4** — a repo-tracked (team-shared) overlay set a malformed `review_sequence`
  value, or the repo-tracked config file is structurally malformed: a
  hard-fail. **Stop condition** — record to `tasks.md` Awaiting input and halt;
  do not converge over a broken shared review sequence.
- **5** — broken install (the core default itself is unresolvable). **Stop
  condition** — halt and hand off.

**Run each named skill in order, with `--nested`.** For each name the resolver
printed, invoke `/<name> --nested`. Each review skill runs in-session (REQ-E2.2,
D-13): one session, one context, hooks fire once per actual tool call; it
drains every action disposition per act-then-review and returns its audit
record without pushing or creating a PR (that is this skill's job, which is why
`--nested` is mandatory for every review-sequence skill). After each returns:

- **Normal exit** (converged, or handed off with queued forks): continue to the
  next skill in the sequence; once the whole sequence has run, proceed to PR
  creation, folding each skill's audit record — the four bucket tables, the
  declined log, the pending-sign-off checklist, and any queued
  Needs-human-judgment forks — into the PR body.
- **Safety stop** (wider-suite failure, loop detection, iteration cap): the
  branch may be in a known-broken state. Surface the stop reason and halt; do
  not run later review-sequence skills and do not open a PR over a broken branch.
- **Hard-disqualifier finding** a review-sequence skill surfaced but could not resolve
  autonomously: a stop condition — hand off for human direction.

## In-flight amendments (D-19, REQ-A3.3, REQ-F1.10)

If implementation reveals the spec itself needs an edit, classify it on the
amendment axis:

- **Expression-only** (a typo, an ambiguity, a gap-fill consistent with the
  accepted decisions): fix it in place with a dated `## Changelog` entry,
  riding this task's PR, and write a **marked self-re-anchor entry** to the
  brief's amendment log — `Class: expression-only`, citing the changelog line,
  with the anchor computed by `scripts/spec-anchor.sh specs/<spec>` written
  last. This is the one anchor entry an execution skill may write (the
  sanctioned marked-expression-only ritual; misclassification is auditable and
  one revert from undone).
- **Meaning-class** (contradicts an accepted decision, alters a REQ's meaning,
  or adds a REQ/D-ID): **contract drift** — do not edit the contract from
  execution. Halt, surface the drift with the conflicting reading, and route
  the human to a `/spec-kickoff` delta re-walkthrough. There is no silent
  proceed.

## PR creation (REQ-E1.5, D-21)

1. **Push the branch:** `git push origin <branch>` (with `-u` on first push).
   New commits only — never force-push, amend, squash, or rebase (REQ-J1.4).
   On push or `gh` auth failure, degrade gracefully (REQ-K1.6, REQ-K1.7): the
   local work is intact and committed; record an Awaiting-input note in
   `tasks.md` naming the pending push/PR step and the failure, surface it, and
   stop. Never retry into an opaque failure.
2. **Open or update a draft PR.** If a PR already exists for the branch,
   update its body in place; otherwise `gh pr create --draft` with an explicit
   `--title` and `--body` (headless `gh` prompts or fails without them). The
   title is conventional and passes the project's PR-title lint
   (`scripts/check-commit-msgs.sh`, enforced on PR titles in CI):
   `feat(<scope>): <task title>` or the fitting type. The body carries:
   - the **kickoff brief path** (`specs/<spec>/kickoff-brief.md`);
   - the **task IDs** this PR implements;
   - the **REQs satisfied**, from the task `Citations:`;
   - the **test additions** and what they verify;
   - **Polish's audit record**: the pending-sign-off checklist (the human
     approves each item by leaving its commit, rejects with the named revert,
     at PR review), the four tables, the declined log, and the queued forks;
   - **implementation notes**: key decisions, especially any extending beyond
     the brief's assumptions.

   The PR is always a draft. Never mark it ready and never merge.
3. **Annotate the unit.** Update the task block's annotations to
   `- **Status:** PR #<N> draft` and `- **Last activity:** <today>`. Section
   moves on `gh pr create`/`merge` are the `tasks-pr-sync` hook's job; these
   annotations are anchor-excluded.

**Hand off.** Report: the unit and spec, the freshness-gate result, the tests
written and CI outcome, Polish's convergence summary, the verified anchor, the
push/PR outcome (or the degradation note), and the items the human decides at
PR review — the pending-sign-off checklist and any queued forks. Apply
artifact data-hygiene to everything surfaced.

## Stop conditions (mandatory human handoff)

Halt and hand back when any fires. Record the unit to `tasks.md` Awaiting
input with the reason (the pause protocol's dispatched arm); in an attended
session, present it and wait.

| Condition | Trigger |
| --- | --- |
| Spec not Active | Pre-flight step 4 found a non-Active status. |
| Missing/erroring validator | Pre-flight step 5: validator absent on the dispatch path, or Active errors. |
| No / partial kickoff brief | Pre-flight step 6 found no brief or a brief without its anchor line. |
| Freshness-gate halt | Pre-flight step 7: anchor mismatch, or an absent / unparseable / non-sanctioned / wrong-writer entry. |
| Dependency not completed | Pre-flight step 8 found an incomplete dependency. |
| Test cannot fail for the right reason | Test-first step 2: the test passes immediately or fails for an unrelated reason and cannot be isolated. |
| CI logic failure | A logic-classified CI failure, or transient retries exhausted then reclassified. |
| Research reveals an uncovered risk | Research surfaced a significant risk the brief did not anticipate. |
| Contract drift | Implementation needs a meaning-class spec change. Route to `/spec-kickoff`. |
| Ambiguity in task definition | `Done when:` or `Deliverables:` admit multiple valid interpretations. |
| Hard-disqualifier finding in Polish | Polish surfaced a disqualifier-zone finding it could not resolve. |
| `gh` not authenticated / push rejected | PR step cannot reach GitHub; local work is complete. |

## Invariants

These hold at every step:

- **Never** act on a spec whose status is not Active (D-33), and **never**
  bypass the execution freshness gate (REQ-F1.9). No bypass flag exists for
  either.
- **Never** create a non-draft PR, mark a PR ready for review, or merge
  (D-21, REQ-J1.1). The draft→ready flip and the merge are the human's.
- **Never** create a worktree (D-37, D-44) — this skill runs inside one it did
  not make.
- **Never** invoke a `review_sequence` skill (`/polish` by default)
  without `--nested`: this skill owns push and PR creation (D-39, REQ-E1.4,
  REQ-D1.3).
- **Never** skip the test-first loop for a behavior-introducing unit when
  `test-spec.md` describes a verification path (REQ-E1.1).
- **Never** retry a logic CI failure; transient retries cap at two; unknown
  classifications default to logic (REQ-E1.2).
- **Never** silently proceed past a meaning-class contract drift; surface it
  and route to `/spec-kickoff` (REQ-A3.3).
- **Never** write a meaning-class anchor entry: an execution skill is not the
  sanctioned meaning-class writer (REQ-F1.10). The only anchor entry this
  skill writes is the marked `Class: expression-only` self-re-anchor.
- **Never** force-push, amend, squash, or rebase; new commits only (REQ-J1.4).

## Observations

`/execute-task` only runs on an Active planwright spec, so `specs/` and the
observations log necessarily exist. When something outside the unit's scope
surfaces during implementation or convergence — complexity growth, an
outdated pattern, a newly available dependency feature, an uncatalogued
decision domain — append one line to `specs/_observations/opportunities.md`,
format `- <YYYY-MM-DD> [<repo>] <observation>`, and commit the append within
the iteration that produced it (its action commit, or its own chore commit)
so the tree returns to clean. Do not act on observations during the unit; they
are seed material for `/spec-draft`, the log's canonical reader (REQ-E2.1,
REQ-H1.6).

## Maintenance

After the run completes (or halts), compare these instructions against the
resolved doctrine docs (REQ-B3.2, D-42) — especially `spec-format` (the
anchor command forms, sign-off record format, and amendment ritual),
`gate-wiring`, `research-rigor`, `security-posture`, and `decision-domains`.
If a concept this skill names has changed meaning, gained or lost a step, or
moved between docs, append a drift observation to
`specs/_observations/opportunities.md` (format above, prefixed
`skill-drift(execute-task):`), commit it as its own chore commit, and tell the
user what drifted. Do not edit this skill or the doctrine docs to resolve the
drift; the observation log's reader owns folding drift into spec amendments.
