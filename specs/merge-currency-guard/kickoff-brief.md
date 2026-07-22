# Merge Currency Guard — Kickoff Brief

## 1. Header

- **Spec path:** `specs/merge-currency-guard`
- **Spec commit at walkthrough start:** `9224674` (branch `planwright/merge-currency-guard/spec`)
- **Walkthrough date:** 2026-07-20
- **Mode:** First activation (Draft, no prior brief)
- **Validator outcome (pre-flight):** `spec-validate` clean — 0 errors, 0 warnings
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true` (defaults; no local override)
- **Working location:** spec worktree `.claude/worktrees/merge-currency-guard-spec` recreated on the existing spec branch (worktree was pruned; branch + bundle intact)
- **Open PR:** #276 (draft) — `spec(merge-currency-guard): draft bundle`
- **Resume note (2026-07-21):** the 2026-07-20 session was interrupted after
  writing this header. Header facts re-verified on resume (spec commit still
  `9224674`, validator re-run clean 0/0, PR #276 still draft, config defaults
  confirmed); walk resumed at section 2.

## 2. Goal & glossary

**Restatement.** The bundle makes the ready-flip signal trustworthy by
construction. "Ready" attests converged + CI-green + review-clean, but today it
attests that about a head that may be hours stale against `main`; GitHub blocks
*merging* a DIRTY PR, but nothing protects the *ready signal* that precedes the
merge. Two mechanisms under one invariant (REQ-A1.1): (1) `/execute-task`
fetch+merges `origin/main` at the top of every convergence iteration via a
one-line `converge-sync-main.sh` call, so the final verification always runs on
a `main`-current head; (2) a deny-emitting `ready-guard` PreToolUse hook — a
new modality beside the allow-only sibling guards — denies draft→ready unless
`mergeStateStatus == CLEAN` AND `origin/main` is an ancestor of the PR's head
commit (stated as `HEAD` when this section signed; retargeted to the PR's
`headRefOid` at §4),
fail-closed on any doubt, covering both the `gh pr ready` Bash surface and the
`mcp__github__update_pull_request` MCP surface.

*(Forward note: the predicate stated in this §2/§4 record was further settled
during the sign-off lens pass — see §8 and the 2026-07-22 changelog entries.
The final, authoritative predicate is server-authoritative `mergeStateStatus ∈
{CLEAN, UNSTABLE}` + `mergeable == MERGEABLE`, no local `is-ancestor`. The
restatement below is preserved as the walk's historical record.)*

**Rules out:** who-flips policy and autonomous flipping (D-9: capability in
core, policy in overlay); auto-merge or any merge-gate change; the bare-shell
out-of-session flip (accepted residual, D-7); server-side promotion; reopening
`guard-coverage` / `fleet-hardening` (consumed as cited siblings).

**Assumes:** GitHub `mergeStateStatus` is the authoritative
currency+mergeability signal, with the local `is-ancestor` check as the
async-lag backstop (D-3); all autonomous flippers run in-session; deny-over-allow
precedence is pinned by outcome tests, never assumed (obs:4dda9fe1).

**Implicit terms surfaced:** *defer* (guard emits nothing → flip proceeds),
*conforming flip* (predicate satisfied), *convergence iteration* (the
`review_sequence` loop unit — exact boundary pinned in §3).

**Resolutions.**

1. **Shared ready-flip surface ownership** — three specs touch the ready-flip
   interception surface (this bundle's gate; `concurrent-orchestrator-coordination`'s
   tower merge-`main` relay; the deterministic-pr-ready-push observation's
   notification). **Decided: merge-currency-guard owns the single gating hook**
   (grounded in D-7 global wiring); the relay
   stays the sibling's operational mitigation above this enforcement floor, and
   any notification rides its own observer hook. Applied as spec edit #1
   (Out-of-scope boundary bullet in `requirements.md`); a risk-register row
   follows in §7.

**Queued for later sections:** the tower-issued-flip case for D-3's
`is-ancestor` leg (`HEAD` = local main when a tower flips PR #n from the shared
checkout, so the backstop leg mis-fires — a false deny when local main lags,
a vacuous pass otherwise; resolved at §4 by retargeting to the PR's
`headRefOid`) → §4; `[manual]` sweep ownership → §5; the "top of each
convergence iteration" boundary → §3.

Signed off: 2026-07-21

## 3. Requirements walkthrough

**REQ-A (invariant).** Intent confirmed: one hard invariant in the bootstrap
never-merge family, flipper-agnostic, no who-flips mandate. Decision: A1.2's
enforcement scope split explicitly — currency + mergeability are
guard-enforced by construction; CI-and-review verification stays attested by
the flipping party's convergence discipline (CI additionally covered where
checks are GitHub-required, via `BLOCKED`). The guard is never read as
certifying review state. (Edit #2.)

**REQ-B (loop sync).** Intent confirmed. Decisions: sync cadence pinned to
once per full `review_sequence` pass, before its first skill runs (edit #3);
fetch failure resolves like a conflict — non-zero exit into the existing halt
path with a clear reason (resolved from fail-closed doctrine, reported not
asked; edit #4 adds the fixture to REQ-D1.3 and the test-spec).

**REQ-C (guard).** Intent confirmed, including the deny-emitting modality
inversion and the outcome-pinned deny-over-allow. Decision: the MCP matcher
discriminates a true draft→ready transition by reading `isDraft` from the same
PR query the guard already issues for `mergeStateStatus`; only a
currently-draft PR is gated, preserving REQ-C1.8's letter at zero extra
network cost, with a failed query already DENY per REQ-C1.3. Lands as a D-8
wording refinement in §4 — no REQ edit. The `HEAD`-vs-PR-branch question on
the `is-ancestor` leg remains queued to §4 (D-3).

**REQ-D (verification).** Intent confirmed: every deny branch and every
never-deny branch has a fixture; precedence pinned by outcome. No changes
beyond edit #4's fetch-failure case.

**REQ-K (degradation/hygiene).** Intent confirmed; bootstrap-inherited
posture. No changes.

**Consolidated spec-edit list (walk-wide, applied in place — Draft bundle):**

1. `requirements.md` Out of scope — shared ready-flip surface boundary bullet
   (§2 decision: MCG owns the single gating hook; siblings compose).
2. `requirements.md` REQ-A1.2 — enforcement-scope split (guard-enforced
   currency+mergeability vs attested review-verification).
3. `requirements.md` REQ-B1.1 — sync cadence clarifier (once per full pass).
4. `requirements.md` REQ-D1.3 + `test-spec.md` REQ-D1.3 — fetch-failure
   non-zero-exit case added.
5. (applied at §4) D-3 ancestor-leg retarget — `design.md` D-3,
   `requirements.md` REQ-C1.1, `tasks.md` Task 2, `test-spec.md` REQ-C1.1.
6. (applied at §4) D-8 MCP transition discrimination via current `isDraft`.
7. (applied at §4) `requirements.md` `## Changelog` section added (required by
   spec-format, absent from the draft).
8. (applied at §5) `test-spec.md` REQ-D1.2 — deny-over-allow pattern pointer to
   the `test-tower-command-guard.sh` OUTCOME block.

Signed off: 2026-07-21

## 4. Design walkthrough

**Reconciled D-ID ledger (all 9 accounted for):**

| D-ID | Disposition |
| --- | --- |
| D-1 altitude record | Confirmed — rationale intact |
| D-2 deny-emitting PreToolUse at the flip point | Confirmed |
| D-3 predicate | **Amended** — ancestor leg retargeted from the session's `HEAD` to the PR's `headRefOid` (read from the guard's own PR query, 40-hex-validated, resolved against the local object db; unknown OID → DENY naming the fetch remedy). Reason: `HEAD` is only correct when the flipper sits on the PR's branch; a tower flipping from the shared checkout got a false deny (stale local main) or a vacuous pass. Operator chose fail-closed OID targeting over a conditional backstop or an accepted residual. |
| D-4 in-loop fetch+merge via script | Confirmed — §3 cadence pin matches |
| D-5 no in-hook fetch, deny on doubt | Confirmed — OID lookup is local-object-db only, consistent |
| D-6 deny-over-allow pinned by outcome | Confirmed |
| D-7 global wiring + bare-shell residual | Confirmed — §2 boundary decision reinforces it |
| D-8 both surfaces | **Amended** — MCP matcher gates only a currently-draft PR, `isDraft` from the same PR query (§3 decision folded in) |
| D-9 capability core / who-flips overlay | Confirmed |

**Mid-walk delta lens (D-3/D-8 edits, inline — small narrow delta):** one
finding, applied — the server-supplied `headRefOid` must be validated as
40-hex before interpolation into the git command (security lens,
`security-posture` inert-data rule); added to D-3's text. Post-lens
stale-reference sweep ran (grep for `HEAD` / `is-ancestor` across the
bundle + earlier brief sections): one stale reference in §2's restatement,
reconciled with a marked retarget note. Validator re-run after all edits:
clean, 0 errors / 0 warnings. No design decision contradicts a walked
requirement; no inconsistency halt.

Signed off: 2026-07-21

## 5. Verification approach

**Coverage mix reviewed** (cited from `test-spec.md`'s intro and tags):
predominantly `[test]` — deterministic shell mechanisms, fixture-testable
including all negative assertions; `[manual]` reserved for the
Claude-Code-version-sensitive platform contracts (REQ-C1.6 deny-actually-blocks
on both surfaces; REQ-B1.3's halt-mapping review); `[design-level]` for
REQ-A1.1, REQ-A1.4, REQ-K1.2.

**Verification ownership (decided):** `[test]` entries run in the project CI
(`mise run check`) on every task PR. `[design-level]` entries are verified at
Task 1 review and this kickoff's lens pass. `[manual]` entries: the Task 2/4
worker performs the live end-to-end confirmation at landing and documents it
in the task PR body; the operator owns re-sweeps when the Claude Code version
materially changes (operational note, no new checklist surface).

**Dead-path check:** REQ-D1.2's deny-over-allow `[test]` tag was probed as the
riskiest path (a live-session dependency would make it unrunnable in CI) and
resolved: the `test-tower-command-guard.sh` deny-precedence OUTCOME block
(`fleet-hardening` REQ-C1.3 precedent) pins the outcome at the script +
settings-structure level, CI-runnable; the live-blocking half rides
REQ-C1.6's `[manual]` sweep. Pattern pointer added to `test-spec.md`
REQ-D1.2 (edit #8). No other REQ names a verification that cannot run.

Signed off: 2026-07-21

## 6. Task graph

**Graph reconstructed from `Dependencies:` lines** (`tasks.md`, the sole
source of truth; render on demand via `scripts/spec-graph.sh`):

- Task 1 (none) → Task 2 (deps: 1) and Task 3 (deps: 1) → Task 4 (deps: 2, 3).

**Parallelism:** Tasks 2 and 3 are independent of each other and run in
parallel once Task 1 lands. **Effort-weighted critical path** (efforts cited
from the task blocks): 1 → 2 → 4; the 1 → 3 → 4 branch is shorter, so Task 3
never gates the finish while Task 2 is in flight. The intro's
guard-infrastructure-first note (Task 2 outranks once Task 1 lands) is
consistent — Task 2 sits on the critical path anyway.

**Deliberate non-edges** (recorded so nobody "fixes" them later):

- **Task 2 ↮ Task 3.** The guard and the loop-sync are independent mechanisms
  by design (D-2 vs D-4); serializing them would forfeit the parallelism for
  no ordering gain. Their only join is Task 4.
- **Task 1 → Task 4 (no direct edge).** Task 4's dependency on Task 1 is
  transitive through 2 and 3; adding a direct edge would be redundant.

No dispatch is implied by this section: kickoff never dispatches, and the
first dispatch (via `/orchestrate` after the spec PR merges) is what derives
Active.

Signed off: 2026-07-21

## 7. Risk register

**Decision-domains gap check:** walked against the 11-domain prose seed
(`doctrine/decision-domains.md`); no adopter/repo/machine overlay catalog
layers exist. Degradation note: `scripts/resolve-catalog.sh decision-domains`
produced empty output (exit 0) despite the core seed yaml being present — the
prose seed was walked directly; quirk recorded as an observation. Domains the
spec touches and decides: async external state (D-3/D-5), plugin/API surface
(D-7, REQ-C1.7), authorization-adjacent trust
boundary (D-9). Undecided touches became rows 2 and 4 below.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | Shared ready-flip surface: three specs converge on it (this gate; `concurrent-orchestrator-coordination`'s tower relay; the deterministic-pr-ready-push notification observation) — duplicate or conflicting hooks | Ownership decided at §2 (grounded in D-7 global wiring): MCG owns the single gating hook, recorded in Out of scope; siblings compose. Early signal: a sibling bundle drafting a second gating hook or restating the predicate — fold-detection at that spec's draft should trip. |
| 2 | TOCTOU residual (gap check, concurrency): `main` can advance, or `mergeStateStatus` change, between the guard's evaluation and the flip executing; no client-side gate can close this window | Accepted risk: the window is seconds (versus hours today), and GitHub's DIRTY-merge block remains the merge floor beneath it. Early signal: a ready PR observed `BEHIND` immediately after a guarded flip. |
| 3 | GitHub async-compute lag: right after the convergence head moves, `mergeable` sits at `UNKNOWN` → deny of the (legitimate) modal post-sync flip | Guard re-queries once within its bounded runtime before denying, and the `UNKNOWN` deny names a wait-and-retry remedy, not a fetch (REQ-C1.3, REQ-K1.1); the flipper retries once GitHub settles. Early signal: recurring `UNKNOWN` denials of conforming flips. |
| 4 | No adopter opt-out knob for a globally-wired deny (gap check, configuration) | Deliberate: the gated transition is universally wrong and the guard grants nothing (D-7); an adopter escape hatch, if friction ever demands one, is overlay hook-shadowing, not a core knob. Early signal: adopter reports of legitimate flips denied. |
| 5 | Platform-contract drift: whether a PreToolUse deny actually blocks each surface is Claude-Code-version-sensitive | `[manual]` sweep ownership decided at §5 (worker confirms live at landing, documented in the task PR; operator re-sweeps on material version changes). Early signal: a deny that fails to block after an upgrade. |
| 6 | Sole reliance on GitHub's server APIs (compare `behind_by` + `mergeable`; the predicate has no local backstop): if GitHub is degraded or slow, the guard fail-closes and denies all flips until it recovers | Deliberate fail-closed posture (a denied flip is safe; the flipper retries); the compare-based currency signal is branch-protection-independent (avoids the `mergeStateStatus`-reads-`CLEAN`-for-a-behind-PR false-allow the panel caught, G1) and needs no local ref/OID (no stale-local-ref false-allow). Early signal: a burst of `gh`-error/timeout denials tracking a GitHub incident. |
| 7 | The seed citation `obs:921b93c9` lives on the unmerged `planwright/chore/observations` branch; if that branch never lands, the Sources cite dangles | Cite carries the full path and date so it stays resolvable from history; land the observations branch. Early signal: a broken obs lookup at the next drain. |
| 8 | Convergence churn under a hot `main`: each top-of-iteration merge re-dirties the head and re-runs the full CI + review sequence, so a heavy unit whose CI outlasts the fleet's merge cadence can loop without converging | Accepted cost of keeping the head current (D-4); bounded in practice by per-spec `max_parallel_units` throttling merge rate. Early signal: a unit exceeding N convergence iterations with each iteration ingesting new `main` commits — worth an `/execute-task` iteration cap if observed. *(Added at kickoff §7 lens pass 2026-07-22.)* |

No open questions remain: every question raised during the walk was resolved
into a decision (§§2–5) or an explicitly accepted risk (rows 2, 4 above).

Signed off: 2026-07-21

## 8. Sign-off

**Scope:** first activation — full-bundle walkthrough (§§2–7) plus the terminal
Discovery-Rigor lens pass over the whole bundle.

**Altitude check (REQ-H1.3):** trigger fired (the pinned seed claim in
`## Sources`, "unbypassable by construction, matching planwright's guard
philosophy"). D-1 altitude record present, cited from the Goal; the task
decomposition is mechanism-primary with one carried invariant statement, which
matches the claimed altitude. **Pass.**

**Lens review pass — fan-out (9 read-only lens sub-agents) + an adversarial
re-check of the applied predicate.** Canonical lens-coverage table:

| Lens | Findings | Disposition |
| --- | --- | --- |
| Correctness, logic, edge cases | many | Predicate re-derived to server-authoritative `mergeStateStatus ∈ {CLEAN, UNSTABLE}` + `mergeable == MERGEABLE` (C1, via 3 iterations under adversarial pressure); matcher coverage widened (C3/REQ-C1.10); base handling folded into the server signal (C4). All applied. |
| Security | 2 | PR-target selector resolution + injection hardening (REQ-C1.9); echo-safety on emitted untrusted content (REQ-K1.3). Applied. |
| Error handling & failure modes | 10 | Conflict aborts + halts idempotently (REQ-B1.3); distinct fetch/conflict/dirty-tree exit reasons (REQ-B1.6); `gh pr view` timeout + `UNKNOWN` re-query + wait-retry remedy (REQ-C1.3). Applied. |
| Performance | 8 | `gh pr view` bounded + network-free fast path (REQ-C1.3); convergence-churn accepted (risk row 8). Applied / accepted. |
| Concurrency / state | 4 | Conflict-wedge idempotency (REQ-B1.3); the refspec-freshness concern dissolved by the server-authoritative predicate (no local ref read). Applied / moot. |
| Naming, readability, structure | 4 | `design.md` decisions → `## Decision log` at H3 so the validator parses them (C11); dual-category dropped with the catalog (C9); origin-tag legend; brief numbering. Applied. |
| Documentation | 6 | guard-catalog registration dropped as a category error (C9); invariant single home pinned to REQ-A1.1 cross-ref bootstrap (C10); changelog completed. Applied. |
| Tests / verification | 12 | Server-predicate matrix + mechanical completeness manifest (REQ-D1.1); no-LLM stub reachability; selector-injection, echo-safety, distinct-exit, gauntlet-shape fixtures. Applied. |
| Cross-file consistency | 4 | fetch-failure gated into Task 3/4; edit-ledger + changelog bookkeeping; all meaning-class edits followed by a stale-reference sweep. Applied. |

**Adversarial re-check (post-application):** an independent refutation pass on
the first applied predicate found a stale-local-ref false-*allow* (F1/F2) and a
cross-fork false-*deny* (F5) in the `is-ancestor` currency leg; the predicate was
re-settled server-authoritative, which removes all three. The empirical basis
was corrected mid-pass: an earlier "CLEAN is unsatisfiable for drafts" claim was
overgeneralized from stale PR #276 and retracted (current drafts do report
`CLEAN`; the real defect is `CLEAN` over-denying non-required-check `UNSTABLE`).
Live GitHub queries (PRs #276/#298/#300–#302) grounded the final predicate.

**Disposition summary:** every finding applied as an in-place Draft edit or an
explicitly accepted risk (register rows 2, 4, 6, 8); no finding deferred
undispositioned; no inconsistency left open. Six design forks were the human's
call (recorded via the kickoff dialogue): C1 predicate, C5 conflict protocol,
C2 target resolution, C4 base/wiring, C3 matcher scope, C9 catalog — plus the
server-authoritative currency-signal re-decision after the adversarial pass.

**Pre-flip verification:** `scripts/spec-validate.sh` clean (0/0); markdownlint
clean over the bundle; post-lens stale-reference sweeps run after every
meaning-class batch (predicate references, catalog references, minted REQ IDs
C1.9/C1.10/K1.3/B1.6 all reconciled). No numeric/derived claim is transcribed in
this brief that is not cited to its source file.

Class: meaning
Lens-pass: the §8 lens review pass recorded in this section (full-bundle
Discovery-Rigor fan-out + adversarial re-check; table above; all findings
dispositioned)
Anchor: `cb3b1dac20f7f4c4380b47ff1e8affbdfb11f0be` — computed as
`scripts/spec-anchor.sh specs/merge-currency-guard`

Signed off: 2026-07-22

## 9. Amendment log

### Amendment 1 — panel-pass currency-signal fix (2026-07-22)

Pre-merge re-sign-off of the Ready bundle (REQ-D1.4 delta re-walkthrough; the
spec PR stays as it was, no reopen). Triggered by the operator-directed
`/panel-review --nested` pass over the signed bundle.

**Delta:** the independent-model panel (gemini) found the §8 predicate's currency
signal critically broken (G1): `mergeStateStatus` reports `BEHIND` only under the
base branch's "require branches up to date" protection, which planwright's `main`
lacks — so a behind PR reads `CLEAN` (confirmed live: PR #276, 22 commits behind,
`mergeStateStatus CLEAN`/`mergeable MERGEABLE`) and the guard would **false-allow
the stale flip** the bundle exists to prevent. Currency moved to GitHub's compare
endpoint (`behind_by == 0`), which is branch-protection-independent and
server-side (PR #276 → `behind_by 23`; a current PR → `behind_by 0`).
`mergeStateStatus` dropped entirely (dissolving `DRAFT`/`HAS_HOOKS` handling and
REQ-A1.2's guard-covers-`BLOCKED` clause — the guard reads no check state).
Also: the `gh api graphql` ready-mutation surface demoted to a documented
residual (G3, opaque node-ID selector unresolvable under REQ-C1.9); the Bash
`isDraft` gate made symmetric with the MCP matcher (G4, no spurious deny of an
already-ready no-op). G2 (missing `DRAFT`/`HAS_HOOKS` test cells) dissolved with
`mergeStateStatus`.

**Lens pass:** the `/panel-review --nested` gemini discovery pass over the signed
diff (4 findings), each validated locally with the three-pass rigor — G1 by
direct reproduction against live PRs #276/#298/#300–#302 and the branch-protection
API; all four applied. Bundle re-validated `spec-validate` 0/0 as Ready;
markdownlint clean; post-edit stale-reference sweep run (residual
`mergeStateStatus` references confined to the D-3 rationale, rejected-alternatives,
a deliberate test-regression pin, and the changelog).

Class: meaning
Lens-pass: the `/panel-review --nested` gemini pass recorded in this amendment
(4 findings, three-pass-validated, all applied)
Anchor: `fe28fb81a1ac6c66c3fb163e4a8bca5b8739ce7a` — computed as
`scripts/spec-anchor.sh specs/merge-currency-guard`

Signed off: 2026-07-22
