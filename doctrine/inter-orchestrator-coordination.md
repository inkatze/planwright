# Inter-Orchestrator Coordination

This doctrine turns the tmux operator's hand-relay protocol between towers and
workers into an enforceable capability with two parts: an explicit **division
of labor** and an **attributed, non-impersonating relay**, which reaches a
live, busy worker by messaging. One audited script, `scripts/orchestrate-relay.sh`,
enforces the relay's mechanics and delegates every messaging post to
`scripts/fleet-messaging.sh`, the messaging enforcement point the
[Messaging Transport](messaging-transport.md) doctrine names.

Citations: orchestration-fleet REQ-D1.2 (division of labor), orchestration-fleet
REQ-D1.3 (attributed, non-impersonating relay), orchestration-fleet REQ-B1.7
(relay/spawn security bounds), orchestration-fleet REQ-A1.6 (fleet-artifact data
hygiene) · orchestration-fleet D-7, tower-comms D-12 · fleet-messaging REQ-C1.7,
REQ-G1.4, REQ-G1.7, REQ-G1.8, REQ-G1.9, D-13, D-14, D-27, D-29.

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
- **The meta-tower** owns cross-spec *selection* under the fleet bound, then
  runs the chosen spec's single-spec step itself: it takes that spec's
  per-spec lock, so a single-spec tower on the same spec excludes it, writes
  the dispatch record, and edits no other tower's or worker's branch state.

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

A tower steers a **live, busy worker mid-task** by messaging, read between
its tool calls, and observes it by a read. The relay discipline keeps the
worker's authorization boundary intact.
**Tower-to-worker** relay is attributed in every form below, which is what keeps
it non-impersonating. **Tower-to-tower** coordination between peer towers (for
example, reconcile-then-quick-PR hand-offs) is an advisory under the
[Messaging Transport](messaging-transport.md) doctrine's advisory rule: the
tower's model sends it through the harness's message tool, it never claims,
releases, or resolves a unit of work, and with messaging absent it is not sent
rather than pasted.

### A listed peer gets a direct message; the paste is the fallback

When the target is a Claude Code session the tower's `ListAgents` lists, the
tower messages it with `SendMessage`: the harness delivers an attributed
message, queued while the peer is mid-turn, and nothing touches its input box.
The pane relay below is only for a target that is not listed (another host, a
harness without peer messaging, a pane that is not Claude Code), and never
for a peer tower, whose advisory is not sent instead. When the
two tools are deferred, the tower loads their schemas (`ToolSearch`) and calls
`ListAgents` before deciding; a listed peer that `SendMessage` cannot reach
counts as unlisted. The choice is the model's: a
script can list sessions (`claude agents --json`) but has no documented way
to send to one. Nobody types or pastes into a pane by hand.

### Steer-in-flight: messaging first, buffer-paste the fallback, never `send-keys`

A steer or a decision answer reaches an eligible worker as a message first:
`fleet-messaging.sh send --to-worker <handle>`, called by the relay's messaging
arm and by `fleet-decision.sh`, so the harness delivers it attributed and
nothing touches the input box. The messaging-transport doctrine's per-path
table governs each rung: a `stream-json-persistent` decision answer is always
the supervisor's control response, and a `headless-oneshot` worker receives no
downward delivery. When the sending session's probe reads absent, the worker
has no recorded inbox, or the post is refused or fails, delivery falls back to
the rung's attributed steer delivery, that table's fallback ladder; a held post
is not a failure and is never descended.

On `tmux` that fallback is a **buffer-paste** mechanism (`load-buffer` then
`paste-buffer`); every other rung takes the fallback its table row names. The
paste is clearly **marked as tower-originated** so the worker can tell a
relayed instruction from its own reasoning or the human's. The relay **never**
uses `send-keys`-style impersonation — typing into a worker's input line as if
the human typed it: an authorization decision made by screen-scraping with no
audit trail (the rejection bootstrap D-38 made).

`relay-command` tries its messaging arm, which posts through
`fleet-messaging.sh`, before any paste; on the fallback,
`scripts/orchestrate-relay.sh relay-command tmux <handle> <message-file>` emits
the paste: the script's own `deliver` step, whose paste carries a fixed
attribution header, with the message body left in its file (see data
discipline below). It has no `send-keys` path by construction, and a source
audit (its test) proves the code contains none.

**The paste relay's contract.** The paste serves only where messaging cannot
deliver: the ladder's fallback step, the redelivery paste included, and an
in-pane target a message cannot reach (a dialog waiting in the pane, never a
permission prompt; a slash command). A relay is **one short pointer line**
(`… read <absolute message file>`) with no trailing newline, the payload in
that file, since a multi-line paste becomes a `[Pasted text]` placeholder
blocking every later paste: the paste stages the line and never submits it
unattended. One Enter from a human submits it; a paste into a busy worker
queues behind its turn. `deliver` reads the pane only to guard and confirm
the paste, refusing (exit 3) while a selection prompt, a staged placeholder,
or an earlier relay holds the input box.

Each relay leaves a **pending relay** record stamped with its emit time,
cleared only by a strictly later stamp from the worker's `UserPromptSubmit`
hook, never by a tool use or the pane, and dropped at session end. The tower
checks after every paste, a bounded window later, reading that hook evidence,
never the pane: a pending relay is raised to the operator as its own
attention item, whatever the worker's row reads, until it clears, and is
never re-pasted (`relay-command tmux` refuses meanwhile). An interrupt stays
the operator's: no relay path sends a keystroke. The handle is explicit
(operator-named), never the active pane. `relay-command stream-json`
instead emits `fleet-streamjson.sh steer`: a user turn on the worker's own
stdin, a real submit with a receipt row — the unattended path.

### Observe-in-flight: capture-pane, a read never a write

Status is read by **capture-pane** (or the backend's observe-in-flight
equivalent) — a read of the worker's surface, never a write to it.
`orchestrate-relay.sh observe-command tmux <handle>` emits the `capture-pane -p`
read. The captured text is then classified by the tower as **data** (see below).

### Never answer a worker's permission prompt on the tower's judgment

The tower **never** answers a worker's **harness permission prompt** — the
tool-permission gate — on its own judgment. That gate is the human's: a prompt
falling strictly inside the operator's written standing decision is recorded as
the operator's answer, naming the rule; every other prompt reaches the operator.
This is distinct from a routine *question a worker addresses to the tower*, which
the [Autonomous-Safe-Decision Policy](autonomous-safe-decision.md) may answer
unattended. The sanctioned way to remove *routine* prompts is the shipped
worker-settings profile (`config/worker-settings.json`), which a human installs.

## The supervisor duty

The session that dispatched a worker, its **supervising session**, stays that
worker's operator until the work is finished: the orchestrator for a task
unit, the `/tower` session for a flight (the format glossary's transitional
note). The question message
and the already-idle re-arm reach task workers only, so their handling is
`/orchestrate`'s. The supervising session:

- answers the worker's questions from the task, the spec, and the code;
- answers an in-task prompt it could act on itself;
- relays to the operator only what it cannot answer or what is the
  operator's to decide (a genuine fork, consent, sign-off), and carries the
  answer back to the worker;
- never hands a worker over for the operator to attend unless the operator
  asks.

Two bounds hold. It never answers a harness permission prompt on its own
judgment, and every answer it gives unattended stays inside the
[Autonomous-Safe-Decision Policy](autonomous-safe-decision.md). How a
question that reaches the operator is queued, settled, and delivered is
the [Tower Conversation](tower-comms.md) doctrine's.

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
transient (messaged or buffer-pasted, not committed), but any relay content that lands in a
committed log or a PR body is subject to the same rule.

## How this relates

The [Backend Capability Contract](backend-capability-contract.md) defines the
observe-in-flight and steer-in-flight capabilities this relay consumes; a
backend that does not advertise them cannot host an in-flight relay, and the
tower falls back to the completion-notification surface. The
[Autonomous-Safe-Decision Policy](autonomous-safe-decision.md) draws the line
this doctrine depends on — a worker's *permission prompt* versus a routine
*question to the tower*. The
[Messaging Transport](messaging-transport.md) doctrine owns the message channel
the relay tries first and its fallback table. The
[Security Posture](security-posture.md) is the parent of the security bounds
above.
