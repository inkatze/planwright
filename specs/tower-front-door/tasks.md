# Tower front door — Tasks

**Status:** Ready
**Last reviewed:** 2026-10-10
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order. The eval task deliberately gates the docs
task (D-13): no user-facing doc surface claims routing behavior the
router has not demonstrated (REQ-B1.6).

## Tasks

### Task 1 — Flight-rules doctrine doc

- **Deliverables:** `doctrine/flight-rules.md`: the per-request routing
  rule (automatic, judgment, and advisory signals; the stated-grounds
  form — the fired trigger and its one-line evidence; the inline
  evidence bound for routing; the one-sentence two-way override,
  recognized semantically with the D-5 exemplars illustrative, with
  stated reservation; the REQ-C1.6 decomposition rule), the flight
  boundary per REQ-C1.6 (mutating-only, the mid-offload re-route rule,
  and the mid-flight rule: a flight whose scope outgrows its route parks
  behind its hard pause and returns for re-routing), the audit-record
  content contract and specless-traceability definition, the
  bounded-or-surfaced statement of the survival guarantees, and the
  flight-rules first-use gloss.
- **Done when:** the doc states the routing rule, the flight boundary,
  the record contract, the traceability definition, and the survival
  guarantees; every stated rule cites its D-ID; the doc resolves through
  the rule-doc chain and is enrolled in the doctrine index
  (`check-doctrine-index`); the instruction-budget guard passes with the
  doc enrolled.
- **Dependencies:** none
- **Citations:** D-1, D-4, D-5, D-6, D-10 · REQ-B1.2, REQ-B1.3, REQ-B1.4,
  REQ-C1.6, REQ-E1.1, REQ-E1.4, REQ-F1.6, REQ-H1.4
- **Estimated effort:** 1 day

### Task 2 — Vocabulary inversion, definitional sites

- **Deliverables:** the glossary supersession in
  `doctrine/spec-format.md` (Tower re-defined, Orchestrator minted with a
  one-line distinction from Operator the human, the transitional note
  covering both older prose and tower-named scripts/config), the
  consumer-naming update in `doctrine/work-placement.md`, the
  opening-vocabulary update in `docs/fleet.md`, and the "control tower"
  line of `skills/orchestrate/SKILL.md`'s description re-termed; a
  pin-check for the glossary entries and the transitional note; a dated
  entry in the meta-spec's own versioning section (no version bump — no
  authoring rule changes).
- **Done when:** the four definitional sites use the new vocabulary; the
  transitional note covers both older prose and tower-named
  scripts/config; the Orchestrator entry carries the Operator
  distinction; the glossary pin-check exists and passes; lint and the
  instruction-budget guard pass.
- **Dependencies:** 1
- **Citations:** D-2 · REQ-H1.1, REQ-H1.2
- **Estimated effort:** half day

### Task 3 — Flight branch and worktree grammar

- **Deliverables:** the additive spec-format grammar amendment for
  `planwright/flight/<flight-id>` and the `flight-<flight-id>` worktree
  suffix (the flattened single-segment form of the spec-format D-37
  placement rule);
  `flight` reserved at the identifier grammar level (the validator's
  screening plus every interpolation site); the flight-id format (kebab
  slug plus short uid) defined with the never-reuse rule; the
  `specs/_flights/` record-directory classification added to the
  meta-spec (underscore-screened, skipped by bundle validation, a
  non-accumulator record class) with its own dated changelog entry (no
  version bump; verified no conforming bundle breaks); branch-parser
  cases added where `planwright/` branches are parsed.
- **Done when:** a flight branch parses at every site the branch-parser
  tests enumerate; a spec named `flight` is refused by the validator;
  `spec-validate.sh` skips `specs/_flights/`; the flight-id format and
  never-reuse rule are unit-tested; the meta-spec changelog entry
  exists.
- **Dependencies:** none
- **Citations:** D-11 · REQ-C1.1
- **Estimated effort:** half day

### Task 4 — The `/tower` skill core

- **Deliverables:** `skills/tower/SKILL.md`: session bring-up (posture
  check, start-of-session reconstruction hook point), the router with
  stated grounds, the two-way override, the conversational contract per
  the operator-dialogue disciplines, the escalation flow (invoking
  `/spec-draft` with fold-detection, presenting the one-page case,
  offering — never starting — `/spec-kickoff`), and the status-on-demand
  window behavior (REQ-A1.5); the description authored as a selector;
  the skill enrolled in the instruction-budget guard.
- **Done when:** the skill loads in a fresh session without a guard or
  permission error and completes a scripted bring-up turn; routing
  statements carry grounds in the scripted bring-up scenarios (the full
  route corpus is Task 11's gate); the description reads as a selector
  (trigger and boundary, no procedure); the instruction-budget guard
  passes with the new surface enrolled.
- **Dependencies:** 1, 2
- **Citations:** D-1, D-3, D-4, D-5, D-12, D-15 · REQ-A1.1, REQ-A1.2,
  REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-B1.1, REQ-B1.3, REQ-B1.4, REQ-D1.1,
  REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-G1.2
- **Estimated effort:** 2 days

### Task 5 — Visual-flight dispatch path

- **Deliverables:** the flight dispatch flow: worktree and branch
  creation through the Claude Code native worktree mechanism (never raw
  `git worktree`), registered via the existing worktree tracking, using
  the Task 3 grammar; rung selection through `/offload`'s placement
  logic and the backend seam; the dispatch-time concurrency check
  (REQ-C1.5); the resolved plugin-root pair surfaced at dispatch; and
  the worker brief carrying doctrine load (the worker manifest set), the
  configured `review_sequence`, and the audit-record instructions.
- **Done when:** a small ask dispatches end-to-end into an isolated
  worktree worker that converges and lands its record on both arms
  (draft PR with remote and `gh`; branch plus record file otherwise); a
  read-only offload creates no flight identity; a flight beyond the
  `max_parallel_units` value is declined with a stated re-ask; the PR is
  created draft and never flipped by the tower; the design-level review
  confirms no placement logic exists outside the `/offload` seam.
- **Dependencies:** 3, 4
- **Citations:** D-7, D-11 · REQ-B1.5, REQ-C1.1, REQ-C1.2, REQ-C1.3,
  REQ-C1.4, REQ-C1.5, REQ-C1.6, REQ-G1.5
- **Estimated effort:** 1 day

### Task 6 — Flight record and PR body

- **Deliverables:** the flight record template implementing the REQ-E1.1
  content contract on the existing PR-body conventions, rendered
  human-first per REQ-E1.5 (human what/why/verification lead, no restated
  prompt, the full contract collapsed below, ask sanitized and
  markup-neutralized); the adaptive-home selection (PR body with remote
  and `gh`; the committed per-flight record file at
  `specs/_flights/<flight-id>.md` on the flight branch otherwise),
  determined and declared at routing time.
- **Done when:** both arms produce the full content contract with the
  human-first lead and no restated prompt; the ask is sanitized and
  markup-neutralized; the routing-time home declaration is emitted; the
  no-remote arm commits exactly one record file on the flight branch;
  template structure is unit-tested.
- **Dependencies:** 1, 5
- **Citations:** D-6 · REQ-E1.1, REQ-E1.2, REQ-E1.4, REQ-E1.5
- **Estimated effort:** 1 day

### Task 7 — Shared flight sweep and derived index

- **Deliverables:** one sweep implementation (script) deriving in-flight
  state from durable evidence (flight branches, PRs, worker liveness
  including backend runtime evidence, record files), surfacing the
  resolved plugin-root pair in its render; the derived never-committed
  index under the fleet home; tower start-of-session sweep wiring (a
  deterministic hook, with the skill bring-up step as fallback); flight
  residues riding the existing fleet cleanup sweep.
- **Done when:** deleting the index and re-sweeping reproduces it
  equivalently (stable serialization; timestamps excluded); the index
  path is untracked; a fresh tower session reports what landed and what
  is queued from evidence alone; the sweep consults backend liveness
  before declaring a flight dead.
- **Dependencies:** 3, 6
- **Citations:** D-9 · REQ-E1.3, REQ-F1.3, REQ-F1.4, REQ-F1.6
- **Estimated effort:** 1 day

### Task 8 — `/resume` tower mode

- **Deliverables:** the tower-level sweep mode in `/resume`, consuming
  the Task 7 sweep implementation unchanged.
- **Done when:** `/resume`'s tower mode and the tower's start sweep
  render from the same implementation, asserted at the call sites (no
  second derivation path, Task 7's implementation unmodified by this
  task).
- **Dependencies:** 7
- **Citations:** D-9 · REQ-F1.4
- **Estimated effort:** half day

### Task 9 — Attention integration and crash policy

- **Deliverables:** deterministic flight lifecycle pushes into the
  attention store (dispatch, awaiting-decision, completion with the
  landing reference) via hooks and scripts; decision-queue and
  status-on-demand rendering in the tower conversation through the
  existing fleet-attention seam; flight registration so the fleet
  worker crash-loop knobs cover flight workers, with relaunch resuming
  the flight's own worktree and branch.
- **Done when:** all three lifecycle pushes (dispatch,
  awaiting-decision, completion) reach the store with the tower process
  stopped (no polling in the loop); a killed worker follows backoff then
  surfaces at the disable threshold; the guarantee statements on the
  surfaces this task ships use the bounded-or-surfaced form.
- **Dependencies:** 5
- **Citations:** D-8, D-10 · REQ-F1.1, REQ-F1.2, REQ-F1.5, REQ-F1.6
- **Estimated effort:** 1 day

### Task 10 — Tower posture extension

- **Deliverables:** the reviewed extension of the tower permission
  posture for the tower session's shapes (allow additions or guard
  shapes only); the deny floor untouched; the allow/deny delta document,
  enumerating the routine command shapes it covers, produced for human
  sign-off.
- **Done when:** the enumerated routine command shapes are allow-listed
  and run without permission stalls; the deny floor is byte-identical or
  strictly wider; guard tests assert zero false-allows on the enumerated
  new shapes and that the history-rewrite denies (force-push, amend,
  squash, rebase) hold under the posture; the allow/deny delta document
  exists and carries the human's sign-off.
- **Dependencies:** 4
- **Citations:** D-14 · REQ-A1.3, REQ-G1.1, REQ-G1.3, REQ-G1.4
- **Estimated effort:** 1 day

### Task 11 — Routing behavioral eval

- **Deliverables:** the tower's eval artifact-emission seam (eval-only
  decision-log and sign-off artifacts the harness grades, per the
  kickoff-eval precedent — never a real sign-off, REQ-G1.2); eval
  fixtures derived from the five acceptance scenarios (chat-only,
  split-screen, refusal to merge, escalation, walk-away/resume) plus the
  test-spec case set (consecutive asks with no mode state, the four
  escalation cases including large-but-safe-must-not-file, the three
  override cases, kickoff-never-started, dispatch-on-explicit-go-only),
  asserting route choice, stated grounds, override compliance with
  stated reservation, and the merge refusal.
- **Done when:** every fixture passes its grader assertions and the
  structural floor passes on the behavioral-eval harness; the
  harness-operability caveat is recorded beside the suite (the fixtures
  README).
- **Dependencies:** 4
- **Citations:** D-13 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4,
  REQ-B1.5, REQ-B1.6, REQ-D1.3, REQ-D1.4, REQ-G1.1
- **Estimated effort:** 1 day

### Task 12 — Docs inversion

- **Deliverables:** README and getting-started led by `/tower`; the
  demotion moves (`/orchestrate`, `/execute-task`, `/resume`, `/offload`
  to advanced/architecture docs under existing names); the front-facing
  set unchanged and `/self-review` / `/polish` unchanged in place; the
  two permanent human controls (the draft→ready flip and the merge)
  restated as unchanged on both flight rules, reconciling the README's
  two-controls wording with orchestration-modes doctrine; the first-use
  flight-rules gloss on each touched surface; the README-lead and
  demotion-placement pin-checks and the flight-rules gloss check
  authored.
- **Done when:** a newcomer path exists that names no pipeline machinery
  (the demoted commands, scripts, config knobs, branch/worktree
  plumbing — the flight-rule words with their gloss are allowed); the
  pin-checks this task authors pass along with lint; the two-controls
  restatement is present on both paths; no demoted skill is renamed.
- **Dependencies:** 2, 4, 11
- **Citations:** D-2, D-3 · REQ-H1.3, REQ-H1.4
- **Estimated effort:** 1 day

### Task 13 — Acceptance demo script

- **Deliverables:** the scripted demo driving the five acceptance
  scenarios (chat-only, split-screen, refusal to merge, escalation,
  walk-away/resume) against a live tower session, with the checklist the
  operator's v1 manual sweep marks off.
- **Done when:** the script drives all five scenarios; every `[manual]`
  or `[Gherkin]` test-spec entry that names the demo references a
  scenario the script drives; the checklist exists.
- **Dependencies:** 5, 9
- **Citations:** kickoff §5 (2026-09-01) · REQ-A1.1, REQ-A1.2, REQ-D1.2,
  REQ-F1.1
- **Estimated effort:** half day

### Task 14 — Flight points in dispatch and brief

- **Deliverables:** `scripts/flight-dispatch.sh` drops its skill-only
  refusal and checks every in-run point with unit kind `flight` in
  `/execute-task`'s pre-flight check mode, under the same root the brief
  pins, refusing exactly where that check stops a task unit and naming
  the point and step id, and naming every skipped step in its report;
  the brief names each in-run point (custom-steps' wired-in-`/execute-task`
  points, the flip points excluded) at its moment in the flight's work
  and directs the worker to run it by `/execute-task`'s *Points* procedure
  under the pinned root, always `--unattended`, mapping the procedure's
  pause protocol to the flight park; the convergence point runs the
  `main` sync where the flight has a remote and records it not run where
  it has none; on the PR home the brief fires `post-pr` after the draft PR
  exists with the PR number in the step context, then runs
  `/execute-task`'s after-`post-pr` sequence by reference (less the
  unit-PR ready-flip), re-emitting the record only by re-running
  `flight-record.sh render` with the same inputs, and parks when the PR
  is no longer a draft; `scripts/flight-record.sh` accepts a step table
  per in-run point (its required audit elements widened from the
  convergence table alone) and renders the file home's not-fired
  `post-pr` row; the header comments and brief text in
  `scripts/flight-dispatch.sh` that say a flight runs skill steps only
  are corrected; a pin-check asserting the referenced *Points* heading
  exists in `/execute-task`'s skill.
- **Done when:** dispatch tests place a flight whose configured lists
  carry skill, prompt, and command steps at every in-run point, and the
  brief names, in order, exactly the points `/execute-task`'s pre-flight
  point check names, less the conditional `pre-ready-flip`; the brief
  points at the *Points* procedure under the pinned root and states
  `--unattended` and the flight-park mapping; a dispatch whose only
  problem is an adopter or machine-local list naming an undefined step id
  places the flight, that step named as skipped in the report and the
  brief; a malformed entry at any layer, or an unresolvable skill target,
  refuses with the point and step id named and places nothing; dispatch
  under root skew checks against the pinned root; brief tests assert the
  convergence `main` sync and its no-remote not-run record, `post-pr`
  after the draft PR with the PR number in context, the after-`post-pr`
  sequence referenced with the re-emit through `flight-record.sh render`,
  and a park on a non-draft PR; record tests find every fired point's
  table in both homes and the not-fired `post-pr` row on the file home;
  the pin-check fails when the heading is renamed; the instruction-budget
  guard passes.
- **Dependencies:** none
- **Citations:** D-16, D-17, D-18 · REQ-C1.7, REQ-C1.8, REQ-C1.9,
  REQ-C1.11, REQ-C1.12, REQ-E1.6
- **Estimated effort:** 2 days

### Task 15 — Guard and degradation parity tests

- **Deliverables:** worker-command-guard tests running one shared corpus
  of declared command lines under unit kind `task` and `flight`,
  including adversarial cases showing a flight worker gains no approval a
  task worker lacks, and a root-skew case showing a catalog command
  step's line deferred, not approved, when the brief's pinned root differs
  from the guard's own; a guard change only where a test shows a gap,
  carrying its own security pass; dispatch tests for degradation parity
  across the overlay layers.
- **Done when:** the shared corpus yields identical verdicts under both
  unit kinds; the adversarial and root-skew tests pass; any guard change
  carries the hard-pause discipline and its allow/deny delta for human
  sign-off; the degradation-parity tests pass at every layer the
  resolver's missing-step matrix distinguishes.
- **Dependencies:** 14
- **Citations:** D-16, D-19 · REQ-C1.9, REQ-C1.10
- **Estimated effort:** half day

### Task 16 — Public ask summary

- **Deliverables:** `/offload`'s flight petition gains the optional public
  summary file (its petition definition and its dispatch line), and
  `scripts/flight-dispatch.sh` accepts it beside the ask, keeps the
  private ask only in the private brief directory, and echoes neither
  into its report; the brief, when a summary is given, tells the worker
  the ask is private and keeps its commits, PR title, record inputs, and
  PR comments at the summary's level; `scripts/flight-record.sh` takes the
  summary (under an option distinct from the lead's existing
  `--summary-file`), quotes it in place of the ask with the fixed
  briefed-beyond line, applies the existing sanitizing, markup
  neutralization, and any personal-data handling Task 19 lands to it, and
  runs the restate check of the lead against both texts and of every
  other worker-written input against the private ask; the `/tower` skill
  states when a summary is owed (REQ-E1.7, an undisclosed security defect
  named), draws the slug from the summary, and hands the summary over as
  data like the ask; the tower posture-delta doc's petition temp-file row
  updated; the eval-only seam's dispatch record gains a summary field,
  with the tower stand-in and `grade.jq` reading it, and routing fixtures
  asserting a summary (and a summary-derived slug) for an ask briefing an
  undisclosed security defect and none for an ordinary ask.
- **Done when:** with a summary given, record tests using distinctive
  ask lines above the restate thresholds find none of them in either
  home's output, first render or re-emit, and find the summary plus the
  fixed line; without one, the record is byte-identical to what
  `flight-record.sh` at this task's base renders from the same inputs
  (the existing record tests pass unchanged); a lead restating either the
  private ask or the summary is refused, as is another worker-written
  input restating the private ask; dispatch tests find no private-ask line
  on dispatch's stdout or stderr, in the flight worktree (tracked or
  untracked), on the branch, or under the fleet home outside the brief
  directory, and no summary line in the report; brief tests assert the
  privacy instruction; the summary fixtures pass their grader assertions,
  and the D-13 gate's live-tower run (or its operator-run fallback) is
  recorded for this judgment; the instruction-budget guard passes with
  the skill edits.
- **Dependencies:** 19
- **Citations:** D-13, D-20 · REQ-E1.6, REQ-E1.7, REQ-E1.8, REQ-E1.11
- **Estimated effort:** 1.5 days

### Task 17 — Parked flight's private partial record

- **Deliverables:** a `flight-record.sh` mode rendering a partial record
  (findings so far, declined log, park reason) into the flight's brief
  directory under the fleet home, written create-only, without following
  symlinks, and refusing any target outside the brief directory; the
  brief running it before every park (a hard pause, a point's halt or
  park, the non-draft check after `post-pr`, a renderer refusal, a
  destination mismatch, a question it may not wait on), with the park
  notification naming only the kind of park; `scripts/flight-sweep.sh`
  surfacing the partial record's path for a parked flight, so every
  surface rendering the sweep shows it; the brief sweep removing it with
  the brief directory when it retires the flight.
- **Done when:** mode tests find the partial record, carrying the
  findings, declined log, and park reason, under the brief directory and
  no change to any git ref or remote; a target outside the brief
  directory, or a symlink in its place, is refused; a secret planted in an
  input is redacted or refused as in the full record; brief tests find
  the mode run before every park site and a park notification carrying no
  detail beyond the kind; the sweep renders the path; retiring the flight
  removes the record with its brief directory.
- **Dependencies:** 16
- **Citations:** D-21 · REQ-E1.9
- **Estimated effort:** 1 day

### Task 18 — Doctrine and docs for flight points and the record

- **Deliverables:** `doctrine/flight-rules.md` updated: flights fire every
  in-run point under the task runner contract, unattended, parking
  through the flight park; the record contract per REQ-E1.6 with the
  public summary and the private ask; the parked partial record; and
  every record-home refusal condition including the spec root outside the
  checkout; `doctrine/custom-steps.md` updated where it describes flights
  (the unit-run definition, the in-run points' heading, the flights line,
  the posture rule's flight destination) and `doctrine/gate-wiring.md`'s
  pause protocol given the flight destination (D-22); the flight row of
  `doctrine/README.md`; the convergence passage of `skills/tower/SKILL.md`;
  the consumer column of the step options in `docs/options-reference.md`;
  and the flight-residue passage of `docs/fleet.md`.
- **Done when:** flight-rules states the points rule, the record contract,
  the parked record, and every home-refusal condition dispatch enforces,
  each citing its D-ID; a search of `doctrine/`, `skills/`, `docs/`,
  `README.md`, `config/`, and the `scripts/flight-*.sh` headers finds no
  passage still saying a flight runs skill steps only or converges only;
  `check-doctrine-index`, lint, and the instruction-budget guard pass.
- **Dependencies:** 14, 16, 17
- **Citations:** D-16, D-17, D-20, D-21, D-22 · REQ-C1.7, REQ-C1.8,
  REQ-E1.6, REQ-E1.9, REQ-E1.10, REQ-E1.12
- **Estimated effort:** 1 day

### Task 19 — The record renderer's held security fixes

- **Deliverables:** the five security-sensitive fixes to
  `scripts/flight-record.sh` that Task 6's convergence review held for
  decision (its `## Awaiting input` bullet states each problem and its
  recommended fix): whole-block redaction of a pasted private key, a
  case-insensitive assignment rule in the secret screen, a screen run on
  fixed ASCII names that refuses a finding naming a non-input path, the
  operator's chosen handling of personal data in the ask, and a `land`
  that creates the record only when absent, re-checks its directories
  after creating them, rolls back only an uncommitted record from an exit
  handler, and lets a matching re-run succeed. Each fix sits in a
  hard-disqualifier zone, so the worker pauses for the operator's
  decision on each before applying it, recording each decision in the PR
  body's pending-sign-off checklist; the PR removes Task 6's bullet.
- **Done when:** record tests show a pasted private key redacted from
  `BEGIN` through `END` (or to end of input when unterminated), an
  uppercase key assignment caught, a non-ASCII temp path neither passing
  nor mis-redacting a finding; the personal-data choice is verified as it
  was made (a pattern test, or a tower-skill clause and eval fixture when
  the operator chose confirmation); `land` tests, interleaved
  deterministically through a stub between its checks and its write,
  leave neither a committed-but-deleted record nor a stuck file, refuse a
  symlink swapped in after the directory checks, and report success for
  a re-run whose committed record matches; the PR body records each
  decision; the PR's diff removes Task 6's bullet.
- **Dependencies:** none
- **Citations:** D-6, kickoff delta re-walkthrough (2026-10-10) ·
  REQ-E1.2, REQ-E1.11
- **Estimated effort:** 1 day

## Awaiting input

- **Task 6** — scheduled as Task 19, which lands these fixes and removes
  this bullet; the record below is that task's decision input. The
  convergence review of the flight record renderer
  (`scripts/flight-record.sh`) found security-sensitive fixes the review may
  not apply on its own: its secret handling, and the file writes and
  rollback in `land`. None were applied; each needs a decision.
  1. Problem: a private key pasted into the ask or the grounds is only
     partly redacted. The secret screen flags the `BEGIN ... PRIVATE KEY`
     line alone, so the key body and its `END` line reach the record.
     Recommended fix: redact from the flagged `BEGIN` line through the
     matching `END` line, or to the end when there is none.
  2. Problem: the screen's assignment rule matches lowercase keywords only,
     so `API_KEY=<long value>` passes. Recommended fix: match the keyword
     in any case.
  3. Problem: the screen prints the path of each finding with some bytes
     removed, and when the temp directory's path holds such a byte (some
     non-ASCII characters, an em dash for one) no finding matches its
     input, so nothing is redacted or refused. Recommended fix: run the
     screen from the work directory on fixed ASCII names, and refuse rather
     than pass when a finding names a path that is not an input.
  4. Problem: the ask is screened for token-shaped secrets only, not for
     personal data (identity, account, or contact numbers), which the
     security-posture data-hygiene rule also keeps out of a PR body or a
     commit. Choose: add personal-data patterns to the ask's screen, or have
     the operator confirm the ask before it is quoted into the record.
  5. Problem: `land`'s rollback unstages and deletes the record without
     checking whether it is already committed, so two runs at once leave the
     record committed but deleted, with the deletion staged; an interrupted
     run leaves a file every re-run refuses as "already exists"; and a
     symlink swapped in between `land`'s checks and its write would carry
     the write outside the checkout. Recommended fix: create the record only
     if it does not already exist, re-check the directories after creating
     them, roll back only when the record is not in `HEAD` (from an exit
     handler, so an interrupt rolls back too), and let a re-run whose
     committed record matches the render report it and succeed.

  The draft PR's CI is also blocked outside this task: its `check` job stops
  at the full-history secret scan, which flags a test fixture on another
  spec's branch (`fleet-lifecycle-closure/task-6`, a `generic-api-key` hit
  in `tests/test-fleet-cleanup-process.sh`) that is in neither `main` nor
  this branch, and `main`'s own CI fails the same way. Decide how to clear
  it (fix that fixture on its branch, or record the hit in a gitleaks ignore
  on `main`); then re-run this PR's CI, which has not yet reached its tests.

## Deferred

- **Tower floor bypass paths from the skill core's review.** The deny
  floor does not yet cover a merge or ready flip through `gh api`, or the
  GitHub tools another MCP server exposes; the operator assigned closing
  them to Task 10 (tower posture extension) rather than the skill core,
  so they are not named in bring-up. Task 10's block does not name them
  yet, so when the gate fires, check that its landed floor covers both.
  Confidence: high.
  *(2026-10-01: the `gh api` half moved to human-gates Task 6
  (human-gates REQ-G1.7, REQ-G1.8): its policy guard, not the profile floor,
  denies a `gh api` flip, undo, or merge to the tower at every value and
  denies a `gh api` request it cannot read. When this gate fires, check only
  the other MCP servers' GitHub tools.)*
  **Gate:** GATE(when: task 10 completed).
  Citations: D-14 · REQ-A1.3, REQ-G1.1, REQ-G1.4.

- **User-history / trust-ramp routing.** Static signals suffice to prove
  the routing; history adds statefulness and a where-does-it-live
  question. Confidence: high.
  **Gate:** operational evidence from real flights shows the static rule
  misroutes often enough to justify stateful history (surfaced free-text
  condition, evaluated at drain).
  Citations: D-4 · the tower-front-door seed (Sources).
- **Existing-skill renames.** Renames change the published command
  surface mid-review; the naming decisions themselves stay open until
  the review outcome is known. Confidence: high.
  **Gate:** the pending marketplace review of the plugin concludes
  (surfaced free-text condition, external event).
  Citations: D-2 · the tower-front-door seed (Sources).
- **The pervasive vocabulary prose sweep.** The definitional sites plus
  the transitional note carry v1; the full fleet-doc re-terming waits
  until the new vocabulary has been exercised. Confidence: medium.
  **Gate:** the Task 2 definitional sites are merged and no
  transitional-note confusion has been observed in use (surfaced
  free-text condition).
  Citations: D-2 · REQ-H1.2.

## Out of scope

- Multi-repo / cross-repo tower (one tower per repo checkout in v1).
- Bootstrapping un-scaffolded repositories (no `specs/`, or no git
  repository): the inception seam owns the start-from-nothing entrance;
  `/tower` may point the user there.
- Fleet-mode integration beyond seam reuse: no supervision of spec-mode
  orchestrators, no `--meta` fold-in.
- Persistent flight memory beyond the audit trail (preference learning,
  style adaptation).
- Any change to sign-off or merge semantics.
