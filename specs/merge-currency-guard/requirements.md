# Merge Currency Guard — Requirements

**Status:** Ready
**Last reviewed:** 2026-07-22
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
  a draft→ready transition and DENIES it unless the PR is current with its base
  (GitHub's compare `behind_by == 0`) and its `mergeable` field is `MERGEABLE`
  (non-conflicting) — both server-computed against the PR's real base (no local
  ref, OID, fetch, or `mergeStateStatus` / branch-protection dependence), the
  target resolved from the intercepted call's own validated selector — covering
  the `gh pr ready` Bash surface and the `mcp__github__update_pull_request` MCP
  surface (a Bash-string guard does not intercept MCP calls), each gated only
  when the PR is currently a draft.
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
- Owning any other consumer of the ready-flip surface. This bundle owns the
  single **gating** hook on the draft→ready transition; the sibling surfaces
  compose around it rather than duplicating the predicate:
  `concurrent-orchestrator-coordination`'s tower merge-`main` relay remains
  that spec's operational currency mitigation (never a second gate — this
  guard is the enforcement floor beneath it), and the
  deterministic-pr-ready-push observation's notification-on-ready-flip, if
  built, rides its own observer hook on the same surface, outside this
  bundle. (Boundary decided at kickoff §2, 2026-07-21.)
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
  been CI-and-review-verified on a head that is current with its base branch (the
  base has no commit the head lacks — GitHub's compare `behind_by == 0`) and
  mergeable (`mergeable == MERGEABLE`, not `CONFLICTING`). This requirement is
  the single stated home of the invariant (this bullet); it joins bootstrap's
  never-merge/force-push/amend hard-invariant family by citation, not by
  duplication.
  *(Cites: obs:921b93c9 · `bootstrap` REQ-J1.4 invariant family · kickoff §4 lens (2026-07-22).)*
- **REQ-A1.2** The invariant's currency and mergeability clauses SHALL be
  enforced by construction — a deterministic guard that refuses a
  non-conforming flip — not by skill prose, a checklist, or reviewer
  vigilance. The CI-and-review-verified clause remains attested by the
  flipping party's convergence discipline; the guard reads no check or review
  state (only currency and conflict) and is never read as certifying it.
  *(Cites: obs:921b93c9 · `guard-coverage` guard philosophy · kickoff §3 (2026-07-21) · kickoff §4 panel (2026-07-22).)*
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
  at the top of each `review_sequence` convergence iteration (one sync per
  full pass through the sequence, before its first skill runs), so drift from
  `main` is re-closed every iteration and the final CI + review verification
  runs on a `main`-current head. Because the sync runs at the *top* of the
  iteration and `/execute-task`'s CI + review verification runs later within the
  same iteration, the final iteration's verification lands on the post-sync
  (`main`-current) head; no separate post-merge CI re-run is introduced.
  *(Cites: obs:921b93c9 · kickoff §4 lens (2026-07-22).)*
- **REQ-B1.2** The sync in REQ-B1.1 SHALL use an explicit fetch followed by a
  merge (`git fetch origin main` then `git merge --no-edit FETCH_HEAD`); it
  SHALL NOT use `git pull` (which a global `branch.autosetuprebase=always`
  silently turns into a forbidden rebase) and SHALL NOT rebase, amend, squash,
  or force-push (the `bootstrap` REQ-J1.4 hard invariant). The sync keeps the
  worker branch head current so the eventual ready-flip's compare `behind_by` is
  `0`; the guard reads no local ref, so the sync carries no obligation to advance
  any remote-tracking ref for the guard's sake.
  *(Cites: `bootstrap` REQ-J1.4 · drafting-session decision (2026-07-20) · kickoff §4 lens (2026-07-22).)*
- **REQ-B1.3** An `origin/main` merge that cannot be resolved cleanly SHALL be
  aborted (`git merge --abort`, leaving the working tree clean, not
  half-applied) and SHALL halt the unit to `tasks.md` `Awaiting input` with a
  reason distinct from a fetch failure, reusing the existing convergence
  stop-condition protocol; no new halt mechanism is introduced. Because the
  abort leaves a clean tree, re-invoking the sync on resume is idempotent (it
  re-attempts the same fetch + merge rather than failing on a lingering
  `MERGE_HEAD`); drift is re-closed by the human (or the tower's merge-`main`
  relay) landing `origin/main` before convergence resumes.
  *(Cites: `execute-task` SKILL convergence stop conditions · kickoff §4 lens (2026-07-22).)*
- **REQ-B1.6** The sync script SHALL distinguish its non-zero exit causes —
  unreachable-remote fetch failure, an unresolvable `origin/main` merge
  conflict, and a pre-existing dirty working tree that blocks the merge — and
  surface each with its own reason (REQ-K1.1), never collapsing a dirty-tree or
  fetch failure into a misreported "merge conflict".
  *(Cites: REQ-K1.1 · kickoff §4 lens (2026-07-22).)*
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
  transition and emit a DENY decision unless BOTH server-computed conditions
  hold: the PR is current with its base branch — GitHub's compare of
  `<baseRefName>...<headRefOid>` reports `behind_by == 0` — and its `mergeable`
  field is `MERGEABLE` (not `CONFLICTING`); `baseRefName`/`headRefOid`/`mergeable`
  from one `gh pr view`, `behind_by` from the compare endpoint. The guard SHALL
  NOT key currency on `mergeStateStatus` (which reports `BEHIND` only under the
  base's "require up to date" branch protection, so a behind PR on an unprotected
  base reads `CLEAN`). The guard SHALL read no local git ref, object, or
  `is-ancestor` result and SHALL run no `git fetch`, so the decision is identical
  for every flipper and every base branch. `mergeable` reported `UNKNOWN`, or a
  compare/query failure, SHALL resolve to DENY naming a wait-and-retry remedy.
  *(Cites: obs:921b93c9 · kickoff §4 (2026-07-21) · kickoff §4 panel (2026-07-22).)*
- **REQ-C1.2** The guard SHALL be deny-emitting — a new modality relative to the
  allow-only `worker-command-guard.sh` / `tower-command-guard.sh` — with no LLM
  in the decision path and purely deterministic shell logic.
  *(Cites: obs:921b93c9 · `worker-permission-ergonomics` D-1 · `fleet-hardening` D-8.)*
- **REQ-C1.3** The guard SHALL fail closed: any inability to positively confirm
  both REQ-C1.1 conditions — `gh` absent or erroring, `mergeable` reported as
  `UNKNOWN` (GitHub computes it asynchronously), the compare call failing or
  unavailable, `jq` absent, a malformed or empty payload, or any internal error
  — SHALL resolve to DENY with a clear, actionable reason, never a silent allow.
  Because `UNKNOWN` is the expected transient state immediately after the head or
  base moves (a just-pushed convergence head), the guard SHALL re-query at least
  once within its bounded runtime before denying on `UNKNOWN`, and the `UNKNOWN`
  denial's remedy SHALL be **wait-and-retry** (GitHub is still computing), never
  a `git fetch` (which cannot advance a server-side computation). The guard SHALL
  bound its server call(s) with a timeout and treat a timeout as a
  confirm-failure → DENY (a hung call must not stall the PreToolUse hook into a
  no-output fail-open); it SHALL positively identify a gated ready-flip before
  issuing any network call, so a non-matching Bash command returns with zero
  network cost.
  *(Cites: `worker-command-guard.sh` fail-closed contract · kickoff §4 lens (2026-07-22).)*
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
- **REQ-C1.8** Only a genuine draft→ready transition SHALL be gated. On BOTH
  surfaces the guard SHALL read the PR's current `isDraft` and gate only when it
  is `true`, so a `gh pr ready` on an already-ready PR (a no-op) is never denied,
  symmetric with the MCP matcher's handling of a non-transitioning
  `update_pull_request`; `gh pr ready --undo` (re-drafting) is never gated.
  *(Cites: `worker-settings.json` `--undo` handling · drafting-session decision (2026-07-20) · kickoff §4 panel (2026-07-22).)*
- **REQ-C1.9** The guard SHALL derive the target PR only from the intercepted
  call's own selector — the Bash positional PR argument (or, for a bare
  command, the current branch's PR), and the MCP `owner`/`repo`/`pullNumber`
  fields — validate each against its grammar (a PR number is digits; an
  owner/repo matches GitHub's charset) before use, and pass them to `gh pr view`
  as separate arguments, never interpolated into a command string, so a hostile
  selector can neither redirect the query to a different PR/repo nor inject a
  `gh` option or shell metacharacter. A selector that is invalid or resolves the
  target ambiguously SHALL resolve to DENY.
  *(Cites: `security-posture` never-execute-untrusted-input · kickoff §4 lens (2026-07-22).)*
- **REQ-C1.10** The Bash matcher SHALL recognize a gated `gh pr ready`
  invocation behind a simple leading `cd <path> &&` / `;` prefix (the common
  worktree form a worker emits), not only a bare command. The `gh api graphql`
  `markPullRequestReadyForReview` mutation and other indirect invocations a
  deterministic matcher cannot robustly parse (`sh -c '…'`, `eval`, `env gh …`,
  custom wrappers, raw `curl`) are an accepted residual of the same class as the
  out-of-session residual (D-7): the `markPullRequestReadyForReview` mutation
  carries an opaque GraphQL node ID (`pullRequestId`) rather than a
  number/branch selector, so it is not resolvable under the REQ-C1.9 selector
  model without a separate node-ID resolution path; and the autonomous flippers
  use `gh pr ready` and the MCP tool, not the raw mutation. Closing the mutation
  surface is a documented follow-up, not a first-cut requirement.
  *(Cites: `fleet-hardening` tower-guard surface enumeration · kickoff §4 lens (2026-07-22) · kickoff §4 panel (2026-07-22).)*

## REQ-D — Verification

- **REQ-D1.1** A fixture-driven adversarial suite SHALL exercise the guard over
  the full decision matrix: `behind_by == 0` + `mergeable MERGEABLE` → not
  denied; `behind_by > 0` (stale, on a base **without** "require up to date"
  protection, the false-allow case) → denied; `mergeable CONFLICTING` → denied;
  `mergeable UNKNOWN` or a compare failure → denied (after the bounded re-query);
  an already-ready PR (`isDraft == false`) and `gh pr ready --undo` → not denied;
  missing `gh`/`jq`, malformed payload, or an invalid/ambiguous target selector
  → denied (fail-closed); across the Bash and MCP surfaces.
  *(Cites: `worker-permission-ergonomics` adversarial-suite precedent · kickoff §4 lens (2026-07-22) · kickoff §4 panel (2026-07-22).)*
- **REQ-D1.2** A test SHALL assert the deny-over-allow OUTCOME against a payload
  that the `config/worker-settings.json` `gh pr ready` allow entry would
  otherwise pass.
  *(Cites: obs:4dda9fe1 · REQ-C1.4.)*
- **REQ-D1.3** A test SHALL cover the sync script: a clean fast-forward/merge
  succeeds; a conflicting merge exits non-zero for the caller to halt on; a
  failed fetch (unreachable remote) exits non-zero with a clear reason; and
  negative assertions confirm the script issues no `git pull` and no rebase.
  *(Cites: REQ-B1.2 · REQ-B1.3 · kickoff §3 (2026-07-21).)*
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
- **REQ-K1.3** Any untrusted content the guard or the sync script echoes into a
  denial or halt message — a PR head/base branch name, `gh`/`git` stderr, a
  parsed selector — SHALL be stripped of non-printable bytes before it is
  emitted (the canonical `scripts/echo-safety.sh` `sanitize_printable`), so an
  embedded terminal escape sequence in an attacker-controllable fork branch name
  cannot drive the operator's terminal or corrupt the audit log.
  *(Cites: `security-posture` echo-discipline · kickoff §4 lens (2026-07-22).)*

## Changelog

- 2026-07-20 — Initial draft (autonomous `/spec-draft` from obs:921b93c9).
- 2026-07-21 — Kickoff walk edits (Draft, in place): shared ready-flip
  surface boundary added to Out of scope (kickoff §2); REQ-A1.2
  enforcement-scope split; REQ-B1.1 sync-cadence clarifier; fetch-failure
  case added to REQ-D1.3 and the test-spec; D-3 ancestor leg retargeted to
  the PR's `headRefOid` (REQ-C1.1, Task 2, test-spec updated); D-8 MCP
  transition discrimination pinned to current `isDraft`; REQ-D1.2 test-spec
  entry gained the deny-over-allow OUTCOME-pattern pointer; the fetch-failure
  exit was gated into Task 3's Done-when and Task 4's deliverable list.
- 2026-07-22 — Kickoff §4 lens-pass edits (Draft, in place). Guard predicate
  re-derived (D-3, REQ-A1.1, REQ-C1.1, REQ-D1.1, Task 2, test-spec): dropped
  `mergeStateStatus == CLEAN` (it over-denies a current, conflict-free PR whose
  only failing/pending check is non-required — `UNSTABLE`, observed on PR #298 —
  re-enforcing CI state the REQ-A1.2 split excludes) for currency via
  `is-ancestor(origin/<baseRefName>, headRefOid)` + mergeability via
  `mergeable != CONFLICTING`; base branch read
  per-PR (C4); target-PR selector resolution + injection hardening added as new
  **REQ-C1.9** (meaning-class addition); conflict handling now aborts the merge
  and halts idempotently (REQ-B1.3, D-4, Task 3, test-spec, C5); D-5/D-8 updated
  to the new field set. Convergence-churn risk row (§7 row 8) added; several
  test-spec fixtures strengthened (hostile-OID gate, no-LLM stub reachability,
  matrix-completeness manifest, gauntlet-fixture); `design.md` decisions moved
  under a `## Decision log` at H3 so the validator parses them.
- 2026-07-22 — Kickoff §4 lens-pass edits, batch 2 (Draft, in place). Third
  ready surface covered: new **REQ-C1.10** (the `gh api graphql
  markPullRequestReadyForReview` mutation; compound/indirect forms an accepted
  D-7-class residual; D-8, Task 2, test-spec). Guard-catalog registration
  dropped from Task 1 (category error; the builder catalog is for adopter
  stack-tools, not an internal deny hook) — Task 1 retitled, the invariant's
  single home pinned to REQ-A1.1 cross-referenced to bootstrap. Added
  **REQ-K1.3** (echo-safety on emitted untrusted content), a `gh pr view`
  timeout + network-free fast-path clause (REQ-C1.3), an `origin/main`
  remote-tracking-freshness clause (REQ-B1.2), **REQ-B1.6** (distinct
  non-zero-exit causes: fetch/conflict/dirty-tree), a CI-runs-post-sync
  clarifier (REQ-B1.1), and a D-6 hook-vs-rule-precedence reframe. Test-spec
  entries added for REQ-C1.10 / REQ-K1.3 / REQ-B1.6 and the timeout fixture.
- 2026-07-22 — Kickoff §4 lens-pass edits, batch 3 (Draft, in place). An
  adversarial re-check of batch-1's `is-ancestor` currency leg found it
  false-*allows* a stale flip for any flipper but the just-fetched
  `/execute-task` worker and for any non-`main` base (a stale-but-present local
  `origin/<base>` ref passes), and false-*denies* cross-fork heads. Predicate
  settled on **server-authoritative** `mergeStateStatus ∈ {CLEAN, UNSTABLE}` +
  `mergeable == MERGEABLE` (D-3, D-5, REQ-A1.1, REQ-C1.1, REQ-C1.3, REQ-D1.1,
  Task 2, test-spec, Scope): no local ref/OID/`is-ancestor`/fetch, so the
  decision is identical for every flipper and base; `BLOCKED` denies (required
  checks/reviews, per the REQ-A1.2 split), `UNSTABLE` defers (non-required
  checks stay the flipper's concern). REQ-C1.3 gains a bounded `UNKNOWN`
  re-query and a wait-and-retry (not fetch) remedy; REQ-B1.2's guard-ref
  freshness clause is dropped as moot; REQ-C1.10 covers a `cd && gh pr ready`
  prefix; risk rows 3 and 6 re-cast to the server-authoritative residuals.
- 2026-07-22 — Kickoff §4 panel-pass edits, batch 4 (Ready re-sign-off, in
  place). An independent-model panel pass (gemini) found the batch-3 currency
  signal broken (G1, critical): GitHub's `mergeStateStatus` reports `BEHIND` only
  under the base's "require branches up to date" protection, absent on
  planwright's `main`, so a behind PR reads `CLEAN` (confirmed: PR #276, 22
  behind, `CLEAN`/`MERGEABLE`) and the predicate would false-allow the stale
  flip. Currency moved to the compare endpoint's `behind_by == 0` (D-3, D-5,
  REQ-A1.1, REQ-C1.1, REQ-C1.3, REQ-D1.1, Task 2/4, test-spec, Scope) —
  branch-protection-independent, server-side, no local state; `mergeStateStatus`
  dropped entirely (dissolving the `DRAFT`/`HAS_HOOKS` handling). REQ-A1.2's
  guard-covers-`BLOCKED` clause removed (the guard reads no check state). The
  `gh api graphql markPullRequestReadyForReview` surface demoted to a documented
  residual (G3: opaque node-ID selector, unresolvable under REQ-C1.9). The Bash
  `isDraft` gate made symmetric with the MCP matcher (G4; REQ-C1.8, D-8).

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
