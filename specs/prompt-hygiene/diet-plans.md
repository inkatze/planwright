# Prompt Hygiene — Initial audit & diet plans (Task 2)

This is the recorded artifact for **REQ-A1.3** (`[manual]`): the initial per-file
audit run and a diet plan per shortlisted offender, naming what moves to rule
docs, what collapses to a reference, what is cut, and what defers to
point-of-use loading. It is reviewed at the Task 5 / 6 / 7 / 7.5 diet PRs against
the actual diffs (law moved **verbatim in meaning**, no contract change rides a
diet — REQ-D1.1).

Produced by `scripts/check-instructions.sh --audit` on 2026-07-12 against the
branch's merge base. Regenerate with that command; the offender shortlist and
per-file/per-skill numbers below are its output.

## Audit summary (2026-07-12)

Per-file offenders over the error floor (SKILL.md 4,250 / doctrine 4,000):

| File | Words | Floor | Diet task |
| --- | --- | --- | --- |
| `skills/orchestrate/SKILL.md` | 7,019 | 4,250 | Task 5 (pilot, D-12) |
| `skills/execute-task/SKILL.md` | 5,094 | 4,250 | Task 6 |
| `skills/spec-kickoff/SKILL.md` | 4,639 | 4,250 | Task 7 |
| `doctrine/spec-format.md` | 4,568 | 4,000 | Task 7 (trim-or-exempt) |

Per-skill start-load / closure: every skill scores **body-only** at this task —
no `SKILL.md` yet declares a doctrine manifest (those land in Task 3), so
start-load = the SKILL.md body and no start-load/closure offender is *visible*
yet. The known start-load offender `/spec-draft` (≈10,460 at kickoff: ~2,482
body + ~7,978 run-start doctrine, `spec-format.md` dominant) becomes computable
only once Task 3 adds manifests; its transitional start-load allowance is seeded
in Task 3 and its diet is **Task 7.5** (point-of-use reclassification). It is
therefore out of this pre-manifest audit's reach by construction.

Injected-context surface: `scripts/tool-discovery.sh` contributes ~27 words of
static prose (warn floor 200) — a report row, no warning. `tasks-pr-sync.sh`
emits no `additionalContext`/`hookSpecificOutput`, so it is not an
injected-context surface and carries no row.

Warn-level (reported, non-failing, no diet owed): `skills/spec-draft/SKILL.md`
(3,146 ≥ 3,000) and `doctrine/gate-wiring.md` (2,989 ≥ 2,500).

## Diet plans

The shared moves (apply to every skill diet): collapse each restated doctrine
gist in `## Doctrine` to the one-line reference the manifest already carries;
add the doctrine manifest (Task 3) classifying each rule-doc load run-start vs
point-of-use; keep all **gating law** in the always-loaded core (the safety
floor, REQ-C1.2 / instruction-hygiene) — never defer a rule that gates whether
an action is permitted.

### `/orchestrate` → Task 5 (behavioral pilot, D-12)

Largest offender; the pilot verified before/after by the kept eval (Task 4
baseline → Task 5 re-run, pass^3 paired).

- **Defer to point-of-use (rare mode branches):** the `## Meta-tower` and
  `## Fleet entry` sections (the `--meta` / `--fleet` arms) and the
  `### Degradation ladder & runtime failover` subsection are read only when that
  mode/branch is taken — reclassify to point-of-use, not run-start.
- **Move law to a rule doc:** the reconcile-sweep predicate and dispatch-record
  concurrency law belong with the orchestration-concurrency rule doc; the skill
  keeps a one-level reference in its manifest.
- **Collapse to references:** the `## Doctrine` restatements of
  backend-capability-contract / autonomous-safe-decision gists.
- **Keep in run-start core:** Modes, Pre-flight, Selection, the dispatch record's
  gating steps, Stop conditions, Invariants.

### `/execute-task` → Task 6

- **Defer to point-of-use:** `### Step isolation` (the per-unit/per-step hosting
  branch), `### Adaptive CI-failure handling` detail, and
  `## In-flight amendments` (a rare branch) — read at the step that needs them.
- **Collapse to references:** the `## Doctrine` gists (research-rigor,
  security-posture, validation-rigor, finding-categorization, gate-wiring) to
  their manifest references; the Convergence section's review-sequence mechanics
  to a pointer at `gate-wiring` / `finding-categorization`.
- **Keep in run-start core:** Pre-flight gates (freshness, Ready-or-Active,
  dependency), Test-first, PR-creation invariants, Stop conditions, Invariants.

### `/spec-kickoff` → Task 7

- **Collapse to references + defer format detail:** much of `## Sign-off` (the
  largest section: sign-off-record format, the content-anchor command forms, the
  amendment ritual) is already normative law in `doctrine/spec-format.md` —
  collapse the restatement to a one-level reference and read the format detail at
  point-of-use (the sign-off step), not run-start.
- **Defer to point-of-use:** the `## Modes` delta/amendment arms.
- **Keep in run-start core:** Pre-flight, the walkthrough flow and its
  stop-on-inconsistency gate, Invariants.

### `doctrine/spec-format.md` → Task 7 disposition (trim **or** permanent exempt)

A *compliant* trim removes only ~99 words below the 4,000 doctrine floor (it
sits at 4,568), far short of what its dependents (`/spec-draft`, `/spec-kickoff`)
must shed for **start-load** — so their start-load compliance rests on Task 7.5's
point-of-use reclassification **regardless** of the choice here (the coupling is
limited; see requirements REQ-D1.1 note and design cross-cutting concerns).
Task 7 chooses one:

- **Trim** under the doctrine per-file floor if the ~570-word reduction is
  achievable without weakening its authorable-from-alone contract (the meta-spec
  must stay self-contained); or
- **Permanent recorded exemption** (REQ-B1.3a) whose rationale names the
  authorable-from-alone contract and the start-load coupling. A permanent
  exemption never suppresses start-load/closure, so it does not strand the
  dependents — Task 7.5 owns their start-load fix.

## Task 3 update (2026-07-12): start-load now computable

Task 3 added a doctrine manifest to every `skills/*/SKILL.md` (current-reads
classification, no slimming) and wired the manifest-completeness assertion
(REQ-A1.2). With the manifests in place, `scripts/check-instructions.sh --audit`
computes each skill's mandatory-at-start and reachable closure. The manifests
record the **current** reading model — the skills front-load their core doctrine
at run start (D-9's rejected "keep run-start front-loading of all doctrine" is
the state as it stands); a doc is marked `point-of-use` only where the skill's
own prose reads it on a conditional branch or mode (an escalation, `--watch`,
`--bookkeeping`, a decision-domain catalog walk). The diets (Tasks 5/6/7/7.5)
reclassify further and move law to rule docs.

Start-load offenders the computation surfaced (error threshold 10,000):

| Skill | Start-load | Closure | Diet task | Allowance |
| --- | --- | --- | --- | --- |
| `/orchestrate` | 16,371 | 19,789 (warn) | Task 5 | `pending-diet start-load` |
| `/execute-task` | 16,429 | 18,091 (warn) | Task 6 | `pending-diet start-load` |
| `/spec-kickoff` | 13,055 | 14,717 | Task 7 | `pending-diet start-load` |
| `/spec-draft` | 12,636 | 14,298 | **Task 7.5** | `pending-diet start-load` |

`/orchestrate`, `/execute-task`, and `/spec-kickoff` are already per-file
offenders with diet tasks (their start-load allowance rides the same task, and
their own diet PR sheds both allowances). `/spec-draft` is the offender only the
start-load budget catches: its body (3,201) is under the per-file floor, so
Task 2's pre-manifest audit could not see it — its diet is **Task 7.5**,
point-of-use reclassification. No reachable-closure offender surfaced (every
skill's closure is under the 20,000 error threshold; `/orchestrate` and
`/execute-task` warn), so no closure allowance is seeded — matching the kickoff
expectation. `/builder` (start-load 7,334 — its `decision-domains` and
`finding-categorization` reads are run-start: the former is the escalate-vs-
auto-apply permission gate walked before applying, which the safety floor keeps
out of point-of-use, the latter drives the recommend-vs-apply call and the audit
output on every run), `/self-review` (9,994, warn), and `/polish` (9,591, warn)
are under the error threshold and carry no allowance.

Each start-load allowance is seeded in `config/instruction-budget-exemptions.txt`
and removed by its diet task's own PR (Task 8 forbids any lingering `pending diet`
allowance, REQ-D1.4).

## Task 5 outcome (2026-07-13): `/orchestrate` dieted

Executed per the plan above, with the deviations recorded on the Task 5 PR
for the REQ-D1.1 `[manual]` review. Results: body 7,200 → ~4,180 words
(error floor 4,250; warn stands), mandatory-at-start 16,371 → ~4,470 (error
10,000; no warn), closure 19,789 → ~19,470 (warn stands, error 20,000). Law
moved verbatim in meaning to two new point-of-use rule docs:
`doctrine/orchestration-concurrency.md` (dispatch-record/lock/marker law,
reconcile predicate) and `doctrine/orchestration-modes.md` (degradation
ladder & failover, meta-tower, fleet entry). Beyond the plan's literal list —
required to reach the non-exemptible start-load budget — `spec-format` and
`gate-wiring` reclassified run-start → point-of-use (their gating law stays
in the body; only format/record detail defers), and `finding-categorization`
left the manifest (orchestrate applies no finding buckets;
`/execute-task` → `/polish` own them downstream). Both Task 5 allowances
removed; the guard passes with no suppression of `/orchestrate`'s own.
Remaining offenders (Tasks 6/7/7.5) unchanged.

The behavioral pilot (REQ-D1.3) was **deferred at ship**: headless CLI
slash-path skill injection proved unavailable, so no eval cell has ever
measured the instruction file — the honest verdict, the bare-model root
cause, the harness hardening that ships instead (injection sentinel, prompt
delivery fix, cap recalibration, diagnosis seams), and the follow-up path
are recorded in `tests/prompt-evals/results/comparison.md` and the
`behavioral-pilot-injection-design` observation.

### `/spec-draft` → Task 7.5 (point-of-use reclassification)

`/spec-draft`'s start-load (12,636) is dominated by run-start doctrine, not its
body: `spec-format` (4,568) plus `interaction-style`, `research-rigor`,
`autopilot-reflex`, `security-posture`, `engineering-decisions`, `proportionality`,
and `customization-boundary`. Its per-file body (3,201) only warns, so there is
no body diet to lean on; the fix is manifest reclassification, moving law
**verbatim in meaning** (no contract change, REQ-D1.1) and never deferring
gating law (the safety floor, REQ-C1.2).

- **Reclassify run-start → point-of-use (read at the step that needs them):**
  - `engineering-decisions` and `customization-boundary` — read only in the
    **design phase** (design.md recommendations and the capability-vs-style
    scoping call); reclassify to `point-of-use` with that site, joining
    `decision-domains` (already point-of-use for the design-phase catalog walk).
  - `autopilot-reflex` — read at the **altitude-gate** step (seed-claim /
    mid-flow trigger check and the trigger-scoped altitude record); reclassify
    to `point-of-use` if the trigger-scan summary the flow needs at start can be
    stated inline (gating law stays; only the bulk defers).
- **Keep in run-start core:** `spec-format` (the meta-spec every file must
  conform to, needed throughout), `interaction-style` (governs every exchange),
  `security-posture` (artifact data-hygiene for everything committed), and
  `research-rigor` (its triggers are checked before drafting) — plus
  `proportionality`.
- **Target:** mandatory-at-start under 10,000 with no transitional allowance
  remaining. Reclassifying `engineering-decisions` (1,027) + `customization-boundary`
  (1,129) alone sheds ~2,156, bringing start-load to ≈10,480 — still over, so
  `autopilot-reflex` (988) must also reclassify (→ ≈9,492) or the body must
  shed the balance. Task 7.5 owns the final split; whichever combination lands,
  gating law stays run-start (escalate the threshold-vs-safety tension rather
  than defer a permission gate — instruction-hygiene safety floor).

The verbatim-in-meaning move and the "no gating law deferred" check are the
`[manual]` review on the Task 7.5 PR (REQ-D1.1, REQ-C1.2).
