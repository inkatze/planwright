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
  the orchestrate and execute-task closures).
- The exempt-doc aggregate-coupling decision (`doctrine/spec-format.md`
  today, and any future permanently per-file-exempt doc).
- check-instructions tooling: margin reporting, floor-breach and
  below-target findings with declared-exception entries, raise-rationale
  enforcement, the pending-diet Task field in audit output, the reverse
  point-of-use use-site check, offender-shortlist test expectations derived
  from the suppression list, and the stale exemption-rationale text.
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
  class's error threshold ("margin" unqualified in this bundle always means
  margin-to-error; the warn-threshold distance is named margin-to-warn),
  with core default values 250 / 250 / 500 / 1,000 carried as
  overlay-tunable knobs in `config/defaults.yml` named
  `instruction_budget_<skill|doctrine|startload|closure>_floor`, mapping
  one-to-one to the four classes in the order listed. A surface whose margin
  is strictly below its headroom floor (margin equal to the floor is
  compliant) is in breach and SHALL trigger the restoration ladder.
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
  without deferring gating law SHALL escalate to the human instead. The two
  backstops divide by depth: below its headroom floor and blocked ⇒ human
  escalation (this requirement); at or above its floor but unable to reach
  its restoration target ⇒ a declared exception (REQ-A1.5).
  *(Cites: D-5, prompt-hygiene (Sources), kickoff lens pass (2026-07-17).)*
- **REQ-A1.4** Budget raises and exemptions SHALL carry a recorded
  rationale: for a raise, a `raise|<knob>|<value>|<reason>` suppression-list
  entry (D-12) matching the raised knob's effective value. An effective
  `instruction_budget_*_warn` or `instruction_budget_*_error` value above
  its shipped core default with no matching entry (a silent raise), a
  reason-less entry of any form, an absent or unreadable core-default
  baseline, or a stale `raise|` entry (one whose knob is at or below its
  core default, or unknown — removed by the change that un-raises the
  knob, mirroring the pending-diet ownership rule) SHALL be a guard error
  (fail-closed). Floor knobs are protective and outside the raise rule.
  *(Cites: D-5, D-12, prompt-hygiene (Sources).)*
- **REQ-A1.5** A restoration pass SHALL aim for a restoration target of
  twice the surface's headroom floor, so a restored surface absorbs
  floor-many words of routine growth before re-breaching (the closure class
  absorbs the full observed 80–560-word addition range; smaller classes
  absorb their floor, and a >500-word body addition brings its own diet); a
  surface that cannot reach its target without deferring gating law SHALL
  record a declared exception instead (a `declared-exception` entry per
  D-11, machine-checked via REQ-D1.6).
  *(Cites: D-3, D-11, obs:bfe73da9.)*

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
  SHALL have margin at or above its restoration target or carry a declared
  exception per REQ-A1.5, verified from the guard's margin report and
  below-target warnings (REQ-D1.6) on the real corpus in CI.
  *(Cites: D-6, D-11, obs:fd250fb5, obs:dd48dace, kickoff §3
  (2026-07-16).)*
- **REQ-C1.2** Diets SHALL preserve law verbatim in meaning and SHALL run
  the content-pinned structural tests in the same PR; pinned lists and
  grepped phrases stay unbroken on one line.
  *(Cites: D-10, obs:381021a7.)*
- **REQ-C1.3** Reclassifications SHALL respect the safety floor with a
  recorded analysis, update the doctrine manifest, and name the reclassified
  doc at its in-body use site.
  *(Cites: D-6, obs:38878e99.)*
- **REQ-C1.4** The reverted `migrate-format-version.sh` guidance SHALL be
  re-landed in `doctrine/spec-format.md`'s `## Versioning of this
  meta-spec` section by the closing task — sequenced last to shrink the
  sibling-spec merge-conflict window (D-9); under the D-4 cap the addition
  charges nothing further to dependents.
  *(Cites: D-9, obs:92cd453e, kickoff lens pass (2026-07-17).)*

## REQ-D — Guard tooling

- **REQ-D1.1** `check-instructions --audit` SHALL report each floored
  surface's margin-to-warn and margin-to-error (the injected-context
  surface has no error threshold: it stays warn-only and carries no
  floor; a permanently exempt doc likewise carries no headroom floor —
  its per-file budget is already waived by its `exempt|` entry, whose
  existing over-budget notice stands, and its aggregate weight is capped
  per D-4), and every guard run SHALL emit a named floor-breach warning
  (never an error) when a floored surface's margin is strictly below its
  headroom floor. A missing or non-numeric floor knob SHALL abort the
  guard fail-loud, exactly as the existing budget knobs do — never
  fail-open.
  *(Cites: D-2, D-8, kickoff lens pass (2026-07-17).)*
- **REQ-D1.2** The audit shortlist and ranked report SHALL include each
  pending-diet allowance's Task field, so a Task retag is visible to the
  test surface.
  *(Cites: D-8, obs:002ebf4a.)*
- **REQ-D1.3** The guard SHALL check the reverse direction of doctrine
  manifests: every point-of-use doc is named at some in-body step; a
  missing use-site naming SHALL be a warning.
  *(Cites: D-7, obs:38878e99.)*
- **REQ-D1.4** The guard test suite's real-corpus offender-shortlist
  expectations SHALL derive from the suppression list rather than hardcoded
  file names.
  *(Cites: D-8, obs:c5a95acf.)*
- **REQ-D1.5** The spec-format exemption rationale (in
  `config/instruction-budget-exemptions.txt`) SHALL be corrected to drop
  the superseded claim that the doc is the dominant run-start load for
  `/spec-draft` and `/spec-kickoff`, refresh the stale trim-gap figures,
  and state the capped-charge semantics.
  *(Cites: D-4, obs:9faf6a79, kickoff lens pass (2026-07-17).)*
- **REQ-D1.6** The guard SHALL emit a named below-target warning (never an
  error) when a floored surface's margin is at or above its headroom floor
  but below its restoration target (twice the floor, derived from the
  floor knobs — no separate target knobs), and SHALL support a
  `declared-exception|<surface>|<reason>` suppression-list entry (reason
  mandatory; a reason-less entry is an error) that excuses exactly the
  warning it names — a below-target warning, or a use-site warning
  (REQ-D1.3) via the `use-site:<skill>/<doc>` surface key — and never a
  floor-breach warning.
  *(Cites: D-11, kickoff lens pass (2026-07-17).)*

## Changelog

- 2026-07-16 — Bundle drafted via `/spec-draft` (fold-detection ran against
  all thirteen existing specs; overlap with prompt-hygiene resolved as a new
  spec citing it, per the drafting-session decision recorded in Sources).
- 2026-07-16 — Kickoff walkthrough edits (kickoff §3): REQ-C1.1 gains the
  declared-exception clause per REQ-A1.5; Task 2 takes ownership of
  REQ-A1.4's raise-rationale enforcement (deliverable, Done-when, and
  citation added).
- 2026-07-16 — Kickoff walkthrough edits (kickoff §6): the closure-margin
  target assertions move from Tasks 7 and 9 to Task 11 (a multi-task
  outcome verified by the closing task), keeping the four diet tasks
  dispatchable in parallel with Done-when conditions their own scope
  controls.
- 2026-07-17 — Kickoff sign-off lens-pass edits (kickoff §8): REQ-D1.6 and
  D-11/D-12 minted — machine-checkable restoration targets via a named
  below-target warning plus a `declared-exception|` suppression form, and
  the raise-rationale carrier as a `raise|` suppression entry scoped to
  warn/error knobs; floor-knob names pinned in REQ-A1.1; fail-closed
  behaviors pinned (missing floor knob, absent raise baseline, missing or
  malformed exempt doc/entry, malformed manifests); backstop split pinned
  between REQ-A1.3 and REQ-A1.5; test-spec gains per-group H2 headings
  (markdownlint MD001); plus the remaining wording, Done-when, and
  cross-file-consistency corrections from the nine-lens review recorded in
  the brief.
- 2026-07-17 — Panel-pass edits (kickoff §8, gemini backend): the
  declared-exception "only" contradiction in REQ-D1.6/D-11 reworded
  (excuses exactly the warning it names); permanently exempt docs pinned
  as carrying no headroom floor (REQ-D1.1 — without this, Task 11's
  no-floor-breach gate was unsatisfiable); the guard-performance
  invariant scoped to IO/fork growth; D-4's reason-less-entry note
  aligned with REQ-A1.4 (error and cap forfeiture); the unbroken-phrases
  Done-when clause mirrored to Tasks 7–9.
- 2026-07-17 — Panel iteration 2 edits (kickoff §8): a stale `raise|`
  entry pinned as a guard error (REQ-A1.4, mirroring pending-diet
  ownership); Task 11's closing gate extended to unexcepted use-site
  warnings (diets rewrite the bodies the use-site check scans); Task 2's
  declared-exception wording aligned with REQ-D1.6/D-11; the brief's
  critical-path figure and R7 collision set corrected.

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
