# Pair-Flow — Test Spec

**Status:** Active
**Last reviewed:** 2026-05-25

This file pins each REQ to a verification path. Most REQs are verified by manual exercise (the system is workflow infrastructure operated by the user, not a service with unit-testable boundaries). Markers used: `[manual]`, `[design-level only]`, `[Gherkin]` (where the scenario form helps articulate the check). Gherkin is used selectively per D-8, not throughout.

## REQ-A — Spec lifecycle (drafting and comprehension)

### REQ-A1.1, A1.2 — `/spec-draft` extracts requirements via Socratic questioning [manual]

```gherkin
[Gherkin]
Given the user invokes /spec-draft <name> with no seed material
When the user describes the feature in their own words
Then the agent extracts at least three REQ candidates, assigns stable IDs (REQ-X1.1...),
  and proposes SHALL/MUST language and a citation for each
And the user can red-line any REQ before it is recorded
```

Verified by: drafting one real upcoming spec (Task 7), inspecting the produced `requirements.md` for: stable IDs, SHALL/MUST language, citations, no prose-only REQs.

### REQ-A1.3 — `/spec-draft` records D-IDs with alternatives [manual]

Verified by: produced `design.md` contains at least one D-ID with `Alternatives considered:` and `Chosen because:` lines.

### REQ-A1.4 — `/spec-draft` proposes task graph with `Done when:`, `Dependencies:`, `Citations:` [manual]

Verified by: every task in the produced `tasks.md` has those three fields.

### REQ-A1.5 — `/spec-draft` pins each REQ to a verification path [manual]

Verified by: every REQ in the produced `requirements.md` is referenced by at least one entry in the produced `test-spec.md`.

### REQ-A1.6 — `/spec-draft` runs spec validator [manual]

Verified by: validator output appears in the session transcript before the agent declares the spec stakeholder-ready.

### REQ-A1.7 — `/spec-draft` uses seed sources [manual]

Verified by: invocation with `specs/_pending/notes.md` (or equivalent) present produces a draft that cites the seed in at least one REQ.

### REQ-A2.1, A2.2, A2.3 — `/spec-kickoff` walkthrough produces signed-off brief [manual]

```gherkin
[Gherkin]
Given an existing spec at specs/{feature}/ with REQs and decisions
When /spec-kickoff is invoked
Then the agent walks the spec section by section
And for each section the agent restates in its own words
And the agent surfaces at least one implicit domain term definition or assumption
And the user has the opportunity to red-line per section before the next section begins
And after all sections, the agent poses Socratic checks (slicing, edge cases, decision rationale)
And the kickoff brief is written to specs/{feature}/kickoff-brief.md only after the user signs off
```

Verified by: invocation on `tecpan/specs/settings`. The user signs off without major correction (success criterion for Task 6).

### REQ-A2.4 — Task graph reconstruction surfaces unstated dependencies [manual]

Verified by: invocation on a spec where the user knows of an unstated dependency. Agent's graph either lists the dependency or surfaces it as a flagged uncertainty.

### REQ-A2.5 — Risk register produced [manual]

Verified by: kickoff brief contains a `## Risks` section with at least one entry that names a plausible failure mode the user agrees is real.

### REQ-A2.6 — Brief invalidation is section-scoped [manual]

```gherkin
[Gherkin]
Given a signed-off kickoff brief referencing spec commit hash <h>
When tasks.md is reorganized (new commit <h'>) without touching other spec files
Then only the brief's Task graph section is marked invalidated
And other sections (REQ restatements, design walkthrough, risk register) remain signed off
And /spec-kickoff prompts for re-signoff on the Task graph section only

When requirements.md REQ-X is edited
Then only brief sections referencing REQ-X are invalidated
And /spec-kickoff prompts for re-signoff on those sections only

When multiple spec files change in a single commit beyond a threshold
Then the entire brief is invalidated (wholesale rewrite path)
```

Verified by: three induced changes (tasks.md reorder, single-REQ edit, wholesale rewrite). Each produces the expected invalidation scope.

### REQ-A2.7 — Retrofit mode on existing specs [manual]

Verified by: invocation on `tecpan/specs/org` (the spec identified as rough in the 2026-05-22 analysis) surfaces at least three implicit decisions or assumptions the user agrees were under-specified (success criterion for Task 6).

### REQ-A2.8 — Spec-looks-wrong escalation [manual]

```gherkin
[Gherkin]
Given a spec with a genuine inconsistency (e.g., REQ-X1 mandates X and REQ-X2 mandates not-X)
When /spec-kickoff walks the spec
Then the agent surfaces the inconsistency to the user
And halts without producing a brief
And offers two paths: (a) edit spec and re-run, or (b) record an explicit override in the brief with reasoning
```

Verified by: induced inconsistency in a test spec; observe halt, the choice prompt, and that no brief is written if the user chooses (a) and exits.

### REQ-A2.9 — Spec-touching skills bump `Last reviewed:` [manual]

Verified by: invoke `/spec-draft` or `/spec-kickoff` on a spec, make any change, and confirm each modified spec file's `Last reviewed:` line is set to the current date (D-40).

### REQ-A2.10 — Brief written incrementally [manual]

```gherkin
[Gherkin]
Given /spec-kickoff is in mid-walkthrough at section 3 of 5, with sections 1-2 already signed off
When the session is killed forcibly
Then the partial brief at specs/{feature}/kickoff-brief.md contains sections 1-2 only
And re-invocation of /spec-kickoff detects the partial brief
And resumes at section 3, not from the beginning
```

Verified by: induced kill during walkthrough; inspect partial brief; re-run and observe resume point.

### REQ-A2.11 — Kickoff briefs committed to git, not gitignored [design-level only]

Design-level only: briefs live at `specs/<feature>/kickoff-brief.md` as part of the committed bundle (D-49). The standing check is the absence of a `.gitignore` rule covering `kickoff-brief.md`; no runtime test.

### REQ-A2.12 — Brief invalidation uses D-51 wholesale-rewrite triggers [design-level only]

Design-level only: the choice between section-scoped (default) and whole-brief invalidation is governed by D-51's trigger list and implemented in `/spec-kickoff`'s invalidation logic; verified by design review against D-51.

### REQ-A3.1, A3.2, A3.3 — Spec status lifecycle [manual]

```gherkin
[Gherkin]
Given /spec-draft is invoked
When the draft completes
Then the new requirements.md declares Status: Draft

Given a Draft-status spec
When /spec-kickoff sign-off completes
Then requirements.md declares Status: Active

Given an Active-status spec with N tasks
When the Nth task moves to Completed
Then /orchestrate (or Task 12's bookkeeping runner) flips requirements.md to Status: Done

Given a Draft- or Done-status spec
When /execute-task or /orchestrate is invoked
Then the skill refuses to act, surfacing why (status not Active)
And exits cleanly
```

Verified by: end-to-end on a real spec across all three transitions, plus invocation attempts at each non-Active state.

## REQ-B — Task execution

### REQ-B1.1, B1.2 — `/execute-task` accepts one or many task IDs [manual]

Verified by: invocation with a single task ID and with a bundle (two adjacent tasks per D-11). Both produce a single PR.

### REQ-B1.3 — Test-first for new behavior [manual]

```gherkin
[Gherkin]
Given a task whose test-spec.md entry describes new behavior X
When /execute-task is invoked
Then the agent writes the test for X first
And the agent runs the test, confirming it fails for the intended reason
And only then writes implementation code
And the test passes after implementation
```

Verified by: session transcript shows the test was written before the implementation, the failure was observed, and the pass was observed.

### REQ-B1.4 — Regression test first for bug fixes [manual]

Same Gherkin shape as B1.3 but for a regression-fixing task.

### REQ-B1.5 — Research findings recorded in kickoff brief [manual]

Verified by: invocation on a task that requires consulting external docs. Kickoff brief's risk register gains an entry summarizing what was learned and from where.

### REQ-B1.6 — Project CI is green before declaring done [manual]

Verified by: session transcript shows `mix ci` (or equivalent, derived per D-19) was run and exited zero before PR open.

### REQ-B1.9 — CI retry policy is adaptive [manual]

```gherkin
[Gherkin]
Given /execute-task is running and the project CI fails with a network timeout
When the failure is classified as transient
Then /execute-task retries with exponential backoff up to 2 additional attempts
And if any retry succeeds, execution proceeds

Given /execute-task is running and the project CI fails with an assertion error
When the failure is classified as logic
Then /execute-task halts immediately without retry
And writes an Awaiting input inbox entry summarizing the failure
And tasks.md is updated to mark the task as Awaiting input
```

Verified by: induced transient failure (mock network error) and induced logic failure (broken assertion). Observe the classification and the differing responses.

### REQ-B1.7 — `/polish` invoked as final convergence [manual]

Verified by: session transcript shows `/polish` was invoked as the last step before PR open.

### REQ-B1.8 — Draft PR body references kickoff brief, task IDs, REQs [manual]

Verified by: produced PR body contains a path to the kickoff brief, task ID(s), and the REQs the change satisfies.

### REQ-B1.10 — `/execute-task` assumes its worktree exists [manual]

Verified by: invoke `/execute-task` standalone in a pre-created worktree and confirm it does not attempt worktree creation; confirm `/orchestrate` is what creates the worktree when it dispatches the task (D-44).

### REQ-B1.11 — `/execute-task` invokes `/polish` in the same session [manual]

Verified by: session transcript shows `/polish` ran as a sub-step of `/execute-task` within one Claude Code session (no nested session spawned); inbox state remains owned by the outer skill and hooks fire once per actual tool call (D-39).

## REQ-C — Autonomous resolution

### REQ-C1.1, C1.2 — Agent-resolvable bucket and predicate [manual]

```gherkin
[Gherkin]
Given a finding that has a failing test that becomes passing after the fix
And full project CI passes after the fix
And the fix is aligned with the active kickoff brief
And the fix is not in a hard-disqualifier zone
When /polish presents its three-bucket categorization
Then the finding appears in the Agent-resolvable bucket with attached evidence:
  the failing-then-passing test name, the CI invocation, and the kickoff alignment citation
```

Verified by: a real polish run on a task where the predicate holds. Inspect the categorization output for the new bucket with evidence rows.

### REQ-C1.3 — Solo repo auto-application [manual]

```gherkin
[Gherkin]
Given the active repo is declared Repo-class: solo
And a finding qualifies for Agent-resolvable
When /polish processes the finding
Then the fix is applied without human pause
And the bucket entry records the auto-apply with a timestamp
```

Verified by: run on tecpan (Repo-class: solo). Inspect that the fix landed without an `AskUserQuestion` interrupt.

### REQ-C1.4 — Multi-reviewer surfacing with evidence [manual]

Verified by: when (and only when) a multi-reviewer repo is in scope (out of v1 scope but predicate must be correctly checked), the same finding surfaces in the bucket but does not auto-apply.

### REQ-C1.5 — Skills recognize the bucket [manual]

Verified by: each affected skill's documentation file (`polish.md`, `panel-pairing.md`, etc.) contains the four-table presentation contract.

### REQ-C1.6 — Existing buckets unchanged [design-level only]

Verified by: diffing user-global CLAUDE.md against the prior version shows no edits to the definitions of `Auto-applicable`, `Needs sign-off`, `Needs human judgment`.

## REQ-D — Orchestration

### REQ-D1.1 — `/orchestrate` skill exists and advances a spec [manual]

Verified by: invocation on a spec with at least one ready task produces a draft PR.

### REQ-D2.2 — One task per invocation; intra-spec parallelism via multiple invocations [manual]

```gherkin
[Gherkin]
Given a spec with two ready independent tasks A and B
When /orchestrate is invoked once
Then exactly one of A or B is picked, dispatched, and the invocation exits
And the other ready task remains in "ready" status

When /orchestrate is invoked again from a separate session while task A is still in flight
Then task B is picked and dispatched in a separate worktree
And both tasks appear in tasks.md as "In progress"
And both produce independent draft PRs
```

Verified by: two-invocation scenario on a real spec with two independent tasks. Inspect tasks.md, worktrees, and resulting PRs.

### REQ-D2.1 — Statelessness across invocations [manual]

```gherkin
[Gherkin]
Given a spec with task X marked "In progress: PR #42 draft" in tasks.md
When /orchestrate is invoked from a fresh session (no in-memory state)
Then the agent reads tasks.md, recognizes task X is in flight, and either
  picks the next ready task or no-ops cleanly
And does not restart task X or duplicate the PR
```

Verified by: simulated fresh-session run on a partially executed spec.

### REQ-D3.1 — Ready-task identification [manual]

Verified by: spec with task B depending on task A. `/orchestrate` does not pick B until A is in `Completed`.

### REQ-D4.1 — Bundling per D-11 [manual]

Verified by: spec with two consecutive ready tasks meeting the bundling rule. Both end up in one PR.

### REQ-D10.1, D11.1, D12.1 — Orchestrator edge cases [manual]

Cross-spec concurrent (D10.1): two `/orchestrate` invocations on two different specs in the same repo both proceed; each touches its own per-spec lockfile. Verified by: launch both, observe two draft PRs.

Unkickoffed spec (D11.1): invoking `/orchestrate` on a spec with no kickoff brief halts cleanly and prompts the user to invoke `/spec-kickoff`; the orchestrator does not auto-chain into kickoff. Verified by: invoke on a fresh `Draft` spec, observe the halt + prompt + clean exit.

`gh` not authenticated (D12.1): with `gh auth status` showing logged out, invoke `/orchestrate` mid-cycle and `/polish` standalone. Orchestrate halts with `Awaiting input` inbox entry referencing the auth issue; polish's local convergence still completes (PR opening step degrades with the message).

### REQ-D9.1 — Configuration discovery flow [manual]

```gherkin
[Gherkin]
Given the current repo has no entry in ~/.claude/pair-flow.local.yml
When a pair-flow skill is invoked
Then the agent identifies owner/repo via gh repo view (or git remote)
And the agent infers a repo-class default from PR review history
And the inferred value is surfaced to the user with reasoning
And the agent does NOT write to pair-flow.local.yml until the user confirms or overrides
When the user confirms
Then the entry is appended with last-confirmed: <today>
When the user declines or cancels
Then nothing is written and the skill exits cleanly
```

Verified by: invocation in a fresh state (no pair-flow.local.yml). Observe the prompt, decline, verify no file is written. Re-invoke, confirm this time, verify the entry appears with today's date.

### REQ-D5.1 — Format gate with retrofit offer [manual]

```gherkin
[Gherkin]
Given a spec whose tasks.md uses prose without stable IDs or Done-when conditions
When /orchestrate is invoked
Then orchestration halts before performing any move
And the agent offers to invoke /spec-kickoff in retrofit mode
And the user can accept (retrofit runs) or decline (orchestration aborts cleanly)
```

Verified by: invocation on `tecpan/specs/org` as-is. Halt and retrofit offer observed.

### REQ-D6.1 — v1 halts after PR open [manual]

Verified by: orchestration sequence ends at draft PR creation; no post-PR actions taken.

### REQ-D7.1 — Halt conditions emit `Awaiting input` [manual]

Verified by: induced failure modes (ambiguous task, hard-disqualifier finding, contract drift) each result in an inbox entry with state `awaiting-input` and a description of what's blocking.

### REQ-D8.1 — Lockfile coordination [manual]

Verified by: two concurrent `/orchestrate` invocations on the same spec. Second one no-ops cleanly with a logged reason.

## REQ-E — Continuity across sessions

### REQ-E1.1 — `tasks.md` sections present [manual]

Verified by: any spec produced by `/spec-draft` or retrofitted by `/spec-kickoff` contains all five sections.

### REQ-E1.2 — `In progress` annotation format [manual]

Verified by: a task in flight is annotated with phase and timestamp.

### REQ-E5.1 — Uncommitted changes on `/resume` [manual]

```gherkin
[Gherkin]
Given a worktree with uncommitted changes (modified files, untracked files, or staged files)
When /resume is invoked
Then the agent surfaces git status to the user
And asks before proceeding
And does not auto-stash, auto-commit, or auto-clean
```

Verified by: deliberately leaving uncommitted changes in a test worktree; invoke `/resume`; observe the prompt; verify nothing changed on the file system if the user declines.

### REQ-E2.1, E2.2 — `/resume` loads context without requiring handover [manual]

```gherkin
[Gherkin]
Given a worktree with an in-flight task in tasks.md
And no handover brief file exists in the worktree
When the user opens a fresh Claude session in that worktree and types /resume
Then the agent reads the kickoff brief, tasks.md, recent git log, and open PR state
And produces a summary that the user verifies is sufficient to continue work
```

Verified by: actual cold-start session on a real tecpan worktree (success criterion for Task 5).

### REQ-E3.1 — Side-effect updates to tasks.md [manual]

Verified by: each affected skill's run produces a corresponding tasks.md edit observable in git diff.

### REQ-E4.1 — Optional handover brief does not block resume [design-level only]

Verified by: `/resume` skill's prompt explicitly states the handover is optional; absence is not an error.

## REQ-F — Cross-session awareness

### REQ-F1.1, F1.2 — Inbox substrate exists, writes JSON with heartbeat [manual]

Verified by: `~/.claude/inbox/` exists; sample inbox entry contains the documented fields (`host`, `session`, `repo`, `branch`, `state`, `first-seen`, `last-heartbeat`, optional `summary`). Heartbeat refreshes every ~30 seconds while the session is alive.

```gherkin
[Gherkin]
Given an active session writing inbox entries with last-heartbeat refreshed every 30s
When the session is killed forcibly (kill -9, no chance to clean up)
Then the entry remains in the file but readers (dashboard, status segment) skip it within 2 minutes
And the dashboard popup no longer shows the entry

Given a legacy inbox entry written by an older skill version with no last-heartbeat field
When 24 hours pass with no activity
Then readers skip the entry and the next sweep removes it
```

Verified by: induced kill-9 on a session and timed inspection of the dashboard.

### REQ-F2.1 — tmux popup renders inbox [manual]

```gherkin
[Gherkin]
Given two concurrent Claude sessions writing inbox entries
When the user presses the bound tmux key combination
Then a popup appears listing both entries
And entries with state "awaiting-input" appear first in the list
And selecting an entry shows its full JSON contents
```

Verified by: actual two-session test (success criterion for Task 3).

### REQ-F2.2 — tmux status segment counts `awaiting-input` [manual]

Verified by: same test; status bar segment shows the correct integer.

### REQ-F2.3 — Long-running task visual distinction [manual]

```gherkin
[Gherkin]
Given a session writing inbox entries continuously, with first-seen timestamp at T
When 30 minutes pass (current time = T + 30 min) and state is still "working"
Then the entry is rendered in yellow in the tmux popup
And it sorts above green (fresh) entries but below red and orange
When 2 hours pass (current time = T + 2 hr) and state is still "working"
Then the entry is rendered in orange
And it sorts above blue, yellow, green
```

Verified by: a deliberately long-running test session held open for >2 hours. Observe yellow at 30 min, orange at 2 hr.

### REQ-F3.1 — macOS notification on state transition [manual]

Verified by: triggered transition observed as a macOS Notification Center entry.

### REQ-F4.1 — Phone push is out of scope for v1 [design-level only]

Verified by: v1 ships without phone push integration; design accommodates layering it on later (the inbox file substrate is the future reader's source).

## REQ-G — Operational integration

### REQ-G1.1 — Panel-* investigation deliverable exists [manual]

Verified by: `specs/pair-flow/research/panel-underuse.md` exists, names a primary cause, cites transcript evidence, and recommends one of the three options (Task 1's `Done when`).

### REQ-G2.1 — File-path PreToolUse hook installed and scoped [manual]

Verified by: hook is wired in `settings.json`. Manually exercised on a known-bad path for each of `Read`, `Edit`, `Write` — clean error observed all three times. `Bash` calls and `NotebookEdit` calls with non-existent paths pass through (out of v1 scope per D-26).

Telemetry baseline (82 mistakes/month) re-measured 30 days post-install and compared per the task's Measurement plan.

### REQ-G3.1 — Codex default on all profiles [manual]

Verified by: `/panel-review --help` (or equivalent) and skill source on each profile show codex as the default backend.

### REQ-G4.1 — New skills tracked under Ansible role [manual]

Verified by: each new skill file lives at `roles/osx/files/claude/commands/<name>.md` and is materialized into `~/.claude/commands/` after `mise run osx`.

### REQ-G5.1 — New hooks wired in settings.json [manual]

Verified by: each new hook is referenced in the tracked `roles/osx/files/claude/settings.json` and appears in the materialized file.

### REQ-G6.1 — Project CLAUDE.md updated [manual]

Verified by: a cold-read of the project CLAUDE.md by the user surfaces no missing information about the pipeline (Task 14's `Done when`).

### REQ-G7.1 — Validator extended, status-aware enforcement [manual]

```gherkin
[Gherkin]
Given a Draft-status spec with tasks missing Done-when or Citations
When the validator runs
Then the output contains warnings naming each missing field
And exit code is zero (non-blocking)

Given an Active-status spec with the same gaps
When the validator runs (e.g., as a precondition for /execute-task)
Then the output contains errors naming each missing field
And exit code is non-zero
And /execute-task refuses to act on this spec until the gaps are fixed
```

Verified by: same test spec flipped between Draft and Active status; run validator both ways; verify exit codes and skill behavior.

## What's not tested here

Explicitly listing out-of-scope verification so the bar is clear:

- **Performance of the orchestrator under load.** Not measured. The system is single-user, not a service. Sub-second responsiveness is not a goal.
- **Security of inbox JSON contents.** The inbox is on the user's filesystem; contents are not encrypted. If the user syncs via iCloud, Apple's encryption applies at rest. No additional encryption layer is verified.
- **Behavior under git merge conflicts in `tasks.md`.** Possible during concurrent orchestrator runs. Handled at the merge level; no special tooling.
- **Cross-version compatibility with future Claude Code releases.** The skills depend on Claude Code's slash-command and hook contracts; breakage on upgrade is detected by the next test cycle, not pre-emptively.
- **Telemetry accuracy.** The post-implementation re-analysis is point-in-time; not continuously validated.
- **Multi-reviewer behavior end-to-end.** The predicate (D-3, D-4) is implemented to support it, but the actual workflow on a multi-reviewer work repo is out of v1 scope (see Out of scope in `tasks.md`).
- **`/copilot-pairing` and `/copilot-review` integration.** These remain transitional and unchanged by this spec.
