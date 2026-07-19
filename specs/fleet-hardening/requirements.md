# Fleet Hardening — Requirements

**Status:** Ready
**Last reviewed:** 2026-07-19
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright's `fleet-autonomy` bundle (Done) moved most fleet housekeeping onto hooks and
heartbeats, but a set of the tower's **control-plane signals** — the mechanisms by which a tower
learns a worker needs attention, relays a decision to a worker, launches and names a worker,
learns that `main` advanced or a PR merged, and permits its own orchestration commands — are still
resolved by fragile means: heuristic pane screen-scraping, TUI menu-position counting, timing and
polling, silent-glob permission rules, and a stochastic permission classifier. Each is a
false-signal waiting to fire. One already did: on 2026-07-19 the tower's pane-grep busy-detector
false-negatived a worker parked at a real CI-config sign-off fork — scrollback text ("Waiting for
N background agent", spinner words) matched the busy heuristic over the whole captured pane and
masked the idle-at-fork footer, so no attention event fired and the worker sat blocked for roughly
seven hours.

This spec hardens those signals by replacing the remaining heuristic / screen-scraping / timing /
polling / stochastic mechanisms with deterministic, event-driven ones: native Claude Code hooks
for attention, a structured channel for decisions, an allow-rule-matchable code-level launch shape
for ghost-text prevention, a deterministic dispatch primitive for D-36 branch naming, a tested
allow layer fronting the tower's own permission classifier, and fetch/event triggers so dispatch
bases and merge detection are never stale. It closes the specific gaps the shipped attention surface
left (`fleet-autonomy` D-1, `orchestration-fleet` D-9) — chiefly the unwired `Notification` hook that made
the 7-hour fork-park invisible — and extends the same deterministic-over-heuristic discipline to
dispatch, tower self-permission, and freshness. The deliverable is mechanism-primary with one
carried doctrine statement; that altitude call is recorded as **D-1** (autopilot-reflex altitude
gate) and cited here from the Goal.

Two floors carry throughout, unchanged: no mechanism this bundle introduces invokes an LLM to make
a routine control-plane decision (`fleet-autonomy` D-18), and nothing here re-opens auto-merge or
autonomous PR-ready-marking beyond the existing sanctioned kickoff exception.

## Scope

### In scope

- A worker-side `Notification`-hook attention signal that PUSHES an `awaiting-human` record (reason
  plus timestamp) into `fleet-autonomy`'s existing attention store the instant a worker parks for
  human input, and a tower that learns of it by watching the store as an event, never by
  polling and grep-parsing worker panes. (The anchor gap.)
- A single codified fallback pane-state detector for dispatch backends that cannot register hooks:
  footer-region-only, positive at-prompt anchor plus absence of every busy marker, debounced across
  consecutive frames, so scrollback can never false-match and a main-idle / background-busy worker
  is never misread as idle.
- A structured worker-to-tower decision channel: a worker parked at a multi-option fork surfaces
  the pending decision and its full option set (labels plus the worker's recommendation) to a
  channel the tower or human reads and answers by label, replacing tmux menu-position keystroke
  counting; the answer is delivered through the existing attributed buffer-paste / structured-marker
  path, never by `send-keys` menu navigation.
- Ghost-text prevention (`CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false`) applied by the dispatch
  primitive's own launch construction (a code path, not skill prose the model must remember), through
  a launch shape the worker's permission layer auto-approves so applying the pin never forces a
  bare-launch fallback that drops it.
- Correct-glob allow-rule discipline: path-scoped Bash allow rules use the `Bash(<dir>/*)` form,
  never the word-boundary `Bash(<dir>/:*)` form that never matches `<dir>/<file>`, plus a mechanical
  check that flags the footgun.
- Deterministic D-36 branch naming at tmux-backend dispatch (`planwright/<spec>/task-<id>`), folded
  into the dispatch primitive so no manual post-launch `git branch -m` rename is required.
- A tower-settings profile that wires a deterministic PreToolUse command-guard over the tower's own
  orchestration command set, fronting Claude Code's stochastic `auto`-mode classifier with a tested
  allow layer, with an adversarial suite proving zero false-allows and denial of every dangerous
  orchestration operation.
- Fetch-before-gate dispatch freshness and merge detection: `/orchestrate` and `/execute-task`
  fetch `origin` and evaluate the freshness gate and merge state against the fetched `origin/main`
  refs, never advancing local `main`, so a stale local `main` cannot base a dispatch on outdated
  spec content or re-dispatch an already-merged task.
- A sanctioned path carrying tower-recorded observations to the accumulator on `main`, so
  autonomy learnings are not stranded on disposable, never-pushed tower branches.
- One carried doctrine statement elevating deterministic / event-driven over heuristic / polling /
  stochastic for the fleet control plane.

### Out of scope

- Everything `fleet-autonomy` already shipped and that works: the store-based state classifier, the
  five-state taxonomy, the `Stop`/`PermissionRequest`/`PostToolUse`/`SessionEnd`/`StopFailure` hooks
  it wired, the `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION` env-var definition (D-10), and the worker
  `auto`-mode rejection (D-19) — all consumed as authoritative and extended, never redefined.
- The `worker-command-guard.sh` mechanism and worker literal-path script resolution themselves
  (`worker-permission-ergonomics`, Done, #236/#237) — consumed as the built mechanism this bundle
  reuses for the tower and depends on for the ghost-text auto-approve.
- Content-anchor hash freshness — whether the executed bundle is the one the human signed off
  (`anchor-integrity`, Ready, owns it). This bundle's freshness work is git-ref currency (local
  `main` vs `origin/main`), a distinct axis; the two do not overlap.
- The `release-publish` / `release-pending` stale-local-main version-derivation variant — the same
  root cause in a different flow, which its own observation routes to `release-hardening`.
- The buffer-paste relay's no-`send-keys` / no-impersonation contract (`orchestration-fleet`) — the
  decision channel is additive and upward; it never re-introduces `send-keys`.
- Answering a worker's harness *permission* prompt on its behalf (that gate stays the human's,
  `inter-orchestrator-coordination`); the decision channel carries the worker's own
  `AskUserQuestion` forks, not its permission prompts.
- Auto-merge at any tier, and autonomous PR-ready-marking beyond the sanctioned kickoff exception
  (permanent carried floors).
- A second-multiplexer adapter (still gated on a concrete adopter need, per `orchestration-fleet`).
- Any LLM-in-the-loop control-plane decision (carried `fleet-autonomy` D-18).

## REQ-A — Attention & decision signals

- **REQ-A1.1** A dispatched worker SHALL push an `awaiting-human` attention record — carrying a
  reason and a timestamp — into `fleet-autonomy`'s attention store the instant it parks for human
  input, via a native Claude Code `Notification` hook, with no pane capture involved, for every fork
  type that raises `Notification`; fork types that do not are covered by the REQ-A1.3 reconcile
  backstop. The record SHALL be sufficient for the classifier to resolve `awaiting-human` directly,
  never by heartbeat-age inference.
  *(Cites: obs:ee255934 · `fleet-autonomy` D-1 · `orchestration-fleet` D-9.)*
- **REQ-A1.2** The tower SHALL learn of a pushed attention record by watching the attention store
  as an event (an inotify/Monitor-style watch or equivalent), not by polling and grep-parsing
  worker panes.
  *(Cites: obs:ee255934 · obs:26029772.)*
- **REQ-A1.3** For dispatch backends that cannot register hooks — or where a registered hook has not
  produced an attention push within a bounded reconcile interval (a registered-but-non-firing fork
  type) — the fleet SHALL provide one codified fallback pane-state detector that (a) reads only the
  bounded footer region, not the full scrollback; (b) requires a positive at-prompt anchor AND the
  absence of every busy marker (`esc to interrupt`, background-agent `Waiting for` / `to manage`,
  spinner words); and (c) debounces across at least two consecutive frames. This detector is a
  reconcile backstop, never the primary path where a fresh hook push exists (carrying `fleet-autonomy`
  D-1's push-first / reconcile pattern).
 
  *(Cites: obs:26029772 · `fleet-autonomy` D-1.)*
- **REQ-A1.4** A worker parked at a multi-option decision fork SHALL surface the pending decision
  and its full option set — each option's label and the worker's recommendation — to a structured
  channel the tower or human reads and answers by label, so a decision is never selected by
  screen-scraped TUI menu position.
  *(Cites: obs:ac0a9bba.)*
- **REQ-A1.5** A decision answer SHALL be delivered to the worker through the existing attributed
  buffer-paste / structured-marker path and selected by option label, never by `send-keys` menu
  navigation or keystroke counting — preserving the no-impersonation relay contract.
  *(Cites: obs:ac0a9bba · `orchestration-fleet` (buffer-paste relay contract).)*

## REQ-B — Dispatch hardening

- **REQ-B1.1** Every fleet-launched worker session that another session reads via pane capture
  SHALL have `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` applied by the dispatch primitive's own
  launch construction — a code path — not by a skill-prose instruction the model must remember to
  follow.
  *(Cites: obs:1d6a2b76 · `fleet-autonomy` D-10.)*
- **REQ-B1.2** The worker launch shape that carries the ghost-text pin SHALL be one the worker's
  permission layer auto-approves deterministically (the `worker-command-guard` literal-path
  resolution, or a correctly-globbed allow rule), so applying the pin never forces a permission
  flood that falls back to a bare launch dropping it.
  *(Cites: obs:1d6a2b76 · obs:2a19f510 ·)*
  `worker-permission-ergonomics` (#236/#237).
- **REQ-B1.3** Any shipped or documented path-scoped Bash allow rule SHALL use the `Bash(<dir>/*)`
  form, never the word-boundary `Bash(<dir>/:*)` form (which never matches `<dir>/<file>` because
  `:*` requires a following space or end-of-string), and a mechanical check SHALL flag any
  `Bash(<path>/:*)` directory-scoped rule as a likely never-match footgun.
  *(Cites: obs:1d6a2b76 ·)*
  drafting-session decision (2026-07-19).
- **REQ-B1.4** The tmux-backend dispatch primitive SHALL produce a worktree on the canonical D-36
  branch `planwright/<spec>/task-<id>` deterministically at launch, with no manual post-launch
  `git branch -m` rename step.
  *(Cites: obs:4e24463c.)*

## REQ-C — Tower self-governance

- **REQ-C1.1** A tower SHALL run under a tower-settings profile that wires a deterministic PreToolUse
  command-guard over the tower's own orchestration command set (tmux relay/observe, `claude
  --worktree` worker launches, planwright scripts resolved by literal path), fronting Claude Code's
  stochastic `auto`-mode classifier with a tested allow layer so routine orchestration commands are
  never non-deterministically blocked.
  *(Cites: obs:8eacaa65 · `fleet-autonomy` D-19.)*
- **REQ-C1.2** The tower safe set SHALL be a distinct, tower-oriented allow set — not a verbatim
  reuse of the worker safe set — and the tower guard SHALL be allow-only (never emitting deny or
  ask). Because the guard has no default-deny, deny-block coverage is the security floor: anything
  neither allowed nor explicitly denied falls to the stochastic classifier, so the profile's deny
  block SHALL deny every dangerous operation regardless of guard output, and its coverage SHALL
  extend beyond shell strings:
  - **(a) Shell ops:** `merge`, `force-push` in every spelling (`--force`, `-f`,
    `--force-with-lease`, `+`-prefixed refspecs), `amend`, `squash`, `rebase`, `gh pr merge`.
  - **(b) Default-branch writes / local-`main` mutation:** any push that writes the default branch
    outside the sanctioned flow (e.g. `git push origin HEAD:main`), and any local-`main`-mutating
    command (`reset --hard`, `branch -f`, `update-ref` on the default branch, a `merge` into it) —
    the shared-checkout read-only-local-`main` invariant is **guard-enforced**, not merely observed
    by the fetch code path.
  - **(c) Equivalent GitHub MCP tool surface:** `mcp__github__merge_pull_request`,
    `mcp__github__update_pull_request` draft→ready transitions, and `push_files` /
    `create_or_update_file` targeting the default branch — a PreToolUse Bash-string guard does not
    intercept MCP calls, so the never-merge / never-ready floors must deny the MCP surface too.
  - **(d)** every never-merge / never-ready guardrail.

  The tower allow-set SHALL be pinned so a `claude --worktree` allow never matches
  `--dangerously-skip-permissions` / `--permission-mode bypassPermissions` (which would launch a
  worker with its permission layer disabled — a fleet-wide escalation), and a `tmux` allow is scoped
  to `load-buffer` / `paste-buffer` / `capture-pane`, never `send-keys` or `kill-session`. The guard
  SHALL **fail closed** (never emit `allow` on error, uncertainty, or absence). The sanctioned
  kickoff spec-PR ready-flip SHALL be reconciled explicitly against the never-ready deny: the deny
  block denies ready-marking for task PRs / by the tower, and the flip is permitted only via the
  kickoff skill path for the spec PR.
  *(Cites: obs:8eacaa65 · `fleet-autonomy` D-18 · `kickoff-lifecycle` (the sanctioned ready-flip).)*
- **REQ-C1.3** The tower guard SHALL be deterministic and covered by an adversarial test suite
  asserting zero false-allows over the tower safe set, that every dangerous / guardrail operation —
  including the flag-appended escalation shapes and the MCP / direct-`main` surfaces of REQ-C1.2 —
  defers or is denied, and that the guard fails closed on error or absence. Tests SHALL assert the
  *outcome* (the guard never emits `allow` for a deny-listed command) rather than relying on
  documented Claude Code allow-vs-deny precedence, which is not confirmed for the running version
  (obs:4dda9fe1); the allow-before-classifier evaluation order is a platform-contract note, not a
  guard-output assertion.
  *(Cites: obs:8eacaa65 · obs:4dda9fe1.)*

## REQ-D — Freshness & propagation

- **REQ-D1.1** The execution freshness gate in `/orchestrate` and `/execute-task` SHALL fetch
  `origin` and evaluate currency — and re-point `anchor-integrity`'s existing content-anchor check —
  against the fetched `origin/main` ref before dispatch, so a stale local `main` cannot base a
  dispatch on outdated spec content or miss an upstream re-anchor. This bundle changes only which ref
  the existing anchor check reads against; it does not implement anchor-hash comparison (that remains
  `anchor-integrity`'s). The fetch SHALL NOT advance local `main`, preserving the shared-checkout
  read-only-local-`main` invariant.
  *(Cites: obs:04b578da (related) · `orchestration-concurrency` · `anchor-integrity` (owns the
  anchor-hash check).)*
- **REQ-D1.2** Merge detection SHALL evaluate against freshly-fetched `origin/main` and
  remote-tracking refs, so a merged task PR whose merge trailer has not reached local `main` is not
  re-dispatched as if unmerged.
  *(Cites: obs:04b578da (related) · drafting-session decision)*
  (2026-07-19).
- **REQ-D1.3** Tower-recorded observations SHALL have a sanctioned path to the accumulator on
  `main` (the `--bookkeeping` / drain pass, or the tower, auto-opening a chore PR for accumulated
  tower observations), so autonomy learnings are not stranded on disposable, never-pushed tower
  branches.
  *(Cites: obs:a877745e.)*

## REQ-E — Carried floors & control-plane doctrine

- **REQ-E1.1** planwright SHALL carry a doctrine statement that fleet control-plane signals (a
  worker needing attention, a decision needing an answer, `main` having advanced, a PR having
  merged, a command being permitted) are resolved by deterministic, event-driven mechanisms —
  native hooks, structured channels, fetch/event triggers — in preference to heuristic pane
  scraping, timing/polling, or stochastic classification wherever the harness exposes a deterministic
  signal. This extends `fleet-autonomy` D-10 ("prefer an official disable switch over a detection
  heuristic") and D-18 (no-LLM-daemon-mechanics) to the whole control plane.
  *(Cites: D-1 ·)*
  `fleet-autonomy` D-10, D-18.
- **REQ-E1.2** This bundle SHALL NOT redefine `fleet-autonomy`'s shipped attention store, five-state
  classifier, or the hooks it already wired; it extends them.
  *(Cites: `fleet-autonomy` D-1, D-2.)*
- **REQ-E1.3** No mechanism this bundle introduces SHALL invoke an LLM to make a routine
  control-plane decision.
  *(Cites: `fleet-autonomy` D-18.)*
- **REQ-E1.4** Auto-merge and autonomous PR-ready-marking beyond the existing sanctioned kickoff
  exception SHALL remain out of scope.
  *(Cites: `orchestration-fleet`, `kickoff-lifecycle`)*
  (carried floors).

## Changelog

- 2026-07-19 — Bundle drafted (`/spec-draft`). Fold-detection against `fleet-autonomy` (Done)
  resolved to a new bundle citing it, rather than reopening the released bundle, because several
  findings are new external interfaces (structured decision channel, native branch dispatch,
  fetch-before-gate) outside its self-maintenance-daemon domain (D-21 spin-new triggers).

## Sources

- **The `fleet-hardening` drafting session** (2026-07-19) — the full elicitation: the free-form
  hardening idea, the fold-detection pass against `fleet-autonomy` (Done) and the boundary checks
  against `anchor-integrity` (Ready) and `release-hardening`, and two read-only source-audit passes
  over the fleet dispatch/relay/attention scripts and the merge/freshness/branch paths. The audit
  reframed several seed premises against shipped ground truth: the idle classifier is already
  store-based (not pane-scraping) — the 7-hour incident's grep-parse was the operator's manual
  fallback, forced because no hook pushed the fork-park transition; the relay is buffer-paste with
  `send-keys` affirmatively forbidden — menu-scraping is out-of-doctrine operator practice; D-36
  branches are cut natively in shipped code — the mangling is a tmux `claude --worktree` operator
  path; and no broken `Bash(<dir>/:*)` rule ships (the operator's machine-local settings carried it).
- **The stale-local-`main` dogfood** (2026-07-19) — this drafting session itself hit the finding it
  specs: local `main` sat one commit behind `origin/main`, so the seed's named observations appeared
  absent until the spec branch was based on the fetched `origin/main`. Direct evidence for REQ-D1.1.
- **obs:ee255934** — hook-based worker attention signal: the anchor. The tower's pane-grep
  busy-detector false-negatived a fork-parked worker for hours; the deterministic fix is a worker-side
  `Stop`/`Notification` hook pushing a per-worker attention record the tower watches. Consumed.
- **obs:26029772** — idle-detect background-agent false-positive: absence-of-busy pane heuristics
  misread a main-idle / background-busy worker as idle; the robust detector is footer-only,
  positive-anchor, debounced. Consumed.
- **obs:2a19f510** — guard-forbids-bootstrap-automode: before the worker-command-guard existed, the
  only flood-free bootstrap was `auto` mode, which the dispatch guard forbids — a bootstrap deadlock
  that required a human override. Consumed; informs REQ-B1.2.
- **obs:4e24463c** — tmux-classic dispatch primitive: `claude --worktree <suffix> --tmux=classic`
  folds worktree + session + launch into one native command, but still creates a mangled
  `worktree-<suffix>` branch needing the D-36 rename; `--tmux` (non-classic) uses non-relay-targetable
  iTerm2 panes. Consumed; grounds REQ-B1.4.
- **obs:8eacaa65** — tower-hook-extension amendment: the operator's 2026-07-18 decision to cover the tower
  with a deterministic command-guard, with a distinct tower safe set and an adversarial zero-false-allow
  suite. Consumed. Routing note below.
- **obs:1d6a2b76** — ghost-text-hazard bare launch: bare worker launches dropped the ghost-text pin
  and showed dangerous prompt-suggestions ("mark PR ready", "clean up worktree and window"); root cause
  was the machine-local scripts allow-rule using the `Bash(<dir>/:*)` word-boundary form that never
  matched the wrapper path. Consumed; grounds REQ-B1.1/B1.2/B1.3.
- **obs:ac0a9bba** — menu-scraping relay hazard: answering an `AskUserQuestion` by tmux
  keystroke-counting is a mis-selection hazard (a reordered Skip/Apply prompt nearly selected the
  wrong disposition); the fix is a structured worker-to-tower decision channel. Consumed; grounds
  REQ-A1.4/A1.5.
- **obs:a877745e** — tower observations stranded unpushed: tower-recorded observations never reach
  `main` because `/orchestrate` never pushes the tower branch, so autonomy learnings are lost unless a
  human notices. Consumed; grounds REQ-D1.3.
- **obs:04b578da** (related, not consumed) — release-publish stale-local-`main`: the same
  stale-local-`main` root cause in the release flow; its own note routes the fix to `release-hardening`.
  Cited as the sibling manifestation of REQ-D1.1/D1.2's root cause; left in the accumulator for
  `release-hardening` to drain.
- **obs:4dda9fe1** (related, not consumed) — CC hook allow-vs-deny precedence undocumented: the
  platform-contract fact underlying the tower guard's deny-precedence is not documented for the running
  Claude Code version, so REQ-C1.3 asserts the outcome rather than the documented precedence. Left for
  `worker-permission-ergonomics` to drain.
- **`fleet-autonomy`** (Done) — the attention store and five-state classifier (D-1/D-2), the hooks it
  wired, the ghost-text env-var (D-10), the worker `auto`-mode rejection (D-19), and the
  no-LLM-daemon-mechanics floor (D-18): consumed as authoritative and extended, never redefined. Its
  D-1 wired `Stop`/`PermissionRequest`/`PostToolUse`/`SessionEnd`/`StopFailure` but not `Notification`
  — the gap this bundle's REQ-A1.1 closes.
- **`worker-permission-ergonomics`** (Done, v0.23.0, #236/#237) — the deterministic
  `worker-command-guard.sh` PreToolUse hook and literal-path plugin-script resolution; reused as the
  pattern for the tower guard (REQ-C1.x) and depended on for the ghost-text auto-approve (REQ-B1.2).
- **`orchestration-fleet`** (Done) — the backend capability contract, the attention/notification
  capability (D-9), and the buffer-paste relay contract that forbids `send-keys` impersonation.
- **`orchestration-concurrency`** (Done) — the derived-projection state model, the per-spec advisory
  lock, and the shared-checkout coordination model (local `main` read-only; reconcile without
  clobbering a peer's unpushed commits) that REQ-D1.1's never-advance-local-`main` constraint honors.
- **`anchor-integrity`** (Ready) — owns content-anchor hash freshness; cited as the sibling that owns
  the *other* freshness axis so REQ-D1.x stays scoped to git-ref currency. Kickoff reconciliation
  (2026-07-19): the flagged `anchor-freshness` branch carries no `specs/anchor-freshness` bundle (it
  predates the anchor work), so there is no competing bundle — the hash-freshness axis is
  `anchor-integrity`'s alone, and REQ-D1.x's git-ref-currency axis stays distinct.
- **`kickoff-lifecycle`** (Ready/Done) — owns the sanctioned spec-PR ready-flip exception; grounds the
  REQ-E1.4 / REQ-C1.2 carried floor that auto-merge and autonomous ready-marking stay out of scope
  beyond that one exception.
- **`observation-recording`** (Done) — the intra-repo accumulator log and its concurrent-shared-write
  solution; referenced by D-9's observation-propagation half (REQ-D1.3) as the sibling whose
  conflict class the tower-observation carry must not re-open. Does **not** own a tower→`main` carry
  path (that is net-new here).
- **Routing supersession (drafting-session decision, 2026-07-19).** The tower command-guard
  (REQ-C1.x) was directed on 2026-07-18 (obs:8eacaa65) to land as an amendment to
  `worker-permission-ergonomics`. The 2026-07-19 hardening seed instead scopes it into this bundle as
  one of a coherent set of control-plane hardening findings. This bundle follows the newer intent and
  records the superseded routing here so `/spec-kickoff` can confirm the placement rather than
  discover the conflict.
