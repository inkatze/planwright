# planwright options reference

The single canonical reference for every planwright config option (REQ-K1.8,
D-43). The tracked defaults live in [`config/defaults.yml`](../config/defaults.yml);
per-repo overrides live in `<repo>/.claude/planwright.local.yml` (gitignored,
agent-maintained, per-repo entries written only on human confirmation per
REQ-K1.1).

Every option present in the default config must have a row here.
`scripts/check-options-reference.sh` enforces that; planwright's CI runs it
(wired in by the self-hosting CI task) and fails on an undocumented option.

Config-model fallback: a skill that finds a config file absent, unreadable,
or malformed falls back to the tracked defaults below and surfaces a
warning when it reads the config, before any default-driven action fires
(REQ-K1.7).

Format constraints the checker relies on: each row's first table cell must
contain only the backticked option name (annotations go in the Effect
column), and `config/defaults.yml` must stay flat `key: value` lines (nested
YAML keys would be invisible to the parser, which fails closed when it
parses zero keys).

| Option | Default | Effect | Consumed by |
| --- | --- | --- | --- |
| `commit_on_draft` | `true` | Auto-commit the completed Draft bundle after elicitation finishes (D-41). Commit only, never push. | `/spec-draft` |
| `commit_on_kickoff` | `true` | Auto-commit the kickoff brief plus the Draft→Ready status flip after sign-off (D-41). Commit only; the push, draft PR, and terminal ready-flip are separate kickoff steps. | `/spec-kickoff` |
| `commit_on_state_move` | `true` | Auto-commit `tasks.md` orchestration-state edits — section moves (e.g. `/drain` relocating a block between human-owned sections) and the per-block `Status` / `Last activity` annotations (e.g. `/execute-task` stamping `Last activity`) — with a fixed conventional message (D-41). | `/drain`, `/execute-task` |
| `mark_spec_pr_ready_on_kickoff` | `true` | On a clean kickoff completion, `/spec-kickoff` marks the **spec** PR ready (un-draft) as its terminal step, after the configurable `review_sequence` verification has converged (D-6, D-7) — the narrow exception to bootstrap D-26's all-drafts rule: only the spec PR is readied, task PRs stay drafts, merge stays the human's (never auto-merge). `false` leaves the spec PR draft for the human to un-draft. The flip is also suppressed when sign-off parked on a fork or verification did not converge; a flip failure degrades to `tasks.md` Awaiting input (REQ-D1.2, REQ-D1.3). | `/spec-kickoff` |
| `dispatch_backend` | `subagent` | Which dispatch backend `/orchestrate` uses for execution units: `subagent` (default), `tmux`, `print`, or `in-session` (D-38, REQ-F1.8). Each value maps to an advertised capability set per the [backend capability contract](../doctrine/backend-capability-contract.md) (D-2), which defines how a new terminal/multiplexer becomes a selectable value by advertising the contract rather than by a skill edit. `/orchestrate` autodetects the backends actually present and, attended, presents them and asks (never a silent pick); unattended, it reads this value and, when that backend is absent or not autonomously selectable, degrades down the degradation ladder — never to a silently-chosen interactive backend (REQ-B1.4, D-3). So this value is the configured default and the unattended selection input; the per-backend dispatch adaptation is still name-keyed pending a later task. | `/orchestrate` |
| `dispatch_isolation` | `per-step` | How `/execute-task` sequences a unit's steps (D-5, REQ-C1.3): `per-step` (default) runs implementation and each configured `review_sequence` skill in its own fresh `/resume`-seeded session, so context stays bounded and each review's perspective is uncontaminated by prior steps (backends that cannot spawn a fresh session approximate it via context clears between steps); `per-unit` keeps today's single-session behavior for the whole unit. The `per-step` default is the assigned human decision; `per-unit` stays supported for constrained hosts. Resolved through `scripts/resolve-dispatch-isolation.sh`; a value other than `per-step`/`per-unit` is malformed under the REQ-E1.4 by-layer policy (degrade+warn for adopter/machine-local, hard-fail for repo-tracked). The default-flip from the historical `per-unit` behavior is tracked cross-spec as the required bootstrap D-38 amendment. | `/execute-task` |
| `max_parallel_units` | `3` | Concurrency cap on simultaneously in-flight execution units (REQ-F1.8). | `/orchestrate` |
| `stale_lock_threshold` | `15m` | Age past which a per-spec advisory lock is treated as stale and may be broken by the next runner (D-10). | `/orchestrate`, `tasks-pr-sync` hook |
| `stale_marker_threshold` | `15m` | Age past which a runtime dispatch marker whose branch carries no commits is treated as stale, reverting the task to Ready so a dispatch that crashed before its first commit cannot wedge it In progress (orchestration-concurrency D-3). | `scripts/orchestrate-state.sh` (task-state derivation) |
| `review_sequence` | `[polish]` | Ordered review sequence `/execute-task`'s convergence phase runs: an inline list of nestable review-skill names (a *nestable* review skill is one invocable with `--nested`, e.g. `/polish`, `/self-review`). The default reproduces today's single `/polish --nested` convergence; an overlay can reorder or extend it. Resolved through `scripts/resolve-review-sequence.sh`; an entry naming an unknown or non-nestable skill is malformed under the REQ-E1.4 by-layer policy (degrade+warn for adopter/machine-local, hard-fail for repo-tracked) (D-6, REQ-D1.3). | `/execute-task` |
