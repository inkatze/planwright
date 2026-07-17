# Guard Coverage — Test Spec

**Status:** Draft
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix (nineteen REQs): most verify `[test]` (automated, running
in this repo's CI via `mise run check` or the test suite), one is pure
`[manual]` (the fork-PR audit, a human-reviewed record), one is pure
`[design-level]` (the doctrine amendment), and four are mixed
(`A1.3`, `B1.2`, `H1.1`, `H1.2`). Mixed tags mark REQs whose
verification spans paths. Every guard's fixtures include a
vacuous-input case per REQ-H1.3.

## REQ-A — Worker permission-deny hardening

### REQ-A1.1 — matcher fixture test [test]

`tests/` gains the fixture-driven matcher test of Task 1: the table of
push/commit invocations (force forms; every `main` spelling including
flags after `main`; the `--amend -m`/`--amend -F` and
`--fixup=amend:`/`--fixup=reword:` families; hook-bypass spellings
`--no-verify` and `git -c`/`git config` `core.hooksPath` crossed with
push/force/amend) asserted against the documented matcher model and
`config/worker-settings.json`. Each row is tagged load-bearing
(expected-deny regression guard) or honest documentation of a current
allow; the test verifies config-vs-model equivalence only (real-matcher
fidelity is the manual re-verify of risk row 1). Verified by the test
failing when a covering deny rule is removed, erroring on an empty or
unparseable deny set, and passing on the current config.

### REQ-A1.2 — hook backstop rejections [test]

Git-fixture tests (Task 2) exercise each hook end-to-end in a scratch
repo against a pinned minimum spelling set: amend (positions the hook
can detect), squash/fixup any position, `amend!` subjects, rebase
(and `git pull --rebase`), and every enumerated `main`-push spelling
(`HEAD:refs/heads/main`, `HEAD:main`, `+refs/heads/main`, a feature
branch whose upstream is main, `HEAD` while on main) rejected; normal
commits and feature-branch pushes succeed. The `--amend -m`/`-F` family,
undetectable by the client hook, is asserted denied at the glob layer
(REQ-A1.1) instead, with that boundary recorded.

### REQ-A1.3 — hook wiring and absence detection [test + manual]

The detection check fails on a fixture clone with `core.hooksPath`
unset, pointing elsewhere, or missing/non-executable hook files, and
passes only on a fully wired clone `[test]`; its CI behavior is pinned
to wire-then-verify and a fixture asserts it cannot degrade to a silent
skip `[test]`; the dedicated wire step is exercised once by hand on a
fresh clone and worktree and recorded in the task PR `[manual]`.

## REQ-B — Purged-identifier guard

### REQ-B1.1 — seeded reappearance detection [test]

Fixture tests (Task 3) plant a test-only seeded token in a scratch tree
and assert the check fails; a clean tree passes; a normalization-
equivalent variant (case, separator, or embedded in a URL/`mailto:`/
slug) of a seeded token is still caught, and a deliberately
out-of-scope variant passes, pinning the normalization boundary both
ways. A fixture commit whose message contains a planted token is
rejected by both the `commit-msg` hook and the CI-side commit-range
scan. A missing/empty/zero-hash seed file fails closed. The real check
runs in the `check` aggregate in CI.

### REQ-B1.2 — no plaintext seeds and non-vacuity floor [test + design-level]

A test asserts the committed seed file matches the hash-only format (no
token of plaintext shape) and meets the committed minimum-real-seed
count so the guard cannot run green empty `[test]`; the human-
provisioning flow (non-logging stdin path) and the accepted
low-entropy-guessability caveat are reviewed against D-5 at kickoff
`[design-level]`.

## REQ-C — Fork-PR CI isolation

### REQ-C1.1 — fork-PR audit record [manual]

The audit record in the kickoff brief risk register: the `pull_request`
and `workflow_run` reachable surface enumerated (permissions, secret
references, cache poisoning, artifact writes), sources consulted,
conclusion stated against D-6. A falsifying finding must appear as a
design amendment, not silent absorption. Human-reviewed at the task PR.

### REQ-C1.2 — workflow-posture check [test]

Fixture workflows each fail `check:workflow-posture` for:
`pull_request_target`; a non-`GITHUB_TOKEN` `secrets.*` or
`secrets: inherit` reachable from `pull_request` (including through a
reusable-workflow `uses:` call); a job-level write-permission
escalation under a read-only top level; and a `workflow_run` workflow
holding write permissions or secrets that drops its base-branch filter
or consumes a PR artifact. Passing fixtures: only `secrets.GITHUB_TOKEN`
under
read-only permissions; a non-`GITHUB_TOKEN` secret in a push/
`workflow_run`-only workflow with no `pull_request` trigger (pinning
reachability scoping). An unparseable workflow fails closed. The repo's
real workflows pass. Runs in the `check` aggregate.

## REQ-D — CI-eval exclusion transitivity

### REQ-D1.1 — transitive eval closure [test]

Synthetic `mise.toml` fixtures (Task 5): a CI-run task reaching `eval:`
through a transitive `depends`, `depends_post`, or `wait_for` chain
fails, as does a run-body `mise run eval:…` and a run-body invoking an
intermediate task that reaches `eval:`; an unparseable or zero-task
`mise.toml` fails closed; a clean graph passes; the current repo
passes. Runs in the `check` aggregate.

## REQ-E — Test/CI wall-clock budget

### REQ-E1.1 — test-time budget gate [test]

Fixture timing reports at-or-over the per-file or total budget fail
`check:test-time`; under-budget reports pass; a report missing an entry
for a discovered file, or an empty/malformed report, fails closed; a
capture round-trip test asserts the runner emits a non-empty,
plausibly-bounded per-file time for a known test. The real suite runs
green under the committed budgets in CI (no second suite invocation).
Runs in the `check` aggregate.

### REQ-E1.2 — straggler split [test]

The post-split suite passes with the assertion count (emitted verdict
lines, a mechanically defined metric) not reduced from the pre-split
baseline; per-file wall-clock is measured across all test files on the
reference runner (GitHub Actions CI) in a dedicated measurement run
outside the 15-minute `check` job with a per-file best-of-N noise bound,
and no file exceeds the accepted split target; measured times recorded in
the Task 6 PR.

### REQ-E1.3 — Performance-lens target [design-level]

`doctrine/discovery-rigor.md`'s Performance lens names test/CI
ergonomics an explicit lens target for reviewers, noting the mechanical
catch is REQ-E1.1's gate. Existence and wording of the amendment is the
verification, reviewed at kickoff of the amendment.

## REQ-F — Drift tethers

### REQ-F1.1 — doctrine index completeness [test]

`check:doctrine-index` fixture tests (bijection both directions): an
unindexed fixture doctrine doc fails, and a stale README row pointing at
a removed doc fails; a missing README, unparseable index table, or empty
doctrine-doc set fails closed; the current tree passes; removing a
README row locally fails `mise run check`.

### REQ-F1.2 — capability-contract agreement [test]

The drift test asserts the doctrine prose table, `caps_for()`, and
`docs/fleet.md`'s backend table agree under the specified normalization
contract (`n/a`↔`na`, annotations/backticks stripped); it fails on a
fixture mismatch in any of the three surfaces, fails closed if any side
parses to zero rows, and passes on the current agreeing triple.

### REQ-F1.3 — fleet knobs tether [test]

The widened `check-options-reference` fails on a fixture divergence for
each of the six `docs/fleet.md` knob defaults against
`config/defaults.yml` (a per-knob divergence fixture proves all six are
individually tethered), fails closed on a zero-row fleet-table parse,
and passes on the current tree.

## REQ-G — Lint scope and house patterns

### REQ-G1.1 — templates linted [test]

`lint:md`'s glob covers `templates/**/*.md`, verified by a committed
assertion that the resolved `lint:md` target set includes a
`templates/**/*.md` path (so a future glob narrowing fails a test) plus
a deliberate fixture violation failing locally during Task 10.

### REQ-G1.2 — CDPATH house pattern [test]

Fixture tests: a script (and an extensionless `githooks/` hook, reached
by shebang enumeration) using `$(cd ...)` without top-level
`unset CDPATH` fails the check; a compliant script passes; one
representative cd-resolving script is exercised under `CDPATH=.` and
produces correct paths; the current tree passes.

## REQ-H — Guard catalog and guard robustness

### REQ-H1.1 — pinned-action-freshness catalog entry [test + design-level]

The `config/guard-catalog.yaml` entry (with declared `category` and
core-vs-breadth) passes the schema check that asserts required fields
and category enum membership `[test]`; the signal-only (no auto-bump)
and degraded-network (loud unknown) framing is reviewed against D-13 at
kickoff `[design-level]`.

### REQ-H1.2 — guard registration sweep and standing check [test + design-level]

A standing check asserts every `check:`/`lint:`/`scan:` task is wired
into the `check` aggregate; a fixture unregistered guard fails it and
the real tree passes `[test]`. The Task 11 sweep record maps every
shipped guard to its `check` aggregate entry and doc location
(`docs/CONTRIBUTING.md` quality gate, dogfooding list); its existence
and completeness is human-reviewed at the Task 11 PR `[design-level]`.

### REQ-H1.3 — fail-closed guard posture [test]

Each guard this spec ships has a fixture proving it exits non-zero on
its vacuous-input case — a zero-hash seed file (B1.1), an unparseable
workflow (C1.2) or `mise.toml` and zero workflow roots (D1.1), a timing
report missing a discovered file (E1.1), a zero-row reference table
(F1.2/F1.3), a missing README (F1.1), a zero-file shebang enumeration
for the CDPATH check (G1.2), a zero-task parse for the registration
check (H1.2), or a failed fixture setup — rather than passing
vacuously.
