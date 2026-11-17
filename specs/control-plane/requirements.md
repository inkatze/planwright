# Control plane — Requirements

**Status:** Ready
**Last reviewed:** 2026-11-16
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright runs its control plane on language-model sessions. Ordering,
approvals, limits, event routing and evidence all live in session context and
in written rules, and at today's scale that layer is lossy, slow and
expensive: a handover rebuilds the picture from a prose brief and loses what
the brief missed, a routine approval costs several model turns at large
context, a missed rule becomes a new rule and the rule load grows, step
records written by a model need truth checks and then audits of the checks,
and every friction the layer causes becomes a planwright pull request that
competes with real work. The cause is one design assumption, that sessions
can be the control plane if given enough written doctrine, and none of the
failures is a missing feature: the things that must never be missed are done
by the component most likely to miss them.

This spec moves the control plane into deterministic code, in three layers
with a hard line between them: **code holds the state and makes every routine
move, models do the work that needs judgment, and the operator sees only
gates.** The routine moves are the approval of a worker's routine prompt, the
dropping of a repeat, stale or off-order event, the landing order and
work-in-progress limit on a launch, continuous-integration hygiene, the
recording of evidence, and the shape of a decision packet. Every limit,
allow-list, landing order and merge mode is data in a configuration file with
a schema, not a code path, so an operator tunes the control plane without
editing it. Merges, sign-offs and anything the operator sees stay the
operator's; merging defaults to the operator, and a policy class may allow
more only where the operator configured it.

The work lands as four slices, each useful on its own, built one at a time
with a design walk before each, and each measured against a baseline taken
before the first. **Slice one, the approval policy engine and event dedupe,
is specified in full here.** Slices two to four (the queue, the reconciler,
briefs from state with a thin hub) are specified as outlined requirements and
design with task stubs, and each is marked for its own design walk, whose
output amends this spec before any of its code is built. Leaf skills
(execute-task, polish, the reviews, kickoff) stay as they are; only their
launch and bookkeeping change. The altitude (a layering line enforced by
mechanism, not one more script) is resolved in D-1 and stated in REQ-A.

## Scope

### In scope

- The approval policy engine: a tested, data-driven allow-list that answers
  routine worker prompts (reads, single tests, lint, step-record writes and
  bounded CI waits inside a worker's own worktree, among others) with no model
  turn, refuses the acts no policy may reach, and hands everything else to a
  model and then the operator. This slice is built first.
- Event dedupe at the source: repeat, stale and off-order events dropped
  before they wake a session, routine events coalesced, and the drops counted.
- Policy as data: schemas and layered configuration for allow-lists, limits,
  landing order, merge mode and the floor of acts no layer may loosen.
- The measurement baseline and the per-slice measured claim.
- Outlined, each for its own design walk: the unit and pull-request queue with
  a dispatcher that enforces landing order and the work-in-progress limit; the
  reconciler that advances queue states, handles continuous-integration
  hygiene and records evidence from machines rather than models; briefs
  generated from queue state, decision packets and a thin hub.
- Folding in the closed mission-control drafts and the open issues this
  control plane addresses, each mapped to a requirement or a stated
  out-of-scope reason (*Sources*, the issue map in `design.md`).
- Folded in at kickoff: a program's per-repository spec roots (REQ-F1.7 to
  REQ-F1.9, with the queue), the operator panel's gaps (REQ-H1.6 to REQ-H1.9,
  with the last slice) and the refused-push rename (REQ-G1.7, with the
  reconciler), each an outline for its slice's design walk.

### Out of scope

- **Gates.** Merging (outside an operator-configured policy class), signing a
  spec off, sending to a person, and anything the operator sees without the
  render gate stay the operator's. No code here performs or authorizes them
  by default. *(Cites: REQ-A1.2.)*
- **Leaf skills' judgment.** Review, polish, kickoff, drafting and execution
  keep their behavior; this spec changes how they are launched and how their
  bookkeeping is recorded, not what they decide.
- **Choosing the compiled-tier language.** Slice one is written in the shell
  the plugin already uses, behind a language-neutral contract (D-16), so a
  later rewrite changes no fixture or policy file; whether the core moves to a
  compiled tier is the universal-binary amendment's decision.
- **The operator-facing prose of mission control's guide** beyond the decision
  packet's shape; the guide's register stays with the mission-control spec.
- **Per-project resource isolation** (databases, migration counters) and the
  other open issues the map names as out of scope, with their reasons.
- **Work-machine content.** Nothing from the work machine's data crosses into
  this spec; its asks are used for the kind of capability they request only.

## REQ-A — The three layers and the line between them

- **REQ-A1.1** Every routine move of the control plane (admitting a worker's
  routine prompt, dropping a repeat, stale or off-order event, enforcing a
  landing order or work-in-progress limit on a launch, advancing a landing
  step, recording evidence, shaping a decision packet) SHALL be made by
  deterministic code from stored state, with no model in the path of the
  decision. A model is consulted only for work that needs judgment, and the
  operator only for gates.
  *(Cites: D-1, D-2; the control-plane design memo (Sources).)*
- **REQ-A1.2** The gates SHALL stay the operator's: no code in this spec
  merges a pull request outside an operator-configured policy class (REQ-B1.7),
  signs a spec off, marks a spec pull request ready, sends a message to a
  person, or shows the operator anything outside the render gate, and the
  approval floor (REQ-C1.5) lists these acts so that no policy layer can allow
  them.
  *(Cites: D-1, D-4; the control-plane design memo (Sources).)*
- **REQ-A1.3** Failure SHALL be asymmetric on purpose. An unreadable,
  unknown-format or ambiguous input to an approval or admission decision SHALL
  refuse or defer it, never allow it, and an unreadable input to an event
  dedupe SHALL deliver the event, never drop it. A control-plane component
  that cannot decide leaves the decision with the layer above it.
  *(Cites: D-4, D-8.)*
- **REQ-A1.4** Every standing rule of the kinds the memo names (ordering and
  limits, continuous-integration hygiene, routine approvals, reporting shape,
  judgment, taste and trust) SHALL have exactly one home, and a rule SHALL
  retire from prose only when its code home's tests have landed and a check
  proves the code refuses what the rule forbade; until then the prose rule
  stands. Rules of taste and trust stay written, as the operator's gates.
  *(Cites: D-2; the control-plane design memo (Sources).)*
- **REQ-A1.5** The control plane SHALL be built one slice at a time: each
  slice has its own design walk with the operator, lands, and is measured
  (REQ-E1.2) before the next starts, and a slice that moves no baseline number
  is rethought rather than followed by another.
  *(Cites: D-13; the control-plane design memo (Sources).)*
- **REQ-A1.6** Leaf skills SHALL keep their present behavior: the control
  plane changes how a unit is launched, supervised and recorded, and no skill
  gains or loses a step of its own judgment through it.
  *(Cites: D-1; the control-plane design memo (Sources).)*

## REQ-B — Policy as data

- **REQ-B1.1** Every allow-list, limit, threshold, window, landing order,
  rank and merge mode the control plane applies SHALL be a value in a
  configuration file with a schema, never a literal in a code path, so that an
  operator changes the control plane's behavior by editing data and a reader
  finds every tunable in one place.
  *(Cites: D-3; the configurability ask (Sources).)*
- **REQ-B1.2** Policy files SHALL layer through planwright's existing
  catalog and configuration resolvers (core, adopter, repository-tracked,
  machine-local), with each key documented in the options reference, and a
  decision SHALL be explainable: an `explain` verb names, for any verdict, the
  layer and rule id that supplied it.
  *(Cites: D-3.)*
- **REQ-B1.3** Every policy file SHALL be checked against its schema by a
  check that runs in the repository's CI and at load. An entry that fails its
  schema SHALL be dropped from its layer (never partly applied) while the
  other valid entries and the lower layers stay in force; a failure in a
  value that bounds a class (its scope, floor or limit) SHALL make the class
  defer everything until fixed (a malformed floor makes floor acts defer and
  fails the check loudly).
  *(Cites: D-3, D-4; REQ-A1.3.)*
- **REQ-B1.4** The approval floor SHALL ship as data that no overlay layer can
  remove or loosen: a layer may only narrow it. A layer entry that tries to
  allow a floor act SHALL fail the schema check and be reported by name.
  *(Cites: D-3, D-4; REQ-C1.5.)*
- **REQ-B1.5** The landing order, the work-in-progress limit, the host-wide
  launch ceiling and the main-work and side-work ranks SHALL be policy data
  read by the dispatcher (REQ-F1.3), so that ordering rules are enforced by
  code from configuration and not restated in prose.
  *(Cites: D-3, D-11; the configurability ask (Sources).)*
- **REQ-B1.6** Every verdict the control plane records SHALL carry a digest of
  the policy that produced it, so that a later reader can tell which version of
  the data decided.
  *(Cites: D-3; REQ-C1.8.)*
- **REQ-B1.7** The merge mode SHALL be policy data that defaults to the
  operator merging. It SHALL reuse the existing merge policy values (the
  operator merges; a person enables auto-merge; a pull request inside a
  declared class merges with no per-pull-request act) and add one reach value
  an operator may configure, whether a release is also merged and published.
  A mode that lets code merge SHALL take effect only in a repository the
  operator owns and no other person works in, never for a spec pull request,
  never for a pull request carrying an unresolved sign-off item, and never
  where merging needs a check bypass, and SHALL be read from the shipped and
  adopter layers only, never from a machine-local file a session could write.
  *(Cites: D-10; the auto-merge ruling (Sources); the configurability ask
  (Sources).)*

## REQ-C — The approval policy engine (slice one)

- **REQ-C1.1** An approval engine SHALL take one structured request and
  return one verdict, `allow`, `deny` or `defer`, with the class and rule id
  that decided. It SHALL be a pure function of the request, the resolved
  policy and a read-only state snapshot: no model, no network, no write other
  than its decision log (REQ-C1.8).
  *(Cites: D-4, D-5.)*
- **REQ-C1.2** A request SHALL come from the harness's own pending-prompt
  record (the worker, its program, the tool, the command as argument vector,
  the working directory, the branch, the request id), never parsed from
  terminal text. A command SHALL be matched on its argument vector after
  quote-aware splitting, and any shell substitution, expansion, redirection to
  a non-scratch path, or construct the matcher cannot fully read SHALL defer.
  *(Cites: D-4, D-5; the closed approval-answer drafts (Sources).)*
- **REQ-C1.3** The engine SHALL ship these classes, each a data entry with a
  scope predicate and its own mode (REQ-C1.6): `read-only` (read verbs of the
  version-control and forge tools and file reads inside the worker's own
  worktree and program checkouts); `own-branch-push` (a fast-forward push of
  the branch the worker's own record names, never a protected branch, never a
  rewrite); `automated-reviewer-reply` (a reply to, or the resolution of, a
  review thread whose author the configured bot patterns match in full, never
  a thread a person has replied in); `release-run` (the publish helper's run
  after the operator merged the release pull request; shipped in shadow, so it
  records what it would answer at every release and answers nothing until the
  operator moves it to enforce); `host-act` (a register of exact commands the
  operator adds, shipped empty); and the three worktree-bound classes of
  REQ-C1.11. A class admits only what its scope predicate and argument-aware
  rules name.
  *(Cites: D-4, D-6; the closed approval-answer drafts (Sources); the memo's
  routine-approvals row.)*
- **REQ-C1.4** An allow SHALL be delivered only for a worker the asking
  session's own program owns, the owner taken from the launcher registry and
  never from the environment, and the answer SHALL describe itself (the
  worker, its program, the first line of the command) so that it reads as a
  legible owned act. An answer is keyed by the request id, and an answer for a
  request that is no longer pending SHALL change nothing.
  *(Cites: D-4; the answer-owner draft and the operator-signed fixes of the
  answer amendment (Sources).)*
- **REQ-C1.5** The floor SHALL be a list of acts the engine never allows under
  any layer, class or mode (it binds what a worker asks the engine to approve,
  not the reconciler's own recorded merge under REQ-B1.7): a merge, marking a
  spec pull request ready, a push to a protected branch, a history rewrite
  outside the operator's stated scope, a message to a person without the
  operator's yes, showing the operator anything outside the render gate, a
  write of a secret, a change to the permission or hook configuration, a
  sign-off, and a deletion of a remote branch. A floor act
  SHALL be answered `deny` with a message naming the floor entry (never a bare
  deny, which kills the worker's session), and counted.
  *(Cites: D-4; the denial-friction draft (Sources); REQ-A1.2.)*
- **REQ-C1.6** Each class SHALL carry a mode, `off`, `shadow` or `enforce`,
  shipped as `shadow`: in shadow the engine records what it would have
  answered beside what the session or operator actually answered and answers
  nothing; only the operator's configuration moves a class to `enforce`, and
  the shadow log is the evidence for that move. Every class ships in shadow,
  none in enforce, and the floor is not a class and is always enforced. A
  class's `enforce` mode SHALL be read from the shipped and adopter layers
  only, as REQ-B1.7 reads the merge mode, never from a machine-local file a
  session could write; a machine-local value is ignored and reported. The
  shadow log is read by the hub (the operator's mission-control session), not
  by the operator: before a class moves to enforce, the hub SHALL bring the
  operator a one-line evidence summary computed by code (counts of the
  engine's would-have answers against the actual answers, with the sample
  size, and each mismatch listed beneath on request), and that summary is the
  gate for the operator's yes. A summary over no records says so and gates
  nothing. The actual answer is the first answer delivered on the request id,
  with its source.
  *(Cites: D-6; the memo's risks (Sources); the class-mode ruling (Sources).)*
- **REQ-C1.7** Every allowed class SHALL have at least one near-miss fixture,
  a request that resembles an allowed one and that the engine refuses or
  defers, and a check SHALL fail when a shipped class has none. Fixtures SHALL
  be language-neutral data, written before the engine's rule they test, and the
  check itself SHALL be shown to fail once against a rule deliberately
  widened.
  *(Cites: D-7; the memo's risks (Sources).)*
- **REQ-C1.8** Every verdict SHALL append one redacted record to a decision
  log: the request digest, class, rule id, mode, verdict, policy digest and
  outcome, with the command bounded in length and never holding a secret, and
  the actual answer and its source where the wiring has recorded one (written
  by the wiring, keyed by request id, never by the engine). The
  log feeds the denial counts and the self-audit, and the engine SHALL count
  denials by floor entry and by class so a rule that mostly blocks ordinary
  work is visible.
  *(Cites: D-4, D-7; the denial-friction draft (Sources).)*
- **REQ-C1.9** The engine SHALL be consulted at the event source, before a
  pending-prompt event is raised or a model turn is spent, and an allow in an
  enforced class SHALL go through the worker's own answer channel with its
  owner check (in shadow nothing is answered, REQ-C1.6). A defer
  SHALL raise the event as it is raised today, so that a miss costs what it
  cost before and nothing more.
  *(Cites: D-4, D-6.)*
- **REQ-C1.10** A check SHALL compare the engine's `read-only` class with the
  read-only command set the worker command guard auto-approves, and fail on any
  command one admits and the other refuses without a recorded reason, so the
  two classifications cannot drift apart.
  *(Cites: D-3; REQ-C1.3; the worker-permission-ergonomics spec (Sources).)*
- **REQ-C1.11** The engine SHALL ship three more classes, each a data entry
  with its own mode, shipped in shadow, and limited to commands whose working
  directory is the worker's own worktree. An entry point is one declared in the
  repository's manifest at the base commit or in operator policy data, never in
  a file the worker changed on its branch, and a path is judged on the argument
  vector after resolving `..` and symlinks. `test-run` is one entry point
  invoked once with an explicit filter naming a single test file, test or
  package (the unfiltered entry point is a full suite and defers); `lint-run`
  is a lint or format-check entry point in check mode with no fix or write flag
  (a rewriting entry point defers even inside the worktree); `evidence-and-wait`
  is a write of the step record whose task and branch equal those in the
  request record, through the recorder helper, and a wait on continuous
  integration carrying an explicit timeout in seconds no longer than a
  configured bound (an unset bound refuses). They exist because the approval
  record shows these, with plain reads, to be nearly all of the requests the
  operator is asked about. Each SHALL have its near-miss fixtures (REQ-C1.7),
  including a command naming a path outside the worktree, a full suite, a
  rewriting lint and a wait with no bound.
  *(Cites: D-4, D-6, D-19; the approval-volume record and the
  slice-one-coverage ruling (Sources).)*

## REQ-D — Event dedupe at the source (slice one)

- **REQ-D1.1** Every control-plane event SHALL pass one gate at its source
  before it is appended, and the gate SHALL key it by kind, subject and the
  subject's state version (a head, a prompt id, a worker generation) with a
  per-subject sequence number.
  *(Cites: D-8.)*
- **REQ-D1.2** The gate SHALL drop a repeat (the same key and an unchanged
  state version inside the configured horizon), a stale event (its subject has
  since moved: the pull request head changed, the prompt was answered, the
  worker retired), and an off-order event (a sequence number below the last
  applied for the subject).
  *(Cites: D-8.)*
- **REQ-D1.3** The gate SHALL never drop the first occurrence of an event of
  the decision, blocker, failure or landed class, and SHALL deliver any event
  whose state it cannot read (REQ-A1.3). A first occurrence of those classes is
  delivered even when it is stale, and an event the gate itself raises
  (REQ-D1.4) bypasses the gate.
  *(Cites: D-8; REQ-A1.3.)*
- **REQ-D1.4** Every drop SHALL be counted by reason and subject kind, with
  the key and no payload, in a ledger an audit reads; a gate that drops more
  than a configured share of a class SHALL raise its own event, so a gate
  that is too keen is visible.
  *(Cites: D-8.)*
- **REQ-D1.5** Routine-class events SHALL coalesce into at most one wake per
  configured window per session, and a session with no event pending SHALL not
  be woken by a timer.
  *(Cites: D-8; work-hub drops 0040 and 0042 (Sources).)*

## REQ-E — Measure the claim

- **REQ-E1.1** Before the first slice's code is wired or enabled (the stall
  watcher hook and the dedupe gate), a baseline SHALL be recorded on the machine it will run on: model turns per day by session role,
  the spend split, merges per day and operator interruptions. The recording
  SHALL be machine-local data, never committed with machine content.
  *(Cites: D-9; the memo's risks (Sources).)*
- **REQ-E1.2** Every slice SHALL name the baseline number it is expected to
  move, and its landing SHALL record the measured change; a slice that moves
  none is rethought before the next slice starts. Slice one's approval classes
  answer nothing in shadow, so the number they move while in shadow is the
  share of prompts the engine would have answered with no mismatch; the change
  in model turns and operator interruptions is recorded at the first class's
  move to enforce, and the dedupe gate's drops and wakes are measured at
  landing.
  *(Cites: D-9, D-13; REQ-A1.5.)*
- **REQ-E1.3** The control plane SHALL be machine-agnostic: every machine
  specific (paths, tracker or chat names, thresholds) lives in an overlay
  layer's policy data, so that one design serves the home machine and a work
  machine, each adopting slice by slice, and no spec or fixture carries content
  from either.
  *(Cites: D-15; work-hub drops 0040 to 0042 (Sources).)*

## REQ-F — The queue (slice two, outlined; design walk before build)

- **REQ-F1.1** One store SHALL hold every unit and pull request as a row (kind,
  state, owner, head, blocker, next step, rank), written only by scripts
  through verbs, never by a session's prose or by hand, format-versioned,
  protected by a lock, and refused when its format is unknown.
  *(Cites: D-11; the memo's slice two (Sources).)*
- **REQ-F1.2** The store SHALL derive from branch, pull request and merge
  evidence and be rebuildable from them, so that a lost or stale store is
  rebuilt and never trusted over the forge; it SHALL hold units of every kind
  (spec task, visual flight, ad-hoc fix, petition, pull-request-only) and
  SHALL read a hard cross-spec dependency edge only between specs under the
  same spec root, written `<spec>:<id>`, and fail closed (the task is not
  started) when the foreign bundle is not readable or lies under another root,
  flagging the edge. A prose-form edge SHALL
  draw a validator warning and never be rewritten.
  *(Cites: D-11, D-17; the dispatch-record issue and the offload petition
  issue (Sources).)*
- **REQ-F1.3** The dispatcher SHALL admit or refuse a launch from the queue
  and the policy: a launch that breaks the landing order, the work-in-progress
  limit, the host-wide ceiling or the account, load and memory holds SHALL be
  refused by code, the refusal naming the rule and the blocker. Main work and
  side work SHALL be told apart by the operator-kept rank list. While a
  higher-ranked unit is ready, a lower-ranked launch SHALL be held, and the
  hold SHALL lapse after a configured time (one hour by default) into a
  choice put to the operator, never into a silent launch.
  *(Cites: D-11, D-18; REQ-B1.5; the launch-admission draft (Sources).)*
- **REQ-F1.4** Every launch SHALL go through one launch seam that applies the
  fixed environment pins, resolves the fleet home from one resolver whatever
  the plugin install mode, and verifies the launched worker's branch and
  worktree against the row, flagging a worker that committed elsewhere.
  *(Cites: D-11; the launch-seam issues (Sources).)*
- **REQ-F1.5** The queue's states SHALL be named, and an operator MAY attach a
  command or skill to a transition through policy data, run by the reconciler
  and never by a session's own initiative.
  *(Cites: D-11; the lifecycle-hooks issue (Sources).)*
- **REQ-F1.6** A unit's goal and its operator-confirmed done-when check SHALL
  be a row attribute, and a unit SHALL be reported done only after that check
  passes, not because its pull requests merged.
  *(Cites: D-11; the goals draft (Sources).)*
- **REQ-F1.7** A program SHALL name one or more work repositories and MAY name
  one spec root. With the root set, it is one path used as is for every listed
  repository, exactly as before. With it unset, each listed repository's root
  SHALL be the one the spec-root resolver answers when run in that repository,
  in any posture the resolver supports. A program that sets the root SHALL
  validate and read with the existing verbs' output byte-identical to before,
  and no existing configuration SHALL need an edit.
  *(Cites: D-20; the spec-roots draft (Sources).)*
- **REQ-F1.8** A unit's spec SHALL be read from the root of the repository it
  belongs to (its row's repository attribute). A spec name that exists under
  two or more of a program's roots SHALL be refused as ambiguous, the unit
  unselectable, until qualified as `<alias>:<spec>` with the repository's name
  in the work-repository registry, the refusal naming every root that holds
  it. Program validation SHALL flag a listed repository whose root the resolver
  refuses or whose root is not a directory, naming the repository and the
  reason.
  *(Cites: D-20; the spec-roots draft (Sources).)*
- **REQ-F1.9** Every reader of a program's spec roots (the queue, the
  readiness check, the deadline scan, the setup and kickoff prose) SHALL obtain
  them from one program reader verb that returns each root with its
  repository, and a check SHALL fail on any script or skill instruction that
  reads the program's root field by another route (the field name appearing
  only in the verb and a named allowlist). The verb is additive, read-only and
  has no side effects. The change SHALL add no root registry, repository map or
  marker of its own, and SHALL leave the floor unchanged: no edit to a
  repository, no launch or retirement, no gate weakened.
  *(Cites: D-20; the spec-roots draft (Sources).)*

## REQ-G — The reconciler (slice three, outlined; design walk before build)

- **REQ-G1.1** A reconciler loop SHALL advance queue states itself: sync a
  branch with its base with the hooks' autofix disabled and refuse to commit
  unless the diff against the base lists only the pull request's own files;
  start and cancel continuous integration, cancelling a doomed run, never
  starting a second run on a flip that an earlier run on the same head already
  covers, and running the macOS shards on a draft before the flip; flip a pull
  request ready only under the ready-flip policy once every check has finished
  (never a pull request carrying the screenshot condition of REQ-H1.9, and
  never a spec pull request, REQ-A1.2); and retire workers whose unit has
  landed.
  *(Cites: D-12; the memo's slice three (Sources); the ready-flip policy issue
  (Sources).)*
- **REQ-G1.2** Evidence of a step SHALL be recorded from continuous
  integration and hooks by code: a step record whose start, head or outcome
  the recorder cannot establish from a machine SHALL be refused, rather than
  written from a model's word and audited later.
  *(Cites: D-12; the step-record truth draft (Sources).)*
- **REQ-G1.3** Each fixed landing procedure SHALL be one idempotent verb a
  poller or a session can call: the post-ready-flip checks, the merge order of
  approved pull requests with their blockers, stale pull requests, the
  post-merge bookkeeping, and why each queued unit waits.
  *(Cites: D-12; work-hub drop 0040 (Sources).)*
- **REQ-G1.4** A host-level poller SHALL run every tick's deterministic inputs
  (pull request state, reviews, conflicts, check state, stuck prompts, usage),
  diff them against its last state and append an event only on a change, with
  no timer waking a session.
  *(Cites: D-12; REQ-D1.5; work-hub drop 0040 (Sources).)*
- **REQ-G1.5** Landing SHALL obey the merge mode (REQ-B1.7): with the operator
  merging, the reconciler prepares and reports the merge-ready state and never
  merges; where the operator configured more, each merge is a recorded act
  re-checked at its last step, and after a release is published the reconciler
  advances the release pull request's label state and raises an event when a
  release was dropped or left unreleased.
  *(Cites: D-10, D-12; the release issues and the auto-merge draft (Sources).)*
- **REQ-G1.6** The reconciler SHALL bound every watcher step with a timeout, take
  a context and cost reading of each session so that a handover is triggered by
  a number and not a judgment, and adopt a live session it did not launch.
  *(Cites: D-12; the step-timeout, context-reading and adoption drafts
  (Sources); work-hub drop 0040 (Sources).)*
- **REQ-G1.7** When a push is refused and the helper's refusal names the branch
  it accepts, and that branch does not exist yet, the push SHALL be renamed to
  that branch and retried through the same guarded helper (not an engine
  `own-branch-push` consultation), with these limits: only to the exact name
  the refusal's own structured field names; only when that branch does not
  exist; the rename recorded in the decision log and the worker's record and
  row updated to the new name together; never with force; never to a protected
  or shared branch (a branch another worker's record names, or whose
  protection cannot be confirmed, counts as protected); one rename per original
  push, a refusal of the retry stopping and being reported with its exact text.
  *(Cites: D-17; the refused-push ruling (Sources).)*

## REQ-H — Briefs from state and a thin hub (slice four, outlined; design walk before build)

- **REQ-H1.1** A worker SHALL be launched straight from a queue row with a brief
  generated from state, the brief kept in the program home so a queued launch
  never points at a scratch file, and the worker SHALL report back to the
  queue.
  *(Cites: D-13; the memo's slice four (Sources); the records-and-routing draft
  (Sources).)*
- **REQ-H1.2** A decision SHALL reach the operator as one packet built from
  state (what it is, why it matters, the options, a recommendation, links to
  the evidence), carrying the cadence result on a consequential moment, and the
  operator's answer SHALL be recorded against the queue row.
  *(Cites: D-13; the cadence-line draft (Sources).)*
- **REQ-H1.3** A standing per-program supervisor SHALL be optional: the hub
  MAY launch workers from the queue directly, and a handover SHALL carry
  nothing the queue does not already hold.
  *(Cites: D-13; work-hub drop 0040 (Sources).)*
- **REQ-H1.4** The model tier of a wake SHALL be policy data chosen per wake
  class, with a small-context triage tier that decides whether a wake needs the
  full hub at all, and a launch's effort SHALL resolve from a unit-size or label
  hint so no hand step is needed.
  *(Cites: D-13; work-hub drops 0041 and 0042 (Sources).)*
- **REQ-H1.5** Every standing rule that remains SHALL say how it is enforced (a
  script, knob, hook, duty or default, an open fix, or prose with its reason),
  and a check SHALL list the rules that live only as prose, so rule retirement
  (REQ-A1.4) is measured; a state-source map SHALL carry the platform-fact
  class so a rule about a tool release cites a source.
  *(Cites: D-2, D-13; the rule-enforcement and platform-class drafts
  (Sources).)*
- **REQ-H1.6** The operator panel SHALL read from the queue and name every
  item by its title (or its kind in words), never by a pull request number,
  session, task, worker or launch identifier, hash, branch name or file path.
  Its in-flight section SHALL list every piece of work in motion (each live
  session grouped by what it is doing, each piece of work with no session
  running grouped as waiting and saying in words why it waits), each item with
  a state symbol and word and how long it has been in that state (from the
  queue row's state-entered time), sorted with the items that need the
  operator first and, when they do not all fit, an "and N more" count per
  state. A working
  session SHALL show its current step in a few words from a fixed vocabulary
  recorded by a hook, never from raw command text, and never a step older than
  its current state. The checked merge command of a ready pull request SHALL
  appear only in that row's opened detail.
  *(Cites: D-21; the panel-gaps draft (Sources).)*
- **REQ-H1.7** The panel SHALL draw context fill, each usage limit, host load
  and memory as an instrument row with values and marks (a reading that cannot
  be read shown as unknown, never zero or full); each usage limit's spend,
  reset time and time remaining, the limit with the highest share used as a
  fuel bar; the
  month's dollar spend and, where the operator sets a monthly budget (unset by
  default), the share spent and its rate; and, per spec with work remaining,
  tasks merged against its total and a count of pull requests per stage, each
  read through an aged snapshot and never on the redraw path.
  *(Cites: D-21; the panel-gaps draft (Sources).)*
- **REQ-H1.8** No meaning in the panel SHALL rest on colour alone: every state
  carries a symbol and a word; no colour is drawn when `NO_COLOR` is set or
  the colour knob is off; the palette stays distinct for colour-blind
  operators; and a plain mode (a knob) shows state words in place of symbols
  and drawing, titles and times unchanged, for a screen reader. The panel mod's TypeScript SHALL be type-checked in CI, the check
  failing on a seeded type error.
  *(Cites: D-21; the panel-gaps draft (Sources).)*
- **REQ-H1.9** A panel change SHALL stay a draft until the operator has seen a
  screenshot of the real panel (rendered over fixture data) and said yes, and
  the pull request SHALL quote that approval.
  *(Cites: D-21; the panel-gaps draft's standing condition (Sources).)*

## REQ-I — Safety and rollout

- **REQ-I1.1** Policy code SHALL be built test-first: the failing fixtures for a
  rule (its allows, its near-misses and its floor refusals) exist and fail
  before the rule does, and the policy engine and reconciler SHALL be listed in
  the repository's guard catalog as safety-relevant code.
  *(Cites: D-7; the memo's risks (Sources).)*
- **REQ-I1.2** One setting SHALL turn the whole control plane to defer
  everything (the approval engine answers nothing, floor acts included, which
  raise the event as today; the dedupe gate delivers everything; the dispatcher
  leaves admission to today's host admission check), restoring today's
  behavior, and every verb SHALL read it first. A kill switch left on SHALL be
  reported at each wake.
  *(Cites: D-14.)*
- **REQ-I1.3** The engine and gate contracts SHALL be language-neutral: a verb,
  a structured stdin record, a structured stdout verdict and exit codes, with
  fixtures as data, so that the implementation language (D-16) is replaceable
  without changing a fixture or a policy file.
  *(Cites: D-5, D-16.)*
- **REQ-I1.4** The decision log, the drop ledger and the queue SHALL hold
  identifiers, digests and bounded strings (the bounded command is the one
  exempt free-text field), and no secret, credential, message body or other
  work content, and a check SHALL scan them for token-shaped values.
  *(Cites: D-4; REQ-C1.8.)*

## Changelog

- 2026-11-15 — Drafted from the operator-approved control-plane design memo
  (decisions: the diagnosis is right, all four slices in one spec built one
  slice at a time, the work machine adopts slice by slice). Slice one is
  specified in full; slices two to four are outlined with task stubs, each
  gated on its own design walk. Three questions are open for kickoff
  (D-16, D-17, D-18) with their recommended defaults drafted.
- 2026-11-16 — Kickoff walk. Settled by the operator: the language (shell now,
  swap later, D-16); cross-spec edges (same root, hard, fail closed) and the
  refused-push rename with its limits (D-17, REQ-G1.7); the main-versus-side
  hold with an hour's lapse (D-18); every class ships in shadow with the hub
  reading the log and the operator gating on its one-line summary, `release-run`
  included (REQ-C1.6, REQ-C1.3); and tests, lint, step-record writes and
  bounded CI waits join slice one (REQ-C1.11, D-19). Folded in as inputs:
  Amendment 19's spec roots (REQ-F1.7 to REQ-F1.9, D-20) into the queue, and
  Amendment 18's panel gaps (REQ-H1.6 to REQ-H1.9, D-21) into the last slice;
  both mission-control drafts are marked superseded at sign-off.

## Sources

- **The control-plane design memo** — a Claude Docs document, operator-approved
  2026-11-15 with "yes to all" (every recommendation). The diagnosis (state in
  context, sessions as a message bus, rules as prose, evidence written by
  models, a queue that fixes itself), the three-layer target, where the
  standing rules go, the four slices in order, and the risks and build rules.
  Framed REQ-A, REQ-C, REQ-D, REQ-E, REQ-F to REQ-I and D-1, D-2, D-6, D-9,
  D-13.
- **The altitude claim.** The memo states the cause as a design assumption, not
  a missing feature, and that "none of this is a missing feature": a pinned
  altitude claim (doctrine and mechanism, not one more script), resolved in D-1.
- **The configurability ask** — operator, 2026-11-15, relayed by mission
  control: as configurable as possible, policy as data (allow-lists, limits,
  landing order, merge policy in files with schemas); merge mode defaults to
  operator merges and a policy class may allow more where configured; address
  as many open issues as possible; test-first, fail-closed, a near-miss
  fixture for every allowed class, gates stay the operator's. Framed REQ-B and
  the safety rules.
- **The closed approval-answer drafts** — pull requests 986 (adopt live
  sessions, answer their prompts) and 1021 (a mission control answers its own
  workers' prompts: an owner-only, argument-aware arm, a read-only vet that
  replays the worker's guards, one verb to resolve an automated reviewer's
  thread). The operator-signed fixes on the local amendment branch
  (`planwright/mission-control/amendment-16`, commit 8459e89c) make the
  answer verb's request id `<request-id>` and say the owner-check work (the
  answer-owner draft) lands before the answer is wired. Framed REQ-C1.2,
  REQ-C1.3, REQ-C1.9.
- **The answer-owner draft** — pull request 1057: `answer` describes itself and
  an owner token may answer only its own program's worker. Framed REQ-C1.4.
- **The denial-friction draft** — pull request 944 (mission-control amendment
  nine): guard refusals counted, rules that mostly block ordinary work loosened
  with every hard line kept, a host-act lane of exact registered commands.
  Framed REQ-C1.3 (`host-act`), REQ-C1.5, REQ-C1.8.
- **The auto-merge draft** — pull request 1013 (opt-in automatic merge and
  release, solo repositories only, spec pull requests never, each merge a
  recorded act re-checked by a short-lived helper). Framed REQ-B1.7, REQ-G1.5.
- **The records-and-routing and step-record truth draft** — pull request 1016:
  a recorder that refuses a record it cannot establish from a machine, briefs
  kept in the program home, a quieter conflict radar, a stand-in reviewer.
  Framed REQ-G1.2, REQ-H1.1.
- **The launch-admission draft** — pull request 1039: one host-shared
  admission check on account, load, memory, host ceiling and program bound.
  Framed REQ-F1.3.
- **The step-timeout draft** — pull request 1041: a bounded watcher step, the
  calibration measures, dispatch suggestions from the orchestrator's own
  selection. Framed REQ-F1.3, REQ-G1.6.
- **The context-reading draft** — pull request 1044: a context reading for
  every session, a handover keyed to it. Framed REQ-G1.6.
- **The duties draft** — pull request 1036: undo, self-audit and proposals
  duties armed with watchers that raise an event only on a change. Framed
  REQ-D1.5, REQ-G1.4.
- **The goals draft** — pull request 1040: program goals with an
  operator-confirmed done-when check. Framed REQ-F1.6.
- **The rule-enforcement draft** — pull request 1045: a rule says how it is
  enforced, and a doctor lists the prose-only ones. Framed REQ-H1.5.
- **The cadence-line draft** — pull request 1031: a decision packet opens with
  the cadence audit's result. Framed REQ-H1.2.
- **The platform-class draft** — pull request 1033: a platform fact class in the
  state-source map. Framed REQ-H1.5.
- **The work hub's design asks** — drops 0040, 0041 and 0042, a work machine's
  asks, used only for the kind of capability they request: an event-only poller
  (REQ-D1.5, REQ-G1.4), idempotent procedure verbs (REQ-G1.3), a shared queue
  and a flatter topology (REQ-F1.1, REQ-H1.3), a main-sync verb that refuses
  to sweep in unrelated files (REQ-G1.1), handover by cost (REQ-G1.6), a
  per-wake model tier and a size-resolved effort (REQ-H1.4), and coalescing
  notification turns (REQ-D1.5). No company, product, person, repository,
  ticket, path or figure from them is carried here.
- **Open issues folded in** — the dispatch-record issue (88), the lifecycle-hooks
  issue (383), the ready-flip policy issue (379), the release issues (173,
  380), the launch-seam issues (341, 545, 547), and the offload petition issue
  (342); the full map, with the out-of-scope reasons, is in `design.md`.
- **The worker-permission-ergonomics spec** — the worker command guard and its
  self-approval policy, whose read-only classification REQ-C1.10 keeps from
  drifting; the fleet-autonomy floor that no model classifier sits in the
  approval path.
- **The mission-control and universal-binary specs** — the layer this spec
  moves into code, and the verdict draft (pull request 1063, pending) that
  recommends Go for the library tier; slice one stays in shell behind a neutral
  contract (D-16, settled).
- **The spec-roots draft (Amendment 19)** — local branch
  `planwright/mission-control/amend-spec-roots`, commit 7d457290: a program's
  per-repository spec roots (its REQ-T1.1 to REQ-T1.5, D-100 to D-103, Tasks 130
  to 132). Folded by the operator's ruling (2026-11-16) into the queue part as
  REQ-F1.7 to REQ-F1.9 and D-20; the mission-control draft is superseded at
  sign-off.
- **The panel-gaps draft (Amendment 18)** — local branch
  `planwright/mission-control/amend-panel-gaps`, commit f88cd454: the panel
  shows what the operator feels is missing (its REQ-S1.1 to REQ-S1.10, D-85 to
  D-89, Tasks 105 to 112, six gaps deferred). Folded by the operator's ruling
  (2026-11-16) into the last part as REQ-H1.6 to REQ-H1.9 and D-21, with its
  standing screenshot condition; the mission-control draft is superseded at
  sign-off. Its deferred gaps (widget catalogue, density layouts, drill-down
  keys, urgency-led band, proposed sections, panel-API docs) carry over as the
  deferred items in the task list's Deferred section.
- **The class-mode, slice-one-coverage and refused-push rulings** — the
  operator, 2026-11-16, relayed by mission control: every class ships in
  shadow and the hub reads the log (REQ-C1.6); tests, lint, step-record writes
  and bounded CI waits join slice one (REQ-C1.11), because the operator's
  approval record shows those kinds to be nearly all of the requests asked
  about (the figures stay machine-local, REQ-E1.1);
  `release-run` ships in shadow; the rename's limits (REQ-G1.7).
- **The cross-spec dependency and main-work drafts** — the local branches
  `planwright/invariant-tasks/amend-cross-spec-edges` (commit 6e74b80c, with
  uncommitted edits in a sibling worktree) and
  `planwright/mission-control/amend-main-work` (commit b52466c9), whose
  drafted defaults were settled by the operator as D-17 and D-18.
