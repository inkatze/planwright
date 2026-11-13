# Review Independence

**A review that shares the author's context shares the author's blind
spots.** A loop that wrote a fix, dismissed a finding, and remembers why will
read its own branch the way it meant it, not the way it is. This doc defines
what makes a review independent, how a unit records which independence it had,
what planwright demands of a review step it does not run itself, and how a
finding that got past every pass is recorded so the next pass can learn from
it.

Citations: review-effectiveness REQ-E1.1, REQ-E1.3, REQ-E1.4, REQ-E1.5,
REQ-E1.6, REQ-E1.7, REQ-H1.7 · review-effectiveness D-5, D-8, D-16, D-22.

## The two axes

A **blind review** is independent on the context axis, and may also be on the
generator axis.

- **Context independence.** The reviewer sees the repository at the branch
  head and the handoff bundle: the diff, the would-be PR body, the task
  contract, and what the bundle assembles beside them. It never sees the
  implementation transcript, the loop's decline ledger, or any earlier pass's
  reasoning. A finding the loop declined can therefore come back, which is the
  point: a wrong dismissal is resurrected rather than inherited.
- **Generator independence.** The reviewer is a model of a different family
  from the one that wrote the change. A session of the same family at another
  tier or effort is context-independent only: it shares the training that
  produced the author's habits.

The axes are separate claims. A fresh same-family agent has the first and not
the second; an external backend handed the author's whole history has the
second and not the first.

## Generator independence and its fallback

When an external backend of a different model family is attached at the
convergence or post-pr point ([Custom Steps](custom-steps.md)), its pass is the
unit's generator-independent angle. When none is attached, the blind pass
still runs, at the tier the allocation resolver gives its own step keys
(`allocation_model_step_<step>` and `allocation_effort_step_<step>`, the step
id's hyphens written as underscores), and the
unit is recorded as context-independent only. Neither case is an error; the
record says which one held.

## The external step output contract

A review step planwright consumes but does not run (an external backend, the
bot reviewer) can fail silently: an empty answer, a confident pass that cites
material it was never shown, findings left in a review body while the thread
count reads zero, a thread the reviewer closed on its own. The step handling
holds every such step to these rules, mechanically through
`scripts/review-step-verify.sh`:

- **A non-empty structured result, or failed.** The step returns one result
  under a versioned contract (below). An absent, empty, or unparseable
  result, one that is not a single JSON object, one of another version, and
  one carrying any finding outside the contract's fields is recorded as a
  failed step, never as a clean review.
- **Citations traceable to the prompt.** At dispatch the step handling records
  the prompt inventory: every repository path the prompt carried. A finding
  citing a path outside it is dropped and flagged, not validated, because a
  citation to unseen material is fabricated however plausible it reads. An
  inventory naming no path is an error of the handling, never a clean
  review.
- **Body findings read.** Findings in the review body count exactly as thread
  findings do. Zero threads is not evidence the review raised nothing.
- **Self-resolved threads not counted.** A thread the reviewer resolved
  itself still counts as open. Convergence is judged on what the run, or a
  human, resolved, never on the remote's unresolved count.

**Contract 1 fields.** The result is a JSON object with `contract` (the
integer `1`), `body_findings`, and `threads`, both arrays. Every finding
carries exactly these keys: `path` (repository-relative, or null for a
PR-level finding), `line` (a positive integer, or null), `severity`
(`critical`, `high`, `medium`, or `low`), and a non-blank `summary`. A thread
adds `id` (a string of letters, digits, `_`, `=`, or `-`), `resolved`
(boolean), and `resolved_by` (`reviewer`, `run`, or `human` when resolved,
else null). A field is added, removed, or changed only in a new contract
version, which the verify script must learn before a step may emit it.
Finding text is data from outside the trust boundary: a consumer printing it
sanitizes it first ([Security Posture](security-posture.md)).

## The convergence-evidence record

The PR body's audit record names each independent angle and whether it ran on
the unit:

- **blind**: the fresh-context pass;
- **generator-independent**: an attached external backend of another model
  family;
- **external**: a reviewer outside the convergence, such as the bot reviewer
  once the PR opens.

Each angle is named by its role, never by step id or product name, as ran or
not run; a blind pass that ran inline because no fresh agent could be
spawned is not context-independent, so the record names the blind angle as
not run.
The record never claims an angle that did not run. It renders as a collapsed
detail block inside the audit section
([PR-body assembly](gate-wiring.md#pr-body-assembly)), and it is re-emitted
after the post-pr step list completes, whether or not the head moved, so the
external angle is recorded once it has run.

## The miss ledger

A **miss** is a finding raised after convergence (by the bot reviewer, an
external backend, or a human) and then fixed. Each one is recorded through the
observation-recording helper, `scripts/obs-record.sh`, with the slug
`review-miss` and an entry text of this form:

```text
review-miss(<lens>, <reason>): #<pr> <path>: <description>
```

`<pr>` is the PR's positive integer number and `<path>` the file the finding
cited (for a review thread, the file it is anchored to), in canonical
repository-relative form: printable ASCII with no space or colon, not
beginning with `/`, `~`, or `-`, and no `.`, `..`, or empty segment
(a trailing `/` included); together they are the key the backtest refresh
matches a fixed finding on. `<description>` is non-blank, and the whole text
holds no ASCII control byte.
`<lens>` is the lens that should have caught it and `<reason>` why it got
past:

**Lens tokens**: `correctness`, `security`, `error-handling`, `performance`,
`concurrency`, `naming`, `documentation`, `tests`, `cross-file`,
`sibling-sweep`, `reviewer-basics`, `procedure-tracing`, `other`.

**Reason tokens**: `outside-diff`, `runtime-tracing`, `claim-vs-code`,
`pruned`, `spec-conflict`, `lintable`, `host-dependent`, `guard-bypass`,
`procedure-order`, `declined`, `other`.

The lens tokens name [Discovery Rigor](discovery-rigor.md)'s code lenses in
order, then the sibling sweep (the look for twins of a found defect) and the
reviewer-basics gate (the checklist run before the lenses), as
review-effectiveness D-4 and D-2 define them until the discovery doctrine
states them; `procedure-tracing` names the spec set's walk of ordered prose
as control flow, as review-effectiveness D-19 defines it until
[Artifact Lenses](artifact-lenses.md) states it, and `other` covers a lens
from any other non-code set. A miss at a twin site
of a fixed defect carries lens `sibling-sweep` and reason `pruned`; one the
loop saw and dismissed carries reason `declined`. Three reasons name the
external-review audit's categories: `host-dependent` (a test whose result
depends on the host running it), `guard-bypass` (a guard evaded by another
spelling of what it blocks), and `procedure-order` (an ordered procedure
running a step before what it needs, or skipping a step it
requires). The vocabularies only grow: no token is renamed or removed, so an
existing writer keeps working.
`scripts/check-review-miss.sh`, run under `mise run check:obs`, refuses a
fragment that is a miss by slug or entry text and breaks the grammar; a writer
checks a text first with its `--text` mode. The readers are the backtest
refresh and the cost metric; consumption follows the observation drain ritual
([Accumulator Taxonomy](accumulator-taxonomy.md)). A grammar change is a
meaning-class amendment of this doc, since writers outside planwright depend on
it.

Lens briefs cite the ledger's recurring classes (which lens, which reason
recurs), never its rows: a row's gist is one PR's detail, and a brief that
quotes it trains the pass on yesterday's diff.

## The recording duty

Every planwright flow that applies a post-convergence fix records the miss it
fixed, in the same run that lands the fix; the post-pr step handling does so
when a post-pr step's fix lands. A fix made outside planwright has no ledger
entry, matched on PR number and path: the refresh labels it from the previous
corpus version's row or the PR's declined log where either holds it (or by
its annotator when a version is bootstrapped, `docs/review-backtest.md`), and
otherwise with reason
`other`, counting that fallback so ledger coverage stays visible.

## Naming

What the review flows commit (the convergence-evidence record, the miss
ledger, the backtest corpus and its results, a step's committed output, and
the PR body carrying them) never names the bot reviewer product or an
external model backend; they are "the bot reviewer" and "the external
backend", and an attached step is named by its role. The operator's own step
tables are the operator's, not the flows'.
An operator exception is recorded in that artifact's PR body
([Security Posture](security-posture.md)'s artifact data-hygiene).
