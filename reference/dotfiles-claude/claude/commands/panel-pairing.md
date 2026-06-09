Iterate `/panel-review` autonomously, applying only Auto-applicable items, until none remain. Hand control back when no Auto-applicable items are left to drain (surfacing any Needs sign-off and Needs human judgment items in the final tables) or any safety condition fires.

Same Discovery + Validation rigor as `/panel-review`, executed on autopilot, with hard stop conditions baked in for safety.

## When to use

You want the `/copilot-pairing` shape (review, address, push, re-review, repeat) but with non-Anthropic model backends doing the discovery instead of GitHub Copilot. Common cases:

- Copilot quota is exhausted for the month and you still want pairing-style autonomous draining.
- You want backend variance (different training distributions) without GitHub's per-request billing model.
- You are starting from a branch with no PR yet and want pairing-style cleanup before opening one.

`/panel-pairing` is the autonomous counterpart to `/panel-review`. It auto-applies items in the Auto-applicable bucket (CLAUDE.md `Finding Categorization`) plus, in solo repos with an active kickoff brief, items in the Agent-resolvable bucket (failing-then-passing regression test + full project CI green + kickoff alignment + no hard disqualifier). In multi-reviewer repos, Agent-resolvable items surface for human review with evidence attached instead of auto-applying. Needs sign-off and Needs human judgment items are surfaced for human review when the loop exits, same boundary `/polish` uses for self-review. For interactive review of all buckets, use `/panel-review` directly.

## Pre-flight (once per run)

1. **Identify base branch and capture the diff** (same as `/panel-review` pre-flight 1).
2. **(Optional) Jira ticket** (same as `/panel-review` pre-flight 2).
3. **Detect repo profile** (same as `/panel-review` pre-flight 3).
4. **Resolve the backend set.** Same logic as `/panel-review` pre-flight 4 (run `~/.claude/scripts/pair-flow-config.sh show`, the canonical merger of `~/.claude/pair-flow.yml` and `pair-flow.local.yml`, and read its `panel-backends` key first, then fall back to the profile table):

   | Profile | Default backends |
   |---|---|
   | work | `codex` |
   | personal / alt | `gemini` |

   `--backends` overrides. `copilot` is opt-in only. The Ollama models (`qwen-coder`, `gpt-oss`) remain available via `--backends` for variance panels on big-stakes diffs.

5. **Verify each backend** (same as `/panel-review` pre-flight 5; stop with the same install / auth messages on any failure).
6. **Initialize iteration counter** = 0.
7. **Confirm the working tree is clean.** `git status --porcelain` must be empty before the loop starts. Uncommitted changes interfere with per-iteration commit boundaries and make rollback ambiguous. If the tree is dirty, stop and ask the user to commit or stash first.
8. **Confirm the branch has an upstream**, or that the first push will create one. `git rev-parse --abbrev-ref --symbolic-full-name @{u}` succeeds when an upstream exists; if it fails, the first push in step (e) uses `git push -u origin <branch>` instead of `git push origin <branch>`. Do not pre-push at pre-flight; the first iteration's push handles it.
9. **Resolve `repo-class` and detect the active kickoff brief.** Run `~/.claude/scripts/pair-flow-config.sh repo-class`:
   - Exit 0 with `solo`: enable the Agent-resolvable bucket; items in it auto-apply.
   - Exit 0 with `multi-reviewer`: enable the Agent-resolvable bucket; items in it surface for human review with evidence (treated as Needs sign-off for loop-fate purposes), they do not auto-apply.
   - Exit 2 with `needs-confirmation:<inferred>`: surface the inferred value and the helper's reasoning to the human and wait for confirmation. **Never** call `confirm-repo-class` without explicit human input (REQ-D9.1, D-20 in the pair-flow spec). On confirmation, run `~/.claude/scripts/pair-flow-config.sh confirm-repo-class <value>` and proceed.
   - Non-zero with any other status: log it, disable the Agent-resolvable bucket for this run, and proceed with the three-bucket flow.

   Then derive the active kickoff brief by walking the heuristics in order, stopping at the first unambiguous match:

   1. **D-32 branch pattern.** If the branch matches `pair-flow/<spec>/task-...`, the brief is `specs/<spec>/kickoff-brief.md`.
   2. **Single Active spec.** If exactly one `specs/*/requirements.md` is `Status: Active` and a sibling `kickoff-brief.md` exists, use it.
   3. **Branch-name match.** If multiple specs are Active, look for one whose directory name appears in the current branch name as a token (e.g., `worktree-settings` → `specs/settings/`). Unambiguous match wins.
   4. **Diff-scope match.** If still ambiguous, compute the diff against the base and check whether ≥80% of changed lines live under a single `specs/<spec>/` or the application code that spec governs (use the spec's `Citations:` files when present). Unambiguous match wins.
   5. **Ask.** If 2-4 are all ambiguous and multiple specs remain candidates, prompt the user via `AskUserQuestion` to pick the active brief from the candidate set. Do not guess. Do not silently disable the Agent-resolvable bucket when human input could resolve it.

   If no Active spec exists at all (none of the heuristics produce a candidate), disable the Agent-resolvable bucket for this run and proceed with the three-bucket flow; log this as informational, not a stop condition. Record the resolved `repo-class` and the brief path (or "no active brief") in iteration summaries.

## Iteration loop

For each iteration (cap = **15**):

**Cap check (run at the start of every iteration, before step (a)).** Read the iteration counter (initialized to 0 in pre-flight step 6; incremented in step (f)). If the counter has reached **15**, do not enter step (a). Trigger the **Iteration cap** stop condition and hand control back. This is the only place the cap is enforced; the increment in (f) does not enforce it itself.

### a. Generate + validate findings

Run `/panel-review` steps 1-5 in full: project tooling sweep, parallel backend discovery pass, merge + dedupe, self-critique pass, three-pass Validation Rigor on every finding. Validation Rigor is a hard gate for findings that could be routed to Auto-applicable or (in solo repos with an active kickoff brief) Agent-resolvable, since the loop applies those silently; the test-driven shape of Agent-resolvable in step (d-AR) below is itself the converged-validation evidence.

Be more conservative than in `/panel-review` because nobody is checking the categorization in real time. **When in doubt, route to Needs sign-off or Needs human judgment, never Auto-applicable or Agent-resolvable.** False negatives (a real action-bucket item routed to human) are cheap, costing one extra iteration. False positives (a judgment item auto-applied) silently corrupt the branch.

### b. Categorize per `Finding Categorization`

Each finding lands in exactly one bucket out of four: Auto-applicable, Agent-resolvable (only enabled when pre-flight step 9 resolved `repo-class` and found an active kickoff brief; otherwise the bucket is unavailable and findings route to Needs sign-off or Needs human judgment instead), Needs sign-off, or Needs human judgment. The four Auto-applicable conditions, the five Agent-resolvable conditions, and the disqualifiers are in CLAUDE.md `Finding Categorization`.

### c. Decide loop fate

Branch on the bucket counts. The Agent-resolvable bucket is treated as an "action" bucket only when pre-flight step 9 resolved `repo-class: solo` AND an active kickoff brief was found; in multi-reviewer repos Agent-resolvable items are counted toward Needs sign-off for loop-fate purposes (they require human review with evidence before landing; the bucket presentation keeps them separate for audit clarity).

- **All four buckets empty.** Success. Exit the loop. Print the final summary noting "panel converged, no findings remain". Do not commit (nothing changed this iteration).
- **Auto-applicable AND Agent-resolvable (when an action bucket) both empty, Needs sign-off or Needs human judgment non-empty.** Stop. Trigger **Human attention required** stop condition. Print the latest tables and hand control back. Do not push, do not commit, do not auto-apply anything from the populated buckets.
- **Auto-applicable OR Agent-resolvable (when an action bucket) non-empty, regardless of the other buckets.** Proceed to step (d). Items in the other buckets are re-evaluated next iteration; the user addresses them after `/panel-pairing` hands off.

### d. Apply Auto-applicable items (solution validation rigor)

For each Auto-applicable item, apply CLAUDE.md `Validation Rigor (Solutions)` even though the fix is mechanical:

1. **Pre-fix tool run.** Run the cited tool against the file(s) and confirm the rule actually fires on the current code. If it does not (e.g., the rule was already silenced, the file changed since discovery), drop the item and continue. Do not apply a fix for a rule that does not currently fire.
2. **Apply the fix.**
3. **Post-fix tool run.** Run the cited tool again against the same file(s) and confirm the rule no longer fires.
4. **Wider check.** Run the broader project test suite, linters, and type-checkers. Any failure (even a pre-existing one we surface for the first time) triggers the **Test failure** stop condition.

For non-testable fixes (formatting, typos in comments, doc adjustments), substitute review angles per the canonical doctrine in CLAUDE.md.

### d-AR. Apply Agent-resolvable items (solo repos only)

Only runs in solo repos with an active kickoff brief; in multi-reviewer repos these items already routed to surface-with-evidence in step (b) and are not applied here. For each Agent-resolvable item:

1. **Write the failing regression test first.** Author a test that fails on current code for the finding's exact reason. Place it in the project's existing test layout. The test must target the specific behavior described in the finding, not a tangentially related one.
2. **Confirm the test fails for the right reason.** Run the targeted test. The failure mode must match the finding (assertion failure on the specific value, expected exception path, etc.), not a setup error or import failure. If the failure does not match, drop the item and route it to Needs sign-off; do not proceed.
3. **Apply the fix.**
4. **Confirm the test now passes.** Re-run the targeted test. Pass is required; if still failing, the fix is wrong and the item routes to Needs sign-off (do not retry-loop).
5. **Wider check (full project CI equivalent).** Run the broader project test suite, linters, and type-checkers, same as step (d.4) for Auto-applicable. Any failure (even a pre-existing one surfaced for the first time) triggers the **Test failure** stop condition.
6. **Verify kickoff alignment.** Re-read the relevant kickoff brief section(s) and confirm the fix does not introduce contract drift (new behavior the brief did not anticipate, error contract changes the brief did not approve, scope creep beyond the brief's goals). If the fix drifts, drop the item and route it to Needs sign-off; do not proceed.
7. **Record evidence in the iteration row.** Capture: test file path + test name, condensed before/after test output (one line each), wider-check command + result, and a one-line citation of the kickoff brief section the fix aligns with. This is the audit trail for the auto-apply.

The hard-disqualifier zones (security primitives, migrations, public API contracts, secrets handling, CI configuration) MUST already have rerouted this item to Needs sign-off at step (b). If you reach this step and discover the item touches one of those zones, stop, route to Needs sign-off, and trigger **Security-sensitive** or **Migrations / data / destructive ops** as applicable.

### e. Commit and push

Order matters: land the code, then move on.

1. `git add` only the files actually changed (never `git add -A`).
2. Commit with a message of the form `chore(panel): iter N, <short summary>` (e.g., `chore(panel): iter 1, drop unused imports and fix typos`).
3. Push: `git push origin <branch>` (or `git push -u origin <branch>` on the first iteration if pre-flight step 8 detected no upstream). **Never** `--force`, `--force-with-lease`, or any rebase flag. If the push fails on a hook (pre-push test, security check, lefthook stage, etc.), trigger the **Push hook failure** stop condition; do not silently retry, do not bypass with `--no-verify`, and do not "fix" unrelated test flakes inside this branch.
4. Do **not** amend, squash, or rebase. Each iteration is its own commit so you can inspect and revert per-iteration if needed.

### f. Iteration summary

Print a short summary:

- Iteration N / cap.
- `repo-class` in effect and active kickoff brief path (or "no active brief; Agent-resolvable bucket unavailable").
- Backends invoked + wall-clock per backend (so you can see which were slow / fast).
- Counts: Auto-applicable applied, Agent-resolvable applied (solo only; in multi-reviewer this is always 0 since they surface for human review), Needs sign-off surfaced, Needs human judgment surfaced, dropped at step (d.1) (Auto-applicable rule no longer fires), dropped at step (d-AR.2 or d-AR.4) (Agent-resolvable test did not fail or pass as required).
- For each Agent-resolvable applied: test file + test name, wider-check command + result, kickoff-brief section cited.
- Files touched.
- Commit SHA.
- Test command run + result.

This is what you scroll back through to audit the run. Then increment iteration counter and loop to (a).

## Stop conditions (mandatory human handoff)

If any condition fires, **stop**. Print the latest tables, name the condition, and wait for the user. Do not commit further, do not push, do not invoke backends again.

| Condition | Trigger |
|---|---|
| **Human attention required** | Step (c) found Needs sign-off or Needs human judgment items and Auto-applicable is empty. The normal path to handoff. |
| **Test failure** | Any test, linter, type-check, or formatter failed at step (d.4), including pre-existing failures surfaced for the first time. |
| **Push hook failure** | `git push origin <branch>` (step e.3) failed on a hook (pre-push test, security check, lefthook stage, etc.). Diagnose whether the failure traces to this iteration's diff or to pre-existing / unrelated state, surface the diagnosis, and hand off. Do not silently retry, do not bypass with `--no-verify`, and do not "fix" unrelated test flakes inside this branch. |
| **Loop detection** | A substantively similar finding (same file, same root issue, regardless of which backend surfaced it) has been raised in two consecutive iterations after the prior iteration applied a fix. Indicates the fix is not actually addressing the underlying issue, or that backends are hallucinating consistent false positives. |
| **Backend failure** | A backend invocation in step (a) did **not recover**: a final non-zero exit, empty or unparseable output, or auth lost with no successful retry. Judge by the final outcome, not intermediate stderr: do **not** fire on transient quota / rate-limit / retry notices the backend CLI prints while it retries internally and then still returns a valid result. Stop only on a non-recovered failure, rather than silently dropping the backend; the user invoked this skill specifically for that backend's variance. |
| **Iteration cap** | 15 iterations completed without convergence. |
| **Ambiguity** | A finding is borderline between buckets and the bright-line conditions cannot be confidently asserted across two consecutive iterations. Hand off rather than guessing. |
| **Security-sensitive** | Any Auto-applicable candidate touches auth, secrets, crypto, permissions, IAM, SQL/shell construction, or sandbox boundaries. Per the categorization disqualifiers, the item should already be Needs sign-off; if for any reason it landed in Auto-applicable, stop. |
| **Migrations / data / destructive ops** | Same as above for schema migrations, backfills, deletes, drops, anything irreversible. |
| **Dirty working tree** | Pre-flight step 7 found uncommitted changes. Stop before iteration starts. |
| **High false-positive ratio** | At least 3 items in the iteration AND more than half were dropped at step (d.1) (rule no longer fires). Backends may be misreading the diff or hallucinating tool output. Pause for re-alignment rather than spamming useless commits. |

## Auto-execution invariants

These hold at every step:

- **Never** address a Needs sign-off or Needs human judgment item, even if it looks easy. Those are reserved for the post-loop human pass via `/panel-review` or manual fixes.
- **Never** route a finding to Auto-applicable without a specific rule citation. "I am sure this is a typo" does not qualify; "ruff F401: imported but unused" does. The rule citation must come from the project tooling run in step (a), not from a backend's free-form recommendation.
- **Never** route a finding to Agent-resolvable without all five conditions (failing test exists and was confirmed to fail before the fix, test passes after, wider CI passes, kickoff alignment cited, not in a hard-disqualifier zone). A backend asserting "this fix is safe" is not evidence; the actual test + CI result is.
- **Never** route a finding to Agent-resolvable when pre-flight step 9 disabled the bucket (no `repo-class` resolved, no active kickoff brief, or `repo-class: multi-reviewer` keeps it on the surface-with-evidence path).
- **Never** silently drop a backend that failed in step (a). The user picked the backend set; partial runs hide which variance source went missing.
- **Never** modify CI configuration, `.env`, secrets, or lockfiles, even on a tool's recommendation.
- **Never** push `--force`, `--force-with-lease`, or amend / squash / rebase commits already pushed.
- **Never** silently retry a failed `git push` or bypass with `--no-verify`. Trigger the **Push hook failure** stop condition with a brief diagnosis instead.
- **Never** create a PR. `/panel-pairing` is a fix-drain loop; PR creation is `/self-review` or `/panel-review`'s job after the loop hands off.
- **Never** post anything to chat platforms, tickets, or any remote system.
- **Never** skip step (d.4) or step (d-AR.5) (wider test / lint / type-check run). A "simple" fix that breaks an unrelated test is the failure mode these guard against.
- **Never** skip step (d-AR.6) (kickoff alignment check). The whole point of the bucket is that downstream skills can trust the fix did not drift from the brief.
- **Never** trust the iteration counter alone for cap enforcement; verify at the top of the iteration via the explicit cap check.

## After the loop

When `/panel-pairing` exits (success, human handoff, or any other stop condition), present any remaining Needs sign-off / Needs human judgment items per the "Handoff presentation" rules below, then hand control back.

### Handoff presentation

When handing off Needs sign-off and/or Needs human judgment items, follow the CLAUDE.md `Code & PR Reviews` workflow rules. Do not default to one-by-one; choose the mode that minimizes human effort:

**Clustered decisions first.** Look for items that share a decision axis: same fix template (e.g., "add missing test coverage"), same lens (all doc nits, all naming nits), same scope (all in one module). When a cluster of 3+ items exists, use clustered-decision mode per CLAUDE.md: one `AskUserQuestion` per cluster with cluster-wide actions. For Needs sign-off clusters: `Apply all / Skip all / Pick individually`. For Needs human judgment clusters: bespoke options reflecting the shared axis. List each cluster's members before the question so the user can spot mis-grouped items.

**Batched decisions for the rest.** Items that don't fit a cluster use batched-decision mode: up to 4 findings per `AskUserQuestion` call, each as its own single-select question. Needs sign-off items get `Apply / Skip / Modify`. Needs human judgment items get bespoke options per finding.

**Progress tracking.** Always show a progress indicator (e.g., `[2/5]` or `cluster [1/2]: 4 findings`) so the user knows their position and what's left.

**Skip the workflow choice prompt.** Unlike `/self-review` and `/panel-review`, the pairing loop has already done the autonomous work and is handing off a small residual set. Don't ask "how do you want to review these?" when the answer is obvious from the item count and clustering shape. Just present them in the best mode.

The user's next move depends on the exit reason:

- On success ("panel converged, no findings remain"): consider running `/self-review` or `/panel-review` to do a final pass and open a PR.
- On Human attention required: address the surfaced items (already presented above), then re-run `/panel-pairing` to drain anything new, then open a PR.
- On Test failure, Push hook failure, or other safety stops: investigate the named condition. `/panel-pairing` does not auto-resume; the user explicitly re-invokes after the underlying issue is understood.

## Maintenance

After completing the workflow (or stopping), check if any part of these instructions seems outdated, incorrect, or misaligned with current tooling: backend CLI command syntax changes, changes to `Finding Categorization` thresholds, new auto-fix tools that should be tool-grounded by default, drift from `/panel-review`'s discovery shape (which `/panel-pairing` follows), or stop-condition gaps revealed by a real run. If something looks off, flag it and offer a ready-to-use prompt to paste into a new dotfiles session to update this command.

$ARGUMENTS
