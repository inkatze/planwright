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
