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

(none yet — first-activation sign-off recorded in §8.)
