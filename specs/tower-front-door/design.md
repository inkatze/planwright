# Tower front door — Design

**Status:** Ready
**Last reviewed:** 2026-10-10
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new decision, minted in this bundle's drafting session
(2026-08-27); `E` = extension decision, minted in the 2026-10-10 amendment
drafting session. Foreign IDs are namespace-qualified.

## Decision log

### D-1: Altitude — capability plus doctrine, seams consumed not minted  (N)

**Decision:** The deliverable sits at capability-plus-doctrine altitude.
The flight-rules routing rule and the vocabulary inversion land as
doctrine (a flight-rules doctrine doc, a glossary supersession); the
entrance is a capability seam filled by the `/tower` skill as its
mechanism; every other need is met by consuming existing seams (backend
placement, convergence, attention, permission posture, worker lifecycle)
rather than minting parallels. New mechanism is minted only where a named
seam demonstrably misfits (D-6, D-11), each with a seam-misfit note.

**Alternatives considered:**
- Mechanism-only: ship `/tower` as a skill with the routing rule embedded
  in its prose. Rejected because: the routing rule has three consumers
  (the skill, the docs, the audit record) and doctrine buried in a skill
  is invisible; the seed's altitude claims explicitly assert the
  doctrine framing.
- Doctrine-only: write the routing doctrine and defer the skill. Rejected
  because: the entrance problem is the product gap; doctrine without the
  front door leaves the entry fee in place.

**Chosen because:** the autopilot-reflex altitude gate fired on pinned
seed claims ("the routing principle already exists", "the Rails-like
front door"), and right-altitude placement puts rules-about-thinking in
doctrine and concrete workflows in mechanism.

### D-2: The staged tower inversion  (N)

**Decision:** The entry skill ships as `/tower`, and the vocabulary
inverts: **Tower** is superseded in the glossary to mean the standing
conversational front-door session; **Orchestrator** is minted for the
dispatching `/orchestrate` session. v1 updates only the definitional
sites (spec-format glossary, work-placement consumer naming, the fleet
doc's opening) plus a transitional note; the pervasive prose sweep is
deferred behind a gate; script and config file names (`tower-settings`,
`tower-command-guard`, the fleet tower marker family) are not renamed —
most transfer to the chat tower, whose posture and lifecycle they were
effectively built for. No existing skill is renamed.

**Alternatives considered:**
- Qualified coexistence ("chat tower" vs "dispatch tower", permanently).
  Rejected because: with the tower model as the main selling point, the
  unqualified word inevitably drifts to the chat session in every future
  surface; a permanent two-sense term fights usage forever.
- A different skill name (`/planwright`, or another non-colliding name),
  glossary untouched. Rejected because: the main selling point would
  ship under a secondary name while the strongest word stays attached to
  machinery being demoted from the front page.
- Full one-shot inversion (re-term every fleet/doctrine surface in this
  spec). Rejected because: balloons v1 scope into the instruction-budget
  crisis on doc surfaces, and fleet-mode integration is out of scope
  anyway; staging keeps v1 shippable.

**Chosen because:** the name should belong to the thing being sold;
"orchestrator" already circulates as the second name so the sweep is
cheap; the tower-named assets transfer rather than strand; and the
repo's own precedent for a vocabulary collision (the dual-registry
naming, legacy observations log line 144 — left unconsumed for its own
drain) is resolution by distinct layer names, with the premium name on
the user-facing layer.

*(Amended at kickoff lens review 2026-09-01: the tower-lifecycle
watchdog/relaunch family — `fleet-tower-watchdog.sh`, the
`tower_relaunch_*` knobs — stays orchestrator machinery: the chat tower
does not register under it in v1, and the REQ-H1.1 transitional note
covers those names. The line-144 precedent is cited as the problem that
motivates distinct layer names, not as a resolved precedent.)*

### D-3: Flight rules named visual flight / instrument flight  (N)

**Decision:** The two routing outcomes are **visual flight** (specless)
and **instrument flight** (the spec pipeline), chosen per request by the
tower. Every doc surface glosses the analogy in one sentence at first
use (visual rules when conditions are clear; instrument rules when you
file a plan and trust the gauges).

**Alternatives considered:**
- Quick / filed. Rejected because: "quick" implies the specless path is
  the careless path, the exact impression to avoid.
- Direct / filed. Rejected because: self-explains slightly better aloud,
  but the operator preferred the VFR/IFR pair's semantic precision, and
  the always-stated routing grounds (REQ-B1.3) mean the name never
  stands alone in conversation.
- Split registers (doctrine says visual/instrument, conversation speaks
  plainly). Rejected because: two registers to keep consistent forever,
  and the audit record would still have to pick one.

**Chosen because:** aviation-correct, rhymes with the autopilot/tower
framing, implies no quality gap between the rules, and the mandatory
first-use gloss caps the jargon cost at one sentence per surface.

### D-4: The escalation rule  (N)

**Decision:** Instrument flight is forced automatically by work centered
in a hard-disqualifier zone or otherwise not one-revert-from-undone
(published interfaces, data deletion, external side effects). Ambiguity
(no statable Done-when the user would agree with) escalates by declared
judgment. Size proxies are advisory only. User history is deferred with
a gate. Zone semantics carry two recorded refinements: the fix
*location* governs whether a finding is zone work, and a deliverable
that itself lives in a zone lands behind a draft PR with its
pending-sign-off checklist. Routing is preventive; the gate-wiring hard
pauses stay in force in every worker regardless of route.

**Alternatives considered:**
- Zones-only automatic, irreversibility by judgment. Rejected because: a
  published-API change or an external side effect would then rely on
  judgment, weakening the declared mechanical floor.
- All judgment, stated. Rejected because: the trust story loses its
  verifiable floor; an adopter cannot point at the rule that guarantees
  auth work files.
- Zones + irreversibility + ambiguity all automatic. Rejected because:
  ambiguity is not mechanically detectable; forcing it automatic is
  fake determinism.

**Chosen because:** the zones are already the canonical low-reversibility
list proportionality points at, so the mechanical floor reuses settled
doctrine, and the judgment lane is exactly where stated-grounds
transparency does its work.

### D-5: The override — one sentence, both directions, reservation stated  (N)

**Decision:** "Just do it" forces visual flight and "write this one up"
forces instrument flight, each as a single sentence in chat, never a
config change. When an override crosses an automatic escalation trigger,
the tower states its reservation and the trigger's grounds, then
complies. No override crosses a hard invariant: the backstops (hard
pauses, draft PR, the human's merge) hold on every route.

**Alternatives considered:**
- Two-step acknowledgment for zone overrides (tower names the zone and
  risk, user confirms once more). Rejected because: a deliberate stretch
  of the seed's verbatim trivial-override constraint; the backstops
  already catch the danger, and the friction re-taxes exactly the small
  zone-adjacent asks the feature exists to unblock.
- Zones un-overridable. Rejected because: a comment fix in an auth file
  would pay full spec ceremony with no escape — the entry-fee problem
  reborn.

**Chosen because:** the seed states the trivial-override rule at verbatim
strength, and the invariant layer, not the router, is where safety is
enforced.

### D-6: The audit record — adaptive home, artifact not accumulator  (N)

**Decision:** The record's content contract is fixed (REQ-E1.1; *(Amended
at kickoff delta re-walkthrough 2026-10-10: now REQ-E1.6, per D-20.)*). Its
authoritative home is adaptive and declared at routing time: with a
remote and `gh`, the draft PR body; without, a committed per-flight
record file riding the flight's own branch (the tower cannot write the
default branch and a worker owns only its branch, so the record travels
in the reviewed diff and one revert undoes record and work together).
One file per flight, at `specs/_flights/<flight-id>.md`: a reserved
underscore directory classified as a record directory — screened by the
underscore name rule, skipped by bundle validation, owing no drain
ritual. A local flight index exists only as a derived,
regenerable, never-committed cache under the fleet home. The record is
an audit artifact in the kickoff-brief class, not an accumulator: it
collects no deferred decisions, so it owes no named reader or drain
ritual.

**Alternatives considered:**
- PR body only. Rejected because: every fresh session re-derives from
  the forge, and the no-remote arm has no durable record at all.
- A committed flight-log accumulator (for example `specs/_flights/` on
  the main view). Rejected because: owes the accumulator contract,
  inherits the known silent-loss paths (the gitignore shadow over the
  observations store; unpushed control-session branches), and adds
  per-request committed writes — the write-amplification load the
  audit-store findings warn about (obs:fcc5f742, obs:2bea1358).
- Commit the record in both arms. Rejected because: two
  authoritative-looking copies of one record is the drift
  cite-don't-copy exists to prevent.

**Chosen because:** derive-from-evidence is the repo's settled state
posture, the PR-as-audit-surface has direct precedent, and the adaptive
arm keeps the no-remote path first-class instead of degraded-to-nothing.

*(Amended at kickoff lens review 2026-09-01: "the kickoff-brief class"
reads as: an audit artifact, not an accumulator — it collects no
deferred decisions, so it owes no named reader or drain ritual; the
pending-sign-off checklist it renders keeps its own PR-review drain.
The record-directory classification of `specs/_flights/` lands in the
meta-spec via Task 3's amendment. Seam-misfit note (existing-seam-reuse
domain): the shared fleet-audit trail misfits as a per-flight record
store — no row identity, silent truncation, lock contention, write
amplification (obs:fcc5f742, obs:2bea1358) — so the per-flight record
home is minted.)*

### D-7: One convergence sequence, proportionality inside it  (N)

**Decision:** Visual flight runs the identical configured
`review_sequence` instrument-flight tasks run. Proportionality may scope
rigor inside a pass for low-stake, high-reversibility changes, and any
scoping actually applied is declared in the flight's audit record. No
second sequence, no new knob.

**Alternatives considered:**
- Identical full depth always. Rejected because: a typo-fix request pays
  a full polish loop — the entry-fee problem in miniature.
- A `review_sequence_visual` knob. Rejected because: parallel review
  machinery the hard constraints forbid, and a lever to quietly zero
  out review on the specless path.

**Chosen because:** proportionality already licenses declared lighter
passes for exactly this case; reusing it keeps one convergence contract
and the strongest trust story.

### D-8: Attention — decision-queue posture, deterministic push  (N)

**Decision:** The tower's push surface is the decision queue (workers
blocked on a human decision, plus flight lifecycle events); everything
else is status on demand; each flight reports its draft-PR link on
completion. Lifecycle events reach the attention store by deterministic
push (hooks and scripts), with tower polling as fallback only. The tower
renders through the existing fleet-attention seam and
`notification_channel`, never beside them.

**Alternatives considered:**
- Silence until the PR. Rejected because: blocked workers wait invisibly
  and in-flight work is forgettable.
- Heartbeat digest. Rejected because: the wall-of-status failure mode
  the fleet docs warn the user tunes out.

**Chosen because:** "load scales with actionable decisions, not workers"
is the settled fleet posture, and the live failure where PR-ready
reached the human only via tower polling (obs:bfc6faf0) makes
deterministic push the recorded lesson, not a preference.

*(Amended at kickoff lens review 2026-09-01: "draft-PR link" reads
adaptively as the landing reference — the PR link, or the branch and
record path on the no-remote arm, per REQ-F1.1.)*

### D-9: Reconstruction on both surfaces over one shared sweep  (N)

**Decision:** A fresh tower session reconstructs at session start by
sweeping durable evidence (flight branches, PRs, the derived index,
worker liveness — including backend runtime evidence, per
obs:c6107c38); `/resume` additionally gains a tower-level sweep mode for
use outside the tower. Both surfaces consume one shared sweep
implementation, so the two renders cannot drift.

**Alternatives considered:**
- Tower start-sweep only. Rejected because: the operator chose the
  wider coverage; outside-the-tower reconstruction has real uses.
- `/resume` mode only. Rejected because: reconstruction becomes a step
  the human must remember — the pull-not-push pattern the autopilot
  reflex forbids.

**Chosen because:** both surfaces were wanted, and the single-sweep
constraint converts "two implementations to keep consistent" from a risk
into a non-issue.

### D-10: Dead workers inherit fleet crash policy; bounded-or-surfaced  (N)

**Decision:** Dead visual-flight workers inherit the fleet crash-loop
policy (backoff relaunch under the existing knobs, then escalation to
the human at the disable threshold). All survival and cleanup guarantees
are stated in the bounded-or-surfaced form: best-effort while the
substrate is reachable, every residue bounded and swept or durably
surfaced to the operator, never silent, never absolute.

**Alternatives considered:**
- Report-and-ask always. Rejected because: every transient crash costs a
  human interaction where the fleet layer already retries safely and
  bounded.

**Chosen because:** the policy exists, is bounded, and ends at a human
anyway; and the bounded-or-surfaced shape was re-derived across four
kickoff halts (obs:7d475b1e) — this bundle adopts it rather than
re-deriving it a fifth time.

### D-11: Flight branch and worktree grammar  (N)

**Decision:** Visual flights branch as `planwright/flight/<flight-id>`
with worktrees at `.claude/worktrees/flight-<flight-id>`; `flight` is a
reserved segment no spec identifier may claim; the flight id is a kebab
slug plus a short uid, collision-free by construction. This is an
additive spec-format grammar amendment. Seam-misfit note
(existing-seam-reuse domain): the existing task-id grammar cannot
express a specless unit (obs:96261531) and the bare suffix grammar
collides across concurrent units (obs:5001e9f4), so a new segment is
minted rather than overloading task ids.

**Alternatives considered:**
- `planwright/adhoc/<id>`. Rejected because: loses the flight vocabulary
  everywhere the branch name surfaces.
- A namespace outside `planwright/`. Rejected because: every hook and
  guard keyed on the `planwright/` prefix would need new cases — minted
  machinery the reuse constraint forbids.

**Chosen because:** the familiar shape keeps existing branch parsers
one additive case away, and reserving `flight` closes the collision with
a hypothetical spec of that name at the grammar level.

### D-12: Zero new config knobs in v1  (N)

**Decision:** v1 mints no new config knobs. The routing rule is doctrine,
not configuration; attention rides the existing `notification_channel`;
convergence rides the existing `review_sequence`. Tunable escalation
thresholds are a future overlay-graduation candidate: they enter core
only as an opt-in, default-preserving knob and only with drain-loop
evidence that the tuning generalizes.

**Alternatives considered:**
- Ship threshold knobs now. Rejected because: unproven preference; the
  customization-boundary default tilt says overlay-until-evidence, and a
  threshold knob is also a lever to quietly weaken the routing floor.

**Chosen because:** frugality on the config surface, and the boundary
doctrine's graduation path exists precisely for this case.

### D-13: The router is load-bearing model judgment — eval-gated  (N)

**Decision:** The routing decision is load-bearing LLM output
(llm-output-quality domain), so it ships behind a behavioral-eval gate:
the five acceptance scenarios become fixtures asserting route, stated
grounds, override compliance, and refusal behavior, and the docs task
depends on the eval task so no surface claims behavior the router has
not demonstrated.

**Alternatives considered:**
- Manual demo script only. Rejected because: the domain's disposition
  requires a pre-committed gate for load-bearing model output, and a
  demo is not a regression surface.

**Chosen because:** the automatic triggers are deterministic but the
judgment lane is not, and an eval fixture is the cheapest honest gate
the harness offers.

### D-14: The tower posture — extended, never loosened  (N)

**Decision:** The tower session runs under the
`config/tower-settings.json` posture. Any extension for chat-tower
shapes adds allow entries or guard shapes only; the deny floor
(never-merge, never-ready, no-default-branch-writes, no
history-rewriting) is never weakened, and the extension is
security-sensitive work: hard-pause discipline applies and the allow/deny
delta needs human sign-off. The tower can never self-grant permissions
(editing its own allowlist remains blocked).

**Alternatives considered:**
- A fresh chat-tower settings profile. Rejected because: a second
  posture to keep in sync with the first is parallel machinery; the
  existing profile was built for a standing control session and
  transfers.

**Chosen because:** the seed states this constraint at verbatim
strength, and the guard corpus findings this session mined show posture
divergence, not posture reuse, is where the live failures were.

*(Amended at kickoff lens review 2026-09-01: "chat-tower" in this
decision is transitional drafting shorthand for the tower session; the
qualified term ships in no deliverable, per D-2's rejection of qualified
coexistence.)*

### D-15: Post-sign-off orchestration on explicit ask only  (N)

**Decision:** After an instrument flight's spec is signed off, the tower
may dispatch orchestration of that spec only on an explicit per-request
user go; it never self-starts on sign-off completion or on the spec PR's
merge. The existing no-auto-chain invariant (drafting never chains into
kickoff) is untouched.

**Alternatives considered:**
- Offer the command only. Rejected because: hands the newcomer the
  internal command the docs just demoted, at the front door's best
  moment.
- Auto-start after spec-PR merge. Rejected because: converts the human's
  merge into an implicit go — a gate softened into a default-yes, which
  the autopilot reflex forbids.

**Chosen because:** the go stays a conscious human act per request while
the front door stays useful end-to-end.

### D-16: Flights fire every in-run point under the task runner contract  (E)

**Decision:** A visual flight fires every in-run attachment point
`/execute-task` fires (custom-steps' point vocabulary, read from its
doctrine rather than restated here; the flip points are not in-run
points), in the same order and at the same moments relative to its own
work, with unit kind `flight`. The `convergence` point keeps its whole
definition, the merge-currency `main` sync included, so a flight's
converged head is `main`-current like a task's; a flight with no remote
records the sync as not run. Every step kind the step grammar defines
runs, under the same runner contract a task unit's steps follow.
Dispatch replaces its skill-only refusal with the same whole-run point
check `/execute-task` runs at pre-flight (check mode), and refuses exactly
where that check stops a task unit — a malformed entry at any layer,
machine-local included, or a step no worker can run (an unresolvable
skill target) — naming the point and step id. What degrades is what
check mode passes with a warning: an adopter or machine-local list naming
a step id no catalog defines, skipped on a flight exactly as on a task
unit, and named in the dispatch report and the brief. *(Amended at
kickoff delta re-walkthrough 2026-10-10: the degrade examples corrected
to check mode's actual behaviour, the operator choosing strict parity
over a more lenient flight dispatch; the convergence `main` sync and the
flip-point exclusion stated.)* D-7's one
convergence sequence stands unchanged; the skill-only narrowing was a
dispatch-path choice recorded in custom-steps' flight deferral, not a
decision of this bundle, and it is the narrowing that is lifted.

**Alternatives considered:**
- Convergence plus `post-pr` only. Rejected because: the operator's
  overlay already carries steps at the other points (a `pre-ci` command
  step among them), and leaving them unfired on flights keeps the "relay
  it by hand" gap open for every point but one.
- Keep the skill-only rule, degrading a non-skill step to a recorded skip.
  Rejected because: it fixes the blast radius (obs:6f21547d) but not the
  gap itself: a configured prompt step at `post-pr` still never runs on a
  flight.
- Keep refusing a flight whose list names a non-skill step. Rejected
  because: one machine-local step entry took down every flight on a host
  (obs:6f21547d), a blast radius a task unit does not suffer.

**Chosen because:** custom-steps already counts the flight as a unit kind
(custom-steps D-13), and the operator's verification cadence is per PR,
not per route; parity removes the tower's hand relay instead of moving
it.

### D-17: The flight worker runs points by `/execute-task`'s procedure  (E)

**Decision:** The flight worker is the runner at each point. The brief
names each in-run point at its moment in the flight's work and directs the
worker to run it by `/execute-task`'s *Points* procedure, read from the
planwright root the brief pins — the worker's root — with that root
pinned for the resolver; dispatch runs its up-front check of every
in-run point under that same pinned root, so the check and the run
resolve against one catalog and one set of skills. Two mappings make the
procedure fit a specless unit, stated in the brief: a flight always
resolves `--unattended` (it never blocks on a question), and wherever the
procedure ends or parks the unit through the pause protocol — whose
dispatched destination is a spec's `tasks.md` — a flight parks through
the flight park instead (the awaiting-decision push and the private
partial record, D-21), writing no spec state. A pin-check asserts the
referenced section heading exists in `/execute-task`'s skill, so a
rename there fails the gate instead of breaking flights silently; a
change of procedure under the same heading reaches flights by design.
*(Amended at kickoff delta re-walkthrough 2026-10-10: the pinned root,
unattended resolution, and the pause-protocol mapping stated.)*

**Alternatives considered:**
- Extract the *Points* procedure into one shared runner doc both consumers
  load. Rejected because: it reworks `/execute-task`'s text and the
  instruction budget for a dedupe whose payoff, one copy, the pin-check
  already protects; the operator chose the smaller change.
- Pre-render every resolved step into the brief (hosting, timeout,
  posture, screened text) and have the worker run the list. Rejected
  because: it re-implements, in dispatch, the screening and resolution the
  resolver already owns — the parallel machinery REQ-G1.5 rules out, and
  the reason custom-steps deferred flight rendering in the first place.

**Chosen because:** one runner procedure serves both unit kinds with no
second copy, and resolution at point time in the flight's own worktree
gives worktree-relative command resolution for free.

### D-18: `post-pr` fires only on a PR; the file home records it unfired  (E)

**Decision:** A flight's `post-pr` point fires after its draft PR exists,
with the PR number in the step context, then the flight runs
`/execute-task`'s after-`post-pr` sequence by reference (read from that
skill, not restated), less the unit-PR ready-flip a flight never
performs; its re-emit of the step tables into the record (the PR body)
goes only through the record renderer, re-run with the same inputs as
the first render, so the screen, neutralization, size bound, and public
summary all apply again; and it verifies the PR is still a draft,
parking when it is not. On the file home there is no PR: the point does
not fire, and the record's `post-pr` table carries a not-fired row
stating why, which the record renderer produces (the step-record helper
has no not-fired outcome, and this amendment adds none). *(Amended at
kickoff delta re-walkthrough 2026-10-10: the sequence cited rather than
partly enumerated; the re-emit path and the not-fired row's producer
named.)*

**Alternatives considered:**
- Fire `post-pr` on the file home too, after the record is landed, with no
  PR number in the context. Rejected because: the point is defined as
  "after the draft PR exists", and steps written for it (a hosted-review
  drain) have nothing to act on without one.

**Chosen because:** it keeps the point's meaning identical across unit
kinds, and a not-fired row keeps the record honest about what ran.

### D-19: Command steps on a flight: guard parity, no new approval  (E)

**Decision:** A flight's command steps are approved by the worker command
guard through the same declared-line path a task worker's are (the guard
already accepts unit kind `flight`); this amendment adds parity tests,
including adversarial ones showing a flight worker gains no approval a
task worker lacks, and changes no guard rule unless a test shows a gap.
The guard takes its install root from its own resolution, never from the
root a brief pins: under root skew a catalog command step's declared line
is deferred to the human, not approved, because letting the brief choose
the catalog the guard trusts would be exactly the widening this decision
rules out. *(Amended at kickoff delta re-walkthrough 2026-10-10: the
root-skew rule stated.)*

**Alternatives considered:**
- A flight-specific allow shape for command steps. Rejected because: it
  is a second approval path for the same act, and an authorization surface
  (decision-domains: authentication and authorization) widened without a
  stake-bearing reason.
- Keep command steps refused on flights. Rejected because: the operator
  chose full step-kind parity (D-16).

**Chosen because:** the guard's declared-line rule was built for exactly
this act and already names the flight unit kind; parity tests are the
cheapest honest proof that nothing widened.

### D-20: A public summary beside the private ask  (E)

**Decision:** The tower may hand dispatch a public summary of the ask
alongside the ask, and must when the ask carries detail security-posture
keeps off committed or remote surfaces (REQ-E1.7). The full ask reaches the
worker only through its brief under the fleet home; the record quotes the
summary, followed by a fixed line saying the worker was briefed beyond it,
with the existing sanitizing and markup neutralization applied to it.
Without a summary the record quotes the ask as today. The renderer's
restate check tests the lead against both texts, and, when a summary is
given, every other worker-written record input against the private ask;
the brief tells the worker the ask is private and keeps its commits, PR
title, record inputs, and PR comments at the summary's level, and the
tower draws the flight's slug (which becomes the pushed branch name)
from the summary. The check catches restatement above its thresholds,
not paraphrase or short fragments; that residual rests on the brief's
instruction and is recorded as a risk, not claimed closed. The tower's
call on when a summary is owed is load-bearing model judgment, so it
joins D-13's eval gate: fixtures assert a summary for a sensitive ask (an
undisclosed security defect among them) and none for an ordinary one,
graded from a summary field on the eval decision log's dispatch record.
This moves D-6's content-contract pointer from REQ-E1.1 to REQ-E1.6.
*(Amended at kickoff delta re-walkthrough 2026-10-10: the worker-side
surfaces, the slug, the widened restate check and its stated residual,
the graded field, and the D-6 pointer added; "its own summary" corrected
to the lead.)*

**Alternatives considered:**
- A private marker: the record withholds the ask behind a fixed line.
  Rejected because: the public record then states nothing of what was
  asked, weakening specless traceability (REQ-E1.12).
- Never quote the ask; always a tower-written statement. Rejected
  because: it costs verbatim-ask traceability on every ordinary flight to
  serve the rare sensitive one.
- Leave the record as it is and rely on the tower sanitizing asks by
  hand. Rejected because: the 2026-10-07 save depended on the worker
  noticing and parking (obs:2080c12b), and hand discipline is the memory
  burden the autopilot reflex closes.

**Chosen because:** every record still carries a statement of the ask,
nothing private reaches a public surface, and the default path is
unchanged.

### D-21: A parked flight's partial record stays private under the fleet home  (E)

**Decision:** Before parking, for any reason (a hard pause, a step halt
or park at a point, the non-draft check after `post-pr`, a renderer
refusal, a destination mismatch, a question it may not wait on), a flight
renders its partial record (review findings so far, declined log, park
reason) beside its brief under the fleet home, never committed or
pushed, written create-only, without following symlinks, and contained
to the brief directory. The park notification names only the kind of
park; its detail stays in the partial record, since the notification
channel may leave the host. The flight sweep surfaces the record's path
for a parked flight, so every surface rendering the sweep (the tower's
start sweep, and `/resume`'s tower mode once it lands) shows it. It
persists while the flight's worktree exists, and is removed with its
brief directory by the sweep that retires the flight: bounded, D-10.
*(Amended at kickoff delta re-walkthrough 2026-10-10: every park site,
the generic notification, write safety, the sweep as the one surfacing
path, and bounded removal stated.)*

**Alternatives considered:**
- Commit the partial record on the flight branch. Rejected because: a
  flight that later lands as a PR would carry a second copy of its record
  in the diff, which D-6 rejected.
- Open the draft PR at park time with the partial record. Rejected
  because: it publishes a security-pause flight's findings, the exposure
  D-20 closes.
- Leave it out of scope. Rejected because: the operator chose to consume
  obs:6d860346 here.

**Chosen because:** the fleet home is already the flight's private,
session-surviving store, and a hard-pause flight is exactly the case whose
findings security-posture keeps off public surfaces.

### D-22: Cross-bundle edges of this amendment  (E)

**Decision:** Both gaps land in this bundle, as the operator chose over
splitting gap 1 into a custom-steps extension. This bundle's tasks edit
the custom-steps doctrine lines that describe flights (the doc
custom-steps owns: its unit-run definition, the in-run points'
heading, the flights line, and the posture rule's flight destination)
and gate-wiring's pause protocol (a flight's destination) to match the
new behavior, and leave custom-steps' own ledger, its "Command
and prompt steps on a flight" deferral included, to that bundle's owner,
told through an observation recorded at this amendment's kickoff;
custom-steps REQ-F1.5 stays satisfied, since flights still read
`steps_convergence` with unit kind `flight`. The flight-rules doctrine,
owned here, also gains the outside-root record-home refusal spec-format
already states (obs:357b0e50).

**Alternatives considered:**
- Split: gap 1 as a custom-steps extension draining its own deferral.
  Rejected by the operator: two drafts and two kickoffs for one
  operator-facing gap.
- Also remove custom-steps' deferral bullet from this spec branch.
  Rejected by the operator: a write into another bundle's ledger.

**Chosen because:** the flight dispatch path and the record are this
bundle's, and the doctrine edit to custom-steps is a consistency
follow-through, not a change to the step contract.

## Cross-cutting concerns

- **Instruction headroom.** The new skill and every doc this bundle
  touches land inside the existing word-budget guard; the `/tower`
  SKILL.md description is authored as a selector (trigger and boundary,
  never procedure), and no sibling skill at zero headroom is asked to
  absorb new prose — cross-references land in the flight-rules doctrine
  doc instead.
- **Plugin-version skew.** A standing tower and its workers can resolve
  different plugin versions; the sweep and dispatch tasks surface the
  resolved-root pair rather than assuming agreement.
- **Multiplicity.** The tower assumes concurrent orchestrators and
  towers may exist (the coordination doctrine's discipline); the derived
  index is per-checkout cache and never a coordination surface.
