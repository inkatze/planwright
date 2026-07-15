---
name: spec-kickoff
description: >
  Walk a spec bundle section by section to mutual understanding, producing
  the signed-off kickoff brief that downstream skills execute from. On
  sign-off: runs the Discovery-Rigor lens pass, flips Draft to Ready,
  updates Last reviewed, records the machine-checkable sign-off record with
  the content anchor written last, commits brief + flip (commit_on_kickoff
  opt-out), pushes the spec branch, opens a draft PR, then on clean completion
  marks the spec PR ready as the terminal step (mark_spec_pr_ready_on_kickoff
  opt-out). The human's merge makes the Ready spec operational; the first
  dispatch derives Active. Also
  runs delta re-walkthroughs (on a Ready or Active spec) and amendments (on
  an Active spec). Halts on genuine spec inconsistency rather than papering
  over it.
argument-hint: "<spec-path>"
---

# /spec-kickoff

The comprehension layer of the planwright pipeline (REQ-B2.4, REQ-B2.2):
a section-by-section walkthrough of a spec bundle until human and agent
hold the same understanding, recorded as `specs/<spec>/kickoff-brief.md` —
the durable contract (two-brief model, D-3). Downstream skills
(`/execute-task`, `/orchestrate`) operate from the brief, not by re-reading
the spec; what this walkthrough gets wrong, execution gets wrong, so the
walkthrough is mutually didactic: the agent restates and probes, the human
corrects, and the agent surfaces what the human has not considered.

Sign-off is the first key of a two-key launch (D-44): it flips the spec
Draft→Ready and, on a clean completion, marks the spec PR ready (D-6, D-7; the
walkthrough is the bundle's review). The human's merge is the second key,
making the Ready spec operational (the first dispatch derives Active, via the
single reconcile writer — not this skill). This skill marks only the spec PR
ready (task PRs stay drafts, a narrow exception to bootstrap D-26), never
merges, never dispatches execution.

## Doctrine

This skill is procedure, not doctrine. Resolve and read the run-start rule
docs via the rule-doc resolution convention
(`scripts/resolve-rule-doc.sh <doc-name>` under the resolved planwright
root); their definitions govern wherever this skill names a concept:

- `security-posture` — artifact data-hygiene: the brief is committed and
  its risk register invites operational detail.

`spec-format` is read at pre-flight step 2, its point of use (only argument
parsing precedes it) — the meta-spec: bundle conventions, status lifecycle,
the required kickoff-brief structure, the amendment ritual, sign-off
records, content anchors, and the sanctioned anchor command forms. This
skill is the writer the meta-spec's sign-off rules name; it follows them
exactly. Three more are point-of-use reads at Sign-off step 1:

- `discovery-rigor` — the lens checklist, canonical lens-coverage table,
  fan-out, and self-critique pass behind the sign-off lens review.
- `autopilot-reflex` — the altitude gate (D-11): the trigger classes and the
  trigger-scoped altitude record behind the sign-off altitude check.
- `validation-rigor` — validation of lens-pass findings before they are
  dispositioned.

If any of those five does not resolve — at run start or point of use —
halt with a clear message naming the missing doc and the chain consulted
(REQ-K1.7). Two more resolve with graceful degradation instead:

- `decision-domains` — the gap check's catalog. Absent: note the missing
  catalog in one line, skip the gap check, and record the skip in the brief
  so the gap is visible.
- `interaction-style` — governs the exchanges in the flow. Absent: follow
  the summary inline here (progress indicator, small bites, selectors with
  a recommendation, running summary) and note the missing doc.

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

## Modes

Three modes, selected at pre-flight from the spec's status and the brief's
state:

- **First activation.** Status Draft, no signed brief (or a partial one —
  see resumability). The full walkthrough below, ending in the first
  sign-off, the Draft→Ready flip, push, draft PR, and — on a clean
  completion — the terminal spec-PR ready-flip (sign-off step 7).
- **Delta re-walkthrough.** Status Ready or Active with a signed brief, and
  the freshness comparison in pre-flight step 2 found the spec content changed
  since the brief's most recent anchor entry (this is the remedy
  REQ-F1.9's freshness gate names), or the human asks for a re-walk. Walk
  only the delta identified at pre-flight; the lens pass is delta-scoped;
  the outcome is an appended amendment-log entry with a fresh anchor.
- **Amendment.** Status Active; the human declares a specific change they
  are bringing — this mode is always human-declared, never inferred.
  Classified on the REQ-A3.3 axis (the human classifies at sign-off):
  meaning-class changes get a scoped walk of the affected sections, a
  delta-scoped lens pass, and a meaning-class entry; expression-only
  changes get a changelog entry and an expression-only anchor entry with
  no lens pass.

**Change-handling scales with the lifecycle stage (REQ-D1.4).** A Ready bundle
(signed off, pre-merge, nothing dispatched) takes pre-merge changes through a
delta re-walkthrough / re-sign-off — not the amendment ritual — and the spec PR
stays as it was (no reopen). The amendment ritual is reserved for an Active
bundle (work in flight), where a change coordinates with execution already
underway. A Done bundle reopens to Draft first (the REQ-A1.6 reopen cycle
below) — never amended in place. The per-class ritual detail (expression-only
changelog + self-re-anchor vs. meaning-class delta lens pass + fresh anchor)
is `spec-format`'s *amendment ritual*.

A **reopened bundle** (Status Draft with a complete signed brief — the
REQ-A3.1 / REQ-A1.6 reopen cycle, entered when `/spec-draft --extend` flips a
Done spec back to Draft) is a scoped kickoff of the delta, not a first
activation: walk the extension delta in the delta re-walkthrough shape,
and the sign-off flips Draft→Ready again (the delta's first dispatch derives
Active). A Done spec has nothing to kick off regardless of stray edits: say so
and point at `/spec-draft --extend` (the reopen path above). Retired and
Superseded are terminal: refuse — no skill-driven transition leaves a terminal
state.

## Pre-flight

1. **Parse `$ARGUMENTS`.** Expect a spec path (`specs/<spec>` or the bare
   `<spec>`). Validate the `<spec>` segment against the anchored,
   full-string pattern `^[a-z0-9][a-z0-9-]*$`, maximum length 64
   (REQ-A1.8), **before** it appears in any path, branch name, or command;
   a failing identifier is never interpolated anywhere. No argument: list
   the bundles under `specs/` (underscore-prefixed accumulators are not
   bundles) and ask.
2. **Verify the bundle and select the mode.** All four files must exist
   (`requirements.md`, `design.md`, `tasks.md`, `test-spec.md`). A missing
   file or unreadable status is a structural defect: surface it and point
   at `/spec-draft`; there is nothing to walk. Resolve and read
   `spec-format` here (its point-of-use read). Read the `**Status:**` line:
   - **Draft** → first activation; a resume when step 6 finds a partial
     brief; a reopened-bundle delta kickoff when the brief is complete
     and signed (per the Modes section).
   - **Ready or Active with a signed brief** → run the freshness comparison:
     parse the brief's most recent anchor entry, recompute the anchor with the
     exact command that entry records, and compare. **Mismatch** → delta
     re-walkthrough; derive the delta from the git history of the four
     spec files since the entry was recorded plus any uncommitted changes,
     and confirm that scope with the human before walking. **Match** →
     nothing is stale; ask what the human is bringing (a re-walk on
     request, or — on an Active bundle — an amendment, always human-declared;
     a Ready bundle's pre-merge change is the delta re-walk path, REQ-D1.4).
     **Brief or anchor entry absent, unparseable, or non-sanctioned** (e.g. a
     hand-flipped Ready/Active spec that never had a kickoff) → the sign-off
     record needs creating or repairing, and this skill's sign-off flow is the
     repair REQ-F1.9 names: walk it as a delta re-walkthrough scoped to the
     whole bundle (a missing brief gets the full first-activation structure
     minus the already-done status flip).
   - **Done / Retired / Superseded** → per the Modes section.
3. **Run the validator.** `scripts/spec-validate.sh specs/<spec>` when
   present and executable. On a Draft bundle findings are warnings: surface
   them, fix structural ones with the human before walking (a walkthrough
   over a malformed bundle wastes the human's attention), and record the
   outcome for the brief header. On a Ready or Active bundle findings are
   errors (the validator is status-aware — Ready blocks on errors exactly
   as Active does): surface them and carry each into the walk as a must-fix
   item — the delta walk fixes them with the human, and sign-off step 3's
   re-validation refuses to record while any remain. Validator absent or not
   executable: kickoff is an authoring path, so this degrades rather than halts
   (REQ-K1.7) — but a merged signed-off bundle is dispatchable, so the sign-off
   this run records lands unvalidated (on a first activation or reopen the
   Draft→Ready flip itself goes unvalidated; on an already-signed Ready or
   Active bundle there is no flip, but the re-sign-off still leaves it
   dispatchable and unvalidated). Naming the Draft→Ready flip only when this run
   flips, ask the human whether to proceed anyway or stop here, install the
   validator, and re-run `/spec-kickoff specs/<spec>`.
4. **Read the config.** `commit_on_kickoff` and
   `mark_spec_pr_ready_on_kickoff` from `config/defaults.yml` overridden by
   `<repo>/.claude/planwright.local.yml` (local wins). Both default `true`; an
   absent, unreadable, or malformed config file falls back to the defaults with
   a one-line warning surfaced now and repeated in the handoff.
   `mark_spec_pr_ready_on_kickoff` gates the terminal ready-flip (sign-off
   step 7).
5. **Resolve the working location** (D-44, graceful in every starting
   state). The spec branch is `planwright/<spec>/spec` (the reserved namespace
   the `tasks-pr-sync` hook no-ops on); the spec worktree is
   `<repo>/.claude/worktrees/<spec>-spec` (D-37 placement — the directory name
   disambiguates the literal `spec` branch suffix, which would collide across
   specs, while staying attachable via `claude --worktree <spec>-spec`).
   - **Already in the spec's own worktree:** proceed. Dirty or diverged
     state: surface it and ask before touching anything — never
     auto-stash, auto-commit, or clean.
   - **In the main checkout or an unrelated worktree:** if the spec
     worktree exists, do not work here — print the re-open command
     (`claude --worktree <spec>-spec`) and stop. If the spec branch exists
     but the worktree was pruned, recreate the worktree from the branch via
     Claude Code's native mechanism (`claude --worktree` / EnterWorktree —
     never raw `git worktree`, D-37). If neither exists (a hand-written or
     retrofit bundle that never went through `/spec-draft`), create them:
     worktree via the native mechanism, then
     `git switch -c planwright/<spec>/spec` inside it, branched from the
     current main view.
   - **Not a git repository:** degrade per REQ-K1.7 — say so up front,
     run the walkthrough and write the brief in place, and skip every
     branch, commit, push, and PR step below, surfacing at the end what
     was skipped and why. **No remote configured:** proceed normally; the
     push/PR step degrades when it is reached.
6. **Detect a partial brief** (resumability). If `kickoff-brief.md` exists,
   classify it: per-section `Signed off:` lines present but no final sign-off
   record with an anchor → a killed session left a resumable partial brief.
   Present the running summary of every signed section, confirm it still
   stands, and resume at the first unsigned section — signed sections are not
   re-walked unless the human asks. A brief whose final record exists but lacks
   its anchor line is the same case (anchor-written-last makes a killed session
   indistinguishable from absent-anchor, by design): resume at the sign-off
   step.
7. **Surface the optional independent walkthrough (suggest only).** Before the
   guided walkthrough, recommend the human may optionally run
   `/spec-walkthrough specs/<spec>` themselves for an unaided, plain-language
   cold read — the complement to this guided dialogue, not a replacement
   (REQ-F1.1, REQ-F1.2, D-11). A suggestion only; this skill never performs it,
   and sign-off does not depend on it.

## The walkthrough

Section by section, in the brief's required structure (`spec-format` defines
it; the brief is written incrementally, one section to disk as it is signed).
The walkthrough covers components 1–7 of that structure; the remaining two —
the sign-off section and the amendment log — are written by the sign-off flow
below, not walked. Every exchange follows the `interaction-style` rules
(progress indicator `[section <n>/7]`, small bites, selectors with a
recommendation, running summary after each section). Each section ends with an
explicit `Signed off: <date>` line — what resumability keys on.

1. **Header block.** Spec path, spec commit at walkthrough start,
   walkthrough date, validator outcome from pre-flight. Written first, no
   sign-off needed.
2. **Goal & glossary.** Restate the goal in the agent's own words — a
   restatement, not a summary: what the spec is for, rules out, and assumes.
   Surface implicit terms (vocabulary the spec uses but never defines) and
   record resolutions to every ambiguity the restatement exposes. This section
   anchors every later judgment call.
3. **Requirements walkthrough.** Per REQ group: restate the group's
   intent, probe edge cases and gaps Socratically, and record per-group
   outcomes and decisions. Collect spec edits in a consolidated list
   rather than scattering them (applied per the edit rules below).
4. **Design walkthrough.** Every D-ID accounted for — confirmed (rationale
   intact), amended (what changed and why), or superseded — with a
   reconciled ledger. A design decision that contradicts a walked
   requirement is an inconsistency (below), not a ledger entry.
5. **Verification approach.** Review the coverage mix across test-spec
   tags, state verification ownership (which CI runs `[test]` entries, who
   sweeps `[manual]`), and check for dead paths — REQs whose named
   verification cannot actually run.
6. **Task graph.** Reconstruct the dependency graph from the `Dependencies:`
   lines (authoritative; any diagram is derived), identify parallelism and the
   effort-weighted critical path, and record deliberate non-edges so nobody
   "fixes" them later.
7. **Risk register.** Numbered rows of risk + mitigation / early signal.
   Inputs: risks surfaced during the walk, the human's cold-review questions,
   and the **decision-domains gap check** — walk the catalog against the spec
   (the prose seed plus overlay-added domains via the merged path
   `scripts/resolve-catalog.sh decision-domains`, so adopter/team additions
   count, not just the core layer, REQ-D1.1); any catalogued domain the spec
   touches but never decides becomes a risk-register row naming the domain and
   the undecided question (REQ-G1.4, D-39). Catalog absent: record the one-line
   skip here. Open questions must end the section resolved to decisions or
   recorded as explicit accepted risks; an open question is not a sign-off.

**Spec edits during the walkthrough.** A Draft bundle is unsigned: edits land
in place, applied with the human section by section, and the consolidated edit
list is recorded in the brief. On a signed bundle the stage-scaled
change-handling above governs (REQ-D1.4, the Modes rule — Ready takes a delta
re-walkthrough, Active the amendment ritual); post-merge changes follow
`spec-format`'s supersede / changelog rules.

**The inconsistency halt (REQ-B2.3).** A genuine spec inconsistency — two
requirements that contradict, a design decision that contradicts a
requirement, a Done-when no deliverable can satisfy — halts the
walkthrough rather than being papered over. Present the contradiction with
both readings and the smallest edit that would resolve each way. The human
resolves by **editing the spec** (the affected sections re-walk) or by
**recording an explicit override in the brief** (the contradiction stands,
named, with the chosen reading and rationale). Until one happens there is
no sign-off, no Ready flip, and no anchor entry: the run ends with the
partial brief on disk and the halt reason stated. Fail closed, not
helpful.

## Sign-off

Sign-off runs only when every section above is signed and no inconsistency
is open. Its steps are ordered so that a session killed at any point fails
closed: the most recent anchor entry never describes spec content that was
not walked.

1. **The lens review pass.** On a re-walkthrough or amendment, first ask the
   human to classify the delta on the REQ-A3.3 axis — recorded later in the
   `Class:` line, but needed now because it sets this pass's scope. Then the
   pass: a Discovery-Rigor review of the bundle — the spec is the artifact, and
   spec bugs (a silent clean-no-op, a fixture encoding the spec's own wrong
   belief) are invisible to execution feedback, so this is the last line of
   defense (D-45). Scope: **full bundle at first activation**, **delta-scoped
   at re-walkthroughs and amendments**, **skipped for expression-only changes**
   (REQ-A3.3). Fan out one read-only sub-agent per canonical lens for any
   non-trivial delta per `discovery-rigor`; walk inline only for small, narrow
   deltas, and declare which path was taken. Emit the canonical lens-coverage
   table.
   **Kickoff-specific altitude check (REQ-H1.3)** — a check item, not a new
   canonical lens (the `discovery-rigor` list is untouched). Determine
   **bundle-locally** whether drafting fired an altitude trigger from the
   pinned seed claims in the bundle's `## Sources` section in `requirements.md`
   (never drafting-session memory); per `autopilot-reflex`, a present altitude
   D-ID is the record a fired trigger leaves — evidence a mid-flow signal was
   handled, not a trigger class in its own right. For a **triggered** bundle,
   verify the altitude D-ID exists, is cited from the bundle's goal, and that
   the task decomposition matches the claimed altitude (a doctrine-first bundle
   with only mechanism tasks is a finding, dispositioned like any other). An
   **untriggered** bundle requires no altitude record (per `proportionality`):
   record not-applicable and move on.
   Validate findings per `validation-rigor`, then disposition every one
   with the human (applied as a spec edit, declined with rationale, or
   deferred to a named backlog in the brief) — an undispositioned finding
   blocks the anchor. Record table and dispositions in the section the
   sign-off record will close.
2. **The refusal rule (REQ-F1.10).** A meaning-class sign-off whose lens
   pass is absent, or whose findings are not all dispositioned, refuses to
   record an execution-valid anchor: say exactly what is missing, leave
   the record without its anchor line (the freshness gate treats that as
   absent-anchor and halts dispatch — fail closed), and stop. There is no
   override.
3. **Status flip and `Last reviewed:`.** First activation (and a
   reopened-bundle delta kickoff): flip
   `**Status:**` Draft→Ready and `**Last reviewed:**` to today on all
   four spec files (REQ-D1.1, REQ-A1.4 — this stored, human-gated flip is the
   only stored status transition; Ready↔Active is *derived* from task state by
   the single reconcile writer, REQ-A1.5, and is never written by this skill).
   Re-walkthroughs and amendments on an already-signed bundle (Ready or
   Active): bump `Last reviewed:` on the files the delta touched, with no
   status flip. Then, when the validator is present, re-run it (Ready, Active,
   and Done all block on errors): errors now block — fix them with the human, or
   halt without recording the sign-off entry (on a first activation or reopen,
   also revert the flip so the bundle does not sit Ready and erroring; on an
   already-signed spec there is no flip to revert, and the stale anchor keeps
   dispatch blocked). Never sign off over an erroring bundle. Validator absent
   (the pre-flight consent path — re-ask on a resumed session that never saw
   pre-flight step 3): record "signed off unvalidated (validator absent,
   human-consented)"
   in the sign-off section, adding "including the Draft→Ready flip" only when
   this run actually flipped, so the degradation is auditable rather than
   silent.
4. **The sign-off record** (record format, sanctioned anchor command
   forms, and writers rule per `spec-format`'s *Sign-off records and content
   anchors*; REQ-F1.10). Write it into the brief's sign-off section (first
   activation) or as an appended amendment-log entry (everything later) —
   sections above the amendment log are append-only after first sign-off.
   Carry `Class:`, `Lens-pass:` (meaning-class only), and **the anchor line
   last**, after everything else in the entry (the fail-closed ordering).
   Compute the anchor with `scripts/spec-anchor.sh specs/<spec>` after every
   spec-file edit of this run (flip, `Last reviewed:`, applied findings) is on
   disk; it fails closed on a defective bundle — surface its stderr and stop
   with no anchor line, never hand-roll it, and reach for the sanctioned
   interim whole-file form only when the script is absent (recording that
   exact command so recomputation stays deterministic). This flow is the only
   writer of a meaning-class entry; it writes an expression-only entry (no
   lens pass, citing the changelog line) only when the human classified the
   entire delta expression-only.
5. **Commit** (D-41) when `commit_on_kickoff` is true: one commit on
   `planwright/<spec>/spec` with the brief, the four spec files, and any
   observation fragment that rode this run — first activation `feat(spec):
   <spec> kickoff, brief + Ready flip`; later events `docs(spec): <spec>
   <event>` (e.g. `delta re-walkthrough`, `amendment`), the same shapes the PR
   titles below use. New commits only — never force-push, amend, squash, or
   rebase (REQ-J1.4). Opt-out: leave the work uncommitted, say so, and skip
   push/PR (an unpushed commit is recoverable; pushing uncommitted state is
   not).
6. **Push and draft PR** (REQ-B2.4, D-44). Publishing is the run's last
   commit-producing action (step 7's ready-flip issues no commit): run the
   Observations and Maintenance steps below first, so their chore commits land
   before the push and nothing is left unpushed. Then push the spec branch:
   `git push -u origin planwright/<spec>/spec`. Then the PR: if one already
   exists for the branch, update its body; otherwise `gh pr create --draft`
   with explicit `--title` and `--body`. The title must pass the project's
   conventional PR-title lint (`scripts/check-commit-msgs.sh`, enforced on PR
   titles in CI at 100 chars): `feat(spec): <spec> kickoff sign-off` for a
   first activation, `docs(spec): <spec> <event>` for later events. The body
   carries the spec path, brief path, walkthrough scope (full or delta),
   validator outcome, lens-pass summary, and the anchor. The PR is created as a
   draft; step 7 un-drafts it on a clean completion, while merge stays the
   human's. On no remote, push rejection, or `gh` absence/auth failure: degrade
   per REQ-K1.6/K1.7 — the local work is complete and committed; record a note
   in the spec's `tasks.md` `## Awaiting input` section naming the pending
   push/PR step and the failure, surface it in the handoff, and stop. Never
   retry into an opaque failure.
7. **Mark the spec PR ready (terminal step, D-6/D-7; REQ-D1.2, REQ-D1.3,
   REQ-D1.5).** The run's final action, only on a **clean completion** — the
   sign-off record above is written with its anchor (no inconsistency halt, no
   carried open question, every lens finding dispositioned) and any configured
   verification has converged. That verification (a user may informally call it
   a "gauntlet") is the configurable `review_sequence`-class mechanism (D-7,
   customization-overlay D-6 / REQ-D1.3), **not a hardcoded** core step: in
   bare core it is this skill's own walkthrough and Discovery-Rigor lens pass
   (already complete above); an overlay may run an additional review pass over
   the spec PR whose terminal step is this flip. When
   `mark_spec_pr_ready_on_kickoff` is true (pre-flight step 4) and the
   completion is clean, un-draft the spec PR — but **first check its state**
   (`gh pr view <spec-PR> --json isDraft,state`) and run `gh pr ready
   <spec-PR>` **only while it is still a draft**; skip it entirely when the PR
   is already ready or merged/closed (a benign no-op, not a degradation — the
   skip is what keeps it from being one; `gh pr ready` there exits non-zero and
   would wrongly trip the degradation path). This is the narrow exception to
   bootstrap D-26's all-drafts rule: **only the spec PR**, and only this skill,
   marks a PR ready; **task PRs stay drafts** (their execution review is owned
   by the execution and review skills). Merge stays the human's second key —
   **never auto-merge**.
   - **Do not flip** when sign-off parked on a fork (an inconsistency halt, a
     carried open question, an undispositioned finding) or the configured
     verification did not converge: leave the PR draft and say so in the
     handoff.
   - **Opt-out:** `mark_spec_pr_ready_on_kickoff: false` suppresses the flip;
     the PR stays draft and the human un-drafts it by hand.
   - **Degrade, never retry into opacity (bootstrap REQ-K1.6/K1.7):** if the
     flip itself fails — no remote, `gh` absent or auth failure, PR not
     found — the recorded sign-off stands (never roll it back); record the
     pending ready-flip in the spec's `tasks.md` `## Awaiting input` section
     naming the failure, surface it in the handoff, and stop.

**Hand off.** Report: mode and scope, sections walked, spec edits applied,
gap-check outcome, lens-pass summary, the anchor, commit/push/PR outcome
(or the degradation notes), the spec PR's ready/draft state (and the opt-out
or degradation reason when it stayed draft), and the next step — merge the
spec PR (now ready), then `/orchestrate specs/<spec>`.

**Data hygiene throughout (`security-posture`):** the brief, risk register, and
PR body are committed artifacts — no secrets, credentials, internal hostnames,
or sensitive operational detail; neutralize what walkthrough discussion
surfaces before it is written.

## Observations

When anything outside this kickoff's scope surfaces during the walk
(doctrine gaps, tooling gaps, recurring friction, an uncatalogued decision
domain), record one fragment per item through the shared helper —
`scripts/obs-record.sh --slug <topic> --scope <repo> --text '<observation>'`
(resolved under the planwright root; it composes the one-line entry form
and writes one file under the host repo's `specs/_observations/entries/`) —
and commit the fragment (with the sign-off commit, or as its own chore
commit); surface a non-zero helper exit rather than silently dropping the
observation. Do not act on observations during the kickoff; they are seed
material for `/spec-draft`, the accumulator's canonical reader.

## Maintenance

Before the push step on a run that reaches sign-off (so the chore commit
lands pushed), or at the halt point otherwise, compare these instructions
against the
resolved doctrine docs listed above (REQ-B3.2, D-42) — especially
`spec-format` (brief structure, sign-off record format, sanctioned anchor
command forms, amendment ritual) and `decision-domains` (lifecycle wiring).
If a concept this skill names has changed meaning, gained or lost a step,
or moved between docs, record a drift observation through the shared helper
(`scripts/obs-record.sh --slug skill-drift --scope <repo> --text
'skill-drift(spec-kickoff): <what>'` — the entry text keeps the
`skill-drift(...)` prefix; in repositories without `specs/`, surface the
drift to the user instead of recording it), commit the fragment as its own
chore commit, and tell the user what drifted; surface a non-zero helper
exit rather than silently dropping the observation. Do not edit this skill
or the doctrine docs to resolve the drift; the accumulator's canonical
reader (`/spec-draft`) owns folding drift into spec amendments.
