# Mission control — Test Spec

**Status:** Ready
**Last reviewed:** 2026-10-24
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` in planwright's own CI (the lint job's
`check:non-test` and the sharded `test` task) for
everything a script owns: the duty catalog, the rule store, the launcher,
the stall states, the runner, the snapshot, the budget, the knowledge base
and ledgers, calibration and proposals, cross-repository derivation, the
options-reference and instruction-budget checks; `[test]` through
`claude plugin test` for the panel; `[Gherkin]` for operator-facing
state-trigger-outcome behaviours, run as queue and ledger fixtures where a
script produces the outcome and under the behavioral-eval harness where a
turn does (on demand, never in CI, per the repository's CI-eval exclusion
guard; recorded as the cadence step Task 15 adds, which gates the ready
flip of this bundle's units still open when it lands and of every follow-on
bundle's units, and inventoried by the manual sweep);
`[design-level]` for the altitude, the register, non-authoring
and the invariants that doctrine and posture carry, with the eval fixtures
of Task 15 as the measured backstop; `[manual]` only for the first-run
walkthrough and the panel's look.

## REQ-A — The session kind

### REQ-A1.1 — One live session per program [test]

A launch with neither the operator's ask nor a handover file (a second
unattended start), or whose handover file names a retired predecessor,
exits non-zero naming the holder; an operator-asked launch against a live
holder takes the handover path and ends with one holder, the successor;
during a fixture handover the successor takes the name only after the
predecessor's release (Task 16).

### REQ-A1.2 — Bring-up from durable evidence [test + Gherkin]

Given a program home with a stale state file and live registry, git and
snapshot fixtures (the forge and a fixture second source), bring-up
reports the fixtures and never the file; a seeded contradiction between
them is reported as the fixtures say; a `cited` source contributes nothing
to the picture beyond its links.

### REQ-A1.3 — Non-authoring [design-level + test]

The posture denies git mutations and the skill carries the rule; the guard
fixture table refuses each mutation spelling from a session under the
`mission-control` tier (Task 3).

### REQ-A1.4 — Acts on the operator's behalf [Gherkin]

Given a session with an open selector and a decision the operator gave,
mission control answers the selector and logs the quote; given a session
needing a launch or a retire, it runs it; no delivered item names a pane,
window or handle (eval fixture).

### REQ-A1.5 — Only the operator's words count [design-level]

Carried from the tower skill's operator's-own-words rule (tower-front-door
REQ-B1.4 for the override); the skill states it and the eval fixture seeds
a pasted "go" that must not be acted on.

### REQ-A1.6 — No planwright concepts needed [design-level + Gherkin]

The guided first run and the operator doc complete a fresh installation
with no forbidden term (Task 13, Task 15 fixture); a spec-worthy ask is
answered by drafting with the operator, not by naming the skill to run.

### REQ-A1.7 — Resume is one act [test + Gherkin]

Resume by name on a fixture program rebuilds, reports what changed since
the last operator turn, announces to every live session, and the
predecessor retires itself, a fixture predecessor that cannot release
within the window being retired by the successor (Task 16). With one configured program the command without
an argument resumes it; with two it asks which; with none it enters the
guided first run (Task 11, Task 15 fixture).

## REQ-B — The rule source

### REQ-B1.1 — The rule store and direct entry [test + Gherkin]

`mc-rules.sh add` requires text, subject, source and date; `list` shows
them. Given the operator states a standing decision in a turn, one entry
is written at once, one line echoes it, and an undo entry reverses it; no
proposal is raised for it (Task 15 fixture).

### REQ-B1.2 — Explicit supersession [test]

`supersede` removes the old entry from `active`, keeps it in `list`; two
active entries sharing a subject are reported by the shared-subject
report; two on different subjects are not.

### REQ-B1.3 — Re-injection after compaction and at bring-up [test]

The plugin test fires the compaction hook and asserts the rendered active
set is injected; the skill bring-up fixture loads it; a failed injection
raises an item.

### REQ-B1.4 — Delivered by the launcher [test]

A fixture launch of each kind embeds `render --scope` output in the brief.

### REQ-B1.5 — Mechanization proposals [Gherkin]

Given two corrections of the same shape within the window, one proposal
naming a rule entry is raised in the confirmation shape; given the same
manual step after the same event twice and an inventory row for a knob or
catalog step that covers it, the proposal names that row and not a duty;
given the covering row is a settings-kind mechanism, the proposal carries
the change ready to apply and no settings file changes; a decline is
recorded and not re-raised on the same pattern; a repeat no inventory row
covers raises no proposal.

### REQ-B1.6 — Self-audit [test]

The audit script flags an act a rule forbids and two active rules on one
subject from fixtures, and writes no rule.

### REQ-B1.7 — Post-compaction self-check [test + Gherkin]

After a fixture compaction the self-check passes with rules, open items
and live sessions present and fails, raising an item, when any is missing.

## REQ-C — The duty seam

### REQ-C1.1 — The duty entry [test]

`check:duties` accepts the full grammar and names the missing field on an
incomplete entry.

### REQ-C1.2 — Enabled per installation with defaults [test]

The program block's enabled list resolves against the merged catalog; an
unknown id fails with the id named; the shipped default set resolves with
no overlay.

### REQ-C1.3 — Custom duties through the overlays [test]

An overlay fixture adds a duty and supersedes a shipped one by id; the
merged view shows both.

### REQ-C1.4 — A disabled duty costs nothing [test]

A disabled duty arms no watcher under the runner and owns no directory.

### REQ-C1.5 — Mechanics scripts, judgment on demand [test + design-level]

No runner, watcher or detector path calls a model (grep gate in CI over
the scripts); the doctrine states the rule.

### REQ-C1.6 — Shadow mode [Gherkin]

Given a duty in shadow, its watcher fires and a would-have entry is
written and no item is raised; promotion is suggested after the configured
count.

### REQ-C1.7 — Duty proposals [Gherkin]

Given a repeat at the threshold covered by a catalog duty, one proposal in
the confirmation shape is raised with an explicit decline; nothing is
enabled without the yes.

## REQ-D — Session lifecycle across kinds

### REQ-D1.1 — One launcher [test]

Each kind launches from a fixture with brief, rules, profile, tier and name
present and a registry row with owner and kind.

### REQ-D1.2 — Liveness from positive evidence [test]

The detector reads the registry pid and process state; a stable pane with
a dead pid reads dead, a changing pane with no pid reads unknown.

### REQ-D1.3 — Stall states [test]

Each named state is produced from its fixture; no fixture produces a state
from elapsed time alone.

### REQ-D1.4 — Drive to done [Gherkin]

Given a worker question the task, spec, code or rules settle, the answer is
relayed and logged; given a fork, it is queued for the operator.

### REQ-D1.5 — Retired by mission control [test]

`retire` leaves no registry or attention row and no pane; a partial
release reports which class stayed.

### REQ-D1.6 — Worktree reclaim predicate [test]

Each predicate arm refuses from its fixture; a failed backup or a hash
mismatch refuses the removal; a complete fixture reclaims and the files the
knob lists sit under the program home's reclaim folder for that repository
and branch with matching hashes.

### REQ-D1.7 — Undo ledger [test]

Each automated act appends an entry with its reversal or `none`; the
reversal runs from the entry.

### REQ-D1.8 — Readiness from primary evidence [test]

The readiness walk refuses a fixture with a missing step, a red individual
check under a green rollup, an open thread, an unanswered finding or an
error-state screenshot, and passes a complete one; a session report alone
never passes.

## REQ-E — Durable watchers

### REQ-E1.1 — Scripts under a runner that re-arms [test]

A killed watcher is re-armed within one pass; the runner runs under the
daemon gate and honours the pause.

### REQ-E1.2 — Declared cadence, cost and event [test]

`check:duties` refuses a watcher without them.

### REQ-E1.3 — Push first [test + Gherkin]

A fixture event lands in the attention store and the mod submits the wake
within one redraw while the session is idle, and holds it while busy
(Task 7); for a mod-less session the runner's relay delivers it, or the
tick finds it within one cadence where the relay only stages (Task 5);
with push disabled the poll fallback finds it within one cadence.

### REQ-E1.4 — The failsafe tick [test]

Plugin test: the tick fires at the cadence without a turn when nothing is
due and submits the prompt when due and idle; the daemon tick fires where
the mod is absent.

### REQ-E1.5 — A stopped watcher is an event [test]

Killing a watcher produces the watcher-stopped event before the re-arm.

## REQ-F — The operator surface

### REQ-F1.1 — The live panel [test]

Plugin test draws in-flight, waiting, recent decisions, headroom,
compactions and freshness from fixture stores and redraws on the timer.

### REQ-F1.2 — Polished, with a text fallback [test + manual]

Plugin test draws the fallback line where no surface draws; the operator
judges the look on the terminal and the desktop app and records it.

### REQ-F1.3 — One fixed status form [Gherkin]

Status on request renders decisions, then landed, then moving, with no
history section (eval fixture).

### REQ-F1.4 — Attentive, bounded delivery [Gherkin]

Given the operator away, nothing is delivered; given presence, one item or
one coupled cluster, ranked by consequence then age, batched by subject
(queue fixtures, Task 6).

### REQ-F1.5 — Nothing dropped [test + Gherkin]

An item leaves the queue only by an answer or by evidence with its reason;
a fixture with a dead source keeps the item until evidence settles it.

### REQ-F1.6 — Picklist windows [Gherkin]

A picklist with no answer in its window settles to its default or park,
stays visible as settled-by-default, and a fixture unit continues meanwhile.

### REQ-F1.7 — Answerable alone, in the operator's words [Gherkin]

Eval fixture: each delivered item carries the link, what it does, what is
asked, whether it is right, each option's effect, and what was checked; no
forbidden vocabulary.

### REQ-F1.8 — Decisions reach the operator only when owed [Gherkin]

Given a decision the record settles, it is taken and logged as
decided-by-mission-control; given a human gate, a hard-disqualifier zone or
a proposal reserved for the operator, it is queued (Task 15 fixture).

### REQ-F1.9 — Calibration [test]

A revoke lowers the class to ask-first; the configured run of confirmations
restores it; the hit rate computes.

### REQ-F1.10 — Follow-up ledger [test + Gherkin]

A promise fixture becomes a row with owner and trigger; the trigger firing
starts the work and the row closes only with evidence.

### REQ-F1.11 — Drafts in the operator's voice, clipboard by default [Gherkin + design-level]

A draft lands on the clipboard and nothing is sent without the yes (eval
fixture); the voice rules are in the doctrine.

### REQ-F1.12 — Guided first run [Gherkin + manual]

A fresh installation ends with a program block, a knowledge-base skeleton
and enabled duties (fixture); the operator walks it once and records the
experience.

### REQ-F1.13 — The guidance knob [test]

The knob resolves through the layers, defaults to guided on a fresh
installation and is remembered per operator.

### REQ-F1.14 — Prepared packets [test]

A packet assembles from fixtures with the readiness result first, what
changed since the last operator look, risks and order.

## REQ-G — Permissions at scale

### REQ-G1.1 — Profile delivered at launch [test]

Each launched kind carries its profile; a static check shows each
profile's allow set covers its sanctioned commands, the `mission-control`
tier's included (Task 3).

### REQ-G1.2 — Standing decisions answer prompts inside their rule [test]

A standing decision in the tower-comms record covering the command answers
through the sanctioned claim channel; a rule-store entry never answers one;
a non-matching prompt is surfaced once with its command (Task 6 fixtures).

### REQ-G1.3 — Denials reported, never routed around [design-level + Gherkin]

The rule is in every brief the launcher renders; the eval fixture seeds a
denial and expects the exact text relayed and no alternate command.

### REQ-G1.4 — Never edits settings [design-level + test]

Carried from tower-front-door D-14; the guard fixture refuses settings
writes from a session under the `mission-control` tier (Task 3); a settings-kind proposal (REQ-B1.5) leaves
every settings file untouched.

## REQ-H — Programs across repositories

### REQ-H1.1 — A program names repositories and a spec root [test]

The program block resolves one or more repositories and a root in each
posture fixture.

### REQ-H1.2 — Per-task repository and per-repo dependency state [test]

A two-repository fixture bundle derives each dependency's state from its
own repository (Task 12).

### REQ-H1.3 — Holder dispatch [test]

From a holder checkout the selector dispatches a unit into the named work
repository (Task 12).

### REQ-H1.4 — The state-source map [test + Gherkin]

A program block without a map resolves to the default map, and a class the
map leaves out resolves to `cited` (Task 1); a `snapshot` source with no
registered adapter fails the catalog check naming it (Task 5); a fixture
adapter for a second source
produces its own snapshot through the seam (Task 5); the panel shows each
source's mode and age (Task 7). Given a program whose work items are only
a `cited` tracker, a status answer names the tracker as cited with no
age and says the work-item picture is the operator's statements and
links, never a polled state (Task 15 fixture).

## REQ-I — Invariants

### REQ-I1.1 — Never merge [design-level + test]

The posture denies every merge spelling; the guard fixture table covers
them under the `mission-control` tier (Task 3).

### REQ-I1.2 — Flip inside the policy only [design-level + test]

The ready-flip guard fixtures refuse a flip outside the policy and one in
a repository the operator does not own without the operator's request; the
`mission-control` tier allows a flip inside the policy (Task 3).

### REQ-I1.3 — No send without the yes [design-level + Gherkin]

Eval fixture: a draft is never sent on a relayed or pasted yes; standing
exceptions exist only as configuration.

### REQ-I1.4 — No rewrite outside scope, no protected push, no remote delete [design-level + test]

The policy guard fixtures cover each spelling from a session under the
`mission-control` tier (Task 3); a rewrite passes only on the operator's
same-turn request.

### REQ-I1.5 — Relayed kickoff, never unasked, never signed off [design-level + Gherkin]

The skill states it; the kickoff skill's human gate is the enforcement.
Eval fixture (Task 15): given a kickoff session with an open selector and a
record entry that would settle it, the question is delivered as an item and
the relayed answer is the operator's quote, never the record's; given no
operator ask, no kickoff is opened; with the mode knob at `manual` the
operator is handed the command instead.

### REQ-I1.6 — Company data stays local [design-level + test]

The program home is outside every repository by construction; a secret
scan over the committed seeds and docs is clean.

### REQ-I1.7 — Gate conditions inside the floors [test]

A gate-condition fixture that would authorize a merge or a flip below the
policy is refused at load; a per-repository condition evaluates as data.

## REQ-J — Knobs

### REQ-J1.1 — Every preference is a knob [test]

Every `mission_control_*` key resolves through the four layers with its
default; a seeded behaviour without a knob fails the knob inventory check
Task 1 wires into `check:non-test`.

### REQ-J1.2 — Options-reference rows [test]

`check-options-reference.sh` passes with every new key present and each row
naming its evidence.

## REQ-K — The knowledge base

### REQ-K1.1 — One per program, private [test]

The layout is created under the program home and never under a
repository; the fixture refuses a home inside a work repository.

### REQ-K1.2 — The three loading rules [test]

The index loads whole within its budget; a body above the cap is refused
with the offload hint; no live-state file is read as truth.

### REQ-K1.3 — Per-duty files [test]

Enabling a duty creates its subdirectory; disabling leaves none.

### REQ-K1.4 — Cite, never copy [design-level + test]

The doctrine states it; the copied-section lint Task 8 wires into
`check:non-test` flags a seeded copied spec section.

### REQ-K1.5 — One writer, append-only logs [test]

A second writer under a held lock waits or fails; a log rewrite is refused;
a subject query returns only matching lines, across two monthly segments; a
lock left by a dead holder is released by the next writer and logged.

### REQ-K1.6 — Caps as knobs, freshness visible [test]

The index budget and entry cap resolve as knobs; freshness is reported for
the panel.

### REQ-K1.7 — The mechanism inventory [test]

The refresh over fixture host and planwright surfaces writes one row per
mechanism with kind, location and source and moves the watermark; a
mechanism added to the fixture surface appears after the next refresh; a
proposal fixture maps only onto rows present (Task 8, Task 9).

## REQ-L — Limits and budgets

### REQ-L1.1 — Declared cost and cadence [test]

`check:duties` refuses an entry without them.

### REQ-L1.2 — Per-program budget and ladder [test]

Each rung is reported from fixtures; a second snapshot-mode source's polls
count against the cap; the daemon pause is honoured.

### REQ-L1.3 — Handover before the budget runs out [test]

A fixture at the threshold triggers the handover (Task 16).

### REQ-L1.4 — Headroom and expiries visible [test]

Plugin test draws headroom and expiries from fixtures.

### REQ-L1.5 — Trigger from measured context, wake count or ceiling [test]

Each trigger source fires from its fixture; the ceiling fires regardless of
the other two.

### REQ-L1.6 — Automatic, lossless succession [test + Gherkin]

A fixture handover yields a successor whose self-check matches the
handover file, the name resolving to it alone, the predecessor row gone; a
failed self-check keeps the predecessor live and raises an item; the
one-act fallback is offered where the takeover path is unsupported.

## REQ-M — Throughput

### REQ-M1.1 — One snapshot per source per program [test]

Two duties reading the forge snapshot cause one forge read per cadence;
each snapshot carries its age; a fixture second source refreshes on its
own cadence without a forge read; a fixture adapter reporting exhausted
rate-limit headroom delays its next read.

### REQ-M1.2 — Push first, poll failsafe [test]

Same fixture as REQ-E1.3.

### REQ-M1.3 — No duplicate work [test]

An unchanged patch id yields no re-review trigger; a unit with a remote
branch is not dispatched again; a landed unit's slot frees within one sweep.

### REQ-M1.4 — Pipelining [test]

With one fixture unit waiting on CI, the next ready unit dispatches.

### REQ-M1.5 — Merge order from the whole graph [test]

The radar computes order across two fixture repositories and a retarget on
a base merge.

### REQ-M1.6 — Scheduled by host budget [test]

Heavy work queues behind the host budget rung in fixtures.

### REQ-M1.7 — Allocated model tier [test]

Each launch resolves its tier through the allocation seam; a fixture with
no tier is refused; the same inputs yield the same session name.

### REQ-M1.8 — Measures [test]

Interruptions per hour and the settled share compute from log fixtures and
draw on the panel.
