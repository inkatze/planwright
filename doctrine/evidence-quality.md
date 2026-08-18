# Evidence Quality

An assumption is only as good as what would falsify it, and a claim is only as
strong as what somebody gave up to produce it. This doc defines both: the
falsifiability format every assumption is written in, the pre-committed
threshold that decides it, and the commitment-weighted ladder that grades the
evidence cited against it.

[inception-format.md](inception-format.md) owns the *fields* (`Statement:`,
`Threshold:`, `Evidence:`, `Risk-tag:`) and the literal grade tokens; this doc
owns their *meaning* — what a well-formed statement says, what makes a
threshold real, and what earns each grade.

Citations: inception REQ-I1.4, inception REQ-C1.3, inception REQ-E1.1 ·
inception D-1.

## The falsifiability format

Every assumption is stated in four parts, in this order:

> **believe** `<claim>`; **verify** `<test>`; **measure** `<observable>`;
> **right if** `<pre-committed condition>`.

- **believe** — the claim, narrow enough that a reasonable person could
  disagree with it. "Users want this" is not a claim; "operators running more
  than three concurrent tasks will pay for a queue view" is.
- **verify** — the test that produces the observation. Names the method and
  who or what it is run against.
- **measure** — the observable the test yields. It must be countable or
  categorizable *before* the result is known.
- **right if** — the condition that decides it, fixed in advance.

A claim that cannot be written in this shape is not an assumption. It is
either an opinion (record it as context, not as a register entry) or a
decision already taken (record it in the decision backlog).

## Thresholds are fail conditions

The `right if` condition and the register's `Threshold:` field are the same
commitment, and both are subject to three rules:

1. **Pre-committed.** Fixed before the test runs. A threshold written after
   seeing results is not a threshold; it is a description.
2. **Expressible as a fail condition.** If you cannot state the outcome that
   would make you abandon the claim — "fewer than 4 of 10", "no participant
   completed the flow unaided", "median under 12 minutes" — the threshold is
   not decidable. Writing the fail side is the test of the pass side.
3. **Failable in practice.** A threshold no realistic outcome could miss
   measures nothing. If every plausible result passes, the bar is wrong, not
   the claim confirmed.

Thresholds live on the assumption; the time or cost *cap* lives on the
validation task that buys evidence against it. They are read together at the
gate: a task that exhausted its cap without meeting its threshold is an
unresolved assumption, not a passed one.

## The commitment-weighted ladder

Grades order weakest to strongest:

`synthetic` < `opinion` < `stated-intent` < `costly-signal` < `behavior`

The grading question is always the same: **what did the source give up to
produce this signal?** Not how confident it sounded, and not how much of it
there was.

| Grade | What earns it |
| --- | --- |
| *(none)* | Reasoning, desk analysis, or a model's assertion about the world. Not citable evidence; an entry backed only by reasoning carries `Evidence: none`. |
| `synthetic` | Simulated evidence: persona-panel output, an LLM standing in for a user, a scenario walked by a model rather than a person. |
| `opinion` | A real person said something, at no cost to themselves. |
| `stated-intent` | A real person committed to a future action: "I would buy this", a waitlist signup, a stated adoption plan. Costs a little reputation, nothing else. |
| `costly-signal` | A real person spent something they cannot trivially recover: money, a scheduled hour, an introduction, a letter of intent, reputation inside their own organization. |
| `behavior` | Observed real-world action in the real context, unprompted — usage, purchase, retention, a workaround someone built without being asked. |

Three grading rules:

- **Grade the weakest link.** Evidence assembled from a strong observation and
  a weak inference is graded at the inference.
- **Volume does not promote.** Ten opinions are still `opinion`. Breadth
  raises confidence *within* a grade; it does not cross one.
- **Provenance is named.** Every graded entry cites its source — a name in the
  bundle's sources register, or the findings document of the validation task
  that produced it.

### Where `synthetic` sits, and why

`synthetic` is above nothing-but-reasoning: a persona panel is structured,
reproducible, and records the frame it ran against, which raw reasoning does
not. It is below any real person's stated opinion: no one's interest,
attention, or reputation is behind it. It can be wrong in a correlated way
across every seat, because the seats share a generator — so its errors do not
average out the way independent human opinions do.

That places it as useful for **sharpening the question** (surfacing the
objection nobody in the room raised, ranking what to test first, drafting the
instrument) and unusable as a **substitute for a person**.

## Desirability and the synthetic exclusion

Assumptions carry one of four risk tags: **value**, **usability**,
**feasibility**, **viability**. **Desirability** is the union of the first
two — value risk (do they want it) plus usability risk (can they use it) —
because both are claims about what a human will actually do.

**A `synthetic`-graded entry cannot count as a passing test toward a
`Graduate` outcome on a desirability-tagged assumption.** The gate reads the
tag and the grade together: the entry cannot mark that assumption's threshold
`pass`. Where it is the only evidence, the assumption stays unresolved, and a
blocking unresolved assumption is what refuses the `Graduate` (REQ-E1.1).
Higher-graded evidence on the same assumption is unaffected — the bar is on
what `synthetic` can carry, not on the assumption having any synthetic
evidence at all.

The exclusion is scoped deliberately:

- It bars `synthetic` from *clearing* a desirability assumption. It does not
  bar recording it — a `synthetic` entry is legitimate evidence at its grade,
  and is often the honest state of a young venture.
- It does not apply to feasibility or viability assumptions, where a
  simulation can be a real test of the thing being claimed (a modeled cost
  envelope, a walked-through architecture).
- It does not block the other gate outcomes. A venture may `Hold`, `Recycle`,
  or `Kill` on synthetic evidence; only `Graduate` — the outcome that spends
  real engineering capacity — carries the bar.

The reason is not that simulated evidence is worthless. It is that graduation
converts a belief about people into committed work, and no amount of simulated
agreement is a person choosing to change what they do.

## Proportionality

Evidence standards scale with stake and reversibility
([proportionality.md](proportionality.md)). A reversible, cheap call may
proceed on `opinion` with the grade recorded. A one-way door — a published
price, a positioning claim, a graduation — is the case the ladder exists for.
Recording a low grade honestly is always conforming; inflating one never is.

**Lineage.** The four-part statement is the test-card format from the
lean-startup and Strategyzer lineage; the commitment weighting follows the
Mom Test's currencies (time, reputation, money) and pretotyping's
skin-in-the-game weighting; the fail-condition framing is standard
experiment-design practice. planwright's contribution is the `synthetic` grade
and its scoped exclusion, which the prior art predates.
