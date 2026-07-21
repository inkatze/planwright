# Merge Currency Guard — Requirements

**Status:** Draft
**Last reviewed:** 2026-07-20
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright treats "PR marked ready" as "merge me": a human merges a ready PR on
sight, and the fleet flips ready autonomously (a worker or the personal
gauntlet on clean convergence, a tower under an adopter overlay). But nothing
guarantees that a PR flipped ready is still **current with `main`** and
**mergeable**. `main` advances during the long gap — hours for a heavy task —
between a worker converging on its branch head (Copilot-clean, CI-green) and
the ready-flip firing. `/execute-task` verifies CI and the review sequence on
whatever head the branch is at, and nothing re-checks that that head includes
current `main`. The only safety net is a manual tower step (relay merge-`main`
to in-flight workers after every merge), which fails under load. The result: a
ready flag can fire on a stale, DIRTY head, so the trustworthiness of the
"merge me" signal degrades exactly when the fleet is busiest.

This bundle makes the ready signal trustworthy by construction. It keeps the
verified head current — `/execute-task` merges `origin/main` into the branch at
the top of each convergence iteration, so the final CI + review verification
always runs on a `main`-current head and merge drift stays tiny — and it
enforces the invariant at the flip point with a deterministic, deny-emitting
`ready-guard` PreToolUse hook that refuses a ready-flip unless the PR is
provably current-with-`main` and mergeable. The guard is unbypassable by
construction, matching planwright's existing guard philosophy (the sibling
`worker-command-guard.sh` / `tower-command-guard.sh` deny surface). The
deliverable's altitude split — one carried hard-invariant statement on top of
two mechanisms — is recorded in D-1 (cites the pinned seed claim in Sources).

GitHub already blocks *merging* a DIRTY PR, so the human is protected at the
merge gate; this bundle protects the *ready signal* that precedes it, so a
ready PR means what the fleet and the human both assume it means.

## Scope

### In scope

- A hard invariant, stated once and cited: a PR SHALL be flipped from draft to
  ready only when it has been CI-and-review-verified on a head that includes
  current `origin/main` and is mergeable, and that invariant is enforced by a
  deterministic guard rather than by skill prose or reviewer vigilance.
- `/execute-task` syncing `origin/main` into the worker branch at the top of
  each `review_sequence` convergence iteration, via an explicit fetch + merge
  (never `pull`, never rebase), so the final CI + review verification runs on a
  `main`-current head and merge drift is kept tiny. An unresolvable conflict
  halts to `Awaiting input` (the existing convergence stop condition; no new
  halt mechanism).
- A deterministic, deny-emitting `ready-guard` PreToolUse hook that intercepts
  a draft→ready transition and DENIES it unless the PR's `mergeStateStatus` is
  `CLEAN` and `origin/main` is an ancestor of the branch head — covering both
  the `gh pr ready` Bash surface and the `mcp__github__update_pull_request`
  MCP surface, since a Bash-string guard does not intercept MCP calls.
- The guard's fail-closed contract (no LLM in the decision path, the
  intercepted command treated as inert data, any inability to positively
  confirm both conditions resolves to DENY) and an adversarial suite that pins
  the deny-over-allow outcome rather than an undocumented precedence.
- Global wiring of the guard in `hooks/hooks.json` so it governs every
  planwright session that attempts a ready-flip, regardless of the settings
  profile in force.

### Out of scope

- Adding an autonomous ready-flip to `/execute-task`. The draft→ready flip
  stays a control exercised by the human, the gauntlet, or an adopter overlay;
  this bundle makes the head the flip lands on current, and gates the flip —
  it does not decide *who* flips or mandate that the flip be automatic (D-9).
- Auto-merge or any change to the merge gate. Merge stays the human's reserved
  control; GitHub's own DIRTY-PR merge block is unchanged and relied upon.
- Governing a ready-flip issued from a bare shell outside any Claude Code
  session. Hooks fire only in-session; a human typing `gh pr ready` at a raw
  terminal is exercising their reserved control and is an accepted residual
  (D-7), the same class of residual as guard-coverage's `--no-verify` gap.
- The tower's own merge-detection and fetch-before-gate dispatch freshness
  (`fleet-hardening` D-9 / its `dispatch-fetch.sh`), which evaluates the gate
  against fetched `origin/main` **without advancing local `main`** and does not
  merge into any branch — a read-only dispatch-time concern, distinct from this
  bundle's in-loop branch merge. Consumed as a sibling, not redefined.
- Promoting the guard to a server-side boundary. Branch protection can block a
  merge but cannot express "the head includes current `main`" nor intercept the
  ready-flip; the guard is the in-session enforcement layer, best-effort against
  a determined out-of-session bypass, the same honesty guard-coverage states
  for its permission-deny layer.
- Reopening the `guard-coverage` or `fleet-hardening` bundles. Their artifacts
  (the guard family, the fetch-before-gate primitive) are consumed and cited as
  Sources, never edited.

## REQ-A — The ready-currency invariant

- **REQ-A1.1** A PR SHALL be transitioned from draft to ready only when it has
  been CI-and-review-verified on a head that includes current `origin/main` and
  is mergeable (its GitHub `mergeStateStatus` is `CLEAN`).
  *(Cites: obs:921b93c9.)*
- **REQ-A1.2** The invariant in REQ-A1.1 SHALL be enforced by construction — a
  deterministic guard that refuses a non-conforming flip — not by skill prose,
  a checklist, or reviewer vigilance.
  *(Cites: obs:921b93c9 · `guard-coverage` guard philosophy.)*
- **REQ-A1.3** Enforcement SHALL be agnostic to which party issues the flip
  (a `/execute-task` worker, the gauntlet, a tower under an adopter overlay, or
  a human acting inside a Claude Code session): the guard fires wherever a
  draft→ready transition is attempted in-session.
  *(Cites: drafting-session decision (2026-07-20).)*
- **REQ-A1.4** This bundle SHALL NOT mandate that the ready-flip be automatic
  or performed by any particular party; it enforces the currency invariant at
  whatever flip occurs and leaves the who-flips policy to the settings/overlay
  layer.
  *(Cites: drafting-session decision (2026-07-20) · D-9.)*

## REQ-B — Convergence-loop main-currency

- **REQ-B1.1** `/execute-task` SHALL merge `origin/main` into the worker branch
  at the top of each `review_sequence` convergence iteration, so drift from
  `main` is re-closed every iteration and the final CI + review verification
  runs on a `main`-current head.
  *(Cites: obs:921b93c9.)*
- **REQ-B1.2** The sync in REQ-B1.1 SHALL use an explicit fetch followed by a
  merge (`git fetch origin main` then `git merge FETCH_HEAD`); it SHALL NOT use
  `git pull` (which a global `branch.autosetuprebase=always` silently turns
  into a forbidden rebase) and SHALL NOT rebase, amend, squash, or force-push
  (the `bootstrap` REQ-J1.4 hard invariant).
  *(Cites: `bootstrap` REQ-J1.4 · drafting-session decision (2026-07-20).)*
- **REQ-B1.3** An `origin/main` merge that cannot be resolved cleanly SHALL
  halt the unit to `tasks.md` `Awaiting input` with the reason, reusing the
  existing convergence stop-condition protocol; no new halt mechanism is
  introduced.
  *(Cites: `execute-task` SKILL convergence stop conditions.)*
- **REQ-B1.4** `/execute-task` SHALL continue to open only a draft PR and SHALL
  NOT itself perform the draft→ready flip; the in-loop sync changes the head the
  eventual flip lands on, not who flips.
  *(Cites: `execute-task` SKILL D-21 / REQ-J1.1 · drafting-session decision (2026-07-20).)*
- **REQ-B1.5** The sync mechanism SHALL be implemented as a dedicated script the
  skill invokes in a single line, so the `/execute-task` instruction body does
  not grow a paragraph and stays within its instruction-headroom budget.
  *(Cites: `instruction-headroom` requirements · `prompt-hygiene`.)*

## REQ-C — The ready-guard

- **REQ-C1.1** A deterministic PreToolUse guard SHALL intercept a draft→ready
  transition and emit a DENY decision unless BOTH conditions hold: the PR's
  GitHub `mergeStateStatus` is `CLEAN`, and `git merge-base --is-ancestor
  origin/main HEAD` succeeds.
  *(Cites: obs:921b93c9.)*
- **REQ-C1.2** The guard SHALL be deny-emitting — a new modality relative to the
  allow-only `worker-command-guard.sh` / `tower-command-guard.sh` — with no LLM
  in the decision path and purely deterministic shell logic.
  *(Cites: obs:921b93c9 · `worker-permission-ergonomics` D-1 · `fleet-hardening` D-8.)*
- **REQ-C1.3** The guard SHALL fail closed: any inability to positively confirm
  both REQ-C1.1 conditions — `gh` absent or erroring, `mergeStateStatus`
  reported as `UNKNOWN` (GitHub computes it asynchronously), `jq` absent, a
  malformed or empty payload, or any internal error — SHALL resolve to DENY with
  a clear, actionable reason, never a silent allow.
  *(Cites: `worker-command-guard.sh` fail-closed contract.)*
- **REQ-C1.4** The guard's DENY SHALL take precedence over the existing
  `gh pr ready` allow entry in `config/worker-settings.json`, and an adversarial
  suite SHALL pin that OUTCOME (a denied flip stays denied) rather than relying
  on Claude Code's undocumented allow-vs-deny precedence.
  *(Cites: obs:4dda9fe1 · `fleet-hardening` REQ-C1.3.)*
- **REQ-C1.5** The guard SHALL treat the intercepted command or tool payload
  strictly as inert data — never eval-ed, re-expanded, glob-expanded, or
  executed — so analyzing a hostile invocation can never run it.
  *(Cites: `worker-command-guard.sh` security contract.)*
- **REQ-C1.6** The guard SHALL cover both draft→ready surfaces: the
  `gh pr ready` Bash surface and the `mcp__github__update_pull_request`
  MCP surface (the draft→ready field transition), applying the same REQ-C1.1
  predicate to each, since a Bash-string PreToolUse guard does not intercept
  MCP tool calls.
  *(Cites: `fleet-hardening` tower-settings MCP-surface clause · drafting-session decision (2026-07-20).)*
- **REQ-C1.7** The guard SHALL be wired as a global PreToolUse hook in
  `hooks/hooks.json` (a Bash matcher and an MCP matcher), so it governs every
  planwright session that attempts a ready-flip regardless of the settings
  profile in force.
  *(Cites: drafting-session decision (2026-07-20) · `tower-command-guard.sh` profile-scoping contrast.)*
- **REQ-C1.8** The guard SHALL NOT block `gh pr ready --undo` (re-drafting a PR
  is always safe) nor any non-transitioning `update_pull_request` call; only a
  draft→ready transition is gated.
  *(Cites: `worker-settings.json` `--undo` handling · drafting-session decision (2026-07-20).)*

## REQ-D — Verification

- **REQ-D1.1** A fixture-driven adversarial suite SHALL exercise the guard over
  the full decision matrix: current + `CLEAN` → not denied; `BEHIND` → denied;
  `DIRTY`/`BLOCKED` → denied; `UNKNOWN` → denied; `gh pr ready --undo` → not
  denied; missing `gh`/`jq`, malformed payload → denied (fail-closed); across
  both the Bash and MCP surfaces.
  *(Cites: `worker-permission-ergonomics` adversarial-suite precedent.)*
- **REQ-D1.2** A test SHALL assert the deny-over-allow OUTCOME against a payload
  that the `config/worker-settings.json` `gh pr ready` allow entry would
  otherwise pass.
  *(Cites: obs:4dda9fe1 · REQ-C1.4.)*
- **REQ-D1.3** A test SHALL cover the sync script: a clean fast-forward/merge
  succeeds; a conflicting merge exits non-zero for the caller to halt on; and
  negative assertions confirm the script issues no `git pull` and no rebase.
  *(Cites: REQ-B1.2 · REQ-B1.3.)*
- **REQ-D1.4** Negative assertions SHALL confirm no model/API call appears in
  the guard's or the sync script's decision path.
  *(Cites: `fleet-autonomy` D-18 · REQ-C1.2.)*

## REQ-K — Graceful degradation and data hygiene

- **REQ-K1.1** Every guard denial and every sync halt SHALL surface a clear
  message naming what could not be confirmed (or what conflicted) and the next
  step, rather than failing opaquely.
  *(Cites: `bootstrap` REQ-K1.7.)*
- **REQ-K1.2** No committed artifact of this bundle — spec prose, scripts,
  fixtures, test data — SHALL contain secrets, credentials, internal hostnames,
  or sensitive operational detail.
  *(Cites: `bootstrap` REQ-D1.6.)*

## Sources

- `obs:921b93c9` — the seed observation (recorded 2026-07-20,
  `specs/_observations/entries/2026-07-20-pre-ready-main-sync-921b93c9.md`,
  currently on the unmerged `planwright/chore/observations` branch): in-flight
  worker PRs go behind/DIRTY vs `main` because `main` advances during the gap
  between convergence and the ready-flip; observed on `fleet-hardening` #271
  (DIRTY) and #268 (7 behind); the manual tower merge-`main` relay fails under
  load; durable fix = a mandatory pre-ready currency step plus a deterministic
  gate. **Pinned altitude claim:** the seed frames the fix as encoding a hard
  invariant "unbypassable by construction, matching planwright's guard
  philosophy" — a first-class-concern claim that fires the autopilot-reflex
  altitude gate and is resolved in D-1.
- **Related specs (cited, not extended):** `guard-coverage` (Ready) — the
  deterministic guard family this guard joins as a sibling; its
  never-merge/force-push/amend guards are the closest prior art, but a
  ready-currency guard is a distinct invariant with its own predicate.
  `fleet-hardening` (Ready) — its fetch-before-gate dispatch freshness
  (`dispatch-fetch.sh`, D-9) and its tower-guard MCP-surface handling are
  consumed as siblings; the seed is an observation *about* fleet-hardening's
  execution (#271), not part of its scope. Fold-detection ran against all
  non-terminal specs; spin-new because every D-21 trigger fired (new external
  interface, independently ownable, decisions orthogonal to either bundle's
  domain, both candidates Ready/in-flight).
- `obs:4dda9fe1` — Claude Code's allow-vs-deny precedence is undocumented, so
  guard tests must pin the OUTCOME, not the assumed precedence (consumed by
  `fleet-hardening`; cited here for REQ-C1.4).
- `bootstrap` REQ-J1.4 (never rebase/amend/squash/force-push), REQ-J1.1 /
  `execute-task` D-21 (draft→ready is the human's reserved control), REQ-K1.7
  (graceful degradation), REQ-D1.6 (data hygiene).
- `worker-permission-ergonomics` (Done, #236/#237) — `worker-command-guard.sh`,
  the allow-only PreToolUse guard pattern, tokenizer, and fail-closed
  contract this guard reuses (inverted to deny-emitting).
- Machine-local operational note: a global `branch.autosetuprebase=always`
  turns a bare `git pull` into a forbidden rebase, which is why REQ-B1.2
  mandates explicit fetch + merge. (Origin: recurring planwright worker-pull
  strandings; verified against planwright #248.)
