# Concurrent Orchestrator Coordination — Test Spec

**Status:** Draft
**Last reviewed:** 2026-07-20
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: predominantly `[test]`, since every mechanism is deterministic script logic over
structured signals (per-tower record files, the `fleet-death-evidence` predicate, git state) and is
fixture-testable, including the assertions that carry the design: the **dispatch-time origin fence**
serializes a unit across separate clones against a **local bare-repo `origin` fixture** (one winner, the
loser's expect-absent ref push rejected, aborting before it launches a worker), the atomic
exclusive-create claim serializes selection above that fence (one winner, the loser reads-and-skips), and
the negative assertions (no shared-registry write path, no LLM on discovery/reclaim, no rebase under
`autosetuprebase`, no double-dispatch on the fence / claim / reclaim, no `eval` of peer output, no
record / reclaim / quarantine path escaping the surface). Atomicity is asserted **structurally** — the
write primitive *is* a temp-then-rename / hardlink, never a `mkdir`-then-populate — rather than by the
unobservable "a reader never sees a torn record", which is flaky by construction. `[manual]` is reserved
for the genuinely multi-checkout / multi-tower end-to-end confirmations that a fixture cannot fully stand
in for (two real towers on two checkouts), each with an explicit Done-when anchor so it is not silently
droppable. `[design-level]` covers the checks whose signal is a design judgment rather than a mechanism's
output — the doctrine statement (REQ-A1.1's floor half, REQ-D1.3) and the scope-boundary cross-references
(REQ-D1.1, REQ-D1.2, which also carry a positive "the relay is consumed" assertion, not only a
grep-for-absence).

## REQ-A — Cross-tower awareness

### REQ-A1.1 — Tower discovers peers, never assumes solitude [test + design-level]

`[test]`: a discovery fixture seeded with ≥1 live peer record in the **current repo-id sub-surface**
asserts the tower's discovery scan returns a non-empty live-peer set and the selection path does not take
the sole-tower branch; a record under a **different** repo-id sub-surface is excluded from the peer set;
and the tower's **own** record is excluded **by tower identity** (no self-as-peer, REQ-A1.7). A cadence
fixture asserts discovery invokes the death predicate **at most once per record per pass** (per-pass
liveness cache) rather than unboundedly. `[design-level]`: the assume-multiplicity floor
statement (Task 1, D-1) exists and is cited from the Goal and by this REQ — the doctrine half is verified
by the artifact's existence and citation, not a runtime assertion.

### REQ-A1.2 — Per-tower record published, distinct-per-writer, atomic [test]

A fixture asserts a tower writes its own presence record (repository id, tower identity, checkout path,
spec(s), start time, heartbeat, death handle, meta-tower marker) as a single file in the current repo-id
sub-surface, and that two concurrent writers land two distinct files with no shared-registry write path
invoked (grep-level assertion that no single-registry-file edit exists on the publish path). Asserts the
write is atomic **structurally** — the publish primitive *is* a write-temp-then-rename, asserted at the
call level, not by the flaky "a reader never observes a torn record". Asserts the **meta-tower marker is
the record's own validated field** and that the meta/ordinary distinction is **not** read from
`fleet-tower-marker.sh` (whose field is the orthogonal `unattended|interactive` recovery mode) — a
source/grep assertion. Asserts the **death handle** is one of the two `fleet-death-evidence.sh` forms
(`process <pid>` or `tmux-window <session> <window>`) with the `tmux-window` form emitted where the tower
runs under tmux. Asserts the **tower identity** derivation (REQ-A1.7): it is the session UUID where
present, else the pid + start-time + checkout-hash composite, and two towers on **one** checkout compute
**distinct** identities (no collision, no self-as-peer). Asserts the **repository id is origin-anchored**:
two records produced from **separate clones of the same repo** (same `origin`, different checkout paths)
carry the **same** repo id and therefore discover each other as peers, while the derivation is shown
**not** to be the checkout path (which would split genuine peers).

### REQ-A1.3 — Reclaim on positive death evidence only, tri-state, no LLM [test]

Fixtures: (a) a heartbeating peer record classifies **live** (not reclaimable); (b) a record whose tower
is positively dead per `fleet-death-evidence.sh` classifies **reclaimable**; (c) a record that is merely
stale-by-timeout but not positively dead does **not** classify reclaimable; (c′) a record whose death
predicate returns **unknown/errored** does **not** classify reclaimable (unknown treated as not-dead —
never reclaim on a guess); (d) on discovery, a positively-dead tower's whole presence file is deleted
(GC) while a **live** peer's file is neither deleted nor edited (its bytes are unchanged after a
discovery pass); (d′) a **guarded-GC** fixture: a positively-dead tower's file GC racing that same
tower's **re-publish of a fresh live record** (dead-then-restarted, same identity, new session) does
**not** delete the fresh record — the sweep re-reads under the lock, sees the record is no longer the
dead one, and leaves it (an unguarded `rm` would be the bug); and an assertion that the discovery /
reclaim path invokes no LLM (no model-call in the code path).

### REQ-A1.4 — Presence is derived on demand, user-private, no new shared-write accumulator [test]

A fixture asserts the live-tower set is computed by scanning the record directory on demand and that no
committed or hand-maintained registry artifact is produced (no new shared-write accumulator file is
written); the publish path uses only the per-writer file form; the record directory resolves to a fixed
machine-local path outside every checkout (not a path inside a clone); and the surface directory is
**user-private** (`0700` — owner-only), created with an atomic mode-explicit `mkdir`, with a fixture
asserting a **pre-existing over-broad** surface (group/other-accessible) is **refused, not reused**
(verify-or-refuse) — the access-control enforcement of the same-operator trust model.

### REQ-A1.5 — Discovery fails closed on a broken surface; first-run bootstraps [test]

Fixtures: (a) a present-but-empty surface directory yields a healthy empty peer set (genuinely no
peers); (a′) a **first-run** surface path that does not yet exist **and carries no persistence sentinel**
yields a healthy empty peer set with the tower creating the user-private (`0700`) directory and dropping
the sentinel (bootstrap), and the tower never reads the surface as absent between creating and populating
it; (a″) a **vanished** surface (the sentinel is present but the directory is gone) **fails closed** — an
explicit error / "unknown peer status", never read as first-run solitude; (b) an existing surface path
that is unreadable / misconfigured yields an explicit error or an "unknown peer status" result, **not** an
empty set, and on that result the tower **halts dispatch for the step** (D-10) rather than taking the
sole-tower branch (which is reserved for the genuine no-remote solo posture); (c) a **concurrent-bootstrap**
`mkdir` returning `EEXIST` (a peer created the surface first) is treated as **success**, not an error.
Asserts a broken or vanished surface is never silently read as solitude, while genuine first-run absence
is the healthy-empty bootstrap case.

### REQ-A1.6 — Per-record parsing fails closed [test]

A fixture asserts that a malformed, truncated, or unparseable presence/claim record is **skipped with a
surfaced error** — never interpreted as absent, empty, or "no such peer/claim" — so a corrupt record can
never cause a tower to conclude a live peer or claim does not exist (the per-record analog of REQ-A1.5's
surface-level fail-closed rule). A further fixture asserts a **corrupt claim** record (which cannot be
liveness-checked, so it would otherwise be honored forever and strand its unit) is **quarantined** on
repeated parse failure — moved to the containment-checked dead-letter sub-surface and surfaced for the
operator — after which the unit is **re-selectable**, and that the quarantine is *not* a blind delete of
the untrusted content (REQ-C1.5).

### REQ-A1.7 — Tower identity is deterministic, unique per tower, and self-excluding [test]

A fixture asserts the tower-identity derivation: (a) where a Claude **session id (UUID)** is present it
is the identity, validated against the UUID grammar; (b) where none is present the identity is the
**pid + process start-time + checkout-path hash** composite, and is shown **not** to be the bare pid
(reuse would make it non-unique) nor the checkout path alone; (c) two towers on **one** checkout compute
**distinct** identities (so neither overwrites the other's presence record and neither self-excludes the
other); and (d) discovery excludes exactly the tower's own identity from the peer set (no self-as-peer,
no real peer dropped).

### REQ-B1.1 — Separate per-tower checkouts, private mutable `main` [manual + design-level]

`[design-level]`: the per-tower-checkout topology (each tower a separate checkout owning a private local
`main`) is documented (Task 3). `[manual]`: two real towers on two separate checkouts advance work
concurrently and neither observes the other's local-`main` state change — the shared-`main` race cannot
occur because there is no shared mutable `main` — confirmed once against the running setup. **Done-when
anchor (so this is not silently droppable):** a dated entry in Task 3's verification notes recording the
two-checkout run, the two tower identities, and that no shared-`main` mutation was observed; the task is
not complete until that note exists.

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
a shared `main` occurs. Additional fixtures assert: when `main` is **not** the checked-out branch the
sync updates the `main` ref via **`git fetch origin main:main`** (a fast-forward-only ref update that
refuses a non-fast-forward by nature) rather than a bare merge onto a worker branch — that ref-update
path is **exercised, not left untested**; a `git fetch` failure is **classified before acting** — a
**no-`origin`-configured** state degrades to the single-checkout **solo flow** (not an error) while a
**transient fetch failure against a configured `origin`** fails closed (surfaces the failure, does not
proceed on a stale `main`); and a **`--ff-only` refusal** (simulated divergence) is surfaced for the
operator with no force / rebase / reset.

## REQ-C — Work division across peer towers

### REQ-C1.1 — Dispatch-time origin fence is authoritative; atomic claim is best-effort [test]

**Authoritative layer (REQ-C1.6):** against a **local bare-repo `origin` fixture**, two towers dispatch
one unit and both attempt the atomic expect-absent ref create
(`git push --force-with-lease=refs/heads/<branch>:`); exactly **one succeeds** and the loser's push is
**rejected**, whereupon the loser **aborts before launching a worker**. When the claim layer is forced to
fail (two towers made to both "hold" a claim, e.g. by simulating a stale-broken reclaim lock) the result
is still a **single dispatch** — the second tower's fence push is rejected at dispatch, so the race
degrades to wasted *selection* work, not a double dispatch (and specifically **not** a second worker that
runs to push time). **Best-effort layer:** a two-tower fixture asserts tower B, selecting work, skips a
unit tower A holds a live claim for, so the unit is rarely selected twice; and that a tower takes its
claim before the dispatch step, not after. A concurrency fixture asserts the claim serializer is the
**atomic, exclusive create-with-content** of the unit-keyed claim object on the machine-local surface:
two towers racing to claim one unit resolve to a single holder — exactly one create succeeds, the loser's
create fails atomically and it reads the existing claim rather than writing a second one. The fixture
exercises the **separate-clone** case (two surfaces that are the same machine-local directory, distinct
checkout paths) to assert serialization holds where the checkout-local per-spec lock cannot.
Atomicity-with-content is asserted **structurally**: the claim primitive *is* a hardlink of a
fully-written temp into the unit-keyed name (asserted at the call level), so no bare-`mkdir` empty-claim
window can exist — a tower interrupted before its claim is complete leaves no half-claim that would strand
the unit under REQ-A1.6 — and a plain temp-then-rename is shown insufficient (it would overwrite a peer's
claim, losing exclusivity). The temp is created inside the surface directory (same filesystem) so the
hardlink cannot hit `EXDEV`.

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
subprocess held under the lock); and a reclaim whose unit has a **live downstream artifact — the unit's
task-branch ref on `origin` (D-8) or an open PR** — does **not** re-dispatch (the origin-fence guard). A
dedicated fixture seeds a **dead tower's orphan ref on `origin` that has no PR yet** (a worker that
started but has not reached PR-open) and asserts the reclaim guard **sees the ref and does not
re-dispatch** — the pre-rework local-branch guard was blind to this not-yet-pushed orphan; the origin ref
is present from dispatch. So a crashed tower never strands a unit and a live one is never preempted on a
guess.

### REQ-C1.4 — Composes with meta-tower selection [test + design-level]

`[design-level]`: a documented statement that the peer work-claim composes with, and never contradicts,
`orchestration-fleet`'s division-of-labor doctrine and meta-tower cross-spec selection. `[test]`: a
meta-tower-present **fixture** (committed to the executable assertion, not hedged to documentation-only)
asserts division defers to meta-tower selection and the peer claim does not double-assign; the meta-tower
is distinguished on the presence surface by the **record's own validated meta-tower marker field**
(REQ-A1.2) — **not** `fleet-tower-marker.sh`, whose field is the orthogonal `unattended|interactive`
recovery mode.

### REQ-C1.5 — Claim lifecycle: release on handoff / dispatch-failure, dead-claim GC [test]

Fixtures: a claim is **released** once the unit is handed off (its worker is dispatched and the **`origin`
task-branch ref exists**, so the D-8 fence takes over) and **immediately** on a dispatch failure (a failed
dispatch strands nothing — no live-tower claim is left blocking the unit); a live tower's own **release
`rm` that fails** is surfaced and retried, not silently dropped, and the unit is backstopped by the
discovery GC once the tower is dead (bounded delay, not a permanent strand). The discovery sweep GC's
**three residues** are each asserted: a positively-dead tower's claim — including a claim on an
already-completed unit that no peer ever re-selects (the sweep is not gated on re-selection), symmetric
with presence-file GC; a **stale reclaim lock** left by a reclaimer that crashed mid-swap, broken past the
stale threshold (the same `mkdir`-plus-stale-break discipline the per-spec advisory lock uses); and an
**orphan temp file** from an interrupted create-with-content, swept past a threshold. Each GC remove is
asserted to take the **same per-unit reclaim lock and under-lock re-read** as the reclaim path: a fixture
with a GC pass racing a reclaimer that has just swapped a dead claim for a fresh live one shows the GC
does **not** delete the fresh live claim (it re-reads under the lock, sees the owner changed, and leaves
it) — an unguarded GC `rm` would be a double-dispatch. So the claims surface does not grow unbounded, a
crashed reclaimer never wedges a unit's reclaim path, and no unit is permanently blocked.

### REQ-C1.6 — Dispatch-time origin fence: atomic, cross-clone, death-surviving [test + manual]

`[test]`: against a **local bare-repo `origin` fixture**, the fence is asserted end-to-end: (a) a tower's
dispatch performs an **atomic expect-absent ref create** (`git push --force-with-lease=refs/heads/<branch>:`),
and two towers contending for one unit resolve to **exactly one successful create**, the loser's push
**rejected**, the loser aborting **before launching a worker**; (b) the fence ref is created **at dispatch**
(before the worker runs), so a peer clone reading `origin` sees it immediately — not only at PR-open; (c)
the branch name is a **canonical byte-identical** function of the unit id, and both clones contend for the
**same** `origin` ref (a fixture shows `claude --worktree` mangling is not the naming path, and that a
mangled divergent name would create two refs / two PRs and defeat the fence); (d) the fence pushes a
**task-branch ref only** (pointing at the existing base commit), adding **no commit to `main`** (asserted
against the `orchestration-concurrency` no-dispatch-commit floor); (e) a **lost / errored** fence result
**fails closed** (the unit is treated as possibly-taken and not dispatched), never fail-open; (f) the
**no-`origin`** path is the single-checkout **solo flow** — no fence attempted, no multi-tower claimed.
`[manual]`: two real towers on two separate clones sharing one `origin` dispatch one unit and are
confirmed to yield a single worker and a single PR (the end-to-end cross-clone confirmation a bare-repo
fixture stands in for).

## REQ-D — Carried floors, boundaries & hygiene

### REQ-D1.1 — Relay is consumed, not re-implemented [design-level]

Verified by review + cross-reference: this bundle introduces no relay implementation and cites
`orchestration-fleet`'s attributed non-impersonating relay (`orchestration-fleet` REQ-D1.3) as its
channel. Both a **negative** and a **positive** assertion: a grep confirms no `send-keys` /
relay-mechanics code is added here, **and** where coordination relays to a peer it is shown to invoke
`orchestration-fleet`'s relay entry point (`scripts/orchestrate-relay.sh`) rather than any local
send path — so the "consumes the relay" claim is verified positively, not only by absence.

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
unquoted-expansion path (source-audit assertion); **both** a peer tower's machine-local **checkout path**
**and** its **death handle** (a pid, or a tmux session+window name) are shown not to reach a committed
artifact (a PR body); the conditional hygiene guard flags a seeded secret / internal hostname / checkout
path / death handle in a **committed** coordination artifact and passes a clean one, and is a no-op (not a
false failure) when no coordination record is committed. `[design-level]`: a documented
statement that attribution is scoped to the same-operator single-host trust model — grammar-validation
guards against accident and malformed input, and an adversarial peer forging another tower's identity is
out of scope (a co-tenant threat), so no cryptographic spoof-proofing is required.

### REQ-D1.5 — Framework-script security bars on the coordination scripts [test]

`[test]`: **every** parsed field consumed by the coordination logic — tower id, repository id, unit id,
spec id, the timestamps (start time, heartbeat, validated as well-formed timestamps), the **meta-tower
marker** (a validated boolean; it drives the defer-to-authority decision), the **checkout path**, **and
the death handle**, whose **declared grammar is exactly the two `fleet-death-evidence.sh` forms** —
`process <pid>` (positive integer, no leading zero, ≤10 digits) or `tmux-window <session> <window>` (that
predicate's tmux charset, ≤128, no leading dash) — read from an untrusted peer record and passed to
`fleet-death-evidence.sh` — is refused when it violates its declared grammar (not only the tower token),
asserted **per field**; a crafted record path, reclaim-lock path, quarantine path, or unlink target that
would resolve **outside** the surface is refused (canonicalized + containment-checked before any read /
write / `mkdir` / `rm`), **including a surface-root symlink** that would redirect containment outside the
surface; an embedded non-printable / escape sequence in a record field is stripped before it is echoed to
a terminal or log (`scripts/echo-safety.sh`, `sanitize_printable`); and the surface directory is created /
verified `0700` (user-private) with a pre-existing over-broad surface refused. Together these are the
script-boundary enforcement of the same-operator single-host trust model.
