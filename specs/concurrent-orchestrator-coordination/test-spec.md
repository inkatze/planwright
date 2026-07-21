# Concurrent Orchestrator Coordination — Test Spec

**Status:** Draft
**Last reviewed:** 2026-07-20
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: predominantly `[test]`, since every mechanism is deterministic script logic over
structured signals (per-tower record files, the `fleet-death-evidence` predicate, git state) and is
fixture-testable, including the assertions that carry the design: the atomic exclusive-create claim
serializes a unit across separate clones (one winner, the loser reads-and-skips), and the negative
assertions (no shared-registry write path, no LLM on discovery/reclaim, no rebase under `autosetuprebase`,
no double-dispatch on claim or reclaim, no `eval` of peer output, no record/reclaim path escaping the
surface). `[manual]` is reserved for the genuinely multi-checkout / multi-tower end-to-end confirmations
that a fixture cannot fully stand in for (two real towers on two checkouts). `[design-level]` covers the
checks whose signal is a design judgment rather than a mechanism's output — the doctrine statement
(REQ-A1.1's floor half, REQ-D1.3) and the scope-boundary cross-references (REQ-D1.1, REQ-D1.2).

## REQ-A — Cross-tower awareness

### REQ-A1.1 — Tower discovers peers, never assumes solitude [test + design-level]

`[test]`: a discovery fixture seeded with ≥1 live peer record **for the same repository id** asserts the
tower's discovery scan returns a non-empty live-peer set and the selection path does not take the
sole-tower branch; a record for a **different** repository id is excluded from the peer set; and the
tower's **own** record is excluded (no self-as-peer). `[design-level]`: the assume-multiplicity floor
statement (Task 1, D-1) exists and is cited from the Goal and by this REQ — the doctrine half is verified
by the artifact's existence and citation, not a runtime assertion.

### REQ-A1.2 — Per-tower record published, distinct-per-writer, atomic [test]

A fixture asserts a tower writes its own presence record (repository id, tower identity, checkout path,
spec(s), start time, heartbeat, death handle, meta-tower marker) as a single file in the shared
directory, and that two concurrent writers land two distinct files with no shared-registry write path
invoked (grep-level assertion that no single-registry-file edit exists on the publish path). Asserts the
write is **atomic** (write-temp-then-rename): a concurrent reader observes either the old record or the
complete new one, never a torn/partial record. Asserts the **repository id is origin-anchored**: two
records produced from **separate clones of the same repo** (same `origin`, different checkout paths)
carry the **same** repo id and therefore discover each other as peers, while the derivation is shown
**not** to be the checkout path (which would split genuine peers).

### REQ-A1.3 — Reclaim on positive death evidence only, tri-state, no LLM [test]

Fixtures: (a) a heartbeating peer record classifies **live** (not reclaimable); (b) a record whose tower
is positively dead per `fleet-death-evidence.sh` classifies **reclaimable**; (c) a record that is merely
stale-by-timeout but not positively dead does **not** classify reclaimable; (c′) a record whose death
predicate returns **unknown/errored** does **not** classify reclaimable (unknown treated as not-dead —
never reclaim on a guess); (d) on discovery, a positively-dead tower's whole presence file is deleted
(GC) while a **live** peer's file is neither deleted nor edited (its bytes are unchanged after a
discovery pass); and an assertion that the discovery / reclaim path invokes no LLM (no model-call in the
code path).

### REQ-A1.4 — Presence is derived on demand, user-private, no new shared-write accumulator [test]

A fixture asserts the live-tower set is computed by scanning the record directory on demand and that no
committed or hand-maintained registry artifact is produced (no new shared-write accumulator file is
written); the publish path uses only the per-writer file form; the record directory resolves to a fixed
machine-local path outside every checkout (not a path inside a clone); and the surface directory is
**user-private** (`0700` — owner-only), the access-control enforcement of the same-operator trust model.

### REQ-A1.5 — Discovery fails closed on a broken surface; first-run bootstraps [test]

Fixtures: (a) a present-but-empty surface directory yields a healthy empty peer set (genuinely no
peers); (a′) a **first-run** surface path that does not yet exist yields a healthy empty peer set with
the tower creating the user-private (`0700`) directory (bootstrap), and the tower never reads the surface
as absent between creating and populating it; (b) an existing surface path that is unreadable /
misconfigured yields an explicit error or an "unknown peer status" result, **not** an empty set, and the
tower does not take the sole-tower branch. Asserts a broken surface is never silently read as solitude,
while first-run absence is the healthy-empty bootstrap case.

### REQ-A1.6 — Per-record parsing fails closed [test]

A fixture asserts that a malformed, truncated, or unparseable presence/claim record is **skipped with a
surfaced error** — never interpreted as absent, empty, or "no such peer/claim" — so a corrupt record can
never cause a tower to conclude a live peer or claim does not exist (the per-record analog of REQ-A1.5's
surface-level fail-closed rule).

## REQ-B — Shared-`main` isolation

### REQ-B1.1 — Separate per-tower checkouts, private mutable `main` [manual + design-level]

`[design-level]`: the per-tower-checkout topology (each tower a separate checkout owning a private local
`main`) is documented (Task 3). `[manual]`: two real towers on two separate checkouts advance work
concurrently and neither observes the other's local-`main` state change — the shared-`main` race cannot
occur because there is no shared mutable `main` — confirmed once against the running setup.

### REQ-B1.2 — Invariants preserved [test + design-level]

`[design-level]`: a documented cross-check that the per-tower-checkout model leaves
`orchestration-concurrency`'s derived-projection state model and the never-`reset --hard` /
never-force-push / never-rebase / never-amend invariants intact (no invariant weakened). `[test]`: where
the sync path is scripted, a fixture asserts it performs no history-rewriting operation.

### REQ-B1.3 — Migration path and sanctioned fallback [design-level + manual]

`[design-level]`: the adoption / migration path from single-checkout reconcile-via-quick-PR to
per-tower checkouts is documented, and the single-checkout reconcile model is explicitly documented as
the sanctioned degraded fallback where separate checkouts are unavailable (Task 3) — verified by the
document's existence and coverage. `[manual]`: a fresh per-tower clone provisioned via the documented
migration path is confirmed to sign a commit and fetch from `origin` through its own repo-root
machine-local env file and the stable `auth_sock` symlink indirection (not a captured ephemeral
forwarded socket) — the operational check guarding the 2026-06-12 signing-break failure mode.

### REQ-B1.4 — Fast-forward-only fetch-then-merge, hardened against three edge cases [test]

A fixture configures `branch.autosetuprebase=always` and asserts, **at the command level** (the invoked
git operation, since a fast-forward merge and a rebase produce an indistinguishable graph), that the sync
path's `main`-currency operation is an explicit `git fetch origin main && git merge --ff-only
FETCH_HEAD` — a fast-forward-only merge, not a rebase, not a bare `git pull` — and that no direct push to
a shared `main` occurs. Additional fixtures assert: the sync refuses / no-ops when `main` is not the
checked-out branch (it never merges `origin/main` onto a worker branch); and a simulated `git fetch`
failure fails closed (the tower surfaces the failure and does not proceed on a stale `main`).

## REQ-C — Work division across peer towers

### REQ-C1.1 — Branch-as-fence is authoritative; atomic claim is best-effort [test]

**Authoritative layer:** a fixture asserts a tower verifies **no live branch / PR exists for the unit
immediately before dispatch**, and that when the claim layer is forced to fail (two towers made to both
"hold" a claim, e.g. by simulating a stale-broken reclaim lock) the result is still a **single dispatch**
— the second tower's pre-dispatch branch-as-fence check (or its rejected `origin` branch push) aborts it,
so the race degrades to wasted selection work, not a double dispatch. **Best-effort layer:** a two-tower
fixture asserts tower B, selecting work, skips a unit tower A holds a live claim for, so the unit is
rarely selected twice; and that a tower takes its claim before the dispatch step, not after. A
concurrency fixture asserts the claim serializer is the **atomic, exclusive create-with-content** of the
unit-keyed claim object on the machine-local surface: two towers racing to claim one unit resolve to a
single holder — exactly one create succeeds, the loser's create fails atomically and it reads the
existing claim rather than writing a second one. The fixture exercises the **separate-clone** case (two
surfaces that are the same machine-local directory, distinct checkout paths) to assert serialization
holds where the checkout-local per-spec lock cannot. Atomicity-with-content is asserted directly: a
reader never observes a claim object lacking its owner identity + death handle (no bare-`mkdir`
empty-claim window — a tower interrupted before its claim is complete leaves no half-claim that would
strand the unit under REQ-A1.6), and a plain temp-then-rename is shown insufficient (it would overwrite
a peer's claim, losing exclusivity).

### REQ-C1.2 — Claim is unit-keyed and contended, no direct peer mutation [test]

A fixture asserts a claim is a **unit-keyed** object (keyed by the unit's stable id under the repository
scope) that is contended by construction — two towers claiming the *same* unit collide so exactly one
wins (the inverse of the presence surface's distinct-per-writer semantics) — and that the claim path only
creates / reads / removes claim objects and never writes into a peer tower's or a worker's branch state
(no cross-slice mutation on the path).

### REQ-C1.3 — Live claim honored; reclaim positive-death, serialized, artifact-guarded [test]

Fixtures: a live claiming tower's claim is honored (a peer skips the unit), **including a live-but-hung
tower's** (it is not dead, so its claim is never auto-reclaimed); a claim whose tower is positively dead
per `fleet-death-evidence.sh` is reclaimable (a peer may take the unit); a claim whose tower is
stale-by-timeout, or whose death predicate returns **unknown/errored**, is **not** reclaimable (no
reclaim on a guess); two towers reclaiming one positively-dead claim resolve to a **single** holder via
the **per-unit reclaim lock** (concurrent reclaimers serialize on the lock — one wins the swap, the other
finds the lock busy and skips the round), and the lock-free schemes are shown unsafe and not used (a
rename-aside destroys a live claim if it moves before confirming death; a delete-then-recreate
double-dispatches when two reclaimers race). A concurrency fixture asserts the **under-lock re-read
aborts** the swap when the claim changed during the slow death/artifact check — a fresh claimant that took
the freed unit between the reclaimer's read and its lock acquisition is neither clobbered nor
double-dispatched. Fixtures also assert the death / artifact check runs **outside** the lock (no
subprocess held under the lock); and a reclaim whose unit has a **live downstream artifact** (a branch /
open PR) does **not** re-dispatch (the branch-as-fence guard, so a dead tower's surviving worker is not
doubled). So a crashed tower never strands a unit and a live one is never preempted on a guess.

### REQ-C1.4 — Composes with meta-tower selection [test + design-level]

`[design-level]`: a documented statement that the peer work-claim composes with, and never contradicts,
`orchestration-fleet`'s division-of-labor doctrine and meta-tower cross-spec selection. `[test]` (where
scriptable): a meta-tower-present fixture asserts division defers to meta-tower selection and the peer
claim does not double-assign; the meta-tower is distinguished on the presence surface by the
`fleet-tower-marker.sh` marker carried in the schema.

### REQ-C1.5 — Claim lifecycle: release on handoff / dispatch-failure, dead-claim GC [test]

Fixtures: a claim is **released** once the unit is handed off (its worker is dispatched and a branch/PR
exists, so the branch-as-fence takes over) and **immediately** on a dispatch failure (a failed dispatch
strands nothing — no live-tower claim is left blocking the unit); a positively-dead tower's claim is
**garbage-collected during discovery** — including a claim on an already-completed unit that no peer ever
re-selects (asserting the sweep is not gated on re-selection), symmetric with presence-file GC. The
discovery GC of a claim is asserted to take the **same per-unit reclaim lock and under-lock re-read** as
the reclaim path: a fixture with a GC pass racing a reclaimer that has just swapped a dead claim for a
fresh live one shows the GC does **not** delete the fresh live claim (it re-reads under the lock, sees the
owner changed, and leaves it) — an unguarded GC `rm` would be a double-dispatch. And a **stale reclaim
lock** left by a reclaimer that crashed mid-swap is broken during discovery (past the stale threshold,
the same `mkdir`-plus-stale-break discipline the per-spec advisory lock uses), so a crashed reclaimer
never wedges a unit's reclaim path — so the claims surface does not grow unbounded and no unit is
permanently blocked.

## REQ-D — Carried floors, boundaries & hygiene

### REQ-D1.1 — Relay is consumed, not re-implemented [design-level]

Verified by review + cross-reference: this bundle introduces no relay implementation and cites
`orchestration-fleet`'s attributed non-impersonating relay (REQ-D1.3) as its channel — a grep confirms no
`send-keys` / relay-mechanics code is added here.

### REQ-D1.2 — Usage governance stays in `fleet-autonomy` [design-level]

Verified by review + cross-reference: this bundle implements no global-`/usage` reading or quota
governance and cross-references `fleet-autonomy` REQ-E1.3 as the owner — a grep confirms no usage/quota
mechanism is added here.

### REQ-D1.3 — Reserved floors carried unchanged [design-level]

The no-auto-merge, no-autonomous-PR-ready (beyond the sanctioned kickoff exception), and
tower-non-authoring boundaries are stated as carried-unchanged (Task 1, D-1) and no mechanism in this
bundle re-opens them — verified by the floor statement's existence and a review that no task crosses it.

### REQ-D1.4 — Attribution, data-not-code, artifact hygiene [test + design-level]

`[test]`: a malformed / hostile tower-identity token is refused before use (validated against a declared
grammar, never interpolated); peer output consumed for awareness is handled as data with no `eval` /
unquoted-expansion path (source-audit assertion); a peer tower's machine-local **checkout path** is shown
not to reach a committed artifact (a PR body); the conditional hygiene guard flags a seeded secret /
internal hostname / checkout path in a **committed** coordination artifact and passes a clean one, and is
a no-op (not a false failure) when no coordination record is committed. `[design-level]`: a documented
statement that attribution is scoped to the same-operator single-host trust model — grammar-validation
guards against accident and malformed input, and an adversarial peer forging another tower's identity is
out of scope (a co-tenant threat), so no cryptographic spoof-proofing is required.

### REQ-D1.5 — Framework-script security bars on the coordination scripts [test]

`[test]`: **every** parsed field consumed by the coordination logic — tower id, repository id, unit id,
spec id, the timestamps (start time, heartbeat, validated as well-formed timestamps), **and the death
handle** (read from an untrusted peer record and passed to `fleet-death-evidence.sh`) — is refused when
it violates its declared grammar (not only the tower token), asserted per field; a crafted record path,
reclaim-lock path, or unlink target that would resolve **outside** the surface is refused (canonicalized +
containment-checked before any read / write / `mkdir` / `rm`); an embedded non-printable / escape sequence in a
record field is stripped before it is echoed to a terminal or log (`scripts/echo-safety.sh`,
`sanitize_printable`); and the surface directory is created / verified `0700` (user-private). Together
these are the script-boundary enforcement of the same-operator single-host trust model.
