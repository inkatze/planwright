# Remote worker rung — Tasks

**Status:** Draft
**Last reviewed:** 2026-11-06
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order, which is presentation; the `Dependencies:` lines
carry the graph. The channel's first form (`scripts/fleet-remote.sh`,
including its compute verb) landed with this bundle; Task 1 completes it.

## Tasks

### Task 1 — Complete the channel

- **Deliverables:** `scripts/fleet-remote.sh` gains a `version` verb (the
  remote planwright version and the verbs it offers), a `capacity` verb (load
  average, core count, free memory, input idle seconds where the platform
  reports them), a `usage` verb (the remote status-line mirror, else the
  newest worker rate-limit readings, each labelled with its source) and a
  `stop` verb; a `docs/fleet.md` section on the remote host's environment
  file and setup; tests on the fake-SSH harness under every remote shell
  present.
- **Done when:** each new verb's output parses on fixtures from a macOS and a
  Linux remote; a remote with no rate-limit source prints `unavailable`, not
  zero; an argument with a backslash, a control character or a leading-dash
  alias still reaches no SSH call; the suite runs in CI.
- **Dependencies:** none
- **Citations:** D-3, D-4, D-12, D-13 · REQ-A1.2, REQ-A1.3, REQ-A1.4,
  REQ-A1.5, REQ-A1.6, REQ-D1.4
- **Estimated effort:** 1 day

### Task 2 — Host registry

- **Deliverables:** A machine-local host registry (alias, repository alias to
  remote clone path, worker ceiling, account label, shared flag, idle
  threshold, hold switch, unreachable grace, and the compute credential
  stance: a login-free compute account, or the operator's acceptance) read
  through the config resolver, refused when tracked; a reader script with a
  validation verb.
- **Done when:** a valid registry resolves; a malformed alias, a relative
  clone path or a registry in a tracked file is refused with the field named;
  a host with no compute credential stance is refused for compute and still
  accepted for workers;
  `check:purged-identifiers` and the data-hygiene sweep find no alias in any
  committed file the tests create.
- **Dependencies:** none
- **Citations:** D-2, D-16 · REQ-A1.1, REQ-F1.1, REQ-G1.6
- **Estimated effort:** 1 day

### Task 3 — Remote dispatch and routing

- **Deliverables:** A remote dispatch path that runs the remote launcher
  through the channel, writes the local dispatch record, and routes status,
  steer, answer, stop and retire by that record; the fleet status view lists
  remote workers with their host; the unreachable and lost states; the
  fetch-back path for a host with no hosting-remote login (fetch the branch
  from the remote clone over the alias, push it from here).
- **Done when:** on the fake-SSH harness a dispatch writes one record and each
  later verb reaches the recorded host; an unreachable host reads
  `unreachable` before its grace ends and `lost` after; no code path runs a
  local pid check against a remote worker (a test seeds a colliding local pid
  and shows it is ignored); a fake remote with no login has its branch
  fetched back and pushed from this host, and one with a login is left to
  push itself.
- **Dependencies:** Task 1, Task 2
- **Citations:** D-3, D-5, D-6, D-10 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4,
  REQ-B1.7, REQ-E1.3
- **Estimated effort:** 2 days

### Task 4 — Guard approval of the channel

- **Deliverables:** The tower and mission-control command guards approve
  `scripts/fleet-remote.sh` by its resolved literal root for its fixed verbs,
  in the modes that approve the local stream-json verbs; guard tests.
- **Done when:** the guard approves each fixed verb, falls through on an
  unknown verb, on a `~` or variable path and on a raw `ssh` command, and the
  guard-wiring check passes.
- **Dependencies:** Task 1
- **Citations:** D-9 · REQ-C1.5
- **Estimated effort:** half day

### Task 5 — Remote requests in the vetting loop

- **Deliverables:** Mission control's vetting pass, the keeper's pending-age
  sweep and the wake relay read and act on remote workers through the
  channel; an attention item for a host that cannot be read.
- **Done when:** on the fake-SSH harness a remote pending request appears in
  the vetting view with its host, an answer settles it on the remote journal,
  an overdue remote request raises the alarm, and an unreachable host raises
  its own item.
- **Dependencies:** Task 3, Task 4
- **Citations:** D-7 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4
- **Estimated effort:** 2 days

### Task 6 — Per-host capacity, shared hosts and keep-awake

- **Deliverables:** The dynamic worker limit applied per host from the
  capacity verb and the registry ceiling; the shared-host idle rule and hold
  switch; keep-awake while a worker runs on a platform that offers it.
- **Done when:** fixtures show a dispatch held at the ceiling, on tight remote
  load, while a shared host is in use and while it is on hold, and admitted
  otherwise; the keep-awake holder starts with the first remote worker and
  ends with the last.
- **Dependencies:** Task 1, Task 2
- **Citations:** D-8, D-12 · REQ-D1.1, REQ-D1.2, REQ-B1.6
- **Estimated effort:** 1 day

### Task 7 — Per-account usage

- **Deliverables:** The usage gate takes an account subject carrying its
  reset time and billing kind; a remote host's dispatch gates on its
  account's usage from the usage verb, under the same hard stop and the same
  unavailable-signal degradation; metered accounts are read in dollars.
- **Done when:** fixtures show a remote dispatch held when its account is past
  the stop while this host's account is not, and the reverse; an unavailable
  remote reading degrades as the local gate does; a metered account's dollar
  reading is never compared against a percent threshold.
- **Dependencies:** Task 1, Task 2
- **Citations:** D-13, D-15 · REQ-D1.3, REQ-D1.4, REQ-D1.5
- **Estimated effort:** 1 day

### Task 8 — The remote rung in placement

- **Deliverables:** The remote rung row in the backend capability contract,
  its presence in backend detection, the host dimension in work placement,
  and host selection in the orchestrator and mission control's launch by the
  placement rule; the dispatch report names the host.
- **Done when:** the capability-drift check passes with the new row;
  detection lists a remote rung only for a registered, reachable host;
  placement fixtures pick hosts by the recorded rule (the subscription that
  resets soonest with headroom first, metered last) and honor a pin; a
  remote dispatch report names the host, handle and observe hint.
- **Dependencies:** Task 3, Task 6, Task 7
- **Citations:** D-1, D-14, D-15 · REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.4
- **Estimated effort:** 2 days

### Task 9 — Remote retire and cleanup

- **Deliverables:** Retire and the daily fleet cleanup release remote workers
  through the remote close verb and remove remote worktrees on the local
  conditions.
- **Done when:** on the fake-SSH harness a merged unit's remote worktree is
  removed, an unmerged or unpushed one is kept, and a live worker is never
  touched.
- **Dependencies:** Task 3
- **Citations:** D-5 · REQ-B1.5
- **Estimated effort:** 1 day

### Task 11 — Gate runs on a remote host

- **Deliverables:** A placement step that sends a worker's gate run (the full
  check, or a named suite) through the compute verb to a registered host with
  room, by the per-host capacity rule, falling back to a local run when no
  host has room or the channel fails before the command starts; the worker
  briefs and `/execute-task`'s CI step name it; the step record notes where
  the gate ran.
- **Done when:** fixtures show a gate run placed remotely when a host has
  room, run locally when none has, and rerun locally after a ship failure
  (exit 4) or a run whose command never started (no `fleet-remote: running`
  line on stderr), but never after a run whose command started, whatever
  its exit status, 255 included; a host whose registry entry records no
  compute credential stance is never chosen;
  the step record names the host alias class (remote or local) without the
  alias itself.
- **Dependencies:** Task 2, Task 4, Task 6
- **Citations:** D-12, D-16 · REQ-G1.1, REQ-G1.2, REQ-G1.3, REQ-G1.4,
  REQ-G1.5, REQ-G1.6
- **Estimated effort:** 1 day

### Task 10 — Live acceptance on a real remote host

- **Deliverables:** A recorded run on one real remote host: dispatch, a vetted
  prompt, a steer, the pull request from the remote clone, retire; the
  authentication setup documented for a macOS host.
- **Done when:** the run's report shows each step's outcome, an
  authentication failure case surfaces as a named failure, and the report
  holds no alias, hostname, path or token.
- **Dependencies:** Task 5, Task 8, Task 9
- **Citations:** D-11 · REQ-B1.4, REQ-C1.6, REQ-F1.2
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
