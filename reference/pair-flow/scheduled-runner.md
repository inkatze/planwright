# Pair-Flow Scheduled Runner

The scheduled runner is a remote agent routine that performs orchestration bookkeeping without requiring an interactive session. It runs `/orchestrate --bookkeeping` on a cadence (hourly default per D-29).

## What it does

The runner performs non-implementation moves only:

1. **PR-merge reconciliation.** For each task in `In progress` whose annotation shows `PR #N draft`, checks PR state via `gh pr view`. If merged, moves the task to `Completed` with the standard one-line bullet.
2. **Stale In-progress detection.** Tasks with `Last activity:` older than 48 hours whose PR is not in `MERGED` or `OPEN` state move to `Awaiting input`.
3. **Advance pickups.** After reconciliation, checks if new tasks are now ready (deps just completed). Posts an inbox entry for each newly-ready task.
4. **Spec completion check.** If all tasks are now Completed, flips spec status to Done (D-31).

The runner does **not** implement code, create worktrees, or open PRs. It only reconciles state that changed outside the session (typically: a human merged a PR via the GitHub web UI).

## Setup

Configure the routine via `/schedule` in any Claude Code session:

```
/schedule create --name "pair-flow-bookkeeping" \
  --cron "0 * * * *" \
  --prompt "/orchestrate --bookkeeping specs/<spec-name>"
```

For multiple active specs, create one routine per spec:

```
/schedule create --name "pair-flow-bookkeeping-auth" \
  --cron "0 * * * *" \
  --prompt "/orchestrate --bookkeeping specs/auth"

/schedule create --name "pair-flow-bookkeeping-settings" \
  --cron "0 * * * *" \
  --prompt "/orchestrate --bookkeeping specs/settings"
```

## Cadence

The default is hourly (`0 * * * *`). This is sufficient for state propagation because:

- The human merges PRs manually (D-21: pair-flow never auto-merges).
- The delay between merge and `tasks.md` update is acceptable (under 1 hour).
- More frequent polling has no benefit (PRs don't merge faster).

Adjust if needed:

- `*/30 * * * *` for 30-minute cadence (during active sprints).
- `0 9-18 * * 1-5` for business-hours-only (reduces noise on nights/weekends).

## Prerequisites

- `gh` must be authenticated on the host running the routine (`gh auth status` returns success).
- The spec must be at `Active` status with a signed-off kickoff brief.
- The `~/.claude/scripts/pair-flow-config.sh` helper must be available.

If `gh` is not authenticated, the routine halts gracefully and posts an `Awaiting input` inbox entry (D-43).

## Managing routines

```
/schedule list                     # See all active routines
/schedule update <name> --cron ... # Change cadence
/schedule delete <name>            # Remove a routine
/schedule run <name>               # One-shot manual trigger
```

## Lifecycle

- **Create** the routine when a spec flips to Active after `/spec-kickoff`.
- **Delete** (or let it no-op) when the spec flips to Done. The runner exits cleanly when all tasks are Completed.
- **Pause** during periods where no pair-flow work is active to avoid unnecessary scheduled runs.

## Observability

The runner posts inbox entries on state transitions:

- New task ready: state `working` with a summary naming the task.
- Stale detection: state `awaiting-input` with the stale task ID.
- Spec completed: state `idle` with "all tasks done" summary.

These surface in the tmux dashboard (prefix + i) and status segment.
