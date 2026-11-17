# Control plane — Test Spec

**Status:** Ready
**Last reviewed:** 2026-11-16
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: slice one is verified almost entirely by `[test]`: language-neutral
fixture data (allow, near-miss and floor requests with recorded verdicts) run
by the repository's CI suite, with the near-miss check shown to fail once. The
doctrine-level requirements (the layer line, rule homes, language neutrality)
are `[design-level]`, and the per-slice measured claim and the operator's
gates are `[manual]`. Entries for slices two to four are outlines, tightened
at each slice's design walk.

## REQ-A — The three layers and the line between them

### REQ-A1.1 — routine moves are code [design-level]

The artifact's existence and coverage: each slice's tasks show the routine move as a verb with no model call; a grep-style check that the engine, gate and dispatcher import no model client.

### REQ-A1.2 — gates stay the operator's [test]

Fixtures drive every floor act (merge, ready-mark of a spec pull request, sign-off, message to a person) through the engine and assert deny; a check asserts no verb in this spec's scripts invokes a merge or sign-off helper outside the configured merge mode. Run by the CI suite.

### REQ-A1.3 — asymmetric failure [test]

Fixtures: an unreadable policy, an unknown format and a malformed request each defer in the engine; the same unreadable state delivers in the dedupe gate. Run by the CI suite.

### REQ-A1.4 — one home per rule, retire against proof [test + design-level]

The rule-enforcement doctor (Task 20) lists prose-only rules on a fixture store; a retirement without a green proving check fails. The mapping itself is design-level (D-2).

### REQ-A1.5 — one slice at a time [manual]

At each slice's walk the operator confirms the previous slice's measured change is recorded; Tasks 6, 11 and 16 carry the dependency edges that make the order mechanical.

### REQ-A1.6 — leaf skills keep their behavior [test]

The existing skill suites run unchanged in CI after each slice lands; a change to a leaf skill's step list in a slice's diff is a review finding.

## REQ-B — Policy as data

### REQ-B1.1 — no policy literal in code [test]

A check scans the control-plane scripts for numeric limits and list literals outside the catalogs and fails on a plant; every tunable appears in the options reference (the existing options check). CI.

### REQ-B1.2 — layering and explain [test]

Fixtures with a value in each layer assert the resolved value and that `explain` names the supplying layer.

### REQ-B1.3 — schema check, drop invalid entry [test]

Fixtures: an invalid entry is dropped and the lower layer stays; an invalid class-bounding value makes the class refuse everything; the schema check runs in CI and at load.

### REQ-B1.4 — tighten-only floor [test]

Fixture: an overlay entry allowing a floor act fails the schema check naming it; an overlay narrowing the floor is accepted.

### REQ-B1.5 — limits and order as data [test]

Dispatcher fixtures (Task 8) read the landing order, limit, ceiling and ranks from policy and change behavior when the data changes; no literal in the dispatcher.

### REQ-B1.6 — policy digest on every verdict [test]

Fixture verdict records carry the digest; changing a policy value changes it.

### REQ-B1.7 — merge mode defaults to the operator [test]

Fixtures: the default configuration never merges; a configured reach merges only an eligible pull request; a spec pull request, a sign-off item, a bypass need, a shared repository and a machine-local reach are each refused or ignored.

## REQ-C — The approval policy engine

### REQ-C1.1 — pure verdict function [test]

Fixture requests return the recorded verdict; a check asserts the engine opens no network socket and writes nothing but the log.

### REQ-C1.2 — structured request, argument-vector match [test]

Near-miss fixtures with substitution, expansion, redirection and unreadable quoting all defer; a request built from pane text is rejected.

### REQ-C1.3 — shipped classes [test]

Allow and near-miss fixtures for each class; `release-run` ships in shadow and `host-act` ships empty (asserted from the shipped catalog).

### REQ-C1.4 — owner check and self-describing answer [test]

Fixtures: an answer for another program's worker is refused with nothing written; a stale request id changes nothing; the answer line names worker, program and first command line.

### REQ-C1.5 — the floor, denied with a message [test]

Each floor entry has a fixture that returns deny with a message naming the entry and increments its count; a bare deny is asserted never emitted.

### REQ-C1.6 — modes, shipped shadow [test]

Fixtures: shadow answers nothing and logs the pair; enforce answers; off defers; every shipped class is `shadow`; a machine-local `enforce` is ignored and reported; a fixture log with N matches and M mismatches yields the one-line per-class summary (counts, sample size, mismatches on request), an empty log says so, and no class mode moves from shadow without the summary having been produced. The hub's bringing the summary to the operator is [manual], inventoried at each class's move to enforce.

### REQ-C1.7 — near-miss fixture for every class [test]

The check fails when a class lacks a near-miss; its self-test widens a rule and confirms the check fails once.

### REQ-C1.8 — decision log and denial counts [test]

Fixture run asserts one redacted record per verdict with the listed fields, a bounded command and the counts by entry and class; the token-shape scan fails on a plant.

### REQ-C1.9 — consulted at the source [test]

The stall-watcher fixture: an allowed prompt raises no event; a deferred one raises the event unchanged.

### REQ-C1.10 — no drift from the worker guard [test]

The drift check fails on a command one classification admits and the other refuses without a recorded reason.

### REQ-C1.11 — test, lint and evidence-and-wait classes [test]

Fixtures: a single test run and a lint check inside the worktree allow in shadow and record the would-have answer; a command naming a path outside the worktree, a full-suite chain, a lint run that rewrites files and a CI wait with no bound each defer. Run by the CI suite; each class has near-miss fixtures (REQ-C1.7).

## REQ-D — Event dedupe at the source

### REQ-D1.1 — one gate at the append point [test]

A check asserts every event writer calls the gate; fixtures assert the key fields.

### REQ-D1.2 — repeat, stale and off-order drops [test]

One fixture per reason asserts the drop and its count.

### REQ-D1.3 — never drop the first, deliver on doubt [test]

Fixtures: the first decision, blocker, failure and landed events are delivered; an event with unreadable state is delivered.

### REQ-D1.4 — drop ledger and over-keen event [test]

The ledger holds keys and no payload; a fixture past the configured share raises the gate's own event.

### REQ-D1.5 — coalescing and no timer wake [test]

Fixture: routine events inside one window yield one wake; an idle session with nothing pending is not woken.

## REQ-E — Measure the claim

### REQ-E1.1 — baseline before slice one [test]

The recording script reproduces a fixture's numbers and writes only machine-local data; a check fails on a committed figure.

### REQ-E1.2 — each slice moves a number [manual]

At each slice's walk the operator reads the recorded change against the baseline; a slice with no move is rethought.

### REQ-E1.3 — machine-agnostic [test + manual]

A check asserts no core catalog or fixture holds a machine path or tracker name; the work-machine adoption is confirmed by the operator.

## REQ-F — The queue (outlined)

### REQ-F1.1 — one store, written by verbs [test]

Outlined: a hand edit is detected and an unknown format refused; tightened at the slice-two walk.

### REQ-F1.2 — rebuildable, all unit kinds, cross-spec read [test]

Outlined: delete-and-rebuild equals the original on fixtures; a hard cross-spec edge is read, and an unreadable foreign bundle fails closed (D-17).

### REQ-F1.3 — admission by code [test]

Outlined: a launch breaking each limit is refused naming the rule; the lower-ranked hold lapses per policy (D-18).

### REQ-F1.4 — one launch seam [test]

Outlined: each rung's launch carries the pins; the fleet home resolves from a tower shell; a worker on another branch is flagged.

### REQ-F1.5 — named states and hooks [test]

Outlined: a configured hook runs on its transition only.

### REQ-F1.6 — done-when check [test]

Outlined: a unit is not done until its confirmed check passes.

### REQ-F1.7 — a program's per-repository roots [test]

Outlined: a program with the root set reads byte-identically to before; with it unset each repository's own resolved root is read; the set value wins when both apply.

### REQ-F1.8 — ambiguity refusal and root validation [test]

Outlined: a spec name under two roots is refused naming both; a refused or missing root is flagged naming the repository and the resolver's reason.

### REQ-F1.9 — one reader verb, no new registry [test]

Outlined: the check goes red on a seeded direct read of the root field; the resolver and registry sources are unchanged and no root registry file is written.

## REQ-G — The reconciler (outlined)

### REQ-G1.1 — the reconciler loop [test]

Outlined: each verb is idempotent over a repeated or interrupted pass; a sync sweeping in unrelated files is refused.

### REQ-G1.2 — evidence from machines [test]

Outlined: a record with an invented start or a moved head is refused.

### REQ-G1.3 — procedure verbs [test]

Outlined: each verb returns the same result when run twice.

### REQ-G1.4 — event-only poller [test]

Outlined: no event on an unchanged state, one on a change.

### REQ-G1.5 — landing under the merge mode [test]

Outlined: with the operator merging, no merge; the release label advances after a publish; a dropped release raises an event.

### REQ-G1.6 — bounded steps, cost handover, adoption [test]

Outlined: a hung step is stopped; a handover is triggered by a reading; a live session is adopted.

### REQ-G1.7 — refused-push rename within limits [test]

Outlined: a refusal naming an absent branch renames and retries once through the helper; a refusal naming an existing, protected or shared branch, a second refusal, and any force spelling do not rename and stop with the exact text.

## REQ-H — Briefs from state and a thin hub (outlined)

### REQ-H1.1 — launch from a row with a generated brief [test]

Outlined: a brief survives the loss of a scratch directory and the report updates the row.

### REQ-H1.2 — one packet per decision [test]

Outlined: a fixture decision renders one complete packet and its answer is recorded.

### REQ-H1.3 — optional supervisor [test + manual]

Outlined: a program with no supervisor runs a fixture unit to landing; the operator confirms the topology at the walk.

### REQ-H1.4 — per-wake tier and size-resolved effort [test]

Outlined: a wake class resolves its tier from policy; a size hint resolves the effort.

### REQ-H1.5 — rules say how enforced [test]

Outlined: the doctor lists prose-only rules; the platform class validates.

### REQ-H1.6 — titles, work in motion and current step [test]

Outlined: no row carries an identifier, hash, branch or path; a waiting item says why; an overflow keeps operator-needed items first; a step older than its state is not shown and raw command text never reaches the step.

### REQ-H1.7 — instruments, usage, spend and progress [test]

Outlined: an unreadable reading draws unknown; spend shows with no budget and adds share and rate with one; a redraw does not wait on a snapshot refresh; a stale snapshot shows its age.

### REQ-H1.8 — accessibility and the type check [test]

Outlined: every state has a symbol and word; no colour under `NO_COLOR`; plain mode shows words only; the type check fails on a seeded error.

### REQ-H1.9 — screenshot before leaving draft [manual]

The operator sees a screenshot of the real panel over fixture data and says yes; the pull request quotes it. Swept by the operator at each panel pull request.

## REQ-I — Safety and rollout

### REQ-I1.1 — test-first and guard-catalog registration [design-level]

Each policy task's Done-when names its fixtures written first; the guard catalog lists the engine and reconciler (the guard-catalog check).

### REQ-I1.2 — kill switch [test]

With the setting on, the engine answers nothing, the gate delivers everything and the dispatcher admits as today (fixtures).

### REQ-I1.3 — language-neutral contract [design-level]

The fixtures are data files with no implementation-language code; the contract is the verb, stdin record, stdout verdict and exit codes.

### REQ-I1.4 — no secrets in logs and queue [test]

The token-shape scan fails on a planted value in the log, ledger or queue fixture.
