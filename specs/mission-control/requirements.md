# Mission control — Requirements

**Status:** Ready
**Last reviewed:** 2026-11-11
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

Mission control works smoothly for every operator, from one new to
planwright to an expert: what it presents as working runs, what it starts is
supervised, verified and finished up to the human gates without a manual
step, and the guidance
level decides how much it teaches at the moments that carry consequence (a
merge, a ready flip), never whether a gate holds (D-31).

The bundle is the **core**: the session kind and the **duty** seam. A duty
is a named unit of mission control's work (its triggers, watchers, wake,
rules, operator items and lifecycle), switched on per installation; a
default set ships here, and the larger optional duties (a review desk for
both directions of code review, spec currency against external sources, a
shared-environment broker, a budgeted night shift) and the state-source
adapters (trackers, documents and design tools as snapshot sources) are
follow-on bundles seeded by pending notes this bundle writes (D-1, D-27).

The altitude call is D-1: capability plus doctrine, consuming planwright's
seams rather than minting beside them, with the duty catalog as the one new
operator-facing extension point (the snapshot adapter contract is a seam
later planwright bundles implement, D-12).

## Scope

### In scope

- The mission-control session kind: identity, posture, bring-up from
  durable evidence, resume by program name, non-authoring, acting on the
  operator's behalf toward every other session.
- A compaction-safe rule source with explicit supersession, re-injected
  after compaction and delivered to every launched session.
- The duty seam: a data catalog of duties, a shipped default set, custom
  duties through the overlay layers, shadow mode, and duty proposals as
  one kind of mechanization proposal.
- Session lifecycle across every session kind: one launcher, liveness from
  positive evidence, stall detection, retirement, worktree reclaim with a
  verified backup, and an undo ledger.
- Cheaper supervision: a context reading for every mission-control
  session and a handover at a natural break under the same name, direct
  dispatch of units that need no holder's judgment, a notifier for prompts
  and finished units with batched wakes, spend per session on the panel,
  real-render previews before an operator-visible change ships, and an
  idle-wait audit in the throughput duty; a read-only bring-up audit of
  drift from the shipped defaults.
- Rules that say how they are enforced (an enforcement field the doctor
  lists), a live session moved between programs, and a readiness check
  that waits for reviewers who only review once a pull request is ready.
- Durable watchers under the fleet daemon layer, a single snapshot per
  state source per program (the forge shipped, a per-program source map
  naming the rest), and a per-program budget with declared degradation.
- The operator surface: a live panel (a Claude Code mod) with a text
  fallback, one fixed status form, attentive-only delivery with nothing
  dropped, picklist windows, context-carrying items, a follow-up ledger,
  drafts in the operator's voice, a guided first run, and prepared packets
  before human gates.
- Autonomy at the mission-control tier: decisions settled with grounds and
  shown for review, calibration, mechanization proposals over a mechanism
  inventory, self-audit.
- Permission posture delivered at launch; denials reported, never routed
  around.
- A program spanning one or more work repositories and one spec root,
  including the per-task repository field and holder dispatch as routed
  amendments.
- A per-program knowledge base with bounded loading rules.
- Handover over compaction: automatic, lossless succession by a fresh
  session.
- Every preference as a documented, default-preserving knob.
- Smooth operation at every guidance level: duties that run when shown,
  launches that are supervised, verified and finished up to the human
  gates without a manual step, a panel with no setup, and teaching at consequential moments.
- Taking over a running tower's fleet and adopting sessions mission
  control did not launch.
- Launch admission shared across programs on one host.
- Specs kept true to what ships: a change to behaviour a spec describes
  carries that spec's edit and the operator's sign-off before it is ready.
- Program goals reported done only when their own check passes, never
  because their pull requests merged.

### Out of scope

- Any merge an agent authorizes, under any `merge_policy` value;
  authorizing a merge stays the human gate `human-gates` states, and
  executing one follows that policy.
- Any message to a person without the operator's yes on the exact text and
  recipient; standing exceptions exist only as named configuration.
- Replacing CI or the automated reviewers.
- Authoring code or editing any repository from mission control.
- Phone or remote-control access for the operator.
  *(Amended at the 2026-11-07 amendment: a pane successor keeps the
  harness's own Remote Control only when its predecessor had it, REQ-L1.9;
  planwright builds no remote access of its own.)*
- A remote development-environment rung.
- Program-specific values (channels, bot identities, walk tooling, ticket
  conventions, voice samples): they stay in overlays.
- A web or GUI dashboard beyond the in-app panel.
- Cross-machine mission control.
- Running post-pull-request steps alongside CI, and cost-tiered model
  defaults: separate work, outside Amendment 6.
- The review desk, spec currency, the environment broker and the night
  shift as duties: follow-on bundles (D-27); their observations stay live
  for them.
- Adapters that snapshot a tracker, a document store or a design tool
  (Jira, Notion and Figma are the named candidates): a follow-on bundle on
  the source seam REQ-H1.5 fixes; until one exists such a source is
  `cited`.

## REQ-A — The session kind

- **REQ-A1.1** Exactly one live mission-control session SHALL hold a
  program's name at a time. Two launches may find a live holder and
  proceed: the launch the operator asks for (REQ-A1.7), which is a resume
  and runs as the handover of REQ-L1.6, and the successor the predecessor
  launches with a handover file (D-30); in both the successor takes the
  name only after the predecessor releases it. Any other launch that finds
  a live holder (a second unattended start, a successor whose handover
  file names a predecessor already retired) SHALL refuse to start and say
  so.
  *(Cites: D-8, D-30; the hub record (Sources); kickoff §3 (2026-10-23).)*
  *(Amended at kickoff 2026-10-23: the operator-asked launch named as the
  resume path; the refusal scoped to launches that are neither that nor a
  handover successor.)*
- **REQ-A1.2** Bring-up SHALL rebuild the live picture from durable evidence
  only (the session registry, git, the snapshots of the program's
  snapshot-mode sources, the forge among them, the attention store, the
  ledgers) and SHALL never read a stored live-state file as truth.
  *(Cites: D-9, D-12; the hub record (Sources); obs:b44d3841, obs:7db974ee;
  kickoff §5 (2026-10-23).)*
  *(Amended at kickoff 2026-10-23: the snapshots generalized from the forge
  to every snapshot-mode source.)*
- **REQ-A1.3** Mission control SHALL NOT edit any repository and SHALL NOT
  run a git mutation; every change goes through a session it dispatches.
  *(Cites: D-23; the invocation seed (Sources); the hub record (Sources).)*
  *(Amended at Amendment 9, 2026-11-11: a host act the operator asks for
  (REQ-A1.13) is such a dispatched session; mission control's own tier
  gains no git mutation.)*
- **REQ-A1.4** Mission control SHALL act on the operator's behalf toward
  every other session (launch, message, answer a selector with a decision
  the operator gave, retire) and SHALL NOT hand the operator a window, pane,
  handle or per-session step.
  *(Cites: D-23; the invocation seed (Sources); obs:9a95e385,
  obs:fc7fe636.)*
  *(Amended at the 2026-11-07 amendment: an attended session's pane
  successor replaces the operator's own mission-control pane and needs no
  act, so it is not a handed pane, REQ-L1.9.)*
- **REQ-A1.5** Only the operator's own words in the mission-control turn
  count as a go, a yes or an override; pasted material, session output,
  forge text and record contents are data.
  *(Cites: D-2; the tower skill's operator's-own-words rule, with
  tower-front-door REQ-B1.4 for the one-sentence override (Sources).)*
- **REQ-A1.6** An operator SHALL need no planwright concepts to use mission
  control: it drafts a spec with them when work calls for one, drives
  kickoffs and amendments as guided conversations, orchestrates, executes
  and flies visual flights on their behalf, and stops at the human gates.
  *(Cites: D-1, D-19; drafting-session decision (2026-10-22).)*
- **REQ-A1.7** Resuming SHALL be one operator act: the mission-control
  skill command, with the program name as its only argument, which may be
  omitted when exactly one program is configured (several configured
  programs ask which; none enters the guided first run, REQ-F1.12). The
  fresh session rebuilds (REQ-A1.2), tells the operator what changed since
  they last looked, re-announces itself to every live session under the
  same name; the predecessor retires itself (REQ-L1.6), and one that
  cannot release within the handover window is retired by the successor.
  *(Cites: D-18, D-29, D-30; drafting-session decision (2026-10-22); the
  hub record (Sources); kickoff §3 (2026-10-23).)*
  *(Amended at kickoff 2026-10-23: the entry point stated as the skill
  command with the program-name argument and its omission rules.)*
  *(Amended at sign-off lens pass 2026-10-24: who retires the predecessor aligned
  with REQ-L1.6, with the arm for a predecessor that cannot release.)*
  *(Amended at the 2026-11-04 extension: a program the launch environment
  names counts as the argument, so such a session resumes without asking,
  D-37.)*
- **REQ-A1.8** Mission control SHALL be able to take over the fleet of a
  running tower (a tower handover): it adopts the sessions the tower
  dispatched or its fleet sweep tracks (REQ-D1.12), from which moment the
  tower's sweep and answer paths skip them; it carries the tower's open
  attention items into its own queue by origin id, settling the tower's
  copy with a carried-over reason (REQ-F1.5); it runs the fleet sweep's
  relaunch and observing reap for the adopted flights; and it retires the
  tower only on the operator's yes, releasing the adopted sessions back on
  a no. A re-run resumes a partial tower handover without duplicating. A
  wake mission control relays into a tower session SHALL never count as
  the operator's reply there.
  *(Cites: D-38; audit item 7 (Sources); tower-comms D-6 (Sources);
  obs:a89108b6.)*
- **REQ-A1.9** Bring-up and every successor's self-check SHALL audit, read
  only, what the program runs on that is not planwright's shipped default,
  and report each as a finding the operator settles: a knob a layer sets
  away from its shipped value, a default duty left off, a launch on another
  rung than the knob names, and a cron line touching the program; a
  standing rule whose text names a number for a knob it governs (the
  knob's name followed by a value, or a handover at a context percent)
  while the knob's effective value differs; and a local-layer override
  whose comment or value carries a date already past, or the word interim,
  temporary or until with no date still ahead. Each finding SHALL name the
  file, the knob, the rule or comment and the effective value, in plain
  words. The audit SHALL never edit a layer or a rule.
  *(Cites: D-52; the doctor drift note (2026-11-09, Sources).)*
- **REQ-A1.10** The same audit SHALL list every active standing rule whose
  enforcement (REQ-B1.8) is prose, is unknown, or names an open fix that
  has since closed (a pull request merged or closed, an observation
  consumed), each as one plain line saying what to do (name the thing that
  now enforces it, or keep it as prose with a reason, or retire it). A
  closed-fix check that cannot be made reads as unknown, never as clear,
  and the listing, like the rest of the audit, edits no rule.
  *(Cites: D-53; the rule-enforcement report (2026-11-10, Sources).)*

- **REQ-A1.11** The bring-up audit SHALL also check each active standing
  rule whose enforcement names a knob with a required value or predicate
  (REQ-B1.13) against the knob's effective value, read through the same
  resolver REQ-A1.9 uses, and report a disagreement as a finding the operator
  settles, in plain words naming the rule, the knob, the value the rule
  requires, the effective value and the layer that sets it. A knob that
  cannot be read, or a predicate that cannot be evaluated, reads as
  disagreeing, never as agreeing. The check covers what REQ-A1.9's
  number-in-prose reading does not: it reads the structured field, not the
  rule's text, and the audit edits no layer and no rule.
  *(Cites: D-58; REQ-A1.9, REQ-B1.13; the idle-capacity report (2026-11-10,
  Sources).)*
- **REQ-A1.12** The audit SHALL also list, as candidates and never as
  defects, each active rule whose text carries an obligation word from a
  shipped list (overlay-extendable) and whose enforcement is prose or
  unknown, one plain line each suggesting a clause (REQ-B1.9) or a named
  enforcer, so the rules that sound hard and keep nothing are found. A
  rule that already carries a clause or names an enforcer is not listed.
  The listing edits nothing and is advisory in every operator level.
  *(Cites: D-57; REQ-A1.10, REQ-B1.8; the rule-enforcement ask (2026-11-10,
  Sources).)*
- **REQ-A1.13** When the operator asks in words, in the session, for a host
  act (fast-forwarding a named primary checkout and running one named setup
  command, or reading a configuration file), mission control SHALL take the
  ask as a host-act ask: it records the operator's words quoted in the undo
  ledger (D-24), shows the exact command the ask resolves to, and runs it
  once and in the open. A read-only host act runs in mission control itself;
  every host act that changes a checkout or the machine runs in a host-chore
  session it launches (REQ-A1.14). An ask that resolves to no
  register row (REQ-A1.15) is answered with what is missing, never run from
  free text, and a host act is never started on mission control's own
  initiative: the operator's ask, or a standing rule that names the act as
  the next step after a merge the operator made, is what starts it.
  *(Cites: D-60; D-24; REQ-A1.3; the host-act ask (2026-11-11, Sources).)*
- **REQ-A1.14** A host-chore session SHALL be a session kind launched with a
  launch record, written before it starts where it cannot write, naming one
  checkout (an alias from the machine-local registry, never a path the ask
  supplies), one register row, the operator's quoted ask and its expiry. Its
  permission profile SHALL admit only this: when the named checkout is a
  primary checkout on its default branch with a clean tree, fetch it and
  fast-forward it to the remote default branch (a checkout that is not
  clean, or a branch that cannot fast-forward, stops the session; no merge,
  rebase, reset, push (other than the spec push of REQ-A1.17), stash,
  checkout of another ref or history rewrite is ever admitted); then run the row's one declared command with the row's
  declared arguments. It follows the supervision rules of every worker: one
  purpose, retired when it reports, silent unless it fails.
  *(Cites: D-60; REQ-I1.4; REQ-D1.1; the
  host-act ask (2026-11-11, Sources).)*
- **REQ-A1.15** The host-act register SHALL be shipped data (one row per
  act: an id, the checkout alias, whether it fast-forwards, the one command
  and its arguments as a closed list, and a plain description), extended by
  an overlay and never by the ask's own text. The shipped register holds no
  act: planwright ships the mechanism, and each machine's overlay supplies
  its rows (this machine's dotfiles update, a fast-forward of the dotfiles
  checkout and the user-config playbook run, is rendered into its overlay by
  the dotfiles repo), so no operator-specific path enters shared defaults. A
  row naming a command that merges, pushes, rewrites history, sends a
  message or writes a secret is refused when the register is read.
  *(Cites: D-60; REQ-I1.9; r-29 (Sources); the host-act ask (2026-11-11,
  Sources).)*
- **REQ-A1.16** A host act SHALL run in the open (its exact command shown
  before it starts), its output tail and exit status SHALL be recorded with the act in the undo ledger, and mission
  control SHALL report the outcome in one plain line, and for a failure the
  cause and the routed fix (a launched session), never an automatic retry
  and never the operator's own commands.
  *(Cites: D-60; REQ-G1.3; r-40 (Sources); the host-act ask (2026-11-11,
  Sources).)*
- **REQ-A1.17** A raw push of a spec branch stays refused for every session.
  A host-chore session MAY run the kickoff spec-push helper
  (`kickoff-spec-push.sh`, with the spec id as its only argument) for one
  named spec whose kickoff sign-off record is complete with its anchor, on
  the operator's quoted ask and a launch record (REQ-A1.14) naming that spec; the helper's own sign-off check stays in force,
  and the session admits no other push, no other helper argument and no
  other branch.
  *(Cites: D-60; REQ-I1.4; the host-act ask (2026-11-11, Sources); the
  Amendment 9 walk answers (2026-11-11, Sources).)*

## REQ-B — The rule source

- **REQ-B1.1** Ground rules and standing decisions SHALL live in a durable,
  versioned rule store, each entry carrying its text, its subject, its
  source and its date. A standing decision the operator states in a
  mission-control turn SHALL be written as an entry at once (the operator's
  words are the go, REQ-A1.5), echoed back in one line, with its reversal
  in the undo log (REQ-D1.7); the proposal path (REQ-B1.5) is for repeats
  mission control infers, never for what the operator said outright.
  *(Cites: D-5; the invocation seed (Sources); the hub record (Sources);
  kickoff §3 (2026-10-23).)*
  *(Amended at kickoff 2026-10-23: subject added to the entry; direct
  entry of an operator-stated decision made explicit.)*
- **REQ-B1.2** A changed rule SHALL supersede the old one explicitly; two
  entries in force on one subject is a finding the self-audit reports as an
  operator item, the meaning call left to the operator.
  *(Cites: D-5, D-16; the invocation seed (Sources), failure mode 9;
  kickoff §3 (2026-10-23).)*
  *(Amended at kickoff 2026-10-23: the conflict made mechanical, a shared
  subject, with the meaning judgment on the operator.)*
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
- **REQ-B1.5** A repeat mission control notices (an operator correction, a
  manual step after the same event, the same answer to the same question)
  SHALL yield a mechanization proposal: the smallest mechanism in the
  inventory (REQ-K1.7) that would cover it, named with the evidence (the
  quotes or the repeated acts), the proposed change, its cost and an
  explicit decline, never a silent habit. The mechanism kinds are an open
  list the inventory owns (a rule entry, a knob, a catalog step, a hook or
  permission rule, a scheduled routine, a duty among them). A proposal
  whose change lands in a settings file SHALL be handed over ready to
  apply and never applied (REQ-G1.4).
  *(Cites: D-14; drafting-session decision (2026-10-22); the hub record
  (Sources); kickoff §3 (2026-10-23).)*
  *(Amended at kickoff 2026-10-23: widened from rule proposals to
  mechanization proposals over the inventory's open list of kinds.)*
  *(Amended at Amendment 4, 2026-11-07: the repeats include the same guard
  denial a knob governs, proposed as that knob's setting from
  `config/denial-knobs.tsv`, D-14.)*
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
- **REQ-B1.8** Each rule entry SHALL carry an enforcement field saying how
  the rule is kept, one of: a named script, knob, hook, duty or default
  (the kind and the thing it names); an open fix that will enforce it (a
  pull request or observation id); or prose with a one-line reason.
  `mc-rules.sh add` and `supersede` take it. An entry written before the
  field existed reads as unknown, never as an error, and never stops the
  active set from loading, rendering or re-injecting (REQ-B1.3). The
  field is data the doctor reads (REQ-A1.10); it never changes what a rule
  says or who it binds.
  *(Cites: D-53; the rule-enforcement report (2026-11-10, Sources).)*
  *(Extended by REQ-B1.9 (2026-11-10): a clause is a further enforcement
  the worker tier's guard keeps; by REQ-B1.13: the `knob` kind may carry
  the required value.)*

- **REQ-B1.9** A rule entry SHALL be able to carry an enforcement clause
  that the worker tier's policy guard keeps, so a rule an operator states
  in prose can be kept deterministically with no feature-specific setting.
  A clause is data in a closed grammar with four parts: a match (the tool
  and the command words or argument shape, read by planwright's own
  tokenizer and matcher over literal words, word wildcards and path
  prefixes, never a raw regular expression, with optional path and working
  directory scopes), an effect (deny with the rule's own text, require a
  named flag or argument, or ask the operator-facing session), an optional
  unless naming a lease kind (REQ-G1.7), and a scope (program, worker kind,
  repository; the narrowest that fits is the default). `mc-rules.sh add`
  and `supersede` take it, and a hub-drafted proposal the operator approves
  (D-14's form) may carry it. The clause is stored and compiled as data and
  never evaluated as code, and a clause outside the grammar is refused at
  add with the part at fault named.
  *(Cites: D-57; REQ-B1.8; the rule-enforcement ask (2026-11-10, Sources).)*
- **REQ-B1.10** The policy guard at the worker tier SHALL evaluate every
  live clause whose scope matches on every worker tool call (Bash, the file
  tools and MCP calls alike), reading the compiled clause set from the
  program home and never from the worker's worktree, and a call a clause
  denies SHALL be refused with the rule's id, its text and the remedy (the
  lease to ask for, or the flag to add). A clause set that cannot be read
  or fails its digest check denies and says so, as every other guard read
  failure does; a call that no clause's tool and scope can match defers
  with no clause read.
  *(Cites: D-57; the guard's existing failure posture (Sources).)*
- **REQ-B1.11** A new clause SHALL start in shadow mode: it is evaluated on
  every call, records each call it would have refused with the rule id in
  the guard's audit record, and blocks nothing. It goes live only on the
  operator's yes, after mission control shows what the shadow run recorded
  (the count and examples, and a replay over recent recorded calls where
  the records hold them). `mc-rules.sh` takes the mode change as a verb
  that cites the operator's words, and a clause can be returned to shadow
  or retired the same way.
  *(Cites: D-57, D-14; the rule-enforcement ask (2026-11-10, Sources).)*
- **REQ-B1.12** The capability SHALL ship with a worked example and
  acceptance fixture, the headed browser rule: a launch of a visible
  browser window is denied unless a sign-in lease is open for that worker,
  and a headless launch is not touched. Whether a program holds that rule
  is the operator's and lives in the program's rules, not in shipped
  configuration. A cookie hand-off from a signed-in browser to a headless
  one is a helper a later change may add, not part of this requirement.
  *(Cites: D-57; the rule-enforcement ask (2026-11-10, Sources).)*
- **REQ-B1.13** (extends REQ-B1.8) The `knob` enforcement kind SHALL be
  able to carry the value the rule requires: `knob:<name>=<value>`,
  `knob:<name>!=<value>`, `knob:<name> in <a|b>` and, for a number,
  `knob:<name>>=<n>` or `<=<n>`, matched against that closed grammar and
  stored as data. A knob kind without a value stays valid and means the
  rule only names the knob; the doctor checks the rest (REQ-A1.11).
  *(Cites: D-58; REQ-B1.8.)*

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
  it could take on (the duty kind of REQ-B1.5), as a confirmation in the
  operator's words (what it noticed, the plan, the cadence, where the
  operator still intervenes, the cost, how to turn it off, an explicit
  decline), and SHALL never enable one itself.
  *(Cites: D-14; drafting-session decision (2026-10-22); autopilot-reflex
  (Sources).)*
  *(Amended at kickoff 2026-10-23: the duty named as one kind of REQ-B1.5's
  mechanization proposals.)*
- **REQ-C1.8** Every duty the operator guide or the first run presents as
  working SHALL be armed when enabled (a catalog entry with its watchers
  and schedule); a duty with no such entry SHALL be presented as not yet
  available. An overlay entry the catalog skips as invalid SHALL leave the
  next lower layer's valid entry in force.
  *(Cites: D-40; obs:380ade20, obs:3b7be7a7, obs:a6112066.)*

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
  *(Amended at the 2026-11-04 extension: the pid may come from the
  backend's own record as well as the registry, REQ-D1.12.)*
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
  and its ignored audit files were verifiably backed up first into the
  program home (D-8), under a per-repository, per-branch folder, the copy
  verified by size and hash before removal; which ignored files count is a
  knob whose default lists the audit-file patterns.
  *(Cites: D-8, D-10; the hub record (Sources); obs:a96e128c,
  obs:c113f3a6, obs:ac5c0438; kickoff §3 (2026-10-23).)*
  *(Amended at kickoff 2026-10-23: the backup destination and its
  verification stated; the file set made a knob.)*
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
  *(Amended at Amendment 7, 2026-11-10: a reviewer that only reviews once the pull request is ready is first asked to review while the pull request is a draft; the flip's own conditions are unchanged, and a reviewer that cannot or does not review the draft falls back to a merge-ready report that waits for its pass, REQ-D1.17.)*
- **REQ-D1.9** The readiness check SHALL audit the configured cadence
  (every step the configuration requires at the in-run points through
  `post-pr`) at the pull request's head as the forge reports it, and SHALL
  refuse a flip when a required step has no record or only failed ones,
  when a point's completion is absent or does not count at that head
  (D-33), when the worktree's head differs from the forge's, or when the
  audit cannot run. The gate-condition data (REQ-I1.7) adds conditions and
  never narrows the configured cadence. The configured cadence is not a
  cadence step (a steps-catalog entry whose run gates later units).
  *(Cites: D-33; audit item 2 (Sources); the in-flight cadence fix
  (Sources).)*
  **Superseded-by: REQ-D1.14** (2026-11-07).
- **REQ-D1.14** (supersedes REQ-D1.9) The readiness check SHALL audit the
  configured cadence (every step the configuration requires at the in-run
  points through `post-pr`) at the pull request's head as the forge reports
  it, and SHALL refuse a flip when a required step has no record or only
  failed ones, when a point's completion is absent or does not count at
  that head (D-33), when the worktree's head differs from the forge's, or
  when the audit cannot run. The gate-condition data (REQ-I1.7) adds
  conditions and never narrows the configured cadence, with one exception:
  a spec-only pull request (every changed path a Markdown file added,
  modified or deleted under the spec root, the head holding that root) is
  held for each touched bundle's kickoff sign-off instead of the cadence
  and the gate data's steps, and one touching only the reserved
  accumulators has none to hold. The configured cadence is not a cadence
  step (a steps-catalog entry whose run gates later units).
  *(Cites: D-33; the operator's ruling that spec-only pull requests skip
  the code review steps (2026-11-05, Sources); the spec-drift audit
  (Sources).)*
  *(Amended at Amendment 6, 2026-11-09: the readiness check also refuses an unapproved operator-visible change, REQ-F1.18, adding a condition and never narrowing the cadence; a spec-only pull request is on no listed path.)*
- **REQ-D1.10** A session of a kind that changes a repository (worker,
  reviewer, ad-hoc, kickoff) SHALL run in its own worktree: one the dispatch
  machinery creates at launch, off the default branch or on the unit's
  branch when it exists, or an existing worktree other than a primary
  checkout that the launch names and no live session uses; never a primary
  checkout. Creating it is part of launching, as for a tower's flights, not
  an authoring act (REQ-A1.3). A launch whose worktree cannot be created
  SHALL be refused with no session started. Other kinds run where they are
  launched.
  *(Cites: D-34; audit item 5 (Sources).)*
- **REQ-D1.11** A launch of a kind that changes a repository SHALL carry
  the configured cadence in its brief, as the procedure that resolves and
  records its steps plus the audit command that checks them, so the session
  runs them without being told; a brief that is itself a skill command
  carries that skill's own cadence and is exempt. REQ-D1.9 is the backstop.
  *(Cites: D-33; audit item 2 (Sources); the in-flight cadence fix
  (Sources).)*
  *(Amended at Amendment 4, 2026-11-07: the backstop is now REQ-D1.14,
  which supersedes REQ-D1.9.)*
- **REQ-D1.12** Mission control SHALL be able to adopt a live session it
  did not launch (a tower's dispatch, a hand-launched session, on any
  backend): a launcher verb registers it under the program with its owner,
  kind, scope, backend handle and an adopted origin, only on positive
  liveness evidence (REQ-D1.2), and refuses a session another live
  supervisor holds. From then on stall detection, prompt handling
  (REQ-G1.6) and retirement cover it as they cover a launched one, except
  that retiring a session the operator launched by hand needs the
  operator's yes. Liveness on every backend comes from the session's process
  (its pid in the registry or the backend's own record) and process state,
  never from a row's presence; a stream-json session's event stream informs
  its stall state.
  *(Cites: D-35, D-11; audit item 3 (Sources).)*
  *(Amended at Amendment 7, 2026-11-10: a live session's program and owner can also be moved to another program, REQ-D1.16.)*
- **REQ-D1.13** The readiness check SHALL refuse a flip of a pull request
  that changes behaviour a spec describes unless the same pull request
  edits that spec (changes its anchored content) and the edited spec's
  latest sign-off anchor matches its content at the pull request's head
  (the operator signed the edit off in a relayed kickoff). It SHALL also
  refuse when the spec-drift check flags the pull request: a changed file
  some spec lists as a task deliverable, with that spec's anchored content
  unchanged and no reason line naming that file in the pull request's
  covering-spec statement (D-45). A changed file that is a deliverable of a
  task the pull request's own task trailer names is that task's work and
  is never flagged. A pull request with no statement is read as covering
  no spec and giving no reasons. A check that cannot run refuses.
  *(Cites: D-45; the operator's request (2026-11-07, Sources); the
  spec-drift audit (Sources).)*
- **REQ-D1.15** A unit whose kind is on `mission_control_direct_dispatch_kinds`
  (shipped: a review skill run on a pull request, and read-only checks: a
  spec-walkthrough render, a goal-evidence session, a read-only audit;
  never a kickoff, an implementation unit or anything that changes a
  repository) SHALL be launched by the mission control that has the work
  (the **launching mission control**) through the launcher (REQ-D1.1),
  registered under the unit's program with the launching mission control
  as its registry owner, without a turn of the program's holder. The unit
  SHALL write its result, with a `format` field, to a launcher-composed
  path in the program home (D-8), its one write there; the launching
  mission control reads it, and the program's holder reads it from the
  program's records at its own next wake and is not woken for it. A unit
  that ends without a result is a unit-lost event to the launching mission
  control. A cadence step the unit runs is recorded through the step runner
  as for any unit, and the result file is never evidence for the readiness
  check. The unit's questions and prompts go to the launching mission
  control, answered only as REQ-G1.2 and REQ-G1.6 already allow (a standing
  decision of the unit's program, or the operator's own answer); who may
  answer is unchanged. A kind not on the list keeps the holder's relay.
  *(Cites: D-48; the relay-cost report (2026-11-09, Sources).)*
- **REQ-D1.16** Mission control SHALL be able to move a live session to
  another program, as when one program folds into another: a launcher verb
  sets the session's registry program and owner to the destination
  program's mission control, so that from then on its prompts, stalls and
  other events route to the destination and not the source, the
  destination's list shows it, and retirement works from the destination
  (REQ-G1.6 and REQ-D1.12 cover it there as they cover a launched
  session). It refuses an unknown session, an unknown or the same program,
  a mission-control session (a holder moves by handover, REQ-L1.6, never
  by this verb) and any session whose registry row cannot be rewritten
  under the registry lock. It touches no process, worktree or branch, and
  records the move as one event in both programs' event logs and an undo
  entry naming the source (REQ-D1.7). It runs only at a fold-in the
  operator ordered (one order covers every live session of the folded
  program, with no ask per session), or with the operator's own yes for
  that one session; the verb takes a reference to that record in the
  decisions log and refuses without it, and mission control never moves a
  session on its own judgment. Reversing a move by the undo entry needs no
  new authority.
  *(Cites: D-54; the fold-in report (2026-11-10, Sources).)*
- **REQ-D1.17** The readiness check SHALL treat a hosted reviewer that
  reviews only once a pull request is marked ready (the names on
  `mission_control_review_on_ready_bots`, shipped empty, which each project
  or overlay sets) in two steps. First, while the pull request is still a
  draft, mission control SHALL ask each named reviewer to review the
  current head by that reviewer's trigger comment, and every thread of the
  review SHALL be answered and resolved through the bot-review step before
  the flip. Second, a reviewer that has not reviewed the current head
  within `mission_control_review_on_ready_wait` (shipped: 30 minutes) of
  its trigger comment, or that cannot be triggered on a draft, falls back
  to the after-flip path for that reviewer: the flip is never refused for
  want of its pass, but the unit SHALL NOT be reported merge-ready, and the
  ready-to-merge notice (the program's standing rule) SHALL NOT be sent,
  until that reviewer has reviewed the pull request's current head, every
  thread of it has been answered and resolved, and the readiness check
  passes again at that head. A fallback reviewer silent for another
  `mission_control_review_on_ready_wait` after the flip is an operator
  item naming it, never a silent pass; a push restarts the wait for the new
  head. A named reviewer's quota or outage reply is recorded as that
  reviewer's skipped pass with the reply quoted, and a quota reply is not
  triggered again.
  *(Cites: D-55; the review-on-ready report (2026-11-10, Sources);
  drafting-session decision (2026-11-10, operator: review in draft, flip
  when done).)*

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
  *(Cites: D-6, D-7; fleet-coordination-floor (Sources); obs:5e71ac80,
  obs:a7be9fd5; kickoff §4 (2026-10-23).)*
- **REQ-E1.4** The failsafe tick SHALL fire from the panel's timer where the
  panel loads and from the daemon runner otherwise, so it fires whether or
  not the model remembers.
  *(Cites: D-6; drafting-session decision (2026-10-22); research: Claude
  Code mods API (Sources).)*
- **REQ-E1.5** A watcher that stops SHALL itself be an event.
  *(Cites: D-4; the invocation seed (Sources), failure mode 2.)*
- **REQ-E1.6** Every watcher run and snapshot refresh SHALL run under a
  timeout (a `mission_control_*` knob in seconds, overridable per watcher),
  be stopped when it expires and re-arm on the next pass; the expiry is an
  event (REQ-E1.5), so one hung step never stalls the runner pass.
  *(Cites: D-40; obs:b8d064cc.)*
- **REQ-E1.7** A pending permission prompt in a session with an answer
  channel, and a finished-unit notice, SHALL reach the mission control that
  answers it (the program's holder, or the launching mission control for a
  direct unit, REQ-D1.15) through a notifier script the runner arms per
  pass, with no model turn of any other mission control in between. The
  notifier reads `scripts/fleet-streamjson.sh pending` and the registry,
  claims each delivery in the attention store under its lock before
  sending (at most once), delivers one sanitized line (the kind, the
  session and a truncated, control-stripped summary, the text the
  attention store already holds) by push, retries a failed delivery on the
  next pass and raises an event after the configured retries. A prompt in
  a session with no answer channel stays surfaced to the operator once
  (REQ-G1.6). The other events that would wake a program's holder SHALL be
  held in the attention store and delivered as one wake per
  `mission_control_relay_batch_interval` (shipped: 10 minutes), except the shipped urgent
  classes, which wake at once: a handover-due wake, a stopped watcher or
  notifier (REQ-E1.5), a failed self-check, a denial (D-23) and an
  operator's answer arriving. A notifier delivery counts as a wake for
  REQ-L1.5's fallback.
  *(Cites: D-49; the relay-cost report (2026-11-09, Sources).)*

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
  fork the record and the sources cannot settle, a hard-disqualifier
  zone, or a proposal this bundle reserves for the operator's confirmation
  (REQ-B1.5, REQ-C1.7, a permission prompt no standing decision covers,
  REQ-G1.2); every other decision is taken with grounds, logged, and shown
  for review.
  *(Cites: D-13; autonomous-safe-decision (Sources); drafting-session
  decision (2026-10-22).)*
  *(Amended at sign-off lens pass 2026-10-24: the reserved proposals added as the
  fourth reason a decision reaches the operator, which REQ-B1.5, REQ-C1.7
  and REQ-G1.2 already required.)*
- **REQ-F1.9** A decision mission control settled that the operator later
  revokes SHALL lower that decision class's autonomy (a decision class is
  the autonomous-safe-decision bucket a decision maps onto, D-13), and the
  hit rate SHALL be visible.
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
  *(Amended at Amendment 4, 2026-11-07: an objective is asked only when
  the operator can decide it from their own work; the rest is settled from
  the repository, a check or a default and said in one line, D-18.)*
- **REQ-F1.13** The guidance level SHALL be a knob, guided by default on a
  fresh installation.
  *(Cites: D-18, D-20; drafting-session decision (2026-10-22).)*
- **REQ-F1.14** Before a human gate, the operator SHALL get a prepared
  packet: what to look at, what changed since they last looked, the risks,
  and the order.
  *(Cites: D-25; drafting-session decision (2026-10-22); the hub record
  (Sources).)*
- **REQ-F1.15** When mission control presents a merge recommendation or a
  ready flip it requests or offers, or the operator states an intent to
  merge, it SHALL state at every guidance level the cadence audit's result
  for the pull request's head: which configured steps are covered and which
  are gaps, or that the audit could not run and why. At `guided` it SHALL
  also say in plain words why a gap matters and recommend closing it first;
  at `standard` it SHALL add the recommendation alone; at `expert` the
  one-line result stands alone; an unaudited result carries no lesson. The
  guidance level SHALL never soften or skip a gate, pre-select an option,
  or withhold the result.
  *(Cites: D-31, D-33; the operator priority (2026-11-04) (Sources).)*
- **REQ-F1.16** The panel SHALL activate in every mission-control session,
  however it started (the skill command typed in a plain session, the
  launcher's mission-control kind, a handover successor), with no
  environment variable, restart or launch flag on the operator's side; a
  session mission control launches SHALL NOT inherit the activation. Where
  the host cannot load mods, mission control SHALL say so once in plain
  words and use the text panel (REQ-F1.2).
  *(Cites: D-37; audit item 6 (Sources); the operator priority (2026-11-04)
  (Sources); obs:cf5bce54.)*
- **REQ-F1.17** The panel and the text panel SHALL show each live
  session's spend since it started, in dollars, priced from its own
  transcript usage with `config/token-prices.tsv`, and the program's total
  for the current UTC day across every session that ran in it, with the
  share spent by mission-control sessions (registry kind
  mission-control), so supervision overhead shows before a daily limit is
  crossed. A session whose spend cannot be read, or whose model has no
  price, SHALL show unknown, never zero, and a total missing any session
  SHALL be marked partial. The figures are display only and feed no
  budget.
  *(Cites: D-50; the relay-cost report (2026-11-09, Sources).)*
- **REQ-F1.18** A pull request that changes anything the operator sees
  (a path on the shipped operator-visible list, `mission_control_visible_paths`,
  which each project may extend: the panel mod, the text panel, the
  digest lines, the guide) SHALL stay a draft until the operator has
  approved a preview built from the real render of that change, rendered
  over fixture data and never the live program's figures, and never a
  mock-up. Mission control records the approval in the program's decisions
  log with the operator's own words and the preview's digest, and quotes it
  in the pull request; a worker never records it. Once the readiness gate
  ships, the readiness check SHALL refuse a flip of such a pull request
  with no matching recorded approval; until then the approval is recorded
  by hand the same way.
  *(Cites: D-50; the relay-cost report (2026-11-09, Sources).)*

- **REQ-F1.19** (extends REQ-F1.10) Every operator ask that carries an
  action, and every duty or promise mission control takes on, SHALL get a
  ledger item when it is made, written by the mission-control tier's own
  deterministic path and not from the session's memory: each operator
  message is recorded as an intake row on arrival, the intake rows form a
  durable queue of asks, and neither a turn nor a handover (REQ-L1.6) can
  end while an intake row is neither made into an item nor dismissed with a
  one-line reason (a question, an acknowledgement). An item carries an
  owner, a trigger and a done-condition: a command whose exit status says
  done, an event of an emitted class (REQ-F1.22), a date, or the operator's
  own confirmation. An item with no done-condition is refused at add.
  *(Cites: D-56; REQ-F1.10; the follow-up ledger report (2026-11-10,
  Sources).)*
- **REQ-F1.20** Overdue items SHALL lead the status. An item is overdue when
  its trigger has fired and it is still open and unacknowledged
  (REQ-F1.21). The panel and every plain-language status answer list the
  overdue items before anything waiting on the operator and before
  in-flight work, one line each naming the item, how overdue it is, its
  done-condition and its owner.
  *(Cites: D-56; the follow-up ledger report (2026-11-10, Sources).)*
- **REQ-F1.21** The handover self-check (REQ-L1.6) SHALL fail while an
  overdue item is unacknowledged, naming each. An acknowledgement is a
  ledger record by the session that states what it will do next and a new
  date or event; it never closes the item, and only the next sweep or
  `close` with evidence ends it. The successor reads the ledger and applies
  the same rule.
  *(Cites: D-56; REQ-L1.6; the follow-up ledger report (2026-11-10,
  Sources).)*
- **REQ-F1.22** An event trigger SHALL name an event class something emits:
  `followup add` validates the class against the emitted set (the event
  kinds the shipped watchers declare, REQ-E1.2, and those the event store
  emits) and refuses an unknown class, naming the known ones, unless the
  call carries a fallback date, which is then stored as a date trigger in
  the same call. An existing item whose class nothing emits is listed by
  the audit (REQ-F1.23) and never deleted.
  *(Cites: D-56; REQ-E1.2; the follow-up ledger report (2026-11-10,
  Sources).)*
- **REQ-F1.23** An item SHALL close only through `close` with evidence, and
  a stale-open audit at bring-up, at each handover and daily SHALL flag
  every open item whose done-condition is already met (its command check
  exits success, an event of its class was seen after it opened, the pull
  request it names merged) as a proposal to close it with that evidence.
  The audit never closes an item itself and edits nothing else.
  *(Cites: D-56; the follow-up ledger report (2026-11-10, Sources).)*
- **REQ-F1.24** An audit of mission control's own state SHALL find what
  should be a durable queue and is not, at bring-up, at each handover and
  daily: for every kind of state mission control holds that something is
  waiting on (operator decisions, merge-ready announcements, relayed
  questions, pending prompts, follow-ups, intake rows), a shipped register
  names its store and the disposition that removes an entry from it, and the
  audit flags a kind with no register row, a kind whose store is a
  transient file, a session's memory or a message not yet persisted, and a
  kind whose entries have no recorded way out. A kind the register records
  as deliberately not a queue carries a one-line reason. Each flag is one
  plain line with the remedy (join the queue model, or record the reason),
  and the audit edits nothing.
  *(Cites: D-56; REQ-F1.10, REQ-F1.19; the follow-up ledger report
  (2026-11-10, Sources); drafting-session decision (2026-11-10).)*

## REQ-G — Permissions at scale

- **REQ-G1.1** The launcher SHALL deliver the right permission profile to
  every session, so a sanctioned command never prompts.
  *(Cites: D-10; obs:eea622de, obs:5cc481d6, obs:849b32d5, obs:a0b33b4b.)*
- **REQ-G1.2** A permission prompt that reaches the queue SHALL be answered
  by a standing decision in the tower-comms standing-decision record when
  one covers the command (coverage is that record's literal command
  prefixes, with its refusal of a rule that reaches a reserved control),
  strictly inside its rule, and otherwise surfaced once with its command.
  The mission-control rule store (REQ-B1.1) holds mission control's own
  behaviour rules; an entry there that would answer a prompt is proposed
  into that record (REQ-B1.5), never applied from the store.
  *(Cites: D-5, D-7; tower-comms D-12 (Sources); obs:fd1824a4, obs:3ea8cd0d.)*
  *(Amended at sign-off lens pass 2026-10-24: the store that answers prompts
  named, since only the tower-comms record carries command coverage.)*
- **REQ-G1.3** A hook, guard or classifier denial SHALL be reported with its
  exact text and SHALL never be routed around by any session mission
  control runs.
  *(Cites: D-23; the invocation seed (Sources), failure mode 10; the hub
  record (Sources).)*
- **REQ-G1.4** Mission control SHALL NOT edit a settings file or widen its
  own posture; a settings change it proposes (REQ-B1.5) is handed to the
  operator ready to apply.
  *(Cites: D-2; tower-front-door D-14 (Sources); kickoff §3 (2026-10-23).)*
  *(Amended at kickoff 2026-10-23: the settings-handover clause added.)*
  *(Amended at Amendment 9, 2026-11-11: a declared register command the
  operator asked for may write machine configuration that an operator-merged
  change already describes (REQ-I1.9); mission control authors no change.)*
- **REQ-G1.5** At bring-up mission control SHALL run a posture check, a
  script the launcher and the skill read alike, confirming the shipped
  mission-control deny floor is in force and the guard hooks are wired. On
  a failure it SHALL say so in one plain line and continue read-only (no
  launch, no answer, no request; its own runtime stores stay writable),
  re-checking on the failsafe tick. The `mission-control` guard tier SHALL
  keep enforcing non-authoring (REQ-A1.3) and the ready-flip policy
  (REQ-I1.2), and its pre-approvals SHALL come from one core-only list of
  script verbs, derived from the scripts the skill and the duty catalog
  invoke, that excludes the raw prompt-answer verb.
  *(Cites: D-32; audit item 1 (Sources); tower-front-door D-14 (Sources);
  obs:bb22668a.)*
- **REQ-G1.6** A permission prompt pending in any session mission control
  supervises SHALL raise an attention event keyed by session and prompt,
  waking mission control by push (REQ-E1.3); re-detection is a no-op and
  the event clears once the prompt is no longer pending. Mission control
  SHALL answer a prompt only through the tower-comms answer channel, which
  re-checks REQ-G1.2's standing-decision coverage, or with the operator's
  own answer to that prompt (REQ-A1.5), never through the raw answer verb.
  A prompt in a session whose backend has no answer channel (tmux) SHALL be
  surfaced once with its command and take only the operator's own answer,
  delivered by the pane relay (D-23); a standing decision is never typed
  into a pane.
  *(Cites: D-35; audit item 3 (Sources); tower-comms D-12 (Sources);
  obs:3845960c.)*
  *(Amended 2026-11-08, operator ruling relayed through the hub: "can't it
  be fixed from the root so we don't really need to do it?". The plugin's own
  PreToolUse hook SHALL approve, for a mission-control session only, exactly
  one simple command per verb: the literal resolved path of the installed
  plugin root's `scripts/fleet-streamjson.sh` followed by `pending ...` or
  `answer ...`, with no shell expansion, compound, pipe, redirection,
  background marker or symlink out of the installed root; every other shape
  stays unapproved. This removes the per-release settings bump the user-scope
  allow rules needed. The guard tier's pre-approval list (REQ-G1.5) keeps
  excluding the raw answer verb, and the exact-path allow-rule discipline of
  `fleet-hardening` REQ-B1.5 and D-20 is unchanged. Settled at the kickoff
  (operator: "Your rule or reply (Recommended)"): the hook approves only the
  call's shape, never its content. An `answer` it lets through SHALL still
  carry either a standing decision covering that prompt (REQ-G1.2, claimed
  through `fleet-attention.sh claim`, which re-checks coverage, before the
  call delivers it) or the operator's own answer to that prompt, and stays
  an undo-ledger entry naming what authorized it (D-24); mission control's
  own judgment never authorizes an answer. "Never through the raw answer
  verb" above therefore means never on mission control's own judgment. A
  mission-control session is one the plugin's own prompt hook marked, with
  the tower-session mark store's bar; in any other session the hook
  defers.)*
  *(Amended at Amendment 6, 2026-11-09: the prompt's wake is the notifier's delivery to the mission control that answers it, REQ-E1.7; a direct unit's prompts go to its launching mission control, REQ-D1.15; who may answer is unchanged.)*
  *(Amended at Amendment 7, 2026-11-10: a session moved to another program, REQ-D1.16, is supervised by the destination's mission control from the move; its pending prompts raise their events there and not in the source.)*

- **REQ-G1.7** A lease SHALL be the one way a worker is allowed, for a named
  purpose and a short time, something a standing rule denies. A lease is a
  record naming its kind, one worker session, its scope (paths or the rule
  it lifts), its expiry, whether it is single use, and the operator
  authorization it rests on. Only mission control opens one, and only
  after the operator's yes naming the worker, the kind and why (the
  undo-ledger entry of D-24 cites it); the store lives in the program home,
  outside every worktree and unwritable by the worker tier. A lease closes
  when the worker reports its unit done or is retired, or at expiry
  (`mission_control_lease_ttl`, shipped: one hour, never longer than a
  hard cap), whichever comes first. A lease never lifts a row of the worker
  profile's Bash `deny` block, never covers another worker, and a lease
  that is expired, closed, missing or unreadable reads as no lease, in
  every consumer, through one shared reader.
  *(Cites: D-57; D-24; the rule-enforcement ask (2026-11-10, Sources).)*
- **REQ-G1.8** While a lease is open mission control SHALL show it in the
  status (worker, kind, expiry), and a unit whose worker held a lease
  SHALL carry it into the readiness record: the pull request's top names
  the lease and the leased paths it changed as a posture change the
  operator decides on, and the ready-to-merge notice is not sent as an
  ordinary ready.
  *(Cites: D-57; r-30's pull request shape (Sources).)*
- **REQ-G1.9** The guards' denials SHALL be measured, not assumed: a script
  counts the denials in the fleet records per guard and rule, joins each to
  the command it refused, and reports for each rule the share of refused
  commands that did not contain the act the rule protects (counts and
  refusal texts only, never conversation content), naming what the records
  cannot see. The shipped denial table (D-59) is its first run, and a rule
  is loosened or removed only where this data shows it mostly blocks work
  that was not the act.
  *(Cites: D-59; the denial-friction ask (2026-11-11, Sources); the fleet
  denial records (2026-11-11, Sources).)*
- **REQ-G1.10** The mission-control guard tier SHALL refuse a command that
  writes a settings or configuration file, and SHALL NOT refuse a command
  for naming one: a plain read (grep, cat, jq, a pager, a listing), a
  follow-up or message whose text quotes a name, and a path used as a
  read argument pass. A name through an expansion or an interpreter that can
  write still refuses.
  *(Cites: D-59; REQ-G1.4; the denial-friction ask (2026-11-11, Sources).)*
- **REQ-G1.11** A guard's reserved-act rule SHALL fire on an act in command
  position, and SHALL NOT fire on an act's words appearing only as data: a
  quoted argument, a here-document body that feeds a file write or a
  non-interpreter, a test or file name, a commit or comment text. Text
  handed to an interpreter that can run it (a shell, python3 and the other
  wrappers the guard lists) still refuses when it names an act.
  *(Cites: D-59; REQ-G1.3; the denial-friction ask (2026-11-11, Sources).)*
- **REQ-G1.12** A command or process substitution SHALL be read, not
  refused unread, where its body is one simple command the guard can check
  with the same rules at one level of depth; a body it cannot parse, a
  nested substitution, backticks and ANSI-C quoting stay refused when the
  command's text names an act.
  *(Cites: D-59; the denial-friction ask (2026-11-11, Sources).)*
- **REQ-G1.13** A command name given as a leading `~/` path, as the plugin-root variable the launcher exports, or as a
  variable the same command assigned a literal path earlier, SHALL be
  resolved by the guard to the path it names and judged as that command;
  only a name that cannot be resolved to a literal refuses.
  *(Cites: D-59; the denial-friction ask (2026-11-11, Sources).)*
- **REQ-G1.14** A worker's `git merge`, `git pull` or `git rebase` of the
  pull request base (`origin/main`) or of the origin branch of its own unit
  into its own unit branch SHALL be admitted whether it is run from its
  worktree or through `git -C` naming that worktree; any other source, any
  protected branch and any other worktree stay refused.
  *(Cites: D-59; REQ-I1.4; the denial-friction ask (2026-11-11, Sources).)*
- **REQ-G1.15** A `gh api` request whose method and endpoint are literal and
  are not a reserved act (a merge, a ready flip, a branch deletion, a
  protected push) SHALL be admitted whether its body is a literal field or
  is read from a file or standard input, and a download flag such as
  `--output` SHALL be admitted on a read; the body's content never decides
  admission, and a message to a person stays under REQ-I1.3.
  *(Cites: D-59; REQ-I1.3; the denial-friction ask (2026-11-11, Sources).)*
- **REQ-G1.16** Mission control SHALL be able to type into a tmux pane that
  its launcher registry lists and whose foreground process is a plain shell,
  and never into a pane running a Claude session or into any pane the
  registry does not list; the text typed is checked as a command by the same
  rules (REQ-G1.11).
  *(Cites: D-59; REQ-A1.4; the host-act ask (2026-11-11, Sources).)*
- **REQ-G1.17** The launcher SHALL export the plugin root every guard needs
  to every session it starts, bring-up's posture check (REQ-G1.5) SHALL fail
  plainly when a launched session lacks it, and a guard that finds it unset
  SHALL name the one-line fix rather than refuse every call.
  *(Cites: D-59; REQ-G1.5; the fleet denial records (2026-11-11, Sources).)*
- **REQ-G1.18** Every loosening in REQ-G1.10 to REQ-G1.16 SHALL ship with a
  corpus of refusing cases for the lines it keeps (a merge helper run in
  command position under `merge_policy` human, a push to a protected branch,
  a history rewrite outside the rules, a message to a person, a secret
  read), and the guard suites SHALL fail if any of these stops refusing.
  *(Cites: D-59; REQ-I1.1, REQ-I1.3, REQ-I1.4; the denial-friction ask
  (2026-11-11, Sources).)*

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
- **REQ-H1.4** A program SHALL declare its state sources: for each fact
  class (work items, code state, decisions, deadlines, designs) the
  authoritative source and its access mode, `record` (a store planwright
  writes, directly or through a session mission control dispatches),
  `snapshot` (an adapter refreshes an age-stamped copy, D-12) or `cited`
  (links and the operator's statements only; never polled, never claimed as
  known). The default map is the specs as `record` for work items,
  decisions and deadlines (the dates the specs and the operator state), the
  forge as `snapshot` for code state, and `cited` for designs and for any
  class the map leaves out; a tracker, document store or design tool is
  `cited` until an adapter exists. Mission control SHALL name a source's mode and age wherever it
  reports from it, and SHALL say so when a fact class has only a `cited`
  source.
  *(Cites: D-8, D-12; kickoff §5 (2026-10-23).)*
  *(Added at kickoff 2026-10-23: programs whose public state lives in a
  tracker or document store rather than the specs had no decided source
  map.)*
  *(Amended at sign-off lens pass 2026-10-24: `record` reworded so it does not
  read as mission control editing a repository (REQ-A1.3); the default map
  completed for deadlines, designs and unlisted classes.)*
  **Superseded-by: REQ-H1.5** (2026-11-04).
- **REQ-H1.5** (supersedes REQ-H1.4) A program SHALL declare its state
  sources: for each fact class (work items, code state, decisions,
  deadlines, designs, platform) the authoritative source and its access
  mode, `record` (a store planwright writes, directly or through a session
  mission control dispatches), `snapshot` (an adapter refreshes an
  age-stamped copy, D-12) or `cited` (links and the operator's statements
  only; never polled, never claimed as known). The `platform` class (the
  releases of the host tools and platforms the program builds on) admits
  only `snapshot` and `cited`. The default map is the specs as `record` for
  work items, decisions and deadlines (the dates the specs and the operator
  state), the forge as `snapshot` for code state, and `cited` for designs,
  platform and any class the map leaves out; a tracker, document store or
  design tool is `cited` until an adapter exists. Mission control SHALL
  name a source's mode and age wherever it reports from it, and SHALL say
  so when a fact class has only a `cited` source.
  *(Cites: D-8, D-12, D-39; kickoff §5 (2026-10-23); platform-currency
  D-14 (Sources).)*

## REQ-I — Invariants

- **REQ-I1.1** Mission control SHALL never merge.
  *(Cites: human-gates (Sources).)*
- **REQ-I1.2** Mission control SHALL never flip a PR ready outside the
  configured policy, and in a repository the operator does not own (an
  employer's or another organization's) only on the operator's request.
  *(Cites: D-10; human-gates (Sources); the hub record (Sources).)*
  *(Amended at sign-off lens pass 2026-10-24: "work repository" replaced, since
  the doctrine uses that term for the repository the tasks change.)*
- **REQ-I1.3** Mission control SHALL never send to a person without the yes
  on the exact text and recipient; standing exceptions exist only as named
  configuration.
  *(Cites: D-20; the hub record (Sources).)*
- **REQ-I1.4** Mission control SHALL never rewrite published history except
  on the operator's explicit request in the same turn, inside the
  repository's rewrite scope and never from a standing decision (the
  human-gates force-push row), SHALL never push to a protected branch and
  SHALL never delete a remote branch.
  *(Cites: D-10; human-gates (Sources); the invocation seed (Sources).)*
  *(Amended at sign-off lens pass 2026-10-24: the force-push row's same-turn
  request condition carried instead of an implied free rewrite in scope.)*
- **REQ-I1.5** Mission control SHALL never open a kickoff unasked and SHALL
  never sign off a spec. A kickoff or amendment the operator asks for runs
  in a session mission control launches and relays; every kickoff question
  is operator-only, answered with the operator's own words (REQ-A1.5) and
  never settled from the record; the relay-or-manual mode is a knob, relay
  by default, and `manual` (the operator runs the kickoff command) is the
  operator's own configured exception to REQ-A1.4.
  *(Cites: D-2, D-20; human-gates (Sources); tower-front-door REQ-D1.3
  (Sources); kickoff §2 (2026-10-22).)*
  *(Amended at kickoff 2026-10-22: relayed kickoff and the mode knob
  added; the tower's offer-never-start limit lifted per D-2.)*
- **REQ-I1.6** Company data SHALL stay local and in company systems; the
  program home is never committed to a work repository.
  *(Cites: D-8; security-posture (Sources); the hub record (Sources).)*
- **REQ-I1.7** Ready-when and merge-recommendation conditions SHALL be
  configurable per program, repository, label or path as data, and SHALL
  never place a flip or a merge below the floors `human-gates` states.
  *(Cites: D-26; drafting-session decision (2026-10-22); the hub record
  (Sources).)*
- **REQ-I1.8** A kickoff or amendment mission control relays (REQ-I1.5)
  SHALL be able to publish its own result under a kickoff permission
  profile the launcher delivers: a plain push of the one spec branch its
  launch record names, the draft pull request for that branch and the pull
  request's configured ready flip. The profile SHALL admit no force push,
  no branch deletion and no other branch; the launch record it reads is
  written before the session starts, where that session cannot write; and
  mission control itself gains no push. The core protected floor admits
  this one push only once the routed human-gates amendment lands (Task 31).
  *(Cites: D-36; audit item 4 (Sources); the operator priority (2026-11-04)
  (Sources).)*
- **REQ-I1.9** The host-act lane (REQ-A1.13 to REQ-A1.17) SHALL leave every
  invariant above in force: mission control itself still runs no git
  mutation and edits no repository (REQ-A1.3), a host-chore session never
  merges, never pushes (bar the sign-off-checked spec push of REQ-A1.17),
  never rewrites history, never sends to a person and
  never reads or writes a secret, and a guard denial inside the lane is
  reported with its text and never routed around (REQ-G1.3). The one
  precise exception is that a host-chore session may fast-forward the one
  named primary checkout to its remote default branch, which is content the
  operator already merged, and run the register's declared command, which
  may write the machine's configuration; mission control authors no
  configuration change (REQ-G1.4), and a changed posture takes effect only
  at its next restart followed by the posture check (REQ-G1.5).
  *(Cites: D-60; REQ-A1.3, REQ-G1.4; human-gates (Sources); the host-act ask
  (2026-11-11, Sources).)*

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
- **REQ-K1.7** The knowledge base SHALL hold a mechanism inventory: a
  living source (D-9) listing what the host and planwright can make
  deterministic, each row naming the mechanism kind, the mechanism, where
  it is configured and the source it was read from, refreshed against the
  installed versions; mechanization proposals (REQ-B1.5) map a repeat onto
  a row and never onto a mechanism absent from it.
  *(Cites: D-9, D-14; kickoff §3 (2026-10-23).)*
  *(Added at kickoff 2026-10-23.)*

## REQ-L — Limits and budgets

- **REQ-L1.1** Every duty and watcher SHALL declare its cost and cadence.
  *(Cites: D-17; obs:0c4456bb.)*
- **REQ-L1.2** A per-program budget SHALL bound sessions, source polls per
  hour (every snapshot-mode source counted), spend class, context steps and
  host load, with a declared degradation ladder.
  *(Cites: D-17; quota-handling (Sources); obs:4d47cc6b, obs:6ee76cba,
  obs:fde746e3.)*
  *(Amended at the 2026-11-04 extension: its session and host-load bounds
  are per-program ceilings beneath the host-shared admission of
  REQ-L1.7.)*
- **REQ-L1.3** Mission control SHALL hand over to a fresh session before its
  context budget runs out.
  *(Cites: D-17, D-29; context-budget-autoheal (Sources); obs:2f52c84a.)*
  **Superseded-by: REQ-L1.8** (2026-11-04).
- **REQ-L1.4** Budget headroom and watcher expiries SHALL be visible.
  *(Cites: D-6, D-17; obs:d75dd699, obs:7e67fe74.)*
- **REQ-L1.5** The handover trigger SHALL use measured context percent where
  the harness exposes it, the completed-wake count otherwise (a wake is one
  duty trigger or one operator turn; its ceiling is a `mission_control_*`
  knob), and a compaction-count ceiling in either case.
  *(Cites: D-29; research: Claude Code mods API (Sources);
  context-budget-autoheal (Sources).)*
  *(Amended at the 2026-11-04 extension: the trigger applies to a
  launched holder only, REQ-L1.8.)*
  *(Amended at the 2026-11-07 amendment: the trigger applies to every
  session, attended or launched, again, REQ-L1.9.)*
  *(Amended at Amendment 6, 2026-11-09: where the host exposes no percent,
  the measured context is the transcript reading of REQ-L1.10.)*
- **REQ-L1.6** The handover SHALL be automatic and lossless where the harness
  allows: the successor is launched, rebuilds, proves it holds the active
  rules and open items against the predecessor's last ledger entry, takes
  the program name, and the predecessor retires itself; the operator sees
  one line. A handover that cannot complete unattended SHALL fall to one
  operator act, never to a degraded session.
  *(Cites: D-30; drafting-session decision (2026-10-22).)*
  *(Amended at the 2026-11-04 extension: a launched holder's handover;
  an attended session compacts instead, REQ-L1.8.)*
  *(Amended at the 2026-11-07 amendment: an attended session hands over
  through a pane beside it, or the one operator act, REQ-L1.9.)*
  *(Amended at Amendment 6, 2026-11-09: a launched holder with no operator at its terminal hands over itself at a natural break, REQ-L1.11.)*
- **REQ-L1.7** Launch admission SHALL be dynamic on two axes, the
  account's usage headroom and the host's capacity (load against cores,
  available memory), each with a `mission_control_*` threshold knob, and
  shared by every program's mission control on the host through one locked
  host-level reservation store; `fleet_max_parallel_units` caps the
  host-wide total and is never the target. REQ-L1.2's per-program bounds
  stay ceilings beneath it.
  *(Cites: D-41; the operator priority (2026-11-04) (Sources).)*
- **REQ-L1.8** (supersedes REQ-L1.3) A mission-control session that mission
  control launched itself (a registry holder) SHALL hand over to a fresh
  session before its context budget runs out (REQ-L1.5, REQ-L1.6). An
  attended session (the operator typed the skill command in their own
  terminal) SHALL leave a full context to the host's compaction, made safe
  by the post-compaction step (REQ-B1.3, REQ-B1.7), and SHALL raise no
  handover act or item for context; only a failed self-check becomes an
  operator item. Running mission control as a launched session the operator
  attaches to stays available, never required.
  *(Cites: D-42; the operator priority (2026-11-04) (Sources).)*
  **Superseded-by: REQ-L1.9** (2026-11-07).
- **REQ-L1.9** (supersedes REQ-L1.8) Every mission-control session,
  attended or launched, SHALL hand over to a fresh session before its
  context budget runs out (REQ-L1.5, REQ-L1.6). An attended session (the
  operator typed the skill command in their own terminal, or it took the
  name in a pane beside an attended predecessor) SHALL work down the
  handover ladder, falling to the next rung whenever one does not end with
  its successor holding the program name: first, its successor opened in
  a new split of its own window through a pane adapter whose read-only,
  local probe passes (tmux, and best-effort other terminals), keeping
  Remote Control only when the predecessor had it, the released
  predecessor ending itself, and a successor that does not verify in time
  closed by the predecessor; then one operator act, raised once per
  session; and only as the last resort the host's compaction, made safe by
  the post-compaction step (REQ-B1.3, REQ-B1.7), a self-checked compaction
  not being the degraded session REQ-L1.6 forbids, with each later trigger
  retrying the pane rung.
  The shipped measured-context trigger SHALL be 40 percent for every
  session.
  *(Cites: D-43; the handover-as-best-as-possible ruling (2026-11-06 and
  2026-11-07) (Sources); obs:32bde2c6, obs:3b1fad05, obs:b632d19a.)*
  *(Amended at Amendment 6, 2026-11-09: the ladder starts at the next natural break, REQ-L1.11.)*
- **REQ-L1.10** Every mission-control session, attended or launched, on
  every backend (a terminal session, tmux, stream-json), SHALL have a
  context reading: the percent of its model's context window its last
  assistant turn used (input, cache-read and cache-creation tokens), read
  by `scripts/mc-context.sh` from the tail of the transcript its registry
  row names, never from a path given as an argument. The runner SHALL take
  one reading per session per wake and record it in the program's records;
  `scripts/mc-handover.sh due` and the panel read that record. Where the
  host gives the session a percent, that value is used and the panel says
  which source it shows. A reading that cannot be taken SHALL read the
  literal `unknown`, so the wake-count fallback applies, never zero.
  *(Cites: D-46; the context-reading reports (2026-11-08 and 2026-11-09,
  Sources).)*
- **REQ-L1.11** A mission-control session whose trigger is due SHALL hand
  over at its next natural break: the act in hand has ended and no new one
  started, and no launch, relay or answer of its own is half done, as an
  in-flight record in the program's records shows. While it waits, D-43's
  compaction deferral and its cap hold, and the wake and compaction
  ceilings still force the handover. A launched holder with no operator at
  its terminal SHALL write the handover file and launch its successor
  itself (REQ-L1.6) after exactly one handover-due wake. Where the backend
  can carry it, the successor SHALL keep the predecessor's session name,
  so a message addressed to that name after `take` reaches the successor;
  until `take` finishes a script forwards what the predecessor receives,
  verbatim, and the predecessor acts on none of it. A failed `take` leaves
  the name and the program with the predecessor. A successor arms no
  handover before its own first reading is below the trigger. Where the
  backend cannot carry the name, the handover falls to D-43's rung 2.
  *(Cites: D-47; the context-reading reports (2026-11-08 and 2026-11-09,
  Sources); the operator's scope for Amendment 6 (2026-11-09, Sources);
  obs:3b1fad05.)*

## REQ-M — Throughput

- **REQ-M1.1** One snapshot per snapshot-mode source per program per
  cadence, age-stamped, SHALL be shared by every duty; no duty polls a
  source on its own. The forge is the shipped snapshot source.
  *(Cites: D-12; obs:8b694bdb, obs:b1b85008; the hub record (Sources);
  kickoff §5 (2026-10-23).)*
  *(Amended at kickoff 2026-10-23: generalized from the forge to every
  snapshot-mode source.)*
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
  *(Amended at the 2026-11-04 extension: the measures the panel reads are
  written in its shape, D-40; obs:06c6841d.)*
- **REQ-M1.9** Every dispatch suggestion mission control makes SHALL come
  from the orchestrator's own selection, so a task whose own or
  dependency's repository the selection withholds is never suggested.
  *(Cites: D-40; obs:5d662727.)*
- **REQ-M1.10** The throughput duty SHALL run an idle-wait audit at each
  handover and at least once every `mission_control_idle_audit_interval`
  (shipped: one day): from the program's step, flight and dispatch records,
  the forge snapshot's CI timing (REQ-M1.1) and the attention store, it
  finds where units sat idle waiting on something they did not need (a CI
  result a step does not consume, a quiet or cadence timer, steps run one
  after another that do not depend on each other, a relay through another
  session), and brings the operator each as a mechanization proposal in
  D-14's form, naming the change and the time it would save per day (the
  measured waits of that kind in the audit window, scaled to a day),
  without D-14's repeat threshold. A declined proposal stays declined as
  D-14 says. The audit changes nothing it reads.
  *(Cites: D-51; the relay-cost report (2026-11-09, Sources).)*

- **REQ-M1.11** The throughput duty SHALL also report idle capacity, at each
  handover and at least once every `mission_control_idle_audit_interval`
  (REQ-M1.10's cadence): a reachable configured or known offload host left
  unused while work ran elsewhere, free worker slots while ready units
  queued, and a host far under its load cap over the window. Each finding
  is a mechanization proposal in D-14's form naming the knob that would
  change it, its present value and the proposed one, and the idle measured
  (for example slot-minutes) in the window, without D-14's repeat
  threshold. A declined proposal stays declined as D-14 says, and the
  audit changes nothing it reads.
  *(Cites: D-58; REQ-M1.10; the idle-capacity report (2026-11-10,
  Sources).)*

## REQ-N — Program goals

- **REQ-N1.1** A program goal SHALL carry its own done-when check: a plain
  statement of the outcome and, where one fits, a command whose exit status
  proves it. Mission control SHALL draft the check when the goal is set and
  the operator SHALL confirm or correct it; a goal whose check is
  unconfirmed is reported as such, never as done.
  *(Cites: D-44; the operator's request (2026-11-07, Sources).)*
- **REQ-N1.2** Mission control SHALL report a goal done only after its
  confirmed check passes: the command exits 0, or, where no command fits,
  a read-only session it launches reports evidence that the outcome holds,
  which mission control records. A goal names the work it tracks (pull
  requests, flights or spec tasks), and that work's merge triggers its
  check. Merged
  pull requests SHALL never count as a pass. A goal whose work merged while
  its check fails or has not run SHALL be reported as merged but not done,
  naming what failed, and its fix routed without the operator asking.
  *(Cites: D-44; the offload-host case (Sources).)*
- **REQ-N1.3** A done goal whose check is a command SHALL be re-checked
  once a day and at every bring-up; a failure SHALL reopen the goal with
  one line to the operator naming what now fails, and route the fix. A
  session-based check SHALL not re-run on its own. A passing re-check SHALL
  say nothing.
  *(Cites: D-44; the operator's request (2026-11-07, Sources).)*
- **REQ-N1.4** Goals and their checks SHALL live in the program home
  (D-8), never in a repository, written under one lock. A check command is
  data the operator confirmed, shown to them verbatim before they confirm:
  mission control drafts only commands that change nothing, a goal stores
  no secret (a command reaches a host
  through the operator's existing access), and it runs with a timeout,
  from the program home, with no value from a forge, a session or a record
  interpolated into it.
  *(Cites: D-44, D-8; security-posture (Sources).)*

## Changelog

- 2026-10-22 — Drafted (`/spec-draft`): the requirement groups and
  design decisions this bundle lists, elicited from the invocation seed, the hub
  record, four pending notes (cited, not consumed), the observations
  accumulator and the mods research; shape settled as the core bundle with
  the duty seam, the larger duties routed to follow-on bundles.
- 2026-10-22 — Kickoff §2 (meaning-class, pre-merge, in place): REQ-I1.5
  reworded so a kickoff the operator asks for runs relayed in a launched
  session, with every kickoff question operator-only and a relay-or-manual
  knob; resolves the contradiction with the Goal and REQ-A1.6. D-2 lists
  the lifted limit; Task 15 carries the fixture.
- 2026-10-23 — Kickoff §3 (meaning-class, pre-merge, in place): REQ-A1.1
  and REQ-A1.7 reconciled: an operator-asked launch by name against a live
  holder is the resume and runs as the REQ-L1.6 handover, and only a launch
  that is neither that nor a handover successor refuses; the entry point
  stated as the skill
  command with the program-name argument. Task 11 carries the command;
  Task 16 carries the racing-successor fixture.
- 2026-10-23 — Kickoff §3 (meaning-class, pre-merge, in place): REQ-B1.1
  gains the subject field and the direct entry of an operator-stated
  decision; REQ-B1.2's conflict made mechanical (a shared subject);
  REQ-B1.5 widened to mechanization proposals over an open list of kinds,
  grounded in a new mechanism inventory (REQ-K1.7), with settings changes
  handed over ready to apply (REQ-G1.4). D-5, D-9, D-14, D-16 amended;
  Tasks 2, 8, 9 and 15 carry the work.
- 2026-10-23 — Kickoff §3 (meaning-class, pre-merge, in place): REQ-D1.6
  names the reclaim backup destination (the program home, per repository
  and branch, verified by size and hash) and makes the audit-file set a
  knob; D-8 and Task 4 carry it.
- 2026-10-23 — Kickoff §4 (meaning-class, pre-merge, in place): the push
  wake REQ-E1.3 and REQ-M1.2 promise gets its decision in D-6 (the mod
  watches the attention store and submits when idle; the daemon runner
  relays where the mod does not load; the tick stays the failsafe); Tasks 5
  and 7 carry it.
- 2026-10-23 — Kickoff §5 (meaning-class, pre-merge, in place): Task 15's
  behavioral fixtures move from "run in CI" to on demand with a recorded
  cadence step gating the ready flip, because the repository's CI-eval
  exclusion guard forbids evals in CI; the test-spec coverage mix says so.
  Task 7 wires the panel's plugin tests into the `check` aggregate, which
  nothing had done.
- 2026-10-23 — Kickoff §5 (meaning-class, pre-merge, in place): REQ-H1.4
  added (the per-program state-source map with `record`, `snapshot` and
  `cited` modes); REQ-A1.2 and REQ-M1.1 generalized from the forge to
  snapshot-mode sources; D-8, D-12, D-18, D-22, D-27 and D-28 amended;
  state-source adapters (Jira, Notion, Figma named) become a fifth
  follow-on bundle Task 14 seeds; Tasks 1, 5, 7 and 11 carry the seam.
- 2026-10-23 — Kickoff §5 (meaning-class, pre-merge, in place): D-1 and the
  altitude paragraph name the duty catalog the one operator-facing extension
  point and the snapshot adapter contract a seam later planwright bundles
  implement, resolving the cross-file reading the §5 lens pass raised; Task 5
  retitled for source snapshots.
- 2026-10-24 — Kickoff §6 (meaning-class, pre-merge, in place): Task 10
  depends on Task 4 (the reclaim predicate it runs); Task 13 depends on Task
  10 (the duties its operator doc describes); Task 15's cadence step gates
  this bundle's still-open units and every follow-on bundle's units, not
  "later units" alone; the skill's non-dependence on the default duties is
  recorded as deliberate.
- 2026-10-24 — Kickoff §7 (meaning-class, pre-merge, in place): D-8 gains the
  format field on every program-home store, the additive-only rule and the
  per-launch rollout of the launcher; D-28 records deploy and migration and
  versioning scheme as decided; Tasks 2, 8 and 16 check the field.
- 2026-10-24 — Sign-off lens pass (meaning-class, pre-merge, in place), from
  the brief's lens table: REQ-A1.7 (who retires the predecessor), REQ-F1.8
  (reserved proposals as a reason to reach the operator), REQ-F1.9 (decision
  class defined), REQ-G1.2 (the tower-comms record answers prompts), REQ-H1.4
  (`record` reworded, default map completed), REQ-I1.2 (repository the
  operator does not own), REQ-I1.4 (the force-push row), REQ-L1.2 (source
  polls), REQ-L1.5 (wake count and knob); the out-of-scope merge line
  aligned with human-gates; REQ-A1.5's citation corrected to the tower
  skill's rule; annotations added where the kickoff had amended without one
  (REQ-C1.7, REQ-G1.4, REQ-A1.2, REQ-M1.1, D-16, D-22).
- 2026-10-24 — Sign-off lens pass, design and tasks: D-5 and D-9 (prompt
  store, monthly log segments, lock holder), D-8 (program home in a
  human-owned location per storage-classes, no credential held, runtime
  state stays in the data home), D-10 and D-28 (the `mission-control` guard
  tier), D-11 (the `unknown` state), D-13 (decision class), D-17 and D-29
  (source polls, wake count), D-18 (knob remembered in the machine-local
  layer), D-21 (instruction-hygiene's order), D-23 (citation), D-24
  (`subject`), D-27 (deadline-watch's day-one sources); Tasks 1, 3, 4, 5, 7,
  8, 9, 10, 11, 13, 15 and 16 per the brief (CI wiring through
  `check:non-test`, the CI CLI pin raised to the mods floor, the knob
  inventory and copied-section checks, the tier and its fixtures, one
  fixture per Gherkin arm, edges 2→9 and 8→16, Done-when clauses made
  evaluable); test-spec entries paired with each.
- 2026-11-02 — Delta kickoff (meaning-class, brief Amendment 1): D-18
  remembers the guidance level in the adopter layer rather than the
  machine-local one, since the machine-local file sits inside a checkout
  where mission control writes nothing (REQ-A1.3). Raised by Task 11.

- 2026-11-04 — Extended (`/spec-draft --extend`, reopen cycle: stored
  Ready to Draft over a derived Done), then revised at the reopened delta
  kickoff's lens pass: a Goal paragraph and Scope bullets on working
  smoothly for every operator level; REQ-A1.8 (tower handover), REQ-C1.8
  (presented duties are armed), REQ-D1.9 to REQ-D1.12 (cadence audit at
  readiness, launch worktrees, cadence in launch briefs, adoption and
  liveness on every backend), REQ-E1.6 (step timeouts), REQ-F1.15 (the
  cadence result at merge and flip moments, shaped by the guidance level),
  REQ-F1.16 (the panel with no setup), REQ-G1.5 (posture check and one
  pre-approval list), REQ-G1.6 (prompts wake mission control and are
  answered through the tower-comms channel or the operator's own answer),
  REQ-H1.5 superseding REQ-H1.4 (the `platform` fact class), REQ-I1.8 (a
  relayed kickoff publishes its own spec branch), REQ-L1.7 (dynamic,
  host-shared launch admission), REQ-L1.8 superseding REQ-L1.3 (attended
  sessions compact, launched holders hand over), REQ-M1.9 (suggestions from
  the orchestrator's selection); amendment notes on REQ-D1.2, REQ-L1.2,
  REQ-L1.5, REQ-L1.6 and REQ-M1.8; D-31 to D-42, with amendment notes on
  D-8, D-10, D-11, D-17, D-18, D-22, D-25, D-28, D-29 and D-30; Tasks 17
  to 32. Mission-control observations mined and consumed as listed under
  Sources.
- 2026-11-05 — Expression-only (brief Re-anchor, test-spec pointer): the
  REQ-G1.5 test entry names `tests/test-policy-guard-mission-control.sh`
  for the edit and git-mutation denials, which that suite pins, rather than
  the command-guard suite. Operator ruling relayed by mission control; no
  requirement or decision changes meaning.

- 2026-11-07 — Amended (meaning-class, operator-declared, signed off at
  the amendment kickoff): REQ-L1.9 superseding REQ-L1.8 and D-43
  superseding D-42 (every session hands over; an attended one opens its
  successor in a pane beside itself, falls back to one operator act, and
  compacts only as a last resort; the shipped context trigger is 40
  percent); amendment notes on REQ-A1.4, REQ-L1.5, REQ-L1.6, the Out of
  scope list, D-28, D-29 and D-30; Task 33 superseding Task 30, with Task
  29's dependency moved to it.

- 2026-11-07 — Amendment 4 (post-merge, meaning-class, on the Active
  bundle): specs kept true to what ships and goals checked by outcome.
  REQ-D1.13 (the readiness check refuses a flip over spec drift or an
  unsigned spec edit), REQ-N1.1 to REQ-N1.4 (program goals with
  operator-confirmed done-when checks, reported done only on a pass), two
  Scope bullets; D-44 and D-45; Tasks 34 to 37 (Task 36 routes the router
  and flight rules to tower-front-door). Drift the spec-drift audit found
  in this bundle, brought up to what shipped: REQ-D1.14 supersedes
  REQ-D1.9 (the spec-only hold, PR #852); notes on REQ-B1.5 and D-14 (the
  denial repeat, PR #835), REQ-F1.12 and D-18 (the first run asks only what
  the operator can answer, PR #822), D-32 (launched mission-control
  sessions in auto mode, PR #859), D-33 (the spec-only hold), D-22 (the
  routed tower-front-door amendment, Task 36) and Task 19 (its push half
  landed in PR #866). Revised at the delta lens pass (see the kickoff
  brief's Amendment 4).
- 2026-11-08 — Amendment 5 (meaning-class, on the Active bundle): the
  plugin's own hook approves mission control's exact `fleet-streamjson.sh
  pending` and `answer` calls, so approvals survive every release without a
  settings rule; an answer still needs a standing decision or the
  operator's own answer. Notes on REQ-G1.6 and D-35; Task 38 and its test
  entry under REQ-G1.6 (see the kickoff brief's Amendment 5).
- 2026-11-09 — Amendment 6 (meaning-class, on the Active bundle): cheaper
  supervision. REQ-L1.10 (a context reading for every mission-control
  session, from its own transcript), REQ-L1.11 (the handover at a natural
  break, a headless holder handing over itself, the session name kept),
  REQ-D1.15 (direct dispatch of reviews and read-only checks), REQ-E1.7
  (a notifier for prompts and finished units, batching for the rest),
  REQ-F1.17 (spend per session on the panel), REQ-F1.18 (operator-visible
  changes stay draft until a preview from the real render is approved),
  REQ-M1.10 (the throughput duty's idle-wait audit), REQ-A1.9 (the
  bring-up drift audit); D-46 to D-52; Tasks 39 to 46; one In scope and one Out of scope bullet; notes on REQ-L1.5,
  REQ-L1.6, REQ-L1.9, REQ-G1.6, REQ-D1.14, D-23, D-25, D-29, D-30, D-35 and
  D-43 (see the kickoff brief's Amendment 6). Folded in later the same
  day (relayed, settled): REQ-B1.8 (a rule's enforcement field) and
  REQ-A1.10 (the doctor lists prose, unknown and closed-fix rules), D-53,
  Task 47.
- 2026-11-10 — Amendment 7 (meaning-class, on the Active bundle): REQ-D1.16
  (a live session moved between programs), REQ-D1.17 (reviewers that
  review only once a pull request is ready are asked to review the draft
  first, with a per-reviewer fallback to waiting after the flip); D-54, D-55;
  Tasks 48 and 49; notes on REQ-D1.8, REQ-D1.12 and REQ-G1.6.

- 2026-11-10 — Amendment 8 (meaning-class, on the Active bundle, relayed by
  the hub): the follow-up ledger forgot asks and duties (REQ-F1.19 to
  REQ-F1.24: automatic items with a done-condition, asks kept in a durable
  queue, overdue items lead the status, handover verify fails on
  unacknowledged overdue items and open asks, event triggers validated at
  add, a stale-open audit, an audit of state that should be a queue; D-56);
  operator rules that
  planwright enforces (REQ-B1.9 to REQ-B1.12, REQ-G1.7, REQ-G1.8: clauses
  the worker tier's guard keeps, shadow mode, one lease shape, the headed
  browser rule as the worked example; D-57); and the doctor and throughput
  duty gaps (REQ-B1.13, REQ-A1.11, REQ-A1.12, REQ-M1.11: a knob rule's
  required value checked, hard-sounding rules without a clause listed, idle
  capacity reported; D-58). The runner calling `followup due` each pass is
  REQ-F1.10's and ships as its own flight; REQ-A1.9, REQ-A1.10 and REQ-M1.10
  already cover number-valued rules, prose or unknown enforcement and idle
  waits and are not redrafted. Tasks 50 to 56.
- 2026-11-11 — Amendment 9 (meaning-class, on the Active bundle, relayed by
  the hub): denial friction measured and removed, and a host-act lane. The
  guards' denials were counted from the fleet records (D-59): REQ-G1.9 to
  REQ-G1.18 loosen the rules that mostly blocked work that was not the act
  (a settings-file name in a read, act words in data, an unread
  substitution, a `~/` command name, a worker syncing its own branch, a
  `gh api` body from a file, a plain-shell pane, an unset plugin root) and
  keep the hard lines with refusing tests; REQ-A1.13 to REQ-A1.17 and
  REQ-I1.9 add the operator-asked host-act lane, run by a host-chore session
  from a register that ships no act and takes its rows from an overlay
  (D-60), with the fast-forward-only exception and the sign-off-checked spec
  push stated narrowly. Walk answers: interpreter text that names an act
  stays refused, typing into registry-listed plain-shell panes only, raw
  spec-branch pushes stay refused. A guard refusal log (so counts cover
  interactive sessions) was left unanswered by the operator and is recorded
  as deferred. Tasks 57 to 67.
- 2026-11-11 — Expression-only (brief Re-anchor, test-spec file pointers):
  the REQ-A1.9 test entry names `tests/test-mc-config-doctor.sh`, and the
  REQ-L1.9 entry also names `tests/test-mc-handover-tmux.sh`, the files the
  per-file test-time budget split moved those cases into. No requirement
  or decision changes meaning.
- 2026-11-11 — Expression-only (brief Re-anchor, launch-test split file pointers):
  the REQ-D1.10 and REQ-D1.11 test entries name
  `tests/test-mission-control-launch-worktrees.sh`, and the REQ-D1.16 entry
  names `tests/test-mission-control-launch-host.sh`, the files the per-file
  test-time budget split moved those cases into. No requirement or decision
  changes meaning.
- 2026-11-12 — Expression-only (brief Re-anchor, after the main merge):
  the recorded anchor is refreshed after merging main's expression-only
  test-file pointer edits into the amendment branch. No requirement or
  decision changes meaning.

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
- **The mission-control audit (2026-11-04)** — a read-only audit of the
  shipped mission control at release 0.65.0, kept with the operator's
  records, listing gaps between the bundle and what an operator meets.
  Items 1 to 7 are this extension's, cited as `audit item <n>`: (1) the
  documented start has no posture check and its invariants are prose only;
  (2) the configured cadence is checked nowhere outside the ready-flip
  helper; (3) sessions mission control did not launch go unsupervised and
  their pending prompts never surface; (4) a relayed kickoff cannot push its
  spec branch; (5) the launcher creates no worktree; (6) the panel never
  activates; (7) nothing covers taking over from a tower. Items 8 to 11
  (launcher owner rows, the release-window check, stray files in a primary
  checkout, testing a pull request's plugin version) are routed to separate
  flights. Evidence for
  gap 3 from another program's mission control: three stream-json workers
  sat on unanswered permission prompts for eight days with nothing
  surfacing them.
- **The operator priority (2026-11-04)** — "our priority for now is to make
  mission-control work smoothly for any kind of operator, extra newby or
  expert", with the example that a newcomer would have wanted to be told
  not to push a pull request without reviewing it even once. Rulings in the
  same session: the worker limit is driven by account and computer limits
  dynamically; most people want the panel without setting it up; a relayed
  kickoff gets its own narrow push permission; the four smoothness fixes
  from the observations are in scope; in an attended session a full
  context is left to the host's compaction and its post-compaction
  self-check, accepting that compaction can lose conversational nuance a
  successor reading a handover file would keep.
- **The in-flight cadence fix (2026-11-04)** — the visual flight on
  branch `planwright/flight/mc-launch-cadence`, unmerged when this was
  written: a read-only `audit` verb in `scripts/step-run.sh`, a `cadence`
  evidence row in `scripts/mc-readiness.sh` that refuses a walk with a gap,
  an audit at another head or no audit, a cadence section the launcher adds
  to repository-changing briefs, the skill reporting a pull request as
  ready only through the readiness check, and a doctrine note. D-33, Task
  17 and Task 18 describe what that fix delivers.
- **platform-currency D-14 (draft bundle, 2026-11-04)** — the
  platform-currency bundle needs a `platform` fact class in the state-source
  map, admitting only `snapshot` and `cited`, before its duty can read
  platform snapshots.
- **Observations consumed (2026-11-04)** — the mission-control fragments
  this extension covers, archived in the same commit: obs:cf5bce54,
  obs:855b725a, obs:3845960c, obs:bb22668a, obs:a89108b6, obs:380ade20,
  obs:3b7be7a7, obs:a6112066, obs:06c6841d, obs:b8d064cc, obs:5d662727
  (obs:855b725a is cited in D-37 as the record that the launcher's
  mission-control kind landed). Fragments
  left live: internal speed and refactor notes (obs:fe8f2648,
  obs:ea11bd32), a load-reading fallback current hosts never reach (obs:f8cb8d43),
  items other bundles own (obs:14399ba2, obs:edfc0ca9, obs:6d91e632),
  a prose dependency already landed plus a format-lint idea (obs:f3bc9c7a),
  proposal refinements (obs:190f117b, obs:8e998e2c) and the narrower flip
  scope the operator left to a follow-on (obs:279d8ddd).
- **The handover-as-best-as-possible ruling (2026-11-06 and 2026-11-07)**: the
  operator's amendment of D-42, relayed through mission control: "the idea
  is what we talked about before, to handover as best as possible and
  compact potentially as last resort". At the amendment walk: "Maybe do
  out best effort to emulate what we do with tmux in whatever tool we are
  in at the moment, some terminals allow tmux-like commands"; and, on the
  40 percent context trigger (the program's standing rule) as the shipped
  default, "It's fine as a default but is there a good way to find a good
  default?", deriving it from measured cost per turn being a follow-on.
  After sign-off (2026-11-07), relayed by the hub: only the hub keeps
  Remote Control; a successor keeps it only when its predecessor had it,
  other mission-control sessions getting none by default.
- **Observations consumed (2026-11-07)**: obs:32bde2c6 (attended
  self-succession in a tmux pane, with the by-hand finding that a
  successor must start under a profile whose prompts the fleet can
  answer) and obs:b632d19a (the `path` and `offer` verbs, now rung 2 of
  the handover ladder), archived in the same commit. Cited and left live:
  obs:3b1fad05, whose 40 percent default this amendment ships and whose
  natural-break trigger it does not cover.

- **The operator's request (2026-11-07)** — relayed by mission control:
  flights that change behaviour a spec covers must update that spec in the
  same change; security, CI and guard work routes to the spec pipeline
  unless the operator overrides it, the override recorded; a program goal
  carries its own done-when check and is reported done only after it
  passes.
- **The offload-host case (2026-11-07)** — the Mac offload goal was
  reported done when its pull requests merged, while that host still ran
  an old planwright and had no CI runner registered.
- **The spec-drift audit (2026-11-07)** — a read-only audit mapping which
  merged flights changed behaviour a spec describes without amending it:
  of the flights merged since 2026-11-04, eight specs (mission-control
  among them) describe behaviour a flight changed with no amendment, and
  ten flights did hard-disqualifier-zone work with no routing override on
  record, each resting on the operator asking for the change or on mission
  control's launch brief.
- **The operator's ruling on spec-only pull requests (2026-11-05)** — spec
  bundle pull requests skip the code review cadence steps and are marked
  ready on green CI, mergeable and the kickoff sign-off.
- **The context-reading reports (2026-11-08 and 2026-11-09)** — relayed
  from another host's mission-control hub: an attended session cannot
  measure its own context, so the 40 percent handover never fired for it
  (it handed over near 46 percent only when told); headless stream-json
  supervisors have neither a reading nor an automatic handover, one
  transcript reaching about 44 MB. The workaround that worked: sum the
  input, cache-read and cache-creation tokens of the last assistant usage
  record in the session's own transcript. The attended tmux self-handover
  (PR #902) covers the successor path inside tmux, not the reading.
- **The relay-cost report (2026-11-09)** — the same hub, one day measured:
  two supervising mission controls cost far more than the workers they
  supervised (about 60 percent of the day's spend was supervision), each
  prompt, draft and report costing a full-context supervisor turn. The
  asks: direct dispatch of units that need no supervisor judgment, a cheap
  relay for prompts and finished units, spend per session on the panel,
  and a self-audit that finds idle waits the operator should not have had
  to spot. Relayed by this program's mission control with the operator's
  go-ahead ("lets go with your recommendations"); anything the operator
  sees stays a draft until they approve a preview built from the real
  render.
- **The operator's scope for Amendment 6 (2026-11-09)** — relayed by this
  program's mission control at launch: a context reading for every
  mission-control session, attended and headless, and the 40 percent
  self-handover at a natural break keeping the session name, built first;
  direct dispatch for units needing no supervisor judgment, results in a
  file mission control reads; a cheap relay for permission prompts and
  finished-unit notices; cost per session on the panel, anything the
  operator sees staying a draft until a preview from the real render is
  approved; a periodic self-audit for idle waits, joining the throughput
  duty. Post-pull-request steps alongside CI are a separate flight.
- **The doctor drift note (2026-11-09)** — a pending note captured while
  two drift checks shipped in the bring-up audit (`scripts/mc-config.sh
  doctor`, first shipped as a flight fix with no signed requirement): a
  rule saying mission control hands over at 40 percent sat beside the
  shipped 70 with nothing flagging it, and a dated fleet-size bump in a
  machine-local layer outlived its comment, both found only by hand. The
  operator folded it into this amendment (relayed through the hub,
  2026-11-09: "Fold into held amendment").
- **The rule-enforcement report (2026-11-10)** — relayed through the hub
  from an audit of the rule store: most rules are prose nothing enforces,
  so they drift, are copied between programs and forgotten across
  handovers (dozens of copies, several whose fixes had already landed).
  The operator asked that each rule say how it is enforced and that the
  doctor show which ones only live as prose (the unit brief, 2026-11-10);
  settled to join Amendment 6.
- **The fold-in report (2026-11-10)** — relayed through the hub: when one
  program folded into another (2026-11-09), its live sessions kept their
  old program and owner, so their pending-prompt events went to the old
  program's runner and the new owner had to poll each by hand. A merged
  fix made every pending prompt announced within its own program; this
  asks that a session's owner be movable.
- **The review-on-ready report (2026-11-10)** — relayed through the hub
  from another project's pull request: hosted reviewers configured to
  review on ready reviewed only after the flip (the flip, then the two
  reviewers a minute apart, four threads), so readiness passed before
  their findings landed. Fix asked: readiness knows which bots review on
  ready and the post-flip step waits for and clears them before
  merge-ready is reported (observation W64 of the hub's queue).

- **The follow-up ledger report (2026-11-10)** — relayed through the hub
  (observation W81 of the hub's queue, priority): two due items stayed open
  and unsurfaced and one stayed open after it was resolved; event triggers
  named events nothing emits; the operator's standing ask to make the
  offload host work first never got an item and stayed undone for days. The
  runner-calls-due part is REQ-F1.10's, shipped separately.
- **The rule-enforcement ask (2026-11-10)** — relayed through the hub
  (observation W72): operator rules that planwright enforces
  deterministically, after workers kept opening visible browser windows
  under a prose rule; builds on the signed enforcement field (REQ-B1.8,
  REQ-A1.10). Framed REQ-B1.9 to REQ-B1.12, REQ-G1.7, REQ-G1.8, REQ-A1.12,
  D-57.
- **The idle-capacity report (2026-11-10)** — relayed through the hub
  (observation W80): the offload host knob shipped but stayed local though
  the rules say to offload, and nothing noticed. Framed REQ-M1.11,
  REQ-B1.13, REQ-A1.11, D-58.
- **The denial-friction ask (2026-11-11)** — relayed through the hub (the
  operator's picklist answer "Cut friction, keep the hard lines"): count
  every policy-guard and worker-guard denial, measure how many blocked
  legitimate work, remove or loosen the rules that mostly do, and keep never
  merge, no protected push, no rewrite outside the rules, no message to a
  person without a yes, and no secrets. Framed REQ-G1.9 to REQ-G1.18, D-59.
- **The fleet denial records (2026-11-11)** — the guards' refusal texts and
  refused commands extracted from the fleet workers' event records (the
  stream-json backend), grouped by rule; and the hub's own count of denial
  strings across this machine's session records (relative weight only: the
  records repeat results and tests quote the strings). Neither sees the
  operator's interactive hub session. Framed D-59, REQ-G1.9, REQ-G1.17.
- **The Amendment 9 walk answers (2026-11-11)** — the operator's own words,
  relayed through the hub: host-chore session shape; no built-in host acts,
  the operator's own in the machine overlay; keep refusing interpreter text
  that names an act; yes to typing into listed plain-shell panes only; keep
  the raw spec-branch push refusal, with a host-chore session running the
  spec-push helper for a signed-off spec. No answer was given on a guard
  refusal log. Framed REQ-A1.15, REQ-A1.17, REQ-G1.11, REQ-G1.16.
- **The host-act ask (2026-11-11)** — relayed through the hub (a usability
  gap, fixed now): the operator asked in words for a fast-forward of the
  dotfiles checkout and its playbook run, and the policy guard refused every
  form (the playbook run, a tmux send-keys to a plain shell pane, a
  fast-forward pull in the primary checkout), though standing rule r-29
  says mission control applies merged dotfiles changes itself and r-40 says
  to leave the operator only the irreducible act. Framed REQ-A1.13 to
  REQ-A1.16, REQ-I1.9, REQ-G1.16, D-60.
