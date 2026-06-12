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
| `commit_on_kickoff` | `true` | Auto-commit the kickoff brief plus the Draft→Active status flip after sign-off (D-41). Commit only; the push and draft PR are separate kickoff steps. | `/spec-kickoff` |
| `commit_on_state_move` | `true` | Auto-commit `tasks.md` orchestration state moves with a fixed conventional message (D-41). | `/orchestrate` |
| `dispatch_backend` | `subagent` | Which dispatch backend `/orchestrate` uses for execution units: `subagent` (default), `tmux`, `print`, or `in-session` (D-38, REQ-F1.8). | `/orchestrate` |
| `max_parallel_units` | `3` | Concurrency cap on simultaneously in-flight execution units (REQ-F1.8). | `/orchestrate` |
| `stale_lock_threshold` | `15m` | Age past which a per-spec advisory lock is treated as stale and may be broken by the next runner (D-10). | `/orchestrate` |
