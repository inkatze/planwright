# Environment Configuration

This system is configured with the following development environment:

## Shell Environment
- **Shell**: Fish shell (`fish`) - A smart and user-friendly command line shell
- **Version Manager**: `mise` (formerly rtx) - Multi-language runtime version manager
- **Terminal Multiplexer**: `tmux` - Terminal session manager

## Running Commands

When you need to execute commands on this system, please use this environment setup:

### Fish Shell
The default shell is Fish. Run commands directly in Fish:
```fish
# Fish shell commands work natively
echo "Hello from Fish"
```

### Mise for Runtime Management
Use `mise` to manage language versions (Node.js, Python, Ruby, etc.):
```fish
mise list              # List installed runtimes
mise current           # Show current versions
mise install node@20   # Install specific versions
```

### Running Mise-Managed Tools
**IMPORTANT**: When running any mise-managed tools, always use Fish shell with mise. The following languages and tools are managed by mise:
- **Languages**: Ruby, Python, Node.js/JavaScript, Go, Rust, Java, Elixir, Erlang
- **Tools**: Terraform, Ansible, and other CLI tools

Examples of running mise-managed tools (use `fish -c "..."` to ensure mise is available):
```bash
# Run Python scripts
fish -c "python script.py"

# Run Ruby scripts
fish -c "ruby script.rb"

# Run Node.js
fish -c "node app.js"
fish -c "npm install"
fish -c "npm run dev"

# Run Go
fish -c "go run main.go"

# Run Rust
fish -c "cargo build"

# Run Terraform
fish -c "terraform plan"

# Run Ansible
fish -c "ansible-playbook playbook.yml"
```

All these commands will automatically use the versions specified in `.mise.toml` or `.tool-versions` files in your project directories.

### Tmux Sessions
Tmux is available for managing terminal sessions:
```fish
tmux ls                # List sessions
tmux attach -t session # Attach to session
tmux new -s session    # Create new session
```

## Git Conventions

When creating git commits:
- Do NOT add `Co-Authored-By: Claude` or any co-author attribution
- Do NOT add the Claude Code generation footer
- Keep commit messages clean and conventional (type: description)
- The user will handle GPG signing

When pushing:
- MUST always specify the remote and branch explicitly: `git push origin branch-name`
- Never use bare `git push` without arguments

## Plan Mode & Implementation

Plans are written with limited context and the codebase may have changed since. When transitioning from a plan to implementation:
- **Plans are directional, not prescriptive**: Treat plans as a guide for intent and scope, not as step-by-step instructions to follow blindly
- **Verify before acting**: Always read the actual code before making changes. Don't assume the plan's description of file contents, function signatures, or structure is accurate
- **Adapt to reality**: If the code doesn't match what the plan expected, adjust your approach to fit the actual state of the codebase rather than forcing the plan's assumptions

## Design Principles

**Composability by default.** At the domain/logic layer, prefer small units that take data in and return data out. Compose them via the language's natural mechanism (pipes, chaining, function composition, middleware stacks) rather than coordinating through shared mutable state or deep inheritance. At the framework boundary (routing, config, ORM, DI), follow the framework's established conventions; a Phoenix context, a Rails controller, a Next.js route, a Go handler should look like what someone familiar with that stack expects. The test: "could I use this unit in a different context without importing its neighbors?" Don't reach for service abstractions, DDD aggregates, or architectural patterns unless the problem genuinely requires coordination beyond what function composition provides.

## Code & PR Reviews

When reviewing code, features, or addressing PR feedback:
- **Verify issues are real**: Before reporting an issue, confirm it by reading the relevant code and running tests/linters if applicable. Do not report speculative or hypothetical issues, only confirmed ones.
- **Present all issues first**: After analysis, present the complete list of confirmed issues as a numbered summary with brief descriptions.
- **Let the user choose the workflow**: Ask whether they want to review items (a) all at once / as a whole list (re-prioritize, group, bulk-dismiss), (b) one by one with discussion per item, (c) batched decisions (per-finding picklist via `AskUserQuestion`, up to 4 findings per call), or (d) clustered decisions (findings grouped by shared decision axis; one question per cluster; the answer applies to every finding in that cluster). Do not assume they want all items addressed at once. When the finding count is high (~10+), proactively suggest (c) or (d) rather than (b).
- **Progress tracking**: In one-by-one or batched-decision mode, always show a progress tracker (e.g., `[2/7]`) so the current position and total count are always visible. In clustered-decision mode, show cluster index plus the count it covers (e.g., `cluster [2/4]: 5 findings`).
- **Batched-decision mode**: use `AskUserQuestion` to present up to 4 findings per call, each as its own single-select question. The option set is determined by the finding's bucket per `Finding Categorization`. Needs sign-off findings (and Agent-resolvable findings in multi-reviewer repos, which carry test + CI + kickoff-alignment evidence in the row) use the standard `Apply / Skip / Modify` option set across every skill that surfaces them. Agent-resolvable findings in solo repos are auto-applied and do not surface as a decision; they appear only in the iteration audit log. Needs human judgment findings use **bespoke options the skill authors per finding** (the actual decision branches; generic timing options like "now / later / dismiss" are forbidden in this bucket (see `Finding Categorization` for the forcing function)). Skills that don't use the categorization (e.g., `/code-review`) define their own option set tied to the action they're taking (e.g., `/code-review`: Post inline / Post as PR-level / Defer to follow-up / Dismiss, since the workflow is drafting comments to post). The auto-added "Other" handles custom decisions. Acknowledge the decisions before moving on, then act on them per the user's broader workflow choice.
- **Clustered-decisions mode**: when many findings share a decision axis, collapse them into clusters and ask one question per cluster instead of one per finding. Strong axes: same fix template ("apply this pattern to all"), same lens (docs nits, naming nits), same scope (all in one module), same destination. One `AskUserQuestion` per cluster, single-select with cluster-wide actions matching the cluster's bucket per `Finding Categorization`: Needs sign-off clusters (and Agent-resolvable clusters in multi-reviewer repos) get `Apply all / Skip all / Pick individually`; Agent-resolvable clusters in solo repos do not surface as a decision (auto-applied, logged only); Needs human judgment clusters get cluster-wide options that reflect the shared axis (e.g., "Choose strict for all" / "Choose lenient for all" / "Pick individually". The same forbidden-timing rule applies, the cluster axis is what determines the options). Skills not using the categorization define their own cluster-wide options (e.g., `/code-review`: Post all inline / Post all as PR-level / Defer all to follow-up / Dismiss all / Pick individually). "Pick individually" drops into batched-decision mode for that cluster only. Findings that fit no cluster fall back to (b) or (c). List each cluster's members briefly before the question (file:line + one-line summary) so the user can spot mis-grouped items before answering. Best when the finding list is large and several findings share an axis; weak when every finding is bespoke (Needs human judgment findings often resist clustering).
- For each item in one-by-one mode: present it, discuss it, and wait for the user's decision before moving to the next.
- This applies to: PR review comments, code review findings, feature review feedback, and any similar review workflow.

### Validation Rigor (Issue Identification)

For any review workflow that flags issues, do at least **three independent validation passes per finding**. Each pass must use a different method or perspective, not the same approach repeated. The goal is to expose blind spots that any single approach misses. If the three passes do not converge on the same conclusion, drop or downgrade the finding.

- **Pass 1: direct reproduction.** When the claim concerns runtime behavior, reproduce it. Write a failing test, run the code, trace through with concrete inputs, or construct the exact failing scenario. Inability to reproduce is a strong signal the issue may not exist.
- **Pass 2: orthogonal angle.** Use a different lens than pass 1. Examples: callers and upstream context, related code paths and side effects, project conventions and sibling implementations, existing test coverage that may already prove the case safe.
- **Pass 3: outside-in angle.** Consult sources outside the diff. `git log` / `git blame` for the why-it-is-the-way-it-is. Repo-wide search for similar patterns. For text or research-based claims (API correctness, spec compliance, deprecated patterns, security claims, library behavior): official docs, the library's own source and tests, the deepwiki MCP for repo facts, GitHub issues, RFCs, web search. Note what was consulted in the finding.

Skills MAY scope the three-pass requirement to findings the agent will act on locally (e.g., `/polish` applies the full three-pass to Auto-applicable and Agent-resolvable candidates (since those get auto-applied in solo repos) and a soft-floor false-positive spot-check to Needs sign-off and Needs human judgment findings, since the user finishes validation when reviewing those). The scoping must be documented in the skill; the default for any skill that does not specify otherwise is the full three passes on every finding.

### Validation Rigor (Solutions)

For any fix, validate the solution with at least two independent test angles, three when relevant:

1. **Targeted test.** Write a test that fails on current code for the bug's exact reason. Confirm it fails for the right reason before applying the fix. Apply the fix. Confirm the test now passes.
2. **Wider check.** Run the full project test suite, linters, and type-checkers. Watch for regressions, including in unrelated areas the change could now affect.
3. **Edge / integration / manual.** When relevant: boundary cases (null, empty, max size, concurrency), integration or smoke tests, manual exercise of the user-facing flow.

For non-testable changes (docs, comments, formatting, pure renames, type-only adjustments): substitute review angles. Re-read the diff, read it from the perspective of each caller, and grep the repo for places the change could silently break. **For contract rewords (a doc rule expressed in several places, a behavior summary that recurs in workflow lists, a rename touching prose as well as code identifiers): grep the affected files for the surface patterns of the rule before declaring alignment, not only the lines a thread points at. Otherwise stragglers surface as new threads in the next review cycle.** Note in the reply why a test was not added.

### Discovery Rigor (Issue Identification)

Validation Rigor confirms a finding is real. Discovery Rigor makes sure the finding *list itself* is complete on the first pass. The failure mode this prevents: surfacing a few items, the user runs the skill again, and pass 2 returns valid findings that were not caused by pass 1's fixes (i.e., they could have been reported the first time but were silently pruned).

For any review workflow that generates findings (not just validates pre-existing threads), apply this on the discovery pass:

- **Lens checklist, no silent pruning.** Walk every lens below, in order, before producing the finding list. Severity-based self-pruning ("I already found a bug, the doc nit is not worth mentioning") is the exact failure mode to avoid: report findings at every severity in the same pass.

  1. Correctness, logic, edge cases (null, empty, max size, concurrency, off-by-one, error paths)
  2. Security (injection, auth, data exposure, secret handling, untrusted input)
  3. Error handling and failure modes (what happens when this fails partway)
  4. Performance (allocation, IO, complexity, hot paths)
  5. Concurrency / state (race conditions, idempotency, ordering, retries)
  6. Naming, readability, structure (only flag when this PR worsens it; see Refactor Instinct)
  7. Documentation (docstrings, READMEs, specs, ADRs, config docs, CLAUDE.md sections)
  8. Tests / verification (coverage of new behavior, missing failing-case tests, brittle assertions)
  9. Cross-file consistency (did the diff break a documented invariant or sibling pattern)

- **Lens-coverage table (canonical output).** After walking the lenses, emit this table verbatim, one row per lens, before any per-finding output. Empty lenses must show `none` with a one-line reason; this is what makes silent pruning visible.

  | Lens | Findings | Notes |
  | --- | --- | --- |
  | Correctness, logic, edge cases | `<count or "none">` | `<one-line summary or reason for none>` |
  | Security | ... | ... |
  | Error handling and failure modes | ... | ... |
  | Performance | ... | ... |
  | Concurrency / state | ... | ... |
  | Naming, readability, structure | ... | ... |
  | Documentation | ... | ... |
  | Tests / verification | ... | ... |
  | Cross-file consistency | ... | ... |

  A lens may be marked `n/a` instead of `none` when it is genuinely inapplicable to the change (e.g., concurrency lens for a doc-only diff). `n/a` requires a one-line reason in the Notes column. Skipping a row is not allowed.

- **Tool-grounded discovery.** Before relying on judgment, run what the project ships: linters, formatters, type checkers, static analyzers, complexity / duplication meters, dead-code detectors, security scanners. Discover them via `lefthook.yml`, CI workflows, `mise.toml` tasks, language-specific config files (`.rubocop.yml`, `pyproject.toml`, `tsconfig.json`, `Cargo.toml`, etc.), or the auto-detected summary the SessionStart `tool-discovery` hook injects when present. Tool output is grounded; vibes are not. Cite the rule when flagging.

- **Parallel lens fan-out (preferred for non-trivial diffs).** A single coordinator agent walking all lenses still self-prunes within its context window. For diffs beyond a few hunks, spawn parallel `Explore` sub-agents instead, one per lens, each with a narrow brief: "find issues in this diff for ONE lens only: `<lens>`; be exhaustive within your lens; severity-pruning is forbidden; if no findings, return `none` with a one-line reason." Pass the shared tooling output to every sub-agent. The coordinator merges, dedupes (a finding hitting two lenses gets one row with both lens labels), then runs the self-critique pass. Skills that perform discovery should specify when to fan out vs run inline.

- **Self-critique pass before reporting.** After the lens walk (or fan-out merge) produces a finding list, do one more pass: assume the list is incomplete, re-scan the diff specifically looking for what feels under-represented, and add what you find. This is mandatory, not optional. The cost is small; the upside is that the user does not have to re-run the skill to drain pass-2 findings.

Skills cite this section the same way they cite Validation Rigor. The canonical lens list lives here so individual skills do not drift.

### Finding Categorization

After Discovery Rigor produces findings and Validation Rigor confirms them, skills that **act on findings locally** (such as `/self-review`, `/polish`, `/peer-review`, `/panel-review`, `/panel-pairing`, `/copilot-pairing`, plus `/copilot-review`'s adjacent-findings output) categorize each finding into one of four buckets and present them as separate tables. `/polish` and `/panel-pairing` use the Auto-applicable and Agent-resolvable buckets (the latter only in solo repos with an active kickoff brief) as their loop boundary. Skills that **only draft output for elsewhere** (e.g. `/code-review`, which drafts comments for the human to submit) skip the categorization and use a presentation tailored to their workflow (typically severity-grouped). They still apply Discovery Rigor and Validation Rigor in full; the categorization just doesn't gate behavior because no fixes are auto-applied.

The bucket is determined by the **honest decision shape**: what the human actually needs to decide. If the only call is "apply or not", the LLM has the call; if real alternatives exist, the human does. The bucket the finding lands in must match the kind of question the human would otherwise have to answer.

**Auto-applicable.** LLM applies without asking. All four conditions must hold; if any is uncertain, the finding routes to Needs sign-off (or Needs human judgment, if uncertainty is about which path to take rather than whether to apply a known fix).

1. **Tool-grounded.** A specific rule was cited by a linter, formatter, type-checker, static analyzer, or dead-code detector run against the project. "I think this is a bug" does not qualify; "ruff F401: imported but unused" does. The rule citation must appear in the finding row.
2. **Mechanical fix.** The fix is a rename, reformat, drop-unused, missing-import, missing-newline, typo, inferable-type-annotation, or similar single-step transform. No design decision, no choice between alternatives.
3. **No user-observable behavior change.** Internal-only edits qualify. Anything that changes a public API, error message a caller could depend on, log output a downstream consumer might parse, or any external contract does not.
4. **Validation passes converged with high confidence.** All three Validation Rigor passes agreed on the finding and the fix. Low-confidence or split-pass items are never Auto-applicable, even if they look mechanical.

Plus the unconditional disqualifiers below. Anything disqualified routes to Needs sign-off or Needs human judgment regardless of how mechanical the fix looks; the disqualifier prevents autonomous application but does not prevent the LLM from recommending the fix.

- **Security-sensitive code** (auth, secrets, crypto, permissions, IAM, SQL/shell construction, sandbox boundaries).
- **Migration / data / destructive ops** (schema changes, backfills, deletes, drops, anything irreversible).
- **CI configuration, lockfiles, `.env`, secrets files.**

**Agent-resolvable.** LLM resolves the finding with a failing-then-passing regression test plus CI evidence, the same discipline a human engineer would apply, just automated. The decision shape is "resolve, with the test and CI as proof". All five conditions must hold; if any is uncertain, the finding routes to Needs sign-off (or Needs human judgment when the path is ambiguous).

1. **Failing regression or behavior test.** A test exists that fails on current code for the finding's exact reason. It is written and confirmed to fail *before* the fix is applied.
2. **Test passes after the fix.** The same test, unchanged, passes once the fix is in.
3. **Full project CI passes after the fix.** The project's wider test / lint / type-check suite passes. No new regressions in any other area.
4. **Aligned with the active kickoff brief.** No contract drift relative to the brief's goals, constraints, or decisions. If no kickoff brief is active for the current branch, the finding cannot be Agent-resolvable.
5. **Not in a hard-disqualifier zone.** Security primitives, migrations, public API contracts, secrets handling, and CI configuration always route to Needs sign-off (or Needs human judgment), regardless of how clean the test passes are.

**Repo-class behavior split.** Determination is per-repo via `~/.claude/scripts/pair-flow-config.sh repo-class` (writes `solo` or `multi-reviewer` to stdout on exit 0; `needs-confirmation:<inferred>` on exit 2, in which case the calling skill must surface the inferred value to the human before proceeding, per REQ-D9.1 / D-20 in the pair-flow spec).

- **Solo repos** (`repo-class: solo`): Agent-resolvable findings auto-apply without human pause. The failing-then-passing test path, before/after test output, CI output, and kickoff-alignment citation are recorded in the iteration row.
- **Multi-reviewer repos** (`repo-class: multi-reviewer`): Agent-resolvable findings surface for human review with the same evidence attached. They do not auto-apply.

**Decision shape:** in solo repos, no per-finding decision is required at finding time (the LLM applies; the row carries the evidence). In multi-reviewer repos, the option set is `Apply / Skip / Modify` (auto-added "Other"), same shape as Needs sign-off, with the test+CI+alignment evidence in the row.

**Skills that recognize this bucket:** `/polish`, `/panel-pairing`, `/peer-review`, `/copilot-pairing`. They read `repo-class` at pre-flight; if no kickoff brief is active for the current branch (derived from the spec id in pair-flow branch naming, `specs/<spec-id>/kickoff-brief.md`), the bucket is unavailable and findings route per the existing three-bucket rules.

**Needs sign-off.** LLM has a single specific recommended fix and validation converged with high confidence, but the change warrants human approval before landing. The decision the human is making is "apply this exact fix, yes or no", not "what to do" (that's Needs human judgment) and not "when" (which routes here as "yes, apply now" by default).

Route to this bucket when any of these hold:

- The fix touches a public API, error contract, log format, or any external interface.
- The fix causes a user-observable behavior change but the resolution is clearly correct.
- The change is in security-sensitive code, a migration / destructive op, CI config, a lockfile, `.env`, or a secrets file (the disqualifiers above), and the LLM has an unambiguous recommended fix.
- The fix is multi-step or non-mechanical (Auto-applicable condition 2 fails) but the path is unambiguous; the LLM has one best fix, not a choice among alternatives.

**Decision shape: `Apply / Skip / Modify`** (auto-added "Other"). The standard option set across every skill that surfaces this bucket. Default is Apply. `Skip` covers both "no, leave it" and "defer to a follow-up". The LLM does not present timing as a separate option because the question being asked is binary apply-or-not, with deferral expressed as Skip.

**Needs human judgment.** Genuinely requires human input. The decision the human is making is "which approach", not "yes or no".

Route to this bucket when any of these hold:

- Multiple valid resolutions exist and the LLM cannot pick between them from first principles.
- Missing product / UX / domain context the LLM cannot derive.
- A real tradeoff that depends on user priorities, not facts.
- Validation passes did not converge (low confidence in the finding itself).
- The fix changes a contract in a way that requires a policy call.

**Decision shape: bespoke options per finding.** The skill must enumerate concrete branches: the actual design alternatives, or a specific question with concrete answers. Examples of well-shaped options:

- "Validation could be strict (reject) or lenient (coerce). Which fits the contract?" → `Strict reject` / `Lenient coerce` / `Strict but log coerce path`
- "Retry policy on partial success is undefined. Which behavior do you want?" → `Retry full operation` / `Retry only the failed sub-step` / `Fail fast`
- "Endpoint visibility: public or internal?" → `Public` / `Internal` / `Mixed (specify in Other)`

Generic timing options (`Address now` / `Defer to follow-up` / `Dismiss` / `Discuss first`) are **forbidden** in this bucket. If the only honest decision shape is timing, the finding does not belong here; it belongs in Auto-applicable (just do it) or Needs sign-off (Apply with the LLM's recommendation as the default; Skip covers the "later / dismiss" cases).

The auto-added "Other" option exists for edge cases the LLM did not enumerate. The LLM's job is to enumerate the obvious branches; "Other" is the escape hatch, not the default.

**Forcing function.** When drafting options for a finding, if you find yourself writing "now / later / dismiss", stop. Re-route the finding. If the LLM has a single recommended fix, it belongs in Needs sign-off and the options collapse to `Apply / Skip / Modify`. If the LLM does not have a single recommended fix, the bucket-3 options must be the *actual* alternatives the human is choosing between, not timing labels. A bucket-3 finding with generic timing options is a misclassified bucket-2 finding.

**Presentation.** Skills using the categorization present these as **four tables in fixed order**: Auto-applicable, Agent-resolvable, Needs sign-off, Needs human judgment. If any bucket is empty, the table still appears with a single `none` row (anti-silent-pruning guard, same purpose as the canonical lens-coverage table). In solo repos, the Agent-resolvable table is part of the iteration audit log even though items in it are auto-applied; the row carries the evidence (test path, before/after test output, CI run + result, kickoff-alignment citation). In multi-reviewer repos, the Agent-resolvable table is surfaced for human review with the same evidence.

### Refactor Instinct

Guiding principle: **small, continuous refactors prevent large, breaking ones.** Favor composable code shaped by frequent small cleanups over big periodic rewrites. Whether to act on this depends on the mode you are in.

**Tool-grounded over vibes (both modes).** Before claiming code needs a refactor, check what the repo already runs: linters, formatters, type checkers, static analyzers, complexity / duplication meters. Same discovery channels as Discovery Rigor. If a tool flags it, the finding is grounded; cite the tool and rule. If no tool flags it but you still feel something needs refactoring, your judgment is less reliable, so be more conservative (especially in review mode). If the repo has no relevant tooling for the language or area, prefer suggesting that tooling be added over making subjective calls.

**Implementation mode (low bar, clean as you go).**

- Rename a confusing variable, extract a helper when a third caller appears, split a function that grew past one screen.
- Before adding to messy code, pause and either (a) make the small cleanup inline, or (b) surface the friction with a concrete proposal. Do not barrel through and add more mess.
- **Pre-ship self-review.** Before declaring a task done, run the project's linters, formatters, and type checkers locally. Fix what they surface in the area you touched, in the same change. Then walk the Discovery Rigor lens checklist against what you just wrote and address what you find. This shifts iteration cost from external review loops to internal ones.
- Refactor proposals during implementation should be small, scoped to the area you are touching, and easy to accept or reject.

**Review mode (high bar).**

- Only flag refactors when **this PR** materially worsens structure (new duplication introduced, nesting deepened, abstraction muddled, naming made worse). Pre-existing mess unrelated to the diff is out of scope.
- Anchor flags in tool output where possible. "X trips `<linter>` rule Y" is grounded; "this could be cleaner" is not and should be dropped.
- Prefer follow-up suggestions over blocking comments. "Consider as a follow-up" is usually the right framing.
- Do not propose alternative architectures, rewrites, or stylistic preferences unless the current shape will demonstrably cause maintenance pain.
- Do not invent abstractions for hypothetical future requirements. Three similar lines is fine; demanding a helper for them is noise.

### Review Workflows
There are seven review workflows, each with a corresponding slash command:

1. **Self-review** (`/self-review`): Comprehensive code review of the feature branch against main. Review, validate for false positives, iterate until clean, then push and create a draft PR.
2. **Polish** (`/polish`): Autonomous loop of `/self-review`'s discovery + validation, applying Auto-applicable items (tool-grounded, mechanical, no behavior change, validation passes converged) plus, in solo repos with an active kickoff brief, Agent-resolvable items (failing-then-passing regression test + CI evidence + kickoff alignment). Each iteration drains both action buckets; Needs sign-off and Needs human judgment accumulate; the loop hands off when both action buckets are empty (surfacing the remaining items in the four-table summary) or any safety condition fires. In multi-reviewer repos, Agent-resolvable items surface for human review with the evidence attached instead of auto-applying. Local-only: no push, no PR. Use as a finishing pass before `/self-review` opens the PR.
3. **Panel review** (`/panel-review`): Same shape as `/self-review` but routes Discovery Rigor and Validation Rigor through configurable external backends (OpenAI Codex CLI on work, Google Gemini CLI on personal/alt, local Ollama models like Qwen2.5-Coder and gpt-oss:20b available via opt-in) so the variance does not come exclusively from the active Claude session. Pluggable `--backends` flag with profile-aware defaults: work defaults to `codex`; personal/alt default to `gemini` (per D-6 in `specs/pair-flow/design.md`). Intended to replace `/copilot-review` for cases where GitHub Copilot quota is the bottleneck.
4. **Panel pairing** (`/panel-pairing`): Autonomous loop of `/panel-review`, same shape as `/copilot-pairing` minus all GitHub-Copilot-specific machinery (no bot detection, no GraphQL re-request, no 10-minute poll). Same profile-aware backend defaults as `/panel-review` (codex on work, gemini on personal/alt). Same bucket handling as `/polish`: applies Auto-applicable items, plus Agent-resolvable items in solo repos with an active kickoff brief; surfaces Agent-resolvable for human review in multi-reviewer repos. Iterates until convergence (two consecutive iterations with zero new valid findings) or a safety condition fires; iteration cap 15. Intended to replace `/copilot-pairing`.
5. **Peer review** (`/peer-review`): Address unresolved peer review threads on the current PR. Same validation process as `/copilot-review`, but responses must sound natural, human, and match the user's communication style.
6. **Copilot review** (`/copilot-review`): Address unresolved GitHub Copilot review threads on the current PR. Fetch threads via GraphQL, reproduce each issue when relevant, design our own fix (do not trust Copilot's recommendation), validate via the three-pass rigor, present findings as a table, then implement test-first when applicable, comment, and resolve threads via GraphQL. **Transitional**, kept active during the `/panel-*` proving period and retired in a follow-up PR.
7. **Copilot pairing** (`/copilot-pairing`): Same rigor as `/copilot-review`, but loops autonomously: address Copilot's threads, push, re-request review, wait for Copilot's response, repeat until Copilot has no new comments. Hard stop conditions (ambiguity, scope creep, test failure, security-sensitive code, loop detection, iteration cap of 10) hand control back to the human. **Transitional**, kept active during the `/panel-pairing` proving period and retired in a follow-up PR.

For reviewing **someone else's** PR (not your own), use `/code-review` instead. It checks out the PR, applies the same three-pass validation rigor, and drafts comments for the user to submit manually.

## Spec-Driven Autonomy Pipeline

The review workflows above are the convergence layer of a larger spec-driven pipeline (the "pair-flow" system; full spec at `specs/pair-flow/` in the dotfiles repo). It pairs human and agent from comprehension through execution and orchestration using Claude Code primitives only (skills, hooks, slash commands, scheduled remote agents, file-based state); no second agent framework is introduced.

**The four-file spec.** Each feature lives in `specs/<feature>/` as `requirements.md` (REQ-IDs), `design.md` (D-IDs with `Alternatives considered:` / `Chosen because:`), `tasks.md` (stable task IDs with `Done when:` / `Dependencies:` / `Citations:`), and `test-spec.md` (each REQ pinned to a verification path). `requirements.md` carries a status: `Draft` → `Active` → `Done`. `tasks.md` doubles as the canonical orchestration state record (sections: Completed, In progress, Awaiting input, Deferred, Out of scope). The validator (`~/.claude/scripts/spec-validate.sh`) enforces task structure: warnings on Draft, errors that block execution on Active.

**The skills, in pipeline order:**

1. **`/spec-draft <feature>`**: interactively elicit the four-file bundle via Socratic questioning. Writes Status: Draft. Never commits or flips to Active.
2. **`/spec-kickoff <spec-path>`**: walk the spec section by section with the human until mutually didactic understanding, producing a signed-off `kickoff-brief.md` (the durable contract every downstream skill works against). Flips Draft → Active on sign-off. Halts on genuine spec inconsistencies rather than papering over them.
3. **`/orchestrate <spec-path>`**: stateless step machine: read `tasks.md`, pick the next ready task (or bundle per the D-11 bundling rule), create or reuse a worktree, dispatch `/execute-task`, exit. One task per invocation; intra-spec parallelism comes from running it in multiple sessions. Per-spec advisory lock; never auto-merges. A `--bookkeeping` mode reconciles merged PRs back into `tasks.md` on a schedule.
4. **`/execute-task <task-ids>`**: the execution workhorse. Test-first discipline (write the failing test, confirm it fails for the right reason, implement until green), research recorded in the kickoff brief's risk register, full project CI with adaptive retry, `/polish` as the convergence step, then a draft PR referencing the brief, task IDs, REQs satisfied, and test additions.
5. **`/resume`**: read-only context loader for a fresh session in a worktree with in-flight work: kickoff brief + `tasks.md` + git log + open PR state, plus an optional handover brief at `{worktree}/.claude/handover.md`.

**Autonomy gate.** The four-bucket `Finding Categorization` above is how the pipeline decides what to apply autonomously vs. surface to the human. `repo-class` (solo vs multi-reviewer, via `~/.claude/scripts/pair-flow-config.sh repo-class`) determines whether Agent-resolvable findings auto-apply (solo) or surface with test + CI + kickoff-alignment evidence for review (multi-reviewer).

**Cross-session awareness.** Active sessions write heartbeat state to `~/.claude/inbox/`; a tmux popup (`prefix + i`) and a status-bar segment surface which sessions need attention, and macOS notifications fire on transitions into `awaiting-input` / `draft-pr-ready`.

**Hard invariants.** Never auto-merge (merge is a reserved human action, permanent, not deferred). Never act on a non-Active spec (no bypass flag). Never auto-chain `/orchestrate` into `/spec-kickoff`. Never force-push, amend, squash, or rebase; create new commits only.

## Writing Style
- Avoid em-dashes in prose unless strictly necessary. Use commas, parentheses, colons, or separate sentences instead.

## Non-obvious Tools

- **`fish`**: Default shell. Use Fish syntax, not bash/zsh (e.g., `set` not `export`).
- **`mise`**: Runtime version manager for all languages (replaces nvm, rbenv, pyenv).
- **`age`**: File encryption tool for metrics snapshots under `specs/metrics-baseline/`.
- **`lefthook`**: Git hooks manager. Pre-commit hooks are defined in `lefthook.yml`.
- **`jq`**: JSON processor. Used by Ansible to merge `settings.json` into `~/.claude/`.
