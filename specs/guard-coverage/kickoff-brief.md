# Guard Coverage — Kickoff Brief

**Spec:** specs/guard-coverage
**Spec commit at walkthrough start:** 7a4ef7f921cd38e7d4ab24bcb067337ffab12228
**Walkthrough date:** 2026-07-17
**Mode:** first activation (Status Draft, no prior brief)
**Validator:** `scripts/spec-validate.sh specs/guard-coverage` — 0 errors, 0 warnings (Draft)
**Config:** `commit_on_kickoff: true` · `mark_spec_pr_ready_on_kickoff: true` (defaults; local overlay overrides neither)
**Format-version:** 2 (stored status rests at Ready after sign-off; Active/Done derived)
**Rule docs:** all seven resolved via `scripts/resolve-rule-doc.sh` (core layer, 0.14.1 cache — byte-identical to this repo's `doctrine/` copies, verified at pre-flight)

## 2. Goal & glossary

**Restatement.** guard-coverage converts nine triage-confirmed (2026-07-16)
holes in the invariant-protection layer into mechanical guards (CI checks,
repo-side git hooks) or recorded audit decisions, plus one doctrine
amendment (the Performance lens learns to see whole-system test/CI rot).
The meta-goal: regressions in the layer that protects the hard invariants
and CI-honesty guarantees become tool-caught rather than vigilance-caught.

**Rules out.** Patching/re-implementing Claude Code's matcher (modeled as a
test oracle only); promoting deny globs to a security boundary (hooks are
enforcement, globs defense-in-depth); isolated-runner redesign unless the
fork-PR audit demands it; automated pin-bumping; evals in CI under any flag;
suite-wide perf work beyond the named stragglers; adopter application;
reopening the three Done source bundles.

**Assumes.** (a) The 2026-07-16 triage's nine holes are the working
universe of guard gaps — completeness rests on that triage. (b) Claude
Code's matcher semantics are modelable from documentation (D-4). (c)
`core.hooksPath` wiring reaches every clone/worktree shape workers use
(D-3's absence check exists because this can fail silently).

**Implicit terms resolved.**

1. *Reference runner* = the GitHub Actions CI runner (where the gate
   enforces); D-8's 30–50% headroom is its noise margin.
2. *Agreed per-file target* (Task 6) = a rough ceiling agreed before/at
   Task 6, formalized by Task 7 from the post-split baseline; pressed
   again in the REQ-E group walk.
3. *Guard / guard inventory* = a mechanical, tool-grounded check wired
   into `mise run check`, a repo-side git hook, or CI; inventory = where
   guards are discoverable (check aggregate + guard catalog + docs).
4. *Tracked tree* (REQ-B1.1) = what `git ls-files` enumerates; untracked
   and ignored content is out of reach by design.
5. *House pattern* = a repo-wide scripting convention promoted from
   review-vigilance to a checked rule.

Signed off: 2026-07-17

## 3. Requirements walkthrough

All eight groups (A–H) walked. Per-group outcomes:

- **A (deny hardening).** Restated: fixture-tested matcher model +
  repo-side hooks as enforcement. Probed and closed: worker hook-bypass
  vectors (`--no-verify` any position; `git -c core.hooksPath=…` prefix,
  which also evades the literal-substring amend denies) added to
  REQ-A1.1/A1.2, Task 1's fixture table, and the deny-glob set. Policy
  confirmed: hooks bind humans too; `--no-verify` stays the human's
  deliberate escape hatch.
- **B (purged identifiers).** Probed: commit messages were outside the
  tracked-tree scope yet become permanent public history. Decision:
  Task 2's `commit-msg` hook additionally screens messages against the
  hashed seed list (hash compare needs no plaintext); REQ-B1.1 and
  Task 3 extended; Task 3 now depends on Task 2.
- **C (fork-PR).** Grounded against the three real workflows (ci,
  release-window: `pull_request` + `contents: read`, no secrets;
  release-please: `workflow_run` on main only). Decision: the secrets
  assertion targets stored secrets — `secrets.GITHUB_TOKEN` exempt, its
  privilege governed by the read-only-permissions assertion (which also
  covers the `github.token` alias spelling).
- **D (eval transitivity).** Grounded: one `depends` block today, no
  run-body task invocations. Decision: closure broadened to all mise
  edge kinds (`depends`, `depends_post`, `wait_for`) plus a run-body
  scan reusing the workflow pass's invocation-form matching.
- **E (wall-clock budget).** Circularity resolved: Task 6's PR proposes
  the per-file target from split feasibility, accepted at PR review;
  Task 7 formalizes budgets from the measured post-split baseline +
  30–50% headroom. Per-file budget = one ceiling for every file.
  Reference runner = GitHub Actions CI.
- **F (drift tethers).** Confirmed as specced; direction of truth for
  the capability contract is the prose table (registry changes require
  the doc edit first).
- **G (lint + house patterns).** Confirmed; gap-fill applied: CDPATH
  check scope extended to the new `hooks/` directory Task 2 introduces.
- **H (catalog).** Confirmed as specced.

**Consolidated edit list (all applied in place, Draft rules):**

1. REQ-A1.1 + Task 1 + test-spec A1.1: hook-bypass fixture rows and
   deny-glob additions (`--no-verify`, `git -c` prefix forms).
2. REQ-A1.2: globs extended to cover hook-bypass spellings.
3. REQ-B1.1 + Task 3 + test-spec B1.1: commit-msg message screening;
   Task 3 dependency none → 2.
4. REQ-C1.2 + Task 4 + test-spec C1.2: stored-secrets sharpening
   (GITHUB_TOKEN exempt).
5. REQ-D1.1 + Task 5 + test-spec D1.1: closure over all edge kinds +
   run-body scan.
6. Task 6 + test-spec E1.2: per-file target proposed/accepted in the
   Task 6 PR; reference runner named.
7. Task 10: CDPATH check scope gains `hooks/` (later corrected to
   `githooks/` in the §8 lens pass, when the hook dir was renamed).

Signed off: 2026-07-17

## 4. Design walkthrough

All 13 D-IDs accounted for; reconciled ledger:

- **Confirmed (4):** D-1, D-4, D-9, D-11 — rationale intact as drafted
  (D-9's split-target/budget terms were later clarified in the lens
  pass but the decision is unchanged).
- **Amended (9), each in place with a dated annotation:** D-2, D-3, D-5,
  D-6, D-7, D-8, D-10, D-12, D-13. The requirements-walk amendments were
  D-2/D-7/D-12; the kickoff lens pass (below) added the rest. D-6 is
  amended (not confirmed as first recorded here): the stored-secrets
  sharpening and `workflow_run` hardening changed its check clause.

No design decision contradicts a walked requirement.

Signed off: 2026-07-17 (design ledger reconciled against the lens pass)

## 5. Verification approach

Coverage mix reviewed per `test-spec.md`'s intro (nineteen REQs after
the lens pass added REQ-H1.3; counts cited from that file, not copied
forward): `[test]`-including majority, four mixed entries (A1.3, B1.2,
H1.1, H1.2), one pure `[manual]` (C1.1), one pure `[design-level]`
(E1.3). Ownership: `[test]` runs in GitHub Actions CI via
`mise run check` (ci.yml runs the same tasks); `[manual]` sweeps are the
human's at task-PR review (C1.1 audit record at the Task 4 PR; A1.3
fresh-clone/worktree install exercise at the Task 2 PR); `[design-level]`
reviews land at the shipping PR (E1.3 at Task 8; H1.1/H1.2 design-level
arms at Task 11). B1.2's caveat review and H1.1's framing review are
satisfied by this walkthrough (D-5, D-13 walked and signed).

Dead paths: none — every named verification can run. Execution notes:
Task 3's "runs green in fork-PR CI" is end-to-end verifiable only once a
real fork PR exists (fixture verification suffices pre-merge); the
pre-push hook tests need a scratch bare remote in fixtures.

Signed off: 2026-07-17

## 6. Task graph

Reconstructed from the `Dependencies:` lines (authoritative; render on
demand via `scripts/spec-graph.sh`). The lens pass re-ordered Task 7 to
gate on the full fixture-bearing suite, changing the graph from the
walkthrough reading. Current shape: roots 1, 2, 4, 5, 6, 8, 9, 10;
Task 3 depends on 2; Task 7 depends on 1, 2, 3, 4, 5, 6, 9, 10 (all
fixture/check-adding tasks, so budgets see the whole suite); Task 11
depends on 1, 2, 3, 4, 5, 7, 9, 10 (Task 11 feeds directly on 2 as well
as via 3 — both edges are real: 2 ships the hook guard 11 registers).
Effort-weighted critical path now runs through Task 7's widened
dependency set (2 → 3 → 7 → 11), ~4.5 days.

Deliberate non-edges (do not "fix"):

- Task 11 does not depend on 6 — the split ships no guard; its output
  matters only via 7.
- Neither 7 nor 11 depends on 8 — a doctrine amendment, not a guard.
- Task 1 is independent of Task 2 — the deny-glob config edit and
  matcher fixture test need no hooks.

Signed off: 2026-07-17 (graph re-derived after the lens-pass Task 7
re-ordering)

## 7. Risk register

Decision-domains gap check: merged catalog consulted via
`scripts/resolve-catalog.sh decision-domains` (11 core domains, no
overlay additions). Domains the spec touches — auth, secrets-config,
caching (inside the fork-PR audit surface), dependency-adoption,
observability, deploy-migration — are all decided in the bundle or by
the human-selected security forks, except deploy-migration, which
produced row 4 below (detection decided in D-3; the rollout sweep is
the row's mitigation). No catalogued domain the spec touches is left
undecided.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | Matcher-model drift: Claude Code changes matcher semantics; the D-4 model diverges while fixtures stay green against the stale model. | Model doc pins version + docs consulted; fixture table records current outcomes honestly; re-verify on Claude Code upgrades. Signal: a deny not firing in real sessions. |
| 2 | Human `--no-verify` bypass of the hook layer. | Accepted by design (signed §3): workers are the threat model and the glob layer backstops them; `--no-verify` is the human's deliberate escape hatch. |
| 3 | Seed-hash guessability (low-entropy purged identifiers). | Accepted residual per D-5: threat model is accidental reintroduction, not adversarial secrecy. |
| 4 | Existing clones/worktrees stay unwired when the hook layer lands (deploy-migration gap-check finding: rollout is non-atomic). | One-time re-wire sweep after Task 2 merges; the unwired-clone check fails loudly meanwhile. Signal: check red on a local run. |
| 5 | The fork-PR audit falsifies D-6's safe-by-construction posture. | Designed-for: a falsifying finding reopens D-6 as a design amendment; isolated-runner direction re-enters scope. Signal: the Task 4 audit record. |
| 6 | CI-runner timing noise trips the hard-fail budgets without a real regression. | 30–50% headroom over the measured post-split baseline; bumps are conscious reviewed edits with derivation recorded. Signal: budget failures on diffs touching no tests. |
| 7 | Task 2↔3 coupling: commit-msg hook and seed format span two PRs. | The 3→2 edge serializes them; the hook-extension fixture test catches format mismatch. |
| 8 | Seed provisioning is human-gated mid-execution (Task 3 needs out-of-band plaintexts). | Provisioning step documented in the check header; absent the human, Task 3 parks in Awaiting input rather than shipping empty seeds. Signal: a Task 3 PR with only test-token hashes. |
| 9 | Tracked `githooks/` + `core.hooksPath` is an arbitrary-code-execution vector: a covered git command on an untrusted fork-PR checkout runs that branch's hook code (surfaced by the panel lens pass). | Accepted residual (D-2): same caution as running an untrusted checkout's tests; hooks are small and diff-reviewed; reviewers unset `core.hooksPath` before operating on an untrusted branch. Open to the human as a D-2 tradeoff (accept / add a trust-gate / reconsider tracked hooks). |

Open questions: none carried — all resolved to decisions or recorded
above as explicit accepted risks.

Signed off: 2026-07-17

## 8. Sign-off — lens review pass

**Scope:** full bundle (first activation). **Method:** parallel fan-out,
one read-only sub-agent per canonical lens (nine), each grounded against
the real repo, severity-pruning forbidden; coordinator merged, deduped,
validated per `validation-rigor`, then dispositioned every finding with
the human. ~100 raw findings converged to 20 applied spec edits, 4
human-decided forks, and a set of recorded residuals.

**Kickoff altitude check (REQ-H1.3 of autopilot-reflex, not a new lens):**
Drafting fired an altitude trigger — the pinned seed claim obs:cf6a2bd2
("that's a doctrine gap") recorded in `## Sources`. The bundle carries
the altitude record D-1, cited from the Goal, and the task decomposition
matches the claimed split (doctrine = Task 8; capability = catalog
entries in Task 11; mechanism = the checks/hooks; local value = budget
numbers + seed hashes). Triggered-and-recorded: satisfied.

### Lens-coverage table

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 15 | Amend-detection boundary (`--amend -m`), phantom install seam, unwired-clone CI no-op, `git -c` push bypass, workflow_run, fleet-table normalization, self-referential Task 6 target, run-body second-order, `amend!` subjects — all applied or forked. |
| Security | 10 | workflow_run privileged trigger, `secrets: inherit`/reusable-workflow/effective-permissions gaps, CI-side message screen, `git -c` push enforcement collapse, embedded-form false-negatives, provisioning hygiene — applied. |
| Error handling and failure modes | 24 | Systemic fail-open on empty/malformed input across every new guard → consolidated into new REQ-H1.3 fail-closed posture + per-guard vacuous-input fixtures. |
| Performance | 11 | `check:test-time` re-run hazard (CI timeout), aggregate contention, baseline-context, per-token hashing → report-driven wiring, batched hash, all-files baseline, CI/local split. |
| Concurrency / state | 7 | `core.hooksPath` clone-global blast radius, phantom seam, mise.toml `depends` append contention, Task 7 budget merge-order tripwire → wire-step redesign, Task 7 re-ordering, registration sweep owns the append. |
| Naming, readability, structure | 4 | `hooks/` collision, seed list vs file, target vs budget, "a check" vs "a test" → `githooks/` rename, terminology aligned. |
| Documentation | 8 | CONTRIBUTING quality-gate + hook-enforcement docs, install.sh purpose, guard-catalog category enum, budget-file location vs options-reference, fleet.md third restatement → doc tasks assigned, tether extended. |
| Tests / verification | 13 | Vacuously-green seed list, missing negative/scoping fixtures, non-mechanical Done-whens, coverage-not-proven-by-green → non-vacuity floor, negative fixtures, assertion-count metric, target-set assertion. |
| Cross-file consistency | 11 | Stale D-6 wording, missing changelog entry, three stale Scope bullets, brief graph 11→2 edge, manual-count phrasing → all reconciled this pass. |

### Dispositions

- **Applied as spec edits (20 Needs-sign-off, human-approved as a batch):**
  the REQ/design/task/test-spec changes summarized in the Changelog's
  2026-07-17 lens-pass entry and the D-2/D-3/D-5/D-6/D-7/D-8/D-10/D-12/
  D-13 amendment annotations, plus the new REQ-H1.3.
- **Human-decided forks (4):** git-hook location → new `githooks/` dir;
  budget-setting order → Task 7 waits for all fixture-adding tasks;
  cache/artifact posture → audit-only residual recorded in D-6;
  `check:test-time` hard-fail → CI hard-fail, local loud-warn.
- **Recorded residuals (declined-as-accepted, with rationale):**
  mise file-based-task parse boundary (D-7); cache/artifact standing
  check (D-6); low-entropy seed-hash guessability (D-5, pre-existing);
  per-commit hook latency (D-2); the `--amend -m` family being
  glob-only, not hook-covered (REQ-A1.2, stated honestly).
- **Undispositioned findings:** none.

Class: meaning
Lens-pass: §8 lens review pass (this section) — full-bundle fan-out, table and dispositions above
