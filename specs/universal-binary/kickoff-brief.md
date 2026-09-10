# Universal Binary — Kickoff brief

## 1. Header

- **Spec:** `specs/universal-binary` (format-version 2)
- **Spec commit at walkthrough start:** `45d56e5`
- **Walkthrough date:** 2026-09-09
- **Mode:** first activation
- **Validator outcome (pre-flight):** `spec-validate: 0 error(s), 0 warning(s)` (plugin 0.38.0)
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true`, `kickoff_ready_ci_wait: 10m` (defaults; no local override file present)
- **Working location:** spec worktree `.claude/worktrees/universal-binary-spec`, branch `planwright/universal-binary/spec`, clean tree; no spec PR open yet
- **Doctrine resolution:** all nine rule docs resolved from the repository's own `doctrine/`
- **Independent walkthrough:** `/spec-walkthrough specs/universal-binary` suggested as an optional cold read; not a dependency of this brief

## 2. Goal & glossary

**Restatement.** This bundle does not decide whether planwright's script
layer moves to a compiled binary. It builds and ships the *method* that
decides it per tier, with measurements: a call-graph partition of the
script layer into tiers by invoker (D-3), attribution of the recorded
observations to tiers and defect classes as a dated pain matrix (D-4), a
derived constraint profile per surviving tier, a candidate screen against
the one hard constraint (REQ-B1.1: installing and running planwright SHALL
NOT require a compiler, interpreter, or package manager beyond a POSIX
shell, `git`, and the bootstrap tools), a bake-off of the survivors on one
representative primitive per tier under a shipped harness that reproduces
every cited figure (D-7), and one verdict per tier minted as a design
decision by the meaning-class amendment ritual with the human's scoped
re-sign-off (D-8). Migration tasks exist from birth and stay parked under
free-text gates until a verdict unparks them (D-18). Two hardenings land
first so the shell candidate is measured in its best form: the
atomic-create lock (D-11) and the printf echo discipline (D-12). The
altitude decision (D-1) supersedes the bootstrap runtime decision and keeps
its core value as the hard constraint.

**Rules out.** Editing skill prose (entry points are frozen instead,
REQ-E1.2); native Windows (a Deferred opportunity); any change to pipeline
semantics (spec format, status lifecycle, permission model, fleet
protocols); new adopter-facing features; any verdict minted by a skill on
its own authority; committing prebuilt binaries into the repository.

**Assumes.** Executables are permitted by the plugin platform under the
delivery constraints the Sources record (no top-level `bin/`). The mined
observation set cited in the Sources is the evidence base. Go and Rust
cannot be excluded by reading alone. The bootstrap decision is superseded
by annotation, never edited. Both delivery modes (marketplace copy and the
`~/.claude/` writer) must carry whatever a verdict selects, or say which
one does not.

**Resolutions recorded (with the spec edits applied in place).**

1. *Tests-only tier.* Tests are not live callers under REQ-A1.3, so the
   tests-only tier is entirely flagged and is dissolved by the flag: each
   script is relocated under `tests/` or removed before any migration. It
   carries no profile, screen, verdict, or migration task. An initial
   fold-into-dev-check reading was tried, found to contradict REQ-A1.3's
   "no flagged script SHALL be migrated", and reverted in favour of this
   reading. Edits: REQ-A1.3 (dissolution sentence), REQ-B1.2 and Task 3
   Done-when and test-spec REQ-B1.2 ("every tier that survives the flag" in
   place of "all five tiers").
2. *Live caller is transitive.* A script is live when reachable through the
   call graph from a hook registration, a tracked git hook, a skill body,
   or a check task or workflow; a library reachable only from flagged code
   is flagged too. Edits: REQ-A1.3, test-spec REQ-A1.3 (fixtures for the
   dead-subtree, test-only, and documentation-only cases).
3. *Operator tools are given a caller, not a tier.* A grounding check found
   that today's no-caller scripts are maintainer tools invoked by hand and
   named in `docs/`; a documentation mention is not a caller, and the
   sanctioned remedy is registering each as a check task, which places it
   in the dev-check tier by the call graph. No sixth tier. Edit: REQ-A1.3.
4. *The hardened-shell candidate's shared library is built at prototype
   scope inside Task 6* for the representative primitive only, promotable
   as Task 13's seed under D-17, never a layer-wide consolidation before
   the bake-off. Edit: Task 6 deliverables.

**Mid-walk lens (delta-scoped, inline; edits 1 through 4).** The first
application of edit 1 (fold into dev-check) was caught by this pass as a
contradiction with REQ-A1.3 and re-put to the human; the second
application is clean. Remaining lenses over the delta: correctness (Task
11's "no-caller scripts removed or given a caller first" and Task 2's
derivation list agree with the new REQ-A1.3 wording), cross-file
consistency (test-spec REQ-A1.1's "referenced only by a test" fixture lands
in the tests-only tier and is then flagged, as intended), documentation
(the Sources' dated no-caller and tests-only counts are regenerated by the
Task 2 script, not anchored claims). No further findings.

**Glossary (implicit terms surfaced).**

- *Adopter tier* — a tier whose scripts run on an adopter's machine: hook,
  skill-called, and library. Dev-check is dev-only; tests-only is dissolved
  by the REQ-A1.3 flag.
- *The writer* — the `~/.claude/` writer delivery mode, the alternative to
  the plugin marketplace copy.
- *The mined set* — the observation fragments and frozen legacy lines the
  Sources section of `requirements.md` cites; the attribution of REQ-A1.2
  is bounded to it.
- *Verdict* — one design decision per surviving tier, minted by amendment,
  whose rationale is the harness measurements and the cost-benefit line.
- *Representative primitive* — the primitives a bake-off's task names,
  implemented identically by every full candidate (comparison points
  implement none): the lock and the most-duplicated parser for the
  adopter-runtime pair (Task 6), the command-guard tokenizer and the
  ready-guard decision path for the hook tier (Task 7).
- *Adopter-runtime pair* — the library and skill-called tiers, which share
  a constraint profile and one bake-off (D-5).
- *Full candidate* versus *comparison point* — the two classes REQ-C1.1
  names: a full candidate implements the primitives under the differential
  fixtures; a comparison point is measured on the harness's trivial
  program only and cannot be selected without a further bake-off.
- *The portability floor* — POSIX-specified shell and tool options plus
  the runtime set REQ-B1.1 names (a POSIX shell, `git`, `gh`), on the
  platforms of the D-13 matrix; a fix outside it is escalated, never
  applied.
- *Check task* — any task in `mise.toml`, whether in the check aggregate or
  on-demand; the sanctioned caller that places an operator tool in the
  dev-check tier.
- *Selector*, two senses — the shell/compiled implementation selector (a
  key in the operator-owned machine-local configuration layer, REQ-E1.3),
  and the orchestration selector that picks the next task; the bundle
  names the second in full wherever it means it.
- *Hardened-shell candidate* — shell with the Task 1 lock, the Task 1.1
  printf discipline, and, at prototype scope inside the bake-off, a shared
  library seam and batched reads (D-6), so substrate effect is measured
  apart from architecture effect.
- *Fetch shim* versus *migration shim* — two roles one file may play: the
  D-9 shim that fetches and verifies a compiled artifact on first use, and
  the D-10 shim that keeps an entry point's path and contract while
  delegating to a migrated implementation.
- *Convergence pass* — the review loop `/execute-task` runs before opening a
  PR (the configured `review_sequence`, default `/polish --nested`); its
  findings per candidate are a measured field of D-7.
- *Differential fixtures* — recorded inputs with recorded stdout, stderr
  class (empty, or matching a recorded pattern), and exit code, run
  against the shell implementation and each candidate implementation,
  prototype (REQ-C1.6) or migrated (REQ-E1.3).
- *Scoped re-sign-off* — a `/spec-kickoff` amendment walk over the delta a
  verdict amendment introduces, the human's key on every verdict.
- *The check aggregate* — `mise run check`, the local gate CI mirrors.

Signed off: 2026-09-09

## 3. Requirements walkthrough

Walked group by group, one decision per turn after the operator asked for a
slower, plainer pace; each decision below is restated in the terms the
operator confirmed it in.

**REQ-A — Partition and attribution.** Intent: know which scripts exist,
who calls them, and which recorded bugs belong to which of them, produced
by scripts rather than by hand. Settled in section 2 (tests-only
dissolution, transitive liveness, operator tools given a caller). One
further decision: the number-copy guard of REQ-A1.4 scans the
claim-making text only; the Sources and Changelog sections are the spec's
bibliography and history and may carry the drafting-day figures.
Outcome: confirmed, with edits.

**REQ-B — Constraint profiles.** Intent: state per tier what a substrate
must satisfy, and turn the claimed portability floor into a tested one.
Decision: the existing test suite is repaired on macOS and Alpine *first*,
as its own task, and every job on every platform is blocking from the day
the platform joins; there is no advisory mode and no promotion switch to
own or forget. This reverses a rejected alternative in D-13 and is recorded
there as an amendment. The repair cost is accepted as unknown until the
first run on each platform. Outcome: amended.

**REQ-C — Candidate screen and bake-off.** Intent: measure before
choosing, on equal terms, with a harness that reproduces every figure.
Decision: two classes of screened-in candidate. Full candidates (hardened
shell, Go, Rust) implement the representative primitives; comparison
points (Zig, Bun-compiled TypeScript) are measured on a trivial program
only and can never be selected by a verdict without first being promoted
through a further bake-off. Outcome: confirmed, with edits.

**REQ-D — Verdict record.** Intent: the decision per tier is a design
decision with measured rationale, signed by a human. Decision: the
worker's Task 9 ends with the drafted verdicts on the spec branch; the
operator's scoped re-sign-off is a separate human act, and the parked
migration tasks wait on a *signed* verdict, not on Task 9 completing.
REQ-D1.2's route (a `Superseded-by` annotation on the bootstrap decision,
body untouched) is established practice in `specs/bootstrap/design.md`.
Outcome: confirmed, with edits.

**REQ-E — Migration gates.** Intent: nothing leaves shell without a
verdict; entry points keep their contract; the shell version stays and
stays tested until a human removes it. No decision needed; the operator
confirmed the two-implementations-one-switch model when it came up under
REQ-F. Outcome: confirmed.

**REQ-F — Delivery of compiled artifacts.** Intent: a compiled program is
fetched once, verified against a pinned checksum, and never trusted
unverified. Decision: when the artifact cannot be fetched or verified the
entry point *stops* and prints how to select the shell implementation; it
never turns to shell by itself. Consequence accepted: an offline first
run, or a hook whose fetch failed, blocks the adopter until they flip the
setting. Outcome: confirmed; reading recorded here, no edit.

**REQ-G — Cost-benefit record.** Intent: every verdict costs the
do-nothing option at equal weight and states a break-even condition. No
decision needed. One observation carried to the risk register: the
porting rate REQ-G1.3 logs is measured on the fleet's automated workers,
so it predicts their effort, not a person's. Outcome: confirmed.

**Consolidated spec-edit list (all applied in place on the Draft bundle).**

1. REQ-A1.3 — transitive liveness; documentation is not a caller; tests-only
   tier dissolved by the flag; remedies named (relocate under `tests/`,
   register as a check task). Paired test-spec REQ-A1.3 fixtures.
2. REQ-B1.2, Task 3 Done-when, test-spec REQ-B1.2 — "every tier that
   survives the flag" replaces "all five tiers".
3. Task 6 — hardened-shell prototype at prototype scope; full candidates
   versus comparison points named.
4. REQ-A1.4 and test-spec REQ-A1.4 — Sources and Changelog exempt from the
   number-copy guard.
5. REQ-B1.4, D-13 (amended), test-spec REQ-B1.4 — repair-first, blocking
   from day one; Task 4 re-scoped to the repair and Task 4.1 added for the
   matrix jobs; Task 5 now depends on Task 4.1.
6. REQ-C1.1 and test-spec REQ-C1.1 — the two candidate classes.
7. Task 9 Done-when and the six Deferred gates — the human re-sign-off is
   the gate, not a task deliverable.
8. The sign-off lens pass's dispositions (section 8): applied across all
   four files on 2026-09-09 after the seven above.

**Mid-walk lens (delta-scoped, inline; edits 4 through 7).** Edit 5's
dependents checked: Task 5's dependency moved to Task 4.1; REQ-C1.4's
"including any red ones" still holds for reds that appear after the repair;
test-spec REQ-B1.1's smoke step now lives in Task 4.1. One pre-existing gap
surfaced for section 6: Task 1.1's Done-when named the Alpine job while the
task declared no dependency on the matrix (settled in section 6, then
re-settled at sign-off, see section 8). Edit 7's dependents checked: REQ-E1.1
already says the migration tasks depend on the verdict amendment, and the
free-text gates now say "signed". No further findings.

Signed off: 2026-09-09

## 4. Design walkthrough

Every decision in `design.md` accounted for. "Confirmed" means the
rationale stands as written and nothing walked in sections 2 and 3
contradicts it.

| D-ID | Title (short) | Disposition |
| --- | --- | --- |
| D-1 | Altitude: a method, not a binary | Confirmed. Cited from the goal; the altitude check at sign-off reads this. |
| D-2 | New bundle, not an extension | Confirmed. |
| D-3 | Tier partition derived from the call graph | Confirmed. Liveness reading (transitive; docs are not callers) recorded in REQ-A1.3, consistent with this decision. |
| D-4 | Snapshots cited, not copied | Confirmed. The Sources/Changelog exemption narrows the guard, not the rule. |
| D-5 | Bake-off breadth by inheritance | Confirmed. Tests-only carries no profile, so the rule applies to four tiers. |
| D-6 | Candidate set | Confirmed, annotated: Zig and Bun are comparison points (REQ-C1.1 classes). |
| D-7 | The measurement contract | Confirmed. |
| D-8 | Verdict by amendment with scoped re-sign-off | Confirmed. Task 9's boundary (worker drafts, human signs) is this decision applied to the task ledger. |
| D-9 | Attested release assets fetched into the data directory | Confirmed. The fail-closed reading (stop, print how to select shell; never auto-fallback) is the reading the decision's own rationale argues for. |
| D-10 | Strangler behind frozen entry points | Confirmed. The two-implementations-one-switch model was explained to and confirmed by the operator. |
| D-11 | Lock baseline: atomic create with owner token | Confirmed. Symlink versus noclobber is left to the executor; both are within the floor. |
| D-12 | Echo baseline: printf discipline with a lint guard | Confirmed. |
| D-13 | Platform matrix | **Amended** at this kickoff: repair-first, blocking from day one; the informational-until-green form moved to the rejected alternatives with the reason. |
| D-14 | Relative hook latency budget | Confirmed. |
| D-15 | The cost-benefit model | Confirmed. Porting-rate caveat carried to the risk register. |
| D-16 | Auditability criteria to doctrine; method stays in the spec | Confirmed. |
| D-17 | Prototypes are promotable | Confirmed. The Task 6 prototype-scope edit leans on it. |
| D-18 | Verdict-conditional tasks parked with free-text gates | Confirmed. Gates now name a *signed* verdict. |

**Reconciled ledger.** No decision contradicts a walked requirement.
Cross-cutting concerns (decision-domains walk, research triggers, the tier
boundary precedent, data hygiene) stand as written; the three survey risks
the design asks the register to carry from the start are carried in
section 7.

Signed off: 2026-09-09

## 5. Verification approach

**Coverage mix.** Per-tag tallies are derived from the tag suffixes in
`test-spec.md`, not copied here. The shape: most requirements are `[test]`
(shell suite under the check aggregate, or workflow jobs); the artifact-
shaped requirements (constraint profiles, screen record, breadth rule,
verdicts, doctrine restatement, cost-benefit lines) are `[design-level]`;
one entry is `[manual]` (the fresh-machine install, REQ-F1.5, owned by the
operator and recorded under `docs/`).

**Verification ownership.**

- `[test]` entries: `mise run check` locally and the CI workflow on every
  pull request, on every matrix platform once Task 4.1 lands. Owned by the
  executing worker at task time and by CI thereafter.
- `[design-level]` entries: the operator, at the scoped re-sign-off of the
  Task 9 verdict amendment, through `/spec-kickoff`.
- `[manual]` entry: the operator, at the review of Task 10's pull request,
  which records the fresh-machine install through both delivery modes.

**Dead paths checked.** Eight `[test]` entries, in seven rows below, named
a guard no task delivered. Disposition (operator-approved): each guard is now a deliverable
of the task that builds the thing it checks, and one new task holds the
guard nothing else naturally owned.

| Test-spec entry | Guard | Now delivered by |
| --- | --- | --- |
| REQ-A1.4 | number-copy guard | Task 3 |
| REQ-C1.5 | verdict figure matches a report field | Task 5 |
| REQ-G1.3 | verdict effort cites the logged rate | Task 5 |
| REQ-D1.2 | supersession annotation present, body unchanged | Task 9 (wording in the entry corrected from "the ledger guard", which is a `tasks.md` guard) |
| REQ-F1.1 | no top-level `bin/`, literal-path shim invocation | Task 10 |
| REQ-E1.4 | single implementation per named primitive | Task 13 |
| REQ-E1.2, REQ-A1.3 | entry-point guard | **Task 2.1 (new)**; Tasks 11 and 12 now depend on it |

The sign-off lens pass (section 8) then found four more entries whose
named guard exists but does not assert what the entry claimed; each is now
either delivered by a task or reworded:

| Test-spec entry | Was | Now |
| --- | --- | --- |
| REQ-B1.4 | "the workflow-posture guard" asserts the matrix jobs (it checks fork-PR security only) | Task 4.1 extends the guard with the job and blocking assertions |
| REQ-F1.2 | the same guard asserts the attestation step | Task 10's placement guard asserts attestation and NOTICE steps |
| REQ-D1.3 | "manifest and index guards pass over the restated line" (neither reads doctrine content) | retagged `[design-level]`; the normative-token check at re-sign-off is the verification |
| REQ-E1.1 | "the drain suite over this bundle" (the suite is fixture-only) | "over a fixture reproducing this bundle's six Deferred bullets" |

Entries that depend on parked tasks (REQ-F group, REQ-E1.3's differential
suite) are conditional by design and are not dead paths.

Signed off: 2026-09-09

## 6. Task graph

Reconstructed from the `Dependencies:` lines in `tasks.md`, which are
authoritative; effort weights are the `Estimated effort:` lines there.
The diagram below is derived and carries no information the lines do not.

```
wave 1 (no dependencies)      Task 1 (lock)   Task 2 (partition)
wave 2 (after Task 2)         Task 2.1 (entry-point guard)   Task 3 (attribution)   Task 4 (suite green on macOS/Alpine)
wave 3 (after Task 4)         Task 4.1 (matrix jobs, blocking)
wave 4 (after Task 4.1)       Task 1.1 (echo)   Task 5 (harness)
wave 5 (after 1, 1.1, 3, 5)   Task 6 (bake-off A)
wave 6 (after Task 6)         Task 7 (bake-off B; also after 5)   Task 8 (dev-check screen; also after 3)
wave 7 (after 6, 7, 8)        Task 9 (drafted verdicts)
--- human scoped re-sign-off of the verdicts (the gate, not a task) ---
parked, verdict-conditional   Task 10 (after 9)   Task 13 (after 9)   Task 14 (after 8, 9)
                              Task 11 and Task 12 (after 2.1, 9, 10)
```

**Parallelism.** Two independent starts (Tasks 1 and 2; Task 1.1 waits on
Task 4.1 per the edit below). After Task 2, three tasks run
side by side (2.1, 3, 4). After Task 4.1, Tasks 1.1 and 5 run side by
side. After Task 6, Tasks 7 and 8 run side by side.

**Effort-weighted critical path (pre-verdict).** Task 2 → Task 4 → Task
4.1 → Task 5 → Task 6 → Task 7 → Task 9. Sum the `Estimated effort:` lines
of those seven tasks for the figure; every other pre-verdict task has
slack against this chain. The Task 4 estimate is the low-confidence link
(repair scope unknown until the first run), so the chain's length is
itself a risk (section 7). Post-verdict, the longest conditional tail is
Task 10 → Task 11.

**Edit applied in this section.** Task 1.1 now depends on Task 4.1, so its
Done-when ("on the Alpine job") is checkable where it says; no
critical-path cost, since Task 6 waits on Task 5 in any case. Accepted
cost: the live echo fix lands a few days later than it otherwise could.

**Deliberate non-edges (do not "fix").**

- Task 1 and Task 1.1 do not depend on each other: disjoint sites, both
  feed Task 6.
- Task 2.1 (entry-point guard) does not gate Task 6 or Task 7: the guard
  protects migration, not measurement. It gates Tasks 11 and 12 only.
- Task 3 does not depend on Task 1 or Task 1.1: attribution reads the
  observations, not the fixed code.
- Task 5 does not depend on Task 3: the harness is candidate-agnostic and
  self-tests on a stub.
- Task 8 does not depend on Task 7: the dev-check screen needs the
  adopter-runtime measurements (Task 6), not the hook ones.
- Task 13 does not depend on Task 10: shell-verdict fixes need no delivery
  pipeline.
- Task 14 does not depend on Task 10: the dev-check tier runs where a
  toolchain exists, so a compiled dev-check substrate builds in CI rather
  than being fetched.
- No task depends on the human re-sign-off as a task: it is the gate the
  six Deferred bullets name (section 3, REQ-D decision).

**Reopened at sign-off (2026-09-09).** The lens pass found the edit above
created a loop: Task 4 needs the suite green on Alpine, the Alpine reds
include the echo class Task 1.1 cures, and Task 1.1 waited on Task 4.1.
The operator re-decided: Task 1.1 depends on nothing again and proves
itself under a local `dash`; Task 4 depends on Tasks 1, 1.1, and 2 and
re-runs the dash regression test on the Alpine job. The wave list and the
critical path above are read with that change: wave 1 is Tasks 1, 1.1,
and 2; wave 2 (after Task 2) is Tasks 2.1 and 3, and Task 4 once Tasks 1
and 1.1 land; the long chain is unchanged in membership except that Task
1 (its longer predecessor) precedes Task 4 in it.

Signed off: 2026-09-09

## 7. Risk register

Inputs: risks surfaced during the walk, the operator's cold-review
questions (both resolved into decisions in section 3: the repair-first
matrix, and the two-implementations-one-switch model), the three risks
`design.md`'s research triggers ask the register to carry from the start,
and the decision-domains gap check below. Every open question raised in
the walk was resolved into a decision; none is carried open.

**Decision-domains gap check.** Catalog resolved through the merged path
(`scripts/resolve-catalog.sh decision-domains`, core seed, no overlay
additions present). Domains the design's own cross-cutting walk already
decides: api-surface (D-10), concurrency (D-11), deploy-migration (D-10),
dependency-adoption (D-7), versioning-scheme (D-9), existing-seam-reuse
(D-9), data-storage and caching (D-4, D-9), secrets-config (the user-config
seam, D-9), auth (attestation not the only check, D-9), observability (the
fail-closed message, D-9; the harness report, D-7), llm-output-quality
(the human verdict gate, D-8), org-design (unpark and sign-off are human
acts, D-8, D-18), product-strategy (fires on the D-15 success metric and
is discharged by the D-8 human gate). Not applicable: packaging-pricing.
Touched but undecided at the walk, each a row below: queues-async (R8),
knowledge-engineering (R9), ip-posture (R10), human-comprehension (R11).
The sign-off lens pass's independent second walk found twelve further
undecided considerations on domains this paragraph had marked decided;
their dispositions are in section 8, and where they decided something the
rows above were updated in place.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| R1 | The Mac/Alpine repair (Task 4) is the low-confidence link on the critical path: its scope is unknown until the first run on each platform. | Task 4 records each root cause as an observation and escalates floor-forbidden fixes as Awaiting-input rather than patching around them. Early signal: the first CI run on each platform; a failure count in the dozens means the estimate is off by days, not hours. |
| R2 | The marketplace plugin copy is reported to strip execute bits with no visible fix, which bears on today's hook registrations as much as on any fetched artifact. | The fetch shim never assumes an execute bit (D-9); Task 4.1's smoke step installs through the marketplace copy and runs an entry point, so the stripping is a tested fact. Early signal: the smoke step on the first matrix run. |
| R3 | GitHub attestation verification may require authentication, so it cannot be the bootstrap's only check. | Decided: the pinned checksum is load-bearing, the attestation is a second layer (D-9). Early signal: Task 10's fixture-server test of an unauthenticated verify. |
| R4 | Every precedent surveyed kept a shell layer; the one capability a binary cannot recover is mutation of the calling shell. | The partition's shell-mutation flag (REQ-A1.1) must be clear on every entry point before any tier moves; Task 3's profiles say which side of the tier boundary precedent each surviving tier falls on. Early signal: a flagged entry point in the partition output. |
| R5 | The porting rate REQ-G1.3 logs is measured on the fleet's automated workers, so it predicts their effort, not a person's, and the review-findings field measures their code. | Recorded here so a verdict's effort figure is read as a fleet figure; the verdict's cost-benefit line names the population it was measured on. Early signal: a human-authored migration PR whose time diverges from the logged rate. |
| R6 | Fail-closed fetch on the hook tier blocks every tool call until the adopter flips the shell selector. | Accepted consequence of the REQ-F decision; the message names the selector; a session-start prefetch (D-9) makes an offline first use rarer. Early signal: adopter reports of a blocked session; Task 10's macOS first-execution job. |
| R7 | Rust cross-compilation to macOS needs an Apple SDK that licensing keeps off community images, while Go signs from a Linux runner. | Measured, not assumed: the D-7 contract records delivery per platform per candidate. Early signal: Task 6's per-platform pass/fail column for Rust on macOS. |
| R8 | *(queues-async)* A `SessionStart` prefetch is a network call on the session's critical path. | Decided at sign-off and homed in Task 10's deliverables: bounded timeout, never blocking session start, silent on failure with the fail-closed message deferred to first use, cleared by the hook-contracts guard. Early signal: session-start latency on the matrix. |
| R9 | *(knowledge-engineering)* The defect-class set and the tier vocabulary are fixed taxonomies every profile, screen, and verdict keys on. | Decided at sign-off: a new class is proposed as an Awaiting-input entry and added by amendment, never minted by the script (REQ-A1.2); a script matching two tier definitions takes the first in order, and a script whose tier changes after its verdict is signed blocks its migration until the human names the governing verdict (REQ-A1.1). Early signal: fragments landing in a catch-all during Task 3; a partition diff after Task 9. |
| R10 | *(ip-posture)* A static binary bundles third-party code, and a shipped asset carries a public name. | Decided at sign-off: a candidate whose dependencies carry a licence incompatible with planwright's outbound licence is screened out (REQ-C1.2); each release ships a NOTICE file generated from the dependency list; the release name is checked for trademark collision and escalated if not clean (Task 10). Early signal: the dependency listing in the Task 6 report. |
| R11 | *(human-comprehension)* The operator found the spec hard to follow at kickoff; the verdict amendment (Task 9) is a second comprehension-heavy sign-off. | Task 9's docs page is written for a reader without the spec open; the operator may run `/spec-walkthrough` before the re-sign-off; the re-sign-off walk keeps the one-decision-per-turn pace used here. Early signal: clarification requests during the re-sign-off. |
| R12 | The number-copy guard (REQ-A1.4) matches figure-shaped tokens and may false-positive on unrelated numbers in claim-making prose (`bash 3.2`, "twenty of twenty"). | Task 3 scopes the guard to values present in the snapshots, not any digit; an exemption list, if needed, lives beside the guard with a reason per entry. Early signal: guard noise on its first run. |
| R13 | Attribution of the mined set (several hundred fragments) is labour-intensive, and the manual pass for script-less fragments could silently shrink coverage. | Task 3's Done-when requires every UID in the Sources to appear in the matrix; the re-sign-off verifies it (test-spec REQ-A1.2). Early signal: the matrix's unattributed count after the first run. |

Signed off: 2026-09-09

## 8. Sign-off

### Lens review pass (first activation, full bundle)

Artifact class: **spec**; lens set per `doctrine/artifact-lenses.md`.
Path taken: parallel fan-out, one read-only sub-agent per lens (eight),
each briefed with the full bundle, the brief, and the day's diff; the
ninth lens (rendered-content safety) walked inline. Tool-grounded pass
first: `scripts/spec-validate.sh` (0 errors, 0 warnings after fixes) and
`markdownlint-cli2` (0 errors) over the five files. The coordinator
merged and deduplicated (a finding hitting two lenses carries both
labels), then ran the self-critique pass, which added the Alpine tooling
scope and the two loop findings to the decision set rather than the
mechanical set. Validation scoping, declared: every finding applied to
the bundle received the three passes (re-read as each consumer; grep of
the affected files for the rule's surface patterns; the repository and
doctrine as the outside source, which the agents' reports cite by path);
findings declined as executor latitude received the re-read and grep
passes only, since the operator's disposition finishes their validation.
The adversarial re-validation refuted none of the kept set and
resurrected one decline (the Windows out-of-scope naming) into the kept
set.

| Lens (spec set) | Findings | Notes |
| --- | --- | --- |
| Contract correctness and internal consistency | 26 | comparison-point split not propagated (4); dev-check screen-only branch missing (3); tests-only dissolution not propagated (2); artifact placement and invocation rules contradicting (5); task-graph loops and gates (5); guards pulling opposite ways (1); Windows naming (1); headers and changelog (2); attribution scope (1); baseline phase ownership (1); arithmetic (1) |
| Ambiguity and interpretation forks | 72 | 31 load-bearing forks pinned in the spec (tie-break, script definition, liveness of documentation, blocking, regression statistic, interpreted runtimes, candidate-class scope, correctness metric, version equality, offline switch, removal proposal, lock staleness and reentrancy, stderr class, PATH allowlist, and others); 41 declined as executor latitude, listed below |
| Citation and coverage integrity | 7 | D-2 uncited (now cited from the Changelog); D-3 and D-4 lacked amendment annotations (added); a Sources bullet cited D-7 for a lint field it has no analogue of (now D-12); two UIDs listed as live evidence were consumed by the lock class (noted); the Windows Deferred bullet omitted D-18 (added); Task 14's D-5 edge (kept, defensible). Derived counts: 33 REQs with 33 test-spec entries, 18 D-IDs, 17 tasks, 300 distinct observation UIDs all resolving by filename, 6 Deferred bullets |
| Dead verification paths | 20 | four named guards that exist but do not assert what the entry claimed (section 5 addendum); harness self-test assertions no task delivered (3, now Task 5); Task 3 test suite absent (added); REQ-A1.4's regeneration clause unrunnable as a standing check (dropped); REQ-D1.3's guards vacuous (retagged); verification moments after the event or outside the re-sign-off's scope (3, moved to the delivering PR's review or the re-sign-off checklist); mislabelled tag (REQ-B1.3); macOS quarantine premise (fixed); Alpine realization (container, scoped); parallel-suite mode unasserted (fixed); supersession baseline located (validator's baseline ref); manual entry owner and record (fixed) |
| Decision-domain gaps | 16 | twelve considerations on domains section 7 had marked decided, four beyond R8 to R11; all applied under the operator's group-A approval (cache key and eviction, atomic rename, reserved exit code, exact version and per-release builds, operator-owned selector, named options, licence screen and NOTICE, prefetch homed, review-findings normalisation and attribution sample, report snapshot and add-only schema, offline-replayability field, removal re-ask); product-strategy reclassified as fires-and-discharged |
| Testability of Done-when | 34 clauses | 11 not evaluable and 23 needing judgment, plus nine deliverables with no clause (five from the day's guard additions); every one reworded or given a clause in the rewritten `tasks.md` |
| Cross-file consistency | 23 | comparison-point and tests-only stragglers (12), coverage-mix paragraph (3), brief bookkeeping (4), repair-first ordering evidence (1), wrap damage (2), stale headers and changelog (2); all applied |
| Documentation and glossary drift | 26 | ten undefined terms (six now in the glossary, the rest pinned in the spec); four glossary-versus-bundle drifts (fixed); fifteen doctrine or repository references saying something other than the bundle attributed (fixed: full "Stay auditable" quote and a fifth criterion, data directory named per storage-classes, invocation per plugin-script-invocation, `SessionStart` spelling, the execute-bit observation added to the mined set, guard wiring and naming conventions, snapshot lint disposition, the doctrine-to-docs link rule); one structural note (this section was not yet written) |
| Rendered-content safety | n/a | the bundle is rendered by markdownlint and the spec tooling only; free-text gates are parsed by the drain pass as data with fixed-string matching, never executed; the brief contains no HTML |

**Altitude check (REQ-H1.3).** Triggered bundle: the Sources pin three
seed claims, the first an altitude claim. D-1 exists, is cited from the
goal, and the task decomposition matches capability altitude (Tasks 2, 3,
and 5 build the method; 6 to 8 measure; 9 decides; 10 to 14 are parked
mechanism). Pass.

### Dispositions

**Applied (operator-approved in three groups).** Group A, the twelve
compiled-program-path decisions, applied to REQ-C1.2, REQ-C1.4, REQ-C1.5,
REQ-E1.3, REQ-F1.1 to REQ-F1.4, REQ-G1.3, D-9, D-10, and Tasks 5, 9, 10.
Group B, the mechanical set: comparison-point and surviving-tier
propagation across all four files; amendment annotations on D-3, D-4, D-5,
D-7, D-9, D-10, D-11 and the D-13 and D-16 rewordings; the citation fixes
above; finish-line clauses for every guard and deliverable that lacked
one; the load-bearing wording pins; the four dead-path repairs; the
Changelog entry; `Last reviewed:` bumped at the flip below. Two decisions
taken at sign-off rather than mechanically: the Task 4 loop (lock and
echo fixes first, then the repair; section 6 addendum) and the Alpine job
scope (shell suite, harness, and smoke step inside a stock Alpine
container; other steps Ubuntu-only and named).

**Declined, executor latitude (41 ambiguity items).** Each is a precision
the executing worker can settle without a policy call, escalating as an
Awaiting-input entry only if two readings would produce different
deliverables. The set, by task: the isolated-run definition and the
exact `mkdir` pattern the lock lint matches (Task 1); the `# trusted:`
annotation's grammar (Task 1.1); which file kinds count as documentation
beyond Markdown, and the fixture-capture mechanism (Tasks 2, 2.1);
snapshot filenames, the attribution file's format, the frozen-log line
identifier scheme (Task 3); the branch-filter mechanism for the two jobs
(Task 4); the run-count value, the trivial program's content, the report
and rendered-view formats, the timeout value, the run-identifier form
(Task 5); the copy-count metric's tie-break, the screen record's layout,
the "fifth of the fixtures" threshold's rounding (Task 6); the vector
enumeration format (Task 7); the screen outcome vocabulary (Task 8); the
checklist's layout and the docs page's structure (Task 9); the option
names, the message text, the NOTICE format, the release-name check's
method (Task 10); the parity file's format and the removal plan's shape
(Tasks 11, 12); the time-anchored list's format (Task 13); the extended
guard's construct list beyond the four named (Task 14); and, in the
requirements, the exact spread statistic (REQ-B1.5), the "auditability
weight" rubric behind high, medium, and low (REQ-B1.2), the source-size
unit for a compiled prototype (bytes of sources, as stated; binary size
is a comparison-point field), the "as of" date of the bootstrap tool set
(the bundle's sign-off), and the hand-back attribution rule's evidence
form (REQ-G1.1).

**Declined with rationale (2).** Task 14's citation of D-5 stays: D-5
supplies the inherited or screen-settled verdict Task 14 satisfies. The
pre-existing over-long heading and link lines in the four files stay: the
scoped markdownlint config exempts spec bundles from the column limit.

**Post-lens stale-reference sweep.** The pass re-scoped REQ-A1.1, A1.2,
A1.3, A1.4, B1.1, B1.2, B1.4, B1.5, C1.1 to C1.6, D1.1, D1.3, E1.2, E1.3,
E1.4, F1.1 to F1.4, F1.6, G1.1 to G1.4 (no REQ minted or removed; the
REQ set is unchanged at the count section 5 cites). The sweep grepped
the four files and this brief for the surface patterns of every changed
rule (the section 8 table's "cross-file" row); the brief's sections 2, 3,
5, 6, and 7 were corrected in place where they carried the pre-edit
reading (glossary entries, the coverage mix, the dead-path table, the
task-graph addendum, risk rows R4, R8, R9, R10, and the gap-check
paragraph), each correction marked as made at sign-off.

**Recorded-claim re-derivation (REQ-B1.3).** Claims this section records
as evidence, re-derived mechanically before the flip with fixed-string
matching over the bundle as data: 33 REQ bullets in `requirements.md` and
33 `### REQ-` headings in `test-spec.md`, set-identical; 18 `### D-`
headings; 17 `### Task` headings; every REQ cited by at least one task
`Citations:` line; every D-ID cited by at least one REQ or task; test-spec
tag tally 19 `[test]`, 8 `[design-level]`, 5 `[test + design-level]`, 1
`[test + manual]`; 6 `**Gate:**` lines under Deferred. Match.

**Expression-only normalisation at sign-off.** The status render flagged
the drafted `Dependencies: Task n` form (the format's grammar is bare
task ids); all seventeen lines were normalised to bare ids after the
flip, with no change to any edge. The Changelog entry above covers it.

### Sign-off record

Signed off by the operator on 2026-09-09 after the shared-understanding
approval summary (the walk's eleven decisions, the design ledger, the
verification ownership, the task graph with its loop untangled, thirteen
risks, and the lens pass's dispositions), with the plain-language gate
framing: the lens pass above as the last review of the spec itself; the
anchor below as the fingerprint of the exact spec bytes signed, so
execution refuses a drifted spec; the CI gate on the spec PR's head
commit before it is offered for merge. Draft→Ready flipped and
`Last reviewed:` set to 2026-09-09 on all four files; the validator ran
clean at Ready (0 errors, 0 warnings) and the status render derives Ready
with the five parked tasks and the Windows opportunity deferred.

Class: meaning
Lens-pass: section 8, "Lens review pass (first activation, full bundle)"
Anchor: `cc916e12057c4fa437c4fdc825cf0fd6e7c4be71` — computed as
`scripts/spec-anchor.sh specs/universal-binary`

## 9. Amendment log

(none yet)
