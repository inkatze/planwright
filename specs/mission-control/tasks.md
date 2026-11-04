# Mission control — Tasks

**Status:** Draft
**Last reviewed:** 2026-11-04
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

### Task 17 — The cadence audit at readiness

- **Deliverables:** A read-only `audit --through <point> [--head <sha>]`
  verb in `scripts/step-run.sh` that resolves the configured cadence
  through the in-run points and reports per point `covered` or a `gap`
  (incomplete, stale, missing, failed) and a final `audit complete|gaps`
  line, exit 0, 1 or 4; `scripts/mc-readiness.sh` collecting a `cadence`
  evidence row (audited at a head, a gap, or unaudited with its reason)
  from the worktree holding the pull request's branch, and its walk
  refusing any gap, an audit at another head, or no audit; tests for both.
- **Done when:** A fixture whose configured convergence step has no record
  is refused by the walk naming the point and step, whatever the
  gate-condition data names; a fixture with every step recorded and each
  point completed at the head passes; a completion on an older head with a
  non-merge commit after it reports stale; with no worktree holding the
  branch the row reads unaudited and the walk refuses; an unresolvable
  cadence exits 4.
- **Dependencies:** none
- **Citations:** D-33, D-25 · REQ-D1.9, REQ-D1.8
- **Estimated effort:** 1 day

### Task 18 — Launch worktrees and cadence briefs

- **Deliverables:** `scripts/mission-control-launch.sh` creating a worktree
  for every kind that changes a repository (off the default branch, or the
  unit's branch when it exists), starting the session there, refusing an
  explicit directory that is a primary checkout, and keeping the caller's
  directory for read-only kinds; the resolved cadence written into the
  brief of each repository-changing launch; the skill's kickoff relay
  pointed at the launcher's worktree; tests.
- **Done when:** A fixture worker launch with no directory starts in a new
  worktree off the default branch and the primary checkout is untouched; a
  launch naming the primary checkout is refused; a read-only kind starts
  in the caller's directory; the brief of a repository-changing launch
  lists the steps the configuration resolves for its points, and an empty
  cadence says so.
- **Dependencies:** none
- **Citations:** D-33, D-34 · REQ-D1.10, REQ-D1.11
- **Estimated effort:** 1 day

### Task 19 — The kickoff permission profile

- **Deliverables:** A kickoff launch kind and settings profile: the worker
  profile plus a plain push of the spec branch its scope names and the
  draft pull request for it; `scripts/policy-guard.sh` reading the
  permitted branch from the launch record and keeping the protected floor
  for every other spec branch; the skill's relay using the kind; tests.
- **Done when:** A fixture kickoff session pushes its own spec branch
  without a prompt; a push of another spec branch, a force push of its own,
  and a push to `main` are each denied with the guard's text; a worker
  launch keeps the floor for every spec branch; mission control's own
  profile still denies every push.
- **Dependencies:** 18
- **Citations:** D-36 · REQ-I1.8, REQ-I1.5, REQ-I1.4
- **Estimated effort:** 1 day

### Task 20 — The posture check and the guard-enforced invariants

- **Deliverables:** The skill's bring-up opening with the tower's posture
  check by reference, a failed check reported in one plain line with
  mission control continuing read-only; the `mission-control` guard tier
  denying repository edits and git mutations and holding the ready-flip
  policy; its allow list read from one shared list covering every
  planwright script mission control runs routinely, with a test that fails
  when a routine script is missing from it.
- **Done when:** A fixture session without the shipped deny floor reports
  the posture failure and refuses a launch; a fixture edit or git mutation
  from mission control is denied by the tier; every script the skill and
  its duties name as routine runs without a prompt; adding a routine script
  without listing it fails the test.
- **Dependencies:** none
- **Citations:** D-32 · REQ-G1.5, REQ-A1.3, REQ-I1.2
- **Estimated effort:** 1 day

### Task 21 — Adoption, liveness on every backend, and prompt answers

- **Deliverables:** An `adopt` verb registering a live session mission
  control did not launch; `scripts/mc-stall.sh` reading every registered
  session and a stream-json session's liveness from its process and event
  stream; a pending prompt raising an attention event that wakes mission
  control; an answer wrapper that checks the tower-comms standing-decision
  coverage before calling the backend's answer verb, pre-approved by the
  guard tier while the raw answer verb is not; the tmux arm surfacing the
  prompt once and recommending a relaunch; tests.
- **Done when:** A fixture hand-launched stream-json worker, once adopted,
  is reported dead when its process exits and stalled on a pending prompt;
  the prompt wakes mission control through the attention store; a prompt a
  standing decision covers is answered, one it does not cover is surfaced
  once and left pending; the raw answer verb prompts in the mission-control
  tier; a tmux prompt is surfaced once with its command.
- **Dependencies:** 20
- **Citations:** D-35 · REQ-D1.12, REQ-G1.6, REQ-G1.2, REQ-D1.3
- **Estimated effort:** 2 days

### Task 22 — Takeover from a tower

- **Deliverables:** A tower takeover path in `scripts/mc-handover.sh`:
  adopt each live session the tower supervises, import its open operator
  items with their origin, start the fleet sweep's relaunch and reap work
  under mission control's supervision, and ask before retiring the tower;
  the wake marker mission control's relayed wakes carry and the tower reply
  hook ignoring a turn that bears it; tests.
- **Done when:** A fixture tower with two live workers and an open item
  hands over: both workers are adopted, the item is in mission control's
  queue with its origin, the sweep's relaunch runs for a crashed fixture
  worker, and the tower is untouched until a yes; a relayed wake into a
  tower session leaves the tower's attention marker unwritten.
- **Dependencies:** 21
- **Citations:** D-38 · REQ-A1.8, REQ-F1.5
- **Estimated effort:** 2 days

### Task 23 — The panel with no setup

- **Deliverables:** An activation record written by mission control's entry
  and bring-up for the current session; the panel mod activating from a
  record naming its own session on its timer and session events, the
  environment variable kept as an optional fast path; the skill's one-line
  notice and text-panel fallback where mods cannot load; tests through
  `claude plugin test` and the panel script.
- **Done when:** A fixture session with no mission-control environment
  activates the panel after the record is written; a session launched from
  it does not activate; a handover successor activates through its own
  bring-up; with mods unavailable the notice appears once and the text
  panel renders.
- **Dependencies:** none
- **Citations:** D-37 · REQ-F1.16, REQ-F1.2
- **Estimated effort:** 1 day

### Task 24 — Review evidence at consequential moments

- **Deliverables:** The prepared packet opening with the review-evidence
  line from the cadence audit at the merge and ready-flip moments; a lesson catalog keyed by moment and guidance level merged
  through the overlay layers, with shipped `guided` and `standard` texts;
  the skill naming the rule once; tests.
- **Done when:** For a fixture pull request with convergence missing, the
  packet at every level names the missing step; at `guided` it adds the
  lesson and the recommendation, at `standard` the recommendation alone,
  at `expert` neither; no level changes the gate result or pre-selects an
  option; an overlay lesson replaces the shipped text.
- **Dependencies:** 17
- **Citations:** D-31, D-18, D-25 · REQ-F1.15, REQ-F1.13, REQ-F1.14
- **Estimated effort:** 1 day

### Task 25 — The platform fact class

- **Deliverables:** `platform` added to the fact classes in
  `scripts/mc-program.sh`, admitting only `snapshot` and `cited` and
  defaulting to `cited`; the first run's state-source objective and the
  operator guide naming it; tests.
- **Done when:** A program block mapping `platform` to a snapshot source
  validates; one mapping it to `record` is refused naming the class; a map
  leaving it out resolves it `cited`; the class list stays the one the
  validator and the reader share.
- **Dependencies:** none
- **Citations:** D-39 · REQ-H1.5
- **Estimated effort:** half day

### Task 26 — Armed duties

- **Deliverables:** Catalog entries with watchers and schedules for the
  duties whose scripts exist (the undo ledger, self-audit, proposals),
  `config/duties.yaml` and the operator guide agreeing on which are
  available; `scripts/mc-duties.sh` restoring the shadowed entry when an
  invalid overlay entry that supersedes it is skipped; tests.
- **Done when:** Enabling each of those duties arms its watcher in a
  fixture installation; the guide presents no duty that ships unarmed
  without saying it is not yet available; an invalid superseding overlay
  entry leaves the shipped entry armed.
- **Dependencies:** none
- **Citations:** D-40 · REQ-C1.8, REQ-C1.4
- **Estimated effort:** 1 day

### Task 27 — Step deadlines, measures and dispatch suggestions

- **Deliverables:** A deadline knob for watcher runs and snapshot refreshes
  with the runner stopping an expired step and emitting the expiry as an
  event; the calibration work writing the measures file in the shape the
  panel reads; `scripts/mc-keeper.sh next` taking its suggestions from the
  orchestrator's selection; tests and the options-reference row.
- **Done when:** A fixture watcher that hangs is stopped at the deadline,
  the pass completes and the expiry is an event; the panel shows
  interruptions per hour and the settled share from a fixture measures
  file the calibration work wrote; a task whose dependency's repository is
  withheld is not suggested.
- **Dependencies:** none
- **Citations:** D-40 · REQ-E1.6, REQ-M1.8, REQ-M1.9
- **Estimated effort:** 1 day

### Task 28 — Dynamic, host-shared launch admission

- **Deliverables:** Admission before every launch reading the account's
  usage headroom and the host's capacity (load against cores, available
  memory), capped by `fleet_max_parallel_units`; the admission state in a
  host-level store under a lock that every program's mission control reads
  and writes; the panel and the budget showing which axis holds a launch;
  tests and the options-reference rows.
- **Done when:** A fixture with account headroom and a host loaded past its
  limit holds the launch naming the host axis, and the reverse names the
  account axis; two fixture programs on one host never admit more than the
  shared capacity together; the ceiling caps a host with room to spare.
- **Dependencies:** none
- **Citations:** D-41, D-17 · REQ-L1.7, REQ-L1.2, REQ-M1.6
- **Estimated effort:** 2 days

### Task 29 — Skill, guide and eval fixtures for the extension

- **Deliverables:** The skill's prose for the posture check, adoption and
  takeover, the kickoff kind, the activation record and the
  consequential-moment rule, inside the instruction budget (D-21); the
  operator guide's sections for each; behavioral eval fixtures for the
  review-evidence line at each guidance level, a takeover and a relayed
  kickoff that publishes, under Task 15's cadence step.
- **Done when:** The instruction-budget check passes; the guide describes
  each new behaviour and names no duty or knob the catalog or options
  reference lacks; each new fixture passes under the eval harness and is
  recorded by the cadence step.
- **Dependencies:** 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28
- **Citations:** D-21, D-31, D-32, D-35, D-36, D-37, D-38 · REQ-A1.6,
  REQ-A1.8, REQ-F1.15, REQ-F1.16, REQ-G1.5, REQ-I1.8
- **Estimated effort:** 2 days

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

- The review desk, spec currency, the environment broker, the night shift
  and the state-source adapters as duties in this bundle: follow-on bundles
  seeded by Task 14.
- A web or GUI dashboard beyond the in-app panel.
- Cross-machine mission control.
