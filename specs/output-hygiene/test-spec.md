# Output & Accumulator Hygiene — Test Spec

**Status:** Done
**Last reviewed:** 2026-07-08
**Format-version:** 1

Coverage mix: the mechanical REQs are `[test]` (suites under `tests/`, run by the
`mise run check` aggregate — the repo's CI); the prose-contract REQs are
`[design-level]` with `[manual]` exercise on the next real emission, because a fixture
asserting "this markdown is concise" would be verification theater.

## REQ-A — Human-first PR bodies

### REQ-A1.1 — Summary-first body [design-level + manual]

The gate-wiring PR-body assembly section (Task 3) states the summary-first content list;
both emitting skills cite it. Manual: read the next `/execute-task` or `/self-review` PR
body — summary present and first, task IDs / REQs / pending items named.

### REQ-A1.2 — Audit record complete but collapsed [design-level + manual]

The section requires the complete audit record inside a collapsed block, and its example
body shows it. Manual: the next emitted body carries the full audit record inside
`<details>`, nothing dropped versus the audit-record definition.

### REQ-A1.3 — No hard-wrapped prose [design-level + manual]

The section forbids fixed-column wrapping; its example body contains none. Manual: the
next emitted body renders without ragged mid-sentence breaks on GitHub.

### REQ-A1.4 — One normative home, updates included [design-level]

Both skills' emission steps cite the gate-wiring section and carry no duplicated
body-content list of their own (Task 3 Done-when); the section states that in-place
updates keep the structure.

## REQ-B — Conflict-free observations recording

*(Group superseded 2026-07-08: the REQ-B requirements moved to
`specs/observation-recording` and their verification lives in that bundle's test-spec;
the entries were removed with the group — see requirements `## Changelog`.)*

## REQ-C — Pending-sign-off marker canonicalization

### REQ-C1.1 — Canonical placement defined and lint-safe [test + design-level]

Design-level: gate-wiring pins end-of-subject placement. Test: `--marker` fixtures —
canonical subject passes; pre-prefix placement fails (it already fails the conventional
lint: reproduced during drafting); mid-subject fails the marker mode.

### REQ-C1.2 — Skills emit canonical placement [manual]

The next `[pending-sign-off]` commit emitted by a skill carries the marker at end of
subject. (The emit-time self-lint of REQ-C1.3 is the mechanical backstop.)

### REQ-C1.3 — Guard fires at fixable time, no new trap [test + design-level]

Test: the `--marker` mode rejects bad placement on `--stdin` input (the emit-time path).
Design-level: the CI commit-range invocation is unchanged by Task 4 (diff-inspectable),
so no historical commit can newly redden a PR.

### REQ-C1.4 — Branch-scoped marker [test + design-level]

Test: a marker in the PR-title position is rejected by the title lint path (Task 4's
`--marker` mode). Design-level: the branch-scoped-*consumption* rule (marker consumers scan
only the PR `base..head` range, never merged mainline where squash relocates relic text) is
stated in the gate-wiring doctrine and the merge-strategy matrix, and its **existing
consumer is the pending-sign-off checklist regeneration** (gate-wiring), which rebuilds from
`[pending-sign-off]` commits ahead of the base and already excludes markers arriving through
a merge from the base — i.e. it already implements the branch-scoping and the squash-relic
exclusion. Verification is that Task 4's doctrine wording and that consumer's scan scope
agree; a marker relic on the base side of a `base..head` range is not counted (exercised
against the checklist regeneration's existing base-exclusion behavior, manually on the next
emission).

## REQ-D — Committed-reference integrity

### REQ-D1.1 — No reader-unresolvable references [test + manual]

Covered mechanically by the REQ-D1.3 lint fixtures for delivered-layout links, and by the
**standing** `[[name]]` guard (Task 5/6): a fixture with a `[[foo]]` token in a spec file
fails the `check:*` guard under `mise run check`, and a clean bundle passes — so a future
writer that skips neutralization is caught by CI, not just by a one-shot grep. Manual: the
fleet-bundle amendment leaves no `[[…]]` citation behind in its spec files.

### REQ-D1.2 — Neutralization step in the writers [design-level + manual]

Design-level: the `/spec-draft` completion step states the rewrite rule and the Sources
citation form. Manual: the next drafted bundle commits no `[[name]]` token.

### REQ-D1.3 — Delivery-safe link convention, linted [test]

Task 5 fixtures: a doctrine file linking `../skills/...` fails; sibling-doctrine,
`../config/`, and `../scripts/` links pass (all three are co-located delivery siblings);
in-page anchors unaffected. Runs in `check:links` under `mise run check`.

### REQ-D1.4 — Known violations reconciled [test + manual]

Test: repo-wide `check:links` green after the guard-catalog fix, with the new rule
active. Manual: the orchestration-fleet changelog records the expression-only amendment
and its brief anchor matches `scripts/spec-anchor.sh` output.

## REQ-E — Derived-content hygiene

### REQ-E1.1 — Cited or regenerated, never hand-copied [design-level]

The principle is expressed by its three applications: REQ-E1.2's stamping test, and the
REQ-E1.3 / REQ-E1.4 guidance edits, each verified below.

### REQ-E1.2 — Organic completion-annotation stamping [test]

Task 7 suite: a reconcile run over merged-PR evidence stamps the canonical
`Completed · PR #<n> merged <YYYY-MM-DD>` string on the moved block; the no-remote fixture
shows exactly one of the two pinned outputs — `Completed · merged <YYYY-MM-DD>` or the
annotation left untouched — never an invented PR number and never a third variant;
annotations of non-completion tasks remain byte-for-byte; and the content anchor
(`scripts/spec-anchor.sh`) over the bundle is **unchanged** by the stamp (the five
definition fields are untouched — confirms the additive, non-supersession property).

### REQ-E1.3 — Brief cite-don't-copy convention [design-level + manual]

Design-level: the meta-spec's kickoff-brief guidance names the convention. Manual: the
next kickoff brief cites source sections for tallies instead of copying figures.

### REQ-E1.4 — No hand-drawn graphs [design-level]

The meta-spec's `tasks.md` section no longer suggests a drawn graph and names
`Dependencies:` lines as sole source of truth with the graph view as renderer; this
bundle's own `tasks.md` conforms from birth.
