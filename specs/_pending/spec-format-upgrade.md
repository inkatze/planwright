# Seed brief: an automated spec-format upgrade for older bundles

Captured 2026-10-29 at the `invariant-tasks` kickoff delta re-walkthrough
(per-task repositories, format-version 3), where the operator asked for
this to be seeded rather than built inside that extension.

Suggested invocation, from a fresh session in the planwright repo:

    /spec-draft

Fold-detection may route it to an extension of `invariant-tasks` or of the
meta-spec's own owner; follow its recommendation.

## The gap

`invariant-tasks` D-13 lands format-version 3 as version 2 plus one
optional task field, `Repository:`. A bundle declares version 3 only when a
task needs the field, and no migration ships with it. The only existing
upgrade path is `scripts/migrate-format-version.sh`, which performs the
v1→v2 conversion and nothing else. A bundle written at an older version
that later needs a newer version's capability has to be upgraded by hand,
and a signed bundle then also needs its changelog entry and re-anchor
written by hand.

## What the process would do

- Upgrade a bundle from the version it declares to a named newer version,
  chaining the per-version steps (v1→v2 is the existing mechanical
  conversion; v2→v3 is only the `Format-version:` bump, since the field is
  optional and nothing else changes).
- Stay mechanical or refuse, as the v1→v2 migration does.
- For a signed bundle, write the dated changelog entry and the
  machine-written re-anchor the expression-only lane allows, since a bump
  that adds no field changes no task-definition content.

## Questions for the drafter

- One script that chains versions, or one script per step behind a
  dispatcher?
- Is v2→v3 with no field worth automating on its own, or only as a step in
  a chain?
- Should `/spec-draft --extend` offer the upgrade when an extension needs
  a newer version's capability?
