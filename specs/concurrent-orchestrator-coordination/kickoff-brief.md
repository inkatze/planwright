# Concurrent Orchestrator Coordination — Kickoff Brief

**Spec path:** specs/concurrent-orchestrator-coordination
**Spec commit at walkthrough start:** 18e0088
**Walkthrough date:** 2026-07-20
**Validator outcome (pre-flight):** 0 errors, 0 warnings (clean)
**Mode:** First activation (Draft, no prior brief)

**Re-kickoff run 2 (2026-07-21).** Spec commit at re-walkthrough start: `e69556e`
(the `/spec-draft` rework + 3 `/panel-review` iterations that followed run 1's
halt). Focused re-walk (operator-selected): framing confirmed, reworked
coordination mechanics walked, full-bundle Discovery-Rigor lens pass re-run.
**Outcome: HALTED AGAIN (fail closed) — see §8 (run 2).** Sections 2–7 below
describe the *pre-rework* spec (commit `18e0088`) and are **stale**; they are
regenerated at the next kickoff after the run-2 rework, not re-signed here.

<!-- Sections 8 (sign-off) and 9 (amendment log) are written by the sign-off flow. -->

## 2. Goal & glossary

**Goal restatement (agent's words).** This bundle is the awareness + coordination
layer directly above `orchestration-concurrency`'s (Done) ledger state-safety
floor. State-safety guarantees no tower corrupts the shared `tasks.md` ledger or
drags foreign dispatch commits onto worker branches; it does not make a tower
*aware* of peers or stop two towers colliding. This bundle adds three mechanisms
and one doctrine line to close that gap. (Full goal text: `requirements.md` §Goal;
mechanism detail cited there and in `design.md` D-1–D-6, not transcribed here.)

- **Mechanism 1 — cross-tower awareness (D-2):** per-tower heartbeat files in a
  shared directory; discover peers by scanning + the `fleet-death-evidence.sh`
  liveness predicate. No shared registry, no daemon, no LLM.
- **Mechanism 2 — shared-`main` isolation (D-3):** separate per-tower checkouts
  (separate clones, each a private mutable local `main`) as the root fix, **not**
  git worktrees; single-checkout reconcile-via-quick-PR demoted to sanctioned
  degraded fallback; currency by `git fetch origin main && git merge FETCH_HEAD`,
  never rebase (accounts for the `autosetuprebase=always` pitfall).
- **Mechanism 3 — work division (D-4, D-5):** claim-before-dispatch on a shared
  blackboard; live claims honored, dead-tower claims reclaimable only on positive
  death evidence; reuses `orchestration-fleet`'s meta-tower selection + relay.
- **Doctrine (D-1):** a tower **assumes multiplicity, not solitude** — the
  altitude record, extending `fleet-coordination-floor.md`, cited from the Goal.

**Rules out (owned elsewhere, cross-referenced not implemented):** proactive
`/usage` quota governance (→ `fleet-autonomy`); the inter-orchestrator relay (→
`orchestration-fleet`); ledger state-safety mechanics (→ `orchestration-concurrency`).
Re-opens nothing: auto-merge, autonomous PR-ready, tower non-authoring boundary all
carry in unchanged.

**Assumes:** `orchestration-concurrency`'s state-safety as an authoritative
contract; `fleet-death-evidence.sh` as the only sanctioned death signal; every
awareness/reclaim/division decision is deterministic script logic, never model
judgment.

**Glossary / implicit terms surfaced.**

- **Checkout (D-3 sense) = a separate clone**, not a git worktree. Load-bearing
  and non-obvious: planwright is worktree-heavy, but D-3 rejects worktrees (git
  forbids `main` in two worktrees; worktrees share one object store + `main` ref).
- **Presence / claim surface = a fixed machine-local path outside every checkout.**
  See the resolution below.
- **Tower, unit, meta-tower, positive-evidence-of-death** — used per `spec-format`
  glossary and the `fleet-death-evidence` predicate; no local redefinition.

**Resolved ambiguities.**

- *Where the shared surface physically lives (spec was silent).* **Resolved
  (operator, 2026-07-20):** a fixed machine-local path outside every checkout, so
  all peer clones on one host read the same directory. This bakes in a
  **single-host co-location** assumption; cross-machine / distributed peer towers
  are **out of scope**. Rationale: matches D-2's local-first / no-remote-required
  posture, and `fleet-death-evidence` (PIDs/tmux) is host-local and cannot classify
  a remote peer. → **Spec-edit candidate S1** (make machine-local location + single-host
  assumption explicit in D-2; add cross-machine exclusion to Scope §Out of scope).

Signed off: 2026-07-20

## 3. Requirements walkthrough

Group intents restated and probed; per-group outcomes below. REQ groups, count, and
text: see `requirements.md` (4 groups A–D; count derived there, not transcribed —
REQ-A1.5 was added during this walkthrough), not copied here to avoid drift.

**REQ-A — Cross-tower awareness.** Intent: a tower discovers live peers from a
derived, on-demand presence signal and never assumes solitude; publish is
distinct-per-writer; reclaim is death-evidence-only, deterministic, no LLM.
Outcome: intent sound. One gap closed:
- *Presence GC vs never-edit (resolved, operator 2026-07-20):* deletion of a
  **positively-dead** peer's *whole* presence file is permitted and is distinct
  from the forbidden content-edit of a *live* peer's file; the discovering peer
  unlinks the stale file once death evidence is positive. Self-heals during
  discovery, no new sweep. → **Edit S2.**

**REQ-B — Shared-`main` isolation.** Intent: separate per-tower checkouts as
root fix, invariants preserved, migration path + sanctioned fallback,
fetch-then-merge currency past the `autosetuprebase` pitfall. Outcome: intent
sound. Agent readings (correct at summary):
- *Fetch-merge is always a fast-forward:* a tower's private `main` is never
  directly committed to (commits ride task branches; merges land on `origin` via
  PR), so `git merge FETCH_HEAD` fast-forwards. `--ff-only` is a low-stakes
  hardening Task 3 may adopt to surface unexpected divergence as a refusal rather
  than a silent merge commit. Not blocking.
- *Per-clone machine-local env layer (migration detail):* separate clones each
  need their own repo-root machine-local env file and a **stable** `auth_sock`
  symlink indirection (never a captured ephemeral forwarded socket) — the origin
  of the 2026-06-12 signing-break lesson. Task 3's migration path should cover
  it. → **Edit S5** (Task 3 deliverable + risk-register row).

**REQ-C — Work division.** Intent: claim-before-dispatch, honor live claims,
reclaim dead-tower claims on death evidence, compose with meta-tower selection.
Outcome: one gap closed, one reading:
- *Claim TOCTOU (resolved, operator 2026-07-20):* the claim read-check-write
  occurs **within the existing per-spec advisory lock window** /orchestrate
  already takes; two towers targeting one unit serialize on that spec's lock, so
  the second sees the first's claim and skips. No new lock. → **Edit S3** (make
  in-lock ordering normative).
- *Meta-tower detection (reading):* a meta-tower is distinguishable on the
  presence surface via the existing tower-marker mechanism
  (`fleet-tower-marker.sh`); REQ-C1.4's "where a meta-tower is present" resolves
  through presence discovery, not a new signal.

**REQ-D — Carried floors, boundaries & hygiene.** Intent: don't re-implement the
relay or usage governance; carry auto-merge / autonomous-ready / non-authoring
floors unchanged; attribution validated, peer output is data, artifacts secret-clean.
Outcome: one gap closed:
- *Trust model (resolved, operator 2026-07-20):* peer towers are the **same
  operator's sessions on one host, mutually trusting**. Attribution validation
  guards against accidental collision and malformed identity tokens (grammar
  validation + refuse-malformed), **not** an adversarial peer forging identity;
  no crypto spoof-proofing. Scopes Task 5's identity validation. → **Edit S4.**

### Consolidated spec-edit list (applied as a batch pre-sign-off, then re-validated)

- **S1** — `design.md` D-2 (+ Scope §Out of scope): make explicit that the
  presence/claim surface is a fixed machine-local path outside every checkout,
  with a single-host co-location assumption; cross-machine / distributed peer
  towers out of scope.
- **S2** — `requirements.md` REQ-A group + `design.md` D-2: a positively-dead
  peer's whole presence file MAY be deleted by the discovering peer (distinct
  from the forbidden edit of a live peer's file content); this is the GC path.
- **S3** — `requirements.md` REQ-C1.1 + `design.md` D-5: the claim
  read-check-write is performed within the per-spec advisory lock window (closes
  the claim TOCTOU); stated normatively.
- **S4** — `requirements.md` REQ-D1.4 + `design.md` cross-cutting §Security:
  scope attribution to the same-operator single-host anti-accident trust model
  (grammar-validate + refuse-malformed; no adversarial spoof-proofing).
- **S5** — `tasks.md` Task 3 deliverable + a risk-register row: the migration
  path covers each clone's own repo-root machine-local env file and a stable
  `auth_sock` symlink indirection (no captured ephemeral forwarded socket).
- **S6** — `tasks.md` Task 5 (Deliverables + Done-when) + `test-spec.md`
  REQ-D1.4: refocus the hygiene guard on the commit-independent core —
  attribution/grammar validation + data-not-code (no-`eval`) on peer records read
  from the machine-local surface — plus a *conditional* hygiene scan that fires
  only if a deployment commits a coordination record. Drops the false premise
  (from S1) that presence/claim records are normally committed.

Signed off: 2026-07-20

## 4. Design walkthrough

Every D-ID accounted for; no design decision contradicts a walked requirement
(no inconsistency halt). Reconciled ledger:

| D-ID | Disposition | Note |
| --- | --- | --- |
| D-1 | Confirmed | Altitude record (mechanism-primary + one doctrine line); cited from Goal. |
| D-2 | Amended (Draft, in place) | S1 pins surface = machine-local path; S2 adds delete-dead-file GC path. |
| D-3 | Confirmed | Separate clones as root fix; worktree rejection sound (git forbids `main` in two worktrees; shared ref/object store). |
| D-4 | Confirmed | Reuse meta-tower selection + relay; peer claim additive; no second relay. |
| D-5 | Amended (Draft, in place) | S3 makes in-lock claim ordering normative. |
| D-6 | Confirmed | Single-owner scope boundary (usage → fleet-autonomy; relay → orchestration-fleet). |

Reconciliation recorded: D-2 rejects peer *discovery* by tmux/process scraping
(backend-specific), while `fleet-death-evidence.sh` uses PIDs/tmux only to
*confirm death of an already-identified* tower (whose handle its own presence
record recorded). Discovery = file scan; death-confirmation = process state. No
contradiction. The D-2/D-5 amendments are clarifications consistent with the
accepted decisions, not reversals.

Signed off: 2026-07-20

## 5. Verification approach

Coverage mix and per-REQ tags: `test-spec.md` (predominantly `[test]`;
`[design-level]` for the doctrine + cross-reference REQs; one `[manual]`), not
transcribed.

**Ownership.**
- `[test]` → repo CI (`mise run check`).
- `[manual]` → **REQ-B1.1 only** (two real towers on two real checkouts): correct
  as manual; **operator-swept once** against the running setup. Should be tracked
  at execution (a manual-sweep / Awaiting-input note when Task 3 lands) so it is
  not silently dropped.
- `[design-level]` → artifact existence + citation + grep-for-absence checks.

**Dead-path / soft-spot check (no unrunnable verification found).**
- REQ-A1.1's `[test]` selection-path assertion is **Task 4's** path (per Task 2's
  Done-when); REQ-A1.1 is fully verified only once Task 4 exists — a standalone
  flag stands in until then. Recorded so it is not read as complete at Task 2.
- REQ-C1.4's `[test]` is "where scriptable" with a `[design-level]` fallback:
  acceptable as written, but the fallback must be a **conscious** call at
  execution if a meta-tower fixture proves hard, not a silent degrade.

**Edit ripple into test-spec.** S2/S3/S4/S5 are applied as amendments to existing
REQ bodies + their test-spec entries (REQ IDs stay stable; coverage intact):
delete/no-edit fixture → REQ-A1.3; serialize-under-lock fixture → REQ-C1.1;
adversarial-out-of-scope design note → REQ-D1.4; env-migration design line →
REQ-B1.3.

Signed off: 2026-07-20

## 6. Task graph

Reconstructed from `tasks.md` `Dependencies:` lines (authoritative; rendered via
`spec-graph.sh`). Counts/effort cited from `tasks.md`, not transcribed.

- **Edges:** Task 1 → {2, 3, 5}; Task 2 → 4.
- **Critical path (effort-weighted):** 1 → 2 → 4 = 5 days (Task 3 chain 3d, Task 5
  chain 2d).
- **Parallelism after Task 1:** Task 2 ∥ Task 3 ∥ Task 5.
- **Dispatch order:** Task 1 first; then **Task 5 guard-first** (hygiene/infra
  guard outranks the critical path once Task 1 lands, per the guard-tasks-first
  rule); Task 2 ∥ Task 3; Task 4 after Task 2.
- **Deliberate non-edges (do not "fix"):** Task 3 ⊥ Task 2 (checkout topology
  needs no presence signal); Task 4 ⊥ Task 3 (the claim reuses Task 2's presence
  surface, not the checkout model — a claim works within one checkout); Task 5 ⊥
  Task 2/4 (the guard depends only on Task 1's floors).

### Additional edits from sections 6–7

- **S7** — `requirements.md` **new REQ-A1.5** (fail-closed discovery) +
  `test-spec.md` REQ-A1.5 + risk row R1: discovery MUST distinguish a
  healthy-but-empty surface from an absent/unreadable/misconfigured one and fail
  closed on the latter (surface an error / "peer status unknown"), never reading a
  broken surface as solitude. Cites D-2 + the fail-closed floor.
- **S8** — `design.md` decision-domains walk paragraph: name **concurrency** (the
  central, decided domain) and **observability** (the S7 gap) explicitly, instead
  of folding them under "integration surface."

**Cross-file issue surfaced (resolved, operator 2026-07-20):** Task 5's scope
("presence/claim records that land in a committed log") is largely vacuous under
S1 (those surfaces are machine-local, derived, uncommitted). Refocus Task 5 on
the commit-independent core (attribution + data-not-code validation) plus a
*conditional* hygiene scan for any coordination record a deployment does commit.
→ **Edit S6.**

Signed off: 2026-07-20

## 7. Risk register

Inputs: risks surfaced during the walk + the decision-domains gap check (11-domain
seed catalog walked; no overlay layers present; concurrency and auth/attribution
touched-and-decided, observability touched-and-undecided → R1, secrets/config
conditional → R8).

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| R1 | **Solitude-by-misconfiguration** — an absent/unreadable/misconfigured presence surface reads as "no peers," silently defeating the whole feature. | Fail-closed discovery (REQ-A1.5, S7): distinguish empty-healthy from broken, error on broken. Early signal: discovery emits an explicit "surface unreadable" rather than empty. |
| R2 | **Signing/fetch break across clones** — a captured ephemeral forwarded `auth_sock` or a missing per-clone env file breaks signing/fetch on a separate checkout (the 2026-06-12 lesson). | Stable `auth_sock` symlink indirection + per-clone repo-root machine-local env file (S5). Early signal: publickey-denied or signing failure on a fresh clone. |
| R3 | **Claim TOCTOU double-dispatch** — two towers claim one unit, two workers/PRs result. | In-lock claim ordering (S3). Early signal: two branches/PRs for one task id. |
| R4 | **Presence-dir growth** — dead-tower files accumulate unbounded. | Delete-dead-file GC on discovery (S2). Early signal: unbounded file count in the surface dir. |
| R5 | **Meta-tower test silent degrade** — REQ-C1.4's "where scriptable" quietly becomes design-level-only. | Conscious execution-time call; ensure Task 4's PR states whether a scripted meta-tower fixture exists. |
| R6 | **Manual verification dropped** — REQ-B1.1's two-real-tower confirmation lost. | Track as a manual sweep / Awaiting-input note when Task 3 lands. |
| R7 | **REQ-A1.1 partial verification** — only fully verified once Task 4's selection path exists. | Standalone flag interim; Task 4 must close the sole-tower-branch assertion. |
| R8 | **Undocumented config option** — if the surface path becomes configurable, it must reach the canonical options reference. | Existing options-reference guard (`check-options-reference.sh`) at Task 2. |
| R9 | **Trust-model breach** — the single-host same-operator anti-accident model is insufficient if the host gains untrusted co-tenants. | Documented single-host assumption (S1, S4); revisit attribution if co-tenancy ever appears. |

Every walkthrough-surfaced ambiguity resolved to a decision (S1–S8) or an accepted
risk (R1–R9). The sign-off lens pass then reopened the coordination mechanics — see §8.

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

### Lens pass — path and coverage

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
