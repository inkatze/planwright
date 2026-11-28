# Core rewrite — Tasks

**Status:** Draft
**Last reviewed:** 2026-11-27
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

- **Deliverables:** The Go module and its build for the supported platforms;
  the store schema (sessions, leases, events, prompts, inbox, approvals, rules,
  duties, step records, decision log) with migrations; the decision engine as
  a pure function with its tier order and the floor; the must-never-allow
  fixture set drawn from every floor act in every spelling the guard-coverage
  corpus holds, plus a positive control; `planwright replay` over the recorded
  prompt envelopes of a chosen window, reporting the share settled per tier and
  every disagreement with what was answered; the dependency-adoption record
  for Go, the SQLite build and mvdan/sh (FTS5 availability confirmed); the
  baseline of REQ-G1.8's measures, extending control-plane Task 1's.
- **Done when:** the replay runs offline over a recorded window and prints its
  per-tier report; the replay exits non-zero when any must-never-allow fixture
  is allowed and the positive control shows it can; the engine's fixture suite
  runs in the repository's CI; the baseline file exists with each measure and
  its method; no live session's behaviour changed.
- **Dependencies:** none
- **Citations:** D-2, D-4, D-14, D-15 · REQ-B1.2, REQ-D1.1, REQ-D1.2, REQ-G1.8,
  REQ-H1.1, REQ-H1.4
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

- **Deliverables:** A control-plane change marking it Superseded with
  `**Superseded-by:** specs/core-rewrite/`, its landed Task 1 recorded as
  standing; a universal-binary amendment retiring Tasks 9 to 14 by reference
  bullets citing this bundle; a worker-permission-ergonomics amendment
  recording that REQ-D replaces its guard mechanism and keeps its outcomes,
  and amending REQ-F1.2; an execution-backends amendment of D-5; each carried
  through that bundle's amendment ritual.
- **Done when:** the validator passes on all four touched bundles; control-plane
  carries the Superseded status and pointer; universal-binary's Tasks 9 to 14
  each carry an Out-of-scope reference bullet citing this bundle; the amended
  REQ-F1.2 and D-5 cite this bundle's D-7.
- **Dependencies:** none
- **Citations:** D-7, D-16 · REQ-I1.1, REQ-I1.2, REQ-I1.3
- **Estimated effort:** 1 day

### Task 3 — Delivery of the executable and the shims

- **Deliverables:** Release assets per platform with checksums and provenance;
  first-use fetch that verifies before running and refuses on a failed
  verification; one stable command name on the Bash tool's path; the shim
  form every `scripts/<name>.sh` entry point takes when its body moves into
  the core, with a check that every shim execs the stable name.
- **Done when:** a fresh install on each supported platform in CI fetches,
  verifies and runs `planwright --version` with no toolchain present; a
  tampered asset is refused; the shim check fails on a fixture shim that
  bypasses the stable name.
- **Dependencies:** Task 1
- **Citations:** D-2 · REQ-B1.1, REQ-B1.5, REQ-B1.7
- **Estimated effort:** 2 days

### Task 4 — The mechanical-enforcement rule doc and its lens

- **Deliverables:** A doctrine rule doc stating REQ-A's line (every rule has a
  code home that refuses its violation; a rule an agent must remember is a
  defect), registered in the doctrine index; the open-gap record form for
  rules still in prose; the spec-draft design-phase and kickoff lens wiring
  that flags a requirement whose only enforcement is an instruction, kept
  within each touched skill's instruction budget.
- **Done when:** the rule doc resolves through the rule-doc resolver; the
  doctrine index check passes; a fixture bundle with an instruction-only
  requirement draws the lens flag.
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1, REQ-A1.2, REQ-A1.5
- **Estimated effort:** 1 day

### Task 5 — The shadow hook in every session type

- **Deliverables:** `planwright hook pretooluse` registered beside the
  existing guards in the worker, tower and mission-control profiles and for
  subagents, deciding and logging only; a shadow report of agreement and
  disagreement with the shell guards, floor disagreements listed first.
- **Done when:** the shadow hook's decisions appear in the decision log for
  each session type on this host; the report runs over the log and names
  every floor disagreement; no session's permission outcome changed.
- **Dependencies:** Task 3
- **Citations:** D-4, D-14 · REQ-D1.1, REQ-H1.2
- **Estimated effort:** 1 day

### Task 6 — Typed verbs for outward acts and the resolved-ref push check

- **Deliverables:** Typed verbs for push, pull-request writes, ready flip,
  merge admission, thread replies, planwright's records and the kickoff's
  publish of a signed spec branch (resumable from the signed anchor), each
  validating its arguments against the session's row; the push verb judging the
  destination refs git resolves (a pre-push check inside the verb); fixtures
  for the 2026-11-27 bypasses (option swallow, brace and glob expansion of
  option words) and every push spelling in the guard-coverage corpus; the
  floor acts as deny and ask rules in every shipped settings profile.
- **Done when:** every push fixture that targets a protected or foreign branch
  is refused by the verb whatever its spelling; the verb pushes the unit's own
  branch; each settings profile's floor rules are present and a check fails a
  profile missing one; the security pass is recorded.
- **Dependencies:** Task 1
- **Citations:** D-4, D-6 · REQ-D1.3, REQ-D1.6, REQ-D1.7
- **Estimated effort:** 3 days

### Task 7 — Sandboxed worker profile on one program

- **Deliverables:** The worker and mission-control sandbox profiles (writes to
  worktree, scratch and shared git directory with hooks and config denied,
  forge credentials masked, unsandboxed retry off, sandbox required where the
  host advertises it); mission control with no repository write; the parser
  tier for hosts without a sandbox, failing closed on any non-literal word;
  the store and record files write-denied to agents; a measured run on one
  program reporting prompts per unit against the baseline and every toolchain
  command that failed inside the sandbox.
- **Done when:** on a sandbox-capable host a worker's in-worktree build, test
  and commit run with no prompt and a write outside its worktree is refused by
  the OS; mission control's repository write is refused; the parser-tier
  fixtures (expansions, eval, source, alias, brace and glob in judged words)
  all ask; the measured-run report exists; the security pass is recorded.
- **Dependencies:** Task 5, Task 6
- **Citations:** D-5, D-22 · REQ-C1.5, REQ-D1.4, REQ-D1.5, REQ-D1.8
- **Estimated effort:** 3 days

### Task 8 — Engine live, the prompts table and the supervisor in the core

- **Deliverables:** The engine deciding live at the hook (allow, deny, ask)
  with the routine classes as policy data an operator tunes without code; the
  prompts table storing prompts whole; the owner inbox with delivered, read and
  answered states and redelivery; per-program prompt visibility; the
  supervisor spawning the installed `claude`, owning its pipes with one writer
  and each worker's process group; the kill switch.
- **Done when:** a routine-class call is allowed with no prompt and logged; a
  floor call is denied even with the engine's policy data set to allow it; an
  ask lands in the owner's inbox with its full payload and is redelivered
  until acknowledged; a program cannot list another program's prompts; the
  kill switch returns sessions to the shell path and the floor still denies;
  the FIFO supervisor is no longer on any launch path behind the switch.
- **Dependencies:** Task 2, Task 7
- **Citations:** D-4, D-7, D-9, D-13, D-14 · REQ-D1.2, REQ-E1.1, REQ-E1.2,
  REQ-E1.3, REQ-F1.2, REQ-H1.3
- **Estimated effort:** 4 days

### Task 9 — Service mode: delivery, escalation, ownership and restart

- **Deliverables:** The per-user daemon (systemd user unit, launchd agent),
  enabled only through a recorded operator yes; push delivery to owners within
  seconds; an escalation timer on every pending prompt ending in an operator
  push; duties on timers; process ownership with cgroup scopes on Linux;
  re-exec onto the installed version after an update and new sessions on the
  installed root; the doctor's per-host capability lines.
- **Done when:** with service mode enabled, a prompt reaches its owner's inbox
  within the configured bound in a timed fixture; an unanswered prompt
  escalates to the notification seam at its timer; an update moves the daemon
  and new sessions onto the new root with no stale-root session left
  unraised; a host without the operator's yes refuses to enable it; the
  doctor prints each capability and each lack.
- **Dependencies:** Task 8
- **Citations:** D-3, D-9, D-13 · REQ-B1.3, REQ-B1.4, REQ-E1.3, REQ-E1.4,
  REQ-F1.4
- **Estimated effort:** 3 days

### Task 10 — Sessions, events and leases in the store

- **Deliverables:** One sessions row per session with register, recover,
  relaunch and retire as single transactions; liveness from the recorded
  process; events and leases in the store; event dedupe at the source with
  control-plane REQ-D's meaning; the shell registry and lock entry points as
  shims.
- **Done when:** a recover keeps the worker's owner in a fixture; a completed
  row is never removed while its process lives; liveness of a fixture worker
  needs no process scan; a repeat, stale or off-order event is dropped before
  it wakes a session and an unreadable one is delivered; the registry and lock
  shims pass the existing suites.
- **Dependencies:** Task 8
- **Citations:** D-13, D-15, D-16 · REQ-E1.7, REQ-F1.1, REQ-F1.3
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
  with a missing step refused, and a convergence completion after an applying
  pass refused; the existing audit and render outputs are unchanged for a
  valid run.
- **Dependencies:** Task 10
- **Citations:** D-10, D-11, D-18 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4,
  REQ-C1.5
- **Estimated effort:** 4 days

### Task 12 — Readiness computed once for every unit kind

- **Deliverables:** One readiness and audit computation over the store and
  the forge's current state, the same for spec tasks, flights and
  mission-control launches; configuration resolved from the session's row;
  the ready-flip helper and the readiness check as callers of it; the
  hosted-review run rule (once on the final head, once after a code fix round)
  reported as a readiness defect when broken.
- **Done when:** a flight and a spec task with the same records produce the
  same readiness verdict; a session with a wrong or missing overlay variable
  still reads its own program's config; a pull request with a hosted-review run
  on a non-final head reports the defect; the ready-flip helper serves a
  flight.
- **Dependencies:** Task 11
- **Citations:** D-11, D-17 · REQ-C1.6, REQ-C1.8, REQ-G1.3
- **Estimated effort:** 2 days

### Task 13 — Approvals as records, the request ledger, generated handovers

- **Deliverables:** The approval record (quoted words, time, text hash, act,
  target) written at the operator-facing surface and the core performing an
  approved act on a match; the request ledger carried with control-plane
  REQ-J's meaning; handover briefs generated from the store and diffed, take
  refused on an unacknowledged request or commitment; the idle-wait end and
  relaunch from a generated brief; the supervisor handover threshold from the
  measured cost curve.
- **Done when:** a relayed go with a matching record performs its act with no
  model carrying it, and one without a record is refused; a request captured
  on arrival survives a handover and blocks take until acknowledged; a worker
  whose wait passes the cache lifetime ends and is relaunched from a generated
  brief in a fixture; the threshold default cites its measurement.
- **Dependencies:** Task 10
- **Citations:** D-8, D-12, D-16, D-17 · REQ-C1.7, REQ-E1.5, REQ-E1.6,
  REQ-G1.7
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
  before-and-after measurement is recorded.
- **Dependencies:** Task 11
- **Citations:** D-18 · REQ-G1.1, REQ-G1.2
- **Estimated effort:** 2 days

### Task 15 — CI rounds, the usage ladder and model tiers

- **Deliverables:** The per-file test-time budget judging only touched files,
  with one retry for an untouched file; the usage ladder in the core failing
  closed on an unreadable or refused read; model and effort tiers resolved by
  the core per launch point and step; shipped default changes only with their
  measurement cited.
- **Done when:** an untouched file over budget is retried and reported, not
  failed, and a touched one fails; an unreadable usage read holds launches and
  raises an event; the tier resolver's fixtures pass; each changed default
  names its measurement.
- **Dependencies:** Task 10
- **Citations:** D-17, D-19 · REQ-G1.4, REQ-G1.5, REQ-G1.6
- **Estimated effort:** 2 days

### Task 16 — Measure the slices and retire the shell guards

- **Deliverables:** The slice report against the baseline for every measure of
  REQ-G1.8; the shadow-window record showing no floor disagreement; the
  human-directed removal of the enumerate-the-spellings shell guards, the
  prose rules whose code homes landed retired against their fixtures.
- **Done when:** the report shows each measure before and after; the shadow
  record covers the configured window with zero floor disagreements; the shell
  guards are absent from every shipped profile only after the operator's
  recorded go; each retired prose rule names its refusing fixture.
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

## Out of scope

- Changing the human-gates list; machine setup on any host; employer data
  (see `requirements.md` Out of scope).
