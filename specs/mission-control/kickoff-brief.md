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

### Execution research: Task 5 (2026-10-25, after sign-off)

Recorded during Task 5's execution, after the sign-off above, as
`/execute-task`'s research step appends to the risk register. It is not
part of the walked and signed section and changes no decision; the sign-off
in section 8 covers the brief as it stood on 2026-10-24.

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

### Execution research: Task 7 (2026-10-26, after sign-off)

Recorded during Task 7's execution, as the Task 5 record above was; it
changes no decision and is not part of the signed section.

Scoping: one version-sensitive API (the Claude Code mods API, read from the
type declarations and validator the installed CLI ships, 2.1.310) and the
relay question risk row 5 left to this task; no new dependency, so a short
pass against those primary sources and local probes.

- **Row 5, per backend (submit or stage).**

  | Path | Submits or stages | Fallback |
  | --- | --- | --- |
  | The mod (`$.prompt.submit`) | Submits: the prompt starts a turn of its own once the session is idle, and the call resolves as that turn starts. The mod holds a wake while its session is busy and marks the events submitted only after the call resolves. | Its own tick, at the tick cadence. |
  | stream-json, stream-json-persistent (`fleet-streamjson.sh steer`) | Submits: a user turn on the worker's stdin. | The daemon tick. |
  | tmux (`orchestrate-relay.sh deliver tmux`) | Stages only: a buffer paste with no newline. | The daemon tick re-stages until the session acknowledges. |
  | Any other backend (a one-shot print run, a cloud session) | Neither: no session relay reaches it, and the relay reports it unreachable. | None; a wake cannot reach such a session at all. |

- **Idle.** The API has no idle query. The mod tracks the main loop's
  `turn.start` and `turn.complete` and holds a wake between them, then
  submits it as the turn completes; a timer alone would wait a redraw.
- **Context and limits.** `$.session.usage()` carries the context percent
  and the rate-limit windows the status line shows; either may be absent
  (no reading yet, no subscription), so the completed-wake count stands in
  for the percent exactly as D-29 states.
- **Compaction.** The `session.compact` hook appends the rendered rules to
  the compacted conversation on its way up, rather than appending a row
  after it, which could land before the engine replaces the transcript. A
  deferral is a `skip`, never for a manual compaction, only while a
  handover verb is installed, and not past 95% context.
- **Packaging.** The module is listed in a second hooks file the manifest's
  `hooks` field names, so `hooks/hooks.json` and its guard hooks are
  untouched; `claude plugin details` lists every event that file registers
  with the field in place. Whether a CLI below the floor reads the second
  file cleanly was not probed (a second CLI install is ruled out for
  workers); the floor is the accepted dependency of risk row 6.
- **Tests.** The plugin-test kit offers no filesystem or process access,
  so the mod reads every store through one script whose output the tests
  supply; that script is tested in the shell suite against real fixture
  stores. Each plugin test was checked to fail under a mutation of the
  behaviour it covers before it was trusted.
- **Edges to later units.** The presence marker is the producer side the
  routed queue amendment's presence verb reads; the measures file is what
  Task 9's measures write; the `handover-due` event is what Task 16 acts
  on; the decisions log is read in the layout Task 8 writes. Each absent
  store draws as absent, never as empty.

### Execution research: Task 4 (2026-10-27, after sign-off)

Recorded during Task 4's execution, as the records above were; it changes
no decision and is not part of the signed section.

Scoping: two security-touching patterns (a script that copies files out of a
worktree into the program home, and one that removes a worktree) and the
process-table read liveness rests on; no new dependency, so a short pass of
local probes against the installed git and the existing fleet scripts.

- **Ignored files and removal.** A probe showed `git worktree remove`
  deletes a clean worktree's ignored files without a word, so the backup
  must finish and verify before the removal starts, never after.
- **Removal reused, not rebuilt.** `scripts/fleet-cleanup.sh worktree`
  already removes a worktree on positive evidence (clean, and pushed or
  merged at exactly its head), behind the daemon gate, the self-target
  guard and the audit trail. The reclaim runs its own predicate and backup,
  then hands the removal to that arm from the main checkout.
- **A worker-written `.git` file.** A worktree's `.git` file is the
  worker's to write, and git trusts it: a review pass showed a forged one
  pointing at a repository built in the worktree runs `core.fsmonitor`
  during a plain `git status`. The reclaim takes the worktree only when the
  program repository's own `worktrees/<id>/gitdir` points back at it,
  names that git directory on its own calls on the worktree, and turns
  `core.fsmonitor` and hooks off for every git call that reads it, the
  removal's included, through git's environment configuration. A submodule
  is refused outright: its git directory is the worker's to configure and
  status would run its filters.
- **Copying out of a worktree.** Only files git reports ignored are copied;
  a symbolic link is never followed, a file name holding a newline is
  refused (it would split the file list), and a source or destination
  directory that resolves outside its root is refused, so a worktree cannot
  steer a copy of an arbitrary file into the program home or a copy out of
  it. A refusal before the removal takes back the copies and folders it
  made, so none blocks the next attempt; once the removal starts the copies
  stay, since a removal failing partway may already have deleted their
  sources.
- **Untracked files.** `git status` honours `status.showUntrackedFiles`, so
  the clean check names `--untracked-files=all`: with `no` set, an untracked
  file passed and `git worktree remove` deleted it.
- **Liveness.** Death is `scripts/fleet-death-evidence.sh`'s positive
  verdict, which tells lost observability from a gone process: a tmux
  window gone from a healthy server, or the pid in it gone; a stream-json
  worker's recorded pid gone, or a state directory whose supervisor removed
  both pidfiles on exit. A window id is trusted only while the window
  still carries the session's name. "In use" is any process the reclaim
  can see whose working directory is in the worktree, read from procfs or,
  where there is none, `lsof`; in practice those are the operator's own,
  since another user's are not visible without privilege, and a procfs
  that hides this process's own working directory refuses the reclaim.
- **Pane signals.** The selector, staged-paste, busy and input-box markers
  come from `scripts/fleet-pane-vocabulary.sh`, the one place the TUI's
  text is pinned, matched as whole strings: under `LC_ALL=C` a bracket class
  of box glyphs matches single bytes, which a review pass caught skipping
  every line opening with a bullet glyph. The busy-unchanged hash drops
  spinner lines, whose timer ticks every second, so only the work above
  them counts as change.

### Execution research: Task 16 (2026-10-28, after sign-off)

Recorded during Task 16's execution, as the records above were; it changes
no decision and is not part of the signed section.

Scoping: one version-sensitive question, how a successor takes the program
name unattended (D-30's research item), read from the installed CLI
(2.1.312: its `--help` and the mods session surface its binary carries) and
the CLI's session documentation; no new dependency, so a short pass.

- **What the harness offers.** A session's name is a display name set at
  launch (`claude -n <name>`: the prompt box, the resume picker and the
  terminal title) or by the interactive `/rename` command inside that
  session; `--resume` finds a session by id or that name. The mods session
  surface has no rename or name-transfer call. Public issue reports of
  renamed sessions that resume by name cannot find (several CLI versions)
  argue against building on it.
- **The takeover path chosen.** The program name is planwright's own
  holder record under the program's runtime directory, moved by
  `scripts/mc-handover.sh take` (or `resume`) once the predecessor releases
  (or the handover window closes), never the harness's display name. Sessions
  reach mission control through the event store and the wake, which
  address the program, so the transfer is unattended for every session the
  launcher started.
- **The one-act fallback.** Where the holder is the operator's own
  session, the harness cannot move the operator's terminal to a launched
  successor, so a handover launch over it is refused (`launch --handover`
  exits 4): the
  handover is offered on the panel as one operator act (one command opening
  a fresh session that runs the mission-control command with the program
  name), which runs as the resume. This is the D-30 fallback, never a degraded session.
- **Tests.** Each guarded behaviour in the shell suite was checked to fail
  under a mutation of it before it was trusted.

Sources: `claude --help` (2.1.312, `-n/--name`, `-r/--resume`); Claude Code
sessions documentation, <https://code.claude.com/docs/en/sessions>; public
reports such as <https://github.com/anthropics/claude-code/issues/26249>.

### Execution research: Task 10 (2026-10-28, after sign-off)

Recorded during Task 10's execution, as the records above were; it changes
no decision and is not part of the signed section.

Scoping: one version-sensitive API (the forge's review-thread GraphQL
shape, read the way the Task 5 adapter reads its fields) and several
security-touching patterns (git reads over branch names, a command named by
a knob, a guard fed a synthetic payload); no new dependency, so a short pass
of local probes.

- **Readiness from primary evidence.** The collector reads each check
  context on its own, never the rollup, so a red context under a green
  rollup fails the walk; a thread opened by a bot is a finding, answered
  once resolved or replied to by a person other than the pull request's
  author, whose own sessions post under that login. A finding written only in a
  review body is not read: its answered state has no general marker, so the
  walk leaves it to the reviewer duty a follow-on bundle owns.
- **The guard composed, not reimplemented.** The ready-flip floor is
  `scripts/ready-guard.sh`, fed the flip it would refuse as data;
  `ready-flip.sh evaluate` is not called, since its reconcile can commit and
  push, and mission control writes no repository.
- **Gate conditions.** A per-program file in the program home, refused
  whole when any line would authorize a merge or ask for a flip the
  configured policy does not allow; nothing evaluates from a refused file.
- **Branch names and commands.** Branch and ref names are checked against a
  conservative grammar (no leading dash, no `..`) before any git call; the
  clipboard command is `auto` or an absolute path, run with the draft on
  stdin and never through a shell.
- **A worker's git configuration.** Every git read mission control makes in
  a worker-written checkout (the packet's log, the step records a walk
  collects) or over worker-pushed branches (the radar's diffs) runs with
  fsmonitor, hooks, signature display and lazy fetching off, and no
  inherited repository selector, through the environment, which outranks the
  checkout's own configuration: a probe showed a partial-clone checkout otherwise runs its
  ssh command on a missing commit. The clipboard command is never read from
  the repo-tracked layer.
- **The duty catalog's list form.** The session-keeper's triggers do not
  fit the line-length lint on one line, and the reader took only one-line
  lists. The catalog grammar (D-3's API surface, a low-stake additive call)
  now lets a flow list wrap onto deeper-indented lines, joined by both the
  merge path and the duties reader; a one-line list reads as before.

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

## 9. Amendment log

### Amendment 1 — 2026-11-02 (delta kickoff: D-18 names the adopter layer)

**Trigger.** Task 11 (PR #796) found that D-18 remembers the guidance level
in the machine-local configuration layer, but that file sits inside a
repository checkout, where mission control writes no file (REQ-A1.3). The
branch writes the adopter layer instead, the per-operator home REQ-F1.13's
test entry already describes. Operator ruling, 2026-11-02: amend D-18.

**Delta walked.** D-18's decision text names the adopter layer, with a dated
amendment note; the changelog records it. No requirement, task or test
entry changes.

**Lens review (delta-scoped).** Spec lens set, walked inline over the
one-sentence delta; no fan-out, scoped by size.

| Lens | Findings | Notes |
| --- | --- | --- |
| Contract correctness and internal consistency | 0 | D-18 now agrees with REQ-A1.3 and REQ-F1.13's test entry |
| Ambiguity and interpretation forks | 0 | None |
| Citation and coverage integrity | 0 | None |
| Dead verification paths | 0 | REQ-F1.13's test already checks per-operator memory |
| Decision-domain gaps | 0 | None |
| Testability | 0 | None |
| Cross-file consistency | 0 | The 2026-10-24 changelog line naming the machine-local layer is history and stays |
| Documentation and glossary drift | 0 | None |
| Rendered-content safety and data hygiene | 0 | None |

#### Sign-off record (Amendment 1)

Signed off 2026-11-02 by the operator after the approval summary, relayed
through the fleet tower, as a delta re-walkthrough of an Active (derived)
bundle: no status flip; `Last reviewed:` bumped on design.md and
requirements.md; `scripts/spec-validate.sh` re-run after the edits with 0
errors and 0 warnings.

Class: meaning
Lens-pass: Amendment 1, delta-scoped lens review above (spec lens set, inline; no findings)
Anchor: `e6d636fd93c1e03830386d789bc8265230e25dd4` — computed as
`scripts/spec-anchor.sh specs/mission-control`

### Amendment 2 — 2026-11-04 (reopened delta kickoff: works smoothly for every operator)

Spec path `specs/mission-control`; walk started at `ada9ebd9` (the
extension commit on `planwright/mission-control/spec`, off `cbb15897`);
walkthrough date 2026-11-04; validator at walk start: 0 errors, 0
warnings. Mode: reopened-bundle delta kickoff. Every task had merged, so the
bundle derived Done; the operator's amendment request (relayed by mission
control) was routed through `/spec-draft --extend`, which reopened the
stored Ready to Draft, and this walk covers that extension delta only.
Every question was the operator's, asked through mission control's relay
and answered in their own words.

#### Goal and glossary (delta)

Restatement: mission control should work for any operator. What it shows
runs; what it starts is supervised, verified and finished up to the human
gates with no manual step; the guidance level decides how much it explains
when the operator is about to merge or a pull request is about to flip
ready, never whether a gate holds. Rules out: new gates, mission control
merging or pushing itself, audit items 8 to 11 (routed to separate
flights). Assumes the cadence fix already in flight lands as Task 17.

Terms: *consequential moment* (a merge recommendation, a ready flip mission
control requests or offers, a stated intent to merge); *configured
cadence* (every step the configuration requires at the in-run points),
distinct from a *cadence step* (a steps-catalog entry gating later units);
*adopt* (register a live session mission control did not launch); *tower
handover* (taking over a tower's fleet), distinct from Task 16's name
takeover; *attended session* (the operator typed the skill command in their
own terminal) versus a *launched holder*; *activation record* (the
per-session file that turns the panel on).

Signed off: 2026-11-04

#### Requirements walkthrough (delta)

The new and superseding requirements are the ones the 2026-11-04 Changelog
entry in `requirements.md` lists, in seven themes: tower handover with
adoption and prompt waking; launches that finish on their own (worktrees,
cadence in briefs, the kickoff push); verification (the cadence audit at
readiness and its result at consequential moments); the posture check; the
panel with no setup; what is shown works (armed duties, timeouts,
suggestions); the platform class and dynamic host-shared admission. The
operator's attended-compaction decision (folded in before sign-off) added
REQ-L1.8 superseding REQ-L1.3. A program the launch environment names now
counts as the skill's argument (REQ-A1.7 note). Spec edits: the
extension commit plus the lens-pass revision, both in this branch's diff.

Signed off: 2026-11-04

#### Design walkthrough (delta)

D-31 to D-42 are new; D-8, D-10, D-11, D-17, D-18, D-22, D-25, D-28, D-29
and D-30 carry dated amendment notes pointing at them, bodies unchanged;
every other decision is confirmed as signed. Defaults the operator
accepted: lesson texts are core data, not an overlay catalog (D-1's single
extension point stands); `expert` gets the one-line result alone; a tower
is retired only on the operator's yes and stops supervising adopted
sessions at adoption; a tmux prompt is surfaced once and takes only the
operator's own answer, typed by the pane relay; the kickoff push waits on a
routed human-gates amendment (Task 31); `fleet_max_parallel_units` becomes
the host-wide ceiling; new stores carry a `format` field. Re-signed after
the lens pass with those changes, and D-42 (attended sessions compact,
launched holders hand over; the nuance-loss trade-off named) signed on its
own.

Signed off: 2026-11-04 (re-signed after the lens pass)

#### Verification approach (delta)

Every new requirement has a `[test]` entry run by planwright's CI
(`scripts/run-tests.sh` discovers `tests/*.sh`; the panel through
`check:panel-mod`). No `[Gherkin]` or `[manual]` entry was added: a
Gherkin arm without its eval persona fails `tests/test-mc-eval-cadence.sh`
in CI, so the behaviours that live in skill prose were moved into scripts
(the posture script, the activation-record verb, the packet's lesson data)
where a shell test reaches them. Test files a task creates are named in
its deliverables (`tests/test-mc-packet.sh`, the posture script's test);
`tests/test-step-run-audit.sh` exists on the in-flight branch.

Signed off: 2026-11-04

#### Task graph (delta)

Reconstructed from the `Dependencies:` lines (`scripts/spec-graph.sh
specs/mission-control`). Tasks 17, 18, 20, 23, 25, 26, 27, 28, 30, 31 and
32 have no unmet edge and can start at once. Chains: 18 and 31 before 19;
20 then 21, and 21 and 32 before 22; 17 before 24; Task 29 last. The
effort-weighted critical path runs 20, 21, 22, 29. Deliberate non-edges:
28 does not wait on 18 (admission is independent of worktrees); 24 does not
wait on 23 (the cadence line does not need the panel); 30 does not wait on
16's successor work, which already landed.

Signed off: 2026-11-04

#### Risk register (delta)

1. Task 17 is delivered by the in-flight flight; unless its pull request
   carries Task 17's trailer, the derivation will not count it.
   Mitigation: mission control routes that flight as Task 17.
2. The skill's instruction budget is saturated; Task 29's prose may not
   fit. Mitigation: behaviour lives in scripts and core data with pointers;
   the budget check blocks the merge otherwise.
3. The kickoff profile widens one session's push. Mitigation: the guard
   reads the branch from a launch record the session cannot write; every
   other push form is tested denied; Task 31 must land first.
4. The host-level admission store could jam or go stale. Mitigation: one
   lock, recounts from the registries, dead-holder and timeout reclaim.
5. Adoption could contend with a live tower. Mitigation: supervision moves
   at adoption, the tower's paths skip supervised sessions, retirement
   waits for a yes.
6. The platform-currency draft's Task 4 waits on this merge, and its text
   still cites REQ-H1.4; it should move to REQ-H1.5 when next touched.
7. Accepted at the lens pass: D-18, D-25, D-29 and D-30 change by dated
   notes, not supersession; only mission control's launcher reserves
   admission slots (others are seen through registries and load); a merge
   done directly on the forge cannot trigger the cadence notice.
8. Attended compaction can lose conversational nuance a successor would
   keep (D-42); the self-check covers rules and state only. Accepted by the
   operator.

Decision-domain gap check (catalog via `scripts/resolve-catalog.sh
decision-domains`): one gap at the walk (store versioning), closed in D-37
and D-41; the lens pass's domain findings were applied (D-28's note lists
where each is decided).

Signed off: 2026-11-04

#### Lens review (delta-scoped)

Spec lens set (`doctrine/artifact-lenses.md`), fanned out: one read-only
reviewer per lens over the extension diff, then validated and merged here.
Findings were heavily duplicated across lenses; counts are as each reviewer
reported them.

| Lens | Findings | Disposition |
| --- | --- | --- |
| Contract correctness and internal consistency | 19 | Applied (prompt-answer arm, per-verb allow list, worktree creation as launching, the floor wording, step staleness, budget ceilings, tower handover suspension, liveness, packet order, extension point) |
| Ambiguity and interpretation forks | 40 | Applied (audit point and head, kinds listed, branch reuse, admission thresholds and units, tower handover outcomes); the direct-forge merge limit accepted |
| Citation and coverage integrity | 15 | Applied (audit items spelled out, citations added, obs:855b725a re-cited in D-37, changelog completed); D-25/D-18 by note accepted |
| Dead verification paths | 13 | Applied (Gherkin tags removed, posture and activation as scripts, guide check owned by Task 26, memory override, timeout scale) |
| Decision-domain gaps | 26 | Applied (store homes and classes, reclaim, burst counting, adopt and answer contracts, wake marker, session id, mod detection, kickoff record tamper, posture targets, D-28 note); every-launcher admission accepted as a limit |
| Testability | 66 | Applied (every Done-when rewritten with observables and refusal cases) |
| Cross-file consistency | 19 | Applied (human-gates and tower-comms routed as Tasks 31 and 32, D-35 composes the claim channel, knob meaning rewritten, doctrine updates in Tasks 25 and 29, sweep identity) |
| Documentation and glossary drift | 17 | Applied (timeout, tower handover, audit item, H1.4 pointers, D-10/D-11/D-17/D-22 notes, overlays row made moot by core lesson data) |
| Rendered-content safety and data hygiene | 0 | Not a rendered context; committed text checked for names, hosts and paths, none found |

Altitude check: no altitude trigger in the delta (no new pinned claim; D-31
keeps D-1's extension point): not applicable. Ship-gate check: the
out-of-band fixes named are the cadence flight (gated as Task 17) and audit
items 8 to 11 (each on its own flight branch); no fix is named in prose
only. Every finding is dispositioned with the operator (2026-11-04).

#### Pre-flip verification (Amendment 2)

`mise run lint:md`'s markdownlint over the four spec files and this brief:
clean. `scripts/check-memory-links.sh`: clean. `scripts/spec-validate.sh
specs/mission-control`: 0 errors, 0 warnings. The post-lens stale-reference
sweep found only historical mentions of REQ-H1.4 (completed task citations,
dated changelog lines, the D-8 text under its note). Enumerations in the
delta are explicit lists, not counts of an outside surface; the source
figures this brief cites are named by file.

#### Sign-off record (Amendment 2)

Signed off 2026-11-04 by the operator after the approval summary, relayed
through mission control, as a reopened-bundle delta kickoff: stored status
flipped Draft to Ready on all four spec files, `Last reviewed:` 2026-11-04
on all four; `scripts/spec-validate.sh` re-run after the flip with 0
errors and 0 warnings. The delta adds requirements and decisions, so it is
meaning-class.

Class: meaning
Lens-pass: Amendment 2, delta-scoped lens review above (spec lens set, fanned out; every finding dispositioned)
Anchor: `f7a8780cef5cf4ce13a5299a78a7e4a81ac927c1` — computed as
`scripts/spec-anchor.sh specs/mission-control`

### Re-anchor — REQ-G1.5 test-spec pointer (2026-11-05)

Marked self-re-anchor for an expression-only edit, machine-written per the
meta-spec's expression-only lane (`doctrine/spec-format.md`, *Writers*).
The REQ-G1.5 entry in `test-spec.md` now names
`tests/test-policy-guard-mission-control.sh` for the edit and git-mutation
denials, the suite that pins them; the command-guard suite keeps the
pre-approval arms. No requirement or decision changes meaning. The operator
chose "Fix it (Recommended)" for this pointer, relayed by mission control.
`Last reviewed:` moves on `test-spec.md` and `requirements.md`.

**Cites the changelog line:** the 2026-11-05 `## Changelog` entry in
`requirements.md`.

Class: expression-only
Anchor: `260b43f423d8d49d039bc9f318b31702f8daba2d` — computed as
`scripts/spec-anchor.sh specs/mission-control`

### Amendment 3 — 2026-11-07 (amendment: every session hands over, compaction last)

Header: spec `specs/mission-control`, Active (derived), walked at spec
commit `b2aee10d`; validator at pre-flight 0 errors, 0 warnings. Declared
by the operator (2026-11-06, relayed by the hub mission control), scoped to
D-42. Walked as a delta, every question relayed through mission control
and answered in the operator's own words.

#### Goal and glossary (Amendment 3)

The amendment reverses D-42: an attended session no longer just compacts.
It hands over as best it can and compacts only as a last resort. It rules
out building any remote-access surface and any terminal configuration
change. It assumes the host's own compaction stays as the safety net.

- **Handover ladder**: an attended session's three rungs at its trigger:
  a pane beside itself, then one operator act, then the host's compaction.
  Distinct from D-17's degradation ladder.
- **Pane adapter**: a launcher `pane` rung's per-terminal unit that probes
  for and opens a split beside the session. Distinct from a snapshot
  source's *adapter*.
- **Attended session** now also covers a session that took the name in a
  pane beside an attended predecessor.

Signed off: 2026-11-07

#### Requirements walkthrough (Amendment 3)

REQ-L1.9 supersedes REQ-L1.8: every session hands over, attended sessions
down the handover ladder, and the shipped context trigger is 40 percent.
Amendment notes go on REQ-A1.4 (a pane successor is not a handed pane),
REQ-L1.5, REQ-L1.6 and the Out of scope remote-access line. Operator
answers:

- Q1, the ladder: "Maybe do out best effort to emulate what we do with
  tmux in whatever tool we are in at the moment, some terminals allow
  tmux-like commands". This became best-effort pane adapters beyond tmux.
- Q2, the default: "It's fine as a default but is there a good way to find
  a good default?". The answer given: derive it from the measured
  cost-per-turn curve and re-check it weekly and on drift, as a follow-on
  (observation recorded).
- After sign-off: only the hub keeps Remote Control, and a successor keeps
  it only when its predecessor had it.

Signed off: 2026-11-07

#### Design walkthrough (Amendment 3)

- D-42 is superseded by D-43.
- D-29 and D-30 are confirmed with amendment notes; they govern attended
  sessions again through D-43.
- D-28 gains a note naming D-43 for context handling and the domains it
  decides.
- Every other D-ID is unchanged.

Signed off: 2026-11-07

#### Verification approach (Amendment 3)

REQ-L1.9 is `[test + manual]`:

- **`[test]`:** the handover and panel suites plus the mod's
  `compaction.test.tsx` under `check:panel-mod`, run by CI, against a stub
  tmux extended with `split-window` and `kill-pane`.
- **`[manual]`:** one real-terminal run per non-tmux adapter, swept by the
  operator or the executing worker on a host with that terminal. An
  adapter not run ships stub-verified only.
- **REQ-L1.8:** its entry stays, marked superseded.

Signed off: 2026-11-07

#### Task graph (Amendment 3)

- Task 33 supersedes Task 30 (parked under Out of scope), with no task
  dependencies.
- Task 29 now depends on 33 instead of 30.
- PR #874 (the predecessor's self-exit) is a deliberate non-edge. Task 33
  reuses it when it has landed and builds it otherwise, so neither waits on
  the other.

Signed off: 2026-11-07

#### Risk register (Amendment 3)

1. **Handover rate and cost.** The 40 percent default roughly doubles the
   handover rate for launched holders and starts handovers in attended
   sessions; per-handover cost is unmeasured. Mitigation: the knob is
   overridable per machine; the follow-on derives the default from
   measured cost. Early signal: the throughput duty's cost-per-turn curve.
2. **Terminal control channels execute code.** Mitigation: probes are
   read-only, local and owned by the session's user; commands are argument
   vectors from launcher-grammar values; no adapter enables a channel.
   Early signal: the metacharacter refusal fixture.
3. **Non-tmux adapters may not work on real terminals.** Mitigation: the
   `[manual]` runs, and the ladder falls to the one operator act when a
   pane fails. Early signal: the rung-1 fall panel event.
4. **The successor's permission profile.** The successor runs the shipped mission-control profile in auto mode, which can be looser than the operator's own session; the operator chose it after the review pass (2026-11-07), so a successor never stalls on its own prompts.
5. **Decision-domain gap check.** Walked over the delta in the lens pass.
   Auth, concurrency, failure modes, cost, migration, API surface and
   observability are decided in D-43 or recorded above. Migration: an
   adopter's own override of the context knob keeps its value; the
   implementing PR marks the attended-behaviour change as breaking in its
   title.

Signed off: 2026-11-07

#### Lens review (Amendment 3, delta-scoped)

Spec lens set (`doctrine/artifact-lenses.md`), fanned out in four read-only
reviewers, each covering a group of lenses over the amendment diff, then
validated against the files and merged. Findings overlapped heavily across
reviewers; counts are as each reported.

| Lens group | Findings | Disposition |
| --- | --- | --- |
| Contract correctness, cross-file consistency | 14 | Applied: holder kind with a registry row, who closes which pane, the pane rung in the launcher's backend seam, REQ-A1.4 and Out of scope notes, profile named, mod and options-reference rows and `--help` text in Task 33, doctrine sentence on resume, REQ-L1.6 degraded-session clause, once per session, launcher-derived name |
| Ambiguity, glossary drift | 16 | Applied: which name, Remote Control (operator ruling), attended definition widened, own-window split on this host, adapter order by first passing probe, read-only probe, fall-through on any rung-1 failure, unverified successor closed, deferral scope, launched holder at 40, handover ladder and pane adapter named |
| Citation, dead paths, testability | 15 | Applied: Out of scope note, D-28 note, observations cited and consumed, Sources dated both days, stub tmux and runner deliverables, stub-verified adapters plus `[manual]`, mod suite named, Done-when tied to the test-spec entry, Task 16 fixtures retargeted. Declined: dropping REQ-L1.8's superseded marker (spec-format is silent and the marker aids lineage). Outside scope: the status renderer's multibyte cut, recorded as an observation |
| Decision-domain gaps, security | 20 | Applied: D-28 walk, Remote Control inherited, profile (to the operator), user-owned local channel only, own pane identity targeted, no act after the handover file, deferral only while rung 1 is in flight, stray pane closed, end at idle prompt with one line, cost and migration risk rows, follow-on recorded, rung and adapter recorded, argument-vector commands, metacharacter refusal fixture. Declined: an opt-out knob for rung 1 (the operator approved the ladder as the default; the context knob delays it) and a reserved-windows knob (the split lands in the session's own window) |
| Rendered-content safety, data hygiene | 0 | Not a rendered context; committed text checked for names, hosts and paths, none found |

Altitude check: no altitude trigger in the delta (no new pinned claim): not
applicable. Ship-gate check: the one out-of-band fix named, PR #874, is
owned by Task 33's deliverable, not named in prose only.

Signed off: 2026-11-07

#### Pre-flip verification (Amendment 3)

`markdownlint-cli2` over the four spec files, this brief and the new
observation fragments: clean. `scripts/check-memory-links.sh`: clean.
`scripts/spec-validate.sh specs/mission-control`: 0 errors, 0 warnings. The
post-lens stale-reference sweep over the bundle found D-42, REQ-L1.8 and
Task 30 only in their own superseded records, dated amendment notes, the
changelog and Sources. The lens counts above are as each reviewer reported
them, not derived figures; the delta's enumerations are explicit lists.

#### Sign-off record (Amendment 3)

Signed off 2026-11-07 by the operator, relayed through the hub mission
control: the approval summary was answered "A. Sign off (Recommended)",
and the one review point touching what was approved, the successor's
permission profile, was answered "A. Mission-control profile
(Recommended)". The Remote Control ruling came after sign-off. Amendment on
an Active bundle: no status flip; `Last reviewed:` 2026-11-07 on all four
spec files; validator re-run with 0 errors and 0 warnings. The delta
supersedes a requirement and a decision, so it is meaning-class.

Class: meaning
Lens-pass: Amendment 3, delta-scoped lens review above (spec lens set, fanned out in four groups; every finding dispositioned)
Anchor: `bfed68e37ea8beb929c153a50684d05a850ae5ce` — computed as
`scripts/spec-anchor.sh specs/mission-control`

### Amendment 4 — 2026-11-07 (amendment: specs kept true to what ships, goals checked by outcome)

Spec path `specs/mission-control`; walk started at `04303aa3` and
re-based by a merge of `f2118b6d` (Amendment 3, PR #879) before the lens
pass; walkthrough date 2026-11-07; validator at walk start: 0 errors, 0
warnings. Mode: amendment on an Active (derived) bundle, operator-declared
through mission control. Every question was the operator's, relayed by
mission control and answered in their own words; the read-only spec-drift
audit was used as evidence only.

#### Goal and glossary (Amendment 4)

Restatement: a spec must keep saying what ships, and a goal must be
called done only when its outcome is proven. A pull request that changes
behaviour a spec describes carries that spec's edit and the operator's
signed-off amendment before it is ready, and security, CI and guard work
goes through the spec pipeline unless the operator overrides it in their
own words. A program goal carries a check of its outcome, and merged pull
requests never count as that check. Rules out: amending the seven other
bundles the audit names (recorded as an observation for their own
amendments). Assumes the tower-front-door bundle is reopened for its part,
which the operator approved.

Terms: *covering-spec statement* (the pull request body's `Covering
spec:` line and its `Not covered: <path> — <reason>` lines, D-45);
*spec-drift check* (`scripts/spec-drift-check.sh`, the mechanical
backstop); *edited spec* (its anchored content changed, so status
annotations alone do not count); *goal* (a program-home record of an
outcome, the work it tracks and its check); *done-when check* (a goal's
outcome check, distinct from a task's `Done when:` field); *merged but not
done* (a goal whose tracked work merged while its check fails or has not
run).

Signed off: 2026-11-07

#### Requirements walkthrough (Amendment 4)

The operator's decisions, in order: a change to specified behaviour edits
the spec in the same pull request and waits for a relayed sign-off (Q1,
option A); detection by the worker's statement plus a mechanical check
(Q2, A); routing by a shipped path list plus judgment, the override
recorded (Q3, A, after the operator asked for the question reframed around
staying unnoticed day to day); guard and hook scripts do not join the
polish pause zones (Q4, A); mission control drafts each goal's check and
the operator confirms it (Q5, A); command checks re-run daily and at
bring-up, session checks not re-run (Q6, A); the drafted change confirmed
(Q7, A); the audit's mission-control drift folded into this amendment (Q8,
A). New and superseding requirements: REQ-D1.13, REQ-D1.14 (supersedes
REQ-D1.9), REQ-N1.1 to REQ-N1.4, two Scope bullets; amendment notes on
REQ-B1.5 and REQ-F1.12. The 2026-11-07 Amendment 4 Changelog entry in
`requirements.md` lists them.

Signed off: 2026-11-07

#### Design walkthrough (Amendment 4)

D-44 (goals done on their own check) and D-45 (a signed spec edit rides
the pull request; the statement's form and the check are this bundle's,
the router rules routed) are new. Dated notes: D-14 (the denial repeat),
D-18 (the first run asks only what the operator can answer), D-22 (the
routed tower-front-door amendment), D-32 (launched sessions in auto mode),
D-33 (the spec-only hold). Every other decision is confirmed as signed.

Signed off: 2026-11-07

#### Verification approach (Amendment 4)

Every new requirement has a `[test]` entry planwright's CI runs
(`scripts/run-tests.sh` discovers `tests/*.sh`): `tests/test-mc-goals.sh`
and `tests/test-spec-drift-check.sh` are created by Tasks 34 and 35;
`tests/test-mc-readiness.sh` and `tests/test-mc-duties.sh` exist. The
drift folded in is already covered by shipped tests, named in each entry:
the spec-only hold in `tests/test-mc-readiness.sh`, the denial repeat in
`tests/test-mc-proposals.sh`, the first-run asked-or-settled grade in
`tests/test-behavioral-eval-mission-control.sh`. No `[Gherkin]` or
`[manual]` entry was added.

Signed off: 2026-11-07

#### Task graph (Amendment 4)

Tasks 34, 35 and 36 have no unmet edge and can start at once; Task 37
follows 34 and 35. Cross-bundle edge: the tower-front-door task that has
flights run the drift check at `pre-pr` depends on Task 35, which ships
the script and owns the statement's form. Deliberate non-edges: Task 36
does not wait on Task 35 (it is the routed kickoff, which needs no
script); Task 35 does not wait on Task 36 (a pull request with no
statement is checked as covering nothing). Task 17 already derives
completed; Task 19 carries a note on its landed push half; Task 30 is
superseded by Task 33 (Amendment 3), so its partial landing in PR #848 is
not recorded here.

Signed off: 2026-11-07

#### Risk register (Amendment 4)

1. Until the tower-front-door part lands, flight pull requests carry no
   covering-spec statement, so the drift check flags every changed listed
   deliverable and readiness refuses more often at first. Mitigation: a
   one-line `Not covered:` reason clears a harmless change; mission
   control's launch briefs can ask for the statement before Task 36 lands.
2. A harmless edit to a listed file needs a written reason (the operator
   accepted this at Q2).
3. Session-based goal checks are not re-run, so such an outcome can break
   quietly (accepted at Q6).
4. The relayed kickoff that signs a flight's spec edit runs on the flight's
   own branch and pushes it as that branch's commit; a guard that treats a
   kickoff-kind session as allowed only its spec branch would refuse it.
   Mitigation: mission control launches that kickoff as it launched this
   one, as a session on the flight's branch.
5. A check command runs as the operator confirmed it; a wrongly confirmed
   command that changes something would still run. Mitigation: mission
   control drafts only commands that change nothing and shows the command
   verbatim before confirmation.
6. The skill's instruction budget is saturated; Task 37's prose may not
   fit. Mitigation: mechanics live in the scripts with pointers; the budget
   check blocks the merge otherwise.

Decision-domain gap check (catalog via `scripts/resolve-catalog.sh
decision-domains`): data-storage, concurrency, secrets-config,
observability, versioning-scheme and existing-seam-reuse touched; each
decided in D-44, D-45 or REQ-N1.4 after the lens pass (the goal store's
work link, single writer, lock and `format` field; the watcher timeout
reused; deliverables read through `scripts/spec-model.sh`).

Signed off: 2026-11-07

#### Lens review (Amendment 4, delta-scoped)

Spec lens set (`doctrine/artifact-lenses.md`), fanned out: one read-only
reviewer per lens over the delta, then validated and merged here. Findings
overlapped heavily across lenses; counts are as each reviewer reported
them.

| Lens | Findings | Disposition |
| --- | --- | --- |
| Contract correctness and internal consistency | 4 | Applied: task pull requests delivering their own task's files are exempt; the sign-off kickoff runs on the pull request's branch (D-45); the statement's form owned here so Tasks 35 and 36 need no edge; the misfiled test entry moved |
| Ambiguity and interpretation forks | 4 | Applied: "edited" means anchored content; the statement's form and per-path reasons; goals name their tracked work; a session check passes only on evidence the outcome holds |
| Citation and coverage integrity | 2 | Applied: Task 35 cites REQ-D1.14; the misfiled test entry moved |
| Dead verification paths | 2 | Applied: the statement's form defined; the goal's work link added |
| Decision-domain gaps | 4 | Applied: the work link, the single writer under a lock, D-40's watcher timeout reused, deliverables read through `scripts/spec-model.sh` with backticked paths |
| Testability | 6 | Applied: the work link, the `format` refusal, bring-up, session no-re-run and lock cases, a falsifiable metacharacter case, Task 19's remaining clauses named, the statement cases |
| Cross-file consistency | 3 | Applied: the misfiled entry, the Task 35/36 ordering, the work link |
| Documentation and glossary drift | 5 | Applied: the entry moved, a `## REQ-N` heading in the test spec, `unconfirmed` used throughout, *done-when check* in the glossary above, the D-22 note in the changelog |
| Rendered-content safety and data hygiene | 0 | Not a rendered context; committed text checked for names, hosts and paths, none found |

Altitude check: no altitude trigger in the delta (no new pinned seed
claim): not applicable. Ship-gate check: the out-of-band fixes named are
the tower-front-door amendment (gated as Task 36) and the seven other
bundles' drift (recorded as observation fragment
`2026-11-07-flight-spec-drift-other-bundles`); none is named in prose
only. Every finding is dispositioned with the operator at the approval
summary.

Signed off: 2026-11-07

#### Pre-flip verification (Amendment 4)

`markdownlint-cli2` over the four spec files and this brief: clean.
`scripts/check-memory-links.sh`: clean. `scripts/spec-validate.sh
specs/mission-control`: 0 errors, 1 warning (REQ-D1.11 changed while its
test entry did not; the change is a pointer note naming REQ-D1.14 as the
backstop, so its verification path is unchanged). The post-lens
stale-reference sweep found REQ-D1.9 live only in REQ-D1.11's pointer
(noted to REQ-D1.14); the rest are its own superseded record and test
entry, completed Task 17's citations, and dated changelog lines. The lens
counts above are as each reviewer reported them, not derived figures; the
delta's enumerations are explicit lists.

#### Sign-off record (Amendment 4)

Signed off 2026-11-08 by the operator, relayed through the hub mission
control: the approval summary was answered "A: sign off (Recommended)".
Amendment on an Active bundle: no status flip; `Last reviewed:` 2026-11-08
on all four spec files; validator re-run with 0 errors. The delta adds
requirements and decisions and supersedes REQ-D1.9, so it is
meaning-class.

Class: meaning
Lens-pass: Amendment 4, delta-scoped lens review above (spec lens set, fanned out one reviewer per lens; every finding dispositioned)
Anchor: `9a3b0b7da88c8cc8fcd05c77ea4f981e4c3b0a34` — computed as
`scripts/spec-anchor.sh specs/mission-control`

### Re-anchor — main's Amendment 3 merged with the REQ-G1.5 test-spec pointer (2026-11-07)

Marked self-re-anchor for an expression-only edit, machine-written per the
meta-spec's expression-only lane (`doctrine/spec-format.md`, *Writers*).
Merging main into the branch that carries the 2026-11-05 test-spec pointer
re-anchor combines that edit with Amendment 3. Against Amendment 3's
anchored content, the merged bundle differs only by that pointer edit, so
no requirement or decision changes meaning; this entry records the combined
anchor.

**Cites the changelog line:** the 2026-11-05 `## Changelog` entry in
`requirements.md`.

Class: expression-only
Anchor: `1b8a5bff791edb063bcd323ca27f40da593dccbd` — computed as
`scripts/spec-anchor.sh specs/mission-control`

### Re-anchor — main's pointer re-anchor merged with Amendment 4 (2026-11-08)

Marked self-re-anchor for an expression-only edit, machine-written per the
meta-spec's expression-only lane (`doctrine/spec-format.md`, *Writers*).
Merging main into the branch that carries Amendment 4 combines Amendment 4
with the REQ-G1.5 test-spec pointer edit recorded in the entry above.
Against Amendment 4's anchored content, the merged bundle differs only by
that pointer edit, so no requirement or decision changes meaning; this
entry records the combined anchor.

**Cites the changelog line:** the 2026-11-05 `## Changelog` entry in
`requirements.md`.

Class: expression-only
Anchor: `47b4f81e088a268569c6ecb2583d751c68e549df` — computed as
`scripts/spec-anchor.sh specs/mission-control`

### Amendment 5 — 2026-11-08 (amendment: the plugin hook approves mission control's prompt-answer calls)

Spec path `specs/mission-control`; walk started at `358cd50e`; walkthrough
date 2026-11-08; validator at walk start: 0 errors, 0 warnings. Mode:
amendment on an Active (derived) bundle, operator-declared through mission
control, walked as a delta of the dated 2026-11-08 notes on REQ-G1.6 and
D-35 only. Every question was the operator's, relayed by mission control
and answered in their own words.

#### Goal and glossary (Amendment 5)

Restatement: approvals of mission control's `fleet-streamjson.sh pending`
and `answer` calls must survive every planwright release, so the plugin's
own hook approves those exact calls instead of a settings rule that names
one version's install path. Rules out: widening what authorizes an answer,
adding the raw answer verb to the guard tier's list, and changing the
exact-path rule for settings allow rules. Terms: *exact shape* (the literal
resolved installed-root path, one simple command, no expansion, compound,
pipe, redirection, background marker or symlink out of the root);
*mission-control session* (one the plugin's prompt hook marked, in the
tower-session mark store).

Signed off: 2026-11-08

#### Requirements walkthrough (Amendment 5)

Q1, the amendment's open point: what backs a hook-approved answer. The
operator answered "Your rule or reply (Recommended)": a standing decision
covering the prompt, claimed through the answer channel, or the operator's
own answer to it, as before; never mission control's own judgment. The
REQ-G1.6 note now says so and reads "never through the raw answer verb" as
never on mission control's own judgment, which resolves the conflict with
the hook approving that verb's call. A changelog entry (Amendment 5) was
added.

Signed off: 2026-11-08

#### Design walkthrough (Amendment 5)

D-35's note records the same settlement, the session test reusing the
plugin's prompt-hook marking, and the observation that this mark now lets a
call through rather than only denying, so the hook also requires the call
to name the installed root it runs from. Every other decision is confirmed
as signed.

Signed off: 2026-11-08

#### Verification approach (Amendment 5)

A new `[test]` paragraph under REQ-G1.6 names `tests/test-mc-approve-hook.sh`
(created by Task 38), run by planwright's CI through `scripts/run-tests.sh`.
No `[Gherkin]` or `[manual]` entry was added.

Signed off: 2026-11-08

#### Task graph (Amendment 5)

Task 38 (the hook, the mark and the skill pointer) depends on Task 21,
which ships the answer channel and the stall test the new entry sits
beside. Deliberate non-edge: Task 38 does not wait on Tasks 34 to 37.

Signed off: 2026-11-08

#### Risk register (Amendment 5)

1. The mission-control mark becomes an approval input, not only a
   restriction, so a wrongly marked session could run these two calls
   without a prompt. Mitigation: the exact shape and the unchanged
   authorization of every answer; the test covers an unmarked session.
2. How a hook's approval interacts with a settings deny or ask rule is
   the harness's behaviour, not this bundle's. Early signal: Task 38's
   tests confirm a deny rule still wins before the hook ships.
3. Until Task 38 lands, approvals keep breaking on each release.

Decision-domain gap check (catalog via `scripts/resolve-catalog.sh
decision-domains`): security-posture and existing-seam-reuse touched, both
decided in the notes (exact shape, authorization unchanged; the mark store
reused).

Signed off: 2026-11-08

#### Lens review (Amendment 5, delta-scoped)

Small, narrow delta walked inline per `kickoff-verification`.

| Lens | Findings | Disposition |
| --- | --- | --- |
| Contract correctness and internal consistency | 1 | Applied: "never through the raw answer verb" reread as never on mission control's own judgment |
| Ambiguity and interpretation forks | 1 | Applied: how a mission-control session is identified |
| Citation and coverage integrity | 1 | Applied: Task 38 carries the implementation |
| Dead verification paths | 1 | Applied: the REQ-G1.6 test paragraph |
| Decision-domain gaps | 1 | Applied: the mark's new trust weight (D-35 note, risk 1) |
| Testability | 0 | Covered by the new test paragraph |
| Cross-file consistency | 1 | Applied: the changelog entry |
| Documentation and glossary drift | 0 | None |
| Rendered-content safety and data hygiene | 0 | Not a rendered context; no names, hosts or secrets |

Altitude check: no new pinned seed claim, not applicable. Ship-gate check:
the implementation is gated as Task 38, not named in prose only.

Signed off: 2026-11-08

#### Pre-flip verification (Amendment 5)

`markdownlint-cli2` over the four spec files and this brief: clean.
`scripts/spec-validate.sh specs/mission-control`: 0 errors, 0 warnings. The
lens counts above are this walk's own; the delta's enumerations are
explicit lists.

#### Sign-off record (Amendment 5)

Signed off 2026-11-08 by the operator, relayed through mission control:
the approval summary was answered "Sign off (Recommended)". Amendment on an
Active bundle: no status flip; `Last reviewed:` already 2026-11-08 on all
four spec files; validator re-run with 0 errors. The delta settles what
authorizes an answer and adds a task, so it is meaning-class.

Class: meaning
Lens-pass: Amendment 5, delta-scoped lens review above (spec lens set, walked inline; every finding dispositioned)
Anchor: `39b49a22e3449a1308da884674343e2adce89a58` — computed as
`scripts/spec-anchor.sh specs/mission-control`

### Amendment 6 (2026-11-09, amendment: cheaper supervision)

Spec path `specs/mission-control`; walk started at `b1a904ee`; walkthrough
date 2026-11-09; validator at walk start: 0 errors, 0 warnings. Mode:
amendment on an Active (derived) bundle, operator-declared through mission
control ("lets go with your recommendations"), scoped to the queued asks
on a context reading for every mission-control session, the natural-break
handover keeping the session name, direct dispatch, a cheap relay, spend
per session with real-render previews before anything the operator sees
ships, and an idle-wait self-audit, plus the bring-up drift audit the operator
folded in (2026-11-09). A machine-wide bound on heavy local runs, which
conflicts with custom-steps' empty `full_suite_pool` default, is queued as
its own custom-steps amendment note, not part of this delta. The
post-PR-steps-alongside-CI ask is a separate flight and out of scope. The
delta was drafted into the bundle before the walk, from the
recommendations; each question goes to the operator through mission
control, and only their own relayed words are recorded as answers.

#### Goal and glossary (Amendment 6)

Restatement: supervision costs more than the work it supervises, because
supervising sessions grow their context without bound and every relay
costs a full-context turn. The delta makes every mission-control session
read its own context and hand over at 40 percent at a natural break under
the same session name, sends units that need no supervisor judgment
straight to a worker, moves prompt and finished-unit relays to a script,
shows spend per session, and has the throughput duty find idle waits
nobody needed. Rules out: running post-PR steps alongside CI, changing
the rungs of D-43's ladder (only when it starts moves, to a natural
break), cost-tiered model defaults, and any change to who may answer a
prompt (only where the line goes). What PR #902 already covers: the attended successor
path inside tmux; not the reading, not headless holders, not the name.
Terms: *program's holder* (the mission-control session holding a
program's name, often one another mission control launched, with no
operator at its terminal); *launching mission control* (the mission
control that launches a direct-dispatch unit and owns its registry row);
*natural break* (the act in hand ended, none started, no launch, relay or
answer of the session's own half done); *direct-dispatch kind* (a registered
unit kind on `mission_control_direct_dispatch_kinds`); *real-render preview* (the change's own render,
captured over fixture data, never a mock-up); *relay* (forwarding a
session's prompt, result or message through another session).

#### Requirements walkthrough (Amendment 6)

Every question went to the operator through mission control; the answers
below are the operator's own picks, relayed 2026-11-10. The draft followed
each recommendation, so no answer changed it.

- **Direct dispatch (REQ-D1.15).** Reviews of a pull request, spec
  walkthrough renders, goal-evidence sessions and read-only audits go
  straight to a worker, as an editable list; kickoffs, implementation and
  anything that changes a repository stay with the supervisor. Who may
  answer a prompt is unchanged.
- **Relays (REQ-E1.7).** A notifier delivers each new prompt and each
  finished unit at once, one line each, without waking the supervisor;
  other routine events batch into one wake every 10 minutes; urgent ones
  (a handover due, a stopped watcher, a failed self-check, a denial, the
  operator's own answer) still wake at once.
- **Session name (REQ-L1.6, REQ-L1.9).** A handing-over session keeps its
  name where the session type allows it, else falls back to the
  one-command handover; a script forwards what the old session receives,
  word for word, until the switch completes.
- **Previews and spend (REQ-F1.17, REQ-F1.18).** Every operator-visible
  change (panel, text panel, digest lines, guide) stays draft until the
  operator approves a preview built from the real render over sample data,
  enforced by the readiness check; spend totals count by UTC day.
- **Idle-wait audit (REQ-M1.10).** At every handover and at least once a
  day; each finding is a proposed change with the time it would save per
  day; nothing changes without the operator's yes.
- **Drift audit (REQ-A1.9).** Startup and every handover successor flag,
  read only, a rule quoting a number its setting no longer holds and a
  local override whose comment carries a past date or an undated
  temporary; nothing is edited.
- **Rule enforcement field (REQ-B1.8, REQ-A1.10).** Folded in from a
  separate queued ask (settled before the walk, no question needed): each
  rule says how it is enforced and the doctor lists prose, unknown and
  closed-fix rules; an old rule reads as unknown and still loads.
- **Classification.** Meaning-class: it adds requirements and decisions,
  which the spec's rules settle, so no question was asked.
- **Related, separate bundle.** The machine-wide bound on heavy local test
  runs is walked in this same session as its own change to the custom-steps
  spec, with its own sign-off.

#### Design walkthrough (Amendment 6)

Ledger: D-46 to D-53 are new and confirmed as drafted (context reading;
natural-break handover keeping the name; direct dispatch; the notifier and
batching; spend and previews; the idle-wait audit; the drift audit; the
rule enforcement field). D-23, D-25, D-29, D-30, D-35 and D-43 carry
amendment notes and are otherwise confirmed as signed. No decision was
superseded.

#### Verification approach (Amendment 6)

New test-spec entries for REQ-A1.9, REQ-A1.10, REQ-B1.8, REQ-D1.15,
REQ-E1.7, REQ-F1.17, REQ-F1.18, REQ-L1.5, REQ-L1.6, REQ-L1.9 and REQ-M1.10,
mostly `[test]` in the named test files, run by planwright's CI through
`scripts/run-tests.sh`; name delivery under a real session type and preview
approvals are `[manual]` until the gate ships (decided by the dead-paths
lens). Positive controls come first where an empty log could read as a pass.

#### Task graph (Amendment 6)

Tasks 39 to 47. Task 39 (the context reading) goes first and gates 40 to 45;
Task 40 also waits for Task 33, the in-progress every-session handover
task, because both change the same handover commands (the operator's build
order). Task 42 follows 41; Task 44 follows 40; Task 45 (the preview gate)
follows 39 to 44. Tasks 46 (drift audit) and 47 (enforcement field) have no
dependencies. Deliberate non-edge: 43 (spend) does not wait for 40.

#### Risk register (Amendment 6)

1. The shipped handover threshold still reads 70 in `config/defaults.yml`
   until Task 33 ships 40; fixtures set it explicitly (accepted risk).
2. A notifier delivering prompts without waking the supervisor could hide
   one if it fails. Mitigation: delivery claimed under lock, a failed
   delivery retried and raised, a stopped notifier is an urgent wake.
3. A kept session name depends on the backend carrying it. Mitigation: the
   fallback handover, and a `[manual]` real-run check with a named owner.
4. The enforcement field's doctor listing lands beside the open doctor flag
   for a rule that disagrees with its knob. Mitigation: shared reader,
   separate report section, Task 47 must not conflict with that pull
   request.
5. A machine-wide heavy-run bound (separate custom-steps bundle) changes a
   signed default; walked on its own.

Decision-domain gap check (catalog via `scripts/resolve-catalog.sh
decision-domains`): security-posture, concurrency, data-modeling and
observability touched, all decided in D-46 to D-53 (sanitized delivery
line, delivery claimed under lock, registry lock, display-only spend).

#### Lens review (Amendment 6, delta-scoped)

Fan-out, one read-only sub-agent per spec lens over the delta as first
drafted; findings validated against the bundle and the shipped scripts,
then applied unless noted. The drift audit (REQ-A1.9, D-52, Task 46) was
drafted after that pass and the enforcement field (REQ-B1.8, REQ-A1.10,
D-53, Task 47) was folded in later; both are re-covered by the Amendment 7
lens pass below. The operator accepted the 110 findings as applied.

| Lens | Findings | Disposition |
| --- | --- | --- |
| Contract correctness and internal consistency | 17 | Applied: answering authority stated unchanged; wake now the notifier's; tmux prompts stay operator-surfaced; urgent classes listed; handover-due never batched; name kept only where the backend carries it, else the fallback; script forward is not a new act; natural-break wait under the ceilings; amendment notes on REQ-L1.6, L1.9, G1.6, D1.14, D-23, D-25, D-30, D-35, D-43; registry owner and result file as the one write; result file never readiness evidence; preview obligation on Tasks 39, 43, 45; one recorded reading per session per wake |
| Ambiguity and interpretation forks | 14 | Applied: holder and launching mission control named; kinds by registered kind, kickoffs and repository-changing kinds never listed; UTC day, ended sessions counted; in-flight record as the natural-break marker; name mechanics; window source order; time-saved formula; proposal identity; path-list knob and approval form |
| Citation and coverage integrity | 4 | Applied: waiter citation removed; the operator's scope Sources entry added; Task citations widened |
| Dead verification paths | 7 | Applied: name delivery tested as registry resolution plus a `[manual]` real run; positive control for the empty wake log; approval form defined; mod and text-panel tests named; preview approvals `[manual]` until the gate ships |
| Decision-domain gaps | 15 | Applied: transcript path from the registry only; sanitized truncated delivery line; delivery claimed under lock; failed take rollback; no handover loop; one shared parser; previews over fixture data; spend display-only; unit-lost event; held events persisted; knob names and defaults. Accepted as risk: handover default 70 until Task 33 |
| Testability | 26 | Applied in the test-spec: clocks, literal `unknown`, host-percent precedence, exactly-one wake, sanitization, symlink escape, checksums, options-reference check on every knob task |
| Cross-file consistency | 16 | Applied: amendment-note form; In scope and Out of scope bullets; Task 41/42 edges. Declined: restoring the em-dash heading form (mission control's instruction and the project's writing style). Deferred to sign-off: `Last reviewed:` bump |
| Documentation and glossary drift | 11 | Applied: one term each for holder, launching mission control, direct-dispatch kind, real-render preview, relay |
| Rendered-content safety and data hygiene | 0 | Spec prose is not rendered into an executing context; runtime surfaces carry sanitization and fixture-only previews |

Altitude check: no new pinned seed claim, not applicable. Ship-gate check:
every out-of-band fix named is gated as a task (Tasks 39 to 47).

#### Sign-off record (Amendment 6)

Signed off 2026-11-10 by the operator, relayed through mission control and
the hub, signed together with Amendment 7 and the three other amended
specs: the approval summary was answered "Sign off all four
(Recommended)". Amendment on an Active bundle: no status flip;
`Last reviewed:` 2026-11-10 on all four spec files; validator re-run with
0 errors. The delta adds requirements and decisions, so it is
meaning-class. Accepted risks: the shipped handover threshold reads 70
until the in-progress handover task ships 40; the one fix declined and the
110 pre-walk findings accepted as applied, per the lens table above.

Class: meaning
Lens-pass: Amendment 6, delta-scoped lens review above (spec lens set, fanned out; every finding dispositioned), re-covered for the later additions by the Amendment 7 pass
Anchor: `895f1b643ba80174e71bd820f73547054c1efb29` — computed as
`scripts/spec-anchor.sh specs/mission-control`

### Amendment 7 (2026-11-10, amendment: move a session between programs, and reviewers that review only when ready)

Spec path `specs/mission-control`; walk started at `8a226219`; walkthrough
date 2026-11-10. Mode: amendment on an Active bundle, operator-declared
through mission control, walked in the same session as Amendment 6 and
signed separately. Scope: two stop-reports from workers whose units the
signed requirements did not cover (a launcher verb to move a live session
between programs, which adoption and in-program prompt routing did not
allow; and readiness for pull requests whose hosted reviewers review only
once ready). The rule enforcement field is not part of this delta: it
joined Amendment 6.

#### Goal and glossary (Amendment 7)

Restatement: when a program folds into another, its live sessions keep the
old program as owner and their prompts and stalls go unseen; the delta lets
the operator's fold-in move them. Separately, bots that only review after
the flip made readiness pass before their findings landed; the delta has
mission control ask them to review the draft first. Rules out: moving a
mission-control session (it moves by handover), mission control moving a
session on its own judgment, and weakening the flip's conditions. Terms:
*fold-in* (one program merged into another by the operator's order);
*review-on-ready bot* (a hosted reviewer named on
`mission_control_review_on_ready_bots`, shipped empty).

#### Requirements walkthrough (Amendment 7)

- **Who may move a session (REQ-D1.16).** The operator's answer: automatic
  at a fold-in the operator ordered, covering all of that program's live
  sessions with no ask per session; any other move needs the operator's yes
  for that session. The verb takes a reference to that record and refuses
  without it.
- **Reviewers that review only when ready (REQ-D1.17).** The operator's
  answer, in their words: "Can we respond to bots in draft mode and flip
  when done?" Evidence put to them: cubic's trigger comment is known to
  work on drafts; PR-Agent's draft behavior is unconfirmed. They chose:
  review in draft first, with a 30-minute fallback per bot to the
  after-flip wait. The draft was changed to match before this walk
  finished.
- **Silent-bot wait.** 30 minutes, then an operator item naming the bot.

#### Design walkthrough (Amendment 7)

D-54 (the reparent verb and its authority) and D-55 (draft-first review with
the per-reviewer fallback) are new and confirmed as amended. D-35 and D-25
carry amendment notes. No decision was superseded.

#### Verification approach (Amendment 7)

New `[test]` entries for REQ-D1.16 (`tests/test-mission-control-launch.sh`,
fixtures only) and REQ-D1.17 (`tests/test-mc-readiness.sh`, fixture forge
snapshot, draft trigger and fallback paths included). No `[manual]` entry.

#### Task graph (Amendment 7)

Tasks 48 and 49. Task 48 has no dependencies. Task 49 follows Task 45
because both edit the readiness files. Deliberate non-edge: Task 49 does not
wait for Task 48.

#### Risk register (Amendment 7)

1. PR-Agent may not review a draft on a comment. Mitigation: the
   per-reviewer fallback to waiting after the flip; the shipped list is
   empty, so no project changes until it names a bot.
2. cubic's quota is out for planwright until 2026-12-02. Mitigation: a quota
   reply is recorded as skipped and never triggered again.
3. A move rewrites who answers a session's prompts. Mitigation: the
   authority reference is required and the move is undoable.

Decision-domain gap check: security-posture and authorization touched,
decided (authority required; the flip's gate unchanged); concurrency
decided (registry lock).

#### Lens review (Amendment 7, delta-scoped)

Walked inline over the Amendment 7 delta (REQ-D1.16, REQ-D1.17, D-54, D-55,
Tasks 48 and 49) plus the enforcement field's additions (REQ-B1.8,
REQ-A1.10, D-53, Task 47).

| Lens | Findings | Disposition |
| --- | --- | --- |
| Contract correctness and internal consistency | 0 | None |
| Ambiguity and interpretation forks | 1 | Applied: whether a fold-in order covers every session or one (all of the folded program's live sessions) |
| Citation and coverage integrity | 0 | None |
| Dead verification paths | 1 | Applied: how the verb knows it has the operator's authority, now an `--authority` decisions-log reference with a refusal test |
| Decision-domain gaps | 1 | Applied: undoing a move needs no new authority |
| Testability | 3 | Applied: an enumerated "six kinds" count removed (seven kinds exist); consumed-observation case and an unwritable-row case added to the tests |
| Cross-file consistency | 2 | Applied: D-55's rationale and the changelog entry updated to the operator's draft-first choice |
| Documentation and glossary drift | 0 | None |
| Rendered-content safety and data hygiene | 0 | The enforcement value is stored as data and never evaluated; the test covers a shell substitution |

Altitude check: no pinned seed claim, not applicable. Ship-gate check:
every fix named is gated as a task (47, 48, 49).

#### Sign-off record (Amendment 7)

Signed off 2026-11-10 by the operator, relayed through mission control and
the hub: the approval summary was answered "Sign off all four
(Recommended)". Amendment on an Active bundle: no status flip;
`Last reviewed:` 2026-11-10 on all four spec files; validator re-run with
0 errors. The delta adds requirements and decisions, so it is
meaning-class. Accepted risks: PR-Agent's behaviour on a draft is
unconfirmed (the per-reviewer fallback covers it) and cubic's quota is out
on planwright until 2026-12-02.

Class: meaning
Lens-pass: Amendment 7, delta-scoped lens review above (spec lens set; every finding dispositioned)
Anchor: `895f1b643ba80174e71bd820f73547054c1efb29` — computed as
`scripts/spec-anchor.sh specs/mission-control`

### Amendment 8 (2026-11-10, amendment: forgotten asks and duties, enforced rules and leases, idle capacity)

Spec path `specs/mission-control`; walk started at `59175a11`; walkthrough
date 2026-11-10. Mode: amendment on an Active bundle, operator-declared
through mission control and walked with the operator by relay in rounds of
plain questions, drafted in the same session as the worker-permission
delta that shares its lease. Scope: the follow-up ledger forgetting asks and
duties (priority), operator rules the worker tier's guard keeps with one
lease shape, and two doctor and throughput gaps. The runner calling due
items each pass is the signed ledger requirement's and ships as a separate
flight; the number-in-prose doctor check, the prose-or-unknown listing and
the idle-wait audit are signed and not redrafted.

#### Goal and glossary (Amendment 8)

Restatement: mission control must not depend on remembering. Every ask and
duty becomes a tracked item by a path that does not need the session to
remember; overdue ones lead the status and stop a handover; a rule the
operator states can be kept by the guard instead of by prose; one lease shape
is the only way a worker is allowed, briefly, something a rule denies; and
the doctor and throughput duty notice rules that disagree with settings and
capacity left idle. Rules out: the guard evaluating raw regular expressions
or running clause text, a standing lease, a lease lifting a Bash deny row,
and the audits changing anything. Terms: *intake row* (a stored operator
message awaiting disposition), *clause* (a rule's data-form enforcement),
*lease* (a short, single-worker, operator-authorized exception).

#### Requirements walkthrough (Amendment 8)

Operator's answers, relayed through mission control and the hub:

- **Hook edits (REQ-G1.7, and the worker-permission delta).** "Mid-run, one
  worker (Recommended)": a lease the hub opens after the operator's yes, one
  hour by default and four at most, closing on report.
- **Asks (REQ-F1.19).** The operator asked whether a queue fits; the draft
  already was one. Answer "1" plus "we maybe missing some more queues": the
  durable ask queue with the turn-end and handover block, and REQ-F1.24, the
  audit of state that should be a queue but is not.
- **Event triggers (REQ-F1.22).** "Refuse it (Recommended)", with a fallback
  date flag.
- **New rules (REQ-B1.11).** "Watch-only first (Recommended)".
- **Unreadable rules file (REQ-B1.10).** "Refuse and say why (Recommended)".
- **Test commands** are the worker-permission delta's: "Command shapes
  (Recommended)", a new setting.
- **Idle capacity (REQ-M1.11).** "Bring a proposal (Recommended)".

#### Design walkthrough (Amendment 8)

D-56 (ledger duties by a deterministic path), D-57 (one lease shape, rules
carry clauses) and D-58 (idle capacity, a knob rule's required value) are new
and confirmed. D-53 gains annotations only. No signed decision is superseded.

#### Verification approach (Amendment 8)

Every new requirement has a `[test]` entry; the changed enforcement
requirement's entry names its extensions. Coverage runs in the existing suites
plus a new lease suite, in CI. No dead path found: the one behaviour that
depends on the host (a turn-end check refusing a stop) is proven by Task 51's
fixture, and the handover check fails regardless.

#### Task graph (Amendment 8)

The new tasks are in the bundle's task list; their `Dependencies:` lines are
the graph. Deliberate non-edges: the lease work and the ledger work do not
depend on each other, and the throughput task depends only on the existing
idle-wait task, so they run in parallel. The worker-permission delta's lease
consumer reads the lease store this bundle's lease task ships and treats an
absent lease as no lease, so it needs no cross-bundle edge.

#### Risk register (Amendment 8)

1. A turn-end check depends on how the host's stop hook behaves.
   Mitigation: Task 51 proves it with a fixture; the handover check fails on
   an open intake row regardless.
2. Clause evaluation on every worker call could slow workers. Mitigation:
   a call no clause's tool and scope can match reads nothing.
3. A leased worker's own commit runs the hook it edited. Mitigation: one
   named worker, an hour, the diff, and the posture-change flag on the pull
   request; accepted as a residual.
4. A mistaken live clause blocks workers. Mitigation: watch-only first, and
   returning a clause to watch-only is one verb.
5. An obligation-word list will miss and over-list rules. Mitigation: the
   listing is advisory and overlay-extendable.

Decision-domain gap check: security-posture and authorization touched and
decided (lease opened only by mission control on the operator's cited yes,
closed on report, expiry or retirement); concurrency decided (one shared
reader, a lease never read from a worktree); data handling decided (clauses
stored and compiled as data, never evaluated).

#### Lens review (Amendment 8, delta-scoped)

Walked inline over the Amendment 8 delta (the ledger, clause, lease,
required-value, doctor and idle-capacity requirements and decisions D-56 to
D-58 with their tasks), with the worker-permission delta read for the shared
lease.

| Lens | Findings | Disposition |
| --- | --- | --- |
| Contract correctness and internal consistency | 1 | Applied: the worker tier's policy guard defers the file and MCP surfaces today, so the clause task now names adding them |
| Ambiguity and interpretation forks | 1 | Applied: the unreadable-rules posture settled by the operator (refuse, say why) |
| Citation and coverage integrity | 0 | None |
| Dead verification paths | 1 | Applied: the enforcement requirement's test entry names the clause and required-value extensions the annotation adds |
| Decision-domain gaps | 0 | Security, authorization and concurrency decided above |
| Testability | 1 | Accepted: the stop-hook behaviour is proven in Task 51 (risk 1) |
| Cross-file consistency | 1 | Applied: the worker-permission bundle annotates its hooks requirement and supersedes its deny-block requirement; the lease is cited by qualified name in both directions |
| Documentation and glossary drift | 0 | None |
| Rendered-content safety and data hygiene | 0 | Clause text is stored as data; the clause test covers a substitution |

Altitude check: no pinned seed claim, not applicable. Ship-gate check: every
change is a task. Enumeration cross-check: no requirement states a count;
the changelog's task range records the event.

#### Sign-off record (Amendment 8)

Signed off 2026-11-10 by the operator, relayed through mission control and
the hub: the sign-off answer was "Signoff but this is impossible to
understand and I thought we fixed it already", taken as sign-off with the
instruction that the pull request lead with plain sentences, say that only
the runner's due-item check (a separate pull request) is built, and fold the
rest. Amendment on an Active bundle: no status flip; `Last reviewed:`
2026-11-10 on all four spec files; validator re-run with 0 errors. The delta
adds requirements and decisions, so it is meaning-class. Accepted risks:
see the register above.

Class: meaning
Lens-pass: Amendment 8, delta-scoped lens review above (spec lens set; every finding dispositioned)
Anchor: `680823240e853952e6d4083f57285b25f1bf0ca7` — computed as
`scripts/spec-anchor.sh specs/mission-control`

### Re-anchor — test-spec file pointers after the per-file budget split (2026-11-11)

Marked self-re-anchor for an expression-only edit, machine-written per the
meta-spec's expression-only lane (`doctrine/spec-format.md`, *Writers*).
The REQ-A1.9 and REQ-L1.9 test entries now name the test files their cases
moved into; no requirement or decision changes meaning.

**Cites the changelog line:** the 2026-11-11 `## Changelog` entry in
`requirements.md`.

Class: expression-only
Anchor: `0b3470f9d383b8b0b419b86405748f4ee8249298` — computed as
`scripts/spec-anchor.sh specs/mission-control`

### Re-anchor — test-spec file pointers after the launch-test split (2026-11-11)

Marked self-re-anchor for an expression-only edit, machine-written per the
meta-spec's expression-only lane (`doctrine/spec-format.md`, *Writers*).
The REQ-D1.10, REQ-D1.11 and REQ-D1.16 test entries now name the test files
their cases moved into; no requirement or decision changes meaning.

**Cites the changelog line:** the 2026-11-11 `## Changelog` entry in
`requirements.md` (the launch-test split).

Class: expression-only
Anchor: `d6cab8debc8599d3cb842fd5d3bdf7c0234013b7` — computed as
`scripts/spec-anchor.sh specs/mission-control`

### Amendment 15 (2026-11-13, amendment: the duty ledger drives itself, rulings do not cross handovers, outcomes are audited)

Spec path `specs/mission-control`; walk started at `6653bb25`; walkthrough
date 2026-11-13. Mode: amendment on an Active bundle, operator-declared
through mission control and walked by relay, one plain question per turn.
Scope: the runner repeating a due wake and sweeping validity (REQ-F1.25,
REQ-P1.1 to P1.6, D-65 to D-67, Tasks 75 to 79) and, folded in by the
operator mid-walk, rulings checked at every crossing (REQ-P1.7 to P1.10,
D-68, Tasks 80 and 81) and the outcome audit with a miss ledger (REQ-P1.11
to P1.14, D-69, Tasks 82 and 83). Changelog notes the numbering against the
other unsigned amendments (9 to 14).

#### Goal and glossary (Amendment 15)

Restatement: nothing core may depend on the operator noticing. A duty is
something monitored and fulfilled until done, whose moment may be unknown;
the runner, not a session's memory, re-checks every open item, repeats the
wake until acted on, and pushes an overdue one as a failure. A ruling given
once is data every successor reads. The system audits outcomes the way the
operator does and learns from each miss the operator caught first. Rules
out: the sweep closing on a person's confirmation, moving a rule or
deleting an item by itself, or reading free text for intent. Terms: *sweep*
(the validity re-check), *miss* (a problem the operator caught first).

#### Requirements walkthrough (Amendment 15)

Operator's answers, relayed through mission control and the hub, verbatim:

- **Home of the work.** "Extend mission-control (Recommended)".
- **Scope.** "Fold all three in (Recommended)": crossed decisions, the
  outcome audit with the miss ledger, and the unrelayed question as the
  audit's first fixture (REQ-P1.12).
- **Knob values.** "Tighter (Recommended)": repeat interval 2 hours, overdue
  grace 12 hours, sweep interval 30 minutes, stale window 7 days, a relayed
  question left unasked flagged after 30 minutes, other audit thresholds the
  overdue grace. Values live in the knob defaults, not the spec.
- **Behavior defaults.** "Confirm all three (Recommended)": the sweep closes
  only on a passing machine check and raises person-only conditions as
  stale; time-bound rules use `--until` and existing ones are only proposed;
  dead event words are listed stale, never deleted.

#### Design walkthrough (Amendment 15)

D-65 (repeat and sweep; amends D-56's rejection of auto-close to a check,
never a bare assertion), D-66, D-67, D-68 and D-69 are new and confirmed.
No signed decision is superseded; REQ-F1.25 supersedes REQ-F1.23.

#### Verification approach (Amendment 15)

Every new requirement has a `[test]` entry. Coverage runs in the existing
suites plus the registry check under `mise run check`, which must fail once
on its fixture before it is trusted. No dead path found.

#### Task graph (Amendment 15)

Tasks 75 to 83; their `Dependencies:` lines are the graph. Deliberate
non-edges: the registry check (77) and the ruling checks (80) depend only on
Task 50 and run in parallel with the repeat and sweep work; the doctor flag
(81) waits only on 80.

#### Risk register (Amendment 15)

1. Tasks 50 and 52 are not landed; the first flights extend what they add.
   Mitigation: stated dependencies.
2. Numbering may collide with the other unsigned amendments. Mitigation: the
   changelog note; whichever is kicked off second renumbers.
3. Subject matching can miss a ruling filed under another subject.
   Mitigation: check-first only refuses or proposes; the miss ledger records
   a crossing that still happens.
4. The relayed-question event depends on the host's turn-end signal.
   Mitigation: the audit's unasked check reads the relay record as backstop.
5. A command check on an item runs operator-authored text. Mitigation: the
   REQ-N1.4 limits, a hostile-text fixture.

Decision-domain gap check: data handling (checks print presence, never a
secret), authorization (the sweep closes only on a machine check),
concurrency (one writer per file, per-item records in the runtime
directory) and failure handling (a failed raise repeats) touched and decided.

#### Lens review (Amendment 15, delta-scoped)

Walked inline over the Amendment 15 delta (REQ-F1.25, REQ-P1.1 to P1.14,
D-65 to D-69, Tasks 75 to 83, their test-spec entries).

| Lens | Findings | Disposition |
| --- | --- | --- |
| Contract correctness and internal consistency | 1 | Applied: Task 82 names the turn-end signal as the question event's source and the relay record as backstop |
| Ambiguity and interpretation forks | 0 | None |
| Citation and coverage integrity | 0 | Every cited ID resolves; every new REQ has a test entry |
| Dead verification paths | 0 | None |
| Decision-domain gaps | 0 | Decided above |
| Testability | 1 | Accepted: subject matching (risk 3) |
| Cross-file consistency | 0 | None |
| Documentation and glossary drift | 0 | None |
| Rendered-content safety and data hygiene | 0 | Hostile-text and secret fixtures in REQ-P1.3 |

Altitude check: the duty-ledger report's pinned claim is core, default-on;
D-67 records it and Tasks 79 and 82 ship the duties. Ship-gate check: every
change is a task. Enumeration cross-check: no requirement states a count.

#### Sign-off record (Amendment 15)

Signed off 2026-11-13 by the operator, relayed through mission control and
the hub: "Sign off (Recommended)". Amendment on an Active bundle: no status
flip; `Last reviewed:` 2026-11-13 on all four spec files; validator re-run
with 0 errors. The delta adds requirements and decisions, so it is
meaning-class. Accepted risks: see the register above.

Class: meaning
Lens-pass: Amendment 15, delta-scoped lens review above (spec lens set; every finding dispositioned)
Anchor: `2382840828be4b416a291dfebe9bc3d225d2bbc2` — computed as
`scripts/spec-anchor.sh specs/mission-control`
