# Tower placement — Tasks

**Status:** Ready
**Last reviewed:** 2026-10-08
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order. Tasks 8, 3, and 4 change guard code, hook
wiring, and the tower profile: each takes the security-zone hard pause, and
its PR presents the allow/deny delta for human sign-off. The tower-enforcement
flight's branch is prior art for Tasks 3 and 4 (D-12).

## Tasks

### Task 8 — Tower profile hooks that run under `--settings`

- **Deliverables:** every hook command in
  `config/tower-settings.json` rewritten to the quoted, unbraced
  `"$CLAUDE_PLUGIN_ROOT"/scripts/…` spelling, each policy-guard command
  suffixed, in POSIX shell, so a non-zero exit prints on stderr a reason
  naming the guard and the remedy and exits 2 (D-16); the static half of
  `tests/test-settings-fragment-hook-expansion.sh` widened to every hook
  command under every event in every `config/*.json` carrying a `hooks`
  key, per REQ-C1.11's per-occurrence rule, reading the profiles from a
  directory the test can point at fixtures, its header naming both
  profiles; `tests/test-tower-settings-hook-wiring.sh` re-pinned to both
  guards' new full commands, keeping its tier-word assertion;
  `scripts/check-hook-contracts.sh` and its test taught the suffixed
  command shape (its command-exists and silence checks still run against
  the guard script); the tier-argument parsing in
  `tests/test-reserved-control-spellings.sh` taught the same shape; an
  execution test that runs each tower hook command with `sh -c` and a
  payload shaped for its matcher; the profile's `_about` corrected per
  REQ-D1.6 and a test asserting it; the tower-profile paragraph of
  `docs/fleet.md` carrying REQ-F1.6's statements.
- **Done when:** the widened check passes on the shipped profiles and
  fails on fixture profiles carrying the braced token in a later hook of
  the same group, in a later matcher group, and under another event, an
  unquoted root, and `${CLAUDE_PLUGIN_ROOT:-}`, and passes a fixture with
  a compliant suffixed command; with the root exported, the execution test
  shows the command guard emitting its allow on a tmux read and each policy
  hook emitting the guard's own deny on a reserved act shaped for its
  matcher; with the root unset, empty, pointing at a directory without the
  guard, or at a guard that is not executable, both policy hooks exit 2
  with the reason on stderr and the command guard's hook exits neither 0
  nor 2; the `_about` test asserts REQ-D1.6's statements, the "why it
  differs" included, and the absence of the dropped claims;
  `config/worker-settings.json` unchanged; the tower-tier and worker-tier
  expectations of the policy-guard and reserved-control suites unchanged;
  each test file within `config/test-time-budget.yml`'s per-file ceiling
  as measured on CI, and the suite total within budget or the budget
  raised deliberately in the PR; `mise run check` passes under umask 022;
  the PR body carries an operator checklist, run before the ready flip,
  of one manual launch through the supported launcher (a tmux read
  auto-approved with no other settings layer allowing it, and
  `git -C . merge`, which no deny rule matches, refused with the policy
  guard's own reason) and of the opt-in live CLI probe, a skip stated as
  a skip; the PR body presents the allow/deny delta for the security-zone
  sign-off, the command guard's allow set newly live in profile-launched
  towers and the exported root as the trust root for its script allows
  included; its commits carry the breaking-change marker, whose footer
  names the newly live allows and denials in a profile-launched tower and
  that a launch whose policy guard does not run now refuses Bash.
- **Dependencies:** none
- **Citations:** D-13, D-14, D-15, D-16 · REQ-C1.10, REQ-C1.11,
  REQ-C1.12, REQ-C1.13, REQ-D1.6, REQ-F1.6, REQ-G1.2, REQ-G1.4
- **Estimated effort:** 1 day

### Task 1 — Tower placement floor in the fleet doctrine

- **Deliverables:** a tower placement floor section in
  `doctrine/fleet-coordination-floor.md` stating that a tower runs in its
  own working tree and never moves a branch, switches, dirties, or writes
  the stash in a checkout it does not own, naming the sanctioned-script
  exceptions REQ-A1.2 lists; the doc's opening floor count, its citation
  line, and its `doctrine/README.md` row updated.
- **Done when:** the section exists, names each sanctioned-script
  exception, and cites this bundle's REQ-A1.2 (verified at PR review);
  `mise run check` passes, the doctrine-index check included.
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.2
- **Estimated effort:** half day

### Task 2 — Placement classifier and the `tower_placement` knob

- **Deliverables:** a script that classifies the current checkout from
  git's own and common directories and prints one of `main`, `linked`, or
  `none` (a bare repository or no repository) beside the resolved
  `tower_placement` value, exiting 0 in every case; the knob in
  `config/defaults.yml` with `warn` as its default, resolved through
  `scripts/resolve-config-knob.sh` with the existing malformed-value
  policy; the knob's row in `docs/options-reference.md`; tests.
- **Done when:** tests cover a main tree (`main`), a linked worktree
  (`linked`), a separate clone (`main`), a bare repository and a path
  outside any repository (`none`), and each knob value and a malformed one
  at each layer; the script's output depends only on git's directory
  queries and the knob resolver; `mise run check` passes, `check:options`
  included.
- **Dependencies:** none
- **Citations:** D-1, D-4, D-5 · REQ-A1.3, REQ-B1.1, REQ-F1.3
- **Estimated effort:** 1 day

### Task 3 — Session marking and the plugin-wired deny-only floor

- **Deliverables:** a tower-session mark store in the fleet home, distinct
  from the existing tower marker, written only by hook processes,
  atomically, under the sibling stores' bar (owner-only, no symlinks,
  UUID-validated ids, rename-based refresh, link-safe pruning), its
  fleet-home resolution shared with `scripts/fleet-state.sh` or
  parity-tested against it; the activation handshake (a fixed command the
  PreToolUse hook intercepts, marks, and refuses with a constant "active"
  message); a plugin `UserPromptSubmit` hook that marks a session whose
  prompt opens with the `/tower` or `/orchestrate` command, bare or
  plugin-namespaced; plugin `PreToolUse` entries for Bash and for every
  GitHub MCP tool in the tower profile's deny list (including
  `mcp__github__update_pull_request_branch`, added to the profile here)
  that run `policy-guard.sh` at the tower tier in marked sessions and
  defer otherwise, each with an explicit timeout; age-based pruning on
  every mark write; policy-guard acts covering every entry already in the
  tower deny list, in every spelling REQ-D1.2 names, built on the shared
  option parser; a test-only pause point after the session is found
  marked; the deny-to-act fixture and the check that fails on an unmapped
  entry; adversarial tests.
- **Done when:** tests show every existing tower deny entry refused in a
  marked session launched without the profile, in every spelling REQ-D1.2
  names; an unmarked session unaffected, with no external command running
  before its prefilter decides and a static check that the prefilter holds
  no command substitution, pipeline, or subshell; a self-marked ordinary
  session gaining no allow; a leading bare or plugin-namespaced `/tower`
  or `/orchestrate` marking and a command tag later in the prompt not
  marking; in a marked session, a corrupt or tampered mark and an
  unsearchable store denying; a missing store and an unreadable id
  deferring; an oversized payload in a marked session denying; SIGTERM,
  SIGINT, and SIGHUP delivered at the pause point denying; a nested
  `session_id` in tool input reading the top-level id; a command naming
  the store refused; each added hook entry's timeout longer than the
  guard's whole-call deadline plus margin and below the harness default
  (600 seconds, per the flight review's F12); `tower-command-guard.sh`
  absent from the plugin hooks; the map check failing on a deliberately
  unmapped entry; a mark older than the pruning age removed by a mark
  write and a refreshed one kept; the handshake refused with the "active"
  message in a wired session and its command body never running there;
  the worker-tier expectations of the policy-guard and reserved-control
  suites unchanged; Task 8's execution test still passing; each test
  file within `config/test-time-budget.yml`'s
  per-file ceiling as measured on CI, and the suite total within budget or
  the budget raised deliberately in the PR; `mise run check` passes under
  umask 022; the PR body carries the deny-to-act map and what stays
  untested; its commits carry the breaking-change marker and the changelog
  states the new tower-session denials.
- **Dependencies:** 8
- **Citations:** D-1, D-7, D-8, D-9, D-12 · REQ-C1.1, REQ-C1.2, REQ-C1.3,
  REQ-C1.4, REQ-C1.5, REQ-C1.6, REQ-C1.13, REQ-C1.9, REQ-D1.2, REQ-D1.3,
  REQ-D1.4, REQ-G1.1, REQ-G1.2, REQ-G1.4
- **Estimated effort:** 3 days

### Task 4 — Deny-floor tightening

- **Deliverables:** tower profile deny entries and policy-guard tower acts
  for every act REQ-D1.1 lists, refused in their global-option,
  long-prefix, ref-form, and repo-alias spellings (repo aliases being
  `alias.*` in repository-local config); fixture rows for each new entry,
  the fixture's spelling rows being the spelling set that counts; a
  committed fixture freezing the deny list as of this bundle's base; the
  profile's `_about` corrected to say the guards receive the command as
  written, and its other statements this bundle falsifies (tower scoping
  only by hook wiring, the tower committing via git) corrected.
- **Done when:** tests show each new act refused in a marked session and
  under the profile launch, in every spelling REQ-D1.2 names, against the
  tower's own checkout too; `stash list`, `stash show`, a plain commit,
  plain branch creation and deletion, `git worktree add <path> -b
  docs/main`, and `git push origin docs/main` still allowed; the frozen
  pre-bundle deny list a subset of the shipped one; a test asserting
  `_about` no longer says the command arrives expanded and says it arrives
  as written; the hook-wiring suite passing with only its pinned `_about`
  phrases updated; the worker-tier expectations of the policy-guard and
  reserved-control suites unchanged; the map check passing; `mise run
  check` passes under umask 022; the PR body presents the allow/deny
  delta; its commits carry the breaking-change marker.
- **Dependencies:** 3
- **Citations:** D-1, D-9, D-10, D-12 · REQ-D1.1, REQ-D1.2, REQ-D1.4,
  REQ-D1.5, REQ-G1.2, REQ-G1.4
- **Estimated effort:** 1.5 days

### Task 5 — Dispatch from a tower's own tree

- **Deliverables:** a regression test pinning unit worktree placement
  from a tower in a linked worktree (the dispatch scripts already resolve
  the primary checkout); flight slot counting and brief retirement
  skipping the primary checkout; NUL-delimited worktree-list parsing;
  tests.
- **Done when:** tests dispatch from a tower in a linked worktree and find
  the unit worktree under the primary `.claude/worktrees/`; a flight
  branch checked out in the primary checkout does not count as a live
  flight or have its brief retired; a worktree path holding a newline
  cannot forge a list line; the worker launch path unchanged;
  `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-11 · REQ-E1.1, REQ-E1.2, REQ-G1.2
- **Estimated effort:** 1 day

### Task 6 — Bring-up wiring in `/tower` and `/orchestrate`

- **Deliverables:** each skill's bring-up runs the classifier and responds
  per `tower_placement` (treating `none` as a main tree), runs the
  isolation probe and warns, re-marks the session through the activation
  handshake (bring-up and each on-request posture check), and treats
  plugin enforcement as meeting the floor while keeping the fallback
  (`/tower` read-only, `/orchestrate` holding dispatch, relay, and the
  bookkeeping push and PR, unattended parking in Awaiting input; a
  bring-up and posture check `/orchestrate` gains here, once per
  invocation) and naming every layer it read, the plugin hooks file
  included; both skills land word-neutral.
- **Done when:** `tests/test-tower-skill.sh` and a matching structural
  test over `skills/orchestrate/SKILL.md` find each bring-up step (the
  classifier call, the isolation probe, the handshake, the per-skill
  fallback, the layer naming); `check:instructions` passes; the PR body
  carries a checklist for the operator's manual runs of every `[manual]`
  entry in the test-spec, run with the plugin loaded from the PR branch's
  checkout, and states which have run.
- **Dependencies:** 2, 3
- **Citations:** D-1, D-4, D-6, D-8 · REQ-A1.1, REQ-B1.1, REQ-B1.2,
  REQ-B1.3, REQ-B1.4, REQ-B1.5, REQ-C1.8, REQ-C1.9
- **Estimated effort:** 1 day

### Task 7 — Docs

- **Deliverables:** in `docs/fleet.md`, the supported launch (both forms
  and why never `--worktree`), the plugin-wired floor and its resume
  residual, the upgrade note to restart running towers, and recovery from
  a misfiring floor (the act from a plain session, then a plugin
  downgrade or fix release; there is no off switch);
  `docs/per-tower-checkouts.md` reconciled (one tower in a linked worktree
  is supported; several towers want clones; its currency table no longer
  shows commands the floor denies; worker worktrees branch from
  `origin/main`); the prose explaining `allow` in the options-reference
  row Task 2 adds; a note in `docs/permission-matcher-model.md` that a
  deny-list edit needs a map row; the stale script headers and prose the
  flight review's F15 named corrected to name both enforcement paths.
- **Done when:** each doc carries its section; a search for the phrasing
  that the floor loads only with the profile finds nothing in the files
  F15 named; `mise run check` passes, docs checks included.
- **Dependencies:** 1, 2, 4, 6
- **Citations:** D-3, D-4, D-8 · REQ-A1.1, REQ-F1.1, REQ-F1.2, REQ-F1.3,
  REQ-F1.4, REQ-F1.5, REQ-C1.8, REQ-G1.2, REQ-G1.3
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
- **Operator launcher and overlay adopt the supported launch.** Outside
  this repository: the operator's tower launcher follows the documented
  recipe (own working tree, never `--worktree`, `CLAUDE_PLUGIN_ROOT`
  exported when passing the profile), running profile-launched towers are
  relaunched once Task 8 releases, the operator's overlay
  sets `tower_placement: refuse`, and any dedicated tower clone sets
  `allow` in its machine-local layer. Confidence: high.
  **Gate:** GATE(when: task 7 completed).
  Citations: D-1, D-4, D-14 · REQ-F1.6 · the tower-placement seed (Sources).

- **Worker profile's policy hooks on an unresolved root.** The worker
  profile's policy-guard hooks share the tower's exposure: with
  `CLAUDE_PLUGIN_ROOT` unset they exit 127 and the call proceeds. The
  dispatch wrapper exports the root, and REQ-G1.2 keeps workers unchanged
  here, so the D-16 suffix for the worker profile is a follow-up.
  Confidence: high.
  **Gate:** GATE(when: task 8 completed).
  Citations: D-16 · REQ-G1.2 · obs:aed5517e.

## Out of scope

- **The operator's tower launcher.** It lives outside this repository;
  the docs carry the recipe it follows. Citations: the tower-placement
  seed (Sources).
- **Worker isolation.** Workers keep their `--worktree` launch.
  Citations: REQ-G1.2.
- **Edit and Write deny for towers.** Not selected for this bundle.
  Citations: drafting-session decision (2026-10-07).
