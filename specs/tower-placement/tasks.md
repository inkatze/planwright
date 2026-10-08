# Tower placement — Tasks

**Status:** Draft
**Last reviewed:** 2026-10-07
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order. Tasks 3 and 4 change guard code, hook wiring,
and the tower profile: each takes the security-zone hard pause, and its PR
presents the allow/deny delta for human sign-off. The tower-enforcement
flight's branch is prior art for both (D-12).

## Tasks

### Task 1 — Tower placement floor in the fleet doctrine

- **Deliverables:** a tower placement floor section in
  `doctrine/fleet-coordination-floor.md` stating that a tower runs in its
  own working tree and never moves a branch, switches, dirties, or writes
  the stash in a checkout it does not own; the doc's citation line and its
  `doctrine/README.md` row updated.
- **Done when:** the section exists and cites this bundle's REQ-A1.2;
  `mise run check` passes, the doctrine-index check included.
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.2
- **Estimated effort:** half day

### Task 2 — Placement classifier and the `tower_placement` knob

- **Deliverables:** a script that classifies the current checkout as a
  main tree or a linked worktree from git's own and common directories and
  prints the resolved `tower_placement` value beside the class; the knob in
  `config/defaults.yml` with `warn` as its default, resolved through
  `scripts/resolve-config-knob.sh` with the existing malformed-value
  policy; tests.
- **Done when:** tests cover a main tree, a linked worktree, a separate
  clone (classified as a main tree), a bare repository, a path outside any
  repository, and each knob value and a malformed one at each layer; the
  script takes no model input; `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-4, D-5 · REQ-A1.3, REQ-B1.1
- **Estimated effort:** 1 day

### Task 3 — Session marking and the plugin-wired deny-only floor

- **Deliverables:** a tower-session mark store under the fleet state
  directory with an atomic, idempotent activate verb; a plugin
  `UserPromptSubmit` hook that marks a session whose prompt opens with the
  `/tower` or `/orchestrate` command; plugin `PreToolUse` entries for Bash
  and the profile's GitHub tools that run `policy-guard.sh` at the tower
  tier in marked sessions and defer otherwise, each with an explicit
  timeout; policy-guard acts covering every entry already in the tower
  deny list, built on the shared option parser; the deny-to-act fixture
  and the check that fails on an unmapped entry; adversarial tests.
- **Done when:** tests show every existing tower deny entry refused in a
  marked session launched without the profile; an unmarked session
  unaffected and forking nothing before its prefilter decides; a
  self-marked ordinary session gaining no allow; a missing, corrupt,
  unsearchable, or tampered store denying; an oversized payload, a signal
  before the verdict, and a nested `session_id` in tool input each
  denying or reading the top-level id; a mark tag outside the prompt's
  start not marking; `tower-command-guard.sh` absent from the plugin
  hooks; the map check failing on a deliberately unmapped entry; each test
  file within the per-file time ceiling; `mise run check` passes under
  umask 022; the PR body carries the deny-to-act map and what stays
  untested.
- **Dependencies:** none
- **Citations:** D-7, D-8, D-9, D-12 · REQ-C1.1, REQ-C1.2, REQ-C1.3,
  REQ-C1.4, REQ-C1.5, REQ-C1.6, REQ-C1.7, REQ-D1.3, REQ-D1.4, REQ-G1.1,
  REQ-G1.4
- **Estimated effort:** 3 days

### Task 4 — Deny-floor tightening

- **Deliverables:** tower profile deny entries and policy-guard tower acts
  for every branch-moving and stash-writing command per D-10, refused in
  their global-option, long-prefix, ref-form, and repo-alias spellings;
  fixture rows for each new entry; the profile's `_about` corrected to say
  the guards receive the command as written.
- **Done when:** tests show each new act refused in a marked session and
  under the profile launch, in every spelling REQ-D1.2 names; read-only
  stash inspection still allowed; a new branch whose name contains a
  protected name not denied; the deny list before this task a subset of
  the list after it; the map check passing; `mise run check` passes under
  umask 022; the PR body presents the allow/deny delta.
- **Dependencies:** 3
- **Citations:** D-9, D-10, D-12 · REQ-D1.1, REQ-D1.2, REQ-D1.4, REQ-D1.5,
  REQ-G1.4
- **Estimated effort:** 1.5 days

### Task 5 — Dispatch from a tower's own tree

- **Deliverables:** unit worktree placement resolved from the repository's
  primary worktree in the dispatch scripts; flight slot counting and brief
  retirement skipping the primary checkout; NUL-delimited worktree-list
  parsing; tests.
- **Done when:** tests dispatch from a tower in a linked worktree and find
  the unit worktree under the primary `.claude/worktrees/`; a flight
  branch checked out in the primary checkout does not count as a live
  flight or have its brief retired; a worktree path holding a newline
  cannot forge a list line; `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-11 · REQ-E1.1, REQ-E1.2
- **Estimated effort:** 1 day

### Task 6 — Bring-up wiring in `/tower` and `/orchestrate`

- **Deliverables:** each skill's bring-up runs the classifier and responds
  per `tower_placement`, runs the isolation probe and warns, re-marks the
  session, and treats plugin enforcement as meeting the floor while
  keeping the read-only fallback and naming every layer it read; both
  skills land word-neutral or within their budget.
- **Done when:** the skills' instructions carry each step; the routing eval
  fixtures and `check:instructions` pass; the PR body carries a checklist
  for the operator's manual runs of the test-spec's `[manual]` REQ-B
  entries.
- **Dependencies:** 2, 3
- **Citations:** D-4, D-6, D-8 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4,
  REQ-B1.5, REQ-C1.8
- **Estimated effort:** 1 day

### Task 7 — Docs

- **Deliverables:** the supported launch in `docs/fleet.md` (both forms and
  why never `--worktree`), the plugin-wired floor and its resume residual;
  `docs/per-tower-checkouts.md` reconciled (one tower in a linked worktree
  is supported; several towers want clones); `tower_placement` in
  `docs/options-reference.md`; a note in `docs/permission-matcher-model.md`
  that a deny-list edit needs a map row; the stale script headers and
  prose naming the profile as the only enforcement path corrected.
- **Done when:** each doc carries its section; no doc or header claims the
  floor loads only with the profile; `mise run check` passes, docs checks
  included.
- **Dependencies:** 1, 2, 4, 6
- **Citations:** D-3, D-4, D-8 · REQ-F1.1, REQ-F1.2, REQ-F1.3, REQ-F1.4,
  REQ-C1.8, REQ-G1.2, REQ-G1.3
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

- **Shell-feed and wrapper spellings at both guard tiers.** Commands fed
  through a shell or wrapper (`bash <<<`, `mise exec --`, `direnv exec`,
  git-core binaries by path, shell aliases, `gh alias`) pass the policy
  guard at the worker and tower tiers alike, and the deny globs miss them
  too. Fixing one tier would split the guard's model, so it is a follow-up
  for both. Confidence: high.
  **Gate:** GATE(when: task 4 completed).
  Citations: D-9 · the tower-enforcement flight review D2 (Sources).
- **Per-checkout versus per-repository orchestrator state.** A tower in its
  own tree cannot see dispatch records or backend failover state another
  checkout wrote; deciding per record which scope it has, and unifying the
  shared-state namespaces, belongs with the orchestrator's state model.
  Confidence: medium.
  **Gate:** GATE(when: task 7 completed).
  Citations: D-11 · obs:d9fa2e76, obs:af90eadf.

## Out of scope

- **The operator's tower launcher.** It lives outside this repository;
  the docs carry the recipe it follows. Citations: the tower-placement
  seed (Sources).
- **Worker isolation.** Workers keep their `--worktree` launch.
  Citations: REQ-G1.2.
- **Edit and Write deny for towers.** Not selected for this bundle.
  Citations: drafting-session decision (2026-10-07).
