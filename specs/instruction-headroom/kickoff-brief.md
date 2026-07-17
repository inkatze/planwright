# Instruction-budget headroom — Kickoff Brief

## 1. Header

- **Spec:** `specs/instruction-headroom`
- **Spec commit at walkthrough start:** `370123f` (370123fe60268ac31918ad8dff94f20f792c82bc)
- **Walkthrough date(s):** 2026-07-16 – 2026-07-17 (sections 2–7 walked
  and signed 07-16; lens pass, panel pass, and sign-off 07-17)
- **Mode:** first activation (Status Draft, format-version 2, no prior brief)
- **Validator outcome (pre-flight):** `scripts/spec-validate.sh` — 0 errors, 0 warnings
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true`
  (core defaults; the machine-local overlay overrides neither)
- **Working location:** spec worktree
  `.claude/worktrees/instruction-headroom-spec`, branch
  `planwright/instruction-headroom/spec`
- **Independent walkthrough:** suggested (`/spec-walkthrough
  specs/instruction-headroom`); optional, not a sign-off dependency

## 2. Goal & glossary

**Restatement.** prompt-hygiene built word budgets over every instruction
surface, enforced by `check-instructions.sh`. Landing features under the
guard saturated the guarded surfaces (per the 2026-07-16 audit cited in the
Goal), so the guard now blocks required doctrine growth: two required
additions were already reverted or force-trimmed purely for budget. The fix
is four-part: (a) **policy** as doctrine — headroom floors per surface
class (about 5% of each error threshold, overlay-tunable knobs), breach as
a named warning never an error, and the four-rung restoration ladder (diet
→ point-of-use reclassification → deliberate raise → exemption), each rung
gated on the prior being exhausted or recorded-inapplicable, gating law
unmovable on any rung; (b) **restoration** passes bringing every
policy-flagged surface to margin ≥ 2× floor, else a declared exception;
(c) **structure** — aggregates charge a permanently per-file-exempt doc at
min(actual, its per-file error threshold), actual always printed;
(d) **tooling** — margin columns, floor-breach warnings, Task-field
visibility, suppression-list-derived test expectations, the reverse
use-site check, and the stale exemption-rationale fix.

**Rules out.** Changing the unit (words) or guard architecture (POSIX
shell, data-only inputs); deferring gating law to hit a number; silent
meaning changes in diets; the sibling format-grammar spec's meta-spec
wording (fragment 94f03e6c deliberately unconsumed).

**Assumes.** The 2026-07-16 audit at v0.14.1 is ground truth for margins;
routine doctrine additions run 80–560 words (sizing basis for floors and
targets); the format-grammar sibling drafts concurrently and spends the
headroom this spec creates.

**Glossary (implicit terms surfaced).** *Surface classes:* SKILL.md body
and rule doc (per-file); mandatory-at-start (start-load) and reachable
closure (aggregates). *Margin:* error threshold minus current (charged)
words. *Floor:* minimum margin; below it is a breach, triggering the
ladder. *Restoration target:* twice the floor. *Gating law / safety
floor:* instruction-hygiene's rule that permission-gating law loads
run-start; unmovable by any rung. *Capped charge:* min(actual, per-file
error threshold), permanently exempt docs only, aggregates only.
*Pending-diet allowance / suppression list:* prompt-hygiene's existing
transitional-cover and exemption mechanisms, extended not replaced.

**Resolutions.** (1) Restoration scope is **live-computed**: REQ-C1.1 /
Task 11 bind to whatever the guard flags on the real corpus when the tasks
run; D-6's breach list is the plan, not the contract.

Signed off: 2026-07-16

## 3. Requirements walkthrough

**REQ-A — Standing headroom policy (5 REQs).** Intent: give the guard a
vocabulary for "close to the wall" before the wall blocks work. Floors as
core knobs (250/250/500/1,000, roughly 5–6% of the error thresholds —
arithmetic checked), breach as a named warning on every run (an error
would recreate the blocking problem), the ordered ladder with recorded
rung-entry and inapplicability, safety floor inviolable with human
escalation, 2×-floor targets with the declared-exception path. Probed: an
overlay setting a floor to 0 disables the warning — accepted as normal
overlay freedom. Outcome: intact; REQ-A1.4 ownership resolved (finding 1).

**REQ-B — Exempt-doc aggregate coupling (2 REQs).** Intent: dependents of
a sanctioned over-floor doc pay the budgeted size, not the overage.
Capped charge applies automatically to any permanently exempt doc
(suppression-list `exempt|` entries; today only `spec-format.md`); an
exempt doc under its threshold charges actual (min() handles it);
pending-diet allowances stay fully charged (transitional, not
sanctioned); actual words always printed beside charged. Outcome: intact.

**REQ-C — Restoration passes (4 REQs).** Intent: execute the ladder on
today's breaches and prove the result. Close verifies the live-computed
corpus (§2 resolution 1); diets preserve law verbatim in meaning with
content-pinned tests in the same PR and grepped phrases unbroken;
reclassifications need a recorded safety-floor analysis, manifest update,
and in-body use-site naming; the ~80-word `migrate-format-version.sh`
guidance re-lands last, into restored margin, no allowance ceremony.
Outcome: intact; REQ-C1.1 edit applied (finding 2).

**REQ-D — Guard tooling (5 REQs).** Intent: make headroom work verifiable.
Margin-to-warn and margin-to-error in audit rows; the floor-breach warning
is warning-severity by standing law ("never an error" in the REQ text,
unlike D-7's use-site check where promotion stays open); pending-diet Task
field visible in shortlist and ranked report; reverse use-site check warns
per skill and doc; real-corpus shortlist expectations derive from the
suppression list; the stale "dominant run-start load" claim is replaced by
capped-charge semantics. Outcome: intact.

**Findings resolved.**

1. **REQ-A1.4 task-coverage gap** (verified against
   `check-instructions.sh:282-350`: reason-less suppression entries error
   today, but no raise-detection exists and no task delivered it while
   test-spec pins it `[test]`). Resolution: **fold into Task 2** —
   deliverable, Done-when, and REQ-A1.4 citation added.
2. **REQ-C1.1 missing exception clause** (REQ-A1.5 and Task 11 both carry
   the declared-exception path; C1.1 did not). Resolution: **edit
   applied** — C1.1 gains "or carry a declared exception per REQ-A1.5".

**Consolidated spec-edit list.** `requirements.md`: REQ-C1.1 exception
clause + citation; Changelog entry (2026-07-16, kickoff §3). `tasks.md`:
Task 2 deliverables gain raise-rationale enforcement, Done-when gains the
raise fixture condition, Citations gain REQ-A1.4.

Signed off: 2026-07-16

## 4. Design walkthrough

Reconciled ledger: **10 confirmed, 0 amended, 0 superseded** (D-IDs per
`design.md`; all origin `N`, 2026-07-16). No decision contradicts a walked
requirement. D-6's factual claims were verified against the live corpus at
walkthrough time: gate-wiring.md 2,988 words (a ~500-word diet clears the
2,500 warn), spec-format.md 5,125 actual vs the 4,000 doctrine error
threshold (1,125 relief per dependent aggregate under D-4's cap),
execute-task body 4,248 / spec-kickoff 4,243 / orchestrate 4,179 (the
D-6 diet sizes reach ≤3,750), research-rigor exactly 491 words and
`run-start` in both the self-review and polish manifests today. Notes per
decision: D-1 is the pinned altitude record (cited from the goal; three
seeds independently assert standing-policy altitude); D-2's "never error"
posture is consistent with REQ-D1.1 and the blocking problem it fixes;
D-4's start-load inclusion is justified because spec-format.md is
run-start gating law for /execute-task and unreclassifiable; D-5's raise
discipline is instantiated by Task 2's raise-rationale enforcement (§3
finding 1 — instantiation, not a design change); D-6 remains the plan
while scope binds live (§2 resolution 1); D-7's warning severity leaves
promotion open, unlike REQ-D1.1's standing warning-only law; D-8 keeps one
report as the single reading surface and removes the obs:c5a95acf test
coupling; D-9 minimizes the sibling-spec merge-conflict window; D-10 keeps
operational technique out of doctrine with obs:381021a7's two silent
failure modes covered by Done-when conditions.

Signed off: 2026-07-16

## 5. Verification approach

Coverage mix (per `test-spec.md`'s intro): guard mechanics `[test]` via
fixtures in `tests/test-check-instructions.sh`; policy prose
`[design-level]` (Task 1's amended doctrine is the artifact); restoration
outcomes `[test + manual]`; the re-land and text fixes `[manual]`.
**Ownership:** GitHub CI (`mise run check`) runs every `[test]` entry; the
human sweeps `[manual]` at each diet PR's meaning-preservation review and
at the Task 11 closing audit. **Dead-path check:** one found — REQ-A1.4's
pinned `[test]` behavior had no delivering task — resolved in §3 (folded
into Task 2). Every other `[test]` entry maps to fixtures a named task
builds; both pure-`[design-level]` entries (REQ-A1.2, REQ-A1.3) have
Task 1 as their artifact and REQ-A1.3 additionally exercises through
REQ-C1.3's recorded analyses.

Signed off: 2026-07-16

## 6. Task graph

Reconstructed from the `Dependencies:` lines (authoritative; render on
demand via `scripts/spec-graph.sh`). Waves: T1 → (T2 ∥ T3) → (T4 ∥ T5) →
(T6 ∥ T7 ∥ T8 ∥ T9) → T10 → T11. **Critical path:**
1 → 2 → 4 → 6 → 10 → 11, seven half-days ≈ 3.5 days serial (Task 2
became a 1-day unit at the lens pass; the rest are half-day, per
`tasks.md`); maximum width 4 at the diet wave. *(Corrected at panel
iteration 2: the pre-lens-pass "six half-days" figure was stale.)*

**Finding (resolved).** Tasks 7 and 9 asserted closure-margin targets
their own dependencies could not deliver (both need Task 6's gate-wiring
diet, absent from their `Dependencies:`; corpus math: cap 1,125 + body
diet ~500 leaves the execute-task closure ~275 short of its 2,000
target without gate-wiring's ~500). Resolution: **closure-margin target
assertions moved to Task 11** (the designated closing verification,
which already depends on 6,7,8,9,10); T7 keeps its start-load target
(achievable from its own scope under the Task 3 cap), T9 keeps body +
structural tests. Diet-wave parallelism preserved.

**Deliberate non-edges (do not "fix" later):**
- T5 ↛ T3, T4 — the use-site check needs only T2's config plumbing.
- T6–T9 mutually independent — four files, one diet each; no hidden
  T6→T7/T9 edge remains after the finding's resolution.
- T7, T8, T9 ↛ T10 — the self-review/polish start-loads T10 restores do
  not include the dieted bodies; only T6 feeds them, and T10 has that
  edge.
- T2 ∥ T3 — both edit `check-instructions.sh` *and*
  `tests/test-check-instructions.sh` in different code paths;
  merge-conflict exposure is risks R2/R7, not an edge. *(Corrected at the
  lens pass: the shared test file was missing from this note, and the same
  two files are also shared by T4 ∥ T5 and T3 ∥ T5 — see R7.)*
- T11 ↛ T5 — deliberate; T5 is transitively upstream via T10.

Signed off: 2026-07-16

## 7. Risk register

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| R1 | Sibling-spec collision: format-grammar lands ~560 words into `spec-format.md` mid-restoration; merge conflicts with Task 11's re-land. *(Corrected at panel iteration 3: Task 3's rationale rewrite lives in `config/instruction-budget-exemptions.txt`, a different file — no T3 collision.)* | D-4's cap absorbs the growth for dependents; D-9 sequences the re-land last. Signal: format-grammar PR merges while T11 in flight. |
| R2 | T2 ∥ T3 both edit `check-instructions.sh` and `tests/test-check-instructions.sh`; parallel dispatch may conflict. | Orchestrator picks critical-path-first (T2 first); conflicts small and worker-resolvable. Signal: second guard PR conflicts. |
| R3 | Diet meaning-inversion (obs:381021a7 precedent: wrap-broken grep, inverted contract sentence). | D-10 discipline in every diet Done-when; content-pinned tests same-PR; human meaning-preservation review per diet PR. Signal: structural test failure or reviewer catch. |
| R4 | Corpus drift between the 2026-07-16 audit and execution; ~450–500-word diet sizes may undershoot. | Scope binds live (§2 resolution 1); Task 11 is the catch-all with the declared-exception path. Signal: T11 margin report below target on a surface whose diet "passed". |
| R5 | Raise-detection subtlety in layered config (defaults → overlay → local); only "raised above core default" is a sound comparison. | Task 2 scopes enforcement to `instruction_budget_*` increases above core default; mechanism chosen at implementation. Signal: fixture design forces the question at T2. |
| R6 | Standing warning noise: floor-breach warnings fire on every guard run from T2 until restoration completes; desensitization risk. | Accepted: warnings never block, restoration tasks are the drain, named-warning format stays greppable. Signal: a breach warning surviving past T11. |
| R7 | T4 ∥ T5 (and T3 ∥ T5, since T5 depends only on T2) also share `check-instructions.sh` and `tests/test-check-instructions.sh`; T3 ∥ T5 additionally share `config/instruction-budget-exemptions.txt` (T3 rewrites the exempt rationale, T5 may add `declared-exception\|use-site:` entries). The same parallel-edit exposure as R2 in the tooling wave. *(Added at the lens pass; exemptions-file collision added at panel iteration 2.)* | Same mitigation as R2: critical-path-first dispatch and worker-resolvable conflicts; the tower may serialize the guard-script tasks when both are ready. Signal: a tooling-wave PR reports conflicts. |

**Decision-domains gap check** (merged catalog via
`scripts/resolve-catalog.sh decision-domains`, 11 domains): touched —
`api-surface` (audit output compatibility, decided in D-8) and
`secrets-config` (new knobs, decided in D-2 + REQ-A1.4; the
options-reference guard forces documentation via Task 2's
`mise run check`). Nine domains untouched or n/a (observability is
itself the deliverable, decided in D-2). **No catalogued domain the spec
touches is left undecided.** No open questions remain: R1–R7 all carry
mitigations and early signals; none is an undecided fork.

Signed off: 2026-07-16

## 8. Sign-off

### Lens review pass (first activation — full bundle, fan-out)

Nine read-only sub-agents, one per canonical Discovery-Rigor lens, over
the full bundle (fan-out path declared; first activation is non-trivial
scope). Shared tooling output: `spec-validate` 0/0 and markdownlint
(which itself contributed one tool-grounded finding, fixed before the
fan-out returned: test-spec per-group H2 headings, MD001). Raw findings
were merged and deduped; each load-bearing claim was validated per
Validation Rigor (the lens agents grounded claims against the live corpus
and `check-instructions.sh` line-by-line — reproduction and outside-in
built in; convergence across independent lenses served as the orthogonal
angle) and the adversarial bi-directional pass ran over both sets: no
kept finding was refuted, no declined finding was resurrected. The
self-critique pass added the test-spec REQ-C1.1 update (my own §6
relocation had not been mirrored there) and the two brief corrections
(R2/R7).

**Canonical lens-coverage table** (raw counts per lens before dedupe):

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 10 | absorb-claim over-broad; self-review target math 2 words short; two vacuous conditions; operator and backstop pins; all numeric claims otherwise verified correct |
| Security | 3 | echo-safety on new output surfaces; fixed-string matching pin; rationale data-hygiene; bundle itself clean of secrets |
| Error handling and failure modes | 12 | fail-open/fail-closed forks pinned (floor knob, raise baseline, missing exempt doc, malformed manifest, unmeasured surfaces at Task 11); target/exception mechanism gap (fork 1) |
| Performance | 4 | R10 fork-free invariant unstated; use-site check O(skills×docs) risk; duplicate-invocation risk resolved by fork 1; config-get batching declined |
| Concurrency / state | 6 | declared-exception statelessness gap (fork 1); shared-file collisions R2/R7; brittle 5,125 literal; premise correction (no T3/T11 file collision) |
| Naming, readability, structure | 8 | knob names unpinned; floor/margin terminology; garbled Task 5 sentence; group-reorder declined as stable-ID-violating |
| Documentation | 4 | options-reference obligation made explicit; second stale figure; exemptions file named; re-land section anchored |
| Tests / verification | 9 | raise fixture artifact undefined (fork 2); target comparator missing (fork 1); derived-expectations over-claim scoped; D1.5 content-pin added |
| Cross-file consistency | 3 | In-scope closure omission; Out-of-scope mirror; D1.5 skill-naming alignment |

**Altitude check (REQ-H1.3):** triggered bundle — `## Sources` pins three
seed claims asserting standing-policy altitude (obs:fd250fb5,
obs:36fa1662, obs:bfe73da9). D-1 is the altitude record, cited from the
goal; the task decomposition matches the claimed altitude (Task 1
doctrine, Tasks 2–5 core capability, Tasks 6–11 repo-local
instantiation). Verified, no finding.

**Dispositions.** 59 raw findings → 38 after dedupe. Two design forks
decided by the human (2026-07-17): **fork 1** — machine-checkable targets
(below-target warning + `declared-exception|` suppression form; minted
D-11 and REQ-D1.6); **fork 2** — raise-rationale carrier as a `raise|`
suppression entry scoped to warn/error knobs (minted D-12, REQ-A1.4
reworded). A 24-edit batch (E1–E24, itemized in the changelog entry and
the per-file diffs of this commit) was approved and applied, covering the
remaining 32 findings. **Declined with rationale (4):** REQ group
reorder (group letters live inside stable REQ-IDs; renaming violates
never-reuse, D-20); config-get fork batching (implementation detail on a
non-hot path — the guard runs once per PR, not per commit); dropping
Task 11's `--closeout` clause (kept as a cheap invariant assert);
further diet-title parallelism beyond the Task 6 rename (remaining
variation is informative). Zero findings left undispositioned. Validator
and markdownlint re-ran green after the batch.

### Panel pass (/panel-review --nested, gemini backend)

Run at the human's request after the lens-pass batch, on the committed
branch diff (interim commit `414519a`). Iteration 1 returned six
findings; local three-pass validation kept five, all approved and
applied as a sign-off cluster: the REQ-D1.6/D-11 "only" contradiction
(reworded to name both excusable warning kinds), the
exempt-docs-floor-breach gap (high — without the pin, `spec-format.md`'s
−1,125 margin would floor-breach forever and Task 11's gate was
unsatisfiable; REQ-D1.1 and its fixtures now exempt permanently exempt
docs from headroom floors), the guard-performance invariant overclaim
(scoped to IO/fork growth), the D-4 reason-less-entry alignment with
REQ-A1.4 (error and cap forfeiture, doubly fail-closed), and the
unbroken-phrases Done-when clause mirrored to Tasks 7–9. **Declined
(1):** the Task 11 `--closeout` brittleness claim — `mise run check`
already runs `--closeout` on every branch's CI, so the scenario is a
pre-existing repo-wide property, not this spec's defect. **Iteration 2**
returned five findings, all validated as consistency ripples of the
earlier edit waves and applied under the human's standing routine-fix
authorization (none is a design fork): the brief's stale six-half-day
critical-path figure (Task 2 is now a 1-day unit → seven half-days);
the stale-`raise|`-entry fail-closed pin (REQ-A1.4 + fixture); the R7
exemptions-file collision (T3 ∥ T5); Task 11's gate extended to
unexcepted use-site warnings; Task 2's declared-exception wording
aligned with REQ-D1.6/D-11. **Iteration 3** returned six: two declined
on validation (the fixed-string "stem mismatch" misreads the manifest
grammar — doc names are bare kebab, no paths or extensions; the
floor-lowering concern re-raises the overlay freedom the human accepted
in §3), four applied (brief R1's disproven Task 3 collision, the
below-target band's lower bound in Task 2, Task 10's body-trim
authorization, the unreadable-baseline fixture), plus the
stale-declared-exception cleanup-warning pin (REQ-D1.6, warn posture).
**Iteration 4** came back with eight of ten lenses clean and three
deliverable-text mirror nits (use-site-key fixture assigned to Task 5,
echo-safety fixture mapped in test-spec, stale-raise clause mirrored to
Task 2), all applied. **Convergence declared at iteration 4** on
diminishing returns: three consecutive iterations of strictly
decreasing, ripple-only findings, no repeated finding, no design fork
since iteration 1. Panel iteration commits: `17badec`, `928b86c`,
`fde1845`, `0e38113`.

### Sign-off record

First activation sign-off: all seven sections walked and signed
(2026-07-16), the full-bundle Discovery-Rigor lens pass fan-out completed
with every finding dispositioned, the REQ-H1.3 altitude check verified
(triggered bundle, D-1 cited from the goal, decomposition matches), and
the requested `/panel-review --nested` pass converged (4 iterations,
gemini backend). Validator re-ran green on the Ready bundle
(0 errors, 0 warnings); markdownlint clean. Status flipped Draft→Ready
and `Last reviewed:` bumped to 2026-07-17 on all four spec files (the
format-version 2 resting state; Active/Done are derived).

Signed off: 2026-07-17

Class: meaning
Lens-pass: the lens review pass recorded in this section (canonical
lens-coverage table, fork and batch dispositions, declines with
rationale; supplemented by the panel pass record above)
Anchor: `ad372c7305375155ca77272ceafed9df74b133b5` — computed as
`scripts/spec-anchor.sh specs/instruction-headroom`

## 9. Amendment log

(none yet)
