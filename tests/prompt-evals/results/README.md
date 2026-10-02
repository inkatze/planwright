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
  command". `polish-attended-apply.json` is this first run.
- **`polish-attended-apply`, second run** (same fixture and runner options,
  against the reworded skills, run once on request) came back **INVALID**
  (exit 3), $0.65: the runner's injection check found no `# /polish` H1 in
  the transcript, which also never echoes the `/planwright:polish` prompt,
  so the runner recorded no JSON for it. The run's side effects and final
  text did meet every assert clause (a `Planwright-Sign-Off: PS-1` commit
  applied without asking, no suffix, the exit contract restored, and a
  handoff naming the commit and printing the trailer-aware `git log`
  command), but an uninjected run cannot count as evidence for the skill,
  so the reworded handoff remains unmeasured. Not re-run.

The recording is produced by the on-demand `mise run eval:skill` /
`scripts/prompt-eval.sh` path, never by CI.
