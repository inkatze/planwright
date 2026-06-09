Review and address unresolved GitHub Copilot review threads on the current PR.

## Steps

### 1. Get PR and repo info

```bash
gh pr view --json number -q '.number'
gh repo view --json owner,name -q '.owner.login + " " + .name'
```

### 2. (Optional) Fetch Jira ticket for context

Extract a Jira ticket key from the branch name or PR title. If a key is found, fetch the ticket using the Jira MCP tools (`getJiraIssue`) and note the description and acceptance criteria. Use this context when validating threads (e.g., a concern might be out of scope per the AC, or a missing check might be required by the AC). If no key is found or Jira tools are unavailable, skip this step.

### 3. Fetch unresolved review threads

Use this exact GraphQL query (substitute the owner, repo, and number values):

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $number: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            path
            line
            startLine
            comments(first: 20) {
              nodes {
                id
                body
                author { __typename login }
                createdAt
              }
            }
          }
        }
      }
    }
  }
' -f owner='OWNER' -f repo='REPO' -F number=NUMBER
```

Filter to threads where `isResolved: false` AND the first comment author is the Copilot bot. The standard bot login is `copilot-pull-request-reviewer` (`__typename: Bot`), but verify per run, especially on GHES or repos with custom bot integrations. Use `reviews(last: 5)` so the query surfaces the most-recent reviews; `first: 5` would return the oldest and may not include Copilot on a long-lived PR:

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $number: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
        reviews(last: 5) { nodes { author { __typename login } } }
      }
    }
  }
' -f owner='OWNER' -f repo='REPO' -F number=NUMBER
```

Use the actual `Bot` login if it differs. If the PR has threads from other authors too, leave those for `/peer-review`.

Apply this jq filter to the **`reviewThreads` query output** (the first GraphQL block in this step, not the `reviews(last: 5)` bot-login verification block) (substitute the verified bot login if it isn't the default):

```bash
jq --arg bot 'copilot-pull-request-reviewer' '
    .data.repository.pullRequest.reviewThreads.nodes
    | map(select(.isResolved == false and .comments.nodes[0].author.login == $bot))'
```

Filter on `login` rather than `__typename == "Bot"` so other bot integrations (CodeQL, Dependabot review, etc.) don't get pulled in.

### 4. Validate every thread: three passes minimum (different angle each)

Apply the canonical rigor in CLAUDE.md `Validation Rigor (Issue Identification)`. For each unresolved Copilot thread:

- **Read first.** Comment body, referenced file:line, plus enough surrounding context (callers, related modules) to understand the real behavior.
- **Pass 1: direct reproduction.** When the claim is about runtime behavior, try to reproduce it. Write a failing test, run a script, trace through the code with concrete inputs, or construct an input that triggers the claimed bug. Inability to reproduce is a strong signal of a false positive.
- **Pass 2: orthogonal angle.** Look at it from a different perspective: callers and what they assume, related code paths and side effects, hidden invariants, project conventions, sibling implementations, existing test coverage that may already prove the case safe.
- **Pass 3: outside-in angle.** Sources outside the diff. `git log` / `git blame` for the why-it-is-the-way-it-is. Repo-wide search for similar patterns to see if the concern applies elsewhere or only here. For text/research-based claims (API correctness, spec compliance, deprecated patterns, security claims, library behavior): official docs, the library's own source/tests, deepwiki MCP, GitHub issues, RFCs, web search. Note what was consulted.

**Do not take Copilot's recommendation as correct.** Even when the underlying concern is real, design the best solution from first principles. Copilot's suggested fix may be insufficient (treating a symptom not the cause), wrong (introduces a new bug), unidiomatic for the codebase, or out of scope. Apply the same three-pass rigor to the proposed fix: does it actually resolve the issue, does it survive an orthogonal angle, does it match what docs/conventions/external references would recommend.

Classify each thread as **valid** (needs a fix), **false positive** (no real problem), or **low-confidence** (passes did not converge; never guess).

**Adjacent-findings Discovery Rigor pass.** After classifying every thread, do a scoped Discovery Rigor pass over the files / hunks Copilot reviewed (canonical spec in CLAUDE.md `Discovery Rigor (Issue Identification)`). Walk the lens checklist (correctness, security, error handling, performance, concurrency / state, naming / readability / structure, documentation, tests, cross-file consistency); for each lens, list findings or state `none`. Run the project's linters / formatters / type checkers / static analyzers and cite rules when they fire. Then a self-critique pass for what feels under-represented. Surface each finding as an extra row tagged `adjacent finding` in the table. Scope: only the files / hunks Copilot reviewed; a full-diff sweep belongs in `/self-review`. In `/copilot-pairing`, adjacent findings are never auto-fixed (per the auto-execution invariants); they are surfaced for human review only.

### 5. Present the validated table

Output one Markdown table. Default columns:

| # | Thread ID | File:Line | Copilot's concern | What we found | Reproduced? | Classification | Confidence | Our proposed fix |
|---|---|---|---|---|---|---|---|---|

Notes on columns:
- **Copilot's concern**: a tight one-line summary of what the bot said, not a copy-paste.
- **What we found**: the result of our investigation (the actual behavior, the real root cause, or "no issue, code already handles X").
- **Reproduced?**: `yes` / `no` / `n/a` (n/a for items not reproducible by their nature, e.g. style/naming).
- **Classification**: `valid` / `false positive` / `low-confidence` / `adjacent finding`.
- **Confidence**: `high` / `medium` / `low`. How sure we are about the classification.
- **Our proposed fix**: a one-line description of the change we want to make. May explicitly differ from Copilot's suggestion.

If a column is not useful for the current PR (or you want a different cut), say so before printing the table and adjust. Optional add-ons worth considering case by case: `Severity`, `Test plan`, `Copilot's suggested fix` (when it diverges meaningfully from ours), `Files touched by fix`, `Scope risk` (in-scope / out-of-scope).

**Adjacent-findings output (from step 4's Discovery Rigor pass).** Always emit:

1. The canonical lens-coverage table from CLAUDE.md `Discovery Rigor (Issue Identification)`, scoped to the files / hunks Copilot reviewed (not the full diff).
2. **Three adjacent-findings tables**, split per CLAUDE.md `Finding Categorization`. All three always appear; print a single `none` row when a bucket is empty.

**Auto-applicable adjacent findings** (`/polish` could handle these autonomously on the same branch):

| # | Lens | File:Line | Finding | Rule cited | Validation passes | Recommendation |
|---|---|---|---|---|---|---|

**Needs sign-off adjacent findings** (LLM has a single recommended fix, but the change warrants approval before landing):

| # | Lens | File:Line | Finding | Proposed fix | Why sign-off | Validation passes | Recommendation |
|---|---|---|---|---|---|---|---|

**Needs human judgment adjacent findings** (multiple valid resolutions, missing context, or low confidence):

| # | Lens | File:Line | Finding | Why ambiguous | Confidence | Validation passes | Options |
|---|---|---|---|---|---|---|---|

No `Draft comment` column on any of the three: adjacent findings are surfaced for the user to decide on, not posted as standalone PR comments. If the user chooses to address one, fold the change into this iteration's commit. In `/copilot-pairing`, the auto-execution invariant prevents auto-fixing adjacent findings; they are only surfaced for human review.

### 6. Address items: solution validated with two or three test angles

Follow the standard review workflow (let me choose: all at once, one by one, batched decisions, or clustered decisions, with progress tracking). Option sets are derived from each thread's bucket per CLAUDE.md `Finding Categorization` (applies to both the main Copilot-thread table and the adjacent findings):

- **Auto-applicable**: apply the mechanical fix; the reply is the terse "Done in `<sha>`" template.
- **Needs sign-off**: `Apply / Skip / Modify` in batched mode (Apply lands the fix + posts the drafted reply; Skip drops the thread; Modify adjusts before landing); `Apply all / Skip all / Pick individually` in clustered mode.
- **Needs human judgment**: bespoke options per thread (the actual response branches; generic timing options are forbidden); cluster-wide options reflect the shared axis when clustering applies.

The classification column from the main table (`valid` / `false positive` / `low-confidence` / `adjacent finding`) drives where a thread lands: `valid` items with a clear fix go to Needs sign-off (or Auto-applicable when the fix is mechanical and tool-grounded), `false positive` to Needs sign-off (dismissal reply requires approval), `low-confidence` to Needs human judgment.

For **valid** items that affect runtime behavior, apply the canonical rigor in CLAUDE.md `Validation Rigor (Solutions)`:

1. **Targeted test.** Write a test that demonstrates the bug. Run it and confirm it fails for the expected reason (not for an unrelated reason like a missing import). Apply the fix. Re-run the test and confirm it now passes.
2. **Wider check.** Run the broader project test suite, linters, and type-checkers. Watch for regressions, including in code paths the fix did not directly touch.
3. **Edge / integration / manual** (when relevant). Boundary cases (null, empty, max size, concurrency), an integration or smoke test, or manual exercise of the user-facing flow.

"When applicable" means: skip targeted-test for non-behavioral changes (doc-only fixes, comment changes, pure renames, type-only adjustments, formatting). For those, substitute review angles per the canonical doctrine: re-read the diff, read it from each caller's perspective, grep for places the change could silently break. Note in the reply why no test was added.

For **false positives**: prepare a brief dismissal comment explaining what we checked (cite the three passes) and why the concern does not apply.
For **low-confidence**: pause and ask me before taking action.

### 7. Commit and push

After all items are addressed, commit the changes and push.

**If the push fails on a hook (pre-push test, security check, lefthook stage, etc.):** diagnose whether the failure is caused by this branch's diff or by something pre-existing / unrelated (a flaky test, a broken main, a security check tripping on untouched code). Surface the diagnosis to me and ask whether to (a) investigate and fix in-scope, or (b) hold off pushing. Do not silently retry, **never** bypass with `--no-verify` (the repo policy in `.github/copilot-instructions.md:122-123` forbids it), and do not "fix" unrelated test flakes inside this branch without checking first.

### 8. Reply to and resolve each thread

**Use `addPullRequestReviewThreadReply` only.** Do **NOT** use `addPullRequestReviewComment` (with or without `inReplyTo`) for this workflow.

Both mutations can leave replies invisible by attaching them to a *pending* review owned by the viewer:

- `addPullRequestReviewComment` always builds onto a review and creates a pending one if none is in progress. This has bitten this skill before; replies sat as drafts until someone manually clicked Submit.
- `addPullRequestReviewThreadReply` is the more direct mutation, but per a 2026-05-02 live-run failure on `SymmetrySoftware/stl-poc#13` it can also auto-vivify a pending review when the viewer has none in progress. The reply then stays invisible (to the GitHub UI, to Copilot, to humans) until the pending review is submitted.

After the batch of replies, **always** submit any pending review you own on this PR before resolving threads (see "Submit any auto-vivified pending review" below). A successful-looking run can otherwise complete with all replies silently invisible.

**Shell quoting rules:**
- Always use multi-line query strings for GraphQL mutations. Single-line strings cause the shell to eat `$` in variable names like `$threadId`.
- Construct the response body as an inline single-quoted bash heredoc inside the same `Bash` invocation that runs the GraphQL mutation. The single-quoted delimiter (`<<'EOF'`) keeps backticks, `$variables`, and other shell metacharacters literal, so the body is safe to embed without escaping. The previously-suggested temp-file pattern (`printf` to `/tmp/...` then `-F body=@file` in a separate `Bash` call) has been observed to trip harness permission denials with the rationale "body content is unverifiable" because the harness can flag chained file-write-then-public-post sequences as suspicious. Inline heredoc keeps body construction and posting in a single tool invocation. Fall back to a temp file only when the body is genuinely too large to inline (rare).

For each thread, run the reply mutation. After the whole batch of replies, run the pending-review submit step **once**, then run the resolve mutation per thread.

**Reply to the thread** (use the thread `id` from step 3, not the comment id):

```bash
body=$(cat <<'EOF'
RESPONSE_BODY (multi-line ok; backticks and $vars stay literal)
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
' -f threadId='THREAD_ID' -f body="$body"
```

**Submit any auto-vivified pending review** (run once after all replies are posted, before resolving):

Query the PR's pending reviews and the viewer's login in one round-trip, then submit each pending review owned by the viewer:

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $number: Int!) {
    viewer { login }
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
        reviews(states: PENDING, first: 10) {
          nodes { id author { login } }
        }
      }
    }
  }
' -f owner='OWNER' -f repo='REPO' -F number=NUMBER
```

For each `reviews.nodes` entry where `author.login == viewer.login`:

```bash
gh api graphql -f query='
  mutation($id: ID!) {
    submitPullRequestReview(input: {
      pullRequestReviewId: $id,
      event: COMMENT
    }) {
      pullRequestReview { id state submittedAt }
    }
  }
' -f id='REVIEW_ID'
```

Re-run the pending-reviews query and assert no pending reviews owned by the viewer remain. If a pending review cannot be submitted, stop and surface the error rather than silently resolving threads on top of invisible replies.

**Resolve the thread:**

```bash
gh api graphql -f query='
  mutation($threadId: ID!) {
    resolveReviewThread(input: {
      threadId: $threadId
    }) {
      thread { isResolved }
    }
  }
' -f threadId='THREAD_ID'
```

## Maintenance

After completing the workflow, check if any part of these instructions seem outdated, incorrect, or misaligned with the current project's tooling or workflow (e.g., GraphQL schema changes, deprecated fields, new `gh` CLI capabilities, Copilot bot login changes). If something looks off, flag it and offer a ready-to-use prompt I can paste into a new dotfiles session to update this command.

$ARGUMENTS
