# The attention/notification capability

planwright's fleet has two seams (D-12): the **execution substrate** (how workers
are hosted, addressed, observed, steered) and the **attention surface** (what the
human watches). The [backend capability
contract](backend-capability-contract.md) is the execution seam lifted into core.
This doc is its counterpart: the **attention/notification capability** lifted into
core, so a marketplace-install user gets a legible default surface without any
dotfiles-local mechanism (no `~/.claude/inbox/`, no personal statusline, no
tmux-popup script).

The load-bearing idea (D-13): the human's load scales with the number of
**actionable decisions**, not the number of workers. A worker-event stream floods;
a decision *queue* — bounded by the `## Awaiting input` count, every surfaced item
actionable — is the mature discipline (ISA-18.2 alarm rationalization, Sheridan
supervisory control) that agent tooling generally ignores.

## The four parts

The capability is four cooperating pieces, all implemented by
[`scripts/fleet-attention.sh`](../scripts/fleet-attention.sh):

- **Heartbeat / awareness state.** A per-worker current-state store, keyed by
  worker handle: the worker's scope (spec + unit), its state, a commit-time
  heartbeat timestamp, and — when it is blocked — the structured decision it waits
  on. It is a *state store*, not a log: one row per worker, last write wins
  (`heartbeat`, `decide`, `clear`).
- **The portable status renderer** (`render`). Lists each worker's scope and
  state. It is substrate-agnostic: it reads the store, so it renders identically
  from a plain terminal, a detached-multiplexer popup, or an editor panel.
- **The decision queue** (`queue`). One ordered queue of the **actionable** items
  across all active specs — the workers in the `awaiting-input` state — each
  rendered as a structured choice (scope, question, recommended default, options).
  Non-actionable signal (working / pr-ready / merged / done) is suppressed. Its
  length tracks the `## Awaiting input` count, not the worker count.
- **The notification seam** (`notify`). Pushes a one-line summary through the
  resolved channel. The seam is core; the specific channel is the overlay value
  (below).

### The worker states

A worker's scope pairs with one of five states:

- **`working`** — executing; not actionable.
- **`awaiting-input`** — blocked on a human decision. This is the one state that
  carries a structured decision, so it is set only by `decide`, never by a bare
  `heartbeat`. Each `awaiting-input` record is one decision-queue item and mirrors
  one `## Awaiting input` entry in the owning spec's `tasks.md`.
- **`pr-ready`** — a draft PR is up; the human's reserved review/merge is pending,
  but planwright surfaces it as status, not as a queue decision (merge is never a
  planwright action).
- **`merged` / `done`** — terminal; surfaced as status, then cleared on teardown.

Only `awaiting-input` is actionable, which is what makes the queue length track
the `## Awaiting input` count rather than the worker count.

## Alarm rationalization

The queue is ordered, not just filtered — every surfaced item is actionable and
ranked by consequence:

- **Priority first.** Each decision carries a priority (`high` / `normal` / `low`,
  default `normal`); higher priority sorts first.
- **Oldest-waiting first within a priority.** The commit-time heartbeat breaks
  ties, so the decision that has waited longest surfaces ahead of a newer one at
  the same priority.

This is the ISA-18.2 posture: suppress the non-actionable, prioritize the rest by
consequence, and never let signal volume scale with fleet size.

## Built on the cross-spec home, not beside it

The attention capability does not resolve its own durable home or invent its own
lock. It **consumes** the Task 9 cross-spec fleet-state substrate
([`scripts/fleet-state.sh`](../scripts/fleet-state.sh); D-11): `root` resolves the
`${CLAUDE_PLUGIN_DATA}`-chain home, and `lock` / `unlock` are the named advisory
primitive. The attention store lives at `<fleet-home>/attention/`, so
heartbeat/registry state lives under the same cross-spec home the meta-tower's
accounting uses, and every mutating write is serialized through the same lock
(reads see an atomically-renamed complete file, never a torn one). No attention
path ever writes into the sibling's spec-local `.orchestrate/` dir — that is
`orchestration-concurrency`'s per-spec territory.

## The notification channel is the overlay value

`notification_channel`
([`docs/options-reference.md`](../docs/options-reference.md); resolved through
[`scripts/resolve-notification-channel.sh`](../scripts/resolve-notification-channel.sh))
is the capability-vs-style split: the notification *seam* is a core capability;
the specific *channel* is overlay-owned, resolved through the four config layers.

- **`none`** (default) — pull-only. Nothing is pushed; the operator reads the
  decision queue on demand. Dependency-free and behavior-preserving, so it is the
  safe default the unread config resolves to.
- **`tmux-popup`** — a multiplexer popup (the multiplexer-user persona).
- **`os-notify`** — an OS notification (the non-terminal-user persona).
- **`editor-toast`** — an editor toast the editor tails (the editor-feedback
  persona).

The channel adapters treat the summary as data: it is stripped of control bytes,
and each adapter passes it so that no format specifier, AppleScript string, or
shell metacharacter in the summary can execute. A channel whose tool is absent
degrades to leaving the item in the queue rather than failing the run.

## Deferring to a backend's own surface

A backend may advertise `provides_attention_surface: true` (backend capability
contract): it renders the operator's queue itself (a cmux-class tool). When that
signal is present — passed per-call as `--surface-provided`, or ambient via
`PLANWRIGHT_ATTENTION_SURFACE_PROVIDED` — planwright **suppresses its own** `render`
and `queue` output and defers, so the operator sees one attention surface, not
two. This is the attention-seam half of the same adapt-to-advertised discipline
the execution seam follows: planwright reacts to the advertised set, never to the
backend's name.

## Data hygiene (REQ-A1.6)

Every attention artifact is committed-artifact-adjacent and follows the
[security-posture](security-posture.md) framework-script rules. Worker and scope
handles are validated against the Task 9 field grammar, and decision text against
a control-free text grammar, **before** any write — a traversal token, an embedded
tab or newline, or a control byte is refused rather than tearing the store or
escaping a path. Rendered output is stripped of C0/DEL through the canonical
echo-discipline sanitizer, so even a hand-corrupted store line cannot drive the
terminal. No secret-shaped content, internal hostname, or sensitive operational
detail belongs in a heartbeat, a decision, a toast, or a rendered surface.
