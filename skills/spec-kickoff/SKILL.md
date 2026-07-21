---
name: spec-kickoff
description: >
  Walk a spec bundle section by section to mutual understanding, producing
  the signed-off kickoff brief downstream skills execute from. On sign-off:
  runs the Discovery-Rigor lens pass, flips Draft to Ready, records the
  sign-off record (anchor last), commits, pushes, opens a draft PR, then on
  clean completion marks the spec PR ready (mark_spec_pr_ready_on_kickoff
  opt-out). Also runs delta re-walkthroughs and amendments; halts on genuine
  spec inconsistency rather than papering over it.
argument-hint: "<spec-path>"
---

# /spec-kickoff

The comprehension layer of the planwright pipeline (REQ-B2.4, REQ-B2.2):
a section-by-section walkthrough of a spec bundle until human and agent
hold the same understanding, recorded as `specs/<spec>/kickoff-brief.md` —
the durable contract (two-brief model, D-3). Downstream skills
(`/execute-task`, `/orchestrate`) operate from the brief, not the spec; what
this walkthrough gets wrong, execution gets wrong. The agent probes, the human
corrects.

Sign-off is the first key of a two-key launch (D-44): it flips the spec
Draft→Ready and, on a clean completion, marks the spec PR ready (D-6, D-7; the
walkthrough is the bundle's review). The human's merge is the second key,
making the Ready spec operational (the first dispatch derives Active, not this
skill). This skill marks only the spec PR ready, never merges, never dispatches
execution.

## Doctrine

This skill is procedure, not doctrine. Resolve and read the run-start rule
docs via the rule-doc resolution convention
(`scripts/resolve-rule-doc.sh <doc-name>` under the resolved planwright
root); their definitions govern wherever this skill names a concept:

- `security-posture` — artifact data-hygiene: the brief and risk register are
  committed.

**Invoking plugin scripts (REQ-D1.1, D-7).** Call `scripts/<name>.sh` by the
**resolved literal absolute path**, never `$VAR/scripts/<name>.sh` —
`doctrine/plugin-script-invocation.md`.

`spec-format` (pre-flight step 2) — the meta-spec: bundle format, status
lifecycle, amendment ritual, sign-off records, content anchors, and sanctioned
anchor command forms. This skill is the writer its sign-off rules name; it
follows them exactly. Three more, at Sign-off step 1:

- `discovery-rigor` — the lens checklist, coverage table, and fan-out behind the
  lens review.
- `autopilot-reflex` — the altitude gate (D-11) behind the altitude check.
- `validation-rigor` — validation of lens findings before disposition.

If any of those five does not resolve — at run start or point of use — halt
naming the missing doc and the chain consulted (REQ-K1.7). The rest degrade
gracefully instead:

- `decision-domains` — the gap check's catalog. Absent: note it in one line,
  skip the gap check, and record the skip in the brief.
- `interaction-style` — governs the flow's exchanges; `kickoff-dialogue`
  (point-of-use) records their `/spec-kickoff` instantiation. Either doc absent:
  follow the inline summary (progress indicator, small bites, selectors with a
  recommendation, running summary) and the walk/sign-off spine below, and note
  which is missing.
- `kickoff-verification` — the kickoff lens/verification mechanics: the mid-walk
  lens (walkthrough), the stale-reference sweep and sign-off lens-review scope,
  fan-out, and altitude check (sign-off), and the terminal ready-flip CI gate
  (step 8). Each pass's load-bearing spine stays inline.
  Absent: run each from
  that spine and its halt-if-absent base (`discovery-rigor`, `autopilot-reflex`),
  and skip the ready-flip, leaving the PR draft (fail closed).

Doctrine manifest (the reading model above in machine-parseable form, per
`doctrine/instruction-hygiene.md`; `run-start` loads before work begins,
`point-of-use` loads at the named step or branch):

Doctrine: run-start security-posture
Doctrine: run-start interaction-style
Doctrine: point-of-use spec-format (pre-flight step 2)
Doctrine: point-of-use discovery-rigor (the sign-off lens pass)
Doctrine: point-of-use autopilot-reflex (the sign-off altitude check)
Doctrine: point-of-use validation-rigor (lens-finding validation)
Doctrine: point-of-use decision-domains (the sign-off gap check)
Doctrine: point-of-use kickoff-verification (kickoff lens/sweep passes and the ready-flip gate)
Doctrine: point-of-use kickoff-dialogue (discipline instantiation, approval summary, structured-log emit)

## Modes

Three modes, selected at pre-flight from status and brief state:

- **First activation** (Draft, no signed brief — or a partial one, see
  resumability): the full walkthrough through first sign-off, the
  Draft→Ready flip, push, draft PR, and — on clean completion — the terminal
  spec-PR ready-flip (sign-off step 8).
- **Delta re-walkthrough** (Ready or Active, signed brief): entered when
  pre-flight step 2's freshness comparison finds changed spec content (the remedy
  REQ-F1.9's gate names) or the human asks. Walk only the delta; the lens pass is
  delta-scoped; the outcome is an appended amendment-log entry with a fresh
  anchor.
- **Amendment** (Active; human-declared, never inferred): the REQ-A3.3
  meaning-class vs expression-only split, applied at sign-off (sign-off steps 1
  and 5).

**Change-handling scales with the lifecycle stage (REQ-D1.4).** A Ready bundle
(signed off, pre-merge, nothing dispatched) takes pre-merge changes through a
delta re-walkthrough / re-sign-off — not the amendment ritual — and the spec PR
stays as it was (no reopen). The amendment ritual is reserved for an Active
bundle (work in flight), where the change coordinates with execution underway.
A Done bundle reopens to Draft first (the REQ-A1.6 reopen cycle below) — never
amended in place. The per-class ritual detail (expression-only changelog +
self-re-anchor vs. meaning-class delta lens pass + fresh anchor) is
`spec-format`'s *amendment ritual*.

A **reopened bundle** (Status Draft with a complete signed brief — the
REQ-A3.1 / REQ-A1.6 reopen cycle, entered when `/spec-draft --extend` flips a
Done spec back to Draft) is a scoped kickoff of the delta, not a first
activation: walk the extension delta in the delta re-walkthrough shape, and the
sign-off flips Draft→Ready again (the delta's first dispatch derives Active). A
Done spec has nothing to kick off: point at `/spec-draft --extend`. Retired and
Superseded are terminal: refuse — no skill-driven transition leaves them.

## Pre-flight

1. **Parse `$ARGUMENTS`.** Expect a spec path (`specs/<spec>` or the bare
   `<spec>`). Validate the `<spec>` segment against the anchored, full-string
   pattern `^[a-z0-9][a-z0-9-]*$`, maximum length 64 (REQ-A1.8), **before** it
   appears in any path, branch name, or command; a failing identifier is never
   interpolated. No argument: list the bundles under `specs/`
   (underscore-prefixed accumulators are not bundles) and ask.
2. **Verify the bundle and select the mode.** All four files must exist
   (`requirements.md`, `design.md`, `tasks.md`, `test-spec.md`). A missing file
   or unreadable status is a structural defect: surface it and point at
   `/spec-draft`. Resolve and read `spec-format` here. Read the `**Status:**`
   line:
   - **Draft** → first activation; a resume when step 6 finds a partial
     brief; a reopened-bundle delta kickoff when the brief is complete
     and signed (per the Modes section).
   - **Ready or Active with a signed brief** → run the freshness comparison:
     parse the brief's most recent anchor entry, recompute the anchor with the
     command it records, and compare. **Mismatch** → delta re-walkthrough;
     derive the delta from the four spec files' git history since the entry plus
     any uncommitted changes, and confirm scope with the human first. **Match**
     → nothing is stale; ask what the human brings (a re-walk on request, or —
     on an Active bundle — an amendment, always human-declared; a Ready bundle's
     pre-merge change is the delta re-walk path, REQ-D1.4). On a format-version 2
     bundle the stored header rests at Ready — Active is derived — so distinguish
     Ready from Active via the render (`mise run status specs/<spec>`), never a
     stored `Active`. **Brief or anchor entry absent, unparseable, or
     non-sanctioned** (e.g. a hand-flipped spec that never had a kickoff) → the
     sign-off record needs creating or repairing; this skill's sign-off flow is
     the repair REQ-F1.9 names: walk it as a whole-bundle delta re-walkthrough (a
     missing brief gets the full first-activation structure minus the
     already-done flip).
   - **Done / Retired / Superseded** → per the Modes section.
3. **Run the validator.** `scripts/spec-validate.sh specs/<spec>` when present
   and executable. Draft findings are warnings: surface them, fix structural
   ones with the human before walking, and record the outcome for the brief
   header. Ready or Active findings are errors (status-aware — Ready blocks on
   errors exactly as Active does): surface them and carry each
   into the walk as a must-fix item; the delta walk fixes them, and sign-off
   step 4's re-validation refuses to record while any remain. Validator absent
   or not executable: an authoring path degrades rather than halts (REQ-K1.7) —
   but a merged signed-off bundle is dispatchable, so this run's sign-off lands
   unvalidated (whether or not it flips Draft→Ready). Naming the Draft→Ready
   flip only when this run flips, ask the human whether to proceed anyway or
   stop, install the validator, and re-run.
4. **Read the config.** `commit_on_kickoff`, `mark_spec_pr_ready_on_kickoff`,
   and `kickoff_ready_ci_wait` (default `10m`) from `config/defaults.yml`
   overridden by `<repo>/.claude/planwright.local.yml` (local wins). The
   booleans default `true`; an absent, unreadable, or malformed value falls back
   to its default with a one-line warning.
   `mark_spec_pr_ready_on_kickoff` gates the terminal ready-flip and
   `kickoff_ready_ci_wait` bounds its CI wait (sign-off step 8).
5. **Resolve the working location** (D-44, graceful in every starting state).
   The spec branch is `planwright/<spec>/spec` (the namespace `tasks-pr-sync`
   no-ops on); the spec worktree is `<repo>/.claude/worktrees/<spec>-spec` (D-37).
   - **Already in the spec worktree:** proceed; on dirty/diverged state, surface
     it and ask first — never auto-stash, auto-commit, or clean.
   - **In the main checkout or an unrelated worktree:** if the spec worktree
     exists, print the re-open command (`claude --worktree <spec>-spec`) and stop;
     if only the branch exists (worktree pruned), recreate it via Claude Code's
     native mechanism (never raw `git worktree`, D-37); if neither (a retrofit
     bundle that never went through `/spec-draft`), create both, then `git switch
     -c planwright/<spec>/spec` inside it, off the current main view.
   - **Not a git repository:** degrade per REQ-K1.7 — say so up front, walk and
     write the brief in place, skip every branch/commit/push/PR step, and surface
     at the end what was skipped. **No remote configured:** proceed; the push/PR
     step degrades when reached.
6. **Detect a partial brief** (resumability). If `kickoff-brief.md` exists,
   classify it: per-section `Signed off:` lines present but no final sign-off
   record with an anchor → a killed session left a resumable partial brief.
   Present the running summary of every signed section, confirm it still stands,
   and resume at the first unsigned section — signed sections are not re-walked
   unless the human asks. A final record lacking its anchor line is the same case
   (anchor-written-last, by design): resume at the sign-off step.
7. **Surface the optional independent walkthrough (suggest only).** Recommend the
   human may optionally run `/spec-walkthrough specs/<spec>` for an unaided cold
   read — the complement to this guided dialogue, not a replacement, never a
   dependency (REQ-F1.1, REQ-F1.2, D-11; comprehend-first stays in-band, per
   `kickoff-dialogue`). This skill never performs it; sign-off does not depend on
   it.

## The walkthrough

Section by section, in the brief's required structure (`spec-format` defines
it; written incrementally, one section to disk as signed). It covers components
1–7; the remaining two (sign-off section, amendment log) are written by the
sign-off flow below, not walked. Every exchange follows the `interaction-style`
rules
(progress indicator `[section <n>/7]`, small bites, selectors with a
recommendation, running summary after each section) and **instantiates the three
disciplines in-band, and emits the structured decision/transcript log the eval
grades, per `kickoff-dialogue`** (REQ-F1.1, REQ-G1.3): comprehend-first (section
2), with **adaptive-level calibration** (frontier detection, fade, a lightweight
per-concept uptake estimate, no learner model; REQ-B1.3, REQ-B1.4, D-4);
backward-chaining completeness bounded per pass, present without steering. Each
section ends with an explicit
`Signed off: <date>` line — what resumability keys on.

1. **Header block.** Spec path, spec commit at walkthrough start, walkthrough
   date, validator outcome from pre-flight. Written first, no sign-off needed.
2. **Goal & glossary.** Restate the goal in the agent's own words — a
   restatement, not a summary: what the spec is for, rules out, and assumes.
   Surface implicit terms (vocabulary the spec uses but never defines) and
   record resolutions to every ambiguity the restatement exposes.
3. **Requirements walkthrough.** Per REQ group: restate the group's intent,
   probe edge cases and gaps Socratically, and record per-group outcomes and
   decisions. Collect spec edits in a consolidated list rather than scattering
   them (applied per the edit rules below).
4. **Design walkthrough.** Every D-ID accounted for — confirmed (rationale
   intact), amended (what changed and why), or superseded — with a reconciled
   ledger. A design decision that contradicts a walked requirement is an
   inconsistency (below), not a ledger entry.
5. **Verification approach.** Review the coverage mix across test-spec tags,
   state verification ownership (which CI runs `[test]` entries, who sweeps
   `[manual]`), and check for dead paths — REQs whose named verification cannot
   actually run.
6. **Task graph.** Reconstruct the dependency graph from the `Dependencies:`
   lines (authoritative; any diagram is derived), identify parallelism and the
   effort-weighted critical path, and record deliberate non-edges so nobody
   "fixes" them later.
7. **Risk register.** Numbered rows of risk + mitigation / early signal.
   Inputs: risks surfaced during the walk, the human's cold-review questions,
   and the **decision-domains gap check** — walk the catalog against the spec
   (the prose seed plus overlay-added domains via the merged path
   `scripts/resolve-catalog.sh decision-domains`, so adopter/team additions
   count, REQ-D1.1); any catalogued domain the spec touches but never decides
   becomes a risk-register row naming the domain and the undecided question
   (REQ-G1.4, D-39). Catalog absent: record the one-line skip here. Open
   questions must end resolved to decisions or explicit accepted risks.

**Spec edits during the walkthrough.** A Draft bundle is unsigned: edits land
in place, applied with the human section by section, and the consolidated list
is recorded in the brief. On a signed bundle the stage-scaled change-handling
above governs (REQ-D1.4); post-merge changes follow `spec-format`'s supersede /
changelog rules. An agent-authored meaning-class edit applied here also gets the
mid-walk delta-scoped lens pass at the point of application — its disposition
recorded in the brief section carrying it, an erroring pass surfaced
(`kickoff-verification`, REQ-B1.4, D-5).

**The inconsistency halt (REQ-B2.3).** A genuine spec inconsistency — two
requirements that contradict, a design decision that contradicts a requirement,
a Done-when no deliverable can satisfy — halts the walkthrough rather than being
papered over. Present the contradiction with both readings and the smallest
edit that resolves each way. The human resolves by **editing the spec** (the
affected sections re-walk) or **recording an explicit override in the brief**
(the contradiction stands, named, with the chosen reading and rationale). Until
one happens there is no sign-off, no Ready flip, and no anchor entry: the run
ends with the partial brief on disk and the halt reason stated. Fail closed.

## Sign-off

Sign-off runs only when every section above is signed and no inconsistency is
open. Its steps are ordered so a session killed at any point fails closed: the
most recent anchor entry never describes spec content that was not walked.

1. **The lens review pass.** On a re-walkthrough or amendment, first ask the
   human to classify the delta on the REQ-A3.3 axis (recorded later in the
   `Class:` line, but needed now to scope this pass). Then run the
   Discovery-Rigor lens review of the bundle per `kickoff-verification` (scope,
   fan-out, and the canonical lens-coverage table there; D-45, REQ-A3.3). The
   **kickoff-specific altitude check (REQ-H1.3)** — a check item, not a new lens
   — runs within this pass per `kickoff-verification`.
   Validate findings per `validation-rigor`, then disposition every one with the
   human (applied as a spec edit, declined with rationale, or deferred to a
   named backlog in the brief) — an undispositioned finding blocks the anchor.
   Record table and dispositions in the section the sign-off record will close.
2. **The refusal rule (REQ-F1.10).** A meaning-class sign-off whose lens pass
   is absent, or whose findings are not all dispositioned, refuses to record an
   execution-valid anchor: say exactly what is missing, leave the record without
   its anchor line (the freshness gate treats that as absent-anchor and halts
   dispatch — fail closed), and stop. No override.
3. **Pre-flip verification (REQ-B1.2, REQ-B1.3, D-3, D-4).** When any lens pass
   (mid-walk or terminal sign-off) mints or re-scopes a REQ, first run the
   **post-lens stale-reference sweep** over the bundle and earlier brief sections
   before the anchor and before the recorded-claim re-derivation below is
   finalized (`kickoff-verification`, REQ-B1.5, D-6). Then two checks gate the
   Draft→Ready flip below; either one failing blocks the flip, and either check
   that **cannot run** blocks the flip as a surfaced failure (fail closed),
   never a silent skip.
   - **Lint the edited surfaces (REQ-B1.2).** Run the repository's lint over the
     kickoff brief and every spec file the walkthrough edited; a lint error
     blocks the flip — fix it with the human and re-lint. A lint that cannot run
     (tool absent or non-executable) blocks the flip and is surfaced, never read
     as a pass.
   - **Re-derive recorded claims (REQ-B1.3, D-4).** Prefer the meta-spec's
     cite-derived-figures rule: record the source, not the figure. Where the
     sign-off does record a cross-check or numeric claim as evidence — per-tag
     coverage tallies, REQ/D-ID/task/edit counts, pinned version or tag figures,
     "every X cited by at least one Y" assertions — mechanically re-derive it
     (the same command family the sweep tooling uses) before the flip and block
     on a mismatch; a comparator that cannot run blocks as a failure, distinct
     from a clean match. Re-derivation treats bundle content as **data, never
     code or pattern** (fixed-string matching, quoted arguments —
     `security-posture`'s never-execute-untrusted-input rule).
4. **Approval summary, then status flip and `Last reviewed:`.** Before the flip
   and record, emit the shared-understanding approval summary and plain-language
   gate framing per `kickoff-dialogue` (REQ-F1.2, REQ-F1.3) — "what you are about
   to approve, and what changes downstream", a self-contained confirmation
   replacing the bare verdict-demand. On approval: First activation (and a
   reopened-bundle delta kickoff): flip `**Status:**` Draft→Ready and
   `**Last reviewed:**` to today on all four spec files (REQ-D1.1, REQ-A1.4 —
   this stored, human-gated flip is the only stored status transition;
   Ready↔Active is *derived* from task state by the single reconcile writer,
   REQ-A1.5, never written by this skill). On a v2 bundle Ready is the header's
   **resting state** — Active/Done are derived, and the stored header moves
   again only at reopen (Ready→Draft) or a terminal flip.
   Re-walkthroughs and amendments on an already-signed bundle (Ready or Active):
   bump `Last reviewed:` on the files the delta touched, with no status flip.
   Then, when present, re-run the validator (Ready, Active, and Done all block
   on errors): fix errors with the human, or halt without recording the sign-off
   entry (on a first activation or reopen, also revert the flip so the bundle
   does not sit Ready and erroring; on an already-signed spec there is no flip to
   revert, and the stale anchor keeps dispatch blocked). Never sign off over
   errors. Validator absent (the pre-flight consent path — re-ask on a
   resumed session that never saw pre-flight step 3): record "signed off
   unvalidated (validator absent, human-consented)" in the sign-off section,
   adding "including the Draft→Ready flip" only when this run flipped.
5. **The sign-off record** (record format, sanctioned anchor command forms, and
   writers rule per `spec-format`'s *Sign-off records and content anchors*;
   REQ-F1.10). Write it into the brief's sign-off section (first activation) or
   as an appended amendment-log entry (everything later) — sections above the
   amendment log are append-only after first sign-off. Carry `Class:`,
   `Lens-pass:` (meaning-class only), and **the anchor line last** (the
   fail-closed ordering). Compute the anchor
   with `scripts/spec-anchor.sh specs/<spec>` after every spec-file edit of this
   run (flip, `Last reviewed:`, applied findings) is on disk; it fails closed on
   a defective bundle — surface its stderr and stop with no anchor line, never
   hand-roll it, and reach for the sanctioned interim whole-file form only when
   the script is absent (recording that exact command). This flow is the only
   writer of a meaning-class entry; it writes an expression-only entry (no lens
   pass, citing the changelog line) only when the human classified the entire
   delta expression-only.
6. **Commit** (D-41) when `commit_on_kickoff` is true: one commit on
   `planwright/<spec>/spec` with the brief, the four spec files, and any
   observation fragment from this run — first activation `feat(spec):
   <spec> kickoff, brief + Ready flip`; later events `docs(spec): <spec>
   <event>` (e.g. `delta re-walkthrough`, `amendment`). New commits only —
   never force-push, amend, squash, or rebase (REQ-J1.4). Opt-out: leave the
   work uncommitted, say so, and skip push/PR.
7. **Push and draft PR** (REQ-B2.4, D-44). Run the Observations and Maintenance
   steps below before pushing (step 8's ready-flip issues no commit), so their
   chore commits land before the push and nothing is left unpushed. Then push:
   `git push -u origin planwright/<spec>/spec`. Then the PR: if one exists for
   the branch, update its body; otherwise `gh pr create --draft` with `--title`
   and `--body`. The title must pass the conventional PR-title lint
   (`scripts/check-commit-msgs.sh`, enforced on PR titles in CI at 100 chars):
   `feat(spec): <spec> kickoff sign-off` for a first activation, `docs(spec):
   <spec> <event>` for later events. The body carries the spec path, brief path,
   walkthrough scope (full or delta), validator outcome, lens-pass summary, and
   the anchor. On no remote, push rejection, or `gh` absence/auth failure:
   degrade per REQ-K1.6/K1.7 — the work is committed; record a note in the
   spec's `tasks.md` `## Awaiting input` section naming the pending push/PR step
   and the failure, surface it in the handoff, and stop. Never retry into an
   opaque failure.
8. **Mark the spec PR ready (terminal step, D-6/D-7; REQ-D1.2, REQ-D1.3,
   REQ-D1.5).** The run's final action, only on a **clean completion** — the
   sign-off record above is written with its anchor (no inconsistency halt, no
   carried open question, every lens finding dispositioned) and any configured
   verification has converged. That verification (informally a "gauntlet") is
   the configurable `review_sequence`-class mechanism (D-7,
   customization-overlay D-6 / REQ-D1.3), **not a hardcoded** core step: in bare
   core it is this skill's own walkthrough and Discovery-Rigor lens pass; an
   overlay may run an additional review pass over the spec PR whose terminal
   step is this flip. When
   `mark_spec_pr_ready_on_kickoff` is true (pre-flight step 4) and the
   completion is clean, un-draft the spec PR — but **first gate the flip on the
   head SHA's CI** per `kickoff-verification` (REQ-B1.1, D-3), then **check its
   state** (`gh pr view <spec-PR> --json isDraft,state`) and run `gh pr ready
   <spec-PR>` **only while it is still a draft**; skip it when the PR is already
   ready or merged/closed (a benign no-op that would otherwise exit non-zero and
   wrongly trip the degradation path). This is the narrow exception to bootstrap
   D-26's all-drafts rule: **only the spec PR**, and only this skill, marks a PR
   ready; **task PRs stay drafts** (their review is owned by the execution and
   review skills). Merge stays the human's second key —
   **never auto-merge**.
   - **Do not flip** when sign-off parked on a fork (inconsistency halt, carried
     open question, undispositioned finding) or the configured verification did
     not converge: leave the PR draft and say so in the handoff.
   - **Opt-out:** `mark_spec_pr_ready_on_kickoff: false` suppresses the flip;
     the PR stays draft and the human un-drafts it by hand.
   - **Degrade, never retry into opacity (bootstrap REQ-K1.6/K1.7):** if the
     flip itself fails — no remote, `gh` absent or auth failure, PR not found —
     the recorded sign-off stands (never roll it back); record the pending
     ready-flip in the spec's `tasks.md` `## Awaiting input` section naming the
     failure, surface it in the handoff, and stop.

**Hand off.** Report: mode and scope, sections walked, spec edits applied,
gap-check outcome, lens-pass summary, the anchor, commit/push/PR outcome (or
degradation notes), the spec PR's ready/draft state (with the reason when it
stayed draft), and the next step — merge the spec PR (now ready), then
`/orchestrate specs/<spec>`.

**Data hygiene throughout (`security-posture`):** the brief, risk register, and
PR body are committed — no secrets, credentials, internal hostnames, or
sensitive detail; neutralize what discussion surfaces before writing it.

## Observations

When anything outside this kickoff's scope surfaces during the walk (doctrine or
tooling gaps, recurring friction, an uncatalogued decision domain), record one
fragment per item through the shared helper `scripts/obs-record.sh --slug
<topic> --scope <repo> --text '<observation>'` (resolved under the planwright
root) and commit it (with the sign-off commit, or as its own chore commit);
surface a non-zero helper exit rather than dropping the observation. Do not act
on observations during the kickoff; they are seed material for `/spec-draft`.

## Maintenance

Before the push step on a run that reaches sign-off (so the chore commit lands
pushed), or at the halt point otherwise, compare these instructions against the
resolved doctrine docs listed above (REQ-B3.2, D-42) — especially `spec-format`
and `decision-domains`. If a concept this skill names has changed meaning,
gained or lost a step, or moved between docs, record a drift observation through
the shared helper (`scripts/obs-record.sh --slug skill-drift --scope <repo>
--text 'skill-drift(spec-kickoff): <what>'` — keeping the `skill-drift(...)`
prefix; in repositories without `specs/`, surface the drift to the user
instead), commit it as its own chore commit, and tell the user what drifted;
surface a non-zero helper exit rather than dropping it. Do not edit this skill or
the doctrine docs to resolve the drift; `/spec-draft` owns folding drift into
spec amendments.
