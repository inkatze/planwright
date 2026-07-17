# Release Hardening — Design

**Status:** Ready
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

Origin-tag legend: `N` — a new decision made for this bundle; `C, <ns> <id>` —
carried from a foreign bundle's decision, namespace-qualified.

**Altitude note (autopilot-reflex D-11 / REQ-H1.1).** No altitude trigger
fired. The parent `autopilot-reflex` was the doctrine-altitude deliverable
(it minted the release-tagging doctrine and the autopilot-reflex thought
process); this bundle is mechanism hardening of that already-doctrine'd
surface. Every fix here *instantiates* existing doctrine — the fail-closed
posture (security-posture), "containment-checked after canonicalization"
(security-posture), and the capability-vs-style boundary
(customization-boundary) — rather than minting new doctrine. Per
`proportionality`, the altitude ceremony is scoped to specs that exhibit the
risk; none does here, so no altitude D-ID is recorded.

## Decision log

### D-1: New spec citing autopilot-reflex, not a reopen  (N)

**Decision:** Draft this backlog as a new `specs/release-hardening/` bundle
that cites `autopilot-reflex` as its Source, rather than reopening the Done
`autopilot-reflex` bundle (REQ-A3.1 reopen cycle) to append the fixes.

**Alternatives considered:**
- Extend `autopilot-reflex` (Done→Draft on all four headers, append REQs/D-IDs,
  scoped delta kickoff). Rejected because: it parks a large 11-task Done
  contract in Draft while the delta signs off, and two D-21 spin-new triggers
  arguably fire (the backlog is independently ownable, and would push the
  bundle past "one feature a reader holds in their head").
- Hybrid: a new spec for the backlog plus a micro-reopen of `autopilot-reflex`
  scoped only to the REQ-D1.3 text amendment. Rejected because: two kickoff
  cycles and two PRs for one body of work, for a text clarification that
  restatement-by-citation (D-8) handles without touching the frozen contract.

**Chosen because:** the human chose it at the fold-detection fork; it keeps
`autopilot-reflex`'s Done contract frozen, gives the hardening its own kickoff
and review cycle, and uses a fresh v2-format bundle. The one text that "wants"
to live in REQ-D1.3 (the window-lock carve-out semantics) is restated by
citation in REQ-C1.4 instead of edited in place.

### D-2: Fail-closed comparator via a distinct error status  (N)

**Decision:** Give `rl_version_gt` a distinct error exit (2) for a malformed or
unusable input reaching it — validating both operands against
`rl_valid_semver` at entry and returning 2 on failure — and have both callers
(`release-pending.sh`, `release-window-check.sh`'s `--ref` path) capture the
status three-way: 0 → pending/open, 1 → none/closed, 2 → fail-closed exit 2
with a diagnostic. The callers stop folding "any non-zero" into `none`.

**Alternatives considered:**
- Leave it as-is because the inputs are pre-validated so the error path is
  unreachable today. Rejected because: a fail-closed control that reads a
  future undefined-comparator result as "not pending → merge may proceed" is a
  latent fail-open on a safety gate; the cost of the distinction is one
  validation branch and a three-way status capture.
- Have `rl_version_gt` print an error to stderr but keep exit 1. Rejected
  because: exit 1 is a legitimate "not greater" result; overloading it is
  exactly the ambiguity being removed. The signal must be a distinct status.

**Chosen because:** it makes the fail-closed posture real and testable: a unit
test drives `rl_version_gt` to its error status directly (REQ-A1.1), and the
propagation to `release-pending.sh` / `release-window-check.sh` exit 2
(REQ-A1.2/A1.3) is exercised by fault-injecting the comparator status — every
caller pre-validates its operands, so no black-box input reaches the error path
today. This is deliberate defense-in-depth for a future non-validating caller
(the "latent fail-open" above), not the closing of a live fail-open, matching
the ls-remote and CI gates' existing fail-closed shape at minimal cost.

### D-3: Resume hardening = SHA assertion + signature re-verify  (N)

**Decision:** On a resume (origin tag present, Release absent),
`release-publish.sh` **fetches the origin tag object into a distinct
verification ref** (never the same-named local tag, which git refuses to clobber
and which would otherwise shadow the object) and asserts its target commit
equals the locally recomputed `release_sha` (refusing, naming both SHAs, on
mismatch), then re-verifies **that origin tag object's** signature, before
`gh release create`. The origin object — the one `--verify-tag` publishes — is
what both the SHA assertion and the re-verify target; never a possibly-absent or
stale local tag (a fresh-clone resume has no local tag). The re-verify keys off
the **origin tag's own signedness**, never the resuming machine's signer config
(unknowable relative to creation on a cross-machine resume): `require` mandates a
valid signature (refuse on missing/unverifiable); `auto` verifies iff the origin
tag is signed (refuse a present-but-invalid signature; accept an unsigned tag —
the SHA is pinned and `auto` is best-effort); `never` skips. Guaranteed
signature-on-resume is the `require` operator's choice. The creation gates
(CI/monotonicity/sync/clean-tree) and the tag create+push stay skipped on resume.
The resume relabel-idempotency aspect is D-12. The stranded-partial edge (E3),
the signing-policy-change edge (R10), and the unsigned-`auto`-tag-at-pinned-SHA
residual (R10b) are Out of scope / accepted risk.
*(Amended at kickoff lens pass 2026-07-17: origin-object fetch + read-the-origin-
object made explicit; relabel idempotency split to D-12. Amended at panel pass
2026-07-17: fetch to a distinct verification ref; `auto` keys off the tag's
signedness, not the resumer's config — the panel showed the resumer-config
criterion was broken cross-machine.)*

**Alternatives considered:**
- Full re-gate on resume (re-run CI-green, monotonicity, sync, clean-tree plus
  the SHA/signature checks). Rejected because: the tag is already published on
  origin and cannot be un-pushed, so re-litigating merge-time gates against an
  immutable published tag adds failure surface on the recovery path without
  changing what can be undone.
- Option 1 plus an E3 stranded-tag scan (scan all origin release tags for one
  whose Release is missing, so a stranded partial is resumable after a newer
  version bump). Rejected because: it adds a multi-tag scan and the
  "which stranded tag to resume when several exist" question — more design
  surface than the confirmed edge warrants. Recorded Out of scope.

**Chosen because:** it closes the two concrete correctness holes the triage
named — the silent tag/notes mismatch when main was rewritten, and the
unconditional trust of a non-script-placed origin tag — with a bounded,
fail-closed change that stays on the recovery path's honest minimum.

### D-4: One rl_ci_state in release-lib.sh, workflow-scoped exclusion  (N)

**Decision:** Promote a single `rl_ci_state <sha>` into `release-lib.sh` that
both `release-publish.sh` (its `ci_green` gate) and `release-arm.sh` (its
`rl_ci_verdict`) call. The helper reads the `statusCheckRollup` `contexts`,
judges each check to SUCCESS/PENDING/FAILURE/NEUTRAL, excludes the
untagged-window lock **scoped to its owning workflow** — a `CheckRun` whose
name is `window-lock` **and** whose
`checkSuite.workflowRun.workflow.name` is `release-window` — then folds the
remainder to one verdict, returning a distinct status (2, empty output) on a
query failure. A unified verdict vocabulary replaces publish's SUCCESS-based
and arm's GREEN-based spellings.

**Alternatives considered:**
- Keep the two inline copies (the `autopilot-reflex` posture: leave
  `release-publish.sh` byte-for-byte unchanged). Rejected because: this
  bundle is explicitly free to touch publish, and the duplication is the
  divergence risk the triage flagged — arm and publish must agree on the
  release-gating verdict or arm can arm-and-fire on a state publish then
  refuses.
- Consolidate but keep the bare-name exclusion (item 6 without item 3).
  Rejected because: the bare-name match is a fail-open surface on a
  safety-critical gate (a `window-lock` check-run from any other workflow is
  silently dropped from the gate); the shared helper is the one change that is
  free to touch publish, so fixing the scoping here is nearly free.

**Chosen because:** it retires the duplication and closes the name-only
fail-open in one coherent change. Arm's query already fetches the workflow
name; publish's `ci_green` query gains it. The workflow-scoped predicate is
identical in both callers by construction, which is the property the exclusion
exists to guarantee.

### D-5: Portable canonicalization + containment, scoped to the fs reader  (N)

**Decision:** Add a portable canonicalizing containment check to the
`version_file` path guard and apply it in `release-pending.sh` — the only
script that reads the version file from the filesystem (`<"$vf_path"`). The
resolved real path is canonicalized — **resolving symlinks in every component
including the final `version_file` component itself, not only the parent
directory** — and confirmed to sit within the repository root; anything outside
is a clean refusal (exit 2). **The subsequent read targets the canonicalized
real path, never the original `$vf_path`**, so a resolved path cannot be
re-defeated by re-following the original symlink. The existing absolute-path and
`..`-component checks stay as cheap pre-filters. The check is factored into a
reusable shell function so a future filesystem reader reuses it.
*(Amended at kickoff lens pass 2026-07-17: leaf-component resolution +
read-the-canonical-path made explicit; the parent-dir-only recipe was
insufficient.)*

**Alternatives considered:**
- Apply the canonicalization to all four scripts uniformly. Rejected because:
  `release-window-check.sh`, `release-publish.sh`, and `release-arm.sh` read
  the version file via `git show <ref>:<path>`, which resolves the blob in the
  git tree and follows no filesystem symlink — they are already immune, so
  adding the check there is dead code that implies a risk they do not have.
- Depend on `realpath -m` / `readlink -f`. Rejected because: neither is
  reliably present on the BSD/macOS shell floor the pipeline pins
  (`autopilot-reflex` REQ-D1.9); the canonicalization must be a portable
  construction under `LC_ALL=C` that resolves the **leaf**: iteratively
  `readlink` the final component until it is not a symlink (bounded against
  loops), then `cd` into the containing directory and `pwd -P`. A bare
  `cd`-and-`pwd -P` on the parent directory alone leaves a leaf `version_file`
  symlink unresolved and is insufficient (the leaf symlink is the attack).

**Chosen because:** it meets the security-posture rule ("containment-checked
after canonicalization") exactly where the filesystem read happens, without
implying false risk on the symlink-immune readers, and stays on the pipeline's
portability floor.

### D-6: Document the overflow, pin the precedence surface  (N)

**Decision:** Add `tests/test-release-lib.sh` covering the two-prerelease
precedence surface of `rl_version_gt` (`-rc.1 < -rc.2`,
numeric-vs-alphanumeric ranking, fewer-fields-lower, prerelease-below-release,
build-metadata ignored). Record the 64-bit numeric-identifier overflow as a
known, in-code and test-spec documented limit, with one boundary test asserting
current behavior at a safe (non-overflowing) numeric width. No change to the
comparator's arithmetic.

**Alternatives considered:**
- Guard the overflow with a length-then-lexical numeric compare (equal-length
  → lexical, else longer numeric wins). Rejected because: a ~19-20+ digit
  numeric SemVer identifier is not a realistic version string; the guard adds a
  branch to the comparator's hot path that only matters for pathological
  inputs, and the precedence tests plus the documented limit already make the
  behavior explicit and honest.

**Chosen because:** the untested precedence surface is the real coverage gap
(`pending` only ever compares release-vs-release, so a prerelease-ordering
regression ships silently today); the overflow is a documented boundary, not a
live risk. Proportionality: pin what can regress, document what cannot occur.

### D-7: require_ci as a default-preserving core knob  (N)

**Decision:** Add a core config knob `require_ci` (default `true`) read through
the config overlay. When `true`, the publish CI gate keeps today's strict
behavior (a null/NONE rollup — no positive CI confirmation — refuses). When
`false`, only the NONE case is relaxed to allow publish; a genuinely FAILING
or PENDING check (and the TOO_MANY unread-overflow case) stays fail-closed.

**Alternatives considered:**
- Docs only, no knob (a no-CI adopter adds CI or forks the script). Rejected
  because: the reported gap is that the strict default silently blocks a
  legitimate no-CI adopter from ever publishing via the script; a
  default-preserving opt-out is the minimal capability that unblocks them
  without weakening the default.
- Knob only, skip the README prose. Rejected because: it leaves the
  relabel-obligation and required-check gaps (the actual reported docs gaps)
  unaddressed.

**Chosen because:** `customization-boundary` — the general *capability*
(opt out of the CI-required refusal) lands in core as an opt-in with the
default unchanged, while the specific *value* (whether a given adopter turns
it off) stays the adopter's overlay choice. The relaxation is deliberately
narrow: it never turns a red or pending check green, only removes the
"no CI at all" refusal.

### D-8: REQ-D1.3 carve-out semantics restated by citation  (N)

**Decision:** Express the publish CI gate's window-lock carve-out semantics
(per-check evaluation with the release-window lock excluded, not the aggregate
`statusCheckRollup.state`) as REQ-C1.4 in this bundle, citing
`autopilot-reflex` REQ-D1.3 as the amended-by-citation Source. The
`autopilot-reflex` requirements text is not edited.

**Alternatives considered:**
- Reopen `autopilot-reflex` and amend REQ-D1.3 in place. Rejected because: the
  fold decision (D-1) chose a new spec precisely to keep the Done contract
  frozen; a new spec cannot edit a foreign bundle's frozen REQ, only restate
  its reading in its own REQ space.

**Chosen because:** it makes the spec text follow the code carve-out that
shipped in #163 (which REQ-D1.3's text never did — the confirmed line-201
gap), while honoring the stable-ID/supersession discipline: the frozen record
stays frozen, the new reading is a new ID that cites it.

### D-9: mise release-arm task, thin wrapper  (N)

**Decision:** Add a `[tasks.release-arm]` entry to `mise.toml` that invokes
`scripts/release-arm.sh` and forwards the required `<pr>` argument. The task is
a discoverability wrapper only; the script keeps no `mise` dependency and stays
directly invokable, matching the `release` task's relationship to
`release-publish.sh`.

**Alternatives considered:**
- Leave arm without a mise task (its required PR argument does not fit the
  zero-arg `mise run release` pattern as cleanly). Rejected because: the armed
  path being less discoverable than the fallback is the reported gap; mise
  tasks accept trailing arguments, so the PR number forwards fine.

**Chosen because:** it makes the faster armed path as discoverable as the
post-merge fallback with a thin wrapper that respects the portability floor.

### D-10: Adopter relabel obligation documented  (N)

**Decision:** Document in `templates/release-please/README.md` that an adopter
supplying their own publish step must also relabel the merged release PR from
`autorelease: pending` to `autorelease: tagged` (the work release-please's
skipped github-release step would have done), or release-please aborts the next
cycle's release PR with "untagged, merged release PRs outstanding".

**Alternatives considered:**
- Assume the adopter infers it from release-please's own docs. Rejected
  because: planwright's own publish path (`release-publish.sh`) does the
  relabel (issue #175's `relabel_release_pr`), so an adopter reading the
  bring-your-own-publish note has no signal that the relabel is a separate
  obligation — exactly the issue #173 class the observation names.

**Chosen because:** the template's whole job is to get an adopter to a working
release loop; omitting the cross-cycle relabel obligation makes the documented
path work for cycle 1 and deadlock on cycle 2.

### D-11: Item-9 verified finding + adopter caveat  (N)

**Decision:** Record the verified finding — this repository has no
branch-protection required status check on the release PR (checked via
`gh api`: no branch protection, and the default ruleset carries no
required-status-check rule) — and add an adopter caveat to
`templates/release-please/README.md`: making the `ci` check a required status
check on the release PR would deadlock it, because a `GITHUB_TOKEN`-authored
release PR raises no CI workflow run, so the required check never reports.

**Alternatives considered:**
- Design a code guardrail against the required-check deadlock. Rejected
  because: the deadlock is a property of an external branch-protection setting,
  not the tree; there is nothing in-repo to guard, and the setting is dormant
  here (verified). The honest deliverable is a documented caveat, not a guard
  against a non-existent configuration.

**Chosen because:** the item was flagged verify-first precisely because it
could not be confirmed from the tree; the verification resolved it (not a
required check), so the deliverable is the recorded finding plus the caveat
that keeps an adopter from configuring themselves into the deadlock.

### D-12: Resume relabel idempotency  (N)

**Decision:** On a resume where the GitHub Release already exists but the merged
release PR is still labeled `autorelease: pending`, `release-publish.sh`
(re-)performs the `pending` → `tagged` relabel instead of aborting with "already
published" before the relabel runs (REQ-B1.4). The relabel is idempotent
(create-if-missing, a no-op when already `tagged`).

**Alternatives considered:**
- Leave resume idempotency as-is (die "already published" once the origin tag
  and Release both exist). Rejected because: `relabel_release_pr` runs only
  after `gh release create`; a process killed — or a `gh` client error after a
  server-side success — between the two leaves the Release created but the PR
  stuck on `autorelease: pending`, with no code path that ever flips it, so
  release-please aborts every future cycle on "untagged, merged release PRs
  outstanding". The bundle owns the relabel obligation (REQ-G1.1/D-10), so
  leaving this window open contradicts its own goal.
- Defer to a follow-up spec (like the E3 stranded-partial edge). Rejected
  because: unlike E3 (which needs a multi-tag scan and a which-tag-to-resume
  design), this is a bounded in-place idempotency fix on a window the bundle's
  own resume + relabel deliverables create; the human chose to close it here at
  the kickoff lens pass.

**Chosen because:** it closes a concrete deadlock the lens pass found in the
exact interaction between REQ-B (resume) and REQ-G1.1 (relabel) that this bundle
owns, with a bounded idempotent-relabel change on the already-published resume
path.

## Cross-cutting concerns

- **Shared-file coordination.** REQ-C (rl_ci_state → publish + arm), REQ-B
  (resume path in publish), and REQ-G1.3 (`require_ci` in publish's CI gate)
  all touch `release-publish.sh`. Task ordering carries explicit edges so the
  shared-helper task lands before the knob task, and workers merge `main`
  between tasks; the regions edited are distinct (resume block vs CI gate vs
  the shared helper call site) so the coupling is sequencing, not logic.
  `release-lib.sh` is likewise shared by Task 1 (the in-code overflow comment on
  `rl_version_gt`), Task 2 (`rl_version_gt`'s error-status validation) and Task 3
  (the new `rl_ci_state` function): edges 1→2 and 1→3 serialize Task 1's
  co-edits/test-home ahead of the others, and Task 3's addition is a distinct
  region. Two further same-file, no-edge overlaps exist and are deliberate
  (distinct regions, merge `main` between tasks): `release-pending.sh` is
  touched by the fail-closed comparator status capture (REQ-A / Task 2) and the
  `version_file` canonicalization guard (REQ-D / Task 5); and `mise.toml` is
  touched by the `release-arm` task entry (REQ-F / Task 7) and the `lint:md`
  glob addition that wires the template-lint verification (REQ-G / Task 8). No
  edge is needed between either pair.
- **Fail-closed invariant.** Every new refusal path (comparator error, SHA
  mismatch, containment failure, CI query failure) exits non-zero with a
  diagnostic and no side effects, consistent with the pipeline's existing
  gates. The `require_ci=false` relaxation is the one deliberate narrowing, and
  it never turns a failing or pending check green.
- **Portability floor.** All new shell stays bash 3.2 / BSD-tooling portable
  under `LC_ALL=C`, no new runtime dependency (git, gh, jq only), per
  `autopilot-reflex` REQ-D1.9.
