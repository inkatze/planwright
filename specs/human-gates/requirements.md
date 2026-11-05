# Human gates — Requirements

**Status:** Draft
**Last reviewed:** 2026-11-05
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright's reserved-control list was fixed in bootstrap D-26 when agents ran
without guards: every framework PR stays draft, the human flips it ready, the
human merges, nothing rewrites history. The guards have since arrived (deny
profiles per tier, a deny-emitting ready-guard, allow-only command guards, CI
on the head SHA, a review sequence that converges before a PR opens), and the
repo has ruled twice that the draft→ready flip is a preference rather than a
gate (merge-currency-guard D-9; kickoff-lifecycle D-6), yet the skills, the
docs, and the tower profile still say "never", and the operator flips every
unit by hand, which is the bottleneck fleet operation exists to remove.

This spec re-derives the human-gate list from a stated test rather than from
the era it was written in (altitude: doctrine first, then policy, then
mechanism, D-1): an act stays human when it is irreversible for
other people or when it is the approval act that ends the framework's review
contract. Everything else becomes a policy with a core default an adopter may
change through the overlay, or is recognised as a composition contract between
skills that was never a trust rule at all. Concretely: sign-off moves to the
human's approval act so that an agent flipping a PR ready approves nothing;
the flip becomes a policy with verifiable preconditions; merge becomes a tiered
policy whose shipped default keeps today's posture; a worker may merge its base
into the branch it owns; never-pushed commits may be reshaped; and every guard,
profile, skill, and doc restates one list instead of carrying its own.

The 2026-11-05 extension applies the operator's rule for unattended work: act
automatically wherever the act is verified and reversible, and stop only
where it could cause harm (D-19). It does so as a test a named class of pull
requests must pass before it may be enabled, never as a blanket permission:
an opt-in list of automatic merge classes, empty by default, lets mission
control merge a PR inside an enabled class once every condition holds on
the PR's current head, leaving an audit record, a one-step undo, and a kill
switch, while every PR outside an enabled class stays exactly where the
list above puts it.

## Scope

### In scope

- The gate test and the resulting human-gate list, superseding bootstrap
  D-26 by pointer and carrying its unchanged rules forward.
- Sign-off relocated to the approval act, with the `Planwright-Sign-Off`
  trailer replacing the subject marker, the checklist regenerated from
  trailers, and the revert double-count closed.
- A `ready_flip_policy` knob with its preconditions, records, and failure
  path, and the reviewer-request side effect that un-drafts a PR.
- A tiered `merge_policy` knob (`human`, `on-approval`, `policy-class`) with
  `human` as the shipped default, the approval surface, the predicates a
  policy class may use, and the record an agent merge leaves.
- A worker merging the PR base into the branch it owns, with conflict handling
  as a knob.
- Reshaping never-pushed commits on an owned branch; an operator-requested
  force-push through the tower; the commit-message repair path; the secret
  purge staying human.
- Enforcement derived from the resolved policy: profiles as the floor, guards
  reading the policy, and one shared fixture list of reserved-control
  spellings every guard copy must refuse, with the `gh api` control lines
  the policy guard reads (REQ-G1.8).
- Every skill and doc surface restating the list from one doctrine source,
  with composition contracts labelled apart from trust rules.
- Supersede pointers on the records other bundles still carry for a changed
  rule, and the release PR's exclusion from every policy class.
- The floor a relayed kickoff session must meet to publish its own spec
  branch (a plain push, its draft PR, the configured flip), and the
  doctrine row that names it.
- The class test an automatic merge class must pass, the core-defined
  classes (release, dependency update, test-only, performance, observation
  carry, bookkeeping, documentation-only, deterministic regeneration), the
  knobs that enable and narrow them (all off by default), the conditions
  each must meet on the current head, the merge helper's class mode, the
  audit record, the undo, and the kill switch.
- A release merged by its class being followed by the existing armed
  publish flow.

### Out of scope

- Lifecycle hooks as a general operator seam (issue planwright#383); this
  spec names no pipeline states.
- The deterministic `pr-ready` attention record (the merge-currency-guard
  amendment seed); an agent flip leaves a PR record, not a fleet signal.
- Widening `review_sequence` to skills outside the plugin
  (issue planwright#393).
- Re-arming verification when a merge changes a unit's head, and the reconcile
  fan-out of a base sync after a merge lands: merge-currency-guard owns the
  first and the orchestrator's reconcile sweep owns the second.
- The ready-guard's predicate, its per-call parse cost, and the MCP server
  naming residual; the guard stays the fail-closed floor exactly as shipped.
- Acting on a spec that is neither Ready nor Active, and auto-chaining
  `/orchestrate` into `/spec-kickoff`: both carry forward unchanged.
- The release publish gate: release-hardening owns it.
- The dotfiles `CLAUDE.md` restatement of the invariants: out of this repo,
  named in the handoff.
- A merge executed by an agent outside a configured policy, at any tier,
  under any value: there is no such value.
- The kickoff launch kind, its settings profile, its launch record, and the
  policy-guard code that admits its push: mission-control D-36 and its
  Task 19 ship and test them against REQ-G1.9.
- Mission control's own act of calling the class merge helper, its tier
  profile's allowance, and the amendment of its "never merge" requirement
  (mission-control REQ-I1.1): routed to mission-control as a follow-on;
  this bundle states the floor they must meet.
- Installing or configuring a dependency bot in this repository: a
  prerequisite for the dependency class here, decided apart from it
  (D-22).
- The operator's own `CLAUDE.md` "Never auto-merge" line: changed in a
  separate dotfiles PR.
- A class an adopter defines in configuration: a new class is a spec
  amendment that passes the class test, never a config value.

## REQ-A — The human-gate list

- **REQ-A1.1** planwright SHALL keep an act human-reserved exactly when it
  meets the gate test: the act is irreversible for other people (it changes
  shared history or ships something), or it is the approval act that ends the
  framework's review contract. An act meeting neither condition SHALL NOT be
  a human gate; it is a policy or a composition contract.
  *(Cites: D-1, D-2; obs:77e452b4; issue planwright#379; the autopilot-reflex
  gate list (Sources).)*
- **REQ-A1.2** Under that test, authorizing a merge and signing off a finding
  SHALL be human gates at every tier and under every policy value. The
  draft→ready flip, a base merge into an owned branch, and the reshaping of
  never-pushed commits SHALL NOT be human gates; each SHALL be a policy with
  a core default. The push of an owned branch SHALL be a composition
  contract between skills, never a trust rule.
  *(Cites: D-2, D-4, D-6, D-7, D-8; issue planwright#385.)*
- **REQ-A1.3** The gate list and the rule kinds SHALL be stated once, in one
  doctrine document; every skill, profile, guard, and doc SHALL restate that
  list by citation, and a divergent copy SHALL be a defect.
  *(Cites: D-10; obs:518be7dd.)*
- **REQ-A1.4** Every rule bootstrap D-26 and bootstrap REQ-J1 carry that this
  bundle changes SHALL be superseded by pointer, its body unedited; every rule
  it does not change (never act on a spec that is neither Ready nor Active,
  never auto-chain `/orchestrate` into `/spec-kickoff`) SHALL carry forward
  with its citation intact.
  *(Cites: D-2; bootstrap D-26 (Sources).)*
- **REQ-A1.5** Every rule the list states SHALL be labelled with its kind:
  a human gate, a policy (naming its knob and default), or a composition
  contract (naming the owning skill). A rule whose kind cannot be named SHALL
  NOT ship.
  *(Cites: D-10; issue planwright#385.)*
- **REQ-A1.6** The list SHALL carry a composition-contract row for pushing
  a spec branch and opening its draft PR, owned by `/spec-kickoff`, run
  either attended under no tier profile or as a relayed kickoff session
  under the kickoff profile, which writes only the one spec branch its
  launch record names (REQ-G1.9). A plain push of a spec branch SHALL NOT
  be a human gate; rewriting a spec branch SHALL stay one (REQ-F1.5).
  *(Cites: D-18; mission-control D-36 and REQ-I1.8 (Sources).)*
- **REQ-A1.7** A class of pull requests SHALL be eligible for unattended
  merge only when it passes the class test: membership is decided by
  mechanical predicates over the PR's head with no model in the decision
  path; every predicate is verifiable on the current head immediately
  before the merge, and one that cannot be read counts as unmet; the merge
  is undone by one revert PR and changes nothing outside the repository;
  and a wrong admission, left until the operator notices and reverts it,
  harms no one outside the repository's maintainers (no published
  artifact, no secret, no enforcement surface, no sign-off item). A class
  whose merge has an outward effect SHALL name that effect, and SHALL be
  enabled only after the operator accepted the effect at a kickoff. The
  test SHALL be stated in the human-gates doctrine as the bar every future
  class meets, and SHALL NOT be read as a permission for any act it does
  not name.
  *(Cites: D-19; the operator's unattended-work request (Sources).)*
- **REQ-A1.8** Enabling an automatic merge class SHALL be the human's
  standing authorization of every merge inside it, so authorizing a merge
  stays a human gate (REQ-A1.2). These SHALL stay human gates, unchanged by
  any class: the merge of every PR outside an enabled class, a spec PR and
  every sign-off, a push to a protected branch, every force push, the
  deletion of a remote branch, and every message to a person.
  *(Cites: D-19; the operator's unattended-work request (Sources).)*

## REQ-B — Sign-off at the approval act

- **REQ-B1.1** The sign-off of a Needs-sign-off finding SHALL be the human's
  approval act on the PR — the merge under `merge_policy: human`, the
  approval that enables the merge under `on-approval` — and SHALL NOT be the
  draft→ready flip. Flipping a PR ready SHALL approve nothing.
  *(Cites: D-3; obs:77e452b4; obs:2e9b7741.)*
- **REQ-B1.2** A commit carrying a Needs-sign-off application SHALL carry a
  `Planwright-Sign-Off: PS-<n>` git trailer stamped through the trailer
  helper, and SHALL NOT carry the `[pending-sign-off]` subject suffix. The
  `PS-<n>` value SHALL be written at commit time and SHALL never be
  recomputed from commit order.
  *(Cites: D-3; issue planwright#384; obs:2bba6bcf.)*
- **REQ-B1.3** The pending-sign-off checklist SHALL regenerate from the
  trailers in the PR's `base..head` range through git's trailer parser, never
  from subject text. A revert of a trailered commit SHALL remove that item
  and SHALL NOT be counted as a new item; a later commit in the range
  carrying `Planwright-Sign-Off-Rejected: PS-<n>` SHALL remove the item too,
  the mechanism for rejecting one finding of a shared commit or a `resolve`
  resolution where a plain revert is not the recipe. A `base..head` range
  that cannot be resolved SHALL fail the regeneration with a named error,
  never emit an empty checklist, and `PS-<n>` allocation over it SHALL refuse
  rather than restart the sequence.
  *(Cites: D-3; issue planwright#388; kickoff sign-off lens pass
  (2026-09-22).)*
- **REQ-B1.4** `scripts/check-commit-msgs.sh --marker subject` SHALL be
  retired. `--marker title` SHALL be kept for one release, broadened to
  reject the legacy bracket or a bare `Planwright-Sign-Off:` line in a PR
  title, and its removal SHALL be a gated deferral.
  *(Cites: D-3; issue planwright#384.)*
- **REQ-B1.5** The generated pending-sign-off section SHALL state, inside
  the section itself, which act approves the listed items and that an item is
  rejected before that act by its printed recipe (a revert, or the REQ-B1.3
  rejected trailer where a revert is not the recipe); the checkbox SHALL NOT
  read as the approval control.
  *(Cites: D-13; obs:2e9b7741.)*
- **REQ-B1.6** The one-commit-per-finding discipline SHALL yield to
  green-commit ordering: where findings are not file-isolable or share a
  regression test, one commit carrying every affected finding's trailer with a
  per-item rejection recipe in the checklist (a partial revert commit carrying
  that item's REQ-B1.3 rejected trailer) SHALL be conforming, and the
  checklist SHALL disclose the shared commit.
  *(Cites: D-12; obs:94b217c4.)*
- **REQ-B1.7** The attended path of every gate-wired skill SHALL state the
  apply-then-review default as its unattended path does: a Needs-sign-off
  finding is applied on the branch in its own commit and SHALL NOT be posed
  as a question before application.
  *(Cites: D-13; obs:11c3af76.)*
- **REQ-B1.8** Every handoff that leaves trailered commits on a branch SHALL
  print their SHAs and the trailer-aware log command, since a trailer is
  invisible in `git log --oneline`.
  *(Cites: D-3; issue planwright#384.)*
- **REQ-B1.9** The migration SHALL be a single doctrine line mapping the
  legacy subject marker to the trailer; no history SHALL be rewritten and no
  branch SHALL be swept.
  *(Cites: D-3; issue planwright#384.)*
- **REQ-B1.10** A legacy commit, meaning any commit whose subject ends with
  a space and `[pending-sign-off]` and that carries no
  `Planwright-Sign-Off` trailer,
  whatever its date, SHALL render in the checklist with the id
  `PS-legacy-<sha7>`, where `<sha7>` is the first seven hex characters of
  its full commit hash (never git's auto-abbreviation), never derived from
  commit order and never allocated from the `PS-<n>` sequence. Two legacy
  commits in one range sharing that prefix SHALL fail the regeneration with
  a named error. A commit whose body carries git's `This reverts commit
  <sha>` line SHALL never itself be an item and SHALL drop the legacy item
  it reverts; a later commit carrying
  `Planwright-Sign-Off-Rejected: PS-legacy-<sha7>`, matched exactly, SHALL
  drop it too, the rejected-trailer value grammar being `PS-<n>` or
  `PS-legacy-<sha7>`. For the legacy suffix only, this requirement takes
  precedence over REQ-B1.3's never-from-subject-text rule, and it extends
  REQ-B1.9's one-line migration with this rendering; no history is
  rewritten and no branch swept.
  *(Cites: D-3, D-16; planwright#506 review decisions (Sources).)*

## REQ-C — Ready-flip policy

- **REQ-C1.1** A `ready_flip_policy` knob SHALL resolve through the
  four-layer overlay with the values `human` (only a human flips, the
  REQ-D1.4 helper's own flip of an admitted PR excepted) and `unit-owner`
  (the skill executing a unit flips its own PR once REQ-C1.2 holds). The
  shipped default SHALL be `unit-owner`. A malformed repo-tracked value
  SHALL make the resolver fail and every reader SHALL deny the act; a
  malformed adopter or machine-local value SHALL degrade to `human` with a
  warning, never to the shipped default.
  *(Cites: D-4; issue planwright#379; merge-currency-guard D-9 (Sources);
  kickoff sign-off lens pass (2026-09-22).)*
- **REQ-C1.2** A `unit-owner` flip SHALL fire only after the unit's draft PR
  exists and only when every precondition holds on the head that results
  once the helper has reconciled and pushed the unit's Awaiting-input section
  (REQ-C1.4): the ready-guard's currency and mergeability check passes; the
  head SHA's check rollup is a positive green within a bounded wait; the
  configured review sequence converged on that head, where a commit touching
  only the spec's `tasks.md` Awaiting-input section (a park or unpark) SHALL
  NOT count as moving the reviewed head; and the unit has no live
  Awaiting-input segment other than a REQ-C1.4 parking lead, read from both
  the unit's checkout and the fetched base ref. The check SHALL be
  deterministic, with no model in the decision path. With no PR or no host
  CLI the helper SHALL skip cleanly and say so in the handoff, never park; a
  transient host failure SHALL be retried within the bounded wait before it
  counts as a failed precondition.
  *(Cites: D-5; obs:921b93c9; obs:75c25c5d; kickoff-verification (Sources);
  kickoff sign-off lens pass (2026-09-22).)*
- **REQ-C1.3** A `unit-owner` flip SHALL leave a record on the PR before the
  flip naming the policy value, the head SHA, and the evidence for each
  precondition. A flip whose record write fails SHALL NOT proceed. The record
  is a claim of intent: a flip call that fails after the record is written
  SHALL park per REQ-C1.4 and append a follow-up comment naming the failure,
  so no PR carries an unqualified record of an act that did not happen.
  *(Cites: D-5; kickoff sign-off lens pass (2026-09-22).)*
- **REQ-C1.4** When any precondition fails, the PR SHALL stay draft and the
  pending flip SHALL be recorded under the spec's `## Awaiting input` naming
  the failed precondition, the same re-entry path `/spec-kickoff` uses. The
  parking text SHALL be a segment opening with the fixed lead
  `pending ready-flip:`; every predicate that reads `## Awaiting input`
  (REQ-C1.2, REQ-D1.3) SHALL ignore that segment only, so a bullet carrying
  any other live segment (a `halt` park, a human question) still blocks. The
  park SHALL be one read-modify-write of the section in the unit's own
  checkout, committed in one commit on the unit branch and pushed,
  idempotent per lead (a re-run replaces its own segment) and composing with
  any bullet the base already carries for the unit; a park that cannot be
  written SHALL leave the tree clean and be named in the handoff. The next
  passing run SHALL remove only its own segment, reconciling and pushing
  before it pins the head it evaluates.
  *(Cites: D-5; kickoff-verification (Sources); kickoff §3 REQ-C
  (2026-09-22); kickoff sign-off lens pass (2026-09-22).)*
- **REQ-C1.5** The flip under `unit-owner` SHALL be performed by
  `/execute-task`'s convergence run, or by a review skill only when
  `/execute-task` delegates its terminal step to it, directly or through the
  REQ-D1.4 merge helper it calls; a standalone review-skill run SHALL NOT
  flip. The tower profile, which the orchestrator tier runs under, SHALL
  keep its flip deny regardless of the policy value. An attended session
  with no tier profile is outside the policy guard's jurisdiction for the
  flip, where the ready-guard stays the floor; that is where `/spec-kickoff`'s
  spec-PR flip runs.
  *(Cites: D-4, D-9; kickoff sign-off lens pass (2026-09-22).)*
  **Superseded-by: REQ-C1.9** (2026-11-04) — the spec-PR flip may also run
  in a relayed kickoff session under the kickoff profile.
- **REQ-C1.9** (supersedes REQ-C1.5) The flip under `unit-owner` SHALL be
  performed by `/execute-task`'s convergence run, or by a review skill only
  when `/execute-task` delegates its terminal step to it, directly or
  through the REQ-D1.4 merge helper it calls, or by a mission-control
  session for any PR of the repository whose checkout it runs in, under
  mission-control REQ-I1.2; a standalone review-skill run SHALL NOT flip.
  The tower profile, which the orchestrator tier runs under, SHALL keep its
  flip deny regardless of the policy value. An attended session with no
  tier profile is outside the policy guard's jurisdiction
  for the flip, where the ready-guard stays the floor. `/spec-kickoff`'s
  spec-PR flip SHALL run either there or in a relayed kickoff session under
  the kickoff profile, where the policy guard admits only the flip of the
  PR for the spec branch its launch record names (REQ-G1.9) and the
  ready-guard stays the floor too.
  *(Cites: D-4, D-9, D-18; mission-control D-36 and REQ-I1.2 (Sources);
  kickoff amendment lens pass (2026-11-04).)*
- **REQ-C1.6** `mark_spec_pr_ready_on_kickoff` SHALL be documented as the
  spec-PR instance of the same policy kind and SHALL keep its own knob; this
  bundle SHALL NOT change its default.
  *(Cites: D-4; kickoff-lifecycle D-6 (Sources).)*
- **REQ-C1.7** No planwright surface that requests a reviewer on a draft PR
  SHALL leave the PR un-drafted as a side effect: the surface SHALL verify
  the draft state after the request and re-draft it, or use a transport
  without the side effect. The mechanism SHALL be verified against gh and
  GitHub documentation before the fix is chosen. A draft-state check that
  fails SHALL be treated as un-drafted and the corrective run; a corrective
  that fails SHALL park the unit per REQ-C1.4 naming the un-drafted PR.
  *(Cites: D-11; obs:02396e39; kickoff sign-off lens pass (2026-09-22).)*
- **REQ-C1.8** `gh pr ready --undo` SHALL be allowed to an agent only as the
  REQ-C1.7 corrective, through a helper the guards recognise, and SHALL stay
  denied in every other spelling.
  *(Cites: D-11.)*

## REQ-D — Merge policy

- **REQ-D1.1** A `merge_policy` knob SHALL resolve through the four-layer
  overlay with the values `human` (a human authorizes and executes the PR
  merge), `on-approval` (a human authorizes per PR; GitHub executes once
  required checks pass), and `policy-class` (a PR inside a declared class
  merges with no per-PR human act; a PR outside it falls to `on-approval`).
  The shipped default SHALL be `human`. A malformed repo-tracked value SHALL
  make the resolver fail and every reader SHALL deny the act; a malformed
  adopter or machine-local value, or an unresolvable one, SHALL degrade to
  `human` with a warning.
  *(Cites: D-6; research: GitHub auto-merge docs; research: Ona low-risk
  auto-approval; research: homu; kickoff sign-off lens pass (2026-09-22).)*
- **REQ-D1.2** Under `on-approval`, the approval act SHALL be the human
  enabling GitHub auto-merge on the PR; where REQ-D1.7 detects a distinct
  agent identity, an approving review by the human with auto-merge enabled
  SHALL be the same act. Agent sessions SHALL stay denied every PR-merge
  spelling under this value, so enforcement SHALL never depend on which
  token acted.
  *(Cites: D-6, D-14; research: GitHub required reviews.)*
- **REQ-D1.3** A policy class SHALL be declared by mechanical predicates
  only, evaluated by a deterministic script with no model in the decision
  path. The predicates SHALL always include: no `Planwright-Sign-Off` trailer
  in `base..head`; no changed path in the hard-disqualifier zone, defined as
  a core path-glob list no layer can shrink (planwright's own enforcement
  surface: the settings profiles, `hooks/`, the guard and policy scripts, the
  CI workflows, lockfiles, `doctrine/human-gates.md`, and the
  reserved-control fixture) plus the additions `merge_class_exclude_paths`
  carries; no live Awaiting-input segment for the unit other than a REQ-C1.4
  parking lead, read from the fetched base ref at evaluation time; the
  REQ-C1.2 preconditions on the head, evaluated once and handed with their
  SHA to the flip helper so the bounded CI wait never runs twice; and the
  adopter's own bounds (`merge_class_max_lines`, `merge_class_exclude_paths`).
  A PR failing any predicate SHALL fall to `on-approval`.
  *(Cites: D-6; research: Ona low-risk auto-approval; research: Renovate
  automerge; kickoff sign-off lens pass (2026-09-22).)*
- **REQ-D1.4** An agent PR merge under `policy-class` SHALL leave a record on
  the PR naming the policy value and each predicate with its evidence before
  merging, and SHALL run through one helper the guards recognise
  (`scripts/merge-admitted.sh`). A record write that fails SHALL abort the
  merge; the record is a claim of intent, so a merge call that fails after
  it is written SHALL append a follow-up comment naming the failure and park
  per REQ-C1.4. The helper SHALL run in the worker tier, called by the skill
  that owns the unit's branch as the terminal step after its own ready-flip;
  the tower profile SHALL stay denied, and the helper SHALL re-resolve the
  policy itself and fail closed. An admitted PR still in draft SHALL be
  flipped ready by that helper through the REQ-C1.2 path whatever
  `ready_flip_policy` resolves to, since the class predicates include every
  flip precondition. Immediately before the merge call the helper SHALL
  re-confirm the head SHA and the base ref OID and re-read the Awaiting-input
  predicate, refusing on any of them having moved since the predicates were
  evaluated. Every fall-through to `on-approval` SHALL write its reason as a
  PR comment.
  *(Cites: D-6, D-9; kickoff §3 REQ-D (2026-09-22); kickoff sign-off lens
  pass (2026-09-22).)*
- **REQ-D1.5** Under `human` and `on-approval`, no agent session at any tier
  SHALL hold a PR-merge allowance; under `policy-class`, only the helper of
  REQ-D1.4 SHALL be allowed, and only for a PR its predicates admit. The
  direct PR-merge spellings SHALL stay denied to agent sessions under every
  value; the helper is the sole sanctioned path. A worker's base merge
  (REQ-E1.1) is a different act and is governed by its own knob.
  *(Cites: D-6, D-9; kickoff sign-off lens pass (2026-09-22).)*
- **REQ-D1.6** The never-auto-merge floor SHALL be restated as: no agent
  merges outside a policy the human configured, and no value exists under
  which an agent merges a PR carrying a sign-off item. Every doc and doctrine
  passage stating the floor SHALL cite the policy rather than restate an
  unconditional never.
  *(Cites: D-2, D-6, D-10.)*

- **REQ-D1.7** planwright SHALL detect whether the agent session's GitHub
  login differs from the PR author's, SHALL recommend a distinct agent
  identity in its docs, and SHALL NOT require one: every policy value SHALL
  work under a shared identity through client-side enforcement, and a
  detected split SHALL only add the server-verified approval path.
  *(Cites: D-14; research: agent GitHub identity; research: GitHub required
  reviews.)*
- **REQ-D1.8** The merge strategy of a `policy-class` merge SHALL resolve
  from a `merge_class_strategy` knob with the values `sole-allowed` (the
  default: the single merge method the host allows), `squash`, `merge`, and
  `rebase`. When the host allows several methods and the knob is
  `sole-allowed`, when the named method is one the host disallows, or when
  the host query fails, the PR SHALL fall to `on-approval` naming the reason.
  *(Cites: D-6; kickoff §3 REQ-D (2026-09-22); kickoff sign-off lens pass
  (2026-09-22).)*
- **REQ-D1.9** The class evaluator SHALL admit a PR only when its head
  branch is a task branch (`planwright/<spec>/task-<id-or-ids>`, `<spec>`
  one path segment) and its head repository is the base repository. Every
  other PR (a release PR, a dependency-bot PR, a flight branch, a human's
  own branch, a fork) SHALL fall to `on-approval` with the reason on the
  PR, and no layer SHALL widen that set, so a release merge is a human
  approval act under every `merge_policy` value and never a class
  admission. The REQ-D1.3 sign-off predicate SHALL be a raw scan of
  `base..head`: a `Planwright-Sign-Off` trailer or a REQ-B1.10 legacy suffix
  on any commit refuses the PR, whether or not a later commit reverts or
  rejects it. The doctrine passages describing the release approval SHALL
  state this rule.
  *(Cites: D-6, D-15; planwright#506 review decisions (Sources).)*
  **Superseded-by: REQ-D1.10** (2026-11-05) — a release PR, a
  dependency-bot PR, and other non-task PRs may merge through an enabled
  automatic merge class.
- **REQ-D1.10** (supersedes REQ-D1.9) The `merge_policy` class evaluator
  SHALL admit a PR only when its head branch is a task branch
  (`planwright/<spec>/task-<id-or-ids>`, `<spec>` one path segment) and its
  head repository is the base repository; every other PR SHALL fall to
  `on-approval` under that knob with the reason on the PR. The automatic
  merge classes of REQ-I SHALL be the only route by which a release PR, a
  dependency-bot PR, a flight branch, or a human's own branch merges with
  no per-PR human act, and only while its class is enabled; with no class
  enabled, a release merge SHALL stay a human approval act under every
  `merge_policy` value. No layer SHALL widen either set beyond the classes
  core defines. The REQ-D1.3 sign-off predicate SHALL stay a raw scan of
  `base..head`, a `Planwright-Sign-Off` trailer or a REQ-B1.10 legacy
  suffix on any commit refusing the PR in every class, reverted or not.
  The doctrine passages describing the release approval SHALL state this
  rule.
  *(Cites: D-15, D-20; the operator's unattended-work request (Sources).)*

## REQ-E — Worker base merge

- **REQ-E1.1** A worker SHALL be able to merge the PR base into the branch it
  owns, and SHALL NOT merge into main, a protected branch, a spec branch, or
  another unit's branch. The base is the PR's base branch, or the branch the
  worktree was created from before a PR exists. The allowance SHALL be a
  `worker_base_merge` knob (`allow` by default, `deny`), stated as the act and
  enforced on every spelling that performs it, `git pull` included.
  *(Cites: D-7; obs:5775c447; obs:332374a2; kickoff sign-off lens pass
  (2026-09-22).)*
- **REQ-E1.2** A `worker_merge_conflict_policy` knob SHALL resolve through
  the overlay with the values `halt` (a conflicting merge is aborted, the
  tree left clean, and the unit parked under `## Awaiting input` naming the
  conflicting paths) and `resolve` (the worker resolves, commits the
  resolution, and flags that commit in the PR body for review). The shipped
  default SHALL be `halt`. The sync's other failure exits SHALL each have a
  named arm: a dirty tree, a failed fetch, or a failed merge parks the unit
  naming the failure class with the tree as the sync left it; an abort that
  itself fails SHALL write no park and SHALL name hand repair in the handoff.
  A `resolve` commit SHALL carry the `Planwright-Sign-Off` trailer of
  REQ-B1.2, so it appears in the checklist and no `policy-class` merge admits
  the PR; its checklist rejection recipe SHALL be re-running the sync under
  `halt`, the hand resolution's commit carrying the item's REQ-B1.3 rejected
  trailer, never a revert, since reverting a resolution restores the
  conflict.
  *(Cites: D-7; obs:332374a2; kickoff §3 REQ-E (2026-09-22); kickoff sign-off
  lens pass (2026-09-22).)*
- **REQ-E1.3** The tower profile, which the orchestrator tier runs under,
  SHALL keep its PR-merge and base-merge deny; the local-main fast-forward
  SHALL remain the only sanctioned mutation of a local main.
  *(Cites: D-7, D-9.)*

## REQ-F — History rewriting

- **REQ-F1.1** A commit that no remote ref contains, on the unit branch the
  session owns, SHALL be permitted to be amended, squashed, or rebased under
  an `unpushed_rewrite` knob (`allow` by default, `deny`); a spec branch is
  no session's unit branch (REQ-F1.5). Before allowing the act the guard
  SHALL refresh the branch's upstream tracking ref and verify that no
  remote-tracking ref contains the commit, refusing when the refresh fails
  or no upstream is configured; a commit any remote ref contains SHALL stay
  append-only.
  *(Cites: D-8; kickoff sign-off lens pass (2026-09-22).)*
- **REQ-F1.2** A force-push SHALL be performed only by the tower, only on an
  explicit operator request in the same turn, after a warning naming the
  remote commits the push will drop, and never to main or a protected
  branch. A standing decision SHALL NOT authorize it, and no session SHALL
  initiate it.
  *(Cites: D-8.)*
- **REQ-F1.3** A commit-range lint failure on a pushed branch SHALL be the
  named reason for a reword through the REQ-F1.2 path, and the handoff of the
  skill whose gate reports that failure SHALL name the path.
  *(Cites: D-8; the CI commit-range lint (Sources).)*
- **REQ-F1.4** A history purge for a leaked secret SHALL remain a human-run
  rewrite; the tower MAY prepare the command and a rotation checklist and
  SHALL NOT run it.
  *(Cites: D-8; release-checklist (Sources).)*
- **REQ-F1.5** Main, a protected branch, and a spec branch SHALL never be
  rewritten by any tier under any value. The protected set SHALL be the
  union of a core floor no layer can remove (`main`, `master`, and the
  `planwright/*/spec` pattern) and the additions a `protected_branches` knob
  carries, a space-separated single-line value of branch names or glob
  patterns matched against the branch name with `refs/heads/` stripped, as
  the tower queue normalizes today, `*` never spanning `/`; every guard that
  needs the set SHALL read it locally and never query the host at guard
  time. A malformed `protected_branches` value at any layer is a read
  failure: the guard SHALL deny the act (REQ-G1.4), never fall to the floor
  alone.
  *(Cites: D-2, D-8, D-9; kickoff §3 REQ-F (2026-09-22); kickoff sign-off
  lens pass (2026-09-22).)*

## REQ-G — Guards and profiles

- **REQ-G1.1** One shared fixture list of reserved-control spellings — merge
  in every form including `git pull`, the draft→ready flip and its undo,
  every force-push and refspec form reaching a protected ref, amend, squash,
  fixup, rebase, and the MCP equivalents — SHALL be tested against every
  guard copy and deny profile the repository ships; the cross-copy test is
  the enumeration, and a copy the test does not drive is a defect. Each
  fixture line SHALL carry the spelling, its act, the tier, the policy value,
  and the expected verdict per copy (deny, defer, or outside that copy's
  jurisdiction, since an allow-only copy defers what it does not recognise):
  floor lines expect deny from every copy in jurisdiction and from both
  profiles, including the `master` and spec-branch forms; policy lines
  expect the verdict the resolved value yields. The list SHALL also carry
  the `gh api` spellings of REQ-G1.7 and REQ-G1.8: the classified acts, the
  forms the policy guard cannot read, and readable requests outside those
  acts, each expecting `prompt` from both profiles.
  *(Cites: D-9; obs:518be7dd; kickoff §3 REQ-G (2026-09-22); kickoff sign-off
  lens pass (2026-09-22).)* *(Amended at kickoff amendment 2026-10-01: the `gh api` spellings.)*
  **Superseded-by: REQ-G1.10** (2026-11-04) — a third profile, and the
  kickoff tier's exception for a plain push of its own spec branch.
- **REQ-G1.2** Enforcement SHALL follow the resolved policy for the tier: a
  profile SHALL NOT deny an act the resolved policy permits for that tier, a
  deny-emitting guard SHALL refuse an act the policy forbids, and a policy
  that cannot be resolved SHALL enforce as its strictest value (for
  `protected_branches`, denying the act). The REQ-D1.4 helper's own flip is
  exempt from the flip deny under every value, and an attended session with
  no tier profile is outside the policy guard's jurisdiction (it defers).
  *(Cites: D-9; kickoff sign-off lens pass (2026-09-22).)*
- **REQ-G1.3** Acts no policy value can permit SHALL stay in the deny
  profiles as the floor, effective whatever a guard emits, where a profile
  can express them: a merge or rewrite of main, `master`, a protected or
  spec branch on every spelling, the direct PR-merge spellings, force-push,
  and the MCP names. The floor entries a profile cannot express — an agent
  PR merge outside a policy class, a rewrite of a pushed commit outside
  REQ-F1.2 — SHALL be guard-only, and the sanctioned helpers behind them
  SHALL re-resolve the policy and fail closed internally, as their own last
  line. The `gh api` spellings of the floor acts (REQ-G1.7) are guard-only
  too, since a profile glob sees text and cannot read the request; the
  policy-guard suite pins them.
  *(Cites: D-9; worker-permission-ergonomics D-1 (Sources); kickoff sign-off
  lens pass (2026-09-22).)* *(Amended at kickoff amendment 2026-10-01: the `gh api` spellings.)*
- **REQ-G1.4** Every guard that reads a policy SHALL do so deterministically,
  within a wall-clock bound, with no model in the decision path, and SHALL
  fail closed when the read fails. It SHALL classify the intercepted command
  before reading any knob, defer with no read outside its jurisdiction, and
  read only the knob its matched act needs.
  *(Cites: D-9; merge-currency-guard REQ-C1.2, REQ-C1.3 (Sources); kickoff
  sign-off lens pass (2026-09-22).)*
- **REQ-G1.5** Every allowance this bundle grants to a tier SHALL be wired
  through that tier's settings profile and hook set, and the wiring tests
  SHALL pin it.
  *(Cites: D-9.)*
- **REQ-G1.6** Every script this bundle adds that echoes spec text, paths,
  branch names, or host output SHALL source `scripts/echo-safety.sh` and
  validate identifiers against their grammar before use, per the
  security-posture echo discipline.
  *(Cites: D-9; kickoff sign-off lens pass (2026-09-22).)*
- **REQ-G1.7** Within its jurisdiction the policy guard SHALL classify a
  `gh api` request by the act it performs, matching the act's names in any
  field of the request whatever the endpoint, and SHALL deny it at every
  tier under every value with no knob read when it is a ready flip
  (`markPullRequestReadyForReview`), its undo (`convertPullRequestToDraft`),
  a PR merge (`mergePullRequest`, `enablePullRequestAutoMerge`,
  `enqueuePullRequest`, or a write to a `pulls/<n>/merge` path), a base
  merge (`mergeBranch`, `updatePullRequestBranch`, a write to `merges` or to
  `pulls/<n>/update-branch`), or a forced ref update. A ref update or
  delete, a contents write, or a `createCommitOnBranch` whose target is in
  the protected set SHALL be denied reading only `protected_branches`. A
  policy that permits one of these acts permits its `gh pr` or `git`
  spelling or its helper, whose predicates the guards can check; the
  `gh api` spelling is never the permitted path.
  *(Cites: D-9; the operator's `gh api` request (Sources).)*
- **REQ-G1.8** Within its jurisdiction the policy guard SHALL deny, fail
  closed and before any knob read, a `gh api` request it cannot read, as
  D-9 defines readable: a field read from a file or stdin, an `--input`
  body, a non-literal endpoint, method, or `query` field on a write, a flag
  it cannot parse, a protected-ref target it cannot read, and a command
  whose raw text shows `gh` followed by `api` where the parse cannot place
  them as a simple command's verb (a wrapper, a full path, or a construct
  the tokenizer refuses). Every `gh api` segment of a compound command SHALL
  be classified and the strictest verdict SHALL win. A readable request
  outside the REQ-G1.7 acts SHALL defer, and the profiles SHALL keep
  `gh api` writes at the permission prompt. Review approvals and dismissals,
  branch-protection and ruleset changes, non-`gh` clients, and other MCP
  servers' GitHub tools are accepted residuals held at the permission
  prompt.
  *(Cites: D-9; the operator's `gh api` request (Sources).)*
- **REQ-G1.9** A relayed kickoff session, launched under the kickoff
  profile with a launch record naming one spec branch, SHALL be admitted by
  the policy guard, among pushes and PR writes, to exactly three acts: a
  plain push of that branch to the repository its spec root's posture
  names, opening that branch's PR in that repository as a draft, and the
  ready flip of that PR when `mark_spec_pr_ready_on_kickoff` resolves true.
  "That repository" SHALL mean a configured remote whose push URL is the
  posture's repository; a URL or path given in place of a remote name, a
  fork, and the program-running push options (`--receive-pack`, `--exec`)
  SHALL be denied. "That PR" SHALL mean the PR whose head is that branch
  in that repository, never a fork's same-named branch. The guard SHALL
  deny that session a force push in every spelling, a branch deletion, a
  rewrite of that branch, a non-draft PR creation, the flip when the knob
  resolves false, the flip of any other PR, a push of a tag or other
  non-branch ref, and a push of any other branch in any refspec position,
  and SHALL deny it every push when the launch record is absent,
  unreadable, names no branch matching `planwright/<spec>/spec`, or is not
  bound to the running session, or when the posture provides no push. The
  launch record SHALL be written before the session starts, outside every
  path that session can write by any tool, SHALL be bound to that one
  session, and SHALL be removed when the session retires, so a leftover
  record admits nothing. The kickoff profile SHALL keep every deny the
  worker profile carries except the profile's denies of a plain push whose
  destination is a spec branch, which become guard-only for that tier; it
  SHALL keep a deny for every spec-branch deletion spelling a profile can
  express; and it SHALL be a profile the REQ-G1.10 cross-copy test drives.
  The core protected floor (REQ-F1.5) SHALL stay unchanged for every other
  tier, mission control's included, and the admission SHALL grant no
  sign-off: the kickoff's sign-off stays a human gate.
  *(Cites: D-18; mission-control D-36 and REQ-I1.8 (Sources); the
  operator's relayed-kickoff decision (Sources); kickoff amendment lens
  pass (2026-11-04).)*
- **REQ-G1.10** (supersedes REQ-G1.1) One shared fixture list of
  reserved-control spellings — merge in every form including `git pull`,
  the draft→ready flip and its undo, every force-push and refspec form
  reaching a protected ref, amend, squash, fixup, rebase, and the MCP
  equivalents — SHALL be tested against every guard copy and deny profile
  the repository ships; the cross-copy test is the enumeration, and a copy
  the test does not drive is a defect. Each fixture line SHALL carry the
  spelling, its act, the tier, the policy value, and the expected verdict
  per copy (deny, defer, or outside that copy's jurisdiction, since an
  allow-only copy defers what it does not recognise): floor lines expect
  deny from every copy in jurisdiction and from every profile, including
  the `master` and spec-branch forms, with one exception: a plain push of a
  spec branch is a floor line for every tier but the kickoff tier, whose
  profile defers it and whose policy-guard lines expect the REQ-G1.9
  verdicts (admitted for the launch record's branch, denied for any other).
  Policy lines expect the verdict the resolved value yields. The list SHALL
  also carry the `gh api` spellings of REQ-G1.7 and REQ-G1.8: the
  classified acts, the forms the policy guard cannot read, and readable
  requests outside those acts, each expecting `prompt` from every profile.
  *(Cites: D-9, D-18; obs:518be7dd; kickoff §3 REQ-G (2026-09-22); kickoff
  amendment lens pass (2026-11-04).)*

## REQ-H — Prose surfaces

- **REQ-H1.1** Every skill section stating invariants SHALL be split by rule
  kind per REQ-A1.5 and SHALL cite the doctrine source for the list; the
  change SHALL be word-neutral or net-negative on every guarded instruction
  surface as `scripts/check-instructions.sh` measures it.
  *(Cites: D-10; issue planwright#385; instruction-headroom (Sources).)*
- **REQ-H1.2** Every doc surface that restates the list SHALL agree with
  the doctrine source. Retired phrasings SHALL be screened in two ways: a
  short phrase enters the purged-identifier seed (which commits hashes,
  never a readable enumeration, and whose tree-wide scan makes any frozen
  record carrying the phrase verbatim a precondition to check before
  seeding), and a sentence-length phrasing is refused by a dedicated grep
  screen over `doctrine/`, `skills/`, and `docs/` with the historical
  surfaces (`specs/`, the changelog, the observations log) excluded.
  *(Cites: D-10; guard-coverage (Sources); kickoff sign-off lens pass
  (2026-09-22).)*
- **REQ-H1.3** Every knob this bundle adds SHALL have a row in the options
  reference and a commented default in the config defaults, per the existing
  options check. The `ready_flip_policy` default SHALL be carried as a
  `BREAKING CHANGE:` footer on the commit that lands the knob, which the
  release tooling renders into the changelog.
  *(Cites: D-10; bootstrap REQ-K1.8 (Sources); kickoff sign-off lens pass
  (2026-09-22).)*
- **REQ-H1.4** Every REQ or D record in another bundle that still states a
  rule this bundle changes SHALL carry a bold, dated supersede pointer, its
  body unedited: `**Superseded-by: REQ-<id> (human-gates)** (<date>)` on a
  requirement, `**Superseded-by: human-gates D-<n>** (<date>)` on a
  decision, scoped to the changed clause where only part of the record
  changes; each pointed bundle SHALL gain a dated changelog entry naming its
  pointed records. The set SHALL be settled by a survey recorded in the
  sweep's PR (record, replacing id, full or scoped, bundle live or Done). A
  pointer into a bundle whose derived status is Ready or Active when the
  sweep runs SHALL NOT land from the sweep: it SHALL be recorded as a gated
  bullet under this bundle's `## Deferred` naming the pointer lines and the
  `/spec-kickoff` amendment to run on that bundle, so no live bundle's
  anchor changes.
  *(Cites: D-10, D-17; planwright#506 review decisions (Sources).)*

## REQ-I — Automatic merge classes

- **REQ-I1.1** An `auto_merge_classes` knob SHALL resolve through the
  four-layer overlay as a space-separated single-line list of class names
  drawn only from the classes core defines (REQ-I1.9 to REQ-I1.16). The
  shipped default SHALL be empty, so no adopter's behaviour changes until
  they name a class. A name core does not define, or a value that does not
  parse, SHALL make a repo-tracked value fail the resolver, with every
  reader merging nothing; an adopter or machine-local value of that kind
  SHALL degrade to the empty list with a warning. The knob SHALL be read
  independently of `merge_policy`.
  *(Cites: D-20; `customization-boundary` (Sources); the operator's
  unattended-work request (Sources).)*
- **REQ-I1.2** The classes and their predicates SHALL be defined in core.
  A layer MAY narrow a class through that class's own knobs and SHALL NOT
  define a class, add a predicate that widens one, or remove a predicate.
  Adding a class SHALL be a spec amendment whose kickoff applies the
  REQ-A1.7 class test.
  *(Cites: D-19, D-20.)*
- **REQ-I1.3** A PR SHALL be merged by its class only when every condition
  below holds, each evaluated against the PR's current head immediately
  before the merge, with any condition unmet or unreadable meaning no
  merge: every required check on that head completed successfully, a
  queued, pending, or missing required check counting as unmet; the host
  reports the PR `MERGEABLE`, an `UNKNOWN` that persists after one
  re-query counting as unmet; every changed path lies inside the class's
  allow-list and outside the REQ-D1.3 hard-disqualifier zone, the class's
  own named exception excepted; the PR's author is the one the class
  expects, and its head repository is the base repository; the class's
  review cadence (REQ-I1.8) ran on that head; no commit in `base..head`
  carries a `Planwright-Sign-Off` trailer or a legacy suffix; no change
  touches a file that configures planwright's merge behaviour (the
  repo-tracked config and the core defaults); the PR is not itself a
  revert; it carries no hold label, no review requesting changes, and no
  unresolved review thread; a PR on a task branch has no live
  Awaiting-input segment other than a parking lead, read from the fetched
  base ref; and the kill switch is off. The helper SHALL re-confirm the
  head SHA, the base ref OID, and the kill switch immediately before the
  merge call and refuse on any of them having moved.
  *(Cites: D-20, D-21; REQ-D1.4; the operator's unattended-work request
  (Sources).)*
- **REQ-I1.4** A class merge SHALL run only through
  `scripts/merge-admitted.sh` in a class mode that re-resolves
  `auto_merge_classes` and the kill switch itself and fails closed, as a
  normal merge through the host's merge call with the method
  `merge_class_strategy` resolves, never with an administrator override,
  a force, or a bypass of the host's branch protection. A class PR still
  in draft SHALL be flipped ready through the REQ-C1.2 helper first. The
  direct PR-merge spellings SHALL stay denied to every agent session.
  *(Cites: D-20; REQ-D1.4, REQ-D1.5.)*
- **REQ-I1.5** The session that calls the helper in class mode SHALL be a
  mission-control session, or the skill that owns a task branch at its
  terminal step, under a tier whose policy guard admits the helper only
  while `auto_merge_classes` is non-empty and the kill switch is off. This
  bundle SHALL state that floor; mission control's own allowance, its
  profile, and the amendment of its never-merge requirement SHALL be a
  routed mission-control follow-on, and no class merge SHALL run from
  mission control before that follow-on lands.
  *(Cites: D-20; mission-control REQ-I1.1 (Sources).)*
- **REQ-I1.6** Every class merge SHALL leave, before the merge call, a
  record comment on the PR naming the class, each condition with its
  evidence, the head SHA, the base ref OID, and the undo command, and SHALL
  append one line to a machine-local automatic-merge ledger naming the
  repository, the PR, the class, the head SHA, the merge commit once it
  exists, and the time. A record or ledger write that fails SHALL abort the
  merge; a merge call that fails after the record SHALL append a follow-up
  comment naming the failure. The ledger SHALL live outside every
  repository and carry no secret.
  *(Cites: D-21; REQ-D1.4.)*
- **REQ-I1.7** One command SHALL undo a class merge by opening a revert PR
  of its merge commit as a draft, naming the original PR and its record,
  and the revert PR SHALL never be admitted by any class. For a release,
  the undo SHALL be stated as a revert plus the next release, the published
  tag and release staying as they are.
  *(Cites: D-21.)*
- **REQ-I1.8** An `auto_merge_halt` knob SHALL stop every class when any
  layer sets it true, whatever the other layers say, and a value that
  cannot be read SHALL count as true. The helper SHALL read it before
  evaluating and again immediately before the merge call. Each class SHALL
  carry a core minimum review cadence, evidenced by a step record naming
  the PR's current head: none beyond the class predicates for release,
  dependency, observation-carry, bookkeeping, and regeneration PRs; the
  repository's convergence review for test-only and documentation-only
  PRs; and that review plus the post-PR automated reviewer, where one is
  configured, with no open finding, for performance PRs. A layer MAY add
  steps to a class's cadence and SHALL NOT remove one.
  *(Cites: D-21; the operator's unattended-work request (Sources).)*
- **REQ-I1.9** The `release` class SHALL admit a PR only when: its head
  branch is the release tool's branch for the base; its author and every
  commit's author is a login in `auto_merge_release_authors` (bot accounts
  only, default `github-actions[bot]`); it changes only the file
  `version_file` names, the changelog, and the release tool's manifest, and
  the version file's diff changes only the version value; the proposed
  version is valid SemVer, greater than the latest release tag, and not yet
  tagged; and an armed release watcher for this PR's head has passed its
  pre-validation, including a non-interactive probe that the tag can be
  signed as `require_signed_tags` demands. Its outward effect, the publish,
  SHALL be named, and the merge SHALL be followed by the existing armed
  publish flow; a publish that fails SHALL be reported to the operator as a
  failure, with the untagged-window lock holding other merges as it does
  today. Whether a release whose changes themselves merged with no human
  act may still merge by this class SHALL be decided at the extension's
  kickoff.
  *(Cites: D-23; autopilot-reflex D-12 (Sources); the operator's
  unattended-work request (Sources).)*
- **REQ-I1.10** The `dependency` class SHALL admit a PR only when its
  author and every commit's author is a login in
  `auto_merge_dependency_authors` (bot accounts only, default empty); it
  changes only dependency manifests and lockfiles matched by a core list
  plus the additions `auto_merge_dependency_paths` carries, the class's one
  exception to the hard-disqualifier zone being lockfiles; it changes no CI
  workflow, hook, or other zone path; and every version change it makes is
  a patch or minor update determined from the changed lines, an update
  whose type cannot be determined counting as major. A major update SHALL
  never be admitted.
  *(Cites: D-22; research: GitHub Dependabot automation; research:
  Renovate automerge (Sources).)*
- **REQ-I1.11** The `test-only` class SHALL admit a PR only when every
  changed path matches the test globs (a core list plus
  `auto_merge_test_paths`), no test file is deleted or renamed out of
  those globs, the reserved-control fixture and every other zone path are
  untouched, and the full required check suite is green on the head.
  *(Cites: D-21; the operator's test and performance addition (Sources).)*
- **REQ-I1.12** The `performance` class SHALL admit a PR only when no path
  matching the test globs changes, the required check suite is green on
  the head, and the PR body carries a measurement block naming the
  command, the before and after figures, and an after figure better than
  the before; a missing or unparseable block counts as unmet.
  *(Cites: D-21; the operator's test and performance addition (Sources).)*
- **REQ-I1.13** The `observation-carry` class SHALL admit a PR only when
  every change adds an observation fragment or moves one between the
  accumulator's live and archive directories, no fragment's content
  changes in the move, and nothing outside the accumulator changes.
  *(Cites: D-24; observation-PRs-skip-review practice (Sources).)*
- **REQ-I1.14** The `bookkeeping` class SHALL admit a PR only when its
  whole diff removes reference bullets from the `## Awaiting input`
  sections of spec `tasks.md` files, and every task a removed bullet names
  derives Completed on the base.
  *(Cites: D-24; the merged-PR survey (Sources).)*
- **REQ-I1.15** The `docs-only` class SHALL admit a PR only when every
  changed path matches the documentation globs (a core list plus
  `auto_merge_docs_paths`) and none is doctrine, a skill, an agent
  instruction file, or another file the framework reads as behaviour.
  *(Cites: D-24; the merged-PR survey (Sources).)*
- **REQ-I1.16** The `regeneration` class SHALL admit a PR only when the
  command `auto_merge_regen_command` names, read from the base and never
  from the head, run in a clean scratch checkout of the base, reproduces
  the head's tree exactly. An empty or unreadable command SHALL admit
  nothing.
  *(Cites: D-24; the merged-PR survey (Sources).)*
- **REQ-I1.17** Every knob this extension adds SHALL have an options
  reference row and a commented default; the human-gates doctrine SHALL
  carry the class test, a row per class naming its kind as a policy with
  its knob and default, and the kill switch; and the routed follow-ons
  (mission control's caller and its never-merge requirement, the operator's
  dotfiles line) SHALL each carry a gated record in this bundle.
  *(Cites: D-19, D-20; REQ-A1.3, REQ-H1.3.)*

## Changelog

- 2026-09-22 — Draft bundle elicited by `/spec-draft` from the invocation
  text, the core observation set, and issues planwright#379, #384, #385,
  #388.
- 2026-09-22 — Kickoff walkthrough and sign-off lens pass: the knob set
  grew (`merge_class_strategy`, `protected_branches`, `worker_base_merge`,
  `unpushed_rewrite` added; `worker_merge_conflicts` renamed
  `worker_merge_conflict_policy`; the flip value `agent` renamed
  `unit-owner`; Task 4 is the enumeration); REQ-D1.8 minted for the merge
  strategy and REQ-G1.6 for the echo discipline; the parking-segment,
  record-as-intent, base-ref read, rejected-trailer, and jurisdiction rules
  added; the details are in `kickoff-brief.md`.
- 2026-09-28 — Amendment from the planwright#506 review decisions:
  REQ-B1.10 minted for legacy checklist ids, REQ-D1.9 for task-branch-only
  class admission (which excludes release PRs) and the raw sign-off scan,
  REQ-H1.4 for cross-bundle supersede pointers; Tasks 2, 9, 11, and 12 grew
  to carry them; the details are in `kickoff-brief.md`'s amendment log.
- 2026-10-01 — Amendment from the operator's `gh api` request: REQ-G1.7
  minted for the `gh api` acts the policy guard denies, REQ-G1.8 for the
  fail-closed read of a request it cannot read and the named residuals;
  REQ-G1.1 and REQ-G1.3 extended to the `gh api` fixture lines and
  guard-only floor; D-9, test-spec, and Tasks 6, 8, and 12 grew to carry
  them, and tower-front-door's Deferred "Tower floor bypass paths" bullet
  was annotated; the details are in `kickoff-brief.md`'s amendment log.
- 2026-11-04 — Extension by `/spec-draft --extend`, routed from
  mission-control Task 31: REQ-A1.6 minted for the spec-branch push row,
  REQ-C1.9 superseding REQ-C1.5 so the spec-PR flip may run in a relayed
  kickoff session, REQ-G1.9 for that session's narrow admission; D-18 and
  Task 13 added, with the in-scope and out-of-scope bullets, two Sources
  entries, and the decision-domains walk extended. The bundle reopens
  Ready→Draft for a scoped kickoff.
- 2026-11-04 — Scoped kickoff of that extension: its lens pass tightened
  REQ-G1.9 (the remote, the PR, refspec positions, tags, the knob-false
  flip, the record's session binding and removal, the profile's deletion
  denies), minted REQ-G1.10 superseding REQ-G1.1 for the kickoff profile's
  fixture exception, added the mission-control flip clause to REQ-C1.9,
  repointed the pending supersede pointers to REQ-C1.9, and routed the
  missing kickoff-tier cases to mission-control Task 19 as a Deferred item;
  the details are in `kickoff-brief.md`'s amendment log.
- 2026-11-05 — Extension by `/spec-draft --extend` from the operator's
  unattended-work request: REQ-A1.7 (the class test) and REQ-A1.8 (enabling
  a class as standing authorization, and the gates no class changes)
  minted; REQ-D1.10 supersedes REQ-D1.9 so non-task PRs may merge through
  an enabled class; REQ-I group minted for the automatic merge classes,
  their knobs, conditions, helper mode, record, undo, kill switch, and the
  eight core classes; D-19 to D-24 added, D-2 gains a scoped pointer to
  D-19 and D-15 is superseded by D-20; Tasks 14 to 18 and three Deferred
  bullets added. The bundle reopens Ready→Draft for a scoped kickoff, as
  the 2026-11-04 extension did.

## Sources

- **The drafting invocation (2026-09-21).** The operator's framing: the
  invariants were set when agents ran without harnesses; re-evaluate what
  stays strict, what changes, what becomes configurable. Pinned altitude
  claim: this is a re-decision of the reserved-control doctrine, not a knob.
- **obs:77e452b4** — operator decision 2026-09-02: the sign-off act is the
  merge, not the draft→ready flip.
- **obs:2bba6bcf** — the subject-marker strategy is repo-configuration
  dependent; move the signal to a trailer.
- **obs:2e9b7741** — the pending-sign-off mechanism is illegible at the
  moment of decision.
- **obs:94b217c4** — one commit per finding conflicts with green-commit
  ordering.
- **obs:11c3af76** — an attended tower asked about Needs-sign-off items the
  policy says to apply.
- **obs:02396e39** — requesting a reviewer un-drafted a PR with no flip call.
- **obs:518be7dd** — the reserved-control refusal is implemented in more
  than one place.
- **obs:5775c447** — the worker merge deny blocks the sanctioned base sync.
- **obs:332374a2** — a conflicting task branch cannot be resolved by the
  worker; widen or add a resolve mode.
- **obs:921b93c9** and **obs:75c25c5d** — cited, not consumed: a flip must
  land on a current, re-verified head.
- **issue planwright#379** — make the draft→ready flip a configurable policy;
  its research comment traces the invariant to its origin and finds the
  repo's later decisions contradict it.
- **issue planwright#384** — sign-off moves to the merge and is carried as a
  `Planwright-Sign-Off` trailer (operator-decided 2026-09-02).
- **issue planwright#385** — the never-push rule in `/polish` is a
  composition contract, not a trust restriction.
- **issue planwright#388** — a revert copies the subject marker and
  double-counts a rejected item.
- **The review-gauntlet seed note** (`specs/_pending/review-gauntlet.md`) —
  its third open question, task-PR-ready automation, is what REQ-C decides;
  its other questions stay with that note.
- **bootstrap D-26** and **bootstrap REQ-J1** — the rules superseded or
  carried forward.
- **merge-currency-guard D-9**, **REQ-A1.3**, **REQ-A1.4** — the flip guard
  is flipper-agnostic and who-flips is an overlay preference.
- **kickoff-lifecycle D-6** — the spec-PR flip precedent and its reasoning.
- **kickoff-verification** (`doctrine/kickoff-verification.md`) — the
  terminal ready-flip CI gate and its Awaiting-input re-entry.
- **worker-permission-ergonomics D-1** — the deny profile is the security
  floor; guards are allow-only.
- **merge-currency-guard REQ-C1.2** — no model in a guard's decision path;
  **REQ-C1.3** — positively identify a gated act before any costly call.
- **The autopilot-reflex gate list** (`doctrine/autopilot-reflex.md`, step
  1) — sign-off, merge, publish as the irreducible gates.
- **instruction-headroom** — the guarded instruction surfaces are saturated;
  prose changes must be word-neutral.
- **guard-coverage** — the purged-identifier list and its CI screen.
- **release-checklist** (`docs/release-checklist.md`) — the history purge is
  human-reserved.
- **The CI commit-range lint** (`.github/workflows/ci.yml`, the
  check-commit-msgs step over the PR range).
- **bootstrap REQ-K1.8** — every option has an options-reference row.
- **research: GitHub auto-merge docs** —
  <https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/automatically-merging-a-pull-request>:
  auto-merge merges when all required reviews and status checks pass; a
  person with write permission enables it.
- **research: GitHub merge queue** —
  <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue>.
- **research: GitHub required reviews** —
  <https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/approving-a-pull-request-with-required-reviews>:
  a PR author cannot approve their own PR; Copilot approvals never count
  toward required reviews.
- **research: agent GitHub identity** —
  <https://savas.me/2026/04/27/my-coding-agent-needed-its-own-github-identity/>:
  a GitHub App identity makes self-approval impossible and attribution
  clear; on a personal repo an App cannot open PRs, so a machine user is
  needed.
- **The repository's own ruleset (read 2026-09-22)** — zero required
  approving reviews, two required status checks, squash only, auto-merge
  enabled, PRs authored under the operator's login: the shared-identity
  case REQ-D1.7 keeps working.
- **research: Copilot agents card** —
  <https://docs.github.com/en/copilot/responsible-use/agents>: the agent
  cannot push to the default branch; human review before merging.
- **research: Ona low-risk auto-approval** —
  <https://ona.com/stories/auto-approving-low-risk-prs>: six mechanical
  exclusion criteria; the agent approves, a human always merges as the
  auditable event; engineers cannot self-classify.
- **planwright#506 review decisions** —
  <https://github.com/inkatze/planwright/pull/506#issuecomment-5875255206>:
  the operator's 2026-09-28 answers on cross-bundle pointers, release PRs
  under a policy class, and legacy checklist ids, walked in this bundle's
  2026-09-28 kickoff amendment.
- **the operator's `gh api` request** — no external locator (given in the
  kickoff amendment session): the operator's 2026-09-30 request that the
  policy guard refuse a `gh api` ready flip, undo, or merge per tier and
  policy and deny any `gh api` request it cannot read, walked in this
  bundle's 2026-10-01 kickoff amendment; the fixture lines pinning those
  spellings landed in <https://github.com/inkatze/planwright/pull/529>.
- **mission-control D-36, REQ-I1.8, and Tasks 19 and 31**
  (`specs/mission-control/`, signed off in
  <https://github.com/inkatze/planwright/pull/827>): the kickoff permission
  profile for relayed kickoffs, the task that builds it, and the routed
  amendment of this bundle it waits on. Its REQ-I1.2 is the
  mission-control tier's flip policy the doctrine's `unit-owner` row
  names.
- **the operator's relayed-kickoff decision** — no external locator: the
  operator chose on 2026-11-04, in the mission-control extension's kickoff,
  that a relayed kickoff publishes its own result under a kickoff profile
  rather than mission control or the operator pushing it, and chose the same
  day to draft this amendment now.
- **the operator's unattended-work request** — no external locator: the
  operator's words of 2026-11-05, relayed by mission control: "I think we
  are ready for safe automated work to be done automatically. You can even
  get pre-approvals or whatever and only stop if you can actually mess
  something up. We can start with super safe ones like dependencies and
  releases". Pinned altitude claim: a rule for which acts run unattended
  (verified and reversible runs, possible harm stops), so doctrine before
  mechanism (D-19).
- **the operator's test and performance addition** — no external locator,
  the same day: "Performance improvements, test improvements/broadening
  could be fine too", and "I might be missing other good candidates now
  that I think about it", asking for a survey of merged PRs and a
  multi-select of candidate classes at kickoff.
- **the merged-PR survey** — the repository's most recent merged PRs read
  on 2026-11-05 through the host CLI: release PRs touch only the version
  file, the release manifest, and the changelog, authored by the CI bot;
  stale Awaiting-input cleanups touch only spec `tasks.md` sections;
  observation carries touch only the accumulator; secret-scan allowlist
  chores and guard-script changes recur and stay outside every class.
- **observation-PRs-skip-review practice** — no external locator: the
  observation-carry PR is merged with `check:obs` as its gate and no review
  pass, an operator practice since 2026-10.
- **mission-control REQ-I1.1** (`specs/mission-control/`): "Mission control
  SHALL never merge", the requirement the routed follow-on amends.
- **autopilot-reflex D-12** — the armed release watcher (`release-arm.sh`)
  that pre-validates a release PR and runs the signed publish on the
  observed merge.
- **`customization-boundary`** (`doctrine/customization-boundary.md`) — a
  capability lands in core as an opt-in knob whose default preserves
  today's behaviour; the value stays in an overlay.
- **research: GitHub Dependabot automation** —
  <https://docs.github.com/en/code-security/dependabot/working-with-dependabot/automating-dependabot-with-github-actions>:
  check the PR author's login, filter on update type (patch), require
  status checks through branch protection or auto-merge proceeds untested.
- **research: Dependabot ecosystems** —
  <https://docs.github.com/en/enterprise-server@3.17/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories>:
  no mise ecosystem is listed.
- **research: Renovate mise manager** —
  <https://docs.renovatebot.com/modules/manager/mise/>: Renovate updates
  tool versions in `mise.toml`.
- **research: homu** — <https://github.com/rust-lang/homu>: a human's `r+`
  authorizes, the bot merges after testing against the current base.
- **research: Mergify queue rules** —
  <https://docs.mergify.com/merge-queue/rules/>: queue conditions versus
  merge conditions as declared rules.
- **research: Renovate automerge** —
  <https://www.systemshardening.com/articles/cicd/renovate-dependabot-security/>:
  a declared class (update type, CI, release age) merges itself.
- **research: Claude Code in Actions containment** —
  <https://readysolutions.ai/blog/2026-05-27-claude-code-github-actions-ci-agents/>:
  a merge gate the agent does not own.
