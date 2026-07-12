# Untagged-window lock template (opt-in)

An adopter-facing mechanism template: a GitHub Actions workflow that **locks the
untagged window** — the gap between a release PR merging (a version bump lands on
your default branch) and the signed tag being published. While that window is
open, the check fails, and with require-branches-up-to-date it blocks every
merge until you publish. Forgetting to publish becomes structurally impossible
rather than merely discouraged (autopilot-reflex step 4: surface by
forcing-function, never by pull; D-7, REQ-E1.1).

It is the release-side complement to the
[`release-please`](../release-please/README.md) PR-only template: that one
proposes the release, this one makes the follow-through unforgettable.

This template is **opt-in**. It lives under `templates/` so planwright never
auto-lands a workflow in your repository (the customization-boundary rule:
capability ships in core, mechanism ships as templates you consent to, value is
configuration). Nothing here runs until you copy it in.

## What you get

- A required status check that is **red while a release is pending** (your
  version of truth is ahead of the latest release tag) and **green otherwise**.
- After a release PR merges, the check goes red on the default branch, so no
  further merge lands until the tag is published — the block message names your
  publish command so the fix is one command away.
- Ordinary PRs that do not bump the version are unaffected outside the window
  (REQ-E1.2).

## Why it reads the base branch, not the PR head

The lock is a property of your **default branch**, so the workflow evaluates
that branch's state, never the PR head. On a `pull_request` or `merge_group` it
checks out the **base** branch.

This is deliberate. If the check read the PR head instead, the **release PR
itself** — which bumps the version — would trip the lock and could never merge:
the signed tag can only exist *after* the bump lands, so requiring the tag on
the release PR is an unsolvable chicken-and-egg. Base-reading lets the release
PR through (the base is still at the tag when it merges) while blocking every
*subsequent* merge once the bump has landed. That is exactly the serialization
you want: the release PR opens the window, the publish closes it, nothing else
slips in between.

## Files

| File | Copy to | Purpose |
| --- | --- | --- |
| `release-window.yml` | `.github/workflows/release-window.yml` | The window-lock check. |

The check step calls `scripts/release-window-check.sh`, which planwright core
ships (it reuses `scripts/release-pending.sh`, the one shared definition of
"pending"). **Adopting without planwright core?** Supply your own comparator
that exits non-zero while your version of truth is ahead of the latest release
tag and names your publish command, and point the final `run:` step at it.

## Adopting

1. Copy `release-window.yml` to `.github/workflows/release-window.yml`.
2. In the workflow, set `push.branches` to your default branch if it is not
   `main`. Keep the `actions/checkout` pin at a full commit SHA and bump the
   `# vX.Y.Z` comment alongside it.
3. If you are not using planwright core, replace the final `run:` step with your
   own comparator (see above).
4. **Make the check required, but only once the window is closed.** In branch
   protection for your default branch, add the workflow's status check
   (`release-window / window-lock`) to the required checks. Enabling it *while a
   release is pending* turns the branch red instantly and blocks all merges, so
   flip it to required only when your version of truth already equals the latest
   tag (nothing pending). Publish any open release first, then require the
   check.

## Is a merge queue proportionate for you?

`require-branches-up-to-date` is the **minimum** serialization: it forces every
PR to include the latest default-branch commits before merging, so a PR opened
before the release bump must re-sync (and re-run the check, going red) once the
window is open. For most repositories that is enough — it closes the common case
without any queue.

Add a **GitHub merge queue** on top only when your **merge concurrency** makes
the re-sync race real: multiple PRs merging close together can each pass the
check against a stale pre-bump base and land before the window-open state
propagates. A merge queue serializes the final merge + check, removing that
race. Scale the mechanism to your traffic:

- **Low concurrency** (occasional merges, one or two contributors): require the
  check with `require-branches-up-to-date`. A merge queue is overkill.
- **High concurrency** (frequent back-to-back merges, several active
  contributors or automated towers): add the merge queue so concurrent merges
  cannot race the release PR.

Publishing promptly after the release PR merges is the real mitigation either
way — the shorter the untagged window, the less the lock can block unrelated
work.

## Invariants this template preserves

- **The lock never makes tagging correct** — it only closes the forget-window.
  Publish correctness comes from the publish step tagging the observed
  release-merge commit under any merge interleaving (REQ-E1.4); the lock is
  belt, not suspenders.
- **No secrets, least privilege.** The check reads git and a file only —
  `contents: read`, no `gh`, no signing material in CI.
