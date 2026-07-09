# Output & Accumulator Hygiene — Kickoff Brief

## 1. Header

- **Spec path:** `specs/output-hygiene`
- **Spec commit at walkthrough start:** `d378eb6`
- **Walkthrough date:** 2026-07-02
- **Mode:** First activation (all four files Draft, no prior brief).
- **Validator outcome (pre-flight, Draft = warnings):** `spec-validate: 0 error(s), 0 warning(s)`.
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true` (defaults; no local override).
- **Working location:** spec branch `planwright/output-hygiene/spec`, clean tree.
- **Doctrine resolution:** all six rule docs resolved via planwright 0.2.6
  (`spec-format`, `discovery-rigor`, `validation-rigor`, `security-posture`,
  `decision-domains`, `interaction-style`); decision-domains catalog merged
  (ten domains).
- **Skill-drift note (pre-flight):** the invoked `/spec-kickoff` is the personal
  copy at `~/.claude/skills/spec-kickoff` (dated 2026-06-18), which still names the
  five-status lifecycle (Draft→Active on sign-off, draft-only PR). Current
  planwright doctrine (spec-format 0.2.6) is the six-status lifecycle: sign-off
  flips Draft→**Ready** and `mark_spec_pr_ready_on_kickoff` marks the spec PR
  ready. This run follows current doctrine (the skill subordinates named concepts
  to the doctrine docs). A `skill-drift(spec-kickoff)` observation is recorded at
  the maintenance step.

<!-- Section 8 (sign-off) and 9 (amendment log) are written by the sign-off flow. -->

## 2. Goal & glossary

**Goal (restated).** planwright emits artifacts that *others* read later (PR bodies,
commit subjects, committed spec prose, generated views) and accumulates shared state
across concurrent runs (the observations log, `tasks.md` annotations). Too many are
shaped for the *writer* (the emitting process), not the *reader* (a human weeks later,
a tool, or a concurrent sibling run). This spec makes every generated output
**human-first** and every shared accumulator **conflict-free and format-stable under
concurrency**. It is a hygiene / quality-of-artifact spec, not a new-capability spec.

**Organizing through-line (the "reader test").** Every REQ can be checked by asking
*"who reads this, and can they use it?"* No artifact optimized for its writer at the
reader's expense. This is the anchor sentence for later judgment calls.

**What it rules out** (Scope/Out): cross-repo / multi-target observation routing (a
separate deferred effort); input-side parser consolidation; fleet *attention* surfaces
(live watching is `orchestration-fleet`'s seam); retroactive edits to already-merged PR
bodies; the `tasks.md` *placement* derivation (consumed as-is — only the annotation
layer is touched); the escaper/sanitizer consolidation (extracted to a live sibling
chore).

**What it assumes.** Claude Code primitives only (patterns borrowed, tools not — e.g.
towncrier's news-fragment pattern, not the tool). History is never rewritten (this is
*why* several fixes must act at emit-time / read branch-scoped). The accumulator-taxonomy
class-3 invariants (durable home, canonical reader, drain surfacing, archive-on-consume)
are a fixed contract to preserve, not to redesign.

**Glossary — terms resolved:**

- **Human-first** — the reviewer's summary is above the fold and unwrapped; the exhaustive
  audit record is *preserved but collapsed*. It means *reordered and un-buried*, never
  *less information*. Invariant: REQ-A1.2 drops nothing from the audit record. Any future
  "trim the audit record" reading is out of bounds.
- **Conflict-free by construction** — distinct per-run filenames so two runs literally
  cannot touch the same bytes, versus a merge driver or append etiquette that only *tries*
  to avoid collision (and failed under real concurrency).
- **Named refresh owner** — a derived figure either cites its source (never copied) or has
  a specific mechanical trigger that re-stamps it (the level-triggered reconcile), so no
  human has to *remember* to refresh it.
- **Emit-time / branch-scoped** — guard the marker while the commit is still being authored
  (fixable), and only ever *read* it within the PR branch range, never mainline (squash
  relocates relic text there).
- **Delivered layout** — the tree an adopter gets when planwright is installed
  (writer-install or plugin), distinct from the in-repo layout. A doctrine file's relative
  links can be green in CI (in-repo) yet dead once installed, because sibling trees are not
  co-located there. This distinction is the whole point of D-4.

**Load-bearing scope edge (flagged, carried forward).** The delicate boundary is
*annotation layer vs. placement derivation*. This spec touches `tasks.md`'s **annotation**
layer (completion stamps, Task 7 / D-5) **additively** — filling the unowned
completion-annotation gap. (At §2 this was framed as a "narrow supersession" of an
`orchestration-concurrency` REQ-B1.1 clause; §4 corrected that: no such clause exists, the
change contradicts no requirement, and no `Superseded-by:` pointer is written — see §4.) It
does **not** touch the placement derivation or the content-anchor computation. During the
walkthrough this edge was re-confirmed against a live anchor-drift question: the anchor /
placement machinery (`spec-anchor.sh`, the reconcile's whole-block moves) is consumed
as-is; any anchor-drift fix is out-of-scope and routes to `spec-format` /
kickoff-lifecycle, not here. Execution must not read Task 7 as license to touch reconcile
placement or anchor logic.

Signed off: 2026-07-02

## 3. Requirements walkthrough

**Per-group outcomes.**

- **REQ-A — human-first PR bodies.** Intent confirmed: summary-first, full audit collapsed
  in `<details>`, no hard-wrap, one normative home in gate-wiring cited by `/execute-task`
  + `/self-review`. *Confirm (no edit):* the contract binds those two skills only, **not**
  `/spec-kickoff`'s own spec-PR body (kickoff bodies are already concise); PR bodies are
  GitHub-API content, not repo files, so markdownlint MD013 line-length does not fight the
  no-hard-wrap rule (REQ-A1.3).
- **REQ-B — conflict-free observations.** Intent confirmed. **Edit ① (applied):** the
  fragment filename's run-uniqueness was unpinned — D-1 + Task 1 now require a run-unique
  `<slug>` component (branch/task id, content-hash fallback for a bare `/spec-draft`
  session), so concurrent same-date runs cannot collide on a filename. Uniqueness is a
  by-construction filename property, matching the design's own thesis (collision-free by
  construction, not etiquette). Task 1 Done-when now asserts distinct filenames.
- **REQ-C — marker canonicalization.** Intent confirmed. *Confirm (no edit):* the
  branch-scoped-consumption rule (REQ-C1.4) is **normative / forward-looking** — a repo
  sweep found no script or skill that scans commit history for `[pending-sign-off]` today
  (it is emit-time + PR-body-checklist only across execute-task / polish / self-review).
  Task 4 correctly enumerates no consumer to patch. The emit-time-guard vs. CI-PR-title
  asymmetry is coherent: commit subjects are guarded pre-commit (fixable), PR titles are
  editable so a CI rejection there is never unfixable-red.
- **REQ-D — reference integrity.** Intent confirmed. **Edit ② (applied):** the doctrine
  link allowlist was narrower than reality — doctrine has 5 non-sibling relative links
  (4× `../scripts/`, 1× `../skills/`). Verified against `install.sh`: `doctrine/`,
  `config/`, and `scripts/` are all co-located under `<root>/planwright/` in both the
  plugin and writer-install layouts, while `../skills/` does **not** ship as a doctrine
  sibling. So D-4 + Task 5 + REQ-D1.3 now **permit `../scripts/`**; the `../skills/`
  guard-catalog link is the sole real violation. **Edit ③ (applied):** the `[[name]]`
  sweep (Task 6) is scoped to the **four spec files** of any bundle; already-signed
  kickoff-brief bodies are append-only and out of scope (REQ-D1.2 keeps new briefs clean
  going forward). This resolves the collision with the orchestration-fleet brief, whose
  own lens pass consciously declined its brief-body `[[ ]]` links.
- **REQ-E — derived-content hygiene.** Intent confirmed, no edit. Canonical annotation
  format `Completed · PR #<n> merged <YYYY-MM-DD>` aligns with spec-format's existing
  conventional annotation value; the completion-stamp change is **additive** to
  `orchestration-concurrency` (not a supersession — resolved in §4), touching only the
  unowned annotation gap, not placement/anchor. This bundle's own `tasks.md`
  conforms to REQ-E1.4 from birth (no drawn graph).

**Consolidated spec-edit list (applied in place, Draft):**

1. `design.md` D-1 + `tasks.md` Task 1 (deliverable + Done-when): run-unique fragment name.
2. `design.md` D-4 + `tasks.md` Task 5 (deliverable + Done-when) + `test-spec.md` REQ-D1.3:
   permit `../scripts/` in the doctrine link allowlist; `../skills/` is the sole violation.
3. `tasks.md` Task 6 Done-when: `[[name]]` sweep scoped to the four spec files; briefs
   append-only / out of scope.
4. `requirements.md` `## Changelog`: dated kickoff-walkthrough entry recording 1–3.

All edits are clarifications or one design-rule widening; no REQ meaning was reversed. They
change spec-file bytes, so the content anchor is (re)computed at sign-off after all edits.

Signed off: 2026-07-06

## 4. Design walkthrough

**Reconciled ledger — every D-ID accounted for:**

| D-ID | Decision | Status | Note |
| --- | --- | --- | --- |
| D-1 | Fragment files + single-writer consolidation | **Amended** | Edit ①: run-unique fragment name. Rationale intact. |
| D-2 | PR-body contract home in gate-wiring | **Confirmed** | Core per customization boundary. Flags the uncatalogued human-comprehension / information-UX domain → §7 risk row. |
| D-3 | Marker: end-of-subject / emit-time / branch-scoped | **Confirmed** | Merge-strategy matrix complete; emit-vs-CI asymmetry coherent. |
| D-4 | Reference integrity by restriction + lint | **Amended** | Edit ②: `../scripts/` permitted (verified sibling). Rationale intact. |
| D-5 | Derived-content owners (cite-or-regenerate) | **Amended** | Resolution (A): completion-stamp reframed additive, not a supersession (finding below). |

**§4 finding — the D-5 "supersession" targeted a non-existent clause (resolved, (A)).**
D-5 item 1, Task 7, and the Out-of-scope note claimed the completion-stamp change *"narrowly
supersedes `orchestration-concurrency` REQ-B1.1's annotations-preserved-byte-for-byte
clause."* Grounded check: `orchestration-concurrency/requirements.md` has **zero**
occurrences of "annotation," "preserved," or "byte-for-byte." REQ-B1.1 is placement
sole-writer + atomic write; its byte-for-byte guarantee (via the `tasks-pr-sync.sh`
implementation) is over the **five definition fields** — the anchor-stability contract,
which output-hygiene does not touch. The "annotations are `/execute-task`'s to write"
invariant is an **implementation comment**, not a REQ, and the completion annotation is an
**unowned gap** (observations log 2026-06-29: "nobody refreshes completion annotations").

**Resolution (A), applied (Diego, 2026-07-06):** reframe the change as **additive** to
`orchestration-concurrency`'s contract — it contradicts no requirement. **No cross-bundle
`Superseded-by:` pointer is written** (Task 7's old deliverable pointed at a non-existent
clause). Task 7 instead corrects the stale `tasks-pr-sync.sh` implementation comment as
part of its own delivery; no `orchestration-concurrency` spec file is edited. Edits landed
in `design.md` D-5, `tasks.md` Task 7 (deliverable + Done-when), `requirements.md`
Out-of-scope + Changelog, and the brief's §2/§3 forward-references. Validator: 0/0 after.

**Consolidated spec-edit list — §4 addendum** (continuing §3's list; items 5–7 of the
overall sequence):

1. (edit 5) `design.md` D-5 item 1: supersession → additive framing; Task 7 corrects the
   `tasks-pr-sync.sh` comment instead of writing a pointer.
2. (edit 6) `tasks.md` Task 7 deliverable + Done-when: drop the `Superseded-by:` pointer;
   add the comment correction and the "definition fields untouched / anchor unchanged" check.
3. (edit 7) `requirements.md` Out-of-scope reframed additive; `## Changelog` §4 entry added.

Signed off: 2026-07-06

## 5. Verification approach

**Coverage mix (21 REQs — B1.5 added in the §8 lens pass).** Mechanical → `[test]` (B1.1,
B1.3, B1.5, D1.3, E1.2, plus the `check:links` / `check:specs` gate entries); prose-contract
→ `[design-level]` + `[manual]`-on-next-emission (all of A, C1.2, D1.2, E1.3); several mixed
(`[test + design-level]`: B1.2, B1.4, C1.1, C1.3, C1.4; `[test + manual]`: D1.1, D1.4). The
split is honest — a fixture asserting "this markdown is concise" would be verification
theater. **(§8 correction:** the §5 "no marker consumer exists / REQ-C1.4 dead path"
finding was **reverted** by the lens pass — a consumer does exist. See §8 Cluster 3.)

**Verification ownership (grounded).** All `[test]` entries are shell suites under
`tests/*.sh`, run by the `mise run check` aggregate, which is the single step in
`.github/workflows/ci.yml` on every PR. The aggregate = `test` + `lint:shell` + `lint:fmt`
+ `lint:md` + `lint:yaml` + `lint:commits` + `check:links` (D-4 lint) + `check:specs`
(validator) + options-reference / ledger / gitleaks. So every mechanical REQ is CI-run
**provided its task ships a `tests/*.sh` suite** (Tasks 1, 2, 4, 5, 6, 7 each owe one).
`[manual]` sweeps are the human's, exercised opportunistically on the next real emission of
each skill.

**Dead-path check — one found and fixed (§5 resolution (a)).** REQ-C1.4 was pure `[test]`
but one of its two fixtures ("a squash-body relic marker … is not counted by
marker-consuming tooling") had **no code under test** — no marker-consuming tooling exists
(§3) and Task 4 builds none (`--marker` validates a *subject*, it does not scan a range).
Retagged `[test + design-level]`: PR-title rejection stays a real test; the branch-scoped
consumption rule is design-level doctrine until a consumer is built. No other dead paths:
E1.2's reconcile fixture is CLI-drivable (`tasks-pr-sync.sh reconcile`), D1.4's
`check:links`-green is runnable, B1.1/B1.3 consolidation fixtures are Task 1's routine.

**Carried to §7 (risk register).** The `[manual]` sweeps (A1.1–1.3, C1.2, D1.1/1.2/1.4,
E1.3) have **no named owner or trigger** beyond "the next real emission" — a standing
verification-theater risk if never exercised.

Signed off: 2026-07-06

## 6. Task graph

Reconstructed from the authoritative `Dependencies:` lines (no drawn graph — REQ-E1.4 from
birth):

```
Task 1 (2d) ── Task 2 (1d)              critical path = 3d
Task 5 (½d) ─┬─ Task 3 (1d)
             ├─ Task 4 (1d)
             ├─ Task 6 (1d)
             └─ Task 8 (½d)
Task 7 (1d)  [isolated: no deps, no dependents]
```

**Effort-weighted critical path: Task 1 → Task 2 = 3 days** (confirms the intro). All other
chains are ≤1.5 days. **Parallelism:** three roots start at once (1, 5, 7); Task 5's half
day clears before the critical path does, unlocking 3/4/6/8 — peak width ≈6 in flight. Task
2 is the only unit gated behind the long pole (Task 1). Guard-first (Task 5 before the
doc-writers) costs effectively nothing.

**Deliberate non-edges (recorded so nobody "fixes" them):**
- **Task 7 ⊥ everything** — no deps, no dependents. Reconcile-adjacent to Task 2 on
  `tasks-pr-sync.sh` (possible merge-adjacency, same class as the design's esc-consolidation
  concurrent-edit note), but not a logical dependency.
- **Task 2 ⊥ Task 5** — Task 2 writes no `doctrine/` cross-links, so the guard-first edge
  does not apply.

**Guard-first edge criterion (recorded, leave-as-is — Diego, 2026-07-06).** The edges
3/4/6/8 → 5 are *not* "every doc-writing task depends on Task 5." Task 1 also writes doctrine
(the accumulator-taxonomy amendment) but is **exempt** (critical-path root; its amendment
adds no cross-tree links); Task 6 does **not** write `doctrine/` (skill step + fleet
*spec-file* amendment) but is **included** for uniformity. The operative criterion is
"plausibly adds a doctrine cross-link" (3, 4, 8) plus Task 6 for uniformity. Harmless either
way — CI's `check:links` sweeps the whole repo once Task 5 merges, independent of edges. Not
tightened, by decision.

Signed off: 2026-07-06

## 7. Risk register

**Decision-domains gap check (10 merged domains walked; no touched-but-undecided domain —
the halt condition did not fire).**
- **Decided:** data-storage (D-1 fragment layout), concurrency (D-1 single-writer +
  collision-free naming), api-surface (D-1/D-2 consumed surfaces, REQ-B1.4), observability
  (drain surfacing preserved).
- **Declined:** dependency-adoption (news-fragment *pattern* borrowed, no tool added).
- **Refinements to the design's "untouched" list:** queues-async is *touched and decided*
  (D-1 idempotency / ordering / append-before-delete crash safety), not untouched;
  secrets-config is *partially touched and decided* via the data-hygiene re-screening.
- **Genuinely untouched:** caching, auth, deploy-migration (lightly touched — row 3).
- **Catalog gap (not a spec gap):** the spec's central domain, human-comprehension /
  information-UX, has no catalog entry (D-2 flags it). Deliberate non-edge → observation for
  the catalog's own amendment (D-39 self-amend path).

**Risk rows (all accepted; mitigations shown):**

| # | Risk | Mitigation / early signal | Disposition |
| --- | --- | --- | --- |
| 1 | `[manual]` test-spec entries are a **write-only accumulator** — no named reader, no drain ritual (violates accumulator-taxonomy's "every accumulator drains" invariant); verification depends on someone remembering the next emission. **Doctrine-level, generic to all specs.** | design-level halves are CI-checked; exercise the manual halves on the next real emission of each skill | **Accepted risk + doctrine observation** (seed a `/drain` extension surfacing un-exercised `[manual]` entries per spec). Not patched spec-locally — would mis-level a systemic gap. |
| 2 | Two consolidation writers (`--bookkeeping` + `/spec-draft`) race on the log | advisory lock + idempotent + append-before-delete; Task 1 concurrent-writer test surfaces it | Accepted |
| 3 | First post-Task-7 reconcile **rewrites completion annotations fleet-wide** across active specs' `tasks.md` (canonicalization rollout) | level-triggered idempotent; non-completion annotations byte-for-byte; watch the first reconcile diff | Accepted |
| 4 | This bundle's own task PRs (+ the parallel esc-consolidation chore) conflict on `opportunities.md` / `tasks-pr-sync.sh` | live demonstration of REQ-B1.1; second-to-merge resolves a small conflict (design concurrent-edit note) | Accepted |
| 5 | **Task 6 ↔ orchestration-fleet:** fleet is `Ready`; if it derives `Active` before Task 6's re-anchor lands, the fleet's freshness gate could halt on an anchor mismatch | **Applied edit:** Task 6 coordination note (check fleet In-progress state; sequence the expression-only re-anchor, don't race it) | **Mitigated (spec edit applied)** |
| 6 | Uncatalogued human-comprehension / information-UX domain (see gap check) | observation for the catalog's self-amendment | Accepted + observation |

**Cold-review:** no additional risks surfaced. **No open question remains** — every
walkthrough fork (①②③, D-5→(A), C1.4→(a), graph leave-as-is, §7 dispositions) is resolved to
a decision or an explicitly accepted risk.

Signed off: 2026-07-06

## 8. Sign-off

**Mode:** first activation, meaning-class. **Lens review pass scope:** full bundle
(first activation). **Path taken:** fan-out — six read-only sub-agents covering all nine
canonical lenses (severity-pruning forbidden; `none` requires a reason). The pass found
genuine spec-bugs the guided walkthrough missed, **including a reversal of the §5 dead-path
fix and a structural non-conformance the validator was blind to** — which is exactly the
last-line-of-defense role this pass plays (D-45).

**Canonical lens-coverage table (discovery counts):**

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness / logic / edge cases | 4 | consolidation crash-dup (1.1), spec-draft-on-branch (1.3), ordering vs no-reorder (1.5), marker-mode polarity (clarified in D-3/Task 4) |
| Security | 4 | slug validation/containment (2.1), re-screen contradiction (2.2), no REQ/test (2.3), echo-discipline (2.4) |
| Error handling / failure modes | 2 | crash→duplicate (1.1), no-remote annotation format undefined (5.4) |
| Performance | 1 | chronological-insert vs append-only (1.5); otherwise clean (no per-item cost — annotation stamp reuses the derivation batch) |
| Concurrency / state | 5 | lock-scope (1.2), crash-dup (1.1), spec-draft branch collision (1.3), slug not run-unique (1.4), sub-day ordering (1.5) |
| Naming / readability / structure | 3 | `design.md` H2/period non-conformance (3.2), changelog newest-first (3.3), `queue/` name (6.3, kept) |
| Documentation | 3 | class-3 4-tuple vs 3-tuple (6.4), dangling 2026-06-16 source (5.1), canonical-format no doctrine home (5.5) |
| Tests / verification | 5 | marker consumer exists — §5 was wrong (3.1), `[[name]]` no standing guard (4.1), 2 missing test assertions (4.2/4.3), A1.4 untestable (accepted, D-2) |
| Cross-file consistency | 5 | brief §5 tag (5.3), dangling source (5.1), REQ-B1.1 attribution (3.4), `D-21` unqualified (5.2), REQ-D1.1 blanket vs scoped (4.4) |

**Findings validated** per validation-rigor (the reversing/structural ones got direct
ground-truth checks: the marker consumer against `gate-wiring.md`/`self-review`; the
`design.md` non-conformance against the validator regex + a sibling; class-3 against
`accumulator-taxonomy.md`). **Two validated out** as non-issues: Last-reviewed staleness
(handled by this flip) and the Task 2 drain fixture (the surface already exists in
`drain-gates.sh`).

**Dispositions — six clusters, all resolved with Diego (2026-07-06/07):**

- **Cluster 1 — D-1 consolidation soundness → reworked in-session (1.1–1.5).** Single
  default-branch consolidation writer (`/spec-draft` mines read-only); one atomic
  append+delete commit; idempotent + regenerate-from-current-state on conflict; a dedicated
  global `_observations` advisory lock (perf only); append-in-consolidation-order (kills the
  reorder contradiction); per-run-nonce fragment name `<date>-<taskid>-<run-nonce>`
  (**supersedes edit ① from §3**, which relied on task-id alone). Applied to D-1, REQ-B1.1/
  B1.3, Task 1/2.
- **Cluster 2 — security → REQ added + fixes (2.1–2.4).** New **REQ-B1.5**
  (charset-validate-before-path-use, containment check, clean refusal, printable-sanitize)
  mirroring `orchestration-concurrency` REQ-F1.1; Task 1 + a `[test]` entry; the wrong
  "reserved-accumulator rule" citation dropped; the re-screen-on-boundary claim corrected to
  write-time-only (consolidation moves text verbatim — REQ-B1.3).
- **Cluster 3 — my errors → applied (3.1–3.4).** §5 C1.4 dead-path **reverted** (the
  pending-sign-off checklist regeneration is the consumer); `design.md` restructured to
  conformant `### D-N:` + colon labels (the validator's `^### D-` regex was blind to the H2
  form → **logged as an observation**); Changelog reordered to chronological; D-5's residual
  REQ-B1.1 byte-for-byte attribution retargeted to the content-anchor doctrine.
- **Cluster 4 — coverage → applied incl. a standing guard (4.1–4.4).** A mechanical
  `[[name]]` `check:*` guard added (Task 6, REQ-D1.1) so the prohibition has a CI reader;
  test-spec REQ-B1.1 (distinct-filename) and REQ-E1.2 (anchor-unchanged) assertions added;
  REQ-D1.1 wording reconciled with the spec-files-only sweep + append-only-brief carve-out.
- **Cluster 5 — citation/format → applied (5.1–5.5).** Sources gains the 2026-06-16
  (catalog-gap) entry; `D-21` → `bootstrap D-21`; brief §5 tags corrected; REQ-E1.2 degraded
  string pinned (`Completed · merged <YYYY-MM-DD>`); the canonical annotation format gets a
  doctrine home (Task 8).
- **Cluster 6 — scope/naming → wording fixes, `queue/` kept (6.1–6.5).** Goal + "collisions
  impossible by construction" claims scoped to the write side; two Sources relabeled
  consumed; class-3 wording softened to the 3-tuple; `queue/` retained.

**Re-validation after applying:** `spec-validate` 0/0 (and the decisions are now H3, so the
validator actually checks them — previously blind). All 21 REQs carry test-spec coverage.

Class: meaning
Lens-pass: recorded above (this section, §8), full-bundle fan-out, findings dispositioned 2026-07-07.
Status flip: Draft → Ready on all four spec files; Last reviewed → 2026-07-07. Validator 0/0 under Ready enforcement.
Anchor: `b4f1bf1216ea19818d736d84f9de892b87e785d8` — computed as
`scripts/spec-anchor.sh specs/output-hygiene`

Signed off: 2026-07-07

## 9. Amendment log

### Delta re-walkthrough — scope-down: observations recording carved out (2026-07-08)

**Mode:** delta re-walkthrough on the Ready spec (post-merge of spec PR #124; nothing
dispatched), declared by the scope-down brief; run from spec commit `1af51af`. Validator
at pre-flight: 0/0; freshness check: recorded anchor `b4f1bf12…` matched recomputation
(no staleness — the delta is human-declared).

**Trigger.** The conflict-free observations-recording concern (REQ-B, D-1, Tasks 1–2)
proved unsound under the PR-only, squash-merge, never-auto-merge regime across three
redesigns. (The two §9 delta entries that recorded those redesigns lived only on the
pre-#127 spec branch, discarded when PR #127 was closed and its branch deleted — they
never merged; the failure history is recorded in `specs/observation-recording`'s Goal
and Sources.) The concern was carved into `specs/observation-recording` (merged Ready
2026-07-08, PR #128), whose REQ-E1.4 / D-9 declare the supersession and whose scope
fully owns the fragment substrate, conflict-freedom invariants, readers/drain/class-3
contract, security guards, and migration of the existing log (coverage cross-checked
REQ-by-REQ against that bundle's In-scope and test-spec; no gap). This entry performs
the carve-out amendment that observation-recording's Deferred coordination gate awaits;
landing this PR satisfies the gate as worded (the human clears the Deferred entry on a
later drain pass — dispatch of Tasks 1–2 is meanwhile impossible via section membership).

**Delta applied (mechanism per the meta-spec's post-merge supersede ritual):**

- REQ-B1.1–B1.5 marked superseded in place, bodies frozen, each pointing at its
  observation-recording successor: B1.1 → REQ-A1.1 (with REQ-B1.1/B1.3), B1.2 → REQ-C1.1,
  B1.3 → REQ-E1.1, B1.4 → REQ-C1.2 (with REQ-C1.3), B1.5 → REQ-D1.1 (with REQ-D1.3).
  Pointer form: `**Superseded-by: REQ-<id> (observation-recording)**` — trailing
  namespace qualifier because the validator anchors the supersede marker on the literal
  `Superseded-by: REQ-` prefix; D-pointers use the namespace-first precedent form.
- D-1 marked `**Superseded-by: observation-recording D-1**`, record frozen; the design
  intro and the cross-cutting section carry amendment notes scoping what remains live.
- Tasks 1–2 moved whole (definition fields intact, `Status: superseded` annotations) from
  `## Forward plan` to `## Out of scope` — kept as frozen records per the stable-ID rule;
  never dispatched, excluded from Done determination by section membership (verified
  against the reconcile's status derivation and the selector).
- Scope: In-scope bullet dropped; Out-of-scope pointer bullets added (requirements +
  tasks); the Goal's accumulator claim narrowed to the retained `tasks.md` annotation
  layer. test-spec `## REQ-B` entries removed with the group (tombstone note; verification
  lives in observation-recording's test-spec — every live REQ here keeps exact-ID
  coverage). tasks.md intro updated; dated Changelog entry names every superseded ID.

**§6/§7 figures superseded by this delta:** the task-graph section's effort figures are
now historical — the live graph is Task 5 → {3, 4, 6, 8} with Task 7 standalone, two
roots (5, 7), peak width ≈5, critical path Task 5 → any of {3, 4, 6} = 1.5 days
(replacing Task 1 → Task 2 = 3 days; the §6 guard-first criterion's Task 1 exemplar is
likewise historical). Risk register rows 2 and 4's consolidation-writer/`opportunities.md`
collision content moved with the concern (now governed by observation-recording); row 5
(Task 6 ↔ fleet re-anchor) stands unchanged.

**Lens pass (delta-scoped, fan-out — nine read-only sub-agents, one per canonical
lens; severity-pruning forbidden):**

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness / logic / edge cases | 3 | cross-cutting banner self-contradiction (fixed); domain-walk and concurrent-edit-note staleness (covered by the reworded banner); graph arithmetic and supersession mapping verified correct |
| Security | none | REQ-B1.5's four elements each verified against a live observation-recording successor (REQ-D1.1/D1.3/D1.4) down to test fixtures; new prose hygiene-clean |
| Error handling / failure modes | 2 | section-blind in-flight accounting → phantom-slot hazard (hypothetical — no evidence exists or can be framework-minted; declined as spec edit, routed to observation); anchor/reconcile/drain/validator all verified clean on the new layout |
| Performance | 3 | intro arithmetic verified correct; §6's 3-day critical path, roots {1,5,7}, peak ≈6 stale (superseded by this entry, above) |
| Concurrency / state | none | gate satisfied on landing; no governance gap (baseline single-file doctrine governs until observation-recording executes); Done derivation correct via section membership; stale `observation-routing` branch flagged to the human |
| Naming / readability / structure | 5 | pointer-form deviation (declined — validator-forced, documented in Changelog); rationale relocated to Changelog (fixed); markers moved above Cites lines (fixed); task-blocks-in-Out-of-scope + test-spec tombstone (declined with rationale, doctrine gap → observation); markdownlint 0 errors |
| Documentation | 1 | no live doc surface misleads (queue design never propagated — Tasks 1–2 never dispatched); the flagged missing §9 amendment entry is this entry |
| Tests / verification | none | all 16 live REQs covered exact-ID; no stale fixtures; validator coverage exemption for superseded REQs confirmed by design; no verification orphan |
| Cross-file consistency | 3 | Goal head-claim over-promise (fixed); banner tension (fixed with correctness lens); bare D-20 qualified to bootstrap D-20 (fixed); mirrors/references/counts/mapping all verified |

**Dispositions:** 6 findings applied as spec edits this entry (Goal claim narrowed;
cross-cutting banner made precise; three bare D-20 citations qualified; five supersede
markers reordered above their Cites lines; pointer-form rationale relocated to the
Changelog); 3 declined with recorded rationale (pointer form — validator-forced;
task blocks in Out of scope and the test-spec tombstone — no sanctioned alternative, a
spec-format doctrine gap); 2 routed to the observations log (the doctrine gap; the
section-blind in-flight accounting), appended this run; the stale-§6/§7-figures findings
are resolved by the superseding paragraph above (signed sections are append-only). No
finding left undispositioned.

**Re-validation after applying:** `spec-validate` 0 errors / 0 warnings under Ready
enforcement; markdownlint 0 errors; `Last reviewed:` 2026-07-08 on all four files;
Status stays Ready (no flip on a delta re-walkthrough).

Class: meaning
Lens-pass: recorded above (this entry, §9), delta-scoped fan-out, findings dispositioned 2026-07-08.
Anchor: `8d37221962ead5104868dafff88636da992608e6` — computed as
`scripts/spec-anchor.sh specs/output-hygiene`

Signed off: 2026-07-08

### Delta re-walkthrough — anchor reconciliation (2026-07-09)

**Mode:** delta re-walkthrough on the Ready spec (post-merge of scope-down PR #129; nothing
dispatched), triggered by the execution freshness gate: every task dispatch halts on the
anchor mismatch until this entry lands. Run from spec commit `1993673`; scope and the
expression-only classification declared by the human via the fleet-run relay (2026-07-09).
Validator at pre-flight: 0 errors / 0 warnings under Ready enforcement.

**Trigger.** The 2026-07-08 entry above records anchor `8d372219…`, computed before that
entry's post-review fix (panel pass, same date: the cross-repo-routing Out-of-scope
bullet's "this spec fixes intra-repo recording only" clause reworded to point at
`specs/observation-recording`) was applied, and both landed in the same squash (PR #129) —
so the recorded anchor never matched any committed state of the bundle. Verified this run,
corroborating the Task-7 execution worker's three-way diagnosis: recomputation over the
merged bundle at spec commit `1993673` yielded `02e6f3a28df866ac1f166eeaba6dc2c1884440b0`,
and git history shows no spec-file commit since the entry was recorded, so the staleness
was baked into the recording commit itself.

**Delta.** No spec content change: the merged bundle is correct and intended. The reword is
a gap-fill consistent with the signed scope-down's accepted decisions (the carve-out
already assigns intra-repo recording to `specs/observation-recording`), which is the
REQ-A3.3 definition of expression-only. This run edits only the `requirements.md`
Changelog (dated 2026-07-09 entry) and its `Last reviewed:` line — both anchored content,
so the anchor below is recomputed after those edits, not the pre-edit `02e6f3a2…`. Lens
pass: skipped (expression-only, per REQ-A3.3 and the spec-format amendment ritual).

**Re-validation after applying:** `spec-validate` 0 errors / 0 warnings under Ready
enforcement; `Last reviewed:` 2026-07-09 on `requirements.md` (the only file touched);
Status stays Ready (no flip on a delta re-walkthrough).

Class: expression-only
Changelog: `requirements.md` `## Changelog`, 2026-07-09 entry (this run); the underlying
reword is recorded in that changelog's 2026-07-08 entry, post-review-fix line.
Anchor: `4cb5688d30b20d8baca91e9da958845593aa9bc6` — computed as
`scripts/spec-anchor.sh specs/output-hygiene`

Signed off: 2026-07-09
