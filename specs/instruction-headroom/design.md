# Instruction-budget headroom — Design

**Status:** Draft
**Last reviewed:** 2026-07-16
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new decision minted in this bundle's drafting session
(2026-07-16). Foreign IDs are namespace-qualified.

## Decision log

### D-1: Altitude — policy in doctrine, mechanism in the guard, trims as instantiation  (N)

**Decision:** The deliverable splits across three altitudes: the headroom
policy (floors, restoration targets, the ladder, capped-charge law) is
**doctrine**, landing as an instruction-hygiene amendment; its enforcement
(floor knobs, margin reporting, capped charge, the reverse use-site check)
is **core capability** in `check-instructions.sh` with overlay-tunable
knobs; the restoration passes over today's saturated surfaces are
**repo-local instantiation** tasks. Cited from the bundle's goal per the
autopilot-reflex trigger-scoped altitude record.

**Alternatives considered:**
- A one-off trim campaign with no policy. Rejected because: three pinned
  seed claims (obs:fd250fb5, obs:36fa1662, obs:bfe73da9) independently
  assert the gap is a missing standing policy; trims alone reproduce
  today's saturation at the next growth spurt.
- Policy expressed only in guard code and config comments. Rejected
  because: doctrine buried in a script is invisible (autopilot-reflex step
  5); the ladder is a rule about how to think, owned by the framework.

**Chosen because:** the altitude triggers fired during seed gathering, and
right-altitude placement puts the durable reasoning where skills and humans
read law, the mechanical enforcement where it cannot be pencil-whipped, and
the disposable trims in tasks.

### D-2: Headroom floors as core knobs, breach is a named warning  (N)

**Decision:** Four floor knobs in `config/defaults.yml` — SKILL.md body
250, rule doc 250, mandatory-at-start 500, reachable closure 1,000 (about
5% of each error threshold, rounded) — overlay-tunable like the existing
`instruction_budget_*` knobs. A surface whose margin to its error threshold
is below its floor produces a **named warning** on every guard run; the
error thresholds themselves are unchanged.

**Alternatives considered:**
- Lean floors (100/100/250/500). Rejected because: observed routine
  doctrine additions run 80–560 words, so a sub-250 margin cannot absorb
  even one addition; the two ~350–400-margin start-loads would stay one
  medium addition from breach.
- A percentage rule evaluated at runtime. Rejected because: less legible
  round numbers in guard output for no added protection at today's fixed
  thresholds.
- Breach as a CI error, or an error after a grace period. Rejected because:
  an error would recreate the exact blocking problem this spec fixes, and
  grace-period state does not belong in a dependency-free shell guard.

**Chosen because:** 5%-scale floors make erosion visible a full addition
before the hard wall, and a warning surfaces in every check run without
blocking unrelated PRs; the drain path is an observation fragment plus a
restoration chore.

### D-3: Restoration target is twice the floor  (N)

**Decision:** A restoration pass aims for margin ≥ 2× the surface's floor
(500/500/1,000/2,000). A surface that cannot reach its target without
deferring gating law records a declared exception instead.

**Alternatives considered:**
- Restore to the bare floor. Rejected because: the next 100-word addition
  on a 250-margin body re-breaches immediately, making the ladder a
  recurring ceremony.
- Floor + 560 (largest observed addition) everywhere. Rejected because: it
  forces disproportionately deep body diets (~810-word margins), while a
  >500-word body addition should bring its own diet anyway.

**Chosen because:** one large routine addition fits within the start-load
and closure targets with room to spare, and the drafting-session math
showed 2× targets attainable with rung-1/rung-2 means alone.

### D-4: Capped charge for permanently exempt docs, on all aggregates  (N)

**Decision:** Aggregate enforcement (start-load and closure) charges a
permanently per-file-exempt doc at min(actual words, its per-file error
threshold): `spec-format.md` charges 4,000, not 5,125. Actual words are
still computed and printed alongside the charged value (charged-vs-actual),
and non-exempt docs stay fully charged. The exemption-file rationale is
rewritten to state these semantics, dropping the superseded "dominant
run-start load" claim (obs:9faf6a79).

**Alternatives considered:**
- Capping closure only, start-load keeping full weight. Rejected because:
  `spec-format.md` is run-start **gating law** for /execute-task (the
  freshness gate), unreclassifiable by the safety floor, so only a ~1,200-
  word body diet could restore that start-load — a brutality the cap
  resolves on principle instead.
- Raising the closure and start-load budgets. Rejected because: it licenses
  bloat for every skill, not just exempt-doc dependents, eroding the
  research-grounded ceilings, and the wall returns at the next growth
  spurt with no mechanism.
- Zero-charging exempt docs in aggregates. Rejected because: the words
  still hit the model's context; hiding the entire load breaks REQ-B1.2's
  honesty requirement.
- Splitting `spec-format.md` (v1 law into a sibling doc). Rejected because:
  the meta-spec's structure is the sibling format-grammar spec's territory,
  and the authorable-from-alone contract resists a split taken purely for
  budget relief.

**Chosen because:** the cap is the same number the per-file budget already
calls the doc's sanctioned maximum — growth beyond it was accepted by the
standing exemption — so dependents pay the budgeted size while the overage
stays visible on the exempt doc's own audit line.

### D-5: Restoration-ladder rung conditions  (N)

**Decision:** The ladder is ordered diet → point-of-use reclassification →
deliberate budget raise → exemption. Rung entry conditions: reclassification
requires the diet to be exhausted (no trimmable non-law prose remains) or
disproportionate, and never moves gating law; a raise requires both prior
rungs exhausted or inapplicable, applies to a named budget with a recorded
rationale, and is never silent; exemption is per-file-floor only, permanent,
with a standing rationale. Every escalation records why the prior rung was
insufficient.

**Alternatives considered:**
- An unordered menu of options chosen case by case. Rejected because:
  unordered options invite reaching straight for the raise, the rung that
  erodes the budgets' purpose.
- Making raises forbidden outright. Rejected because: a legitimate corpus
  change (a new mandatory doctrine class) may someday warrant one; the
  discipline is recorded rationale, not prohibition.

**Chosen because:** the ordering encodes the cheapest-honest-fix-first
principle, and recorded inapplicability keeps the ladder auditable.

### D-6: The restoration plan for today's breaches  (N)

**Decision:** At the D-2 floors, today's breach list and rung assignments:
gate-wiring.md diet (~500 words, also clearing its own per-file warn;
relieves the self-review and polish start-loads and the orchestrate and
execute-task closures); execute-task, spec-kickoff, and orchestrate body
diets (~450–500 words each, to ≤3,750); research-rigor reclassified
run-start → point-of-use in self-review and polish (491 words each; site:
the finding-validation step where its triggers fire); the D-4 cap resolving
the remainder (orchestrate closure, execute-task start-load and closure).
Small body trims top up any surface left between floor and target.

**Alternatives considered:**
- Diets alone, no cap and no reclassification. Rejected because: the
  orchestrate closure would need ~2,000 words trimmed from members that are
  mostly law, and execute-task's start-load ~1,200 from its body.
- Reclassifying refactor-instinct too. Rejected because: its review-mode
  bar shapes what discovery flags, and discovery begins immediately at
  run — a point-of-use read at that step is run-start in all but name.

**Chosen because:** research-rigor is trigger-fired law with an existing
point-of-use precedent in execute-task, satisfying the safety floor, and
the combination reaches every 2× target with rung-1/rung-2 means.

### D-7: Reverse use-site check at warning severity  (N)

**Decision:** The guard verifies, per skill, that every point-of-use
manifest doc is named somewhere in the body prose outside the manifest
block and fenced code; a miss is a warning naming the skill and doc.

**Alternatives considered:**
- Error severity. Rejected because: the check is new against an existing
  corpus and a completeness lint, not a safety gate; promotion to error
  stays open once the corpus is proven clean.
- Leaving site notes parser-ignored with no check. Rejected because: that
  is the tooling gap obs:38878e99 records — a point-of-use doc named
  nowhere in the body is a read that never happens.

**Chosen because:** warning severity closes the gap visibly without
blocking, matching D-2's breach posture.

### D-8: Audit output — margin columns, Task field, derived expectations  (N)

**Decision:** `--audit` gains per-surface margin-to-warn and
margin-to-error columns and charged-vs-actual for capped docs; the offender
shortlist and ranked report print each pending-diet allowance's Task field;
the guard test suite's real-corpus shortlist expectations derive from the
suppression list instead of hardcoded names.

**Alternatives considered:**
- A separate `--headroom` subcommand. Rejected because: margins belong next
  to the words they qualify; a second report drifts from the first.
- Keeping hardcoded section-0 expectations. Rejected because: every diet
  task then edits the test's name list in the same PR (obs:c5a95acf), a
  recurring coupling with no informational value.

**Chosen because:** one report stays the single reading surface, and
derived expectations make the test track the config that defines the
corpus's sanctioned state.

### D-9: Re-land sequencing for the reverted guidance  (N)

**Decision:** The ~80-word `migrate-format-version.sh` guidance
(obs:92cd453e) is re-landed in `spec-format.md`'s versioning section by the
closing task, after the cap and diets restore closure margin, and verified
by a green guard run.

**Alternatives considered:**
- Leaving the re-land to the format-grammar spec. Rejected because: the
  content is unrelated to that spec's ordering-wording concern, and a
  consumed fragment with no named owner stays lost (drafting-session
  decision, 2026-07-16).
- Re-landing early under a pending-diet allowance. Rejected because:
  allowances are transitional cover for offenders, not credit for planned
  work; landing into restored margin needs no ceremony.

**Chosen because:** late sequencing needs no allowance and shrinks the
merge-conflict window with the sibling spec's `spec-format.md` edits to one
small, final change.

### D-10: Diet-pass discipline  (N)

**Decision:** Every diet task's definition carries the obs:381021a7
discipline: pinned lists and grepped phrases stay unbroken on one line;
the content-pinned structural tests (`tests/test-*.sh` that grep skill
bodies) run in the same PR; condensation is checked against the governing
REQ/D text for meaning inversion; law moves verbatim in meaning.

**Alternatives considered:**
- Encoding the discipline as new instruction-hygiene prose. Rejected
  because: it is operational technique for a bounded campaign, not standing
  law; doctrine words are exactly the budget this spec conserves.
- Relying on reviewers to remember it. Rejected because: obs:381021a7
  records two silent failure modes (a wrap-broken grep, an inverted
  contract sentence) that review missed until tests caught them.

**Chosen because:** the tasks are where the discipline is exercised, and
Done-when conditions make it checkable per PR.

## Cross-cutting concerns

- **Decision-domains walk (merged catalog, 2026-07-16):** of the eleven
  domains, `api-surface` is touched (the guard's parsed audit output; the
  derived-expectations decision D-8 owns the compatibility story) and
  `secrets-config` (new knobs in `config/defaults.yml`, decided in D-2). No
  stake-bearing domain is left undecided; no new dependency enters (the
  guard stays plain POSIX shell, so the dependency-adoption checklist does
  not fire).
- **Sibling coordination:** the format-grammar spec (drafting concurrently)
  will add meta-spec wording; this bundle's cap plus targets are sized so a
  ~560-word addition to `spec-format.md` charges nothing further to
  dependents (already above the cap) and its own exempt audit line carries
  the visibility. Its fragment 94f03e6c is deliberately not consumed here.
- **Customization boundary:** floors and the cap are core capability
  (knobs and mechanism); the chosen values ship as core defaults in the
  same file and pattern as the existing budget knobs, overridable per
  overlay layer.
