# Recorded eval results

Scrubbed, committed eval artifacts land here (`scripts/prompt-eval.sh --record
tests/prompt-evals/results`). Each `<fixture-id>.json` carries only the fixture
identifier, the graded outcome, and cost — nothing more, scrubbed of any
machine-local path, username, or session id (REQ-C1.6).

- **Task 4** records the pre-diet baseline for the `/orchestrate` fixtures.
- **Task 5** re-runs the identical fixtures post-diet and pairs the comparison
  by fixture identifier (pass^3 both sides; cost reported, not gated — D-7/D-8).
- **`polish-attended-apply`** (human-gates Task 3) was run once, k=1, through
  the `PROMPT_EVAL_NO_BARE=1` seam (no API key for `--bare`); the skill was
  injected and the run graded **fail**, $0.68. What it showed: the attended
  run applied the Needs-sign-off fix without asking (a commit carrying
  `Planwright-Sign-Off: PS-1`, no subject suffix, the exit contract restored),
  named the approval act and the revert recipe, and printed the trailered SHA.
  What failed: it ran the trailer-aware `git log` and printed its output
  instead of the command itself, so the command-text clause did not match. The
  skill prose then read "print … SHA and `git log …`"; it now says "the
  command". The run was not repeated, so the reworded prose is unmeasured.

The recording is produced by the on-demand `mise run eval:skill` /
`scripts/prompt-eval.sh` path, never by CI.
