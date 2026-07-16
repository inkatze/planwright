# Fleet Autonomy — Design

**Status:** Ready
**Last reviewed:** 2026-07-14
**Format-version:** 2
**Execution:** derived — see the status render

Origin-tag legend: **N** — new to this bundle. **C, `<spec> D-<n>`** — carried: this bundle
reuses an existing decision from the named sibling spec rather than inventing a parallel one.

## Decision log

### D-1: Push-first liveness, periodic reconcile as the correctness backstop (N)

**Decision:** Worker state transitions are pushed via native Claude Code hook events the instant
they occur — `Stop` (working→idle), `PermissionRequest` (working→awaiting-human), the next
`PostToolUse` after a pending `PermissionRequest` (awaiting-human→working, inferred), `SessionEnd`
(session termination), and `StopFailure` (turn ended on an API error) — wherever the dispatch
backend supports hook registration. *(Amended at kickoff walkthrough 2026-07-14: "idle/done"
reworded to "idle" — "done" was shorthand for the existing merged-and-idle cleanup case, not a
distinct liveness state.)* The health watchdog's periodic sweep is retained regardless,
reconciling state from ground truth (git, process, heartbeat-file evidence) so a missed hook fire,
a failed write, or a dropped event self-heals on the next sweep rather than silently persisting.

**Alternatives considered:**
- Tower-side polling only (the status quo: the tower calls `fleet-attention.sh heartbeat` itself
  after observing a worker). Rejected because: this is poll-then-record, not push — it still costs
  a tower's attention every step, which is exactly the mechanical load this bundle exists to
  eliminate.
- Push-only, no reconcile backstop. Rejected because: Anthropic's API fails transiently, hook
  scripts can themselves error, and a write can be lost — a push-only design has no self-healing
  path for a missed event. This mirrors systemd's own posture (`Type=notify`/`WatchdogSec`): even
  a push-based liveness mechanism needs a passive timeout as the correctness floor.
- A permission-resolution hook for the awaiting-human→working transition. Rejected because: no
  such hook exists (confirmed against `hooks.md`'s full event list and cross-checked by an
  independent fetch) — `PermissionDenied` fires only for the auto-mode classifier, never for a
  human's response. The next `PostToolUse` firing after a pending `PermissionRequest` is the best
  available inference, documented as inference rather than a direct signal.

**Chosen because:** push is strictly better latency than poll wherever a real hook event exists,
and the reconcile-from-ground-truth backstop is the same level-triggered pattern
`orchestration-concurrency` already uses for `tasks.md` state — pairing push for speed with
reconcile for correctness, never trusting either alone.

### D-2: Idle / hung / awaiting-human / flailing as four distinct states (N)

**Decision:** A worker's state is exactly one of `working`, `idle`, `hung`, `awaiting-human`, or
`flailing`. `flailing` is new: heartbeating (harness responsive) with no forward progress (no new
commit, no state change) across a configured threshold — distinct from `hung` (heartbeat stopped
entirely). A `flailing` classification escalates to a human decision; it is never resolved by an
automatic nudge or restart.

**Alternatives considered:**
- Collapse `flailing` into `hung`. Rejected because: a process that is alive and responsive but
  looping unproductively (the same failing test, no commits) needs a different response than a
  genuinely dead process — restarting a flailing worker just restarts the same loop, while a
  design fork ("this task may be stuck") is what actually resolves it.
- Nudge a flailing worker automatically before escalating. Rejected because: a nudge risks
  becoming injected chatter into the worker's context to check aliveness, which is the exact
  clutter this bundle's actionable-to-towers-not-workers principle rules out; re-verifying via
  capture-pane is the only pre-escalation action taken.

**Chosen because:** the failure modes are genuinely different (dead process vs. unproductive
cognition), and conflating them would either restart-loop a stuck worker pointlessly or delay
escalating a genuinely dead one.

### D-3: Escalating crash-loop backoff with a disable threshold (N)

**Decision:** A worker that crashes and is relaunched repeatedly backs off on an escalating
schedule and is disabled after a configured consecutive-failure threshold, escalating to a human
decision rather than restart-looping indefinitely.

**Alternatives considered:**
- Instant restart on every crash, no backoff. Rejected because: this is the exact hot-loop failure
  mode PM2's `min_uptime`/`exp-backoff-restart-delay` and supervisord's `startretries` both exist
  to prevent — a transient failure that instantly re-triggers can pin a host in a crash loop.
- No disable threshold (back off forever). Rejected because: an unbounded backoff never surfaces a
  genuinely broken task to a human; it just gets quieter about failing.

**Chosen because:** this is a directly-precedented pattern (PM2, supervisord, and
`claude_code_agent_farm`'s own 3-consecutive-error disable threshold all converge on the same
shape) — proportionate, well-understood, and cheap to implement as deterministic backoff logic.

### D-4: Mode-aware tower-liveness recovery (N)

**Decision:** Ungraceful tower death is recovered differently depending on whether the tower was
running unattended or interactively-led. For an **unattended** tower (`--watch`), an external,
cron-scheduled check (never another Claude Code tower) verifies a live process exists whenever
ready work exists, and on positive evidence of death launches a fresh, memoryless tower via the
existing `continue-as-new` auto-heal handover. For an **interactively-led** tower, a `SessionStart`
hook (`source: "startup"`) detects an orphaned tower marker and surfaces the exact
`claude --resume <session-id>` command to the human — never auto-resuming, never auto-discarding.

**Alternatives considered:**
- One recovery path for both modes (always cold-restart a fresh tower). Rejected because: an
  unattended tower never held meaningful undisclosed intent, so a memoryless rebuild is lossless —
  but an interactively-led tower's actual conversation (the human's in-progress reasoning) is not
  recoverable from `tasks.md`/git state at all. Confirmed via Claude Code's own documentation that
  `--resume`/`--continue` restore the full transcript even after a hard crash, which a disk-only
  rebuild discards for no reason when the mode is interactive.
- Have another tower watch the tower (recursive watchdog). Rejected because: this is unbounded
  regress — who watches the watcher's watcher? The dead-man's-switch pattern from process
  supervision (systemd's watchdog, healthchecks.io-style external heartbeat monitors) resolves this
  by making the outermost check a dumb, external, always-firing mechanism, never another instance
  of the thing being watched.
- Auto-resume the interactive session on the daemon's own initiative. Rejected because: no cron or
  daemon can resume a human's conversation — only the human can meaningfully continue it; silently
  resuming into an unknown state without the human present is worse than surfacing the exact
  command and letting them choose.
- Detect "clean exit vs. crash" from Claude Code's own session metadata. Rejected because: no such
  signal is documented or exposed (confirmed directly against `hooks.md`/`sessions.md`) — the only
  reliable signal is tracking the wrapping OS process externally (a PID/heartbeat marker), which is
  what this decision actually does.

**Chosen because:** the two failure classes have genuinely different correct answers, and Claude
Code's own real, documented capabilities (`--resume`, the `SessionStart` `source` field) map onto
them cleanly without inventing anything fragile.

*(Amended at kickoff walkthrough 2026-07-14: the unattended-tower relaunch path now backs off and
disables on repeated failure, per REQ-A1.9 — see the added alternative below.)*

**Alternatives considered (added at kickoff):**
- No backoff on relaunch — the cron check simply relaunches on every tick it finds the tower dead.
  Rejected because: this was an oversight surfaced during the kickoff requirements walkthrough, not
  a considered choice — a tower that crash-loops (a bad config, a broken environment) would
  otherwise be relaunched forever with no human escalation, exactly the failure mode D-3 already
  exists to prevent for workers. REQ-A1.9 extends D-3's escalating-backoff-then-disable pattern to
  the tower-relaunch path instead of leaving an unexplained asymmetry between worker and tower
  crash handling.

### D-5: Positive-evidence-of-death as the shared kill/cleanup/restart predicate (C, orchestration-fleet D-2)

**Decision:** Every mechanism in this spec that kills, cleans up, or restarts a resource reuses
`orchestration-fleet`'s existing `positive-evidence-of-death` capability predicate rather than
inventing a parallel staleness check per mechanism.

**Alternatives considered:**
- A per-mechanism timeout heuristic (each of idle-cleanup, stale-window-cleanup, and the
  tower-liveness watchdog invents its own "stale after N minutes" rule). Rejected because: this is
  the exact class of mistake the fleet has already made once — the `2026-06-12` incident where a
  dead tmux socket plus a truncated process listing mimicked dead workers that were in fact alive,
  because the sweep didn't distinguish lost observability from observed death.
- Let the LLM classify aliveness from ambiguous signals. Rejected because: this is precisely the
  no-LLM-daemon-mechanics floor (D-18) this bundle carries — a destructive action needs a
  deterministic, positive signal, not a judgment call.

**Chosen because:** one predicate, reused everywhere destructive action is possible, is both
safer (the lesson is only learned once) and cheaper (no parallel implementation to drift).

### D-6: Deterministic-script-only cleanup, self-targeting-guarded (N)

**Decision:** Stale window/pane/worktree cleanup runs as deterministic script logic, never
in-context model judgment, and explicitly refuses to target the process's own hosting session.

**Alternatives considered:**
- Let the tower's own LLM reasoning decide what to clean up (the historical pattern this spec
  displaces). Rejected because: a real, documented postmortem
  (`anthropics/claude-code#29787`) shows an LLM-driven cleanup non-deterministically issuing
  `tmux kill-session` against its own hosting pane, destroying the entire session. Cleanup
  decided by model judgment is not hypothetically risky; it has already happened.

**Chosen because:** deterministic code with an explicit self-targeting guard closes the exact
documented failure mode rather than trusting a model not to repeat it.

### D-7: `WorktreeCreate`/`WorktreeRemove` hook-driven worktree lifecycle tracking (N)

**Decision:** Worktree lifecycle is tracked via the `WorktreeCreate` and `WorktreeRemove` hook
events (creation via `--worktree`/`isolation: "worktree"`; removal at session exit or subagent
finish) rather than periodic disk scanning, wherever the backend supports hook registration.

**Alternatives considered:**
- Periodic filesystem scan for orphaned worktree directories (the only option before this hook
  pair was confirmed to exist). Rejected because: a scan can only ever notice staleness after the
  fact, on whatever cadence it runs; a hook fires exactly when the lifecycle event happens.

**Chosen because:** this closes a gap discovered mid-design (the hook pair wasn't part of the
original facet list) at zero additional mechanism cost — it's the same push-first principle as
D-1, applied to a resource this bundle already needs to track.

### D-8: Dirty-tree sweep scope — every tracked working tree, including the tower's own checkout (N)

**Decision:** The periodic sweep for stale uncommitted/unpushed diffs covers every worker
worktree *and* the tower's own checkout, on whatever branch it is currently on — not just worker
worktrees.

**Alternatives considered:**
- Worker worktrees only (workers already have a documented post-merge self-sync ritual).
  Rejected because: the motivating incident (a tower directly editing a config file and opening
  its own PR, per the doctrine-gap(tower-role) observation) happened on the *tower's* checkout, not
  a worker's — narrowing the sweep to workers would miss the exact case that prompted this
  requirement.
- No sweep at all; rely on the tower non-authoring boundary (D-17) to prevent the problem instead
  of catching it. Rejected because: a policy floor and a safety net are complementary, not
  redundant — D-17 reduces how often a tower edits directly; this sweep catches it when it happens
  anyway (including the graceful-handoff blind spot where a retiring tower's in-flight edit was
  never committed before it handed off).

**Chosen because:** the auto-heal handover's "rebuild from disk" model assumes disk state is
clean and attributable; this sweep is what makes that assumption actually checked, not just
assumed.

### D-9: Context-budget corroboration via peer-pane `/context` capture, capability-gated (N)

**Decision:** A peer pane running `/context`, capture-paned, offers a corroborating direct
context-budget signal alongside the existing completed-step-count proxy. It runs only against an
idle session, is capability-gated to backends that support a peer observation pane, and its
parsed output is treated as UI text (an unstable contract) — a parse failure degrades to the
step-count proxy with a warning, never an opaque halt.

**Alternatives considered:**
- Replace the step-count proxy entirely with the `/context` signal. Rejected because: `/context`'s
  output is documented as interactive-only, human-oriented UI text with no stability guarantee
  across Claude Code releases — it is a corroborating signal, not a replacement for the portable,
  version-stable proxy `context-budget-autoheal.md` already ships.
- Parse Claude Code's internal session transcript for real token counts instead. Rejected because:
  `context-budget-autoheal.md` already rejected this explicitly — the transcript schema is
  documented as internal and version-unstable, and a monitor that silently breaks on a release is
  exactly the failure this doctrine exists to prevent. The same reasoning applies here.

**Chosen because:** this closes the honest gap `context-budget-autoheal.md` already names ("no
supported way for a session to read its own context-window usage") without repeating either of
the approaches that doctrine already rejected, and it was an unconsumed observation
(`2026-07-09 context-budget premise challenge`) sitting unresolved in the fleet's own log.

### D-10: Ghost-text prevention via environment variable at dispatch, not runtime detection (N)

**Decision:** Every fleet-launched Claude Code session that another session reads via pane
capture (a dispatched worker, and any tower a meta-tower observes) is launched with
`CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` set in its environment. A backspace-probe
disambiguation check may exist as a documented defense-in-depth fallback, but is never the
primary or required mechanism.

**Alternatives considered:**
- Runtime detection via a backspace probe (send a backspace, diff the pane before/after).
  Rejected as the primary mechanism because: it is a workaround for a problem that has an
  official prevention switch — confirmed via Claude Code's own documentation
  (`interactive-mode.md`) that `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` disables the behavior
  entirely, and the tower already controls the launch environment of every session it dispatches.
- Runtime detection via a typed sentinel/probe token (the folklore method originally logged in
  the ghost-text-disambiguation observation). Rejected as the primary mechanism for the same
  reason — both detection methods are strictly worse than prevention when prevention is available
  and free.

**Chosen because:** an official disable switch, applied at launch, eliminates the ambiguity at
the source rather than detecting and working around it every time — a general principle worth
recording: prefer an official disable switch over a detection heuristic whenever the harness
exposes one.

### D-11: Rule-based (not confidence-calibrated-cascade) model/effort/command selection (N)

**Decision:** Per-task selection of model, reasoning effort, and which slash command(s) a
dispatched unit runs is resolved by a deterministic, task-type-keyed rule table, not a
confidence-calibrated model cascade.

**Alternatives considered:**
- A confidence-calibrated cascade (cheap model first, escalate on low confidence — the
  OpenRouter/LiteLLM/academic pattern surveyed). Rejected because: the survey found calibrating
  the escalation threshold correctly is an open, hard problem even in the literature ("the hard
  problem is calibrating the escalation threshold so it fires exactly when the cheap model is
  wrong, not merely uncertain") — disproportionate machinery for this bundle's actual need, per
  the proportionality doctrine.

**Chosen because:** a rule table is deterministic (no LLM judgment, per D-18), auditable, and
sufficient for the actual ask (routing routine vs. judgment-heavy work to an appropriate
model/effort tier) without taking on a genuinely unsolved calibration problem.

### D-12: Reactive fleet-wide throttling off Claude Code's native rate-limit signal (N)

**Decision:** Fleet-wide dispatch throttling is triggered reactively by detecting Claude Code's
own native rate-limit signal (its rate-limit prompt/retry event) and pausing dispatch until the
signaled reset time.

**Alternatives considered:**
- Proactive polling of a usage/quota API. Rejected because: confirmed via three Claude Code GitHub
  issues (#38380, #40793, #33820, all closed not-planned or unshipped) that no supported,
  machine-readable way exists to read Claude Code's own account-level usage or rate-limit state.
  The raw Anthropic API exposes `anthropic-ratelimit-*` response headers, but Claude Code CLI does
  not surface them to the invoking process.
- Local-transcript usage estimation (the `ccusage`-style community tool). Rejected as the primary
  mechanism because: it reconstructs *past* consumption from local JSONL files, not *remaining*
  server-side quota — useful as a corroborating estimate, not a throttling trigger.

**Chosen because:** this is the one concrete, already-working precedent found in the fleet-tooling
survey (`amux`'s fleet-wide rate-limit recovery: detect the shared rate-limit prompt across all
sessions on one account, parse the reset time, resume all parked sessions) — it reacts to Claude
Code's own authoritative signal rather than guessing at a number Claude Code doesn't expose.

### D-13: Fleet stats as a derived, rendered view (N)

**Decision:** Fleet health/activity statistics are derived and rendered on demand from existing
per-worker/per-daemon state, never captured into a new shared-write accumulator file.

**Alternatives considered:**
- A new append-only stats log, written by every daemon action. Rejected because: this reopens the
  exact concurrent-write-conflict class `observation-recording` had to solve for the shared
  `opportunities.md` log (GitHub ignores `.gitattributes merge=union` on PR merges; no merge-time
  rule reconciles a shared file multiple PRs both append to and prune). A stats log with the same
  shape would hit the same wall for no reason, since nothing here needs to be committed.

**Chosen because:** `fleet-attention.sh`'s `render`/`queue` functions already prove the
derived-view pattern works for this exact class of data (per-worker current state, rendered on
demand); stats are the same shape, just aggregated counters instead of per-worker state.

### D-14: `statusline` value on the existing `notification_channel` knob (N)

**Decision:** A `statusline` value is added to the existing `notification_channel` overlay
knob's enum, rendering the fleet stats (D-13) natively inside the operator's own Claude Code
terminal via the `statusLine` feature, composing with `fleet-attention.sh`'s existing
render/queue functions.

**Alternatives considered:**
- A GUI/web dashboard. Rejected because: `orchestration-fleet` already deferred this explicitly,
  gated on "the terminal/editor-legible decision queue proving insufficient in practice" — a gate
  that has not fired, and building a separate app would duplicate the attention capability's
  existing render logic for no new information.
- A new, separate notification channel outside the existing enum. Rejected because: `statusLine`
  is confirmed a real, plugin-drivable, native Claude Code surface — it fits the existing
  `notification_channel` capability-vs-style split (the seam is core, the channel is overlay-owned)
  precisely, needing only a new enum value, not a new seam.

**Chosen because:** this is the one native, plugin-drivable, always-visible-in-terminal surface
Claude Code actually offers (confirmed against `statusline.md`), and it resolves the "dashboard,
visible in Claude Code" ask without reopening the GUI/web dashboard call.

### D-15: Operator kill-switch for the autonomous daemon layer (N)

**Decision:** A config knob pauses every autonomous daemon action this spec introduces (cleanup,
restart, throttle) without disabling fleet operation entirely.

**Alternatives considered:**
- No kill-switch; rely on the per-mechanism config knobs (e.g. `context_budget_threshold: off`) to
  disable individual daemons one at a time. Rejected because: an operator debugging something
  unusual needs one lever, not N separate ones to remember and re-enable correctly afterward.

**Chosen because:** cheap to build (one flag every daemon mechanism checks), and the failure mode
it prevents (an operator fighting their own automation mid-debug) is real and easy to hit.

### D-16: Audit trail for autonomous daemon actions (N)

**Decision:** Every autonomous daemon action this spec introduces logs its trigger and reasoning
to an audit trail available for human review.

**Alternatives considered:**
- No audit trail; rely on the decision queue for escalations only. Rejected because: the decision
  queue only surfaces items needing a human decision — an autonomous action that succeeded (a
  cleanup that ran, a throttle that engaged) leaves no trace at all without this, and "did things go
  out of whack" (the original motivating question) is unanswerable without a record of what
  actually happened.

**Chosen because:** this is the same audit-then-review discipline the rest of the fleet's
autonomy gate already applies to findings; extending it to daemon actions is consistent, not new
machinery.

### D-17: Tower non-authoring boundary (N)

**Decision:** A tower dispatches, monitors, and reconciles; it does not author repo, config, or
content changes itself except as a narrow, explicitly-flagged exception surfaced as a
Needs-human-judgment fork — never the default response to a "quick change" request.

**Alternatives considered:**
- Leave this implicit (the status quo). Rejected because: this is precisely the gap the
  doctrine-gap(tower-role) observation names — a tower, on a loose request, directly reversed a
  rationale-documented decision (disabling a markdownlint rule) and opened its own PR, instead of
  treating a decision-reversal as a fork or routing it as a worker chore. The doctrine never said
  this wasn't allowed, so nothing stopped it.

**Chosen because:** mining a real, already-logged incident into an explicit boundary closes the
gap at its source rather than leaving it as a recurring rationalization risk ("just a quick
config tweak"). This is the altitude decision for the doctrine-gap(tower-role) trigger
(`autopilot-reflex.md` — Seed claims): the observation named an unstated doctrine floor, not a
one-repo mechanism, so the fix lands as a doctrine statement (Task 1), not a per-repo script.
*(Amended at kickoff walkthrough 2026-07-14: recorded as the altitude D-ID for this trigger, cited
from the Goal.)*

### D-18: No-LLM-daemon-mechanics invariant (N)

**Decision:** No daemon, hook, or cron mechanism this spec introduces invokes an LLM to make a
routine mechanical decision. Every such mechanism is deterministic script logic operating on
structured signals (files, process IDs, git state, pattern-matched known text); LLM invocation
stays reserved for the tower and worker sessions doing the actual task work.

**Alternatives considered:**
- Use a cheap/fast LLM call to classify ambiguous cases (e.g. "is this worker stuck?"). Rejected
  because: every fleet-mechanics decision that requires an LLM call to work becomes itself subject
  to the exact rate-limit/cost-throttling problem this spec exists to manage (REQ-E1.3) — a
  bootstrapping absurdity. It also reintroduces the deterministic-vs-model-judgment risk D-6
  already closed for cleanup specifically, generalized to every daemon mechanism.

**Chosen because:** an audit of all 16 original facets found every one of them already
implementable deterministically once designed carefully — this decision just makes that a
binding constraint rather than an accident of how the design happened to land.

### D-19: Reject `auto` permission mode for fleet dispatch (N)

**Decision:** Fleet dispatch does not use Claude Code's `auto` permission mode for worker
sessions. The existing human-reviewed, human-installed static `config/worker-settings.json`
allowlist remains the sole permission-approval mechanism for dispatched workers.

**Alternatives considered:**
- Launch workers in `auto` mode to reduce permission-prompt blocking. Rejected because two
  independent reasons converge: (1) `auto` mode's classifier is LLM-based and judgment-driven,
  directly contradicting D-18's no-LLM-daemon-mechanics floor for the single most
  security-sensitive decision a dispatched session makes — Claude Code's own documentation
  cautions it is not for "security-critical code without human review," which is exactly what
  worker dispatch is; (2) it is mechanically incompatible with the existing delivery channel —
  `defaultMode: "auto"` is settable only in a user's own `~/.claude/settings.json`, and Claude Code
  deliberately ignores it in project `.claude/settings.json` as a security guard, so it cannot be
  shipped through the same human-reviewed, project-scoped `worker-settings.json` channel the
  existing allowlist uses.

**Chosen because:** the actual goal (workers not blocking on routine prompts) is already served,
more safely and more auditably, by the existing static allowlist plus this bundle's own
`PermissionRequest` push (REQ-A1.1) — `auto` mode buys nothing the current design doesn't already
get, at a real cost to both auditability and mechanical compatibility.

### D-20: Multi-tower coordination reuses the existing advisory lock (C, orchestration-concurrency D-4)

**Decision:** Coordination among multiple concurrently-running towers' daemon actions serializes
through `orchestration-concurrency`'s existing per-spec advisory lock; this bundle introduces no
second lock primitive.

**Alternatives considered:**
- A separate lock for daemon-layer coordination. Rejected because: `orchestration-concurrency`'s
  lock already exists specifically to guard state moves against concurrent towers; a second
  primitive would need its own stale-break logic and its own correctness argument for no benefit
  over reusing the first.

**Chosen because:** one lock primitive, reused everywhere concurrent coordination is needed, is
strictly simpler to reason about than two.

### D-21: Session-per-tower tmux isolation (N)

**Decision:** Fleet-launched sessions are structured session-per-tower (or an equivalent isolation
unit), so fleet activity does not land in a resident tmux operator's own windows or session.

**Alternatives considered:**
- Launch fleet windows directly inside whatever tmux session the operator happens to already be
  attached to. Rejected because: this clutters the operator's own working windows with fleet
  infrastructure they didn't ask to see in that session, and risks a fleet-driven action
  (cleanup, relay) touching a pane the operator is actively using for unrelated work.

**Chosen because:** isolating fleet activity into its own session (or equivalent unit) keeps a
tmux poweruser's existing workflow undisturbed while still keeping everything addressable and
attachable when they want to look.

### D-22: Every new knob resolves through the existing overlay mechanism (C, customization-overlay D-1)

**Decision:** Every configuration knob this spec introduces resolves through the existing
four-layer overlay mechanism (`config-get.sh` and the `resolve-*.sh` pattern), never a second
config-resolution path.

**Alternatives considered:**
- A bespoke config mechanism for this bundle's new knobs. Rejected because:
  `customization-overlay` already ships exactly this capability, and `review_sequence`'s resolver
  is a proven, working template (`resolve-review-sequence.sh`) for exactly this shape of problem —
  reinventing it here would fragment where an operator has to look to understand their own
  configuration.

**Chosen because:** consistency with the framework's one established configuration contract is
strictly better than a bundle-local variant, and it directly answers the operator's own question
("we need to make as much of this as configurable as possible") using infrastructure that already
exists rather than new infrastructure that would need its own review.

## Changelog

- 2026-07-14 — Initial draft.
- 2026-07-14 — Kickoff walkthrough: amended D-1's wording (idle/done → idle) and D-4 (added the
  tower crash-loop backoff/disable alternative, citing new REQ-A1.9). Amended D-17: recorded as
  the altitude D-ID for the doctrine-gap(tower-role) trigger, per the kickoff sign-off lens pass's
  altitude check (`autopilot-reflex` REQ-H1.3).

## Sources

See `requirements.md`'s `## Sources` section; this file's decisions cite the same seeds and
sibling specs.
