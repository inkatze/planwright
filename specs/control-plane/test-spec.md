# Control plane — Test Spec

**Status:** Ready
**Last reviewed:** 2026-11-19
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

Fixtures: an invalid entry is dropped and the lower layer stays; an invalid class-bounding value makes the class refuse everything; the schema check runs in CI and at load; each dropped entry is counted and reported at the wake naming its file and entry, and again at the next wake while it stays dropped, and `explain` shows it.

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

### REQ-D1.3 — never drop the first, deliver on doubt [test] (superseded by REQ-D1.6)

Fixtures: the first decision, blocker, failure and landed events are delivered; an event with unreadable state is delivered. Not run on its own: the REQ-D1.6 entry carries these fixtures.

### REQ-D1.4 — drop ledger and over-keen event [test]

The ledger holds keys and no payload; a fixture past the configured share raises the gate's own event.

### REQ-D1.5 — coalescing and no timer wake [test]

Fixture: routine events inside one window yield one wake; an idle session with nothing pending is not woken.

### REQ-D1.6 — never drop an open request, only coalesce it [test]

Fixtures: the first decision, blocker, failure and landed events are delivered, a stale first occurrence included; for an operator message, a cross-session message and a request-bearing event kind, a repeated, a stale and an off-order event are each delivered while the request is open, and each is dropped and counted as a drop once the ledger has closed every request it carries (a fixture ledger seeded with close records); a burst of request-bearing events in one window yields one coalesced event carrying every request id the ledger holds for them, and the drop ledger counts them as coalesced with no drop; an event with unreadable state is delivered. Run by the CI suite (Task 5).

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

With the setting on, the engine answers nothing, the gate delivers everything and the dispatcher admits as today (fixtures); a machine-local value of the setting is ignored and reported, and the floor refusals and limits stay in force.

### REQ-I1.3 — language-neutral contract [design-level]

The fixtures are data files with no implementation-language code; the contract is the verb, stdin record, stdout verdict and exit codes.

### REQ-I1.4 — no secrets in logs and queue [test]

The token-shape scan fails on a planted value in the log, ledger or queue fixture.

### REQ-I1.5 — locked one-line appends [test]

Fixtures: concurrent writers, run as separate processes, append to the log and the ledger and every record survives whole; a pre-seeded file ending without a newline (a simulated crash mid-write) is read without error, skipping the torn line, and the next write starts on a fresh line and leaves earlier records intact; a lock that cannot be taken within its bound leaves the verdict and the event delivery unchanged and the lost record counted and reported.

## REQ-J — The request ledger

Slice one's ledger is verified by `[test]` fixtures run in the repository's CI suite, against a fixture program home; which seam sees which arrival is a recorded probe, and the panel line is the operator's preview gate.

### REQ-J1.1 — capture on arrival, by code [test]

Fixtures: an operator prompt, a cross-session message and a request-bearing event (a pending prompt) each append one arrival with its own id before the receiving model turn acts on it (observed as before the turn's first tool call or reply); composer-written and hook-injected text appends nothing; a session holding no program name appends nothing; a check asserts no skill instruction asks the model to write an arrival, and goes red on a seeded one. Run by the CI suite (Task 5.1).

### REQ-J1.2 — both sides captured, linked, probed [test + manual]

Fixtures: one message seen by the receiving hook and by the send script yields two sightings linked under one open request; a pair the linker cannot match stays two open requests; two identical sends in one burst keep two ids. The probe of which hook sees which arrival on each launch rung is `[manual]`, run by Task 5.1's worker and committed as the research note before the fixtures, which derive from it; a fixture with a kind no seam sees makes the doctor name it. Run by the CI suite (Task 5.1).

### REQ-J1.3 — capture never blocks; failures spool and raise [test]

Fixtures: an unwritable ledger leaves the prompt unchanged and unblocked, writes a spool line carrying its id that counts as open, is retried at the next capture and at the next wake, and raises a failure-class event; a held lock delays the prompt no longer than the hook's bound. Run by the CI suite (Task 5.1).

### REQ-J1.4 — the arrival record and its excerpt [test]

Fixtures: an arrival holds each listed field; an excerpt past its bound is cut on a character boundary; a planted token-shaped value, email address and phone number are each redacted at write, a token straddling the cut included, and so are a close record's quoted words and reason; with the screen or the pattern pass failing or missing, the arrival is written with no excerpt, counted open, and a failure-class event raised; and the log's check fails on each planted past the screen; a separate-process concurrent-writer fixture and a torn-last-line fixture keep every record whole; nothing is written inside a repository. Run by the CI suite (Task 5.1).

### REQ-J1.5 — close only with checked evidence [test]

Fixtures: each evidence kind closes a request when its source confirms it and is refused when it does not (an unmerged pull request; an answer older than the arrival or addressed to someone other than the sender; a quote absent from the cited message; a quote from a relay with no matching send record by the hub's live holder, while one typed into the session or from a matched hub relay closes; an unknown follow-up id; a repeat citing an unknown id, itself or a request closed as a repeat; an empty no-ask reason); a close with no evidence is refused; a close from a session that does not hold the program is refused; a request aged past every window, its log line truncated and its event delivered and handed over stays open; a spooled arrival closes with the same verb; a pending prompt the stall watcher records as no longer pending is closed by code as a machine evidence citing that record, and by a seeded answer record; a `noask` close of an operator message appears in the next status. Run by the CI suite (Task 5.2).

### REQ-J1.6 — a silent turn end is held once [test]

Fixtures: a turn ending with an open request from that turn (the arrival that began it, or a spooled one) is held once, naming it; any later stop ends the turn and the request is marked as held past a turn end, which the next wake lists (Task 5.4); a turn whose requests are all closed is not held. Run by the CI suite (Task 5.2).

### REQ-J1.7 — the handover checks the ledger, at verify and at take [test]

Fixtures: a picture missing an open request fails verify, take, resume and the rules self-check, naming the id; a request appended between a passing verify and the take refuses the take until a second verify includes it (the mid-handover relay of the spec-pipeline evidence); a spooled arrival counts as open; a handover file that lacks a request the ledger holds does not rescue a picture that lacks it; take marks no event whose request is open; an unreadable ledger refuses the take with the handover's existing failure and the predecessor keeps the name. Run by the CI suite (Task 5.3).

### REQ-J1.8 — every wake re-reads the ledger [test + manual]

Fixtures: a wake composed over a fixture ledger shows the count, then every open request oldest first with its sender, excerpt and age, a held-past-turn-end mark where set and a spooled arrival among them, and an "and N more" past the bound; an unreadable ledger shows as unreadable; the wake-path check goes red on a seeded path that skips the composer, the gate's coalesced wake included; the panel line's render over fixture data shows the open count and the oldest request, and unreadable when the ledger is. The look of the panel and text-panel line is `[manual]`: the operator sees a preview of the real render over fixture data, the unreadable state included, and says yes before the pull request leaves draft, the yes recorded in the pull request. Run by the CI suite (Task 5.4).

### REQ-J1.9 — an unanswered request is raised [test]

Fixtures, on an injected clock: a request past its kind's window raises one blocker-class event naming it, its sender, age and excerpt, handed to the notification channel once; with several requests overdue, each interval from the previous repeat yields one combined repeat naming the open count and the oldest, delivered through the gate, until the last closes; neither is rendered as a routine line; a request closed before its window raises nothing; the shipped knob defaults equal D-28's; for each ledger knob (the windows, the interval, the excerpt bound, the link window, the wake-list bound) a machine-local value is ignored and reported while a shipped or adopter value is read (Tasks 5.1 and 5.4). Run by the CI suite (Task 5.4).

### REQ-J1.10 — the kill switch keeps capture [test]

Fixtures: with the kill switch set in a shipped or adopter layer, capture still appends, the turn-end hold, the handover refusal and the unanswered raises stand down to one wake line naming the open count, and a failed append and a failed redaction are still raised. Run by the CI suite (the hold in Task 5.2, the handover refusal in Task 5.3, the raises, the capture-failure raises and the wake line in Task 5.4).

### REQ-J1.11 — the measured claim [manual + test]

At Task 6's walk the operator compares the operator interruptions and the dropped-request misses with the baseline and the comparison is recorded (`[manual]`; the misses are recorded as unavailable until mission-control's miss ledger, its Task 83, has landed); a fixture run writes the daily counts (captured, closed by evidence kind, raised, handovers refused) with their values only to the machine-local location (`[test]`, Task 5.4).

### REQ-J1.12 — the hold and the refusal ship record-only [test + manual]

Fixtures: in the shipped `shadow` mode, a turn that `enforce` would hold is not held and a picture `enforce` would refuse passes, each named in its would-have record; a machine-local `enforce` is ignored and reported; an adopter-layer `enforce` turns each on; the one-line summary is computed from the record. The move to `enforce` is `[manual]`: the operator says yes on the hub's summary. Run by the CI suite (the hold in Task 5.2, the refusal in Task 5.3).
