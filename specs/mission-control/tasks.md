# Mission control — Tasks

**Status:** Ready
**Last reviewed:** 2026-10-24
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order, which is presentation; the `Dependencies:` lines
carry the graph. Tasks 6, 12 and 14 are routed work (amendments to owner
bundles, and pending notes for follow-on bundles) and depend on nothing
here, so they can run first.

## Tasks

### Task 1 — Program and duty catalog seams

- **Deliverables:** The `duties` catalog: `config/duties.yaml` with the
  entry grammar (id, summary, triggers, watchers with cadence and cost
  class, wake, rules, kinds, files, lifecycle, never-propose), merged by
  `scripts/resolve-catalog.sh` with supersede-by-id across the four layers;
  the `program` configuration block (repositories, spec root, program home,
  enabled duties, budget, the state-source map with its `record`,
  `snapshot` and `cited` modes and the specs-plus-forge default) read
  through the config resolver; every
  `mission_control_*` knob this bundle names in `config/defaults.yml` with
  its options-reference row and its evidence; a `check:duties` script
  validating catalog entries and enabled lists, and a knob inventory check
  (every `mission_control_*` key resolves with its default; a seeded
  behaviour without a knob fails), both wired as dependencies of
  `check:non-test`, the aggregate CI's lint job runs.
- **Done when:** A fixture overlay adds a custom duty and supersedes a
  shipped one and the merged view shows both; an invalid entry fails
  `check:duties` with the field named; every new knob has an
  options-reference row and the reference check passes; a disabled duty
  resolves to no watchers and no files; a program block without a source
  map resolves to the default map, one naming an unknown mode fails
  `check:duties` with the mode named, and a class the map leaves out
  resolves to `cited`; a seeded knob-less behaviour fails the knob
  inventory check; CI's lint job runs both checks.
- **Dependencies:** none
- **Citations:** D-3, D-8, D-20 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4,
  REQ-H1.1, REQ-H1.4, REQ-J1.1, REQ-J1.2
- **Estimated effort:** 2 days

*(Amended at sign-off lens pass 2026-10-24: wired into `check:non-test`, the
task CI actually runs; the knob inventory check built here, since REQ-J1.1
named one nothing delivered; the no-adapter check moved to Task 5, where
the adapters arrive.)*

### Task 2 — The rule store

- **Deliverables:** `rules.yaml` in the program home and
  `scripts/mc-rules.sh` with `add`, `supersede`, `list`, `active` and
  `render` verbs (entries carry text, subject, source, date, scope,
  supersedes; the active set excludes superseded entries; one writer under
  a lock); the direct-entry path for an operator-stated decision (add,
  one-line echo, undo entry); the render shape the launcher embeds in
  briefs; the bring-up load and the post-compaction self-check the skill
  runs; a shared-subject report for the self-audit.
- **Done when:** Superseding an entry removes it from `active` and keeps it
  in `list`; `add` without a subject is refused; `render --scope
  <duty|repo>` emits only in-scope rules; two active entries sharing a
  subject are reported; a fixture brief contains the rendered rules; the
  store carries its `format` field and a store with an unknown format is
  refused with the field named.
- **Dependencies:** 1
- **Citations:** D-5, D-29 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4,
  REQ-B1.7
- **Estimated effort:** 2 days

### Task 3 — The launcher across session kinds

- **Deliverables:** `scripts/mission-control-launch.sh` composing the
  flight, tmux, stream-json and offload dispatch primitives to start a
  session of kind tower, orchestrator, worker, reviewer or ad-hoc with a
  brief, the in-scope rules, the permission profile, the model tier from the
  allocation seam and a deterministic name, registering owner, kind and
  scope; the `mission-control` guard tier and its settings profile (the
  tower tier's denials plus a ready flip inside the configured ready-flip
  policy) with its guard fixture rows (git mutations, merges, settings
  writes, flips outside the policy, rewrites without a same-turn request,
  protected pushes and remote deletes refused; a flip inside the policy
  allowed); a `retire` verb that exits, closes the pane and clears the
  registry and attention rows, reporting any part not released; the
  never-hand-the-operator-a-pane rule in the skill's relay step.
- **Done when:** Each kind launches from a fixture with the brief, rules
  and profile present in the launched session's inputs and a registry row
  with owner and kind; `retire` on a finished fixture session leaves no
  row and no pane, and a partial release is reported as partial; a launch
  without a profile is refused; a launch with no resolvable tier is
  refused; the same inputs yield the same session name; a static check
  shows each profile's allow set covers its sanctioned commands; the
  mission-control tier's fixture rows pass.
- **Dependencies:** 1, 2
- **Citations:** D-10, D-23 · REQ-A1.3, REQ-A1.4, REQ-D1.1, REQ-D1.5,
  REQ-G1.1, REQ-G1.4, REQ-I1.1, REQ-I1.2, REQ-I1.4, REQ-M1.7
- **Estimated effort:** 3 days

*(Amended at sign-off lens pass 2026-10-24: the `mission-control` guard tier
and its fixture rows delivered here, since five test entries ran "from a
mission-control marked session" that nothing built; tier refusal, the
deterministic name and the static profile check added to Done-when.)*

### Task 4 — Liveness and stall states for every session kind

- **Deliverables:** The stuck detector extended with positively named
  states for every kind (dead, open selector, unsubmitted prompt, turn
  ended with background work, idle with a question, busy unchanged past the
  stall window, unknown for a changing pane with no pid), each emitting an
  attention event; liveness from the
  registry pid and process state only; the worktree reclaim predicate
  (no live user, PR landed or closed, nothing uncommitted or unpushed,
  ignored audit files backed up into the program home's per-repository,
  per-branch reclaim folder and verified by size and hash) as a script,
  with the audit-file set as a knob; the routed fleet-lifecycle-closure
  amendment note for the new resource classes.
- **Done when:** Each state is produced from a fixture and no state is
  inferred from elapsed time alone; a reclaim with a failed backup or a
  hash mismatch is refused and says why; a complete reclaim leaves the
  copied files under the program home; the amendment note names the
  resource classes and cites this task.
- **Dependencies:** 3
- **Citations:** D-8, D-11, D-22 · REQ-D1.2, REQ-D1.3, REQ-D1.6
- **Estimated effort:** 2 days

*(Amended at sign-off lens pass 2026-10-24: the `unknown` state added with
D-11.)*

### Task 5 — Watcher runner, source snapshots and budget

- **Deliverables:** `scripts/mc-watch.sh`, a runner under the fleet daemon
  gate that arms every enabled duty's watchers at their cadence, re-arms
  one that stopped and emits a watcher-stopped event; `scripts/mc-snapshot.sh`
  as the source-agnostic snapshot seam (one age-stamped snapshot per
  snapshot-mode source in the program's map, an adapter contract a later
  bundle implements per source) with the forge adapter shipped (heads,
  drafts, mergeability, review decision, open threads, checks, reviews,
  comments, patch id per PR) and rate-limit backoff; the per-program budget
  file (sessions, source polls per hour across every snapshot-mode source,
  spend class per duty, context steps, host load) and
  `scripts/mc-budget.sh` reporting headroom and the degradation rung; the
  daemon-side wake relay for sessions without the mod (through the fleet's
  session relay for the registered backend) and the daemon-side failsafe
  tick.
- **Done when:** A killed watcher is re-armed within one runner pass and
  the stop is an event; a fixture event reaches a mod-less session through
  the relay or, where the relay only stages, within one tick; a fixture
  adapter registered for a second source produces its own age-stamped
  snapshot through the seam; two duties
  reading the snapshot cause one forge
  read per cadence; a snapshot older than its cadence reports its age; a
  `snapshot` source with no registered adapter fails `check:duties` with
  the source named; a fixture adapter reporting exhausted rate-limit
  headroom delays its next read instead of polling; the budget script
  reports each rung from fixtures, counts a second source's polls against
  the cap and honours the daemon pause; no runner step calls a model.
- **Dependencies:** 1
- **Citations:** D-4, D-12, D-17 · REQ-A1.2, REQ-C1.5, REQ-E1.1, REQ-E1.2,
  REQ-E1.3, REQ-E1.5, REQ-H1.4, REQ-L1.1, REQ-L1.2, REQ-L1.4, REQ-M1.1,
  REQ-M1.6
- **Estimated effort:** 3 days

*(Amended at sign-off lens pass 2026-10-24: the no-adapter check moved here
from Task 1; the backoff and the second source's polls made evaluable.)*

### Task 6 — Operator queue amendment (routed to tower-comms)

- **Deliverables:** Through `/spec-draft --extend tower-comms`: a presence
  input the queue reads (from the panel's prompt events, falling back to
  the quiet-interval detector); picklist windows with a declared default
  or park; the settled-by-default and decided-by-mission-control item
  kinds, visible and reversible; the "nothing dropped" settling rule (an
  item leaves only by an answer or by evidence it no longer applies, with
  the reason); batching by subject.
- **Done when:** The tower-comms delta is signed off and its tasks merged,
  with fixtures showing a timed-out picklist settling to its default while
  the item stays visible and a settled-by-evidence item carrying its reason.
- **Dependencies:** none
- **Citations:** D-7, D-22 · REQ-F1.4, REQ-F1.5, REQ-F1.6, REQ-G1.2,
  REQ-M1.2
- **Estimated effort:** 3 days

### Task 7 — The panel mod

- **Deliverables:** A mod inside the planwright plugin: a pane and a band
  showing what is in flight, what waits, recent decisions, headroom,
  compactions since start, knowledge-base freshness and each state
  source's mode and age, read from the
  stores on a timer; the primary wake (an attention-store watch that
  submits the wake prompt when an event is pending and the session is
  idle); presence fed to the queue from prompt events; the
  failsafe tick from the timer submitting a prompt only when due and idle;
  the research record on whether each fleet relay submits or only stages a
  prompt, with the stages-only backends falling back to the tick;
  context percent and rate limits from the session usage call; the
  post-compaction rule re-injection hook; the handover trigger at the knob
  threshold; light aviation theming and animation within the redraw
  throttle; a text fallback where nothing draws; `claude plugin test`
  tests for every surface and the fallback, wired as a dependency of
  `check:non-test`, the aggregate CI's lint job runs, beside the existing
  plugin validation; the CI workflow's pinned CLI version raised to at
  least the mods floor (D-6) so the suite runs above it.
- **Done when:** Tests draw the pane on each surface from fixture stores,
  show the fallback where no surface draws, submit the wake prompt within
  one redraw of a fixture event when idle and hold it while busy, fire the
  tick at the cadence without a turn when nothing is due, submit the tick
  prompt when due and idle, re-inject rules on the compaction hook, and
  raise the handover at the threshold; the research record states, per
  backend, whether the relay submits; `claude plugin validate` lists only
  the calls the design names; the plugin tests run in CI's lint job through
  `check:non-test`, on a CLI at or above the mods floor, and fail the gate
  on a seeded drawing defect.
- **Dependencies:** 2, 5
- **Citations:** D-6, D-29 · REQ-E1.3, REQ-E1.4, REQ-F1.1, REQ-F1.2,
  REQ-H1.4, REQ-L1.4, REQ-L1.5, REQ-M1.2, REQ-M1.8
- **Estimated effort:** 4 days

*(Amended at sign-off lens pass 2026-10-24: wired into `check:non-test`, since
CI never runs the `check` aggregate itself; the CI CLI pin raised, since
it sat below the mods floor.)*

### Task 8 — Knowledge base, ledgers and undo

- **Deliverables:** The program-home layout (`kb/index.md`, per-duty
  subdirectories, `decisions.log`, `undo.log` and the shadow would-have log
  as monthly segments, the follow-up ledger, the living-versus-consumed
  source table, the mechanism inventory) with `scripts/mc-kb.sh` verbs to
  index, read within the entry cap, append a decision or an undo entry with
  its subject and reversal, query a log by subject across segments, claim a
  file's write lock (recording the holder pid, releasing a dead holder's
  lock with a log line), and refresh the mechanism inventory from the
  installed host and planwright surfaces (knobs from the options
  reference, catalog steps, hook and permission settings, routines,
  duties, the rule store) with a source per row; the loading rules and
  caps as knobs; freshness reported for the panel; a copied-section lint
  over the knowledge-base fixtures, wired as a dependency of
  `check:non-test`.
- **Done when:** A read above the cap is refused with the offload hint; an
  append under a held lock waits or fails, never interleaves; a decision and
  its undo entry round-trip and the reversal command runs from the entry;
  the index stays within its line budget or reports the overflow; the
  inventory refresh writes one row per mechanism with its source and moves
  the table's watermark; every store the layout creates carries its
  `format` field, and a read of a store with a missing or unknown format is
  refused with the store named; a subject query spanning two segments
  returns matches from both; a lock left by a dead pid is released by the
  next writer and logged; the copied-section lint flags a seeded copy.
- **Dependencies:** 1
- **Citations:** D-9, D-24 · REQ-D1.7, REQ-F1.10, REQ-K1.1, REQ-K1.2,
  REQ-K1.3, REQ-K1.4, REQ-K1.5, REQ-K1.6, REQ-K1.7
- **Estimated effort:** 2 days

*(Amended at sign-off lens pass 2026-10-24: monthly segments, the dead-holder
release and the copied-section lint, each with its Done-when clause.)*

### Task 9 — Autonomy, calibration, proposals, shadow mode and self-audit

- **Deliverables:** The decided-by-mission-control record and the reasons
  grammar; the calibration ledger (a revoked class drops to ask-first until
  a configured run of confirmations); the repeat detector over the decisions
  log and asks with threshold and window knobs; the mechanization proposal
  record (a repeat mapped to the smallest covering row of the mechanism
  inventory) in the confirmation shape (noticed, mechanism and change,
  cadence, intervention points, cost, off switch, explicit decline),
  accepted, declined and parked outcomes, with a settings-kind change
  rendered ready to apply and never written; the `shadow` lifecycle with
  would-have
  entries and the promotion suggestion; the self-audit duty script
  comparing logs with active rules; the interruption and settled-share
  measures.
- **Done when:** Fixtures show a revoke lowering a class and confirmations
  restoring it; a repeat at the threshold yields exactly one proposal
  naming an inventory row and a declined one is not re-proposed on the same
  pattern; a repeat covered by a knob or catalog step proposes that and not
  a duty; a settings-kind proposal leaves every settings file untouched; a
  shadow duty writes would-have entries and raises nothing; the audit
  flags an act against a rule and two active entries sharing a subject;
  the measures compute from the logs.
- **Dependencies:** 2, 8
- **Citations:** D-13, D-14, D-15, D-16 · REQ-B1.5, REQ-B1.6, REQ-C1.6,
  REQ-C1.7, REQ-F1.8, REQ-F1.9, REQ-G1.4, REQ-K1.7, REQ-M1.8
- **Estimated effort:** 3 days

*(Amended at sign-off lens pass 2026-10-24: depends on Task 2, whose
shared-subject report the self-audit reads.)*

### Task 10 — The default duties

- **Deliverables:** Catalog entries and scripts for session-keeper (drive
  to done, retire on landing, reclaim), inbox (status form, item shape,
  voice drafts to the clipboard, prepared packets), readiness-check (the
  primary-evidence walk over the gate-condition data, composing the
  ready-flip guards, screenshots opened and judged), the gate-condition data
  format per program, repository, label and path bounded by the gate
  policies, conflict-radar (same-file and same-line prediction across the
  program's branches, merge order and stack retargets from the whole
  graph), deadline-watch (dates in `record` and `snapshot` stores and
  operator-stated dates driving priority and the first turn after silence;
  no calendar read until an adapter exists), prepared-moments; pipelining
  of the next ready unit while others wait.
- **Done when:** Each duty resolves from the catalog and its watchers arm
  under the runner; the readiness walk refuses a fixture with a missing
  step, a red individual check, an open thread, an unanswered finding or a
  screenshot whose recorded judgment is error or missing, and passes a
  complete one; a gate condition that would authorize a merge is refused at
  load; the radar flags a same-line overlap from two fixture branches,
  computes merge order from the graph and yields a retarget for a stacked
  branch on a base merge; a fixture deadline raises its unit's priority; a
  voice draft lands on the clipboard and nothing is sent; a packet is
  assembled from fixtures with the readiness result first; the next ready
  unit dispatches while a fixture unit waits on CI.
- **Dependencies:** 3, 4, 5, 9
- **Citations:** D-25, D-26, D-27 · REQ-D1.4, REQ-D1.8, REQ-F1.3,
  REQ-F1.7, REQ-F1.11, REQ-F1.14, REQ-I1.7, REQ-M1.3, REQ-M1.4, REQ-M1.5
- **Estimated effort:** 4 days

*(Amended at kickoff 2026-10-24: depends on Task 4, whose reclaim predicate
the session-keeper duty runs.)*

*(Amended at sign-off lens pass 2026-10-24: deadline-watch's day-one sources
per D-27; the screenshot clause given an observable; clauses for deadline
priority, stack retargets and clipboard drafts.)*

### Task 11 — The skill

- **Deliverables:** `skills/mission-control/SKILL.md`: the command with
  its optional program-name argument (one program resumes, several ask,
  none enters the first run), bring-up from durable evidence, the
  one-live-session rule with the operator-asked resume path, the
  source-naming rule (mode and age wherever a report draws on a source, a
  stated gap where a fact class is only `cited`), the guided
  first run with its state-source objective and
  the guidance knob, the register, the contract by reference to the tower
  with the lifted limits stated, the duty catalog on request, the relay and
  denial rules, the relayed kickoff and amendment flow with its
  relay-or-manual knob (kickoff questions operator-only), the invariants;
  the doctrine manifest; `/tower` gains a
  one-line pointer to mission control; `check-instructions.sh` green for the
  skill and its closure.
- **Done when:** The skill resolves its doctrine at run start; a fresh
  installation enters the guided first run and ends with a program block,
  a knowledge-base skeleton and enabled duties written; the instruction
  budget check passes in CI; `skills/tower/SKILL.md` carries the one-line
  pointer; the relay-or-manual knob resolves with its options-reference
  row.
- **Dependencies:** 2, 3, 5, 6, 7, 8, 9, 16
- **Citations:** D-1, D-2, D-18, D-19, D-21, D-23 · REQ-A1.1, REQ-A1.2,
  REQ-A1.3, REQ-A1.5, REQ-A1.6, REQ-A1.7, REQ-F1.12, REQ-F1.13, REQ-G1.3,
  REQ-G1.4, REQ-H1.4,
  REQ-I1.1, REQ-I1.2, REQ-I1.3, REQ-I1.4, REQ-I1.5, REQ-I1.6
- **Estimated effort:** 3 days

*(Amended at sign-off lens pass 2026-10-24: a Done-when clause that any skill
file satisfied replaced by the pointer and knob checks.)*

### Task 12 — Cross-repository amendments (routed)

- **Deliverables:** Through the owner bundles: a per-task repository field
  in the task block grammar (invariant-tasks and spec-format) read by the
  dependency derivation so each dependency's state comes from the
  repository it landed in; the holder-to-work-repository reverse registry
  that lifts custom-spec-location's deferred gate, so a session in a holder
  dispatches into its work repositories; a pending note for each.
- **Done when:** A fixture bundle with tasks in two repositories derives
  each task's dependency state from its own repository and the selector
  dispatches a unit into the right one from a holder checkout; the
  amendments are signed off and merged.
- **Dependencies:** none
- **Citations:** D-22 · REQ-H1.2, REQ-H1.3
- **Estimated effort:** 3 days

### Task 13 — Doctrine and docs

- **Deliverables:** `doctrine/mission-control.md` (the session kind, the
  duty contract, the rule store, the register delta, autonomy at this tier,
  the program and its home, the floors restated by reference), the glossary
  entries in `doctrine/spec-format.md` (mission control, program, program
  home, duty, rule store, state-source map and its modes, mechanism
  inventory, mechanization proposal, shadow mode, reclaim folder, cadence
  step, the format field and its additive-only rule, the handover file as
  distinct from the handover brief, launch kinds), `docs/mission-control.md`
  for operators (first run, state sources, duties, proposals, knobs,
  resume, handover), README and doctrine index rows.
- **Done when:** The doctrine index check passes; each glossary term the
  skill uses links to a section of the doctrine doc; the operator doc walks
  a fresh installation end to end without a planwright term the register
  forbids.
- **Dependencies:** 10, 11
- **Citations:** D-1, D-19 · REQ-A1.6
- **Estimated effort:** 2 days

*(Amended at kickoff 2026-10-24: depends on Task 10, whose default duties
the operator doc describes; the skill itself does not, a deliberate
non-edge the kickoff brief records.)*

*(Amended at sign-off lens pass 2026-10-24: the glossary file named and the
kickoff's concepts listed; the concept clause given a checkable set.)*

### Task 14 — Pending notes for the follow-on bundles

- **Deliverables:** `_pending/review-desk.md`, `_pending/spec-currency.md`,
  `_pending/environment-broker.md`, `_pending/night-shift.md` and
  `_pending/state-source-adapters.md` (the snapshot adapter contract of
  D-12 implemented per source, Jira, Notion and Figma named as candidates,
  each adapter's auth, rate limits and write policy as that bundle's
  decisions), each naming the shape from the seed or this kickoff, the
  observation uids left live for it, the seams it consumes here (the duty
  catalog, the launcher, the snapshot seam, the queue, the source map) and
  the suggested invocation; the observation routing recorded so the next
  drafting consumes them.
- **Done when:** Each note exists, cites only live fragments, and names
  this bundle's decisions it builds on; no fragment named is archived.
- **Dependencies:** none
- **Citations:** D-22, D-27
- **Estimated effort:** half day

### Task 15 — Behavioral eval fixtures, the eval cadence step and CI wiring

- **Deliverables:** One fixture per `[Gherkin]` arm of the test-spec, which
  owns the list (the register, turn density, picklist shape, proposal
  shape, the guided first run, the first turn after silence, the relayed
  kickoff selector, the argument rules, the direct rule entry, the
  cited-source answer and the decide-or-queue routing among them), run on
  demand under the
  behavioral-eval harness (never in CI, per the repository's CI-eval
  exclusion guard); a cadence step in the steps catalog that runs the
  suite and records its outcome, required before any unit of this bundle
  still open when the step lands, and every unit of the follow-on bundles,
  is marked ready; the manual sweep row that inventories the runs;
  CI wiring for the deterministic checks only: `check:duties`, the
  options-reference rows, the plugin tests and the instruction budget.
- **Done when:** The suite runs on demand against the skill and fails on a
  seeded violation of each rule; the cadence step records a run per head
  and a red or missing record refuses the ready flip of this bundle's
  still-open units and of every follow-on bundle's units; the CI-eval
  exclusion guard stays green with the step present; a Gherkin arm with no
  fixture fails the suite's own completeness check; the deterministic
  checks run in CI.
- **Dependencies:** 11
- **Citations:** D-19, D-21 · REQ-A1.7, REQ-B1.1, REQ-F1.7, REQ-F1.8,
  REQ-F1.12, REQ-H1.4, REQ-I1.5
- **Estimated effort:** 2 days

*(Amended at kickoff 2026-10-24: the step's reach stated as the units still
open when it lands plus the follow-on bundles, since this task sits in the
last wave and "later units" of this bundle would name almost none.)*

*(Amended at sign-off lens pass 2026-10-24: the fixture list replaced by the
decided rule "one fixture per Gherkin arm", since seven arms named fixtures
the list lacked; the annotation moved below the task's fields.)*

### Task 16 — Compaction and handover

- **Deliverables:** The handover file (last ledger sequence, open items,
  live sessions) and `scripts/mc-handover.sh` verbs to write it, launch the
  successor through the launcher, verify the successor's self-check against
  it, transfer the program name and retire the predecessor; the trigger
  (measured context percent, step count fallback, compaction ceiling) as
  knobs; the research record on unattended name takeover and the one-act
  panel fallback; the resume-by-name flow (rebuild, what changed, announce,
  retire predecessor).
- **Done when:** A fixture handover produces a successor whose self-check
  matches the file, the name resolves to the successor only, and the
  predecessor's registry row is gone; a failed self-check keeps the
  predecessor live and raises an item; resume by name on a fixture program
  announces itself to every live session and reports what changed; a
  launch with neither the operator's ask nor a live handover refuses naming
  the holder; the research record states which takeover path the harness
  supports; the handover file carries its `format` field and a successor
  refuses a file whose format it does not know; a fixture predecessor that
  cannot release within the window is retired by the successor.
- **Dependencies:** 2, 3, 7, 8
- **Citations:** D-29, D-30 · REQ-A1.1, REQ-A1.7, REQ-B1.3, REQ-B1.7,
  REQ-L1.3, REQ-L1.5, REQ-L1.6
- **Estimated effort:** 3 days

## Awaiting input

- **Task 5** — pending ready-flip: review-converged failed on f8c964f89099
- **Task 7** — pending ready-flip: ci-rollup failed on 72eefc8197df
- **Task 3** — PR #751 parked before its ready flip: cubic converged with 0
  issues and CI is green on 9d7cfe05, but the PR conflicts with main in
  `.gitleaksignore` (the same fixture entry landed through #752 with a
  different comment line). Clearing it means merging main, which the ruling
  keeps out of the flip path; after a merge, the fresh convergence pass and
  the flip run on the new head.

## Deferred

(none yet)

## Out of scope

- The review desk, spec currency, the environment broker, the night shift
  and the state-source adapters as duties in this bundle: follow-on bundles
  seeded by Task 14.
- A web or GUI dashboard beyond the in-app panel.
- Cross-machine mission control.
