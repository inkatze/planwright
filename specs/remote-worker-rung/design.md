# Remote worker rung — Design

**Status:** Draft
**Last reviewed:** 2026-11-06
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `S` from a seed source, `N` new in this drafting session, `Q` a
recommended default that waits on the operator's answer before kickoff.

## Decision log

### D-1: Altitude — a new rung plus a host dimension in placement  (S)

**Decision:** The deliverable is an execution rung (a worker on another host)
and a host dimension in the work-placement doctrine, the capability contract
and the launchers that read them. It is not a second mission control and not
a cross-machine messaging layer.

**Alternatives considered:**
- A second mission control on the remote host with its own share of the
  work. Rejected because: the operator moved it behind the offload channel;
  it splits vetting, and it needs the cross-machine relay that does not
  exist.
- A by-hand recipe only. Rejected because: every remote call would be an
  unvetted command line, and nothing would watch remote requests.

**Chosen because:** the operator asked for the extra option first, and a rung
reuses the remote host's whole supervisor rather than rebuilding it.

### D-2: The host is an SSH alias in machine-local config  (S)

**Decision:** A remote host is an alias from the operator's SSH
configuration, held in a machine-local registry (never tracked) with the
remote clone path per repository alias, a worker ceiling, the account label,
a shared-host flag and an unreachable grace period.

**Alternatives considered:**
- Hostnames or addresses in tracked config. Rejected because: data hygiene
  forbids internal hostnames in committed artifacts, and they differ per
  machine.
- A named machine kind (Mac, Coder). Rejected because: the channel is the
  same for every SSH host; kinds would fork the code for no behaviour.

**Chosen because:** SSH configuration already owns how to reach a host (keys,
jump hosts, `coder config-ssh` entries), so planwright only needs the name.

### D-3: The remote host supervises its own worker  (N)

**Decision:** The remote host's own planwright runs the launcher and the
stream-json supervisor; this host only calls its verbs. The remote root is
resolved on the remote host, and its version is checked before a dispatch.

**Alternatives considered:**
- Run the supervisor here and carry the worker's stdio over a long-lived SSH
  session. Rejected because: an SSH drop would kill or orphan the worker, and
  the journal, fifo answers and recovery would all need a remote twin.
- Copy this host's scripts to the remote per call. Rejected because: the
  remote's hooks and guards must be its installed copy, the one Claude Code
  loads there.

**Chosen because:** the supervisor already detaches, journals every request
and survives its caller; reaching it by verb keeps one authority per worker.

### D-4: A fixed-verb, quoted, batch-mode channel  (N)

**Decision:** One near-side script owns every remote call: a fixed verb set,
each argument single-quoted and refused when it holds a backslash or a control
character (so sh, bash, zsh and fish all read it the same), free text over
stdin into a remote temp file, SSH in batch mode with no terminal.

**Alternatives considered:**
- Let callers compose `ssh <alias> <command>`. Rejected because: SSH joins its
  arguments into a remote shell string, so every caller would re-solve quoting
  and the guard could not tell a routine call from an arbitrary one.
- A general remote-exec verb. Rejected because: an approved planwright script
  that runs any command would be an approval bypass.

**Chosen because:** it is the smallest surface that is both safe to approve
and enough for the recipe; the shipped `scripts/fleet-remote.sh` is its first
form.

### D-5: A local dispatch record routes later verbs  (N)

**Decision:** Each remote dispatch writes a record in this host's fleet home
(host alias, remote worker, unit, branch, dispatch time). Status, steer,
answer, stop, retire and cleanup read it to route to the right host, and the
fleet status view lists remote workers with their host.

**Alternatives considered:**
- Ask every registered host on each call. Rejected because: it multiplies SSH
  calls and cannot tell which host owns a worker name reused across hosts.

**Chosen because:** routing needs one lookup, and the record is the inventory
cleanup already expects.

### D-6: Remote liveness is remote evidence only  (N)

**Decision:** No local check reads a remote pid. A remote worker's state comes
from the remote status verb; a failed SSH call yields `unreachable`, and only
after the host's grace period does the worker read as lost.

**Alternatives considered:**
- Treat an unreachable host as a dead worker. Rejected because: a sleeping
  laptop or a network blip would trigger relaunches of live work.

**Chosen because:** every local liveness check tests pids on its own host, so
pointing one at a remote worker would read it as dead.

### D-7: This host's mission control vets remote prompts  (Q)

**Decision:** Remote requests join this host's vetting loop: each pass reads
every registered host's pending view through the channel and answers through
it; the alarm and the wake relay cover them too.

**Alternatives considered:**
- A mission control on the remote host vets its own workers. Rejected
  because: it is the second mission control the operator put behind this
  option, and it splits one program's approvals across two sessions.

**Chosen because:** one place approves everything for the program. Waits on
the operator's answer.

### D-8: A shared host is free when idle, with a hold switch  (Q)

**Decision:** A host marked shared takes new work only after its input has
been idle for a configured time (input idle time, read on the host), and a
machine-local hold switch keeps all new work off it. While it runs a worker
it is kept awake by the platform's own mechanism (`caffeinate` on macOS).
Running workers are not stopped when the owner returns.

**Alternatives considered:**
- Fixed hours. Rejected because: it ignores whether the owner is actually
  there.
- No check. Rejected because: the standing rule says the computer is used
  only when its owner is not using it.

**Chosen because:** idle time is the direct signal, and the switch covers what
it misses. Waits on the operator's answer.

### D-9: The guard approves the channel's verbs like the local ones  (Q)

**Decision:** The command guard approves `scripts/fleet-remote.sh` under the
resolved literal root, in the sessions that already approve the local
stream-json verbs, for its fixed verbs only; any other command reaching a
remote host falls to the normal prompt.

**Alternatives considered:**
- Prompt on every remote call. Rejected because: the vetting loop would ask
  the operator on every pass, which is the stall the channel exists to end.

**Chosen because:** the channel's verbs do on the remote exactly what the
approved local verbs do here. Waits on the operator's answer, because it
changes a guard.

### D-10: Branches travel through the hosting remote  (S)

**Decision:** The remote worker pushes its branch and opens its pull request
from the remote clone; nothing moves git objects between the two hosts.

**Alternatives considered:**
- Fetch the remote worktree over SSH into a local branch. Rejected because:
  it creates a second copy of every branch and a second push path.

**Chosen because:** review, step records and the ready flip already run
against the pull request.

### D-11: Remote login is the remote host's own  (Q)

**Decision:** The remote host's model-provider login and repository
credentials are set up there by the operator; for a macOS host whose keychain
an SSH session cannot open, the documented setup is a long-lived token
(`claude setup-token`) in an untracked, owner-only file the remote
environment file loads. The channel never carries a credential.

**Alternatives considered:**
- Unlock the keychain over SSH. Rejected because: it needs the login password
  in a non-interactive session.
- Send this host's token. Rejected because: it would be the wrong account and
  a credential on the wire.

**Chosen because:** it keeps each account's login on its own host. Waits on
the operator's answer.

### D-12: Capacity is read on the host it describes  (N)

**Decision:** A remote dispatch reads the remote host's load average, core
count and free memory through a channel verb and applies the local dynamic
limit's rule, capped by the host's worker ceiling.

**Alternatives considered:**
- One fleet-wide ceiling. Rejected because: the hosts differ in size, and a
  busy host would block an idle one.

**Chosen because:** the local rule already exists; only its input moves.

### D-13: Usage is per account, read where the account runs  (N)

**Decision:** Each host's account is a usage subject. A remote host's usage
comes from its own status-line mirror when present, else from the newest
rate-limit readings its workers recorded; the hard stop applies per account.

**Alternatives considered:**
- Gate every dispatch on this host's account. Rejected because: the second
  account would never be used once the first neared its stop.

**Chosen because:** the operator has two accounts to use in full, and each
host's signals already exist on that host.

### D-14: The remote rung in the capability contract  (N)

**Decision:** The contract gains a remote rung that advertises the remote
supervisor's capabilities (survives the placing session, runs beyond it,
observable through the channel, not human-attachable) plus a host property,
present only for registered, reachable hosts. It runs the same profile,
guards and cadence as local work.

**Alternatives considered:**
- Treat a remote host as an attribute of the existing stream-json rung only.
  Rejected because: placement selects by advertised set, and reachability
  and per-host capacity are properties local stream-json does not have.

**Chosen because:** selection by capability keeps the axioms unchanged and
makes the host a visible part of every report.

### D-15: Placement prefers the account with more weekly room  (Q)

**Decision:** Among hosts with room, a session-grade unit goes to the host
whose account has the most weekly usage left; on a tie, this host. The
operator can pin a unit or a program to a host.

**Alternatives considered:**
- Local first, remote only when local is full. Rejected because: the second
  account would sit idle on light weeks.
- Round robin. Rejected because: it ignores usage, the scarce resource.

**Chosen because:** the standing rule is to use both accounts in full each
week. Waits on the operator's answer.

## Cross-cutting concerns

- **Security.** The channel is the one new path to another machine. Its alias
  check blocks SSH option injection, its fixed verbs block arbitrary
  execution, and its quoting blocks remote re-parsing; the guard approves it
  only by its resolved literal path.
- **Portability.** The remote may be macOS (bash 3.2, BSD tools) or Linux;
  the remote program is POSIX sh and runs the remote host's own scripts,
  which CI already exercises on macOS and Alpine.
