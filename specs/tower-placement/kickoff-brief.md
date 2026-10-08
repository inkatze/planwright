# Tower placement — Kickoff brief

## 1. Header

- **Spec:** `specs/tower-placement`
- **Spec commit at walkthrough start:** `d767b0b177cb37151ef94170f170f80d805ad54e`
- **Walkthrough date:** 2026-10-07
- **Mode:** first activation (Status Draft, no prior brief)
- **Validator at pre-flight:** `scripts/spec-validate.sh specs/tower-placement`,
  0 errors, 0 warnings
- **Decision/transcript log:** no harness-provided log in this session; the
  turn mirror is skipped, not improvised into the repository.

## 2. Goal & glossary

**Restatement.** Towers today run either in the primary checkout, where one
slip moves or dirties the `main` every session reads, or under Claude Code's
`--worktree` isolation, which refuses the cross-worktree commands a tower
exists to run; and the tower deny floor exists only when the session was
launched with the tower settings profile. This bundle makes a tower's own
working tree (a plain linked worktree or a separate clone, never
`--worktree`) the supported home; checks placement at bring-up against the
`tower_placement` knob (`warn` / `refuse` / `allow`); enforces the floor from
the plugin's own hooks in any session marked as a tower, deny-only, so a mark
can never grant a permission; widens the floor to every branch-moving and
stash-writing command; and fixes the two dispatch defects that appear once a
tower leaves the primary checkout. The rule itself lands as a fleet doctrine
floor.

**Rules out.** Worker launch and isolation changes, the operator's own tower
launcher, Edit/Write denies for towers, shell-feed and wrapper spellings
(deferred), per-checkout vs per-repository orchestrator state (deferred), and
any change to sign-off, merge, or the draft-to-ready flip.

**Assumes.** Workers branch from `origin/main`, so a tower never needs to move
local `main`; Claude Code exposes no worktree-isolation signal (hence D-6's
probe); plugin hooks share the settings hook shape, `timeout` included.

**Implicit terms resolved.**

- **Main tree vs linked worktree.** The only distinction git can make. A
  separate clone classifies as a main tree, so a clone-based tower declares
  itself with a machine-local `tower_placement: allow`, or it warns at every
  bring-up under the default.
- **Marked session.** A session id recorded in the fleet state store as a
  tower. A mark only restricts the session carrying it, so marking needs no
  trust.
- **"A checkout it does not own."** REQ-A1.2 states the rule for checkouts the
  tower does not own; REQ-D1.1's mechanism denies the acts in every checkout,
  the tower's own included, because the guard cannot prove which checkout a
  command reaches. The mechanism is deliberately stricter than the rule; not an
  inconsistency.

Signed off: 2026-10-07

## 3. Requirements walkthrough

**REQ-A (placement).** Intent: an own working tree is the supported home, the
never-touch-what-you-don't-own rule is a doctrine floor, and one knob governs
the response. No open questions.

**REQ-B (bring-up).** Gap found: `refuse` and the posture fallback were
defined only in `/tower` terms (routes, relay, read-only), while
`/orchestrate` has no routes, no relay, and no posture check. Decision: for
`/orchestrate`, whose only repo-mutating act is dispatch, `refuse` holds
dispatch on the same terms (moved or acknowledged) while bookkeeping and
status reads continue, and missing or broken plugin enforcement also holds
dispatch; `/orchestrate` gains a posture check in Task 6, landed
word-neutral. Grounds: D-2 brought `/orchestrate` into scope for the seed's
meta-tower incident, and D-8's fail-closed contract. Mid-walk lens (inline,
narrow delta): D-4 described the hold as the posture check's existing one,
which `/orchestrate` lacks; aligned in the same edit. No other dependents.

**REQ-C (plugin-wired enforcement).** Clarified: the marking command includes
the plugin-namespaced forms (`/planwright:tower`, `/planwright:orchestrate`),
as the flight's prior art matched. Gap found: a different, unmarked session
can delete a tower's mark and drop that tower's plugin floor until its next
bring-up; REQ-C1.4's store refusal holds only inside marked sessions.
Decision: accepted as a risk (risk register), keeping REQ-C1.6's "unmarked
sessions untouched" exact.

**REQ-D (the deny floor).** Inconsistency resolved by edit: D-10's decided rule
("any command that changes which commit a branch names") covered the commit
family, which REQ-D1.1's list omitted. Decision: the literal rule; commit,
cherry-pick, revert, and am join the tower-tier denies in every parseable
spelling. Grounds: obs:8bc1198c (a tower commit on `main` stranded) and
D-10's own reasoning that the guard cannot tell which checkout a command
reaches; tower commits happen inside planwright scripts, which the guard sees
as script calls. Mid-walk lens: consistent with REQ-D1.4 (tightening only);
one consequence recorded as a risk (a marked session cannot hand-commit for
the rest of the session). *Reopened at the sign-off lens review (§8): the
premise was false (`/orchestrate` hand-commits its observation fragments and
its in-session backend runs `/execute-task` in the tower's session); the
operator reverted the decision and the commit family stays allowed.*

**REQ-E (dispatch), REQ-F (docs), REQ-G (invariants).** No open questions.

**Consolidated spec-edit list (Draft, applied in place).**

1. REQ-B1.2: `/orchestrate` holds dispatch under `refuse`; cites D-2.
2. REQ-B1.4: posture check in both skills, per-skill fallback; cites D-2.
3. D-4: the `/orchestrate` dispatch hold.
4. Task 6 deliverables: the per-skill fallback and the new `/orchestrate`
   posture check.
5. test-spec REQ-B1.2 and REQ-B1.4: `/orchestrate` manual runs.
6. REQ-C1.3 and its test-spec entry: plugin-namespaced commands mark.
7. REQ-D1.1: the commit family; cites obs:8bc1198c.
8. D-10: the commit family and why.
9. Task 4 Done when and test-spec REQ-D1.1: the commit family.

Signed off: 2026-10-07

## 4. Design walkthrough

Every D-ID in `design.md` accounted for; none contradicts a walked
requirement.

- **Amended this walk:** D-4 (`/orchestrate` holds dispatch under `refuse`),
  D-10 (the commit family is branch-moving). See section 3's edit list.
- **Confirmed, rationale intact:** D-1, D-2, D-3, D-5, D-6, D-7, D-8, D-9,
  D-11, D-12.
- *Updated at the sign-off lens review (§8):* D-1 (sanctioned-script
  exceptions; capability vs mechanisms), D-3 (citations), D-4 (the
  `/orchestrate` hold covers every outward act; `warn` is additive), D-7 and
  D-9 (Research tags), D-8 (hook-only handshake, unknown sessions defer,
  timeouts, store safety bar, pruning, seam note), D-10 (closed act list,
  commit family outside it), D-11 (nesting already fixed). The final ledger
  is `design.md` as anchored in §8.
- **Superseded:** none.

Note recorded: a tower launched with the profile runs the policy guard from
both the profile hook and the plugin hook. Both paths only deny, so the
double run costs latency, never correctness.

Signed off: 2026-10-07

## 5. Verification approach

**Coverage mix.** Per `test-spec.md`'s preamble: `[test]` for the classifier,
the knob, the guard, the hooks, and dispatch; `[manual]` for live-session
bring-up behavior; `[design-level]` for doctrine and docs. Every REQ has an
entry.

**Ownership.** `[test]` entries are shell test files run by `mise run check`
locally and by the repository CI. `[manual]` entries are swept by the
operator from the checklist Task 6's PR carries. `[design-level]` entries are
verified at each task's PR review.

**Dead paths.** One found and fixed: Task 6's checklist covered only the
`[manual]` REQ-B entries, leaving REQ-A1.1's and REQ-C1.8's manual halves
unowned. Task 6's Done when now covers every `[manual]` entry (Task 6 depends
on Task 3's marking, so every manual run is possible at its PR). Each
remaining `[test]` entry names an act a shell test can perform; REQ-C1.6's
no-fork trace is achievable with logging stubs on `PATH`.

Signed off: 2026-10-07

## 6. Task graph

Reconstructed from the `Dependencies:` lines in `tasks.md` (authoritative);
effort weights from each task's `Estimated effort:` line.

- **Roots, startable in parallel:** Tasks 1, 2, 3, 5.
- **Edges:** 4 ← 3; 6 ← 2, 3; 7 ← 1, 2, 4, 6.
- **Critical path:** 3 → 4 → 7 by effort weight, with 3 → 6 → 7 close
  behind. Task 3 is the bottleneck and takes the security-zone hard pause,
  as does Task 4, so both pauses sit on the critical path.

**Deliberate non-edges (do not "fix"):**

- 7 does not depend on 5: the docs do not describe the dispatch fixes.
- 4 and 6 are independent: bring-up needs only Task 3's marking, not the
  wider deny list.
- 5 touches no guard, hook, or profile code and stays off the security path.

Signed off: 2026-10-08

## 7. Risk register

**Decision-domains gap check** (catalog via `scripts/resolve-catalog.sh
decision-domains`): auth, configuration, concurrency, and the integration
surface are decided in the bundle (D-4, D-7 to D-10, cross-cutting concerns).
Two touched domains were undecided and are now decided: data storage (mark
lifetime, REQ-C1.9) and deploy/migration (the upgrade window, REQ-F1.5).
Rows 11 to 18 were added at the sign-off lens review (§8).
Both edits pair their test-spec entries.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | An unmarked session (a worker, a cleanup) deletes a tower's mark, dropping that tower's plugin floor until its next bring-up. REQ-C1.4's store refusal holds only in marked sessions. | Accepted: other sessions are not treated as adversaries; the posture check on request re-marks and reports. Profile-launched towers keep the profile floor. |
| 2 | Pruning (REQ-C1.9) removes the mark of a tower that ran past the pruning age with no bring-up or posture check. | Bring-up and the on-request posture check refresh the mark; the same widening class as row 1, bounded to stale marks. |
| 3 | *(Superseded at §8: the commit family is no longer denied.)* A deliberate `git -C <primary checkout> commit` from a tower still lands on the primary `main`. | Forbidden by the placement floor (doctrine only); the placement check keeps towers out of the primary checkout, so a plain commit lands on the tower's own branch. |
| 4 | `/orchestrate`'s new posture check (Task 6) does not fit the saturated instruction budget. | Land word-neutral, detail in scripts and docs; signal: `check:instructions` failing on Task 6. |
| 5 | D-6's isolation probe misreads (a refusal for another reason, or isolation that does not refuse the probe). | Warn only, never blocks; signal: an isolation warning in a plainly launched tower. |
| 6 | The plugin hook adds cost to every Bash call in every session. | REQ-C1.6's in-shell prefilter before any fork; signal: the per-file test-time ceiling and the no-fork trace test. |
| 7 | Shell-feed and wrapper spellings (`bash <<<`, `mise exec --`, scripts by path) still bypass both guard tiers. | Deferred in `tasks.md`, gated on Task 4. |
| 8 | A tower running when the release installs has no mark, so no plugin floor, until its next bring-up. | REQ-F1.5's restart note in the docs; profile-launched towers keep the profile floor. |
| 9 | Several towers in linked worktrees of one clone share a single `main` ref. | REQ-F1.2: the docs steer multiple towers to separate clones. |
| 10 | The tower-enforcement flight branch is merged instead of serving as prior art. | D-12; signal: a PR opened from that branch. Tasks 3 and 4 build on `main`. |
| 11 | A subagent launched from a tower session shares its session id and so inherits the deny floor. | By design: the floor covers the whole session tree. Authoring petitions from a tower take a separate-session rung. |
| 12 | A prune can race a refresh and drop a live mark. | The next handshake restores it; signal: the posture check reporting an unmarked session. |
| 13 | Ancestor-path or variable spellings dodge the "names the store" refusal. | The floor guards against slips, not a hostile model; shell-feed forms are already deferred (row 7). |
| 14 | A tower edits its own settings to disable hooks or the plugin; the change takes effect next session. | The next bring-up's handshake fails and the posture check falls back (REQ-B1.4). |
| 15 | A plugin update mid-session leaves the hook path dangling, so calls proceed until restart. | REQ-F1.5's restart note; signal: the handshake failing on the next posture check. |
| 16 | "Dirties" in the placement floor has no mechanism (`restore`, `clean`, Edit, Write, and shell writes stay open). | Decided at §8: doctrine-only. |
| 17 | `refuse` and the posture fallback are honored by the skill, not enforced mechanically. | The deny floor is the mechanical layer; the knob is a capability (D-1). |
| 18 | The plugin floor has no off switch, so a misfire waits for a fix release or a plugin downgrade. | Decided at §8; the act can be done from a plain session meanwhile (REQ-F1.5's docs). |

Signed off: 2026-10-08

## 8. Sign-off

### Lens review (first activation, full bundle)

Fan-out: one read-only sub-agent per spec-class lens (lenses paired where
closely related), plus one for the kickoff-specific altitude and ship-gate
checks, each with a self-critique pass; the coordinator merged and deduped
across agents. The original flight review record was recovered from its
worker session to make the bundle's "flight review" citations checkable.

| Lens (spec class) | Findings | Notes |
| --- | --- | --- |
| Contract correctness and internal consistency | 15 | Commit-family premise false (`/orchestrate` hand-commits; in-session backend); missing store denying every session; timeout below the guard's deadline; REQ-E1.1 already fixed on `main`; branch deletion undefined; others low. |
| Ambiguity and interpretation forks | 20 | Mark writer location; failure-state verdicts; posture "active" test; act-list edges (create, delete, `-B`, stash forms); MCP tool set; timeouts; `/orchestrate` bring-up and acknowledgement; classifier `none`; probe; thresholds. |
| Citation and coverage integrity | 14 | REQ-A1.1 cited by no task; REQ-C1.9 refresh unverified; flight-review F/D ids not durable; kickoff citations unnamed; Sources entries uncited; Research tags. |
| Dead verification paths | 10 | No-fork trace not observable; timeout without a number; `_about` test owned by no task; routing evals blind to Task 6; doctrine-index check blind to Task 1; REQ-G1.2/G1.3 unownable as written; frozen baseline; manual-run procedure. |
| Decision-domain gaps | 19 | Mark writer and fleet home; fail-closed scope; harness-level fail-open; hook-live proof; store safety bar; standing tower practices vs the placement floor; act completeness; remote refs and an unlisted MCP tool; "dirties"; kill switch; subagents; seam reuse; version skew; release marker. |
| Testability | 13 | Task 2 cannot pass `check:options` (row in Task 7); undefined verdicts; MCP scope; timeout scope; Done-when gaps; classifier outputs; signal set; time budget; spelling set; open-ended doc negative. |
| Cross-file consistency | 25 | Overlaps above, plus `/orchestrate` outward acts beyond dispatch; `_about` statements falsified; changelog and `Last reviewed:`; brief ledger; per-tower-checkouts table and worker base; word-budget wording. |
| Documentation and glossary drift | 10 | "Tower" vs the meta-spec's orchestrator; "mark" vs the tower marker; "primary checkout" senses; "floor" senses; "heartbeat-class"; `/orchestrate` bring-up; fleet-home naming; "command tag"; "mechanism". |
| Rendered-content safety | n/a | No bundle prose is copied into an executing or markup context; Task 6's PR checklist copies plain titles only. |

**Altitude check (REQ-H1.3):** triggered (the pinned altitude seed claim);
D-1 exists and is cited from the Goal; the decomposition carries a doctrine
task (1), capability (2, 6), and mechanism (3, 4, 5) tasks. One low
traceability finding (mechanism tasks not citing D-1), applied.

**Ship-gate check (REQ-L1.4):** one finding (the operator's launcher and
overlay named only in prose), applied as a gated Deferred bullet; the two
existing Deferred gates parse as pending under `scripts/drain-gates.sh`.

**Validation (`validation-rigor`).** Load-bearing findings were reproduced
against the repository (the `/orchestrate` hand-commit and in-session
backend, the nesting fix from #548, the hook entries lacking timeouts, the
guard's whole-call deadline, `check:options` behaviour), cross-checked by
independent lens convergence (most high findings were raised by two or
three agents), and checked outside-in against git history and the recovered
flight review. Adversarial pass: the claimed conflict with the tower's
ready-flip practice was refuted (the flip runs through `ready-flip.sh` and
moves no branch); the rest of the keep set survived. Resurrected from the
decline set: none.

### Dispositions

**Decided by the operator (applied):**

1. Commit-family deny reverted; commit, cherry-pick, revert, am stay allowed
   (REQ-D1.1, D-10, Task 4, test-spec; risk row 3).
2. Marks written only by hook processes through the activation handshake,
   which is also the posture check's proof the floor is live (D-8, REQ-B1.4,
   REQ-C1.9, Tasks 3, 6, test-spec).
3. Unknown sessions (no store, unreadable id) defer; marked or unsearchable
   deny; added hook timeouts exceed the guard's deadline plus margin
   (REQ-C1.4, REQ-C1.5, D-8, Task 3, test-spec).
4. The placement floor names sanctioned-script exceptions (the release
   fast-forward, the forward-merge start) (REQ-A1.2, D-1, Task 1).
5. `/orchestrate` under `refuse` holds every outward act; bring-up once per
   invocation; unattended parks (REQ-B1.2, D-4, Task 6, test-spec).
6. REQ-D1.1 a closed act list: force-reset forms, rename and copy,
   `checkout`/`reset` in every form, `gh pr checkout`, `gh repo sync`, stash
   beyond `list`/`show`; plain create and delete allowed; "dirties"
   doctrine-only (D-10, test-spec; risk row 16).
7. The mark store adopts the sibling tower stores' safety bar (D-8, Task 3,
   test-spec).
8. The flight review summarized per finding in `requirements.md` Sources.
9. REQ-E1.1 kept as a regression test (D-11, Task 5).
10. The operator's launcher and overlay tracked as a gated Deferred bullet.
11. No off switch; recovery documented (REQ-F1.5; risk row 18).
12. `mcp__github__update_pull_request_branch` added to the floor (REQ-C1.1,
    Task 3, test-spec).
13. Six residuals accepted (risk rows 11 to 16, 17 already covered).
14. Tasks 3 and 4 carry the breaking-change marker and changelog note.

**Mechanical batch (operator-approved, applied):** Task 2 ships the
options-reference row; task Done-when lines aligned with every decision
above; testable wording for classifier outputs, the no-fork check, timeouts,
signals, Task 6's suites, REQ-G1.2 and REQ-G1.3; missing task citations
(REQ-A1.1, REQ-G1.2, REQ-G1.3, D-1); Sources entries for the drafting and
kickoff decisions; Research tags; changelog entry; `Last reviewed:`; a
bundle-scoped glossary (tower, deny floor vs placement floor); the store's
seam note; the per-tower-checkouts reconciliation scope.

**Declined (with rationale):**

- Survey git for every effect-matching command (`bisect`, `replay`,
  `submodule update`): the operator chose a closed list; anything unlisted
  is outside the floor.
- Pin the oversized-payload threshold in the spec: the guard's existing cap
  owns the value; the spec cites the behavior, not the figure.
- A third fail-open close for harness-level failures beyond the timeout
  relation (a dangling hook path): accepted as risk row 15.

**Deferred:** none beyond the bundle's gated Deferred bullets.

### Sign-off record

Signed off 2026-10-08 by the operator after the approval summary: Status
Draft→Ready on all four spec files, `Last reviewed:` 2026-10-08; validator
0 errors, 0 warnings after the flip; markdownlint clean over the bundle.

Class: meaning
Lens-pass: §8 "Lens review (first activation, full bundle)" and its dispositions, this section
Anchor: `3ab656277a8b4e4d297033d748b2482c0557681b` — computed as
`scripts/spec-anchor.sh specs/tower-placement`

## 9. Amendment log

(none yet)
