# Merge Currency Guard — Design

**Status:** Draft
**Last reviewed:** 2026-07-20
**Format-version:** 2
**Execution:** derived — see the status render

Origin-tag legend: **N** — new to this bundle. **C, `<spec> D-<n>`** — carried:
this bundle reuses an existing decision from the named sibling spec rather than
inventing a parallel one.

The design leads with the invariant it exists to protect: **a PR flipped ready
must have been CI-and-review-verified on a head that includes current `main`,
and be mergeable.** Two mechanisms carry it — one that keeps the verified head
current (D-4), and one that refuses a flip that violates the invariant (D-2,
D-3). The guard is the enforcement floor; the in-loop sync is what keeps that
floor from ever being hit in normal operation.

## D-1: Deliverable altitude — mechanism-primary with one carried invariant statement (N)

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

## D-2: Enforce at the flip point with a deny-emitting PreToolUse guard (N)

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

## D-3: Guard predicate — server-authoritative `mergeStateStatus` plus an offline `is-ancestor` backstop (N)

**Decision:** The guard denies unless BOTH hold: (a) the PR's GitHub
`mergeStateStatus` is `CLEAN`, and (b) `git merge-base --is-ancestor
origin/main HEAD` succeeds. `mergeStateStatus == CLEAN` is the authoritative
signal: GitHub computes it server-side against the real base, and `CLEAN`
already encodes both currency (a `BEHIND` PR is not `CLEAN`) and mergeability (a
`DIRTY`/`BLOCKED` PR is not `CLEAN`). The `is-ancestor` check is a fast, offline,
deterministic backstop against GitHub's *asynchronous* `mergeStateStatus`
computation: immediately after a push, GitHub may still report the pre-push
status, so the local ancestor check catches a stale-`CLEAN` window the server
signal alone would miss.

**Alternatives considered:**

- The `mergeable` field (`MERGEABLE`/`CONFLICTING`/`UNKNOWN`) instead of
  `mergeStateStatus`. Rejected because: `mergeable` reports conflict state only,
  not out-of-date-with-base (`BEHIND`) — a PR can be `MERGEABLE` yet behind
  `main`, which is precisely the stale-but-conflict-free head the seed reports
  (#268, 7 behind, no conflict). `mergeStateStatus`'s richer state space
  (`CLEAN`/`BEHIND`/`DIRTY`/`BLOCKED`/`UNKNOWN`) distinguishes them.
- `is-ancestor` against *local* `main`. Rejected because: local `main` is stale
  in a worktree that never advances it (and must not — the shared-checkout
  read-only-local-`main` invariant, `orchestration-fleet`); the check must use
  `origin/main` as the baseline, left current by `/execute-task`'s in-loop fetch
  (D-4) and by any recent fetch.
- `is-ancestor` alone (no server check). Rejected because: a local ancestor
  check cannot see a `BLOCKED` state (failing required checks, unresolved
  reviews) — mergeability is genuinely a server fact.

**Chosen because:** the server `mergeStateStatus` is the authoritative
currency-and-mergeability truth and needs no local fetch; the local
`is-ancestor` closes the async-lag window deterministically and offline. Both
required, either failing → deny — the conjunction is the fail-closed posture
REQ-C1.3 demands.

## D-4: In-loop `main`-sync via fetch + merge, offloaded to a script (N)

**Decision:** `/execute-task` merges `origin/main` into the worker branch at the
top of each `review_sequence` convergence iteration. The mechanism lives in a
dedicated script (`scripts/converge-sync-main.sh`) that runs `git fetch origin
main` then `git merge FETCH_HEAD`; `/execute-task` invokes it in a single line.
It never runs `git pull` (a global `branch.autosetuprebase=always` silently
rewrites `pull` into a forbidden rebase) and never rebases, amends, squashes, or
force-pushes (bootstrap REQ-J1.4). A merge that cannot resolve cleanly exits
non-zero, and `/execute-task` halts the unit to `Awaiting input` via its
existing convergence stop-condition protocol (REQ-B1.3) — no new halt mechanism.

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

## D-5: Guard degradation — no in-hook fetch; fail closed on any doubt (N)

**Decision:** The guard does NOT itself run `git fetch` in the hook. It relies
on `mergeStateStatus` (server truth, no local fetch needed) as the authoritative
signal, and evaluates `is-ancestor` against whatever `origin/main` the last
fetch left (kept fresh by D-4's in-loop fetch and any recent orchestration
fetch). On any inability to positively confirm both D-3 conditions — `gh` absent
or erroring, `mergeStateStatus` `UNKNOWN`, `jq` absent, malformed/empty payload,
internal error — the guard DENIES with a clear reason (REQ-C1.3, REQ-K1.1).

**Alternatives considered:**

- Have the guard `git fetch origin main` itself before the ancestor check.
  Rejected because: a network fetch inside a PreToolUse hook can hang or stall
  the tool call (bounded-runtime violation, the concern the sibling guards
  encode with `MAX_CMD_LEN`); the authoritative currency signal
  (`mergeStateStatus`) is already server-computed and fetch-free, so an in-hook
  fetch buys only the async-lag backstop at the cost of latency and flakiness.
- Trust the local `origin/main` ref unconditionally (treat a passing
  `is-ancestor` as sufficient). Rejected because: a stale local ref could
  false-pass; the server `mergeStateStatus` conjunction is what prevents that.

**Chosen because:** deny-on-doubt is the only posture consistent with
"unbypassable by construction"; leaning on the fetch-free server signal keeps
the hook bounded, and the offline ancestor check adds determinism without
network cost.

## D-6: Deny precedence over the worker allow, pinned by outcome (C, `fleet-hardening` D-8 · obs:4dda9fe1)

**Decision:** `config/worker-settings.json` currently ALLOWS `Bash(gh pr ready:*)`
(so the gauntlet / a worker can flip a spec PR ready). The ready-guard's DENY
must override that allow when the invariant is unmet. Claude Code evaluates deny
before allow, but that precedence is undocumented (`obs:4dda9fe1`), so the
adversarial suite asserts the OUTCOME — a non-conforming flip stays denied even
with the allow entry present — rather than leaning on the precedence as an
assumption (REQ-C1.4, REQ-D1.2).

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

## D-7: Global wiring in `hooks/hooks.json`; the out-of-session residual (N)

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

## D-8: Cover both ready surfaces — Bash and MCP (N)

**Decision:** The guard applies the D-3 predicate to BOTH draft→ready surfaces:
the `gh pr ready` Bash command and the `mcp__github__update_pull_request` MCP
tool call carrying a draft→ready field transition. A PreToolUse Bash-string
guard does not intercept MCP tool calls (the exact gap `fleet-hardening`'s tower
guard closes by denying the GitHub MCP tools by name), so the MCP surface needs
its own matcher. The MCP matcher inspects the tool input for the draft→ready
transition (`isDraft`/`draft` going false) and applies the same predicate;
non-transitioning `update_pull_request` calls and `gh pr ready --undo` are never
gated (REQ-C1.8).

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

## D-9: The guard is core and flipper-agnostic; who-flips stays a preference (N, `customization-boundary`)

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
