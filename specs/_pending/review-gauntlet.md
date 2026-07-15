# Seed brief for `review-gauntlet` (scoped out of `fleet-autonomy`)

Suggested invocation (fresh Claude session in the planwright repo, this file is the seed):

    /spec-draft review-gauntlet

Read this whole brief before eliciting. Run fold-detection against `bootstrap` (Done — likely owner
of `/execute-task`'s convergence mechanics today) and `customization-overlay` (Done — owner of the
four-layer overlay mechanism this whole ask plugs into) before assuming a new bundle; this brief
does not prejudge extend-vs-spin-new.

## Why this is a separate spec, not folded into `fleet-autonomy`

Surfaced during the `fleet-autonomy` drafting session (2026-07-14): the operator wants to configure
their personal PR-readiness gauntlet — concretely, running `/polish`, `/self-review`,
`/panel-pairing`, and `/copilot-pairing` in that order before marking a task PR ready. This is
task-execution convergence architecture (which review skills run, in what order, against what
target), not fleet/worker/tower orchestration (the subject of `fleet-autonomy`). Folding it in would
repeat the exact scope-mixing `fleet-autonomy`'s own fold-detection pass flagged and corrected at the
start of that session — a different decision domain deserves its own bundle.

## The problem

`review_sequence` (`config/defaults.yml`, default `[polish]`) already exists: an overlay-resolved
(`scripts/resolve-review-sequence.sh`, four-layer precedence) ordered list of **nestable** review
skills `/execute-task`'s convergence phase runs, each in its own fresh `/resume`-seeded session
(`dispatch_isolation: per-step`). `customization-overlay`'s own Goal section names "a review-gauntlet
ordering" as one of its two motivating examples for the overlay mechanism — so reordering/extending
*this* chain is already solved, and needs no new spec.

The gap is precise, not vague:

1. **`/panel-pairing` and `/copilot-pairing` are not "nestable."** `resolve-review-sequence.sh`'s own
   header states the current nestable set is `{polish, self-review}` (a skill is nestable if its
   `SKILL.md` frontmatter declares `--nested`). Both are pre-PR convergence skills, run in a fresh
   session per step. `/panel-pairing`/`/copilot-pairing` are architecturally different: **post-PR**
   autonomous loops that address review comments against an already-open PR. Slotting them into
   `review_sequence` as it exists today is a category error, not a missing list entry.
2. **No automation marks a task PR ready.** `mark_spec_pr_ready_on_kickoff` exists only for **spec**
   PRs, as a narrow, explicitly-considered, opt-outable exception to bootstrap's all-drafts rule
   (task PRs always stay draft for a human to un-draft). Extending "mark ready on clean convergence"
   to task PRs is a new policy decision with the same shape as that prior one — not something to
   default into existing, and not something this seed should pre-decide.

## Constraints / non-goals

- **Never-auto-merge stays permanent**, unaffected by anything here — this is about draft-vs-ready,
  never about merge.
- Whatever chaining mechanism results **must resolve through the existing four-layer overlay**
  (`config-get.sh` / the `resolve-*.sh` pattern `review_sequence` already establishes), not invent a
  second config-resolution path.
- Do not assume task-PR-ready automation is wanted by default — if the drafter and human decide to
  add it, it needs its own considered default (most likely opt-in or opt-out mirroring
  `mark_spec_pr_ready_on_kickoff`'s posture) and its own convergence-criterion definition analogous
  to that knob's "after the configured review_sequence verification has converged."

## Open questions for the drafter to resolve (with the human)

1. Should `/panel-pairing`/`/copilot-pairing` gain `--nested` support so they fit the *existing*
   `review_sequence` knob uniformly, or does post-PR chaining need its own distinct mechanism given
   the real architectural difference (pre-PR fresh-session convergence vs. post-PR loops against a
   live GitHub PR)?
2. Is this a `bootstrap` amendment (reopen Done→Draft, since `/execute-task`'s convergence phase is
   likely specified there) or a new sibling spec (the carve-out pattern `observation-recording` used
   against `output-hygiene`)? Fold-detection should decide this, not this brief.
3. If task-PR-ready automation is added: what's the safe default (on or off), what exactly counts as
   "converged" across a mixed pre-PR/post-PR chain, and does a failure anywhere in the chain degrade
   to `tasks.md` `## Awaiting input` the same way `mark_spec_pr_ready_on_kickoff`'s failure path does?
4. Is the desired granularity global (one `review_sequence`-equivalent for the whole repo) or
   per-spec/per-task-type (e.g., security-sensitive tasks get a longer gauntlet)? The overlay layers
   already support per-repo and per-machine granularity; confirm whether that's sufficient or a new
   axis (per-task-type) is actually wanted.

## References

- `docs/options-reference.md` — `review_sequence` and `mark_spec_pr_ready_on_kickoff` rows (exact
  current behavior and defaults).
- `scripts/resolve-review-sequence.sh` — header comment naming the current nestable set and the
  by-layer malformed-value policy.
- `specs/customization-overlay/requirements.md` — Goal section naming "a review-gauntlet ordering" as
  a motivating example for the overlay mechanism.
- CLAUDE.md's "Review Workflows" section — the seven review skills and which are transitional
  (`/copilot-review`, `/copilot-pairing`, both slated for retirement once `/panel-*` proves out).
- `specs/fleet-autonomy/` — the drafting session this was scoped out of (2026-07-14).
