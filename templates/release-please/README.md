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
The template gets you the proposal PR; the signed publish is yours to wire.

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
   `0.0.0` for a fresh project with no prior release).
4. In the workflow, replace `ci` with the name of your CI workflow so the
   proposal is gated on CI success. Keep the action pinned to a full commit
   SHA and bump the `# vX.Y.Z` comment alongside it.
5. Confirm the token posture: the default `GITHUB_TOKEN` with `contents:
   write` and `pull-requests: write` is sufficient. No PAT or stored secret is
   needed.

## Invariants this template preserves

- **CI never tags.** `skip-github-release: true` keeps release-please to the
  proposal PR. The signed tag comes only from the human-gated publish step.
- **Merge is the human's.** No path in this template merges the release PR.
- **Least privilege, no secrets.** Default `GITHUB_TOKEN`, two scopes.
