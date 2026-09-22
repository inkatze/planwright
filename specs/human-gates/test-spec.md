# Human gates — Test Spec

**Status:** Ready
**Last reviewed:** 2026-09-22
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` where automation is honest (the knob resolver, the
guards and their adversarial suites, the trailer parser, the helpers over a
stubbed `gh`, and the repository's existing index, link, options, purge, and
instruction-budget checks, all run by `mise run check` and the repository
CI); `[Gherkin]` for the policy scenarios the helpers must reproduce as
fixtures; `[manual]` for the two live acts (the reviewer-request probe and
the tower's operator-requested force-push) and the on-demand `eval:skill`
runs behind the skill-prose entries, run and recorded by the executing
worker; `[design-level]` where a rule's presence in the named doc is the
verification. `check:test-time` is part of `mise run check`, so every
`[test]` entry runs inside its per-file and suite budgets.

## REQ-A — The human-gate list

### REQ-A1.1 — The gate test [design-level]

`doctrine/human-gates.md` states the test in the two-arm form and applies it
to every act it lists; the kickoff lens pass confirms each listed act carries
the arm it meets or the reason it meets neither (Task 1).

### REQ-A1.2 — The list under the test [design-level + test]

The doc lists merge authorization and sign-off as gates, the flip, the base
merge, and the never-pushed rewrite as policies each naming its knob, and
the owned push as a composition contract naming its owner; the guard suites
pin that no value admits an agent PR merge outside a class and that each of
the three policies resolves through its knob (Task 1, Task 6, Task 9).

### REQ-A1.3 — One source [test]

The doctrine-index check pins the doc's row; a grep fixture over
`doctrine/`, `skills/`, and `docs/` finds every invariant section anchored
on a citation of `doctrine/human-gates.md` and no retired phrasing outside
the mapping line (Task 12).

### REQ-A1.4 — Supersession by pointer [test]

`scripts/spec-validate.sh specs/bootstrap` accepts the `Superseded-by`
pointers on D-26, REQ-J1.1, and REQ-J1.4 with their changelog entry; a diff
test shows each pointed record's body unchanged (Task 1).

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
trailer stamped, the subject unchanged, and the regenerated checklist's ids
unchanged across a base-merge that reorders the range (Task 2).

### REQ-B1.3 — Regeneration from trailers [test]

A fixture branch with one trailered commit and its revert regenerates to
zero items; the same fixture under the legacy subject grep yields two, which
the test asserts as the failing baseline; a later commit carrying the
rejected trailer for one of two items drops exactly that item; an
unresolvable range yields a named error and no checklist, and id
allocation refuses (Task 2).

### REQ-B1.4 — Lint retirement and broadening [test]

`tests/test-check-commit-msgs.sh`: `--marker subject` is unknown; `--marker
title` rejects the bracket and a bare trailer line; the deferral bullet
carries a dated gate (Task 2).

### REQ-B1.5 — Approval semantics at the point of use [test]

A fixture run of the section generator emits the approval statement and,
per item, its printed rejection recipe (a revert, or the rejected trailer
where a revert is not the recipe) inside the section, and no checkbox
reading as a control (Task 3).

### REQ-B1.6 — Green commits over split commits [test + design-level]

A fixture with two interleaved findings and one shared test produces one
trailered commit and a checklist disclosing it with two rejection recipes
naming the rejected trailer; the rule is stated in gate-wiring (Task 2,
Task 3).

### REQ-B1.7 — Attended apply-then-review [test + manual]

A CI grep fixture asserts each gate-wired skill's attended path carries the
apply-then-review statement in the unattended path's words; the on-demand
`eval:skill` run, recorded by the executing worker, shows the attended path
applying a Needs-sign-off finding without a preceding question (Task 3).

### REQ-B1.8 — Trailered SHAs at handoff [test + manual]

A CI grep fixture asserts each skill's handoff instruction names the
trailered SHAs and the trailer-aware log command; the on-demand
`eval:skill` run, recorded by the executing worker, shows a handoff
printing them (Task 3).

### REQ-B1.9 — Migration is one line [design-level]

gate-wiring carries the mapping line; a diff test shows no branch swept and
no history rewritten by the change's own PR (Task 1).

## REQ-C — Ready-flip policy

### REQ-C1.1 — The flip knob [test]

Resolver tests for `human`, `unit-owner`, and the shipped default; a
malformed repo-tracked value exits non-zero and a stubbed reader denies; a
malformed adopter-layer value resolves to `human` with a warning, never to
`unit-owner` (Task 4).

### REQ-C1.2 — Preconditions [test + Gherkin]

Given a stubbed `gh` and a unit with an open draft PR, when exactly one
predicate fails, then the PR stays draft and the failed predicate is named;
when every predicate holds, then the PR flips. Given no PR or no host CLI,
then the helper skips with a handoff line and writes no park. Given a
transient host failure inside the wait, then the predicate is retried
before it counts as failed. Given a park commit as the only change since
the handoff record's head, then the review-converged predicate holds. The
helper contains no model call (Task 7).

### REQ-C1.3 — The PR record [test]

The record comment precedes the flip call in the stubbed call log; a failing
record write yields no flip call; a flip call that fails after the record
yields a follow-up comment naming the failure and a park (Task 7).

### REQ-C1.4 — Failure parks the flip [test]

A failing fixture adds an `## Awaiting input` segment opening with the
`pending ready-flip:` lead and naming the predicate, in one commit on the
unit branch; a second run with only that segment present is not blocked by
it; a bullet composed of a live `halt` segment and the lead still blocks;
a re-run replaces its own segment rather than appending a second; a park
that cannot be written leaves the tree clean; the next passing run removes
only its own segment and pushes before evaluating the head (Task 7).

### REQ-C1.5 — Worker-only [test]

The policy-guard suite denies the flip spelling under the tower profile at
every value, defers it under the worker profile at `unit-owner` and for the
merge helper's own flip call under `policy-class`, and defers it in a
session with no tier profile; a standalone review-skill fixture never calls
the helper (Task 6, Task 7).

### REQ-C1.6 — The spec-PR knob [design-level]

The options reference row for `mark_spec_pr_ready_on_kickoff` names it as
the spec-PR instance of the same kind and its default is unchanged in
`config/defaults.yml` (Task 7).

### REQ-C1.7 — No silent un-draft [manual + test]

The live probe on a scratch PR is recorded in the risk register; the stubbed
re-draft test shows a request followed by a state check and, on un-draft,
the corrective; a failing state check runs the corrective; a failing
corrective parks the unit naming the PR (Task 8).

### REQ-C1.8 — The narrow undo [test]

The guard suite admits the corrective helper and denies every other
`--undo` spelling in the fixtures (Task 6, Task 8).

## REQ-D — Merge policy

### REQ-D1.1 — The merge knob [test]

Resolver tests for the three values and the shipped default; a malformed
repo-tracked value exits non-zero and a stubbed reader denies; a malformed
adopter-layer or unresolvable value resolves to `human` with a warning
(Task 4).

### REQ-D1.2 — The on-approval act [design-level + test]

The docs state the act; the guard suite denies every PR-merge spelling to
agent sessions under `on-approval` (Task 9).

### REQ-D1.3 — Mechanical class predicates [test + Gherkin]

Given a fixture PR, when exactly one predicate fails, then the PR falls
through to `on-approval` with the reason on the PR. Given a sign-off
trailer in the range, then the PR is refused under every bound. Given a
changed path matching a core-zone glob, then the PR is refused whatever
`merge_class_exclude_paths` says. Given a human park on the fetched base
ref and none in the unit checkout, then the PR is refused. Given only a
`pending ready-flip:` segment, then the predicate holds. The evaluator
contains no model call, and the stubbed log shows one CI rollup wait in
total across evaluation and flip (Task 9).

### REQ-D1.4 — Record, helper, re-pin [test]

The record comment precedes the merge call; a failing record write yields
no merge call; a merge call that fails after the record yields a follow-up
comment and a park; an admitted draft PR gets the flip call before the
merge call under `ready_flip_policy: human`; a head, a base OID, or an
Awaiting-input segment that moves between the predicate pass and the merge
call yields no merge call and a PR comment; the helper denies under the
tower profile and refuses when its own policy re-read fails (Task 9).

### REQ-D1.5 — No allowance outside the class [test]

The guard suite denies every PR-merge spelling under `human` and
`on-approval`, and under `policy-class` admits only `merge-admitted.sh` for
an admitted PR; a worker base-merge line under the same values is judged
by `worker_base_merge`, not by this knob (Task 6, Task 9).

### REQ-D1.6 — The floor restated [test]

The grep screen refuses the retired unconditional phrasing in a fixture; a
grep fixture over `doctrine/` and `docs/` finds the policy citation at each
floor statement (Task 1, Task 12).

### REQ-D1.7 — Identity detected, never required [test + design-level]

The detector, given a login equal to the author, emits the auto-merge act
name; given a differing login, it also emits the approving-review act; no
value refuses to run on equality; the docs carry the recommendation
(Task 9).

### REQ-D1.8 — The merge strategy [test]

With the host stub allowing one method and `merge_class_strategy:
sole-allowed` that method is used; with several allowed under
`sole-allowed`, with an explicit method the stub disallows, and with a
failing host query the PR falls to `on-approval` with the reason on the PR
(Task 4, Task 9).

## REQ-E — Worker base merge

### REQ-E1.1 — The act, every spelling [test]

The policy-guard suite defers a base merge on the unit branch from the PR
base under `allow` and denies it under `deny`, and denies a merge from
main, a spec branch, or another unit's branch, for `git merge`,
`git pull`, and the helper; before a PR exists the base is the branch the
worktree was created from (Task 6, Task 10).

### REQ-E1.2 — The conflict knob [test + Gherkin]

Given a fixture conflict: under `halt` the tree is clean and the parking
bullet names the paths; under `resolve` a resolution commit exists carrying
the sign-off trailer, the PR body carries the flag, and the checklist's
recipe for that item names the `halt` re-run with the rejected trailer, not
a revert. Given a dirty tree, a failed fetch, or a failed merge, then the
unit is parked naming the failure class. Given a failed abort, then no park
is written and the handoff names hand repair (Task 10).

### REQ-E1.3 — Tower and orchestrator stay denied [test]

The suite denies every PR-merge and base-merge spelling under the tower
profile at every value; the fast-forward helper stays the only admitted
local-main mutation (Task 6, Task 10).

## REQ-F — History rewriting

### REQ-F1.1 — Never-pushed rewrite [test]

The guard admits an amend of a commit no remote-tracking ref contains on
the unit branch under `allow` and denies it under `deny`; it denies one a
remote ref contains, one whose upstream refresh fails, and one on a branch
with no upstream; off-branch attempts deny, including an amend of an
unpushed commit on a `planwright/*/spec` branch (Task 4, Task 6).

### REQ-F1.2 — Operator-requested force-push [manual + test]

The tower-queue tests refuse a standing decision covering a force-push and
refuse main, protected, and spec targets; the confirmation passes
`check-confirmation.sh`; one recorded live run shows the warning, the yes,
and the push (Task 11).

### REQ-F1.3 — The repair path named [test + manual]

A CI grep fixture asserts the reporting skill's gate-failure handoff names
the tower reword path; the on-demand `eval:skill` run, recorded by the
executing worker, shows a range-lint failure handoff naming it (Task 11).

### REQ-F1.4 — Purge stays human [test]

The purge helper prints the command and checklist and exits without
executing in a fixture (Task 11).

### REQ-F1.5 — Never main, protected, or spec [test]

The spelling fixtures include every rewrite and push form against those
refs and every copy in jurisdiction refuses them; a resolver test shows the
core floor (`main`, `master`, the spec pattern) present with the knob
unset, an overlay adding a glob the guard then refuses, an overlay value
naming only a feature branch leaving `main` still refused, a
`refs/heads/main` target matched after stripping, `planwright/*/spec` not
matching a two-segment middle, a malformed value denying the act, and no
host call in the guard's stubbed call log (Task 4, Task 5, Task 6).

## REQ-G — Guards and profiles

### REQ-G1.1 — One spelling list, every copy [test]

The cross-copy test drives the fixture file through every guard copy and
both profiles and fails on any line whose verdict for that copy differs
from the copy's output; the `git pull` and `master` lines fail before the
profile edit; a line the ready-guard does not recognise expects defer from
it and deny from the profiles; after Task 6 a worker-tier base-merge line
under the default value expects defer and a tower-tier one expects deny
(Task 5, Task 6).

### REQ-G1.2 — Enforcement follows the policy [test]

The policy-guard suite covers every value and tier for each policy-permittable
spelling; an unresolvable knob denies; the merge helper's flip call is
admitted under every flip value; a session with no tier profile gets defer
on every policy spelling (Task 6).

### REQ-G1.3 — The floor stays in the profiles [test]

The wiring tests assert every profile-expressible floor entry (main,
`master`, spec-branch mutation, direct PR-merge spellings, force-push, the
MCP names) is present in both profiles and that no policy-permittable entry
remains for a tier a value can grant it to; the guard-only floor entries are
pinned by the helpers' own fail-closed re-read tests (Task 6, Task 9).

### REQ-G1.4 — Deterministic, bounded, fail-closed [test]

The suite pins no model invocation, a wall-clock bound on the knob read, a
deny on a stubbed read failure, and zero resolver calls in the stubbed log
for a command outside the guard's jurisdiction (Task 6).

### REQ-G1.5 — Wired and pinned [test]

`tests/test-worker-settings-hook-wiring.sh` and the tower sibling cover the
new hook (Task 6) and the corrective helper (Task 8).

### REQ-G1.6 — Echo discipline in the new scripts [test]

`check:echo-safety` passes over the new scripts, each sources
`scripts/echo-safety.sh`, and a fixture feeding a control sequence through
a branch name, a conflicting path, and a host reply shows it stripped from
every PR record and park the scripts write (Task 6, Task 7, Task 9,
Task 10).

## REQ-H — Prose surfaces

### REQ-H1.1 — Skills split by kind, within budget [test]

`check-instructions.sh` reports no surface over budget after the sweep; a
grep fixture finds each skill's invariant section citing the doctrine doc
(Task 12).

### REQ-H1.2 — Docs agree, retired phrasings purged [test]

The purge seed refuses a reintroduced short phrase in a fixture and the
dedicated grep screen refuses a reintroduced sentence-length phrasing while
ignoring `specs/`, the changelog, and the observations log;
`check-doc-links.sh` and the options check pass (Task 12).

### REQ-H1.3 — Every knob documented [test]

`scripts/check-options-reference.sh` passes with the new rows; a grep over
the merged history finds the `BREAKING CHANGE:` footer on the commit that
lands `ready_flip_policy` (Task 4, Task 12).
