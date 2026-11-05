# Human gates — Test Spec

**Status:** Ready
**Last reviewed:** 2026-11-05
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` where automation is honest (the knob resolver, the
guards and their adversarial suites, the trailer parser, the helpers over a
stubbed `gh`, and the repository's existing index, link, options, purge, and
instruction-budget checks, all run by `mise run check` and the repository
CI); `[Gherkin]` for the policy scenarios the helpers must reproduce as
fixtures; `[manual]` for the live acts (the reviewer-request probe, the
tower's operator-requested force-push, and the first unattended release)
and the on-demand `eval:skill`
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

### REQ-A1.6 — The spec-branch push row [test]

`tests/test-human-gates-doctrine.sh`, run by `mise run check`, passes its
kind check with the new composition-contract row and finds `/spec-kickoff`,
the relayed kickoff session, and the launch-record-named branch in it; a
fixture copy of the doc without the row fails; the spec-branch rewrite row
is unchanged against the merge-base (Task 13).

### REQ-A1.7 — The class test [test + design-level]

`tests/test-human-gates-doctrine.sh` finds the class test's four arms and
the named-outward-effect clause in `doctrine/human-gates.md` and fails on a
fixture copy without them (Task 14). The extension's kickoff lens pass
applies the test to each core class and records the arm-by-arm reading,
the release class's outward effect included [design-level].

### REQ-A1.8 — Standing authorization and the unchanged gates [test + design-level]

The doctrine test finds the standing-authorization rule and a Human gate
row for each act REQ-A1.8 lists, unchanged against the merge-base for the
rows that already existed (Task 14). The cross-copy fixture keeps every
floor line's deny for those acts at every tier (Task 17).

### REQ-A1.9 — The drafting-push row [test]

`tests/test-human-gates-doctrine.sh` finds the composition-contract row
naming `/spec-draft`, the relayed drafting session, and the one spec branch
its launch record names, and fails on a fixture copy without it; the
REQ-A1.6 row is unchanged (Task 19).

### REQ-A1.10 — The release authorization and the publish row [test]

The doctrine test finds the "Publishing a release" row stated as an
authorization (the operator's merge of the release PR, or an enabled release
class) with its Human gate kind, and the composition-contract row naming the
release tool and the relayed release session, failing on a fixture copy
without them (Task 20).

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

### REQ-B1.10 — Legacy ids from the hash [test]

A fixture branch with one commit whose subject ends with
a space and `[pending-sign-off]` and no trailer regenerates to one item with id
`PS-legacy-` plus the first seven hex characters of that commit's full
hash; the id is unchanged across a base-merge that reorders the range; its
revert drops it and is not itself an item; a later commit carrying
`Planwright-Sign-Off-Rejected: PS-legacy-<sha7>` drops it; two legacy
commits sharing the prefix yield a named error and no checklist; the next
`PS-<n>` allocation on the same branch is unaffected (Task 2).

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

### REQ-C1.5 — Worker-only [test] (superseded by REQ-C1.9)

The policy-guard suite denies the flip spelling under the tower profile at
every value, defers it under the worker profile at `unit-owner` and for the
merge helper's own flip call under `policy-class`, and defers it in a
session with no tier profile; a standalone review-skill fixture never calls
the helper (Task 6, Task 7).

### REQ-C1.9 — Worker-only, plus the relayed kickoff's spec-PR flip [test]

Every REQ-C1.5 case holds unchanged (Task 6, Task 7), and the mission-control
tier's flip cases stay mission-control's. The kickoff-tier cases ship with
mission-control Task 19, routed there by this bundle's Deferred item "The
kickoff-tier cases in mission-control Task 19": in
`tests/test-policy-guard-mission-control.sh`, run by `mise run check`, the
flip of the spec PR whose head is the launch record's branch in the
posture's repository passes the policy guard when
`mark_spec_pr_ready_on_kickoff` resolves true and is denied when it
resolves false, and the flip of any other PR, a fork's same-named branch
included, is denied under the kickoff profile.

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

### REQ-D1.5 — No allowance outside the class [test] (superseded by REQ-D1.11)

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

### REQ-D1.9 — Task branches only, release never [test + Gherkin + design-level]

Given a fixture PR on `planwright/<spec>/task-<id>` from the base
repository with every other predicate holding, then it is admitted. Given
the same branch name from a fork, or any non-task head (the
`release-please--branches--main` release branch, a `dependabot/` branch,
`planwright/flight/<id>`), then it falls to `on-approval` with the reason on
the PR under every layer's configuration. Given a trailered or legacy
suffixed commit in the range that a later commit reverts, then the PR is
still refused (Task 9). Each release-approval passage Task 9 names states
the rule [design-level] (Task 9).

### REQ-D1.11 — The class mode under every merge policy [test]

The policy-guard suite admits the helper's class mode in the worker tier
under `human`, `on-approval`, and `policy-class` while a class is enabled
and the kill switch is off, denies it with no class enabled, and denies it
to the tower profile under every value (Task 17).

### REQ-D1.10 — Task branches under the policy, other PRs only through a class [test + Gherkin + design-level]

Given no automatic merge class enabled, then REQ-D1.9's scenarios hold
unchanged under every `merge_policy` value (Task 17). Given `merge_policy:
policy-class` and a release PR, then the `merge_policy` path still falls to
`on-approval` and only the release class's evaluation can admit it (Task
17). Given a release PR carrying a trailered commit with the release class
enabled, then it is refused (Task 16). Each release-approval passage Task 14
names states the class exception [design-level] (Task 14).

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

### REQ-G1.1 — One spelling list, every copy [test] (superseded by REQ-G1.10)

The cross-copy test drives the fixture file through every guard copy and
both profiles and fails on any line whose verdict for that copy differs
from the copy's output; the `git pull` and `master` lines fail before the
profile edit; a line the ready-guard does not recognise expects defer from
it and deny from the profiles, except a `gh api` line, which expects prompt
from both; after Task 6 a worker-tier base-merge line
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
pinned by the helpers' own fail-closed re-read tests, and the `gh api` ones
by the policy-guard suite (Task 6, Task 9).

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

### REQ-G1.7 — The `gh api` acts deny [test]

The fixture's policy-guard column expects deny, at worker and tower tiers,
on a `gh api` line for each classified act: the three named mutations,
`enablePullRequestAutoMerge`, `enqueuePullRequest`, `mergeBranch`,
`updatePullRequestBranch`, REST writes to `pulls/<n>/merge`, `merges`, and
`pulls/<n>/update-branch` (with a leading slash, a full URL, `-XPUT`, and
`--method=PUT` among the spellings), a forced ref update, and a
protected-ref write; both profiles expect prompt on every one. The
policy-guard suite shows zero resolver calls for every act but the
protected-ref write, which reads only `protected_branches` (Task 6).

### REQ-G1.8 — Unreadable denies, readable defers [test]

The fixture's policy-guard column expects deny on each unreadable form (a
query from `@<path>` and `@-`, a non-query `-F x=@file`, `--field`, an
`--input` body, a write on a variable endpoint with no method flag, a
query held in a variable and in `$(...)`, a `{branch}` in a query, an
unknown flag, `bash -c` and `env gh` wrappers, a compound with one reserved
segment) and defer on an inline thread-resolution mutation and a literal
REST reviewer request; both profiles expect prompt. The policy-guard suite
shows zero resolver calls for each unreadable form, defer on every `gh api`
line with no tier profile, and a deny message naming its remedy (Task 6).

### REQ-G1.9 — The relayed kickoff's one-branch admission [test]

The cases ship with mission-control Task 19 (its D-36), routed there by
this bundle's Deferred item "The kickoff-tier cases in mission-control
Task 19", in `tests/test-policy-guard-mission-control.sh` and
`tests/test-permission-matcher.sh`, run by `mise run check`, plus kickoff
profile lines in the REQ-G1.10 cross-copy fixture. A fixture kickoff
session plain-pushes its record's spec branch to the posture's remote and
opens its draft PR with no prompt. Each of these is denied with the
guard's reason line: a force push (`--force`, `--force-with-lease`, a `+`
refspec); a deletion (`--delete`, `:<branch>`); a rewrite; a non-draft PR;
a push of another spec branch, a task branch, or `main`, as a plain name
or a destination (`HEAD:planwright/<other>/spec`,
`planwright/<spec>/spec:main`); a two-refspec push pairing the record's
branch with a task branch; a tag push; a push to a URL, a path, or a
remote whose push URL is not the posture's repository; and a push carrying
`--receive-pack` or `--exec`. A session with no launch record, one naming
no conforming branch, or one whose record is bound to another session is
denied every push, as is a push under a posture providing none. A
worker-tier and a mission-control-tier push to the same spec branch keep
their pre-amendment verdict. A grep of the kickoff profile finds every
worker-profile deny other than the spec-branch plain-push denies, and a
deny for the spec-branch deletion spellings.

### REQ-G1.10 — One spelling list, every profile [test] (superseded by REQ-G1.13)

Every REQ-G1.1 case holds unchanged for the worker and tower profiles
(Task 5, Task 6). With mission-control Task 19, the cross-copy test drives
the kickoff profile too: its spec-branch plain-push lines expect defer from
that profile and the REQ-G1.9 verdicts from the policy guard's kickoff
tier, every other floor line expects deny from it, and a floor line
expecting anything but deny from the worker or tower profile still fails
the test.

### REQ-G1.11 — The relayed drafting session's one push [design-level + manual]

The Deferred bullet routing mission control's drafting launch kind exists
with its gate, and names the cross-copy cases its guard code must carry: the
launch record's branch admitted for a plain push; every PR creation, every
ready flip, another branch, a tag, a force push, a deletion, and a record of
another kind or session denied [design-level]. The `/spec-draft` eval run
shows the push after the commit, skipped and surfaced with an open non-draft
PR on the branch, and no push in an attended run [manual] (Task 19).

### REQ-G1.12 — The relayed release session's two paths [design-level + manual]

The Deferred bullet routing mission control's release launch kind exists
with its gate, and names the cross-copy cases its guard code must carry: the
watcher armed only on an open release PR; the fast-forward of the primary
checkout's `main` admitted only with `main` checked out, a clean tree, a
merged PR, and no watcher armed, and the release tool only after it; any
other pull, merge, rebase, reset, checkout, push,
edit, or PR write denied, and every act denied with a record that is absent,
of another session, or naming an unmerged PR [design-level]. The first
release published by such a session is watched by the operator and read
against the published tag, owned by the operator through the routing
bullet [manual].

### REQ-G1.13 — One spelling list, two tier-scoped exceptions [design-level]

The Deferred bullets routing mission control's drafting and release kinds
name the cross-copy floor-line cases for the kickoff tier's spec-branch
push and the release tier's fast-forward [design-level]; the unchanged
REQ-G1.10 cases keep passing in `mise run check` [test] (the existing
cross-copy suite).

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

### REQ-H1.4 — Supersede pointers across bundles [test]

Every row of the survey table in the sweep's PR carries its pointer in the
REQ-H1.4 form or, for a bundle deriving Ready or Active at the run, a gated
bullet under this bundle's `## Deferred`; a diff test shows every pointed
record's body unchanged; `scripts/spec-validate.sh --baseline <merge-base>`
passes on every bundle edited; `scripts/spec-anchor.sh` gives the same
anchor at the merge-base and the head for every bundle deriving Ready or
Active at the merge-base (Task 12).

## REQ-I — Automatic merge classes

### REQ-I1.1 — The opt-in class list [test]

The knob tests resolve `auto_merge_classes` through all four layers, read
empty by default, fail a repo-tracked unknown name with a non-zero exit, and
degrade an adopter or machine-local unknown name to empty with a warning; a
`merge_policy` value never changes the list's reading (Task 15).

### REQ-I1.2 — Classes defined in core, narrowed by layers [test]

A fixture layer naming an extra glob outside a class's core list does not
widen it, and a narrowing knob value admits strictly fewer fixture PRs than
the default (Task 16).

### REQ-I1.3 — The shared conditions on the current head [test + Gherkin]

One scenario per condition, each with every other condition met: given a
queued, pending, or missing required check; an `UNKNOWN` mergeability that
persists after one re-query; a path outside the allow-list or in the zone;
an unexpected author or a fork head; no step record on the head; a
sign-off trailer or legacy suffix, reverted or not; a change to a
merge-configuration file; a revert PR; a hold label, a changes-requested
review, or an unresolved thread; a live Awaiting-input segment on a task
branch; the kill switch on; a required approval, code-owner review, or
last-push approval outstanding, a required conversation unresolved, a merge
method the base disallows, a merge state other than `CLEAN`, or a required
merge queue; a failing non-required check; a change to the release
tooling; a symlink, submodule, or mode change; a commit not verified by
the host, or on an identity-bound class not signed by the host; a base
branch retargeted after evaluation; then the PR is refused
with that condition named. Given the head, base OID, or kill switch moving between evaluation
and the merge call, then no merge call is made (Tasks 16, 17).

### REQ-I1.4 — One helper, a normal merge [test]

The helper suite shows the class merge using the resolved method with no
administrator or force flag, a draft class PR flipped through the ready-flip
helper before merging, and every direct PR-merge spelling denied to every
tier in the cross-copy test (Task 17).

### REQ-I1.5 — The caller's floor [test + design-level]

The policy-guard suite admits the helper's class mode for the
mission-control and worker tiers only while a class is enabled and the kill
switch is off, and denies it otherwise (Task 17). The Deferred bullet
routing mission control's amendment exists with its gate [design-level].

### REQ-I1.6 — The record and the ledger [test]

Over stubbed `gh`, an admitted PR gets the record comment (class, each
condition and its evidence, head SHA, base OID, undo command) and the ledger
line before the merge call; a failing record or ledger write yields no merge
call; a merge call failing after the record yields the follow-up comment
(Task 17).

### REQ-I1.7 — The undo [test]

The undo helper opens a draft revert PR naming the original record, and the
evaluator refuses that revert PR under every class (Task 17); for a release,
the record's undo text names the revert-plus-next-release form (Task 18).

### REQ-I1.8 — The kill switch and the class cadences [test]

`auto_merge_halt: true` at the machine-local layer under a repo-tracked
`false` stops every class, and an unreadable value stops it too (Task 15);
the helper re-reads it before the merge call (Task 17). For each class, a
fixture PR lacking the core cadence's step record on the head is refused,
and a layer removing a step is ignored (Task 16).

### REQ-I1.9 — The release class [test + Gherkin + manual]

Given the release tool's PR with every condition met and an armed watcher
pre-validated on its head, then it is admitted and the publish runs on the
observed merge; given a changed path beyond the three files, a version-file
diff touching more than the version, a version not above the latest tag, a
human commit, no armed watcher, or a signer that prompts, then it is refused
(Tasks 16, 18). Given a release carrying a class-merged change and every
condition met, then it is admitted; given a changelog section with no
user-facing entry, a required check red on the commit to tag, or an open
revert of a carried change, then it is refused (Task 18). The first
unattended release in this repository is watched by the operator and its
record read against the published tag [manual].

### REQ-I1.10 — The dependency class [test + Gherkin]

Given a bot-authored PR bumping a patch or minor version in a core-listed
manifest and its lockfile, then it is admitted; given a major bump, an
undeterminable type, a CI workflow change, a human commit on the bot branch,
or an author outside the list (the default empty list included), then it is
refused (Task 16).

### REQ-I1.11 — The test-only class [test + Gherkin]

Given a PR changing only test-glob paths, adding or editing tests, then it
is admitted; given a deleted or renamed-away test file, or a change to the
reserved-control fixture, then it is refused (Task 16).

### REQ-I1.12 — No performance class [test]

`auto_merge_classes: performance` fails a repo-tracked value and degrades
an adopter or machine-local one to empty, as any undefined name does (Task
15); a fixture speedup PR is admitted by no class (Task 16).

### REQ-I1.13 — The observation-carry class [test + Gherkin]

Given a PR adding fragments or moving them unchanged between the live and
archive directories, then it is admitted; given an edited fragment or a
path outside the accumulator, then it is refused (Task 16).

### REQ-I1.14 — The bookkeeping class [test + Gherkin]

Given a PR removing only Awaiting-input reference bullets whose tasks derive
Completed on the base, then it is admitted; given a removed bullet whose
task does not, or any other line changed, then it is refused (Task 16).

### REQ-I1.15 — The docs-only class [test + Gherkin]

Given a PR changing only documentation-glob paths, then it is admitted;
given a change to doctrine, a skill, or an agent instruction file, then it
is refused (Task 16).

### REQ-I1.16 — The regeneration class [test + Gherkin]

Given a PR whose head tree the base's command reproduces on a clean base
checkout, then it is admitted; given a tree that differs, an empty command,
or a command changed only on the head, then it is refused, the head's
command never run (Task 16).

### REQ-I1.17 — Options, doctrine rows, and routed follow-ons [test + design-level]

The options check finds a row and a commented default for every knob Task 15
adds; the doctrine test finds the class rows and the kill switch row (Task
14); the bundle's `## Deferred` carries the mission-control and dotfiles
bullets with their gates [design-level].

### REQ-I1.18 — Waiting on a required approval [test + Gherkin + design-level]

Given a class PR meeting every condition but an outstanding required
approval, then the evaluator's verdict is a wait naming that gate, distinct
from a refusal, and no approval, review dismissal, review request, or
override is issued; given the approval arriving, then the same PR is
admitted on a later evaluation (Task 16). The once-per-head report and the
sweep re-evaluation are cases the mission-control caller's Deferred bullet
names [design-level].
