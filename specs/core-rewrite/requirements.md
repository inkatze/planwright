# Core rewrite — Requirements

**Status:** Ready
**Last reviewed:** 2026-11-28
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright's pipeline works only as well as its agents remember their
instructions. Pipeline state, gates, the verification cadence, step records,
readiness and handovers are kept by sessions following prose, and the shell
guards meant to hold the line try to prove a raw command string safe by
enumerating its spellings. At today's scale that design fails the same few
ways over and over. Workers record steps they did not run and times they did
not observe, and only mission control's vetting catches it: seven records on
one pull request were sent back for it. A guard closes one spelling and the
next review round finds another: about twenty push-guard bypasses across one
guard's review rounds, and two more on 2026-11-27 that reached main without a
prompt. Every command a guard cannot prove becomes a permission prompt that a
model session answers between its other work, which made approval waits the
largest single bottleneck on 2026-11-26. The operator named the cause: the
revamp is "rewriting the core and actually make things work mechanically"
(Sources).

This spec rewrites the core so that the pipeline's mechanics are **enforced by
code, not by instructions**. A deterministic core holds the pipeline state in
a store of its own and moves it only through a state machine whose verbs
refuse a wrong transition. A worker cannot record a step it did not run, a
time it did not observe, a convergence that did not converge, or a readiness
the store does not show. The guard model stops deciding safety from command
text: the operating system confines local work, a small set of typed verbs
carries every outward act and validates it on its arguments, a real shell
parser fails closed on anything it cannot read literally, and only
irreversible or outward acts are hard-blocked, the acts the human-gates list
names forming a floor no policy can allow.
Approvals become records and decisions made in code. A prompt that still needs
a person reaches its owner within seconds, and a relayed operator go is a
record the core acts on, not prose a model must carry past the classifier.
The cost and throughput measures the operator asked for (review sized to the
diff, PR-Agent spend, fewer CI rounds, fewer handovers, the usage ladder and
model tiers) land as mechanisms of the same core rather than as more rules.

The deliverable is a framework-core capability with one doctrine line beneath
it (D-1): every rule the pipeline depends on has a code home that refuses its
violation, and a rule an agent must remember is a defect to close. It lands in
slices, each run in shadow beside today's shell path before it decides
anything live, with the human gates fixed as a must-never-allow set from the
first slice (D-14). It supersedes the control-plane spec and universal-binary's
unbuilt verdict and migration tasks, and replaces worker-permission-ergonomics'
guard mechanism while keeping its outcomes (D-16).

## Scope

### In scope

- The core program: one prebuilt `planwright` executable with an embedded
  store, its delivery to adopters with no toolchain, the shims that keep every
  shell entry point a skill calls, and a direct mode that needs no service
  alongside an opt-in service mode.
- The pipeline state machine: units, points, steps and their records, stamped
  by the core's own clock and git reads; readiness and the step audit computed
  from the store; point completion refused while a step lacks its record;
  handovers generated from the store.
- The guard model: the decision engine at the PreToolUse hook in every session
  type, the OS sandbox profile for workers and mission control, typed verbs
  for outward acts, the fail-closed parser tier, the human gates as settings
  deny and ask rules, and retirement of the enumerate-the-spellings shell
  guards once the replacement has held in shadow.
- The approval flow: the routine classes (read-only and own-branch work) as
  policy data,
  prompts stored whole and delivered to their owner with redelivery and an
  escalation timer, approvals and relayed operator goes as records, and the
  request ledger and event dedupe carried from control-plane.
- Process lifecycle in the core: one sessions table, a supervisor that owns
  each worker's pipes and process group, reaping, restart onto a new install,
  and recovery that keeps a worker's owner.
- Cost and throughput mechanisms: review passes sized to the diff and stopped
  mechanically, PR-Agent once per final head, CI rounds cut by judging only
  what a pull request touches, fewer and cheaper handovers, the usage ladder
  failing closed, and model tiers resolved per step.
- The supersession bookkeeping for the bundles this spec replaces or amends.

### Out of scope

- Changing what the human gates are. The list stays human-gates' own; this
  spec only makes it mechanical.
- Merging, signing off, marking a pull request ready by any path other than
  the ones human-gates already allows, or sending a message to a person
  without the operator's yes.
- The shared knowledge base and search receipt (hub follow-up f-50) and the
  two-surface mission-control mod redesign (f-41, item 1): separate concerns
  with their own seeds, deferred in `tasks.md`.
- A network listener on any host, a queue or database server (Redis,
  Postgres, NATS), and the Agent SDK as a runtime (D-2, D-13).
- Cross-host transport beyond today's SSH rung (deferred, D-21).
- Machine setup on any host (the sandbox packages, a service unit): those are
  operator-approved dotfiles changes routed by mission control, never a task
  of this bundle (D-22).
- Employer data of any kind: only generic lessons reach this bundle.

## REQ-A — Mechanical enforcement

- **REQ-A1.1** Every rule the pipeline depends on for correctness (an order of
  steps, a gate, a record's truth, a readiness condition, a lifecycle
  transition, a limit) SHALL have a code home that refuses its violation, and
  no such rule SHALL depend on an agent remembering an instruction. A rule
  that is still prose SHALL be recorded as an open gap naming its intended
  code home, never treated as enforced.
  *(Cites: D-1; the operator's revamp words (Sources).)*
- **REQ-A1.2** A prose rule SHALL retire only when its code home's tests have
  landed and a fixture proves the code refuses what the rule forbade; until
  then the prose rule stands beside the code.
  *(Cites: D-1, D-16; control-plane REQ-A1.4 (Sources).)*
- **REQ-A1.3** Failure SHALL be asymmetric: an unreadable, unknown-format or
  ambiguous input to an allow, admission, record or readiness decision SHALL
  refuse or defer it, never allow it, and an unreadable input to an event
  dedupe SHALL deliver the event, never drop it.
  *(Cites: D-4; control-plane REQ-A1.3 (Sources).)*
- **REQ-A1.4** The human gates SHALL stay human: no code in this spec
  performs an act the human-gates list names as a human gate, or a ready flip
  or merge outside the policy human-gates sets for it, on its own authority.
  Such an act proceeds only on an operator approval record (REQ-E1.5), and
  only where human-gates lets the operator's yes authorize it. The decision
  engine's floor (REQ-D1.2) holds every act of that list, read from
  human-gates rather than copied, so that no policy layer can allow one.
  *(Cites: D-4; human-gates REQ-A1.1, REQ-A1.2, REQ-C1.1 (Sources).)*
  *(Amended at kickoff 2026-11-28: the floor cites the whole human-gates list,
  and the approval-record path is named.)*
- **REQ-A1.5** planwright's doctrine SHALL carry the mechanical-enforcement
  line as a rule doc of its own, and the spec-draft design phase and the
  kickoff lens pass SHALL flag a requirement whose only enforcement is an
  instruction.
  *(Cites: D-1.)*

## REQ-B — The core program and store

- **REQ-B1.1** The core SHALL ship as one prebuilt `planwright` executable for
  every platform of universal-binary's CI platform matrix, and installing or
  running planwright SHALL NOT require a compiler, interpreter or package
  manager on the adopter's machine beyond the POSIX shell, git and gh that
  universal-binary REQ-B1.1 already permits (the shims are POSIX shell).
  *(Cites: D-2; universal-binary REQ-B1.1 (Sources).)*
- **REQ-B1.2** The executable SHALL embed its store (SQLite in write-ahead-log
  mode) and SHALL NOT depend on a database, queue or message server.
  *(Cites: D-2; the core-substrate research report (Sources).)*
- **REQ-B1.3** The same executable and the same store SHALL run in two modes:
  direct (no service; each call opens the store) and service (a per-user
  daemon). Decisions SHALL be identical in both; a mode changes only liveness
  (delivery latency, restart, timers).
  *(Cites: D-3.)*
- **REQ-B1.4** Service mode SHALL be switched on per host only by a recorded
  operator yes (a capability row with the operator's words and time), and the
  doctor SHALL print each host's capabilities and what it lacks. Nothing SHALL
  install or enable itself.
  *(Cites: D-3, D-22.)*
- **REQ-B1.5** Every `scripts/<name>.sh` entry point a skill, hook or adopter
  calls by path SHALL keep working as a thin shim onto the executable until a
  human-directed removal, and a skill SHALL reach the core by one stable
  command name, never a versioned path.
  *(Cites: D-2, D-14; the work-machine lessons (Sources).)*
- **REQ-B1.6** The store SHALL hold only state that is rebuildable or exported:
  work products (rules, follow-ups, decisions, the request ledger, approval
  records and host capability rows) SHALL be exported to their text forms on
  change, and the decision log SHALL be written as an append-only log file
  the store indexes, so nothing is trapped in the database.
  *(Cites: D-15; storage-classes doctrine (Sources).)*
- **REQ-B1.7** The delivered executable SHALL be verified before first use
  against the checksum pin committed in the repository and the release's
  provenance attestation, never against a checksum fetched beside the asset, and a failed verification SHALL refuse to run
  rather than fall back to an unverified copy.
  *(Cites: D-2; universal-binary Task 10 (Sources).)*
- **REQ-B1.8** Every worker launch SHALL refuse bare mode explicitly, and every
  session the core starts SHALL check on its first tool call that the
  planwright PreToolUse hook ran, refusing to continue when it did not.
  *(Cites: D-20; the core-substrate research report (Sources).)*
- **REQ-B1.9** The store and executable SHALL follow D-23's upkeep rules:
  forward-only migrations after a snapshot, an older executable refusing to
  write a newer store, configured retention with each pruning recorded, a
  shim version check that fails closed, a direct-mode write lock whose timeout
  refuses or asks, caller identity taken from the harness, credentials
  redacted before storage, and a hook time limit that never allows.
  *(Cites: D-23.)*
  *(Added at kickoff 2026-11-28.)*

## REQ-C — The pipeline state machine

- **REQ-C1.1** Units, points, steps and their outcomes SHALL be states of one
  state machine in the core, moved only by its verbs, and a verb SHALL refuse
  any transition the machine does not define. A unit here is a spec task (or
  cohesion bundle), a flight or a mission-control launch, wider than
  spec-format's unit; a point is a named moment in a unit's cadence at which
  steps resolve.
  *(Cites: D-11.)*
- **REQ-C1.2** A step record's start and end times SHALL be taken by the core
  from its own clock when the step's begin and end verbs run, and its heads
  SHALL be read by the core from git; a record carrying an agent-supplied time
  or head SHALL be refused.
  *(Cites: D-10; hub follow-ups f-48 and f-56 (Sources).)*
- **REQ-C1.3** A prompt-kind or skill-kind step SHALL be recordable only after
  the core delivered its prompt (the resolve of its point) and only with times
  strictly after that delivery.
  *(Cites: D-10; hub follow-up f-56 (Sources); obs:e596d787.)*
- **REQ-C1.4** A point's completion SHALL be refused while any resolved step of
  it (a step its resolve returned) lacks a record, a skipped step recording
  its skip as its outcome, and a convergence completion SHALL be refused while
  the last review pass applied a change.
  *(Cites: D-11, D-18; obs:77e09e51, obs:a724c17f.)*
- **REQ-C1.5** A record SHALL be written only through the core's verbs; the
  store and the record files SHALL be write-denied to agents at the OS level
  where the sandbox runs and at the file-tool and parser-tier level
  everywhere, and a copied, wrapped or renamed recorder SHALL gain no
  authority.
  *(Cites: D-5, D-10, D-22; obs:8f0c4892, obs:ff4e3890.)*
  *(Amended at kickoff 2026-11-28: the OS-level deny applies where the sandbox
  runs.)*
- **REQ-C1.6** Ready-flip readiness and the step audit SHALL be computed by the core from
  the store and the forge's current state, never from a session's account of
  them, and SHALL be the same computation for every unit kind (spec task,
  flight, mission-control launch).
  *(Cites: D-11; obs:38178048, obs:201699a6.)*
- **REQ-C1.7** A handover brief SHALL be generated from the store (open units,
  open requests, commitments, duties) and diffed against the previous one, and
  a successor's take SHALL be refused while a request or commitment is
  neither acknowledged by the successor nor waived by an operator approval
  record.
  *(Cites: D-12; obs:28d0df97, obs:e97aa5bb.)*
- **REQ-C1.8** The core SHALL resolve a session's configuration from that
  session's own row, never from inherited environment, so a session can never
  read another program's configuration.
  *(Cites: D-11; hub follow-up f-48 (Sources).)*

## REQ-D — The guard model

- **REQ-D1.1** One decision engine, a pure function from (session row, tool
  call) to allow, deny with a reason, or ask a named owner, SHALL decide every
  tool call at the PreToolUse hook in every session type (headless worker,
  tmux session, tower, mission control, subagent), and every decision SHALL
  be logged with a digest of its inputs. A call from a session with no row
  SHALL ask (REQ-A1.3).
  *(Cites: D-4.)*
- **REQ-D1.2** The engine's tiers SHALL apply in this order: the floor (the
  human-gate acts, and a session editing its own permissions, guard, policy or
  audit log), which the engine never allows on policy alone (a floor act
  proceeds only on an operator approval record under REQ-E1.5, and only where
  human-gates lets the operator's yes authorize it); typed verbs, validated on their
  arguments against the session's row; sandboxed local work, allowed and
  logged; the parser tier where no sandbox runs; and ask.
  *(Cites: D-4, D-5, D-6.)*
- **REQ-D1.3** The floor acts SHALL also be deny or ask rules in every shipped
  settings profile, so that no hook defect can loosen them.
  *(Cites: D-4; Claude Code permission precedence (Sources).)*
- **REQ-D1.4** Outside the floor, the guard SHALL hard-block only acts that are
  irreversible or reach outside the machine; reversible local acts SHALL run
  without a prompt and be audited after the fact from the decision log. An act
  is reversible when its effects stay inside the session's own worktree,
  scratch directory and unpushed unit branch.
  *(Cites: D-4; hub follow-up f-43 (Sources); obs:665b36dd.)*
- **REQ-D1.5** Workers and mission controls SHALL run under the OS sandbox
  where the host has it: writes limited to the session's own worktree, its
  scratch directory and the shared git directory (its hooks and config
  excluded), every forge credential source the host has (config files, agent
  sockets, credential helpers, token environment variables) denied inside the
  sandbox, unsandboxed retry off, and the sandbox required rather than
  silently skipped: on a host whose capability row says it is
  sandbox-capable, a launch whose sandbox fails to start SHALL be refused,
  and a host without one runs the parser tier and logs that it does. Mission
  control SHALL have no repository write at the OS level.
  *(Cites: D-5, D-22; hub follow-up f-43 (Sources).)*
- **REQ-D1.6** Every outward act (push, pull-request write, ready flip, merge
  admission, thread reply, message, planwright's own records, the kickoff's
  publish of a signed spec branch) SHALL go
  through a typed verb that runs outside the sandbox, holds the credential and
  validates its arguments against the session's row; no outward act SHALL be
  admitted from free shell text, and on a host with no sandbox an outward act
  in shell text SHALL be refused, not parsed. Each verb SHALL take a fixed
  argument schema whose every identifier (repository, ref, pull request,
  thread) matches the row exactly; the message verb SHALL refuse a person as
  recipient without an operator approval record; no verb SHALL write an
  approval record.
  *(Cites: D-6; hub follow-up f-57 (Sources).)*
- **REQ-D1.7** The push verb SHALL judge the destination git itself resolves
  (the refs a pre-push check receives), never the command's spelling, so that
  option swallowing, brace or glob expansion, ordering, config redirection or
  ref shorthand cannot change what is judged. A push to a protected branch
  (`planwright/*/spec` included) SHALL be refused, with one exception: the
  kickoff publish verb MAY push a signed spec or amendment branch only through
  the core's own push command, only on the operator's sign-off approval record
  for that exact branch and commit, and only once per record. Every other
  spec-branch push stays refused.
  *(Amended at kickoff 2026-11-28: the operator's bound exception for the
  kickoff publish.)*
  *(Cites: D-6; hub follow-up f-54 and the 2026-11-27 push bypasses (Sources);
  obs:5408541c.)*
- **REQ-D1.8** Where the parser tier decides, it SHALL parse the command into
  a syntax tree with a real shell parser and SHALL treat as unknown (ask, never
  allow) any word that is not literal after quote removal (a parameter,
  command or arithmetic expansion, a brace or glob pattern, `eval`, `source`,
  an alias or a function) in a command position or in any argument the tier
  judges. Redirection targets, here-documents and substitutions SHALL be
  judged as arguments, the allow-list SHALL name each command's permitted
  options, and running a file the session wrote SHALL ask.
  *(Cites: D-5; obs:66e65bab, obs:88a46da1, obs:34b06157.)*
- **REQ-D1.9** The enumerate-the-spellings shell guards SHALL be removed only
  by a human-directed removal after the engine has run in shadow beside them
  with no floor disagreement over the shadow window.
  *(Cites: D-14.)*

## REQ-E — The approval flow

- **REQ-E1.1** Routine classes (read-only git and gh, the worker's own scratch
  and worktree writes, planwright's own record and audit verbs, the project's
  tests, lint and format inside its own worktree, replies on threads in which
  only automated reviewers have posted) SHALL be policy data the engine
  allows with no model turn, and an operator SHALL tune them without editing
  code. A thread any person has posted in is a message to that person, and
  its reply stays on the floor. Policy data SHALL be validated at load: an
  entry matching a floor act SHALL be rejected, and a failed load SHALL keep
  the previous policy. The project's tests, lint and format are the commands
  its configured tasks name.
  *(Cites: D-7; hub rule r-111 (Sources); obs:3096a22b, obs:79cabf07.)*
  *(Amended at kickoff 2026-11-28: bot-thread replies narrowed to threads
  only bots have posted in.)*
- **REQ-E1.2** The engine SHALL answer a worker's permission prompt itself for
  every call it can decide, logging each answer; only an ask SHALL reach a
  model or the operator.
  *(Cites: D-7.)*
- **REQ-E1.3** A prompt that still needs an answer SHALL be stored whole (no
  display truncation) with its owner, and SHALL reach that owner's inbox with
  delivered, read and answered states and redelivery until acknowledged; in
  service mode delivery SHALL take seconds, not a wake cycle (the bound a
  config setting). A prompt's owner is the asking session's owner, else its
  program's mission control, else the operator.
  *(Cites: D-9; hub follow-ups f-45 and f-48 (Sources).)*
- **REQ-E1.4** Every pending prompt SHALL carry an escalation timer whoever
  owns it, ending in an operator push, and a program SHALL see only its own
  sessions' prompts. The timer is recorded in both modes; it fires on time in
  service mode and at the next core call in direct mode.
  *(Cites: D-9; obs:ef47a4ed.)*
- **REQ-E1.5** An operator approval SHALL be a record the core writes itself
  from the operator's own answer (a selector answer or typed reply the harness
  delivers, never an argument a model supplies), carrying the operator's
  quoted words, the time, the exact text's hash, the act, its target and the
  commit it applies to. No model session SHALL be able to write one. A record
  SHALL be single-use unless it carries an explicit scope with an expiry, and
  the core SHALL perform an approved act only on a record matching its act,
  target and commit, so that no model carries the authority across a relay.
  *(Cites: D-8; hub follow-up f-42 (Sources).)*
  *(Amended at kickoff 2026-11-28: the core captures the record from the
  operator's own answer, bound to act, target and commit.)*
- **REQ-E1.6** The request ledger (capture on arrival, closure with cited
  evidence, the handover check, the re-read at every wake) SHALL be carried
  into the core with control-plane REQ-J's meaning.
  *(Cites: D-16; control-plane REQ-J (Sources).)*
- **REQ-E1.7** Event dedupe at the source (repeat, stale and off-order events
  dropped before they wake a session, routine events coalesced, drops counted)
  SHALL be carried into the core with control-plane REQ-D's meaning.
  *(Cites: D-16; control-plane REQ-D (Sources).)*

## REQ-F — Process lifecycle

- **REQ-F1.1** Every session SHALL have exactly one row in the store, and
  register, recover, relaunch and retire SHALL each be one transaction, so a
  recovered or relaunched worker keeps its owner and a completed row is never
  swept while its process lives.
  *(Cites: D-13; hub follow-up f-46 (Sources); obs:50d47869.)*
- **REQ-F1.2** The core's supervisor SHALL spawn the installed `claude`
  executable, own the child's pipes with a single writer, and keep each worker
  in a process group (a cgroup scope where the host has one) that retire and
  stop end whole.
  *(Cites: D-13; obs:c22c2e08, obs:47e24470, obs:44b2795b.)*
- **REQ-F1.3** Liveness SHALL be read from the process the core recorded at
  spawn, never inferred by scanning the process table.
  *(Cites: D-13; obs:3bf031b9, obs:5610ccff.)*
- **REQ-F1.4** After a plugin update, the core SHALL move its long-lived
  processes onto the installed version itself and launch every new session
  with the installed root; a session found on a superseded root SHALL be
  raised to its owner, not left running silently.
  *(Cites: D-13; obs:b45f1311, obs:3aac06ec.)*

## REQ-G — Cost and throughput

- **REQ-G1.1** A review pass's lens set SHALL be sized from the diff it reviews
  (after the first pass, only the files the previous pass changed), and the loop
  SHALL stop on the first pass that applies nothing.
  *(Cites: D-18; hub follow-ups f-44 and f-55 (Sources); obs:d29ab51b.)*
- **REQ-G1.2** A review loop SHALL carry a round cap and a wall-clock budget as
  config, and reaching either SHALL end the loop with a recorded outcome rather
  than another pass.
  *(Cites: D-18; obs:caefb6a1.)*
- **REQ-G1.3** A hosted reviewer that bills per run (PR-Agent today) SHALL run
  once per pull request, on the final head before the ready flip, plus once
  after each fix round that changes code, and the readiness computation SHALL
  report any other run as a defect.
  *(Cites: D-17; hub rule r-59 (Sources).)*
- **REQ-G1.4** A per-file test-time budget SHALL fail a pull request only for a
  file its diff against the merge base touches; an untouched file over budget SHALL be
  retried once and then reported, not failed.
  *(Cites: D-19; hub follow-up f-53 (Sources).)*
- **REQ-G1.5** The usage ladder (quota-handling's) SHALL live in the core and
  fail closed: an
  unreadable or refused usage or load read SHALL hold launches and raise an
  event, never read as zero.
  *(Cites: D-17; obs:281716e8, obs:f8cb8d43.)*
- **REQ-G1.6** Model and effort tiers SHALL be resolved by the core per launch
  kind and per step, and a shipped default SHALL change only with the
  measured cost and catch data that justify it, cited in the change.
  *(Cites: D-17; model-allocation (Sources).)*
- **REQ-G1.7** A worker expecting to wait past the prompt-cache lifetime (a
  config setting citing its source) SHALL
  end and be relaunched from a generated handover when its wait ends, and a
  supervisor's handover threshold SHALL be derived from the measured
  cost-per-turn curve.
  *(Cites: D-12, D-17; obs:b96eef36, obs:3b1fad05.)*
- **REQ-G1.8** Each slice SHALL report its effect against a baseline taken
  before the first slice (prompts per unit, prompt wait, mission-control turns,
  review time, CI rounds per pull request, handovers per day), and a slice
  whose measure does not move SHALL be raised to the operator before the next
  slice starts. A slice is a task that changes a live decision or session
  outcome; it reports in its own Done-when, and the raise is an Awaiting-input
  entry on the next slice's task, which blocks that task's dispatch until the
  operator answers.
  *(Cites: D-14; control-plane Task 1's baseline (Sources).)*

## REQ-H — Migration and safety

- **REQ-H1.1** The first slice SHALL be an offline replay of recorded prompt
  envelopes through the decision engine, reporting the share settled per tier
  and every disagreement with what was actually answered, and SHALL fail hard
  if any must-never-allow fixture is allowed.
  *(Cites: D-14; the core-substrate research report (Sources).)*
- **REQ-H1.2** Every slice that decides live SHALL first run in shadow beside
  the path it replaces, logging only, and SHALL go live only after its shadow
  window shows no floor disagreement. The window is a config setting whose
  default is 7 days, and it closes only once it also holds at least one
  logged decision from every session type. A floor disagreement is the new
  path allowing any floor act, or allowing a call the path it replaces
  refused on a floor ground; the new path being stricter is logged, never
  blocking.
  *(Cites: D-14.)*
  *(Amended at kickoff 2026-11-28: the window's default, closing rule and
  failure rule decided.)*
- **REQ-H1.3** The core SHALL ship a kill switch that returns every session to
  the shell path in one act, and the kill switch SHALL never loosen the floor.
  The shell path is the retained pre-shim script bodies the switch selects;
  the switch SHALL be thrown only on an operator approval record, SHALL be
  logged, and SHALL leave the engine running in shadow and the settings floor
  in force.
  *(Cites: D-14; control-plane REQ-I (Sources).)*
- **REQ-H1.4** Every policy and guard task SHALL land its failing fixtures
  first: the must-never-allow set (every floor act in every spelling the
  guard-coverage corpus holds) and a positive control that proves the harness
  can fail.
  *(Cites: D-14; guard-coverage (Sources); obs:e9f5cc37.)*

## REQ-I — Supersession

- **REQ-I1.1** Once this spec is signed off, control-plane SHALL be marked
  Superseded with a pointer to this bundle; its landed baseline (Task 1)
  stands; its fail-closed, prose-retirement, policy-as-data, dedupe, safety
  and request-ledger meaning SHALL be carried by REQ-A1.2, REQ-A1.3,
  REQ-E1.1, REQ-E1.6, REQ-E1.7 and REQ-H1.3; and every other requirement and
  stub task of it SHALL be named as carried, dropped or deferred in its
  supersession amendment (Task 2).
  *(Cites: D-16.)*
- **REQ-I1.2** universal-binary's unbuilt verdict and migration tasks (Tasks 9
  to 14 at this sign-off) SHALL be retired by an amendment of that bundle
  citing this one, its landed baselines and bake-off data standing as this
  spec's evidence and its Task 10 delivery design carried into this bundle's
  Task 3.
  *(Cites: D-2, D-16.)*
- **REQ-I1.3** worker-permission-ergonomics' guard mechanism SHALL be replaced
  by REQ-D, keeping its outcomes (no model in the routine approval path, the
  deny floor), and execution-backends D-5 and worker-permission-ergonomics
  REQ-F1.2 SHALL each be superseded by a new record in its bundle so the
  engine may answer prompts.
  *(Cites: D-7, D-16.)*

## Changelog

- 2026-11-27: Drafted by `/spec-draft` from the hub's revamp follow-ups, the
  core-substrate research report, the work-machine lessons, the pending notes
  and the observations accumulator (Sources).
- 2026-11-28: Edited in place during the `/spec-kickoff` walk with the
  operator; the decisions and the full fix list are in `kickoff-brief.md`.

## Sources

- **The operator's revamp words (pinned altitude claim).** 2026-11-24, hub
  rule r-110: "for the revamp I thought we were rewriting the core and
  actually make things work mechanically and add all cost-saving measures,
  approval issues, etc"; 2026-11-27, hub picklist: "Start now but will it
  include the revamped deterministic core?" (answered yes: the deterministic
  core is the centre of this spec).
- **The operator's drafting answers** (hub picklist, 2026-11-28): Go for the
  core (D-2); the engine may answer prompts outside the floor (D-7);
  supersede control-plane and universal-binary's unbuilt tasks (D-16); turn
  on the OS sandbox for workers on planwright's Linux host, its missing
  package added through dotfiles (D-22).
- **The hub's draft brief (pinned altitude claim).** 2026-11-27: "Nothing
  relies on agents remembering instructions. A worker cannot record a step it
  did not run, and cannot record a time it did not observe."
- **Hub follow-ups f-41 to f-59** (mission-control hub knowledge base), the
  weekend-revamp inputs: f-42 approval flow; f-43 guard model (pinned claim:
  "hard-block only irreversible or outward acts"); f-44 and f-55 polish time;
  f-45 prompt delivery; f-46 lost owner rows; f-47 the other machine's gap
  batches; f-48 record stamps, launch scope and config resolution; f-49 the
  substrate research ask; f-52 hook edits, record end heads and posture
  diagnostics; f-53 test-time budget; f-54 push-guard convergence; f-56
  prompt-record times; f-57 the kickoff publish path; f-58 approval waits;
  f-59 the human-gates follow-up build.
- **The core-substrate research report** (research session, hub knowledge
  base, 2026-11-26): the one-binary-plus-SQLite recommendation, the decision
  engine tiers, the sandbox and typed-verb findings, the bare-mode risk, the
  measured prompt and wait figures for this host, and the migration order.
- **The work-machine lessons** (hub knowledge base), generic lessons only:
  version-pinned allow rules, self-modification refusals, literal allow
  matching, per-prompt approval cost, fixing at the root in the plugin, held
  pushes that stay denied, guards refusing plain reads beside a pipe, stacked
  pull requests with no agent path, and frame writes that hang.
- **The 2026-11-27 push bypasses:** an `--end-of-options` option swallow and
  brace or glob expansion of push option words, both reaching main with no
  prompt (planwright pull request #1191).
- **Hub rules** r-46 (every operating gap fixed in planwright's shipped
  defaults), r-59 (PR-Agent sparing use), r-104 (the freeze this spec
  ends), r-111 (the narrow worker allow-list exception), r-114 (the
  panel-review cap).
- **Pending notes** (read, not consumed: each stays with its owning bundle):
  `deterministic-worker-approvals.md`, `worker-permission-ergonomics-amendment.md`,
  `isolated-remote-workers.md`, `review-effectiveness-research.md`,
  `mission-control-handover-200k-amendment.md`, `fleet-idle-worker-end-amendment.md`,
  `model-allocation-review-sonnet-amendment.md`, `supervisor-cost-tiering-amendment.md`,
  `custom-steps-heavy-run-bound-amendment.md`, `selector-cross-spec-edges.md`.
- **Prior bundles:** control-plane (superseded here: REQ-A1.3, REQ-A1.4,
  REQ-D, REQ-I, REQ-J and Task 1's baseline); universal-binary (REQ-B1.1, the
  landed Tasks 1 to 8, Task 10's delivery design, and the unsigned verdict
  draft); worker-permission-ergonomics; execution-backends D-5; human-gates
  REQ-A1.1; guard-coverage's fixture corpus; harness-rebaseline's permission
  trial; review-effectiveness; model-allocation; fleet-autonomy;
  quota-handling; mission-control.
- **Doctrine:** storage-classes, human-gates, autopilot-reflex,
  customization-boundary.
- **Claude Code permission precedence** (official permissions and sandboxing
  documentation, as read by the research report on 2026-11-26): deny, then
  ask, then allow; an ask rule still prompts when a hook allows.
- **Observations consumed:** the fragments archived with this bundle under
  `specs/_observations/archive/`, each carrying
  `Consumed-by: specs/core-rewrite`, cited as `obs:<uid>` where a requirement
  or decision uses one directly; the rest are consumed as corpus input to the
  must-never-allow fixtures (REQ-H1.4) and the replay (REQ-H1.1).
