# Remote worker rung — Requirements

**Status:** Ready
**Last reviewed:** 2026-11-11
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

Let a placing session on this host run a worker on another host it reaches by
SSH (a second computer on the LAN, or a cloud development workspace such as a
Coder workspace) and supervise it as closely as a local one: dispatch it, vet
its permission prompts, steer it, read its result and retire it, with the
branch travelling through GitHub. The other host is one more execution rung,
chosen by work placement like any rung, and the choice weighs each host's
capacity and whether its owner is using it (D-1). The host is
always a parameter, an SSH alias, never a particular machine (D-2). The same
channel also offloads plain compute: a worktree's committed test or check run
executed on the other host, with no worker and no model account involved
(D-16).

Today this works only by hand, through the recipe and the thin near-side
channel the seed research left (the research note and the channel script in
Sources): mission control's vetting loop, guards, usage gate, capacity limit
and placement all see only the local host.

## Scope

### In scope

- A machine-local registry of remote hosts: alias, the remote clone of each
  work repository, a worker ceiling and the account the host runs.
- The near-side channel: a fixed set of verbs run on the remote host's own
  planwright over SSH, every argument quoted, free text sent over stdin.
- Dispatch onto a remote host, its dispatch record on this host, and routing
  every later verb (status, steer, answer, stop, retire, cleanup) back to the
  host that runs the worker.
- Mission control's vetting loop, pending-age alarm and wake relay covering
  remote workers.
- Command-guard approval of the channel's fixed verbs.
- Per-host capacity, a shared host's "owner is using it" signal, and keeping
  the remote host awake while it runs a worker.
- Usage for remote hosts that run this host's own account (the one shared
  usage gate), and a refusal of a host whose account differs.
- A remote rung in the backend capability contract and a host dimension in
  work placement, the orchestrator and mission control's launch.
- Compute offload: running one allowlisted command (the full check, a named
  task, a named test file) against a worktree's exact committed HEAD on a
  remote host, and pointing workers' gate runs at it.

### Out of scope

- Per-account usage tracking: accounts whose windows reset on different
  days, a second subscription account on a remote host, and metered
  (dollar) accounts. The program runs one account across every host, so
  the shared usage gate already covers remote work; a host on a different
  account is refused (REQ-D1.5) until a later bundle builds this.
- A second mission control on the remote host, and messaging between two
  mission controls on different machines (obs:57770415 stays open for that).
- Moving git objects between hosts directly, beyond the two paths this bundle
  names: compute's push of one commit to the remote clone (REQ-G1.1) and the
  fetch-back of a worker branch from a host with no hosting-remote login
  (REQ-B1.7). Every other branch goes through the hosting remote (GitHub).
- Installing or upgrading planwright, Claude Code, credentials or SSH keys on
  the remote host: that is the operator's machine setup (the dotfiles
  repository), which this bundle documents but does not perform.
- Interactive attachment to a remote worker (a tmux rung on the remote).
- Creating, starting or rebuilding cloud workspaces.
- A dollar-denominated spend limit (obs:af17332a owns it); this bundle only
  reads metered spend as a placement cost.
- Offloading to model providers other than Anthropic: a named future
  extension through the backend seam, not built here unless it falls out of
  the seam unchanged.

## REQ-A — The channel

- **REQ-A1.1** A remote host SHALL be named by an SSH alias resolved through
  the operator's SSH configuration, validated against a fixed character set
  with no leading dash before any use, and SHALL be recorded only in
  machine-local configuration, never in a tracked file.
  *(Cites: D-2.)*
- **REQ-A1.2** Every operation on a remote host SHALL go through one
  near-side channel that runs a fixed set of verbs on the remote host's own
  planwright; the channel SHALL NOT run a caller-supplied command, and SHALL
  quote every argument so the remote login shell, whatever it is, never
  re-parses caller text.
  *(Cites: D-4.)*
- **REQ-A1.3** Free text (a brief, a steer message) SHALL travel to the
  remote host over stdin into a remote temporary file the channel removes
  afterwards, never on a command line.
  *(Cites: D-4.)*
- **REQ-A1.4** The channel SHALL run SSH non-interactively, so a host that
  would prompt for a password or a host key fails at once with a named
  error instead of waiting.
  *(Cites: D-4.)*
- **REQ-A1.5** The channel SHALL resolve the planwright root on the remote
  host, through that host's own installed-plugin record, SHALL NOT send this
  host's root, and SHALL NOT let a caller point a verb at another copy; a
  remote host with no resolvable root SHALL fail with a message naming the
  fix.
  *(Cites: D-3.)*
- **REQ-A1.6** Before a dispatch, the channel SHALL report the remote
  planwright version, and a dispatch SHALL be refused when the remote version
  lacks a verb the dispatch needs.
  *(Cites: D-3.)*

## REQ-B — Dispatch and lifecycle

- **REQ-B1.1** A remote dispatch SHALL launch through the remote host's own
  launcher, which creates the worker's worktree in the remote clone of the
  work repository on the unit's branch, starts the supervisor there and
  registers the worker in the remote fleet home.
  *(Cites: D-3.)*
- **REQ-B1.2** Each remote dispatch SHALL write a record on this host naming
  the host alias and the remote worker, and every later verb for that worker
  SHALL route to that host through the channel.
  *(Cites: D-5.)*
- **REQ-B1.3** A remote worker's liveness SHALL be judged only from the
  remote host's own status verb; no check on this host SHALL read a remote
  worker's pid. An unreachable host SHALL read as unreachable, not dead, until
  the host's configured grace period ends (30 minutes by default), after
  which the worker reads as lost and its unit is reported.
  *(Cites: D-6.)*
- **REQ-B1.4** A remote worker's branch SHALL be pushed to the hosting remote
  from the remote clone when that host holds its own hosting-remote login,
  and review, step records and the ready flip SHALL run against the pull
  request exactly as for a local worker.
  *(Cites: D-10.)*
- **REQ-B1.7** A remote host without its own hosting-remote login SHALL
  still deliver its worker's commits: this host fetches the branch from the
  remote clone over the SSH alias and pushes it, and no credential of this
  host SHALL be copied to the remote host for it.
  *(Cites: D-10.)*
- **REQ-B1.5** Retiring a remote worker SHALL release it through the remote
  host's own close verb, and its remote worktree SHALL be removed only on the
  same conditions as a local one (pull request merged or closed, no unpushed
  work, nothing live).
  *(Cites: D-5.)*
- **REQ-B1.6** Where the remote platform offers it, the remote host SHALL be
  kept from sleeping while it runs a worker, and released when its last
  worker ends.
  *(Cites: D-8.)*

## REQ-C — Supervision

- **REQ-C1.1** Mission control's vetting loop SHALL read every remote
  worker's pending permission requests on each pass, through the channel's
  pending verb, and SHALL judge them by the same rules as local requests.
  *(Cites: D-7.)*
- **REQ-C1.2** An answer to a remote request SHALL be delivered on the remote
  host by the channel's answer verb, so the remote journal and its
  undeliverable handling stay authoritative.
  *(Cites: D-3, D-7.)*
- **REQ-C1.3** The pending-age alarm SHALL cover remote requests from this
  host, and a remote host that cannot be read SHALL raise its own attention
  item rather than hide its workers' requests.
  *(Cites: D-7.)*
- **REQ-C1.4** Steering and the wake relay SHALL reach a remote worker
  through the channel's steer verb.
  *(Cites: D-7.)*
- **REQ-C1.5** The command guard SHALL approve the channel's fixed verbs in
  the same sessions and on the same terms it approves the local stream-json
  verbs, and SHALL approve no other command that reaches a remote host.
  *(Cites: D-9.)*
- **REQ-C1.6** A remote worker that cannot authenticate to its model
  provider SHALL end with a named authentication failure in its result,
  surfaced like any worker death.
  *(Cites: D-11.)*

## REQ-D — Capacity and usage

- **REQ-D1.1** Each remote host SHALL carry a worker ceiling, and a remote
  dispatch SHALL be held when the host is at its ceiling or its own load or
  free memory, read on that host, is tight by the same rule the local
  dynamic limit applies.
  *(Cites: D-12.)*
- **REQ-D1.2** A host the registry marks as shared SHALL take new work only
  while its owner is not using it (input idle for the host's configured
  time, 15 minutes by default), by the signal D-8 defines, and the
  operator SHALL be able to hold all work off a host with one switch.
  *(Cites: D-8.)*
- **REQ-D1.3** A remote dispatch SHALL pass through the same usage gate and
  hard stop as a local dispatch, read on this host, because a registered
  host runs this host's account.
  *(Cites: D-13.)*
- **REQ-D1.4** Usage that cannot be read SHALL be reported as unavailable
  and SHALL degrade the way the local usage gate already degrades, never
  read as zero.
  *(Cites: D-13.)*
- **REQ-D1.5** Each registry entry SHALL name the account label the host
  runs, and a dispatch SHALL be refused for a host whose label differs from
  this host's, with the reason named, so a second account is never spent
  unmetered by accident.
  *(Cites: D-13.)*

## REQ-E — Placement

- **REQ-E1.1** The backend capability contract SHALL describe the remote rung
  by its advertised capabilities (it survives the placing session, runs
  beyond it, is observable, is not human-attachable) plus the host it runs
  on, and its presence SHALL be advertised only for registered hosts the
  channel can reach.
  *(Cites: D-14.)*
- **REQ-E1.2** Work placement SHALL treat the host as a dimension of the
  rung choice: a unit whose sufficient rung is session-grade MAY run on any
  registered host with room, and the choice SHALL follow the placement rule
  D-15 records: a free remote host first, this host otherwise, and an
  operator pin over both.
  *(Cites: D-15.)*
- **REQ-E1.3** A dispatch report for a remote worker SHALL name the host
  alias, the remote worker handle and how to observe it through the channel.
  *(Cites: D-14.)*
- **REQ-E1.4** Placement onto a remote host SHALL never relax a safety rule:
  the remote worker runs the same profile, guards and verification cadence
  as a local one.
  *(Cites: D-14.)*

## REQ-G — Compute offload

- **REQ-G1.1** The channel SHALL offer a compute verb that ships a local
  worktree's exact HEAD commit to the remote host's clone of the same
  repository and runs one command from a fixed set (the full check, a named
  task, a named test file under `tests/`) in a fresh scratch worktree there;
  uncommitted changes SHALL NOT be shipped, and the caller SHALL be warned
  when they exist.
  *(Cites: D-16.)*
- **REQ-G1.2** A compute run SHALL stream the command's output back, exit
  with the command's own status, and report its duration.
  *(Cites: D-16.)*
- **REQ-G1.3** A compute run SHALL stop the command and every process it
  started at its timeout, exiting with the terminate status, and SHALL
  remove its scratch worktree, temporary directory and shipped ref on every
  exit path.
  *(Cites: D-16.)*
- **REQ-G1.4** No commit SHALL originate in a compute run, and a compute run
  SHALL need no hosting-remote login and no model account on the remote
  host.
  *(Cites: D-16.)*
- **REQ-G1.5** Workers' gate runs (the full check before a pull request, a
  named suite) SHALL be placeable on a remote host with room, by the same
  per-host capacity rule as remote workers, falling back to a local run
  when no host has room or the channel fails before the command starts.
  *(Cites: D-12, D-16.)*
- **REQ-G1.6** Because a compute run executes the shipped commit's code as
  the remote account, a host SHALL take compute runs only when its registry
  entry records how that account's credentials are kept from that code: an
  account holding no hosting-remote or model login, or the operator's
  explicit acceptance that the code can read the logins it holds.
  *(Cites: D-11, D-16.)*

## REQ-F — Hygiene

- **REQ-F1.1** No committed artifact SHALL carry a host alias, hostname,
  address, remote user name or remote path; such values live only in
  machine-local configuration.
  *(Cites: D-2.)*
- **REQ-F1.2** The channel SHALL NOT carry credentials; a remote host's
  model-provider login and repository credentials are set up on that host and
  never sent from this one.
  *(Cites: D-11.)*

## Changelog

- 2026-11-10 — Kickoff decisions: one account covers every host, so the
  per-account usage tracking is dropped to a shared gate plus a refusal of a
  differing account (REQ-D1.3 to D1.5, D-13, D-15); a shared host takes work
  after 15 minutes of idle input; this host's mission control vets remote
  prompts and the guard approves the channel's fixed verbs; compute's
  credential exposure is accepted per host and recorded; the unreachable
  grace is 30 minutes; placement prefers the free remote host; fetch-back
  for a host with no hosting-remote login stays. Test and lint offload
  shipped meanwhile as `scripts/compute-route.sh` over the channel's compute
  verb; Task 11 extends it instead of building it.

- 2026-11-06 — Drafted from the remote-worker research note and the operator's
  request to offload workers to another host and steer them remotely.

## Sources

- **The operator's request (2026-11-06)** — "lets also figure out how to,
  for example, just offload workers and steer them remotely? but whatever we
  can do for now is cool", then, relayed by mission control, "would it be
  easier to figure out that offload channel instead and have that extra
  option? with a different mission control I was able to offload to coder so
  I thought it would be easy". Pinned altitude claim: an extra option, the
  offload channel, ahead of a second mission control (D-1).
- **The remote-worker research note** — `docs/research/remote-worker-over-ssh.md`:
  the by-hand recipe and the gaps this bundle closes.
- **The near-side channel** — `scripts/fleet-remote.sh` and its test suite,
  landed with this bundle as the smallest working form of REQ-A and REQ-G.
- **The operator's later notes, relayed by mission control (2026-11-06)** —
  compute offload first, because this host is CPU-bound by test suites
  while the second computer's cores sit idle ("run a worktree's exact HEAD
  tests on the Mac, stream back exit code and log"); full remote workers
  push and open pull requests themselves once the remote host is signed in,
  with fetch-back through this host as the fallback; support the advanced
  cases where cheap: accounts whose weekly windows reset on different days
  (spend the one that resets next), compute versus full workers, and other
  model providers as a future extension; and metered (pay-per-use)
  consumption costs significantly more than subscription capacity, so
  placement prefers subscription headroom before its reset and treats
  metered spend as the costlier fallback, in each account's own unit.
- **The first remote host's setup (2026-11-06)** — a dedicated account on a
  shared personal machine, key-only SSH from this host, work confined to
  that account's home (no elevated rights, nothing in the owner's account,
  package manager or settings). The model-provider login worked over SSH
  without the keychain problem the research note feared. Its
  hosting-remote login was set up later through the provider's CLI, which
  stored the token in plain text in that account's CLI config because the
  account has no keychain: a known limitation of the setup, not something
  the channel carries.
- **The first live compute runs (2026-11-06)** — the stream-json supervisor
  suite on the remote host and on this host, at the same time on the same
  commit: both passed every check; the remote took a little over two
  minutes and this host (load around 41 on 12 cores) over eight.
- **The program's standing rules (2026-11-04 to 2026-11-10)** — the dynamic
  worker limit, the shared usage ladder with its hard stop, the second
  computer as a work host used only while its owner is not using it, remote
  workers as full workers under the same cadence, and one account covering
  both hosts (the Mac adds no usage budget).
- **The kickoff answers (2026-11-10)** — the operator chose, in order: the
  simple usage version; input idle for 15 minutes before a shared host takes
  work; this host's mission control vetting remote prompts and the guard
  approving the channel's fixed verbs; accepting and recording the
  credential exposure for compute; the Mac first whenever it is free; keeping
  the fetch-back path; a 30-minute unreachable grace.
- **mission-control's scope** — its out-of-scope list names a remote
  development-environment rung and cross-machine mission control; this bundle
  takes the first and leaves the second.
- obs:57770415 — cross-machine mission-control relay, cited as the boundary
  of this bundle, not consumed.
