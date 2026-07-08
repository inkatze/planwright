# Observation Recording — Kickoff Brief

## 1. Header

- **Spec:** `specs/observation-recording/`
- **Spec commit at walkthrough start:** `b1b802fc54ccb14d221a9c1ba02371f1ca26766e`
- **Walkthrough date:** 2026-07-08
- **Mode:** first activation (Status Draft, no prior brief)
- **Validator:** `scripts/spec-validate.sh specs/observation-recording` — 0 errors, 0 warnings (Draft enforcement)
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true` (defaults; no local override)
- **Rule docs:** all six resolved from the repo's own `doctrine/` (this repo is planwright; `PLANWRIGHT_ROOT` set to the worktree)
- **Lifecycle:** sign-off flips Draft→Ready per spec-format v1; first task dispatch later derives Active

## 2. Goal & glossary

**Restatement.** Today every recording skill
appends observations to one committed file
(`specs/_observations/opportunities.md`) and consumption prunes lines out of
it into `archive.md`. Under fleet concurrency on a PR-only, squash-merge,
never-auto-merge `main`, no merge rule can reconcile a file that concurrent
PRs both append to and prune. Three prior designs failed: union-of-appends
resurrects deletions (10 resurrected duplicates sit in production's log as
live proof); fragment-identity idempotency was unspecified (entries carried
no id to dedup on); a single-writer reconcile cannot atomically write a
protected main. This spec stops trying to reconcile the shared file and
dissolves it, on reno's model: each observation becomes its own fragment
file `<YYYY-MM-DD>-<slug>-<8hex-uid>.md` under
`specs/_observations/entries/`; consumption appends a `Consumed-by:` line
inside the fragment and then moves it to `archive/`, keyed on the UID; the
chronological log is demoted to an on-demand, byte-deterministic render that
is never committed. Concurrent adds are distinct filenames by construction;
concurrent consume-vs-add is a disjoint-file move; the class-3 accumulator
contract (durable home, `/spec-draft` as canonical reader, drain surfacing,
archive-on-consume) is preserved on the new layout.

**Rules out:** adopting any external changelog/news-fragment tool (reno's
pattern is borrowed, the dependency declined); bulk-converting the ~156
legacy entries; multi-repo routing (`observation-routing`'s domain);
re-solving output-hygiene's other four concerns; the reconcile-PR pattern.

**Assumes:** the PR-only/squash/protected-main regime persists; the frozen
legacy log drains gradually through normal mining (annotated in place,
accepting small residual conflict exposure on a shrinking, low-traffic
file); output-hygiene's Tasks 1–2 stay undispatched until its carve-out
amendment lands (the Deferred coordination gate).

**Glossary (implicit terms surfaced):**

- **Fragment** — one observation, one file, under `entries/` (live) or
  `archive/` (consumed).
- **UID** — 8 lowercase hex chars from a system entropy source; the entry's
  durable identity and its `obs:<uid>` citation key; survives slug rename,
  content edit, and the archive move. The slug is cosmetic and renameable.
- **Frozen legacy file** — `opportunities.md` post-migration: freeze header,
  no new appends, drains in place via `— consumed-by:` annotations.
- **Unconsumed legacy entry** — a frozen-log line with no consumed-by
  annotation.
- **Recording skills** — the ten named in REQ-E1.3 (`/spec-draft`,
  `/spec-kickoff`, `/execute-task`, `/self-review`, `/polish`, `/drain`,
  `/orchestrate`, `/builder`, `/resume`, `/spec-walkthrough` — every
  shipped skill carries at least the drift-log write).
- **Render** — the derived chronological view: stdout only, date-then-UID
  order, `--archived` opt-in, legacy interleave while unconsumed legacy
  entries exist.

**Ground-truth checks run at walkthrough start:** the "four F1–F5 entries"
wording is accurate (five findings in four log entries; F3+F5 share one;
verified at commit `7ac4c2c`). The live log holds 167 entry lines in this
worktree = the spec's 166 plus this branch's own drift-observation append.
`archive.md` carries 12 consumed-by records against the "~10 resurrected
duplicates" estimate; the migration task verifies the pairing line-by-line
(REQ-E1.1's `[manual]` half), so the estimate is not load-bearing.

**Resolution recorded:** the seed brief
(`specs/_pending/observation-recording.md`) and the research synthesis
(`specs/_pending/observation-recording-research.md`) were untracked files in
the main checkout while being cited as Sources. Decision (2026-07-08):
commit both on this spec branch so the citations resolve durably on `main`.

Signed off: 2026-07-08

## 3. Requirements walkthrough

**REQ-A — Fragment recording substrate.** Intent confirmed: one fragment
per observation, strict composite filename grammar, one shared helper.
Probes resolved without a spec edit: the helper *refuses* an invalid slug
rather than auto-slugifying (D-7's refusal posture — no transform
ambiguity, validation stays single-path); the helper *mints the date
itself* (today), no date argument (no backfill exists to justify one; bulk
conversion is out of scope). Two probes produced decisions (below).

**REQ-B — Conflict-freedom invariants.** Confirmed: adds are distinct
filenames by construction, consume is a single-file move, the view is
never committed. The test-spec's two-branch merge fixtures exercise
exactly the claimed invariants; no gaps.

**REQ-C — Readers, drain, class-3 contract.** Confirmed: mining reads live
fragments + the frozen legacy file's unconsumed lines as one candidate
set; drain names both surfaces while the legacy file drains; render is
byte-deterministic. Probe resolved: the consumer in
`Consumed-by: specs/<spec>` is always a spec (`/spec-draft` is the sole
canonical reader), so no consumer-identity grammar edge exists.

**REQ-D — Security, hygiene, guards.** Confirmed: validate/contain/refuse
(carried from orchestration-concurrency REQ-F1.1), content-is-data for
every reader, standing `check:obs` CI guard. The guard's body-shape
underspecification became decision 2 below.

**REQ-E — Migration and coordination.** Confirmed: dedup-then-freeze, the
Tasks 5+6 one-unit cutover (REQ-E1.2), ten-skill reconciliation, and the
explicit supersession of output-hygiene REQ-B / D-1 / Tasks 1–2 with the
Deferred gate. The `archive.md` 12-consumed-by vs "~10 duplicates" delta
is absorbed by REQ-E1.1's line-by-line `[manual]` verification.

**Decisions taken (2026-07-08):**

1. **UID uniqueness spans `entries/` + `archive/`.** The as-drafted
   fail-on-exists checked only the live filename; an archived fragment's
   UID could be re-minted, making `obs:<uid>` match two files and breaking
   REQ-A1.5's exactly-one-file guarantee. The collision check now keys on
   the UID (`*-<uid>.md`) across both directories; full-filename
   fail-on-exists remains the final write guard.
2. **Fragment body is strict: entry line + recognized metadata + blanks.**
   Free prose rides inside the entry line (the legacy convention). Keeps
   one-entry-per-file mechanically checkable and readers line-oriented.

**Consolidated spec-edit list (all applied in place; Draft bundle):**

- `requirements.md` REQ-A1.3 — UID-uniqueness scope widened to both
  directories; citation updated.
- `requirements.md` REQ-A1.4 — body strictness added; citation updated.
- `requirements.md` Changelog — dated kickoff-walkthrough entry added.
- `design.md` D-2 — collision-check scope + structural-guarantee rationale.
- `design.md` D-3 — body strictness sentence added to the content contract.
- `test-spec.md` REQ-A1.3 — archived-UID collision fixture added.
- `test-spec.md` REQ-A1.4 — free-prose-body rejection fixture added.
- `tasks.md` Task 1 — done-when includes the archived-UID collision case.
- `tasks.md` Task 2 — seeded violations include a free-prose body.

Signed off: 2026-07-08

## 4. Design walkthrough

Ledger — every D-ID accounted for:

| D-ID | Disposition | Notes |
| --- | --- | --- |
| D-1 (reno model) | Confirmed | Rationale intact; production evidence (resurrected duplicates) re-verified at walkthrough start. |
| D-2 (filename grammar) | Amended | Kickoff decision 1: collision check keys on the UID across `entries/` + `archive/`; full-filename fail-on-exists stays as the final write guard. |
| D-3 (annotate-then-move) | Amended | Kickoff decision 2: body strictness (entry line + recognized metadata + blanks) added to the content contract. |
| D-4 (render + drain) | Confirmed | Legacy interleave is the only parsing surface added; fixture-covered. |
| D-5 (dedup-then-freeze) | Confirmed | Escalated-and-decided in drafting (deploy-migration domain); rollback = revert the migration PR. |
| D-6 (helper + guard) | Confirmed | Note: in adopter repos the helper resolves plugin-relative (`PLANWRIGHT_ROOT`/`CLAUDE_PLUGIN_ROOT` chain) while the fragment directories are the *host repo's* — Task 1 anchors `specs/_observations/` at the host repo root (cwd), never the plugin root. |
| D-7 (validate/contain/refuse) | Confirmed | Carried unchanged from orchestration-concurrency REQ-F1.1. |
| D-8 (doctrine home) | Confirmed | The skill-drift evidence is the observation this branch already logged (`b1b802f`). |
| D-9 (supersession + adjacency) | Confirmed | Deferred gate carries the coordination; observation-routing adjacency recorded, not folded. |

No design decision contradicts a walked requirement; no inconsistency
halt was triggered.

Signed off: 2026-07-08

## 5. Verification approach

- **Coverage mix (21 REQs):** `[test]` shell fixtures under `tests/`,
  run by `mise run check` in GitHub Actions (`ci.yml`); `[design-level]`
  artifact checks and mechanical greps folded into task done-whens
  (chiefly Task 5's zero-matches grep); `[manual]` five items.
- **Ownership:** CI owns every `[test]` path. The human owns the
  `[manual]` sweep: (1) line-by-line dedup review at the Tasks 5+6
  migration PR (REQ-E1.1); (2) the output-hygiene carve-out amendment and
  holding its Tasks 1–2 undispatched (REQ-E1.4); (3) the first
  post-cutover `/spec-draft` mining pass exercising the combined candidate
  set (REQ-C1.2); (4) write-time prose-leak screening, backed by
  `scan:secrets` for token-shaped leaks (REQ-D1.2); (5) confirming at the
  Tasks 5+6 PR that the flip and the freeze land together (REQ-E1.2).
  `[design-level]`
  items verify inside the owning task's done-when at PR review.
- **Dead paths:** none — every REQ's named verification can run; each
  `[manual]` item has an owner and a concrete occasion.

Signed off: 2026-07-08

## 6. Task graph

Reconstructed from the `Dependencies:` lines (authoritative):

```
1 ──► 2 ──► 3 ──┐
      │ └─► 4 ──┼─► 5 ──► 6
      └─────────────────► 6 (direct edge 2→6)
```

- **Edges:** 2←1; 3←1,2; 4←1,2; 5←1,2,3,4; 6←2,5.
- **Parallelism:** Tasks 3 ∥ 4 once Task 2 lands (the only parallel pair).
- **Effort-weighted critical path:** 1 (1d) → 2 (0.5d) → 3 (1d) → 5 (1d)
  → 6 (0.5d) = **4 days** of 4.5d total effort; Task 4's half day rides
  the Task 3 slot.
- **Cohesion bundle:** Tasks 5+6 dispatch as one unit, one PR (REQ-E1.2's
  no-split-brain window).
- **Deliberate non-edges (do not "fix"):** 4↛3 (independent scripts,
  independent tests); 6's dependency on 3 and 4 is transitive via 5 only;
  the output-hygiene carve-out amendment is *not* a task edge — it is an
  external human action tracked as the Deferred free-text gate
  (`**Gate:** the output-hygiene carve-out amendment has landed` — the
  status-atom form was rejected in D-9 because it falls silent once this
  spec completes).
- **Guard-first:** Task 2 deliberately precedes every task whose
  verification it protects, per the guard-infrastructure-first doctrine.

Signed off: 2026-07-08

## 7. Risk register

Decision-domains gap check (merged catalog via
`scripts/resolve-catalog.sh decision-domains`, ten core domains, no
overlay additions): **clean** — the design's cross-cutting walk covers all
ten (seven decided, three untouched with recorded reasons); no catalogued
domain is touched-but-undecided.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | Concurrent consumption of the same fragment (two mining runs on different branches) → one-file modify/delete or rename/rename conflict. | Accepted: rare and self-limiting (design cross-cutting). Keep either archived copy; hand-union the `Consumed-by:` lines. Signal: a merge conflict inside `specs/_observations/archive/`. |
| 2 | Residual conflicts on the frozen legacy file while it drains (in-place annotations from concurrent branches), including a partial annotation misclassifying a consumed line as unmined (lens pass G5). | Accepted: shrinking, low-traffic file; annotation edits union trivially, and a mis-read line at worst re-surfaces for mining. Signal: repeated `opportunities.md` conflicts post-freeze → reconsider a one-shot bulk drain. |
| 3 | Post-freeze append regression: a stale overlay, an unreconciled skill text, or an in-flight branch checked out from pre-migration `main` (lens pass G6) appends to the frozen log; `check:obs` guards only `entries/` + `archive/`, so CI would not catch it. | Freeze header + Task 5's zero-matches grep at cutover + drain naming both surfaces; fleet practice already directs in-flight workers to merge `main` after each merge. Signal: the frozen file's entry-line count grows after migration. |
| 4 | Adopter-repo cutover rides the plugin upgrade with no per-repo migration: adopter `opportunities.md` files never get the dedup/freeze-header pass and drain unfrozen, unaudited. | Accepted (2026-07-08): readers key on the legacy file's presence, not its header; the dedup pass only mattered for planwright's own corrupted log. Signal: an adopter drain report showing implausible counts. |
| 5 | Unbounded fragment population: `archive/` never shrinks by design, and per-record globs, the full-sweep guard, and the stateless render are all O(N) in the total population (lens pass G1, covering all seven performance findings). | Accepted: the observed entry rate keeps N in low thousands for years; reno runs the same model at far larger scale. Signal: `entries/` + `archive/` approaching ~5k files, or `check:obs` wall-clock becoming noticeable in CI → revisit sharding and guard-scoping then. |

Open questions: none carried — all resolved to decisions or recorded above
as explicit accepted risks.

Signed off: 2026-07-08

## 8. Sign-off

### Lens review pass (Discovery Rigor, full bundle — first activation)

Path taken: **parallel fan-out**, one read-only sub-agent per canonical
lens (nine agents), per the discovery-rigor doc; the bundle is a
non-trivial artifact. Shared tooling output passed to every agent:
`scripts/spec-validate.sh specs/observation-recording` — 0 errors,
0 warnings (re-run after the walkthrough edits). Coordinator merged and
deduped 86 raw findings into 42; validation pass re-verified every
load-bearing repo claim by direct grep (ten skills reference the log, not
seven; `docs/CONTRIBUTING.md:91` and `doctrine/decision-domains.md:68`
instruct the append; the glossary says "append-only"; the citation-kinds
table lacks `obs:`; the taxonomy's universal rule is class + home +
reader + drain), downgrading one claim
(`inter-orchestrator-coordination.md` references the log by name only —
review, not rewrite). Self-critique pass added two findings the lenses
missed (the legacy-consume arm's unspecified keying; the
unexpected-file check needing a legacy-file carve-out).

Lens-coverage table (canonical):

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 9 | Gate-window bug, calendar-date validity, annotate idempotency, empty state, interleave tiebreak, F1–F5 count wording |
| Security | 6 | Consume-surface validation gap, symlink append, guard locale, `Consumed-by:` injection, legacy echo discipline; one declined (G2) |
| Error handling and failure modes | 15 | Atomic writes, half-consumed state, cross-branch UID collision, migration snapshot drift, rollback completeness, caller contract |
| Performance | 7 | All orbit unbounded `archive/` + O(N) scans — declined as machinery (G1), converted to risk row 5 with a threshold signal |
| Concurrency / state | 11 | Converged with error handling on UID collision, half-consumed state, legacy-file mutation, ordering claims |
| Naming, readability, structure | 11 | Log/view overloading, unpinned task name, dangling citations, class-3 arity wording, count inconsistencies |
| Documentation | 8 | Reconciliation list missing three skills + `CONTRIBUTING.md` + `decision-domains.md`; glossary "append-only"; drift-log routing unstated |
| Tests / verification | 14 | Uncovered SHALL clauses (UID-keying, metadata whitelist, containment, consume data-only), unpinned golden order, `--today` pinning |
| Cross-file consistency | 5 | Class-3 arity contradiction with the owning doctrine, missing `obs:` citation kind, two dangling Sources refs |

### Dispositions (2026-07-08, all 42 findings dispositioned with the human)

Presented as seven clusters; the human decided each cluster-wide. (The
cluster parentheticals below enumerate 52 applied/declined line-items —
deduped from the 42 findings; some findings produced multiple edits or
were bundled — so the cluster counts sum past the finding count by
design; annotation added at the 2026-07-08 self-review pass, decided by
the human.)

- **Cluster A — applied** (10): mechanical clarity and citation fixes
  (F1–F5 wording, ~156-file count, Task-4 label, `obs:log` pinned,
  bootstrap Sources entry, REQ-A1.4 recited, "chronological view"
  de-overload, seed-brief naming, class-3 token, determinism scope).
- **Cluster B — applied** (12): mechanics tightening (cross-branch UID
  wording + guard net, bounded retry + entropy refusal, calendar dates,
  atomic record write, conditional/atomic annotate, half-consumed reader
  rule, consume-surface validate/contain/refuse + symlink + spec-id
  validation, caller contract, newline refusal, legacy-consume keying,
  render total order, empty state).
- **Cluster C — applied** (10): guard/verification coverage (guard
  `LC_ALL=C`, unexpected-file check, UID-keying fixture, metadata
  whitelist fixture, content-edit fixture, double-consume fixture,
  consume data-only fixture, containment unit test, `--today` pinning,
  legacy echo fixtures).
- **Cluster D — applied** (6): reconciliation scope widened to all ten
  skills + `decision-domains.md` + `docs/CONTRIBUTING.md`, drift-log
  routing through the helper, `obs:<uid>` citation kind in spec-format's
  table, class-3 arity corrected, glossary rewrite scope,
  coordination-doc framing review.
- **Cluster E — applied** (4): migration hardening (merge-time
  recompute, keep-when-in-doubt, durable F1–F5 contingency gate,
  rollback note).
- **Cluster F — applied** (1): the coordination gate reworded from
  `GATE(when: output-hygiene carve-out amendment has landed)` to plain
  prose after `**Gate:**`, so the drain surfaces the hold for its entire
  window.
- **Cluster G — declined with rationale** (9): G1 performance machinery
  (→ risk row 5), G2 standing prose-leak guard (deliberate REQ-D1.2
  design), G3 entropy verification (untestable directly), G4 marker
  casing (intentional distinction, verified), G5 legacy
  partial-annotation machinery (→ risk row 2), G6 in-flight-branch
  machinery (→ risk row 3), G7 enforced consumed-by union (risk row 1 +
  fixture C6), G8 dedup automation (deliberate `[manual]` escalation),
  G9 off-main Sources (seed files committed this run; the Cluster E
  F1–F5 contingency gate).

No finding is undispositioned. No inconsistency halt was triggered; no
open question is carried.

### Sign-off record

First activation: all seven sections signed 2026-07-08; the lens pass
above is fully dispositioned; `**Status:**` flipped Draft→Ready and
`**Last reviewed:**` set to 2026-07-08 on all four spec files; validator
re-run under Ready (errors-block) enforcement after every edit of this
run: 0 errors, 0 warnings.

Signed off by: Diego Romero (<jd@inkatze.com>), 2026-07-08.

Class: meaning
Lens-pass: recorded above (this section), findings dispositioned 2026-07-08.
Anchor: `7b4e2e1f0acf042747ad8f9c29d2285d574588b8` — computed as
`scripts/spec-anchor.sh specs/observation-recording`

## 9. Amendment log

(none yet)
