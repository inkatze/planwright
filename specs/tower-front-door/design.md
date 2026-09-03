# Tower front door — Design

**Status:** Ready
**Last reviewed:** 2026-09-01
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new decision, minted in this bundle's drafting session
(2026-08-27). Foreign IDs are namespace-qualified.

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

**Decision:** The record's content contract is fixed (REQ-E1.1). Its
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
