---
name: builder
description: >
  Detect a project's stack and recommend or apply the universal mechanical
  quality guards from planwright's core catalog (formatter, linters,
  type-checker, test runner, secret scan, commit hooks, CI gate), plus the
  growable breadth dimensions. Escalates stake-bearing decisions (auth, data
  modeling, security posture, integration surface) into the deferral
  mechanism instead of auto-defaulting them. Plugs into /spec-draft's design
  phase and /execute-task's guard-application step.
argument-hint: "[<target-dir>] [--apply | --recommend]"
---

# /builder

The engineering builder of the planwright pipeline (REQ-G1.2, D-15): the
mechanism that gives a project the quality floor a principal engineer would
set up — the formatter, the linters, the test runner, the secret scan, the
commit and CI gates — by detecting the stack and applying the guards that
stack warrants, so no human re-decides them each time. Its harder job is the
inverse: recognizing the decisions that look mechanical but are
architecture-defining, and escalating those instead of stamping a default
(REQ-G1.3, D-16).

The builder is both a standalone skill (point it at a project to audit or set
up its guards) and a hook the authoring and execution skills call into (the
lifecycle wiring below). It recommends and applies; it never merges, never
marks a PR ready, and never auto-defaults a load-bearing decision.

## Doctrine

This skill is procedure, not doctrine. Resolve and read these rule docs at
run start via the rule-doc resolution convention
(`scripts/resolve-rule-doc.sh <doc-name>` under the resolved planwright root,
or the documented `PLANWRIGHT_ROOT`/`CLAUDE_PLUGIN_ROOT` chain); their
definitions govern wherever this skill names a concept:

- `guard-catalog` — the normative core catalog: guard categories, the entry
  format, breadth dimensions, the extension model, and the dogfood contract.
  Its machine view is `config/guard-catalog.yaml`, read by
  `scripts/builder-guards.sh`.
- `engineering-decisions` — the decision ladder (idiom → tooling →
  mature-project research) and the no-flattening rule the escalation step
  applies.
- `decision-domains` — the catalogued stake-bearing domains and their
  triggers; what the builder escalates rather than auto-applies.
- `finding-categorization` and `gate-wiring` — the buckets, the
  hard-disqualifier zones, and the `GATE(when: …)` deferral mechanism an
  escalated decision routes into.
- `research-rigor` — the mature-project comparison and new-dependency triggers
  that fire when a guard or tool is being adopted.
- `proportionality` — guard rigor scales with stake and reversibility; any
  scoping or departure is declared, never silent.
- `interaction-style` — governs the recommend/confirm exchanges when run
  interactively.

If a doc does not resolve, degrade per REQ-K1.7: the builder runs on both
authoring (graceful) and execution paths, so name the missing doc in one line
and proceed where the remaining docs allow it, rather than failing opaquely.
A missing `guard-catalog` / `config/guard-catalog.yaml` is the one hard stop:
without the catalog there is nothing to detect against — say so and halt.

Doctrine manifest (the reading model above in machine-parseable form, per
`doctrine/instruction-hygiene.md`; `run-start` loads before work begins,
`point-of-use` loads at the named step or branch):

Doctrine: run-start guard-catalog
Doctrine: run-start engineering-decisions
Doctrine: run-start proportionality
Doctrine: point-of-use decision-domains (the escalate-vs-auto-apply catalog)
Doctrine: point-of-use finding-categorization (an escalated decision's routing)
Doctrine: point-of-use gate-wiring (the GATE deferral an escalation routes into)
Doctrine: point-of-use research-rigor (when a guard or tool is being adopted)
Doctrine: point-of-use interaction-style (the interactive recommend/confirm mode)

## Detection

The mechanical detect-and-map step is `scripts/builder-guards.sh` (resolved
under the planwright root), the same script the dogfood test exercises:

```sh
scripts/builder-guards.sh [--core] [--catalog <path>] [<target-dir>]
```

It reads the catalog, evaluates each guard's detection signals against the
target project, and prints the recommended guards as tab-separated
`<id>\t<category>\t<tool>` lines (sorted by id); `--core` restricts the output
to the universal core guards, omitting advisory breadth dimensions. An adopter
project with its own catalog supplies it via `PLANWRIGHT_GUARD_CATALOG` or
`--catalog` (see `guard-catalog`'s extension model).

Run it against the target, then read the output as the recommendation set.
Detection is real: a stack with no type-checker (a shell or plain-docs
project) gets none, and a guard whose signals do not match does not appear.
Cross-check the output against the SessionStart tool-discovery summary
(REQ-K1.3) when present — it lists what the project *already* runs, so the
builder distinguishes guards to add from guards already wired.

## Recommend vs apply

For each recommended guard, decide between applying it and recommending it,
governed by `finding-categorization` and `proportionality`:

- **Apply** the mechanical guards that are unambiguous for the detected stack
  and carry no design choice: wiring the formatter, the linters, the test
  runner, the secret scan, the commit-message lint, and the CI gate that runs
  them. Pin the toolchain and own the conventions-bearing defaults at adoption
  per `engineering-decisions` (record any deviation with its rationale in
  tracked config). Adopting a new tool fires `research-rigor`'s
  new-dependency trigger — run the dependency-adoption checklist and record it.
- **Recommend** (do not silently apply) where a guard implies a choice the
  project should own: a stricter lint ruleset, a coverage threshold, a CI
  topology. Surface it with the recommendation and let the human decide
  (`interaction-style` selectors when interactive).
- **Breadth dimensions** (documentation, i18n, a11y, architecture) are always
  advisory: name the dimension and the consideration, never auto-apply a tool.

Default to `--recommend` when run as an audit; `--apply` wires the
unambiguous core guards and reports the rest. Either way, the four-table audit
record (`finding-categorization`) is the honest output: what was applied, what
needs sign-off, what needs human judgment.

## Stake escalation (REQ-G1.3, D-16)

Before applying anything, walk the `decision-domains` catalog against what the
build touches — the prose seed (`doctrine/decision-domains.md`) unioned with any
adopter/team/machine-local additions via the merged path
`scripts/resolve-catalog.sh decision-domains`, so overlay domains are covered
too rather than a single-layer read (REQ-D1.1, the same merge path the guard
catalog uses). When a guard or setup step is about to cross a catalogued
decision domain the spec or kickoff brief has not decided — authentication,
data modeling, security posture, integration surface, and the rest — do not
auto-default it, however idiomatic the stack default looks. Escalate it as a
design / Needs-human-judgment decision and route it into the deferral
mechanism as a `GATE(when: …)` entry per `gate-wiring`, with the considerations
the catalog names recorded. Domains overlapping the hard-disqualifier zones
(auth, secrets, migrations) always escalate. A decision in a domain the
catalog does not cover yet records an observation fragment through the
shared helper (`scripts/obs-record.sh`; the fragment lands under
`specs/_observations/entries/` — the catalog grows through the drain loop).
This is the rule that keeps the builder from flattening a load-bearing
decision into a checkbox.

## Lifecycle wiring (REQ-G1.4)

The builder is consulted at two points beyond standalone runs (the third
wiring point, `/spec-kickoff`'s decision-domains gap check, consumes the
`decision-domains` catalog directly and needs no builder call):

- **`/spec-draft`, design phase.** The hook point already in `/spec-draft`:
  surface the guards the drafted stack warrants so the spec decides its
  quality floor explicitly, and flag the stake-bearing decision domains the
  feature touches so the spec decides them instead of inheriting defaults.
- **`/execute-task`, guard application.** During implementation, apply the
  core guards the task's changes warrant that the project does not already
  run (a new file type that wants a linter, a missing CI step), and let the
  decision-domains drift triggers escalate load-bearing calls. Guard changes
  ride the task's own PR.

In both, the builder composes in-session (REQ-E2.2): it is a function the
host skill calls, not a separate dispatch.

## Dogfooding (REQ-G1.7, D-32)

planwright's own repo is the builder's first subject. Run against planwright,
the builder reproduces the core guard set Task 2 established — `shfmt`, the
shell / prose / YAML / JSON linters, the shell test runner, `gitleaks`,
conventional-commit linting, and the GitHub Actions CI gate — and recommends
no type-checker (the stack has none). `tests/test-builder-guards.sh` asserts
this reproduction in CI against the repo's actual wiring, so the dogfood loop
fails if a guard is dropped or the catalog drifts from what planwright runs.
The dogfood is scoped to the universal core; planwright's project-bespoke
guards (the spec validator, the doc-link and options-reference checks) are
project extensions of the catalog, not universal categories (see
`guard-catalog`'s dogfood note).

## Maintenance

After the run completes (or halts), compare these instructions against the
resolved doctrine docs (REQ-B3.2, D-42) — especially `guard-catalog` (guard
categories, breadth dimensions, the extension model), `decision-domains`
(triggers and dispositions), and `engineering-decisions` (the no-flattening
rule). If a concept this skill names has changed meaning, gained or lost a
step, or moved between docs — or if `config/guard-catalog.yaml` has grown
guards this skill's prose does not reflect — record a drift observation
through the shared helper (`scripts/obs-record.sh --slug skill-drift
--scope <repo> --text 'skill-drift(builder): <what>'` — the entry text keeps
the `skill-drift(...)` prefix; in repositories without `specs/`, surface the
drift to the user instead of recording it), commit the fragment as its own
chore commit, and tell the user what drifted; surface a non-zero helper exit
rather than silently dropping the observation. Do not edit this skill or the
doctrine docs to resolve the drift; the accumulator's canonical reader
(`/spec-draft`) owns folding drift into spec amendments.
