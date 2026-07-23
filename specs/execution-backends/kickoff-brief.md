# Execution Backends — Kickoff Brief

## 1. Header

- **Spec:** `specs/execution-backends`
- **Spec commit at walkthrough start:** `b573da4`
- **Walkthrough date:** 2026-07-21
- **Mode:** first activation (Status Draft, no prior brief)
- **Validator:** `spec-validate: 0 error(s), 0 warning(s)` (run at pre-flight, 2026-07-21)
- **Format-version:** 2 (stored status rests at Ready after the flip; Active/Done derived)
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true`,
  `kickoff_ready_ci_wait: 10m` (defaults; no local override of these keys)
- **Working location:** worktree `.claude/worktrees/draft-exec-backends` on branch
  `planwright/execution-backends/spec` (clean; name predates the `<spec>-spec` convention,
  branch is canonical)

## 2. Goal & glossary

**Restatement.** The spec decouples planwright's fleet richness (observe-in-flight,
steer-in-flight, session-grade, human-attachable) from the tmux substrate. Verified research
(CLI v2.1.217, obs:3414579b) proved a stream-json worker is the same binary and harness —
SessionStart hooks fire under `-p`, `session_id` persists, `--resume` recovers — so session
grade no longer requires a terminal. Five clusters: (1) the capability-contract extension
(two new rows, `overhead` + `hook_registration` properties, subagent row corrected,
non-`--bare` pinned, adapter grammar 6→8 back-compatibly); (2) `dispatch_backend` gains
semantic `full-session` and the shipped default flips from `subagent` (operator-default only);
(3) the standalone `/offload` skill, sole home of adaptive selection, governed by the
tower-frugality and smallest-sufficient-rung axioms in `doctrine/work-placement.md`;
(4) the backend-agnostic status view, phased CLI table → rendered dashboard (planned, not
contingency); (5) the `claude agents --json` idle oracle as Task 1, protecting the existing
tmux fleet first.

**Rules out:** model/effort allocation (fleet-autonomy), cross-tower coordination, Agent
Teams, SDK-as-library, per-task auto-selection, deprecating tmux, the worktree config-layer
gap (risk only, config territory).

**Assumes:** the installed CLI is the universal, already-authenticated substrate; v2.1.217
findings hold with re-verification against the running CLI at execution (D-4); the attention
store and degradation ladder from orchestration-fleet are reusable as-is.

**Implicit terms surfaced and resolved:**

1. **Decision-queue = attention store** (operator, 2026-07-21): a decision-queue item IS an
   attention-store entry. Task 4 writes to the existing store (no new queue surface, no
   mirror); Task 7/8 read the attention store as one source. Matches D-5's "converts the
   deadlock into the existing attention-store discipline".
2. **Attended `full-session` and tmux** (operator, 2026-07-21): "attended runs may present
   tmux" (D-8) means a **tmux-context-detected ask** — when the tower detects it is itself
   running inside a tmux session (e.g. `$TMUX` set), it asks the operator once per run
   whether tmux joins the candidate set; outside tmux context, or unanswered, attended
   resolution behaves exactly as unattended (richest non-interactive session-grade rung).
   Never-silently-interactive holds in all cases. → Spec edit E1 (D-8 amendment), collected
   for the design walkthrough.
3. Terms checked and found defined in place: *session-grade-as-recoverable* (D-5),
   *operational heartbeat* (REQ-C1.2 inline), Task 3's *completion signal* (task-level
   design freedom, noted deliberately unpinned).

**Consolidated spec-edit list (running):**

- **E1** — D-8: replace "attended runs may present tmux" with the tmux-context-detected
  once-per-run ask semantics above. (Applied at section 4.)

Signed off: 2026-07-22

## 3. Requirements walkthrough

Per-group outcomes (groups A–F, `requirements.md`):

- **REQ-A — contract & registry.** Intent confirmed: all new capability content lands as
  first-class contract rows/properties with the lockstep drift guard (A1.6) and the
  back-compatible 6→8 adapter grammar (A1.7); no consumer keys on backend names. Edge
  checked: A1.5's pinning scope ("every headless and stream-json launch planwright emits")
  is comprehensive and matches D-12's `-p`-family guard. No changes.
- **REQ-B — the knob.** Intent confirmed: backend choice is operator policy. Edge resolved
  (operator, 2026-07-22): an **explicitly configured backend not advertised on the host
  fails closed** — the dispatch halts to Awaiting input naming the missing backend; never a
  silent substitute. Degradation is defined for semantic values (`full-session` walks the
  ladder); an explicit literal overrides the ladder and is honored or halted. → Edits E2,
  E3. B1.1's "unattended" parenthetical stays compatible with E1's attended-ask semantics.
- **REQ-C — /offload.** Intent confirmed: adaptive selection in exactly one place; axioms
  doctrine-grade; C1.4's ask-never-guess SHALL NOT stands. `/offload` is inherently
  attended (an operator petition), so no unattended arm is needed.
- **REQ-D — status view.** Intent confirmed: one source-merging layer, two renderers,
  visible per-source degrade. The dashboard's serving/refresh mechanism stays **Task 8
  design freedom** (spec altitude), with a risk-register row (section 7) recording the
  operator's direction (2026-07-22): the selection criterion is the **best and most useful
  surface for the phone/browser away-workflow, not the simplest** — pragmatic simplicity
  that undercuts usefulness defeats Task 8's purpose. Task 8's executor reads this from
  the brief.
- **REQ-E — harness contract.** Intent confirmed; decision-queue = attention store (§2).
  The pending-age threshold value is deliberately unpinned (task/config freedom).
- **REQ-F — idle oracle.** Intent confirmed: oracle authoritative when the call-time probe
  succeeds; pane-scrape fallback-only. The research already verified the oracle covers
  tmux-launched workers.

**Consolidated spec-edit list (running):**

- **E1** — D-8: attended tmux semantics → tmux-context-detected once-per-run ask (§2).
- **E2** — D-8: add the explicit-but-unavailable fail-closed rule (halt to Awaiting input
  naming the missing backend; never silently substitute).
- **E3** — test-spec REQ-B1.1: fixture line for the fail-closed halt on an explicitly
  configured, unadvertised backend.

Signed off: 2026-07-22

## 4. Design walkthrough

Ledger — every D-ID accounted for (`design.md`):

| D-ID | Disposition | Note |
| --- | --- | --- |
| D-1 | Confirmed | Altitude record for both pinned seed claims; two consumers justify doctrine placement. |
| D-2 | Confirmed | Amend the Done-owned contract doc in place; operator confirmed at fold-detection. |
| D-3 | Confirmed | First-class rows, not adapters; core-verified rungs. |
| D-4 | Confirmed | Installed CLI only; execution re-verifies against the running CLI version. |
| D-5 | **Amended** | Clarification applied (kickoff 2026-07-22): decision-queue = the existing attention store, no new surface (§2 resolution 1). |
| D-6 | Confirmed | Qualitative overhead enum; evaluable per backend. |
| D-7 | Confirmed | `hook_registration` boolean closes obs:4dc16740 at the contract. |
| D-8 | **Amended** | E1: attended ask pinned to tmux-context detection, once per run, unanswered → unattended behavior. E2: explicit-but-unavailable fails closed (halt to Awaiting input); ladders apply to semantic values only. |
| D-9 | Confirmed | Per-spec override rides config overlays; policy stays out of signed spec content. |
| D-10 | Confirmed as pre-amended | Dashboard promoted to planned Task 8 (2026-07-21); §3 adds the best-and-most-useful criterion to the risk register. |
| D-11 | Confirmed | Oracle primary, capability-probed at call time; retires a false-idle class. |
| D-12 | Confirmed | Non-`--bare` pinned at every `-p`-family launch site. |
| D-13 | Confirmed | 6→8 append with fail-safe defaults; malformed still fails closed. |

**Edit application record.** E1 + E2 applied as the D-8 amendment (annotated in place);
E2 additionally minted **REQ-B1.5** (fail-closed rule, cited to D-8 and kickoff §3) with
Task 5's Done-when/Citations extended; E3 applied as the test-spec **REQ-B1.5** entry plus
attended-resolution fixtures under REQ-B1.4's entry (the ask is the non-silent path of the
safety invariant); the §2 decision-queue resolution applied as the D-5 parenthetical.
Changelog entry dated 2026-07-22 added to `requirements.md`.

**Mid-walk delta-scoped lens pass** (per `kickoff-verification`, run at application,
2026-07-22): scope = the D-5/D-8 amendments, REQ-B1.5, and dependents. Checks: no
contradiction between the fail-closed rule and `full-session`'s ladder (semantic/literal
split explicit); unanswered attended ask falls back to unattended (no deadlock);
once-per-run ask compatible with REQ-B1.2; validator re-run clean (0/0); stale-reference
sweep clean (REQ-B1.5 cited from tasks, test-spec, changelog; no stale D-8 phrasing outside
the brief's own edit record). Findings: none. Disposition: clean pass, recorded here.

No design decision contradicts a walked requirement; no inconsistency halt raised.

Signed off: 2026-07-22

## 5. Verification approach

**Coverage mix.** Derived from `grep '^### REQ-' specs/execution-backends/test-spec.md`
(cite, don't copy): every REQ has an entry; the mix is predominantly `[test]` under the
repo's fixture-driven shell suites, with `[test + design-level]` for doctrine/skill-prose
surfaces, three `[test + manual]` entries, one `[Gherkin]` (REQ-C1.4). *(Reconciled at the
lens-pass sweep 2026-07-22: REQ-A1.4 re-tagged `[test + design-level]` — its drift-guard half
was automated all along — leaving no pure `[design-level]` entry.)*

**Verification ownership.**

- `[test]` — `mise run check` in CI (`.github/workflows/ci.yml` runs the same tasks); the
  referenced suites all exist today: `test-fleet-liveness.sh`, `test-orchestrate-backends.sh`,
  `test-dispatch-launch-pin.sh`, `test-config-get.sh`, `test-check-options-reference.sh`
  (verified at walkthrough, 2026-07-22).
- `[manual]` — three entries, each documented in the owning task's PR: REQ-E1.3's real-CLI
  resume probe and REQ-F1.1's live oracle probe (version-sensitive, the task executor runs
  them), and REQ-D1.2's phone/browser glance check. The operator sweeps them at PR review
  (merge is the human key).
- `[design-level]` — artifact existence-plus-coverage, checked at the owning task's review
  convergence and by the structural guards where wired (skill guards, drift guard).
- `[Gherkin]` — REQ-C1.4's scenario is recorded specification; enforced by `/offload`'s
  skill prose and exercised manually at Task 6 convergence.

**Dead-path check.** No dead paths: every named suite, guard, and mise task exists
(grounded above). One stale claim found and fixed (E5, expression-only): the coverage-mix
intro still said `[manual]` was "reserved for the two real-CLI paths" — stale since the
Task 8 promotion added the glance check as a third manual entry. Intro reworded; changelog
entry extended.

**Consolidated spec-edit list (running):** E1–E3 applied (§4) · **E5** — test-spec intro
reworded for the third `[manual]` entry (expression-only, changelog-noted).

Signed off: 2026-07-22

## 6. Task graph

Reconstructed from the `Dependencies:` lines (authoritative; render via
`scripts/spec-graph.sh specs/execution-backends`, verified matching at walkthrough
2026-07-22 — cite, don't copy).

- **Wave structure.** Ready now: T1 (idle oracle), T2 (contract hub). After T2: T3, T4, T6
  in parallel. T5 needs T2+T4; T7 needs T1+T4; T8 needs T7. Peak parallelism four units
  in flight (T1, T3, T4, T6) while T2's dependents fan out.
- **Critical path (effort-weighted).** 2 → 4 → 7 → 8 (confirmed by the render's crit
  marking; the effort weights come from the task blocks' `Estimated effort:` fields). T4
  (3d) is the heaviest single unit; anything that shortens its convergence shortens the
  whole spec.
- **Dispatch order note.** T1 dispatches first (drafting decision recorded in the tasks
  intro): highest-value, lowest-risk, protects the existing tmux fleet independent of all
  contract work.
- **Deliberate non-edges** (do not "fix" these):
  1. **T6 ↛ T3/T4** — `/offload` dispatches through the backend seam as it exists on the
     host; it does not require the new rungs to have landed.
  2. **T5 ↛ T3** — the resolver works off advertised sets and synthetic fixtures, not the
     rungs' implementations, so Task 5 needs no Task 3 code to build or test against.
     *(Rationale corrected at the lens-pass sweep 2026-07-22: headless-oneshot IS
     session-grade per the contract's evaluable definition; the non-edge stands on build
     independence, not capability class.)*
  3. **Nothing depends on T3** — the headless rung is standalone dispatch capability; its
     terminal position is intentional, not an omission.
  4. **T1 ↛ T2** — the oracle consumes the *installed CLI*, not the contract; coupling it
     to T2 would delay the fleet protection for no information gain.

Signed off: 2026-07-22

## 7. Risk register

**Decision-domains gap check** (2026-07-22): walked against the full eleven-domain core
seed (`config/decision-domains.yaml`, read plugin-direct; no adopter, repo-tracked, or
machine-local overlay catalog exists, verified by path check — the merged-path resolver
returned empty due to a core-root misresolution, recorded as an observation, not a gap in
this bundle). Every domain the spec touches is decided: api-surface (D-3/D-6/D-7/D-13,
REQ-C), concurrency (D-5; cross-tower explicitly out of scope), observability (D-10/D-11,
visible degrade), secrets-config (D-8/D-9; worktree gap → risk 3), queues-async (§2:
decision-queue = attention store, 1:1 mapping, no-auto-answer), deploy-migration (the
default flip, declared with migration note in Task 5), versioning-scheme (D-13
append-with-defaults), auth (scoped out via D-4), data-storage / caching /
dependency-adoption (nothing new; Task 8's serving choice could implicate
dependency-adoption → folded into risk 4). **No undecided catalogued domain remains.**

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| 1 | A CLI default flip to `--bare` strips SessionStart hooks and harness surface from every headless worker at once. | D-12 pins non-`--bare` at every `-p`-family launch site; the launch-pin guard (REQ-A1.5) fails CI on an unpinned site. Early signal: CLI release notes; guard failure. |
| 2 | Version sensitivity: stream-json behaviors verified at CLI v2.1.217 only; the platform (including Agent Teams) keeps moving. | D-4: execution re-verifies against the running CLI; the two real-CLI `[manual]` probes (REQ-E1.3, REQ-F1.1) are the per-task check. Early signal: a manual probe diverging from the pinned findings. |
| 3 | The machine-local config overlay does not propagate to task worktrees, so a machine-local `dispatch_backend` may not reach workers — interacting with the default flip. | Known gap, owned by config territory (out of scope here, per Sources). Early signal: a worker launching on an unexpected backend. Fix tracked outside this bundle. |
| 4 | Task 8 under-builds the dashboard: "smallest sufficient mechanism" pragmatism picks the simplest serving shape and under-delivers the phone/browser away-workflow (operator direction, 2026-07-22). | The brief carries the selection criterion: **best and most useful surface, not simplest** — simplicity acceptable only when it costs no usefulness. Serving/refresh mechanism decided at Task 8 pickup on Task 7's merge-layer shape, recorded in Task 8's PR; a serving choice implying a new runtime dependency escalates per the dependency-adoption domain. Early signal: a Task 8 design note choosing "simplest" without a usefulness argument. |
| 5 | The verified indefinite-pend deadlock: `--permission-prompt-tool stdio` pends forever if unanswered. | D-5 couples every receipt to an attention-store item plus a pending-age alarm; fixture-covered (REQ-E1.1, including the no-auto-answer assertion). Early signal: the alarm firing. |

**Open questions:** none carried — every question raised in the walk was resolved into a
decision (§2, §3), a spec edit (E1–E3, E5), or a risk row above.

Signed off: 2026-07-22

**Research notes — Task 1 execution (appended 2026-07-22, /execute-task).** The risk-row-2
re-verification against the running CLI (v2.1.217, the pinned research version), performed
while building the idle oracle:

- `claude agents --json` re-verified live: rows carry `cwd`, `sessionId`, `kind`
  (`interactive` | `background`), `startedAt`, `name`, optional `pid`, and `status`; all
  three status values (`busy`, `idle`, `waiting` — the latter with a `waitingFor` detail,
  e.g. a permission prompt) observed in the live fleet. Defunct background rows carry no
  `status` (and no `pid`); the oracle treats a status-less row as contributing no evidence.
- Unknown/future status values contribute no evidence either (forward-compatible: never
  guessed into busy or idle), and a worker absent from the output is `absent` — no evidence,
  never death (REQ-F1.1's positive-evidence baseline preserved).
- The CLI's own `--cwd` flag filters *background* sessions only, so it is not used; the
  oracle filters client-side over the full row set (tmux workers appear as `interactive`).
- Probe cost on a loaded host: 2–10 s wall (node CLI cold start under load); the probe is
  bounded at 10 s by default (`PLANWRIGHT_ORACLE_TIMEOUT` overrides), and a timeout reads as
  oracle-unavailable → fallback, never a wrong verdict. Oracle probe caching stays declined
  (re-anchor 3); a per-call probe at reconcile cadence is acceptable at this cost.
- Session `name` values are free text; the oracle's scanner is string-boundary- and
  escape-aware, so a name carrying spoofed JSON text can never assign fields
  (fixture-covered).

**Research notes — Task 3 execution (appended 2026-07-23, /execute-task).** The risk-row-2
re-verification against the running CLI (v2.1.218; the pinned research version was v2.1.217),
performed while building the headless-oneshot dispatch:

- `--bare` still ships and still has no explicit inverse flag, so the D-12 pin remains
  "never pass `--bare`"; the launch-pin guard's `-p`-family site scan discovers launch
  sites by the long `--print` form (the short `-p` is ungreppable beside `mkdir -p`).
- `--print` (the documented long form of `-p`) verified live: stdin prompt accepted,
  `--output-format json` returns `is_error`, `result`, and `session_id` (the session
  persists and is resumable), exit 0.
- `--permission-prompt-tool` no longer appears in `--help` at v2.1.218 (it was the
  verified indefinite-pend gotcha at v2.1.217). The one-shot posture is unchanged and
  verified live: with no prompt tool attached, an unauthorized Bash ask under `--print`
  TERMINATES the run with the refusal visible in the result text (the tool call is denied
  at the harness; no file was created; no pend) — the no-pend posture holds at the running
  version.
- New at this version: `--bg/--background` (background agent, managed via
  `claude agents`). Not adopted — Task 3 uses shell-level detachment for a deterministic
  exit-code completion signal; recorded as observation
  `obs:b48fa0a1` for future research.

## 8. Sign-off

**Lens review pass** (first activation — full bundle; fan-out: one read-only sub-agent per
canonical lens, 2026-07-22). ~177 raw candidates merged to ~60 distinct findings.

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | 29 raw | 6 verified cross-spec contradictions; resolved via clusters 1–4 below |
| Security | 20 raw | Echo/render discipline, capture hygiene, dashboard exposure, launch-as-data; cluster 6 |
| Error handling and failure modes | 34 raw | Resume/crash windows, vacuous-pass guards; clusters 5, 7 |
| Performance | 12 raw | 2 survived as spec items (overhead enum, once-per-run); rest declined as task-level |
| Concurrency / state | 25 raw | Dedup keys, alarm durability, orphan race, ask-state; clusters 4, 5 |
| Naming, readability, structure | 23 raw | GATE token, obs UIDs, tag fix applied; wording nits declined |
| Documentation | 5 raw | All 5 applied (guard-wording honesty, 3 citation fixes) |
| Tests / verification | 26 raw | Pinned sets/ladder + fixture cells applied; cluster 7 |
| Cross-file consistency | 3 raw | Task 2 += D-5 applied; Last-reviewed handled at the flip; intro claim fixed |

**Altitude check (REQ-H1.3):** pass — both pinned seed claims resolved by D-1, cited from the
Goal; decomposition matches (doctrine task 6, capability-seam task 2, mechanism tasks, config
value task 5). Not applicable arm unused.

**Dispositions** (operator-decided in seven clusters, 2026-07-22):

1. **Fail-closed scope** → dispatch-time only; declared narrowing of orchestration-fleet
   REQ-B1.4's degrade-on-absence for explicit literals; mid-run failover keeps the foreign
   logged descent. Applied: REQ-B1.5, D-8.
2. **Attended model** → configured semantic value is the operator's standing answer; the
   tmux-context ask is the only attended ask. Declared narrowing of o-f REQ-B1.4's attended
   present-and-ask. Applied: REQ-B1.1, D-8.
3. **Session grade / ladder** → headless-oneshot is session-grade (contract's evaluable
   definition + its own headless-pool example + CLI evidence: `-p` sessions persist and
   resume, non-`--bare` loads the full harness); ladder pinned tmux > stream-json-persistent >
   headless-oneshot > subagent > print/in-session; both advertised sets and the overhead enum
   pinned. Applied: REQ-A1.2, REQ-A1.3, REQ-A1.8, D-6, D-8.
4. **Run boundary** → "run" = one tower session; non-blocking ask; answer persisted in the
   spec-local runtime dir. Applied: D-8, Task 5, test-spec REQ-B1.1.
5. **REQ-E depth** → invariants in spec (REQ-E1.4 answer delivery; REQ-E1.5 crash-window
   guarantees), mechanics to Task 4 (backlog below). Applied.
6. **Security clauses** → all four applied: launch/advertise input hygiene (REQ-A1.9), render
   hygiene (REQ-D1.1/D1.2, Task 7/8), capture hygiene (Task 4), dashboard read-only +
   no-unauthenticated-exposure (REQ-D1.2, Task 8).
7. **Mechanical package** → all ~22 items applied (guard-wording honesty, citation fixes,
   tags, GATE token, obs UIDs, manual probes in Done-when, fixture cells, oracle failure
   semantics, offload ask/report clauses, print scoping, D-12 pin mechanism).

**Task 4 design-freedom backlog** (mechanics deliberately not pinned; executor decides against
the running CLI, guided by REQ-E1.4/E1.5): receipt-journal format and location; alarm
timer-vs-scan model and threshold value (config knob candidate); dedup-key derivation from the
control_request envelope; recovery-initiator identity (tower reconcile vs supervisor watchdog)
and its lock; answer-at-crash re-delivery protocol; capture rotation/retention; completion- and
event-stream sharing mechanism for status-view readers; supervisor memory bounds.

**Declined findings** (with rationale): probe/render/refresh cost engineering and supervisor
resource caps (task-level mechanism, no spec bound warranted — smallest-sufficient-mechanism);
default-flip justification demanded quantification (operator-decided in the primary seed);
sub-1KB pre-ingestion evaluability (the axiom is guidance over known size classes, not a
runtime predicate); config-layer trust distinctions for explicit values (planwright's existing
overlay trust model governs; repo-tracked content is reviewed content); sentence-structure
rewrites of REQ-B1.1/C1.2/D1.2 beyond what clarity required (churn); "Status Draft
contradicts signed brief" (mid-pipeline state, the flip below resolves it);
provides_attention_surface suppression interaction (no shipped backend advertises it; recorded
here for Task 7's executor); per-worker completion-signal integrity model (Task 3 freedom,
liveness is positive-evidence-of-death regardless).

**Sign-off record** (first activation, 2026-07-22). Walkthrough sections 1–7 signed; lens pass
above fully dispositioned; pre-flip verification passed (markdownlint clean over the bundle
and brief; recorded claims re-derived: validator 0/0 at Ready, tag tally and new-REQ coverage
re-checked); Status flipped Draft→Ready and `Last reviewed:` bumped to 2026-07-22 on all four
files; validator re-run clean post-flip. Signed off by the operator via the approval summary.

Class: meaning
Lens-pass: §8 lens review pass above (canonical table, fan-out, dispositions 1–7, declined
log, Task 4 backlog)
Anchor: `5a8ab7fef8c1961490c4bfc19a86d84312c678b4` — computed as
`scripts/spec-anchor.sh specs/execution-backends`

## Amendment log

### Re-anchor 1 — panel-review clarifications (2026-07-22)

Four expression-only wording clarifications from the `/panel-review --nested` gemini pass,
operator-approved as a cluster (apply all): REQ-E1.5 failed-resume halt scoped to the affected
unit; D-8 late-answer race stated benign; test-spec REQ-E1.4 visible-failure pinned to an
attention-store item; REQ-F1.1 pane-scrape fallback scoped to pane-hosted workers. Cites the
requirements.md Changelog entry dated 2026-07-22 ("Post-sign-off panel-review
clarifications"). Two panel findings declined: the unattended Awaiting-input halt is the
designed attention surface, not a deadlock; the dashboard exposure constraint already exists
in REQ-D1.2/Task 8.

Class: expression-only
Anchor: `2ec5d07b8269ea9dfa8741f15d23e4e0d8211cce` — computed as
`scripts/spec-anchor.sh specs/execution-backends`

### Re-anchor 2 — panel iteration 2 clarifications (2026-07-22)

Three expression-only clarifications from the second gemini panel pass, operator-approved as a
cluster: REQ-B1.5 ladder-exclusion explicitly scoped to dispatch-time resolution; the
pending-age alarm coupling extended to AskUserQuestion items (REQ-E1.2, D-5, test-spec —
sibling parity with REQ-E1.1); D-12 forward non-bare-flag adoption clause. Cites the
requirements.md Changelog entry "Panel iteration 2 clarifications". Re-declined (consistent
with the §8 declined log): unbounded event-stream render cost (task-level mechanism). Noted:
§3's E3 label ("test-spec REQ-B1.1") predates REQ-B1.5's minting; §4's application record is
the reconciliation (§3 is append-only post-sign-off).

Class: expression-only
Anchor: `fa6f35ad4a4d88eeafe2933c023beefb2ada9398` — computed as
`scripts/spec-anchor.sh specs/execution-backends`

### Re-anchor 3 — panel iteration 3 clarifications (2026-07-22)

Five expression-only clarifications from the third gemini pass, operator-approved as a cluster
(with the exit rule: a final pass returning only new minor wording nits declares convergence):
Task 3 no-pend mechanism grounded; REQ-F1.1 death determination = the backend's
positive-evidence liveness baseline ("advertised" corrected); test-spec REQ-A1.2
fails-visibly fixture; Task 4 completion/liveness parity line. Cites the requirements.md
Changelog entry "Panel iteration 3 clarifications". Re-declined: oracle probe caching
(task-level mechanism, consistent with the §8 declined log).

Class: expression-only
Anchor: `955f204cc5a5cc40f4344bd635becd82726b0e97` — computed as
`scripts/spec-anchor.sh specs/execution-backends`

### Re-anchor 4 — panel iteration 4, convergence declared (2026-07-22)

Final gemini pass, dispositioned under the operator's exit rule (iter-3 approval). Applied
(expression-only, all restating operator-approved content): REQ-B1.1 no-session-grade-host
degradation parenthetical; REQ-A1.8 existing rows' overhead classes pinned; test-spec
REQ-D1.2 manual check extended to confirm the exposure constraint. Declined: --bare-omission
re-raise (mitigation already three-part: guard + re-verification + forward-flag clause; residual
in risk row 2); duplicate-ask race (cosmetic, every arm safe under the declared benign-race
semantics). Task-4 backlog additions (mechanics, no spec change): alarm-firing outcome =
operator escalation on the attention surface, never auto-answer or worker kill; ask-state
duplicate-suppression across concurrent dispatches. Panel converged: no High+ finding survived
validation as a new decision. Cites the requirements.md Changelog entry "Panel iteration 4".

Class: expression-only
Anchor: `845b132198b19a424f05ae31cad1261da375c026` — computed as
`scripts/spec-anchor.sh specs/execution-backends`

### Re-anchor 5 — Task 1 execution, test-spec fixture pinning (2026-07-22)

Expression-only self-re-anchor by `/execute-task` (the one anchor entry an execution skill may
write): test-spec REQ-F1.1 now names `tests/test-fleet-pane-detect.sh` as the home of the
pane-scrape false-idle fixture (the pane-side half; the liveness suite covers the store-side
correction and every other REQ-F1.1 clause). Gap-fill consistent with the accepted decisions —
D-11's demotion puts the pane fixture beside the pane heuristics it gates. Cites the
requirements.md Changelog entry "Task 1 execution, expression-only: test-spec REQ-F1.1".

Class: expression-only
Anchor: `d332fc7da182d53e145b9524a72643713f27ab42` — computed as
`scripts/spec-anchor.sh specs/execution-backends`
