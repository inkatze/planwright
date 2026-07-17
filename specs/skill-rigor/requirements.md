# Skill rigor — Requirements

**Status:** Draft
**Last reviewed:** 2026-07-16
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright's own skills have drifted below their documented contracts in four
confirmed clusters: lifecycle and format-version-2 stragglers left behind by
invariant-tasks and kickoff-lifecycle (`/self-review` resolves its spec by a
stored-`Active` grep that misses every v2 bundle; `/orchestrate` documents
selection exits 0/1/2 while the shipped selector also exits 3); a sign-off
ritual that records claims it never re-derives and can mark the spec PR ready
while CI is red on the head SHA; a drafting skill with no self-critique over
its own freshly assembled output; and a doctrine resolver that cannot locate
core doctrine inside planwright's own checkout, worktrees, or dispatched
worker subshells. skill-rigor reconciles the skill surfaces with shipped
reality, hardens the sign-off and drafting rituals with mechanical
verification in place of trusted narrative, and makes rule-doc resolution
deterministic — all inside the hard instruction-budget walls the repo already
enforces. The work is mechanism-altitude by explicit decision (D-1): the
governing impulses already live in doctrine; what ships here is the skill and
script mechanism that applies them.

## Scope

### In scope

- `/self-review` spec resolution and brief binding: format-version-2-aware
  resolution through the status render, Ready-widening of the no-arg
  fallback rung, and the brief fall-through misbind fix.
- `/orchestrate` selection-contract documentation: the exit-3 transient
  evidence hold mapped in the selection prose and the stop-conditions table,
  and version-keyed ready-task candidacy.
- `/spec-kickoff` sign-off verification: a pre-flip repo-lint check, the
  mechanical re-derivation of recorded cross-check and numeric claims, a
  head-SHA CI gate on the terminal ready-flip, a delta-scoped lens pass at
  the point a mid-walk agent-authored meaning-class edit is applied, and a
  post-lens stale-reference sweep.
- `/spec-draft` self-critique: a scoped lens pass over the freshly drafted
  bundle before handoff.
- `scripts/resolve-rule-doc.sh` deterministic self-location, adopting the
  existing `fix/resolve-rule-doc-self-locate` branch work.
- Consuming the fourteen seed observations named in `## Sources` (plus the
  fix branch's own fragment, which rides Task 1).
- Instruction-budget compliance for every skill-prose change this spec
  makes.

### Out of scope

- `/execute-task`'s status fallback and gate: already Ready-widened at
  v0.14.1; nothing to fix.
- Accumulator findings outside the seed set (validator gaps, parser
  divergence, release edges, and the rest of the triage ledger's VALID
  items): they keep their own drain path.
- The dotfiles-side workflows and the rigor-doctrine copies duplicated in
  the user's global CLAUDE.md: out of this repo's reach.
- Redesigning CI, the release pipeline, or the ready-flip's ownership
  semantics: kickoff-lifecycle owns the sign-off ritual; this spec hardens
  its verification only.
- Raising the instruction-budget ceilings or editing budget exemptions:
  the instruction-headroom spec's domain.

## REQ-A — Lifecycle and format-v2 skill reconciliation

- **REQ-A1.1** `/self-review`'s no-arg spec-resolution fallback SHALL
  resolve the spec through the status render (`scripts/spec-status.sh`),
  accepting a spec whose reported status is Ready or Active, and SHALL NOT
  grep for a stored `Status: Active`; format-version-2 bundles, which store
  Ready while work is in flight, SHALL be found.
  *(Cites: D-2; obs:a74ddac5, legacy line 157 (Sources), legacy line 125
  (Sources).)*
- **REQ-A1.2** When the branch convention names a spec that has no kickoff
  brief of its own, `/self-review` SHALL treat the brief as absent (the
  Agent-resolvable bucket unavailable) and SHALL NOT fall through to an
  unrelated spec's brief.
  *(Cites: D-2; legacy line 109 (Sources).)*
- **REQ-A1.3** `/orchestrate`'s instructions SHALL document selection
  exit 3 (the format-version-2 transient evidence hold) in both the
  selection prose and the stop-conditions table, as a clean report-and-end
  of the step — never as an unmapped hard failure.
  *(Cites: D-10; obs:bf4f1091.)*
- **REQ-A1.4** `/orchestrate`'s ready-task candidacy prose SHALL be
  version-keyed: the version 1 and format-version-2 candidacy conditions
  each stated.
  *(Cites: D-10; obs:bf4f1091.)*

## REQ-B — Sign-off verification rigor

- **REQ-B1.1** `/spec-kickoff` SHALL NOT mark the spec PR ready while the
  head SHA's check rollup is failing or unresolved; on a red rollup or an
  expired wait bound it SHALL leave the PR draft and surface the remedy.
  *(Cites: D-3; legacy line 168 (Sources).)*
- **REQ-B1.2** Before the Draft→Ready flip, `/spec-kickoff` SHALL run the
  repository's lint over the kickoff brief and every spec file it edited,
  and SHALL block the flip on errors.
  *(Cites: D-3; legacy line 131 (Sources).)*
- **REQ-B1.3** Any cross-check or numeric claim the sign-off records as
  evidence (per-tag coverage tallies, REQ/D-ID/task/edit counts, pinned
  version or tag figures, "every X cited by at least one Y" assertions)
  SHALL be mechanically re-derived before the flip, a mismatch blocking;
  figures derivable from the bundle SHALL be cited rather than copied, per
  the meta-spec's cite-derived-figures rule.
  *(Cites: D-4; legacy line 131 (Sources), legacy line 132 (Sources).)*
- **REQ-B1.4** An agent-authored meaning-class edit applied during the
  walkthrough SHALL receive a delta-scoped lens pass at the point of
  application, recorded in the brief; the terminal sign-off lens pass is
  unchanged and still runs.
  *(Cites: D-5; legacy line 173 (Sources).)*
- **REQ-B1.5** After the sign-off lens pass mints or re-scopes any REQ,
  `/spec-kickoff` SHALL sweep the bundle and the earlier brief sections for
  now-stale references (counts, cross-references, dependent task and test
  wording, risk-IDs) before computing the anchor.
  *(Cites: D-6; legacy line 105 (Sources).)*

## REQ-C — Drafting self-critique

- **REQ-C1.1** `/spec-draft` SHALL run a scoped self-critique lens pass
  over the freshly assembled bundle before handoff, dispositioning every
  finding (fixed, or surfaced to the human) — never silently dropping one.
  *(Cites: D-7; legacy line 165 (Sources).)*

## REQ-D — Deterministic doctrine resolution

- **REQ-D1.1** `scripts/resolve-rule-doc.sh` SHALL resolve core doctrine
  with no environment roots set whenever the doctrine directory ships
  beside the script (self-location), covering planwright's own checkout,
  its worktrees, and dispatched worker subshells.
  *(Cites: D-8; obs:446f8103, legacy line 164 (Sources), legacy line 75
  (Sources).)*
- **REQ-D1.2** The existing resolution precedence SHALL be unchanged —
  overlay layers first, then `PLANWRIGHT_ROOT`, `CLAUDE_PLUGIN_ROOT`, the
  writer root; the self-location arm is additive and lowest-precedence,
  never overriding an environment root.
  *(Cites: D-8; the self-locate fix branch (Sources).)*

## REQ-E — Instruction-budget compliance

- **REQ-E1.1** Every skill-prose change this spec makes SHALL leave the
  touched skill within its instruction budgets as enforced by
  `check:instructions`; a change that cannot fit SHALL be gated on the
  instruction-headroom spec's relief or a compensating trim landing in the
  same change — never a silent breach and never an exemption edit.
  *(Cites: D-9; drafting-session decision (2026-07-16).)*

## Changelog

- 2026-07-16 — Bundle drafted via `/spec-draft`. Fourteen seed
  observations consumed (three fragments archived, eleven frozen legacy
  lines annotated in place); fold-detection surfaced extend-vs-new against
  bootstrap, kickoff-lifecycle, and invariant-tasks, and the human chose a
  new bundle.

## Sources

- **obs:a74ddac5** — `/self-review` resolves its spec by a stored-`Active`
  grep, missing format-version-2 bundles (fragment, archived 2026-07-16).
- **obs:bf4f1091** — selector exit 3 shipped after the skill
  reconciliation task was drafted; `/orchestrate`'s instructions never
  folded it (fragment, archived 2026-07-16).
- **obs:446f8103** — worker worktrees resolve no doctrine because the
  resolver's env roots are unset in worker subshells; observed on PRs #196
  and #199 (fragment, archived 2026-07-16).
- **obs:29f05039** — the self-locate fix's own observation fragment; rides
  the `fix/resolve-rule-doc-self-locate` branch and is consumed when
  Task 1 lands.
- **legacy line 75** — self-hosted runs resolve doctrine to a stale
  writer-install copy (opportunities.md, annotated 2026-07-16).
- **legacy line 105** — post-lens stale references in earlier brief
  sections; three review-cycle stragglers from one root cause
  (opportunities.md, annotated 2026-07-16).
- **legacy line 109** — the brief fall-through arm can bind a
  spec-authoring branch to an unrelated Active spec's brief
  (opportunities.md, annotated 2026-07-16).
- **legacy line 125** — the no-arg selection fallbacks accept only
  `Active`, not `Ready`; `/execute-task`'s half has since been fixed,
  `/self-review`'s has not (opportunities.md, annotated 2026-07-16).
- **legacy line 131** — kickoff signed off autopilot-reflex with red
  `lint:md` on the brief and an unverified cited-by cross-check
  (opportunities.md, annotated 2026-07-16).
- **legacy line 132** — the sign-off also records numeric claims it never
  re-derives; two shipped past sign-off (opportunities.md, annotated
  2026-07-16).
- **legacy line 157** — a Ready spec with a signed brief is invisible to
  the fallback rung (opportunities.md, annotated 2026-07-16).
- **legacy line 164** — the resolver never considers "the repo I am
  standing in IS planwright" (opportunities.md, annotated 2026-07-16).
- **legacy line 165** — an 86-raw/42-valid kickoff lens yield over a fresh
  draft suggests `/spec-draft` should self-critique before handoff
  (opportunities.md, annotated 2026-07-16).
- **legacy line 168** — `/spec-kickoff` marked PR #128 ready while its CI
  was red; the terminal step verifies no CI state (opportunities.md,
  annotated 2026-07-16).
- **legacy line 173** — a mid-walk agent-authored meaning-class edit
  introduced a real deadlock caught only at the terminal lens pass
  (opportunities.md, annotated 2026-07-16).
- **The self-locate fix branch** — `fix/resolve-rule-doc-self-locate`, two
  unpushed local commits (the script's self-location arm plus tests and
  doc alignment), discovered non-empty during drafting despite the
  invocation brief describing it as zero-commit.
- **Invocation brief (2026-07-16)** — the `/spec-draft` mission text
  framing the four gap groups, the budget walls, and the fold-detection
  overlaps.
- **2026-07-16 accumulator triage** — a ten-agent verification of the full
  accumulator against v0.14.1 confirming every seed still valid
  (session-local verdict ledger; not committed).
- **Altitude claim: sign-off trusts the narrative** — legacy lines 131 and
  132 assert the sign-off records evidence it never re-derives; pinned per
  the autopilot-reflex seed-claim trigger and resolved as D-1.
- **Altitude claim: catches shift one stage left** — legacy line 165
  asserts each authoring stage should self-check before handoff; pinned
  and resolved as D-1.
- **Altitude claim: resolution must be deterministic** — obs:446f8103
  asserts doctrine resolution must not be memory-dependent; pinned and
  resolved as D-1.
