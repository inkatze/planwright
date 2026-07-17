# Release Hardening — Tasks

**Status:** Ready
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

The task-definition record for `specs/release-hardening`; execution status is
derived on demand, never stored here (see the status render). Dependency edges
are the sole source of truth for the task graph. Guard-first note: Task 1
establishes the comparator test home (`tests/test-release-lib.sh`) that Task 2
extends, so the test surface for the fail-closed comparator exists before its
fix lands. The three tasks that touch `release-publish.sh` (Task 3, Task 4,
Task 6) carry edges so the shared `rl_ci_state` helper lands before the resume
and knob changes that share the file.

## Tasks

### Task 1 — Comparator precedence and overflow test coverage

- **Deliverables:** A new `tests/test-release-lib.sh` that sources
  `scripts/release-lib.sh` and exercises the two-prerelease precedence surface
  of `rl_version_gt` — `-rc.1 < -rc.2`, numeric-vs-alphanumeric identifier
  ranking (numeric ranks below alphanumeric), fewer-fields-lower, a prerelease
  ranking below its release, build-metadata accepted-and-ignored — plus a
  boundary test at a safe (non-overflowing) numeric identifier width. An
  in-code comment on `rl_version_gt` documenting the 64-bit numeric-identifier
  overflow limit. The suite wired into the project test runner so
  `mise run check` runs it.
- **Done when:** `tests/test-release-lib.sh` covers each precedence case above
  and the overflow-boundary case; the overflow limit is documented in
  `release-lib.sh`; the new suite runs under `mise run check` and passes;
  `mise run check` is green.
- **Dependencies:** none
- **Citations:** D-6 · REQ-E1.1, REQ-E1.2 · legacy line 186 (Sources), legacy line 187
  (Sources)
- **Estimated effort:** 0.5 day

### Task 2 — Fail-closed comparator signaling

- **Deliverables:** `rl_version_gt` returns a distinct error status (2) when a
  malformed or unusable operand reaches it (validating both operands against
  `rl_valid_semver` at entry). `release-pending.sh` and
  `release-window-check.sh`'s `--ref` path capture the status three-way
  (0 → pending/open, 1 → none/closed, 2 → fail-closed exit 2 with a
  diagnostic), no longer folding any non-zero into `none`. Tests: the
  error-status path in `tests/test-release-lib.sh`; the fail-closed
  propagation in `tests/test-release-pending.sh` and
  `tests/test-release-window-check.sh`.
- **Done when:** a malformed operand makes `rl_version_gt` exit 2; that status
  propagates to `release-pending.sh` exit 2 and `release-window-check.sh`
  exit 2 (never `none`/exit 0); the existing pending/none/valid results are
  unchanged; new tests fail on the pre-change code for the right reason and
  pass after; `mise run check` is green.
- **Dependencies:** Task 1
- **Citations:** D-2 · REQ-A1.1, REQ-A1.2, REQ-A1.3 · obs:fa2075a3 ·
  autopilot-reflex REQ-D1.8 (Source)
- **Estimated effort:** 0.5 day

### Task 3 — Shared rl_ci_state with workflow-scoped exclusion

- **Deliverables:** `rl_ci_state <sha>` in `scripts/release-lib.sh`: reads the
  `statusCheckRollup` `contexts`, judges each check, excludes the
  untagged-window lock scoped to its owning workflow (a `CheckRun` named
  `window-lock` **and** whose `checkSuite.workflowRun.workflow.name` is
  `release-window`), folds the remainder to one verdict, and returns a distinct
  status (2, empty output) on a query failure. `release-publish.sh`'s
  `ci_green` and `release-arm.sh`'s `rl_ci_verdict` reduced to thin callers of
  it, with one unified verdict vocabulary; the duplicated inline evaluators
  removed. Tests (added to `tests/test-release-lib.sh`, the lib test home Task 1
  creates) covering each verdict **including the distinct query-failure status**,
  the workflow-scoped exclusion (a same-named check-run from another workflow is
  judged, not dropped; a null-`workflowRun` namesake is judged), and that publish
  and arm resolve to the **same verdict string** for the same SHA.
- **Done when:** both scripts call `rl_ci_state`; a `window-lock` check-run
  from a non-`release-window` workflow is judged by the gate; the distinct
  query-failure status is returned and asserted; publish and arm resolve to the
  same verdict string for the same SHA (their downstream disposition of a
  query-failure deliberately differs — publish fails closed one-shot, arm
  retries within its poll budget — so only the verdict, not the handling, is
  asserted identical); the existing window-lock-excluded
  green/failing/pending/none/too-many behavior is preserved; new tests (in
  `tests/test-release-lib.sh`) fail pre-change and pass after; `mise run check`
  is green.
- **Dependencies:** Task 1
- **Citations:** D-4, D-8 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4 · legacy line 197
  (Sources), legacy line 201 (Sources), legacy line 202 (Sources)
- **Estimated effort:** 1 day

### Task 4 — Resume-path integrity

- **Deliverables:** On a resume in `release-publish.sh` (origin tag present,
  Release absent), **fetch the origin tag object into a distinct verification
  ref** (never the same-named local tag — git rejects the same-ref fetch when a
  local tag lingers, and a same-named local tag would shadow the object), assert
  its target commit equals the recomputed `release_sha` — refusing without side
  effects and naming both SHAs on a mismatch — and re-verify **that origin
  object's** signature before `gh release create`, keyed off the **origin tag's
  own signedness** (not the resumer's signer config): `require` requires a valid
  signature (refuse on missing/unverifiable); `auto` verifies iff the origin tag
  is signed (refuse a present-but-invalid signature; accept an unsigned tag);
  `never` skips. Creation gates and tag create+push stay skipped on resume.
  Additionally (REQ-B1.4): a resume that finds the Release already present but the
  merged release PR still labeled `autorelease: pending` performs only the
  idempotent `pending`→`tagged` relabel instead of dying "already published".
  Tests: a matching-SHA resume proceeds; a mismatched-SHA resume refuses naming
  both; a **lingering same-named local tag does not shadow the fetched origin
  object**; under `require` the re-verify runs and refuses a missing/invalid
  signature; under `auto` a signed origin tag is verified (refused on an invalid
  signature) and an unsigned origin tag is accepted; under `never` skipped; a
  fresh-clone resume (no local tag) verifies the fetched origin object; a
  Release-present + PR-`pending` resume performs the relabel and does not die.
- **Done when:** the origin tag object is fetched to a distinct verification ref
  and both the SHA assertion and the signature re-verify target it (a lingering
  local tag does not shadow it); a mismatch refuses with both SHAs and no Release;
  a matching resume creates the Release; the `require`/`auto`-signed/
  `auto`-unsigned/`never` re-verify behavior matches REQ-B1.2; a fresh-clone
  resume verifies the fetched origin object correctly; a Release-present +
  PR-`pending` resume performs the relabel instead of dying; the non-resume path
  is unchanged; new tests fail pre-change and pass after; `mise run check` is
  green.
- **Dependencies:** Task 3
- **Citations:** D-3, D-12 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4 · obs:86525b9e ·
  legacy line 184 (Sources) · autopilot-reflex REQ-D1.3 (Source), REQ-D1.4 (Source)
- **Estimated effort:** 1.5 days

### Task 5 — version_file canonicalization and containment

- **Deliverables:** A portable (bash 3.2 / BSD, `LC_ALL=C`, no new dependency)
  canonicalizing containment check factored as a reusable shell function,
  applied in `release-pending.sh` before its filesystem read of the
  `version_file`: the resolved real path is canonicalized (symlinks resolved in
  **every component including the leaf `version_file` itself**) and confirmed
  within the repository root, and the read targets the canonicalized real path
  (never the original `$vf_path`); anything outside is a clean refusal (exit 2).
  The existing absolute-path and `..`-component checks stay as cheap pre-filters.
  Tests: a **leaf** symlink (the `version_file` value itself pointing outside the
  tree) is refused — not only a symlinked parent dir; an in-tree path (plain and
  via an in-tree symlink) still reads.
- **Done when:** an out-of-tree symlink `version_file` in `release-pending.sh`
  is a clean exit-2 refusal, including when the leaf `version_file` component is
  itself the escaping symlink; an in-tree `version_file` still resolves and
  reads; the check is a reusable function and the read uses the canonicalized
  path; the `git show` readers (window-check, publish, arm) are untouched; new
  tests fail pre-change and pass after; `mise run check` is green.
- **Dependencies:** none
- **Citations:** D-5 · REQ-D1.1, REQ-D1.2 · legacy line 182 (Sources) ·
  security-posture.md · autopilot-reflex REQ-D1.9 (Source)
- **Estimated effort:** 1 day

### Task 6 — require_ci knob

- **Deliverables:** A core `require_ci` config knob (default `true`) read
  through the config overlay, plus its documentation in the canonical options
  reference (`docs/options-reference.md`). In `release-publish.sh`'s CI gate:
  when `require_ci` is `false`, relax only the `none`/NONE verdict — all three
  sub-cases it folds together: a null rollup, an empty-after-window-lock-
  exclusion rollup, and a rollup whose non-excluded checks all resolved
  NEUTRAL/SKIPPED — to allow publish, emitting a stderr diagnostic that it
  published without positive CI confirmation (`require_ci=false`); a FAILING or
  PENDING check, the TOO_MANY unread-overflow case, and the distinct
  CI-query-failure status stay fail-closed regardless. The `require_ci` value is
  validated as a boolean; a non-conforming value is a clean fail-closed
  configuration error (symmetric with `require_signed_tags`). Tests: default
  (`true`) preserves today's strict refusal on NONE; `false` allows publish on
  NONE (including the all-NEUTRAL/SKIPPED sub-case) but still refuses on FAILURE,
  PENDING, TOO_MANY, and query-failure; the relaxed-path diagnostic is present
  on the NONE publish and absent otherwise; a non-boolean `require_ci` value is a
  clean configuration error.
- **Done when:** `require_ci` defaults to `true` with unchanged behavior;
  `false` publishes on any NONE sub-case (null, empty-after-exclusion, or
  all-NEUTRAL/SKIPPED) but never on a failing, pending, overflow, or
  query-failure verdict; a non-boolean value is a clean fail-closed config error;
  the relaxed NONE publish emits the stderr diagnostic (asserted present on the
  relaxed path, absent otherwise); the knob is documented in
  `docs/options-reference.md`; new tests fail pre-change and pass after;
  `mise run check` is green.
- **Dependencies:** Task 3
- **Citations:** D-7 · REQ-G1.3 · customization-boundary.md · legacy line 181 (Sources)
- **Estimated effort:** 0.5 day

### Task 7 — mise release-arm task

- **Deliverables:** A `[tasks.release-arm]` entry in `mise.toml` invoking
  `scripts/release-arm.sh` and forwarding the required `<pr>` argument, with a
  description matching the `release` task's ergonomics-only framing. A test in
  the mise-task test family asserting the task exists and forwards its
  argument.
- **Done when:** `mise run release-arm <pr>` invokes `release-arm.sh` with the
  PR number; the script keeps no `mise` dependency and stays directly
  invokable; a test asserts the task and its argument forwarding;
  `mise run check` is green.
- **Dependencies:** none
- **Citations:** D-9 · REQ-F1.1 · legacy line 198 (Sources) · autopilot-reflex
  REQ-F1.3 (Source)
- **Estimated effort:** 0.25 day

### Task 8 — Adopter documentation

- **Deliverables:** Updates to `templates/release-please/README.md`:
  (a) the bring-your-own-publish adopter must also relabel the merged release
  PR `autorelease: pending` → `autorelease: tagged`, or release-please aborts
  the next cycle; (b) the publish CI gate's strict default treats a null
  `statusCheckRollup` as not-green and refuses, so a no-CI adopter must add CI
  or set `require_ci=false` (REQ-G1.3); (c) an adopter caveat that making the
  `ci` check a required status check on the release PR would deadlock it (a
  `GITHUB_TOKEN`-authored PR raises no CI run) absent a CI-triggering token fix
  — namely authoring the release PR with a Personal Access Token or a GitHub App
  token (via release-please's `token:` input) instead of the default
  `GITHUB_TOKEN`. The verified item-9 finding recorded in the bundle (already in
  requirements.md Sources).
  (d) Add `templates/**/*.md` to the `lint:md` glob in `mise.toml` so the
  adopter-facing template READMEs are linted in CI (today `mise.toml:36`'s
  allowlist does not include `templates/`, leaving them unlinted and
  REQ-G1.1/G1.2's named CI verification a dead path); the glob covers **both**
  `templates/release-please/README.md` and `templates/release-window/README.md`,
  so fix any pre-existing lint violations in either newly covered template.
- **Done when:** the README documents the relabel obligation, the strict
  null-CI prerequisite and the `require_ci` opt-out, and the required-check
  caveat with its PAT/App-token remedy; `templates/**/*.md` is in the `lint:md`
  glob and markdown lint passes over both templates (no longer a dead path);
  `mise run check` is green.
- **Dependencies:** Task 6
- **Citations:** D-10, D-11 · REQ-G1.1, REQ-G1.2, REQ-G1.4 · obs:86525b9e ·
  legacy line 181 (Sources), legacy line 194 (Sources)
- **Estimated effort:** 0.5 day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

- **Commits-since-last-tag comparator extension** (legacy opportunity line
  130). A release-please detection-failure enhancement, orthogonal to
  hardening the confirmed gaps; deserves its own spec or a deliberate accept.
- **Stranded-partial-publish recovery (E3).** A tag pushed but the Release
  failed becomes unresumable once a newer version bumps `version_file`; a
  multi-tag stranded scan is deferred (D-3).
- **Signing-policy change between the failed publish and the resume (B4).** An
  unsigned `auto`-created tag becomes unresumable if the operator later resumes
  under `require` (a legit tag refused). Defensible fail-closed behavior;
  accepted as risk R10 rather than special-cased (D-3, lens pass 2026-07-17).
- **64-bit overflow guard in `rl_version_gt`.** The overflow is documented and
  boundary-tested, not guarded with a length-then-lexical compare; unreachable
  with realistic version strings (D-6).
- **Reopening `autopilot-reflex` to edit REQ-D1.3 in place.** The frozen Done
  contract stays frozen; its carve-out reading is restated by citation in
  REQ-C1.4 (D-1, D-8).
