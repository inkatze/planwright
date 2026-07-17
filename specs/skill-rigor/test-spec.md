# Skill rigor — Test spec

**Status:** Draft
**Last reviewed:** 2026-07-16
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: the resolver and budget requirements are `[test]` (real
scripts run in `mise run check` on GitHub CI); the skill-prose behaviors
are `[design-level]` (the SKILL text is the shipped artifact), with
`[manual]` paths added where only a live run can exercise the behavior.
No `[test]` tag is claimed where nothing executes: skill-prose behavior
has no automated harness today.

## REQ-A — Lifecycle and format-v2 skill reconciliation

### REQ-A1.1 — Render-based spec resolution [design-level + manual]

Design-level: `skills/self-review/SKILL.md`'s fallback rung names
`scripts/spec-status.sh` and Ready-or-Active acceptance, with no stored
`Status:` grep remaining (grep the SKILL for the old pattern). Manual: in
a worktree of a format-version-2 bundle with work in flight (stored
Ready), run `/self-review` with no argument off a non-convention branch
and confirm the spec and its brief are found.

### REQ-A1.2 — Brief absent over misbind [design-level]

The pre-flight rung states that a branch-named spec without its own
`kickoff-brief.md` yields brief-absent (Agent-resolvable unavailable),
with no fall-through to another spec's brief. Verified by reading the
shipped rung text against the legacy line 109 scenario.

### REQ-A1.3 — Exit 3 documented as a hold [design-level]

`skills/orchestrate/SKILL.md`'s stop-conditions table carries a selection
exit 3 row and the selection prose describes the hold as report-and-end,
matching `scripts/orchestrate-select.sh`'s shipped exit contract (cross
read: the script's exit-3 site).

### REQ-A1.4 — Version-keyed candidacy [design-level]

The selection section states ready-task candidacy for version 1 and
format-version 2 explicitly; verified by reading the section against the
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
records its disposition. Manual: during a walkthrough, have the agent
propose and apply a meaning-class edit and confirm the brief section
carries the scoped lens record.

### REQ-B1.5 — Post-lens stale-reference sweep [design-level]

The sign-off section documents the sweep (its trigger — the lens pass
minting or re-scoping a REQ — and its targets: counts, cross-references,
dependent task and test wording, risk-IDs) running before the anchor is
computed.

## REQ-C — Drafting self-critique

### REQ-C1.1 — Draft self-critique pass [design-level]

`skills/spec-draft/SKILL.md`'s review-and-validate phase documents the
inline scoped lens pass with its disposition rule (fixed or surfaced,
never silently dropped) and its declared proportionality scoping. The
pass's yield is observable in later drafting sessions' handoffs.

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

### REQ-E1.1 — Budget compliance [test]

`check:instructions` (in `mise run check`, CI-gated) fails any change
that pushes a touched skill past its per-file, start-load, or closure
budget; each prose task's Done-when requires it green on the touched
surface, so the requirement is exercised on every landing PR.
