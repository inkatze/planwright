# Autopilot Reflex — Kickoff Brief

## 1. Header

- **Spec:** `specs/autopilot-reflex/`
- **Spec commit at walkthrough start:** `b4f0eee0c57227a7310f9deb4be11125113d0c67`
- **Walkthrough date:** 2026-07-01
- **Mode:** first activation (Status Draft, no prior brief)
- **Validator:** `scripts/spec-validate.sh specs/autopilot-reflex` — 0 errors, 0 warnings (Draft enforcement)
- **Config:** `commit_on_kickoff: true` (defaults; no local override)
- **Lifecycle:** sign-off flips Draft→Ready per spec-format v1 / kickoff-lifecycle D-1; first task dispatch later derives Active

## 2. Goal & glossary

**Restatement.** The primary deliverable is doctrine: `doctrine/autopilot-reflex.md`,
the six-step reflex for closing recurring-manual-ceremony gaps — (1) name the
irreducible human gates first; (2) automate up to the gates, never through
them; (3) verify the burden was eliminated, not relocated; (4) surface by push
or forcing-function, never by pull; (5) right-altitude every piece
(doctrine / capability / mechanism / local value, mechanical tools over LLM
judgment where no judgment exists); (6) capture the reasoning as the reusable
asset. Two instantiations prove it. **A — release tagging (runtime ceremony):**
release-please in PR-only mode maintains a release PR from conventional
commits (detection, correction, cancellation, and approval in one standing
artifact); the human merge is the approval; a local signer-agnostic
`scripts/release-publish.sh` cuts a signed annotated tag on the observed
release-merge SHA (never HEAD) plus the GitHub Release; a required CI check
locks the untagged window. Organic proof: planwright's own next release cut
through the machinery (T11). **B — authoring altitude gate (authoring
ceremony):** `/spec-draft` pins seed claims and resolves deliverable altitude
before design, phase-end summaries re-anchor, `/spec-kickoff`'s lens pass
verifies the altitude D-ID.

**Rules out.** Any auto-merge (merge-bearing `/approve-release` rejected,
D-5); background auto-sign or CI-held signing material; CalVer for planwright;
an LLM `/release` skill; the one-time private→public gate (bootstrap
REQ-J1.5); monorepo release orchestration; altitude gate beyond the two named
skills.

**Assumes.** Conventional commits enforced on `main` (existing commit lint);
GitHub as forge (`gh`, merge queue, release-please); signing configuration
lives on the publisher's machine (a local value, not capability);
`.claude-plugin/plugin.json` is the version source of truth.

**Glossary.**
- *Ceremony gap* — a recurring ritual that fires only when a human remembers it.
- *Altitude* — the doctrine → capability → mechanism → local-value ladder
  (REQ-A1.1 step 5, D-13).
- *Untagged window* — from release-PR merge (version bump on `main`) to tag
  publish; locked by REQ-E1.1.
- *Observed release-merge SHA* — the commit where the version bump landed on
  `main`; the only commit ever tagged (D-6).
- *PR-only mode* — release-please maintains the proposal PR but never creates
  tags or Releases (REQ-C1.3).
- *Armed mode* — T10's pre-validated watcher that fires the publish on the
  observed merge.

**Resolutions.**
- Stale Goal prose ("currently `0.1.0`"; main is at 0.2.2 / tag v0.2.1):
  fixed in place — version number un-pinned from the Goal. Logged in the
  consolidated edit list (§3).
- Release state verified against origin at walkthrough time: v0.2.0–v0.2.6
  exist as signed annotated tags with GitHub Releases, cut manually (v0.2.4
  skipped — a live example of manual-ceremony fallibility); no untagged
  window open (main = v0.2.6 = plugin.json 0.2.6). Transient sequencing
  (flipping T6's check to required while a window happens to be open) is
  carried to the risk register (§7). *(Corrected 2026-07-02: an earlier
  stale fetch had misread the repo as mid-window.)*

Signed off: 2026-07-01

## 3. Requirements walkthrough

**REQ-A — the autopilot-reflex doctrine.** Intent confirmed: the six-step
reflex as a standalone, citable, link-checked rule doc defining altitude
triggers (seed claims + mid-flow signals; firing forces altitude resolution
before solution design) and the phase re-anchor, with the proportional
artifact rule (fired trigger ⇒ altitude D-ID cited from the goal; no trigger
⇒ no ceremony). Decision: trigger detectability at kickoff must not depend on
session memory — pinned seed claims are durably recorded in the bundle's
`## Sources` (edit #2, REQ-H1.1 clarified; gap-fill consistent with what this
bundle itself practices). Signed with REQ-B on 2026-07-02.

**REQ-B — release-tagging policy note.** Intent confirmed: the five policy
points (detection automated; approval = human merge; publish human-gated and
signed per repo policy; window locked; merge/publish never autonomous) map
one-to-one onto reflex steps and D-3/D-5/D-7; the capability/mechanism/value
table (B1.2) prevents later promotion of mechanism to core. No edits.

**REQ-C — detection & proposal.** Intent confirmed: release-please PR-only is
the detector; the standing release PR is proposal + correction (edit) +
cancellation (close) + approval gate (merge) in one artifact; CI never tags
(C1.3); merge stays human (C1.4); notes from merged PRs, spec-enriched never
spec-dependent (C1.5). Close/reopen semantics are third-party behavior,
honestly `[manual]` in the test spec. No edits.

**REQ-D — signed publish.** Intent confirmed: portable signer-agnostic
script, observed-merge-SHA tagging, five refuse-without-side-effects gates,
signature verified before push, Release via `--verify-tag`, one shared
"pending" definition (comparator). Decision: the first-release case (no
existing tags — moot for planwright, real for fresh adopters) added as a
passing fixture to test-spec REQ-D1.3 (edit #3).

**REQ-E — untagged-window lock.** Intent confirmed: required check red while
version > latest tag; merge queue serializes; E1.4's invariant (correctness
never depends on the lock) understood as load-bearing. Release state at
walkthrough verified live: v0.2.0–v0.2.6 signed tags + Releases, no open
window; the transient enablement-while-window-open sequencing goes to the
risk register, no task edit. Signed (C+D+E): 2026-07-02.

**REQ-F — surfacing.** Intent confirmed: three deliberately redundant layers
(PR-body push, bookkeeping belt-and-suspenders, `mise run release` sugar over
the dependency-free script). No edits.

**REQ-G — adopter path.** Intent confirmed. Decision: both catalogs are
doc/yaml pairs and `resolve-catalog.sh` serves the yaml machine views, so
Task 3's deliverables now name `config/guard-catalog.yaml` and
`config/decision-domains.yaml` alongside the prose docs (edit #4) — T3's own
Done-when (resolver test) is unsatisfiable otherwise.

**REQ-H — altitude gate.** H1.1 clarified earlier (edit #2). Decision on
H1.3: the altitude check is a **kickoff-specific check item** inside the
sign-off lens pass, not a tenth canonical lens; `discovery-rigor`'s canonical
list is untouched. T8 Done-when and test-spec REQ-H1.3 wording clarified
(edit #5).

**REQ-I — organic proof.** I1.2 verified live during the walkthrough (D-1
exists, Goal cites it). I1.1 human-gated by construction; at the current
release cadence the proof opportunity follows T5/T6 almost immediately. No
edits.

**Consolidated spec-edit list (all applied in place; Draft bundle):**

1. `requirements.md` Goal — stale "currently `0.1.0`" un-pinned.
2. `requirements.md` REQ-H1.1 — pinned seed claims recorded in `## Sources`
   (kickoff check made bundle-local).
3. `test-spec.md` REQ-D1.3 — first-release (no-tags) passing fixture added.
4. `tasks.md` Task 3 — yaml machine views named alongside the prose catalogs.
5. `tasks.md` Task 8 Done-when + `test-spec.md` REQ-H1.3 — altitude check
   clarified as kickoff-specific; canonical lens list untouched.

Signed off: 2026-07-02

## 4. Design walkthrough

Reconciled ledger — all thirteen decisions **confirmed**, none amended, none
superseded:

- **D-1** doctrine-first altitude (the bundle's own altitude record; I1.2
  verified live at this kickoff) · **D-2** reflex as standalone rule doc ·
  **D-3** release-please PR-only (four needs, one artifact) · **D-4**
  signing delegated to git config, `require` here — matches observed
  practice, the live v0.2.x tags are SSH-signed annotated · **D-5** framework
  never merges (bright-line) · **D-6** tag the observed merge SHA, never
  HEAD · **D-7** lock + push/forcing-function (enablement sequencing → §7
  risk register; decision untouched) · **D-8** publish is a mechanical
  script · **D-9** SemVer (live lineage already follows it) · **D-10** notes
  from merged PRs, spec-enriched never spec-dependent · **D-11** altitude
  triggers + re-anchor (edits #2/#5 sharpened wiring, not the decision) ·
  **D-12** armed mode as sequenced follow-up T10 · **D-13** adopter path via
  builder/catalogs (edit #4 is implementation precision).

Cross-checks: every D-ID cited by ≥1 REQ and ≥1 task; no decision
contradicts a walked requirement; D-5/D-4 rejected alternatives mirrored in
Out of scope.

Signed off: 2026-07-02

## 5. Verification approach

**Coverage mix** (30 entries; validator confirms every REQ pinned):
`[test]` component on 17 entries — the REQ-D script surface, lock logic,
resolver/link-check, the no-merge-call-sites grep, bookkeeping branch, mise
task, template-placement inventory; all in `mise run check` with fixture
repos and a throwaway SSH key (no 1Password in tests). `[manual]` on 13 —
live release-please behavior, repo settings, live PR body, the altitude-gate
exercises, the organic proof; honestly not fixture-testable. `[design-level]`
on 16 — doctrine and catalog artifacts. No `[Gherkin]` entries (nothing
scenario-shaped).

**Ownership.** `[test]`: the repo's aggregate `mise run check` on GitHub CI
(external CI state is the gate). `[manual]`: the human, pinned to execution
moments (T5 live cycle, T6 settings, T11 window observation) rather than a
floating sweep. `[design-level]`: read at task-PR review as each artifact
lands.

**Dead-path check.** One found and fixed: six `[design-level]` entries named
"kickoff walkthrough" as the verification moment for artifacts that only
exist after execution (A1.2, A1.3, A1.4, B1.2, C1.4 prose half, G1.1) — the
verification as named could never run at the named moment. Reworded to
"design-level read at task-PR review" (edit #6). I1.2 keeps its kickoff
reference (bundle-internal; verified live at this kickoff).

Signed off: 2026-07-02

## 6. Task graph

Reconstructed from the `Dependencies:` lines (authoritative; the tasks.md
intro's level view is derived and was verified to match):

- T1 → T2 → {T3, T4, T5}; T4+T5 → {T6, T7}; T4 → T9; T4+T6 → T10;
  T5+T6+T7+T9 → T11; T1 → T8 (independent of the release chain).
- **Critical path:** T1→T2→T4→T6→T10 = 5.5d (verified). T11's longest chain
  = 4.75d via T6 (verified).
- **Parallelism:** T8 parallel to the whole release chain after T1; after T2
  fan out {T3, T4, T5}; after T4+T5 fan out {T6, T7, T9}. Widest useful
  fleet: 3 workers.
- **Deliberate non-edges:** (1) T8 ↛ release chain — instantiation B needs
  only the doctrine; (2) T11 ↛ T10 — the proof uses the post-merge path,
  armed mode is ergonomics (D-12); (3) T11 ↛ T3/T8 — the proof is
  release-side only; (4) T9 ← T4 only — signing prerequisites don't need the
  lock; (5) T10–T5 has no direct edge — transitively covered via T6.
- No cycles, no orphans; every task cites REQs/D-IDs (validator-clean).

Signed off: 2026-07-02

## 7. Risk register

Gap check: merged decision-domains catalog (ten seed domains, no overlay
additions) walked against the bundle. Decided by the spec: api-surface
(REQ-D1.4/D1.6, D-13), secrets-config (D-4, T4), concurrency (D-6/D-7,
REQ-E1.4), dependency-adoption (D-3). n/a: data-storage, caching,
queues-async. Gaps became rows 2 and 3; deploy-migration's config-flip
concern became row 1.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | Flipping T6's check to *required* while a release is pending turns main red instantly | T6 flips only after the comparator reports "none". Signal: main red immediately after enablement |
| 2 | **Accepted risk:** silent detection failure — a broken release-please workflow yields no release PR, and the comparator (bump-vs-tag) reports "none"; the ceremony gap silently reopens | Accepted for v1. Signal: releasable commits accumulating with no release PR. Named follow-up if it bites: commits-since-tag comparator extension |
| 3 | **Decision:** release-please workflow token posture (auth gap-check finding) | Resolved at kickoff: default `GITHUB_TOKEN`, least-privilege in-workflow permissions (`contents: write`, `pull-requests: write`); no PAT, no stored secrets — consistent with D-4's zero-CI-secrets posture. Cited at T5 |
| 4 | Manifest bootstrap vs the gapped manual lineage (v0.2.4 skipped): first release PR could propose a wrong version | T5 Done-when requires the observed bump be correct. Signal: first PR's version ≠ expected |
| 5 | Fleet-wide merge blocking during the untagged window (by design, but ~3 releases/day cadence blocks concurrent tower PRs) | Publish promptly; T10 armed mode shrinks the window to merge-to-sign. Signal: unrelated PRs failing the release-pending check |
| 6 | release-please supply chain: third-party action with write permissions | Pin by SHA at T5 (dependency-adoption checklist via D-3) |

No open questions: row 2 is an explicit accepted risk, row 3 is a recorded
decision, all rows carry mitigation and early signal. Data hygiene checked:
no secrets, hostnames, or private-repo identifiers.

Signed off: 2026-07-02

## 8. Sign-off

**Lens review pass** (first activation → full bundle; fan-out per
`discovery-rigor`, nine read-only sub-agents, one per canonical lens; ~62 raw
findings merged, deduped, self-critiqued, validated per `validation-rigor`
three-pass + adversarial refute/resurrect scoped to spec-prose review):

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 2 | F1 version-read source; F2 first-release monotonicity base case. Remainder implementation-altitude or covered (pending CI = not green = refuse; lock runs in CI; no releasable commits = no PR) |
| Security | 1 | F4 T4 input-validation citation (near-redundant with standing security-posture; made executor-visible). D-4 posture confirmed sound |
| Error handling and failure modes | 1 | F3 partial-publish resume. `gh` errors fail closed; armed-mode crash falls back to post-merge mode; silent detection failure = accepted risk row 2 |
| Performance | none | Polling/queue-latency quantification left to implementation (proportionality); blocking impact tracked in risk row 5 |
| Concurrency / state | none | No falsifiable defect; real variants merged into F1/F3; one release PR by tool design; queue-vs-lock blocking is the intended forcing function |
| Naming, readability, structure | none | Three hyphenation cosmetics; no semantic ambiguity |
| Documentation | none | Every doc deliverable has a task home; no stale references |
| Tests / verification | 1 | F5 REQ-H1.3 positive case. "Design-level reads lack rubrics" is inherent to the tag per the meta-spec |
| Cross-file consistency | none | Citations, graph math, external refs verified clean. One raw finding ("Status should already be Ready") false-positive — the flip is this flow's next step |

**Altitude check (kickoff-specific item, REQ-H1.3 self-applied): PASS** —
D-1 exists, the Goal cites it, task decomposition matches the doctrine-first
claim (T1 is the graph root).

**Dispositions (2026-07-02, human: apply all):** F1 applied (REQ-D1.2,
edit #7); F2 applied (REQ-D1.3, edit #8); F3 applied (REQ-D1.3 + test-spec
REQ-D1.7, edit #9); F4 applied (Task 4, edit #10); F5 applied (test-spec
REQ-H1.3, edit #11). All other raw findings declined with rationale in the
table notes above; no deferrals. Changelog entry added to `requirements.md`
covering all eleven kickoff edits.

**Validator:** clean (0 errors, 0 warnings) on the edited bundle before the
flip, and clean again under Ready enforcement after the Draft→Ready flip and
`Last reviewed:` bump (2026-07-02) on all four files.

**Sign-off record** (first activation; sections above this record are
append-only from here; later contract changes travel as amendment-log
entries below):

Signed off: 2026-07-02

Class: meaning
Lens-pass: recorded above (this section), findings dispositioned 2026-07-02.
Anchor: `789f80e89a6138fe516a954e64bf651db4ee9358` — computed as
`scripts/spec-anchor.sh specs/autopilot-reflex`

## 9. Amendment log

(none yet)
