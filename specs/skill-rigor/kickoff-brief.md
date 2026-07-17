# Skill rigor — Kickoff brief

## 1. Header

- **Spec:** `specs/skill-rigor`
- **Spec commit at walkthrough start:** `77fd74a` (`feat(spec): draft specs/skill-rigor bundle`)
- **Walkthrough date:** 2026-07-16
- **Mode:** first activation (Status Draft, no prior brief)
- **Validator outcome:** `scripts/spec-validate.sh specs/skill-rigor` — 0 errors, 0 warnings
- **Doctrine resolution:** all seven rule docs resolved (plugin cache `planwright/0.14.1`)
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true` (defaults; no local override)
- **Format-version:** 2 (stored status set is Draft/Ready/terminal; Active/Done derived)
- **Pre-walk grounding:** selector exit 3 confirmed at `scripts/orchestrate-select.sh:292`; stored-`Active` grep confirmed at `skills/self-review/SKILL.md:123`; `scripts/spec-status.sh` present; budget figures confirmed against `check:instructions` output. Discrepancies carried into the walk: the `fix/resolve-rule-doc-self-locate` branch has three commits and is pushed to origin (Sources says "two unpushed local commits"); design's cross-cutting budget note labels orchestrate's 19,997-word figure "start-load" where `check:instructions` reports it as the closure figure.

## 2. Goal & glossary

**Restatement.** The doctrine layer is complete; the mechanism layer drifted
below it in four confirmed clusters, every one seed-grounded and re-verified
against the working tree at walkthrough start:

1. **Lifecycle / format-v2 stragglers.** `/self-review`'s no-arg fallback
   resolves specs by grepping stored `Status: Active`
   (`skills/self-review/SKILL.md:123`) — dead against every format-v2 bundle
   (v2 stores Ready while work is in flight) and blind to signed-but-unstarted
   v1 bundles; its brief fall-through can bind a spec-authoring branch to an
   unrelated spec's brief. `/orchestrate`'s instructions never folded the
   shipped selector exit 3 (`scripts/orchestrate-select.sh:292`, the transient
   evidence hold) and its ready-task candidacy prose is not version-keyed.
2. **Sign-off trusts narrative.** `/spec-kickoff` records cross-check and
   numeric claims it never re-derives (two defects shipped past sign-off on
   autopilot-reflex) and once marked a spec PR ready while CI was red on the
   head SHA (PR #128); there is no pre-flip lint.
3. **Drafting has no self-critique.** An 86-raw/42-valid kickoff lens yield
   over a fresh draft shows cheap catches sitting one stage right of where
   they could land.
4. **Non-deterministic doctrine resolution.** `scripts/resolve-rule-doc.sh`
   cannot locate core doctrine shipped beside it (planwright's own checkout,
   worktrees, dispatched worker subshells) when no env root is set.

**What ships:** skill and script mechanism citing the doctrine impulses that
already govern it (D-1: mechanism altitude, no new rule doc), inside the
`check:instructions` budget walls, with the instruction-headroom sibling spec
as expected-but-not-gated relief (D-9 makes the dependency agent-evaluable
via `Done when:`).

**Rules out:** minting or extending doctrine; touching budget ceilings or
exemptions; `/execute-task` (already Ready-widened at v0.14.1); accumulator
findings outside the seed set; dotfiles-side copies; redesigning CI, release,
or ready-flip ownership.

**Assumes:** the doctrine layer is complete (every seed documents a skill not
doing what doctrine already implies); the fix-branch work is sound and
adoptable; relief ordering relative to instruction-headroom is deliberately
unconstrained beyond the D-9 gate.

**Implicit terms resolved:**

- *status render* — `scripts/spec-status.sh`, the canonical derived-status
  read surface (invariant-tasks Task 7 precedent).
- *transient evidence hold* — selector exit 3: v2 execution evidence still
  settling; report and end the step cleanly (lock-contention shape), never a
  halt.
- *head-SHA check rollup* — `statusCheckRollup` on the head commit: checks on
  the SHA, never PR review states.
- *instruction budgets* — `check-instructions.sh`'s per-file, start-load, and
  closure word budgets (warn floors, hard walls).
- *mechanism altitude* — autopilot-reflex's doctrine-vs-mechanism axis; D-1 is
  the altitude record for the three pinned seed claims.
- *cite-derived-figures* — the meta-spec rule: record the source, not a copied
  figure.

**Ambiguities surfaced and their resolutions:** two stale-snapshot
discrepancies found during pre-walk grounding were deferred to their home
sections — the fix-branch Sources description (section 3) and the
cross-cutting budget-figure label (section 4).

Signed off: 2026-07-16

## 3. Requirements walkthrough

Walked group by group; per-group outcomes below. Group tallies and REQ
wording are cited from `requirements.md` (cite-don't-copy), not transcribed.

- **REQ-A (lifecycle/v2 reconciliation) — signed as drafted.** Probes
  resolved: the Ready-or-Active widening's multi-candidate ambiguity is
  handled by D-2's degradation to the existing ask-when-attended /
  proceed-brief-less arm (never a guess), and deliberately lives in design
  rather than REQ text; REQ-A1.2's brief-absent outcome maps onto
  `/self-review`'s existing brief-absent degradation (Agent-resolvable
  bucket unavailable) — no new degradation path invented.
- **REQ-B (sign-off verification) — signed with two scopings confirmed as
  deliberate non-coverage:** (1) REQ-B1.4's mid-walk lens triggers only on
  agent-authored meaning-class edits; human-authored mid-walk edits wait
  for the terminal pass (proportionality; the observed failure was
  agent-authored). (2) REQ-B1.5's sweep triggers only on the lens minting
  or re-scoping a REQ, not on new D-IDs or task edits (the observed
  stragglers were REQ-driven; the sweep's targets still include task and
  test wording once triggered). Recorded so nobody "fixes" them later.
  *(Lens-pass update 2026-07-17: scoping (2)'s REQ-only trigger stands,
  but its lens scope widened — the sweep now fires on any walkthrough
  lens pass (mid-walk or terminal) that mints or re-scopes a REQ, closing
  the mid-walk-minted-REQ escape the correctness lens found.)*
- **REQ-C (drafting self-critique) — signed as drafted.** Inline, not
  fan-out; kickoff's full pass follows, so the rigor budget is not spent
  twice.
- **REQ-D (deterministic resolution) — signed as drafted.** Ordering probe
  resolved: the REQs pin behavior, not the fix branch's SHAs, so branch
  drift before Task 1 lands is absorbable (cherry-pick or re-land).
- **REQ-E (budget compliance) — signed as drafted.** Relief source
  (instruction-headroom landing or a compensating trim) deliberately
  unconstrained; the guard is the dependency's mechanical form.

**Consolidated spec-edit list (applied in place; Draft bundle):**

1. `tasks.md` Task 6 Deliverables: the wait-bound config option is
   registered in `config/defaults.yml` with its row in
   `docs/options-reference.md` (bootstrap D-43/REQ-K1.8; `check:options`
   enforces the pairing). Rationale: an unregistered key would trip full CI
   or invite hardcoding. *(Corrected at the sign-off lens pass 2026-07-17:
   the enforcing task is `check:options`, and the foreign IDs are
   bootstrap-namespaced; the original edit misnamed both, and the repair
   also added the registration to Task 6's Done-when and a D-3 backing
   sentence.)*
2. `requirements.md` Sources, self-locate fix branch entry: corrected the
   stale snapshot ("two unpushed local commits") to three commits pushed to
   origin, including the review-iteration test nit.

Signed off: 2026-07-16

## 4. Design walkthrough

**Reconciled ledger — every D-ID accounted for.** At the walkthrough, all
ten decisions were **confirmed** with rationale intact; none superseded.
*(Lens-pass update 2026-07-17: D-3, D-4, D-5, D-6, D-7, D-8, and D-9 were
subsequently amended in place by the dispositioned sign-off lens findings,
each carrying its amendment annotation; the confirmations below record the
walkthrough-time state.)* Notes per decision where the walk added
evidence:

- **D-1** — confirmed. The altitude record for the three pinned seed
  claims; cited from the goal ("mechanism-altitude by explicit decision").
- **D-2** — confirmed. Multi-candidate ambiguity degradation confirmed as
  design-level detail (§3, REQ-A probe 1).
- **D-3** — confirmed. Its config-overridable wait bound is now an
  explicitly registered config key via the Task 6 edit (§3, edit 1).
- **D-4** — confirmed.
- **D-5** — confirmed; the agent-authored-only trigger recorded as
  deliberate in §3.
- **D-6** — confirmed; the REQ-only sweep trigger recorded as deliberate
  in §3.
- **D-7** — confirmed.
- **D-8** — confirmed; the fix-branch Sources snapshot corrected in §3
  (edit 2). Adoption is behavior-pinned, not SHA-pinned.
- **D-9** — confirmed. All three near-wall figures mechanically re-derived
  against `config/defaults.yml` walls (per-file error 4,250; start-load
  error 10,000; closure error 20,000): spec-kickoff 4,243 per-file and
  self-review 9,993 start-load are exact; the orchestrate figure is real
  but was mislabeled (below).
- **D-10** — confirmed against the shipped exit site
  (`scripts/orchestrate-select.sh:292`).

No design decision contradicts a walked requirement.

**Spec edit (consolidated list #3, expression-only):** cross-cutting
Budget-walls note relabeled `/orchestrate` 19,997/20,000 from "start-load"
to "closure" — `check:instructions` reports that figure under the closure
budget; orchestrate's start-load is nowhere near its 10,000 wall.

Signed off: 2026-07-16

## 5. Verification approach

**Coverage mix** (entries and tags cited from `test-spec.md`): `[test]`
only where something executes — the resolver suite
(`tests/test-resolve-rule-doc.sh`, extended by Task 1) and
`check:instructions` — both in `mise run check` on GitHub CI. Skill-prose
behaviors are `[design-level]` (the SKILL text is the shipped artifact);
five entries add `[manual]` live-run paths. The intro's refusal to claim
`[test]` where nothing executes was reviewed and endorsed.
*(Lens-pass correction 2026-07-17: the endorsed premise was wrong — the
repo already ships grep-based structural guard suites over SKILL prose,
so the greppable entries were re-tagged `[test]` wired to guard
extensions riding Tasks 3, 4, and 7, and failing-case manual scenarios
were added; the mix statement above records the walkthrough-time reading,
superseded by the current `test-spec.md` intro.)*

**Ownership:** `[test]` entries are owned by GitHub CI on every landing
PR. `[manual]` paths are exercised by the human at task-PR review via
`/execute-task`'s pending-sign-off checklist — the pipeline's existing
mechanism; no separate sweep cadence is invented. Recorded here, no spec
edit (human's call, §5 sign-off).

**Dead-path check:** none found. Every `[manual]` scenario is
constructible (REQ-A1.1's needs a format-v2 bundle with work in flight —
this spec itself becomes one post-merge); both `[test]` suites exist or
arrive with Task 1; all 13 REQs carry an entry (validator corroborates
coverage). *(Corrected 2026-07-17: originally written "12" — a live
instance of the exact recorded-numeric-claim failure class REQ-B1.3
targets, caught by the lens pass's re-derivation: A:4 + B:5 + C:1 + D:2 +
E:1 = 13.)*

Signed off: 2026-07-16

## 6. Task graph

Reconstructed from the `Dependencies:` lines in `tasks.md` (authoritative;
the `scripts/spec-graph.sh` render agrees — cite the render, not a pasted
copy).

- **Structure:** tasks 1–4 are independent roots; the only chain is
  5→6→7. Up to five units can start at once (1, 2, 3, 4, 5).
- **Critical path:** 5→6→7, effort-weighted 1.5 days (three half-days;
  per-task efforts cited from `tasks.md`).
- **Cohesion note:** the 5→6→7 edges encode same-file cohesion (all three
  edit `skills/spec-kickoff/SKILL.md`) plus the hardened flow's order, not
  logical dependency; dispatching 5-7 as one cohesion bundle is a
  legitimate orchestration choice the graph permits.
- **Deliberate non-edges (do not "fix"):**
  1. Task 1 (resolver) feeds nothing — no prose task needs the resolver
     fix to land.
  2. Tasks 3 and 4 carry no edge between them — different skill files, no
     conflict.
  3. No edge to the instruction-headroom sibling spec — the dependency is
     deliberately expressed as D-9's `check:instructions` gate in each
     prose task's `Done when:` (agent-evaluable; cross-spec edges are not
     in the task grammar).

Signed off: 2026-07-16

## 7. Risk register

Inputs: risks surfaced during the walk and the decision-domains gap check
(merged catalog via `scripts/resolve-catalog.sh decision-domains`, eleven
domains walked). Gap-check outcome: `secrets-config` triggered but decided
(the wait-bound key is pinned to a documented default and registered per
§3 edit 1); `concurrency` touched with one undecided sliver → R3; the
remaining nine domains do not apply to a skill-prose-and-shell-script
bundle.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| R1 | Budget squeeze: `skills/spec-kickoff/SKILL.md` has 7 words of per-file headroom against five new mechanisms (Tasks 5–7), and `/orchestrate`'s closure wall is tighter still — 3 words against Task 4's additions. *(Extended at the lens pass 2026-07-17: mechanism count corrected four→five; the orchestrate gap named.)* | D-9's `check:instructions` gate; instruction-headroom relief or compensating trims. Signal: the guard red on the first Task 4 or Task 5 attempt before relief lands. |
| R2 | Kickoff latency: the terminal CI gate can block up to the wait bound (default 10 min). | Config-overridable bound; refusal arm leaves a resumable draft with the remedy. Signal: kickoffs habitually timing out. |
| R3 | **Mid-wait head movement** (decision-domains gap row, domain: `concurrency`): D-3 pins the rollup to the head SHA but did not decide behavior if the branch head moves during the wait. *(RESOLVED at the lens pass 2026-07-17: the refuse-and-draft branch was chosen — head identity is re-confirmed immediately before `gh pr ready`, and a moved head refuses the flip into the Awaiting-input re-entry (REQ-B1.1, D-3, Task 6).)* | Rule now specced; residual signal: the REQ-B1.1 manual run exercised with a mid-wait push. |
| R4 | Re-derivation under-scoping: "cross-check or numeric claim" is an open class a worker could under-read. | D-4's enumerated family; the seeded-mismatch manual test (REQ-B1.3). Signal: a claim class shipping unverified after Task 5. |
| R5 | Fix-branch drift: main may move under the three-commit branch before Task 1 lands. | Behavior-pinned REQs — adoption is a cherry-pick or re-land, not SHA-bound. Signal: conflict at adoption. |
| R6 | Resolver residual (appended at the lens pass 2026-07-17): the self-location arm is lowest-precedence, so a resolvable-but-stale writer install (`~/.claude/planwright`) still outranks it — the legacy line 75 scenario is mitigated only while no stale install exists. Accepted: env-root precedence is deliberate (REQ-D1.2). | Documented in REQ-D1.1/D-8 as an accepted residual. Signal: doctrine resolving to a writer-install path on a machine with a repo checkout. |

No open questions carried: R3 was resolved at the lens pass (rule now
specced into Task 6); R6 is an explicit accepted risk; everything else is
resolved or accepted above.

Signed off: 2026-07-16
