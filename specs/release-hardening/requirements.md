# Release Hardening — Requirements

**Status:** Draft
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

`autopilot-reflex` (Done) shipped planwright's release pipeline: the
comparator (`release-pending.sh`), the untagged-window lock
(`release-window-check.sh`), the human-gated signed publish
(`release-publish.sh`), the armed watch-and-publish path (`release-arm.sh`),
and the shared primitives (`release-lib.sh`). A 2026-07-16 full-accumulator
triage (10-agent verification against v0.14.1) confirmed a backlog of
correctness, fail-closed, and coverage gaps that were surfaced-and-recorded
during that spec's execution but landed outside its task scope. This bundle
closes that backlog as a focused hardening pass over the same five scripts,
citing `autopilot-reflex` as its Source rather than reopening it (D-1).

The theme is **fail closed and stay honest**: a control that cannot determine
its state must refuse rather than pass; a gate must scope its carve-outs so a
namesake cannot slip through; a path guard must canonicalize before it trusts;
and the comparator's untested precedence surface must be pinned. The hard
invariants from `autopilot-reflex` stand untouched: `release-publish.sh`
remains local and human-invoked, and never-auto-merge is not in scope here.

## Scope

### In scope

- Fail-closed error signaling in the release comparator so a comparator error
  is distinguished from "not pending" in both `release-pending.sh` and
  `release-window-check.sh` (REQ-A).
- Resume-path integrity in `release-publish.sh`: assert the origin tag's
  commit equals the recomputed release SHA and re-verify the tag signature
  before creating the GitHub Release on a resume (REQ-B).
- CI-gate consolidation and scoping: one shared `rl_ci_state` helper in
  `release-lib.sh` used by both publish and arm, with a workflow-scoped
  window-lock exclusion, plus the REQ-D1.3 gate-semantics clarification
  expressed here (REQ-C).
- Input hardening: canonicalize and containment-check the `version_file`
  path before the filesystem read in `release-pending.sh` (REQ-D).
- Comparator test coverage: a new `test-release-lib.sh` exercising the
  two-prerelease precedence surface of `rl_version_gt`, plus the 64-bit
  numeric-identifier limit documented and boundary-tested (REQ-E).
- Operator surface: a `mise run release-arm <pr>` task (REQ-F).
- Adopter surface: the `templates/release-please/README.md` gaps
  (pending→tagged relabel obligation; strict null-CI publish prerequisite),
  a default-preserving `require_ci` core knob, and the verified item-9
  required-check caveat (REQ-G).

### Out of scope

- A commits-since-last-tag comparator extension (legacy opportunity line 130):
  a release-please detection-failure enhancement, orthogonal to hardening the
  confirmed gaps. Consumed into this bundle's Sources and recorded here;
  deserves its own spec or a deliberate accept (drafting-session decision
  2026-07-17).
- The stranded-partial-publish recovery edge (E3): a tag pushed but the
  Release failed becomes unresumable once a newer version bumps
  `version_file`, because resume only probes the current version's tag. A
  multi-tag stranded scan is deferred; this bundle hardens the current
  target's resume only (D-3).
- Re-running the creation gates (CI-green, monotonicity, sync, clean-tree) on
  resume: the tag already exists on origin and cannot be un-pushed, so
  re-gating it adds little; resume hardening is the SHA assertion and the
  signature re-verify only (D-3).
- Guarding the 64-bit numeric-identifier overflow in `rl_version_gt` with a
  length-then-lexical compare: the risk is unreachable with realistic version
  strings, so it is documented and boundary-tested rather than coded (D-6).
- Reopening `autopilot-reflex` to edit REQ-D1.3 in place: the frozen Done
  contract stays frozen; its window-lock-carve-out reading is restated by
  citation in REQ-C1.4 (D-1, D-8).
- Never-auto-merge and the local + human-invoked publish invariant: unchanged,
  not touched by any REQ here.

## REQ-A — Fail-closed comparator signaling

- **REQ-A1.1** `rl_version_gt` SHALL signal an internal comparator error with
  a distinct non-zero exit status (2) — reserved for a malformed or
  unusable input reaching the comparator — separate from its "not strictly
  greater" result (exit 1), so a caller can tell a comparator failure from a
  negative comparison.
  *(Cites: D-2; obs:fa2075a3; autopilot-reflex REQ-D1.8 (Source).)*
- **REQ-A1.2** `release-pending.sh` SHALL treat a comparator-error status
  from `rl_version_gt` as a fail-closed condition — a diagnostic on stderr and
  exit 2 — never folding it into the `none` (not-pending, exit 0) result.
  *(Cites: D-2; obs:fa2075a3.)*
- **REQ-A1.3** `release-window-check.sh` SHALL treat a comparator-error status
  in its `--ref` path as fail-closed (exit 2), consistent with its existing
  fail-closed posture for an unreadable or malformed version of truth; the
  lock never lets a merge through on a state it could not determine.
  *(Cites: D-2; obs:fa2075a3.)*

## REQ-B — Resume-path integrity

- **REQ-B1.1** On a resume (a partial publish: the target tag exists on
  origin but its GitHub Release is absent), `release-publish.sh` SHALL assert
  that the origin tag's target commit equals the locally recomputed
  release SHA, and SHALL refuse without side effects — naming both SHAs — on a
  mismatch, before creating the Release.
  *(Cites: D-3; legacy line 184 (Sources); autopilot-reflex REQ-D1.3 (Source).)*
- **REQ-B1.2** On a resume, `release-publish.sh` SHALL re-verify the tag's
  signature under the effective signing policy before creating the Release,
  so an origin tag placed by non-script means is not trusted unconditionally.
  When the signing policy does not require a signature, the re-verify is
  skipped consistently with creation-time signing behavior.
  *(Cites: D-3; legacy line 184 (Sources); autopilot-reflex REQ-D1.4 (Source).)*
- **REQ-B1.3** The resume path SHALL continue to skip the creation gates
  (monotonicity, clean-tree, sync, CI-green) and the tag create+push: the tag
  is already published on origin and cannot be un-pushed, so resume hardens
  the tag/commit correspondence, not the merge-time gates.
  *(Cites: D-3.)*

## REQ-C — CI-gate consolidation and scoping

- **REQ-C1.1** `release-lib.sh` SHALL define a single CI-verdict primitive
  `rl_ci_state <sha>` that reads the GitHub `statusCheckRollup` for the
  commit, judges each check individually, excludes the untagged-window lock,
  and folds the remainder to one verdict (green / failing / pending / no
  positive confirmation / unread-overflow), returning a distinct status on a
  query failure so an infra outage is never misreported as a red verdict.
  *(Cites: D-4; legacy line 197 (Sources).)*
- **REQ-C1.2** `release-publish.sh`'s CI gate and `release-arm.sh`'s
  release-gating CI verdict SHALL both be expressed as thin callers of
  `rl_ci_state`, so the two never drift on what counts as release-gating CI;
  the duplicated inline evaluators are retired.
  *(Cites: D-4; legacy line 197 (Sources).)*
- **REQ-C1.3** The window-lock exclusion in `rl_ci_state` SHALL be scoped to
  the release-window workflow — matching the check-run's owning workflow name
  (`release-window`) in addition to the check-run display name (`window-lock`)
  — so a same-named check-run produced by any other workflow is judged by the
  gate, not silently dropped from it.
  *(Cites: D-4; legacy line 202 (Sources), legacy line 201 (Sources).)*
- **REQ-C1.4** This bundle SHALL record the publish CI gate's window-lock
  carve-out semantics — the gate evaluates per-check with the release-window
  lock excluded, not the aggregate `statusCheckRollup.state` (which is red by
  design during the untagged window) — as a requirement in this bundle,
  amending by citation the reading of `autopilot-reflex` REQ-D1.3 rather than
  editing that frozen Done contract in place.
  *(Cites: D-8, D-1; legacy line 201 (Sources); autopilot-reflex REQ-D1.3 (Source).)*

## REQ-D — Input hardening

- **REQ-D1.1** Before the filesystem read of the `version_file` in
  `release-pending.sh`, the resolved path SHALL be canonicalized and
  containment-checked against the repository root, so a repo-relative symlink
  resolving outside the tree is a clean refusal (exit 2), meeting the
  security-posture rule "containment-checked after canonicalization". The
  existing absolute-path and `..`-component rejections are retained as the
  cheap pre-checks.
  *(Cites: D-5; legacy line 182 (Sources); security-posture.md.)*
- **REQ-D1.2** The canonicalization SHALL be portable to the repo's shell
  floor (bash 3.2 / BSD tooling, `LC_ALL=C`, no dependency beyond git and the
  existing tools), and SHALL be factored so any future filesystem reader of a
  config-specified path reuses it rather than re-implementing the guard.
  Readers that access the version file via `git show` (window-check, publish,
  arm) are already symlink-immune and need no change.
  *(Cites: D-5; autopilot-reflex REQ-D1.9 (Source).)*

## REQ-E — Comparator test coverage

- **REQ-E1.1** A new `tests/test-release-lib.sh` SHALL exercise the
  two-prerelease precedence surface of `rl_version_gt` that `pending` never
  reaches (it only ever compares release-vs-release): `-rc.1 < -rc.2`,
  numeric-vs-alphanumeric identifier ranking (numeric below alphanumeric),
  fewer-fields-lower, a prerelease ranking below its release, and
  build-metadata accepted-and-ignored.
  *(Cites: D-6; legacy line 186 (Sources).)*
- **REQ-E1.2** The 64-bit signed-arithmetic limit of `rl_version_gt`'s numeric
  identifier comparison (`((10#$x > 10#$y))` overflows at ~19-20+ digits)
  SHALL be documented in-code and in the test-spec as a known, unreachable-
  with-realistic-inputs limit, and a boundary test SHALL assert the current
  behavior at a safe (non-overflowing) numeric identifier width.
  *(Cites: D-6; legacy line 187 (Sources).)*

## REQ-F — Operator surface

- **REQ-F1.1** A `mise run release-arm <pr>` task SHALL surface
  `scripts/release-arm.sh`, so the armed watch-and-publish path is as
  discoverable as the post-merge `mise run release` wrapper. The task SHALL
  pass the required PR-number argument through to the script and remain a thin
  wrapper — the script keeps no `mise` dependency and stays directly
  invokable (portability floor).
  *(Cites: D-9; legacy line 198 (Sources); autopilot-reflex REQ-F1.3 (Source).)*

## REQ-G — Adopter surface

- **REQ-G1.1** `templates/release-please/README.md` SHALL document that an
  adopter supplying their own publish step (bypassing
  `scripts/release-publish.sh`) must also perform the
  `autorelease: pending` → `autorelease: tagged` relabel that release-please's
  skipped github-release step would have done, or release-please aborts the
  next cycle's release PR.
  *(Cites: D-10; obs:86525b9e; legacy line 181 (Sources).)*
- **REQ-G1.2** `templates/release-please/README.md` SHALL document that the
  publish CI gate's strict default treats a null `statusCheckRollup` (no
  checks) as not-green and refuses, so a no-CI adopter must add CI before
  publishing via the script, or set the `require_ci` knob (REQ-G1.3).
  *(Cites: D-7; legacy line 181 (Sources).)*
- **REQ-G1.3** A core config knob `require_ci` SHALL default to `true`
  (preserving today's strict behavior) and, when set to `false`, relax only
  the "no positive CI confirmation" (null / NONE) refusal in the publish CI
  gate — a genuinely failing or still-pending check SHALL remain fail-closed
  regardless. The capability lands in core as an opt-in with the default
  unchanged; the specific value is the adopter's overlay choice.
  *(Cites: D-7; customization-boundary.md; legacy line 181 (Sources).)*
- **REQ-G1.4** The bundle SHALL record the verified finding that this
  repository has no branch-protection required status check on the release PR,
  and `templates/release-please/README.md` SHALL carry an adopter caveat that
  making the `ci` check a required status check on the release PR would
  deadlock it (a `GITHUB_TOKEN`-authored PR raises no CI run) unless a
  CI-triggering token fix is applied first.
  *(Cites: D-11; legacy line 194 (Sources).)*

## Changelog

- 2026-07-17 — Draft created. Nine-item confirmed backlog from the
  `autopilot-reflex` execution, elicited via `/spec-draft`. Fold-detection
  surfaced an extend-vs-new-spec fork; the human chose a new spec citing
  `autopilot-reflex` as Source (D-1). Scope forks resolved: line 130
  out-of-scope; adopter surface = docs + core `require_ci` knob; CI-gate items
  bundled into one `rl_ci_state` with workflow-scoped exclusion; resume
  hardening = SHA assert + signature re-verify (E3 out of scope); comparator
  overflow documented-not-guarded.

## Sources

- **autopilot-reflex** (`specs/autopilot-reflex/`, Done) — the spec that
  shipped the release pipeline this bundle hardens. Cited as the framing
  Source for every REQ; its REQ-D1.3 (creation gates), REQ-D1.4 (signing),
  REQ-D1.8 (the shared comparator), and REQ-D1.9 (portability floor) are the
  frozen contracts this bundle restates-by-citation rather than reopens.
- **obs:fa2075a3** — release comparator error reads as fail-open ("not ahead →
  exit 0") in `release-pending.sh` and `release-window-check.sh`; a fail-closed
  control should distinguish comparator-error from not-pending. Consumed into
  REQ-A / D-2.
- **obs:86525b9e** — `templates/release-please/README.md` omits the
  bring-your-own-publish adopter's `autorelease: pending` → `tagged` relabel
  obligation (issue #173 class). Consumed into REQ-G1.1 / D-10.
- **Legacy opportunity line 130** — a commits-since-last-tag comparator
  extension to surface silent release-please detection failure. Consumed;
  recorded Out of scope (a detection enhancement, not a hardening of a
  confirmed gap).
- **Legacy opportunity line 181** — the publish CI gate refuses a release
  commit with a null `statusCheckRollup` (no CI), a deliberate strict default
  that blocks a no-CI adopter; candidate `require_ci` knob or adopter doc note.
  Consumed into REQ-G / D-7.
- **Legacy opportunity line 182** — the `version_file` path guard rejects
  absolute and `..` paths but does not canonicalize, so a repo-relative
  symlink escapes the tree in `release-pending.sh`'s filesystem read (the
  `git show` readers are immune). Consumed into REQ-D / D-5.
- **Legacy opportunity line 184** — partial-publish resume edges: an origin
  tag is trusted unconditionally on resume (no signature-verify, no
  origin-tag-SHA == release_sha assertion; a rewritten main yields a silent
  tag/notes mismatch); and a stranded partial is unresumable after a newer
  version bump. Consumed into REQ-B / D-3 (the SHA + signature hardening;
  the stranded-scan edge recorded Out of scope).
- **Legacy opportunity line 186** — the positive prerelease/build precedence
  surface of `rl_version_gt` is largely untested; `pending` only compares
  release-vs-release. Consumed into REQ-E1.1 / D-6.
- **Legacy opportunity line 187** — `rl_version_gt`'s `((10#$x > 10#$y))`
  (64-bit signed) mis-ranks a ~19-20+ digit numeric identifier. Consumed into
  REQ-E1.2 / D-6.
- **Legacy opportunity line 194** — whether the release-PR `ci` check is a
  required status check is a GitHub branch-protection setting not confirmable
  from the tree. Verified during drafting via `gh api`: this repo has no
  branch protection and its default ruleset carries no required-status-check
  rule, so the `GITHUB_TOKEN`-CI-never-fires deadlock is dormant. Consumed into
  REQ-G1.4 / D-11.
- **Legacy opportunity line 197** — the CI-rollup check exists in two inline
  copies (`release-publish.sh` `ci_green`, `release-arm.sh` `rl_ci_verdict`);
  candidate to promote one `rl_ci_state` into `release-lib.sh`. Consumed into
  REQ-C1.1–C1.2 / D-4.
- **Legacy opportunity line 198** — no `mise` task surfaces
  `release-arm.sh` (only `release`). Consumed into REQ-F1.1 / D-9.
- **Legacy opportunity line 201** — the publish/window-lock deadlock: the
  code carve-out shipped (#163) but the REQ-D1.3 spec text never followed.
  Consumed into REQ-C1.4 / D-8.
- **Legacy opportunity line 202** — the window-lock carve-out excludes by
  bare check-run name with no workflow/app scoping, a fail-open surface on a
  safety-critical gate. Consumed into REQ-C1.3 / D-4.
- **2026-07-16 accumulator triage** — the 10-agent verification run (against
  v0.14.1) that confirmed every item above valid; verdict ledger held in the
  drafting session's scratch reference. Grounding for the "confirmed backlog"
  framing.
