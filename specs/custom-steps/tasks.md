# Custom steps — Tasks

**Status:** Ready
**Last reviewed:** 2026-10-06
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order. The rule doc lands first so every mechanism
cites a stated contract; the resolver and the record helper land before
any skill is wired to them; the point keys land with the resolver so no
commit on `main` reads a key that has no reader, and the old knob's removal
follows once the reader exists; the flip-point status verb lands before the
kickoff wiring that posts it, and the evidence hook that requires it stays
deferred until every flipper posts.

## Tasks

### Task 1 — The custom-steps rule doc

- **Deliverables:** `doctrine/custom-steps.md`: the point vocabulary (the
  wired points and the named, unwired ones REQ-A1.1 through REQ-A1.3
  name, with the vocabulary's core ownership and the `tower-idle` rename),
  the moment each wired point fires per D-3 (`pre-ci` before the first full
  CI run of the unit run), the step entry fields, their enums, the id
  charset and the reserved phase id, the fixed context set with the
  `PLANWRIGHT_STEP_*` variable names, the empty-versus-unset rule, and its
  two delivery channels, the three hosting modes with the invocation
  mechanism per kind and mode and the dispatch-isolation default, the
  outcome set with the runner-classification rule and the `applied`
  discriminator, the failure postures and their in-run and flip-point
  destinations, the missing-step matrix with its four decision tokens, the
  reserved controls (the four no-push points, the two flip surfaces) and
  the no-recursion rule with the pipeline-entry list the resolver reads,
  the record fields and the cache path, the flip-point evidence (the
  outcome-to-status mapping, the branch-to-context mapping, what the
  status does and does not prove, the permission it needs), the credential
  rule, and the no-elevation rule for skill steps. The doctrine index row;
  the `customization-boundary` worked example reworded from the
  review-sequence knob to the convergence point's list;
  `doctrine/gate-wiring.md`'s PR-body assembly gaining the per-point step
  tables inside the collapsed audit block (a point that ran nothing still
  emitting a `none` row) and its pause protocol naming step failure as a
  reuse of its two destinations; `doctrine/flight-rules.md`'s reference to
  the configured review sequence reworded to the convergence point's list.
- **Done when:** every rule a `[design-level]` test-spec entry assigns to
  the rule doc appears in it; `check:links`, `check:doctrine-index`,
  `lint:md`, and `check:instructions` pass with no new declared exception.
- **Dependencies:** none
- **Citations:** D-1, D-2, D-3, D-6, D-7, D-8, D-9, D-14, D-16, D-17, D-20 · REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-B1.2, REQ-B1.4, REQ-B1.5, REQ-C1.4, REQ-C1.8, REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-D1.5, REQ-D1.6, REQ-D1.7, REQ-D1.8, REQ-D1.9, REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.5, REQ-F1.5, REQ-G1.4, REQ-H1.5
- **Estimated effort:** 1 day

### Task 2 — The steps catalog, the point keys, and the resolver

- **Deliverables:** `config/steps.yaml`, the core seed carrying the `polish`
  and `self-review` entries as skill steps with `args: --nested`; the
  `steps_<point>` keys REQ-B1.3 names in `config/defaults.yml` with the
  defaults it fixes, and their `docs/options-reference.md` rows; a
  per-layer read mode in `scripts/config-get.sh` that prints every layer's
  value for a key; `scripts/resolve-steps.sh <point> [--explain]
  [--preamble] [--check] --attended|--unattended`, which reads the point's
  list through `config-get`, the catalog through `resolve-catalog`,
  validates ids, fields, enums, targets, and `requires` per REQ-B and
  REQ-C (a namespaced skill target located through the installed-plugin
  registry), applies the missing-step matrix and prints the REQ-H1.3
  output with the decision token per step, prints the shadow warning, the
  per-layer stale `review_sequence` warning, and the unwired-point warning,
  refuses pipeline-entry targets (read from the rule doc's list), a
  first-position or post-subprocess `continue`, an in-session `timeout`
  on a session step, and `args` on a prompt, exits per REQ-H1.3, and in
  check mode applies REQ-H1.3's check-mode rule; `tests/test-resolve-steps.sh`
  covering each rule with layer fixtures under a temporary home; the two
  dispatch-entry disjointness cross-checks in the fleet-resource-select and
  allocation-select tests retargeted from the retired nestable predicate to
  the resolver's pipeline-entry refusal.
- **Done when:** with no overlay the resolution of `convergence` prints the
  single `polish` step as `run` and every other named point prints
  nothing with exit 0; every REQ-B and REQ-C rule whose test-spec entry
  names this test has a passing fixture, including the shadow warning, the
  matrix in both attendance modes, the stale-key warning at each layer, the
  by-layer policy for lists and for entries, the recursion refusal,
  provenance and preamble output, and the exit codes; `check:options`
  passes with a row per new key; the retargeted disjointness checks pass;
  `lint:shell` and `check:echo-safety` pass.
- **Dependencies:** 1
- **Citations:** D-4, D-5, D-6, D-10, D-15, D-17, D-18, D-19 · REQ-A1.3, REQ-A1.4, REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.6, REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.6, REQ-C1.7, REQ-C1.8, REQ-D1.8, REQ-D1.9, REQ-G1.1, REQ-H1.1, REQ-H1.3
- **Estimated effort:** 2 days

### Task 3 — Remove the review-sequence knob

- **Deliverables:** `review_sequence` removed from `config/defaults.yml`
  (key and prose comments); `scripts/resolve-review-sequence.sh` and its
  test deleted; this repository's `.claude/planwright.yml` gaining
  `steps_convergence: [self-review]` beside the kept `review_sequence`
  line with a dated comment naming the Deferred entry that removes it;
  every non-spec surface REQ-F1.3's grep reaches outside the two skill
  bodies updated, the judgement-bearing ones being `docs/overlays.md`
  (worked example B replaced by the steps example REQ-H1.2 describes, the
  growable-catalog enumeration corrected, the context set, the record
  cache and its ignore line, the credential rule, the status-write
  permission, and the disclosure note), `docs/options-reference.md` (the
  old row removed, the allocation rows reworded as step-id-keyed with the
  one-directional rule), and an upgrade note in `docs/getting-started.md`
  with the breaking-change marker in the commit footer; the stale-key
  sweep added to `check:steps`'s scope (Task 8 wires the task).
- **Done when:** `check:options` passes; the REQ-F1.3 grep, run as `git
  grep` over the stated roots, returns only the resolver's stale-key
  warning site, the fixtures that exercise it, and the transitional line;
  `mise run check` passes.
- **Dependencies:** 2
- **Citations:** D-10 · REQ-B1.5, REQ-F1.1, REQ-F1.2, REQ-F1.3, REQ-F1.4, REQ-F1.5, REQ-H1.1, REQ-H1.2
- **Estimated effort:** 1 day

### Task 4 — Step records and the PR-body fold

- **Deliverables:** `scripts/step-record.sh` with `write`, `list`, and
  `render` verbs over `<worktree>/.claude/steps/`, the record fields
  REQ-D1.5 names including the point-completion record, the excerpt
  screening (secret shapes through the repository's existing secret
  screen, non-printable bytes stripped, a stated length bound, table-safe
  rendering), the per-point table renderer the PR-body assembly consumes
  (a `none` row for an empty point, the point's warnings), and a
  `regenerate` verb that re-emits the pending-sign-off checklist from the
  marked commits of a base and head plus the per-point tables from the
  records; the `.gitignore` line for the cache path;
  `tests/test-step-record.sh`.
- **Done when:** a written record round-trips through `list` and `render`;
  the rendered table carries every field REQ-D1.5 names; an excerpt
  carrying a token-shaped string, a control byte, or a table delimiter
  renders screened, stripped, and escaped; `regenerate` over a fixture
  range reproduces a golden checklist fixture; a record with a skip reason
  renders as skipped; a point with no step records but a completion record
  renders its `none` row; the cache path is ignored; `lint:shell` and
  `check:echo-safety` pass.
- **Dependencies:** 1
- **Citations:** D-12, D-16 · REQ-D1.5, REQ-E1.2, REQ-H1.3
- **Estimated effort:** 1 day

### Task 5 — Wire the unit points into /execute-task

- **Deliverables:** `skills/execute-task/SKILL.md` invokes the resolver
  and runs the resolved steps at each in-run point per D-3, with the
  convergence section's review-sequence prose replaced by the point call
  (the compensating trim, keeping the queued-fork rule as the `halted`
  mapping), the hosting modes realized through the per-step session launch
  (`offload-dispatch` with the preamble) and the recorded session id, the
  outcome classification and posture handling per REQ-D1.1 and REQ-D1.2,
  the timeout rule, the post-pr regeneration and draft verification, the
  `pre-ci` call before the first CI run, and the manifest line loading the
  rule doc point-of-use; `tests/test-converge-sync-main.sh`'s anchor on
  the review-sequence run instruction moved to the point call;
  `skills/orchestrate/SKILL.md`'s dispatch prose citing the keys per
  REQ-E1.4 where it names the review sequence today, with its own
  compensating trim.
- **Done when:** with the shipped defaults a unit runs exactly today's
  single polish convergence and the converge-sync test passes on its new
  anchor; with a fixture overlay in the adopter layer declaring a command
  step at each in-run point, the step records show every such point fired
  once in order with the fixed context present in the command's
  environment; a `continue` step whose predecessor's session the backend
  cannot resume records `failed`; a post-pr command step that pushes
  triggers the regeneration and the draft check; `check:instructions`
  passes with `/execute-task`'s and `/orchestrate`'s margins at or above
  their declared figures and its manifest-resolution pass green on the new
  doc.
- **Dependencies:** 2, 3, 4
- **Citations:** D-3, D-7, D-8, D-9, D-12, D-14, D-15 · REQ-A1.1, REQ-A1.4, REQ-A1.5, REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-D1.7, REQ-E1.1, REQ-E1.2, REQ-E1.4, REQ-F1.1, REQ-G1.1, REQ-H1.4, REQ-H1.5
- **Estimated effort:** 2 days

### Task 6 — Wire the spec-PR flip point into /spec-kickoff

- **Deliverables:** `skills/spec-kickoff/SKILL.md` runs
  `steps_pre_spec_ready_flip` through the resolver after its push and PR
  step and before the terminal CI gate, posts the
  `planwright/pre-spec-ready-flip` status through the record helper's
  `status` verb on the head the list ends on, refuses the flip on a halted
  or failed step and records the pending flip to Awaiting input as the
  gate already does, its review-sequence-class sentence reworded to the
  point, with the compensating trim taken from the same sign-off step's
  prose; `doctrine/kickoff-verification.md`'s terminal CI gate excluding
  the flip-point contexts from its positive-green judgement;
  `tests/test-spec-kickoff-pr-ready.sh`'s review-sequence-class assertion
  retargeted to the point, plus a structural row asserting the exclusion
  wording.
- **Done when:** with the default empty list the kickoff flow is unchanged
  apart from the posted `success` status; with a fixture overlay in the
  adopter layer declaring a failing command step the flip is refused, the
  head carries a `failure` status, and the Awaiting-input entry names the
  step; the retargeted spec-kickoff PR-ready test and the existing kickoff
  ready-flip test pass; `check:instructions` passes with `/spec-kickoff`'s
  per-file and closure margins at or above their declared figures, the
  closure charged for both edited files.
- **Dependencies:** 2, 3, 4, 9
- **Citations:** D-3, D-9, D-13, D-20 · REQ-A1.2, REQ-E1.3, REQ-E1.5, REQ-F1.3, REQ-H1.4
- **Estimated effort:** half day

### Task 7 — The worker guard approves declared command lines

- **Deliverables:** `scripts/worker-command-guard.sh` resolves the declared
  command steps for the named points only for a segment not already
  known-safe, within its existing wall-clock bound, and approves a segment
  whose tokenized word sequence, after stripping leading
  `PLANWRIGHT_STEP_*` assignments, equals a declared step's resolved
  absolute location, as the resolver prints it on the guard's host,
  followed by its args as written, after that location's charset check
  and, for a path target, its
  canonicalization and traversal rejection, allow-only; fixture rows in
  `tests/test-worker-command-guard.sh` for an approved declared line, the
  same line with the context assignments prefixed, a word-identical
  respelling, the same line spelled with the bare target instead of its
  resolved location, a segment sharing only the first word, a non-declared
  command, and a path target with a traversal segment; the existing
  runtime-bound row re-run with a fixture catalog of several entries;
  `docs/overlays.md` section 9 documents the manual allow entry as the
  degraded-path fallback and states the REQ-G1.2 trust posture.
- **Done when:** every fixture row the deliverable names passes; the
  existing runtime-bound row passes with the fixture catalog present;
  `config/worker-settings.json` and `scripts/ready-guard.sh` carry no diff
  in this task's range; the permission-matcher and ready-guard tests still
  pass; `check:guard-wiring` and `check:hook-contracts` pass.
- **Dependencies:** 2
- **Citations:** D-11 · REQ-D1.6, REQ-G1.2, REQ-G1.3, REQ-G1.4
- **Estimated effort:** 1 day

### Task 8 — The check:steps guard

- **Deliverables:** a `check:steps` task in `mise.toml`, wired into
  `check`, that runs the resolver in check mode for every named point
  against this repository's own configuration and sweeps the stale key
  per REQ-F1.1; `tests/test-check-steps.sh` with a fixture showing it fails
  on an unresolvable step, on a non-empty unwired list, and on the stale
  key outside the transitional line.
- **Done when:** `mise run check` runs the guard and it resolves every
  named point, the non-empty one included, on the migrated configuration;
  each failing fixture exits non-zero naming the step, the point, or the
  key.
- **Dependencies:** 2, 3
- **Citations:** D-9 · REQ-A1.3, REQ-F1.1, REQ-H1.4
- **Estimated effort:** half day

### Task 9 — The flip-point status verb

- **Deliverables:** a `status` verb in `scripts/step-record.sh` that,
  from the latest attempt's records for a head in the worktree cache the
  flipper ran the point in, posts the `planwright/pre-ready-flip` or
  `planwright/pre-spec-ready-flip` commit status on that head in the base
  repository the PR targets (`success` when no record is halted or failed,
  an empty list included; `failure` otherwise), through `gh` as the
  plugin script the worker guard already approves, naming the required
  permission in its failure message; `scripts/release-lib.sh`'s rollup
  judgement excluding the flip-point contexts by context name (a new
  status-context arm beside the check-run-scoped window-lock exclusion, its
  comment updated); rows in `tests/test-step-record.sh` for the state
  derivation and in `tests/test-release-lib.sh` for the exclusion.
- **Done when:** the verb derives `success` over an empty attempt and over
  all-passed or applied records, `failure` over any halted or failed
  record, ignores an earlier attempt's records for the same head, and
  refuses a head with no completion record; a rollup holding only a
  flip-point status is not judged green; the posting call names the base
  repository; the release-lib suite's existing cases pass unchanged.
- **Dependencies:** 4
- **Citations:** D-20, D-16 · REQ-E1.5
- **Estimated effort:** half day

### Task 10 — The extension's contract in the rule doc and the docs

- **Deliverables:** `doctrine/custom-steps.md` states the expensive-check
  contract (the `pool`, `paths`, and `refire` fields, pools, the
  fingerprint, reuse, and re-fire), the outcome set with `limited`, the
  skip reasons, the end head, the previous and new head context fields,
  resume continuation, the `continue` rule over a skipped predecessor, and
  a quota-handling field list naming that bundle as the owner of their
  meaning; `docs/overlays.md` gains the pool, paths, and re-fire example
  (an adopter-layer catalog entry used by a repo-tracked `steps_pre_pr`
  list) and the hand-run full-suite recipe; `docs/options-reference.md`
  gains rows
  for `step_pool_capacity`, `step_pool_capacity_<pool>`,
  `step_pool_wait`, and `full_suite_pool`; the doctrine index row for the
  rule doc is refreshed.
- **Done when:** the options check, the doc-links check, the doctrine
  index check, and `check:instructions` pass with every closure that loads
  the rule doc at or above its declared margin; each REQ this task cites
  has its rule stated in the rule doc or the overlay documentation.
- **Dependencies:** none
- **Citations:** D-21, D-24, D-25, D-29, D-30, D-31 · REQ-A1.6, REQ-B1.7,
  REQ-D1.10, REQ-D1.11, REQ-D1.12, REQ-I1.5, REQ-I1.12, REQ-J1.3
- **Estimated effort:** 1 day

### Task 11 — The step pool helper and its knobs

- **Deliverables:** `scripts/step-pool.sh` with take, report, and release
  verbs over per-user pools built on `scripts/lock-lib.sh` (one slot lock
  per capacity unit, held on behalf of a named owning process, dead
  holders reclaimed, the pool directory screened for a symbolic link and
  for ownership, unusable pools reported for an unpooled run) and the
  bounded wait reporting live holders; the four config keys in
  `config/defaults.yml` with their core defaults; `scripts/lock-lib.sh`'s
  lock-holder list naming the helper; `tests/test-step-pool.sh`.
- **Done when:** fixture rows show capacity one serializing two callers, a
  per-pool capacity override admitting two, a dead holder's slot
  reclaimed, a child process that outlives the owning process not keeping
  the slot, the wait bound expiring with the holder named, a symbolic-link
  pool directory reported as unpooled, a malformed capacity and wait each
  falling back with a warning, and no verb executing a command it is
  given; `scripts/check-lock-primitive.sh` passes.
- **Dependencies:** none
- **Citations:** D-22, D-23, D-24, D-25 · REQ-I1.1, REQ-I1.2, REQ-I1.3,
  REQ-I1.4, REQ-I1.6
- **Estimated effort:** 1 day

### Task 12 — The resolver admits and validates the new fields

- **Deliverables:** `scripts/resolve-steps.sh` accepting `pool`, `paths`,
  `refire`, and quota-handling's six fields as known entry fields,
  refusing the malformations REQ-I1.11 names, and printing pool, paths,
  and re-fire in `--explain`; rows in `tests/test-resolve-steps.sh`.
- **Done when:** fixture rows show each REQ-I1.11 malformation refused for
  its layer with the right exit, each quota-handling field accepted as a
  known field without being validated beyond the single-line scalar rule,
  a `refire` step accepted in `steps_pre_ci` and `steps_pre_pr` and
  refused in `steps_convergence`, and `--explain` printing the new
  provenance; the existing resolver rows pass unchanged.
- **Dependencies:** none
- **Citations:** D-22, D-26, D-28, D-29 · REQ-B1.7, REQ-I1.7, REQ-I1.11,
  REQ-J1.3
- **Estimated effort:** 1 day

### Task 13 — Records, fingerprints, reuse lookup, and `limited` in the status

- **Deliverables:** `scripts/step-record.sh` writing the end head, the
  skip reason with the record it stands on, the pool, wait, holders, and
  unpooled fields, and the fingerprint; a fingerprint verb computing it
  from a worktree and a path list; a lookup verb returning the record a
  reuse or a resume continuation would stand on; the `status` verb
  deriving `failure` over a `limited` record; the PR-body table rendering
  the new fields table-safe; rows in `tests/test-step-record.sh`.
- **Done when:** fixture rows show a fingerprint stable across two commits
  that leave the paths unchanged, changed by a commit touching one, absent
  under an uncommitted or untracked change in a declared path, and
  marking an absent path; reuse lookup matching only a `passed` record of
  the same id, target, args, and fingerprint, across runs; resume lookup
  matching only `passed` or `applied` records of the interrupted run whose
  end head equals the given head; the `status` verb deriving `failure`
  over a `limited` record; the existing rows pass unchanged.
- **Dependencies:** none
- **Citations:** D-26, D-27, D-31, D-32 · REQ-D1.10, REQ-D1.12, REQ-E1.6,
  REQ-I1.7, REQ-I1.8, REQ-I1.10, REQ-J1.1, REQ-J1.2
- **Estimated effort:** 1 day

### Task 14 — Wire pools, reuse, re-fire, and resume into /execute-task

- **Deliverables:** `skills/execute-task/SKILL.md` taking a pool slot
  around a pooled command step and around every full local suite run when
  `full_suite_pool` is set, checking reuse before a step that declares
  `paths`, running the re-fire pass after the post-pr list and before the
  regeneration, attaching a `continue` step to the session behind a
  skipped predecessor, skipping per resume continuation on a resumed run,
  and exposing the previous and new head in the context; the mechanics
  live in the scripts and the rule doc, the skill carrying one-line calls
  with a compensating trim in the same change.
- **Done when:** with the shipped defaults a unit runs exactly as before;
  with a fixture overlay in the adopter layer declaring a pooled
  path-declaring re-fire command step at `pre-pr` and a post-pr command
  step that pushes a change to a declared path, the records show the slot
  taken and released, the check re-fired on the final head, and a second
  run of the unit reusing the passing record; a push touching no declared
  path re-fires as a `reuse` skip; a failing re-fire parks the unit with
  the PR a draft; two fixture units sharing `full_suite_pool` never run
  their suites at once; `check:instructions` passes with `/execute-task`'s
  margins at or above their declared figures.
- **Dependencies:** 10, 11, 12, 13
- **Citations:** D-25, D-27, D-28, D-30 · REQ-A1.6, REQ-D1.11, REQ-I1.1,
  REQ-I1.4, REQ-I1.5, REQ-I1.8, REQ-I1.9, REQ-J1.1
- **Estimated effort:** 2 days

### Task 15 — check:steps covers the new fields

- **Deliverables:** the `check:steps` guard resolving the new fields on
  this repository's configuration, and rows in `tests/test-check-steps.sh`
  for a malformed pool name, a misplaced re-fire step, and a step naming
  `refire` without `paths`.
- **Done when:** `mise run check` runs the guard green on this
  repository's configuration and each new failing fixture exits non-zero
  naming the step and the field.
- **Dependencies:** 8, 12
- **Citations:** D-9 · REQ-I1.11, REQ-I1.12
- **Estimated effort:** half day

### Task 16 — This repository joins the native pool

- **Deliverables:** `.claude/planwright.yml` setting `full_suite_pool`
  with a comment naming the release that carries the helper;
  `docs/CONTRIBUTING.md`'s full-gate instructions naming the pool
  helper's hand-run recipe as the way to run the gate by hand.
- **Done when:** the options check and `check:steps` pass on the new
  configuration; a full gate run through the documented recipe takes and
  releases a slot of the configured pool, recorded in the PR body.
- **Dependencies:** 11, 14
- **Citations:** D-25 · REQ-I1.13
- **Estimated effort:** half day

## Awaiting input

- **Task 10** anchor re-review pending: the 2026-10-06 extension is
  meaning-class Draft content inside this signed bundle, so its recorded
  anchor no longer recomputes; Task 10 and its dependents wait on the
  delta kickoff, whose sign-off re-records the anchor and removes this
  bullet.

## Deferred

- **Orchestrator-side and pipeline-side points.** `spec-drafted`,
  `kickoff-signed-off`, `unit-selected`, `pre-dispatch`, `post-dispatch`,
  `unit-halted`, `post-merge`, and `orchestrator-idle` are named in the rule
  doc and not wired; `/orchestrate`'s instruction closure has no headroom
  and no seed records a need at those points. Confidence: high.
  **Gate:** a recorded observation naming a step an operator needed at one
  of these points, or the `/orchestrate` diet landing (surfaced free-text
  condition, evaluated at drain).
  Citations: D-2 · issue 383 (Sources).
- **Per-spec and per-task-type lists.** The overlay layers give per-user
  and per-project granularity; a per-spec map has a precedent
  (`dispatch_backend_per_spec`) and a per-task-type key would need a
  classification the format lacks. Confidence: medium.
  **Gate:** a recorded observation from a run where one spec needed a
  different chain than its siblings (surfaced free-text condition,
  evaluated at drain).
  Citations: D-4, D-5 · the review-gauntlet seed (Sources).
- **Parallel steps within a point.** Serial order is what `continue`
  hosting and the commit discipline assume. Confidence: medium.
  **Gate:** a recorded observation where two independent steps at one point
  dominated a unit's wall clock (surfaced free-text condition, evaluated at
  drain).
  Citations: D-18.
- **The flip-evidence hook.** A deny-emitting PreToolUse hook of this
  bundle's own, `scripts/flip-evidence-guard.sh`, wired on the same two
  flip surfaces as the ready-guard (the shell ready command and the GitHub
  MCP update tool), reading the PR's head branch name, head repository,
  and the head's statuses under the ready-guard's wall-clock bound,
  denying an in-session flip of a PR whose head branch is under
  `planwright/` (task, spec, and flight branches alike) without the
  `success` status matching the branch, denying on a read that errors, and
  deferring on every other PR and on a fork head; fixture rows for each of
  those arms on both surfaces; the guard-wiring and hook-contract checks.
  Not wired until an in-repo unit-PR flipper that runs the point exists,
  because until then every task-PR flip would be denied with nothing to
  satisfy it; the obligation on that flipper (run the point, post the
  status) is recorded on issue 379 so its author sees it. Confidence:
  high.
  **Gate:** an in-repo unit-PR flip skill that runs `steps_pre_ready_flip`
  and posts the status lands (issue 379's policy or tower-front-door's
  flip step) (surfaced free-text condition, evaluated at drain).
  Citations: D-20 · REQ-E1.5, REQ-E1.3.
- **Dropping the transitional `review_sequence` line.** This repository's
  `.claude/planwright.yml` keeps the old key beside `steps_convergence`
  so units here, which run the installed plugin, keep converging through
  `[self-review]` until the release carrying the new resolver is
  installed. Confidence: high.
  **Gate:** the release carrying Task 3 is installed on this repository's
  machines (surfaced free-text condition, evaluated at drain).
  Citations: D-10 · REQ-F1.2.
- **Command and prompt steps on a flight.** The flight dispatch path
  (`scripts/flight-dispatch.sh`) renders skill steps only and refuses a
  command or prompt step at unit kind `flight` by name, placing nothing;
  the operator chose this narrowing on 2026-09-28 over rendering both
  kinds in Task 3. Full rendering needs: step `args` and prompt text
  screened before they reach the brief, and kept out of inline code; a
  relative command target resolved in the placed flight worktree, printed
  quoted, and carried as the `--line` rendering with its step context;
  each step's hosting, on-failure posture, and timeout carried into the
  brief; a skipped step named in the brief and the dispatch report; and
  the resolver's failures told apart (a park reported as a park, not as
  one exit-4 message). Confidence: high.
  **Gate:** an operator asks for a command or prompt step on a flight, or
  a recorded observation names a flight refused for one (surfaced
  free-text condition, evaluated at drain).
  Citations: D-10, D-13 · REQ-F1.5, REQ-G1.1.

- **Pooled, path-declaring, and re-firing skill or prompt steps.** The
  2026-10-06 extension gives `pool`, `paths`, and `refire` to command
  steps only: a session step's cost is not a function of the tree, and
  holding a slot across a session needs its own owning-process rule.
  Confidence: medium.
  **Gate:** a recorded observation naming a skill or prompt step an
  operator needed pooled or re-fired (surfaced free-text condition,
  evaluated at drain).
  Citations: D-27, D-28 · REQ-I1.11.

## Out of scope

- The ready-flip authorization policy (issue 379) and merge; this bundle
  provides the pre-ready-flip point and its evidence, performs no flip,
  and authorizes none.
- Plugin wrappers for external review tools; the operator's commands are
  named from an overlay.
- Machine-local configuration reaching worktrees; owned by
  customization-overlay.
- Re-running earlier points after a post-pr step moves the head; unit
  sizing and sync frugality are recorded in obs:36916a48 for a bundle that
  owns those rules. The one exception is a command step declaring
  re-fire (REQ-I1.9).
- Test-file pooling and the worker verification policy (test-throughput),
  and quota-handling's mechanics; see requirements.md's Scope.
- Editing the operator's own review commands, or any step's internal loop
  and convergence criteria.
- Steps editing signed spec content outside the amendment ritual; a
  worker executing a task under this bundle keeps that rule.
- The ready-guard's accepted residual surface (the raw GraphQL mutation)
  and evidence written by CI; see requirements.md's Scope.
