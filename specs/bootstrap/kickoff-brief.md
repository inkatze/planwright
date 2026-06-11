# planwright Bootstrap — Kickoff Brief

**Spec:** `specs/bootstrap`
**Spec commit:** 64df4248e7ac9f427ba0aabaaa6a3459257e1477
**Walkthrough started:** 2026-06-10
**Repo-class:** solo (human-confirmed 2026-06-10; pair-flow harness pre-flight field — obsoleted by the Section 2 decision dropping repo-class from planwright v1: the registry was dropped along with the concept, so there is no entry to write)
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

**Rules out:** auto-merge (permanent), personal scaffolding
(fish/mise/tmux/Ansible), cross-session awareness in v1, non-GitHub hosts, the
commodity review workflows.

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
spec-edit list is in Section 5 (Task graph reconstruction & spec edits) and is
applied during that section (the spec is Draft and unsigned, so these are in-place
edits, not supersedes).

### REQ-A — format, lifecycle, evolution
- **Citations (REQ-A1.2) vs. bundle reality:** REQ stays strict (citation per
  requirement). This bundle's conformance is gated on Task 4, which gains
  deliverables: citation syntax, lightweight citation kinds for adopters
  ("drafting-session decision" etc.), and backfilling this bundle. Known
  non-conformance until then.
- **Status lifecycle goes to five** (grounded in a survey of
  PEP/KEP/IETF/ADR/MADR/TC39/Rust-RFC lifecycles — the two missing concepts
  appeared in all six process families, counting ADR/MADR as one): Draft,
  Active, Done, **Retired** (terminal: abandoned/withdrawn),
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
  implements; detected drift is written to the observations log (which has a
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
- **Decision-domains catalog** (D-16 generalized): data-driven,
  adopter-extensible entries of trigger + considerations checklist + disposition
  rule.
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
D-7, D-9, D-10, D-11, D-17, D-18, D-19, D-20, D-21, D-22, D-23, D-24,
D-26, D-28, D-30, D-31, D-32, D-34, D-36); 13 amended by Section 2 decisions
(D-4 buckets-as-taxonomy; D-5/D-6 rewritten to act-then-review, repo-class
dropped; D-12 rationale realigned to act-then-review (consequence of D-5/D-6);
D-13 composition-vs-dispatch precision; D-15/D-16 decision-domains catalog,
three wiring points; D-25 five statuses; D-27 gate condition (c) reword; D-29
new contract in docs; D-33 toggles in / registry out; D-35 graceful-degradation
lessons; D-37 native `claude --worktree`); 2 precision fixes:
*(Ledger reconciled at self-review 2026-06-10: D-12 moved confirmed→amended,
D-36 moved amended→confirmed — its only change was editorial placeholder
normalization; counts unchanged at 22/13/2.)*

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

Coverage mix reviewed: ~30 [test] (validator/parser/hook fixtures, run in
planwright's own CI), 16 [design-level] (doctrine artifacts; each names its
required content), ~23 [manual] plus 8 [Gherkin] (both exercised by Task 18's
manual-verification sweep; counts are pure-tag — mixed-tag entries also sweep).

- **Task 18 becomes the explicit manual-verification sweep:** its findings doc
  carries a checklist of every test-spec entry whose tag includes [manual] or
  [Gherkin] — exercised, or the gap named. The manual tier gains a drain point;
  release-gate condition (c) certifies the manual tier, not just "a run
  happened".
- Test-spec deltas ride the Section 5 edit list: entries for new REQs (B3.2,
  D1.5–D1.7, F1.8, G1.8, K1.8, observation staleness), rewritten/new REQ-C
  entries (act-then-review: checklist generation C1.3 [Gherkin]; declined log
  C1.6 [manual]; resolution ladder C1.7 [Gherkin]), repo-class inference tests
  deleted, five-status validator fixtures (Retired/Superseded, reopen cycle).
- Verifiability spot-check: E1.2 adaptive-retry is executable (classifier is a
  fixture-testable script); no dead verification paths found.

Signed off: 2026-06-10

## Section 4b — Clarification review (2026-06-10)

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

Signed off: 2026-06-10

## Section 5 — Task graph reconstruction & spec edits

**Graph:** reconstructs cleanly from `Dependencies:` lines; the layered diagram in
`tasks.md` is generated from those lines, which stay authoritative. Parallel
start: T1, T3, T4. Critical path (longest chain by estimated effort, 12.5d):
T3→T7→T11→T12→T13→T18→T19. Under critical-path-first selection (REQ-F1.2), T3
(the intelligence migration) dispatches first. *(Corrected at polish review
2026-06-10: the brief originally named T4→T5→T6→T13→T18→T19 (9.5d) as critical
and T4 as first dispatch; the effort-weighted recomputation supersedes that.)*

**Deliberate non-edges (hook-point pattern, recorded so nobody "fixes" them):**
- T8 (`/spec-draft`) ships the builder/catalog hook point; T16 plugs the builder
  in. A literal edge would be circular (T16 depends on T8).
- T9 (`/spec-kickoff`) ships the decision-domains gap check, degrading
  gracefully until T15 lands. No edge, to avoid serializing kickoff behind
  doctrine work.

**Effort moves:** T3 +0.5d, T4 +0.5d, T13 +1d, T15 +0.5d. Net ≈ +2.5d.

**Edits applied (2026-06-10), all traceable to signed decisions:**
- `requirements.md`: edits touching 28 REQ-IDs + Changelog section (A1.6, A3.1,
  B1.1, B2.1, B3.2, C1.3–C1.7 rewrite, D1.2, D1.5–D1.7, E1.5, E2.1, E2.2, F1.1,
  F1.2, F1.8, G1.1, G1.4, G1.8, H1.4, J1.5 condition (c), K1.1, K1.7, K1.8,
  goal/scope rewords).
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
| 9 | *(Appended at Task 3 execution 2026-06-11.)* T3 landed the doctrine docs at `doctrine/` before T1's rule-doc resolution path convention exists (deliberate parallel start; T3 has no edge to T1). If T1 pins a different home, the docs move or the convention adapts. | T1's resolution-path deliverable must resolve to `doctrine/` from both delivery modes or relocate the files in the same PR; REQ-D1.4's [test] entry verifies the resolved path. |

**Open questions: none.** Every Socratic check resolved to a decision; the
catalog seed-domain list is finalized by T15 as a deliverable, not an
ambiguity.

Signed off: 2026-06-10

### Risk register additions — Task 1 execution (2026-06-11)

Research Rigor findings recorded per REQ-E1.3/REQ-D1.5 (execution-skill write,
named-section only; no anchor entry). Trigger: version-sensitive API use (the
Claude Code plugin format). Sources: official plugin docs at
code.claude.com/docs (plugins, plugins-reference, discover-plugins), consulted
2026-06-11.

| # | Risk | Mitigation / early signal |
|---|---|---|
| 10 | `${CLAUDE_PLUGIN_ROOT}` is ephemeral: the path changes on every plugin update (old versions retained ~7 days). Any planwright state written under the plugin root would be silently lost on update. | Convention set at Task 1: plugin root is read-only at runtime; durable runtime state belongs in `${CLAUDE_PLUGIN_DATA}` (`~/.claude/plugins/data/<id>/`, update-stable) or repo-local paths. Re-check when T13 places locks and T19 finalizes packaging. |
| 11 | Manifest/layout facts verified current as of 2026-06-11: manifest at `.claude-plugin/plugin.json` (only `name` required, kebab-case); `skills/`, `commands/`, `agents/`, `hooks/hooks.json` auto-discovered at plugin root only; plain `~/.claude/` files remain a supported non-plugin fallback. Plugin format is actively evolving (displayName v2.1.143+, defaultEnabled v2.1.154+), so these facts can drift before T19. | Resolution chain (`PLANWRIGHT_ROOT` → `CLAUDE_PLUGIN_ROOT` → `<claude-dir>/planwright`) isolates skills from layout drift; T19 re-verifies the manifest schema against current docs before finalization. |
| 12 | Doctrine gap surfaced at T1's tooling pass, routed here so T15's executor sees it (the observations log feeds `/spec-draft`, not task execution): the engineering doctrine's "defer to tooling and ecosystem standards" needs two companion principles — pin the quality toolchain (reproducibility is what makes tool-grounded discovery trustworthy) and own adopted tools' defaults (review conventions-bearing defaults at adoption, record deviations with rationale; tool defaults are the tool author's context). Fits T15's existing deliverable scope without contract drift. | Two observation entries dated 2026-06-11 carry the full evidence (shim failures pre-pinning; 80-column defaults in two tools; gitleaks `--redact`; shellcheck optional-tier trial: 4 hits, none load-bearing). T16's builder applies the same at guard-adoption time. |

## Section 7 — Sign-off

**Signed off: 2026-06-10.** Status flipped Draft→Active on all four spec files;
validator re-run under Active enforcement: 0 errors, 0 warnings. No retrofit
patches, no REQ-B2.3 inconsistency overrides. Walkthrough base commit: 64df4248 (this kickoff's
spec edits are staged on top, committed by the human).

This brief is now the durable contract. Downstream pair-flow skills
(`/execute-task`, `/orchestrate`) operate from it. Parallel start: T1, T3, T4
(T3 first under critical-path-first; corrected per the Section 5 note). Human
prerequisite before T2: create the private GitHub repository and remote,
authenticate `gh`.

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

## Amendment 2 — Polish-review hardening + design-gap backlog (2026-06-10)

A `/polish` review pass (nine-lens fan-out; spot-check validation per the polish
skill's scoping; all findings human-dispositioned via clustered decisions)
produced corrections across the bundle plus the following normative amendments.
The human chose to amend the five highest-stakes gaps immediately and defer the
remaining 29 to the backlog below ("amend critical, log rest"):

1. **Spec-identifier charset (new REQ-A1.8).** `<spec>` identifiers match
   `[a-z0-9][a-z0-9-]*`, validator-enforced; no skill or hook interpolates a
   failing identifier into a path or command. (Tasks 4, 5.)
2. **Sync-hook branch sanitization (REQ-K1.2).** Parsed branch segments are
   charset-validated and the resolved path containment-checked under `specs/`;
   hostile branch names are a clean no-op. (Task 6; hostile fixture in
   test-spec K1.2.)
3. **Gate-condition closed grammar (REQ-H1.3).** Gate conditions parse by
   pattern match against a closed declarative grammar; never `eval`, subshell,
   or arithmetic expansion; malformed gates surface as errors, never silently
   skipped. (Task 10; hostile fixtures in test-spec H1.3.)
4. **Orphaned-In-progress disposition (REQ-F1.1, D-38).** The reconcile sweep
   moves In-progress tasks with no live worker and no open PR to Awaiting input
   with an orphan note; never left in place, never auto-re-dispatched.
   (Task 13; fixture in test-spec F1.1.)
5. **Validator-absent precedence (REQ-K1.7).** On execution paths a missing
   validator halts (fail closed, preserving REQ-A2.1's block-execution
   guarantee); graceful degradation applies to authoring/read-only paths.

Also applied with sign-off, no normative change: recorded Section 3 amendments
propagated into D-15/D-16/D-25/D-27/D-33 text (D-12's edit was a stale-reference
realignment to D-5/D-6, reclassified in the Section 3 ledger at self-review);
count corrections in this brief (13 amended D-IDs, 28 edited REQ-IDs, ~30 [test]
coverage); critical path recomputed (Section 5 note); REQ-I1.4 restated as a
cross-reference to REQ-D2.2; F1.8 deliberate-bundling note; work-repo
identifiers neutralized per REQ-D1.6; traceability and editorial fixes across
all four files.

Edits: requirements.md (A1.8 added; K1.2/H1.3/F1.1/K1.7 amended; changelog),
design.md (D-38 orphan rule; amendment propagation), tasks.md (T4/T5/T6/T10/T13
deliverables, Done-whens, Citations), test-spec.md (A1.8 entry; K1.2/H1.3/F1.1
fixtures), this brief (counts, Section 5 correction, backlog).

**Scoped re-sign-off: 2026-06-10** (clustered decisions, all eight answered by
the human in session).

### Deferred design-gap backlog (polish review, 2026-06-10)

Human-dispositioned as "log, address via the spec's amendment process later".
Grouped by sub-theme; each line is a known underspecification, not a bug in
shipped code (nothing is implemented yet).

**Locking & state:**
- `tasks-pr-sync` hook: lock acquisition is named only in risk row 3, not in
  REQ-K1.2/Task 6; hook lock-failure path (no-op would drop a PR event) needs a
  named recovery (bookkeeping reconciliation as backstop, or retry).
- Lock path `specs/<spec>/.orchestrate.lock` is per-checkout; worktree-resident
  writers must lock the primary checkout's path (canonicalization rule).
- Stale-lock break needs atomic break-and-reacquire semantics (two concurrent
  breakers must not both proceed); contention fixture for test-spec F1.3.
- `--bookkeeping` / `/drain` `tasks.md` writes are not stated to take the
  advisory lock (D-31/D-17).
- State-move commits in a shared checkout: stage only the spec's own files;
  define commit ownership for hook writes; handle `.git/index.lock` contention.
- D-41 auto-commit opt-out contradicts the parallel-dispatch rationale; define
  the interaction (opt-out forces single-unit, or unattended ignores it).
- Observations-log concurrent append vs `/spec-draft` archive/trim race; define
  append-only discipline + trim-under-lock and the canonical checkout.
- `max_parallel_units` scope undefined under multiple concurrent towers; derive
  the live count from In-progress entries, not the local process list.
- Active→Done flip actor ambiguous (sync hook vs bookkeeping); name one.

**Failure contracts:**
- D-41 auto-commit failure path (pre-commit hook rejection, dirty index):
  halt-to-Awaiting-input, never dispatch on uncommitted state.
- Worker crash/timeout missing from REQ-F1.5's halt enumeration; per-backend
  post-detection disposition for errored/stuck workers (D-38).
- Escalation target undefined for REQ-E1.2 (where does "escalate immediately"
  land in a dispatched worker?); transient-retry exhaustion branch unstated.
- "Resumable partial brief" (Task 9 Done-when) has no REQ/design/verification
  home; specify the resumability mechanism or strike it.
- Unattended-mode outcome contract: a headless run that parks units in
  Awaiting input needs a surfacing channel (exit code / summary artifact).
- Rule-doc resolution failure absent from REQ-K1.7's missing-prerequisite
  enumeration; define fail-closed-or-surface for unresolvable doctrine docs.
- Re-dispatch into an existing dirty worktree (orphan recovery path) undefined
  for `/orchestrate` (D-37/D-38; D-44 covers only the spec skills).

**Semantics:**
- PR-event→section transition map for the sync hook (create vs merge; Completed
  SHOULD mean merged-to-main, else dependents branch from main without the
  dependency's code).
- Never-pushed state commits diverge across clones; define which ref is "main's
  view" (D-44) and how state commits reach the remote.
- Non-Active refusal when invoked inside the spec worktree (files say Active,
  main says Draft) depends on an unstated read-from-ref mechanic; make it
  explicit + fixture.
- Gate re-surfacing: target section should be Forward plan / Awaiting input
  (never In progress); define the Done-spec outcome and re-surface idempotency
  (a satisfied gate must not re-surface on every pass).

**Security (beyond the amended five):**
- Worker-settings profile needs a least-privilege requirement: enumerated grant
  list in the options reference; never pre-approves REQ-C1.4 disqualifier zones.
- `~/.claude/` writer needs do-not-clobber: show a plan/diff, never silently
  overwrite user config, confine writes to namespaced paths (REQ-I1.2).

**Bounds:**
- `--watch` tmux polling: configurable interval (options-reference entry per
  D-43) + termination condition.
- Reconcile sweep trigger frequency (it calls `gh`): tower start / recovery,
  at most once per step — not per watch tick.
- `/polish` loop needs an iteration cap + convergence criterion (pair-flow had
  cap 15 / two clean iterations; the planwright bundle dropped both).
- Worktree pruning policy for unattended mode (fresh worktrees accumulate
  forever; prune on merge via the sync hook or a bookkeeping sweep).
- Fold-detection scan input bound (Goal + Scope sections only, not full
  bundles).
- Gate sweep excludes terminal (Retired/Superseded) specs; migrate or close
  open gates at retirement/supersession.
- *(Added at Amendment 5 2026-06-11.)* Parallel in-flight amendment anchors
  under merge: two branches each appending anchor entries leaves "most recent"
  merge-order-ambiguous and neither anchor matching merged main; define
  provisional anchors + a post-merge re-anchor step (bookkeeping prompt).

## Amendment 3 — Self-review corrections to the polish amendments (2026-06-10)

A `/self-review` pass over the polished bundle (nine-lens fan-out, three-pass
validation, all findings human-dispositioned) found the polish amendments
introduced one functional regression and several underspecifications. The human
approved all 23 recommended fixes and chose "tighten the predicate" for the
orphan rule. Normative corrections:

1. **Task-id grammar split from REQ-A1.8 (K1.2).** The polish amendment
   validated branch `<id>` segments against the spec-identifier charset, which
   rejects D-36's blessed dotted ids (`3.5`) — dotted-id PR events would have
   silently no-opped. `<id>` now has its own anchored grammar
   `^[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?$`; A1.8 governs `<spec>` only.
   Positive `task-3.5` fixture added.
2. **A1.8 anchored + bounded.** Full-string `^[a-z0-9][a-z0-9-]*$` (substring
   matching non-conforming), 64-char max; skill-side hostile-identifier
   refusal gains a verification path.
3. **H1.3 grammar pinned.** Atoms (task-ID refs, spec statuses, ISO dates),
   `and`-of-atoms as the only combinator, a surface-only free-text gate lane
   (the bundle's own prose gates use it); data-only handling rules; the
   malformed-gate disposition moved into the REQ as drain-report-level.
4. **F1.1 orphan predicate tightened.** Dispatch metadata recorded in
   In-progress entries; PR-state reconciliation precedes orphaning (merged →
   Completed); grace threshold; observable-backend + positive-evidence-of-death
   requirements; print-backend exempt until threshold + human confirm. D-17
   re-surfacing no longer targets In progress (collision resolved).
5. **K1.7 fail-closed scoped to dispatch steps.** `--bookkeeping`, `/drain`,
   `/resume` degrade normally; the stale fail-soft doctrine bullet in design.md
   was aligned.
6. **F1.2 effort-weighting made explicit** ("longest dependent chain weighted
   by estimated effort") — the weighting is what makes T3 the critical-path
   head.

Ledger reconciliation (Section 3): D-12 moved confirmed→amended, D-36 moved
amended→confirmed (counts stay 22/13/2); kickoff amendments recorded for
D-4/D-29/D-35 propagated into design.md with annotations. Plus editorial fixes:
annotation-format unified (`*(Amended at <event> <date>: …)*`, now a Task 4
convention), sweep scope says "tag includes [manual]/[Gherkin]", design-level
count corrected to 16, Amendment 2 gained its Edits/re-sign-off block, history
purge scope widened to pre-neutralization spec blobs, and small prose repairs.

Edits: requirements.md (A1.8, K1.2, H1.3, F1.1, K1.7, F1.2, F1.8 note,
changelog), design.md (D-3, D-4, D-17, D-29, D-35, D-38, degradation bullet),
tasks.md (T4, T10, T12, T13, T18, Deferred purge entry), test-spec.md (header,
A1.8, K1.2, F1.1, F1.2, F1.8, D1.6, H1.3, K1.7, cross-ref stubs), this brief,
`.gitignore`, `specs/_observations/opportunities.md`.

**Scoped re-sign-off: 2026-06-10** (workflow: apply-all-23 + tighten-predicate,
both human-selected in session).

## Delta re-walkthrough (2026-06-11)

Scope: `/spec-kickoff` over the post-sign-off amendment delta (commits ed21005,
3bd60b1 — Amendments 2/3). Pair-flow D-51's literal wholesale trigger fired
(requirements + design changed in the same commits) but the human chose a delta
walk: both
commits co-amended this brief in lockstep with recorded scoped re-sign-offs, so
the brief was never stale. Validator: 0 errors, 0 warnings on Active, before
and after. Section 1 unchanged (anchor context).

Decisions taken during the walk:

1. **Amendment-ritual scope (REQ-A3.3 compliance).** The in-place meaning
   changes in Amendments 2/3 are compliant as **pre-merge corrections**: the
   spec PR (#1) is unmerged, so the supersede ritual — which governs post-merge
   changes — does not apply; pre-merge corrections on the spec's own PR amend
   in place with a changelog entry + recorded re-sign-off. Codified as a Task 4
   meta-spec convention so the question never recurs.
2. **Underscore accumulator exemption (REQ-A1.8).** `_pending/` and
   `_observations/` failed the new charset. Resolved: leading underscore is the
   reserved non-spec-accumulator marker — exempt from the charset, never
   validated as bundles. A1.8 amended; Task 5 validator skip rule; test-spec
   fixture added.
3. **Grace-threshold coupling accepted.** The orphan grace default stays tied
   to D-10's 15-min stale-lock threshold (one named knob); accepted risk, T1's
   options reference can split them if field experience demands.

Per-section outcomes: S2 (8 REQs restated; two red-lines above applied);
S3 (13 design items; D-17 and D-38 meaning changes confirmed sound — D-17's
narrowing strengthens its no-write-only-deferral promise); S4 (all amended
clauses pinned; A1.8 manual fixture defers to T18's sweep by design); S5
(layered graph re-verified against Dependencies; T3-first effort-weighted
critical path confirmed; no unstated dependencies); S6 (new accepted risks:
grace coupling, print-backend orphan latency, In-progress dispatch-metadata
format is a Task 4 deliverable T13 depends on).

Edits applied during the walk: requirements.md (A1.8 underscore exemption),
tasks.md (Task 4 conventions: amendment-ritual scope + underscore marker;
Task 5 skip rule), test-spec.md (A1.8 underscore fixture).

Signed off: 2026-06-11

## Amendment 4 — Execution freshness gate (2026-06-11, pre-merge class)

Trigger: a human near-miss observed today. Post-sign-off amendments (Amendments
2/3) were re-validated only because the human thought to ask ("would any of
these have been caught if I just tried to execute?" — answer: the worst ones,
never). Nothing prevented `/orchestrate` or `/execute-task` from dispatching
against spec content that changed after the brief's sign-off.

**New REQ-F1.9 + D-45.** Every brief sign-off, amendment, and re-walkthrough
records a content anchor over the four spec files (canonical order:
requirements, design, tasks, test-spec; `cat <files> | git hash-object
--stdin`). `/orchestrate` dispatch steps and `/execute-task` recompute the
anchor at pre-flight and halt to Awaiting input on mismatch, naming the
`/spec-kickoff` delta re-walkthrough as the remedy. No bypass flag (same class
as the non-Active refusal). Semantic re-validation of spec changes stops
depending on human initiative.

Edits: requirements.md (REQ-F1.9; changelog), design.md (D-45), tasks.md (T9
writes anchors; T12/T13 gate at pre-flight; Citations), test-spec.md (REQ-F1.9
fixture entry).

**Reviewed-at anchor (covers the four spec files as of this amendment):**
`c8a23dd1c5f0995852a7e96571780faf4f4889a5`

**Scoped re-sign-off: 2026-06-11** (amendment requested by the human in
session; pre-merge in-place class per the ritual-scope rule codified in the
delta re-walkthrough).

## Amendment 5 — Mandatory lens pass + gate hardening (2026-06-11, pre-merge class)

Trigger: the human asked whether Amendment 4 itself needed a kickoff, and
whether the deeper lens fan-out (the machinery that caught the dotted-id
regression) could be forced rather than left to initiative. Resolved: yes to
both, as one rule — an anchor is execution-valid only if its sign-off included
the required lens review pass.

**The rule (REQ-F1.9 rewritten, new REQ-F1.10, D-45 extended).** Anchors are
manifest-style (per-file `git hash-object`, digest list hashed — boundary-safe);
`tasks.md` contributes task-definition content only (human choice: state moves
must not trip the gate, meaning edits must); the gate runs inside the D-10 lock
against the primary checkout's main view; absent/unparseable/non-sanctioned
entries fail closed. Sign-off records are machine-checkable (Class /
self-describing Anchor / Lens-pass), written anchor-last; meaning-class entries
are kickoff-only; expression-only edits self-re-anchor via a marked
machine-written entry (human choice: the lightweight A3.3/D-19 path must not
freeze unattended dispatch; misclassification is auditable and one revert from
undone). A3.3 scoped (supersede = post-merge; additions are meaning-class;
human classifies at sign-off). A1.8's accumulator class closed. Validity
conditions apply to anchors recorded from this amendment onward.

**Lens-pass record (first mandatory run, delta-scoped over the staged delta:
delta-walkthrough edits + Amendments 4–5).** Nine-agent fan-out; 58 raw
findings, 29 after dedup; all dispositioned (applied via this amendment's
edits, except one logged to the deferred backlog). Class: meaning.

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 9 | remedy mismatch, A3.3 scope/decider, grandfather, underscore class, all applied |
| Security | 6 | forgeability, anchor scope, boundary collisions, self-attestation — applied (threat model declared in D-45) |
| Error handling and failure modes | 6 | absent-anchor fail-open risk, write ordering, expression-only halt trap — applied |
| Performance | 1 | per-dispatch classification leak — applied (class marker) |
| Concurrency / state | 7 | tasks.md self-invalidation (critical), lock window, frame of reference — applied; merge-edge → backlog |
| Naming, readability, structure | 6 | annotation drift, glossary, F1.9 split — applied |
| Documentation | 12 | restatement divergences, command canonicalization, terminology — applied |
| Tests / verification | 6 | unpinned write paths, validity-halt wiring, record-format determinism — applied |
| Cross-file consistency | 5 | D-19/D-44 reconciliation, F1.5 list, changelog completeness — applied |

The mid-flight self-demonstration (Amendment 5's spec edits existing before
this brief section, recorded anchor stale) was the expected ordering — the
pass had to run before the section recording it could be written; the
anchor-last rule this amendment introduces makes that ordering normative.

Edits: requirements.md (F1.9 rewrite, new F1.10, A3.3, A1.8, F1.5, changelog),
design.md (D-45 threat model/scope, D-19, D-44, grammar), tasks.md (T4
extraction + record format + glossary, T9, T12, T13), test-spec.md (F1.9
rewrite, new F1.10 entry, A1.8, A3.3), this brief (backlog row, pair-flow D-51
qualification, this section).

Class: meaning
Lens-pass: recorded above (this section), findings dispositioned 2026-06-11.
Anchor: `3db417bfa7bd91c1738166272fdd0fe94825f0ad` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships — safe, as no state moves can occur before
the dispatch tooling exists).

**Scoped re-sign-off: 2026-06-11** (batch + two design forks human-selected in
session: definition-content anchor scope; marked expression-only self-re-anchor).

## Expression-only re-anchor (2026-06-11, panel review)

Machine-written entry per REQ-F1.10's expression-only lane. Edits: design.md
(`Last reviewed:` bump 2026-06-10 → 2026-06-11, missed at the Amendment 4–5
header sweep), this brief (Amendment 3 hard-wrap repair, "history- / purge" →
"history purge"). Changelog: requirements.md, entry "2026-06-11
(expression-only, panel review)". Both fixes human-approved (Apply/Apply) at
the panel-pairing handoff before application.

Class: expression-only
Anchor: `1dee698823e8af3cf1e6af54fb191d74a247ea85` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).

## Amendment 6 — T19 release checklist: purge wiring (2026-06-11, pre-merge class)

Panel review (gemini backend) caught a kickoff-propagation miss: Risk Register
row 8 (added at kickoff, 2026-06-10) claims the `reference/` history purge is
"enforced by the T19 release checklist", but Task 19's draft-era wording
(2026-06-09) and test-spec's REQ-J1.5 entry scoped the checklist to only
REQ-J1.5's three gate conditions. The purge is not one of the three, so row 8's
mitigation was hollow until now.

Resolution (human-selected at the panel-review handoff, "Apply here" over a
`/spec-kickoff` delta re-walkthrough): the checklist's scope is the three gate
conditions **plus every release-blocking gated Deferred entry** (currently the
purge, human-reserved per REQ-J1.4 — the checklist verifies it happened, it
does not perform it). The general "release-blocking Deferred entries" phrasing
keeps future Deferred entries with a before-any-public-release gate from
re-opening this same gap.

Writer note: REQ-F1.10 reserves meaning-class entries for `/spec-kickoff`'s
sign-off flow; this entry is written by the panel-review session under explicit
human authorization (auditable here, one revert from undone, reviewable at the
PR — the same recourse F1.10 names for misclassification).

Lens pass (delta-scoped, this review's canonical table): 8 lenses none/n-a;
cross-file consistency 1 finding (this amendment), validated 3/3 (reproduced in
all three files; no other purge→T19 wiring exists; git history pins the drift
to 8739abb vs 9b18d45).

Edits: tasks.md (T19 deliverables + Done-when widened, citations + D-27 /
REQ-J1.4), test-spec.md (REQ-J1.5 entry aligned), requirements.md (changelog),
this brief (this section).

Signed off: 2026-06-11 (human, panel-review handoff)

Class: meaning
Lens-pass: recorded above (this section), findings dispositioned 2026-06-11.
Anchor: `dcb342304ccfe699d266cafea554b8a7bdb04068` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).

## Amendment 7 — F1.9/F1.10 fixture completion (2026-06-11, pre-merge class)

Self-review (full 8-lens fan-out per Discovery Rigor; performance n/a for a
doc-only diff) over the whole branch diff. Raw candidates ~30; all but two
dropped at validation: the error-handling and concurrency candidates
re-reported this brief's own Amendment 2 design-gap backlog (recorded
deferrals), the stale Section 2/3 counts ("77 REQs", "37 D-IDs") are
true-at-signing statements in append-only historical sections, and the
remaining doc/naming candidates failed pass-1 reproduction.

Lens pass (branch-scoped): 8 lenses none/n-a; tests/verification 2 findings,
both validated 3/3 and human-approved (Apply/Apply) at the self-review
handoff:

1. test-spec F1.9 fixtures covered three of the REQ's four fail-closed halt
   conditions; "entry from a non-sanctioned writer" (dispatch-time gate halt,
   distinct from F1.10's write-time rejection) added as the fourth.
2. test-spec F1.10 had no fixture for the REQ's writer-side refusal clause;
   added: a kickoff flow whose lens-pass findings are absent or undispositioned
   refuses to write the meaning-class anchor entry.

No normative REQ text changed; the additions tighten verification coverage of
clauses already normative since Amendment 5. Writer note: as with Amendment 6,
this meaning-class entry is written by the review session under explicit human
authorization rather than `/spec-kickoff` (REQ-F1.10's named writer);
auditable here, one revert from undone, reviewable at the PR.

Edits: test-spec.md (F1.9 fixture list, F1.10 parse fixtures),
requirements.md (changelog), this brief (this section).

Signed off: 2026-06-11 (human, self-review handoff)

Class: meaning
Lens-pass: recorded above (this section), findings dispositioned 2026-06-11.
Anchor: `6acda5043ac116723def8c3be786a43f747f15e0` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).

## Expression-only re-anchor (2026-06-11, Copilot review)

Machine-written entry per REQ-F1.10's expression-only lane. Edits: test-spec.md
(A1.8 mixed fixture reframed as a proposed-identifier string; a path-like input
like `good-name/../escape` can never exist as a single on-disk directory name,
so the fixture is implementable only as string validation before any path is
formed; surfaced by GitHub Copilot's first PR review, thread validated 3/3),
requirements.md (changelog). Changelog: requirements.md, entry "2026-06-11
(expression-only, Copilot review)". Human-approved (Apply) at the
copilot-review handoff before application.

Class: expression-only
Anchor: `d1f2575e36e8ffa95dfb3ab924dc3a4092d61252` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).

## Expression-only re-anchor (2026-06-11, Copilot pairing iter 1)

Machine-written entry per REQ-F1.10's expression-only lane. Edits: test-spec.md
(H1.6 and I1.4 verification tags normalized from `[manual, via the joint entry
under REQ-B/D]` to pure `[manual]`; the bracket prose duplicated what the entry
bodies already say and broke the "tag includes [manual]" sweep convention that
Task 18's manual-verification checklist greps on; surfaced by GitHub Copilot's
second PR review, both threads validated 3/3 as one root issue),
requirements.md (changelog). Changelog: requirements.md, entry "2026-06-11
(expression-only, Copilot pairing iter 1)". Section 4's "~23 [manual]" pure-tag
count reads 25 after normalization; the recorded tilde-approximation stands as
a historical statement.

Class: expression-only
Anchor: `7b8ce0c480c1f203d1732f1b1a41622538bf762f` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).

## Expression-only re-anchor (2026-06-11, Copilot pairing iter 2)

Machine-written entry per REQ-F1.10's expression-only lane. Edits: tasks.md
(dependency-graph intro reworded "generated" → "derived"; no generator tooling
exists in-repo, the view is maintained by hand against the authoritative
`Dependencies:` lines; surfaced by GitHub Copilot's third PR review, thread
validated 3/3), requirements.md (changelog). Changelog: requirements.md, entry
"2026-06-11 (expression-only, Copilot pairing iter 2)".

Class: expression-only
Anchor: `539c3fbafd32259d79956de339d3344e05c9568b` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).

## Expression-only re-anchor (2026-06-11, Copilot pairing iter 3)

Machine-written entry per REQ-F1.10's expression-only lane. Edits: test-spec.md
(H1.3 fixture "echoed stripped" → "echoed with the control characters
stripped", mirroring REQ-H1.3's own phrasing "control characters stripped when
echoed"; surfaced by GitHub Copilot's fourth PR review, thread validated 3/3),
requirements.md (changelog). Changelog: requirements.md, entry "2026-06-11
(expression-only, Copilot pairing iter 3)".

Class: expression-only
Anchor: `cef5c9c6270e322485c1687786559393550c258f` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).

## Expression-only re-anchor (2026-06-11, orchestrate state move: Task 3 dispatch)

Machine-written entry per REQ-F1.10's expression-only lane. Edits: tasks.md only
— Task 3 moved Forward plan → In progress with dispatch metadata (backend=tmux,
window `pw-bootstrap-task-3`, branch `planwright/bootstrap/task-3`). This is an
orchestration-state placement move, content REQ-F1.9 excludes from the anchor
under the canonical extraction; the interim whole-file form cannot express that
exclusion, so the state move forces this re-anchor. (The interim form's safety
note — "no state moves can occur before the dispatch tooling exists" — is
superseded in practice by this emulated dispatch; recorded here so the gate
stays coherent.) No task-definition content, requirement, design decision, or
test-spec entry changed: pre-move anchor `cef5c9c6270e322485c1687786559393550c258f`
verified matching immediately before the move inside the D-10 lock window.

Class: expression-only
Anchor: `2fe3ed5046b1de26c8f1c6c8078029d279de4bc3` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).

## Expression-only re-anchor (2026-06-11, orchestrate state move: Task 4 dispatch)

Machine-written entry per REQ-F1.10's expression-only lane. Edits: tasks.md only
— Task 4 moved Forward plan → In progress with dispatch metadata (backend=tmux,
window `pw-bootstrap-task-4`, branch `planwright/bootstrap/task-4`). Same
orchestration-state-placement rationale as the Task 3 dispatch entry above.
Pre-move anchor `2fe3ed5046b1de26c8f1c6c8078029d279de4bc3` verified matching
immediately before the move inside the D-10 lock window.

Class: expression-only
Anchor: `e469f8f2f23c5aefb193718b4aa225b2982b70aa` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).

## Expression-only re-anchor (2026-06-11, orchestrate state move: Task 1 dispatch)

Machine-written entry per REQ-F1.10's expression-only lane. Edits: tasks.md only
— Task 1 moved Forward plan → In progress with dispatch metadata (backend=tmux,
window `pw-bootstrap-task-1`, branch `planwright/bootstrap/task-1`). Same
orchestration-state-placement rationale as the Task 3 dispatch entry above.
With this dispatch the in-flight unit count reaches `max_parallel_units` (3).
Pre-move anchor `e469f8f2f23c5aefb193718b4aa225b2982b70aa` verified matching
immediately before the move inside the D-10 lock window.

Class: expression-only
Anchor: `d623c4a54df920e0b6821e60c9aa9f962511c4c1` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).

## Expression-only re-anchor (2026-06-11, orchestrate state move: Task 3 PR reconcile)

Machine-written entry per REQ-F1.10's expression-only lane. Edits: tasks.md only
— Task 3's In-progress annotation updated `implementing` → `draft-pr-ready ·
PR #2 (draft)` after the worker opened the draft PR. Same
orchestration-state-placement rationale as the dispatch entries above.
Pre-move anchor `d623c4a54df920e0b6821e60c9aa9f962511c4c1` verified matching
immediately before the move inside the D-10 lock window.

Class: expression-only
Anchor: `0e9a573662ec91db2af3ecffd76365026ea64fe2` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).

## Expression-only re-anchor (2026-06-11, orchestrate state move: Task 1 PR reconcile)

Machine-written entry per REQ-F1.10's expression-only lane. Edits: tasks.md only
— Task 1's In-progress annotation updated `implementing` → `draft-pr-ready ·
PR #3 (draft)` after the worker opened the draft PR (two commits: the status
move, then this entry's format alignment to the Task 3 sibling annotation).
Same orchestration-state-placement rationale as the dispatch entries above.
Pre-move anchor `0e9a573662ec91db2af3ecffd76365026ea64fe2` verified matching
immediately before the move.

Class: expression-only
Anchor: `c9336cb51543bf9e528ad5ef389296bf21c0834f` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).

## Expression-only re-anchor (2026-06-11, orchestrate state move: Task 4 PR reconcile)

Machine-written entry per REQ-F1.10's expression-only lane. Edits: tasks.md only
— Task 4's In-progress annotation updated `implementing` → `draft-pr-ready ·
PR #4 (draft)` after the worker opened the draft PR. Same
orchestration-state-placement rationale as the entries above. With this move
all three dispatched units (T1, T3, T4) are draft-pr-ready; no Forward-plan
task is ready until a merge lands. Pre-move anchor
`c9336cb51543bf9e528ad5ef389296bf21c0834f` verified matching immediately
before the move inside the D-10 lock window.

Class: expression-only
Anchor: `a217310efe10a830ae357cae6492e51d4260de77` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).

## Expression-only re-anchor (2026-06-11, orchestrate state move: Task 3 Completed)

Machine-written entry per REQ-F1.10's expression-only lane. Edits: tasks.md only
— Task 3 moved In progress → Completed after PR #2 merged (human-reserved
action). The full task block is preserved in Completed (definition content
intact; only the Status annotation changed), so under the canonical extraction
this remains a placement-only move. Pre-move anchor
`a217310efe10a830ae357cae6492e51d4260de77` verified matching immediately
before the move inside the D-10 lock window.

Class: expression-only
Anchor: `c47f8b6028b193bd4e87030d95f38f7df06b39b6` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).

## Expression-only re-anchor (2026-06-11, orchestrate state move: Task 7 dispatch)

Machine-written entry per REQ-F1.10's expression-only lane. Edits: tasks.md only
— Task 7 moved Forward plan → In progress with dispatch metadata (backend=tmux,
window `pw-bootstrap-task-7`, branch `planwright/bootstrap/task-7`). Ready via
Task 3's completion (PR #2 merged); selected critical-path-first (T7 heads the
longest remaining chain T7→T11→T12→T13→T18→T19). Slot accounting: draft-pr-ready
units (T1, T4) hold no active-worker slot; active workers after this dispatch: 1.
Same orchestration-state-placement rationale as the entries above. Pre-move
anchor `c47f8b6028b193bd4e87030d95f38f7df06b39b6` verified matching immediately
before the move inside the D-10 lock window.

Class: expression-only
Anchor: `a27684b6e23f5d60f4dec51458f567fd8a14f504` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).

## Expression-only re-anchor (2026-06-11, orchestrate state move: Task 15 dispatch)

Machine-written entry per REQ-F1.10's expression-only lane. Edits: tasks.md only
— Task 15 moved Forward plan → In progress with dispatch metadata (backend=tmux,
window `pw-bootstrap-task-15`, branch `planwright/bootstrap/task-15`). Ready via
Task 3's completion; second of the two units that merge unlocked (no cohesion
bundle with T7: gate wiring vs. doctrine doc). Active workers after this
dispatch: 2 of 3. Same orchestration-state-placement rationale as the entries
above. Pre-move anchor `a27684b6e23f5d60f4dec51458f567fd8a14f504` verified
matching immediately before the move inside the D-10 lock window.

Class: expression-only
Anchor: `5f8633a9a5182cdc3dde52117fcd82cd08e03771` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).

## Expression-only re-anchor (2026-06-11, orchestrate state move: Task 7 PR reconcile)

Machine-written entry per REQ-F1.10's expression-only lane. Edits: tasks.md only
— Task 7's In-progress annotation updated `implementing` → `draft-pr-ready ·
PR #5 (draft)` after the worker opened the draft PR. Same
orchestration-state-placement rationale as the entries above. Pre-move anchor
`5f8633a9a5182cdc3dde52117fcd82cd08e03771` verified matching immediately before
the move inside the D-10 lock window.

Class: expression-only
Anchor: `fcf84b3ce2c1f78d5b570d46d10d4c110dcb1a51` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).

## Expression-only re-anchor (2026-06-11, orchestrate state move: Task 15 PR reconcile)

Machine-written entry per REQ-F1.10's expression-only lane. Edits: tasks.md only
— Task 15's In-progress annotation updated `implementing` → `draft-pr-ready ·
PR #6 (draft)` after the worker opened the draft PR. All in-flight units (T1,
T4, T7, T15) are now draft-pr-ready; zero active workers; nothing dispatchable
until a merge. Same orchestration-state-placement rationale as the entries
above. Pre-move anchor `fcf84b3ce2c1f78d5b570d46d10d4c110dcb1a51` verified
matching immediately before the move inside the D-10 lock window.

Class: expression-only
Anchor: `9bbf9961fb754089a3d5e84312c450bcac313fd4` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).

## Expression-only re-anchor (2026-06-11, orchestrate state move: Task 1 Completed)

Machine-written entry per REQ-F1.10's expression-only lane. Edits: tasks.md only
— Task 1 moved In progress → Completed after PR #3 merged (human-reserved
action). The merge produced conflicts in tasks.md and this brief (the PR branch
carried dispatch-time snapshots of both); resolved by keeping the primary
checkout's state (the branch side was a strict subset/stale snapshot — verified
hunk by hunk before resolving). Full task block preserved in Completed. The
pre-move anchor `9bbf9961fb754089a3d5e84312c450bcac313fd4` was verified
matching immediately after the conflict resolution and before this move,
inside the D-10 lock window.

Class: expression-only
Anchor: `13c2af6516317a653052e66003b4b80f6188e432` — computed as
`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`
(manifest form over whole files; the sanctioned interim form until Task 4's
canonical tasks.md extraction ships).
