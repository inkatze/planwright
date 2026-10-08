# Tower placement — Design

**Status:** Draft
**Last reviewed:** 2026-10-07
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` new in this bundle; `C, <spec> <id>` carried from another
bundle.

## Decision log

### D-1: Altitude — a doctrine floor with three mechanisms  (N)

**Decision:** The rule that a tower never moves, dirties, or stashes in a
checkout it does not own lands as a new floor in
`doctrine/fleet-coordination-floor.md`, beside the tower non-authoring
boundary. Its mechanisms are the `tower_placement` knob with the bring-up
check (capability), the plugin-wired deny-only floor (mechanism), and the
wider deny list (mechanism). The operator's launcher and knob value are
local values, outside this repository.

**Alternatives considered:**
- Mechanism and docs only, the rule stated in `docs/per-tower-checkouts.md`.
  Rejected because: the floor list is what fleet skills and mechanisms
  cite; a rule only in a guide is invisible to the next mechanism author.
- Fold it into the non-authoring boundary paragraph. Rejected because:
  it stretches "authoring" to cover branch moves and placement, which
  reads less plainly than a named floor.

**Chosen because:** the seed states an invariant across every tower kind,
which is the autopilot-reflex seed-claim trigger; the floors document
exists to hold exactly such invariants, and no skill loads it at run
start, so it costs no instruction budget. Operator decision (2026-10-07).

### D-2: A new bundle covering every tower kind  (N)

**Decision:** This is its own bundle rather than an extension of
tower-front-door, and it covers `/tower` and `/orchestrate` towers alike,
meta-towers and subordinate towers included.

**Alternatives considered:**
- Extend tower-front-door for `/tower` only. Rejected because: the
  meta-tower incident in the seed would stay uncovered, and the tower
  profile is shared by both kinds.
- Extend tower-front-door for every kind. Rejected because: it supersedes
  that bundle's fleet-integration exclusion and pushes a large bundle into
  a second skill's territory.
- Extend concurrent-orchestrator-coordination. Rejected because: its goal
  is coordination among several towers; a single tower's placement and
  the `/tower` bring-up sit outside it.

**Chosen because:** fold-detection's spin-new trigger "independently
ownable" fires: placement spans two skills' bring-ups and decides checkout
policy, not routing or coordination. Operator decision (2026-10-07).

### D-3: The supported launch — its own tree, never `--worktree`  (N)

**Decision:** A tower is launched from its own working tree: a linked
worktree made with plain `git worktree add`, or a separate clone. It is
never launched with `claude --worktree`. One tower in a linked worktree is
a supported home; several concurrent towers still want separate clones, as
the per-tower-checkouts guide says, because linked worktrees share one
`main` ref.

**Alternatives considered:**
- Keep `--worktree` and ship helper verbs for every refused form.
  Rejected because: the isolation refuses any command it cannot prove
  stays inside the worktree, including loops, computed command names, and
  variable-built arguments; the set of helpers would never close, and the
  harness documents no way to relax it.
- Run towers in the primary checkout with a stricter floor. Rejected
  because: the operator's requirement is that the primary checkout's
  `main` is never dirtied or switched, and a floor narrows the risk without
  removing the shared working tree.

**Chosen because:** a tower's job crosses worktrees, so the only fence it
can live with is its own floor, not the harness's isolation. Workers branch
from `origin/main`, so a tower in a linked worktree never needs to move
local `main`.

### D-4: One knob, `tower_placement`, default `warn`  (N)

**Decision:** `tower_placement` takes `warn` (default), `refuse`, or
`allow`, resolved through the existing knob resolver and config layers.
`warn` reports a tower in a main tree once and continues. `refuse` applies
the posture check's existing hold: no repo-mutating route and no relay
until the tower moves or the operator acknowledges; questions and
read-only work continue. `allow` is how a dedicated tower clone declares
itself, set in that clone's machine-local layer.

**Alternatives considered:**
- Default `refuse`. Rejected because: a core default that changes every
  adopter's behavior breaks the customization-boundary rule that a core
  knob's default preserves today's behavior.
- Two knobs, placement kind and response. Rejected because: "clone only"
  cannot be verified by git and still needs the local declaration, so the
  second key adds documentation and tests without adding a check.
- No knob, always refuse. Rejected because: a clone-based tower would need
  an acknowledgement every session.

**Chosen because:** git can tell a linked worktree from a main tree but
not a dedicated clone from the operator's primary checkout; a local `allow`
is the honest declaration, and the operator's own `refuse` lives in their
overlay. Operator decision (2026-10-07).

### D-5: A deterministic placement classifier  (N)

**Decision:** A script classifies the checkout as a main tree or a linked
worktree by comparing git's own directory with its common directory, and
reports the knob's resolved value beside it. No model judgment decides the
classification; the skill only renders the result.

**Alternatives considered:**
- Path heuristics (`.claude/worktrees/` in the path). Rejected because: a
  plain `git worktree add` may place a tower anywhere.

**Chosen because:** git's own metadata is authoritative and cheap, and a
script can be tested.

### D-6: Isolation is detected by probe and only warned  (N)

**Decision:** Bring-up runs one harmless read against the primary
checkout that the harness's worktree isolation is documented to refuse; a
refusal means the session is isolated, and the tower warns once, naming
the supported launch. It never blocks the tower.

**Alternatives considered:**
- Read a harness signal. Rejected because: Claude Code documents no
  environment variable, hook field, or setting that reports worktree
  isolation (Research, Sources).
- Refuse when isolated. Rejected because: an isolated tower can still do
  useful read-only work, and the probe's reading is a heuristic.

**Chosen because:** it is the only observable the harness offers, and a
warning is proportional to a heuristic.

### D-7: The plugin path is deny-only  (N)

**Decision:** The plugin's hooks run `policy-guard.sh` at the tower tier
for marked sessions and nothing else. `tower-command-guard.sh` and its
auto-allows stay with the profile launch. A mark therefore can only
restrict the session that carries it, so marking needs no trust.

**Alternatives considered:**
- Run the command guard from the plugin as well. Rejected because: any
  session could mark itself and gain its auto-allows (flight review F1).
- Grant the allows only with a launch-time signal the model cannot write.
  Rejected because: it helps only launchers that set the signal, drops
  desktop and IDE launches, and rests on harness behavior the docs leave
  undocumented.
- Keep the floor profile-only. Rejected because: the ask is a floor that
  holds however the tower is launched.

**Chosen because:** tightening-only is the posture rule, and a deny-only
path makes self-marking harmless by construction. Operator decision
(2026-10-07).

### D-8: Session marking, failing closed  (N)

**Decision:** A plugin prompt hook marks a session whose prompt opens with
the `/tower` or `/orchestrate` command; each skill's bring-up marks again,
so resume, fork, or a skill entered another way is covered. Marks live in
the fleet state store. The guard reads the session id from the payload's
top level, checks the mark with an in-shell prefilter before forking
anything, installs its deny trap once the id is read, denies an oversized
payload in a marked session, treats an unsearchable store as marked, and
refuses any command naming the store. Every plugin hook entry carries an
explicit timeout below the harness default. The posture check accepts an
active mark with the plugin hook wired as meeting the floor.

**Alternatives considered:**
- Mark only from the skill. Rejected because: the model can skip a skill
  step; the hook path cannot be skipped.
- Mark on a command tag anywhere in the prompt. Rejected because: a pasted
  transcript would mark (flight review F11).

**Chosen because:** each element closes a validated finding of the
flight's review (F2, F7, F8, F9, F10, F11, F12, F13), and failing closed is
the guard family's contract.

### D-9: One source of truth for the floor  (N)

**Decision:** The tower profile's deny list stays the declared floor; the
policy guard's classifier covers every act the list blocks, through its
shared option parser; a fixture maps each deny entry to its act, and a
check fails when an entry has no act. No hook interprets permission globs.

**Alternatives considered:**
- Interpret the deny globs in a hook. Rejected because: it re-implements
  the harness matcher, which the docs say does not match option-shifted
  spellings anyway.

**Chosen because:** the guard sees every spelling the parser can read, and
the map check keeps the profile and the guard from drifting apart.

### D-10: What "branch-moving" and "stash-writing" mean  (N)

**Decision:** A branch-moving act is any command that changes which commit
a branch or a checkout's HEAD names. A stash-writing act is any command
that changes the stash stack, which every worktree of a clone shares.
Read-only stash inspection stays allowed. A name that merely contains a
protected branch name is not a match.

**Alternatives considered:**
- Only `checkout`, `switch`, and `stash`, as the seed listed. Rejected
  because: `reset`, `branch -f`/`-M`, `symbolic-ref`, and a fetch into a
  local branch move a branch just as well (flight review D1).
- Deny all stash commands. Rejected because: it removes read-only
  inspection for no safety gain.

**Chosen because:** a decided rule covers spellings an enumeration would
miss. Operator decision (2026-10-07).

### D-11: Dispatch from a tower's own tree  (N)

**Decision:** Dispatch resolves the worktree root from the repository's
primary worktree (via git's common directory), never from the current
toplevel, and flight slot counting and brief retirement skip the primary
checkout, reading worktree lists NUL-delimited.

**Alternatives considered:**
- Leave nested placement as is. Rejected because: it diverges from the
  documented placement and from attachability from the primary checkout.

**Chosen because:** both defects appear exactly when towers move into their
own trees, which this bundle makes the supported launch. Operator decision
(2026-10-07).

### D-12: The flight is prior art, not code to merge  (N)

**Decision:** The tower-enforcement flight's branch informs Tasks 3 and 4;
those tasks build on `main` and meet the review's findings, and the flight
branch is never merged.

**Alternatives considered:**
- Continue the flight branch. Rejected because: the operator moved the
  work into a spec after the review stopped on validated findings in
  guard code.

**Chosen because:** operator decision (2026-10-07), relayed through the
tower.

## Cross-cutting concerns

- **Decision domains.** Security posture and authorization (the plugin
  floor, marking, the deny list) are escalated as D-7 through D-10, each
  operator-decided. Integration surface (Claude Code hooks, settings
  layers, worktree isolation) rests on the documentation research in
  Sources, with the undocumented points avoided rather than relied on.
  Configuration follows the customization-boundary default (D-4).
- **Instruction headroom.** The skill instruction budget is saturated;
  Task 6 lands its bring-up wiring word-neutral in both skills and puts
  detail in docs and scripts, not skill prose.
- **Concurrency.** The mark store takes concurrent writers; a mark write is
  atomic and idempotent, and the guard reads it without the fleet lock.
- **Plugin-version skew.** A tower and its plugin hooks resolve the same
  plugin root; the posture check reports the root it read.
