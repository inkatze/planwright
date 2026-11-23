# Control-plane measurement baseline

The control plane claims that moving routine decisions out of model sessions
and into code costs fewer model turns, fewer dollars and fewer operator
interruptions, without slowing merges. This document is the method for
checking that claim: what is measured, how it is recorded and which number
each slice of the control plane is expected to move. It holds no figures.
Recorded numbers are machine-local data and never enter the repository.

## When to record

Record a baseline on the machine the control plane will run on, before the
first slice's code is wired or enabled there (the stall watcher hook and the
dedupe gate). After a slice lands, record again over a window of the same
length that starts after the landing (for slice one, after its shadow window
and again after its first class moves to enforce); that recording is the
slice's measured change, and the next slice's design walk reads it against
the baseline. A window of 14 whole days is a sensible default; a shorter one
is noisy and a longer one blurs a change.

## How to record

```sh
scripts/control-plane-baseline.sh record --since <YYYY-MM-DD> --until <YYYY-MM-DD> \
  --repo <owner>/<name> [--repo <owner>/<name>]...
```

Pass every repository the program merges into. The script reads this host's
Claude Code transcripts and asks the forge (`gh`) for each repository's merged
pull requests, then writes one file per window under the fleet home:
`<fleet-home>/control-plane/baseline/<since>--<until>.tsv`, readable by its
owner only. It refuses a location inside a git work tree. `--help` prints the
file's format and the exit codes.

Days are whole UTC days, `--since` to `--until` inclusive. Record only
windows that have ended: a window that includes today undercounts it.

## What is measured

Each number comes from the same seam the rest of planwright already uses, so
the baseline and later readings agree on their definitions.

- **Model turns per day by session role.** A turn is one assistant message
  that carries usage, each message id counted once, read through
  `scripts/token-spend.sh rows`. The role is the session's kind as
  `token-spend.sh report` classes it from the session's first prompt
  (mission control, tower, a session mission control launched, a fleet worker,
  a review, an interactive session, or unknown). Sub-agent turns are counted
  apart from the main chain's, under the role of the session that started
  them.
- **The spend split.** The dollars each role spent over the window and its
  share of the total, priced with `config/token-prices.tsv`.
- **Merges per day.** Pull requests merged into the named repositories, on the
  day of their merge.
- **Operator interruptions.** Each time a session asked the operator
  something (an `AskUserQuestion` use) or pushed them a notification (a
  `PushNotification` use), read from the same transcripts. A permission
  prompt shown in an interactive terminal leaves no transcript record and is
  not counted; the method undercounts those the same way at every reading.

## The number each slice moves

Each slice names the one number it is expected to move. Its landing records
the measured change, and a slice that moves none is rethought before the next
slice starts.

| Slice | What it builds | The number it moves |
| --- | --- | --- |
| One | The approval engine, the event dedupe gate, the request ledger | Mission control's model turns per day. While the approval classes are in shadow they answer nothing, so the shadow-period number is the share of prompts the engine would have answered with no mismatch; the change in turns and in operator interruptions is read at the first class's move to enforce, and the dedupe gate's drops and wakes at its landing. |
| Two | The queue and the dispatcher | Merges per day, with the work-in-progress limit and landing order held by code. |
| Three | The reconciler | Operator interruptions per day, as syncs, check hygiene, flips and evidence stop reaching the operator. |
| Four | Briefs from state and a thin hub | Mission control's share of the spend. |

## Keeping figures out of the repository

`scripts/control-plane-baseline.sh check-committed` fails when a tracked file
holds the baseline's format line or one of its rows, and the test suite runs
it over this repository on every change. The made-up numbers in
`tests/fixtures/control-plane-baseline/` are the one exemption. A figure
retyped into prose escapes the check, so quote a change as a direction and a
reference to the machine-local file, never as the number itself.
