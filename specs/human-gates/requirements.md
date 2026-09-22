# Human gates — Requirements

**Status:** Draft
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
- Acting on a non-Ready spec and auto-chaining `/orchestrate` into
  `/spec-kickoff`: both carry forward unchanged.
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
  it does not change (never act on a non-Ready spec, never auto-chain
  `/orchestrate` into `/spec-kickoff`, never rewrite main) SHALL carry
  forward with its citation intact.
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
  and SHALL NOT be counted as a new item.
  *(Cites: D-3; issue planwright#388.)*
- **REQ-B1.4** `scripts/check-commit-msgs.sh --marker subject` SHALL be
  retired. `--marker title` SHALL be kept for one release, broadened to
  reject the legacy bracket or a bare `Planwright-Sign-Off:` line in a PR
  title, and its removal SHALL be a gated deferral.
  *(Cites: D-3; issue planwright#384.)*
- **REQ-B1.5** The generated pending-sign-off section SHALL state, inside
  the section itself, which act approves the listed items and that an item is
  rejected by reverting its commit before that act; the checkbox SHALL NOT
  read as the approval control.
  *(Cites: D-13; obs:2e9b7741.)*
- **REQ-B1.6** The one-commit-per-finding discipline SHALL yield to
  green-commit ordering: where findings are not file-isolable or share a
  regression test, one commit carrying every affected finding's trailer with a
  per-item revert recipe in the checklist SHALL be conforming, and the
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
  four-layer overlay with the values `human` (only a human flips) and `agent`
  (the skill executing a unit flips its own PR once REQ-C1.2 holds). The
  shipped default SHALL be `agent`. A malformed repo-tracked value SHALL fail
  closed to `human`.
  *(Cites: D-4; issue planwright#379; merge-currency-guard D-9 (Sources).)*
- **REQ-C1.2** An agent flip SHALL fire only when every precondition holds on
  the current head: the ready-guard's currency and mergeability check passes;
  the head SHA's check rollup is a positive green within a bounded wait; the
  configured review sequence converged on that head; and the unit has no live
  Awaiting-input bullet. The check SHALL be deterministic, with no model in
  the decision path.
  *(Cites: D-5; obs:921b93c9; obs:75c25c5d; kickoff-verification (Sources).)*
- **REQ-C1.3** An agent flip SHALL leave a record on the PR before the flip
  naming the policy value, the head SHA, and the evidence for each
  precondition. A flip whose record write fails SHALL NOT proceed.
  *(Cites: D-5.)*
- **REQ-C1.4** When any precondition fails, the PR SHALL stay draft and the
  pending flip SHALL be recorded under the spec's `## Awaiting input` naming
  the failed precondition, the same re-entry path `/spec-kickoff` uses.
  *(Cites: D-5; kickoff-verification (Sources).)*
- **REQ-C1.5** The flip under `agent` SHALL be performed by the skill that
  owns the unit's branch; the orchestrator and tower profiles SHALL keep
  their flip deny regardless of the policy value.
  *(Cites: D-4, D-9.)*
- **REQ-C1.6** `mark_spec_pr_ready_on_kickoff` SHALL be documented as the
  spec-PR instance of the same policy class and SHALL keep its own knob; this
  bundle SHALL NOT change its default.
  *(Cites: D-4; kickoff-lifecycle D-6 (Sources).)*
- **REQ-C1.7** No planwright surface that requests a reviewer on a draft PR
  SHALL leave the PR un-drafted as a side effect: the surface SHALL verify
  the draft state after the request and re-draft it, or use a transport
  without the side effect. The mechanism SHALL be verified against gh and
  GitHub documentation before the fix is chosen.
  *(Cites: D-11; obs:02396e39.)*
- **REQ-C1.8** `gh pr ready --undo` SHALL be allowed to an agent only as the
  REQ-C1.7 corrective, through a helper the guards recognise, and SHALL stay
  denied in every other spelling.
  *(Cites: D-11.)*

## REQ-D — Merge policy

- **REQ-D1.1** A `merge_policy` knob SHALL resolve through the four-layer
  overlay with the values `human` (a human authorizes and executes),
  `on-approval` (a human authorizes per PR; GitHub executes once required
  checks pass), and `policy-class` (a PR inside a declared class merges with
  no per-PR human act; a PR outside it falls to `on-approval`). The shipped
  default SHALL be `human`. A malformed or unresolvable value SHALL fail
  closed to `human`.
  *(Cites: D-6; research: GitHub auto-merge docs; research: Ona low-risk
  auto-approval; research: homu.)*
- **REQ-D1.2** Under `on-approval`, the approval act SHALL be the human
  enabling GitHub auto-merge on the PR; where REQ-D1.7 detects a distinct
  agent identity, an approving review by the human with auto-merge enabled
  SHALL be the same act. Agent sessions SHALL stay denied every merge
  spelling under this value, so enforcement SHALL never depend on which
  token acted.
  *(Cites: D-6, D-14; research: GitHub required reviews.)*
- **REQ-D1.7** planwright SHALL detect whether the agent session's GitHub
  login differs from the PR author's, SHALL recommend a distinct agent
  identity in its docs, and SHALL NOT require one: every policy value SHALL
  work under a shared identity through client-side enforcement, and a
  detected split SHALL only add the server-verified approval path.
  *(Cites: D-14; research: agent GitHub identity; research: GitHub required
  reviews.)*
- **REQ-D1.3** A policy class SHALL be declared by mechanical predicates
  only, evaluated by a deterministic script with no model in the decision
  path. The predicates SHALL always include: no `Planwright-Sign-Off` trailer
  in `base..head`; no path in a hard-disqualifier zone as
  `doctrine/finding-categorization.md` names them; no live Awaiting-input
  bullet for the unit; the REQ-C1.2 preconditions on the head; and the
  adopter's own bounds (a size cap, a path exclusion list). A PR failing any
  predicate SHALL fall to `on-approval`.
  *(Cites: D-6; research: Ona low-risk auto-approval; research: Renovate
  automerge.)*
- **REQ-D1.4** An agent merge under `policy-class` SHALL leave a record on
  the PR naming the policy value and each predicate with its evidence before
  merging, SHALL use the repository's sanctioned merge strategy, and SHALL run
  through one helper the guards recognise. A record write that fails SHALL
  abort the merge.
  *(Cites: D-6, D-9.)*
- **REQ-D1.5** Under `human` and `on-approval`, no agent session at any tier
  SHALL hold a merge allowance; under `policy-class`, only the helper of
  REQ-D1.4 SHALL be allowed, and only for a PR its predicates admit. The
  direct merge spellings SHALL stay denied to agent sessions under every
  value; the helper is the sole sanctioned path.
  *(Cites: D-6, D-9.)*
- **REQ-D1.6** The never-auto-merge floor SHALL be restated as: no agent
  merges outside a policy the human configured, and no value exists under
  which an agent merges a PR carrying a sign-off item. Every doc and doctrine
  passage stating the floor SHALL cite the policy rather than restate an
  unconditional never.
  *(Cites: D-2, D-6, D-10.)*

## REQ-E — Worker base merge

- **REQ-E1.1** A worker SHALL be able to merge the PR base into the branch it
  owns, and SHALL NOT merge into main, a protected branch, a spec branch, or
  another unit's branch. The allowance SHALL be stated as the act and
  enforced on every spelling that performs it, `git pull` included.
  *(Cites: D-7; obs:5775c447; obs:332374a2.)*
- **REQ-E1.2** A `worker_merge_conflicts` knob SHALL resolve through the
  overlay with the values `halt` (a conflicting merge is aborted, the tree
  left clean, and the unit parked under `## Awaiting input` naming the
  conflicting paths) and `resolve` (the worker resolves, commits the
  resolution, and flags that commit in the PR body for review). The shipped
  default SHALL be `halt`.
  *(Cites: D-7; obs:332374a2.)*
- **REQ-E1.3** The orchestrator and tower profiles SHALL keep their merge
  deny; the local-main fast-forward SHALL remain the only sanctioned
  mutation of a local main.
  *(Cites: D-7, D-9.)*

## REQ-F — History rewriting

- **REQ-F1.1** A commit that no remote ref contains, on the branch the
  session owns, SHALL be permitted to be amended, squashed, or rebased by
  default. The guard SHALL verify
  that no remote-tracking ref contains the commit before allowing the act; a
  commit any remote ref contains SHALL stay append-only.
  *(Cites: D-8.)*
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
  rewritten by any tier under any value.
  *(Cites: D-2, D-8.)*

## REQ-G — Guards and profiles

- **REQ-G1.1** One shared fixture list of reserved-control spellings — merge
  in every form including `git pull`, the draft→ready flip and its undo,
  every force-push and refspec form reaching a protected ref, amend, squash,
  fixup, rebase, and the MCP equivalents — SHALL be tested against every
  guard copy and deny profile the repository ships; the cross-copy test is
  the enumeration, and a copy the test does not drive is a defect.
  *(Cites: D-9; obs:518be7dd.)*
- **REQ-G1.2** Enforcement SHALL follow the resolved policy for the tier: a
  profile SHALL NOT deny an act the resolved policy permits for that tier, a
  deny-emitting guard SHALL refuse an act the policy forbids, and a policy
  that cannot be resolved SHALL enforce as its strictest value.
  *(Cites: D-9.)*
- **REQ-G1.3** Acts no policy value can permit — a merge or rewrite of main
  or a protected branch, an agent merge outside a policy class, a rewrite of
  a pushed commit outside REQ-F1.2 — SHALL stay in the deny profiles as the
  floor, effective whatever a guard emits.
  *(Cites: D-9; worker-permission-ergonomics D-1 (Sources).)*
- **REQ-G1.4** Every guard that reads a policy SHALL do so deterministically,
  within a wall-clock bound, with no model in the decision path, and SHALL
  fail closed when the read fails.
  *(Cites: D-9; merge-currency-guard REQ-C1.2 (Sources).)*
- **REQ-G1.5** Every allowance this bundle grants to a tier SHALL be wired
  through that tier's settings profile and hook set, and the wiring tests
  SHALL pin it.
  *(Cites: D-9.)*

## REQ-H — Prose surfaces

- **REQ-H1.1** Every skill section stating invariants SHALL be split by rule
  kind per REQ-A1.5 and SHALL cite the doctrine source for the list; the
  change SHALL be word-neutral or net-negative on every guarded instruction
  surface as `scripts/check-instructions.sh` measures it.
  *(Cites: D-10; issue planwright#385; instruction-headroom (Sources).)*
- **REQ-H1.2** Every doc surface that restates the list SHALL agree with
  the doctrine source, and every retired phrasing of the old rule SHALL enter
  the purged-identifier list so it cannot return; the purge screen is the
  enumeration of what may not come back.
  *(Cites: D-10; guard-coverage (Sources).)*
- **REQ-H1.3** Every knob this bundle adds SHALL have a row in the options
  reference and a commented default in the config defaults, per the existing
  options check.
  *(Cites: D-10; bootstrap REQ-K1.8 (Sources).)*

## Changelog

- 2026-09-22 — Draft bundle elicited by `/spec-draft` from the invocation
  text, the core observation set, and issues planwright#379, #384, #385,
  #388.

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
- **obs:518be7dd** — the reserved-control refusal is implemented three times.
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
- **merge-currency-guard REQ-C1.2** — no model in a guard's decision path.
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
