# Tower placement — Design

**Status:** Ready
**Last reviewed:** 2026-10-08
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` new in this bundle; `C, <spec> <id>` carried from another
bundle.

## Decision log

### D-1: Altitude — a doctrine floor with three mechanisms  (N)

**Decision:** The rule that a tower never moves, dirties, or stashes in a
checkout it does not own lands as a new floor in
`doctrine/fleet-coordination-floor.md`, beside the tower non-authoring
boundary. The floor binds a tower's own commands and names its exceptions:
planwright scripts performing operator-sanctioned acts (the release
fast-forward of the primary `main`, starting a forward-merge in a worker's
worktree), which the operator chose at kickoff (2026-10-08) to keep rather
than retire. Its mechanisms are the `tower_placement` knob with the bring-up
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
which is the autopilot-reflex seed-claim trigger (the pinned altitude seed
claim, Sources); the floors document
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
  harness documents no way to relax it (Research, Sources).
- Run towers in the primary checkout with a stricter floor. Rejected
  because: the operator's requirement is that the primary checkout's
  `main` is never dirtied or switched, and a floor narrows the risk without
  removing the shared working tree.

**Chosen because:** a tower's job crosses worktrees, so the only fence it
can live with is its own floor, not the harness's isolation. Workers branch
from `origin/main` (`scripts/fleet-dispatch-worktree.sh`), so a tower in a
linked worktree never needs to move local `main`; plain `git worktree add`
is already a sanctioned exception to native worktree creation
(obs:a19fc34c, obs:7ad46e46).

### D-4: One knob, `tower_placement`, default `warn`  (N)

**Decision:** `tower_placement` takes `warn` (default), `refuse`, or
`allow`, resolved through the existing knob resolver and config layers.
`warn` reports a tower in a main tree once and continues. `refuse` applies
the posture check's existing hold: no repo-mutating route and no relay
until the tower moves or the operator acknowledges; questions and
read-only work continue. `/orchestrate` holds its outward acts (dispatch,
relay, the bookkeeping push and PR) on the same terms, status and
read-only reconcile continuing; its bring-up runs once per invocation, and
unattended it notifies and parks rather than waiting for an
acknowledgement. `allow` is how a dedicated tower clone declares
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
overlay. `warn` adds a non-blocking message and nothing else, which is as
close to today's behavior as a new check allows. The hold `refuse` applies
is tower-front-door's posture hold (its REQ-A1.3, D-14). Operator decision
(2026-10-07).

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
  undocumented (Research, Sources).
- Keep the floor profile-only. Rejected because: the ask is a floor that
  holds however the tower is launched.

**Chosen because:** tightening-only is the posture rule, and a deny-only
path makes self-marking harmless by construction. Operator decision
(2026-10-07).

### D-8: Session marking, failing closed  (N)

**Decision:** A plugin prompt hook marks a session whose prompt opens with
the `/tower` or `/orchestrate` command; each skill's bring-up marks again,
so resume, fork, or a skill entered another way is covered. Only hook
processes write marks, so a mark lands in the fleet home the guard reads
(the session's own shell can resolve another). Bring-up marks through a
handshake: it runs a fixed activation command, which the PreToolUse hook
intercepts, marks the session, and refuses with a constant "active"
message; the command's own body never runs in a wired session. Seeing
that refusal is the proof the plugin floor is live, so the posture check
counts enforcement as active only on it, and any other outcome (the
command running, a different refusal) as missing or broken. Marks live in
the fleet home, under the bar the sibling tower stores already hold
(`tower-queue.sh`, `tower-reply-hook.sh`): owner-only directory and files,
no symlink anywhere in the store, the session id validated as a UUID
before it becomes a path, refresh by temp file and rename, and pruning
that never follows a link. A mark failing that check in a marked session
denies; a "tampered" mark means exactly such a failure. The guard reads the session id from the payload's
top level, checks the mark with an in-shell prefilter before forking
anything, installs its deny trap once the session is found marked, denies
an oversized payload in a marked session, treats an unsearchable store as
marked, defers where no store exists or no id can be read (ordinary
sessions are never gated by a broken or absent store), and refuses any
command naming the store. Every mark write prunes marks not
refreshed within 30 days, and every mark write refreshes the session's own
mark, so bring-up and the on-request posture check (each a handshake) keep
a tower that is still answering. Every plugin hook entry this bundle adds
carries an explicit timeout longer than the guard's own deadline plus
margin, since a hook the harness kills lets the command through.

**Alternatives considered:**
- Mark only from the skill. Rejected because: the model can skip a skill
  step; the hook path cannot be skipped.
- Mark from a script the skill runs in the session's shell. Rejected
  because: that shell can resolve a different fleet home than the hook,
  leaving the floor off while the posture check reports it on, and it
  cannot prove the hook is live (operator decision at kickoff,
  2026-10-08).
- Mark on a command tag anywhere in the prompt. Rejected because: a pasted
  transcript would mark (flight review F11).

**Chosen because:** each element closes a validated finding of the
flight's review (F2, F7, F8, F9, F10, F11, F12, F13), failing closed is
the guard family's contract, and the hook-only writer, the store's safety
bar, and its pruning close kickoff §8's lens findings and §7's
decision-domains gap (2026-10-08). The store is new rather than the
existing tower marker or fleet presence records because those are keyed
per spec or published by a loop, while a mark must exist from the first
prompt of any tower session.

### D-9: One source of truth for the floor  (N)

**Decision:** The tower profile's deny list stays the declared floor; the
policy guard's classifier covers every act the list blocks, through its
shared option parser; a fixture maps each deny entry to its act, and a
check fails when an entry has no act. No hook interprets permission globs.

**Alternatives considered:**
- Interpret the deny globs in a hook. Rejected because: it re-implements
  the harness matcher, which the docs say does not match option-shifted
  spellings anyway (Research, Sources).

**Chosen because:** the guard sees every spelling the parser can read, and
the map check keeps the profile and the guard from drifting apart.

### D-10: What "branch-moving" and "stash-writing" mean  (N)

**Decision:** A branch-moving act is a command that repoints an existing
branch or a checkout's HEAD without authoring a new commit; a
stash-writing act is any stash use beyond `list` and `show`, since the
stack is shared by every worktree of a clone. REQ-D1.1 holds the act list,
and it is closed: the rule explains the list, the list is what Task 4
builds. `checkout` and `reset` are denied in every form, path-restoring
ones included, so the guard never has to tell the forms apart. Plain
branch creation and deletion stay allowed (a tower cleans up squash-merged
flight branches with `branch -D`). File-only commands (`restore`,
`clean`) stay outside it: "dirties" in the doctrine floor has no
mechanism, by decision.
The commit family (commit, cherry-pick, revert, am) is outside the rule:
`/orchestrate` commits its observation fragments by hand and its
in-session backend runs `/execute-task` in the tower's own session, and a
tower in its own tree commits onto its own branch. A deliberate commit into
another checkout stays forbidden by the doctrine floor (D-1) alone.
A name that merely contains a protected branch name is not a match.

**Alternatives considered:**
- Only `checkout`, `switch`, and `stash`, as the seed listed. Rejected
  because: `reset`, `branch -f`/`-M`, `symbolic-ref`, and a fetch into a
  local branch move a branch just as well (flight review D1).
- Include the commit family. Rejected because: it breaks `/orchestrate`'s
  observation commits and in-session backend, while the stranded-commit
  incident (obs:8bc1198c) came from a tower in the primary checkout, which
  the placement check now addresses (operator decision at kickoff,
  2026-10-08).
- Deny all stash commands. Rejected because: it removes read-only
  inspection for no safety gain.

- Leave the act set as an open rule for the builder to survey. Rejected
  because: two builders would deny different edge commands (branch
  delete, `worktree add -B`, file-only forms), and the map fixture needs a
  fixed set (operator decision at kickoff, 2026-10-08).
- Also deny `restore` and `clean`. Rejected because: file writes through
  Edit, Write, and the shell stay open regardless, so it would cost a
  tower its own tidying for a partial cover.

**Chosen because:** the rule names the intent and the closed list makes it
buildable and testable; spellings of each listed act are covered by
REQ-D1.2. Operator decisions (2026-10-07, 2026-10-08).

### D-11: Dispatch from a tower's own tree  (N)

**Decision:** Dispatch resolves the worktree root from the repository's
primary worktree (via git's common directory), never from the current
toplevel, and flight slot counting and brief retirement skip the primary
checkout, reading worktree lists NUL-delimited.

**Alternatives considered:**
- Leave nested placement as is. Rejected because: it diverges from the
  documented placement and from attachability from the primary checkout.

**Chosen because:** both defects appear exactly when towers move into their
own trees, which this bundle makes the supported launch. The nesting
defect (obs:6688f319) was fixed on `main` after the observation was filed,
so only the flight-count defect (obs:cc66393d) needs a fix; the placement
gets a regression test. Operator decision
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

### D-13: Altitude of the profile-hooks fix — a mechanism and its check  (N)

**Decision:** The dead tower-profile hooks are fixed as a mechanism (the
spelling and a fail-closed prefix) plus a check over every settings
profile, not as a new doctrine rule. The recurrence (the worker profile
fixed, the tower profile missed) is the mid-flow signal that triggered
this call.

**Alternatives considered:**
- A doctrine rule on how settings profiles name the plugin root. Rejected
  because: the rule is a single spelling a test can enforce; the existing
  pinning test already holds the explanation, and a check is what stops a
  third profile from repeating the defect.
- Fix the tower profile alone. Rejected because: that is how the tower
  profile was missed after the worker fix.

**Chosen because:** a mechanical rule belongs in a mechanical check.
Drafting-session decision (2026-10-08).

### D-14: The quoted, unbraced plugin-root spelling  (N)

**Decision:** Each tower-profile hook names its script as
`"$CLAUDE_PLUGIN_ROOT"/scripts/…`, which Claude Code leaves alone and the
shell expands from the environment the launcher exports, exactly as
`config/worker-settings.json` already does.

**Alternatives considered:**
- A literal absolute path generated at launch. Rejected because: it adds a
  generation step to every launcher, while the supported launcher already
  exports the root.
- `${CLAUDE_PROJECT_DIR}`. Rejected because: it names the project, not the
  plugin install, and a tower may run the installed plugin rather than a
  checkout.
- Unquoted `$CLAUDE_PLUGIN_ROOT`. Rejected because: it word-splits on a
  root containing a space, a second way for the hook to never run
  (obs:aed5517e).

**Chosen because:** it is the one spelling measured to run under
`--settings` (obs:aed5517e, the profile-hooks seed), and it matches the
worker profile, so one check covers both.

### D-15: One check over every settings profile  (N)

**Decision:** The static half of
`tests/test-settings-fragment-hook-expansion.sh` is widened from the
worker profile's first hook to every hook command in every `config/*.json`
that carries a `hooks` key, failing on the braced token or any other
plugin-root form; `tests/test-tower-settings-hook-wiring.sh` drops its
pin on the braced spelling.

**Alternatives considered:**
- A new `scripts/check-*.sh` under `mise run check`. Rejected because: the
  existing test already owns this rule and its rationale, and a second
  home would split them.
- List the profiles by name. Rejected because: a new profile would escape
  the check, which is the recurrence this fixes.

**Chosen because:** reuse of the existing seam, scoped by a decided rule
(a `hooks` key) rather than an enumerated list. Drafting-session decision
(2026-10-08).

### D-16: Policy hooks refuse an unresolved root  (N)

**Decision:** Each tower-profile hook that runs the policy guard first
checks that the guard script is executable at the expanded path, and
otherwise prints a reason naming the unresolved guard and exits 2, which
blocks the call. The command guard's hook stays as is: an unresolved path
exits 127, which the harness treats as non-blocking, and for an allow-only
guard that is a defer, its existing fail-closed behaviour.

**Alternatives considered:**
- Also block on the command guard's hook. Rejected because: the policy
  hook already blocks every Bash call in that state, so it adds nothing,
  and it would give an allow-only guard a blocking path.
- Leave every hook non-blocking. Rejected because: exit 127 lets the call
  through, so a missing environment variable silently removes the
  deny-emitting layer, against the guard family's fail-closed contract
  (REQ-C1.4).

**Chosen because:** only exit 2 blocks in PreToolUse (Research: Claude
Code hooks exit codes, Sources), and refusing every call until the tower
is relaunched correctly is loud where a dropped layer is silent. Operator
decision (2026-10-08).

## Cross-cutting concerns

- **Decision domains.** Security posture and authorization (the plugin
  floor, marking, the deny list) are escalated as D-7 through D-10, each
  operator-decided. Integration surface (Claude Code hooks, settings
  layers, worktree isolation) rests on the documentation research in
  Sources, with the undocumented points avoided rather than relied on.
  Configuration follows the customization-boundary default (D-4). Data
  storage (the mark store's lifetime and safety bar) and deploy/migration
  (the upgrade window, no off switch, the breaking-change marker) were
  decided at kickoff (D-8, REQ-C1.9, REQ-F1.5).
- **Instruction headroom.** The skill instruction budget is saturated;
  Task 6 lands its bring-up wiring word-neutral in both skills and puts
  detail in docs and scripts, not skill prose.
- **Concurrency.** The mark store takes concurrent writers; a mark write is
  atomic and idempotent, and the guard reads it without the fleet lock.
- **Profile rollout.** A running tower keeps the profile it launched
  with; the fixed hooks take effect on relaunch, and a launch without
  `CLAUDE_PLUGIN_ROOT` exported now refuses Bash outright (D-16), which
  the docs and changelog state (REQ-F1.6).
- **Plugin-version skew.** A tower and its plugin hooks resolve the same
  plugin root; the posture check reports the root it read.
