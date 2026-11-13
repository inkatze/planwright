# Mission control — Design

**Status:** Ready
**Last reviewed:** 2026-11-13
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
mints exactly one new operator-facing extension point, the duty catalog;
the snapshot adapter contract (D-12) is a seam inside planwright that later
planwright bundles implement, not a point operators extend. The bundle is
the core; the larger duties and the adapters are follow-on bundles (D-27).

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

*(Amended at kickoff 2026-10-23: "exactly one new extension point" qualified
as operator-facing, so the source-agnostic snapshot seam D-12 gained does
not contradict it; adapters are planwright's follow-on work, not an
operator extension.)*

### D-2: Built on the tower; its limits lifted in mission control's own posture  (S)

**Decision:** Mission control reuses `/tower`'s conversational contract,
router, flight machinery and permission posture by reference, and states
only its deltas: supervision of the sessions it launches, watchers and a
failsafe tick, a program spanning repositories, the duty seam, and the
relayed kickoff (REQ-I1.5: the tower offers and never starts; mission
control launches and relays on the operator's ask). The
tower's own text keeps its "no watch loop, no supervision, one repo" rules
for the plain tower; `/tower` remains the single-repo, no-duties front door.
Mission control never edits a settings file or widens its posture
(tower-front-door D-14 carries).
*(Amended at kickoff 2026-10-22: the relayed kickoff added to the lifted
limits.)*

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
`id`, `text`, `subject` (one per entry, free text, the key the conflict
report groups on), `source` (who said it, when, where), `date`, `scope`
(program, duty, repository) and `supersedes`. A helper adds, supersedes,
lists and renders the active set; the active set excludes superseded
entries. A standing decision the operator states in a turn is added at
once, echoed in one line and paired with an undo entry; the proposal path
(D-14) is for inferred repeats. The
active set is loaded whole at bring-up and re-injected after compaction by
the panel mod's post-compaction hook, with the skill's own bring-up step as
the fallback where the mod does not load. The launcher renders the rules in
scope into every launched session's brief through the launch-brief seam.
Answering permission prompts is not this store's job: a prompt is answered
from the tower-comms standing-decision record, which carries command
coverage (REQ-G1.2); an entry here that would answer one is proposed into
that record (D-14).

**Alternatives considered:**
- Rules as memory files. Rejected because: memory is per session, cannot be
  delivered to launched sessions, and has no supersession, which is exactly
  how the record's rule conflicts arose.
- Rules in a repository instruction file. Rejected because: they would be
  committed, visible to every reader and carry company data.

**Chosen because:** supersession and delivery are the two properties the
twelve-day record lacked; both need a structured store with one writer.

*(Amended at kickoff 2026-10-23: `subject` added to the entry; the direct
entry of an operator-stated decision made explicit.)*

*(Amended at sign-off lens pass 2026-10-24: prompt answering assigned to the
tower-comms record, whose coverage field this store lacks.)*

### D-6: The panel is a mod shipped in the planwright plugin, with a text fallback  (S)

**Decision:** The planwright plugin ships a mod. It draws a pane and a band
above the prompt from the attention store, the registry, the source
snapshots (the forge among them, each with its mode and age), the budget
file and the ledgers, read on a timer; it reads
context percent and rate-limit headroom from the session usage call; it
is the primary wake: it watches the attention store and submits the wake
prompt as soon as an event is pending and the session is idle; it runs the
failsafe tick from its timer and submits a prompt only when a tick is due
and the session is idle; it feeds presence to the queue from prompt
events; it re-injects rules on the post-compaction hook. Where the mod
does not load, the daemon runner relays the wake through the fleet's
session relay for the session's backend (stdin for stream-json, the pane
relay for tmux), and the tick stays the failsafe on both paths; whether
each relay submits or only stages the prompt is the research item of the
panel task, and a relay that only stages falls back to the tick. Animation
uses
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

*(Amended at kickoff 2026-10-23: the primary wake named (the mod watching
the attention store, the runner's relay where the mod does not load); the
tick was the only path the design described.)*

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
repositories, the spec root, the program home, the enabled duties, the
budget and the state-source map (REQ-H1.4: per fact class, the
authoritative source and its mode, `record`, `snapshot` or `cited`; specs
and forge by default). One mission control runs per program, under the
program's name.
The program home is class-3 work product (storage-classes): it defaults to
`mission-control/<program>/` under the operator's planwright configuration
root, a human-owned location, is named in the program block and
overridable, and holds the rule store, the knowledge base, the ledgers and
the handover file, never inside a work repository, never committed. The
nearest existing home, the plugin data home, is runtime state and does not
fit: a work product parked there is invisible to review and dies with the
plugin's data. Runtime state (the source snapshots, the budget file, duty
working files) stays under the plugin data home. The home holds no secret
or credential: the forge adapter uses the forge CLI's own authentication,
and the first run's forge-access objective checks that access and stores
nothing. It also receives the reclaim backups REQ-D1.6 names: a
`reclaimed/<repository>/<branch>/` folder per reclaimed worktree, holding
the ignored audit files the reclaim knob lists, verified by size and hash
before the worktree goes.
Every store the home holds (the rule store, the knowledge base and its
ledgers, the handover file) and the budget file carry a `format` field; this
bundle's shapes are additive-only, a reader refuses a store whose format it
does not know and names it, and a shape change is a follow-on's migration
task, never an in-place edit. The launcher rollout is the same: a session
started under the previous launcher finishes under it, and only new
launches take the new one.

**Alternatives considered:**
- A home inside the repository under an ignored path. Rejected because: a
  program spans repositories, and ignored files are deleted with worktrees
  (the record lost audit files that way).
- A global home for every program. Rejected because: two programs' rules
  and queues would mix.

**Chosen because:** storage-classes puts work product where the human owns
it and runtime state in the data home; the record's hub lived in a
human-owned folder and survived every session.

*(Amended at kickoff 2026-10-23: the reclaim backup folder added; a
repository-local backup folder was declined because reclaiming a checkout
would take its backups with it. The state-source map added to the block.)*

*(Amended at kickoff 2026-10-24: the format field, the additive-only rule
and the launcher rollout added, closing the deploy-and-migration and
versioning-scheme gap the kickoff's decision-domain check found.)*

*(Amended at sign-off lens pass 2026-10-24: the home moved to a human-owned
location, since storage-classes keeps work product out of the plugin data
home, with the minting rationale recorded; the no-credential rule D-28
already claimed written here.)*

*(Amended at the 2026-11-04 extension: the state-source map is now
REQ-H1.5's, which adds the `platform` class, D-39.)*

### D-9: Knowledge-base layout and the three loading rules  (S)

**Decision:** The knowledge base is a directory in the program home with an
`index.md` of one line per entry, loaded whole at bring-up; bodies read on
demand; any read above the per-entry cap offloaded to a read-only session
that returns an answer, never the file; a per-duty subdirectory per enabled
duty; a `decisions.log`, an `undo.log` and the shadow would-have log, each
append-only, written as monthly segment files (appends go to the current
segment, a subject query reads across segments, no segment is rewritten)
and queried by subject; a follow-up ledger; a living-versus-consumed source table with
watermarks; a mechanism inventory (the living source D-14 maps repeats
onto: what the host and planwright can make deterministic, by kind, with
where each is configured and the source it was read from, refreshed
against the installed versions). One writer per file, held by a lock
file that records its holder's pid; a lock whose holder is dead is
released by the next writer and the release logged. Specs, tickets and
sources are cited, never copied.

**Alternatives considered:**
- Load the knowledge base whole. Rejected because: it fills the window
  with reference material and the session loses the picture it exists to
  hold.
- A database. Rejected because: plain files stay auditable, diffable and
  recoverable by hand, and the stores this reads already are files.

**Chosen because:** tower frugality bounds inline ingestion, and the record
shows only rules and decisions stayed true while state rotted.

*(Amended at kickoff 2026-10-23: the mechanism inventory added as a
living source.)*

*(Amended at sign-off lens pass 2026-10-24: monthly log segments, since a
long-lived session's append-only logs had no bound; the dead-holder lock
rule, since a judgment session can die mid-write.)*

### D-10: One launcher for every session kind  (N)

**Decision:** A launcher script composes the existing dispatch primitives
(the flight dispatcher, the tmux and stream-json fleet dispatchers, the
offload seam) to start a session of any kind (tower, orchestrator, worker,
reviewer, ad-hoc), delivering the brief, the in-scope rules, the permission
profile (for mission control itself the `mission-control` guard tier: the
tower tier's denials plus a ready flip inside the configured ready-flip
policy, REQ-I1.2), the model tier from the allocation seam and a
deterministic name, and registering the session with its owner, kind and
scope. It has a
`retire` verb that exits the session, closes its pane and clears its
registry and attention rows, reporting any part it could not release.

**Alternatives considered:**
- One launcher per kind. Rejected because: the delivery contract (brief,
  rules, profile, tier, name, registry row) is the same for every kind and
  diverges silently when copied.

**Chosen because:** the record's worst stalls were launches that delivered
nothing (no profile, no prompt, no model), and one path is testable.

*(Amended at sign-off lens pass 2026-10-24: the `mission-control` guard tier
named, since the policy guard knew only worker and tower and the tower tier
denies every flip.)*

*(Amended at the 2026-11-04 extension: the kinds also include
`mission-control` and `kickoff` (D-36); repository-changing kinds start in
their own worktree (D-34); an `adopt` verb registers sessions the launcher
did not start (D-35).)*

### D-11: Liveness and stall states for every session kind  (N)

**Decision:** Liveness is the registry pid and process state. The stall
detector enumerates positive states for every session kind: dead, open
selector, unsubmitted prompt, turn ended with background work, idle with a
question in its pane, busy with no change past the stall window, unknown
(a changing pane with no registry pid). Each state is an event. Extending the detector's resource classes from workers to
every kind rides a routed fleet-lifecycle-closure amendment.

**Alternatives considered:**
- Elapsed time and pane stability as the signal. Rejected because: a frozen
  pane is stable precisely because it is stuck, and a dead reviewer read as
  idle.

**Chosen because:** the lifecycle-closure floor requires positively named
states, and the record's stall detector missed exactly the unnamed ones.

*(Amended at sign-off lens pass 2026-10-24: `unknown` added, a state the
test-spec already expected.)*

*(Amended at the 2026-11-04 extension: a session's pid may come from the
backend's own record as well as the registry, and a stream-json session's
event stream informs its stall state, D-35.)*

### D-12: One age-stamped snapshot per source per program  (N)

**Decision:** The snapshot seam is source-agnostic: for each
snapshot-mode source in the program's map an adapter script refreshes one
age-stamped snapshot per program per cadence into the program home, and
every duty reads snapshots, none polls a source itself. The forge adapter
ships here (PR heads, draft state, mergeability, review decision, open
threads, checks, reviews and comments for the program's tracked PRs, with a
patch id per PR so an unchanged patch is recognized). Adapters for
trackers, document stores and design tools are a follow-on bundle (D-27);
until one exists such a source is `cited`, and mission control holds only
its links and what the operator said about it. The cadence and the tracked
set are knobs per source; a refresher backs off on rate-limit headroom.

**Alternatives considered:**
- Each watcher polls what it needs. Rejected because: the record ran three
  pollers over the same PRs and the dashboard re-ran the full merge each
  tick.

**Chosen because:** the staleness tolerance is a program knob, which makes
the cache decision a configured one rather than a product guess.

*(Amended at kickoff 2026-10-23: generalized from the forge to any
snapshot-mode source, the forge the shipped adapter, so a program whose
public state lives in a tracker or document store gains an adapter through
the seam, without changing it; adapter feasibility is the follow-on's question, and `cited`
is the honest mode meanwhile.)*

### D-13: Autonomy at the mission-control tier, with calibration  (N)

**Decision:** Decisions map onto the autonomous-safe-decision buckets at
this tier: a decision reaches the operator only at a human gate, a fork the
record and sources cannot settle, or a hard-disqualifier zone; every other
decision is taken, logged with grounds as decided-by-mission-control, and
shown for review. A given go is not re-asked unless a check changes the
answer; a likely answer is searched for first and asked as a confirmation
with its source. A decision class is the autonomous-safe-decision bucket a
decision maps onto; a revoked self-decision lowers its class to ask-first
until a configured run of confirmations restores it; the hit rate is on the
panel. Interruptions per hour and the settled share are measured.

**Alternatives considered:**
- A static autonomy policy. Rejected because: the record shows both
  over-asking (re-asking given goes) and over-acting (flipping without a
  walk); only measured calibration moves both.

**Chosen because:** the operator's load scales with decisions only they
can make, and the whole-picture position settles more of the rest.

*(Amended at sign-off lens pass 2026-10-24: decision class defined as the
autonomous-safe-decision bucket, since REQ-F1.9 and the calibration ledger
used the term undefined.)*

### D-14: Mechanization proposals  (S)

**Decision:** A detector over the decisions log and the operator's asks
counts repeats per shape (the same ask kind, a manual step after the same
event, the same answer to the same question) against a threshold and a
window. For a repeat at the threshold, mission control looks up the
smallest mechanism in the knowledge base's mechanism inventory (D-9) that
covers it and proposes it as a confirmation in the operator's words: what
it noticed, the mechanism and its change, the cadence, where the operator
still intervenes, the cost, how to turn it off, an explicit decline. The
inventory's kinds are an open list (a rule entry, a knob, a catalog step
such as a convergence or review step, a hook or permission rule, a
scheduled routine, a shipped or custom duty); the inventory is refreshed
from the installed host and planwright versions so a mechanism that
appears later becomes proposable without a bundle change. An accepted
proposal applies the change where mission control may write (the rule
store, the program block, duty enablement) and hands a settings change
over ready to apply (REQ-G1.4); a declined one is recorded and not
re-proposed unless the pattern changes; "not now" parks it with a
trigger. Nothing enables or applies itself. The duty catalog is shown in
the guided first run and on request.

**Alternatives considered:**
- Enable the obvious duties by default and let the operator turn them off.
  Rejected because: a duty acts on the operator's behalf; consent must be
  explicit.
- Leave discovery to documentation. Rejected because: the autopilot reflex
  names "we keep doing X manually" as the trigger the machine should catch.

**Chosen because:** it is the runtime form of the reflex, and the hub's
memory rules were all born as repeated corrections.

*(Amended at kickoff 2026-10-23: widened from duty-or-rule to any
mechanism in the inventory; the operator's example was a review process
run by hand that convergence steps already make deterministic.)*
*(Amended at Amendment 4, 2026-11-07: a fourth repeat shape, the same
guard denial a knob governs, maps to a settings proposal through
`config/denial-knobs.tsv`; it shipped in PR #835 without an amendment.)*

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
no act for a configured period, two active entries sharing a `subject`
(the meaning call is the operator's). Findings become operator items or
rule proposals. The audit edits nothing.

**Alternatives considered:**
- Audit by an LLM pass over the transcript. Rejected because: the floor
  reserves mechanics for scripts, and the record's seven-pass audit was a
  one-off nobody could afford to repeat.

**Chosen because:** drift was invisible for days; a cheap scheduled compare
is what makes it visible.

*(Amended at kickoff 2026-10-23: two active entries sharing a `subject`
named as the mechanical finding, the meaning call the operator's.)*

### D-17: Budgets and the degradation ladder  (N)

**Decision:** A per-program budget file bounds live sessions, source polls
per hour (every snapshot-mode source counted), spend class per duty, context steps and host load. Each duty and
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

*(Amended at the 2026-11-04 extension: launch admission across programs
is host-shared and dynamic (D-41); this file's session and host-load
bounds are per-program ceilings beneath it.)*

### D-18: The guided first run and the guidance knob  (S)

**Decision:** With no program configured, mission control runs a guided
first run: one objective at a time (repositories, spec root, forge access,
where the program's state lives per fact class and in which mode, duties
to enable, voice and quiet hours), visible progress on the panel,
immediate feedback, hints only when stuck, scaffolds that fade per concept.
It ends by writing the program block, the knowledge-base skeleton and the
enabled duties. A guidance knob (guided, standard, expert; guided on a
fresh installation, remembered in the adopter configuration layer)
sets the depth everywhere.
The didactics shape the turn and the panel and never soften a normative
token, pre-select an option or pad a turn past the density rules.

**Alternatives considered:**
- A setup document. Rejected because: the operator will not read it, and
  interaction-style already prefers teaching inside the dialogue.

**Chosen because:** mission control is meant for operators who do not know
planwright; a guided first run is how they get a working configuration.

*(Amended at kickoff 2026-10-23: the state-source objective added to the
first run's list, so a program's source map is written before any duty
reads from it.)*
*(Amended at the 2026-11-02 delta kickoff: the guidance level is remembered
in the adopter layer, not the machine-local one. The machine-local file
sits inside a repository checkout, where mission control writes no file
(REQ-A1.3), and the adopter layer is the per-operator home REQ-F1.13's
test entry describes.)*
*(Amended at the 2026-11-04 extension: the level also shapes the teaching
at consequential moments, D-31.)*
*(Amended at Amendment 4, 2026-11-07: the first run asks only what the
operator can decide from their own work; an objective the repository, a
check or a shipped default settles is settled and said in one plain line
the operator can overrule, never asked. The objective list above is what
the run settles, not what it asks. It shipped in PR #822 without an
amendment.)*

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
closure. A task that would push the closure past its cap follows
instruction-hygiene's order: trim non-law prose first, then move bulk to
point-of-use (a script's usage header, the catalog, the doctrine doc), then
a deliberate raise with its recorded rationale, then escalation to the
operator; no step defers gating law.

**Alternatives considered:**
- Raise the cap first, before the diet and the move. Rejected because: the
  cap exists to keep every skill loadable; the closure is already at it.

**Chosen because:** budget trims by deduplication are exhausted; only
structure keeps a skill of this size inside it.

*(Amended at sign-off lens pass 2026-10-24: instruction-hygiene's fixed order of
fixes cited instead of a local rule that skipped the recorded raise.)*

### D-22: Cross-bundle edges  (N)

**Decision:** This bundle depends on routed amendments it names and does
not re-decide: tower-comms (presence input, picklist windows, the two item
kinds), fleet-lifecycle-closure (resource classes for every session kind),
custom-spec-location (the holder-to-work-repository reverse registry),
invariant-tasks and spec-format (a per-task repository field and per-repo
dependency state), fleet-hardening (a tower permission floor independent of
the launch), merge-currency-guard (the deterministic pr-ready attention
record), worker-permission-ergonomics (profile delivery at dispatch). It
seeds five follow-on bundles through pending notes: review desk, spec
currency, environment broker, night shift, state-source adapters.

**Alternatives considered:**
- Decide those pieces here. Rejected because: each has an owner whose scope
  text claims it; a second decision would conflict with the first.

**Chosen because:** the fold-detection pass named the owners, and the
operator chose routed amendments over a self-contained bundle.

*(Amended at kickoff 2026-10-23: the state-source adapters named as the
fifth follow-on.)*

*(Amended at the 2026-11-04 extension: further routed edges are the
human-gates amendment for the kickoff push (Task 31), the tower-comms
amendment for the reply hook (Task 32), the platform-currency bundle
consuming D-39, and the widened meaning of `fleet_max_parallel_units`
(D-41).)*

*(Amended at Amendment 4, 2026-11-07: the router and flight rules of D-45
are routed to tower-front-door as Task 36.)*

### D-23: Non-authoring and relay  (C, fleet-coordination-floor; fleet-autonomy D-17)

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
*(Amended at Amendment 6, 2026-11-09: a notifier delivery or a forward while `take` runs is a relay by script, never a yes mission control types, D-47 and D-49.)*

### D-24: The undo ledger  (S)

**Decision:** Every automated act appends an entry naming the act, its
`subject` (the shared key, D-5), its target, its grounds and a one-step
reversal command where one exists
(resolve a thread, re-approve, retire a session, park a unit). The panel's
recent-decisions view reads it, and a revoke runs the reversal.

**Alternatives considered:**
- Rely on the decisions log alone. Rejected because: reviewing an act is
  cheap only when reversing it is cheaper.

**Chosen because:** act-then-review needs a cheap undo to stay honest.

*(Amended at sign-off lens pass 2026-10-24: `subject` added, since D-9 queries
the undo log by it.)*

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

*(Amended at the 2026-11-04 extension: the readiness check also audits
the configured cadence, D-33, and the packet is prepared at the ready-flip
and merge-recommendation moments D-31 names as well as before a human
gate.)*
*(Amended at Amendment 6, 2026-11-09: the readiness check also refuses an operator-visible change with no recorded real-render approval, D-50.)*
*(Amended at Amendment 7, 2026-11-10: a reviewer that reviews only once the pull request is ready is asked to review the draft first and waited for after the flip only as the fallback, D-55.)*

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
deadline-watch (dates held in `record` and `snapshot` stores and dates the
operator states drive priority and the first turn after silence; calendar
reads arrive with the state-source adapters), prepared-moments (D-25), undo-ledger (D-24), self-audit
(D-16) and proposals (D-14). Review desk, spec currency, environment
broker, night shift and the state-source adapters (D-12: Jira, Notion and
Figma named as candidates) are follow-on bundles, each seeded by a pending
note.

**Alternatives considered:**
- Ship the review desk as the reference duty here. Rejected because: it is
  the most evidenced but also the most decision-heavy, and not every
  operator runs one.

**Chosen because:** the shipped set is what every mission control needs;
the follow-ons are what some do.

*(Amended at kickoff 2026-10-23: the state-source adapters added as the
fifth follow-on.)*

*(Amended at sign-off lens pass 2026-10-24: deadline-watch's day-one sources
stated, since no calendar adapter ships and `cited` forbids polling.)*

### D-28: Decision-domain walk  (N)

**Decision:** Domains touched and decided here: data storage and modelling
(D-5, D-9, D-24), caching (D-12), queues and async work (D-4, D-7), API
surface (the duty entry format, the launcher verbs, the knobs, the
state-source map and the snapshot adapter seam: D-3, D-8, D-10, D-12,
D-20), secrets and configuration (every knob documented, D-20; no secret or
credential in the program home, the forge CLI's own authentication reused,
D-8), concurrency (one writer per file with a dead-holder release, D-9),
observability (the panel and the measures, D-6, D-13), dependency adoption
(the mods API and its version floor, D-6), LLM output quality (proposal and
routing judgment eval-gated, test-spec), human comprehension (the panel and
items, researched against the mods docs and interaction-style, D-6, D-19),
existing-seam reuse (D-2, D-3, D-10), knowledge engineering (the
knowledge-base taxonomy, D-9), product strategy (front-door positioning,
operator-decided, D-1). Authentication and authorization adds no new
surface beyond the `mission-control` guard tier (D-10: the tower tier plus
policy-bounded flips, worker and tower profiles delivered unchanged);
organization design is unchanged (the human gates). Deploy and migration and versioning scheme:
the program-home stores carry a format field under an additive-only rule
and the launcher rolls out per new launch (D-8). Not touched: packaging and
pricing, IP posture.

**Alternatives considered:**
- Leave the walk to kickoff. Rejected because: the drafting phase is where
  the catalog is consulted so the spec decides rather than inherits.

**Chosen because:** the kickoff gap check then has nothing to flag.

*(Amended at kickoff 2026-10-23: the state-source map and adapter seam
added under API surface; the kickoff found the source-of-truth question
touched and undecided.)*

*(Amended at kickoff 2026-10-24: deploy and migration and versioning scheme
moved from "not touched" to decided, the §7 gap check having found the
persisted stores and the launcher rollout touched.)*

*(Amended at sign-off lens pass 2026-10-24: the secrets claim now backed by
D-8's text; the guard tier recorded under authentication.)*

*(Amended at the 2026-11-04 extension: data storage D-37 and D-41;
concurrency D-38 and D-41; API surface the `audit` and `adopt` verbs, the
kickoff kind and the activation record (D-33 to D-37); authentication and
authorization D-32, D-35 and D-36; deploy and migration D-33 (pull
requests no launch registered) and D-38 (partial handover); human
comprehension D-31; context handling D-42.)*
*(Amended at the 2026-11-07 amendment: context handling D-43; its API
surface is the launcher's `pane` rung and its pane adapters; auth (the
terminal's control channel, Remote Control carried only from the
predecessor, the successor's profile), concurrency (the predecessor takes
no act after writing the handover file; the deferral holds only while a
rung-1 successor is in flight), failure modes (an unverified successor's
pane closed by the predecessor) and observability (the rung and adapter
recorded) are decided in D-43.)*

### D-29: Handover over compaction  (S)

**Decision:** Mission control prefers a continue-as-new handover to a
compaction. The trigger is measured context percent from the session usage
call where the harness exposes it, the completed-wake proxy otherwise (one
duty trigger or operator turn, its ceiling a knob), and a compaction-count
ceiling in either case; the mod's compaction hook defers
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

*(Amended at the 2026-11-04 extension: superseded for attended sessions
by D-42; it governs launched holders.)*
*(Amended at the 2026-11-07 amendment: governs attended sessions again
through D-43's ladder.)*
*(Amended at Amendment 6, 2026-11-09: where the host exposes no percent,
the measured context comes from the session's own transcript, D-46; the
handover runs at a natural break, D-47.)*

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

*(Amended at the 2026-11-04 extension: succession applies to launched
holders; an attended session compacts instead, D-42.)*
*(Amended at the 2026-11-07 amendment: an attended session's successor
opens in a pane beside it, D-43.)*
*(Amended at Amendment 6, 2026-11-09: a launched holder with no operator at its terminal runs this itself at a natural break, keeping its session name where the backend can carry it, D-47.)*

### D-31: Guidance shapes the teaching at consequential moments, never the gate  (S)

**Decision:** The guidance level (D-18) reaches past the first run to the
moments that carry consequence: mission control presenting a merge
recommendation or a ready flip it requests or offers, and the operator
stating an intent to merge. At each, the readiness section of the prepared
packet (D-25) opens with one line built from the cadence audit (D-33):
which configured steps are covered at the pull request's head and which
are gaps, or that the audit could not run and why. The level picks only
what follows that line: `guided` adds a plain-words lesson on why a gap
matters and a recommendation to close it first, `standard` the
recommendation alone, `expert` nothing; an unaudited result carries no
lesson. The lesson texts are core data shipped beside the packet script,
keyed by a closed set of moments and by level, so the skill names the rule
once and stays inside the instruction budget (D-21); they are not an
overlay catalog, so D-1's single operator-facing extension point stands.
No level softens or skips a gate, pre-selects an option or withholds the
line.

**Alternatives considered:**
- Teach only in the first run. Rejected because: the operator's own example
  (a newcomer pushing a pull request nobody had reviewed) happens long after
  setup, at the merge.
- Write the lessons into the skill. Rejected because: the instruction budget
  is saturated.
- An overlay-extensible lesson catalog. Rejected because: it would be a
  second operator-facing extension point beside the duty catalog (D-1) with
  no evidence an adopter wants to change the wording.
- Block the merge or flip until the gaps close. Rejected because: the gates
  already decide that; guidance that adds a gate would make the level a
  policy knob in disguise.

**Chosen because:** the result is cheap to state at every level and the
lesson is where a newcomer needs it, while an expert loses one line at most.

### D-32: A posture check at bring-up, and one pre-approval list  (N)

**Decision:** A posture script reads each loaded settings layer by
projection, the way the tower's bring-up step does (tower-front-door D-14),
with the shipped `config/mission-control-settings.json` as the floor and an
unwired guard hook counted as a failure. The skill runs it at bring-up and
on the failsafe tick, and the launcher reads the same result before a
launch. A failure is said in one plain line and mission control continues
read-only (no launch, no answer, no request; its own runtime stores stay
writable) until a later check passes. The `mission-control` guard tier
already refuses edits, git mutations and flips outside the policy (D-10);
what changes is its pre-approval list, which today is a hand-kept string:
it becomes one core-only list of script verbs, derived from the scripts
the skill and the duty catalog invoke and shared by the tier and its
tests, that excludes `fleet-streamjson.sh answer`. An overlay never adds to
it; an overlay duty's scripts run under the daemon runner, not in mission
control's session.

**Alternatives considered:**
- Trust the launch to have delivered the profile. Rejected because: the
  documented start is the operator typing the skill command in whatever
  session they have open, which no launcher touched.
- Refuse to run at all without the posture. Rejected because: a read-only
  mission control still answers questions and shows status, which a new
  operator needs while fixing the setup.
- Keep the posture check as skill prose by reference. Rejected because: the
  launcher cannot read prose, and a script is testable.

**Chosen because:** the tower already proved the check, and a list derived
from what the skill invokes cannot fall behind it the way the hand-kept one
did.

*(Amended at Amendment 4, 2026-11-07: a mission-control session that
mission control launches, a successor included, runs in Claude Code's auto
mode; the deny floor and the guard hooks this check confirms stay the
floor, and a session the operator opens keeps their own settings. It
shipped in PR #859 without an amendment.)*

### D-33: The configured cadence is audited at readiness and carried in briefs  (N)

**Decision:** A read-only `audit --through <point> [--head <sha>]` verb on
the step runner resolves the configured cadence through the in-run points
from pre-implementation to the point named and compares it with the step
records. A point with a required step and no completion record is a gap; so
is a completion that does not count at the head (it counts on an ancestor
of the head, and for the last point with a required step only at the head
itself or with nothing but merge commits on the first-parent path after
it); so is a required step with no record, or whose records are all outside
passed, applied and skipped, in any run. The readiness check runs it
`--through post-pr` with the forge's pull-request head as `--head`, in the
worktree holding the branch, and records a `cadence` evidence row: audited
at a head, a gap, or unaudited with its reason. Any gap, an audit at
another head, a worktree head that differs from the forge's, or no audit
refuses the walk. A pull request no planwright launch registered reads
unaudited (not planwright-run): the packet says so, and only a flip
mission control would request is refused. The launcher adds a cadence
section to every repository-changing brief, naming the procedure that
resolves and records the steps and the audit command; a brief that is a
skill command is exempt, the skill carrying its own cadence. The
configured cadence is distinct from a cadence step, the steps-catalog entry
whose recorded run gates later units.

**Alternatives considered:**
- Require the steps in the gate-condition data. Rejected because: that data
  ships empty, so the check verified nothing by default, which is how a
  launch with no review reached a ready flip.
- A CI check on step records. Rejected because: step records are local to
  the worktree that ran them and never reach CI; readiness runs where they
  live.

**Chosen because:** it catches a skipped point or step whoever skipped it,
reuses the resolver the cadence already uses, and is what the fix in flight
already delivers, so there is one fix rather than two.

*(Amended at Amendment 4, 2026-11-07: a spec-only pull request (every
changed path a Markdown file under the spec root, the head holding that
root) is held for each touched bundle's kickoff sign-off instead of the
cadence and the gate data's steps, by the operator's ruling that spec-only
pull requests skip the code review steps; it shipped in PR #852, and
REQ-D1.14 supersedes REQ-D1.9 to say so.)*

### D-34: A repository-changing launch gets its own worktree  (N)

**Decision:** The worker, reviewer, ad-hoc and kickoff kinds start in a
worktree the launcher has the dispatch machinery create
(`scripts/fleet-dispatch-worktree.sh`, as a tower's flights do), under the
repository's worktree directory: on the unit's branch when it exists,
otherwise off the default branch. When another worktree already holds the
unit's branch, the launcher reuses it only if no live session runs there,
and refuses naming that session otherwise. An explicit directory is
accepted only when it is a worktree other than a primary checkout that no
live session uses. A launch whose worktree cannot be created is refused
with no session started and no fallback. The tower, orchestrator and
mission-control kinds start where they are launched. Creating the worktree
is part of launching, as it is for a tower's flights, not an authoring act
(REQ-A1.3).

**Alternatives considered:**
- Leave the directory to the caller. Rejected because: the caller is a model
  that defaulted to the primary checkout, and the operator then had to
  write the worktree command into every brief by hand.
- Let the launched session create its own worktree. Rejected because: the
  session would start in the primary checkout first, which is the hazard.

**Chosen because:** the primary checkout is shared by everything on the
host, and a worktree is the isolation every other planwright launch already
has.

### D-35: Adoption, liveness on every backend, and prompt answers  (N; C, tower-comms D-12)

**Decision:** The launcher gains an `adopt` verb
(`adopt --handle <backend:id> --kind <kind> --scope <scope> [--owner <o>]`)
that registers a session mission control did not launch, with an adopted
origin, after positive liveness evidence; it refuses a session with no
resolvable pid and one whose row names another live supervisor. The stall
detector reads every registered session rather than launcher rows alone,
taking each backend's pid from the registry or the backend's own record,
and a stream-json session's event stream for its stall state. Retiring an
adopted session whose owner is the operator is a confirmation item, never
a self-decision. A pending permission prompt raises an attention event
keyed by session and prompt id; re-detection is a no-op and the event
clears when the prompt is no longer pending, whatever answered it.
Answers go through the tower-comms answer channel (`fleet-attention.sh
claim`, which re-checks standing-decision coverage at its boundary,
tower-comms D-12), or carry the operator's own answer to that prompt; each
answer is an undo-ledger entry naming what authorized it (D-24). The guard
tier pre-approves that channel and not the raw answer verb. A tmux session
has no answer channel: its prompt is surfaced once with its command, and
only the operator's own answer reaches it, by the pane relay (D-23).

**Alternatives considered:**
- Supervise launched sessions only. Rejected because: a tower handover
  (D-38) and the operator's own hand-launched sessions would go unwatched,
  which is how prompts sat for days unseen.
- Allow the raw answer verb. Rejected because: it settles a prompt with no
  check that a standing decision covers it (REQ-G1.2).
- Relaunch a tmux session on stream-json to get an answer channel. Rejected
  because: it discards the session's context, and flights refuse that
  backend.

**Chosen because:** supervision has to follow the sessions, not the launch
path, and the coverage check already sits in front of the channel that
answers.

*(Amended 2026-11-08, operator ruling relayed through the hub: "can't it be
fixed from the root so we don't really need to do it?". Today approvals run
`fleet-streamjson.sh pending|answer` only through user-scope allow rules that
name one plugin version's install path, so each release breaks them and the
auto-mode classifier denies the call. The fix is at the root: a plugin
PreToolUse hook approves exactly the literal resolved installed-root path
`<root>/scripts/fleet-streamjson.sh` with `pending` or `answer`, as one simple
command (no expansion, compound, pipe, redirection, background marker, or
path through a symlink to elsewhere), in a mission-control session only.
The "allow the raw answer verb" alternative above is rejected for the guard
tier's list and stays rejected there; this hook is a separate, narrower
approval whose coverage is its exact shape, not a verb-wide allow. The
fleet-hardening D-20 exact-path rule for settings allow rules is kept as is.
Settled at the kickoff (operator: "Your rule or reply (Recommended)"): the
hook judges only the call's shape; what authorizes an answer is unchanged, a
standing decision claimed through the answer channel or the operator's own
answer, recorded in the undo ledger, never mission control's own judgment.
The session test reuses the plugin's prompt-hook marking (as
`tower-session.sh` marks towers), with a mission-control mark in the same
store and bar; because this mark now lets a call through rather than only
denying, the hook also requires the call to name the installed root it runs
from. Task 38 builds it.)*
*(Amended at Amendment 6, 2026-11-09: the prompt's wake is the notifier's delivery, D-49; a direct unit's prompts go to its launching mission control, D-48; who may answer is unchanged.)*
*(Amended at Amendment 7, 2026-11-10: adoption's registry row can be moved to another program, D-54; the move changes only where the events go.)*

### D-36: A kickoff permission profile for relayed kickoffs  (S)

**Decision:** The launcher gets a kickoff kind with its own settings
profile: the worker profile's rules without its spec-branch push denies,
since a deny cannot be narrowed by an allow. The policy guard is what
admits the one push: it reads the permitted branch from the launch record,
written before the session starts outside every path the worker profile
may write, and admits a plain push of that branch, the draft pull request
for it and the kickoff's configured ready flip; it denies a force push, a
deletion and any other branch. The push targets the spec root's repository
as its posture reports it, and under the `plain` posture the kind adds no
push. The core protected floor names `planwright/*/spec`, so this kind
waits on a routed human-gates amendment (Task 31) admitting the relayed
kickoff session as a writer of its own spec branch. Mission control's own
profile is unchanged.

**Alternatives considered:**
- Mission control pushes for the kickoff. Rejected because: mission control
  runs no git mutation (REQ-A1.3).
- The operator pushes by hand. Rejected because: it hands the operator a
  per-session step every time (REQ-A1.4).

**Chosen because:** the operator chose it (2026-11-04), and it widens one
session by one branch it was launched to publish.

### D-37: The panel activates from a bring-up record, not the environment  (S)

**Decision:** Mission control's entry and bring-up write an activation
record for the current session through a panel-script verb: program,
session id, written time and a `format` field, additive-only as D-8's
stores are. The record lives host-wide under the fleet home, one file per
session id, so the mod reads only the file its own session id names and
never scans programs. The session id comes from the session-start hook's
input. The mod checks for its record on its timer and on the session events
it already handles, activates when it finds one, and writes an
acknowledgment beside it. A launched session never matches another
session's record, so the activation is never inherited. The launcher's
mission-control kind (which already exists, obs:855b725a) and a handover
successor reach the record through their own bring-up, and the
`PLANWRIGHT_MC_PROGRAM` environment variable stays an optional fast path
(obs:cf5bce54); the skill's entry reads the same variable as the program
argument when none is typed, so such a session resumes without asking. Retirement and a predecessor's self-retirement remove the
record, and the keeper removes any record whose session has no live
process. No acknowledgment within a bounded wait, or a host below the mods
floor (D-6), means the skill says once that the panel cannot load and uses
the text form.

**Alternatives considered:**
- Have the launcher set the environment. Rejected because: the documented
  start is typing the skill command in a session no launcher started, and
  the operator wants no setup (2026-11-04).

**Chosen because:** it needs nothing from the operator and keeps the
non-inheritance property by construction.

### D-38: Tower handover  (N; C, tower-comms D-6)

**Decision:** Mission control takes over a running tower's fleet as a
handover variant. It adopts each live session the tower dispatched or its
fleet sweep tracks (D-35), writing itself as the supervisor in each row, and
from that moment the tower's sweep and answer paths skip a session another
supervisor holds. It imports the open entries of the tower's attention
store into its queue by origin id, settling the tower's copy with a
carried-over reason; an item answered on either side clears on both. It
runs the fleet sweep for the adopted flights under its own identity as the
sweep's tower identity, one checkout per repository, with the reap
observing-only as fleet-lifecycle-closure keeps it, and records each
relaunch against the dead session's row so a second relaunch is a no-op.
It asks before retiring the tower; on a no it releases the adopted sessions
back. A re-run adopts what is not yet adopted and imports by origin id
without duplicating; nothing is undone on a partial failure, and the tower
stays authoritative for what was not adopted. A wake mission control relays
carries a fixed leading marker, defined once in a constant both sides read,
and the tower's reply hook (owned by tower-comms, D-6 there) ignores a turn
bearing it, through a routed tower-comms amendment (Task 32).

**Alternatives considered:**
- Run beside the tower. Rejected because: two supervisors act on the same
  sessions and answer the same prompts.
- Retire the tower unasked. Rejected because: the operator may be talking
  to it.

**Chosen because:** operators start with a tower and grow into mission
control; the move should lose nothing.

### D-39: The `platform` fact class  (C, platform-currency D-14)

**Decision:** The state-source map's closed set of fact classes gains
`platform` (the releases of the host tools and platforms the program builds
on), admitting only `snapshot` and `cited`, `cited` by default. REQ-H1.5
supersedes REQ-H1.4 with the class added; the map's reader refuses `record`
for it, and the validator and the reader keep one class definition.

**Alternatives considered:**
- Reuse `decisions` or `designs`. Rejected because: a changelog is neither,
  and the mode and age labels would mislead.

**Chosen because:** it keeps the one-snapshot seam (D-12) for the
platform-currency duty at the cost of one class.

### D-40: What is shown as working, works  (S)

**Decision:** Four repairs the observations name, under one rule. A duty
the guide or first run presents is armed when enabled, or presented as not
yet available, checked mechanically against the catalog; an invalid
overlay entry leaves the next lower layer's valid entry in force. Every
watcher run and snapshot refresh has a timeout (a seconds knob, overridable
per watcher) and is stopped on expiry, re-armed on the next pass, the
expiry an event. The calibration ledger's writer (D-13) writes the measures
file in the shape the panel reads. The keeper's dispatch suggestions come
from the orchestrator's selection, its withheld repositories included.

**Alternatives considered:**
- Caveat the guide instead of arming the duties. Rejected because: the
  scripts behind them exist, and a newcomer reads the guide as a promise.

**Chosen because:** each is a place where a new operator sees something
that does not happen, which costs more trust than any missing feature.

### D-41: Launch admission is dynamic and shared across the host  (S)

**Decision:** Before a launch, admission reads the account's usage headroom
(the rate-limit figures the session usage call exposes, D-6, cached with
their age; a vendor quota hold is a hard stop) and the host's capacity
(load against core count, available memory), and admits only while each is
inside its `mission_control_admit_*` threshold knob;
`fleet_max_parallel_units`, whose meaning widens to a host-wide ceiling
shared by every program and the meta-orchestrator, caps the total. The
state is class-2 runtime state under the fleet home: in-flight reservations
(holder pid, program, time) under one lock, with D-8's `format` field.
Each admission recounts live sessions from every program's registry under
the lock, and counts each reservation and each session younger than a
warm-up knob at its configured share, so a lagging load reading never
admits a burst. A reservation is released when its session registers or
its launch fails; one whose holder pid is dead, or older than a timeout,
is reclaimed by the next admitter and logged. Sessions started outside the
launcher are seen through the registry and measured load. REQ-L1.2's
per-program bounds stay ceilings beneath this.

**Alternatives considered:**
- A fixed worker count per program. Rejected because: the operator's ruling
  (2026-11-04) is that the limit follows account and computer limits, and a
  per-program count double-books a shared host.

**Chosen because:** both real limits are measurable, and only a host-level
store sees every program at once.

### D-42: An attended session compacts; a launched holder hands over  (S)

**Decision:** D-29 and D-30 prefer a handover to a compaction. That holds
for a mission-control session mission control launched itself (a registry
holder), where no terminal has to move. In an attended session (the
operator typed the skill command in their own terminal), a full context is
left to the host's compaction, made safe by the post-compaction step D-29
already defines: the rules re-injected and the self-check run against the
durable stores, only a failed check raised as an operator item. Mission
control raises no handover act, panel handover-due event or operator item
for context in an attended session, and the operator never has to do
anything about context. Running mission control as a launched session the
operator attaches to stays available, never required. The trade-off is
named: a compacted session can lose conversational nuance that a successor
reading the handover file would keep; the self-check catches lost rules
and state, not lost tone. The operator accepted that for out-of-the-box
behaviour.

**Alternatives considered:**
- Hand over in attended sessions too. Rejected because: the successor runs
  in a new session, so the operator would have to move to it, which is the
  manual act this extension removes.

**Chosen because:** the operator's decision (2026-11-04): zero context
handling for the person at the terminal, with the durable stores and the
self-check carrying what must survive.

**Superseded-by: D-43** (2026-11-07).

### D-43: Every session hands over; an attended one opens its successor beside itself, compaction last  (S)

**Decision:** D-29 and D-30's preference for a handover over a compaction
holds for every mission-control session, attended or launched. At its
trigger an attended session works down the **handover ladder**, falling to
the next rung whenever one does not end with its successor holding the
program name:

1. **A pane beside itself.** It writes the handover file, takes no new act
   after that, and opens its successor in a new split of its own window
   in the innermost terminal or multiplexer on this host, through a
   **pane adapter**: a launcher rung (`--backend pane`, beside the
   launcher's `stream-json` and `tmux` rungs, D-30's launch path) so the
   successor gets its registry row as any launched session does. tmux's
   adapter is the reference; kitty, WezTerm and Zellij get best-effort
   adapters, each verified against a stub, and others may be added later.
   An adapter is used only when its probe passes: the probe is read-only
   (it opens nothing and changes no terminal state), finds the pane
   identity of the session's own process (for example `TMUX_PANE` or
   `KITTY_WINDOW_ID`), and accepts only a control channel already enabled
   on this host and owned by the session's user, never enabling one or
   editing terminal configuration. The adapter passes the successor's
   command as an argument vector built only from launcher-grammar names
   and checked paths, never as a shell string. The successor starts with
   its launcher-derived display name (the program name moves by `take`),
   keeps Remote Control only when its predecessor had it on, and runs
   under the shipped mission-control profile, as launched mission-control
   sessions do. Its pane takes focus; it verifies and takes the program
   name as D-30 describes, recorded as an attended holder, which
   retirement still retires through its registry row. The released
   predecessor says one line naming the new pane and ends itself at an
   idle prompt, so its pane closes and the operator does nothing; one that
   has not ended when `take` finishes is closed by the successor through
   the same adapter, that pane only. A successor that does not verify
   within `mission_control_handover_window` is closed by the predecessor
   through the adapter that opened it, the predecessor keeps the name, and
   the ladder falls to rung 2.
2. **One operator act.** The handover is the one command
   `scripts/mc-handover.sh`'s `path` names, raised through `offer` once per
   session and said in one plain line. Its exit 4 now applies only here.
3. **Compaction, last.** While a rung-1 successor is in flight the mod's
   compaction deferral (D-29) holds, with its cap; while only the rung-2
   act is pending it does not, so the host's compaction is the last
   resort. After it the post-compaction step D-29 defines (rules
   re-injected, the self-check against the durable stores, only a failed
   check an operator item) keeps the session sound: a self-checked
   compaction is not the degraded session D-30 forbids. Each later trigger
   retries rung 1 only.

Each handover records the rung and adapter that ran, and a fall from rung 1
is a panel event. The shipped measured-context trigger
(`mission_control_handover_context`) is 40 percent for every session,
launched holders included; the wake and compaction ceilings keep their
shipped values and now apply to attended sessions too. A launched holder's
handover mechanism is otherwise unchanged. A resume still never closes the
operator's own session; only a release to a pane successor does.

**Alternatives considered:**
- Keep D-42 (attended sessions compact). Rejected because: the operator
  wants the handover's lossless successor wherever it can run, compaction
  losing conversational nuance the handover file keeps.
- tmux only. Rejected because: the operator asked for a best effort in
  whatever terminal the session runs in.
- Never compact, reminding until the operator acts. Rejected because:
  compaction is the host's own safety net, and a degraded session is worse
  than a compacted one.
- A pane seam inside `scripts/mc-handover.sh`. Rejected because: the
  launcher's backend seam already owns registry rows and retirement, which
  a pane successor needs.
- Remote Control on for every successor. Rejected because: the operator
  ruled (2026-11-07) that only the hub keeps Remote Control and a
  successor keeps it only when its predecessor had it.

**Chosen because:** the operator's decision (2026-11-06 and 2026-11-07):
hand over as best as possible and compact only as a last resort, emulating
the tmux pane in whatever terminal is in use.
*(Amended at Amendment 6, 2026-11-09: the ladder starts at the next natural break, and a forward by script while `take` runs is not a new act, D-47.)*

### D-44: A goal is done when its own check passes  (S)

**Decision:** A program goal is a record in the program home holding the
outcome in plain words, the work it tracks (pull requests, flights or spec
tasks, attached when the goal is set or when a launch names it), an
optional check command, the check's state (unconfirmed, confirmed,
passing, failing, unrun) and the evidence of its last run; the store
carries a `format` field and is written only by mission control, under one
lock. When the operator sets a goal, mission control drafts the check (a
statement, plus a command where one can prove it) and the operator confirms
or corrects it in one line. When the goal's work merges, mission control
runs the check: the command from the program home, as a run of the
`goal-check` duty and so under D-40's watcher timeout, or, where no
command fits, a read-only session that looks and reports what it found,
which mission control writes into the goal's evidence. It reports the goal done only on a pass; on a fail or an unrun
check it reports the goal as merged but not done, naming what failed, and
routes the fix. A done goal with a command check is re-checked daily and at bring-up,
silently while it passes; a failure reopens it with one line and routes the
fix. Session-based checks are not re-run unasked. A command is operator-confirmed
data, so it is run as written, never assembled from forge, session or
record text.

**Alternatives considered:**
- The operator writes every check. Rejected because: a step on every goal,
  for checks mission control can draft for a one-line confirmation.
- Commands only, with no session-based check. Rejected because: some
  outcomes (a host's installed version, a runner's registration) are
  easiest to verify by looking, and a goal would otherwise never be called
  done.
- Merged pull requests as the done signal. Rejected because: that is the
  failure being fixed; the Mac offload goal was called done while the host
  still ran an old planwright with no runner registered.

**Chosen because:** the operator's decision (2026-11-07): mission control
drafts, the operator confirms, and nothing is called done without
evidence.

### D-45: A pull request that changes specified behaviour carries its signed spec edit  (S; C, tower-front-door)

**Decision:** A change to behaviour a spec describes edits that spec in the
same pull request, with a dated amendment note, and is not ready until the
operator signs the edit off in a short relayed kickoff. That kickoff runs
on the pull request's own branch, in its worktree, and its sign-off commit
is pushed like any other commit on that branch, so no spec-branch push is
involved. Two signals find such a change. The worker's covering-spec
statement in its pull request body: a `Covering spec:` line naming each
bundle the change touches, or `none`, and one `Not covered: <path> —
<reason>` line per changed deliverable file whose spec the change leaves
alone. And a mechanical spec-drift check (`scripts/spec-drift-check.sh`),
which reads each task's deliverables through `scripts/spec-model.sh`,
takes the backticked repository paths in them as the listed files, and
lists every changed listed file whose spec's anchored content is unchanged
and which no `Not covered:` line names, except a deliverable of a task the
pull request's own trailer names. A pull request with no statement reads
as covering nothing with no reasons. This bundle owns the statement's form
and the check; tower-front-door has its flights write the statement and
run the check at `pre-pr` (Task 36). The readiness check (D-25, D-33) runs the drift check and
compares each edited spec's latest sign-off anchor with its content at the
head; either gap refuses the flip. The router and flight rules are routed
to tower-front-door (Task 36), decided by the operator at this kickoff: a
shipped path list (CI workflows, git hooks, guard and policy scripts, the
security doctrine; each project may add paths) plus judgment for an ask
whose purpose is security routes that work to the spec pipeline; the
operator's one-sentence override keeps it a visual flight and is recorded
word for word with its date in the pull request and the flight record; the
polish pause zones stay as they are. An operator asking for the change, or
a launch brief mission control writes, is not an override: only the
operator's own override sentence keeps zone work a visual flight (the
audit found every zone flight resting on one of those instead).

**Alternatives considered:**
- A pending-amendment note in the pull request, the kickoff later.
  Rejected because: the spec stays wrong until a later kickoff that kept
  not happening, which is how the drift arose.
- Worker judgment alone, or the path match alone. Rejected because: the
  first drifts silently when the worker forgets; the second misses
  behaviour in unlisted files and flags harmless edits.
- Guard and hook scripts joining the polish pause zones. Rejected because:
  the kickoff sign-off already covers the change, so the operator would be
  asked twice.

**Chosen because:** the operator's decisions (2026-11-07): edit the spec in
the same pull request, worker statement plus mechanical check, path list
plus judgment for routing, pause zones unchanged.

### D-46: Every mission-control session reads its own context from its transcript  (N)

**Decision:** A new read-only script, `scripts/mc-context.sh`, reads a
session's context use from the tail of its own transcript, found through
the session's registry row and never from a path given as an argument: the
last assistant message's final usage (input, cache-read and cache-creation
tokens summed, the last frame of a message streamed in several) against
its model's context window. The window comes from the transcript where it
records one (a stream-json result's `modelUsage` context window), else
from the session's `context/<name>` window file the throughput duty
already reads, else from `mission_control_context_window`; the usage
parser is the one `scripts/mc-throughput.sh` already uses, lifted into a
shared helper, so there is one parser. It works the same for an attended
terminal session, tmux and stream-json, because every backend writes the
transcript. Where the host already gives the session a percent (the mod's
reading), that value is used and the panel says which source it shows.
The runner takes one reading per mission-control session per wake and
records it in the program's records; `scripts/mc-handover.sh due`, the
panel and the text panel read that record, and nothing else parses the
transcript for it. A missing transcript, an unknown window or a malformed
record reads the literal `unknown`, which leaves the wake-count fallback
(REQ-L1.5) in force. The transcript is read as data: fixed-field parsing,
nothing from it executed or interpolated.

**Alternatives considered:**
- A hook-injected context line each turn. Rejected because: stream-json
  sessions load no mod, the line costs every turn, and the runner, which
  decides when a launched holder is due, needs the reading outside the
  session anyway.
- Leave stream-json sessions on the wake-count proxy. Rejected because: it
  is the gap the report measured, a context that grew without bound.

**Chosen because:** the reported workaround measured the right number on
every backend, and a script keeps it mechanical (D-4).

### D-47: The handover waits for a natural break and keeps the session name  (N)

**Decision:** A due trigger arms the handover; it runs at the next natural
break: the act in hand has ended and no new one has started, and no launch,
relay or prompt answer of the session's own is half done. The session
writes an in-flight record in the program's records when it starts one of
those and clears it at the end; `due` reports `wait` while one is open.
While the handover is armed and waiting, D-43's compaction deferral and its
cap hold, and the wake and compaction ceilings still force it. A launched
holder with no operator at its terminal runs D-30's handover itself at the
break (write, launch, verify, take), prompted by exactly one handover-due
wake from the runner, which never batches it (D-49). The handover file
lists the holder's open direct-dispatch units (D-48), whose registry owner
moves to the successor at `take`.

Where the backend can carry it, the successor answers to the predecessor's
session name, the name other sessions address: the launcher gives the
successor that name, and `take` moves the name under the registry lock in
one step. Until `take` finishes, a script forwards what the predecessor
receives to the successor verbatim, and the predecessor acts on none of it;
a forward is a relay by script, not a new act, and never reinterprets an
operator's answer. A failed `take` leaves the name and the program with the
predecessor, which keeps acting, and retires the successor. A successor
arms no handover before its own first reading is below the trigger, so
handovers cannot loop. How the name moves on each backend is researched in
the task and recorded per backend; a backend that cannot carry it falls to
D-43's rung 2. The attended tmux path PR #902 shipped, Task 33's pane rung,
and the rest of D-43's ladder are unchanged; Task 40 builds on Task 33's
`launch --handover` and `take`.

**Alternatives considered:**
- Hand over at once when due. Rejected because: a half-done relay or
  answer is lost or doubled across the handover.
- A fresh name, with every sender resolving the current holder. Rejected
  because: every sender would need the lookup, and the report shows
  messages already going to a released session.

**Chosen because:** the operator's scope for this amendment (Sources): hand
over at a natural break, keeping the session name.

### D-48: Direct dispatch for units that need no holder's judgment  (N)

**Decision:** `mission_control_direct_dispatch_kinds` lists the unit kinds,
by the launcher's registered kind and never by prose, that need no
judgment from the program's holder; it ships with a review skill run on a
pull request and read-only checks (a spec-walkthrough render, a
goal-evidence session, a read-only audit). A kickoff, an implementation
unit and any kind that changes a repository are never listed. The mission
control that has such a unit (the launching mission control) launches it
through the launcher under the unit's program, with the program's rules and
the profile its kind already has, as the unit's registry owner, and names a
result path the launcher composes under the program home's results folder.
The unit writes its result there, one JSON object with a `format` field
written by rename into place, its one write in the program home, and ends.
The launching mission control reads it; the program's holder sees it in the
program's records at its own next wake, and is not woken for it. A unit
that ends without a result is a unit-lost event to the launching mission
control. A result file is removed once the unit is retired and its result
recorded in the program's records, or at program retire. A cadence step the
unit runs is recorded through the step runner as for any unit; the result
file is never readiness evidence (D-25). The unit's questions and prompts go
to the launching mission control, which answers only what REQ-G1.2 and
REQ-G1.6 already allow (a standing decision of the unit's program, or the
operator's own answer); anything else goes to the operator, never to the
holder. A kind the list does not name keeps the holder's relay.

**Alternatives considered:**
- Every unit dispatched directly. Rejected because: implementation units
  need the holder's knowledge of the spec and of the program's state.
- A cheaper model for the holder instead. Rejected because: it keeps the
  relay hop and its full-context turn; cost tiering is separate work.

**Chosen because:** each relay hop costs a full-context turn of the holder
for a unit whose result it only passes along.

### D-49: A notifier relays prompts and finished units; the rest is batched  (N)

**Decision:** A notifier script, run by the runner each pass under its
re-arming and timeout (REQ-E1.1, REQ-E1.6), reads
`scripts/fleet-streamjson.sh pending` and the registry and, for each new
pending prompt in a session with an answer channel and each finished unit,
delivers one line to the mission control that answers it (the program's
holder, or the launching mission control for a direct unit, D-48) by the
existing cross-session delivery, with no model turn of any other session in
between. It claims each delivery in the attention store under its lock
before sending, so a delivery happens at most once; the line carries the
kind, the session and a truncated, control-stripped summary, the same text
the attention store already holds. A failed delivery stays pending and is
retried next pass; after `mission_control_relay_retries` passes (shipped:
3) it becomes an event. A prompt in a session with no answer channel stays surfaced to
the operator once (REQ-G1.6). The other events that would wake a program's
holder are held in the attention store, not in memory, and delivered as one
wake per `mission_control_relay_batch_interval` (shipped: 10 minutes); the
shipped urgent classes
wake at once: a handover-due wake, a stopped watcher or notifier, a failed
self-check, a denial (D-23) and an operator's answer arriving. A notifier
delivery counts as a wake for REQ-L1.5's fallback.

**Alternatives considered:**
- Batching alone. Rejected because: a waiting prompt holds a worker idle
  for the whole interval.
- The notifier alone. Rejected because: the holder would still take a
  full-context turn per routine event.

**Chosen because:** mechanics are scripts (D-4): forwarding a prompt or a
finished-unit notice needs no judgment.

### D-50: Spend per session on the panel, and real-render previews before an operator-visible change ships  (N)

**Decision:** The panel and the text panel show each live session's spend
since its start in dollars, priced from its transcript's usage records with
`config/token-prices.tsv` through the shared token-spend pricing helper,
the program's total for the current UTC day across every session that ran
in it (the day the token-spend report counts), and the share of it spent by
mission-control sessions (registry kind mission-control). A session whose
spend cannot be read, or whose model has no price, shows unknown, and a
total missing any session is marked partial. The figures are display only
and feed no budget. The runner records them with the context reading
(D-46), so the panel parses no transcript.

A pull request that changes a path on `mission_control_visible_paths` (the
shipped list: the panel mod, the text panel, the digest lines, the guide;
each project may add paths) stays a draft until the operator has approved a
preview built from the real render of the change (the mod's own render or
the text panel's output, captured), rendered over fixture data and never
the live program's figures, never a mock-up. Mission control records the
approval in the program's decisions log with the operator's own words and
the preview's digest, and quotes it in the pull request; a worker never
records it. The readiness check refuses a flip of such a pull request with
no matching recorded approval, a condition added, never a narrowing of the
cadence (D-33); until that gate ships, the approval is recorded by hand the
same way.

**Alternatives considered:**
- A daily spend line only. Rejected because: the supervision overhead the
  report found is per session.
- Mock-ups for approval. Rejected because: the operator asked for the real
  render, which is what they will see.
- A preview over live figures. Rejected because: the preview is quoted in a
  pull request, and the program's figures are program data (D-8).

**Chosen because:** the operator's scope for this amendment (Sources):
spend per session visible before the daily line is crossed, and drafts held
until the real render is approved.

### D-51: The throughput duty audits idle waits  (N)

**Decision:** The throughput duty (`scripts/mc-throughput.sh`, already
shipped) gains an idle-wait audit, run at each handover and at least once
every `mission_control_idle_audit_interval` (shipped: one day), with an
injectable clock for tests. From the program's step, flight and dispatch
records, the forge snapshot's CI timing (D-12, so no duty polls the forge
itself) and the attention store, it finds intervals where a unit waited on
something it did not consume: a CI result a step does not read, a quiet or
cadence timer, steps run one after another that do not depend on each
other, and a relay through another session. Each finding becomes a
mechanization proposal in D-14's form (the mechanism looked up in the
inventory, phrased as a confirmation), naming the change and the time it
saves per day: the measured waits of that kind in the audit window, scaled
to a day. D-14's repeat threshold is waived for a measured wait; a declined
proposal stays declined as D-14 says; a proposal is identified by its kind
and the step or timer it names, so a second run proposes nothing new. The
audit is a read; it changes nothing.

**Alternatives considered:**
- Leave it to the existing bottleneck report. Rejected because: that
  report names the slowest stage, not waits that were never needed, and
  the operator found the CI wait themselves.

**Chosen because:** the operator's scope for this amendment (Sources):
mission control should find these, with an estimate, rather than the
operator.

### D-52: Bring-up audits drift from the shipped defaults, read only  (N)

**Decision:** The bring-up audit (`scripts/mc-config.sh doctor`) runs at
bring-up and in every successor's self-check, read only, and reports what
the program runs on that is not the shipped default: the four checks it
already ships (a knob set away from its shipped value, a default duty off,
a launch on another rung than the knob, a cron line touching the program),
plus a standing rule whose text names a number for a knob it governs (the
knob's name followed by a value, or a handover at a context percent) while
the knob's effective value differs, and a local-layer override whose
comment or value carries a past date, or interim, temporary or until with
no date ahead. Rule text and comments are matched as data with fixed
patterns, never evaluated. Each finding names the file, the knob, the rule
or comment and the effective value in plain words and becomes a finding the
operator settles; the audit edits no layer and no rule.

**Alternatives considered:**
- Correct the drift automatically. Rejected because: which side is right
  (the rule or the knob, the override or its comment) is the operator's
  call.

**Chosen because:** both drifts the note records were found only by hand;
the operator folded the requirement into this amendment (Sources).

### D-53: A rule says how it is enforced, and the doctor lists the ones that only live as prose  (N)

**Decision:** The rule store's entry (D-5) gains one `enforcement` field:
`script:<name>`, `knob:<name>`, `hook:<name>`, `duty:<name>` or
`default:<name>` (the kind and the thing it names), `fix:<pr-or-observation
id>` (an open fix that will enforce it), or `prose:<one-line reason>`.
`mc-rules.sh add` and `supersede` accept it (`--enforcement`); the value is
matched against that closed grammar and stored as data, never evaluated; an
entry without the field reads as `unknown`, and the loader, `render` and
re-injection (D-29) treat unknown exactly as any other value, so no old
store stops loading. `mc-config.sh doctor` (D-52) lists each active rule
whose enforcement is `prose`, `unknown`, or a `fix` whose pull request is
merged or closed (read through the forge snapshot's pull-request state, D-12,
or one read-only lookup where the snapshot lacks it; a lookup that fails
reads as unknown), each on one plain line naming the rule and the action
(name what enforces it now, keep it as prose with a reason, or retire it).
The listing edits nothing. It lands beside the open doctor flag for a rule
that disagrees with its knob (D-52), sharing its rule-text reader and
adding a separate report section, so the two do not conflict.

**Alternatives considered:**
- A free-text note on each rule. Rejected because: prose cannot be
  checked, and the whole point is to find the rules nothing enforces.
- Refuse a rule with no enforcement. Rejected because: old rules and
  genuinely prose-only ones (a tone, a priority) are legitimate, and a
  blocked load would stall bring-up.

**Chosen because:** the operator asked that each rule say how it is
enforced and that prose-only rules show (Sources); a closed grammar makes
the check mechanical and keeps the doctor read only.

### D-54: A live session's program and owner can be moved  (N; C, D-35)

**Decision:** A launcher verb, `mission-control-launch.sh reparent
<session> --program <destination>`, rewrites one registry row, under the
registry lock, from the source program to the destination and sets its
owner to the destination program's mission control (`mission-control:
<destination>`). Event routing keys on the row's program (D-35, D-49), so
a prompt raised after the move reaches the destination's events and not the
source's; the destination's `list` shows it and retirement works from it
(D-35's adoption covers it from then on). It refuses an unknown session, an
unknown or the same program, a session whose kind is mission-control, and
a row that cannot be rewritten; it never touches the session's process,
worktree or branch. The move writes one event to both programs' logs (so
each can read it) and an undo entry naming the source (D-24, with
`reparent` back as its reversal). Authority is the operator's: the verb
runs at a fold-in the operator ordered (one order covers all of the folded
program's live sessions, the operator's choice) or with their yes for that
one session, the same posture as adoption of an operator's session (D-35);
it takes `--authority <decisions-log record>` naming that order or yes and
refuses without it, so the refusal is checkable. Reversing a move through
its undo entry needs no new authority.

**Alternatives considered:**
- Re-adopt the session under the new program (the existing adopt verb).
  Rejected because: adoption refuses a session another live supervisor
  holds, which the source program's row still does, and releasing first
  loses the row's history and ownership between the two steps.
- Poll the moved sessions by a script on the new owner (the stopgap in
  use). Rejected because: it is the manual step this removes, one per
  fold-in.

**Chosen because:** the gap the fold-in showed (Sources): the owner field
was the only thing wrong, so moving exactly that field, with both programs
told, fixes it without touching a session.

### D-55: A reviewer that reviews only when ready is asked in draft first, waited for after the flip as the fallback  (N; C, D-25, D-33)

**Decision:** A knob, `mission_control_review_on_ready_bots` (shipped
empty; each project or overlay names its hosted reviewers that review only
once a pull request is ready), tells mission control which reviewers are
normally silent until the flip. Mission control first asks each of them to
review the draft by its trigger comment (a trigger comment known to work on
drafts, or the reviewer's documented review command), answers and resolves
their threads through the bot-review step, and then flips: the operator's
choice, so the flip means done. A reviewer that has not reviewed the
current head within `mission_control_review_on_ready_wait` (shipped: 30
minutes) of its trigger, or that cannot be triggered on a draft, falls back
to the path below for that reviewer, so nothing deadlocks. The readiness
check is split at that line, not weakened: the flip conditions (D-33's
cadence, CI, mergeability, threads, the spec and visual gates) are
unchanged and never wait on a fallback reviewer, because it cannot review
first; the *merge-ready* report is a second evaluation at the same head,
which additionally requires
that every named reviewer has a review on the pull request's current head
(read from the forge snapshot, D-12), that every thread is answered and
resolved by the bot-review step, and that the flip conditions still hold.
Until then the unit's state is *ready, awaiting reviewers*; the
ready-to-merge notice (the program's standing rule) is not sent. A reviewer
silent after `mission_control_review_on_ready_wait` (shipped: 30 minutes)
is an operator item naming it; a quota or outage reply is recorded as that
reviewer's skipped pass with the reply quoted; a push restarts the wait.
The bot-review step's own contract (answers, rejections needing the
operator's yes) is unchanged.

**Alternatives considered:**
- Flip first and always wait after it (the draft's first form). Rejected
  because: the operator chose to review in draft and flip when done; it
  survives only as the fallback for a reviewer that cannot or does not
  review the draft.
- Refuse the flip until they have reviewed, with no fallback. Rejected
  because: a reviewer that only starts on the ready event would deadlock it.
- Mark the pull request ready, then back to draft while waiting. Rejected
  because: it re-triggers or hides reviewers and misstates the pull
  request's state.

**Chosen because:** the review-on-ready report (Sources): readiness passed
before findings landed on four threads; the operator's choice (review in
draft, flip when done) handles the findings before the flip, and the
per-reviewer fallback with a separate merge-ready report keeps the flip's
gate whole for a reviewer that cannot be reached in draft.

### D-56: Asks and duties become ledger items by a deterministic path  (N; C, D-9)

**Decision:** The ledger (D-9) stops depending on the session remembering to
write to it. The mission-control tier records each operator message as an
intake row when it arrives (the intake rows are a durable queue of asks),
and a turn-end check and the handover self-check refuse to finish while an
intake row is neither made into a ledger item (owner, trigger,
done-condition) nor dismissed with a one-line reason. An audit of the
state mission control holds that something waits on checks each kind
against a shipped register (its store, and what removes an entry), flagging
a kind that is not a durable queue and has no recorded reason. The ledger row gains a
done-condition field; the row format version moves with a reader that treats
an old row as having none. Overdue items (trigger fired, open, not
acknowledged) lead the status and make the handover self-check fail until
each is acknowledged by a record that states the next step and a new date or
event. `followup add` checks an event trigger against the emitted event
classes (the watchers' declared kinds and the event store's, from the
shipped class table) and refuses an unknown one unless a fallback date is
given. A stale-open audit proposes closing items whose done-condition is
already met, with the evidence, and never closes one. The runner calling
`followup due` each pass is D-9's and is a separate flight.

**Alternatives considered:**
- A stronger reminder in the skill text. Rejected because: that is the
  memory the failure came from, and the instruction budget is full.
- Classify asks by reading the message for verbs in a script. Rejected
  because: deterministic detection of an ask in free text is unreliable;
  recording every message and requiring a disposition keeps the check
  mechanical and puts the judgment in the one place that has context.
- Auto-close an item when its condition is met. Rejected because: closing
  is a claim, and an item closes only with evidence a person can read.

**Chosen because:** the operator named forgetting asks and duties as the
core gap; an intake row plus a turn-end check makes recording the default
and forgetting a refusal.

*(Amended at amendment 15 2026-11-13: the stale-open audit's "never closes
one" and the auto-close alternative are narrowed by D-65; a sweep closes on a
passing machine check with the evidence recorded, never on a person's
confirmation or a bare assertion.)*

### D-57: One lease shape, and rules carry clauses the guard keeps  (N; C, D-5, D-24, D-53)

**Decision:** A rule entry may carry an enforcement clause (match, effect,
unless, scope) in a closed grammar, compiled by `mc-rules.sh` into a
digest-checked clause file in the program home, which the worker tier's
policy guard reads on each tool call whose tool and scope a clause could
match, and otherwise leaves untouched. Matching uses planwright's own
tokenizer and matcher, never raw regular expressions or evaluated text. A
new clause runs in shadow mode (record, never block) until the operator
says yes after seeing what it recorded. A denial names the rule id. The
`unless` part, and the worker-permission-ergonomics hooks-directory edit
(that bundle's D-35), share one lease: a record naming kind, one worker,
scope, expiry and the operator authorization, opened only by mission control
after the operator's yes, held outside every worktree, closed on report,
retirement or expiry, read through one reader where anything not clearly
open is no lease. A lease never lifts a Bash `deny` row. The headed browser
rule is the worked example and fixture, held by a program as its own rule.
The doctor lists hard-sounding rules without a clause as candidates only.

**Alternatives considered:**
- One purpose-built setting per rule (a browser knob and so on). Rejected
  because: the operator asked for no feature-specific settings; every new
  rule would need new code.
- Let the hub's session enforce rules by reviewing calls. Rejected because:
  prose enforcement is what failed; a guard decides the same way every time.
- A separate lease design for the hooks edit. Rejected because: two stores
  with the same job drift apart; one reader is one place to be wrong.
- Start every clause live. Rejected because: a false deny blocks work, and a
  rule written in prose has never been tested against real calls.

**Chosen because:** the operator asked for rules planwright enforces
deterministically and for the hooks lease to be the same shape; the clause
grammar stays data so enforcement adds no new way to run text.

### D-58: Idle capacity is reported and a knob rule says its required value  (N; C, D-51, D-52, D-53)

**Decision:** The throughput duty's audit (D-51) also reports idle capacity
as proposals naming the knob: an offload host left unused, free slots while
units queue, a host far under its load cap. The `knob` enforcement kind
(D-53) may carry the required value or a predicate from a closed set, and
the doctor (D-52) reads the effective value and flags a disagreement, a
value it cannot read counting as disagreeing. The number-in-prose reading
stays as it is.

**Alternatives considered:**
- Parse the required value out of the rule's text. Rejected because: that is
  the prose reading D-52 already does for numbers, and it cannot say
  "not local".
- Report idle capacity from the operator's own prompt. Rejected because: the
  operator should not have to notice it; the waste is invisible until measured.

**Chosen because:** the offload knob stayed at its local default while two
rules said otherwise and nothing noticed; a structured required value turns
that into a check, and the duty reports the waste it left.

### D-61: An idle-capacity duty raises an event, from a declared backlog  (N; C, D-51, D-58, D-17)

**Decision:** A core `idle-capacity` duty (`scripts/mc-idle.sh`, a five
minute low-priority watcher, in the default duty set) runs the check each
wake: free slots are the smaller of the host-wide bound less every program's
live sessions and the program bound less its own, mission-control sessions
counted in neither; the gates are the launcher's own admission for heavy
work (`scripts/mc-budget.sh admit heavy`), so the duty cannot raise a launch
the launcher would refuse. With a slot free, the gates open and a unit in
the backlog, it raises an `idle-capacity` event (class blocker) naming up to
one unit per free slot, at most five. The backlog is a configured file of
ranked unit ids, one per program (a program-scoped knob, absolute path or
`off`); none, or unreadable, raises one `idle-capacity-undeclared` event
(class decision) and nothing else. Dedupe: the same unit list is not raised
again inside `mission_control_idle_interval`, a changed list raises at once,
and a state that stops being idle is forgotten. The duty never launches; the
holder acts on the event. D-58's windowed report (REQ-M1.11) is unchanged.

**Alternatives considered:**
- Extend D-58's report to raise per wake. Rejected because: that report is a
  proposal in D-14's form on a daily and handover cadence, read by the
  operator; a free slot is an act for the holder now, so it must be an event.
- The duty launches the unit itself. Rejected because: launching is the
  holder's act and its gates (the operator's holds, REQ-I1 invariants) live
  there; the duty only makes the gap visible.
- Infer the backlog from open pull requests, specs or the ledger. Rejected
  because: every inferred source guesses, and a wrong guess launches wrong
  work; a declared file makes the work order the operator's or the
  supervisor's own.

**Chosen because:** every other duty reacts to an event, so a supervisor
whose units finished waited for the operator with slots free; a per-wake
comparison closes the gap without a second place that launches.

### D-65: The runner repeats the wake and sweeps validity; the sweep may close on machine evidence  (N; C, D-9, D-56)

**Decision:** The runner's follow-up pass (D-9) changes from raise-once to
repeat-until-acted-on: a due item raises `followup-due` (class act), and
the same wake repeats each repeat interval while the item stays open and
unacknowledged; past an overdue grace it raises `followup-overdue`, a
failure-class event the operator is pushed, repeating the same way. A second
runner step, the validity sweep, re-checks every open item against live
state (a command check, the pull request the item names, an event of its
class seen after it opened, the date) and ends each in one recorded outcome:
closed with the evidence, still valid (checked-at recorded), due and raised,
or stale and raised (`followup-stale`, class act). The sweep may call
`close` itself, and only where the done-condition is machine-checkable and
the check passes; evidence is recorded in the same call, so an item still
closes only with evidence a person can read. An item whose condition only a
person can confirm is never closed by the sweep. The per-item raise record
and the sweep outcomes live in the runner's runtime directory, not in the
ledger, so the ledger's row format and its one writer per file (REQ-K1.5)
are untouched. D-56's rejection of auto-close is amended to this: the
rejected shape was closing on a bare assertion, and the sweep closes on a
check.

**Alternatives considered:**
- Keep raise-once and rely on the acknowledgement rule (D-56). Rejected
  because: a promise raised once at a moment nobody reads is exactly the
  forgotten item; the operator lost a week to it.
- A scheduled standing LLM session reviewing the ledger. Rejected because:
  REQ-C1.5 keeps mechanics deterministic and no standing session watches
  anything.
- Propose closes and never close (D-56 as written). Rejected because: a
  proposal nobody acts on leaves the ledger growing; a passing check the
  runner already ran is the evidence.
- Close on any condition, including a person's confirmation. Rejected
  because: that is the bare assertion D-56 rightly refused.

**Chosen because:** the failure was a ledger that depended on a session
remembering to look; a runner that re-checks every item on every pass makes
silence impossible, and failure-class overdue events put a missed duty where
the operator cannot miss it.

### D-66: A time-bound standing rule is a ledger item  (N; C, D-5, D-56)

**Decision:** The rule store keeps what holds without end; whatever ends
when a condition is met is a ledger item. `mc-rules.sh add` takes an end
condition (`--until`, a date, an event or a command check) and, given one,
writes the rule and its ledger item in one call, the item naming the rule
and its done-condition being the end condition; closing the item with
evidence supersedes the rule in the same step, through the rule store's own
supersede path (REQ-B1.2). A rule without an end condition is standing.
Existing rules that read as time-bound are listed by the sweep as proposals
to move; detection is a word list and only ever proposes.

**Alternatives considered:**
- Detect time-bound rules from their text and move them automatically.
  Rejected because: D-56 already records that deterministic detection of an
  intent in free text is unreliable; a wrong move changes what the operator
  asked for.
- Leave the end condition in the rule's prose for the session to honour.
  Rejected because: "until the operator resets usage" stayed in force past
  its condition because nothing watched it.

**Chosen because:** the same ledger machinery (trigger, wake, sweep,
evidence) then governs the end of a rule, and a rule's lifetime is recorded
data instead of a sentence.

### D-67: The ledger is a default-on duty; the event registry is checked complete  (N; C, D-3, D-27, D-56)

**Decision:** The altitude is core: the ledger's runner steps ship as a
duty in `config/duties.yaml`, lifecycle live, named in the default duty set
(`mission_control_default_duties`), so every installation and every
adopter's hub gets it without opting in. The raise pass and the sweep arm
only while the duty is enabled (REQ-C1.4); the doctor flags a program whose
own list omits it, or a disabled duty with open items, naming the count.
Ledger writes (`followup add` and `close`) work whatever the duty state, so
nothing is lost by disabling. Separately, a shipped check fails when an
emitter writes an event kind the registry lacks, so the emitted set
`followup add` validates against cannot drift behind the emitters; the
words in existing triggers that nothing emits are reported by the sweep.

**Alternatives considered:**
- Leave the raise pass hard-wired in the tick with no duty. Rejected
  because: it cannot be switched off for a shadow period (REQ-C1.6), is
  invisible in the duty list the operator reads, and gives the doctor
  nothing to flag.
- Ship the duty off by default. Rejected because: a duty only some
  adopters turn on is the per-machine habit the operator's loss came from.
- Add the missing event words (`launches-unheld` and the like) as emitted
  events. Rejected because: those words describe a condition, and a command
  check says the same without a new emitter per phrase.

**Chosen because:** the operator wants this for every hub and coworker, with
no step to remember.

### D-68: Rulings are recorded when given and checked at every crossing  (N; D-5, D-56, D-65)

**Decision:** An operator ruling is data the moment it is given: it goes to
the rules store when it is standing or to the decisions log when it settles
one question, quoting the words. Three checks read that store so a ruling
cannot cross a handover or a question unseen: handover verify and resume
match each step the brief hands the operator and each question it plans to
ask against the recorded rulings by their recorded subject and fail naming
the ruling; the inbox and decide verbs check an item against the rulings
first and apply a match instead of asking; the doctor lists session memory
that holds a ruling as a proposal to migrate. Matching is on the recorded
subject, never on free text read for intent (D-56), and every check only
refuses or proposes.

**Alternatives considered:**
- Trust the successor to read the predecessor's brief carefully. Rejected
  because: that is how a settled publish step was handed back to the
  operator.
- Infer rulings from prose in briefs and memory. Rejected because: D-56
  records that detecting an intent in free text is unreliable.

**Chosen because:** a ruling that lives only in a session's head is lost
with the session; one in the store is read by every successor.

### D-69: The outcome audit and the miss ledger  (N; D-9, D-65, D-67)

**Decision:** The self-audit checks acts against rules and throughput
measures time; neither checks outcomes. An outcome-audit duty ships default
on (D-67) and runs, on a cadence, the checks the operator runs by eye over
recorded state: pull requests going ready per program, ready pull requests
waiting on merge, parked or idle workers, launch holds, overdue ledger
items, operator items left unasked or put again after a ruling. A red check
raises a failure-class event the operator is pushed (D-65's overdue path). A
relayed session's finished turn ending in a question raises an event to its
mission control at once, closing the unrelayed-question gap. When the
operator catches a problem the system did not raise, it is recorded in a
miss ledger (the follow-up ledger's format, D-65's close-only-with-evidence
rule) with their words, and closes only when a detector exists with a test
proving it fires on that case and the upstream fix exists. A periodic report
counts misses caught by the operator against those the system raised first.

**Alternatives considered:**
- Add each check to the self-audit. Rejected because: it audits acts
  against rules; an outcome has no rule it breaks.
- Fix each missed case and record nothing. Rejected because: the next miss
  has no trend and no detector.

**Chosen because:** every core failure so far was found by the operator;
the system should find the next one first, and learn from each it did not.

## Cross-cutting concerns

- **Data hygiene.** The program home holds company data by design and is
  never committed; every committed artifact this bundle produces (catalog
  seeds, docs, pending notes) is neutral.
- **Instruction budget.** D-21 governs every task that adds skill prose.
- **Floors.** Non-authoring, no-LLM mechanics, assume multiplicity,
  deterministic attention, lifecycle closure and the human gates carry
  unchanged into every decision above.
