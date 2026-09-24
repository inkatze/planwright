# Custom Steps

A unit's execution process exposes **named attachment points**: moments at
which an operator declares, per point and through the overlay layers
(`core defaults < adopter < repo-tracked < machine-local`), an ordered list of
**steps** to run there. This doc is the one normative home for the point
vocabulary, when each point fires, and the step contract (REQ-A1.5, D-9).
Skills carry the invocation; `scripts/resolve-steps.sh` and
`scripts/step-record.sh` carry the mechanics, their usage headers pinning
what this doc delegates to them (the resolver's line format and usage-error
exit, the preamble and prefix rendering with its quoting grammar, the run id
and its ordering, the excerpt bound and the secret screen's action, the
rendered columns, the status description and target); the operator's own
chain lives in their overlay (D-1,
[customization-boundary](customization-boundary.md)).

*The runner* is the session hosting the unit, or the flipper at a flip point,
with the scripts it calls. *Attended* narrows [gate-wiring](gate-wiring.md)'s
pause-protocol distinction to the backend seam's launch record: a headless
launch is unattended, any other attended. *Unit* widens
[spec-format](spec-format.md)'s task-or-bundle sense to the spec bundle and
the flight (D-13); a *unit run* is one `/execute-task` invocation, a flight's
convergence, or a flip point's firing.

Citations: custom-steps REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5,
REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5, REQ-B1.6, REQ-C1.1,
REQ-C1.2, REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.6, REQ-C1.7, REQ-C1.8,
REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-D1.5, REQ-D1.6, REQ-D1.7,
REQ-D1.8, REQ-D1.9, REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.5, REQ-F1.5,
REQ-G1.1, REQ-G1.2, REQ-G1.3, REQ-G1.4, REQ-H1.3, REQ-H1.4, REQ-H1.5 ·
custom-steps D-1, D-2, D-3, D-4, D-5, D-6, D-7, D-8, D-9, D-10, D-11, D-12,
D-13, D-14, D-15, D-16, D-17, D-18, D-19, D-20 · tower-front-door REQ-H1.1.

## The point vocabulary

The vocabulary is **core-owned**: every point is a moment inside a skill only
core can wire, so an adopter needing a moment planwright does not name records
an observation, never an overlay point (REQ-A1.3, D-2). A point name outside
this vocabulary is a resolver usage error.

**Wired in `/execute-task`** (the *in-run points*), each fired once when the
run reaches it and never again in that run (a re-execution against a unit
with an open PR is a new run, REQ-A1.1, REQ-A1.4), in this order (D-3):

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

**Defined here, wired by the first in-repo unit-PR flipper:** `pre-ready-flip`,
immediately before any agent-issued draft-to-ready flip of a unit PR, on the
head to be flipped, once per flip attempt. `/execute-task` never flips, so
nothing wires it yet; it is not an unwired point (REQ-A1.1, REQ-E1.3, D-2).

**Named, not wired** (gated under custom-steps' Deferred): `spec-drafted`,
`kickoff-signed-off`, `unit-selected`, `pre-dispatch`, `post-dispatch`,
`unit-halted`, `post-merge`, and `orchestrator-idle` (issue 383's
`tower-idle`, in the orchestrator sense tower-front-door REQ-H1.1 fixes). A
non-empty list at one of these resolves no steps and is reported as unwired
by the resolver when that point is resolved and by `check:steps`, never
silently ignored.

**Flights.** Any skill that converges a flight reads `steps_convergence` with
unit kind `flight` (REQ-F1.5).

## The step entry

Steps are entries in the `steps` data catalog, merged across the overlay
layers by `scripts/resolve-catalog.sh` like every catalog; `supersede: true`
is part of the entry format, never an unknown field (REQ-B1.1, D-4). Every
value is a single-line scalar of the constrained reader. Core ships the
`polish` and `self-review` entries.

| Field | Value |
| --- | --- |
| `id` | required; `^[a-z][a-z0-9-]*$`, at most 64 bytes, validated before any key or path use; `implementation` is reserved for the unit's own implementation phase and is never a step id |
| `kind` | required; `skill`, `command`, or `prompt` |
| `target` | required; per the kind's grammar below |
| `args` | optional; on a skill, passed to the invocation verbatim and never shell-interpreted; on a command, plain words only (no operators, redirections, expansions, or quoting), so the declared line is one simple command whose words are the same under a shell and as argv; forbidden on a prompt, whose target is the whole prompt |
| `hosting` | optional; `isolated`, `continue`, or `in-session`; default per *Hosting* |
| `on-failure` | optional; `halt` (default) or `continue` |
| `timeout` | optional; a positive integer of seconds, unset meaning no limit beyond a hosting tool's own; forbidden on an `in-session` skill or prompt step, since the unit session cannot end itself |
| `requires` | optional; space-separated executable names in the command-target charset |

**Target grammar (REQ-B1.6).** A skill target is `<name>` or
`<plugin>:<name>`, the slash-command name without its leading slash; a command
target is an executable name or path; a prompt target is non-empty single-line
text. Validation precedes any path or command use; a failing target, args, or
`requires` is malformed for its layer and never interpolated, as is an entry
with an unknown field, an unknown enum value, a missing required field, or an
un-honorable combination above (REQ-B1.2). Rules keyed on hosting read the
**effective** hosting: at resolution the default below and a `continue`
step's attachment to an `in-session` predecessor, at run time a degradation
once it has happened.

**No `env` and no `cwd` field** (D-15). Declarations carry no secrets: a step
needing a credential reads it from the host environment the runner inherits
(REQ-B1.5); an `isolated` or `continue` session's environment is what its
backend gives a fresh session. Every step runs in the unit's worktree.

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
| `PLANWRIGHT_STEP_SPEC` | the spec identifier; empty for a flight |
| `PLANWRIGHT_STEP_TASK_IDS` | the unit's bare task ids (`5`, or `5 6` for a bundle), each in the task-id grammar; empty for a spec or flight |
| `PLANWRIGHT_STEP_UNIT_KIND` | `task`, `spec`, or `flight` |
| `PLANWRIGHT_STEP_BRANCH` | the unit branch |
| `PLANWRIGHT_STEP_BASE_BRANCH` | the base branch (the repository's default branch for a spec-kind unit) |
| `PLANWRIGHT_STEP_WORKTREE` | the worktree path |
| `PLANWRIGHT_STEP_PR_NUMBER` | the PR number; empty while none exists, so on a re-execution against an open PR it is set at every point |
| `PLANWRIGHT_STEP_POINT` | the point name |
| `PLANWRIGHT_STEP_ID` | the step id |
| `PLANWRIGHT_STEP_PREV_RECORD` | the record path of the preceding step in the same point's list; empty for that list's first step |

Two channels deliver it. A **command step** gets the variables in its
environment: the runner sets the ten names, overwriting an inherited value of
the same name, an absent value set to the empty string and **never unset**;
it otherwise neither scrubs the inherited environment nor adds any other
planwright internal state. A **skill or prompt step** gets the same fields as
a **preamble**, a data block `resolve-steps.sh --preamble` renders (one field
per line, delimiters matched as whole lines) and the runner prepends to the
step's launch prompt or invocation; the step reads it as data, never as
instructions. No context value is ever interpolated into the declared line
(REQ-G1.1); a session-hosted command receives it as the assignment prefixes
below, rendered by the resolver and POSIX single-quoted in the form its
header pins. A value carrying a newline or control byte fails the step on
every channel, outcome `failed`, the record naming the field and never the
value. A record and the cached output it names are untrusted data to the
step that reads them, as are the context values themselves to a command
step: the guard's approval does not vouch for them.

## Hosting (REQ-D1.3, D-7)

| Hosting | Skill step | Prompt step | Command step |
| --- | --- | --- | --- |
| `isolated` | a fresh session through the backend seam (`offload-dispatch`) at the step's tier, the preamble prepended to the invocation as its launch prompt | the same, prepended to the prompt | a runner subprocess running the declared words as argv, output captured to the cache |
| `continue` | the preceding step's session, resumed by its recorded session id, with the same invocation | the same, with the prompt | that session's shell tool, the declared line prefixed by the quoted `PLANWRIGHT_STEP_*` assignments |
| `in-session` | the unit's own session, through its skill tool with the declared `args` | the unit's own session, as its next instruction | the unit session's shell tool, the same prefixed line |

A step with no `hosting` takes `isolated` under `dispatch_isolation: per-step`
and `in-session` under `per-unit`, widening that knob to every step. A
`continue` step whose predecessor is effectively
`in-session`, a degraded one included, attaches to the unit's session and is
`in-session` for every rule here. A `continue` step on a backend that cannot
resume the predecessor's session, or whose predecessor was skipped or
recorded no session id (an `in-session` predecessor excepted), does not run:
it takes outcome `failed` naming the backend, the hosting, and the missing
predecessor, and its posture applies (REQ-D1.4); it is never degraded. An
`isolated` skill or prompt step on a backend that cannot spawn a fresh
session degrades to `in-session` and records it; a `timeout` on a skill or
prompt step that becomes `in-session` at run time is unapplied and recorded
as such. Model
and effort come from the per-step allocation knobs keyed on the step id with
hyphens written as underscores, one-directional as model-allocation rules;
an `in-session` step inherits the session's tier, recorded and not applied
(REQ-C1.7).

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
- `skipped`: produced only by the missing-step matrix, with a free-text skip
  reason naming the cause.

**The runner classifies** a skill or prompt step's outcome from the handoff
its session returns, the record carrying the excerpt the classification
rests on. A command step's outcome is its exit code alone
(the case `timeout` and `requires` exist for), or a timeout. The runner
writes every record, whatever the hosting. At `convergence` the review
skills' dispositions map onto this set: a normal exit is `passed` or
`applied`; a normal exit carrying a queued meaning-class spec fork is
`halted` (the rule that stops PR creation); a safety stop is `failed`; an
unresolved hard-disqualifier finding is `halted` (REQ-E1.1).

**Posture (REQ-D1.2).** A `halted` or `failed` step whose `on-failure` is
`halt` ends the point; no later step at it runs. At an **in-run point** it
ends the unit through the gate-wiring
[pause protocol](gate-wiring.md#pause-protocol)'s destinations: an unattended
run parks the unit to `tasks.md` Awaiting input; an attended session presents
it and waits for direction. At a **flip point** it refuses the flip and
surfaces the step (kickoff records the pending flip to Awaiting input as its
CI gate already does).
Every Awaiting-input entry this doc causes names only the point, the
validated step ids, the outcome, token, or
cause (a failed post's missing permission, a PR no longer a draft), and the
record path relative to the worktree where one exists, never a target's text
or an excerpt. A posture of `continue` records the outcome and proceeds to
the next step; posture governs the list only, and the PR-creation stop, the
flip refusal, and the evidence below read the records whatever the posture.

**Timeout (REQ-D1.7, D-15).** Where the runner owns the process, it ends the
step at `timeout`; where an `isolated` or `continue` session owns it, the
runner stops the session through the backend seam when the backend exposes a
stop and otherwise stops waiting on it, recording which applied. Either way
the outcome is `failed` naming the timeout; a head moved by a session no
longer waited on is covered by the ready-guard's currency check and the
post-pr draft verification. An `in-session` command step's `timeout` is
passed to the session's shell tool, within that tool's limit.

## Resolution and the missing-step matrix

A point's list resolves through `config-get` with **last layer wins**, the
resolver printing one warning naming every lower layer that sets the key
whatever its value, provenance per step (the hosting, its default applied)
on request,
and one warning per layer on the retired convergence knob's key (REQ-C1.1,
REQ-C1.2, REQ-C1.6, D-5, D-10).

**Resolution completes for the whole point before its first step runs**: a
point either runs its resolved list or runs nothing (REQ-D1.9). Every id must
resolve to a catalog entry and every target on the host under the lookup rules
REQ-C1.3 and D-19 fix, with every `requires` executable on the path
(REQ-D1.8). An id naming no entry, a target the host lacks, a `requires`
executable off the path, or a plugin registry the resolver cannot read is a
step that does not resolve, never an error.

**The matrix (REQ-C1.4, D-6).** The resolver prints one decision token per
step, keyed on the layer that supplied the **winning list** and on
attendance, which the hosting skill passes explicitly (`--unattended` exactly
when the unit was launched headless, per the backend seam's launch record;
`--attended` otherwise; neither flag, or both, is a usage error):

| Winning list from | Attended | Unattended |
| --- | --- | --- |
| core default | `park` (a broken install) | `park` |
| repo-tracked | `ask` | `park` |
| adopter or machine-local | `ask` | `skip` |

`run` is a resolved step; `ask` surfaces the missing step and waits, the
human either repairing and re-resolving or ending the unit; `park` parks the
unit to Awaiting input before any step at the point runs; `skip` warns and
writes a skip record. The resolver exits per REQ-H1.3: 0 when every step is `run` (a
`skip` under REQ-C1.4 included), 1 when the point runs nothing (`park` or
`ask`). A malformed list value or entry takes
the by-layer policy instead (REQ-C1.5): core is a broken install (exit 5);
repo-tracked hard-fails (exit 4); an adopter or machine-local **list** warns
and degrades to the core default; an adopter or machine-local **entry**
warns and is dropped from the merged catalog, its id then non-resolving
under the matrix. Check mode (`--check` with `--unattended`) exits
non-zero on any `park`, any malformation, or an unwired non-empty list, and
passes with a warning on an adopter or machine-local `skip` (REQ-H1.3,
REQ-A1.3); `check:steps` runs it over every named point of this repository's
own configuration (REQ-H1.4).

## Reserved controls (REQ-D1.6, D-17)

A step **never** merges, marks a PR ready, force-pushes, amends, squashes, or
rebases. A step at the **four no-push points**, `pre-implementation`,
`pre-ci`, `convergence`, and `pre-pr`, never pushes; a step at `post-pr` or
either flip point may. The worker permission denies and the ready-guard keep
applying to every session-hosted step as to everything else, the ready-guard
on its flip surfaces (the shell ready command and the GitHub MCP pull-request
update tool); a runner subprocess sees no hook, so these controls bind it by
declaration alone, and the no-push ordering is doctrine, enforced by no
mechanism. After `post-pr`'s list completes, the runner re-emits the
per-point
tables through the PR-body assembly (post-pr's included) and verifies the PR
is still a draft, parking the unit to Awaiting input naming the post-pr
steps that ran when it is not; if the head moved it also regenerates the
pending-sign-off checklist from the final range and re-emits the review
handoff; earlier points are never re-run (REQ-E1.2, D-12).

**No recursion (REQ-C1.8).** A step never targets a pipeline entry skill,
matched on the name after any `<plugin>:` prefix; a match is malformed for
its layer, the message naming `pipeline-entry` and the matched name. The
resolver reads the list from `<script-dir>/../doctrine/custom-steps.md`,
the self-location path with no environment arm, never through
`resolve-rule-doc.sh`; in planwright's own repository that file shares the
trusted-repository-code posture of `scripts/`. Exactly one line beginning
`pipeline-entry:` at column zero, tokens split on single spaces and each in
the id charset; a missing or duplicated line or a bad token is a broken
install. `tower` is forward-declared for
tower-front-door. The dispatch-entry disjointness checks target this
refusal.

```text
pipeline-entry: execute-task orchestrate drain spec-draft spec-kickoff offload tower
```

**Permissions (D-11).** Catalogs and lists are read only from the
human-owned layers: core and adopter sit outside the worktree and outside a
dispatched worker's write set; repo-tracked and machine-local sit inside it
and inherit the trusted-repository-code posture the guard already extends to
`scripts/`; the worker profile is unchanged (REQ-G1.2). The worker command
guard auto-approves, allow-only, a segment whose word sequence, after
stripping leading assignments whose names are among the ten context names
and whose form is the resolver's exact output, equals a command target from
any well-formed catalog entry at any layer followed by its `args` as written,
once the
target passes the guard's charset and path checks; a segment sharing only
the first word is not approved (REQ-G1.3). **A skill step runs under the
worker's permission profile like any other skill, with no elevation**, an
`isolated` session under the profile its backend gives any session it spawns
(REQ-G1.4).

## Records (REQ-D1.5, D-16)

Every step leaves a record under `<worktree>/.claude/steps/`, an untracked
cache the repository's ignore list names (adopters add the same line), keyed
by a run id the helper issues; planwright reads records only through the
helper, and a step reading the record `PREV_RECORD` names treats its form as
unstable. Fields: the head SHA at start, the run id, point, step id,
kind, target, hosting, backend, session id where one exists, start and end
times, outcome, a bounded excerpt (the classification excerpt for a session
step, the tail of the captured output for a command step, stored screened
through the repository's secret screen and stripped of non-printable bytes),
the full captured output's cache path where one exists (that output stays
unscreened in the cache), and a skip reason when skipped. The runner also
writes one **point-completion record** per point whose list ran, to
completion or to a halt, an empty list included, carrying the point, run id,
the head SHA the list ended on, and the resolver's warnings; a point the
matrix parked or asked, or whose resolution failed, writes none. The in-run
points' tables fold into `/execute-task`'s PR body inside the collapsed
audit block
([PR-body assembly](gate-wiring.md#pr-body-assembly)), the current run's
records only, with every rendered cell and warning screened and
**table-safe** (markup, pipes, and newlines neutralized, mentions and
issue-closing keywords too, paths relative to the worktree, layers by name).
A point whose list was empty still emits its table with a single `none` row
and its warnings; the turn reports counts.

## The flip points and their evidence (REQ-E1.3, REQ-E1.5, D-20)

Any **agent-issued** draft-to-ready flip of a unit PR runs
`steps_pre_ready_flip` on the head to be flipped first and refuses the flip on
a `halted` or `failed` step. At either flip point a step that pushes moves the
head; **the flip targets the head the list ends on**, and the flip's own checks
(the ready-guard's currency check for a unit PR, the CI gate for the spec PR)
check that head. This doctrine authorizes no flip.

**Evidence.** After the point ends, by completion or by a halt, an empty list
included and whether or not a flip follows, the runner posts a commit status
on the exact head the list ended on, in the base repository the PR targets,
through `step-record.sh status`, which reads the records from the worktree
the point ran in. The latest attempt is that flip point's newest completion
record naming the head, in the helper's run-id order; a head with none is
refused, which counts as a failed post. A point the matrix parked or asked,
or whose resolution failed, posts nothing.

| Head branch | Context |
| --- | --- |
| `planwright/<spec>/spec` | `planwright/pre-spec-ready-flip` |
| any other `planwright/` head (`planwright/<spec>/task-<id-or-ids>`, `planwright/flight/<flight-id>`) | `planwright/pre-ready-flip` |

| The latest attempt's records for that head | State |
| --- | --- |
| none `halted` or `failed` (an empty attempt included; `skipped` and the classified outcomes count as the record says) | `success` |
| any `halted` or `failed` | `failure` |

The status carries the description and target the helper's header pins,
never an excerpt or a local path. A later post on the same head and context
replaces the earlier one. A post that fails, a missing permission included,
ends the flip attempt without a flip, surfaced like a failed step whether or
not a flip was to follow, naming the missing permission. The runner's login
needs commit-status write access: the `repo:status` scope (or the wider
`repo`) on a classic token, or the repository's **Commit statuses** write
permission on a fine-grained token or app.

**What the status proves.** That its poster ran the point on that head and
no record of the latest attempt halted or failed; not what the steps did,
which the records hold (the PR-body table where one is folded). Written by
the actor the hook binds, it guards a flipper that forgets, not one that
forges. The two contexts are
**excluded by name from every CI rollup judgement planwright makes**, so a
flip point's own status never counts as a completed check; adopters' own
status-consuming tooling sees them.

**The evidence hook**, gated under custom-steps' Deferred until an in-repo
unit-PR flipper runs the point, will sit on the ready-guard's flip surfaces
and refuse an in-session flip (one issued through those surfaces) of a
`planwright/` head lacking a `success` status in the context the branch
table assigns it, denying on a read that errors and deferring on every other
PR and on a head repository differing from its base; the out-of-session flip
is the recovery path. Until then this doc binds an agent-issued flip.
