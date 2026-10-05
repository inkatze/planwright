# Quota handling — Design

**Status:** Ready
**Last reviewed:** 2026-10-05
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` new in this bundle; `C, <namespace> <id>` carried from
another bundle's decision.

## Decision log

### D-1: Altitude — mechanism-primary, no new doctrine  (N)

**Decision:** The rules this bundle states (hold by default, resume only on
evidence, never retry into a refusal, no spend control for a non-Claude
vendor) live in this bundle's requirements and decisions and are enforced
by deterministic scripts: the classifier, the hold store, the step runner,
and the review-request command. The adapter contract is documented in a
reference document under `docs/`, and `doctrine/custom-steps.md` gains
only a pointer line where it lists outcomes. Vendor-specific values
(recognizer strings, bot logins, control invocations) live in overlays.

**Alternatives considered:**
- A new doctrine document stating an external-limits posture. Rejected
  because: every rule here is mechanically checkable, and autopilot-reflex
  step 5 prefers a mechanical tool to an instruction an LLM follows; a
  doctrine document would add instruction-budget load to every skill that
  cites it.
- A quota section in `doctrine/custom-steps.md`. Rejected because: that
  document is charged to an instruction-budget closure, and Claude's
  worker-death handling is not a steps concern.
- Deferring the call to kickoff. Rejected because: an altitude trigger
  fired mid-flow (the requirements acquired doctrine-shaped rules), and
  the autopilot-reflex doctrine requires resolving it before design.

**Chosen because:** The trigger was a mechanism acquiring rules that read
like doctrine; the resolution is that the rules are mechanism-enforced
invariants of this capability, not a way of thinking a skill must follow.

### D-2: A new bundle consuming three owners as contracts  (N)

**Decision:** Spin `quota-handling` as its own bundle. custom-steps,
fleet-autonomy, and model-allocation are consumed as contracts; the one
change to a signed contract (D-3) travels as a custom-steps amendment
through that bundle's own ritual.

**Alternatives considered:**
- Extend custom-steps. Rejected because: custom-steps excludes wrappers
  for external review tools and owns no usage accounting or worker-death
  classification; folding the vendor adapter in would push it past one
  feature a reader holds in their head.
- Extend fleet-autonomy. Rejected because: it is signed off and
  Claude-only by construction, and step outcomes are not its domain.

**Chosen because:** The per-vendor adapter is a new external interface
whose decisions are orthogonal to each owner's domain, which is a spin-new
trigger under the fold-detection rule.

### D-3: `limited` is a sixth step outcome, via a custom-steps amendment  (N)

**Decision:** Add `limited` to the step outcome set by amending
custom-steps: supersede its REQ-D1.1 to widen the set, and add the step
catalog fields this bundle needs (`vendor`, `control`, `on-limit`,
`moves-head`, `final-head`, `drains`), two context fields carrying the previous and
new head SHAs (D-12), the resume-continuation rule of D-8, and `skipped`
produced outside the missing-step matrix: by the review-request command's
same-head skip (D-11) and by D-8's resume skip, with how a `continue`-hosted
step treats a skipped predecessor (custom-steps REQ-D1.4) restated for
both. The amendment also carries the `limited` entry in
`doctrine/custom-steps.md`'s outcome list, since that list is custom-steps'
normative home. It is drafted with `/spec-draft --extend custom-steps` and
signed in a delta kickoff. This bundle's tasks that write a `limited` step
record or read the new fields wait on it landing.

**Alternatives considered:**
- Record a limit as `halted` with a cause token. Rejected because:
  custom-steps REQ-D1.2 binds `halted` to the on-failure posture, which
  ends the point, so on-limit and on-failure would both key on `halted`
  and every reader would have to inspect the cause to tell a hold from a
  stop.
- Supersede custom-steps REQ-D1.1 from this bundle directly. Rejected
  because: custom-steps would then cite a supersession it never signed,
  and its kickoff brief would go stale silently.

**Chosen because:** It keeps every signed contract signed by its owner,
and a distinct outcome lets the record table, the PR-body fold, and the
flip-point status treat a hold as neither success nor failure.

### D-4: Fixed-string recognizers; unknown stays as classified  (N)

**Decision:** A vendor-bound step's captured output (a command step's
stdout and stderr, a skill or prompt step's handoff excerpt, the
review-request command's printed bot reply, a worker's event stream or
headless `result.json` error text) is matched against the adapter's
recognizers as fixed, case-sensitive substrings by a core classifier
script. A match yields `limited` with the matching recognizer's id, a
screened excerpt, and a reset time when the adapter declares where one
appears; no match leaves the custom-steps classification untouched. The
excerpt is screened exactly as `scripts/step-record.sh` screens a record
excerpt (its canonical sanitizer, secret screen, and excerpt bound), and
the same excerpt, flattened to one line, is the *reason* the hold store,
the ledger, and the attention push carry. A located reset time is accepted
only as an ISO-8601 UTC timestamp or epoch seconds; an unparseable value,
one already past, or one beyond the throttle's existing hold ceiling is
treated as no stated reset time.

**Alternatives considered:**
- Anchored regular expressions. Rejected because: a pattern from overlay
  data carries backtracking and injection risk that security-posture
  rules out for parsed input.
- Classifying by model judgment. Rejected because: fleet-autonomy D-18
  keeps an LLM out of routine daemon and hook mechanics, and a judged hold
  cannot be reproduced.

**Chosen because:** Fixed strings are the least expressive form that
covers every refusal observed so far, and they fail toward the existing
behavior (a visible failure) rather than toward a silent hold.

### D-5: Hold by default, with a declarable on-limit posture  (N)

**Decision:** A step's `on-limit` field takes `hold` (default),
`continue`, or `alternate <step-id>`. `hold` holds the unit in the hold
store (D-6). `continue` records `limited` and runs the rest of the point.
A `limited` record from any point of the run, on the head about to be
flipped, refuses the flip whatever its posture, as a `halted` one does.
`alternate` runs the named step once in the held step's place; resolution
refuses an alternate bound to the same vendor, an alternate that itself
declares `alternate`, and a missing id. An alternate that is itself
classified `limited`, or finds its own vendor held, takes `hold`.

**Alternatives considered:**
- Hold only, fixed. Rejected because: a monthly quota would stall a unit
  for a month unless the operator intervened by hand.
- Hold the step and run the rest of the point. Rejected because: later
  steps would run on a head the held step never reviewed, breaking the
  declared order.

**Chosen because:** The operator chose a declarable posture with hold as
the default; the flip-point rule keeps `continue` from becoming a path to
ready-flipping past an unreviewed head.

### D-6: A host-wide vendor hold store  (N)

**Decision:** Holds live in the fleet home under one directory per vendor,
written under the existing lock library, and every vendor-bound step
checks it before sending a request. A step that finds its vendor held
takes its posture with outcome `limited` and the hold's recorded reason,
sending nothing. The store is per host; a second host learns of a limit
by meeting it. The store is also where a held unit waits: it is recorded
there rather than as an Awaiting-input bullet, selection
(`scripts/orchestrate-select.sh`) skips a unit the store holds, and the
status render shows it held.

**Alternatives considered:**
- Per-unit holds. Rejected because: every other unit would spend one
  request, metered or refused, to learn what the host already knows.
- A cross-host store. Rejected because: the fleet home is the host's
  durable state, and no cross-host state channel exists to build on.
- Parking a held unit with an Awaiting-input bullet. Rejected because: the
  bullet is committed on the task branch, and spec-format allows park and
  unpark writes only by the human or a halting skill, so the automatic
  resume sweep could not release it without a daemon committing to task
  branches.

**Chosen because:** It makes "no further requests to a held vendor" a
property of the host rather than of each run, reusing the fleet home and
lock library already trusted for fleet state.

### D-7: Evidence-only automatic resume, operator resume, push surfacing  (N)

**Decision:** A hold records its vendor, reason, stated reset time,
holding units (with the step held, or `worker` for a worker death, D-15),
and the time it began, and pushes an attention event through the existing
attention store naming the vendor, the reason, the stated reset time, and
the operator's resume command. Recording a hold and pushing its event are
one act of the hold store, whichever caller holds. Automatic resume is attempted only
by a sweep the attention watcher's reconcile pass already runs: for each
held vendor it asks the vendor's evidence kind whether the limit cleared,
and releases on a positive answer. Evidence kinds are a closed core set
(D-9). The operator's resume command releases a vendor unconditionally.
Release is staged: it marks the vendor's hold as probing and releases the
longest-held unit alone, with no commit, through the normal selection
path. When that unit's first request to the vendor (a vendor-bound step,
or for `claude` the re-dispatched worker) ends with any outcome but
`limited`, the hold record is deleted and every other held unit
re-dispatches; when it is refused, the hold renews and the others never
send. A false release therefore costs at most one request.

**Alternatives considered:**
- Resume when the stated reset time passes. Rejected because: the clock
  passing says nothing about the new window, and resuming on it alone
  dispatched blind in the incident obs:c24a01af records.
- Releasing every held unit at once. Rejected because: a release on
  wrong evidence, or an early operator resume, would spend one refused
  metered request per held unit before the hold re-formed.
- A dedicated resume daemon. Rejected because: the attention watcher
  already runs a periodic reconcile, and a second daemon adds a liveness
  surface to watch.

**Chosen because:** The operator chose evidence-only resume; reusing the
attention store and watcher keeps surfacing push-based, never a status
command the operator must remember to poll.

### D-8: Resume continues the point from the held step  (N)

**Decision:** A resumed unit starts a new run, as custom-steps defines.
A step record's head is the head after the step ran. The runner reads the
interrupted run's records and skips each step recorded `passed` or
`applied` whose recorded head equals the current head, recording it
`skipped`, and starts real work at the first step not so recorded. If the
head moved while the unit was held, no record matches and nothing is
skipped.

**Alternatives considered:**
- Restart the held step's whole point. Rejected because: it re-spends the
  earlier steps' cost (polish, an external-model panel) for no new
  information.

**Chosen because:** Same-head records are exactly the evidence that a
step's work still holds; a moved head invalidates that evidence, so the
rule degrades to a full re-run where it must. Skipping is part of the
custom-steps amendment (D-3) because it changes "the chain that runs is
the chain declared".

### D-9: Adapters are a data catalog with a closed set of evidence kinds  (N)

**Decision:** A `vendors` catalog, merged by `scripts/resolve-catalog.sh`
across the overlay layers as the steps catalog is, with its constrained
reader unchanged: every field a single-line scalar. An adapter is
therefore spread over flat entries that share a `vendor:` field, one per
part, each with the id `<vendor>.<name>` so overlay merge and supersede
work per part: one vendor entry (`evidence`, one of the core kinds, and
`bot-login` for a PR-comment vendor); one entry per recognizer (a fixed
string, plus an optional reset-time locator naming a fixed prefix after
which a timestamp appears); one entry per control (a name in the vendor's
vocabulary mapped to its invocation: a comment body for a PR-comment
vendor, an argument string for a CLI vendor); and one entry per
choice-rule pair (rule name, position, condition, control). The resolver
groups the merged entries by vendor; a part whose vendor has no vendor
entry is malformed. Core implements the evidence kinds `claude-frames`
(D-14) and `none`; adding a kind is a core change.
Core ships the `claude` entry. The reference document illustrates a
PR-comment review bot and an external CLI with invented placeholder
vendors, never a real product's name, login, refusal wording, or
commands; the operator writes their real vendors' strings in an
overlay. Malformed entries follow the catalog's by-layer
policy.

Field grammars, all checked by the vendors validator before use: `id` and
recognizer ids follow the step-id grammar; `bot-login` is the login GitHub's
REST API reports, `[bot]` suffix included; a comment-body control may
mention no handle other than the `bot-login`, carries no issue or URL
reference, and is size-capped; a CLI control's arguments follow
custom-steps' plain-word `args` grammar and are passed as separate argv
entries, never through a shell.

**Alternatives considered:**
- Executables on PATH that answer adapter verbs, mirroring the backend
  seam. Rejected because: overlay-supplied code would run on every
  classification, contradicting REQ-C1.5.
- Nested adapter entries, by extending the shared reader or by a
  dedicated vendors parser. Rejected because: the shared reader serves
  every catalog under the bash 3.2 floor, and a second parser would be a
  second untrusted-input surface to keep in step with security-posture.
- A data catalog plus an operator-declared probe command as an evidence
  kind. Rejected because: it widens the trusted surface to an overlay
  command; it remains available later as a new core evidence kind with
  its own review.

**Chosen because:** The steps catalog already proves this merge path, and
data-only adapters keep every vendor's contribution inspectable and inert.
Flat per-part entries keep the shared reader untouched (it stays
bash-3.2-safe and is shared by every catalog), at the cost of more
verbose authoring.

### D-10: Controls in vendor vocabulary, with a history-keyed choice  (N)

**Decision:** A step names a control as `<vendor>:<control>`, or names a
choice rule the adapter declares. A choice rule is an ordered list of
`(condition, control)` pairs over a closed condition set the ledger can
answer for the current PR (`no-prior-review`, `prior-review`, where a
review is a request the vendor answered, its reply not classified
`limited`); the first matching pair wins. Core never translates between vendors' controls.

**Alternatives considered:**
- A common vocabulary (`full`, `incremental`, `effort:<n>`) that adapters
  map onto. Rejected because: the operator directed that vendors' options
  do not map one to one and the spec must not assume they do.

**Chosen because:** The closed condition set is the least needed to
express "full first, incremental after", and every other choice stays in
the vendor's own terms.

### D-11: One vendor-agnostic review-request command  (N)

**Decision:** Core ships a command step script that, given a vendor, a
control or choice rule, and a required `--wait <seconds>` shorter than the
step's timeout, checks the hold store, checks the ledger for a request on
the current head that the vendor answered (skipping, outcome `skipped`,
when found; a refused or unanswered request does not count), confirms the
adapter's `bot-login` is a bot account on GitHub, posts the control's
comment body to the PR from a file (never interpolated into a command
line), records the request with its head, then waits up to `--wait` for a
reply and prints it screened for the classifier. A reply counts only when
it is a new issue comment or PR review, authored by the `bot-login`,
reported by GitHub as a Bot, and created after the recorded request;
edits to earlier comments and every other author are ignored. The command
records an answer line for that head when the classifier does not return
`limited`, and exits non-zero (`failed`) when no reply arrives in time.
Posting to an automated reviewer is outside the messages-to-people
confirmation the operator's conventions require; the comment still reaches
the PR's subscribers, which is why the control body may address only the
bot (D-9).

When the ledger holds no line for the PR (a first run after rollout, or a
lost fleet home), the command rebuilds the PR's history from the PR's own
comments by the `bot-login` before choosing, so the ledger stays runtime
state with a rebuild path, per the storage-classes doctrine.

**Alternatives considered:**
- The operator's own command or skill surfaces the reply. Rejected
  because: the reply is what classification reads, and REQ-F1.1 requires
  the request, classification, hold, and resume to be shipped, unlike the
  panel and drain steps it lets an overlay name.
- A new `bot` step kind. Rejected because: it widens the custom-steps
  kind set, a second cross-bundle amendment, for behavior a command step
  already hosts.

**Chosen because:** Every vendor-specific string stays in the overlay
adapter, so the command is a capability rather than a vendor wrapper; the
bot-account check and the author pin make it unable to message a person or
to act on a person's comment as the bot's.

### D-12: Head-moved signal and final-head ordering  (N)

**Decision:** After each post-pr step, the runner compares the PR head to
the head before the step; on a change it records both SHAs in the step
record and adds them to the fixed step context of every later step at
that point. Steps gain `moves-head: true` (the step may push),
`final-head: true` (the step runs only after every head-moving step at its
point), and `drains: <step-id>` (a head-moving step that applies the
findings of the named final-head step). Resolution refuses a list placing
a `final-head` step before a `moves-head` step, except a `moves-head` step
whose `drains` names that `final-head` step; it refuses a `drains` naming a
missing step or a step that is not `final-head`. The three fields and the
two head context fields travel in the custom-steps amendment (D-3).

**Alternatives considered:**
- Ordering by documentation only. Rejected because: a misplaced bot step
  would silently review a stale head and spend quota on it.
- Declaring a drain without `moves-head`. Rejected because: it makes the
  declaration false for exactly the steps that push, and a later rule
  that trusts `moves-head` (re-firing earlier checks after a commit,
  obs:6c3342a8) would inherit the lie.
- Carrying the signal across runs. Rejected because: the ledger's
  per-PR request history already answers what the next run needs (D-10).

**Chosen because:** A declared, checkable ordering is cheaper than
discovering a stale-head review after the quota is spent, and an explicit
drain link keeps every declaration true while scaling to several metered
reviewers, each paired with its own drain.

### D-13: A machine-local per-vendor ledger  (N)

**Decision:** One append-only line-oriented file per vendor under the
fleet home records requests, answers, refusals, holds, and resumes, each
with its time, the PR and head where the event has one, and the
recognizer id for a refusal; never committed. Every field is checked
against its grammar and stripped of control characters on write (PR
numbers decimal, heads 40 or 64 hex characters, unit ids in the
fleet-state field grammar, ids in the step-id grammar, reasons as D-4
defines them), and a line that fails the grammar on read is skipped, never
trusted. The retention knob `quota_ledger_retention_days` prunes lines
older than its value, defaulting to 90 days so a live PR's request history
outlives the PR and pruning never makes a later request look like a first
review. The ledger is runtime state: its rebuild path is D-11's. The fleet
status surface (`scripts/fleet-stats.sh render`), which already prints
the Claude throttle and usage-gate rung, gains a vendor view rendering
hold state, its reason, and counts over the retention period.

**Alternatives considered:**
- Committing usage records. Rejected because: they are host- and
  account-specific operational detail, which artifact data-hygiene keeps
  out of committed artifacts.

**Chosen because:** The fleet home is already the durable machine-local
home of fleet state, and line files keep the ledger readable by the
portable shell tooling the repository is built from.

### D-14: Claude clearance evidence from worker rate-limit frames  (N)

**Decision:** The stream-json supervisor persists each worker's newest
rate-limit frame in the fleet home beside the worker's other runtime
state. The `claude-frames` evidence kind reads across those files per
window, since each frame carries a session and a weekly reading and the
usage gate governs each window separately: for each window, ignore every
reading whose reset time has passed and take the one with the
furthest-future reset. A Claude hold clears only when every governed
window has a reading received after the hold began and below that
window's lowest-rung descend threshold (an existing knob, so no new
threshold), so a window dropping out as its reset passes can never let
the clock release a hold. The reading is labelled account-wide wherever
it is rendered. A backend emitting no frames, and a fleet with no live
frame, report unmeasured. The usage gate's own signal (fleet-autonomy's
`/usage` read) is untouched; frames feed no gate producer here.

**Alternatives considered:**
- Feeding the frames to the usage gate as a second producer. Rejected
  because: fleet-autonomy defines that signal as its `/usage` read with
  its own TTL, plausibility, and hysteresis rules, and changing it is that
  bundle's amendment to sign, not this one's.
- Scraping the interactive usage view. Rejected because: driving a TUI is
  forbidden to the tower, and obs:7e67fe74 found no producer for it.
- Deriving a percentage from transcript token counts. Rejected because:
  the window's denominator is unpublished, so every threshold would need
  re-deriving.

**Chosen because:** The frames already carry the exact percentage and
reset time a clearance check needs; the staleness rule is the one
verified on 2026-09-02 (obs:c24a01af).

### D-15: Worker-death classification on every rung, and the throttle  (N)

**Decision:** Every completion reader this bundle owns (the stream-json
status, its exit fallback, the headless rung's `result.json`, which no
reader parses yet and gains one here, and the stuck detector) reads the
error signal and the error text (the stream-json event stream, or the
headless result's `is_error` and result text), never only an exit code or
a result subtype. A rate-limit error classifies the death `limited`
against the `claude` vendor, records a hold whose step is `worker`, and
engages fleet-autonomy's throttle through `scripts/fleet-throttle.sh
engage --until <epoch>` with the stated reset time, or through its
`observe` verb over the error text when none was stated (its degraded
default applies); any other API error is a failure naming its cause. The
tmux worktree rung and `/offload`'s tmux, print, and subagent rungs have
no completion reader to correct and are out of this decision.

**Alternatives considered:**
- Classifying only on the stream-json rung. Rejected because: the same
  false clean completion recurs one rung over (obs:f0b55c65,
  obs:d9681390).

**Chosen because:** A worker's death is the Claude vendor's refusal, so it
takes the same classification and hold as a step's, and the throttle's
structured verb finally gets a caller.

### D-16: The boundary — no retry, no spend, prediction deferred  (N)

**Decision:** Never retry into a limit refusal; never offer a spend,
upgrade, or overage control for a non-Claude vendor; defer forecasting a
non-Claude quota until a vendor offers a supported readout.

**Alternatives considered:**
- Bounded retry with backoff. Rejected because: each retry against a
  metered bot spends or wastes a request, the cost the seed names.
- Quota forecasting now. Rejected because: no observed vendor offers a
  supported readout, so there is nothing to build on.

**Chosen because:** The operator adopted this boundary; the spend floor
mirrors fleet-autonomy REQ-E1.11's decline-by-default posture.

## Cross-cutting concerns

- **Security.** Adapter fields, bot replies, ledger and hold-store lines
  read back, frame files, and event-stream text are untrusted: matched as
  fixed strings, printed with `printf` after the canonical sanitizer, and
  never interpolated into a command. The comment body is posted from a
  file. Vendor, step, recognizer, and unit ids, PR numbers, and head SHAs
  are validated against their grammars (D-9, D-13) before any path,
  ledger, or context use. Frame utilizations must parse as numbers in
  range and reset times as epochs within the throttle's ceiling; anything
  else is unmeasured. Examples in `docs/quota.md` use invented placeholder
  vendors, and the `[manual]` observation records a vendor's refusal in
  shape only, never an account, plan, or billing detail.
- **Concurrency.** The hold store and ledger are written under the lock
  library, since several units on a host can meet the same limit at once.
- **Research.** No new dependency is adopted. The Claude frame shape and
  the staleness rule come from recorded observations (obs:c24a01af); real
  review bots' refusal text and commands stay in the operator's overlay,
  where a vendor's wording change is the operator's edit, and the shipped
  examples are placeholders (an IP-posture call: no third-party names or
  quoted wording in planwright's own docs).
