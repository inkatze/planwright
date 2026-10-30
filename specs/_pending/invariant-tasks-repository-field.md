# Seed brief: amend `invariant-tasks` (a per-task repository field)

Captured 2026-10-25 while carrying `mission-control` Task 12, which routes
this work here rather than absorbing it (mission-control D-22, REQ-H1.2):
the task block grammar and the derivation that reads it belong to
`invariant-tasks` and the meta-spec, not to the mission-control session.

Suggested invocation, from a fresh session in the planwright repo:

    /spec-draft --extend invariant-tasks

The bundle derives **Done**. Extend per the bundle's declared format
version; append new REQ/D-IDs and task ids, never renumber.

## The gap

A bundle whose tasks change code in more than one repository cannot be
executed. A task block names no repository, and the derivation engine
reads every task's state from the single work repository the resolver
picks, so a dependency merged in another repository reads as unmet and
every unit dispatches into the launch repository (obs:74a7f907). Splitting
the bundle per repository loses exactly the cross-repository dependency
edges, since there is no cross-bundle dependency syntax.

## What mission-control needs

- A task MAY name the repository its code lives in.
- Dependency state is read from the repository each dependency landed in.
- A fixture bundle with tasks in two repositories derives each
  dependency's state from its own repository.

## Questions for the drafter

- Is the field additive within format-version 2, or a version bump?
- What does the field hold: an alias, a path, a remote URL?
- What resolves the field to a local checkout, and what happens when it
  does not resolve on this machine?
- Where do holder-only tasks and tasks that touch no repository go?

## Companion amendment

`custom-spec-location`'s reverse registry (its own pending note,
`custom-spec-location-reverse-registry.md`) is the machine-local map a
session uses to find a work repository's checkout; the alias this field
holds is most naturally a key into it.
