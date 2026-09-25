# Custom steps — Tasks

**Status:** Ready
**Last reviewed:** 2026-09-22
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
  `PLANWRIGHT_STEP_*` assignments, equals a declared target followed by
  its args as written, after its charset check and, for a path target, its
  canonicalization and traversal rejection, allow-only; fixture rows in
  `tests/test-worker-command-guard.sh` for an approved declared line, the
  same line with the context assignments prefixed, a word-identical
  respelling, a segment sharing only the first word, a non-declared
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

## Awaiting input

- **Task 2** — paused on a security-zone review finding; the rest of the
  task is converged and on draft PR #509. A bare command target that names a
  shell builtin (`cd`, `hash`, `printf`, `kill`, `umask`, and others that
  macOS also ships as wrapper files on the path) resolves to `run`, with its
  location set to the wrapper file. An `isolated` step runs that file as
  argv, but a session-hosted step's declared line goes through the session's
  shell, which runs the builtin instead, so the two hostings diverge and the
  builtin can change the session shell's own state (its working directory,
  a variable, its command hash). The printed location is then not what runs,
  which is also what the later worker command guard would match on. No new
  privilege is involved: an overlay author can already run any executable.
  Options: *refuse a command target that a clean shell reports as a builtin,
  keyword, or alias (malformed for its layer)* · *run session-hosted command
  lines through the resolved absolute location rather than the bare target,
  and state that in the rule doc* · *accept the divergence and document it*.

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
  owns those rules.
- Editing the operator's own review commands, or any step's internal loop
  and convergence criteria.
- Steps editing signed spec content outside the amendment ritual; a
  worker executing a task under this bundle keeps that rule.
- The ready-guard's accepted residual surface (the raw GraphQL mutation)
  and evidence written by CI; see requirements.md's Scope.
