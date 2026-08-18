# Artifact Lenses

[Discovery Rigor](discovery-rigor.md)'s canonical lens list is code-shaped, and
that is correct for code. Applied unchanged to a spec, an inception bundle, or
a report written for a human, several of its lenses fire on a threat model the
artifact does not have: performance and concurrency findings against a document
nothing executes, code-security findings against prose nothing parses. The
observed cost is not a false alarm here and there — it is most of the fan-out
budget spent declining code-shaped findings, while the artifact's real defects
(an uncited claim, a dead verification path, an unfalsifiable assumption) have
no lens looking for them.

This doc is the selection rule: **the lens set is chosen by the artifact class
of the thing under review, before the lens walk begins.** It changes which
lenses are walked, never the no-silent-pruning discipline — every lens in the
selected set gets a row in the coverage table, and an empty one still shows
`none` or `n/a` with a reason.

Citations: inception REQ-I1.3 · inception D-17.

## Selecting the class

Name the artifact class once per artifact under review, and say which set was
selected in the coverage table's caption. A change spanning two classes (a spec
edit that also touches a script) runs both sets and merges the results, deduping
a finding that lands under a lens in each.

| Class | What it is |
| --- | --- |
| **code** | Anything executed or executable: source, scripts, config the runtime reads, infrastructure definitions |
| **spec** | Prose contracts: spec bundles, doctrine docs, skill instructions, ADRs, README-class documentation |
| **inception** | Venture-scope judgment artifacts: the inception bundle (brief, discipline map, assumption register, decision backlog, validation plan) and its exports |
| **human-facing** | Generated output whose whole purpose is being read: PR bodies, reports, rendered views, walkthroughs, status surfaces |

## The lens sets

**code.** The canonical nine in [Discovery Rigor](discovery-rigor.md),
unchanged. This is the default when no class is named.

**spec.** Contract correctness and internal consistency (does any rule
contradict another); ambiguity and interpretation forks (can two readers act
differently on the same line); citation and coverage integrity (every claim
traceable, every requirement reachable); dead verification paths (a stated
check nothing can run); decision-domain gaps (a
[catalogued domain](decision-domains.md) the artifact touches but never
decides); testability (is every `Done when:` evaluable); cross-file
consistency; documentation and glossary drift; rendered-content safety, but
only when the prose is rendered into an executing or markup context.

**inception.** Falsifiability (is each assumption written in the
believe / verify / measure / right-if skeleton); evidence-grade honesty (does
the cited grade match what was actually observed, per
[evidence-quality.md](evidence-quality.md)); threshold pre-commitment (fixed
before the test ran, expressible as a fail condition); decision-door
classification (is every one-way call reserved to a named human); discipline
coverage and unstaffed honesty (is a gap flagged rather than quietly
unfilled); stakeholder authority (does a named human hold each decision);
kill criteria and cost caps (present, dated, and checkable); traceability
(every plan task tests something; every register entry links its task).

**human-facing.** Above-the-fold summary (does the first screen carry the
answer); progressive disclosure (is the detail reachable rather than dumped);
reader-not-writer formatting (a flat log, hard-wrapped machine output, or an
unsummarized dump serves the writer); comprehension (plain language for the
actual audience, precision preserved where it is load-bearing);
accessibility; data hygiene (no secrets, credentials, internal hostnames, or
sensitive detail — [security-posture.md](security-posture.md)); escaping and
injection, when the output is rendered into HTML or another markup surface;
truncation and failure rendering (what the reader sees when the data is
missing or oversized).

## When code lenses do not apply

For the **spec**, **inception**, and **human-facing** classes:

- **Performance**, **concurrency / state**, and **error handling and failure
  modes** do not apply. They describe a running program; these artifacts have
  no execution path, no shared state, and no partial-failure semantics.
  Marking them `n/a` with that one-line reason is conforming. Running them
  anyway is what produces the out-of-threat-model findings this rule exists to
  stop.
- **Security** is *reframed*, not dropped. The code-shaped questions
  (injection, auth, untrusted input) do not apply to prose nothing parses. The
  questions that do apply: what is this artifact rendered into, and by what;
  what does committing it disclose. Both are live — an artifact rendered into
  HTML needs escaping, and every committed artifact is subject to data
  hygiene.
- **Correctness** narrows from runtime behavior to *contract* behavior: not
  "does it compute the right value" but "does this rule contradict another,
  and can two readers act differently on it".

An artifact class never *adds* code lenses back by default. If a specific
review needs one (a spec that embeds a script, a report generated by a hot
path), name it explicitly alongside the selected set and say why.

## Validation across classes

[Validation Rigor](validation-rigor.md)'s three passes hold for every class;
what satisfies pass 1 changes. With no runtime to reproduce against, pass 1 is
the non-testable-changes substitute that doc already defines — re-read the
artifact as each consumer, and search for every place the claim is expressed —
plus, for an **inception** artifact, checking the claim against its cited
evidence at its stated grade. Pass 3 (outside-in) carries *more* weight in
these classes, not less: with no execution to appeal to, the sources outside
the artifact are the check.

## Proportionality

Lens-set selection scales with stake like everything else
([proportionality.md](proportionality.md)). A skill that narrows a selected set
declares the narrowing; silent scoping is non-conforming, in exactly the way
silent pruning is.
