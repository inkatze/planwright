# Human gates — Tasks

**Status:** Draft
**Last reviewed:** 2026-09-22
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order, which is presentation; the `Dependencies:` lines
carry the graph. The order follows the altitude D-1 fixes: the doctrine lands
first, the knobs and the shared spelling fixtures next, the guards on top of
them, the policy helpers on top of the guards, and the prose sweep last, once
every surface it restates exists.

## Tasks

### Task 1 — The human-gates doctrine and its pointers

- **Deliverables:** `doctrine/human-gates.md` stating the gate test, the
  list it yields, and each rule's kind with its knob and default or its
  owning skill; its row in the doctrine README index; a `Superseded-by:
  human-gates D-2` pointer on bootstrap D-26 with a dated bootstrap changelog
  entry and no body edit; `doctrine/gate-wiring.md` rewritten so the
  approval act is the merge or the `on-approval` act, never the flip, with
  the one-line legacy-marker mapping; `doctrine/autonomous-safe-decision.md`
  and `doctrine/orchestration-modes.md` citing the policy instead of an
  unconditional never; the doctrine-index and doc-link checks green.
- **Done when:** the doc exists and every rule in it carries a kind; the
  bootstrap pointer resolves; grep of `doctrine/` for the retired phrasing
  finds only the mapping line; `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-1, D-2, D-3, D-10, D-13 · REQ-A1.1, REQ-A1.2, REQ-A1.3,
  REQ-A1.4, REQ-A1.5, REQ-B1.1, REQ-B1.9, REQ-D1.6
- **Estimated effort:** 1 day

### Task 2 — Sign-off trailer mechanics

- **Deliverables:** `scripts/planwright-commit-trailers.sh` (or a sibling)
  stamping `Planwright-Sign-Off: PS-<n>` with the id written once from the
  branch's next free id; checklist regeneration reading trailers through
  `git log --format='%(trailers:key=Planwright-Sign-Off,valueonly)'` over
  `base..head`; `scripts/check-commit-msgs.sh --marker subject` retired and
  `--marker title` broadened to reject the legacy bracket or a bare trailer
  line; `tests/test-check-commit-msgs.sh` updated; a regression test
  proving a revert of a trailered commit yields one item, not two; a gated
  deferral for dropping `--marker title` after one release.
- **Done when:** the revert test fails on the subject-grep path and passes
  on the trailer path; a base-merge that reorders the range leaves every
  `PS-<n>` unchanged; the lint suite is green.
- **Dependencies:** 1
- **Citations:** D-3, D-12 · REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.6
- **Estimated effort:** 1 day

### Task 3 — Sign-off prose in the gate-wired skills

- **Deliverables:** `/polish`, `/self-review`, and `/execute-task` stamping
  the trailer instead of the subject suffix, printing trailered SHAs and the
  trailer-aware log command at handoff, generating the pending-sign-off
  section with the approval act and the revert rule stated inside it and the
  checkbox dropped or relabelled, disclosing a shared commit with per-item
  revert recipes, and stating the apply-then-review default in the attended
  path in the same words as the unattended one; `check-instructions.sh`
  word-neutral or better on each surface.
- **Done when:** a fixture run of each skill emits a section carrying the
  approval statement; no skill body contains the retired subject suffix;
  `mise run check` (instruction budget included) passes.
- **Dependencies:** 2
- **Citations:** D-3, D-12, D-13 · REQ-B1.5, REQ-B1.6, REQ-B1.7, REQ-B1.8
- **Estimated effort:** 1 day

### Task 4 — The policy knobs

- **Deliverables:** `ready_flip_policy`, `ready_flip_ci_wait`,
  `merge_policy`, `merge_class_max_lines`, `merge_class_exclude_paths`, and
  `worker_merge_conflicts` in `config/defaults.yml` with commented defaults;
  their rows in `docs/options-reference.md`; legal-value validation through
  `scripts/resolve-config-knob.sh` with the by-layer malformed policy and
  fail-closed defaults (`human`, `human`, `halt`); tests for each value and
  each malformed arm.
- **Done when:** each knob resolves through all four layers in a test; a
  malformed repo-tracked value exits non-zero and an adopter-layer one
  degrades to the strict default with a warning; the options check passes.
- **Dependencies:** 1
- **Citations:** D-4, D-6, D-7 · REQ-C1.1, REQ-D1.1, REQ-E1.2, REQ-H1.3
- **Estimated effort:** half day

### Task 5 — The shared reserved-control spelling fixtures

- **Deliverables:** `tests/fixtures/reserved-control-spellings`, one refused
  spelling per line with its class (merge including `git pull` and every
  refspec form, the flip and its undo, force-push, amend, squash, fixup,
  rebase, protected-ref pushes, the MCP names); one test driving the file
  through the tower queue's reserved-control check, the ready-guard, the
  worker and tower command guards, and both deny profiles, failing on any
  copy that admits a line; the `git pull` gap closed in the profiles.
- **Done when:** the test fails before the profile edit on `git pull` and
  passes after; every existing guard test stays green.
- **Dependencies:** none
- **Citations:** D-9 · REQ-G1.1
- **Estimated effort:** 1 day

### Task 6 — The policy guard and the profile floor

- **Deliverables:** `scripts/policy-guard.sh`, a deny-emitting PreToolUse
  hook reading the policy knobs through the shared resolver within a
  wall-clock bound and refusing what the resolved value forbids for the
  session's tier (flip, base merge, never-pushed rewrite, `--undo` outside
  the corrective helper), denying on any read failure; its wiring in
  `hooks/hooks.json` and both settings profiles; the profiles reduced to
  the floor (main and protected-ref mutation, agent merge outside the
  class, pushed-commit rewrite) with policy-permittable spellings removed
  for the tiers a value can grant them to; an adversarial suite in the
  ready-guard's style; the wiring tests updated; the cross-copy test of
  Task 5 extended to drive the new guard too.
- **Done when:** each policy value produces the expected deny or defer per
  spelling in the suite; an unresolvable knob denies; the never-pushed check
  refuses a commit any remote-tracking ref contains; the hook-contract and
  wiring checks pass.
- **Dependencies:** 4, 5
- **Citations:** D-8, D-9 · REQ-C1.5, REQ-E1.3, REQ-F1.1, REQ-F1.5,
  REQ-G1.2, REQ-G1.3, REQ-G1.4, REQ-G1.5
- **Estimated effort:** 2 days

### Task 7 — The ready-flip helper and its wiring

- **Deliverables:** `scripts/ready-flip.sh` evaluating the preconditions on
  the current head (ready-guard defer, positive-green rollup within
  `ready_flip_ci_wait`, the review loop's handoff record naming that head
  with a head-SHA line added if it lacks one, no Awaiting-input bullet),
  writing the PR record before flipping, parking a
  failed flip under `## Awaiting input` naming the predicate; `/execute-task`
  calling it as the terminal convergence step under `agent`; the
  spec-PR knob documented as the same class; tests over stubbed `gh` for
  every predicate and the record-write failure.
- **Done when:** a fixture PR with one failing predicate stays draft and
  gains the parking bullet; a passing one gains the record comment and the
  flip in that order; `human` never calls the helper.
- **Dependencies:** 4, 6
- **Citations:** D-4, D-5 · REQ-C1.2, REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.6
- **Estimated effort:** 1.5 days

### Task 8 — The reviewer-request side effect

- **Deliverables:** a recorded verification (docs plus a scratch-PR probe)
  of whether requesting a reviewer un-drafts a draft PR, appended to the
  kickoff brief's risk register; the fix the evidence selects in every
  planwright surface that requests a reviewer (verify-then-re-draft through
  a helper that is the sole sanctioned `--undo` spelling, or a transport
  without the side effect); the helper allowlisted in the policy guard; a
  test for the re-draft path.
- **Done when:** the risk-register entry names the sources consulted; a
  stubbed request that un-drafts is followed by a re-draft; no other undo
  spelling is admitted by the guard suite.
- **Dependencies:** 6
- **Citations:** D-11 · REQ-C1.7, REQ-C1.8
- **Estimated effort:** half day

### Task 9 — The merge policy

- **Deliverables:** `scripts/merge-class.sh` evaluating the class
  predicates deterministically (no trailer in range, no hard-disqualifier
  path, no Awaiting-input bullet, the Task 7 preconditions, the adopter
  bounds) and emitting the evidence record; one merge helper using the
  repository's sanctioned strategy, allowlisted only under `policy-class`
  for an admitted PR; identity detection comparing the session login to the
  PR author, with the docs' recommended split and the approving-review path
  it unlocks; `on-approval` documented as enabling auto-merge; tests for
  each predicate, the fall-through to `on-approval`, and the record-write
  abort.
- **Done when:** a PR carrying a sign-off trailer is never admitted under
  any bounds; an admitted PR gets its record before the merge call; under
  `human` and `on-approval` the guard suite denies every merge spelling.
- **Dependencies:** 4, 6, 7
- **Citations:** D-6, D-14 · REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4,
  REQ-D1.5, REQ-D1.7
- **Estimated effort:** 2 days

### Task 10 — Worker base merge and the conflict knob

- **Deliverables:** `scripts/converge-sync-main.sh` gaining a `resolve`
  mode gated by `worker_merge_conflicts`; the `halt` path parking the unit
  under `## Awaiting input` with the conflicting paths; the `resolve` path
  committing the resolution and flagging it in the PR body; the worker
  profile and policy guard admitting a merge only when the current branch
  is the session's unit branch and the source is the PR base; tests for
  both modes and for a refused off-branch merge.
- **Done when:** a fixture conflict under `halt` leaves a clean tree and a
  parking bullet; under `resolve` it leaves a resolution commit and a PR
  body flag; a merge attempted from a non-unit branch is denied.
- **Dependencies:** 4, 6
- **Citations:** D-7 · REQ-E1.1, REQ-E1.2, REQ-E1.3
- **Estimated effort:** 1 day

### Task 11 — Rewrite paths through the tower

- **Deliverables:** the tower's operator-requested force-push path: a
  confirmation conforming to `check-confirmation.sh` naming the remote
  commits the push drops, refused for main, protected, and spec branches,
  refused from standing decisions, and run only in the turn it was asked;
  the commit-range lint failure named in the reporting skill's handoff as
  the reason for that path; the secret-purge preparation (command plus
  rotation checklist) with the run left to the human; tests over the tower
  queue for the refusal arms and the confirmation shape.
- **Done when:** a standing decision covering a force-push is refused; a
  same-turn request produces the confirmation and the push only after a
  yes; the purge helper prints and never executes.
- **Dependencies:** 6
- **Citations:** D-8 · REQ-F1.2, REQ-F1.3, REQ-F1.4
- **Estimated effort:** 1 day

### Task 12 — The prose sweep and the purge list

- **Deliverables:** every skill invariant section split by rule kind and
  citing `doctrine/human-gates.md`, word-neutral or better; the README,
  `docs/fleet.md`, `docs/getting-started.md`, `docs/per-tower-checkouts.md`,
  `docs/CONTRIBUTING.md`, `docs/options-reference.md`, and the
  `config/defaults.yml` comments agreeing with the doctrine; the retired
  phrasings added to the purged-identifier list; the release note naming
  the `ready_flip_policy` default as a behaviour change; the dotfiles
  restatement named in the handoff as out-of-repo follow-up.
- **Done when:** `check:purged-identifiers` refuses a reintroduced retired
  phrase in a fixture; `check-instructions.sh` reports no surface over
  budget; `mise run check` passes.
- **Dependencies:** 1, 3, 7, 9, 10, 11
- **Citations:** D-10 · REQ-A1.3, REQ-A1.5, REQ-D1.6, REQ-H1.1, REQ-H1.2
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

- **Lifecycle hooks as an operator seam** (issue planwright#383): a
  different decision domain; this bundle names no pipeline states.
- **The `pr-ready` attention record** (`specs/_pending/merge-currency-guard-amendment.md`):
  a fleet signal owned by the merge-currency-guard amendment.
- **Reconcile fan-out of a base sync after a merge** (obs:7db974ee stays
  unconsumed): orchestrator mechanics.
- **The ready-guard's predicate, parse cost, and MCP server naming**
  (obs:ec12d9b8, obs:f618a38c stay unconsumed): the guard stays as shipped.
