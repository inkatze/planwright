# Mission control — Tasks

**Status:** Draft
**Last reviewed:** 2026-10-22
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
  enabled duties, budget) read through the config resolver; every
  `mission_control_*` knob this bundle names in `config/defaults.yml` with
  its options-reference row and its evidence; a `check:duties` script
  validating catalog entries and enabled lists, wired into `mise run check`.
- **Done when:** A fixture overlay adds a custom duty and supersedes a
  shipped one and the merged view shows both; an invalid entry fails
  `check:duties` with the field named; every new knob has an
  options-reference row and the reference check passes; a disabled duty
  resolves to no watchers and no files.
- **Dependencies:** none
- **Citations:** D-3, D-8, D-20 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4,
  REQ-H1.1, REQ-J1.1, REQ-J1.2
- **Estimated effort:** 2 days

### Task 2 — The rule store

- **Deliverables:** `rules.yaml` in the program home and
  `scripts/mc-rules.sh` with `add`, `supersede`, `list`, `active` and
  `render` verbs (entries carry text, source, date, scope, supersedes; the
  active set excludes superseded entries; one writer under a lock); the
  render shape the launcher embeds in briefs; the bring-up load and the
  post-compaction self-check the skill runs; a conflicting-active-rules
  report for the self-audit.
- **Done when:** Superseding an entry removes it from `active` and keeps it
  in `list`; `render --scope <duty|repo>` emits only in-scope rules; two
  active rules on one subject are reported; a fixture brief contains the
  rendered rules.
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
  scope; a `retire` verb that exits, closes the pane and clears the registry
  and attention rows, reporting any part not released; the never-hand-the-
  operator-a-pane rule in the skill's relay step.
- **Done when:** Each kind launches from a fixture with the brief, rules
  and profile present in the launched session's inputs and a registry row
  with owner and kind; `retire` on a finished fixture session leaves no
  row and no pane, and a partial release is reported as partial; a launch
  without a profile is refused.
- **Dependencies:** 1, 2
- **Citations:** D-10, D-23 · REQ-A1.4, REQ-D1.1, REQ-D1.5, REQ-G1.1,
  REQ-M1.7
- **Estimated effort:** 3 days

### Task 4 — Liveness and stall states for every session kind

- **Deliverables:** The stuck detector extended with positively named
  states for every kind (dead, open selector, unsubmitted prompt, turn
  ended with background work, idle with a question, busy unchanged past the
  stall window), each emitting an attention event; liveness from the
  registry pid and process state only; the worktree reclaim predicate
  (no live user, PR landed or closed, nothing uncommitted or unpushed,
  ignored audit files verifiably backed up) as a script; the routed
  fleet-lifecycle-closure amendment note for the new resource classes.
- **Done when:** Each state is produced from a fixture and no state is
  inferred from elapsed time alone; a reclaim with a failed backup is
  refused and says why; the amendment note names the resource classes and
  cites this task.
- **Dependencies:** 3
- **Citations:** D-11, D-22 · REQ-D1.2, REQ-D1.3, REQ-D1.6
- **Estimated effort:** 2 days

### Task 5 — Watcher runner, forge snapshot and budget

- **Deliverables:** `scripts/mc-watch.sh`, a runner under the fleet daemon
  gate that arms every enabled duty's watchers at their cadence, re-arms
  one that stopped and emits a watcher-stopped event; `scripts/mc-snapshot.sh`
  refreshing one age-stamped program snapshot (heads, drafts, mergeability,
  review decision, open threads, checks, reviews, comments, patch id per
  PR) with rate-limit backoff; the per-program budget file (sessions, polls
  per hour, spend class per duty, context steps, host load) and
  `scripts/mc-budget.sh` reporting headroom and the degradation rung; the
  daemon-side failsafe tick.
- **Done when:** A killed watcher is re-armed within one runner pass and
  the stop is an event; two duties reading the snapshot cause one forge
  read per cadence; a snapshot older than its cadence reports its age; the
  budget script reports each rung from fixtures and honours the daemon
  pause; no runner step calls a model.
- **Dependencies:** 1
- **Citations:** D-4, D-12, D-17 · REQ-C1.5, REQ-E1.1, REQ-E1.2, REQ-E1.3,
  REQ-E1.5, REQ-L1.1, REQ-L1.2, REQ-L1.4, REQ-M1.1, REQ-M1.6
- **Estimated effort:** 3 days

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
  compactions since start and knowledge-base freshness, read from the
  stores on a timer; presence fed to the queue from prompt events; the
  failsafe tick from the timer submitting a prompt only when due and idle;
  context percent and rate limits from the session usage call; the
  post-compaction rule re-injection hook; the handover trigger at the knob
  threshold; light aviation theming and animation within the redraw
  throttle; a text fallback where nothing draws; `claude plugin test`
  tests for every surface and the fallback.
- **Done when:** Tests draw the pane on each surface from fixture stores,
  show the fallback where no surface draws, fire the tick at the cadence
  without a turn when nothing is due, submit the tick prompt when due and
  idle, re-inject rules on the compaction hook, and raise the handover at
  the threshold; `claude plugin validate` lists only the calls the design
  names.
- **Dependencies:** 2, 5
- **Citations:** D-6, D-29 · REQ-E1.4, REQ-F1.1, REQ-F1.2, REQ-L1.4,
  REQ-L1.5, REQ-M1.8
- **Estimated effort:** 4 days

### Task 8 — Knowledge base, ledgers and undo

- **Deliverables:** The program-home layout (`kb/index.md`, per-duty
  subdirectories, `decisions.log`, `undo.log`, the follow-up ledger, the
  living-versus-consumed source table) with `scripts/mc-kb.sh` verbs to
  index, read within the entry cap, append a decision or an undo entry with
  its reversal, query a log by subject, and claim a file's write lock; the
  loading rules and caps as knobs; freshness reported for the panel.
- **Done when:** A read above the cap is refused with the offload hint; an
  append under a held lock waits or fails, never interleaves; a decision and
  its undo entry round-trip and the reversal command runs from the entry;
  the index stays within its line budget or reports the overflow.
- **Dependencies:** 1
- **Citations:** D-9, D-24 · REQ-D1.7, REQ-F1.10, REQ-K1.1, REQ-K1.2,
  REQ-K1.3, REQ-K1.4, REQ-K1.5, REQ-K1.6
- **Estimated effort:** 2 days

### Task 9 — Autonomy, calibration, proposals, shadow mode and self-audit

- **Deliverables:** The decided-by-mission-control record and the reasons
  grammar; the calibration ledger (a revoked class drops to ask-first until
  a configured run of confirmations); the repeat detector over the decisions
  log and asks with threshold and window knobs; the proposal record for
  duties and rules in the confirmation shape (noticed, plan, cadence,
  intervention points, cost, off switch, explicit decline), accepted,
  declined and parked outcomes; the `shadow` lifecycle with would-have
  entries and the promotion suggestion; the self-audit duty script
  comparing logs with active rules; the interruption and settled-share
  measures.
- **Done when:** Fixtures show a revoke lowering a class and confirmations
  restoring it; a repeat at the threshold yields exactly one proposal and a
  declined one is not re-proposed on the same pattern; a shadow duty writes
  would-have entries and raises nothing; the audit flags an act against a
  rule and two active rules on one subject; the measures compute from the
  logs.
- **Dependencies:** 8
- **Citations:** D-13, D-14, D-15, D-16 · REQ-B1.5, REQ-B1.6, REQ-C1.6,
  REQ-C1.7, REQ-F1.8, REQ-F1.9, REQ-M1.8
- **Estimated effort:** 3 days

### Task 10 — The default duties

- **Deliverables:** Catalog entries and scripts for session-keeper (drive
  to done, retire on landing, reclaim), inbox (status form, item shape,
  voice drafts to the clipboard, prepared packets), readiness-check (the
  primary-evidence walk over the gate-condition data, composing the
  ready-flip guards, screenshots opened and judged), the gate-condition data
  format per program, repository, label and path bounded by the gate
  policies, conflict-radar (same-file and same-line prediction across the
  program's branches, merge order and stack retargets from the whole
  graph), deadline-watch (date and calendar sources driving priority and
  the first turn after silence), prepared-moments; pipelining of the next
  ready unit while others wait.
- **Done when:** Each duty resolves from the catalog and its watchers arm
  under the runner; the readiness walk refuses a fixture with a missing
  step, a red individual check, an open thread, an unanswered finding or an
  error-state screenshot and passes a complete one; a gate condition that
  would authorize a merge is refused at load; the radar flags a same-line
  overlap from two fixture branches and computes merge order from the
  graph; a packet is assembled from fixtures with the readiness result
  first; the next ready unit dispatches while a fixture unit waits on CI.
- **Dependencies:** 3, 5, 9
- **Citations:** D-25, D-26, D-27 · REQ-D1.4, REQ-D1.8, REQ-F1.3,
  REQ-F1.7, REQ-F1.11, REQ-F1.14, REQ-I1.7, REQ-M1.3, REQ-M1.4, REQ-M1.5
- **Estimated effort:** 4 days

### Task 11 — The skill

- **Deliverables:** `skills/mission-control/SKILL.md`: bring-up from
  durable evidence, the one-live-session rule, the guided first run with
  the guidance knob, the register, the contract by reference to the tower
  with the lifted limits stated, the duty catalog on request, the relay and
  denial rules, the invariants; the doctrine manifest; `/tower` gains a
  one-line pointer to mission control; `check-instructions.sh` green for the
  skill and its closure.
- **Done when:** The skill resolves its doctrine at run start; a fresh
  installation enters the guided first run and ends with a program block,
  a knowledge-base skeleton and enabled duties written; the instruction
  budget check passes in CI; the behavioral fixtures of Task 15 have a
  skill to run against.
- **Dependencies:** 2, 3, 5, 6, 7, 8, 9, 16
- **Citations:** D-1, D-2, D-18, D-19, D-21, D-23 · REQ-A1.1, REQ-A1.2,
  REQ-A1.3, REQ-A1.5, REQ-A1.6, REQ-F1.12, REQ-F1.13, REQ-G1.3, REQ-G1.4,
  REQ-I1.1, REQ-I1.2, REQ-I1.3, REQ-I1.4, REQ-I1.5, REQ-I1.6
- **Estimated effort:** 3 days

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
  entries (mission control, program, duty, rule store), `docs/mission-control.md`
  for operators (first run, duties, knobs, resume, handover), README and
  doctrine index rows.
- **Done when:** The doctrine index check passes; every concept the skill
  names resolves to the doc; the operator doc walks a fresh installation
  end to end without a planwright term the register forbids.
- **Dependencies:** 11
- **Citations:** D-1, D-19 · REQ-A1.6
- **Estimated effort:** 2 days

### Task 14 — Pending notes for the follow-on bundles

- **Deliverables:** `_pending/review-desk.md`, `_pending/spec-currency.md`,
  `_pending/environment-broker.md` and `_pending/night-shift.md`, each
  naming the duty's shape from the seed, the observation uids left live for
  it, the seams it consumes here (the duty catalog, the launcher, the
  snapshot, the queue) and the suggested invocation; the observation
  routing recorded so the next drafting consumes them.
- **Done when:** Each note exists, cites only live fragments, and names
  this bundle's decisions it builds on; no fragment named is archived.
- **Dependencies:** none
- **Citations:** D-22, D-27
- **Estimated effort:** half day

### Task 15 — Behavioral eval fixtures and CI wiring

- **Deliverables:** Fixtures for the register (no forbidden vocabulary in
  delivered items), turn density, picklist shape (self-contained, explicit
  decline, no pre-selection), proposal shape, the guided first run and the
  first turn after silence, run under the behavioral-eval harness; CI
  wiring for `check:duties`, the options-reference rows, the plugin tests
  and the instruction budget.
- **Done when:** The fixtures run in CI against the skill and fail on a
  seeded violation of each rule; a red fixture blocks the merge of this
  bundle's later tasks.
- **Dependencies:** 11
- **Citations:** D-19, D-21 · REQ-F1.7, REQ-F1.12
- **Estimated effort:** 2 days

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
  announces itself to every live session and reports what changed; the
  research record states which takeover path the harness supports.
- **Dependencies:** 2, 3, 7
- **Citations:** D-29, D-30 · REQ-A1.1, REQ-A1.7, REQ-B1.3, REQ-B1.7,
  REQ-L1.3, REQ-L1.5, REQ-L1.6
- **Estimated effort:** 3 days

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

- The review desk, spec currency, the environment broker and the night
  shift as duties in this bundle: follow-on bundles seeded by Task 14.
- A web or GUI dashboard beyond the in-app panel.
- Cross-machine mission control.
