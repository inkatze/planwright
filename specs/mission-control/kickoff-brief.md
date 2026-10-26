# Mission control — Kickoff brief

## 1. Header

- **Spec:** `specs/mission-control`
- **Spec commit at walkthrough start:** `eb92554bbd5cfcf21f76af55d69db1ec7d456e8a`
- **Walkthrough date:** 2026-10-22
- **Mode:** first activation (Status Draft, no prior brief)
- **Validator at pre-flight:** `scripts/spec-validate.sh` — 0 errors, 0 warnings
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true`,
  `kickoff_ready_ci_wait: 10m` (defaults; the machine-local layer sets none
  of them)
- **Doctrine resolved at run start:** security-posture, interaction-style,
  spec-format, discovery-rigor, autopilot-reflex, validation-rigor,
  decision-domains, kickoff-verification, kickoff-dialogue (all present)
- **Structured decision/transcript log:** no harness-provided log in this
  session; the turn mirror is skipped, not improvised into the repository
  (`kickoff-dialogue`, *Turn records*)
- **Working location:** the spec worktree on `planwright/mission-control/spec`,
  clean at start

## 2. Goal & glossary

**Restatement.** Mission control is one standing, conversational session per
program, the operator's only contact point for work too big to track by hand.
It launches, supervises, drives and retires every other session kind; it never
edits a repository itself; it consolidates decisions from every source into
the specs; it keeps working while the operator is away; and it brings the
operator only what needs their judgment, packaged to decide. The operator
needs no planwright vocabulary. Its rules and duties are shipped
configuration, delivered to every launched session and re-injected after
compaction. The bundle ships the core and a default duty set; the four large
duties are follow-on bundles.

**Rules out:** merging; sending to a person without the yes on exact text
and recipient; authoring code or editing a repository; replacing CI or the
automated reviewers; phone or remote access; a remote development rung; a
GUI dashboard beyond the in-app mod; cross-machine operation; the review
desk, spec currency, environment broker and night shift as duties here.

**Assumes:** the tower and fleet seams this bundle consumes exist (tower
contract, attention store and operator queue, fleet registry and daemon
layer, dispatch backends, catalog resolver, policy guards, model
allocation); the Claude Code mods API at the version floor D-6 names offers
what the research recorded; the routed amendments D-22 names will be drafted
and landed by their owner bundles.

**Implicit terms, resolved:**

| Term | Resolution |
| --- | --- |
| the record | The program's durable stores: rule store, decisions log, knowledge base and the specs. REQ-D1.4 names the same set as "the task, the spec, the code and the rule store"; the two are one set. |
| wake | The push path from an attention-store event into the session's turn. The design names only the failsafe tick; the push channel itself is carried to the design walk (section 4). |
| the first turn after silence | The turn after the operator returns, carrying what REQ-A1.7 names: what changed since they last looked. |
| knowledge-base freshness | The age of the index and the watermarks of the living-source table (D-9). |
| cost class, spend class | Enumerations the duty entry grammar defines (Task 1); the bundle fixes that they exist, not their values. |
| entry point | How an operator starts or resumes mission control is not stated; carried to the REQ-A walk (section 3). |
| kickoff question | Any selector or question a launched kickoff session raises; operator-only by REQ-I1.5 (below). |

**Contradiction found and resolved (REQ-B2.3).** The Goal and REQ-A1.6 had
mission control "drive kickoffs and amendments as guided conversations";
REQ-I1.5 carried the tower's "offer, never start". Both readings were
presented with the smallest edit each way. Grounds for the chosen reading:
offer-only breaks REQ-A1.4 (never hand the operator a per-session step),
while relay lifts only a tower limit D-2 exists to lift. The operator chose
relay by default with a configurable manual mode, and operator-only kickoff
questions as the guard against mission control settling comprehension
questions from its knowledge base.

**Spec edits applied in this section (consolidated):**

1. `requirements.md` REQ-I1.5 reworded: never open a kickoff unasked, never
   sign off; an asked-for kickoff or amendment runs in a launched, relayed
   session; every kickoff question is operator-only, answered in the
   operator's words and never settled from the record; relay-or-manual knob,
   relay by default, `manual` the operator's configured exception to
   REQ-A1.4. Amendment annotation and changelog entry added.
2. `design.md` D-2: the relayed kickoff added to the list of lifted tower
   limits, with amendment annotation.
3. `test-spec.md` REQ-I1.5: tag widened to `[design-level + Gherkin]`; the
   Task 15 eval fixture arm added (selector delivered as an item, operator's
   quote relayed, record never used, nothing opened unasked, `manual` hands
   the command over).
4. `tasks.md` Task 11: the relayed kickoff and amendment flow and its knob
   named in the deliverables. Task 15: the relayed-kickoff fixture named in
   the deliverables; REQ-I1.5 added to its citations.

**Mid-walk delta-scoped lens pass** (`kickoff-verification`, REQ-B1.4;
spec lens set per `artifact-lenses`; walked inline, declared: a four-file
delta of one requirement and its dependents). Validator and `lint:md` clean
after the edit (tool-grounded first).

| Lens | Findings | Notes |
| --- | --- | --- |
| Contract correctness and internal consistency | 1 | `manual` mode hands the operator a command, which REQ-A1.4 forbids; applied: REQ-I1.5 names it the operator's own configured exception. |
| Ambiguity and interpretation forks | none | "the record" and "operator-only" defined in the glossary above. |
| Citation and coverage integrity | 1 | Task 15 now carries the REQ-I1.5 fixture but did not cite it; applied. |
| Dead verification paths | none | The Gherkin arm runs under the behavioral-eval harness Task 15 wires. |
| Decision-domain gaps | none | The new knob is plain documented configuration under D-20. |
| Testability | none | Task 15's Done-when (fail on a seeded violation of each rule) covers the arm. |
| Cross-file consistency | 1 | D-2's lifted-limits list omitted the relayed kickoff; applied. |
| Documentation and glossary drift | 1 | `handoff` collided with `handover` (REQ-L1.6 session succession); applied: knob values are `relay` and `manual`. |
| Rendered-content safety | n/a | Prose rendered into no executing context. |

All four findings validated (re-read as the skill author and the Task 15
author; bundle-wide search for the surface patterns; sibling check against
tower-front-door REQ-D1.3 and human-gates) and applied in the same
disposition. Self-critique pass: nothing further.

Signed off: 2026-10-22

## 3. Requirements walkthrough

Walked per group, REQ-A through REQ-M, each group's intent restated and its
edge cases probed. Every edit below landed in place (Draft bundle), with an
amendment annotation on the requirement, a changelog entry, and the
dependent design, task and test entries aligned in the same disposition.

**Group A, the session kind.** Intent: one session per program, rebuilt
from durable evidence, never authoring, acting on the operator's behalf,
taking only the operator's words as a go, usable without planwright
vocabulary, resumed in one act. Finding: REQ-A1.1 (a launch that finds a
live holder refuses) and REQ-A1.7 (resume by name retires the predecessor)
both described an operator starting mission control while one was live,
and nothing said which applied; the entry point itself was unstated.
Decision (operator): the launch the operator asks for is the resume and
runs as the REQ-L1.6 handover; the successor D-30 launches with a handover
file proceeds; any other launch that finds a live holder refuses. The entry
point is the mission-control skill command with the program name as its
only argument, omitted when one program is configured (several ask; none
enters the guided first run).

**Group B, the rule source.** Intent: one versioned store with explicit
supersession, loaded at bring-up, re-injected after compaction, delivered by
the launcher, grown by proposals, audited mechanically. Three findings.
(1) REQ-B1.2, D-16 and Task 2 reported "two rules on one subject", but the
D-5 entry had no subject field and "conflicting meaning" is not a mechanical
test. Decision: `subject` joins the entry; the audit reports a shared
subject and the meaning call is the operator's. (2) Nothing said how a
standing decision stated once enters the store. Decision (operator, from a
picklist): direct entry, the operator's words being the go (REQ-A1.5),
echoed in one line, undoable; the proposal path is for inferred repeats.
(3) The operator raised that proposals should reach configuration too: a
review process run by hand is already deterministic as convergence steps,
and "there might be many more cases". Decision (operator, from a picklist):
proposals widen from duty-or-rule to any mechanism, an open list owned by a
mechanism inventory in the knowledge base (knobs, catalog steps, hooks and
permission rules, routines, duties, rule entries), refreshed from the
installed host and planwright surfaces; a settings-kind change is handed
over ready to apply and never written (REQ-G1.4). REQ-K1.7 added; REQ-C1.7
named the duty kind of it; the Goal bullets aligned. REQ-B1.6 and D-16 keep
"rule proposals" deliberately: the audit raises that kind specifically.

**Group C, the duty seam.** Probed who can enable a duty (only the
operator, D-14) and file ownership between duties (REQ-C1.1, REQ-K1.3,
REQ-K1.5: one writer, per-duty files). No change.

**Group D, lifecycle.** REQ-D1.8's "before a flip is offered or requested"
agrees with REQ-I1.2 (the flip stays inside the configured policy).
Finding: REQ-D1.6 required ignored audit files "verifiably backed up" with
no destination anywhere in the bundle. Decision (operator, from a
picklist): the program home, under a per-repository, per-branch reclaim
folder, verified by size and hash before removal, the file set a knob; a
repository-local backup folder was declined because reclaiming a checkout
would take its backups with it. D-8 and Task 4 carry it.

**Group E, durable watchers.** No change; the push wake channel is the
carried design question (section 4).

**Groups F to M.** F: presence (REQ-F1.4) is decided in D-7 through the
routed tower-comms amendment. G: the settings-handover clause landed on
REQ-G1.4 in group B. H, I, J, K, L: hold as written. M: REQ-M1.2 restates
REQ-E1.3 and shares its fixture; left in place as deliberate duplication
(M1.2 states the throughput consequence), so it is not read as drift later.

**Spec edits applied in this section (consolidated):**

1. `requirements.md`: REQ-A1.1, REQ-A1.7, REQ-B1.1, REQ-B1.2, REQ-B1.5,
   REQ-C1.7, REQ-D1.6, REQ-G1.4 reworded (annotated); REQ-K1.7 added; two
   Goal bullets aligned; three changelog entries.
2. `design.md`: D-5 (subject, direct entry), D-8 (reclaim folder), D-9
   (mechanism inventory), D-14 (retitled Mechanization proposals, reworded),
   D-16 (shared subject), each annotated.
3. `tasks.md`: Task 2 (subject, direct entry, shared-subject report), Task
   4 (backup destination and verification, cites D-8), Task 8 (inventory
   and its refresh, cites REQ-K1.7), Task 9 (mechanization proposal record,
   settings never written, cites REQ-G1.4 and REQ-K1.7), Task 11 (the
   command and its argument rules, cites REQ-A1.7), Task 15 (argument-rules
   and direct-entry fixtures, cites REQ-A1.7 and REQ-B1.1), Task 16
   (refusal arm).
4. `test-spec.md`: REQ-A1.1, REQ-A1.7, REQ-B1.1, REQ-B1.2, REQ-B1.5,
   REQ-D1.6, REQ-G1.4 entries extended; REQ-K1.7 entry added.

**Mid-walk delta-scoped lens passes** (`kickoff-verification`, REQ-B1.4;
one per edit set, walked inline over the four-file delta; validator and
`lint:md` clean after each):

| Lens | A | B | D | Notes |
| --- | --- | --- | --- | --- |
| Contract correctness and internal consistency | 1 | none | none | A: the first draft of the REQ-A1.1 refusal would have refused the handover successor D-30 launches; reworded to two permitted launches. |
| Ambiguity and interpretation forks | none | none | none | "launch kinds", "mechanism", "subject" defined below. |
| Citation and coverage integrity | 1 | none | none | A: the test entry named a Task 15 fixture Task 15 did not cite; citation added. |
| Dead verification paths | none | none | none | Every new arm names the task that builds its fixture. |
| Decision-domain gaps | none | none | none | Data-storage for the inventory and the backup folder decided in D-9 and D-8. |
| Testability | none | none | none | Shared subject and hash verification are mechanical checks. |
| Cross-file consistency | none | none | none | D-16 and REQ-B1.6 checked against the widened D-14; kept. |
| Documentation and glossary drift | none | 1 | none | B: the Goal bullets still said duty and rule proposals; aligned. |
| Rendered-content safety | n/a | n/a | n/a | Prose only. |

All three findings validated by re-reading as the Task 16, Task 15 and
Task 11 authors and by a fixed-string sweep of the bundle, and applied.

**Glossary additions:**

| Term | Resolution |
| --- | --- |
| launch kinds | Operator-asked (the resume, a handover), handover successor (carries a handover file), other (refuses on a live holder). REQ-A1.1. |
| subject | One free-text key per rule entry; the shared-subject report groups on it. D-5. |
| mechanism, mechanization proposal | Anything the host or planwright can make deterministic, and the confirmation that proposes one for a noticed repeat. D-14. |
| mechanism inventory | The knowledge base's living source of mechanisms by kind, refreshed from installed versions. REQ-K1.7, D-9. |
| reclaim folder | The program home's per-repository, per-branch backup of a reclaimed worktree's audit files. D-8. |

Signed off: 2026-10-23

## 4. Design walkthrough

Every decision read against the requirements walked in section 3 and the
tasks and tests that cite it. Ledger:

| D-ID | Disposition | Note |
| --- | --- | --- |
| D-1 | confirmed | Altitude: capability plus doctrine, the front door for most operators; the decomposition check at sign-off runs against it. |
| D-2 | amended (§2) | Relayed kickoff added to the lifted tower limits. |
| D-3, D-4 | confirmed | Duty catalog through the overlay; mechanics scripts, judgment on demand. The mod's wake (D-6) is not an LLM watcher. |
| D-5 | amended (§3) | `subject` on the entry; direct entry of an operator-stated decision. |
| D-6 | amended (§4) | The primary wake named: the mod watches the attention store and submits when idle; the daemon runner relays through the fleet's session relay where the mod does not load; the tick stays the failsafe on both paths. Which relays submit rather than stage is Task 7's research record; a staging relay falls back to the tick. REQ-E1.3 and REQ-M1.2 promised push and no decision delivered it. |
| D-7 | confirmed | The queue decides delivery; the wake prompt starts a turn, it delivers nothing to the operator, so REQ-F1.4 holds. |
| D-8 | amended (§3) | The reclaim folder under the program home. |
| D-9 | amended (§3) | The mechanism inventory as a living source. |
| D-10 to D-13 | confirmed | One launcher, positive liveness, one snapshot, calibrated autonomy. |
| D-14 | amended (§3) | Retitled Mechanization proposals; widened to any mechanism in the inventory; settings changes handed over. |
| D-15 | confirmed | Shadow mode. |
| D-16 | amended (§3) | Shared subject is the mechanical finding; meaning is the operator's. |
| D-17, D-18 | confirmed | Budgets and the ladder; the guided first run (now also the no-program branch of the resume command, REQ-A1.7). |
| D-19 | confirmed | Checked against the `manual` kickoff mode: a skill name appears only when the operator runs it themselves, which is that case. |
| D-20 | confirmed | The knobs added this kickoff (kickoff mode, reclaim file set) follow its rule. |
| D-21 | confirmed | Carried to the risk register: sections 2 to 4 add skill prose and the closure is at its cap. |
| D-22 to D-27 | confirmed | Routed edges, non-authoring and relay, undo, readiness and packets, gate data inside the floors, the default duty set. |
| D-28 | confirmed | The widened D-14 and the inventory fall under domains the walk already decides (configuration, knowledge engineering, LLM output quality); the kickoff gap check re-runs in section 7. |
| D-29, D-30 | confirmed | Handover over compaction; automatic succession, now also the path an operator-asked resume takes (REQ-A1.1). |

No decision superseded. No design decision contradicts a walked
requirement after the amendments above.

**Spec edits applied in this section:** D-6 amended (annotated);
REQ-E1.3 cites D-6; Task 5 (runner-side wake relay for mod-less sessions),
Task 7 (the attention-store watch, the relay research record, cites
REQ-E1.3 and REQ-M1.2); test-spec REQ-E1.3 arms; changelog entry.

**Mid-walk delta-scoped lens pass** (inline; validator and `lint:md`
clean): contract correctness none (D-4's no-standing-LLM-watcher floor
holds, the mod is not a model); cross-file none (D-7's delivery authority
untouched); citation none (both REQs now cite a task that builds the push
half); the remaining lenses none.

**Carried to section 5:** Task 15's Done-when has the behavioral fixtures
running in CI and blocking merges; the repository's standing guard
(`scripts/check-no-ci-evals.sh`) forbids any eval in CI and the sibling
specs that use the harness say "never in CI, on demand". A Done-when no
deliverable can satisfy: section 5 opens on it as the REQ-B2.3 halt.

Signed off: 2026-10-23

## 5. Verification approach

Opened on the REQ-B2.3 halt section 4 carried: Task 15's Done-when had the
behavioral fixtures running in CI and blocking merges, while the
repository's standing guard (`scripts/check-no-ci-evals.sh`) forbids any
eval task in CI and the sibling bundles that use the harness say "never in
CI, on demand". Both readings were presented with the smallest edit each
way (drop the guard for this bundle, or move the fixtures off CI); the
operator resolved by spec edit: the fixtures run on demand, a cadence step
in the steps catalog records a run per head, and a red or missing record
refuses the ready flip of this bundle's later units. The halt is closed.

**Coverage mix** across test-spec tags, re-derived after every edit in this
section with
`grep "^### REQ-" test-spec.md | sed 's/.*\[\(.*\)\]$/\1/' | sort | uniq -c`
(tag order inside a bracket varies in the file; the rows below merge the
orderings):

| Tag | Entries | Verified by |
| --- | --- | --- |
| `[test]` | 51 | Deterministic shell tests, run by CI through the `check` aggregate and the sharded test task. |
| `[Gherkin]` | 10 | The behavioral-eval harness, on demand, recorded by Task 15's cadence step. |
| `[test + Gherkin]` | 9 | Both of the above; the script half in CI, the turn half on demand. |
| `[design-level + test]` | 8 | The test half as above; the design half at kickoff and at each delta re-walk. |
| `[design-level + Gherkin]` | 5 | As above, with the harness for the turn half. |
| `[design-level]` | 1 | REQ-A1.5 (altitude), judged at this kickoff's D-1 check and re-judged at every re-walk. |
| `[test + manual]` | 1 | REQ-F1.2: the fallback is tested; the polish is swept by the operator on a real terminal. |
| `[Gherkin + manual]` | 1 | REQ-F1.12: the first-run turns under the harness; the end-to-end run swept by the operator. |

Eighty-six entries for eighty-six requirements (one entry each, checked by
`grep -c "^### REQ-" test-spec.md` against `grep -c "^- \*\*REQ-"
requirements.md`).

**Verification ownership.**

- `[test]` entries: CI, via the lint job's `check:non-test` and the sharded
  `mise run test`, the two task invocations the repository's CI workflow
  runs (the `check` aggregate itself is the local gate, not a CI step: a
  sign-off lens finding corrected this bullet, which first named it). Task 1
  wires `check:duties` and the knob inventory check, Task 8 the
  copied-section lint and Task 7 the panel's `claude plugin test` suite into
  `check:non-test`; nothing had wired the plugin tests before (CI ran
  `claude plugin validate` only), and the CI CLI pin sat below the mods
  floor, which Task 7 raises.
- `[Gherkin]` entries: the behavioral-eval harness, never in CI. Task 15's
  cadence step runs the suite and records its outcome per head; a later unit
  of this bundle is not marked ready without a green record on its head; the
  manual sweep inventories the runs.
- `[design-level]` entries: this kickoff (section 4's ledger and the
  sign-off altitude check), then every delta re-walkthrough.
- `[manual]` entries: the operator, inventoried by the drain pass over the
  live bundle's `[manual]` entries (REQ-F1.2, REQ-F1.12).

**Dead verification paths found and closed.**

1. Task 15's "run in CI" (the halt above): closed by the on-demand cadence
   step; the test-spec preamble and REQ-B1.1's entry say so.
2. The panel's `claude plugin test` entries had no runner anywhere in CI or
   the `check` aggregate: closed by Task 7's wiring, with a Done-when that
   the suite fails the gate on a seeded drawing defect.
3. REQ-A1.2 and REQ-M1.1 named the forge as the only external state, so a
   program whose public state lives elsewhere had no verifiable path:
   closed by REQ-H1.4 and the generalized D-12 (below).

**Operator question resolved here.** Whether mission control adapts to
programs whose public state is a tracker, a document store or a design tool
rather than specs, with the source of truth scattered. Resolution, chosen
by picklist (the operator unsure that tracker adapters are feasible short
term, naming Notion and Jira as current trackers and Figma as a candidate
by category): REQ-H1.4, a per-program state-source map naming, per fact
class (work items, code state, decisions, deadlines, designs), the
authoritative source and its mode: `record` (a store planwright writes,
directly or through a session mission control dispatches; the sign-off
lens pass reworded this from "a store mission control writes", which read
against REQ-A1.3), `snapshot` (an adapter refreshes an age-stamped copy) or
`cited`
(links and the operator's statements only, never polled, never claimed as
known). Default: specs `record`, forge `snapshot`. A source without an
adapter is `cited`, and mission control names the mode and age wherever it
reports from a source. D-12 becomes source-agnostic with the forge as the
shipped adapter; adapters for trackers, document stores and design tools
are a fifth follow-on bundle Task 14 seeds, their auth and write policy
decided there. The guided first run (D-18) gains the state-source
objective. Adapter feasibility goes to the risk register (section 7) with
its early signal.

**Spec edits applied in this section** (in place, annotated, each with a
changelog entry under the requirements changelog):

- Task 15 retitled and reworded: fixtures on demand, never in CI; the
  cadence step; the manual sweep row; CI for the deterministic checks only;
  fixtures added for the argument rules, direct rule entry and the
  cited-source answer; cites REQ-A1.7, REQ-B1.1, REQ-H1.4.
- Task 7: the plugin tests wired into the `check` aggregate; Done-when
  extended.
- test-spec preamble: the behavioral-eval ownership sentence.
- REQ-H1.4 added (`[test + Gherkin]`); REQ-A1.2 and REQ-M1.1 generalized
  from the forge to snapshot-mode sources; goal bullets, scope paragraph and
  out-of-scope list aligned (adapters named as follow-on, `cited`
  meanwhile).
- D-8 (state-source map in the program block), D-12 (retitled, generalized),
  D-18 (state-source objective), D-22 and D-27 (fifth follow-on), D-28
  (state-source map and adapter seam added to the API surface) amended.
- D-1 and the requirements' altitude paragraph qualified: the duty catalog is
  the one operator-facing extension point; the adapter contract is a seam
  later planwright bundles implement.
- Tasks 1, 5, 7, 11 and 14 carry the seam (program-block map with default and
  a `check:duties` failure for a snapshot source with no adapter; the
  source-agnostic `mc-snapshot.sh` with the forge adapter and a fixture
  second source; panel mode and age; the source-naming rule and first-run
  objective; the fifth pending note). Task 5 retitled for source snapshots.

**Glossary additions:** *state-source map* (the per-program table of fact
class to source and mode), *mode* (`record`, `snapshot`, `cited`, as
defined above), *adapter* (the script that refreshes one snapshot-mode
source; the forge's ships in this bundle), *cadence step* (a steps-catalog
entry whose recorded run per head gates a later unit's ready flip).

**Mid-walk delta-scoped lens passes** (`kickoff-verification`, REQ-B1.4;
spec lens set per `artifact-lenses`; walked inline per edit set: A the
Task 15 and Task 7 verification edits, B the state-source map). Validator
and `lint:md` clean after each set.

| Lens | A | B | Notes |
| --- | --- | --- | --- |
| Contract correctness and internal consistency | none | none | The step's refusal is a ready-flip gate, not a merge block, matching the repository's step-record mechanism; `cited` claims nothing, so REQ-A1.2's durable-evidence rule holds. |
| Ambiguity and interpretation forks | none | 1 | `cited` versus `snapshot` for a source with an adapter the operator does not want: the map is the operator's; a mode is never inferred. Recorded in REQ-H1.4's wording; glossary above. |
| Citation and coverage integrity | none | none | REQ-H1.4 cited by Tasks 1, 5, 7, 11 and 15 and carried by its own test entry. |
| Dead verification paths | 2 | none | The two paths above, both closed. |
| Decision-domain gaps | none | 1 | Adapter auth and write policy are undecided here by design (follow-on); carried to section 7 as a named row rather than decided in the core. |
| Testability | none | none | Task 1's Done-when fails `check:duties` on a snapshot source with no adapter; Task 5's fixture second source exercises the seam without a real tracker. |
| Cross-file consistency | none | 1 | D-1 and the altitude paragraph said "exactly one new extension point"; the adapter contract read as a second. Applied: qualified as operator-facing, the adapter contract an internal seam. |
| Documentation and glossary drift | none | 1 | Task 5's title still said "forge snapshot"; renamed. The forge-only sentence in REQ-M1.1's test entry stays: it tests the shipped adapter's deduplication. |
| Rendered-content safety | n/a | n/a | Prose rendered into no executing context; the map's values are an enumerated set, never a path or command. |

All findings validated (re-read as the Task 5 and Task 15 author;
bundle-wide fixed-string search for "extension point", "forge snapshot" and
"in CI"; the CI workflow and the `check` aggregate read for what runs) and
applied in the same disposition. Self-critique pass: nothing further.

Signed off: 2026-10-23

## 6. Task graph

Reconstructed from the `Dependencies:` lines (authoritative; the graph
tool's render, `scripts/spec-graph.sh specs/mission-control`, agrees and is
derived). Re-derived after the edits below. No cycle.

**Waves** (tasks that can run in parallel once their wave opens):

1. Tasks 1, 6, 12, 14 (no dependencies; 6, 12 and 14 are routed work and
   pending notes, startable at once).
2. Tasks 2, 5, 8 (after 1).
3. Tasks 3 (1, 2), 7 (2, 5), 9 (8).
4. Tasks 4 (3), 16 (2, 3, 7, 8).
5. Tasks 10 (3, 4, 5, 9), 11 (2, 3, 5, 6, 7, 8, 9, 16).
6. Tasks 13 (10, 11), 15 (11).

(The wave list was re-derived at sign-off: the edge 4 → 10 chosen below
moves Task 10 to wave five, which the first draft of this list missed, and
the sign-off lens pass added two edges, 2 → 9 and 8 → 16, recorded in the
sign-off section; neither changes the critical path.)

**Critical path, effort-weighted** (per the `Estimated effort:` lines):
1 → 5 → 7 → 16 → 11 → 13, seventeen days. The path through Task 15 in
place of Task 13 has the same length (both hang off the skill at two days
each), so the two closing units are jointly critical. Slack elsewhere: the
launcher chain 1 → 2 → 3 → 4 closes at day nine, the autonomy chain
1 → 8 → 9 → 10 at day thirteen. The panel (Task 7, four days) is the
widest single unit on the path; its research record for the relay
submit-or-stage question (D-6) is on it too.

**Edges added this section** (picklist, operator-chosen):

- 4 → 10: the session-keeper duty runs the reclaim predicate Task 4 builds.
  Task 10's earliest start moves from day seven to day nine; it stays off
  the critical path.
- 10 → 13: the operator doc describes the default duties.

**Deliberate non-edges**, recorded so nobody adds them later:

- 10 → 11: the skill is built against the catalog seam (Task 1) with
  fixture duties, not the shipped default duties. Adding the edge would put
  Task 10's four days ahead of the skill for no verification gain; the
  operator doc (Task 13) carries the dependency instead.
- 12 → anything, 6 → anything but 11, 14 → anything: routed amendments and
  pending notes land in their owner bundles; the skill waits for the queue
  amendment (6) because its picklist shape and settled-by-default kinds come
  from it, and for nothing from 12 or 14.
- 15 → 13: docs and fixtures run in parallel; neither reads the other.

**Gate reach of Task 15** (picklist, operator-chosen): the eval cadence
step gates the ready flip of this bundle's units still open when the step
lands and of every follow-on bundle's units. Section 5 recorded it as "this
bundle's later units"; this wording supersedes that, since Task 15 sits in
the last wave and "later units" would name almost none. Task 15, its
Done-when and the test-spec preamble reworded.

**Dependency check on the section 5 additions:** Task 1's source-map check
and Task 5's adapter seam add no edge (5 already depends on 1); the panel's
mode-and-age column and the skill's source-naming rule both sit downstream
of 5 already; the cadence step uses the repository's existing steps catalog
and step-record mechanism, no in-bundle dependency.

**Spec edits applied in this section:** Task 10 and Task 13 dependencies
(annotated); Task 15 deliverable and Done-when reach (annotated); test-spec
preamble aligned; changelog entry.

**Mid-walk delta-scoped lens pass** (inline; validator and `lint:md`
clean): contract correctness none (no cycle, every added edge names a
deliverable the dependent consumes); dead verification paths 1, the gate
reach above, applied; cross-file 1, the test-spec preamble, applied;
citation none (no REQ moved); the remaining lenses none. Validated by
re-running the graph tool and reading Tasks 4, 10, 11, 13 and 15 as their
author. Self-critique pass: nothing further.

Signed off: 2026-10-24

## 7. Risk register

Inputs: risks surfaced in sections 2 to 6, the operator's cold-review
questions (the relay default in section 2, the settings proposals in
section 3, the scattered source of truth in section 5), and the
decision-domains gap check below.

**Decision-domains gap check.** Catalog resolved through the merged path
(`scripts/resolve-catalog.sh decision-domains`, run under `bash`; the
script is not POSIX sh) and walked against D-28. Every resolved domain is
either decided in D-28 with its D-IDs, named as adding no surface
(authentication, organization design), or named as not touched (packaging
and pricing, IP posture). One gap found: D-28 listed deploy and migration
and versioning scheme as not touched, while the bundle creates persisted
stores in the program home with no format version and changes the launcher
on a fleet with sessions in flight. Resolved by spec edit (picklist): D-8
gains a `format` field on every store, an additive-only rule for this
bundle's shapes, migration as a follow-on's task, and a per-launch rollout
of the launcher; D-28 records both domains as decided; Tasks 2, 8 and 16
check the field. Row 10 keeps the residual risk.

| # | Risk | Mitigation | Early signal |
| --- | --- | --- | --- |
| 1 | The skill's instruction closure is at its cap (D-21) and this kickoff added skill prose: the argument rules, the source-naming rule, the first-run objective, the one-live-session paths. | D-21's rule: mechanics into scripts, the catalog and the doctrine doc; deltas from the tower by reference; never raise the cap. | `check-instructions.sh` red on Task 11's first draft; a budget trim that drops a rule's last copy (checked against the manifests, never by shortening). |
| 2 | `claude plugin test` may be absent or differ on the CI runner; Task 7 makes it a gate for the first time, and the CI workflow's CLI pin sat below the mods floor when this was written. | Task 7's Done-when (the suite fails the gate on a seeded defect, on a CLI at or above the floor); Task 7 raises the pin. | Task 7's first CI run; a green run that executed no test; a pin bump that breaks an unrelated job. |
| 3 | Adapters for trackers, document stores and design tools may not be feasible short term (the operator's doubt; Notion and Jira in use, Figma by category). | `cited` is the day-one mode: links and the operator's statements, never polled, never claimed as known (REQ-H1.4); the fifth follow-on decides feasibility per source. | The operator citing a tracker as the state mission control should hold; a program whose work-items class stays `cited` for its whole life. |
| 4 | Adapter authentication and write policy are undecided here by design (authentication and secrets-configuration domains). | The core's `cited` mode writes nothing and holds no credential; the follow-on decides auth, token storage and whether an adapter ever writes. Program home never holds secrets (D-8). | The first adapter design asking for a credential in the program home. |
| 5 | The daemon-side wake relay may be able to stage text but not submit it (D-6); mod-less sessions would then wake only on the failsafe tick. | Task 7's research record decides submit-or-stage per backend before the relay ships; the tick stays the floor for every session kind. | The research record naming a backend where staging is all the harness supports. |
| 6 | The panel depends on the mods API at its version floor; API drift breaks the panel. | The text fallback (REQ-F1.2) carries every item; the floor is an accepted dependency adoption (D-6); plugin tests catch drift at upgrade. | Plugin tests red after a CLI upgrade; the fallback drawing where the mod used to. |
| 7 | An operator reads a `cited` fact class as known state. | Mode and age named wherever a report draws on a source; a stated gap where a class is only cited (REQ-H1.4); the Task 15 cited-source fixture. | The fixture failing; an operator item acted on a cited fact that had moved. |
| 8 | The eval cadence step gates ready flips of still-open and follow-on units; a flaky suite blocks flips. | The step records per head and re-runs on demand; the manual sweep inventories runs; a red record is a finding to read, never a reason to skip the step. | Repeated re-runs of the same head in the sweep; a flip proposed without a record. |
| 9 | Tasks 6 and 12 route amendments through other bundles' sign-off, and the skill (Task 11) waits on Task 6. | Both are wave-one work with no in-bundle dependency, so they start first; D-22 names the edges; a late owner bundle delays the skill, not the core. | The tower-comms extension not signed when wave five opens. |
| 10 | Residual of the gap check: the format field is new convention; a follow-on bundle could change a store shape in place anyway. | D-8's additive-only rule and refusal of unknown formats; Tasks 2, 8 and 16 test the refusal; D-8 names a shape change a follow-on's migration task. | A follow-on draft editing a store shape without a migration task; a reader refusing a store after an upgrade. |
| 11 | The hub record the bundle mines is company data. | Cited generically in the Sources section; no excerpt, hostname or identifier in any committed artifact; the sign-off rendered-content lens re-checks. | Any committed line quoting the record. |

**Open questions.** None remain open. The relay default (section 2) is
the `relay` knob value with `manual` as the operator's configured
exception; the settings proposals (section 3) are the mechanization
proposals over the mechanism inventory; the scattered source of truth
(section 5) is the state-source map. The adapter questions (rows 3 and 4)
are accepted risks owned by the fifth follow-on bundle.

**Spec edits applied in this section:** D-8 (format field, additive-only
rule, launcher rollout; annotated), D-28 (two domains moved to decided;
annotated), Tasks 2, 8 and 16 Done-when (the format check); changelog
entry.

**Mid-walk delta-scoped lens pass** (inline; validator and `lint:md`
clean): contract correctness none (the format rule touches no walked
requirement; the launcher rollout agrees with D-30's succession, which
replaces a session only through a handover); decision-domain gaps none
after the edit (all nineteen resolved domains accounted for); testability
none (three Done-when clauses name the refusal); cross-file none (D-28 and
D-8 agree; Task 14's pending notes are unchanged, since D-8 itself assigns
a shape change to the follow-on that needs it); the remaining lenses none.
Self-critique pass: nothing further.

Signed off: 2026-10-24

### Execution research: Task 5 (2026-10-25)

Scoping: version-sensitive APIs only (the forge's GraphQL schema and the
fleet's two session relays); no new dependency, so a short pass against
primary sources.

- **Forge read shape.** One GraphQL query per repository carries the rate
  limit, the viewer, and per pull request the head, draft state,
  mergeability, review decision, thread resolution, the rollup check state
  and the review and comment counts; checked live against the forge with
  gh's built-in jq, which has `fromdateiso8601`. The patch id needs a
  diff read per pull request, so the adapter carries it forward while the
  head is unchanged. Tradeoff: the newest 50 open pull requests and the
  first 100 threads per pull request, stated in the adapter's header.
- **Row 5 (submit or stage).** The relay ships here as Task 5 requires,
  on what the fleet's own relays already document: the stream-json steer
  writes a user turn on the worker's stdin (a submit), and the tmux
  buffer-paste deliberately loads no newline (a stage, measured in
  `scripts/orchestrate-relay.sh`). The tick re-sends anything not
  submitted, so a staged or refused wake is found within one tick. Task
  7's research record still decides the mod's path and may refine the
  per-backend table; no new risk.
- **Adapter registration.** Registered through a `snapshot-adapters`
  catalog merged by the existing catalog resolver, the shape D-3 chose for
  duties, so a later bundle adds an adapter with an overlay entry and no
  seam change.

## 8. Sign-off

First activation, full walkthrough, every section above signed, no
inconsistency open (the one REQ-B2.3 halt, section 5, was resolved by spec
edit). Sign-off date 2026-10-24.

### Lens review pass (sign-off, full bundle)

Scope: the whole bundle at first activation (`kickoff-verification`,
REQ-A3.3). Artifact class: spec; lens set per `artifact-lenses`. Fan-out:
one read-only sub-agent per lens on the opus tier, eight agents, each
briefed with the bundle paths, the format conventions and the validation
rule (re-read as the consumer, search every expression of the claim before
reporting); rendered-content safety walked inline, with the data-hygiene
scan. Every finding was validated against the files (and the doctrine docs
for the drift lens) before disposition; the operator dispositioned them by
picklist: 41 applied as the stated fix in one batch, the four that needed a
design call decided one by one (A to D below), none declined, none deferred.

| Lens | Findings | Disposition |
| --- | --- | --- |
| Contract correctness and internal consistency | 6 | Applied: D-12's "without a core edit" reworded; `record` redefined so mission control writes no repository (REQ-H1.4); deadline-watch's day-one sources stated (D-27, Task 10) with unmapped classes defaulting to `cited`; the no-adapter check moved from Task 1 to Task 5; who retires the predecessor aligned with REQ-L1.6, with the hung-predecessor arm (REQ-A1.7, Task 16, test); reserved proposals added to REQ-F1.8's reasons. |
| Ambiguity and interpretation forks | 8 | Applied: "work repository" replaced in REQ-I1.2; rule render scope stated (D-5 unchanged, the forks settled in REQ-G1.2's rewrite and Task 2's verb); wake count and its knob named (REQ-L1.5, D-29); `unknown` state added (D-11, Task 4); default map completed (REQ-H1.4); decision class defined (D-13, REQ-F1.9); "since they last looked" anchored in the tests; the guidance knob remembered in the machine-local layer (D-18). |
| Citation and coverage integrity | 2 | Applied: REQ-A1.5 and its test cite the tower skill's operator's-own-words rule; D-23 cites fleet-autonomy D-17. Mechanical checks clean: 86 requirements and 86 test entries in bijection, every requirement cited by a task, every D-ID cited (D-28 from the changelog), no dangling ID, five qualified foreign citations resolving to the record relied on. |
| Dead verification paths | 6 | Applied: CI wiring through `check:non-test` (Tasks 1, 7, 8, preamble, this brief's section 5); the CI CLI pin raised to the mods floor (Task 7, risk row 2); one fixture per Gherkin arm as a decided rule (Task 15); the `mission-control` guard tier and fixture rows (decision A, Task 3, D-10, D-28, five test entries); REQ-G1.1's arm made a static profile check; the knob inventory check and the copied-section lint built (Tasks 1 and 8, REQ-J1.1, REQ-K1.4). |
| Decision-domain gaps | 5 | Applied: the no-credential rule written into D-8; deadline-watch (as above); monthly log segments (decision B, D-9, Task 8, REQ-K1.5); the dead-holder lock release (D-9, Task 8); the decide-or-queue routing fixture (REQ-F1.8, Task 15). All nineteen resolved domains accounted for after the edits. |
| Testability | 5 | Applied: Task 3 (tier refusal, deterministic name), Task 5 (backoff, second source's polls), Task 10 (recorded screenshot judgment, deadline priority, retargets, clipboard drafts), Task 11 (pointer and knob checks), Task 13 (glossary terms link to sections). |
| Cross-file consistency | 6 | Applied: tasks.md's follow-on list names five; missing annotations added (REQ-C1.7, REQ-G1.4, REQ-A1.2, REQ-M1.1, D-16, D-22); "source polls per hour" (REQ-L1.2, D-17, Task 5); edges 2 → 9 and 8 → 16; the Task 15 annotation moved below the task's fields. |
| Documentation and glossary drift | 7 | Applied: Task 13 lists the kickoff's concepts and names the glossary file; the program home moved to a human-owned location per storage-classes (decision C, D-8); prompt answering assigned to the tower-comms record (decision D, REQ-G1.2, D-5, test); REQ-I1.4 carries human-gates' force-push row; D-21 cites instruction-hygiene's order; D-24 gains `subject`; the merge line distinguishes authorizing from executing. |
| Rendered-content safety | n/a | Prose rendered into no executing context; fixed-string scan of the five committed files for links, hostnames, credential words and archive names found only a repository-relative catalog path. |

**Decisions A to D** (operator, by picklist): A, a `mission-control` guard
tier (tower denials plus policy-bounded flips) rather than running under the
tower tier; B, monthly log segments rather than size-based segments or an
accepted risk; C, a human-owned default for the program home rather than a
recorded deviation; D, the tower-comms standing-decision record answers
prompts rather than a coverage field copied into the rule store.

**Kickoff-specific altitude check (REQ-H1.3):** triggered bundle. The
Sources section pins four altitude claims from the invocation seed and one
from the operator asides; D-1 is the altitude record, cited from the goal
and scope paragraphs; the decomposition matches the claimed altitude
(capability plus doctrine: a doctrine doc in Task 13, a skill in Task 11,
mechanism tasks under them, the duty catalog as the one operator-facing
extension point). No finding.

**Ship-gate check (REQ-L1.4):** the walk named no out-of-band fix. Its
deferrals are tracked in the spec itself (the fifth follow-on bundle through
Task 14's pending note) and in this register (rows 3, 4 and 10); the
decisions owed by the operator were all taken in-band. No prose-only item.

**Post-lens stale-reference sweep (REQ-B1.5):** fixed-string search of the
bundle and this brief for the phrases the pass re-scoped (the CI command,
the `record` definition, "work repository", "step count", "forge polls",
"marked session", "later units", the wave list). Three stragglers in this
brief corrected before the anchor: the section 5 ownership bullet (CI runs
`check:non-test` and `test`, not the `check` aggregate), the section 5
`record` wording, and the section 6 wave list (Task 10 in wave five after
the 4 → 10 edge). The bundle's remaining "work repository" uses are the
doctrine's sense and stand.

### Pre-flip verification

- **Lint (REQ-B1.2):** `mise run lint:md` over the five files in
  `specs/mission-control/`: 0 errors (one MD036 raised during the pass by a
  one-line annotation, fixed by expanding it).
- **Validator:** `scripts/spec-validate.sh specs/mission-control`: 0 errors,
  0 warnings before the flip and again after it.
- **Recorded claims re-derived (REQ-B1.3):** a fixed-string, data-only
  re-derivation of every figure this brief records (requirement and test
  entry counts and their bijection, the per-tag coverage mix, the
  design-level-only and manual entries, the D-ID and task counts, the edge
  count, the critical path and its length, the equal-length path through
  Task 15, the wave list, the added edges and the non-edge, the
  decision-domain count, D-28's untouched domains, the risk row count, the
  signed sections) matched after the corrections above. The wave list was
  the one mismatch the re-derivation caught; corrected in section 6.
- **Enumerations cross-checked (REQ-E1.2):** the only counts in anchored
  prose are the five follow-on bundles (owned here, named in D-22, D-27 and
  the scope), the configuration layers (the doctrine's term) and the mods
  version floor (an external reference cited from the research source).
  Nothing to convert.

### Approval and flip

The shared-understanding approval summary was emitted and the operator
approved by picklist ("Approve": flip, record, commit, push, draft PR,
point, CI-gated ready flip). `**Status:**` Draft → Ready and
`**Last reviewed:**` → 2026-10-24 on all four spec files; validator re-run
after the flip.

### Record

Class: meaning
Lens-pass: the lens review pass recorded in this section (sign-off, full
bundle, eight lenses by fan-out plus one inline, 45 findings, all
dispositioned)
Anchor: `fba783ef835789583c61f3d09a13932de1108a69` — computed as
`scripts/spec-anchor.sh specs/mission-control`
