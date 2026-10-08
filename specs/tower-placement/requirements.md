# Tower placement — Requirements

**Status:** Ready
**Last reviewed:** 2026-10-08
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
with the knob and its bring-up check as the capability and the plugin
floor and the wider deny list as its mechanisms (D-1). In this bundle,
"tower" means a `/tower` session or an `/orchestrate` orchestrator alike;
"deny floor" is the guard-enforced deny set and "placement floor" the
doctrine rule.
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
  is never touched by a tower. The exception is a planwright script
  performing an act the operator has sanctioned for towers (fast-forwarding
  the primary checkout's `main` for a release, starting a forward-merge in
  a worker's worktree for the worker to resolve); the floor SHALL name each
  sanctioned act. This rule SHALL be stated as a floor in the fleet
  coordination doctrine.
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
  questions and read-only work continue; `allow` says nothing. For
  `/orchestrate`, `refuse` holds every outward act on the same terms
  (dispatch, relay, and the bookkeeping push and PR) while status and
  read-only reconcile continue; its bring-up runs once per invocation
  (`--watch` steps do not repeat it), and an unattended orchestrator, which
  no operator can acknowledge, notifies and parks in Awaiting input. A
  linked worktree passes under every value.
  *(Cites: D-2, D-4, D-5.)*
- **REQ-B1.3** A tower running under Claude Code worktree isolation SHALL
  warn once at bring-up, naming the supported launch; the warning SHALL
  never block the tower.
  *(Cites: D-6, obs:55bb13a7.)*
- **REQ-B1.4** The bring-up posture check, in `/tower` and in
  `/orchestrate` alike, SHALL accept plugin enforcement active for the
  session as meeting the floor, judging it active only when the hook
  refuses the activation handshake with its "active" message, SHALL fall
  back when that enforcement is
  missing or broken (`/tower` to read-only, `/orchestrate` to holding its
  outward acts), and SHALL name every settings layer it read.
  *(Cites: D-2, D-8, obs:48faa6b7, the tower-enforcement flight (Sources).)*
- **REQ-B1.5** Every bring-up placement and posture read SHALL be
  read once at bring-up and again on request, never polled, each read
  bounded and inline.
  *(Cites: drafting-session decision (2026-10-07) (Sources).)*

## REQ-C — Plugin-wired enforcement

- **REQ-C1.1** In a session marked as a tower, the plugin's own PreToolUse
  hooks SHALL run the policy guard at the tower tier for Bash and for
  every GitHub MCP tool in the tower profile's deny list, which gains
  `mcp__github__update_pull_request_branch`, whatever settings the session
  was launched with.
  *(Cites: D-7, the tower-enforcement flight (Sources).)*
- **REQ-C1.2** Marking a session SHALL never widen any session's
  permissions: the plugin path only denies or defers, and no auto-allow is
  granted on the strength of a mark.
  *(Cites: D-7, the tower-enforcement flight review F1 (Sources).)*
- **REQ-C1.3** A session SHALL be marked by a plugin hook when its prompt
  opens with the `/tower` or `/orchestrate` command (bare or
  plugin-namespaced, such as `/planwright:tower`), and again by each
  skill's bring-up; a command tag matched anywhere other than the prompt's
  start SHALL NOT mark.
  *(Cites: D-8, the tower-enforcement flight review F11 (Sources).)*
- **REQ-C1.4** Enforcement SHALL fail closed in a marked session or one
  whose mark cannot be read: a store that exists but cannot be searched
  counts as marked; in such a session an oversized or unreadable payload
  denies, a signal or crash before a verdict denies, and any command that
  names the mark store is refused. Where no store exists, or no top-level
  session id can be read, the session counts as unmarked and the hook
  defers.
  *(Cites: D-8, the tower-enforcement flight review F2, F7, F8 (Sources).)*
- **REQ-C1.5** The session id SHALL be read from the payload's top level
  only, and every plugin hook entry this bundle adds SHALL carry an
  explicit timeout longer than the policy guard's own whole-call deadline
  plus margin and below the harness default, so the guard always reaches
  its own verdict before the harness can kill it.
  *(Cites: D-8, the tower-enforcement flight review F9, F12 (Sources).)*
- **REQ-C1.6** An unmarked session SHALL be unaffected, and its path
  through the hook SHALL be a cheap in-shell prefilter before any process
  is forked.
  *(Cites: D-8, the tower-enforcement flight review F13 (Sources).)*
- **REQ-C1.7** The profile launch (`--settings` with the tower profile)
  SHALL keep working as an additional layer, its command guard included.
  *(Cites: D-7.)*
- **REQ-C1.8** A tower resumed or forked under a different fleet home or
  session id SHALL be re-marked by its bring-up, and the docs SHALL state
  the residual window: from the resume until the bring-up or on-request
  posture check re-marks it, which the posture check reports.
  *(Cites: D-8, the tower-enforcement flight review F10 (Sources).)*
- **REQ-C1.9** Only plugin hook processes SHALL write marks. The mark
  store SHALL stay bounded: every mark write SHALL prune marks not
  refreshed within 30 days, and every bring-up and on-request posture
  check SHALL refresh the session's own mark through the activation
  handshake.
  *(Cites: D-8, kickoff §7 decision-domains gap check (2026-10-08)
  (Sources).)*

## REQ-D — The deny floor

- **REQ-D1.1** The tower floor SHALL deny exactly these acts, in every
  checkout including the tower's own, since the guard cannot prove which
  checkout a command reaches: `checkout` and `reset` in every form (the
  path-restoring forms included); `switch`; every form that force-resets
  an existing branch (`branch -f`, `checkout -B`, `switch -C`,
  `worktree add -B` on any branch); branch rename and copy (`-m`, `-M`,
  `-c`, `-C`); `symbolic-ref` writes; fetches into a local branch;
  `gh pr checkout` and `gh repo sync`; and every `stash` subcommand except
  `stash list` and `stash show`. Plain branch creation and deletion, and
  the commit family, stay allowed. Any act not listed is outside the floor.
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
  as receiving the command as written, unexpanded, and SHALL drop the
  statements this bundle makes false (tower scoping enforced only by hook
  wiring; the tower committing via git as its reason not to need the MCP
  write tools).
  *(Cites: obs:b159857e.)*

## REQ-E — Dispatch from a tower's own tree

- **REQ-E1.1** Unit worktrees dispatched from a tower in a linked worktree
  SHALL be placed under the repository's primary `.claude/worktrees/`,
  never nested under the tower's own worktree. The dispatch scripts
  already resolve the primary checkout; this bundle pins that with a
  regression test.
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
- **REQ-F1.5** The docs SHALL carry an upgrade note: a tower already running
  when this release installs has no mark, and so no plugin floor, until its
  next bring-up; restart running towers after installing. The docs SHALL
  also state that the plugin floor has no off switch: a misfire is worked
  around from a plain session and fixed by a plugin downgrade or release.
  *(Cites: D-8, kickoff §7 decision-domains gap check (2026-10-08)
  (Sources).)*

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
- 2026-10-08 — Kickoff walkthrough edits (meaning-class, applied in
  Draft): `/orchestrate`'s bring-up, posture check, and `refuse` hold over
  its outward acts; plugin-namespaced marking; hook-only marking through
  the activation handshake; unknown sessions defer; hook timeouts above
  the guard's deadline; the mark store's safety bar, pruning (REQ-C1.9),
  and upgrade note (REQ-F1.5); REQ-D1.1 as a closed act list, the commit
  family outside it; the sanctioned-script exceptions to the placement
  floor; REQ-E1.1 as a regression test; the flight review summarized in
  Sources; task wording, citations, and glossary aligned.

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
  (2026-10-07) as prior art, not as code to merge. The record lives only in
  that worker's session; its findings, summarized here with their
  disposition in this bundle, are what the bundle's "flight review"
  citations refer to:
  - F1: self-marking unlocked the command guard's auto-allows. Met by D-7
    and REQ-C1.2 (deny-only plugin path).
  - F2: an oversized payload in a marked session deferred. REQ-C1.4.
  - F3: an abbreviated `--reason` let `worktree add … main` through.
    REQ-D1.2 (long-option prefixes).
  - F4: a `remotes/<remote>/main` ref form deferred. REQ-D1.2 (ref forms).
  - F5: a new branch named `docs/main` was wrongly denied. REQ-D1.4.
  - F6: repo aliases to tower acts deferred. REQ-D1.2 (aliases).
  - F7: a marked tower could unmark itself through the store. REQ-C1.4.
  - F8: a signal before the deny trap let a marked call through.
    REQ-C1.4.
  - F9: the session id was read at any payload depth. REQ-C1.5.
  - F10: a resumed or forked tower under another fleet home was unmarked.
    REQ-C1.8.
  - F11: a command tag anywhere in the prompt marked. REQ-C1.3.
  - F12: hook entries carried no timeout. REQ-C1.5.
  - F13: the unmarked path forked several processes per call. REQ-C1.6.
  - F14: hand-rolled option walks beside the shared parser. D-9.
  - F15: stale prose across headers, `_about`, and docs. REQ-D1.5,
    REQ-F1.4.
  - F16: missing tests for the F2, F3, F9 and store-failure cases. Task 3
    and Task 4 Done when.
  - F17: the session test file ran near the per-file time ceiling under
    load. Task 3 Done when (the per-file ceiling).
  - D1 (declined there): further branch-moving forms deferred. Taken up
    here as REQ-D1.1's closed list; remote `push --delete` stays outside
    it.
  - D2 (declined there): shell-feed and wrapper spellings. Deferred in
    `tasks.md`.
  - D3 (declined there): only a server named `github` is matched. Out of
    scope here.
  - D4 (declined there): the activation pattern accepted shell operators.
    Superseded by D-8's hook-only handshake.
  - D5 (declined there): a helper name collision taking constants only.
    No action.
- **tower-front-door** (`specs/tower-front-door/`): the tower permission
  posture (its REQ-A1.3, D-14), the hard invariants (its REQ-G group), and
  its bring-up posture check.
- **concurrent-orchestrator-coordination**
  (`specs/concurrent-orchestrator-coordination/`) and
  `docs/per-tower-checkouts.md`: the per-tower checkout model.
- **Drafting-session decision** (2026-10-07): the operator's choices made
  while drafting this bundle, recorded in the decisions that cite it.
- **Kickoff walkthrough** (2026-10-07 to 2026-10-08):
  `specs/tower-placement/kickoff-brief.md`; "kickoff §N" citations name its
  sections.
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
