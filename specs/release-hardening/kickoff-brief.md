# Release Hardening — Kickoff Brief

**Spec path:** `specs/release-hardening/`
**Spec commit at walkthrough start:** `fa8ac5c3c6f6cf4fa96422b84f302b7d0bcde124`
**Walkthrough date:** 2026-07-17
**Mode:** First activation
**Validator outcome (pre-flight):** clean — 0 error(s), 0 warning(s)
**Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true`
(defaults; no `.claude/planwright.local.yml` override)

## 2. Goal & glossary

**Restated goal.** `autopilot-reflex` (Done) shipped planwright's five-script
release pipeline (`release-pending.sh`, `release-window-check.sh`,
`release-publish.sh`, `release-arm.sh`, `release-lib.sh`). A 2026-07-16
ten-agent triage against v0.14.1 confirmed a nine-item backlog of correctness,
fail-closed, and coverage gaps that were surfaced-and-recorded during that
spec's execution but landed outside its task scope. This bundle closes exactly
that backlog as a focused hardening pass over the same five scripts, citing
`autopilot-reflex` as its Source rather than reopening it (D-1). Theme: **fail
closed and stay honest**.

**Rules out (firm):** never-auto-merge and the local + human-invoked
`release-publish.sh` invariant are untouched; `autopilot-reflex`'s frozen Done
contract is not reopened (REQ-D1.3's reading is restated by citation in
REQ-C1.4); the E3 stranded-partial recovery edge, the commits-since-last-tag
comparator extension, and the 64-bit overflow *guard* are out of scope
(documented/deferred, not coded).

**Assumes:** the `autopilot-reflex` REQ-D1.9 portability floor (bash 3.2 / BSD,
`LC_ALL=C`, no runtime dep beyond git/gh/jq); the existing per-script `tests/`
families run under `mise run check`.

**Glossary (implicit terms surfaced):**
- **comparator error (exit 2)** — a distinct new `rl_version_gt` status for a
  malformed/unusable operand, separate from "not greater" (exit 1) and
  "greater" (exit 0). The tri-state is the spine of REQ-A.
- **resume / partial publish** — origin tag present, GitHub Release absent; the
  path REQ-B hardens.
- **window-lock carve-out** — the release-window `window-lock` check is
  expected-red during the untagged window; the CI gate evaluates per-check with
  that one lock excluded, not the aggregate `statusCheckRollup.state`.
- **`git show` readers vs the filesystem reader** — only `release-pending.sh`
  reads `version_file` from the working tree (`<"$vf_path"`); the other three
  read via `git show <ref>:<path>` and are symlink-immune. REQ-D's
  canonicalization is scoped to the one filesystem reader.

Signed off: 2026-07-17

## 3. Requirements walkthrough

Seven REQ groups (A–G; see `requirements.md`). Per-group outcomes:

- **REQ-A — fail-closed comparator signaling.** Confirmed. `rl_version_gt` gains
  a distinct exit 2 for a malformed operand; both callers capture the status
  three-way (0 pending/open · 1 none/closed · 2 fail-closed exit 2). **Probe A
  (CORRECTED at the lens pass — my walkthrough claim was wrong):** I claimed a
  malformed origin tag reaches the comparator via the `latest` operand. It does
  not — `rl_latest_release_tag` filters invalid tags through `rl_valid_semver`
  (`release-lib.sh:239`), so `latest` is always valid and the exit-2 propagation
  is **unreachable via real inputs** in both `pending` and `window-check`.
  REQ-A1.2/A1.3 are honest **defense-in-depth** for a future non-validating
  caller (not the closing of a live fail-open); the tests fault-inject the
  status. See §8 cluster A.
- **REQ-B — resume integrity.** Confirmed, with one edit. **Probe B (applied):**
  REQ-B1.2's "skip when signature not required" wording was ambiguous against
  Task 4's "`auto` exercises re-verify". Tightened REQ-B1.2 to name the
  creation-time three-way explicitly (`require` → must verify; `auto` → verify
  iff the tag is signed; `never` → skip) and added the `auto` signed/unsigned
  cases to test-spec REQ-B1.2. Expression-level sharpening consistent with D-3.
- **REQ-C — `rl_ci_state` consolidation.** Confirmed. **Probe C (resolved):** the
  workflow-scoped exclusion drops a check only when `name == window-lock` AND
  `checkSuite.workflowRun.workflow.name == release-window`; a null-`workflowRun`
  namesake (non-Actions app check) fails the workflow test and is **judged**,
  never silently excluded — the fail-open surface REQ-C1.3 closes.
- **REQ-D — input hardening.** Confirmed. **Probe D (→ risk register):** the
  portable canonicalization must resolve the **leaf** component's symlink, not
  only the parent dir (`cd dirname; pwd -P` misses a symlinked
  `version_file` itself — the exact attack). Requirement-level "resolving
  symlinks" already covers it; captured as risk-register early-signal row R4 so
  Task 5 is tested against a leaf symlink.
- **REQ-E — comparator test coverage.** Confirmed. Pins the two-prerelease
  precedence surface `pending` never reaches (`release-lib.sh:129-159`);
  64-bit overflow (`release-lib.sh:125,151`) documented + boundary-tested, not
  guarded.
- **REQ-F — `mise run release-arm <pr>`.** Confirmed. Thin wrapper; script keeps
  no `mise` dependency.
- **REQ-G — adopter surface.** Confirmed. **Probe G (resolved):**
  `require_ci=false` relaxes **only** the NONE / no-positive-confirmation
  refusal; FAILING, PENDING, and TOO_MANY all stay fail-closed even under
  `false` (TOO_MANY means checks exist but exceed one page — the "no CI" opt-out
  must not apply).

**Consolidated spec-edit list (applied this walkthrough):**
1. `requirements.md` REQ-B1.2 — reworded to the explicit `require`/`auto`/`never`
   re-verify three-way (Probe B).
2. `test-spec.md` REQ-B1.2 — added the `auto` signed (verify runs) and unsigned
   (verify skipped, resume proceeds) test cases (Probe B).

Signed off: 2026-07-17

## 4. Design walkthrough

Every D-ID accounted for; no design decision contradicts a walked requirement
(no inconsistency halt). Reconciled ledger (see `design.md`):

| D-ID | Decision | Maps to | Status |
| --- | --- | --- | --- |
| D-1 | New spec citing autopilot-reflex, not a reopen | REQ-C1.4 | Confirmed |
| D-2 | Fail-closed comparator via distinct exit 2 | REQ-A | Confirmed |
| D-3 | Resume = SHA assert + signature re-verify | REQ-B | Confirmed (REQ-B1.2 wording sharpened toward D-3; no D-ID change) |
| D-4 | One `rl_ci_state`, workflow-scoped exclusion | REQ-C | Confirmed |
| D-5 | Portable canonicalization, scoped to fs reader | REQ-D | Confirmed (leaf-symlink constraint → risk R4) |
| D-6 | Document overflow, pin precedence surface | REQ-E | Confirmed |
| D-7 | `require_ci` default-preserving core knob | REQ-G1.3 | Confirmed |
| D-8 | REQ-D1.3 carve-out restated by citation | REQ-C1.4 | Confirmed |
| D-9 | `mise release-arm`, thin wrapper | REQ-F | Confirmed |
| D-10 | Adopter relabel obligation documented | REQ-G1.1 | Confirmed |
| D-11 | Item-9 verified finding + adopter caveat | REQ-G1.4 | Confirmed |

**Altitude determination:** no trigger fired (the `design.md` altitude note
concurs). `autopilot-reflex` was the doctrine-altitude deliverable; this bundle
is mechanism hardening of an already-doctrine'd surface. The one candidate, the
`require_ci` knob (D-7), instantiates existing `customization-boundary` doctrine
rather than minting new doctrine. Untriggered → no altitude D-ID required
(`proportionality`); recorded not-applicable, verified at the sign-off altitude
check.

**Cross-cutting concerns** (shared-`release-publish.sh` coordination via edges
3→4 and 3→6; fail-closed invariant on every new refusal path; portability
floor) reviewed and sound; the parallel-Tasks-4-&-6 sequencing detail is
carried to section 6.

Signed off: 2026-07-17

## 5. Verification approach

**Coverage mix** (per `test-spec.md`, 20 REQ entries after the lens pass added
REQ-B1.4): heavily `[test]` (the
scripts are portable shell with per-script `tests/` families run by
`mise run check`), with `[design-level]` for the two non-executable
requirements (REQ-C1.4 restatement-by-citation, REQ-G1.4 point-in-time
external-state finding), `[manual + design-level]` for the two README prose
docs (REQ-G1.1, G1.2), and `[test + design-level]` for the portability claim
(REQ-D1.2) and the documented overflow limit (REQ-E1.2).

**Harnesses confirmed present:** `test-release-{pending,window-check,publish,arm,mise-task}.sh`
all exist; `test-release-lib.sh` is correctly absent (Task 1 creates it,
guard-first). No orphaned test-file references.

**Verification ownership:** CI (`mise run check`) runs the `[test]` families and
the linters (`lint:shell`/`lint:fmt`/`lint:md`/…); the `[manual]` README reviews
(G1.1, G1.2) are swept by the kickoff/execution reviewer.

**Dead path found and resolved:** REQ-G1.1/G1.2 and Task 8's Done-when named a
markdown-lint-over-the-template CI verification, but `mise.toml:36`'s `lint:md`
glob is an allowlist that does not include `templates/` — the template READMEs
(`templates/release-please/README.md` and `templates/release-window/README.md`)
were unlinted and the named verification could not run. Resolved by folding a
`lint:md` glob addition (`templates/**/*.md`, covering both templates) into
**Task 8 deliverable (d)**, making the verification real and closing the
incidental gap that the adopter-facing templates shipped unlinted. test-spec
REQ-G1.1/G1.2 annotated; changelog entry added.

**Consolidated spec-edit list (this section):**
3. `tasks.md` Task 8 — deliverable (d) + Done-when: add `templates/**/*.md` to
   the `lint:md` glob.
4. `test-spec.md` REQ-G1.1, REQ-G1.2 — annotated that the CI-lint claim is made
   real by the Task 8 glob addition.

Signed off: 2026-07-17

## 6. Task graph

Reconstructed from the `Dependencies:` lines in `tasks.md` (authoritative;
figures derived from that file, not transcribed):

- **Roots (no deps):** Task 1, Task 5, Task 7 — 3-wide parallelism at the start
  (Task 3 gained a 1→3 edge at the lens pass: its tests live in the
  `tests/test-release-lib.sh` file Task 1 creates).
- **Edges:** 1→2 (guard-first: Task 1 creates `tests/test-release-lib.sh`, Task
  2 extends it); **1→3** (Task 3's `rl_ci_state` tests live in that same file);
  3→4 and 3→6 (shared `release-publish.sh`; the `rl_ci_state` refactor lands
  first, and Task 6's `require_ci` logically sits on the consolidated verdict);
  6→8.
- **Critical path (effort-weighted): ~3.0 days** via `1→3→4` (Task 4 grew to
  1.5d at the lens pass for the origin-object fetch + relabel idempotency); the
  other long chain `1→3→6→8` is 2.5d. Total effort ≈ 5.75d (see `tasks.md`
  per-task estimates); wall-clock floor ≈ 3.0d given enough workers.

**Deliberate non-edges + shared-file coordination** (recorded so no worker
"fixes" a missing edge into existence; all pairs edit distinct regions and
merge `main` between tasks):

| File | Tasks | Edge | Coupling |
| --- | --- | --- | --- |
| `release-lib.sh` | 1, 2, 3 | 1→2, 1→3 | 1 & 2 sequence on `rl_version_gt`; 3 adds `rl_ci_state` (distinct), gated behind Task 1's test-file creation |
| `release-pending.sh` | 2, 5 | none | status capture vs `version_file` guard |
| `release-publish.sh` | 3, 4, 6 | 3→4, 3→6 | resume block vs CI gate vs helper call site |
| `mise.toml` | 7, 8 | none | `[tasks.release-arm]` vs the `lint:md` glob (both now recorded in `design.md`) |

The `mise.toml` {7, 8} overlap was introduced by this walkthrough's Task 8
dead-path fix and is now recorded in `design.md`'s Shared-file coordination
note (edit 5 below).

**Consolidated spec-edit list (this section):**
5. `design.md` Cross-cutting concerns — Shared-file coordination note extended
   to name the `release-pending.sh` {2,5} and `mise.toml` {7,8} no-edge
   overlaps.

Signed off: 2026-07-17

## 7. Risk register

**`decision-domains` gap check** (catalog resolved via
`scripts/resolve-catalog.sh decision-domains`, 11 seed domains, no overlay
additions present): the spec touches api-surface, auth, secrets-config,
queues-async, deploy-migration, dependency-adoption, and versioning-scheme —
each **decided** in-bundle or inherited-and-instantiated from `autopilot-reflex`
(E3 stranded-partial is *decided-to-defer*, not undecided). data-storage,
caching, concurrency are **not touched**. One genuine undecided gap surfaced:
**observability** → R6, resolved below.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| R1 | `rl_ci_state` consolidation regresses publish's CI gate (rewrites the `autopilot-reflex`-frozen `ci_green`) | REQ-C1.2 same-verdict-string test (publish == arm for same SHA) + preserved green/failing/pending/none/too-many behavior tests (Task 3) |
| R2 | Window-lock exclusion **under**-excludes → the real `release-window` lock is judged red → publish deadlocks in the untagged window | REQ-C1.3 test must assert the **real** `release-window`/`window-lock` check is excluded (Actions checks populate `workflowRun`) *and* a foreign namesake is judged |
| R3 | Shared-file merge regressions: `release-lib.sh` {1,2,3}, `release-pending.sh` {2,5}, `release-publish.sh` {3,4,6}, `mise.toml` {7,8} | task edges + distinct-region design (design.md cross-cutting) + workers merge `main` between tasks |
| R4 | **Leaf-symlink** canonicalization misses the attack | **Design recipe fixed at lens pass** — D-5 + REQ-D1.1 now mandate leaf-component resolution + reading the canonicalized path (the parent-dir-only recipe was insufficient); Task 5 test must include a `version_file` that is itself an escaping symlink |
| R5 | `rl_version_gt` exit-2 contract reaches all 7 callers; the propagation is unreachable via real inputs | **Corrected at lens pass** — every caller pre-validates (`rl_latest_release_tag` filters `latest`), so exit 2 is unreachable everywhere today; REQ-A1.2/A1.3 reframed as honest defense-in-depth, tested via fault injection (cluster A) |
| R6 | Observability gap — `require_ci=false` relaxed publish on NONE left no signal that CI was absent | **RESOLVED** — REQ-G1.3 stderr diagnostic on the relaxed NONE publish; Task 6 + test-spec deliver and assert it |
| R7 | Resume verified the wrong/absent tag object (local `git tag -v` vs the published origin tag; fresh-clone has no local tag) | **Fixed at lens pass** — REQ-B1.1/B1.2 fetch and target the **origin** tag object; Task 4 + test-spec cover the fresh-clone resume (cluster B) |
| R8 | Resume after `gh release create` but before relabel → dies "already published" → release-please deadlock | **Fixed at lens pass** — new REQ-B1.4 / D-12 makes the resume relabel idempotent; Task 4 + test-spec assert it (cluster B) |
| R9 | `require_ci=false` relaxes the whole NONE verdict, folding all-NEUTRAL/SKIPPED checks, not just "no CI" | **Accepted + tested at lens pass** — deliberate (all three sub-cases are "no positive confirmation", the diagnostic fires); query-failure stays fail-closed; test-spec REQ-G1.3 covers the all-skipped sub-case (cluster C) |
| R10 | Signing-policy change between the failed publish and the resume (unsigned tag + resume under `require`) makes a legit partial-publish unresumable | **Accepted risk** (B4) — defensible fail-closed behavior; out of scope for this bundle's resume hardening (recorded in D-3 / tasks.md Out of scope) |
| R10b | Under `auto`, an unsigned origin tag at the pinned release SHA is accepted on resume (no cryptographic provenance) | **Accepted risk** (panel GEM-2) — `auto` is best-effort and the SHA is pinned by REQ-B1.1; an operator wanting a guaranteed signature on resume uses `require` (REQ-B1.2, D-3) |

No open questions remain. R6 resolved to a decision; R4/R5/R7/R8 fixed at the
lens pass; R9/R10 accepted (R9 tested); R1–R3 to mitigations/early signals. No
inconsistency halt.

**Consolidated spec-edit list (this section):**
6. `requirements.md` REQ-G1.3 — added the `require_ci=false` relaxed-path stderr
   diagnostic clause; `tasks.md` Task 6 + `test-spec.md` REQ-G1.3 updated to
   deliver and assert it (R6).

Signed off: 2026-07-17

## 8. Sign-off

**Scope:** first activation, full bundle. Meaning-class (adds new REQ-B1.4 and
D-12; tightens REQ-B1.2, REQ-G1.3; reframes REQ-A1.2/A1.3).

### Lens review pass (Discovery-Rigor)

**Fan-out path taken:** one read-only sub-agent per canonical lens (6 agents:
correctness, security, error-handling+concurrency, tests/verification,
cross-file consistency, docs+naming/spec-format), each briefed to be exhaustive
within its single lens with severity-pruning forbidden. Findings merged,
de-duplicated, and validated — the high-severity items are triple-lens
convergent (independently found by security, correctness, and error-handling
agents) and code-grounded against the actual scripts.

**Canonical lens-coverage table:**

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 6 | REQ-A unreachable; Task 4↔REQ-B1.2 contradiction; auto-verify-failure unspecified; resume tag object; "excludes templates" wrong belief; policy-change edge |
| Security | 7 | leaf-symlink *recipe* wrong; wrong tag object verified; auto trusts unsigned on signed repo; require_ci widens to skipped; REQ-A threat nonexistent; spoofable workflow.name; echo discipline |
| Error handling & failure modes | 4 | REQ-A unreachable; resume wrong/absent object; relabel deadlock on resume; require_ci omits query-failure |
| Concurrency / state | 2 | all four shared-file overlaps verified sound (PASS); REQ-C1.2 "resolve identically" over-claims |
| Naming, readability, structure | 1 | CI-verdict vocabulary drift across files |
| Documentation | 3 | options-reference path unnamed; required-check remedy abstract; REQ-G1.4 tag |
| Tests / verification | 4 | missing 1→3 edge; Task 3 Done-when omits query-failure; glob lints 2nd template; all REQs pinned ✓ |
| Cross-file consistency | 3 | design.md omits release-lib.sh {1,2,3}; REQ-G1.1 mis-cites 181; REQ-C1.3 over-cites 201 |
| Artifact data-hygiene (`security-posture`) | none | clean — only obs-IDs, issue #s, SHAs, `file:line` refs; no secrets/hostnames |

**Kickoff altitude check (REQ-H1.3):** determined bundle-locally from the pinned
seed claims in `requirements.md` `## Sources` — no altitude trigger fired
(`autopilot-reflex` was the doctrine-altitude deliverable; this bundle is
mechanism hardening of that already-doctrine'd surface, every fix instantiating
existing doctrine). **Untriggered → not applicable**, no altitude D-ID required
(`proportionality`); consistent with the `design.md` altitude note.

### Findings and dispositions

All findings validated per `validation-rigor` (triple-lens convergence for the
HIGH items + direct code grounding). Dispositioned with the human across five
clusters plus one late-clustered HIGH finding:

- **Cluster A — REQ-A honesty (applied):** REQ-A1.2/A1.3 + D-2 reframed as
  defense-in-depth (the exit-2 propagation is unreachable via real inputs — all
  callers pre-validate); test-spec retargeted to fault-injection;
  `sanitize_printable` mandated on the diagnostic; brief Probe A + risk R5
  corrected; "excludes templates" wording fixed.
- **Cluster B — resume integrity (thorough, applied):** REQ-B1.1 fetches +
  targets the **origin** tag object; REQ-B1.2 tightened (`auto` requires a valid
  signature when signing is configured; refuse on present-but-unverifiable);
  new **REQ-B1.4 + D-12** make the resume relabel idempotent (closes the
  release-please deadlock); Task 4 wording fixed and re-scoped (1→1.5d); B4
  (policy-change edge) accepted as risk R10.
- **Cluster C — require_ci scope (accept whole NONE + test + doc, applied):**
  REQ-G1.3 spells out all three NONE sub-cases (incl. all-NEUTRAL/SKIPPED) as
  relaxable, keeps FAILURE/PENDING/TOO_MANY/query-failure fail-closed; test-spec
  covers the all-skipped sub-case; leans on the R6 diagnostic for honesty.
- **Cluster D — task-graph & stragglers (applied):** 1→3 edge added (Task 3's
  tests live in Task 1's file; critical path → ~3.0d); Task 3 Done-when gains
  the query-failure test; Task 8 glob covers both templates; design.md note gains
  `release-lib.sh` {1,2,3}; REQ-C1.2 reworded to "same verdict string" + notes
  the deliberate query-failure divergence.
- **Cluster E — citations & doc nits (applied):** options-reference path named;
  CI-verdict vocabulary pinned in REQ-C1.1; REQ-G1.4 tag → `[manual +
  design-level]`; mis-citations dropped (legacy 181 from G1.1, 201 from C1.3);
  PAT/App-token remedy named; echo-discipline mandated; workflow-`name`
  spoofability recorded as a documented limit in REQ-C1.3.
- **S1 — leaf-symlink design recipe (late-clustered, applied):** D-5's recipe
  corrected to resolve the leaf component's symlink and read the canonicalized
  path (the parent-dir-only recipe shipped the bypass); REQ-D1.1 + Task 5
  strengthened.

No finding left undispositioned; no inconsistency halt. Validator: 0/0 after the
rework; `markdownlint-cli2` clean over the bundle.

Class: meaning
Lens-pass: §8 "Lens review pass" (6-lens fan-out, table above, all findings dispositioned)
Anchor: `ea81bec0827694a572e33ab7b24e3524d7431498` — computed as
`scripts/spec-anchor.sh specs/release-hardening`

## 9. Amendment log

### Amendment 1 — panel pass corrections (2026-07-17)

Independent-model panel pass (`panel-review --nested`, gemini backend) over the
signed bundle — the additional-verification pass before the terminal ready-flip.
It found the lens-pass `auto`-signing mechanism (REQ-B1.2) broken cross-machine,
plus three clear fixes. Pre-merge corrections on the spec PR, amended in place,
dispositioned with the human:

- **GEM-2 (auto semantics, human judgment):** the resume re-verify keyed off the
  *resuming machine's* signer config, which wrongly skips verifying a signed tag
  on a fresh clone and wrongly rejects a legit unsigned tag on a configured
  machine. Corrected to key off the **origin tag's own signedness**: `require`
  mandates a valid signature; `auto` verifies iff the tag is signed (accepts an
  unsigned tag at the pinned SHA); `never` skips. Guaranteed-signature-on-resume
  lives in `require`. New accepted risk R10b.
- **GEM-1 (origin-fetch, applied):** REQ-B1.1/Task 4 fetch the origin tag object
  to a **distinct verification ref** (a same-named local tag clobbers/shadows
  it); repro-confirmed (`git fetch refs/tags/X:refs/tags/X` → "would clobber
  existing tag").
- **GEM-5 (applied):** `require_ci` value validated as boolean, symmetric with
  `require_signed_tags` (REQ-G1.3 / Task 6 + test).
- **GEM-6 (applied):** test-spec REQ-C1.1 aligned to the canonical verdict names.
- **Dropped (FP/covered):** jq null-index is null-safe (not a crash); the
  design.md `release-lib.sh` {1,2,3} note is already present (`design.md:342`);
  the two concurrency overlaps are already documented.

Files touched: `requirements.md` (REQ-B1.1, REQ-B1.2, REQ-G1.3, changelog),
`design.md` (D-3), `tasks.md` (Task 4, Task 6), `test-spec.md` (REQ-B1.1,
REQ-B1.2, REQ-C1.1, REQ-G1.3). Validator 0/0; `markdownlint-cli2` clean.

Class: meaning
Lens-pass: panel pass (gemini via `panel-review --nested`); GEM findings validated three-pass (incl. a git repro for GEM-1) and dispositioned above
Anchor: `cce1d153e505b957fe2f863fed3e5c3ff1137c7e` — computed as
`scripts/spec-anchor.sh specs/release-hardening`

### Amendment 2 — panel pass iter 2, defensive tail (2026-07-17)

Confirmation panel pass (gemini iteration 2) over Amendment 1. **Result: the
corrected `auto`-trust model is sound** — the Security lens raised nothing beyond
the accepted R10b, and Cross-file consistency returned "none — exceptional
alignment". Four defensive-tail refinements applied (all clear fixes,
dispositioned with the human); the panel is treated as converged (further
iterations yield only diminishing incremental nits):

- **I2-1 (applied):** REQ-B1.1/Task 4 force-update a reserved verification ref
  (`refs/release-verify/<tag>`) and clean it up — a stale ref from an aborted
  resume would otherwise block the next fetch.
- **I2-2 (applied):** REQ-B1.2 treats a lightweight tag (no tag object) as
  unsigned — accepted under `auto`, refused under `require`, never fed to
  `git tag -v` (which errors on a non-tag object).
- **I2-4 (applied):** REQ-G1.3 validates `require_ci` at config-read time
  (unconditional), not lazily inside the CI gate the resume path skips.
- **I2-8 (applied):** REQ-D1.1/D-5 treat a dangling/broken symlink or loop as a
  clean exit-2 refusal.
- **Dropped:** R10b re-flag (accepted); `release-window/README.md` docs (FP — the
  relabel/CI obligations are release-please-specific); a test-stub detail.

Files touched: `requirements.md` (REQ-B1.1, REQ-B1.2, REQ-G1.3, REQ-D1.1,
changelog), `design.md` (D-5), `tasks.md` (Task 4, Task 5), `test-spec.md`
(REQ-B1.2, REQ-D1.1). Validator 0/0; `markdownlint-cli2` clean.

Class: meaning
Lens-pass: panel pass iter 2 (gemini); model confirmed sound, defensive-tail findings validated and dispositioned above
Anchor: `23c587e30863b4a8614c9ac65745f0143cec4860` — computed as
`scripts/spec-anchor.sh specs/release-hardening`

### Re-anchor — anchor-scope exclusion sweep (2026-08-24)

Machine-written entry per the meta-spec's expression-only lane
(`doctrine/spec-format.md`, *Writers*), recorded by the coordinated sweep
that lands with the hash-scope change (anchor-integrity D-3, REQ-A1.4).

**Why the anchor moved:** the hash scope changed, not this bundle's
content. The per-file digests for `requirements.md`, `design.md`, and
`test-spec.md` now drop the header-block `**Status:**` line, so every
bundle carrying one recomputes to a new value. Verified by isolation:
recomputing under the amended semantics over this bundle as it stood at the
prior entry's commit (`c6bd51b`) yields the same hash recorded below, so no
anchored byte has changed since that entry was written.

**Cites the changelog line:** the 2026-07-26 `## Changelog` entry in
`doctrine/spec-format.md` ("Anchor-scope exclusion"), the doctrine half of
the change this entry re-anchors against.

Class: expression-only
Anchor: `dfcf35014c58620b9b0a2f954c57bb3a135add0b` — computed as
`scripts/spec-anchor.sh specs/release-hardening`

### Amendment 3 — release-please bootstrap race (2026-08-25)

The bundle grows a fourth surface. On 2026-07-30, minutes after v0.33.0 was
published, release-please opened PR #339 proposing a bogus bump whose diff
re-listed 124 already-released commits; the run log shows it looking for the
v0.33.0 tag three seconds before the signed tag existed, then falling back to
`bootstrapSha` and regenerating from near the start of history. Two defects,
recorded as obs:fd6c2f4f: the workflow fires on `ci` completing on main, which
for a release commit is exactly the interval where the tag deliberately does
not exist yet — so every release passes through it — and release-please
bootstraps rather than failing loudly whenever it cannot see the latest
release, so any cause of that (API blip, rate limit, permissions change,
deleted tag) yields the same plausible merge-ready proposal.

This delta was first written as PR #340 and recut here onto its own spec branch
as PR #353. It adds **REQ-H** (release-proposal integrity), **D-13** (gate the
workflow on the existing window check) and **D-14** (judge the proposal, not
only the trigger), and **Tasks 9-10**. Meaning-class by the REQ-A3.3 axis:
new REQs and new D-IDs. Pre-merge amendment — nothing signed has shipped, so
the records are amended in place per the meta-spec's scope rule and PR #353 is
the review surface.

**Lens review pass (Discovery-Rigor), delta-scoped.** Walked inline over the
143-line delta against `origin/main` (four files, one new REQ group, two
decisions, two tasks), not a full-bundle re-walkthrough. Findings validated
three-pass before reporting: read against the actual scripts and workflows,
cross-checked from the callers and the sibling `release-window.yml`, and
grounded outside the diff in the observation store and the shipped exit-status
contracts. `spec-validate` 0/0 and `markdownlint-cli2` clean both before and
after the rework.

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 2 | REQ-H1.1/D-13 read the window check's *non-zero* exit as "window open", but 1 is the window and 2 is fail-closed-could-not-tell; Task 9 omitted the checkout the guard needs, and a tagless one reads "no releases yet, window open" and skips every run |
| Security | 1 | the checkout Task 9 needs lands in a `contents: write` `workflow_run` job whose branch filter a fork PR can satisfy (obs:131af768) |
| Error handling & failure modes | 1 | same as correctness item 1, from the other side: folding exit 2 into the skip re-opens the fail-open REQ-A/D-2 exist to close |
| Performance | none | one added script invocation in a CI job that already runs for minutes |
| Concurrency / state | 1 + 1 PASS | `mise.toml` overlap is now {7, 8, 10}, recorded in `design.md`; D-13's "self-clears" claim verified sound — the `release-window` lock holds merges shut for the whole span the guard skips, so no proposal is dropped |
| Naming, readability, structure | 1 | the REQ-H group theme named the untagged window, under-describing the deliberately cause-agnostic REQ-H1.2/H1.3 |
| Documentation | 3 | no `## Scope` bullet for REQ-H and a Goal that still framed the pass as five scripts; no `## Changelog` entry; no `## Sources` entry for obs:fd6c2f4f |
| Tests / verification | 2 | `test-spec.md` REQ-H entries carried no `## REQ-H` group heading and sat under REQ-G; Task 9 said "the workflow test family" where every sibling task names its file |
| Cross-file consistency | 2 | REQ-H1.2 said "older than" where D-14, Task 10, and the test-spec said "at or older", and the basis (SemVer precedence vs entry date) was never pinned; `design.md`'s altitude note cites a foreign `REQ-H1.1` that now collides with this bundle's own |
| Artifact data-hygiene (`security-posture`) | none | obs UIDs, PR numbers, version strings only; no secrets, tokens, or hostnames |

**Dispositions.** All applied on the branch; none deferred, none dropped.

- **The tri-state exit (correctness + error handling, applied).** REQ-H1.1 and
  D-13 now split `release-window-check.sh`'s three statuses instead of testing
  non-zero: 0 proceeds, 1 skips the job, 2 fails it. The script's own header
  documents 2 as "usage error, or the comparator failed (FAIL CLOSED)", and
  REQ-A1.3 in this very bundle exists to mint that distinct status — a guard
  that skipped on both would launder an unreadable state into a green no-op.
- **The missing checkout (correctness, applied).** `release-please.yml` has no
  `actions/checkout` today, and `rl_latest_release_tag` reads local
  `git tag -l`. Task 9 now carries the checkout and the explicit
  `git fetch --force --tags origin +refs/heads/main:refs/remotes/origin/main`
  that `release-window.yml` already proves out, with the failure mode named:
  a tagless checkout reports "no release tags yet, window open" and skips the
  job forever, silently.
- **The privileged checkout (security, applied).** That job holds
  `contents: write` and `pull-requests: write`. obs:131af768 records that its
  `head_branch == 'main'` filter is satisfiable by a fork PR whose head branch
  is named `main`, and that `guard-coverage` D-6 accepted the residual
  *because* the job checks out no PR code — a premise Task 9 would otherwise
  remove. D-13 and Task 9 now pin the checkout to the repository's own default
  branch and forbid `github.event.workflow_run.head_sha`. The adjacent
  `head_repository.full_name == github.repository` clause the observation
  proposes stays out of scope: it belongs to `guard-coverage` D-6, and the
  default-branch pin is sufficient here (see the human note below).
- **The comparison basis (cross-file consistency, applied).** REQ-H1.2's
  "older than" is now "at or below the latest release tag" everywhere, and all
  four files pin the comparison to SemVer precedence through
  `rl_latest_release_tag` / `rl_version_gt` — the one definition
  `autopilot-reflex` REQ-D1.8 owns — rather than to the entries' dates, which
  a regenerated changelog restamps. `test-spec.md` gains a third fixture
  (fresh dates, already-released versions) so a date-based implementation
  cannot pass the suite.
- **Bundle framing (documentation, applied).** REQ-H is the one part of this
  pass that reaches past the five scripts it was scoped to, onto the proposal
  end of the same pipeline. `## Scope` gains its bullet, the Goal records the
  extension, `## Sources` gains obs:fd6c2f4f and obs:131af768, and the
  `## Changelog` gains the dated meaning-class entry this ritual requires.
- **Structure and naming (applied).** `test-spec.md` gains the `## REQ-H`
  group heading its entries were missing (they sat under REQ-G); the group is
  retitled "release-proposal integrity", dropping the untagged-window
  qualifier that under-described REQ-H1.2/H1.3; the test-spec intro drops its
  "the two non-executable requirements" count, now three; Task 9 names
  `tests/test-release-please.sh` instead of "the workflow test family";
  `design.md`'s Shared-file coordination note adds Task 10 to the `mise.toml`
  overlap.
- **The REQ-H1.1 collision (cross-file consistency, applied where editable).**
  `design.md`'s altitude note cites `autopilot-reflex` REQ-H1.1, which this
  delta gives a local namesake; the note now qualifies the namespace on both
  IDs. §8's "Kickoff altitude check (REQ-H1.3)" above has the same collision
  and is deliberately left alone: everything above this log is append-only
  after sign-off. Read it as `autopilot-reflex` REQ-H1.3, per the meta-spec's
  rule that foreign IDs are always namespace-qualified.

**For the human, not decided here.** Whether `guard-coverage`'s accepted
residual (obs:131af768's `head_repository` clause) should now be closed rather
than left accepted, given that Task 9 makes this job check code out for the
first time. The default-branch pin makes the residual no worse than it is
today, so nothing here blocks; the question is whether the observation should
be re-mined into `guard-coverage` rather than staying accepted.

**Human classification and sign-off is the merge of PR #353.** This is a
pre-merge amendment, so the PR is the review surface: approving and merging it
is the human act that classifies this delta as meaning-class and signs the
record, exactly as the scope rule prescribes for corrections on a spec's own
PR.

Files touched: `requirements.md` (Goal, Scope, REQ-H1.1, REQ-H1.2, Changelog,
Sources), `design.md` (altitude note, D-13, D-14, Cross-cutting concerns),
`tasks.md` (Task 9, Task 10), `test-spec.md` (intro, REQ-H group heading,
REQ-H1.1, REQ-H1.2). `spec-validate` 0/0; `markdownlint-cli2` clean.

Class: meaning
Lens-pass: §9 "Amendment 3" — the delta-scoped lens review above, canonical
table and all dispositions recorded in this section
Anchor: `c8502e7ece784bcde91f69dec9d9a09b2bd5f8f5` — computed as
`scripts/spec-anchor.sh specs/release-hardening`

### Re-anchor — REQ-H1.3 finding recorded (2026-08-26)

Machine-written entry per the meta-spec's expression-only lane
(`doctrine/spec-format.md`, *Writers*), recorded by `/execute-task` on Task 10.

**Why the anchor moved:** `requirements.md` gained the `## Changelog` entry
REQ-H1.3 commissions. REQ-H1.3's whole obligation is "establish and record the
fact"; recording the established fact executes an accepted decision rather than
changing one, so the delta is expression-only. No requirement, decision, or
task text was edited — in particular D-14's `Alternatives considered:` entry
for "Remove `bootstrap-sha` outright" is left exactly as signed, because the
finding vindicates its reasoning rather than revising it.

**Cites the changelog line:** the 2026-08-26 `## Changelog` entry in
`requirements.md` ("REQ-H1.3 finding, recorded (Task 10): removing
`bootstrap-sha` is NOT safe, and the key stays").

Task 10's other half (REQ-H1.2) is **not** delivered: it halted on
meaning-class contract drift, recorded in `tasks.md` `## Awaiting input` and
routed to a `/spec-kickoff` delta re-walkthrough. That entry sits outside the
anchor's `tasks.md` extraction (task-definition content only), verified by
isolation: with the `requirements.md` edit set aside, the bundle recomputes to
`c8502e7e`, the prior entry's value.

Class: expression-only
Anchor: `00bb891f207f57dfc74c0440c9995cacb592521a` — computed as
`scripts/spec-anchor.sh specs/release-hardening`

### Re-anchor — merge-commit clause corrected in the REQ-H1.3 finding (2026-08-26)

Machine-written entry per the meta-spec's expression-only lane
(`doctrine/spec-format.md`, *Writers*), recorded by `/panel-review` on Task 10.

**Why the anchor moved:** one supporting clause of the `## Changelog` entry
above was factually wrong. It read "this repo squash-merges, so it holds no
merge commits at all"; `origin/main` holds 18. The measurement behind it
(`git rev-list --merges --count`, cited in commit `78c0218`) was taken over
`71ea089f..HEAD`, which returns 0, but the claim it supports is about the walk
*past* `71ea089f` — and all 18 merge commits sit in `root..71ea089f`, exactly
the segment an unbounded walk would newly cover. The clause now scopes the
measurement to the range it was taken over and states the count for the rest.

**What did not change:** the finding's conclusion, which never depended on the
clause. The scan cap is on the branch's commit history rather than on merge
commits either way, all 433 commits sit inside the 500 cap, and removing
`bootstrap-sha` still walks to the root commit with no loud failure. The key
stays; D-14 is untouched.

**Also corrected, anchor-neutral:** the `## Awaiting input` bullet in
`tasks.md` led with an em-dash, which `sanitize_printable`'s C1 byte-range
strip mangles into a replacement character in `mise run status` (documented as
the intended trade in `scripts/echo-safety.sh`, so the fix belongs on the
authoring side). Now a colon. Re-verified by isolation with that edit in
place: with the `requirements.md` edit set aside, the bundle still recomputes
to `c8502e7e`.

Class: expression-only
Anchor: `99502f9688a480ff4b3fbbe23d3c014acf907355` — computed as
`scripts/spec-anchor.sh specs/release-hardening`
