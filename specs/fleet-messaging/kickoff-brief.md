# Fleet Messaging — Kickoff Brief

**Spec:** specs/fleet-messaging
**Spec commit at walkthrough start:** 727b47a
**Walkthrough date(s):** 2026-08-27
**Mode:** first activation (Draft, no prior brief)
**Validator at pre-flight:** `scripts/spec-validate.sh specs/fleet-messaging` — 0 errors, 0 warnings
**Pre-flight determinations:** format-version 2 bundle; worktree
`.claude/worktrees/fleet-messaging-spec` on `planwright/fleet-messaging/spec`,
clean, one draft commit ahead of main. Config: `commit_on_kickoff: true`,
`mark_spec_pr_ready_on_kickoff: true`, `kickoff_ready_ci_wait: 10m` (defaults;
no local overlay). Independent cold read: the operator read the
`/spec-walkthrough` artifact for this bundle before kickoff (optional
complement, not a dependency).

**Resume note (2026-09-02):** the 2026-08-27 session wrote this header and
ended before section 2. Resumed at section 2 after re-verifying the header:
HEAD still `727b47a`, validator re-run 0 errors / 0 warnings.

## 2. Goal & glossary

**Restatement (the agent's own words).** The fleet's signals today ride
mechanisms that predate any native inter-session channel: the file store
doubles as durable record *and* signaling bus, so every signal pays a store
write under a contended lock and every consumer polls; delivery is
capture-pane scraping and attributed tmux buffer-paste. Claude Code now ships
cross-session messaging that is attributed, non-impersonating, and delivered
mid-turn without polling. This bundle adopts it in exactly two capacities:

1. **Signal transport** — messaging-first for tower→worker steer and
   decision answers on every rung that advertises and accepts it;
   hook-posted doorbells and one-shot idle notices for worker→tower;
   advisory-only tower↔tower. Every path names its pre-messaging fallback
   and reaches it on absence, refusal, or failure.
2. **Store-load diet** — signal-purpose reads and poll cadences demote to a
   documented low-cadence reconcile floor wherever push is live. No store
   write is removed; no record moves (REQ-E1.3).

**What it rules out** (per `## Scope` → Out of scope): state of record on
messages; fixing the store's lost-append/lock-race defects; the
operator-facing merge-ready push (`merge-currency-guard` owns it); reopening
`concurrent-orchestrator-coordination`'s signed design; LLM-in-daemon
mechanics; observe-in-flight; cross-machine as anything but a double-gated
opt-in; agent teams/workflows.

**What it assumes:** availability is deterministically probeable and
fail-safe-absent (REQ-A1.1, REQ-A1.2); **no signal is ever
correctness-critical** — the retained level-triggered reconcile heals every
loss (REQ-D1.4, REQ-E1.2); the platform contract is version-pinned and
fixture-guarded because harness contract drift has silently broken core
mechanisms before (REQ-A1.4, D-11, obs:16facd5b).

**Altitude:** the seed's pinned claim ("use this instead of serialized JSON
persistent") was reconciled at drafting into D-1 (transport + diet, not state
replacement). Confirmed settled at kickoff; not reopened.

**Implicit terms surfaced, with resolutions:**

- **tower / worker** — the dispatching `/orchestrate` session vs. a
  dispatched execution session (prior-bundle vocabulary; see the
  fleet-coordination-floor doctrine).
- **rung** — a backend level in the backend capability contract.
- **session-grade rung** — a rung the contract's `Session-grade` column marks
  `yes` (see `doctrine/backend-capability-contract.md`, *The backends, by
  advertised set*). Verified at kickoff against that table (2026-09-02);
  the set coincides with the rungs D-6 names as able to bind an inbox
  socket. Tasks 3 and 4's per-rung checks read against that column, not a
  copied list.
- **doorbell** — one grammar-validated, length-bounded pointer line posted
  to an inbox socket by a deterministic hook script; the store row it points
  at is the authoritative content (D-2, D-7).
- **the store** — the existing attention/decision file store (prior bundles
  `fleet-autonomy`, `fleet-hardening`); unchanged as record.
- **reconcile floor** — the retained low-cadence level-triggered poll; its
  exact cadence is deliberately left to Task 7 to document.
- **discipline ladder** (`doorbell` < `tiered` < `open`) — the bundle names,
  orders, and defaults the ladder but does not define rung semantics; the
  definition ships in Task 1's doctrine doc and Task 8's prose. **Operator
  decision (2026-09-02): record the intended semantics here as the intent
  Task 1 authors from** (no spec edit):
  - `doorbell` — deterministic doorbell posts only; no model-composed sends
    in either direction.
  - `tiered` (default) — doorbell, plus model-composed sends for the named
    signal classes only (steer, decision answers, completion/advisory).
  - `open` — the model may compose messages freely.
  - Direction asymmetry (REQ-F1.3) and send-time pressure demotion
    (REQ-F1.4) apply at every rung.

### Revision delta (2026-09-02, resumed session)

The 2026-09-02 revision (`727b47a..89d8f54`, clusters A–F of §8's
worklist) changed the ground under this section; the original text above
stands as the pre-revision reading and this note is the delta read with the
operator. Where the two disagree, this note governs.

- **Restatement.** "Store-load diet" → "store-load reduction". The retained
  level-triggered poll is the **healing sweep**, with one overlay-resolved
  cadence knob (`messaging_heal_cadence_seconds`, shipped default per
  D-16) applied to every demoted consumer. The ladder terminal is
  **operator handoff** (today's undelivered-answer surfacing), not "park".
  Delivery outcomes split by observability: the send path consumes what the
  post returns synchronously (accepted, held, refused, or a failed post;
  REQ-C1.5); dropped and expired are unobservable to a script and are healed
  by the sweep.
- **Rules out (two entries added).** The general worker-settings-profile
  delivery mechanism and the dead `--settings` hook fix belong to the
  `worker-permission-ergonomics` amendment; this bundle wires only the
  messaging settings through the verified interim pattern (D-18). The
  merge-ready push entry is softened from "`merge-currency-guard` owns it"
  to the fleet-coordination-floor doctrine's assignment plus that bundle's
  pending note.
- **Assumes (reshaped).** Availability is a per-session fact (the sending
  session's own inbox-socket env plus CLI version against one pin of
  record; REQ-A1.1) and eligibility a per-rung fact derived from the
  contract's existing session-grade column with no new column (REQ-A1.6,
  D-17). One pin of record replaces per-task pins (REQ-A1.4).
- **Glossary.** "Rung" is reserved for backends and the usage gate; ladder
  levels are **values**. "Session-grade rung" is now the spec-level
  eligibility derivation (D-17), superseding the kickoff cross-check
  recorded above. "Doorbell" carries a fixed wire grammar (D-15). The
  "reconcile floor" entry above is superseded: the sweep's cadence is the
  knob named here, not "left to Task 7 to document". The discipline-ladder
  per-value semantics recorded above as operator intent are still not in
  the spec and remain Task 1's authoring input (operator decision, resumed
  session: no spec edit).
- **Addendum (2026-09-04, section 3 walk).** The "doorbell" entry above is
  retired: after the platform experiments (§8) the operator chose the
  harness's idle notice plus the healing sweep as the whole upward path
  (REQ-D1.6, D-20). A worker never posts to the tower; "the worker stopped"
  reaches the tower as a one-shot notice carrying its closing line, and the
  tower's only action on it is the store re-read verb. The discipline
  ladder's floor value is renamed `script` (script-posted downward sends
  and idle notices ride at every value; no model-composed sends).

Signed off: 2026-09-02 (original walk and revision delta)

## 3. Requirements walkthrough

Per-group outcomes (eight groups, REQ-A–H in `requirements.md`):

- **REQ-A (availability & advertisement) — clean.** Probe-gated, fail-safe
  absent, contract-property advertisement, drift-guarded platform contract.
  Consistent with D-6/D-11 and the sourced platform-contract facts.
- **REQ-B (addressable identity) — clean.** Launch `--name` from the handle
  grammar, observed-name read-back into the registry, names validated as
  data. Consistent with D-8 and obs:d4d66281.
- **REQ-C (downward delivery) — clean.** Messaging-first ladder
  (messaging → attributed paste → park), claim-persist-deliver-verify
  ordering, never re-claim, delivery outcomes consumed, no impersonation.
  Consistent with D-3/D-9 and obs:efe0b752, obs:b7618838.
- **REQ-D (upward signals) — clean.** Hook-posted doorbells with pointer
  payloads, store re-read as the acting surface, idle notices as completion
  supplement only, reconcile heals loss, tower address propagated and
  validated. Consistent with D-2/D-7/D-10.
- **REQ-E (store-load diet) — clean.** Demote-where-push-is-live, reconcile
  never removed, record semantics untouched. Consistent with D-1/D-2 and
  obs:8b694bdb.
- **REQ-F (settings & discipline) — one ambiguity, resolved.** REQ-F1.3's
  direction asymmetry left the knob-to-direction mapping and ladder-end
  behavior undefined (the REQ-F1.3 test asserts the offset at each setting,
  so tests were unwritable without it). **Operator decision (2026-09-02):
  the knob value names the worker→tower rung; tower→worker resolves one
  rung stricter, floored below `doorbell` at "no model-composed sends"; the
  ladder gates model-composed traffic only, so deterministic script sends
  (doorbell posts upward; script-delivered decision answers and operator
  steers downward) ride at every rung.** This keeps REQ-C1.1's
  messaging-first delivery live at the default and honors D-4's
  protect-the-workers rationale. Recorded as brief intent for Tasks 1, 2,
  and 8; no spec edit.
- **REQ-G (degradation & floors) — one wording tension, resolved as a
  reading.** REQ-G1.1 ("reach the fallback without operator intervention")
  vs. the tower↔tower advisory path, whose pre-messaging mechanism is
  operator hand-relay. **Operator decision (2026-09-02): recorded reading —
  REQ-G1.1 governs paths replacing deterministic mechanisms; the advisory
  path degrades to not-sent (the status quo), which is safe because
  REQ-G1.4 keeps advisories off the correctness path.** No spec edit; not
  an inconsistency.
- **REQ-H (security & hygiene) — clean.** Inbound content untrusted
  (same-user-writable socket), grammar-screened, echo-sanitized,
  store-re-read-gated; committed-artifact hygiene on message text.
  Consistent with D-5/D-7 and the security-posture doctrine.

**Consolidated spec-edit list:** none. Both resolutions above are recorded
brief intent, not spec edits.

### Revision delta (2026-09-04/07, resumed session; walked one behavior at a time)

The revision and this session's decisions changed what the requirements
say. Walked with the operator as five behaviors, each confirmed:

1. **Sending downward.** The decision script claims the fork, saves the
   answer, then posts it straight to the worker's inbox socket; on refusal
   or a failed write it steps to today's attributed paste, then to today's
   undelivered-answer surface; one attempt per step, never a retry, never a
   second claim. A held message is reported unconfirmed and left queued.
   Applies to any worker that can take a steer and was launched normally
   (not bare). The "accepted / held / refused reply on the socket" is an
   assumption Task 2 tests first; write success is all the script may get.
2. **Signalling upward.** Presented as three shapes, then decided on the
   platform experiments (§8): **the harness's idle notice plus the healing
   sweep; no worker-side post.** A worker never learns a tower socket path;
   "the worker stopped" reaches the tower as a one-shot notice carrying the
   worker's closing line, enqueued within seconds and seen by the tower's
   model at its next turn boundary; the tower's only action is the store
   re-read verb; mid-turn rows wait for the sweep. The doorbell grammar and
   verbs are retired (REQ-D1.6, REQ-D1.7, D-20, D-21).
3. **Failure.** Asked "could we do better?", the operator chose to make a
   lost downward answer observable: the post carries the tower's own
   socket as its reply address, so the harness's drop or expiry status
   frame reaches the tower, whose one action is a single `redeliver`
   through the fallback; if Task 2 finds no such frame, the parked worker
   is surfaced as answered-undelivered for the operator. Upward losses
   and delays are the sweep's. When messaging is absent, every consumer
   takes today's code path byte for byte. No signal is correctness-
   critical.
4. **Configurable.** Three knobs: the discipline ladder `script` <
   `tiered` < `open` (worker→tower at the knob, tower→worker one stricter,
   tower↔tower at the knob, pressure one further, floor `script`, stderr
   notice per pressure-demoted send, nothing stored); the cross-machine
   cue `messaging_cross_machine` (enforcement is `isolatePeerMachines:
   true` in both profiles); the healing cadence, default 300, one value for
   both looping consumers, an explicit `--interval` winning.
5. **Guarded.** One audited script for every socket post and every check;
   nothing inbound trusted, action only through store-backed verbs; test
   seams refused without `PLANWRIGHT_TEST_SEAM=1`; the documented minimum
   version for the probe and a raise-only last-verified pin with the frozen
   contract assumptions; the dispatch launch-argument pin and the tower
   command-guard re-scoped for the profile path and `--name`, never
   bypassed.

**Per-group ledger (artifact-side; the turn carried the behaviors above).**
Superseded: REQ-A1.2 → A1.6, A1.3 → A1.5, C1.3 → C1.5, H1.1 → H1.4, F1.5 →
F1.6, D1.1 and D1.5 → D1.6, D1.2 and D1.3 → D1.7. New: REQ-G1.6, G1.7,
H1.3, H1.5. Amended in place with dated annotations: A1.1, A1.4, A1.5,
A1.6, B1.1, B1.2, C1.1, C1.4, C1.5, D1.4, E1.1, F1.1, F1.3, F1.4, G1.1,
G1.3, G1.4, G1.5, G1.6, G1.7, H1.3, H1.4. The two items recorded above as
brief intent with no spec edit (REQ-F1.3's knob-to-direction rule,
REQ-G1.1's operator-handoff reading) are now spec text.

**Consolidated spec-edit list (revised):** the five revision commits
(clusters A–F), this session's worklist-2 edits and their mid-walk
corrections, the shape-B redesign and its mid-walk corrections, and the
reply-address observability edit — all recorded in §8 and in the
requirements changelog entries dated 2026-09-02 through 2026-09-07.

Signed off: 2026-09-07 (original walk and revision delta)

## 4. Design walkthrough

Ledger over the decision log in `design.md` (all D-IDs, first activation):
**every decision confirmed; none amended; none superseded.** One carries a
kickoff refinement:

- **D-4 (discipline ladder) — confirmed, with refinement.** The knob-value
  anchoring, ladder-end behavior, and model-composed-only gating are recorded
  as brief intent in sections 2 and 3 (operator decisions, 2026-09-02). The
  decision's text is not contradicted; the refinement fills what it left
  unstated and feeds Tasks 1, 2, and 8.
- All other decisions (D-1–D-3, D-5–D-14) — confirmed, rationale intact,
  no conflict with any walked requirement. Notable reconciliations checked:
  D-6's rung-by-rung advertisement against REQ-A1.2's fail-safe rule; D-9's
  ordering against REQ-C1.2/C1.3; D-14's advisory rule against the REQ-G1.1
  reading recorded in section 3.

### Revision delta (2026-09-07, resumed session; walked as the reasons behind section 3's behaviors)

The design was walked as *why*, one reason per behavior, and then
sanity-checked by two reviewers and one more experiment (§8). What the
operator confirmed:

- **A transport, not a state store** (D-1): messages are lossy, cost a turn,
  and depend on version and provider; files and git stay the record.
- **Messaging first on every rung that can take a steer** (D-3): two live
  primary paths would keep the guard friction alive. Decision answers on
  the stream-json rung go through the supervisor's own control-response
  verb; the decision channel refuses that rung.
- **The idle notice, not a worker-side doorbell, as the upward push**
  (D-20, D-21): decided on evidence; the doorbell's outcome handling was
  fiction, its socket propagation a spoofable surface, its tower turn per
  signal bought only mid-turn rows the sweep already carries. Only a
  turn-ending stop fires a notice; mid-turn suspensions are the sweep's.
- **An event-driven tower** (D-22): the watch loop ends its turn per step
  and is woken by a notice, a peer message, or the harness's scheduled
  wakeup — where the probe reads available and the session survives a
  turn end; the metronome stays where the wakeup is unavailable, for a
  `-p` tower, and for a step with no wake source. The fleet watchdog
  cannot stand in (its tick exits on an interactive marker).
- **The reply address makes a lost answer observable** (D-9): the harness's
  own status frames; one deliberate re-delivery through the fallback;
  bookkeeping in a metadata sibling, never in the pasted artifact.
- **One audited script** (D-12), **eligibility from the contract's existing
  column** (D-17), **the profiles delivered with `--settings`** (D-19, no
  guard re-scoped), **two version pins** (D-11), **cross-machine as a cue
  with the harness setting as the gate** (D-5), **self-registration from a
  session's own record** (D-8: no seam read-back, no retry window).

**Reconciled ledger (artifact-side).** Kept with terminology-only
annotations: D-1, D-14. Amended in place with dated annotations: D-3, D-4,
D-5, D-8, D-9, D-11, D-12, D-13, D-16, D-17, D-19, D-20, D-21. Superseded:
D-2 → D-16, D-6 → D-17, D-7 → D-20, D-10 → D-21, D-15 (retired, no
replacement grammar), D-18 → D-19. Minted this kickoff: D-15 (R), D-16 (R),
D-17 (R), D-18 (R, since superseded), D-19 (R2), D-20 (R3), D-21 (R3),
D-22 (R4). No decision contradicts a walked requirement; every
contradiction the lens passes found was resolved by spec text, none by
override. Cross-bundle: D-22 amends `bootstrap` D-38 through a pending
note Task 6 ships; D-13 amends the inter-orchestrator-coordination doctrine
and adds one class to the fleet-coordination-floor doctrine's lifecycle
contract.

Signed off: 2026-09-07 (original walk and revision delta)

## 5. Verification approach

Coverage mix as stated in `test-spec.md`'s intro (reviewed, accurate against
the entries). Ownership:

- **`[test]`** — the repo's CI shell suite runs every automated entry.
- **`[manual]`** — the operator sweeps live two-session checks at each
  task's Done-when; the optional behavioral eval stays local-only, never CI
  (the evals-never-in-CI guard).
- **`[design-level]`** — verified at doctrine/contract review time.

**Dead-path check: none found** — every REQ's named verification can run.
Weakest path: REQ-F1.5 `[manual]` needs a second machine or a cloud session
for the cross-machine double-gate check; routed to the risk register as an
early-signal row rather than a dead path.

### Revision delta (2026-09-07, resumed session; verification)

The original note above stands as the pre-revision reading; the mix and
the ownership were re-derived on the revised test-spec (35 entries, one
per live requirement; the tag tally is cited from the test-spec's headings
rather than copied here).

- **Three kinds of check, three owners.** The CI shell suite runs every
  `[test]` arm through the recording post seam and the four guarded
  test-only switches, never a live socket. Live `[manual]` arms run in the
  executing task's PR, each with a named environment (a tower and one
  worker on one machine; two towers; once a second machine or a cloud
  session), an observable, and a pass criterion. `[design-level]` review
  covers the doctrine, the contract doc, and the profiles in the task PR.
- **Undocumented platform behavior is verified first, then frozen.** Task
  2 opens with a live wire-contract step recording what a raw post must
  write, whether anything comes back, whether status frames reach a reply
  address, whether `CLAUDE_PID` reaches a hook, whether a second
  subscription stacks, whether a held message is released when the
  receiver relaxes to `accept`, and (in the session-driven half) in which
  session types the scheduled wakeup exists — each with an observable and
  a stated fallback, the unknowns written so either outcome passes.
- **Dead paths: none.** The first lens pass found 26; each was given a
  seam, re-tagged honestly, or removed. Two paths stay deliberately thin
  and say so: CI's CLI is below the messaging floor (only the live
  re-verification sees the platform move), and the discipline ladder is
  prose-enforced (the oracle's arithmetic plus the prose's presence; no
  behavioral arm claimed).
- **Weakest path:** the scheduled-wakeup timer, the one wake path no
  experiment covered; a session type without it keeps today's metronome,
  so the event-driven loop is never worse than today.
- **Three long-term forms adopted at this walk:** the fleet smoke runner
  (REQ-A1.7, D-23) as the standing platform-drift check and Task 7's
  capstone; the `off` switch value as the per-fleet kill switch (REQ-F1.2);
  a Deferred gate on Task 6's loop change until bootstrap's D-38 amendment
  is signed (REQ-D1.8, D-22).
- **Terminal lens (2026-09-07, §8):** the gate is free text (bootstrap
  passes through Ready only transiently), and its gated set also holds
  the runner's notice-wake step and duty-cycle figure, REQ-D1.7's
  notice-consumption criterion, and REQ-E1.1's loop-reads half; before
  the gate the runner's circuit passes when the metronome tower acts on
  the park. The runner's five observables are named and its window
  pinned; every frozen comparand reads its base SHA from a fixture file.

Signed off: 2026-09-07 (original walk and revision delta)

## 6. Task graph

Reconstructed from the `Dependencies:` lines (authoritative; render on
demand via `scripts/spec-graph.sh specs/fleet-messaging`, which confirmed
this reconstruction at kickoff).

- **Critical path (effort-weighted):** 1 → 2 → 4 → 6 → 7, 7 of 11
  effort-days.
- **Waves:** T1 alone (sole root) → T2 ∥ T3 → T4 ∥ T8 → T5 ∥ T6 → T7. No
  wave is wider than two tasks, so **two parallel workers achieve the
  minimum wall-clock**; a third is never useful.
- **Unit shape (operator decision, 2026-09-02):** T5 and T6 dispatch as
  **parallel single-task units**, not a cohesion bundle — they modify
  disjoint consumers (relay/decision delivery vs. hooks/watch consumers),
  so merge adjacency is low.
- **Deliberate non-edges (operator-confirmed, 2026-09-02; do not "fix"):**
  - **8 ↛ 4** — advisory tower↔tower addresses peers via listing
    round-trips; deterministic identity is a worker-dispatch concern.
  - **7 ↛ 3** — the diet's demoted consumers are tower-side pollers;
    worker inbound settings are irrelevant to them.
  - **5 ↮ 6** — downward delivery and upward signaling share dependencies
    but touch disjoint consumers; no ordering between them.

### Revision delta (2026-09-07, resumed session; task graph)

Re-derived from the revised `Dependencies:` lines (`scripts/spec-graph.sh
specs/fleet-messaging` confirmed the reconstruction; figures are cited from
that render and from the tasks' `Estimated effort` lines, not copied).

- **Waves:** T1 alone → T2 ∥ T3 → T4 → T5 ∥ T6 ∥ T8 → T7. Task 4 now
  precedes the three-wide wave (it writes the marker names Task 8
  addresses by and the seams every delivery needs); Task 7 closes, its
  smoke-runner capstone needing both delivery (T5) and the loop (T6).
- **Critical path:** 1 → 2 → 4 → 5 → 7, eleven of fifteen effort-days per
  the render (Task 1 grew to 2 days at the terminal lens for the
  `/orchestrate` diet); two parallel workers reach that bound, a third
  never helps.
- **Unit shape (operator, 2026-09-07):** T5, T6, T8 dispatch as parallel
  single-task units, not a bundle.
- **Deliberate non-edges (re-confirmed):** 7 ↛ 3 (tower-side consumers,
  not worker settings); 5 ↮ 6 (disjoint consumers); 8 ↮ 5, 8 ↮ 6 (the
  advisory path needs marker names, not delivery or the loop).
- **Non-edge retired:** 8 ↛ 4 — Task 8 now depends on Task 4 (marker-name
  addressing, D-8/D-14).
- **Gated deliverables:** Task 6's `--watch` loop change and the arms
  that rest on it (Task 7's notice-wake step and duty-cycle figure) wait
  on the Deferred gate (bootstrap's D-38 amendment signed); the rest of
  Tasks 6 and 7 is ungated, so the wave plan holds if the gate is slow.
  Task 4 also ships the thin tower launch script (terminal lens, §8); no
  edge changes.

Signed off: 2026-09-07 (original walk and revision delta)

## 7. Risk register

**Decision-domains gap check (2026-09-02):** the merged catalog
(`scripts/resolve-catalog.sh decision-domains`; core seed, no overlay
additions on this machine) was walked domain by domain against the bundle.
Every domain the spec touches carries a recorded decision (auth → the
untrusted-socket rule REQ-H1.1/D-7; concurrency → claim-under-lock D-9;
secrets-config → the two documented knobs, Task 1; deploy-migration →
fail-safe absence REQ-A1.3; dependency-adoption → pin-probe-fixture D-11;
queues-async → lossy-transport semantics D-2; existing-seam-reuse →
D-6/D-12; llm-output-quality → advisory-never-load-bearing REQ-G1.4;
observability → debug-log visibility D-7, demotion logging REQ-F1.4).
**No touched domain is undecided; no gap rows.**

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | Platform contract drift: a harness update changes messaging env vars, socket framing, or tool semantics and silently no-ops a fleet mechanism (the WorktreeCreate shape). | Pin the verified CLI version per task; deterministic probe; fixture drift guard (D-11, Task 2). Early signal: the drift-guard test fails visibly. |
| 2 | No positive delivery ACK exists — only negative notices (held/refused/dropped/expired). A held message with no notice yet can look delivered. | Consume every notice, descend the fallback ladder (REQ-C1.3); the reconcile floor heals any missed loss (REQ-D1.4); the fork record never depends on delivery (D-9). Early signal: the live held-message check (REQ-C1.3 [manual]). |
| 3 | Same-OS-user socket spoofing: any local process can post to an inbox socket. Accepted residual — spoofed content is a latency nuisance, never a correctness attack. | Grammar-screen, length-bound, echo-sanitize; act only on the store re-read (REQ-H1.1, D-7). Early signal: hostile-input fixtures in Task 2's suite. |
| 4 | Interrupt noise and token cost scale with fleet size at permissive settings. | The discipline ladder with direction asymmetry and send-time pressure demotion (D-4, REQ-F1.4). Early signal: demotion log entries firing frequently. |
| 5 | REQ-F1.5's cross-machine live check needs a second machine or a cloud session — the bundle's weakest verification path. | A cloud session satisfies it; the check is manual and one-time per wiring change. Early signal: Task 3's Done-when blocked on environment availability. |
| 6 | Settings-delivery failure recurrence: dispatched workers silently missing their settings profile (the ~8-hour unanswered-prompt incident, obs:eea622de). | Delivery folded into the dispatch seam with required visible failure (REQ-F1.1, Task 3 Done-when). Early signal: the dispatch-seam failure test. |

**Open questions: none.** Every question raised during the walk was resolved
into a recorded decision (sections 2, 3, 6) or an accepted-risk row above.

### Revision delta (2026-09-07, resumed session; risk register)

**Decision-domains gap check, re-run against the final bundle** (the merged
catalog via `scripts/resolve-catalog.sh decision-domains`; core seed, no
overlay additions): every touched domain carries a recorded decision —
data storage (registry columns and the answer metadata sibling, D-8/D-9);
queues-async (lossy transport, the sweep, D-16/D-20); API surface (the verb
signatures, D-12; the unverified wire contract verified first, Task 2);
auth (the untrusted socket, self-registration from a session's own record,
the acceptance conjunct, D-7-lineage/D-17); secrets-config (four knob
values including `off`, the guarded test seams, REQ-H1.5); concurrency
(claim under the fleet lock, D-9; the amend verb under the same lock, D-8
— the one clause this re-run added); observability (stderr notices, the
metadata trace, the smoke runner's printed figures, D-23); deploy-migration
(registry and marker arities with tolerant readers, D-8); dependency
adoption and versioning (two pins, D-11); LLM output quality (the
prose-enforced sanction and ladder, verified by greps and manual arms,
accepted); human comprehension UX (operator-facing cadences kept,
REQ-E1.1); existing-seam reuse (one script, the contract's column, the
existing SessionStart hook). **No gap rows.**

The register below supersedes the six rows above, which cite retired
records (REQ-C1.3, H1.1, A1.3, F1.5; D-2, D-7); those rows stay as the
pre-revision reading.

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | Platform contract drift under a harness upgrade. | Two pins (the documented minimum for the probe, the raise-only last-verified pin for the drift guard) and the fleet smoke runner as the standing check (D-11, D-23). Signal: the drift guard or a smoke run fails. |
| 2 | The raw socket post returns no outcome and no status frame reaches the reply address. | Task 2's first step verifies both; write-success and surface-only recovery are already specified (REQ-C1.5, D-9, D-12). Signal: Task 2's PR records "none". |
| 3 | The harness's scheduled wakeup is unavailable in a session type. | That tower keeps today's metronome (REQ-D1.8, D-22); only the push benefit is lost there. Signal: Task 2's recorded outcome per session type. |
| 4 | Same-user socket spoofing (an accepted residual). | Screened, length-bounded, sanitized; action only through the store re-read verbs (REQ-H1.4, D-21). Signal: the hostile fixtures. |
| 5 | Tower turns per notice and per advisory scale with fleet size. | The discipline ladder, pressure demotion, and the `off` switch (D-4). Signal: frequent demotion notices; the usage gate at `reduce-concurrency` or above. |
| 6 | The cross-machine approval check needs a second machine or a cloud session. | `[manual]`, once per wiring change (REQ-F1.6). Signal: Task 3's arm blocked on environment. |
| 7 | Profile delivery on the interactive `tmux` rung is unverified, and the profile's guard hook stays dead until `worker-permission-ergonomics` lands (obs:a4a4fa59). | The messaging keys apply regardless; the profile header says so (D-19). Signal: Task 4's live acceptance check. |
| 8 | Registry (7 → 9 columns) and marker (7 → 8 fields) schema changes break a reader. | Every reader made tolerant and fixture-gated (D-8, Task 4). Signal: the mixed-arity fixtures; a `fleet-status` render showing n/a rows. |
| 9 | Bootstrap's D-38 amendment is slow to sign, delaying Task 6's loop change. | The Deferred gate (REQ-D1.8); the rest of Task 6 ships ungated. Signal: the drain pass reporting the gate unmet. |
| 10 | The `/orchestrate` instruction budget sits at its floors (closure margin 1009 against a floor of 1000, skill file 253 against 250, measured at the terminal lens), and Tasks 1, 5, 6, and 8 all add prose. | Task 1 ships an `/orchestrate` diet first and records a per-task word allotment; every task that adds prose gates `check:instructions` with no pending-diet allowance. Signal: a floor-breach `WARN:` pair appearing. |
| 11 | `--name` collision behavior on `-p` launches is undocumented. | Task 4 records the observed outcome into D-8; a CLI refusal surfaces as a dispatch failure, a duplicate is recorded from the listing (D-8). Signal: the live collision check. |
| 12 | Attention rows on `tmux` and `stream-json-persistent` depend on the identity environment Task 4 newly exports (obs:fbb701bc). | Per-seam fixtures (REQ-B1.1). Signal: rows rendering as n/a after Task 4 lands. |
| 13 | A second `notify_when_idle` per delivery might fan out notices. | Task 2 records the behavior before Task 6 relies on it (D-11). Signal: more than one notice per worker stop. |

**Open questions: none.** Every question raised this session became a
recorded decision (sections 2–6, §8) or a row above.

Signed off: 2026-09-07 (original walk and revision delta)

## 8. Sign-off

**HALTED 2026-09-02 — no sign-off record, no anchor, no Draft→Ready flip.**
The sign-off lens review (below) surfaced ~180 raw findings merging to ~35
root causes. Operator decision (2026-09-02): **halt for revision** — the
findings stand undispositioned as the revision worklist; a revision pass
works the clusters, then a re-kickoff walks the revision as its delta and
signs off. The freshness gate treats this record as absent-anchor (fail
closed), which is correct: nothing may dispatch against this bundle.
The revision will invalidate parts of sections 2–7 above; the re-walk
treats the whole revision as its delta rather than re-confirming those
sections wholesale.

### Lens review pass (2026-09-02) — full bundle, first activation

Method: Discovery-Rigor fan-out per `kickoff-verification` — spec-class
lens set (`artifact-lenses`), seven parallel read-only agents (one per
substantive lens), two rows inline (decision-domain gaps via §7's catalog
walk; rendered-content safety via validator parse + lint). Tooling:
`spec-validate` 0 errors / 0 warnings; `mise run lint:md` 0 errors.
**Altitude check (REQ-H1.3): pass** — the seed's pinned altitude claim is
recorded as D-1, cited from the goal, and the task decomposition matches
(doctrine + transport tasks + one diet task; no state-replacement work).

Validation scoping (declared per `validation-rigor` proportionality): full
validation on the contradiction cluster and cross-file findings (each
verified against the cited artifact at the cited lines by the reviewing
agent), convergence-based validation where two or more lenses surfaced the
same root cause independently, spot-check on singletons; adversarial sweep
run on the blocking set. Self-critique outcome: one under-represented area
— no lens re-verified the Sources' platform facts against current harness
documentation (verified once, on the drafting host, CLI 2.1.247); the
collision-rename assumption (D-8, Task 4) is specifically unverified
platform behavior.

| Lens | Findings | Notes |
| --- | --- | --- |
| Contract correctness & internal consistency | 29 | REQ↔REQ and REQ↔D contradictions; ungated deliverables |
| Ambiguity & interpretation forks | 47 | material two-reading forks an executor would hit |
| Citation & coverage integrity | 10 | all IDs/obs resolve; wrong-target cites, orphan REQs |
| Dead verification paths | 26 | `[test]` entries with no executable subject in CI |
| Decision-domain gaps | none | §7 catalog walk: every touched domain decided |
| Testability (Done-when evaluable) | 26 | undefined criteria/thresholds; ungated deliverables |
| Cross-file consistency | 13 | contradictions with signed bundles, doctrine, scripts |
| Documentation & glossary drift | 29 | term overloads and naming drift, mostly expression-only |
| Rendered-content safety | none | validator parse clean; lint:md clean; no embedded markup |

### Revision worklist (root causes; dispositions pending)

**Cluster A — genuine contradictions (meaning-class edits required):**

- **A1.** REQ-A1.3 ("adoption changes no behavior… without messaging",
  requirements.md:86–88) vs the unconditional REQ-B1.1 (:99–102) and
  REQ-F1.1 (:176–179) dispatch-seam obligations; the REQ-A1.3 test
  (test-spec.md:32–33) covers only three consumer classes. Condition
  B1.1/F1.1 on capability presence, or scope A1.3.
- **A2.** "held" semantics: REQ-C1.3 (:123–126) mandates descending the
  fallback on *held*; D-9 (design.md:197–200) and test-spec.md:74–76
  mandate surface-only. Fallback-on-held double-delivers; pick one.
- **A3.** D-2 rejects "payload plus store as backstop" (design.md:51–53);
  D-9/REQ-C1.2 adopt exactly that shape for decision answers. Scope D-2 to
  upward/doorbell signals explicitly.
- **A4.** Host-level probe gating "the whole capability" (D-6,
  design.md:130–133) vs per-rung advertisement (REQ-A1.2) — socket-env
  presence is a per-session fact; probed from a socket-less rung a
  host-level gate reads everything absent. Also `probe`'s "host + session"
  split (tasks.md:28–30) never defines the session half's subject.
- **A5.** REQ-G1.1 "reach the fallback without operator intervention"
  (:201–203) vs the delivery ladder's terminal rung "park for the
  operator" (:117).
- **A6.** Goal/scope verbs "retire"/"replaces" (:19–21, :38–40) vs
  REQ-E1.2 "SHALL never be removed" (:166–167). Align on demotion.
- **A7.** REQ-F1.5's opt-in-plus-approval path vs the recommended
  `isolatePeerMachines: true` that suppresses it (:194–196,
  tasks.md:55–60, test-spec.md:158–162); additionally the harness
  approval prompt only fires for model tool calls, so script-driven sends
  have no per-send approval surface.
- **A8.** REQ-H1.1 "act only on what the store or git ground truth
  re-validates" (:226–229) vs steer text (no artifact to re-validate) and
  tower↔tower advisories (no store row). Scope H1.1 to doorbells/upward
  signals with an explicit advisory carve-out.
- **A9.** REQ-G1.4/D-14 and the out-of-scope entry name "the origin fence
  **and the presence surface**" as authorities on division of work;
  `concurrent-orchestrator-coordination` (its REQ-C1.1) and
  `fleet-coordination-floor.md:103–106` make the fence sole authority and
  presence attribution-only, never on the correctness path. Reword; the
  test entry (test-spec.md:183–187) freezes the same conflation.
- **A10.** REQ-C1.1 messaging-first steer on "every rung that advertises
  and accepts it" vs `headless-oneshot`'s `can_steer_inflight: false` /
  no-pend contract row. Scope delivery to steer-advertising rungs or flip
  the contract row deliberately (a contract change, not a side effect).
- **A11.** Idle-notice subscriber: D-10 pins the main-conversation
  subscriber; Task 6 places subscription "at the dispatch or watch step"
  (a deterministic script path; daemons receive nothing per the bundle's
  own floor). State who subscribes, and the one-shot/re-subscribe policy.
- **A12.** REQ-F1.4 "logged each time" (a transition) vs "no stored mode
  state" — transition detection needs prior mode. Pick log-per-send or a
  sanctioned marker; test-spec.md:155 currently forbids the marker.
- **A13.** Pressure demotion at the `doorbell` floor undefined (REQ-F1.4;
  distinct from the §3-resolved direction-offset floor).
- **A14.** Mechanism-vs-prose fork on the enforcement path: tower-side
  "handling **guidance**" (tasks.md:100–101) vs the deterministic handler
  REQ-D1.2/H1.1's SHALLs and tests presuppose; `send`'s "delivery-notice
  consumption **guidance**" (tasks.md:32–34) vs REQ-C1.3's deterministic
  consumption, D-12's single enforcement point, and the emit-only
  contracts of `fleet-decision.sh`/`orchestrate-relay.sh` (both print
  commands; sender-side notices arrive in the sending session's turn, not
  on a script's stdout). Decide the mechanism per path; most of cluster D
  hangs on this.

**Cluster B — coverage gaps (meaning-class additions):**

- **B1.** Orphan REQs: G1.1, G1.2, G1.3, H1.2 appear in no task's
  Citations and no deliverable produces their artifacts (H1.2's
  echo-sanitization tests; G1.1's per-path fallback headers).
- **B2.** D-12 (single enforcement point) is cited by no REQ and tested
  nowhere; nothing forbids parallel messaging code.
- **B3.** Towers: REQ-B1.1 covers "workers and towers" but Task 4 names
  only worker dispatch seams; D-8 rejects listing round-trips; Task 8
  needs tower addressability and depends on no identity work. No in-bundle
  mechanism addresses a tower.
- **B4.** REQ-A1.4's "pinned… per task" lands only in Task 2.
- **B5.** Ungated deliverables (no Done-when clause): doctrine index (T1),
  tower-profile acceptance + `isolatePeerMachines` recommendation (T3),
  tower-guard allow rules (T5), debug-log send visibility (T6),
  duty-cycle observation (T7), the verified-CLI-version record (T2).
- **B6.** The contract extension names only the doctrine table; the
  mechanism needs the pluggable adapter line grammar (8 fixed fields,
  `scripts/check-backend-capability-drift.sh` fails closed on other
  arities), `config/defaults.yml` entries for both knobs (the options
  reference is checked against it), and the `docs/fleet.md` knobs-table
  rows.
- **B7.** Lifecycle-closure floor: the new acquired resource classes
  (idle-notice subscription, tower inbox-address record) have no
  open/close/stuck-detector rows.
- **B8.** `doctrine/inter-orchestrator-coordination.md` pins buffer-paste
  as the delivery mechanism of record and already sanctions tower↔tower
  paste between co-located towers; the bundle changes that doctrine's
  mechanism without listing it for amendment (D-13 addresses only
  `fleet-coordination-floor.md`), and frames tower↔tower as pure
  hand-relay replacement.
- **B9.** The cross-machine opt-in knob is never named; its
  options-reference entry (Task 1) is unkeyable, and it risks conflation
  with the inversely-polarized harness setting `isolatePeerMachines`.

**Cluster C — undefined values blocking tests:**

- **C1.** The probe's CLI version threshold (which version gates
  messaging) is never stated.
- **C2.** Doorbell/message field set and length bounds — producer (Task 2)
  and receiver (Task 6) must share an undefined wire contract.
- **C3.** The reconcile-floor value, singular-vs-per-consumer floors, and
  a time-control seam for the healing tests (no clock injection exists in
  tests/lib/).
- **C4.** "Reported pressure": which monitor states count
  (`fleet-usage-gate.sh` has a five-state ladder, `context-budget-monitor`
  a binary; neither emits "pressure"; the worker→tower side has no
  pressure input at all).
- **C5.** Composition order of the direction offset and the pressure
  demotion (three readings, all passing the isolated tests).

**Cluster D — verification-path repairs (largely downstream of A14):**

- **D1.** The drift guard is self-referential: fixtures assert the pinned
  assumptions against themselves; CI has no live harness to detect real
  platform drift. Needs a live-probe arm, or an honest re-scope of what it
  guards.
- **D2.** Notice-driven `[test]` entries have no executable subject in a
  CI shell suite (C1.3 notice fixtures, C1.1 fixture-forced *refusal*,
  C1.2 induced delivery failure).
- **D3.** Model-guidance assertions tagged `[test]` (D1.2/H1.1 "cannot
  drive action past the re-read"; C1.4's permission clause is a platform
  guarantee, not testable repo behavior).
- **D4.** Missing baselines: A1.3's fixture-diff comparand, E1.1's "keeps
  today's cadence", Task 6's "liveness unchanged".
- **D5.** Unreachable branches in their own tag's environment: the
  idle-notice *expired* branch (12-hour one-shot, no fast-forward);
  the wrong-owner-socket case (needs a second uid).
- **D6.** Vacuous/undecidable Done-when clauses: "by construction in
  tests" (T5), the eval-or-recorded disjunct (T8), unbounded universal
  negatives ("cannot drive tower action", "no mode state file", "no
  correctness side effect"), "fails visibly"/"cleanly" with no criterion
  (T2/T3/T5), "evaluable definition" with no judge (T1), "each rung"
  unqualified (T4).
- **D7.** Tag mismatches: REQ-G1.4's review clause under `[test]`;
  REQ-F1.5's design-level clause under `[manual]`; E1.3's "no write path
  changed" is diff-review, not runtime.
- **D8.** The probe's positive branch has no version-injection seam; Task
  2's Done-when covers only the negative case.
- **D9.** Collision-rename is unverified platform behavior with no forcing
  method and no alternative-outcome wording (T4, D-8).

**Cluster E — evidence hygiene:**

- **E1.** obs:67861aa6 is mischaracterized (its subject is CI wall-clock
  vs the 600s tool ceiling, not completion signaling) and mis-consumed:
  none of its asks appear in the bundle. Recharacterize REQ-D1.3's
  evidence; un-consume the fragment.
- **E2.** obs:8b694bdb consumed while its stated fix (source-reader
  caching) is explicitly out of the diet's scope — switch to
  cited-not-consumed.
- **E3.** obs:eea622de and obs:58aa232e consumed although
  `specs/_pending/worker-permission-ergonomics-amendment.md` routes the
  same delivery work to `worker-permission-ergonomics`; reconcile
  ownership and cross-reference the note the way the merge-currency-guard
  note is.
- **E4.** "`merge-currency-guard` owns it" contradicts that bundle's
  signed out-of-scope (ownership lives in doctrine plus a pending note);
  soften the scope entry to match.
- **E5.** Citation repairs: REQ-C1.4's "orchestration-fleet relay
  doctrine" → `doctrine/inter-orchestrator-coordination.md`; REQ-G1.3's
  floor list matches neither the doctrine's five floors nor the homes of
  never-impersonate / no-auto-merge (and drops assume-multiplicity and
  lifecycle-closure); REQ-F1.1's substance has no backing D-ID (D-3 is the
  delivery ladder); REQ-D1.5's mechanism is design-unbacked (extend D-7 or
  mint); D-7's write-amplification claim → cite obs:2bea1358; unnamed
  precedents in D-2 (the push-first credit belongs to fleet-autonomy D-1),
  D-4, D-8, D-11; D-1 uncited by Task 7.

**Cluster F — terminology sweep (expression-only, one pass):** 29 items
from the glossary lens, headline overloads: capability vs property (pick
the contract's mechanism and a snake_case property id); "peer-messaging"
vs the platform's "cross-session messaging"; "rung" reused for ladder
levels (use "values"); "message discipline" vs `messaging_discipline`;
"reconcile floor"/"reconcile poll" vs the repo's reserved
"reconcile"/"floor" senses; "store-load diet" vs the instruction-hygiene
"diet"; ladder-terminal "park" vs the worker park state; doctrine
reference style (doc-name resolvable through the rule-doc chain);
"tower-guard" → "tower command-guard"; "bare mode" → "interactive
(non-`-p`)"; tmux-specific "paste" in all-rung ladder statements; "fleet
profiles" → the settings file names; "worker/scope registry" (two real
surfaces — pick one); v1 "task ledger" vocabulary in a v2 bundle;
"store lock" vs "fleet lock"; the contract's n/a / false / deferred
tri-state vocabulary; backticked contract rung ids; one ordered
delivery-outcome noun set; inbox address/socket/path naming.

Halted: 2026-09-02 (no sign-off record; anchor deliberately absent)

### Lens review pass 2 (2026-09-02, resumed session) — delta-scoped over the revision

**Scope and method.** Delta-scoped per `kickoff-verification`: the revision
`727b47a..89d8f54` (clusters A–F of the worklist above) plus what depends
on it; in practice the revision touched most of the bundle, so every lens
read all four files in full. Spec-class lens set (`artifact-lenses`),
seven parallel read-only agents (one per substantive lens) plus one
closure auditor over the worklist above, two rows inline (decision-domain
gaps via the §7 catalog walk re-run against the delta; rendered-content
safety via validator parse + lint). Tooling: `spec-validate` 0 errors /
0 warnings; `mise run lint:md` 0 errors over the bundle and this brief.
**Altitude check (REQ-H1.3): pass, re-confirmed** — D-1 stands unchanged
by the revision, is cited from the goal, and the task decomposition still
matches (doctrine + transport + one reduction task; no state-replacement
work).

**Validation.** Proportionate per `validation-rigor`: full three-pass
validation on the contradiction cluster (G below) — pass 1 re-read as each
consumer at the cited lines; pass 2 the sibling artifact (scripts, doctrine,
sibling bundles) the reviewing agent read; pass 3 outside-in against the
platform documentation the bundle's Sources cite, read again on 2026-09-02
(`code.claude.com/docs/en/cross-session-messaging`), and against this
host's running CLI (2.1.259; the resumed kickoff session is itself an
interactive session with `CLAUDE_CODE_MESSAGING_SOCKET` set). Convergence
validation where two or more lenses surfaced one root cause; spot-check on
singletons. Adversarial sweep on the keep set: the four findings that
assumed the Sources' "interactive sessions do not bind inboxes" line was
true (contract 1–2, cross-file 1–2, dead-path 3/19, closure NP1) are
refuted as stated by the documentation and by this session's own
environment — and resurrect as one root cause, G1 (the terminology sweep
mis-stated the platform fact). Self-critique outcome: the platform facts
verified this pass are the ones the docs page states; the socket post's
request line and any synchronous response are **not** on that page, which
is itself finding G2.

**Platform facts re-verified 2026-09-02 (docs page + this host):** the
inbox socket is bound by interactive sessions and by `-p` sessions alike;
only `--bare` sessions bind none. Socket path and per-session token are
exported to hooks and Bash as `CLAUDE_CODE_MESSAGING_SOCKET` /
`CLAUDE_CODE_MESSAGING_TOKEN`; a posting script writes one complete line
within 30 s, optionally preceded by an auth line; the docs state no
response line. Feature floor: CLI 2.1.224 (macOS/Linux), 2.1.248 on
non-Anthropic providers or with flag fetching off; `notify_when_idle`
needs 2.1.236 in both sessions. Inbound outcomes: delivered, held,
refused; a `-p` session's default-held message expires after
`dialogExpiry` (5 min default) and is reported as expired to a reachable
sender; sender-side hold/deliver/deny/expire notices are shown when the
sender is an interactive session. `crossSessionInbound: accept` is
documented as deliverable through a `-p` session's `--settings` value.
`isolatePeerMachines: true` from any scope forces an approval prompt on
every cross-machine `SendMessage`, even in bypass mode. Interactive
start/resume/rename onto a used name renames to a variant; `-p --name`
collision behavior is not stated. `ListAgents` and `SendMessage` are
absent from the repo today; CI installs CLI 2.1.179, below the messaging
floor.

| Lens (spec class) | Findings | Notes |
| --- | --- | --- |
| Contract correctness & internal consistency | 20 raw | 4 refuted as stated (→ G1); the rest merge into G2–G25 |
| Ambiguity & interpretation forks | 25 raw | executor forks on `probe`/`send`/`doorbell-read` signatures, consumers, seams → cluster H |
| Citation & coverage integrity | 10 raw (8 checks clean) | no orphan REQ/D-ID; obs restorations verified in the store; mis-targets → cluster I |
| Dead verification paths | 26 raw | 2 refuted (→ G1); test-bound socket, comparands, eval offer, live arms → G2, H |
| Decision-domain gaps | 3 | re-run against the delta: socket wire contract (API surface), notice/log destination (observability), test-only override guarding (secrets-config) undecided → G2, G17, H-override |
| Testability (Done-when evaluable) | 45 raw | one non-existent gate (`check:hook-contracts`), ungated deliverables, citation gaps → cluster H |
| Cross-file consistency | 17 raw | 2 refuted (→ G1); registry grammar / marker arity / meta-tower seam / lifecycle placement / manifest → G15–G23 |
| Documentation & glossary drift | 27 raw | sweep stragglers and new collisions (`eligibility`, `availability`) → cluster J |
| Rendered-content safety | none | validator parse clean; lint clean; no embedded markup |

**Worklist closure audit (the worklist above, verified against the
current text, not the commit messages).** Applied: A1–A6, A8–A10, A12,
A13; B1, B2, B4, B5, B9; C2, C4, C5; D3, D4, D6, D7, D9; E1–E3; F1, F2,
F4–F7, F9, F14–F19. Superseded, consistently: B6 (D-17 removed the need
for a column), B7 (a no-new-class declaration instead of rows — residual
G21). Partial or with residuals: A7 → G4; A11 (subscribe/re-arm is a
prose step, `[manual]` only — accepted); A14 → G2, G15; B3 → G10, G18,
G19; B4 (Task 8 lacks the re-verify clause) → H; B8 (D-14 still frames
the status quo as hand-relay) → J; C1 → G13; C3/D5/D8 (test-only
overrides unguarded) → H; D1 (REQ-A1.4 text overclaims what fixtures
catch) → H; D2 → G2; E4 (test-spec still says "left to
`merge-currency-guard`") → I; E5 (test-spec floor list; D-11 label) → I;
F3, F11, F12, F13 stragglers → J; F10 → G1.

### Revision worklist 2 (root causes; dispositions recorded below as decided)

**Cluster G — contradictions and unverified premises (meaning-class):**

- **G1.** The cluster-F sweep rewrote Sources' "bare mode does not [bind
  inboxes]" as "interactive (non-`-p`) sessions do not"
  (requirements.md:483) — false per the docs and this host; it made
  D-17/REQ-A1.6's `tmux` eligibility, D-3/REQ-C1.1's "`tmux` included",
  the tower as doorbell receiver (D-7, REQ-D1.1/D1.5) and Task 5's live
  `tmux` check look self-contradictory. Fix: restore "`--bare` sessions
  bind none" and add the non-`--bare` conjunct to D-17/REQ-A1.6 (planwright
  already pins non-`--bare` launches, execution-backends D-12).
- **G2.** The script-post design assumes a synchronous outcome (accepted,
  held, refused) returned on the socket — REQ-C1.5, D-9, D-12, Task 2
  `send`, test-spec C1.5, every "test-bound socket speaking the pinned
  protocol" clause — but Sources (requirements.md:478) and the docs record
  only asynchronous sender-side notices, and the docs state no response
  line and no request-line format. Unverified platform behavior, unlike
  D-8 not flagged as such; the "pinned protocol" the drift guard freezes
  (test-spec.md:44–47) has no stated content. Options: (a) keep the
  synchronous design, mark it unverified with Task 2's first step the
  verification and a stated fallback; (b) redesign now: a post observes
  only success/failure of the write, every other outcome is healed by the
  sweep or recovered from the artifact; (c) route sends through the
  model's `SendMessage` tool (rejected in D-9's alternatives).
- **G3.** D-18 inverts obs:58aa232e (which says permission-class keys via
  `--settings` DO apply; only hooks fail to register) and the docs say
  `crossSessionInbound: accept` is delivered through a `-p` session's
  `--settings` value; Task 3's Done-when ("both shipped profiles carry the
  inbound … settings") and its deliverable (`settings.local.json` + env
  gate) name two different routes; requirements.md:71–74 and :515–516
  attribute the interim pattern to the pending note, which does not record
  it (obs:58aa232e does). Fix: D-18 → the messaging keys ride the shipped
  profiles via `--settings`; the `settings.local.json` route is hook-only
  and not needed here; attribute the pattern to obs:58aa232e.
- **G4.** `messaging_cross_machine` is a SHALL (REQ-F1.5) on a path no
  shipped code reads (only model-composed sends can be cross-machine, and
  they bypass `fleet-messaging.sh`); Task 3's "a cross-machine send
  without the knob is refused" asserts a refusal nothing performs. Fix:
  REQ-F1.5/D-5 state that enforcement is the harness's
  `isolatePeerMachines: true` (carried in both profiles, a `true` from any
  scope wins) and the knob is the documented operator cue; Task 3's
  Done-when becomes the profile assertion plus a `[manual]` prompt check.
- **G5.** REQ-D1.4 heals "lost, held, or dropped"; REQ-C1.5 leaves held
  queued and names dropped/expired as the sweep's cases. Fix: D1.4 →
  "lost, dropped, or expired".
- **G6.** D-15's kind set includes `complete`, which no producer emits
  (REQ-D1.1/Task 6 post attention/fork/park; completion is idle notices per
  REQ-D1.3); and `<instance>` is the fork instance id, meaningless for
  three of four kinds. Fix: drop `complete`; make `<instance>` `-` for
  non-fork kinds (five fields kept, grammar unchanged otherwise).
- **G7.** D-10 re-arms after every delivery ("the prior one-shot has fired
  or will") yet says "an expired subscription is not renewed" and rejects
  idempotent re-subscribe as undocumented. Fix: one rule — re-subscribe
  after each downward delivery, unconditionally; a duplicate or expired
  prior subscription is harmless because a notice is only a supplement;
  drop the "not renewed" clause and the now-moot rejection rationale.
- **G8.** Tower↔tower advisory traffic is "under the discipline knob"
  (Task 8) but D-4's formula defines only two directions. Fix: add the
  third direction — tower↔tower resolves at the knob value (offset 0;
  towers are the interrupt-absorbing side per D-4's rationale), pressure
  demotion applies.
- **G9.** The ladder gates model-composed traffic only, so `send`'s
  "discipline-checked" post is a permanent no-op and REQ-H1.3's
  "discipline enforcement has exactly one home" is false (enforcement is
  prose, Task 8). Fix: drop "discipline enforcement" from REQ-H1.3 and
  "discipline-checked" from Task 2; `effective-mode` is the oracle the
  prose consults (and tests).
- **G10.** REQ-D1.5's marker fallback is unconditional, but D-8/Task 4
  write the marker's socket path only for fleet-launched towers; the
  ordinary operator-launched tower gets none. Fix: every tower writes its
  observed name and socket path into its marker at `/orchestrate` start
  (the marker is already written per tower); Task 4's Done-when covers
  every tower.
- **G11.** REQ-D1.1 "no model turn on the routine path" vs REQ-D1.2's
  tower-session receiver (a tower turn per doorbell). Fix: "no
  worker-model turn"; state the tower-turn cost once (also G25).
- **G12.** REQ-G1.1 requires reaching the fallback on any failure; REQ-C1.5
  declares dropped/expired unobservable; and the "healing sweep" REQ-C1.5
  names for downward deliveries is tower-side (Task 7) and re-delivers
  nothing — no deliverable heals a dropped downward answer. Fix: scope
  G1.1 to observable outcomes; C1.5/D-9: a dropped or expired downward
  delivery leaves the worker parked, which the tower's sweep surfaces as
  an undelivered answer for the operator handoff (recovery = the persisted
  artifact); no re-delivery mechanism is added.
- **G13.** The pin of record is both the probe's version floor and the
  drift guard's last-verified anchor, and every platform task "updates the
  pin" — so a task run on a newer CLI raises the floor and silently reads
  older capable hosts as absent (the silent no-op REQ-A1.4 forbids); the
  pin's initial value is stated nowhere normative; nothing forbids
  lowering it. Fix: split — a documented minimum (`2.1.224`; `2.1.248` on
  non-Anthropic providers / flag fetching off) the probe compares against,
  and a last-verified pin (`2.1.247` initially) the drift guard freezes and
  tasks raise, never lower, recording the observed version in the task PR;
  a running CLI below the pin halts the task.
- **G14.** REQ-A1.5 calls the dispatch-seam preparation "unconditional";
  Tasks 3/4 scope it to the three session-grade rungs. Fix: "unconditional
  on eligible rungs — independent of the per-session probe".
- **G15.** Task 5 turns `orchestrate-relay.sh` and `fleet-decision.sh`
  from command-emitters into actors (the post is performed, its outcome
  consumed) without naming the contract change: the scripts' headers, the
  inter-orchestrator doctrine's "one audited script" sentence and
  `relay-command` description (REQ-G1.7's amendment does not cover them),
  and `fleet-decision.sh`'s exit-4 contract vs Task 5's "exit 0". Fix:
  Task 5 states the exit codes per ladder outcome (terminal handoff keeps
  today's non-zero exit; 0 only when a step delivered), names the header
  and exit-table updates; Task 1's amendment covers the two doctrine
  sentences.
- **G16.** REQ-H1.3's audit ("no other script opens a socket path") vs
  D-7's hook validating the socket path before posting; "opens a socket
  path" is not greppable. Fix: the audit's match set is literal — the
  `planwright-doorbell` tag and the `CLAUDE_CODE_MESSAGING_SOCKET` name —
  over `scripts/*.sh`, exempting `fleet-messaging.sh`; the owner/existence
  predicate lives in `fleet-messaging.sh` and the hook calls it.
- **G17.** REQ-F1.4's "one log line per demoted send" and D-7's "per-worker
  debug log" have no defined destination (no such log exists), and the
  test's "state directory listing identical" invariant is unsatisfiable if
  the line lands under the fleet home. Fix: notices go to stderr from
  `fleet-messaging.sh`; the doorbell hook appends them to a named
  per-worker file `<fleet-home>/workers/<id>/messaging.log` (Task 6
  deliverable); the listing invariant is scoped to `effective-mode`.
- **G18.** REQ-B1.2/Task 4's "additive fields": the worker registry's
  field grammar forbids `/` (a security rationale REQ-B1.3 leans on), and
  the tower marker is a fixed seven-field row whose lockless reader skips
  any other arity. Fix: the worker's socket path is recorded in a
  per-worker state-directory file, not the registry; the marker gains one
  field with its readers (`fleet-tower-signpost.sh`, the watchdog) updated
  and a mixed-arity fixture — named in Task 4's deliverables and Done-when.
- **G19.** REQ-B1.1 names `--name` for towers "launched by the meta-tower",
  but a meta-dispatched subordinate may run on `subagent`/`in-session`
  (no CLI launch). Fix: scope the tower clause to session-grade tower
  launches (the watchdog's `tmux` launch, any `-p` launch); a
  subagent-hosted subordinate is not a messaging peer.
- **G20.** Task 1 puts "the per-session probe definition" in the contract
  doc; D-17 says the contract doc gains only the derivation rule. Fix:
  probe definition lives in the messaging-transport doctrine.
- **G21.** REQ-G1.6's no-new-class declaration lives in the new doctrine,
  while the lifecycle-closure floor's contract is a single-home table
  (`fleet-coordination-floor.md`, fleet-lifecycle-closure REQ-A1.4) whose
  discipline is that absence means omission; D-13 says the floor is not
  amended. Options: (a) one row in the floor's class table for the inbox
  socket (harness-owned, closes with the session, detector: the session's
  own death evidence); (b) keep the declaration in the new doctrine and cite
  fleet-lifecycle-closure REQ-A1.5 by ID from REQ-G1.6.
- **G22.** Task 8 / test-spec G1.4 assert the presence file byte-identical
  across a live window; the sibling bundle re-publishes presence on every
  heartbeat. Fix: byte-identity on fence refs and `tasks.md`; presence
  covered by the design-level "no advisory path writes it" review.
- **G23.** REQ-G1.5's "cited by skills" needs `Doctrine:` manifest lines
  (`instruction-hygiene`) in `/orchestrate` (and `/execute-task` for the
  hook side); no task ships them. Fix: Task 8 (and Task 6) deliverable +
  Done-when.
- **G24.** Task 1's fallback table must cover "every messaging path this
  bundle's tasks ship" before any ships (Task 1 has no dependencies).
  Fix: enumerate the paths in D-13 (downward steer, decision answer,
  doorbell, idle notice, the demoted sweeps, tower↔tower advisory) and gate
  Task 1 against that list; Task 7 re-verifies the table last.
- **G25.** Every doorbell costs a tower model turn (D-1), yet D-4 keeps
  doorbells ungated at maximum pressure as "the cheapest signal". Not a
  contradiction (cheapest on the worker side) but an unrecorded trade.
  Fix: one sentence in D-4 recording it; a risk-register row.

**Cluster H — executor forks and evaluability (gap-fills consistent with
the decisions above; each is a small addition):** H1 pin `send`'s
signature (`--to <socket path> --direction <worker-to-tower|tower-to-worker|tower-to-tower> --message-file <path>`; the body is read
from the file and posted as data, never interpolated) and `doorbell-read`'s
(one invocation per doorbell, the whole line verbatim; delegates to
`fleet-attention.sh render` for the worker's row) in D-12/Task 2. H2 the
probe predicate: `CLAUDE_CODE_MESSAGING_SOCKET` set and naming an existing
socket owned by the invoking uid, CLI version compared numerically per
dotted component. H3 who posts doorbells: `fleet-attention.sh`'s
`attention`/`fork`/`park` verbs delegate to `fleet-messaging.sh doorbell`;
no `hooks.json` entry. H4 the test seam for the socket: a test-only post
override (`PLANWRIGHT_MESSAGING_POST`, pointing at a recording stub that
returns a canned outcome), since the CI toolchain has no socket binder;
the same stub gives REQ-G1.4's advisory test a sending subject. H5 the
demoted consumers by path: `fleet-dashboard.sh watch` (default 30 s) and
`fleet-attention-watch.sh watch` (default 15 s; its fswatch branch is a
timeout, unchanged); `fleet-status.sh` has no loop and is dropped; the knob
replaces the default interval, an explicit `--interval` wins; the tower
loop demotes when its own probe reads available and at least one in-flight
worker is eligible-and-wired, re-evaluated each pass. H6 "accepting" for
idle notices = the target rung is eligible and the shipped profile carries
`crossSessionInbound: accept`. H7 "each session-grade rung" → the three
shipped ids, in Tasks 3/4/6. H8 the tower-marker lookup key is the spec
half of `PLANWRIGHT_WORKER_SCOPE`; a meta-tower is never a doorbell
target. H9 REQ-A1.5's comparand: frozen outputs of the delivery scripts and
the two demoted consumers only (the doorbell and idle-notice paths have no
pre-messaging output; absence there is "not invoked"); the post-Task-4
launch argv is the naming comparand; both freezes gated in Task 2/Task 7
Done-whens. H10 duty-cycle: derived from the resolved cadences over a
one-hour window, not sampled. H11 held is surfaced as one stderr notice, no
store row. H12 `check:hook-contracts` does not exist → `check:githooks` (superseded on
2026-09-04: the merge of `main` brought `check:hook-contracts` in, and the
bundle gates it in Task 3; the `check:githooks` substitution was reverted)
(or drop). H13 ungated deliverables get clauses: T1's six doctrine
contents + the G1.7 cross-reference half + the three knob surfaces +
`check-backend-capability-drift.sh` passing; T2's four post outcomes, the
demotion log line, the listing invariant, the echo-sanitization surface;
T4's worker record; T6's socket-path propagation (five fixtures) and the
second-notice re-arm `[manual]`; T8's two addressing paths and the
three-value composition prose; T3's cue prose (folded into T1's
options-reference row) and the per-rung settings write (fixture).
H14 citations: REQ-D1.4 → Task 7; REQ-E1.1 → Task 1; obs:b7618838 →
Task 5; REQ-A1.4 + the re-verify clause → Task 8. H15 `[manual]` carried
inline on live clauses in Tasks 3/4/5/6/8. H16 Task 2's "absent on a host
without the feature" dropped (indistinguishable). H17 T5's universal
negatives → bounded assertions (one post attempt per step by call counter;
claim field unchanged by before/after diff; the `send-keys` grep kept).
H18 T6's hostile table = one row per D-15 constraint. H19 T7's E1.3 clause
mirrors the test-spec split. H20 Task 8: `check:instructions` exits 0 with
no new warnings; the live advisory check's criterion is "the post reports
success and the receiving tower's transcript shows the text"; the eval
disjunct becomes a named `[manual]` observable (the tower's next turn
invokes `doorbell-read` and nothing else; same for H1.4), and the
behavioral-eval offer is dropped (the harness drives one session). H21
REQ-E1.2's per-value sweep → a source audit that no demoted consumer reads
`messaging_discipline`. H22 REQ-A1.4's text: "fixtures guard planwright's
parsers; the live re-verification is what catches the platform moving".
H23 test-only overrides (`--cli-version`, `--owner-uid`, `--now`,
`PLANWRIGHT_MESSAGING_POST`): refused unless `PLANWRIGHT_TEST_SEAM=1` is
set (one guard, documented in D-11). H24 the collision check: the
observed outcome is written into D-8's amendment note, not only the PR.
H25 REQ-F1.5 live arms: the refusal arm is design-level (profile review);
the prompt arm stays `[manual]` and notes it needs a second machine or a
cloud session.

**Cluster I — citation and evidence repairs (expression-only):** test-spec
G1.3's floor list → the requirements wording (five floors by doctrine,
never-impersonate via inter-orchestrator-coordination, never-auto-merge via
the autonomous-safe-decision doctrine, also added to REQ-G1.3's cites);
test-spec E4 straggler ("left to `merge-currency-guard`" → the doctrine's
assignment); D-11's "launch-pin precedent, execution-backends D-4" → the
version-pin-and-re-verify precedent (D-4), launch pin D-12; D-4's
`invariant-tasks D-2` → `invariant-tasks D-12` / `orchestration-concurrency
D-1`; REQ-G1.7's "tower↔tower paragraph" → the tower-to-tower clause of the
*Attributed, non-impersonating relay* section; tags: F1.5 `[test + manual +
design-level]`, G1.5/G1.7 `[test + design-level]`; "lifecycle-closure" →
"the fleet-coordination-floor doctrine's lifecycle-closure floor";
changelog: D-8 "names its precedent" narrowed to D-11; Sources'
`orchestration-fleet` "(relay doctrine …)" → the inter-orchestrator
doctrine and the backend capability contract; D-4's context-budget monitor
"binary" → three states; test-spec A1.6 "the registry" → the backend
capability registry (`orchestrate-backends.sh caps_for`); Task 3/Task 1
cite the two shipped profile files by name.

**Cluster J — terminology (expression-only, second sweep):** "worker/scope
handle grammar" in D-15 → the per-backend fleet handle grammar
`fleet-decision.sh` owns; "push-first-reconcile-backed" in D-16 →
"push-first, sweep-backed"; `peer_messaging` in D-17's alternative → "a
new messaging column"; "the next fallback rung" (REQ-C1.5) and "one logged
notice per rung" (Task 5) → "step"; "paste" in D-16/D-9 all-rung sentences
→ "attributed steer delivery"; "capability boundary" (D-1) / "capability
without silent egress" (D-5) → availability; "property of the rung/session"
(D-17) → "fact about"; outcome order in Sources and test-spec C1.5;
"advertised and wired" (REQ-E1.1) → "eligible and the session's probe
reads available", headings → "Availability & eligibility"; unbackticked
`tmux` (Sources); "eligibility" → "messaging eligibility" wherever
unqualified, with one D-17 sentence distinguishing it from the contract's
dispatch eligibility; REQ-A1.6's composite "availability" → "a send is
possible when"; "session-grade column" as the one noun; `messaging_discipline`
named in test-spec F1.2 and `messaging_cross_machine` in D-5; `--cli-version`
named in test-spec A1.1; `effective-mode` kept as the verb name with one
D-12 line saying so; "handoff trigger" (D-4) → "context-handoff trigger";
one doctrine sentence distinguishing the healing sweep from `/orchestrate`'s
reconcile sweep (Task 1); the three over-long lines re-wrapped; ladder
naming: "fallback ladder" only (D-3's title), "discipline ladder"; the
doctrine's file name `doctrine/messaging-transport.md` stated in D-13/Task
1; first-use citations for the tower marker (`fleet-tower-marker.sh`), the
two stores (attention vs decision-channel), the `--now` precedent
(`fleet-pane-detect.sh`); D-14's alternatives no longer call the status quo
pure hand-relay.

### Worklist 2 dispositions (2026-09-02/03, operator picklist)

- **Workflow:** resolve everything in this session (a second revision
  commit set), rather than halt again.
- **G2:** keep the synchronous-outcome design, marked unverified with a
  write-success fallback; Task 2's first step verifies the wire contract.
- **G21:** one class added to the floor's lifecycle-closure contract (the
  inbox socket).
- **G12:** no re-delivery; the sweep surfaces the parked worker for the
  operator handoff (recovery = the persisted artifact).
- **G13:** the documented minimum and the last-verified pin are split.
- **G1, G3–G11, G14–G20, G22–G25:** applied as proposed. **H, I, J:**
  applied as proposed. Applied in requirements.md and design.md by the
  kickoff session; tasks.md and test-spec.md rewritten from them.

### Mid-walk lens over the applied edits (2026-09-03; `kickoff-verification`, REQ-B1.4, D-5)

Delta-scoped over the working-tree diff (the four spec files against
HEAD), three read-only agents: contract consistency + ambiguity forks;
citation and coverage + cross-file consistency against the repo's scripts,
doctrine, sibling bundles, and observation store; dead verification paths +
testability of the rewritten tasks and test entries. Validation: every
finding cites the script or doctrine line it read; the kickoff session
re-read the flagged scripts' verb tables, arity gates, and the doctrine
manifest guard before dispositioning.

| Lens (spec class) | Findings | Notes |
| --- | --- | --- |
| Contract correctness & internal consistency | 12 | exit-table wording, D1.4 scope, D-12's stale rationale, D-7's "hooks", the one-audited-point audit vs socket-path propagation |
| Ambiguity & interpretation forks | 5 | two-valued minimum, "runs demoted", both-accept, two per-worker homes, `send --direction worker-to-tower` |
| Citation & coverage integrity | 14 | missing citations both ways (Tasks 1/3/6/8), ungated deliverables, two `[manual]` arms no PR asks for, `fleet-autonomy D-7` push-side only, lifecycle-closure REQ-A1.5 mis-cited |
| Dead verification paths | 10 | `check:doctrine-manifest` blind to the new lines; `--now` reads no clock in the sweep pass; the dashboard is not a healing sweep; the G1.4 test tautology; the per-worker directory does not exist |
| Decision-domain gaps | none | the delta added no undecided domain; the post-seam contract (API surface) and notice destination (observability) were decided in this pass |
| Testability (Done-when evaluable) | 12 | post-seam contract undefined, comparand freezing not reviewable across a squash, `check:githooks`/`lint:json` insensitive, unbounded sanitization set |
| Cross-file consistency | 9 | `fleet-attention.sh attention` does not exist (`heartbeat`/`decide`/`fork`/`park`); `render` has no worker selector; the handle grammar is `orchestrate-relay.sh`'s; the marker is seven fields; `fleet-dispatch-worktree.sh`'s pin refuses `--settings`; the floor table's no-blank-cell rule needs a column; the steer-in-flight heading |
| Documentation & glossary drift | 6 | annotation placement/order/dates, `Last reviewed`, three long lines |
| Rendered-content safety | none | validator parse clean; lint clean |

**Dispositions.** Two findings reopened earlier dispositions and went to
the operator: the per-worker record home (G17/G18 — no `workers/` tree
exists, the lifecycle-closure bundle's state directory is unshipped, and
the floor table gives the `tmux` rung no state directory) → **registry
basename field, notices to stderr, no per-worker log** (the floor
amendment stays one class); the initial pin → **2.1.259**, the highest
version this bundle observed. Everything else applied as proposed: the
verbs, the grammar owner, two marker fields with `fleet-tower-marker.sh`
named, the marker written at step start, the probe against 2.1.248
unconditionally, the `--now` seam dropped and `--socket-type` added, the
`eligible` and `self-socket` verbs, `PLANWRIGHT_TOWER_INBOX_SOCKET`, the
post-seam contract, the doorbell and `effective-mode` signatures, the row
plus column floor amendment, the steer-in-flight heading, the escalation
pin and tower command-guard allow rules for the profile path and `--name`,
the tower profile at fleet tower launches, the answered-undelivered
attention mark, the citation and gating repairs, the annotation and date
fixes. Declined: none. Deferred: none. An erroring pass: none.

### Platform experiments (2026-09-04, kickoff host, CLI 2.1.259 tower / 2.1.261 worker)

Run at the operator's request while walking section 3 (upward signals), to
decide between the specified shape and two alternatives on evidence rather
than a guessed trade-off. Static evidence first: the installed CLI binary's
own strings give the inbox wire format (JSON lines: an optional
`{"type":"auth","token":…}` then `{"type":"user","message":{"role":"user",
"content":…}}`, the binary's example piping through `nc -N -U <socket>`),
and show that held / refused / dropped outcomes are `peer_message_status`
frames addressed to the sender's *reply address*, correlated by message id
— not a reply on the posting connection. `inotifywait` and `fswatch` are
absent on this host; OpenBSD netcat (connect and listen on Unix sockets) is
present.

| Experiment | Observed |
| --- | --- |
| E1: raw post from this interactive session's Bash to its own inbox (`nc -N -U`) | delivered into the session as a peer message ≈100 ms later; connection returned 0 bytes; `nc` exit 0 |
| E2a: `SendMessage` from this session to a `claude -p` worker launched with `--settings {crossSessionInbound: accept}` and `--name` | the worker appeared in `ListAgents` under its name 2 s after launch; the message was read mid-turn, between tool calls, during its `sleep` |
| E2b: raw post from the worker's Bash (not this session's child, no permission-class attestation) to this session's inbox | delivered ≈1 s later, not held (this session is in a prompting mode); 0 bytes returned |
| E4 (2026-09-07): an interactive `claude` in a tmux window (`--name`, inbound accept) armed an idle subscription on the kickoff session and went idle; the kickoff session then sent it a message and later ended its turn | the message started a new turn in the idle session within seconds (it replied); the idle notice, enqueued when the kickoff session's turn ended, also started a new turn in the idle session; the subscription was consumed by that one notice |
| E3: `notify_when_idle` subscription on the worker | the idle notice was enqueued here 1 s after the worker's turn ended, carrying the worker's own one-line closing status; it reached this session's model only at its next turn boundary (about 40 minutes later, the session having stayed busy), whereas E2b's raw message was read mid-turn between tool calls |

What this settles: a script post observes only write success or failure
(G2's fallback is the primary path, not the exception); a raw post reaches
a prompting-mode tower without being held; a `-p` worker takes messages
unattended through `--settings`; the idle notice is prompt and carries a
status line, so a parked worker's "stopped" reaches the tower without any
worker-side socket handling; shape C (tower-side inotify watcher) would be
polling on this host.

### Section 3 decision on the upward path (2026-09-04) and its mid-walk lens

Presented as three shapes at equal weight (A: worker-side doorbells as
specified; B: idle notices plus the sweep; C: a tower-side inotify watcher),
then re-presented on the experiment evidence. **Operator decision: B.**
Applied as a meaning-class redesign: REQ-D1.1 and REQ-D1.5 → REQ-D1.6,
REQ-D1.2 and REQ-D1.3 → REQ-D1.7, D-7 → D-20, D-10 → D-21, D-15 retired
without a replacement grammar; the ladder floor value renamed `doorbell` →
`script`; the tower marker gains the name only; `notice-read` replaces the
doorbell verbs; tasks.md and test-spec.md rewritten on Opus.

Mid-walk lens (two Opus agents, delta-scoped over the redesign):
contract/ambiguity 19 raw, citation/cross-file/verification 27 raw. All
applied as proposed, with these substantive outcomes: the worker's registry
row records the observed session name beside the socket basename, both
read from the CLI's per-session record `~/.claude/sessions/<pid>.json`
(verified on this host: name, nameSource, kind, status, cwd,
messagingSocketPath, plus a `.key` auth file; an undocumented surface the
drift guard freezes); `send` gains `--to-worker` so the basename is resolved
inside the one audited script; the tower↔tower advisory is model-composed
through the harness's message tool (no script post; fallback not-sent);
notice timing is stated at enqueue with model visibility at the next turn
boundary; the `notice-read` name grammar and its `--watch` scoping; the
`inbox=` field as REQ-E1.1's proxy for the unrecorded subscription; the
`headless-oneshot` fire-before-exit unknown recorded for Task 6's live
check; `validate-handle` arms for the two `-p` rungs; the instruction-budget
constraint on Task 1 and Task 8 (measured closure headroom about 1000
words). Declined: none. Deferred: none.

**Section 3, failure bite (2026-09-07).** Asked "could we do better?", the
kickoff presented the lost-downward-answer gap with two options (make the
loss observable through the reply address the harness's status frames use;
timed re-delivery) beside surface-only. **Operator decision: observable
via the reply address.** Applied: REQ-C1.5, D-9, D-12, D-11's frozen
assumptions, Task 2's wire step (a refused receiver as the probe for the
status frame), Task 5 (`fleet-decision.sh redeliver <fork id>`, once per
fork, fallback step only, plus the `/orchestrate` standing instruction),
test-spec C1.5 and H1.4. Surface-only stands where Task 2 finds no frame.

**Section 4 sanity check (2026-09-07; two Opus reviewers: assumptions and
blind spots; five fleet-flow simulations).** Ranked findings relayed to the
operator in plain terms. The decisive one: E3 had shown an idle notice
waits for the receiving turn to end while a peer message is read
mid-turn, and the `--watch` loop is one long turn, so the chosen upward
push never reached the posture the watchdog launches. Experiment E4 then
showed an idle interactive session is woken by a message and by a notice
alike. **Operator decision: the tower becomes event-driven** — the watch
loop ends its turn per step and is woken by a notice, a message, or a
timer (REQ-D1.8, D-22; an amendment orchestration-fleet D-38 must accept,
recorded as a pending note Task 6 ships). Applied with it, from the
reviewers' lists: the identity environment exported at every session-grade
seam (obs:fbb701bc — tmux and stream-json workers write no attention rows
today); decision answers on `stream-json-persistent` go through the
supervisor's control-response verb, never a message (a message cannot
resolve a pending control request); read-back keyed on the worker's
checkout path, not a process id two rungs never hold, with a bounded
retry; a start-of-tower subscribe pass over the in-flight set (a fresh
tower after a relaunch or handover holds no subscriptions) and the
demotion trigger requiring a live subscriber; the message id recorded in
the answer artifact so a drop frame names a fork; held's own exit code;
operator-facing cadences (the watcher with a callback, the dashboard's
refresh) kept at today's intervals — nothing pushes to the human — and the
cadence bounded by the watcher's liveness max-age; the probe's
inbound-acceptance conjunct (an unmerged tower profile reads absent);
mid-turn suspensions (permission and elicitation dialogs, obs:4c25e743)
named as the sweep's case; the Stop hook recorded as a considered
alternative; the goal's delivery wording corrected; four platform
behaviors added to Task 2's wire-step list. Noted for the reviewer's
proportionality point: the discipline ladder now gates only the advisory
path and an operator-prompted worker send; the operator kept it.
Declined: none. Deferred: none.

**Mid-walk lens over the event-driven edit (2026-09-07; two Opus agents:
consistency and citations; dead paths and repo fit).** Contract/ambiguity
33 raw, verification/repo 44 raw; all applied. The substantive outcomes:
the fleet watchdog cannot stand in for the timer (its tick exits on an
interactive marker, is one recorded action, and runs only where an
operator scheduled it), so the timer is the harness's scheduled wakeup
alone and the metronome is kept where the wakeup is unavailable, where the
probe reads absent, for a `-p` tower (the continue-as-new handover launches
one), and for a step with no wake source; a session's own process id
(`CLAUDE_PID`, verified on this host to name its per-session record) lets
workers record their own name and socket basename from a SessionStart hook
(`self-register`, a new `fleet-state.sh amend` verb, `-` sentinels until
the hook runs, every registry reader tolerant of both arities), which
retires the seam read-back and its retry window; the marker goes back to
watch-loop start (a step-start write leaked a dead-tower signpost after
every single step); the message id and the `redelivered` mark live in a
per-fork metadata sibling, never inside the answer artifact the fallback
pastes verbatim; on `stream-json-persistent` the decision channel refuses
and the supervisor's verb answers from the decide row's request id; both
guard re-scopes are dropped (each seam builds its own launch line and the
tower command-guard auto-approves planwright scripts wholesale); Task 3
keeps the profiles and gates `check:hook-contracts` (which now exists after
the merge), the seam wiring and the live acceptance checks move to Task 4;
REQ-E1.1's trigger rests on recorded facts only, the watcher's deep
reconcile period is preserved under demotion, its bring-up is documented
(it has no shipped caller), and the cadence is bounded against
`--max-age`; the metronome decision is `bootstrap` D-38 (the note is
renamed); the probe's acceptance conjunct gains the seam-exported layer a
`--settings` launch needs; `Last reviewed` bumped to 2026-09-07. Declined:
none. Deferred: none.

**Section 5 walk (2026-09-07).** Asked "anything we are missing?", the
kickoff named three verification gaps and, asked for the better long-term
form of each, recommended: a local-only fleet smoke runner as the standing
platform-drift check (REQ-A1.7, D-23; Task 7 ships it and runs it as its
capstone; later platform-touching changes rerun it); the `off` switch value
of `messaging_discipline` as the per-fleet kill switch (REQ-F1.2, REQ-A1.1,
D-4); and a Deferred gate on Task 6's loop change until bootstrap's D-38
amendment, drafted for real through `/spec-draft --extend bootstrap`, is
signed (REQ-D1.8, D-22). **Operator decision: all three.**

### Terminal lens pass (2026-09-07) — full bundle, sign-off step 1

Four Opus lens agents over the four spec files in full (the brief read only
where a cross-check demanded it): contract + ambiguity (34 findings),
citations + cross-file (22), dead verification paths + testability (24),
glossary + drift (20). 100 raw findings merged into the root causes below;
every code-grounded claim was re-checked against the worktree by the
kickoff before disposition (answer-artifact path, watcher defaults and
flags, registry readers and charsets, the tower guard's `--settings`
handling, the instruction-budget floors, bootstrap's status, the
stream-json decide row). Nothing was refuted.

Lens coverage (spec class, `kickoff-verification`):

| Lens | Findings | Notes |
| --- | --- | --- |
| Contract correctness | 28 | interfaces, arities, exit codes, ownership |
| Ambiguity / interpretation forks | 4 | precedence and grammar gaps |
| Citations / cross-file | 22 | 10 meaning-bearing, 12 wording |
| Dead verification paths | 11 | gate-blocked and observable-less arms |
| Testability | 18 | unsatisfiable or unpinned fixtures |
| Glossary / drift | 20 | retired terms only in titles and glosses |
| Inline decision-domain gaps | none | the §7 gap check stands (13 rows) |
| Rendered-content safety | none | no secret, hostname, or path leaks |
| Altitude (REQ-H1.3) | pass | D-1 present, cited from the goal; tasks match |

Altitude check: D-1 (the messaging-as-signal boundary) is cited from the
goal restatement in §2 and from REQ-D1.4/REQ-G1.1; the eight tasks add
mechanism under that decision and none re-opens it.

Root causes, grouped by the decision they need. Finding ids: Co = contract,
Ci = citations, Ve = verification, Gl = glossary.

**Needs human judgment (three).**

- T1 Task 7's capstone and the gate (Co C-7/C-8, Ve A3/A4/B14). The
  runner's "notice wakes the tower" step and the duty-cycle figure both
  need the event-driven loop that Task 6 holds behind the Deferred gate,
  so Task 7 cannot pass while the gate holds. REQ-D1.7's "iteration that
  consumes a notice" criterion and REQ-E1.1's loop-reads half are the same
  case. Options: gate those arms with Task 6 (the pre-gate runner passes
  when the metronome tower acts on the park), or make Task 7 depend on
  the gate outright.
- T2 The tower guard vs the two prose tower launches (Ve B6). The
  worktree seam is approved wholesale, but the meta-tower's subordinate
  and the continue-as-new handover are prose Bash strings, and the guard
  defers any `--settings`. Options: a thin launch script for those two
  launches (Task 4), an accepted operator prompt on each, or teaching the
  guard the fleet profile path.
- T3 `/orchestrate`'s instruction budget (Ci F1/F9, Ve B1). The closure
  margin is 1009 words against an unsuppressible floor of 1000, and the
  skill file's margin is 253 against a floor of 250: any growth trips a
  new floor-breach warning, and Task 8's Done-when requires the warning
  set unchanged. Tasks 1, 5, 6, 8 all add `/orchestrate` prose; Task 5
  carries no `check:instructions` clause. Options: Task 1 ships an
  `/orchestrate` diet before the growth, or Task 8 carries an accepted
  floor-breach carve-out, or the diet is Task 8's own deliverable.

**Needs sign-off (one recommended fix each).**

- T4 Message id provenance (Co C-1/C-14/C-23). `send` mints the id
  itself and writes it into the frame beside the reply address; prints it
  for every written post, held included; posts no auth line (E2b).
- T5 The `.meta` sibling (Co C-2, Ci F4, Gl F8). One `answers/<worker>.meta`
  holding one record per fork instance id; a second fork adds a record;
  `redeliver` refuses an id whose fork is not the artifact's current fork;
  gloss "fork instance id" once in the live text.
- T6 Demotion arithmetic and bounds (Co C-3/C-4/C-15/C-16, Ve B3/B4,
  Ci F6). `reconcile_every = max(1, round(300 / cadence))`, preserved to
  within one demoted interval; drop the `--max-age` refusal clause (the
  ≤900 bound already keeps the liveness stamp alive); the timer cadence is
  the healing cadence only where REQ-E1.1's trigger holds; "a live
  subscription" is that trigger's recorded `inbox` proxy.
- T7 Registry readers (Co C-5, Ve B8, Ci F3/F17). Only `fleet-status.sh`
  parses the registry today (the dashboard consumes its merged output,
  cleanup reads none); the reader set is re-derived by grep at Task 4 and
  the fixture asserts tolerance of three-, seven-, and nine-column rows.
- T8 The tower's name (Co C-6). `self-register` writes nothing for a
  tower; the `--watch` loop records the marker at loop start with a name
  read by a new `fleet-messaging.sh self-name` verb (D-12, Task 2).
- T9 Two-outcome arms (Co C-9, Ve A7/A10). The scheduled-wakeup arm and
  the held-then-released arm get the "either outcome recorded" shape; the
  wakeup probe moves to Task 2's session-driven half; held-release is a
  sixth wire-step behavior.
- T10 Eligibility conjunct on `send` (Co C-10). Drop it from Task 5 and
  from REQ-E1.1's trigger: a recorded `inbox` already means a bound inbox.
- T11 The stream-json rung (Co C-11, Ve A2, Ci F2). The fork is still
  claimed and the answer persisted before the control response; the tower
  obtains the full request id from `fleet-streamjson.sh status`, not from
  a decide-row field that does not exist.
- T12 Status-frame turns (Co C-12/C-13). Drop, expiry, or refused frames
  run `redeliver` first; held frames run the step's own action; a refused
  frame after an accepted outcome drives the one fallback delivery.
- T13 The `off` value (Co C-17, Co A-4). At `off` no model-composed
  message is sent in any direction; an unknown knob value reads absent.
- T14 Task 3 vs Task 4 ownership (Co C-18, Ci F10). Requirements and D-19
  name Task 4 for the live check and the migration; Task 3 also rewrites
  the tower profile's `_about` (both routes, dead-hook note).
- T15 The initial pin (Co C-19). Keep 2.1.259 and say "the highest version
  observed in a tower session"; add the 2.1.261 worker to Sources.
- T16 Mid-turn suspension (Co C-20). State the mechanism: a stale
  heartbeat past the liveness max-age, never an attention row.
- T17 Where the demotion notice lives (Co C-21). `effective-mode`, not
  `send`, in Task 2's Done-when.
- T18 Audit and citation bounds (Co C-22/C-25, Ve B17). The drift guard
  lives under `tests/`; Task 7 states the audit passes with
  `fleet-smoke.sh` in the tree; header citations are the six named
  scripts.
- T19 "Never in CI" (Co C-24). The live circuit never runs in CI; the
  dry-run mode runs in the shell suite.
- T20 Ambiguity rules (Co C-26/C-27, Co A-1/A-2/A-3, Ve B9). Last record
  wins for `amend` and `--to-worker`; registry columns hold bare values and
  the registry write grammar is the narrowest screen (a failing name keeps
  the sentinel); `PLANWRIGHT_MESSAGING_INBOUND` stands for the `--settings`
  layer and outranks the files (mixed-case fixture); wake-source order is
  `notice-read`, `redeliver`, reconcile sweep, step action, with the
  subscribe pass first on a tower's first turn; "once Task 7 has landed".
- T21 Contradictory rung list (Co C-28). Test-spec C1.1's three-step
  ladder is for `tmux`; the two-step clause stands for stream-json.
- T22 Comparands (Ve B2/B13). The frozen-comparand fixture store carries
  no answered-undelivered case; each comparand task records its base SHA
  in a one-line fixture file the test reads.
- T23 JSON parse contract (Ve B5). awk-based, no jq (REQ-K1.5);
  `crossSessionInbound` is a top-level settings key; a parse failure reads
  absent.
- T24 Exit code 4 (Ve B7). Keeps today's meaning and both sub-cases; Task 5
  gates the sub-case messages.
- T25 Verification-arm gaps (Ve A5/A6/A8/A9/A11/B11/B12/B16/B18). Scope
  the notice-line re-read to Tasks 2 and 6 then the runner; the `tmux`
  `--settings` arm's observable is the unattended acceptance itself;
  collisions: CLI refusal surfaces, duplicates are recorded from the
  listing; the runner's five observables named (park row, post-log entry
  within a pinned window, heartbeat row) and the window pinned; H1.2 bound
  to the two script send paths; presence dropped from H1.4's manual
  criterion; Task 5 records the platform-guarantee review; the usage gate
  verb is `rung` and the listing assertion excludes `usage/`; the `tmux`
  arm is the control for the headless negative branch.
- T26 The Deferred gate atom (Ci F5). bootstrap is Done; "spec bootstrap
  ready" is true only in a transient window. Replace with a free-text gate
  naming the D-38 amendment's sign-off.

**Expression-only (apply as a block).** Gl F1–F3, F5–F7, F9–F20 (titles of
D-8 and D-16, "five behaviors", R4 legend, D-38's home, the sweep-names
sentence, D-13's nine contents, "paste" in rung-generic sentences,
annotation order and placement, backticks, "capability contract",
"messaging eligibility", "the sanction sentence", "Session-grade column",
"doorbell" negations); Gl F4 as a new 2026-09-07 changelog entry (option
a); Co C-29–C-33; Ve A1 (`caps`, not `caps_for`), B10 and Ci F8 ("a
different screen"), B15 (the guard lives in the script); Ci F7 (D-9 in
Task 7's citations), F11 (obs consumed-elsewhere group), F12 (REQ-C1.5's
annotation), F13, F14, F15, F16 (`name` column), F18 (the third wakeup arm
is a watchdog-launched interactive tower), F19, F20 (planwright's own
screen), F21 (REQ-D1.6 in Task 2's citations), F22 (the `-` sentinel).
Co C-34 and the brief's stale H12 note: corrected in the brief only.

Dispositions: recorded below.

### Terminal lens dispositions (2026-09-07, operator picklist)

- T1: gate only the notice arms. The runner's circuit passes before the
  gate when the metronome tower acts on the park; the notice-wake step,
  the duty-cycle figure, REQ-D1.7's notice-consumption criterion, and
  REQ-E1.1's loop-reads half join the Deferred entry's gated set (the
  entry names them).
- T2: a thin launch script. `scripts/fleet-tower-launch.sh` (Task 4)
  wraps the meta-tower's subordinate launch and the continue-as-new
  handover so the tower command-guard approves them wholesale, the same
  shape as `fleet-dispatch-worktree.sh`; it passes `--settings` with the
  tower profile and exports `PLANWRIGHT_MESSAGING_INBOUND=accept`. D-19
  amended; Task 4 gains the deliverable and a fixture; REQ-B1.1 names it.
- T3: Task 1 ships the diet first. Task 1 measures both `/orchestrate`
  margins (closure 1009 against floor 1000; skill file 253 against 250),
  trims `/orchestrate` to restore headroom for the growth Tasks 1, 5, 6,
  and 8 plan, and records a per-task word allotment in its PR; its effort
  becomes 2 days. Task 5 gains the `check:instructions` clause.
- T4–T26 and the expression-only block: apply all as recorded above.
  Declined: none. Deferred: none.

Pinned wording for the applied edits (both editing agents use these):

- New verb `fleet-messaging.sh self-name`: prints the session's observed
  name from `~/.claude/sessions/$CLAUDE_PID.json`, exit non-zero when the
  record is absent or carries no name; `self-register` calls it.
- Message id: minted by `send` (a UUID), written into the frame beside the
  reply address, printed on stdout for every post that was written
  (accepted or held); no auth line is posted.
- `.meta` sibling: `<fleet-home>/attention/answers/<worker>.meta`, one
  line per fork instance id (the attention store's fork discriminator):
  `<instance>\t<message id>\t<epoch>`; `redeliver` refuses an id whose
  fork is not the artifact's current fork.
- Recompute: `reconcile_every = max(1, round(300 / cadence))`; the deep
  reconcile period is at least the pre-demotion period and within one
  demoted interval of it.
- Registry readers: "the scripts that parse the registry file, re-derived
  by grep at Task 4 (today `fleet-status.sh`), plus the readers this bundle
  adds"; rows of three, seven, and nine columns.
- Free-text gate, written after the bold `Gate:` label with no
  `GATE(` wrapper: bootstrap's D-38 amendment (the `--watch` loop
  event-driven under tmux) is signed off.
- Runner observables: park = the worker's `awaiting-input` attention row;
  notice/answer = the tower's answer post in the post log within 120 s of
  the park row (the runner's own threshold); resume = the worker's next
  heartbeat row after the answer.
- Comparand base: each comparand-shipping task records its base SHA in a
  one-line file under `tests/fixtures/`, one per comparand; the content
  still comes from `git show <sha>:<file>`.
- Wake-source order: `notice-read`, then `redeliver`, then the reconcile
  sweep, then the step's own first action; the subscribe pass precedes all
  of them on a tower's first turn.
- Sweep names: the healing sweep is `fleet-attention-watch.sh watch`'s
  level-triggered pass; the reconcile sweep is `/orchestrate`'s tower step
  that rebuilds in-flight state from disk; `fleet-attention-watch.sh
  reconcile` is that script's own deep-reconcile verb.
- Changelog: a new `2026-09-07` entry carries the sections 4–5 walk (moved
  out of the 2026-09-04 entry) and the terminal-lens edits; the `R4`
  legend reads "section-4 sanity check and section-5 walk (2026-09-07)".

**Application and cross-check (2026-09-07).** Two Opus agents applied the
edits (requirements + design; tasks + test-spec), each reporting every
finding applied and none declined on merit; the kickoff added the `off`
clause to D-4 the first agent flagged. A third, read-only Opus agent then
checked the pinned wording across all four files and found seven
disagreements, all fixed by the kickoff: `self-name` named as the
marker's source in test-spec REQ-B1.2; the minted id, frame write, and
no-auth-line assertions added to test-spec REQ-C1.5; "fork instance id"
glossed in tasks and test-spec; the recompute formula given its design
home in D-16; test-spec REQ-D1.8's gated set narrowed to the three-wake
arm and the source audits (the relaunch subscribe pass is ungated, as
tasks.md says); D-4 and D-16 added to the changelog's amended-in-place
list; REQ-E1.2 added to Task 1's citations. Wording drift the check
noted was unified ("notice-consumption"; the held-release wire-step arm
carries the either-outcome shape everywhere; "delivered artifact" in the
changelog). Left as history: two 2026-09-04 annotations that name the
retired read-back, which the 2026-09-07 annotations below them retire.
After the fixes: validator 0/0, the Deferred entry classifies as a
free-text gate, `lint:md` clean, no body line over 80 characters.

### Sign-off record (2026-09-07, first activation, resumed)

Mode: first activation, resumed after the 2026-09-02 halt-for-revision.
Sections 2–7 signed (section 2 on 2026-09-02; sections 3–7 on 2026-09-07
after the revision delta walk). The terminal lens pass above covers the
full bundle; every finding is dispositioned (applied; declined none;
deferred none). Pre-flip checks: validator 0 errors / 0 warnings on the
Ready bundle; `mise run lint:md` clean over the brief and the four files;
recorded claims re-derived (8 tasks, efforts 15 with critical path
1 → 2 → 4 → 5 → 7 at 11 from `scripts/spec-graph.sh`; 35 test-spec
entries for 35 live requirements; 13 risk rows). Status flipped
Draft → Ready on all four files with `Last reviewed: 2026-09-07`.
Operator approval recorded at the approval summary (decision log seq 77).

Class: meaning
Lens-pass: Terminal lens pass (2026-09-07) — full bundle, sign-off step 1
Anchor: `c192280a9ff3b9ded2f8e6c0d4e5b6aef2922102` — computed as
`scripts/spec-anchor.sh specs/fleet-messaging`
