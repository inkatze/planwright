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
