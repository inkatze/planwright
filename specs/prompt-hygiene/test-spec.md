# Prompt Hygiene — Test Spec

**Status:** Done
**Last reviewed:** 2026-07-15
**Format-version:** 1

Coverage mix: 18 of 23 REQs carry `[test]` (all deterministic, run by
GitHub CI via `mise run check` / `mise run test`; the eval runner's logic
is tested against a stubbed `claude` on PATH so no CI run spends tokens);
4 REQs are `[design-level]` (the doctrine-prose REQs C1.1–C1.3 plus the
threshold-derivation record B1.5); judgment-shaped verifications are
`[manual]` with their recorded artifact named. Real behavioral eval runs
never execute in CI (D-8).

## REQ-A — Measurement & audit

### REQ-A1.1 — Ranked report [test]

`tests/test-check-instructions.sh`: a fixture instruction tree with known
word counts; assert `--audit` emits every file ranked by words with line
counts present. Runs under `mise run test` in GitHub CI.

### REQ-A1.2 — Start-load and closure computation [test]

Fixture skill with a manifest naming run-start and point-of-use docs of
known sizes; assert the computed mandatory-at-start and closure sums. A skill
with a **malformed** manifest yields the defined missing-manifest error; a
skill with **no** manifest is scored body-only (start-load = SKILL.md words,
no error). The manifest-completeness assertion flags a manifest-less skill
when the assertion is active (a fixture with the assertion on and a
manifest-less skill errors; with it off, the same skill scores body-only and
passes).

### REQ-A1.3 — Offender shortlist and diet plans [test + manual]

`[test]`: fixtures straddling the thresholds; assert the shortlist
contains exactly the over-threshold offenders (files over per-file floors
and skills over the start-load/closure budget), ranked. `[manual]`: the diet
plans recorded by Task 2's audit run are reviewed at the Task 5–7.5 PRs;
the recorded plans are the artifact.

### REQ-A1.4 — Injected-context measurement [test]

Fixture `hooks.json` registering a hook whose script emits an
`additionalContext` payload (literal prose plus a line with a `$(…)`
interpolation); assert `--audit` reports the injected-context class with the
static word count computed by excluding the interpolation line, and that the
hook is never executed (a fixture hook that would side-effect on execution
leaves no trace). A registered hook that is under the warn floor still yields
a report row (presence is always reported; the warning is REQ-B1.7's).

## REQ-B — Instruction guard

### REQ-B1.1 — Check-aggregate wiring [test]

Seeded-violation fixture (the per-guard pattern): a copy of the tree with
one file pushed over the error threshold makes `check:instructions` exit
non-zero; the clean tree passes; the task is present in the `check`
aggregate (asserted against `mise.toml`).

### REQ-B1.2 — Budgets and knobs [test]

Fixtures over/under each of the four budget classes assert warn vs error
vs pass; a threshold override via a temp
`.claude/planwright.local.yml` flips a failing fixture to passing
(config-get layering exercised).

### REQ-B1.3 — Exemptions and transitional allowances [test]

A permanent-exempted over-floor file passes with its reason echoed; the same
file still counts toward start-load/closure sums (assert a start-load and a
closure error survive the permanent exemption); an entry of either form
without a reason is an error. A transitional `pending diet (Task N)` allowance
on a start-load offender — and, identically, on a reachable-closure offender —
lets the check pass (the only form that may cover a start-load or closure
offender, transiently); removing it re-fails the offender.

### REQ-B1.4 — Options-reference rows [test]

The existing `scripts/check-options-reference.sh` (already in the check
aggregate) fails if any `instruction_budget_*` knob lacks its
`docs/options-reference.md` row.

### REQ-B1.5 — Grounded default thresholds [design-level]

D-2 records the derivation (official 500-line ceiling × measured corpus
words-per-line ratio → the four default pairs). Verification is the
decision's existence and coverage; the values themselves are knobs.

### REQ-B1.6 — Resolution check [test]

Fixture manifest naming a nonexistent rule doc fails with the offending
name; existing docs pass; point-of-use entries are checked identically to
run-start entries.

### REQ-B1.7 — Injected-context warn floor [test]

Fixture injected-context payload at or over the warn floor makes `--audit` /
`check:instructions` emit a warning but exit zero (never fails CI); a payload
exactly at the floor warns (`≥`, matching REQ-B1.8); under the floor still
emits the report row but no warning (the floor gates the warning, not the row —
REQ-A1.4). A fixture hook whose static prose cannot be extracted emits a
parse-failure **warning** and still exits zero (never a hard error — the
injected surface never fails CI). A floor override via a temp
`.claude/planwright.local.yml` moves the warn boundary (config-get layering
exercised).

### REQ-B1.8 — Fail-loud on malformed input and boundary semantics [test]

For each deterministic malformed-input class — a garbled/unrecognized manifest
entry, a malformed exemption/allowance entry, a missing/non-numeric threshold
knob — a fixture asserts the guard errors (never silently skips, zeroes, or
passes). A skill with **no** manifest is scored body-only and does **not** error
here (the missing-manifest error is malformed-only; REQ-A1.2). An injected-context
hook whose static prose cannot be extracted is out of scope for this fail-loud
assertion — it is a warn (REQ-B1.7), not an error. Boundary fixtures at exactly
the error and warn thresholds assert error and warn respectively (`≥`).

### REQ-B1.9 — Untrusted-input safety [test]

Fixtures with hostile PR-controllable content — a manifest entry / rule-doc
name containing shell metacharacters or `../` traversal, an exemption reason
with metacharacters — assert the guard neither shell-evaluates the content nor
resolves outside the resolution roots, and (with REQ-A1.4) never executes a
hook script.

## REQ-C — Authoring doctrine

### REQ-C1.1 — Authoring rule doc [design-level]

`doctrine/instruction-hygiene.md` exists, resolves via the resolution
chain, is indexed in `doctrine/README.md`, and covers the authoring rule;
lint:md and check:links guard its mechanics.

### REQ-C1.2 — Loading convention [design-level]

The doc defines always-loaded core vs point-of-use bulk and the safety
floor (gating law never deferred); application is exercised by the Task
5–7.5 diets and their manifests (Task 7.5 is the flagship point-of-use
reclassification).

### REQ-C1.3 — Test-and-measure principle [design-level]

The doc states the principle (instruction files are runtime artifacts;
nondeterminism changes verification's form and cadence, never whether).

### REQ-C1.4 — Kept prompt-eval convention [test + manual]

`[test]`: the stubbed-`claude` suite in `mise run test` drives the runner
deterministically: pass^k aggregation (2-of-3 fails, 3-of-3 passes),
budget-cap flags passed through, `system/init` plugin verification
(missing plugin aborts before grading), worktree teardown, cost captured
from the JSON payload. `[manual]`: a real on-demand `eval:skill` run
(Task 4's baseline) exercises the unstubbed path; its recorded result is
the artifact.

### REQ-C1.5 — Guard-catalog entry [test]

The merged guard catalog contains id `instruction-hygiene`
(`scripts/resolve-catalog.sh` view asserted in the test suite).

### REQ-C1.6 — Eval artifact hygiene and CI-exclusion guard [test]

`[test]`: against the stubbed-`claude` output, assert the recorded artifact
contains the per-fixture graded outcome, the fixture identifier, and cost, and
no machine-local path / username / session id (a fixture stub payload carrying
those is scrubbed; the fixture identifier is retained so the paired comparison
survives — REQ-D1.3). The
CI-exclusion guard (part of `mise run check`) fails on a fixture workflow that
wires an eval task into CI, and passes on the real workflow set.

## REQ-D — Diets & verification

### REQ-D1.1 — Offenders under budget [test + manual]

`[test]`: post-diet, `check:instructions` passes with the dieted files
carrying no suppression (permanent exemption or transitional allowance).
`[manual]`: "law moved verbatim in meaning, no contract change" is reviewed on
each diet PR against the Task 2 diet plan.

### REQ-D1.2 — Moved law resolvable [test + manual]

`[test]`: the REQ-B1.6 resolution check over the updated manifests confirms
every reference **resolves** (and the diet PRs keep `mise run check` green).
`[manual]`: resolution proves the reference points at an existing doc, not
that the law's *content* landed there — content-presence ("verbatim in
meaning") is the REQ-D1.1 `[manual]` review on each diet PR. The tag is split
so the mechanical claim is not overstated.

### REQ-D1.3 — Pilot before/after eval [manual]

The recorded artifacts are the verification: Task 4's baseline run and
Task 5's post-diet run on identical fixtures, pass^3 both sides, paired
comparison and per-run cost recorded under `tests/prompt-evals/`. "No
regression" is defined as: post-diet holds pass^3 on every paired fixture
(a fixture that passed pre-diet must still pass) and per-run cost is recorded
for review (cost is reported, not gated). Not a CI path by design (D-8).

### REQ-D1.4 — Zero grandfathered errors [test + manual]

`[test]`: a check (Task 8) fails if any suppression entry is a `pending diet`
allowance (per-file, start-load, or closure) — since a start-load or closure
offender can only be carried by such an allowance (REQ-B1.3b), this catches a
lingering start-load or closure offender, not just per-file ones. `[manual]`:
Task 8's closing audit re-run is
recorded and confirms every skill under the mandatory-at-start error
threshold.
