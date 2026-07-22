# Merge Currency Guard — Design

**Status:** Ready
**Last reviewed:** 2026-07-22
**Format-version:** 2
**Execution:** derived — see the status render

Origin-tag legend: **N** — new to this bundle. **C, `<spec> D-<n>`** — carried:
this bundle reuses an existing decision from the named sibling spec rather than
inventing a parallel one. A tag may append a governing doctrine name after the
kind (as D-9's `customization-boundary` does), naming the doctrine the decision
instantiates.

The design leads with the invariant it exists to protect: **a PR flipped ready
must have been CI-and-review-verified on a head that includes current `main`,
and be mergeable.** Two mechanisms carry it — one that keeps the verified head
current (D-4), and one that refuses a flip that violates the invariant (D-2,
D-3). The guard is the enforcement floor; the in-loop sync is what keeps that
floor from ever being hit in normal operation.

## Decision log

### D-1: Deliverable altitude — mechanism-primary with one carried invariant statement (N)

**Decision:** This bundle is two concrete mechanisms — an `/execute-task`
convergence-loop `main`-sync (D-4) and a deny-emitting `ready-guard` PreToolUse
hook (D-2, D-3) — plus exactly one carried hard-invariant statement (REQ-A1.1):
a PR is flipped ready only on a `main`-current, mergeable head, enforced by
construction (REQ-A1.2). The invariant statement is the altitude decision this
bundle records per the autopilot-reflex altitude gate, cited from the Goal.

**Alternatives considered:**

- Pure mechanism, no invariant statement. Rejected because: the seed explicitly
  frames the fix as encoding an invariant "unbypassable by construction,
  matching planwright's guard philosophy" — a first-class-concern claim that
  fires the altitude gate. Leaving the invariant implicit is how the next
  ready-flip path gets built (a new skill, a new backend) without anyone
  noticing it must also be gated. The invariant belongs in the same family as
  bootstrap's never-merge/force-push/amend invariants, stated once and cited.
- Doctrine-primary reframe — elevate "ready ⇒ current + mergeable" into a
  standalone doctrine rule and defer the mechanisms. Rejected because: the
  recurring incident (`fleet-hardening` #271 DIRTY, #268 seven behind) demands
  the concrete guard and loop-sync now, not a principle awaiting future
  instantiation. The honest weight is one invariant line carried on top of two
  mechanisms — the same shape `fleet-hardening` D-1 and `guard-coverage` D-1
  both chose.

**Chosen because:** the altitude trigger fired (a pinned seed claim framing
this as a guard-philosophy invariant, recorded in Sources), so the call is
recorded rather than retrofitted; and the honest weight is one invariant
statement carried on two mechanisms, scoped per proportionality to the risk
this bundle actually exhibited.

### D-2: Enforce at the flip point with a deny-emitting PreToolUse guard (N)

**Decision:** The invariant is enforced by a deterministic `ready-guard`
PreToolUse hook that intercepts a draft→ready transition and emits a DENY
decision when the invariant is unmet. This is a new guard *modality* for
planwright: the shipped `worker-command-guard.sh` and `tower-command-guard.sh`
are allow-only (they emit `allow` or nothing, never deny), because their job is
to un-block routine commands, not to block dangerous ones. The ready-guard
inverts that — it emits `deny` or nothing — because its job is to block a
specific dangerous transition while leaving every conforming flip untouched.

**Alternatives considered:**

- Reuse the allow-only pattern. Rejected because: an allow-only hook structurally
  cannot block anything; blocking a conforming-looking-but-stale flip is exactly
  the requirement. The two modalities are complementary, not substitutes.
- Skill prose — a mandatory "verify currency before `gh pr ready`" step in
  `/execute-task` / the gauntlet. Rejected because: prose is bypassable and
  unenforced (the exact failure the seed reports — the manual tower relay is
  prose-level and fails under load), and REQ-A1.2 requires enforcement by
  construction. Prose also cannot govern a flip issued from a different session
  (gauntlet, tower, human-in-session).
- GitHub branch protection (server-side). Rejected because: branch protection
  gates the *merge*, not the *ready-flip* (GitHub already blocks merging a DIRTY
  PR — the seed notes the human is protected there); it has no "ready" gate and
  cannot express "the head includes current `main`". It is a merge-time boundary,
  orthogonal to the ready-signal problem, and left as the merge floor it already
  is.

**Chosen because:** a deny-emitting PreToolUse hook is the only option that makes
the invariant unbypassable by construction at the flip point, deterministically,
with no LLM, matching the guard philosophy the seed invokes. It is a scoped,
auditable inversion of a pattern the codebase already trusts.

### D-3: Guard predicate — server-authoritative `mergeStateStatus` + `mergeable`; no local ref, OID, or fetch (N)

**Decision:** The guard resolves the target PR from the intercepted call's own
validated selector (REQ-C1.9: the Bash positional PR argument, or the current
branch's PR when the command is bare; the MCP `owner`/`repo`/`pullNumber`
fields), each validated against its grammar — a PR number is digits, an
owner/repo matches GitHub's charset — before use and passed to `gh pr view` as
separate argv arguments, never interpolated into a command string (a hostile
selector can neither redirect the query to another PR/repo nor inject a `gh`
option or shell; the response is data, never code — `security-posture`). From
that single query it reads GitHub's server-computed `mergeStateStatus` and
`mergeable`. It **defers only** when `mergeStateStatus ∈ {CLEAN, UNSTABLE}`
**and** `mergeable == MERGEABLE`; every other value **denies**:
`BEHIND` (stale — not current with base), `DIRTY` (conflict), `BLOCKED`
(a required check failing or a required review outstanding), `mergeable ==
CONFLICTING`, and `UNKNOWN`/`DRAFT`/absent/unavailable (fail-closed). The signal
is entirely server-side: no local ref, no local OID, no `is-ancestor`, and no
in-hook fetch (D-5) — so the check is identical for every flipper (a worker, the
gauntlet, a tower on the shared checkout, a human in-session) and for any base
branch, because GitHub computes the status against the PR's real base. A
`mergeStateStatus`/`mergeable` of `UNKNOWN` (GitHub recomputes asynchronously
whenever the head or base moves) denies with a **wait-and-retry** remedy, not a
fetch remedy.

Why `{CLEAN, UNSTABLE}` and not `CLEAN` alone: `CLEAN` additionally requires
*every* check green, so a current, conflict-free PR whose only failing/pending
check is **non-required** reports `UNSTABLE` and would be falsely denied
(observed: PR #298 `UNSTABLE`/`MERGEABLE`) — that PR is exactly
current-and-mergeable, the non-required check being the flipping party's concern
under the REQ-A1.2 split. Denying `BLOCKED` keeps the guard covering
*required* checks and required reviews (the REQ-A1.2 clause that CI is
guard-covered where GitHub-required), while allowing `UNSTABLE` lets
non-required checks stay the flipper's business.

Why server-authoritative and not a local `is-ancestor` backstop: a local
`origin/<base>` ref is only as fresh as the last fetch, which no mechanism
guarantees for a gauntlet/tower/human flipper or for a non-`main` base — a
stale-but-present ref would false-*allow* a behind PR (the exact stale-flip this
bundle kills), and a cross-fork head OID absent from the local object DB would
false-*deny*. The server status has neither failure mode: it needs no local
state and is computed against the real base for any PR.

Soundness of allowing `UNSTABLE`: this rests on GitHub's `mergeStateStatus`
being a single value with a fixed precedence — `DIRTY` / `BLOCKED` / `BEHIND`
outrank `UNSTABLE`, so a PR that is behind *or* blocked *or* conflicting never
reports `UNSTABLE`. An allowed `UNSTABLE` therefore genuinely means
current-and-mergeable with only a non-required check outstanding; it cannot mask
a `BEHIND`. If that precedence ever changed, the guard would only ever
false-*deny* (a safe, retryable direction), never false-allow, because the
conjoined `mergeable == MERGEABLE` leg independently blocks a conflict.
`HAS_HOOKS` (mergeable, checks passing, repo has pre-receive hooks) is
conservatively **excluded** from the defer set: it is rare in planwright repos,
and denying it is a safe, retryable false-deny rather than a risk — the defer
set stays exactly `{CLEAN, UNSTABLE}`.
*(Amended at kickoff §4 lens pass 2026-07-22: predicate settled on
server-authoritative `mergeStateStatus ∈ {CLEAN, UNSTABLE}` + `mergeable ==
MERGEABLE` after an adversarial re-check showed a local `is-ancestor` currency
leg false-allows a stale flip for any non-just-fetched flipper and any non-main
base [F1/F2] and false-denies cross-fork heads [F5]; an earlier draft's
`mergeStateStatus == CLEAN` over-denied non-required-check `UNSTABLE` state.
Both fields sit at `UNKNOWN` in GitHub's async recompute window — the
fail-closed deny + wait-retry of REQ-C1.3 and risk row 3.)*

**Alternatives considered:**

- `mergeStateStatus == CLEAN` as the single server signal (the original draft).
  Rejected because: `CLEAN` requires all checks green and so over-denies a
  current, conflict-free PR whose only failing/pending check is **non-required**
  (`UNSTABLE`, observed on PR #298) — re-enforcing the CI state the REQ-A1.2
  scope-split attests to the flipper's convergence, not this guard.
- A local `git merge-base --is-ancestor origin/<base> <headOID>` currency leg
  (an interim draft of this decision). Rejected because: the local
  `origin/<base>` ref is only as fresh as the last fetch, guaranteed for no
  flipper but the just-fetched `/execute-task` worker and for no non-`main`
  base — a stale-but-present ref false-*allows* a behind PR (the very stale-flip
  this bundle exists to prevent), and a cross-fork head OID absent locally
  false-*denies* with an unachievable fetch remedy. An in-hook `git fetch` to
  refresh the ref would fix the freshness but reintroduce the bounded-runtime
  hazard D-5 forbids. The server status has neither failure mode and needs no
  local state.
- `mergeable` alone (no currency signal). Rejected because: `mergeable` reports
  conflict state only, not out-of-date-with-base — a PR can be `MERGEABLE` yet
  behind its base (#268, 7 behind, no conflict). `mergeStateStatus == BEHIND` is
  what covers currency.

**Chosen because:** the server `mergeStateStatus` + `mergeable` conjunction (a)
is satisfiable for a still-draft PR (current drafts report `CLEAN`/`MERGEABLE`),
(b) enforces exactly the currency + mergeability + required-checks REQ-A1.2
assigns to the guard while letting non-required checks (`UNSTABLE`) through, and
(c) needs no local ref, OID, or fetch, so it is genuinely flipper- and
base-agnostic (REQ-A1.3) with no stale-local-ref false-allow. Any value outside
`{CLEAN, UNSTABLE}`×`MERGEABLE`, or any inability to positively confirm both,
→ deny — the fail-closed posture REQ-C1.3 demands.

### D-4: In-loop `main`-sync via fetch + merge, offloaded to a script (N)

**Decision:** `/execute-task` merges `origin/main` into the worker branch at the
top of each `review_sequence` convergence iteration. The mechanism lives in a
dedicated script (`scripts/converge-sync-main.sh`) that runs `git fetch origin
main` then `git merge FETCH_HEAD`; `/execute-task` invokes it in a single line.
It never runs `git pull` (a global `branch.autosetuprebase=always` silently
rewrites `pull` into a forbidden rebase) and never rebases, amends, squashes, or
force-pushes (bootstrap REQ-J1.4). A merge that cannot resolve cleanly runs
`git merge --abort` (leaving a clean tree, so the next iteration's sync is
idempotent rather than wedged on a lingering `MERGE_HEAD`) and exits non-zero
with a reason distinct from a fetch failure, and `/execute-task` halts the unit
to `Awaiting input` via its existing convergence stop-condition protocol
(REQ-B1.3) — no new halt mechanism; drift is re-closed by a human or the tower
merge-`main` relay before resume. (The sync targets `origin/main` specifically —
the worker-convergence base by planwright convention; the guard needs no
counterpart per-base handling because its D-3 signal is server-computed against
each PR's real base, not a local ref.)

**Alternatives considered:**

- Sync once, only immediately before the ready-flip. Rejected because: a single
  end-of-run sync lets drift accumulate to one large, conflict-prone merge, and
  it re-verifies CI + review on the post-merge head only once — the failure mode
  where a late conflict strands the unit after all the convergence work is done.
  Top-of-iteration syncing keeps each merge tiny and re-runs verification on the
  fresh head every iteration.
- Rebase the branch onto `origin/main`. Rejected outright: rebase is a bootstrap
  REQ-J1.4 hard invariant violation (rewrites published history, breaks the
  content anchor, forbidden for workers).
- Inline the fetch + merge as skill prose in `/execute-task`. Rejected because:
  the `/execute-task` instruction body is at its instruction-headroom ceiling
  (the 2026-07-16 audit put it at 4,248/4,250 words); a prose paragraph would
  breach the budget. A one-line script call adds a single line and keeps the
  mechanism testable in isolation (REQ-B1.5, REQ-D1.3).

**Chosen because:** top-of-iteration fetch + merge keeps drift tiny and
guarantees the final verification runs on a `main`-current head, the exact
property the ready-guard later checks; scripting it respects the invariant set
(no `pull`, no rebase) deterministically and stays within the instruction
budget.

### D-5: Guard degradation — no in-hook fetch; fail closed on any doubt (N)

**Decision:** The guard reads no local git state at all — no ref, no object, no
`git fetch` in the hook. Both predicate signals (`mergeStateStatus`,
`mergeable`) come from the one server `gh pr view` query (D-3), so there is no
local freshness dependency to keep current and no stale-local-ref hazard. On any
inability to positively confirm both D-3 conditions — `gh` absent or erroring,
the query timing out, `mergeStateStatus`/`mergeable` `UNKNOWN` (the async
recompute window), `jq` absent, malformed/empty payload, internal error — the
guard DENIES with a clear reason (REQ-C1.3, REQ-K1.1); an `UNKNOWN` names a
wait-and-retry remedy rather than a fetch.

**Alternatives considered:**

- Have the guard `git fetch` (a base ref, or `origin/main`) itself before a
  local currency check. Rejected because: a network fetch inside a PreToolUse
  hook can hang or stall the tool call (bounded-runtime violation, the concern
  the sibling guards encode with `MAX_CMD_LEN`); the authoritative currency +
  mergeability signal (`mergeStateStatus`/`mergeable`) is already server-computed
  and needs no local ref at all, so an in-hook fetch buys nothing.
- Keep a local `is-ancestor` check as an offline backstop alongside the server
  signal. Rejected because: a local `origin/<base>` ref is only as fresh as the
  last fetch — unguaranteed for a gauntlet/tower/human flipper or a non-`main`
  base — so the backstop would either false-*allow* against a stale ref or add a
  cross-fork false-*deny*; the server signal is strictly safer with no local
  state to go stale.

**Chosen because:** deny-on-doubt over a purely server-computed signal is the
only posture that is both bounded (no in-hook fetch) and genuinely
flipper/base-agnostic (no local ref or OID that can be stale or missing);
determinism comes from the deterministic mapping of the server enum to
defer/deny, not from any local git computation.

### D-6: Deny precedence over the worker allow, pinned by outcome (C, `fleet-hardening` D-8 · obs:4dda9fe1)

**Decision:** `config/worker-settings.json` currently ALLOWS `Bash(gh pr ready:*)`
(so the gauntlet / a worker can flip a spec PR ready). The ready-guard's DENY
must override that allow when the invariant is unmet. Note the two mechanisms
are distinct subsystems: the ready-guard's DENY is a **PreToolUse hook
decision**, which blocks a tool call independent of any permission *rule*, while
`obs:4dda9fe1` concerns permission-*rule* allow-vs-deny ordering — an analogous
but separate precedence. Because the hook layer's authority over an allow rule
is itself not something to assume, the adversarial suite asserts the OUTCOME — a
non-conforming flip stays denied even with the `gh pr ready` allow entry present
— rather than leaning on either precedence as an assumption (REQ-C1.4,
REQ-D1.2).

**Alternatives considered:**

- Remove `gh pr ready` from the worker allow list and let the guard be the only
  gate. Rejected because: a conforming flip would then fall to the stochastic
  auto-mode classifier and could be non-deterministically blocked or prompted —
  the exact ergonomics regression `fleet-hardening` D-8 fixed for the tower.
  Keeping the allow for conforming flips and the deny-guard for non-conforming
  ones is the clean split.

**Chosen because:** the allow-for-conforming / deny-for-violating split
preserves ergonomics while making the invariant unbypassable, and pinning the
outcome (not the precedence) matches how `fleet-hardening` handled the same
undocumented-precedence risk.

### D-7: Global wiring in `hooks/hooks.json`; the out-of-session residual (N)

**Decision:** The guard is wired in the plugin-global `hooks/hooks.json` as a
PreToolUse Bash matcher and a PreToolUse MCP matcher, so it governs every
planwright session that attempts a ready-flip regardless of settings profile.
This is deliberately the opposite of `tower-command-guard.sh`, which is
profile-scoped (wired only into `tower-settings.json`) because it grants a
tower-specific allow set that must not leak into worker/human sessions. The
ready-guard grants nothing — it only denies a universally-wrong transition — so
global wiring is correct and leak-free. Residual: a hook fires only inside a
Claude Code session, so a human running `gh pr ready` at a bare terminal is
ungoverned. That is an accepted residual, the same class as `guard-coverage`'s
`--no-verify` gap: the autonomous flippers (worker, gauntlet, tower) all run
in-session, and a human at a raw shell is exercising a reserved control.

**Alternatives considered:**

- Wire the guard per-profile (into `worker-settings.json` / `tower-settings.json`).
  Rejected because: a ready-flip can come from the gauntlet or an
  overlay-configured tower running under a profile the bundle does not ship, and
  the invariant must hold for all of them; a universal deny belongs plugin-global.
- Attempt to also cover the bare-shell path (e.g. a git `pre-push`-style hook).
  Rejected as out of scope: `gh pr ready` is a GitHub API call, not a git
  operation, so no git hook intercepts it; server-side enforcement is the only
  bare-shell-proof option and is out of scope (D-2).

**Chosen because:** a deny-only, grants-nothing guard is safe to wire globally,
and global wiring is the only placement that governs every in-session flipper;
the bare-shell residual is stated honestly rather than papered over.

### D-8: Cover the in-session ready surfaces — Bash `gh pr ready`, the MCP tool, and the `gh api graphql` mutation (N)

**Decision:** The guard applies the D-3 predicate to the draft→ready surfaces an
in-session flipper actually uses: the `gh pr ready` Bash command, the
`mcp__github__update_pull_request` MCP tool call carrying a draft→ready field
transition, and the `gh api graphql` `markPullRequestReadyForReview` mutation
(REQ-C1.10). Compound/indirect shell forms (`sh -c`, `env`, wrappers, raw
`curl`) are an accepted residual in the D-7 out-of-session class — a
deterministic matcher cannot robustly parse arbitrary nesting, and the
autonomous flippers do not use those forms. A PreToolUse Bash-string
guard does not intercept MCP tool calls (the exact gap `fleet-hardening`'s tower
guard closes by denying the GitHub MCP tools by name), so the MCP surface needs
its own matcher. The MCP matcher gates a call whose input requests
`draft: false` only when the PR is *currently* a draft — `isDraft` read from
the same `gh pr view` query that supplies the D-3 predicate fields, a failed
query already resolving to DENY (REQ-C1.3) — and applies the same predicate;
non-transitioning `update_pull_request` calls and `gh pr ready --undo` are never
gated (REQ-C1.8). *(Amended at kickoff §4 2026-07-21: transition
discrimination pinned to current `isDraft` from the guard's existing PR
query.)*

**Alternatives considered:**

- Bash-only coverage. Rejected because: a flipper using the GitHub MCP tool would
  bypass the invariant entirely — a silent hole in a guard whose whole value is
  being unbypassable.
- Deny the MCP tool WHOLESALE by name (the tower-guard approach). Rejected here
  because: the tower never legitimately readies, so wholesale deny is correct
  there; but this guard must let *conforming* MCP readies through, so it must
  discriminate the transition and apply the predicate, not blanket-deny.

**Chosen because:** applying one predicate to both surfaces is the only complete
enforcement; discriminating the transition (rather than wholesale-denying)
preserves conforming MCP readies, matching the Bash surface's behavior.

### D-9: The guard is core and flipper-agnostic; who-flips stays a preference (N, `customization-boundary`)

**Decision:** The currency-at-ready *capability* — enforce that any ready-flip
lands on a current, mergeable head — is core and flipper-agnostic. The *policy*
of who may flip ready and whether the flip is automatic (human-only in core;
worker/gauntlet/tower-autonomous under an adopter overlay) stays in the
settings/overlay layer, unchanged by this bundle. The guard does not mandate
autonomous flipping and does not care which party flips; it only enforces the
invariant at whatever flip occurs (REQ-A1.3, REQ-A1.4).

**Alternatives considered:**

- Bundle a who-flips policy into this spec (e.g. mandate that `/execute-task`
  auto-flips after a conforming sync). Rejected because: who-flips is a genuine
  preference that already varies by adopter (core keeps the flip a human
  control; an overlay grants it to workers/tower) — the customization-boundary
  default tilts to overlay for a value that varies, and baking a policy into
  core would override adopters who deliberately keep the flip manual.

**Chosen because:** the general capability (gate the flip) generalizes and
belongs in core as a default-preserving guard; the specific value (who flips,
when) varies by adopter and stays overlay — the capability-in-core /
value-in-overlay split `customization-boundary` prescribes.
