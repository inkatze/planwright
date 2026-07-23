# Behavioral evals

The on-demand behavioral eval harness (operator-dialogue Task 5; `design.md`
D-8, REQ-G1.1–REQ-G1.6). Where the kept prompt-evals (`tests/prompt-evals/`)
drive a skill **headlessly** and grade observable outcomes, this harness drives
a skill through a **real interactive TTY session** — a tmux session driven by
`send-keys` + `C-m`, idle detected by a positive footer anchor
(`scripts/fleet-pane-detect.sh`) — so the picker and dialogue surfaces are
exercised exactly as the operator sees them. It grades the **durable artifacts a
run writes** (a structured decision log and an eval-only sign-off record), never
a scraped pane.

It runs **on demand**, never in CI (see "Never in CI" below).

The `greeter` fixture is the **scaffold** (Task 5): a generic fixture skill that
demonstrates the harness. The **`kickoff` fixture** (Task 6) is the
measurable-acceptance layer: a deterministic stand-in for the real `/spec-kickoff`
surface that pins the assertable invariants (self-contained option set, absence
of verdict tokens, preserved normative tokens, completeness), the novice/expert
persona pilots, and the changed-answer/input-robustness paths. Driving the true
model-backed `/spec-kickoff` needs a live Claude TTY session (nondeterministic,
priced), so the invariants are pinned against the fixture; the experiential
qualities remain scored by the rubric instrument (`rubrics/`) and the human.

## Layout

```text
tests/behavioral-evals/
  README.md                 this file
  fixtures/<id>/            one directory per fixture (greeter, kickoff)
    fixture.conf            id, skill, personas, turns, anchor, footer_lines
                            (KEY=VALUE, data only)
    skill.sh                the interactive program the harness drives
    personas/<name>.persona a simulated-operator answer script (expertise +
                            answer.<turn> lines; data only)
    grade.jq                the structural (invariant) grade over the artifacts
  lib/tmux-stub.sh          the shared faithful tmux double the hermetic tests use
  rubrics/                  the CDC CCI + IPDAS experiential-quality instrument
                            (see rubrics/experiential-rubrics.md)
```

## Running it

```sh
mise run eval:behavioral                                   # the whole suite
scripts/behavioral-eval.sh --suite tests/behavioral-evals/fixtures
scripts/behavioral-eval.sh tests/behavioral-evals/fixtures/greeter
scripts/behavioral-eval.sh --persona novice \
  --grader ./my-panel-grader.sh --grader-id ext-panel \
  --record /tmp/be-results tests/behavioral-evals/fixtures/greeter
```

The real-tmux path needs `tmux` and `jq` on `PATH`. The hermetic branch coverage
(`tests/test-behavioral-eval.sh` for the harness, `tests/test-behavioral-eval-kickoff.sh`
for the kickoff acceptance layer, and `tests/test-rubric-instrument.sh` for the
rubric grader/self-audit — all run by `mise run test`) uses the shared **stub
tmux** (`lib/tmux-stub.sh`) that replays the driver's answers through the real
fixture skill, so CI needs no tmux, model, or API key.

## Grading and the independence firewall

Grading is two-layer:

- **Structural (invariant) grade** — `grade.jq` over the merged artifacts. A
  mechanical check (non-empty log, an eval-only / non-authoritative sign-off), so
  it runs harness-side; it is not a quality opinion.
- **Experiential grade** — the **independent grader** (`--grader`, a non-Anthropic
  panel backend) with the human as final rater. Its id (`--grader-id`) MUST differ
  from the driver id (self-grading is refused fail-closed). With no independent
  grader — or one that is unavailable — the run **degrades to human-rater**
  (`outcome: human-rater-required`) and substitutes **no** self-graded score
  (REQ-G1.4, REQ-H1.3).

## Personas

Each persona parameterizes the simulated operator by expertise (at minimum a
domain-novice and a domain-expert), so the adaptive-level requirement is
behaviourally testable by comparing how the skill pitched to each (REQ-G1.2). The
`greeter` fixture demonstrates the divergence: the novice is taught in full, the
expert gets the brief form, and the chosen depth is recorded in each run's
decision log.

## Security (REQ-G1.6)

The harness honors `doctrine/security-posture.md`'s framework-script disciplines:
persona text is sanitized before `send-keys`; the disposable-tree teardown is
containment-checked after canonicalization; the structured log is emitted and
parsed in an escape-safe, non-code-bearing form; surfaced artifact values pass
the echo-safety sanitizer; only fixture content reaches a third-party grader;
grader-backend credentials are read from the environment / a secret store, never
committed or recorded; the session runs with publishing disabled
(`PLANWRIGHT_PUBLISH_DISABLED=1` — no push / PR / ready flip); and any
driver-produced sign-off is stamped eval-only / non-authoritative so it can never
be mistaken for a human sign-off.

## Isolation & hygiene (REQ-G1.5)

Each run gets a disposable tree under `$BEHAVIORAL_EVAL_WORKBASE`, a
per-run-unique tmux session name (with stale sessions from crashed prior runs of
the same fixture+persona reaped first), a per-persona turn/poll ceiling, and an
allowlisted scalar-only recorded result (fixture, persona, outcome, driver/grader
ids, structural pass, cost — nothing more, re-verified before write).

## Never in CI

Behavioral evals are on-demand by design (D-8): they cost time, need tmux (and,
for the real Task-6 surface, a model + credentials), and gate nondeterministically.
The harness is registered under the `eval:` mise namespace so
`scripts/check-no-ci-evals.sh` — the standing CI-exclusion guard — covers it: the
guard fails loud if `eval:behavioral` (or a direct `behavioral-eval.sh` call) is
ever wired into a workflow file. Never add it to `mise run check` or
`.github/workflows/`.
