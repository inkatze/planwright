# Format grammar & parser unification — Requirements

**Status:** Draft
**Last reviewed:** 2026-07-16
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

The meta-spec's parse grammar is implemented in many divergent copies and has no
normative answers for cases that already bit in practice: fenced example lines
parse as real headings, a duplicate `Format-version:` line silently wins by
position, four v2 parsers disagree on fence and CRLF posture, the gate grammar
predates the six-status lifecycle, and the validator is blind to a documented
set of malformations. This spec lands the grammar as normative doctrine — the
fence/illustration amendment the human decided on 2026-06-12 that never landed,
plus the rules the observations accumulated since — and unifies the
implementations under one shared, sourceable extraction library
(`echo-safety.sh` precedent) that becomes the single future home of the
spec-parse grammar (D-1, D-4). Scripts implement and cite the doctrine; the
doctrine stops being homeless prose asserted only in scattered tests.

## Scope

### In scope

- A normative fence/illustration grammar, a duplicate-declaration rule for
  the load-bearing header keys (`Format-version:`, `Status:`), and a
  header-block scope definition in `doctrine/spec-format.md`.
- One shared extraction lib re-pointing the `extract_tasks` triplication, the
  `Format-version:` parse family, and the parked-map/reference-bullet parse;
  the four v2 parsers (`orchestrate-select.sh`, `drain-gates.sh`,
  `spec-status.sh`, `spec-validate.sh`) aligned on one posture; v1 parsers
  (`spec-validate.sh`, `spec-anchor.sh`) fence-aware in lockstep with the
  grammar amendment; the line-80 grammar surfaces (REQ bullets, D-headings,
  task headings, `Dependencies:`/`Citations:` tokens across validator,
  selector, `spec-model.sh`) migrated onto the lib as a sequenced follow-on.
- Validator hardening: Awaiting-input purity, cited-but-empty REQ bullets,
  out-of-range/unqualified cross-spec ID tokens, the H2 D-ID blindspot,
  a changelog-named task-retirement path, coverage-based dead-path checking,
  canonical task-heading form, duplicate header-declaration errors.
- Gate-grammar reconciliation: `ready` in the status-atom grammar and the
  `drain-gates.sh` whitelist, a normative free-text-gate form, the
  accumulator-taxonomy delta (stale single-pass claim, missing unresolved
  lane), the malformed invariant-tasks Deferred gate fixed, and a per-spec
  `[manual]` test-spec inventory surfaced by the drain.
- Meta-spec wording fixes: `## Tasks` ordering made non-normative, the
  invariant-tasks REQ-C1.5 severity phrasing, the completed-semantics
  asymmetry sentence, a sanctioned home for superseded/retired task blocks,
  test-spec H2 grouping vs MD001.
- Verification homes for three thin `/spec-kickoff` behaviors that were
  explicitly parked for this vehicle (legacy line 46).

### Out of scope

- The `/spec-walkthrough` scope grammar unification (legacy line 96): a
  comprehension-domain grammar, left unconsumed for a later vehicle
  (drafting-session decision, 2026-07-16).
- Instruction-budget relief itself: the sibling instruction-headroom spec owns
  it; this spec's doctrine tasks gate on it (REQ-G1.1), never deliver it.
- Re-deciding derivation-engine semantics: the completed-semantics asymmetry
  is documented, not "fixed" (obs:28d4ceb1 records both sides as deliberate).
- Migrating v1 bundles to v2, or any change to what either format version
  stores.
- A semantic cross-spec citation index: structural validation cannot verify
  topical consistency; the honest remedy is a lens-checklist item (D-13).
- Changing gate *evaluation* semantics beyond the grammar additions named
  above.

## REQ-A — Normative grammar (doctrine amendments)

- **REQ-A1.1** `doctrine/spec-format.md` SHALL define a normative
  fence/illustration grammar: a column-0 code-fence line toggles illustration
  mode, and a fenced line SHALL NOT parse as any grammar element in any
  parser of spec bundles (headings, requirement bullets, reference bullets,
  gate entries, header lines, task-definition field bullets, and
  dependency/citation tokens are the illustrative cases; the rule is
  universal, not enumerated). The rule codifies the fence semantics `drain-gates.sh` shipped
  (D-5); all fence-aware parsers cite this one definition. The amendment
  SHALL also pin the unclosed-fence disposition: an unbalanced column-0
  fence count is a validator-flagged malformation (REQ-D1.11), never a
  silent illustration-to-end-of-file, and the lib's parse entry points
  treat end-of-file inside an open fence as malformed input and fail
  closed (the derivation path is guarded at the lib, not only at validate
  time).
  *(Cites: D-1, D-5, legacy line 41 (Sources), legacy line 45 (Sources),
  obs:e6a18bb1, obs:22ef9d55.)*
- **REQ-A1.2** The meta-spec SHALL state that more than one `Format-version:`
  or `Status:` declaration in a file's header block makes that declaration
  unparseable: parsers fail closed, and the validator reports an error at
  every status. (The two load-bearing header keys share one fail-closed
  posture; a contradictory duplicate of either has no honest positional
  winner.)
  *(Cites: D-6, obs:e6a18bb1, kickoff lens pass (2026-07-17).)*
- **REQ-A1.3** The meta-spec SHALL define the header block's extent and state
  that `Format-version:` and `Status:` declarations are recognized only
  within it; a body line carrying the same literal is inert content.
  *(Cites: D-7, obs:89cf2853.)*
- **REQ-A1.4** The meta-spec SHALL state that v2 `## Tasks` block order
  carries no meaning: `Dependencies:` lines are the sole source of the task
  graph, dependency order is recommended authoring guidance, and the
  id-sorted order the migration emits is equally conformant.
  *(Cites: D-11, obs:94f03e6c.)*
- **REQ-A1.5** The meta-spec SHALL name the sanctioned representation for a
  superseded or retired task: in v1, the retained whole block in its state
  section with a supersession/retirement annotation; in v2, a reference
  bullet parking the block Out of scope or Deferred; plus the test-spec
  handling of a superseded REQ group (entries removed, tombstone note in a
  dated Changelog entry).
  *(Cites: D-12, legacy line 65 (Sources), legacy line 169 (Sources).)*
- **REQ-A1.6** The meta-spec SHALL document a changelog-named task-retirement
  escape mirroring REQ supersession: removing a task block present on the
  baseline passes validation when a dated `## Changelog` entry names the
  retired id.
  *(Cites: D-12, legacy line 65 (Sources).)*
- **REQ-A1.7** The meta-spec's `test-spec.md` section SHALL show and require
  `## REQ-<Group> — <theme>` H2 grouping above the H3 entries, so the format
  example agrees with the MD001 heading-increment guard.
  *(Cites: legacy line 57 (Sources).)*
- **REQ-A1.8** The meta-spec SHALL state the completed-semantics asymmetry:
  gate atoms in `drain-gates.sh` apply reference-bullet authority (a
  re-parked merged task stays unmet) while dependency satisfaction in
  `orchestrate-select.sh` uses the raw engine completed set, both preserving
  their own v1 semantics — so neither side is "fixed" into the other. The
  statement SHALL include the accepted consequence that the two evaluators
  may disagree about the same re-parked task at the same instant.
  *(Cites: obs:28d4ceb1.)*
- **REQ-A1.9** The invariant-tasks REQ-C1.5 severity phrasing SHALL be
  clarified (expression-only): "errors on non-Draft v2 bundles" means the
  signed-off live statuses per the carried bootstrap D-25 severity model;
  Retired/Superseded bundles warn.
  *(Cites: obs:ec113dfe.)*
- **REQ-A1.10** The meta-spec SHALL state that `### Task <id> — <title>` is
  the only recognized task-heading form: a heading matching `### Task` that
  deviates from it (for example a colon separator) is malformed, never
  silently parsed into a wrong id.
  *(Cites: legacy line 38 (Sources).)*

## REQ-B — Shared extraction lib

- **REQ-B1.1** One sourceable POSIX-sh library SHALL be the single
  implementation home of the spec-parse grammar, exposing stream-emitting
  entry points callers consume (the `echo-safety.sh` precedent); no consumer
  keeps a private copy of a grammar the lib implements.
  *(Cites: D-3, D-4, obs:6d8f32a4, legacy line 80 (Sources).)*
- **REQ-B1.2** The canonical `tasks.md` definition extraction SHALL live in
  the lib, with `scripts/spec-anchor.sh`, `scripts/migrate-format-version.sh`,
  and the migration test oracle re-pointed to it; the re-point SHALL NOT
  change the computed anchor of any conforming bundle.
  *(Cites: D-3, obs:6d8f32a4.)*
- **REQ-B1.3** The header-declaration parse — `Format-version:` and
  `Status:`, the two load-bearing keys — SHALL live in the lib,
  header-block-scoped per REQ-A1.3, with every script parsing either
  declaration re-pointed to it — `spec-status.sh`, `tasks-pr-sync`,
  `check-ledger.sh`, `spec-validate.sh`, `orchestrate-select.sh`,
  `drain-gates.sh`, `migrate-format-version.sh`, and `spec-graph.sh`
  (the full private-copy set at drafting; the re-point sweep
  grep-verifies no other consumer remains) — and a duplicate in-header
  declaration fails closed per REQ-A1.2.
  *(Cites: D-6, D-7, obs:89cf2853, kickoff lens pass (2026-07-17).)*
- **REQ-B1.4** The parked-map/reference-bullet parse SHALL live in the lib,
  with all four v2 parsers re-pointed to it.
  *(Cites: D-8, obs:5782486b, obs:22878c2c.)*
- **REQ-B1.5** The line-80 grammar surfaces — requirement bullets, D-ID
  headings, task headings, and `Dependencies:`/`Citations:` token extraction
  across `spec-validate.sh`, `orchestrate-select.sh`, and `spec-model.sh` —
  SHALL migrate onto the lib, sequenced after REQ-B1.2–B1.4 land.
  *(Cites: D-4, legacy line 80 (Sources).)*
- **REQ-B1.6** The lib SHALL satisfy the framework-script security posture:
  parsed spec content is data, never code; identifiers validate against
  their declared grammar before use; echoed untrusted content passes the
  echo-safety discipline; and paths derived from parsed input are
  containment-checked after canonicalization before any read or write.
  Additionally: (a) a consumer SHALL fail closed when the lib cannot be
  sourced (missing, unreadable, or syntax-erroring — a bare POSIX `.` of a
  missing file continues fail-open and is forbidden); (b) the lib's
  stream-record framing SHALL be injection-safe — embedded delimiter or
  newline bytes in parsed content cannot spoof or split records; (c) the
  sanitization boundary is pinned: the lib emits raw bytes (anchor
  stability forbids lib-side mutation) and echo discipline remains at each
  caller's output sites; (d) NUL-bearing input is malformed and fails
  closed in every lib parse (generalizing the screen `drain-gates.sh`
  ships); (e) reference-bullet classification (a whitespace-free token)
  and task-id grammar validation are distinct gates — an emitted token
  still validates against its grammar before any use; (f) consumers check
  the lib's exit status on every call — a truncated stream consumed with
  an unchecked exit is the named fail-open.
  *(Cites: doctrine/security-posture.md (Sources), kickoff lens pass
  (2026-07-17).)*

## REQ-C — Parser posture alignment

- **REQ-C1.1** The four v2 parsers SHALL apply one posture: fence lines
  toggle illustration mode (REQ-A1.1), section headings are matched with
  CRLF-tolerant trimming, a payload-section bullet is a reference only when
  its bold lead is a complete `**Task <token>**` with a whitespace-free
  token, and plain prose bullets are tolerated per the validator's
  inner-whitespace rule. Until the REQ-A1.1 amendment lands, fence-aware
  parsers cite this bundle's D-5 as the rule's provenance; Task 5's landing
  flips the citations to the meta-spec.
  *(Cites: D-8, obs:5782486b, obs:22878c2c.)*
- **REQ-C1.2** The v1 parsers (`spec-validate.sh` and `spec-anchor.sh`'s
  canonical extraction) SHALL become fence-aware in lockstep with the
  REQ-A1.1 amendment, per the 2026-06-12 human decision.
  (`spec-validate.sh` parses both format versions, so it appears among the
  v2 parsers and the v1 parsers deliberately.)
  *(Cites: D-5, legacy line 41 (Sources), obs:22ef9d55.)*
- **REQ-C1.3** `spec-status.sh`'s parked-map parse SHALL gain the fence guard
  and CRLF trim so a live Awaiting-input bullet always blocks derived Done
  on a CRLF checkout (the invariant-tasks REQ-B1.6 inverse).
  *(Cites: obs:5782486b.)*
- **REQ-C1.4** Any parser change that moves a shipped bundle's content anchor
  SHALL be landed with an expression-only re-anchor sweep over the affected
  bundles in the same change, so no freshness gate trips on an unamended
  bundle.
  *(Cites: D-9, doctrine/spec-format.md (Sources).)*

## REQ-D — Validator hardening

- **REQ-D1.1** The validator SHALL flag a non-reference bullet under
  `## Awaiting input` in a v2 bundle (section purity), at the bootstrap
  D-25 severity model.
  *(Cites: obs:cae4fb17.)*
- **REQ-D1.2** The validator SHALL flag a live requirement bullet that
  carries a citation but no normative prose.
  *(Cites: legacy line 86 (Sources).)*
- **REQ-D1.3** The validator SHALL warn on a `D-<n>` or `REQ-<id>` token
  whose number falls outside the bundle's own defined range and which
  carries no sibling-spec qualifier on the same line or enclosing block.
  *(Cites: D-13, legacy line 107 (Sources).)*
- **REQ-D1.4** Semantic cross-spec misattribution (a qualified citation
  resolving to a real-but-unrelated record) SHALL be handled as a documented
  kickoff lens-checklist item, not a validator rule; the limitation is
  stated where the D-13 lens item is defined.
  *(Cites: D-13, legacy line 108 (Sources).)*
- **REQ-D1.5** The validator SHALL flag decision-shaped headings that are not
  `### D-<n>: <title>` — including H2 `D-<n>` headings — and
  period-labelled Decision/Alternatives/Chosen fields, as malformed
  decisions.
  *(Cites: legacy line 161 (Sources).)*
- **REQ-D1.6** The validator's task stable-ID check SHALL accept a task-block
  removal when a dated `## Changelog` entry names the retired id
  (REQ-A1.6's escape), and reject it otherwise; the changelog-extracted id
  is validated against the task-id grammar before the comparison.
  *(Cites: D-12, legacy line 65 (Sources).)*
- **REQ-D1.7** The validator SHALL flag a `### Task` heading that deviates
  from the canonical `### Task <id> — <title>` form (REQ-A1.10).
  *(Cites: legacy line 38 (Sources).)*
- **REQ-D1.8** The validator SHALL warn when a REQ's bullet text changed
  since the baseline ref while its test-spec entry did not (coverage-based
  dead-path check), sharing one baseline load per run with the REQ-D1.6
  check; and the kickoff lens-pass disposition rule SHALL treat a
  requirement addition or extension as requiring a paired test-spec edit in
  the same disposition.
  *(Cites: D-14, legacy line 67 (Sources).)*
- **REQ-D1.9** The validator SHALL report a duplicate in-header
  `Format-version:` or `Status:` declaration as an error at every status,
  and every script keyed on the duplicated declaration SHALL fail closed
  on it (REQ-A1.2).
  *(Cites: D-6, obs:e6a18bb1.)*
- **REQ-D1.10** Every new validator rule SHALL be run against all in-repo
  bundles before landing, with violations fixed or the rule adjusted in the
  same task, and adopter-visible severity changes named in the release
  notes; an in-task fix to a signed-off bundle rides the expression-only
  self-re-anchor ritual so the fix does not stale that bundle's anchor.
  *(Cites: D-9.)*
- **REQ-D1.11** The validator SHALL flag a file whose column-0 fence count
  is unbalanced (an unclosed fence): under the REQ-A1.1 grammar an
  unterminated fence would otherwise silently swallow the remainder of the
  file as illustration, dropping content from every parser with no signal.
  *(Cites: D-5, kickoff lens pass (2026-07-17).)*

## REQ-E — Gate grammar and drain

- **REQ-E1.1** `ready` SHALL be added to the status-atom grammar in
  `doctrine/accumulator-taxonomy.md` and to both of `drain-gates.sh`'s
  stored-status whitelists (the shell `case` list and the awk `VALID` map),
  reconciling all with the six-status lifecycle; the whitelist fix may land
  first, citing the meta-spec's status table as the already-normative set
  (D-10).
  *(Cites: D-10, obs:302b75ca, legacy line 166 (Sources).)*
- **REQ-E1.2** The free-text-gate form SHALL be normatively defined (plain
  prose after `**Gate:**`, never a `GATE(` wrapper), and the drain report
  SHALL hint at that form when a `GATE(when:)` condition matches no
  recognized atom; the hint's echoed condition passes the echo-safety
  discipline before terminal output.
  *(Cites: legacy line 167 (Sources), obs:f46510f1.)*
- **REQ-E1.3** The invariant-tasks Deferred entry using `GATE(when:)` with
  prose atoms SHALL be rewritten to the free-text form as an expression-only
  amendment with a dated changelog entry, silencing the recurring MALFORMED
  report.
  *(Cites: obs:f46510f1.)*
- **REQ-E1.4** `doctrine/accumulator-taxonomy.md` SHALL be updated to the
  shipped drain-gates behavior: the single-pass claim replaced by the
  multi-read evaluation guarded by the widened digest bracket (detection,
  not prevention), and the unresolved clause (`unresolved — completion
  evidence unavailable`) documented as a lane annotation.
  *(Cites: obs:2361a49f.)*
- **REQ-E1.5** `orchestrate-meta-select.sh`'s unexpected-selector-exit
  handling SHALL fail closed: any unexpected non-zero selector exit — or
  selector output that does not parse — is treated as an evaluation
  failure, never as not-a-candidate.
  *(Cites: obs:2361a49f.)*
- **REQ-E1.6** The `/drain` pass SHALL surface a per-spec inventory of
  `[manual]` test-spec entries for live specs, making un-exercised manual
  verification obligations visible each sweep without introducing a new
  state store.
  *(Cites: D-15, legacy line 160 (Sources).)*

## REQ-F — Kickoff verification homes

- **REQ-F1.1** `/spec-kickoff`'s pre-flight amendment-mode routing SHALL have
  a named verification home in this bundle's test-spec.
  *(Cites: D-17, legacy line 46 (Sources).)*
- **REQ-F1.2** Skill-written expression-only anchor-entry production SHALL be
  covered by a fixture test verifying a produced entry parses as
  execution-valid.
  *(Cites: D-17, legacy line 46 (Sources).)*
- **REQ-F1.3** The kickoff gap-check's degradation when the decision-domains
  catalog is absent SHALL be covered by a fixture test.
  *(Cites: D-17, legacy line 46 (Sources).)*

## REQ-G — Sequencing constraint

- **REQ-G1.1** Deliverables that grow `doctrine/spec-format.md` or
  `doctrine/accumulator-taxonomy.md` SHALL NOT land while the
  reachable-closure instruction budget check fails on their dependents
  (orchestrate's closure stands at 19,997/20,000); the tasks carrying them
  are parked awaiting instruction-headroom relief and unpark when the check
  passes with the amendment applied.
  *(Cites: D-16, obs:94f03e6c, the invocation mission (Sources).)*

## Changelog

- 2026-07-16 — Initial draft: bundle elicited from the invocation mission,
  13 observation fragments, and 16 frozen legacy lines; fold-detection
  surfaced invariant-tasks and bootstrap overlaps and the human chose a new
  bundle; lib-reach, `## Tasks` ordering, and scope-rider forks resolved by
  the human (recorded as D-4, D-11, D-17).
- 2026-07-17 — Kickoff walkthrough and lens-pass edits (first activation,
  applied with the human): D-9 severity carve-out; REQ-A1.9's
  invariant-tasks edit moved from Task 5 to Task 4 (single owner of both
  cross-bundle edits, self-re-anchor obligation attached); the
  `Format-version:` consumer list extended to the full eight-script
  private-copy set; the duplicate-declaration validator error moved from
  Task 6 to Task 3 (already-normative grounding); interim fence provenance
  stated (cite D-5 until Task 5 lands); REQ-B1.6 extended with the
  path-access, lib-sourcing, stream-framing, sanitization-boundary, NUL,
  and classification-vs-validation clauses; **REQ-D1.11 added**
  (unbalanced-fence validator flag) with REQ-A1.1 pinning the
  unclosed-fence disposition; assorted Done-when and test-spec
  strengthenings, foreign-ID qualifiers (bootstrap D-25 / bootstrap D-21),
  and tag corrections per the kickoff brief's lens-pass record. A nested
  panel pass (gemini backend) in the same kickoff contributed: the
  fence-EOF fail-closed clause (REQ-A1.1), the duplicate-`Status:`
  extension (REQ-A1.2/REQ-D1.9, D-6), the 7→4 dependency edge, the
  mismatched-id retirement trip case, and two wording corrections.

## Sources

- **The invocation mission (2026-07-16)** — the `/spec-draft` prompt scoping
  the five work areas, naming the seed set, the budget wall, and the
  fold-detection candidates.
- **2026-07-16 accumulator triage** — a 10-agent verification pass against
  v0.14.1 confirming every seed below still valid or partial (session-local
  verdict ledger, machine-local; not committed).
- **Observation fragments (consumed, cited as `obs:<uid>`)** — obs:e6a18bb1
  (fence grammar + duplicate Format-version), obs:22ef9d55 (v1 fence
  blindness), obs:5782486b (v2 parser alignment gaps), obs:22878c2c
  (reference-bullet discrimination), obs:89cf2853 (header-scoped
  Format-version parse), obs:6d8f32a4 (extract_tasks triplication),
  obs:cae4fb17 (Awaiting-input purity), obs:28d4ceb1 (completed-semantics
  asymmetry), obs:ec113dfe (REQ-C1.5 phrasing), obs:302b75ca (gate grammar
  `ready`), obs:f46510f1 (malformed Deferred gate), obs:2361a49f (taxonomy
  drift + unresolved lane), obs:94f03e6c (`## Tasks` ordering wording).
- **Frozen legacy observation lines (consumed in place,
  `specs/_observations/opportunities.md`)** — lines 38 (canonical task
  heading), 41 (the 2026-06-12 fence-amendment decision), 45 (drain-gates
  fence rule fold), 46 (kickoff thin test-spec homes), 57 (test-spec H2
  grouping), 65 (task-retirement path), 67 (dead-path coverage), 80
  (spec-parse grammar triplication), 86 (cited-but-empty REQ), 107
  (out-of-range citations), 108 (semantic misattribution), 160 (`[manual]`
  write-only accumulator), 161 (D-ID heading blindspot), 166 (`ready`
  status atoms), 167 (free-text-gate foot-gun), 169 (superseded task-block
  home). Line 96 (scope grammar) was mined and deliberately left unconsumed
  (Out of scope).
- **Pinned altitude claims** — legacy line 41: the human-decided resolution
  is a *full grammar amendment* in the meta-spec, meaning-class;
  obs:e6a18bb1: the fence posture is "normatively homeless"; legacy line
  45: all parsers should "cite one normative rule". These pin the
  deliverable at doctrine altitude (recorded as D-1).
- **specs/invariant-tasks** and **specs/bootstrap** — the overlapping prior
  bundles (v2 owner; original meta-spec owner) this spec extends upon
  without reopening.
- **doctrine/spec-format.md** and **doctrine/accumulator-taxonomy.md** — the
  normative surfaces amended.
- **doctrine/security-posture.md** — the framework-script security bar the
  lib inherits.
