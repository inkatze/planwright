# Proportionality

**Rigor scales with stake and reversibility.** The full weight of planwright's
rigor doctrine exists for changes where being wrong is expensive or hard to
undo. Applying it uniformly to every change would make the doctrine the
bottleneck; applying it silently unevenly would make it a fiction. The rule
that resolves the tension: scale deliberately, and declare the scaling.

Citations: REQ-D1.7.

## The scaling rule

Two questions size the rigor a change deserves:

- **Stake.** What breaks if this is wrong, and for whom? A typo fix in a
  doc, an internal helper rename, and a change to an authentication check
  do not deserve the same scrutiny.
- **Reversibility.** How cheap is undo? A commit on a draft-PR branch is one
  revert from undone. A merged migration, a published API, a deleted
  history are not. The hard-disqualifier zones in
  [finding-categorization.md](finding-categorization.md) are the canonical
  list of low-reversibility territory, and the reserved human controls
  (sign-off, merge) sit exactly at the points of least reversibility.

High stake or low reversibility pulls toward the full doctrine: all three
validation passes, lens fan-out, write-time security passes, research before
implementation. Low stake and high reversibility permit lighter passes:
inline discovery instead of fan-out, spot-check validation for findings a
human will review anyway.

## Declared scoping

Any skill that scopes a rigor requirement declares the scoping explicitly,
in the skill, where a reader can find it. "This skill applies the full
three-pass validation to findings it acts on autonomously and a spot-check
to findings surfaced for human review" is a declared scope. Skipping a pass
because the change felt small is not a scope; it is the silent pruning the
rigor docs exist to prevent. The default for any skill that does not declare
otherwise is the full requirement.
