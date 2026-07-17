# Instruction-budget headroom — Requirements

**Status:** Draft
**Last reviewed:** 2026-07-16
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

prompt-hygiene built the measurement and the guard: word budgets over every
instruction surface, enforced by `scripts/check-instructions.sh` in CI.
Landing features under that guard has saturated the guarded surfaces — the
2026-07-16 audit shows the orchestrate reachable closure at 19,997/20,000,
the execute-task body at 4,248/4,250, the spec-kickoff body at 4,243/4,250,
and the /self-review start-load at 9,993/10,000 — so the guard now blocks
required doctrine growth instead of bounding bloat: two required additions
have already been reverted or force-trimmed purely for budget reasons. This
spec (a) establishes the standing headroom policy the guard lacks: margin
floors below each error threshold and a decision ladder — diet, point-of-use
reclassification, budget raise, exemption — with the conditions under which
each rung applies; (b) executes the restoration passes that bring every
policy-flagged surface back within margin; (c) decides the structural
question the exemption mechanism left open: the per-file-exempt meta-spec
still charges every dependent skill's aggregates in full, and aggregate
budgets cannot be relieved by reclassification; and (d) closes the
check-instructions tooling gaps that make headroom work unverifiable. The
altitude of each deliverable — policy as doctrine, enforcement as core
capability, trims as repo-local instantiation — is recorded in D-1.
*(Cites: D-1, the mission seed (Sources), obs:fd250fb5, obs:bfe73da9.)*

## Scope

### In scope

- The standing headroom policy as doctrine (an amendment to
  `doctrine/instruction-hygiene.md`): floors, restoration targets, the
  restoration ladder, and rung-entry conditions.
- Restoration passes over every surface the policy flags at the floors
  chosen in REQ-A1.1 (at drafting time: the execute-task, spec-kickoff, and
  orchestrate bodies; the self-review, polish, and execute-task start-loads;
  the orchestrate closure).
- The exempt-doc aggregate-coupling decision (`doctrine/spec-format.md`
  today, and any future permanently per-file-exempt doc).
- check-instructions tooling: margin reporting, floor-breach findings, the
  pending-diet Task field in audit output, the reverse point-of-use use-site
  check, offender-shortlist test expectations derived from the suppression
  list, and the stale exemption-rationale text.
- Diet-pass operational discipline (unbroken grepped phrases, content-pinned
  tests in the same PR, the meaning-inversion hazard) encoded in the diet
  tasks' definitions.
- Re-landing the reverted `migrate-format-version.sh` guidance in
  `doctrine/spec-format.md` once closure margin permits.

### Out of scope

- Authoring the format-grammar spec's meta-spec wording changes (that
  sibling spec spends the headroom this one creates; its fragment 94f03e6c
  stays unconsumed here).
- Changing the measurement unit (words stay words), the prompt-eval harness,
  or the guard's basic architecture (plain POSIX shell, data-only inputs).
- Deferring gating law to hit a number: the instruction-hygiene safety floor
  is inviolable in every reclassification.
- Silent meaning changes during diets: law moves verbatim in meaning, never
  silently weakened.

## REQ-A — Standing headroom policy

- **REQ-A1.1** `doctrine/instruction-hygiene.md` SHALL define a headroom
  floor per budgeted surface class — SKILL.md body, rule doc,
  mandatory-at-start, reachable closure — as a minimum word margin below the
  class's error threshold, with core default values 250 / 250 / 500 / 1,000
  carried as overlay-tunable knobs in `config/defaults.yml`. A surface whose
  margin is below its floor is in breach and SHALL trigger the restoration
  ladder.
  *(Cites: D-2, obs:fd250fb5, obs:dd48dace, obs:c5c3eb2c, obs:094e588c,
  obs:36fa1662.)*
- **REQ-A1.2** The policy SHALL define the restoration ladder with
  rung-entry conditions, in order: (1) diet, (2) point-of-use
  reclassification, (3) deliberate budget raise, (4) exemption. Escalation
  to a rung SHALL require the prior rung to be exhausted or inapplicable,
  with the inapplicability recorded.
  *(Cites: D-5.)*
- **REQ-A1.3** No ladder rung SHALL defer gating law (the
  instruction-hygiene safety floor); a surface that cannot restore margin
  without deferring gating law SHALL escalate to the human instead.
  *(Cites: D-5, prompt-hygiene (Sources).)*
- **REQ-A1.4** Budget raises and exemptions SHALL carry a recorded rationale
  in the configuration that sets them; a silent raise or reason-less entry
  SHALL be a guard error.
  *(Cites: D-5, prompt-hygiene (Sources).)*
- **REQ-A1.5** A restoration pass SHALL aim for a restoration target of
  twice the surface's floor, so a restored surface absorbs routine doctrine
  growth (the observed 80–560-word range) before breaching again; a surface
  that cannot reach its target without deferring gating law SHALL record a
  declared exception instead.
  *(Cites: D-3, obs:bfe73da9.)*

## REQ-B — Exempt-doc aggregate coupling

- **REQ-B1.1** Aggregate enforcement (mandatory-at-start and reachable
  closure) SHALL charge a permanently per-file-exempt doc at
  min(actual words, that doc's per-file error threshold), so dependents of a
  sanctioned over-floor doc can absorb its bounded growth without per-edit
  budget ceremony.
  *(Cites: D-4, obs:bfe73da9, obs:92cd453e.)*
- **REQ-B1.2** Any aggregate-relief mechanism SHALL keep measurement honest:
  the full word counts are still computed and reported alongside the charged
  values; only the enforcement comparison changes.
  *(Cites: D-4.)*

## REQ-C — Restoration passes

- **REQ-C1.1** After this spec's restoration tasks, every budgeted surface
  SHALL meet its floor with margin at or above its restoration target,
  verified from the guard's margin report on the real corpus in CI.
  *(Cites: D-6, obs:fd250fb5, obs:dd48dace.)*
- **REQ-C1.2** Diets SHALL preserve law verbatim in meaning and SHALL run
  the content-pinned structural tests in the same PR; pinned lists and
  grepped phrases stay unbroken on one line.
  *(Cites: D-10, obs:381021a7.)*
- **REQ-C1.3** Reclassifications SHALL respect the safety floor with a
  recorded analysis, update the doctrine manifest, and name the reclassified
  doc at its in-body use site.
  *(Cites: D-6, obs:38878e99.)*
- **REQ-C1.4** The reverted `migrate-format-version.sh` guidance SHALL be
  re-landed in `doctrine/spec-format.md`'s versioning section once the
  dependent closures' restored margin absorbs it.
  *(Cites: D-9, obs:92cd453e.)*

## REQ-D — Guard tooling

- **REQ-D1.1** `check-instructions --audit` SHALL report each surface's
  margin to its warn and error thresholds, and every guard run SHALL emit a
  named floor-breach warning (never an error) when a surface's margin is
  below its floor.
  *(Cites: D-2, D-8.)*
- **REQ-D1.2** The audit shortlist and ranked report SHALL include each
  pending-diet allowance's Task field, so a Task retag is visible to the
  test surface.
  *(Cites: D-8, obs:002ebf4a.)*
- **REQ-D1.3** The guard SHALL check the reverse direction of doctrine
  manifests: every point-of-use doc named at some in-body step; a missing
  use-site naming SHALL be a warning.
  *(Cites: D-7, obs:38878e99.)*
- **REQ-D1.4** The guard test suite's real-corpus offender-shortlist
  expectations SHALL derive from the suppression list rather than hardcoded
  file names.
  *(Cites: D-8, obs:c5a95acf.)*
- **REQ-D1.5** The spec-format exemption rationale SHALL be corrected to
  drop the superseded "dominant run-start load" claim and to state the
  capped-charge semantics.
  *(Cites: D-4, obs:9faf6a79.)*

## Changelog

- 2026-07-16 — Bundle drafted via `/spec-draft` (fold-detection ran against
  all thirteen existing specs; overlap with prompt-hygiene resolved as a new
  spec citing it, per the drafting-session decision recorded in Sources).

## Sources

- **The mission seed** — the `/spec-draft instruction-headroom` invocation
  (2026-07-16): the saturation numbers, the policy/diet/tooling triple
  mandate, the fold-fork and sibling-coordination notes. A same-day
  full-accumulator triage (10-agent verification against v0.14.1) confirmed
  every consumed fragment below still valid.
- **Pinned altitude claims** — three seeds assert the deliverable's nature
  is a standing policy, not a one-off trim: obs:fd250fb5 ("consider a small
  standing headroom budget"), obs:36fa1662 ("a deliberate margin policy is
  seed material"), obs:bfe73da9 ("a real policy decision is needed here, not
  just a trim"). Resolved as D-1.
- **specs/prompt-hygiene** (Done) — owns the budget guard, the budgets, the
  suppression-list grammar, and the original diet passes; this spec extends
  its guard and cites its REQ/Task numbers namespace-qualified.
- **Consumed observation fragments** — obs:fd250fb5, obs:c5c3eb2c,
  obs:dd48dace, obs:094e588c, obs:36fa1662, obs:bfe73da9, obs:92cd453e,
  obs:002ebf4a, obs:38878e99, obs:c5a95acf, obs:9faf6a79, obs:381021a7.
- **The 2026-07-16 audit** — `check-instructions --audit` on main at
  v0.14.1, the ground truth for every margin figure in this bundle.
- **Drafting-session decisions (2026-07-16)** — new-spec-over-extend at the
  fold fork; this spec owns the obs:92cd453e re-land; floor sizing, breach
  severity, coupling mechanism, restoration target, and the research-rigor
  reclassification, each taken as a recorded selector answer during
  elicitation.
