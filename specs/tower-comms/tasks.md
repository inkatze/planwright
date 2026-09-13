# Tower comms — Tasks

**Status:** Ready
**Last reviewed:** 2026-09-12
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order, which is presentation; the `Dependencies:` lines
are what carry the bundle's load-bearing claim (D-15), and Task 8's
dependency on Task 2 is the edge that enforces it: the log and scorecard
land first and measure today's tower, and the queue is wired in only after a
baseline exists, so the experiment has an honest before.

## Tasks

### Task 1 — The event log and the scorecard

- **Deliverables:** `scripts/tower-queue.sh` with its `log` and `report`
  verbs: one flat JSON line per event under the fleet home (schema version,
  monotonic sequence, kind, payload; string and number values only, never a
  nested one), written under the fleet lock and parsed by the script's own
  awk with no `jq`, the grammar test pinning that subset; the sequence held
  in a counter file read and bumped inside the same critical section; the
  event kinds including a per-pass `tick` carrying the live-worker count and
  a `session` kind covering a session's start and its rebuild; the writing
  tower's identity on every `reply`, `acknowledged`, `delivered`, `knocked`
  and `tick` line; the secret-shaped redaction helper living in the `log`
  verb and applied to every event kind it writes, which the prompt-submit
  hook and `capture` reuse rather than reimplement; the log and its counter
  created owner-only inside a `0700` sub-surface of the fleet home whose
  mode is verified before each write; rotation by age with a floor that
  keeps the experiment's own sessions readable, run inside that critical
  section; the `tower_log_rotate_age`, `tower_report_window`,
  `tower_tick_gap_max` and `tower_hook_lock_wait` knobs in
  `config/defaults.yml` with their `docs/options-reference.md` rows, every
  interval among them accepting sub-second values; the scorecard computed
  from the log alone, with the headline (items that reached the operator per
  hour of fleet work, wall-clock with at least one live worker, computed per
  tower from its own tick stream and the per-tower intervals unioned,
  against items settled without them) and the secondary measures
  (blocked-worker wait, multi-ask turns, items delivered in prose with no
  queue record, friction moments, jargon counts over delivered text, items
  lost across restart); the jargon count implemented over a word list
  shipped with the script, which the rule doc cites once it lands (Task 7);
  a committed fixture log under `tests/fixtures/tower-comms/` with its
  hand-computed numbers beside it; unit tests for the log grammar, the
  sequence, the rotation, and each measure; a `mise run tower:report` task;
  no CI wiring.
- **Done when:** the log verb refuses a control byte, a malformed field, and
  a nested JSON value, and a grep of the script finds no `jq`; a
  secret-shaped value is redacted in every event kind the verb writes; the
  log, its counter, and their directory are owner-only, and a loosened mode
  refuses the write; a fixture log past the rotation age rotates inside the
  lock and `report` reads only the `tower_report_window` window; the report
  over the committed fixture reproduces its hand-computed numbers for every
  measure, including a two-tower fixture whose overlapping ticks count the
  shared hour once and one whose tick gap exceeds `tower_tick_gap_max` and
  is reported as a gap beside the headline; the tower loop can log a
  delivered turn and an operator reply with no queue present; and
  `check-no-ci-evals.sh`, `check:options`, `check:test-time` and
  `mise run check` all pass.
- **Dependencies:** none
- **Citations:** D-14, D-15 · REQ-A1.4, REQ-D1.1, REQ-D1.4, REQ-G1.1,
  REQ-G1.2, REQ-G1.5, REQ-G1.6, REQ-G1.7, REQ-G1.8, REQ-H1.3, REQ-H1.4
- **Estimated effort:** 1.5 days

### Task 2 — Baseline sessions

- **Deliverables:** the log verb called from today's `/orchestrate` watch
  loop and step report for every delivered turn; a deterministic
  prompt-submit hook in `hooks/hooks.json` that stamps the operator's reply
  time into a per-tower attention marker file it alone owns under the fleet
  home, taking no shared lock so that write is never dropped, and then logs
  the reply as a `reply` event through the `log` verb (inheriting the lock,
  the sequence, and that verb's redaction, waiting for the lock no longer
  than `tower_hook_lock_wait` and then dropping the line and bumping a
  dropped-line counter rather than delaying the turn); that hook gated on a
  live published presence record for the session's own identity, never on
  prose, so it is a no-op everywhere else; the prompt-submit event's row in
  `scripts/check-hook-contracts.sh`'s contract table and its payload fixture
  under `tests/fixtures/hook-payloads/`; a tick written from each loop pass
  with the live-worker count, coalesced with the previous tick when that
  count is unchanged; nothing else in the loop changed; a recorded baseline
  over real fleet sessions (the sessions counted, the scorecard per session,
  the aggregate), appended to the kickoff brief's risk register.
- **Done when:** the baseline entry names its sessions and numbers; the
  watch-loop change adds no queue behaviour (the diff touches only logging
  calls, the tick, and the hook); one loop pass over a fixture fleet emits
  exactly one tick whose live-worker count matches the fleet's, and a second
  pass at the same count coalesces rather than appending; the hook writes
  nothing and calls no model in a session with no live published presence
  record; the hook advances the attention marker even on the run where the
  lock wait expires and the log line is dropped, and the dropped-line
  counter moves; the hook redacts secret-shaped content through the `log`
  verb's helper; `check:hook-contracts` (with the new row and its fixture)
  and `check:instructions` both pass.
- **Dependencies:** 1
- **Citations:** D-6, D-14, D-15 · REQ-C1.10, REQ-G1.1, REQ-G1.3, REQ-G1.6,
  REQ-G1.8, REQ-H1.4
- **Estimated effort:** half day plus the sessions' wall clock

### Task 3 — The queue store and script

- **Deliverables:** `scripts/tower-queue.sh` verbs `add`, `list`, `next`,
  `ack`, `shelve`, `settle`, and `counts` over a queue store under the fleet
  home, written under the fleet lock with atomic rename, every verb bounding
  its lock wait by `tower_hook_lock_wait` and reporting the expiry as an
  error rather than writing unlocked, holding the lock far below the stale
  threshold and re-reading and comparing the store before the rename,
  because the advisory lock carries no holder token; the store created
  owner-only inside a `0700` sub-surface whose mode is verified before each
  write; the five item kinds, with a standing decision registered but never
  delivered and never ranked; urgency on the attention store's `high` /
  `normal` / `low` scale; the single-line record grammar with the
  closing-condition field and the refusal of a record promising an automatic
  step; content written to its home before the index record; content
  pointers as relative paths under a declared root, canonicalised and
  containment-checked, and a pointer at an attention-store row carrying that
  row's instance identifier; echo-safety on every rendered value; retention
  that keeps the open items plus the settled ones inside the catch-up
  window; `next` running the settling pass (REQ-B1.1) before it selects;
  attention read only from the per-tower marker the prompt-submit hook
  writes, with `next` returning a knock line only when a knock is due and
  otherwise nothing, and handing over nothing until that marker shows a
  reply later than its own last delivery to that tower; `ack` closing an
  item without releasing the next, refusing when the caller holds no lease
  (a logged duplicate no-op) and no-opping on an already-closed item; `next`
  leasing every hand-over to the calling tower's presence identity under the
  lock, with a tower-session-scoped fallback identity written into the store
  when none resolves, the lease released on acknowledgement, shelve, settle,
  merge-absorption, death evidence or a not-live owner, renewed on that
  tower's replies, preemptible by an attended tower, and expiring only as a
  backstop; the `tower_quiet_interval` and `tower_lease_interval` knobs in
  `config/defaults.yml` with their `docs/options-reference.md` rows, both
  accepting sub-second values, and `tower_lease_interval` floored at
  `tower_quiet_interval`; `next` logging each delivery, fail-open if that
  append fails; rebuild of the queue from the content homes when the store
  is absent, serialised under the lock with the absence re-checked inside
  it and identifiers derived deterministically from each content home's key;
  unit tests including a hostile-input table, a rebuild-after-loss case, a
  two-tower lease case, and a two-tower attention case.
- **Done when:** every verb round-trips through the store under a
  concurrent-writer test with no torn record, and a lock-saturation test
  reports the bounded wait's expiry as an error instead of writing; `next`
  prints at most one item and orders by kind, urgency, then age, running the
  settling pass first; `next` prints the knock only when one is due and
  hands over no content until the marker shows a later reply; a second
  `next` with no new reply hands over nothing; an `ack` from a tower holding
  no lease is refused and logged, and one on a closed item is a logged
  no-op; two towers whose markers advance independently each see only their
  own attention state; a store that cannot be written surfaces an error in
  the turn rather than a silent skip; `counts` prints the open count per
  kind and the top item's kind; `list` prints every open item and no settled
  one; an urgency outside high/normal/low is refused, a worker-question item
  inherits its row's priority, and the hostile-input table's rows (control
  bytes, embedded newlines, over-long fields, a leading-whitespace prefix, a
  pointer escaping the declared root) are each refused with a message; two
  callers with distinct presence identities never receive the same item, an
  expired lease releases it, a lease renews on its holder's reply, and an
  attended tower preempts an unattended tower's lease; a deleted store
  rebuilds under the lock with deterministic identifiers and no content lost
  beyond the stated budget; `check:options` and `check:test-time` pass;
  `mise run check` passes.
- **Dependencies:** 1
- **Citations:** D-2, D-3, D-4, D-6, D-18 · REQ-A1.1, REQ-A1.2, REQ-A1.3,
  REQ-A1.4, REQ-A1.5, REQ-A1.6, REQ-A1.7, REQ-A1.8, REQ-A1.9, REQ-B1.1,
  REQ-B1.5, REQ-C1.1, REQ-C1.2, REQ-C1.5, REQ-C1.6, REQ-C1.9, REQ-C1.10,
  REQ-C1.11, REQ-F1.1, REQ-G1.1, REQ-H1.3, REQ-H1.4
- **Estimated effort:** 2 days

### Task 4 — Settling and merging

- **Deliverables:** the settling pass behind the `settle` verb in
  `scripts/tower-queue.sh`, level-triggered so each pass re-evaluates every
  open item's closing condition against the evidence available now; one pass
  per tower-loop iteration, serving both the loop and the delivery that
  follows it; the worker attention store's decision queue read as an input,
  and the reconcile sweep's already-derived evidence and its TTL-stamped
  fetch consumed rather than re-polled (PR state, branch commits, ledger
  closure, and answered-by-another-route, which means an acknowledgement on
  the item, a `claim` close on the worker's record, or a matching standing
  decision, and never a worker's output); evidence gathered outside the
  fleet lock, which is taken only for the writes and held for a stated
  bound; items whose closing condition is met settled with a record naming
  the evidence, and an item whose content home has vanished settled with
  that reason; an evidence source that cannot be reached distinguished from
  one reporting nothing and logged as unavailable, with a worsening re-knock
  held while it is down; merging and pairing computed by keying every open,
  unleased, undelivered candidate in one pass, merging on identical
  normalised question text and option set (case-folded,
  whitespace-collapsed, with the origin worker handle and worktree path
  removed by fixed-string replacement) and naming every source, except that
  an item carrying a worker command merges only on byte equality after that
  removal; at most two items of the same kind naming the same subject key
  (worker handle, PR number, or branch) paired into one delivered item
  naming both sources, the result carrying the highest urgency and the
  oldest age of its sources; a refusal to settle on a worker's completion
  report, result frame, or status line; an item settled while the operator
  was away recorded as such; the `catchup` verb rendering
  settled-since-last-reply with reasons plus open counts by kind, bounded to
  the most recent `tower_catchup_limit` items plus a count of the remainder;
  and that knob in `config/defaults.yml` with its
  `docs/options-reference.md` row beside it.
- **Done when:** fixtures for each evidence source settle the right item and
  nothing else; a worker "completed/success" fixture settles nothing; an
  unreachable evidence source is logged as unavailable, settles nothing, and
  holds the worsening re-knock; a fixture whose content home has been
  removed settles with that reason and logs it; two same-question fixtures
  merge into one item with both sources, while two command-bearing fixtures
  differing only in case or spacing do not; a shared-subject pair is handed
  over as one item naming both sources, and neither two items with different
  subjects, nor two of different kinds on one subject, nor a leased or
  already-delivered candidate pairs at all; a merged item carries the
  highest urgency and the oldest age of its sources; `catchup` over a
  fixture lists every settled item with its reason up to
  `tower_catchup_limit` and then a remainder count; the fleet lock's hold
  time over a large fixture stays inside the stated bound; `check:options`
  and `mise run check` pass.
- **Dependencies:** 3
- **Citations:** D-5, D-8 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5,
  REQ-C1.8, REQ-F1.4, REQ-H1.2
- **Estimated effort:** 1.5 days

### Task 5 — Delivery, the knock, and away detection

- **Deliverables:** the `knock` verb rendering the one-line knock (kind and
  urgency of what is waiting), which is the line `next` returns, so the text
  has one home while `next` keeps the attention state and the lease; away
  detection per tower conversation from that tower's last knock and last
  reply against `tower_quiet_interval`; the away push fired on the
  transition into away while a blocking item is open and after that only on
  worsening (more blocked workers, or a blocked item passing
  `tower_reknock_age`), never on a fixed schedule; that push deduped per
  item across towers under the fleet lock and its outcome logged as its own
  event; urgent news knocking in the conversation but never pushing while
  away; the push routed through `fleet-attention.sh notify`, with `none` and
  `statusline` both push-less and the item left queued; the new
  session-relayed `push` channel, on which notify writes a pending-push
  marker under the fleet home (deduped per item under the same lock) for the
  tower session to relay in Task 8; shelve return; the two config knobs
  owned here (`tower_reknock_age`, `tower_shelve_return`) in
  `config/defaults.yml` with their `docs/options-reference.md` rows, both
  accepting sub-second values; the `statusline` channel's render (owned by
  fleet-autonomy REQ-F1.2) extended in place with a `waiting` field (the top
  item's kind plus one total, from a lock-free best-effort read of the
  store, fed by `counts`) under an unmistakable planwright label, rendering
  nothing on any other channel and nothing while no live tower presence
  exists, and degrading to one distinct unreadable marker on an unreadable
  store, a torn or malformed line, or a kind outside the closed set; unit
  tests for the away state machine, the re-knock rule, and the render.
- **Done when:** a fixture timeline produces exactly the knocks the rule
  allows and no fixed-interval repeat; the push fires on the transition into
  away with a blocking item open, and one item open in two towers pushes
  once; an urgent news item knocks and never pushes; every push attempt's
  outcome appears in the log; a `none` channel and a `statusline` channel
  both queue without error and without a push; the `push` channel writes one
  pending-push marker per item and no more; a shelved item returns at the
  knob's interval and at an overridden one; the status line shows the field
  only under the `statusline` channel and only with a live tower presence;
  an absent, corrupt, or unknown-kind store still renders the rest of the
  line and shows the unreadable marker rather than a blank or a zero; the
  read takes no lock and the field is named `waiting`; the render completes
  inside a stated latency ceiling over a full-sized fixture store;
  `check:options`, `check:test-time` and `mise run check` pass.
- **Dependencies:** 3, 4
- **Citations:** D-6, D-7, D-9, D-17, D-19 · REQ-C1.2, REQ-C1.4, REQ-C1.6,
  REQ-C1.7, REQ-C1.9, REQ-F1.1, REQ-F1.2, REQ-F1.3, REQ-F1.6
- **Estimated effort:** 1.5 days

### Task 6 — Inbound capture and standing decisions

- **Deliverables:** the `capture` verb for requests, approvals,
  questions-needing-work, and standing decisions, with its one-line echo
  text and the `log` verb's redaction helper reused for everything it
  writes; the pre-ship fallback itself, one machine-local, untracked,
  owner-only ledger-shaped file under the fleet home, written when the
  action-item ledger's helpers are absent and read the same way when they
  are not; the standing-decision record (the rule in the operator's words,
  its date, and its coverage as a list of literal command prefixes when the
  rule covers worker commands and free text otherwise); an explicit subject
  key (worker handle, PR number, or branch) recorded whenever the operator
  names one; a refusal to record any rule whose coverage reaches a reserved
  control; the settle-by-rule route in the settling pass, confined to
  permission prompts, with the settling record and its log line carrying the
  decision's identifier and the spoken text naming the rule in the
  operator's own words; a non-command rule surfaced beside an open item
  naming the same subject and never settling it, the tower's reply that
  applies it naming the rule; the `PermissionRequest` hook extended to
  capture the prompt's command text from the harness payload into a
  `command` field on the permission record, beside the positive marker
  (attention-store field 9, `permission`) it stamps there; the permission
  match reading only that field and refusing a record without it or the
  marker; a match requiring the command to start with one of a rule's
  prefixes under fixed-string comparison with a token boundary after it, and
  the remainder to consist solely of the allowlisted token set (characters
  in `[A-Za-z0-9._/@:=+-]`, spaces, and quoted-string interiors); a
  mechanical refusal on the reserved-control shapes regardless of coverage;
  command text rendered ASCII-only for the operator, any other byte shown as
  an escape beside a warning; a matched prompt answered through the
  sanctioned answer channel and anything else queued for the operator; the
  answer channel (`fleet-attention.sh claim`) extended to accept an answer
  to a permission-park only when it names a standing decision, resolving
  that decision, confirming its kind, and re-running the match against the
  parked command itself, its existing refusal kept for every other
  permission-park and its test updated to say so; the item settled only
  after that answer is confirmed to have exited zero, a non-zero exit
  leaving it open with the attempt logged; unit tests including a prompt
  just outside a rule, a prefix-boundary case, a suffix carrying a shell
  operator, a record with no `command` field, and a rule whose coverage
  names a reserved control.
- **Done when:** a captured request appears in its content home before its
  queue record and the record points at it; the fallback file is created
  owner-only and untracked; a prompt inside a standing decision is answered
  and the log line carries the rule's identifier; a prompt one token outside
  it reaches the queue; a command whose remainder leaves the allowlist after
  a covered prefix is never answered; a permission record with no `command`
  field or no `permission` marker is refused rather than matched; a coverage
  naming a reserved control is refused at `capture`, and a reserved-control
  command is refused at match time even when a rule claims it; non-ASCII
  command text is shown escaped with a warning; a non-command rule never
  settles an item and is shown beside one; a permission-park answer without
  a named rule is still refused by the answer channel, and one whose named
  decision does not cover the parked command is refused too; a non-zero exit
  from the answer channel leaves the item open with the attempt logged; no
  path answers from anything but a written rule; `mise run check` passes.
- **Dependencies:** 3, 4
- **Citations:** D-5, D-11, D-12 · REQ-A1.3, REQ-B1.2, REQ-B1.5, REQ-E1.1,
  REQ-E1.2, REQ-E1.3, REQ-E1.4, REQ-E1.5, REQ-E1.6, REQ-E1.7, REQ-E1.8,
  REQ-E1.9, REQ-E1.10, REQ-G1.8, REQ-H1.1, REQ-H1.2, REQ-H1.3
- **Estimated effort:** 2 days

### Task 7 — The conversation rule doc and its budget

- **Deliverables:** `doctrine/tower-comms.md`, the short rule doc, holding
  exactly what no script can enforce and nothing else: the speech register
  and the listener-side word test; how the first turn after silence is
  framed (state, not a report of what the tower did); the answerable-alone
  rule and the one-layer-on-request rule with its wait; and answering an
  operator's question inside the turn, capturing only the work it needs
  (REQ-E1.6); plus a pointer to the jargon word list the scorecard reads;
  its row in the doctrine README index; the reachable-budget raise recorded
  as a `raise|` line in `config/instruction-budget-exemptions.txt` naming
  the knob, the value, the reason, and why the rungs below a raise did not
  apply, per the headroom policy's budget-raise rung; no restatement beyond
  a one-line gist in any skill.
- **Done when:** every sentence in the doc has been checked against the
  verbs Tasks 3 through 6 specify and none restates a rule one of them
  enforces, the check recorded in the PR body and re-run at Task 8;
  `check:doctrine-index`, `check:links`, and `check:instructions` pass with
  the raise recorded and no floor-breach warning; the use-site warning for
  the doc is reviewed and either cleared or carried as a
  `declared-exception` line with its reason; the doc's word count is printed
  in the PR body beside the raise.
- **Dependencies:** none
- **Citations:** D-10, D-13, D-16 · REQ-C1.3, REQ-C1.8, REQ-D1.1, REQ-D1.2,
  REQ-D1.3, REQ-E1.6, REQ-E1.7, REQ-I1.1, REQ-I1.2, REQ-I1.3, REQ-I1.4
- **Estimated effort:** 1 day

### Task 8 — Wiring into the tower loop

- **Deliverables:** `/orchestrate`'s watch loop, `--fleet` loop, and step
  report route every operator-bound item through the queue: one settling
  pass each iteration serving both the loop and the delivery, `next` for the
  step report's requests slot (or the step report's equivalent place until
  operator-dialogue Task 11 defines that slot), the knock line before the
  first item of an attention session, `capture` for operator input, the
  state picture composed from the `catchup` verb's list for the first turn
  after silence, and the pending-push marker relayed on the loop's next step
  by calling Claude Code's push-notification tool with one line under 200
  characters in the doc's register; each `next` call carrying the loop's own
  presence identity, resolved with the flags its presence publish uses; a
  delivered item's content fenced as untrusted where the turn renders it;
  the attention render no longer re-rendering items the queue already
  delivered; and the `tower-comms` doc cited at point of use in the manifest
  of each tower skill.
- **Done when:** a scripted tower session over a fixture fleet delivers one
  item per hand-over, knocks once at the start of an attention session and
  not again between items until attention lapses, and captures an operator
  request in the same turn; the first turn after an autonomous stretch
  reads as state rather than a report, and the catch-up list itself appears
  only when asked for; a fixture item whose content carries instructions
  addressed to the tower is rendered as fenced data and acted on by nobody;
  a pending-push marker is relayed exactly once and then cleared; the
  per-step context growth over the fixture session is measured and reported
  in the PR body; Task 7's check of the doc against the specified verbs is
  re-run and still holds; `check:instructions` passes at the raised budget
  with no floor-breach warning; `mise run check` passes.
- **Dependencies:** 2, 5, 6, 7
- **Citations:** D-6, D-13, D-16, D-18, D-19 · REQ-A1.1, REQ-A1.7, REQ-C1.1,
  REQ-C1.2, REQ-C1.4, REQ-C1.8, REQ-C1.10, REQ-C1.11, REQ-E1.1, REQ-F1.5,
  REQ-F1.6, REQ-H1.3, REQ-I1.2, REQ-I1.4
- **Estimated effort:** 1.5 days

### Task 9 — The experiment and the extension gate

- **Deliverables:** real fleet sessions run with the queue wired in, the
  scorecard per session and aggregate, the comparison against the Task 2
  baseline, and the recorded result in the kickoff brief's risk register;
  the standing-decision mismatch rate reported from the log; and the four
  observations only a human can make, recorded in that entry: whether each
  delivered item was answerable from its own message (REQ-C1.3), whether the
  first turn after an autonomous stretch described state rather than the
  tower's actions (REQ-C1.8), which positional labels were spoken
  (REQ-D1.2), and whether questions were answered in the turn with only
  their work captured (REQ-E1.6).
- **Done when:** the risk-register entry names the sessions on both sides,
  every measure, and each of the four observations with what was seen; no
  spec or doctrine file outside this bundle is edited by this task.
- **Dependencies:** 2, 8
- **Citations:** D-15, D-16 · REQ-C1.3, REQ-C1.8, REQ-D1.2, REQ-E1.6,
  REQ-G1.4, REQ-I1.4
- **Estimated effort:** half day plus the sessions' wall clock

### Task 10 — Docs and doctrine reconciliation

- **Deliverables:** a `docs/fleet.md` section on the operator queue (what the
  operator sees, the replies the tower understands, the knobs
  (`tower_quiet_interval`, `tower_lease_interval`, `tower_reknock_age`,
  `tower_shelve_return`, `tower_tick_gap_max`, `tower_log_rotate_age`,
  `tower_report_window`, `tower_hook_lock_wait`, `tower_catchup_limit`), the
  status-line indicator, what a lease expiry looks like from the operator's
  side, that a tower session logs replies to the machine-local event log,
  and the scorecard command); that guide's "what the fleet decides without
  you" section extended with standing decisions and what they may and may
  not cover; its status-line field list extended with `waiting` and its
  durable-state enumeration with the queue store, the event log, the
  attention markers, and the pre-ship fallback; the `notification_channel`
  row in `docs/options-reference.md` updated for the `waiting` field and for
  the new `push` value; the attention capability doc's writer enumeration
  refreshed and the sibling queue named as a reader; the intervention
  contract in the finding-categorization doctrine amended to state its two
  routes (a sign-off request and a hard pause) and the knock as the way a
  hard pause reaches the operator; the four places that restate the
  never-answer rule brought into line with D-12's reading
  (`doctrine/inter-orchestrator-coordination.md`'s section,
  `doctrine/README.md`'s index row, `docs/fleet.md`, and the Never bullet in
  `skills/orchestrate/SKILL.md`); the autonomous-safe-decision doctrine's
  permission-prompt sentence amended to name the standing-decision case; a
  one-line pointer beside orchestration-fleet REQ-B1.7 naming the override
  this bundle records.
- **Done when:** `check:links`, `check:doctrine-index`, and
  `check:instructions` pass with no floor-breach warning; the REQ-D1.3 word
  test is stated in the fleet guide in the operator's terms; a grep for the
  never-answer rule's wording finds no site still stating it without D-12's
  reading; the two attention-capability sites (the writer enumeration and
  the reader list) and the two intervention routes each read back the change
  this bundle made to them.
- **Dependencies:** 8
- **Citations:** D-2, D-9, D-12, D-17, D-18, D-19 · REQ-A1.7, REQ-C1.9,
  REQ-D1.3, REQ-E1.5, REQ-F1.2, REQ-F1.6
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

- **Extend the conversation rules to `/spec-kickoff`, `/spec-draft`,
  `/resume`, and `/drain`.** The rules are universal in content but bound to
  towers in this version; they spread when the experiment shows they helped.
  Confidence: medium.
  **Gate:** Task 9's recorded comparison shows the operator's load per hour
  of fleet work fell against the Task 2 baseline, with no secondary measure
  worse.
  Citations: D-16, REQ-G1.4, REQ-I1.4.
- **Wire the queue into the `/tower` front door.** The skill does not exist
  yet; the wiring is the same as Task 8's.
  Confidence: high.
  **Gate:** tower-front-door Task 4 merged.
  Citations: D-16, REQ-F1.5.
- **Cut over standing decisions, approvals, and captures from the pre-ship
  fallback to the action-item ledger.** The ledger bundle owns the cutover;
  this bundle writes to the machine-local fallback until then.
  Confidence: high.
  **Gate:** action-item-ledger gains a standing-decision kind and its Task 1
  merges.
  Citations: D-11, REQ-A1.3, REQ-E1.2, REQ-E1.3.
- **Consume obs:478f36fc.** The fragment is cited here but lives on an
  unmerged chore branch, so this bundle cannot mark it consumed yet.
  Confidence: high.
  **Gate:** the chore branch carrying obs:478f36fc merges to main.
  Citations: REQ-D1.1, REQ-D1.2, REQ-D1.3.

## Out of scope

- **Worker permission allowlists and guard shapes.** Owned by
  worker-permission-ergonomics. Citations: REQ-E1.5.
- **Worker liveness and completion truth.** Owned by fleet-lifecycle-closure
  and the stream-json fixes. Citations: REQ-B1.2.
- **Notification channel adapters and transport.** Owned by the attention
  capability and fleet-messaging, with one carve-out: the session-relayed
  `push` channel, which adds a marker file and no transport.
  Citations: REQ-F1.2, REQ-F1.6.
- **Durable tracking and closure of owed items.** Owned by
  action-item-ledger. Citations: REQ-E1.2.
- **The reserved human controls and artifact completeness.** Unchanged,
  permanently. Citations: REQ-H1.1.
