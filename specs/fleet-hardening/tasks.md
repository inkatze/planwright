# Fleet Hardening — Tasks

**Status:** Draft
**Last reviewed:** 2026-07-19
**Format-version:** 2
**Execution:** derived — see the status render

Nine tasks. Task 1 (the control-plane doctrine statement plus the carried-floor citations) is
foundational: every other task cites it, so it dispatches first. The three guard/infrastructure
tasks that protect every dispatch — Task 6 (correct-glob check), Task 7 (tower command-guard), and
Task 8 (fetch-before-gate) — outrank the critical path per the guard-infrastructure-first selection
rule once Task 1 lands. The top wins by impact are Task 2 (the `Notification`-hook attention signal
that closes the seven-hour gap) and Task 4 (the structured decision channel); Task 3 is the
reconcile backstop to Task 2, and Task 4 extends the same attention-store record Task 2 shapes, so
Task 4 depends on Task 2. Tasks 5, 9 are otherwise independent of one another. All tasks depend on
Task 1.

## Tasks

### Task 1 — Control-plane doctrine statement & carried floors

- **Deliverables:** The doctrine statement for deterministic / event-driven over heuristic / polling
  / stochastic fleet control-plane signals (REQ-E1.1), written as an extension of `fleet-autonomy`
  D-10 and D-18; the carried-floor citations (no-LLM control-plane decision REQ-E1.3; no-redefinition
  of `fleet-autonomy`'s shipped surface REQ-E1.2; auto-merge / autonomous-ready-flip out of scope
  REQ-E1.4). No new mechanism — this task establishes the altitude record (D-1) the other tasks cite.
- **Done when:** the doctrine statement exists and is cited by REQ-E1.1 and from the design Goal as
  the D-1 altitude record; the three carried floors are stated with their citations; the spec
  validator passes on the bundle; CI passes.
- **Dependencies:** none
- **Citations:** D-1 · REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.4
- **Estimated effort:** 1 day

### Task 2 — Fork-park attention signal via the `Notification` hook

- **Deliverables:** A worker-side `Notification` hook (wired the way `fleet-autonomy` Task 2 wired its
  hooks — a shipped hook plus the worker-settings wiring instruction, since planwright never edits
  `settings.json`) that pushes an `awaiting-human` record with reason and timestamp into the existing
  attention store the instant a worker parks for input, with no pane capture; the tower-side event
  watch that reacts to a store change (inotify/Monitor-style), replacing the manual pane-grep for the
  fork-park case; confirmation, pinned against the running Claude Code `hooks` documentation, that
  `Notification` fires for the fork-park / idle-wait state.
- **Done when:** a fixture worker firing a `Notification` stub updates the store's `awaiting-human`
  row within one event cycle, carrying reason + timestamp, with no `capture-pane` involved; the
  classifier resolves that row to `awaiting-human` directly (not via heartbeat-age inference); a
  fork-parked fixture is never classified `working` or `hung`; the tower-watch path reacts to the
  store change as an event, not on a poll cycle; the `Notification`-fires-for-fork-park fact is
  confirmed and recorded (or, if a fork type does not raise it, that gap is documented and delegated
  to Task 3's backstop); tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-2 · REQ-A1.1, REQ-A1.2
- **Estimated effort:** 2 days

### Task 3 — Fallback pane-state detector (footer-only, positive-anchor, debounced)

- **Deliverables:** One codified planwright pane-state detector for hook-less backends: it reads only
  the bounded footer region, requires a positive at-prompt anchor AND the absence of every busy
  marker (`esc to interrupt`, background-agent `Waiting for` / `to manage`, spinner words), and
  debounces across at least two consecutive frames; wired as the reconcile backstop to Task 2's push,
  never the primary path where a hook exists.
- **Done when:** a fixture pane whose scrollback contains busy words ABOVE an idle footer classifies
  idle (no scrollback false-match); a main-idle / background-busy fixture (footer shows
  `Waiting for N background agent`, no `esc to interrupt`) classifies busy, not idle; a single-frame
  flap is suppressed by the two-frame debounce; the detector is invoked only where no hook is
  registered; tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-3 · REQ-A1.3
- **Estimated effort:** 2 days

### Task 4 — Structured worker-to-tower decision channel

- **Deliverables:** An extension of the attention store's `decide` / `awaiting-input` path so a worker
  parked at a multi-option fork writes the pending decision plus its full option set (each option's
  label and the worker's recommendation) as a structured record; a tower/human read-and-answer path
  keyed on option *label*; downward delivery through the existing attributed buffer-paste /
  structured-marker path, with no `send-keys` menu navigation introduced.
- **Done when:** a fixture fork writes a decision record carrying every option label and the
  recommendation; answering by label selects the correct option even when option order differs from a
  sibling prompt (the reordered Skip/Apply case); a test asserts no `send-keys` menu-navigation path
  is emitted anywhere in the channel; the worker's own harness permission prompts are explicitly out
  of the channel's scope; tests/CI pass.
- **Dependencies:** 1, 2
- **Citations:** D-4 · REQ-A1.4, REQ-A1.5
- **Estimated effort:** 2 days

### Task 5 — Ghost-text pin in the dispatch launch primitive

- **Deliverables:** The worker launch construction (the dispatch primitive / relay launch path)
  applies `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` as a code path, through a launch shape the
  worker's `worker-command-guard` literal-path resolution auto-approves, replacing the SKILL-prose
  instruction as the mechanism of record.
- **Done when:** a launched-worker fixture asserts the ghost-text env var is set on the worker
  process by the primitive itself (not by model-obeyed prose); the wrapped launch shape is
  auto-approved by the worker-command-guard path (no permission flood, no bare-launch fallback that
  drops the pin); a bare-launch regression fixture (the 2026-07-19 shape) is shown to be replaced;
  tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-5 · REQ-B1.1, REQ-B1.2
- **Estimated effort:** 2 days

### Task 6 — Correct-glob allow-rule discipline & check

- **Deliverables:** Documentation of the `Bash(<dir>/*)`-not-`Bash(<dir>/:*)` rule for path-scoped
  allow rules (in the adopter allow-rule guidance and the worker/tower settings docs); a mechanical
  check (in the `mise run check` guard suite) that flags any `Bash(<path>/:*)` directory-scoped rule
  as a likely never-match footgun; an audit of every shipped and documented allow rule confirming the
  `/*` form.
- **Done when:** the check flags a `Bash(<path>/:*)` directory rule and passes a `Bash(<path>/*)`
  rule and the legitimate command globs (`Bash(git status:*)` etc., which are correct and must not be
  flagged); the documented correct form exists and is cross-referenced from the ghost-text and
  tower-guard docs; every shipped/documented path-scoped rule is confirmed `/*`; tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-6 · REQ-B1.3
- **Estimated effort:** 1 day

### Task 7 — Tower-settings profile & deterministic tower command-guard

- **Deliverables:** A tower-oriented deterministic PreToolUse command-guard (reusing the
  `worker-command-guard` pattern but with a distinct tower safe set: tmux relay/observe, `claude
  --worktree` worker launches, planwright scripts by resolved literal path) and a tower-settings
  profile that wires it; the profile's deny block denying every dangerous orchestration operation and
  every never-merge / never-ready guardrail; an adversarial test suite over the tower safe set.
- **Done when:** the adversarial suite proves zero false-allows over the tower safe set; every
  dangerous / guardrail operation (merge, force-push, amend, squash, rebase, `gh pr merge`, and the
  never-ready guardrails) defers or is denied; the allow layer is evaluated before the stochastic
  classifier; tests assert the *outcome* (the guard never emits `allow` for a deny-listed command)
  rather than relying on documented allow-vs-deny precedence; the guard invokes no LLM; the
  worker-only-scoping security rationale is consciously re-opened and documented; tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-8 · REQ-C1.1, REQ-C1.2, REQ-C1.3
- **Estimated effort:** 3 days

### Task 8 — Fetch-before-gate dispatch freshness & merge detection

- **Deliverables:** `/orchestrate` and `/execute-task` fetch `origin` and evaluate the execution
  freshness gate (currency + content anchor) and merge detection against the fetched `origin/main` /
  remote-tracking refs before dispatch, without advancing local `main`.
- **Done when:** a fixture with local `main` behind `origin/main` gates and detects merge state
  against `origin/main` (it sees the newer anchor, and does not re-dispatch a task whose PR merged on
  `origin` but whose trailer has not reached local `main`); local `main` is provably unchanged after
  the gate (the shared-checkout invariant holds); `no-remote` / `no-gh` degrades gracefully; the
  scope boundary against `anchor-integrity` (anchor-hash freshness) and `release-hardening`
  (release-publish variant) is honored — this task touches only the dispatch/merge git-ref path;
  tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-9 · REQ-D1.1, REQ-D1.2
- **Estimated effort:** 2 days

### Task 9 — Sanctioned tower-observation-to-main path

- **Deliverables:** A sanctioned path carrying tower-recorded observations to the accumulator on
  `main` — the `--bookkeeping` / drain pass (or the tower) auto-opening a chore PR for accumulated
  tower observations on the disposable tower branch — so autonomy learnings are not stranded unpushed.
- **Done when:** a fixture tower branch carrying committed observations, run through the bookkeeping
  path, produces a chore PR (or equivalent sanctioned carry) landing them toward `main`; a
  no-observation run is a clean no-op; nothing is stranded silently; the path never merges the PR
  (merge stays human) and never touches shared local `main`; tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-9 · REQ-D1.3
- **Estimated effort:** 2 days

## Awaiting input

- (none yet)

## Deferred

- **capture-pane partial-frame robustness for on-demand observation.** The shipped idle classifier
  is store-based, so partial/empty capture-pane frames no longer cause false idles on the automated
  path. The remaining `capture-pane` consumers — on-demand tmux worker observation and the
  context-budget peer estimate — treat a partial frame as a re-read rather than a false attention
  event, so the stakes are low. A debounce/retry hardening of those on-demand reads is deferred.
  Confidence: high. **Gate:** a concrete case where a partial-frame on-demand observation produces a
  wrong tower action (not merely a re-read) is observed in the drain loop.

## Out of scope

- Redefining `fleet-autonomy`'s shipped attention store, five-state classifier, or the hooks it
  already wired (REQ-E1.2, carried).
- The `worker-command-guard.sh` mechanism and worker literal-path resolution themselves
  (`worker-permission-ergonomics`, consumed).
- Content-anchor hash freshness (`anchor-integrity`) and the `release-publish` stale-`main` variant
  (`release-hardening`).
- Re-introducing any `send-keys` impersonation path in the relay (`orchestration-fleet` contract).
- Auto-merge and autonomous PR-ready-marking beyond the sanctioned kickoff exception (permanent
  carried floors).
- Any LLM-in-the-loop control-plane decision (carried `fleet-autonomy` D-18).
