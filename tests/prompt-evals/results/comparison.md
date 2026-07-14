# Task 5 pilot — paired before/after comparison and verdict (REQ-D1.3)

Recorded 2026-07-14 at the `/orchestrate` diet (prompt-hygiene Task 5, D-12).
Pre-diet plugin: the Task 4 baseline commit (`3bdc818`); post-diet plugin: the
Task 5 branch head.

## Verdict

**The behavioral pilot is DEFERRED: headless skill injection is unavailable
via the CLI slash path, so no recorded cell has ever measured the
`/orchestrate` instruction file.** Task 5's Done-when clause "the post-diet
eval passes pass^3" is therefore **unmet-with-cause** (this document is the
cause record; accepting it is the human's call at the PR, and may warrant a
spec-amendment note). The diet itself is verified by the two mechanisms that
do not depend on the eval:

- the size guard: body 7,200 → 4,178 words (error floor 4,250),
  mandatory-at-start 16,371 → 4,471 (error 10,000), reachable closure
  19,789 → 19,468 (warn; error 20,000), with both Task 5 `pending diet`
  allowances removed and no suppression of `/orchestrate`'s own (REQ-D1.1
  `[test]`);
- the REQ-D1.1 `[manual]` meaning-preservation review (law moved verbatim in
  meaning; deviations documented on the PR).

One anecdotal-positive behavioral data point exists (below), but no graded
pass^k evidence on either side. "No regression" cannot honestly be claimed
behaviorally — and neither can a regression: the eval measured a bare model
on every recorded cell, identically on both sides.

## What the recorded cells actually measured

Every recorded artifact predates the skill-injection guard and is a
**bare-model run**: the fixture prompts were prose ("Run /orchestrate on…"),
headless `-p` exposes no Skill tool, and the SKILL.md never entered context.
The model improvised over the seeded repo — in one preserved run it invented
its own dispatch-record schema at a non-contract path and narrated the
dispatch as done. The artifacts are retained as the historical record of that
failure mode, not as behavioral evidence:

| Cell (chronology) | Fixture cap | Outcome | Cost (USD) | Post-hoc validity |
| --- | --- | --- | --- | --- |
| Task 4 baseline, pre-diet | print-ready $0.50 | fail (cap-hit, ungraded) | 0.6061 (1 run) | bare model |
| Task 4 baseline, pre-diet | refuse-draft $0.30 | pass 3/3 | 0.1792 | bare model |
| Post-diet, first run | print-ready $0.50 | fail (cap-hit, ungraded) | 0.6226 (1 run) | bare model |
| Post-diet, first run | refuse-draft $0.30 | pass 3/3 | 0.1808 | bare model |
| Recalibrated $1.00, pre-diet | print-ready $1.00 | fail (assertion) | 0.1945 (1 run) | bare model |
| Recalibrated $1.00, post-diet | print-ready $1.00 | fail (assertion) | 0.1445 (1 run) | bare model |

A `refuse-draft` "pass" is reachable by a bare model reading `Status: Draft`,
which is why the failure mode stayed invisible until the print-ready
assertion was investigated with a preserved transcript.

## The one skill-following run (anecdotal, not a graded cell)

One post-diet run (2026-07-13, $1.0557, 23 turns, killed by the then-$1.00
cap) **self-loaded** the dieted SKILL.md by reading it from disk mid-run, and
then executed the contract correctly: pre-flight 1–6 with fail-closed
doctrine resolution, the point-of-use reads exactly as the dieted manifest
prescribes (`proportionality` at start; `spec-format` at the gate;
`orchestration-concurrency` at the dispatch record), freshness-gate MATCH
inside the lock (sanctioned command form, sanctioned writer, `Lens-pass:`
verified), branch-first, marker written at the contract path
(`specs/demo/.orchestrate/markers/1`) — killed roughly two turns before
printing the launch command. This is an encouraging signal that the dieted
instruction file drives correct behavior when it IS in context, and it is
not admissible as pilot evidence (self-injection, single run, cap-killed).

## Root cause and the fix arc (all guard-verified)

1. **Bare-model root cause found**: an instrumented repro preserved a
   transcript; the failing assert conjunct was `marker_written`, the "marker
   written" claim in the result text was confabulation, and the transcript
   contained zero SKILL.md content.
2. **Skill-injection guard added**: when `fixture.conf` names a `skill`, the
   transcript must carry that SKILL.md's full H1 line or the run is INVALID
   (exit 3), never a graded result. This guard then correctly rejected every
   subsequent non-injected attempt.
3. **Literal slash-command prompts** (`/planwright:orchestrate specs/demo
   --backend print --unattended`): still not expanded when piped on stdin.
4. **Prompt as the `-p` argument**: probed; still INVALID — `--bare` itself
   suppresses expansion.
5. **`--bare` dropped** (`PROMPT_EVAL_NO_BARE=1` seam): probed; still
   INVALID. Headless CLI slash-path injection is unavailable in the current
   CLI, with or without `--bare`.
6. **Runner-side injection (prepending the SKILL.md body to the prompt) was
   considered and deliberately deferred** — a faithful injection mechanism
   deserves its own design pass, not a bolt-on under Task 5 pressure. The
   follow-up observation is recorded in the observations accumulator
   (`behavioral-pilot-injection-design`).

## What ships, and the suite's standing status

Task 5 ships the diet plus the eval-harness hardening, all stub-tested: the
skill-injection sentinel (INVALID, not a graded fail), the `-p`-argument
prompt delivery, per-run caps recalibrated on measured real cost
(print-ready $3.00 / 60 turns), the `PROMPT_EVAL_KEEP_FAILED` diagnosis seam,
and the `PROMPT_EVAL_NO_BARE` seam. **The kept suite is currently
guarded-inoperative**: every cell correctly aborts INVALID until an
injection mechanism lands, which is the honest state — a suite that cannot
inject refuses to grade rather than grading a bare model.

Total probe/eval spend across the investigation: ≈ $3.2 (recorded per-cell
above plus the instrumented repro at $0.1554, the $1.0557 self-injected run,
and three sub-$0.05 INVALID probes).
