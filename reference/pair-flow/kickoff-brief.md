# Pair-Flow — Kickoff Brief

**Spec path:** `specs/pair-flow/`
**Spec commit:** 7d99b2b5c3adfde4d9b73648b508d9386a248192 (Section 3 re-signed 2026-06-04 for D-54 + D-44 amendment; original sign-off 2026-05-25 at 422f956b1683105668de1c56c8fe2ee12976a16c)
**Date started:** 2026-05-25
**Date signed off:** 2026-05-25
**Repo-class:** solo
**Retrofit mode:** no (validator passed with 0 warnings)
**Status flip:** Draft → Active (confirmed, validator 0 errors post-flip)

---

## 1. Goal and Glossary

The system takes a feature from structured drafting, through a human-agent comprehension pass (the kickoff brief), into autonomous test-first execution, with a stateless orchestrator managing the task graph and opening draft PRs, all surviving session boundaries by treating the spec's `tasks.md` as the canonical state record, with a cross-session inbox so the human knows when judgment is needed. Everything runs on Claude Code primitives; no second agent framework is introduced unless those primitives prove insufficient for a specific need.

The glossary's load-bearing distinction: the kickoff brief is the durable contract (downstream skills operate from it, not by re-reading the spec); the handover brief is an optional cache (system works without it). The `Agent-resolvable` bucket and the solo/multi-reviewer split are the new contribution to the existing review infrastructure.

**Surfaced implicit terms:**
- "Structural rigor sufficient to drive autonomous execution" is measurable via the validator (D-45). The assumption is that validation catches insufficient structure before execution starts.
- "Mutually didactic" means the brief IS the agent's learning artifact; what the agent "learns" is what it records there.
- "Session boundaries" means Claude Code session exits. Host reboots, network partitions during sync, and 1Password agent failures are environmental hazards, not session-boundary events.

**Socratic checks and answers:**
1. *Slicing:* Each layer ships independently when ready. The six-part goal is aspirational until all layers land. The current walkthrough happening mid-implementation is evidence of this.
2. *Interruption model:* "Minimal human interruption" means human interruption only at explicit decision points, never at mechanical steps. The mandatory handoff points (D-33 kickoff gate, D-21 no-auto-merge, D-47 no-auto-stash) are all explicit decision points by design.
3. *No-second-framework constraint:* This holds unless Claude Code primitives prove insufficient for a specific orchestration need. It is a pragmatic preference for simplicity, not a hard architectural boundary. If headless `claude -p` never stabilizes and a specific need arises, the constraint yields to the outcome.

Signed off: 2026-05-25

## 2. Requirements Walkthrough

Seven REQ groups spanning the full pipeline:

**REQ-A (Spec lifecycle):** Two authoring skills plus a three-state lifecycle. `/spec-draft` produces a validator-clean four-file bundle at Draft status. `/spec-kickoff` walks it interactively and produces the kickoff brief as contract, flipping to Active. The Active gate (A3.3) is the hard boundary between planning and execution. The brief is incremental (survives crashes), section-scoped on invalidation (survives minor edits), and committed to git.

**REQ-B (Task execution):** `/execute-task` mandates test-first (B1.3/B1.4), full CI before done (B1.6), `/polish` as convergence (B1.7), always-draft PRs (B1.8). CI failures get adaptive retry: transient 2x, logic escalates immediately (B1.9). Worktree assumed to exist (B1.10). Polish invoked in-session (B1.11).

**REQ-C (Autonomous resolution):** Agent-resolvable bucket with five-condition predicate. Solo auto-applies; multi-reviewer surfaces with evidence. Existing buckets unchanged.

**REQ-D (Orchestration):** Stateless step machine, one task per invocation, advisory lockfile released before execution. Never auto-merges. Degrades gracefully without gh. Halts on ambiguity or contract drift.

**REQ-E (Continuity):** `tasks.md` is canonical state. `/resume` reconstructs from spec + git + PR without handover brief. Uncommitted changes prompt, never auto-act.

**REQ-F (Cross-session awareness):** Inbox with 30s heartbeat, 2-min stale threshold, six states. tmux popup + status segment. macOS notifications. Phone push deferred.

**REQ-G (Operational integration):** Panel-underuse investigation (done, confirms codex default on work). File-path hook (done). Codex default on work profile; Gemini on personal/alt profiles (amendment to D-6, see below). Ansible propagation. Validator extended for D-15 structure.

**Surfaced implicit assumptions:**
- REQ-B1.3's "confirm it fails for the intended reason" assumes the agent can distinguish a missing-implementation failure from a broken-test-setup failure. Requires clear assertion messages in tests.
- REQ-D2.2's one-task-per-invocation model means N parallel tasks require N manual `/orchestrate` invocations. No fan-out primitive.
- REQ-F1.2's file naming uses session UUID (per D-34), which is unique across hosts by construction.

**Socratic checks and answers:**
1. *Risk register mutability (REQ-B1.5):* The risk register is append-only post-sign-off. Research findings during execution add new entries annotated with "Discovered during Task N execution" but never modify existing signed-off entries. The PR body carries the full research narrative; the risk register gets a one-liner pointing at it.
2. *"Aligned with kickoff brief" (REQ-C1.2 condition d):* Operational definition: the fix does not contradict any constraint, decision, or assumption stated in the brief, AND the fix is within the scope of the brief's stated goals. "In-scope and non-contradictory" is the bar for "ready to autorun without human checking the direction."
3. *Active-status and manual work (REQ-A3.3):* Active does not lock out manual work. The user can implement tasks directly; reconciliation happens via manual `tasks.md` update or scheduled runner. Skills are also designed to work gracefully mid-implementation on a Draft spec (pair-flow execution skills won't auto-run, but `/spec-kickoff` and `/resume` still function).

**D-6 amendment (recorded for design walkthrough):** Codex remains the default backend on the work profile. Personal/alt profiles use Gemini 2.5 Pro instead of Codex (user does not want to fund OpenAI for personal use). The `--backends` flag profile-aware defaults become: work = `codex`, personal/alt = `gemini`.

Signed off: 2026-05-25

## 3. Design Walkthrough

54 D-IDs across six clusters. All major decisions held through implementation without requiring reversal. Amendments identified below.

**Architecture (D-1 through D-5, D-18):** Five independently-shippable layers. `tasks.md` as canonical state. Two-brief model (kickoff = contract, handover = optional cache). Stateless orchestrator. Claude Code primitives only (with the pragmatic escape hatch from Section 1 if primitives prove insufficient). All confirmed by implementation.

**Configuration (D-19, D-20):** Two-file split (tracked defaults + agent-maintained local). Discovery prompts on first encounter. Verified in Task 3.5.

**Panel/Convergence (D-6, D-12, D-13):** D-6 amended (see below). `/polish` is default convergence; `/panel-pairing` is escalation-only. Standalone Polish opens draft PR.

**Execution (D-25, D-39, D-44, D-53, D-54):** Adaptive CI retry (transient 2x, logic escalate). In-session skill composition. Worktree ownership split (orchestrator creates *or reuses*, execute-task assumes). Worktree reuse + `claude --worktree` interop (D-54, see amendment 5). Research findings append to risk register.

**Orchestration (D-11, D-17, D-21, D-24, D-31, D-32, D-33, D-36, D-37, D-52):** Bundling rule. Advisory lockfile. Always-draft PRs, never auto-merge (permanent). Bundle sizing via citations + git history. Three-state lifecycle. Per-spec locking. One task per invocation.

**Awareness (D-10, D-22, D-23, D-34):** Inbox via shared filesystem. Color-coded dashboard (red/orange/blue/yellow/green/grey). 30s heartbeat, 2-min stale threshold. Per-session keyed, per-worktree presented.

**Brief lifecycle (D-7, D-27, D-35, D-40, D-41, D-42, D-45, D-49, D-51):** Didactic walkthrough. Section-scoped invalidation with wholesale-rewrite triggers. Incremental write. Inconsistency escalation. Status-aware enforcement. Briefs committed to git.

**Socratic checks and amendments:**

1. *D-6 profile-aware backends:* `pair-flow.yml` keeps `panel-backends: [codex]` as the universal default. Personal/alt hosts override via `pair-flow.local.yml` with `panel-backends: [gemini]`. No host-conditional logic in the tracked file; the existing two-file merge handles it. The "Provisional" qualifier on D-6 is dropped (Task 1 confirmed panel is newly available, not underused). Decision becomes: codex on work, Gemini 2.5 Pro on personal/alt.

2. *D-17 stale-lock threshold reduced to 15 minutes:* Post-D-52, the lock is held only during task selection (seconds). A lock older than a few seconds is anomalous. The new default of 15 minutes accounts for iCloud sync lag (worst case ~5 min) without false positives, while recovering from crashes within one scheduled-runner cycle. The 1-hour original was sized for "lock held during execution" which no longer applies.

3. *D-24 bundle sizing fallback for low-data repos:* When `gh pr list --search` returns fewer than 5 relevant PRs, fall back to the `Estimated effort` field: half day = ≤300 lines, 1 day = ≤500 lines, 2 days = ≤700 lines. Bundle only if the sum stays ≤700. Grounded in data already in the spec (Estimated effort is required per task). Telemetry (D-30) calibrates the multipliers over time.

4. *Effort levels and extended thinking in sub-agents:* Not addressed in the current design. Claude Code does not currently expose effort-level or thinking-budget controls to skills or the Agent tool. When these become available, pair-flow skills should differentiate: high effort for Discovery Rigor, regression-test writing, and research; normal effort for task selection, bookkeeping, and status updates. Current workaround: configure sessions by purpose (speed for bookkeeping, depth for execution). Recorded as a calibration note for Task 13.

5. *D-54 worktree reuse + `claude --worktree` interop (added 2026-06-04, Task 16):* `/orchestrate`'s dispatch no longer unconditionally `git worktree add`s. It detects whether the session is already in a linked worktree (predicate `git rev-parse --git-dir` ≠ `git rev-parse --git-common-dir`, the same one the worktree-bootstrap hook uses), reuses a clean current worktree after a one-line confirm, and asks where to work when in the primary checkout (honoring a pre-directed "use the current branch"). Fresh worktrees move from the legacy sibling `<repo>--claude-worktrees-<suffix>` path to `<repo>/.claude/worktrees/<suffix>` so Claude Code's native `claude --worktree` / `EnterWorktree` tooling discovers them; D-32 branch naming is deliberately kept because `tasks-pr-sync.sh`, `skill-contracts.sh`, and `/resume` parse it (only the worktree *directory* needs to match for discovery, not the branch name). After create-or-reuse, `/orchestrate` prints the `cd <repo>/.claude/worktrees/<suffix> && claude` re-open command (`claude --worktree` always creates rather than attaches). D-44 amended in lockstep ("creates" → "creates or reuses"; path placement delegated to D-54). The ownership boundary is unchanged: `/execute-task` still assumes-exists and never learns whether the tree was created or reused. The confirm sits at an explicit decision point (which working tree to mutate), consistent with Section 1's interruption model.

Signed off: 2026-05-25 (Sections 1, 2, 4, 5, 6); Section 3 re-signed 2026-06-04 (D-54 + D-44 amendment, spec commit 7d99b2b)

## 4. Verification Approach

The verification approach is almost entirely manual exercise, appropriate because pair-flow is workflow infrastructure (skills, hooks, file-based state) without unit-testable API boundaries. Three categories of verification paths:

1. **Behavioral Gherkin** (REQ-A2.1, A2.6, A2.8, A2.10, B1.3, B1.9, C1.1-C1.3, D2.2, D9.1, E5.1, F1.2, F2.1-F2.3): Given/When/Then scenarios where state-machine behavior benefits from formal articulation.
2. **Inspection-based manual** (REQ-A1.x, G-series): invoke the skill, inspect the output for required structural properties.
3. **Design-level only** (C1.6, E4.1, F4.1): verified by design inspection, not runtime behavior.

Every REQ is pinned to at least one entry. Coverage is complete.

**Surfaced assumptions:**
- REQ-A2.6 (brief invalidation) and REQ-A2.8 (inconsistency escalation) require induced scenarios (deliberately breaking a spec). These won't occur naturally during Task 13; they need separate test runs.
- REQ-B1.9 (adaptive CI retry) requires induced transient failure (mock network error or a real flaky test), which is not guaranteed during Task 13.

**Socratic checks and answers:**

1. *This session as verification:* This walkthrough on `specs/pair-flow/` satisfies REQ-A2.1/A2.2/A2.3's verification path. We are executing exactly what the Gherkin describes: section-by-section walk, restatement, implicit terms surfaced, Socratic checks posed, human red-lines per section, brief written incrementally. The tecpan exercise during Task 13 becomes a second confirmation. Mark REQ-A2.1/A2.2/A2.3 as verified by this session.

2. *Automated regression guard:* The most common regression mode is structural drift between skill files (editing one, forgetting to update cross-references in another). This is automatable via a contract-consistency checker: a shell script (~50 lines) that greps skill files for cross-file invariants (flag names, table counts, branch naming patterns, handler paths). Runs as a lefthook pre-commit job filtered to `roles/osx/files/claude/commands/*.md`. Does not attempt to test LLM interpretation (non-deterministic, not automatable). Task 13's retrospective identifies which cross-references are load-bearing in practice and produces the script as a sub-deliverable.

Signed off: 2026-05-25

## 5. Task Graph Reconstruction

*Snapshot of the task set as of sign-off (2026-05-25). `tasks.md` is the canonical, current state; Tasks 15-16 were added after sign-off and are not reflected below.*

16 tasks were defined at sign-off (1, 2, 3, 3.5, 3.6, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14). The dependency chains and remaining graph below describe the task set as it stood then.

**Reconstructed dependency chains:**
- Chain A (spec lifecycle): 3.6 → 6 → 7
- Chain B (infrastructure): 2, 3, 3.5, 4 (mostly independent of each other)
- Chain C (execution): 8, 9 → 10 → 11 → 12
- Task 1: independent investigation
- Task 5: branches off after Task 4
- Convergence: all chains → Task 13 → Task 14

**Remaining graph:** Task 13 (ready, all deps satisfied) → Task 14 (blocked on 13). No parallelism available.

**Task 13 deliverable amendment (from this walkthrough):**

Original: "A short retrospective at `specs/pair-flow/research/v1-retrospective.md`."

Amended to include:
- The retrospective document (original)
- Contract-consistency checker script at `roles/osx/files/claude/scripts/skill-contracts.sh`, wired as a lefthook pre-commit job (from Section 4 discussion)
- Spec amendments: D-6 profile split (codex on work, gemini on personal/alt), D-17 threshold to 15 minutes, D-24 effort-based fallback for low-data repos (from Section 3 discussion)

These amendments are the first commits in Task 13's implementation, before the end-to-end validation run.

**Socratic checks and answers:**

1. *Task 13 catch-all dependency:* "Tasks 1-12" is satisfied. No issue.
2. *Contract-consistency checker:* Added to Task 13's Deliverables explicitly (we know we want it; leaving it as a retrospective finding would be artificial).
3. *Spec amendments from this walkthrough:* Folded into Task 13 as the first commits. Recorded in this brief as the authoritative decisions; `design.md` and `pair-flow.yml` updates land when Task 13 begins.

**No unstated dependencies identified.** The graph is clean; all remaining work flows linearly through Task 13 → 14.

Signed off: 2026-05-25

## 6. Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| 1 | **Gemini backend integration doesn't exist yet.** `/panel-*` currently supports codex and ollama. Gemini needs an adapter. | High (new work) | Low (fallback to codex or ollama exists; user ready to set up when needed) | Task 13 scope includes the D-6 amendment. User will set up Gemini auth when directed. |
| 2 | **Agent-resolvable predicate untested in production.** Five-condition predicate (D-3) never exercised on a real finding. May be too permissive or too restrictive. | Medium | Medium (too permissive = bad auto-apply; too restrictive = bucket is useless) | D-3 explicitly calls this "open calibration." Task 13 exercises it. |
| 3 | **Cross-host inbox sync.** iCloud not available on work machine. Inbox entries on work are local-only unless Syncthing is configured. | Medium | Low (per-host local is fine for most workflows; cross-host is nice-to-have) | Sync mechanism choice is in Awaiting Input. Syncthing is the answer for cross-host if needed. Per-host local is the default. User accepts this latency. |
| 4 | **No testable CI for dotfiles itself.** Dotfiles has lefthook + yamllint + ansible-lint but no project test suite. Test-first (REQ-B1.3) doesn't apply meaningfully to config/skill changes. | High | Low | Already handled in `/execute-task`: "For tasks that are primarily configuration, documentation, or infrastructure, skip the test-first loop." |
| 5 | **Session crash mid-`tasks.md` update.** Dirty state between "move to In progress" and push. Next `/orchestrate` could re-pick the same task. | Low | Medium (duplicate work, conflicting worktrees) | Lock serializes picks. `/orchestrate` checks In-progress entries. Worktree creation fails on duplicate (git rejects). |
| 6 | **Effort/thinking controls unavailable per-step.** All work in a session runs at session-level effort. Bookkeeping burns the same tokens as implementation. | Medium | Low (cost/speed, not correctness) | Session-purpose separation. Scheduled runner prompts can include "ultrathink" for deeper reasoning. Interactive invocations can include it too. In-session skill composition (D-39) inherits the session's level throughout. |
| 7 | **System requires more human attention than expected.** Agent-resolvable too restrictive; stop conditions fire too often; degrades to "fancy issue tracker with extra steps." | Medium | High (defeats the purpose) | D-3 open calibration via Task 13. If stops fire too often, root cause is underspecified tasks/brief (fix upstream). |
| 8 | **Ships code that does the wrong thing.** Tests can be poorly written (assert implementation details, not behavior). Agent might write a test that passes without verifying the Done-when condition. | Medium | High | Done-when specificity is the upstream fix. Human reviews draft PRs before merge (D-21). Task 13 exercises this. |
| 9 | **Implements well-known security or performance anti-patterns.** Agent might choose a working approach with known vulnerabilities. `/polish` catches what linters flag but not all semantic issues. | Low-Medium | High | Hard-disqualifier zones ensure security-sensitive code always routes to human review. Linters catch surface patterns. Draft-PR review (D-21) is the last gate. If Task 13 reveals this as real, add security-focused lint to CI derivation. No benchmark CI for performance (known gap, accepted for v1). |

**Silent failure analysis:** The scariest silent failure is the scheduled runner reconciling a PR merge incorrectly (wrong task to Completed). Mitigation: PR bodies reference task IDs explicitly (REQ-B1.8), and `tasks-pr-sync.sh` parses from D-32 branch names (machine-generated, unambiguous). Validator catches task/dependency mismatches on the next Active-spec run.

**Known gap: curiosity-driven maintenance.**

The system only acts when told to. A human developer naturally notices complexity growth, outdated patterns, and newly-available dependency features. This is not a risk (won't cause failure) but a capability gap worth addressing:

- **Layer 1 (free, convention only):** Execution skills record observations to `specs/_observations/opportunities.md` as seed material for `/spec-draft`. During `/execute-task` and `/polish`, when the agent notices complexity, drift, or opportunities, it appends a one-liner.
- **Layer 1b (free, via existing memory system):** Same observations stored as `project`-type memories. Future sessions consult them automatically when touching related code. No new infrastructure; the memory system already persists, loads, and informs.
- **Layer 2 (new infra, deferred):** A periodic "health scan" scheduled runner that checks dependency changelogs (language-agnostic: hex.pm, npm, PyPI, crates.io, keyed off lockfile type), runs complexity metrics on recently-changed modules, and produces a digest. Cross-references against known workarounds stored in memory/observations.

Layers 1 and 1b are a skill-instruction convention, not infrastructure. Added to Task 13's scope: update `/execute-task` and `/polish` instructions to include the observation convention. Layer 2 is deferred (gate: v1 stable for 30 days, observation file has ≥10 entries proving passive accumulation generates actionable material).

Signed off: 2026-05-25

