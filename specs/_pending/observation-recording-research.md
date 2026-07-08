# Synthesis: conflict-free accumulation into a shared file on a protected `main`

Status: COMPLETE — all five research tracks reported and folded in; every per-tool section
verified against primary sources (docs + source code + issue trackers). (Session: fable,
2026-07-07.)

## 0. Verified platform facts (foundation for everything below)

**F1. GitHub's server-side PR merge ignores user `.gitattributes` merge drivers, including
`merge=union`.** Long-standing, still-open feature request:
[community discussion #9288](https://github.com/orgs/community/discussions/9288). Kubernetes
removed its union driver for the changelog for exactly this reason:
[kubernetes/kubernetes#70576](https://github.com/kubernetes/kubernetes/pull/70576)
("gitattributes: remove the union merge driver since GitHub doesn't support it"). GitLab DOES
honor union merge (via rugged/libgit2); GitHub does not. Consequence: any design where two
concurrent PRs both edit the shared file WILL hit manual-rebase conflicts on GitHub, no
gitattributes escape hatch. The brief's premise is confirmed.

**F2. Bot-opened PRs and the `GITHUB_TOKEN` trigger rule.** When a workflow creates or updates
a PR using the repo-scoped `GITHUB_TOKEN`, the resulting `pull_request` workflow runs are held
in an approval-required state (historically: not created at all) — deliberate recursive-workflow
prevention. To get CI to run automatically on a bot-opened PR you use a GitHub App installation
token or a PAT. Sources:
[Triggering a workflow — GitHub Docs](https://docs.github.com/actions/using-workflows/triggering-a-workflow),
[community discussion #65321](https://github.com/orgs/community/discussions/65321),
[peter-evans/create-pull-request concepts doc](https://github.com/peter-evans/create-pull-request/blob/main/docs/concepts-guidelines.md).
This is the main *operational* catch of the reconcile-PR pattern, and it is well-trodden with a
documented fix.

**F3. planwright ground truth (read from the repo, 2026-07-07).**
- `specs/_observations/opportunities.md` + `archive.md` exist; entries are one-line bullets
  `- <date> [scope] <text>` with NO stable IDs — identity today is exact text match.
- `.github/workflows/` contains only `ci.yml` (the `mise run check` aggregate gate).
  **No release-please workflow is wired yet**: the autopilot-reflex spec (kickoff merged
  2026-07-03, PR #107) prescribes release-please in PR-only mode, but the first release /
  workflow wiring is still pending. So the "already in-house" pattern is in-house *on paper*
  (spec'd, doctrine-approved), not yet in CI.

## 1. The dominant pattern + variants (VERIFIED)

Every tool that survives contact with a protected main converges on one invariant:
**contributors never write the shared compiled file; each contribution is an add-only unit
(fragment file or commit message) with a collision-free name; at most ONE serial writer ever
touches the compiled file.** The variants differ only in who that writer is and whether the
compiled file is committed at all:

- **Variant 1 — fragment files + single-writer reconcile PR** (Changesets, knope,
  towncrier-as-pytest-uses-it): fragments in a directory (`.changeset/`, `changelog.d/`); a bot
  (or human-triggered workflow) compiles them into the shared file AND deletes the consumed
  fragments in the SAME PR, which a human merges. The reconcile branch is canonical (one per
  target branch) and force-regenerated from main's tip on every trigger — regenerate, never
  repair.
- **Variant 2 — commit messages as fragments + reconcile PR** (release-please): the per-change
  data rides in commit metadata, unconflictable by construction; otherwise identical PR
  mechanics.
- **Variant 3 — no committed compiled file at all** (reno; git-cliff's full-regeneration mode
  is the degenerate cousin): the compiled view is a BUILD ARTIFACT rendered on demand from the
  fragments (+ git history). The consolidation-to-protected-main problem is dissolved rather
  than solved, and — uniquely — later EDIT and DELETE of old entries become conflict-free
  single-file operations too.
- **Anti-variant — direct push with protection bypass** (semantic-release, default auto):
  requires elevating a bot above the branch rules; semantic-release's own docs call the
  workaround a security risk and recommend not committing the changelog at all.

**On the hardest sub-question (removing/editing OLD entries in the compiled file):** NO tool
supports pruning/editing old entries in a *committed* compiled file across concurrent
contributors. Variant 1/2 compiled files are append-forever; the only deletion any of them do
is of FRAGMENT files, inside the serial writer's own PR. The one system where old-entry
removal/edit is a designed, conflict-free, identity-stable operation is reno — and it achieves
that precisely by NOT committing a compiled file: the entry's single source of truth stays its
own per-entry file forever, so editing/removing it is the same single-file operation as adding
it. That is the load-bearing move, and the direct answer to planwright's archive-on-consume
problem.

## 2. Per-tool findings

(table to be finalized once all agent reports are in; verified per-tool sections below)

### release-please (VERIFIED against source + docs)

Primary sources: [README](https://github.com/googleapis/release-please/blob/main/README.md),
[docs/design.md](https://github.com/googleapis/release-please/blob/main/docs/design.md),
[docs/manifest-releaser.md](https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md),
[src/manifest.ts](https://github.com/googleapis/release-please/blob/main/src/manifest.ts),
[src/updaters/changelog.ts](https://github.com/googleapis/release-please/blob/main/src/updaters/changelog.ts),
[release-please-action README](https://github.com/googleapis/release-please-action/blob/main/README.md).

- **(a) Concurrency:** entries are conventional-commit MESSAGES, not files — conflict-free by
  construction (commit metadata; no shared file touched by feature PRs). CHANGELOG.md is pure
  output, materialized only inside the bot's release PR.
- **(b) Consolidation under protection:** runs on push to main; maintains exactly ONE release PR
  per target branch, head branch `release-please--branches--main`. The branch is **regenerated
  from main's tip and force-pushed on every run** (code-suggester `force: true`; "This will
  force-push to that branch" in src/github.ts). One-open-PR invariant enforced by head-branch-name
  equality in `createOrUpdatePullRequest()`. Feature PRs merging while the release PR is open are
  the DESIGNED case, not a race: each merge retriggers the workflow, which recomputes
  commits-since-last-release from scratch and force-rebuilds the PR ("Release PRs are kept
  up-to-date as additional work is merged"). Never pushes to main; has NO merge capability at all
  — the human merge IS the release trigger, detected afterwards by label (`autorelease: pending` →
  `tagged`) + merge-commit SHA. Squash-merge is "highly recommended" (one PR = one commit = one
  entry) and label-based detection is merge-method-agnostic. Token catch: with default
  `GITHUB_TOKEN` the release PR gets no CI runs; README prescribes a PAT/App token.
- **(c) Prune:** none. CHANGELOG.md is prepend-only — `src/updaters/changelog.ts updateContent()`
  splices the new entry above the first existing version header; old entries never touched.
  Within an open release PR's lifetime the *pending* entry is rewritten wholesale (branch
  force-rebuilt); merged history is immutable.
- **(d) Identity:** layered anchors, none per-entry: the release TAG/GitHub Release ("find the
  SHA of the latest released version"), the `autorelease:*` labels, and
  `.release-please-manifest.json` (versions per path, read at the LAST MERGED RELEASE PR's commit,
  not HEAD — that pinning is what makes the manifest race-free). `bootstrap-sha` /
  `last-release-sha` are bootstrap/manual-recovery anchors.
- **Design property worth copying:** recovery model is *regeneration, not repair* — every run
  recomputes the full desired PR state from durable inputs and force-pushes; the bot branch is
  derived state, safe to blow away.

### Changesets + changesets/action (VERIFIED against source + docs + issue tracker)

Primary sources: [packages/write/src/index.ts](https://github.com/changesets/changesets/blob/main/packages/write/src/index.ts),
[docs/common-questions.md](https://github.com/changesets/changesets/blob/main/docs/common-questions.md),
[packages/apply-release-plan/src/index.ts](https://github.com/changesets/changesets/blob/main/packages/apply-release-plan/src/index.ts),
[changesets/action README + src](https://github.com/changesets/action/blob/main/src/run.ts),
issues [#263](https://github.com/changesets/action/issues/263), [#455](https://github.com/changesets/action/issues/455),
[#523](https://github.com/changesets/action/issues/523), [#70](https://github.com/changesets/action/issues/70).

- **(a) Concurrency:** one fragment file per change, `.changeset/<random-name>.md`. Names from
  the `human-id` package (adjective-noun-verb, e.g. `tidy-lions-shave`, ~15M pool). Source
  comment: "the ID merely needs to be a unique hash to avoid git conflicts." NO collision check
  (`fs.writeFile` would silently overwrite); the design leans on pool size + fragments being
  consumed frequently so the live population stays small. Docs: "no harm will come from renaming
  them" — the filename is a pure conflict-avoidance token with zero semantic weight.
- **(b) Consolidation under protection:** action runs on push to main; single well-known branch
  `changeset-release/main`; every run `git reset --hard` to the triggering commit on main,
  re-runs `changeset version`, commits, `push --force`; create-or-update of ONE canonical PR
  (matched by head branch). Maintainer on why non-force-push is infeasible (#455): the branch has
  no durable history of its own; state lives entirely in the fragments on main. **Race handling
  is workflow-level serialization, not app-level locking**: README workflows include
  `concurrency: ${{ github.workflow }}-${{ github.ref }}`; issue #263 (maintainer): "use the
  `concurrency` setting ... and queue all Changeset workflows"; skipping non-HEAD commits was
  rejected because it "could lead to a stale Version Packages PR being merged." Self-healing:
  a stale force-push is corrected by the next push to main; residual risk = human merges a stale
  Version PR before the next regeneration. Never touches main directly, never auto-merges —
  human merges the Version PR. Branch protection pain point = CI on the bot PR: with
  `GITHUB_TOKEN` the Version PR gets no workflow runs, so required checks never pass (#523, #70);
  fix = PAT or GitHub App token via the `github-token` input. Also: don't put `[skip ci]` in the
  version commit (#198 — kills the post-merge publish workflow).
- **(c) Prune:** `changeset version` "will read then delete changesets on disk, ensuring that
  they are only used once" (CLI README); implementation `fs.rm(changesetPath)` per consumed
  fragment. So the Version PR's diff = bump manifests + prepend CHANGELOG + DELETE consumed
  fragments: **consumption and compilation are atomic at merge time, inside the same
  human-merged PR**. Structurally conflict-free vs. open feature branches (they add different
  files). A fragment merged to main after the Version PR opened → next trigger rebuilds the PR
  over the larger fragment set.
- **(d) Identity:** fragment filename only, and it's disposable; the ID does NOT survive into
  CHANGELOG.md (compiled entries carry only summary text + short commit hash / PR link).
  CHANGELOG.md is prepend-only; no mechanism to edit/remove old compiled entries —
  "append-forever," retroactive edits outside the model.

### towncrier + scriv (VERIFIED against docs + source + real projects)

Primary sources: [towncrier tutorial](https://towncrier.readthedocs.io/en/stable/tutorial.html),
[CLI](https://towncrier.readthedocs.io/en/stable/cli.html),
[configuration](https://towncrier.readthedocs.io/en/stable/configuration.html),
[scriv commands](https://scriv.readthedocs.io/en/latest/commands.html),
[scriv source](https://raw.githubusercontent.com/nedbat/scriv/master/src/scriv/scriv.py),
[pytest prepare-release-pr.py](https://github.com/pytest-dev/pytest/blob/main/scripts/prepare-release-pr.py),
[pip release process](https://pip.pypa.io/en/latest/development/release-process/),
[attrs contributing](https://www.attrs.org/en/latest/contributing.html),
[plone.releaser #17](https://github.com/plone/plone.releaser/issues/17).

- **(a) Concurrency:** towncrier fragments are `<issue>.<type>(.<counter>)` — identity is the
  issue/PR number (unique per PR by construction); on same-name collision `towncrier create`
  increments a counter until the filename is free. No-issue entries use `+`-prefixed "orphan"
  fragments; `towncrier create +` generates a random hash suffix. attrs deliberately exploits
  filename identity: same-content fragments under multiple issue numbers merge into one entry
  with multiple links. scriv fragments are `YYYYMMDD_HHMMSS_user_branch.rst` (configurable
  `fragment_name_fields`); collision-safe probabilistically (no exists-check in source).
- **(b) Consolidation:** `towncrier build` inserts rendered news at the `start_string` marker,
  `git rm`s consumed fragments, stages, leaves the commit to the operator; `--yes` for
  automation. No official build action. **Real-world reference implementations:**
  - **pytest = the bot-opened, human-merged release PR** (closest match to planwright's model):
    human triggers the `prepare-release-pr` workflow → script creates `release-X.Y.Z` branch,
    runs towncrier, pushes, opens a DRAFT PR via `gh pr create`; humans approve/merge, then a
    human triggers deploy.
  - **pip = release-manager-direct-push variant**: `nox -s prepare-release` runs
    `towncrier build --yes` with an interactive "review the NEWS file" pause; RM commits and
    pushes directly.
  - `towncrier check` (enforce fragment-per-PR) auto-skips "when the main news file is modified
    inside the branch as this signals a release branch" — the documented release-PR affordance.
- **(c) Prune:** both delete consumed fragments at build/collect time (opt-out `--keep`).
  Release commit vs in-flight fragment PRs: no path overlap (deletes old files + edits compiled
  file vs adds a new uniquely-named file) → no conflict. Squash-merge does NOT resurrect
  deleted fragments (a squash applies only the PR's own diff). No documented squash gotcha found.
- **(d) Identity:** towncrier's issue number SURVIVES into the compiled output (rendered per
  `issue_format`, e.g. `#1234` links) — the strongest fragment→compiled identity carry-through
  of the file-based tools. Orphan random suffixes do NOT appear in output. scriv's filename is
  ordering metadata only; compiled identity is just the text. Both treat the compiled file as
  frozen history: no command edits/removes an already-built entry; post-build edits are ordinary
  hand edits (safe only because fragment PRs never touch the compiled file).
- **Why fragments beat union merge (community evidence, plone.releaser #17):** union merge
  trades visible conflicts for SILENT MISPLACEMENT — "too often a PR has an entry for
  CHANGES.rst, it gets merged, and the entry ends up under the wrong version header, or under
  bug fixes instead of new features, or in the middle of a different entry."
- towncrier philosophy: "Rather than reading the Git history, or having one single file which
  developers all write to and produce merge conflicts, towncrier reads 'news fragments'..."

### semantic-release / git-cliff / knope / auto (VERIFIED against docs + issues)

Primary sources: [semantic-release CI docs](https://semantic-release.gitbook.io/semantic-release/usage/ci-configuration),
[FAQ](https://semantic-release.gitbook.io/semantic-release/support/faq),
[@semantic-release/git](https://github.com/semantic-release/git),
[git-cliff docs](https://git-cliff.org/docs/), [git-cliff-action](https://github.com/orhun/git-cliff-action),
[knope release-PR recipe](https://knope.tech/recipes/1-preview-releases-with-pull-requests/),
[knope PrepareRelease](https://knope.tech/reference/config-file/steps/prepare-release/),
[auto shipit](https://intuit.github.io/auto/docs/generated/shipit),
[@auto-it/protected-branch](https://github.com/intuit/auto/blob/main/plugins/protected-branch/README.md),
[intuit/auto#945](https://github.com/intuit/auto/issues/945).

- **semantic-release: the anti-pattern for this repo's constraints.** Direct-push model (tags
  always; changelog commits via `@semantic-release/git`, which requires the bot to "push commit
  to the release branch"). Docs explicitly say protected branches need the release user to
  BYPASS restrictions (uncheck "Include administrators", use an admin user), the FAQ warns this
  elevates access "beyond what would otherwise be desired/considered secure", and the GitHub
  Actions recipe says overriding `GITHUB_TOKEN` with a PAT "poses a security risk". Their own
  recommendation: don't commit the changelog at all (GitHub Releases only). Under a strict
  no-bypass, human-merges-everything policy, semantic-release's compiled-file path is unusable
  as documented. Entries = commit messages; prepend-only; no prune/identity.
- **git-cliff: a pure generator, protection-agnostic; the interesting identity model.** No
  built-in write path (the action's README example is a manual direct push, but outputs compose
  with PR actions). Distinctive property: full-regeneration mode — `git cliff -o CHANGELOG.md`
  rebuilds the ENTIRE file from git history × config each run, idempotently. **The compiled file
  is a pure function of history; the commit hash is the entry identity; "editing/pruning old
  entries" = change config (`commit_parsers` with `skip = true`) or filters and regenerate.**
  Hand edits are overwritten (unsupported in this mode); `--prepend` preserves them but gives up
  the pure-function property. Full regeneration dissolves the consolidation problem in
  principle (rebuild anywhere), at the cost of forbidding hand curation.
- **knope: the strongest PR-native match.** Documented primary workflow: on push to main, CI
  runs `PrepareRelease` (bumps versions, adds CHANGELOG section, **deletes consumed changesets**)
  on a side branch (`release` / bot: `knope/release`) and opens a PR; **the human merge of that
  PR is the release trigger**. Needs no protection bypass by design. Sources entries from BOTH
  conventional commits AND `.changeset` fragment files. Old sections inert after merge.
- **auto: PR-shaped escape hatch but bot-merged — violates never-auto-merge.** Default
  `auto shipit` pushes changelog+version directly to base (fails GH006 under protection,
  #945). The `@auto-it/protected-branch` plugin creates a temp branch → opens PR → **approves it
  with a second bot PAT and auto-merges it**. PR-only compatible, human-merge INCOMPATIBLE.
  Useful as the boundary case: "PR-based" alone is not the property planwright needs;
  "human-merged" is a separate axis.

### reno (VERIFIED against source + design docs — the strongest prior art for the hardest question)

Primary sources: [design.rst](https://docs.openstack.org/reno/latest/user/design.html),
[usage](https://docs.openstack.org/reno/latest/user/usage.html),
[scanner.py](https://opendev.org/openstack/reno/raw/branch/master/reno/scanner.py),
[create.py](https://opendev.org/openstack/reno/raw/branch/master/reno/create.py),
[utils.py](https://opendev.org/openstack/reno/raw/branch/master/reno/utils.py),
[OpenStack project-team-guide](https://docs.openstack.org/project-team-guide/release-management.html).

- **(a) Concurrency:** one YAML file per note, `releasenotes/notes/<slug>-<16-hex-random>.yaml`.
  UID = 8 random bytes hexlified (`os.urandom`), local-uniqueness check only (50-try
  `os.path.exists` loop); cross-contributor collision left to 64-bit randomness. Front page:
  "Reno stores each release note in a separate file to enable a large number of developers to
  work on multiple patches simultaneously, all targeting the same branch, without worrying about
  merge conflicts." Design constraint: authors "shouldn't need to know any special values for
  naming their notes files (i.e., no change id or SHA value that has special meaning)" — paired
  with "easy to identify the file... on a particular topic": that pair IS the slug+UID split.
- **(b) Consolidation: THERE IS NO COMMITTED COMPILED FILE AT ALL.** The rendered notes are a
  build artifact: the Sphinx `release-notes` directive (or `reno report`) scans git history at
  docs-build time. The consolidation-to-protected-main problem is dissolved, not solved.
  Cost: rendering needs full unshallowed history + tags; assumes trunk-based branching.
- **(c) Prune/edit of OLD entries — supported, conflict-free, by design.** The scanner keys
  everything on the filename UID (`_get_unique_id` takes the last 16 chars):
  - **Edit later** → the note renders under its ORIGINAL version with the content of its LATEST
    edit (scan runs newest→oldest: `last_name_by_id` fixed by most recent change,
    `earliest_seen` walks back to the add-commit). "Notes are mutable in that a clone today vs
    a clone tomorrow might have different release notes about the same change"; "Notes are
    immutable in that for a given git hash/tag the release notes will be the same."
  - **Delete later** → the note vanishes from ALL rendered history including its original
    version (`uniqueids_deleted` short-circuits add/modify). Explicit design constraint:
    **"We must be able to entirely remove a release note."**
  - **Rename/move** → identity-preserving via UID (add+delete of same UID = rename).
  - Sharp edge: edits must land on the note's original branch, else the note jumps to the later
    branch's render; escape hatch `ignore-notes`, itself keyed by filename/UID. (Irrelevant for
    a single-main repo like planwright.)
  - No prune ritual exists or is needed: EOL'd branches are frozen as `foo-eol` tags
    (`closed_branch_tag_re`), note files stay in history forever; "We must not make things
    progressively slow down to a crawl over years of usage" is handled by scan-scoping config,
    not deletion.
- **(d) Identity:** the 16-hex random filename UID, durable across slug renames, moves, edits;
  the only identity in the system, and the anchor for every operation including the escape
  hatches.

### Summary table

| Tool | (a) Concurrency of new entries | (b) Consolidation under PR-only, human-merge, no-bypass main | (c) Prune of consumed entries | (d) Entry identity |
|---|---|---|---|---|
| **Changesets** | one fragment file per change, random human-id name (~15M pool, no collision check) | bot force-regenerates `changeset-release/main` + ONE canonical PR, human merges; needs PAT/App token for CI; workflow `concurrency` queues runs | fragments deleted inside the same Version PR (atomic with compile at merge) | filename only, disposable; does NOT survive into CHANGELOG |
| **release-please** | entries = conventional commit messages (no files) | bot force-regenerates `release-please--branches--main` + ONE canonical PR, human merge = release trigger; no merge capability at all | none — CHANGELOG prepend-only, old entries never touched | release tag + labels + manifest (pinned to last merged release PR's commit) |
| **towncrier** | `<issue>.<type>(.<counter>)`, `+`-orphans with random hash | no built-in writer; pytest = human-triggered workflow → draft release PR, human merges; pip = RM direct push | build `git rm`s consumed fragments (`--keep` to opt out); no conflict with in-flight adds | issue number — SURVIVES into compiled output as rendered links |
| **scriv** | `date_user_branch` filename (probabilistic) | no built-in writer; same wiring options | collect deletes fragments (`--keep`) | filename is ordering metadata only; compiled identity = text |
| **reno** | one YAML per note, slug + 16-hex random UID | N/A — no committed compiled file; rendered at build time from git history | delete the note FILE later → entry vanishes from all rendered history; edit → latest content under original version | **filename UID — durable, survives rename/move/edit, anchors everything** |
| **git-cliff** | commit messages | pure generator; compose into PR flow yourself | full-regeneration mode: compiled file = pure function of history × config; "prune" = config skip + regenerate (hand edits lost) | commit hash |
| **semantic-release** | commit messages | INCOMPATIBLE without admin bypass; docs recommend against committing changelog at all | none | none |
| **knope** | conventional commits AND `.changeset` fragments | first-class release PR, human merge = trigger; no bypass needed | deletes consumed changesets in the release PR | fragment filename (changesets-style) |
| **auto** | PR labels + commit messages | PR-shaped but bot-self-approved AUTO-merge — violates never-auto-merge | none | none |

## 3. Verdict on question 1 (reconcile PR to a never-auto-merge main)

**YES — verified across four independent implementations, with two instructive
counter-examples.**

The pattern "bot-opened, human-merged reconcile PR compiles the shared file; the bot never
touches main; the human merge is the state transition" is the standard, battle-tested answer:

1. **release-please**: no merge capability at all; single canonical branch
   `release-please--branches--main`, force-regenerated from main's tip on every push to main;
   one-open-PR invariant by head-branch-name match; merged-PR detection by label + squash-merge
   compatible.
2. **changesets/action**: identical shape (`changeset-release/main`, hard-reset + force-push
   per run, create-or-update one PR); consumed fragments DELETED inside the same PR;
   run-ordering races handled by workflow `concurrency` queueing (maintainer-endorsed, #263).
3. **knope**: the documented primary workflow is exactly this (side branch → PR → human merge
   triggers release), sourcing from both commits and changeset fragments.
4. **pytest** (towncrier in the wild): human-triggered workflow builds the changelog + deletes
   fragments on a `release-X.Y.Z` branch and opens a draft PR; humans approve, merge, then
   deploy.

Counter-examples that sharpen the verdict: **semantic-release** (direct-push model; docs
require a protection BYPASS and warn it's a security risk; their own advice is "don't commit
the changelog") and **intuit/auto** (protected-branch plugin is PR-shaped but bot-self-approves
and AUTO-MERGES — PR-only ≠ human-merged; planwright's never-auto-merge invariant is a separate,
stricter axis that release-please/changesets/knope satisfy and auto does not).

**The four operational requirements the working implementations share:**
1. ONE canonical bot branch per target branch, create-or-update matched by branch name — the
   serial-writer invariant lives in the branch name.
2. **Regenerate, don't repair**: every run rebuilds the branch from durable inputs on main
   (fragments / commit history) and force-pushes; the reconcile PR is disposable derived state,
   so concurrent feature merges just retrigger regeneration and staleness self-heals.
3. Workflow-level `concurrency` serialization (queue runs per ref) to prevent an older run's
   force-push landing after a newer one's; residual risk is a human merging a stale reconcile PR
   in the window before the next regeneration.
4. A GitHub App token or PAT (not `GITHUB_TOKEN`) so the bot PR gets CI runs and can satisfy
   required status checks (F2; changesets #523/#70; release-please README).

## 4. Recommendation for archive/prune + entry identity

### The fork: (A) reno model vs (B) release-please model

**(A) reno model.** Drop the committed compiled `opportunities.md` entirely. Observations live
as a directory of per-entry files (`specs/_observations/entries/<date>-<slug>-<8hex>.md`, one
one-line entry each, reno's slug+UID split with scriv's date prefix for `ls` chronology). The
"log" is a rendered view, generated on demand. Archive-on-consume = `git mv` the entry file to
`specs/_observations/archive/` (or delete it) — a single-file operation, conflict-free by the
same mechanism that makes adds conflict-free. Identity = the filename UID, minted once at
creation, durable across slug renames, edits, and the archive move.

**(B) release-please model.** Keep `opportunities.md` as an append-forever compiled file
written ONLY by a force-regenerated canonical reconcile PR that a human merges (PAT/App token
for CI if a GitHub Action opens it). "Consumed" is tracked at the fragment/marker level —
tombstone fragments or a consumed-ids ledger — never by pruning the compiled file.

### The deciding question: does planwright NEED a human-openable chronological log FILE?

**No — and the evidence is in who actually consumes it.** The log's consumers are:

1. **`/spec-draft` mining** — a skill that filters entries by target and cites them. A
   directory of per-entry files is *better* for this consumer: each entry carries its own
   provenance, is individually citable by filename (a stable citation the current line-format
   can't offer), and archive-on-consume becomes the atomic `git mv` the skill can do on its own
   spec branch without touching any shared file.
2. **`/drain`'s sweep** — reports the log's unmined state; globbing a directory is the same
   read.
3. **The human, occasionally** — reviewing what's accumulated. This is real but does not
   require a *committed compiled* file: `ls -t entries/` on one-line files, a `mise run
   obs:log` render task (cat in date order — ~5 lines of shell), or /drain's own report all
   serve it. git-cliff's model is the proof this is sound: when the view is a pure function of
   the durable inputs, materializing it is optional and can happen anywhere.

The compiled file exists today because it was the path of least resistance, not because any
consumer needs compiled-ness. Nothing in the pipeline greps `opportunities.md` for anything a
directory glob can't answer.

**How each option handles the three consumers:**

| | (A) entry-per-file | (B) compiled + reconcile PR |
|---|---|---|
| Human reading | `ls -t` / render task / drain report; view always current with the working tree | one committed file — but only as fresh as the last MERGED reconcile PR; between merges the file lies about active state |
| /spec-draft mining | glob + filter; consume = `git mv` on own branch, atomic with the mining PR | must read compiled file MINUS consumed-markers ledger; consume = tombstone fragment, effective only after next reconcile merge |
| /drain | glob; nothing to reconcile | must also surface "reconcile PR pending" state |
| Archive-on-consume | single-file `git mv`, conflict-free, no serialization needed | needs tombstones + the serial writer; the consumed entry stays visibly "active" in the compiled file until a human merges the reconcile PR |
| New moving parts | none (a render task is optional sugar) | canonical branch + reconcile trigger + PAT/App token + workflow concurrency group + stale-PR-merge risk |
| Migration | one-time: freeze current files (see below) | none for existing entries; new machinery instead |

### Primary recommendation: (A), the reno model

The decisive argument is planwright-specific: **archive-on-consume is as concurrent as
appending.** Consumption happens from `/spec-draft` runs on feature branches — exactly as
parallel as the workers producing observations. Option B serializes every consume through the
human-merged reconcile PR: a consumed entry remains "active" in the compiled file until Diego
merges a bot PR, and the consuming spec's citation can't be reconciled atomically with the
consumption. Option A makes consume the same conflict-free single-file move that prior art
already proves for adds — and it is the ONLY model in which prior art supports removing old
entries at all (reno, §1). B's entire machinery (canonical branch, force-regeneration, token,
concurrency group, stale-PR risk) buys planwright nothing except a committed file no consumer
requires.

Concrete shape, borrowing the verified pieces:

- **Identity (reno):** `<date>-<slug>-<8hex>.md`; 8 hex chars of `urandom` entropy is
  plenty at planwright's entry rate (reno ships 64-bit entropy with a local-only existence
  check; Changesets ships ~15M-pool names with NO check). Slug is cosmetic and renameable; the
  UID is the citation key. Skills cite `obs:<8hex>` in specs — a durable reference that
  survives the archive move, unlike today's exact-text identity.
- **Entry body:** the existing one-line format, unchanged (D-1's `[target]` tag + trailing
  provenance sentence), so parsers and doctrine wording carry over. Consume appends a
  `Consumed-by: specs/<spec-id>` line inside the file before/with the `git mv` — single-file
  edit, conflict-free, and the archive keeps its audit trail.
- **Archive (reno's freeze, not deletion):** `git mv entries/<f> archive/<f>` preserves the
  filename/UID; git history preserves everything else. No compiled archive.md needed either —
  same rendering answer.
- **Migration (the project's own D-2 precedent — no backfill):** freeze the current
  `opportunities.md`/`archive.md` as-is (rename to `archive/pre-fragment-log.md` or leave with
  a header note); new entries go to `entries/` from the cutover. Do NOT bulk-rewrite 78
  historical entries into files — that is exactly the migration-zone bulk edit D-2 already
  rejected once.
- **Optional sugar:** a `mise run obs:log` render task; a CI guard that entry filenames match
  the charset/format (planwright already has the validator muscle for this).

**When (B) would be right instead:** if a committed, always-in-the-repo compiled log were a
hard requirement (e.g., adopters browse it on GitHub as documentation). Then: compiled file as
a MATERIALIZED VIEW, force-regenerated from `entries/` by one canonical reconcile branch
(release-please mechanics verbatim), never hand-edited, consumed state still tracked in the
fragment layer. One planwright-specific relief: the "bot" need not be a GitHub Action — the
reconcile PR can be opened by Diego's own agent session (as /drain's sanctioned mutating phase,
D-5-style), with his credentials, which makes the PAT/App-token problem vanish because the PR
author is a real user. But even at its best, B leaves the compiled file stale between merges;
A has no staleness to manage.

## 5. What naive designs get wrong

1. **Relying on `.gitattributes merge=union`** — GitHub's server-side merge ignores it (F1),
   and even where union merge works it trades visible conflicts for SILENT MISPLACEMENT:
   entries land under the wrong version header or inside another entry (plone.releaser #17,
   quoted in §2). Kubernetes removed the driver for this reason.
2. **Treating the committed compiled file as the source of truth** — then every prune/edit of
   an old entry is a shared-file write and the conflict returns. Every working design makes the
   per-entry unit (file or commit message) the truth and the compiled view derived.
3. **Identity by exact text or by semantic key** — text breaks on any wording edit (prune
   silently no-ops or hits the wrong entry); semantic keys (SHA, change-id) are reno's
   explicitly rejected alternative ("no special values... that have special meaning"). Random
   UID + cosmetic slug is the proven shape.
4. **Bot PR opened with `GITHUB_TOKEN`** — no CI runs on it, required checks never pass, human
   can't merge (F2; changesets #523/#70; release-please README). Fix: GitHub App token/PAT — or
   have a real user's session open the reconcile PR.
5. **Incrementally patching the reconcile branch instead of regenerating it** — accumulates
   drift and merge state. Both Changesets and release-please hard-reset/force-push the
   canonical branch from main's tip every run; the maintainers rejected non-force-push as "not
   very feasible" (changesets/action #455).
6. **No workflow-level serialization** — two quick-succession merges each trigger a run; the
   older run's force-push can land last and produce a stale reconcile PR. Fix is a
   `concurrency` queue per ref (changesets/action #263), and awareness of the residual risk:
   a human merging a stale reconcile PR before the next regeneration.
7. **Letting contributors edit the compiled file "just this once"** — reintroduces the exact
   conflict fragments removed, and breaks view = f(fragments) idempotency.
8. **`[skip ci]` in the reconcile commit** — suppresses the post-merge workflows too
   (changesets/action #198).
9. **Fearing squash-merge fragment resurrection** — unfounded; a squash applies only the PR's
   own diff, so fragments deleted by a merged reconcile PR stay deleted (verified, no
   documented gotcha in either towncrier or scriv).
10. **Conflating "PR-based" with "human-merged"** — intuit/auto's protected-branch plugin is
    PR-shaped but self-approves and auto-merges; under a never-auto-merge invariant that is
    non-compliant automation, not compliance.
11. **Under-provisioned name entropy WITH an overwrite** — Changesets does no existence check
    and `fs.writeFile` would silently clobber on collision. Use ≥64 bits of randomness
    (reno) or at least fail-on-exists.
