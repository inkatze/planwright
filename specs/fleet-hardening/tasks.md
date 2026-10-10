# Fleet Hardening — Tasks

**Status:** Draft
**Last reviewed:** 2026-10-10
**Format-version:** 2
**Execution:** derived — see the status render

Task 1 (the control-plane doctrine statement plus the carried-floor citations) is
foundational: every other task cites it, so it dispatches first. The three guard/infrastructure
tasks that protect every dispatch — Task 6 (correct-glob check), Task 7 (tower command-guard), and
Task 8 (fetch-before-gate) — outrank the critical path per the guard-infrastructure-first selection
rule once Task 1 lands. The top wins by impact are Task 2 (the `Notification`-hook attention signal
that closes the seven-hour gap) and Task 4 (the structured decision channel); Task 3 is the
reconcile backstop to Task 2, and Task 4 reuses the tower-side store event-watch
infrastructure Task 2 builds (and extends the store's separate `decide`/`awaiting-input` path), so
Task 4 depends on Task 2. Tasks 5, 9, and 10 (the two dispatch-primitive hardenings — ghost-text pin
and bootstrap D-36 branch naming — plus the observation-carry path) are otherwise independent of one another.
All tasks depend on Task 1.

The 2026-10-04 extension adds the tmux rung's launch work (D-10 through D-15). Task 11's fixture
harness comes first because every launch fixture after it runs on that harness. Task 12 ships the
detached launch together with its safety arms, so the launch never exists without them. Task 13
(startup confirmation) and Task 14 (docs and the seam exemption) follow Task 12; Task 13 rewrites
the same launch function, so it waits for Task 12 rather than running beside it.

## Tasks

### Task 1 — Control-plane doctrine statement & carried floors

- **Deliverables:** The doctrine statement for deterministic / event-driven over heuristic / polling
  / stochastic fleet control-plane signals (REQ-E1.1), written as an extension of `fleet-autonomy`
  D-10 and D-18; the carried-floor citations (no-LLM control-plane decision REQ-E1.3; no-redefinition
  of `fleet-autonomy`'s shipped surface REQ-E1.2; auto-merge / autonomous-ready-flip out of scope
  REQ-E1.4). No new mechanism — this task establishes the altitude record (D-1) the other tasks cite.
- **Done when:** the doctrine statement exists and is cited by REQ-E1.1 and from the Goal (in
  `requirements.md`) as the D-1 altitude record; the carried floors and the no-redefinition
  constraint are stated with their citations; the spec validator passes on the bundle; CI passes.
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
  to Task 3's backstop); the hook gates on the `Notification` payload reason so a permission-park /
  idle-nudge does not push a false `awaiting-human`; the event-watch carries a liveness check and a
  periodic full-store reconcile sweep (a push written before the watch is established, or a dead
  watch, degrades to poll-latency, not silent blindness); the `awaiting-human` row is cleared /
  superseded when the worker resumes (the exit edge, asserted by a resume-clears-the-row fixture;
  terminal exit — crash / session end — clears the row via `fleet-autonomy`'s existing SessionEnd /
  StopFailure transitions, which take precedence over the push); a
  negative assertion confirms no model/API call in the push decision path (REQ-E1.3); the shipped
  `fleet-autonomy` attention-store + classifier surface is asserted behaviorally unchanged by this
  extension (REQ-E1.2 regression); tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-2 · REQ-A1.1, REQ-A1.2, REQ-E1.2, REQ-E1.3
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
  flap is suppressed by the two-frame debounce; the detector runs only as the reconcile backstop —
  where no hook is registered, OR where a registered hook has not pushed within the bounded reconcile
  interval (the registered-but-non-firing case) — never where a fresh hook push exists; a negative
  assertion confirms no model/API call in the detector's decision path (REQ-E1.3); tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-3 · REQ-A1.3, REQ-E1.3
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
  is emitted anywhere in the channel; each decision record carries a unique instance id the answer
  must match, and a stale-answer fixture (a late answer for a resolved fork whose labels collide with
  a later fork) is refused, not mis-applied; a double-answer fixture shows first-answer-wins claim /
  close (the second answer is a no-op); the channel mechanically refuses to emit an answer for a
  record whose reason is a permission-park (a negative fixture), keeping that gate the human's; a
  negative assertion confirms no model/API call in the channel's decision path (REQ-E1.3); the shipped
  store surface is asserted behaviorally unchanged (REQ-E1.2 regression); tests/CI pass.
- **Dependencies:** 1, 2
- **Citations:** D-4 · REQ-A1.4, REQ-A1.5, REQ-E1.2, REQ-E1.3
- **Estimated effort:** 2 days

### Task 5 — Ghost-text pin in the dispatch launch primitive

- **Deliverables:** The worker launch construction (the dispatch primitive / relay launch path)
  applies `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` as a code path, through a launch shape the
  worker's `worker-command-guard` literal-path resolution auto-approves, replacing the SKILL-prose
  instruction as the mechanism of record.
- **Done when:** a launched-worker fixture asserts the ghost-text env var is set on the worker
  process by the primitive itself (not by model-obeyed prose); the wrapped launch shape is
  auto-approved by the worker-command-guard path (no permission flood, no bare-launch fallback that
  drops the pin); a bare-launch regression fixture (the 2026-07-19 shape) is shown to be replaced; a
  negative assertion confirms no model/API call in the launch-construction decision path (REQ-E1.3);
  tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-5 · REQ-B1.1, REQ-B1.2, REQ-E1.3
- **Estimated effort:** 2 days

### Task 6 — Correct-glob allow-rule discipline & check

- **Deliverables:** Documentation of the `Bash(<dir>/*)`-not-`Bash(<dir>/:*)` rule for path-scoped
  allow rules (in the adopter allow-rule guidance and the worker/tower settings docs); a mechanical
  check (in the `mise run check` guard suite) that flags any `Bash(<path>/:*)` directory-scoped rule
  as a likely never-match footgun; an audit of every shipped and documented allow rule confirming the
  `/*` form.
- **Done when:** the check flags a `Bash(<path>/:*)` directory rule and passes a `Bash(<path>/*)`
  rule and the legitimate command globs (`Bash(git status:*)` etc., which are correct and must not be
  flagged); the documented correct form exists and its presence + cross-reference from the ghost-text
  (D-5) and tower-guard (D-8) docs is verified (a doc-presence check, so the documentation half of
  D-6 is not an unverified deliverable); every shipped/documented path-scoped rule is confirmed `/*`;
  a negative assertion confirms no model/API call in the check's decision path (REQ-E1.3); tests/CI
  pass.
- **Dependencies:** 1
- **Citations:** D-6 · REQ-B1.3, REQ-E1.3
- **Estimated effort:** 1 day

### Task 7 — Tower-settings profile & deterministic tower command-guard

- **Deliverables:** A tower-oriented deterministic PreToolUse command-guard (reusing the
  `worker-command-guard` pattern but with a distinct tower safe set: tmux relay/observe, `claude
  --worktree` worker launches, planwright scripts by resolved literal path) and a tower-settings
  profile that wires it; the profile's deny block denying every dangerous orchestration operation and
  every never-merge / never-ready guardrail; an adversarial test suite over the tower safe set.
- **Done when:** the adversarial suite proves zero false-allows over the tower safe set; the deny
  block denies — regardless of guard output — every dangerous / guardrail operation across all
  surfaces: the shell ops (merge, force-push in every spelling `--force`/`-f`/`--force-with-lease`/
  `+`-refspec, amend, squash, rebase, `gh pr merge`), default-branch writes and local-`main` mutation
  (`git push …:main`, `reset --hard`, `branch -f`, `update-ref`), and the equivalent GitHub MCP tools
  (`mcp__github__merge_pull_request`, `update_pull_request` draft→ready, `push_files` /
  `create_or_update_file` / `delete_file` on the default branch); the allow-set is pinned so `claude --worktree`
  never matches `--dangerously-skip-permissions` / `--permission-mode` and `tmux` is scoped to
  `load-buffer` / `paste-buffer` / `capture-pane` (never `send-keys` / `kill-session`), with
  flag-appended false-allow probes in the suite; the guard fails closed on error / absence (asserted);
  the sanctioned kickoff spec-PR ready-flip is reconciled against the never-ready deny (denied for
  task PRs / by the tower, permitted only via the kickoff skill path); tests assert the *outcome* (the
  guard never emits `allow` for a deny-listed command) rather than relying on documented allow-vs-deny
  precedence (the allow-before-classifier order is a platform-contract note, not a guard-output
  assertion); the guard invokes no LLM (REQ-E1.3); the worker-only-scoping security rationale is
  consciously re-opened and documented; tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-8 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-E1.3, REQ-E1.4
- **Estimated effort:** 3 days

### Task 8 — Fetch-before-gate dispatch freshness & merge detection

- **Deliverables:** `/orchestrate` and `/execute-task` fetch `origin` and evaluate the execution
  freshness gate (currency + content anchor) and merge detection against the fetched `origin/main` /
  remote-tracking refs before dispatch, without advancing local `main`.
- **Done when:** a fixture with local `main` behind `origin/main` gates and detects merge state
  against `origin/main` (it sees the newer anchor, and does not re-dispatch a task whose PR merged on
  `origin` but whose trailer has not reached local `main`); local `main` is provably unchanged after
  the gate (the shared-checkout invariant holds); the gate re-points `anchor-integrity`'s existing
  content-anchor check at the fetched ref (it does not implement anchor-hash comparison); a transient
  fetch failure against a present remote is handled distinctly from structural `no-remote` (retry,
  then block or proceed with an explicit stale flag — never a silent stale gate), covered by both a
  transient-failure and a `no-remote` fixture for currency AND merge detection; the per-gate fetch is
  bounded (TTL / coalesced with the reconcile sweep) so an `/orchestrate --watch` idle loop does not
  fetch every cycle; the scope boundary against `anchor-integrity` (anchor-hash freshness) and
  `release-hardening` (release-publish variant) is honored — this task touches only the dispatch/merge
  git-ref path; a negative assertion confirms no model/API call in the gate's decision path
  (REQ-E1.3); tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-9 · REQ-D1.1, REQ-D1.2, REQ-E1.3
- **Estimated effort:** 2 days

### Task 9 — Sanctioned tower-observation-to-main path

- **Deliverables:** A sanctioned path carrying tower-recorded observations to the accumulator on
  `main` — the `--bookkeeping` / drain pass (or the tower) auto-opening a chore PR for accumulated
  tower observations on the disposable tower branch — so autonomy learnings are not stranded unpushed.
- **Done when:** a fixture tower branch carrying committed observations, run through the bookkeeping
  path, produces a chore PR (or equivalent sanctioned carry) landing them toward `main`; a
  no-observation run is a clean no-op; nothing is stranded silently; the carry is idempotent
  (reuse / update one open chore PR, dedupe already-carried observations) and safe under repeat and
  concurrent bookkeeping runs (a duplicate-run fixture opens no second PR); the path never merges the
  PR (merge stays human) and never touches shared local `main`; a negative assertion confirms no
  model/API call in the carry's decision path (REQ-E1.3); tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-9 · REQ-D1.3, REQ-E1.3
- **Estimated effort:** 2 days

### Task 10 — Deterministic D-36 branch naming in the tmux dispatch primitive

- **Deliverables:** The tmux-backend dispatch primitive produces a worktree on the canonical bootstrap D-36
  branch `planwright/<spec>/task-<id>` deterministically at launch, with no manual post-launch `git
  branch -m` rename step. **Create** via a single
  `git worktree add -b planwright/<spec>/task-<id> .claude/worktrees/<suffix> <base>` call — the
  narrow, documented never-shell-`git worktree` exception scoped to this one dispatch primitive
  (D-7) — with `<base>` the freshly-fetched `origin/main`, `<suffix>` a deterministic function of
  `(spec, task-id)`, and `<spec>` / `<id>` / `<suffix>` validated against the D-36 grammar (or passed
  as argv) before interpolation; then **attach** via `claude --worktree <suffix> --tmux=classic` only
  if the create exited zero. The primitive reconciles collisions against this bundle's liveness
  signals (dispatch marker / tmux session / Task-2 heartbeat store): a live dispatch aborts as
  already-in-flight; a stale/orphaned branch or worktree (including a leftover empty `<suffix>` dir, or
  a partial create) is GC-adopted / rolled back before recreating, never wedging the task. Two carried
  caveats: `--tmux=classic` is mandatory (plain `--tmux` opens non-relay-targetable iTerm2 panes), and
  the attach switches the attached tmux client to the new session, which must be mitigated so a tower
  watching another session is not disrupted.
- **Done when:** a fixture asserts the resulting branch name matches the D-36 grammar
  `planwright/<spec>/task-<id>` with no post-launch `git branch -m` step, created by the single scoped
  `git worktree add -b` call, with the mangled `worktree-<suffix>` name provably not the output;
  `<base>` is asserted to be the freshly-fetched `origin/main` (not stale local `main`/HEAD), and
  `<spec>` / `<id>` / `<suffix>` are validated against the D-36 grammar before interpolation — a
  fixture feeds a metacharacter/`..`-bearing value and asserts it is rejected (no shell execution, no
  path escape); a guard over this bundle's dispatch/tower sources asserts the dispatch primitive is
  the **only** worktree-creation path in the bundle that shells out to `git worktree` (grep /
  call-site allowlist), so the exception (D-7) stays narrow; **collision/orphan fixtures** assert that
  a *live* concurrent/repeat dispatch aborts as already-in-flight (via `git worktree add -b`'s atomic
  non-zero exit, not a pre-check), while a *stale* orphan — a dead branch or worktree with no live
  session, a leftover empty `<suffix>` dir, and a partial create (branch made, worktree-add failed) —
  is GC-adopted / rolled back and the dispatch proceeds, never a permanent already-in-flight wedge;
  the create exit-code is asserted to gate the attach (non-zero create ⇒ no attach); the client-switch
  mitigation is designed (launch detached, or capture-and-restore the prior client attachment) and
  **asserted by a fixture**, not merely manually confirmed; the tower deny floor is asserted to deny
  the dangerous `git worktree` forms (default-branch / detach / `--force`) and the primitive's own
  `git worktree add` runs inside the literal-path script (never a classifier-exposed Bash string); a
  negative assertion confirms no model/API call in the branch-naming decision path (REQ-E1.3);
  `[manual]` confirms on a real dispatch that `--tmux=classic` (not plain `--tmux`) is used and the
  client-switch mitigation holds so a watching tower is not disrupted; tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-7 · REQ-B1.4, REQ-C1.1, REQ-C1.2, REQ-E1.3
- **Estimated effort:** 2–3 days (was 1 day; expanded at the 2026-07-20 amendment with collision/orphan
  reconcile, token validation, `<base>` pinning, and the tower-guard assertions)

### Task 11 — Launch fixture harness for the tmux rung

- **Deliverables:** A shared fixture harness for the tmux-rung launch tests this extension adds: a
  runner that bounds every launch with a timeout and fails (never hangs) on a blocking launch; a
  stub tmux whose "server" environment is built separately from the dispatcher's, so the stubbed
  session's command runs with the server's environment and not the caller's; a stub worker that
  pushes the startup confirmation row (with the launch token) by default, which a fixture can turn
  off; path assertions in canonicalized (`pwd -P`) form; stubs that write their logs and pid files
  atomically, per invocation, and reap every process they start. The bound exceeds the confirm
  step's shortened cap. Scope is the new launch fixtures and the existing cases Task 12 rewrites;
  the macOS canonicalization of the existing cases in `tests/test-fleet-dispatch-worktree.sh` stays
  with `test-throughput`.
- **Done when:** a self-test of the harness shows a deliberately blocking launch stub failing
  within the bound with a non-hang diagnosis; a stub session's command observes a variable set
  only in the stub server's environment and does not observe one set only in the dispatcher's; a
  fixture run under a symlinked temporary directory passes its path assertions; concurrent stub
  calls leave intact, non-interleaved logs; a deliberately leaked stub process makes the reaper
  self-test fail, and after the suite no process the stubs started is still running; each touched
  test file stays within its `config/test-time-budget.yml` ceiling with no budget change;
  tests/CI pass.
- **Dependencies:** 1
- **Citations:** D-10, D-11, D-15 · REQ-H1.1, REQ-H1.2, REQ-H1.4
- **Estimated effort:** 1–1.5 days

### Task 12 — Detached tmux launch with its safety arms

- **Deliverables:** Builds on the parked flight's candidate commit. The dispatch arm launches the
  worker with `tmux new-session -d -s <session> -c <physical worktree> -P -F … -- <wrapper>
  <wrapper options> <absolute claude> <launch args> [-- <prompt>]` after the create succeeds,
  turning `remain-on-exit` off in the same invocation (D-10), never switching a client and never
  waiting on the worker. The live launch is two steps: launch (returns once the session exists)
  and confirm, which until Task 13 reports started-unconfirmed; `flight-dispatch.sh` runs the
  launch under its flight lock, releases the lock, then runs the confirm step. `fleet-dispatch-env.sh`
  gains `--identity`, `--launch-token`, `--root`, `--fleet-home`, and the check-only `--check` mode
  the dispatch runs before `new-session` (D-11). The registry record is written once, after
  `new-session` succeeds, with the `-P -F` death handle. `flight-dispatch.sh` takes the session
  name for its report and hints from the launch's report line and drops its own session-name
  search. Every shipped caller treats started-unconfirmed as placed. The observe hint targets
  `'=<session>:'`. The safety arms ship in the same change, so the detached launch never exists
  unhardened: the path and session-name charsets (first byte, 128-byte cap) and the start-directory
  checks (D-12); the live standalone attach refused, its dry-run plan printing the detached plan
  (D-13); the `<base>-<hash6>_<suffix'>` session name, the live-name pre-check before any durable
  side effect, the lost-race abort that touches nothing, the undo of only this run's creations on
  any other post-create failure, and liveness probes for the new name and the prior launcher's
  spelling (basename mapped as tmux maps it) with the bare `<suffix>` and `worktree-<suffix>`
  probes removed and a charset-refused probe read as live (D-14); the refusal of a worker CLI that
  does not resolve to an absolute executable, or a `tmux` that does not resolve, before any side
  effect (D-15's first half). Seam discovery in `tests/test-fleet-registration.sh` learns the
  `tmux new-session` launch shape, with a scoped exemption for `fleet-tower-watchdog.sh`'s tower
  relaunch, so its non-vacuity floor holds once the old launch line is gone. The existing fixtures
  that assert the old launch shape (`tests/test-fleet-dispatch-worktree.sh` c10's dry-run plan and
  the `claude --worktree flight-<id> --tmux=classic` assertion in `tests/test-flight-dispatch.sh`)
  assert the detached plan.
- **Done when:** on the Task 11 harness:
  - A launch fixture returns within its bound while the stub worker keeps running, with its report
    printed and its exit status the launch outcome; a second flight dispatch from the same checkout,
    run with `PLANWRIGHT_FLIGHT_LOCK_WAIT=0` while the first's stub worker is still running,
    proceeds. The bounded case from the candidate commit is kept as the regression.
  - The session is created with `-d`; the stub worker's argv carries no `--worktree` and no
    `--tmux`; no client-moving call reaches the stub tmux. The session's start directory is the
    physical placed worktree.
  - With the stub server's environment holding a decoy `PLANWRIGHT_ROOT` and none of the pinned
    values, the worker's process environment carries the ghost-text pin, the dispatcher's root and
    fleet home, the launch token, and a handle and scope equal to the registry record's, for both
    a task and a flight dispatch, and a liveness hook run with that environment records a transition
    for the handle.
  - The wrapper's `--check` refuses a malformed or half-supplied option with exit 2, and the
    dispatch then reports the refusal with no `new-session` call.
  - The registered death handle equals the `-P -F` output, a decoy pane whose working directory is
    the worktree does not change it, and a source assertion scoped to the launch function finds no
    pane-working-directory lookup. The flight report names the session from the launch's report
    line.
  - Each refusal and failure arm has a fixture that fails when the arm is removed: a worktree path
    outside the charset (including a `#`-bearing path, refused before any tmux call); a session
    name outside the charset or over 128 bytes, driven through the name-check function (the
    dispatch only builds conforming names); a start directory removed between create and launch,
    through a test seam; a start directory that is not the placed worktree; a live standalone
    attach; a live session already holding the name (refused before the worktree, branch, marker,
    or registry record exists); a lost race (nothing removed, cleared, or written; the winner's
    worktree and marker intact); a non-race post-create failure (this run's worktree and branch
    removed and marker cleared, an adopted branch kept); a failing undo step reported by name; a
    non-absolute or non-executable worker CLI; and a `tmux` that does not resolve.
  - Liveness fixtures treat the new name and the prior launcher's spelling (including for a dotted
    repository basename) as live, a probe name the charset refuses reads as live with no
    `has-session` call, and no probe for the bare `<suffix>` or `worktree-<suffix>` remains.
  - Seam discovery finds `fleet-dispatch-worktree.sh` through the new launch shape, the tower
    relaunch stays exempt, and the discovery floor passes. c10 and the flight-dispatch assertion
    check the detached plan.
  - Until Task 13 adds the startup confirmation, a launch whose session was created reports
    started-unconfirmed (never started), and each shipped caller treats it as placed.
  - A runtime recorder, or a source check scoped to the launch function (not the file-wide no-LLM
    exemption), confirms no model or API call in the launch path (REQ-E1.3).
  - `[manual]`: on a real dispatch from inside a tmux client, the dispatch prints its report and
    exits, the operator's client stays on its session, the worker runs in the placed worktree on its
    `bootstrap` D-36 branch with no second worktree created, and its process environment shows the
    pin and the identity. That confirmation replaces REQ-B1.4's former `--tmux=classic` check.
  - tests/CI pass.
- **Dependencies:** 11
- **Citations:** D-10, D-11, D-12, D-13, D-14, D-15 · REQ-F1.1, REQ-F1.2, REQ-F1.3, REQ-F1.4,
  REQ-F1.5, REQ-G1.1, REQ-G1.2, REQ-G1.3, REQ-G1.4, REQ-G1.5, REQ-G1.6, REQ-G1.7, REQ-H1.3,
  REQ-H1.6, REQ-B1.4, REQ-E1.3
- **Estimated effort:** 4 days

### Task 13 — Startup confirmation through the worker's SessionStart hook

- **Deliverables:** A `SessionStart` arm in `fleet-liveness.sh`, wired in `hooks/hooks.json` under
  the `startup` and `resume` matchers, identity-gated like every other arm, that pushes `working`
  for the worker's handle and records the launch token in the row. The confirm step's bounded
  wait: the dispatch start captured immediately before `new-session` and handed to the confirm
  step (an unknown start never confirms); a poll at a fixed interval up to a fixed cap, both defined
  in the launch script with a test seam that shortens them; on each poll the store read first (a
  row for the handle carrying this launch's token, stamped no earlier than the start, confirms),
  then the session probe (a definite "no such session" from a reachable server is
  failed-at-startup; an unreachable server or unreadable store keeps waiting); cap expiry is
  started-unconfirmed. Failed-at-startup clears the marker the dispatch set, and for a flight the
  report names the hand removal step for its worktree. The three outcomes (started,
  failed-at-startup, started-unconfirmed) and every refusal carry distinct exit statuses, all
  documented in the primitive's usage header. Every shipped caller of the primitive
  (`flight-dispatch.sh` and the `/orchestrate` tmux dispatch path) reports started-unconfirmed as
  placed and failed-at-startup as a failure that names the cause.
- **Done when:** the hook arm writes `working` with the token for a valid identity, no-ops with no
  identity, and refuses a half-set identity without writing; an assertion over `hooks/hooks.json`
  finds the arm under both matchers. A launch fixture whose stub worker confirms reports started
  (exit 0); one whose stub session exits before confirming reports failed-at-startup with its
  status and leaves the marker cleared; one whose session stays up without confirming reports
  started-unconfirmed with its status and the handles, and each shipped caller treats it as placed
  (no re-dispatch path taken); one whose stub server is unreachable reports started-unconfirmed,
  never failed. A row stamped before the dispatch start, a row for the handle without this launch's
  token, and an unknown start time each fail to confirm. Each outcome fixture fails when its arm is
  removed. The usage header lists every exit status the launch returns. A source check scoped to
  the confirm step finds no model or API call (REQ-E1.3). `[manual]`: on a real dispatch, the
  SessionStart arm fires for the launched worker and the dispatch reports started. tests/CI pass.
- **Dependencies:** 12
- **Citations:** D-10, D-15 · REQ-F1.1, REQ-G1.5, REQ-H1.3, REQ-E1.2, REQ-E1.3
- **Estimated effort:** 1.5–2 days

### Task 14 — Launch docs, the launch-shape check, and the narrowed seam exemption

- **Deliverables:** Every shipped doc, skill, config, and script comment that describes the tmux
  rung's launch describes the detached launch: at least `scripts/fleet-dispatch-worktree.sh` (its
  header and the attach and client-switch prose), `scripts/flight-dispatch.sh` (its header and
  session comments), `scripts/tower-command-guard.sh`'s launch-shape comments,
  `scripts/fleet-dispatch-headless.sh`'s `--no-attach` prose, `skills/orchestrate/SKILL.md`,
  `doctrine/backend-capability-contract.md`, `doctrine/spec-format.md`'s attachable-worktree line,
  `docs/fleet.md`, `docs/conventions.md`, and `config/tower-settings.json`'s `_about`, plus any
  other site the check finds. The tower guard's `claude --worktree` allow is labeled as an
  operator's hand-launch, and `--no-attach` is described as creating the worktree without
  launching a worker. A mechanical check under `mise run check` scans `docs/`, `doctrine/`,
  `skills/`, `scripts/`, `config/`, and the README files (excluding `specs/`, the changelog, and
  `tests/`, whose fixtures quote the old shape as negative cases) and fails on prose that presents
  `claude --worktree`, with or without `--tmux=classic`, as the rung's worker launch. The
  seam-discovery exemption Task 12 adds for `fleet-tower-watchdog.sh` is narrowed to the
  tower-relaunch launch itself.
- **Done when:** the check fails on a fixture doc presenting either form of the old shape as the
  rung's launch and passes on the hand-launch label. It passes on the repository with the doc set
  updated. A fixture copy of `fleet-tower-watchdog.sh` (fed to the discovery through a directory
  argument or seam) adds a worker launch in the same file, and the seam discovery reports it as
  unmanifested while the tower relaunch stays exempt. The exemption stays reachable (its own
  unreached-exemption guard passes on the real file). tests/CI pass.
- **Dependencies:** 12
- **Citations:** D-10, D-13 · REQ-H1.5, REQ-H1.6
- **Estimated effort:** 1 day

### Task 15 — The session mark records its kind

- **Deliverables:** The plugin prompt hook and each skill's bring-up handshake that write
  `tower-placement`'s session mark record the kind of command that marked the session (`tower` for
  `/tower`, `orchestrate` for `/orchestrate`, bare or plugin-namespaced); a mark written as `tower`
  keeps that kind when a later `/orchestrate` refreshes it; the policy guard exposes a read of the
  kind under the store's existing safety bar. Marks written before this task carry no kind and
  read as `orchestrate`.
- **Done when:** tests show a `/tower` prompt and the `/tower` handshake each write kind `tower`,
  an `/orchestrate` prompt writes `orchestrate`, an `/orchestrate` refresh of a `tower` mark leaves
  it `tower`, a kindless mark reads `orchestrate`, and every existing mark-store test still passes.
  tests/CI pass.
- **Dependencies:** none
- **Citations:** D-18, D-19 · REQ-I1.4
- **Estimated effort:** half day

### Task 16 — The file-tool authoring floor

- **Deliverables:** One PreToolUse entry in `hooks/hooks.json` matching Edit, Write, and
  NotebookEdit, with an explicit timeout set as `tower-placement` REQ-C1.5 requires, running the
  policy guard on a new file surface. In a `tower`-kind session the surface canonicalizes the
  target (`tool_input.file_path`, or `notebook_path` for NotebookEdit) and denies, with a reason
  naming the rule and the flight route, when it lies inside the primary checkout, a linked
  worktree, or the git directory of the repository the session's working directory belongs to; it
  denies when the payload, the target, or the checkout list cannot be read; it defers otherwise. In
  an `orchestrate`-kind or unmarked session it defers through the in-shell prefilter.
- **Done when:** an adversarial suite passes: in a `tower`-kind session, Edit, Write, and
  NotebookEdit into the primary checkout, a linked worktree, and the git directory are denied, as
  are a not-yet-existing nested path, a `..` path climbing back in, and a path under a temp
  directory that is a symlink into the checkout; a temp-file target and a path outside every
  checkout defer; a malformed payload, a missing target, and an unlistable repository deny; the
  same calls defer in an `orchestrate`-kind and an unmarked session; the guard never emits allow on
  this surface. tests/CI pass.
- **Dependencies:** 15
- **Citations:** D-17, D-18 · REQ-I1.1, REQ-I1.2, REQ-I1.3, REQ-I1.5
- **Estimated effort:** 1 day

### Task 17 — Posture report, skill, and profile text

- **Deliverables:** The `/tower` bring-up and on-request posture report states whether the
  authoring floor is active, counting it active on the activation handshake `tower-placement`
  defines. `skills/tower/SKILL.md` replaces "The posture allows Edit and Write; not authoring is
  this skill's own rule" with the refusal and its route. `config/tower-settings.json`'s `_about`
  and `docs/tower-posture-delta.md` describe the plugin-wired file-tool deny for `/tower` sessions,
  that it holds over the profile's Edit and Write allow, and that shell-spelled writes are outside
  it.
- **Done when:** the posture report names the authoring floor's state in a fixture with the plugin
  floor live and in one with it missing; no shipped doc, skill, or config text still says the
  tower posture allows Edit and Write without the refusal; the instruction-budget and doc checks
  under `mise run check` pass; a live `/tower` session launched with the tower profile is refused
  a Write into its checkout and allowed one into a `mktemp` file, as the PR description records.
  tests/CI pass.
- **Dependencies:** 16
- **Citations:** D-18 · REQ-I1.1, REQ-I1.6
- **Estimated effort:** half day

## Awaiting input

## Deferred

- **Task 15** — Builds on `tower-placement`'s session mark and plugin-wired floor, which are
  not on `main` yet; the later tasks of this extension depend on it. Confidence: high.
  **Gate:** GATE(when: spec tower-placement done).
  Citations: D-19 · REQ-I1.4.
- **Retire the prior launcher's liveness probe.** D-14 keeps a liveness probe for the prior
  launcher's `<repo-basename>_worktree-<suffix'>` session spelling so workers started before the
  detached launch still read as live. Once no such worker can be running, the probe matches
  nothing and should go, as the bare `<suffix>` and `worktree-<suffix>` probes did. Confidence: high.
  **Gate:** a release containing Task 12 has shipped and the operator confirms no tmux worker
  started before it is still running.
  Citations: D-14 · REQ-G1.7.
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
