# Skill rigor — Test spec

**Status:** Draft
**Last reviewed:** 2026-07-16
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: the resolver and budget requirements are `[test]` (real
scripts run in `mise run check` on GitHub CI). Skill-prose behaviors with
a stable, greppable surface pattern are also `[test]`, wired to the
repo's structural guard suites (the `tests/test-skill-*.sh` /
`tests/test-spec-kickoff-*.sh` pattern, extended by the task that edits
the surface); `[design-level]` covers what a grep cannot pin, with
`[manual]` paths added where only a live run can exercise the behavior.

## REQ-A — Lifecycle and format-v2 skill reconciliation

### REQ-A1.1 — Render-based spec resolution [test + manual]

Test: a structural guard (extended by Task 3) asserts the fallback rung
names `scripts/spec-status.sh` and Ready-or-Active acceptance, with no
stored `Status:` grep remaining in the rung (rung-scoped, matching
Task 3's Done-when). Manual: in a worktree of a format-version-2 bundle
with work in flight (stored Ready) — this spec itself is such a fixture
once merged and its first task starts — run `/self-review` with no
argument off a non-convention branch and confirm the spec and its brief
are found.

### REQ-A1.2 — Brief absent over misbind [design-level + manual]

Design-level: the pre-flight rung states that a branch-named spec without
its own `kickoff-brief.md` yields brief-absent (Agent-resolvable
unavailable), with no fall-through to another spec's brief. Verified by
reading the shipped rung text against the legacy line 109 scenario.
Manual failing case: on a branch naming a spec that has no brief (a spec
branch pre-kickoff reproduces this), run `/self-review` while another
spec with a brief is Ready or Active, and confirm no foreign brief is
bound.

### REQ-A1.3 — Exit 3 documented as a hold [test]

A structural guard (extended by Task 4) asserts
`skills/orchestrate/SKILL.md`'s stop-conditions table carries a selection
exit 3 row and the selection prose describes the hold as report-and-end,
matching `scripts/orchestrate-select.sh`'s shipped exit contract (cross
read: the script's exit-3 site).

### REQ-A1.4 — Version-keyed candidacy [test + design-level]

Test: a structural guard (extended by Task 4) asserts the selection
section states ready-task candidacy for version 1 and format-version-2
explicitly. Design-level: the stated conditions are read against the
meta-spec's two candidacy definitions.

## REQ-B — Sign-off verification rigor

### REQ-B1.1 — CI-gated ready-flip [design-level + manual]

Design-level: the terminal step's documented rollup query targets the
head SHA's checks (never PR review states), with the wait bound and
refusal arm stated. Manual: run a kickoff whose pushed brief carries a
deliberate lint error; CI goes red; confirm the PR is left draft with the
remedy surfaced, and that fixing and re-running flips it ready.

### REQ-B1.2 — Pre-flip lint [design-level + manual]

Design-level: the sign-off flow documents the blocking pre-flip lint over
the brief and edited spec files. Manual: introduce a markdownlint error
into the brief during a walkthrough and confirm the flip is blocked
before any push.

### REQ-B1.3 — Recorded claims re-derived [design-level + manual]

Design-level: the sign-off flow documents mechanical re-derivation of
recorded cross-check and numeric claims with blocking semantics, and the
cite-derived-figures preference. Manual: seed a brief draft with a
deliberately wrong coverage tally and confirm the flip is blocked with
the mismatch named.

### REQ-B1.4 — Mid-walk lens on meaning edits [design-level + manual]

Design-level: the walkthrough section documents the delta-scoped lens at
the point an agent-authored meaning-class edit is applied, and the brief
records its disposition. Manual failing case: during a walkthrough, have
the agent propose and apply a meaning-class edit carrying a planted
defect (a claim contradicting a signed section) and confirm the mid-walk
lens catches it at application — not merely that a lens record exists.

### REQ-B1.5 — Post-lens stale-reference sweep [test + manual]

Test: a structural guard (extended by Task 7) asserts the sign-off
section documents the sweep (its trigger — any walkthrough lens pass
minting or re-scoping a REQ — its targets: counts, cross-references,
dependent task and test wording, risk-IDs, and its ordering before the
D-4 re-derivation is finalized) running before the anchor is computed.
Manual failing case: seed a stale count in an earlier brief section, mint
a REQ in the lens pass, and confirm the sweep reconciles the count before
the anchor.

## REQ-C — Drafting self-critique

### REQ-C1.1 — Draft self-critique pass [design-level + manual]

Design-level: `skills/spec-draft/SKILL.md`'s review-and-validate phase
documents the inline scoped lens pass with its trigger point, disposition
rule (fixed or surfaced, never silently dropped; an erroring pass
surfaced, never treated as clean), and its declared proportionality
scoping. Manual: one live drafting run confirms the handoff carries the
pass's disposition list.

## REQ-D — Deterministic doctrine resolution

### REQ-D1.1 — Self-locating resolver [test]

`tests/test-resolve-rule-doc.sh` (extended by the adopted fix-branch
work) covers resolution with `PLANWRIGHT_ROOT`, `CLAUDE_PLUGIN_ROOT`,
`CLAUDE_DIR`, and `HOME` all unset from a checkout-shaped layout, and
runs in `mise run check` on GitHub CI.

### REQ-D1.2 — Precedence no-regression [test]

The existing resolver test cases for the overlay layers and the three
env-root arms keep passing unchanged in the same suite; the self-location
case additionally asserts an env root wins over the script-dir arm when
both are present.

## REQ-E — Instruction-budget compliance

### REQ-E1.1 — Budget compliance [test + manual]

Test: `check:instructions` (in `mise run check`, CI-gated) fails any
change that pushes a touched skill past its per-file, start-load, or
closure budget; each prose task's Done-when requires it green on the
touched surface, so the requirement is exercised on every landing PR.
Manual: the no-silent-breach / no-exemption-edit clause is verified at
task-PR review (the diff touches no budget ceiling or exemption entry); a
diff-scoped guard for this is recorded as an observation, not specced
here.
