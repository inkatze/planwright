# Universal Binary — Test Spec

**Status:** Draft
**Last reviewed:** 2026-09-08
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: the shipped scripts (the partition, the attribution and cost
baseline, the bake-off harness, the lock library, the echo lint guard, the
fetch shim, the entry-point guard) are `[test]` in the repository's shell
suite under `mise run check`, which the CI workflow runs on every pull
request; the CI matrix, the toolchain-absence smoke check, both delivery
modes, and the macOS first-execution check are `[test]` as workflow jobs;
the candidate screen, the breadth rule, the verdict decisions, the
doctrine restatement, and the cost-benefit lines are `[design-level]`,
verified by the artifact's existence and coverage at the scoped
re-sign-off; one entry is `[manual]`: a fresh-machine install through both
delivery modes, recorded in the delivery task's PR.

## REQ-A — Partition and attribution

### REQ-A1.1 — Call-graph partition [test]

A fixture tree with one script per tier (registered in a hook file, named
in a skill body, invoked only by another script, named only in a check
task, referenced only by a test) is partitioned by the shipped script; the
suite asserts each lands in its tier, that every script receives exactly
one tier, that the coupling profile names the external processes the
fixture drives, and that two runs produce identical output.

### REQ-A1.2 — Observation attribution [test + design-level]

The attribution script is run over a fixture set of fragments naming
scripts in each tier and one naming none; the suite asserts each maps to
the expected tier and class and that the script-less fragment is reported
as requiring the manual file rather than dropped. The committed matrix is
verified at re-sign-off to carry every UID the Sources list.

### REQ-A1.3 — No-caller flag gates migration [test]

The partition suite asserts the flag on a fixture script with no caller;
the migration tasks' entry-point guard refuses to shim a flagged script,
asserted by a fixture in the guard's suite.

### REQ-A1.4 — Snapshots cited, not copied [test]

A guard under `mise run check` asserts the bundle's anchored prose carries
no figure that appears in the snapshot files (a figure-shaped token present
in both is a finding), and that each snapshot regenerates from its
documented command.

## REQ-B — Constraint profiles

### REQ-B1.1 — No adopter toolchain [test]

Each matrix job runs a smoke step that installs planwright through both
delivery modes and runs a representative adopter-tier entry point with a
`PATH` stripped of every compiler, interpreter, and package manager; the
step fails on a fixture entry point that invokes one of them, which proves
the stripping is real on runner images that ship toolchains by default.

### REQ-B1.2 — Constraint profiles [design-level]

The profiles committed by Task 3 name every field for all five tiers;
verified at re-sign-off against the partition and the matrix.

### REQ-B1.3 — Both delivery modes [test]

The CI workflow installs the plugin through a local marketplace copy and
through the writer on each matrix platform and runs a representative
entry point through each; a verdict that records a mode as unsupported is
verified at re-sign-off to name the fallback.

### REQ-B1.4 — Platform matrix [test]

The workflow file is asserted by the workflow-posture guard to carry the
Ubuntu, macOS, and Alpine jobs, the harness step blocking on each, and the
suite step informational on the new platforms with the promotion rule
present; the Alpine job asserts `/bin/sh` is `dash` and awk is busybox.

### REQ-B1.5 — Relative hook budget [test]

The harness report for the hook tier carries shell and candidate latency
from the same run on the same runner; the harness self-test fails if either
column is missing or if they come from different runs.

## REQ-C — Candidate screen and bake-off

### REQ-C1.1 — Minimum candidate set [design-level]

The Task 6 screen record lists hardened shell, Go, and Rust for adopter
tiers and the interpreted runtimes for the dev-check tier; verified at
re-sign-off.

### REQ-C1.2 — Screen before prototype [design-level]

The screen record names, for every candidate not measured, the constraint
that excluded it; verified at re-sign-off, and the bake-off report is
checked to contain no candidate absent from the screen record.

### REQ-C1.3 — Breadth rule [design-level]

Each tier's verdict decision either cites its own bake-off report or an
inheritance with the profile comparison; verified at re-sign-off against
the profiles.

### REQ-C1.4 — Measurement contract [test]

The harness self-test runs a stub candidate and asserts every contract
field is present in the report: correctness, latency over repeated runs,
external processes spawned per invocation, size, dependency count,
per-platform pass or fail, both delivery modes, literal-path check,
implementation time, review findings.

### REQ-C1.5 — Reproducible figures [test]

The harness is run twice on the stub candidate and the report schema and
field set are asserted identical; a guard asserts every figure cited in a
verdict decision matches a field in the committed report.

### REQ-C1.6 — Prototypes on production fixtures [test]

The harness refuses a candidate that does not declare the production
differential fixture set, asserted by a fixture candidate that omits it.

## REQ-D — Verdict record

### REQ-D1.1 — Verdict by amendment [design-level]

Each verdict decision carries the amendment annotation and the brief
records the scoped re-sign-off; verified at re-sign-off.

### REQ-D1.2 — Supersession of the bootstrap decision [test + design-level]

The ledger guard asserts the bootstrap bundle's runtime decision carries
the supersession annotation and that its body is unchanged from the
baseline; the annotation's target is verified at re-sign-off.

### REQ-D1.3 — Doctrine restatement [test + design-level]

The doctrine manifest and index guards pass over the restated line; the
restatement is verified at re-sign-off to preserve every normative token
the original carried.

## REQ-E — Migration gates

### REQ-E1.1 — No migration without a verdict [test + design-level]

The drain pass surfaces the Deferred bullets' free-text gates verbatim,
asserted by the drain suite over this bundle; the dependency edge from
every migration task to the verdict task, and the unpark being a human
act, are verified at re-sign-off.

### REQ-E1.2 — Frozen entry points [test]

An entry-point guard under `mise run check` lists every script named by a
skill body, a hook registration, or a tracked git hook and asserts each
exists, accepts its recorded argument fixture, and produces the recorded
stdout and exit code; a fixture removing an entry point fails the guard.

### REQ-E1.3 — Differential parity and human-directed removal [test + design-level]

The differential suite runs the shell and the migrated implementation over
the recorded fixtures on every CI run for as long as both exist and asserts
identical stdout, stderr classes, and exit codes; the selector keeping
shell reachable is exercised by a test; the removal plan and the
human-directed step are verified in the migration PR body at re-sign-off.

### REQ-E1.4 — Shell-verdict class fixes [test]

For each named primitive a guard asserts a single implementation; the
injectable clock is exercised by the time-anchored tests under the
parallel suite; the source guard fails on a fixture sourcing the sanitizer
bare where the house rule requires a guard.

### REQ-E1.5 — Baselines before bake-off [test]

The registry race test and the dash echo reproduction are in the suite and
green before Task 6 starts; the selector honours the dependency edges from
Task 6 to Tasks 1 and 1.1, so Task 6 cannot dispatch before both derive
completed, verified by the status render at re-sign-off.

## REQ-F — Delivery of compiled artifacts

### REQ-F1.1 — Placement and literal-path invocation [test]

A guard asserts no top-level `bin/` in the plugin tree and that every
compiled-artifact invocation in a shim is a literal path through the
plugin root; a fixture with a `bin/` directory fails it.

### REQ-F1.2 — Attested, pinned, fail-closed fetch [test]

The fetch shim is exercised against a local fixture server: a matching
checksum installs the artifact, a mismatched checksum and a missing asset
each fail closed with the documented message naming the shell fallback, and
the artifact is not executable before verification; the release workflow's
attestation step is asserted by the workflow-posture guard.

### REQ-F1.3 — Version check [test]

The shim refuses an artifact whose embedded version differs from the
installed manifest's, asserted by a fixture pair.

### REQ-F1.4 — State under the plugin data directory [test]

The shim's write paths are asserted to resolve under the plugin data
directory and never under the plugin root, with a fixture where the plugin
root is read-only.

### REQ-F1.5 — Writer delivery [test + manual]

The writer job in CI installs the shim and reaches a working artifact;
the fresh-machine install through both modes is the one `[manual]` entry,
its observable being a working adopter-tier entry point on a machine with
no prior planwright install, recorded in the delivery task's PR.

### REQ-F1.6 — macOS first execution [test]

The macOS matrix job fetches an artifact through the shim and executes it;
the job fails if the first execution stalls beyond the harness's timeout or
is refused by the platform.

## REQ-G — Cost-benefit record

### REQ-G1.1 — Cost baseline script [test]

The baseline script is run over a fixture repository with known history
and fixture fragments; the suite asserts the fix-rate, inflow-by-class,
wall-clock, and handoff fields match the fixture's known values and that
the snapshot regenerates identically.

### REQ-G1.2 — Cost-benefit line per verdict [design-level]

Each verdict decision carries migration effort, ongoing delta, eliminated
versus relocated classes, and the stay-in-shell figures; verified at
re-sign-off.

### REQ-G1.3 — Porting-rate and review-findings logs [test]

The harness self-test asserts the implementation-time and review-findings
log fields are present per candidate and refuses a report without them; a
guard asserts a verdict's effort figure cites the logged rate.

### REQ-G1.4 — Break-even statement [design-level]

Each verdict decision states a break-even condition or its explicit
absence; verified at re-sign-off.
