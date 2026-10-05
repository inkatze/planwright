# Quota handling — Requirements

**Status:** Ready
**Last reviewed:** 2026-10-05
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

A unit's process depends on services planwright does not run: hosted review
bots triggered by a PR comment, external model CLIs a panel step shells out
to, and Claude itself. Each of them meters use, and when one runs out
planwright cannot tell. A bot that replies that its review limit is
reached reads as an ordinary failed step, so the unit fails and a
retry spends another metered request. An external CLI's monthly quota stalls
flights at their panel step with no reason the operator can see. A worker
killed by Claude's own rate limit exits at once, recorded as a success on
some paths, with the reason only in its event log. Usage and throttle
accounting exists for Claude alone.

This bundle makes a quota, usage, or rate-limit refusal a first-class
condition. A refusal a vendor's adapter recognizes is classified `limited`,
never `failed`; the step is held, by default, with the reason in front of
the operator; and it resumes when the vendor's adapter shows positive
evidence the limit cleared, or on the operator's word. Each vendor is
described by an adapter that declares its own refusal recognizers, its
evidence source, and the controls it offers (full versus incremental
review, effort levels), named in that vendor's own vocabulary with no
common mapping. A post-pr head-moved signal lets a metered bot review only
the final head, and a per-vendor ledger extends usage accounting beyond
Claude. The deliverable is mechanism-primary: every rule is enforced by
deterministic scripts, no new doctrine document is added, and the
vendor-specific values stay in overlays (the altitude call, D-1).
*(Cites: D-1, D-2, the invocation (Sources), obs:5aa3d7ee, obs:05313aff,
obs:c24a01af.)*

## Scope

### In scope

- Classifying a recognized limit refusal as the step outcome `limited`,
  from the output of any step kind and from a supervised worker's death on
  each dispatch rung that has a completion reader (stream-json and
  headless).
- Holding a limited step and its unit, vendor-wide across the host, with
  the reason pushed to the operator; a per-step `on-limit` posture
  (`hold`, `continue`, `alternate <step-id>`).
- Automatic resume on positive adapter evidence only, and an operator
  resume command; resume continuing the held step's point.
- A `vendors` catalog of per-vendor adapters resolved through the overlay
  layers: recognizers, evidence kind, and controls in the vendor's own
  vocabulary, including a choice keyed on recorded PR history.
- One vendor-agnostic command that requests a review by PR comment, awaits
  the bot's reply, and records the head it asked about.
- A post-pr head-moved signal, and a final-head ordering rule for steps.
- A machine-local per-vendor ledger, rendered on demand; Claude's
  clearance evidence read from the rate-limit frames workers already emit;
  automatic engagement of the existing Claude throttle on a Claude limit.
- The amendment to custom-steps that the sixth outcome and the new step
  fields require, taken through that bundle's own extension and kickoff.

### Out of scope

- Retrying into a limit refusal. The only automatic re-attempt is the one
  a resume makes.
- Any spend, upgrade, or paid-overage control for a non-Claude vendor.
  Claude's existing credit-continuation opt-in (fleet-autonomy REQ-E1.11)
  is untouched.
- Re-running convergence or pre-pr points after a post-pr commit moves the
  head; obs:6c3342a8 keeps that ask open for a custom-steps extension.
- Changing the Claude usage gate's ladder, thresholds, caps, or signal
  source (fleet-autonomy owns them); worker frames feed no usage-gate
  producer here, and obs:7e67fe74 and obs:d75dd699 stay open for that
  bundle.
- Merge, and deciding who may flip a task PR ready; this bundle only keeps
  a held run from reaching its flip point.
- Planwright-owned adapters for specific third-party vendors, active or
  as examples; the documented examples use invented placeholder vendors.

## REQ-A — Classifying a refusal

- **REQ-A1.1** A refusal caused by a quota, usage, or rate limit SHALL be
  classified as the step outcome `limited`, never `failed` or `passed`.
  *(Cites: D-3, obs:5aa3d7ee.)*
- **REQ-A1.2** Classification SHALL be deterministic script logic that
  matches the step's captured output against the recognizers its vendor's
  adapter declares, never model judgment.
  *(Cites: D-4, fleet-autonomy D-18 (Sources).)*
- **REQ-A1.3** A refusal that no recognizer matches SHALL keep the outcome
  custom-steps already assigns it; an unknown refusal never becomes a hold.
  *(Cites: D-4.)*
- **REQ-A1.4** A supervised worker that ends with an API error SHALL never
  be recorded as a clean completion by any completion reader: the
  stream-json result frame, its exit fallback, the headless rung's result,
  and the stuck detector. A death whose event stream or headless result
  carries a rate-limit error SHALL be classified `limited` against the
  Claude vendor; any other API error SHALL be recorded as a failure naming
  its cause. Rungs with no completion reader (the tmux worktree rung and
  `/offload`'s tmux, print, and subagent rungs) are outside this rule.
  *(Cites: D-15, obs:05313aff, obs:f0b55c65, obs:d9681390.)*
- **REQ-A1.5** A `limited` record SHALL carry the vendor id, the matching
  recognizer id, an excerpt of the refusal screened as a step-record
  excerpt is, and the reset time the vendor stated when it stated one in an
  accepted form (ISO-8601 UTC or epoch seconds, not past, within the
  throttle's hold ceiling); any other value counts as no stated reset
  time.
  *(Cites: D-4, D-13.)*

## REQ-B — Holding and resuming

- **REQ-B1.1** A `limited` step whose posture is `hold` SHALL hold its
  unit at that step: the vendor hold store records the unit with the
  vendor, the step, the reason, and any stated reset time; selection does
  not dispatch a held unit and the status render shows it held; and an
  attention event is pushed to the operator. A hold writes nothing to
  `tasks.md`, and its release makes no commit.
  *(Cites: D-5, D-6, D-7.)*
- **REQ-B1.2** A step MAY declare an `on-limit` posture: `hold` (the
  default), `continue` (record the step `limited` and run the rest of the
  point), or `alternate <step-id>` (run the named step once in its place,
  its outcome standing for the point). Resolution SHALL refuse an
  alternate bound to the same vendor, an alternate that itself declares
  `alternate`, and an alternate id that does not resolve; an alternate
  that is itself classified `limited` takes `hold`. A `limited` record
  from any point of the run, on the head about to be flipped, SHALL refuse
  the flip whatever its posture.
  *(Cites: D-5, drafting-session decision (2026-10-05).)*
- **REQ-B1.3** A hold SHALL be vendor-wide on the host: while a vendor is
  held, every step bound to that vendor, in any unit, SHALL take its
  `on-limit` posture without sending a request.
  *(Cites: D-6.)*
- **REQ-B1.4** An automatic resume SHALL happen only on positive evidence
  from the vendor's adapter that the limit cleared: for `claude-frames`, a
  reading received after the hold began, for every window the usage gate
  governs, below that window's lowest-rung descend threshold. A stated
  reset time passing is not evidence, and a vendor whose evidence kind is
  `none` waits for the operator. A `claude` hold does not itself stop
  worker dispatch; the throttle (REQ-E1.6) does, until its own reset.
  *(Cites: D-7, obs:c24a01af.)*
- **REQ-B1.5** The operator SHALL be able to resume a held vendor at any
  time through one documented command. Every release, automatic or by the
  operator, SHALL re-dispatch one held unit first (the longest held); the
  others stay held until that unit's first request to the vendor ends
  with an outcome other than `limited`, when they are released, or is
  refused, when the hold renews and they send nothing.
  *(Cites: D-7.)*
- **REQ-B1.6** A resume SHALL re-run the held step and continue the rest
  of its point's list, without re-running a step recorded `passed` or
  `applied`, in the run the hold interrupted, with a recorded head (the
  head after the step) equal to the current head; such a step is recorded
  `skipped`.
  *(Cites: D-8.)*
- **REQ-B1.7** A limit refusal SHALL NOT be retried. Each resume makes one
  attempt, and a renewed refusal renews the hold.
  *(Cites: D-16, the invocation (Sources).)*

## REQ-C — Vendor adapters

- **REQ-C1.1** Each vendor SHALL be described by one adapter declaring its
  identity, the recognizers for its limit refusals, its clearance-evidence
  kind, and the controls it supports, each control mapped to the concrete
  invocation it produces.
  *(Cites: D-9.)*
- **REQ-C1.2** Controls SHALL be named in the vendor's own vocabulary and
  referenced by a step as `<vendor>:<control>`. Core SHALL NOT define a
  cross-vendor control vocabulary or map one vendor's control onto
  another's.
  *(Cites: D-10, the invocation (Sources).)*
- **REQ-C1.3** An adapter MAY declare a control choice keyed on what the
  ledger records for the PR, such as a full review when the vendor has not
  yet answered a review request on this PR and an incremental review after.
  A request refused with a limit, or left without a reply before the
  review-request command's wait expires, does not count as answered.
  *(Cites: D-10, obs:5aa3d7ee.)*
- **REQ-C1.4** A step bound to a vendor or control that no resolved
  adapter declares SHALL be treated as a step that does not resolve,
  handled by custom-steps' missing-step matrix (its `ask`, `park`, and
  `skip` tokens by layer and attendance).
  *(Cites: D-9, custom-steps REQ-C1.4 (Sources).)*
- **REQ-C1.5** Adapters SHALL resolve through the overlay layers as
  untrusted, bounded data: recognizers are matched as fixed strings, a
  CLI control's arguments follow custom-steps' plain-word `args` grammar
  and are passed as argv, a comment-body control addresses no one but the
  vendor's bot, and no adapter field is executed, evaluated, or used as a
  pattern.
  *(Cites: D-9, security-posture (Sources).)*
- **REQ-C1.6** Core SHALL ship the adapter for Claude. Third-party
  adapters SHALL live only in an operator's overlay; the reference
  document SHALL illustrate them with invented placeholder vendors (names,
  bot logins, refusal text, and controls), never a real product's name or
  quoted wording.
  *(Cites: D-9, customization-boundary (Sources).)*

## REQ-D — The head-moved signal

- **REQ-D1.1** When a post-pr step moves the PR head, the runner SHALL
  record the previous and new head SHAs and expose them to every later
  step at that point through the fixed step context.
  *(Cites: D-12, obs:5aa3d7ee.)*
- **REQ-D1.2** The review-request command SHALL record in the ledger the
  head it asked the vendor to review.
  *(Cites: D-11, D-13.)*
- **REQ-D1.3** The review-request command SHALL NOT send a request when
  the ledger records that the vendor answered a request for the current
  head; its outcome is `skipped`, naming the head already reviewed. A
  request refused with a limit, or left without a reply before the
  command's wait expires, does not count as answered, so a later run or a
  resume on the same head asks again. With no ledger line for the PR, the
  command SHALL rebuild the PR's history from the bot's own PR comments
  first.
  *(Cites: D-11.)*
- **REQ-D1.4** A step MAY declare that it runs only on the final head, and
  resolution SHALL refuse a point list that places such a step before a
  step declared as moving the head, unless that later step declares that
  it drains the final-head step by naming its id; a drain naming any other
  step, or a step that is not final-head, SHALL be refused.
  *(Cites: D-12.)*
- **REQ-D1.5** The review-request command SHALL post only when the
  adapter's declared bot login is an account GitHub reports as a bot, and
  SHALL refuse otherwise; the comment addresses only that bot. It SHALL
  count as the reply only a new comment or review authored by that bot
  login and created after the recorded request, so no person's comment is
  read as the bot's answer or refusal.
  *(Cites: D-11.)*

## REQ-E — Usage accounting

- **REQ-E1.1** Planwright SHALL keep a per-vendor ledger under the fleet
  home, never committed, of requests sent, answers, refusals, holds, and
  resumes, each with its time and, where the event has them, its PR and
  head, pruned past a configurable retention whose default is 90 days. A
  line whose fields fail their grammar SHALL be skipped on read.
  *(Cites: D-13.)*
- **REQ-E1.2** The ledger SHALL render on demand per vendor (current hold
  state with its reason, and counts over the retention period) through
  the fleet status surface (`scripts/fleet-stats.sh render`).
  *(Cites: D-13.)*
- **REQ-E1.3** The supervisor SHALL persist each stream-json worker's
  newest rate-limit frame in the fleet home, and the `claude-frames`
  evidence kind SHALL read those frames separately for each window the
  usage gate governs (the session and the weekly): a window reading whose
  reset time has passed is ignored, the reading with the furthest-future
  reset is taken, and the limit counts as cleared only per REQ-B1.4. The
  usage gate's own signal is not changed.
  *(Cites: D-14, obs:c24a01af.)*
- **REQ-E1.4** The Claude signal SHALL be treated as account-wide, a
  ceiling to respect, never reported or acted on as spend the fleet
  caused.
  *(Cites: D-14, obs:c24a01af.)*
- **REQ-E1.5** A dispatch backend that emits no rate-limit frames SHALL be
  reported as unmeasured, never read as having headroom.
  *(Cites: D-14, obs:7e67fe74.)*
- **REQ-E1.6** A Claude `limited` classification SHALL engage
  fleet-autonomy's existing dispatch throttle through its own verbs:
  `engage --until` with the stated reset time, or `observe` over the error
  text when none was stated.
  *(Cites: D-15, fleet-autonomy REQ-E1.7 (Sources).)*

## REQ-F — Acceptance

- **REQ-F1.1** This order SHALL be expressible with shipped mechanisms and
  overlay configuration only: polish, self-review, external-model panel,
  push, bot review on the final head (full until the bot has answered a
  request on the PR, incremental after), one bot-review drain pass
  declared as draining that review, ready
  flip, with merge left to the operator. The external-model panel and the
  drain pass MAY be overlay entries naming operator-installed commands, as
  custom-steps keeps review-tool wrappers out of core; the bot review
  request, its classification, the hold, and the resume SHALL be shipped.
  *(Cites: D-11, D-12, obs:5aa3d7ee, obs:6c3342a8.)*
- **REQ-F1.2** When the bot's quota runs out at its step in that order,
  the run SHALL hold at that step: no `failed` outcome, no retry, the PR
  stays a draft, the flip point is not reached, and the reason reaches the
  operator. A resume, on evidence or the operator's word, SHALL complete
  the order.
  *(Cites: D-5, D-7, obs:5aa3d7ee.)*

## Changelog

- 2026-10-05: Bundle drafted at Status Draft via `/spec-draft`. Spun as a
  new bundle: fold-detection read custom-steps (owner of step outcomes and
  the post-pr point), fleet-autonomy (owner of the Claude throttle and
  usage gate), and model-allocation (consumer of the usage gate, no vendor
  notion); the spin-new triggers fire because the per-vendor adapter is a
  new external interface whose decisions cut across all three (D-2).
- 2026-10-05: Edited in place during the `/spec-kickoff` walkthrough and
  its sign-off lens pass (bundle still Draft); every edit and its reason is
  listed in `kickoff-brief.md` sections 3, 4, 6, 7, and 8. Worker frames now
  feed only Claude clearance evidence, so obs:7e67fe74 and obs:d75dd699
  return to the live log.

## Sources

- **The invocation (2026-10-05)** — the operator's seed: classify a quota
  or limit refusal apart from a failure, hold the step and surface the
  reason instead of failing or retrying, resume when the limit clears or
  on the operator's word, for review bots, external model CLIs, and
  Claude's own rate limit; optional per-vendor controls whose names differ
  per platform and must not be mapped to a common vocabulary; a post-pr
  head-changed signal; usage accounting beyond Claude; and the acceptance
  scenario. No altitude claim about the deliverable's nature was pinned.
- **Drafting-session decisions (2026-10-05)** — the operator's answers
  during elicitation: hold by default with a declarable posture;
  evidence-only automatic resume; the out-of-scope and deferred boundary;
  the altitude, outcome-set, adapter-form, and bot-path calls recorded as
  D-1, D-3, D-9, and D-11.
- **custom-steps** — `specs/custom-steps/`: the step outcome set
  (REQ-D1.1), failure posture (REQ-D1.2), missing-step rule (REQ-C1.4),
  the post-pr point, and step records; amended by this bundle's D-3.
- **fleet-autonomy** — `specs/fleet-autonomy/`: the reactive throttle
  (REQ-E1.7), the proactive usage gate and ladder, credit continuation
  (REQ-E1.11), and the no-LLM daemon-mechanics floor (D-18).
- **model-allocation** — `specs/model-allocation/`: consumes the usage
  gate as a contract; unchanged here.
- **security-posture** — `doctrine/security-posture.md`: untrusted input,
  echo discipline, and artifact data-hygiene.
- **customization-boundary** — `doctrine/customization-boundary.md`: the
  capability-versus-style call behind REQ-C1.6.
- **obs:5aa3d7ee** — metered review bots cannot be expressed as steps
  (consumed).
- **obs:05313aff** — an API 529 that kills a worker is recorded as success
  (consumed).
- **obs:f0b55c65** — the headless rung drops `is_error` (consumed).
- **obs:d9681390** — the stream-json exit fallback records a false clean
  completion (consumed).
- **obs:c24a01af** — the usage signal already flows in worker
  rate-limit frames, with the staleness and account-wide caveats
  (consumed).
- **obs:7e67fe74** — the usage gate has no producer; the subagent backend
  emits no frames (cited, not consumed: the gate producer stays
  fleet-autonomy's).
- **obs:d75dd699** — the tower's usage signal is never fed (cited, not
  consumed, as above).
- **obs:6c3342a8** — no native expensive-check step; carries the shared
  acceptance scenario (cited, not consumed).
