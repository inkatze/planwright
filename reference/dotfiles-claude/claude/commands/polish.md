Iterate `/self-review` autonomously, applying only Auto-applicable items, until none remain. Hand control back when no Auto-applicable items are left to drain (surfacing any Needs sign-off or Needs human judgment items in the final tables) or any safety condition fires.

Same Discovery + Validation rigor as `/self-review`, executed on autopilot, with hard stop conditions baked in for safety.

## When to use

You are nearly done with a branch and want to drain the trivial, tool-grounded fixes (linter rule violations, formatter output, type-checker errors, missing imports, unused variables, typos in comments, inferable type annotations) before opening a PR. Polish auto-applies items that meet the strict Auto-applicable definition in CLAUDE.md `Finding Categorization`, plus, in solo repos with an active kickoff brief, items that meet the Agent-resolvable predicate (failing-then-passing regression test + full project CI green + kickoff alignment + no hard disqualifier). Once both action buckets are empty (or any safety condition fires), it surfaces any Needs sign-off or Needs human judgment items in the final iteration tables and hands off.

When the toolchain is clean and the diff is uniformly inside a categorization disqualifier (e.g., entirely security-sensitive auth code), Polish will hand off on the first iteration with all findings in Needs sign-off or Needs human judgment. The same first-iteration handoff happens when the project ships no tool that can ground a finding for the changed file types (e.g., a markdown-only diff in a project without a markdown linter) and no Agent-resolvable finding meets condition (a) (a failing regression test must exist for the finding's exact reason). Both are the expected outcome, not a failure.

In **standalone mode** (default), Polish pushes the branch and opens (or updates) a draft PR after the loop exits via success or human-attention-required handoff. In **nested mode** (Polish invoked from another skill that owns PR creation, e.g., `/execute-task` per the pair-flow design), Polish remains local-only and the parent skill handles PR creation. The two modes are detected at pre-flight per the rules below.

## Invocation mode

Read the literal flag `--nested` from `$ARGUMENTS` at the very start of the run:

- `$ARGUMENTS` contains `--nested`: Polish is nested inside another skill (typically `/execute-task`). Suppress the "Standalone-mode PR creation" step after the loop. Auto-execution invariants below treat push and PR creation as forbidden in this mode.
- `$ARGUMENTS` does not contain `--nested`: Polish is standalone. The "Standalone-mode PR creation" step runs after a normal exit (success or human-attention-required). Safety stops still suppress it because the branch is in a known-broken state.

Record the resolved mode in iteration summaries so the user can see it.

## Pre-flight (once per run)

1. **Identify the base branch and capture diff baseline** (same as `/self-review` step 1).
2. **(Optional) Fetch Jira ticket for context** (same as `/self-review` step 2). Used only as an extra lens during Discovery Rigor, not as a fix authority. Failing to satisfy an acceptance criterion is always Needs sign-off or Needs human judgment.
3. **Initialize iteration counter** = 0.
4. **Confirm the working tree is clean.** Polish requires `git status --porcelain` to be empty before it starts. Uncommitted changes interfere with the per-iteration commit boundary and make rollback ambiguous. If the tree is dirty, stop and ask the user to commit or stash first.
5. **Resolve `repo-class` and detect the active kickoff brief.** Run `~/.claude/scripts/pair-flow-config.sh repo-class`:
   - Exit 0 with `solo`: enable the Agent-resolvable bucket; items in it auto-apply.
   - Exit 0 with `multi-reviewer`: enable the Agent-resolvable bucket; items in it surface for human review with evidence (treated as Needs sign-off for loop-fate purposes), they do not auto-apply.
   - Exit 2 with `needs-confirmation:<inferred>`: surface the inferred value and the helper's reasoning to the human and wait for confirmation. **Never** call `confirm-repo-class` without explicit human input (REQ-D9.1, D-20 in the pair-flow spec). On confirmation, run `~/.claude/scripts/pair-flow-config.sh confirm-repo-class <value>` and proceed.
   - Non-zero with any other status: log it, disable the Agent-resolvable bucket for this run, and proceed with the three-bucket flow.

   Then derive the active kickoff brief by walking the heuristics in order, stopping at the first unambiguous match:

   1. **D-32 branch pattern.** If the branch matches `pair-flow/<spec>/task-...`, the brief is `specs/<spec>/kickoff-brief.md`.
   2. **Single Active spec.** If exactly one `specs/*/requirements.md` is `Status: Active` and a sibling `kickoff-brief.md` exists, use it.
   3. **Branch-name match.** If multiple specs are Active, look for one whose directory name appears in the current branch name as a token (e.g., `worktree-settings` → `specs/settings/`). Unambiguous match wins.
   4. **Diff-scope match.** If still ambiguous, compute the diff against the base (`origin/main` per step 1) and check whether ≥80% of changed lines live under a single `specs/<spec>/` or the application code that spec governs (use the spec's `Citations:` files when present). Unambiguous match wins.
   5. **Ask.** If 2-4 are all ambiguous and multiple specs remain candidates, prompt the user via `AskUserQuestion` to pick the active brief from the candidate set. Do not guess. Do not silently disable the Agent-resolvable bucket when human input could resolve it.

   If no Active spec exists at all (none of the heuristics produce a candidate), disable the Agent-resolvable bucket for this run and proceed with the three-bucket flow; log this as informational, not a stop condition. Record the resolved `repo-class` and the brief path (or "no active brief") in iteration summaries.

## Iteration loop

For each iteration (cap = **10**):

**Cap check (run at the start of every iteration, before step (a)).** Read the iteration counter (initialized to 0 in pre-flight step 3; incremented in step (f)). If the counter has reached **10**, do not enter step (a). Trigger the **Iteration cap** stop condition and hand control back.

### a. Generate findings

Apply `/self-review` step 3 (lens walk + tooling sweep + self-critique), then validate findings per `/self-review` step 4 (Validation Rigor). Full three-pass rigor is a **hard gate** for findings that could be routed to Auto-applicable or (in solo repos with an active kickoff brief) to Agent-resolvable, since Polish will silently apply those: condition 4 of `Finding Categorization` requires converged validation for Auto-applicable, and the test-driven shape of Agent-resolvable in step (d-AR) below is itself the converged-validation evidence. For findings that already fail one of the Auto-applicable conditions 1–3 (not tool-grounded, not mechanical, or user-observable change) AND fail one of the Agent-resolvable conditions a–e (no failing test exists, fix breaks CI, no kickoff alignment, or hard-disqualifier zone), and can therefore only land in Needs sign-off or Needs human judgment, a **soft-floor pass** is enough: spot-check to drop clear false positives, then route. The user finishes validation during their own review of those items.

**Fan-out vs inline.** `/self-review` step 3 defaults to spawning one `Explore` sub-agent per canonical lens, and that default holds for any non-trivial diff. You may walk lenses inline only when **all three** of these hold; otherwise fan out:

- **Doc/config dominant.** More than 80% of changed lines are in markdown, YAML, JSON, TOML, or HCL (`.tf`, `.tfvars`). HCL counts as config only when the repo ships no terraform-specific linter (tflint, tfsec, checkov, OPA); if any of those exist, `.tf` counts as executable code and forces fan-out so the lens-coverage table reflects each tool's signal.
- **Narrow code surface.** At most 2 files contain executable code (shell, Ruby, Python, Go, etc.).
- **Modest total size.** Fewer than ~300 changed lines.

Inline walking does not waive any other invariant: the lens-coverage table, the no-silent-pruning rule, and the mandatory self-critique pass all still apply. CLAUDE.md `Discovery Rigor` prefers fan-out for non-trivial diffs and explicitly grants skills the authority to specify when to walk inline; this section exercises that authority. The bar is intentionally low because a single coordinator agent self-prunes once a diff is even mid-size, and fan-out is cheap insurance.

**Known false-positive patterns.** Some tool outputs look like cleanup candidates but are intentional. Drop these at discovery rather than routing them anywhere:

- **Dialyzer `:unnecessary_skip` against paths outside the current env's `elixirc_paths`** (commonly `test/support/*` files surfaced when running `mix dialyzer` directly instead of `mix ci`). The skip filter is intentional CI-side coverage for code Dialyzer cannot see from the dev compile path; removing it would silently lose CI coverage. If you cannot determine whether the skip target is reachable from the current env's compile path, route to Needs sign-off or Needs human judgment rather than Auto-applicable.

### b. Categorize per CLAUDE.md `Finding Categorization`

Each finding lands in exactly one bucket out of four: **Auto-applicable** (all four bright-line conditions met, no disqualifiers), **Agent-resolvable** (all five test+CI+kickoff conditions met, no hard disqualifier; bucket is enabled in pre-flight step 5 only when `repo-class` resolved and an active kickoff brief exists), **Needs sign-off** (LLM has a single recommended fix but the change warrants human approval before landing), or **Needs human judgment** (multiple valid resolutions, missing context, or low confidence). The four Auto-applicable conditions:

1. Tool-grounded (a specific linter / type-checker / formatter / static-analyzer rule was cited).
2. Mechanical fix (rename, reformat, drop-unused, missing-import, missing-newline, typo, inferable-type-annotation; no design decision).
3. No user-observable behavior change.
4. All three Validation Rigor passes converged with high confidence.

The five Agent-resolvable conditions (all must hold; see CLAUDE.md `Finding Categorization` for the full definition):

a. A failing regression or behavior test exists that fails on current code for the finding's exact reason (and you can write it before step (d-AR) applies the fix).
b. The test passes after the proposed fix.
c. Full project CI (the wider test / lint / type-check suite run in step (d.4)) passes after the fix.
d. The fix is aligned with the active kickoff brief (no contract drift relative to the brief's goals, constraints, or decisions). If no brief is active, the bucket is unavailable for this run (pre-flight step 5).
e. The fix is not in a hard-disqualifier zone (security primitives, migrations, public API contracts, secrets handling, CI configuration).

Plus the unconditional disqualifiers for both action buckets (security-sensitive code, migrations, destructive ops, CI config, lockfiles, secrets files, `.env`). Anything disqualified routes to Needs sign-off (when the LLM has a clear fix) or Needs human judgment (when the path is genuinely ambiguous); the disqualifier prevents autonomous application but does not prevent the LLM from recommending the fix. See `Finding Categorization` for full bucket definitions.

Be more conservative than `/self-review` because nobody is checking the categorization in real time. **When in doubt, route to Needs sign-off (if you have a recommended fix) or Needs human judgment (if you do not).** False negatives (a real Auto-applicable or Agent-resolvable item routed to human) are cheap, costing one extra iteration. False positives (a judgment item auto-applied) silently corrupt the branch.

### c. Decide loop fate

Branch on the bucket counts. The Agent-resolvable bucket is treated as an "action" bucket only when pre-flight step 5 resolved `repo-class: solo` AND an active kickoff brief was found; otherwise it routes to Needs sign-off for the human review path (multi-reviewer repos) or is unavailable entirely (no brief).

- **All four buckets empty.** Success. Exit the loop. Print the final summary noting "no findings remain". Do not commit.
- **Auto-applicable AND Agent-resolvable (when an action bucket) both empty, Needs sign-off or Needs human judgment non-empty.** Stop. Trigger **Human attention required** stop condition. Print the latest tables and hand control back. Do not push, do not commit, do not auto-apply anything from the populated buckets.
- **Auto-applicable OR Agent-resolvable (when an action bucket) non-empty, regardless of the other buckets.** Proceed to step (d). Items in Needs sign-off and Needs human judgment will be re-evaluated next iteration; the user addresses them after Polish hands off.

When `repo-class: multi-reviewer` is in effect, Agent-resolvable findings already routed to the surface-with-evidence path are counted toward Needs sign-off for loop-fate purposes (they require human review before landing; the bucket presentation keeps them separate for audit clarity).

### d. Apply Auto-applicable items (solution validation rigor)

For each Auto-applicable item, apply CLAUDE.md `Validation Rigor (Solutions)` even though the fix is mechanical. The reason: a "simple" fix can still break tests if the rule citation was wrong about scope or the fix has subtle implications.

1. **Pre-fix tool run.** Run the cited tool against the file(s) and confirm the rule actually fires on the current code. If it does not (e.g., the rule was already silenced, the file changed since discovery), drop the item and continue. Do not apply a fix for a rule that does not currently fire.
2. **Apply the fix.**
3. **Post-fix tool run.** Run the cited tool again against the same file(s) and confirm the rule no longer fires.
4. **Wider check.** Run the broader project test suite, linters, and type-checkers. Any failure (even a pre-existing one we surface for the first time) triggers the **Test failure** stop condition.

For non-testable fixes (formatting, typos in comments, doc adjustments), substitute review angles per the canonical doctrine in CLAUDE.md.

### d-AR. Apply Agent-resolvable items (solo repos only)

Only runs in solo repos with an active kickoff brief; in multi-reviewer repos these items already routed to surface-with-evidence in step (b) and are not applied here. For each Agent-resolvable item:

1. **Write the failing regression test first.** Author a test that fails on current code for the finding's exact reason. Place it in the project's existing test layout (e.g., `test/`, `spec/`, `__tests__/`). The test must target the specific behavior described in the finding, not a tangentially related one.
2. **Confirm the test fails for the right reason.** Run the targeted test. The failure mode must match the finding (assertion failure on the specific value, expected exception path, etc.), not a setup error or import failure. If the failure does not match, drop the item and route it to Needs sign-off; do not proceed.
3. **Apply the fix.**
4. **Confirm the test now passes.** Re-run the targeted test. Pass is required; if still failing, the fix is wrong and the item routes to Needs sign-off (do not retry-loop).
5. **Wider check (full project CI equivalent).** Run the broader project test suite, linters, and type-checkers, same as step (d.4) for Auto-applicable. Any failure (even a pre-existing one surfaced for the first time) triggers the **Test failure** stop condition.
6. **Verify kickoff alignment.** Re-read the relevant kickoff brief section(s) and confirm the fix does not introduce contract drift (new behavior the brief did not anticipate, error contract changes the brief did not approve, scope creep beyond the brief's goals). If the fix drifts, drop the item and route it to Needs sign-off; do not proceed.
7. **Record evidence in the iteration row.** Capture: test file path + test name, condensed before/after test output (one line each), wider-check command + result, and a one-line citation of the kickoff brief section the fix aligns with. This is the audit trail for the auto-apply.

The hard-disqualifier zones (security primitives, migrations, public API contracts, secrets handling, CI configuration) MUST already have rerouted this item to Needs sign-off at step (b). If you reach this step and discover the item touches one of those zones, stop, route to Needs sign-off, and trigger **Security-sensitive** or **Migrations / data / destructive ops** as applicable.

### e. Commit

Commit the changes from this iteration:

- `git add` only the files actually changed (never `git add -A`). Include the new regression test file(s) when step (d-AR) ran.
- Commit with a message of the form `chore(polish): iter N, <short summary>` (e.g., `chore(polish): iter 1, drop unused imports and fix typos`). When the iteration applied Agent-resolvable items, the summary should note the behavior fixed (e.g., `chore(polish): iter 2, fix off-by-one in retry-count; regression test added`).
- Do **not** push. Polish does not interact with remotes; pushing is `/self-review`'s job.
- Do **not** amend, squash, or rebase. Each iteration is its own commit so the user can inspect and revert per-iteration if needed.

### f. Iteration summary

Print a short summary:

- Iteration N / cap
- Invocation mode (standalone or nested per "Invocation mode" section)
- `repo-class` in effect and active kickoff brief path (or "no active brief; Agent-resolvable bucket unavailable")
- Counts: Auto-applicable applied, Agent-resolvable applied (solo only; in multi-reviewer this is always 0 since they surface for human review), Needs sign-off surfaced, Needs human judgment surfaced, dropped at step (d.1) (Auto-applicable rule no longer fires), dropped at step (d-AR.2 or d-AR.4) (Agent-resolvable test did not fail or pass as required)
- For each Agent-resolvable applied: test file + test name, wider-check command + result, kickoff-brief section cited
- Files touched
- Commit SHA
- Test command run + result

This is what the user scrolls back through to audit the run. Then increment iteration counter and loop to (a).

## Stop conditions (mandatory human handoff)

If any condition fires, **stop**. Print the latest tables, name the condition, and wait for the user. Do not commit further, do not modify anything else.

| Condition | Trigger |
|---|---|
| **Human attention required** | Step (c) found Needs sign-off or Needs human judgment items and Auto-applicable is empty. The normal path to handoff. |
| **Test failure** | Any test, linter, type-check, or formatter failed at step (d.4), including pre-existing failures surfaced for the first time. |
| **Loop detection** | The same Auto-applicable item has been "fixed" in two consecutive iterations (rule fires before the fix in iteration N, fires again before the fix in iteration N+1). Indicates the fix is not actually addressing the rule. |
| **Iteration cap** | 10 iterations completed without convergence. |
| **Ambiguity** | A finding is borderline between buckets and the bright-line conditions cannot be confidently asserted. Route to Needs sign-off when there is a clear recommended fix, otherwise to Needs human judgment; the bucket re-evaluation in the next iteration is the safety net, but if the ambiguity persists across iterations, stop. |
| **Security-sensitive** | Any Auto-applicable candidate touches auth, secrets, crypto, permissions, IAM, SQL/shell construction, or sandbox boundaries. Per the categorization disqualifiers, the item should already be Needs sign-off (or Needs human judgment if the resolution is ambiguous); if for any reason it landed in Auto-applicable, stop. |
| **Migrations / data / destructive ops** | Same as above for schema migrations, backfills, deletes, drops, anything irreversible. |
| **Dirty working tree** | Pre-flight step 4 found uncommitted changes. Stop before iteration starts. |
| **High false-positive ratio** | At least 3 items in the iteration AND more than half were dropped at step (d.1) (rule no longer fires). The model may be misreading the diff or hallucinating tool output. Pause for re-alignment rather than spamming useless commits. |

## Auto-execution invariants

These hold at every step:

- **Never** address a Needs sign-off or Needs human judgment item, even if it looks easy.
- **Never** route a finding to Auto-applicable without a specific rule citation. "I am sure this is a typo" does not qualify; "rubocop Style/UnlessElse" does.
- **Never** route a finding to Agent-resolvable without all five conditions (failing test exists and was confirmed to fail before the fix, test passes after, wider CI passes, kickoff alignment cited, not in a hard-disqualifier zone). "The fix is obvious and I am sure CI will pass" does not qualify; the actual test + CI evidence does.
- **Never** route a finding to Agent-resolvable when pre-flight step 5 disabled the bucket (no `repo-class` resolved, no active kickoff brief, or `repo-class: multi-reviewer` keeps it on the surface-with-evidence path).
- **Never** modify CI configuration, `.env`, secrets, or lockfiles, even on a tool's recommendation.
- **Never** push, force-push, amend, squash, or rebase **inside the iteration loop** (steps (a) through (f)). In standalone mode, push happens only in the post-loop "Standalone-mode PR creation" step. In nested mode, push never happens; the parent skill owns remote interaction.
- **Never** force-push, amend, squash, or rebase **at any time**, including the post-loop PR-creation step. The push there is a plain `git push origin <branch>` (with `-u` on first push); rewriting history is out of scope for Polish.
- **Never** create a PR in **nested mode**. The parent skill (e.g., `/execute-task`) owns PR creation. In standalone mode, the post-loop step creates (or updates) a draft PR per the rules in that section.
- **Never** post anything to chat platforms, tickets, or any remote system other than the GitHub PR draft body the post-loop step writes.
- **Never** skip step (d.4) or step (d-AR.5). A "simple" fix that breaks an unrelated test is the failure mode these guard against.
- **Never** skip step (d-AR.6) (kickoff alignment check). The whole point of the bucket is that downstream skills can trust the fix did not drift from the brief.
- **Never** trust the iteration counter alone for cap enforcement; verify at the top of the iteration via the explicit cap check. Confirmation bias from a long successful run is the failure mode this catches.
- **Never** call any of the other review skills (`/copilot-review`, `/copilot-pairing`, `/peer-review`, `/code-review`, `/self-review`) from inside the loop. Polish runs `/self-review`'s discovery and validation steps directly; it does not invoke the skill, which would re-trigger pre-flight, prompt the user for workflow choice, or attempt PR creation.

## After the loop

When the loop exits, branch on the exit reason and the invocation mode (set in the "Invocation mode" section above):

- **Normal exit (success or Human attention required) in standalone mode.** Present any remaining Needs sign-off / Needs human judgment items per the "Handoff presentation" rules below. Then run the "Standalone-mode PR creation" step. After it lands a draft PR (or updates an existing one), summarize: exit reason, PR URL + state, and any items still unresolved.
- **Normal exit in nested mode.** Present remaining items per "Handoff presentation", then hand control back to the parent skill with the final tables. The parent owns push and PR creation.
- **Safety stop (Test failure, Loop detection, Iteration cap, Ambiguity, Security-sensitive, Migrations / data / destructive ops, Dirty working tree, High false-positive ratio).** Regardless of mode: print the latest tables, name the condition, and hand off. Do not push, do not create a PR; the branch is in a known-broken state. Still apply "Handoff presentation" for any accumulated items.

### Handoff presentation

When handing off Needs sign-off and/or Needs human judgment items, follow the CLAUDE.md `Code & PR Reviews` workflow rules. Do not default to one-by-one; choose the mode that minimizes human effort:

**Clustered decisions first.** Look for items that share a decision axis: same fix template (e.g., "add missing test coverage"), same lens (all doc nits, all naming nits), same scope (all in one module). When a cluster of 3+ items exists, use clustered-decision mode per CLAUDE.md: one `AskUserQuestion` per cluster with cluster-wide actions. For Needs sign-off clusters: `Apply all / Skip all / Pick individually`. For Needs human judgment clusters: bespoke options reflecting the shared axis. List each cluster's members before the question so the user can spot mis-grouped items.

**Batched decisions for the rest.** Items that don't fit a cluster use batched-decision mode: up to 4 findings per `AskUserQuestion` call, each as its own single-select question. Needs sign-off items get `Apply / Skip / Modify`. Needs human judgment items get bespoke options per finding.

**Progress tracking.** Always show a progress indicator (e.g., `[2/5]` or `cluster [1/2]: 4 findings`) so the user knows their position and what's left.

**Skip the workflow choice prompt.** Unlike `/self-review` and `/code-review`, Polish has already done the autonomous work and is handing off a small residual set. Don't ask "how do you want to review these?" when the answer is obvious from the item count and clustering shape. Just present them in the best mode.

The user's next move depends on the exit reason:

- On success in standalone mode: the draft PR is open; consider running `/self-review` to make a final pass and mark the PR ready for review.
- On Human attention required in standalone mode: address the surfaced Needs sign-off / Needs human judgment items (on the branch, which now matches the open draft PR), then re-run `/polish` to drain anything new, then `/self-review` to wrap up.
- On safety stops: investigate the named condition. Polish does not auto-resume; the user explicitly re-invokes after the underlying issue is understood.

## Standalone-mode PR creation

Runs only on normal exit in standalone mode. Skipped entirely in nested mode and on safety stops.

1. **Push the branch.** `git push origin <branch>` (or `git push -u origin <branch>` if the branch has no upstream yet). If the push fails on a hook (pre-push test, security check, lefthook stage, etc.), diagnose whether the failure traces to this branch's diff or to pre-existing / unrelated state, surface the diagnosis, and hand off. Do not silently retry, **never** bypass with `--no-verify`, and do not "fix" unrelated test flakes inside this branch.
2. **Check if a PR already exists for this branch.**
   ```
   gh pr view --json number,url,state,isDraft,title 2>/dev/null
   ```
   - If a PR exists: do not create a new one. Report the existing PR's URL and state (draft/ready, open/merged). If the existing PR is merged or closed, hand back to the user; do not assume reopening or creating fresh.
   - If no PR exists: proceed to step 3.
3. **Check for templates (only when creating a new PR).** Look for `.github/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE.md`, or templates in `.github/PULL_REQUEST_TEMPLATE/`. If a template exists, use it as the structure for the PR body, filling in sections based on the branch changes.
4. **Check for conventions (only when creating a new PR).** If no template exists, look at recent merged PRs for patterns (`gh pr list --state merged --limit 5 --json title,body`). Follow a clear pattern if one emerges.
5. **Create the draft PR.** `gh pr create --draft` with a `--title` (under 70 characters) and a `--body` written via heredoc. The body shall include: a one-paragraph summary of what the branch does, a short "Polish notes" section listing Auto-applicable and Agent-resolvable items applied across iterations (test paths and kickoff-brief citations for the Agent-resolvable rows), and any unresolved Needs sign-off / Needs human judgment items the human needs to address before marking the PR ready for review. If no template or convention was found, fall back to `gh pr create --draft --fill` and then `gh pr edit --body` to append the Polish notes.

## Observations

This step applies **only when the repo has adopted pair-flow**, evidenced by an existing `specs/` directory containing at least one spec bundle (a `specs/<feature>/requirements.md`). If the repo has not adopted pair-flow, skip this step entirely: do **not** create `specs/_observations/` or any file under it (observations are seed material for `/spec-draft`, which is meaningless in a repo that does not use the spec pipeline).

When pair-flow is in use and, during iteration, you notice complexity growth, outdated patterns, newly available dependency features, or opportunities for improvement that are outside the current branch's scope, append a one-liner to `specs/_observations/opportunities.md` (create the file if it does not exist). Format: `- <YYYY-MM-DD> [<repo>] <observation>`. These accumulate as seed material for future `/spec-draft` invocations. Do not act on observations during this run; they are a passive record.

## Maintenance

After completing the workflow (or stopping), check if any part of these instructions seems outdated, incorrect, or misaligned with current tooling: changes to the canonical lens list, changes to `Finding Categorization` thresholds, new auto-fix tools that should be tool-grounded by default, or drift from `/self-review`'s discovery shape (which Polish follows). If something looks off, flag it and offer a ready-to-use prompt I can paste into a new dotfiles session to update this command.

$ARGUMENTS
