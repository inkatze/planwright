# Anchor integrity — Tasks

**Status:** Draft
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

Task blocks below sit in dependency order. Execution state is derived, never
authored; see the status render.

## Tasks

### Task 1 — Meta-spec anchor amendments

- **Deliverables:** Amendments to `doctrine/spec-format.md`: the
  header-block `**Status:**` exclusion rule for the v1 per-file digests
  (bounded by the header-block scope; defer to format-grammar's scope
  definition where landed, else define the bound inline with a reconcile
  note); the committed-main frame statement in the execution-validity
  prose; the third sanctioned resolution-aware command form and the
  resolution chain it names; the decided-rule authoring-guidance
  refinement (no format-version bump). Dated meta-spec changelog entries
  for each.
- **Done when:** the meta-spec states all four amendments with changelog
  entries; `mise run check` documentation and lint tasks pass.
- **Dependencies:** none
- **Citations:** D-1, D-2, D-4, D-7, D-8 · REQ-A1.1, REQ-A1.2, REQ-B1.1,
  REQ-E1.1, REQ-F1.1
- **Estimated effort:** half day

### Task 2 — Anchor tool hash-scope change

- **Deliverables:** The D-2 exclusion implemented for the
  `requirements.md` / `design.md` / `test-spec.md` digests, inside the
  shared extraction library if format-grammar's re-point has landed, else
  in `scripts/spec-anchor.sh` with a reconcile note; the script's header
  self-description corrected; the `scripts/tasks-pr-sync.sh` "NOT yet
  anchor-excluded" caveat comment updated; verification that
  `scripts/migrate-format-version.sh`'s written anchor entries remain
  sanctioned under the amended forms. Unit tests: anchor invariance under
  header Status flips across the sanctioned stored and derived values of
  each format version, across all four files' mirrors; meaning-edit
  sensitivity unchanged; header-block bounding (a body-prose or fenced
  `**Status:**` line still moves the anchor when edited); fail-closed on
  a malformed, duplicated, or unterminated header block (non-zero exit,
  no anchor printed).
- **Done when:** the new tests pass alongside the existing
  `tests/test-spec-anchor.sh` suite; recomputed anchors move only for
  bundles whose Status line previously rode the hash; the
  `tasks-pr-sync.sh` caveat comment is updated and
  `migrate-format-version.sh`'s written form re-verified; the change
  ships in the same PR as Task 3 (required cohesion bundle 2+3 — the
  hash-scope change is not independently mergeable).
- **Dependencies:** 1
- **Citations:** D-2 · REQ-A1.1, REQ-A1.2, REQ-A1.3
- **Estimated effort:** 1 day

### Task 3 — Coordinated v1 re-anchor sweep

- **Deliverables:** Marked `Class: expression-only` re-anchor entries
  appended to the kickoff brief of every briefed non-Draft, non-terminal
  bundle whose latest anchor fails to recompute under the amended
  semantics — pre-existing staleness and interim whole-file-form entries
  included (the latter converted to a current sanctioned form) — after a
  per-bundle delta classification per REQ-A1.4: diff from the commit
  that introduced the entry's anchor line; lifecycle-only or
  expression-only → machine entry citing the delta that actually moved
  the anchor (the Task 1 amendment's changelog line for hash-scope
  movement); meaning-class or unresolvable → route to the status-apt
  re-review ritual (delta re-walkthrough for Ready/Active, reopen cycle
  for Done) and park that bundle without blocking the sweep, writing the
  live `anchor re-review pending` bullet into its `## Awaiting input`
  (removed at the re-review's sign-off). A one-shot
  landing proof that every in-scope bundle recomputes equal, re-verified
  along with the classifications at the sweep PR's merge SHA. Adopter
  remedy documented (the `docs/` home plus the freshness gate's
  halt-guidance prose naming the one-time self-re-anchor with the same
  classification rule).
- **Done when:** the landing proof is green in the same PR as Task 2's
  change (cohesion bundle 2+3) and re-verified at the merge SHA; the
  adopter remedy prose exists in both named places; the landing commits
  carry the conventional breaking-change marker naming the one-time
  remedy (bump class derives from the release scheme at release time).
- **Dependencies:** 2
- **Citations:** D-3 · REQ-A1.4, REQ-A1.5
- **Estimated effort:** half day

### Task 4 — Anchor-freshness guard

- **Deliverables:** A guard script (working name
  `scripts/check-anchor-freshness.sh`) asserting, for every non-Draft,
  non-terminal bundle with a kickoff brief: the brief's most recent
  anchor entry parses, uses a sanctioned command form, and recomputes
  equal against the checked tree; and that an edit to anchored content
  since the baseline ref (detected via the canonical extraction —
  changes confined to excluded content never flag) carries a dated
  Changelog entry in that bundle. Draft and terminal-state bundles
  skipped with a notice; a brief-less non-Draft, non-terminal bundle is
  an error naming the repair remedy; a bundle carrying the live
  `anchor re-review pending` park marker is a known-parked notice, not
  an error. Recorded commands handled per
  REQ-D1.5 (grammar-validate then invoke with a containment-checked
  argument, sanitized echo, rev-parse-validated baseline); an
  unresolvable default baseline degrades the pairing check to a
  skip-with-notice (explicit `--baseline` failures stay fatal). Wired as
  a `mise run check` task (the normative merge gate, whole-corpus) and
  as a lefthook pre-commit mirror scoped to commits staging `specs/**`
  (lefthook introduced to the repo by this task — net-new hook
  infrastructure, including the `mise.toml` tools entry and a documented
  install step via the repo's existing setup path, so the best-effort
  mirror is discoverable rather than private to whoever wired it).
  Unit tests covering the green, stale-anchor,
  non-sanctioned-form, unparseable-entry, most-recent-entry-selection,
  missing-changelog, excluded-content-edit-stays-green,
  missing-brief-error, known-parked-notice, and skip paths.
- **Done when:** the guard is red on a synthesized stale-anchor fixture,
  green on the swept repo, wired into `mise run check` and the
  newly-introduced `lefthook.yml`, and its tests pass in CI.
- **Dependencies:** 2, 3
- **Citations:** D-6 · REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-D1.5
- **Estimated effort:** 1 day

### Task 5 — Act-on-findings re-anchor ritual

- **Deliverables:** `/self-review`, `/polish`, and `/execute-task`'s
  convergence step gain the three D-5 behaviors: stale-anchor pre-flight
  before any signed-bundle edit (blocking on mismatch, absent or
  unparseable entry, and recompute failure alike); the expression-only
  self-re-anchor ritual (dated Changelog entry plus marked anchor entry,
  all in one commit with the edit);
  meaning-class refusal with routing to `/spec-kickoff`. The doctrine
  statement binding act-on-findings skills generally (external families
  included) lands in the meta-spec's writer prose or `gate-wiring.md`
  (placement decided at execution, cited back here). Gherkin
  state/trigger/outcome scenarios recorded in `test-spec.md` verification
  homes.
- **Done when:** all three behaviors appear in each named skill's prose;
  the doctrine statement exists; skill instruction-budget checks stay
  green.
- **Dependencies:** 1
- **Citations:** D-5 · REQ-C1.1, REQ-C1.2, REQ-C1.3
- **Estimated effort:** 1 day

### Task 6 — Kickoff terminal re-anchor

- **Deliverables:** `/spec-kickoff`'s finishing ritual gains the terminal
  recompute: any edit to anchored content after the sign-off record is
  written (post-sign-off review or panel fixes on the spec PR included)
  re-triggers the anchor recompute and re-record as the final pre-push
  step — expression-only edits only (a meaning-class post-sign-off edit
  re-enters the sign-off flow first), halting the push on a failed
  recompute. Gherkin scenario recorded in `test-spec.md`.
- **Done when:** the skill prose states the terminal recompute; the
  scenario is recorded; skill instruction-budget checks stay green.
- **Dependencies:** 1
- **Citations:** D-5 · REQ-C1.4
- **Estimated effort:** half day

### Task 7 — Enumeration cross-check at draft and kickoff

- **Deliverables:** `/spec-draft` and `/spec-kickoff` gain the enumeration
  cross-check step: flag enumerated counts and corpus claims in bundle
  prose, verify each against the surface it enumerates or convert it to a
  decided-rule statement, citing the Task 1 guidance refinement.
- **Done when:** both skills state the check; skill instruction-budget
  checks stay green.
- **Dependencies:** 1
- **Citations:** D-8 · REQ-E1.1, REQ-E1.2
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
