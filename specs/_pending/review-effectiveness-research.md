# Research: what the review passes cost and what they miss

Status: COMPLETE. The research tracks (skill anatomy, observation mining,
fold-detection, PR-history mining over two slices, token telemetry) reported
on 2026-09-24 and are folded in here. This note is the seed for the
review-effectiveness spec; the figures are measured over this repo's own
history and transcripts, and the method for each is stated so it can be
re-run. Per-PR datasets and scripts live in the drafting session's
scratchpad and are not committed; the numbers below are the ones the spec
cites.

## 1. Headline findings

1. **Bot reviewers find real defects after our passes declare clean, on most
   PRs.** Over 496 PRs, 272 got a bot review. In the 301+ slice, 80 of
   90 bot-reviewed PRs (89%) got at least one finding; in the 1-300
   slice, 147 of 182. The bot's thread precision is about 80% (735 fixed of
   912 decided in the first slice; 254 fixed of 321 threads in the second).
   The median bot-reviewed PR carried 3 fixed findings.
2. **Findings drive the long cycles.** PRs with a bot finding: median 3
   commits after the first review and a median of 3 to 4 review rounds
   (mean 4.2 to 4.4; tails of 6 to 10 rounds). PRs without: 0 commits, 1
   round. A large share of round-2+ findings (96 of 254 in the second
   slice) are regressions or half-fixes introduced by the previous round's
   own edits.
3. **Our own audit record was blind on the lens that later produced the
   fix, in a large minority of cases.** First slice: 188 of 482 checkable
   findings (39%, a floor, since some bodies were rewritten after the bot review)
   fell under a lens row our table marked `none`; by PR, 64 of 90. Second
   slice: 38 of 209 (18%). The more telling number from the second slice:
   82% of misses fell in lenses where the pass had reported *other*
   findings. The pass was not blind to the lens; it found some instances
   and stopped.
4. **Miss reasons (rule- or model-assigned, indicative):** first slice,
   735 fixed threads: (d) visible in the diff but not surfaced 166; (a)
   needed context outside the diff 149; (b) needed running or tracing the
   code 142; (c) a comment, doc, header or PR body claims one thing and the
   code does another 132; (f) conflicts with a spec, doctrine rule or repo
   convention 107; (g) a shell nit a linter could catch 28. Second slice,
   254 fixed threads: (b) 98; (c) 58; (d) 54; (g) 17; (a) 16; (f) 11.
   **Severity shifts the mix:** among the 45 high-severity fixed findings,
   (b) runtime tracing 23 and (a) cross-file context 11 dominate; pruning
   (d) is 3. Serious misses need tracing and callers, not more lenses.
5. **File-type failure modes are distinct.** Shell scripts draw most fixed
   findings in absolute terms (228 of 369 in the second slice; 331 in
   `scripts/` plus 152 in `tests/` in the first) with runtime correctness,
   fail-open exit paths, hostile-input handling and sibling-script
   inconsistency. Test files fail on vacuous or weak assertions. Prose
   (skills 13.5, doctrine 10.7, docs 15.9 fixed findings per 1,000 added
   lines, versus 8.7 for scripts) fails on self-consistency: a claim next to
   the code it misdescribes, a count that disagrees with the list beside it,
   a PR body that disagrees with the diff, stale copies of one claim in
   other files.
6. **The recurring shape of a miss is the unswept sibling.** Fixes land at
   the pointed-at site while twin sites survive (#315, #357, #399, #471;
   obs 749d937c, a0add2f0, 587d7d7b, 15a7fdcb). The owner's own words on
   #399: "the previous round had fixed the sites that were pointed at
   rather than the ones that were wrong. There were four."
7. **Review convergence is the dominant token cost of a unit, and the
   parent context, not the fan-out, is the dominant term.** Across 57
   `/execute-task` workers with a review run, the convergence took a median
   52% of the worker's tokens (p10 28%, p90 80%; 57% in aggregate). Per
   convergence run (last 20): median 17.0M tokens, p90 44.8M. Composition:
   parent session 62 to 76% (almost all cache reads of an accumulated
   context averaging about 255k tokens per request, up to 537k), lens
   agents 23 to 36%, validation agents 1 to 2%, output under 1%. Priced by
   cost rather than raw tokens the parent/sub-agent split is roughly 47/53.
   In one measured worker the polish loop was about nine tenths of the
   worker's cost (six passes, 54 lens agents, 26M sub-agent tokens), and
   that worker cost several times the others in the fleet.
8. **Repeated work is structural, not incidental.** Every polish pass
   re-fans all nine lenses over the full `origin/main...HEAD` diff, never
   the delta since the previous pass; the confirming pass required for
   convergence costs a full extra fan-out on every productive run; the same
   files are re-read by every lens in every pass (50 of 70 reads duplicated
   in one run); doctrine and brief are re-resolved per pass. 52 of 57 nested
   convergence runs spawned no sub-agents at all (the stream-json worker
   constraint forces inline lensing), so their lens work was billed at the
   parent's 250k+ context per step.
9. **Different-model and cross-author reviewers find what same-model lenses
   cannot.** The external backend caught a merge-state API-semantics bug
   the nine-lens fan-out and the adversarial re-check both missed (obs
   01b3a1eb); an external backend found self-contradictions in freshly written doctrine
   the same-model pass passed (#326: 21 raised, 13 confirmed); a lens with a
   different author found 4 working false-allows a 539-assertion suite and
   an adversarial sweep missed (obs 3ed95276). But the external backends are
   unreliable in their own way: empty exit-0 output, a ~150KB size ceiling,
   sigil expansion producing fabricated findings, invented citations, and
   `none` rows filled with compliments (obs 03653377, 361dd7e5, fbf43658,
   4f7c2e91, b7d3e2a1). The external backend said "clean" and the bot still found 12 (#216)
   and 10 (#284) fixed findings.
10. **The bot reviewer's own signals are unreliable as convergence evidence.**
    Findings sit in the review body with zero threads (14 body findings in
    the first slice, 7 still unaddressed at merge; 270 in the second slice);
    the bot resolves its own threads; every review-request form returns
    success and may add nobody (obs 8b24690f, 51b53aa5, 67aafd6a).

## 2. Structural causes in the skill and doctrine text

Read from `skills/self-review/SKILL.md`, `skills/polish/SKILL.md`,
`skills/execute-task/SKILL.md`, `doctrine/discovery-rigor.md`,
`doctrine/validation-rigor.md`, `doctrine/finding-categorization.md`,
`doctrine/gate-wiring.md`, `doctrine/evidence-quality.md`.

- **Discovery is diff-scoped.** The lens brief is "find issues in this
  diff for ONE lens only"; lens agents get the diff slice, the tooling
  output and a single-lens brief; no instruction to read whole files,
  callers or sibling code. Callers are consulted only in validation pass 2,
  so only for findings that already exist. The dotfiles `/code-review`
  reads each full source file plus callers; planwright has no equivalent.
  Matches miss reason (a).
- **No lens targets the defensive-completeness tail or sibling symmetry.**
  The operator's external-backend review command carries a tenth lens ("presence/type/shape
  guards and symmetric handling across parallel paths; flag sibling
  fields/cases that lack it") that planwright's canonical nine do not.
  Matches finding 6.
- **No lens reads a claim against the code.** Nothing checks a comment,
  header, usage block, count, PR body or `Done when:` against what the diff
  does. The human-facing lens set applies only when the artifact is a PR
  body, and at convergence time the PR body does not yet exist. Matches
  miss reason (c), the single largest prose class.
- **Convergence prunes real but uncertain findings, permanently.** A
  finding whose three passes do not converge is dropped or declined; the
  decline set gets only a spot-check; a declined finding stays declined
  across iterations and never counts toward progress. A wrong decline in
  iteration 1 is invisible to every later iteration. The bi-directional
  adversarial pass validation-rigor defines is not named in `/self-review`,
  so its scoping is undeclared (legacy L58, L69). Matches miss reason (d).
- **Validation prefers a targeted test; whole-system reproduction is
  "angle 3, when relevant"** (legacy L59). Matches miss reason (b), the
  dominant high-severity class.
- **Same generator reviews its own work.** Nested self-review is one
  session, one context; `per-step` isolation seeds a fresh session with the
  author's brief and is still the same model family; the correlated-
  generator argument in evidence-quality is applied to personas, never to
  review. "Fresh eyes" is not a doctrine concept anywhere. No different-model
  backend can enter `review_sequence` (custom-steps replaces that knob with
  a step list, which is the attachment point this spec should use).
- **The self-critique pass runs in the coordinator's own context**, not an
  independent agent.
- **No dedup-by-root-cause convention.** 130 to 180 raw findings collapse
  to 9 to 35 root causes at kickoff passes (obs 19ec8cd4, 8dcf0f7c,
  9c3cf221, c10c0a24); duplication is spent effort while blind spots stay
  unlensed.
- **External findings never feed back.** Nothing mines bot or external-backend
  findings into the lens set; the polish ledger is used for suppression,
  not steering.
- **Ceremony per iteration:** the lens table with `none` rows, four bucket
  tables with `none` rows, the declined log, ladder rows, the sign-off
  checklist, a pass summary, the drift check and observation step, a
  stale-anchor pre-flight, a full-suite run per fix, and three-pass
  validation repeated for tool-cited mechanical items.
- **Instruction load:** `/self-review` start-load 9,168 words and `/polish`
  9,222 against a 10,000 error line, both carrying recorded below-target
  exceptions; seven run-start docs each; `finding-categorization.md` cannot
  grow by a word without breaking their margins (obs d2abb33d, 97e811db,
  15240f38, 7c02f52b, 4034976f). The composed nested chain (polish body +
  self-review body + shared doctrine) is roughly 11.9k words at start and
  no guard charges it as a whole.

## 3. Structural causes outside the skills

- **Base drift invalidates converged work.** #471 passed self-review,
  an external-backend pass and six bot rounds and was invalidated by one merge to main
  (obs 75c25c5d, 921b93c9, 98a155ab). merge-currency-guard (Ready) owns
  the sync; unit size and file partitioning drive conflicts (obs 36916a48).
- **The CI gate inside every convergence pass** costs 400 to 800 seconds
  per pass, runs concurrently across workers, and produced about 23% false
  reds in one sample (obs 7fe26f10, 0c4456bb, 66ae088f, 67861aa6).
- **Emitters do not lint their output**, so generated-artifact defects
  reached a sixth review round (obs 8c6fdca5).
- **Portability repeats almost verbatim** (`mktemp` without a template,
  GNU `timeout`, `find -maxdepth`, `sort -V`): 17 threads across more than
  8 PRs in one slice, 28 in the other; each is a lint rule.
- **Recurring classes a structural check could own:** raw untrusted input
  echoed to stderr against the repo's own echo discipline; `cd`, `mkdir`
  or `mktemp` given caller args with no leading-dash guard; `mkdir` lock
  failure read as contention when the directory is unwritable; `gh` or
  `jq` failure read as "absent" or "pass"; `config-get` not pinned to the
  repo root; a pipeline's `$?` read as the first stage's; comments that say
  "fail-closed" or "self-heals" over code that does neither.

## 4. What already owns adjacent territory (fold-detection outcome)

No bundle owns review effectiveness or review cost. Contracts this spec
consumes unchanged: custom-steps' convergence and post-pr points (never
`review_sequence`, which it retires); model-allocation's tier resolver
(its scope excludes context engineering and names a future spec as the
consumer of the `ctxeng-*` fragments); instruction-headroom's budgets and
floors; prose-disposition's amended Documentation lens and prose batching;
output-hygiene's PR-body presentation contract; bootstrap REQ-C/D/E as the
historical owner. prose-disposition (Ready) edits the same skill prose and
doctrine files, so an ordering decision is needed. Four spin-new triggers
fire against every extend candidate.

## 5. Candidate levers surfaced by the research (not decisions)

Effectiveness: a sibling-sweep step after every applied fix ("where else
does this property hold?"); a claim-versus-code lens for prose and headers;
whole-file-plus-callers reading for changed functions; whole-system
reproduction as the default pass 1 for shell; a bi-directional adversarial
pass with declared scoping and a resurrection path across iterations;
root-cause clustering before disposition; a reviewer-perspective check of
the would-be PR body against the diff before the PR opens; feeding bot and
external-backend findings back as a miss ledger; lint rules for the recurring shell
classes; emitter output linting; an independent-generator pass (different
model or different author session) as a declared step.

Cost: delta-scoped discovery after the first pass; a cheaper confirming
pass; a fresh, bounded context for the review pass rather than the
implementation transcript; passing the diff and file contents once instead
of each lens re-reading; not re-resolving doctrine and brief per pass;
proportional validation for tool-cited mechanical findings; one suite run
per iteration instead of per fix; point-of-use or section-scoped loading
of the run-start doctrine; charging the composed chain in the budget guard.

## 6. Observation fragments this research mined

Live fragments (UIDs) relevant to this spec, by theme. None carried a
`Consumed-by:` line at research time.

- Misses caught outside our passes: 01b3a1eb, 972182f6, 3e8a5d60, 97dc8742,
  8fdca68f, 749d937c, 247c430b, 7003944a, fa167d02, b11b9175, c50cc98d,
  f63eb20c, e9daedb7, 097e7cea, a682c3fc, 8c6fdca5, 587d7d7b, c1ed7ea1,
  d45387c2, 51fe1178, bf59017f, 5b1c9e77, 3ed95276, 15a7fdcb, 75c25c5d,
  98a155ab.
- Loop and convergence behaviour: a0add2f0, f03a7e23, d7e936d7, 36916a48,
  921b93c9, b23d6ea9, 54b2c3b6, 2f71ba54, 588f099a, 35e89205.
- Bot reviewer mechanics: 8b24690f, 51b53aa5, 67aafd6a, 148dc028.
- External backend reliability: 03653377, 361dd7e5, fbf43658, 4f7c2e91,
  b7d3e2a1.
- Lens fan-out mechanics: 19ec8cd4, 8dcf0f7c, 9c3cf221, c10c0a24, 7da1eedb,
  3672d83d, 38f3809f, 614d4db7, 830c511b, 0299c9fa, 7c83417d, 11bd17fe,
  aaf2fd57.
- Validation rigor and evidence quality: af6048cb, e9f5cc37, 6a2d1abd,
  e25c7458, ef2549c2.
- Categorization edges: 49ad55ea, 7f0b4274, c06b2908, 5756e0af, 84f076ea,
  9124476b.
- CI gate cost inside convergence: 7fe26f10, 0c4456bb, 67861aa6, 66ae088f,
  14bf37c8, edf96ce1, 38dcb4ee, f240fe9c.
- Instruction budget of the review skills: d2abb33d, 97e811db, 4a3e2947,
  fb7cd43e, 8905e6b9, 15240f38, 7c02f52b, 8d2f1a63, d20e8988, 34cae1db,
  4034976f, fbc582f6.
- Review noise and follow-up volume: d394ee29, 61e551d2, 82f8272b,
  062ee866, 2ed2c876, a7a7cc84, 980f2be4, ed0c7477.

Frozen legacy lines (`specs/_observations/opportunities.md`) relevant and
unconsumed: the 2026-06-11 fan-out partial-failure entry, the 2026-06-11
resolution-ladder silence entry, the 2026-06-12 polish loop-bounds entry,
the 2026-06-15 self-hosting rigor gap entry, the 2026-06-15
dispatch-isolation decision entry, the 2026-06-16 review/disposition
asymmetry entry, the 2026-06-16 validation thoroughness gap entry, the
2026-06-16 bi-directional re-validation scoping entry, and the 2026-06-16
base-capture contract entry.

## 7. Method and limits

- PR mining: `gh api` over reviews, review comments, issue comments,
  commits and files for every PR; disposition from the owner's reply
  ("Fixed in", "Addressed in" versus "false positive", "by design");
  category and miss reason model- or regex-assigned (spot-checked error
  rate about 20%, mostly the security/correctness split); lens status from
  the final PR body, which cannot distinguish pre-review `none` from
  post-review rewrites; external-backend findings appear only as PR-body prose and
  were not itemized.
- Token telemetry: every assistant message's usage in the Claude Code
  transcripts for this repo's checkouts (301 main sessions, 728 sub-agent
  transcripts), de-duplicated by message id, cross-checked against the
  fleet `result` events to within 0.1%; run boundaries heuristic (skill
  marker to next non-review marker, human message, or PR creation);
  external backends (the bot reviewer and the external backends) not measurable.
