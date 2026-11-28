# Core rewrite — Design

**Status:** Ready
**Last reviewed:** 2026-11-28
**Format-version:** 2
**Execution:** derived — see the status render

Origin-tag legend: `N` = new to this bundle; `C, <namespace> <id>` = carried
from another bundle's decision, the foreign id namespace-qualified; `O` = an
operator decision still open at drafting (none remain: each was settled by
the operator during drafting).

## Decision log

### D-1: Altitude — a framework-core capability under one doctrine line (N)

**Decision:** The deliverable sits at two altitudes. The doctrine line, stated
in REQ-A and shipped as its own rule doc: every rule the pipeline depends on
has a code home that refuses its violation, and a rule an agent must remember
is a defect to close. The capability beneath it: a deterministic core
(program, store, state machine, decision engine, typed verbs, supervisor)
that every adopter gets in planwright's shipped defaults. Planwright's own
values (its allow-list contents, thresholds, model tiers) stay config. The
pinned seed claims (the operator's "make things work mechanically", the hub's
draft brief's "nothing relies on agents remembering instructions") are why REQ-A comes first
and every later group cites a code home.

**Alternatives considered:**
- Mechanism only, one fix per failure. Rejected because: that is the pattern
  that produced the enumerate-the-spellings guards and the record truth checks
  of checks; each fix closes one case and the class stays open.
- Doctrine only (sharper instructions). Rejected because: the recorded
  failures are agents not following instructions they already have.
- A machine-local fix for this host. Rejected because: hub rule r-46 requires
  every operating gap to be fixed in planwright's shipped defaults.

**Chosen because:** the failure is a design assumption (sessions can hold the
line if given enough prose), so the fix must change where the line is held
and say so as doctrine, or the next feature will re-derive the assumption.

### D-2: One prebuilt Go executable with SQLite embedded (N)

**Decision:** The core is one `planwright` executable written in Go, prebuilt
per platform and delivered the way universal-binary's Task 10 designed
(release assets, checksum and provenance, first-use fetch, fail closed). It
embeds SQLite (a pure-Go or statically linked build; FTS5 availability is
confirmed in Task 1) and a shell parser (mvdan/sh). Every shell entry point a
skill calls becomes a shim that execs it. The operator chose Go at drafting
(hub picklist, 2026-11-28: "Yes, Go (Recommended)").

**Alternatives considered:**
- Rust. Rejected because: faster in the hook bake-off, but more source to
  write, a musl and LGPL caveat, a macOS
  cross-compile risk, and no shell parser of mvdan/sh's maturity.
- Stay in shell and harden it. Rejected because: the parser, the single-writer
  store and the process ownership this spec needs cannot be built reliably in
  portable shell (the lock races and tokenizer bypasses in the consumed
  observations are that evidence), and every call forks.
- The Agent SDK as the runtime. Rejected because: it adds a Node or Python
  runtime per host, its docs steer SDK use to API keys, and planwright already
  speaks the control protocol the SDK wraps (the research report).
- A database or queue server (Redis, Postgres, NATS). Rejected because: each
  is a daemon to install and keep up per host, collides with development
  stacks of the same names, and does nothing an embedded store plus one
  optional daemon does not at this scale.

**Chosen because:** universal-binary's bake-off (its unsigned verdict draft)
already measured Go as the
recommended substrate for two tiers, mvdan/sh settles the parser tier, and an
embedded store gives a coworker with no services and a host with the service
the same file and the same semantics.

### D-3: Direct and service modes share the code and the store (N)

**Decision:** Direct mode opens the store per call and needs nothing running;
service mode adds one per-user daemon (systemd user unit on Linux, launchd
agent on macOS) that owns writes, pushes deliveries, runs timers and owns
worker processes. A host enables service mode only by a recorded operator yes
(`planwright host enable service`, a capability row with the words and time).
Decisions are the same in both; only latency and liveness differ.

**Alternatives considered:**
- Service always on. Rejected because: managed laptops may forbid a user
  agent, and planwright must work for a coworker with the plugin only.
- Direct only. Rejected because: a prompt reaching its owner within seconds
  while no session is turning, escalation timers and restart on upgrade cannot
  be promised by processes a model turn starts.

**Chosen because:** one rule (same verbs, same tables, same decisions) keeps
adopters on one code path while letting a host that can run a daemon gain
liveness.

### D-4: One decision engine, tiered, with the floor held twice (C, control-plane D-4, D-5)

**Decision:** The engine is a pure function from (session row, tool call) to
allow, deny with a reason, or ask a named owner, called from the PreToolUse
hook in every session type. Tiers apply in order: floor (every act the
human-gates list names, and self-permission edits, never allowed on policy
alone: one proceeds only on an operator approval record under D-8, performed
by the core's typed verb outside the session, and only where human-gates lets
the operator's yes authorize it), typed verbs, sandboxed local work, the
parser tier, ask. The floor acts are also deny and ask rules in every shipped
settings profile, which Claude Code applies before any hook decision, so no
engine defect loosens them. Unknown, unreadable or ambiguous input asks or
denies, never allows. Every decision is logged with an input digest, which is
the after-the-fact audit hub follow-up f-43 asks for.

**Alternatives considered:**
- A guard per session tier (worker, tower, mission control), as today.
  Rejected because: three tokenizers and three policies drift; the consumed
  observations record the same fix applied twice and missed once.
- Floor held by the hook alone. Rejected because: a hook can fail open on a
  timeout or a missing root; settings rules cannot.

**Chosen because:** one function is testable from fixtures alone, and holding
the floor in settings as well makes the gates independent of the engine's
correctness.

### D-5: The OS sandbox is the boundary; the parser is the fallback tier (N)

**Decision:** Workers and mission controls run under Claude Code's sandbox
where the host has it: writes to the worktree, scratch and shared git
directory (hooks and config denied), every forge credential source masked,
unsandboxed retry off, and `failIfUnavailable` on for a host whose capability
row says it is sandbox-capable; a host without a sandbox runs the parser tier
and logs that it does (D-22). Mission control gets no repository write.
Where no sandbox runs, the parser tier builds a syntax tree with mvdan/sh and
allows only commands whose every judged word is literal after quote removal,
matched against the allow-list; anything dynamic is unknown and asks.

**Alternatives considered:**
- A better tokenizer alone. Rejected because: no static parser resolves
  expansions, `eval`, aliases or a script edited after the check; Claude
  Code's own docs call Bash rules "not a security boundary".
- Deny-lists of dangerous spellings. Rejected because: the record is about
  twenty bypasses across one guard's review rounds and two more on 2026-11-27;
  a deny-list over text does not converge.

**Chosen because:** the OS enforces writes, reads and credentials whatever the
command text says, which turns most of today's prompts into allowed local
work, and the parser tier fails closed for hosts that lack it.

### D-6: Outward acts only through typed verbs; push judges the resolved refs (N)

**Decision:** Push, pull-request writes, ready flip, merge admission, thread
replies, messages, planwright's own records and the kickoff's publish of a
signed spec or amendment branch (bound as REQ-D1.7 states) are typed verbs of the core
(CLI first, an MCP face optional), running outside the sandbox, holding the
credential, and validating arguments against the session's row (its unit
branch, its pull request, its program). The push verb runs git itself and
judges the destination refs a pre-push check receives, so no spelling of the
command line changes what is judged. Free shell text never reaches an outward
act: the sandbox holds no forge credential, and on a host with no sandbox the
parser tier refuses an outward act in shell text rather than parsing it.

**Alternatives considered:**
- Keep pushes in shell and harden the matcher. Rejected because: that is the
  approach the 2026-11-27 bypasses defeated.
- A git wrapper on PATH. Rejected because: it is bypassed by an absolute path
  to git; the credential custody is what makes the verb unavoidable.

**Chosen because:** validating arguments of a fixed verb is decidable, and
judging the resolved refs closes the whole spelling class hub follow-up f-54
names.

### D-7: The engine answers prompts itself, every answer logged (N)

**Decision:** The engine answers a worker's permission prompt for every call
it can decide (allow for the routine classes in policy data, deny for the
floor), logging each answer; only an ask reaches a model or the operator.
This supersedes execution-backends D-5 (a permission prompt is never
auto-answered) and worker-permission-ergonomics REQ-F1.2 (the guard as the only
self-approval mechanism): the engine is the one approval engine, and the
guard it replaces goes away. The operator agreed at drafting (hub picklist,
2026-11-28: "Yes (Recommended)").

**Alternatives considered:**
- Keep the guard-or-model rule and only widen the allow-list. Rejected
  because: the 2026-11-07 replay showed the guard approving almost nothing it
  queued, and every remaining prompt costs a model turn at large context.
- A replay-on-failure answerer only (the pending note's narrowest form).
  Rejected because: it covers hooks that failed, not the measured cause.

**Chosen because:** about 12,500 prompts a week on this host, roughly 830
hours of worker waiting (the research report, seven days to 2026-11-25), are mostly routine shapes code can decide in
milliseconds (the research report), and the floor stays outside the engine's
reach by D-4.

### D-8: Approvals are records; the core performs the approved act (N)

**Decision:** An operator approval is a record the core writes itself from
the operator's own answer, as the harness delivers it at the surface the
operator answers on (a selector answer or a typed reply, read by the core's
hook), never from an argument a model supplies: the operator's quoted words,
the time, the exact text's hash, the act, its target and the commit it
applies to. No model session can write one. A relayed go is the record, not
prose; the core performs the act through its typed verb when a record matches
the act, target and commit and the act's own preconditions hold, and only
where human-gates lets the operator's yes authorize that act. No model carries
authority across a hop, so the classifier is never asked to trust a relay.
Records are single-use unless they carry an explicit scope field with an
expiry; the core never infers a standing scope from the words. The operator
chose this capture at kickoff (hub picklist, 2026-11-28: "The core captures
it (Recommended)").
*(Amended at kickoff 2026-11-28: capture by the core, bound to commit, typed
scope with expiry.)*

**Alternatives considered:**
- Better relay wording. Rejected because: the classifier refuses a relayed go
  by design (it cannot verify provenance); wording cannot fix provenance.
- Signed tokens from the operator's device. Rejected for now because: no
  operator device path exists; the record binds to the operator-facing
  session, and a stronger binding can supersede this later.

**Chosen because:** it removes the refusal class (relayed sign-offs, merge-main
goes, held pushes that stay denied) by taking authority out of model hands.

### D-9: Prompts table, owner inbox, redelivery and escalation (N)

**Decision:** A prompt that needs an answer is stored whole with its owner.
The owner's inbox carries delivered, read and answered states; delivery
repeats until acknowledged; every prompt has an escalation timer ending in an
operator push; a program sees only its own sessions' prompts. In service mode
the daemon pushes within seconds; in direct mode the states hold and the
runner polls.

**Alternatives considered:**
- Today's keeper, runner and steer chain. Rejected because: it has no bound,
  marks events submitted when written, and delivered prompts two to eighteen
  hours late on 2026-11-25.
- A display view with a size cap. Rejected because: the cap and a text filter
  hid long prompts from sweeps.

**Chosen because:** explicit states and timers make lateness visible and
bounded.

### D-10: The core stamps every record from its own clock and git (N)

**Decision:** Step begin and end are verbs; the core reads its clock and the
git head at each and writes the record itself. No record verb accepts a time
or head argument. A prompt- or skill-kind step is recordable only after the
core delivered its prompt and only with times after it. The store and record
files are write-denied to agents (sandbox and file-tool deny), and authority
comes from the session row, so a copied or renamed recorder gains none.

**Alternatives considered:**
- Keep agent-supplied stamps with stronger truth checks. Rejected because:
  checks of agent stamps became checks of the checks, and mission control's
  vetting still caught what they missed.

**Chosen because:** a time the agent never supplies cannot be invented.

### D-11: One state machine for units, points and steps; readiness computed (N)

**Decision:** Units (spec task, flight, mission-control launch), their points
and steps are states of one machine with explicit transitions; verbs refuse
undefined ones. Completion of a point requires a record for every resolved
step; convergence completion also requires the last pass to have applied
nothing. Readiness and the step audit are computed from the store plus the
forge's current state, identically for every unit kind. A session's config is
resolved from its own row.

**Alternatives considered:**
- Keep per-script checks (step-run audit, ready-flip helper, readiness duty).
  Rejected because: they diverge by unit kind (the ready-flip helper serves
  only spec tasks) and read inherited environment.

**Chosen because:** one machine and one readiness computation make "the
cadence ran" a fact the store holds rather than a claim a session makes.

### D-12: Handovers generated from the store and diffed (C, control-plane D-26)

**Decision:** A handover brief is generated from the store (open units, open
requests, commitments, duties, the predecessor's unread inbox) and diffed
against the previous brief; take is refused while a request or commitment is
unacknowledged. A worker that expects to wait past the prompt-cache lifetime
ends and is relaunched from a generated brief when the wait ends. A
supervisor's handover threshold comes from the measured cost-per-turn curve.

**Alternatives considered:**
- Prose briefs written by the outgoing session. Rejected because: items fall
  out (messages sent just before a handover were lost) and writing one costs a
  large-context turn.

**Chosen because:** a generated brief is cheap enough to hand over earlier,
which cuts the cost of every later turn, and complete by construction.

### D-13: The supervisor lives in the core and owns its processes (N)

**Decision:** The core's supervisor spawns the installed `claude` with the
stream-json flags used today, owns the child's pipes with a single writer,
and places each worker in a process group (a cgroup scope on Linux under the
service). Each session has one row; register, recover, relaunch and retire are
single transactions. Liveness is the recorded process, never a scan. After an
update the service re-execs onto the installed version and new sessions start
with the installed root.

**Alternatives considered:**
- The shell FIFO supervisor, hardened. Rejected because: its pipe race is
  documented as unclosable in POSIX sh, frames over the pipe limit are not
  atomic, and nothing owns the process tree.
- Build on Claude Code's own background-agent supervisor. Rejected for now
  because: it is a research preview built for a person watching.

**Chosen because:** process ownership and atomic rows remove the orphan,
lost-owner and stale-root classes together.

### D-14: Replay, then shadow, then live, with a must-never-allow set (C, control-plane D-6, D-7, D-14)

**Decision:** The first slice replays the recorded prompt envelopes offline
through the engine and reports the share settled per tier and every
disagreement, failing hard if a must-never-allow fixture is allowed. Every
live slice runs first in shadow beside the shell path it replaces. Policy and
guard tasks land failing fixtures first, with a positive control. A kill
switch, thrown only on an operator approval record, returns every session to
the retained pre-shim shell path without loosening the floor.
Shell entry points stay as shims until a human-directed removal. Each slice
reports against one baseline taken before the first.

**Alternatives considered:**
- Big-bang cutover over the weekend. Rejected because: the guards are
  security-critical and a regression reaches main or loses work.

**Chosen because:** it proves the headline saving before any live session
changes and keeps every step one switch from undone.

### D-15: The store is rebuildable state plus exported work products (N)

**Decision:** Operational state (sessions, leases, prompts, events, step
records) lives in the store and is rebuildable from git, the forge and the
logs where storage-classes requires it. Work products (rules, follow-ups,
decisions, the request ledger) are exported to their text forms on change.
Step records keep their worktree-cache export so pull-request bodies still
render them.

**Alternatives considered:**
- Everything in the database. Rejected because: it traps operator-owned text
  and breaks storage-classes' rebuild rule.

**Chosen because:** it keeps the doctrine's rebuild guarantee while giving the
core one transactional home.

### D-16: What this spec supersedes, extends and amends (N)

**Decision:** control-plane is superseded whole (its Task 1 baseline stands;
its REQ-A1.3, REQ-A1.4, REQ-D, REQ-I and REQ-J are carried here; every other
requirement and slice stub of it is named carried, dropped or deferred in its
supersession amendment). universal-binary keeps its landed Tasks 1 to 8 and
is amended to retire its unbuilt verdict and migration tasks, its bake-off
data and REQ-B1.1 standing as evidence and constraint here and its Task 10
delivery design carried into Task 3. worker-permission-ergonomics' guard
mechanism is replaced and its outcomes kept; its REQ-F1.2 and
execution-backends D-5 are superseded by new records. Each change is its own
amendment, walked with the operator at its own kickoff (Task 2; the operator
chose this at kickoff, hub picklist 2026-11-28: "Amendment walks
(Recommended)"). Specs this one sits beside and consumes: human-gates (the gate list),
guard-coverage (the fixture corpus), harness-rebaseline (its permission trial
is answered by this spec's replay and shadow data), review-effectiveness,
model-allocation, fleet-autonomy, quota-handling, mission-control. The
operator agreed at drafting (hub picklist, 2026-11-28: "Yes, supersede both
(Recommended)").

**Alternatives considered:**
- Fold into control-plane. Rejected because: control-plane's design assumes
  shell stores and scripts; folding the substrate, guard model and cost scope
  into it would push it past one feature a reader holds in their head.
- Sit beside control-plane and universal-binary. Rejected because: two live
  specs would own the approval engine and the substrate verdict.

**Chosen because:** one design owns the core, and nothing landed is lost.

### D-17: Cost measures are core capabilities with measured defaults (N)

**Decision:** Each cost measure is a capability in the core with a config
knob: the per-run hosted-review rule (once on the final head), the usage
ladder failing closed, model and effort tiers per launch kind and step, the
handover threshold, the idle-wait end. A shipped default changes only with
the measurement that justifies it, cited in the change (for example the
pending Sonnet-review and 200k-handover notes' figures).

**Alternatives considered:**
- Bake planwright's current values in. Rejected because: customization-boundary
  keeps values in overlays unless evidence shows they generalize.
- Leave them as rules for sessions. Rejected because: REQ-A1.1.

**Chosen because:** the mechanism generalizes to every adopter; the values
follow evidence.

### D-18: Review loops size to the diff and stop mechanically (N)

**Decision:** A review pass's lens set is chosen from the diff it reviews;
after the first pass only what the previous pass changed is re-reviewed. The
loop stops on the first pass that applies nothing, and a round cap and
wall-clock budget end it with a recorded outcome. The convergence completion
verb refuses while the last pass applied a change (D-11), so convergence is a
fact, not a claim.

**Alternatives considered:**
- A lower severity floor only. Rejected because: it shortens passes but still
  re-fans every lens over the whole branch each pass.

**Chosen because:** polish was the slowest cadence step (median 25 minutes
over 28 runs on 2026-11-24, 1h10m over 25 runs on 2026-11-26; hub
follow-ups f-44 and f-55), and the
measured causes are full re-fans, passes past the cap and approval waits.

### D-19: CI judges what a pull request touches (N)

**Decision:** The per-file test-time budget fails a pull request only for a
file it touches; an untouched file over budget is retried once, then reported.

**Alternatives considered:**
- Raise the budget. Rejected because: it hides real regressions in touched
  files.

**Chosen because:** runner variance failed a pull request on a file it did not
touch (hub follow-up f-53), costing a CI round for nothing.

### D-20: Pin against bare mode and self-check the hook (N)

**Decision:** Every launch refuses bare mode explicitly, and the core checks on
a session's first tool call that its PreToolUse hook ran, refusing to continue
when it did not.

**Alternatives considered:**
- Wait for the default to change. Rejected because: in bare mode no plugin
  hook runs, so every guard would vanish silently.

**Chosen because:** Claude Code's docs say bare mode will become the default
for `-p`; this lands before anything else depends on hooks.

### D-21: Scope boundary — what waits for its own spec (N)

**Decision:** The shared knowledge base and search receipt (f-50), the
mission-control mod redesign (f-41 item 1) and cross-host transport beyond the
SSH rung are deferred with gates in `tasks.md`; this spec leaves the store
ready to hold them.

**Alternatives considered:**
- Include them. Rejected because: each is a separate concern with its own
  seed, and the core must land first.

**Chosen because:** keeps the bundle to one feature a reader holds in their
head.

### D-22: Host setup stays the operator's; the design needs none of it to work (N)

**Decision:** The sandbox packages on a Linux host (bubblewrap, socat, an
AppArmor profile where needed) and a service unit are operator-approved
dotfiles changes routed by mission control, never tasks here. The design works
without them: no sandbox means the parser tier; no service means direct mode;
a managed laptop that forbids a user agent, a local socket or a local MCP
server keeps direct mode with CLI verbs. For planwright's own Linux host the
operator agreed at drafting to turn the sandbox on, its missing package added
through a dotfiles change (hub, 2026-11-28: "a").

**Alternatives considered:**
- Make the sandbox mandatory. Rejected because: it would exclude hosts that
  cannot install it.

**Chosen because:** a host adds capabilities; it never changes behaviour.

### D-23: Store and executable upkeep with safe defaults (N)

**Decision:** The store and the executable follow one set of upkeep rules,
each value a config setting with a safe default:

- **Schema.** The store carries a schema version. Migrations run forward
  only, each in one transaction, after a snapshot copy of the store. An
  executable older than the store's schema refuses to write it, naming both
  versions.
- **Backups and retention.** A snapshot is taken before every migration and
  on a configured interval, keeping a configured count. The decision log,
  prompts and events carry configured age and size limits, and each pruning
  is itself recorded. Work products export per D-15.
- **Versions.** The executable's version follows the plugin's. Every shim
  checks the executable's version against the installed plugin manifest and
  fails closed with a message on a mismatch.
- **Writers.** In direct mode every write takes the store's write lock up
  front with a configured busy timeout; a timed-out write makes a record verb
  refuse and a decision ask, never allow (REQ-A1.3).
- **Caller identity.** The core derives a caller's session row from the
  identity the harness supplies (the hook input's session id, or the
  supervisor's spawn record), never from an id the caller passes. The service
  mode's local socket is usable by its own user only.
- **Secrets.** Credentials are redacted from prompts, the decision log and
  replay input before they are stored. Store files are user-only and never sit
  inside a repository.
- **Hook time limit.** The hook carries a configured time limit; a decision
  not reached within it asks, or denies on a floor act, and never allows.

**Alternatives considered:**
- Leave each to the task that first meets it. Rejected because: the store is
  shared by every task, so per-task choices would diverge, and the
  decision-domain catalog requires each domain the spec touches to be decided
  or accepted as a risk.

**Chosen because:** the operator chose safe defaults at kickoff (hub picklist,
2026-11-28: "Add it with safe defaults (Recommended)"), and every default
above fails closed in the sense REQ-A1.3 requires.

## Cross-cutting concerns

- **Decision domains crossed:** data storage (D-2, D-15), queues and async
  work (D-9), API surface (D-6), authorization (D-4, D-5, D-7, D-8), secrets
  and configuration (D-5 credential custody, REQ-C1.8), concurrency (D-3 single
  writer, D-13), observability (D-4 decision log, REQ-G1.8), deploy and
  migration (D-14), dependency adoption (D-2: Go toolchain for builds, SQLite,
  mvdan/sh, each through the dependency-adoption checklist in Task 1),
  versioning (D-2 release assets), existing-seam reuse (D-16: the overlay,
  config-knob, rule-doc, execution-backend and notification seams are reused;
  the store is minted, its nearest seam being the machine-local state home,
  which it lives in).
- **Bounds and timers:** every bound this bundle names without a value
  (delivery latency, escalation timer, review round cap and wall-clock
  budget, prompt-cache lifetime, replay window, write-lock timeout, hook time
  limit, retention) is a config setting; the task that delivers it sets the
  default, cites the measurement or source behind it, and its Done-when
  fixture runs against the configured value.
- **Data storage and lifecycle:** D-23 decides migration, backup, retention,
  version matching, writer concurrency, caller identity, redaction and the
  hook time limit.
- **Security posture:** every task touching the engine, verbs, sandbox profile
  or parser gets the write-time security pass for authorization, subprocess
  construction and path handling.
