# Concurrent Orchestrator Coordination — Test Spec

**Status:** Draft
**Last reviewed:** 2026-07-21
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: predominantly `[test]`, since every mechanism is deterministic script logic over
structured signals (per-tower record files, the `fleet-death-evidence` predicate, git ref state) and is
fixture-testable, including the assertions that carry the design: the **authoritative per-unit `origin`
fence** serializes a unit across separate clones via an atomic expect-absent CAS against a **local
bare-repo `origin` fixture** (one winner, the loser's push rejected), cohesion-bundle members are fenced
together by `git push --atomic`, a dead-owner strand is **surfaced to the durable dedup'd sink, never
auto-reclaimed**, and a terminal unit's fence is **GC'd idempotently**; plus the negative assertions (no
shared-registry write path, no LLM on discovery/surfacing, no rebase under `autosetuprebase`, no
double-dispatch on the fence, no `eval` of peer output, no ref operation escaping the
`refs/planwright-fence/` namespace, and **no machine-local claim / reclaim lock / four-residue GC /
quarantine** — their absence asserted structurally). Atomicity is asserted **structurally** — the presence
write primitive *is* a temp-then-rename, and the fence *is* an expect-absent CAS — rather than by the
unobservable "a reader never sees a torn record", which is flaky by construction. `[manual]` is reserved
for the genuinely multi-checkout / multi-tower end-to-end confirmations that a fixture cannot fully stand
in for (two real towers on two checkouts), each with an explicit Done-when anchor so it is not silently
droppable. `[design-level]` covers the checks whose signal is a design judgment rather than a mechanism's
output — the doctrine statement (REQ-A1.1's floor half, REQ-D1.3), the failure-axis coverage matrix and the
downgraded guarantee (D-12, D-13, verified by their presence and cell-completeness at kickoff), and the
scope-boundary cross-references (REQ-D1.1, REQ-D1.2, which also carry a positive "the relay is consumed"
assertion, not only a grep-for-absence).

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
spec(s), the **currently-fenced unit-ids**, start time, heartbeat, death handle, meta-tower marker) as a
single file in the current repo-id sub-surface, and that two concurrent writers land two distinct files
with no shared-registry write path invoked (grep-level assertion that no single-registry-file edit exists
on the publish path). Asserts the record carries the tower's **currently-fenced unit-ids**, refreshed on
the heartbeat, and that a peer resolves a fence ref's owner from that field — and classifies a fence no
live record lists as **unknown-owner** (REQ-C1.3, REQ-C1.7). Asserts the
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
empty set, and on that result the tower **degrades awareness/strand-attribution for the step while dispatch
proceeds** (D-10) rather than reading solitude — see the closing assertion below; (c) a **concurrent-bootstrap**
`mkdir` returning `EEXIST` (a peer created the surface first) is treated as **success**, not an error.
Asserts a broken or vanished surface is never silently read as solitude, while genuine first-run absence
is the healthy-empty bootstrap case. On the (b) broken/unreadable case, asserts the tower **surfaces
"unknown peer status" and degrades awareness/strand-attribution while dispatch still proceeds** — because
under the origin-fence floor (REQ-C1.1, D-11) exclusion is independent of this surface, so a broken
presence surface can no longer cause a double dispatch (the Architecture-B change from the run-3 draft,
which halted dispatch because the claim surface *was* the correctness floor); solo dispatch remains
reserved for the genuine no-remote posture, never a surface failure.

### REQ-A1.6 — Per-record parsing fails closed [test]

A fixture asserts that a malformed, truncated, or unparseable presence record is **skipped with a surfaced
error** — never interpreted as absent, empty, or "no such peer" — so a corrupt record can never cause a
tower to conclude a live peer does not exist (the per-record analog of REQ-A1.5's surface-level fail-closed
rule). A further fixture asserts a **schema-skewed record written by a different-planwright-version peer**
is treated as **a peer that exists but whose details are unreadable** — assume-live for awareness, never
GC'd on a guess, surfaced as an unclassifiable awareness anomaly to the durable sink (REQ-C1.7) — and,
critically, that this **cannot free a fenced unit**: a companion assertion shows the correctness floor is
git-ref existence (REQ-C1.1), which has no record schema, so the run-4 "well-formed-but-unparseable claim →
quarantine → double dispatch" path **does not exist** here (there is no claim record to quarantine and no
dead-letter sub-surface — asserted structurally by their absence).

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

### REQ-C1.1 — Per-unit origin fence ref is authoritative; presence is off the correctness path [test]

Against a **local bare-repo `origin` fixture**, a concurrency fixture asserts the exclusion serializer is
the **atomic expect-absent CAS** creating `refs/planwright-fence/<spec>/<unit-id>` with the **explicit
all-zeros OID**: two towers racing to fence one unit resolve to a single winner — exactly one push succeeds,
the loser's is **rejected** and it selects another unit. The fixture exercises the **separate-clone** case
(two clones pushing to one `origin`) to assert serialization holds where the checkout-local per-spec lock
cannot. A companion assertion shows correctness is **independent of the presence surface**: with the presence
surface removed or unreadable, two towers still resolve to a **single dispatch** (the fence alone excludes) —
and, structurally, that **no machine-local claim object, reclaim lock, or `claims/` sub-surface is
constructed** on the dispatch path (a grep/source assertion of Architecture A's absence). The fence targets
an existing commit (`origin/main` tip) so it adds **no history to `main`**.

### REQ-C1.2 — Fence is per-unit-keyed under a dedicated namespace, bundle-atomic, no direct peer mutation [test]

A fixture asserts the fence is a ref under the **dedicated `refs/planwright-fence/<spec>/<unit-id>`
namespace**, **not** the unit's task-branch ref (asserted structurally), pushed by the tower under the
canonical name **directly** — so **no worker branch and no dispatch-backend rename** is in the fencing path
(a fixture shows both `fleet-dispatch-worktree.sh` and the `claude --worktree`/tmux dispatch producing the
identical canonical fence ref). A **cohesion-bundle** dispatch fences **every member unit-id** in a single
**`git push --atomic`**: a fixture where one member is already fenced by a peer shows the whole atomic push
**rejected** and the tower backing off the entire bundle, so a peer selecting **any** member — lead or
non-lead — collides (no unfenced member). Asserts the tower only creates / reads / deletes fence refs and
reads the presence surface, never writing into a peer tower's or a worker's branch state.

### REQ-C1.3 — Live-owner fence honored; dead-owner/unclassifiable strand surfaced, never auto-reclaimed [test]

Fixtures (owner attribution via the presence currently-fenced-unit field, REQ-A1.2): a fence whose owner
is **live** is honored (a peer leaves the unit alone); a fence whose owner is **positively dead** per
`fleet-death-evidence.sh` **and** whose unit has **no live completion artifact** is a **strand → surfaced to
the durable sink (REQ-C1.7), never auto-reclaimed** (a fixture asserts no ref delete and no re-dispatch — the
tower raises an operator item instead). The **completion-artifact guard** is asserted both ways against a
**local bare-repo `origin` fixture**: a dead owner whose unit has an **open PR or task-branch commits** (read
live via `ls-remote`) is **not** surfaced as a strand — the work is in review, so its fence is a GC-on-terminal
case (REQ-C1.5), not a strand; a **transient `origin` read** during the artifact check **fails closed** (do
not act, retry). Unclassifiable cases are each surfaced, never silently honored and never auto-reclaimed: an
**unknown/errored** owner-liveness probe; a fence **owned by no live presence record** (an unknown-owner
orphan); and a **reused-pid ambiguity** on a degraded bare-`process <pid>` owner handle. A structural
assertion confirms there is **no per-unit reclaim lock, no under-lock re-read, and no worker-liveness probe
on the dispatch/correctness path** (Architecture A's reclaim apparatus is absent). So a dead-owner unit with
no artifact is always **surfaced** (bounded delay), a live-owner fence is never disturbed, and no strand is
silently honored forever.

### REQ-C1.4 — Composes with meta-tower selection [test + design-level]

`[design-level]`: a documented statement that the peer **fence** composes with, and never contradicts,
`orchestration-fleet`'s division-of-labor doctrine and meta-tower cross-spec selection. `[test]`: a
meta-tower-present **fixture** (committed to the executable assertion, not hedged to documentation-only)
asserts division defers to meta-tower selection and the peer fence does not double-assign; the meta-tower
is distinguished on the presence surface by the **record's own validated meta-tower marker field**
(REQ-A1.2) — **not** `fleet-tower-marker.sh`, whose field is the orthogonal `unattended|interactive`
recovery mode.

### REQ-C1.5 — Fence lifecycle: GC-on-terminal, idempotent, bounded namespace [test]

Fixtures: a fence ref **persists from dispatch until its unit is terminal** and is then **deleted from
`origin`** — on both the owning tower's completion path and the discovery sweep — when the unit's PR is
merged/present or the ledger marks it done; a fixture asserts the delete is **idempotent** (two towers
GC'ing the same terminal fence, or a delete of an already-absent ref, both succeed with no error and no
destructive race — a ref delete has no torn-read window); a **transient `origin` GC failure** is surfaced
and retried next pass, never silently dropped; and the fence namespace is shown **bounded** (every fence is
deleted at its unit's terminal transition, so it does not accumulate across the repo's history — the run-4
no-GC gap closed). A structural assertion confirms there is **no machine-local residue GC** (no
four-residue sweep, no reclaim lock, no orphan-temp sweep, no dead-letter TTL) and **no claim quarantine** —
the only swept residue is the terminal `origin` fence ref, and the only other bounded surface is the
dedup'd strand sink (REQ-C1.7). A fence delete is **containment-checked** to `refs/planwright-fence/<spec>/`
so a crafted unit id cannot drive a ref delete outside it.

### REQ-C1.6 — Origin-reachability classification; fail closed or safely solo, never fail open [test + manual]

`[test]`: against a **local bare-repo `origin` fixture**, the fence-push classification is asserted three
ways: (a) **no `origin` configured** → the genuine **no-remote single-host solo posture**, the tower
dispatches **without** a fence (no peers to collide with), never failing open into a multi-tower collision;
(b) a **rejected expect-absent CAS** (a peer already fenced the unit) → the tower **backs off this unit and
selects another**; (c) a **transient push failure against a configured `origin`** → **fail closed** (do not
dispatch this unit this pass, surface, retry), never dispatch blind against a possibly-fenced unit. Asserts
the tower **never `--force`s** a fence ref it did not create (only the expect-absent lease is used), and
that the fence adds **no commit to `main`** (a ref at an existing commit — the `orchestration-concurrency`
no-dispatch-commit floor). `[manual]`: two real towers on two separate clones sharing one `origin` dispatch
one unit and are confirmed to yield a single worker and a single PR (the end-to-end cross-clone confirmation
a bare-repo fixture stands in for). **Done-when anchor (so this is not silently droppable):** a dated entry
in Task 4's verification notes recording the two-clone run, the two tower identities, the single winning
fence ref, and that only one worker/PR resulted; the task is not complete until that note exists.

### REQ-C1.7 — Every strand and anomaly lands in a durable, dedup'd, push-delivered operator sink [test]

A fixture asserts every **strand** (REQ-C1.3) and every **unclassifiable awareness anomaly** (REQ-A1.6)
lands in a **durable, deduplicated, operator-facing** entry delivered by **push** through
`orchestration-fleet`'s attention surface — **never a transient log line and never poll-only**. Asserts
**deduplication**: the same strand re-observed on successive discovery passes is surfaced **once** (dedup
key = fence-ref name + owner identity for a strand, record id for an awareness anomaly), verified by running
two discovery passes over the same unresolved strand and asserting a single sink entry. Asserts each entry
**names the unit, the dead/unknown owner, and a defined operator action** (reclaim / investigate /
dismiss), so "surfaced" is actionable, not noise. Asserts the sink carries **no checkout path, death
handle, secret, or internal hostname** into any committed artifact (REQ-D1.4), and that it is **bounded** —
entries are resolved by the operator or swept when their unit turns terminal, so it does not grow unbounded
(the run-4 no-durable-dedup'd-sink gap closed).

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

`[test]`: **every** parsed field consumed by the coordination logic — tower id, repository id, **unit id
and spec id (validated before any `origin` fence-ref push or delete)**, the timestamps (start time,
heartbeat, validated as well-formed timestamps), the **meta-tower marker** (a validated boolean; it drives
the defer-to-authority decision), the **checkout path**, **and the death handle**, whose **declared grammar
is exactly the two `fleet-death-evidence.sh` forms** — `process <pid>` (positive integer, no leading zero,
≤10 digits) or `tmux-window <session> <window>` (that predicate's tmux charset, ≤128, no leading dash) —
read from an untrusted peer presence record and passed to `fleet-death-evidence.sh` — is refused when it
violates its declared grammar (not only the tower token), asserted **per field**; a crafted presence record
path, strand-sink path, or **fence-ref name** that would resolve **outside** its bounds is refused
(canonicalized + containment-checked before any read / write / `mkdir` / unlink / ref push-or-delete, the
fence ref confirmed inside `refs/planwright-fence/<spec>/`), **including a surface-root symlink** that would
redirect containment outside the surface; an embedded non-printable / escape sequence in a record field is
stripped before it is echoed to a terminal or log (`scripts/echo-safety.sh`, `sanitize_printable`); and the
surface directory is created / verified `0700` (user-private) with a pre-existing over-broad surface
refused. Together these are the script-boundary enforcement of the same-operator single-host trust model.

### REQ-D1.6 — Companion doctrine line present; ready-push mechanism cross-referenced, not implemented [design-level]

Verified by review + cross-reference, both a **negative** and a **positive** assertion. Positive: the
companion coordination-floor doctrine line — a merge-ready PR reaches the operator by deterministic push,
with an LLM tower polling GitHub as the fallback — exists under the D-1 altitude record and is cited from
the Goal (REQ-D1.6, Task 1). Negative: this bundle introduces **no** ready-surface hook and **no**
attention-surface reclassification — a grep confirms no `gh pr ready` / draft→ready interception and no
`pr-ready`-reclassification code is added here — and the mechanism is cross-referenced to the planned
`merge-currency-guard` spec (D-6). So the doctrine floor lands without the mechanism, exactly as scoped.
