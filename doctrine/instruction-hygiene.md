# Instruction Hygiene

Instruction files are the prose that drives planwright at runtime: the
`skills/*/SKILL.md` bodies the harness injects at invocation, and the
`doctrine/*.md` rule docs skills load. They grow monotonically as features
land, and instruction-following measurably degrades as that load grows. This
doc is the authoring law that keeps the instruction layer within budget: the
authoring rule, the doctrine manifest, the loading convention and its safety
floor, the size budgets, the test-and-measure principle, and the kept
prompt-eval convention. The size guard (`scripts/check-instructions.sh`, wired
into `mise run check`) enforces the budgets; this doc governs the writing.

Citations: prompt-hygiene REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4 · D-2, D-3,
D-6, D-7, D-8, D-9, D-10, D-11.

## Why: instruction-following degrades with instruction load

The degradation claim is grounded in a fixed, conservative source set; each
source is cited for exactly the sentence it supports:

- Effective context degrades well before advertised context limits (NoLiMa,
  arXiv 2502.05167).
- Instruction compliance consistently degrades as the number of simultaneous
  instructions grows (ManyIFEval, arXiv 2509.21051; IFScale, arXiv 2507.11538,
  is the higher-count companion).
- Degradation with growing input length appears across 18 current models even
  on simple tasks (Chroma, "Context Rot").
- Attention is a budget; context is a finite resource with diminishing returns
  (Anthropic, "Effective context engineering for AI agents").

A new degradation claim in this doc or a diet plan needs a source that
supports exactly that claim; do not stretch these four.

## The authoring rule: flow in skills, law in rule docs

- **The SKILL.md carries the flow**: the procedure, its ordering, its stop
  conditions, and the judgment calls the skill makes in sequence.
- **Normative law lives in rule docs**, referenced by resolution path (the
  chain in [README.md](README.md#resolution-convention), implemented by
  `scripts/resolve-rule-doc.sh`). A definition stated once in doctrine governs
  every skill that cites it; a skill restates at most the one-line gist it
  needs inline.
- **References stay one level deep from the SKILL.md.** The manifest lists
  every rule doc the skill itself relies on. A rule doc may link sibling docs
  for the human reader, but those links never extend a skill's load: nested
  references get partially read, so a skill that needs a doc must declare it
  directly.
- **Bulk and rare branches load at point of use.** Reference tables, extend
  arms, and degradation paths are read at the step that needs them, not
  front-loaded (see the loading convention below).

## The doctrine manifest

Each SKILL.md declares its rule-doc loads in a machine-parseable manifest.
One declaration feeds three consumers: the start-load and closure computation,
the resolution check, and the skill's own reading model, so measurement can
never disagree with what the skill actually loads.

### Grammar

A manifest entry is one full line, at column zero, outside fenced code blocks:

```text
Doctrine: run-start <doc-name>
Doctrine: point-of-use <doc-name> (<site note>)
```

- `Doctrine:` is a reserved line prefix. Every column-zero line outside a
  fence that begins with `Doctrine:` MUST parse as an entry; one that does not
  is a malformed manifest and a guard error, never a silent skip.
- The class token is exactly `run-start` or `point-of-use`, lowercase. Any
  other token is malformed.
- `<doc-name>` is the rule doc's kebab-case basename, matching
  `^[a-z0-9][a-z0-9-]*$` (the resolution chain's identifier discipline), no
  `.md` suffix, no path. Every named doc must resolve through the rule-doc
  resolution chain; an unresolvable reference fails the resolution check.
- An optional trailing parenthesized note names the step or branch that reads
  a point-of-use doc. Parsers take the doc name and ignore the note; the note
  is for the reading model.
- Tokens are separated by horizontal whitespace; nothing else may follow the
  entry on the line.
- A doc name appears at most once in a skill's manifest, in one class.
  Duplicates, or the same doc in both classes, are malformed.
- Parsers MUST track fenced code blocks (``` and ~~~) and ignore fenced
  content; that is what lets this doc and others quote example entries safely.
  Indented or quoted lines are not at column zero and are never entries.

The skill's manifest is the set of all its entry lines. Convention places
them as one contiguous block in the skill's doctrine section, but position
carries no meaning. A SKILL.md with zero entry lines declares no manifest:
its start-load is scored as its body alone, which is not an error to the
guard (the completeness assertion that every skill declares a manifest is a
separate corpus-wide check).

### Semantics

- **run-start**: resolved and read before work begins. Its words count toward
  the skill's mandatory-at-start load.
- **point-of-use**: read at the named step or branch, only when that path is
  taken. Its words count toward the reachable closure, not the start-load.

The skill's prose references the same lists; the manifest is the single
source of truth for what the skill loads and when.

## The loading convention and the safety floor

Split a skill's instruction content into:

- **Always-loaded core**: the SKILL.md body plus run-start docs. It holds the
  hard invariants, the safety rules, and any law that gates whether an action
  is permitted.
- **Deferred bulk**: point-of-use docs. Reference detail, format
  specifications consulted at one step, rare branches (extend arms,
  degradation ladders, error-recovery procedures).

**The safety floor: gating law is never deferred.** The test for each rule:
if the model reached the acting step without having read this rule, could it
take an action the rule forbids? If yes, the rule belongs in the always-loaded
core, in the body or a run-start doc. A rule the model has not read cannot
govern. Deferral trades bloat risk for skip risk, and for permission-gating
law that trade is never acceptable: a skill that cannot reach its budget
without deferring gating law escalates the threshold-versus-safety tension to
the human instead of deferring.

## Budgets

Budgets are enforced in **words** (`wc -w`): deterministic, dependency-free,
and wrap-invariant, where line counts are reflow-gameable. Line counts are
reported informationally. Defaults derive from the published 500-line SKILL.md
authoring ceiling converted through the measured corpus density:

| Surface | Warn | Error |
| --- | --- | --- |
| SKILL.md body (per file) | 3,000 | 4,250 |
| Rule doc (per file) | 2,500 | 4,000 |
| Mandatory-at-start (body + run-start docs) | 8,000 | 10,000 |
| Reachable closure (start-load + point-of-use docs) | 15,000 | 20,000 |

The start-load budget is the primary one: what degrades instruction-following
is total instruction context per invocation, and a fat rule doc automatically
charges every skill that front-loads it. Per-file floors are the cheap
early-warning signal. Threshold comparison is boundary-inclusive: a count
equal to a threshold trips it (`>=`).

Values live as `instruction_budget_*` knobs in `config/defaults.yml`,
overlay-tunable; the mechanism is core. The `doctrine/README.md` index is
excluded from the per-file walk (an index, not run-start law). Two suppression
forms exist, each requiring a recorded reason: a **permanent exemption**
(per-file floor only, never start-load or closure, standing rationale) and a
**transitional `pending diet (Task N)` allowance** (any budget, temporary,
removed by that diet's own PR, forbidden at closeout).

## Test and measure

Instruction files are runtime artifacts and get the discipline of code:
measured and behavior-tested, not merely reviewed as prose. Their
nondeterminism changes the **form and cadence** of verification, never
**whether** to verify. Deterministic proxies (word budgets, manifest
resolution) run on every commit in CI; sampled behavioral checks (the kept
evals below) run when the prose they verify changes, gated pass^k because a
single stochastic run proves nothing.

## The kept prompt-eval convention

The behavioral backstop for the proxy: a fixture suite kept in the repo,
run on demand, catching the case where a file passes the size budget yet
still degrades behavior.

- **Fixture format.** Each fixture carries a stable identifier, the scenario
  that drives the skill headlessly, a hermetic setup (a disposable worktree;
  the plugin pinned via `--bare --plugin-dir`), deterministic grading criteria
  over observable outcomes (files written, markers dropped, commands printed,
  refusals issued), and per-run budget caps (`--max-turns`,
  `--max-budget-usd`).
- **Runner contract.** A dependency-free POSIX-sh script driving
  `claude -p --output-format json` (stream-json where trace assertions need
  it). No eval framework is adopted. The runner verifies plugin load from the
  `system/init` event before grading (a run that never loaded the plugin
  aborts as invalid, it is not a graded failure), captures per-run cost from
  the JSON payload, and tears down its worktree.
- **pass^k gating.** A judgment passes only when all `k` runs pass (default
  `k=3`). A merge-relevant judgment is never taken from a single stochastic
  run. Diet verification compares before/after **paired on identical
  fixtures**, matched by fixture identifier.
- **Cadence.** On demand, and when the instruction files under eval change.
  Never per-commit: the suite is not part of `mise run check` and never runs
  in GitHub CI (cost, nondeterministic gating, and an API-key requirement in
  a public repo). A standing CI-exclusion check enforces that no eval task is
  wired into a CI workflow.
- **Artifact hygiene.** A recorded eval artifact carries the per-fixture
  graded outcome, the fixture identifier (the paired comparison needs it),
  and the per-run cost — and nothing more. It is scrubbed of machine-local
  paths, usernames, and session identifiers before commit (see
  [security-posture.md](security-posture.md)).

## Self-application

This doc, and every instruction file this repo ships, is subject to the
budgets above. Doctrine additions that push a run-start doc over budget are
diet triggers, not grandfather cases: slim the doc or reclassify its bulk to
point of use, moving law verbatim in meaning, never silently raising a
threshold.
