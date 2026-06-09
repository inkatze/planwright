# planwright Bootstrap — Test Spec

**Status:** Draft
**Last reviewed:** 2026-06-09
**Format-version:** 1

Every REQ is pinned to at least one verification path. Types: **test** (automated),
**manual** (human-exercised), **design-level** (the artifact's existence + coverage is
the verification), **Gherkin** (state/trigger/outcome). planwright is mostly skills +
doctrine + a portable-shell validator, so coverage is a deliberate mix.

## REQ-A — Spec format, lifecycle & evolution

### REQ-A1.1 — Versioned four-file meta-spec exists [design-level]

The meta-spec (Task 4) documents the four-file format; this bundle conforms to it.

### REQ-A1.2 — REQ-ID convention [test]

Validator fixture: a bundle with prose-only REQs warns/errors; a bundle with
`REQ-<Group><N>.<M>` IDs + citations passes.

### REQ-A1.3 — D-ID convention [test]

Validator/manual: each D-ID carries Decision, Alternatives considered, Chosen because;
a D-ID missing a field is flagged.

### REQ-A1.4 — tasks.md fields [test]

Validator fixture: a task missing Done when / Dependencies / Citations is flagged
(warn on Draft, error on Active).

### REQ-A1.5 — test-spec coverage [test]

Validator: a REQ with no test-spec entry is flagged.

### REQ-A1.6 — Status declared [test]

Validator: missing `Status:` warns and defaults to Draft.

### REQ-A1.7 — Format-version selects rules [test]

Validator fixture: a version-mismatched bundle is handled by the rules for its declared
version.

### REQ-A2.1 — Status-aware enforcement [test]

Draft fixture with a gap → warning, exit 0; the same gap with Status Active → error, exit 1.

### REQ-A2.2 — Validator scope [test]

Fixtures for each of: missing file, malformed task, REQ↔test-spec gap.

### REQ-A3.1 — Lifecycle transitions [Gherkin]

Given a Draft spec, When `/spec-kickoff` signs off, Then Status is Active. Given the last
task moves to Completed, When bookkeeping runs, Then Status is Done.

### REQ-A3.2 — Stable, never-reused IDs [test]

Validator rejects a reused/renumbered ID; a supersede (new ID + `Superseded-by` on the
old) passes.

### REQ-A3.3 — Amendment ritual [manual]

An expression-only edit needs only a dated Changelog entry (no re-approval); a
decision-contradicting edit triggers supersede + scoped kickoff re-sign-off.

### REQ-A3.4 — Fold-vs-new rule [design-level]

The rule (four spin-new triggers, partition by functional separation) is documented;
`/spec-draft` exercises it (REQ-B1.3).

## REQ-B — Authoring & comprehension

### REQ-B1.1 — Draft-only `/spec-draft` [manual]

Run `/spec-draft`; confirm Status=Draft and no commit/push/Active flip.

### REQ-B1.2 — Seed sources cited [manual]

A seeded run cites the seed in `requirements.md` Sources.

### REQ-B1.3 — Fold-detection always-scan [Gherkin]

Given an overlapping existing spec, When `/spec-draft <different-name>` runs, Then it
surfaces an extend recommendation for the human to decide (no auto-fold).

### REQ-B1.4 / REQ-H1.6 — Mine and archive `_observations` [manual]

Opportunities entries appear as seeds in a draft; consumed entries are archived/trimmed.

### REQ-B2.1 — Kickoff walkthrough → Active [manual]

`/spec-kickoff` produces a signed brief and flips the spec Active.

### REQ-B2.2 — Two-brief model + brief structure [manual]

Cold-read: the kickoff brief reads as the working contract (not a summary) and follows the
specified structure; the handover is optional.

### REQ-B2.3 — Inconsistency halt [manual]

A seeded contradictory spec causes `/spec-kickoff` to halt without a brief.

### REQ-B3.1 — Interaction-style rules [design-level]

Rules documented; authoring skills show the progress indicator + selectors.

## REQ-C — Finding categorization & autonomy gate

### REQ-C1.1 / REQ-C1.2 — Four buckets + predicates [design-level]

The categorization doctrine defines all four buckets and the Agent-resolvable
five-condition predicate.

### REQ-C1.3 — Solo/multi split [Gherkin]

Given a solo repo, Then Agent-resolvable auto-applies. Given a multi-reviewer repo, Then it
surfaces with test + CI + alignment evidence.

### REQ-C1.4 — Infer + confirm, multi default [test + manual]

Test: PR-history inference; ambiguous signals → multi-reviewer. Manual: never written
without confirmation.

### REQ-C1.5 — Four-table output [manual]

`/polish` emits all four bucket tables including empty ones.

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

`/execute-task` runs `/polish`, then opens a draft PR referencing brief, task IDs, REQs, and
test additions.

### REQ-E2.1 — self-review/polish + observation writing [manual]

`/polish` drains both action buckets; both skills append to the opportunities log.

### REQ-E2.2 — In-session composition [design-level]

Nested skill invocation fires hooks once; documented and observed.

## REQ-F — Orchestration

### REQ-F1.1 — Stateless, one unit/invocation [test]

One `/orchestrate` invocation advances exactly one ready unit, updates `tasks.md`, and exits.

### REQ-F1.2 — Ready-task selection [test]

Selection logic picks a task whose deps are all Completed and which is not In progress /
Awaiting input.

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

Standards surface in `/spec-draft`'s design phase; guards apply in `/execute-task`.

### REQ-G1.5 — Extensible catalog [design-level]

The catalog is data-driven; breadth dimensions are addable without core edits.

### REQ-G1.6 — Priority-balancing nuance [design-level]

The doctrine advises and weighs tradeoffs rather than rigidly enforcing.

### REQ-G1.7 — Dogfooding, CI-enforced [test]

planwright's own CI runs the prescribed guards; the builder run against planwright reproduces
that guard set (Task 16 dogfood loop).

## REQ-H — Accumulator taxonomy & drain policy

### REQ-H1.1 — Accumulator taxonomy [design-level]

Each surface is classified with its drain ritual.

### REQ-H1.2 — No write-only deferral [design-level + manual]

Every deferral surface has a named reader and a re-surfacing gate/ritual.

### REQ-H1.3 — `GATE(when:)` convention [test]

Gate parser: a condition gate vs. a date gate (surface-only) are handled per the rule.

### REQ-H1.4 — Bookkeeping drain, no auto-drop; `/drain` [test]

A satisfied gate re-surfaces; nothing is auto-resolved or auto-dropped; `/drain` and
`--bookkeeping` share the evaluator.

### REQ-H1.5 — Confidence levels [manual]

Deferred decisions carry a confidence level; low-confidence items resurface first.

## REQ-I — Packaging, delivery & onboarding

### REQ-I1.1 — Plugin manifest + plugin-relative resolution [manual]

Install as a plugin; skills resolve their rule docs.

### REQ-I1.2 — `~/.claude/` writer fallback, no banned deps [manual]

The writer installs on a clean machine with no fish/mise/tmux/Ansible dependency.

### REQ-I1.3 — Autopilot model docs [manual]

Cold-read: an adopter understands the human-reserved controls from the docs.

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

The release checklist enforces the three gate conditions (incl. Task 18 + the migrated docs +
the meta-spec).

## REQ-K — Operational integration

### REQ-K1.1 — Config model [manual]

repo-class registry + thresholds live in a tracked default + gitignored local override;
repo-class is written only on confirmation.

### REQ-K1.2 — tasks-pr-sync hook [test]

`gh pr create` / `gh pr merge` on a convention-named branch moves the matching task block;
non-matching input is a clean no-op.

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

Not-a-repo / missing `gh` / missing validator each surface a clear message rather than failing
opaquely.
