# Seed brief for `environment-broker` (a follow-on bundle of `mission-control`)

Suggested invocation (fresh Claude session in the planwright repo, this file is the seed):

    /spec-draft environment-broker

Read this whole brief before eliciting. Run fold-detection against `test-throughput` (owner of the
gate's host-load handling), `fleet-lifecycle-closure` (owner of resource classes and reclaim) and
`orchestration-concurrency` (owner of the per-spec lock) before assuming a new bundle; this brief
does not prejudge extend-vs-spin-new.

## Why this is a follow-on, not part of `mission-control`

"Shared-environment collisions" is one of the ten failure modes the mission-control invocation
seed records. `mission-control` ships the per-program budget with host load as one of its bounds
(D-17, REQ-L1.2, REQ-M1.6) but scoped the broker that leases shared resources out as a follow-on:
it is independently ownable and forces decisions orthogonal to the core (D-1, D-22, D-27).

## The shape (from the mission-control invocation seed and kickoff)

A **duty** that brokers every resource concurrent sessions on one host (or one program) share:
the gate lock and test pool, temp space, the shared `.git` and its stash, the tmux server, the
fleet registry, and any external environment a program declares (a staging deployment, a test
database, a device). Sessions ask the broker for a lease; it grants, queues or refuses by the
budget, names the holder of a busy lease, and reclaims a lease whose holder is dead (positive
evidence only, mission-control D-11). Mechanics are scripts; the judgment session runs only when a
lease conflict needs a decision (D-4).

## Seams it consumes from `mission-control`

- **The duty catalog** (D-3, REQ-C1.1 to REQ-C1.6), starting in `shadow` (D-15).
- **The budget and its degradation ladder** (D-17, REQ-L1.1, REQ-L1.2, REQ-M1.6): leases are
  counted against host load, not head count.
- **The launcher** (D-10, REQ-D1.1): a launched session receives its lease set with its brief.
- **Liveness and the stall detector** (D-11, REQ-D1.2, REQ-D1.3): a lease held by a dead or
  stalled holder is an event.
- **The queue** (D-7): a contended lease that needs a decision reaches the operator as an item.

## Observations left live for this bundle

- obs:b11f14ac: orphaned fixture processes inherited the host gate-lock descriptor, so every
  later gate on the host queued indefinitely.
- obs:6ed98940, obs:69089148: the test pool hung while holding the gate lock on a loaded host,
  queuing every other gate behind it.
- obs:7424d6d2: the per-spec advisory lock is checkout-local, so orchestrators in two worktrees
  take different locks.
- obs:68489f8e: the secret scan reads every ref in the shared `.git`, so one worker's fixture
  fails every other worker's scan.
- obs:53a1587a: OS temp cleanup deleted a long-running tower's dispatch prompts.
- obs:7411f2a4: a test's "isolated" tmux session landed in the host's real tmux server and killed
  it.
- obs:eebce870: a suite registered workers into the operator's real fleet registry.
- obs:147b0473: a test suite leaked looping supervisor shells that kept loading the host.

`mission-control` itself cites obs:4d47cc6b, obs:6ee76cba, obs:0c4456bb, obs:fe2744fa and
obs:f4607cf0 (host-budget and shared-temp evidence for REQ-B1.4, REQ-L1.1, REQ-L1.2 and
REQ-M1.6); they stay live and are this bundle's evidence too.

## Open questions for the drafter

1. The lease model: one broker per host or per program, and how a lease survives the session that
   took it (mission-control's stable-indirection posture).
2. Which shared resources are brokered in the first version, and which stay a fix in the owning
   script (a test that leaks is a bug, not a lease).
3. How a program declares an external environment, and whether the broker ever holds that
   environment's credentials (the program home never does, mission-control D-8).
