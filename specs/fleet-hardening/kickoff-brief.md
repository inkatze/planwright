# Fleet Hardening — Kickoff Brief

<!-- The durable contract between human and agent (spec-format, D-3). Downstream
     skills (/execute-task, /orchestrate) operate from this brief, not by
     re-reading the spec. Written incrementally, one section to disk as it is
     signed off. -->

## 1. Header block

- **Spec path:** `specs/fleet-hardening`
- **Spec commit at walkthrough start:** `f3f1d65` (draft), merged up to `origin/main`
  during the walkthrough → HEAD `f93fc3e`. The merge (#232, instruction-hygiene headroom
  policy) touched only `doctrine/instruction-hygiene.md`; none of the four spec files
  changed, so the content anchor is unaffected. No observation seeds were missed.
- **Walkthrough date:** 2026-07-19
- **Mode:** first activation (Status Draft, no prior signed brief)
- **Validator outcome (pre-flight):** `spec-validate specs/fleet-hardening` → 0 errors, 0 warnings
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true` (both defaults; no local override)
- **Working location:** spec worktree `.claude/worktrees/fleet-hardening`, branch
  `planwright/fleet-hardening/spec`, clean.

<!-- Header written first; no sign-off needed. -->

## 2. Goal & glossary

**Restatement.** `fleet-autonomy` (Done) moved fleet housekeeping onto hooks and heartbeats, but a
set of the tower's **control-plane signals** are still resolved by fragile means: heuristic pane
screen-scraping, TUI menu-position counting, timing/polling, silent-glob permission rules, and a
stochastic permission classifier. This bundle replaces each with a deterministic, event-driven
equivalent — a native `Notification` hook for fork-park attention (the anchor gap that cost seven
hours), a codified fallback pane detector, a structured decision channel answered by label, a
code-path ghost-text pin through an auto-approved launch shape, correct-glob allow-rule discipline
plus a check, deterministic D-36 branch naming in the dispatch primitive, a tested allow layer
fronting the tower's own permission classifier, and fetch-before-gate freshness/merge detection —
plus one carried doctrine statement (D-1, the altitude record) generalizing the principle.

**Rules out:** no LLM in any routine control-plane decision (carried `fleet-autonomy` D-18); no
re-opening auto-merge or autonomous PR-ready beyond the sanctioned kickoff exception; no
redefinition of `fleet-autonomy`'s shipped attention store / five-state classifier / already-wired
hooks (extends them); no second-multiplexer adapter.

**Assumes:** `fleet-autonomy`'s attention store, classifier, and `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION`
env-var (D-10) exist and are authoritative; `worker-permission-ergonomics`' `worker-command-guard.sh`
+ literal-path resolution (Done, v0.23.0, #236/#237) exist and are the reuse substrate for the tower
guard and the ghost-text auto-approve.

**Glossary (terms new / load-bearing to this bundle; all shared vocabulary — attention store,
awaiting-human, buffer-paste relay, content anchor, freshness gate, safe set, D-36, D-37, the
five-state / `working` / `hung` vocabulary — is defined in sibling specs and not re-pinned here):**

- **Control-plane signal** — one of the five mechanisms in the Goal: worker-needs-attention,
  decision-needs-answer, `main`-advanced, PR-merged, command-permitted. The bundle's unit of scope.
- **Fork-park** — a worker stopped mid-turn at an `AskUserQuestion` decision fork awaiting human
  input: not "stopped" (turn hasn't ended → no `Stop` hook) and not a tool-permission prompt (→ no
  `PermissionRequest` hook). The exact state that fired `Notification` with nothing wired to catch it.
- **Anchor gap** — the specific unwired `Notification` hook that made the 7-hour fork-park invisible.
- **Reconcile backstop** — the fallback pane detector (D-3) runs only where no hook can register;
  push-first, reconcile-second (carrying `fleet-autonomy` D-1's pattern).

**Platform-contract assumption (surfaced, routed to risk register, not blocking):** the bundle's
headline mechanism (D-2) rests on Claude Code's `Notification` hook actually firing for the
fork-park / idle-wait state. D-2 flags this as a version-sensitive research trigger and Task 2 defers
the confirmation to execution — the right place. Recorded as risk-register row 1.

Signed off: 2026-07-19

## 3. Requirements walkthrough

Five REQ groups (A–E), REQ tally per `requirements.md`. Per-group outcome:

- **REQ-A (attention & decision signals).** Intent confirmed: push-first attention via the
  `Notification` hook (A1.1), event-watch not pane-poll (A1.2), a footer-only/positive-anchor/debounced
  fallback detector as reconcile backstop (A1.3), a structured fork-decision channel answered by label
  (A1.4), delivered downward via the attributed buffer-paste path never `send-keys` (A1.5). **Edge
  noted → risk register:** the `Notification` hook can fire for reasons other than a fork-park
  (permission-park, idle nudge). A1.1's "carrying a reason" field plus A1.4's fork-only channel scope
  already bound this correctly (a permission-park is still legitimately `awaiting-human`; only the
  decision *channel* is fork-scoped), but Task 2 must record the notification reason so the tower can
  tell fork-park from permission-park. Recorded as risk-register row 2, not a spec edit.
- **REQ-B (dispatch hardening).** Intent confirmed: code-path ghost-text pin (B1.1) through an
  auto-approved launch shape (B1.2), correct-glob allow-rule discipline + mechanical check (B1.3),
  deterministic D-36 branch naming in the dispatch primitive (B1.4). **Spec edit applied (see below).**
- **REQ-C (tower self-governance).** Intent confirmed: a distinct tower safe set fronting the
  stochastic classifier (C1.1), allow-only with a deny block for every dangerous op regardless of
  guard output (C1.2), an adversarial suite asserting zero false-allows and outcome-not-precedence
  (C1.3). Coherent and well-bounded.
- **REQ-D (freshness & propagation).** Intent confirmed: fetch-before-gate against `origin/main`
  without advancing local `main` (D1.1), fetch-based merge detection (D1.2), a sanctioned
  tower-observation-to-`main` carry path (D1.3). Routing of D1.3 resolved to *stays here* (see §4).
- **REQ-E (carried floors & doctrine).** Intent confirmed: the control-plane doctrine statement as the
  D-1 altitude record (E1.1), no-redefinition (E1.2), no-LLM-control-plane (E1.3), no auto-merge /
  autonomous-ready beyond the kickoff exception (E1.4). All four carried correctly.

**Consolidated spec-edit list (applied in place on the Draft).** The first edit came from the
requirements/task-graph walk; the rest were dispositioned from the §8 lens pass (recorded here per
the brief structure, detailed in §8). Every applied edit kept the validator at 0/0 and full
REQ→task coverage.

1. **Added Task 10 — Deterministic D-36 branch naming in the tmux dispatch primitive** (cites D-7 ·
   REQ-B1.4). REQ-B1.4 + D-7 had a requirement, design, and test but **no implementing task** — the
   validator checks REQ→test but not REQ→task coverage, so it passed 0/0 despite the gap. Verified
   three ways; intro prose + task count (nine → ten) updated.
2. **Anchor-gap contradiction fixed** (REQ-A1.1 / REQ-A1.3 / D-2 / D-3 / Task 2 / Task 3 / test-spec):
   D-2 delegated the registered-but-non-firing-hook case to D-3, but D-3 was scoped "hookless
   backends only", leaving the exact 7-hour fork-park state uncovered. Widened the detector's gating
   to "no hook, OR a registered hook that hasn't pushed within a bounded reconcile interval"; made
   REQ-A1.1 conditional on fork types that raise `Notification`.
3. **Tower-guard security hardening (full — your Q1 call)** (REQ-C1.2 / REQ-C1.3 / D-8 / Task 7 /
   test-spec): the allow-only guard had no default-deny and a shell-string-only deny block. Extended
   the required deny surface to the GitHub **MCP** merge/ready/push tools, **direct default-branch
   writes**, **local-`main` mutation**, and **all force-push spellings**; **pinned the allow-set**
   against `--dangerously-skip-permissions` / `--permission-mode` and `tmux send-keys`/`kill-session`;
   required the guard to **fail closed**; **reconciled** the never-ready deny with the sanctioned
   kickoff spec-PR flip.
4. **Content-anchor scope-leak reworded** (REQ-D1.1 / D-9 / test-spec): "evaluate the content anchor"
   → "re-point `anchor-integrity`'s *existing* anchor check at `origin/main`"; this bundle does not
   implement anchor-hash comparison.
5. **Verification-ownership dead paths fixed** (Tasks 2–9 Done-whens + test-spec): REQ-E1.3's
   per-mechanism no-LLM assertions (7 of 8 were unowned) assigned to Tasks 2, 3, 4, 5, 6, 8, 9;
   REQ-E1.2 regression assigned to Tasks 2/4 and strengthened against a vacuous pass; D-6 doc-presence
   check added; C1.3 "allow-before-classifier" re-labeled `[design-level]`; A1.1 `[manual]` ownership
   disambiguated; merge-detection degradation test added.
6. **Robustness items bound to Task Done-whens + risk rows (your Q2 call)** — see §7 rows 8–12 and the
   named Task Done-whens: decision-instance id + claim/close + permission-park gate (Task 4);
   event-watch liveness + reconcile sweep + `awaiting-human` exit edge + Notification payload-gating
   (Task 2); transient-fetch degradation + fetch-TTL (Task 8); chore-PR idempotency (Task 9);
   client-switch design + branch-collision handling (Task 10). No new REQs minted.
7. **Consistency / citation / tag nits** (all four files): "seven"→"eight" mechanisms; D-9 →
   `orchestration-fleet` attribution; "the design Goal"→"the Goal (in requirements.md)"; "Two floors"
   vs Task 1 wording aligned; `kickoff-lifecycle` + `observation-recording` Source entries added;
   `[design-level]` tag introduced in the coverage-mix intro; ranking-order wording; Task 4→2
   dependency rationale corrected; `anchor-freshness` reconciliation resolution recorded; one
   data-hygiene edit ("Diego's decision" → "the operator's decision").

Signed off: 2026-07-19

## 4. Design walkthrough

Every D-ID accounted for (D-IDs per `design.md`). Reconciled ledger:

- **D-1 (deliverable altitude — mechanism-primary + one carried doctrine statement)** — **confirmed.**
  The altitude record for the bundle; rationale intact. Verified at sign-off against the
  autopilot-reflex altitude gate (§ sign-off).
- **D-2 (fork-park attention via the native `Notification` hook)** — **confirmed.** The headline
  mechanism; carries the platform-contract research trigger (risk row 1).
- **D-3 (fallback pane detector — footer-only, positive-anchor, debounced)** — **confirmed.**
  Reconcile backstop, never primary.
- **D-4 (structured decision channel, answered by label)** — **confirmed.** Reuses the store's
  `decide` / `awaiting-input` path; preserves the no-`send-keys` relay contract.
- **D-5 (ghost-text pin in the launch primitive, via an auto-approved shape)** — **confirmed.**
- **D-6 (correct-glob allow-rule discipline, documented + guard-checked)** — **confirmed.**
- **D-7 (deterministic D-36 branch naming folded into the tmux dispatch primitive)** — **confirmed;
  now has an implementing task (Task 10) after the §3 edit.** Rationale unchanged; the two caveats
  (`--tmux=classic` mandatory; client-switch mitigation) carried into Task 10's Done-when.
- **D-8 (tower command-guard — distinct tower safe set fronting the classifier)** — **confirmed,
  placement confirmed.** The obs:8eacaa65 (2026-07-18) routing to a `worker-permission-ergonomics`
  amendment is superseded by the 2026-07-19 hardening seed, which places it here. Grounds:
  `worker-permission-ergonomics` is Done/released (amending needs a reopen); this bundle is the
  coherent control-plane home. Newer intent wins; the human holds a standing veto to route it back.
- **D-9 (fetch-before-gate freshness + merge detection, without advancing local `main`)** —
  **confirmed; D1.3 propagation-half placement confirmed here.** `observation-recording` (Done) does
  not own a tower→main carry path and is out-of-scope for one; `observation-routing` (draft) is
  cross-repo, a different axis; REQ-D1.3's intra-repo tower→`main` carry is fleet-domain and stays
  here. Scope boundaries against `anchor-integrity` (anchor-hash freshness) and `release-hardening`
  (release-publish stale-`main` variant) intact.

No design decision contradicts a walked requirement; no inconsistency halt raised.

## 5. Verification approach

Coverage mix per `test-spec.md`: predominantly `[test]` (every mechanism is deterministic script
logic, REQ-E1.3, fixture-testable including the negative assertions — no `capture-pane` on the push
path, no `send-keys` in the decision channel, no `allow` for a deny-listed command, no local-`main`
advance after a fetch). `[manual]` is reserved for the version-sensitive platform-contract
confirmations (`Notification` fires for a real fork-park; the tmux client-switch behavior of the
native launch primitive) and the doctrine statement (`[design-level]`, a design judgment not a
mechanism output).

**Verification ownership:** `[test]` entries run under the project's `mise run check` in CI (the glob
check B1.3 explicitly joins that guard suite). `[manual]` entries are execution-time confirmations the
executing worker records against the running Claude Code version (Task 2's `Notification` confirmation;
Task 10's `--tmux=classic` + client-switch confirmation). `[design-level]` entries (E1.1, and the
design-level halves of E1.2/E1.4) are verified by review, not runtime.

**Dead-path check:** every REQ has at least one verification path AND — after the §3 edit — at least
one implementing task. REQ-B1.4's `[test]` fixture is no longer orphaned (Task 10 now builds what it
asserts). No REQ names a verification that cannot run.

## 6. Task graph

Dependency graph reconstructed from the `Dependencies:` lines in `tasks.md` (authoritative; task
count and effort per that file):

- **Task 1** (control-plane doctrine + carried floors) — the root; every other task depends on it.
- **Tasks 2–10 all depend on Task 1** and nothing else, except **Task 4 → {1, 2}** (the decision
  channel extends the attention-store record Task 2 shapes).
- **Parallelism:** once Task 1 lands, Tasks 2, 3, 5, 6, 7, 8, 9, 10 are all independently dispatchable;
  Task 4 waits on Task 2.
- **Guard-infrastructure-first ordering:** Tasks 6 (glob check), 7 (tower guard), 8 (fetch-before-gate)
  outrank the impact critical path per the guard-first selection rule once Task 1 lands.
- **Effort-weighted critical path:** Task 1 → Task 2 → Task 4 (the only depth-3 chain; Task 7 is the
  single heaviest node at ~3 days but sits at depth 2). Effort figures per `tasks.md`.
- **Deliberate non-edges (recorded so nobody "fixes" them):** Task 3 (fallback detector) does **not**
  depend on Task 2 — it is the reconcile backstop, deliberately independent so a hook-less backend is
  covered even if Task 2's hook path is unavailable. Tasks 5 and 10 both touch the tmux dispatch
  primitive but are **independent** (env-var pin vs branch naming — separate deliverables, separate
  fixtures), a conscious split per the §3 decision, not an oversight.

## 7. Risk register

**Decision-domains gap check.** Catalog resolved via `resolve-catalog.sh decision-domains` (empty
overlay → the 11 core prose-seed domains). All 11 walked. Untouched: caching (2), versioning (11).
Decided-by-reuse (no gap): data storage & modeling (1) and concurrency (7) defer to `fleet-autonomy`'s
attention store and `orchestration-concurrency`'s shared-checkout model; queues/async (3) is
push-first/reconcile-idempotent; auth/authz (5) is the tower guard's core, fully decided (D-8);
secrets/config (6) follows the never-edit-`settings.json` + ship-hook-plus-wiring convention with no
secrets in artifacts; dependency adoption (10) is platform features of an already-adopted dependency,
handled as the D-2/D-7 research triggers. **Touched-but-not-fully-decided → risk rows below:**
observability (8, row 3), API surface / migration (4 + 9, row 4).

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | **Platform-contract (D-2):** Claude Code's `Notification` hook may not fire for every fork-park / idle-wait state on the running version — the bundle's headline mechanism rests on it. | D-2's version-sensitive research trigger, confirmed at Task 2 execution against the running `hooks` docs and a real fork-park. Where a fork type does not raise it, D-3's fallback detector is the reconcile backstop; the retained heartbeat-age `hung` classifier is the final catch. |
| 2 | **Notification over-fires:** the hook fires for non-fork-park reasons too (permission-park, idle nudge), risking a mis-routed attention record. | A1.1's record carries a *reason* field; the decision *channel* (A1.4) is fork-scoped, so a permission-park is still legitimately `awaiting-human` but never enters the answerable channel. Task 2 records the notification reason so the tower distinguishes fork-park from permission-park. |
| 3 | **Observability of the watcher itself (gap-check domain 8):** the new event-driven machinery (Notification hook, store event-watch, fallback detector) could itself fail silently — recreating the exact invisible-park this bundle fixes. | Decided via three-layer defense-in-depth, recorded here to make it explicit: push-first (D-2) → reconcile pane detector (D-3) → retained heartbeat-age `hung` classifier (`fleet-autonomy`) as the final backstop. No single silent failure hides a parked worker. Early signal: a store row aging toward `hung` is the watcher-down tell. |
| 4 | **Attention-store schema evolution (gap-check domains 4 + 9):** the store record is extended with new fields (awaiting-human reason/timestamp; decision option-set + recommendation). A version-skewed fleet (worker and tower on different plugin versions) could drop a field — missing a decision or an event. | Additive fields with older-reader-ignores semantics (no redefinition of the shipped shape, REQ-E1.2). In practice all fleet sessions run the same installed plugin version (single-machine, single-operator fleet), so skew is low-probability. **Accepted risk.** Early signal: a decision record written but never answered. |
| 5 | **Tower-guard blast radius (D-8):** the tower safe set is broader than the worker set (tmux relay/observe, `claude --worktree` launches), consciously re-opening the worker-only-scoping security rationale `worker-permission-ergonomics` chose. | The profile's deny block denies every dangerous op regardless of guard output (C1.2); the adversarial suite asserts zero false-allows and the deny-outcome (C1.3). Task 7 must document the re-opened rationale, not silently widen it. |
| 6 | **Undocumented precedence (obs:4dda9fe1):** Claude Code's allow-vs-deny precedence is not documented for the running version, so the tower guard's safety cannot lean on it. | REQ-C1.3 asserts the *outcome* (the guard never emits `allow` for any deny-listed command) rather than relying on documented precedence — the safety property holds regardless of how the harness resolves allow-vs-deny. |
| 7 | **tmux client-switch (D-7 / Task 10):** the native `claude --worktree … --tmux=classic` launch switches the attached tmux client to the new session, which could disrupt a tower watching another session. | Task 10 now **designs** the mitigation (launch detached, or capture-and-restore the prior attachment), not just a `[manual]` confirmation (row 12). |

Rows 8–12 are the §8 lens-pass robustness findings, dispositioned (your Q2 call) to Task Done-whens
+ these risk rows rather than new REQs:

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 8 | **Decision mis-apply (Task 4):** answers keyed only by label — a late answer for a resolved fork, or a second answerer, can land on the wrong fork (recurring `Skip`/`Apply` labels) or double-deliver. | Each decision record carries a unique **instance id** the answer must match, with **first-answer-wins claim/close** (Task 4 Done-when). Early signal: an answer refused as stale. |
| 9 | **Watcher liveness (Task 2)** — strengthens row 3: a dead event-watch, or a push written before the watch is established, silently re-creates the 7-hour blindness through a new single point of failure. | The watch carries a **liveness check + periodic full-store reconcile sweep**, so a dead watch degrades to poll-latency, not silence (Task 2 Done-when). |
| 10 | **Stuck attention row (Task 2):** the push sets `awaiting-human` over heartbeat, so without an exit edge a resumed worker's row never clears → permanent false attention. | The row is **cleared/superseded on resume** (the exit edge), asserted by a resume-clears-the-row fixture (Task 2 Done-when). |
| 11 | **Freshness degradation + hot fetch (Task 8):** a transient fetch failure against a present remote could silently gate stale; `/orchestrate --watch` would fetch every idle cycle. | Transient-failure handled distinctly from `no-remote` (retry, then block/flag — never silent stale); per-gate fetch **bounded** (TTL / coalesced with the reconcile sweep) (Task 8 Done-when). |
| 12 | **Duplicate carry + branch collision (Tasks 9/10):** repeat/concurrent bookkeeping opens duplicate chore PRs; concurrent dispatch of one task collides on the deterministic D-36 branch. | Carry is **idempotent** (reuse one open PR, dedupe) and concurrency-safe (Task 9); a concurrent/repeat dispatch **detects the existing branch/worktree and aborts as already-in-flight** (Task 10). |

No open questions remain; every surfaced concern is resolved to a decision or recorded as an explicit
accepted risk (row 4) or a Task-bound robustness item (rows 8–12).

## 8. Sign-off

**Lens review pass.** Scope: **full bundle** (first activation). Path: **parallel fan-out** — five
read-only lens sub-agents over the nine canonical Discovery-Rigor lenses (the diff is far beyond a
few hunks; inline would self-prune). Shared context: validator 0/0, the Task-10 edit already applied.
Findings validated against the spec text, deduped, and dispositioned with the human below.

### Canonical lens-coverage table

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 5 | Anchor-gap re-opens (load-bearing contradiction); "design Goal" citation target absent; Task 4→2 dep rationale; content-anchor scope leak; merge-detection had no degradation test |
| Security | 8 | Shell-string-only deny block bypassed by MCP merge/ready/push tools, direct `git push …:main`, local-`main` mutation; allow-set over-matches `--dangerously-skip-permissions`; force-push spellings; permission-park answerable; never-ready-vs-kickoff-flip unreconciled; one data-hygiene nit |
| Error handling & failure modes | 6 | Registered-but-non-firing hook uncovered; push-write failure; transient fetch vs no-remote; guard fail-open/closed undefined; client-switch only manually confirmed |
| Performance | 1 | Fetch-before-gate fires a round-trip every `--watch` idle cycle (no TTL/coalesce) |
| Concurrency / state | 9 | Event-watch liveness; at-least-once/startup race; `awaiting-human` no exit edge; multi-writer atomicity; decision-instance correlation; double-answer; chore-PR idempotency; D-36 branch collision; Notification over-fires |
| Naming, readability, structure | 6 | "seven" vs eight mechanisms; D-9 mis-attribution; "Two floors" vs three; ranking-order claim; tag vocabulary; missing Source entries |
| Documentation | 3 | D-6 doc half unverified; doctrine (E1.1) home self-referential; `kickoff-lifecycle`/`observation-recording` absent from Sources |
| Tests / verification | 5 | REQ-E1.3's 7-of-8 no-LLM assertions unowned (vacuous floor); E1.2 regression unowned; C1.3 "allow-before-classifier" mislabeled `[test]`; A1.1 `[manual]` ownership split |
| Cross-file consistency | 4 | Content-anchor scope leak; D-9 attribution; Task-4 dep; Goal-citation |

**Kickoff altitude check (REQ-H1.3).** Bundle **is** altitude-triggered (control-plane framing + a
mechanism that had acquired doctrine-like rules). Altitude record **D-1 exists**, is cited from the
Goal, and the decomposition matches the claimed altitude (nine mechanism tasks + one doctrine task,
per `tasks.md`). **Pass** — the one nit (citation said "design Goal"; the Goal lives in
`requirements.md`) is folded into the applied edits.

### Dispositions (every finding accounted for)

- **Applied as spec edits** (§3 items 2–7, and the Task-10 gap as item 1): the anchor-gap
  contradiction, the full tower-guard security hardening (human Q1 = full), the content-anchor
  scope-leak wording, the verification-ownership dead-path fixes, and all consistency/citation/tag/doc
  nits including the data-hygiene edit.
- **Bound to Task Done-whens + risk rows** (human Q2 = Task Done-whens + risks; §7 rows 8–12): the
  ~10 failure-mode / concurrency robustness items (decision-instance id + claim/close +
  permission-park gate; event-watch liveness + reconcile sweep + `awaiting-human` exit edge +
  Notification payload-gating; transient-fetch degradation + fetch-TTL; chore-PR idempotency;
  client-switch design + branch-collision). No new REQs minted.
- **Accepted as standing risks** (§7 rows 1–7): the platform-contract confirmation (Task 2), the
  Notification over-fire (now payload-gated in Task 2), the blast-radius widening (deny-block +
  adversarial suite), the undocumented precedence (outcome-asserted), and the schema-skew accepted
  risk (single-version fleet).
- **Declined:** none.

No finding is left undispositioned; no inconsistency halt is open; the bundle re-validates 0/0 with
full REQ→task coverage after every edit.

Class: meaning
Lens-pass: §8 (full-bundle first-activation fan-out, canonical lens-coverage table above, all findings dispositioned)
Anchor: `c6d923cee5adef82b469da024e4ac9c48ab4a002` — computed as
`scripts/spec-anchor.sh specs/fleet-hardening`

## 9. Amendment log

### 2026-07-19 — Panel-review delta (`/panel-review --nested`, iteration 1)

An independent-model panel pass (gemini backend, personal profile) over the merged bundle diff, run
after the first sign-off as a cross-distribution check. It surfaced five real completeness gaps — all
validated three ways, none a false positive, nothing broken (validator 0/0, lint:md 0 throughout).
The notable one (NS-1) was invisible to §8's same-session Claude lens fan-out: that fan-out reviewed
the pre-edit bundle, and the E1.3 asymmetry was *introduced* by §8's own Task 2–9 no-LLM-assertion
edits, so only a fresh post-edit pass could catch it. All five applied (human: apply all 5):

1. **NS-1 — E1.3 no-LLM coverage made symmetric.** Task 10 (dispatch branch naming) is the ninth
   mechanism but was omitted from test-spec REQ-E1.3's enumeration and lacked the no-LLM assertion +
   E1.3 citation Tasks 2–9 carry; Task 7 referenced E1.3 in its Done-when without citing it.
   → REQ-E1.3 enumeration 8 → 9 (adds branch naming); Task 10 gains the assertion + `REQ-E1.3`
   citation; Task 7 gains the `REQ-E1.3` citation.
2. **NS-2 — deny surface completed.** REQ-C1.2 (c)'s MCP deny list omitted the sibling destructive
   op `mcp__github__delete_file` (a default-branch write). → added to REQ-C1.2, Task 7 Done-when, and
   test-spec REQ-C1.2. Consistent with the Q1 full-hardening decision.
3. **NS-3 — negative test added.** REQ-A1.3's positive-at-prompt-anchor requirement had no fixture
   for its own negation. → added a fifth A1.3 fixture (no anchor → NOT idle, so a starting-up worker
   is never misread as idle-at-fork).
4. **NS-4 — terminal-clear clarified.** Task 2's `awaiting-human` exit edge covered resume but not a
   crash/session-end before resume. → clarified that terminal exit clears the row via
   `fleet-autonomy`'s existing SessionEnd / StopFailure transitions (precedence over the push).
5. **NS-5 — cosmetic.** REQ-D1.2's citation date was orphaned outside the italic. → moved inside.

Gemini's Security and Performance lenses returned `none`, independently re-confirming the §8 security
hardening ("meticulously defined, fails closed, deny-blocks have precedence") and the TTL/debounce
bounding. The nested loop then exited (Auto-applicable empty — no finding was project-tool-grounded,
so none auto-applied; all five routed to human sign-off, applied here on approval).

Class: meaning
Lens-pass: §9 (panel-review delta, gemini backend; five findings, all applied)
Anchor: `fb32fc83acb0e87d3e61ab4c66bfc37303e1b460` — computed as
`scripts/spec-anchor.sh specs/fleet-hardening`

### 2026-07-20 — Amendment (`/spec-kickoff`, meaning-class): D-7 / Task 10 dispatch-primitive mechanism

Human-declared amendment on the Active bundle: the tmux dispatch primitive's worktree-creation
mechanism. The prior D-7 mechanism (pure-native `claude --worktree <suffix> --tmux=classic` as a
single fold "satisfying D-37") was found **unrealizable** — confirmed three ways (the `claude
--worktree` contract, the running CLI 2.1.215, and the recurring tmux-dispatch-branch-rename
operational evidence): `claude --worktree <name>` always names the branch `worktree-<name>`, never the
slashed D-36 `planwright/<spec>/task-<id>`, and of {deterministic D-36 name, no rename,
no-shell-`git worktree`} only two hold at once. The task-10 executor had already halted on this exact
contract-drift; the human chose the **narrow D-37 exception** direction.

**Applied (D-7, Task 10, test-spec REQ-B1.4; REQ-B1.4 itself unchanged — the new mechanism still
satisfies it):** create-then-attach — `git worktree add -b planwright/<spec>/task-<id>
.claude/worktrees/<suffix> <base>` creates the exact D-36 branch (a narrow, documented
never-shell-`git worktree` exception scoped to this one dispatch primitive), then
`claude --worktree <suffix> --tmux=classic` discovers/attaches (grounded in `docs/conventions.md`'s
"any worktree placed there is attachable … regardless of which backend created it"). Task 10's
unrealizable no-shell + no-rename framing dropped.

**D-37 boundary (human: document in D-7 + observe).** D-37 lives in the sibling `bootstrap` bundle
(`design.md:595`), and `docs/conventions.md:103-105` carries the same never-shell rule; both are
already aspirational (kickoff's own spec-worktree creation shells out too). The scoped exception is
documented in D-7; reconciling the repo-wide invariant is delegated to core via an observation
(`d37-slashed-branch-shell-exception`, tying to the 2026-06-16 opportunity `opportunities.md:68`).

**Lens pass (delta-scoped, parallel fan-out — four read-only sub-agents over the delta).** Findings
dispositioned with the human. *Mechanism soundness (apply all):* `<base>` pinned to fetched
`origin/main`; interpolated `<spec>`/`<id>`/`<suffix>` validated (or argv) against
injection/traversal; collision detection via `git worktree add -b`'s atomic non-zero exit (no TOCTOU)
with the create exit-code gating the attach; tower-guard (D-8) reconciliation (the `git worktree add`
runs inside the literal-path dispatch primitive; the deny floor names the dangerous forms); test-spec
collision coverage + the client-switch [test]/[manual] contradiction resolved. *Broader robustness
(fully specify):* live-vs-stale orphan reconcile — a dead branch/worktree, empty leftover dir, or
partial create is GC-adopted / rolled back rather than wedging the task permanently already-in-flight;
`<suffix>` determinism. *My own guard bug (fixed):* the guard's "no other path shells out" was
self-contradictory (kickoff shells out too) — rescoped to this bundle's dispatch code, at the task's
altitude. Task 10 effort 1 → 2–3 days. *Out of scope:* the pre-existing 8-vs-9 mechanism count →
observation `fleet-hardening-mechanism-count-8-vs-9`; the 2026-07-19 obs:4e24463c Sources note left as
a dated audit record.

Lens-coverage: correctness 4 · security 2 · error-handling 3 · performance n/a · concurrency 2 ·
naming 1 · documentation 2 · tests 4 · cross-file 1. Altitude check (REQ-H1.3): the delta is
mechanism-level; no altitude trigger fired; not applicable.

Class: meaning
Lens-pass: §9 (delta-scoped fan-out, four sub-agents; mechanism-soundness + broader-robustness
applied, one guard bug fixed, one pre-existing item deferred to an observation)
Anchor: `6c1f836ddbdec1db3bd8ebbe121139fc5e71a0fa` — computed as
`scripts/spec-anchor.sh specs/fleet-hardening`

### Re-anchor — anchor-scope exclusion sweep (2026-08-24)

Machine-written entry per the meta-spec's expression-only lane
(`doctrine/spec-format.md`, *Writers*), recorded by the coordinated sweep
that lands with the hash-scope change (anchor-integrity D-3, REQ-A1.4).

**Why the anchor moved:** the hash scope changed, not this bundle's
content. The per-file digests for `requirements.md`, `design.md`, and
`test-spec.md` now drop the header-block `**Status:**` line, so every
bundle carrying one recomputes to a new value. Verified by isolation:
recomputing under the amended semantics over this bundle as it stood at the
prior entry's commit (`5c2245a`) yields the same hash recorded below, so no
anchored byte has changed since that entry was written.

**Cites the changelog line:** the 2026-07-26 `## Changelog` entry in
`doctrine/spec-format.md` ("Anchor-scope exclusion"), the doctrine half of
the change this entry re-anchors against.

Class: expression-only
Anchor: `f5aab2529be51c1db424250eecde2d4ad070fdaf` — computed as
`scripts/spec-anchor.sh specs/fleet-hardening`

### Re-anchor — foreign citations qualified (2026-09-03)

Marked self-re-anchor for the expression-only edit the format-grammar
validator's citation-range rule (format-grammar REQ-D1.3, D-13) surfaced on
its all-bundle rollout run (format-grammar D-9, REQ-D1.10): the bare `D-36`
tokens in REQ-B1.4, the `## Sources` tmux note, the `tasks.md` intro and
Task 10 deliverables, and the REQ-B1.4 test-spec entry now read `bootstrap
D-36`; the `## Awaiting input` placeholder in `tasks.md` became the plain
`(none yet)` form (format-grammar REQ-D1.1), outside the anchor. Each
qualified id now carries its owning spec's name within the reader's reach
(the same line, bullet, or block, the scope the rule reads); no requirement
or decision changes meaning. `Last reviewed:` moves on the edited files.

**Cites the changelog line:** the 2026-09-03 `## Changelog` entry in
`requirements.md`.

Class: expression-only
Anchor: `6d5cec7e4c143f8e9bfc0a767d1e0f325910210c` — computed as
`scripts/spec-anchor.sh specs/fleet-hardening`

### 2026-10-04 — Extension delta kickoff (`/spec-kickoff`, reopened bundle): detached tmux launch

**Header.**

- **Spec path:** `specs/fleet-hardening`
- **Spec commit at walkthrough start:** `7c9e5fe` (the `/spec-draft --extend` commit that reopened
  the bundle to Draft on all four headers)
- **Walkthrough date:** 2026-10-04
- **Mode:** reopened-bundle delta kickoff (Status Draft with a complete signed brief). Delta: the
  2026-10-04 extension as recorded in `requirements.md`'s `## Changelog`; everything outside it
  stands as signed above.
- **Validator outcome (pre-flight):** `spec-validate specs/fleet-hardening` → 0 errors, 0 warnings
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true`,
  `kickoff_ready_ci_wait: 10m` (defaults; no local override)
- **Working location:** spec worktree `.claude/worktrees/fleet-hardening-spec`, branch
  `planwright/fleet-hardening/spec`, clean.
- **Decision/transcript log:** no harness-provided log in this session; the turn mirror is skipped.

**Goal & glossary (delta).**

*Restatement.* Today a tmux-rung dispatch hands off to Claude Code's own launcher, which inside
tmux never comes back: it builds the worker's session, pulls the operator's tmux client onto it, and
keeps running for the worker's whole life. The dispatch therefore holds the checkout's flight lock
until the worker exits, never prints its report, and reads as a failed launch if anything kills it,
which invites a duplicate dispatch. The worker it starts inherits the tmux server's environment, so
neither the ghost-text pin nor a worker identity reaches it, and its launcher can resolve a second
worktree of its own. The extension has the dispatch create the worker's tmux session itself,
detached, in the worktree it already placed, with the environment built inside that session, and
return as soon as the worker proves it started. Because that is shell and path construction fed by
repository-derived values, its safety properties are requirements: values tmux would expand are
allowlisted, every live launch passes one containment guard, session names are unique per checkout
and checked before anything durable is written, the worker CLI is resolved fail-closed, and the
death handle comes from the session-creation call. Fixtures that cannot hang and can actually fail,
plus doc and seam-discovery cleanup, close it out. The altitude stays mechanism-primary.

*Rules out.* Removing the operator's hand-typed `claude --worktree` launch (it stays allowed, only
relabelled); splitting `tests/test-flight-dispatch.sh`; the macOS canonicalization that
`test-throughput` owns; a tmux rung for checkouts whose physical path falls outside the charset
(refused there, other rungs unaffected); any second multiplexer.

*Assumes.* The tmux 3.6 expansion behavior probed in Sources holds on the versions adopters run (no
tmux floor is declared); Claude Code fires `SessionStart` for a worker launched this way; the
identity-gate grammar the liveness hooks already enforce is the grammar the wrapper validates.

*Implicit terms surfaced.*

- **Started / failed / started-unconfirmed:** the three launch outcomes; only the worker's own
  startup confirmation counts as started.
- **Physical path:** the `pwd -P` form, symlinks resolved.
- **Death handle:** the session name and window id the registry records so death evidence can probe
  the right session.
- **Prior launcher's spelling:** `<repo-basename>_worktree-<suffix'>`, the session name the native
  launcher actually creates (per the tmux probe), kept live-probed through the upgrade window.
- **The parked flight:** the visual flight for issue #546 whose candidate commit, zone finding, and
  review findings seed this extension.
- **`<hash6>`:** see resolutions.

*Resolutions.*

- **`<hash6>` rendering.** "First six digits of the `cksum` CRC rendered in lowercase hex" read two
  ways (unpadded hex can be shorter than six digits). Resolved mechanically for determinism: render
  the CRC as eight zero-padded lowercase hex digits (`printf '%08x'`) and take the first six. Spec
  edit queued (consolidated list).
- **What "started" means before the confirmation task lands** (operator decision). The detached
  launch ships one task ahead of the startup confirmation. In that window a created session is
  reported started-unconfirmed, never started, and every shipped caller treats it as placed; the
  confirmation task later adds the started and failed-at-startup outcomes. Chosen over merging the
  two tasks and over leaving the gap as a risk, because the bundle defines "started" as the
  worker's own confirmation.

Signed off: 2026-10-04

**Requirements walkthrough (delta).**

- *Launch behavior group.* The dispatch returns once the launch outcome is known, never moves a tmux
  client, starts the worker in the placed worktree with no launcher-side worktree resolution, and
  puts the pin and the worker identity in the worker's own environment. What the operator will
  notice: the dispatch report comes back, the tmux view stays put, and tmux workers start raising
  the same attention signals (fork-park pushes, status rows) headless workers already do, since
  they now carry an identity. Outcome: confirmed.
- *Launch safety group.* Charset allowlist on everything tmux expands, physical start directory
  that must exist, one containment guard for every live launch, repo-qualified names checked
  before any durable write with failure arms that never touch a winner's state, fail-closed CLI resolution, startup
  confirmation, death handle from session creation, and liveness probes across the upgrade window.
  Outcome: confirmed with two gap-fills (edits 2 and 3 below).
- *Verification and docs group.* Bounded fixtures, a stub server environment distinct from the
  dispatcher's, a fixture per refusal arm that fails with the arm removed, canonical path compares
  with race-free self-reaping stubs, a mechanical check against the old launch shape in prose, and
  a seam-discovery exemption narrowed to the tower relaunch. Outcome: confirmed.

*Consolidated spec-edit list (all applied in place; the bundle is Draft):*

1. `design.md` D-14: `<hash6>` rendered as eight zero-padded hex digits, first six taken.
2. `requirements.md` REQ-G1.4: the side-effect list gains "branch", matching D-14 and the test-spec
   entry.
3. `design.md` D-14, `tasks.md` Task 12 (deliverables and done-when) and the gated deferral,
   `test-spec.md` REQ-G1.7: the removed probes are the bare `<suffix>` and `worktree-<suffix>` forms
   and their alternate-name forms, not only `worktree-<suffix>`. The current probe in
   `scripts/fleet-dispatch-worktree.sh` checks both bare forms, and neither is a name any launch
   creates, so REQ-G1.7's own rule removes both; the new-name and prior-spelling probes cover the
   alternate name too.
4. `tasks.md` Task 12: the interim started-unconfirmed reporting (operator decision above), and
   REQ-G1.5 added to its citations, since it ships that requirement's CLI-resolution half.
5. `design.md` D-15, `tasks.md` Task 13: the `SessionStart` arm is wired under the `startup`
   matcher, as the plugin's other `SessionStart` hooks in `hooks/hooks.json` are; the
   confirmation is for a fresh launch, and a resumed or cleared session is not a launch.
   *(Reconciled after the lens pass: wired under `startup` and `resume`, because task dispatches
   may forward `--continue` / `--resume`, which would otherwise never confirm.)*

Edits 1–5 are gap-fills consistent with the decisions already recorded (expression-class in
isolation); no agent-authored meaning-class edit was applied mid-walk, so no mid-walk lens pass
ran. The whole extension is meaning-class and takes the terminal lens pass.

Signed off: 2026-10-04

**Design walkthrough (delta).** D-7's attach step is superseded by D-10 (its create step, collision
and orphan handling, exception scope, and tower-guard interaction carry forward unchanged, as the
`Superseded-by:` note on D-7 records). D-10 through D-15 are minted: D-10 confirmed; D-11 confirmed;
D-12 confirmed; D-13 confirmed; D-14 amended (edits 1 and 3); D-15 amended (edit 5). D-1 through
D-6, D-8, and D-9 are untouched by the delta and stand as signed. No design decision contradicts a
walked requirement. *(Reconciled after the lens pass: D-10 through D-15 are all amended per the
lens dispositions below, and D-8 carries a hand-launch annotation.)*

Signed off: 2026-10-04

**Verification approach (delta).** The new entries are predominantly `[test]`, run by the
repository CI under `mise run check`; `[manual]` is confined to the real-dispatch confirmations
(launch returns, client stays, worker environment, `SessionStart` fires), swept by the operator on
Task 12's and Task 13's first real dispatch; the one `[design-level]` arm (each refusal fixture was
run once with its arm removed) is confirmed at PR review from the PR description. The REQ-B1.4
`[manual]` arm moved from the `--tmux=classic` check to the detached launch; REQ-B1.4 itself is
unchanged. Dead-path check: every new entry names a fixture that can run on the Task 11 harness or
the repository itself; none depends on an unavailable platform.

Signed off: 2026-10-04

**Task graph (delta).** From the `Dependencies:` lines in `tasks.md`: Task 11 depends on Task 1
(done); Task 12 on Task 11; Tasks 13 and 14 each on Task 12. Critical path: 11 → 12 → 13 (see the
tasks' effort lines). Task 14 runs beside Task 13. Deliberate non-edges: Task 14 does not wait on
Task 13 (the launch-shape check concerns the old launch's prose, not the confirmation outcomes,
which Task 13 documents in the primitive's own usage header); Task 13 does not run beside Task 12,
because both rewrite the same launch function.

Signed off: 2026-10-04

**Risk register (delta).** Rows continue the numbering of §7 as appended rows; earlier rows are
untouched.

- **E1. Interim window between Tasks 12 and 13.** A release between them reports every created
  session as started-unconfirmed. Mitigation: callers treat it as placed (Task 12 done-when);
  early signal: an unconfirmed report on every tmux dispatch until Task 13 merges, which is
  expected and not a failure.
- **E2. tmux expansion behavior varies by version** and no tmux floor is declared. Mitigation: an
  allowlist (not a denylist), checked before any tmux call; early signal: a charset refusal on a
  path that looks ordinary.
- **E3. `SessionStart` not firing for a launched worker** on some Claude Code version. Mitigation:
  the started-unconfirmed outcome keeps a live worker from being read as dead; early signal:
  unconfirmed reports while the worker's own status row shows activity.
- **E4. Moving or renaming the primary checkout changes `<hash6>`** while workers run, so their
  sessions stop matching the computed name. Mitigation: liveness fails safe toward live via the
  dispatch marker; early signal: a reconcile reporting an orphan right after a checkout move.
- **E5. tmux workers start producing attention signals** (fork-park pushes, status rows) once they
  carry an identity. Intended, but an operator used to silent tmux workers may read it as new
  noise. Mitigation: the docs task names the change.

*Decision-domains gap check* (catalog via `scripts/resolve-catalog.sh decision-domains`, seed plus
overlay domains): concurrency (the lost-race abort, the flight lock released before the startup wait), observability (three
outcomes, orphan reconcile), deploy and migration (upgrade-window probe plus its gated deferral),
API surface (documented exit statuses, the refused live `attach`), dependency adoption (no tmux
floor, rows E2), authentication (identity-gate grammar validation), existing-seam reuse (the env
wrapper) are all touched and decided. No catalogued domain is touched but undecided; no gap row.

Signed off: 2026-10-04

**Lens review (delta-scoped, parallel fan-out).** Nine read-only sub-agents, one per canonical
lens, over the extension delta (`git diff origin/main` of the four spec files, the code it names,
and the sibling specs it touches). Each finding carried file:line evidence; the coordinator
re-checked the load-bearing ones against the code (the resume flags task dispatches forward, the
registry's tmux-token grammar, the seam-discovery pattern and its missing exemption arm, the flight
lock's stated purpose, the flight dispatch's session lookup, `fleet-messaging`'s identity export,
`fleet-lifecycle-closure`'s retire rule) and ran two live tmux 3.6 probes (recorded in Sources).
Raw findings overlapped heavily across lenses and were merged before disposition.

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 11 | resume never confirming; names outside the death-handle grammar; unmapped prior-launcher basename; failed outcome not adoptable; seam floor breaking between tasks |
| Security | 6 | command words after `--` (disproved by probe); server env overriding the root; forgeable confirmation; refused probe direction; name charset vs handle grammar; containment recheck |
| Error handling and failure modes | 8 | post-create failures with no undo; in-session wrapper refusal unobservable; undo failure unreported; exit-code contract; unreachable server read as death; fleet home split |
| Performance | 4 | startup wait under the flight lock; unstated poll mechanism; every fixture paying the cap; bound vs cap vs test-time budget |
| Concurrency / state | 8 | lost-race rollback destroying the winner's state; registry written before the session; start-time pinning; lock held through the wait |
| Naming, readability, structure | 9 | outcome name drift; multi-obligation REQs; "attach" double meaning; D-12 title; partial supersede marker; bare D-36; placeholder drift |
| Documentation | 9 | missing doc sites; check scope undefined; `--no-attach` wording; changelog and Sources gaps; overview parenthetical |
| Tests / verification | 11 | existing fixtures asserting the old shape; six vacuous checks; pairing gaps both ways; untestable injection points |
| Cross-file consistency | 10 | D-14 misreading D-7; record-closing reserved to the reconcile; identity export duplicated with `fleet-messaging`; seam guard owned by `fleet-lifecycle-closure`; overlap with `test-throughput` |

*Check items.* Qualified cross-spec citations: every qualified citation resolves; the missing ones
(`fleet-lifecycle-closure` REQ-E1.1 and REQ-E1.5, `fleet-messaging` REQ-B1.1) are now cited, and
the bare D-36 is qualified. Requirement/test-spec pairing: every re-scoped REQ carries its paired
test-spec edit in the same disposition. Altitude (REQ-H1.3): the pinned seed claim in Sources is
reconciled as mechanism-primary under D-1, Tasks 11–14 are mechanism tasks; not applicable. Ship
gate (REQ-L1.4): the prior-launcher probe has its gated deferral; the `fleet-messaging` overlap
carries observation `2026-10-04-fleet-messaging-tmux-identity-owner-2fa9088c`; the `test-throughput`
overlap is removed by scoping Task 11 rather than handed off.

*Dispositions.* Operator decisions (four forks):

1. Lost race: abort as already-in-flight touching nothing; the registry is written only after the
   session exists; other post-create failures undo only this run's creations (D-14, D-10, REQ-G1.4,
   REQ-G1.6, Task 12, test-spec).
2. Startup wait vs the flight lock: release the lock once the session exists; launch and confirm
   become two steps (D-10, REQ-F1.1, Tasks 12 and 13, test-spec).
3. Confirmation bound to a per-launch token (D-11, D-15, REQ-G1.5, Task 13, test-spec).
4. This bundle owns the tmux rung's identity export; `fleet-messaging` cited, observation recorded
   (D-11, REQ-F1.5, Sources).

Applied as one grouped disposition (operator: apply all): session names inside the registry's
token grammar with the prior-launcher basename mapped and a refused probe read as live; the
`SessionStart` arm under `startup` and `resume`; `tmux` resolved before side effects;
`remain-on-exit` off on the worker's window; the containment recheck before `new-session`; the
wrapper's `--check` mode and its explicit root and fleet home; the startup wait's ordering,
failure modes, start-time pinning, poll interval, and test seam; distinct documented exit statuses
with no pass-through; the failed outcome clearing its marker and naming the flight's hand removal;
the flight report's session name from the launch line; caller handling of started-unconfirmed in
Task 12; seam discovery taught the new shape with a scoped exemption in Task 12; the old-shape
fixtures rewritten; Task 11 scoped off `test-throughput`'s turf with confirming stubs by default and
budget-bounded timings; the vacuous checks given teeth and Done-when / test-spec paired both ways;
Task 14's doc set, scan scope, and `--no-attach` wording; and the wording fixes (outcome names,
D-12 title and "attach" wording, the partial supersede marker, D-14's reading of D-7, placeholders
and named wrapper options, bare D-36, REQ-F1.1's wording, the overview and in-scope lists, the
changelog, the Sources enumeration, and the hand-launch annotations on REQ-C1.1 and D-8).

Declined, with rationale:

- Splitting REQ-G1.4, REQ-G1.5, and REQ-H1.5 into narrower requirements: their test-spec entries
  already enumerate each obligation, and task citations name which task delivers which half.
- A charset on the command words after `--`: the tmux 3.6 command-word probe shows tmux passes them
  through unexpanded, so the check would cost the prompt and forwarded flags bytes for no
  protection; the probe is recorded in Sources and D-12.

*Post-lens stale-reference sweep.* The lens re-scoped REQ-F1.1, F1.4, F1.5, G1.1, G1.2, G1.4, G1.5,
G1.6, H1.5, and H1.6 (no REQ minted). Grepped the bundle and this entry for the superseded wording
(rollback and terminal-record language, pass-through statuses, exit 127, the `failed` outcome name,
the `startup`-only matcher, the old session charset, "returns once the worker has started"); the
in-scope line, the requirements walk, edit 5, the design ledger, and the gap check were reconciled
in place. `spec-validate` afterwards: 0 errors, 1 warning (REQ-C1.1 changed without a test-spec
change; the change is a hand-launch annotation, so its verification path correctly stands).
`mise run lint:md`: 0 errors.

**Sign-off.** Approved by the operator 2026-10-04 after the shared-understanding summary; Status
flipped Draft→Ready on all four spec files, `Last reviewed:` 2026-10-04. Validator at Ready: 0
errors, the one warning above.

Class: meaning
Lens-pass: this entry's lens review (delta-scoped, nine-lens fan-out; four forks decided by the
operator, the grouped fixes applied, two findings declined with rationale)
Anchor: `05f21e5a2c213c3c9a97c8fba6ca7cad7f35c74c` — computed as
`scripts/spec-anchor.sh specs/fleet-hardening`

### 2026-10-10 — Extension delta kickoff (`/spec-kickoff`, reopened bundle): the front door's authoring floor

**Header.**

- **Spec path:** `specs/fleet-hardening`
- **Spec commit at walkthrough start:** `9ff0c33` (the `/spec-draft --extend` commit that reopened
  the bundle to Draft on all four headers)
- **Walkthrough date:** 2026-10-10
- **Mode:** reopened-bundle delta kickoff (Status Draft with a complete signed brief). Delta: the
  2026-10-10 extension as recorded in `requirements.md`'s `## Changelog`; everything outside it
  stands as signed above.
- **Validator outcome (pre-flight):** `spec-validate specs/fleet-hardening` → 0 errors, 0 warnings
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true`,
  `kickoff_ready_ci_wait: 10m` (defaults; no local override of these keys)
- **Working location:** spec worktree `.claude/worktrees/fleet-hardening-spec`, branch
  `planwright/fleet-hardening/spec`, clean; no open spec PR for the branch.
- **Decision/transcript log:** no harness-provided log in this session; the turn mirror is skipped.

**Goal & glossary (delta).**

*Restatement.* `/tower`, the front door, already has the rule that it never edits the repository
and routes every change as a flight, but nothing enforces it: the tower profile allows Edit and
Write outright, so a tower that slips, or is talked into "just edit it here", writes straight into
a checkout other sessions read. The extension adds a plugin-wired PreToolUse hook that, in any
session marked by `/tower` however it was launched, refuses Edit, Write, and NotebookEdit whose
target lies inside the repository (primary checkout, any linked worktree, the git directory), with
a reason naming the rule and the flight route. Writes outside the repository (petition temp files,
memory) pass. To tell the front door from an orchestrator, `tower-placement`'s session mark gains
a kind; `tower` is sticky for the mark's life, and a mark written before the change reads as
`orchestrate`. The altitude is mechanism under D-1: it enforces an existing rule (D-16).

*Rules out.* `/orchestrate` sessions (their reconcile writes `tasks.md` on the primary checkout);
shell-spelled and MCP filesystem writes (the command guards and the deny list keep the shell path);
removing Edit and Write from the profile's allow list; worker posture; and everything
`tower-placement` owns (the mark store, the plugin Bash/MCP floor, the deny-to-act coverage, the
posture check that reads plugin enforcement).

*Assumes.* `tower-placement` lands first (Task 15 is gated on it deriving Done, D-19); a hook's JSON
deny outranks a settings allow on the running Claude Code version (documented for the exit-2 form,
checked live per the REQ-I1.1 `[manual]` entry).

*Implicit terms surfaced.*

- **Kind:** the `tower` / `orchestrate` field on a session mark.
- **Inside the repository:** canonical-path containment in the primary checkout, a linked worktree,
  or the git directory of the repository the session's working directory belongs to.
- **Authoring floor:** this file-tool deny.

*Resolutions.*

- **A working directory in no repository** (operator decision). REQ-I1.5's "the repository's
  checkouts cannot be listed" read two ways when the session's working directory is not inside any
  git repository. Resolved: no repository means nothing to protect, so the hook defers; a listing
  that fails inside a repository, or a git that cannot run, still denies. Grounded in D-17's scope
  ("the session's repository"); a tower launched outside its tree is already flagged by
  `tower-placement`'s placement check. Spec edit 1 below (applied in place).
  *(Superseded after the lens pass: the floor now protects any git repository and no longer
  depends on a working directory, which the payload `cwd` showed to move with every `cd`; a
  target in no repository defers.)*

Signed off: 2026-10-10

**Requirements walkthrough (delta).**

- *REQ-I, the authoring floor.* In a `/tower` session the plugin denies in-repo Edit, Write, and
  NotebookEdit whatever the launch settings (I1.1), naming the rule and the flight route (I1.2);
  the hook only denies or defers, deferring for outside targets, `orchestrate`-kind sessions, and
  unmarked sessions through the in-shell prefilter (I1.3); the mark records its kind and `tower`
  is sticky (I1.4); containment compares canonical paths and fails closed (I1.5); the posture
  report and docs describe the floor (I1.6). Outcome: confirmed with two gap-fills (edits 1 and 2).
  Probed and left standing: a forged `tower` mark only restricts (deny-only path); a kindless
  pre-upgrade mark leaves a running tower unfloored until its next bring-up or posture check
  re-marks it, the same residual window `tower-placement` REQ-C1.8 documents; the posture
  report's "active" rests on the Bash entry's handshake, accepted in D-18 because both entries
  ship in one hooks file.
  *(Reconciled after the lens pass: I1.1 covers any git repository plus Claude Code's user
  settings files and the plugin root; REQ-I1.7 is minted for the mark store; I1.3 through I1.6 are
  re-scoped as the lens dispositions below record; the kindless-mark window is the docs' to state,
  not REQ-C1.8's, which covers resume and fork.)*

*Consolidated spec-edit list (all applied in place; the bundle is Draft):*

1. `requirements.md` REQ-I1.5, `design.md` D-18, `tasks.md` Task 16 (deliverables and done-when),
   `test-spec.md` REQ-I1.5: a working directory in no git repository defers; a failing listing
   inside a repository, or a git that cannot run, still denies (operator decision, section 2).
   *(Superseded by the lens disposition "any git repository": no working directory decides the
   protected set.)*
2. `design.md` D-18, `tasks.md` Task 15 (deliverables and done-when), `test-spec.md` REQ-I1.4: the
   activation handshake gains two fixed spellings, one per kind, matched as fixed strings, anything
   else marking nothing; each skill's bring-up and posture check runs its own (operator decision:
   `tower-placement`'s single fixed handshake could not carry the kind, and it is the path that
   re-marks a tower entered by resume, fork, or a mid-session skill call).
   *(Refined after the lens pass: matched by whole-command equality; `tower-placement`'s original
   spelling becomes the `orchestrate` one.)*

Both edits resolve ambiguities the operator decided; neither is an agent-authored meaning-class
edit, so no mid-walk lens pass ran. The whole extension is meaning-class and takes the terminal
lens pass.

Signed off: 2026-10-10

**Design walkthrough (delta).** D-16 through D-19 are minted. D-16 (mechanism altitude) confirmed;
D-17 (front-door sessions, in-repo targets, deny) confirmed; D-18 (the kind-carrying mark and the
file surface inside the policy guard) amended by edits 1 and 2; D-19 (parked on `GATE(when: spec
tower-placement done)`) confirmed: the gate is a valid status atom in `accumulator-taxonomy`'s
grammar, and `spec-status` treats a Deferred-parked task as excluded from the Done universe while
Tasks 16 and 17 stay pending on it, so the bundle cannot derive Done around the parked work.
D-1 through D-15 are untouched by the delta and stand as signed. No design decision contradicts a
walked requirement. *(Reconciled after the lens pass: D-16 is amended (where the rule already
lives), D-17 amended (any repository, the floor-switching places, the decided-rule wording, no
knob), D-18 amended (kind-gated fail-closed arms, handshake spelling fate, both-path containment,
the hook-failure default, the corrected path-rule research, the deny-list relation); D-19
confirmed.)*

Signed off: 2026-10-10

**Verification approach (delta).** REQ-I1.2 through I1.5 are `[test]`, run by repository CI under
`mise run check` from Task 15's and Task 16's suites. REQ-I1.1 is `[test + manual]`: the deny per
target class runs in CI; the live confirmation that the hook's JSON deny outranks the tower
profile's Edit/Write allow on the running Claude Code version (profile launch and plain launch)
is swept by the operator on Task 17's PR, whose description records both runs. REQ-I1.6 is
`[test + design-level]`: posture fixtures in CI; the reviewer confirms the skill, profile `_about`,
and posture-delta doc wording at PR review. Dead-path check: every `[test]` entry names a fixture
the policy guard's existing test harness can run (the fork-stub fixture reuses the prefilter
seam `tower-placement` REQ-C1.6 establishes); none depends on an unavailable platform.
*(Reconciled after the lens pass: the posture report has no script to feed a fixture, so REQ-I1.6
is `[test + manual + design-level]`, its `[test]` a structural check in `tests/test-tower-skill.sh`
plus a grep for the retired sentence; the fork check uses logging stubs and a static check, as
`tower-placement` does; REQ-I1.4 gains a `[manual]` docs check; REQ-I1.7 is `[test]`; the live
runs load the plugin from the PR branch and include a subagent Write; the `.GIT` case-variant
fixture runs where the platform allows it.)*

Signed off: 2026-10-10

**Task graph (delta).** From the `Dependencies:` lines: Task 15 has none; Task 16 depends on 15;
Task 17 on 16. A strict chain, no parallelism; critical path 15 → 16 → 17 (see the tasks' effort
lines). Task 15 is parked by its gated Deferred bullet (`GATE(when: spec tower-placement done)`),
so the chain cannot start before `tower-placement` derives Done. Deliberate non-edges: Task 15
carries no `Dependencies:` edge on `tower-placement`, because task dependencies cannot cross
bundles; the gate is the cross-bundle wait (D-19). Task 17 has no direct edge on 15; it reaches it
through 16.

Signed off: 2026-10-10

**Risk register (delta).** Rows continue the numbering of §7 as appended rows; earlier rows are
untouched.

- **F1. `tower-placement` slips.** The extension stays parked as long as that bundle is not Done,
  its docs task included. Mitigation: the gate re-surfaces on every drain; early signal: the drain
  reporting the gate unreached while `tower-placement`'s code tasks are merged.
- **F2. The JSON deny may not outrank a settings allow** on the running Claude Code version (the
  docs state precedence for the exit-2 form). Mitigation: the REQ-I1.1 `[manual]` live check on
  Task 17, with the exit-2 form as the fallback spelling; early signal: a live Write into the
  checkout succeeding under the tower profile.
- **F3. Kindless or stale marks leave a running tower unfloored** until its next bring-up or
  posture check re-marks it. Mitigation: the bring-up and on-request handshakes re-mark with kind
  `tower`; `docs/fleet.md` states the window (Task 17). No live early signal: the posture check is
  itself the re-marking handshake, so a kindless mark is never visible as inactive; the residual
  is bounded by how long a tower runs before its next posture check.
- **F4. "Active" is proven by the Bash entry's handshake, not the file-tool entry's.** A broken
  file-tool matcher would report active while letting writes through. Mitigation: both entries ship
  in one hooks file, a CI check pins the file-tool entry's matcher and timeout (Task 16), and Task
  17's live check exercises the file-tool deny; early signal: the REQ-I1.1 `[manual]` run.
- **F5. An undocumented tower write inside a repository breaks.** A tower habit that writes a repo
  file with the file tool (a machine-local, uncommitted file, for example) is now refused.
  Intended by D-17; mitigation: the refusal names a flight or the operator as the route; early
  signal: refusals in tower sessions on paths no flight would own.
- **F6. Mark-format change across plugin versions** (data-storage and deploy-migration domains).
  Adding a kind changes the
  mark's content; a guard from an older plugin version reading a newer mark under the store's
  strict check could read it as tampered and deny everything in that session. Accepted: a mark is
  written and read by one session's own hooks, so a mismatch needs a plugin upgrade mid-session;
  mitigation: Task 15 keeps the kindless form readable (it reads as `orchestrate`); early signal: a
  tower denying every Bash call right after an upgrade, cleared by a fresh session.
- **F7. A hook that cannot start or times out lets the write through** (operator decision at the
  lens pass: keep the harness default rather than `onFailure: block`). Mitigation: the explicit
  timeout above the guard's own deadline, and a plugin install the posture check proves live;
  early signal: a tower Write into a checkout succeeding while the posture report reads active.
- **F8. A subagent's tool calls may not carry the parent's session id** (undocumented). If not, a
  `/tower` session that delegates a write to an Agent subagent gets an unmarked lookup and a defer.
  Mitigation: the Task 17 live run includes a subagent Write; early signal: that run succeeding.
- **F9. Hardlinks and a check-then-write race.** A hardlink from a temp path to a repository file,
  or a symlink swapped between the guard's check and the write, defeats path containment; both
  need a shell step, which stays out of scope with the command guards. Accepted.
- **F10. A future built-in file-writing tool** would be unmatched by the fixed Edit, Write, and
  NotebookEdit matcher. Mitigation: the hooks-wiring check names the three; early signal: a new
  file tool in the Claude Code tools reference.
- **F11. A broken mark store denies file writes host-wide.** An unsearchable store or tampered mark
  counts as `tower` (operator decision at the lens pass), so every marked session, and any session
  while the store cannot be searched, loses in-repository file writes, workers included, as
  `tower-placement` already accepts for Bash. Early signal: workers refused Edit in their own
  worktrees.

*Decision-domains gap check* (catalog via `scripts/resolve-catalog.sh decision-domains`, seed plus
overlay domains): authentication and authorization (deny-only, sticky `tower` kind, forged
handshake only restricts), concurrency (one session's prompt hook and tool hooks never overlap, so
the sticky read-modify-write has no in-session race), observability (posture report, refusal
reason), deploy and migration (kindless marks read `orchestrate`; the D-19 gate), human
comprehension (the refusal names the rule and route), existing-seam reuse (the policy guard and
`tower-placement`'s store) are touched and decided. Versioning is touched and undecided in the
spec (the mark-format change across plugin versions): recorded as accepted risk F6. No other gap.
*(Reconciled after the lens pass: the lens found the auth, concurrency, and deploy-migration
claims only partly decided and four domains missed; each is now decided in the spec or recorded
here: the protected set and its anchor (auth, D-17), the sticky refresh's no-race rationale and
the kindless window (concurrency and deploy-migration, D-18 and REQ-I1.4), the handshake
spelling's fate (deploy-migration, D-18), the kind's storage as a mark-store shape change
(data-storage, F6 relabelled), the refusal's route for uncommitted files (API surface, REQ-I1.2),
no opt-out knob (secrets and configuration, D-17), and canonicalization pinned by behavior
rather than a named primitive (dependency adoption, the Task 16 cases).)*

Signed off: 2026-10-10

**Lens review (delta-scoped, parallel fan-out).** Artifact class: spec, so the spec lens set,
plus one explicitly named code lens (security and failure modes of the designed mechanism) because
the delta specifies a containment guard. Nine read-only sub-agents, one per lens, over the
extension delta (`git diff 0e173fbc` of the four spec files, the code it names, and
`tower-placement`); rendered-content safety walked inline. The Claude Code platform claims the
lenses relied on (`onFailure`, the default on hook failure, path-rule coverage, absolute targets,
`cwd` versus `CLAUDE_PROJECT_DIR`, subagent payloads, deny precedence, `disableAllHooks`, the
file-tool set) were re-checked independently against the current hooks, permissions, tools,
settings, and subagent reference pages. Raw findings overlapped heavily and were merged before
disposition.

| Lens | Findings | Notes |
| --- | --- | --- |
| Contract correctness and internal consistency | 9 | file tools could rewrite the mark (floor off); fail-closed contract vs "orchestrate defers" (a genuine contradiction); unreadable-mark kind undecided; working directory unpinned; separate-clone tower; handshake spelling fate; F3 signal could not fire; `/orchestrate` inside a tower session; relative targets |
| Ambiguity and interpretation forks | 17 | working-directory source; common vs per-worktree git dir; `..` vs symlink order; dangling symlinks; "no repository" test; arm precedence; orchestrate-kind prefilter; fixed-string matching; "active"; profile-answered handshake; live-run mismatch; "target missing"; relative targets; nested repos; unexpected tool name; "defer" output; case-insensitive volumes |
| Citation and coverage integrity | 6 | live-run mismatch; Done-when gaps; D-16 misplaced the rule's home; obs:6be13a0c "delivered there"; REQ-I1.6 omitted the posture-delta doc; changelog lacked the kickoff edits |
| Dead verification paths | 7 | posture `[test]` had nothing to run; fork check could not fail; Done-when gaps; live-run mismatch; live run could pass without the hook (model refusal, installed plugin); working-directory source; repo-wide negative unrunnable |
| Decision-domain gaps | 7 | auth (working directory), data-storage (mark shape, missed), deploy-migration (handshake fate), API surface (route for uncommitted files, missed), secrets-config (knob, missed), concurrency rationale, dependency adoption (canonicalization primitive, missed) |
| Testability | 18 | posture fixture unrunnable; hooks.json wiring untested; live-run mismatch; Done-when pairing gaps; unpinned reason text; prefix sibling; root equality; case-insensitive; inherited fail-closed arms untested; orchestrate-kind vs fail-closed; mark store via file tool; unknown kind; marking paths; "existing tests" anchor; doc Done-when; check names; posture wording; working directory and relative targets |
| Cross-file consistency | 11 | handshake fate vs `tower-placement` D-8; unreadable-mark kind; mark store writable; REQ-I1.4 vs kindless rule; orchestrate prefilter; oversized outside Write; out-of-scope line vs stickiness; precedence stated as settled; REQ-I1.6 scope; separate clone; D-9 deny-list relation and the window's docs home |
| Documentation and glossary drift | 7 | wrong path-rule research claim; REQ-I1.4 vs kindless; unreadable-mark kind; D-17 enumerated claim; `_about` has no Edit/Write statement; prefilter scope; NotebookEdit omitted in scope line |
| Security and failure modes of the designed mechanism (named code lens) | 9 | working directory moves with `cd`; outside-repo off-switches (mark store, settings, plugin root); fail-open on hook failure; case-insensitive and bind mounts; subagent session id; reverse symlink, hardlinks, race; relative targets; path-rule claim; `disableAllHooks` overclaim and future file tools |
| Rendered-content safety | n/a | the bundle is not rendered into an executing or markup context; data hygiene checked: no secrets, hostnames, or private detail |

*Validation.* Each merged finding was taken through three passes: re-reading the delta as each
consumer (the Task 15/16/17 workers, the reviewer, the operator); checking it against the guard
code and `tower-placement`'s text (the payload `cwd` read and its `$PWD` fallback, the
`CLAUDE_PROJECT_DIR` read, the 2 MB payload bound, the hooks file's entries); and checking the
platform claims against the docs. An adversarial pass then tried to refute the keep set and
resurrect the decline set. It refuted the claim that `..` must be collapsed first (the writer's
order is undocumented) and replaced it with the order-independent "either path inside denies"
rule. It also refuted the eval-artifact finding in part, since the default eval directory sits
under the temp directory, though the decided-rule wording still lands.

*Check items.* Altitude (REQ-H1.3): the pinned seed claim is reconciled as mechanism under D-1 and
recorded as D-16, cited from the goal; Tasks 15 to 17 are mechanism tasks, matching. Ship gate
(REQ-L1.4): the one out-of-band follow-up, pointing `tower-placement` D-8 at D-18 once Task 15
lands, carries observation `2026-10-10-tower-placement-handshake-superseded-c29675e0`; obs:c2c57cdf
stays live, owned by `worker-permission-ergonomics`. Qualified cross-spec citations resolve.

*Dispositions.* Operator decisions:

1. The fail-closed contradiction: arms are kind-gated; an `orchestrate`-kind or unmarked session
   defers on every arm (except the mark store); an unsearchable store, tampered mark, or unknown
   kind counts as `tower`; an oversized payload denies in a `tower`-kind session (D-18, REQ-I1.3,
   REQ-I1.5, risk F11).
2. Protect any git repository, whatever project, rather than the session's own; this supersedes
   the working-directory anchor (decided `CLAUDE_PROJECT_DIR` first, then superseded the same turn
   when the operator raised towers handling several projects) and section 2's no-repo resolution
   (D-17, REQ-I1.1, REQ-I1.5).
3. Close Claude Code's user settings files and the plugin root as floor-switching places, the
   separate-clone gap (by 2), and case-insensitive volumes (by the case-insensitive `.git` walk)
   (D-17, D-18, REQ-I1.1, REQ-I1.5).
4. Keep the harness default on hook failure rather than `onFailure: block` (D-18, risk F7).

Applied as one grouped disposition (operator: apply all): the mark store closed to file tools in
any marked session (REQ-I1.7); the handshake's whole-command matching with `tower-placement`'s
spelling becoming `orchestrate`; REQ-I1.4's kindless carve-out and its documented window; the
posture `[test]` made structural plus a `[manual]` live/missing run, with "active" requiring the
`tower` kind afterward; the hooks.json wiring check; Task 16's cases (reason constant, logging-stub
fork check, prefix sibling, root equality, dangling and file symlinks, both-path containment,
relative target, unexpected tool, defer output, the inherited fail-closed arms); the Task 17 live
runs (PR-branch plugin, both launches, the hook's own deny text, a subagent Write); the corrected
path-rule research and the Sources research entry; D-16's rule home; D-17's decided-rule wording
and no knob; D-18's relation to the deny list; REQ-I1.2's operator route for uncommitted files;
the scope lines (NotebookEdit, "marked only by `/orchestrate`", `/orchestrate` inside a tower,
precedence "expected", `disableAllHooks`, obs:6be13a0c); REQ-I1.6 and Task 17's doc set
(`docs/tower-posture-delta.md`, `docs/fleet.md`); the changelog's kickoff entry; and risk rows F7
to F11 with F3, F4, F5, and F6 revised.

Declined, with rationale:

- Naming a canonicalization primitive in the spec (`cd -P` plus a `readlink` loop): the worker
  picks it under the guard's portability floor; the Task 16 cases (file and dangling symlinks,
  both-path containment) pin the behavior.
- Collapsing `..` lexically before resolving symlinks: refuted as stated; replaced by judging both
  paths.

*Post-lens stale-reference sweep.* The lens re-scoped REQ-I1.1 through I1.6 and minted REQ-I1.7.
Grepped the four spec files and this entry for the superseded wording ("the session's
repository", "working directory belongs", "checkouts cannot be listed", "checkout list",
"unlistable", "inside the repository", "for Edit only", "holds over the allow", "matched as fixed
strings", "no git repository"); the one remaining hit is the drafting changelog entry, which
records history correctly. Earlier sections of this entry carry reconciliation notes in place.
`spec-validate` afterwards: 0 errors, 0 warnings. `mise run lint:md`: 0 errors.

**Sign-off.** Approved by the operator 2026-10-10 after the shared-understanding summary; Status
flipped Draft→Ready on all four spec files, `Last reviewed:` 2026-10-10. Validator at Ready: 0
errors, 0 warnings.

Class: meaning
Lens-pass: this entry's lens review (delta-scoped, spec lens set plus a named security lens,
parallel fan-out; four operator decisions, the grouped fixes applied, two findings declined with
rationale)
Anchor: `e854030aaaf798476697e8c64e66c6905ed251d0` — computed as
`scripts/spec-anchor.sh specs/fleet-hardening`

## 10. Execution research log

<!-- Research-rigor recordings appended during execution (findings, tradeoffs,
     sources). These are NOT anchor entries and never carry a Class:/Anchor:
     line; the spec anchor is computed over the four spec files, not this brief,
     so an execution research note never moves it. -->

### 2026-07-19 — Task 2: the `Notification` hook platform contract (risk rows 1, 2)

The bundle's headline mechanism (D-2) rests on Claude Code's native `Notification`
hook firing for the fork-park / idle-wait state, and on the payload distinguishing
a fork-park from a permission-park. D-2 flagged this as a version-sensitive research
trigger deferred to Task 2 execution; this is that recording. Source consulted: the
current Claude Code hooks documentation (the official reference, over model memory —
research-rigor recency discipline).

**Findings (pinned against the running-version docs):**

- The `Notification` hook fires with a JSON payload carrying a **`notification_type`**
  field — the machine-reliable discriminator (the human-readable `message` is a
  secondary signal). Documented types: `permission_prompt` (permission needed);
  `idle_prompt`, `agent_needs_input`, `elicitation_dialog` (input-wait variants);
  `auth_success`, `agent_completed`, `elicitation_complete`, `elicitation_response`
  (informational — a completion/answer, not a wait, so the gating below suppresses
  it). Other payload fields: `session_id`, `transcript_path`, `cwd`,
  `hook_event_name`.
- A `Notification` hook is **non-blocking**: exit 0 shows stdout to the user only;
  any non-zero exit is a non-blocking error (the notification proceeds). A
  side-effect script (push a store record) just needs to exit 0 — which the hook
  arm does unconditionally, honoring the fleet-autonomy always-exit-0 discipline.
- **Matchers:** the docs are internally inconsistent (one section says matchers are
  ignored for `Notification`; the matcher table lists it as supported). Decision:
  the arm does NOT rely on the matcher — it gates in-script on `notification_type`,
  so correctness holds regardless of how the running version treats the matcher.

**How Task 2 uses it (the payload-reason gating, risk row 2):** the hook arm parses
`notification_type` with awk (never jq, REQ-K1.5), STRICTLY validates it against a
fixed allow-list, and pushes an `awaiting-human` record ONLY for a genuine input-wait
(`idle_prompt` / `agent_needs_input` / `elicitation_dialog`). `permission_prompt` is
suppressed (fleet-autonomy's `PermissionRequest` hook already owns permission-park;
a second push here would race it — the "false awaiting-human" the Done-when forbids);
`elicitation_response` (the user already answered), `auth_success`, `agent_completed`,
`elicitation_complete`, and any unknown / absent / spoofed type push NOTHING. A
spoofed value can only map to a known-safe action or be suppressed — no payload text
is executed or stored raw.

**Residual (delegated per risk row 1, an accepted completion path):** the end-to-end
`[manual]` confirmation (park a REAL worker at an `AskUserQuestion` fork on the live
Claude Code version and confirm which `notification_type` it raises, and that the push
lands) is a human-in-the-loop check the automated suite cannot run; it is surfaced in
the PR's pending-sign-off checklist. The push set covers every documented input-wait
type, so it is robust to which one a fork-park raises; and if a fork type raises none,
D-3's reconcile backstop plus the retained heartbeat-age `hung` classifier catch it
(the three-layer defense-in-depth of risk row 3) — never the silent 7-hour blindness.
No significant unanticipated risk surfaced; no stop condition.

**`idle_prompt` vs the terminal Stop-downgrade (a convergence-review fork, deferred to
the same `[manual]` check).** `idle_prompt` is the most likely `notification_type` for
the central `AskUserQuestion` fork, so it stays in the push set. But `idle_prompt` is
also the "turn ended, agent idle at the prompt" condition — exactly when the `Stop`
hook fires. For the other two push types (`agent_needs_input`, `elicitation_dialog`)
a tool call is still pending, so the turn has not ended and no `Stop` fires; for
`idle_prompt`, if `Notification` lands before `Stop`, the terminal exit edge clears the
fresh fork-park to `idle` (and the reconcile cannot recover a downgraded-to-`idle` row).
This is arguably self-correcting — a genuine mid-turn fork raises no `Stop`, and a real
turn-end idle *should* resolve to `idle` — but it hinges on the undocumented
Notification/Stop firing order. The live `[manual]` check must confirm that order for
`idle_prompt`, and the human decides between: **(a)** keep `idle_prompt` in the push
set and accept the self-correcting behavior (recommended: it is the primary fork
signal); **(b)** exempt an `idle_prompt`-reason park from the terminal clobber (risks a
stuck `awaiting-human` on a real turn-end idle); or **(c)** drop `idle_prompt` from the
push set (risks missing the primary `AskUserQuestion` fork). Surfaced as a queued fork
in this task's PR, not resolved in code — every option has a downside the live
confirmation must inform.
