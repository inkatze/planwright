# Prose disposition — Requirements

**Status:** Draft
**Last reviewed:** 2026-09-03
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

Prose is expensive in planwright's pipeline, and not because it costs
tokens once at write time. Three doctrine rules compose into a work
multiplier: the Documentation lens in `doctrine/discovery-rigor.md` names a
surface (docstrings, READMEs, specs, doctrine) and attaches no defect class,
so any prose that could be sharper becomes a finding; the categorization in
`doctrine/finding-categorization.md` routes "any external contract" change
to Needs sign-off, and agents read doctrine wording as a contract; the
commit discipline in `doctrine/gate-wiring.md` lands one Needs-sign-off
finding per commit, never batched. Composed, one wording nit becomes one
commit, one checklist entry, and one human sign-off decision. Measured on
tower-front-door Task 1: 42 insertions and 24 deletions of doctrine prose
became 30 commits and a 30-item sign-off queue across two review passes
(obs:0d6a3ed8, the tower-front-door Task 1 PR in Sources). Source comments
are the largest such surface: `scripts/*.sh` carries 20,807 comment lines
against 33,843 code lines, 30 percent of them in 138 blocks of 25 lines or
more, and the mass is neither restatement nor junk: 132 of those 138 blocks
cite a spec, 109 also carry rationale, and 2 of 2,526 blocks duplicate
spec or doctrine prose (obs:a81cee76). Every such block is an untested
assertion about behaviour that the rigor lenses will keep reconciling with
the code, forever, at a commit and a sign-off decision each.

This bundle fixes the disposition machinery first, then bounds the surface,
then cleans it under the new rules. The doctrine amendments scope the
Documentation lens to a defect class, classify prose findings on the
meta-spec's existing expression-only versus meaning-class axis so wording
that changes no rule applies without a sign-off entry, treat a prose surface
the PR itself introduces as internal until it merges, and permit batching
the meaning-class prose that remains. A comment-block budget guard modelled
on the instruction-budget guard bounds the largest contiguous comment block
per file. A two-phase cleanup then disposes of every block under a
five-reason taxonomy, with a verification method that confirms only
comments that earn their place remain. The ordering is load-bearing: a
cleanup before the disposition fix would generate roughly a thousand
sign-off entries under today's rules. The deliverable's altitude, doctrine
first with the guard as a core capability and the cleanup as repo-local
work, is recorded in D-1 and cited here from the goal.
*(Cites: D-1, D-13, obs:a81cee76, obs:0d6a3ed8, the issue correction (Sources).)*

## Scope

### In scope

- Scoping the code lens set's Documentation lens to named defect classes
  and stating, across every lens set, that merely improvable prose is not a
  finding.
- Classifying prose findings on the meta-spec's expression-only versus
  meaning-class axis: expression-only prose is Auto-applicable with a
  recorded normative-preservation check or a prose-guard rule as its
  grounding; meaning-class prose keeps its Needs-sign-off route.
- The PR-introduced-surface rule: a prose file the PR creates carries no
  external contract until it merges.
- Batching meaning-class prose findings into one commit and one checklist
  entry per loop iteration with a manifest, reserving one commit per finding
  for fixes that change code behaviour.
- Instantiating the amended rules in `/self-review`, `/polish`, and
  `/execute-task`'s convergence prose, with a surface-pattern straggler
  sweep across skills, doctrine, and docs.
- A comment-hygiene rule doc: what a comment is for, the no-provenance rule
  and where the script-to-spec link lives instead, the five-reason
  disposition taxonomy, and the comment-block budget model.
- The comment-block budget guard: the measurement, its knobs, its
  suppression list with permanent and transitional forms, its audit and
  code-invariance modes, its tests, and its wiring into the aggregate check
  and the pre-commit mirror.
- The comprehensive cleanup of planwright's own `#`-commented surfaces in
  two phases, evidence-free blocks by rule and the large evidenced headers
  by reading, with the verification method as a deliverable: reproducible
  measurement, mechanical code-invariance, and an independent reading pass
  recorded in each cleanup PR.
- Closing the deliverables gap for the scripts reachable through neither a
  commit trailer nor an owning bundle's deliverables, in the bundles that
  own them.

### Out of scope

- Relocating the sign-off marker to a commit trailer and moving the approval
  act to the merge (planwright issue #384). This bundle names the marker
  abstractly and records the sequencing risk with that work in D-5; it does
  not change the carrier or the approval semantics.
- Lifecycle states and operator hooks (planwright issue #383) and the
  ownership of checklist regeneration when `/polish --nested` runs with no
  invoking skill (obs:ff5ca260). Evidence only.
- The release-proposal drop (planwright issue #380) and the 529 result-frame
  mislabel (obs:05313aff): cited as prose-versus-code drift evidence for the
  defect class, remedied elsewhere.
- Prose inside spec bundles and doctrine bodies as a budgeted surface. Their
  size is `doctrine/instruction-hygiene.md`'s concern and their drift is the
  anchor and kickoff machinery's; this bundle changes how findings about
  them are dispositioned, not their budgets.
- JSON `_about` strings in the settings fragments (obs:b75dc6d2), the
  skill-versus-doctrine restatement detector (obs:ff8f7659), and the
  directive-density metric (obs:79a5adbc): adjacent prose surfaces that are
  not `#` comments and are not covered by this guard.
- Changing the four-bucket taxonomy itself. No fifth bucket is minted; prose
  is classified inside the existing buckets.
- The operator's personal copies of the rigor sections outside this
  repository. Those copies are the operator's to align; this bundle changes
  planwright's doctrine, which its skills resolve plugin-relative.
- Adopter-facing enrollment of the comment guard in the builder's guard
  catalog: deferred in `tasks.md` behind evidence that the budget generalizes.

## REQ-A — Documentation lens defect class

- **REQ-A1.1** The code lens set's Documentation lens in
  `doctrine/discovery-rigor.md` SHALL name the defect classes it flags: prose
  the change falsifies or leaves stale (a claim about behaviour, a value, or
  an enumeration the diff contradicts); documentation missing for behaviour
  or a contract the change introduces (a config knob without its reference
  row, a flag without usage text, a new script without its purpose stated);
  and a violation reported by a documentation guard the project ships.
  *(Cites: D-2, obs:a81cee76, obs:0d6a3ed8.)*
- **REQ-A1.2** Across every lens set in `doctrine/artifact-lenses.md`, prose
  that is merely improvable (phrasing, emphasis, or a precision preference)
  with no falsifying code, no contradicting sibling statement, and no reader
  who would act differently on it SHALL NOT be a finding, and every
  documentation finding SHALL name which defect class it belongs to.
  *(Cites: D-2, artifact-lenses (Sources).)*
- **REQ-A1.3** The lens-coverage table row for the Documentation lens SHALL
  carry the defect class of each finding it counts, so a pass that produced
  only preference findings is visible as a scoping violation rather than as
  coverage.
  *(Cites: D-2.)*

## REQ-B — Prose finding classification

- **REQ-B1.1** A validated finding whose fix edits only prose (comments,
  documentation, doctrine, skill instructions, or configuration commentary)
  SHALL be classed on the meta-spec's amendment axis: expression-only when no
  normative statement changes meaning (no MUST, SHALL, SHALL NOT, or MAY, no
  threshold, enumerated value, or interface fact is added, removed, or
  altered), meaning-class otherwise.
  *(Cites: D-3, spec-format (Sources).)*
- **REQ-B1.2** An expression-only prose fix SHALL satisfy the Auto-applicable
  tool-grounding condition in one of two ways: a rule reported by a prose
  guard the project ships (the doctrine index and link checks, the
  instruction budget, markdown lint, a gloss or pin check, the comment-block
  guard), or a recorded normative-preservation check listing the normative
  statements of the edited passage before and after and showing them
  identical, performed as `doctrine/validation-rigor.md`'s non-testable
  substitute. The audit row SHALL carry the grounding used.
  *(Cites: D-3, obs:0d6a3ed8.)*
- **REQ-B1.3** The "any external contract" clause in the Auto-applicable and
  Needs-sign-off predicates SHALL be defined for prose as a normative rule a
  reader outside the PR relies on; wording that changes no such rule is not an
  external-contract change and SHALL NOT route to Needs sign-off on that
  clause alone.
  *(Cites: D-3.)*
- **REQ-B1.4** The prose of a file the PR itself introduces (a
  documentation, doctrine, or skill file absent from the PR's base, whole;
  the comments of a new code file) SHALL carry no external contract until
  the PR merges: review-loop edits to that prose are internal, applied and
  batched with the iteration's action commit, and reviewed as part of the
  new content in the PR diff. The code of a new file keeps the existing
  routes.
  *(Cites: D-4, the tower-front-door Task 1 PR (Sources).)*
- **REQ-B1.5** A meaning-class prose fix to a surface that existed before
  the PR SHALL keep its Needs-sign-off route, and when that surface is a
  signed spec bundle SHALL be refused to a `/spec-kickoff` delta
  re-walkthrough per the meta-spec's writer obligations.
  *(Cites: D-3, spec-format (Sources).)*

## REQ-C — Commit discipline for prose

- **REQ-C1.1** Needs-sign-off fixes that edit only prose SHALL batch into one
  commit per loop iteration whose body carries a manifest: one line per fix
  naming the file, the rule as it read before, and the rule as it reads
  after. The pending-sign-off marker, in whatever carrier
  `doctrine/gate-wiring.md` defines at the time, is stamped once on the
  batch.
  *(Cites: D-5.)*
- **REQ-C1.2** The pending-sign-off checklist SHALL render a batched commit
  as one entry with one sub-item per manifest line, carrying the batch's
  revert command and stating that rejecting a single sub-item is a hand edit
  guided by the manifest.
  *(Cites: D-5.)*
- **REQ-C1.3** One commit per finding SHALL remain the rule for any
  Needs-sign-off fix that changes code behaviour, so a targeted revert stays
  available exactly where it matters.
  *(Cites: D-5.)*
- **REQ-C1.4** The Needs-sign-off audit table SHALL keep one row per finding
  for a batched commit, rows sharing the commit and the checklist id, so the
  audit record's per-finding granularity is unchanged by batching.
  *(Cites: D-5.)*

## REQ-D — Skill instantiation

- **REQ-D1.1** `/self-review`, `/polish`, and `/execute-task`'s convergence
  prose SHALL instantiate the amended lens scoping, prose classification,
  PR-introduced-surface rule, and commit discipline by citing the governing
  doctrine sections, restating at most the one-line gist each step needs.
  *(Cites: D-6, obs:8fa65f3f, instruction-hygiene (Sources).)*
- **REQ-D1.2** Landing the doctrine amendments SHALL include a
  surface-pattern sweep over `skills/`, `doctrine/`, and `docs/` for the
  superseded wording (the unbatched one-commit-per-finding rule, the
  unscoped Documentation lens phrasing), with every straggler updated in the
  same change, per `doctrine/validation-rigor.md`'s contract-reword rule.
  *(Cites: D-6, obs:8fa65f3f.)*
- **REQ-D1.3** The instruction-budget guard SHALL pass after the amendments
  with no new raise entry; a warn-threshold crossing on an amended rule doc
  is answered by the restoration ladder's diet rung within the same change.
  *(Cites: D-6, instruction-hygiene (Sources).)*

## REQ-E — Comment hygiene doctrine

- **REQ-E1.1** A rule doc `doctrine/comment-hygiene.md` SHALL state what a
  comment is for: it earns its place only when the code cannot carry the
  information (a non-obvious why, a constraint invisible at that spot, a
  contract a caller depends on, a warning against a plausible wrong edit),
  and it never restates what the code does, never narrates structure, and
  never records provenance (spec, requirement, decision, and task
  identifiers, PR links, review history), which belongs in the commit
  message and the spec files.
  *(Cites: D-7, D-14, the operator's comment-discipline rule (Sources).)*
- **REQ-E1.2** The doc SHALL state the five-reason disposition taxonomy for
  existing comment text and the destination each reason implies: the why of
  this code stays beside the code it explains; an own-surface contract stays
  as the file's bounded usage section; a cross-file protocol moves to the
  doctrine or design page that owns it, with a one-line pointer left behind;
  restatement and history are deleted; a warning against a wrong edit stays
  beside the code it guards.
  *(Cites: D-8, drafting-session decision (2026-09-03).)*
- **REQ-E1.3** The doc SHALL state the comment-block budget model: the unit
  is the largest contiguous comment block per file, thresholds are in lines
  and boundary-inclusive, the knobs are overlay-tunable core configuration,
  and two suppression forms exist, each requiring a recorded reason.
  *(Cites: D-9.)*
- **REQ-E1.4** The doc SHALL be enrolled in the doctrine index and cited by
  the guard's header as its normative home, and the guard's own header SHALL
  stay within the budget the guard enforces.
  *(Cites: D-7, obs:a3c3d55b.)*
- **REQ-E1.5** The provenance rule SHALL name where the script-to-spec link
  lives instead of the comment: the commit's task trailer and the owning
  bundle's task deliverables. A script reachable through neither is a
  deliverables gap to close in the owning bundle, never a citation to add to
  the script.
  *(Cites: D-14, drafting-session decision (2026-09-03).)*

## REQ-F — Comment-block budget guard

- **REQ-F1.1** `scripts/check-comment-budget.sh` SHALL measure, for every
  file in its surface, the largest contiguous run of comment lines, where a
  comment line is optional leading whitespace followed by `#` excluding the
  shebang, and a blank line or a code line ends the run, and SHALL compare
  that length against the `comment_block_warn` and `comment_block_error`
  knobs with boundary-inclusive comparison, reporting a warning or an error
  per offending file with the block's starting line.
  *(Cites: D-9, D-10.)*
- **REQ-F1.2** The guard's surface SHALL be every tracked file whose comment
  syntax is `#` under `scripts/`, `tests/`, `githooks/`, `hooks/`, and
  `config/` (shell and YAML); the definition of a comment line SHALL be
  stated once in the guard's usage text with its known limit, that a heredoc
  body line beginning with `#` counts as a comment line, named honestly.
  *(Cites: D-10, obs:949b0ba3.)*
- **REQ-F1.3** The guard SHALL read `config/comment-budget-exemptions.txt`
  as data with two forms: `exempt|<path>|<reason>`, permanent with a standing
  reason, and `pending-cleanup|<path>|Task <N>|<reason>`, transitional,
  removed by that task's own PR and refused when `--closeout` is passed. A
  reason-less or malformed entry SHALL be an error; an entry whose file no
  longer trips any threshold SHALL be a named cleanup warning, never an
  error.
  *(Cites: D-9, D-11.)*
- **REQ-F1.4** The knobs SHALL live in `config/defaults.yml`, resolve through
  the four-layer configuration chain, be documented in the options reference
  under the existing coverage guard, and abort the guard fail-loud when
  missing or non-numeric.
  *(Cites: D-9.)*
- **REQ-F1.5** `--audit` SHALL emit the per-file inventory (block count,
  comment lines, code lines, the largest block and its starting line) ranked
  by largest block, plus corpus totals, and SHALL classify each block of two
  or more lines by its evidence (cites a spec, requirement, decision, or task
  identifier; carries rationale language; neither), with the patterns used
  stated in the usage text. Run against the `v0.36.0` tree, it SHALL
  reproduce the recorded 2026-09-03 headline figures in Sources.
  *(Cites: D-12, obs:a81cee76.)*
- **REQ-F1.6** `--code-invariant <ref>` SHALL compare, for every surface
  file changed between `<ref>` and the working tree, the sequence of
  non-comment lines, and SHALL exit non-zero naming any file whose
  non-comment content differs.
  *(Cites: D-12.)*
- **REQ-F1.7** The guard SHALL be wired as a `check:comment-budget` task
  inside `mise run check`, so the CI gate runs it, with `--closeout` passed by
  planwright's own task once the cleanup completes, and SHALL have a
  staged-path-scoped pre-commit mirror job with the same best-effort,
  CI-normative posture as the anchor-freshness job.
  *(Cites: D-9, D-11, anchor-integrity (Sources).)*
- **REQ-F1.8** Every input the guard reads (file contents, the suppression
  list, knob values) SHALL be treated as untrusted data: nothing is passed to
  a shell for evaluation, paths resolve inside the repository root, and
  content is sanitized before it is echoed, per `doctrine/security-posture.md`.
  *(Cites: D-9, security-posture (Sources).)*
- **REQ-F1.9** The guard SHALL ship with tests covering threshold arithmetic
  and boundary inclusivity, shebang exclusion, run-breaking on blank and code
  lines, the heredoc limit, every suppression form including malformed and
  stale entries, `--closeout`, `--audit` output shape, and
  `--code-invariant` on a changed and an unchanged file.
  *(Cites: D-9.)*
- **REQ-F1.10** The shipped defaults SHALL be a warn threshold of 12 lines
  and an error threshold of 25 lines, and the guard SHALL land with a
  generated `pending-cleanup` allowance for every file the error threshold
  catches at landing, each naming the cleanup task that removes it, so the
  aggregate check stays green from the day the guard lands.
  *(Cites: D-9, D-11, obs:a81cee76.)*

## REQ-G — Cleanup and verification

- **REQ-G1.1** No cleanup commit SHALL land before the doctrine amendments
  and the skill instantiation have merged; the cleanup tasks carry explicit
  dependency edges on them.
  *(Cites: D-13.)*
- **REQ-G1.2** Phase A SHALL disposition every evidence-free block (no
  rationale language and no spec citation, per the inventory's
  classification) under the taxonomy: deleted where the code carries the
  information, kept where it names a non-obvious why or a warning. Its PR
  SHALL carry the `--audit` figures before and after and the evidence-free
  count remaining.
  *(Cites: D-8, D-12.)*
- **REQ-G1.3** Phase B SHALL read every block at or above the error
  threshold and disposition it block by block under the taxonomy, remove
  provenance per REQ-E1.1, relocate cross-file protocol text to its owning
  doctrine doc or a design page with a pointer, keep own-surface usage
  sections bounded, and record an `exempt` entry with its reason for a
  genuinely long own-surface section with no other home.
  *(Cites: D-8, D-13, D-14.)*
- **REQ-G1.4** Every cleanup PR SHALL pass `--code-invariant` against its
  base, proving the change touched comments only, and SHALL pass the
  project's shell format and lint checks.
  *(Cites: D-12.)*
- **REQ-G1.5** Every Phase B PR SHALL carry an independent verification
  record: a second reading pass, from a fresh session or a non-Anthropic
  review backend, that confirms for each touched file that every removed
  line's information is recoverable from the code, the git history, or the
  named destination, and that every surviving block names its taxonomy
  reason; disagreements are dispositioned in the PR before merge.
  *(Cites: D-12, drafting-session decision (2026-09-03).)*
- **REQ-G1.6** The cleanup SHALL close the deliverables gap for every script
  reachable through neither a commit trailer nor an owning bundle's
  deliverables, by naming the script in its owning bundle's task deliverables
  as an expression-only amendment with the changelog entry and self-re-anchor
  the meta-spec requires.
  *(Cites: D-14, spec-format (Sources).)*
- **REQ-G1.7** The cleanup is complete when `check:comment-budget --closeout`
  passes with zero `pending-cleanup` entries, every remaining `exempt` entry
  carries its reason, and the final `--audit` figures are recorded in the
  closeout PR beside the 2026-09-03 baseline.
  *(Cites: D-12, D-13.)*

## Changelog

- 2026-09-03 — Initial draft: bundle elicited from the comment-volume
  measurement, the tower-front-door Task 1 sign-off record, and the issue
  correction that reframed the problem onto the disposition machinery; four
  forks resolved with the operator during drafting (provenance stripped with
  the deliverables gap closed at its source, the PR-introduced-surface rule
  for prose, per-iteration batching with a manifest, the five-reason
  disposition taxonomy).

## Sources

- **The drafting invocation** (2026-09-03, session-provided): the measured
  root cause, the three composing rules, the leverage-ordered candidate
  scope, and the operator requirement that the cleanup be comprehensive and
  confirmed, with the verification method part of the deliverable.
- **Pinned altitude seed claims** (from the invocation and the issue
  correction, per the autopilot-reflex seed-claim trigger): "the proposal
  targets the wrong layer"; "the comment is not the cost, being an entry
  point into the full disposition machinery is the cost"; "three doctrine
  rules compose into the actual multiplier"; "the ordering is load-bearing".
- **The operator's comment-discipline rule** (2026-09-03, the operator's
  global instructions, session-provided): a comment must earn its place;
  never restate, never narrate structure, never leave provenance in source.
- **The issue correction**: planwright issue #391 and its correction comment,
  which falsified the duplication and junk premises with the block
  inventory and named the three composing rules.
- **The tower-front-door Task 1 PR** (planwright PR #381): 30 marked commits
  on the branch, 30 checklist entries against 8 audit-table rows, every one
  editing a doctrine file the PR itself created; roughly two thirds changed
  what a rule said and one third were citations, glosses, or index rows.
- **The 2026-09-03 comment inventory** (session-provided; measured over the
  `v0.36.0` tree's `scripts/*.sh`, 128 files; reproducible through the
  guard's `--audit` once Task 4 lands): 2,526 blocks of two or more comment
  lines, 20,119 lines; 138 blocks at 25 lines or more holding 8,729 lines;
  1,422 evidence-free blocks holding 5,224 lines; 2 blocks duplicating spec
  or doctrine prose; the largest block 251 lines.
- **The script-to-spec link measurement** (2026-09-03 drafting session): of
  130 scripts, 67 are named in an owning bundle's tasks or design, 77 carry a
  task trailer somewhere in their history, 102 have at least one of the two,
  and 28 have neither.
- **obs:a81cee76** — comment volume manufactures review work: the
  measurement, the compounding mechanism, the check-instructions precedent.
  Consumed.
- **obs:0d6a3ed8** — every prose finding on tower-front-door Task 1 routed to
  Needs sign-off because both agent-owned buckets have code-shaped
  predicates. Consumed.
- **obs:a3c3d55b** — script headers are a large unbudgeted prose surface;
  the trimmable class is restatement of a rule whose home is elsewhere, the
  keep class is rationale and invariants. Consumed.
- **obs:949b0ba3** — a `defaults.yml` comment contradicted its own file for
  four tasks; no guard reads the prose around config keys. Consumed.
- **obs:8fa65f3f** — a doctrine reword left three skills carrying the old
  wording for a review cycle; nothing checks a restatement against the term
  it cites. Evidence for the straggler sweep.
- **obs:fb37c4bf** — implementation narrowing never propagated back to the
  REQ and decision that authorized it. Evidence for the defect class.
- **obs:c2afd203**, **obs:05313aff**, **obs:ff5ca260** — prose claiming a
  guarantee the code does not deliver (the release-proposal guard, the 529
  result frame, the fleet ledger doc). Evidence for the defect class; each
  remedied elsewhere.
- **obs:ff8f7659**, **obs:79a5adbc**, **obs:b75dc6d2** — adjacent prose
  surfaces (skill restatement, directive density, settings `_about` strings)
  named in Out of scope.
- **obs:2e9b7741**, **obs:77e452b4**, **obs:2bba6bcf** — the sign-off
  legibility, merge-as-approval, and trailer-carrier records that issue #384
  owns; this bundle's batching is written against them abstractly.
- **planwright issues #384, #383, #380** — the adjacent work named in Out of
  scope.
- **Prior bundles**: bootstrap (owner of the three amended doctrine docs and
  the four-bucket taxonomy), prompt-hygiene and instruction-headroom (the
  budget-guard shape, the suppression-list convention, the transitional
  allowance and closeout pattern), output-hygiene (the marker and PR-body
  contract), anchor-integrity (the pre-commit mirror posture), skill-rigor
  (the sibling-bundle-citing-bootstrap pattern this bundle follows).
- **Doctrine consulted**: `discovery-rigor`, `finding-categorization`,
  `gate-wiring`, `artifact-lenses`, `validation-rigor`, `spec-format` (the
  amendment axis and the writer obligations), `instruction-hygiene`,
  `security-posture`, `customization-boundary`, `autopilot-reflex`,
  `engineering-decisions`, `refactor-instinct`, `proportionality`.
