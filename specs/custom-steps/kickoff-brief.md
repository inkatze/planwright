# Custom steps — Kickoff brief

## 1. Header

- **Spec path:** `specs/custom-steps`
- **Spec commit at walkthrough start:** `200bde5`
- **Walkthrough date:** 2026-09-22
- **Mode:** first activation (Draft, no prior brief)
- **Validator outcome (pre-flight):** `spec-validate.sh` — 0 errors, 0 warnings
  (format-version 2 bundle)
- **Config:** `commit_on_kickoff: true`,
  `mark_spec_pr_ready_on_kickoff: true`, `kickoff_ready_ci_wait: 10m`
  (defaults; no local override present)
- **Working location:** spec branch `planwright/custom-steps/spec`,
  worktree `.claude/worktrees/custom-steps`
- **Doctrine resolution:** all nine rule docs the skill names resolved under
  the installed plugin's `doctrine/`; the decision-domains catalog resolved
  through `scripts/resolve-catalog.sh` (core seed, no overlay layers present)
- **Decision/transcript log:** no harness-provided log path in this session;
  the structured-log mirror is skipped, per `interaction-style`'s turn-mirror
  rule (never improvised into the repository)
- **Independent cold read:** `/spec-walkthrough specs/custom-steps` offered as
  an optional complement; not a dependency of this walkthrough

## 2. Goal & glossary

**Restatement (agent's own words, confirmed by the operator).** Today the
only place an operator can plug a review into a unit's run is the
review-sequence knob, and it admits only planwright's own nested skills, so
the operator's panel and Copilot passes are typed by hand after the fact or
skipped, and a ready-flip can fire before they ran. This spec replaces that
one knob with named moments in a unit's run (six wired in `/execute-task`,
one in `/spec-kickoff`), a catalog of step definitions merged across the
four overlay layers, and one flat ordered list per moment. A step is a skill
or user command, a shell command, or a prompt; it declares where it runs (a
fresh session, the previous step's session, or the unit's own), what happens
when it fails, and optionally a timeout and the executables it needs.
Everything resolves and prints with provenance before anything runs; a
declared step that cannot run is handled by which layer declared it and
whether a human is present. Core ships behavior-identical (convergence is
`[polish]`, every other list empty). The operator's own gauntlet stays in
their overlay.

**Rules out.** Deciding who may flip a task PR ready; merge; shipping panel
or Copilot wrappers in core; fixing machine-local configuration not reaching
worktrees; the orchestrator-side and pipeline-side points; per-spec and
per-task-type lists; parallel steps; re-running earlier points when a later
step moves the head; editing the operator's review commands or any step's
internal loop; steps editing signed spec content outside the amendment
ritual.

**Assumes.** The constrained catalog reader and `resolve-catalog`, the flat
config reader (`config-get`) with its by-layer malformed policy, the
per-step session launch through the backend seam with recorded session ids,
the allocation knobs' open step-id key space, the ready-guard and worker
permission denies, and the gate-wiring PR-body assembly all exist and fit
as-is.

**Implicit terms, resolved.**

- *Unit run* — one `/execute-task` invocation. A later re-execution against
  a unit that already has an open PR is a new run and fires the in-run
  points again (`post-pr` after the body is regenerated). Derived from
  REQ-A1.1's "once per unit run"; confirmed by the operator.
- *The runner* — the hosting skill session plus the scripts it calls
  (resolver, record helper); there is no daemon or separate process.
  Derived from D-9; confirmed by the operator.
- *Attended* — the existing gate-wiring distinction (an interactive session
  with a human at the prompt versus a dispatched or unattended worker); the
  skill passes it to the resolver as `--attended` or `--unattended`.
  Derived from Task 2 and gate-wiring's pause protocol; confirmed by the
  operator.

**Implicit terms carried to section 3** (each decided with its REQ group):

1. *Predecessor session* — what `continue` attaches to when the immediately
   preceding step was a command step run as a runner subprocess, which
   records no session id. REQ-D.
2. *Plugin skills root* — whether a namespaced skill target from a plugin
   other than planwright resolves, and where. REQ-C.
3. *Agent-issued flip* — how `steps_pre_ready_flip` binds a tower session
   that flips a unit PR by hand, given no in-repo flipper of unit PRs
   exists. REQ-E.

Signed off: 2026-09-22

## 3. Requirements walkthrough

### REQ-A — Named attachment points

Intent confirmed: seven wired moments, eight named-but-unwired ones with a
resolver warning, a fixed context set, one normative rule doc. Recorded
without a spec edit: for a spec-kind unit the task-ids field is empty and
the base branch is `main`. No decision needed.

### REQ-B — Step declaration

Intent confirmed. Probe: declarations the resolver can see are
un-honorable from the entry and list alone. **Decision (operator):** refuse
all three at resolution under the by-layer malformed policy, the same
treatment as a first-position `continue`: a `continue` immediately after
an `isolated` command step (carried term 1: a runner subprocess records no
session), `timeout` on an `in-session` step, and `args` on a `prompt`
step. Grounded in REQ-D1.9 (a point resolves whole before any step runs)
and D-18's determinism. The mid-walk lens pass added: a `continue` after an
`in-session` step attaches to the unit's session; `args` is a sequence of
plain words with no shell operators, expansions, or quoting, so a declared
line is one simple command.

### REQ-C — Resolution

Intent confirmed. Probe: a skill target with a plugin namespace other than
planwright's had a grammar (REQ-B1.6) but no resolution rule (REQ-C1.3).
**Decision (operator, against the agent's first recommendation):** resolve
it through Claude Code's installed-plugin registry to the plugin's install
path (D-19). The agent had recommended planwright-only resolution on
proportionality; the operator's objection, that planwright is a plugin for
adopters and marketplace-installed skills are a class of users rather than
a case a seed must record first, withdrew that grounding and the
recommendation. The lens pass added the edge rules: the registry is the
only source, an ambiguous namespace or an absent registry or reader makes
the target non-resolving under the matrix, never an error.

### REQ-D — Execution contract

Intent confirmed. Probe: a pushing step at a flip point moves the head the
point was run on. **Decision (operator):** the flip targets the head the
list ends on, and the flip's own gates check that head (REQ-E1.3), applied
uniformly to both flip points from D-3's spec-PR wording. Lens-pass
additions: REQ-D1.4 covers a skipped or session-less predecessor; REQ-D1.6
names the four no-push points instead of ordering against `post-pr`, which
the kickoff lifecycle lacks; REQ-D1.7 notes that an `in-session` step
carries no timeout.

### REQ-E — The review points

Intent confirmed. Probe (carried term 3): REQ-E1.3's SHALL bound a hand
flip only by memory, since no in-repo flipper of unit PRs exists and the
tower profile denies the ready command outright, so today's unit flipper is
the operator's own session. **Decisions (operator), in sequence:**

1. Enforcement by evidence at the flip's chokepoint, rather than doctrine
   only or a future tower skill.
2. The evidence lives server-side: the agent first recommended a
   worktree-cache record, then withdrew it on reading the ready-guard's
   no-local-state contract (merge-currency-guard D-5); the PR-body table
   was the next candidate; the operator asked about a commit marker, and a
   commit status on the head SHA was chosen over a marker commit (moves the
   head) and a git note (not served).
3. After the mid-walk lens pass: the check lives in a separate
   deny-emitting hook this bundle owns, on both flip surfaces, leaving
   `ready-guard.sh` and merge-currency-guard REQ-A1.2 / REQ-C1.1 as signed;
   and it lands only once a unit-PR flipper that runs the point exists
   (gated under Deferred), because landing it now would deny every task-PR
   flip with nothing to satisfy it. The status verb and kickoff's posting
   land now.

Recorded in D-20: the evidence is written by the actor it binds, so the
hook guards a flipper that forgets, not one that forges. Also from the
lens pass: the flip-point contexts are excluded from every CI rollup
judgement (the kickoff gate's empty-rollup protection would otherwise count
our own status as a completed check); the branch predicate is `planwright/`
so flight branches are covered; "agent-issued" became "in-session", the
only distinction a hook can make.

### REQ-F — Replacement of the review-sequence knob

Intent confirmed, no edit. Carried to the risk register: under
last-layer-wins an adopter list cannot extend a repo-tracked list, so this
repository's gauntlet is restated in the repo-tracked layer naming a step
whose catalog entry lives in the operator's adopter layer (REQ-H1.2's
worked example); a contributor without that entry parks unattended runs.

### REQ-G — Security and permissions

Intent confirmed. Probe: REQ-G1.3's first-token match approved every
invocation of a declared executable. **Decision (operator):** match the
whole declared line. The lens pass refined the predicate to what the guard
can compare, the tokenized word sequence per segment against target plus
`args` as written, with the charset and containment checks on the resolved
target; REQ-B1.6 and REQ-G1.1 pin a declared line to one simple command
executed as argv, so the guard, a shell, and the runner agree on its
words; the guard consults declarations only for a segment not already
known-safe, within its existing bound.

### REQ-H — Documentation, tooling, and guards

Intent confirmed, no edit.

### Consolidated spec edits (applied in this section, Draft, unsigned)

1. REQ-B1.2, REQ-B1.4, D-7, test-spec REQ-B1.2 and REQ-B1.4: the three
   static refusals and the `in-session` predecessor rule.
2. REQ-B1.6, REQ-G1.1, test-spec REQ-G1.1: `args` as plain words, argv
   execution.
3. REQ-C1.3, new D-19, Task 2, test-spec REQ-C1.3: registry-based
   namespace resolution with its edge rules.
4. REQ-D1.4, REQ-D1.6, REQ-D1.7, test-spec REQ-D1.4 and REQ-D1.6: the
   lens-pass edge cases above.
5. REQ-E1.3: the moved-head rule; "authorizes no flip" reworded to add the
   one precondition.
6. New REQ-E1.5, new D-20, Task 9 (the status verb, half day), Task 6
   (posts the status, excludes the contexts from the CI gate, depends on
   9), Task 1 (the outcome-to-status mapping in the rule doc), a new
   Deferred entry (the flip-evidence hook, gated on a unit-PR flipper),
   the In-scope bullet, the Out-of-scope rewording, test-spec REQ-E1.3 and
   REQ-E1.5.
7. REQ-G1.3, D-11 (two more rejected alternatives), Task 7, test-spec
   REQ-G1.3: the word-sequence match and the runtime bound.
8. REQ-D1.3 and Sources: the step-isolation citation retargeted from
   bootstrap D-5 (act-then-review autonomy, no isolation there) to
   orchestration-fleet D-5, the knob's actual home; an orchestration-fleet
   Sources entry added; merge-currency-guard's entry gains D-5, REQ-A1.2,
   REQ-C1.1.
9. Enumerated counts in Task 7, Task 9, and test-spec REQ-E1.5 and
   REQ-G1.3 converted to rules ("every row the deliverable names"); the
   tasks.md intro gains the status-before-hook ordering; the Changelog
   entry records the kickoff edits.

### Mid-walk delta lens pass (applied edits, 2026-09-22)

**Scope and path.** Delta-scoped per `kickoff-verification`: the seven
walk edits and what depends on them, run as one read-only sub-agent on the
verification tier briefed with the diff, the four files, the guard and
registry scripts, and the merge-currency-guard, bootstrap,
orchestration-fleet, and tower-front-door bundles. Validator and lint were
clean before and after. Findings were validated a second way against the
scripts and bundles they cite before disposition (the misattributed
citation, the tower profile's deny, the rollup's `StatusContext` handling,
and the flight branch form were each confirmed by reading the source).

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 11 | The kickoff CI gate counting our own status; D-20 vs Task 9 on the guard's read count; the guard-match predicate (resolved vs written target, bytes vs words, shell vs argv); `continue` after `in-session` or a skipped predecessor; the registry lookup overstated; "agent-issued" unevaluable by a hook; which repository holds the status |
| Security | 3 | The evidence is forgeable by the actor it binds; an unamended override of merge-currency-guard REQ-A1.2 / REQ-C1.1; the posting channel unstated |
| Error handling and failure modes | 6 | The Task 6 / Task 9 cycle and ordering hazard; no unit-PR flipper to post; registry degradation; the head branch name missing from the guard's read; the adopter arm |
| Performance | 2 | A third network read in a PreToolUse hook; per-call step resolution in the worker guard |
| Concurrency / state | 2 | The poster reading the worktree cache D-20 rejected for the reader; latest-wins status semantics |
| Naming, readability, structure | 3 | Two over-long body lines; two vocabularies for one state |
| Documentation | 4 | Scope silent on the guard change; "authorizes no flip" no longer true; the tasks intro ordering; the changelog |
| Tests / verification | 5 | A count contradicting its own list; four enumerated counts against the decided-rules rule; the unit half unnoted; the MCP surface uncovered; the failure path |
| Cross-file consistency | 6 | `bootstrap D-5` misattributed; REQ-C1.3 vs D-19 scope; the Sources entry; REQ-D1.7; the no-push ordering undefined for kickoff; flight branches outside the grammar |

Raw findings: 42; the per-lens detail is in the run's sub-agent report and
summarised above.

**Dispositions.**

- *Operator's judgment, the check's home:* a separate evidence hook this
  bundle owns rather than an amendment to merge-currency-guard or dropping
  the check (D-20, REQ-E1.5).
- *Operator's judgment, the check's timing:* deferred behind a unit-PR
  flipper gate; the status verb and kickoff's posting land now (Task 9
  re-scoped, Task 6, the Deferred entry).
- *Applied as one cluster:* every remaining finding with a single fix,
  listed under the consolidated edits above.
- *Declined:* none.
- *Deferred to a named backlog:* none.

Signed off: 2026-09-22

## 4. Design walkthrough

No fork surfaced; the ledger is bookkeeping, recorded and reported rather
than asked. Every decision heading in `design.md` is accounted for:

- **Confirmed, rationale intact:** D-1 through D-6, D-8 through D-10,
  D-12 through D-18.
- **Amended in place during section 3 (Draft, no annotation ritual):**
  D-7 (the session-less and `in-session` predecessor rules for
  `continue`), D-11 (word-sequence matching, two more rejected
  alternatives), D-13 (one word: "in-session" for "agent-issued", the
  distinction a hook can evaluate).
- **Minted at kickoff (origin tag `K`):** D-19 (registry namespaces),
  D-20 (the separate evidence hook and the flip-point status).
- **Superseded:** none.

Cross-check against the walked requirements: no decision contradicts a
requirement; D-9's "kickoff loads no new doc" still holds (Task 6 adds a
script call and a status post, no point-of-use doc); D-16's worktree-cache
records are what the status verb reads, with the flipper running the point
in that worktree (D-20). The altitude decision D-1 is cited from the goal,
and the task decomposition matches it (doctrine in Task 1, mechanism in
Tasks 2, 4, 7, 9, wiring in Tasks 5 and 6, guards and docs in Tasks 3 and
8); the sign-off pass re-runs that check formally.

*Amended at the sign-off lens pass (section 8), in place, the bundle
still Draft:* D-1 (a fourth rejected alternative, the host's own hook
seam), D-2 (the unit-PR flip point defined rather than wired; vocabulary
ownership), D-3 (`pre-ci` before the first CI run; the convergence order
resolve, sync, steps; the spec flip point fires whether or not the flip
follows), D-4 (single-line scalars, the empty list), D-5 (the per-layer
read mode), D-6 (the decision tokens, explicit attendance, the by-layer
split for lists and entries, a third rejected alternative), D-7 (the
invocation mechanism per kind and mode, the `isolated` degradation arm,
the one-directional tier rule), D-8 (five outcomes, the runner as
classifier, the `applied` discriminator, the trust extended to the flip
evidence, a third rejected alternative), D-10 (the transitional line
through the upgrade window, a fourth rejected alternative), D-11 (the
trust boundary the profile actually provides, the context-assignment
stripping, two more rejected alternatives), D-12 (the checklist and
tables regenerate, not the judgment-applied audit record), D-13
("agent-issued" kept for the obligation, the "unit" widening named),
D-14 (inherited environment, the preamble's owner), D-15 (the timed-out
session's stop), D-16 (the pinned cache path and ignore line, bounded
excerpts, the latest attempt), D-17 (the four no-push points, the literal
pipeline-entry list), D-19 (several keys versus several paths), D-20 (a
checkout of the head branch, the branch-to-context mapping, the fork and
mutation arms, the recovery path). The section 4 tally above is
superseded by this list; every decision heading remains accounted for and
none is superseded.

Signed off: 2026-09-22

## 5. Verification approach

**Coverage mix.** Derived from the tags on `test-spec.md`'s entries (the
counts live there; the shape here): most entries are `[test]`, run by the
resolver, record-helper, guard, and release-lib test scripts and by the
repository's existing check tasks; the skill-wired behaviors are
`[Gherkin]`, exercised by the executing worker with a fixture overlay on
the terminal rung and recorded in the PR body; rules whose presence in a
doc or row is the verification are `[design-level]`; one entry is
`[manual]` (REQ-D1.3's `isolated` and `continue` hosting on a stream-json
worker, which needs a live session-grade backend).

**Ownership.** `[test]` entries run under `mise run check` locally and in
the repository CI on every task PR; every check task a Done-when names
exists in `mise.toml` today except `check:steps`, which Task 8 adds, and
every existing test a Done-when names exists under `tests/`
(`test-converge-sync-main.sh`, `test-spec-kickoff-pr-ready.sh`,
`test-spec-kickoff-ready-flip.sh`, `test-worker-command-guard.sh`,
`test-permission-matcher.sh`, `test-ready-guard.sh`,
`test-release-lib.sh`, the allocation tests); `test-check-steps.sh`,
`test-resolve-steps.sh`, and `test-step-record.sh` are new. `[Gherkin]`
scenarios are run by the worker executing the task with a fixture overlay
in the adopter layer, and their outcome recorded in the PR body's audit
block. `[manual]` is swept by the operator on the Task 5 PR and recorded
in its body. `[design-level]` entries are verified at review of the owning
task's PR.

**Dead paths, stated honestly.** Three requirements cannot be exercised
end to end in this bundle and say so in their entries: REQ-E1.3 and the
unit half of REQ-E1.5 (no unit-PR flipper exists; the hook that would
enforce them is gated under Deferred, and until it lands the rule doc is
the verification), and REQ-F1.5 (no flight skill ships; the first one
cites the rule). No entry names a check or test that does not exist.
*Amended at the sign-off lens pass:* the pass found and fixed Done-whens
naming the wrong test file (the guard's rows in the permission-matcher
test, kickoff's ready-flip test for a change only the PR-ready test sees),
a manifest check that does not look at `/execute-task`, a release-lib
assertion with no deliverable, an allocation case already covered, and
two `[test]` tags with no automation behind them; each entry now names the
file that can carry it.

Signed off: 2026-09-22

## 6. Task graph

**Edges, from the `Dependencies:` lines** (authoritative; any diagram is
derived): Task 1 has none; 2 and 4 depend on 1; 3 and 7 depend on 2; 8
depends on 2 and 3; 9 depends on 4; 5 depends on 2, 3, and 4; 6 depends on
2, 3, 4, and 9.

**Parallelism.** After Task 1: Tasks 2 and 4 in parallel; Task 9 as soon
as 4 lands; Tasks 3 and 7 as soon as 2 lands; Tasks 5, 6, and 8 once 3
lands (6 also needs 9). Three lanes at the widest point.

**Critical path** (from the `Estimated effort:` lines): Task 1, then 2,
then 3, then 5; the sum of those four efforts is the bundle's floor, with
Task 6 and Task 8 short enough to finish inside Task 5's window.

**Deliberate non-edges**, so nobody "fixes" them later:

- Task 9 (status verb) does not depend on Task 2 (resolver): the verb
  derives state from records alone.
- Task 4 (records) does not depend on Task 2: records are written by the
  runner, not resolved.
- Task 7 (worker guard) does not depend on Task 3: it reads catalogs and
  lists through the resolver, which Task 2 supplies.
- Task 6 does not depend on Task 5: the two skill wirings are independent
  and each carries its own compensating trim.
- The flip-evidence hook is a Deferred entry, not a task, and must never be
  wired before a unit-PR flipper posts the status (the ordering hazard the
  lens pass found).
- Task 9 does not depend on Task 6: the verb is what Task 6 calls, so the
  edge runs the other way (the cycle the sign-off pass removed).
- Task 2 owns the point keys in the core defaults, not Task 3: Task 2's
  first Done-when reads them, and Task 3 only removes the old key (the
  wrong-direction dependency the sign-off pass found).

Signed off: 2026-09-22

## 7. Risk register

Inputs: risks surfaced during the walk, the mid-walk lens pass, and the
decision-domains gap check (the core seed catalog, resolved through
`scripts/resolve-catalog.sh`; no overlay layers present). Domains the spec
touches and decides: secrets and configuration (REQ-B1.5, REQ-H1.1),
authorization (REQ-G, D-11), concurrency (D-18 serial only), deploy and
migration (D-10's warning, the deferred hook ordering), existing-seam reuse
(the catalog reader, `config-get`, the allocation knobs, the guard hook
matchers), human comprehension (REQ-C1.2 provenance, REQ-D1.5 counts at the
turn). Domains touched but undecided became rows 8 to 10.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | An adopter-layer list cannot extend a repo-tracked list (last layer wins), so this repository's gauntlet must be restated in the repo-tracked layer naming a step whose entry lives in the operator's adopter catalog; a contributor without that entry parks every unattended unit. | Accepted: a project step is the team's policy of record (D-6). Early signal: a unit parked to Awaiting input naming the panel step on a machine without the entry. |
| 2 | The machine-local layer is invisible from worktrees, so the per-user layer that reaches workers is the adopter layer (cited constraint, owned by customization-overlay). | Documented in the overlay docs (Task 3). Early signal: a machine-local step list that never fires in a worker. |
| 3 | D-19 depends on the shape of Claude Code's installed-plugin registry, which Claude Code can change without notice. | The resolver degrades to non-resolving under the matrix, never an error (REQ-C1.3). Early signal: every namespaced step skipping or parking at once after a Claude Code upgrade. |
| 4 | Until the flip-evidence hook is un-gated, unit-PR flips are bound only by the rule doc; and once it lands, the evidence is written by the actor it binds (a forgetting guard, not a forging guard). | Accepted and recorded in D-20. Early signal for the gate: a unit-PR flipper landing (issue 379, tower-front-door). |
| 5 | Tasks 5 and 6 edit skills pinned near their instruction-budget floors; the kickoff closure is measured at zero slack, so Task 6's trim must be word-neutral or better. | Each skill edit lands with its compensating trim (D-9); `check:instructions` is in every Done-when. Early signal: that check failing on the Task 6 PR. |
| 6 | A skill or prompt step's outcome is classified by the hosting session from the handoff (D-8), a model judgment made load-bearing: a misread handoff can pass a step that halted. | The record carries the excerpt the classification rests on, folded into the PR body for review. Early signal: an excerpt that disagrees with its outcome in a PR audit block. |
| 7 | A `continue` step is only realizable on session-grade backends; on the terminal rung it fails by design (REQ-D1.4). | Accepted; the resolver's provenance output shows hosting before anything runs. Early signal: a `failed` record naming the backend on a rung the operator expected to resume. |
| 8 | Gap check, API surface: the step entry format and the ten-field context set are new external surfaces with no versioning or compatibility rule; a later added field or variable is a format change with no declared posture. | Accepted for this bundle: additions are backward compatible by construction (unknown fields are malformed only in the entry, never in the context). Early signal: a second bundle adding a field or variable, which must then decide the posture. |
| 9 | Gap check, data storage: step records accumulate in the worktree cache across re-runs with no retention rule. | Accepted: the cache is untracked and the regenerate verb reads by range, not by presence. Early signal: a `list` output mixing runs. |
| 10 | Gap check, observability: a status post that fails silently would strand the human evidence and, once the hook lands, block the flip with no reason visible. | Decided at kickoff: a failed post ends the flip attempt without a flip, surfaced like a failed step (REQ-E1.5). Early signal: an Awaiting-input entry naming the post. |
| 11 | The worker guard resolving declared steps at hook time on every Bash call could stretch the guard past its runtime bound. | Bounded by REQ-G1.3: declarations are consulted only for a segment not already known-safe, within the existing bound; Task 7's Done-when asserts it. Early signal: worker Bash calls slowing after a catalog is added. |

| 12 | This repository's units run the installed plugin, so between Task 3 merging and the next release being installed, a migrated config would silently converge through the old resolver's core fallback. | Decided at the sign-off pass: the old key stays beside the new one with a dated comment until the release is installed, removed under a gated Deferred entry (REQ-F1.2). Early signal: the stale-key warning on every unit run here. |
| 13 | Posting a commit status is planwright's first status write; a login without that permission turns the kickoff flip into a stop. | REQ-E1.5 names the permission in the documentation and the verb's failure message; a failed post ends the attempt visibly. Early signal: an Awaiting-input entry naming the post on the first kickoff after upgrade. |
| 14 | The ready-guard's accepted residual (the raw GraphQL mutation) is a flip surface neither the currency guard nor the evidence hook sees. | Inherited and named in Scope; no new mechanism. Early signal: a ready PR with no flip-point status and no hook denial in the session log. |
| 15 | A timed-out `isolated` or `continue` session on a backend without a stop keeps running after the runner moved on and may push. | REQ-D1.7 stops the session where the backend exposes a stop and records which arm applied; the ready-guard's currency check and the post-pr draft verification cover a late push. Early signal: a record naming the stopped-waiting arm. |
| 16 | The flip-point statuses are visible to the adopter's own status-consuming tooling, and a config written for a newer planwright hard-fails an older install in the repo-tracked layer. | Documented (REQ-H1.2, the cross-cutting note): upgrade the plugin before the config. Early signal: a repo-tracked hard-fail naming an unknown field right after a config change. |

*Amended at the sign-off lens pass:* row 5's "zero slack" is corrected to
what the instruction-budget guard's audit reports (tens of words of slack
above each pinned margin; Task 6's edit is charged to the kickoff closure
for both files it touches); row 6's classifier is the runner, and D-8 now
records that the flip-point status extends that trust; row 7's condition is
a predecessor session the backend cannot resume, not the terminal rung as
such, on which an explicit `isolated` step degrades and records it; row 8
holds in one direction only (a newer config breaks an older install, row
16). Rows 12 to 16 came from the sign-off pass.

The operator's cold review added no row. No open question remained at
sign-off.

*Appended at Task 1 execution (2026-09-24):*

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 17 | The rule doc, complete against every rule the spec assigns it, measures past the execute-task closure headroom the cross-cutting note assumed (the doc's word count against the guard's reported closure margin, both read from `check:instructions --audit` on the Task 1 branch), so Task 5 cannot load it point-of-use at the current budget with its own additions funded only by the convergence trim. | Queued as a fork on the Task 1 PR: a closure raise sized to the doc (tower-comms D-13's precedent), a deeper Task 5 body diet, or trimming the doc's delegable detail into the script usage headers. Early signal: `check:instructions` failing the execute-task closure on the Task 5 branch. Recorded as obs:d6406add. |

Signed off: 2026-09-22

## 8. Sign-off

### Lens review pass (full bundle, first activation)

**Scope and fan-out.** Full bundle, artifact class **spec** per
`artifact-lenses` (the spec lens set, selected before the walk): one
read-only sub-agent per lens on the verification tier, nine in parallel,
each briefed with the five files, the scripts and sibling bundles the
claims rest on, and the mid-walk pass's dispositions, followed by a merge
and dedupe. Findings were validated a second way by each reviewer against
the scripts, tests, sibling bundles, and issue bodies they cite, and the
load-bearing ones a third time by this session before disposition (the
worker profile's allow block, the installed-plugin dogfooding path, the
release-lib rollup arms, the two guard tests' contracts, the kickoff gate's
positive-green rule). The kickoff-specific altitude check ran inline: the
Sources pin two altitude claims (issue 383's "narrow by construction",
obs:87570535's "the general mechanism is missing", the attribution fixed
by this pass), D-1 is cited from the goal, and the task decomposition
matches the claimed altitude (doctrine in Task 1, mechanism in Tasks 2, 4,
7, 9, wiring in Tasks 5 and 6, guards and docs in Tasks 3 and 8). Not a
finding. The ship-gate check ran inline: every out-of-band item the bundle
names carries a record (the evidence hook and the transitional line as
gated Deferred entries; the worktree config gap, the parser continuation
defect, the glossary widening, and the gate-phrasing sweep as observation
fragments). Not a finding.

| Lens | Findings | Notes |
| --- | --- | --- |
| Contract correctness and internal consistency | 22 | The unit-PR flip point declared wired with nothing wiring it; the attended-core matrix cell decided both ways; an id with no entry between two policies; skipped steps outside the closed outcome set yet feeding the flip status; session-hosted command steps unable to receive context under the exact-match guard; Task 3's grep unsatisfiable at Task 3 |
| Ambiguity and interpretation forks | 22 | The resolver's output, attendance default, and exit codes unpinned; how a skill step is invoked per hosting mode; what the preamble is and who renders it; records selected by a head they never carried; the shadow warning needing per-layer reads the config reader lacks; the malformed-entry degrade target; the step-id charset versus the knobs' |
| Citation and coverage integrity | 21 | D-15 and D-18 cited by no task; Task 1's citations omitting the REQs its Done-when names; fleet-autonomy REQ-F1.3 and model-allocation D-8 misattributed; issue 383 credited with an observation's quote; obs:00dccd4e cited for a timeout rule it does not record; two consumed fragments cited nowhere; D-9's figures on two baselines |
| Dead verification paths | 12 | The guard's rows in a test that never runs the guard; kickoff's ready-flip test for a change only the PR-ready test sees; a manifest check that ignores `/execute-task`; a release-lib assertion with no deliverable; the converge-sync test's anchor deleted by Task 5; REQ-F1.1 and REQ-F1.3 tagged `[test]` with no automation |
| Decision-domain gaps | 18 | The upgrade window (the repo runs the installed plugin); the status write's permission and the hook's recovery path; a timed-out session abandoned, not stopped; resolver warnings with no reader unattended; a point that ran nothing indistinguishable from one never wired; captured output reaching a PR body unbounded; the point vocabulary's ownership; a repo-tracked egress step's disclosure |
| Testability | 21 | Task 2's first Done-when reading a key Task 3 adds; `regenerate` promising an artifact a range cannot encode; the kickoff CI-gate exclusion with no verification path; Task 8 green because nothing is configured; fixture overlays with no stated layer; a pre-ci expectation false on re-execution |
| Cross-file consistency | 17 | The worker profile's bare Write and Edit falsifying REQ-G1.2 and, with REQ-G1.3, letting a worker approve itself any line; the guard's plugin-script containment rejecting every command target the feature exists for; the review-sequence sweep missing eleven surfaces and the hyphenated spelling; tower-front-door's second reference; the merge-currency-guard mutation residual inherited unnamed |
| Documentation and glossary drift | 26 | "agent-issued" renamed at two of eight sites; the wired-point count six in two places and seven in three; D-17 still ordering the no-push rule against a point kickoff lacks; "audit record" with three referents; "terminal rung" meaning "cannot resume"; "dispatch brief" naming nothing; "flip surface" defined only in a Deferred entry; `point of use` unhyphenated |
| Rendered-content safety and data hygiene | 8 | The record cache asserted untracked with no ignore line; the step-id charset unvalidated before key and path use; the empty list's validity unstated against a precedent that calls it malformed; `Citations:` continuation lines dropped by the model parser; the inherited-environment posture; data hygiene otherwise clean and every parser form accepted at Draft and at Ready |

Raw findings across the nine lenses: 167, the same fault lines recurring
under several (the flip evidence chain, the guard's match rule, the
review-sequence sweep, the records' fields), so the deduplicated set is
smaller; the per-lens reports are in the run's sub-agent transcripts and
summarised here.

**Dispositions.**

- *Operator's judgment, the worker's trust boundary:* the shipped profile
  grants bare Write and Edit, so REQ-G1.2 is restated to the trust the
  profile provides (core and adopter layers outside the worker's write
  set; repo-tracked and machine-local declarations inheriting the
  trusted-repository-code posture the guard already extends to
  `scripts/`), no new deny rules, the false test and the adopter-facing
  sentence dropped. Chosen over path-scoped denies (a worker can still
  write and run a script, and a deny blocks its own config migration) and
  over trusting only out-of-worktree layers (the team-policy layer would
  lose auto-approval). D-11 records all three.
- *Operator's judgment, the upgrade window:* this repository's config
  keeps `review_sequence` beside `steps_convergence` with a dated comment
  until the release carrying the new resolver is installed, removed under
  a gated Deferred entry; the new resolver warns once per run. Chosen over
  a release-gated migration task and over accepting a silent downgrade
  through `[polish]`. D-10 and REQ-F1.2 record it.
- *Applied as one cluster, every finding with a single fix.* In substance:
  the resolver's output shape, exit codes, check-mode rule, `--preamble`
  mode, and explicit attendance (REQ-H1.3, REQ-C1.4); the decision tokens
  and the attended-core cell (REQ-C1.4); an id with no entry routed to the
  matrix, the by-layer policy split for lists and entries with the core
  arm (REQ-C1.5); the per-layer config read the shadow and stale-key
  warnings need (REQ-C1.1, REQ-C1.6, Task 2); the step-id charset, the
  reserved `implementation` id, single-line scalars, the empty list, the
  `supersede` marker, the namespace grammar, skill `args` verbatim
  (REQ-B1.2, REQ-B1.3, REQ-B1.6); the one-directional tier rule and the
  underscore spelling (REQ-C1.7); the pipeline-entry list as a literal the
  rule doc owns with the old disjointness checks retargeted (REQ-C1.8); a
  fifth outcome `skipped`, the runner as classifier with the `applied`
  discriminator (REQ-D1.1, D-8); the flip-point halt destination
  (REQ-D1.2); the invocation mechanism per kind and mode, the widened
  `dispatch_isolation` scope, the `isolated` degradation arm, context to
  session-hosted command steps as assignment prefixes (REQ-D1.3, REQ-G1.3,
  D-7, D-11); the `in-session` predecessor exception (REQ-D1.4); records
  gaining head SHA, run id, bounded screened excerpt, output path,
  completion record, the pinned `.claude/steps/` path with its ignore
  line, the `none` row and warnings per point (REQ-D1.5, D-16, Task 4);
  the no-push rule as doctrine (REQ-D1.6, D-17); the timed-out session's
  stop and the in-session command timeout (REQ-D1.7, D-15); the
  convergence order and the queued-fork `halted` mapping (REQ-E1.1); the
  checklist-and-tables regeneration (REQ-E1.2, D-12); the unit-PR flip
  point defined rather than wired, `pre-ci` before the first CI run, the
  spec flip point's firing rule (REQ-A1.1, REQ-A1.2, D-2, D-3); the
  context set's inherited environment, empty-versus-unset rule, and the
  preamble's owner (REQ-A1.4, D-14); unwired keys named and swept
  (REQ-A1.3, REQ-B1.3, REQ-H1.4); the vocabulary's ownership and the
  `tower-idle` rename (REQ-A1.3, D-2); the latest-attempt derivation, the
  branch-to-context mapping, the fork and mutation arms, the recovery path,
  the status-write permission, the rollup exclusion by context name
  (REQ-E1.5, D-20, Task 9); the sweep's two-pattern `git grep`, the skill
  bodies owned by Tasks 5 and 6, the breaking-change marker and upgrade
  note, tower-front-door's second reference (REQ-F1.3, REQ-F1.5, Task 3);
  the task-file repairs (Task 2 owning the point keys and options rows,
  Task 6 naming the PR-ready test and the kickoff gate doc, Task 7 naming
  the guard's own test and the no-diff assertion, Task 8 naming its test
  and sweeping the stale key, Task 9 keyed by attempt with the release-lib
  rows, Task 5 naming its files, the converge-sync anchor and
  `/orchestrate`'s trim, Task 1's Done-when as a rule with its citations
  completed, D-15 and D-18 cited, every `Citations:` bullet on one physical
  line); the documentation additions (REQ-H1.2: context set, cache and
  ignore line, credential rule, permission, disclosure note, the growable
  catalogs); the citation repairs (fleet-autonomy's brief note,
  model-allocation's rows, obs:03653377 for the timeout rule, obs:c97cda97
  and obs:fbb56815 placed, issue 383's quote attributed, merge-currency-guard
  D-5 cited for its bounded-server-signal posture, REQ-C1.10 named); the
  wording drift (the wired-point counts removed, "agent-issued" kept for
  the obligation and "in-session" for the hook's predicate at every site,
  "audit record" scoped, "terminal rung" replaced by the resumability
  condition, "dispatch brief" replaced, "flip surface" defined at first
  use, "structurally" dropped, `point-of-use` hyphenated, the "three cited
  bundles" qualified); and the enumerated counts converted to rules.
- *Declined:* the corpus-wide "evaluated at drain" gate phrasing (kept
  for consistency with signed siblings; recorded as an observation for a
  sweep); the `Citations:` continuation-line parser defect (the
  format-grammar bundle's; recorded as an observation, worked around
  here); the spec-format "unit" glossary widening (recorded as an
  observation for the meta-spec's next amendment).
- *Applied to the brief rather than the bundle:* the section 4 ledger
  amendment, the section 5 test list and dead-path note, the section 6
  non-edges, risk rows 5 to 8 corrected and rows 12 to 16 added.

### Pre-flip verification

- **Post-lens stale-reference sweep.** Run after the rewrite over the four
  files: no reference to the retired first-token match, the wired-point
  counts, "bootstrap D-5", "the hosting session" as classifier, "dispatch
  brief", "structurally malformed", the permission-matcher test as the
  guard's home, or "the terminal rung" as a resume condition remains;
  "agent-issued" survives only where it names the obligation and
  "in-session" only where it names the hook's predicate; the brief's
  sections 4 to 7 were reconciled as listed above.
- **Lint.** `markdownlint-cli2` over the brief and the four spec files: 0
  errors. No prose line exceeds 80 columns except single-line H3 headings
  and the `Citations:` bullets, which the format's model parser reads from
  one physical line.
- **Recorded claims re-derived.** Nine rule docs resolved (the header's
  list). Requirement bullets and test-spec entries match one to one (a
  fixed-string count of each, equal). Every decision heading D-1 to D-20 is
  cited by at least one task (a fixed-string count per id over `tasks.md`,
  none zero). Every check task a Done-when names exists in `mise.toml`
  except `check:steps`, which Task 8 adds; every existing test file a
  Done-when names exists under `tests/`. The overlay layer count was
  verified against the catalog resolver's header; the three review
  dispositions against `/execute-task`'s convergence bullets; the
  installed-plugin registry against its file; the flight branch form
  against tower-front-door. The validator reports 0 errors and 0 warnings
  at Draft in the worktree and at Ready on a scratch copy with the sibling
  bundles linked.
- **Enumerations cross-checked.** The bundle's remaining counts are all
  self-owned (the point list, the ten context fields, the three hosting
  modes, the five outcomes) or cite the surface they enumerate; the
  cross-repository counts the drafting carried (the wired-point tallies,
  the budget figures, "four fixture rows", "the three cited bundles") were
  converted to rules or to citations of the guard that measures them.

### Sign-off record

Signed off 2026-09-22 by the operator after the approval summary; the four
spec files flipped Draft → Ready with `Last reviewed:` at today; the
validator re-run at Ready reports 0 errors, 0 warnings; the status render
derives Ready with Task 1 dispatchable and the rest blocked on their
edges. Five observation fragments from this run travel with the sign-off
commit (the no-fork-section selector, the ready-guard's heredoc refusal,
the citation continuation-line parser, the gate phrasing, the "unit"
glossary widening). The operator also chose to post the flipper obligation
as a note on issue 379.

Class: meaning
Lens-pass: the full-bundle lens review recorded in this section (nine-lens
spec-set fan-out, dispositions above), preceded by the mid-walk delta lens
pass recorded in section 3
Anchor: `8770ba2186ad97829f322355cf5017b479ca24e4` — computed as
`scripts/spec-anchor.sh specs/custom-steps`
