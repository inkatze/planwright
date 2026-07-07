# Output & Accumulator Hygiene — Tasks

**Status:** Ready
**Last reviewed:** 2026-07-07
**Format-version:** 1

Eight tasks. The `Dependencies:` lines are authoritative (no drawn graph — REQ-E1.4
applied to this bundle from birth). The guard-first lesson (bootstrap selection-policy
observation, 2026-06-11) is encoded as edges: Task 5's link lint protects every
doc-writing task, so Tasks 3, 4, 6, and 8 depend on it explicitly. Critical path:
Task 1 → Task 2.

## Forward plan

### Task 1 — Fragment queue and consolidation primitive

- **Deliverables:** `specs/_observations/queue/` convention (fragment filename grammar
  `<YYYY-MM-DD>-<taskid>-<run-nonce>.md`: `<taskid>` from the run's task/branch id,
  `<run-nonce>` a run-unique token chosen once at run start — a stable run/dispatch id where
  one exists, else a short `^[a-z0-9]+$` random token — so two runs on the same task+date
  cannot collide; one file per run, all its observations appended to it; all three name
  components — `<date>` (`^\d{4}-\d{2}-\d{2}$`), `<taskid>`, `<run-nonce>` — charset-validated
  before path interpolation and the derived path containment-checked, with a clean refusal on
  hostile/malformed input, per REQ-B1.5); a **single-writer reconcile routine that owns every
  `opportunities.md` mutation** — append queued fragments' entries in consolidation order
  **and** delete the consumed fragments **and** apply recorded archive/trim deletions, as
  **one atomic commit**; idempotency is by **fragment presence** (a serial writer consolidates
  each fragment once, delete-after-consolidate, so a crash-retry is a no-op — no embedded IDs
  or merge-time dedup); a conflict on `opportunities.md` is a **violated-invariant** signal,
  resolved by **rebuild-from-components** (committed log ∪ unconsolidated queue −
  recorded-archived) or **fail-loud**, never blind union/regenerate/ours/theirs; the **global
  `_observations` advisory lock** serializes reconcile runs (a correctness serializer);
  branch-/slug-derived names printable-sanitized before any echo (REQ-B1.5);
  accumulator-taxonomy doctrine amendment naming the queue as a class-3 surface (durable
  home, canonical reader `/spec-draft`, drain ritual).
- **Done when:** two runs with distinct identities on the same date produce **different**
  filenames (asserted directly); the reconcile appends queued fragments (in order, deleted
  after) and applies a recorded archive/trim in the same atomic commit, leaving pre-existing
  entries byte-for-byte apart from the intended append/delete; a re-run over already-consolidated
  state is a byte-identical no-op (fragment-presence idempotency); an injected
  `opportunities.md` conflict is **not** auto-merged — the routine rebuilds from components (or
  fails loud) and no archived-then-trimmed entry is resurrected; a traversal / metacharacter
  fragment name (in any of the three components) is a clean refusal writing no out-of-tree
  file, and an echoed name is printable-sanitized; the doctrine names the queue surface;
  `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-1 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.5
- **Estimated effort:** 3 days

### Task 2 — Consumer wiring for the queue

- **Deliverables:** convert **every recording skill** (`/execute-task`, `/self-review`,
  `/spec-kickoff`, `/spec-draft`) from appending a line to `opportunities.md` to **dropping a
  queue fragment** (Task 1's grammar) — so no feature branch ever writes the log (the root of
  the #124 collision); `/orchestrate --bookkeeping` is the **sole `opportunities.md` writer**,
  invoking Task 1's reconcile routine on the default branch; `/spec-draft` mines the
  consolidated log **plus a read-only queue preview** (recent, not-yet-consolidated
  observations stay visible), and instead of trimming the log on its branch it **records a
  consumption marker** the reconcile applies (archive-move + trim); the drain pass still
  **counts** queue entries in the unmined/oldest-age figures.
- **Done when:** each of the four recording skills' instructions name the fragment-drop (no
  direct `opportunities.md` append remains); a repo search finds no skill appending the log
  directly; a drain-report fixture with queue entries shows them counted; `--bookkeeping` is
  named the sole log writer and applies a recorded consumption marker (archive+trim) in its
  reconcile; `/spec-draft`'s instructions name the log-plus-queue-preview mining source and the
  consumption-marker hand-off (no branch-side log write); `mise run check` passes.
- **Dependencies:** 1
- **Citations:** D-1 · REQ-B1.1, REQ-B1.2, REQ-B1.4
- **Estimated effort:** 2 days

### Task 3 — PR-body contract

- **Deliverables:** a PR-body assembly section in the gate-wiring doctrine (summary-first
  content list, complete audit record collapsed in `<details>`, no hard-wrapped prose,
  update-in-place keeps the structure), with an example body; `/execute-task` and
  `/self-review` emission steps rewritten to cite the section instead of carrying their
  own body lists.
- **Done when:** the section exists with the example; both skills cite it and carry no
  duplicated body-content list; the example body contains no hard-wrapped prose;
  `mise run check` passes.
- **Dependencies:** 5
- **Citations:** D-2 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4
- **Estimated effort:** 1 day

### Task 4 — Marker canonicalization and emit-time guard

- **Deliverables:** gate-wiring doctrine pins the canonical end-of-subject placement, the
  branch-scoped consumption rule (naming the existing consumer — the pending-sign-off
  checklist regeneration — whose base..head scan already implements it), and the
  merge-strategy matrix; a `--marker` mode in `scripts/check-commit-msgs.sh` that takes the
  check **context**: on a commit **subject** (`--stdin` emit-time path) it requires canonical
  end-of-subject placement (pre-prefix and mid-subject fail); on a **PR title** it rejects
  any marker; skills that write marked commits self-lint the subject via the `--marker` mode
  before committing; the CI commit-range invocation unchanged.
- **Done when:** `--marker` fixtures cover the four placements plus the PR-title case;
  the CI workflow and range-lint invocation are diff-identical apart from any PR-title
  `--marker` addition; emitting skills' instructions name the self-lint step;
  `mise run check` passes.
- **Dependencies:** 5
- **Citations:** D-3 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4
- **Estimated effort:** 1 day

### Task 5 — Reference-integrity lint

- **Deliverables:** `scripts/check-doc-links.sh` rule: relative links leaving `doctrine/`
  other than to `../config/` or `../scripts/` are errors (sibling doctrine links, in-page
  anchors, and the co-located `../config/` + `../scripts/` siblings unaffected); the
  guard-catalog `../skills/` delivered-dead link fixed to conform (it is the sole real
  violation — the four `../scripts/` links in `decision-domains.md` and `guard-catalog.md`
  are permitted siblings and stay as-is).
- **Done when:** fixtures show a doctrine→`../skills/` link failing and sibling-doctrine
  plus `../config/` and `../scripts/` links passing; repo-wide `check:links` is green (the
  guard-catalog `../skills/` fix plus the four permitted `../scripts/` links);
  `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-4 · REQ-D1.1, REQ-D1.3, REQ-D1.4
- **Estimated effort:** half day

### Task 6 — `[[name]]` neutralization and fleet-citation reconciliation

- **Deliverables:** a `/spec-draft` completion-step rule neutralizing `[[name]]` links
  into prose plus a `## Sources` pointer (the sanctioned observations-log citation form);
  a **standing mechanical guard** — a `check:*` under `mise run check` (in
  `check-doc-links.sh` or a sibling) that flags any `[[name]]` token in a committed spec file
  **or `kickoff-brief.md`**, with a **named allowlist carve-out** for the pre-existing declined
  orchestration-fleet brief links, so a future writer skipping neutralization fails CI (F5)
  without reopening an already-signed brief's accepted exceptions (REQ-D1.1); the
  orchestration-fleet bundle's `[[…]]` citations
  reconciled via the expression-only amendment ritual (dated changelog entry, re-anchor).
  **Coordination:** the fleet bundle
  is `Ready` and may derive `Active`; land the fleet amendment's re-anchor as its own
  expression-only entry (the sanctioned lane) and sequence it so a concurrent fleet
  execution does not observe an anchor mismatch — check the fleet spec's In-progress state
  before amending, and if fleet execution is in flight, coordinate the re-anchor with it
  rather than racing it.
- **Done when:** the skill step exists; the standing `[[name]]` guard fails on a fixture
  spec file **and** a fixture `kickoff-brief.md` each carrying a `[[foo]]` token, passes on a
  clean bundle, and honors the allowlist carve-out (the declined fleet-brief links do not fail
  it), all under `mise run check`; a repo-wide search finds no *unallowlisted* `[[name]]` token
  in any bundle's four spec files or brief; the fleet bundle's
  `requirements.md` + `design.md` `[[…]]` citations are neutralized via the expression-only
  amendment ritual, its changelog records the amendment, and its brief anchor matches
  `scripts/spec-anchor.sh` output; `mise run check` passes.
- **Dependencies:** 5
- **Citations:** D-4 · REQ-D1.1, REQ-D1.2, REQ-D1.4
- **Estimated effort:** 1 day

### Task 7 — Organic completion-annotation stamping

- **Deliverables:** the level-triggered reconcile stamps
  `Completed · PR #<n> merged <YYYY-MM-DD>` in the same write that places a
  completion-evidenced task in `## Completed`, reusing the derivation's existing
  merged-PR evidence batch; honest no-remote degradation (date-only or no stamp);
  the stale `tasks-pr-sync.sh` implementation comment attributing annotation authoring to
  `/execute-task` corrected to reflect the reconcile-owned completion stamp (no edit to any
  `orchestration-concurrency` spec file — the change is additive to its contract, D-5).
- **Done when:** a fixture with merged-PR evidence yields the canonical string on the
  moved block; a no-remote fixture shows the degraded behavior and no invented PR
  number; non-completion annotations remain byte-for-byte; the five task-definition fields
  are untouched (the content anchor is unchanged, confirming no supersession); the
  `tasks-pr-sync.sh` comment reflects the new owner; `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-5 · REQ-E1.1, REQ-E1.2
- **Estimated effort:** 1 day

### Task 8 — Derived-content authoring guidance

- **Deliverables:** meta-spec (`doctrine/spec-format.md`) guidance edits: hand-drawn
  dependency graphs dropped from the `tasks.md` intro-prose description in favor of
  `Dependencies:` lines plus the on-demand graph view; kickoff-brief guidance gains the
  cite-don't-copy convention for derived figures; the completion-annotation vocabulary
  promoted from illustrative to **normative** — `Completed · PR #<n> merged <YYYY-MM-DD>` is
  the canonical completion annotation and `Completed · merged <YYYY-MM-DD>` its only degraded
  form (giving REQ-E1.2's "canonical format" an actual doctrine home).
- **Done when:** the meta-spec no longer suggests a drawn graph, names the cite-don't-copy
  convention, and states the normative completion-annotation format + its one degraded form;
  the meta-spec versioning note records the guidance change; `mise run check` passes.
- **Dependencies:** 5
- **Citations:** D-5 · REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.4
- **Estimated effort:** half day

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

(none yet)

## Deferred

(none yet)

## Out of scope

- Cross-repo / multi-target observation routing — the deferred accumulator redesign
  (see requirements Out of scope).
- Input-side parser consolidation (spec-parse and scope-grammar duplication entries).
- Retroactive edits to already-merged PR bodies.
- The escaper/sanitizer consolidation — extracted to the standalone
  `chore/esc-consolidation` (2026-07-02).
