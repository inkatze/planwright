# Custom Steps

A unit's execution process exposes **named attachment points**: moments at
which an operator declares, per point and through the overlay layers, an
ordered list of **steps** to run there. This doc is the one normative home for the point
vocabulary, when each point fires, and the step contract (REQ-A1.5, D-9).
Skills carry the invocation; `scripts/resolve-steps.sh`,
`scripts/step-record.sh`, and `scripts/step-pool.sh` carry the mechanics,
their usage headers pinning what this doc delegates to them; the operator's
own chain lives in their overlay (D-1,
[customization-boundary](customization-boundary.md)).

*The runner* is the session hosting the unit, or the flipper at a flip point,
with the scripts it calls. *Attended* narrows [gate-wiring](gate-wiring.md)'s
pause-protocol distinction to the backend seam's launch record: a headless
launch is unattended, any other attended. *Unit* widens
[spec-format](spec-format.md)'s task-or-bundle sense to the spec bundle and
the flight (D-13); a *unit run* is one `/execute-task` invocation, a flight's
convergence, or a flip point's firing.

Citations: custom-steps REQ-A1.1–A1.6, REQ-B1.1–B1.7, REQ-C1.1–C1.8,
REQ-D1.1–D1.12, REQ-E1.1–E1.3, REQ-E1.5, REQ-E1.6, REQ-F1.5, REQ-G1.1–G1.4,
REQ-H1.3–H1.5, REQ-I1.1–I1.11, REQ-J1.1–J1.3 · custom-steps D-1–D-32 ·
tower-front-door REQ-H1.1.

## The point vocabulary

The vocabulary is **core-owned**: every point is a moment inside a skill only
core can wire, so an adopter needing a moment planwright does not name records
an observation, never an overlay point (REQ-A1.3, D-2). A point name outside
this vocabulary is a resolver usage error.

**Wired in `/execute-task`** (the *in-run points*), each fired once when the
run reaches it (a re-execution against a unit with an open PR is a new run,
REQ-A1.1), in this order (D-3):

| Point | Fires |
| --- | --- |
| `pre-implementation` | after pre-flight passes, before the first implementation commit |
| `pre-ci` | after the last implementation commit, before the first full CI run of the unit run |
| `convergence` | after CI is green: the point resolves, then the merge-currency-guard `main` sync once per firing (an empty list included), then the steps; this list is the unit's convergence phase |
| `pre-pr` | after the last convergence step, before the push |
| `post-pr` | after the draft PR exists and its body is assembled |

**Wired in `/spec-kickoff`:** `pre-spec-ready-flip`, after its push and PR
step and before the terminal CI gate, on the head that flip lands on, once per
sign-off that reaches that step, whether or not the flip is configured to
follow (REQ-A1.2, D-13).

**Run by `/execute-task`'s unit-PR flip (`scripts/ready-flip.sh`'s header
owns the sequence):** `pre-ready-flip`, immediately before any agent-issued
draft-to-ready flip of a unit PR, on the head to be flipped, once per flip
attempt (REQ-A1.1, REQ-E1.3, D-2).

**Named, not wired** (gated under custom-steps' Deferred): `spec-drafted`,
`kickoff-signed-off`, `unit-selected`, `pre-dispatch`, `post-dispatch`,
`unit-halted`, `post-merge`, and `orchestrator-idle` (issue 383's
`tower-idle`, in tower-front-door REQ-H1.1's sense). A non-empty list at one
of these resolves no steps; the resolver and `check:steps` report it as
unwired, never silently.

**Flights.** A flight converges through `steps_convergence` with unit kind
`flight`, skill steps only (REQ-F1.5; [flight-rules](flight-rules.md)).

## The step entry

Steps are entries in the `steps` data catalog, merged across the overlay
layers by `scripts/resolve-catalog.sh`; `supersede: true`
is part of the entry format, never an unknown field (REQ-B1.1, D-4). Every
value is a single-line scalar of the constrained reader.

| Field | Value |
| --- | --- |
| `id` | required; `^[a-z][a-z0-9-]*$`, at most 64 bytes, validated before any key or path use; `implementation` is reserved for the unit's implementation phase, never a step id |
| `kind` | required; `skill`, `command`, or `prompt` |
| `target` | required; per the kind's grammar below |
| `args` | optional; on a skill, passed verbatim, never shell-interpreted; on a command, plain words only (no operators, redirections, expansions, or quoting), the same under a shell and as argv; forbidden on a prompt |
| `hosting` | optional; `isolated`, `continue`, or `in-session`; default per *Hosting* |
| `on-failure` | optional; `halt` (default) or `continue` |
| `timeout` | optional; a positive integer of seconds, unset meaning no limit beyond a hosting tool's own; forbidden on an `in-session` skill or prompt step |
| `requires` | optional; space-separated executable names in the command-target charset |
| `pool`, `paths`, `refire` | optional, command steps only (*Expensive checks*) |
| `vendor`, `control`, `on-limit`, `moves-head`, `final-head`, `drains` | optional; known fields whose grammar and meaning quota-handling owns (REQ-J1.3, D-29) |

**Target grammar (REQ-B1.6).** A skill target is `<name>` or
`<plugin>:<name>`, the slash-command name without its leading slash; a command
target is an executable name or path; a prompt target is non-empty single-line
text. Validation precedes any path or command use; a failing target, args, or
`requires` is malformed for its layer and never interpolated, as is an entry
with an unknown field, an unknown or empty value, a missing required field, or
an un-honorable combination (REQ-B1.7). Rules keyed on hosting read the
**effective** hosting: the default below, a `continue` step's attachment to
an `in-session` predecessor, and, once it happens, a run-time degradation.

**No `env` and no `cwd` field** (D-15). Declarations carry no secrets: a step
needing a credential reads it from the host environment the runner inherits
(REQ-B1.5); an `isolated` or `continue` session's environment is what its
backend gives a fresh session. Every step runs in the unit's worktree.

**Point lists (REQ-B1.3).** One flat key per point, `steps_<point>` with
hyphens as underscores (the unwired points included), holds an inline flow
list of step ids. `[]` resolves to no steps and is not malformed. Core ships
`steps_convergence: [polish]` and every other key empty. Steps run serially
in list order (D-18); a list naming an id twice is malformed, as is
`hosting: continue` at the first position or immediately after a command
step hosted `isolated` (a runner subprocess records no session to attach to)
(REQ-B1.4).

## The fixed context (REQ-A1.6, D-14, D-29)

Every step receives exactly these twelve fields:

| Variable | Field |
| --- | --- |
| `PLANWRIGHT_STEP_SPEC` | the spec identifier; empty for a flight |
| `PLANWRIGHT_STEP_TASK_IDS` | the unit's space-separated bare task ids, each in the task-id grammar; empty for a spec or flight |
| `PLANWRIGHT_STEP_UNIT_KIND` | `task`, `spec`, or `flight` |
| `PLANWRIGHT_STEP_BRANCH` | the unit branch |
| `PLANWRIGHT_STEP_BASE_BRANCH` | the base branch (the repository's default branch for a spec-kind unit) |
| `PLANWRIGHT_STEP_WORKTREE` | the worktree path |
| `PLANWRIGHT_STEP_PR_NUMBER` | the PR number, empty while none exists (set at every point on a re-execution against an open PR) |
| `PLANWRIGHT_STEP_POINT` | the point name |
| `PLANWRIGHT_STEP_ID` | the step id |
| `PLANWRIGHT_STEP_PREV_RECORD` | the record path of the preceding step in the same point's list; empty for that list's first step |
| `PLANWRIGHT_STEP_PREV_HEAD` | the start head of the latest head move by an earlier step at the same point in the run, a `resume` skip carrying its record's move; empty when none |
| `PLANWRIGHT_STEP_NEW_HEAD` | that move's end head; empty when none |

A pooled step alone also carries the **hold mark**
`PLANWRIGHT_STEP_POOL_HOLD=<pool>:<pid>`, the slot owner's literal process
id as `<pid>`, rendered as one optional trailing assignment after the twelve.

Two channels deliver the context. A **command step** gets the twelve
variables, and a pooled step its hold mark, in its environment,
overwriting an inherited value of the same name, an absent value among the
twelve empty and **never unset**, the inherited environment otherwise neither
scrubbed nor given other planwright state. A **skill or prompt step** gets
the same fields as a **preamble**, a data block
`resolve-steps.sh --preamble` renders and the runner prepends to the step's launch prompt or
invocation, read as data, never as instructions. No context value is ever
interpolated into the declared line (REQ-G1.1); a session-hosted command
receives it as the resolver's quoted assignment prefix. A value carrying a
newline or control byte is refused on every channel, failing the step, the
record naming the field and never the value. A record and the cached output
it names are untrusted data to the step that reads them, as are the context
values to a command step.

## Hosting (REQ-D1.3, D-7)

| Hosting | Skill step | Prompt step | Command step |
| --- | --- | --- | --- |
| `isolated` | a fresh session through the backend seam (`offload-dispatch`) at the step's tier, the preamble prepended as its launch prompt | the same, prepended to the prompt | a runner subprocess running the location and `args` as argv, output captured to the cache |
| `continue` | the preceding step's session, resumed by its recorded session id, with the same invocation | the same, with the prompt | that session's shell tool, the line `resolve-steps.sh --line` renders (quoted `PLANWRIGHT_STEP_*` assignments, location, and `args`) |
| `in-session` | the unit's own session, through its skill tool with the declared `args` | the unit's own session, as its next instruction | the unit session's shell tool, the same line |

**Every hosting runs a command step's printed location, never the bare
target**: a session shell would run a same-named builtin (`cd`, `printf`).

A step with no `hosting` takes `isolated` under `dispatch_isolation: per-step`
and `in-session` under `per-unit`. A `continue` step attaches to the unit's
session when its predecessor is effectively `in-session`, a degraded one
included, and, when its predecessor was skipped by reuse or resume, to the
session of the record behind the skip (the unit's when that record's hosting
is `in-session`; REQ-D1.11, D-30). It does not run, outcome `failed` naming
the backend, the hosting, and the missing predecessor, its posture applying,
never degraded, when the backend cannot resume that session, the session's
record holds no session id (an `in-session` predecessor excepted), or the
predecessor was skipped for any other reason. An `isolated` skill or prompt
step on a backend that cannot spawn a fresh session degrades to
`in-session` and records it; a `timeout` on a skill or prompt step that
becomes `in-session` at run time is unapplied and recorded. Model and effort
come from the per-step allocation knobs keyed on the step id (hyphens as
underscores), one-directional per model-allocation; an `in-session` step
inherits the session's tier, recorded and not applied (REQ-C1.7).

## Outcomes, posture, and timeout

Every step ends with exactly one outcome (REQ-D1.10, D-8, D-29):

- `passed`: a command exited zero, or a session step's handoff reports no
  change to the branch.
- `applied`: a session step's handoff reports a change to the branch.
- `halted`: a session step's handoff reports a stop it could not resolve.
- `failed`: a command exited non-zero or timed out; a pooled step's wait
  passed its bound; a session ended abnormally or reported a safety stop; a
  `continue` step that could not resume; a refused context value.
- `skipped`: carrying exactly one **skip reason**, `missing` (the
  missing-step matrix), `reuse` (*Expensive checks*), `resume` (*Resume
  continuation*), or `answered` (quota-handling's same-head review-request
  skip); free-text detail is optional.
- `limited`: only from quota-handling's limit classifier, replacing the
  outcome above on a match (its `answered` signal replaces a command's exit
  mapping alike); its effect on the point follows its `on-limit` posture,
  never `on-failure`.

A step **moved the head** when its record's end head differs from its start
head (the worktree's local HEAD, pushed or not), the one head move this doc
means (REQ-D1.12).

**The runner classifies** a skill or prompt step's outcome from the handoff
its session returns, the record carrying the excerpt the classification
rests on; a command step's outcome is its exit code alone, a timeout, or an
expired pool wait. The runner writes every record, whatever the hosting. At
`convergence` the review skills' dispositions map onto this set: a normal
exit is `passed` or `applied`; a normal exit carrying a queued meaning-class
spec fork is `halted`, stopping PR creation; a safety stop is `failed`; an
unresolved hard-disqualifier finding is `halted` (REQ-E1.1).

**Posture (REQ-D1.2).** A `halted` or `failed` step whose `on-failure` is
`halt` ends the point. At an **in-run point** it ends the unit through the
gate-wiring [pause protocol](gate-wiring.md#pause-protocol)'s destinations:
an unattended run parks the unit to `tasks.md` Awaiting input; an attended
session presents it and waits. At a **flip point** it refuses the flip and
surfaces the step (kickoff recording the pending flip to Awaiting input). An
Awaiting-input entry this doc causes names only the point, the validated
step ids, the outcome, token, or cause (a pool wait's holders, a re-fire's
head), and the worktree-relative record path where one exists, never a
target's text or an excerpt. A posture of `continue` records the outcome
and proceeds; posture governs the list only, and the fork's PR-creation
stop, the flip refusal, and the evidence below read the records whatever
the posture.

**Timeout (REQ-D1.7, D-15).** Where the runner owns the process, it ends the
step at `timeout`; where an `isolated` or `continue` session owns it, the
runner stops the session through the backend seam when the backend exposes a
stop and otherwise stops waiting on it, recording which applied. Either way
the outcome is `failed` naming the timeout; the ready-guard's currency check
and the post-pr draft verification cover a head such a session later moves.
An `in-session` command step's `timeout` goes to the session's shell tool.

## Resolution and the missing-step matrix

A point's list resolves through `config-get` with **last layer wins**, the
resolver printing one warning naming every lower overlay layer that sets the
key whatever its value, provenance per step (the hosting, its default
applied, and any pool, paths, or re-fire) on request, and one warning per
layer on the retired convergence knob's key (REQ-C1.1, REQ-C1.2, REQ-C1.6,
D-5, D-10).

**Resolution completes for the whole point before its first step runs**: the
resolved list or nothing (REQ-D1.9). Every id must resolve to a catalog entry
and every target on the host under the lookup rules REQ-C1.3 and D-19 fix,
with every `requires` executable on the path (REQ-D1.8). An id naming no
entry, a target the host lacks, an unrunnable skill (`refuse`: unskippable
save `on-failure: continue`), an off-path `requires` executable, or an
ambiguous or unreadable registry lookup does not resolve, never an error.

**The matrix (REQ-C1.4, D-6).** The resolver prints one decision token per
step, keyed on the layer that supplied the **winning list** and on
attendance, which the hosting skill passes explicitly (`--unattended` exactly
when the unit was launched headless, per the backend seam's launch record;
`--attended` otherwise; neither flag, or both, is a usage error):

| Winning list from | Attended | Unattended |
| --- | --- | --- |
| core default | `park` | `park` |
| repo-tracked | `ask` | `park` |
| adopter or machine-local | `ask` | `skip` |

`run` is a resolved step; `ask` surfaces the missing step and waits for the
human to repair and re-resolve or end the unit; `park` parks the unit to
Awaiting input before any step at the point runs; `skip` warns, records the
skip (reason `missing`), and counts as `run`: exit 0 when every step is
`run`, 1 when the point runs nothing (`park` or `ask`; REQ-H1.3). A
malformed list value or entry takes the by-layer policy instead (REQ-C1.5):
core exits 5 (a broken install), repo-tracked 4; an adopter or machine-local
list degrades to the core default, and such an entry is dropped, its id then
non-resolving. A placement-only fault (a `timeout` landing in-session)
drops an adopter or machine-local entry for that list alone; a misplaced
`continue` degrades such a list first and fails only when list and entry
are both repo-tracked or core. Check mode
(`--check --unattended`; `--attended` is a usage error) exits non-zero on
any `park`, any malformation, or an unwired non-empty list, and warns but
passes on an adopter or machine-local `skip` (REQ-H1.3, REQ-A1.3);
`check:steps` runs it over every point of this repository (REQ-H1.4).

## Expensive checks (REQ-I1.1–I1.11, D-21–D-28)

Core declares no pool, path, or re-fire; which suite, pool, and paths are
overlay values (D-21). `pool` names a pool in the `id` charset; `paths` is
space-separated repository-relative words of letters, digits, `.`, `_`, `-`,
and `/`, none starting with `/` or `-` or holding a `..` segment, `.` the
whole tree; `refire` is `post-pr`, requires `paths`, never pairs with
`hosting: continue`, and is listed only in `steps_pre_ci` or `steps_pre_pr`.

**Pools.** A pooled step holds one slot of its pool, shared by every
checkout, worktree, and unit of the user on the host, for its run only, the
slot owned by a process id, never by a descriptor a child inherits. The
**slot owner** is the process hosting the runner: the unit session's for
`in-session` and `continue` hosting, the runner subprocess for an `isolated`
command, the hand recipe's shell. The wait and take run first, on the
owner's behalf and outside `timeout` (a background job waited on inside the
turn, or bounded repeated calls whose seconds are summed); the owner
releases after the check ends, whatever its exit. An unreleased slot is
reclaimed once its owner exits, and a timeout never releases one while the
check process lives. Capacity is `step_pool_capacity_<pool>` (hyphens as
underscores), else `step_pool_capacity`; the wait, bounded by
`step_pool_wait`, reports each live holder (pid, step id or full-suite
marker, worktree) and admits unordered, and past the bound the step is
`failed` naming the holders. A pool directory that is a symbolic link or not
the user's, or a lock-library error, runs the step unpooled with one
recorded warning. `scripts/step-pool.sh` holds slots and executes nothing;
its header pins the slot mechanics (D-22–D-24).

**The hold mark.** A take under a mark naming the same pool and a live
owner holding a slot of it runs inside that hold, taking no slot, its
release a successful no-op; a mark naming another pool or a dead owner, or
failing the pool charset or a decimal pid, is ignored, and a same-owner take
without a mark waits like any caller.

**The full suite.** When `full_suite_pool` names a pool, each full local
suite attempt `/execute-task` makes, retries included, holds a slot of it;
an expired wait parks the unit naming the holders, never a CI failure or
retried. A full-suite record carries the pool fields, rendered as a
full-suite row of the audit fold on a run with a PR; before a PR exists,
the park entry names the holders (D-25). The overlay documentation's hand
recipe takes the same slot.

**Fingerprint and reuse.** A `paths` step's fingerprint pairs each word with
its git object id at the head (or an absent marker), in order; an
uncommitted tracked change or an untracked, unignored file under a declared
path leaves none, and ignored files never count (D-26). With one, the
runner skips the step (`reuse`) when any run in the worktree's record cache,
the current one and re-fires included, holds a `passed` record of the same
step id, target, and `args` digest with an equal fingerprint (D-27).

**Re-fire.** When a `post-pr` step moved the head, after the post-pr list
and before the regeneration (*Reserved controls*), each distinct step id
declaring `refire: post-pr` in this run's resolved `pre-ci` and `pre-pr`
lists (a resume's: its chain's first run) runs once more on the final head,
at its first declaring list, subject to reuse; one skipped `missing` there
is not re-fired. Each records under `post-pr` with `refire-of` naming its
declaring point; its context point is `post-pr`, its previous record the
pass's prior one (the first: the last post-pr record), its head move the
post-pr one; its declaring point's no-push rule holds. The post-pr
completion record follows the pass. A re-fired `halted` or `failed` step
under `halt` ends the unit through the pause destinations after the
regeneration and draft check, the PR a draft. Once per run (D-28).

## Resume continuation (REQ-J1.1, D-29)

A run is a **resume** exactly when its invocation carries
`--resume <run-id>:<point>`, as in
`/execute-task 5 specs/<spec> --resume 000004:post-pr`, the run id in the
record helper's grammar and the point an in-run point,
both validated before any record is read; quota-handling's resume supplies
them, and only this runner skips. The run starts at that point, never
re-running an earlier one, skipping (`resume`) the leading prefix of steps
recorded `passed` or `applied` in the interrupted run whose end head equals
the current head, read once at the start; each skip copies its record's
start and end heads, and a head that moved after the interrupted run
stopped matches no record, so nothing is skipped. A `resume` skip
stands for its record in a later resume, so chained resumes skip the same
prefix and carry its head move forward. A run held in its re-fire pass
resumes inside it.

## Reserved controls (REQ-D1.6, D-17)

A step **never** merges, marks a PR ready, force-pushes, amends, squashes, or
rebases. A step at the **four no-push points**, `pre-implementation`,
`pre-ci`, `convergence`, and `pre-pr`, never pushes; a step at `post-pr` or
either flip point may. The worker permission denies and the ready-guard keep
applying to every session-hosted step, the ready-guard on its flip surfaces
(the shell ready command and the GitHub MCP pull-request update tool); a
runner subprocess sees no hook, so it is bound by declaration alone; no
mechanism enforces any step's no-push ordering. After `post-pr`'s list
completes, the runner re-emits the per-point tables through the PR-body
assembly (post-pr's included) and verifies the PR is still a draft, parking the unit
to Awaiting input naming the post-pr steps that ran when it is not; if the
head moved it also regenerates the pending-sign-off checklist from the final
range and re-emits the review handoff; earlier points are never re-run, the
re-fire pass before this regeneration the one exception (REQ-E1.2, D-28).

**No recursion (REQ-C1.8).** A step never targets a pipeline entry skill,
matched on the name after any `<plugin>:` prefix; a match is malformed for
its layer, the message naming `pipeline-entry` and the matched name. The
resolver reads the list from `<script-dir>/../doctrine/custom-steps.md`,
the self-location path with no environment arm, never through
`resolve-rule-doc.sh`; in planwright's own repository that file shares the
trusted-repository-code posture of `scripts/`. Exactly one line beginning
`pipeline-entry:` at column zero, tokens split on single spaces and each in
the id charset; a missing or duplicated line or a bad token is a broken
install. `tower` is forward-declared for tower-front-door.

```text
pipeline-entry: execute-task orchestrate drain spec-draft spec-kickoff offload tower
```

**Permissions (D-11).** Catalogs and lists are read only from the
human-owned layers: core and adopter sit outside the worktree and a
dispatched worker's write set; repo-tracked and machine-local sit inside it,
inheriting the guard's trusted-repository-code posture for `scripts/`; the
worker profile is unchanged (REQ-G1.2). The worker command guard
auto-approves, allow-only, a segment whose words, minus leading
`PLANWRIGHT_STEP_*` assignments in the resolver's exact form, equal a
well-formed entry's location as printed on the guard's host, then its `args`,
the location passing the guard's charset and path checks (REQ-G1.3); one
deadline-bounded run, group-killed however it ends, resolves every wired point,
only when the location's file name is cataloged. **A skill step runs under the worker's
permission profile like any other skill, with no elevation**, an `isolated`
session under the profile its backend gives any session it spawns
(REQ-G1.4).

## Records (REQ-D1.5, REQ-D1.12, REQ-I1.10, D-16, D-31)

Every step leaves a record under `<worktree>/.claude/steps/`, an untracked
cache the repository's ignore list names (adopters add the line), keyed by a
run id the helper issues, read by planwright only through the helper, its
form unstable to a step reading the record `PREV_RECORD` names. Fields: the
head SHA at start and at end, the run id, point, step id, kind, target,
hosting, backend, session id where one exists, start and end times,
outcome, a bounded excerpt (a session step's classification excerpt or a
command step's output tail, stored screened through the repository's secret
screen and stripped of non-printable bytes), the full captured output's
cache path where one exists (unscreened), and a skipped step's reason and
detail, a `reuse` or `resume` skip also naming the run id, point, and record
sequence it stands on. A pooled step adds its pool, wait seconds, holders,
and unpooled flag, its start time the take (else the wait's start); a `paths`
step its fingerprint or none and its `args` digest (SHA-256 of `args` as
written); a re-fire its `refire-of`. A legacy record (no end head, or a skip
without a reason code) matches no reuse or resume lookup, never counts
toward a `limited` scan, and renders its free-text reason as written. The runner also writes
one **point-completion record** per point whose list ran, to completion or
to a halt, an empty list included, carrying the point, run id, the head SHA
the list ended on, and the resolver's warnings; a point the matrix parked or
asked, or whose resolution failed, writes none. The in-run points' tables
fold into `/execute-task`'s PR body inside the collapsed audit block
([PR-body assembly](gate-wiring.md#pr-body-assembly)), the current run's
records only, every rendered cell and warning screened and **table-safe**
(markup, pipes, newlines, mentions, and issue-closing keywords neutralized;
paths worktree-relative; layers by name). A point whose list was empty still
emits its table with a single `none` row and its warnings; the turn reports
counts.

## The flip points and their evidence (REQ-E1.3, REQ-E1.6, REQ-J1.2, D-20, D-32)

Any **agent-issued** draft-to-ready flip of a unit PR runs
`steps_pre_ready_flip` on the head to be flipped first and refuses the flip on
a `halted` or `failed` step. Either flip point also refuses on an
**unretired `limited` record** ending on that head, from any run in the
flipping worktree's cache, earlier flip attempts included; it retires once a
later run holds a `passed`, `applied`, or `resume`-skipped record of the
same step id ending there. **The flip targets the head the list ends on**,
and the flip's own checks (the ready-guard's currency check for a unit PR,
the CI gate for the spec PR) check that head. This doctrine authorizes no
flip.

**Evidence.** After the point ends, by completion or by a halt, an empty list
included and whether or not a flip follows, the runner posts a commit status
on the exact head the list ended on, in the base repository the PR targets,
through `step-record.sh status`, reading the records from the worktree the
point ran in. The latest attempt is that flip point's newest completion
record naming the head, in the helper's run-id order; a head with none is
refused, which counts as a failed post. A point the matrix parked or asked,
or whose resolution failed, posts nothing.

| Head branch | Context |
| --- | --- |
| `planwright/<spec>/spec` | `planwright/pre-spec-ready-flip` |
| any other `planwright/` head (`planwright/<spec>/task-<id-or-ids>`, `planwright/flight/<flight-id>`) | `planwright/pre-ready-flip` |

| The records for that head | State |
| --- | --- |
| none of the latest attempt `halted`, `failed`, or `limited` (an empty attempt included; `skipped` and the classified outcomes count as the record says), and no unretired `limited` record of any run | `success` |
| otherwise | `failure` |

The status carries the helper's pinned description and no target URL,
excerpt, or path; a later post on that head and context replaces it. A
failed post, a missing permission included, ends the flip attempt without
a flip, surfaced like a failed step whether or not a flip was to follow and
naming the missing permission. The runner's login
needs commit-status write access: `repo:status` on a classic token, or
**Commit statuses** write on a fine-grained token or app.

**What the status proves.** That its poster ran the point on that head and
no record it counts halted, failed, or stayed limited; not what the steps
did, which the records hold. Written by the actor the hook binds, it guards
a flipper that forgets, not one that forges. The two contexts are
**excluded by name from every CI rollup judgement planwright makes**; an
adopter's own status-consuming tooling still sees them.

**The evidence hook**, gated under custom-steps' Deferred until an in-repo
unit-PR flipper runs the point, will refuse on the ready-guard's flip
surfaces an in-session flip of a `planwright/` head lacking a `success`
status in its branch-table context, deny on a read that errors, and defer on
every other PR and on a fork head; the out-of-session flip is the recovery
path. Until then this doc binds an agent-issued flip.
