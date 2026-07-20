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
  `idle_prompt`, `agent_needs_input`, `elicitation_dialog`, `elicitation_response`
  (input-wait variants); `auth_success`, `agent_completed`, `elicitation_complete`
  (informational). Other payload fields: `session_id`, `transcript_path`, `cwd`,
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
