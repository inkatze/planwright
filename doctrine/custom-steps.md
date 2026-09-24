# Custom Steps

A unit's execution process exposes **named attachment points**: moments at
which an operator declares, per point and through the four overlay layers
(`core defaults < adopter < repo-tracked < machine-local`), an ordered list of
**steps** to run there. This doc is the one normative home for the point
vocabulary, when each point fires, and the step contract (REQ-A1.5). Skills
carry the invocation; `scripts/resolve-steps.sh` and `scripts/step-record.sh`
carry the mechanics; the operator's own chain lives in their overlay (D-1,
[customization-boundary](customization-boundary.md)).

*The runner* is the session hosting the unit, or the flipper at a flip point,
with the scripts it calls. *Attended* is
[gate-wiring](gate-wiring.md)'s distinction: a human at the prompt versus a
dispatched or unattended worker. *Unit* widens
[spec-format](spec-format.md)'s task-or-bundle sense to the spec bundle and
the flight.

Citations: custom-steps REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5,
REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5, REQ-B1.6, REQ-C1.4, REQ-C1.8,
REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-D1.5, REQ-D1.6, REQ-D1.7,
REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.5, REQ-F1.5, REQ-G1.2, REQ-G1.4 ·
custom-steps D-2, D-3, D-6, D-7, D-8, D-14, D-16, D-17, D-20.

## The point vocabulary

The vocabulary is **core-owned**: every point is a moment inside a skill only
core can wire, so an adopter needing a moment planwright does not name records
an observation, the growth path the other catalogs use, never an overlay point
(REQ-A1.3, D-2).

**Wired in `/execute-task`**, each fired exactly once per unit run (one
`/execute-task` invocation; a re-execution against a unit with an open PR is a
new run and fires them again), in this order (D-3):

| Point | Fires |
| --- | --- |
| `pre-implementation` | after pre-flight passes, before the first implementation commit |
| `pre-ci` | after the last implementation commit, before the first full CI run of the unit run |
| `convergence` | after CI is green: the point resolves, then the once-per-pass `main` sync (merge-currency-guard), then the steps; this list replaces the review chain in place |
| `pre-pr` | after the last convergence step, before the push |
| `post-pr` | after the draft PR exists and its body is assembled |

**Wired in `/spec-kickoff`:** `pre-spec-ready-flip`, after its push and PR
step and before the terminal CI gate, on the head that flip lands on, once per
sign-off that reaches that step, whether or not the flip is configured to
follow (REQ-A1.2).

**Defined here, wired by the first in-repo unit-PR flipper:** `pre-ready-flip`,
immediately before any agent-issued draft-to-ready flip of a unit PR, on the
head to be flipped, once per flip attempt. `/execute-task` never flips, so
nothing wires it yet (REQ-A1.1, REQ-E1.3).

**Named, not wired** (gated under the bundle's Deferred): `spec-drafted`,
`kickoff-signed-off`, `unit-selected`, `pre-dispatch`, `post-dispatch`,
`unit-halted`, `post-merge`, and `orchestrator-idle` (issue 383's `tower-idle`,
renamed with the tower-to-orchestrator glossary supersession). A non-empty
list at one of these is reported as unwired by the resolver and by
`check:steps`, never silently ignored.

**Flights** converge through `steps_convergence` like a task, with unit kind
`flight` (REQ-F1.5).

## The step entry

Steps are entries in the `steps` data catalog, merged across the four layers
by `scripts/resolve-catalog.sh` like every catalog; `supersede: true` is part
of the entry format, never an unknown field (REQ-B1.1). Every value is a
single-line scalar of the constrained reader.

| Field | Value |
| --- | --- |
| `id` | required; `^[a-z][a-z0-9-]*$`, at most 64 bytes, validated before any key or path use; `implementation` is reserved for the unit's own implementation phase and is never a step id |
| `kind` | required; `skill`, `command`, or `prompt` |
| `target` | required; per the kind's grammar below |
| `args` | optional; on a skill, passed to the invocation verbatim and never shell-interpreted; on a command, plain words only (no operators, redirections, expansions, or quoting), so the declared line is one simple command whose words are the same under a shell and as argv; forbidden on a prompt, whose target is the whole prompt |
| `hosting` | optional; `isolated`, `continue`, or `in-session`; default per *Hosting* |
| `on-failure` | optional; `halt` (default) or `continue` |
| `timeout` | optional; a positive integer of seconds, unset meaning no limit; forbidden on an `in-session` skill or prompt step, since the unit session cannot end itself |
| `requires` | optional; space-separated executable names that must be on the path |

**Target grammar (REQ-B1.6).** A skill target is `<name>` or
`<plugin>:<name>`, the slash-command name without its leading slash; a command
target is an executable name or path; a prompt target is non-empty single-line
text. Validation precedes any path or command use; a failing target or args is
malformed for its layer and never interpolated, as is an entry with an unknown
field, an unknown enum value, a missing required field, or an un-honorable
combination above (REQ-B1.2).

**No `env` and no `cwd` field** (D-15). Declarations carry no secrets: a step
needing a credential reads it from the host environment the runner inherits
(REQ-B1.5). Every step runs in the unit's worktree.

**Point lists (REQ-B1.3).** One flat key per point, `steps_<point>` with
hyphens written as underscores (`steps_pre_ci`, `steps_convergence`,
`steps_pre_spec_ready_flip`, and so on, the unwired points included), holds
an inline flow list of step ids. `[]` resolves to no steps and is not
malformed. Core ships `steps_convergence: [polish]` and every other key
empty, so shipped behavior is unchanged. Steps run serially in list order
(D-18); a list naming an id twice is malformed, as is `hosting: continue` at
the first position (no predecessor) or immediately after a command step
hosted `isolated` (a runner subprocess records no session to attach to)
(REQ-B1.4).

## The fixed context (REQ-A1.4, D-14)

Every step receives exactly these ten fields, no more:

| Variable | Field |
| --- | --- |
| `PLANWRIGHT_STEP_SPEC` | the spec identifier |
| `PLANWRIGHT_STEP_TASK_IDS` | the unit's task ids, space-separated; empty for a spec-kind unit |
| `PLANWRIGHT_STEP_UNIT_KIND` | `task`, `spec`, or `flight` |
| `PLANWRIGHT_STEP_BRANCH` | the unit branch |
| `PLANWRIGHT_STEP_BASE_BRANCH` | the base branch (`main` for a spec-kind unit) |
| `PLANWRIGHT_STEP_WORKTREE` | the worktree path |
| `PLANWRIGHT_STEP_PR_NUMBER` | the PR number; empty while none exists, so on a re-execution against an open PR it is set at every point |
| `PLANWRIGHT_STEP_POINT` | the point name |
| `PLANWRIGHT_STEP_ID` | the step id |
| `PLANWRIGHT_STEP_PREV_RECORD` | the preceding step's record path; empty for the first step |

Two channels deliver it. A **command step** gets the variables in its
environment, added to the inherited host environment, an absent value set to
the empty string and **never unset**. A **skill or prompt step** gets the same
fields as a **preamble**, the block `resolve-steps.sh --preamble` renders and
the runner prepends to the step's launch prompt or invocation. No context
value is ever interpolated into a command line (REQ-G1.1). The runner neither
scrubs the inherited environment nor adds any other planwright internal state.

## Hosting (REQ-D1.3, D-7)

| Hosting | Skill step | Prompt step | Command step |
| --- | --- | --- | --- |
| `isolated` | a fresh session through the backend seam (`offload-dispatch`) at the step's tier, the preamble prepended to the invocation as its launch prompt | the same, prepended to the prompt | a runner subprocess running the declared words as argv, output captured to the cache |
| `continue` | the preceding step's session, resumed by its recorded session id, with the same invocation | the same, with the prompt | that session's shell tool, the declared line prefixed by the `PLANWRIGHT_STEP_*` assignments |
| `in-session` | the unit's own session, through its skill tool with the declared `args` | the unit's own session, as its next instruction | the unit session's shell tool, the same prefixed line |

A step with no `hosting` takes `isolated` under `dispatch_isolation: per-step`
and `in-session` under `per-unit`, widening that knob's scope to every step
at every point. A `continue`
step whose predecessor ran `in-session` attaches to the unit's session. A
`continue` step on a backend that cannot resume the predecessor's session, or
whose predecessor was skipped or recorded no session id (an `in-session`
predecessor excepted), does not run: it takes outcome `failed` naming the
backend, the hosting, and the missing predecessor, and its posture applies
(REQ-D1.4); it is never degraded. An `isolated` step on a backend that cannot
spawn a fresh session degrades to `in-session` and records the degradation,
keeping the dispatch-isolation contract. Model and effort come from the
per-step allocation knobs keyed on the step id, one-directional as
model-allocation rules.

## Outcomes, posture, and timeout

Every step ends with exactly one of five outcomes (REQ-D1.1, D-8):

- `passed`: a command exited zero, or a session step's handoff reports no
  change to the branch.
- `applied`: a session step's handoff reports a change to the branch (a
  commit, an applied finding); that report is the discriminator from
  `passed`.
- `halted`: a session step's handoff reports a stop it could not resolve.
- `failed`: a command exited non-zero or timed out; a session ended
  abnormally or reported a safety stop; a `continue` step that could not
  resume.
- `skipped`: produced only by the missing-step matrix, with a skip reason.

**The runner classifies** a skill or prompt step's outcome from the handoff
the step's session returns, and the record carries the excerpt the
classification rests on. A command step's outcome is its exit code alone (the
case `timeout` and `requires` exist for). The runner writes every record,
whatever the hosting.
At `convergence` the review skills' dispositions map onto this set: a normal
exit is `passed` or `applied`; a normal exit carrying a queued meaning-class
spec fork is `halted` (the rule that stops PR creation); a safety stop is
`failed`; an unresolved hard-disqualifier finding is `halted` (REQ-E1.1).

**Posture (REQ-D1.2).** A `halted` or `failed` step whose `on-failure` is
`halt` ends the point; no later step at it runs. At an **in-run point** it
ends the unit through the gate-wiring
[pause protocol](gate-wiring.md#pause-protocol)'s two destinations: an
unattended run parks the unit to `tasks.md` Awaiting input naming the point,
the step, and the outcome; an attended session presents it and waits. At a
**flip point** it refuses the flip and surfaces the step (kickoff records the
pending flip to Awaiting input as its CI gate already does). A posture of
`continue` records the outcome and proceeds to the next step.

**Timeout (REQ-D1.7, D-15).** Where the runner owns the process, it ends the
step at `timeout`; where an `isolated` or `continue` session owns it, the
runner stops the session through the backend seam when the backend exposes a
stop and otherwise stops waiting on it, recording which applied. Either way
the outcome is `failed` naming the timeout; a head moved by a session no
longer waited on is covered by the ready-guard's currency check and the
post-pr draft verification. An `in-session` command step's `timeout` is
passed to the session's shell tool.

## Resolution and the missing-step matrix

A point's list resolves through `config-get` with **last layer wins**, the
resolver warning once per shadowed lower layer, printing provenance per step
on request, and warning once per layer on the retired convergence knob's key
(REQ-C1.1, REQ-C1.2, REQ-C1.6; the resolver's usage header is the operative
contract).

**Resolution completes for the whole point before its first step runs**: a
point either runs its resolved list or runs nothing (REQ-D1.9). Every id must
resolve to a catalog entry and every target on the host under the lookup rules
REQ-C1.3 and D-19 fix, with every `requires` executable on the path
(REQ-D1.8). An id naming no entry, a target the host lacks, or a plugin
registry the resolver cannot read is a step that does not resolve, never an
error.

**The matrix (REQ-C1.4, D-6).** The resolver prints one decision token per
step, keyed on the layer that supplied the **winning list** and on
attendance, which the hosting skill passes explicitly (`--unattended` exactly
when the unit was launched headless; `--attended` otherwise; no default):

| Winning list from | Attended | Unattended |
| --- | --- | --- |
| core default | `park` (a broken install) | `park` |
| repo-tracked | `ask` | `park` |
| adopter or machine-local | `ask` | `skip` |

`run` is a resolved step; `ask` surfaces the missing step and waits; `park`
parks the unit to Awaiting input before any step at the point runs; `skip`
warns and writes a skip record. A malformed list value or entry takes the
by-layer policy instead (REQ-C1.5): core is a broken install (exit 5);
repo-tracked hard-fails (exit 4); an adopter or machine-local **list** warns
and degrades to the core default; an adopter or machine-local **entry** warns
and is skipped, its id then non-resolving under the matrix. `check:steps`
runs the resolver in check mode over every named point of this repository's
own configuration (REQ-H1.4).

## Reserved controls (REQ-D1.6, D-17)

A step **never** merges, marks a PR ready, force-pushes, amends, squashes, or
rebases. A step at the **four no-push points**, `pre-implementation`,
`pre-ci`, `convergence`, and `pre-pr`, never pushes; a step at `post-pr` or
either flip point may. The worker permission denies and the ready-guard keep
enforcing the rewrite and flip controls for every step, the ready-guard on its
**two flip surfaces**, the shell ready command and the GitHub MCP pull-request
update tool; the no-push ordering is doctrine, enforced by no mechanism. After
`post-pr`, if the head moved, the runner regenerates the PR body's
pending-sign-off checklist and per-point tables and verifies the PR is still
a draft, parking the unit naming the step when it is not; earlier points are
never re-run (REQ-E1.2, D-12).

**No recursion (REQ-C1.8).** A step never targets a pipeline entry skill. The
resolver reads the literal list from the `pipeline-entry:` line below and
refuses a matching skill target as malformed for its layer; `tower` is
forward-declared for tower-front-door. The dispatch-entry enum's own
disjointness test targets this refusal.

```text
pipeline-entry: execute-task orchestrate drain spec-draft spec-kickoff offload tower
```

**Permissions (REQ-G).** Catalogs and lists are read only from the human-owned
layers: core and adopter sit outside the worktree and outside a dispatched
worker's write set; repo-tracked and machine-local sit inside it and inherit
the trusted-repository-code posture the guard already extends to `scripts/`;
the worker profile is unchanged (REQ-G1.2). The worker command guard
auto-approves a declared command line as written, allow-only, and nothing
wider (REQ-G1.3). **A skill
step runs under the worker's permission profile like any other skill, with no
elevation** (REQ-G1.4).

## Records (REQ-D1.5, D-16)

Every step leaves a record under `<worktree>/.claude/steps/`, an untracked
cache this repository's ignore list names (adopters add the same line).
Fields: the head SHA at start, the run id (one per unit run or flip attempt),
point, step id, kind, target, hosting, backend, session id where one exists,
start and end times, outcome, a bounded excerpt (the classification excerpt
for a session step, the tail of the captured output for a command step;
screened for secret shapes and non-printable bytes and rendered table-safe),
the full captured output's cache path where one exists, and a skip reason
when skipped. The runner also writes one **point-completion record** per
point it runs, an empty list included, carrying the point, run id, head SHA,
and the resolver's warnings. The per-point tables fold into the PR body's
collapsed audit block ([PR-body assembly](gate-wiring.md#pr-body-assembly)):
a point that ran nothing still emits its table with a single `none` row and
its warnings; the turn reports counts.

## The flip points and their evidence (REQ-E1.3, REQ-E1.5, D-20)

Any **agent-issued** draft-to-ready flip of a unit PR runs
`steps_pre_ready_flip` on the head to be flipped first and refuses the flip on
a `halted` or `failed` step. At either flip point a step that pushes moves the
head; **the flip targets the head the list ends on**, and the flip's own gates
(the ready-guard's currency check for a unit PR, the CI gate for the spec PR)
check that head. This doctrine authorizes no flip.

**Evidence.** After the list completes, an empty list included, the flipper
posts a commit status on the exact head the list ended on, in the base
repository the PR targets, through `step-record.sh status`:

| Head branch | Context |
| --- | --- |
| `planwright/<spec>/spec` | `planwright/pre-spec-ready-flip` |
| any other `planwright/` head (`planwright/<spec>/task-<ids>`, `planwright/flight/<id>`) | `planwright/pre-ready-flip` |

| The latest attempt's records for that head | State |
| --- | --- |
| none `halted` or `failed` (an empty attempt included; `skipped` and the classified outcomes count as the record says) | `success` |
| any `halted` or `failed` | `failure` |

A later post on the same head and context replaces the earlier one. A post
that fails, a missing permission included, ends the flip attempt without a
flip, surfaced like a failed step. The flipper's login needs commit-status
write access: the `repo:status` scope on a classic token, or the repository's
**Commit statuses** write permission on a fine-grained token or app.

**What the status proves.** That the actor who posted it ran the point on
that head and no record of the latest attempt halted or failed. Not what the
steps did: the PR-body table is the human record, and the status is written
by the same actor the hook binds, so it guards a flipper that forgets, not
one that forges. The two contexts are
**excluded by name from every CI rollup judgement planwright makes**, so a
flip point's own status never counts as a completed check; adopters' own
status-consuming tooling sees them.

**The evidence hook**, gated under the bundle's Deferred until an in-repo
unit-PR flipper runs the point, will sit on the ready-guard's two flip
surfaces and refuse an in-session flip of a `planwright/` head lacking the
`success` status the mapping above requires, denying on a read that errors
and deferring on every other PR and on a fork head; the out-of-session flip
is the recovery path. Until it lands, this doc is what binds a hand flip.
