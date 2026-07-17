# Format grammar & parser unification — Design

**Status:** Ready
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new this bundle; `H` = human-selected at a drafting fork
(2026-07-16 session); `C` = carried from a prior recorded decision.

## Decision log

### D-1: The deliverable is doctrine-first  (C, legacy line 41; the pinned altitude claims)

**Decision:** The grammar rules this spec introduces (fence/illustration,
duplicate `Format-version:`, header-block scope, ordering, superseded-task
home, gate-grammar additions) land as normative doctrine in
`doctrine/spec-format.md` and `doctrine/accumulator-taxonomy.md`; scripts
implement and cite those definitions. This is the altitude record for the
fired seed-claim trigger: the 2026-06-12 human decision already classified
the fence work as a full, meaning-class meta-spec amendment, and the
fragments describe the shipped posture as "normatively homeless".

**Alternatives considered:**
- Script-local fixes with comment cross-references (the status quo pattern).
  Rejected because: it reproduces exactly the divergence this spec exists to
  end — each parser re-derives the rule, and tests, not doctrine, hold the
  semantics.
- Doctrine in a new standalone grammar doc. Rejected because: the meta-spec's
  contract is authorable-from-this-doc-alone; splitting the grammar out
  breaks that contract and adds a second normative surface to keep in sync.

**Chosen because:** the altitude was already decided by the human on
2026-06-12; this bundle executes that decision rather than re-litigating it.

### D-2: New bundle, not an extension  (H)

**Decision:** The work ships as `specs/format-grammar`, a new bundle citing
invariant-tasks and bootstrap as Sources, rather than extending either.

**Alternatives considered:**
- Extend invariant-tasks (the v2 owner). Rejected because: it is Ready and
  near-fully executed; injecting a large meaning-class delta forces a scoped
  re-walkthrough before its remaining tasks can dispatch, and the v1 fence
  grammar, validator hardening, and taxonomy items sit outside its domain.
- Extend bootstrap (the original meta-spec owner). Rejected because: it is
  Done and v1; reopening the founding bundle contradicts the established
  supersede-pointer precedent (kickoff-lifecycle), and most of this work
  postdates its decision space.

**Chosen because:** the bootstrap D-21 spin-new triggers fire (independently
ownable, orthogonal decision space, would overload either bundle);
human-selected at fold-detection.

### D-3: Lib shape — one flat, sourceable, stream-emitting POSIX-sh library  (N)

**Decision:** The shared extraction lib is a single sourceable POSIX-sh file
in `scripts/` (working name `spec-parse.sh`), following the `echo-safety.sh`
precedent: callers source it and consume stream-emitting functions (the
canonical `tasks.md` extraction stream, the header-scoped `Format-version:`
value, tagged parked-map records). Awk fragments live inside the lib as the
implementation detail. Entry points are batchable: a consumer can obtain
every family it needs in a single pass over the file, so hot paths (the
per-step orchestrate reads) do not multiply file reads or process spawns.
Record framing is injection-safe (embedded delimiter or newline bytes in
parsed content cannot spoof records), and the lib emits raw bytes — anchor
stability forbids lib-side mutation — with echo discipline remaining at
each caller's output sites (REQ-B1.6).

**Alternatives considered:**
- A `scripts/lib/` directory of per-family files. Rejected because: the repo
  has no `lib/` convention; `echo-safety.sh` established flat-sourceable, and
  one file keeps the source-and-call contract trivial.
- A standalone executable emitting a JSON/tagged record stream consumed via
  pipes. Rejected because: every consumer is already a shell script that
  sources helpers; a subprocess contract adds quoting and error-propagation
  surface without a second kind of consumer to justify it.

**Chosen because:** it is the smallest shape that gives the grammar one
implementation home, matches the shipped precedent, and directly supplies
the stream-emitting entry point `spec-anchor.sh` was noted to lack
(obs:6d8f32a4).

### D-4: Lib reach — founding home, named families first  (H)

**Decision:** The lib ships the three named parse families first
(`extract_tasks`, header-scoped `Format-version:`, parked-map/reference
bullets) with the four v2 parsers re-pointed, and is simultaneously decided
to be the single future home of the whole spec-parse grammar: the line-80
surfaces (REQ bullets, D-headings, task headings, `Dependencies:`/
`Citations:` tokens across validator, selector, `spec-model.sh`) migrate
onto it as explicitly sequenced tasks. The `/spec-walkthrough` scope grammar
(legacy line 96) is excluded.

**Alternatives considered:**
- Named families only. Rejected because: it leaves the REQ/D grammar in
  three independent encodings with no decided home, re-deferring legacy
  line 80 with no vehicle.
- Maximal reach including the scope grammar. Rejected because: the scope
  grammar is a comprehension-domain selector language, not spec-format
  grammar; folding it in widens the blast radius across three more
  load-bearing scripts for a different domain's benefit.

**Chosen because:** human-selected at the lib-reach fork; consumes legacy
line 80 honestly (a founding decision plus sequenced migration) without
scope creep into line 96.

### D-5: Fence semantics — codify the shipped column-0 toggle rule  (C, legacy line 45)

**Decision:** The normative fence rule codifies the semantics
`drain-gates.sh` shipped and its tests assert: a column-0 code-fence line
toggles illustration mode; while inside a fence, no line parses as a
heading, requirement bullet, reference bullet, gate entry, or header line.
The amendment task pins the exact lexical definition (which fence markers
count) by matching the shipped implementation and recording any deliberate
extension in the amendment text. The unclosed-fence disposition is pinned
now rather than deferred: an unbalanced column-0 fence count is a
validator-flagged malformation (REQ-D1.11), never a silent
illustration-to-end-of-file — the toggle alone would otherwise let one
stray fence swallow the rest of a bundle from every parser.

**Alternatives considered:**
- Full CommonMark fence semantics (indented fences, info strings, nested
  containers). Rejected because: spec bundles are constrained-authoring
  documents, not arbitrary Markdown; the parsers are line-oriented awk, and
  a full CommonMark lexer in portable awk is disproportionate to the risk.
- Keeping the authoring constraint only ("no column-0 spec-shaped lines in
  fences") with no parser change. Rejected because: the human already
  rejected that on 2026-06-12 by deciding the full grammar amendment; the
  constraint survives only as interim guidance until this lands.

**Chosen because:** two of four v2 parsers already implement and test this
rule; codifying shipped behavior makes the amendment a ratification, not a
migration.

### D-6: Duplicate `Format-version:` fails closed  (N)

**Decision:** More than one `Format-version:` declaration inside a file's
header block is unparseable: version-keyed scripts refuse (never falling
open to a positional winner or the v1 write path), and the validator errors
at every status. The same posture covers a duplicate in-header `Status:`
declaration — the sibling load-bearing header key drives stored-status
whitelists and the derivation, and a contradictory duplicate there has the
identical positional-winner defect *(extended at kickoff lens pass
2026-07-17)*.

**Alternatives considered:**
- First-match wins (the current silent behavior). Rejected because: two
  contradictory declarations mean the file's version is unknown; picking one
  by position hides the contradiction, and each parser could pick
  differently.
- Last-match wins. Rejected because: same defect, different winner.

**Chosen because:** invariant-tasks D-7 already fixed the family posture as
fail-closed on an unparseable declaration; a contradictory duplicate is an
unparseable declaration.

### D-7: Header-block-scoped declaration parsing  (N)

**Decision:** `Format-version:` and `Status:` are recognized only within the
header block; the amendment defines the block's extent normatively (from
the H1 through the contiguous run of bolded `**Key:** value` header lines,
ending at the first line that is neither such a line nor blank). Body
occurrences of the same literals are inert.

**Alternatives considered:**
- Keep first-match-anywhere (the shipped family trait). Rejected because: a
  column-0 body literal masks a *missing* header declaration instead of
  failing closed — the exact latent bug obs:89cf2853 records.
- Fixed line-window scoping (for example lines 1–10). Rejected because: a
  magic number breaks on legitimate header growth (`Superseded-by:`,
  `Execution:`) and is not a rule an author can reason about.

**Chosen because:** it makes the parse match the format's stated structure
(declarations live in the header block), and the previously-declined
one-copy fix becomes safe once all consumers move in one change via the lib
(the out-of-unit objection dissolves).

### D-8: The single v2 parser posture, enumerated  (C, invariant-tasks Task 5 + validator rules)

**Decision:** The aligned v2 posture is: fence-as-illustration (D-5);
CRLF-tolerant trimming when matching section headings; reference-bullet
discrimination requiring a complete `**Task <token>**` bold lead with a
whitespace-free token; and tolerance of plain prose bullets per the
validator's inner-whitespace rule. All four v2 parsers consume the lib's
parked-map parse so the posture cannot re-diverge.

**Alternatives considered:**
- Alignment by parallel edits to four scripts without the shared lib.
  Rejected because: that is the fourth copy obs:5782486b warns against;
  divergence would re-accumulate with the next edit.
- Loosest-common-denominator posture (accept any bullet whose bold lead
  merely begins with the `**Task` prefix).
  Rejected because: the validator already ships the stricter discrimination;
  loosening downstream readers would treat validator-accepted prose as
  parking references (obs:22878c2c's exact drift).

**Chosen because:** every element is already shipped and tested somewhere in
the family; the decision is which member's behavior generalizes, and in each
case the hardened Task-5 behavior is the one with tests.

### D-9: Compatibility posture for new validator rules and anchor-moving changes  (N)

**Decision:** New validator rules follow the carried bootstrap D-25
severity model
(warnings on Draft, errors on the signed-off live statuses, warnings on
Retired/Superseded). Exception: a rule that makes a version declaration
unparseable (the duplicate in-header `Format-version:`/`Status:` rule,
REQ-A1.2 / REQ-D1.9) follows the fail-closed family posture carried from
invariant-tasks D-7 and errors at every status, Draft included. Before
landing, each rule runs against every in-repo bundle; violations are fixed (or the rule adjusted) in the same task, and
adopter-visible severity changes are named in release notes. Any parser
change that moves a shipped bundle's content anchor lands with an
expression-only re-anchor sweep in the same change.

**Alternatives considered:**
- Introduce new rules as warnings everywhere, promote to errors later.
  Rejected because: a two-phase rollout doubles the release surface, and the
  bootstrap D-25 model already scopes blast radius (Draft bundles never
  hard-fail).
- Land parser changes and let freshness gates trip naturally. Rejected
  because: a tripped gate halts every dependent dispatch with a misleading
  "meaning changed" signal for what is a tooling change.

**Chosen because:** the decision-domains api-surface entry escalates
adopter-visible contract changes; this pins the rollout contract once
instead of per-rule.

### D-10: Gate-grammar lockstep, split by budget  (N)

**Decision:** `drain-gates.sh`'s stored-status whitelist gains `ready`
in the ungated script task, citing the meta-spec's six-status table as the
already-normative status set; the status-atom *grammar text* in
`doctrine/accumulator-taxonomy.md` updates in the budget-gated doctrine
task, together with the free-text-gate form and the taxonomy delta.

**Alternatives considered:**
- Strict lockstep (whitelist and grammar text in one change). Rejected
  because: the taxonomy doc sits inside orchestrate's reachable closure
  (19,997/20,000 words), so the pair would park a live false-alarm fix —
  every sweep over a Ready spec warns today — behind the headroom wall.
- Whitelist-only, no taxonomy update. Rejected because: it leaves the
  grammar doc contradicting the shipped evaluator, the exact drift class
  obs:2361a49f records.

**Chosen because:** the six-status lifecycle is already normative in
`doctrine/spec-format.md`; the taxonomy is the lagging mirror, so the
script fix follows existing doctrine rather than preceding it.

### D-11: `## Tasks` ordering is non-normative  (H)

**Decision:** Block order in a v2 `## Tasks` section carries no meaning.
`Dependencies:` lines are the sole source of the task graph; dependency
order is recommended authoring guidance; the id-sorted order the migration
emits is equally conformant. No validator ordering rule is added.

**Alternatives considered:**
- Normative id-sorted order. Rejected because: fresh drafts lose the
  readable dependency-ordered narrative, and enforcement adds churn for a
  property nothing consumes (the anchor extraction id-sorts regardless).
- Normative dependency order. Rejected because: it makes the shipped
  migration output and every migrated bundle nonconforming, requiring a
  topological-sort rework for zero functional gain.

**Chosen because:** human-selected; the contradiction between the two
normative surfaces dissolves without churning either implementation.

### D-12: Superseded/retired tasks — document the home and add the escape  (N)

**Decision:** Both remedies land: the meta-spec names the sanctioned
representation (v1: the retained whole block in its state section with a
supersession/retirement annotation; v2: a reference bullet parking the
block Out of scope or Deferred, block staying in `## Tasks`), including the
test-spec tombstone handling for a superseded REQ group; and the validator
gains a changelog-named task-retirement escape mirroring the REQ
supersession path.

**Alternatives considered:**
- Document-only (the legacy line 65 "arguably correct never-delete"
  reading). Rejected because: it leaves the validator asymmetry — REQs can
  retire via changelog, tasks cannot — that forced the bootstrap T18
  workaround.
- Escape-only. Rejected because: without a named home, each carve-out
  improvises placement (the output-hygiene experience, legacy line 169).

**Chosen because:** the two seeds record two different failure modes; each
remedy addresses one, and they compose.

### D-13: Cross-spec citation checks scoped to honest capability  (N)

**Decision:** The validator warns on out-of-range, unqualified `D-<n>` /
`REQ-<id>` tokens (mechanical, low-false-positive). Semantic misattribution
of a *qualified* citation is a documented kickoff lens-checklist item, with
the structural validator's limitation stated alongside.

**Alternatives considered:**
- A cross-spec citation index asserting topical consistency of cited
  headings. Rejected because: "topically consistent" is a judgment call; a
  keyword heuristic would false-positive on legitimate cites and lull
  readers on subtle ones (the legacy line 108 case would likely pass one).

**Chosen because:** each failure mode gets the strongest check that cannot
lie: mechanical range/qualifier checking for the mechanical defect, a named
human lens for the semantic one.

### D-14: Dead-path strengthening via baseline diff  (N)

**Decision:** The coverage-based dead-path check compares against the
validator's existing baseline ref: a REQ whose bullet text changed while
its test-spec entry did not warns. It pairs with a lens-disposition rule:
applying a requirement addition or extension requires a paired test-spec
edit in the same disposition.

**Alternatives considered:**
- Per-clause semantic matching (flag a `[test]` REQ whose entry fails to
  mention each behavioral clause). Rejected because: clause segmentation of
  prose is heuristic; false positives would train authors to pad test-spec
  entries with echoed phrases rather than verification content.

**Chosen because:** the baseline-diff form is exact (no prose
interpretation), reuses shipped machinery, and catches the actual observed
failure (extensions landing without a mirrored test-spec edit).

### D-15: `[manual]` sweep is inventory surfacing, not state tracking  (N)

**Decision:** `/drain` surfaces a per-spec inventory of `[manual]`
test-spec entries for live specs. No exercised/un-exercised state store is
introduced; visibility each sweep is the remedy.

**Alternatives considered:**
- Track per-entry exercise state (a ledger of which manual verifications
  ran). Rejected because: it creates a new shared-write accumulator — the
  exact artifact class the taxonomy doctrine exists to constrain — to solve
  a visibility problem.

**Chosen because:** the write-only-accumulator violation is the absence of a
named reader and drain ritual; an inventory in the existing drain pass
supplies both at zero new state.

### D-16: Budget gating by parking, not fake edges  (N)

**Decision:** The doctrine-amendment task is parked in `## Awaiting input`
via a reference bullet whose free text states the blocking condition
(instruction-headroom relief; the orchestrate closure stands at
19,997/20,000 words). Parking blocks derived Done and keeps the task
surfaced; it unparks when the closure check passes with the amendment
applied.

**Alternatives considered:**
- A cross-spec `Dependencies:` edge. Rejected because: the field's grammar
  is same-bundle task ids, and the sibling instruction-headroom spec does
  not exist yet to be named.
- Parking in `## Deferred` with a gate. Rejected because: Deferred-parked
  tasks are excluded from the Done universe, so the spec could derive Done
  without its core doctrine deliverable.
- A placeholder "verify headroom" task as the dependency target. Rejected
  because: it manufactures a task that is a wait, not work.

**Chosen because:** Awaiting-input parking is the sanctioned v2 mechanism
whose semantics (blocks Done, surfaced every render, human unparks) exactly
match the constraint — and the bullet's free text demonstrates the
free-text-gate form this spec normatively defines.

### D-17: Line-46 verification homes live in this bundle  (H)

**Decision:** The three thin `/spec-kickoff` behaviors (amendment-mode
routing, expression-only anchor-entry production, catalog-absent
degradation) get their verification homes in this bundle's test-spec and
fixture tests, rather than reopening the Done bootstrap bundle whose
test-spec originally under-covered them.

**Alternatives considered:**
- Reopen bootstrap to extend its test-spec. Rejected because: a Done→Draft
  reopen of the founding bundle for test-spec entries is maximal ceremony
  for additive coverage, against the supersede-pointer precedent.
- Leave legacy line 46 unconsumed. Rejected because: it was explicitly
  parked "for the pending fence-grammar delta re-walkthrough" — this
  vehicle; deferring again recreates the write-only deferral.

**Chosen because:** human-selected at the scope-rider fork; the coverage
obligation follows the vehicle that adopted it.

## Cross-cutting concerns

- **Security.** The lib parses untrusted committed content (spec files,
  gate conditions). It inherits the framework-script bar (REQ-B1.6):
  parsed values are data, identifiers re-validate against their grammars,
  echo discipline applies on output. No new attack surface is introduced;
  several are narrowed (fail-closed duplicate handling, header scoping).
- **Anchor stability.** Two changes can move shipped anchors: the
  extraction re-point (REQ-B1.2 forbids any movement) and v1
  fence-awareness (REQ-C1.4 requires the re-anchor sweep when a bundle
  actually contains fenced task-shaped lines). Anchor movement is treated
  as a first-class deliverable risk, not a side effect.
- **Research rigor.** No new dependency, no unfamiliar domain, no
  version-sensitive API: the triggers fire only on the security-touching
  parser patterns, which the security-posture doc already governs; sources
  consulted are this repo's shipped parsers, their tests, and the recorded
  observations.
