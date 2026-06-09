Iterate with GitHub Copilot autonomously until it has no unresolved threads on the current PR. Copilot reviews land as `state: COMMENTED` (not `CHANGES_REQUESTED`), so the termination signal is "the latest Copilot review after our push leaves zero unresolved Copilot threads", not a state change.

Same validation rigor as `/copilot-review`, executed on autopilot, with hard stop conditions baked in for safety.

## When to use

You want a hands-off pairing pass with Copilot. The skill loops: address Copilot's threads, push, re-request review, wait, repeat. It pauses for human input the moment anything is ambiguous, looping, expanding scope, or breaking tests.

## Pre-flight (once per run)

1. **Get PR / repo info** (same as `/copilot-review` step 1).
2. **(Optional) Jira context** (same as `/copilot-review` step 2).
3. **Confirm the Copilot bot login and detect repo mode.** Default login is `copilot-pull-request-reviewer`. Verify by inspecting an existing review on the PR (`reviews(last: 20)` so the window is wide enough to surface a Copilot review even when several non-Copilot reviews stacked after the last Copilot one; `first: N` would return the oldest and may not include Copilot on a long-lived PR):
   ```bash
   gh api graphql -f query='
     query($owner: String!, $repo: String!, $number: Int!) {
       repository(owner: $owner, name: $repo) {
         pullRequest(number: $number) {
           reviews(last: 20) { nodes { author { __typename login } } }
         }
       }
     }
   ' -f owner='OWNER' -f repo='REPO' -F number=NUMBER
   ```
   Use the actual `Bot` login if it differs.

   **Fallback when no Copilot review is found.** If `reviews(last: 20)` returns zero Copilot-authored reviews (a brand-new PR Copilot has not yet reviewed, or a long-lived PR where 20+ non-Copilot reviews stacked after the last Copilot one), bot detection cannot key off a prior review on this PR. Two options, in preference order: (a) inspect another open or recently-merged PR in the same repo via the same `reviews(last: 20)` query and use that PR's Copilot review for `__typename` detection, or (b) default to `repo_mode = "app"` (the common case in 2026 since Copilot installs as a GitHub App by default) and let step (f)'s `request_copilot_review` MCP call plus `reviewRequests.nodes` verification confirm the assumption.

   Then set `repo_mode` from the same `__typename` field:
   - `__typename == "Bot"` → `repo_mode = "app"`. Copilot is installed as a GitHub App, not a collaborator. The REST endpoint `POST /repos/{owner}/{repo}/pulls/{n}/requested_reviewers` returns 422 ("not a collaborator") for App-typed reviewers and must NOT be used in this mode. Step (f) instead calls the `request_copilot_review` MCP tool (which wraps an internal endpoint that accepts Bot reviewers). Do not assume push alone will trigger a Copilot review: auto-review-on-push has been observed to silently no-op (see step (f) for the verified failure mode), so step (g)'s 10-minute poll is the only authoritative confirmation that Copilot has reviewed.
   - Otherwise → `repo_mode = "collaborator"`. Use the explicit re-request POST in step (f).
4. **Initialize iteration counter** = 0. The loop's per-iteration filter is `isResolved: false` (step (a)), so we don't need to snapshot HEAD or the baseline thread-ID set.

## Iteration loop

For each iteration (cap = **10**):

**Cap check (run at the start of every iteration, before step (a)).** Read the iteration counter (initialized to 0 in pre-flight step 4; incremented in step (g) on `NEW_REVIEW` and in step (f.5) on "one or more remaining"). If the counter has reached **10**, do not enter step (a). Trigger the **Iteration cap** stop condition and hand control back. This is the only place the cap is enforced; the counter increments in (g) and (f.5) do not enforce it themselves.

### a. Fetch Copilot's open threads

Use the same GraphQL query as `/copilot-review` step 3. Filter to threads where `isResolved: false` AND first comment author login == Copilot bot login. Do not add a "skip if older than last push" filter: `isResolved: false` is the canonical signal, and a previous iteration's resolve mutation may have failed silently; this loop should retry it, not skip it.

**Pre-check for already-handled threads.** Before running the validation passes, read the referenced file and decide whether the code already implements what Copilot asked for (because a prior iteration applied the fix but the resolve mutation never landed). If yes, classify the thread as `already-handled`, skip steps (b) and (c) for it, and let step (e) post a brief reply ("addressed in <commit-sha>") and re-fire the resolve mutation. This is what keeps a benign retry from tripping the **Cannot reproduce** stop condition in step (b)'s Pass 1.

**Guardrail.** A misjudged `already-handled` posts a misleading "addressed in <sha>" reply and resolves a thread that should not be resolved, and the rigor that would catch the misjudgement (step (b)) is the very rigor we just skipped. To classify as `already-handled`, you must (1) point to the specific commit on this branch that applied the fix (find via `git log "$(gh pr view --json baseRefName -q '.baseRefName')..HEAD" --oneline -- <file>`), and (2) confirm the current code on that file:line behaviorally matches Copilot's ask, not just looks superficially similar. If either step is uncertain, do **not** classify as `already-handled`; let the thread go through the full three-pass validation in step (b). False negatives are cheap (one extra validation pass); false positives are silent and corrupt the loop.

### b. Validate every thread (strict, three passes minimum)

Apply `/copilot-review` step 4 in full: the canonical three-pass rigor in CLAUDE.md `Validation Rigor (Issue Identification)`. Pass 1 reproduces, pass 2 takes an orthogonal angle, pass 3 consults outside-the-diff sources (git history, repo-wide search, official docs, library source/tests, deepwiki MCP, GitHub issues, RFCs, web search for text/research-based claims).

Be more conservative than in `/copilot-review` because nobody is checking our work in real time:

- If the three passes do not converge, mark `low-confidence` and trigger the **Cannot reproduce** or **Ambiguity** stop condition (whichever fits).
- If two valid interpretations exist, trigger **Ambiguity**.
- If a fix would touch code outside the PR's existing diff (lines this PR did not introduce or modify, even within an already-touched file), branch on the iteration's mix. **All** threads out-of-scope: trigger **Scope creep**. **Some** in-scope and **some** out-of-scope: do not stop here; follow the **Partial scope creep recipe** below the stop-conditions table, which drains in-scope threads via the normal Path A flow and replies to out-of-scope threads as adjacent findings before handing off.
- After classifying every thread, if the iteration has at least 3 threads AND more than half are `false positive`, trigger **High false-positive ratio** (the model may be misreading the change; pause for re-alignment rather than spamming dismissals). Single isolated hallucinations on small-thread iterations should be dismissed-and-resumed in-loop rather than escalated.
- Apply the same three-pass rigor to every proposed fix. Do not trust Copilot's recommendation; design our own from first principles, then validate it from three angles before accepting.

### c. Implement valid items: solution validated with two or three test angles

Apply `/copilot-review` step 6 (canonical rigor in CLAUDE.md `Validation Rigor (Solutions)`):

1. **Targeted test.** Write a failing test for the bug's exact reason, confirm it fails for the right reason, apply the fix, confirm it now passes.
2. **Wider check.** Run the broader project test suite, linters, type-checkers. Any regression (even in unrelated areas) triggers the **Test failure** stop condition.
3. **Edge / integration / manual** (when relevant). Boundary cases, integration or smoke tests, manual exercise of the user-facing flow.

Skip the targeted-test step only for non-behavioral changes (docs, comments, pure renames, formatting). For those, substitute review angles per the canonical doctrine — including the contract-reword grep rule, which is especially load-bearing in this loop because every iteration we leave stragglers in costs a full Copilot review cycle.

For **false positives**, draft the dismissal reply (citing the three passes) but do NOT post yet. We post all replies in step (e) after the build is green.

### d. Run the full local check suite

Run whatever the project ships for local verification: tests, linters, type checkers, formatters. Common entry points: `npm test`, `pytest`, `go test ./...`, `cargo test`, `bundle exec rspec`, `mise run test`, `lefthook run pre-commit`. If the project has a single canonical command, prefer it. If anything fails (even a pre-existing failure unrelated to our changes), trigger the **Test failure** stop condition.

### e. Commit, push, reply, resolve

Order matters: land the code first, then talk about it. If we replied/resolved before pushing and the push failed, threads would sit resolved without an actual fix landed and the next iteration would not see them as unresolved (silent loss of work).

**Branch on whether this iteration produced code changes.**

**Path A (code changes were made, the common path):**

1. **Commit and push.**
   - `git add` only the files we actually changed for this iteration (never `git add -A`).
   - Commit with a message of the form `chore(copilot): iter N, address <short summary>`.
   - Push: `git push origin <branch>`. **Never** `--force`, `--force-with-lease`, or any rebase flag. If the push fails on a hook (pre-push test, security check, lefthook stage, etc.), trigger the **Push hook failure** stop condition; do not silently retry, do not bypass with `--no-verify`, and do not "fix" unrelated test flakes inside this branch.
2. **Capture poll-window start epoch and baseline Copilot-review id** (substitute the PR number from pre-flight step 1; substitute the verified bot login from pre-flight step 3 in the `--arg bot ...` flag if it differs from the default, otherwise the baseline file silently lands empty and step (g) loses its disambiguation):
   ```bash
   echo $(( $(date +%s) - 2 )) > /tmp/copilot-pairing-push-epoch.NUMBER
   gh api graphql -f query='
     query($owner: String!, $repo: String!, $number: Int!) {
       repository(owner: $owner, name: $repo) {
         pullRequest(number: $number) {
           reviews(last: 20) { nodes { id author { login } } }
         }
       }
     }
   ' -f owner='OWNER' -f repo='REPO' -F number=NUMBER \
     | jq -r --arg bot 'copilot-pull-request-reviewer' '
         .data.repository.pullRequest.reviews.nodes
         | map(select(.author.login == $bot))
         | last // empty
         | .id // ""' \
     > /tmp/copilot-pairing-baseline-review-id.NUMBER
   ```
   The Bash tool spawns a fresh shell per invocation, so plain shell variables will not be visible to the step (g) script. Use the temp files, or inline the literal values into the step (g) script when you send it. Filenames are namespaced by PR number so concurrent pairing sessions on different PRs (e.g., separate worktrees) do not clobber each other.

   We capture two values because step (g) needs both:
   - **`push_epoch`** (poll-window start, kept under that legacy name in the variable + temp-file path for backward compatibility with existing run-script copies; conceptually it is the lower bound for the (g) poll filter, applicable to both Path A after a push and Path B with no push) drives the 10-minute deadline math. We subtract 2 seconds when writing the file to absorb a sub-second race: jq's `fromdateiso8601` is second-precision, and a fast Copilot review submitted between `git push` returning and our `date +%s` call could land its `submittedAt` one second before `push_epoch` and be falsely filtered out. Two seconds is conservative for plausible clock skew and still keeps the (g) poll's start before any meaningful new-review submission window.
   - **`baseline_id`** lets the poll match a *new* Copilot review unambiguously even when its `submittedAt` rounds down to the same second as `push_epoch`. Filtering on `submittedAt > push_epoch` alone misses same-second submissions (jq's `fromdateiso8601` is second-precision, and macOS `date` doesn't support sub-second `%N`). Filtering on `id != baseline_id` alone would re-match older Copilot reviews. Combining both (`submittedAt >= push_epoch AND id != baseline_id`) excludes pre-existing reviews and accepts same-second submissions. If there is no prior Copilot review, the baseline file holds the empty string and any non-empty review id passes.

   **Why `reviews(last: 20)` here, not a narrower window.** A narrower window can drop the most recent Copilot review on long-lived PRs: each `addPullRequestReviewThreadReply` in (e.3) can auto-vivify a separate viewer-authored review (see step (e.4) "Two auto-vivify modes"), and several review-state mutations can stack up between Copilot reviews. With `last: 5`, the most recent Copilot review can fall out of the window, the jq pipeline writes the empty string to the baseline file, and step (g)'s poll then cannot distinguish "new Copilot review submitted at the same second as `push_epoch`" from "no new review at all". `last: 20` keeps the actual baseline visible across realistic clutter. (Pre-flight step 3 uses the same `last: 20` window for the same robustness reason; see its no-Copilot-review fallback for the bootstrap case where this PR has no prior Copilot review at all.)
3. **Reply to threads** using `/copilot-review` step 8 mutations. **Use `addPullRequestReviewThreadReply` only**; see the DO-NOT-USE callout in `/copilot-review` step 8 about `addPullRequestReviewComment`. **Body construction: inline bash heredoc, not temp file.** Build the body inside the same `Bash` invocation that runs the GraphQL mutation:

   ```bash
   body=$(cat <<'EOF'
   Addressed in <sha>. <short prose>
   EOF
   )
   gh api graphql -f query='
     mutation($threadId: ID!, $body: String!) {
       addPullRequestReviewThreadReply(input: {
         pullRequestReviewThreadId: $threadId,
         body: $body
       }) {
         comment { id }
       }
     }
   ' -f threadId='<thread_id>' -f body="$body"
   ```

   The earlier-recommended pattern (`Write` to `/tmp/copilot-reply-*.md`, then `cat` it in a separate `Bash` call) has been observed to trip permission denials with the rationale "body content is unverifiable" because the harness can flag chained file-write-then-public-post sequences as suspicious. Inline heredoc keeps body construction and posting in a single tool invocation. Fall back to a temp file only when a body is genuinely too large to inline (rare). Reply body varies by classification, since this iteration may have a mix:
   - **`valid`**: short reply describing the change we made, ideally referencing the new commit SHA from (e.1).
   - **`already-handled`**: reply with `addressed in <commit-sha>` per Path B step 2, using the same `git log "$(gh pr view --json baseRefName -q '.baseRefName')..HEAD" --oneline -- <file>` lookup. Do not hardcode `main` as the base.
   - **`false positive`**: post the dismissal reply drafted in step (b) (citing the three passes and why the concern does not apply).
4. **Submit any auto-vivified pending review (mandatory).** `addPullRequestReviewThreadReply` can create a new pending review owned by the viewer when none is in progress; the replies posted in (e.3) then stay invisible (to GitHub UI, to Copilot, to humans) until that review is submitted. See `/copilot-review` step 8's "Submit any auto-vivified pending review" sub-step for the exact GraphQL. Procedure: query the PR's `reviews(states: PENDING)` filtered by `author.login == viewer.login`; for each, call `submitPullRequestReview(id, event: COMMENT)`. Re-query and assert zero pending reviews owned by the viewer remain before proceeding to step (e.5). If a pending review cannot be submitted, stop with the **Pending reply unsubmittable** condition.

   **Two auto-vivify modes.** Across real runs, `addPullRequestReviewThreadReply` has been observed in two distinct shapes, and they need different responses:
   - **(a) Pending-and-not-submitted (dangerous, silent invisibility).** The mutation creates a viewer-authored review in state `PENDING` and the reply is parented under it; GitHub, Copilot, and humans see nothing until that review is submitted. This is exactly what (e.4) above guards against: the `reviews(states: PENDING)` query catches it and `submitPullRequestReview(event: COMMENT)` rescues the replies. **Mandatory to handle.**
   - **(b) Auto-vivified-and-auto-submitted (benign timeline clutter).** The mutation creates a separate viewer-authored review that GitHub immediately submits as `state: COMMENTED` (i.e. it never sits in `PENDING`). Replies are visible to everyone, but the PR timeline grows one extra review per reply mutation. The (e.4) query correctly finds zero pending reviews; nothing is broken. **Acceptable, no action needed**: do not add cleanup mutations to delete these (they are real `state: COMMENTED` reviews and removing them is incorrect). Step (h)'s iteration summary may note "N auto-vivified COMMENTED reviews" if useful for auditing, but the loop should not pause for this condition.

   The distinction matters because the same mutation produces both shapes non-deterministically across iterations of the same run; do not treat (b)'s presence as evidence that (a) cannot also happen later.
5. **Resolve threads** using `/copilot-review` step 8's `resolveReviewThread` mutation.
6. Proceed to step (f).

**Path B (no code changes; every thread was `already-handled` or `false positive`):**

1. Skip commit/push (no new HEAD), but still capture the poll-window start epoch (`push_epoch`, using the same `echo $(( $(date +%s) - 2 )) > /tmp/copilot-pairing-push-epoch.NUMBER` capture from Path A step 2; the variable and temp-file name keep the `push_epoch` / `push-epoch` legacy spelling) and baseline Copilot-review id using the same GraphQL block as Path A step 2. Step (g)'s poll runs on Path B too (see step 5).
2. Post the reply for each thread, varying by classification (use `addPullRequestReviewThreadReply` either way; same DO-NOT-USE callout applies):
   - **`already-handled`**: reply with a short body referencing the prior commit that actually addressed it. Find the commit via `git log "$(gh pr view --json baseRefName -q '.baseRefName')..HEAD" --oneline -- <file>` (scoped to this branch's commits, top entry is the most recent). Do not hardcode `main`: PRs targeting `develop`, `release/*`, or any other base branch would otherwise return wrong or empty commits.
   - **`false positive`**: post the dismissal reply drafted in step (b) (citing the three passes and why the concern does not apply).
3. **Submit any auto-vivified pending review (mandatory).** Same procedure as Path A step 4. The auto-vivify failure mode applies here too because we still call `addPullRequestReviewThreadReply`.
4. Resolve threads via `resolveReviewThread`.
5. Proceed to step (f) and (g), like Path A. The earlier guidance to skip (f)/(g) "because Copilot will not respond on unchanged HEAD" was based on a wrong premise: real-run evidence (PR #18 on 2026-05-08) shows Copilot does re-review an unchanged HEAD when observable PR state has changed since the last review (PR description / title / label edits, plus the replies and resolves you just posted). Run (f) and (g) to capture any response. The (g) TIMEOUT branch is now safe on Path B: it falls through to step (f.5) instead of triggering **No response** (see step (g) exit handling).

### f. Re-request Copilot review (mode-aware, verify-loud)

Branch on `repo_mode` from pre-flight step 3.

**`app` mode (`__typename == "Bot"` in pre-flight):** auto-review on push is **not** guaranteed. Verified failure mode (2026-05-02 live run on `SymmetrySoftware/stl-poc#13`): push completed, `reviewRequests.nodes` came back empty, no auto-review fired, and step (g) would have timed out silently after 10 minutes. Do not skip the request.

Explicitly request Copilot via the GitHub MCP tool:

```
mcp__<github-server>__request_copilot_review
params: { owner, repo, pullNumber }
```

The substitute for `<github-server>` depends on the active MCP server (e.g. `claude_ai_Github-Symmetry`, `claude_ai_Github-Gusto`). The REST endpoint `POST /repos/{owner}/{repo}/pulls/{n}/requested_reviewers` returns 422 "not a collaborator" for Bot reviewers and must NOT be used in app mode; the MCP tool wraps an internal Copilot-review-request endpoint that accepts Bot reviewers. If no `request_copilot_review` MCP tool is available on the active server, stop with **Re-review unavailable** and report; do not assume push alone will trigger a review.

After the MCP call returns success, **verify** Copilot is actually on the requested-reviewer list:

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $number: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
        reviewRequests(first: 10) {
          nodes {
            requestedReviewer {
              ... on Bot { login }
              ... on User { login }
            }
          }
        }
      }
    }
  }
' -f owner='OWNER' -f repo='REPO' -F number=NUMBER
```

If the verified Copilot bot login (from pre-flight step 3) is in `reviewRequests.nodes`, proceed to step (g). If not, log a warning ("MCP request_copilot_review returned success but reviewRequests does not include the bot") and proceed to step (g) anyway: the poll is the authoritative confirmation. **Step (g) is mandatory in app mode.** Skipping it on the assumption that the request "must have worked" is the regression earlier wording was written to prevent.

**`collaborator` mode:** try to trigger a new Copilot review by re-adding it to the requested reviewers list. Substitute the verified bot login from pre-flight step 3 if it differs from the default.

```bash
gh api -X POST "repos/OWNER/REPO/pulls/NUMBER/requested_reviewers" \
  -f 'reviewers[]=copilot-pull-request-reviewer'
```

This call is **best-effort**, not load-bearing. The actual signal the loop relies on is step (g)'s GraphQL poll for a new review.

Inspect the response and branch:

| Outcome | Body contains | Action |
|---|---|---|
| 2xx | n/a | Proceed to step (g). |
| 422 | `already requested` (or similar "duplicate reviewer") | DELETE the reviewer, re-POST. Then proceed to step (g). |
| 422 | `not a collaborator` | REST cannot request this reviewer. Possible causes: pre-flight mode detection was wrong (bot is App-typed), the bot lost collaborator status mid-run, or the login is otherwise ineligible. Log the outcome and proceed to step (g); the poll is the authoritative signal. Re-check pre-flight step 3 on the next run. |
| Other (4xx/5xx) | n/a | Log warning. Proceed to step (g). |

DELETE+POST retry pattern (only for the `already requested` case):

```bash
gh api -X DELETE "repos/OWNER/REPO/pulls/NUMBER/requested_reviewers" \
  -f 'reviewers[]=copilot-pull-request-reviewer'

gh api -X POST "repos/OWNER/REPO/pulls/NUMBER/requested_reviewers" \
  -f 'reviewers[]=copilot-pull-request-reviewer'
```

Do NOT trigger the **No response** stop condition based on this step's HTTP outcome. **No response** is reserved for step (g)'s 10-minute poll timing out, the only authoritative signal that Copilot did not review.

### f.5. Resolved-thread sanity check (Path B fall-through)

Reached on Path B after step (g) returns TIMEOUT (Copilot did not re-review the unchanged HEAD). On Path A, (g)'s NEW_REVIEW branch already re-fetches threads and (g)'s TIMEOUT branch triggers **No response**, so this step is Path B-only. Re-fetch reviewThreads (same query as step (a)) and count unresolved Copilot threads:

- **Zero remaining**: success. Exit the loop. Print the iteration summary noting "resolve-only iteration, (g) timed out as expected, all Copilot threads now resolved".
- **One or more remaining** (rare: a resolve mutation failed again): increment iteration counter and loop back to step (a). If the same threads remain unresolved across two consecutive iterations, trigger the **Persistent resolve failure** stop condition.

### g. Wait for Copilot's response

**This step is mandatory after every Path-A push, in both `app` and `collaborator` modes.** Do not infer that Copilot has reviewed from any other signal: not the push itself, not step (f)'s HTTP outcome, not "the last N iterations all converged so this one will too". The poll below is the only authoritative confirmation.

We need to wait up to **10 minutes** for a new Copilot review. The harness's Bash tool blocks long leading sleeps and shorter sleeps chained across multiple tool calls (the limit applies at the tool-invocation boundary, not inside a running process). So do not poll by issuing one Bash tool call per attempt with `sleep` between them. Both patterns below are safe because the sleeping happens *inside* a single backgrounded invocation that the harness does not introspect.

**Preferred: a single backgrounded poll script** (`Bash` with `run_in_background=true`). The script polls itself and exits when the condition is met or the deadline passes. You'll be notified when it exits. Substitute the verified bot login from pre-flight step 3 in the `--arg bot ...` flag if it differs from the default.

```bash
# Read push_epoch and baseline_id from the temp files written in step (e).
# Bash tool calls do not share shell state, so reading from the files (or
# inlining the literal values before sending the script) is required. Files
# are namespaced by PR number; substitute NUMBER from pre-flight step 1.
push_epoch=$(cat /tmp/copilot-pairing-push-epoch.NUMBER 2>/dev/null)
baseline_id=$(cat /tmp/copilot-pairing-baseline-review-id.NUMBER 2>/dev/null)
[ -n "$push_epoch" ] || { echo "push_epoch not set; capture it in step (e) before running"; exit 2; }
deadline=$(( push_epoch + 600 ))
while [ $(date +%s) -lt $deadline ]; do
  latest=$(gh api graphql -f query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          reviews(last: 20) { nodes { id author { login } state submittedAt } }
        }
      }
    }
  ' -f owner='OWNER' -f repo='REPO' -F number=NUMBER \
    | jq -r --arg bot 'copilot-pull-request-reviewer' --arg baseline "$baseline_id" --argjson since "$push_epoch" '
        .data.repository.pullRequest.reviews.nodes
        | map(select(
            .author.login == $bot
            and .id != $baseline
            and (.submittedAt | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) >= $since
          ))
        | last // empty')
  if [ -n "$latest" ]; then echo "NEW_REVIEW $latest"; exit 0; fi
  sleep 30
done
echo "TIMEOUT"; exit 1
```

**Alternative**: `Monitor` the same script with an until-loop if you want streaming progress lines.

Branch on the script's exit:

- **Exit 0 (`NEW_REVIEW`)**: re-fetch reviewThreads. If any are unresolved, increment iteration counter and loop back to (a). If zero unresolved, success: exit the loop.
- **Exit 1 (`TIMEOUT`) on Path A**: trigger the **No response** stop condition (Copilot did not review the new code).
- **Exit 1 (`TIMEOUT`) on Path B**: fall through to step (f.5) for the resolved-thread sanity check; success if zero unresolved. Path B TIMEOUT is the expected outcome when no observable PR-state change triggered Copilot to re-review an unchanged HEAD; the resolves we already landed mean the loop has converged.
- **Exit 2 (bad input)**: step (e) failed to capture `push_epoch`. Bug in our flow. Stop and surface the script's stderr.
- **Any other exit code (e.g. 143 from SIGTERM, 137 from SIGKILL/OOM, or any 128+N signal exit from a harness session end)**: the script was killed externally; its output is not authoritative. Re-query GraphQL directly, reading `push_epoch` and `baseline_id` from the temp files. The recovery query uses `reviews(last: 20)` for the same reason the poll script and step (e.2)'s baseline capture do: viewer-authored auto-vivified reviews and other state churn since the push can stack up, and a narrower window can miss the new Copilot review. (Substitute the verified bot login from pre-flight step 3 in the `--arg bot ...` flag if it differs from the default; same instruction as the poll script.)
  ```bash
  push_epoch=$(cat /tmp/copilot-pairing-push-epoch.NUMBER)
  baseline_id=$(cat /tmp/copilot-pairing-baseline-review-id.NUMBER)
  gh api graphql -f query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          reviews(last: 20) { nodes { id author { login } state submittedAt } }
        }
      }
    }
  ' -f owner='OWNER' -f repo='REPO' -F number=NUMBER \
    | jq --arg bot 'copilot-pull-request-reviewer' --arg baseline "$baseline_id" --argjson since "$push_epoch" '
        .data.repository.pullRequest.reviews.nodes
        | map(select(
            .author.login == $bot
            and .id != $baseline
            and (.submittedAt | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) >= $since
          ))'
  ```
  - **New Copilot review found**: treat as `NEW_REVIEW` and proceed as above.
  - **No new review, still inside the 10-minute window** (`[ $(date +%s) -lt $((push_epoch + 600)) ]`): restart the background poll script. Cap restarts at **2** per iteration to prevent thrashing; after that, treat as `TIMEOUT` and apply the same Path A / Path B split as the next bullet.
  - **No new review, past deadline**: treat as `TIMEOUT`. On Path A: trigger **No response**. On Path B: fall through to step (f.5) for the resolved-thread sanity check (TIMEOUT is the expected case on Path B; same semantics as the normal Exit 1 split above).

Never assume "loop succeeded" from a non-zero, non-1 exit code. Always cross-check via GraphQL.

### h. Iteration summary

After each iteration, print a short summary:
- Iteration number / cap
- Path taken (A = code changes pushed, B = resolve-only)
- Threads addressed (counts by classification: valid / already-handled / false positive / adjacent finding)
- Commit SHA pushed (Path A only; `n/a` on Path B)
- Test command run + result (Path A only; `n/a` on Path B since no code changed)
- Re-review request status: both paths. In `app` mode, report the outcome of step (f)'s `request_copilot_review` MCP call plus the `reviewRequests.nodes` verification result; in `collaborator` mode, report the actual HTTP outcome from step (f). On Path B, also note whether step (g) returned NEW_REVIEW (Copilot re-reviewed unchanged HEAD) or TIMEOUT (the expected case that falls through to (f.5)).

This is what I scroll back through to audit the run.

## Stop conditions (mandatory human handoff)

If any condition fires, **stop**. Print the latest iteration table, name the condition, and wait for me. Do not push, do not reply, do not re-request review. (Exception: when the **Scope creep** row's "SOME threads in-scope" branch fires, follow the **Partial scope creep recipe** below the table instead; it deliberately drains in-scope work via the normal Path A flow and posts adjacent-finding replies on out-of-scope threads before stopping without re-requesting review. Every other row follows this preamble strictly.)

| Condition | Trigger |
|---|---|
| **Ambiguity** | Comment is unclear, has multiple valid interpretations, or requires a product/UX call. |
| **Loop detection** | Copilot raised a substantively similar concern (same file, same root issue) in two consecutive iterations. |
| **Persistent resolve failure** | A `resolveReviewThread` mutation has silently failed (or been rolled back) for the same threads across two consecutive iterations, so the resolve-only short-circuit in step f.5 cannot drain the queue. |
| **Scope creep** | A fix would touch code outside the PR's existing diff, or contradicts the PR's stated intent / Jira AC. When SOME threads are in-scope and others are not, see "Partial scope creep" below for the recipe before stopping. |
| **Test failure** | Any test, linter, type-check, or formatter fails after our change, including pre-existing failures we surface for the first time. |
| **Push hook failure** | `git push origin <branch>` (step (e.1)) fails on a hook (pre-push test, security check, lefthook stage, etc.). Diagnose whether the failure traces to this iteration's diff or to pre-existing / unrelated state, surface the diagnosis, and hand off. Do not silently retry, do not bypass with `--no-verify`, and do not "fix" unrelated test flakes inside this branch. |
| **Security-sensitive** | The change touches auth, secrets handling, crypto, permissions, IAM, SQL/shell construction, or sandbox boundaries. Always pause. |
| **High false-positive ratio** | At least 3 threads in the iteration AND more than half are false positives (model may be misreading the change). Pause for re-alignment. |
| **Iteration cap** | 10 iterations completed without convergence. Stop and report. |
| **Cannot reproduce** | Issue is not reproducible and the proposed fix is non-trivial. |
| **Migrations / data / destructive ops** | Schema migrations, data backfills, deletes, drops, or anything irreversible. Always human-driven. |
| **No response** | 10-minute poll window in step (g) expires with no new Copilot review. |
| **Re-review unavailable** | Step (f) `app` mode found no `request_copilot_review` MCP tool on the active server, so we cannot trigger a Copilot review and step (g)'s poll would never see one. |
| **Pending reply unsubmittable** | A pending review owned by the viewer cannot be submitted via `submitPullRequestReview` in step (e.4), so replies posted in (e.3) would remain invisible to GitHub, Copilot, and humans. |
| **Conflicting signals** | Copilot's later review contradicts an earlier one we already addressed. Pause to decide which to honor. |

### Partial scope creep recipe

When an iteration's threads split between in-scope (lines this PR introduced or modified) and out-of-scope (pre-existing code the PR does not touch), the **Scope creep** row above is a partial stop, not a full stop. Use this recipe instead of treating the iteration as a hard handoff:

1. **Address the in-scope threads as normal.** Run steps (b) validate, (c) implement, (d) local check, (e.1) commit + push, (e.3) reply, (e.4) submit any pending review, (e.5) resolve. Treat them exactly as you would an iteration with no out-of-scope threads.
2. **Reply to the out-of-scope threads as adjacent findings.** For each, post a reply via `addPullRequestReviewThreadReply` whose body names: (a) that the lines pre-date this PR's diff (cite the commit or `git blame` evidence), (b) what the proposed fix would be (so the human or a follow-up PR has the design ready), and (c) where the fix should live (separate PR, follow-up issue, or specific file outside the diff). **Do NOT call `resolveReviewThread` on these.** Leaving them unresolved is what hands them to the human as live findings. **After all adjacent replies are posted, re-run the (e.4) pending-review submission guard.** Auto-vivify mode (a) can re-occur on these new replies even after step 1's (e.4) cleared the queue, so query `reviews(states: PENDING)` filtered by `author.login == viewer.login` again, submit each via `submitPullRequestReview(id, event: COMMENT)`, and re-assert zero pending reviews owned by the viewer remain before proceeding to step 3. If a pending review cannot be submitted, stop with the **Pending reply unsubmittable** condition.
3. **Stop the loop, do not re-request review.** Skip steps (f) and (g) for this iteration: the next move is a human decision (the three-choice prompt below), so the 10-minute poll would only delay the handoff. This is the **only** documented exception to the "never skip step (g) after a Path-A push" auto-execution invariant; if the user picks "approve fixing in this PR", the next iteration fetches a fresh Copilot review anyway, so no signal is permanently lost. Print the iteration summary table per step (h), with the adjacent-finding count broken out, and ask the user to choose:
   - **(a) Approve fixing in this PR**: resume the loop on the next iteration with the deferred fixes pulled into scope. Pushing the new commit will land via the normal Path A flow.
   - **(b) Track in a follow-up issue**: file the issue (or have the user file it), then post a final reply on each adjacent thread with `tracked in <link>` and call `resolveReviewThread` on it. Loop ends.
   - **(c) "Won't fix in this PR"**: post a one-line rationale reply on each adjacent thread, call `resolveReviewThread`, then resume the loop if there are still in-scope threads to address (rare, since step 1 already drained those) or end the loop otherwise.

**Scope this recipe carefully.** It applies only when the in-scope set is **non-empty**. If every thread in an iteration would touch out-of-PR-diff code, the original full-stop **Scope creep** condition still applies: do not push, do not reply, stop and hand off entirely. The recipe exists to avoid wasting a converged iteration when the in-scope half is real work; it is not a license to address adjacent findings in the absence of any in-scope work.

## Auto-execution invariants

These hold at every step:
- **Never** `git push --force` or `--force-with-lease`.
- **Never** silently retry a failed `git push` or bypass with `--no-verify`. Trigger the **Push hook failure** stop condition with a brief diagnosis instead.
- **Never** amend, squash, or rebase commits already pushed.
- **Never** resolve a thread without an explanatory reply.
- **Never** skip the failing-test-first step on a behavior-changing fix.
- **Never** commit or touch files outside the PR's diff to "fix" something we noticed in passing. Surface it as an adjacent finding for human review instead.
- **Never** modify CI configuration, `.env`, secrets, or lockfiles unless the Copilot thread is specifically about that file.
- **Never** post anything to chat platforms or tickets.
- **Never** skip step (g) after a Path-A push, with one documented exception: the **Partial scope creep recipe** step 3 explicitly skips (f) and (g) because the loop hands off to the user immediately and the next iteration (if the user picks "approve fixing in this PR") fetches a fresh Copilot review anyway. Outside that recipe, the 10-minute poll is the only authoritative signal that Copilot has (or has not) reviewed. App-mode auto-review, step (f)'s HTTP outcome, prior iterations' patterns, and elapsed iteration count are not substitutes. Confirmation bias from a long successful run is the failure mode this invariant catches. **Path B also runs (g)** even though HEAD is unchanged: Copilot can re-review unchanged HEAD on PR-state changes (description/title/label edits, replies, resolves), and the (g) TIMEOUT branch falls through to (f.5) safely on Path B.
- **Never** leave replies in a pending review. `addPullRequestReviewThreadReply` may auto-vivify a pending review owned by the viewer when none is in progress; step (e.4) submits it before resolving threads. A run that completes with replies still pending is a silent failure: GitHub, Copilot, and humans see no replies, and the next iteration polls Copilot reviewing against a state where it has no record of our responses (confirmation-bias path: looks fine, isn't).
- **Never** trust an external-effect step's happy-path response without re-querying state. After step (f)'s `request_copilot_review` MCP call, verify the bot is on `reviewRequests.nodes`; after step (e.3)'s reply mutation, verify zero pending reviews owned by the viewer remain. Both bugs that motivated this section's wording (2026-05-02 live run on `SymmetrySoftware/stl-poc#13`) returned success and looked fine.

## Maintenance

After completing the workflow (or stopping), check if any part of these instructions seem outdated or misaligned with current tooling: GraphQL schema changes, deprecated fields, new `gh` CLI capabilities, changes to how Copilot reviews are requested or to the bot's login. If something looks off, flag it and offer a ready-to-use prompt I can paste into a new dotfiles session to update this command.

$ARGUMENTS
