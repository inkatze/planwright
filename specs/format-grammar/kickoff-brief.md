# Format grammar & parser unification — Kickoff brief

## 1. Header

- **Spec:** `specs/format-grammar` (format-version 2)
- **Spec commit at walkthrough start:** `3262f51`
- **Walkthrough date:** 2026-07-16
- **Mode:** first activation
- **Validator outcome (pre-flight):** `spec-validate: 0 error(s), 0 warning(s)` (v0.14.1)
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true`
- **Working location:** spec worktree `.claude/worktrees/format-grammar-spec`, branch `planwright/format-grammar/spec`, clean tree

## 2. Goal & glossary

**Restatement.** The spec-parse grammar — how a bundle's lines are lexed into
headings, REQ bullets, header declarations, reference bullets, and gate
entries — exists today only as divergent script-local copies, with tests
rather than doctrine holding the semantics. This spec does three coupled
things: (a) lands the grammar as normative doctrine in
`doctrine/spec-format.md` and `doctrine/accumulator-taxonomy.md`, executing
the 2026-06-12 human fence-amendment decision plus the rules the observations
accumulated since; (b) gives the grammar exactly one implementation home, a
sourceable POSIX-sh lib (working name `spec-parse.sh`, the `echo-safety.sh`
precedent) that all parsers source and cite, founded with three parse
families and with the line-80 surfaces sequenced onto it; (c) hardens the
validator against a documented blind-spot list and reconciles the gate
grammar with the six-status lifecycle. Three thin `/spec-kickoff`
verification homes ride along (D-17). Doctrine is the deliverable; scripts
implement and cite it.

**Rules out.** The `/spec-walkthrough` scope grammar (legacy line 96);
instruction-budget relief itself (the sibling instruction-headroom spec owns
it; this spec only gates on it); re-deciding derivation-engine semantics (the
completed-semantics asymmetry is documented, not fixed); v1→v2 migration; a
semantic cross-spec citation index; gate *evaluation* changes.

**Assumes.** The sibling instruction-headroom spec exists and lands enough
relief that `scripts/check-instructions.sh` passes with Task 5's amendments
applied; the shipped `drain-gates.sh` fence semantics are the right ones to
ratify (D-5); the doctrine altitude is pre-decided, not re-litigated (D-1).

**Recorded resolution.** The bundle is born with Task 5 parked in
`## Awaiting input`, so after sign-off the spec sits Ready with a live parked
bullet from day one — deliberate per D-16: the parking blocks derived Done,
stays surfaced every render, and the unpark is a human act keyed to the
closure check passing with the amendments applied.

**Glossary (implicit terms surfaced).**

- *The four v2 parsers* — `orchestrate-select.sh`, `drain-gates.sh`,
  `spec-status.sh`, `spec-validate.sh`.
- *Illustration mode* — the state a column-0 code-fence line toggles; inside
  it no line parses as a heading, requirement bullet, reference bullet, gate
  entry, or header line.
- *Posture* — a parser's lexical tolerance set: fence guard, CRLF-tolerant
  trimming, `**Task <token>**` reference-bullet discrimination, prose-bullet
  tolerance.
- *Line-80 surfaces* — REQ bullets, D-ID headings, task headings, and
  `Dependencies:`/`Citations:` token extraction (named for frozen legacy
  observation line 80).
- *Budget wall* — the `check-instructions.sh` reachable-closure instruction
  budget (20,000 words); orchestrate's closure stands at 19,997 at drafting.

Signed off: 2026-07-16

## 3. Requirements walkthrough

Groups walked in order (REQ-A through REQ-G; group and REQ inventory per
`requirements.md`, cited not copied).

- **REQ-A (normative grammar):** restated as ten doctrine amendments.
  Fence lexical details (which markers count, unclosed-fence behavior) are
  deliberately pinned at Task 5 by matching the shipped `drain-gates.sh`
  implementation (D-5) — accepted. REQ-A1.9 and (in group E) REQ-E1.3 edit
  the invariant-tasks bundle as expression-only amendments; confirmed
  sanctioned under the meta-spec's self-re-anchor writer rule. Grounding:
  all 14 in-repo `test-spec.md` files already use H2 REQ grouping, so
  REQ-A1.7 ratifies existing practice and makes no bundle nonconforming.
- **REQ-B (shared lib):** restated; anchor stability on the
  `extract_tasks` re-point is a hard Done-when, and the security bar is
  inherited rather than restated. No gaps found.
- **REQ-C (posture alignment):** restated; the re-anchor-sweep obligation
  (REQ-C1.4) covers the only two anchor-moving changes (extraction
  re-point — forbidden to move; v1 fence-awareness — swept). No gaps found.
- **REQ-D (validator hardening):** the D-9 blanket severity wording lacked
  the exception REQ-A1.2/REQ-D1.9 pin (error at every status). **Decision
  (human, 2026-07-16): add a carve-out to D-9** naming the fail-closed
  family posture (invariant-tasks D-7) for unparseable-version rules.
  Grounding: the baseline-ref machinery REQ-D1.8 reuses already exists in
  the stable-ID check.
- **REQ-E (gate grammar and drain):** the D-10 budget split means the
  whitelist fix and free-text hint (Task 4, ungated) ship before the
  taxonomy grammar text (Task 5, gated) — a deliberate
  doctrine-lags-script window, accepted because the six-status set is
  already normative in the meta-spec and the alternative parks a live
  false-alarm fix behind the headroom wall.
- **REQ-F (kickoff verification homes):** REQ-F1.1 stays `[manual]`,
  exercised at the next real occurrence of each routing mode (this kickoff
  is a first activation and does not discharge it).
- **REQ-G (sequencing):** the unpark condition is
  `check-instructions.sh` passing with the amendments applied; the
  19,997/20,000 figure is a point-in-time drafting measurement whose drift
  does not stale the gate.

**Consolidated spec-edit list:** 1. `design.md` D-9 — severity carve-out
for unparseable-version declaration rules (applied 2026-07-16).

Signed off: 2026-07-16

## 4. Design walkthrough

All 17 D-IDs accounted for (ledger per `design.md`, cited not copied):

- **Confirmed, rationale intact (16):** D-1, D-2, D-3, D-4, D-5, D-6, D-7,
  D-8, D-10, D-11, D-12, D-13, D-14, D-15, D-16, D-17.
- **Amended (1):** D-9 — severity carve-out for unparseable-version rules,
  applied at this walkthrough per the section-3 decision.
- **Superseded (0):** none.

No design decision contradicts a walked requirement. Cross-cutting
concerns reviewed: the lib inherits the framework-script security bar
(REQ-B1.6); anchor movement is a first-class deliverable risk (REQ-B1.2
forbids movement on the re-point, REQ-C1.4 sweeps v1 fence-awareness);
research-rigor triggers scoped to the security-touching parser patterns.

Signed off: 2026-07-16

## 5. Verification approach

**Coverage mix** (per `test-spec.md`'s intro, cited not copied): parser,
validator, and gate behaviors `[test]` (fixture suites under `tests/`, run
by `mise run check` in CI); doctrine amendments `[design-level]` with
`[test]` companions where a parser enforces the rule; skill-ritual
behaviors `[manual]`. Every REQ has at least one entry (validator coverage
check clean at pre-flight).

**Ownership.** `[test]`: GitHub CI via `mise run check`. `[manual]`
(REQ-D1.10, REQ-F1.1, and the manual halves of REQ-C1.4, REQ-D1.8,
REQ-G1.1): reviewed at PR time or exercised at the next real occurrence —
and kept visible by the `/drain` per-spec `[manual]` inventory this spec
itself delivers in Task 4 (dogfooding its own remedy).

**Dead paths.** None found: REQ-E1.3's real sweep runs today; the
baseline-ref fixtures reuse shipped stable-ID machinery;
`check-instructions.sh` exists and is wired into Task 5's Done-when.
REQ-F1.1 is deferred-but-not-dead: Task 7 must produce the documented
exercise steps before the next real occurrence runs them.

Signed off: 2026-07-16

## 6. Task graph

Reconstructed from the `Dependencies:` lines in `tasks.md` (authoritative;
this rendering is derived):

```
Task 1 ──▶ Task 2 ──▶ Task 3
              │
              └──▶ Task 6 ──▶ Task 8
                    ▲
Task 5 (parked) ────┘
Task 4 ──▶ Task 7
```

**Parallelism:** Tasks 1 and 4 are dispatchable immediately once the spec
is operational; Task 7 follows Task 4 (edge added at the 2026-07-17 panel
pass: its REQ-F1.2 fixture captures the entry Task 4 produces); Task 5 is
a parked root (headroom condition); the gated lane is 5 → 6 → 8.

**Critical path** (effort-weighted, efforts per `tasks.md`):
1 → 2 → 6 → 8, ~9 chained days — with the real wall-clock gate being the
external headroom relief that unparks Task 5, not effort.

**Deliberate non-edges (do not "fix"):**

1. **4 ↛ 5** — D-10 deliberately splits the whitelist fix (follows
   already-normative meta-spec doctrine, ships ungated) from the taxonomy
   grammar text (budget-gated).
2. **3 ↛ 5** — Task 3's hardening rules ground in already-normative
   meta-spec text; the amendment-dependent rules (retirement escape,
   fence-awareness) sit in Task 6, which does depend on 5. The split is by
   doctrine-grounding, not theme. (The duplicate-declaration error was
   originally listed here as Task 6's; the 2026-07-17 lens pass moved it
   to Task 3 on its already-normative grounding.)
3. **No cross-spec edge from Task 5** — the `Dependencies:` grammar is
   same-bundle task ids and the sibling spec does not exist yet;
   Awaiting-input parking is the sanctioned mechanism (D-16).

Signed off: 2026-07-16

## 7. Risk register

Gap check: the merged decision-domains catalog
(`scripts/resolve-catalog.sh decision-domains`, 11 domains) walked against
the spec; two touched-but-undecided domains surfaced (rows 6–7) and were
resolved to decisions with the human. All other domains untouched or
already decided in the bundle (data-storage: D-15; observability:
convention; deploy-migration: anchor REQs; dependency-adoption: D-3).

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | Anchor movement trips freshness gates on shipped bundles | REQ-B1.2 byte-identical proof (Task 1 Done-when); REQ-C1.4 re-anchor sweep in the same change (Task 6). Signal: recomputed-anchor diffs in the tasks' own checks. |
| 2 | Headroom relief lands late or never; Tasks 5/6/8 stay parked and the spec cannot derive Done | Awaiting-input parking keeps it surfaced every render; ungated lanes (1→2→3, 4, 7) deliver independent value. Signal: drain sweeps; the sibling instruction-headroom spec branch already exists. |
| 3 | Doctrine-lags-script window: Tasks 2/3/4 ship behavior before Task 5's doctrine text | Accepted per D-10 and the 3↛5 non-edge. The `ready` whitelist and duplicate-declaration rules cite already-normative meta-spec text; the fence posture is NOT yet normative anywhere, so interim fence-aware parsers cite this bundle's D-5, with Task 5 flipping the citations to the meta-spec (REQ-C1.1, corrected at the lens pass). Signal: reviewer/adopter confusion on the interim state. |
| 4 | New validator rules false-positive on adopter bundles | D-9 rollout contract (all-bundle runs, in-task fixes, release notes; warn severity for the REQ-D1.3 heuristic). Signal: trip counts on in-repo bundles during Task 3. |
| 5 | Lib becomes a single point of failure: one bug breaks all four parsers at once | Lib unit tests; shared fixture corpus requiring identical classifications; anchor-stability proof; fail-closed posture halts rather than silently mis-parses. Signal: fixture-corpus disagreement in CI. |
| 6 | Gap-check decision (api-surface): the lib's sourceable function surface had no declared audience | **Decided 2026-07-16: internal-only.** No adopter stability promise; in-repo scripts are the only supported consumers. Declaring a public surface later is additive. |
| 7 | Gap-check decision (versioning-scheme): whether the grammar amendments bump the meta-spec format version | **Decided 2026-07-16: no bump.** The amendments define previously-undefined lexical behavior and land as dated version-history clarifications applying to versions 1 and 2 (the 2026-07-10 precedent); Task 5 records the rationale in the amendment text. Adopter-visible validator changes covered by D-9's release-notes contract. |
| 8 | Cross-bundle expression-only amendments (invariant-tasks edits, consolidated into Task 4 at the lens pass) mis-executed: missing changelog or re-anchor entry would stale invariant-tasks' anchor and block its dispatch | Task 4 is now the single owner of both edits with the self-re-anchor entry in its Done-when; REQ-F1.2's fixture proves the produced entry parses execution-valid; the freshness gate fails closed either way. Signal: a freshness-gate halt on invariant-tasks. |
| 9 | Residual (lens pass, accepted): re-anchor sweep merge-window TOCTOU — a bundle gaining fenced task-shaped lines between Task 6's execution and its merge is outside the sweep's snapshot | Backstop: the freshness gate fails closed on the missed bundle; recovery is a marked expression-only self-re-anchor, not a re-walkthrough. |
| 10 | Residual (lens pass, accepted): headroom re-consumed by concurrent doctrine merges between the human unpark decision and Task 5's landing | Backstop: Task 5's Done-when re-runs `check-instructions.sh` at landing, failing closed; the unpark simply re-parks. |
| 11 | Residual (lens pass, accepted): a bundle merged concurrently with a new validator rule can violate it immediately on landing (D-9 all-bundle run is a snapshot) | Backstop: CI runs the validator on main continuously; a violating merge surfaces as a red check immediately, remedied by an in-place fix riding the self-re-anchor ritual. |

No open questions remain: both gap-check forks resolved to decisions;
every other row is mitigated or explicitly accepted.

Signed off: 2026-07-16 (rows 9–11 and the row 3/8 corrections appended at
the 2026-07-17 lens pass, before first sign-off)
