# Quota handling — Kickoff Brief

## 1. Header

- **Spec path:** `specs/quota-handling/`
- **Spec commit at walkthrough start:** `1dab81a8`
- **Walkthrough date:** 2026-10-05
- **Mode:** first activation (Status Draft, no prior brief)
- **Validator (pre-flight):** `scripts/spec-validate.sh specs/quota-handling`
  reported no errors and no warnings.
- **Config:** `commit_on_kickoff` and `mark_spec_pr_ready_on_kickoff` true,
  `kickoff_ready_ci_wait` at its default, all from `config/defaults.yml` with
  no local override.
- **Decision/transcript log:** no harness-provided log in this session; the
  turn mirror is skipped.

## 2. Goal & glossary

**Goal (restated).** Today a quota, usage, or rate-limit refusal from a
service planwright depends on (a hosted review bot, an external model CLI,
Claude itself) reads as an ordinary failure: the unit fails, a retry spends
another metered request, and a Claude rate-limit death can even be recorded as
a success. This bundle makes such a refusal its own step outcome, `limited`.
By default the step holds: the unit parks with the reason pushed to the
operator, and no step on the host sends that vendor a request until the
vendor's adapter shows positive evidence the limit cleared or the operator
resumes. A stated reset time passing is not evidence. Each vendor is a
data-only adapter (refusal recognizers, evidence kind, controls in the
vendor's own vocabulary, never mapped to a shared one). A post-pr head-moved
signal lets a metered bot review only the final head, and a machine-local
per-vendor ledger extends usage accounting beyond Claude.

**Rules out.** Retrying into a refusal; spend, upgrade, or overage controls
for non-Claude vendors; re-running earlier points after a post-pr commit;
changing the Claude usage gate's ladder or thresholds; third-party adapters
active by default; merge and ready-flip authority.

**Assumes.** The custom-steps amendment (D-3) lands first through that
bundle's own extension and kickoff; Claude's worker rate-limit frames are a
sound enough signal to drive automatic resume (obs:c24a01af).

**Implicit terms.**

- *Vendor*: any metered external service a step depends on, Claude included.
- *Vendor-bound step*: a step whose catalog entry names a `vendor`.
- *Flip point*: a point whose terminal act is a draft-to-ready flip
  (custom-steps REQ-E1.3).
- *Fleet home*: the host's durable machine-local state root
  (`scripts/fleet-state.sh root`).
- *Metered step* (REQ-D1.3): resolved below.

**Resolutions.**

- *Metered step* means the review-request command only, matching D-11 and
  Task 9; other vendor-bound steps re-run normally on the same head.
  REQ-D1.3 is reworded accordingly (edit list, section 3).

Signed off: 2026-10-05

## 3. Requirements walkthrough

Per-group outcomes:

- **REQ-A (classifying a refusal).** Confirmed as written. A recognizer that
  appears in a legitimate reply (a review quoting a refusal phrase) yields a
  false hold; accepted as a risk (register row 1), since the hold is pushed
  and cleared by an operator resume.
- **REQ-B (holding and resuming).** Two resolutions:
  - *Inconsistency halt, resolved by spec edit.* The ledger recorded a
    request before the bot answered, so after a refusal a same-head resume
    hit the same-head skip (REQ-D1.3) and the review never ran, breaking
    REQ-B1.6 and REQ-F1.2; the history-keyed choice (REQ-C1.3) likewise
    counted a refused request as prior. Resolved by keying both on an
    *answered* request: a refused or timed-out request does not count. A
    late-replying bot may be asked twice; accepted (register row 2).
  - *Gap, resolved by spec edit.* Parking a held unit as a committed
    Awaiting-input bullet left the automatic release with no sanctioned
    writer (spec-format allows park writes only by the human or a halting
    skill). The vendor hold store is now the park: selection skips a held
    unit, the status render shows it, and release makes no commit.
- **REQ-C (vendor adapters).** Confirmed; REQ-C1.3 reworded by the REQ-B
  resolution.
- **REQ-D (head-moved signal).** Confirmed; REQ-D1.3 narrowed to the
  review-request command (section 2) and reworded by the REQ-B resolution.
- **REQ-E (usage accounting).** REQ-E1.2's "existing status surface" named
  as `scripts/fleet-stats.sh render`, where the Claude throttle and rung
  already render. REQ-E1.1 gains the answer line kind.
- **REQ-F (acceptance).** REQ-F1.1 clarified: the panel and the bot-review
  drain may be overlay entries naming operator-installed commands (custom-
  steps keeps review-tool wrappers out of core); the bot request,
  classification, hold, and resume must be shipped. D-11's rejected
  alternative reworded to match.

**Consolidated spec-edit list** (all applied in place; Draft bundle):

1. REQ-D1.3: "a metered step" becomes "the review-request command"; skip
   only after an answered request on the current head (design D-11, Task 9,
   test-spec REQ-D1.3 follow).
2. REQ-C1.3 and D-10: choice conditions become `no-prior-review` /
   `prior-review` over answered requests (test-spec REQ-C1.3 follows).
3. REQ-E1.1, D-13, test-spec REQ-E1.1: ledger records answers.
4. REQ-F1.1, Task 10, test-spec REQ-F1.2: "full until the bot has answered
   a request on the PR"; "no second request before the resume"; resume
   re-sends the full-review request on the same head.
5. REQ-B1.1, D-6 (new rejected alternative), D-7, Task 4, test-spec
   REQ-B1.1: the hold store is the park; no `tasks.md` write, no commit on
   release; `scripts/orchestrate-select.sh` skips a held unit.
6. REQ-E1.2, D-13, Task 3, test-spec REQ-E1.2: vendor view in
   `scripts/fleet-stats.sh render`.
7. REQ-F1.1, D-11, Task 10, test-spec REQ-F1.1: operator-command panel and
   drain allowed via overlay.
8. Expression-only factual fixes: D-1 (custom-steps doctrine is
   budget-charged, not protected), D-2 (fleet-autonomy is signed off, not
   Done), D-4 (fleet-autonomy D-18's actual scope), D-15 and Task 5 (the
   headless rung's `result.json` has no reader yet; Task 5 adds one).

**Mid-walk lens (delta-scoped, inline).** Run over edits 1, 2, 5 and their
dependents (REQ-F1.1, REQ-F1.2, Task 4, Task 9, Task 10, test-spec
entries). Findings: three dependent wordings went stale ("first request" in
REQ-F1.1; "no second request" in Task 10 and test-spec REQ-F1.2) and were
reworded in edit 4. No other finding.

Signed off: 2026-10-05

## 4. Design walkthrough

Reconciled ledger (every D-ID in `design.md`):

- **D-1** amended (expression-only): the rejected custom-steps doctrine
  section is budget-charged, not in the protected set. Altitude call
  (mechanism-primary, no new doctrine) confirmed.
- **D-2** amended (expression-only): fleet-autonomy is signed off, not
  Done; the spin-new rationale confirmed.
- **D-3** confirmed: `limited` as a sixth outcome via a custom-steps
  amendment signed in that bundle's own kickoff.
- **D-4** amended (expression-only): fleet-autonomy D-18 cited for its
  actual scope (routine daemon and hook mechanics). Fixed-string matching
  confirmed; false-match risk accepted (register row 1).
- **D-5** confirmed.
- **D-6** amended: the hold store is also the unit's park; new rejected
  alternative records why an Awaiting-input bullet cannot be the park.
- **D-7** amended: release deletes the hold record with no commit.
- **D-8** confirmed.
- **D-9** confirmed.
- **D-10** amended: choice conditions `no-prior-review` / `prior-review`,
  over requests the vendor answered without a refusal.
- **D-11** amended: same-head skip only after an answered request; the
  command records an answer line; the rejected operator-command alternative
  reworded to REQ-F1.1's clarified line.
- **D-12** confirmed.
- **D-13** amended: answer line kind; vendor view lives in
  `scripts/fleet-stats.sh render`.
- **D-14** amended: the staleness and furthest-future rule applies per
  window (session and weekly), matching the usage gate's per-window
  governance. (Further amended by the sign-off lens pass, section 8: frames
  feed clearance evidence only, never the usage gate.)
- **D-15** amended (expression-only): the headless rung's `result.json` has
  no reader today; Task 5 adds one.
- **D-16** confirmed.

No design decision contradicts a walked requirement after the section 3
edits.

**Mid-walk lens (D-14 delta, inline).** Dependents checked: REQ-B1.4,
Task 7, test-spec REQ-B1.4 speak of a "fresh low-utilization frame", which
the per-window rule still satisfies. No finding.

Signed off: 2026-10-05

## 5. Verification approach

- **Coverage mix.** Per `test-spec.md`'s intro and per-entry tags: nearly
  every REQ is `[test]`, several add `[Gherkin]` scenarios the fixtures must
  produce, a few add `[design-level]` checks against `docs/quota.md` or a
  decision, and one carries `[manual]`.
- **Ownership.** `[test]` entries run in `scripts/run-tests.sh` under
  `mise run check` and the repository CI. The `[manual]` entry (REQ-F1.2:
  the first real bot quota refusal checked against the acceptance outcomes,
  recorded as an observation) is swept by the operator and inventoried by
  `/drain`.
- **Dead paths.** None found during the walk. The section 3 edits carried
  their test-spec pairing in the same edit. The sign-off lens pass
  (section 8) later found several: runner behaviour has no script to drive,
  so those entries now run as recorded terminal-rung fixture overlays; the
  headless rung has no event stream; and the review-request command could
  not see the step timeout. All were fixed there.

Signed off: 2026-10-05

## 6. Task graph

Reconstructed from the `Dependencies:` lines in `tasks.md` (authoritative;
efforts are each block's `Estimated effort`, not copied here).

- **Roots:** Task 1 and Task 8. Task 8 is parked behind the custom-steps
  amendment (its Awaiting-input bullet), as is Task 2.
- **Fan-out after Task 1:** Tasks 2 and 3; after Task 3: Tasks 5 and 6.
- **Joins:** Task 4 (2, 3); Task 7 (4, 6); Task 9 (2, 3, 8); Task 10
  (4, 7, 9).
- **Critical path:** Task 1 → Task 2 or Task 3 → Task 4 → Task 7 →
  Task 10, gated in practice by the custom-steps amendment landing (Task 2
  sits on it).
- **Parallelism:** Task 8 runs beside the whole Task 1 branch; Tasks 5 and
  6 run beside Tasks 2 and 4; Task 9 joins late.

**Edit applied (task-graph walk).** The limit classifier moved from Task 2
to Task 1 (Task 1 renamed and re-estimated, Task 2 renamed; D-4 and
REQ-A1.5 added to Task 1 and kept on Task 2, which writes the record;
REQ-A1.2 moved to Task 1; D-4 added to Task 5). Reason:
Task 5 runs worker event streams through the classifier (D-4) but did not
depend on Task 2, and Task 2 waits on the custom-steps amendment that
worker-death handling does not need; with the classifier in Task 1, the
worker false-success fix ships without waiting on the amendment.

**Deliberate non-edges** (do not "fix"):

- Task 5 does not depend on Task 2: it writes worker status and a hold,
  not a step record, so it needs neither the `limited` step outcome nor
  the amendment.
- Task 6 does not depend on Task 5: the frame producer reads frames from
  live workers and does not need deaths classified.
- Task 8 does not depend on Task 1: the head-moved signal is
  vendor-agnostic.
- The custom-steps amendment is not a task here (D-3); it travels through
  that bundle's own extension and kickoff, tracked by the two
  Awaiting-input bullets.

Signed off: 2026-10-05

## 7. Risk register

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | A fixed-string recognizer matches legitimate output (a review quoting a refusal phrase) and holds a unit falsely. | Accepted. The hold is pushed with its excerpt and cleared by an operator resume; adapter authors pick distinctive strings. Signal: a hold whose excerpt reads as an ordinary review. |
| 2 | A request that timed out without a reply does not count as answered, so a late-replying bot can be asked twice on one head, spending quota. | Accepted (the resume/skip resolution, section 3). Signal: two request lines on one PR and head in a vendor's ledger with no answer line between them. |
| 3 | The custom-steps amendment (D-3) is not drafted yet; Tasks 2 and 8, and through them the critical path, wait on it. | Ship-gate: the Awaiting-input bullets on Tasks 2 and 8. Next step after merge: `/spec-draft --extend custom-steps` and its delta kickoff; Tasks 1, 3, 5, 6 proceed meanwhile. |
| 4 | A vendor changes its refusal wording, so recognizers miss and a quota refusal reverts to a visible failure. | Fails toward today's behavior by design (D-4). Signal: a failed vendor-bound step whose output reads as a quota message; the fix is an overlay edit. |
| 5 | Claude frames are account-wide, so other sessions' consumption can keep a Claude hold from auto-releasing. | REQ-E1.4's ceiling semantics and label; operator resume stays available. Signal: a Claude hold outliving the fleet's own activity. |
| 6 | A `none`-evidence vendor with a monthly quota holds its units until the operator acts. | The push surfaces it at hold time; the `continue` and `alternate` postures exist for exactly this case. |
| 7 | The hold store is per host (D-6): a second host meets the limit independently and spends one refused request. | Accepted in D-6; no cross-host state channel exists. |
| 8 | A head moved while a unit was held, so the resumed run re-runs every step (D-8), re-spending earlier steps' cost. | Accepted: a moved head invalidates the earlier records' evidence. |
| 9 | A worker classified on the new completion readers changes how existing in-flight workers are recorded at rollout. | Task 5's fixtures cover each rung; a rollout during a quiet fleet avoids mid-run reclassification. Signal: a worker recorded differently before and after the release. |
| 10 | The ledger starts empty at rollout, and is lost with the fleet home, so a PR the bot already reviewed could look unreviewed and get a second full review. | Decided in the lens pass: the review-request command rebuilds a PR's history from the bot's own PR comments when the ledger holds nothing for it (D-11). Signal: a full-review request on a PR the bot already commented on. |
| 11 | A release on wrong evidence, or an early resume, spends a request against a vendor still out of quota. | Decided in the lens pass: release is staged, one unit first (REQ-B1.5, D-7), so a false release costs at most one request. |
| 12 | Usage-gate producer stays absent: frames feed only Claude clearance evidence, so the proactive gate still runs blind. | Accepted in the lens pass (fork 1): changing the gate's signal is fleet-autonomy's amendment; obs:7e67fe74 and obs:d75dd699 returned to the live log for it. |

**Decision-domains gap check** (catalog resolved via
`scripts/resolve-catalog.sh decision-domains`):

- *secrets-config*: the ledger retention knob had no default; resolved in
  the walk as a 90-day default (REQ-E1.1, D-13, test-spec REQ-E1.1).
- *ip-posture* (escalated in the lens pass): example adapters in
  `docs/quota.md` use invented placeholder vendors, never a real product's
  name or quoted wording (REQ-C1.6, D-9).
- *human-comprehension*: the vendor view and held-unit render follow the
  existing `fleet-stats.sh` and status-render conventions; the hold push
  payload is fixed in D-7 (vendor, reason, reset time, resume command).
- *existing-seam-reuse*: the hold store is a second wait mechanism beside
  Awaiting input, decided in D-6 with its rejected alternative.
- *llm-output-quality*: decided by D-4 (deterministic classifier, no model
  judgment).
- *caching*: touched and decided (D-14's staleness rule for persisted
  frames).
- *data-storage* (hold store, ledger and its rebuild path: D-6, D-11,
  D-13), *concurrency* (lock
  library: D-6, cross-cutting), *api-surface* (vendors catalog, step fields,
  resume and review-request commands: D-3, D-9, D-11), *queues-async*
  (resume sweep and staged release: D-7), *observability* (attention
  pushes: D-7), *deploy-migration* (amendment ordering: D-3; rollout, rows
  9 and 10), *auth*
  (posting under the existing GitHub auth, bot accounts only: D-11):
  decided in the bundle.
- *dependency-adoption*, *versioning-scheme*,
  *product-strategy*, *packaging-pricing* (planwright meters nothing it
  sells), *knowledge-engineering*, *org-design*: not touched.

No open question remains.

Signed off: 2026-10-05

## 8. Sign-off

### Lens review (full bundle, first activation)

**Path.** Spec artifact class, so the spec lens set from
`doctrine/artifact-lenses.md`; fanned out to one read-only reviewer per
lens (plus one for the kickoff altitude and ship-gate items), merged and
deduplicated by the coordinator, then a self-critique pass. Tool grounding
first: `scripts/spec-validate.sh` reported no errors and no warnings before
and after.

**Validation (scoped, declared).** Each kept finding was checked against
its source rather than by three full passes: factual claims against the
code and the consumed bundles (custom-steps REQ-C1.4, REQ-D1.1 and its
fixed step context; the catalog reader's single-line fields; the throttle's
`observe` and `engage` verbs; fleet-autonomy REQ-E1.5's `/usage` signal;
the storage-classes losability rule; the dispatch rungs in
`docs/fleet.md`), logical claims by re-reading every place the rule is
expressed. Every checked claim held; none moved to the decline set.

| Lens (spec set) | Findings | Notes |
| --- | --- | --- |
| Contract correctness and internal consistency | 6 | `skipped` producer outside the matrix; final-head vs a pushing drain (fork 3); frames changing fleet-autonomy's gate contract (fork 1); amendment-gated REQs cited on Task 1; ledger PR/head on vendor-wide events; REQ-B1.2 under-stating D-5 |
| Ambiguity and interpretation forks | 13 | throttle verb; flip-refusal scope; a record's head; descend vs climb threshold; a window dropping out lets the clock release; "fresh"; reset-time format; excerpt bound; what counts as the bot's reply; worker-death hold step; `bot-login` form; view window; alternate that is itself limited |
| Citation and coverage integrity | 3 | REQ-C1.4 misstated the missing-step rule; REQ-C1.4 delivered by no task; Task 5 citations |
| Dead verification paths and testability | 9 | runner has no script to drive; headless has no event stream; unpaired no-commit check; vendor id missing from the record deliverable; head context has no channel; the command cannot see its timeout; unbounded "every rendering"; panel and drain stubs; `[manual]` prerequisite |
| Decision-domain gaps | 5 | ledger rebuild path; view window; release fan-out (fork 4); brief gap check missing four catalog domains; ip-posture of third-party examples (fork 5) |
| Cross-file consistency | 9 | nested adapter data vs the flat catalog reader (fork 2); throttle verb; worker-death hold push; amendment-gated citations; rung coverage; unbounded wait; Awaiting-input bullet scope; tasks intro vs Task 5; retention row placement |
| Documentation and glossary drift | 9 | "answered" vs "replies"; REQ-D1.2 scope; three meanings of "park"; D-5 citing D-7; Task 9 "first request"; REQ-D1.3 "resume"; `limited` as step outcome vs worker status; single-rung leftovers; two brief mismatches |
| Security (reframed) and rendered-content safety | 8 | bot-reply authorship; comment body can notify people; CLI args grammar; identifier grammars; ledger lines read back as trusted; reason screening; reset and frame value bounds; committed observation hygiene |
| Kickoff altitude and ship-gate items | 1 | altitude record present and matched by the tasks; the custom-steps doctrine pointer line belongs to that amendment's owner. Ship-gate: none, every out-of-band item carries a task, gated Deferred entry, or Awaiting-input bullet |

Many findings recur across lenses (throttle verb, amendment-gated
citations, "fresh", single-rung wording); after deduplication the
dispositions below cover each once.

**Dispositions.**

- *Applied, grounded (operator approved as one batch).* `skipped` produced
  outside the matrix, the head context fields, the `drains` field, and the
  doctrine outcome-list entry all moved into the custom-steps amendment
  (D-3, both Awaiting-input bullets); REQ-C1.4 reworded to the missing-step
  matrix and moved with REQ-C1.2 to Task 2; ledger lines carry PR and head
  only where the event has them, with field grammars on write and invalid
  lines skipped on read; REQ-B1.2 states all three alternate refusals and
  that a limited alternate holds; the throttle engages through `engage
  --until`, or `observe` when no reset was stated; any `limited` record of
  the run on the flipped head refuses the flip; a record's head is the head
  after the step; clearance needs a post-hold reading for every governed
  window below its lowest-rung descend threshold, and a `claude` hold does
  not itself stop dispatch; accepted reset-time forms and clamping; the
  excerpt and the hold reason screened as a step-record excerpt is; a reply
  counts only from the bot login, as a Bot, after the request; a worker
  death holds with step `worker`; `bot-login` in REST form; the vendor view
  counts over the retention period, knob `quota_ledger_retention_days`
  with its row in Task 3; the ledger rebuilds from the bot's PR comments;
  the hold verb pushes for every caller with a fixed payload; the control
  body addresses only the bot; CLI control arguments follow the plain-word
  grammar as argv; identifier grammars listed; the committed observation
  and the docs examples carry no account detail; the headless rung reads
  `result.json`; REQ-A1.4 names the rungs it covers; the review-request
  command takes a required `--wait`; REQ-E1.4's rendering set enumerated;
  runner entries run as recorded terminal-rung fixture overlays; the drift
  rewordings; the brief corrected in sections 4, 5, 6, and 7.
- *Fork 1, applied (frames for resume only).* Worker frames feed only the
  `claude-frames` clearance evidence; the usage gate's signal is untouched
  (REQ-E1.3, D-14, Task 6); obs:7e67fe74 and obs:d75dd699 returned to the
  live log for fleet-autonomy (risk row 12).
- *Fork 2, applied (flat entries per part).* The vendors catalog keeps the
  shared reader unchanged, one entry per adapter part keyed `<vendor>.<name>`
  (D-9, Task 1).
- *Fork 3, applied (drain names its review).* `drains: <step-id>` lets a
  head-moving drain follow the final-head step it drains (REQ-D1.4, D-12,
  Task 8, REQ-F1.1).
- *Fork 4, applied (one unit first).* Release is staged: the longest-held
  unit probes, the rest follow an answer or stay held on a refusal
  (REQ-B1.5, D-7, Task 4; risk row 11).
- *Fork 5, applied (generic placeholders).* Example adapters use invented
  vendors only (REQ-C1.6, D-9, Task 1).

Declined: none. Deferred: none.

**Altitude check.** The altitude call is D-1 (mechanism-primary, no new
doctrine), cited from the goal and recorded in Sources; every task
delivers scripts, config, fixtures, or reference docs, and the one
doctrine edit now travels in the custom-steps amendment. Matches.

**Ship-gate check.** The custom-steps amendment carries the Awaiting-input
bullets on Tasks 2 and 8; non-Claude forecasting and the probe evidence
kind carry gated Deferred entries; the usage-gate producer and the
re-firing ask stay in the live observations log; the `[manual]` REQ-F1.2
entry is inventoried by `/drain`. No out-of-band fix is named in prose
only.

**Post-lens stale-reference sweep.** Ran over the bundle and brief
sections 2–7 for the re-scoped REQs (REQ-B1.2, REQ-B1.4, REQ-B1.5,
REQ-C1.4, REQ-C1.6, REQ-D1.2, REQ-D1.4, REQ-D1.5, REQ-E1.3, REQ-E1.6):
stale wording in brief sections 4, 5, and 7 reconciled; none left in the
bundle.

### Sign-off record

Approved by the operator on 2026-10-05 after the approval summary: the
bundle flips Draft to Ready on all four files.

Class: meaning
Lens-pass: section 8, "Lens review (full bundle, first activation)"
Anchor: `fc76462d9ac9b87ff4620f1268b29c087de291f2` — computed as
`scripts/spec-anchor.sh specs/quota-handling`

## 9. Amendment log

(none yet)
