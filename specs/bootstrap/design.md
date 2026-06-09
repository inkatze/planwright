# planwright Bootstrap — Design

**Status:** Draft
**Last reviewed:** 2026-06-09
**Format-version:** 1

Decision log for building planwright v1. Each decision carries a Decision,
Alternatives considered, and Chosen because. **N** = new this drafting session;
**C** = carried from pair-flow (validated in v1, re-grounded for a standalone
framework). Carried decisions cite their pair-flow origin.

## Decision log

### D-1: Spec format is versioned, declared per-spec  (N)

**Decision:** The four-file meta-spec carries a format-version; each spec bundle
declares the `Format-version:` it targets, and the validator keys its rules off
that version.

**Alternatives considered:**
- Unversioned single format. Rejected because: a future format change becomes a
  silent breaking change for every adopter's existing specs, with no migration
  signal.

**Chosen because:** planwright is built for external adopters; a versioned format
is a stable contract that can evolve without breaking pinned specs.

### D-2: `tasks.md` is canonical orchestration state; no parallel state file  (C, pair-flow D-1)

**Decision:** `tasks.md` doubles as the orchestration state record (Forward plan /
In progress / Completed / Awaiting input / Deferred / Out of scope). No separate
`state.json`.

**Alternatives considered:**
- A separate machine-state file. Rejected because: a second source of truth can
  desync from the spec and isn't human-readable in the same place.

**Chosen because:** single source of truth, version-controlled, degrades gracefully
(stale entries recoverable from PR + git log), validated across 7-day multi-session
work in pair-flow v1.

### D-3: Two-brief model — kickoff is contract, handover is optional cache  (C, pair-flow D-2)

**Decision:** `specs/{feature}/kickoff-brief.md` is the durable contract;
`{worktree}/.claude/handover.md` is an optional cache of in-flight context.

**Alternatives considered:**
- Single brief that is both contract and scratchpad. Rejected because: it couples
  the durable contract to volatile working state.

**Chosen because:** robust under partial failure — the spec/brief is always correct;
the handover is best-effort. Survived multi-day work in v1 unmodified.

### D-4: Four-bucket finding categorization with explicit predicates  (C, pair-flow D-3)

**Decision:** Findings route into Auto-applicable, Agent-resolvable, Needs sign-off,
or Needs human judgment, each with an explicit predicate; skills present all four as
tables (including empties).

**Alternatives considered:**
- A binary apply/surface split. Rejected because: it collapses the distinct
  "resolve-with-test-evidence" and "needs-a-human-decision" shapes.

**Chosen because:** typed dispatch determining agent autonomy is planwright's
distinctive contribution; the four buckets match the honest decision shape a human
would otherwise have to make.

### D-5: Solo vs multi-reviewer autonomy split; multi-reviewer is the safe default  (C+N, pair-flow D-4/D-20)

**Decision:** In solo repos Agent-resolvable auto-applies; in multi-reviewer repos it
surfaces for review with evidence. On ambiguous repo-class signals the safe default is
multi-reviewer.

**Alternatives considered:**
- Default solo on ambiguity. Rejected because: the cost of guessing solo on a true
  multi-reviewer repo is auto-applying changes that should have been reviewed — the
  more dangerous error.
- Refuse to proceed until confirmed. Rejected because: it blocks zero-config autonomy
  on first run.

**Chosen because:** safe-by-default; surfacing for confirmation (D-6) catches the
mistake cheaply while keeping the bootstrap zero-config.

### D-6: repo-class inferred and surfaced for confirmation, never silently written  (C, pair-flow D-20)

**Decision:** On a repo with no config entry, infer repo-class from PR history (a
non-author human reviewer in recent PRs → multi-reviewer; else → solo), always surface
for confirmation, and write the entry only on confirm.

**Alternatives considered:**
- Silent inference + write. Rejected because: a wrong silent guess changes autonomy
  behavior without the human's knowledge.

**Chosen because:** zero-config bootstrap with a human checkpoint at the one decision
that governs autonomy.

### D-7: Stateless step-machine orchestration  (C, pair-flow D-5)

**Decision:** `/orchestrate` holds no internal state. Each invocation reads `tasks.md`,
computes the next move, performs it, updates `tasks.md`, and exits.

**Alternatives considered:**
- A long-running orchestrator holding remaining work in memory. Rejected because: it
  is fragile across session boundaries and has state to corrupt.

**Chosen because:** the only state is `tasks.md` on disk; any invocation can crash and
the next re-reads and continues. Compatible with scheduled runners.

### D-8: One unit per invocation; intra-spec parallelism via multiple invocations  (C, pair-flow D-52)

**Decision:** Each `/orchestrate` invocation advances exactly one unit (a single task or
one cohesion-bundle per D-9) and exits. Throughput comes from running it concurrently
(multiple tmux windows or a scheduler), serialized only during the brief state-changing
move by the per-spec lock (D-10).

**Alternatives considered:**
- Loop through all ready tasks in one run. Rejected because: it rebuilds the fragile
  long-running-state model D-7 avoids.

**Chosen because:** keeps the orchestrator stateless and crash-safe; matches the
validated private-work-repo workflow of running parallel workstreams in separate windows.

### D-9: Cohesion-first PR bundling  (N, replaces pair-flow D-11/D-24 line-count rule)

**Decision:** `/orchestrate` bundles consecutive ready tasks only when they form one
coherent, revertable, single-purpose deliverable (same module/concern + shared
dependencies). Combined size is a guardrail against bloat, not the primary signal.

**Alternatives considered:**
- pair-flow's line-count-primary heuristic (Citations + git-history estimation).
  Rejected because: it optimizes for diff size rather than PR quality, and the
  retrospective flagged it as unmeasured.

**Chosen because:** grounded in private-work-repo PR #161 (Tasks 3,4,5 bundled as one "storage
substrate" deliverable while single tasks shipped alone). A PR should be a good unit of
history — revertable, single-concern, right-sized — which is a cohesion property, not a
length property.

### D-10: Per-spec advisory lock, held only during state-changing moves  (C, pair-flow D-17/D-37)

**Decision:** A per-spec lockfile at `specs/{feature}/.orchestrate.lock` is held only
during task selection + `tasks.md` update, released before `/execute-task` runs.
Stale-lock break threshold: 15 minutes. Lock-acquire failure is a clean no-op.

**Alternatives considered:**
- Hold the lock for the whole execution. Rejected because: it serializes execution and
  defeats intra-spec parallelism (D-8).

**Chosen because:** cheap, crash-robust, and the short window unblocks parallel
execution while still serializing concurrent state mutations on the same spec.

### D-11: Test-first execution + adaptive CI retry  (C, pair-flow B1.3/D-25)

**Decision:** `/execute-task` writes the failing test first, confirms it fails for the
right reason, implements to green. CI retry is adaptive: transient failures (network,
timeouts, infrastructure) retry up to twice with backoff; logic failures (assertions,
type errors, compilation) escalate immediately; unknown defaults to logic.

**Alternatives considered:**
- Fixed retry count for all failures. Rejected because: retrying a logic failure wastes
  cycles and masks a real defect.

**Chosen because:** mirrors how a human developer triages CI; test-first is the
discipline that makes Agent-resolvable findings trustworthy.

### D-12: Review surface is the gate-wired core only  (N)

**Decision:** v1 ships `/self-review` + `/polish` (the workflows wired into the
categorization gate). `/peer-review`, `/code-review`, `/panel-*`, `/copilot-*` are
fast-follows.

**Alternatives considered:**
- Ship the generic peer/code-review workflows too. Rejected because: they are commodity
  (every review tool does PR review) and add surface without adding differentiation.

**Chosen because:** planwright's differentiation lives in the autonomy gate, not the act
of reviewing. `/self-review` feeds `/polish`, and `/polish` routes findings through the
four buckets and the solo/multi-reviewer split — that is the distinctive part.

### D-13: Skill-to-skill invocation is in-session  (C, pair-flow D-39)

**Decision:** When one skill invokes another (e.g. `/execute-task` calling `/polish`),
it runs in the same Claude Code session; hooks fire once per actual tool call; inbox/
state is owned by the outer skill.

**Alternatives considered:**
- Launch nested skills as separate processes. Rejected because: it duplicates hook
  firings and fragments state ownership.

**Chosen because:** skills compose as functions, not as separate processes.

### D-14: Cross-session awareness is out of v1 scope  (N)

**Decision:** The inbox/heartbeat/tmux dashboard layer (pair-flow REQ-F) is not in v1;
it is a documented fast-follow.

**Alternatives considered:**
- Genericize a delivery-agnostic awareness layer in v1. Rejected because: it is the
  most host/tmux-coupled and least-validated layer (retrospective §5).

**Chosen because:** v1 keeps orchestration (core to the autopilot promise) and drops the
most personal-preference-laden, least-validated layer.

### D-15: Engineering builder is doctrine doc + skill + lifecycle hooks, stake-aware  (N)

**Decision:** The opinionated engineering builder is delivered as (a) an engineering
doctrine doc encoding the decision process, (b) a builder skill that detects the stack
and applies/recommends guards, and (c) hooks into `/spec-draft` (design phase) and
`/execute-task` (applies guards).

**Alternatives considered:**
- A standalone skill with embedded opinions. Rejected because: the opinions aren't
  reusable by other skills and don't participate in the spec lifecycle.
- Folding into the existing rigor docs. Rejected because: it conflates "detect what
  exists" (rigor) with "establish what should exist" (builder) and flattens complexity.

**Chosen because:** follows planwright's own composable pattern (knowledge in doctrine
docs, behavior in skills, enforcement in hooks) and Claude Code's native grain.

### D-16: The builder escalates load-bearing "mechanical" decisions instead of flattening  (N)

**Decision:** The builder auto-applies universal mechanical guards but escalates
decisions that look mechanical yet carry technical + business/domain stakes
(authentication, data modeling, security posture, integration surface) as design
decisions / Needs-human-judgment, routed into the deferral mechanism (D-17).

**Alternatives considered:**
- Treat all standards as a flat auto-applied checklist. Rejected because: it would
  auto-stamp decisions like auth that are architecture-defining and business
  differentiators (grounded in the private-work-repo auth example).

**Chosen because:** the builder's primary intelligence is recognizing which
seemingly-mechanical decisions are actually load-bearing and refusing to auto-resolve
them. This is what distinguishes it from an "add a linter" scaffolder.

### D-17: Drain mechanism — condition-gated entries + bookkeeping pass + `/drain`  (N)

**Decision:** Every deferral is a structured `GATE(when: …)` line written inline where
the work/decision was deferred. The `/orchestrate --bookkeeping` pass evaluates open
gates and re-surfaces satisfied items (moving them to Awaiting input / In progress or
flagging them in the report); the same evaluator is exposed as an on-demand `/drain`
move. Condition gates (a landed task/dependency) are preferred over date gates; date
gates only surface, never hard-fail. The pass never auto-resolves or auto-drops.
Deferred decisions carry a confidence level so low-confidence items resurface first.

**Alternatives considered:**
- Gates-in-files only (no skill). Rejected because: lacks an on-demand escape hatch.
- A dedicated `/drain` skill only. Rejected because: reliability would depend on
  remembering to run it — the documented rot mode for ADRs and tech-debt registers.

**Chosen because:** research (`eslint-plugin-unicorn` `expiring-todo-comments`, tickgit,
Azure WAF ADR confidence levels, the stale-bot critique) shows the reliable pattern puts
the drain in automation while keeping the writer's friction to one inline line, and never
auto-drops on a timer — which also matches planwright's human-reserved-actions invariant.

### D-18: Accumulator taxonomy with a defined drain per class  (N)

**Decision:** Every staging/accumulator surface is classified into one of three classes,
each with a named drain ritual: self-draining live state (automatic, e.g. the advisory
lock's release + stale-break); state-machine durable state (drained by skill/hook
transitions, e.g. `tasks.md` sections on PR create/merge); manually-/condition-drained
seed accumulators (e.g. `_pending/notes.md`, `_observations/opportunities.md`, drained by
their canonical reader and the gate/bookkeeping pass).

**Alternatives considered:**
- Leave drain disciplines implicit and scattered (the pair-flow status quo). Rejected
  because: that is how `_observations` ended up with writers and no reader.

**Chosen because:** naming the taxonomy makes "no write-only deferral" (D-17, REQ-H1.2)
enforceable instead of aspirational.

### D-19: In-flight amendment ritual is axis-driven  (N)

**Decision:** The amendment axis is "does the change contradict an accepted decision or
alter a REQ's meaning?" Expression-only changes (typo, ambiguity, gap-fill in the spirit
of accepted decisions) are fixed in place with a mandatory dated Changelog entry and no
re-approval. Changes that contradict an accepted decision are superseded (D-20), with the
kickoff brief re-synced by diff-review and scoped re-sign-off for only the moved decision.

**Alternatives considered:**
- Re-approve on every spec edit. Rejected because: it makes in-spirit fixes heavyweight
  and blocks execution (specification-as-bureaucracy).
- Allow silent in-place edits of any kind. Rejected because: a silently moved contract is
  the fatal failure mode for agent execution.

**Chosen because:** the mandatory changelog is cheap insurance that makes fix-in-place
safe; supersede is the auditable escape hatch for genuine reversals (RFC/PEP/ADR practice).

### D-20: Stable, never-reused IDs; supersede-don't-mutate  (N)

**Decision:** REQ-IDs and D-IDs are stable and never reused. A changed-meaning
requirement/decision mints a new ID and marks the old `Superseded-by`; the old record's
body is never edited.

**Alternatives considered:**
- Rewrite IDs in place when meaning changes. Rejected because: it destroys the audit
  trail and breaks downstream citations.

**Chosen because:** stable never-reused IDs are the non-negotiable traceability primitive
(requirements-management practice); supersede preserves the why-it-changed.

### D-21: Fold-vs-new-bundle rule; extend by default  (N)

**Decision:** A new idea extends an existing bundle by default (append new REQ/D-IDs,
supersede what it overrides, grow `test-spec.md`, re-sync `tasks.md`, append a brief
changelog line; re-sign-off only if it touched an accepted decision) unless a spin-new
trigger fires: introduces a new external interface, is independently ownable, forces
decisions orthogonal to the bundle's domain, or would push the bundle past "one feature a
reader holds in their head." Bundles partition by functional separation.

**Alternatives considered:**
- Append-only separate files per change (one Spec Kit camp). Rejected because: forcing an
  agent to reconcile N historical fragments hurts agent context; git gives the audit trail
  for free.
- One mega-spec absorbing everything. Rejected because: the documented 37-doc/2MB
  agent-failure mode.

**Chosen because:** a single consolidated bundle the agent reads as the current contract,
with lineage preserved via stable IDs + changelog + supersede links, is the best fit for
agent execution against a contract.

### D-22: `/spec-draft` fold-detection always scans; the name is a hint  (N)

**Decision:** `/spec-draft` runs semantic fold-detection on every invocation regardless of
the feature name. On an overlap with no spin-new trigger it surfaces an extend
recommendation (extend as the default option) for the human to decide. It never auto-folds
and never silently obeys the name over a clear overlap.

**Alternatives considered:**
- Skip the scan when an explicit non-colliding name is given. Rejected because: it misses
  the "I named it X but it belongs in Y" case.
- Auto-fold when the overlap is unambiguous. Rejected because: folding is a
  contract-touching action and sits in tension with the human-reserved-decision invariant.

**Chosen because:** the name is a hint, not a command; surfacing-and-deciding catches
differently-named overlaps while keeping the human in control.

### D-23: `/spec-draft` mines `_observations` as a first-class seed, archives consumed entries  (N)

**Decision:** `/spec-draft` reads `specs/_observations/opportunities.md` as a first-class
seed source and archives/trims the entries it consumes.

**Alternatives considered:**
- Leave the opportunities log as write-only (the pair-flow bug). Rejected because: writers
  (`/execute-task`, `/polish`) with no canonical reader is a silent drop.

**Chosen because:** closes the writer-without-reader loop; the observations convention only
pays off if something reads it.

### D-24: Delivery is a Claude Code plugin (primary) + `~/.claude/` writer (fallback)  (N)

**Decision:** planwright ships primarily as a Claude Code plugin manifest; skills resolve
their externalized rule docs via a stable plugin-relative path. A documented `~/.claude/`
writer is the fallback, with no fish/mise/tmux/Ansible/symlink dependency.

**Alternatives considered:**
- `~/.claude/` writer as primary. Rejected because: it reintroduces a materialization step
  (the thing the seed wanted to avoid with Ansible).
- Both co-equal. Rejected because: it doubles the packaging + resolution surface for v1.

**Chosen because:** the plugin manifest is the modern Claude-Code-native mechanism and
gives the cleanest install story; the writer covers environments without plugin support.

### D-25: Status-aware validator, keyed off format-version  (C+N, pair-flow D-45)

**Decision:** The validator enforces four-file presence, per-task structure (stable ID,
Done when, Dependencies, Citations), and REQ↔test-spec coverage. Enforcement is
status-aware (warnings on Draft, errors on Active) and keyed off the declared
format-version (D-1).

**Alternatives considered:**
- Always-error enforcement. Rejected because: it blocks iterative drafting.

**Chosen because:** status-aware enforcement matches the lifecycle; version-keying lets the
format evolve.

### D-26: Hard invariants carried in unchanged  (C, pair-flow D-21/D-33/D-36)

**Decision:** Never auto-merge; never act on a non-Active spec (no bypass flag); never
auto-chain `/orchestrate` into `/spec-kickoff`; never force-push, amend, squash, or rebase
(new commits only); all framework-created PRs are drafts.

**Alternatives considered:**
- A bypass flag for ad-hoc execution. Rejected because: the kickoff is the contract;
  skipping it defeats the purpose.

**Chosen because:** these preserve human control at the boundaries that are permanent and
irreversible; the user stated they are constraints, not future capabilities.

### D-27: Private start; public release gated on three conditions  (N)

**Decision:** The repository starts private. Public release is gated on all three of: (a)
the CLAUDE.md rules are inlined into planwright's own docs; (b) the four-file format
meta-spec exists; (c) at least one clean multi-reviewer end-to-end run has completed.

**Alternatives considered:**
- Public from the start. Rejected because: the skills are hollow until the intelligence is
  migrated and the format meta-spec exists.

**Chosen because:** the three conditions are exactly what make planwright usable by someone
who isn't the author.

### D-28: MIT license  (N)

**Decision:** planwright is MIT-licensed.

**Alternatives considered:**
- Apache-2.0. Rejected (for v1) because: the explicit patent grant / contribution terms add
  weight not needed for a tool optimizing for broad adoption.

**Chosen because:** permissive, maximal adoption, minimal obligations — the right fit for a
framework meant to be widely used and embedded.

### D-29: Autopilot / pilot-in-command documentation model  (N)

**Decision:** planwright documents itself through the autopilot / pilot-in-command mental
model: the human must know how to operate the machine and retains the reserved controls
(sign-off, merge); the framework flies the spec once signed off.

**Alternatives considered:**
- Document skills in isolation without a unifying model. Rejected because: adopters need to
  understand where their control begins and ends.

**Chosen because:** the model makes the human-reserved controls legible and sets correct
expectations about autonomy being bounded by spec quality.

### D-30: `/resume` is a read-only context loader  (C, pair-flow D-47)

**Decision:** `/resume` loads kickoff brief + `tasks.md` + git log + PR state + optional
handover brief, surfaces uncommitted changes, and asks before proceeding. It does not
auto-stash, auto-commit, or auto-clean.

**Alternatives considered:**
- Auto-resolve uncommitted state. Rejected because: it makes a decision that belongs to the
  human.

**Chosen because:** surfaces information, defers the decision.

### D-31: Bookkeeping drain pass lives in `/orchestrate --bookkeeping`; `/drain` shares the evaluator  (N)

**Decision:** The gate-evaluation/re-surfacing drain runs as `/orchestrate --bookkeeping`
(also reconciling out-of-session merges into `tasks.md`); `/drain` invokes the same
evaluator on demand.

**Alternatives considered:**
- A wholly separate drain subsystem. Rejected because: the bookkeeping pass already needs to
  reconcile `tasks.md`; gate evaluation is the same kind of sweep.

**Chosen because:** one evaluator, two entry points (scheduled/bookkeeping and on-demand),
no duplicated logic.

### D-32: planwright dogfoods its engineering doctrine; CI stood up early  (N)

**Decision:** planwright's own quality guards + CI are stood up early (Task 2); every
framework task develops under green CI; and the builder, once built, is validated by
reproducing/auditing planwright's own guard set.

**Alternatives considered:**
- Set up CI late / only before public release. Rejected because: it leaves the other tasks
  untested and makes it impossible to validate the `/execute-task` + CI flow on planwright
  itself.

**Chosen because:** the framework's credibility depends on self-hosting its own standards,
and a working CI pipeline is a prerequisite for exercising the execution + adaptive-retry
flow.

### D-33: Config model is a tracked default + a local gitignored override  (N)

**Decision:** A tracked default config holds universal defaults (thresholds, gate
conventions); a local gitignored override (agent-maintained, per-repo) holds the
repo-class registry and overrides. repo-class entries are written only on human
confirmation (D-6).

**Alternatives considered:**
- Single tracked config with per-repo entries. Rejected because: per-machine/per-repo
  overrides don't belong in a shared tracked file.
- repo-level metadata inside the spec bundle. Rejected because: repo-class is a property of
  the repository, not the spec.

**Chosen because:** clean separation of universal facts from per-repo/personal settings;
matches the validated pair-flow two-file config split (pair-flow D-19).

### D-34: Implementation runtime is portable POSIX/bash  (N)

**Decision:** The validator, hooks, and writer scripts are portable shell (bash, POSIX
where feasible, compatible with macOS bash 3.2 and BSD tooling).

**Alternatives considered:**
- Python (stdlib). Rejected because: it adds an interpreter dependency the seed's "no mise"
  spirit pushes against.
- Node/TypeScript. Rejected because: it adds a toolchain + build step for small scripts.

**Chosen because:** zero extra runtime for adopters beyond a shell + git + gh; matches
pair-flow's shell scripts and Claude Code hook norms. Heavier logic (gate parsing) is
awkward but tractable in shell + awk.

### D-35: GitHub-only via `gh` for v1, with graceful degradation  (N)

**Decision:** v1 targets GitHub through the `gh` CLI for PR operations. PR-related
operations degrade gracefully on `gh` auth failure (local work proceeds; `/orchestrate`
records an Awaiting-input entry). Non-GitHub hosts (GitLab, Bitbucket) are out of v1 scope.

**Alternatives considered:**
- Abstract the git host now. Rejected because: it adds an abstraction layer for hosts that
  may never be needed, and only GitHub is validated.

**Chosen because:** keeps v1 focused on the one validated path; the abstraction is a clean
fast-follow if demand appears.

### D-36: Branch-naming convention  (C, pair-flow D-32)

**Decision:** Orchestrator-created branches use `planwright/{spec}/task-{id-or-ids}` (single
`3` / `3.5`, or `3-4` for a bundle). The `tasks-pr-sync` hook parses this to move task
blocks between `tasks.md` sections.

**Alternatives considered:**
- Free-form branch names. Rejected because: the sync hook needs a machine-parseable
  convention to map a PR back to its task(s).

**Chosen because:** namespaced, machine-parseable, signals planwright ownership.

### D-37: Worktree placement compatible with `claude --worktree`  (C, pair-flow D-54)

**Decision:** `/orchestrate` reuses the current worktree when clean (after a one-line
confirm) and otherwise creates fresh worktrees under `<repo>/.claude/worktrees/<branch-suffix>`
so Claude Code's native worktree tooling discovers them; it prints the re-open command after
create-or-reuse.

**Alternatives considered:**
- Place worktrees in an arbitrary external directory. Rejected because: `claude --worktree`
  and `EnterWorktree` would not discover them.

**Chosen because:** places worktrees where the native tooling looks; detect-and-reuse avoids
redundant worktrees.

## Cross-cutting concerns

- **Every deferral must drain.** D-16, D-17, D-18, and D-19 form one theme: escalations and
  deferrals are only safe if a named reader and a re-surfacing gate exist. "No write-only
  deferral" (REQ-H1.2) is the invariant; the accumulator taxonomy (D-18) is how it is made
  enforceable.
- **The autonomy gate is the spine.** Categorization (D-4/D-5) connects to execution (D-11)
  and to the builder (D-16): all three route work through the same typed-dispatch decision
  about what the agent may do autonomously versus surface.
- **Composability-by-default, reflexively.** The principle governs both the code planwright
  helps adopters write and planwright's own architecture (knowledge in doctrine docs,
  behavior in skills, enforcement in hooks; D-15).
- **Framework-script security.** planwright ships hooks that run on adopter machines and a
  `~/.claude/` writer. Its own scripts must avoid executing untrusted input, guard path
  access, and be auditable; the dogfooded CI (D-32) includes secret scanning and shellcheck
  over these scripts.
- **Graceful degradation.** Skills fail soft on missing prerequisites (not a git repo, `gh`
  or validator absent; D-35, REQ-K1.7), surfacing a clear message and doing whatever local
  work remains possible rather than failing opaquely.
