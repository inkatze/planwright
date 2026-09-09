# Universal Binary — Test Spec

**Status:** Ready
**Last reviewed:** 2026-09-09
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: the shipped scripts and guards (the partition, the
attribution and cost baseline, the bake-off harness, the lock library, the
echo lint guard, the entry-point guard, the number-copy guard, the two
verdict guards, the supersession guard, the fetch shim, the placement
guard, the single-implementation guard) will be `[test]` in the
repository's shell suite under `mise run check`, which the CI workflow runs
on every pull request, once their tasks land; the CI matrix, the
toolchain-absence smoke check, both delivery modes, and the macOS
first-execution check are `[test]` as workflow jobs; the constraint
profiles, the candidate screen, the breadth rule, the verdict decisions,
and the cost-benefit lines are `[design-level]`, verified at the scoped
re-sign-off by the artifact existing and carrying every field its
requirement enumerates, against a verification checklist Task 9 ships;
one entry is `[manual]`: a fresh-machine install through both delivery
modes, owned by the operator and recorded under `docs/`.

## REQ-A — Partition and attribution

### REQ-A1.1 — Call-graph partition [test]

A fixture tree with one script per tier (registered in a hook file, named
in a skill body, invoked only by another script, named only in a `mise`
task, referenced only by a test), one script matching two definitions, and
one that `eval`s a variable is partitioned by the shipped script; the suite
asserts each lands in its tier, that the two-definition script takes the
first tier in the listed order, that every script receives exactly one
tier, that the coupling profile names the external processes the fixture
drives and sets the shell-mutation flag on the `eval` script, and that two
runs produce byte-identical output.

### REQ-A1.2 — Observation attribution [test + design-level]

The attribution script is run over a fixture set of fragments naming
scripts in each tier and one naming none; the suite asserts each maps to
the expected tier and class and that the script-less fragment is reported
as requiring the manual file rather than dropped. The committed matrix is
verified at re-sign-off to carry every UID and every dated frozen-log line
the Sources list, and the operator re-reads twenty sampled manual
attributions there.

### REQ-A1.3 — No-caller flag gates migration [test]

The partition suite asserts the flag on a fixture script with no caller, on
a fixture library reachable only from that flagged script, on a fixture
helper invoked only by a test, and on a fixture script named only in a
documentation file, and asserts the flag clears on the same script once a
fixture `mise` task names it; the entry-point guard (Task 2.1) refuses to
shim a flagged script, asserted by a fixture in the guard's suite.

### REQ-A1.4 — Snapshots cited, not copied [test]

A guard under `mise run check` asserts the bundle's prose, with the
`## Sources` and `## Changelog` sections and a verdict decision's
measurement and cost-benefit lines excluded, carries no figure that
appears in the snapshot files (a figure-shaped token present in both is a
finding; a fixture placing the token only in Sources passes, and a fixture
placing it in a verdict's measurement line passes).

## REQ-B — Constraint profiles

### REQ-B1.1 — No adopter toolchain [test]

Each matrix job runs a smoke step that installs planwright through both
delivery modes and runs the named adopter-tier entry point with a `PATH`
built as an allowlist of exactly the tools REQ-B1.1 names; the step fails
on a fixture entry point that invokes `cargo`, `go`, `node`, or `python`,
which proves the allowlist is real on runner images that ship toolchains
by default.

### REQ-B1.2 — Constraint profiles [design-level]

The profiles committed by Task 3 name every field, the tier-boundary side
included, for every tier other than tests-only, and the tests-only tier
carries none; verified at re-sign-off against the partition and the
matrix.

### REQ-B1.3 — Both delivery modes [test + design-level]

The CI workflow installs the plugin through a local marketplace copy and
through the writer on each matrix platform and runs the named entry point
through each; a verdict that records a mode as unsupported is verified at
re-sign-off to name the fallback.

### REQ-B1.4 — Platform matrix [test]

The workflow-posture guard, extended by Task 4.1, asserts the workflow
carries the Ubuntu, macOS, and Alpine jobs with every step blocking on
each (no `continue-on-error`, no `|| true` in a `run:` block, no
job-level `if:` gating on a platform name) and that the Alpine job's step
list matches the scope REQ-B1.4 names; the Alpine job asserts `/bin/sh`
is `dash` and awk is busybox; the repair-before-join ordering is carried
by the Task 4 → Task 4.1 dependency edge, and the suite's own green run
on both platforms is the evidence Task 4 records.

### REQ-B1.5 — Relative hook budget [test]

The harness report for the hook tier carries a run identifier and the
shell and candidate latency medians and spread from that run on the same
runner; the harness self-test fails if either column is missing or if
they carry different run identifiers.

## REQ-C — Candidate screen and bake-off

### REQ-C1.1 — Minimum candidate set [design-level]

The Task 6 screen record lists hardened shell, Go, and Rust as full
candidates for adopter tiers, Zig and Bun-compiled TypeScript as
comparison points, and Python and Node for the dev-check tier; the
harness self-test asserts a comparison-point row carries no value in the
correctness, differential-fixture, or implementation-time fields;
verified at re-sign-off.

### REQ-C1.2 — Screen before prototype [design-level]

The screen record names, for every candidate not measured, every
constraint that excluded it, licence incompatibility included; the
operator verifies at re-sign-off that the bake-off report contains no
candidate absent from the screen record.

### REQ-C1.3 — Breadth rule [design-level]

Each surviving tier's verdict decision either cites its own bake-off
report, an inheritance with the profile comparison, or the screen record
that settled it; verified at re-sign-off against the profiles.

### REQ-C1.4 — Measurement contract [test]

The harness self-test runs a stub full candidate and a stub comparison
point and asserts every contract field required of that candidate's class
is present in the report: for the full candidate, correctness counts,
latency over the fixed run count, external processes spawned per
invocation, size in bytes, dependency count with the dependency listing,
per-platform pass or fail, both delivery modes, literal-path check,
offline replayability, implementation time, and the normalised review
findings with their run count; for the comparison point, the
trivial-program set only.

### REQ-C1.5 — Reproducible figures [test]

The harness is run twice on the stub candidates and the report schema and
field set are asserted identical; a guard asserts every numeric token in a
verdict decision's rationale names a field of that tier's committed report
snapshot and equals its value, and fails on a fixture verdict citing a
figure absent from a stub report.

### REQ-C1.6 — Prototypes on production fixtures [test]

The harness refuses a candidate whose run does not execute every fixture
in the production differential set, asserted by a fixture candidate that
omits one; a failing fixture is recorded per fixture, not refused.

## REQ-D — Verdict record

### REQ-D1.1 — Verdict by amendment [design-level]

Each verdict decision carries the amendment annotation and the brief
records the scoped re-sign-off; verified at re-sign-off.

### REQ-D1.2 — Supersession of the bootstrap decision [test + design-level]

The supersession guard Task 9 delivers asserts the bootstrap bundle's
runtime decision carries the supersession annotation and that its body is
byte-identical to its blob at the baseline ref the validator already
resolves (default `origin/main`), and fails on a fixture altering one
character of that body; the annotation's target is verified at
re-sign-off.

### REQ-D1.3 — Doctrine restatement [design-level]

The restatement is verified at re-sign-off to preserve every normative
token the original carried (each modal verb with the duty it attaches
to), against the token list Task 9's PR body quotes.

## REQ-E — Migration gates

### REQ-E1.1 — No migration without a verdict [test + design-level]

The drain pass surfaces free-text gates verbatim, asserted by the drain
suite over a fixture reproducing this bundle's six Deferred bullets; the
dependency edge from every migration task to the verdict task, and the
unpark being a human act, are verified at re-sign-off.

### REQ-E1.2 — Frozen entry points [test]

An entry-point guard under `mise run check` lists every script named by a
skill body, a hook registration, or a tracked git hook and asserts each
exists, accepts its recorded argument fixture, and produces the recorded
stdout bytes, stderr class, and exit code; a fixture removing an entry
point fails the guard, as does a fixture shim exiting with the reserved
fetch-failure code on its stdout contract.

### REQ-E1.3 — Differential parity and human-directed removal [test + design-level]

The differential suite runs the shell and the migrated implementation over
the recorded fixtures on every CI run for as long as both exist and asserts
identical stdout, stderr classes (empty, or matching the fixture's recorded
stderr pattern), and exit codes, regenerating the committed parity file;
the selector keeping shell reachable is exercised by a test on both
implementations, and a fixture asserts it is read from the machine-local
configuration layer only; the removal plan and the human-directed step are
verified in the migration PR body at the migration PR's review.

### REQ-E1.4 — Shell-verdict class fixes [test]

For each named primitive a guard asserts a single shell implementation
(an implementation kept selectable under REQ-E1.3 does not count); the
injectable clock is exercised by the time-anchored tests under
`mise run test` with `mode=parallel` in the timing report; the source guard
fails on a fixture sourcing the sanitizer bare.

### REQ-E1.5 — Baselines before bake-off [test]

The registry race test and the dash echo regression test are in the suite
and green before Task 6 starts; the orchestration selector honours the
dependency edges from Task 6 to Tasks 1 and 1.1, asserted by the
selector's dependency tests and checked in the status render at Task 6's
dispatch.

## REQ-F — Delivery of compiled artifacts

### REQ-F1.1 — Placement and literal-path invocation [test]

A guard asserts no top-level `bin/` in the plugin tree, that every
invocation of a shim in a skill body or hook registration is a resolved
literal absolute path, and that a shim's exec of the artifact resolves
under the plugin data directory; a fixture with a `bin/` directory fails
it, as does a fixture shim invoked through an unresolved variable path.

### REQ-F1.2 — Attested, pinned, fail-closed fetch [test]

The fetch shim is exercised against a local fixture server: a matching
checksum installs the artifact through a temporary path and atomic rename,
a mismatched checksum, a missing asset, and an absent hasher each fail
closed with the documented message naming the shell selector and the
reserved exit code, leaving no file behind, and the artifact is not
executable before verification; two concurrent first uses serialize
through the lock; a superseded version's artifact is removed after a
successful fetch; the three options resolve through the configuration
defaults file; the release workflow's attestation step and NOTICE
generation are asserted by the guard Task 10 delivers.

### REQ-F1.3 — Version check [test]

The shim refuses an artifact whose embedded version string is not equal
to the installed manifest's, asserted by a fixture pair, and fails closed
on a fixture manifest version with no published asset.

### REQ-F1.4 — State under the plugin data directory [test]

The shim's write paths are asserted to resolve under `CLAUDE_PLUGIN_DATA`
in plugin mode and under the writer's per-plugin state home in writer
mode, never under the plugin root, with a fixture where the plugin root is
read-only.

### REQ-F1.5 — Writer delivery [test + manual]

The writer job in CI installs the shim, executes the fetched artifact,
and reads back the manifest's version; the fresh-machine install through
both modes is the one `[manual]` entry, owned by the operator, its
observable being the named adopter-tier entry point producing its recorded
output on a fresh VM or container image per platform plus one macOS host
that has never run planwright, recorded under `docs/` with machine
description and date and cited from the delivery task's PR.

### REQ-F1.6 — macOS first execution [test]

The macOS matrix job fetches an artifact through the shim, sets the
quarantine attribute on it, and executes it; the job fails if the first
execution stalls beyond the per-execution timeout the job names or is
refused by the platform.

## REQ-G — Cost-benefit record

### REQ-G1.1 — Cost baseline script [test]

The baseline script is run over a fixture repository with known history
and fixture fragments; the suite asserts the fix-rate, inflow-by-class,
and handoff fields match the fixture's known values, that the wall-clock
field is present and non-zero, and that the snapshot regenerates
byte-identically on the unchanged fixture.

### REQ-G1.2 — Cost-benefit line per verdict [design-level]

Each verdict decision carries migration effort, the projected ongoing
delta, eliminated versus relocated classes, the restructured-shell share
of the gain, and the stay-in-shell figures; verified at re-sign-off.

### REQ-G1.3 — Porting-rate and review-findings logs [test]

The harness self-test asserts the implementation-time and review-findings
log fields are present per full candidate and refuses a report without
them; a guard asserts a verdict's effort figure cites the logged rate or
carries the explicit absence token, and fails on a fixture verdict with
neither.

### REQ-G1.4 — Break-even statement [design-level]

Each verdict decision states a break-even condition as a threshold on a
cost-baseline field with its value, or its explicit absence; verified at
re-sign-off.
