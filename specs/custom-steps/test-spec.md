# Custom steps — Test Spec

**Status:** Draft
**Last reviewed:** 2026-09-22
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` where automation is honest (the resolver, the
record helper, the guard fixture rows, and the repository's existing
options, links, doctrine-index, manifest, instruction-budget, and shell
checks, all run by `mise run check` and the repository CI); `[Gherkin]` for
the skill-wired behaviors a fixture overlay exercises end to end on the
terminal rung, recorded in the PR body; `[design-level]` where a rule's
presence in the named doc or row is the verification; `[manual]` for the
one behavior that needs a live session-grade backend.

## REQ-A — Named attachment points

### REQ-A1.1 — The wired points fire once, in order [Gherkin + test]

Scenario: given a fixture overlay declaring one command step at each in-run
point, when a unit runs on the terminal rung, then the step records show
each of those points exactly once, in the D-3 order. The resolver test also
asserts every wired point name resolves and any other name is refused. The
flip-attempt point is verified under REQ-E1.3. Task 5, Task 2.

### REQ-A1.2 — The spec-PR flip point [Gherkin]

Scenario: given a fixture overlay declaring a failing command step at
`pre-spec-ready-flip`, when a clean kickoff reaches its terminal flip, then
the flip is refused and the Awaiting-input entry names the step. Scenario:
given the default empty list, when the same kickoff runs, then the flow is
unchanged. Task 6.

### REQ-A1.3 — Unwired points are named and warned [test + design-level]

The rule doc lists the unwired names REQ-A1.3 names. The resolver test
asserts a non-empty list for an unwired point prints the unwired warning
and resolves nothing. Task 1, Task 2.

### REQ-A1.4 — The fixed context set [Gherkin + test]

Scenario: given a command step that prints its environment, when it runs at
`post-pr`, then exactly the ten `PLANWRIGHT_STEP_*` fields are present and
the PR number is set; at `pre-ci` the PR number is empty. The resolver test
asserts the preamble renders the same ten fields. Task 5, Task 2.

### REQ-A1.5 — One normative home [design-level + test]

`doctrine/custom-steps.md` exists, the doctrine index lists it, and
`/execute-task`'s manifest declares it point-of-use; `check:doctrine-index`
and `check:doctrine-manifest` pass. Task 1, Task 5.

## REQ-B — Step declaration

### REQ-B1.1 — The steps catalog kind [test]

The resolver test places a step entry in each layer's catalog location and
asserts the merged catalog carries all of them, with a `supersede: true`
overlay entry replacing the core `polish` entry. Task 2.

### REQ-B1.2 — Entry fields and enums [test]

Fixtures: an entry with every field resolves; an unknown field, an unknown
kind, an unknown hosting, a non-integer timeout, and a missing target are
each malformed, with the by-layer policy applied per the layer that
supplied them. Task 2.

### REQ-B1.3 — One flat key per point with the shipped defaults [test]

With no overlay, `steps_convergence` resolves to `polish` and every other
key to an empty list; `check:options` finds a row per key. Task 2, Task 3.

### REQ-B1.4 — Serial order, no duplicates, no leading continue [test]

Fixtures: a list is emitted in declared order; a repeated id is malformed;
a first-position `continue` is malformed. Task 2.

### REQ-B1.5 — No secrets in declarations [design-level]

The entry format defines no environment field and the overlay
documentation states where a credential comes from. Task 1, Task 3.

### REQ-B1.6 — Target grammar per kind [test]

Fixtures: a skill target with a namespace and without; a command target as
a name and as a path; an empty prompt refused; a target carrying a shell
metacharacter or traversal segment refused before any filesystem probe.
Task 2.

## REQ-C — Resolution

### REQ-C1.1 — Last layer wins with a shadow warning [test]

Fixtures: lists at two layers resolve to the higher one and the warning
names the lower; lists at one layer print no warning. Task 2.

### REQ-C1.2 — Provenance [test]

`--explain` prints one line per step carrying point, id, list layer, entry
layer, target, and hosting. Task 2.

### REQ-C1.3 — Resolvability on the host [test]

Fixtures under a temporary home: a skill under the plugin skills root, a
user command file, a project skill directory, a command on the path, a
command at a path, and a prompt each resolve; each one absent does not;
`requires` naming an absent executable does not; a `--nested` argument is
passed through unexamined. Task 2.

### REQ-C1.4 — The missing-step matrix [test]

Fixtures for every cell: attended prints `ask` at each layer; unattended
prints `park` for a repo-tracked list and `skip` with a warning for an
adopter or machine-local list; a core-default step made unresolvable prints
`park` at both attendances; check mode exits non-zero in every case.
Task 2.

### REQ-C1.5 — Structural malformation by layer [test]

A malformed list in the repo-tracked layer exits 4; in the adopter layer it
warns and resolves the core default. Task 2.

### REQ-C1.6 — The stale key warns and is ignored [test]

`review_sequence` set at each layer produces one warning naming that layer
and `steps_convergence`, and the resolved chain is unaffected. Task 2.

### REQ-C1.7 — Tier from the step-id-keyed knobs [test]

The existing allocation test's step-tier case is extended with a step id
that is neither `polish` nor `self-review` and resolves to `inherit`
unconfigured and to the configured tier when set. Task 2.

### REQ-C1.8 — No pipeline-entry targets [test]

Each pipeline-entry skill name as a skill target is refused with a message
naming the rule. Task 2.

## REQ-D — Execution contract

### REQ-D1.1 — Outcomes [Gherkin + test]

Scenario: given a command step exiting zero, then its record reads
`passed`; exiting non-zero, `failed`. Scenario: given a prompt step whose
handoff reports findings applied, when the host classifies it, then the
record reads `applied` and carries the excerpt. The record helper test
asserts the outcome enum is closed. Task 5, Task 4.

### REQ-D1.2 — Posture and the pause protocol [Gherkin]

Scenario: given a failing step with the default posture on an unattended
run, then the unit parks to Awaiting input naming point, step, and outcome,
and no later step at that point runs. Scenario: given posture `continue`,
then the failure is recorded and the next step runs. Task 5.

### REQ-D1.3 — Hosting modes [Gherkin + manual]

Scenario: given a command step with `in-session`, then the unit session
executes it and its output appears in the session. Manual, recorded in the
PR body: on a stream-json worker, a skill step with `isolated` runs in a
fresh session whose id the record carries, and a following `continue` step
resumes that id. Task 5.

### REQ-D1.4 — Continue without resume fails [Gherkin]

Scenario: given a `continue` step on the terminal rung, then it does not
run, its record reads `failed` naming the backend and hosting, and its
posture applies. Task 5.

### REQ-D1.5 — Records and the PR fold [test]

The record helper test round-trips every field, renders the per-point
table, and the rendered table appears inside the collapsed audit block of
a fixture PR body. Task 4.

### REQ-D1.6 — Reserved controls [design-level + test]

The rule doc states the controls; the worker deny rules and ready-guard are
unchanged, verified by their existing tests still passing. Task 1.

### REQ-D1.7 — Timeout [Gherkin]

Scenario: given a command step sleeping past its `timeout`, then the
runner ends it, the record reads `failed` naming the timeout, and the
posture applies. Task 5.

### REQ-D1.8 — Missing requires [test]

Covered by the REQ-C1.3 and REQ-C1.4 fixtures: an absent `requires`
executable takes the matrix path. Task 2.

### REQ-D1.9 — Whole-point resolution [test]

A list with one unresolvable step in unattended repo-tracked mode prints
`park` for the point and `run` for no step. Task 2.

## REQ-E — The review points

### REQ-E1.1 — Convergence contract [Gherkin + test]

Scenario: given the shipped defaults, when a unit converges, then exactly
one polish step runs after the main sync, and its audit record folds into
the PR body as before. The existing converge-sync test still passes.
Task 5.

### REQ-E1.2 — Post-pr regeneration and draft check [Gherkin + test]

Scenario: given a post-pr command step that commits and pushes, when the
list completes, then the PR body's checklist is regenerated from the new
range. Scenario: given a post-pr step that un-drafts the PR, then the unit
parks naming the step. The record helper test covers `regenerate` over a
fixture range. Task 5, Task 4.

### REQ-E1.3 — Pre-ready-flip contract [design-level + test]

The rule doc states that any agent-issued unit flip runs the point first;
the resolver test resolves `pre-ready-flip` like every other point. No
in-repo flipper of unit PRs exists to exercise it end to end; the rule
binds the first one that lands. Task 1, Task 2.

### REQ-E1.4 — Briefs cite keys [design-level]

`/orchestrate`'s dispatch prose names the point keys and no list. Task 5.

## REQ-F — Replacement of the review-sequence knob

### REQ-F1.1 — Removal [test]

`config/defaults.yml` has no `review_sequence`; the old resolver and its
test are absent; the convergence prose names `steps_convergence`. Task 3,
Task 5.

### REQ-F1.2 — Repo config migrated [test]

`.claude/planwright.yml` carries `steps_convergence: [self-review]` and
`check:steps` resolves it. Task 3, Task 8.

### REQ-F1.3 — Surface sweep [test]

The grep the task's Done-when defines returns only the stale-key warning
site. Task 3.

### REQ-F1.4 — Allocation knobs unchanged [test]

The existing allocation tests pass unmodified; the options rows describe
the knobs as step-id-keyed. Task 3.

### REQ-F1.5 — Flights read the convergence list [design-level]

No flight skill ships yet; the rule doc states that a flight converges
through `steps_convergence` with unit kind `flight`, and the first flight
skill that lands cites it. Task 1, Task 3.

## REQ-G — Security and permissions

### REQ-G1.1 — Context by environment only [test + Gherkin]

The resolver test asserts a declared command line is emitted byte-for-byte;
the REQ-A1.4 scenario shows the fields in the environment and none in the
command. Task 2, Task 5.

### REQ-G1.2 — Human-owned layers [design-level + test]

The worker profile carries no allow rule matching a write under
`.claude/catalogs`, `.claude/catalogs.local`, or the config files; a test
asserts the absence over the shipped profile. Task 7.

### REQ-G1.3 — Guard approval of declared targets [test]

Three fixture rows: a declared target approved, a non-declared command
deferred, a declared target failing containment deferred. Task 7.

### REQ-G1.4 — No elevation for skill steps [design-level]

The rule doc states it and the profile is unchanged for skills. Task 1.

## REQ-H — Documentation, tooling, and guards

### REQ-H1.1 — Options rows [test]

`check:options` passes. Task 3.

### REQ-H1.2 — Overlay documentation [design-level]

`docs/overlays.md` describes the catalog and the worked example shows a
per-user entry used by a per-project list. Task 3.

### REQ-H1.3 — Resolver and record commands [test]

Covered by the resolver and record helper tests. Task 2, Task 4.

### REQ-H1.4 — The check:steps guard and the budget [test]

`mise run check` runs `check:steps`; the failing fixture exits non-zero;
`check:instructions` passes on every skill edit. Task 8, Task 5, Task 6.

### REQ-H1.5 — Index and manifests [test]

`check:doctrine-index` and `check:doctrine-manifest` pass. Task 1, Task 5.
