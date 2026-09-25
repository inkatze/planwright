# Tower front door — Tasks

**Status:** Ready
**Last reviewed:** 2026-09-03
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

## Awaiting input

- **Task 4** — review pass on the skill core paused on permission and
  shell-construction findings (hard-disqualifier zone; recommended fixes
  recorded, none applied). Decide each: (1) a mutation need a read-only
  worker surfaces becomes a routed request only on the operator's own ask,
  and "a request" joins the list of things worker or pasted text never
  counts as; (2) branch names, flight ids, and `<spec>` values are checked
  against their grammar (a `<spec>` must equal an existing `specs/*/`
  basename; no match asks the operator) before entering any command or
  offered command; (3) the drift-capture `--text` value is passed as one
  argument, never interpolated into quotes; (4) the posture check fails
  closed when the shipped deny list is absent or unreadable, treats an absent
  layer as empty and only a parse or read error as unreadable, covers a
  `--settings` layer, checks the hook path resolves, reads hooks by
  projection only, and re-runs before lifting the block on "wired"; (5) the
  floor's `gh api` merge and ready-flip path and GitHub tools on other MCP
  servers are left to Task 10 or named in bring-up; (6) a failed `/offload`
  report is sanitized before relay, the hand-off hygiene list matches
  `security-posture` (customer data, private-repository detail), and
  markup-neutralization cites `flight-rules`. Queued judgment forks are in
  the draft PR's audit record.
- **Task 5** — review pass on the flight dispatch path paused on
  security-zone findings (shell and argv construction, permission and
  sandbox boundaries, egress, a destructive reconcile; recommended fixes
  recorded, none applied). Decide each: (1) the worktree primitive's flight
  arm treats a registered flight worktree with no tmux session as live and
  aborts instead of force-removing it, since a print-rung worker has no
  session; (2) `--brief` is confined to the flight's own brief under the
  fleet home after canonicalization, with a conservative path charset, the
  flight-id screen refuses an embedded newline, and `--continue` or
  `--resume` is refused beside a brief; (3) `home` reports the origin host,
  a `pr` home is declared only for an approved company host, and the tower
  states the destination before any push; (4) the skills require the ask and
  grounds files to be the tower's own temp files written with the file tool,
  never through shell quoting, removed after dispatch, with the brief
  directory cleaned when its flight retires; (5) report paths carrying
  control bytes are refused up front; (6) invisible and bidi Unicode in the
  ask is stripped or flagged before it reaches the brief; (7) the print-rung
  launch runs through the dispatch environment pin; (8) the brief
  directory's existing permissions, ownership, and symlinks are checked
  before writing; (9) the primitive's header, its worktree-creation
  exception note, and the tower posture's description name the flight arm,
  and a standalone flight `attach` can hand the worker its brief. Queued
  judgment forks are in the draft PR's audit record.
  A second review pass added three more in the same zones (a destructive
  cleanup and untrusted-input handling; recommended fixes recorded, none
  applied): (10) a failed `git worktree list` reads as "no worktree", so a
  failed placement removes the brief directory even when a worktree may
  exist: detect the listing's failure, keep the brief, and report the
  worktree state as unknown; (11) the grounds file is read with `cat` taking
  the path as an argument, unlike the size and line checks, so a relative
  name such as `-` or `-n` reads stdin or an option: read it through a
  redirect; (12) the grounds line gets no screen for invisible or bidi
  Unicode, the same gap as (6) on the second operator-text channel: apply
  (6)'s decision to it.

## Deferred

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
