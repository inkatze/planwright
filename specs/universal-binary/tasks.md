# Universal Binary — Tasks

**Status:** Draft
**Last reviewed:** 2026-09-08
**Format-version:** 2
**Execution:** derived — see the status render

## Tasks

### Task 1 — Lock baseline: one atomic-create primitive for every advisory lock

- **Deliverables:** a shared lock library under `scripts/` implementing
  acquisition by atomic create with an owner token, ownership-verified
  release, a stale break that cannot double-grant, signal-safe release
  installed before the critical section, and token reentrancy; every lock
  holder in the script layer (the orchestration lock, the fleet state
  registry, the allocation locks, the stream-json supervisor's locks, the
  audit and observation appenders) adopted onto it; `mkdir` retired as an
  acquisition primitive with a lint guard rejecting its return; the
  registry race and lost-append tests green.
- **Done when:** the registry race test passes twenty of twenty
  registrations in ten consecutive isolated runs and under the parallel
  suite; the bound counter never grants past its bound in the same runs;
  every lock holder sources the shared library and no script calls `mkdir`
  to acquire a lock; the lint guard runs under `mise run check`.
- **Dependencies:** none
- **Citations:** D-11 · REQ-E1.5, REQ-E1.4
- **Estimated effort:** 2 days

### Task 1.1 — Echo baseline: printf discipline and its lint guard

- **Deliverables:** every site that echoes sanitized or untrusted text
  moved to `printf '%s'`; a lint guard under `mise run check` that rejects
  an `echo` whose argument is a sanitizer result or an untrusted variable;
  the source-guard split (bare versus guarded sourcing of the sanitizer)
  resolved to one house rule enforced by the same guard.
- **Done when:** the guard passes on the swept tree and fails on a fixture
  reintroducing the pattern; the dash reproduction from the observations
  (a literal backslash sequence re-synthesized into a live escape) emits no
  control byte on the Alpine job.
- **Dependencies:** none
- **Citations:** D-12 · REQ-E1.5, REQ-E1.4
- **Estimated effort:** 1 day

### Task 2 — Partition script and coupling profile

- **Deliverables:** `scripts/substrate-partition.sh` and a `substrate:partition`
  task producing, for every script in the layer, its tier (hook,
  skill-called, library, dev-check, tests-only) derived from hook
  registrations, tracked git hooks, skill bodies, check tasks and
  workflows, and script-to-script invocation; its coupling profile (the
  external processes it drives); and a no-live-caller flag; a test suite
  over a fixture tree.
- **Done when:** the task regenerates the partition from a clean checkout
  in one command; every script receives exactly one tier; the fixture suite
  covers each tier and the no-caller flag; the output is stable across two
  runs.
- **Dependencies:** none
- **Citations:** D-3 · REQ-A1.1, REQ-A1.3
- **Estimated effort:** half day

### Task 3 — Observation attribution, pain matrix, and cost baseline

- **Deliverables:** `scripts/substrate-attribute.sh` mapping every
  observation in the mined set to the scripts it names and thence to tiers
  and defect classes, with a recorded manual attribution file for fragments
  naming no script; the tier-by-class pain matrix and the maintenance-cost
  baseline (fix-typed commit rate on the layer, observation inflow by class,
  check-aggregate wall-clock, load-flake handoffs) committed as dated
  snapshots under `docs/`; each tier's constraint profile recorded from the
  partition and the matrix.
- **Done when:** every UID in the Sources appears in the matrix with a tier
  and a class; the manual file covers every script-less fragment; both
  snapshots regenerate from one command each; the profiles name audience,
  latency budget, correctness needs, platform reach, auditability weight,
  and delivery modes for all five tiers.
- **Dependencies:** Task 2
- **Citations:** D-4, D-15 · REQ-A1.2, REQ-A1.4, REQ-B1.2, REQ-G1.1
- **Estimated effort:** 1 day

### Task 4 — CI platform matrix

- **Deliverables:** a macOS job (system `bash`, BSD awk and sed) and an
  Alpine job (musl, `dash` as `/bin/sh`, busybox) in the CI workflow; the
  existing shell suite running informationally on both with its failures
  recorded as observations; a promotion rule in the workflow that makes the
  suite blocking on a platform once it is green there; a smoke step on
  each platform that installs planwright through both delivery modes and
  runs a representative adopter-tier entry point with a `PATH` from which
  every compiler, interpreter, and package manager has been removed, so the
  hard constraint is exercised on runner images that carry toolchains by
  default.
- **Done when:** both jobs run on every pull request; the harness step is
  blocking and the suite step informational on the new platforms; the
  stripped-`PATH` smoke step passes on every platform and fails on a
  fixture entry point that invokes `cargo`, `go`, `node`, or `python`.
- **Dependencies:** Task 2
- **Citations:** D-13 · REQ-B1.1, REQ-B1.4
- **Estimated effort:** 1 day

### Task 5 — Bake-off harness

- **Deliverables:** `scripts/substrate-bakeoff.sh` and a `substrate:bakeoff`
  task implementing the measurement contract: differential fixtures per
  representative primitive, correctness under the existing tests,
  repeated-run latency, external processes spawned per invocation, source
  size, transitive dependency count, matrix pass or fail, delivery through
  both modes, literal-path invocation check, and a log format for
  implementation time and review findings; a generated report with a stable
  schema; a self-test over a stub candidate.
- **Done when:** one command produces the full report for a stub candidate
  on every matrix platform; the self-test fails when any contract field is
  missing; the report schema is documented beside the task.
- **Dependencies:** Task 4
- **Citations:** D-7, D-17 · REQ-C1.4, REQ-C1.5, REQ-C1.6, REQ-G1.3
- **Estimated effort:** 2 days

### Task 6 — Bake-off A: the adopter-runtime pair

- **Deliverables:** the Task 1 lock primitive and the parser the pain
  matrix ranks most duplicated (the spec-grammar family or the config
  readers, whichever the matrix names) implemented against the same
  contract in hardened shell, Go, Rust, and any candidate the distribution
  survey admitted through the screen; the harness report for each; the
  implementation-time and review-findings logs; the screen record naming
  every candidate excluded and by which constraint.
- **Done when:** every candidate passes the differential fixtures or its
  failures are recorded; the report carries every contract field for every
  candidate on every matrix platform; the logs are complete; the screen
  record exists.
- **Dependencies:** Task 1, Task 1.1, Task 3, Task 5
- **Citations:** D-5, D-6, D-7 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4,
  REQ-G1.3
- **Estimated effort:** 4 days

### Task 7 — Bake-off B: the hook tier

- **Deliverables:** the command-guard tokenizer and the ready-guard
  decision path implemented against the same contract in hardened shell
  and every candidate Task 6's screen admitted; per-call latency on every
  matrix platform against the shell baseline in the same run; the
  allowlist-shape check for each invocation; the implementation-time and
  review-findings logs.
- **Done when:** the report shows each candidate's latency relative to
  shell on the same runner; the tokenizer fixtures include the false-allow
  vectors the observations recorded; the logs are complete.
- **Dependencies:** Task 5, Task 6
- **Citations:** D-5, D-7, D-14 · REQ-B1.5, REQ-C1.3, REQ-C1.4, REQ-G1.3
- **Estimated effort:** 3 days

### Task 8 — Dev-check tier screen

- **Deliverables:** the screen record for the dev-check tier, where a
  pinned toolchain already exists, stating for each candidate (including
  interpreted runtimes) whether it passes the tier profile; the inheritance
  decision under the breadth rule, with the profile comparison; a
  recommendation to the verdict amendment.
- **Done when:** the record names every candidate's screen outcome and
  either an inherited verdict with its comparison or a case for a bake-off
  with the primitive named.
- **Dependencies:** Task 3, Task 6
- **Citations:** D-5, D-6 · REQ-C1.2, REQ-C1.3
- **Estimated effort:** half day

### Task 9 — Verdict amendment, doctrine restatement, and cost-benefit record

- **Deliverables:** the meaning-class amendment adding one verdict decision
  per tier, each with the harness measurements and the cost-benefit line
  (migration effort from the logged porting rate, ongoing delta against the
  baseline, eliminated versus relocated classes, the stay-in-shell figures
  at equal weight, a break-even condition or its absence); the bootstrap
  bundle's supersession annotation on its runtime decision; the
  security-posture restatement as substrate-neutral criteria; the docs page
  that walks the method and points at the snapshots and the report; the
  scoped re-sign-off through `/spec-kickoff`.
- **Done when:** every tier has a verdict decision citing report fields
  that exist; the cost-benefit line is present on each; the doctrine
  restatement preserves every normative token of the original and passes
  the manifest and index guards; the re-sign-off is recorded in the brief.
- **Dependencies:** Task 6, Task 7, Task 8
- **Citations:** D-1, D-8, D-15, D-16 · REQ-D1.1, REQ-D1.2, REQ-D1.3,
  REQ-G1.2, REQ-G1.4
- **Estimated effort:** 1 day

### Task 10 — Delivery pipeline for compiled artifacts

- **Deliverables:** a CI job cross-compiling the selected artifact for every
  matrix platform from the tagged source; release assets with provenance
  attestations; a checksum pin file in the repository; the fetch shim under
  `scripts/` that downloads into the plugin data directory, verifies the
  checksum before marking executable, checks the artifact version against
  the installed manifest, and fails closed naming the shell fallback; writer
  delivery of the shim and fetch path; the macOS first-execution test.
- **Done when:** a fresh plugin install and a fresh writer install both
  reach a working artifact on every matrix platform in CI; a mismatched
  checksum, a missing asset, and a version skew each fail closed with the
  documented message; the macOS job executes a fetched artifact.
- **Dependencies:** Task 9
- **Citations:** D-9, D-13 · REQ-B1.3, REQ-F1.1, REQ-F1.2, REQ-F1.3,
  REQ-F1.4, REQ-F1.5, REQ-F1.6
- **Estimated effort:** 3 days

### Task 11 — Migrate the library and skill-called tiers

- **Deliverables:** shims for every entry point in the two tiers,
  delegating to the selected implementation; differential parity over the
  recorded fixtures for every migrated script; a selector that keeps the
  shell implementation reachable until parity is recorded; the ordered
  removal plan with the human-directed step named; no-caller scripts
  removed or given a caller first.
- **Done when:** every migrated entry point keeps its path, arguments,
  stdout, and exit codes under the entry-point guard; parity is recorded per
  script; the removal plan is in the PR body and no shell implementation
  has been removed by the task itself.
- **Dependencies:** Task 9, Task 10
- **Citations:** D-10, D-17 · REQ-A1.3, REQ-E1.1, REQ-E1.2, REQ-E1.3
- **Estimated effort:** 5 days

### Task 12 — Migrate the hook tier

- **Deliverables:** shims and parity for the hook-tier entry points; the
  per-call latency check against shell on every matrix platform kept as a
  blocking harness step; the allowlist-shape check kept; the removal plan
  with the human-directed step named.
- **Done when:** every hook entry point keeps its contract; latency shows
  no regression on any platform; the removal plan is recorded and nothing
  has been removed by the task itself.
- **Dependencies:** Task 9, Task 10
- **Citations:** D-10, D-14 · REQ-B1.5, REQ-E1.1, REQ-E1.2, REQ-E1.3
- **Estimated effort:** 3 days

### Task 13 — Shell-verdict class fixes

- **Deliverables:** for every adopter tier whose verdict keeps shell: the
  shared-library consolidation of the duplicated primitives the pain
  matrix names (the command-guard engine, the knob resolvers, the liveness
  seam, the config and table readers, the model roster); an injectable
  clock for every time-anchored test; the source guard; each fix cited to
  the observations it closes and consuming them.
- **Done when:** no primitive in the named set has more than one
  implementation; every time-anchored test passes with the clock injected
  under the parallel suite; the cited observations are consumed.
- **Dependencies:** Task 9
- **Citations:** D-11, D-12 · REQ-E1.4
- **Estimated effort:** 4 days

### Task 14 — Dev-check tier migration or consolidation

- **Deliverables:** the dev-check tier's migration under its verdict:
  either shims and parity onto the selected substrate, or the
  consolidation of its hand-rolled parsers and table readers onto shared
  helpers; the workflow-embedded shell moved into `scripts/` so the
  existing lint gates cover it.
- **Done when:** every check task keeps its invocation under `mise run
  check`; no `run:` block in a workflow carries branching shell; the tier's
  verdict is satisfied as recorded.
- **Dependencies:** Task 8, Task 9
- **Citations:** D-5, D-10 · REQ-E1.1, REQ-E1.4
- **Estimated effort:** 2 days

## Awaiting input

(none yet)

## Deferred

- **Task 10** parks until a verdict selects a compiled artifact for at
  least one adopter tier; the pipeline is designed (D-9) but building it
  for no artifact would be work with no consumer. Confidence: high.
  **Gate:** a Task 9 verdict decision selects a compiled artifact for an
  adopter tier.
  Citations: D-9, D-18 · REQ-E1.1.
- **Task 11** parks until the library or skill-called tier's verdict
  selects a non-shell substrate and Task 10 has delivered it. Confidence:
  high.
  **Gate:** a Task 9 verdict decision selects a non-shell substrate for the
  library or the skill-called tier.
  Citations: D-10, D-18 · REQ-E1.1.
- **Task 12** parks until the hook tier's verdict selects a non-shell
  substrate and Task 10 has delivered it. Confidence: high.
  **Gate:** a Task 9 verdict decision selects a non-shell substrate for the
  hook tier.
  Citations: D-10, D-18 · REQ-E1.1.
- **Task 13** parks until a verdict keeps at least one adopter tier on
  shell; its consolidation work is the migration for that tier and is
  wasted on a tier that leaves shell. Confidence: high.
  **Gate:** a Task 9 verdict decision keeps an adopter tier on shell.
  Citations: D-11, D-12, D-18 · REQ-E1.4.
- **Task 14** parks until the dev-check tier's verdict is recorded, whether
  inherited or measured. Confidence: high.
  **Gate:** a Task 9 verdict decision is recorded for the dev-check tier.
  Citations: D-5, D-18 · REQ-E1.1.
- **Native Windows through Git Bash.** A compiled artifact would make the
  script layer runnable where the platform host already supports Windows,
  but no planwright document promises it and the operator did not select it
  for the matrix. Confidence: medium.
  **Gate:** a Task 9 verdict decision selects a compiled artifact for an
  adopter tier, and an adopter asks for Windows.
  Citations: D-13.

## Out of scope

- **Rewriting skill prose.** `SKILL.md` bodies are not edited by this
  bundle; only the scripts they call may change substrate, which is why the
  entry points are frozen (REQ-E1.2). Instruction-headroom relief that
  follows from procedure moving into scripts is a side effect, not a
  deliverable.
