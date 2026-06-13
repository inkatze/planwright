---
name: spec-kickoff
description: >
  Walk a spec bundle section by section to mutual understanding, producing
  the signed-off kickoff brief that downstream skills execute from. On
  sign-off: runs the Discovery-Rigor lens pass, flips Draft to Active,
  updates Last reviewed, records the machine-checkable sign-off record with
  the content anchor written last, commits brief + flip (commit_on_kickoff
  opt-out), pushes the spec branch, and opens a draft PR. The human's merge
  activates the spec. Also runs delta re-walkthroughs and amendments on
  Active specs. Halts on genuine spec inconsistency rather than papering
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
Draft→Active, and the human's merge of the spec PR makes the Active spec
operational. This skill never marks the PR ready, never merges, and never
dispatches execution.

## Doctrine

This skill is procedure, not doctrine. Resolve and read these rule docs at
run start via the rule-doc resolution convention
(`scripts/resolve-rule-doc.sh <doc-name>` under the resolved planwright
root, or the documented `PLANWRIGHT_ROOT`/`CLAUDE_PLUGIN_ROOT` chain); their
definitions govern wherever this skill names a concept:

- `spec-format` — the meta-spec: bundle conventions, status lifecycle, the
  required kickoff-brief structure, the amendment ritual, sign-off records,
  content anchors, and the sanctioned anchor command forms. This skill is
  the writer the meta-spec's sign-off rules name; it follows them exactly.
- `discovery-rigor` — the lens checklist, canonical lens-coverage table,
  fan-out, and self-critique pass behind the sign-off lens review.
- `validation-rigor` — validation of lens-pass findings before they are
  dispositioned.
- `security-posture` — artifact data-hygiene: the brief is a committed
  artifact and its risk register invites operational detail.

If any of those four does not resolve, halt with a clear message naming the
missing doc and the chain consulted (REQ-K1.7: the clear message is the
graceful arm; signing a contract without the rules that define it is the
opaque failure). Two more resolve with graceful degradation instead:

- `decision-domains` — the gap check's catalog. Absent: note the missing
  catalog in one line, skip the gap check, and record the skip in the brief
  so the gap is visible (the catalog is a deliberate non-edge, not a
  dependency).
- `interaction-style` — governs the exchanges in the flow. Absent: follow
  the summary inline here (progress indicator, small bites, selectors with
  a recommendation, running summary) and note the missing doc.

## Modes

Three modes, selected at pre-flight from the spec's status and the brief's
state:

- **First activation.** Status Draft, no signed brief (or a partial one —
  see resumability). The full walkthrough below, ending in the first
  sign-off, the Active flip, push, and draft PR.
- **Delta re-walkthrough.** Status Active with a signed brief, and the
  freshness comparison in pre-flight step 2 found the spec content changed
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

A **reopened bundle** (Status Draft with a complete signed brief — the
REQ-A3.1 reopen cycle, entered when `/spec-draft --extend` flips a Done
spec back to Draft) is a scoped kickoff of the delta, not a first
activation: walk the extension delta in the delta re-walkthrough shape,
and the sign-off flips Draft→Active again. A Done spec has nothing to
kick off regardless of stray edits: say so and point at
`/spec-draft --extend` (the reopen path above). Retired and Superseded
are terminal: refuse — no skill-driven transition leaves a terminal
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
   at `/spec-draft`; there is nothing to walk. Read the `**Status:**` line:
   - **Draft** → first activation; a resume when step 6 finds a partial
     brief; a reopened-bundle delta kickoff when the brief is complete
     and signed (per the Modes section).
   - **Active with a signed brief** → run the freshness comparison: parse
     the brief's most recent anchor entry, recompute the anchor with the
     exact command that entry records, and compare. **Mismatch** → delta
     re-walkthrough; derive the delta from the git history of the four
     spec files since the entry was recorded plus any uncommitted changes,
     and confirm that scope with the human before walking. **Match** →
     nothing is stale; ask what the human is bringing (a re-walk on
     request, or an amendment — amendment mode is always human-declared).
     **Brief or anchor entry absent, unparseable, or non-sanctioned**
     (including a hand-flipped Active spec that never had a kickoff) → the
     sign-off record needs creating or repairing, and this skill's
     sign-off flow is the repair REQ-F1.9 names: walk it as a delta
     re-walkthrough scoped to the whole bundle (a missing brief gets the
     full structure, first-activation shape, minus the already-done
     Active flip).
   - **Done / Retired / Superseded** → per the Modes section.
3. **Run the validator.** `scripts/spec-validate.sh specs/<spec>` when
   present and executable. On a Draft bundle findings are warnings: surface
   them, fix structural ones with the human before walking (a walkthrough
   over a malformed bundle wastes the human's attention), and record the
   outcome for the brief header. Validator absent or not executable:
   kickoff is an authoring path, so this degrades rather than halts
   (REQ-K1.7) — but the flip to Active is what arms execution, so say
   plainly that the bundle will go Active unvalidated and ask the human
   whether to proceed or install the validator first.
4. **Read the config.** `commit_on_kickoff` from `config/defaults.yml`
   overridden by `<repo>/.claude/planwright.local.yml` (local wins).
   Default `true`; an absent, unreadable, or malformed config file falls
   back to the default with a one-line warning surfaced now and repeated in
   the handoff.
5. **Resolve the working location** (D-44, graceful in every starting
   state). The spec branch is `planwright/<spec>/spec` (the reserved
   namespace the `tasks-pr-sync` hook no-ops on); the spec worktree is
   `<repo>/.claude/worktrees/<spec>-spec` (D-37 placement — the directory
   name disambiguates the literal branch suffix `spec`, which would collide
   across specs, while staying attachable via
   `claude --worktree <spec>-spec`).
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
   classify it: per-section `Signed off:` lines present but no final
   sign-off record with an anchor → a killed or interrupted session left a
   resumable partial brief. Present the running summary of every signed
   section, confirm it still stands, and resume at the first unsigned
   section — signed sections are not re-walked unless the human asks. A
   brief whose final record exists but lacks its anchor line is the same
   case (the anchor-written-last ordering makes a killed session
   indistinguishable from absent-anchor, by design): resume at the
   sign-off step.

## The walkthrough

Section by section, in the brief's required structure (the `spec-format`
doc defines it; the brief is written incrementally, one section to disk as
it is signed). The walkthrough covers components 1–7 of that structure;
the remaining two — the sign-off section and the amendment log — are
written by the sign-off flow below, not walked. Every exchange follows the interaction-style rules: show
the progress indicator (`[section <n>/7]`), work in small bites, present
decisions as selectors with a recommendation, end each section with the
running summary of everything decided so far. Each section ends with an
explicit `Signed off: <date>` line — that line is what resumability keys
on.

1. **Header block.** Spec path, spec commit at walkthrough start,
   walkthrough date, validator outcome from pre-flight. Written first, no
   sign-off needed.
2. **Goal & glossary.** Restate the goal in the agent's own words — a
   restatement, not a summary: what the spec is for, what it rules out,
   what it assumes. Surface implicit terms (vocabulary the spec uses but
   never defines) and record resolutions to every ambiguity the
   restatement exposes. This section anchors every later judgment call.
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
6. **Task graph.** Reconstruct the dependency graph from the
   `Dependencies:` lines (they are authoritative; any diagram is derived),
   identify parallelism and the effort-weighted critical path, and record
   deliberate non-edges so nobody "fixes" them later.
7. **Risk register.** Numbered rows of risk + mitigation / early signal.
   Inputs: risks surfaced during the walk, the human's cold-review
   questions, and the **decision-domains gap check** — walk the catalog's
   entries against the spec; any catalogued domain the spec touches but
   never decides becomes a risk-register row naming the domain and the
   undecided question (REQ-G1.4, D-39). Catalog absent: record the
   one-line skip here instead. Open questions must end the section
   resolved to decisions or recorded as explicit accepted risks; an open
   question is not a sign-off.

**Spec edits during the walkthrough.** A Draft bundle is unsigned: edits
land in place, applied with the human section by section, and the
consolidated edit list is recorded in the brief. On an Active bundle the
amendment ritual governs (REQ-A3.3, `spec-format`): pre-merge corrections
on the spec's own PR amend in place with a changelog entry and a recorded
re-sign-off; post-merge meaning changes supersede (new ID, old marked
`Superseded-by`); expression-only fixes take a dated changelog entry.

**The inconsistency halt (REQ-B2.3).** A genuine spec inconsistency — two
requirements that contradict, a design decision that contradicts a
requirement, a Done-when no deliverable can satisfy — halts the
walkthrough rather than being papered over. Present the contradiction with
both readings and the smallest edit that would resolve each way. The human
resolves by **editing the spec** (the affected sections re-walk) or by
**recording an explicit override in the brief** (the contradiction stands,
named, with the chosen reading and rationale). Until one happens there is
no sign-off, no Active flip, and no anchor entry: the run ends with the
partial brief on disk and the halt reason stated. Fail closed, not
helpful.

## Sign-off

Sign-off runs only when every section above is signed and no inconsistency
is open. Its steps are ordered so that a session killed at any point fails
closed: the most recent anchor entry never describes spec content that was
not walked.

1. **The lens review pass.** A Discovery-Rigor review of the bundle —
   the spec is the artifact under review, and spec bugs (a silent
   clean-no-op, a fixture encoding the spec's own wrong belief) are
   invisible to execution feedback, so this pass is the last line of
   defense (D-45). Scope: the **full bundle at first activation**,
   **delta-scoped at re-walkthroughs and amendments**, **skipped entirely
   for expression-only changes** (REQ-A3.3). Fan out one read-only
   sub-agent per canonical lens for any non-trivial delta per the
   `discovery-rigor` doc; walk inline only for small, narrow deltas, and
   declare which path was taken. Emit the canonical lens-coverage table.
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
3. **Status flip and `Last reviewed:`.** First activation: flip
   `**Status:**` Draft→Active and `**Last reviewed:**` to today on all
   four spec files. Re-walkthroughs and amendments: bump `Last reviewed:`
   on the files the delta touched. Then re-run the validator under Active
   enforcement: errors now block — fix them with the human, or halt
   without recording the sign-off entry (on a first activation or reopen,
   also revert the flip so the bundle does not sit Active and erroring;
   on an already-Active spec there is no flip to revert, and the stale
   anchor keeps dispatch blocked). Never sign off over an erroring Active
   bundle.
4. **The sign-off record** (format per `spec-format`; REQ-F1.10). Write
   the record into the brief's sign-off section (first activation) or as
   an appended amendment-log entry (everything later) — sections above the
   amendment log are append-only after first sign-off. The record carries
   `Class:` (`meaning` or `expression-only`, the human classifies;
   additions count as meaning), `Lens-pass:` (meaning-class only — the
   reference to the dispositioned pass recorded in the same section), and
   **the anchor line last**, after everything else in the entry:

   ```markdown
   Class: meaning
   Lens-pass: recorded above (this section), findings dispositioned <date>.
   Anchor: `<hash>` — computed as
   `scripts/spec-anchor.sh specs/<spec>`
   ```

   Compute the anchor with the canonical sanctioned command,
   `scripts/spec-anchor.sh specs/<spec>`, after every spec-file edit of
   this run (flip, `Last reviewed:`, applied findings) is on disk. The
   script fails closed (non-zero exit, no anchor printed) on a defective
   bundle: surface its stderr and stop without an anchor line — never
   substitute a hand-rolled computation, and never reach for the interim
   whole-file form when the script is present. Meaning-class anchor
   entries are written by this sign-off flow and nowhere else; this skill
   writes an expression-only entry (no lens pass, citing the changelog
   line) only when the human classified the entire delta expression-only.
5. **Commit** (D-41) when `commit_on_kickoff` is true: one commit on
   `planwright/<spec>/spec` containing the brief and the four spec files —
   first activation: `feat(spec): kickoff specs/<spec>, brief + Active
   flip`; later events: `docs(spec): <event> specs/<spec>` (e.g.
   `delta re-walkthrough`, `amendment`). New commits only — never
   force-push, amend, squash, or rebase (REQ-J1.4). Opt-out set: leave the
   work uncommitted, say so explicitly, and skip push/PR (an unpushed
   commit is recoverable; pushing uncommitted state is not a thing).
6. **Push and draft PR** (REQ-B2.4, D-44). Push the spec branch:
   `git push -u origin planwright/<spec>/spec`. Then the PR: if one
   already exists for the branch, update its body; otherwise
   `gh pr create --draft` with explicit `--title` and `--body`. The title
   must pass the project's conventional PR-title lint
   (`scripts/check-commit-msgs.sh`, enforced on PR titles in CI at 100
   chars): `feat(spec): <spec> kickoff sign-off` for a first activation,
   `docs(spec): <spec> <event>` for later events. The body carries the spec
   path, brief path, walkthrough scope (full or delta), validator outcome,
   lens-pass summary, and the anchor. The PR is always a draft; the
   draft→ready flip and the merge are the human's (the second key — merge
   is what makes the Active spec operational for orchestration). On no
   remote, push rejection, or `gh` absence/auth failure: degrade per
   REQ-K1.6/K1.7 — the local work is complete and committed; record a note
   in the spec's `tasks.md` `## Awaiting input` section naming the pending
   push/PR step and the failure, surface it in the handoff, and stop.
   Never retry into an opaque failure.

**Hand off.** Report: mode and scope, sections walked, spec edits applied,
gap-check outcome, lens-pass summary, the anchor, commit/push/PR outcome
(or the degradation notes), and the next step — merge the spec PR, then
`/orchestrate specs/<spec>`.

**Data hygiene throughout (security-posture):** the brief, the risk
register, and the PR body are committed artifacts — no secrets,
credentials, internal hostnames, or sensitive operational detail in any of
them; neutralize what walkthrough discussion surfaces before it is
written.

## Observations

When anything outside this kickoff's scope surfaces during the walk
(doctrine gaps, tooling gaps, recurring friction, an uncatalogued decision
domain), append one line per item to
`specs/_observations/opportunities.md` — format
`- <YYYY-MM-DD> [<repo>] <observation>` — and commit the append (with the
sign-off commit, or as its own chore commit). Do not act on observations
during the kickoff; they are seed material for `/spec-draft`, the log's
canonical reader.

## Maintenance

After the run completes (or halts), compare these instructions against the
resolved doctrine docs listed above (REQ-B3.2, D-42) — especially
`spec-format` (brief structure, sign-off record format, sanctioned anchor
command forms, amendment ritual) and `decision-domains` (lifecycle wiring).
If a concept this skill names has changed meaning, gained or lost a step,
or moved between docs, append a drift observation to
`specs/_observations/opportunities.md` (format above, prefixed
`skill-drift(spec-kickoff):`; in repositories without `specs/`, surface
the drift to the user instead of writing the log), commit the append as
its own chore commit, and tell the user what drifted. Do not edit this
skill or the doctrine docs to resolve the drift; the observation log's
reader owns folding drift into spec amendments.
