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

The **`tower` fixture** is the routing gate: a deterministic stand-in for the
`/tower` router, one persona per acceptance scenario (chat-only, split-screen,
refusal to merge, escalation, walk-away/resume) and per routing case set
(consecutive asks with no mode state, the four escalation cases, the three
overrides, the kickoff offered and never started, orchestration on an explicit
go only). See "Tower routing" below.

## Layout

```text
tests/behavioral-evals/
  README.md                 this file
  fixtures/<id>/            one directory per fixture (greeter, kickoff, tower)
    fixture.conf            id, skill, personas, turns, anchor, footer_lines
                            (KEY=VALUE, data only)
    skill.sh                the interactive program the harness drives
    personas/<name>.persona a simulated-operator answer script (expertise +
                            answer.<turn> lines; data only)
    grade.jq                the structural (invariant) grade over the artifacts
  turn-shape/<id>/          the turn-shape fixtures (see "Turn shape" below);
    fixture.conf            as above, plus runs= and the turn_* grading keys
    skill.sh                execs lib/turn-surface.sh with this fixture's scenario
    scenario.jsonl          what the stand-in surface emits and asks
    personas/<name>.persona as above
  lib/tmux-stub.sh          the shared faithful tmux double the hermetic tests use
  lib/turn-surface.sh       the stand-in every turn-shape fixture replays
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

## Turn shape

The turn-shape invariants grade what an attended surface put in front of the
operator, from the **turn records** it mirrors into the decision log (each
projection it emits, as emitted). They run on demand as `mise run
eval:turn-shape`, the harness over `turn-shape/`; `scripts/turn-shape-grade.sh`
is the grader and `tests/test-turn-shape-eval.sh` drives it hermetically.

### The turn-record schema (v2)

The log's records follow the form `doctrine/kickoff-dialogue.md` documents: a
schema version `v`, a monotonic `seq`, the `phase`, and a `kind` of `present`,
`ask`, `answer`, `decision`, or `turn`. No record was ever written as `v: 1`;
`v: 2`, the version that adds turn records, is the first value recorded. A
turn record carries:

| Field | Meaning |
| --- | --- |
| `surface` | the skill that emitted the turn |
| `projection` | its class: `handoff`, `ci-failure`, `drain-report`, `resume-lead`, `step-report`, `halt-batch`, `lens-pass`, `running-summary`, `open-captures`, `resume-confirmation`, `selector`, `capture-proposal` |
| `text` | the turn exactly as emitted, after the echo-safety sanitizer |
| `sections` | the turn's parts in order, each a `role` (`decision`, `question`, `request`, `state`, `reasoning`, `bookkeeping`) and the `text` it covers; a `request` may name the `capture` recording it |
| `full_record` | the artifact holding the whole record the turn projects |
| `selector` | a selector's `question` and `options` (`label`, `description`) |
| `captures` | the tracked forms a capture proposal offers (`id`, `target`, `form`) |

An `answer` to a capture proposal carries `confirms` or `declines` with the
item's id, and a written capture is a `decision` whose `capture` names its
`id`, `target` (`awaiting-input`, `deferred`, or `observation`), and `ref`.

The kickoff fixture's records predate the versioned form: an integer `turn`
index, kinds `question` / `explanation` / `confirmation` / `summary`, and no
`v`, `seq`, or `phase`. Its `grade.jq` and the rubric scripts read that shape,
and the turn-shape grader reads only `v: 2` records, so the two never collide;
moving the kickoff fixture onto the documented form is a separate change.

### The invariants

| Invariant | Fails when |
| --- | --- |
| `no-table-dump` | a turn carries more tables than the fixture allows |
| `projection-present` | a turn runs past its length or (where the fixture says) section bound, or a projection of a larger record does not point at an artifact that exists, is larger than the turn, and (where the fixture says) carries the full record's tables |
| `decisions-first` | a decision, question, or request comes after supporting state, reasoning, or bookkeeping |
| `no-monotonic-growth` | a repeated summary or open-captures list restates every state line of the one before, or a resume confirmation spends more than one line on a settled section |
| `identifier-density` | a selector carries more REQ, D, or observation identifiers than the fixture allows, or an option lacks its action (`label`) or consequence (`description`) |
| `capture-at-birth` | the planted item is confirmed but not written to tracked state, was never proposed first, or a declined item was tracked anyway |
| `step-report-slots` | a step report strays outside the state / reasoning / requests slots, runs its reasoning past two lines, or leaves a request uncaptured |
| `open-captures-list` | a phase ends without showing the open-captures list |

Every tunable threshold lives in the fixture's `turn_*` keys, never in
doctrine or the grader: doctrine keeps the density bound qualitative, and a
listed invariant whose threshold the fixture omits is a config error. The
shapes doctrine fixes itself (one line per settled section, one or two lines
of reasoning) are part of the invariant. `runs=` sets the pass
threshold: every persona passes on every run, so a flake is a failure.

A **wall** fixture plants turns that break named invariants and lists them in
`turn_expect_fail`; it grades clean only if exactly those fail, each for a
reason with something to grade. A run that emitted nothing can never satisfy
an expected failure. Each wall pairs with a conforming fixture, and the unit
test grades every invariant alone against both sides of its pair.

The fixtures are deterministic stand-ins; a live surface mirrors its own
turns into this log, and the mirror is self-reported,
so a divergence between the pane and the log is the residual these
invariants cannot see.

## Tower routing

The `tower` fixture's artifacts follow the eval-only seam
`doctrine/flight-rules.md` specifies (*Eval-only runs*): a decision log of
operator turns, evidence events, what was said, and each route, dispatch,
refusal, offer, hold, and reconstruction; and a run record that is eval-only,
non-authoritative, and a sign-off of nothing. Persona lines starting
`@event:` stand for durable evidence the tower reads (a landing, a sign-off, a
spec PR merge, a finished draft, a session restart), never the operator's
words, so an event can never count as a go, a yes, or an override. The line
`that's all` ends the session.

`grade.jq` holds every run to the routing floor (every route states its
grounds; automatic triggers and ambiguity file, size never does; an override
across a trigger states its reservation; a flight follows its own route and a
read-only look mints none; a draft follows the one-page case and the
operator's yes; orchestration follows the operator's own go for a signed spec;
no merge, ready flip, or kickoff is performed; no mode, no verdict, no silent
turn) and pins each named persona's routes, dispatches, refusals, and offers.
`tests/test-behavioral-eval-tower.sh` runs it hermetically, end to end through
the harness and directly, with a negative case for each rule.

**Harness operability caveat.** The fixture is a shell model of the routing
rule, so a pass shows the rule, the artifact contract, and the grade hold
together; it does not show that the model-backed `/tower` routes an unseen
ask the way the rule says. That needs a live Claude TTY session writing the
same artifacts, which is nondeterministic, priced, and on demand. When the
harness cannot drive a live tower (no tmux, no model or credentials, or the
session's surface not settling on the harness's anchor), routing
verification falls back to the operator: the same scenarios are run by hand,
through the acceptance demo script, and judged against the same floor. That
fallback changes who runs the scenarios, never whether the gate must pass
before any user-facing doc claims the routing behavior.

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
The harness is registered under the `eval:` mise namespace (`eval:behavioral`
and `eval:turn-shape`) so
`scripts/check-no-ci-evals.sh` — the standing CI-exclusion guard — covers it: the
guard fails loud if any `eval:` task (or a direct `behavioral-eval.sh` call) is
ever wired into a workflow file, and equally if any task CI does invoke reaches
one through the task graph declared in `mise.toml`. Never add them to
`mise run check` or `.github/workflows/`.
