# Seed brief: amend `fleet-lifecycle-closure` (resource classes for every session kind)

Captured 2026-10-27 by `mission-control` Task 4, which routed this work here
rather than absorbing it (mission-control's D-11 and D-22).

Suggested invocation, from a fresh session in the planwright repo:

    /spec-draft --extend fleet-lifecycle-closure

The bundle derives **Active** at capture, so extending it leaves the stored
status untouched and `/spec-kickoff`'s delta re-walkthrough is the sign-off
path. Check the derived state again before drafting; if it has gone Done,
the extension takes the reopen cycle instead.

## The gap

The lifecycle floor (`doctrine/fleet-coordination-floor.md`, this bundle's
D-1) says every lifecycle phase is a resource class with a deterministic
open, a deterministic close and a script-readable stuck detector. Its
classes and its detector (`scripts/fleet-stuck-detector.sh`) cover
dispatched **workers**. Mission control now launches and retires sessions of
every kind (tower, orchestrator, worker, reviewer, ad-hoc and mission control
itself) through `scripts/mission-control-launch.sh`, and detects their stalls
through `scripts/mc-stall.sh`. Those classes sit outside the floor, so
nothing says a future rung or kind owes them a close or a detector.

## The resource classes to bring under the floor

- **The launched session of a non-worker kind**: its process and its tmux
  window, opened by the launcher's `launch` and closed by its `retire`.
- **The launcher's registry row and launch directory** under the fleet home
  (`mission-control/sessions/`, `mission-control/launch/`), released last
  by `retire`, which reports a partial release by class.
- **The stall sample** `mc-stall.sh` keeps per session under the program's
  runtime directory, and the `stall-<state>` events it emits into the
  program's attention store (pruned by `mission_control_event_retention`).
  A relaunch under the same name starts a fresh sample, but nothing removes
  a retired session's sample yet: `retire` has no close for it.
- **The reclaimed worktree and its reclaim folder**: `scripts/mc-reclaim.sh`
  opens a backup under the program home's `reclaimed/<repository>/<branch>/`
  and closes the worktree through `fleet-cleanup.sh worktree`, refusing
  unless no process uses it, its PR landed or closed, nothing is
  uncommitted or unpushed, and every copy matched by size and hash.

## Questions for the drafting session

- Whether `fleet-stuck-detector.sh`'s four states and `mc-stall.sh`'s states
  should converge on one vocabulary, or the floor names both as detectors
  of their own classes.
- Whether the reclaim folder is a resource class with a close of its own (a
  retention rule), or class-3 work product the operator owns
  (storage-classes), as mission control's D-8 has it.
