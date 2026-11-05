# Seed brief: pushing past a pre-push stage that fails for reasons unrelated to the diff

Captured 2026-11-04 during the worker-permission-ergonomics extension drafting, which routed
this here rather than absorbing it (its Out of scope names this note).

Suggested invocation, from a fresh session in the planwright repo:

    /spec-draft unrelated-pre-push-failure

Run fold-detection against `guard-coverage` (owns the hook-skip denies and the githooks
backstop), `human-gates` (owns the reserved-control list and the approval surface) and
`worker-permission-ergonomics` (owns the worker profile that carries the denies) before assuming
a new bundle.

## The problem

In a repository other than planwright, a pre-push stage failed across the whole repository for
reasons unrelated to any worker's change (a check broken on the base branch itself). Every push
was blocked, including documentation-only pushes, and the worker profile forbids skipping hooks
(`--no-verify` and the `core.hooksPath` spellings are denied), so the work sat until a person
pushed it by hand.

## What the operator asked for

Consider an operator-approvable path: when the failing stage is shown to fail on the base branch
too and the diff touches only documentation, the operator can approve that one push past that one
stage. Never an agent's own call, never a blanket skip.

## Constraints already fixed elsewhere

- Hook skips are reserved: the worker profile's denies stay, and no agent widens them.
- The approval must name the stage, the push, and the evidence that the stage fails on the base
  independently of the diff.
- Prefer the hook manager's own per-stage exclusion over skipping every hook.

## Open questions for the drafter

1. What counts as documentation-only (an extension list, a path list, or a repository-declared
   set), and who decides it.
2. How "fails on the base too" is proven mechanically, and how fresh that proof must be.
3. Whether the approval is one push, or a standing approval that lasts until the stage is fixed
   on the base.
