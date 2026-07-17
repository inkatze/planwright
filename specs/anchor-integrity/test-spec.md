# Anchor integrity — Test Spec

**Status:** Draft
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` for the hash mechanics, the landing proof, and the
guard (all run in `mise run check`, which GitHub Actions CI executes);
`[design-level]` for doctrine prose whose existence and coverage is the
verification; `[Gherkin]` plus `[manual]` for skill-ritual behaviors
exercised in live runs.

## REQ-A — Anchor scope

### REQ-A1.1 — Status-line exclusion [test]

Unit tests in the `tests/test-spec-anchor.sh` suite: a format-version 1
fixture bundle is anchored, then its header `**Status:**` line is flipped
across the sanctioned stored and derived values (Draft→Ready→Active→Done,
plus the terminal values) across all four files' mirrors; the anchor is
byte-identical throughout. A format-version 2 fixture shows the same
invariance across its stored set (Draft→Ready, and the reopen
Ready→Draft) — the exclusion is universal. A meaning edit (a REQ body
word change, a task field change) changes the anchor. Runs under
`mise run check` in CI.

### REQ-A1.2 — Header-block bounding [test]

Fixture with `**Status:**` lines in body prose and inside a fence: editing
those lines changes the anchor (they remain anchored content); only the
header-block line is excluded. A malformed, duplicated, or unterminated
header block makes the tool fail closed (non-zero exit, no anchor
printed) — asserted red. Same suite and CI path as REQ-A1.1.

### REQ-A1.3 — Tool self-description accuracy [design-level]

The corrected header comment in the anchor tool describes exactly the
implemented digest scope; verified by review against the REQ-A1.1/A1.2
tests, which pin the behavior the prose must describe.

### REQ-A1.4 — Paired re-anchor sweep [test]

One-shot landing proof in Task 3's PR: for every non-Draft, non-terminal
bundle under `specs/` with a kickoff brief, the recomputed anchor equals
the brief's most recent anchor entry, re-verified with the
classifications at the merge SHA. The sweep PR records each bundle's
delta classification (lifecycle/expression-only entered vs meaning-class
routed), including a routed fixture case: a meaning-class delta parks its
bundle (no machine entry, the `anchor re-review pending` bullet written,
gate stays failed closed) and the sweep still lands with the landing
proof green — the parked bundle reports as a known-parked notice. The
Task 4 guard then enforces the recompute-equal property permanently in
`mise run check`.

### REQ-A1.5 — Adopter remedy documented [design-level]

The adopter docs and the freshness gate's v1 halt guidance both name the
one-time expression-only self-re-anchor remedy; existence and placement
verified at review.

## REQ-B — Gate reference frame

### REQ-B1.1 — Committed-main frame stated [design-level]

The meta-spec's execution-validity prose contains the v1 committed-main
frame statement scoped to the sanctioned derived Status mirror; the gate
consumers (`/orchestrate`, `/execute-task`) cite it. Verified by review.

## REQ-C — Re-anchor pathways

### REQ-C1.1 — Stale-anchor pre-flight [Gherkin + manual]

Scenario: given a signed bundle whose brief anchor no longer recomputes
equal — or whose entry is absent or unparseable, or whose recompute
errors — when a planwright-shipped skill is about to edit the bundle,
then it surfaces the condition and applies no bundle edit. True-negative:
given a fresh anchor, the pre-flight proceeds without noise. Exercised
manually in the next live act-on-findings run over a signed spec.

### REQ-C1.2 — Expression-only self-ritual [Gherkin + manual]

Scenario: given a validated expression-only finding on a signed bundle,
when the skill applies it, then the same change contains the dated
Changelog entry and the marked `Class: expression-only` self-re-anchor
entry citing it, all in one commit, and the REQ-D1.1 guard is green
afterwards. Exercised manually at the next live act-on-findings run over
a signed spec (the REQ-C1.1 occasion); the guard provides the mechanical
backstop.

### REQ-C1.3 — Meaning-class refusal and routing [Gherkin + manual]

Scenario: given a validated meaning-class finding on a signed bundle, when
the skill routes findings, then the bundle is untouched and the handoff
names `/spec-kickoff` as the route. Exercised manually in live runs.

### REQ-C1.4 — Kickoff terminal recompute [Gherkin + manual]

Scenario: given expression-only anchored content edited after the
sign-off record was written, when `/spec-kickoff` reaches its final
pre-push step, then the anchor is recomputed and re-recorded before the
push, and the spec PR's squash carries the fresh anchor; given a
meaning-class post-sign-off edit, the flow re-enters the sign-off walk
first; given a failing recompute, the push halts. Exercised manually at
the next `/spec-kickoff` run whose spec PR receives post-sign-off fixes.
The REQ-D1.1 guard on the PR is the mechanical backstop.

## REQ-D — Mechanical guards

### REQ-D1.1 — Guard: recorded anchor recomputes equal [test]

Unit tests for the guard script: green on a fixture repo whose briefs
match; red on a synthesized stale anchor; red on a non-sanctioned command
form; red on an unparseable anchor entry; with multiple entries, the most
recent is the one checked (fixture with an older-fresh/newer-stale pair);
each sanctioned form accepted; a stale-anchored fixture carrying the live
`anchor re-review pending` marker reports as a known-parked notice and
exits 0. Wired as a `mise run check` task, so GitHub Actions CI runs it
on every PR.

### REQ-D1.2 — Guard: changelog pairing [test]

Fixture: an edit to anchored content since the baseline ref without a
dated Changelog entry in that bundle is red; the same edit with the entry
is green. False-positive direction: an edit confined to excluded content
(a header Status flip, a `tasks.md` state annotation or block move)
without a changelog entry stays green. An unresolvable default baseline
degrades to skip-with-notice; a failing explicit `--baseline` is fatal.
Same suite and wiring as REQ-D1.1.

### REQ-D1.3 — Pre-commit mirror [test + manual]

`lefthook.yml` (introduced to the repo by Task 4) invokes the same guard
script only when `specs/**` content is staged (asserted by a config
test); manual: a commit in this repo staging a stale-anchored spec is
blocked at commit time when hooks are installed, and a non-spec commit
pays no guard latency.

### REQ-D1.4 — Guard skip semantics [test]

Fixtures: a Draft bundle, a Retired bundle, and a Superseded bundle are
skipped with a notice and exit 0; a brief-less Ready fixture is red with
the repair remedy named. Same suite as REQ-D1.1.

### REQ-D1.5 — Guard execution safety [test]

Fixtures in the same suite: a brief entry whose recorded command carries
an injected suffix (`; …`), a substitution, or an out-of-tree
`<spec-dir>` is refused as non-sanctioned with no execution side effect;
diagnostics for a fixture with control bytes in parsed content arrive
sanitized; an invalid `--baseline` value is rejected before any git
invocation.

## REQ-E — Authoring guidance

### REQ-E1.1 — Decided-rule guidance [design-level]

The meta-spec's authoring guidance contains the decided-rule refinement
with its dated changelog entry; verified by review.

### REQ-E1.2 — Enumeration cross-check step [design-level + manual]

Both `/spec-draft` and `/spec-kickoff` prose carry the cross-check step;
exercised manually at the next live drafting and kickoff sessions.

## REQ-F — Portability

### REQ-F1.1 — Resolution-aware command form [test]

Resolution test: in a temp directory with no `scripts/`, with the root
chain pointing at the shipped tree, the logical form resolves and
recomputes the same anchor as the canonical repo-relative form.
Negatives: each chain arm is exercised and the first-hit precedence
asserted; a chain that resolves nothing produces the fail-closed
absent-anchor-class halt; with a checked-tree canonical script present,
it wins over the chain. Gate acceptance of all sanctioned forms is
covered by the REQ-D1.1 form tests.
