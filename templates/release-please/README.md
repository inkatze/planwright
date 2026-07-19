# release-please PR-only template (opt-in)

An adopter-facing mechanism template: a GitHub Actions workflow that runs
[release-please](https://github.com/googleapis/release-please) in **PR-only
mode**. It maintains a standing release PR from your conventional commits and
**never creates a tag or a GitHub Release** — tagging is done by a separate,
human-gated, signed publish step, never by CI.

**The publish step is not part of this template.** planwright core ships one
(`scripts/release-publish.sh`) that signs and pushes the annotated tag. If you
adopt this workflow **without** planwright core, you must supply your own
signed-tag publish step and name it wherever this template says
`scripts/release-publish.sh` (the workflow header and the config's PR body).
The template gets you the proposal PR; the signed publish is yours to wire. If
you go this route, note the relabel obligation under "Publish-time obligations
and caveats" below: a bring-your-own-publish path must relabel the merged
release PR by hand, or release-please deadlocks on the next cycle.

This template is **opt-in**. It lives under `templates/` so planwright never
auto-lands a workflow in your repository (the customization-boundary rule:
capability ships in core, mechanism ships as templates you consent to, value
is configuration). Nothing here runs until you copy it in.

## What you get

- One standing release PR that is the detection surface (it appears when
  releasable commits land), the correction surface (edit it), the cancellation
  surface (close it), and the approval gate (**merging it is the release
  approval, and stays a human act**).
- A version bump to your version source of truth and an updated `CHANGELOG.md`.
- A PR body that states the full flow — merge approves the release, then run
  the publish command to sign and publish the tag — with the notes preview,
  so approval and publish read as one adjacent act.

## Files

| File | Copy to | Purpose |
| --- | --- | --- |
| `release-please.yml` | `.github/workflows/release-please.yml` | The PR-only workflow. |
| `release-please-config.json` | repo root (or your `config-file` path) | Version target, changelog path, PR body. |
| `.release-please-manifest.json` | repo root (or your `manifest-file` path) | Records your last released version. |

## Adopting

1. Copy the three files to the destinations above.
2. In `release-please-config.json`, point `extra-files` at **your** version
   source of truth and set `changelog-path`. **The shipped default targets
   `.claude-plugin/plugin.json` `$.version`, which is planwright-specific** —
   leave it unchanged only if your repo actually has that file; otherwise
   change the `path`/`jsonpath` to your own `version_file` (e.g.
   `package.json` `$.version`), or release-please will try to bump a file you
   do not have.
3. Seed `.release-please-manifest.json` with your last released version (use
   `0.0.0` for a fresh project with no prior release). **Migrating from
   hand-made tags?** Also set `"bootstrap-sha": "<commit of your last release>"`
   at the top level of `release-please-config.json`. Without it, the first
   release PR can dump your entire commit history into the changelog because
   release-please cannot find a prior release-please release to anchor on.
   `bootstrap-sha` is used only on the first run and ignored afterward.
4. In the workflow, replace `ci` with the name of your CI workflow so the
   proposal is gated on CI success. Keep the action pinned to a full commit
   SHA and bump the `# vX.Y.Z` comment alongside it.
5. Confirm the token posture: the default `GITHUB_TOKEN` with `contents:
   write` and `pull-requests: write` is sufficient. No PAT or stored secret is
   needed. The one exception is making the `ci` check a *required* status check
   on the release PR — see "Do not make `ci` a required check on the release
   PR" below before you do.

## Publish-time obligations and caveats

Read these before your first publish. Each is a foot-gun the happy-path
walkthrough above does not surface on its own.

### Relabel the merged release PR (bring-your-own-publish only)

If you supply your own publish step instead of planwright core's
`scripts/release-publish.sh`, you must also relabel the merged release PR from
`autorelease: pending` to `autorelease: tagged` once you have tagged. That is
the bookkeeping release-please's skipped github-release step would have done for
you; release-please's own publish path does it, and planwright core's
`release-publish.sh` does it too, so **only** the bring-your-own-publish path
has to do it by hand. Skip it and release-please aborts the **next** cycle's
release PR with "untagged, merged release PRs outstanding" — the documented path
works for cycle 1 and deadlocks on cycle 2.

### The publish CI gate refuses a no-CI repo by default

planwright core's `scripts/release-publish.sh` gates publishing on CI: it reads
the release commit's `statusCheckRollup`, and its **strict default treats a null
rollup (no checks at all) as not-green and refuses**. If your repo runs no CI on
the release commit, the publish step will not tag. Two ways forward:

- Add a CI workflow (this template's `ci` gate is the natural one), so the
  release commit carries a green check; or
- Set the core `require_ci` knob to `false` to relax **only** the
  "no positive CI confirmation" verdict. It weakens no other gate: a genuinely
  failing or still-pending check still refuses. When it does publish on a no-CI
  rollup it emits a stderr note recording that it published without positive CI
  confirmation (`require_ci=false`), so the relaxation stays auditable.

This obligation applies only if you publish with planwright core's script; a
bring-your-own publish step gates however you wrote it.

### Do not make `ci` a required check on the release PR

It is tempting to make the `ci` status check **required** on the release PR via
branch protection. Do not — unless you first change the token posture. A release
PR authored by the default `GITHUB_TOKEN` raises no `pull_request`/`push`
workflow run (GitHub suppresses workflow triggers on token-authored events to
prevent recursion), so a required `ci` check never reports and the PR can never
satisfy it: a deadlock. (In this repository the finding is dormant — there is no
required status check on the release PR, verified via `gh api`.)

To make `ci` required on the release PR, first apply a CI-triggering token fix:
author the release PR with a Personal Access Token or a GitHub App token (whose
pushes **do** trigger `pull_request`/`push` workflows) via release-please's
`token:` input, instead of the default `GITHUB_TOKEN`. With that in place the
check runs and the requirement becomes satisfiable.

## Invariants this template preserves

- **CI never tags.** `skip-github-release: true` keeps release-please to the
  proposal PR. The signed tag comes only from the human-gated publish step.
- **Merge is the human's.** No path in this template merges the release PR.
- **Least privilege, no secrets.** Default `GITHUB_TOKEN`, two scopes.
