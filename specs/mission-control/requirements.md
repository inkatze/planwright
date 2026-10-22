# Mission control — Requirements

**Status:** Draft
**Last reviewed:** 2026-10-22
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

Mission control is a standing planwright session for work too complex for
one person to track: many concurrent units of several kinds, decisions
arriving from many sources, and more sessions than an operator can watch.
It is the operator's single point of contact. It launches, drives, verifies
and retires every other session (orchestrators, towers, workers, reviewer
and ad-hoc sessions), relays the operator's decisions, consolidates
decisions from every source into the specs and keeps them linked, keeps
working while the operator is away, and brings the operator only what needs
their own judgment, with the context to decide it. An operator need not know
planwright's concepts: mission control drafts specs with them when work
calls for one, drives kickoffs and amendments as guided conversations,
orchestrates, executes and flies visual flights on their behalf, and stops at
the human gates. Its ground rules and cadence are shipped configuration that
overlays extend and the launcher delivers to every session it starts, so
they survive compaction and are never repeated by hand. Work across several
repositories is one shape it supports.

The bundle is the **core**: the session kind and the **duty** seam. A duty
is a named unit of mission control's work (its triggers, watchers, wake,
rules, operator items and lifecycle), switched on per installation; a
default set ships here, and the larger optional duties (a review desk for
both directions of code review, spec currency against external sources, a
shared-environment broker, a budgeted night shift) are follow-on bundles
seeded by pending notes this bundle writes (D-1, D-27).

The altitude call is D-1: capability plus doctrine, consuming planwright's
seams rather than minting beside them, with the duty catalog as the one new
extension point.

## Scope

### In scope

- The mission-control session kind: identity, posture, bring-up from
  durable evidence, resume by program name, non-authoring, acting on the
  operator's behalf toward every other session.
- A compaction-safe rule source with explicit supersession, re-injected
  after compaction and delivered to every launched session.
- The duty seam: a data catalog of duties, a shipped default set, custom
  duties through the overlay layers, shadow mode, and duty proposals.
- Session lifecycle across every session kind: one launcher, liveness from
  positive evidence, stall detection, retirement, worktree reclaim with a
  verified backup, and an undo ledger.
- Durable watchers under the fleet daemon layer, a single forge snapshot
  per program, and a per-program budget with declared degradation.
- The operator surface: a live panel (a Claude Code mod) with a text
  fallback, one fixed status form, attentive-only delivery with nothing
  dropped, picklist windows, context-carrying items, a follow-up ledger,
  drafts in the operator's voice, a guided first run, and prepared packets
  before human gates.
- Autonomy at the mission-control tier: decisions settled with grounds and
  shown for review, calibration, rule proposals, self-audit.
- Permission posture delivered at launch; denials reported, never routed
  around.
- A program spanning one or more work repositories and one spec root,
  including the per-task repository field and holder dispatch as routed
  amendments.
- A per-program knowledge base with bounded loading rules.
- Handover over compaction: automatic, lossless succession by a fresh
  session.
- Every preference as a documented, default-preserving knob.

### Out of scope

- Any merge executed by an agent, under any value; merging stays the human
  gate `human-gates` states.
- Any message to a person without the operator's yes on the exact text and
  recipient; standing exceptions exist only as named configuration.
- Replacing CI or the automated reviewers.
- Authoring code or editing any repository from mission control.
- Phone or remote-control access for the operator.
- A remote development-environment rung.
- Program-specific values (channels, bot identities, walk tooling, ticket
  conventions, voice samples): they stay in overlays.
- A web or GUI dashboard beyond the in-app panel.
- Cross-machine mission control.
- The review desk, spec currency, the environment broker and the night
  shift as duties: follow-on bundles (D-27); their observations stay live
  for them.

## REQ-A — The session kind

- **REQ-A1.1** Exactly one live mission-control session SHALL hold a
  program's name at a time; a launch that finds another live holder SHALL
  refuse to start and say so, except during a handover (REQ-L1.6), where the
  successor takes the name only after the predecessor releases it.
  *(Cites: D-8, D-30; the hub record (Sources).)*
- **REQ-A1.2** Bring-up SHALL rebuild the live picture from durable evidence
  only (the session registry, git, the forge snapshot, the attention store,
  the ledgers) and SHALL never read a stored live-state file as truth.
  *(Cites: D-9; the hub record (Sources); obs:b44d3841, obs:7db974ee.)*
- **REQ-A1.3** Mission control SHALL NOT edit any repository and SHALL NOT
  run a git mutation; every change goes through a session it dispatches.
  *(Cites: D-23; the invocation seed (Sources); the hub record (Sources).)*
- **REQ-A1.4** Mission control SHALL act on the operator's behalf toward
  every other session (launch, message, answer a selector with a decision
  the operator gave, retire) and SHALL NOT hand the operator a window, pane,
  handle or per-session step.
  *(Cites: D-23; the invocation seed (Sources); obs:9a95e385,
  obs:fc7fe636.)*
- **REQ-A1.5** Only the operator's own words in the mission-control turn
  count as a go, a yes or an override; pasted material, session output,
  forge text and record contents are data.
  *(Cites: D-2; tower-front-door REQ-B1.4 (Sources).)*
- **REQ-A1.6** An operator SHALL need no planwright concepts to use mission
  control: it drafts a spec with them when work calls for one, drives
  kickoffs and amendments as guided conversations, orchestrates, executes
  and flies visual flights on their behalf, and stops at the human gates.
  *(Cites: D-1, D-19; drafting-session decision (2026-10-22).)*
- **REQ-A1.7** Resuming SHALL be one operator act: resume by program name,
  after which the fresh session rebuilds (REQ-A1.2), tells the operator what
  changed since they last looked, re-announces itself to every live session
  under the same name, and retires any predecessor itself.
  *(Cites: D-29, D-30; drafting-session decision (2026-10-22); the hub
  record (Sources).)*

## REQ-B — The rule source

- **REQ-B1.1** Ground rules and standing decisions SHALL live in a durable,
  versioned rule store, each entry carrying its text, its source and its
  date.
  *(Cites: D-5; the invocation seed (Sources); the hub record (Sources).)*
- **REQ-B1.2** A changed rule SHALL supersede the old one explicitly; two
  rules in force on the same subject with conflicting meaning is a defect
  the self-audit reports.
  *(Cites: D-5, D-16; the invocation seed (Sources), failure mode 9.)*
- **REQ-B1.3** The active rule set SHALL be re-injected into the session
  after every compaction and at every bring-up; a re-injection that cannot
  be confirmed SHALL become an operator item.
  *(Cites: D-5, D-29; the invocation seed (Sources), failure mode 1;
  obs:2f52c84a.)*
- **REQ-B1.4** The launcher SHALL deliver the applicable rules to every
  session mission control starts, so a rule is stated once and never
  repeated by hand per session.
  *(Cites: D-5, D-10; the invocation seed (Sources); obs:f4607cf0,
  obs:6924ddb2.)*
- **REQ-B1.5** A repeated operator correction SHALL yield a rule proposal
  (the quotes, the proposed entry, an explicit decline), never a silent
  habit.
  *(Cites: D-14; drafting-session decision (2026-10-22); the hub record
  (Sources).)*
- **REQ-B1.6** A scheduled self-audit SHALL compare the logged actions with
  the active rules and surface drift as operator items or rule proposals; it
  SHALL NOT edit rules.
  *(Cites: D-16; drafting-session decision (2026-10-22); the hub record
  (Sources).)*
- **REQ-B1.7** After a compaction that does occur, the session SHALL
  re-derive its working picture from durable sources and pass a self-check
  (active rules present, open items known, live sessions known) before its
  next act.
  *(Cites: D-29; drafting-session decision (2026-10-22); the hub record
  (Sources).)*

## REQ-C — The duty seam

- **REQ-C1.1** A duty SHALL be a declared entry naming its triggers, its
  watchers, its wake, its rules, the operator-item kinds it may raise, the
  files it owns and its lifecycle hooks.
  *(Cites: D-3; drafting-session decision (2026-10-22).)*
- **REQ-C1.2** Duties SHALL be enabled per installation by configuration,
  with a shipped default set.
  *(Cites: D-3, D-27; drafting-session decision (2026-10-22).)*
- **REQ-C1.3** An overlay SHALL be able to add a custom duty through the
  same four-layer catalog mechanism steps use, with no edit to core.
  *(Cites: D-3; customization-boundary (Sources).)*
- **REQ-C1.4** A disabled duty SHALL arm nothing and cost nothing: no
  watcher, no files, no items.
  *(Cites: D-3; drafting-session decision (2026-10-22).)*
- **REQ-C1.5** A duty's mechanics SHALL be deterministic scripts that
  outlive the session; its judgment SHALL run in short-lived on-demand
  sessions, one per trigger; no standing LLM session SHALL watch anything.
  *(Cites: D-4; fleet-coordination-floor (Sources); the hub record
  (Sources); obs:b9f53634.)*
- **REQ-C1.6** A duty SHALL be able to run in shadow mode, reporting what it
  would have done and doing nothing, before it goes live.
  *(Cites: D-15; drafting-session decision (2026-10-22).)*
- **REQ-C1.7** Mission control SHALL propose a duty when it notices a repeat
  it could take on, as a confirmation in the operator's words (what it
  noticed, the plan, the cadence, where the operator still intervenes, the
  cost, how to turn it off, an explicit decline), and SHALL never enable
  one itself.
  *(Cites: D-14; drafting-session decision (2026-10-22); autopilot-reflex
  (Sources).)*

## REQ-D — Session lifecycle across kinds

- **REQ-D1.1** Every launch SHALL go through one launcher that delivers the
  brief, the rules, the permission profile, the model tier and the
  session's name, and registers the session.
  *(Cites: D-10; obs:eea622de, obs:fde746e3, obs:4b088f58,
  obs:f6658362.)*
- **REQ-D1.2** Liveness SHALL come from positive evidence (the registry pid
  and process state), never from a pane's text or elapsed time.
  *(Cites: D-11; fleet-coordination-floor (Sources); obs:ffc22bbf,
  obs:f1d1efcc.)*
- **REQ-D1.3** The stall detector SHALL name its states positively and
  SHALL catch a dead session, an unsubmitted prompt, an open selector and a
  turn that ended with background work still running.
  *(Cites: D-11; the invocation seed (Sources), failure mode 6;
  obs:b23d6ea9, obs:54b2c3b6, obs:aa7c5b3b, obs:faca6d00.)*
- **REQ-D1.4** Mission control SHALL drive a session to done: it answers
  what the task, the spec, the code and the rule store settle, and relays
  only forks and operator-only blockers.
  *(Cites: D-13; inter-orchestrator-coordination (Sources);
  obs:fc7fe636.)*
- **REQ-D1.5** A finished session SHALL be retired by mission control
  (exited, pane closed, registry row cleared), never left for the operator.
  *(Cites: D-10; obs:7bc2494a, obs:b3182907, obs:5b600809.)*
- **REQ-D1.6** A worktree SHALL be reclaimed only when no live session uses
  it, its PR has landed or closed, it holds no uncommitted or unpushed work,
  and its ignored audit files were verifiably backed up first.
  *(Cites: D-10; the hub record (Sources); obs:a96e128c, obs:c113f3a6,
  obs:ac5c0438.)*
- **REQ-D1.7** Every automated act SHALL be logged with a one-step reversal
  where one exists.
  *(Cites: D-24; drafting-session decision (2026-10-22).)*
- **REQ-D1.8** A readiness-check duty SHALL verify, from primary evidence at
  the current head (recorded cadence steps, CI, review threads, automated
  reviewer findings, smoke and walk evidence), that a unit is ready before a
  flip is offered or requested, and SHALL never rely on a session's own
  report alone.
  *(Cites: D-25; the invocation seed (Sources), failure mode 8;
  obs:921b93c9, obs:3739da3e, obs:3d66ac61, obs:f63d8644, obs:f2c2c3ae.)*

## REQ-E — Durable watchers

- **REQ-E1.1** Watchers SHALL be deterministic scripts armed by a daemon
  runner that re-arms them, so they outlive any session.
  *(Cites: D-4; the invocation seed (Sources), failure mode 2;
  obs:e7a9f1e0.)*
- **REQ-E1.2** Each watcher SHALL declare its cadence, its cost class and
  the event it emits.
  *(Cites: D-12, D-17; obs:b1b85008, obs:8b694bdb.)*
- **REQ-E1.3** Events SHALL land in the attention store and wake mission
  control by push; polling is the failsafe, never the sole path.
  *(Cites: D-7; fleet-coordination-floor (Sources); obs:5e71ac80,
  obs:a7be9fd5.)*
- **REQ-E1.4** The failsafe tick SHALL fire from the panel's timer where the
  panel loads and from the daemon runner otherwise, so it fires whether or
  not the model remembers.
  *(Cites: D-6; drafting-session decision (2026-10-22); research: Claude
  Code mods API (Sources).)*
- **REQ-E1.5** A watcher that stops SHALL itself be an event.
  *(Cites: D-4; the invocation seed (Sources), failure mode 2.)*

## REQ-F — The operator surface

- **REQ-F1.1** A live panel SHALL show what is in flight, what waits on the
  operator, recent decisions, budget headroom, compactions since start and
  knowledge-base freshness, updated from the stores without a turn.
  *(Cites: D-6; the invocation seed (Sources); obs:97519339,
  obs:0674f1ee.)*
- **REQ-F1.2** The panel SHALL be polished (clear hierarchy, good
  interaction, light aviation theming and animation where it fits) and
  SHALL degrade to a text line where nothing draws.
  *(Cites: D-6; drafting-session decision (2026-10-22).)*
- **REQ-F1.3** Status on request SHALL come in one fixed form: decisions
  first, then what landed, then what is moving, never history.
  *(Cites: D-19; the invocation seed (Sources); tower-comms (Sources).)*
- **REQ-F1.4** The inbox SHALL deliver only when the operator is present,
  one item or one coupled cluster per turn, ranked by consequence and age,
  batched by subject.
  *(Cites: D-7; the invocation seed (Sources); the hub record (Sources).)*
- **REQ-F1.5** The queue SHALL be durable and nothing SHALL be dropped: an
  item leaves only by an operator answer or by evidence it no longer
  applies, with the settling reason recorded.
  *(Cites: D-7; drafting-session decision (2026-10-22); obs:5b600809,
  obs:6a2d1abd.)*
- **REQ-F1.6** A picklist with no answer within its window SHALL fall to its
  declared default or a park, stay visible as settled-by-default, and work
  SHALL continue meanwhile.
  *(Cites: D-7; the invocation seed (Sources).)*
- **REQ-F1.7** Every delivered item SHALL be answerable alone, in the
  operator's domain words, with full links, what the thing does, what is
  asked, whether it is right, what each option would do, and a grounded
  recommendation with what was checked.
  *(Cites: D-19; the invocation seed (Sources); the hub record (Sources);
  obs:478f36fc, obs:15c75f4f.)*
- **REQ-F1.8** A decision SHALL reach the operator only at a human gate, a
  fork the record and the sources cannot settle, or a hard-disqualifier
  zone; every other decision is taken with grounds, logged, and shown for
  review.
  *(Cites: D-13; autonomous-safe-decision (Sources); drafting-session
  decision (2026-10-22).)*
- **REQ-F1.9** A decision mission control settled that the operator later
  revokes SHALL lower that decision class's autonomy, and the hit rate SHALL
  be visible.
  *(Cites: D-13; drafting-session decision (2026-10-22).)*
- **REQ-F1.10** A follow-up ledger SHALL track every promise, deferral and
  open question with owner and trigger, and due items SHALL be started, not
  remembered.
  *(Cites: D-9; the hub record (Sources).)*
- **REQ-F1.11** Drafts for people SHALL be in the operator's voice and go to
  the clipboard unless the operator says send; nothing SHALL be sent without
  the yes.
  *(Cites: D-19; the hub record (Sources); REQ-I1.3.)*
- **REQ-F1.12** The first run SHALL be guided: one objective at a time,
  visible progress, immediate feedback, scaffolds that fade with uptake, and
  it SHALL end with a working configuration.
  *(Cites: D-18; drafting-session decision (2026-10-22);
  interaction-style (Sources).)*
- **REQ-F1.13** The guidance level SHALL be a knob, guided by default on a
  fresh installation.
  *(Cites: D-18, D-20; drafting-session decision (2026-10-22).)*
- **REQ-F1.14** Before a human gate, the operator SHALL get a prepared
  packet: what to look at, what changed since they last looked, the risks,
  and the order.
  *(Cites: D-25; drafting-session decision (2026-10-22); the hub record
  (Sources).)*

## REQ-G — Permissions at scale

- **REQ-G1.1** The launcher SHALL deliver the right permission profile to
  every session, so a sanctioned command never prompts.
  *(Cites: D-10; obs:eea622de, obs:5cc481d6, obs:849b32d5, obs:a0b33b4b.)*
- **REQ-G1.2** A permission prompt that reaches the queue SHALL be answered
  by a standing decision when one matches, strictly inside its rule, and
  otherwise surfaced once with its command.
  *(Cites: D-7; tower-comms D-12 (Sources); obs:fd1824a4, obs:3ea8cd0d.)*
- **REQ-G1.3** A hook, guard or classifier denial SHALL be reported with its
  exact text and SHALL never be routed around by any session mission
  control runs.
  *(Cites: D-23; the invocation seed (Sources), failure mode 10; the hub
  record (Sources).)*
- **REQ-G1.4** Mission control SHALL NOT edit a settings file or widen its
  own posture.
  *(Cites: D-2; tower-front-door D-14 (Sources).)*

## REQ-H — Programs across repositories

- **REQ-H1.1** A program SHALL name one or more work repositories and one
  spec root, in any posture the spec root supports.
  *(Cites: D-8; the invocation seed (Sources); obs:74a7f907.)*
- **REQ-H1.2** A task MAY name the repository its code lives in, and
  dependency state SHALL be read from the repository each dependency landed
  in.
  *(Cites: D-22; obs:74a7f907; the hub record (Sources).)*
- **REQ-H1.3** A session started in a spec holder SHALL be able to dispatch
  into its work repositories.
  *(Cites: D-22; custom-spec-location (Sources); obs:e1722435.)*

## REQ-I — Invariants

- **REQ-I1.1** Mission control SHALL never merge.
  *(Cites: human-gates (Sources).)*
- **REQ-I1.2** Mission control SHALL never flip a PR ready outside the
  configured policy, and in a work repository only on the operator's
  request.
  *(Cites: human-gates (Sources); the hub record (Sources).)*
- **REQ-I1.3** Mission control SHALL never send to a person without the yes
  on the exact text and recipient; standing exceptions exist only as named
  configuration.
  *(Cites: D-20; the hub record (Sources).)*
- **REQ-I1.4** Mission control SHALL never rewrite published history outside
  the repository's rewrite scope, never push to a protected branch and never
  delete a remote branch.
  *(Cites: human-gates (Sources); the invocation seed (Sources).)*
- **REQ-I1.5** Mission control SHALL never start a kickoff and never sign
  off a spec.
  *(Cites: human-gates (Sources); tower-front-door REQ-D1.3 (Sources).)*
- **REQ-I1.6** Company data SHALL stay local and in company systems; the
  program home is never committed to a work repository.
  *(Cites: D-8; security-posture (Sources); the hub record (Sources).)*
- **REQ-I1.7** Ready-when and merge-recommendation conditions SHALL be
  configurable per program, repository, label or path as data, and SHALL
  never place a flip or a merge below the floors `human-gates` states.
  *(Cites: D-26; drafting-session decision (2026-10-22); the hub record
  (Sources).)*

## REQ-J — Knobs

- **REQ-J1.1** Every behaviour in this bundle that admits a preference SHALL
  be a documented, default-preserving knob on the four-layer overlay.
  *(Cites: D-20; customization-boundary (Sources); drafting-session
  decision (2026-10-22).)*
- **REQ-J1.2** Every knob SHALL have a row in the options reference naming
  its default and the evidence it came from.
  *(Cites: D-20; bootstrap REQ-K1.8 (Sources).)*

## REQ-K — The knowledge base

- **REQ-K1.1** Each program SHALL have one knowledge base, local and
  private, never committed to a work repository.
  *(Cites: D-8, D-9; storage-classes (Sources).)*
- **REQ-K1.2** Three loading rules SHALL hold: rules are loaded whole; live
  state is derived, never stored; reference knowledge is indexed, bodies
  read on demand, and a read above the entry cap is offloaded to a read-only
  session that returns an answer.
  *(Cites: D-9; work-placement (Sources); the hub record (Sources).)*
- **REQ-K1.3** Each duty SHALL own its own files inside the knowledge base.
  *(Cites: D-3, D-9.)*
- **REQ-K1.4** Specs SHALL be cited, never copied, into the knowledge base;
  source links live there and committed spec text stays neutral.
  *(Cites: D-9; the hub record (Sources); security-posture (Sources).)*
- **REQ-K1.5** One writer per file at a time SHALL hold, and the decisions
  log SHALL be append-only and queried by subject, never read whole.
  *(Cites: D-9; the hub record (Sources).)*
- **REQ-K1.6** The index line budget and the per-entry size cap SHALL be
  knobs, and knowledge-base freshness SHALL be visible.
  *(Cites: D-9, D-20.)*

## REQ-L — Limits and budgets

- **REQ-L1.1** Every duty and watcher SHALL declare its cost and cadence.
  *(Cites: D-17; obs:0c4456bb.)*
- **REQ-L1.2** A per-program budget SHALL bound sessions, forge polls per
  hour, spend class, context steps and host load, with a declared
  degradation ladder.
  *(Cites: D-17; quota-handling (Sources); obs:4d47cc6b, obs:6ee76cba,
  obs:fde746e3.)*
- **REQ-L1.3** Mission control SHALL hand over to a fresh session before its
  context budget runs out.
  *(Cites: D-17, D-29; context-budget-autoheal (Sources); obs:2f52c84a.)*
- **REQ-L1.4** Budget headroom and watcher expiries SHALL be visible.
  *(Cites: D-6, D-17; obs:d75dd699, obs:7e67fe74.)*
- **REQ-L1.5** The handover trigger SHALL use measured context percent where
  the harness exposes it, the completed-step count otherwise, and a
  compaction-count ceiling in either case.
  *(Cites: D-29; research: Claude Code mods API (Sources);
  context-budget-autoheal (Sources).)*
- **REQ-L1.6** The handover SHALL be automatic and lossless where the harness
  allows: the successor is launched, rebuilds, proves it holds the active
  rules and open items against the predecessor's last ledger entry, takes
  the program name, and the predecessor retires itself; the operator sees
  one line. A handover that cannot complete unattended SHALL fall to one
  operator act, never to a degraded session.
  *(Cites: D-30; drafting-session decision (2026-10-22).)*

## REQ-M — Throughput

- **REQ-M1.1** One forge snapshot per program per cadence, age-stamped,
  SHALL be shared by every duty; no duty polls the forge on its own.
  *(Cites: D-12; obs:8b694bdb, obs:b1b85008; the hub record (Sources).)*
- **REQ-M1.2** Events SHALL reach mission control by push first; polling is
  the failsafe.
  *(Cites: D-7; obs:b9f53634.)*
- **REQ-M1.3** No duplicate work SHALL be done: an unchanged patch is not
  re-reviewed, a unit is never dispatched twice, and a landed unit frees its
  slot within one sweep.
  *(Cites: D-12; obs:ed92dc3a, obs:ac5c0438; the hub record (Sources).)*
- **REQ-M1.4** The next ready unit SHALL dispatch while others wait on CI or
  review.
  *(Cites: D-13; obs:139172a5; the hub record (Sources).)*
- **REQ-M1.5** Merge order and stack retargets SHALL be computed from the
  whole dependency graph across the program's repositories.
  *(Cites: D-25; the hub record (Sources).)*
- **REQ-M1.6** Heavy work SHALL be scheduled against the host budget, not a
  session count.
  *(Cites: D-17; obs:0c4456bb, obs:4d47cc6b, obs:fe2744fa.)*
- **REQ-M1.7** Each act SHALL run on its allocated model tier through the
  existing allocation seam.
  *(Cites: D-10; model-allocation (Sources); obs:fde746e3.)*
- **REQ-M1.8** Interruptions per hour and the share of decisions settled
  without the operator SHALL be measured and visible.
  *(Cites: D-13, D-6; drafting-session decision (2026-10-22).)*

## Changelog

- 2026-10-22 — Drafted (`/spec-draft`): the requirement groups and
  design decisions this bundle lists, elicited from the invocation seed, the hub
  record, four pending notes (cited, not consumed), the observations
  accumulator and the mods research; shape settled as the core bundle with
  the duty seam, the larger duties routed to follow-on bundles.

## Sources

- **The invocation seed (2026-10-21)** — the operator's framing of a hub
  session that holds the whole picture of a complex program, acts on their
  behalf, keeps specs current from many sources, runs code review in both
  directions, and makes what the operator must answer minimal; plus the
  hub's own description of itself: actors, capabilities, hard invariants,
  ten observed failure modes (context drift after compaction, session-only
  machinery, relayed decisions refused, stale drafts, shared-environment
  collisions, silent stalls, rotting live state, unverified "ready", rule
  conflicts, guard bypass) and the candidate pieces. Pinned altitude claims:
  "it is a tower itself but different to the towers running specs" (a new
  session kind); "make the definition and steps configurable as the rest of
  planwright" (capability plus overlay values); "any minor mistake in our
  workflow gets amplified at scale" (rules in shipped configuration, not
  per-session prompt text); "whether this becomes a planwright-native
  capability or stays a local hub" (the altitude question itself).
- **The hub record (read 2026-10-21)** — the resume rules, ground rules,
  memory rules, lane prompts, watcher scripts and queue files of a local,
  uncommitted coordination hub that ran a multi-repository product program
  at an employer for twelve days; read as one instance of the generic
  scenario and neutralized here (no names, identifiers, hosts or links).
  Pinned claims from it: "the hub is the tower, the operator never tracks
  workers"; "specs are a consolidation of decisions from many sources, kept
  current, never the authority"; "only rules and decisions can be made
  durable; state must be re-derived".
- **Operator asides (drafting session, 2026-10-22)** — the duties
  abstraction with defaults and custom duties; mechanics as scripts,
  judgment on demand, no standing attention worker; mission control as the
  front door for most operators with planwright vocabulary internal; every
  knob configurable with good defaults; a guided, game-like first run;
  bounded delivery with nothing dropped; the knowledge-base boundaries;
  limits and landmines; throughput gains at this altitude; less noise
  through settled decisions; duty and rule proposals; shadow mode;
  self-audit; calibration; conflict radar; deadline awareness; undo;
  prepared packets; the night shift; automatic lossless handover over
  compaction. Pinned altitude claim: "mission control is the abstraction
  most people need".
- **Pending notes (cited, not consumed)** — `_pending/tower-comms-supervision.md`
  (queue mechanics for the supervisor duty belong to tower-comms),
  `_pending/fleet-hardening-amendment.md` (a tower permission floor that
  does not depend on the launch), `_pending/merge-currency-guard-amendment.md`
  (the deterministic pr-ready attention record),
  `_pending/worker-permission-ergonomics-amendment.md` (guard screens and
  profile delivery). Each names its owner bundle; this bundle depends on
  them and does not re-decide them.
- **Observations consumed** — cited inline as `obs:<uid>`; the full set this
  drafting mined is the archive move recorded in the same commit. Fragments
  about the review desk, spec currency and the environment broker stay live
  for their follow-on bundles.
- **Research: Claude Code mods (read 2026-10-21 and 2026-10-22)** — the
  mods overview, interface, API and reference pages: render sites (pane,
  band above the prompt, status line, toast, log line, the question
  dialog), timers, file and process access, cross-session messages,
  prompt submission from a timer, the session usage call exposing context
  percent and rate limits, the compaction and post-compaction hooks, the
  redraw throttle, the version floor (2.1.287) and the surfaces where a mod
  draws nothing.
- **Doctrine and bundles consulted** — tower-front-door (the tower, its
  router, its posture, its scope exclusions), tower-comms (the operator
  queue and register), fleet-coordination-floor (non-authoring, no-LLM
  mechanics, assume multiplicity, deterministic attention, lifecycle
  closure), attention-notification-capability, work-placement,
  inter-orchestrator-coordination (the supervisor duty), storage-classes,
  context-budget-autoheal, autonomous-safe-decision, customization-boundary,
  custom-steps, human-gates, model-allocation, quota-handling,
  custom-spec-location, interaction-style, autopilot-reflex, bootstrap
  (REQ-K1.8 options reference; D-21 fold rule), security-posture.
