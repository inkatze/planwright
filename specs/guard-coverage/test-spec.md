# Guard Coverage — Test Spec

**Status:** Draft
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: fifteen REQs verify `[test]` (automated, running in this
repo's CI via `mise run check` or the test suite), one is `[manual]`
(the fork-PR audit, a human-reviewed record), and the doctrine amendment
and registration sweep are `[design-level]`. Mixed tags mark REQs whose
verification spans paths.

### REQ-A1.1 — matcher fixture test [test]

`tests/` gains the fixture-driven matcher test of Task 1: the table of
push/commit invocations asserted against the documented matcher model
and `config/worker-settings.json`. Verified by the test failing when a
covering deny rule is removed and passing on the current config.

### REQ-A1.2 — hook backstop rejections [test]

Git-fixture tests (Task 2) exercise each hook end-to-end in a scratch
repo: amend/squash/fixup at any flag position, rebase, and every fixture
`main`-push spelling rejected; normal commits and feature-branch pushes
succeed.

### REQ-A1.3 — hook wiring and absence detection [test + manual]

The unwired-clone check fails on a fixture clone without
`core.hooksPath` and passes on a wired one `[test]`; the install-path
wiring is exercised once by hand on a fresh clone and worktree and the
result recorded in the task PR `[manual]`.

### REQ-B1.1 — seeded reappearance detection [test]

Fixture tests (Task 3) plant a test-only seeded token in a scratch tree
and assert the check fails; a clean tree passes. The real check runs in
the `check` aggregate in CI.

### REQ-B1.2 — no plaintext seeds [test + design-level]

A test asserts the committed seed file matches the hash-only format (no
token of plaintext shape) `[test]`; the human-provisioning flow and the
accepted low-entropy-guessability caveat are reviewed against D-5 at
kickoff `[design-level]`.

### REQ-C1.1 — fork-PR audit record [manual]

The audit record in the kickoff brief risk register: surface enumerated,
sources consulted, conclusion stated against D-6. A falsifying finding
must appear as a design amendment, not silent absorption. Human-reviewed
at the task PR.

### REQ-C1.2 — workflow-posture check [test]

Fixture workflows containing `pull_request_target`, a `secrets.*`
reference reachable from `pull_request`, or missing read-only
permissions each fail `check:workflow-posture`; the repo's real
workflows pass. Runs in the `check` aggregate.

### REQ-D1.1 — transitive eval closure [test]

Synthetic `mise.toml` fixtures (Task 5): a CI-run task with a transitive
`depends` chain reaching `eval:` fails; a clean graph passes; the
current repo passes. Runs in the `check` aggregate.

### REQ-E1.1 — test-time budget gate [test]

Fixture timing reports over the per-file and total budgets fail
`check:test-time`; in-budget reports pass; the real suite runs green
under the committed budgets. Runs in the `check` aggregate.

### REQ-E1.2 — straggler split [test]

The post-split suite passes with assertion count not reduced from the
pre-split baseline, and no single file exceeds the per-file target on
the reference runner; measured times recorded in the Task 6 PR.

### REQ-E1.3 — Performance-lens target [design-level]

`doctrine/discovery-rigor.md`'s Performance lens names test/CI
ergonomics an explicit target. Existence and wording of the amendment is
the verification, reviewed at kickoff of the amendment.

### REQ-F1.1 — doctrine index completeness [test]

`check:doctrine-index` fixture tests: an unindexed fixture doctrine doc
fails; the current tree passes; removing a README row locally fails
`mise run check`.

### REQ-F1.2 — capability-contract agreement [test]

The table-vs-`caps_for()` test fails on a fixture mismatch in either
direction and passes on the current pair.

### REQ-F1.3 — fleet knobs tether [test]

The widened `check-options-reference` fails on a fixture divergence
between `docs/fleet.md` knob defaults and `config/defaults.yml`, and
passes on the current tree.

### REQ-G1.1 — templates linted [test]

`lint:md`'s glob covers `templates/**/*.md`; verified by the lint run in
CI and a deliberate fixture violation failing locally during Task 10.

### REQ-G1.2 — CDPATH house pattern [test]

Fixture tests: a script using `$(cd ...)` without top-level
`unset CDPATH` fails the check; a compliant script passes; the current
tree passes.

### REQ-H1.1 — pinned-action-freshness catalog entry [test + design-level]

The `config/guard-catalog.yaml` entry passes the existing schema/lint
checks `[test]`; the prose entry's signal-only (no auto-bump) framing is
reviewed against D-13 at kickoff `[design-level]`.

### REQ-H1.2 — guard registration sweep [design-level]

The Task 11 sweep record maps every shipped guard to its `check`
aggregate entry and doc location; its existence and completeness is the
verification, human-reviewed at the Task 11 PR.
