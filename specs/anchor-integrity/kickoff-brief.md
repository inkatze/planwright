# Anchor integrity — Kickoff Brief

## 1. Header

- **Spec:** `specs/anchor-integrity/`
- **Spec commit at walkthrough start:** `ad73cf9` (`feat(spec): draft specs/anchor-integrity bundle`)
- **Walkthrough date:** 2026-07-17
- **Mode:** first activation (Status Draft, no prior brief)
- **Format-version:** 2 (stored header rests at Ready after sign-off; Active/Done derived)
- **Validator outcome:** `scripts/spec-validate.sh specs/anchor-integrity` — 0 errors, 0 warnings (Draft status, findings would be warnings)
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true` (repo `config/defaults.yml`; no local overlay)
- **Doctrine resolution:** rule docs resolved repo-local via `PLANWRIGHT_ROOT=<repo>` (dev-repo dogfooding; the default chain resolves to the installed plugin cache, which trails HEAD)

## 2. Goal & glossary

**Restatement.** The content anchor must prove "the bundle a worker executes
is the bundle the human signed off"; today it cannot, for two independent
reasons, both fixed here without touching what `format-grammar` or
`invariant-tasks` own.

- **Write side:** three of the four v1 per-file digests whole-file hash, so
  the header `**Status:**` line rides the anchor and every sanctioned
  lifecycle Status write (stored Draft→Ready, derived Ready↔Active mirrors)
  false-stales it — fired live on invariant-tasks Task 3. Fix (D-2): exclude
  exactly the header-block Status line from those three digests, land
  atomically with the expression-only re-anchor sweep (D-3), document the
  one-time adopter self-re-anchor remedy.
- **Process side:** skills that legally edit signed bundles have no
  sanctioned re-anchor path, so the ritual gets skipped (three recurrences,
  once inside a squash). Fix (D-5): stale-anchor pre-flight, expression-only
  self-re-anchor ritual in the same change, meaning-class refusal routed to
  `/spec-kickoff`, plus `/spec-kickoff`'s terminal pre-push recompute.
  Meaning-class anchor writership stays with `/spec-kickoff` alone.
- **Hardenings:** the anchor-freshness guard (one script; normative
  `mise run check` CI wiring, best-effort lefthook mirror); the
  committed-main gate-frame statement for the v1 arm; decided-rules-over-
  enumerated-counts authoring guidance; the resolution-path-aware third
  sanctioned command form for adopter repos without `scripts/`.

**Rules out:** extraction internals (format-grammar), v2 semantics / forced
migration (invariant-tasks; v1 valid indefinitely), redesigning the derived
flip or single-writer reconcile, widening meaning-class writership, gate
semantics beyond the frame statement.

**Assumes:** format-grammar (Ready) may or may not have landed at execution
time; Tasks 1–2 carry explicit conditional homes so neither ordering blocks.

**Implicit terms resolved:**

1. **"Signed bundle"** = Ready or Active (REQ-C1.1's parenthetical).
2. **"Baseline ref"** (REQ-D1.2) — read as the same baseline-ref convention
   the existing check infrastructure uses (effectively merge-base with main
   in CI); pinned in the REQ-D walk.
3. **"Landing proof"** (D-3/Task 3) — a one-shot assertion in the sweep PR
   that every briefed bundle recomputes equal; concrete form deliberately
   left to execution, with the Task 4 guard as the permanent form.
4. **v1-vs-universal exclusion scope** — flagged here, resolved in the REQ-A
   walk (see section 3).

Signed off: 2026-07-17

## 3. Requirements walkthrough

| Group | Outcome |
| --- | --- |
| A — anchor scope | **Fork decided: universal exclusion.** One digest definition (the meta-spec's version-1 body), inherited unchanged by every later format version; the tool parses no format-version. The Task 3 sweep therefore covers moved bundles of any version. |
| B — gate frame | Confirmed as-is. The committed-main frame statement stays live post-D-2: it governs interim whole-file-form entries, yet-unswept bundles, and transient mid-reconcile states. |
| C — re-anchor pathways | Confirmed. Coverage triangle closed: C1.2 self-ritual covers act-on-findings edits, C1.4 terminal recompute covers kickoff-owned post-sign-off flows, the REQ-D guard covers out-of-flow edits. An absent/unparseable anchor entry at C1.1 pre-flight surfaces the same as a mismatch. |
| D — mechanical guards | **Fork decided: terminal states (Retired, Superseded) skip with notice** — frozen history, briefs never grow machine entries. Baseline ref pinned to the existing `spec-validate` convention (default `origin/main`, explicit `--baseline` override). |
| E — authoring guidance | Confirmed. *(Corrected at the sign-off lens pass: the changelog's fork-decision enumeration was itself a rot candidate this row missed; it is now a decided-rule citation — see the disposition record.)* |
| F — portability | Confirmed. Version-skew risk (recorded anchor vs chain-resolved tool version across the D-2 boundary) carried to the risk register. |

**Consolidated spec-edit list (Draft edits, applied in place 2026-07-17):**

1. `requirements.md` In-scope bullet 1 — universality clarification.
2. `requirements.md` REQ-A1.1 — digest defined once in the v1 body,
   inherited by every later format version; no version parsing.
3. `requirements.md` REQ-A1.5 — adopter remedy covers any format version.
4. `design.md` D-2 — universality sentence appended.
5. `test-spec.md` REQ-A1.1 — format-version 2 invariance fixture added.
6. `requirements.md` REQ-D1.2 — baseline-ref convention pinned.
7. `requirements.md` REQ-D1.4 — terminal-state skip added.
8. `design.md` D-6 — terminal-state skip sentence.
9. `tasks.md` Task 4 — terminal-state skip in deliverables.
10. `test-spec.md` REQ-D1.4 — Retired and Superseded skip fixtures added.

*(Added during sections 5–7:)*

11. `requirements.md` REQ-A1.4 — sweep scope widened to pre-existing stale
    anchors with per-bundle delta classification (section 7 fork).
12. `design.md` D-3 — sweep-scope and classification sentences appended.
13. `tasks.md` Task 3 — classification step, scope wording, and the
    breaking-change-marker release signaling added.
14. `test-spec.md` REQ-A1.4 — landing-proof scope aligned (non-Draft,
    non-terminal) and classification record added.
15. Sign-off lens-pass fix set (dispositioned 2026-07-17, clusters 1–3
    applied in full, cluster 4 declined): the per-file edits are
    enumerated in the sign-off section's disposition record below, not
    re-listed here (cite-don't-copy).

Signed off: 2026-07-17

## 4. Design walkthrough

Reconciled D-ID ledger (all decisions from `design.md`, verdicts from the
2026-07-17 walkthrough):

| D-ID | Verdict | Notes |
| --- | --- | --- |
| D-1 mixed-altitude | Confirmed | The trigger-scoped altitude record resolving both pinned Sources claims; re-verified at the sign-off altitude check. |
| D-2 Status-line exclusion | Amended at kickoff | Universality sentence appended (section 3, group A fork). Rationale and alternatives intact; the amendment narrows an ambiguity, reverses nothing. |
| D-3 coordinated sweep | Confirmed | Sweep pool = every briefed bundle under `specs/` whose anchor moves, any format version. Grounded: every non-Draft in-repo bundle has a brief, so none is unsweepable. |
| D-4 committed-main frame | Confirmed | Liveness post-D-2 established (interim-form entries, unswept bundles, mid-reconcile transients). |
| D-5 re-anchor pathway | Confirmed | Named trio matches Task 5; external families bound via doctrine, delivered in their own repos. |
| D-6 guard, two wirings | Amended at kickoff | Terminal-state skip sentence appended (section 3, group D fork). Alternatives intact. |
| D-7 logical command form | Confirmed | Chain matches `resolve-rule-doc.sh`'s documented order (verified live this session, including the stale-env failure the rejected alternative cites). |
| D-8 decided rules | Confirmed | Both motivating recurrences check out against Sources. |

**Cross-cutting grounding:** `scripts/tasks-pr-sync.sh:79` carries the "NOT
yet anchor-excluded" caveat, attributed to kickoff-lifecycle Task 3 (a
stale pointer; Task 2's caveat update corrects it).
`scripts/migrate-format-version.sh:874` writes the canonical repo-relative
form — stays sanctioned under D-7. format-grammar conditional homes match
its Ready state. No D-ID contradicts a walked requirement.

Signed off: 2026-07-17

## 5. Verification approach

Coverage mix reviewed against `test-spec.md` (every REQ pinned; the
validator's coverage invariant is the count's source — cited, not copied):

- **`[test]`** — hash mechanics, landing proof, guard paths, resolution
  test; all under `mise run check`, run by GitHub Actions on every PR. The
  two kickoff forks (universality, terminal skip) both landed as fixtures
  in this arm. CI on the head SHA is the arbiter (the local `[test]` task
  has known machine-specific noise).
- **`[design-level]`** — doctrine/prose entries (A1.3, A1.5, B1.1, E1.1,
  E1.2's prose half), discharged at spec-PR review.
- **`[Gherkin + manual]`** — the four C-group rituals plus D1.3's
  commit-time block and E1.2's live cross-check; each pinned to a named
  occasion (next act-on-findings run over a signed spec, next commit with
  hooks, next drafting/kickoff sessions). Owner: the human.

**Dead paths: none.** The landing proof runs one-shot in Task 3's PR before
the Task 4 guard exists (correct ordering; the guard then makes the
property permanent). F1.1's resolution test needs only a temp dir plus the
chain env vars. C-group scenarios have abundant signed bundles to run
against. Noted (not a defect): the C1.1–C1.4 Gherkin scenarios already
exist in `test-spec.md`; Task 5/6's "record" is confirm-and-refine at
execution.

**Backstop pattern:** each manual ritual (C1.2, C1.4) names the REQ-D1.1
guard as its mechanical backstop — a skipped ritual still fails the merge
gate.

Signed off: 2026-07-17

## 6. Task graph

Reconstructed from the `Dependencies:` lines (rendered via
`scripts/spec-graph.sh`, which confirmed the reconstruction):

- Fan-out: Task 1 → {2, 5, 6, 7}; chain: 2 → 3 → {4}, with 4 also on 2.
- **Critical path (effort-weighted):** 1 → 2 → 3 → 4 (~3 days). Forced:
  the sweep needs the new hash semantics; the guard must first run against
  a swept repo (D-3 "green from its first run"). Guard-first preference
  satisfied as tightly as dependencies allow.
- **Parallelism:** after Task 1, up to four lanes — the mechanism chain
  (2→3→4) plus Tasks 5, 6, 7.
- **Deliberate non-edges:** 5/6/7 ↛ 2/3/4 (skill prose cites doctrine,
  never mechanism); 3 ↛ 1 and 4 ↛ 1 direct (transitively satisfied via 2).
  Workers must not add these edges.
- **Dispatch note:** Tasks 6 and 7 both edit `/spec-kickoff` prose —
  cohesion-bundle candidate (6+7) or one sequential lane; Task 5 parallels
  freely. Dispatch-time suggestion, not a spec edit.

Signed off: 2026-07-17

## 7. Risk register

**Decision-domains gap check** (merged catalog via
`scripts/resolve-catalog.sh decision-domains`, 11 domains walked): touched
and decided — api-surface (D-6/D-7), concurrency (D-4 + row 3),
observability (the guard), deploy-migration (REQ-A1.5 + row 2),
secrets-config (no new secrets; wiring is decided build config). Untouched
— data-storage, caching, queues-async, auth, dependency-adoption. One
touched-but-undecided domain (versioning-scheme) was surfaced and resolved
during the walk (row 7).

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | Pre-existing stale anchors on the Done bundles could hide an unreviewed meaning edit; a machine sweep would launder it. | Mitigated by the classify-deltas decision (REQ-A1.4: per-bundle diff since the recorded entry; meaning-class routes to a delta re-walkthrough). Early signal: classification hits a non-lifecycle delta during Task 3. |
| 2 | Version skew across the D-2 boundary: an adopter's recorded anchors and the chain-resolved tool disagree (either direction) after a plugin upgrade. Observed in-session: the default chain served 0.14.1 doctrine in a 0.17.0 repo. | REQ-A1.5 remedy prose; D-7's explicit resolution chain. Early signal: adopter false-halt reports immediately after upgrading. |
| 3 | Sweep-window race: a spec signs off between sweep computation and sweep-PR merge, re-staling the landing proof. | Re-run the proof at the merge SHA; hold kickoffs while the sweep PR is open. Early signal: proof red at merge time. |
| 4 | Merge-gate blast radius: one stale bundle turns the REQ-D1.1 guard red repo-wide, blocking unrelated PRs. | Skip semantics; sweep-before-guard ordering (Task 4 depends on 3); terminal skip. Early signal: guard red on a bundle the PR didn't touch. |
| 5 | Instruction-budget pressure: Tasks 5–7 add prose to five skills. | Budget checks in each Done-when; trim within the same skill if red. Early signal: budget check red on the task PR. |
| 6 | format-grammar lands mid-execution, forking the header-block-bound / extraction-home definitions. | Conditional homes + reconcile-note discipline (Tasks 1–2). Early signal: two live definitions of the bound. |
| 7 | **Decided at kickoff** (was the gap-check's undecided versioning-scheme row): the D-2 boundary's release-bump class. Decision: the landing commits carry the conventional breaking-change marker naming the one-time remedy; the bump class derives from the release scheme at release time; release notes signal the boundary. Recorded in Task 3's deliverables. | Early signal if violated: a release carrying Tasks 2–3 without the marker or remedy note. |

No open questions carried; all resolved to decisions or mitigated rows.

Signed off: 2026-07-17

## Sign-off

### Lens review pass (first activation — full bundle, fan-out)

Nine read-only sub-agents, one per canonical lens (`discovery-rigor`
fan-out; the bundle is non-trivial). Shared tooling given to every agent:
`spec-validate` 0/0; `check:ledger`, `check:memory-links`, `check:links`
green. Raw findings: 76; deduped to three apply-clusters (validated per
`validation-rigor`: agent primary-source verification plus multi-lens
convergence, adversarial bi-directional sweep run) and one decline set.

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 11 | Done-bundle remedy mode; Task 2+3 atomicity; interim-form population; guard/gate divergence; one-directional A1.3; invalid v2 fixture state; Done-when gaps |
| Security | 8 | Parse-validate-then-invoke; root containment; `<spec-dir>` grammar; echo discipline; forged-entry laundering; brief-deletion bypass; baseline validation |
| Error handling and failure modes | 19 | Malformed-header fail-closed; classification baseline/ambiguity; meaning-delta availability; baseline-unresolvable; extraction-aware D1.2; resolve-failure arm; ritual ordering; adopter asymmetry |
| Performance | 8 | Unconditional mirror ≈1.5–2.5s/commit (net-new); false "costs nothing" premise; unbounded growth |
| Concurrency / state | 8 | Frame snapshot unpinned; torn mirror writes; reconcile writer re-stales sweep; classification overtaken; re-run provenance; Task-2-alone false-halt; mirror blocks worktrees |
| Naming, readability, structure | 7 | v1-label stragglers; sweep-scope lead drift; "lifecycle-only" undefined; citation kind |
| Documentation | 6 | lefthook phantom home (obs line 113 uncited); changelog fork-enumeration rot; unpinned A1.5 homes |
| Tests / verification | 8 | Transition matrix; laundering invisible to proof; D1.2 false-positive direction; wrong-root negatives; entry-selection cases; C1.1 true-negative; manual occasions |
| Cross-file consistency | 1 | "Tool contradicts its own header" is a seed misread; header accurate, tasks-scoped |

**Altitude check (REQ-H1.3): pass.** Triggered bundle (two pinned Sources
altitude claims); D-1 exists, is cited from the goal, both claims marked
resolved at it; decomposition matches the mixed altitude (doctrine Task 1,
mechanism Tasks 2–4, skill wiring Tasks 5–7).

**Dispositions (human, 2026-07-17, clustered):**

- **Cluster 1 — safety-critical (applied in full):** classification
  integrity (ambiguity defaults to meaning-class; baseline = the entry's
  introducing commit; Done bundles route via the reopen cycle; merge-SHA
  re-verification; honest re-run provenance; adopter remedy and C1.4 gain
  the classification gate) → REQ-A1.4/A1.5/C1.4, D-3, Task 3, test-spec
  A1.4/C1.4. Task 2+3 required cohesion bundle with park-not-block
  split-out → Task 2/3 Done-whens, D-3. Execution-safety → new REQ-D1.5,
  D-6, Task 4, new test-spec D1.5. Malformed-header fail-closed →
  REQ-A1.2, D-2, Task 2, test-spec A1.2. Brief-less non-Draft = error →
  REQ-D1.4, D-6, Task 4, test-spec D1.4.
- **Cluster 2 — precision/degradation (applied in full):** mirror scoped
  to staged `specs/**` + corrected D-6 cost rationale; extraction-aware
  D1.2 + baseline degradation; pinned single-SHA gate frame with
  content-defined allowance → REQ-B1.1, D-4; ritual failure ordering
  (C1.1 blocks on absent/unparseable/error; C1.2 one commit; C1.4 halts
  on failure) → REQ-C1.1/C1.2/C1.4, D-5, Tasks 5–6, test-spec C1.1–C1.4;
  resolve-failure halt arm + prefer-checked-tree → REQ-F1.1, D-7,
  test-spec F1.1; interim-form entries join sweep and remedy →
  REQ-A1.4/A1.5, D-3, Task 3; bidirectional A1.3.
- **Cluster 3 — alignment (applied in full):** seed-misread reframe
  (Goal, Sources line-188 entry, REQ-A1.3 rationale); v1-label
  stragglers (D-2 title, A1.5, In-scope bullets, D-3 lead);
  lifecycle-only defined in REQ-A1.4; citation token → `kickoff §7 risk 1
  (2026-07-17)`; Done-when gaps closed (Task 2 caveat/migrate, Task 3
  breaking marker); test-spec matrix and negative-case additions
  (including correcting the v2 fixture to its valid stored set); lefthook
  acknowledged net-new with obs line 113 added to Sources; A1.5 homes
  pinned; kickoff changelog entry added with fork enumeration converted
  to decided-rule citation; brief group-E row corrected.
- **Cluster 4 — declined (confirmed):** recompute memoization (~86ms per
  recompute, state not worth it); CI-arm change-scoping (whole-corpus at
  ~1.5s keeps the merge gate total); gitattributes digest determinism
  (execution detail; sweep re-baselines; note rides Task 2's tests);
  "Chosen because" provenance ordering (cosmetic, conformant); full
  mechanical writership verification (impossible; residual-risk note in
  D-6 instead); torn-write provenance verification (subsumed by the
  content-defined frame allowance). One agent note dropped as false
  positive at validation: "brief exists while Draft" (the brief is
  written incrementally by design).

No undispositioned findings remain.

### Panel pass (`/panel-review --nested`, backend: gemini)

Iteration 1 over the committed walkthrough state (`963cbcf`): 3 findings.
Dispositions (human, 2026-07-17): **applied** — the park carve-out (a
parked bundle writes a live `anchor re-review pending` bullet to its
`## Awaiting input`; guard and landing proof report it as a known-parked
notice, dispatch gate still fails closed; REQ-A1.4, REQ-D1.1, D-3, D-6,
Tasks 3–4, test-spec A1.4/D1.1) and the lefthook install wiring
(`mise.toml` tools entry plus documented install step, Task 4);
**dropped as previously declined** — whole-corpus CI growth (lens-pass
cluster 4b). Iteration 2 (over `40fa49f`) returned one finding — REQ-B1.1
frame vacuity — dropped as a false positive at validation: the gate
recomputes with the entry's recorded command form, so interim-form
entries keep whole-file semantics and the frame stays live (converges
with the section-3 walk and the cross-file lens agent's independent
check). Zero findings remain: panel converged.

### Sign-off record

First activation signed off 2026-07-17 by Diego Romero with the agent's
walkthrough. Scope: full bundle (sections 2–7 walked and signed; lens
pass full-bundle fan-out; panel pass converged). Status flipped
Draft→Ready on all four files; validator re-run on Ready: 0 errors,
0 warnings.

Class: meaning
Lens-pass: the "Lens review pass" subsection above (canonical
lens-coverage table, nine-agent fan-out, altitude check, clustered
dispositions; plus the panel pass record) — every finding dispositioned,
none open.
Anchor: `48504616fd42e71fb9f4a49d8fbda691c844f606` — computed as
`scripts/spec-anchor.sh specs/anchor-integrity`

## Amendment log

(none yet)
