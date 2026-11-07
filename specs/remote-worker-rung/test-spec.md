# Remote worker rung — Test Spec

**Status:** Draft
**Last reviewed:** 2026-11-06
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` in planwright's CI for everything a script owns, on a
fake `ssh` that runs the remote command under each installed shell with a
sandbox home and fake remote verbs; `[manual]` for the live run on a real
remote host; `[design-level]` for the hygiene and safety rules the artifacts
carry.

## REQ-A — The channel

### REQ-A1.1 — Alias validation and machine-local registry [test]

A leading-dash alias, one with a space or a shell metacharacter, is refused
before any SSH call (the fake logs nothing); a registry in a tracked file is
refused.

### REQ-A1.2 — Fixed verbs, quoted arguments [test]

An unknown verb is a usage error; a hostile argument (quotes, command
substitution, backticks, separators, globs) arrives verbatim at the fake
remote verb under sh, bash, zsh and fish, whichever are installed, and a
canary file it would create never appears.

### REQ-A1.3 — Free text over stdin [test]

Steer and launch deliver stdin as the message or brief file, the remote temp
file is gone afterwards, and empty stdin is refused.

### REQ-A1.4 — Batch mode [test]

Every SSH call carries batch mode and no terminal; an unreachable host
returns SSH's own failure code.

### REQ-A1.5 — Remote root resolution [test]

The root comes from `--root`, else the remote environment file, else the
remote installed-plugin record; none of them yields exit 3 with the fix
named; this host's root is never sent.

### REQ-A1.6 — Version check before dispatch [test]

A fake remote reporting a version without a needed verb refuses the
dispatch, naming the version and the missing verb.

## REQ-B — Dispatch and lifecycle

### REQ-B1.1 — Launch through the remote launcher [test]

A dispatch reaches the fake remote launcher with the unit's scope, repository
clone and the brief from stdin.

### REQ-B1.2 — Local record routes later verbs [test]

One dispatch writes one record; status, steer, answer, stop and retire each
reach the recorded host and no other.

### REQ-B1.3 — Remote liveness only [test]

A colliding local pid does not change a remote worker's state; an
unreachable host reads `unreachable` within its grace and `lost` after.

### REQ-B1.4 — Branch through the hosting remote [manual]

In the live run the pull request comes from the remote clone and the review
and ready flip run here against it.

### REQ-B1.7 — Fetch-back for an unsigned host [test]

A fake remote with no hosting-remote login has its worker branch fetched
over the alias and pushed from this host; one with a login is left to push
itself; no local credential file is read or sent.

### REQ-B1.5 — Retire and worktree removal [test]

A merged unit's remote worktree is removed; an unmerged, unpushed or live one
is kept.

### REQ-B1.6 — Keep-awake [test]

The keep-awake holder starts with the first remote worker and ends with the
last; a platform without one records that it has none.

## REQ-C — Supervision

### REQ-C1.1 — Remote requests in the vetting view [test]

A remote pending request appears in the vetting pass with its host and is
judged by the same rules as a local one.

### REQ-C1.2 — Answers delivered remotely [test]

An answer settles the request in the fake remote journal; an undeliverable
answer is reported by the remote verb, not here.

### REQ-C1.3 — Alarm and unreadable host [test]

An overdue remote request raises the pending-age alarm; an unreachable host
raises its own attention item.

### REQ-C1.4 — Steer and wake relay [test]

The wake relay's steer reaches the remote worker through the channel.

### REQ-C1.5 — Guard approval [test]

The guard approves each fixed verb by the resolved literal path, and falls
through on an unknown verb, a `~` or variable path, and a raw `ssh` command.

### REQ-C1.6 — Named authentication failure [test + manual]

A fake worker result carrying an authentication error is surfaced as a named
failure; the live run reproduces it once on a host with no login.

## REQ-D — Capacity and usage

### REQ-D1.1 — Per-host capacity [test]

Fixtures hold a dispatch at the host ceiling and on tight remote load or
memory, and admit it otherwise.

### REQ-D1.2 — Shared-host idle rule and hold [test]

A shared host with recent input, or on hold, takes no new work; an idle one
does.

### REQ-D1.3 — Per-account gate [test]

A remote dispatch is held when its account is past the stop while this
host's is not, and the reverse.

### REQ-D1.4 — Unavailable usage [test]

A remote with no usage source reports `unavailable` and degrades as the local
gate does.

### REQ-D1.5 — Reset times and billing kinds [test]

Fixtures with two subscription accounts resetting on different days and one
metered account: each reading stays in its own unit, and no dollar reading
meets a percent threshold.

## REQ-E — Placement

### REQ-E1.1 — Capability contract row [test]

The capability-drift check passes with the remote row; detection lists the
rung only for registered, reachable hosts.

### REQ-E1.2 — Host choice [test]

Placement fixtures pick the host by the recorded rule and honor a pin.

### REQ-E1.3 — Dispatch report [test]

A remote dispatch report names the host alias, the remote handle and the
channel observe hint.

### REQ-E1.4 — No relaxed safety [design-level]

The remote launch uses the same profile, guards and cadence as a local one;
verified by the launch path calling the remote's own launcher unchanged.

## REQ-G — Compute offload

### REQ-G1.1 — Ship HEAD, run one allowlisted command [test]

`tests/test-fleet-remote.sh` on the fake SSH: a file only the shipped commit
holds runs remotely; a path outside `tests/`, a task name outside the
grammar, two command kinds and a relative worktree are refused before any
SSH call; uncommitted changes produce the warning and are not shipped.

### REQ-G1.2 — Output, status and duration [test]

The same suite: the command's output arrives, a failing command's status
passes through, and the trailer names the commit and the duration.

### REQ-G1.3 — Timeout and cleanup [test + manual]

The same suite: a sleeping command stops at a one-second timeout with the
terminate status, and no scratch run, extra worktree or hidden ref remains;
the live run on the first remote host repeated it on a real suite.

### REQ-G1.4 — No commits, no logins [design-level]

The compute path has no commit or push on the remote side and reads no
credential; it ran on the first remote host before that host had any
hosting-remote login.

### REQ-G1.5 — Gate runs placed remotely with local fallback [test]

Task 11's fixtures: remote placement with room, local with none, local rerun
after a ship failure or an unreachable host, no rerun after a failing
command.

## REQ-F — Hygiene

### REQ-F1.1 — No host values committed [test + design-level]

The purged-identifier and data-hygiene checks pass over every committed
file; tests use placeholder aliases only.

### REQ-F1.2 — No credentials on the channel [design-level]

The channel's verb set carries no credential argument and no verb reads a
local credential file.
