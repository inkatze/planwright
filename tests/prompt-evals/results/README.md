# Recorded eval results

Scrubbed, committed eval artifacts land here (`scripts/prompt-eval.sh --record
tests/prompt-evals/results`). Each `<fixture-id>.json` carries only the fixture
identifier, the graded outcome, and cost — nothing more, scrubbed of any
machine-local path, username, or session id (REQ-C1.6).

- **Task 4** records the pre-diet baseline for the `/orchestrate` fixtures.
- **Task 5** re-runs the identical fixtures post-diet and pairs the comparison
  by fixture identifier (pass^3 both sides; cost reported, not gated — D-7/D-8).

The recording is produced by the on-demand `mise run eval:skill` /
`scripts/prompt-eval.sh` path, never by CI.
