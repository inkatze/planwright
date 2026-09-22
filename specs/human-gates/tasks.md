# Human gates — Tasks

**Status:** Ready
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
  owning skill; its row in the doctrine README index and the rows of every
  doctrine doc this task edits; a second scoped
  `Superseded-by: human-gates D-2` pointer line on bootstrap D-26 beneath its
  existing kickoff-lifecycle D-6 line, `Superseded-by` pointers on bootstrap
  REQ-J1.1 (replaced by REQ-D1.6) and REQ-J1.4 (both of its rules replaced:
  the rewrite prohibition by REQ-F1.1 and REQ-F1.2, the all-drafts rule by
  REQ-C1.1), one dated bootstrap changelog entry naming every pointer, and
  no body edit on any of them; `doctrine/gate-wiring.md` rewritten so the
  approval act is the merge or the `on-approval` act, never the flip, with
  the one-line legacy-marker mapping and the rejected-trailer rule; every
  other doctrine doc that states the flip as the review gate, an
  unconditional never, or the all-drafts rule rewritten to cite the policy
  (at drafting: `finding-categorization.md`, `autonomous-safe-decision.md`,
  `orchestration-modes.md`, `context-budget-autoheal.md`,
  `flight-rules.md`; the Done-when grep is the enumeration); the
  doctrine-index and doc-link checks green.
- **Done when:** the doc exists and every rule in it carries a kind; every
  bootstrap pointer the deliverable names resolves; a grep of `doctrine/`
  for the retired phrasings and for "review gate" finds only the mapping
  line and the human-gates doc; `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-1, D-2, D-3, D-10, D-13 · REQ-A1.1, REQ-A1.2, REQ-A1.3,
  REQ-A1.4, REQ-A1.5, REQ-B1.1, REQ-B1.9, REQ-D1.6
- **Estimated effort:** 1 day

### Task 2 — Sign-off trailer mechanics

- **Deliverables:** `scripts/planwright-commit-trailers.sh` (or a sibling)
  stamping `Planwright-Sign-Off: PS-<n>` with the id written once from the
  branch's next free id, and stamping `Planwright-Sign-Off-Rejected: PS-<n>`
  on a rejection commit; checklist regeneration reading trailers through
  `git log --format='%(trailers:key=Planwright-Sign-Off,valueonly)'` over
  `base..head`, dropping a reverted original by pairing git's
  `This reverts commit <sha>` body line to it and dropping an item a later
  rejected trailer names, and failing with a named error on a range it
  cannot resolve, never emitting an empty checklist; id allocation refusing
  over an unresolvable range; `scripts/check-commit-msgs.sh --marker
  subject` retired and `--marker title` broadened to reject the legacy
  bracket or a bare trailer line; `tests/test-check-commit-msgs.sh`
  updated; a regression test proving a revert of a trailered commit yields
  one item, not two; a gated deferral for dropping `--marker title` after
  one release.
- **Done when:** the revert test fails on the subject-grep path and passes
  on the trailer path; a rejected-trailer fixture drops exactly the named
  item; a base-merge that reorders the range leaves every checklist id
  unchanged; an unfetched base yields a named error and no checklist; the
  lint suite is green.
- **Dependencies:** 1
- **Citations:** D-3, D-12 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4,
  REQ-B1.6
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
- **Done when:** a CI grep fixture finds the approval statement, the
  apply-then-review statement, and the handoff SHA instruction in each
  gate-wired skill body; one recorded on-demand `eval:skill` run shows the
  attended path applying without asking; no skill body contains the retired
  subject suffix; `mise run check` (instruction budget included) passes.
- **Dependencies:** 2
- **Citations:** D-3, D-12, D-13 · REQ-B1.5, REQ-B1.6, REQ-B1.7, REQ-B1.8
- **Estimated effort:** 1 day

### Task 4 — The policy knobs

- **Deliverables:** `ready_flip_policy`, `ready_flip_ci_wait`,
  `merge_policy`, `merge_class_max_lines`, `merge_class_exclude_paths`,
  `merge_class_strategy`, `worker_base_merge`,
  `worker_merge_conflict_policy`, `unpushed_rewrite`, and
  `protected_branches` in `config/defaults.yml` with commented defaults;
  their rows in `docs/options-reference.md`; legal-value validation through
  `scripts/resolve-config-knob.sh` with the by-layer malformed policy and a
  per-knob strict degrade target for the adopter and machine-local layers
  (`human` for the flip and merge policies, `halt` for conflicts,
  `sole-allowed` for the strategy, `deny` for the base-merge and rewrite
  allowances, a class that admits nothing for a malformed bound, and a read
  failure that denies the act for the protected set), since the shared
  resolver's core-default degrade would otherwise land on the permissive
  value; the `BREAKING CHANGE:` footer naming the `ready_flip_policy`
  default on the commit that lands the knob; tests for each value and each
  malformed arm.
- **Done when:** each knob resolves through all four layers in a test; a
  malformed repo-tracked value exits non-zero and an adopter-layer one
  degrades to that knob's strict target with a warning, never to the shipped
  default; the footer is present on the knob commit; the options check and
  `check:test-time` pass.
- **Dependencies:** 1
- **Citations:** D-4, D-6, D-7, D-8, D-9 · REQ-C1.1, REQ-D1.1, REQ-D1.3,
  REQ-D1.8, REQ-E1.1, REQ-E1.2, REQ-F1.1, REQ-F1.5, REQ-H1.3
- **Estimated effort:** half day

### Task 5 — The shared reserved-control spelling fixtures

- **Deliverables:** `tests/fixtures/reserved-control-spellings`, one
  spelling per line with its act, tier, policy value, and expected verdict
  per copy (deny, defer, or outside that copy's jurisdiction; merge
  including `git pull` and every refspec form, the flip and its undo,
  force-push, amend, squash, fixup, rebase, protected-ref pushes against
  `main`, `master`, and a spec branch, the MCP names; floor lines deny from
  every copy in jurisdiction and from both profiles); one test driving the
  file through the tower queue's reserved-control check, the ready-guard,
  the worker and tower command guards, and both deny profiles, failing on
  any copy whose verdict differs from the line's; the `git pull` gap and
  the missing `master` and spec-branch globs closed in the profiles. Until
  Task 6 lands, every policy line's expected verdict is deny, since no
  policy value resolves yet.
- **Done when:** the test fails before the profile edit on `git pull` and on
  a `master` push and passes after; every line carries every column and the
  driver rejects a line missing one; every existing guard test stays green;
  `check:test-time` passes.
- **Dependencies:** none
- **Citations:** D-9 · REQ-F1.5, REQ-G1.1
- **Estimated effort:** 1 day

### Task 6 — The policy guard and the profile floor

- **Deliverables:** `scripts/policy-guard.sh`, a deny-emitting PreToolUse
  hook that classifies the intercepted command before any knob read, defers
  with no read outside its jurisdiction (an attended session with no tier
  profile included), reads only the knob the matched act needs through the
  shared resolver within a wall-clock bound, learns the tier from the
  session's settings profile, and refuses what the resolved value forbids
  for that tier (flip, base merge off the unit branch or from a source other
  than the PR base, never-pushed rewrite with the upstream refreshed before
  the containment read, `--undo` outside the corrective helper), exempting
  the merge helper's own flip, reading the protected set from the core floor
  plus `protected_branches` with `refs/heads/` stripped, denying on any
  read failure, and sourcing `scripts/echo-safety.sh`; its wiring in
  `hooks/hooks.json` and both settings profiles; the profiles reduced to
  the floor (main, `master`, protected and spec-branch mutation, the direct
  PR-merge spellings, force-push, the MCP names) with policy-permittable
  spellings removed for the tiers a value can grant them to;
  `docs/permission-matcher-model.md` and `tests/test-merge-currency-matrix.sh`
  updated for the profile change; an adversarial suite in the ready-guard's
  style; the wiring tests updated; the cross-copy test of Task 5 extended to
  drive the new guard too, and its fixture's verdict column rewritten from
  all-deny to the verdict each tier and value yields.
- **Done when:** each policy value produces the expected deny or defer per
  spelling in the suite; an unresolvable knob denies; a non-matching command
  produces no resolver call in the stubbed log; the never-pushed check
  refuses a commit any remote-tracking ref contains, a failed refresh, and a
  branch with no upstream; the hook-contract, wiring, and `check:test-time`
  checks pass.
- **Dependencies:** 4, 5
- **Citations:** D-8, D-9 · REQ-A1.2, REQ-C1.5, REQ-C1.8, REQ-D1.5,
  REQ-E1.1, REQ-E1.3, REQ-F1.1, REQ-F1.5, REQ-G1.1, REQ-G1.2, REQ-G1.3,
  REQ-G1.4, REQ-G1.5, REQ-G1.6
- **Estimated effort:** 2 days

### Task 7 — The ready-flip helper and its wiring

- **Deliverables:** `scripts/ready-flip.sh` reconciling and pushing the
  unit's Awaiting-input section first, then evaluating the preconditions on
  the resulting head (ready-guard defer, positive-green rollup within
  `ready_flip_ci_wait`, the review loop's handoff record naming that head
  with park and unpark commits excluded from the comparison and a head-SHA
  line added if it lacks one, no live Awaiting-input segment other than its
  own lead, read from the unit checkout and the fetched base ref), writing
  the PR record before flipping, appending a follow-up comment and parking
  when the flip call fails after the record, parking a failed precondition
  as a segment under `## Awaiting input` in one idempotent commit that
  composes with an existing bullet, skipping cleanly with no PR or no host
  CLI, retrying a transient host failure within the wait, and accepting a
  precondition result handed in by the merge helper so the CI wait runs
  once; `/execute-task` calling it after its draft PR exists, under
  `unit-owner`; the spec-PR knob documented as the same kind; tests over
  stubbed `gh` for every predicate, the record-write failure, and the
  flip-call failure.
- **Done when:** a fixture PR with one failing predicate stays draft and
  gains the parking segment; a passing one gains the record comment and the
  flip in that order; a composed bullet with a live `halt` segment still
  blocks; under `human`, `/execute-task`'s own step never calls the helper
  (the REQ-D1.4 helper's call is exempt); `check:test-time` passes.
- **Dependencies:** 4, 6
- **Citations:** D-4, D-5 · REQ-C1.2, REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.6
- **Estimated effort:** 1.5 days

### Task 8 — The reviewer-request side effect

- **Deliverables:** a recorded verification (docs plus a scratch-PR probe)
  of whether requesting a reviewer un-drafts a draft PR, appended to the
  kickoff brief's risk register; the fix the evidence selects in every
  planwright surface that requests a reviewer (verify-then-re-draft through
  a helper that is the sole sanctioned `--undo` spelling, or a transport
  without the side effect), a failed draft-state check treated as un-drafted
  and a failed corrective parking the unit; the helper allowlisted in the
  policy guard and pinned by the wiring tests; a test for the re-draft path
  and both failure arms.
- **Done when:** the risk-register entry names the sources consulted; a
  stubbed request that un-drafts is followed by a re-draft; a failing state
  check runs the corrective and a failing corrective parks; no other undo
  spelling is admitted by the guard suite; the wiring tests cover the
  helper.
- **Dependencies:** 6
- **Citations:** D-11 · REQ-C1.7, REQ-C1.8, REQ-G1.5
- **Estimated effort:** half day

### Task 9 — The merge policy

- **Deliverables:** `scripts/merge-class.sh` evaluating the class
  predicates deterministically (no trailer in range, no changed path in the
  core hard-disqualifier zone plus the adopter's exclusions, no live
  Awaiting-input segment other than a parking lead read from the fetched
  base ref, the Task 7 preconditions evaluated once, the adopter bounds)
  and emitting the evidence record; `scripts/merge-admitted.sh` flipping an
  admitted draft PR ready through the ready-flip helper with the
  precondition result handed forward, re-confirming head, base OID, and the
  Awaiting-input predicate immediately before the merge call, merging with
  the strategy `merge_class_strategy` resolves, writing every fall-through
  reason as a PR comment, appending a follow-up comment and parking when
  the merge call fails after the record, re-resolving the policy itself and
  failing closed, run in the worker tier by the skill owning the unit
  branch and allowlisted only under `policy-class` for an admitted PR;
  identity detection emitting the act name the docs' recommended split
  unlocks (auto-merge, or an approving review with it enabled);
  `on-approval` documented as enabling auto-merge; one Gherkin scenario per
  predicate in the fixtures; tests for each predicate, each fall-through,
  the moved head and moved base, and the record-write and merge-call
  failures.
- **Done when:** a PR carrying a sign-off trailer is never admitted under
  any bounds; a PR touching a core-zone path is never admitted; an admitted
  PR gets its record before the merge call and one CI wait in total; a base
  moved since evaluation yields no merge call; under `human` and
  `on-approval` the guard suite denies every PR-merge spelling;
  `check:test-time` passes.
- **Dependencies:** 4, 6, 7
- **Citations:** D-6, D-14 · REQ-A1.2, REQ-D1.1, REQ-D1.2, REQ-D1.3,
  REQ-D1.4, REQ-D1.5, REQ-D1.7, REQ-D1.8
- **Estimated effort:** 2 days

### Task 10 — Worker base merge and the conflict knob

- **Deliverables:** `scripts/converge-sync-main.sh` gaining a `resolve`
  mode gated by `worker_merge_conflict_policy` and honouring
  `worker_base_merge`; the `halt` path parking the unit under
  `## Awaiting input` with the conflicting paths; the dirty-tree,
  failed-fetch, and failed-merge exits parking the unit naming the failure
  class, and the failed-abort exit writing no park and naming hand repair;
  the `resolve` path committing the resolution with the sign-off trailer
  and flagging it in the PR body, its checklist recipe naming the `halt`
  re-run with the rejected trailer; the worker profile and policy guard
  admitting a merge only when the knob allows, the current branch is the
  session's unit branch, and the source is the PR base; tests for both
  modes, every exit arm, and a refused off-branch merge.
- **Done when:** a fixture conflict under `halt` leaves a clean tree and a
  parking bullet naming the paths; under `resolve` it leaves a resolution
  commit carrying the trailer, a PR body flag, and a checklist recipe naming
  the `halt` re-run; a failed abort leaves no park; a merge attempted from a
  non-unit branch or under `deny` is denied; `check:test-time` passes.
- **Dependencies:** 2, 4, 6
- **Citations:** D-3, D-7 · REQ-B1.2, REQ-B1.3, REQ-E1.1, REQ-E1.2,
  REQ-E1.3
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
  yes; the purge helper prints and never executes; a CI grep fixture finds
  the reword path named in the reporting skill's gate-failure handoff and
  one recorded on-demand `eval:skill` run shows it; `check:test-time`
  passes.
- **Dependencies:** 6
- **Citations:** D-8 · REQ-F1.2, REQ-F1.3, REQ-F1.4
- **Estimated effort:** 1 day

### Task 12 — The prose sweep and the purge list

- **Deliverables:** every skill invariant section split by rule kind and
  citing `doctrine/human-gates.md`, word-neutral or better; every doc and
  script header that restates the list or cites bootstrap REQ-J1.1 or
  REQ-J1.4 rewritten to agree with the doctrine (the README, `docs/`, and
  the `config/defaults.yml` comments among them; the Done-when grep is the
  enumeration); the short retired phrases added to the purged-identifier
  seed after a check that no frozen record carries them verbatim, and the
  dedicated grep screen for sentence-length phrasings over `doctrine/`,
  `skills/`, and `docs/` wired into `mise run check`; a check that the
  `BREAKING CHANGE:` footer of Task 4 is present in the merged history; the
  dotfiles restatement carried as the gated deferral below.
- **Done when:** the purge seed refuses a reintroduced short phrase in a
  fixture and the grep screen refuses a reintroduced sentence; a grep over
  `doctrine/`, `skills/`, `docs/`, and `scripts/` for the retired phrasings
  and the superseded bootstrap citations finds only the mapping line;
  `check-instructions.sh` reports no surface over budget; `mise run check`
  passes.
- **Dependencies:** 1, 3, 7, 9, 10, 11
- **Citations:** D-10 · REQ-A1.3, REQ-A1.5, REQ-D1.6, REQ-H1.1, REQ-H1.2,
  REQ-H1.3
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

- **Dotfiles `CLAUDE.md` restatement of the invariants.** The operator's
  dotfiles carry the old reserved-control list and must be re-derived from
  `doctrine/human-gates.md` once it lands; out of this repository, so no
  task here can ship it. Confidence: high.
  **Gate:** GATE(when: task 12 completed).
  Citations: D-10 · REQ-A1.3.

## Out of scope

- **Lifecycle hooks as an operator seam** (issue planwright#383): a
  different decision domain; this bundle names no pipeline states.
- **The `pr-ready` attention record** (`specs/_pending/merge-currency-guard-amendment.md`):
  a fleet signal owned by the merge-currency-guard amendment.
- **Reconcile fan-out of a base sync after a merge** (obs:7db974ee stays
  unconsumed): orchestrator mechanics.
- **The ready-guard's predicate, parse cost, and MCP server naming**
  (obs:ec12d9b8, obs:f618a38c stay unconsumed): the guard stays as shipped.
