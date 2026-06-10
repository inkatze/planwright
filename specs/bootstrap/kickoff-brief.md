# planwright Bootstrap — Kickoff Brief

**Spec:** `specs/bootstrap`
**Spec commit:** 64df4248e7ac9f427ba0aabaaa6a3459257e1477
**Walkthrough started:** 2026-06-10
**Repo-class:** solo (human-confirmed 2026-06-10; registry write blocked — `pair-flow-config.sh` cannot identify a repo with no git remote; entry to be written once a remote exists)
**Retrofit mode:** no (validator clean: 0 errors, 0 warnings on Draft)

This brief is the durable contract between human and agent for executing the
bootstrap spec. Downstream skills (`/execute-task`, `/orchestrate`) operate from
this brief, not by re-reading the spec.

Cold-review questions raised by the human at kickoff, tracked through the
walkthrough: self-healing/maintenance checks in skills; pipeline placement of
staff-engineering suggestions; bucket revisit; configuration documentation
(solo/multi); smarter `/orchestrate`; option documentation in general; status
lifecycle sufficiency; whether `/spec-draft` should commit; rigor-doctrine gaps;
senior/staff-engineer behavior during execution.

## Section 1 — Goal & glossary

**Restatement.** planwright is an autopilot for spec-driven development. The
human is pilot-in-command and keeps two reserved controls: sign-off and merge.
Once a spec is signed off, the framework advances tasks, opens draft PRs, and
converges review autonomously. Execution quality is bounded by spec quality, so
the primary investment is spec correctness before any code is written. The
deliverable extracts pair-flow's generalizable core (four-file format, kickoff
brief as contract, four-bucket autonomy gate, stateless orchestration, rigor
doctrine, engineering builder) into a standalone Claude Code framework with no
personal-toolchain inheritance.

**Rules out:** auto-merge (permanent), personal scaffolding (fish/mise/tmux/
Ansible), cross-session awareness in v1, non-GitHub hosts, the commodity review
workflows.

**Assumes:** Claude Code is the only runtime (skills + hooks + plugin); GitHub
via `gh`; adopters accept opinionated doctrine.

**Implicit terms surfaced:**
- "Gate" carries three senses in the bundle: autonomy gate (bucket dispatch),
  `GATE(when:)` deferral entries, release gate (REQ-J1.5).
- "Unit" = single task or one cohesion-bundle (the orchestration quantum).
- "Drain" / "accumulator" are framework-specific vocabulary.
- "Adopter" (non-author operator) is the success-criterion persona.

**Resolutions (2026-06-10):**
1. **Per-invocation autonomy is the v1 promise.** "Without further human
   keystrokes" means each `/orchestrate` invocation is fully autonomous up to
   draft PR; continuous advancement is adopter-supplied scheduling or a
   fast-follow. Goal text unchanged.
2. **Glossary becomes a Task 4 meta-spec deliverable**, defining at minimum:
   the three senses of gate, unit, drain, accumulator, adopter, brief (kickoff
   vs handover), bucket.
3. **Bundle deliberately kept whole** (19 tasks) despite D-21's
   comprehensibility trigger: founding spec, and the builder is wired into the
   autonomy gate and lifecycle hooks; splitting would add cross-spec
   coordination for little gain.

Signed off: 2026-06-10

## Section 2 — Requirements walkthrough

All 77 REQs across 11 groups walked in batches. Outcomes below; the consolidated
spec-edit list is at the end of this section and is applied during the Task-graph
section (the spec is Draft and unsigned, so these are in-place edits, not
supersedes).

### REQ-A — format, lifecycle, evolution
- **Citations (REQ-A1.2) vs. bundle reality:** REQ stays strict (citation per
  requirement). This bundle's conformance is gated on Task 4, which gains
  deliverables: citation syntax, lightweight citation kinds for adopters
  ("drafting-session decision" etc.), and backfilling this bundle. Known
  non-conformance until then.
- **Status lifecycle goes to five** (grounded in a survey of PEP/KEP/IETF/ADR/
  MADR/TC39/Rust-RFC lifecycles — the two missing concepts appeared in all six
  processes): Draft, Active, Done, **Retired** (terminal: abandoned/withdrawn),
  **Superseded** (terminal: replaced, mandatory `Superseded-by:` pointer).
  Reopen cycle defined: extending a Done bundle flips Done→Draft; scoped
  kickoff of the delta flips back to Active; completion → Done.
- **Done with open gates:** allowed. Done requires Forward plan / In progress /
  Awaiting input empty; Deferred entries may remain; the gate evaluator sweeps
  all specs regardless of status (gates outlive Done).
- Changelog location: defined by the meta-spec (Task 4); lives in
  `requirements.md`.

### REQ-B — authoring & comprehension
- **Auto-commit, opt-out** (precedent: npm version/release tools, aider,
  create-react-app): `/spec-draft` commits the Draft bundle; `/spec-kickoff`
  commits brief + status flip after sign-off; never push. Config toggles
  `commit_on_draft` / `commit_on_kickoff`. REQ-B1.1 amended.
- **New REQ-B3.2 — self-healing skills:** every planwright skill ends with a
  maintenance check comparing its instructions to the doctrine/spec version it
  implements; detected drift is written to the opportunities log (which has a
  canonical reader), riding the existing accumulator machinery.

### REQ-C — the autonomy gate (largest restructuring of the kickoff)
Trigger: the human reported `/copilot-pairing` achieves near-zero intervention
while the bucket skills do not. Structural diagnosis: copilot-pairing is
exception-based (act unless a hard stop fires) with an agent-completable
disposition space (fix or rebut); the bucket flow was permission-based with two
buckets that queue for the human by design. Per-finding sign-off was never a
reserved control (those are spec sign-off and merge); on a draft-PR branch every
action is one revert from undone.

**Resolved model — act-then-review:**
- Auto-applicable: applied immediately (audit row).
- Agent-resolvable: applied with evidence row (failing→passing test, CI green,
  brief-alignment citation).
- Needs sign-off: **applied on the branch**, listed in a "pending sign-off"
  checklist in the draft PR description; the human approves by leaving it,
  rejects with one revert, at PR review.
- Needs human judgment: NOT applied; must first climb the **resolution ladder**
  (brief/spec citation → research → project convention); only irreducible
  product/priority forks queue, surfaced at loop end with bespoke options.
- **Declined-with-rationale** is a first-class disposition: the agent may close
  a validated finding with reasoning in the audit table (re-raisable at PR
  review).
- **Hard pauses (only mid-loop interrupts):** disqualifier zones
  (security-sensitive code, migrations/destructive ops, CI config, lockfiles,
  secrets files) and irreducible judgment forks.
- Four tables (including empties) remain as audit taxonomy, not a decision
  queue.

**repo-class is dropped from v1.** The author's draft→ready flip is the
universal gate; the framework cannot enforce a multi-reviewer-only
acknowledgment anyway (marking ready is a human GitHub action — no enforcement
point); shipped agents (Copilot coding agent, Devin, OpenHands) and Renovate
treat team-vs-solo as per-action policy, not repo classification. REQ-C1.3/C1.4
and D-5/D-6 are rewritten; Task 7 shrinks to gate wiring; Task 18 and
REQ-J1.5(c) reword to "one clean end-to-end run on a real multi-contributor
work repo"; REQ-K1.1 loses the repo-class registry. Re-add path (config knobs)
documented as fast-follow if teams demonstrate need.

**Intervention contract:** (1) kickoff sign-off before; (2) rare hard pauses +
irreducible forks during; (3) PR review (diff + pending-sign-off checklist) and
merge after. Merge cadence is the autopilot's throttle.

### REQ-D — rigor doctrine (five additions)
- **REQ-D1.5 Research Rigor:** triggers (new dependency, unfamiliar domain,
  security-touching pattern, version-sensitive API, "how do mature projects do
  X"), source hierarchy (official docs > library source/tests > issues/RFCs >
  community), recency discipline (current docs over model memory), antipattern
  check, recording in the risk register. Wired into /execute-task and
  /spec-draft.
- **REQ-D1.6 Security posture:** write-time security triggers (untrusted input,
  subprocess/shell, paths, authz, crypto, serialization → focused pass before
  PR); **artifact data-hygiene** (no secrets/credentials/sensitive detail in
  committed framework artifacts: bundles, briefs, risk registers, observation
  logs, PR bodies); absorbs framework-script security.
- **Altitude check** added to solution validation: cause vs symptom, right
  layer.
- **Proportionality principle:** rigor scales with stake and reversibility;
  scoping must be declared, never silent.
- **Dependency-adoption checklist** in the engineering doctrine (supply chain,
  maintenance, license, transitive weight), stake-escalated per D-16.

### REQ-E — execution
- E1.5: draft PR body gains the pending-sign-off checklist.
- E2.1: loop semantics rewritten per act-then-review (drains everything except
  irreducible forks; emits four tables + declined log).
- E2.2 precision: skill *composition* is in-session; orchestrator *dispatch* is
  deliberately session-creating.

### REQ-F — orchestration (control-tower design, new REQ-F1.8)
- **Dispatch backends:** `subagents` (default; background subagents with
  isolated contexts and native worktree isolation; event-driven completion
  notifications; worker questions funnel to the tower's single prompt queue)
  and `tmux` (opt-in; interactive workers in named windows via
  `claude --worktree`; capture-pane **detection** — detect-and-surface, never
  impersonate via send-keys; routine prompts eliminated by a shipped
  worker-settings profile). Manual multi-session documented as the
  zero-machinery mode. Headless `claude -p` dropped (dominated by subagents).
- **Worktrees handled natively** by `claude --worktree` / EnterWorktree; no raw
  `git worktree` calls (D-37 amended).
- **Tower is disposable** (stateless per D-7: all state in tasks.md + gh +
  process/window list): structured compact worker returns, recycling on heavy
  context, auto-compaction as runway not design. No /clear needed.
- `max_parallel_units` cap, default 3. `--watch`: event-driven under subagents,
  polling metronome under tmux.
- **Orchestrate auto-commits its tasks.md state moves** (fixed conventional
  message, config opt-out).
- **Critical-path-first selection** (REQ-F1.2): among ready units, prefer the
  head of the longest dependent chain; FIFO ties.

### REQ-G — engineering doctrine & builder
- **Decision-domains catalog** (D-16 generalized): data-driven, adopter-
  extensible entries of trigger + considerations checklist + disposition rule.
  Seed ~10 domains: data storage & modeling, caching, queues/async, API surface
  design, authn/z, secrets & config, concurrency, observability,
  deploy/migration strategy, dependency adoption. Execution hitting an
  uncatalogued domain decision writes an observation (catalog grows via the
  drain loop).
- **Three wiring points:** /spec-draft (design phase), /spec-kickoff (flags
  catalogued domains the spec touches but never decides → risk register),
  /execute-task (drift triggers).
- Builder core catalog gains prose/doc linters (typos, vale, markdownlint) to
  widen tool-grounding.

### REQ-H/I/J/K
- `--bookkeeping` surfaces unmined-observation count and oldest-entry age
  (surface only, never auto-drop).
- **New REQ-K1.8:** single canonical options reference (name, default, effect,
  consumer) with a CI drift check — undocumented options fail planwright's own
  CI.
- REQ-J invariants re-checked against all of today's changes: none move.
- Risk-register notes: tasks-pr-sync hook fires in worker sessions and must
  resolve/write the canonical tasks.md in the primary checkout; all planwright
  scripts must handle no-remote brand-new repos gracefully (today's pre-flight
  failure as the lesson).

Signed off: 2026-06-10

## Section 3 — Design walkthrough

All 37 D-IDs accounted for: 22 confirmed with rationale intact (D-1, D-2, D-3,
D-7, D-9, D-10, D-11, D-12, D-17, D-18, D-19, D-20, D-21, D-22, D-23, D-24,
D-26, D-28, D-30, D-31, D-32, D-34); 11 amended by Section 2 decisions (D-4
buckets-as-taxonomy; D-5/D-6 rewritten to act-then-review, repo-class dropped;
D-13 composition-vs-dispatch precision; D-15/D-16 decision-domains catalog,
three wiring points; D-25 five statuses; D-27 gate condition (c) reword; D-29
new contract in docs; D-33 toggles in / registry out; D-35 graceful-degradation
lessons; D-36/D-37 native `claude --worktree`); 2 precision fixes:

- **D-8 reworded:** one unit per **step** (each step atomic, crash-safe); the
  watch loop / control tower take multiple steps per session up to
  `max_parallel_units`. Rationale (statelessness) intact; the invocation stops
  being the unit of throughput.
- **D-14 annotated:** the control tower already delivers single-host awareness
  (question funneling, live task list, Awaiting-input surfacing). The
  cross-session fast-follow shrinks to multi-tower / multi-host awareness and
  must not rebuild what the tower provides.

Signed off: 2026-06-10

## Section 4 — Verification approach

Coverage mix reviewed: ~21 [test] (validator/parser/hook fixtures, run in
planwright's own CI), ~17 [design-level] (doctrine artifacts; each names its
required content), ~21 [manual] + Gherkin.

- **Task 18 becomes the explicit manual-verification sweep:** its findings doc
  carries a checklist of every [manual] test-spec entry — exercised, or the gap
  named. The manual tier gains a drain point; release-gate condition (c)
  certifies the manual tier, not just "a run happened".
- Test-spec deltas ride the Section 5 edit list: entries for new REQs (B3.2,
  D1.5, D1.6, F1.8, K1.8, decision-domains, observation staleness), rewritten
  REQ-C entries (act-then-review: checklist generation [test]; declined log and
  resolution ladder [manual]), repo-class inference tests deleted, five-status
  validator fixtures (Retired/Superseded, reopen cycle).
- Verifiability spot-check: E1.2 adaptive-retry is executable (classifier is a
  fixture-testable script); no dead verification paths found.

Signed off: 2026-06-10

## Clarification review (2026-06-10)

A rendering issue meant the human had not seen the prose explanations behind
several decisions. All eight clarification-driven decisions were re-presented
with full context in preview panes and explicitly confirmed: (1) citations
gated on Task 4; (2) five-status lifecycle + reopen cycle; (3) auto-commit with
opt-outs across /spec-draft, /spec-kickoff, /orchestrate state moves; (4)
act-then-review gate rebalance; (5) repo-class dropped from v1; (6) five rigor
additions + decision-domains catalog; (7) dispatch design; (8)
critical-path-first selection.

The review produced three refinements to the dispatch design (superseding the
Section 2 REQ-F record where they differ):

- **`print` backend added:** orchestrate selects the unit, moves state, preps
  the worktree, prints the launch command (`claude --worktree <name>
  "/execute-task …"`), and exits; the human pastes it into any terminal.
  Zero-dependency, fully interactive manual dispatch.
- **Headless returns as *unattended mode*** (not an attended backend):
  cron/launchd/CI runs `claude -p "/orchestrate … --watch"` — a headless tower
  dispatching subagent workers inside itself; no confirms (always fresh
  worktrees); every would-be prompt becomes an Awaiting-input entry. The
  scheduled-autopilot story.
- **Worktree reuse rule:** if the attended session already sits in a clean
  worktree, one-line confirm to reuse it; otherwise create under
  `.claude/worktrees/<branch-suffix>` so any worktree is attachable via
  `claude --worktree <name>` regardless of which backend launched it. The
  placement convention is the contract; the launch mechanism is incidental.

Final attended backend lineup: subagents (default) / tmux (opt-in) / print /
in-session, plus unattended mode. `max_parallel_units` default 3.

## Section 5 — Task graph reconstruction & spec edits

**Graph:** reconstructs cleanly from `Dependencies:` lines and matches the ASCII
diagram. Parallel start: T1, T3, T4. Critical path: T4→T5→T6→T13→T18→T19 (T3→
T15→T16→T18 alongside). Under critical-path-first selection, T4 (the meta-spec)
dispatches first.

**Deliberate non-edges (hook-point pattern, recorded so nobody "fixes" them):**
- T8 (`/spec-draft`) ships the builder/catalog hook point; T16 plugs the builder
  in. A literal edge would be circular (T16 depends on T8).
- T9 (`/spec-kickoff`) ships the decision-domains gap check, degrading
  gracefully until T15 lands. No edge, to avoid serializing kickoff behind
  doctrine work.

**Effort moves:** T3 +0.5d, T4 +0.5d, T13 +1d, T15 +0.5d. Net ≈ +2.5d.

**Edits applied (2026-06-10), all traceable to signed decisions:**
- `requirements.md`: 17 edits + Changelog section (A1.6, A3.1, B1.1, B2.1,
  B3.2, C1.3–C1.7 rewrite, D1.2, D1.5–D1.7, E1.5, E2.1, E2.2, F1.1, F1.2, F1.8,
  G1.1, G1.4, G1.8, H1.4, J1.5c, K1.1, K1.7, K1.8, goal/scope rewords).
- `design.md`: D-5/D-6 rewritten in place (pre-sign-off Draft edits, not
  supersedes); D-8 reworded (one unit per step); D-13/D-14 precision notes;
  D-37 amended (native worktrees); new D-38 (control-tower dispatch), D-39
  (decision-domains catalog), D-40 (five-status lifecycle), D-41 (auto-commit),
  D-42 (self-healing), D-43 (options reference).
- `tasks.md`: deliverable/Done-when/citation updates across T1–T5, T7–T9,
  T11–T16, T18; T7 retitled (act-then-review gate wiring); T18 retitled
  (multi-contributor work-repo run + manual sweep).
- `test-spec.md`: new entries (B3.2, C1.6, C1.7, D1.5–D1.7, F1.8, G1.8, K1.8);
  rewritten C1.3/C1.4 (act-then-review Gherkin); repo-class inference tests
  removed; five-status and reopen fixtures; auto-commit checks.
- `Last reviewed:` → 2026-06-10 on all four files.

**Validator after edits: 0 errors, 0 warnings (Draft).**

Signed off: 2026-06-10

## Section 6 — Risk register

| # | Risk | Mitigation / early signal |
|---|---|---|
| 1 | Dispatch layer is the least-validated design; the worker-settings profile (pre-approved permissions for subagent/headless workers) is the risk center. | T13 Done-when exercises every backend + tower-kill recovery; Task 18 exercises dispatch on a real repo. Research Rigor trigger at T13: verify current `claude --worktree` / Agent-isolation semantics against docs, not model memory. |
| 2 | Act-then-review is a behavioral bet (inverts a v1-validated design on copilot-pairing evidence + field convergence). Failure mode: long pending-sign-off checklists concentrate review burden at the PR. | T18 findings doc evaluates checklist length and revert frequency; if checklists routinely exceed ~10 items, add severity ordering/batching as a fast-follow. |
| 3 | `tasks-pr-sync` hook fires in worker sessions inside worktrees; must resolve and write the canonical `tasks.md` in the primary checkout, under the per-spec advisory lock. | Named Task 6 design detail. |
| 4 | No GitHub remote exists yet; T2 (CI), T6 (hooks), T13 (PR paths) need the private repo + `gh` auth. | Human prerequisite: create the private repo + remote before T2 dispatches. |
| 5 | Artifact data-hygiene: gitleaks catches token-shaped secrets, not prose-shaped sensitive context; the risk register itself invites detail (REQ-E1.3). | D1.6 doctrine rule; gitleaks in CI; re-read T18's work-repo findings doc before any public flip. |
| 6 | Bash 3.2 portability for the new shell surface (gate parser, reconcile helpers). | Keep heavy logic in skills, shell thin; shellcheck + shell test runner in CI (T2). |
| 7 | Known conformance debt: per-REQ citations absent until Task 4. | Gated; Task 4 Done-when closes it. |
| 8 | `reference/` history purge before public release (human-reserved, easy to forget). | Gated Deferred entry; T19 release checklist enforces it. |

**Open questions: none.** Every Socratic check resolved to a decision; the
catalog seed-domain list is finalized by T15 as a deliverable, not an
ambiguity.

Signed off: 2026-06-10

## Section 7 — Sign-off

**Signed off: 2026-06-10.** Status flipped Draft→Active on all four spec files;
validator re-run under Active enforcement: 0 errors, 0 warnings. No retrofit
patches, no D-42 overrides. Walkthrough base commit: 64df4248 (this kickoff's
spec edits are staged on top, committed by the human).

This brief is now the durable contract. Downstream pair-flow skills
(`/execute-task`, `/orchestrate`) operate from it. Parallel start: T1, T3, T4
(T4 first under critical-path-first). Human prerequisite before T2: create the
private GitHub repository and remote, authenticate `gh`.

## Amendment 1 — Spec-PR flow (2026-06-10, post-activation, supersede ritual)

First exercise of the supersede ritual, minutes after activation. The human
asked whether spec authoring should flow through PRs; the resolved design
contradicted REQ-B2.1's "SHALL NOT push" (a meaning change → supersede, not
fix-in-place).

**REQ-B2.4 supersedes REQ-B2.1.** New D-44. The flow:
- `/spec-draft` creates the spec worktree + branch (`planwright/<spec>/spec`,
  reserved namespace, sync hook no-ops) and commits locally — no push, no PR
  (REQ-B1.1 unchanged).
- `/spec-kickoff` reuses that worktree, commits brief + Active flip, pushes the
  branch, opens a DRAFT PR. The human's merge makes the Active spec operational
  (`/orchestrate` reads main's view). Kickoff never marks ready or merges.
- Two-key launch: sign-off flips status; merge activates.
- Amendments: in-flight ride the triggering task PR; supersede-class get a spec
  PR; expression-only commit directly + changelog.
- Spec authoring is never an orchestration unit (J1.3 intact).
- **Graceful worktree handling in every starting state** (human red-line,
  2026-06-10): both skills detect launch location — spec worktree (proceed),
  main checkout / unrelated worktree (locate + print re-open command, or
  create), pruned worktree (recreate from spec branch), dirty/diverged state
  (surface and ask, never auto-stash), no repo / no remote (degrade per
  REQ-K1.7; push/PR step records an Awaiting-input note, local work intact).

Edits: requirements.md (B2.1 marked Superseded-by, new B2.4, changelog entry),
design.md (D-44), tasks.md (T6, T8, T9), test-spec.md (B2.1/B2.4 entry).

**Scoped re-sign-off: 2026-06-10** (human selected "Adopt via supersede" with
full context preview; worktree-gracefulness red-lined in by the human and
incorporated).

Bootstrap-spec note: this very kickoff ran the flow manually minus the remote —
the bundle sits committed-by-human on a worktree branch; once the private repo
+ remote exist, pushing this branch and opening PR #1 retroactively gives the
bootstrap spec the same record.
