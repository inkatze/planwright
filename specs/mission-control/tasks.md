# Mission control — Tasks

**Status:** Ready
**Last reviewed:** 2026-11-10
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
  verb in `scripts/step-run.sh` printing per point `covered` or a `gap`
  (incomplete, stale, missing, failed) and a final `audit complete` or
  `audit gaps` line, exit 0, 1 or 4; `scripts/mc-readiness.sh` collecting a
  `cadence` evidence row (audited at a head, a gap, or unaudited with its
  reason) by auditing `--through post-pr` at the forge's pull-request head
  in the worktree holding the branch, and its walk refusing any gap, an
  audit at another head, a worktree head that differs from the forge's, or
  no audit; a pull request no planwright launch registered reading
  unaudited (not planwright-run); the cadence-steps doctrine note telling
  the configured cadence apart from a cadence step;
  `tests/test-step-run-audit.sh` and cases in `tests/test-mc-readiness.sh`.
- **Done when:** A fully recorded fixture prints `covered` per point and
  `audit complete`, exit 0, and its readiness walk does not refuse on the
  cadence; a configured step with no record, one with only failed records,
  and a point with no completion each print their gap with `audit gaps`,
  exit 1, and the walk refuses naming the point and step, with the shipped
  empty gate-condition data and with data naming a different step; a
  last-point completion followed by a non-merge commit reports stale, one
  followed only by merge commits counts, and an earlier point completed on
  an ancestor counts; `--head <sha>` judges against that commit; a steps
  configuration the resolver rejects exits 4 with no `audit complete`
  line; a cadence row audited at another head, a worktree head that differs
  from the forge's, and a branch no worktree holds each refuse the walk.
- **Dependencies:** none
- **Citations:** D-33, D-25 · REQ-D1.9, REQ-D1.8
- **Estimated effort:** 1 day

### Task 18 — Launch worktrees and cadence briefs

- **Deliverables:** `scripts/mission-control-launch.sh` starting the
  worker, reviewer, ad-hoc and kickoff kinds in a worktree created through
  `scripts/fleet-dispatch-worktree.sh` (on the unit's branch when it
  exists, otherwise off the default branch; reusing a worktree that holds
  the branch only when no live session runs there), accepting an explicit
  directory only when it is a worktree other than a primary checkout that
  no live session uses, refusing a launch whose worktree cannot be created,
  and starting the other kinds where launched; a cadence section in every
  repository-changing brief that is not a skill command, naming the
  procedure that resolves and records the steps and the audit command; the
  skill's kickoff relay launching with no explicit directory; tests in
  `tests/test-mission-control-launch.sh`.
- **Done when:** A fixture worker launch with no directory starts in a new
  worktree off the default branch, and the primary checkout's HEAD, branch
  and `git status --porcelain` are unchanged; a launch for a unit whose
  branch exists starts on that branch; a worktree already holding the branch
  with a live session refuses naming it, and one with none is reused; a
  launch naming the primary checkout, and one whose worktree creation
  fails, each exit non-zero with no session started and no registry row; a
  launch naming another unused worktree starts there; a tower kind starts
  in the caller's directory; a repository-changing brief carries the
  cadence section with the audit command, and a brief that is a skill
  command carries none; the skill's kickoff relay passes no directory
  (fixed-string check).
- **Dependencies:** none
- **Citations:** D-33, D-34 · REQ-D1.10, REQ-D1.11
- **Estimated effort:** 1 day

### Task 19 — The kickoff permission profile

- **Deliverables:** A kickoff launch kind and its settings profile (the
  worker profile's rules without the spec-branch push denies); the launch
  record naming the permitted branch written before the session starts,
  outside every path the worker profile may write; `scripts/policy-guard.sh`
  admitting from that record only a plain push of that branch, its draft
  pull request and its configured ready flip, targeting the spec root's
  repository by posture and nothing under `plain`; the skill's kickoff relay
  using the kind; cases in `tests/test-policy-guard-mission-control.sh` and
  `tests/test-permission-matcher.sh`; the profiles' descriptions updated.
- **Done when:** A fixture kickoff session pushes its own spec branch and
  opens its draft pull request without a prompt, and its configured ready
  flip passes the guard; `--force`, `--force-with-lease`, a `+` refspec, a
  deletion (`--delete` and `:<branch>`), a push of another spec branch, of a
  task branch and of `main` are each denied with the guard's reason line; a
  kickoff session with no launch record, or a record naming no branch, is
  denied every push; a worker-tier push to a fixture spec branch gets the
  same decision as before; under the mission-control tier a push of the
  kickoff's branch is denied; the skill's relay names the kickoff kind
  (fixed-string check).
- **Dependencies:** 18, 31
- **Citations:** D-36 · REQ-I1.8, REQ-I1.4
- **Estimated effort:** 1 day

*(Amended at Amendment 4, 2026-11-07: the push half landed in PR #866, a
flight with no task trailer, so the status render cannot see it: the policy
guard admits a session whose launch scope is `kickoff-<spec>` to run only
`scripts/kickoff-spec-push.sh`, a plain push of that spec's own branch.
`tests/test-policy-guard.sh` and `tests/test-kickoff-spec-push.sh` prove
the push of its own branch, the refusals of another branch, of `main` and
of a forced push, and the raw push denied. Admission is by the launch
scope, not yet a launch record. What remains is the draft pull request
and the configured ready flip without a prompt, the launch-record admission
with its no-record and no-branch denials, the mission-control-tier deny of
the kickoff's branch, the worker-tier parity case and the relay's
fixed-string check.)*

### Task 20 — The posture check and one pre-approval list

- **Deliverables:** A posture script reading each loaded settings layer by
  projection, with `config/mission-control-settings.json` as the floor and
  an unwired guard hook counted as a failure, run by the skill at bring-up
  and on the failsafe tick and read by the launcher before a launch; the
  `mission-control` guard tier's pre-approvals drawn from one core-only list
  of script verbs derived from the scripts the skill and
  `config/duties.yaml` invoke, excluding `fleet-streamjson.sh answer`, in
  place of the hand-kept string; tests.
- **Done when:** A fixture settings set without the shipped deny floor, and
  one whose guard hooks are not wired, each fail the posture script with a
  one-line reason, and the launcher refuses a launch on that result; a
  passing set lets the launch through; every script verb the skill and the
  duty catalog invoke appears in the list and runs without a prompt at the
  tier, and a fixture reference to an unlisted script fails the test;
  `fleet-streamjson.sh answer` prompts at the tier; an edit and a git
  mutation are each still denied; `gh pr ready` at the tier asks under
  `ready_flip_policy: human`.
- **Dependencies:** none
- **Citations:** D-32 · REQ-G1.5, REQ-A1.3, REQ-I1.2
- **Estimated effort:** 1 day

### Task 21 — Adoption, liveness on every backend, and prompt answers

- **Deliverables:** The launcher's `adopt` verb (handle, kind, scope,
  optional owner; adopted origin; refusals for no resolvable pid and for
  another live supervisor); `scripts/mc-stall.sh` reading every registered
  session, each backend's pid from the registry or the backend's record,
  and a stream-json session's event stream for its stall state; a pending
  prompt raising an attention event keyed by session and prompt id that
  wakes mission control; answers through `fleet-attention.sh claim` or with
  the operator's own answer, each an undo-ledger entry; the tmux arm
  surfacing the prompt once and delivering only an operator answer by the
  pane relay; retirement of an operator-owned adopted session raised as a
  confirmation item; cases in `tests/test-mc-stall.sh` and
  `tests/test-mission-control-launch.sh`.
- **Done when:** Adopting a dead pid or an unknown handle is refused with
  nothing registered, and adopting a session another live supervisor holds
  is refused naming it; an adopted stream-json worker's row carries owner,
  kind, scope, handle and the adopted origin; it is reported dead when its
  process exits and in the prompt-pending stall state on a pending prompt;
  an adopted tmux session's liveness comes from its process; a registry row
  with no live process is never read as live; the pending prompt writes one
  attention event, still one after two stall passes, which clears when the
  prompt is answered elsewhere; a prompt a standing decision covers is
  answered through the claim channel and one it does not cover stays
  pending until an operator answer is given, which is then delivered; each
  answer appends an undo-ledger entry; a tmux prompt is surfaced once with
  its command; retiring an operator-owned adopted session raises a
  confirmation item instead of retiring it.
- **Dependencies:** 20
- **Citations:** D-35 · REQ-D1.12, REQ-G1.6, REQ-G1.2
- **Estimated effort:** 2 days

### Task 22 — Tower handover

- **Deliverables:** A tower handover path in `scripts/mc-handover.sh`:
  adopt each live session the tower dispatched or its sweep tracks, writing
  mission control as supervisor; import the open entries of the tower's
  attention store by origin id and settle the tower's copies with a
  carried-over reason; run the fleet sweep for adopted flights under mission
  control's identity, recording each relaunch against the dead row; ask
  before retiring the tower and release the adopted sessions on a no;
  resume a partial run without duplicating; the fleet sweep and answer
  paths skipping a session another supervisor holds; the wake marker
  constant mission control's relayed wakes carry; tests in
  `tests/test-mc-handover.sh`.
- **Done when:** A fixture tower with two live workers and several open
  items hands over: both workers' rows name mission control as supervisor,
  every item is in mission control's queue with its origin and settled on
  the tower's side, the tower's sweep no longer acts on the adopted
  workers, a crashed adopted flight is relaunched once (a second pass is a
  no-op), and the tower's process and row stay live with no message to it
  until a recorded yes, after which it is retired; a recorded no releases
  both workers; a run killed after one adoption resumes to adopt the other
  without duplicate items; a relayed wake carries the marker.
- **Dependencies:** 21, 32
- **Citations:** D-38 · REQ-A1.8, REQ-F1.5
- **Estimated effort:** 2 days

### Task 23 — The panel with no setup

- **Deliverables:** A `scripts/mc-panel.sh` verb writing the activation
  record (program, session id, written time, `format`) host-wide under the
  fleet home, called by the skill's entry and bring-up and by the handover
  successor; the session id captured from the session-start hook's input;
  the panel mod activating from the record naming its own session on its
  timer and session events, writing an acknowledgment, with the environment
  variable kept as a fast path; retirement removing the record and the
  keeper removing records with no live session; the text-form fallback the
  skill uses when no acknowledgment arrives within a bounded wait or the
  host is below the mods floor; the skill's entry taking a program the
  launch environment names as its argument; tests through `claude plugin
  test` and `tests/test-mc-panel.sh`.
- **Done when:** In a fixture session with no mission-control environment,
  the record verb's output activates the panel within one timer interval
  and an acknowledgment is written; a session launched from it, with a
  different session id, does not activate; with the variable set the panel
  activates without a record; a record with an unknown `format` does not
  activate; a handover successor's bring-up writes its own record;
  retiring the session removes its record, and the keeper removes a record
  whose session is dead; with no acknowledgment the fallback verb reports
  the text form and `scripts/mc-panel.sh` text output carries the in-flight
  and waiting lines; with two programs configured and the variable
  naming one, the entry resolves that program without asking.
- **Dependencies:** none
- **Citations:** D-37 · REQ-F1.16, REQ-F1.2, REQ-A1.7
- **Estimated effort:** 1 day

### Task 24 — The cadence result at consequential moments

- **Deliverables:** `scripts/mc-packet.sh` opening the readiness section
  with the cadence audit's line at the merge-recommendation, ready-flip and
  stated-merge-intent moments; core lesson data beside it keyed by those
  moments and by level, with `guided` and `standard` texts; the skill
  naming the rule once; `tests/test-mc-packet.sh`.
- **Done when:** For a fixture pull request with one step covered and
  convergence a gap, at each moment the readiness section's first line
  names both; the lesson appears only at `guided`, the recommendation at
  `guided` and `standard`, neither at `expert`; with no level configured
  the `guided` shape is used; an unaudited result names its reason and
  carries no lesson; a moment and level with no lesson text still prints
  the line; the gate result is identical at every level and no option
  carries a default marker; the rule appears once in the skill
  (fixed-string check).
- **Dependencies:** 17
- **Citations:** D-31, D-33, D-25 · REQ-F1.15, REQ-F1.13, REQ-F1.14
- **Estimated effort:** 1 day

### Task 25 — The platform fact class

- **Deliverables:** `platform` added to the one fact-class definition the
  validator and reader of `scripts/mc-program.sh` share, admitting only
  `snapshot` and `cited` and defaulting to `cited`; the
  `mission_control_default_sources` options-reference row, the first run's
  state-source objective, the operator guide, `doctrine/mission-control.md`
  and its `doctrine/README.md` row naming it with REQ-H1.5; tests in
  `tests/test-mc-program.sh`.
- **Done when:** A program block mapping `platform` to a snapshot source
  validates, explicit `cited` validates, `record` is refused naming the
  class, and a map leaving it out resolves it `cited`; a status line from a
  `cited` platform class says so; the options-reference row, guide and
  doctrine name `platform` (fixed-string checks).
- **Dependencies:** none
- **Citations:** D-39 · REQ-H1.5
- **Estimated effort:** half day

### Task 26 — Armed duties

- **Deliverables:** Catalog entries with watchers and schedules in
  `config/duties.yaml` for the duties whose scripts exist (the undo ledger,
  self-audit, proposals); `scripts/check-duties.sh` extended to fail when
  the operator guide or the first run presents a duty with no armed entry
  without the phrase "not yet available", with cases in
  `tests/test-check-duties.sh`; `scripts/mc-duties.sh` keeping the next
  lower layer's valid entry when an invalid overlay entry that supersedes
  it is skipped; tests in `tests/test-mc-duties.sh`.
- **Done when:** Enabling each of those duties arms its watcher in a
  fixture installation, and disabling each leaves no watcher, file or item;
  the guide check passes on the shipped files and fails on a fixture guide
  presenting an unarmed duty without the phrase; an invalid superseding
  adopter entry leaves the shipped entry armed, and an invalid
  machine-local entry over a valid adopter entry leaves the adopter entry.
- **Dependencies:** none
- **Citations:** D-40 · REQ-C1.8, REQ-C1.4
- **Estimated effort:** 1 day

### Task 27 — Step timeouts, measures and dispatch suggestions

- **Deliverables:** A `mission_control_*` timeout knob in seconds,
  overridable per watcher, with the runner stopping an expired watcher run
  or snapshot refresh, emitting the expiry as an event and re-arming on the
  next pass; the calibration ledger's writer producing the measures file in
  the shape `scripts/mc-panel.sh` reads; `scripts/mc-keeper.sh next` taking
  its suggestions from the orchestrator's selection; the knob's row in
  `docs/options-reference.md` and `config/mission-control-knobs.tsv`; tests.
- **Done when:** With the knob at a few seconds, a fixture watcher that
  hangs is stopped within one second of it, the pass's other watchers still
  run, an expiry event is written and the watcher runs again next pass; a
  hung snapshot refresh is stopped the same way; running calibration over
  fixture logs writes the measures file and the panel shows the expected
  interruptions per hour and settled share; for a fixture where a task's
  own or dependency's repository is withheld, `next` does not suggest it
  and equals the selection's output; the knob check passes.
- **Dependencies:** none
- **Citations:** D-40 · REQ-E1.6, REQ-M1.8, REQ-M1.9
- **Estimated effort:** 1 day

### Task 28 — Dynamic, host-shared launch admission

- **Deliverables:** Admission before every launch reading account headroom
  from the cached usage figures (a quota hold a hard stop) and host load
  and available memory against `mission_control_admit_*` threshold knobs,
  capped host-wide by `fleet_max_parallel_units`; a class-2 reservation
  store under the fleet home with one lock, a `format` field, recounts from
  every program's registry, warm-up counting, and reclaim of reservations
  whose holder is dead or timed out; a memory override for tests beside the
  existing load override; the held axis in the panel and budget output;
  options-reference and knob-inventory rows, the
  `fleet_max_parallel_units` row rewritten to its host-wide meaning; tests
  in `tests/test-mc-budget.sh`.
- **Done when:** With account headroom and load past its knob the launch
  holds naming the load axis, with memory below its knob it holds naming
  memory, and with headroom spent it holds naming the account axis; with
  capacity for two, four concurrent admissions from two fixture programs
  admit exactly two; a reservation whose holder pid is dead is reclaimed by
  the next admitter; an unreadable usage cache or a lock not taken in time
  holds the launch; a store with an unknown `format` is refused; the
  ceiling caps a host with room to spare; a program's own session bound
  still caps it beneath the shared total.
- **Dependencies:** none
- **Citations:** D-41, D-17 · REQ-L1.7, REQ-L1.2
- **Estimated effort:** 2 days

### Task 29 — Skill, guide and doctrine for the extension

- **Deliverables:** The skill's prose for the posture check, adoption and
  tower handover, the kickoff kind, the activation record, the cadence
  result at consequential moments and attended handover (beside the
  session, else one act, compaction last), inside the instruction budget
  (D-21); the operator guide's sections for each;
  `doctrine/mission-control.md` and its README row updated for D-33 to D-38
  and D-43.
- **Done when:** The instruction-budget check passes; the guide has a
  section for each of the posture check, adoption, tower handover, the
  kickoff kind, the panel activation, the cadence result and attended
  handover, and names no duty or knob the catalog or options reference
  lacks; the jargon check passes over the new skill and guide text; the
  doctrine index check passes.
- **Dependencies:** 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 33
- **Citations:** D-21, D-31, D-32, D-35, D-36, D-37, D-38, D-43 · REQ-A1.6,
  REQ-A1.8, REQ-F1.15, REQ-F1.16, REQ-G1.5, REQ-I1.8, REQ-L1.9
- **Estimated effort:** 2 days

### Task 30 — Attended sessions compact, launched holders hand over

- **Deliverables:** The holder record telling a launched holder from an
  attended session; `scripts/mc-handover.sh` raising its trigger, the
  panel's handover-due event and the one-act fallback only for a launched
  holder; for an attended session, the post-compaction step (rules
  re-injected, `scripts/mc-rules.sh selfcheck` against the durable stores)
  raising an operator item only on a failed check; tests in
  `tests/test-mc-handover.sh` and `tests/test-mc-panel.sh`.
- **Done when:** A fixture attended session past every handover trigger
  raises no handover act, no handover-due event and no item; after a
  fixture compaction its self-check passes silently, and a self-check with
  a rule missing raises one operator item; a fixture launched holder past
  its trigger still launches a successor as Task 16's fixtures describe.
- **Dependencies:** none
- **Citations:** D-42, D-29, D-30 · REQ-L1.8, REQ-L1.5, REQ-L1.6, REQ-B1.3,
  REQ-B1.7
- **Estimated effort:** 1 day

### Task 31 — Human-gates amendment for the relayed kickoff push (routed)

- **Deliverables:** A routed amendment of the `human-gates` bundle, through
  its own kickoff, admitting a relayed kickoff session launched with a
  kickoff profile as a writer of the one spec branch its launch record
  names (plain push, draft pull request, configured ready flip), with the
  core protected floor otherwise unchanged; the matching row in
  `doctrine/human-gates.md`.
- **Done when:** The `human-gates` amendment is signed off and merged, and
  its doctrine row names the relayed kickoff session's narrow write.
- **Dependencies:** none
- **Citations:** D-36, D-22 · REQ-I1.8
- **Estimated effort:** half day

### Task 32 — Tower-comms amendment: the reply hook ignores relayed wakes (routed)

- **Deliverables:** A routed amendment of the `tower-comms` bundle, through
  its own kickoff, having the tower's prompt-submit hook ignore a turn
  bearing mission control's wake marker, and the hook change with its test.
- **Done when:** The `tower-comms` amendment is signed off and merged; a
  fixture turn bearing the marker leaves the attention marker unwritten
  while an unmarked turn in the same fixture writes it.
- **Dependencies:** none
- **Citations:** D-38, D-22 · REQ-A1.8
- **Estimated effort:** half day

### Task 33 — Every session hands over; an attended one beside itself, compaction last

- **Deliverables:**
  - **The pane rung.** A `pane` backend in `scripts/mission-control-launch.sh` (launch, liveness and retire of a split pane, that pane only) with pane adapters for tmux (required) and kitty, WezTerm and Zellij (best-effort, stub-verified). Each adapter has a read-only, local, user-owned probe and an argument-vector command built from launcher-grammar values.
  - **The handover verbs.** In `scripts/mc-handover.sh`, `launch --handover` over a live attended holder is admitted through the first passing adapter, and exit 4 is kept only when none passes. The successor carries Remote Control only from its predecessor and runs the mission-control profile. `take` records an attended holder with a registry row, ends or closes the predecessor's pane, and closes an unverified successor's pane on the predecessor's side. The rung and adapter are recorded and a rung-1 fall is a panel event. `offer` is raised once per session. The `--help` text on holder kinds, `due`, `path`, `launch` and exit codes is updated to match.
  - **The mod.** The handover-due trigger and compaction deferral in `hooks/mission-control/` apply to attended sessions as D-43 describes.
  - **Defaults, docs and skill.** `mission_control_handover_context` ships at 40 in `config/defaults.yml`. The three `mission_control_handover_*` rows in `docs/options-reference.md` are restated for every session, citing D-43 and REQ-L1.9. The skill's handover prose is updated inside the instruction budget (D-21).
  - **Self-exit and tests.** Where the released-predecessor self-exit change (PR #874) has landed it is reused; otherwise it is built here. The stub tmux gains `split-window` and `kill-pane`, the handover runner can set `TMUX` and `TMUX_PANE`, and tests go in `tests/test-mc-handover.sh`, `tests/test-mc-panel.sh` and `hooks/mission-control/compaction.test.tsx`.
- **Done when:** Every `[test]` fixture of the REQ-L1.9 test-spec entry passes; `check:panel-mod`, the options-reference check and the instruction-budget check pass; the `[manual]` real-terminal runs are recorded or each untried adapter is named stub-verified only in the PR.
- **Dependencies:** none
- **Citations:** D-43, D-29, D-30, D-21 · REQ-L1.9, REQ-L1.5, REQ-L1.6,
  REQ-A1.4, REQ-B1.3, REQ-B1.7
- **Estimated effort:** 3 days

### Task 34 — Program goals and their done-when checks

- **Deliverables:** `scripts/mc-goals.sh` with verbs to set a goal with its
  drafted check and the work it tracks, attach more work, confirm or
  correct the check, run it, record a verification session's reported
  evidence and list goals with their state; the goal store in the program
  home, carrying a `format` field and written under one lock; a
  `goal-check` duty in `config/duties.yaml` that runs confirmed command
  checks when a goal's tracked work merges, daily and at bring-up, under
  D-40's watcher timeout; the read-only verification launch for a check
  with no command; tests in `tests/test-mc-goals.sh` and
  `tests/test-mc-duties.sh`.
- **Done when:** A fixture goal with an unconfirmed check lists as
  unconfirmed and never as done; a confirmed command check that exits 0
  marks the goal done with its evidence; one that exits non-zero, times out
  or has not run leaves a goal whose tracked pull requests merged reported
  as merged but not done, naming the failure, with one routed-fix item; a
  merge of work no goal tracks runs no check; a done goal whose daily or
  bring-up re-check fails reopens with one operator line while a passing
  re-check writes no item; a goal with no command launches one read-only
  session and is done only when the evidence that session reports says the
  outcome holds, and is not re-run on its own once done; a tracked pull
  request titled with `$(touch <sentinel>)` leaves no sentinel file after
  the check runs and its item and evidence are written, and the executed
  command equals the stored one byte for byte; two concurrent writes to
  the store serialize under the lock; a store with a missing or unknown
  `format` is refused and nothing is reported done; the store sits under
  the program home and nothing is written in a repository.
- **Dependencies:** none
- **Citations:** D-44, D-8 · REQ-N1.1, REQ-N1.2, REQ-N1.3, REQ-N1.4
- **Estimated effort:** 1.5 days

### Task 35 — Spec drift refused at readiness

- **Deliverables:** `scripts/spec-drift-check.sh`, which takes a base, a
  head and the pull request body and lists every changed file some spec
  names as a task deliverable (backticked paths in the deliverables
  `scripts/spec-model.sh` emits) whose spec's anchored content is unchanged
  and which no `Not covered:` line of the covering-spec statement names,
  skipping deliverables of a task the pull request's trailer names (D-45); in `scripts/mc-readiness.sh`, a row running the
  drift check, and the per-bundle sign-off row that spec-only pull requests
  already get (each touched bundle's anchor recomputed at the head)
  extended to every pull request that edits a bundle; tests in
  `tests/test-spec-drift-check.sh` and `tests/test-mc-readiness.sh`.
- **Done when:** A fixture pull request changing a listed deliverable with
  no spec edit and no reason is flagged and the readiness walk refuses it;
  the same change with a `Not covered:` line naming that path, or with the
  spec's anchored content edited and its anchor re-signed, passes; a
  `Not covered:` line naming another path does not excuse it; a change to
  the spec's status annotations alone does not count as an edit; a task
  pull request whose trailer names the task listing the file passes; a pull
  request with no statement is checked as covering nothing; a spec edit
  whose recorded anchor differs from the head's content refuses; a change
  touching no listed deliverable passes untouched; a deliverable path given
  in prose without backticks is not a listed file; a drift check that
  cannot run (no base, unreadable bundle) refuses with its reason.
- **Dependencies:** none
- **Citations:** D-45, D-25, D-33 · REQ-D1.13, REQ-D1.14
- **Estimated effort:** 1 day

### Task 36 — Tower-front-door amendment: the router list and the flight's spec edit (routed)

- **Deliverables:** A routed amendment of the `tower-front-door` bundle,
  through its own kickoff, carrying D-45's routing decisions: the shipped
  path list plus judgment for security, CI and guard work, the recorded
  override (an ask or a launch brief is not one), every flight pull request
  writing the covering-spec statement in D-45's form, a flight's
  same-pull-request spec edit, and `scripts/spec-drift-check.sh` fired at
  the flight's `pre-pr` point (the tower-front-door task that wires it
  depends on Task 35, which ships the script); the matching text in
  `doctrine/flight-rules.md`.
- **Done when:** The `tower-front-door` amendment is signed off and merged,
  and `doctrine/flight-rules.md` names the path list, the recorded override
  and the flight's spec edit.
- **Dependencies:** none
- **Citations:** D-45, D-22 · REQ-D1.13
- **Estimated effort:** half day

### Task 37 — Skill, guide and doctrine for goals and spec drift

- **Deliverables:** The skill's prose for setting a goal with its check and
  for the drift refusal, inside the instruction budget (D-21), pointing at
  the scripts for the mechanics; the operator guide's sections on goals and
  on why a pull request waits for a spec sign-off; `doctrine/mission-control.md`
  and its README row updated for D-44 and D-45.
- **Done when:** The instruction-budget check passes; the guide has a
  section for goals and for the spec-drift refusal and names no duty or
  knob the catalog or options reference lacks; the jargon check passes over
  the new skill and guide text; the doctrine index check passes.
- **Dependencies:** 34, 35
- **Citations:** D-21, D-44, D-45 · REQ-N1.1, REQ-N1.2, REQ-D1.13
- **Estimated effort:** half day

### Task 38 — The plugin hook approves mission control's prompt-answer calls

- **Deliverables:** A PreToolUse Bash hook wired in `hooks/hooks.json` that,
  in a session the plugin's prompt hook marked as mission control, approves
  exactly one simple command: the literal resolved path of its own installed
  root's `scripts/fleet-streamjson.sh` with `pending` or `answer`, and defers
  on every other shape and in every other session; the mission-control mark
  in the tower-session mark store; the skill's answer prose pointing at it,
  inside the instruction budget (D-21).
- **Done when:** `tests/test-mc-approve-hook.sh` passes the cases its
  test-spec entry names; `config/mission-control-verbs.txt` still excludes
  the raw answer verb and its check passes; the instruction-budget check
  passes.
- **Dependencies:** 21
- **Citations:** D-35 · REQ-G1.6, REQ-G1.2
- **Estimated effort:** half day

### Task 39 — A context reading for every mission-control session

- **Deliverables:** `scripts/mc-context.sh`, a read-only verb that prints a
  session's context percent and its source, or the literal `unknown`, from
  the tail of the transcript its registry row names; the usage parser
  lifted out of `scripts/mc-throughput.sh` into a shared helper both
  scripts use, with the window taken from the transcript, the
  `context/<name>` window file or `mission_control_context_window`; the
  runner taking one reading per mission-control session per wake and
  recording it in the program's records, read by `scripts/mc-handover.sh
  due`; the reading and its source on the panel and the text panel, with a
  real-render preview approved and recorded by hand (REQ-F1.18); the knob
  rows in `docs/options-reference.md` and
  `config/mission-control-knobs.tsv`; tests in `tests/test-mc-context.sh`,
  `tests/test-mc-panel.sh` and the mod's tests.
- **Done when:** The REQ-L1.10 test-spec entry's fixtures pass; the knob,
  options-reference and `check:panel-mod` checks pass; the pull request
  quotes the recorded preview approval.
- **Dependencies:** none
- **Citations:** D-46, D-29, D-6 · REQ-L1.10, REQ-L1.5, REQ-F1.18
- **Estimated effort:** 1 day

### Task 40 — The handover at a natural break, keeping the session name

- **Deliverables:** The in-flight record a session opens at the start of a
  launch, relay or answer and clears at its end, and `scripts/mc-handover.sh
  due` reporting `wait` while one is open; the runner's single,
  never-batched handover-due wake to a launched holder with no operator at
  its terminal, and that holder's own write, launch, verify and take; the
  handover file listing open direct-dispatch units and `take` moving their
  registry owner; the successor launched under the predecessor's session
  name, `take` moving the name under the registry lock, a forwarding verb
  passing what the predecessor receives to the successor verbatim until
  `take` finishes, a failed `take` leaving name and program with the
  predecessor, and no handover armed before the successor's first reading
  is below the trigger; the research record, under a `## Session name by
  backend` heading, naming for each backend whether the name moves or the
  handover falls to D-43's rung 2; the skill's handover prose inside the
  instruction budget (D-21); tests in `tests/test-mc-handover.sh`.
- **Done when:** The REQ-L1.11 test-spec entry's fixtures pass; the research
  record's heading names every launcher backend; the instruction-budget
  check passes.
- **Dependencies:** 33, 39
- **Citations:** D-47, D-30, D-43, D-21 · REQ-L1.11, REQ-L1.6, REQ-L1.9
- **Estimated effort:** 2 days

### Task 41 — Direct dispatch for reviews and read-only checks

- **Deliverables:** `mission_control_direct_dispatch_kinds` (shipped: the
  review and read-only check kinds D-48 names); a launcher path that
  launches such a unit under its program as its launching mission
  control's registry row, with the program's rules and its kind's profile
  and a launcher-composed result path under the program home's results
  folder in its brief, refusing a path outside it or a symlink out of it;
  the result file's format (with a `format` field, written by rename) and
  its reader; the unit-lost event for a unit that ends with no result; the
  result's removal at retire; the unit's questions and prompts routed to
  the launching mission control; the skill's prose inside the instruction
  budget; the knob rows; tests in `tests/test-mc-direct-dispatch.sh`.
- **Done when:** The REQ-D1.15 test-spec entry's fixtures pass; the knob,
  options-reference and instruction-budget checks pass.
- **Dependencies:** 39
- **Citations:** D-48, D-10, D-8, D-21 · REQ-D1.15, REQ-D1.1
- **Estimated effort:** 1 day

### Task 42 — The prompt and finished-unit notifier, and batched wakes

- **Deliverables:** A notifier script the runner runs each pass, reading
  `scripts/fleet-streamjson.sh pending` and the registry, claiming each
  delivery in the attention store under its lock, delivering one sanitized
  line to the mission control that answers it, retrying a failed delivery
  up to `mission_control_relay_retries` passes before an event; holding a
  program holder's non-urgent wakes in the attention store and delivering
  them as one wake per `mission_control_relay_batch_interval`, the shipped
  urgent classes waking at once; the duty-catalog entry; the skill's prose
  inside the instruction budget; the knob rows; tests in
  `tests/test-mc-notifier.sh`.
- **Done when:** The REQ-E1.7 test-spec entry's fixtures pass; the knob,
  options-reference, duty-catalog and instruction-budget checks pass.
- **Dependencies:** 39, 41
- **Citations:** D-49, D-7, D-21 · REQ-E1.7, REQ-E1.3, REQ-G1.6
- **Estimated effort:** 1 day

### Task 43 — Spend per session on the panel

- **Deliverables:** Per-session spend since start, the program's UTC-day
  total across every session that ran in it and the mission-control share,
  priced from transcript usage with `config/token-prices.tsv` through the
  shared token-spend pricing helper and recorded by the runner with the
  context reading, shown in the panel mod and the text panel; unknown for
  an unreadable or unpriced session and a partial marker on the total; a
  preview captured from the real render over fixture data, shown to the
  operator, and their approval recorded by hand (REQ-F1.18); tests in
  `tests/test-mc-panel.sh` and the mod's tests.
- **Done when:** The REQ-F1.17 test-spec entry's fixtures pass;
  `check:panel-mod` passes; the pull request quotes the recorded preview
  approval.
- **Dependencies:** 39
- **Citations:** D-50, D-46, D-6 · REQ-F1.17, REQ-F1.18
- **Estimated effort:** 1 day

### Task 44 — The idle-wait audit in the throughput duty

- **Deliverables:** An idle-wait verb in `scripts/mc-throughput.sh` taking
  `--now`, run by `scripts/mc-handover.sh` at each handover and by the
  runner every `mission_control_idle_audit_interval`, reading the program's
  step, flight and dispatch records, the forge snapshot's CI timing and the
  attention store, writing each wait found as a mechanization proposal in
  D-14's form with its time saved per day, identified by kind and the step
  or timer it names; the skill's prose inside the instruction budget; the
  knob rows; tests in `tests/test-mc-throughput.sh`.
- **Done when:** The REQ-M1.10 test-spec entry's fixtures pass; the knob,
  options-reference and instruction-budget checks pass.
- **Dependencies:** 40
- **Citations:** D-51, D-14, D-12, D-21 · REQ-M1.10
- **Estimated effort:** 1 day

### Task 45 — The preview gate, and the guide for the extension

- **Deliverables:** `mission_control_visible_paths` with its shipped list;
  the readiness check's refusal of a flip for a pull request changing a
  listed path with no matching approval in the program's decisions log;
  the guide's rows for the extension and the options-reference rows; a
  real-render preview of the guide change approved and recorded by hand;
  tests in `tests/test-mc-readiness.sh` and
  `tests/test-mission-control-docs.sh`.
- **Done when:** The REQ-F1.18 test-spec entry's fixtures pass; the knob,
  options-reference and instruction-budget checks pass; the pull request
  quotes the recorded preview approval.
- **Dependencies:** 39, 40, 41, 42, 43, 44
- **Citations:** D-50, D-25, D-33, D-21 · REQ-F1.18, REQ-D1.14
- **Estimated effort:** 1 day

### Task 46 — The bring-up drift audit

- **Deliverables:** In `scripts/mc-config.sh doctor`, the rule-number check
  (a standing rule naming a value for a knob it governs, against the
  knob's effective value) and the stale-override check (a local-layer
  comment or value with a past date, or interim, temporary or until with no
  date ahead), both matched as data with fixed patterns; the audit run in
  every successor's self-check as at bring-up; plain-words findings naming
  file, knob, rule or comment and effective value; tests in
  `tests/test-mc-config.sh`. Where these checks already landed (the
  pending note's pull request), this task is their tests and wiring only.
- **Done when:** The REQ-A1.9 test-spec entry's fixtures pass.
- **Dependencies:** none
- **Citations:** D-52, D-32 · REQ-A1.9, REQ-A1.2
- **Estimated effort:** half day

### Task 47 — Rules say how they are enforced

- **Deliverables:** the `enforcement` field in `scripts/mc-rules.sh`
  (`add` and `supersede` accept it against the closed grammar; `list`,
  `render` and the active-set load read it, an entry without it reading
  `unknown`); in `scripts/mc-config.sh doctor`, the listing of every
  active rule that is prose, unknown or names a closed fix, one plain line
  each; the field documented where the store's format is; tests in
  `tests/test-mc-rules.sh` and `tests/test-mc-config.sh`, in fixtures.
- **Done when:** The REQ-B1.8 and REQ-A1.10 test-spec entries' fixtures
  pass; the pull request does not conflict with the open doctor flag for a
  rule that disagrees with its knob.
- **Dependencies:** none
- **Citations:** D-53, D-52, D-5 · REQ-B1.8, REQ-A1.10, REQ-B1.1
- **Estimated effort:** half day

### Task 48 — Move a live session between programs

- **Deliverables:** `mission-control-launch.sh reparent <session>
  --program <destination> --authority <decisions-log record>` and its
  refusals (including no authority); the event written to both
  programs' logs and the undo entry; the verb documented where the
  launcher's verbs are and in the fold-in and handover guidance mission
  control follows; tests in `tests/test-mission-control-launch.sh`, in
  fixtures.
- **Done when:** The REQ-D1.16 test-spec entry's fixtures pass.
- **Dependencies:** none
- **Citations:** D-54, D-35, D-24 · REQ-D1.16, REQ-D1.12, REQ-G1.6
- **Estimated effort:** half day

### Task 49 — Readiness waits for reviewers that review only when ready

- **Deliverables:** `mission_control_review_on_ready_bots` and
  `mission_control_review_on_ready_wait` with their knob and
  options-reference rows; the draft-stage trigger comment and wait for each
  named reviewer, falling back per reviewer; the readiness check's merge-ready evaluation
  (a review of the current head from each named reviewer, every thread
  resolved, the flip conditions still holding) and the *ready, awaiting
  reviewers* state; the ready-to-merge notice held until it passes; the
  operator item for a silent reviewer; the bot-review step's guidance;
  tests in `tests/test-mc-readiness.sh`.
- **Done when:** The REQ-D1.17 test-spec entry's fixtures pass; the knob,
  options-reference and instruction-budget checks pass.
- **Dependencies:** 45
- **Citations:** D-55, D-25, D-33 · REQ-D1.17, REQ-D1.8, REQ-D1.9
- **Estimated effort:** 1 day

## Awaiting input

- **Task 23** — PR #839's automated review round is unfinished. GitHub rejected the reply to cubic's finding on the activation test twice (the fix landed in 0e4194d2), and cubic has not yet reviewed that head. Next step: post the drafted reply, then run `/bot-review --nested --reviewer cubic` again.

## Deferred

(none yet)

## Out of scope

- **Task 30** — superseded by Task 33 (2026-11-07): an attended session
  hands over beside itself rather than compacting (D-43, REQ-L1.9).

- The review desk, spec currency, the environment broker, the night shift
  and the state-source adapters as duties in this bundle: follow-on bundles
  seeded by Task 14.
- A web or GUI dashboard beyond the in-app panel.
- Cross-machine mission control.
