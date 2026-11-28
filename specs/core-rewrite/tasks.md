# Core rewrite — Tasks

**Status:** Ready
**Last reviewed:** 2026-11-28
**Format-version:** 2
**Execution:** derived — see the status render

The tasks follow the migration order D-14 sets: the offline replay first,
then the shadow hook, then each live slice behind its shadow window. Every
policy and guard task lands its failing fixtures first (REQ-H1.4). Tasks that
touch the engine, verbs, sandbox profile or parser get the write-time security
pass. The supersession bookkeeping (Task 2) lands before the engine goes live
(Task 8), so no two live specs own the approval engine.

## Tasks

### Task 1 — Core skeleton, store schema and the offline replay

- **Deliverables:** The Go module and its build for every platform of
  universal-binary's CI platform matrix;
  the store schema (sessions, leases, events, prompts, inbox, approvals, rules,
  duties, step records, decision log) with migrations, and D-23's store-side
  upkeep (schema version, snapshot before migration, retention, write lock,
  caller identity from the harness, redaction, hook time limit); the decision engine as
  a pure function with its tier order and the floor; the must-never-allow
  fixture set drawn from every floor act in every spelling the guard-coverage
  corpus holds, plus a positive control; a broken-build harness (an allow-all
  engine stub, and a build with a named code home removed) that every refusal
  fixture is run against once; `planwright replay` over the recorded prompt
  envelopes of a window (a config setting), reporting the share settled per
  tier and every disagreement with what was answered, plus a synthetic
  envelope corpus committed for CI; the dependency-adoption record for Go, the
  SQLite build and mvdan/sh (FTS5 availability and licences recorded); the
  baseline of REQ-G1.8's measures at `docs/core-rewrite/baseline.md`,
  extending control-plane Task 1's, each measure with its method and
  collection command.
- **Done when:** the replay runs offline over the synthetic corpus in CI and
  over a recorded host window, printing its per-tier report; the replay exits
  non-zero when any must-never-allow fixture is allowed and the positive
  control shows it can; every refusal fixture fails against the broken-build
  harness; an unreadable, unknown-format or ambiguous input to the engine
  refuses or asks; the dependency list holds no database, queue or message
  client and the store opens in WAL mode with no service running; the engine's
  fixture suite runs in the repository's CI; the baseline file exists with
  each measure, its method and its command; no live session's behaviour
  changed.
- **Dependencies:** none
- **Citations:** D-2, D-4, D-14, D-15, D-23 · REQ-A1.3, REQ-A1.4, REQ-B1.2,
  REQ-B1.9, REQ-D1.1, REQ-D1.2, REQ-G1.8, REQ-H1.1, REQ-H1.4
- **Estimated effort:** 3 days

### Task 1.1 — Refuse bare mode and self-check the hook

- **Deliverables:** An explicit refusal of bare mode on every launch path;
  a first-tool-call check that the planwright PreToolUse hook ran, refusing
  to continue when it did not; fixtures for both.
- **Done when:** a launch with bare mode requested is refused with a message;
  a session started with the hook disabled stops at its first tool call with
  a message naming the missing hook; both fixtures run in CI.
- **Dependencies:** none
- **Citations:** D-20 · REQ-B1.8
- **Estimated effort:** half day

### Task 2 — Supersession bookkeeping

- **Deliverables:** Four amendment drafts, each on that bundle's own
  amendment branch (`planwright/<spec>/amendment-<n>`) and each walked with the
  operator in its own short `/spec-kickoff`, which signs it off and publishes
  it: control-plane marked Superseded with `**Superseded-by:**
  specs/core-rewrite/` (the operator setting that terminal status at its
  walk), its landed Task 1 recorded as standing, and each of its requirements
  and stub tasks named as carried here, dropped or deferred; universal-binary
  retiring its unbuilt verdict and migration tasks by reference bullets citing
  this bundle, its Task 10 delivery design recorded as carried into this
  bundle's Task 3, and the requirements those tasks owned named as carried or
  superseded; worker-permission-ergonomics recording that REQ-D replaces its
  guard mechanism and keeps its outcomes, superseding REQ-F1.2; execution-backends
  superseding D-5. Each follows spec-format's amendment ritual for a signed
  bundle (a new ID supersedes the old, with a changelog entry).
- **Done when:** each of the four amendments is signed off at its own kickoff
  and merged; the validator passes on all four bundles; control-plane carries
  the Superseded status and pointer; universal-binary's retired tasks each
  carry an Out-of-scope reference bullet citing this bundle; the superseding
  records for worker-permission-ergonomics REQ-F1.2 and execution-backends
  D-5 cite this bundle's D-7; each bundle's changelog carries its amendment
  entry.
- **Dependencies:** none
- **Citations:** D-7, D-16 · REQ-I1.1, REQ-I1.2, REQ-I1.3
- **Estimated effort:** 1 day

### Task 3 — Delivery of the executable and the shims

- **Deliverables:** Release assets per platform with provenance
  attestations and the checksum pin committed in the repository, carrying
  universal-binary Task 10's delivery design; first-use fetch that verifies
  against the committed pin and the attestation before running and refuses on
  a failed verification, with a fetch override that points it at a local
  fixture release; a CI install job per platform on an image with no
  toolchain; one stable command name on the Bash tool's path; the shim
  form every `scripts/<name>.sh` entry point takes when its body moves into
  the core, with a check that every shim execs the stable name; the shim's
  version check against the installed plugin manifest (D-23).
- **Done when:** a fresh install on each matrix platform in CI fetches,
  verifies and runs `planwright --version` and one verb with no toolchain
  present; a tampered asset and a wrong checksum served by the fixture release
  are each refused with no fallback; the shim check fails on a fixture shim
  that bypasses the stable name; a shim facing a mismatched executable
  version fails closed.
- **Dependencies:** Task 1
- **Citations:** D-2, D-23 · REQ-B1.1, REQ-B1.5, REQ-B1.7, REQ-B1.9
- **Estimated effort:** 2 days

### Task 4 — The mechanical-enforcement rule doc and its lens

- **Deliverables:** A doctrine rule doc stating REQ-A's line (every rule has a
  code home that refuses its violation; a rule an agent must remember is a
  defect), registered in the doctrine index; the open-gap record form for
  rules still in prose; the spec-draft design-phase and kickoff lens wiring
  that flags a requirement whose only enforcement is an instruction, kept
  within each touched skill's instruction budget (`scripts/check-instructions.sh`).
- **Done when:** the rule doc resolves through the rule-doc resolver; the
  doctrine index check passes; the instruction-budget check passes; a fixture
  bundle with an instruction-only requirement draws the lens flag and a clean
  fixture does not.
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1, REQ-A1.2, REQ-A1.5
- **Estimated effort:** 1 day

### Task 5 — The shadow hook in every session type

- **Deliverables:** `planwright hook pretooluse` registered beside the
  existing guards for every session type (headless worker, tmux session,
  tower, mission control, subagent), deciding and logging only; a shadow
  report of agreement and disagreement with the shell guards, floor
  disagreements (REQ-H1.2's failure rule) listed first; the shadow-window
  setting.
- **Done when:** a fixture replays the hook under each session type's profile
  and finds each decision in the decision log with its input digest; on this
  host the live log shows decisions from each session type; the report runs
  over the log and names every floor disagreement; no session's permission
  outcome changed.
- **Dependencies:** Task 3
- **Citations:** D-4, D-14 · REQ-D1.1, REQ-H1.2
- **Estimated effort:** 1 day

### Task 6 — Typed verbs for outward acts and the resolved-ref push check

- **Deliverables:** Typed verbs for push, pull-request writes, ready flip,
  merge admission, thread replies, messages, planwright's records and the
  kickoff's publish of a signed spec or amendment branch, each with a fixed
  argument schema whose identifiers match the session's row exactly; the
  message verb refusing a person as recipient without an approval record; the
  kickoff publish bound as REQ-D1.7 states (the core's own push command, the
  operator's sign-off record for that exact branch and commit, once per
  record), `scripts/kickoff-spec-push.sh` kept at its path as a shim; the push verb judging the
  destination refs git resolves (a pre-push check inside the verb); fixtures
  for the 2026-11-27 bypasses (option swallow, brace and glob expansion of
  option words) and every push spelling in the guard-coverage corpus; the
  floor acts as deny and ask rules in every shipped settings profile.
- **Done when:** every push fixture that targets a protected or foreign branch
  is refused by the verb whatever its spelling; the verb pushes the unit's own
  branch; the kickoff publish pushes a spec branch only with a matching
  sign-off record for that branch and commit, and a second push on the same
  record, another commit, another branch or no record is refused; a verb
  given an identifier outside its row is refused; each settings profile's
  floor rules are present and a check fails a profile missing one; the
  security pass is recorded.
- **Dependencies:** Task 1
- **Citations:** D-4, D-6 · REQ-A1.4, REQ-D1.3, REQ-D1.6, REQ-D1.7
- **Estimated effort:** 3 days

### Task 7 — Sandboxed worker profile on one program

- **Deliverables:** The worker and mission-control sandbox profiles (writes to
  worktree, scratch and shared git directory with hooks and config denied,
  every forge credential source masked, unsandboxed retry off, the sandbox's
  auto-allow of sandboxed commands on, sandbox required on a host whose
  capability row says sandbox-capable); mission control with no repository
  write; the parser tier for hosts without a sandbox, failing closed on any
  non-literal word and refusing outward acts in shell text; the store, record
  files, decision log, policy data and settings profiles write-denied to
  agents; a measured run on one program reporting prompts per unit against
  the baseline and every toolchain command that failed inside the sandbox.
- **Done when:** a profile check confirms the write list, credential mask,
  unsandboxed retry off and the required flag; a file-tool write to the store
  or a record file is denied in every shipped profile; on a sandbox-capable
  host a worker's in-worktree build, test and commit run with no prompt, a
  write outside its worktree is refused by the OS, and a shell push finds no
  credential; mission control's repository write is refused; the parser-tier
  fixtures (expansions, eval, source, alias, brace and glob in judged words,
  redirections, here-documents, a session-written file run) all ask; the
  measured-run report exists with each of these host results; before the
  profile decides live its shadow record shows a closed window (REQ-H1.2) and
  its slice report is recorded (REQ-G1.8); the security pass is recorded.
- **Dependencies:** Task 5, Task 6
- **Citations:** D-5, D-22 · REQ-C1.5, REQ-D1.4, REQ-D1.5, REQ-D1.6,
  REQ-D1.8, REQ-G1.8, REQ-H1.2
- **Estimated effort:** 3 days

### Task 8 — Engine live, the prompts table and the supervisor in the core

- **Deliverables:** The engine deciding live at the hook (allow, deny, ask)
  with the routine classes as policy data an operator tunes without code; the
  prompts table storing prompts whole; the owner inbox with delivered, read and
  answered states and redelivery; per-program prompt visibility; the
  supervisor spawning the installed `claude`, owning its pipes with one writer
  and each worker's process group; the kill switch over the retained
  pre-shim shell bodies, thrown only on an operator approval record.
- **Done when:** a routine-class call is allowed with no prompt and logged; a
  floor call is denied even with the engine's policy data set to allow it; a
  policy-data entry naming a floor act is rejected at load and the previous
  policy kept; an ask lands in the owner's inbox with its full payload and is
  redelivered until acknowledged; a program cannot list another program's
  prompts; a large frame write does not interleave and stop ends every process
  of a fixture worker's group, grandchild included; the kill switch, thrown on
  a record, returns sessions to the shell path with the engine left in shadow
  and the floor still denying, and a throw without a record is refused; with
  the switch off, the FIFO supervisor is on no launch path; before the engine
  decides live its shadow record shows a closed window (REQ-H1.2) and its
  slice report is recorded (REQ-G1.8).
- **Dependencies:** Task 2, Task 7
- **Citations:** D-4, D-7, D-9, D-13, D-14 · REQ-A1.3, REQ-D1.2, REQ-E1.1,
  REQ-E1.2, REQ-E1.3, REQ-E1.4, REQ-F1.2, REQ-G1.8, REQ-H1.2, REQ-H1.3
- **Estimated effort:** 4 days

### Task 9 — Service mode: delivery, escalation, ownership and restart

- **Deliverables:** The per-user daemon with its unit templates (systemd user
  unit, launchd agent) shipped as data, installing one staying the operator's
  dotfiles act (D-22), enabled only through a recorded operator yes; its local
  socket usable by its own user only, the caller's row taken from the
  harness's identity (D-23); push delivery to owners within seconds; an escalation timer on every pending prompt ending in an operator
  push; duties on timers; process ownership with cgroup scopes on Linux;
  re-exec onto the installed version after an update and new sessions on the
  installed root; the doctor's per-host capability lines.
- **Done when:** in a fixture daemon started by the test harness, a prompt
  reaches its owner's inbox within the configured bound in a timed fixture;
  an unanswered prompt escalates to the notification seam at its timer, and
  in direct mode at the next core call; the engine and verb fixture suites
  give identical decisions in direct and service mode; a socket call naming
  another session's id is judged as the harness's session; a simulated update
  moves the daemon and new sessions onto the new root with no stale-root
  session left unraised; a host without the operator's yes refuses to enable
  it; the doctor prints each capability and each lack; on a host where the
  operator enabled service mode, the delivery bound and a real update are run
  and their results recorded in the task's PR; before the daemon decides live
  its shadow record shows a closed window (REQ-H1.2) and its slice report is
  recorded (REQ-G1.8).
- **Dependencies:** Task 8
- **Citations:** D-3, D-9, D-13, D-23 · REQ-B1.3, REQ-B1.4, REQ-B1.9,
  REQ-E1.3, REQ-E1.4, REQ-F1.4, REQ-G1.8, REQ-H1.2
- **Estimated effort:** 3 days

### Task 10 — Sessions, events and leases in the store

- **Deliverables:** One sessions row per session with register, recover,
  relaunch and retire as single transactions; liveness from the recorded
  process; events and leases in the store; event dedupe at the source with
  control-plane REQ-D's meaning, its verification entries listed by ID in the
  task's fixture index; the text export of work products (REQ-B1.6); the shell
  registry and lock entry points as shims.
- **Done when:** a recover keeps the worker's owner in a fixture; a completed
  row is never removed while its process lives; a crash mid-transaction leaves
  the prior state; liveness of a fixture worker needs no process scan; a
  repeat, stale or off-order event is dropped before it wakes a session,
  routine events are coalesced, drops are counted, and an unreadable one is
  delivered; a change to a rule, follow-up, decision, ledger row, approval or
  capability row writes its text export, and a fixture rebuilds operational
  state from git, the forge fixture and the logs; the registry and lock shims
  pass the repository's full test suite; before the store's session path
  decides live its shadow record shows a closed window (REQ-H1.2) and its
  slice report is recorded (REQ-G1.8).
- **Dependencies:** Task 8
- **Citations:** D-13, D-15, D-16 · REQ-A1.3, REQ-B1.6, REQ-E1.7, REQ-F1.1,
  REQ-F1.3, REQ-G1.8, REQ-H1.2
- **Estimated effort:** 3 days

### Task 11 — The step state machine and records stamped by the core

- **Deliverables:** Units, points and steps as one state machine in the store;
  step begin and end verbs that stamp times from the core's clock and heads
  from git and accept neither as arguments; prompt- and skill-kind steps
  recordable only after their prompt's delivery; point completion refused
  while a resolved step lacks a record; convergence completion refused while
  the last pass applied a change; the record export that pull-request bodies
  render; `step-record.sh` and `step-run.sh` as shims.
- **Done when:** fixtures show a record with an agent-supplied time or head
  refused, a prompt step recorded before its delivery refused, a completion
  with a missing step refused, a convergence completion after an applying
  pass refused, an unreadable record input refused, and a copied or renamed
  recorder recording nothing; the existing audit and render outputs are
  unchanged for a valid run (the repository's step-record and step-run
  suites); before the state machine decides live its shadow record shows a
  closed window (REQ-H1.2) and its slice report is recorded (REQ-G1.8).
- **Dependencies:** Task 10
- **Citations:** D-10, D-11, D-18 · REQ-A1.3, REQ-C1.1, REQ-C1.2, REQ-C1.3,
  REQ-C1.4, REQ-C1.5, REQ-G1.8, REQ-H1.2
- **Estimated effort:** 4 days

### Task 12 — Readiness computed once for every unit kind

- **Deliverables:** One ready-flip readiness and audit computation over the
  store and the forge's current state, the same for spec tasks, flights and
  mission-control launches; configuration resolved from the session's row;
  the ready-flip helper and the readiness check as callers of it; the
  hosted-review run rule (once on the final head, once after each code fix
  round) reported as a readiness defect when broken.
- **Done when:** a flight, a spec task and a mission-control launch with the
  same records produce the same readiness verdict, read from the forge
  fixture's current state; a session with a wrong or missing overlay variable
  still reads its own program's config; a pull request with a hosted-review run
  on a non-final head, with no code fix round between, reports the defect;
  the ready-flip helper serves a flight; before the computation decides live
  its shadow record shows a closed window (REQ-H1.2) and its slice report is
  recorded (REQ-G1.8).
- **Dependencies:** Task 11
- **Citations:** D-11, D-17 · REQ-C1.6, REQ-C1.8, REQ-G1.3, REQ-G1.8,
  REQ-H1.2
- **Estimated effort:** 2 days

### Task 13 — Approvals as records, the request ledger, generated handovers

- **Deliverables:** The approval record (quoted words, time, text hash, act,
  target, commit) written by the core from the operator's harness-delivered
  answer, never from a model-supplied argument, single-use unless it carries
  a scope with an expiry, and the core performing an approved act on a match;
  the request ledger carried with control-plane
  REQ-J's meaning, its verification entries listed by ID in the task's
  fixture index; handover briefs generated from the store and diffed, take
  refused on a request or commitment neither acknowledged by the successor
  nor waived by an operator record; the idle-wait end and
  relaunch from a generated brief; the supervisor handover threshold from the
  measured cost curve.
- **Done when:** a relayed go with a matching record performs its act with no
  model carrying it, and one without a record, with a mismatched commit, with
  an expired scope, or written by a model session is refused; a request captured
  on arrival survives a handover and blocks take until acknowledged or
  waived, and a closure without cited evidence is refused; a generated brief
  lists every open unit, request, commitment and duty in the fixture store
  and prints its diff against the previous one; a worker whose wait passes
  the cache lifetime ends and is relaunched from a generated brief in a
  fixture; the threshold default cites its measurement; before approvals and
  handovers decide live their shadow record shows a closed window (REQ-H1.2)
  and the slice report is recorded (REQ-G1.8).
- **Dependencies:** Task 10, Task 11
- **Citations:** D-8, D-12, D-16, D-17 · REQ-C1.7, REQ-E1.5, REQ-E1.6,
  REQ-G1.7, REQ-G1.8, REQ-H1.2
- **Estimated effort:** 4 days

### Task 14 — Review loops sized to the diff and stopped mechanically

- **Deliverables:** Lens selection from the reviewed diff, with later passes
  reviewing only what the previous pass changed; stop on the first pass that
  applies nothing; a round cap and wall-clock budget as config ending the loop
  with a recorded outcome; a measurement of where review time goes before and
  after.
- **Done when:** a fixture loop whose second pass applies nothing stops there;
  a later pass's lens set covers only the files the previous pass changed;
  reaching the cap or budget records the outcome and runs no further pass; the
  before-and-after measurement is recorded as the slice report (REQ-G1.8);
  before the loop rule decides live its shadow record shows a closed window
  (REQ-H1.2).
- **Dependencies:** Task 11
- **Citations:** D-18 · REQ-G1.1, REQ-G1.2, REQ-G1.8, REQ-H1.2
- **Estimated effort:** 2 days

### Task 15 — CI rounds, the usage ladder and model tiers

- **Deliverables:** The per-file test-time budget (`scripts/check-test-time.sh`)
  judging only files the pull request's diff touches, with one retry for an
  untouched file; the usage ladder in the core failing closed on an
  unreadable or refused read; model and effort tiers resolved by the core per
  launch kind and step; a defaults check failing a shipped default change
  that cites no measurement.
- **Done when:** an untouched file over budget is retried and reported, not
  failed, and a touched one fails; an unreadable usage read holds launches and
  raises an event; the tier resolver's fixtures pass; the defaults check fails
  a fixture default change with no cited measurement; before each mechanism
  decides live its shadow record shows a closed window (REQ-H1.2) and the
  slice report is recorded (REQ-G1.8).
- **Dependencies:** Task 10
- **Citations:** D-17, D-19 · REQ-G1.4, REQ-G1.5, REQ-G1.6, REQ-G1.8,
  REQ-H1.2
- **Estimated effort:** 2 days

### Task 16 — Measure the slices and retire the shell guards

- **Deliverables:** The aggregate report over the slice reports against the
  baseline for every measure of REQ-G1.8; the shadow-window record showing no
  floor disagreement; the human-directed removal of the
  enumerate-the-spellings shell guards on an operator approval record (REQ-E1.5);
  the prose rules whose code homes landed retired against their fixtures, with
  a check that fails when a retired rule names no fixture or its fixture
  passes against the broken-build harness's build with that code home removed.
- **Done when:** the report shows each measure before and after; the shadow
  record covers the configured window with zero floor disagreements; the shell
  guards are absent from every shipped profile only after the operator's
  approval record for the removal exists; the retirement check passes and
  fails on a fixture retired rule with no refusing fixture.
- **Dependencies:** Task 9, Task 12, Task 13, Task 14, Task 15
- **Citations:** D-1, D-14 · REQ-A1.2, REQ-D1.9, REQ-G1.8
- **Estimated effort:** 2 days

## Awaiting input

(none yet)

## Deferred

- **Shared knowledge base and search receipt.** One searchable index across
  programs, refreshed when a research or review doc lands, with drafting,
  kickoff and UI steps that must cite a search receipt. Deferred because: a
  separate concern with its own seed, and the store this spec builds is its
  natural home. Confidence: high.
  **Gate:** GATE(when: task 10 completed).
  Citations: D-21; hub follow-up f-50 (Sources).
- **Mission-control mod redesign for both surfaces.** Deferred because: a UI
  concern that reads the store once it exists. Confidence: high.
  **Gate:** GATE(when: task 10 completed).
  Citations: D-21; hub follow-up f-41 (Sources).
- **Cross-host transport over SSH stdio.** The typed verbs tunnelled to the
  offload host. Deferred because: today's SSH rung works and the verbs must
  settle first. Confidence: medium.
  **Gate:** GATE(when: task 9 completed).
  Citations: D-21; the core-substrate research report (Sources).

- **Sandbox package on planwright's Linux host.** The operator-approved
  dotfiles change that adds the sandbox's missing package (D-22), routed by
  mission control; Task 7's host results need it. Deferred because: machine
  setup is never a task of this bundle. Confidence: high.
  **Gate:** GATE(when: task 5 completed).
  Citations: D-22.
- **Service unit install on a host.** The operator's dotfiles change that
  installs Task 9's unit template where they choose service mode (D-22);
  Task 9's real-host results need it. Deferred because: machine setup is never
  a task of this bundle. Confidence: high.
  **Gate:** GATE(when: task 8 completed).
  Citations: D-22, D-3.

## Out of scope

- Changing the human-gates list; machine setup on any host; employer data
  (see `requirements.md` Out of scope).
