# Custom steps — Test Spec

**Status:** Ready
**Last reviewed:** 2026-10-06
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` where automation is honest (the resolver, the pool helper, the
record helper, the guard fixture rows, and the repository's existing
options, links, doctrine-index, instruction-budget, and shell checks, all
run by `mise run check` and the repository CI); `[Gherkin]` for the
skill-wired behaviors a fixture overlay exercises end to end on the
terminal rung, recorded in the PR body; `[design-level]` where a rule's
presence in the named doc or row is the verification; `[manual]` where a
behavior needs a live session-grade backend or a real gate run on this
host. Every Gherkin
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

### REQ-A1.4 — The fixed context set [Gherkin + test] (superseded by REQ-A1.6)

Scenario: given a command step that prints its environment, when it runs at
`post-pr`, then exactly the `PLANWRIGHT_STEP_*` variables REQ-A1.4 names
are present, the PR number set, and the rest of the host environment
intact; on a first run at `pre-ci` the PR number is set to the empty
string, and on a re-execution it carries the existing PR. The resolver
test asserts `--preamble` renders the same fields. Task 5, Task 2.

Verification now pins to REQ-A1.6, below.

### REQ-A1.6 — The fixed context set with the head move [Gherkin + test]

Scenario: given a command step that prints its environment, when it runs at
`post-pr`, then exactly the `PLANWRIGHT_STEP_*` variables REQ-A1.6 names
are present, the PR number set, and the rest of the host environment
intact; on a first run at `pre-ci` the PR number is set to the empty
string, and on a re-execution it carries the existing PR. Scenario: given
a post-pr command step that pushes, followed by one that prints its
environment, then the second sees the previous and new head of that push;
with no earlier push at the point both are empty strings. Scenario: given
a post-pr command step that commits without pushing, followed by one that
prints its environment, then the second sees that move. The resolver
test asserts `--preamble` renders the same fields, and that `--prefix`
and `--line` render `PLANWRIGHT_STEP_POOL_HOLD=<pool>:<pid>` as one
trailing assignment when given a pool and an owner pid and no mark
assignment otherwise. Task 14, Task 12, Task 10.

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

### REQ-B1.2 — Entry fields and enums [test] (superseded by REQ-B1.7)

Fixtures: an entry with every field resolves; an unknown field, an unknown
kind, an unknown hosting, a non-integer timeout, a missing target, an id
with a leading digit or an uppercase letter, the id `implementation`, a
`timeout` on an `in-session` skill step, and `args` on a `prompt` step are
each malformed, with the by-layer policy applied per the layer that
supplied them; a `timeout` on an `in-session` command step resolves.
Task 2.

Verification now pins to REQ-B1.7, below.

### REQ-B1.7 — Entry fields, including the extension's [test]

Fixtures: every REQ-B1.2 fixture row keeps its result; an entry carrying
`pool`, `paths`, and `refire` on a command step resolves; an entry carrying
each of quota-handling's six fields resolves as known fields; the
REQ-I1.11 combinations are malformed under the by-layer policy. Task 12.

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

### REQ-D1.1 — Outcomes [Gherkin + test] (superseded by REQ-D1.10)

Scenario: given a command step exiting zero, then its record reads
`passed`; exiting non-zero, `failed`. Scenario: given a prompt step whose
handoff is the pinned fixture text reporting a commit, when the runner
classifies it, then the record's outcome is within the closed set and its
excerpt is a substring of that text; the class itself is judged in the
`[manual]` sweep. The record helper test asserts the outcome enum is
closed at five and that `skipped` carries a skip reason. Task 5, Task 4.

Verification now pins to REQ-D1.10, below.

### REQ-D1.10 — Outcomes, with `limited` and the wider `skipped` [Gherkin + test]

Scenario: given a command step exiting zero, then its record reads
`passed`; exiting non-zero, `failed`. Scenario: given a prompt step whose
handoff is the pinned fixture text reporting a commit, when the runner
classifies it, then the record's outcome is within the closed set and its
excerpt is a substring of that text; the class itself is judged in the
`[manual]` sweep. The record helper test asserts the outcome enum is closed
at the six REQ-D1.10 names, that `limited` is accepted, and that every
`skipped` record carries one of the REQ-D1.12 reasons. The `limited`
classification itself, and the `answered` mapping, are verified by
quota-handling's tests. Task 13, Task 5.

### REQ-D1.2 — Posture and the two destinations [Gherkin]

Scenario: given a failing step with the default posture on an unattended
run at an in-run point, then the unit parks to Awaiting input naming point,
step, and outcome, and no later step at that point runs. Scenario: given
posture `continue`, then the failure is recorded and the next step runs.
The flip-point destination (refuse and surface) is REQ-A1.2's scenario.
Task 5.

### REQ-D1.3 — Hosting modes [Gherkin + manual]

Scenario: given a command step with `in-session`, then the unit session
executes it through its shell tool as the resolved location and `args`,
with the context assignments prefixed, a target naming a shell builtin
runs the file the resolver printed, and its output appears in the session. Manual, recorded in the PR body: on
a stream-json worker, a skill step with `isolated` runs in a fresh session
launched with the preamble, whose id the record carries, and a following
`continue` step resumes that id; on the terminal rung an explicit
`isolated` step records its degradation to `in-session`. Task 5.

### REQ-D1.4 — Continue without resume fails [Gherkin] (superseded by REQ-D1.11)

Scenario: given a `continue` step whose predecessor's session the backend
cannot resume, then it does not run, its record reads `failed` naming the
backend and hosting, and its posture applies. Scenario: given a `continue`
step whose predecessor was skipped under the missing-step matrix, then it
does not run and its record reads `failed` naming the missing predecessor.
Task 5.

Verification now pins to REQ-D1.11, below.

### REQ-D1.11 — Continue over a skipped predecessor [Gherkin + manual]

Scenario: given a `continue` step whose predecessor's session the backend
cannot resume, then it does not run, its record reads `failed` naming the
backend and hosting, and its posture applies. Scenario: given a `continue`
step whose predecessor was skipped under the missing-step matrix, then it
does not run and its record reads `failed` naming the missing
predecessor. Scenario: given a `continue` step whose reused predecessor
was hosted `in-session`, then it attaches to the current unit's session.
Scenario: given a reused predecessor's session on a backend that cannot
resume it, then it fails naming the backend. Manual, recorded in Task
14's PR body: on a stream-json worker, a `continue` step whose
predecessor was skipped by reuse attaches to the reused record's session
id, which its record names. Task 14.

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

### REQ-D1.12 — End heads and skip reasons [test + Gherkin]

The record helper test round-trips the end head on every record, refuses
a `skipped` record without exactly one REQ-D1.12 reason code while
keeping the free-text detail optional, round-trips the standing-on run
id, point, and record sequence for a `reuse` and a `resume` skip, and
shows a record written before the extension (no end head, no code)
matching no lookup, never counting toward the REQ-J1.2 scan, and
rendering its free-text reason as written. The `/execute-task`
missing-matrix skip writes code `missing` (Task 13). Scenario: given a
post-pr command step that commits without pushing, then its record's end
head differs from its start head and the next step's context carries the
move (Task 14). Scenario: given a fixture overlay whose
`pre-spec-ready-flip` list declares a passing command step, when
`/spec-kickoff` runs the point, then every record there carries its end
head (Task 6). Task 13, Task 14, Task 6.

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

### REQ-E1.5 — Flip evidence and the evidence hook [test + Gherkin] (superseded by REQ-E1.6)

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

Verification now pins to REQ-E1.6, below.

### REQ-E1.6 — Flip evidence, with `limited` failing it [test + Gherkin]

Every REQ-E1.5 check carries over unchanged except its closing claim that
no unit-PR flipper runs the point: `/execute-task`'s unit flip
(`scripts/ready-flip.sh`) now does, and Task 14's REQ-J1.2 scenario
exercises its refusal. The record helper test
adds that an attempt holding a `limited` record derives `failure`, alone
or beside passed records; that an all-passed attempt derives `failure`
when an earlier unit run in the same record cache holds an unretired
`limited` record ending on the same head; and that an earlier flip
attempt's `limited` record on the same head derives `failure` while an
earlier attempt's `failed` record is still ignored. Task 13, Task 9,
Task 6.

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

The resolver test asserts a declared command line is emitted as the
resolved location followed by its `args` byte-for-byte and that `args`
carrying a shell operator, redirection, expansion, or quote is malformed;
the REQ-A1.4 scenario shows the fields in the environment and none in the
command, and the runner subprocess receives the resolved location and
`args` as argv.
Task 2, Task 5.

### REQ-G1.2 — Human-owned layers [design-level]

The rule doc and the overlay documentation state the trust posture
REQ-G1.2 defines; the worker profile carries no diff in this bundle's
range. Task 1, Task 7.

### REQ-G1.3 — Guard approval of declared lines [test]

The rows Task 7 names in the worker command guard's test: a declared line
approved, the same line with context assignments prefixed approved, a
word-identical respelling approved, the same line spelled with the bare
target instead of its resolved location deferred, a segment sharing only
the first word deferred, a non-declared command deferred, a path target with a traversal
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

## REQ-I — Expensive checks

### REQ-I1.1 — A pooled step holds a slot for its run only [test + Gherkin]

The pool helper test shows a slot taken and released around a fixture
check, released by its owner after a non-zero exit, reclaimed after the
owner process exits, a nested caller's release a successful no-op, and
the slot shared by callers in two different checkouts. Scenario: given
two fixture units on the terminal rung each with a pooled `pre-pr`
command step naming the same pool of capacity one, then each later slot
start (a record's start being when its slot was taken) is at or after
the earlier slot end. Scenario: given a fixture wait longer than the
shell-call cap, then the step is still admitted, its wait seconds summed
across calls. Task 11, Task 14.

### REQ-I1.2 — Slots on the shared lock primitive [test + Gherkin]

The pool helper test shows a dead holder's slot reclaimed, a child process
that outlives the owning process not keeping the slot, a symbolic-link or
foreign-owned pool directory reported for an unpooled run with its cause,
and a lock-library error doing the same; a take under a hold mark of the
same pool and a live owner returning at once at capacity one without a
slot or a warning, and a mark naming a dead owner or another pool, or a
malformed mark, ignored; a take by an owner that already holds a slot
of the pool, without a hold mark, waiting like any other caller;
`scripts/check-lock-primitive.sh` passes with the helper sourcing the
primitive. The worker command guard's test approves a declared line
under the twelve-field context prefix with the trailing hold mark and
without it, and refuses one carrying a malformed mark (Task 12).
Scenario: given a pooled command step whose check takes its own pool
again, then the nested take does not wait and the step records
`passed`. Task 11, Task 12, Task 14.

### REQ-I1.3 — Capacity knobs [test]

The pool helper test shows the shared default of one serializing two
callers, a per-pool override admitting two, and a malformed value at each
key falling back in order with a warning naming the layer. Task 11.

### REQ-I1.4 — The bounded wait [test + Gherkin]

The pool helper test shows a waiter reporting the live holder's process
id, step, and worktree, and a wait past a short fixture bound ending with
the holder named. Scenario: given a pooled step whose wait expires, then
its record reads `failed` naming the holder, its wait seconds are
recorded apart from its run, and its posture applies. Task 11, Task 14.

### REQ-I1.5 — The built-in full suite joins a pool [Gherkin + test]

Scenario: given two fixture units sharing `full_suite_pool`, each fixture
suite appending its start and end timestamps to a shared file, then the
recorded intervals are disjoint. Scenario: given the default empty key,
then a unit's full suite runs as before, taking no slot. Scenario: given
a full-suite wait that expires on a run with a PR, then the unit parks
naming the holders, the suite is not retried, and the PR body's audit
block carries the full-suite row with its pool, wait seconds, and
holders. Scenario: given a first run whose full-suite wait expires before
any PR exists, then the Awaiting-input park entry names the holders and
the wait. The record helper test round-trips the full-suite record and
its row (Task 13). The options
check asserts the key's row, and the overlay documentation's hand-run
recipe is exercised by Task 16's recorded gate run. Task 14, Task 13,
Task 10, Task 16.

### REQ-I1.6 — The helper executes nothing [test]

The pool helper test passes a command line to every verb and asserts
nothing was executed (a fixture command that would create a marker file
leaves none). Task 11.

### REQ-I1.7 — The paths grammar and the fingerprint [test]

The resolver test refuses each grammar violation (a leading `/`, a leading
`-`, a `..` segment, a disallowed character). The record helper test shows
the fingerprint stable across a commit outside the paths, changed by one
inside, absent under an uncommitted or untracked change in a declared
path, unchanged by an ignored file under a declared path, an absent path
contributing its marker, and two different path word sets over the same
content giving different fingerprints. Task 12, Task 13.

### REQ-I1.8 — Reuse of a passing record [test + Gherkin]

The record helper test's lookup matches only a `passed` record of the same
id, target, `args` digest, and fingerprint, across runs and within the
current run, re-fire records included, and never one with a different
target or `args` digest. Scenario: given a unit run twice with no change
to the declared paths, then the second run's record reads `skipped` with
reason `reuse` naming the first. Task 13, Task 14.

### REQ-I1.9 — Re-fire after the post-pr point [Gherkin]

Scenario: given a `refire: post-pr` command step at `pre-pr` and a
post-pr step that pushes a change under its paths, then the step runs
again on the final head before the PR body is regenerated, recorded
under `post-pr` with `refire-of` naming `pre-pr`, before the post-pr
completion record. Scenario: given a push touching no declared path,
then the re-fire records a `reuse` skip. Scenario: given a failing
re-fire with the default posture, then the PR body is regenerated, the
unit parks naming the step and the head, and the PR stays a draft.
Scenario: given no post-pr head move, then nothing re-fires. Scenario:
given one step id declaring re-fire listed at both `pre-ci` and
`pre-pr`, then it re-fires once, with `refire-of` naming `pre-ci`.
Scenario: given a re-fire step skipped with reason `missing` at its
declaring point, then it is not re-fired. Scenario: given a re-fired
step that prints its context, then it reads point `post-pr`, the
previous record of the re-fire pass (or, for the first, the last post-pr
record), and the post-pr head move. Scenario: given a resume, or a chain
of resumes, of a run interrupted at `post-pr`, then the re-fire pass
uses the `pre-ci` and `pre-pr` lists resolved in the first run of the
chain. The record helper test accepts a re-fire record under `post-pr`
before the completion record (Task 13). Task 14, Task 13.

### REQ-I1.10 — Record fields for pools and paths [test]

The record helper test round-trips pool, wait seconds, holders, the
unpooled flag, the fingerprint or its absence, the `args` digest, and the
`refire-of` field, and renders them table-safe in the PR-body fold.
Task 13.

### REQ-I1.11 — Resolution refusals for the new fields [test]

The resolver test refuses each REQ-I1.11 malformation for its layer with
the by-layer exit, `refire` with `hosting: continue` included, accepts a
re-fire step in `steps_pre_ci` and `steps_pre_pr` and refuses it in every
other list, and asserts `--explain` prints pool, paths, and re-fire. The
`check:steps` fixture rows cover the same refusals. Task 12, Task 15.

### REQ-I1.12 — Documentation and the guard [test + design-level]

The options check passes with the new rows; the doc-links and
doctrine-index checks pass; `tests/test-check-steps.sh` resolves a fixture
configuration declaring `pool`, `paths`, and `refire` green. The rule doc's contract and the overlay
documentation's example are verified by their presence. Task 10, Task 15.

### REQ-I1.13 — This repository uses the native pool [test + manual]

The options check and `check:steps` pass with `full_suite_pool` set in the
repo-tracked configuration. Manual, recorded in the PR body: a full gate
run through the documented recipe takes and releases a slot of the
configured pool. Task 16.

## REQ-J — Limits and head ordering

### REQ-J1.1 — Resume continuation [test + Gherkin]

The record helper's resume lookup matches only `passed` or `applied`
records of the interrupted run whose end head equals the given head, or
`resume` skips standing on such records. Scenario: given seeded records
of a run interrupted after two passing steps, and a run whose invocation
names that run and point on the same head, then those steps record
`skipped` with reason `resume` and real work begins at the third, no
earlier point firing; given the head moved since, then nothing is
skipped; given an invocation naming a malformed run id, or a point
outside the in-run points `/execute-task` wires, then it is refused
before any record is read. Scenario: given a second hold in the resumed
run and a resume naming that run, then the steps skipped with reason
`resume` are skipped again. Scenario: given an interrupted post-pr step
that moved the head and a resume that skips it with reason `resume`,
then the carried head move still triggers the re-fire pass and the
REQ-E1.2 regeneration, and the carried move reaches the next step's
environment. Scenario: given a run held during its re-fire pass and a
resume naming it, then the held re-fired step resumes in the re-fire
pass, no earlier point firing. No quota hold is needed; the hold-driven
trigger is verified by quota-handling's tests. Task 13, Task 14.

### REQ-J1.2 — `limited` refuses the flip [test + Gherkin]

The record helper test shows the `status` verb deriving `failure` over a
`limited` record of an earlier unit run whose end head is the head being
flipped, and `success` when that record's end head is a different head;
given a hold, then a resume whose run passes the held step on the same
head, it derives `success`; given an earlier flip attempt's `limited`
record on the same head, it derives `failure`, while an earlier
attempt's `failed` record is still ignored per the carried-over REQ-E1.5
rule. Scenario: given a seeded `limited` record ending on the head, when
`/spec-kickoff` reaches its flip, then the flip is refused and the head
carries a `failure` status (Task 6). Scenario: given a post-pr step
recorded `limited`, when the unit-owner flip runs on the same head, then
`scripts/ready-flip.sh` refuses it (Task 14). The `on-limit` postures are
verified by quota-handling's tests. Task 13, Task 6, Task 14.

### REQ-J1.3 — The fields' owner is named, and the fields are known [test + design-level]

The resolver test accepts each quota-handling field as a known field; the
rule doc's list naming quota-handling as owner is verified by its
presence. Task 12, Task 10.
