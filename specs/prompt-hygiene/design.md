# Prompt Hygiene — Design

**Status:** Draft
**Last reviewed:** 2026-07-08
**Format-version:** 1

Origin tags: `N` = new decision, this bundle. Foreign IDs are
namespace-qualified (for example `bootstrap D-43`).

## Decision log

### D-1: Budget the mandatory-at-start load, not just files  (N)

**Decision:** The primary budget is per-skill instruction load: a tight
budget on the mandatory-at-start load (SKILL.md plus run-start rule docs)
and a loose budget on the reachable closure (plus point-of-use docs).
Per-file floors remain a secondary signal.

**Alternatives considered:**
- Per-file tiers only (one limit for skills, a looser one for doctrine).
  Rejected because: blind to the per-invocation total, which is what
  actually hits the model; invites bloat relocation from skills into
  doctrine.
- Closure budget only, no per-file floors. Rejected because: a single
  ballooning file hides inside a passing total; floors are the cheap
  early-warning signal.

**Chosen because:** the metric matches the degradation mechanism. What
degrades instruction-following is total instruction context per invocation;
a fat doctrine doc automatically charges every skill that front-loads it,
so doctrine needs no separately contested tier.

### D-2: Words as the enforcement unit, grounded in the 500-line ceiling  (N)

**Decision:** Budgets are enforced in words (`wc -w`), with line counts
reported informationally. Default thresholds derive from the official
500-line SKILL.md ceiling converted through the measured corpus density
(~8.5 words/line in `skills/`, ~7.9 in `doctrine/`): SKILL.md warn 3,000 /
error 4,250; doctrine file warn 2,500 / error 4,000; mandatory-at-start
warn 8,000 / error 10,000; closure warn 15,000 / error 20,000.

**Alternatives considered:**
- Lines (the official guidance's unit). Rejected because: line counts are
  reflow-gameable; re-wrapping prose changes them while the model-visible
  content is unchanged.
- Estimated tokens. Rejected because: honest tokenization needs a
  tokenizer dependency; approximations add noise without adding
  enforcement value over words.

**Chosen because:** `wc -w` is deterministic, dependency-free, POSIX, and
wrap-invariant; the official ceiling still anchors the numbers via the
measured ratio, so the defaults are grounded rather than invented
(REQ-B1.5). *(Research: Anthropic skill-authoring best practices, "Keep
SKILL.md body under 500 lines for optimal performance".)*

### D-3: A machine-parseable doctrine manifest per skill  (N)

**Decision:** Each SKILL.md declares its rule-doc loads in a structured
manifest with two classes: run-start (read before work begins) and
point-of-use (read at a named step or branch). The exact syntax is fixed by
the doctrine doc (Task 1); it must be parseable by a POSIX-sh/awk reader at
column 0 outside code fences.

**Alternatives considered:**
- Parse the existing prose ("resolve and read these rule docs"). Rejected
  because: fragile, unstable across rewording, and cannot distinguish
  run-start from point-of-use.
- A sidecar manifest file per skill. Rejected because: drifts from the
  SKILL.md it describes; the declaration belongs in the artifact it
  governs.

**Chosen because:** one declaration feeds three consumers: the closure
computation (REQ-A1.2), the resolution check (REQ-B1.6), and the reading
model itself (the skill's own instructions reference the same lists), so
the measurement can never disagree with what the skill actually loads.

### D-4: One guard script, wired like the sibling checks  (N)

**Decision:** One POSIX-sh script, `scripts/check-instructions.sh`,
implements the budgets, the resolution check, and an `--audit` mode (the
ranked report and shortlist), wired into `mise run check` as its own task,
mirroring the `check-options-reference.sh` pattern.

**Alternatives considered:**
- Separate scripts per concern (size vs resolution vs audit). Rejected
  because: they share the manifest parser and file walk; splitting
  triplicates the grammar (the exact drift class the observations log
  documents for spec parsing).
- Extending `spec-validate.sh`. Rejected because: that validator owns spec
  bundles; instruction files are a different artifact class with different
  lifecycle and thresholds.

**Chosen because:** one parser, one walk, three outputs; the repo's guard
pattern (small self-contained check script + mise task + seeded-violation
fixture) is established and auditable.

### D-5: Thresholds and exemptions as config, values overlay-tunable  (N)

**Decision:** Threshold knobs live flat in `config/defaults.yml`
(`instruction_budget_*`), overlay-tunable through `config-get`. Exemptions
live in a tracked list (file + mandatory reason); transitional exemptions
are annotated `pending diet (Task N)` and removed by the diet task's own
PR; permanent exemptions carry their standing rationale.

**Alternatives considered:**
- Hardcoded thresholds in the script. Rejected because: the capability
  (budgeting) is core, but the values are style; hardcoding forces forks
  for tuning (customization-boundary rule).
- Grandfather offenders by skipping the check until diets land. Rejected
  because: skip-with-notice checks rot (the `check:specs` skip-notice
  lesson, observations log 2026-06-11); an enforced guard with named
  transitional exemptions keeps CI green and the debt visible.

**Chosen because:** mechanism in core, values tunable, debt explicit and
self-liquidating: each diet PR deletes its own exemption, and REQ-D1.4
makes leftover `pending diet` entries a failure.

### D-6: Bespoke sh eval runner over headless `claude -p`; no framework  (N)

**Decision:** The kept-eval runner is a POSIX-sh script driving
`claude -p --output-format json` (stream-json where trace assertions need
it), hermetic via `--bare --plugin-dir <planwright>`, verifying plugin load
from the `system/init` event before grading, budget-capped with
`--max-turns` and `--max-budget-usd`. No eval framework is adopted.

**Alternatives considered:**
- promptfoo (has a genuine claude-agent-sdk provider and a generic `exec:`
  provider). Rejected because: an npm runtime dependency in a repo whose
  runtime is deliberately pin-tool-free POSIX sh; dependency adoption is
  stake-escalated, and the pieces a framework buys (rubric grading, trace
  assertions) are attainable with a grader `claude -p` call and
  stream-json parsing. Named as the escalation path: `exec:` can wrap this
  runner unchanged if matrix/report needs materialize.
- DeepEval / Braintrust / Inspect `claude_code()`. Rejected because:
  Python and/or SaaS surface for the same reasons, heavier still.
- Anthropic's skill-creator eval workflow as-is. Rejected because: it is
  model-orchestrated prose plus JSON schemas, not a runnable harness (its
  only shipped script measures description-trigger rates); we borrow its
  field names and grading-record shape instead.

**Chosen because:** there is no official runner to conform to ("users can
create their own evaluation system"), the dependency cost is zero (Claude
Code is already the runtime), and the flags are verified against the
installed binary. *(Research: session survey 2026-07-08; dependency-
adoption checklist walked: no supply chain, no new licenses, no transitive
weight.)*

### D-7: pass^k gating with paired before/after comparison  (N)

**Decision:** Eval gating uses pass^k (all of k runs pass), default k=3;
a merge-relevant judgment is never taken from a single stochastic run;
before/after diet comparisons are paired on identical fixtures.

**Alternatives considered:**
- pass@k (any of k). Rejected because: a regression suite makes a
  reliability claim; any-of-k rewards flakiness (tau-bench's motivation
  for pass^k).
- Single-run gating. Rejected because: vendor best practice is explicit
  that one stochastic run can mask or fake a change.

**Chosen because:** the selection rule is published (consistency-critical
agents gate pass^k) and k=3 is the low end of established practice,
matching a small kept suite's cost envelope. *(Research: tau-bench arXiv
2406.12045; Anthropic "Demystifying evals for AI agents"; Anthropic
"A statistical approach to model evaluations" for pairing.)*

### D-8: Evals run on demand, never per-commit CI  (N)

**Decision:** The eval suite runs via a dedicated `mise` task, on demand
and when instruction files change; it is not part of `mise run check` and
does not run in GitHub CI.

**Alternatives considered:**
- Per-commit CI evals. Rejected because: token cost on every push,
  nondeterministic gating on shared CI, and an API key requirement in the
  public repo's CI.
- Scheduled (nightly) runs. Rejected because: planwright has no always-on
  runner budget; on-change/on-demand matches the run-on-change pattern the
  ecosystem documents, without idle spend.

**Chosen because:** deterministic checks gate merges; sampled behavioral
checks gate prompt edits at the moment they change, which is when the
signal exists.

### D-9: Loading convention: always-loaded core, point-of-use bulk  (N)

**Decision:** Skills split instruction content into an always-loaded core
(hard invariants, safety rules, anything that gates whether an action is
permitted) and deferred bulk (reference detail, rare branches such as
extend/degradation arms) read at the step that needs it. Gating law is
never deferred. References stay one level deep from the SKILL.md.

**Alternatives considered:**
- Keep run-start front-loading of all doctrine. Rejected because: it is
  the single largest per-invocation cost (12k+ words for `/spec-draft`)
  and loads law for paths never taken.
- Defer everything aggressively. Rejected because: deferred loading trades
  bloat risk for skip risk; a rule the model has not read cannot govern,
  so permission-gating law must be in the core.

**Chosen because:** this is the platform's own progressive-disclosure
architecture (reference files loaded as needed; nested references get
partially read, hence one level deep), applied with an explicit safety
floor. *(Research: Anthropic skill-authoring best practices.)*

### D-10: `doctrine/instruction-hygiene.md` as the doctrine home  (N)

**Decision:** One new rule doc, `doctrine/instruction-hygiene.md`, carries
REQ-C1.1 through REQ-C1.4 (authoring rule, manifest convention, loading
convention, test-and-measure principle, kept-eval convention), registered
in the doctrine README index; the guard-catalog entry is keyed
`instruction-hygiene`.

**Alternatives considered:**
- Fold into an existing rigor doc (discovery/validation-rigor). Rejected
  because: those govern reviewing produced code; this governs authoring
  the instruction layer itself, a different audience and moment.
- Two docs (authoring vs testing). Rejected because: the loading
  convention and the eval convention justify each other (deferral is safe
  because tests exist); splitting invites citing one without the other.

**Chosen because:** one resolution-path name for skills and the builder to
cite, mirroring the sibling `output-hygiene` naming so the family boundary
reads at a glance.

### D-11: Degradation claims cite a fixed, conservative source set  (N)

**Decision:** The doctrine grounds "instruction-following degrades as
instruction context grows" in exactly: NoLiMa (arXiv 2502.05167, effective
context degrades well before advertised limits), ManyIFEval (arXiv
2509.21051, compliance consistently degrades as simultaneous-instruction
count grows; IFScale arXiv 2507.11538 as the higher-N companion), Chroma
"Context Rot" (18 current models, degradation even on simple tasks), and
Anthropic "Effective context engineering for AI agents" (attention budget;
context as a finite resource with diminishing returns).

**Alternatives considered:**
- Citing IFEval or Lost-in-the-Middle for the instruction-count claim.
  Rejected because: IFEval defines the measurement methodology and says
  nothing about degradation with count; Lost-in-the-Middle shows position
  effects, not count effects. Citing them would overclaim.
- No citations (assert from vendor guidance alone). Rejected because: the
  doctrine's forcing function (budgets that fail CI) deserves evidence a
  skeptic can check.

**Chosen because:** each source is primary, current, and supports exactly
the sentence it is cited for; conservative wording survives review.
*(Research: session survey 2026-07-08.)*

### D-12: `/orchestrate` is the pilot eval subject  (N)

**Decision:** The pilot before/after eval targets `/orchestrate`: baseline
fixtures recorded against the pre-diet SKILL.md, the same fixtures re-run
after its diet, gated per D-7.

**Alternatives considered:**
- `/execute-task`. Rejected because: each eval run performs real
  implementation work; slow, expensive, and outcome variance swamps the
  signal.
- `/spec-kickoff`. Rejected because: deeply interactive walkthrough;
  driving it headlessly needs heavy prompt scripting that would test the
  script more than the skill.
- A small skill such as `/drain`. Rejected because: it is not an offender;
  a passing eval there proves little about diet safety.

**Chosen because:** it is the largest offender (6,913 words) and its
`print` dispatch backend yields deterministic, assertable outcomes with no
worker processes: correct unit selected, dispatch marker written, launch
command printed, non-Ready/non-Active spec refused.

## Cross-cutting concerns

- **Family boundary with `specs/output-hygiene`:** that spec governs what
  the pipeline writes for downstream readers (PR bodies, accumulators);
  this one governs what drives the pipeline (instruction files). The
  resolution check (REQ-B1.6) covers doctrine-manifest references only;
  general committed-reference integrity stays with output-hygiene.
- **Decision-domains walk (2026-07-08, merged catalog, ten core domains,
  no overlay additions):** secrets-config fired (new knobs: conventions
  followed, REQ-B1.4 documents them); dependency-adoption fired (resolved
  as no-dependency, D-6); api-surface, observability, and concurrency are
  internal-surface / idiom-rung (eval runner tears down its worktrees).
  Two touched domains are known catalog gaps already logged in the
  observations log (human-comprehension UX, 2026-06-16/2026-07-07; LLM
  eval gates, 2026-06-17): this bundle decides its instances explicitly
  (the audit report shape in Task 2; D-7's gating) and leaves the catalog
  entries to their logged observations.
- **Self-application:** the doctrine doc and this bundle's own additions
  are subject to the budgets they introduce; `doctrine/
  instruction-hygiene.md` must pass the guard it defines.
