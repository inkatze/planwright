# Human gates — Test Spec

**Status:** Draft
**Last reviewed:** 2026-09-22
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` where automation is honest (the knob resolver, the
guards and their adversarial suites, the trailer parser, the helpers over a
stubbed `gh`, and the repository's existing index, link, options, purge, and
instruction-budget checks, all run by `mise run check` and the repository
CI); `[Gherkin]` for the policy scenarios the helpers must reproduce as
fixtures; `[manual]` for the one live probe (the reviewer-request side
effect) and the tower's operator-requested force-push, run and recorded by
the executing worker; `[design-level]` where a rule's presence in the named
doc is the verification.

## REQ-A — The human-gate list

### REQ-A1.1 — The gate test [design-level]

`doctrine/human-gates.md` states the test in the two-arm form and applies it
to every act it lists; the kickoff lens pass confirms each listed act carries
the arm it meets or the reason it meets neither (Task 1).

### REQ-A1.2 — The list under the test [design-level + test]

The doc lists merge authorization and sign-off as gates and the flip, the
owned push, the base merge, and the never-pushed rewrite as policies; the
guard suites of Tasks 6, 7, 9, 10 pin that no value admits an agent merge
outside a class and that every policy has a resolving knob (Task 1, Task 4).

### REQ-A1.3 — One source [test]

`check:purged-identifiers` refuses the retired phrasings in a fixture, and
the doctrine-index check pins the doc's row; a grep fixture over `skills/`
and `docs/` finds no restated list without a citation (Task 12).

### REQ-A1.4 — Supersession by pointer [test]

`scripts/spec-validate.sh specs/bootstrap` accepts the `Superseded-by`
pointer with its changelog entry; a diff test shows D-26's body unchanged
(Task 1).

### REQ-A1.5 — Every rule labelled with its kind [design-level]

The doc's rule table carries a kind column with no empty cell; the kickoff
lens pass checks it (Task 1).

## REQ-B — Sign-off at the approval act

### REQ-B1.1 — The approval act [design-level + Gherkin]

Given a trailered commit on a PR, when the PR is flipped ready, then no
checklist item changes state; when the PR merges, then the item is approved.
Stated in gate-wiring and reproduced as a fixture over the checklist
generator (Task 1, Task 2).

### REQ-B1.2 — The trailer [test]

`tests/test-planwright-commit-trailers.sh` (or the sibling's test) shows the
trailer stamped, the subject unchanged, and the id preserved across a
base-merge that reorders the range (Task 2).

### REQ-B1.3 — Regeneration from trailers [test]

A fixture branch with one trailered commit and its revert regenerates to
zero items; the same fixture under the legacy subject grep yields two, which
the test asserts as the failing baseline (Task 2).

### REQ-B1.4 — Lint retirement and broadening [test]

`tests/test-check-commit-msgs.sh`: `--marker subject` is unknown; `--marker
title` rejects the bracket and a bare trailer line; the deferral bullet
carries a dated gate (Task 2).

### REQ-B1.5 — Approval semantics at the point of use [test]

A fixture run of the section generator emits the approval statement and the
revert rule inside the section and no checkbox reading as a control
(Task 3).

### REQ-B1.6 — Green commits over split commits [test + design-level]

A fixture with two interleaved findings and one shared test produces one
trailered commit and a checklist disclosing it with two revert recipes; the
rule is stated in gate-wiring (Task 2, Task 3).

### REQ-B1.7 — Attended apply-then-review [test]

A prompt-eval fixture of each gate-wired skill's attended path applies a
Needs-sign-off finding without a preceding question (Task 3).

### REQ-B1.8 — Trailered SHAs at handoff [test]

The handoff fixture of each skill prints the SHAs and the trailer-aware log
command (Task 3).

### REQ-B1.9 — Migration is one line [design-level]

gate-wiring carries the mapping line; a diff test shows no branch swept and
no history rewritten by the change's own PR (Task 1).

## REQ-C — Ready-flip policy

### REQ-C1.1 — The flip knob [test]

Resolver tests for `human`, `agent`, the shipped default, and each
malformed arm with its fail-closed value (Task 4).

### REQ-C1.2 — Preconditions [test + Gherkin]

Given a stubbed `gh`, for each predicate a fixture where it alone fails
leaves the PR draft; a fixture where all hold flips; the helper contains no
model call (Task 7).

### REQ-C1.3 — The PR record [test]

The record comment precedes the flip call in the stubbed call log; a failing
record write yields no flip call (Task 7).

### REQ-C1.4 — Failure parks the flip [test]

A failing fixture adds a `## Awaiting input` bullet naming the predicate;
the bullet is removed on the next passing run (Task 7).

### REQ-C1.5 — Worker-only [test]

The policy-guard suite denies the flip spelling under the tower and
orchestrator profiles at every value and defers it under the worker profile
at `agent` (Task 6, Task 7).

### REQ-C1.6 — The spec-PR knob [design-level]

The options reference row for `mark_spec_pr_ready_on_kickoff` names it as
the spec-PR instance and its default is unchanged in `config/defaults.yml`
(Task 7).

### REQ-C1.7 — No silent un-draft [manual + test]

The live probe on a scratch PR is recorded in the risk register; the stubbed
re-draft test shows a request followed by a state check and, on un-draft,
the corrective (Task 8).

### REQ-C1.8 — The narrow undo [test]

The guard suite admits the corrective helper and denies every other
`--undo` spelling in the fixtures (Task 6, Task 8).

## REQ-D — Merge policy

### REQ-D1.1 — The merge knob [test]

Resolver tests for the three values, the shipped default, and fail-closed
to `human` on every malformed or unresolvable arm (Task 4).

### REQ-D1.2 — The on-approval act [design-level + test]

The docs state the act; the guard suite denies every merge spelling to
agent sessions under `on-approval` (Task 9).

### REQ-D1.3 — Mechanical class predicates [test + Gherkin]

For each predicate a fixture where it alone fails falls through to
`on-approval`; a PR with a sign-off trailer is refused under every bound;
the evaluator contains no model call (Task 9).

### REQ-D1.4 — Record, strategy, helper [test]

The record comment precedes the merge call; the merge call uses the
sanctioned strategy; a failing record write yields no merge call (Task 9).

### REQ-D1.5 — No allowance outside the class [test]

The guard suite denies every merge spelling under `human` and
`on-approval`, and under `policy-class` admits only the helper for an
admitted PR (Task 6, Task 9).

### REQ-D1.6 — The floor restated [test]

`check:purged-identifiers` refuses the retired unconditional phrasing; a
grep fixture over `doctrine/` and `docs/` finds the policy citation at each
floor statement (Task 1, Task 12).

### REQ-D1.7 — Identity detected, never required [test + design-level]

A fixture where the login equals the author takes the auto-merge act; one
where it differs also accepts an approving review; no value refuses to run
on equality; the docs carry the recommendation (Task 9).

## REQ-E — Worker base merge

### REQ-E1.1 — The act, every spelling [test]

The policy-guard suite defers a base merge on the unit branch and denies a
merge from main, a spec branch, or another unit's branch, for `git merge`,
`git pull`, and the helper (Task 6, Task 10).

### REQ-E1.2 — The conflict knob [test + Gherkin]

Given a fixture conflict: under `halt` the tree is clean and the parking
bullet names the paths; under `resolve` a resolution commit exists and the
PR body carries the flag (Task 10).

### REQ-E1.3 — Tower and orchestrator stay denied [test]

The suite denies every merge spelling under both profiles at every value;
the fast-forward helper stays the only admitted local-main mutation
(Task 6, Task 10).

## REQ-F — History rewriting

### REQ-F1.1 — Never-pushed rewrite [test]

The guard admits an amend of a commit no remote-tracking ref contains and
denies one a remote ref contains, on the unit branch; off-branch attempts
deny (Task 6).

### REQ-F1.2 — Operator-requested force-push [manual + test]

The tower-queue tests refuse a standing decision covering a force-push and
refuse main, protected, and spec targets; the confirmation passes
`check-confirmation.sh`; one recorded live run shows the warning, the yes,
and the push (Task 11).

### REQ-F1.3 — The repair path named [test]

A handoff fixture where the range lint fails names the tower path
(Task 11).

### REQ-F1.4 — Purge stays human [test]

The purge helper prints the command and checklist and exits without
executing in a fixture (Task 11).

### REQ-F1.5 — Never main, protected, or spec [test]

The spelling fixtures include every rewrite and push form against those
refs and every copy refuses them (Task 5, Task 6).

## REQ-G — Guards and profiles

### REQ-G1.1 — One spelling list, every copy [test]

The cross-copy test drives the fixture file through every guard copy and
both profiles and fails on any admitted line; the `git pull` line fails
before the profile edit (Task 5).

### REQ-G1.2 — Enforcement follows the policy [test]

The policy-guard suite covers every value and tier for each policy-permittable
spelling; an unresolvable knob denies (Task 6).

### REQ-G1.3 — The floor stays in the profiles [test]

The wiring tests assert the floor entries are present in both profiles and
that no policy-permittable entry remains for a tier a value can grant it to
(Task 6).

### REQ-G1.4 — Deterministic, bounded, fail-closed [test]

The suite pins no model invocation, a wall-clock bound on the knob read,
and a deny on a stubbed read failure (Task 6).

### REQ-G1.5 — Wired and pinned [test]

`tests/test-worker-settings-hook-wiring.sh` and the tower sibling cover the
new hook and the corrective helpers (Task 6).

## REQ-H — Prose surfaces

### REQ-H1.1 — Skills split by kind, within budget [test]

`check-instructions.sh` reports no surface over budget after the sweep; a
grep fixture finds each skill's invariant section citing the doctrine doc
(Task 12).

### REQ-H1.2 — Docs agree, retired phrasings purged [test]

`check:purged-identifiers` refuses a reintroduced phrase in a fixture;
`check-doc-links.sh` and the options check pass (Task 12).

### REQ-H1.3 — Every knob documented [test]

`scripts/check-options-reference.sh` passes with the new rows (Task 4).
