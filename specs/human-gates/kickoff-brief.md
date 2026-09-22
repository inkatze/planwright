# Human gates — Kickoff brief

## 1. Header

- **Spec path:** `specs/human-gates`
- **Spec commit at walkthrough start:** `c7abfee`
- **Walkthrough date:** 2026-09-22
- **Mode:** first activation (Draft, no prior brief)
- **Validator outcome (pre-flight):** `spec-validate.sh` — 0 errors, 0 warnings
  (format-version 2 bundle)
- **Config:** `commit_on_kickoff: true`,
  `mark_spec_pr_ready_on_kickoff: true`, `kickoff_ready_ci_wait: 10m`
  (defaults; no local override present)
- **Working location:** spec branch `planwright/human-gates/spec`, checked
  out in the worktree `.claude/worktrees/no-more-flip-ready-invariant` (the
  worktree `/spec-draft` committed the bundle from; used in place of the
  `<spec>-spec` name since the branch is already checked out here)
- **Doctrine resolution:** all nine rule docs the skill names resolved under
  the plugin's core `doctrine/` (no overlay layer supplies any of them); the
  decision-domains catalog is resolved at section 7
- **Structured decision/transcript log:** no harness-provided log path in
  this session; the turn mirror is skipped rather than improvised into the
  repository
- **Independent cold read:** `/spec-walkthrough specs/human-gates` offered as
  an optional complement; not a dependency of this walkthrough

## 2. Goal & glossary

**Restatement (agent's own words, confirmed by the operator).**
planwright's reserved-control list (never auto-merge, never flip a PR ready,
never rewrite history, every framework PR a draft) was written when agents
ran without guards. The guards now exist, the repo has twice ruled the flip a
preference, and yet the skills still say never and the operator flips every
unit by hand. This spec replaces the list with a test: an act stays human
only when it is irreversible for other people, or when it is the approval
act that ends the framework's review contract. Under that test, authorizing a
merge and signing off a finding stay human at every tier and under every
policy value. The draft→ready flip, a worker merging the PR base into the
branch it owns, and reshaping commits no remote holds become policies with
shipped defaults an overlay may change. The never-push rule the review skills
carry is relabelled a composition contract between skills, not a trust rule.
Sign-off moves off the flip onto the merge, carried by a `Planwright-Sign-Off`
commit trailer instead of a subject suffix, so an agent flipping a PR ready
approves nothing. Every guard, profile, skill, and doc then restates one
doctrine list instead of carrying its own.

**Rules out.** Lifecycle hooks as an operator seam; the `pr-ready` fleet
attention record; widening `review_sequence` beyond the plugin; re-arming
verification and reconcile fan-out after a merge; the ready-guard's
predicate, parse cost, and MCP naming residual; acting on a spec that is
neither Ready nor Active, and auto-chaining `/orchestrate` into `/spec-kickoff` (both carried forward
unchanged); the release publish gate; the dotfiles restatement; and any agent
merge outside a configured policy, at any tier, under any value.

**Assumes.** The ready-guard, `converge-sync-main.sh`, the shared knob
resolver (`resolve-config-knob.sh` with its by-layer malformed policy), the
purged-identifier screen, the doctrine-index and options checks, and
`check-instructions.sh` exist and are reused as-is. GitHub auto-merge and the
repository's ruleset (squash only, zero required approving reviews, two
required status checks) are the merge substrate. The agent session's GitHub
login is the operator's own today; a distinct identity is recommended, never
required.

**Implicit terms surfaced and resolved.**

- **tier** — worker, orchestrator, tower. The attended kickoff and draft
  sessions are tower-class (attended, owning no unit branch).
- **owned branch / unit branch** — the `planwright/<spec>/task-<id>` branch
  the session was dispatched on. A spec branch is nobody's unit branch.
- **protected branch** — main plus any ref the host's ruleset protects; how
  a guard learns that set is carried into the REQ-F / REQ-G walk.
- **reserved-control spelling** — a concrete command form (CLI or MCP) that
  performs a reserved act, in the sense the tower queue's reserved-control
  check already uses.
- **approval act** — the merge under `merge_policy: human`; enabling GitHub
  auto-merge (or an approving review with it enabled, under a detected
  identity split) under `on-approval`.

Signed off: 2026-09-22

## 3. Requirements walkthrough

Walked group by group, A to H, each restated and probed with the operator;
every edit below landed in place on the Draft bundle as decided.

**REQ-A — The human-gate list.** Intent confirmed: one test, one doctrine
source, every rule labelled by kind, bootstrap rules superseded by pointer.
Decisions: bootstrap D-26, already carrying a scoped `Superseded-by:
kickoff-lifecycle D-6` line, gains a second scoped pointer to human-gates D-2
beneath it (the form D-6's own line demonstrates); Task 1 also delivers the
bootstrap REQ-J1.1 and REQ-J1.4 pointers REQ-A1.4 requires, naming both of
REQ-J1.4's replacements. The tower force-push on request was checked against
the gate test and found consistent (the human requests, the tower executes).

**REQ-B — Sign-off at the approval act.** Intent confirmed. Checked: no
unmerged remote-tracking branch carries a `[pending-sign-off]` subject, so
the one-line migration strands nothing in flight (accepted risk, recorded in
section 7). Decision: the reverted original is dropped by pairing git's own
`This reverts commit <sha>` body line to the trailered commit, as
gate-wiring's regeneration already does; D-3's "by construction" sentence
now says exactly what the trailer read excludes. `PS-<n>` allocation (next
free id over the range's trailers, reverted ids stay consumed) needed no
change.

**REQ-C — Ready-flip policy.** The operator reconfirmed D-4's declared
departure: `ready_flip_policy` ships `agent` (the value renamed `unit-owner`
at the sign-off lens pass, section 8). Decision: a parked flip is a
self-identifying Awaiting-input bullet (`pending ready-flip:` lead) that
every Awaiting-input predicate ignores and the next passing run removes,
closing the deadlock between REQ-C1.2 and REQ-C1.4. The kickoff's own spec-PR
flip stays on its separate knob and runs where no tower profile applies.

**REQ-D — Merge policy.** Decisions: a `policy-class` merge flips an admitted
draft PR ready itself through the ready-flip helper, whatever
`ready_flip_policy` says, since the class predicates include every flip
precondition and the flip approves nothing; the strategy resolves from a new
`merge_class_strategy` knob (`sole-allowed` default, then `squash`,
`merge`, `rebase`), falling to `on-approval` on ambiguity, a disallowed
method, or a failed host query. The operator asked for "the repo's default
by default"; the host exposes no repository-level default method, only the
allowed set, so `sole-allowed` is the honest name for that intent.

**REQ-E — Worker base merge.** Decision: a `resolve` conflict commit carries
the sign-off trailer, so it is listed for the approval act and the merge
class never admits it; its rejection recipe is a `halt` re-run with a hand
resolution, never a revert.

**REQ-F — History rewriting.** Decisions: REQ-F1.1 says "unit branch", so
unpushed spec-branch commits stay append-only under REQ-F1.5; the protected
set is a core floor (`main`, `master`, the `planwright/*/spec` pattern) no
layer can shrink plus a `protected_branches` knob's additions, read locally
and glob-matched. The "same turn as the request" condition on the tower
force-push is not machine-checkable; carried to section 7.

**REQ-G — Guards and profiles.** Decision: each fixture line carries the
spelling, its class, the tier, the policy value, and the expected verdict;
Task 5 ships all-deny verdicts and Task 6 rewrites the column when the
policy guard lands.

**REQ-H — Prose surfaces.** Intent confirmed, no edit. REQ-H1.1's
word-neutral bound against Task 3's added prose is a risk, not a spec gap
(the bundle's answer is citation over inline text); carried to section 7.

### Consolidated spec-edit list

All Draft in-place edits, applied with the operator during the walk:

1. Task 1: second scoped D-26 pointer; REQ-J1.1 and REQ-J1.4 pointers with
   both of J1.4's replacements named; Done-when without an enumerated count.
2. D-3, Task 2: revert pairing via git's revert body line.
3. REQ-C1.4, D-5, REQ-D1.3, test-spec REQ-C1.4: the `pending ready-flip:`
   parking lead, exempt from every Awaiting-input predicate, written in the
   unit's checkout, composed with an existing park bullet.
4. REQ-D1.4, REQ-C1.5, D-6, Task 4, Task 9, test-spec REQ-C1.5 and
   REQ-D1.4: class merge subsumes the flip, runs in the worker tier;
   `merge_class_strategy` with its value set and fall-through arms.
5. REQ-E1.2, D-7, Task 10, test-spec REQ-E1.2: `resolve` commits carry the
   trailer; `halt` re-run as the rejection recipe; Task 10 depends on Task 2.
6. REQ-F1.1, D-8, test-spec REQ-F1.1: "unit branch"; the spec-branch amend
   case named.
7. REQ-F1.5, D-9, Task 4, Task 6, test-spec REQ-F1.5: core protected floor
   plus the `protected_branches` knob, encoding and matching stated.
8. REQ-G1.1, D-9, Task 5, Task 6, test-spec REQ-G1.1: five-column fixture
   lines; Task 6 owns the verdict rewrite and cites REQ-G1.1.
9. Task 4: citations and fail-closed values cover every knob.

### Mid-walk delta-scoped lens pass

Run once over the whole walk delta (one read-only Opus sub-agent, all nine
lenses, the delta and its dependents; the two spec-format cross-file items
checked: every namespace-qualified citation in the delta resolves, and the
four REQs the delta extended without a paired test-spec edit were paired
before this section closed). Findings were verified against the bundle and
the scripts they cite before disposition (the tower queue's shipped
protected set includes `master`; the config model is flat one-level YAML;
format v2 allows one reference bullet per task).

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 6 | protected-set default and encoding; the class helper's flip against the tier deny; the merge predicate unexempted; a revert recipe that restores a conflict |
| Security | 1 | an overlay could shrink the protected floor |
| Error handling and failure modes | 1 | no arm for a failed host method query or a disallowed explicit strategy |
| Performance | none | the only performance-relevant delta is D-9's refusal to put a host query inside the guard's bound |
| Concurrency / state | 2 | which surface the parking bullet lives on; two writers, one bullet per task |
| Naming, readability, structure | 1 | `repo` named a host default the design denies exists |
| Documentation | 3 | the strategy value set stated only in D-6; an enumerated count in Task 1; REQ-J1.4's two rules |
| Tests / verification | 3 | REQ-C1.4 and REQ-F1.1 unpaired; the fixture verdict column unowned after Task 6 |
| Cross-file consistency | 4 | Task 10's missing edge to Task 2; Task 4's citations; the six `kickoff §3` citations resolving to this section |

Disposition: all eighteen applied, as items 1 to 9 above record (the
operator chose "apply all as proposed", including the three that carried a
choice: the helper's tier, the `halt` re-run recipe, the `sole-allowed`
name). The validator reports 0 errors, 0 warnings after the edits.

Signed off: 2026-09-22

## 4. Design walkthrough

Every decision in `design.md` was walked inside the requirements group that
cites it; the reconciled ledger:

| Decision | Outcome |
| --- | --- |
| D-1 | Confirmed. Expression-only reword: the "nine surfaces" count in its alternatives became the decided rule "every surface that restates the list already diverges from the others" (the count was stale on the day of the walk). |
| D-2 | Confirmed; the second scoped D-26 pointer is how it lands. |
| D-3 | Amended: the revert pairing via git's revert body line (section 3, REQ-B). |
| D-4 | Confirmed; the declared departure (the unit-owner flip as default) reconfirmed by the operator. Amended at the sign-off lens pass: value renamed `unit-owner`, owning-skill set and attended-session jurisdiction stated (section 8). |
| D-5 | Amended: parking lead, exemption scope, surface, and bullet composition (section 3, REQ-C). |
| D-6 | Amended: helper tier, flip subsumption, `merge_class_strategy` and its fall-through arms (section 3, REQ-D). |
| D-7 | Amended: trailered `resolve` commit with the `halt` re-run recipe (section 3, REQ-E). |
| D-8 | Amended: unit branch only; spec branch excluded (section 3, REQ-F). |
| D-9 | Amended: core protected floor plus the knob; five-column fixture lines (section 3, REQ-F and REQ-G). |
| D-10 | Confirmed. |
| D-11 | Confirmed. |
| D-12 | Confirmed. |
| D-13 | Confirmed. |
| D-14 | Confirmed. |

Superseded: none. No decision contradicts a walked requirement; the
cross-cutting concerns (security posture, decision-domains walk,
instruction budget, release note) stand as drafted, with the section 7 gap
check re-walking the catalog against the amended bundle.

Signed off: 2026-09-22

## 5. Verification approach

**Coverage mix.** Per the tags in `test-spec.md`: the bulk is `[test]`,
with `[Gherkin]` scenarios over the helpers and a stubbed host CLI,
`[design-level]` for the doctrine doc's presence and kind column, and
`[manual]` for the two live acts (the reviewer-request probe, REQ-C1.7; one
recorded operator-requested force-push, REQ-F1.2) plus, after this walk, the
on-demand skill evals behind REQ-B1.7, REQ-B1.8, and REQ-F1.3.

**Ownership.** `[test]` entries run under `mise run check`, which the
repository CI runs on every PR against the head commit. `[manual]` entries
are run and written up by the executing worker: the REQ-C1.7 probe lands in
this brief's risk register (Task 8), the REQ-F1.2 live run and the
`eval:skill` runs in the task PR bodies. `[design-level]` entries are read by
the sign-off lens pass of this kickoff and by Task 1's review.

**Dead paths.** Three `[test]` entries named a prompt-eval run of skill
prose, which `check:no-ci-evals` keeps out of CI and `check`. Decision:
retagged `[test + manual]`, a CI grep fixture over the skill bodies carrying
the mechanical half (the mechanism REQ-H1.1 already uses) and the on-demand
`eval:skill` run the behavioural half; Task 3's Done-when now names both. No
other entry names a verification that cannot run where its tag says.

Signed off: 2026-09-22

## 6. Task graph

Reconstructed from the `Dependencies:` lines in `tasks.md` (authoritative;
`scripts/spec-graph.sh specs/human-gates` renders the same graph on demand).

**Waves.** Tasks 1 and 5 are ready at once. Task 1 releases Tasks 2 and 4;
Task 2 releases Task 3; Tasks 4 and 5 together release Task 6. Task 6
releases Tasks 7, 8, and 11, and (with Task 2) Task 10. Task 7 releases
Task 9. Task 12 closes the bundle after Tasks 1, 3, 7, 9, 10, and 11.

**Critical path.** Effort-weighted from the `Estimated effort:` lines:
1 → 4 → 6 → 7 → 9 → 12, eight days of the bundle's total (the total is the
sum of the effort lines in `tasks.md`); the Task 5 branch carries half a day
of slack before Task 6, and the Task 2 → 3 branch finishes well before
Task 12 needs it.

**Deliberate non-edges.**

- Task 5 does not depend on Task 1: the fixture lists spellings, not rules.
- Task 8 does not depend on Task 7: the re-draft corrective is independent
  of the flip helper.
- Task 3 does not depend on Task 4 or Task 6: it stamps trailers (Task 2)
  and rewrites prose; no knob or guard is read.
- Task 9 does not depend on Task 8 or Task 10.
- Task 11 and Task 3 both edit `/execute-task` prose with no edge between
  them; the base sync Task 10 sanctions handles the overlap.
- Task 12 does not list Task 8: Task 8's deliverable is a guard allowlist
  and a test, not a prose surface the sweep restates.

Signed off: 2026-09-22

## 7. Risk register

**Decision-domains gap check.** The merged catalog resolved through
`scripts/resolve-catalog.sh decision-domains` (core seed; no overlay
layers present). Domains touched and decided in the bundle: api-surface
and secrets-config (the knobs, D-4, D-6, D-7, D-9, and the options rows
REQ-H1.3 requires), auth and org-design (D-9, D-14, the worker tier owning
the helpers), observability (the PR records, D-5, D-6), versioning-scheme
(the one-release `--marker title` deprecation, D-3; the release note),
llm-output-quality (no model in any guard, D-5, D-6, D-9),
human-comprehension (D-13), existing-seam-reuse (D-5, D-9),
knowledge-engineering (the three rule kinds, D-2, D-10). Touched and
accepted as drafted: concurrency between a policy change and a mid-session
guard read (last-write-wins, `design.md` cross-cutting concerns) and
deploy-migration (the `unit-owner` default reaching adopters through the
release note). Untouched: data-storage, caching, queues-async,
dependency-adoption, product-strategy, packaging-pricing, ip-posture. One
gap found and decided in this walk: the window between class-predicate
evaluation and the merge call (concurrency); D-6, REQ-D1.4, and the
REQ-D1.4 test-spec entry now carry a head re-pin before the merge call.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | Task 3 adds prose (approval statement, SHA printout, attended apply-then-review) to skill surfaces the instruction-headroom spec measured as saturated; REQ-H1.1 demands word-neutral or better. | Citation over inline text, per D-10 and the cross-cutting instruction-budget rule; if a surface cannot absorb it, a budget amendment rather than a trimmed rule. Signal: `check-instructions.sh` red on Task 3's first commit. |
| 2 | REQ-F1.2's "same turn as the request" condition on a tower force-push is not machine-checkable. | The tower queue's standing-decision refusal and the `check-confirmation.sh` shape (Task 11) carry it; the policy guard checks only tier and target ref. Signal: a force-push with no operator request in the same turn. |
| 3 | Branches opened before the trailer change carry `[pending-sign-off]` subjects the new regeneration no longer reads. | Checked at this walk: no unmerged remote-tracking branch carries one. Signal: a checklist regenerating to `none` on a branch that listed items. |
| 4 | The reviewer-request un-draft (obs:02396e39) may not reproduce on the host today. | Task 8 records the probe's outcome either way and appends it here; the corrective stays wired as a no-op guard if the side effect is absent. |
| 5 | A commit or base move lands between class-predicate evaluation and the merge call. | Head re-pin before the merge call (D-6, REQ-D1.4, decided here). Signal: a record comment naming a SHA other than the merged one. |
| 6 | Adopters upgrading get `ready_flip_policy: agent` without opting in. | Release note naming the behaviour change (D-4, Task 12); one overlay line restores `human`. Signal: an issue reporting PRs going ready unexpectedly. |
| 7 | A glob typo in `protected_branches` protects nothing, silently. | The core floor cannot be removed by any layer; the resolver test covers an added glob (REQ-F1.5). Signal: a push admitted to a ref the operator meant to protect. |
| 8 | Under a shared GitHub identity, `on-approval` enforcement is client-side only: the merge-spelling deny is what stops an agent enabling auto-merge. | Accepted in D-14; a detected identity split adds the server-verified path. Signal: auto-merge enabled on a PR with no human in the session. |
| 9 | Reducing the profiles to the floor (Task 6) could drop a floor entry by mis-edit. | REQ-G1.3's wiring tests pin every floor entry in both profiles; the five-column fixture drives both. |
| 10 | The policy guard reads knobs on every guarded git call; a slow resolver turns into false denies at the wall-clock bound. | Bounded, fail-closed read (REQ-G1.4); the read rides the existing shared resolver with no host call. Signal: denies citing a timeout rather than a policy. |

Rows appended by execution skills (research, performance, security
findings; the Task 8 probe record) follow these and never overwrite them.

Signed off: 2026-09-22

## 8. Sign-off

### Lens review pass (full bundle, first activation)

**Scope and fan-out.** Full bundle, per `kickoff-verification`: one
read-only Opus sub-agent per lens, ten in parallel, each briefed on the
decisions already recorded in this brief, followed by a merge and dedupe by
root cause. Artifact class: **spec**, per `artifact-lenses`. The spec set's
own lenses were covered as follows: contract correctness by the correctness
lens; ambiguity and interpretation forks by a dedicated lens; citation and
coverage integrity and cross-file consistency by the cross-file lens (every
namespace-qualified foreign citation and every observation UID resolved);
dead verification paths and testability by the tests lens; decision-domain
gaps by section 7; documentation and glossary drift by the documentation
lens; rendered-content safety not applicable (nothing in the bundle is
rendered into an executing context). The three code lenses the spec class
normally marks `n/a` (performance, concurrency, error handling) were run
deliberately and are declared here, because the bundle specifies helpers
and guards whose failure, ordering, and per-call cost are part of its
contract. Findings were verified against the bundle and against the
scripts, profiles, and doctrine they cite before disposition (the sync
script's exit codes; the profiles' deny lists; the ready-guard's
jurisdiction rule; the config model's flat shape; the purge guard's
word-window; the plugin-global hooks file).

The kickoff-specific **altitude check** ran inline: the pinned seed claim
in `## Sources` is an altitude trigger, D-1 exists and is cited from the
Goal, and the task decomposition matches the four altitudes it fixes
(doctrine in Task 1; capability in Task 4; mechanism in Tasks 5 to 11;
prose in Task 12). Not a finding. The **ship-gate check** found one
out-of-band fix named only in prose, the dotfiles restatement; it now
carries a gated Deferred bullet in `tasks.md`. The `--marker title` removal
is delivered as a gated deferral by Task 2 itself.

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 10 | The flip helper placed before its PR exists; park commits moving the pinned head; `human` contradicted by the class helper's flip; two policies with no knob; a flat fixture verdict the ready-guard cannot give; per-item revert on a shared commit; a rejected `resolve` item with no exit; short-name floor entries against full ref names; `protected_branches` failing open |
| Security | 7 | The composed parking bullet swallowing a `halt` park; the class predicate reading a branch-local copy; no mechanical hard-disqualifier path list; floor entries a profile cannot express; profiles carrying no `master` or spec-branch deny; a stale tracking ref allowing; no sanitizer pinned |
| Error handling and failure modes | 9 | An adopter-layer malformed value degrading to the permissive default; the park write with no failure arm; an act failing after its record; only one of the sync's failure exits handled; an unreadable range emitting an empty checklist; a fall-through notifying nobody; transient failure conflated with not-ready; the corrective with no failure arm |
| Performance | 3 | Multi-knob resolver reads on every Bash call; the CI rollup wait run twice on the class path; `check:test-time` absent from the test-heavy tasks |
| Concurrency / state | 5 | Park-removal commits moving the head after the predicates; the composed bullet; base moves not re-pinned; a record with no converse rule; two writers of one bullet |
| Naming, readability, structure | 7 | "merge" naming two acts; "class" carrying three meanings; REQ-D1.4 packing five rules; REQ-D1.7 out of order; decision titles outrun by amended bodies; "the helper" with five referents; `agent` and the conflict knob's suffix |
| Documentation | 7 | Doctrine docs stating the old gate unnamed by any task; README index rows unguarded; the release note with no carrier; the purge guard misused for phrasings; a profile that does not exist named; "nine divergent copies" in D-10; a stale matcher-model doc |
| Tests / verification | 11 | The purge guard unable to carry phrasings; the resolver contradiction; unevaluated or unpaired entries (REQ-F1.3, Task 10, REQ-G1.5, REQ-C1.4, REQ-F1.1); a coverage-mix sentence misstating `[manual]`; wrong task pins; `[Gherkin]` with no scenario; an assertion that cannot fail; a grep that cannot anchor; a detector with no subject |
| Cross-file consistency | 8 | An observation gloss matching neither source; "non-Ready" for "neither Ready nor Active"; `human` versus the class helper; the owned push listed as a policy; an unpaired REQ-D1.3 clause; REQ-A1.4's pointers unverified; scripts and docs citing the superseded bootstrap rules; task citations not matching test-spec pins |
| Ambiguity and interpretation forks (spec set) | 6 | The exemption's scope in a composed bullet; Task 7's Done-when against REQ-D1.4; "full ref name"; the knobless policies; "live" read where; the owning-skill set |

Raw findings across the ten lenses plus the two check items and the
self-critique pass (which added the attended-session jurisdiction gap, since
the hooks file is plugin-global): the per-lens counts above. Deduplicated
by root cause: four faults recurred under three or four lenses each (the
composed parking bullet; park and unpark commits against the pinned head;
the class helper's flip against `human` and Task 7; the Awaiting-input read
surface).

**Dispositions.** Two root causes were forks decided by the operator:
the knobless policies gained knobs (`worker_base_merge`,
`unpushed_rewrite`, both `allow` by default) rather than an always-on
shape, grounded in REQ-A1.2's own "policy with a core default"; and both
renames were taken (`agent` → `unit-owner`, `worker_merge_conflicts` →
`worker_merge_conflict_policy`). Every other root cause was applied as
proposed, as a Draft in-place edit: the segment-scoped parking exemption,
the reconcile-push-then-pin ordering with park commits excluded from the
reviewed-head comparison, the park as one idempotent commit, records as
claims of intent with a follow-up comment and park on a failed act, the
class evaluator reading the fetched base ref and re-pinning head, base OID,
and the Awaiting-input predicate before the merge call, "PR merge" against
"base merge" throughout REQ-D and REQ-E, the `act` fixture column with a
verdict per copy including outside-jurisdiction, the
`Planwright-Sign-Off-Rejected` trailer for partial and `resolve`
rejections, `refs/heads/` stripped and `*` bounded at `/`, per-knob strict
degrade targets with the repo-tracked arm hard-failing, the sync's exit
arms with no park over a wedged tree, the loud failure on an unreadable
range, jurisdiction before any knob read and the attended-session defer,
the CI result handed forward, `check:test-time` in every test-heavy
Done-when, the flip helper called after the draft PR exists, a core
hard-disqualifier path zone no layer shrinks, the purge seed scoped to
short phrases plus a grep screen for sentence-length phrasings with
historical surfaces excluded, the doctrine docs and README rows Task 1
missed named by decided rule, the `BREAKING CHANGE:` footer as the release
note's carrier, "the tower profile, which the orchestrator tier runs
under", REQ-D1.8 split out of REQ-D1.4 and REQ-D1.7 moved after REQ-D1.6,
the merge helper named `scripts/merge-admitted.sh`, D-6 and D-9 retitled,
the upstream refreshed before the containment read, REQ-G1.6 for the echo
discipline, and the citation and test-spec pairings the tests and
cross-file lenses listed. No finding was declined and none deferred. The
validator reports 0 errors, 0 warnings after the edits.

### Pre-flip verification

- **Post-lens stale-reference sweep.** Run after the minting and renames:
  no `agent` value, `worker_merge_conflicts`, `repo` strategy value,
  "non-Ready", "three times", "nine surfaces", "per-item revert", or
  "full ref name" remains in the four files outside the changelog entry and
  D-4's naming note, which name the old forms on purpose; the brief's
  sections 2, 3, 4, and 7 were reconciled to the renames and the
  carried-forward wording; the changelog entry's own knob count was
  replaced by a pointer at Task 4.
- **Lint.** `markdownlint-cli2` over the brief and the four spec files: 0
  errors.
- **Recorded claims re-derived.** The header's rule-doc list has nine
  entries and all nine resolved. Requirement bullets and test-spec entries
  match one to one (a fixed-string count of each, equal, after REQ-D1.8 and
  REQ-G1.6 were minted with their entries). Every decision heading is in
  the section 4 ledger (a fixed-string count of each, equal). The critical
  path was recomputed from the `Dependencies:` and `Estimated effort:` lines
  after Task 10 gained its edge to Task 2: unchanged, 1 → 4 → 6 → 7 → 9 →
  12, as the graph script also reports. The validator reports 0 errors and
  0 warnings, both against the merge base and with `--baseline HEAD`.
- **Enumeration cross-check.** Every enumerated count in anchored prose was
  either converted to a decided rule (D-1, D-10, the Sources gloss, the
  changelog entry, Task 1's Done-when, Task 12's doc list) or is a value
  the bundle owns ("one release"; the knob value sets).

### Sign-off record

Signed off 2026-09-22 by the operator after the approval summary; the four
spec files flipped Draft → Ready with `Last reviewed:` bumped; the
validator re-run at Ready reports 0 errors, 0 warnings (against the merge
base and with `--baseline HEAD`); the status render derives Ready with
Tasks 1 and 5 dispatchable.

Class: meaning
Lens-pass: the full-bundle lens review recorded in this section (ten-lens
fan-out over the spec artifact class, dispositions above), preceded by the
mid-walk delta lens pass recorded in section 3
Anchor: `08f36b3e4de91849b0a97449244dca5d5f3e65fd` — computed as
`scripts/spec-anchor.sh specs/human-gates`

## 9. Amendment log

(none yet)
