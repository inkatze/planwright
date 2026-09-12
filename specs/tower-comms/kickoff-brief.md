# Tower comms — Kickoff brief

## 1. Header

- **Spec path:** `specs/tower-comms`
- **Spec commit at walkthrough start:** `d02064a`
- **Walkthrough date:** 2026-09-09
- **Mode:** first activation (Draft, no prior brief)
- **Validator outcome (pre-flight):** `spec-validate.sh` — 0 errors, 0 warnings
  (format-version 2 bundle)
- **Config:** `commit_on_kickoff: true`,
  `mark_spec_pr_ready_on_kickoff: true`, `kickoff_ready_ci_wait: 10m`
  (defaults; no local override present)
- **Working location:** spec branch `planwright/tower-comms/spec`,
  worktree `.claude/worktrees/tower-comms-spec`
- **Doctrine resolution:** all nine rule docs the skill names resolved under
  the repository's `doctrine/`; the decision-domains catalog resolved through
  `scripts/resolve-catalog.sh` (core seed, no overlay layers present)
- **Independent cold read:** `/spec-walkthrough specs/tower-comms` offered as
  an optional complement; not a dependency of this walkthrough

## 2. Goal & glossary

**Restatement (agent's own words, confirmed by the operator).** Today the
tower relays the fleet's output to the operator as it arrives, in framework
vocabulary, and expects the operator to hold every worker's context; the
accumulator records how that fails past one worker. This spec makes the
tower the buffer between fleet and operator. The tower keeps one durable
queue of everything headed to the operator, in five kinds (news, question,
approval, request, standing decision); each item's content lives where its
kind already lives, and only the index and delivery state sit in a new
store under the cross-spec fleet home. Before delivering anything the tower
settles what evidence can settle and merges duplicates. It knocks with one
line, waits for a reply, delivers one item answerable from its own message,
and any reply releases the next. It speaks as a developer who knows
planwright's basics. Anything the operator asks for is captured in the same
turn with a one-line echo; a "from now on" reply becomes a written standing
decision that can settle later items, including a worker's permission
prompt strictly inside the rule. Away, the tower accumulates and settles as
when present, knocks through the existing notification channel once and
again only on worsening, and a successor tower rebuilds the queue from the
content homes. The event log and scorecard ship first, a baseline over real
sessions is taken, and the conversation rules spread to other attended
surfaces only on the experiment's measured result.

**Rules out.** Any change to who merges, readies, or rewrites history;
worker permission allowlists and guard shapes; the truth of a worker's
liveness or completion; notification channel adapters and transport;
durable tracking of owed items (the ledger's); thinning any artifact; and
adoption of the rules by kickoff, drafting, resume, or drain ahead of the
experiment. *(Amended at the sign-off lens pass: one channel is carved back
in, the session-relayed `push` channel, because only a session can call the
push tool; every other adapter stays out of scope.)*

**Assumes.** The fleet home and its advisory lock, the `notify` seam, the
reconcile sweep's evidence sources, the headroom policy's budget-raise rung,
and the kickoff decision log's JSON-lines shape exist and fit as-is; the
action-item ledger arrives later, with a fallback carrying requests and
standing decisions until it does (a tagged fragment as drafted; changed at
the sign-off lens pass to a machine-local, owner-only file under the fleet
home, because the tracked fragment leaked operator prose and stranded with
the tower's branch); the tower sessions governed
are `/orchestrate` (single-spec, `--meta`, `--fleet`) and `/tower` once it
ships.

**Implicit terms, resolved.**

- *Blocked worker* — a question item whose source is a worker (an
  `awaiting-input` row in the worker attention store); "blocked workers
  first" in REQ-C1.5 reads as "questions first".
- *Any reply* (REQ-C1.4) and *next engagement* (REQ-C1.7) — any operator
  message in the tower conversation.
- *Urgency* — the attention store's existing priority enum (`high`,
  `normal`, `low`); "urgent" in REQ-C1.7 means `high`; a worker question
  inherits its row's priority. Decided by the operator; grounded in
  existing-seam reuse.
- *Hour of fleet work* (REQ-G1.2) — wall-clock time during which at least one
  worker was live, derived from a per-pass `tick` event the settling pass
  logs with the live-worker count, so the scorecard stays computable from
  the log alone. Decided by the operator.
- *Catch-up view* (Task 8, REQ-F1.5) — produced by a distinct `catchup` verb
  (Task 4's `settled` listing generalised: settled-since-last-reply with
  reasons plus open counts by kind); `next` stays strictly one item per
  call. Decided by the operator; grounded in REQ-C1.1's by-mechanism bound.
- *The requests slot* (Task 8) — the step report's requests slot defined by
  operator-dialogue Task 11, which has not shipped; carried to the task
  graph (section 6) as a cross-bundle dependency.
- *The sanctioned answer channel* (D-12) — `fleet-attention.sh claim`, which
  today mechanically refuses any permission-park record; carried to the
  REQ-E walk (section 3) as the D-12 inconsistency.

**Decision recorded — a native queue indicator (raised by the operator).**
The operator asked that the tower constantly prioritise the next thing to
communicate (already the spec's shape: the settling pass runs before every
delivery and `next` re-ranks on each call) and that a native status
indicator show, per kind, that decisions or actions are waiting, without
the operator asking, and be obviously planwright's. Resolved: a new
requirement on the existing `statusline` notification channel (the Claude
Code status line, driven by planwright's own render script from the fleet
home), showing open counts per kind and the top item's kind under an
unmistakable planwright label; a `counts` verb in Task 3 and the render
wiring in Task 5; renders only while that channel is selected, as today's
fleet stats do. *(Narrowed at the section 3 lens pass: the status-line
field is named `waiting` and bounded to the top item's kind plus one total;
per-kind counts come from the `counts` verb.)*

**Consolidated spec edits queued from this section** (applied in section 3
with the group they belong to; the indicator requirement is a meaning-class
addition and gets the mid-walk delta lens pass at application):

1. REQ-C1.7 and D-4: name the urgency enum (`high` / `normal` / `low`).
2. REQ-G1.2 and Task 1: name the fleet-hours denominator and the `tick`
   event kind.
3. Task 4, Task 8, test-spec REQ-F1.5: the `catchup` verb; `next` stays one
   item.
4. New REQ-C1.9 (native queue indicator on the statusline channel), its
   D-ID, Task 3 `counts` verb, Task 5 render wiring, and the paired
   test-spec entry.

Signed off: 2026-09-09

## 3. Requirements walkthrough

### REQ-A — The operator queue

**Intent.** One durable, ordered set of everything headed to the operator,
in five kinds, with content in the home each kind already has and only the
index and delivery state in a new store under the fleet home, written under
the fleet lock, losable and rebuildable.

**Probed and decided.**

- *Concurrent towers.* Single-spec towers, the meta-tower, and the fleet loop
  can run at once over the one queue, and nothing said which of them
  delivers an item. Decided: **a delivery lease per tower** — `next` claims
  the item for the calling tower under the fleet lock, recording its
  presence id; another tower skips a leased item until the lease expires
  unacknowledged. New REQ-A1.7 and a design decision, a Task 3 deliverable
  and test, and a paired test-spec entry (edit 5 below). Grounded in the
  fleet presence seam and the `claim` verb's first-answer-wins idiom.
- *Rebuild loses overwritten news.* The worker attention store keeps one
  row per worker and overwrites it, so an undelivered news item whose row
  moved on cannot be rebuilt after losing the store. Decided: **accept, news
  is losable** — REQ-A1.5 gains the sentence; the event log still records
  the item; a risk-register row with the scorecard's lost-across-restart
  measure as its early signal (edit 6).
- *A worker question's content home* (REQ-A1.3) reads "the owning spec's
  Awaiting-input list and the worker attention store"; only a halting
  skill's park writes the Awaiting-input bullet, so the attention row is the
  home every worker question has and the bullet is present only when
  parked. Expression-level reword to "and, when parked, the Awaiting-input
  bullet" (edit 7).

**Outcome.** Group confirmed with two additions and one reword.

### REQ-B — Settling and merging

**Intent.** Before any delivery the queue is run against the events since
the last pass; only evidence or a written standing decision settles an
item, never a worker's own claim; duplicates merge, contradictions pair;
self-settled items are recorded and available, never pushed; mentioning is
not deciding.

**Probed and decided.**

- *Standing-decision coverage grammar.* "What it covers" had no grammar,
  and scripts may never use inbound text as a pattern. Decided: **fixed-string
  command prefixes** — coverage is a list of literal prefixes compared
  against the prompt's command text with fixed-string matching; a prompt
  matches only when its command starts with one exactly. REQ-E1.3 names the
  grammar, D-12 the match, Task 6's tests gain a prefix-boundary case
  (edit 8). Grounded in the security posture's never-a-pattern rule.
- *Contradiction pairing.* Judging contradiction needs a model, which the
  script may never call. Decided: **pair on a shared subject** — two open
  items naming the same subject key (worker handle, PR number, or branch)
  deliver as one decision; the tower session judges anything subtler at
  delivery. REQ-B1.3 names the rule (edit 9).
- *Same-question merging* (resolved from REQ-H1.4, reported): the script
  merges items whose normalised question text and option set are identical;
  semantic near-duplicates are the session's to mention, not the script's to
  merge. Recorded here, no spec edit.

**Outcome.** Group confirmed with two clarifications.

### REQ-C — Attention and delivery

**Intent.** The script bounds the turn: at most one item per call, knock
first and content only after confirmed attention, answerable alone with
context one layer at a time, any reply releases the next, ordered by
consequence, shelving with return, news urgency-gated, and the first turn
after silence explains state.

**Probed and decided.**

- *Shelve return interval.* Unset anywhere, with D-9 naming two knobs.
  Decided: **a third config knob** (`tower_shelve_return`) with a documented
  default and an options-reference row; D-9 says three knobs, Task 5 adds
  the row (edit 10). *(The lens passes later added the lease interval and
  the measurement bounds as further knobs; D-9 names every key.)*
- *Knock-first as mechanism* (resolved from REQ-I1.2 and REQ-C1.1,
  reported): `next` itself returns the knock line while attention is
  unconfirmed and hands over item content only after the knock's
  acknowledgement is logged, so knock-first is enforced by the script, not
  by instruction. Attention is confirmed by any reply and lapses after the
  quiet interval (the same knob as away detection), after which the next
  delivery needs a fresh knock. REQ-C1.2 gains the sentence (edit 11).
- *The native indicator* (from section 2): REQ-C1.9 minted here (edit 4).
- *Urgency enum* (from section 2): REQ-C1.7 names it (edit 1).

**Outcome.** Group confirmed with one addition and two clarifications.

### REQ-D — Speech

**Intent.** The tower writes for a developer who knows planwright's basics,
names things by what the operator can see, applies the listener-side word
test, and its delivered text is lintable from the log.

**Probed.** REQ-D1.1 (explain a doctrine term on first use) and REQ-D1.3
(when the operator asks what a name means, drop it) compose rather than
conflict: gloss once proactively; if the operator still asks, the name goes.
The jargon word list starts as a seed shipped with the script in Task 1 and
is cited by the rule doc in Task 7; identifiers (REQ, D, Task ids) are
counted by shape. No open question.

**Outcome.** Group confirmed as written.

### REQ-E — Inbound capture and standing decisions

**Intent.** Anything the operator asks for becomes a queue item in the same
turn with a one-line echo; "from now on" replies become written standing
decisions; every self-settlement names its rule; a permission prompt is
answered from a rule only strictly inside it, never from the tower's
judgment; questions are answered in the turn.

**Inconsistency halt, resolved by explicit override.** REQ-E1.5 and D-12
let a written standing decision answer a worker's harness permission
prompt. Two rules read against it: this bundle's REQ-H1.1 ("nothing in the
queue grants the tower a decision the gate doctrine does not already
grant") and orchestration-fleet REQ-B1.7 (a tower SHALL NEVER answer a
worker's harness permission prompt), which `fleet-attention.sh claim`
enforces today by refusing any permission-park record. Both readings were
presented with the smallest edit each way (keep D-12 and reword REQ-H1.1;
or narrow REQ-E1.5 to recommend-never-answer and supersede D-12). The
operator chose **keep D-12: the standing decision is the operator's
written answer, and the tower only relays it**. The contradiction with
orchestration-fleet REQ-B1.7 stands, named here as an override: its NEVER is
read as "never from the tower's own judgment", the rationale being that the
recorded failure was prompts answered outside any written rule with no
record a rule existed, and the strict-prefix plus named-rule form is what
makes the practice auditable. That bundle's requirement text is not edited
by this bundle; Task 10 amends the doctrine sentence that restates it.
Consequent edits: REQ-H1.1 reworded to "no decision of the tower's own; a
permission prompt is answered only as the operator's written answer"
(edit 12); Task 6 gains the answer channel accepting a
standing-decision-backed answer to a permission-park, with its refusal test
updated to "refuses unless backed by a named standing decision" (edit 13).
The cross-bundle mechanism change is a risk-register row.

**Probed and decided.**

- *Operator questions* (REQ-E1.6, resolved and reported): a question
  answered in the turn produces no queue item; the reply log line carries it
  for the friction measure. Only work the answer needs becomes a request
  item.
- *Coverage grammar* (from group B): REQ-E1.3 names the fixed-string
  prefix form (edit 8).

**Outcome.** Group confirmed; one halt resolved by override with two edits.

### REQ-F — Unattended operation and survival

**Intent.** Away is a quiet interval with no reply; away knocks go through
the notify seam once and again only on worsening; items accumulate and
settle as when present; a fresh tower resumes from store and homes.

**Probed.** A failed push through the notify seam is logged and not
retried (REQ-F1.3 forbids fixed-schedule repeats; the next worsening
re-knocks); recorded as a risk row. The watch loop keeps running the
settling pass each iteration while away, which is what REQ-F1.4 relies on.
No spec edit.

**Outcome.** Group confirmed as written.

### REQ-G — Measurement and the experiment

**Intent.** One log line per queue event under the fleet home; a
scorecard from the log alone with the operator's load as headline; log and
baseline before the queue; the experiment gates extension; on demand only.

**Probed and decided.**

- *Who writes the log.* As drafted, the tower session had to remember to
  log each turn and reply, so a miss thinned the measure invisibly.
  Decided: **a deterministic prompt-submit hook logs operator replies**,
  active only in tower sessions (the tower's own `ack` writes the
  acknowledgement, split from the reply at the lens pass);
  `next` logs deliveries itself. REQ-G1.1 names the writers, D-14 records
  it, Task 2 gains the hook and Task 3 the in-verb logging (edit 14).
  Grounded in REQ-C1.1's bounded-by-mechanism rule and REQ-H1.4's
  allowance for model-free hooks. The hook fires in every session the
  plugin is loaded in, so its tower-session gate is a risk row.
- *Fleet hours* (from section 2): REQ-G1.2 names the denominator and the
  `tick` event (edit 2).

**Outcome.** Group confirmed with one addition.

### REQ-H — Invariants and hygiene

**Intent.** Reserved controls unchanged; settle only by evidence or written
rule; no secrets, inbound text is data; deterministic mechanics.

**Probed.** REQ-H1.1 reworded per the group E override (edit 12). The new
prompt-submit hook is model-free, so REQ-H1.4 holds. No other change.

**Outcome.** Group confirmed with one reword.

### REQ-I — Where the rules live

**Intent.** One short rule doc cited at point of use; as small as the
mechanism allows; the budget raised by its measured size with the reason
recorded; bound to towers now.

**Probed.** The reachable budget is a per-class knob
(`instruction_budget_closure_*`), so the raise REQ-I1.3 names is class-wide
and lands as a raise-rationale entry the instruction check already
validates; that is the headroom policy's rung as shipped, so the
requirement reads correctly as written. No spec edit.

**Outcome.** Group confirmed as written.

### Consolidated spec edits (applied in this section)

1. REQ-C1.7, D-4: urgency on the attention store's scale.
2. REQ-G1.1, REQ-G1.2, D-14, Task 1: the `tick` event and the fleet-hours
   denominator.
3. D-6, Task 4, Task 8, test-spec REQ-F1.5: the `catchup` verb; `next` stays
   one item.
4. New REQ-C1.9 and D-17 (native indicator), Task 3 `counts`, Task 5 render
   wiring, test-spec REQ-C1.9.
5. New REQ-A1.7 and D-18 (delivery lease), Task 3 deliverable and Done-when,
   test-spec REQ-A1.7, cross-cutting concurrency note.
6. REQ-A1.5, test-spec REQ-A1.5: news losable at rebuild.
7. REQ-A1.3: content-home reword.
8. REQ-E1.3, D-12, Task 6, test-spec REQ-E1.5: coverage as literal command
   prefixes.
9. REQ-B1.3, D-5, test-spec REQ-B1.3: merge on identical text, pair on a
   shared subject.
10. REQ-C1.6, D-9, Task 5, test-spec REQ-C1.6: the shelve return knob.
11. REQ-C1.2, D-6, Task 3, test-spec REQ-C1.2: `next` enforces knock-first.
12. REQ-H1.1: reword per the D-12 override.
13. Task 6, test-spec REQ-E1.5: the answer channel accepts a
    standing-decision-backed answer to a permission-park.
14. REQ-G1.1, D-14, Task 2, Task 3, test-spec REQ-G1.1: hook and in-verb log
    writers.
15. Changelog entry for the kickoff edits.
16. REQ-G1.1, Task 1: log lines as a flat JSON subset parsed by the
    script's own awk, no `jq` (decided at the section 7 gap check).

### Mid-walk delta lens pass (applied edits, 2026-09-09)

Run at the point of application over the consolidated edits above, per
`kickoff-verification`: one read-only sub-agent walked the nine lenses
against `git diff -- specs/tower-comms/` and what depends on it; the agent's
findings were then validated a second way (against the drafted decisions in
`design.md` and the seams in `scripts/`) before disposition. The validator
run the agent added, `spec-validate.sh --baseline HEAD`, is the grounded
check for requirement/test-spec pairing on a bundle that does not yet exist
on `origin/main`.

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 11 | Contradictory sentences the edits introduced (REQ-A1.5, REQ-C1.2), over-broad pairing, lease and tick without an owner or knob, attention modelled globally |
| Security | 4 | Prefix match accepting a shell-operator suffix, answer channel checking a name not coverage, ungrammared prefixes, hook logging raw operator text |
| Error handling and failure modes | 3 | Log-write failure stalling delivery, tick gaps vs idle, status-line never-fail contract |
| Performance | 2 | `counts` on the debounced status-line path, log growth without retention |
| Concurrency / state | 3 | Lease keyed on an awareness-only identity, two writers per reply, hook lock discipline |
| Naming, readability, structure | 2 | A second `queue` on the status line, rewrap damage |
| Documentation | 4 | Changelog omissions, origin-tag legend, unamended D-3/D-11, doc deliverables |
| Tests / verification | 7 | Four validator dead-path warnings, Done-when gaps, urgency scale unverified, scenarios contradicting knock-first |
| Cross-file consistency | 4 | Override invisible in the bundle, task-graph edges, Task 8 citations, render ownership |

**Dispositions.** Thirty-six findings had a single recommended fix and were
applied as one cluster on the operator's decision (the lease interval as a
fourth knob owned with the quiet interval by Task 3; attention and the lease
keyed per tower; the knock taking the lease; the tick written by the loop
with a maximum gap; the prefix match hardened with a token boundary, a
shell-control-operator refusal, grammar-validated prefixes, and coverage
re-checked inside the answer channel; the reply hook routed through the log
verb with a bounded lock wait and secret-shaped redaction; `reply` and
`acknowledged` as distinct events; log rotation and a bounded report window;
a lock-free, never-failing status-line read under a `waiting` field with a
width bound; the channel coupling recorded in D-17 as an accepted
limitation; orchestration-fleet REQ-B1.7 cited from the bundle; D-3 and
D-11 amended with kickoff annotations; the origin-tag legend, changelog,
Done-when and citation gaps, the requirement/test-spec pairings, and
rewrap). Three went to the operator's judgment:

- *Knock cadence* — the agent read D-6 as one knock per item. **Declined:**
  D-6 rejected an explicit go-ahead between items as one extra message each,
  and REQ-C1.4 says any reply releases the next item; the cadence is one
  knock per attention session, now stated plainly in D-6 and REQ-C1.2.
- *Pairing rule* — pairing every open item on a shared subject would make
  multi-ask turns. **Applied as:** at most two open items of the same kind
  naming the same subject.
- *Non-command standing decisions* — the prefix grammar cannot express a
  rule that is not about a command. **Applied as:** mechanical settling by
  rule is permission-prompt-only; other rules are surfaced beside a
  matching-subject item and the acknowledgement applying them names the
  rule (new REQ-E1.7); the settle-by-rule route moves from Task 4 to Task 6,
  which now depends on Task 4.

One finding was applied in part: the quiet-interval knob moves to Task 3,
but no Task 2 edge is added to Task 3, because the tower's own `ack`
confirms attention without the hook. One plausible finding (the render
ownership) was applied at its cheapest form: D-17 says the render is
extended in place with the owning contract unchanged, and Task 10 updates
the options-reference row.

**Post-application verification.** After the cluster was applied, `spec-validate.sh` reported 0 errors and 0 warnings both against `origin/main` and with `--baseline HEAD` (the pre-kickoff commit); the requirement and test-spec entry counts match; no stale reference from the pre-edit wording remains in the four files.

Signed off: 2026-09-09

## 4. Design walkthrough

Every decision in `design.md` accounted for. No design decision contradicts
a walked requirement after the section 3 edits; the one contradiction found
(D-12 against REQ-H1.1 and a foreign never-clause) was resolved there by
override, not here.

| D-ID | Disposition | Note |
| --- | --- | --- |
| D-1 | Confirmed | Altitude record intact; both pinned seed claims are triggers (checked again at sign-off) |
| D-2 | Confirmed | Sibling store above the attention store; the lease (D-18) rides its lock, not its rows |
| D-3 | Amended | Worker-question home reworded; dropped-news exception added (annotated in place) |
| D-4 | Amended | Urgency fixed to the attention store's scale |
| D-5 | Amended | Merge normalisation and the same-kind, same-subject, two-at-most pairing rule named |
| D-6 | Amended | `catchup` verb; knock-first enforced by `next`; one knock per attention session; per-tower attention; write failures surfaced |
| D-7 | Confirmed | News urgency-gated; content after confirmed attention, now per tower |
| D-8 | Confirmed | Self-settled items available via `catchup`, never pushed |
| D-9 | Amended | The config keys named once here: quiet and lease intervals (Task 3), re-knock age and shelve return (Task 5), and after the sign-off lens the log, report, tick-gap, hook-wait and catch-up bounds (Tasks 1, 2, 4) |
| D-10 | Confirmed | Speech register unchanged |
| D-11 | Amended | Coverage grammar scoped to worker commands; other rules surfaced, never settled mechanically (annotated in place) |
| D-12 | Amended | Token boundary, shell-operator refusal, boundary re-check in the answer channel; the orchestration-fleet REQ-B1.7 override named |
| D-13 | Confirmed | One short doc; class-wide closure-budget raise with a raise-rationale entry |
| D-14 | Amended | Tick from the loop pass; hook via the log verb with redaction; `reply` and `acknowledged` distinct; rotation and a bounded report window |
| D-15 | Confirmed | Log first, baseline before the queue; Task 2 now also installs the hook, still with no queue behaviour |
| D-16 | Confirmed | Towers now; extension gated on the experiment |
| D-17 | Minted at kickoff | Native `waiting` indicator on the statusline channel; channel coupling accepted |
| D-18 | Minted at kickoff | Delivery leased per tower; exclusion is the lock's, presence identity only the label |

**Cross-cutting concerns** re-read: the concurrency bullet now names the
lease; the intervention-contract and attention-doc items stay with Task 10;
the tower-headroom note is unchanged.

**Outcome.** Every decision in the ledger above confirmed or amended with
rationale intact; those minted at kickoff are marked as such; none
superseded.

Signed off: 2026-09-09

## 5. Verification approach

**Coverage mix** (derived from the tags on `test-spec.md`'s entries; the
tally is the file's, not copied here). The large majority of entries are
`[test]` or `[test + Gherkin]`: the queue script's grammar, verbs, ordering,
lease, settling and pairing fixtures, the away state machine, the log and
scorecard arithmetic, and the repository's existing index, link,
options-reference, hook-contract, and instruction-budget checks. A small
`[design-level]` set verifies a rule's presence in the rule doc or the fleet
guide (Tasks 7 and 10). The `[manual]` set is the real-session half of the
baseline and the experiment (Tasks 2 and 9) plus the Task 7 review check
that the doc holds no rule a verb enforces.

**Ownership.** Every `[test]` entry runs under `mise run check` on the task
PR and in the repository CI; the concurrent-writer and two-tower cases are
timing-sensitive and are treated as real failures when they fail under load,
never dismissed as flaky (risk register). `[manual]` entries are run and
recorded by the executing worker of Task 2 and Task 9 into this brief's risk
register (the baseline and experiment entries) and re-read by the reviewer;
the Task 7 doc check is recorded in that PR's body. `[design-level]`
entries are checked at the Task 7 and Task 10 PR reviews; the review
clauses in the invariant entries (reserved controls untouched, the daemon
gate not extended) are checked at every task PR's review.

**Dead paths checked.** None found. Two entries deserve a note on what they
honestly verify: the "fixture session in Task 8" entries (REQ-A1.1,
REQ-C1.2, REQ-C1.4, REQ-E1.1, REQ-F1.5) drive the script's verbs in the
sequence the tower loop calls them, so they verify the mechanism's
behaviour, not the model session's; the session's conformance is what the
scorecard measures in Task 9. REQ-E1.5's boundary re-check changes
`fleet-attention.sh claim`, whose existing refusal test is updated by Task 6
rather than left contradicting the new behaviour. Every check a `Done when`
names exists in the repository today (`check:options`,
`check:hook-contracts`, `check:instructions`, `check:doctrine-index`,
`check:links`, `check:test-time`, `check-no-ci-evals.sh`); the sign-off
lens pass caught two Done-when lines naming a non-existent
`check:options-reference` task, corrected to `check:options`.

**Outcome.** Mix reviewed, ownership stated, no dead path.

Signed off: 2026-09-09

## 6. Task graph

**Graph** (reconstructed from the `Dependencies:` lines in `tasks.md`,
which are authoritative; this rendering is derived):

```
Task 1 ─┬─> Task 2 ──────────────────────────┬─> Task 8 ─┬─> Task 9
        └─> Task 3 ─> Task 4 ─┬─> Task 5 ────┤           └─> Task 10
                     └────────┴─> Task 6 ────┤
Task 7 ──────────────────────────────────────┘
(Task 9 also depends on Task 2; Task 6 depends on Tasks 3 and 4)
```

**Parallelism.** Task 7 (the rule doc) starts on day one with no
dependency. Task 2's real-session wall clock runs alongside Tasks 3 through
7. Tasks 5 and 6 run in parallel once Task 4 lands. Tasks 9 and 10 run in
parallel after Task 8.

**Critical path** (effort-weighted from the `Estimated effort:` lines):
Task 1 → Task 3 → Task 4 → Task 6 → Task 8 → Task 9, about nine working
days of effort plus the baseline and experiment sessions' wall clock, which
are the true bound. *(Re-derived at sign-off after the lens pass grew Tasks
1 and 6; Task 6 now outweighs Task 5 on the parallel leg.)*

**Deliberate non-edges** (do not "fix" these):

- Task 2 ↛ Task 3 and Task 3 ↛ Task 2: the baseline must not wait for the
  queue (D-15), and the queue store does not need the reply hook, because
  the tower's own `ack` confirms attention (section 3, lens disposition).
- Task 7 has no dependency on Tasks 3 through 6: the doc states only what a
  script cannot enforce, checked at its own review against the task
  definitions and re-checked when Task 8 wires it in.
- Task 9 ↛ Task 10 and Task 10 ↛ Task 9: docs and the experiment are
  independent once the loop is wired.
- Task 6 → Task 4 is a real edge added at kickoff: the settle-by-rule route
  extends the settling pass.

**Cross-bundle coupling** (not expressible as a Dependencies line):

- Task 8's requests slot is defined by operator-dialogue Task 11, unshipped.
  Decided: Task 8 reworded to wire into that slot or the step report's
  equivalent place until it exists; risk-register row.
- The action-item ledger (unmerged bundle) is carried by the tagged-fragment
  fallback and the Deferred cutover entry; `/tower` wiring is a Deferred
  entry gated on tower-front-door Task 4.

**Outcome.** Graph reconstructed; one reword applied to Task 8; non-edges
recorded.

Signed off: 2026-09-09

## 7. Risk register

Inputs: risks surfaced during the walk, the lens pass, and the
decision-domains gap check (the merged catalog via
`scripts/resolve-catalog.sh decision-domains`: core seed, no overlay
layers). Of the catalogued domains the spec touches, all but one are decided
in the bundle (storage and modelling, queues and async, API surface, auth,
secrets, concurrency, observability, versioning, LLM output quality, human
comprehension, existing-seam reuse); the one undecided domain, dependency
adoption, is row 13 and was decided at kickoff. Execution skills append
rows below; existing rows are never overwritten.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | The D-12 override reads another bundle's SHALL NEVER (orchestration-fleet REQ-B1.7) as never-from-own-judgment and changes the answer channel's refusal | Boundary re-check inside `claim`, named rule on every answer, fleet-hardening's refusal test updated by Task 6, doctrine amended by Task 10. Early signal: the standing-decision mismatch rate Task 9 reports; any answered prompt the operator did not expect |
| 2 | A command-prefix rule wider than the operator meant (privilege shape) | Token boundary and shell-control-operator refusal (REQ-E1.5); a focused security pass before the Task 6 PR per the security posture's write-time triggers. Early signal: mismatch rate; a rule with a one-token prefix |
| 3 | The lease's owner label rests on the presence surface, which is awareness-only and flag-sensitive | Exclusion is the fleet lock's; identity resolved once per tower with the publish flags; session-scoped fallback. Early signal: an item with two `delivered` events in the log |
| 4 | Undelivered news dropped at rebuild (accepted loss) | Log records it; `catchup` shows it. Early signal: the lost-across-restart measure |
| 5 | The reply hook fires in every session the plugin is loaded in | No-op unless a tower presence identity resolves; never gated on prose; secret-shaped redaction. Early signal: `reply` lines whose session is no tower |
| 6 | A notify push fails while the operator is away and is not retried | Next worsening re-knocks; the item stays queued. Early signal: blocked-worker wait rising with no knock event after it |
| 7 | Task 8's requests slot is owned by operator-dialogue Task 11, unshipped | Task 8 wires into the slot or the step report's equivalent place. Early signal: the Task 8 worker halting on the missing slot |
| 8 | The action-item ledger is unmerged; requests and standing decisions live in tagged fragments meanwhile | Fallback in REQ-E1.2/E1.3; Deferred cutover entry gated on the ledger's first task. Early signal: fragment count growth with no ledger in sight |
| 9 | Concurrent-writer, two-tower, and lock-wait tests are timing-sensitive | A failure under load is treated as real, never dismissed as flaky (the repository's recorded lesson). Early signal: CI failures that pass in isolation |
| 10 | The instruction-budget raise is class-wide, not per skill | Raise-rationale entry sized to the doc's measured words; `check:instructions` floor-breach warning as the signal |
| 11 | Baseline validity: Task 2 installs the hook and tick, and Task 8 changes loop cadence, so before and after are measured under slightly different plumbing | Sessions counted on both sides; tick gaps excluded and reported; the comparison names its regimes. Early signal: gap count differing sharply between halves |
| 12 | The `waiting` indicator renders only under the `statusline` channel; the operator's channel is `none` today | Fleet guide documents the setting (Task 10); the knock still reaches the conversation. Early signal: the operator asking whether anything is waiting |
| 13 | Gap check, dependency adoption: JSON lines with no `jq` in the runtime | Decided at kickoff: each log line is a flat JSON object of string and number values, no nesting, written and read by the script's own awk; Task 1's grammar test pins the subset (edit 16) |
| 14 | Log growth under the fleet home | Rotation by size or age; `report` reads a bounded window. Early signal: report runtime |
| 15 | The `claim` and status-line render changes touch scripts other bundles own | Extended in place with the owning contracts unchanged; options-reference row updated by Task 10. Early signal: the owning bundle's tests failing on the Task 5 or Task 6 PR |
| 16 | Baseline entry (Task 2) | To be appended by the Task 2 worker: sessions counted, scorecard per session, aggregate |
| 17 | Experiment entry (Task 9) | To be appended by the Task 9 worker: sessions on both sides, every measure, the mismatch rate, and the Deferred extension gate's outcome |
| 18 | The exposed fleet-lock primitive carries no owner token, so a stale-lock break can release a live holder's lock (sign-off lens) | Queue verbs hold the lock far below the stale threshold, gather evidence outside it, and re-read-and-compare before rename; Task 3's concurrent-writer test adds a saturation case. Early signal: a lost update in the store under load |
| 19 | REQ-E1.1's no-confirmation capture overrides operator-dialogue REQ-L1.1's confirmation clause (sign-off lens) | Recorded as an override in D-11 and the requirement's citation; the no-transcribe intent is kept. Early signal: a mis-heard capture surviving until noticed, counted as a repeated request |
| 20 | Captured requests, approvals, and standing decisions live in a machine-local file under the fleet home until the ledger ships, so they do not travel across machines and a request spoken mid-run dies with the machine | Owner-only file, survives tower death; the Deferred cutover entry gates on the ledger gaining a standing kind. Early signal: a standing decision missing on a second machine |
| 21 | The new session-relayed `push` channel depends on the tower session calling the push tool on its next step, so a stalled tower never relays a pending push | The marker persists until relayed and is deduped per item; a successor tower relays on start. Early signal: a pending-push marker older than the quiet interval with no push event logged |
| 22 | Attention rests on a per-tower marker file written by the prompt-submit hook; a session without the plugin's hooks never confirms attention | Fleet guide documents the hook as part of the tower's install; `next` surfaces "no attention marker" as an error rather than knocking forever. Early signal: knocks with no marker advance across a whole session |
| 23 | The Task 7 raise is sized to the rule doc alone, but wiring it in (Task 8) adds the manifest line and the one-line gist to a tower skill body that sits within a few words of its per-file floor; the guard's audit puts that body at a margin equal to its exception's pinned figure, so any added body word is a widening on the per-file surface, and the same words are charged to the closure, where the raise covers only the doc | Task 8 funds its manifest line and gist with a compensating trim in the same skill body (skill-rigor REQ-E1.1); the per-file ratchet forces that trim regardless of the closure raise, and the trim nets the closure charge back to the doc's own size; until Task 8 lands, the raise's headroom sits unspent above both closure exceptions and is reserved for the doc, so a spend by another change surfaces on Task 8's branch as a widening it did not cause. Early signal: `check:instructions` reporting a widened declared exception on the Task 8 branch |

**Open questions.** None carried: every question raised in the walk was
resolved into a decision or an accepted risk above.

Signed off: 2026-09-09

## 8. Sign-off

### Lens review pass (full bundle, first activation)

**Scope and fan-out.** Full bundle, per `kickoff-verification`: one
read-only sub-agent per canonical lens (nine in parallel), each briefed on
the decisions already recorded in this brief, followed by a merge and
dedupe; findings were then validated a second way against the drafted
decisions in `design.md` and the seams in `scripts/` and `docs/` before
disposition. The kickoff-specific altitude check ran inline as a check
item: both pinned seed claims in the Sources are altitude triggers, D-1 is
cited from the Goal, and the task decomposition matches the four recorded
altitudes (doctrine in Task 7; mechanism in Tasks 1 and 3 to 6; capability
wiring in Task 8; measurement in Tasks 2 and 9; docs in Task 10). Not a
finding.

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 27 | Lease and knock triggers across concurrent towers; the standing-decision kind with no delivery slot; Done-whens and scenarios naming verbs that could not produce them |
| Security | 16 | No trustworthy source for the command the answer channel re-matches; the denylist missing redirections; a self-satisfiable attention gate; tracked fragments leaking operator prose; no file mode or path containment |
| Error handling and failure modes | 14 | Only two failure dispositions stated; push-less `statusline` channel; content home vanished; evidence source unavailable; the lease mid-answer |
| Performance | 13 | Store retention absent; whole-store rewrite per verb; the settling pass re-polling evidence; `catchup` unbounded at session start; the step-count headroom proxy decalibrated |
| Concurrency / state | 23 | The droppable hook line as the gate's only opener; no tower identity on log lines; watermark and rebuild races; the lock primitive's no-token limit |
| Naming, readability, structure | 18 | Four terms with two meanings; multi-name concepts; orphan verbs; unannotated amended decisions; packed requirements |
| Documentation | 23 | Annotations on two of eight amended decisions; changelog order; four doctrine sites still stating the overridden rule; hook contract artifacts unowned |
| Tests / verification | 25 | A non-existent mise task in two Done-whens; five kickoff-minted behaviours unverified; a Done-when contradicting REQ-C1.2 |
| Cross-file consistency | 21 | The operator-dialogue REQ-L1.1 citation contradicted by its citing sentence; the approval kind with no content home; a Deferred gate not encoding REQ-G1.4; brief-to-bundle drift |

Raw findings across the nine lenses: 180, with the same fault lines
recurring under several lenses (the attention gate, the lease, the fallback
home, the away model), so the deduplicated set is smaller; the per-lens
notes and every disposition are in the run's scratch record and summarised
here.

**Dispositions.**

- *Applied as one cluster on the operator's decision:* every finding with a
  single recommended fix. In substance: the lease taken at every hand-over,
  released on acknowledgement, shelve, settle, merge-absorption, or a
  not-live owner, renewed on reply, preemptable by an attended tower;
  `ack` refusing without a lease and a logged no-op on a closed item;
  per-tower away with one deduped push per item across towers; `next`
  knocking only when due and handing over nothing until a later reply; the
  settling pass level-triggered, once per loop iteration, consuming the
  reconcile sweep's fetch, gathering evidence outside the lock, and logging
  a vanished content home or an unavailable source; store retention, keyed
  merge, a bounded `catchup`; the standing-decision kind registered but
  never delivered; the permission record carrying a hook-captured command
  and a positive marker, an allowlisted token set after the prefix, a
  mechanical reserved-control refusal, ASCII-only approval text, pointer
  containment, owner-only `0700` surfaces, redaction inside the `log` verb;
  every event stamped with the writing tower's identity, a sequence counter
  file, rotation by age; the nine config keys named once; the three packed
  requirements split into siblings (REQ-A1.8, A1.9, C1.10, C1.11, E1.8,
  E1.9, E1.10, G1.6, G1.7, G1.8); amendment annotations, citation tokens,
  a chronological changelog, `check:options`, Task 10's four extra doctrine
  sites and its fleet-guide sections, the hook's contract-table row and
  fixture, the operator-dialogue REQ-L1.1 override recorded, and every
  requirement/test-spec and Done-when pairing gap.
- *Operator's judgment, attention source:* only a harness-written marker
  confirms attention. The prompt-submit hook writes the last-reply time to
  a per-tower marker file it alone owns, lock-free and never dropped; the
  log's `reply` line stays best-effort behind a dropped-line counter; `ack`
  closes and never releases (REQ-C1.10). Chosen over a spinning hook (stalls
  the operator's turn) and over `ack` as the confirmer (self-satisfiable).
- *Operator's judgment, fallback home:* captured requests, approvals, and
  standing decisions live in a machine-local, untracked, owner-only
  ledger-shaped file under the fleet home until the ledger ships; the
  tracked-fragment fallback is gone (it leaked operator prose with no human
  in the loop and stranded with the tower's branch). The Deferred cutover
  gate now requires the ledger to gain a standing-decision kind first
  (REQ-A1.3, D-11 amended; risk row 20).
- *Operator's judgment, urgent news while away:* never pushes; the attended
  knock is its only escalation (REQ-C1.7; the test pinned to the attended
  case).
- *Operator's addition, the push channel:* a session-relayed `push` channel
  joins the seam as this bundle's one carve-out from the transport
  out-of-scope: the script marks a pending push under the lock, the tower
  session relays it through Claude Code's push-notification tool on its
  next step (REQ-F1.6, D-19, Task 5; risk row 21).
- *Declined:* the correctness lens re-argued one knock per item; declined
  again on D-6's rejected go-ahead alternative (the cadence is one knock per
  attention session, REQ-C1.10). The error-handling lens's carry-path fix
  for stranded fragments and the documentation lens's accumulator-tag
  convention became moot once the fallback moved off the repo.
- *Applied to the brief rather than the bundle:* the section 2 indicator
  wording and fallback note, the section 3 knob count and edit 16, the
  section 4 tally and D-9 row, the section 5 check name and ownership
  sentence, the section 6 critical path, and risk rows 18 to 22 (the lock
  primitive's no-token limit, the REQ-L1.1 override, the fallback's
  single-machine durability, the push relay's dependence on a live tower,
  and the attention marker's dependence on the hook).

### Pre-flip verification

- **Post-lens stale-reference sweep.** Run after the minting: no reference
  to the pre-edit wording, the old knob counts, the tagged-fragment
  fallback, the old catch-up name, the date-only citation form, or the
  non-existent check name remains in the four files; the brief's own
  figures were reconciled as listed above.
- **Lint.** `markdownlint-cli2` over the brief and the four spec files: 0
  errors. No prose line exceeds 80 columns; only single-line H3 headings
  do, as the format requires.
- **Recorded claims re-derived.** Nine rule docs resolved (the header's
  list has nine entries). Requirement bullets and test-spec entries match
  one to one (a fixed-string count of each, equal). Every decision heading
  is in the section 4 ledger (D-1 to D-19). The critical path was
  recomputed from the `Estimated effort:` lines after the rewrite and the
  section 6 figure corrected. The validator, run both against `origin/main`
  and with `--baseline HEAD`, reports 0 errors and 0 warnings; the dead-path
  pairing rule fires on the second form and is clean.

**One expression-only fix after the lens pass.** The status render (the
canonical execution read surface) rejected every `Dependencies:` line
written in the `Task <n>` form as malformed, leaving nine tasks
undispatchable, while the validator had accepted it; the lines were
rewritten to the bare-id form the format prescribes before the anchor was
computed, and the render now shows Tasks 1 and 7 ready and the rest blocked
on their edges. The validator's silence on that form is recorded as an
observation.

### Sign-off record

Signed off 2026-09-09 by the operator after the approval summary; the four
spec files flipped Draft → Ready with `Last reviewed:` bumped; the
validator re-run at Ready reports 0 errors, 0 warnings; the status render
derives Ready with two tasks dispatchable.

Class: meaning
Lens-pass: the full-bundle lens review recorded in this section (nine-lens
fan-out, dispositions above), preceded by the mid-walk delta lens pass
recorded in section 3
Anchor: `2f461e0c6e78d2cce6d4a2b73f4c8bec4ec5e268` — computed as
`scripts/spec-anchor.sh specs/tower-comms`

## 9. Amendment log

### Re-anchor — Task 7 expression-only edit (2026-09-12)

Machine-written entry per the meta-spec's expression-only lane
(`doctrine/spec-format.md`, *Sign-off records and content anchors*),
recorded by the `/execute-task` run for Task 7 at its convergence pass.

**Why the anchor moved:** one expression-only edit inside the bundle. The
test-spec entries for REQ-E1.7 and REQ-I1.4 assign the no-subject judgment
sentence and the scope statement to the rule doc Task 7 delivers, but Task
7's `Citations:` line named neither requirement; it now does. Both files
bump `Last reviewed:`. `requirements.md` carries the paired changelog
entry. No REQ, D-ID, or `Done when:` condition changes meaning.

**Cites the changelog line:** the 2026-09-12 `## Changelog` entry in
`specs/tower-comms/requirements.md` ("Task 7 expression-only edit").

Class: expression-only
Anchor: `6fca6cf8ebc13883ce351a5f2e84f7a6df49bcf5` — computed as
`scripts/spec-anchor.sh specs/tower-comms`
