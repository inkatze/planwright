# Instruction-budget headroom — Test Spec

**Status:** Ready
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: the guard mechanics are `[test]` via fixtures in
`tests/test-check-instructions.sh`, executed by `mise run check` on GitHub
CI; the policy-prose requirements are `[design-level]`; restoration
outcomes are `[test + manual]` (the guard's real-corpus run must be
breach-free and a human confirms meaning preservation per diet PR); the
re-land and text fixes are `[manual]`.

## REQ-A — Standing headroom policy

### REQ-A1.1 — Headroom floors defined [design-level + test]

The amended instruction-hygiene doc states the four floors and their knob
names; a fixture corpus with a surface whose margin is below its floor
emits the named floor-breach warning, and the knob values in
`config/defaults.yml` drive the comparison.

### REQ-A1.2 — Restoration ladder [design-level]

The doctrine amendment states the four rungs in order with their entry
conditions; the artifact's existence and coverage is the verification.

### REQ-A1.3 — Safety floor on every rung [design-level]

The doctrine amendment states that no rung defers gating law and names the
human-escalation path; each reclassification task's recorded analysis
(REQ-C1.3) exercises it.

### REQ-A1.4 — Recorded rationale for raises and exemptions [test]

Existing guard behavior (a reason-less suppression entry is an error) is
pinned by fixture and extended to the raise discipline per D-12: a fixture
raising an `instruction_budget_*_warn/_error` knob above its core default
with no matching `raise|` entry fails the guard's config parsing, and the
same raise with a matching `raise|<knob>|<value>|<reason>` entry passes —
both directions fixtured. A stale `raise|` entry (knob at or below its
core default, or unknown) is also a config error, fixtured; so is an
absent or unreadable core-default baseline. A raised floor knob trips
nothing (out of scope by suffix).

### REQ-A1.5 — Restoration target [design-level + test]

The doctrine defines the 2×-floor target and the declared-exception path;
the guard's below-target warning (D-11, REQ-D1.6) plus Task 11's
exit-zero assertion verify real-corpus margins at or above target, with
`declared-exception` entries excusing recorded shortfalls.

## REQ-B — Exempt-doc aggregate coupling

### REQ-B1.1 — Capped charge [test]

Fixture: a permanently exempt doc over its per-file error threshold
charges min(actual, threshold) to both a dependent start-load and a
dependent closure; a non-exempt doc in the same fixture stays fully
charged.

### REQ-B1.2 — Honest reporting [test]

Fixture: the audit line for a capped doc shows both the actual and the
charged word counts; aggregate lines distinguish charged totals.

## REQ-C — Restoration passes

### REQ-C1.1 — Surfaces restored [test + manual]

The real-corpus guard run at Task 11 exits zero with no unmeasured
surfaces, no floor-breach warning, and no unexcepted below-target or
use-site warning
(the closure-margin target assertions relocated from Tasks 7 and 9 at
kickoff §6 are carried by the below-target check — see REQ-A1.5 and
REQ-D1.6), asserted in CI on the closing PR; a human reviews the closing
audit output.

### REQ-C1.2 — Diet discipline [test + manual]

Each diet PR runs the content-pinned structural tests
(`tests/test-*.sh` greps over skill bodies) green in the same PR; a human
confirms law is preserved verbatim in meaning against the governing REQ/D
text before merge.

### REQ-C1.3 — Reclassification rules [test + design-level]

The Task 5 use-site check passes for each reclassified doc; the manifest
parses under the guard; the recorded safety-floor analysis in the task's
PR is the design-level artifact.

### REQ-C1.4 — Guidance re-land [manual]

`doctrine/spec-format.md`'s versioning section carries the
`migrate-format-version.sh` guidance and the guard stays green on the
landing PR.

## REQ-D — Guard tooling

### REQ-D1.1 — Margin report and breach warning [test]

Fixtures both ways: a below-floor surface warns with the named finding; a
surface exactly at its floor is compliant (breach is strict:
margin < floor); a compliant surface produces no breach line; a missing
or non-numeric floor knob aborts fail-loud; `--audit` rows carry
margin-to-warn and margin-to-error for the four floored classes (the
injected surface stays warn-only, no floor row); a permanently exempt
doc over its per-file threshold produces no floor-breach row (its
existing exempt over-budget notice stands). Task 2's control-byte
fixture pins the echo-safety discipline on the newly echoed warning
values (cross-cutting).

### REQ-D1.2 — Task field visible [test]

Fixture: retagging a pending-diet allowance's Task field visibly changes
the shortlist and ranked-report output the tests assert.

### REQ-D1.3 — Reverse use-site check [test]

Fixtures: a point-of-use manifest doc unnamed in body prose warns naming
the skill and doc; the same doc named at a step silences the warning;
manifest-block lines and fenced code do not count as naming (a doc named
only there still warns). Matching is fixed-string over the
charset-validated name; a skill whose manifest failed to parse or resolve
is skipped by this check.

### REQ-D1.4 — Derived shortlist expectations [test + design-level]

The section-0 real-corpus present-offender expectations are computed from
the suppression list; adding an exemption in a fixture copy changes the
expectations without editing any test name list. The dieted-clean
absent-checks are structurally underivable from the suppression list and
remain an explicit, maintained name list.

### REQ-D1.5 — Stale exemption text corrected [test + manual]

The spec-format exemption rationale in
`config/instruction-budget-exemptions.txt` no longer claims the doc is
the dominant run-start load for /spec-draft and /spec-kickoff, refreshes
the stale trim-gap figures, and states the capped-charge semantics; a
grep content-pin (old phrase absent, new phrase present) runs in the
suite, and a human reviews the rewritten text on Task 3's PR.

### REQ-D1.6 — Below-target warning and declared exceptions [test]

Fixtures: a floored surface with margin between floor and target emits
the named below-target warning; a matching
`declared-exception|<surface>|<reason>` entry silences it; the same entry
never silences a floor-breach warning; a reason-less declared-exception
entry is a config error; a `use-site:<skill>/<doc>` key excuses a
use-site warning (REQ-D1.3) and nothing else; a stale entry whose named
warning no longer fires produces the named cleanup warning, not an
error.
