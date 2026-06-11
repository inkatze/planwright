# planwright Bootstrap — Test Spec

**Status:** Active
**Last reviewed:** 2026-06-11
**Format-version:** 1

Every REQ is pinned to at least one verification path. Types: **test** (automated),
**manual** (human-exercised), **design-level** (the artifact's existence + coverage is
the verification), **Gherkin** (state/trigger/outcome). planwright is mostly skills +
doctrine + a portable-shell validator, so coverage is a deliberate mix. Verification
ownership: [test] entries run in planwright's own CI; every entry whose tag includes
[manual] or [Gherkin] (mixed tags count) is exercised by Task 18's
manual-verification sweep (each exercised, or the gap named).

## REQ-A — Spec format, lifecycle & evolution

### REQ-A1.1 — Versioned four-file meta-spec exists [design-level]

The meta-spec (Task 4) documents the four-file format; this bundle conforms to it.

### REQ-A1.2 — REQ-ID convention [test]

Validator fixture: a bundle with prose-only REQs warns/errors; a bundle with
`REQ-<Group><N>.<M>` IDs + citations passes.

### REQ-A1.3 — D-ID convention [test + manual]

Validator/manual: each D-ID carries Decision, Alternatives considered, Chosen because;
a D-ID missing a field is flagged.

### REQ-A1.4 — tasks.md fields [test]

Validator fixture: a task missing Done when / Dependencies / Citations is flagged
(warn on Draft, error on Active).

### REQ-A1.5 — test-spec coverage [test]

Validator: a REQ with no test-spec entry is flagged.

### REQ-A1.6 — Status declared, five statuses [test]

Validator: missing `Status:` warns and defaults to Draft; all five statuses
accepted; Superseded without `Superseded-by:` is rejected; an unknown status is
flagged.

### REQ-A1.7 — Format-version selects rules [test]

Validator fixture: a version-mismatched bundle is handled by the rules for its declared
version.

### REQ-A1.8 — Spec-identifier charset [test + manual]

Validator fixture: a spec directory whose identifier fails the anchored
`^[a-z0-9][a-z0-9-]*$` or the 64-char bound is flagged; mixed fixtures (a hostile
identifier *containing* a valid run, e.g. `good-name/../escape`) confirm full-string
matching, not substring; an underscore-prefixed accumulator directory
(`_observations/`) is skipped as a bundle but its name is still screened
(`^_[a-z0-9][a-z0-9-]*$`; a hostile `_foo;rm` is flagged); a hostile identifier
sourced from an accumulator seed (e.g. an `_observations` entry proposing
`../escape`) is re-validated and refused at consumption before interpolation. Hook fixtures (see REQ-K1.2) confirm hostile identifiers
never reach a path or command. Manual: a skill invoked with a hostile identifier
(`../escape`, `foo;rm`) — `/spec-draft` creating `specs/<spec>/` and its branch,
`/orchestrate` forming worktree/lock paths or a printed launch command — refuses
before any path or command is formed.

### REQ-A2.1 — Status-aware enforcement [test]

Draft fixture with a gap → warning, exit 0; the same gap with Status Active → error, exit 1.

### REQ-A2.2 — Validator scope [test]

Fixtures for each of: missing file, malformed task, REQ↔test-spec gap.

### REQ-A3.1 — Lifecycle transitions [Gherkin]

Given a Draft spec, When `/spec-kickoff` signs off, Then Status is Active. Given the last
Forward-plan / In-progress / Awaiting-input task moves to Completed, When bookkeeping
runs, Then Status is Done even with open Deferred gates, And those gates continue to be
swept. Given a Done spec is extended, Then Status flips to Draft, And scoped kickoff
returns it to Active. Given a Retired or Superseded spec, Then no skill-driven
transition out of the terminal state is accepted (validator fixture).

### REQ-A3.2 — Stable, never-reused IDs [test]

Validator rejects a reused/renumbered ID; a supersede (new ID + `Superseded-by` on the
old) passes.

### REQ-A3.3 — Amendment ritual [manual]

An expression-only edit needs only a dated Changelog entry (no re-approval; plus
the marked self-re-anchor per REQ-F1.10); a decision-contradicting edit triggers
supersede + scoped kickoff re-sign-off — post-merge; a pre-merge correction on
the spec's own PR amends in place with changelog + recorded re-sign-off.

### REQ-A3.4 — Fold-vs-new rule [design-level]

The rule (four spin-new triggers, partition by functional separation) is documented;
`/spec-draft` exercises it (REQ-B1.3).

## REQ-B — Authoring & comprehension

### REQ-B1.1 — Draft-only `/spec-draft`, auto-commit [manual]

Run `/spec-draft`; confirm Status=Draft, the bundle is committed (and not committed
when `commit_on_draft` is off), and no push or Active flip occurs.

### REQ-B1.2 — Seed sources cited [manual]

A seeded run cites the seed in `requirements.md` Sources.

### REQ-B1.3 — Fold-detection always-scan [Gherkin]

Given an overlapping existing spec, When `/spec-draft <different-name>` runs, Then it
surfaces an extend recommendation for the human to decide (no auto-fold).

### REQ-B1.4 / REQ-H1.6 — Mine and archive `_observations` [manual]

Opportunities entries appear as seeds in a draft; consumed entries are archived/trimmed.

### REQ-B2.1 (superseded by REQ-B2.4) / REQ-B2.4 — Kickoff walkthrough → Active + spec PR [manual]

`/spec-kickoff` produces a signed brief, flips the spec Active, commits the brief +
flip (skipped when `commit_on_kickoff` is off), pushes the spec branch, and opens a
draft PR; with no remote or failed `gh` auth, local work completes and a degradation
note is recorded instead. It never marks the PR ready or merges. Worktree handling:
launching from main, the spec worktree, or an unrelated worktree each resolves
gracefully (reuse / locate-and-print / recreate from branch).

### REQ-B2.2 — Two-brief model + brief structure [manual]

Cold-read: the kickoff brief reads as the working contract (not a summary) and follows the
specified structure; the handover is optional.

### REQ-B2.3 — Inconsistency halt [manual]

A seeded contradictory spec causes `/spec-kickoff` to halt without a brief.

### REQ-B3.1 — Interaction-style rules [design-level]

Rules documented; authoring skills show the progress indicator + selectors.

### REQ-B3.2 — Self-healing maintenance footer [manual]

Each shipped skill ends with the maintenance check; a seeded doctrine change causes a
skill run to write a drift observation to the observations log.

## REQ-C — Finding categorization & autonomy gate

### REQ-C1.1 / REQ-C1.2 — Four buckets + predicates [design-level]

The categorization doctrine defines all four buckets and the Agent-resolvable
predicate (the four conditions enumerated in REQ-C1.2).

### REQ-C1.3 — Act-then-review [Gherkin]

Given a Needs-sign-off finding, When the loop processes it, Then the fix is applied on
the branch And the finding appears in the draft PR's pending-sign-off checklist. Given
an Agent-resolvable finding, Then the audit row carries the failing→passing test, CI
result, and brief-alignment citation.

### REQ-C1.4 — Hard pauses only [Gherkin]

Given a finding in a disqualifier zone (security / migration / CI config / lockfile /
secrets), Then the loop pauses for the human. Given an irreducible
Needs-human-judgment fork, Then the loop hard-pauses mid-loop (distinct from
REQ-C1.7's loop-end queuing). Given any other validated finding, Then the loop does
not interrupt.

### REQ-C1.5 — Four-table output [manual]

`/polish` emits all four bucket tables including empty ones, as audit (no mid-loop
decision prompts).

### REQ-C1.6 — Declined-with-rationale [manual]

A validated-but-declined finding is closed with recorded reasoning in the audit table
and is visible for re-raise at PR review.

### REQ-C1.7 — Resolution ladder [Gherkin]

Given a fork answerable from the kickoff brief, Then it never reaches the human. Given
an irreducible product fork, Then it queues at loop end with bespoke options.

## REQ-D — Rigor doctrine

### REQ-D1.1 — Discovery Rigor doc [design-level]

Doc covers the lens checklist, lens-coverage table, tool-grounded-first, fan-out, and
self-critique pass.

### REQ-D1.2 — Validation Rigor doc [design-level]

Doc covers the three validation passes and the solution-validation angles.

### REQ-D1.3 — Refactor Instinct doc [design-level]

Doc covers the implementation-mode (low bar) / review-mode (high bar) split, tool-grounded.

### REQ-D1.4 — Framework-owned, runtime-resolved [test]

A skill resolves a rule doc via the plugin-relative path in both delivery modes.

### REQ-D1.5 — Research Rigor doc [design-level + manual]

Doc covers triggers, source hierarchy, recency discipline, antipattern check, and
risk-register recording; an `/execute-task` run hitting a trigger produces a
risk-register entry with citations.

### REQ-D1.6 — Security posture doc [design-level + test]

Doc covers write-time triggers, artifact data-hygiene, and framework-script security;
`gitleaks` in CI covers committed artifacts; a seeded secret in a brief fixture is
caught. Script security is exercised by `shellcheck` in CI (Task 2) and the
hostile-input fixtures (REQ-K1.2 hook, REQ-H1.3 gate parser).

### REQ-D1.7 — Proportionality [design-level]

The rigor docs state the stake/reversibility scaling rule and the declared-scoping
requirement.

### REQ-D2.1 — Composability principle [design-level]

The principle is documented.

### REQ-D2.2 / REQ-I1.4 — Adopter supplies own rigor [manual]

An adopter overrides project tooling/rigor without editing planwright's core docs.

## REQ-E — Task execution & review

### REQ-E1.1 — Test-first [Gherkin]

Given a task, When `/execute-task` runs, Then a failing test precedes the implementation and
the task ends green.

### REQ-E1.2 — Adaptive CI retry [test]

A transient failure is classified and retried with backoff; a logic failure escalates
immediately.

### REQ-E1.3 — Risk register [manual]

Research/perf/security tradeoffs are recorded in the kickoff brief's risk register.

### REQ-E1.4 / REQ-E1.5 — Polish convergence + draft PR [manual]

`/execute-task` runs `/polish`, then opens a draft PR referencing brief, task IDs, REQs,
test additions, and the pending-sign-off checklist (see REQ-C1.3).

### REQ-E2.1 — self-review/polish + observation writing [manual]

`/polish` drains all action dispositions per act-then-review and emits the declined
log; both skills append to the observations log.

### REQ-E2.2 — In-session composition [design-level]

Nested skill invocation fires hooks once; documented and observed.

## REQ-F — Orchestration

### REQ-F1.1 — Stateless, one unit per step [test]

One `/orchestrate` step advances exactly one ready unit and updates `tasks.md`; a
killed tower loses nothing (the reconcile sweep rebuilds from disk). Orphan fixtures
(per the tightened REQ-F1.1 predicate): a dead subagent/tmux worker past the grace
threshold, with PR state reconciled first, moves to Awaiting input with an orphan
note. Negative fixtures: a just-dispatched worker inside the grace window, a
print-backend unit awaiting human launch, and a worker dispatched by another tower
are NOT orphaned; a task whose PR turns out merged moves to Completed, not
Awaiting input.

### REQ-F1.2 — Ready-task selection, critical-path-first [test]

Selection logic picks a task whose deps are all Completed and which is not In progress /
Awaiting input; among ready units, the head of the effort-weighted longest dependent
chain is selected first (fixture: T3-like long chain beats T1-like leaf), FIFO on ties.

### REQ-F1.3 — Advisory lock [test]

Lock acquired during the state move, released before `/execute-task`; stale lock broken at the
threshold; acquire-failure is a clean no-op.

### REQ-F1.4 — Refuse non-Active, no auto-chain [test]

`/orchestrate` on a Draft spec halts and prompts kickoff; it does not chain into `/spec-kickoff`.

### REQ-F1.5 — Halt → Awaiting input [Gherkin]

Given ambiguity / test failure / contract drift, When orchestrating, Then halt to Awaiting input.

### REQ-F1.6 — Draft PRs only, no auto-merge [test]

The created PR is a draft; no merge path exists in the skill.

### REQ-F1.7 — Cohesion-first bundling [manual]

Consecutive cohesive tasks bundle into one PR; non-cohesive ready tasks ship separately.

### REQ-F1.8 — Dispatch backends + unattended mode [manual + test]

Manual: each backend (subagents, tmux, print, in-session) dispatches a worker that
completes a unit; worker questions reach the tower (subagents) or are detected via
capture-pane (tmux). Test: unattended mode records would-be prompts as Awaiting-input
entries; `max_parallel_units` is respected; `tasks.md` state moves are auto-committed
(and not committed when the toggle is off). Manual: a subagent worker completes a
routine unit without permission prompts under the shipped worker-settings profile; the
clean-worktree reuse confirm appears in attended mode only; tmux worker prompts are
detected via capture-pane and never answered via send-keys.

### REQ-F1.9 — Execution freshness gate [test]

Fixtures: a bundle matching the brief's most recent content anchor → the dispatch
step proceeds. One spec file modified after the anchor (committed or uncommitted)
→ `/orchestrate`'s dispatch step and `/execute-task` both halt to Awaiting input
naming the `/spec-kickoff` delta re-walkthrough as the remedy. An orchestrate
state move (section membership, dispatch metadata) does NOT change the anchor;
an edited Done-when does. No anchor entry / an unparseable entry / a
non-sanctioned computation command → both halt (fail closed) naming the
REQ-F1.10 repair remedy. A fresh, valid anchor written by a sign-off or
re-walkthrough → dispatch proceeds again. First-activation sign-off and an
in-place amendment each write a recomputable anchor. A lagging worktree whose
self-consistent brief/spec pair diverges from main's halts. Anchor
recomputation per the entry's recorded command is deterministic.

### REQ-F1.10 — Sign-off record format & anchor validity [test]

Parse fixtures: a meaning-class entry with Class + Anchor + Lens-pass parses as
execution-valid; a meaning-class entry with no Lens-pass reference is invalid
(both skills halt as on mismatch); an expression-only entry explicitly marked
`Class: expression-only` citing a changelog line is valid with no lens pass; an
entry using a non-sanctioned command form is invalid; an anchor-bearing edit
from an execution skill's write path (not the kickoff flow or the marked
expression-only ritual) is rejected/flagged. Manual: a killed `/spec-kickoff`
session that wrote the sign-off record but not the anchor line leaves a record
the gate treats as absent-anchor (fail closed) — the anchor-written-last
ordering is observable.

### REQ-F2.1 — `/resume` read-only + surface uncommitted [manual]

`/resume` loads context, surfaces `git status`, and asks before proceeding; no
auto-stash/commit/clean.

## REQ-G — Engineering doctrine & builder

### REQ-G1.1 — Engineering doctrine doc [design-level]

The doctrine encodes the decision process including the ecosystem-research move.

### REQ-G1.2 — Builder core catalog [manual]

The builder detects the stack and recommends/applies the core guards.

### REQ-G1.3 — No flattening / escalation [Gherkin]

Given an auth-class decision, When the builder runs, Then it escalates to design /
Needs-human-judgment and routes a gate (no auto-default).

### REQ-G1.4 — Lifecycle hooks [manual]

Standards surface in `/spec-draft`'s design phase; guards apply in `/execute-task`;
a kickoff over a spec touching an undecided catalogued domain produces a
risk-register flag (`/spec-kickoff` gap check).

### REQ-G1.5 — Extensible catalog [design-level]

The catalog is data-driven; breadth dimensions are addable without core edits.

### REQ-G1.6 — Priority-balancing nuance [design-level]

The doctrine advises and weighs tradeoffs rather than rigidly enforcing.

### REQ-G1.7 — Dogfooding, CI-enforced [test]

planwright's own CI runs the prescribed guards; the builder run against planwright reproduces
that guard set (Task 16 dogfood loop).

### REQ-G1.8 — Decision-domains catalog [design-level + Gherkin]

The catalog exists with ~10 seed entries (trigger + considerations + disposition each).
Given an implementation about to cross a catalogued domain the brief did not decide,
Then the drift trigger fires (halt or research per stake). Given an uncatalogued domain
decision, Then an observation is written.

## REQ-H — Accumulator taxonomy & drain policy

### REQ-H1.1 — Accumulator taxonomy [design-level]

Each surface is classified with its drain ritual.

### REQ-H1.2 — No write-only deferral [design-level + manual]

Every deferral surface has a named reader and a re-surfacing gate/ritual.

### REQ-H1.3 — `GATE(when:)` convention [test]

Gate parser: a condition gate vs. a date gate (surface-only) are handled per the rule;
an `and`-of-atoms gate evaluates; a free-text gate surfaces without evaluation.
Hostile fixtures: a gate containing shell metacharacters / `$(…)` is never evaluated
(closed grammar, pattern-match parse only); a gate containing control characters is
echoed stripped; a malformed gate surfaces as a drain-report-level error (the pass
completes), never silently skipped.

### REQ-H1.4 — Bookkeeping drain, no auto-drop; `/drain` [test]

A satisfied gate re-surfaces; nothing is auto-resolved or auto-dropped; `/drain` and
`--bookkeeping` share the evaluator; the pass reports the observations log's unmined
count and oldest-entry age.

### REQ-H1.5 — Confidence levels [manual]

Deferred decisions carry a confidence level; low-confidence items resurface first.

### REQ-H1.6 — cross-reference [manual, via the joint entry under REQ-B]

Verified jointly with REQ-B1.4 (mine and archive `_observations`) above.

## REQ-I — Packaging, delivery & onboarding

### REQ-I1.1 — Plugin manifest + plugin-relative resolution [manual]

Install as a plugin; skills resolve their rule docs.

### REQ-I1.2 — `~/.claude/` writer fallback, no banned deps [manual]

The writer installs on a clean machine with no fish/mise/tmux/Ansible dependency.

### REQ-I1.3 — Autopilot model docs [manual]

Cold-read: an adopter understands the human-reserved controls from the docs.

### REQ-I1.4 — cross-reference [manual, via the joint entry under REQ-D]

Verified jointly with REQ-D2.2 (adopter supplies own rigor) above; I1.4 is a
cross-reference to D2.2.

### REQ-I1.5 — MIT license + contribution model [design-level]

`LICENSE` is MIT; a contribution doc exists.

## REQ-J — Invariants & release gating

### REQ-J1.1 — Never auto-merge [test]

No skill path merges a PR.

### REQ-J1.2 — Never act on non-Active [test]

`/execute-task` and `/orchestrate` refuse a non-Active spec; no bypass flag exists.

### REQ-J1.3 — Never auto-chain [test]

`/orchestrate` does not invoke `/spec-kickoff`.

### REQ-J1.4 — No force-push/amend/squash/rebase; draft PRs [test]

Skills create new commits only and open draft PRs; no history-rewriting path exists.

### REQ-J1.5 — Private start, public gate [design-level]

The release checklist enforces the three gate conditions (incl. Task 18's
multi-contributor work-repo run + manual sweep, the migrated docs, and the meta-spec)
and every release-blocking gated Deferred entry (the `reference/` history purge,
human-reserved per REQ-J1.4; the checklist verifies it happened, it does not perform it).

## REQ-K — Operational integration

### REQ-K1.1 — Config model [manual]

Thresholds and commit/dispatch toggles live in a tracked default + gitignored local
override; per-repo entries are written only on human confirmation.

### REQ-K1.2 — tasks-pr-sync hook [test]

`gh pr create` / `gh pr merge` on a convention-named branch moves the matching task block;
non-matching input is a clean no-op. Positive fixture: `task-3.5` and `task-3-4`
branches (valid per the D-36 id grammar) move their blocks. Hostile fixtures: a
branch whose `<spec>` segment fails REQ-A1.8 or whose `<id>` segment fails the
task-id grammar (`task-3..5`, `task-.5`, `..`, `/`, metacharacters) is a clean no-op
and never reaches a filesystem path. Containment fixture (unit-level, charset
validation stubbed out): a resolved `tasks.md` path outside
`<repo-toplevel>/specs/` is rejected.

### REQ-K1.3 — tool-discovery hook [test]

Session start emits a discovered-tools summary consumed by Discovery Rigor and the builder.

### REQ-K1.4 — Branch + worktree conventions [test]

Branch names parse per the convention; worktrees land under `<repo>/.claude/worktrees/` for
`claude --worktree` discovery.

### REQ-K1.5 — Portable runtime [test]

Validator/hooks/scripts run under bash 3.2 + BSD tooling with no fish/mise/tmux/Ansible
dependency (verified in CI).

### REQ-K1.6 — GitHub via gh, graceful degradation [test]

PR ops use `gh`; on `gh` auth failure, local work proceeds and an Awaiting-input entry is
recorded.

### REQ-K1.7 — Graceful degradation on missing prereqs [test]

Not-a-repo / no git remote / missing `gh` / missing validator each surface a clear
message rather than failing opaquely. On dispatch steps (`/orchestrate` step
execution, `/execute-task`), a missing validator halts (fail closed per the K1.7
amendment); authoring, read-only, and non-dispatching paths (`--bookkeeping`,
`/drain`, `/resume`) degrade with the message.

### REQ-K1.8 — CI-enforced options reference [test]

A seeded config option with no options-reference entry fails CI; a documented option
passes.
