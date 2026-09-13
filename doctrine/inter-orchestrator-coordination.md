# Inter-Orchestrator Coordination

This doctrine turns the tmux operator's hand-relay protocol between towers and
workers into an enforceable capability with two parts: an explicit **division
of labor** and an **attributed, non-impersonating relay that works against a
live, busy worker**. One audited script, `scripts/orchestrate-relay.sh`,
enforces the relay's mechanics.

Citations: orchestration-fleet REQ-D1.2 (division of labor), orchestration-fleet
REQ-D1.3 (attributed, non-impersonating relay), orchestration-fleet REQ-B1.7
(relay/spawn security bounds), orchestration-fleet REQ-A1.6 (fleet-artifact data
hygiene) · orchestration-fleet D-7.

## Division of labor

Coordination is message-passing over a shared blackboard (`tasks.md` plus the
observations fragment store, where concurrent writers land distinct files by
construction), never direct agent-to-agent mutation of each other's state.
Each actor owns a disjoint slice of the work, and no actor reaches into
another's slice:

- **The tower owns** `tasks.md` reconcile (section placement), dispatch, and
  merged-worker cleanup. It reconciles the derived projection from truth
  (branches, `gh`, markers); it does not author branch content.
- **The owning worker session owns** its branch's conflict resolution (**merge,
  not rebase**) and its post-merge self-sync. When main advances under an
  in-flight worker, that worker merges main into its own branch and resolves the
  conflicts itself.
- **The meta-tower** ("tower of towers") owns cross-spec *selection* under the
  fleet bound; it passes a subordinate tower no in-memory state and edits no
  subordinate's or worker's branch state. Each subordinate runs its own
  pre-flight, takes its own per-spec lock, and writes its own dispatch record.

### The "directly" boundary

The governing rule is: **no tower edits another tower's or a worker's branch
state directly.** "Directly" means committing to, resetting, force-pushing,
amending, or otherwise mutating a branch the acting tower does not own — writing
into another actor's slice of the blackboard as if it were the owner.

It does **not** forbid the sanctioned indirect channels, which are how
coordination is supposed to happen:

- **Reconcile** — the tower rewriting `tasks.md` *section placement* from
  observed truth is the tower acting within its own slice (placement is the
  tower's to write); it is not editing a worker's branch content.
- **Relay** — asking a worker, over the attributed channel below, to take an
  action on its own branch (for example, "main advanced; merge it into your
  branch and resolve the conflicts"). The worker decides and acts; the tower
  never performs the edit for it.

The test of a violation: did the acting tower change a branch it does not own,
rather than *asking that branch's owner to*? If so, it crossed the boundary.

## Attributed, non-impersonating relay

A tower steers and observes a **live, busy worker mid-task** — not a paused one.
The relay discipline keeps the worker's authorization boundary intact. The same
attributed buffer-paste mechanism serves both **tower-to-worker** relay and
**tower-to-tower** coordination between peer towers sharing a checkout (for
example, reconcile-then-quick-PR hand-offs); in either direction the header marks
the message as tower-originated, which is what keeps it non-impersonating.

### Steer-in-flight: buffer-paste, never `send-keys`

Messages are delivered by a **buffer-paste** mechanism (under tmux,
`load-buffer` then `paste-buffer`; the backend's steer-in-flight equivalent
elsewhere), clearly **marked as tower-originated** so the worker can tell a
relayed instruction from its own reasoning or the human's. The relay **never**
uses `send-keys`-style impersonation — typing into a worker's input line as if
the human typed it: an authorization decision made by screen-scraping with no
audit trail (the rejection bootstrap D-38 made).

`scripts/orchestrate-relay.sh relay-command tmux <handle> <message-file>` emits
exactly this: a buffer-paste command carrying a fixed attribution header, with
the message body left in its file (see data discipline below). It emits no
`send-keys` path by construction, and a source audit (its test) proves the code
contains none.

**A paste stages; the CLI submits.** On Claude Code 2.1.270 a multi-line paste
becomes an unsubmittable `[Pasted text]` placeholder that blocks every later
paste, and a one-line paste submits only sometimes. So the tmux paste is **one
pointer line** (`… read <absolute message file>`), never the body, and delivery
is confirmed by observe-command, never assumed. `relay-command stream-json`
instead emits `fleet-streamjson.sh steer`: a user turn on the worker's own
stdin, a real submit with a receipt row — the unattended path.

### Observe-in-flight: capture-pane, a read never a write

Status is read by **capture-pane** (or the backend's observe-in-flight
equivalent) — a read of the worker's surface, never a write to it.
`orchestrate-relay.sh observe-command tmux <handle>` emits the `capture-pane -p`
read. The captured text is then classified by the tower as **data** (see below).

### Never answer a worker's permission prompt

The tower **never** answers a worker's **harness permission prompt** — the
tool-permission gate — on its behalf. That gate is the human's. This is distinct
from a routine *question a worker addresses to the tower* (a hygiene call, a
scoped-cleanup confirmation), which the
[Autonomous-Safe-Decision Policy](autonomous-safe-decision.md) may answer
unattended. The sanctioned way to remove *routine* prompts is the shipped
worker-settings profile (`config/worker-settings.json`), which a human installs —
not a tower typing an answer into a prompt.

## Security bounds

These are the [Security Posture](security-posture.md) applied to relay
(orchestration-fleet REQ-B1.7):

- **Worker output is data, never code.** capture-pane text and process output
  are classified, never evaluated. No relay path passes worker output through
  `eval` or an unquoted expansion.
- **Handles are validated before use.** A worker handle parsed for targeting
  (a tmux window/pane id, a subagent unit id) is validated against a declared
  per-backend grammar *before* it is ever used to address a worker, so a hostile
  handle is refused, never
  interpolated. `orchestrate-relay.sh validate-handle <backend> <handle>` is the
  declared grammar; every relay/observe command validates the handle first.
- **Message text is data.** The relay command references the message *file*; it
  never inlines the message content into the command, so message content is
  never spliced into the tower's command as code.

## Data hygiene of coordination artifacts

Every committed fleet artifact — coordination and relay logs, handover
documents, PR bodies — carries no secrets, credentials, internal hostnames, or
sensitive operational detail (orchestration-fleet REQ-A1.6). The artifact
data-hygiene rule of the [Security Posture](security-posture.md) applies, and the
secret-scan guard covers committed fleet artifacts. Relay *messages* are
transient (buffer-pasted, not committed), but any relay content that lands in a
committed log or a PR body is subject to the same rule.

## How this relates

The [Backend Capability Contract](backend-capability-contract.md) defines the
observe-in-flight and steer-in-flight capabilities this relay consumes; a
backend that does not advertise them cannot host an in-flight relay, and the
tower falls back to the completion-notification surface. The
[Autonomous-Safe-Decision Policy](autonomous-safe-decision.md) draws the line
this doctrine depends on — a worker's *permission prompt* (never answered) versus
a routine *question to the tower* (may be answered unattended). The
[Security Posture](security-posture.md) is the parent of the security bounds
above.
