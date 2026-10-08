# Tower placement — Requirements

**Status:** Draft
**Last reviewed:** 2026-10-07
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

A tower's job is working across worktrees: it creates task worktrees and
branches, removes landed flights, and reads the primary checkout. Today
towers run either in the primary checkout, where one slip switches or
dirties the `main` every other session reads, or under Claude Code's
`claude --worktree` isolation, which fences the session into its worktree
and refuses the cross-worktree commands a tower exists to run. And the
tower's deny floor holds only when the session was launched with the tower
settings profile, so a tower started any other way either runs with no
floor or goes read-only until relaunched.

This bundle gives every tower (the `/tower` front door and `/orchestrate`
towers, meta-towers included) a supported home and a floor that holds
however it was launched. A tower runs in its own working tree (a plain
`git worktree add` worktree or a separate clone) started without
`--worktree`. Bring-up checks the placement against a configurable policy.
The tower floor is enforced from the plugin's own hooks in every session
marked as a tower, through a deny-only path that marking can never widen.
The floor gains the commands that move a branch or write the shared stash.
The rule underneath, that a tower never moves, dirties, or stashes in a
checkout it does not own, lands as a fleet doctrine floor, with the knob,
the check, and the guard as its mechanisms (D-1).
*(Cites: D-1, D-2, the tower-placement seed (Sources).)*

## Scope

### In scope

- The supported tower launch: its own working tree, without `--worktree`,
  documented in the fleet docs and reconciled with the per-tower-checkouts
  guide.
- A tower placement floor in the fleet coordination doctrine.
- A deterministic placement classifier and the `tower_placement` knob
  resolved through the existing config layers.
- Bring-up wiring in `/tower` and `/orchestrate`: the placement check, an
  isolation warning, and a posture check that accepts plugin enforcement.
- Tower session marking and a plugin-wired, deny-only policy-guard floor
  for marked sessions, meeting the validated findings of the
  tower-enforcement flight's review.
- A deny-to-act coverage rule: every tower deny entry maps to a guard act,
  mechanically checked.
- Deny-floor tightening with branch-moving and stash-writing commands in
  every spelling the guard can parse.
- The two dispatch defects a tower in its own tree triggers: nested unit
  worktrees and the primary checkout counted as a live flight.

### Out of scope

- The operator's own tower launcher script, which lives outside this
  repository.
- Worker isolation: workers keep their `--worktree` launch.
- Running `tower-command-guard.sh` from the plugin's hooks: its auto-allows
  stay with the profile launch (D-7).
- A deny or ask on Edit and Write for tower sessions.
- Shell-feed and wrapper spellings at either guard tier (deferred; see
  `tasks.md`).
- Per-checkout versus per-repository orchestrator state, which a tower in
  its own tree can miss (deferred; see `tasks.md`).
- GitHub tools exposed by MCP servers other than the one the profile names.
- Any change to sign-off, merge, or the draft-to-ready flip.

## REQ-A — Placement

- **REQ-A1.1** Every tower, whichever skill runs it, SHALL be supported in
  its own working tree, either a linked worktree created with
  `git worktree add` or a separate clone, launched without Claude Code's
  `--worktree` session isolation.
  *(Cites: D-2, D-3, obs:55bb13a7.)*
- **REQ-A1.2** A tower SHALL NOT move a branch, switch, dirty, or write the
  shared stash in a checkout it does not own; the primary checkout's `main`
  is never touched by a tower. This rule SHALL be stated as a floor in the
  fleet coordination doctrine.
  *(Cites: D-1, the tower-placement seed (Sources), obs:8bc1198c.)*
- **REQ-A1.3** Placement policy SHALL be one knob, `tower_placement`, with
  the values `warn` (the default), `refuse`, and `allow`, resolved through
  the existing config layers like every other knob.
  *(Cites: D-4.)*

## REQ-B — Bring-up

- **REQ-B1.1** At bring-up, `/tower` and `/orchestrate` SHALL classify the
  checkout they run in as a checkout's main tree or a linked worktree, by a
  deterministic script with no model judgment in the decision.
  *(Cites: D-5.)*
- **REQ-B1.2** A tower in a main tree SHALL respond per `tower_placement`:
  `warn` says so once and continues; `refuse` takes no repo-mutating route
  and no relay until the tower is moved or the operator acknowledges, while
  questions and read-only work continue; `allow` says nothing. A linked
  worktree passes under every value.
  *(Cites: D-4, D-5.)*
- **REQ-B1.3** A tower running under Claude Code worktree isolation SHALL
  warn once at bring-up, naming the supported launch; the warning SHALL
  never block the tower.
  *(Cites: D-6, obs:55bb13a7.)*
- **REQ-B1.4** The bring-up posture check SHALL accept plugin enforcement
  active for the session as meeting the floor, SHALL keep its read-only
  fallback when that enforcement is missing or broken, and SHALL name every
  settings layer it read.
  *(Cites: D-8, obs:48faa6b7, the tower-enforcement flight (Sources).)*
- **REQ-B1.5** Every bring-up placement and posture read SHALL be
  heartbeat-class: read once at bring-up and again on request, never
  polled.
  *(Cites: drafting-session decision (2026-10-07).)*

## REQ-C — Plugin-wired enforcement

- **REQ-C1.1** In a session marked as a tower, the plugin's own PreToolUse
  hooks SHALL run the policy guard at the tower tier for Bash and for the
  GitHub tools the profile names, whatever settings the session was
  launched with.
  *(Cites: D-7, the tower-enforcement flight (Sources).)*
- **REQ-C1.2** Marking a session SHALL never widen any session's
  permissions: the plugin path only denies or defers, and no auto-allow is
  granted on the strength of a mark.
  *(Cites: D-7, the tower-enforcement flight review F1 (Sources).)*
- **REQ-C1.3** A session SHALL be marked by a plugin hook when its prompt
  opens with the `/tower` or `/orchestrate` command, and again by each
  skill's bring-up; a command tag matched anywhere other than the prompt's
  start SHALL NOT mark.
  *(Cites: D-8, the tower-enforcement flight review F11 (Sources).)*
- **REQ-C1.4** Enforcement SHALL fail closed in a marked session or one
  whose mark cannot be read: a store that exists but cannot be searched
  counts as marked; an oversized or unreadable payload denies; a signal or
  crash before a verdict denies; and any command that names the mark store
  is refused.
  *(Cites: D-8, the tower-enforcement flight review F2, F7, F8 (Sources).)*
- **REQ-C1.5** The session id SHALL be read from the payload's top level
  only, and every plugin hook entry SHALL carry an explicit timeout below
  the harness default.
  *(Cites: D-8, the tower-enforcement flight review F9, F12 (Sources).)*
- **REQ-C1.6** An unmarked session SHALL be unaffected, and its path
  through the hook SHALL be a cheap in-shell prefilter before any process
  is forked.
  *(Cites: D-8, the tower-enforcement flight review F13 (Sources).)*
- **REQ-C1.7** The profile launch (`--settings` with the tower profile)
  SHALL keep working as an additional layer, its command guard included.
  *(Cites: D-7.)*
- **REQ-C1.8** A tower resumed or forked under a different fleet home or
  session id SHALL be re-marked by its bring-up, and the residual window
  before bring-up SHALL be stated in the docs as bounded-or-surfaced.
  *(Cites: D-8, the tower-enforcement flight review F10 (Sources).)*

## REQ-D — The deny floor

- **REQ-D1.1** The tower floor SHALL deny every command that changes which
  commit a branch or a checkout's HEAD names (checkout, switch, reset in
  any mode, branch force and rename forms, `symbolic-ref` writes, fetches
  into a local branch) and every command that writes the shared stash, in
  every checkout including the tower's own, since the guard cannot prove
  which checkout a command reaches; a tower that needs a new branch
  creates it with a new worktree. A read-only stash command SHALL stay
  allowed.
  *(Cites: D-10, the tower-placement seed (Sources), the
  tower-enforcement flight review D1 (Sources).)*
- **REQ-D1.2** Each tower deny act SHALL be refused by the policy guard in
  every spelling git accepts that the guard's option parser can read:
  global options (`-C`, `-c`, `--git-dir`, `--work-tree`), unambiguous long
  option prefixes, `refs/`, `heads/`, and `remotes/` ref forms, and repo
  aliases expanding to the act.
  *(Cites: D-9, D-10, obs:5d886bf9, the tower-enforcement flight review
  F3, F4, F6, F14 (Sources).)*
- **REQ-D1.3** Every entry in the tower profile's deny list SHALL map to a
  policy-guard act, and a check SHALL fail when an entry has no act; no
  hook SHALL interpret permission globs.
  *(Cites: D-9.)*
- **REQ-D1.4** The change SHALL be tightening only: nothing the tower floor
  denies before this bundle SHALL become allowed in any session, and a
  branch or path that merely contains a protected name (a new branch
  `docs/main`) SHALL NOT be denied for that reason.
  *(Cites: D-7, D-10, the tower-enforcement flight review F5 (Sources).)*
- **REQ-D1.5** The tower profile's `_about` text SHALL describe the guards
  as receiving the command as written, unexpanded.
  *(Cites: obs:b159857e.)*

## REQ-E — Dispatch from a tower's own tree

- **REQ-E1.1** Unit worktrees dispatched from a tower in a linked worktree
  SHALL be placed under the repository's primary `.claude/worktrees/`,
  never nested under the tower's own worktree.
  *(Cites: D-11, obs:6688f319.)*
- **REQ-E1.2** Flight dispatch slot counting and brief retirement SHALL
  exclude the primary checkout, and worktree lists SHALL be parsed
  NUL-delimited.
  *(Cites: D-11, obs:cc66393d.)*

## REQ-F — Docs

- **REQ-F1.1** The supported tower launch SHALL be documented with both
  forms (a plain linked worktree and a separate clone) and the reason a
  tower is never launched with `--worktree`.
  *(Cites: D-3, obs:55bb13a7.)*
- **REQ-F1.2** The per-tower-checkouts guide SHALL say that one tower in a
  linked worktree is a supported home, and that several towers still want
  separate clones because linked worktrees share one `main` ref.
  *(Cites: D-3, concurrent-orchestrator-coordination (Sources).)*
- **REQ-F1.3** `tower_placement` SHALL be documented in the options
  reference, including the `allow` value as a dedicated clone's
  declaration.
  *(Cites: D-4.)*
- **REQ-F1.4** Every doc and script header the plugin-wired floor makes
  stale SHALL be corrected to name both enforcement paths.
  *(Cites: the tower-enforcement flight review F15 (Sources).)*

## REQ-G — Invariants

- **REQ-G1.1** Merge and the draft-to-ready flip stay reserved; nothing in
  this bundle SHALL let a tower perform either.
  *(Cites: tower-front-door REQ-G1.1, REQ-G1.4 (Sources).)*
- **REQ-G1.2** Worker launch and isolation SHALL be unchanged.
  *(Cites: the tower-placement seed (Sources).)*
- **REQ-G1.3** All work SHALL land as new commits; no history rewrite.
  *(Cites: tower-front-door REQ-G1.3 (Sources).)*
- **REQ-G1.4** Changes to guard code, hook wiring, and the tower profile
  are security-sensitive: their tasks SHALL take the hard pause, and the
  allow/deny delta SHALL be presented for human sign-off at PR review.
  *(Cites: D-7, the tower-placement seed (Sources).)*

## Changelog

- 2026-10-07 — Initial draft. Seeded as an extension of tower-front-door;
  fold-detection and the operator chose a new bundle covering every tower
  kind. Mid-draft, the operator folded the tower-enforcement flight in as
  scope (plugin-wired floor, session marking, the deny-to-act map) after
  its review stopped on validated guard findings.

## Sources

- **The tower-placement seed** (2026-10-07, drafting invocation): towers in
  their own working tree, enforced and configurable, never under
  `--worktree`; the two 2026-10-03 incidents (a flights tower handing
  worktree removal to the operator; a meta-tower launching a subordinate
  tower in the primary checkout); the deny-floor tightening;
  security-sensitive; launcher and worker isolation out of scope.
- **Pinned altitude seed claim** (per the autopilot-reflex seed-claim
  trigger): "the primary checkout's `main` never dirtied or switched by a
  tower", an invariant, resolved as a doctrine floor by D-1.
- **The tower-enforcement flight** (branch
  `planwright/flight/tower-enforcement-from-plugin-736c2209`, three commits
  on `6cbcbbc5`, never merged): the ask (enforce the tower floor from the
  plugin however the tower is launched), its prior-art implementation
  (`scripts/tower-session.sh`, the policy-guard tower acts, the deny-to-act
  fixture), and its review record, findings F1 to F17 and declined log D1
  to D5, held at the security-zone hard pause. Folded in by the operator
  (2026-10-07) as prior art, not as code to merge.
- **tower-front-door** (`specs/tower-front-door/`): the tower permission
  posture (its REQ-A1.3, D-14), the hard invariants (its REQ-G group), and
  its bring-up posture check.
- **concurrent-orchestrator-coordination**
  (`specs/concurrent-orchestrator-coordination/`) and
  `docs/per-tower-checkouts.md`: the per-tower checkout model.
- **Research: Claude Code documentation** (consulted 2026-10-07, CLI
  2.1.293): `code.claude.com/docs/en/worktrees.md` (isolation applies after
  `--worktree`, `EnterWorktree`, and resume, and cannot be turned off; no
  worktree signal), `hooks.md` (hook input fields; hooks inherit the
  launcher's environment), `env-vars.md`, `permissions.md` (deny globs are
  matched per subcommand and do not match `git -C` or `-c` spellings),
  `plugins-reference.md` (plugin hooks share the settings hook shape,
  `timeout` included).
- **obs:55bb13a7** — a `--worktree` tower has `git -C`, worktree removal,
  `$(...)` arguments, and tmux formats refused.
- **obs:48faa6b7** — the bring-up posture check cannot see the `--settings`
  layer and fails closed falsely.
- **obs:5d886bf9** — the tower profile lacks the `git` global-option
  spellings (cited, not consumed: its other open vectors stay live).
- **obs:b159857e** — the tower profile's `_about` says commands arrive
  expanded.
- **obs:6688f319** — dispatch from a tower worktree nests unit worktrees.
- **obs:cc66393d** — flight dispatch counts the primary checkout as a live
  flight, and parses worktree lists without NUL delimiting.
- **obs:d9fa2e76**, **obs:af90eadf** — per-checkout markers and records a
  tower in another tree cannot see (deferred; cited, not consumed).
- **obs:8bc1198c** — a tower commit on `main` strands; the reason towers
  run in their own tree (cited, not consumed).
- **obs:ada69b21**, **obs:4e6c5a33** — worktree isolation refuses
  `fish -c` and nested worktree creation (cited, not consumed).
- **obs:a19fc34c**, **obs:7ad46e46**, and the legacy observations log line
  68 — the sanctioned `git worktree add` exceptions to native worktree
  creation (cited, not consumed).
- **The legacy observations log line 74** — dispatch commits on a local
  `main` rode into a task PR (cited, not consumed).
- **The legacy observations log line 33** — machine-local config reaches
  worktrees inside the repository but not a separate clone (cited, not
  consumed).
- **obs:3055e69a**, **obs:04b578da** — a stale tower checkout misderives
  the release version (cited, not consumed).
