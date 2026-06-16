# Customization & Overlay Mechanism — Kickoff Brief

**Spec path:** specs/customization-overlay
**Spec commit at walkthrough start:** 4d5efea85c42c611de234f35e2023e8738707900
**Walkthrough date:** 2026-06-15
**Mode:** First activation
**Validator outcome (pre-flight, Draft):** 0 errors, 0 warnings (clean)
**Config:** commit_on_kickoff = true (default; no local override)
**Rule docs resolved:** spec-format, discovery-rigor, validation-rigor,
security-posture, decision-domains, interaction-style (all present)

---

## 2. Goal & glossary

**Goal (restated).** planwright core ships *general* doctrine and skills.
The author and adopters carry preferences that are not general (a
review-gauntlet ordering, a dispatch-isolation default, project-specific
decision-domain entries) that today live ad hoc in personal memory and
dotfiles `CLAUDE.md`. Two costs: skills cannot apply those preferences
systematically, and the only way to bake one in is editing core
doctrine/skills, which makes core less general for adopters and pollutes the
observation stream meant to merge upstream. This spec installs a **seam**: a
sanctioned overlay mechanism with four ingredients — a fixed precedence model
(`core defaults < adopter overlay < repo-tracked overlay < machine-local
overlay`), defined per-layer/per-kind overlay locations, a per-kind
resolution + merge contract skills read *through* (config = last-layer-wins
override; doctrine = whole-doc shadow; catalog = append/union), and a
capability-vs-style boundary doctrine (general capability → core + config
knob + opt-in; personal/team style → overlay).

**What it rules out.** It ships the *seam*, not the overlays: no specific
default changes, no work-fork company content, no migration of personal
memory/dotfiles, no secrets in overlays, no executable/code-injection
extensions (overlays stay declarative), no doctrine fragment/section merge
(whole-doc shadow only in v1), and machine-local *env* plumbing
(`mise.local.toml`) is a separate already-solved layer.

**What it assumes.** Bootstrap's config model (D-33), rule-doc resolver
(REQ-I1.1, D-24), options reference (D-43), and identifier discipline
(REQ-A1.8) already exist to extend; this bundle coordinates with bootstrap
rather than re-deciding them. Fold-detection confirmed spin-new (orthogonal
to bootstrap's build domain).

**Glossary (implicit terms, resolved from doctrine/bootstrap).**

| Term | Resolution |
| --- | --- |
| adopter | the non-author operator who installs planwright without inheriting the author's toolchain (spec-format glossary). |
| kind | one of three overlayable things: config values, doctrine/process docs, data catalogs. |
| plugin mode | delivered as a Claude Code plugin; adopter overlay under `$CLAUDE_PLUGIN_DATA` = `~/.claude/plugins/data/<id>/` (update-stable; the `<id>` segment IS the namespace). |
| writer mode | the `~/.claude/` fallback delivery (`install.sh` writes plain files); overlay derives a namespace dir under `<claude-dir>/planwright/`. |
| guard catalog | the builder skill's extensible core guard catalog (bootstrap Task 16 / D-15), the second growable catalog besides decision-domains. |
| the work fork | the author's company fork that must layer company standards as overlays rather than hard-editing core. |
| bootstrap Task 19 | packaging finalization + adopter onboarding docs; the mechanism must be documentable there. |

**Decisions / resolutions recorded.**
- The goal's "ships before bootstrap Task 19 and before the work fork
  diverges" is **motivation/why-now framing only** — no cross-spec
  dependency edge, no blocking ordering. Recorded as context, not encoded as
  a dependency (human decision, 2026-06-15).

Signed off: 2026-06-15

## 3. Requirements walkthrough

**Group intents (restated).**
- **REQ-A — model, layers, precedence.** Four fixed layers `core < adopter <
  repo-tracked < machine-local`; each kind keeps its native mechanism under
  one precedence rule; no-fork invariant; absent layer degrades (never an
  error); adopter overlay per plugin namespace, resolvable in both delivery
  modes; `planwright.local.yml` IS machine-local (highest), team overlay a
  separate tracked file.
- **REQ-B — resolution & merge.** Config last-layer-wins (extend `config-get`
  2→4 layers); doctrine whole-doc shadow (extend `resolve-rule-doc`); catalog
  append/union + supersede-by-id (decision-domains and guard catalogs); one
  stable per-kind path, no skill rolls its own merge; deterministic by layer
  order; `--explain` provenance per resolver.
- **REQ-C — capability-vs-style doctrine.** Decision-time criteria; default
  tilt to overlay + drain-loop graduation; two worked examples (gauntlet =
  style, dispatch-isolation = core capability); `review_sequence` the runnable
  instance.
- **REQ-D — skill integration.** Skills/hooks read through shared paths;
  doctrine overlays need no new per-skill wiring; `review_sequence` a
  four-layer config list-knob honored by `/execute-task` convergence,
  default-preserving.
- **REQ-E — hygiene, security, docs.** No secrets (secret-scan covers
  committed overlays); identifier validation before interpolation;
  options-reference + adopter docs; malformed-by-layer (adopter/machine-local
  degrade+warn, repo-tracked hard-fail); doctrine-overlay path-traversal
  confinement.

**Per-group outcomes.** All five groups are internally coherent and consistent
with the design ledger. Four gaps were surfaced Socratically and resolved with
the human (decisions below); no inconsistency halt was triggered.

**Decisions taken (human, 2026-06-16).**
1. **Writer-mode adopter-overlay namespace (REQ-A1.5 / D-3):** derive the
   `<name>` namespace segment from the plugin manifest `name` field in writer
   mode (`<claude-dir>/planwright/<name>/overlay/`), charset-validated. Does
   not contradict D-3's rejected uniform alternative (that rejection was about
   plugin mode, where `CLAUDE_PLUGIN_DATA` supplies the namespace free).
2. **Protected-doc shadow (REQ-B1.7):** warn-but-allow. Shadowing a protected
   core governance/security doc (`spec-format`, `security-posture`,
   `validation-rigor`, `discovery-rigor`, `finding-categorization`,
   `gate-wiring`) resolves but emits a loud stderr warning. New REQ-B1.7 + D-11.
   (`gate-wiring` added at the 2026-06-16 delta re-walkthrough; see the
   Amendment log below. D-11 remains the normative source.)
3. **Catalog supersede-by-id syntax (REQ-B1.3):** defined here in Task 5 (the
   overlay entry carries target id + supersede marker); bootstrap Task 16's
   builder consumes the contract. Guard-catalog *consumer wiring* is contingent
   on Task 16's catalog existing at Task 5 execution time (risk row R2); the
   merge mechanism and decision-domains consumer ship regardless.
4. **Bad `review_sequence` value (REQ-D1.3):** a name that is unknown or not a
   nestable review skill is treated as a malformed overlay value under the
   REQ-E1.4 by-layer policy.

**Consolidated spec-edit list (applied in place, Draft).**
- requirements.md: added REQ-B1.7 (protected-doc warning); refined REQ-D1.3
  (malformed bad-name clause); Changelog entry 2026-06-16.
- design.md: concretized D-3 (writer-mode manifest-name) + clarifying note on
  the rejected uniform alternative; extended D-5 (Task 5 owns supersede-by-id
  syntax; guard-catalog wiring contingency); added D-11 (warn-but-allow).
- test-spec.md: added REQ-B1.7 entry; extended REQ-D1.3 Gherkin with the
  malformed-name scenario.
- tasks.md: Task 2 (writer-mode manifest-name in deliverables/done-when);
  Task 4 (protected-doc warning + cite D-11/REQ-B1.7); Task 5 (pin
  supersede-by-id syntax + guard-catalog contingency); Task 6 (bad-name clause
  + cite REQ-E1.4).
- Re-validated after edits: 0 errors, 0 warnings; doc-links resolve.

Signed off: 2026-06-16

## 4. Design walkthrough

**Reconciled ledger (D-1…D-11).**

| D-ID | Status | Note |
| --- | --- | --- |
| D-1 Four-layer precedence model | Confirmed | 3-/2-layer rejections still hold (malformed-by-layer + machine-local doctrine need the team/machine split). |
| D-2 Kind-native, one precedence rule | Confirmed | No unified store; each kind reads its native path. |
| D-3 Adopter overlay home via `CLAUDE_PLUGIN_DATA` chain | Amended | Writer-mode namespace concretized to manifest `name`; clarified non-contradiction with the rejected uniform alternative. |
| D-4 Kind-native per-layer locations | Confirmed | No single overlay-root dir; disrupts no existing config path. |
| D-5 Per-kind merge semantics | Amended | Task 5 owns supersede-by-id syntax; guard-catalog wiring contingency noted. |
| D-6 `review_sequence` config list-knob | Confirmed | Default reproduces today's convergence (single-element default list). |
| D-7 Malformed-overlay policy by layer | Confirmed | degrade+warn vs hard-fail. |
| D-8 Doctrine-overlay path-traversal confinement | Confirmed | canonicalize-then-contain. |
| D-9 Provenance via per-resolver `--explain` | Confirmed | No aggregate tool in v1 (deferred). |
| D-10 Capability-vs-style boundary doctrine (new doc) | Confirmed | Own resolvable doc. |
| D-11 Warn-but-allow on protected-doc shadow | New (this kickoff) | Doctrine analogue of D-7's degrade+warn arm. |

**Reconciliations (no contradiction found).**
1. Dispatch-isolation is the *illustrative* core-capability example in the
   boundary doc, not a deliverable; only `review_sequence` ships as a knob
   (REQ-C1.3). Consistent with Out-of-scope's "no specific default changes."
2. D-11's warn-but-allow lets a fork shadow even `security-posture`; that is
   the fork's call and the warning surfaces it. No conflict with REQ-A1.3
   (no-fork applies to *adding overlays*) or REQ-E1.* (overlay *content*
   hygiene, not which docs may be shadowed).

No inconsistency halt triggered. Carried to the risk register: the
`$CLAUDE_PLUGIN_DATA`-semantics re-verification (D-3 cross-cutting note).

Signed off: 2026-06-16

## 5. Verification approach

**Coverage mix (24 REQs).** Predominantly `[test]` (portable shell unit tests
under `mise run check` / CI); `[design-level]` for the boundary doctrine doc,
adopter docs, and consumer audits (REQ-C group, B1.4, D1.2); two `[Gherkin]`
scenario sets (D1.3, E1.4); one `[manual]` (E1.1). Validator confirms every
REQ has ≥1 verification entry.

**Verification ownership.**
- `[test]` → repo CI gate `mise run check` (`test` under the bash 3.2 floor +
  `check:specs/options/links` + `scan:secrets` via gitleaks), every PR. The
  scripts Tasks 3 & 4 extend already have suites (`tests/test-config-get.sh`,
  `tests/test-resolve-rule-doc.sh`). Owner: CI.
- `[design-level]` → existence + coverage of the boundary/adopter docs and the
  "no skill hardcodes a single-layer read" audit; checked at PR review and this
  kickoff. Owner: PR reviewer.
- `[manual]` (E1.1) → reviewer sweep for secret-shaped content, backed by
  gitleaks for committed overlays. Owner: PR reviewer + `scan:secrets`.
- `[Gherkin]` → E1.4 realizes as shell tests (malformed-by-layer scenarios);
  D1.3 split below.

**Dead-path check.** No fully dead paths. One near-dead path corrected:
REQ-D1.3 was `[test + Gherkin]` but its behavioral half ("`/execute-task`
honors the ordering") is skill-driven and not unit-testable. Tightened to
`[test + Gherkin + manual]`: resolution stays `[test]` (via `config-get`); the
"runs in order" outcome is design-level (convergence-phase instructions read
the knob) + a one-time manual exercise (human decision, 2026-06-16). The
guard-catalog `[test]` (REQ-D1.1 / B1.3) is legitimately deferred until
bootstrap Task 16 exists (Task 5 contingency / risk R2), not dead.

Signed off: 2026-06-16

## 6. Task graph

Reconstructed from the authoritative `Dependencies:` lines (the intro
dependency view is derived and matches):

```
T1 (boundary doctrine, 0.5d) ──────────────── standalone
T2 (overlay-root primitive, 1d)
   ├──> T3 (4-layer config, 1d) ──> T6 (review_sequence, 1d) ──┐
   ├──> T4 (doctrine overlay, 1d) ─────────────────────────────┤
   └──> T5 (catalog overlay, 1d) ──────────────────────────────┤
                                                                └──> T7 (adopter docs, 0.5d)
```

**Effort-weighted critical path:** `T2 → T3 → T6 → T7` = 3.5 days. The T4 and
T5 branches (2.5d each) carry ~1 day of slack.

**Parallelism.** T1 runs anytime (independent). After T2, the three resolvers
T3/T4/T5 fan out 3-way in parallel (T1 alongside). T6 gates on T3 only; T7 is
the join of T3/T4/T5/T6. No cycles.

**Deliberate non-edges (recorded so nobody "fixes" them).**
- T4, T5 do not depend on T3 — the three resolvers are independent kinds
  (D-2 kind-native); each needs only the T2 primitive.
- T6 depends on T3 only — `review_sequence` is a *config* knob needing
  four-layer config resolution, not the doctrine/catalog resolvers.
- T1 depends on nothing — the capability-vs-style doctrine is prose; it
  describes `review_sequence` conceptually without the machinery or knob built.
- **T1 ↔ T7 independence is deliberate** (human, 2026-06-16): T1 is
  author-facing doctrine consumed by `/spec-draft`; T7 is adopter onboarding.
  Both carry the two worked examples; they can be authored in parallel and
  cross-referenced, with no blocking edge.

**Cross-spec note (not an intra-spec edge).** Task 5's guard-catalog *consumer
wiring* depends on bootstrap Task 16's guard catalog existing at execution time
(risk R2). This is a soft cross-spec contingency, not a dependency edge in this
bundle's graph; the merge mechanism and decision-domains consumer ship
regardless.

Signed off: 2026-06-16

## 7. Risk register

**Decision-domains gap check** (all 10 catalog domains walked). Touched and
decided: 1 storage (D-4), 6 secrets/config (REQ-E1.1/E1.3), 8 observability
(D-9). Touched with a residual risk: 4 API surface (R6), 9 deploy/migration
(R4), 10 dependency/parsing (R5). Not crossed (n/a): 2 caching, 3 queues,
5 auth, 7 concurrency.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| R1 | `$CLAUDE_PLUGIN_DATA` semantics drift — D-3 leans on 2026-06-11 research; plugin format actively evolving. | Re-verify path + persistence semantics vs current Claude Code docs at Task 2; `$PLANWRIGHT_ADOPTER_OVERLAY` override arm is the fallback. |
| R2 | Guard-catalog consumer wiring depends on bootstrap T16 (In progress; catalog absent here). | Task 5 ships merge mechanism + decision-domains consumer unconditionally; guard-catalog wiring defers if absent. Signal: check T16 merge state at Task 5 dispatch. |
| R3 | Protected-doc set (D-11) maintenance — hardcoded list; renamed/new core docs fall out of protection silently. | Keep the set in one named place cross-referenced from D-11; REQ-B1.7 test asserts each named protected doc exists. |
| R4 | Existing two-layer callers regress when no overlay present. | REQ-B1.1 no-regression clause; existing `tests/test-config-get.sh` / `test-resolve-rule-doc.sh` stay green; REQ-A1.4 absent-layer tests cover the default path. |
| R5 | Catalog entry format vs dependency-free portable-shell / bash-3.2 floor. | Pin a line-oriented/simple catalog entry format at Task 5; verify under the bash-3.2 test floor. |
| R6 | `--explain` output is an unpinned contract humans/skills parse. | Pin a stable documented line format at Tasks 3/4/5; fold into options/adopter docs (REQ-E1.3). |
| R7 | Manual verification of D1.3 ordering may be skipped. | Tagged `[manual]` + Task 6 done-when "ordering scenario verified"; named PR-checklist item. |
| R8 | Security surface — resolvers parse overlay files and derive paths from untrusted repo-tracked overlays. | Focused security pass at Tasks 2/3/4/5: canonicalize-then-contain (D-8), identifier charset validation (REQ-E1.2), no eval of parsed data. |
| R9 | Uncommitted overlays (adopter, machine-local) carry no secret-scanner coverage — gitleaks scans committed files only. | Accepted residual: the data-hygiene rule is the guard there; Task 7 adopter docs carry an explicit warning (added at lens pass). Added 2026-06-16. |

All rows are mitigated or accepted with an early signal; no open question
remains. Human cold-review (2026-06-16): register complete as drafted, no
additions. R9 added at the sign-off lens pass (uncommitted-overlay secret
surface).

Signed off: 2026-06-16

## 8. Sign-off — lens review pass

**Scope:** full bundle (first activation). **Path:** parallel fan-out, 9
read-only sub-agents (one per canonical lens; the perf/concurrency lenses
shared one agent), per `discovery-rigor`. **Class:** meaning (first
activation). Findings validated per `validation-rigor` (three independent
passes, with an explicit adversarial re-validation over BOTH the keep set and
the decline set at the human's request — that pass flipped F7 keep→decline and
upgraded F9/F10/F11 decline→keep).

**Lens-coverage table:**

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 2 | F1 "nestable" undefined; F2 fragment-merge class mismatch. Edge cases (supersede target, etc.) → Task 5 / F10. |
| Security | 1 | F3/R9 uncommitted-overlay secret surface. Path-TOCTOU, YAML-deser declined (config has no deserializer; R8 + framework-script posture cover the rest). |
| Error handling and failure modes | 1 | F4 define "malformed" (covers unreadable/permission). Exit-code/multi-malformed declined as impl-time under D-7. |
| Performance | none | No-cache is deliberate (fresh-per-call, no staleness); matches existing config-get; not a hot path (proportionality). |
| Concurrency / state | none | Read-only resolvers over operator-edited config; concurrent-write/TOCTOU not a realistic threat at this layer. |
| Naming, readability, structure | 1 | F5 terminology (repo-tracked / guard catalog) + REQ-A1.6 file-name symmetry. |
| Documentation | 1 | F6 protected-doc canonical home (D-11). `--explain`/supersede-syntax/Task-19 are recorded risks, not gaps. D-3-changelog "omission" = false positive. |
| Tests / verification | 1 | F11 doctrine-determinism note. F7 ("REQ-B1.2 vacuous") = FALSE POSITIVE (positive assertion already present). options-reference completeness decline confirmed (script exits 1). |
| Cross-file consistency | 1 | F2/F8 (Out-of-scope divergence = the fragment-merge item). All ID/citation cross-refs verified consistent. |

**Dispositions — applied as spec edits (9):**
- F1 — defined "nestable" review skill (`--nested`-invocable) in REQ-D1.3.
- F2 (+F8) — reclassified doctrine fragment/section merge from a permanent
  Out-of-scope exclusion to Deferred-gated (requirements.md), resolving the
  requirements-vs-tasks divergence.
- F3 — added uncommitted-overlay secret warning to Task 7 + risk R9.
- F4 — defined "malformed" (unreadable / unparseable for the kind) in REQ-E1.4.
- F5 — named the team file `planwright.yml` (REQ-A1.6); standardized "guard
  catalog" (REQ-B1.3).
- F6 — made D-11 the normative source of the protected-doc set; REQ-B1.7
  references it; the REQ-B1.7 test asserts each protected doc resolves (R3).
- F9 — absent/unresolvable writer-mode namespace → adopter layer absent,
  degrade per REQ-A1.4 (REQ-A1.5, D-3).
- F10 — Task 5 must pin supersede-of-nonexistent-target behavior.
- F11 — noted doctrine's exclusion from the determinism test (test-spec B1.5).

**Dispositions — declined with rationale:**
- F7 (REQ-B1.2 test vacuous) — false positive; the entry already asserts the
  resolved path is the overlay doc in full.
- D-3-changelog omission, options-reference completeness — false positives
  (D-3 is cited; the script exits 1 on undocumented options).
- Performance (6), concurrency/TOCTOU (7) — declined: no-cache is deliberate,
  resolvers read-only over operator-edited config, not a hot path; the genuine
  path-confinement TOCTOU is impl-time under R8.
- YAML-deserialization, config-value metacharacters — declined: config-get is
  a line-oriented reader (no deserializer); framework-script "data≠code, no
  eval" + R8 cover catalog/doctrine parsing.
- Exit-code uniformity, `--explain` format, supersede-by-id syntax body,
  Task-19 handoff detail — declined as task-execution-time (recorded as R6 /
  Task 5 / Task 7 deliverables, not spec gaps).
- Namespace-stability/plugin-rename — folded into R1. Boundary-doctrine
  "no teeth" — declined: doctrine is advisory-at-decision-time by design;
  design-level verification is correct.

All findings dispositioned; none left open. Bundle re-validated after the
lens-pass edits: 0 errors, 0 warnings; doc-links resolve; markdownlint 0.

**Sign-off record (first activation).** Status flipped Draft→Active and
`Last reviewed:` set to 2026-06-16 on all four spec files; validator re-run
under Active enforcement: 0 errors, 0 warnings. Validator present and clean;
no degradation. commit_on_kickoff = true.

Class: meaning
Lens-pass: recorded above (this section), findings dispositioned 2026-06-16.
Anchor: `8ad2842279bb146b78a67d61923a581b2aebc04c` — computed as
`scripts/spec-anchor.sh specs/customization-overlay`

Signed off: 2026-06-16

## 9. Amendment log

### Amendment — protected-doc set + anchor reconcile (delta re-walkthrough, 2026-06-16)

**Mode:** delta re-walkthrough (Active spec; human-declared amendment).

**Triggers:**
1. **Freshness-gate mismatch.** The §8 kickoff anchor
   (`8ad2842…`) had gone stale: five post-activation commits (`1c33c87`,
   `610387a`, `49de44c`, `31cb0da`, `d8a8c51` — panel-review / panel-pairing
   refinements: D-3 writer-mode manifest source, D-4 `doctrine.local` /
   `catalogs.local` collision split, REQ-E1.4 reword to admit list-valued
   options, four added REQ→task citations, brief cross-ref fixes) committed
   without re-anchoring the brief. The current bundle hashed to `433def6b…`.
2. **Human-declared change.** Add `gate-wiring` to the D-11 protected-doc set
   (surfaced by a `/self-review` pass: gate-wiring is the operational twin of
   the already-protected `finding-categorization`).

**Class:** meaning (addition to the protected set).

**Delta-scoped lens pass (inline).** The new delta is a two-site addition of
one doc name plus its boundary rationale — small and narrow per
`discovery-rigor`, so walked inline. The accumulated panel edits were already
lens-reviewed in their own panel passes and re-validated clean by the
immediately-prior `/self-review` fan-out (traceability + cross-file
consistency), so they are *reconciled* into the fresh anchor, not
re-litigated.

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | none | `gate-wiring` resolves via `resolve-rule-doc.sh`; adding it creates no conflict. |
| Security | none | The addition tightens, not loosens, the shadow-warning surface. |
| Error handling / failure modes | none | warn-but-allow semantics unchanged. |
| Performance | n/a | prose. |
| Concurrency / state | n/a | prose. |
| Naming, readability, structure | none | doc name `gate-wiring` matches the resolver target. |
| Documentation | 1 (applied) | Stated the D-11 set boundary (guarantee-removing docs in; advisory/methodology docs — `research-rigor`, `proportionality`, `refactor-instinct` — out) so the in/out line is principled and not re-flagged next pass. |
| Tests / verification | none | test-spec REQ-B1.7 iterates "the normative D-11 protected-doc list" and asserts each resolves — it now covers `gate-wiring` automatically; no test-spec edit needed; validator 0/0. |
| Cross-file consistency | none | D-11 (normative) and REQ-B1.7 (mirror) both updated; test-spec auto-tracks the list. |

**Dispositions:**
- **Applied:** added `gate-wiring` to D-11's protected set and REQ-B1.7's
  mirror list; stated the set boundary in D-11; Changelog entry added; both
  amended records carry the in-place amendment annotation.
- **Declined with rationale (held out):** `research-rigor` — an advisory
  ladder methodology, not a doc whose silent shadow removes a framework
  guarantee; including it (and the other rigor docs) would dilute the warning
  signal. Re-raisable: the boundary is now documented in D-11, so the line is
  principled rather than arbitrary.

**Validator (Active enforcement) after edits:** 0 errors, 0 warnings;
doc-links resolve (69/69); markdownlint 0; options documented.

**Observation logged** (not acted on here): the panel-* skills applied
post-activation bundle edits and committed them without re-anchoring the
brief, which left the freshness gate stale until this pass. Seed for
`/spec-draft`.

Class: meaning
Lens-pass: recorded above (this section), findings dispositioned 2026-06-16.
Anchor: `7db415d9e61f671fd11d473a04ebb2aab96425cd` — computed as
`scripts/spec-anchor.sh specs/customization-overlay`

Signed off: 2026-06-16

### Amendment — expression-only re-anchor (D-11 mirror wording, 2026-06-16)

**Mode:** delta re-walkthrough (Active spec; freshness-gate mismatch). The
prior anchor (`7db415d9…`) had gone stale: two post-activation
`chore(copilot)` commits landed after the gate-wiring amendment re-anchored
the brief —

1. `fa4410e` — **design.md (spec content):** reworded D-11's account of its
   relationship to REQ-B1.7 (from "REQ-B1.7 references it rather than
   re-listing it authoritatively" to "REQ-B1.7 mirrors it for readability
   while deferring to D-11 as the authoritative source; its inline copy tracks
   D-11, never supersedes it"). This is the only spec-file change since the
   prior anchor and is what moved the bundle hash.
2. `e339277` — **brief only:** added `gate-wiring` to §3 "Decisions taken"
   item 2's protected-set list, with a cross-reference to this Amendment log.
   A brief-internal consistency fix mirroring the gate-wiring amendment above;
   the brief is not part of the anchor, so this commit did not move it.

**Class:** expression-only. The reword makes the D-11 ↔ REQ-B1.7 mirror
relationship explicit; the normative contract (D-11 is the single source of
the protected set, REQ-B1.7 a non-authoritative mirror) is unchanged. The
human classified the delta expression-only at sign-off (2026-06-16).

**Compliance note (the trigger for this run).** The `fa4410e` reword committed
without a changelog entry and without re-anchoring the brief — the same drift
pattern the prior amendment's observation already flagged. Content was
compliant throughout (D-11 and REQ-B1.7 carry the identical six-doc protected
set — `spec-format`, `security-posture`, `validation-rigor`, `discovery-rigor`,
`finding-categorization`, `gate-wiring` — and B1.7 defers to D-11 as
normative; validator 0/0). This entry closes the process gap: a dated
changelog line was added and the anchor reconciled.

**No lens pass** (expression-only, per REQ-A3.3): the contract is unchanged, so
the bundle is reconciled rather than re-reviewed. Cross-file consistency was
spot-checked during pre-flight (D-11's six-doc set == REQ-B1.7's mirror; B1.7
defers to D-11). Validator (Active enforcement) after the changelog edit:
0 errors, 0 warnings.

Class: expression-only
Changelog: requirements.md `## Changelog` entry dated 2026-06-16
("Expression-only wording fix … reworded D-11's account of its relationship to
REQ-B1.7").
Anchor: `69b89ff1f4119d9e5b08b79c7f1a6edd088c4e02` — computed as
`scripts/spec-anchor.sh specs/customization-overlay`

Signed off: 2026-06-16
