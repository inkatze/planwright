# Core rewrite — Kickoff brief

## Header

- **Spec path:** `specs/core-rewrite/`
- **Spec commit at walkthrough start:** `bf642e64`
- **Walkthrough date:** 2026-11-28
- **Mode:** first activation (Status Draft, no prior brief)
- **Validator at pre-flight:** `scripts/spec-validate.sh specs/core-rewrite`, 0 errors, 0 warnings
- **Conduct:** relayed walk. Every question went to the operator through
  planwright mission control as one plain line; answers are the operator's
  relayed words. No harness-provided decision log was present, so the
  structured transcript mirror is skipped for this run.

## Goal & glossary

**Restatement.** The spec moves the rules planwright's pipeline depends on out
of agent instructions and into code that refuses their violation. It builds
one prebuilt Go program with an embedded SQLite store that holds pipeline
state (sessions, units, points, steps, records, prompts, approvals) and moves
it only through state-machine verbs. A single decision engine at every
PreToolUse hook replaces the per-tier shell guards: the OS sandbox confines
local work, typed verbs carry every outward act and judge their arguments
(push judges the refs git resolves, not the command text), a real shell
parser fails closed where no sandbox runs, and the human-gate acts form a
floor held both by the engine and by settings deny/ask rules. Approvals and
relayed operator goes become records the core acts on. Cost measures (review
sized to the diff, PR-Agent once per final head, touched-file CI budgets,
fail-closed usage ladder, per-step model tiers, generated handovers) land as
core capabilities. Rollout is replay, then shadow, then live, with a kill
switch.

**Rules out.** Changing which acts are human-only; any new merge, sign-off,
ready-flip or messaging path beyond what human-gates allows; network
listeners and database or queue servers; the Agent SDK as runtime; cross-host
transport beyond SSH; host setup (sandbox packages, service units) as tasks
of this bundle; the shared knowledge base and the mission-control mod
redesign (deferred).

**Assumes.** Claude Code's permission precedence (deny, then ask, then allow;
an ask rule still prompts when a hook allows) holds; the sandbox is available
on planwright's Linux host once its package lands through dotfiles; the
recorded prompt envelopes are enough for an offline replay; universal-binary's
bake-off data stands as evidence for Go.

**Implicit terms.**

- *Floor*: the human-gate acts plus a session editing its own permissions,
  guard, policy or audit log; never allowed on policy alone (REQ-D1.2).
- *Typed verb*: a core command for one outward act, run outside the sandbox,
  holding the credential, validating its arguments against the session's row.
- *Session row*: the store's one record per session (owner, program, unit,
  branch, PR), the source of a session's authority and configuration.
- *Unit / point / step*: a unit of work (spec task, flight, mission-control
  launch); a point is a named moment in its cadence; a step is one resolved
  action at a point, with a record.
- *Shadow window*: the period a slice runs beside the path it replaces,
  logging only.
- *Must-never-allow set*: the fixture set of every floor act in every spelling
  the guard-coverage corpus holds.
- *Routine classes*: the policy-data allow-list the engine answers with no
  model turn.

**Operator confirmation:** "Yes, that's it (Recommended)" (relayed by mission
control from the hub picklist, 2026-11-28).

Signed off: 2026-11-28

## Requirements walkthrough

Per-group intent was walked against the lens findings (recorded in full in
the sign-off section's lens record). Decisions taken with the operator:

1. **Three consistency fixes** (operator: "Apply all three (Recommended)"):
   - REQ-A1.4 now holds every act the human-gates list names, cited rather
     than copied, never performed on the core's own authority, and only on an
     operator approval record where human-gates lets the operator's yes
     authorize it.
   - REQ-E1.1's auto-allowed thread replies are narrowed to threads in which
     only automated reviewers have posted; a thread a person posted in stays
     on the floor.
   - REQ-C1.5's OS-level write deny applies where the sandbox runs; the
     file-tool and parser-tier deny applies everywhere (D-22's no-sandbox
     path).
2. **Shadow window** (operator: "7 days, adjustable (Recommended)"): REQ-H1.2
   now makes the window a config setting, default 7 days, closing only once
   it holds at least one decision from every session type. **The failure rule
   was not ruled on separately:** it is the proposal the question presented,
   which the operator answered under, applied as written ("the new path
   allowing any floor act, or allowing a call the path it replaces refused on
   a floor ground; the new path being stricter is logged, never blocking").
   It is named here for the operator to see at sign-off.
3. **Approval records** (operator: "The core captures it (Recommended)"):
   REQ-E1.5, D-8, Task 13 and the REQ-E1.5 test entry now have the core write
   the record itself from the operator's harness-delivered answer, never from
   a model-supplied argument, bound to act, target and commit, single-use
   unless it carries an explicit scope with an expiry. A floor act proceeds on
   a record only where human-gates lets the operator's yes authorize it.
4. **Store and executable upkeep** (operator: "Add it with safe defaults
   (Recommended)"): new D-23 and REQ-B1.9 (with its test entry), owned by
   Tasks 1 and 3: forward-only migrations after a snapshot, older executable
   refuses a newer store, configured retention, shim version check, a write
   lock whose timeout refuses or asks, caller identity from the harness,
   credentials redacted, a hook time limit that never allows.
5. **Task 2's shape** (operator: "Amendment walks (Recommended)"): Task 2 now
   drafts each of the four supersession changes on its own amendment branch,
   each walked and signed off with the operator in its own short kickoff;
   Task 8 already depends on Task 2, so the live engine waits until all four
   merge. Mission control noted the walks run back to back; that ordering is
   the hub's note, not an operator answer, and is not written into the spec.
6. **The smaller fixes** (operator: "Apply them all (Recommended)", every item
   below except the spec-branch push exception, which was asked separately).
7. **The spec-branch push exception** (asked separately as "only through the
   core's own push command, only with your sign-off record, for that exact
   branch and commit, once"; operator: "Allow, bound to sign-off
   (Recommended)"). Written into REQ-D1.7 with exactly that limit: the kickoff
   publish verb may push a signed spec or amendment branch only through the
   core's own push command, only on the operator's sign-off approval record for
   that exact branch and commit, and only once per record; every other
   spec-branch push stays refused. Task 6 and the REQ-D1.7 test entry carry
   it. "Once" is read as one successful push per record, so a later re-push
   (a terminal re-anchor, say) needs a fresh sign-off record.

**Consolidated spec-edit list** (the smaller fixes, applied in place):

- Goal: hard-blocking is irreversible or outward acts, with the human-gates
  list as the floor (matches REQ-D1.4).
- Scope: "point completion"; "routine classes" for the allow-list.
- REQ-B1.1: platforms are universal-binary's CI matrix; POSIX shell, git and
  gh stay permitted (the shims are shell).
- REQ-B1.6: approval records and capability rows exported; the decision log
  an append-only log file.
- REQ-B1.7: verification against the committed checksum pin and the
  attestation, never a checksum fetched beside the asset.
- REQ-C1.1: "unit" and "point" defined for this bundle (unit wider than
  spec-format's). REQ-C1.3 "strictly after". REQ-C1.4 "resolved step" and
  skips defined. REQ-C1.6 "ready-flip readiness". REQ-C1.7 take unblocked by
  the successor's acknowledgement or an operator waiver record.
- REQ-D1.1: one session-type list (headless worker, tmux session, tower,
  mission control, subagent); a call from a session with no row asks.
- REQ-D1.4: "reversible" defined (effects inside the session's own worktree,
  scratch and unpushed unit branch).
- REQ-D1.5 and D-5: every forge credential source masked; the sandbox is
  required on a sandbox-capable host (a failed start refuses the launch),
  and a host without one runs the parser tier and logs it.
- REQ-D1.6 and D-6: one outward-act list (messages and the kickoff publish
  included); on a host with no sandbox an outward act in shell text is
  refused; fixed verb schemas with exact identifier matching; the message
  verb refuses a person without an approval record; no verb writes an
  approval record.
- REQ-D1.8: redirections, here-documents and substitutions judged; options
  named per command; running a session-written file asks.
- REQ-E1.1: policy data validated at load (a floor entry rejected, the
  previous policy kept); the project's commands are its configured tasks.
- REQ-E1.3: the owner chain (session owner, then program mission control,
  then operator); the delivery bound a config setting.
- REQ-E1.4: the escalation timer fires on time in service mode and at the
  next core call in direct mode.
- REQ-F1.4: a stale-root session is raised to its owner.
- REQ-G1.1 files; REQ-G1.3 one run per code-changing fix round; REQ-G1.4
  touched means the diff against the merge base; REQ-G1.5 the ladder is
  quota-handling's; REQ-G1.6 "launch kind"; REQ-G1.7 the cache lifetime a
  cited config setting.
- REQ-G1.8: a slice is a task that changes a live decision or session
  outcome; it reports in its own Done-when; the raise is an Awaiting-input
  entry on the next slice's task, blocking its dispatch.
- REQ-H1.3, D-14: the shell path is the retained pre-shim bodies; the switch
  is thrown only on an operator approval record, logged, leaving the engine in
  shadow and the floor in force.
- REQ-I1.1, REQ-I1.2, REQ-I1.3, D-16: carried meaning named in full; the rest
  of control-plane named carried, dropped or deferred in its amendment;
  universal-binary's Task 10 design carried into Task 3; the two foreign
  records superseded by new ones rather than edited.
- D-1 "the hub's draft brief"; D-2's uncited bake-off timings dropped; D-4's
  floor wording matches REQ-D1.2; D-7 quotes execution-backends D-5 exactly;
  D-18's figures cite f-44 and f-55; cross-cutting rules for bounds and timers
  (each a config setting whose delivering task sets and cites the default)
  and for D-23.
- Sources: r-46 added; uncited consumed fragments named as corpus input;
  obs:44b2795b cited on REQ-F1.2; a changelog line for this walk.
- Tasks: REQ-A1.3, REQ-A1.4 and REQ-B1.6 given owning tasks; every live task
  (7 to 15) carries the shadow-window and slice-report clauses; Task 1 gains
  the broken-build harness, a synthetic replay corpus, the WAL and
  dependency-list checks, recorded licences and the baseline path; Task 3 the
  per-platform install job, the committed pin, a fixture release and the
  version check; Task 4 names the instruction-budget check; Task 5 a
  per-profile replay fixture; Task 6 the message verb, schemas and the bound
  kickoff publish; Task 7 the profile, file-tool deny and host-result
  checklist and the sandbox auto-allow; Task 8 policy-load rejection, the
  pipe and process-group checks, and the record-gated kill switch; Task 9
  unit templates as data (install stays the operator's), socket caller
  identity, both-mode parity, direct-mode escalation and real-host results;
  Task 10 exports, coalescing and crash safety; Task 11 the copied-recorder
  check and named suites; Task 12 three unit kinds; Task 13 depends on Task
  11 and gains closure evidence and the brief listing; Task 15 the existing
  test-time check and a defaults check; Task 16 approval-record removal and
  the retirement check.
- Test spec: entries aligned with each change above (broken-build harness,
  human-gates list, matrix platforms, exports, fixture release, skips,
  copied recorder in test, waiver, session types, credential sources, verb
  schemas, the kickoff publish exception, parser cases, bot-only threads and
  policy-load rejection, owner chain, direct-mode escalation, fixture
  indexes, launch kind, kill switch record, fixtures-first via step record,
  supersession wording).
- Deferred: two gated ship-gate bullets for the operator's machine setup
  (the Linux sandbox package, the service unit install), each re-surfacing
  when the task that needs it nears.

**Declined, with reasons:**

- Task 1.1 depending on Tasks 1 and 5: a deliberate non-edge; it lands on
  today's hooks before anything depends on the core (D-20).
- An opt-in knob per new capability (customization-boundary): the shadow
  then live gate and the kill switch are the opt-in, and values are config
  per D-17.
- Pull request #1191 untraceable: it exists (open), so the reference holds.
- Sources inputs not cited by a requirement (some follow-ups, r-114): Sources
  lists seed inputs; an input with no requirement citing it is not a defect.
- Picklist dates a day after the header's: drafting spanned the date change;
  the hub dates its picklists.
- "Unbuilt verdict" and "unsigned verdict draft" as drift: two different
  things (the unbuilt task, and its unsigned draft).
- The hook self-check on every call: removing the hook mid-session is a
  self-permission edit, already on the floor; D-23's hook time limit covers
  timeouts.
- Naming the overlay variables in Task 12, a pass line for Task 7's report,
  and the bare-mode message strings in Task 1.1: each Done-when is evaluable
  as written, and a measure's movement is judged by REQ-G1.8's raise.
- control-plane's baseline lost on supersession: a Superseded bundle's landed
  files stay; Task 1 now also records each measure's method and command.

Signed off: 2026-11-28 (with the operator's final sign-off below)

## Design walkthrough

Ledger, D-1 to D-23 (`design.md`):

- **Confirmed, rationale intact:** D-1, D-2 (bake-off timings dropped as
  uncited, decision unchanged), D-3, D-9, D-10, D-11, D-12, D-13, D-15, D-17,
  D-19, D-20, D-21, D-22.
- **Amended at this walk:** D-4 (floor holds the whole human-gates list;
  approval-record path named), D-5 (credential sources; required only on a
  sandbox-capable host), D-6 (kickoff publish and shell refusal on
  no-sandbox hosts), D-7 (supersedes, quoting execution-backends D-5
  exactly), D-8 (the core captures the record), D-14 (record-gated kill
  switch over the retained shell bodies), D-16 (amendment walks; carried,
  dropped or deferred), D-18 (figures cited).
- **Added:** D-23 (store and executable upkeep), with REQ-B1.9.
- **Superseded:** none.

No design decision contradicts a walked requirement after the edits above.

Signed off: 2026-11-28 (with the operator's final sign-off below)

## Verification approach

Coverage mix, as `test-spec.md`'s tags record it: `[test]` for the engine,
verbs, parser tier, state machine, readiness, store and delivery;
`[design-level]` for the doctrine line (REQ-A1.1) and the supersession
citations (REQ-I1.3); `[test + manual]` where a real host is needed (records
and sandbox, credentials, prompt latency, plugin update); `[manual]` for the
shell-guard removal, the shadow-before-live records and the slice reports.

Ownership: the repository's CI runs every `[test]` entry, the Go suites
beside the existing shell suites the shims must keep passing. The `[manual]`
and host halves are owned by the delivering task's Done-when (Tasks 7, 9 and
16 record host results in their PRs) and swept by mission control at each
task's readiness check; the operator's own acts (enabling service mode, the
dotfiles changes, the removal go) are approval records.

Dead paths checked: the host halves depend on operator machine setup outside
this bundle, now carried by the two gated Deferred bullets (risk rows 2 and
3); the replay has a synthetic corpus for CI; every refusal fixture has the
broken-build harness to fail against; the fixtures-first rule is checked by
step record rather than by commit order, which squash merges erase.

REQ-A1.1's design-level check (no requirement here rests on an instruction
alone) was run in the lens pass: the one requirement found resting on a
session remembering, REQ-G1.8's raise to the operator, now has a mechanical
home (an Awaiting-input entry that blocks the next slice's dispatch).

Signed off: 2026-11-28 (with the operator's final sign-off below)

## Task graph

Reconstructed from the `Dependencies:` lines in `tasks.md` (authoritative):

- Roots: Task 1, Task 1.1, Task 2, Task 4.
- Task 3 and Task 6 after Task 1; Task 5 after Task 3; Task 7 after Tasks 5
  and 6; Task 8 after Tasks 2 and 7; Tasks 9 and 10 after Task 8; Task 11
  after Task 10; Task 15 after Task 10; Tasks 12 and 14 after Task 11; Task 13
  after Tasks 10 and 11; Task 16 after Tasks 9, 12, 13, 14 and 15.

Parallelism: Tasks 1.1, 2 and 4 run beside the Task 1 chain from the start;
Task 6 beside Tasks 3 and 5; after Task 8, Task 9 beside the Task 10 chain;
after Task 11, Tasks 12, 13 and 14 together, with Task 15 already free after
Task 10.

Critical path (by the `Estimated effort:` fields): Task 1, Task 3, Task 5,
Task 7, Task 8, Task 10, Task 11, Task 13, Task 16. Task 6 runs level with
Tasks 3 and 5. Calendar time is longer than effort: each live slice also
waits for its shadow window (risk row 1), and Task 8 waits for the operator's
four amendment walks (Task 2).

Deliberate non-edges, so nobody "fixes" them:

- Task 1.1 has no dependency: it lands on today's hooks first (D-20).
- Task 4 has no dependency: the doctrine line needs no core.
- Task 2 has no dependency and is not a code task: it is four amendment
  drafts walked with the operator; Task 8 is the first task gated on it.
- Task 15 depends only on Task 10, not on Task 11: its mechanisms read
  sessions and events, not step records.

Signed off: 2026-11-28 (with the operator's final sign-off below)

## Risk register

1. **Shadow windows add calendar time.** Each live slice waits at least the
   configured window (7 days by default) before deciding live, and the
   critical path holds several in sequence. Mitigation: independent slices'
   windows run concurrently; the window is a config setting. Early signal: a
   slice report showing a closed window with no disagreements long before
   the next slice is ready.
2. **The Linux host's sandbox package is an operator dotfiles change.**
   Task 7's host results (and the host halves of REQ-C1.5, REQ-D1.5 and
   REQ-D1.6) cannot run until it lands. Mitigation: the gated Deferred bullet
   re-surfaces it once Task 5 completes. Early signal: Task 7 dispatched with
   the bullet still open.
3. **Service mode needs the operator's yes and a unit install.** Task 9's
   real-host results (REQ-E1.3, REQ-F1.4 manual halves) wait on both.
   Mitigation: the gated Deferred bullet; the fixture daemon covers the
   `[test]` halves. Early signal: Task 9 ready with no enabled host.
4. **Four amendment walks are operator time on the critical path.** Task 8
   waits until all four merge. Mitigation: Task 2 starts at once, beside
   Task 1. Early signal: Task 7 complete with an amendment still unwalked.
5. **Approval capture depends on the harness exposing the operator's own
   answer to the core's hook.** If it does not, REQ-E1.5 cannot be met as
   written. Mitigation: the fail-closed reading (no record, no act), never a
   model-written record; raise to the operator. Early signal: Task 13's first
   fixture cannot observe a harness-delivered answer.
6. **The bare-mode default may change before Task 1.1 lands.** Every hook
   would vanish silently. Mitigation: Task 1.1 has no dependency and goes
   first. Early signal: a Claude Code release note changing the `-p` default.
7. **Live false denials or asks.** A stricter engine adds prompts.
   Mitigation: stricter-than-shell is logged in shadow, the slice reports
   show prompts per unit, and the record-gated kill switch returns to the
   shell path. Early signal: prompts per unit rising in a slice report.
8. **The kickoff publish's "once per record".** A re-push of a spec branch
   after its sign-off (a terminal re-anchor) needs a fresh sign-off record.
   Mitigation: the kickoff flow re-anchors before its push. Early signal: a
   refused second publish.
9. **Decision-domain gap check** (the core catalog via
   `scripts/resolve-catalog.sh decision-domains`, no overlay domains): data
   storage, concurrency, versioning, secrets and dependency adoption are now
   decided (D-2, D-15, D-23); authorization, API surface, deploy and
   migration, and existing-seam reuse were already decided; caching,
   product strategy, packaging, knowledge engineering, org design and LLM
   output quality do not apply. Two questions stay undecided and are
   **accepted as risks** for the delivering task to decide and record:
   queue semantics of the owner inbox (at-least-once delivery, answers
   idempotent by prompt id, a redelivery cap ending in escalation; Task 8),
   and health signals of the core itself (daemon down, store locked or
   corrupt, hook self-check failing; Tasks 1.1 and 9, via the doctor).
10. **Replay input may carry secrets.** Recorded prompt envelopes are host
    data. Mitigation: D-23's redaction before storage; the CI corpus is
    synthetic. Early signal: a secret-scan hit on a replay artifact.

Signed off: 2026-11-28 (with the operator's final sign-off below)

## Sign-off

### Lens review

Artifact class: **spec** (the spec lens set). Path: parallel fan-out, one
read-only reviewer per lens over the full bundle at first activation, then a
self-critique pass inline; the walk's own edits were then re-checked inline
as a delta (they apply dispositions the lens produced). Kickoff-specific
checks ran within the pass.

| Lens | Findings | Notes |
| --- | --- | --- |
| Contract correctness and internal consistency | 14 | Floor vs approval path; kickoff publish vs protected push; kill switch vs shims; shadow-first vs live tasks; Task 9 vs D-22; store scope |
| Ambiguity and interpretation forks | 27 | Shadow window, sandbox-required, bounds and timers, owner chain, approval scope, slice, touched files |
| Citation and coverage integrity | 10 | Three REQs without a task; a missed fragment; human-gates cites; figure sources |
| Dead verification paths | 13 | Host halves with no owner; no install job; no broken-build harness; fixtures-first after squash |
| Testability | 16 | Unvalued bounds; unnamed suites and paths |
| Decision-domain gaps | 9 | Migration, retention, versioning, writers, secrets, health, queue semantics, platforms, hook budget |
| Cross-file consistency | 18 | Act and session-type lists; human-gates list; kickoff push script; supersession ritual; foreign quotes |
| Documentation and glossary drift | 16 | Unit, point, readiness, brief; enumerations of other bundles' numbering |
| Security (reframed: data hygiene, contract holes) | 13 | Hygiene none; trust root, approval forgery, socket caller, credential sources, verb schemas, kill switch, parser gaps, policy loading |
| Rendered-content safety | n/a | Plain markdown rendered by the forge; no HTML or executing context |

Self-critique pass: added one finding the lenses missed (auto-allowed
replies on bot-opened threads would cover a thread a person joined: a message
to that person).

Validation: each finding was checked against the bundle text and, where it
named one, the sibling bundle, doctrine or script (execution-backends D-5's
wording, universal-binary Task 10's pin design, PR #1191's existence, the
missed fragment's presence, the test-time and instruction-budget checks).
Duplicates across lenses were merged into the groups the walk dispositioned.

Dispositions: every finding is dispositioned in this brief: the four
operator forks (shadow window, approval capture, D-23, Task 2's shape) and
the separately asked push exception in the requirements walkthrough's
decisions; the smaller fixes in its consolidated edit list; the declines with
reasons beneath it; two domain questions accepted as risks (risk row 9).
None is deferred to a backlog.

**Altitude check:** triggered. The pinned altitude claims in `## Sources`
(the operator's revamp words, the hub's draft brief) left D-1; the goal cites
it; the decomposition matches the two altitudes (Task 4 ships the doctrine
line, the rest the capability).

**Ship-gate check:** the out-of-band fixes the bundle names are the
operator's machine setup (the Linux sandbox package, a service unit
install); each now carries a gated Deferred bullet in `tasks.md`. No other
out-of-band fix is named.

### Approval

Approval summary presented to the operator: the spec as walked (the seven
answers, the smaller fixes, the design decisions through D-23, the test plan,
the task order with Task 8 waiting on the four amendment walks, and the risk
register with two questions accepted as open), and what changes downstream
(the Draft to Ready flip, the anchor, the push and the spec PR readied on
green CI; nothing is built until the operator merges it). The question
carried no recommendation.

Operator's answer, relayed by mission control from the hub picklist on
2026-11-28, verbatim: "Sign off and publish (Recommended)". The
"(Recommended)" tag is the hub picklist's label, not part of this kickoff's
question. Sections 3 to 7 were signed off with this answer: the relayed
question labels counted questions rather than sections, so the hub moved to
sign-off after the seventh question (recorded as an observation).

Validator after the flip: `scripts/spec-validate.sh specs/core-rewrite`, 0
errors, 0 warnings. Lint: `markdownlint-cli2` over the bundle and brief, 0
errors.

**Operator ruling after the sign-off** (relayed by mission control from the
hub picklist, 2026-11-28, verbatim): "Walk the four now (Recommended)". The
design, verification, task-graph and risk sections get a separate delta
kickoff, one section per question; the spec PR stays a draft until that
delta signs, overriding `mark_spec_pr_ready_on_kickoff` for this run.

### Sign-off record

Class: meaning
Lens-pass: the lens review recorded above in this section (spec lens set,
full bundle, fan-out, every finding dispositioned)
Anchor: `6678f839cf152640701b8b68303591a968b8692c` — computed as
`scripts/spec-anchor.sh specs/core-rewrite`

## Amendment log

(none yet)
