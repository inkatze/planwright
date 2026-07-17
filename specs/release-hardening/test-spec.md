# Release Hardening — Test Spec

**Status:** Draft
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

Every REQ is pinned to at least one verification path. The release scripts are
plain portable shell with an existing per-script test family under `tests/`
(run by `mise run check`), so `[test]` is the honest default here; the two
non-executable requirements (a spec-text restatement and a recorded finding)
are `[design-level]`.

## REQ-A — Fail-closed comparator signaling

### REQ-A1.1 — comparator error status [test]

`tests/test-release-lib.sh`: call `rl_version_gt` with a malformed operand and
assert exit status 2, distinct from a valid "not greater" (exit 1) and a valid
"greater" (exit 0). Runs under `mise run check`.

### REQ-A1.2 — pending fails closed on comparator error [test]

`tests/test-release-pending.sh`: with inputs that drive the comparator to its
error status, assert `release-pending.sh` exits 2 with a stderr diagnostic and
prints no `none` on stdout. A regression that folds the error into `none` fails
this.

### REQ-A1.3 — window-check fails closed on comparator error [test]

`tests/test-release-window-check.sh`: the `--ref` path under a comparator-error
condition asserts exit 2 (fail closed), never exit 0 (merges may proceed).
Confirms the lock does not pass on an undeterminable state.

## REQ-B — Resume-path integrity

### REQ-B1.1 — resume asserts tag SHA equals release SHA [test]

`tests/test-release-publish.sh`: a resume scenario (origin tag present via the
git/gh stubs, Release absent) where the origin tag's commit differs from the
recomputed `release_sha` asserts a refusal that names both SHAs and creates no
Release; a matching-SHA resume proceeds. The stub logs the created-Release call
so its absence on mismatch is asserted.

### REQ-B1.2 — resume re-verifies the tag signature [test]

`tests/test-release-publish.sh`: a resume under the `require` signing policy
exercises the signature re-verify (the `git tag -v` stub is asserted called
before `gh release create`); under `never` the re-verify is skipped. Confirms
an origin tag is not trusted unconditionally.

### REQ-B1.3 — resume skips the creation gates [test]

`tests/test-release-publish.sh`: a resume asserts the creation gates
(CI/monotonicity/sync/clean-tree) and the tag create+push are not re-run (their
stubs record no call on the resume path), so resume hardens the tag
correspondence only.

## REQ-C — CI-gate consolidation and scoping

### REQ-C1.1 — rl_ci_state verdicts [test]

`tests/test-release-lib.sh`: drive `rl_ci_state` with stubbed `gh api graphql`
rollups covering each verdict (green, failing, pending, no-positive-
confirmation, unread-overflow) and a query failure, asserting the verdict and
the distinct query-failure status.

### REQ-C1.2 — publish and arm share one verdict [test]

`tests/test-release-publish.sh` and `tests/test-release-arm.sh`: for the same
stubbed SHA rollup, assert publish's CI gate and arm's release-gating verdict
resolve identically (both now route through `rl_ci_state`). Guards against the
two drifting.

### REQ-C1.3 — window-lock exclusion is workflow-scoped [test]

`tests/test-release-lib.sh`: a rollup containing a `window-lock` check-run whose
owning workflow is **not** `release-window` asserts that check is judged (can
fail the gate), while the real `release-window` / `window-lock` check-run is
excluded. A regression to bare-name matching drops the foreign check and fails
this.

### REQ-C1.4 — carve-out semantics restated by citation [design-level]

Verified by this bundle carrying REQ-C1.4: the window-lock carve-out semantics
are stated as a requirement citing `autopilot-reflex` REQ-D1.3 as the
amended-by-citation Source, so the spec text now matches the shipped code
carve-out (#163). No code artifact; the verification is the requirement's
presence and its citation resolving under `mise run check`'s spec validation.

## REQ-D — Input hardening

### REQ-D1.1 — canonicalized containment refuses an escaping symlink [test]

`tests/test-release-pending.sh`: a `version_file` that is a repo-relative
symlink resolving outside the repository root asserts a clean exit-2 refusal
with a diagnostic and no read; an in-tree `version_file` (plain, and via an
in-tree symlink) still resolves and reads.

### REQ-D1.2 — portable, reusable, scoped to the fs reader [test + design-level]

`[test]` the reusable containment function is exercised by the REQ-D1.1 cases;
`[design-level]` the portability claim (bash 3.2 / BSD / `LC_ALL=C`, no new
dependency) is verified by shellcheck and the absence of any non-floor
construct, plus a grep-level cross-check that no canonicalization was added to
the symlink-immune `git show` readers (window-check, publish, arm).

## REQ-E — Comparator test coverage

### REQ-E1.1 — two-prerelease precedence surface [test]

`tests/test-release-lib.sh`: assertions for `-rc.1 < -rc.2`,
numeric-below-alphanumeric ranking, fewer-fields-lower, a prerelease ranking
below its release, and build-metadata accepted-and-ignored, each exercising
`rl_version_gt` directly (the surface `pending` never reaches).

### REQ-E1.2 — documented 64-bit overflow limit [test + design-level]

`[test]` a boundary case at a safe (non-overflowing) numeric identifier width
asserts the current ranking; `[design-level]` the 64-bit overflow is recorded
as a known limit in the in-code comment and here, not guarded (D-6).

## REQ-F — Operator surface

### REQ-F1.1 — mise release-arm task [test]

`tests/test-release-mise-task.sh` (the mise-task test family): assert a
`release-arm` task exists, invokes `release-arm.sh`, and forwards the `<pr>`
argument; and that `release-arm.sh` itself carries no `mise` dependency
(directly invokable).

## REQ-G — Adopter surface

### REQ-G1.1 — relabel obligation documented [manual + design-level]

Review that `templates/release-please/README.md` documents the
`autorelease: pending` → `tagged` relabel obligation for the
bring-your-own-publish path; markdown lint over the template runs in
`mise run check`. Prose correctness is a design-level read against issue #173.

### REQ-G1.2 — strict null-CI prerequisite documented [manual + design-level]

Review that the README documents the strict null-CI publish prerequisite and
the `require_ci` opt-out; lint runs in CI.

### REQ-G1.3 — require_ci narrows only the NONE refusal [test]

`tests/test-release-publish.sh`: with `require_ci` defaulting to `true`, a
null/NONE rollup refuses (unchanged); with `require_ci=false`, the same NONE
rollup publishes, while a FAILING, PENDING, or TOO_MANY rollup still refuses.
Confirms the relaxation is narrow.

### REQ-G1.4 — verified required-check finding + caveat [design-level]

Verified by the recorded finding in requirements.md Sources (this repo has no
required status check on the release PR, checked via `gh api`) and by the
README caveat; a `[manual]` review confirms the caveat text. The finding itself
is a point-in-time external-state verification, not a repeatable test.
