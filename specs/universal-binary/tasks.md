# Universal Binary — Tasks

**Status:** Ready
**Last reviewed:** 2026-09-09
**Format-version:** 2
**Execution:** derived — see the status render

## Tasks

### Task 1 — Lock baseline: one atomic-create primitive for every advisory lock

- **Deliverables:** a shared lock library under `scripts/` implementing
  acquisition by atomic create with an owner token, ownership-verified
  release, a stale break that cannot double-grant (stale meaning the owner
  token's process is absent, never an age), signal-safe release installed
  before the critical section, and token reentrancy (a nested acquire
  under the same token succeeds and the lock is held until the outermost
  release); every lock holder in the script layer adopted onto it — at
  drafting: the orchestration lock, the fleet state registry, the
  allocation locks, the stream-json supervisor's locks, the audit and
  observation appenders, plus any other the tree carries at task time;
  `mkdir` retired as an acquisition primitive with a lint guard
  (`scripts/check-lock-primitive.sh`, wired as `check:lock-primitive`)
  rejecting any `mkdir` whose exit status is used as a lock-acquisition
  signal; the registry race, lost-append, and allocation bound-counter
  tests green; a reentrancy test.
- **Done when:** the registry race test passes twenty of twenty
  registrations in ten consecutive runs with no other test process on the
  host and in ten consecutive runs under `mise run test` with
  `mode=parallel` in the timing report; the allocation lock's
  bound-counter test records no grant past its bound in the same runs;
  the reentrancy test passes; every script in the lock-holder list the
  library's header enumerates sources it and the lint guard reports no
  un-adopted lock site; the lint guard runs under `mise run check`.
- **Dependencies:** none
- **Citations:** D-11 · REQ-E1.5
- **Estimated effort:** 2 days

### Task 1.1 — Echo baseline: printf discipline and its lint guard

- **Deliverables:** every site that echoes sanitized or untrusted text
  moved to `printf '%s'`; a lint guard (`scripts/check-echo-discipline.sh`,
  wired as `check:echo-discipline`) that rejects an `echo` whose argument
  is any variable unless the variable is annotated `# trusted:` with a
  reason; the source-guard split resolved to guarded sourcing of the
  sanitizer, stated in the guard's header with its reason and enforced by
  the same guard, with the two inline copies the security-posture doctrine
  sanctions either consolidated or their sanction re-recorded in that
  doctrine bullet; a regression test under `tests/` reproducing the dash
  escape re-synthesis from the observations (a literal backslash sequence
  turned into a live escape), run under a `dash` the test installs or
  locates.
- **Done when:** the guard passes on the swept tree and fails on a fixture
  reintroducing the pattern and on a fixture sourcing the sanitizer bare;
  the dash regression test emits no control byte under a local `dash`;
  Task 4 re-runs the same test on the Alpine job.
- **Dependencies:** none
- **Citations:** D-12 · REQ-E1.5
- **Estimated effort:** 1 day

### Task 2 — Partition script and coupling profile

- **Deliverables:** `scripts/substrate-partition.sh` and a
  `substrate:partition` task (an on-demand task outside the check
  aggregate, which places the script itself in the dev-check tier)
  producing, for every script in the layer as REQ-A1.1 defines it, its
  tier (hook, skill-called, library, dev-check, tests-only, first match in
  that order) derived from hook registrations, tracked git hooks, skill
  bodies, `mise.toml` tasks and workflows, and script-to-script
  invocation; its coupling profile (every non-builtin command word it
  invokes) and shell-mutation flag; and a no-live-caller flag with
  non-literal invocations reported as unresolved; a test suite over a
  fixture tree.
- **Done when:** the task regenerates the partition from a clean checkout
  in one command; every script receives exactly one tier; the fixture
  suite carries one case per tier, the two-definition tie-break, the
  shell-mutation flag, and the five REQ-A1.3 cases (no caller; library
  reachable only from a flagged script; helper invoked only by a test;
  script named only in documentation; flag clears once a task names it);
  the output is byte-identical across two runs.
- **Dependencies:** none
- **Citations:** D-3 · REQ-A1.1, REQ-A1.3
- **Estimated effort:** half day

### Task 2.1 — Entry-point guard

- **Deliverables:** `scripts/check-entry-points.sh`, wired as
  `check:entry-points`, which takes the partition's entry-point set (every
  script a skill body, a hook registration, or a tracked git hook names)
  and asserts each exists, accepts its recorded argument fixture, and
  produces its recorded stdout bytes, stderr class, and exit code; a
  recorded fixture per entry point, captured from the current
  implementation's observed behaviour and reviewed at task time; a failure
  when any shim's delegation target is a script the partition flags; a
  fixture suite covering a removed entry point, a changed exit code, a
  shim of a flagged script, and a shim exiting with the reserved
  fetch-failure code on its stdout contract.
- **Done when:** the guard passes on the branch's merge-base tree and
  fails on any later entry point without a fixture; it fails on each of
  the four fixtures; every entry point has a recorded fixture.
- **Dependencies:** 2
- **Citations:** D-10 · REQ-E1.2, REQ-A1.3
- **Estimated effort:** 1 day

### Task 3 — Observation attribution, pain matrix, and cost baseline

- **Deliverables:** `scripts/substrate-attribute.sh` with a
  `substrate:attribute` task, mapping every observation in the mined set
  (UIDs and dated frozen-log lines) to the scripts it names and thence to
  tiers and defect classes, with a recorded manual attribution file for
  fragments naming no script, written by the executing worker; the
  cost-baseline script with a `substrate:baseline` task; the tier-by-class
  pain matrix and the maintenance-cost baseline (fix-typed commits per
  month on the layer, observation inflow by class per month,
  check-aggregate wall-clock, load-flake hand-backs as REQ-G1.1 defines
  them) committed as dated snapshots under `docs/` at named paths, each
  either passing the prose lint or excluded from it with a recorded
  reason; a constraint profile for every tier other than tests-only,
  recorded from the partition and the matrix with every REQ-B1.2 field;
  `scripts/check-number-copy.sh`, wired as `check:number-copy`, failing on
  a figure present in both a snapshot and the bundle's prose outside the
  `## Sources` and `## Changelog` sections and a verdict's measurement and
  cost-benefit lines, matching snapshot values only, with any exemption
  list kept beside the guard with a reason per entry; a test suite over
  fixture fragments and a fixture repository with known history.
- **Done when:** every UID and every dated frozen-log line in the Sources
  appears in the matrix with a tier and a class; the manual file covers
  every script-less fragment; both snapshots regenerate byte-identically
  from one documented command each on an unchanged tree; the profiles name
  every REQ-B1.2 field for every tier other than tests-only; the
  number-copy guard runs under `mise run check`, passes on this bundle,
  fails on a fixture copying a snapshot figure into a requirement, and
  passes fixtures placing the figure only under `## Sources` or in a
  verdict's measurement line; the fixture suite passes.
- **Dependencies:** 2
- **Citations:** D-4, D-15 · REQ-A1.2, REQ-A1.4, REQ-B1.2, REQ-G1.1
- **Estimated effort:** 1 day

### Task 4 — Existing suite green on macOS and Alpine

- **Deliverables:** the existing shell suite, including the Task 1 registry
  race test and the Task 1.1 dash regression test, passing on a macOS
  runner (system `bash`, BSD awk and sed) and inside a stock Alpine
  container on the Ubuntu runner (musl, `dash` as `/bin/sh`, busybox);
  the two jobs added under a branch filter in this task's own branch, the
  filter removed by Task 4.1; every fix within the portability floor
  (POSIX-specified options and the tools REQ-B1.1 names); any failure
  whose fix the floor forbids escalated as an Awaiting-input entry naming
  the failing test and the rule the fix would break, rather than patched
  around; each root cause recorded as an observation whose UID the PR body
  lists. The failure count is unknown until the first run on each
  platform, so the estimate below is low-confidence.
- **Done when:** the suite is green on both platforms in this task's CI;
  a floor-forbidden failure blocks completion until the human answers its
  Awaiting-input entry (quarantining the test with a recorded reason, or
  amending the floor), and no test is skipped or marked informational
  except by such an answer; the Awaiting-input section carries every such
  entry, or the line "Task 4: no floor-forbidden failures."
- **Dependencies:** 1, 1.1, 2
- **Citations:** D-13 · REQ-B1.4
- **Estimated effort:** 2 days

### Task 4.1 — CI platform matrix, blocking from day one

- **Deliverables:** the macOS and Alpine jobs from Task 4 joining the
  pull-request workflow beside the Ubuntu job, every step blocking on every
  platform, no informational mode and no promotion switch; the Alpine job
  scoped to the shell test suite, the bake-off harness step, and the smoke
  step, with the prose linters, the plugin-schema check, and every step
  needing a tool without a musl build or the Claude CLI running on Ubuntu
  only and listed by name in the workflow; a smoke step on each platform
  that installs planwright through both delivery modes and runs the named
  adopter-tier entry point (the one with the largest coupling profile in
  the partition) with a `PATH` built as an allowlist of exactly the tools
  REQ-B1.1 names, so the hard constraint is exercised on runner images that
  carry toolchains by default; the workflow-posture guard extended to
  assert the three jobs are present, every step on each is blocking (no
  `continue-on-error`, no `|| true` in a `run:` block, no job-level `if:`
  gating on a platform name), and the Alpine job's step list matches the
  named scope, with cases in its test suite.
- **Done when:** all three jobs run on every pull request and the operator
  has marked each a required status check; the extended workflow-posture
  guard passes on the workflow and fails on a fixture with a soft step;
  the allowlist-`PATH` smoke step passes on every platform and fails on a
  fixture entry point that invokes `cargo`, `go`, `node`, or `python`.
- **Dependencies:** 4
- **Citations:** D-13 · REQ-B1.1, REQ-B1.4
- **Estimated effort:** half day

### Task 5 — Bake-off harness

- **Deliverables:** `scripts/substrate-bakeoff.sh` and a `substrate:bakeoff`
  task implementing the measurement contract of REQ-C1.4 for two candidate
  classes: for a full candidate, differential fixtures per representative
  primitive, correctness counts, latency medians and spread over a fixed
  run count, external processes spawned per invocation, source size,
  transitive dependency count with the dependency listing, matrix pass or
  fail, delivery through both modes, literal-path invocation check,
  offline-replayability, and a log format for implementation time and
  normalised review findings with their run count; for a comparison
  point, the harness's trivial-program fixture (one specified program)
  and the trivial-program set only; a run identifier and a per-execution
  timeout field in every report; a generated report with a stable,
  add-only schema documented at `docs/substrate-bakeoff-report.md` and
  linked from the script's header; a rendered comparison view of the
  report (one row per candidate, decision-relevant fields first, the full
  field set behind) regenerated by the same command; a self-test over a
  stub full candidate and a stub comparison point that rejects a report
  missing a field its class requires, a comparison-point row carrying a
  primitive field, a hook-tier report whose shell and candidate latency
  columns are absent or carry different run identifiers, and a candidate
  whose run does not execute every production differential fixture;
  `scripts/check-verdict-figures.sh` (`check:verdict-figures`) failing on a
  numeric token in a verdict decision's rationale that names no field of
  that tier's committed report or differs from its value, and
  `scripts/check-verdict-effort.sh` (`check:verdict-effort`) failing on a
  verdict effort figure that neither cites the logged porting rate nor
  carries the explicit absence token.
- **Done when:** one command produces the full report and the rendered
  view for both stubs on every matrix platform; each self-test rejection
  fires on its fixture; the schema document exists at the named path; both
  verdict guards run under `mise run check`, pass vacuously on this bundle,
  and each fails on its fixture verdict.
- **Dependencies:** 4.1
- **Citations:** D-7, D-17 · REQ-B1.5, REQ-C1.1, REQ-C1.4, REQ-C1.5,
  REQ-C1.6, REQ-G1.3
- **Estimated effort:** 2 days

### Task 6 — Bake-off A: the adopter-runtime pair

- **Deliverables:** the Task 1 lock primitive and the parser with the
  highest copy count in the pain matrix (the spec-grammar family or the
  config readers, whichever the matrix names) implemented against the same
  contract in hardened shell, Go, and Rust (the full candidates), with Zig
  and Bun-compiled TypeScript measured as comparison points on the
  trivial-program fixture only, never implementing a primitive; the
  hardened-shell prototype built at prototype scope inside this task —
  the shared-library seam and batched reads of D-6 for the representative
  primitives only, promotable as Task 13's seed under D-17, never a
  layer-wide consolidation; the harness report and rendered view for each;
  the implementation-time and review-findings logs; the screen record at
  `docs/substrate-screen.md` naming every candidate excluded and every
  constraint that excluded it (licence incompatibility included) and
  classing each admitted candidate as full or comparison point.
- **Done when:** every full candidate's per-fixture differential result is
  recorded in the report's correctness field, and a full candidate failing
  more than a fifth of the fixtures is marked screened-out rather than
  measured; the report carries every full-candidate field for every full
  candidate and the trivial-program fields for every comparison point on
  every matrix platform, with no primitive field on a comparison-point
  row; the logs carry one entry per full candidate and the self-test's
  log-field check passes; the hardened-shell prototype's diff touches only
  the representative primitives and their fixtures (file list in the PR
  body) and no production call site outside them adopts the prototype
  library; the screen record exists at the named path with every admitted
  candidate classed.
- **Dependencies:** 1, 1.1, 3, 5
- **Citations:** D-5, D-6, D-7 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4,
  REQ-G1.3
- **Estimated effort:** 4 days

### Task 7 — Bake-off B: the hook tier

- **Deliverables:** the command-guard tokenizer and the ready-guard
  decision path implemented against the same contract in hardened shell
  and every full candidate Task 6's screen admitted; per-call latency on
  every matrix platform against the shell baseline in the same run; the
  allowlist-shape check for each invocation; the implementation-time and
  review-findings logs; one tokenizer fixture per false-allow vector named
  in the parser-fragility observations the Sources list, enumerated by UID
  in the PR body.
- **Done when:** the report shows each full candidate's latency relative
  to shell on the same runner under the REQ-B1.5 rule; the tokenizer
  fixture set carries one case per enumerated vector and the suite fails
  when a case is removed; the logs carry one entry per full candidate and
  the self-test's log-field check passes.
- **Dependencies:** 5, 6
- **Citations:** D-5, D-7, D-14 · REQ-B1.5, REQ-C1.3, REQ-C1.4, REQ-G1.3
- **Estimated effort:** 3 days

### Task 8 — Dev-check tier screen

- **Deliverables:** the dev-check section of the screen record at
  `docs/substrate-screen.md`, where a pinned toolchain already exists,
  stating for every candidate in Task 6's screen record plus Python and
  Node whether it passes the tier profile; the breadth-rule decision with
  the profile comparison; a recommendation to the verdict amendment.
- **Done when:** the record names a screen outcome for every candidate
  and either a recommendation to inherit Task 6's measured outcome with
  the REQ-C1.3 profile comparison, a recommendation to settle the tier by
  the screen record where one candidate survives, or a case for a
  dev-check bake-off naming the representative primitive, which is
  escalated as an Awaiting-input entry so that Task 9 mints no dev-check
  verdict until the human answers it.
- **Dependencies:** 3, 6
- **Citations:** D-5, D-6 · REQ-C1.2, REQ-C1.3
- **Estimated effort:** half day

### Task 9 — Verdict amendment, doctrine restatement, and cost-benefit record

- **Deliverables:** the meaning-class amendment adding one verdict decision
  per tier other than tests-only, whether measured, inherited, or
  screen-settled, each with the harness measurements or the inheritance
  comparison and the cost-benefit line (migration effort from the logged
  porting rate or its explicit absence, projected ongoing delta against
  the baseline, eliminated versus relocated classes, the restructured-shell
  share of the gain, the stay-in-shell figures at equal weight, a
  break-even threshold on a baseline field or its absence); the bootstrap
  bundle's supersession annotation on its runtime decision, with
  `scripts/check-supersession.sh` (`check:supersession`) asserting the
  annotation is present and the decision's body is byte-identical to its
  blob at the baseline ref the validator already resolves (default
  `origin/main`); the security-posture restatement as the five
  substrate-neutral criteria of REQ-D1.3, referencing the method page by
  resolution path and never by a relative link into `docs/`; the docs page
  that walks the method for a reader without the spec open and points at
  the snapshots, the report, and the rendered view; a verification
  checklist in the amendment with one line per `[design-level]` test-spec
  entry naming the artifact and section that satisfies it. The human's
  scoped re-sign-off through `/spec-kickoff` is not a deliverable of this
  task: it is the separate human act the parked tasks' gates wait on.
- **Done when:** every tier other than tests-only has a drafted verdict
  decision whose numeric tokens pass the verdict-figures guard; each
  verdict's cost-benefit line names every REQ-G1.2 component and a
  break-even statement per REQ-G1.4; the PR body quotes the original
  doctrine line's normative tokens and shows each in the restatement; the
  supersession guard runs under `mise run check`, passes, and fails on a
  fixture altering one character of the decision body; the verification
  checklist is present; the amendment is committed on this task's branch
  with a pull request open against the spec branch and the brief's
  sign-off record unchanged.
- **Dependencies:** 6, 7, 8
- **Citations:** D-1, D-8, D-15, D-16 · REQ-D1.1, REQ-D1.2, REQ-D1.3,
  REQ-G1.2, REQ-G1.4
- **Estimated effort:** 1 day

### Task 10 — Delivery pipeline for compiled artifacts

- **Deliverables:** a CI job, hanging off the existing release-please
  release, cross-compiling the selected artifact for every matrix platform
  from the tagged source on every release; release assets with provenance
  attestations and a generated NOTICE file, under a release name checked
  for trademark collision (escalated as Awaiting-input if the check is not
  clean); a checksum pin file in the repository; the fetch shim under
  `scripts/` that downloads to a temporary path keyed by plugin version,
  operating system, and architecture under `CLAUDE_PLUGIN_DATA` (or the
  writer's per-plugin state home), verifies the checksum, renames
  atomically, removes an unverifiable file and superseded versions,
  serializes concurrent first uses through the shared lock, checks the
  artifact version string for equality with the installed manifest, and on
  any failure exits with the reserved code and a message on stderr naming
  the shell selector, never invoking the shell implementation itself; the
  mirror-address, offline, and shell-selector options with safe defaults
  in the configuration defaults file and options-reference rows; the
  `SessionStart` prefetch with a bounded timeout that never blocks session
  start and is silent on failure, cleared by the hook-contracts guard;
  writer delivery of the shim and fetch path, or the verdict's recorded
  writer-unsupported fallback exercised instead; the macOS first-execution
  test with the quarantine attribute set and a named per-execution
  timeout; `scripts/check-artifact-placement.sh` (`check:artifact-placement`)
  failing on a top-level `bin/` in the plugin tree, on a shim invocation in
  a skill body or hook registration that is not a resolved literal
  absolute path, on a shim exec resolving outside the data directory, or
  on a release workflow lacking the attestation and NOTICE steps; the
  fresh-machine install record for both modes committed under `docs/`
  with machine description and date, cited from the PR body.
- **Done when:** a fresh plugin install and a fresh writer install (or the
  verdict's recorded fallback for an unsupported mode) both execute the
  fetched artifact through the named entry point and produce its recorded
  stdout and exit code on every matrix platform in CI; a mismatched
  checksum, a missing asset, an absent hasher, a version skew, and a
  manifest version with no published asset each fail closed with the
  documented message and the reserved exit code, leaving no file behind;
  two concurrent first uses serialize; the macOS job executes a
  quarantined fetched artifact within the named timeout; the placement
  guard runs under `mise run check` and fails on each of its fixtures; the
  three options resolve through the defaults file; the fresh-machine
  record exists under `docs/`.
- **Dependencies:** 9
- **Citations:** D-9, D-13 · REQ-B1.3, REQ-F1.1, REQ-F1.2, REQ-F1.3,
  REQ-F1.4, REQ-F1.5, REQ-F1.6
- **Estimated effort:** 3 days

### Task 11 — Migrate the library and skill-called tiers

- **Deliverables:** shims for every entry point in the two tiers,
  delegating to the selected implementation; differential parity over the
  recorded fixtures for every migrated script, recorded in a committed
  parity file the suite regenerates; the selector key in the machine-local
  configuration layer that keeps the shell implementation reachable for as
  long as it exists, with a test exercising both implementations; the
  ordered removal plan with the human-directed step named; the partition
  reporting no flagged script in either tier before the first shim lands.
- **Done when:** every migrated entry point keeps its path, arguments,
  stdout bytes, stderr class, and exit codes under the entry-point guard;
  the differential suite carries a parity case per migrated script and
  passes in CI; the selector test passes; the partition reports no flagged
  script in either tier; the removal plan in the PR body names its
  human-directed step and no shell implementation has been removed by the
  task itself.
- **Dependencies:** 2.1, 9, 10
- **Citations:** D-10, D-17 · REQ-A1.3, REQ-E1.1, REQ-E1.2, REQ-E1.3
- **Estimated effort:** 5 days

### Task 12 — Migrate the hook tier

- **Deliverables:** shims and parity for the hook-tier entry points, in
  the committed parity file; the per-call latency check against shell on
  every matrix platform kept as a blocking harness step under the
  REQ-B1.5 rule; the allowlist-shape check kept, running on every hook
  invocation in the harness; the removal plan with the human-directed step
  named.
- **Done when:** every hook entry point keeps its path, arguments, stdout
  bytes, stderr class, and exit codes under the entry-point guard; the
  harness's hook-tier latency check passes on every platform; the
  allowlist-shape check fails on a fixture shim invoked by a non-literal
  path; the removal plan in the PR body names its human-directed step and
  nothing has been removed by the task itself.
- **Dependencies:** 2.1, 9, 10
- **Citations:** D-10, D-14 · REQ-B1.5, REQ-E1.1, REQ-E1.2, REQ-E1.3
- **Estimated effort:** 3 days

### Task 13 — Shell-verdict class fixes

- **Deliverables:** for every adopter tier whose verdict keeps shell: the
  shared-library consolidation of the duplicated primitives the pain
  matrix names at task time (at drafting: the command-guard engine, the
  knob resolvers, the liveness seam, the config and table readers, the
  model roster), with `scripts/check-single-implementation.sh`
  (`check:single-implementation`) failing when a named primitive has more
  than one shell implementation (an implementation kept selectable under
  REQ-E1.3 does not count); an injectable clock for every test in the
  time-anchored list the task records, with a guard failing on a test that
  reads the wall clock directly; each fix cited to the observations it
  closes and consuming them.
- **Done when:** the single-implementation guard reports no named
  primitive with more than one shell implementation and fails on a fixture
  reintroducing a second copy; every listed time-anchored test passes with
  the clock injected under `mise run test` with `mode=parallel`; every
  observation UID in the duplicated-primitive class the Sources list is
  either consumed or carries a recorded reason it stays open.
- **Dependencies:** 9
- **Citations:** D-11, D-12 · REQ-E1.4
- **Estimated effort:** 4 days

### Task 14 — Dev-check tier migration or consolidation

- **Deliverables:** the dev-check tier's migration under its verdict:
  either shims and parity onto the selected substrate (built in CI, where
  a toolchain exists, rather than fetched), or the consolidation of its
  hand-rolled parsers and table readers onto shared helpers; the
  workflow-embedded shell moved into `scripts/` so the existing lint gates
  cover it, with the workflow-posture guard extended to reject an `if`,
  `case`, `for`, or `while` construct inside a `run:` block.
- **Done when:** every check task keeps its invocation under
  `mise run check`; the extended workflow-posture guard passes on the
  workflows and fails on a fixture `run:` block with an `if`; the branch
  the dev-check verdict selects is present and the PR body quotes the
  verdict clause it satisfies.
- **Dependencies:** 8, 9
- **Citations:** D-5, D-10 · REQ-E1.1, REQ-E1.4
- **Estimated effort:** 2 days

## Awaiting input

(none yet)

## Deferred

- **Task 10** parks until a verdict selects a compiled artifact for at
  least one adopter tier; the pipeline is designed (D-9) but building it
  for no artifact would be work with no consumer. Confidence: high.
  **Gate:** a signed verdict decision (Task 9's amendment, re-signed
  through `/spec-kickoff`) selects a compiled artifact for an adopter tier
  (hook, skill-called, or library).
  Citations: D-9, D-18 · REQ-E1.1.
- **Task 11** parks until the library or skill-called tier's verdict
  selects a non-shell substrate and Task 10 has delivered it. Confidence:
  high.
  **Gate:** a signed verdict decision (Task 9's amendment, re-signed
  through `/spec-kickoff`) selects a non-shell substrate for the library
  or the skill-called tier, and Task 10 has delivered the artifact for
  that tier.
  Citations: D-10, D-18 · REQ-E1.1.
- **Task 12** parks until the hook tier's verdict selects a non-shell
  substrate and Task 10 has delivered it. Confidence: high.
  **Gate:** a signed verdict decision (Task 9's amendment, re-signed
  through `/spec-kickoff`) selects a non-shell substrate for the hook
  tier, and Task 10 has delivered the artifact for that tier.
  Citations: D-10, D-18 · REQ-E1.1.
- **Task 13** parks until a verdict keeps at least one adopter tier on
  shell; its consolidation work is the migration for that tier and is
  wasted on a tier that leaves shell. Confidence: high.
  **Gate:** a signed verdict decision (Task 9's amendment, re-signed
  through `/spec-kickoff`) keeps an adopter tier (hook, skill-called, or
  library) on shell.
  Citations: D-11, D-12, D-18 · REQ-E1.4.
- **Task 14** parks until the dev-check tier's verdict is recorded, whether
  inherited, screen-settled, or measured. Confidence: high.
  **Gate:** a signed verdict decision (Task 9's amendment, re-signed
  through `/spec-kickoff`) covers the dev-check tier, whether minted for
  it, inherited under REQ-C1.3, or settled by the screen.
  Citations: D-5, D-18 · REQ-E1.1.
- **Native Windows through Git Bash.** A compiled artifact would make the
  script layer runnable where the platform host already supports Windows,
  but no planwright document promises it and the operator did not select it
  for the matrix. Confidence: medium.
  **Gate:** a signed verdict decision (Task 9's amendment, re-signed
  through `/spec-kickoff`) selects a compiled artifact for an adopter
  tier, and a Windows request is recorded by the operator under
  `specs/_pending/`.
  Citations: D-13, D-18.

## Out of scope

- **Rewriting skill prose.** `SKILL.md` bodies are not edited by this
  bundle; only the scripts they call may change substrate, which is why the
  entry points are frozen (REQ-E1.2). Instruction-headroom relief that
  follows from procedure moving into scripts is a side effect, not a
  deliverable.
