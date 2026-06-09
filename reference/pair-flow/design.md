# Pair-Flow — Design

**Status:** Active
**Last reviewed:** 2026-05-25

## Architecture: five layers

```
+-------------------------+   L5  Cross-session awareness
|  Inbox + dashboard      |       inbox files, tmux popup, macOS notifications
+-----------+-------------+
            |
+-----------+-------------+   L4  Orchestration
|  /orchestrate           |       stateless step machine, reads tasks.md
+-----------+-------------+
            |
+-----------+-------------+   L3  Autonomous resolution
|  Agent-resolvable       |       /polish, /panel-pairing recognize new bucket
+-----------+-------------+
            |
+-----------+-------------+   L2  Task execution
|  /execute-task          |       TDD, mix ci, /polish, draft PR
+-----------+-------------+
            |
+-----------+-------------+   L1  Spec lifecycle
|  /spec-draft, /spec-    |       drafts and signs off the contract
|  kickoff, /resume       |
+-------------------------+
```

Each layer is independently shippable. L5 and L1 ship first because they unlock the rest with the smallest blast radius.

## Decision log

### D-1: `tasks.md` is canonical state; no parallel `state.json`

**Decision:** The spec's `tasks.md` doubles as the orchestration state record. Sections: `Completed`, `In progress` (with phase + last-activity), `Awaiting input`, `Deferred`, `Out of scope`. Skills that change state update `tasks.md` as a side effect.

**Alternatives considered:**
- Separate `~/.claude/orchestrator/{repo}/state.json` substrate. Rejected because it creates a second source of truth that can drift from the spec, and the user's existing workflow (asking a fresh session "what's left based on the specs and progress so far") already proves the spec is sufficient.

**Chosen because:** Single source of truth. Version controlled. Already battle-tested as a resumption substrate by the user's manual workflow. Degrades gracefully (stale "in progress" entries are recoverable from PR state and git log).

**Reversed by:** —

### D-2: Two-brief model — kickoff is contract, handover is optional cache

**Decision:** The kickoff brief (`specs/{feature}/kickoff-brief.md`) is the durable contract between human and agent at spec time. The handover brief (`{worktree}/.claude/handover.md`) is an optional cache of non-obvious in-flight context that does not fit in `tasks.md`. `/resume` reads kickoff + `tasks.md` + git + PR; layers handover if present.

**Alternatives considered:**
- Handover-brief-first design where every session exit auto-writes a brief and the next session refuses to start without one. Rejected because it makes the system brittle (missing or stale brief becomes a hard failure) and adds friction the spec system already absorbs.
- No handover at all. Rejected because some context genuinely doesn't fit in `tasks.md` ("I considered approach P and rejected because Q"), and a freeform brief is the lightest way to capture it.

**Chosen because:** Robust under partial failure. Spec is always correct; handover is best-effort. Matches the user's existing mental model.

### D-3: `Agent-resolvable` bucket predicate

**Decision:** Findings qualify for the new `Agent-resolvable` bucket if and only if all five hold: (a) failing test exists that fails for the finding's reason on current code, (b) test passes after the fix, (c) full project CI passes after the fix, (d) the fix is aligned with the active kickoff brief, (e) the fix is not in a hard-disqualifier zone (security primitives, migrations, public API contracts, secrets, CI configuration).

**Alternatives considered:**
- Loosen `Auto-applicable` predicate instead of adding a fourth bucket. Rejected because the existing predicate is well-designed for "mechanical, no behavior change" and changing it would muddy that contract.
- Per-finding judgment instead of a fixed predicate. Rejected because per-finding judgment is what produces the 85% Needs human judgment rate observed in transcripts.

**Chosen because:** Captures the user's stated risk tolerance ("agents should resolve issues the way a human would, with regression tests and validation") without weakening any existing bucket.

**Open calibration:** The predicate is initial; the line between `Agent-resolvable` and `Needs sign-off` will be calibrated by accepting/rejecting agent-resolved changes over a few weeks. See Task 13 (end-to-end validation).

### D-4: Solo vs multi-reviewer behavior split

**Decision:** In solo repos (tecpan, dotfiles), `Agent-resolvable` auto-applies. In multi-reviewer repos (a work project), `Agent-resolvable` surfaces for human review with evidence (failing-then-passing test, CI output, kickoff alignment) attached. Determination is per-repo via a config marker (see D-15).

**Alternatives considered:**
- Always require human approval. Rejected; the user explicitly wants autonomy in solo repos.
- Always auto-apply. Rejected; multi-reviewer repos have peer review for reasons that outlast our process.

**Chosen because:** Matches the existing review topology of the user's repos. The Discovery Rigor + Validation Rigor work already done is the warrant for autonomy in solo repos.

### D-5: Stateless orchestrator step machine

**Decision:** `/orchestrate` does not maintain process-internal state. Each invocation reads `tasks.md`, computes the next legal move, performs it, updates `tasks.md`, exits. Multiple invocations across sessions / hosts / scheduled runs accumulate naturally.

**Alternatives considered:**
- Long-running orchestrator process. Rejected because Claude Code is interactive and tied to a session; process longevity is not a primitive we have.
- LangGraph / Crew-AI for stateful orchestration. Rejected; pulling in a second agent framework duplicates concerns and increases debugging surface.

**Chosen because:** Survives session boundaries by construction. No state to corrupt. Compatible with scheduled remote agent runners.

### D-6: Profile-aware panel backend defaults

**Decision:** Codex is the default backend on the work profile. Personal and alt profiles default to Gemini 2.5 Pro (user does not want to fund OpenAI for personal use). The `--backends` flag remains available for explicit overrides on any profile. `pair-flow.yml` keeps `panel-backends: [codex]` as the universal tracked default; personal/alt hosts override via `pair-flow.local.yml` with `panel-backends: [gemini]`. No host-conditional logic in the tracked file; the existing two-file merge handles it.

**Alternatives considered:**
- Codex + one Ollama model for variance. Rejected per user direction; simplification preferred for v1.
- Keep current `codex,qwen-coder` (work) / `qwen-coder,gpt-oss` (personal) split. Rejected per user direction.
- Codex on all profiles. Rejected after user indicated personal/alt should not incur OpenAI costs.

**Chosen because:** User instruction. Task 1 confirmed panel is newly available, not underused, making the "provisional" qualifier unnecessary. Variance comes back as an opt-in via the existing `--backends` flag if needed.

**Amendment (Task 13, from kickoff brief walkthrough):** Original decision was "codex-only on all profiles (provisional)." Amended to profile-aware split. "Provisional" qualifier dropped.

### D-7: `/spec-kickoff` is a didactic walkthrough, not a checklist

**Decision:** `/spec-kickoff` walks the spec section by section, restating in the agent's own words, surfacing implicit domain term definitions, and posing Socratic checks (slicing sanity, edge cases, decision rationale) at each step. The output is rich enough that any downstream agent operates from the brief without re-reading the spec.

**Alternatives considered:**
- Structured questionnaire. Rejected because it forces user reflection without surfacing agent misreads.
- Pure restatement (no questions). Rejected because it doesn't verify that the user shares the understanding.

**Chosen because:** The user explicitly framed this as "thorough, methodical, didactic" and the value is in the questions surfacing things neither party realized needed to be said.

**Quality gate:** First implementation will be evaluated on whether elicitation surfaces things the user did not already know. If not, the design is wrong and the questions need sharpening.

### D-8: Gherkin optional within `test-spec.md`, not mandatory

**Decision:** Gherkin (`Given / When / Then`) scenarios are permitted as a format within `test-spec.md` when behaviors benefit from explicit state/trigger/outcome separation. Not introduced as a separate runner. Not required for any REQ.

**Alternatives considered:**
- Mandate Gherkin across all test-spec entries. Rejected; design decisions and reference material don't fit Gherkin shape.
- Reject Gherkin entirely. Rejected; the format genuinely helps for edge-case enumeration and stakeholder communication.
- Adopt an Elixir Gherkin runner (cabbage, white-bread). Rejected; adds tooling for marginal value when ExUnit already runs tests.

**Chosen because:** Additive, low cost, only used where useful.

### D-9: Skill hooks update `tasks.md` as side effects

**Decision:** `/execute-task` updates `tasks.md` when implementation starts, when a PR opens, and when execution halts. `/orchestrate` updates `tasks.md` when picking a task. A PostToolUse hook (in-session merges) or the scheduled runner (D-29, out-of-session merges) updates `tasks.md` when a PR merges. The discipline is not the human's job.

**Alternatives considered:**
- Manual maintenance. Rejected; would silently drift, undermining `tasks.md` as state.
- A daemon that syncs `tasks.md` from GitHub. Rejected; needs a long-running process we don't have.

**Chosen because:** Pushes the discipline into the skills, which already touch git/PR.

### D-10: Inbox substrate via shared filesystem

**Decision:** Inbox lives at `~/.claude/inbox/` synced across hosts via iCloud Drive or Syncthing. Each file is one session's current state. Writers: every skill that changes state. Readers: tmux popup and status segment.

**Alternatives considered:**
- HTTP server hosting state. Rejected; needs a host, auth, deployment.
- Git-backed (commit state to a config repo). Rejected; commit cadence too coarse for live state.
- Push channel (Pushover, ntfy). Deferred to a later layer; the file substrate is what push would read.

**Chosen because:** Zero infrastructure. Sync mechanism already in place on the user's machines.

### D-11: Bundling rule for multi-task PRs

**Decision:** `/orchestrate` may bundle consecutive ready tasks into a single PR when all hold: (a) tasks touch the same module or context, (b) tasks share dependencies, (c) combined diff is likely to stay under ~700 lines (estimated from spec citations + git history of similar tasks).

**Alternatives considered:**
- Always one task per PR. Rejected; tecpan history shows the user already bundles when tasks are tightly related.
- Bundle aggressively up to some line ceiling. Rejected; module/dependency cohesion is more important than line count.

**Chosen because:** Matches observed user behavior. The 700-line ceiling is calibrated from tecpan's PR size distribution (300–900 typical).

### D-12: `/panel-pairing` demoted to escalation; `/polish` is the default convergence loop

**Decision:** `/polish` runs as the inner convergence loop of `/execute-task`. `/panel-pairing` runs only as an escalation when extra rigor is warranted (security-adjacent, large diff, novel area) or when explicitly invoked by the user.

**Alternatives considered:**
- Run `/panel-pairing` on every task. Rejected; external backends are slow, and the panel-* underuse evidence suggests cost > yield by default.
- Retire `/panel-pairing` entirely. Deferred until Task 1 investigation lands.

**Chosen because:** Keeps the variance benefit available when needed without paying for it on every task.

### D-13: `/polish` opens a draft PR on convergence (standalone mode)

**Decision:** When `/polish` is invoked standalone (not nested in `/execute-task`), it opens a draft PR after converging. When nested, the parent owns PR creation.

**Alternatives considered:**
- Standalone `/polish` stays local-only. Rejected; the user often wants a draft PR after polishing manual changes, and the missing step is friction.
- Always open PR even when nested. Rejected; would create double PRs.

**Chosen because:** Removes a manual handoff step in the common standalone case without breaking the nested case.

### D-14: Scheduled remote agent runner for non-implementation orchestration moves

**Decision:** A scheduled remote agent (via the existing `/schedule` skill) runs periodically (e.g., hourly) and performs orchestration moves that do not require an interactive session: check PR merge status, mark Completed, pick the next ready task and post inbox entry, reconcile stale `In progress` entries. It does not implement code.

**Alternatives considered:**
- macOS launchd / cron locally. Rejected; doesn't reach across hosts and duplicates the existing scheduled-agent primitive.
- No background runner; everything happens interactively. Rejected; user wants "while you're asleep, advance the bookkeeping."

**Chosen because:** Uses an existing primitive. Cross-host by construction.

### D-15: Spec format requirements for orchestration

**Decision:** For a spec to be orchestratable, each task in `tasks.md` shall have: a stable ID, a `Done when:` condition unambiguous enough for an agent to evaluate, explicit `Dependencies:`, and `Citations:`. Repo-level metadata (e.g., `repo-class`) is handled separately per D-19, not embedded in the spec bundle.

**Alternatives considered:**
- Looser format with agent inference. Rejected; the org/ retrospective shows agent inference fails on prose-only specs.
- Embedding repo-level metadata per spec. Initially considered (`Repo-class:` line in `tasks.md` or a top-level `specs/spec-config.yml`). Reversed by D-19: the metadata is per-repo, not per-spec, and putting it in shared repos leaks personal workflow choices.

**Chosen because:** The existing tecpan format is 95% of the way there. The gap is enforcement.

**Reversed (partial) by:** D-19 — the repo-level metadata portion of this decision moved to a user-home config.

### D-16: Headless invocation (`claude -p`) is v2

**Decision:** v1 ships without headless `claude -p` resumption. Sessions are launched interactively by the user (typing `/resume` in a tmux pane) or by scheduled remote agents (which don't need TTY for bookkeeping moves). Headless invocation for implementation work is deferred until v1 proves stable.

**Alternatives considered:**
- Headless from day one. Rejected; risk of failure modes that are hard to debug when there's no human watching.
- Never headless. Rejected; deferring is appropriate, but the option should remain on the table.

**Chosen because:** Smaller v1 risk surface. Easier to reason about failures when a human is in the loop initially.

### D-17: Orchestrator concurrency via advisory lockfile

**Decision:** `/orchestrate` acquires an advisory lockfile (per-spec, at `specs/{feature}/.orchestrate.lock` per D-37) before performing state-changing moves: task selection, worktree creation, `tasks.md` updates. The lock is released before `/execute-task` runs, allowing intra-spec parallelism per D-52. Lock acquisition failure is a clean no-op (exit with reason logged to inbox), not an error.

**Alternatives considered:**
- No locking. Rejected; multi-host runners could collide on state-changing moves.
- Heavyweight locking (e.g., Redis). Rejected; we don't have shared infrastructure beyond a synced filesystem.
- Hold the lock for the duration of `/execute-task`. Rejected; would block intra-spec parallelism, which the user's existing workflow depends on.

**Chosen because:** Cheap, robust to crashes (stale locks can be detected and broken), no new infrastructure. Short lock window unblocks parallel execution.

**Stale-lock threshold:** locks older than 15 minutes (per `pair-flow.yml` `stale-lock-threshold`) are treated as stale and may be broken by the next runner. Post-D-52, the lock is held only during task selection (seconds). A lock older than a few seconds is anomalous. The 15-minute threshold accounts for iCloud sync lag (worst case ~5 min) without false positives, while recovering from crashes within one scheduled-runner cycle.

**Amendment (Task 13, from kickoff brief walkthrough):** Original threshold was 1 hour, sized for "lock held during execution." D-52 moved lock release before execution, making the 1-hour window unnecessarily wide. Reduced to 15 minutes.

### D-18: Build only on Claude Code primitives

**Decision:** The entire system is built using Claude Code's existing primitives (skills, hooks, slash commands, scheduled remote agents, file-based state). No second agent framework is introduced. Inspiration may be drawn from Aider, Cline, Plandex, GitHub Spec Kit, BMad Method, but their code or runtimes are not imported.

**Alternatives considered:**
- LangGraph for orchestration. Rejected per the analysis.
- GitHub Spec Kit as a dependency. Rejected; templates can be cherry-picked but a hard dependency adds upgrade risk.

**Chosen because:** Minimizes maintenance surface. Survives Claude Code upgrades. Easy to debug because everything is files and well-known skills.

### D-19: Configuration model — two-file split with agent-maintained local file

**Decision:** Pair-flow configuration lives in two files at the user's home:

- `~/.claude/pair-flow.yml` (tracked in dotfiles, materialized as symlink): schema and defaults. Fields: `panel-backends`, `stale-lock-threshold`, `inbox-heartbeat-interval`, etc.
- `~/.claude/pair-flow.local.yml` (gitignored, agent-maintained, host-local): the `repos:` block keyed by `owner/repo` with per-repo overrides (`repo-class`, `last-confirmed`).

Repo-objective values (`ci-command`, `default-branch`, language) are derived by project inspection (`mix.exs` aliases, `package.json` scripts, `mise.toml` tasks, lefthook hooks, `gh repo view`), not declared in either config file. The SessionStart tool-discovery hook already performs most of this derivation.

Per-spec overrides remain available via a `Config overrides:` frontmatter section in a spec's `requirements.md` for the rare experimental case.

**Alternatives considered:**
- Single config file `specs/spec-config.yml` inside each shared repo. Rejected: leaks personal workflow into shared repos; `repo-class: solo` is meaningless from a collaborator's perspective.
- Per-spec line in `tasks.md`. Rejected: doesn't match the data model (none of the values vary per spec) and creates drift risk across specs in the same repo.
- Single file under `~/.claude/`, tracked in dotfiles, including the `repos:` block. Rejected: dotfiles is published; the `repos:` block would expose which repos the user treats as solo vs multi-reviewer.

**Chosen because:** Clean separation between universal facts (derived from repo) and personal workflow (in user's home). Matches the existing three-layer permissions model in dotfiles. Discovery flow per D-20 makes the local file effectively zero-config.

### D-20: Configuration discovery flow

**Decision:** When a pair-flow skill encounters a repo with no entry in `~/.claude/pair-flow.local.yml`:

1. Identify the repo via `gh repo view --json nameWithOwner`, falling back to parsing `git remote get-url origin`.
2. Infer a default `repo-class` from PR review history (any non-author human reviewer in the last 30 PRs → `multi-reviewer`; otherwise → `solo`).
3. **Always surface the inferred value for confirmation.** Discovery never silently writes — the cost of guessing `solo` on a `multi-reviewer` repo is auto-applying changes that should have gone through review.
4. On user confirmation, append the entry (with `last-confirmed: <today>`) to `~/.claude/pair-flow.local.yml`. Create the file if it does not exist.
5. On subsequent invocations, the entry is present and no prompt fires.

If the file is deleted or corrupted, discovery re-runs from scratch on the next invocation. One prompt per repo encountered; no permanent loss.

**Alternatives considered:**
- Silent inference. Rejected: any miscalibration auto-applies changes in a multi-reviewer repo.
- Require manual setup before any pair-flow skill runs. Rejected: creates a bootstrap step the user must remember on every new machine.

**Chosen because:** Zero-config bootstrap, safe-by-default. Graceful degradation on file loss.

### D-21: PRs are always drafts; no auto-merge, ever

**Decision:** Every PR created by any pair-flow skill (`/polish`, `/execute-task`, `/orchestrate`) shall be a draft PR. The system shall not include auto-merge functionality at any tier (v1, v2, future). Merge is one of the few human actions reserved by the user.

**Alternatives considered:**
- Defer auto-merge as a future feature. Rejected: the user has explicitly stated this is a permanent constraint, not a future capability. Listing it as deferred implies eventual inclusion, which is incorrect.

**Chosen because:** Hard guarantee preserves human control at the merge boundary.

### D-22: Dashboard visual language

**Decision:** The tmux dashboard popup renders inbox entries with the following visual language and sort order:

| State | Color | Meaning |
|---|---|---|
| awaiting-input | red | needs human now |
| stale lock | red, strikethrough | suspected crash, needs cleanup |
| working, very long (>2 hr) | orange | check whether stuck |
| draft-pr-ready | blue | clean handoff for review |
| working, long (>30 min) | yellow | still going, worth a glance |
| working, fresh | green | active, recent activity |
| idle / exited | grey | nothing happening |

Sort order: red → orange → blue → yellow → green → grey. Duration is computed from the entry's `last-heartbeat` and first-seen timestamp.

**Alternatives considered:**
- Flat list with no color. Rejected: the user explicitly asked for long-running task hints.
- Notification-only (no dashboard color). Rejected: notifications miss the long-running case, which is gradual rather than transitional.

**Chosen because:** Glanceable at-a-glance signal. The user can see "one red, two yellows" in a second.

### D-23: Inbox heartbeat mechanism

**Decision:** Each active session writes its inbox entry with a `last-heartbeat` ISO timestamp, refreshed every 30 seconds via a background helper. Entries are considered:

- **Live:** heartbeat within last 60 seconds.
- **Stale:** heartbeat older than 2 minutes — auto-removed by readers (dashboard, status segment) before display.
- **Legacy (no heartbeat field):** aged out at 24 hours as a fallback for entries written by older skill versions.

On clean session exit, the session removes its own entry.

**Alternatives considered:**
- File mtime as the heartbeat. Rejected: mtimes are unreliable across sync mechanisms (iCloud, Syncthing); explicit timestamps in JSON are durable.
- Longer heartbeat interval (5 minutes). Rejected: a crashed session would appear live for too long.
- A daemon managing all heartbeats. Rejected: introduces a long-running process where none is needed.

**Chosen because:** Catches crashes within ~2 minutes (matching the user's instinct that "inactive sessions" should clear quickly), at low cost (30s tick, write a small JSON file).

### D-24: Bundle sizing via Citations + git history (provisional)

**Decision:** `/orchestrate` estimates a candidate bundle's combined diff size by: (1) counting files in each candidate task's `Citations:`; (2) looking up similar past PRs in the same repo via `gh pr list --search` keyed on cited files and module; (3) summing the median PR size of matched past PRs. Bundle is approved if the estimate is ≤ 700 lines and the other D-11 conditions (same module, shared deps) hold.

Estimate-vs-actual is logged for telemetry per D-30 so the heuristic can be tuned.

**Low-data fallback:** When `gh pr list --search` returns fewer than 5 relevant PRs, fall back to the `Estimated effort` field: half day = ≤300 lines, 1 day = ≤500 lines, 2 days = ≤700 lines. Bundle only if the sum stays ≤700. Grounded in data already in the spec (Estimated effort is required per task). Telemetry (D-30) calibrates the multipliers over time.

**Alternatives considered:**
- Conservative (one task per PR; manual bundling only). Rejected: tecpan PR history shows bundling happens organically when tasks are related; the orchestrator should support it natively.
- Author-hint S/M/L during `/spec-draft`. Reserved as a fallback if the citations heuristic proves inaccurate during Task 13's validation.

**Chosen because:** Citations + git history gives a grounded estimate without asking the user to think about line counts during drafting.

**Provisional:** Heuristic accuracy will be measured during Task 13. If consistently off by more than 2x, switch to author-hint mode.

**Amendment (Task 13, from kickoff brief walkthrough):** Added effort-based fallback for low-data repos (< 5 matching PRs).

### D-25: `/execute-task` CI retry policy is adaptive

**Decision:** When the project CI run fails, `/execute-task` classifies the failure and acts accordingly:

- **Transient** (network errors, timeouts, known-flaky test patterns, infrastructure errors): retry up to 2 times with exponential backoff.
- **Logic** (assertion failures, type errors, compilation errors, anything reproducible): escalate immediately to `Awaiting input` without retry.

Classification is based on the CI output. Unknown patterns default to "logic" — safer to escalate than to burn retries on a real problem.

**Alternatives considered:**
- Fixed N retries regardless of cause. Rejected: burns time on logic errors that will never pass.
- One try, then escalate immediately. Rejected: too aggressive on transient failures, especially when CI infrastructure is flaky.

**Chosen because:** Matches how a human developer triages CI failures.

### D-26: File-path PreToolUse hook scope

**Decision:** The PreToolUse hook validates file paths for `Read`, `Edit`, and `Write` tool calls. `Bash` invocations with file arguments are out of scope (paths are too hard to parse statically from arbitrary shell). `NotebookEdit` is out of scope for v1 (low usage in transcripts).

**Alternatives considered:**
- All file-touching tools including Bash. Rejected: high false-positive risk on shell path parsing.
- Read + Edit only. Rejected: Write also surfaces path mistakes (typos in new file paths).

**Chosen because:** Targets the three highest-yield tools per the April–May friction data without false positives from Bash heuristics.

### D-27: Kickoff brief invalidation is section-scoped

**Decision:** When a spec file changes after the brief is signed off, only the brief sections tied to the changed content require re-signoff:

- Change to `requirements.md` REQ-X → brief sections referencing REQ-X invalidate.
- Change to `design.md` D-Y → brief sections referencing D-Y invalidate.
- Change to `tasks.md` (reorder, retitle, add, remove) → only the Task graph section invalidates.
- Change to `test-spec.md` → only the Verification section invalidates.

Whole-brief invalidation occurs only on a wholesale spec rewrite (multiple files changed simultaneously beyond a threshold).

**Alternatives considered:**
- Whole-brief invalidation on any change. Rejected: forces re-walkthrough every time `tasks.md` is reorganized, which happens often during execution.
- No invalidation tracking. Rejected: defeats the purpose of the brief as a contract.

**Chosen because:** Less disruptive while preserving contract integrity.

### D-28: Validator reuse via port + symlink

**Decision:** The spec validator that lives near `tecpan/specs/validator-runs.md` is ported into this dotfiles repo at `roles/osx/files/claude/scripts/spec-validate.sh`. Both repos symlink to the canonical location. Future extensions land here; tecpan inherits via symlink.

**Alternatives considered:**
- Write a new validator for pair-flow specs. Rejected: duplicate logic.
- Keep tecpan's validator in tecpan and copy-paste here. Rejected: drift risk.

**Chosen because:** Single source of truth, propagated by the existing Ansible symlink mechanism.

### D-29: PR-merge detection via scheduled runner (no webhook)

**Decision:** Detection of "this PR was merged, mark the task Completed" happens via the scheduled remote agent runner (Task 12) polling GitHub PR state on its cadence (hourly default). No GitHub webhook is configured.

**Alternatives considered:**
- GitHub webhook firing a local hook. Rejected: requires GitHub config, an internet-reachable endpoint (or a polling service), and a secret.
- Manual `/sync-tasks` invocation. Rejected: relies on the user remembering after every merge.

**Chosen because:** The scheduled runner exists anyway for other bookkeeping; PR-merge reconciliation is a near-free additional move. Hourly latency is acceptable for state propagation.

### D-30: Telemetry hybrid layout

**Decision:** Telemetry lives under `specs/metrics-baseline/` in three subdirectories:

- `snapshots/baseline-{YYYY-MM}.md.age` — periodic markdown summaries (monthly cadence). Continues existing pattern.
- `deltas/pair-flow-v1-{milestone}.md.age` — initiative-specific markdown deltas tied to milestones (pre-rollout, post-Task 13, 30-day-post).
- `data/{YYYY-MM}.jsonl.age` — raw structured measurements supporting both summaries.

All three are age-encrypted with the existing key (consistent with the current `baseline-2026-04.md.age` precedent).

Each pair-flow task that introduces measurable behavior shall include a "Measurement plan" line in its `Done when:` enumerating the metric, source, and baseline comparison.

**Alternatives considered:**
- Markdown only (snapshots + deltas, no structured data). Rejected: future analyses cannot re-derive from a one-way summary.
- Snapshots only (no deltas). Rejected: loses initiative attribution.
- New top-level `metrics/` directory. Rejected: yet another top-level concept with no clear win over extending `metrics-baseline/`.
- `~/.claude/telemetry/`. Rejected: not version controlled, lost on machine reset.

**Chosen because:** Builds on existing pattern. Initiative-specific attribution plus raw data enables reproducibility.

### D-31: Spec status lifecycle (Draft → Active → Done)

**Decision:** A spec moves through three states declared in `requirements.md` as `**Status:** Draft|Active|Done`. `Draft` is being authored; `Active` is signed off and under execution; `Done` is all tasks Completed. `/spec-draft` writes Draft; `/spec-kickoff` flips to Active on sign-off; `/orchestrate` (or Task 12's bookkeeping runner) flips to Done when the last task moves to Completed.

**Alternatives considered:**
- `Draft → Active` only. Rejected: can't tell at a glance which specs are still in flight.
- `Draft → Approved → Active → Done` with stakeholder Approved state. Rejected for v1: solo proving ground doesn't need it; can be added for multi-reviewer projects later.

**Chosen because:** Three-state machine is enough granularity for "what's done" without overhead.

### D-32: Branch naming for orchestrator-created branches

**Decision:** `pair-flow/{spec}/task-{id-or-ids}`. Examples: `pair-flow/auth/task-3`, `pair-flow/auth/task-3-4` for a bundle. User overrides allowed when running `/execute-task` standalone.

**Alternatives considered:**
- `{spec}/task-{id}` without namespace. Rejected: doesn't signal pair-flow ownership.
- Flat `{spec}-task-{id}`. Rejected: loses hierarchical grouping in tools.

**Chosen because:** Namespaced, machine-parseable, signals ownership.

### D-33: No bypass mode for `/spec-kickoff`

**Decision:** `/execute-task` and `/orchestrate` refuse to act on a spec that has not been signed off via `/spec-kickoff`. No `--no-kickoff` flag, no emergency bypass, no post-hoc kickoff.

**Alternatives considered:**
- Explicit `--no-kickoff` emergency flag. Rejected: creates a backdoor that erodes over time.
- Post-hoc kickoff. Rejected: more complex state, defeats the contract.

**Chosen because:** The kickoff IS the contract; skipping it defeats pair-flow's purpose. Manual work outside pair-flow remains available for emergencies.

### D-34: Inbox keyed per-session, presented per-worktree

**Decision:** Inbox JSON files are keyed by Claude Code session UUID: `{host}-{session-uuid}.json`. Contents include the worktree path and branch so the dashboard groups by worktree.

The dashboard popup renders one row per worktree, aggregating contributing session entries. Sort and color (D-22) apply to the aggregated row using the most urgent contributor's state. Sequential sessions in the same worktree appear as one row across time (prior session's file self-removes on exit; new session writes fresh). Concurrent sessions in the same worktree (rare) appear as one row with a "(N sessions)" annotation.

**Alternatives considered:**
- Key by worktree path. Rejected: collisions when sessions overlap.
- Key by tmux pane. Rejected: noise when one task spans multiple panes.

**Chosen because:** Per-session keying keeps the data model clean; per-worktree presentation matches the user's mental model ("what work is happening in this worktree").

### D-35: `/spec-kickoff` re-walkthrough on partial invalidation

**Decision:** When the brief is partially invalidated (D-27), `/spec-kickoff` walks only the invalidated sections. A one-line summary of unchanged sections is shown at the start to anchor context.

**Alternatives considered:**
- Full re-walkthrough every time. Rejected: defeats D-27's scoping.
- Silent update without re-signoff. Rejected: the brief is a contract.

**Chosen because:** Surgical; respects user time.

### D-36: `/orchestrate` on unkickoffed specs

**Decision:** When `/orchestrate` encounters a spec without a kickoff brief (or whose brief is fully invalidated by a wholesale spec rewrite), it halts cleanly and prompts the user to invoke `/spec-kickoff`. It does not auto-chain into kickoff.

**Alternatives considered:**
- Auto-invoke kickoff. Rejected: kickoff is an interactive walkthrough that wants undivided attention.
- Proceed without brief. Rejected per D-33.

**Chosen because:** Hard separation between authoring/signoff and execution.

### D-37: Cross-spec concurrent `/orchestrate` is allowed

**Decision:** Two `/orchestrate` invocations on different specs in the same repo proceed independently. Locking (D-17) is per-spec via `specs/{feature}/.orchestrate.lock` and held only during state-changing moves (task selection, `tasks.md` updates), not for the duration of `/execute-task`. Concurrent state mutations on the same spec are serialized via the lock; concurrent task execution on the same spec is allowed and is the basis for intra-spec parallelism per D-52.

**Alternatives considered:**
- Repo-wide lock. Rejected: serializes unrelated work.
- Per-spec lock held until execution completes. Rejected: blocks intra-spec parallel tasks.

**Chosen because:** Specs are the orchestration unit; nothing requires repo-wide serialization or full-duration locking.

### D-38: Measurement plan convention

**Decision:** Tasks that introduce measurable behavior include a `**Measurement plan:**` line listing metric, source, and baseline comparison. Same shape and discipline as `Citations:`. Documented in `specs/README.md`.

**Alternatives considered:**
- Separate metrics file per spec. Rejected: fragments the plan from the change.

**Chosen because:** Lightweight, mirrors an existing convention.

### D-39: Skill-to-skill invocation is in-session

**Decision:** When `/execute-task` invokes `/polish` internally, it is a sub-step within the same Claude Code session, not a separately-launched skill. Hooks fire once per actual tool call. Inbox state remains owned by the outer skill.

**Alternatives considered:**
- Spawn sub-sessions for inner skills. Rejected: doubles hook firings; complicates state ownership.

**Chosen because:** Skills compose as functions, not as separate processes.

### D-40: `Last reviewed:` auto-update

**Decision:** `/spec-draft` and `/spec-kickoff` update each modified spec file's `Last reviewed:` line to today's date as a side effect of any change they make. Humans set it manually on direct edits.

**Alternatives considered:**
- No auto-update. Rejected: drifts immediately.
- Auto-update via git hook. Rejected: would touch files the human didn't intend to update.

**Chosen because:** Lightweight mechanical hygiene by the right actors.

### D-41: Kickoff brief written incrementally

**Decision:** `/spec-kickoff` writes the brief section-by-section as each section is signed off, not atomically at the end. A killed session leaves a partial brief; the next `/spec-kickoff` invocation detects it and resumes from the next unsigned section.

**Alternatives considered:**
- Atomic write at end. Rejected: discarding 20 minutes of walkthrough on Ctrl+C is hostile.

**Chosen because:** Robust against interruption.

### D-42: `/spec-kickoff` "spec looks wrong" escalation

**Decision:** When walkthrough surfaces a genuine inconsistency in the spec (REQs contradict, design conflicts with requirement, etc.), `/spec-kickoff` halts without producing a brief. User chooses: (a) edit the spec (back to `/spec-draft` or manual) and re-run, or (b) record an explicit override in the brief explaining why the apparent inconsistency is intentional.

**Alternatives considered:**
- Force resolution in the spec. Rejected: sometimes the apparent inconsistency is intentional.
- Continue silently. Rejected: defeats the brief's purpose.

**Chosen because:** Honors user authority while keeping the disagreement on record.

### D-43: `gh` authentication failure handling

**Decision:** Pair-flow skills degrade gracefully when `gh` is unauthenticated:
- PR-related operations (open PR, query PR state, reconcile merges) halt with a clear "run `gh auth login`" message.
- Local-only operations (`/polish` without PR opening, `/spec-kickoff`, `/spec-draft`) proceed.
- `/orchestrate` halts and writes an `Awaiting input` inbox entry mid-cycle if it cannot reach the PR API.

**Alternatives considered:**
- Hard failure on any gh dependency. Rejected: blocks work that doesn't need gh.

**Chosen because:** Maximizes useful work in the degraded state without faking success.

### D-44: Worktree ownership split

**Decision:** `/orchestrate` creates worktrees as it picks new tasks, *unless it can reuse the current one* per D-54. `/execute-task` assumes the worktree exists (created or reused by the orchestrator, or manually by the user when running standalone). Worktree path placement follows D-54 (under `<repo>/.claude/worktrees/<branch-suffix>` so Claude Code's native `--worktree` / `EnterWorktree` tooling discovers it), resolved by the worktree-bootstrap hook either way.

**Alternatives considered:**
- `/execute-task` creates its own worktree. Rejected: would double-create when run inside `/orchestrate`; manual-create overhead in standalone use is small.

**Chosen because:** Clear ownership boundary; `/execute-task` stays usable both standalone and nested.

### D-54: Worktree reuse and `claude --worktree` interop

**Decision:** `/orchestrate`'s dispatch step does not unconditionally `git worktree add`. It first resolves where the task should run, then creates or reuses:

1. **Detect.** Determine whether the session is already inside a linked worktree via the worktree predicate (`git rev-parse --git-dir` ≠ `git rev-parse --git-common-dir`; equal means the primary checkout). This is the same predicate the worktree-bootstrap hook uses.
2. **Reuse a clean worktree (confirm only).** If already inside a worktree and it is clean (no uncommitted changes), `/orchestrate` reuses it instead of creating a new one. It surfaces the worktree path and branch and asks the user for a one-line confirmation before proceeding (no full prompt).
3. **Ask in the primary checkout.** If in the primary checkout (or in a worktree the user does not want to reuse), `/orchestrate` asks the user where to do the work: (a) the current checkout/branch, or (b) a fresh worktree. The user may also have pre-directed this (e.g. "implement in the current branch"), in which case the answer is taken as given and no question is posed.
4. **Create under the Claude-native path.** When a fresh worktree is created, it is placed at `<repo>/.claude/worktrees/<branch-suffix>` (the directory `claude --worktree` and the `EnterWorktree` tool discover), not the legacy sibling `<repo>--claude-worktrees-<branch-suffix>`. Branch naming stays D-32 (`pair-flow/<spec>/task-<ids>`).
5. **Tell the user how to re-open it.** After creating or reusing a worktree, `/orchestrate` prints the exact command to re-open that worktree in a fresh Claude Code session: `cd <repo>/.claude/worktrees/<branch-suffix> && claude`. (`claude --worktree <name>` always *creates* a new worktree rather than attaching, so the `cd` + `claude` form is the correct re-open path.)

**Alternatives considered:**
- Adopt `claude --worktree`'s `worktree-<name>` branch naming for full transparency. Rejected: it breaks D-32, which `tasks-pr-sync.sh`, `skill-contracts.sh`, and `/resume` all parse to map a branch back to its task. Only the worktree *directory* placement needs to match for `EnterWorktree` discovery; the branch name can stay D-32.
- Keep the legacy sibling `<repo>--claude-worktrees-<branch-suffix>` path. Rejected: invisible to `claude --worktree` / `EnterWorktree`, so a user cannot re-open or switch to it with native tooling.
- Always `git worktree add` (status quo). Rejected: redundant and confusing when the user is already sitting in a suitable clean worktree, or has explicitly asked to work in the current branch.

**Chosen because:** Places worktrees where Claude Code's native worktree tooling looks while preserving the D-32 branch contract the rest of the pipeline depends on. Detect-and-reuse (with a lightweight confirm) avoids redundant worktrees and respects an explicit "work here" instruction; the re-open hint closes the loop so a backgrounded task is trivially resumable in a fresh session.

### D-45: Validator extended for D-15 task structure, status-aware enforcement

**Decision:** The ported validator (D-28) is extended to check each task in `tasks.md` has a stable ID, a `Done when:` condition, explicit `Dependencies:`, and explicit `Citations:`. Enforcement is status-aware:
- `Draft` status: validator failures are warnings (informative, non-blocking).
- `Active` status: validator failures are errors (block `/execute-task`, `/orchestrate`).

**Alternatives considered:**
- Block at Draft. Rejected: too rigid during authoring.
- No extension. Rejected: format compliance drifts without enforcement.

**Chosen because:** Status-aware enforcement matches the spec lifecycle (D-31).

### D-46: Kickoff brief retention

**Decision:** Kickoff briefs are retained indefinitely in the spec bundle directory once a spec is Done. They become a historical artifact. No automatic pruning.

**Alternatives considered:**
- Delete on completion. Rejected: loses decision and assumption traceability.
- Move to archive directory. Rejected: extra discipline for no clear gain.

**Chosen because:** Disk cost is negligible; historical value is real.

### D-47: Uncommitted changes on `/resume`

**Decision:** When `/resume` opens in a worktree with uncommitted changes, it surfaces `git status` to the user and asks before proceeding. No auto-clean, no auto-commit, no auto-stash.

**Alternatives considered:**
- Auto-stash. Rejected: too easy to lose work if resume goes sideways.
- Refuse to resume until clean. Rejected: too rigid; uncommitted changes may be intentional WIP.

**Chosen because:** Surfaces information, defers the decision to the human.

### D-48: No separate audit log

**Decision:** Pair-flow does not maintain a separate audit log. The audit trail is: git history + PR descriptions + `tasks.md` section transitions + inbox state file timestamps + age-encrypted telemetry per D-30.

**Alternatives considered:**
- Append-only audit log per repo at `~/.claude/pair-flow.audit.jsonl`. Rejected: marginal value when git already records what changed and when.

**Chosen because:** Reuse what's already authoritative.

### D-49: Kickoff briefs are committed to git

**Decision:** Kickoff briefs (`specs/{feature}/kickoff-brief.md`) are committed alongside the rest of the spec bundle. Not gitignored. Sized small (typically a few KB) and treated as a historical artifact for the spec.

**Alternatives considered:**
- Gitignore briefs (treat as user-local working state). Rejected: solo-repo briefs are documentation of decisions and assumptions, equivalent in value to design.md; storing them outside git would risk loss and break PR references.
- Commit per-author briefs (`kickoff-brief.{user}.md`). Reserved for the multi-reviewer extension; for v1 (solo only) it's redundant.

**Chosen because:** Briefs are decisions, not secrets. Git is the right home.

### D-50: Validator field checks for v1 are structural only

**Decision:** The extended validator (D-45) checks structural fields per task: stable ID, `Done when:`, `Dependencies:`, `Citations:`. Optional fields like `Measurement plan:` (D-38) and `Last reviewed:` (D-40) are recommended but not validator-enforced for v1.

**Alternatives considered:**
- Validate optional fields and emit warnings. Rejected for v1: spec inventory in `tecpan/specs/` and `dotfiles/specs/` is small enough that human review catches drift; tooling overhead not justified yet.

**Chosen because:** Minimize tooling churn; extend the validator if drift emerges in practice.

### D-51: Wholesale-rewrite threshold for whole-brief invalidation

**Decision:** Per D-27, section-scoped invalidation is the default; whole-brief invalidation fires only on a wholesale rewrite. Two pragmatic triggers:
1. Both `requirements.md` AND `design.md` change in the same commit.
2. More than 50% of REQ-IDs (or D-IDs) change in a single commit (additions or modifications count; pure removals do not).

Either trigger fires the whole-brief path; otherwise stay section-scoped.

**Alternatives considered:**
- Fixed file-count threshold. Rejected: easier to game and less meaningful than ID-level churn.
- No threshold (always section-scoped). Rejected: a true rewrite makes section-by-section invalidation tedious and incoherent.

**Chosen because:** Pragmatic thresholds that match what a "rewrite" actually looks like in practice.

### D-52: One task per `/orchestrate` invocation; intra-spec parallelism via multiple invocations

**Decision:** Each `/orchestrate` invocation picks and dispatches at most one ready task (or one bundle per D-11), then exits. The per-spec advisory lock (D-17, D-37) is held only during state-changing moves — task selection and the resulting `tasks.md` update — not for the duration of `/execute-task`. As a result, multiple ready tasks within the same spec can be in flight simultaneously across different worktrees, each kicked off by a separate `/orchestrate` invocation.

Parallelism is driven by:
- **Manual:** the user runs `/orchestrate` in multiple tmux panes (or sessions) to kick off N parallel tasks. Matches the user's existing "different workstreams in parallel" workflow.
- **Scheduled:** Task 12's bookkeeping runner picks up the next ready task on each cycle; intra-spec parallelism accumulates naturally over time.

**Alternatives considered:**
- Fan-out within one invocation. Rejected: parallel `/execute-task` work would require spawning sub-sessions, conflicting with D-39 (in-session skill composition).
- Long-running `/orchestrate` process holding multiple in-flight tasks. Rejected per D-5 (stateless step machine).

**Chosen because:** Matches the user's existing workflow (parallel tmux panes / sessions for independent workstreams) while preserving the stateless step-machine model.

### D-53: Performance, security, and system-wide considerations during execution

**Decision:** `/execute-task` shall weigh performance, security, and system-wide implications when proposing a fix, alongside its consultation of docs, source code, and reputable external sources (REQ-B1.5). These considerations and any tradeoffs are recorded in the kickoff brief's risk register. CI is the hard gate for correctness; performance regressions that pass CI but materially degrade behavior remain user-observable and therefore are not eligible for Agent-resolvable auto-apply (D-3 already excludes user-observable behavior change).

**Alternatives considered:**
- Add a "performance regression" disqualifier to D-3's hard list. Rejected for v1: automated benchmarking is not in place; codifying a check the system cannot enforce creates a false guarantee.
- Leave the consideration entirely implicit. Rejected: the user explicitly asked for performance and security to be weighed during execution.

**Chosen because:** Explicit reminder of the consideration without overpromising on automated enforcement. When benchmark CI is added in a future task, this can be tightened.

## Cross-cutting concerns

### Permissions and security

- New skills, hooks, and tools may require updates to `roles/osx/files/claude/settings.json` permissions. Each task that introduces a new tool call shall list the permission change in its `Done when:`.
- Hooks that execute arbitrary content (e.g., `claude -p` invocation, executing `worktree-bootstrap` scripts) inherit the existing trust model: the user is responsible for trusting the repo before opening it.

### Per-host config differences

- `work`, `personal`, `alt` profiles already exist in the Ansible role. The autonomy system shall use `inventory_hostname` checks where behavior differs (e.g., Ollama daemon binding, MCP secret loading).
- The inbox substrate is host-neutral; sync is the user's responsibility (iCloud Drive on default, Syncthing if preferred).

### Migration and rollback

- Existing tecpan specs do not have kickoff briefs. The user shall opt in per spec via `/spec-kickoff <spec-path>` in retrofit mode.
- Each task that introduces a new skill or hook shall be reversible by removing the file and re-running Ansible. No destructive migrations.

### Telemetry

- The next round's effectiveness shall be measured by re-running the April-style usage analysis on a 30-day window post-implementation. Baseline: 86 tecpan sessions, 65% review-driven, 38 AskUserQuestion calls, 82 file-path mistakes, 0% Auto-applicable fill rate. Target deltas TBD per task.

## What we explicitly deferred or set aside

- **Phone push notifications** (REQ-F4.1). Deferred. Inbox substrate is designed not to preclude it.
- **Headless `claude -p` for implementation resumption** (D-16). v2.
- **Auto-respond to peer review feedback** (`/orchestrate` v2). After v1 trusted.
- **Multi-spec concurrent orchestration**. After single-spec works.
- **Handover-brief auto-write conditions** (D-2). Deferred unless v1 surfaces specific gaps.
- **Migration of work projects.** Out of scope for v1; design accommodates multi-reviewer but tecpan/dotfiles are the proving ground.
- **Retirement of `/copilot-pairing` and `/copilot-review`**. Existing user-CLAUDE.md already marks these transitional. No change here.

## Sources

- Conversation between user and Claude on 2026-05-22, captured in this dotfiles repo.
- User-global CLAUDE.md sections: Finding Categorization, Validation Rigor, Discovery Rigor, Refactor Instinct, Review Workflows.
- Project CLAUDE.md (dotfiles) sections on materialization, permissions, hooks, MCP, Ollama topology.
- Existing tecpan spec bundles (`specs/auth`, `specs/infra`, `specs/org`, `specs/settings`).
- Subagent analyses 2026-05-22 (peer review pattern, Auto-applicable fill rate, spec quality correlation, friction & time analysis).
