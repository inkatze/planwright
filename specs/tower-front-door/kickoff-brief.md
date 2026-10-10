# Tower front door — Kickoff brief

## 1. Header

- **Spec path:** `specs/tower-front-door`
- **Spec commit at walkthrough start:** `538598e`
- **Walkthrough date:** 2026-08-27
- **Mode:** first activation (Draft, no prior brief)
- **Validator outcome (pre-flight):** `spec-validate.sh` — 0 errors, 0 warnings
  (format-version 2 bundle)
- **Config:** `commit_on_kickoff: true`,
  `mark_spec_pr_ready_on_kickoff: true`, `kickoff_ready_ci_wait: 10m`
  (defaults; no local override present)
- **Working location:** spec branch `planwright/tower-front-door/spec`,
  worktree `.claude/worktrees/tower`

## 2. Goal & glossary

**Restatement (agent's own words, confirmed by the operator).** The spec
inverts planwright's entrance. Today the four-file bundle is the only way
in, so every piece of work pays the spec ceremony and small work routes
around the tool. `/tower` becomes the front door: a standing conversational
session, context-frugal (inline work bounded to pure reasoning over
existing context plus the operational heartbeat), delegating everything
real to isolated worktree workers through the existing backend/`/offload`
seam, converging through the one configured `review_sequence`, always
landing a draft PR. Per request the tower picks flight rules — visual
flight (specless) or instrument flight (escalation into the spec
pipeline) — by stake and reversibility, grounds always stated, a
one-sentence override in both directions, automatic escalation for
hard-disqualifier-zone or not-one-revert-from-undone work. The spec stops
being the entry fee and becomes what the tower escalates into; on the
specless path the audit record carries trust. Altitude: doctrine (routing
rule, vocabulary) plus the `/tower` mechanism consuming existing seams
(D-1).

**Rules out:** fleet-mode integration beyond seam reuse, multi-repo
towers, skill renames, user-history routing, persistent flight memory, any
change to sign-off/merge semantics. The REQ-G invariants hold on both
flight rules. *(Amended at kickoff lens review 2026-09-01: the rules-out
list gained un-scaffolded-repository bootstrapping during the §3 walk —
see §3.)*

**Assumes:** the named seams exist and fit as-is (`/offload` placement,
`review_sequence`, fleet attention and crash policy, tower posture,
worktree conventions); Claude Code primitives only; one tower per repo
checkout; the Tower→Orchestrator vocabulary inversion is staged, not
one-shot.

**Implicit terms, resolved.** Every term the bundle uses without defining
resolves to an existing doctrine home rather than a gap: *rung*,
*operational heartbeat*, *tower-frugality* — `doctrine/work-placement.md`
(cited by REQ-A1.2); *hard-disqualifier zones*, *hard pauses*,
*pending-sign-off checklist* — finding-categorization doctrine; *decision
queue*, *fleet home* — fleet docs. The flight-id "short uid" format is
deliberately a Task 3 deliverable, not an ambiguity.

**Decision recorded — session naming (raised by the operator).** The
operator questioned whether "tower" is the right name, with "operator"
as the alternative in personal circulation. Resolved: **keep `/tower`;
D-2 stands as drafted.** Grounds: "operator" already names the human
across the doctrine corpus (grep re-derived at lens review 2026-09-01:
18 files, plus the operator-dialogue spec namespace), and re-pointing it
at an agent session would blur the
human/agent line in the trust-bearing surfaces while sitting confusably
next to the minted "Orchestrator"; the aviation vocabulary (D-3 flight
rules, D-11 flight branches, the autopilot co-brand) keystones on
"tower"; and the standing vocabulary is aviation-coherent as-is (the
operator is the authority above the tower). No spec edit required.

Signed off: 2026-08-27

## 3. Requirements walkthrough

Walked in three passes (groups A–B, C–E, F–H) across 2026-08-28 …
2026-09-01. Group intents restated and confirmed; per-group outcomes and
the decisions taken:

**Group A (entrance).** Confirmed, with two decisions: the tower never
writes the repo directly — every mutation is a flight, v1 sanctions no
exception (a future one is a spec amendment); and REQ-A1.5 was minted
mid-walk after the operator corrected the agent's hand-off reading — the
tower stays the operator's conversational window onto all planwright
work (status on demand from durable evidence, reserved-control relays on
explicit request) while never supervising or polling spec-mode
execution. Roles reconciled explicitly with the operator: the
orchestrator owns all spec-execution coordination; quality lives in the
workers' review convergence on both paths; the tower's spec-execution
involvement is exactly two passive verbs, relay ("go") and answer
(status on demand).

**Group B (router).** Confirmed as drafted; no edits. The escalation
floor, stated-grounds rule, two-way override, preventive-not-enforcement
posture, and eval gate all restated and accepted.

**Group C (visual flight).** One gap found and resolved: the bundle
never defined what a flight *is*. REQ-C1.6 minted — a flight is a unit
of repo-mutating work; a read-only ask exceeding the inline bound
offloads through the work-placement axioms without flight identity, its
result returning to the conversation. Follow-on rule (operator-decided):
a mutation need surfaced mid-offload returns as a new routed request — a
read-only worker never converts in place (Task 1 deliverable clause).

**Group D (instrument flight).** Confirmed. The post-"go" boundary was
walked twice (diagrams delivered): the tower starts orchestration on the
explicit go and never supervises it; supervision and window are distinct
(see group A / REQ-A1.5).

**Group E (audit record).** Two decisions: the quoted ask is sanitized
per security-posture before it reaches any committed/remote surface; and
REQ-E1.5 minted — the record renders human-first in both homes (a human
what/why/verification lead, no restated prompt, no filler) with the full
REQ-E1.1 contract collapsed below. Chosen over dropping the verbatim ask
(would have made ask-vs-heard divergence unprovable) and over leaving
rendering to implementation.

**Group F (attention and survival).** Confirmed as drafted; no edits.

**Group G (hard invariants).** Confirmed as drafted; no edits, no
questions — restates settled planwright law on both flight rules.

**Group H (vocabulary and docs).** The operator challenged the
tower/orchestrator terminology; assessment: the end state is clear
(operator = human, tower = chat session, orchestrator = dispatching
session, tied to its command name), the transition is the risk. Decision:
keep the naming, harden the transition — REQ-H1.1 extended with two
guardrails: the transitional note also covers tower-named scripts/config
serving either session until renames land, and the Orchestrator glossary
entry carries a one-line distinction from Operator, the human. The
front-facing skill set of REQ-H1.3 read as a coherent rule: the skills
that stay front-facing are exactly the human rituals.

**Walked scenarios (no spec change needed).** Ticket-driven teams:
tickets are just asks; team PR conventions coexist with the audit record
(drafts can be human-flipped immediately; non-`gh` forges take the
branch+record arm). The plural-ask case produced the decomposition rule:
an ask may fan into several flights, one per coherent unit, each routed
with stated grounds (Task 1 deliverable clause).

**Consolidated spec-edit list** (all applied in Draft, validator clean
0/0 after each batch; dated changelog entries 2026-08-28 and 2026-09-01
in `requirements.md`):

1. `requirements.md`: REQ-C1.6 minted; REQ-A1.5 minted; REQ-E1.5 minted;
   REQ-H1.1 extended (transition guardrails); out-of-scope bullet
   (un-scaffolded repos → inception seam); security-posture added to
   consulted-doctrine Sources; two changelog entries.
2. `test-spec.md`: paired entries for REQ-C1.6, REQ-A1.5, REQ-E1.5
   (requirement/test-spec pairing kept at disposition time).
3. `tasks.md`: Task 1 deliverables gained the flight boundary, the
   mid-offload re-route rule, and the decomposition rule; Task 2
   deliverables gained the two vocabulary guardrails; Task 6 deliverables
   gained the human-first rendering; citation updates (Task 1: +C1.6;
   Task 4: +A1.5; Task 5: +C1.6; Task 6: +E1.5); out-of-scope bullet.

*(Amended at kickoff lens review 2026-09-01: the re-route and
decomposition rules recorded above as Task 1 deliverable clauses were
folded up into REQ-C1.6 itself by the lens-review batch, with the
paired test text; Task 1 now cites the REQ rather than restating it.)*

**Mid-walk lens passes** (delta-scoped, inline — small narrow deltas,
path declared per kickoff-verification): REQ-C1.6 pass surfaced one
finding (mid-offload mutation need unstated), dispositioned as the Task 1
re-route clause; REQ-E1.5 and REQ-A1.5 passes clean (both-homes rendering
scope and push/pull split checked); guardrail edit pass clean. No
erroring pass.

**Process note.** Mid-section the operator flagged the walkthrough as
hard to follow; format switched to one-item-per-turn with completeness
kept in this brief. Recorded as observation `2026-09-01-kickoff-density`
for `/spec-draft`.

Signed off: 2026-09-01

## 4. Design walkthrough

All fifteen D-IDs reconciled: **confirmed, rationale intact** — none
amended, none superseded. Section 3's discussion served as the exercise:
the minted requirements (REQ-A1.5, C1.6, E1.5, the H1.1 guardrails) all
land under existing decisions, none against. Notes on the three most
exercised: D-2 survived a direct operator challenge to the naming (kept;
guardrails recorded at the requirement level, decision text unchanged);
D-6 absorbed human-first rendering as an additive layer (record content
and homes untouched); D-15's boundary is sharpened by REQ-A1.5
(relay + answer, never supervise) and reads exactly that way. Checked
mechanically: every D-ID is cited by at least one task, and no rejected
alternative was re-introduced by the walkthrough's edits (the closest
call — "a second review sequence" — is deliberately not what D-7's
declared proportional scoping is). *(Amended at kickoff lens review
2026-09-01: the every-D-ID claim was falsified by the citation lens —
D-12 was cited by no task at the time of writing; fixed by the
ownership sweep (D-12 now cited by Task 4) and re-derived true before
the anchor.)* Cross-cutting concerns (instruction
headroom, plugin-version skew, multiplicity) reviewed; nothing in the
walkthrough's edits touches them.

Signed off: 2026-09-01

## 5. Verification approach

Coverage mix reviewed against `test-spec.md`'s intro and entries (cite:
the file's own tag set — not retallied here). Ownership stated:
`[test]` entries run in the repo CI via the `mise run check` family and
unit tests; the behavioral-eval fixtures run on the plugin eval harness,
whose operability caveat the bundle already records at Task 11 — flagged
in this walkthrough as the one at-risk verification path (falls back to
operator-run when the harness cannot run; accepted, no change).
`[manual]` and `[Gherkin]` demo scenarios are the operator's, exercised
once at v1 acceptance via the demo script (operator-confirmed: after v1,
not per task). `[design-level]` entries are verified by review at
task-PR time. Dead-path check: every REQ's named verification can run,
including the three walkthrough-minted requirements, whose entries were
paired at disposition time. No orphaned entries, no entry naming
machinery that does not exist.

Signed off: 2026-09-01

*(Amended at kickoff lens review 2026-09-01: the terminal lens pass
falsified this section's dead-path claim as originally recorded — the
demo script, the doc pin-checks, the gloss check, and the eval
artifact-emission seam had no owning task. All four gained owners in
the approved edit batch (Tasks 2, 11, 12, and the new Task 13), and the
eval-honesty decision pinned the out-of-CI meaning of eval-backed
`[test]` entries in the test-spec intro. The operator-run fallback
noted above changes who runs the harness, never whether the Task 11
gate must pass before Task 12.)*

## 6. Task graph

Reconstructed from the `Dependencies:` lines (authoritative; the
on-demand render `scripts/spec-graph.sh specs/tower-front-door` was run
and agrees — no committed drawing). Two start-ready tasks in parallel:
Task 1 (doctrine doc) and Task 3 (flight grammar). Critical path,
tool-confirmed and effort-weighted from the blocks' estimates:
1 → 2 → 4 → 5 → 6 → 7 → 8 (doctrine → vocabulary → skill → dispatch →
record → sweep → `/resume`); side branches 9, 10, 11, 12 run off the
main chain. Deliberate non-edges, recorded so nobody "fixes" them:
Task 12 (docs) does not depend on 5/6/7/9 — it gates on vocabulary, the
skill, and the eval only (no doc claims routing behavior before the eval
proves it; doc content is independent of runtime plumbing); Task 10
(posture) has no dependents — the skill runs under the existing posture,
the extension only removes friction; Task 11 (eval) does not depend on
Task 5 — it tests routing judgment, which lives entirely in the skill.
Operator confirmed the order and all three non-edges.

Signed off: 2026-09-01

*(Amended at kickoff lens review 2026-09-01: Task 13 — the acceptance
demo script, deps 5 and 9 — was added by the approved edit batch. It is
a side branch; the recorded critical path and the three non-edges are
unchanged, re-derivable from the `Dependencies:` lines via the same
render command.)*

## 7. Risk register

Decision-domains gap check: run against the merged catalog
(`scripts/resolve-catalog.sh decision-domains`; re-derive the domain
count from the catalog itself — 19 at review, corrected from a copied
"twenty" by the lens pass). Result:
no domain the spec touches is left undecided; two were closed by this
walkthrough itself (human-comprehension → REQ-E1.5; the flight-boundary
edge → REQ-C1.6). Touched domains verified decided: llm-output-quality
(D-13 eval gate), auth-adjacent posture (D-14, escalated per
disposition), concurrency (REQ-C1.1/C1.5, multiplicity concern),
existing-seam-reuse (REQ-G1.5, seam-misfit notes D-6/D-11),
knowledge-engineering (D-2/D-3 staged vocabulary),
data-storage/caching (D-6, REQ-E1.3), queues-async (D-8/D-10),
secrets-config (D-12, E1.5 hygiene), org-design (§5 ownership; reserved
human controls), dependency-adoption (REQ-A1.4).

Numbered rows (risk — mitigation / early signal):

1. Eval-harness operability: routing verification degrades to
   operator-run — caveat recorded at Task 11 wiring; fallback manual.
   Signal: harness fails at Task 11.
2. Two-sense "tower" during transition — transitional note + the two
   REQ-H1.1 guardrails; the sweep's Deferred gate fires on observed
   confusion. Signal: a reader mixes the senses.
3. Tower-named scripts serve the orchestrator while renames wait on an
   external review with no timeline — transitional note covers code
   names. Signal: contributor confusion in fleet-script PRs.
4. Deterministic push into a standing chat session may hit platform
   limits — push targets the attention store, not the session; polling
   fallback stands (REQ-F1.2). Signal: Task 9's done-when unreachable
   without polling.
5. Plugin-version skew between a standing tower and its workers — sweep
   and dispatch surface the resolved-version pair (cross-cutting
   concern). Signal: mismatched pair reported.
6. Instruction-budget headroom on the new skill and doc surfaces —
   selector-style description, cross-refs live in the doctrine doc,
   budget guard enrolled. Signal: guard failure at Tasks 4/12.
7. Operator/Orchestrator word proximity, permanent — glossary
   distinction line (H1.1 guardrail); newcomer surfaces stay
   plain-language (REQ-A1.1). Signal: mix-ups in reviews or docs.

Open questions carried into sign-off: none — every question raised
during the walk was resolved into a decision or a row above.

Signed off: 2026-09-01

## 8. Sign-off

**Mode and scope:** first activation, full walkthrough (sections 2–7
signed 2026-08-27 … 2026-09-01), terminal sign-off 2026-09-01.

**Terminal lens review** (Discovery Rigor, artifact class **spec** —
spec lens set per artifact-lenses; full bundle; fan-out: one read-only
sub-agent per lens for eight lenses, the decision-domain-gaps lens taken
from the in-session §7 catalog walk — scoping declared at fan-out).
Canonical lens-coverage table (spec set):

| Lens | Findings | Notes |
| --- | --- | --- |
| Contract correctness / internal consistency | 16 | PR-arm predicate split, absolute survival claim, eval-gate scope, closed record contract |
| Ambiguity / interpretation forks | 61 | ~⅓ load-bearing; the rest pinned cheaply or declined as task freedom |
| Citation & coverage integrity | 12 | 5 REQs and D-12 owned by no task; overstated source glosses |
| Dead verification paths | 27 | eval artifact contract, phantom demo script, phantom doc tethers |
| Decision-domain gaps | none | in-session walk against the merged catalog; two gaps already closed mid-walk |
| Testability of Done-when | ~40 | systematic deliverable↔Done-when gaps; two unfalsifiable clauses |
| Cross-file consistency | ~40 | pairing gaps, changelog under-reporting, brief figure errors |
| Documentation / glossary drift | 29 | two-sense "tower" fired in-bundle; undefined minted classes |
| Rendered-content safety | 2 | quoted-ask markup gap; marketplace-mention judgment call |

**Altitude check (REQ-H1.3 of the kickoff spec):** pass — the pinned
seed claims sit in Sources, the altitude decision (D-1) exists and is
cited from the goal, and the task decomposition carries doctrine tasks
alongside mechanism, matching capability-plus-doctrine.

**Validation scoping (declared):** apply-routed findings received the
full three passes (reviewer evidence with quotes, the coordinator's
independent in-context cross-read, doctrine/repo grounding) plus the
adversarial refute sweep; declined findings received the resurrect
attempt. Three keep-set items were refuted out to declines
(deny-widening, the REQ-A1.3 wording, the checklist-accumulator claim);
no declined finding was resurrected.

**Dispositions:** ~225 raw findings merged into 14 applied edit clusters
(A1–A14: one PR-arm predicate; the flight noun pinned with REQ-C1.6
extended; the two controls named; REQ-F1.3 restated bounded-or-surfaced;
the `_flights/` record class minted via Task 3; vocabulary hygiene with
the fourth definitional site; the record contract completed with worker
authorship; the task-ownership sweep; verification builders including
Task 13; Done-when hardening; the precision batch; citation accuracy;
bookkeeping; markup neutralization), 6 decline classes (B1–B6, each
with recorded rationale: mid-flow states, refuted tensions, task
freedom, already-decided, trivia, the marketplace mention kept), and 2
operator-decided forks: eval honesty resolved as keep-`[test]` with the
out-of-CI meaning pinned in the test-spec intro and REQ-B1.6 rescoped
to user-facing docs; flight concurrency resolved as the dispatch-time
check against `max_parallel_units` with conversational deferral. Every
finding dispositioned; none left open. The changelog's 2026-09-01
lens-review entry itemizes the spec edits.

**Pre-flip verification:** post-lens stale-reference sweep run
(annotations added to brief §§2, 3, 5, 6; changelog fold-up note);
repository markdown lint 0 errors across the bundle and brief;
recorded-claim re-derivation clean — every REQ in `requirements.md` is
cited by at least one task and every D-ID by at least one task
(mechanically re-derived post-sweep), REQ↔test-spec coverage enforced
by the validator (0 errors at Ready), copied figures replaced by
citations where the lens pass falsified them.

**Validator:** 0 errors, 0 warnings after every batch and after the
Draft→Ready flip.

**Sign-off decision:** the operator approved via the self-contained
confirmation on 2026-09-01 after the shared-understanding approval
summary; Draft→Ready flipped on all four files, `Last reviewed:`
2026-09-01.

Class: meaning
Lens-pass: the terminal lens review recorded in this section
(fan-out table and dispositions above; mid-walk passes in §3)
Anchor: `0c9a65df6e41fb2eed701f328855007b0802f6b9` — computed as
`scripts/spec-anchor.sh specs/tower-front-door`

## 9. Amendment log

### Re-anchor — Awaiting-input placeholder recorded (2026-09-03)

Marked self-re-anchor for an expression-only edit landed with format-grammar
Task 3 (format-grammar D-9, REQ-D1.10): the `## Awaiting input` placeholder
in `tasks.md` became the plain `(none yet)` form, which the validator's
Awaiting-input purity rule (format-grammar REQ-D1.1) had read as a
non-reference bullet. That section is outside the content anchor, so the
anchor moves only for the changelog entry recording the edit and the `Last
reviewed:` bumps on the edited files; no requirement or decision changes
meaning.

**Cites the changelog line:** the 2026-09-03 `## Changelog` entry in
`requirements.md`.

Class: expression-only
Anchor: `f2535d77c6a5868c534019b4be1588cf40d18ef0` — computed as
`scripts/spec-anchor.sh specs/tower-front-door`

### Delta re-walkthrough — flight step points and the private ask (2026-10-10)

#### 1. Header (delta)

- **Mode:** reopened-bundle delta kickoff (Status Draft, signed brief
  present); sign-off flips Draft→Ready again.
- **Spec commit at walkthrough start:** `79ea522`
- **Walkthrough date:** 2026-10-10
- **Delta:** exactly the extension commit `2e77447` — the bundle's anchor
  at its parent recomputes to this log's most recent entry
  (`f2535d77…`), so nothing else moved.
- **Validator outcome (pre-flight):** `spec-validate.sh` — 0 errors,
  0 warnings.
- **Config:** `commit_on_kickoff`, `mark_spec_pr_ready_on_kickoff`, and
  `kickoff_ready_ci_wait` at their defaults; no local override.
- **Structured decision/transcript log:** no harness-provided log in this
  session; the turn mirror is skipped.

#### 2. Goal & glossary (delta)

**Restatement (agent's own words, confirmed by the operator).** Flights
lag task units in two ways the extension closes. First, a flight runs
only the convergence moment and only skill steps there, so post-PR checks
and the other configured moments never fire on a flight (the tower relays
them by hand), and one malformed machine-local step entry refused every
flight dispatch on its host. The extension gives flights the task unit's
full set of in-run moments, every step kind, under the same runner rules,
with a broken step degrading exactly as on a task unit. Second, the audit
record quotes the ask verbatim onto a public surface; the extension has
the tower supply a public summary when the ask carries sensitive detail,
keeps the full ask in the private brief only, and has a parked flight
save its partial review record privately under the fleet home.

**Rules out (delta):** any change to the custom-steps contract (flights
consume it as it stands; its ledger is not edited here), and the
fleet-messaging transport, tower permission floor, and stale-attention
sweep.

**Implicit terms, resolved.** *In-run point*, *runner contract*,
*degrade*, *on-failure posture*: custom-steps doctrine and
`/execute-task`'s *Points* section. *PR home / file home*, *fleet home*,
*brief directory*: flight-rules doctrine and `scripts/flight-dispatch.sh`.
*Public summary* (of the ask) is new and defined by REQ-E1.7 and D-20; it
is distinct from the record renderer's existing lead summary
(`flight-record.sh --summary-file`), a naming collision Task 16 must
avoid (risk row, §7 below).

Signed off: 2026-10-10

#### 3. Requirements walkthrough (delta)

**Group C (flight step points, REQ-C1.7–C1.12).** Restated and confirmed
with no edits: a flight fires the same in-run points as a task unit, in
the same order, under one runner contract for every step kind; dispatch
runs the task unit's whole-run point check and refuses only where it
would stop a task unit, naming point and step id; command steps get
exactly a task worker's guard approval; `post-pr` fires only on the PR
home, recorded not-fired on the file home, followed by the re-emit and
still-a-draft check. Cross-checked against `/execute-task`'s *Points*
procedure and pre-flight point check: no conflict.

**Group E (the record and the private ask, REQ-E1.6–E1.10).** Confirmed.
One gap surfaced and decided: if the tower misses that an ask is
sensitive and supplies no public summary, the record quotes the full ask
on a public surface, as before the extension; the routing eval (D-13's
gate) is the only guard. Options presented: a worker backstop (park
before publishing), tower judgment only, or always summarizing.
**Decision (operator, 2026-10-10): tower judgment only, as drafted** — no
spec edit; the residual exposure is recorded as an accepted risk (§7
below).

**Consolidated spec-edit list (this walk):** see §5 (one test-spec
precision edit); no requirement edits. *(Amended at the delta lens
review 2026-10-10: the lens batch below edited group C and E
requirements in place and superseded REQ-E1.4 and REQ-E1.5; see the
sign-off subsection and the requirements changelog.)*

Signed off: 2026-10-10

#### 4. Design walkthrough (delta)

D-16 through D-22 accounted for: **confirmed, rationale intact**; none
amended or superseded, and no prior D-ID is contradicted. *(Amended at
the delta lens review 2026-10-10: D-16 through D-21 were amended in place
by the lens batch, each carrying its annotation — D-16's degrade examples
were a genuine inconsistency with check mode, resolved by the operator
as strict parity; D-6 gained an annotation pointing its contract at
REQ-E1.6 per D-20.)* The group-E
decision above sits inside D-20 as drafted (its rejected
alternatives — a private marker, always a tower-written statement,
hand sanitizing — are unchanged; the worker backstop was not among them
and is declined in §3, not minted). D-16's note that D-7's single
convergence sequence stands was checked against D-7: consistent.

Signed off: 2026-10-10

#### 5. Verification approach (delta)

Coverage: every minted REQ (C1.7–C1.12, E1.6–E1.10) has a test-spec entry
(validator-enforced); tags per `test-spec.md`. Ownership unchanged from
§5 of the first activation: `[test]` in repo CI, the E1.7 eval fixtures on
the behavioral-eval harness outside CI (the intro's eval-honesty rule),
`[manual]` by the operator at demo time, `[design-level]` at task-PR
review. Dead-path check found one: the REQ-C1.7 entry read the in-run
points "from the resolver", but `scripts/resolve-steps.sh` exposes only
its wired points (flip points included) with no in-run subset. **Edit
applied (Draft, in place):** the entry now compares against the point
list of `/execute-task`'s pre-flight point check, the list a task unit's
runner checks. No other dead path.

Signed off: 2026-10-10

#### 6. Task graph (delta)

Reconstructed from the `Dependencies:` lines (authoritative; rendered
with `scripts/spec-graph.sh specs/tower-front-door`, no committed
drawing). Two chains plus a join: the flight-steps chain (Task 14, then
Task 15) and the private-ask chain (Task 19, then 16, then 17), joined by
Task 18. Tasks 14 and 19 start in parallel. The effort-weighted critical
path, from the blocks' estimates, now runs through the private-ask chain
into Task 18.

**Decision (operator, 2026-10-10): the private-ask chain waits on the
record renderer's held security fixes.** Task 6's convergence review held
five security-sensitive fixes to `scripts/flight-record.sh` for decision
(its live Awaiting-input bullet); Tasks 16 and 17 edit that file, and
Task 17's done-when leans on its secret screen. A `Dependencies: 6` edge
was rejected after checking the derivation: Task 6 derives `completed`
from its merged PR's trailer, and the bullet only excludes Task 6 from
candidacy, so the edge would block nothing (spec-format's deliberate
two-readers asymmetry). Chosen over parking Task 16 behind a manual
bullet: **Task 19 minted** to land the five fixes, each paused for the
operator's decision (hard-disqualifier zone), with Task 16 depending on
it; Task 6's bullet now points at Task 19 and is removed by it.

**Deliberate non-edges:** Task 14 does not depend on Task 19 (the
flight-steps chain does not touch the secret screen); Task 15 is not a
dependency of Task 18 (guard tests change no doctrine); no new task
depends on Tasks 1–13, all of which derive completed. *(Amended at the
delta lens review 2026-10-10: falsified — Tasks 8, 12, and 13 derive
ready, not completed (`scripts/orchestrate-state.sh`). The non-edge
stands: no new task needs them, and REQ-E1.9 was rescoped so Task 17 no
longer leans on Task 8's `/resume` tower mode.)*

**Mid-walk lens pass on the Task 19 edit** (delta-scoped, inline: one new
block, one dependency, one bullet lead — small and narrow, path
declared). Checked: the five fixes match the bullet's items one to one;
each fix is security-sensitive, so the hard pause per fix is the
finding-categorization rule rather than a new one; Task 19's citations
resolve (D-6; REQ-E1.2 for `land`, REQ-E1.5 for sanitizing); no REQ is
minted, so no test-spec pairing is owed. *(Amended at the delta lens
review 2026-10-10: Task 19's done-when was found missing three of its
deliverables and was tightened in the lens batch.)* One finding: removing Task 6's
bullet also removes its trailing note that the PR's CI was blocked by a
full-history secret-scan hit; dispositioned **no change** — `main`'s CI
is green on its current head, so the note is already stale. Also applied
in this section's batch: Task 16 names its summary option distinct from
the lead's `--summary-file` (§7 row 2). Not erroring.

Signed off: 2026-10-10

#### 7. Risk register (delta)

Decision-domains gap check over the delta, against the merged catalog
(`scripts/resolve-catalog.sh decision-domains`): no touched domain left
undecided. Touched and decided: auth (D-19 guard parity, any guard change
hard-paused in Task 15), secrets-config (D-20, Task 19's screen fixes, no
new flight knob per REQ-C1.8), data-storage (D-21's private store and its
retention, bounded-or-surfaced), llm-output-quality (the summary call
joins D-13's eval gate), observability (degraded and not-fired steps
recorded in the step tables, REQ-E1.6), concurrency (Task 19's `land`
races), existing-seam-reuse (D-17 runs `/execute-task`'s procedure rather
than a copy), org-design (Task 19's per-fix operator decisions).

Numbered rows (risk — mitigation / early signal):

1. A missed public summary publishes a sensitive ask in the record —
   **accepted risk (operator, 2026-10-10)**: tower judgment under the D-13
   eval gate is the only guard, no worker backstop. Signal: a flight
   record quoting detail the data-hygiene rule keeps off public surfaces.
2. The new public-summary option colliding with the renderer's existing
   lead `--summary-file` — Task 16's deliverable now requires a distinct
   option. Signal: a record test feeding one where the other was meant.
3. The critical path waits on five operator decisions in Task 19 — the
   flight-steps chain runs meanwhile. Signal: Task 19 parked at a hard
   pause for days.
4. The pin-check catches a renamed *Points* heading, not a changed
   procedure under the same heading — flights follow `/execute-task`'s
   procedure by reference, so a semantic change reaches them by design.
   Signal: an `/execute-task` *Points* edit whose PR does not mention
   flights.
5. Overlay steps resolved at point time can differ from the dispatch-time
   check (an overlay edited mid-flight) — the same exposure a task unit
   has; the flight parks or degrades by the runner contract. Signal: a
   flight halting at a point its dispatch check passed.
6. *(Added at the delta lens review 2026-10-10.)* The restate check
   catches restatement above its thresholds, not paraphrase or short
   fragments of a private ask in worker-written text — the brief's
   privacy instruction carries that residual (D-20). Signal: a published
   flight surface paraphrasing a private ask.
7. *(Added at the delta lens review 2026-10-10.)* Under root skew the
   guard defers a flight's catalog command step to the human rather than
   approving it (D-19), which can stall an unattended flight at that
   step. Signal: dispatch reporting `root-skew` followed by a flight
   parked at a command step.
8. *(Added at the delta lens review 2026-10-10.)* Strict parity means one
   malformed machine-local step entry refuses every flight on the host
   until fixed — the refusal names the point and step, so the cause is
   visible, but the blast radius obs:6f21547d described returns as a
   loud refusal rather than a silent one. Signal: repeated dispatch
   refusals naming the same step id.

Open questions carried into sign-off: none.

Signed off: 2026-10-10

#### Sign-off (delta)

**Class (on the REQ-A3.3 axis):** meaning — the delta adds requirements,
decisions, and tasks, which count as meaning-class.

**Terminal lens review** (Discovery Rigor, artifact class **spec**, spec
lens set per artifact-lenses; delta-scoped to the extension commit plus
this walk's edits; fan-out: one read-only sub-agent per lens for eight
lenses, the decision-domain-gaps lens taken from the in-session §7 catalog
walk — scoping declared at fan-out). Canonical lens-coverage table:

| Lens | Findings | Notes |
| --- | --- | --- |
| Contract correctness / internal consistency | 10 | the check-mode inconsistency (halt, operator-resolved); pause protocol vs specless unit; attendance; root skew; superseded-contract pointers; not-fired row producer; after-`post-pr` sequence; `main` sync |
| Ambiguity / interpretation forks | 9 | the same check-mode fork; attendance; flip-point membership; `main` sync; park scope; summary trigger; fixed-line placement; leak-test scope |
| Citation & coverage integrity | 7 | stale changelog; superseded REQ-E1.1 pointers; D-16 premise overstated; nonexistent `/resume` tower mode; false "Tasks 1–13 completed" brief claim |
| Dead verification paths | 7 | eval field absent; no demo scenario; record tests with no producer; brief tests asserting runtime behaviour; unparkable test flight; conflicting point oracles |
| Decision-domain gaps | none | in-session walk against the merged catalog (§7); every touched domain decided |
| Testability of Done-when | 11 | no baseline for "byte-identical"; deliverables without clauses (Tasks 14, 16, 17, 19); unbounded leak search |
| Cross-file consistency | 9 | live REQ-E1.5 vs REQ-E1.6; superseded test entries; renderer owner; custom-steps scope vs Out of scope; Task 19 vs the bullet |
| Documentation / glossary drift | 11 | "summary" in two senses, "private ask" undefined; pause-protocol destination; `/offload` petition; doc surfaces Task 18 did not name |
| Rendered-content safety / data hygiene | 9 | worker-side surfaces and slug; restate check scope; re-emit path; park notification leaving the host; root-skew guard trust; partial-record write safety |

**Altitude check (REQ-H1.3 of the kickoff spec):** pass — the bundle's
altitude decision (D-1) is unchanged and cited from the goal; the delta's
decomposition pairs mechanism tasks (14–17, 19) with a doctrine task
(18), matching capability-plus-doctrine.

**Ship-gate check (REQ-L1.4):** one out-of-band follow-up was named in
prose only — custom-steps' "Command and prompt steps on a flight"
deferral, left to its owner (D-22). Dispositioned: an observation
fragment recorded for that owner
(`2026-10-10-custom-steps-flight-deferral-addressed`). Task 6's held
fixes carry Task 19 as their ship gate.

**Validation scoping (declared):** every finding was merged and
re-checked by the coordinator against the code or doctrine it cites
(check-mode exit behaviour, the pause protocol's destination, the
resolver's wired-point list, the renderer's audit elements, the
derivation's task states); the adversarial pass refuted none of the kept
set and resurrected nothing from the decline set (the only decline is
below).

**Dispositions:** about 75 raw findings merged into 23 clusters, all
**applied** as spec edits after operator approval (2026-10-10), plus one
operator-decided inconsistency: dispatch refuses exactly where
`/execute-task`'s pre-flight check stops a task unit (strict parity),
chosen over a more lenient flight dispatch. Clusters: the strict-parity
edits and skipped-step naming; unattended resolution; the flight park in
place of the pause protocol; one pinned root for check and run, the guard
never trusting it; the convergence `main` sync; the in-run point oracle;
the after-`post-pr` sequence by reference with the re-emit through the
renderer; the step-table owner and not-fired row; REQ-E1.4 and REQ-E1.5
superseded by REQ-E1.12 and REQ-E1.11 with test entries repointed and
D-6 annotated; the summary trigger and private-ask definition; the
worker-side privacy instruction, slug, and widened restate check; the
`/offload` petition; the eval field and live-gate record; test-precision
clauses; Task 14's missing clauses; every park with a generic
notification and safe writes; the sweep as the surfacing path; bounded
removal; Task 18's named doc surfaces and the narrowed Out of scope;
Task 19's missing clauses; the changelog; the fixed-line wording; Task
15's shared corpus. **Declined:** one — keeping Task 6's CI-blocker note
(stale; `main`'s CI is green), dispositioned at the mid-walk pass in §6.
Every finding dispositioned; none deferred.

**Pre-flip verification:** post-lens stale-reference sweep run over the
bundle and this entry (live references to the superseded REQs repointed:
D-6 annotated, D-20's alternative; completed Tasks 1 and 6 and the dated
changelog keep their historical citations; brief §§3, 4, 6 annotated);
recorded-claim re-derivation clean — every live REQ cited by a task,
every D-ID cited by a task, every live REQ with a test-spec entry
(mechanically re-derived after the sweep); the requirements changelog's
kickoff entry itemizes the edits. Enumeration cross-check: the delta's
enumerated claims — Task 19's "five" held fixes (against Task 6's
bullet), the changelog's "five observations" (against their archived
fragments), and Task 18's named doc surfaces (against the documentation
lens's search) — verified against the surfaces they enumerate. Markdown
lint 0 errors across the bundle and brief; validator 0 errors, 0
warnings.

**Validator:** 0 errors, 0 warnings after every batch and after the
Draft→Ready flip.

**Sign-off decision:** the operator approved via the self-contained
confirmation on 2026-10-10 after the shared-understanding approval
summary; Draft→Ready flipped on all four files, `Last reviewed:`
2026-10-10 on all four.

Class: meaning
Lens-pass: the terminal lens review recorded in this subsection
(lens-coverage table and dispositions above; the mid-walk pass in §6)
Anchor: `92a76528cecfd972a3dac0d2f7beaf0bbec3d821` — computed as
`scripts/spec-anchor.sh specs/tower-front-door`
