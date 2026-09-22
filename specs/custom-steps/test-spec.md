# Custom steps — Test Spec

**Status:** Ready
**Last reviewed:** 2026-09-22
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` where automation is honest (the resolver, the
record helper, the guard fixture rows, and the repository's existing
options, links, doctrine-index, instruction-budget, and shell checks, all
run by `mise run check` and the repository CI); `[Gherkin]` for the
skill-wired behaviors a fixture overlay exercises end to end on the
terminal rung, recorded in the PR body; `[design-level]` where a rule's
presence in the named doc or row is the verification; `[manual]` for the
one behavior that needs a live session-grade backend. Every Gherkin
fixture overlay lives in the adopter layer, supplied through the config
and catalog readers' adopter-root override, so the fixture never enters
the repo-tracked layer `check:steps` judges.

## REQ-A — Named attachment points

### REQ-A1.1 — The wired points fire once, in order [Gherkin + test]

Scenario: given a fixture overlay declaring one command step at each in-run
point, when a unit runs on the terminal rung, then the step records show
each of those points exactly once, in the D-3 order, `pre-ci` before the
first CI run. The resolver test also asserts every named point resolves
and any other name is refused. The flip-attempt point is verified under
REQ-E1.3. Task 5, Task 2.

### REQ-A1.2 — The spec-PR flip point [Gherkin]

Scenario: given a fixture overlay declaring a failing command step at
`pre-spec-ready-flip`, when a clean kickoff reaches its terminal flip, then
the flip is refused and the Awaiting-input entry names the step. Scenario:
given the default empty list, when the same kickoff runs, then the flow is
unchanged apart from the posted status (REQ-E1.5). Scenario: given the
ready-flip opt-out, when the kickoff reaches the push and PR step, then
the point still fires and posts. Task 6.

### REQ-A1.3 — Unwired points are named and warned [test + design-level]

The rule doc lists the unwired names and the vocabulary's ownership. The
resolver test asserts a non-empty list for an unwired point prints the
unwired warning and resolves nothing; the `check:steps` fixture fails on
it. Task 1, Task 2, Task 8.

### REQ-A1.4 — The fixed context set [Gherkin + test]

Scenario: given a command step that prints its environment, when it runs at
`post-pr`, then exactly the `PLANWRIGHT_STEP_*` variables REQ-A1.4 names
are present, the PR number set, and the rest of the host environment
intact; on a first run at `pre-ci` the PR number is set to the empty
string, and on a re-execution it carries the existing PR. The resolver
test asserts `--preamble` renders the same fields. Task 5, Task 2.

### REQ-A1.5 — One normative home [design-level + test]

`doctrine/custom-steps.md` exists, the doctrine index lists it, and
`/execute-task`'s manifest declares it point-of-use; `check:doctrine-index`
passes and `check:instructions`' manifest-resolution pass finds the doc
named in the skill body. Task 1, Task 5.

## REQ-B — Step declaration

### REQ-B1.1 — The steps catalog kind [test]

The resolver test places a step entry in each layer's catalog location and
asserts the merged catalog carries all of them, with a `supersede: true`
overlay entry replacing the core `polish` entry and `supersede` never
reported as an unknown field. Task 2.

### REQ-B1.2 — Entry fields and enums [test]

Fixtures: an entry with every field resolves; an unknown field, an unknown
kind, an unknown hosting, a non-integer timeout, a missing target, an id
with a leading digit or an uppercase letter, the id `implementation`, a
`timeout` on an `in-session` skill step, and `args` on a `prompt` step are
each malformed, with the by-layer policy applied per the layer that
supplied them; a `timeout` on an `in-session` command step resolves.
Task 2.

### REQ-B1.3 — One flat key per point with the shipped defaults [test]

With no overlay, `steps_convergence` resolves to `polish` and every other
named key to an empty list with exit 0; an explicit `[]` at any layer
resolves to no steps without a malformed warning; `check:options` finds a
row per key. Task 2.

### REQ-B1.4 — Serial order, no duplicates, no leading continue [test]

Fixtures: a list is emitted in declared order; a repeated id is malformed;
a first-position `continue` is malformed; a `continue` immediately after an
`isolated` command step is malformed, and one after an `in-session` command
step resolves and prints hosting `in-session`. Task 2.

### REQ-B1.5 — No secrets in declarations [design-level]

The entry format defines no environment field (the rule doc), and the
overlay documentation states that a credential comes from the inherited
host environment. Task 1, Task 3.

### REQ-B1.6 — Target grammar per kind [test]

Fixtures: a skill target as `<name>` and as `<plugin>:<name>`, with a
leading slash refused; a command target as a name and as a path; an empty
or multi-line prompt refused; a target carrying a shell metacharacter or
traversal segment refused before any filesystem probe; a skill step's
`args` emitted verbatim. Task 2.

## REQ-C — Resolution

### REQ-C1.1 — Last layer wins with a shadow warning [test]

Fixtures: lists at two layers resolve to the higher one and the warning
names the lower; lists at three layers name both lower ones; lists at one
layer print no warning; the config reader's per-layer mode prints every
layer's value. Task 2.

### REQ-C1.2 — Provenance [test]

`--explain` prints one line per step carrying point, id, list layer, entry
layer, target, and hosting, tab-separated. Task 2.

### REQ-C1.3 — Resolvability on the host [test]

Fixtures under a temporary home: a skill under the plugin skills root, a
user command file, a project skill directory, a planwright-namespaced
skill, a namespaced skill and a namespaced command under a plugin recorded
in a fixture installed-plugin registry, a plugin key listing two install
paths, a command on the path, a command at a path, and a prompt each
resolve; each one absent does not; a namespace matching two registry keys,
one absent from the registry, an unreadable registry, and a missing JSON
reader each make the target non-resolving with the matrix decision
printed; an id naming no catalog entry takes the matrix path; `requires`
naming an absent executable does not resolve; a `--nested` argument is
passed through unexamined. Task 2.

### REQ-C1.4 — The missing-step matrix [test]

Fixtures for every cell: attended prints `ask` for a missing step from each
overlay layer; unattended prints `park` for a repo-tracked list and `skip`
with a warning for an adopter or machine-local list; a core-default step
made unresolvable prints `park` at both attendances; a call with neither
attendance flag exits non-zero; check mode exits non-zero on every `park`
and passes with a warning on an adopter or machine-local `skip`. Task 2.

### REQ-C1.5 — Malformation by layer [test]

A malformed list in the repo-tracked layer exits 4; in the adopter layer it
warns and resolves the core default; a malformed entry in the repo-tracked
layer exits 4; in the adopter layer it warns, is skipped, and its id takes
the matrix path; a malformed core entry exits 5. Task 2.

### REQ-C1.6 — The stale key warns and is ignored [test]

`review_sequence` set at each layer produces one warning per layer naming
that layer and `steps_convergence`, two layers producing two, and the
resolved chain is unaffected. Task 2.

### REQ-C1.7 — Tier from the step-id-keyed knobs [test]

The existing allocation test's step-tier case already resolves an
unshipped step id to `inherit` unconfigured; it is extended with a
hyphenated id whose underscore-spelled knob is set to a strictly cheaper
tier and applies, to an equal or costlier tier and is ignored with a
ledger row, and with an `in-session` step recorded as inheriting. Task 2.

### REQ-C1.8 — No pipeline-entry targets [test]

Each name in the rule doc's pipeline-entry list as a skill target is
refused as malformed with a message naming the rule; the two retargeted
disjointness cross-checks pass. Task 2.

## REQ-D — Execution contract

### REQ-D1.1 — Outcomes [Gherkin + test]

Scenario: given a command step exiting zero, then its record reads
`passed`; exiting non-zero, `failed`. Scenario: given a prompt step whose
handoff is the pinned fixture text reporting a commit, when the runner
classifies it, then the record's outcome is within the closed set and its
excerpt is a substring of that text; the class itself is judged in the
`[manual]` sweep. The record helper test asserts the outcome enum is
closed at five and that `skipped` carries a skip reason. Task 5, Task 4.

### REQ-D1.2 — Posture and the two destinations [Gherkin]

Scenario: given a failing step with the default posture on an unattended
run at an in-run point, then the unit parks to Awaiting input naming point,
step, and outcome, and no later step at that point runs. Scenario: given
posture `continue`, then the failure is recorded and the next step runs.
The flip-point destination (refuse and surface) is REQ-A1.2's scenario.
Task 5.

### REQ-D1.3 — Hosting modes [Gherkin + manual]

Scenario: given a command step with `in-session`, then the unit session
executes it through its shell tool with the context assignments prefixed
and its output appears in the session. Manual, recorded in the PR body: on
a stream-json worker, a skill step with `isolated` runs in a fresh session
launched with the preamble, whose id the record carries, and a following
`continue` step resumes that id; on the terminal rung an explicit
`isolated` step records its degradation to `in-session`. Task 5.

### REQ-D1.4 — Continue without resume fails [Gherkin]

Scenario: given a `continue` step whose predecessor's session the backend
cannot resume, then it does not run, its record reads `failed` naming the
backend and hosting, and its posture applies. Scenario: given a `continue`
step whose predecessor was skipped under the missing-step matrix, then it
does not run and its record reads `failed` naming the missing predecessor.
Task 5.

### REQ-D1.5 — Records and the PR fold [test]

The record helper test round-trips every field REQ-D1.5 names including
the head SHA and run id, renders the per-point table, screens and bounds
an excerpt carrying a token-shaped string, a control byte, and a table
delimiter, renders a point with only a completion record as a `none` row
with its warnings, and shows the rendered table inside the collapsed audit
block of a fixture PR body; the cache path is ignored. Task 4.

### REQ-D1.6 — Reserved controls [design-level + test]

The rule doc states the controls and names the four no-push points and
the two flip surfaces; `config/worker-settings.json` and
`scripts/ready-guard.sh` carry no diff in this bundle's range, and their
existing tests still pass. Task 1, Task 7.

### REQ-D1.7 — Timeout [Gherkin]

Scenario: given a runner-owned command step sleeping past its `timeout`,
then the runner ends it, the record reads `failed` naming the timeout, and
the posture applies. Scenario: given an `in-session` command step with a
`timeout`, then the session's shell tool receives it. Task 5.

### REQ-D1.8 — Missing requires [test]

Covered by the REQ-C1.3 and REQ-C1.4 fixtures: an absent `requires`
executable takes the matrix path. Task 2.

### REQ-D1.9 — Whole-point resolution [test]

A list with one unresolvable step in unattended repo-tracked mode prints
`park` for the point and `run` for no step. Task 2.

## REQ-E — The review points

### REQ-E1.1 — Convergence contract [Gherkin + test]

Scenario: given the shipped defaults, when a unit converges, then exactly
one polish step runs after the main sync, and its handoff folds into the
PR body as before. Scenario: given `steps_convergence: []`, then the sync
still runs. The converge-sync test passes on its updated anchor. Task 5.

### REQ-E1.2 — Post-pr regeneration and draft check [Gherkin + test]

Scenario: given a post-pr command step that commits and pushes, when the
list completes, then the PR body's checklist and step tables are
regenerated from the new range and records. Scenario: given a post-pr step
that un-drafts the PR, then the unit parks naming the step. The record
helper test covers `regenerate` against a golden checklist fixture. Task 5,
Task 4.

### REQ-E1.3 — Pre-ready-flip contract [design-level + test]

The rule doc states that any agent-issued unit flip runs the point first
and that the flip targets the head the list ends on; the resolver test
resolves `pre-ready-flip` like every other point. No in-repo flipper of
unit PRs exists to exercise it end to end; the flip-evidence hook, once
un-gated, is what will bind a hand flip, and until then the rule doc does.
Task 1, Task 2.

### REQ-E1.4 — Briefs cite keys [design-level]

`/orchestrate`'s dispatch prose names the point keys and no list. Task 5.

### REQ-E1.5 — Flip evidence and the evidence hook [test + Gherkin]

The record helper test covers the `status` verb's state derivation over
fixture records (an empty attempt and an all-passed or applied attempt
derive `success`; any halted or failed record derives `failure`; an
earlier attempt's failure for the same head is ignored; a head with no
completion record is refused; a skipped record does not fail it) and
asserts the posting call names the base repository and a permission
failure names the permission; the release-lib test asserts a rollup
holding only a flip-point context is not judged green; the spec-kickoff
PR-ready test's structural row asserts the kickoff gate's exclusion
wording. Scenario: given a clean kickoff with the default empty list, when
it reaches the flip, then the head carries a `planwright/pre-spec-ready-flip`
`success` status before the flip. Scenario: given a failing step at that
point, then the head carries a `failure` status and the flip is refused.
Scenario: given a status post that fails, then no flip happens and the
Awaiting-input entry names the post. The evidence hook's rows (a
`planwright/` head branch with the status matching its form defers to the
ready-guard, without any status denies, with a `failure` status denies, a
status read that errors denies, a non-`planwright/` branch defers, a fork
head defers, each on both flip surfaces) belong to the Deferred entry and
are written when it is un-gated; until then no unit-PR flipper runs the
point, and the unit half of this requirement is verified only by the rule
doc stating it. Task 9, Task 6, Task 1.

## REQ-F — Replacement of the review-sequence knob

### REQ-F1.1 — Removal [test]

`check:steps` fails on `review_sequence` in `config/defaults.yml` or in
this repository's configuration outside the transitional line; the old
resolver and its test are absent; the convergence prose names
`steps_convergence`. Task 3, Task 8, Task 5.

### REQ-F1.2 — Repo config migrated [test]

`.claude/planwright.yml` carries `steps_convergence: [self-review]` beside
the dated transitional line, and `check:steps` resolves it. Task 3, Task 8.

### REQ-F1.3 — Surface sweep [test]

The `git grep` REQ-F1.3 defines returns only the stale-key warning site,
the fixtures that exercise it, and the transitional line, run after Tasks
5 and 6 land. Task 3, Task 5, Task 6.

### REQ-F1.4 — Allocation knobs keep their names [test]

The existing allocation assertions still pass; the options rows describe
the knobs as step-id-keyed with the one-directional rule. Task 3.

### REQ-F1.5 — Flights read the convergence list [design-level]

No flight skill ships yet; the rule doc states that a flight converges
through `steps_convergence` with unit kind `flight`, and the first flight
skill that lands cites it. Task 1, Task 3.

## REQ-G — Security and permissions

### REQ-G1.1 — Context by environment only [test + Gherkin]

The resolver test asserts a declared command line is emitted byte-for-byte
and that `args` carrying a shell operator, redirection, expansion, or quote
is malformed; the REQ-A1.4 scenario shows the fields in the environment and
none in the command, and the runner subprocess receives the words as argv.
Task 2, Task 5.

### REQ-G1.2 — Human-owned layers [design-level]

The rule doc and the overlay documentation state the trust posture
REQ-G1.2 defines; the worker profile carries no diff in this bundle's
range. Task 1, Task 7.

### REQ-G1.3 — Guard approval of declared lines [test]

The rows Task 7 names in the worker command guard's test: a declared line
approved, the same line with context assignments prefixed approved, a
word-identical respelling approved, a segment sharing only the first word
deferred, a non-declared command deferred, a path target with a traversal
segment deferred; plus the existing runtime-bound row with a fixture
catalog of several entries present. Task 7.

### REQ-G1.4 — No elevation for skill steps [design-level]

The rule doc states it and the profile is unchanged for skills. Task 1.

## REQ-H — Documentation, tooling, and guards

### REQ-H1.1 — Options rows [test]

`check:options` passes. Task 2, Task 3.

### REQ-H1.2 — Overlay documentation [design-level]

`docs/overlays.md` describes the catalog, the context set, the record
cache, the credential rule, the status-write permission, and the disclosure
note; corrects the growable-catalog enumeration; and its worked example
shows a per-user entry used by a per-project list. Task 3.

### REQ-H1.3 — Resolver and record commands [test]

Covered by the resolver test (output shape, exit codes, check mode,
`--preamble`) and the record helper test. Task 2, Task 4.

### REQ-H1.4 — The check:steps guard and the budget [test]

`mise run check` runs `check:steps` over every named point; each failing
fixture exits non-zero; `check:instructions` passes on every skill edit.
Task 8, Task 5, Task 6.

### REQ-H1.5 — Index and manifests [test]

`check:doctrine-index` passes and `check:instructions`' manifest-resolution
pass is green on the new doc. Task 1, Task 5.
