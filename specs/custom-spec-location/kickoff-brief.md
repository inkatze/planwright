# Custom spec location — Kickoff brief

This is the durable contract between human and agent for
`specs/custom-spec-location` (two-brief model, bootstrap D-3).
Downstream skills (`/execute-task`, `/orchestrate`) operate from this brief,
not by re-reading the spec.

## 1. Header block

- **Spec path:** `specs/custom-spec-location`
- **Spec commit at walkthrough start:** `088009a`
- **Walkthrough date:** 2026-09-22
- **Mode:** first activation (Status Draft, no prior brief)
- **Format-version:** 2 (stored header rests at Ready after sign-off; Active/Done derived)
- **Validator outcome (pre-flight):** `spec-validate` — 0 errors, 0 warnings
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true`,
  `kickoff_ready_ci_wait: 10m` (defaults; no `planwright.local.yml` override)
- **Working location:** branch `planwright/custom-spec-location/spec` in the
  worktree `.claude/worktrees/custom-spec-location` (created by the drafting
  session; not the `<spec>-spec` name the skills derive from bootstrap D-37's
  placement rule, kept as is rather than re-created)
- **Doctrine resolved:** all nine run-start and point-of-use docs resolved
  under the checkout's `doctrine/`; no degradation arm taken
- **Structured decision/transcript log:** no harness-provided log in this
  session; the turn mirror is skipped, not improvised into the repository
- **Sources check:** all fifteen `obs:` fragments cited in `requirements.md`
  are present under `specs/_observations/` with a `Consumed-by:` line from the
  draft commit; legacy L79 carries its consumed-by mark in `opportunities.md`

## 2. Goal & glossary

**Restated goal.** Today the spec home is not a decision but an accident:
`git rev-parse --show-toplevel` plus the literal `specs/`, re-derived in each
script, and the copies disagree about worktrees (the config-overlay and
worktree-placement observations under Sources). This spec makes three roots
explicit, each with exactly one resolver: the **install root** (which
planwright copy runs), the **primary checkout root** (which repository the
session belongs to, worktree-aware), and the **spec root** (where bundles
and the observation accumulator live). Every reader and writer of bundles and
fragments goes through them. With nothing configured, the only observable
changes are named corrections carried in the compatibility fixture's
expected-change set (REQ-A1.1; at the walk these were the two worktree
corrections, and the sign-off batch named the primary-root variable's
narrowing, the chain convergence, and the self-hosting pin alongside them).
Configured, the spec root may be another directory in the same repository,
a directory in a second "holder" repository, or a plain directory with no
git. Execution state stays derived from the work repository's git in every
posture; the store's posture governs only how authoring commits and pushes,
never whether a task can dispatch.

**What it rules out.** Non-filesystem stores; execution without a git work
repository; the reverse root-to-work-repo registry (deferred, D-21); public
observation fan-in; any change to sign-off, merge, or never-auto-merge.

**What it assumes.** Every dispatching session starts in the work repository
that owns the `spec_root` pointer. Named observation targets serve one
operator's fleet on one machine. The marker file is the root's identity and
nothing cross-checks its `project:` value today (the registry that would is
deferred).

**Glossary (implicit terms surfaced, resolutions recorded).**

- **work repository** — the git repository whose code the tasks change and
  from whose branches, PRs, and commit trailers task state is derived.
- **holder** — a second git repository whose job is to hold one spec root per
  project it serves; each root carries its own marker and accumulator.
- **primary checkout** — the worktree that owns the common git directory,
  the one `.claude/worktrees/` hangs off. Unqualified "checkout" in the
  bundle means the current toplevel (the view D-7 calls checkout-local).
- **primary view / checkout-local view** — the primary checkout's (or the
  holder's) copy of the root versus the current worktree's own copy; the
  same directory in `separate-repo` and `plain`. (Called the canonical view
  in the draft; renamed at sign-off so "canonical" means only path
  normalization, K15. The terms now live in `requirements.md` under Goal.)
- **posture** — the store's git relationship to the work repository, one of
  the three enumerated rungs in REQ-E1.1.
- **the default root** — decided by resolved path, not by option presence
  (resolution below).

**Ambiguity resolved.** "The default root needs no marker" (REQ-A1.4) did
not say whether "default" meant the option unset or the resolved path equal
to `<primary checkout>/specs`. Decided: the resolved path is the test.
Grounding: D-4 names the mistyped pointer as the risk the marker mitigates,
and no typo produces the default path; D-6 prefers derived filesystem facts
over declared settings; REQ-H1.2 promises no migration step to an adopter
who keeps the default, which an explicit default value still is. Operator
chose to apply the clarification now.

**Spec edits applied in this section (meaning-class, agent-authored).**

1. `requirements.md` REQ-A1.4: added the resolved-path sentence and the
   kickoff citation.
2. `test-spec.md` REQ-A1.4: the fixture gains the explicit-default case with
   `--explain` naming the supplying layer.

**Mid-walk delta-scoped lens (kickoff-verification).** Walked inline (the
delta is one sentence plus one fixture). Dependents checked: D-4 (marker
rationale unchanged, the edit narrows the exemption's edge only); D-7 (an
absolute value inside the primary checkout is re-based onto the current
checkout for the default view, so "resolves to `<primary checkout>/specs`" is
a primary-view comparison and stays consistent; the requirement now says
"primary view" outright, K15); D-18 ("the default root
of a git checkout" as a valid observation target now reads by the same
test); Task 2 Done-when (still holds: "a configured directory without the
marker is refused" applies to non-default roots). Findings: none. Pass did
not error.

Signed off: 2026-09-22

## 3. Requirements walkthrough

Walked in four turns: groups A–C (the three roots), D–E (addressing and
the posture ladder), F (observations), G–H (guards, docs, compatibility).
Per-group outcomes:

- **REQ-A (spec root).** Confirmed, with the section-2 marker clarification
  applied to REQ-A1.4. Recorded readings: a relative value may not escape
  the primary checkout, so a sibling holder is addressed by an absolute or
  `~/` value (D-3's containment is deliberate: a relative escape is the typo
  shape the marker exists to catch); canonicalization resolves symlinks
  before posture classification; `--init` writes the marker into an
  existing directory and does not create one.
- **REQ-B (primary checkout root).** Confirmed. Recorded reading: a session
  started outside any git repository is not a supported starting point; the
  helper exits non-zero (REQ-B1.4) and the skills take their existing
  not-a-git-repository degradation arms. Authoring against a `plain` store
  still assumes the session itself sits in a git work repository.
- **REQ-C (install root).** Confirmed. Recorded reading: the content check
  (REQ-C1.3) is lenient by design, skipping an arm only when it lacks both
  `doctrine/` and `scripts/`; a half-populated arm passes and fails later
  with its own error. Implementation note for Task 3: a consumer locates
  `resolve-root.sh` by self-location (its own script directory) and only
  then asks it for the install root; the resolver walks the chain, so an
  env-pinned root outranks the copy the consumer ran from, as documented.
- **REQ-D (spec identity).** Confirmed, with a gap-fill applied: the alias
  tolerates a single trailing slash (shell completion), REQ-D1.1. Resolved
  and reported, not asked (mechanical consistency with how the alias is
  typed; no other form is admitted).
- **REQ-E (posture ladder).** Confirmed, with one gap closed by the
  operator: a halting skill's Awaiting-input or Deferred write in a holder
  has no task branch to ride. Decided: the write lands as an uncommitted
  file in the store, named in the handoff, and no skill commits, branches,
  or pushes in the holder on a halt (new REQ-E1.9; D-13 amended in place;
  Task 8 and `test-spec.md` paired). Alternatives declined: committing on
  the holder's checked-out branch (a worker writing to a repo's main outside
  any PR) and a dedicated holder branch per halt (a new convention and merge
  step per halt). Recorded reading: with a holder, the spec worktree is
  opened from the holder, not the work repository. Note for Task 10: the
  spec-location guide should say the holder halt note is the operator's
  commit, since `interaction-style`'s capture rule otherwise expects such
  writes on the session's own branch.
- **REQ-F (observations).** Confirmed. Recorded readings: a cross-root
  fragment carries no source-repo provenance where that would name a
  private repository, and the hygiene screen runs on every cross-root
  write regardless of the target's visibility (the target's visibility can
  change after the write); the screen is a heuristic, so the human read at
  consumption stays the real guard (risk register row 3). A refused
  fragment is written nowhere (test-spec REQ-F1.3), so the operator
  reformulates and retries.
- **REQ-G (guards and docs).** Confirmed, with a gap-fill applied to Task 4:
  the literal-`specs/` guard's allowlist covers the namespace-literal sites
  D-11 names (the `Consumed-by: specs/<id>` writer in `scripts/obs-consume.sh`
  and the alias mapper), by line, never by file. Resolved and reported.
- **REQ-H (compatibility).** Confirmed, with one gap closed by the operator:
  the self-hosting pin (REQ-C1.2) is a third named behaviour change with the
  option unset, visible only inside a planwright checkout and outside the
  golden fixture's reach. Decided: name it in REQ-A1.1 and REQ-H1.1, with
  REQ-C1.2's test as its assertion. Alternatives declined: scoping the
  promise to adopter repos (a self-hosted change could later slip in
  unnamed) and leaving it unwritten.

**Consolidated spec-edit list (all applied in place on the Draft bundle).**

1. `requirements.md` REQ-A1.4 — the resolved-path definition of "the
   default root" (section 2).
2. `test-spec.md` REQ-A1.4 — explicit-default fixture with `--explain`
   naming the layer (section 2).
3. `requirements.md` REQ-D1.1 — trailing slash tolerated on the alias.
4. `test-spec.md` REQ-D1.1 — the trailing-slash form in the fixture.
5. `requirements.md` REQ-E1.9 — minted: halt writes in a holder or plain
   store land uncommitted and are named in the handoff.
6. `test-spec.md` REQ-E1.9 — new entry, `[test + manual]`.
7. `design.md` D-13 — amendment annotation extending the uncommitted-file
   shape to `separate-repo`.
8. `tasks.md` Task 8 — deliverables, Done-when, and citations carry
   REQ-E1.9.
9. `tasks.md` Task 6 — "both forms" wording replaced by the accepted forms
   (stale-count sweep after edit 3).
10. `requirements.md` REQ-A1.1 and REQ-H1.1 — the self-hosting pin named as
    the third behaviour change, asserted by REQ-C1.2's test.
11. `tasks.md` Task 4 — the guard allowlist names the namespace-literal
    sites, allowlisted by line.

**Mid-walk delta-scoped lens passes (kickoff-verification).** Edits 3–11
were walked inline, each delta being one to three sentences. Dependents
checked: D-11 and Task 6 for the alias form (Task 6 wording updated, edit
9); D-13, D-15 (the write zone already admits the holder write), REQ-E1.3,
and Task 8 for REQ-E1.9; D-10, REQ-C1.2, and Task 1 for the third named
change (Task 1's Done-when already asserts the pin); D-19 and Task 4 for the
allowlist. Findings: none beyond the stale wording fixed in edit 9. No pass
errored. Validator re-run after the edits: 0 errors, 0 warnings.

Signed off: 2026-09-22

## 4. Design walkthrough

**Reconciled ledger.** Every D-ID in `design.md` (D-1 through D-21) is
accounted for:

- **Confirmed, rationale intact:** D-1, D-2, D-3, D-4, D-5, D-6, D-7, D-8,
  D-9, D-10, D-11, D-12, D-14, D-15, D-16, D-17, D-18, D-19, D-20, D-21.
- **Amended in place:** D-13 — the uncommitted-file shape for a halting
  skill's store write extends from `plain` to `separate-repo`; the holder
  is never committed to, branched, or pushed on a halt (kickoff 2026-09-22,
  annotated in `design.md`; REQ-E1.9 minted alongside).
- **Superseded:** none.

No decision contradicts a walked requirement; no inconsistency halt was
raised.

*Addendum at sign-off (2026-09-22, after the lens pass):* the batch applied
under §8 amended in place D-1, D-2, D-3, D-4, D-5, D-6, D-7, D-8, D-9,
D-10, D-11, D-14, D-15, D-16, D-17, D-18, D-19, and D-20 (each edit and its
K-number in the §8 edit list); D-12 and D-21 stand as drafted; D-13 keeps
its walk-time annotation. The ledger above records the state at the end of
the walk; the §8 list is the reconciled state the anchor seals.

**Readings recorded.**

- D-10's pin means a session inside a planwright checkout runs the
  checkout's scripts and doctrine even when the skill prose was loaded from
  the installed plugin cache. Intended, but a stale cache paired with fresh
  scripts is a mixed-version state (risk register row 4).
- D-4's marker field `project:` is validated against the identifier grammar
  and read by nothing today; it is the identity the deferred registry (D-21)
  will key on.
- D-3's containment of relative values inside the primary checkout, with
  D-12's holder outside it, is consistent: a holder is addressed by an
  absolute or `~/` value only.
- D-18 places `observation_targets` in the machine-local or adopter layer as
  guidance; the repo-tracked layer is not refused, since a `~/`-prefixed
  value is legitimately trackable.

Signed off: 2026-09-22

## 5. Verification approach

**Coverage mix.** Per `test-spec.md`'s intro and tags (cited, not
tallied): `[test]` wherever a script or fixture can prove it; `[Gherkin]`
for the two end-to-end authoring scenarios (REQ-E1.2, REQ-E1.3);
`[manual]` where handoff prose is the artifact (REQ-E1.3, REQ-E1.8,
REQ-E1.9); `[design-level]` for the docs, the doctrine amendment, and the
no-public-send rule (REQ-F1.4, REQ-G1.3, REQ-G1.4). Every REQ has an entry
(validator, 0 errors).

**Ownership.**

- `[test]` entries run under `mise run check` and the repository CI on
  every PR; the golden fixture (Task 4) replays after every migration
  task.
- `[Gherkin]` and `[manual]` entries belong to the release checklist's
  manual-verification sweep (`docs/release-checklist.md`), where every such
  entry in the repo is swept; the operator runs it.
- `[design-level]` entries are verified by the artifact's existence and
  coverage at the task's PR review and the doctrine-index and link checks.

**Kickoff-time read for REQ-F1.4.** Done: no deliverable in `tasks.md`
opens an issue, PR, or remote write for a fragment. The one remote write
that can carry fragments is the existing observation-carry chore PR, an
operator-run act, in a holder as in the work repository.

**Dead paths.** None found at the walk: each named verification appeared
to run in the environment that owns it.

*Correction at sign-off (2026-09-22, K19):* the lens pass found four dead
or vacuous paths the walk missed: the self-hosting-pin test proved nothing
(self-location already wins from a worktree, and the test inherited the
pin); Task 7's "scripted authoring run" needed the eval harness CI bars;
REQ-E1.9's `[test]` half had no scriptable actor; and REQ-G1.2 could not
pass while `mise.toml` composed the literal. All four are repaired in the
bundle (REQ-C1.2's decoy test; the `[Gherkin]` scenarios run on demand
through the behavioral-eval harness and are inventoried by `/drain`;
REQ-E1.9 retagged `[Gherkin + manual]`; the `mise.toml` task bodies in
Task 5). Ownership now reads: `[test]` under `mise run check` and CI;
`[Gherkin]` on demand through the harness plus the manual sweep (every
such entry also carries `[manual]` so `/drain` inventories it);
`[manual]` by the operator; `[design-level]` by artifact existence at PR
review.

Signed off: 2026-09-22

## 6. Task graph

**Source.** The `Dependencies:` lines in `tasks.md` (authoritative;
`scripts/spec-graph.sh specs/custom-spec-location` renders the same graph on
demand). After the kickoff edit below the graph is:

- Task 1 → Task 2 → Task 4, the spine every migration hangs off: the
  resolver, then the spec kind with its marker and postures, then the
  golden fixture and the literal guard. Task 4 deliberately gates every
  migration task so no caller moves without the check that proves the
  default is unchanged.
- After Task 4: Task 3 (chain convergence), then Task 5 (script callers),
  then Task 6 (addressing), serialized by the kickoff edit; Task 9
  (observations) runs in parallel with all three.
- Tasks 7 (authoring skills) and 8 (execution skills, gate, write zone)
  follow 5 and 6 and run in parallel with each other; Task 10 (doctrine and
  docs) closes on 7, 8, and 9.

**Critical path** (effort-weighted, from the `Estimated effort:` fields):
1, 2, 4, 3, 5, 6, 8, 10. Parallel work off the path: 9 (after 4) and 7
(after 6). The kickoff edit lengthened the path by Task 3 plus Task 6's
effort relative to the drafted graph, in exchange for no shared-file
conflicts.

**Kickoff edit.** Task 5 gains dependency 3 and Task 6 gains dependency 5,
because the three edit the same scripts: Tasks 3 and 5 both migrate
`scripts/check-anchor-freshness.sh`; Tasks 5 and 6 both touch
`scripts/dispatch-fetch.sh`, the orchestrate lock, and the fleet dispatchers.
Neither needs the other's result; the edges exist to avoid merge-of-main
conflict resolution (never a rebase). The intro prose in `tasks.md` records
the reason. Alternatives declined: a 5+6 cohesion bundle (same path length,
one three-day unit) and accepting the conflicts.

**Deliberate non-edges** (do not "fix" these):

- Task 4 depends on Task 2, not on Task 1 alone: the fixture is recorded
  once the resolver's spec kind exists and before any caller migrates.
- Task 9 does not depend on 3, 5, or 6: the observation scripts already
  take their store as a directory and are disjoint from the caller
  migration.
- Task 7 does not depend on Task 8, nor 8 on 7: authoring and execution
  skills are separate files.
- Task 10 waits for 7, 8, and 9 rather than shipping docs early: the docs
  describe what landed.

*Addendum at sign-off (2026-09-22, K3):* the doctrine amendments left
Task 10 for a new Task 6.5, depending on Task 2 only, which Tasks 7 and 8
now depend on, so no posture-dependent skill ships while the doctrine still
calls its configuration wrong. The critical path is unchanged (`spec-graph`
recomputed: 1, 2, 4, 3, 5, 6, 8, 10); Task 6.5 runs in parallel with 3, 5,
6, and 9. Deliberate non-edge added: Task 6.5 does not depend on 3, 5, or 6
(doctrine text needs the resolver's vocabulary, not the migrated callers).

Signed off: 2026-09-22

## 7. Risk register

**Decision-domains gap check.** Walked against the merged catalog
(`scripts/resolve-catalog.sh decision-domains`: the seed under
`doctrine/decision-domains.md`, no overlay additions on this machine).
Domains the spec touches, and where each is decided: data storage and
modelling (D-4, D-5); secrets and configuration (D-3, D-18, REQ-H1.3); API
surface (D-11, the `--target` and `--explain` flags); authentication and
authorization, reframed as the worker permission zone (D-15, widened by
exactly one root); concurrency, two work repositories writing one holder
(D-5, UID-named fragments); observability (`--explain`, the skipped-arm
warning); deploy and migration (none, REQ-H1.2); dependency adoption (none);
versioning (the marker's `layout: 1`); existing-seam reuse (the marker is
the one minted mechanism, D-4 names why the overlay config seam does not
fit; `observation_targets` reuses the config-knob seam). Domains not
touched: caching, queues, product strategy, packaging, domain knowledge, org
design, IP posture, LLM evaluation gates, human comprehension beyond
existing handoff conventions. **No undecided domain found.**

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | Migration breadth: two dozen scripts derive the root and a few dozen sites compose `specs/`; a missed caller keeps the old root silently. | Golden fixture (Task 4), literal guard, and the relocated-root suite (Task 5) no hardcoded caller can pass. Signal: a `specs/` literal outside the allowlist, or a posture-suite failure. |
| 2 | The two worktree corrections change behaviour with the option unset. | Named in REQ-A1.1 and asserted by the fixture. Signal: a worktree session that starts honouring machine-local config values it previously ignored. |
| 3 | The cross-root hygiene screen is a heuristic: it can miss a leak or refuse a clean fragment. | Refuse-not-rewrite (D-18); the human read at consumption stays the real guard. Signal: a refused clean fragment, or a path or hostname in a consumed fragment. |
| 4 | Mixed versions inside a planwright checkout: the pin (D-10) pairs checkout scripts and doctrine with skill prose loaded from the installed plugin cache. | Keep the cache current with the checkout; `--explain` shows which root answered. Signal: a skill naming a flag or doc the checkout lacks, or the reverse. |
| 5 | Skill instruction budgets are at their floor; Task 7 adds posture-reading steps to four skills. | Put the mechanics in `docs/spec-location.md` (or a doctrine doc) cited at point of use, not in skill bodies. Signal: the instruction-budget check red on Task 7's PR. |
| 6 | A holder halt note (REQ-E1.9) left uncommitted and forgotten. | The handoff names the file. Signal: a dirty holder checkout. The drain-sweep inventory of uncommitted store files is a gated Deferred entry in `tasks.md` (K20). |
| 7 | Guard allowlist growth: line-level exemptions accrete until the guard stops meaning anything. | Allowlist by line, only the namespace-literal sites D-11 names. Signal: an allowlist entry beyond those sites. |
| 8 | The tracked `mise.toml` pin applies only where mise is activated; a shell without mise sees no pin. | REQ-C1.2's test runs under mise in CI. Signal: a self-hosted run or test resolving the plugin cache again. |

Execution skills append research, performance, and security findings below
this table; appended rows never overwrite existing ones.

Signed off: 2026-09-22

## 8. Sign-off

### Lens review pass (first activation, full bundle)

**Class of the delta:** first activation, meaning-class (the walk minted
REQ-E1.9, amended D-13, and re-scoped several requirements). Artifact class
for lens selection: **spec** (`artifact-lenses`); the code-shaped lenses are
`n/a`. Path taken: **fan-out**, seven read-only reviewers (one per lens or
check item, the smaller check items paired), each grounded against the
repository by grep and citing what it consulted. Reports arrived as agent
hand-backs; the coordinator merged, deduped by root cause into the ledger
below (K-numbers), and ran the self-critique and adversarial re-validation
passes noted after the ledger.

**Lens-coverage table (spec lens set; caption: spec class, code lenses n/a).**

| Lens | Findings | Notes |
| --- | --- | --- |
| Contract correctness and internal consistency | 25 raw → K1, K2, K7, K8, K10, K11, K12, K15, K16, K20, K22 | Two mutually exclusive dispositions for a bad `spec_root` value; the "no other form" addressing rule versus directory-taking scripts; the golden fixture unable to assert the corrections it must assert. |
| Ambiguity and interpretation forks | 25 raw → K1, K2, K4, K6, K10, K11, K12, K13 | Nonexistent path, `--init` ordering, containment before or after symlink resolution, "main view" on a holder whose default branch is not `main`, the hygiene matcher, an empty value. |
| Citation and coverage integrity (incl. qualified cross-spec) | 13 raw → K3, K12, K13, K17, K18 | Mechanical REQ↔task↔test coverage clean; all 15 `obs:` UIDs resolve and support; misattributed or missing foreign cites (inception's exclusion, anchor-integrity's read surface, worker-permission-ergonomics REQ-A1.10, orchestration-concurrency REQ-F1.1, observation-recording D-9). |
| Dead verification paths and testability | 19 raw → K6, K7, K11, K19 | The self-hosting-pin test is vacuous (self-location already wins from a worktree; the test inherits the pin); Task 7's "scripted authoring run" needs the eval harness barred from CI; REQ-E1.9's `[test]` half has no scriptable actor; `mise.toml` literals block REQ-G1.2 as written. Section 5's "no dead paths" claim is corrected below. |
| Decision-domain gaps | none | Walked in section 7 against the merged catalog; every touched domain is decided. The reviewers raised no undecided domain. |
| Testability of every `Done when:` | 6 raw → K19 | Unbounded negatives ("rejects any other"), "the same suite" unnamed, "exactly one normative home" as a judgment call, REQ-E1.8 with no clause. |
| Cross-file consistency (repository) | 20 raw → K3, K5, K6, K8, K11, K13, K16, K17, K18, K21 | Three scripts derive the work repo from the spec dir's git toplevel and refuse otherwise; a Ready sibling spec mints `_flights/` as a third reserved child; the worker guard's five-arm trust chain versus D-9's four; `config-get.sh` runs a three-arm chain; seven skills hardcode `specs/_observations`. |
| Documentation and glossary drift | 16 raw → K3, K9, K13, K14, K15 | "canonical" in three senses, "checkout" against the glossary, "holder" undefined in the bundle, `planwright-root.yml` naming the third referent of "planwright root", the `path` knob type not existing, `/builder` not carrying the spec guards. |
| Rendered-content and data-hygiene safety | none (one derived item → K10) | No secret, credential, hostname, machine path, or private-repo identifier in the five files; no env-literal command path. Derived: an in-repo relocated root un-ignores class-2 state and `_pending/notes.md`. |
| Kickoff altitude check (REQ-H1.3) | 5 raw → K3, K6 | Triggered bundle; D-1 exists, is cited from the Goal, tasks deliver both halves. Defects: D-1 undercounts the doctrine surface, the amendment lands last behind every mechanism, criterion 3 of `customization-boundary` is not argued, the `storage-classes` class-2 interim note this bundle triggers is not touched. |
| Ship-gate check (REQ-L1.4) | 5 raw → K20 | A "later drain sweep", a Task 10 doc obligation, L79's sub-problem (1), and an implementation note are prose-only; the Deferred gate carries leaked template text. |
| Decided rules over enumerated claims (REQ-E1.2 cross-check) | 16 raw → K17 | "Three scripts assert…" is false (two assert, one infers); "a dozen more copies" over-counts; "exactly one file" allowlist falsified by today's edit; closed lists in REQ-F1.1, Task 6, D-20; the `version_file` precedent is not resolved by the shared knob resolver. |
| Performance · Concurrency / state · Error handling | n/a | Spec class: no execution path, shared state, or partial-failure semantics (`artifact-lenses`). |

**Finding ledger (deduped by root cause; disposition recorded after the
operator's decisions).** Severity is the highest among the merged raw
findings. "Fork" rows went to the operator as a decision; "apply" rows are
agent-recommended edits applied on approval of the batch; "accept" rows are
recorded readings.

| K | Root cause | Raw sources | Sev | Disposition |
| --- | --- | --- | --- | --- |
| K1 | Bad-value policy: REQ-A1.3 mandates both refuse-non-zero and by-layer degrade; empty value undefined; nonexistent path unclassified; missing marker's layer behaviour; multi-layer validation scope; value-grammar edge forms | contract F1 F17 F24 · ambiguity F1 F2 F3 F22 F24 F25 · citations F10 | blocking | fork Q1 |
| K2 | Addressing scope: REQ-D1.1 "no other form" on every seam versus the directory-taking scripts and path-driven tests; scope field grammar | contract F14 · ambiguity F9 F10 · dead-path F17 | blocking | fork Q2 |
| K3 | Doctrine amendments: D-1 counts one, the bundle needs several (`storage-classes` incl. the "Committed" sentence and the class-2 interim note; `accumulator-taxonomy`; every normative `specs/` site in `spec-format` incl. the reserved-children list that `tower-front-door` extends with `_flights/`; `orchestration-modes`; README index); amendment lands last behind every mechanism; criterion 3 unargued | altitude F1 F2 F3 F4 · contract F15 F16 · crossfile F2 F13 F14 · docs A6 A7 A8 C8 · citations F2 | blocking | fork Q3 |
| K4 | Hygiene screen: the matcher for path / hostname / private-repo identifier is undefined; screen keyed on the flag or on root inequality | ambiguity F17 F18 | blocking | fork Q4 |
| K5 | Install-root convergence: the worker guard runs five arms (installed roots), the tower guard is deliberately tighter (fleet-hardening REQ-C1.2); `config-get.sh` and `resolve-review-sequence.sh` run three arms; a tracked `PLANWRIGHT_ROOT` pin moves an operator-owned trust input into repo-tracked territory; the chain is documented in three places | crossfile F4 F5 F6 F7 · contract F13 | should-fix | fork Q5 |
| K6 | Self-hosting pin: "that checkout" ambiguous; inheritance claim wrong (each worktree carries its own tracked `mise.toml`); REQ-C1.2's test is vacuous (self-location already wins; the test inherits the pin) | ambiguity F8 · contract F19 · crossfile F8 · dead-path F3 | blocking | apply (batch) |
| K7 | Golden fixture: "any difference fails" cannot assert the corrections REQ-H1.1 orders; corrections invisible from the primary checkout; per-task expected-change set missing; baseline recorded after Task 1/2 state changes | contract F11 F12 · dead-path F1 F2 F11 F12 · docs C13 | blocking | apply (batch) |
| K8 | Work-repo derivation: `orchestrate-state.sh`, `orchestrate-meta-select.sh` (and `spec-status.sh` through it) derive the work repo from the spec dir's git toplevel and refuse in `separate-repo`/`plain`; `fleet-fence.sh` composes both paths; bare-repo case of `--primary` | crossfile F1 F10 F19 | blocking | apply (batch) |
| K9 | REQ-E1.8: the spec guards are project-bespoke, not in the builder catalog; `/builder` cannot wire them | docs A2 | blocking | apply (batch) |
| K10 | Posture semantics: REQ-B1.3 sends the holder's spec worktree to the work repo; "main view" undefined against a branch name and against ref-vs-working-tree; halt-note location and REQ-E1.9's scope (authoring vs execution halts); posture predicate (repository identity vs toplevel; gitignored in-repo root); `same-repo` rung missing from REQ-E1.5; carry in `plain`; `plain` creates no spec branch anywhere; `_observations` under the checkout-local view; `_pending/` and class-2 patterns un-ignored off the default root; write-zone "outside" | contract F6 F7 F8 F9 F10 F20 F21 F22 · ambiguity F6 F11 F12 F13 F14 F15 F16 · docs A5 B2 | should-fix | apply (batch) |
| K11 | Guard scope and build-config literals: `hooks/` has no code, `githooks/`, `mise.toml`, `lefthook.yml`, `.gitignore`, `specs/.markdownlint.jsonc` unnamed; "composed" undefined; REQ-A1.6 versus the namespace literal; D-19/REQ-G1.1 lack the allowlist classes; lefthook rationale misses in-repo relocation; seven skills hardcode `specs/_observations` incl. one command line | contract F2 F3 F4 F5 · ambiguity F20 F21 F23 · dead-path F6 F7 F8 · crossfile F11 F12 F20 · docs A5 | should-fix | apply (batch) |
| K12 | Resolver contract: stdout (bare path vs path+posture); `--explain` on install/repo kinds uncited; `PLANWRIGHT_REPO_ROOT` scope and validation, and its referent change unnamed | contract F18 · citations F6 · ambiguity F7 · docs A15 | should-fix | apply (batch) |
| K13 | `path` knob type does not exist; `version_file` is not resolved by the shared resolver; no existing option takes an out-of-repo path; the fleet home and the adopter overlay root as precedents | docs A3 C6 C7 · crossfile F16 F18 | should-fix | apply (batch) |
| K14 | Marker file name `planwright-root.yml` is the third referent of "planwright root" | docs A4 | minor | apply (batch): `planwright-spec-root.yml` |
| K15 | Terminology: "canonical" in three senses; `<checkout>` against the glossary; "holder", "store", "posture" overloaded; "work repository" ≡ "primary checkout root" never stated | docs A9 A10 A11 A12 A13 A14 A16 · contract F7 F8 | should-fix | apply (batch) |
| K16 | Task 3's chain-consumer list is over- and under-inclusive (`resolve-catalog.sh`, `resolve-config-knob.sh` delegate; `resolve-review-sequence.sh`, `inception-scaffold.sh` run chains) | crossfile F4 | should-fix | apply (batch) |
| K17 | Enumerations to decided rules: "three scripts assert", "a dozen copies", "exactly one file", closed lists in REQ-F1.1, Task 6, D-20, "both guards", "a few dozen sites", "the only path-valued knob" | docs C1–C5 C9–C12 · citations F13 · crossfile F9 F17 | should-fix | apply (batch) |
| K18 | Citation repairs: inception's exclusion is non-git not non-filesystem; anchor-integrity read-surface and reference-frame homes; worker-permission-ergonomics REQ-A1.10; orchestration-concurrency REQ-F1.1; observation-recording D-9 and the observation-routing draft; REQ-H1.2→D-3/D-4; REQ-A1.1 add D-8; REQ-F1.1's obs cites belong to REQ-A1.6; D-2's `plugin-script-invocation` misquote (sourced libs are the script convention); brief's "D-3 of spec-format" → bootstrap D-3; bare D-37 | citations F1 F3 F4 F5 F7 F8 F9 F11 F12 · crossfile F3 · docs A1 | should-fix | apply (batch) |
| K19 | Verification ownership: Task 7 "scripted run" vs `[Gherkin]`; REQ-E1.9 `[test]` half; REQ-A1.5's `_pending` actor is a skill; REQ-H1.2 baseline; Task 10's judgment clause; REQ-E1.8 clause; `[Gherkin]`-only entry on no recurring surface; unbounded negatives; the suite/time budget; REQ-F1.4 standing negative; section 5's "no dead paths" | dead-path F4 F5 F9 F10 F13 F14 F15 F16 F17 F18 F19 | blocking (F16) | apply (batch) |
| K20 | Ship-gate records: "a later drain sweep", the Task 10 doc obligation, L79 sub-problem (1), the Task 3 implementation note, template text in the Deferred gate, Out-of-scope vs Deferred wording | altitude F6 F7 F8 F9 F10 · contract F25 | should-fix | apply (batch) |
| K21 | D-15: the worker guard's containment is a git-free walk-up on a per-call hot path; who computes the resolved root for it | crossfile F15 | minor | apply (batch) |
| K22 | D-18's layer sentence reads normative; the walk recorded it as guidance | contract F23 | minor | apply (batch) |
| K23 | The kickoff's meaning-class edits owe a dated Changelog entry | citations note | minor | apply (batch) |

**Self-critique pass.** Re-scanned for what the fan-out under-represented:
(a) the `_flights/` collision with `tower-front-door` and the queued
`format-grammar` `spec-format` amendment are cross-spec coordination items
the walk missed entirely (folded into K3); (b) `PLANWRIGHT_REPO_ROOT`'s
referent narrowing is a fourth unnamed behaviour change with the option
unset (folded into K7's expected-change set and K12); (c) no reviewer asked
whether `spec_root` in a holder should be *discoverable* from the holder
(the deferred registry covers it; accepted).

**Adversarial re-validation (single sweep).** Refutations attempted on the
keep set: K6's "vacuous test" survives (the chain's last arm is
self-location, so from a worktree `install` prints the worktree with or
without the pin; only a decoy `CLAUDE_PLUGIN_ROOT` makes the pin
load-bearing). K9 survives (`config/guard-catalog.yaml` has no spec-guard
entries). K2 survives (usage strings of 25 scripts take a directory).
Resurrections attempted on the decline set: the lefthook in-repo-relocation
gap was initially declined as "CI backstops it" and is resurrected into K11
as an accepted limitation that must be *stated* in D-19. Nothing else moved.

### Dispositions

Every ledger row is dispositioned; none is deferred to a backlog.

- **Forks decided by the operator (2026-09-22):**
  - K1 → empty means unset and falls through; a well-formed value that
    points somewhere wrong is refused in every layer and never falls back;
    only malformed text follows the by-layer policy; the default is reached
    only by saying nothing. Declined: full by-layer degrade (a machine-local
    typo silently lands on `specs/`); refuse-everything (no way to cancel a
    repo-tracked value locally).
  - K2 → the name rule applies to skill arguments and identity seams;
    directory-taking scripts keep taking a directory; the scope field
    grammar is unchanged and callers pass the bare id. Declined: every
    script parses the name (a much larger migration, every path-driven test
    changes).
  - K3 → the doctrine amendments move into a new Task 6.5 after Task 2 and
    before Tasks 7 and 8, as a decided rule over every doctrine site,
    coordinated with `tower-front-door`'s `_flights/` and `format-grammar`'s
    queued amendment; docs stay last. Declined: moving the docs task
    earlier; widening Task 10's list in place.
  - K4 → three fixed pattern classes (absolute path, `~` path, dotted
    hostname with a public suffix or `.local`/`.internal`), listed in the
    spec-location guide; private-repository names stay with the human at
    consumption; the screen runs on every `--target` write. Declined:
    leaving the matcher to the implementer; absolute paths only.
  - K5 → the helper owns the four-arm chain; each guard composes its own
    trust set on it (the worker's installed-roots arm, the tower's distinct
    tighter set); the drift test checks derivation, not equality; the pin
    stays tracked and names the checkout itself; the shorter chains gaining
    arms is a named correction. Declined: equal trust sets; the pin in the
    untracked machine-local file.
- **Batch applied on the operator's approval (K6–K23):** each edit below.
- **Accepted readings (no edit):** an in-repo root that git ignores is
  `same-repo` and surfaces at the authoring commit step (K10); the lefthook
  pre-commit glob stops firing for an in-repo relocated root while CI still
  runs the check, stated in D-19 (K11); `observation_targets` in the
  repo-tracked layer is not refused (K22); the named-target writer does not
  consult the target checkout's own configuration (K10, ambiguity F19).

### Consolidated spec-edit list, sign-off batch (all in place on the Draft bundle)

The four files were rewritten whole; the substantive changes, by ledger row:

1. K1 — REQ-A1.2 edge forms; REQ-A1.3 rewritten to the bad-value rule;
    REQ-A1.4 refusal in every layer; D-3 rewritten with two more declined
    alternatives; Task 2 deliverables and Done-when; test-spec REQ-A1.2,
    REQ-A1.3.
2. K2 — REQ-D1.1 scoped to skill arguments and identity seams, trailing
    slash on either form; REQ-D1.3 field grammar unchanged; D-11 rewritten
    with the declined alternative; Task 6 retitled and rescoped; test-spec
    REQ-D1.1, REQ-D1.3.
3. K3 — D-1 "amendments" with the evidence-criterion argument; REQ-G1.4
    as a decided rule naming the doctrine homes; D-20 rewritten; new
    Task 6.5 with Tasks 7 and 8 depending on it; Task 10 reduced to docs;
    test-spec REQ-G1.4; Sources doctrine list.
4. K4 — REQ-F1.3 rewritten to the three pattern classes; D-18 rewritten
    with the declined path-shaped alternative and the `observation-routing`
    disposition; Task 9 and test-spec REQ-F1.3.
5. K5 — REQ-C1.1 shared chain, per-guard policy, fleet-hardening REQ-C1.2
    cited; D-9 rewritten with the declined equal-sets alternative; Task 3
    deliverables and drift test; test-spec REQ-C1.1; REQ-A1.1 names the
    chain convergence as a correction.
6. K6 — REQ-C1.2 config-root expansion, nearest-config, non-vacuous decoy
    test; D-10 rewritten (worktree copy, trust note, declined machine-local
    pin); Task 1 Done-when; test-spec REQ-C1.2.
7. K7 — REQ-A1.1 as a decided rule with the named corrections; REQ-H1.1
    expected-change set from both vantage points, baseline timing named;
    REQ-H1.2 anchors in the baseline; Task 4 rewritten; Task 3 and Task 5
    Done-when declare their sets; test-spec REQ-A1.1, REQ-H1.1, REQ-H1.2.
8. K8 — REQ-E1.4 names the derivation scripts; REQ-B1.4 bare repository;
    D-8 bare-repo case; Task 1 and Task 5 (orchestrate state, meta-select,
    status render, fleet fence); test-spec REQ-B1.4, REQ-E1.4.
9. K9 — REQ-E1.8 recipe not `/builder`; D-16 rewritten with the declined
    catalog alternative; Task 7 handoff clause; Task 10 recipe; test-spec
    REQ-E1.8.
10. K10 — REQ-B1.3 owning repository; REQ-E1.1 identity predicate,
    gitignored root, `--posture`; REQ-E1.3 no branch anywhere; REQ-E1.5
    all three rungs and the default branch; REQ-E1.7 "different repository
    or none"; REQ-E1.9 scoped to execution halts in the primary view
    working tree; REQ-A1.5 checkout-local view and ignore rules on init;
    REQ-F1.1 carry no-op in `plain`; D-4 init writes ignore rules; D-5, D-6,
    D-7, D-12 (unchanged), D-13, D-14, D-17; Task 2, Task 8, Task 9;
    test-spec REQ-A1.5, REQ-B1.3, REQ-E1.1, REQ-E1.3, REQ-E1.5, REQ-E1.7,
    REQ-E1.9, REQ-F1.1.
11. K11 — REQ-A1.6 "as a filesystem path", build-config tasks, namespace
    carve-out; REQ-G1.1 scope and the three allowlist classes; REQ-G1.2
    task bodies and the travelling lint relaxation; D-19 rewritten with the
    lefthook limitation stated; Task 4, Task 5, Task 9 (skill command
    lines); test-spec REQ-A1.6, REQ-G1.1, REQ-G1.2.
12. K12 — REQ-A1.8 every kind; REQ-B1.1 variable scope and validation;
    REQ-E1.1 default stdout; D-2, D-6, D-8; Task 1; test-spec REQ-A1.8,
    REQ-B1.1.
13. K13 — D-3 `path` type added as a deliverable, precedent claim
    replaced; Task 2; Sources code map.
14. K14 — marker renamed `planwright-spec-root.yml` (REQ-A1.4, D-4, Task 2,
    test-spec REQ-A1.4).
15. K15 — Terms paragraph under Goal; `--canonical` renamed `--primary`
    (REQ-A1.9, D-2, D-7, Task 2, Task 8, test-spec REQ-A1.9); REQ-A1.4
    "primary view"; Task 2 Done-when `<primary checkout>/specs`; D-4 names
    the collision it avoids.
16. K16 — Task 3 consumer list as a decided rule with the corrected
    illustration; D-9 consumer list.
17. K17 — REQ-A1.7, D-2 ("every script that asserts"); D-8 ("every
    remaining inline call"); D-2 Chosen-because; REQ-F1.1, Task 6, D-20
    lists as decided rules; REQ-C1.1 "every command guard"; D-19 "every site
    the guard flags"; Sources code map rewritten.
18. K18 — Out-of-scope inception wording; REQ-E1.5 cites anchor-integrity;
    REQ-E1.7 cites worker-permission-ergonomics REQ-A1.10; REQ-A1.7 cites
    orchestration-concurrency REQ-F1.1; REQ-F1.2 and D-18 cite
    observation-recording D-9; REQ-H1.2 cites D-3, D-4; REQ-A1.1 cites D-8,
    D-9; REQ-A1.3 drops D-4; obs cites moved from REQ-F1.1 to REQ-A1.6;
    D-2's sourced-library rejection re-grounded; D-13 cites obs:e144633c;
    brief header cites bootstrap D-3 and D-37.
19. K19 — Task 7 Done-when (harness on demand, manual sweep, REQ-E1.8
    clause, budget); test-spec REQ-E1.2 and REQ-E1.9 `[Gherkin + manual]`,
    REQ-A1.5 `[test + manual]`, REQ-F1.4 `[test + design-level]`; Task 6
    "rejects a bundle-file path"; Task 5 "targeted relocated-root subset
    within the suite time budget"; Task 10 Done-when evaluable; brief §5
    corrected.
20. K20 — two Deferred entries added (drain-sweep inventory; L79
    sub-problem (1)); the reverse-registry gate's template text removed;
    Out-of-scope wording; Task 10 carries the holder-halt-note sentence;
    Task 3 carries the self-location note; brief risk row 6.
21. K21 — REQ-E1.7 and D-15: the root computed once at dispatch and handed
    through the worker settings; Task 8.
22. K22 — D-18 "recommended home … not refused".
23. K23 — dated Changelog entry for the sign-off edits.

The eleven walk-time edits are listed in §3; this list restarts at 1. Every edit is a spec-file change on the
Draft bundle, applied in place per the pre-merge rule.

### Post-batch verification

- **Validator:** `spec-validate` — 0 errors, 0 warnings after the batch.
- **Lint (REQ-B1.2):** `markdownlint-cli2` over the brief and the four spec
  files — 0 errors.
- **Post-lens stale-reference sweep (REQ-B1.5):** grep over the bundle and
  the earlier brief sections for the renamed flag, the renamed marker, the
  converted counts, and the old dependency lines; the bundle carries none;
  the brief's header, §2 glossary, §2 lens note, §4 ledger, §5 dead-path
  claim, §6 graph, and §7 row 6 reconciled with dated addenda.
- **Recorded-claim re-derivation (REQ-B1.3, D-4):** re-derived
  mechanically after the batch, as data (fixed-string grep): distinct
  `obs:` UIDs cited in `requirements.md` = 15 (header block claim holds);
  `### D-` headings = 21 (§4 ledger holds); `- **REQ-` bullets = 40 and
  `### REQ-` test entries = 40 (coverage 1:1, the validator agrees);
  task headings = 11 (10 plus 6.5); risk rows = 8; Deferred entries = 3
  (section-scoped comparator). Comparator ran; all match.
- **Enumeration cross-check (REQ-E1.2):** every enumerated count the
  reviewers flagged was converted to a decided rule (K17) or verified
  (the two command guards, the fifteen fragments, the `dispatch_backend_per_spec`
  precedent); the remaining lists in the bundle are marked illustrative.
- **Altitude check:** triggered bundle; D-1 present, cited from the Goal,
  now naming the amendments plural with the evidence argument; the task
  decomposition matches (Tasks 1–9 the capability, Task 6.5 the doctrine
  before the skills, Task 10 the docs).
- **Ship-gate check:** every out-of-band item named in the bundle or brief
  now carries a Deferred entry or a task deliverable.

### Sign-off record

First activation signed off 2026-09-22 by the operator after the approval
summary (what is approved: the restated goal, the reconciled requirement and
design ledgers, the verification ownership, the task graph with Task 6.5,
the risk register, and the dispositioned lens ledger; what changes: the
stored Draft→Ready flip, the anchor below, the commit, the push, the draft
PR, and the ready-flip after green CI on its head commit; merge stays the
operator's second key and the first dispatch derives Active). Status flipped
Draft→Ready on all four spec files, `Last reviewed:` 2026-09-22; validator
re-run at Ready: 0 errors, 0 warnings. Observations recorded this run under
`specs/_observations/entries/` (four fragments: the kickoff first-question
density recurrence, the lens fan-out report channel, the brief template
citation and worktree-name mismatch, and a `skill-drift(spec-kickoff)` on
the lens-set selection); the store guard passed.

Class: meaning
Lens-pass: the *Lens review pass (first activation, full bundle)* above in
this section — spec lens set, seven-reviewer fan-out, the lens-coverage
table, the K1–K23 ledger with every row dispositioned (five operator forks,
eighteen batch edits, four accepted readings), the altitude and ship-gate
check items, the self-critique and adversarial re-validation passes.
Anchor: `e491833aa36c507d74bb2568b15375425c3c300d` — computed as
`scripts/spec-anchor.sh specs/custom-spec-location`

## 9. Amendment log

(none yet)
