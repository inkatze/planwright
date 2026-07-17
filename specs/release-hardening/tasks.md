# Release Hardening — Tasks

**Status:** Draft
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
  removed. Tests covering the workflow-scoped exclusion (a same-named
  check-run from another workflow is judged, not dropped) and the shared
  verdict across both callers.
- **Done when:** both scripts call `rl_ci_state`; a `window-lock` check-run
  from a non-`release-window` workflow is judged by the gate; the
  publish and arm verdicts are identical for the same SHA; the existing
  window-lock-excluded green/red/pending/none/too-many behavior is preserved;
  new tests fail pre-change and pass after; `mise run check` is green.
- **Dependencies:** none
- **Citations:** D-4, D-8 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4 · legacy line 197
  (Sources), legacy line 201 (Sources), legacy line 202 (Sources)
- **Estimated effort:** 1 day

### Task 4 — Resume-path integrity

- **Deliverables:** On a resume in `release-publish.sh` (origin tag present,
  Release absent), assert the origin tag's target commit equals the recomputed
  `release_sha` — refusing without side effects and naming both SHAs on a
  mismatch — and re-verify the tag signature under the effective signing policy
  before `gh release create`. Creation gates and tag create+push stay skipped
  on resume. Tests: a resume with a matching SHA proceeds; a resume with a
  mismatched SHA refuses naming both; the signature re-verify is exercised
  under the `require`/`auto` signing policies (and skipped under `never`).
- **Done when:** the SHA assertion and signature re-verify run on the resume
  path only; a mismatch refuses with both SHAs and no Release created; a
  matching resume still creates the Release; the non-resume path is unchanged;
  new tests fail pre-change and pass after; `mise run check` is green.
- **Dependencies:** Task 3
- **Citations:** D-3 · REQ-B1.1, REQ-B1.2, REQ-B1.3 · legacy line 184 (Sources) ·
  autopilot-reflex REQ-D1.3 (Source), REQ-D1.4 (Source)
- **Estimated effort:** 1 day

### Task 5 — version_file canonicalization and containment

- **Deliverables:** A portable (bash 3.2 / BSD, `LC_ALL=C`, no new dependency)
  canonicalizing containment check factored as a reusable shell function,
  applied in `release-pending.sh` before its filesystem read of the
  `version_file`: the resolved real path is canonicalized (symlinks resolved)
  and confirmed within the repository root; anything outside is a clean refusal
  (exit 2). The existing absolute-path and `..`-component checks stay as cheap
  pre-filters. Tests: a repo-relative symlink resolving outside the tree is
  refused; an in-tree path (plain and via an in-tree symlink) still reads.
- **Done when:** an out-of-tree symlink `version_file` in `release-pending.sh`
  is a clean exit-2 refusal; an in-tree `version_file` still resolves and
  reads; the check is a reusable function; the `git show` readers
  (window-check, publish, arm) are untouched; new tests fail pre-change and
  pass after; `mise run check` is green.
- **Dependencies:** none
- **Citations:** D-5 · REQ-D1.1, REQ-D1.2 · legacy line 182 (Sources) ·
  security-posture.md · autopilot-reflex REQ-D1.9 (Source)
- **Estimated effort:** 1 day

### Task 6 — require_ci knob

- **Deliverables:** A core `require_ci` config knob (default `true`) read
  through the config overlay, plus its documentation in the canonical options
  reference. In `release-publish.sh`'s CI gate: when `require_ci` is `false`,
  relax only the null/NONE ("no positive CI confirmation") refusal to allow
  publish; a FAILING or PENDING check and the TOO_MANY unread-overflow case
  stay fail-closed. Tests: default (`true`) preserves today's strict refusal on
  NONE; `false` allows publish on NONE but still refuses on FAILURE, PENDING,
  and TOO_MANY.
- **Done when:** `require_ci` defaults to `true` with unchanged behavior;
  `false` publishes on a null/NONE rollup but never on a failing, pending, or
  overflow verdict; the knob is documented in the options reference; new tests
  fail pre-change and pass after; `mise run check` is green.
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
  `GITHUB_TOKEN`-authored PR raises no CI run) absent a CI-triggering token
  fix. The verified item-9 finding recorded in the bundle (already in
  requirements.md Sources).
- **Done when:** the README documents the relabel obligation, the strict
  null-CI prerequisite and the `require_ci` opt-out, and the required-check
  caveat; markdown lint passes over the template; `mise run check` is green.
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
- **64-bit overflow guard in `rl_version_gt`.** The overflow is documented and
  boundary-tested, not guarded with a length-then-lexical compare; unreachable
  with realistic version strings (D-6).
- **Reopening `autopilot-reflex` to edit REQ-D1.3 in place.** The frozen Done
  contract stays frozen; its carve-out reading is restated by citation in
  REQ-C1.4 (D-1, D-8).
