# Human Gates

Which acts stay with the human, which are policies an adopter tunes, and which
are ownership contracts between skills. This is the one statement of that
list: every skill, profile, guard, and doc restates it by citing this doc, and
a copy that diverges from it is a defect.

Citations: human-gates REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5,
REQ-B1.1, REQ-C1.1, REQ-C1.5, REQ-C1.6, REQ-D1.1, REQ-D1.2, REQ-D1.4, REQ-D1.5,
REQ-D1.6, REQ-D1.7, REQ-E1.1, REQ-E1.2, REQ-F1.1, REQ-F1.2, REQ-F1.4, REQ-F1.5 ·
human-gates D-1, D-2, D-3, D-4, D-6, D-7, D-8, D-9, D-10, D-14 · supersedes
bootstrap D-26 (scoped), bootstrap REQ-J1.1, bootstrap REQ-J1.4.

## The gate test

An act is a **human gate** exactly when either arm holds:

- **Irreversible for other people.** It changes shared history or ships
  something.
- **The approval act.** It ends the framework's review contract.

An act meeting neither arm is not a gate. It is a **policy** (a knob with a
core default, set through the overlay like any other knob) or a
**composition contract** (which skill in a chain owns the act, never a
statement about trust). Every rule below names its kind; a rule whose kind
cannot be named does not ship.

## The list

| Act | Kind | Arm and scope, knob and default, or owner |
| --- | --- | --- |
| Authorizing a PR merge | Human gate | Approval arm, at every tier under every `merge_policy` value; the policy sets only how the human gives it |
| Signing off a Needs-sign-off finding | Human gate | Approval arm; given by the approval act below, never by the flip |
| Signing off a spec at kickoff | Human gate | Approval arm; no skill acts on a spec that is neither Ready nor Active, and `/orchestrate` never chains into `/spec-kickoff` |
| Publishing a release | Human gate | Irreversible arm; the release tooling automates up to it, never through it |
| Force-pushing a branch outside the protected set | Human gate | Irreversible arm; only on the operator's explicit request in the same turn, never from a standing decision, executed by the tower after naming the remote commits it drops |
| Purging a leaked secret from history | Human gate | Irreversible arm; human-run, the tower may prepare the command and a rotation checklist |
| Rewriting main, a protected branch, or a spec branch | Human gate | Irreversible arm; no tier under any value |
| Executing an authorized merge | Policy | `merge_policy`, default `human`; `on-approval` lets the host merge once the human enables auto-merge, `policy-class` admits a declared class |
| The draft→ready flip of a unit PR | Policy | `ready_flip_policy`, default `unit-owner`; `human` reserves it, except the merge helper's own flip of a PR its class admits |
| The draft→ready flip of a spec PR | Policy | `mark_spec_pr_ready_on_kickoff`, default `true` |
| Merging the PR base into the owned branch | Policy | `worker_base_merge`, default `allow`; conflicts by `worker_merge_conflict_policy`, default `halt` |
| Reshaping never-pushed commits on the owned unit branch | Policy | `unpushed_rewrite`, default `allow` |
| Branches protected beyond the core floor | Policy | `protected_branches`, default empty; it adds to `main`, `master`, and `planwright/*/spec`, never removes |
| Pushing the unit branch and opening its draft PR | Composition contract | `/execute-task`, or a standalone `/self-review`; `/polish` and every `--nested` review skill never push |
| Flipping under `unit-owner` | Composition contract | `/execute-task`'s convergence run, or the review skill it delegates its terminal step to; a standalone review run never flips |

## The floor

No agent merges outside a policy the human configured, and no value exists
under which an agent merges a PR carrying a sign-off item. The tower profile,
which the orchestrator tier runs under, keeps its flip, PR-merge, and
base-merge denies under every value. Pushed history stays append-only outside
the force-push and secret-purge rows of the list. A doc stating this floor
cites this section; it does not restate an unconditional never.

## The approval act

The human signs off every pending item on a PR by the act that lets it merge:
the merge itself under `merge_policy: human`; enabling auto-merge under
`on-approval` (or, where the agent's GitHub login differs from the PR
author's, an approving review with auto-merge enabled). A PR carrying a
sign-off item never enters a `policy-class`, so it always reaches one of
those two acts. The draft→ready flip approves nothing: it moves a PR in front
of reviewers and is one `gh pr ready --undo` from reversed. The checklist
mechanics live in [Gate Wiring](gate-wiring.md).

## Carried forward and superseded

bootstrap D-26 stays the origin of the reserved-control list, superseded by
this doc where the list changed; its unchanged rules are the "Signing off a
spec at kickoff" row. Its merge floor now reads as the floor section; its
rewrite rule as the force-push, secret-purge, main-rewrite, and never-pushed
rows; its all-drafts rule as the two flip rows.
