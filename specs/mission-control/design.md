# Mission control — Design

**Status:** Draft
**Last reviewed:** 2026-10-22
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` new in this bundle; `C, <bundle> D-n` carried from a
sibling bundle; `S` a decision the operator settled in the drafting session.

## Decision log

### D-1: Altitude — capability plus doctrine; the front door for most operators  (N)

**Decision:** Mission control is a planwright session kind at the
capability altitude, with a doctrine document stating the rules no script
can enforce (the register, the autonomy mapping at this tier, the duty
contract). It is the front door most operators use: planwright's own
vocabulary and skills become internal, run on the operator's behalf up to
the human gates. It consumes planwright's seams (the tower, the attention
store and operator queue, the fleet registry and daemon layer, the dispatch
backends, the catalog resolver, the policy guards, model allocation) and
mints exactly one new extension point, the duty catalog. The bundle is the
core; the larger duties are follow-on bundles (D-27).

**Alternatives considered:**
- A local hub with its gaps closed one by one (the seed's other branch).
  Rejected because: every gap the record lists is a general capability an
  independent adopter would want, and a local hub cannot deliver rules to
  the sessions it launches without planwright's launcher.
- A mode of `/orchestrate` (a meta-tower that also talks). Rejected
  because: the orchestrator is disposable and stateless by design; mission
  control is standing and conversational.
- One bundle holding every duty. Rejected because: the review desk, spec
  currency and the environment broker are each independently ownable and
  force decisions orthogonal to the core (bootstrap D-21), and a reader
  cannot hold the sum in their head.

**Chosen because:** every pinned seed claim points at capability altitude
(a new session kind, configurable like the rest of planwright, rules that
do not slip at scale), and the operator's own call in the session was that
mission control is the abstraction most people need. Recording the
altitude here lets the kickoff lens verify the task decomposition against
it.

### D-2: Built on the tower; its limits lifted in mission control's own posture  (S)

**Decision:** Mission control reuses `/tower`'s conversational contract,
router, flight machinery and permission posture by reference, and states
only its deltas: supervision of the sessions it launches, watchers and a
failsafe tick, a program spanning repositories, and the duty seam. The
tower's own text keeps its "no watch loop, no supervision, one repo" rules
for the plain tower; `/tower` remains the single-repo, no-duties front door.
Mission control never edits a settings file or widens its posture
(tower-front-door D-14 carries).

**Alternatives considered:**
- Replace `/tower`. Rejected because: single-repo adopters would inherit a
  program home, duties and a panel they did not ask for.
- A sibling skill with its own prose. Rejected because: the instruction
  budget is at its closure cap and the contract prose would double.

**Chosen because:** existing-seam-reuse, and the budget: the only way a
skill of this size lands is by reference and by pushing mechanics into
scripts and catalogs (D-21).

### D-3: Duties are a data catalog merged through the overlay layers  (S)

**Decision:** A duty is an entry in a `duties` catalog (`config/duties.yaml`
in core, `catalogs/duties.yaml` in the adopter and repo-tracked overlays,
`catalogs.local/duties.yaml` machine-local), merged by the existing catalog
resolver with append/union and supersede-by-id. An entry carries: `id`, a
one-line `summary` of what it saves the operator, `triggers`, `watchers`
(each a script with a cadence and a cost class), `wake` (the event that
reaches the session), `rules` it contributes to the rule store, the
operator-item `kinds` it may raise, the `files` subdirectory it owns under
the knowledge base, its `lifecycle` (`off`, `shadow`, `live`) and a
`never-propose` flag. Enabled duties are a program-level list. A disabled
duty arms nothing and owns nothing.

**Alternatives considered:**
- Duties as skills. Rejected because: a skill costs instruction budget and
  cannot declare watchers or files; the judgment half of a duty may still
  invoke a skill in its on-demand session.
- A hardcoded default list inside the skill. Rejected because: custom duties
  would then need a core edit, which the customization boundary forbids.

**Chosen because:** the step catalog already proves the shape (a core seed,
overlay entries, supersede-by-id, a constrained reader), and the operator
wants shipped defaults plus custom duties.

### D-4: Mechanics are scripts, judgment is on demand  (S)

**Decision:** Every duty's watchers, detectors, sweeps and ticks are
deterministic scripts under the fleet daemon gate, armed and re-armed by a
runner that outlives any session. Judgment runs in a short-lived session
launched per trigger, draft-only, exiting when done. No standing LLM
session watches anything, including other towers.

**Alternatives considered:**
- A standing "attention worker" session that watches on behalf of towers.
  Rejected because: it relocates the memory burden (a session that must
  remember to tick), breaks the no-LLM-daemon floor and the "never another
  tower watching a tower" rule, and the record shows standing watchers were
  most of a day's spend while still missing events.

**Chosen because:** push from scripts woke the hub reliably; its standing
desks did not.

### D-5: The rule store, its supersession, its re-injection and its delivery  (N)

**Decision:** Rules live in `rules.yaml` in the program home: entries with
`id`, `text`, `source` (who said it, when, where), `date`, `scope` (program,
duty, repository) and `supersedes`. A helper adds, supersedes, lists and
renders the active set; the active set excludes superseded entries. The
active set is loaded whole at bring-up and re-injected after compaction by
the panel mod's post-compaction hook, with the skill's own bring-up step as
the fallback where the mod does not load. The launcher renders the rules in
scope into every launched session's brief through the launch-brief seam.

**Alternatives considered:**
- Rules as memory files. Rejected because: memory is per session, cannot be
  delivered to launched sessions, and has no supersession, which is exactly
  how the record's rule conflicts arose.
- Rules in a repository instruction file. Rejected because: they would be
  committed, visible to every reader and carry company data.

**Chosen because:** supersession and delivery are the two properties the
twelve-day record lacked; both need a structured store with one writer.

### D-6: The panel is a mod shipped in the planwright plugin, with a text fallback  (S)

**Decision:** The planwright plugin ships a mod. It draws a pane and a band
above the prompt from the attention store, the registry, the forge
snapshot, the budget file and the ledgers, read on a timer; it reads
context percent and rate-limit headroom from the session usage call; it
runs the failsafe tick from its timer and submits a prompt only when a tick
is due and the session is idle; it feeds presence to the queue from prompt
events; it re-injects rules on the post-compaction hook. Animation uses
the mod's client element or raster repaint within the redraw throttle, with
light aviation theming. Where the mod does not load (versions before
2.1.287, headless and cloud sessions) everything it shows is available as
the fixed status form and the queue render, and the daemon runner carries
the failsafe tick. The version floor is accepted as a dependency adoption.

**Alternatives considered:**
- Require the floor. Rejected because: it excludes older installations and
  every headless use.
- No mod in v1. Rejected because: the live surface is what lets the
  operator stop asking for status, and the usage call is the only honest
  context signal available.

**Chosen because:** the research showed every capability the surface needs
exists in the mods API, and the fallback keeps mission control usable
everywhere.

### D-7: The queue decides delivery; the mod observes  (S)

**Decision:** The operator queue stays the single delivery authority. This
bundle depends on a routed tower-comms amendment adding: a presence input
(from the mod's prompt events, falling back to the quiet-interval
detector), picklist windows with a declared default or park, and two item
kinds, settled-by-default and decided-by-mission-control, both visible and
reversible. The mod renders the queue and never intercepts a message.

**Alternatives considered:**
- The mod holds inbound messages while the operator is away. Rejected
  because: it splits delivery authority and depends on a mod event headless
  sessions never fire.
- The mod as a failsafe gate only. Rejected because: a second path with
  its own tests for little gain.

**Chosen because:** tower-comms made the queue the authority for exactly
this reason, and the record's lost-update and never-cleared rows argue for
one writer.

### D-8: The program is the launch unit; its home is private and class 3  (N)

**Decision:** A `program` block in configuration names the work
repositories, the spec root, the program home, the enabled duties and the
budget. One mission control runs per program, under the program's name.
The program home defaults to `mission-control/<program>/` under the plugin
data home (the adopter data overlay root) and is overridable; it holds the
rule store, the knowledge base, the ledgers, the budget file and duty files.
It is class 3 work product: never inside a work repository, never
committed.

**Alternatives considered:**
- A home inside the repository under an ignored path. Rejected because: a
  program spans repositories, and ignored files are deleted with worktrees
  (the record lost audit files that way).
- A global home for every program. Rejected because: two programs' rules
  and queues would mix.

**Chosen because:** storage-classes already reserves the data home for
framework-authored state and work product; the record's hub lived in such a
folder and survived every session.

### D-9: Knowledge-base layout and the three loading rules  (S)

**Decision:** The knowledge base is a directory in the program home with an
`index.md` of one line per entry, loaded whole at bring-up; bodies read on
demand; any read above the per-entry cap offloaded to a read-only session
that returns an answer, never the file; a per-duty subdirectory per enabled
duty; a `decisions.log` and an `undo.log`, both append-only and queried by
subject; a follow-up ledger; a living-versus-consumed source table with
watermarks. One writer per file, held by a lock file. Specs, tickets and
sources are cited, never copied.

**Alternatives considered:**
- Load the knowledge base whole. Rejected because: it fills the window
  with reference material and the session loses the picture it exists to
  hold.
- A database. Rejected because: plain files stay auditable, diffable and
  recoverable by hand, and the stores this reads already are files.

**Chosen because:** tower frugality bounds inline ingestion, and the record
shows only rules and decisions stayed true while state rotted.

### D-10: One launcher for every session kind  (N)

**Decision:** A launcher script composes the existing dispatch primitives
(the flight dispatcher, the tmux and stream-json fleet dispatchers, the
offload seam) to start a session of any kind (tower, orchestrator, worker,
reviewer, ad-hoc), delivering the brief, the in-scope rules, the permission
profile, the model tier from the allocation seam and a deterministic name,
and registering the session with its owner, kind and scope. It has a
`retire` verb that exits the session, closes its pane and clears its
registry and attention rows, reporting any part it could not release.

**Alternatives considered:**
- One launcher per kind. Rejected because: the delivery contract (brief,
  rules, profile, tier, name, registry row) is the same for every kind and
  diverges silently when copied.

**Chosen because:** the record's worst stalls were launches that delivered
nothing (no profile, no prompt, no model), and one path is testable.

### D-11: Liveness and stall states for every session kind  (N)

**Decision:** Liveness is the registry pid and process state. The stall
detector enumerates positive states for every session kind: dead, open
selector, unsubmitted prompt, turn ended with background work, idle with a
question in its pane, busy with no change past the stall window. Each state
is an event. Extending the detector's resource classes from workers to
every kind rides a routed fleet-lifecycle-closure amendment.

**Alternatives considered:**
- Elapsed time and pane stability as the signal. Rejected because: a frozen
  pane is stable precisely because it is stuck, and a dead reviewer read as
  idle.

**Chosen because:** the lifecycle-closure floor requires positively named
states, and the record's stall detector missed exactly the unnamed ones.

### D-12: One age-stamped forge snapshot per program  (N)

**Decision:** A script refreshes one snapshot per program per cadence (PR
heads, draft state, mergeability, review decision, open threads, checks,
reviews and comments for the program's tracked PRs), age-stamped, with a
patch id per PR so an unchanged patch is recognized. Every duty reads the
snapshot; none polls the forge itself. The cadence and the tracked set are
knobs; the refresher backs off on rate-limit headroom.

**Alternatives considered:**
- Each watcher polls what it needs. Rejected because: the record ran three
  pollers over the same PRs and the dashboard re-ran the full merge each
  tick.

**Chosen because:** the staleness tolerance is a program knob, which makes
the cache decision a configured one rather than a product guess.

### D-13: Autonomy at the mission-control tier, with calibration  (N)

**Decision:** Decisions map onto the autonomous-safe-decision buckets at
this tier: a decision reaches the operator only at a human gate, a fork the
record and sources cannot settle, or a hard-disqualifier zone; every other
decision is taken, logged with grounds as decided-by-mission-control, and
shown for review. A given go is not re-asked unless a check changes the
answer; a likely answer is searched for first and asked as a confirmation
with its source. A revoked self-decision lowers its decision class to
ask-first until a configured run of confirmations restores it; the hit rate
is on the panel. Interruptions per hour and the settled share are measured.

**Alternatives considered:**
- A static autonomy policy. Rejected because: the record shows both
  over-asking (re-asking given goes) and over-acting (flipping without a
  walk); only measured calibration moves both.

**Chosen because:** the operator's load scales with decisions only they
can make, and the whole-picture position settles more of the rest.

### D-14: Duty proposals and rule proposals  (S)

**Decision:** A detector over the decisions log and the operator's asks
counts repeats per shape (the same ask kind, a manual step after the same
event, the same answer to the same question) against a threshold and a
window. When a shipped or custom duty covers the repeat, mission control
proposes it as a confirmation in the operator's words: what it noticed, the
plan, the cadence, where the operator still intervenes, the cost, how to
turn it off, an explicit decline. An accepted proposal enables the duty and
writes its rules; a declined one is recorded and not re-proposed unless the
pattern changes; "not now" parks it with a trigger. A repeated correction
proposes a rule entry the same way. Nothing enables itself. The duty catalog
is shown in the guided first run and on request.

**Alternatives considered:**
- Enable the obvious duties by default and let the operator turn them off.
  Rejected because: a duty acts on the operator's behalf; consent must be
  explicit.
- Leave discovery to documentation. Rejected because: the autopilot reflex
  names "we keep doing X manually" as the trigger the machine should catch.

**Chosen because:** it is the runtime form of the reflex, and the hub's
memory rules were all born as repeated corrections.

### D-15: Shadow mode as a duty lifecycle state  (S)

**Decision:** A duty's lifecycle is `off`, `shadow`, `live`. In shadow the
duty watches, decides and writes would-have entries to its log and raises
nothing; promotion to live is an operator act, suggested after a
configured number of agreed entries.

**Alternatives considered:**
- Live or off only. Rejected because: a custom duty acting on the
  operator's behalf needs a way to earn trust.

**Chosen because:** it is how a guided system introduces a new mechanic.

### D-16: The self-audit duty  (S)

**Decision:** A scheduled, mechanical pass compares the decisions log and
the undo log against the active rule set: acts a rule forbids, rules with
no act for a configured period, two active rules on one subject. Findings
become operator items or rule proposals. The audit edits nothing.

**Alternatives considered:**
- Audit by an LLM pass over the transcript. Rejected because: the floor
  reserves mechanics for scripts, and the record's seven-pass audit was a
  one-off nobody could afford to repeat.

**Chosen because:** drift was invisible for days; a cheap scheduled compare
is what makes it visible.

### D-17: Budgets and the degradation ladder  (N)

**Decision:** A per-program budget file bounds live sessions, forge polls
per hour, spend class per duty, context steps and host load. Each duty and
watcher declares cost and cadence. Under pressure the ladder is declared:
throttle low-value duties, pause watchers by cost class, hold dispatch,
hand over the session; the quota-handling `limited` outcome and the
fleet daemon pause are reused as rungs. Headroom and watcher expiries are
on the panel.

**Alternatives considered:**
- A worker-count cap only. Rejected because: the record shows host load,
  not head count, broke gates and parked finished units.

**Chosen because:** limits at this altitude are plural and have all bitten
once; modelling them beats discovering them.

### D-18: The guided first run and the guidance knob  (S)

**Decision:** With no program configured, mission control runs a guided
first run: one objective at a time (repositories, spec root, forge access,
duties to enable, voice and quiet hours), visible progress on the panel,
immediate feedback, hints only when stuck, scaffolds that fade per concept.
It ends by writing the program block, the knowledge-base skeleton and the
enabled duties. A guidance knob (guided, standard, expert; guided on a
fresh installation, remembered per operator) sets the depth everywhere.
The didactics shape the turn and the panel and never soften a normative
token, pre-select an option or pad a turn past the density rules.

**Alternatives considered:**
- A setup document. Rejected because: the operator will not read it, and
  interaction-style already prefers teaching inside the dialogue.

**Chosen because:** mission control is meant for operators who do not know
planwright; a guided first run is how they get a working configuration.

### D-19: The register, stricter than tower-comms  (N)

**Decision:** Delivered items are phrased in the operator's domain: PRs by
title and link, tickets, people, decisions, what changes for whom. Skill
names appear only when the operator must run one themselves; spec, task and
decision identifiers never. Drafts for people are in the operator's voice,
matched in length to what they answer, one bundled message per person, to
the clipboard unless told to send. The tower-comms scorecard word list is
extended with planwright's skill and flight vocabulary for this session
kind.

**Alternatives considered:**
- Inherit the tower-comms register as is. Rejected because: it allows
  planwright's basics, which mission control's operator need not know.

**Chosen because:** the panel carries the whole picture, so the turn can
afford to carry none of the machinery.

### D-20: Every preference is a knob  (S)

**Decision:** Every behaviour that admits a preference is a
`mission_control_*` key in the defaults file with an options-reference
row naming its default and the evidence it came from, resolved through the
four layers and default-preserving. Tower-front-door's zero-knobs decision
does not bind a new session kind; each knob cites the record that earned
it.

**Alternatives considered:**
- Minimal knobs, overlay prose for the rest. Rejected because: the operator
  asked for personalization, and a preference expressed only as prose is
  the "stated once per session" burden this bundle removes.

**Chosen because:** the customization boundary admits a core knob with
evidence, and the record supplies it knob by knob.

### D-21: Staying inside the instruction budget  (N)

**Decision:** The mission-control skill states its deltas from the tower by
reference, and its mechanics live in scripts, the duty catalog and the
doctrine doc; the budget checker runs in CI against the skill and its
closure. A task that would push the closure past its cap moves prose into
a script's usage header or the catalog instead of raising the cap.

**Alternatives considered:**
- Raise the cap for this skill. Rejected because: the cap exists to keep
  every skill loadable; the closure is already at it.

**Chosen because:** budget trims by deduplication are exhausted; only
structure keeps a skill of this size inside it.

### D-22: Cross-bundle edges  (N)

**Decision:** This bundle depends on routed amendments it names and does
not re-decide: tower-comms (presence input, picklist windows, the two item
kinds), fleet-lifecycle-closure (resource classes for every session kind),
custom-spec-location (the holder-to-work-repository reverse registry),
invariant-tasks and spec-format (a per-task repository field and per-repo
dependency state), fleet-hardening (a tower permission floor independent of
the launch), merge-currency-guard (the deterministic pr-ready attention
record), worker-permission-ergonomics (profile delivery at dispatch). It
seeds four follow-on bundles through pending notes: review desk, spec
currency, environment broker, night shift.

**Alternatives considered:**
- Decide those pieces here. Rejected because: each has an owner whose scope
  text claims it; a second decision would conflict with the first.

**Chosen because:** the fold-detection pass named the owners, and the
operator chose routed amendments over a self-contained bundle.

### D-23: Non-authoring and relay  (C, fleet-coordination-floor; tower-front-door D-2)

**Decision:** Mission control edits no repository and runs no git mutation;
reads are in bounds. It reaches a session by cross-session message first and
by the pane relay only when the message cannot land; it never types a yes
the operator did not give; it never hands the operator a pane. A denial by
any hook, guard or classifier, in any session it runs, is reported with its
exact text and never worked around.

**Alternatives considered:**
- The narrow "quick change" exception. Rejected because: the floor names it
  as the rationalization that caused the logged incident, and the record's
  hub drifted into branch work the same way.

**Chosen because:** the hub's own last rule, after a bypass incident, was
this one.

### D-24: The undo ledger  (S)

**Decision:** Every automated act appends an entry naming the act, its
target, its grounds and a one-step reversal command where one exists
(resolve a thread, re-approve, retire a session, park a unit). The panel's
recent-decisions view reads it, and a revoke runs the reversal.

**Alternatives considered:**
- Rely on the decisions log alone. Rejected because: reviewing an act is
  cheap only when reversing it is cheaper.

**Chosen because:** act-then-review needs a cheap undo to stay honest.

### D-25: The readiness-check duty and prepared packets  (S)

**Decision:** A readiness-check duty verifies, from primary evidence at the
current head, every condition the program's gate-condition data names
(recorded cadence steps, CI including individual contexts, review threads,
automated reviewer findings answered, smoke and walk evidence present,
screenshots opened and judged, body conventions) before a flip is offered
or requested; it composes the existing ready-flip guards and never claims
ready from a session's report. The prepared-moments duty assembles the
packet before a human gate (what to look at, what changed since the
operator last looked, risks, merge order from the whole graph) and the
readiness result is its first section.

**Alternatives considered:**
- Fold the check into the packet. Rejected because: the check must run
  before a session requests a flip, packet or not.
- Route it to the flip guard bundle. Rejected because: that guard owns the
  act, not the evidence walk.

**Chosen because:** every "unverified ready" in the record was caught only
by a primary-evidence check.

### D-26: Gate conditions as configurable data, inside the floors  (S)

**Decision:** Ready-when and merge-recommendation conditions are data per
program, repository, label or path (required steps, evidence kinds, who
resolves a conflict, when to recommend a merge and in what order). Mission
control evaluates them to prepare, verify and recommend. They never place a
flip or a merge below the human-gates floors: the configured
`ready_flip_policy` and `merge_policy` bound them, and no condition can
authorize a merge.

**Alternatives considered:**
- Fixed conditions in the skill. Rejected because: the record shows
  per-repository rules (merge commits forbidden in one, conflicts to the
  operator in another) that no fixed list can carry.

**Chosen because:** the operator asked for conditional instructions per
case, and the floors make that safe.

### D-27: The default duty set and the follow-on bundles  (S)

**Decision:** This bundle ships: session-keeper (lifecycle, D-10, D-11),
inbox (the operator surface, D-7, D-19), readiness-check (D-25),
conflict-radar (same-file and same-line prediction across the program's
branches, merge order and stack retargets from the whole graph),
deadline-watch (calendar and date sources drive priority and the first turn
after silence), prepared-moments (D-25), undo-ledger (D-24), self-audit
(D-16) and proposals (D-14). Review desk, spec currency, environment broker
and night shift are follow-on bundles, each seeded by a pending note.

**Alternatives considered:**
- Ship the review desk as the reference duty here. Rejected because: it is
  the most evidenced but also the most decision-heavy, and not every
  operator runs one.

**Chosen because:** the shipped set is what every mission control needs;
the follow-ons are what some do.

### D-28: Decision-domain walk  (N)

**Decision:** Domains touched and decided here: data storage and modelling
(D-5, D-9, D-24), caching (D-12), queues and async work (D-4, D-7), API
surface (the duty entry format, the launcher verbs, the knobs: D-3, D-10,
D-20), secrets and configuration (every knob documented, D-20; secrets never
in the program home, D-8), concurrency (one writer per file, D-9),
observability (the panel and the measures, D-6, D-13), dependency adoption
(the mods API and its version floor, D-6), LLM output quality (proposal and
routing judgment eval-gated, test-spec), human comprehension (the panel and
items, researched against the mods docs and interaction-style, D-6, D-19),
existing-seam reuse (D-2, D-3, D-10), knowledge engineering (the
knowledge-base taxonomy, D-9), product strategy (front-door positioning,
operator-decided, D-1). Authentication and authorization adds no new
surface (profiles are delivered unchanged); organization design is
unchanged (the human gates). Not touched: deploy and migration, versioning
scheme, packaging and pricing, IP posture.

**Alternatives considered:**
- Leave the walk to kickoff. Rejected because: the drafting phase is where
  the catalog is consulted so the spec decides rather than inherits.

**Chosen because:** the kickoff gap check then has nothing to flag.

### D-29: Handover over compaction  (S)

**Decision:** Mission control prefers a continue-as-new handover to a
compaction. The trigger is measured context percent from the session usage
call where the harness exposes it, the completed-step proxy otherwise, and a
compaction-count ceiling in either case; the mod's compaction hook defers
a compaction while a handover is possible. When a compaction happens
anyway, the active rules are re-injected and the session runs a self-check
against durable sources (rules present, open items known, live sessions
known) before its next act; a failed re-injection is an operator item.
Compactions since start sit on the panel.

**Alternatives considered:**
- Compaction with a better summary prompt. Rejected because: the record's
  summaries kept decisions and dropped rules across many compactions; a
  fresh session from durable state loses nothing by construction.

**Chosen because:** context-budget-autoheal already relies on the
disposable session; measured context makes its trigger honest.

### D-30: Automatic, lossless succession  (S)

**Decision:** At the trigger, the predecessor asks the launcher for a
successor with a handover file (its last ledger sequence, open items,
live sessions). The successor rebuilds from durable state, proves it holds
the active rules and the open items against that file, takes the program
name, re-announces itself to every live session, and the predecessor
retires itself; the operator sees one line. How the successor takes the
name unattended is the research item of the compaction task; where the
harness cannot swap it, the fallback is one operator act offered on the
panel, never a degraded session.

**Alternatives considered:**
- Operator-driven handover only. Rejected because: a ritual that survives
  on the operator remembering it is the gap the autopilot reflex closes.

**Chosen because:** the operator's ask is that compaction and resume happen
automatically without degradation.

## Cross-cutting concerns

- **Data hygiene.** The program home holds company data by design and is
  never committed; every committed artifact this bundle produces (catalog
  seeds, docs, pending notes) is neutral.
- **Instruction budget.** D-21 governs every task that adds skill prose.
- **Floors.** Non-authoring, no-LLM mechanics, assume multiplicity,
  deterministic attention, lifecycle closure and the human gates carry
  unchanged into every decision above.
