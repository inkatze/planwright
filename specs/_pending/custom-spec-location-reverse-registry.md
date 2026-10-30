# Seed brief: amend `custom-spec-location` (the reverse registry and holder dispatch)

Captured 2026-10-25 while carrying `mission-control` Task 12, which routes
this work here rather than absorbing it (mission-control D-22, REQ-H1.3):
the mapping from a spec root back to its work repositories is
`custom-spec-location`'s deferred reverse registry, not a mission-control
mechanism.

Suggested invocation, from a fresh session in the planwright repo:

    /spec-draft --extend custom-spec-location

The bundle derives **Active** (its Task 4 is parked on a stale
Awaiting-input bullet), so extending it leaves the stored status alone; the
delta is signed through a `/spec-kickoff` delta re-walkthrough. Append new
REQ/D-IDs and task ids, never renumber.

## The gap

`custom-spec-location` lets a spec root live in a holder repository, but
every dispatching session has to start in the work repository that owns
the pointer. A session started in the holder resolves the holder itself as
the work repository, so it would derive state from the wrong repository and
dispatch into it. The bundle recorded this as a Deferred entry ("the
reverse registry", D-21) gated on "a session that starts in a holder
repository needs to dispatch execution". mission-control meets that gate:
its program runs from a holder and dispatches into several work
repositories (obs:74a7f907, obs:e1722435).

## What mission-control needs

- A machine-local map from a marker-bearing root back to the work
  repositories registered against it.
- A session started in a holder dispatches each unit into its work
  repository: worktree, branch, worker, pull request.
- A fixture in which the selector, run from a holder checkout, dispatches
  a unit into the right one of two work repositories.

## Questions for the drafter

- How do entries get into the registry, and how is a stale entry caught?
- What name does a repository go by, and is it the same on every machine?
- What happens when a holder bundle's tasks could go to more than one
  repository and the task does not say which?

## Companion amendment

`invariant-tasks`' per-task repository field (its own pending note,
`invariant-tasks-repository-field.md`) names a task's repository by alias;
the registry is what resolves that alias to a checkout.
