# Remote worker rung — Requirements

**Status:** Draft
**Last reviewed:** 2026-11-06
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

Let a placing session on this host run a worker on another host it reaches by
SSH (a second computer on the LAN, or a cloud development workspace such as a
Coder workspace) and supervise it as closely as a local one: dispatch it, vet
its permission prompts, steer it, read its result and retire it, with the
branch travelling through GitHub. The other host is one more execution rung,
chosen by work placement like any rung, and the choice weighs each host's
capacity and the usage left on the account that host runs (D-1). The host is
always a parameter, an SSH alias, never a particular machine (D-2).

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
- Per-account usage for a host whose account differs from this host's.
- A remote rung in the backend capability contract and a host dimension in
  work placement, the orchestrator and mission control's launch.

### Out of scope

- A second mission control on the remote host, and messaging between two
  mission controls on different machines (obs:57770415 stays open for that).
- Moving git objects between hosts directly: branches go through the hosting
  remote (GitHub) only.
- Installing or upgrading planwright, Claude Code, credentials or SSH keys on
  the remote host: that is the operator's machine setup (the dotfiles
  repository), which this bundle documents but does not perform.
- Interactive attachment to a remote worker (a tmux rung on the remote).
- Creating, starting or rebuilding cloud workspaces.
- A dollar-denominated spend limit (obs:af17332a owns it).

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
  host, through that host's own installed-plugin record or its machine-local
  environment file, and SHALL NOT send this host's root; a remote host with
  no resolvable root SHALL fail with a message naming the fix.
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
  the host's configured grace period ends, after which the worker reads as
  lost and its unit is reported.
  *(Cites: D-6.)*
- **REQ-B1.4** A remote worker's branch SHALL be pushed to the hosting remote
  from the remote clone, and review, step records and the ready flip SHALL
  run against the pull request exactly as for a local worker.
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
  while its owner is not using it, by the signal D-8 defines, and the
  operator SHALL be able to hold all work off a host with one switch.
  *(Cites: D-8.)*
- **REQ-D1.3** Usage SHALL be tracked per account: a remote host's dispatch
  SHALL be gated on the usage of the account that host runs, read on that
  host, under the same hard stop as local dispatch.
  *(Cites: D-13.)*
- **REQ-D1.4** Usage that cannot be read for an account SHALL be reported as
  unavailable and SHALL degrade the way the local usage gate already
  degrades, never read as zero.
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
  D-15 records.
  *(Cites: D-15.)*
- **REQ-E1.3** A dispatch report for a remote worker SHALL name the host
  alias, the remote worker handle and how to observe it through the channel.
  *(Cites: D-14.)*
- **REQ-E1.4** Placement onto a remote host SHALL never relax a safety rule:
  the remote worker runs the same profile, guards and verification cadence
  as a local one.
  *(Cites: D-14.)*

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
  landed with this bundle as the smallest working form of REQ-A.
- **The program's standing rules (2026-11-04 to 2026-11-06)** — the dynamic
  worker limit, the shared usage ladder with its hard stop, and the second
  computer as a work host used only while its owner is not using it.
- **mission-control's scope** — its out-of-scope list names a remote
  development-environment rung and cross-machine mission control; this bundle
  takes the first and leaves the second.
- obs:57770415 — cross-machine mission-control relay, cited as the boundary
  of this bundle, not consumed.
