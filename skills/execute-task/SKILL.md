---
name: execute-task
description: >
  Implement one task (or a cohesion bundle) from a signed-off spec (Ready or Active):
  recompute the execution freshness gate, write the verifying test first,
  implement to green, run the project's full CI with adaptive retry, converge
  via the configured review_sequence (default /polish --nested), then open a
  draft PR referencing the brief, task IDs, REQs, tests, and the pending-sign-off
  checklist. The execution workhorse of the planwright pipeline. Assumes the
  worktree already exists; never creates worktrees, never merges, never marks a
  PR ready.
argument-hint: "<task-id> [<task-id> …] [<spec-path>]"
---

# /execute-task

The execution layer of the planwright pipeline (REQ-E1.1–REQ-E1.5): take one
ready unit — a single task or a cohesion bundle — from a Ready or Active spec
with a signed-off kickoff brief, and carry it from a failing test to a draft PR
without further human keystrokes. `/orchestrate` dispatches this skill into a
prepared worktree; a human may also invoke it directly inside one. It operates
from the kickoff brief, the durable contract (D-3), not by re-reading the spec.
It assumes the worktree already exists and the spec is signed off;
it **never** creates worktrees (D-37, D-44), **never** merges, and **never**
marks a PR ready — sign-off and merge are the human's two reserved controls.

## Doctrine

This skill is procedure, not doctrine. Resolve and read the manifest's rule docs
via the rule-doc resolution convention (`scripts/resolve-rule-doc.sh <doc-name>`
under the resolved planwright root, or the documented
`PLANWRIGHT_ROOT`/`CLAUDE_PLUGIN_ROOT` chain); their definitions govern wherever
this skill names a concept. Per `doctrine/instruction-hygiene.md`, `run-start`
entries load before work begins, `point-of-use` entries at the named step or
branch.

If a manifest doc does not resolve — at run start or at its point of use —
halt naming the missing doc and the chain consulted (REQ-K1.7).
`decision-domains` degrades gracefully
instead: absent, note it in one line, skip the drift check, and rely on the
engineering judgment the catalog would otherwise structure.

Doctrine: run-start spec-format (status lifecycle, anchors, sign-off/amendment — freshness gate)
Doctrine: run-start proportionality (rigor scales with stake; scoping declared)
Doctrine: point-of-use research-rigor (the Research Rigor step)
Doctrine: point-of-use security-posture (the write-time security pass)
Doctrine: point-of-use validation-rigor (the test-first solution-validation angles)
Doctrine: point-of-use finding-categorization (the convergence audit buckets)
Doctrine: point-of-use gate-wiring (pause protocol, pending-sign-off checklist, PR-body assembly)
Doctrine: point-of-use decision-domains (the decision-domain drift check)

## Pre-flight

Run once per invocation, in order. Any halt records the unit to the spec's
`tasks.md` `## Awaiting input` section with the reason and ends the step (the
`gate-wiring` pause protocol's dispatched arm); in an attended session, present
it and wait instead.

1. **Parse `$ARGUMENTS`.** Extract one or more task IDs (`5`, `3.5`, or `5 6`
   for a bundle) and an optional spec path, given as either `specs/<spec>` or
   the bare `<spec>` (the two forms `/spec-kickoff` accepts). Validate each
   `<id>` against `^[0-9]+(\.[0-9]+)?$`, and the extracted `<spec>` against the
   anchored identifier pattern `^[a-z0-9][a-z0-9-]*$` (≤64 chars, REQ-A1.8)
   **before** it appears in any path or command; a failing token is never
   interpolated. No task ID: halt and ask which task to execute.
2. **Resolve the spec path**, in order: (a) an explicit spec-path argument
   (`specs/<spec>` or bare `<spec>`, validated in step 1); (b) the branch name
   parsed against `planwright/<spec>/task-<ids>` (D-36); (c) the current
   checkout when it holds exactly one `specs/*/` bundle whose `Status:` is
   `Ready` or `Active`; (d) ask, listing the available bundles
   (underscore-prefixed accumulators are not bundles). Verify the directory
   holds `requirements.md`, `design.md`, `tasks.md`, and `test-spec.md`.
3. **Resolve the doctrine docs** (above). Halt on a run-start-doc resolution
   failure; note a degraded `decision-domains`.
4. **Verify the spec is Ready or Active** (REQ-C1.1, superseding the bootstrap
   non-Active refusal REQ-J1.2, D-33; kickoff-lifecycle D-2, D-3). Read the
   `**Status:**` line in `requirements.md`. `Ready` (signed off, no work
   started) and `Active` (work in flight) are both executable; refuse
   Draft, Done, Retired, and Superseded. The spec file **stays `Ready`** during
   execution: Ready↔Active is **derived, not stored** (D-2), written only by
   `orchestration-concurrency`'s single level-triggered reconcile writer (D-3),
   so a dispatched task normally runs against a `Ready` spec — demanding a stored
   `Active` here is the bug this gate must not reintroduce. On **Draft**, halt
   and suggest `/spec-kickoff`; a terminal (Retired/Superseded) or Done spec has
   nothing to execute. A `Ready` spec is executed on the same terms as Active:
   the freshness gate (step 7) still applies (REQ-C1.3); the two gates compose.
   There is no bypass flag.
5. **Run the validator.** `scripts/spec-validate.sh specs/<spec>`. On this
   dispatch path a missing or non-executable validator fails closed and halts
   (REQ-K1.7). A Ready or Active bundle's findings are errors: surface them and
   halt; an erroring spec is not executed.
6. **Verify the kickoff brief.** `specs/<spec>/kickoff-brief.md` must exist and
   carry a final sign-off record with an anchor line (D-36). Absent, or partial
   (sections signed but no sign-off record, or a record without its anchor line
   — anchor-written-last makes a killed kickoff indistinguishable from
   absent-anchor, by design): halt and prompt `/spec-kickoff`.
7. **Run the execution freshness gate** (REQ-F1.9, REQ-F1.10, D-45; the
   `spec-format` anchor rules). This stops execution against spec content that
   changed since the brief was last signed:
   - Read the brief's **most recent anchor entry** and the four spec files
     **from the primary checkout's main view** (not the possibly-ahead worktree
     copy): the gate's frame of reference is main, what `/orchestrate` and a
     merge see.
   - **Parse and validate the entry.** It is execution-valid only if it parses,
     uses a **sanctioned command form** (`scripts/spec-anchor.sh <spec-dir>`, or
     the interim whole-file form the meta-spec still sanctions), was written by a
     **sanctioned writer** (a `/spec-kickoff` sign-off, or the marked `Class:
     expression-only` ritual), and — for a meaning-class entry — carries a
     dispositioned `Lens-pass:` reference.
   - **Recompute** the anchor with the exact command the entry records, and
     compare. **Match** → proceed. **Mismatch** (any anchored content changed,
     committed or not) → halt, remedy: a `/spec-kickoff` delta re-walkthrough.
     **No entry / unparseable / non-sanctioned command / non-sanctioned writer**
     → halt, remedy: complete or repair the sign-off record per REQ-F1.10. Every
     halt is to Awaiting input, naming its remedy. There is no bypass flag.
8. **Read the brief slice and task block(s).** From the brief: the signed-off
   goal restatement (it anchors every judgment call), the task-graph section,
   and the risk-register entries relevant to the unit. From `tasks.md`: each
   block's `Deliverables`, `Done when`, `Dependencies`, and `Citations`. Confirm
   every listed dependency sits in `## Completed`; if one does not, halt naming
   the blocking dependency.
9. **Derive the full-CI command** (D-19). Pick the most comprehensive guard the
   repo ships, checking in order: a `mise.toml` aggregate task (planwright's own
   is `mise run check`); a `package.json` `ci`/`test` script; a `Makefile`
   `ci`/`test` target; a `lefthook.yml` `pre-commit` stack; a language
   toolchain's check (`mix ci`, `cargo test && cargo clippy -- -D warnings`,
   pytest+ruff+mypy).
   Prefer the aggregate over a bare test run. If none can be derived, ask. Record
   the command for implementation.
10. **Resolve `dispatch_isolation`** (D-5, REQ-C1.3). Run
    `scripts/resolve-dispatch-isolation.sh` (under the resolved planwright root)
    to read the knob through the four-layer overlay; it prints `per-step` (the
    assigned-decision default) or `per-unit` and applies the REQ-E1.4 by-layer
    malformed policy. A hard-fail (exit 4 — a malformed repo-tracked value or a
    structurally malformed team-shared config; exit 5 — a broken install whose
    core default is unresolvable) is a **stop condition**: record to `tasks.md`
    Awaiting input and halt; do not sequence under a broken shared value. A
    warn+degrade (an adopter/machine-local malformed value degraded to the core
    default, exit 0) proceeds. Record the resolved mode; it governs how the
    Implementation and Convergence phases host this unit's steps (see *Step
    isolation*).
11. **Update Last activity; write no placement or `Status`.** The dispatch
    record (the task branch + runtime marker) already makes the unit derivable
    as In progress, so this skill writes **no** `tasks.md` section placement and
    **no** `Status` line. Section placement is the `tasks-pr-sync` reconcile's
    sole job (REQ-B1.1, D-1); a block still sitting in `## Forward plan` while
    its branch is in flight is intentional snapshot lag, not corruption
    (REQ-B1.2). A `Status` here would trip the structural-corruption guard: an
    in-progress `Status` on a `Forward plan` block is a section/status
    contradiction (REQ-E1.1, REQ-E1.2, `scripts/check-ledger.sh`), and the
    placement is not yours to move. The only edit is the block's
    `- **Last activity:** <today>` annotation, which is anchor-excluded
    (`spec-format` canonical extraction) and is not a `Status` line, so it trips
    neither guard; the reconcile later relocates the block on the PR events this
    skill triggers. Commit the Last-activity update when `commit_on_state_move`
    is true (read `config/defaults.yml` overridden by
    `<repo>/.claude/planwright.local.yml`, local wins; absent/malformed config
    falls back to the default with a one-line warning).

## Implementation

### Step isolation (`dispatch_isolation`, REQ-C1.3, REQ-C1.4, D-5)

The mode resolved in pre-flight step 10 governs how this unit's **steps** — the
implementation phase (test-first loop, research, security pass, CI), then each
`review_sequence` skill — are **hosted**. It changes only the hosting, never the
work or the order.

- **`per-unit`** (strictly preserved): the whole unit runs in **one session** —
  implement, run CI, invoke each `review_sequence` skill inline with `--nested`,
  then push and open the PR. No fresh sessions; context carries across steps.
- **`per-step`** (the assigned-decision default): each step runs in its **own
  fresh `/resume`-seeded session**, so context stays bounded and each review's
  perspective is uncontaminated by prior steps. The sequence is unchanged, but
  steps share no context: each is seeded from durable state alone (brief,
  `tasks.md` snapshot, git log, open PR) and commits its own work with the
  `Planwright-Task:` trailer. Realization is the backend's job (D-2): a
  session-grade backend spawns a session per step; the terminal rung (D-3)
  approximates it with a context clear + `/resume` reseed between steps; a
  backend that can do neither degrades to `per-unit` (degrade capability, never
  safety) — note the degrade.

**State-safety holds in both modes (REQ-C1.4):** every `tasks.md` placement move
goes **only** through the sibling reconcile under the per-spec lock, no per-step
session writes dispatch/progress state or opens a PR — push and PR creation
remain this skill's single terminal step (see Invariants).

### Commit convention (REQ-C1.4, D-2)

Every commit this skill authors for the unit — the test-first action commits,
the observation chore commit, any in-flight expression-only amendment commit —
carries a `Planwright-Task: <spec>/<id>` footer trailer: the durable cross-flow
completion anchor the orchestration-state derivation reads by scanning the whole
commit message (so a squash/rebase merge that relocates it mid-body is still
recognized, not git's footer-only `%(trailers)`), surviving branch deletion and
solo direct-to-`main` commits. Stamp it through the shared helper rather than
hand-typing the footer, so it is grammar-validated and identical everywhere:

```sh
printf '%s\n' "$message" \
  | scripts/planwright-commit-trailers.sh <spec>/<id> \
  | git commit -F -
```

For a **bundle**, pass one ref per task (`… <spec>/<id1> <spec>/<id2> …`); the
helper emits one trailer per task. The trailer is footer-only and additive — no
subject-line change, no Claude/co-author attribution — so the no-attribution rule
is unaffected.

### Test-first development (REQ-E1.1, `validation-rigor`)

Read `test-spec.md` for the unit's cited REQs first: each entry describes the
verification path — what to test, what to check, which edge cases matter. Then,
for every piece of new behavior or bug fix the unit introduces:

1. **Write the test**, grounded in the `test-spec.md` entry and the `Done when:`
   conditions. It must be specific enough to fail for the intended reason and
   pass only when the implementation is correct.
2. **Run it and confirm it fails for the right reason** — the failure message
   corresponds to the behavior being implemented, not a syntax, import, or
   unrelated error. A test that passes immediately, or fails for the wrong reason
   and cannot be isolated, is a stop condition.
3. **Implement** to make the test pass, consulting the brief's goal restatement
   and risk register to stay on contract.
4. **Confirm the test passes** — the same test, unchanged. Iterate on the
   implementation, never the test, until it does.

Validate the solution per `validation-rigor`: the targeted test, the wider
project suite (the CI step below), and the altitude check (fix the cause at the
right layer, not the symptom). For a unit that is purely configuration,
documentation, or infrastructure with no testable behavior per `test-spec.md`,
skip the loop and note in the PR body why no test was added.

### Research Rigor (REQ-D1.5, `research-rigor`)

Research fires **before** implementation when a trigger holds — a new
dependency, an unfamiliar domain, a security-touching pattern, a
version-sensitive API, or a "how do mature projects do this" question. Consult
current sources down the hierarchy (official docs for the pinned version first,
then the library's own source and tests, then issues/RFCs), honor recency over
model memory, and run the antipattern check before adopting a pattern.
**Record** the findings, tradeoffs weighed, and sources consulted in the brief's
**risk register**, appended to a named section — never overwriting existing
rows, and never as an anchor entry (the risk register is not the contract
surface the gate hashes). Declare the research depth's scoping per
`proportionality`. If research surfaces a significant risk the brief did not
anticipate, that is a stop condition: record it and hand off.

### Write-time security pass (REQ-D1.6, `security-posture`)

When the diff touches a write-time trigger class — untrusted input, subprocess
or shell construction, path handling, authorization, crypto, or serialization —
run a focused security pass on that risk class before opening the PR, distinct
from the general review lens, with Research Rigor consulted for current guidance.
Apply artifact data-hygiene to everything committed (brief, risk register,
observations log, PR body): no secrets, credentials, internal hostnames, or
sensitive operational detail. Work in a hard-disqualifier zone
(security-sensitive code, migrations or destructive ops, CI config, lockfiles,
secrets files) follows the `gate-wiring` pause protocol rather than landing
autonomously.

### Decision-domains drift triggers (REQ-G1.8, `decision-domains`)

When implementation is about to cross a catalogued decision domain the brief did
not decide, the drift trigger fires: if the brief or spec already decides the
question, proceed citing the decision; otherwise research per stake, then
recommend (a low-stake, reversible call, considerations recorded) or
**escalate** (a load-bearing or hard-disqualifier-adjacent call) as a stop
condition rather than auto-defaulting. A decision in a domain the catalog does
not cover yet writes an **observation** (the catalog grows through the drain
loop). The catalogued domains are the prose seed unioned with any
adopter/team/machine-local additions via `scripts/resolve-catalog.sh
decision-domains` (REQ-D1.1), so overlay domains trigger drift too. When
`decision-domains` did not resolve, note the skipped check and lean on
engineering judgment.

### Run the full project CI (REQ-E1.2)

Run the command derived in pre-flight step 9. The full suite must pass before
convergence; capture its output.

### Adaptive CI-failure handling (REQ-E1.2, D-25)

On a CI failure, classify it with `scripts/classify-ci-failure.sh` over the
captured output (it prints `transient` or `logic`; unknown patterns default to
`logic`, since escalating an unclassifiable failure beats burning retries):

- **`transient`** (network/DNS/connection errors, registry pull failures,
  service-unavailable, rate limits, gateway timeouts): retry the CI command up
  to twice, waiting 30s before the first retry and 90s before the second. A
  retry that goes green proceeds; if both still fail, reclassify as logic and
  escalate.
- **`logic`** (assertion/expectation mismatches, type/compile/syntax errors,
  lint/format violations, test-runner failures): escalate immediately, no retry.
  Record the failure with the full CI output to `tasks.md` Awaiting input and
  halt (attended: surface and wait). A logic failure is never retried.

## Convergence (REQ-E1.4, REQ-D1.3, D-39, D-6)

After CI passes, run the **review sequence** as the convergence step. The
sequence is the `review_sequence` config knob (D-6, REQ-D1.3): an ordered list
of nestable review-skill names, resolved through the four-layer config overlay.
The default is the single `polish`, so out of the box this is exactly today's
`/polish --nested` convergence; an overlay can reorder or extend it.

**Resolve the sequence.** Run `scripts/resolve-review-sequence.sh` (under the
resolved planwright root). It reads `review_sequence` *through* `config-get` (no
layer logic re-implemented, REQ-D1.1), validates each name against the
nestable-review-skill predicate, applies the REQ-E1.4 by-layer malformed policy,
and prints the validated ordered names. By exit code:

- **0** — the printed names are the review sequence, in order. A stderr warning
  may note an adopter/machine-local overlay was degraded to the core default;
  surface it but proceed.
- **4** — a repo-tracked (team-shared) overlay set a malformed value, or the
  repo-tracked config is structurally malformed: a hard-fail. **Stop
  condition** — record to `tasks.md` Awaiting input and halt.
- **5** — broken install (the core default itself is unresolvable). **Stop
  condition** — halt and hand off.

**Run each named skill in order, with `--nested`.** Every review skill runs
`--nested` in both isolation modes — it drains every action disposition per
act-then-review and returns its audit record without pushing or creating a PR
(this skill's job, which is why `--nested` is mandatory). The
`dispatch_isolation` mode (the *Step isolation* subsection) sets only where each
`--nested` call is **hosted** — `per-unit` in-session composition (REQ-E2.2,
D-13) or a fresh `/resume`-seeded `per-step` session — never the `--nested`
contract, which never pushes or opens a PR.

After each returns:

- **Normal exit** (converged, or handed off with queued forks): continue to the
  next skill; once the whole sequence has run, proceed to PR creation, folding
  each skill's audit record — the four bucket tables, the declined log, the
  pending-sign-off checklist, and any queued Needs-human-judgment forks — into
  the PR body.
- **Safety stop** (wider-suite failure, loop detection, iteration cap): the
  branch may be known-broken. Surface the stop reason and halt; do not run later
  review-sequence skills and do not open a PR over a broken branch.
- **Hard-disqualifier finding** a review-sequence skill surfaced but could not
  resolve autonomously: a stop condition — hand off for human direction.

## In-flight amendments (D-19, REQ-A3.3, REQ-F1.10)

If implementation reveals the spec itself needs an edit, classify it on the
amendment axis (the `spec-format` amendment ritual):

- **Expression-only** (a typo, an ambiguity, a gap-fill consistent with the
  accepted decisions): fix it in place with a dated `## Changelog` entry, riding
  this task's PR, and write a **marked self-re-anchor entry** to the brief's
  amendment log — `Class: expression-only`, citing the changelog line, with the
  anchor computed by `scripts/spec-anchor.sh specs/<spec>` written last. This is
  the one anchor entry an execution skill may write (misclassification is
  auditable and one revert from undone).
- **Meaning-class** (contradicts an accepted decision, alters a REQ's meaning,
  or adds a REQ/D-ID): **contract drift** — do not edit the contract from
  execution. Halt, surface the drift with the conflicting reading, and route the
  human to a `/spec-kickoff` delta re-walkthrough. There is no silent proceed.

## PR creation (REQ-E1.5, D-21)

1. **Push the branch:** `git push origin <branch>` (with `-u` on first push).
   New commits only — never force-push, amend, squash, or rebase (REQ-J1.4). On
   push or `gh` auth failure, degrade gracefully (REQ-K1.6, REQ-K1.7): the local
   work is intact and committed; record an Awaiting-input note in `tasks.md`
   naming the pending push/PR step and the failure, surface it, and stop. Never
   retry into an opaque failure.
2. **Open or update a draft PR.** If a PR already exists for the branch, update
   its body in place; otherwise `gh pr create --draft` with an explicit
   `--title` and `--body` (headless `gh` prompts or fails without them). The
   title is conventional and passes the project's PR-title lint
   (`scripts/check-commit-msgs.sh`): `feat(<scope>): <task title>` or the fitting
   type. Assemble the body per the **PR-body assembly** section of the
   `gate-wiring` doctrine (summary first, the audit record collapsed in
   `<details>`, prose never hard-wrapped, structure preserved on updates) — the
   single normative home for the layout (D-2). This skill supplies the summary
   inputs: the kickoff brief path (`specs/<spec>/kickoff-brief.md`), the task IDs
   implemented, the REQs satisfied (from the task `Citations:`), the test
   additions and what they verify, and implementation notes (key decisions,
   especially any extending beyond the brief). The collapsed audit record is the
   review sequence's output — the four tables, the declined log, the
   pending-sign-off checklist (the human approves each item by leaving its
   commit, rejects with the named revert, at PR review), and any queued forks.

   The PR is always a draft. Never mark it ready and never merge.
3. **Annotate the unit.** Update only the task block's `- **Last activity:**
   <today>` annotation; write **no** `Status` line. Section placement is the
   `tasks-pr-sync` reconcile's sole job (REQ-B1.1, D-1); the reconcile preserves
   annotations untouched and does not author the `Status` text. Writing a
   `PR #<N> draft` Status here would race the reconcile: the hook is fail-soft on
   a busy lock (a clean no-op), so the block can still sit in `## Forward plan`,
   an in-progress `Status` there being exactly the section/status contradiction
   `scripts/check-ledger.sh` flags (REQ-E1.1, REQ-E1.2). The Last-activity
   annotation is anchor-excluded and is not a `Status` line, so it trips neither
   guard.

**Hand off.** Report: the unit and spec, the freshness-gate result, the tests
written and CI outcome, the convergence summary, the verified anchor, the
push/PR outcome (or degradation note), and the items the human decides at PR
review — the pending-sign-off checklist and any queued forks. Apply artifact
data-hygiene to everything surfaced.

## Stop conditions (mandatory human handoff)

Halt and hand back when any fires. Record the unit to `tasks.md` Awaiting input
with the reason (the pause protocol's dispatched arm); in an attended session,
present it and wait.

| Condition | Trigger |
| --- | --- |
| Spec not Ready or Active | Pre-flight step 4 found a status outside {Ready, Active} (Draft, Done, Retired, Superseded). Suggest `/spec-kickoff` for Draft. |
| Missing/erroring validator | Pre-flight step 5: validator absent on the dispatch path, or a Ready/Active bundle's errors. |
| No / partial kickoff brief | Pre-flight step 6 found no brief or a brief without its anchor line. |
| Freshness-gate halt | Pre-flight step 7: anchor mismatch, or an absent / unparseable / non-sanctioned / wrong-writer entry. |
| Dependency not completed | Pre-flight step 8 found an incomplete dependency. |
| Malformed `dispatch_isolation` | Pre-flight step 10: `resolve-dispatch-isolation.sh` hard-failed (exit 4/5) — a malformed repo-tracked value, a structurally malformed team-shared config, or a broken install. |
| Test cannot fail for the right reason | Test-first step 2: the test passes immediately or fails for an unrelated reason and cannot be isolated. |
| CI logic failure | A logic-classified CI failure, or transient retries exhausted then reclassified. |
| Research reveals an uncovered risk | Research surfaced a significant risk the brief did not anticipate. |
| Contract drift | Implementation needs a meaning-class spec change. Route to `/spec-kickoff`. |
| Ambiguity in task definition | `Done when:` or `Deliverables:` admit multiple valid interpretations. |
| Hard-disqualifier finding in convergence | A review-sequence skill surfaced a disqualifier-zone finding it could not resolve. |
| `gh` not authenticated / push rejected | PR step cannot reach GitHub; local work is complete. |

## Invariants

These hold at every step:

- **Never** act on a spec whose status is neither Ready nor Active (REQ-C1.1,
  superseding the bootstrap non-Active refusal REQ-J1.2, D-33; kickoff-lifecycle
  D-2, D-3), and **never** bypass the execution freshness gate (REQ-F1.9), which
  composes with the Ready-or-Active gate and applies to a Ready spec exactly as
  to an Active one (REQ-C1.3). No bypass flag exists for either.
- **Never** create a non-draft PR, mark a PR ready for review, or merge (D-21,
  REQ-J1.1). The draft→ready flip and the merge are the human's.
- **Never** create a worktree (D-37, D-44) — this skill runs inside one it did
  not make.
- **Never** invoke a `review_sequence` skill (`/polish` by default) without
  `--nested`: this skill owns push and PR creation (D-39, REQ-E1.4, REQ-D1.3).
- **Never** let `per-step` isolation weaken the state-safety contract
  (REQ-C1.4): a fresh `/resume`-seeded step session rebuilds from durable state
  only, drives every `tasks.md` placement move through the sibling reconcile
  under the per-spec lock, and opens no PR of its own — push and PR creation stay
  this skill's single terminal step regardless of the isolation mode. Degrade
  `per-step` to `per-unit` when the substrate cannot host a fresh session, never
  a guard (degrade capability, never safety).
- **Never** skip the test-first loop for a behavior-introducing unit when
  `test-spec.md` describes a verification path (REQ-E1.1).
- **Never** retry a logic CI failure; transient retries cap at two; unknown
  classifications default to logic (REQ-E1.2).
- **Never** silently proceed past a meaning-class contract drift; surface it and
  route to `/spec-kickoff` (REQ-A3.3).
- **Never** write a meaning-class anchor entry: an execution skill is not the
  sanctioned meaning-class writer (REQ-F1.10). The only anchor entry this skill
  writes is the marked `Class: expression-only` self-re-anchor.
- **Never** force-push, amend, squash, or rebase; new commits only (REQ-J1.4).

## Observations

When something outside the unit's scope surfaces during implementation or
convergence — complexity growth, an outdated pattern, a newly available
dependency feature, an uncatalogued decision domain — record it as its own
fragment through the shared helper: `scripts/obs-record.sh --slug <topic>
--scope <repo> --text '<observation>'` (resolved under the planwright root; it
writes one file under the host repo's `specs/_observations/entries/`). Commit
the fragment within the iteration that produced it (its action or chore commit)
so the tree returns to clean; on a non-zero helper exit, surface the failure
rather than silently dropping the observation. Do not act on observations during
the unit; they are seed material for `/spec-draft` (REQ-E2.1, REQ-H1.6).

## Maintenance

After the run completes (or halts), compare these instructions against the
resolved doctrine docs (REQ-B3.2, D-42) — especially `spec-format` (anchor
command forms, sign-off record format, amendment ritual), `gate-wiring`,
`research-rigor`, `security-posture`, and `decision-domains`. If a concept this
skill names has changed meaning, gained or lost a step, or moved between docs,
record a drift observation through the shared helper (`scripts/obs-record.sh
--slug skill-drift --scope <repo> --text 'skill-drift(execute-task): <what>'` —
keeping the `skill-drift(...)` prefix), commit it as its own chore commit, and
tell the user. Do not edit this skill or the doctrine docs to resolve the drift;
the accumulator's canonical reader (`/spec-draft`) owns folding drift into spec
amendments.
