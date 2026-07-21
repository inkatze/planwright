# Concurrent Orchestrator Coordination — Kickoff Brief

**Spec path:** specs/concurrent-orchestrator-coordination
**Spec commit at walkthrough start:** 18e0088
**Walkthrough date:** 2026-07-20
**Validator outcome (pre-flight):** 0 errors, 0 warnings (clean)
**Mode:** First activation (Draft, no prior brief)

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

## 8. Sign-off — HALTED (fail closed, no anchor)

**This run did not sign off.** The sign-off Discovery-Rigor lens pass (full bundle,
first activation) surfaced a genuine inconsistency plus a set of load-bearing
coordination-mechanics gaps. Per the refusal rule (REQ-F1.10) and the inconsistency
halt (REQ-B2.3), no Draft→Ready flip, no anchor line, no spec-PR ready-flip. The
bundle stays Draft. Operator direction (2026-07-20): fix the mechanical bundle-hygiene
slips now, defer the design gaps to a `/spec-draft` rework.

### Lens pass — path and coverage

Path: parallel read-only sub-agent fan-out, one brief per canonical lens (six agents
covering the nine lenses), per `discovery-rigor` (non-trivial first-activation bundle).
Findings validated (the pivotal lock-locality claim verified against
`orchestrate-lock.sh:97` — the lock is `<spec-dir>/.orchestrate.lock`, checkout-local).

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 8 | Lock clone-local defeats the claim serialization; repo-id missing from schema; bootstrap vs fail-closed; self-exclusion; claim lifecycle; meta-tower marker; hung-tower; presence/claim file discrimination |
| Security | 5 | Echo-safety, per-field validation, path containment, user-private surface, checkout-path→committed-artifact leak — doctrine bars not imported |
| Error handling / failure modes | 4 | Per-record corruption fail-open; death-predicate error outcome; claim-without-dispatch; git-sync + fallback-rung failure paths |
| Performance | 1 | Death-predicate subprocess inside the lock → critical-section / livelock |
| Concurrency / state | 13 | Reclaim not serialized; death-handle GC'd; worker outlives tower; torn reads; heartbeat-liveness shortcut; wrong-branch merge |
| Naming, readability, structure | none | No new structural mess introduced by the bundle |
| Documentation | 2 | Two broken `(Sources)` citations — fixed (see §Fixed) |
| Tests / verification | 6 | S5 unverified (fixed); heartbeat untested; merge-vs-rebase unmeasurable under ff; in-lock TOCTOU needs white-box; absence-by-grep weak; `[manual]` untracked |
| Cross-file consistency | 4 | REQ-A1.5 unwired (fixed); S-labels leaked (fixed); brief tally wrong (fixed); S5 ripple missing (fixed) |

**Altitude check (REQ-H1.3):** triggered bundle; D-1 altitude record present, cited
from the Goal, task decomposition matches mechanism-primary + one doctrine line. OK —
not a finding.

### The inconsistency halt (finding #1)

**D-3 (separate per-tower clones) contradicts REQ-C1.1 / D-5 (claim serialized by the
per-spec advisory lock).** The lock is `<spec-dir>/.orchestrate.lock` — checkout-local —
so separate-clone peers never contend on it, and the claim TOCTOU is not closed under
the *primary* topology (only under the single-checkout fallback). Two resolutions, for
the rework to choose:
- **(a)** Move the claim serialization to a machine-local surface/lock (like the
  presence surface), independent of the checkout-local ledger lock.
- **(b)** State that cross-clone peer-claiming requires the machine-local surface, and
  scope the per-spec lock to intra-clone ledger fencing only.

### Design backlog deferred to `/spec-draft` rework (#1–#20)

All meaning-class; recorded here and in the observations log as `/spec-draft` seed.
Two root axes: *machine-local vs checkout-local surface* (the lock, claim
serialization, repo scoping, user-private access) and *death-handle location + claim/
presence lifecycle*.

- **Claim mechanism:** #1 lock locality (halt, above); #2 reclaim not serialized →
  concurrent reclaimers double-dispatch; #3 death-handle lives in the presence file but
  GC deletes it → surviving claim permanently un-reclaimable; #4 no claim release on
  completion/dispatch-failure and no dead-claim GC → unbounded growth + live-tower
  dispatch-failure strands the unit; #5 reclaim proves the tower dead, not its worker →
  double work.
- **Presence/discovery:** #6 no repository id in the schema (one machine-local path
  shared by all repos on the host → cross-repo false peers, violates "same repository");
  #7 fresh-host bootstrap collides with REQ-A1.5 fail-closed (publish/discover order
  undefined); #8 no self-exclusion; #9 no presence-vs-claim file discriminator; #10
  meta-tower marker absent from the schema + meta-tower may not honor the lock/claim;
  #11 non-atomic writes → torn reads, per-record corruption not fail-closed; #12
  death-predicate error/unknown outcome undefined + heartbeat-freshness liveness
  shortcut; #13 hung-but-alive tower strands units ("never permanently strands"
  overstates); #14 death-predicate inside the lock → livelock.
- **Git sync (#15):** not always fast-forward (`--ff-only` left optional); merges into
  the current branch (no "main checked out" precondition → risks dragging origin/main
  onto a worker branch); fetch-failure → stale main unhandled; merge-vs-rebase test
  can't distinguish under fast-forward.
- **Security bars (#16–#20):** echo-safety (`sanitize_printable`) for peer fields;
  validation beyond the identity token (unit-id / spec-id); path containment +
  canonicalization for record paths / GC unlink; the surface must be *user-private*
  (the enforcing mechanism for the single-host trust model); peer checkout-path leaking
  into committed artifacts (PR bodies) beyond Task 5's current guard scope.

### Fixed this run (mechanical bundle-hygiene, #21–#26)

Validator re-run clean (0/0) after: #21 REQ-A1.5 wired into Task 2 (Citations +
Done-when); #22 leaked S-labels removed from `requirements.md` changelog and `tasks.md`
Task 5; #23 brief REQ tally corrected to a cite (no copied count); #24 REQ-A1.5's
fail-closed floor added to `## Sources`; #25 `security-posture` added to `## Sources`;
#26 the S5 `auth_sock`/env deliverable given a `[manual]` verification (REQ-B1.3) and a
Task 3 Done-when clause.

### Halt record

Class: n/a (no sign-off recorded — halted)
Lens-pass: recorded above; findings NOT all dispositioned to spec edits (20 deferred to
`/spec-draft` by operator direction), so per REQ-F1.10 no execution-valid anchor is
written. The freshness gate treats the absent anchor as blocking — dispatch stays
blocked until a fresh kickoff signs off the reworked bundle.
Anchor: (none — fail closed)

Next step: `/spec-draft specs/concurrent-orchestrator-coordination` to rework REQ-C and
the presence schema against the §8 backlog, then re-run `/spec-kickoff`.
