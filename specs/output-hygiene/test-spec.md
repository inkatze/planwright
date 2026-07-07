# Output & Accumulator Hygiene — Test Spec

**Status:** Ready
**Last reviewed:** 2026-07-07
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

### REQ-B1.1 — No shared append point [test]

Task 1 suite: two runs with distinct identities on the same date compute **different**
fragment filenames (asserted directly — the per-run nonce guarantees it), each writing its
own file with no shared append point; consolidation by the single writer yields one
conflict-free log with entries appended in consolidation order. A concurrent-consolidation
case (two `--bookkeeping` runs over the same queue) proves **fragment-identity idempotency**:
re-processing the same fragment produces no duplicate, but two distinct fragments with
identical text both land; and a simulated `opportunities.md` conflict resolves by
**union-of-appends** (every entry from both sides survives), never by regenerate/ours/theirs.

### REQ-B1.2 — Class-3 invariants preserved [test + design-level]

Design-level: the accumulator-taxonomy amendment names the queue's durable home, canonical
reader, and drain ritual. Test: the drain-report fixture (Task 2) surfaces queue entries
in the unmined count and oldest-age figures.

### REQ-B1.3 — No loss, reorder, or rewrap [test]

Task 1 suite: consolidation over a populated `opportunities.md` leaves every pre-existing
line byte-for-byte intact apart from appended entries (entry text moved verbatim, no
rewrap/redact); appended entries are in consolidation order, never re-sorted by fragment
date. The atomic-commit case proves crash safety: the append and the fragment deletions are
one commit, so an interrupted run persists neither (recovery resets the uncommitted working
tree), and a re-run over partly-consumed state is idempotent by fragment identity — the same
fragment never lands twice, and the union-on-conflict case loses no historical entry.

### REQ-B1.4 — Consumer semantics unchanged [test + design-level]

Test: drain-report fixture with and without queue entries — report grammar unchanged,
counts include the queue. Design-level: `/spec-draft` instructions name **`opportunities.md`
(the consolidated log)** as its mining/archive source (queue counted for visibility only,
never consumed raw — F2), and `--bookkeeping` (the sole consolidation writer) names the queue
in its consolidation step.

### REQ-B1.5 — Hostile-name safety and containment [test]

Task 1 suite: a fragment-name derivation fed a traversal or metacharacter component in **any
of the three parts** — `<date>`, `<taskid>`, or `<run-nonce>` (`../`, an embedded `/`, a
non-printable byte, a malformed date) — is a clean refusal — the observation is
dropped-and-flagged, no file is written outside `specs/_observations/queue/`; a valid
`<date>-<taskid>-<run-nonce>` passes. A name echoed into the drain/consolidation output is
printable-sanitized (an embedded escape sequence does not reach the terminal). Mirrors the
`orchestration-concurrency` REQ-F1.1 traversal test.

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
**standing** `[[name]]` guard (Task 5/6): fixtures with a `[[foo]]` token in a **spec file
and in a `kickoff-brief.md`** each fail the `check:*` guard under `mise run check`, a clean
bundle passes, and the allowlist carve-out lets the declined fleet-brief links pass (F5) — so
a future writer that skips neutralization (spec *or* brief) is caught by CI, not just a
one-shot grep. Manual: the fleet-bundle amendment leaves no `[[…]]` citation behind in its
spec files.

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
