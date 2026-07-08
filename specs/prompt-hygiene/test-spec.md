# Prompt Hygiene — Test Spec

**Status:** Draft
**Last reviewed:** 2026-07-08
**Format-version:** 1

Coverage mix: 11 of 16 REQs carry `[test]` (all deterministic, run by
GitHub CI via `mise run check` / `mise run test`; the eval runner's logic
is tested against a stubbed `claude` on PATH so no CI run spends tokens);
4 doctrine-prose REQs are `[design-level]`; judgment-shaped verifications
are `[manual]` with their recorded artifact named. Real behavioral eval
runs never execute in CI (D-8).

## REQ-A — Measurement & audit

### REQ-A1.1 — Ranked report [test]

`tests/test-check-instructions.sh`: a fixture instruction tree with known
word counts; assert `--audit` emits every file ranked by words with line
counts present. Runs under `mise run test` in GitHub CI.

### REQ-A1.2 — Start-load and closure computation [test]

Fixture skill with a manifest naming run-start and point-of-use docs of
known sizes; assert the computed mandatory-at-start and closure sums; a
skill without a manifest yields the defined missing-manifest error.

### REQ-A1.3 — Offender shortlist and diet plans [test + manual]

`[test]`: fixtures straddling the thresholds; assert the shortlist
contains exactly the over-threshold files, ranked. `[manual]`: the diet
plans recorded by Task 2's audit run are reviewed at the Task 5–7 PRs;
the recorded plans are the artifact.

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

### REQ-B1.3 — Exemptions [test]

An exempted over-floor file passes with its reason echoed; the same file
still counts toward start-load/closure sums (assert a closure error
survives the exemption); an exemption entry without a reason is an error.

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

## REQ-C — Authoring doctrine

### REQ-C1.1 — Authoring rule doc [design-level]

`doctrine/instruction-hygiene.md` exists, resolves via the resolution
chain, is indexed in `doctrine/README.md`, and covers the authoring rule;
lint:md and check:links guard its mechanics.

### REQ-C1.2 — Loading convention [design-level]

The doc defines always-loaded core vs point-of-use bulk and the safety
floor (gating law never deferred); application is exercised by the Task
5–7 diets and their manifests.

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

## REQ-D — Diets & verification

### REQ-D1.1 — Offenders under budget [test + manual]

`[test]`: post-diet, `check:instructions` passes with the dieted files
absent from the exemption list. `[manual]`: "law moved verbatim in
meaning, no contract change" is reviewed on each diet PR against the
Task 2 diet plan.

### REQ-D1.2 — Moved law resolvable [test]

Covered mechanically by the REQ-B1.6 check over the updated manifests;
the diet PRs keep `mise run check` green.

### REQ-D1.3 — Pilot before/after eval [manual]

The recorded artifacts are the verification: Task 4's baseline run and
Task 5's post-diet run on identical fixtures, pass^3 both sides, paired
comparison and per-run cost recorded under `tests/prompt-evals/`. Not a
CI path by design (D-8).

### REQ-D1.4 — Zero grandfathered errors [test + manual]

`[test]`: a check (Task 8) fails if any exemption reason matches
`pending diet`. `[manual]`: Task 8's closing audit re-run is recorded and
confirms every skill under the start-load error threshold.
