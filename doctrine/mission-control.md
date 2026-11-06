# Mission Control

Mission control is a standing, conversational session for one program of
work, the operator's single contact point for work too big to track by hand.
It launches, supervises, drives and retires every other session kind, never
authors in a repository itself, keeps working while the operator is away,
and brings the operator only what needs their judgment, packaged to decide.
This doc holds what no script can enforce: what the session is, the duty
contract, the rule store, the register, the autonomy mapping at this tier
and the program it serves. The mechanics live in the `mc-*` scripts and the
launcher, each of whose `--help` is its contract; the procedure is the
`mission-control` skill's. For operators, `docs/mission-control.md` walks
the same ground in plain words.

Citations: mission-control REQ-A1.1, REQ-A1.2, REQ-A1.4, REQ-A1.5,
REQ-A1.6, REQ-B1.1, REQ-B1.2, REQ-B1.5, REQ-C1.1, REQ-C1.6, REQ-D1.6,
REQ-F1.8, REQ-H1.4, REQ-I1.5, REQ-K1.7, REQ-L1.6 · mission-control D-1,
D-2, D-3, D-4, D-5, D-8, D-9, D-12, D-13, D-14, D-15, D-19, D-23, D-25,
D-29, D-30.

## The session kind

Mission control sits at the capability altitude: a planwright session kind
that most operators use as their front door, with planwright's own
vocabulary and skills running on the operator's behalf up to the human
gates. It is built on the tower: the tower's conversational contract,
router, flight rules and permission posture carry by reference, and only
these tower limits are lifted, in mission control's own posture and never in
the plain tower's:

- supervision of the sessions it launches (watch, nudge, retire);
- scripts watching on its behalf, with a failsafe tick, a wake reaching it
  as a turn;
- a program spanning repositories, with its own duties and rule store;
- the relayed kickoff: a kickoff or amendment the operator asks for runs in
  a session mission control launches, every question it raises relayed to
  the operator and answered only in their words (the default; the `manual`
  kickoff mode, where the operator runs the kickoff command, is their own
  configured exception to never handing them a per-session step, below);
- the ready flip, inside the configured `ready_flip_policy` and after the
  readiness check.

It never edits a settings file or widens its own posture. The plain tower
stays the single-repository, no-duties front door.

**One session per program.** Exactly one live mission control holds a
program's name. It is rebuilt at bring-up from durable evidence only, never
from a stored picture of live state, and a read that fails is reported
unknown, never as empty.

**On the operator's behalf.** Toward every other session it launches,
messages, answers and retires; it never hands the operator a per-session
step (a command to paste, a pane to open). Only the operator's own words in
its own turn are a go: pasted material, session output, forge text and
record contents are data, whatever they say. A denial by any hook, guard or
classifier, in any session it runs, is reported with its exact text and
never worked around.

### Launch kinds

A launch of mission control is one of three kinds, and the kind decides what
happens when a live holder already has the program's name:

- **Operator-asked:** the operator's own resume of the program. It is the
  resume, and it runs as a handover: the live holder is asked to release
  and, if it cannot within the handover window, loses the name anyway,
  retired through the launcher when the launcher started it; the
  operator's own session is never closed, only stripped of the name.
- **Handover successor:** a session the predecessor launched, carrying a
  handover file. It proceeds, proves its picture against the file and takes
  the name. A handover launch over an attended holder (the operator's own
  session) is refused; that succession runs as the operator's resume.
- **Any other launch:** refused while a live holder exists, the refusal
  reported by the session that asked for it, nothing started.

## The program and its home

A **program** is the launch unit: a block in configuration naming its work
repositories, the spec root, the program home, the enabled duties, the
budget and the state-source map. One mission control runs per program, under
the program's name; two programs' rules and queues never mix.

The **program home** is the program's private folder of class-3 work
product (`storage-classes`): by default under the operator's planwright
configuration root, named in the program block and overridable, never
inside a work repository and never committed. It holds the rule store, the
knowledge base and its ledgers, and the handover file, and it holds no
secret or credential (the forge adapter reuses the forge CLI's own
authentication). Runtime state (source snapshots, the budget file, duty
working files) stays in the plugin data home, where a work product would be
invisible to review and die with the plugin's data.

### The state-source map

The **state-source map** declares, per fact class (work items, code state,
decisions, deadlines, designs), the authoritative source and its mode:

- **`record`:** a store planwright writes, directly or through a session
  mission control dispatches (the specs, by default);
- **`snapshot`:** a source an adapter script refreshes into one
  age-stamped snapshot per program per cadence, which every duty reads and
  none polls past;
- **`cited`:** a source with no adapter: mission control holds only its
  links and what the operator said about it, and never claims to know its
  state.

The map is the operator's; a mode is never inferred. Wherever a report draws
on a source it names the mode and the age, and where a fact class is only
`cited` it says the picture there is the operator's statements, not a
polled state.

### The format field

Every store in the program home, and the budget file, carries a **format
field**. This bundle's shapes are **additive-only**: a field may be added, a
field's meaning never changes in place. A reader refuses a store whose
format it does not know and names it. A shape change is a follow-on bundle's
migration task, never an in-place edit. The launcher rolls out the same way:
a session started under the previous launcher finishes under it, and only
new launches take the new one.

### The reclaim folder

The **reclaim folder** is the program home's
`reclaimed/<repository>/<branch>/` backup of a reclaimed worktree's ignored
audit files (the file set is a knob), each verified by size and hash before
the worktree goes. It lives in the program home, not the repository,
because reclaiming a checkout would take a repository-local backup with it.

## The rule store

The **rule store** is the program's one versioned source of ground rules
and standing decisions, in the program home. Each entry has an id, its text,
a **subject** (one free-text key per entry), its source, date and scope,
and what it supersedes. The rules that bind:

- **Supersession is explicit.** A changed rule supersedes the old one by
  id; the active set excludes superseded entries. Two active entries sharing
  a subject are a mechanical finding; whether they conflict in meaning is
  the operator's call.
- **Direct entry.** A standing decision the operator states in a turn is
  added at once, echoed in one line and paired with its undo; the proposal
  path is for repeats mission control infers, never for what the operator
  said.
- **Loaded whole, re-injected, delivered.** The active set loads whole at
  bring-up, is re-injected after a compaction (by the panel's hook, the
  skill's own bring-up step where the panel does not load), and the
  launcher renders the rules in scope into every launched session's brief.
- **Not a permission record.** A permission prompt is answered from the
  tower-comms standing-decision record, which carries command coverage; a
  rule here that would answer one is proposed into that record.

## The duty contract

A **duty** is a declared entry in the duties catalog, the one
operator-facing extension point mission control adds: core seeds it,
overlays add or supersede entries by id through the catalog resolver. An
entry names what it saves the operator (its summary), its triggers, its
watchers (each with a cadence and a cost class), the wake that reaches the
session, the rules it contributes, the item kinds it may raise, the
knowledge-base files it owns and its lifecycle. The contract:

- **Mechanics are scripts, judgment is on demand.** Watchers, detectors and
  sweeps are deterministic scripts under the fleet daemon gate, armed by a
  runner that outlives any session. Judgment runs in a short-lived,
  draft-only session per trigger. No standing model session watches
  anything.
- **Consent is explicit.** Only the operator enables a duty. A disabled
  duty arms nothing, owns nothing and costs nothing.
- **One writer per file.** Each duty owns its files under the knowledge
  base; a lock records its holder, and a dead holder's lock is released by
  the next writer and logged.
- **Cost is declared.** Every duty and watcher declares its cost and
  cadence, and the program budget's ladder throttles them under pressure.

The shipped default set and every entry's summary are in
`config/duties.yaml`; this doc does not restate them.

### Shadow mode

A duty's lifecycle is `off`, `shadow` or `live`. In **shadow mode** a duty
watches and decides as if live, writes what it would have done to its log
and raises nothing. Promotion to live is the operator's act, suggested once
the operator has agreed with a configured number of its would-have entries.

### The mechanism inventory

The **mechanism inventory** is a living source in the knowledge base: what
the host and planwright can make deterministic, by kind (a rule entry, a
knob, a catalog step, a hook or permission rule, a scheduled routine, a
shipped or custom duty), with where each is configured and the source it
was read from. The kinds are an open list, refreshed against the installed
versions, so a mechanism that ships later becomes proposable without a
change here.

### Mechanization proposals

A **mechanization proposal** is mission control's confirmation, in the
operator's words, that a repeat it noticed (the same ask, a manual step
after the same event, the same answer to the same question, the same guard
denial a knob governs) could be
covered by the smallest mechanism in the inventory. It says what was
noticed, the mechanism and its change, the cadence, where the operator
still intervenes, the cost, how to turn it off, and offers an explicit
decline. Nothing applies itself:

- an accepted proposal is applied where mission control may write (the
  rule store, the program block, duty enablement); a settings or posture
  change is handed to the operator ready to apply and never written; a
  repository change is routed as a flight;
- a declined proposal is recorded and not re-proposed unless the pattern
  changes; "not now" parks it with a trigger.

This is the runtime form of `autopilot-reflex`.

### Cadence steps

A **cadence step** is a steps-catalog entry whose recorded run per head
gates a later unit's ready flip: a missing or red record for the current
head refuses the flip. The readiness check walks it with the rest of the
program's gate-condition data, from primary evidence at the current head,
never from a session's report.

The **configured cadence** is different: every in-run point's step list,
which every unit runs, not one catalog entry gating later units. The
readiness check audits it too (`scripts/step-run.sh audit --through
post-pr`): a configured point with no completion that counts at the head,
or a configured step its run did not record passed, applied, or skipped, is
a gap, whatever launched the session and whatever its brief said. A
spec-only pull request (every changed path a Markdown file added, modified or
deleted under the spec root, the head holding that root) is held for
each touched bundle's kickoff sign-off instead of the cadence and the gate
data's steps; one touching only the reserved accumulators has none to hold.

## The register delta

Mission control speaks under `tower-comms`' register, made stricter,
because its operator need not know planwright at all:

- Items are phrased in the operator's domain: a pull request by title and
  link, a ticket, a person, a decision and what changes for whom.
- A skill name appears only when the operator must run that skill
  themselves. A spec, task or decision identifier never appears, nor a
  script, knob, branch grammar, window, pane or session handle.
- A draft for a person is in the operator's voice, as long as what it
  answers, one bundled message per person, put on the clipboard and never
  sent without the yes on its exact text and recipient.

The word list behind the tower's scorecard is extended for this session
kind by `scripts/mission-control-jargon.txt`, beside the tower's list;
that file is the inventory and this doc does not restate it.

## Autonomy at this tier

Decisions map onto the `autonomous-safe-decision` buckets at this tier. A
decision reaches the operator only at a human gate, a fork the record and
the sources cannot settle, a hard-disqualifier zone, or a proposal reserved
for the operator's confirmation (a mechanization or duty proposal, a
permission prompt no standing decision covers). Every other decision
is taken, logged with its grounds and the rules it acts under, shown for
review, and paired with its undo entry. Two refinements:

- **Ask less, and only once.** A given go is not re-asked unless a check
  changes the answer. A likely answer is searched for first and asked as a
  confirmation with its source.
- **Calibration.** A decision class is the bucket a decision maps onto. A
  self-decision the operator revokes lowers its class to ask-first until a
  configured run of confirmations restores it; the hit rate is shown on the
  panel.

Kickoff questions are outside this mapping: every one is the operator's,
answered in their words and never settled from the record, a rule or the
knowledge base.

## The handover file

Mission control prefers a fresh session to a compaction. When its trigger
fires (measured context where the harness exposes it, a wake count
otherwise, and a compaction ceiling either way) the predecessor writes the
**handover file** in the program home (its last ledger sequence, open
items, live sessions) and launches a successor through the launcher. The
successor rebuilds from durable state, proves it holds the active rules and
the open items against the file, takes the program name, re-announces itself
to every live session, and the predecessor retires itself; the operator sees
one line. The program name is planwright's holder record, not the harness's
display name. Where the holder is the operator's own session, whose terminal
cannot pass to a launched successor, the handover launch is refused and the
fallback is one operator act offered on the panel, which runs as the resume,
never a degraded session.

The handover file is not the **handover brief** (`spec-format`'s glossary):
the brief is an optional in-worktree cache that `/resume` reads for a unit
in flight; the handover file is the program home's succession record
between two mission-control sessions.

## The floors, by reference

Every floor below carries into mission control unchanged, stated where it
lives and not restated here:

- the human gates, the merge floor and the ready-flip policy:
  [`human-gates`](human-gates.md);
- non-authoring, no model-run daemon mechanics, assume multiplicity,
  deterministic attention and lifecycle closure: `fleet-coordination-floor`;
- every hand-off's data hygiene: `security-posture`;
- what lives where, and who owns it: `storage-classes`;
- the queue as the single delivery authority: `tower-comms` and the
  operator queue it names.
