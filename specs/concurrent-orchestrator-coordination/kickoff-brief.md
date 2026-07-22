# Concurrent Orchestrator Coordination — Kickoff Brief

**Spec path:** specs/concurrent-orchestrator-coordination
**Walkthrough date (run 5, this sign-off):** 2026-07-21
**Spec commit at run-5 walkthrough start:** c81259d (the `/spec-draft` origin-fence-only rework closing the run-4 multi-axis backlog)
**Validator outcome (pre-flight):** 0 errors, 0 warnings (clean)
**Mode:** First activation, run 5 — sign-off of the reworked bundle (Draft→Ready).

**Run history.** Runs 1–4 each **halted** on a genuine inconsistency on the
**work-division correctness axis** (see §8, preserved): run 1 the checkout-local
advisory lock; run 2 the local task-branch ref (reaches `origin` only at PR-open);
run 3 the passive origin ref with no cross-clone reaper; run 4 the machine-local
worker-liveness claim (Architecture A), which fixed *locality* but failed on the
worker-lifecycle / keying / version-skew / case-completeness axes it never checked.
Run 4's structural diagnosis (D-12): correctness here is **multi-axis** — stop
hunting the next interleaving, enumerate the axes once and answer every cell.

**Run 5 (this brief).** The bundle was reworked to **origin-fence-only
(Architecture B)** — one correctness floor (a per-unit `origin` fence ref, the one
substrate natively both cross-clone and death-surviving) plus a bounded-or-surfaced
residue model (D-13), with the failure-axis matrix (D-12) as a checkable coverage
contract. Sections 2–7 below are **refreshed to this reworked bundle** (the run-1–4
signed sections described superseded designs). The run-5 sign-off lens pass (§8,
run 5) ran a full-bundle 6-agent fan-out; it surfaced fixable defects (no
architecture inconsistency), which were **applied in place** (operator-approved,
2026-07-21) — most importantly the **STRICT** resolution of the dead-owner
downstream-artifact death-state cell — then re-verified CLEAN by a delta-lens pass.
**Outcome: SIGNED OFF, Draft→Ready.**

<!-- Sections 8 (sign-off) and 9 (amendment log) are written by the sign-off flow. -->

## 2. Goal & glossary

**Goal restatement (agent's words).** This bundle is the awareness + coordination
layer directly above `orchestration-concurrency`'s (Done) ledger state-safety
floor. State-safety guarantees no tower corrupts the shared `tasks.md` ledger or
drags foreign dispatch commits onto worker branches; it does not make a tower
*aware* of peers or stop two towers colliding. This bundle adds three mechanisms
and two doctrine statements to close that gap. (Full goal: `requirements.md` §Goal;
decisions in `design.md` D-1–D-13.)

- **Mechanism 1 — cross-tower awareness (D-2):** per-tower heartbeat files in a
  shared, user-private machine-local directory; discover peers by scanning + the
  tri-state `fleet-death-evidence.sh` predicate. No shared registry, no daemon, no
  LLM. **Off the correctness path** — used only to *attribute* an orphan fence to a
  dead owner.
- **Mechanism 2 — shared-`main` isolation (D-3):** separate per-tower checkouts
  (separate clones, each a private mutable local `main`) as the root fix, **not**
  git worktrees; single-checkout reconcile-via-quick-PR demoted to sanctioned
  degraded fallback; currency by `git fetch origin main && git merge --ff-only
  FETCH_HEAD`, never rebase (accounts for the `autosetuprebase=always` pitfall).
- **Mechanism 3 — work division (D-4, D-5, D-8, D-11): the authoritative floor.**
  A per-unit **`origin` fence ref** `refs/planwright-fence/<spec>/<unit-id>` created
  at dispatch **before the worker forks** by an atomic **expect-absent CAS** (the
  object-format all-zeros OID). `origin` serializes ref updates → exactly one tower
  fences a unit; it is natively **both cross-clone and death-surviving**, so no
  machine-local surface has to *fake* that locality (the failure class of runs 1–4).
  Cohesion bundles fenced together with `git push --atomic`. Strands are
  **surfaced to the operator, not auto-reclaimed** (D-7).
- **Doctrine (D-1, two statements):** primary — a tower **assumes multiplicity,
  not solitude**; companion (tower→human axis) — a **merge-ready PR reaches the
  operator by deterministic push, LLM-poll the fallback** (mechanism owned by the
  planned `merge-currency-guard`, cross-referenced, REQ-D1.6). Both extend
  `fleet-coordination-floor.md`; the altitude call is D-1, cited from the Goal.

**The guarantee is downgraded, deliberately (D-13).** Not the absolute "always
reclaimed / never double-dispatched" that runs 1–4 each asserted and each found an
interleaving under, but **best-effort exclusion (authoritative while `origin` is
reachable) + every residue bounded-and-swept OR durably surfaced, never silent.**
The **failure-axis matrix (D-12)** makes that checkable: {locality, worker-lifecycle,
keying/granularity, death-state machine, version/schema skew, recovery-per-fail-closed-
path, durable-sink-per-residue} — every cell answered; worker-lifecycle and
version-skew **dissolve** because the correctness floor is a git ref, not a parsed
record.

**Rules out (owned elsewhere, cross-referenced not implemented):** proactive
`/usage` quota governance (→ `fleet-autonomy`); the inter-orchestrator relay (→
`orchestration-fleet`); the deterministic PR-ready-push *mechanism* (→ planned
`merge-currency-guard`); ledger state-safety mechanics (→ `orchestration-concurrency`).
Re-opens nothing: auto-merge, autonomous PR-ready, tower non-authoring boundary all
carry in unchanged. **Not** in this bundle (removed with Architecture A): any
machine-local work-claim, reclaim lock, four-residue GC, or quarantine.

**Assumes:** `orchestration-concurrency`'s state-safety as an authoritative
contract; a reachable `origin` as the fence precondition for separate-clone
multi-tower (no-remote = the genuine single-checkout **solo** posture);
single-host co-location (now bounds only **strand attribution**, not correctness);
`fleet-death-evidence.sh` as the only sanctioned death signal; every
awareness/reclaim/division decision deterministic script logic, never model judgment.

**Glossary / implicit terms surfaced.**

- **Checkout (D-3 sense) = a separate clone**, not a git worktree. Load-bearing:
  planwright is worktree-heavy, but D-3 rejects worktrees (git forbids `main` in two
  worktrees; worktrees share one object store + `main` ref).
- **Fence ref = a dedicated-namespace `origin` ref** (`refs/planwright-fence/…`),
  keyed by unit id, **never** the worker's task-branch ref — so it exists before
  the worker branch does and carries no backend rename in the fencing path.
- **Presence surface / strand sink = a fixed machine-local path outside every
  checkout** (single-host), user-private (`0700`). There is **no `claims/`
  sub-surface** under Architecture B.
- **Terminal (STRICT) = a *merged* PR or ledger-done.** An **open, unmerged PR is
  NOT terminal** — see §3 REQ-C.
- **Tower, unit, meta-tower, positive-evidence-of-death** — per `spec-format`
  glossary and the `fleet-death-evidence` predicate; no local redefinition.

**Resolved ambiguities (run 5).**

- *How a dead owner's downstream artifact is treated (the run-5 crux, `origin`
  fence lifecycle).* **Resolved (operator, 2026-07-21): STRICT.** A positively-dead
  owner whose unit is **not terminal** — including one carrying only task-branch
  commits or an **open, unmerged PR** — is a **strand → surfaced** (no live tower
  will carry it to merge). Only a **merged** PR or ledger-done is terminal → GC.
  This closes the run-4 "commits-no-PR strand neither surfaced nor GC'd" cell and
  makes D-13's "never silent" hold. (The alternative, LENIENT — treat any artifact
  as hands-off — was declined: it leans on the operator noticing a stale branch, the
  poll-only weakness D-1's companion doctrine argues against.)
- *Machine-local surface location + single-host scope* — carried from run 1 (a
  fixed path outside every checkout; cross-machine peers out of scope), now bounding
  only attribution, not correctness (D-11).

Signed off: 2026-07-21

## 3. Requirements walkthrough

Group intents restated and probed against the reworked (origin-fence-only) bundle.
REQ text: `requirements.md` (4 groups A–D). Outcomes below.

**REQ-A — Cross-tower awareness.** Intent: a tower discovers live peers from a
derived, on-demand presence signal and never assumes solitude; publish is
distinct-per-writer + atomic; reclaim/attribution is death-evidence-only (tri-state,
unknown≠dead), deterministic, no LLM; discovery fails closed on a broken surface
(never read as solitude), first-run bootstraps via a persistence sentinel.
Outcome: intent sound. Under Architecture B, **presence is off the correctness
path** — a broken surface degrades *awareness/attribution* but **dispatch proceeds**
(the fence, not the surface, excludes). Tower identity is deterministic (session
UUID, else pid+start-time+checkout-hash composite; never bare pid or checkout-path
alone, REQ-A1.7). Run-5 hardening applied: the **persistence sentinel lives outside
the surface dir** and its write-failure fails closed; an **unknown-owner orphan is
surfaced only after a one-pass grace re-check** (the heartbeat-lag window between a
live owner's fence push and its next record refresh must not raise a false strand).

**REQ-B — Shared-`main` isolation.** Intent: separate per-tower checkouts as root
fix, invariants preserved, migration path + sanctioned single-checkout fallback,
`--ff-only` fetch-then-merge currency past the `autosetuprebase` pitfall, fetch
failure **classified** (no-`origin` → solo flow vs transient → fail closed).
Outcome: sound. The per-clone machine-local env layer + **stable `auth_sock`
symlink** (the 2026-06-12 signing-break lesson) is a Task 3 migration deliverable
with a manual-sweep Done-when anchor.

**REQ-C — Work division (the correctness core).** Intent: no unit dispatched by
more than one tower, authoritative in the `origin` fence CAS; cohesion bundles
fenced atomically; strands **surfaced not auto-reclaimed**; GC-on-terminal;
origin-reachability classified (never fail open); durable dedup'd sink. Outcome:
sound after the run-5 fixes. Key resolutions applied this run:
- *Dead-owner death-state — **STRICT** (operator, 2026-07-21):* terminal-first,
  then liveness. **Terminal = merged PR / ledger-done → GC** regardless of owner
  liveness; else live owner → honor; else dead + not-terminal (no artifact,
  commits-no-PR, **or open-unmerged PR**) → **surface**; unclassifiable /
  unknown-owner → surface. Full 20-cell cross-product verified non-silent.
- *Fence-push failure classification (EH-F1):* a rejected expect-absent CAS vs a
  transient push failure — **both non-zero `git push`** — are distinguished by the
  **per-ref rejection status** (`--porcelain`/stderr), not exit code alone; a
  misclassification costs one wasted pass, never a double dispatch.
- *CAS literal (SpecVsCode-F1/F6):* the push uses the **object-format all-zeros OID**
  (`:$ZERO_OID`, 40/64 hex), never the bare-empty `:` form (the run-4 defect,
  finally fixed in the literals, not only the prose).
- *Meta-tower detection:* via the presence record's **own validated meta-marker
  field** (not `fleet-tower-marker.sh`, whose field is the orthogonal
  `unattended|interactive` mode).

**REQ-D — Carried floors, boundaries & hygiene.** Intent: don't re-implement the
relay or usage governance; carry auto-merge / autonomous-ready / non-authoring
floors unchanged; framework-script security bars (D-9); same-operator single-host
attribution (grammar-validate + refuse-malformed, no adversarial spoof-proofing);
companion doctrine line (D1.6, mechanism cross-referenced out). Outcome: sound.
Run-5 hardening: the **unit-id/spec-id now carry a declared grammar** and the
fence-ref name is contained via **`git check-ref-format` + literal-prefix** (not
filesystem "canonicalization"), since those two fields reach an `origin` ref
push *and delete* (the delete path enumerates orphan refs — untrusted surface data).

### Consolidated spec-edit list (run 5 — applied in place, Draft bundle, then re-validated)

Genuine inconsistencies (unambiguous fixes): **F0** matrix recovery-cell said "halt
dispatch" (contradicted D-10 "proceed"); **F1/F2/F4** the STRICT death-state
resolution above (REQ-C1.3/C1.5, D-7, matrix, Sources note, tasks, test-spec);
**CrossFile-B1/B2** stale `claims/`-layout and `claim GC` cross-refs repointed;
**SpecVsCode-F1** all-zeros literal written; **SpecVsCode-F2** the phantom
two-backend fence fixture rewritten backend-independent. Must-fix: **Tests-F1**
added the two missing `[manual]` Done-when anchors (Task 3 / Task 4); **Security-F1**
unit-id/spec-id grammar + check-ref-format; **EH-F1** the CAS-vs-transient
discriminator. Robustness (could resurface): **F3** grace re-check; **EH-F4**
sentinel location + write-failure; **EH-F5** over-broad-surface halt action.
Hygiene: obs `entries/`→`archive/` paths, vestigial "claim" vocabulary,
`merge-currency-guard` note. Deferred non-blocking backlog → `obs:c898c154`
(EH-F2/F3, F5, F7, F8, Tests-F2/F3, a clarity cross-ref).

Signed off: 2026-07-21

## 4. Design walkthrough

Every D-ID (D-1…D-13) accounted for against the reworked bundle. After the run-5
fixes, no design decision contradicts a walked requirement (the F0/F1/F2 contradictions
were *resolved in place*, not carried). Reconciled ledger:

| D-ID | Disposition | Note |
| --- | --- | --- |
| D-1 | Confirmed | Altitude record — mechanism-primary + **two** doctrine statements (assume-multiplicity; deterministic-push companion); cited from Goal. |
| D-2 | Confirmed (run-5 hardening) | Presence = per-tower heartbeat files, off the correctness path; sentinel-outside-surface + grace-re-check added. |
| D-3 | Confirmed | Separate clones as root fix; worktree rejection sound; `--ff-only` currency; `origin` reachability now the fence precondition. |
| D-4 | Confirmed | Reuse meta-tower selection + relay; the peer **fence** is additive; no second relay. |
| D-5 | Confirmed | The exclusion primitive = expect-absent CAS creating the per-unit `origin` fence ref (all-zeros OID literal corrected). |
| D-6 | Confirmed | Single-owner scope boundary (usage→fleet-autonomy; relay→orchestration-fleet; ready-push→merge-currency-guard). |
| D-7 | Confirmed (STRICT applied) | Fence lifecycle: GC-on-**merged**/ledger-done, dead-owner non-terminal (incl. open-unmerged-PR) surfaced, durable dedup'd sink; no reclaim apparatus. |
| D-8 | Confirmed | The `origin` fence ref is the authoritative cross-clone exclusion floor. |
| D-9 | Confirmed (run-5 hardening) | Numbered home for the framework-script security bars + same-operator attribution; unit-id/spec-id grammar + check-ref-format added. |
| D-10 | Confirmed (F0 + EH-F1 applied) | Recovery action per fail-closed path; matrix cell corrected to "proceed"; CAS-vs-transient discriminator pinned. |
| D-11 | Confirmed | Authoritative in-flight signal = `origin` fence ref; **no** machine-local claim (the run-4→5 inversion). |
| D-12 | Confirmed | Failure-axis matrix as a coverage contract; the kickoff lens verified cell-completeness (20-cell cross-product, none silent). |
| D-13 | Confirmed | Guarantee downgraded to bounded-or-surfaced, never silent — what makes the STRICT death-state a coverage item, not a contradiction. |

**Inconsistency handling (run 5).** The lens pass surfaced genuine inconsistencies
(F0, F1, F2) — but with **unambiguous resolutions inside Architecture B**, not the
architecture forks that halted runs 1–4. Per the Draft-bundle edit rule they were
applied in place (F1 via the operator's STRICT choice), re-validated (0/0), and
re-verified CLEAN by a delta-lens. No design decision was reversed; D-11's
architecture inversion (run 4→5) is recorded once and stands.

Signed off: 2026-07-21

## 5. Verification approach

Coverage mix (`test-spec.md`): predominantly **`[test]`** — every mechanism is
deterministic script logic over structured signals (per-tower record files, the
`fleet-death-evidence` predicate, git ref state), all fixture-testable. The
authoritative fence is tested against a **local bare-repo `origin` fixture** (two
clones race the expect-absent CAS → one winner; the loser rejected — order-independent,
not timing-flaky). Atomicity asserted **structurally** (the write primitive *is*
temp-then-rename; the fence *is* an expect-absent CAS), never the flaky "reader
never sees a torn record." Negative assertions verify Architecture A's *absence*
(no `claims/` sub-surface, no reclaim lock, no four-residue GC, no quarantine).

**Ownership.**
- `[test]` → repo CI (`mise run check`).
- `[manual]` → the genuinely multi-checkout / multi-tower E2E confirmations a fixture
  cannot stand in for: REQ-B1.1 (two towers on two checkouts, no shared-`main` mutation),
  REQ-B1.3 (fresh clone signs+fetches via its own env/`auth_sock`), REQ-C1.6 (two clones
  one `origin` → single worker/PR). Each now carries an explicit **Done-when dated-entry
  anchor** in Task 3 / Task 4 verification notes (Tests-F1 fix) so none is silently droppable.
- `[design-level]` → doctrine + matrix cell-completeness + cross-reference REQs, with
  *positive* "the relay is consumed" assertions (not only grep-for-absence).

**Dead-path / soft-spot check.** No REQ lacks a runnable verification. Run-5 test-spec
fixes: REQ-C1.3/C1.5 fixtures rewritten to the **STRICT** reading (dead-owner+commits-no-PR
→ surface, dead-owner+open-unmerged-PR → surface, only merged/ledger-done → GC); the
phantom two-backend fence fixture (REQ-C1.2) rewritten backend-independent. Deferred
test-breadth backlog (non-blocking, `obs:c898c154`): an adversarial stale-tracking-ref
fixture (Tests-F2) and converting vacuous absence-greps to positive assertions (Tests-F3).

Signed off: 2026-07-21

## 6. Task graph

Reconstructed from `tasks.md` `Dependencies:` lines (authoritative; rendered via
`spec-graph.sh`). Counts/effort cited from `tasks.md`. **The graph changed under
Architecture B** (the run-3/4→5 inversion): because the fence lives on `origin`,
Task 4's *correctness* now depends on Task 3's `origin` topology, and its
*attribution/surfacing* on Task 2's presence surface — so **Task 4 depends on both
Task 2 and Task 3**, and the correctness critical path runs through **Task 3**, not
Task 2.

- **Edges:** Task 1 → {2, 3, 4, 5}; {Task 2, Task 3} → Task 4.
- **Critical path (effort-weighted):** 1 → 3 → 4 = **5 days** (Task 1 1d + Task 3
  2d + Task 4 2d); Task 2 (2d) runs parallel to Task 3.
- **Parallelism after Task 1:** Task 2 ∥ Task 3 ∥ Task 5; Task 4 joins after both
  Task 2 and Task 3.
- **Dispatch order:** Task 1 first; then **Task 5 guard-first** (hygiene/infra guard
  outranks the critical path once Task 1 lands, per the guard-tasks-first rule);
  Task 2 ∥ Task 3; Task 4 after **both** 2 and 3.
- **Deliberate non-edges (do not "fix"):** **Task 3 ⊥ Task 2** (checkout topology
  needs no presence signal — the load-bearing non-edge; Task 3 is on the correctness
  path, Task 2 is not); Task 5 ⊥ Task 2/4 (the guard depends only on Task 1's floors).

Signed off: 2026-07-21

## 7. Risk register

Inputs: risks surfaced during the walk + the **decision-domains gap check**
(`design.md` §Decision-domains walk, via `resolve-catalog.sh decision-domains`).
Catalogued domains the feature touches — **concurrency** (the central domain),
**integration-surface** (the `origin`/checkout topology), **authentication/attribution**
(tower identity, same-operator single-host model), **observability** (broken-surface
+ durable-sink) — are **all decided in-spec**; secrets/config is **conditional**
(only if the surface path becomes configurable → R6); no catalogued domain is
touched-but-undecided.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| R1 | **The five-halt recurrence** — a further un-enumerated correctness axis surfaces on a later pass, as in runs 1–5. | The D-12 coverage matrix converts "find the next interleaving" into "answer every cell"; the kickoff lens now checks **cell-completeness** (20-cell cross-product verified non-silent this run). Early signal: any execution-time death-state a fixture cannot classify to {honor, surface, GC}. |
| R2 | **`origin` unreachable → no fence** — the authoritative floor requires a reachable `origin`; a misclassified transient failure could fail open. | Origin-reachability **classified** (REQ-C1.6/D-10): no-`origin` = genuine solo posture, transient = fail closed, rejected-CAS vs transient split by per-ref status (EH-F1). No-remote multi-tower is out of scope. Early signal: a dispatch with no fence on a configured `origin`. |
| R3 | **Silent strand** — a dead owner's unfinished work sits invisible (the run-4 case). | STRICT death-state: dead-owner + not-terminal (incl. commits-no-PR, open-unmerged-PR) → **surfaced** to the durable dedup'd sink; D-13 "never silent." Early signal: a fence with no owner and no operator sink entry. |
| R4 | **Signing/fetch break across clones** — a captured ephemeral `auth_sock` or missing per-clone env file (the 2026-06-12 lesson). | Stable `auth_sock` symlink + per-clone repo-root machine-local env (Task 3 migration, manual-sweep anchor). Early signal: publickey-denied on a fresh clone. |
| R5 | **Crafted unit/spec id drives a ref op outside the fence namespace** — the delete path enumerates orphan `origin` refs (untrusted). | Declared unit-id/spec-id grammar + `git check-ref-format` + literal-prefix containment before any push/delete (REQ-D1.5/D-9, Security-F1). Early signal: a ref op targeting outside `refs/planwright-fence/<spec>/`. |
| R6 | **Undocumented config option** — if the surface path becomes configurable it must reach the options reference. | Existing options-reference guard (`check-options-reference.sh`) at Task 2. |
| R7 | **Trust-model breach** — the single-host same-operator model is insufficient under untrusted co-tenancy. | Documented single-host assumption (D-9); `0700` verify-or-refuse; revisit attribution if co-tenancy appears. |
| R8 | **Fence-namespace / server precondition** — an `origin` ruleset restricting `refs/planwright-fence/*` or not advertising `atomic` rejects every fence push (availability, fails closed). | Deferred precondition note (`obs:c898c154`, F8); fails closed + surfaced, never fail-open. Early signal: every fence push rejected on a configured `origin`. |

Every run-5 ambiguity resolved to a decision (the applied fixes) or an accepted /
deferred risk (R1–R8; backlog `obs:c898c154`). The sign-off lens pass and its
disposition are recorded in §8 (run 5).

Signed off: 2026-07-20

## 8. Sign-off (run 1, 2026-07-20) — HALTED (fail closed, no anchor)

**Superseded by §8 (run 2) below.** Run 1's sign-off lens pass halted on the
checkout-local-lock inconsistency (the per-spec advisory lock at
`<spec-dir>/.orchestrate.lock` cannot serialize claims across D-3's separate clones)
plus ~20 coordination-mechanics gaps, all deferred to a `/spec-draft` rework. That
rework happened (spec commits `228e835`→`e69556e`, changelog 2026-07-20) and closed the
run-1 backlog by making the claim its own serializer and demoting it to a best-effort
optimization *below* `orchestration-concurrency`'s branch-as-fence. Run 2 (below) is the
re-kickoff of that reworked bundle. The full run-1 detail lives in git history
(commit `6fb6ff9`) and the `requirements.md` changelog; it is not re-transcribed here.

## 8. Sign-off (run 2, 2026-07-21) — HALTED AGAIN (fail closed, no anchor)

**This run did not sign off.** The re-kickoff's full-bundle Discovery-Rigor lens pass
surfaced a **second genuine inconsistency on the same work-division correctness axis**,
plus ~39 findings after dedup. Per the inconsistency halt (REQ-B2.3) and the refusal
rule (REQ-F1.10): **no Draft→Ready flip, no anchor line, no push, no spec-PR.** The
bundle stays Draft.

**Operator resolution (2026-07-21): Option A — establish the fence at dispatch.** Add a
requirement that dispatch pushes the task branch to `origin` **immediately at dispatch**
(before the worker runs), so the branch-as-fence is genuinely live cross-clone from
dispatch *and* survives the dispatching tower's death — the durable, peer-visible,
death-surviving in-flight marker that both the double-dispatch window and the
orphan-worker reclaim need. Stated preconditions: a reachable `origin` is required for
separate-clone multi-tower (no-remote stays the single-checkout solo flow); branch names
must be byte-identical across clones. Compatible with `orchestration-concurrency`, which
rejected pushing bookkeeping *commits to main*, not a task-branch *ref*. Routed to a
`/spec-draft` rework to instantiate, then re-kickoff.

### Lens pass — path and coverage (run 2)

Path: parallel read-only sub-agent fan-out, six agents covering the nine canonical
lenses, per `discovery-rigor` (non-trivial bundle). Findings validated per
`validation-rigor` (three-pass + adversarial); the pivotal branch-as-fence timing claim
confirmed against ground truth (`orchestration-concurrency` design.md:41 rejects
push-at-dispatch, REQ-A1.3 makes no-remote first-class; `execute-task` SKILL.md:349
pushes only at PR-open, post-convergence). Three independent lenses (correctness,
concurrency, error-handling) converged on the root defect.

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 8 | **Halt cluster**: branch-as-fence not cross-clone-live at dispatch; orphan-worker reclaim; REQ-C1.1↔Task-4 contradiction; branch-name determinism; no-remote gap; corrupt-claim strand; PID reuse; Task 2→4 verify cycle |
| Security | 6 | `0700` named as enforcement but no verify-or-refuse on over-broad surface; meta-marker / checkout-path / death-handle omitted from validated-field list; death-handle grammar undeclared + leakable; surface-root symlink (mostly OOS) |
| Error handling / failure modes | 13 | Fail-closed-**then-what** undefined across the board (fetch-error, ENOENT absent-vs-unreadable, surface-error action, `--ff-only` refusal, release-rm failure, concurrent bootstrap); no-remote contradictions; corrupt-claim + orphan-temp strands |
| Performance | 2 | Death-predicate subprocess per record per heartbeat, unbounded / spec-silent; discovery scan scope described two incompatible ways (also cross-file) |
| Concurrency / state | 6 | Same halt cluster from the race angle; presence-GC unguarded `rm` (vs hardened claim-GC); tower-identity derivation unspecified; PID reuse; orphan temps; `0700` create not atomic |
| Naming, readability, structure | 2 | External `REQ-D1.x` refs collide with local IDs (bare, not namespaced); "lock" overloaded across the reclaim section |
| Documentation | 3 | `orchestration-fleet REQ-D1.7` dangling (only D1.1–D1.6 exist, confirmed); `obs:8cbe0123` / `obs:3ecf4293` resolve to no files (confirmed); rest of Sources checks out |
| Tests / verification | 6 | Atomicity pinned to an unobservable/flaky "never observes torn" assertion; `fetch origin main:main` path untested; REQ-B1.1 two-tower `[manual]` un-anchored / droppable; grep-for-absence passes vacuously; fence assertion un-harnessed; meta-tower test hedged to nonexistence |
| Cross-file consistency | 4 | REQ-D1.4/D1.5 cite D-6 (scope-boundary only) — the security bars have **no numbered decision home**; stale-reclaim-lock GC verified by tasks/test but no REQ mandates it; sync two-option narrowed; brief §8 (this section, run 1) presented the superseded pre-rework design as normative |

**Altitude check (REQ-H1.3):** triggered bundle; D-1 altitude record present, cited from
the Goal, decomposition matches mechanism-primary + one doctrine line. OK — not a finding.

### The inconsistency halt (finding #1 cluster)

**REQ-C1.1 / D-5 designate `orchestration-concurrency`'s branch-as-fence as the
authoritative cross-clone no-duplicate-*dispatch* guarantee, "verified immediately before
dispatching," that "catches the duplicate before a second worker starts," so residual
claim races cost only "wasted *selection* work, never a double dispatch." Under D-3's
primary separate-clone topology this is false.** The task branch is created *locally* at
dispatch and reaches `origin` only at PR-open (post-convergence, hours later), so across
separate clones there is no fence on `origin` for the entire worker run. A claim lost in
the dispatch→first-push window (GC / stale-break — the design's own "safe" cases) lets a
peer clone's pre-dispatch check pass and dispatch a **second full worker** on the unit;
only the second *PR* is rejected. That is a double **dispatch**, which REQ-C1.1 says
never happens — and Task 4's own Done-when contradicts REQ-C1.1 by validating success via
"the second tower's *rejected origin push*" (conceding a worker ran to push time).

**Both readings:** (a) the spec *means* dispatch establishes an `origin` fence
immediately — unstated, and it would need to be added; (b) the spec means the *local*
branch-ref fence — invisible across clones. Either way the bundle is internally
inconsistent as written. **Resolution chosen: (a), Option A above (fence at dispatch).**

### `/spec-draft` rework backlog (run 2) — ~39 findings, all meaning-class seed

Recorded here and in the observations log as `/spec-draft` seed (`obs` fragment this
run). Grouped by cluster; `[Cn]` = converged across n independent lens agents.

- **Halt cluster — no authoritative cross-clone fence at dispatch (Option A instantiates
  the fix):** #1 branch-as-fence absent during dispatch→first-push window → double
  dispatch `[C3, CRITICAL]`; #2 reclaim downstream-artifact guard blind to a dead tower's
  not-yet-pushed orphan worker → re-dispatch into live duplicate `[C2, HIGH]`; #3
  REQ-C1.1 "never reaches a worker / wasted *selection* work" contradicts Task-4 Done-when
  "rejected origin push" `[HIGH]`; #4 fence requires byte-identical cross-clone branch
  names — unstated; repo history shows `claude --worktree` name-mangling → two branches /
  two PRs, fence fails entirely `[MED]`; #5 no-remote separate-clone multi-tower has no
  authoritative layer (no `origin` to arbitrate); repo-id no-`origin` fingerprint
  unspecified `[C2, HIGH]`; #6 the fence check's own error / lost-observability outcome
  undefined (fail-open reopens the incident class) `[HIGH]`.
- **Fail-closed → then-what undefined:** #7 REQ-B1.4 blanket "failed fetch fails closed"
  contradicts no-remote degrade; never distinguishes no-remote from transient `[HIGH]`;
  #8 "absent vs unreadable" undecidable — same ENOENT in both buckets, no persistence
  marker → vanished surface reads as solitude or breaks first run `[HIGH]`; #9 after a
  fail-closed surface error the tower's action is undefined, and the claim layer (same
  dir) is down simultaneously `[HIGH]`; #10 `--ff-only` refusal recovery action undefined
  `[MED]`; #11 live-tower release-`rm` failure → un-reclaimable, un-GC'able claim, no
  retry `[MED]`; #12 concurrent first-run `mkdir` EEXIST handling undefined `[LOW]`.
- **Corrupt / leak / strand:** #13 a corrupt *claim* record is honored forever but can
  never be GC'd (GC needs to parse owner + death handle) → permanent strand + leak, no
  operator/quarantine path `[C2, MED]`; #14 orphan temp files from the atomic
  create-with-content leak on crash, un-swept, poison the presence scan forever `[C2,
  MED]`; #15 rename/hardlink atomicity has an unstated same-filesystem precondition
  (`$TMPDIR` / EXDEV) `[LOW-MED]`.
- **Death handle / PID:** #16 bare-PID death handle defeated by PID reuse → false alive →
  strand, breaking REQ-C1.3's "a crashed tower never strands a unit"; needs a
  reuse-resistant discriminator (process start-time) or a handle-grammar decision `[C2,
  HIGH]`; #17 the death handle's "declared grammar" is never declared in the bundle
  `[LOW]`; #18 the death handle (pid / tmux session+window name) is leakable operational
  detail, absent from the no-leak set and the Task 5 scan targets `[LOW]`.
- **Identity / presence:** #19 tower-identity derivation is unspecified, yet
  distinct-per-writer presence AND self-exclusion both rest on it — two towers on one spec
  can collide (overwrite a peer's record / self-exclude a peer) `[MED]`; #20 presence-file
  GC is an unguarded `rm` (no under-lock re-read, unlike the it3-hardened claim GC) → a
  dead-then-restarted tower's fresh live record is deleted `[MED]`.
- **Security (trust enforcement + field completeness):** #21 `0700` is named as *the*
  same-operator trust enforcement but nothing verifies-or-refuses a pre-existing
  over-broad surface, and creation is not shown atomic `[C2, MED]`; #22 the meta-tower
  marker is omitted from REQ-D1.5's grammar-validated field list + test, though it drives
  a defer-to-authority decision `[MED/LOW]`; #23 the checkout-path field is omitted from
  the validated-field list `[LOW]`; #24 a surface-root symlink defeats path containment
  (co-tenant exploit OOS; robustness note in-scope) `[LOW]`.
- **Performance:** #25 discovery fans out the death-predicate subprocess per record on
  every heartbeat — unbounded, spec-silent (no cadence cap, no per-pass liveness cache)
  `[MED]`; #26 the discovery scan *scope* is described two incompatible ways — REQ-A1.1
  filter-the-whole-host-surface vs D-2 per-`<repo-id>/` subdir `[LOW-MED, also cross-file]`.
- **Tests / verification:** #27 both atomicity claims are pinned to an unobservable
  "reader never observes a torn/empty record" assertion (flaky by construction); only the
  structural "primitive is `rename`/`link`, not `mkdir`+populate" check is sound `[MED]`;
  #28 REQ-B1.4's mandated `git fetch origin main:main` ref-update path is untested and
  Task 3's Done-when drops it `[C2, MED]`; #29 REQ-B1.1's two-real-tower `[manual]` proof
  has no Done-when anchor / owner → silently droppable `[MED]`; #30 REQ-D1.1/D1.2 verified
  only by grep-for-absence — passes vacuously, never verifies the positive "consumes the
  relay" claim `[LOW-MED]`; #31 the newly-authoritative branch-as-fence push-rejection
  assertion has no described harness and no real-`origin` cross-check `[LOW-MED]`; #32 the
  meta-tower `[test]` is hedged ("asserted or documented-and-delegated") into possible
  non-existence `[LOW]`.
- **Cross-file / docs:** #33 `orchestration-fleet REQ-D1.7` is a dangling reference (only
  REQ-D1.1–D1.6 exist), and the bare external `REQ-D1.x` refs collide with this bundle's
  own `REQ-D1.x` IDs (namespace them) `[C3, MED]`; #34 REQ-D1.4 / REQ-D1.5 / Task 5 cite
  D-6, whose decision is only the scope boundary — the framework-script security bars and
  the attribution model have **no numbered decision record**, living only in un-numbered
  Cross-cutting prose `[MED]`; #35 tasks.md + test-spec verify "stale reclaim lock broken
  during discovery," but no REQ mandates it (REQ-C1.5 mandates only dead-*claim* GC; D-7
  breaks the lock on-contention) — add the clause or drop the over-spec `[C2, MED]`; #36
  the two canonical seed sources `obs:8cbe0123` and `obs:3ecf4293` resolve to no files
  under `specs/_observations/` (confirmed) — broken provenance `[MED]`; #37 REQ-D1.1 cites
  only D-6, omitting D-4 (the decision that most directly grounds it) `[LOW]`; #38 Sources
  routes readers to this brief's run-1 §8, which presented the reversed pre-rework design
  as live — now marked superseded above `[LOW]`; #39 "lock" is overloaded across the
  reclaim section (advisory / per-unit reclaim / rejected alternatives) `[LOW]`.

### Halt record (run 2)

Class: n/a (no sign-off recorded — inconsistency halt, REQ-B2.3).
Lens-pass: recorded above (six-agent fan-out, nine lenses, canonical coverage table);
the inconsistency is unresolved on disk (operator chose Option A, to be instantiated by
`/spec-draft`), so per REQ-F1.10 no execution-valid anchor is written. The freshness gate
treats the absent anchor as blocking — dispatch stays blocked until a fresh kickoff signs
off the re-reworked bundle.
Anchor: (none — fail closed)

Next step: `/spec-draft specs/concurrent-orchestrator-coordination` to instantiate
**Option A (fence at dispatch)** as the authoritative cross-clone dispatch-time fence and
work the full run-2 backlog above (leading with the correctness model, not re-mechanizing
the claim primitive first), then re-run `/spec-kickoff`.

## 8. Sign-off (run 3, 2026-07-21) — HALTED AGAIN (fail closed, no anchor)

**This run did not sign off.** The focused delta walk on the fence-at-dispatch rework
surfaced a **third genuine inconsistency on the same work-division correctness axis**, plus
a validated ~18-finding backlog. Per the inconsistency halt (REQ-B2.3) and the refusal rule
(REQ-F1.10): **no Draft→Ready flip, no anchor line, no push, no spec-PR.** The bundle stays
Draft.

**Operator resolution (2026-07-21): Option a — halt and route to `/spec-draft`.** The fix is
a genuine fourth iteration of the correctness model (a cross-clone reaper / worker-liveness
signal for the origin fence ref, reconciliation of the per-unit fence with cohesion-bundle
dispatch, no-remote enforcement, and alignment of the fence's naming/sequencing with the
*actual* shipped dispatch primitives) — too much to bolt on mid-walkthrough, and the
"lead with the correctness model" discipline argues for drafting it deliberately.

### The inconsistency halt (headline finding, confirmed)

**REQ-C1.3 promises "a *crashed* tower never strands a unit," but under D-8/D-7 a tower that
crashes after the fence push but before its worker ever reaches PR-open strands the unit
permanently.** The D-8 fence ref is pushed to `origin` at dispatch pointing at the *base
commit* (zero-commit), and `execute-task` pushes the worker's commits only at PR-open
(confirmed SKILL.md:349) — so from `origin` the fence ref is a zero-commit ref with no PR for
the whole worker run. The D-7 reclaim guard refuses reclaim whenever "the unit's task-branch
ref on `origin` or an open PR" exists — mere ref existence, no stale-break, no commit test —
and **no GC sweep touches `origin` refs** (the three sweeps are all machine-local).
`orchestration-concurrency` *does* recover exactly this case, via its timestamped dispatch
marker + "zero-commit branch → stale → revert to Ready" rule (OC design.md:96–100) — **but
that marker is checkout-local** (COC's own framing, requirements.md:561–562, the basis of the
run-1 halt), so under D-3 separate clones a peer can't see it and the recovery never fires
cross-clone. **D-8 moved the fence to `origin` but left the recovery/stale-break
checkout-local — the exact mirror image of the run-2 halt.**

**Both readings:** (a) the spec *means* the fence ref must carry a cross-clone
worker-liveness/staleness signal so a provably-not-in-flight ref is reapable — unstated, must
be added; (b) the spec means bare-ref existence blocks reclaim indefinitely — which
contradicts REQ-C1.3's own "a crashed tower never strands a unit." Either way the bundle is
internally inconsistent as written. **Resolution chosen: (a), routed to `/spec-draft`.**
**Crux:** safe recovery needs a *cross-clone signal that the WORKER (not just the tower) is
dead* — reclaim on tower-death alone is exactly the live-orphan-worker case D-8 exists to
protect (worker commits sit local in the dead clone until PR-open), and `origin` alone can't
tell "dead worker, zero-commit ref" from "live worker, commits not yet pushed."

### Lens pass — path and coverage (run 3)

Path: three parallel read-only adversarial sub-agents (Explore) over the fence/reclaim/
dispatch correctness axis — the axis the run-3 rework changed and where a run-4 kickoff would
otherwise find the next hole — rather than a full nine-lens whole-bundle sweep (run-2's
non-correctness findings were closed by this rework and would largely be reshaped by it).
Agents: (1) fence & dispatch race hunter, (2) reclaim & lifecycle hole hunter, (3) cross-clone
signal locality auditor. Each cleared its own false positives and grounded findings against
real code — including the shipped `scripts/fleet-dispatch-worktree.sh` and OC's design. Three
converged on the "no cross-clone reaper for the origin fence ref" root.

**Altitude check (REQ-H1.3):** triggered bundle; D-1 altitude record present, cited from the
Goal, decomposition matches mechanism-primary + one doctrine line. OK — not a finding
(unchanged from run 2).

### `/spec-draft` rework backlog (run 3) — validated, grouped by cluster

`[Cn]` = converged across n independent lens agents. Severities are the agents' calibrated
ratings after false-positive clearing.

**Cluster 1 — the origin fence has no cross-clone reaper (headline + generalizations).**
- **H1 (headline, `[CRITICAL]`, confirmed):** zero-commit orphan fence ref from an
  early-crashed tower permanently blocks reclaim (above). OC's stale-break is checkout-local.
- **H2 (`[HIGH]`, agent-3 F1):** *generalization* — an orphan ref **with commits** (worker
  committed then died pre-PR) strands identically; same root, broader than the zero-commit case.
- **H3 (`[HIGH]`, `[C2]`):** **no origin-ref GC on any non-merge terminal path.** GitHub's
  auto-delete-head-branch fires *only on merge*; a **closed-unmerged / abandoned** PR leaves
  the ref → blocks re-dispatch and reads in-flight forever. And if auto-delete *is* enabled,
  a rejected PR re-dispatches deliberately-rejected work on every pass (a dispatch/reject
  loop). The outcome flips on an **unstated GitHub branch-deletion policy**.
- *Root & fix shape:* D-8/D-7 introduce a death-surviving origin ref but **no reaper** for it
  on any path but clean merge. Needs a cross-clone worker-liveness/staleness signal plus a
  fence-ref reclaim path (delete the origin ref + re-dispatch when the unit is provably not in
  flight), mirroring OC's zero-commit-branch stale-break *at `origin`*.

**Cluster 2 — new breaks of the AUTHORITATIVE guarantee / fail-open (not just availability).**
- **A1 (`[CRITICAL]`, agent-1 #1):** **lost-CAS-ACK live-tower strand.** `origin` writes the
  ref, network cut before the tower reads the response → the tower is *alive*, fails closed,
  does not dispatch; the ref exists but **encodes no owner** (every tower pushes the identical
  base-sha), so no tower can prove ownership and the owner is not positively dead → never
  reclaimed → permanent strand of a *live* tower's unit. Implies the fence ref should encode
  owner identity and/or the CAS needs an idempotent-retry story. D-10 has no entry for this path.
- **A2 (`[CRITICAL/HIGH]`, agent-1 #4):** **cohesion-bundle units are unfenced.** Dispatch
  supports a task *or a cohesion bundle* sharing one branch/PR (the lead id); non-lead bundle
  units have **no `origin` fence ref of their own**, so a peer independently selecting a
  non-lead unit fences successfully → genuine double **dispatch**. The *authoritative*
  guarantee fails for every non-lead bundle member; the per-unit fence is never reconciled
  with bundle dispatch (which `/orchestrate` and `/execute-task` both support).
- **A3 (`[MED]`, the *only* fail-open case, agent-3 F3):** **no-remote multi-tower fails
  OPEN.** The "every residual race degrades to wasted selection work" claim is *conditional on
  the fence*, which requires a reachable remote. No-remote multi-tower is a *declared*
  precondition but **not mechanically enforced**; an operator running two towers with no
  remote (separate clones one host, or two towers one checkout) gets a genuine double dispatch
  with no backstop. Needs enforcement (refuse / detect-and-degrade), not just documentation.

**Cluster 3 — the spec models dispatch against the wrong (non-shipped) picture.**
- **S1 (`[HIGH]`, agent-1 #3, confirmed vs `fleet-dispatch-worktree.sh:3-4,577`):** REQ-C1.6 /
  D-8 / Task 4 pin a normative "dispatch **SHALL rename** the worktree branch to the canonical
  name before the fence push," but the shipped subagent primitive creates the canonical
  `planwright/<spec>/task-<id>` **directly** via `git worktree add -b`, deliberately "with no
  manual post-launch rename." The rename is needed *only* on the `claude --worktree`/tmux
  backend (which mangles slashed names — and this machine's `dispatch_backend: tmux` uses it).
  The spec models a single rename-then-push flow and ignores the two backends' different naming
  behavior.
- **S2 (`[HIGH]`, agent-1 #3 cont.):** the fence push is **never sequenced relative to worker
  launch.** The shipped flow launches the worker (`do_attach`) as its final act, so
  REQ-C1.1 / Task-4's "aborts **before launching a worker**" is unproven and is *violated* if
  the fence is inserted at/after attach. The fence must be placed before worker launch in both
  backends.
- **S3 (`[MED]`, agent-1 #6):** the losing tower's **teardown is unspecified.** The local
  worktree/branch/tracking-record/dispatch-marker are created before the fence resolves; the
  loser "aborts" but rolls none back → a stale marker reads in-flight until TTL, and the
  canonical branch forces the adopt/rollback reconcile path on retry.
- **S4 (`[MED]`, agent-1 #7):** **adopt-path fence-base mismatch.** If the fence is pushed at a
  fresh `origin/main` base while an *adopted* worker-tip descends from an older base, the
  worker's PR-open push is non-fast-forward → **rejected after the work is done.** The fence
  base is undefined for the adopt path.
- **S5 (`[MED]`, agent-1 #5):** rename/normalization **failure is an undefined path** — no
  "verify the pushed refname equals the canonical name, or fail closed" guard → can fail open
  into a divergent ref (two refs, two PRs, fence defeated).

**Cluster 4 — quarantine / residue-GC gaps (claim lifecycle).**
- **Q1 (`[HIGH]`, agent-2 #3):** quarantine fires on "**repeated** parse failure across
  passes," but towers are **stateless/disposable** with no defined store for the per-claim
  count; an in-process counter resets every pass/restart → the corrupt claim never reaches the
  threshold → never quarantined → honored forever = a **permanent, invisible strand** (strictly
  worse than the "availability-only, operator-recoverable" promise). No cross-clone keying (the
  record is unparseable, so it can't be keyed by owner), and the quarantine `mv` is **not**
  among the reclaim-lock-guarded ops → concurrent dead-letter race.
- **Q2 (`[MED]`, agent-2 #5):** a **permanently-"unknown"-liveness** claim is covered by no
  sweep and never surfaced — e.g. the tmux server dies so the `tmux-window` handle is
  unclassifiable → unknown forever → honored forever, invisible (not positively-dead → no GC;
  parses fine → no quarantine). Plus the **dead-letter sub-surface has no GC** (grows unbounded,
  in tension with REQ-C1.5's no-unbounded-growth).

**Cluster 5 — under-spec / robustness (`[LOW–MED]`).**
- **U1 (`[LOW]`, hardening, agent-1 #8):** the empty-expected CAS is **correct on modern git**
  — the colon-empty form `--force-with-lease=refs/heads/<branch>:` maps to the zero-OID
  "must-be-absent" expectation (the "some versions treat empty as unchecked" danger is the
  *no-colon* form, not this one), and a plain `git push base:refs/heads/<branch>` would report
  up-to-date and fail to reject the loser (all towers push the identical base), so
  force-with-lease-expect-absent is the correct primitive. But the spec pins **no git-version
  floor and no server-CAS assumption**; harden with the explicit all-zeros OID.
- **U2 (`[LOW]`, agent-3 F4):** the reclaim artifact check doesn't specify a **live
  `ls-remote`** vs a possibly-stale checkout-local remote-tracking ref, nor fail-closed on an
  `origin` read error (unlike the fence and the main-sync, which both specify fail-closed).
- **U3 (`[LOW-MED]`, agent-3 F2):** repo-id is derived from the checkout-local `origin` URL;
  **divergent spellings** (SSH vs HTTPS, `.git` suffix, host aliases) yield divergent repo-ids
  → false solitude (fence-safe, but defeats awareness/optimization). Needs a normalization spec.

**Cluster 6 — cross-host / out-of-scope, fail-safe (note as accepted, not fixes).**
- **N1 (agent-3 F5):** the meta-tower marker is machine-local; second-host towers can't see a
  host-1 meta-tower → redundant selection (fence-safe; consistent with the single-host scope).
- **N2 (agent-3 F6):** a "machine-local" surface placed on a **shared network FS** would
  mis-evaluate death handles cross-host (fail-safe via the fence, *unless* no-remote per A3).

**Seed artifact (agent 3):** a full signal-locality classification table (origin / machine-local
/ checkout-local / in-process for the fence ref, OC marker, advisory lock, claim, reclaim lock,
presence record, sentinel, death handle, worker liveness, worker local commits, PR state,
meta marker, repo-id, base-sha, canonical branch name, identity) lives in the run-3 lens
transcript; the load-bearing conclusion is that **the origin fence is the *only* class-A
cross-clone floor, so every class-B/C/D signal below it degrades to availability (strand) not
safety — *provided a remote exists* (A3 is the one exception).**

### Halt record (run 3)

Class: n/a (no sign-off recorded — inconsistency halt, REQ-B2.3).
Lens-pass: recorded above (three-agent adversarial fan-out on the correctness axis, false
positives cleared, ground-truth-grounded); the inconsistency is unresolved on disk (operator
chose Option a, to be instantiated by `/spec-draft`), so per REQ-F1.10 **no execution-valid
anchor is written.** The freshness gate treats the absent anchor as blocking — dispatch stays
blocked until a fresh kickoff signs off the re-reworked bundle.
Anchor: (none — fail closed)

Next step: `/spec-draft specs/concurrent-orchestrator-coordination` to work the run-3 backlog
above — leading (again) with the correctness model and **this time reconciling it with the
*shipped* dispatch primitives** (`fleet-dispatch-worktree.sh` and the `claude --worktree`/tmux
path): a cross-clone reaper / worker-liveness signal for the origin fence ref (H1–H3, A1), the
per-unit-fence-vs-cohesion-bundle reconciliation (A2), no-remote multi-tower enforcement (A3),
fence naming/sequencing aligned to the real dispatch flow (S1–S5), and the quarantine/residue
gaps (Q1, Q2). Then re-run `/spec-kickoff`.

### Halt record (run 4)

Kickoff run 4 walked the run-3 worker-liveness-claim rework (Architecture A: the machine-local,
worker-liveness-keyed claim is authoritative, D-5/D-7/D-11; the origin ref is demoted to a
best-effort double-PR guard, D-8). The comprehension walk (streamlined, operator-confirmed) found
the model internally coherent at the model altitude. The sign-off Discovery-Rigor lens pass — a
**full-bundle parallel per-lens fan-out** (8 read-only agents: correctness+concurrency, security,
error-handling, performance, tests, cross-file, docs+altitude, and a spec-vs-shipped-code
reconciliation) — did **not** come back clean. It surfaced ~31 validated findings, **6 HIGH**,
several of them genuine REQ-B2.3 inconsistencies on the same work-division correctness axis the
prior three runs halted on. Per REQ-F1.10 the run **fails closed**: no sign-off, no Draft→Ready
flip, no anchor; the bundle stays Draft; dispatch stays blocked until a re-reworked bundle is
signed off.

**Lens-coverage table (canonical):**

| Lens | Findings | Load-bearing |
| --- | --- | --- |
| Correctness / concurrency | 3 HIGH, 3 MED, 1 LOW | claim-before-worker ordering paradox; cohesion-bundle double-dispatch; reclaim-predicate asymmetry |
| Security | 4 MED, 5 LOW | surface trust boundary (uid/owner/EEXIST); echo-on-unparseable; repo-id path grammar |
| Error handling | 2 HIGH, 4 MED, 2 LOW | permanent-origin never reclaims; sentinel gaps; rm permission failure; no-origin detection fails open |
| Performance | 2 MED, 2 LOW | unclassifiable-forever leak (presence + claim), no TTL/aged sweep |
| Tests / verification | 1 HIGH, 4 MED, 2 LOW | manual anchors missing from tasks; ordering-fixtures no deterministic seam |
| Cross-file consistency | 1 HIGH (converged), 1 MED, 2 LOW | stale D-5 parenthetical; obs paths; Last-reviewed date |
| Docs + altitude | 1 HIGH (converged), 3 MED, 1 LOW | stale D-5 parenthetical; no-strand absolute; D-1 one/two; companion-doctrine trigger un-pinned |
| Spec-vs-shipped-code | 1 HIGH, 1 MED | phantom "second dispatch backend"; bare-empty CAS literal |

**The four-halt diagnosis (why this recurs).** Runs 1–3 were one bug — the *authoritative* signal
was assumed cross-clone-and-death-surviving but was not (checkout-local lock → local ref → passive
origin ref). Run 4 correctly fixed that **locality** axis. This run's HIGHs are a *different axis
each*, none of which the model checked: **lifecycle** (the claim is created before the worker
exists yet must contain the worker's death handle — a `process <pid>` is unknowable pre-fork, and a
pre-created tmux window reads *alive-but-worker-never-ran* → silent strand, never even
"unclassifiable" so never surfaced; correctness + error-handling agents converged), **granularity /
keying** (one unit-keyed atomic create cannot fence a cohesion-bundle *set* — a peer selecting a
non-lead member creates its own key and double-dispatches, contradicting REQ-C1.1), **case-
completeness** (reclaim-blocking artifact = "open PR *or commits on ref*" but GC-resolution = "PR
merged/present *or ledger-done*", so a dead worker with pushed-commits-no-PR is neither reclaimed
nor GC'd nor surfaced; and a *permanently*-erroring configured `origin` is treated transient every
pass → a positively-dead worker never reclaimed — both contradict REQ-C1.3's "always reclaimed"),
and **versioning** (quarantine-on-first assumes parse-fail = corruption, but a *live* claim written
by a different-planwright-version peer is well-formed-but-unparseable → quarantined → unit freed →
**double dispatch** — this reverses the run's own earlier "schema-skew is availability-only" call;
it is a safety bug). Plus a **classification** gap (a reused pid reads confident-*alive*, not
unknown, so the bare-pid case is *silently honored*, contradicting the stated unclassifiable-always-
surfaced guarantee; root: the worker handle grammar `process <pid>` carries no start-time, unlike
the reuse-resistant tower-identity composite) and a **surfacing/bounding** gap ("surfaced" for
unclassifiable liveness has no durable dedup'd sink, and unclassifiable presence-records/claims have
no TTL/aged sweep — REQ-C1.3 was tightened but REQ-C1.5's growth guarantee was not).

**S-class recurrence (spec vs shipped code).** The bundle models "two shipped dispatch backends,
one that mangles slashed names and `git branch -m` renames to canonical." Only **one** ships
(`fleet-dispatch-worktree.sh`) and it **direct-creates** the canonical branch; the mangle is the
native `claude --worktree` behavior that primitive was *built to eliminate*; `git branch -m` appears
nowhere but a negative header line. So REQ-C1.6(2) / D-8 / test-spec REQ-C1.6(d) harden and fixture
a **phantom backend** — but this *simplifies*: the canonical name holds by construction and the
whole S1–S5 rename/verify burden collapses to a conditional future-path note. (The CAS literal
`--force-with-lease=refs/heads/<branch>:` is the bare-empty form in all four files under prose
demanding the "explicit all-zeros OID"; verified. `fleet-death-evidence.sh` two-form grammar +
tri-state, `fleet-tower-marker.sh` `unattended|interactive` field, the checkout-local per-spec
`mkdir` lock, `orchestrate-relay.sh`, and `echo-safety.sh sanitize_printable` all VERIFIED against
shipped code.)

**The load-bearing realization for the rework.** Architecture A was chosen over B largely to get
"always reclaimed" — but the lens shows the worker-claim model does **not** deliver "always
reclaimed" either (findings on lifecycle, case-completeness, and classification are all its own
unclassifiable strands), while paying heavy complexity (worker-handle provenance, per-unit reclaim
locks, under-lock re-reads, four-residue GC, quarantine) for a guarantee it does not reach. The
complexity is itself the surface area the next seam hides in.

**Operator decision (2026-07-21): rework, framed structurally first, not patched instance-by-
instance.** Route to `/spec-draft` with this framing, applied **before** re-touching the model:

1. **Enumerate the failure-axis matrix once** — {locality, worker-lifecycle, keying/granularity,
   full death-state machine, version/schema skew, a defined recovery action per fail-closed path, a
   durable sink per residue} — and require the spec to answer **every cell**, converting "find the
   next interleaving" (unbounded) into "fill every cell" (finite, checkable).
2. **Downgrade the top-level guarantee** from absolute ("authoritative floor / always reclaimed / no
   unit dispatched twice") to **"best-effort exclusion + every residue is bounded-and-swept OR
   durably-surfaced-to-the-operator, never silent."** Then the correctness HIGHs stop being
   inconsistencies (spec contradicts mechanism) and become verifiable coverage items. Run 3 already
   began this walk ("never strands" → "positively-dead-reclaimed / unclassifiable-surfaced"); the
   remaining absolutes are exactly where this run's HIGHs landed.
3. **Re-open Architecture A vs B** with the new data: worker-claim does not beat origin-fence on
   "always reclaimed" (both strand on the unclassifiable case), so the *simpler* origin-fence-only
   model with operator-surfaced (not auto-recovered) strands may now win — fewer moving parts is
   fewer seams. A real comparison, not inheritance of run-4's choice.

The full validated backlog (the 6 HIGH above plus the lower-severity clusters: surface uid-scoping /
owner-check / EEXIST-verify, echo-sanitize on unparseable bytes, repo-id path grammar, sentinel
location + 2×2 quadrants, claim-`rm` permission-failure escalation, no-`origin` detection
fail-closed, the three `[manual]` Done-when anchors, deterministic interleaving seams for the
ordering-safety fixtures, obs-path `entries/`→`archive/`, D-4 tag `+ orchestration-fleet D-6`,
Last-reviewed `2026-07-20`→`2026-07-21`, the stale D-5 parenthetical, the no-strand absolutes, the
D-1 "one"/"two" heading, the companion-doctrine altitude trigger, and the all-zeros CAS literal) is
seeded to `obs:a45c20d6`
(`specs/_observations/entries/2026-07-21-coc-multiaxis-halt4-a45c20d6.md`), the canonical `/spec-
draft` reader's input. **Hygiene fixes are deferred to the rework** (not hand-applied here), matching
runs 1–3, since `/spec-draft` will substantially rewrite these files.

Class: n/a (no sign-off recorded — REQ-B2.3 inconsistency halt).
Lens-pass: recorded above (8-agent full-bundle fan-out, findings validated; convergence on the
ordering paradox and the stale D-5 parenthetical). Per REQ-F1.10 **no execution-valid anchor is
written** while the load-bearing inconsistencies stand.
Anchor: (none — fail closed)

Next step: `/spec-draft specs/concurrent-orchestrator-coordination` with the axis-matrix +
guarantee-downgrade framing above (consuming `obs:a45c20d6`); let the model fall out of the filled
table rather than patching the run-4 HIGHs instance-by-instance. Then re-run `/spec-kickoff`.

## 8. Sign-off (run 5, 2026-07-21) — SIGNED OFF (Draft→Ready)

**The four-halt pattern is broken.** Runs 1–4 each halted on an *architecture* inconsistency
(the authoritative signal was assumed cross-clone-and-death-surviving but was not natively so),
each needing a new correctness model. The run-4→5 `/spec-draft` rework to **origin-fence-only
(Architecture B)** put authority on the one substrate that is natively both (a per-unit `origin`
fence ref), downgraded the guarantee (D-13), and made the failure-axis matrix (D-12) a checkable
coverage contract. Run 5's full-bundle lens pass confirmed the core dissolutions are **real, not
asserted**, and the remaining defects were **definition-level fixes inside Architecture B**, not a
fifth architecture fork — so they were applied in place (operator-approved) and the run signed off.

### Lens pass — path and coverage (run 5)

Path: full-bundle parallel read-only sub-agent fan-out — **6 agents** covering the nine canonical
lenses plus the three kickoff-specific checks (altitude, spec-vs-shipped-code, coverage-matrix
cell-completeness), per `discovery-rigor` (first-activation-equivalent of a wholesale rework).
Findings validated per `validation-rigor` (three-pass; the decisive F0/F1/F2 reproduced against the
text, corroborated by the spec's own dissolution claim, and cross-checked against the run-4 halt
record). Shipped code ground-checked: `fleet-death-evidence.sh` (two death-handle forms + tri-state,
grammar bounds), `orchestrate-relay.sh` (buffer-paste, not send-keys), `echo-safety.sh`
(`sanitize_printable`), `fleet-dispatch-worktree.sh` (one backend, direct canonical-branch create),
and real git CAS semantics (all-zeros expect-absent). After the fixes, an independent **delta-lens
re-check** enumerated the full 20-cell death-state cross-product and returned **CLEAN**.

| Lens | Findings | Disposition |
| --- | --- | --- |
| Correctness / concurrency | F0, F1, F2 genuine + F3–F8 | F0/F1/F2/F4 applied (STRICT + matrix); F3 applied (grace re-check); F5/F7/F8 deferred |
| Error handling / failure modes | EH-F1 + EH-F2–F5 | EH-F1/F4/F5 applied; EH-F2/F3 deferred; all safety-clean (no fail-open) |
| Security / attribution | Security-F1 | applied (unit-id/spec-id grammar + `git check-ref-format`); rest verified clean vs shipped scripts |
| Performance | none (1 clarity nit) | cadence-cap + per-pass cache specified everywhere; clarity cross-ref deferred |
| Concurrency / state | (under correctness) | F3 applied; F5 GC-vs-refence closed by never-un-terminal invariant (noted, deferred) |
| Naming / structure | vestigial "claim" vocab | applied (D-3, Task 5) |
| Documentation / citations | CrossFile-B1, B2 genuine + backlog | B1/B2 applied (stale claims-layout / claim-GC cross-refs); obs `entries/`→`archive/`, mcg note applied |
| Tests / verification | Tests-F1 integrity + F2/F3 | Tests-F1 applied (two `[manual]` Done-when anchors); F2/F3 deferred |
| Cross-file consistency | SpecVsCode-F2 + B1/B2 | applied (phantom two-backend fixture rewritten backend-independent) |
| *Kickoff: altitude (D-1)* | **CLEAN** | present, cited from Goal, two-doctrine decomposition, companion trigger pinned — no finding |
| *Kickoff: spec-vs-shipped-code* | SpecVsCode-F1, F2 | applied (all-zeros OID literal written w/ SHA-256-safe width; phantom fixture) |
| *Kickoff: matrix cell-completeness* | F0, F1 | applied (recovery cell corrected; missing death-state cell added; 20-cell set verified) |

**Altitude check (REQ-H1.3):** triggered bundle; D-1 altitude record present, cited from the Goal,
decomposition = mechanism-primary + two doctrine statements (assume-multiplicity + deterministic-push
companion, trigger pinned to a Sources seed). **OK — not a finding.**

### Disposition summary

- **Applied in place (genuine inconsistencies + must-fix + robustness):** F0, F1/F2/F4 (STRICT
  dead-owner death-state, operator-chosen), CrossFile-B1/B2, SpecVsCode-F1/F2, Tests-F1, Security-F1,
  EH-F1, F3, EH-F4, EH-F5, F6, plus hygiene (obs paths, vocab, mcg note). Re-validated 0/0; delta-lens CLEAN.
- **Deferred to a named backlog** (`obs:c898c154`, all non-blocking availability/noise/test-breadth):
  EH-F2 (durable channel for non-strand git-op surfaces), EH-F3 (GC idempotent discriminator), F5
  (GC-vs-refence lease note), F7 (strand dedup key), F8 (fence-namespace/atomic deployment precondition),
  Tests-F2 (stale-tracking-ref fixture), Tests-F3 (positive absence assertions), a clarity cross-ref.
- **Declined:** none.

Class: meaning-class (a full-bundle rework of the correctness model; the STRICT resolution changes behavior).
Lens-pass: full-bundle 6-agent fan-out (nine lenses + three kickoff checks) recorded above; every finding
validated and dispositioned; the applied-in-place fixes re-verified CLEAN by an independent delta-lens over
the edited STRICT death-state model. No inconsistency remains open; no finding is undispositioned (REQ-F1.10 satisfied).
Anchor: df12da9a9a803264e8fc1a06cbd587deac133509 (`scripts/spec-anchor.sh specs/concurrent-orchestrator-coordination`)
