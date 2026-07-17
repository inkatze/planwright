# Format grammar & parser unification — Test spec

**Status:** Draft
**Last reviewed:** 2026-07-16
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: parser, validator, and gate behaviors are `[test]` (fixture
suites under `tests/`, run by `mise run check` in CI); doctrine amendments
are `[design-level]` (the amended text's existence and coverage is the
verification) with `[test]` companions where a parser enforces the rule;
skill-ritual behaviors that no script executes are `[manual]`.

## REQ-A — Normative grammar

### REQ-A1.1 — Fence/illustration grammar [design-level + test]

The amended `doctrine/spec-format.md` defines the fence rule (column-0
toggle, illustration mode) in the extraction/grammar sections, including
the unclosed-fence disposition (enforcement verified under REQ-D1.11).
Companion: the Task 6 fence fixtures — a fenced column-0 `### Task` line
and a fenced requirement bullet parse as illustration in every parser (v1
and v2).

### REQ-A1.2 — Duplicate Format-version/Status rule [design-level + test]

The amendment states the fail-closed rule for both load-bearing header
keys; the Task 2 duplicate-declaration fixtures (`Format-version:` and
`Status:`) verify every keyed consumer refuses, and the Task 3 validator
fixture verifies the error fires at every status.

### REQ-A1.3 — Header-block scope [design-level + test]

The amendment defines the header block's extent; the Task 2 fixture with a
column-0 body `**Format-version:**` literal verifies the body line is inert
and a missing header declaration still fails closed.

### REQ-A1.4 — Tasks ordering non-normative [design-level]

The amended `## Tasks` prose states order carries no meaning, recommends
dependency order for authoring, and names id-sorted migration output
conformant. Verified by reading the amended section against
obs:94f03e6c's contradiction (both orderings conformant, no validator rule).

### REQ-A1.5 — Superseded/retired task home [design-level]

The amended meta-spec names the v1 retained-block pattern, the v2 parking
representation, and the test-spec tombstone handling; the output-hygiene
and bootstrap-T18 precedents are expressible without improvisation under
the amended text.

### REQ-A1.6 — Task-retirement escape documented [design-level]

The amended stable-ID/validator prose documents the changelog-named
retirement path mirroring REQ supersession (enforcement verified under
REQ-D1.6).

### REQ-A1.7 — Test-spec H2 grouping [design-level + test]

The amended `test-spec.md` section shows the `## REQ-<Group>` grouping;
`mise run lint:md` (MD001) passes over a bundle authored exactly from the
amended example. This file itself is a conforming instance.

### REQ-A1.8 — Completed-semantics asymmetry stated [design-level]

The amendment carries the clarification sentence naming both sides
(gate-atom reference-bullet authority vs dependency-satisfaction engine
evidence) as deliberate v1-parity behavior, including the accepted
consequence that the two evaluators may disagree about the same re-parked
task at the same instant.

### REQ-A1.9 — invariant-tasks REQ-C1.5 phrasing [design-level]

The invariant-tasks bundle carries the expression-only clarification
(riding Task 4's single changelog plus marked self-re-anchor entry); the
phrasing matches Ready=error and Draft=warn as pinned by the
invariant-tasks test-spec, and Retired/Superseded=warn per the bootstrap
D-25 severity model.

### REQ-A1.10 — Canonical task-heading form stated [design-level]

The amended task-block prose states the heading grammar is the only
recognized form (enforcement verified under REQ-D1.7).

## REQ-B — Shared extraction lib

### REQ-B1.1 — Single implementation home [test]

Lib unit tests exercise each entry point; the Task 8 grep check asserts no
consumer retains a private copy of a lib-implemented grammar.

### REQ-B1.2 — extract_tasks re-point, anchor-stable [test]

The migration suite's oracle and `tests/test-spec-anchor.sh` pass sourcing
the lib; a before/after anchor comparison over every bundle under `specs/`
is byte-identical (Task 1 Done-when).

### REQ-B1.3 — Format-version parse re-point [test]

Fixtures cover: header declaration parsed; body literal inert; duplicate
in-header declaration fails closed — identically across all eight
re-pointed consumers (`spec-status.sh`, the `tasks-pr-sync` hook,
`check-ledger.sh`, `spec-validate.sh`, `orchestrate-select.sh`,
`drain-gates.sh`, `migrate-format-version.sh`, `spec-graph.sh`); a grep
sweep asserts no private version-parse copy remains.

### REQ-B1.4 — Parked-map parse re-point [test]

A shared fixture corpus (fence, CRLF, prose bullets, whitespace-bearing
bold leads) yields identical classifications from all four v2 parsers.

### REQ-B1.5 — Line-80 migration [test]

Task 8 equivalence fixtures: validator, selector, and model outputs
unchanged over the corpus and all in-repo bundles after the re-point.

### REQ-B1.6 — Lib security posture [test]

Fixtures with hostile content (non-printable bytes in headings, malformed
identifiers, path-shaped tokens, embedded stream-delimiter bytes,
NUL-bearing input, end-of-file inside an open fence) verify clean refusal
or sanitized output; a
consumer-side fixture verifies fail-closed behavior when the lib file is
absent or unsourceable; path-derived reads are containment-checked; shell
lint and the secret scan run over the lib in CI.

## REQ-C — Parser posture alignment

### REQ-C1.1 — One v2 posture [test]

The REQ-B1.4 corpus doubles as the posture proof: per-case expected
classifications encode the fence, CRLF, discrimination, and prose-tolerance
rules; all four parsers assert against the same expectations.

### REQ-C1.2 — v1 fence-awareness lockstep [test]

Task 6 fixtures: the reproduced false duplicate-REQ error (a fenced mock
REQ bullet) no longer fires; a fenced `### Task` line contributes nothing
to the canonical extraction.

### REQ-C1.3 — spec-status CRLF/fence fix [test]

A CRLF-checkout fixture with a live Awaiting-input reference bullet derives
not-Done; a fenced mock bullet does not park anything.

### REQ-C1.4 — Re-anchor sweep on anchor movement [test + manual]

Task 6 recomputes anchors for every bundle under `specs/`, each either
unchanged or carrying a re-anchor entry, and a synthetic trip fixture (a
bundle with fenced task-shaped lines) proves anchor movement produces the
paired re-anchor entry `[test]`; for any real affected bundle, the
expression-only re-anchor entries are reviewed in the task PR `[manual]`.

## REQ-D — Validator hardening

### REQ-D1.1 — Awaiting-input purity [test]

Fixtures: a plain prose bullet under a v2 `## Awaiting input` warns on
Draft and errors on Ready; a reference bullet passes.

### REQ-D1.2 — Cited-but-empty REQ [test]

Fixture: a live `- **REQ-X1.1** *(Cites: D-1.)*` bullet with no normative
prose is flagged; a prose-bearing bullet passes.

### REQ-D1.3 — Out-of-range unqualified tokens [test]

Fixtures: a bare `D-45` in a bundle defining D-1..D-8 warns; the same token
qualified by a sibling-spec name on the line passes; an in-range bare token
passes.

### REQ-D1.4 — Semantic misattribution lens item [design-level]

The amended lens-checklist text names the qualified-citation review item
and states the structural validator's limitation.

### REQ-D1.5 — D-ID heading blindspot [test]

Fixtures: an H2 `D-3` heading, a colon-less H3, and a period-labelled
`**Decision.**` field are each flagged; the canonical shape passes.

### REQ-D1.6 — Retirement escape enforcement [test]

Fixtures against a baseline ref: a removed task block named in a dated
changelog entry passes; an unnamed removal errors; a changelog entry
naming a token that fails the task-id grammar does not activate the
escape; a changelog entry naming a valid but different id than the
removed block still errors (the escape matches the removed id, not any
named id).

### REQ-D1.7 — Canonical task-heading enforcement [test]

Fixtures: `### Task 1: title` and other deviant forms are flagged; the
canonical em-dash form passes.

### REQ-D1.8 — Coverage-based dead-path check [test + manual]

Fixtures: a REQ bullet edited since the baseline with an unchanged
test-spec entry warns; an edit paired with a test-spec edit passes; a
superseded/retired REQ whose test-spec entries were removed per the
tombstone rule does not warn; an unchanged REQ whose file position shifted
does not warn (the comparison is content-based, not line-based) `[test]`.
The lens-disposition pairing rule is exercised at the next meaning-class
kickoff `[manual]`.

### REQ-D1.9 — Duplicate Format-version/Status error [test]

Fixtures: duplicate in-header `Format-version:` and duplicate in-header
`Status:` declarations each error at Draft and Ready alike; scripts keyed
on the duplicated declaration refuse the same fixtures.

### REQ-D1.10 — New-rule rollout contract [manual]

Each hardening task's PR records the all-bundle run and any in-task fixes
(with their self-re-anchor entries on signed bundles); release notes name
adopter-visible severity changes. Reviewed at PR time.

### REQ-D1.11 — Unbalanced fence flagged [test]

Fixtures: a bundle with an unclosed column-0 fence is flagged (the
remainder of the file would otherwise silently parse as illustration); a
balanced-fence bundle passes.

## REQ-E — Gate grammar and drain

### REQ-E1.1 — ready status atom [test + design-level]

Fixtures: a stored-Ready spec emits no unrecognized-status note through
both whitelists (the shell `case` list and the awk `VALID` map); a status
atom referencing `ready` evaluates `[test]`. The taxonomy grammar text is
verified at Task 5 `[design-level]`.

### REQ-E1.2 — Free-text-gate form and hint [design-level + test]

The taxonomy amendment defines the plain-prose form; a fixture gate written
as `GATE(when: prose)` produces the MALFORMED report with the free-text
hint, and a hostile-condition fixture verifies the echoed condition is
sanitized (echo-safety).

### REQ-E1.3 — invariant-tasks gate fix [test]

A real sweep over `specs/invariant-tasks` reports no MALFORMED entry; the
rewritten gate evaluates to the same verdict as before the rewrite; the
bundle carries the dated changelog entry and marked re-anchor entry.

### REQ-E1.4 — Taxonomy delta [design-level]

The amended taxonomy describes multi-read evaluation under the digest
bracket (detection, not prevention) and documents the unresolved lane
annotation, matching shipped `drain-gates.sh` behavior.

### REQ-E1.5 — Meta-select fail-closed [test]

Fixtures: a selector exiting with an unexpected non-zero code, and a
selector exiting zero with unparseable output, each yield an evaluation
failure, not a silent not-a-candidate.

### REQ-E1.6 — [manual] inventory in drain [test]

Fixture: a live spec with `[manual]` and `[test + manual]` entries appears
in the drain output with its per-spec inventory; a spec with none is
absent from that lane.

## REQ-F — Kickoff verification homes

### REQ-F1.1 — Amendment-mode routing [manual]

A documented scenario: invoking `/spec-kickoff` against a Ready bundle with
pre-merge changes routes to delta re-walkthrough, against an Active bundle
to the amendment ritual; exercised and recorded at the next real occurrence
of each, per the Task 7 documented steps.

### REQ-F1.2 — Expression-only anchor-entry production [test]

Fixture: a captured real skill-produced expression-only entry (e.g. the
one Task 4 writes into invariant-tasks — marked class, changelog citation,
anchor line last) parses as execution-valid by the freshness-gate parser;
the fixture is the captured output, not a hand-authored golden.

### REQ-F1.3 — Catalog-absent degradation [test + manual]

The script half is the fixture: `resolve-catalog.sh` with no resolvable
decision-domains catalog fails cleanly `[test]`. The skill's
degrade-to-one-line-notice-and-proceed decision is prose behavior no
fixture executes; it is exercised and recorded at the next real
catalog-absent kickoff `[manual]`.

## REQ-G — Sequencing constraint

### REQ-G1.1 — Budget-gated doctrine landing [test + manual]

`scripts/check-instructions.sh` is the mechanical gate: Task 5's Done-when
requires it to pass with the amendments applied `[test]`. The parking and
unpark decision are human acts recorded in this bundle's `## Awaiting
input` section and changelog `[manual]`.
