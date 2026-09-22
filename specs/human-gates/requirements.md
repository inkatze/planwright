# Human gates — Requirements

**Status:** Ready
**Last reviewed:** 2026-09-22
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
  spellings every guard copy must refuse.
- Every skill and doc surface restating the list from one doctrine source,
  with composition contracts labelled apart from trust rules.

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
  expect the verdict the resolved value yields.
  *(Cites: D-9; obs:518be7dd; kickoff §3 REQ-G (2026-09-22); kickoff sign-off
  lens pass (2026-09-22).)*
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
  line.
  *(Cites: D-9; worker-permission-ergonomics D-1 (Sources); kickoff sign-off
  lens pass (2026-09-22).)*
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
