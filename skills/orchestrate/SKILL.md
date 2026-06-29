---
name: orchestrate
description: >
  Advance one planwright spec by one step: read tasks.md, pick the next ready
  unit critical-path-first (or one cohesion bundle), create or reuse its
  worktree, run the execution freshness gate, move the unit to In progress
  under the per-spec lock, and dispatch /execute-task via the configured
  backend. A stateless, disposable control tower — every step is atomic and a
  reconcile sweep rebuilds the picture from disk. Never merges, never marks a
  PR ready, never auto-chains into /spec-kickoff. --bookkeeping runs the
  out-of-session drain + PR reconcile; --watch loops the step.
argument-hint: "[<spec-path>] [--watch] [--bookkeeping] [--backend <b>] [--unattended]"
---

# /orchestrate

The orchestration layer of the planwright pipeline (REQ-F1.1–REQ-F1.10): a
**stateless step machine** (D-7) that advances a Ready or Active spec one unit
at a time. Each step reads `tasks.md`, selects the next ready unit, prepares its
worktree, dispatches `/execute-task`, records the move, and exits. The step —
not the session — is the unit of crash-safety (D-8): a watch loop or control
tower may take many steps per session, each individually atomic, and any step
may die mid-flight without losing work, because the only durable state is
`tasks.md`, `gh`, and the process/window list. A reconcile sweep rebuilds the
full picture from those three on the next run.

The tower is **disposable** (D-38): it holds no in-memory state beyond the
current step. This is what lets it run headless under cron, be killed and
restarted freely, and run concurrently in several sessions against the same
spec (serialized only during the brief state-move by the per-spec lock, D-10).

`/orchestrate` **never** merges or marks a PR ready (sign-off and merge are
the human's two reserved controls, REQ-J1.1), **never** auto-chains into
`/spec-kickoff` (REQ-J1.3), and **never** force-pushes, amends, squashes, or
rebases (REQ-J1.4). It creates draft PRs only, by way of `/execute-task`.

## Doctrine

This skill is procedure, not doctrine. Resolve and read these rule docs at
run start via the rule-doc resolution convention
(`scripts/resolve-rule-doc.sh <doc-name>` under the resolved planwright root,
or the documented `PLANWRIGHT_ROOT`/`CLAUDE_PLUGIN_ROOT` chain); their
definitions govern wherever this skill names a concept:

- `spec-format` — the meta-spec: status lifecycle, the kickoff-brief and
  sign-off-record structure, content anchors, and the sanctioned anchor
  command forms. This skill is a freshness-gate **reader**: it never writes an
  anchor entry (REQ-F1.10 confines meaning-class writes to `/spec-kickoff`).
- `accumulator-taxonomy` — the `GATE(when:)` grammar, lanes, and drain
  semantics behind `--bookkeeping` and `/drain` (both share the
  `scripts/drain-gates.sh` evaluator; neither parses gates on its own).
- `finding-categorization` and `gate-wiring` — the pause protocol whose
  dispatched arm records a halt to `## Awaiting input`, and the act-then-review
  buckets `/execute-task` → `/polish` apply downstream.
- `proportionality` — bundling, dispatch ceremony, and reconcile caution scale
  with stake and reversibility; scoping is declared, never silent.

On a **dispatch path** (a step that selects and dispatches a unit), a missing
core doc fails closed (REQ-K1.7, the K1.7 amendment): orchestrating against a
contract whose defining rules cannot be read is the opaque failure. Halt with a
clear message naming the missing doc and the chain consulted. On the
**non-dispatching** paths (`--bookkeeping`, a read-only status step), a missing
doc degrades — note it in one line and continue with what remains possible.

## Modes

Selected from `$ARGUMENTS` at pre-flight:

- **Step** (default). Advance exactly one ready unit, then exit.
- **`--watch`.** Repeat the step until no ready unit remains or a halt fires.
  Event-driven under the subagent backend (wake on worker completion), a
  polling metronome under tmux (D-38). Each loop iteration is a full,
  independent, atomic step; `--watch` is a convenience over re-invocation, not
  a stateful long-running process.
- **`--bookkeeping`.** The out-of-session drain pass (D-31): reconcile merged
  PRs into `tasks.md`, evaluate open gates (no auto-drop), and surface the
  observations log's staleness. Dispatches nothing. See its own section.

Flags: `--backend <subagent|tmux|print|in-session>` overrides the configured
`dispatch_backend` for this run; `--unattended` selects headless mode (skip
confirms, route every would-be prompt to Awaiting input). Unattended mode is
implied when the session is non-interactive.

## Pre-flight (per step)

Run in order. Any halt records the unit (when one is selected) to the spec's
`tasks.md` `## Awaiting input` with the reason and ends the step — the
`gate-wiring` pause protocol's dispatched arm; in an attended session, present
the reason and wait instead. When several pre-flight halts fire at once
(not Ready or Active, missing validator, freshness), report them together (D-45).

1. **Parse `$ARGUMENTS`.** Extract the mode flags above and an optional spec
   path, given as `specs/<spec>` or the bare `<spec>`. Validate the `<spec>`
   segment against the anchored identifier pattern `^[a-z0-9][a-z0-9-]*$`
   (≤64 chars, REQ-A1.8) **before** it appears in any path or command; a
   failing token is never interpolated.
2. **Resolve the spec path**, trying in order: (a) an explicit spec-path
   argument; (b) the current branch parsed against `planwright/<spec>/task-<ids>`
   (D-36), giving `specs/<spec>/`; (c) the checkout when it holds exactly one
   `specs/*/` bundle whose `Status:` is `Ready` or `Active`
   (underscore-prefixed accumulators are not bundles); (d) ask, listing the
   available bundles. Verify the
   directory holds `requirements.md`, `design.md`, `tasks.md`, and
   `test-spec.md`.
3. **Resolve the doctrine docs** (above). Halt on a core-doc failure on a
   dispatch path; note a degraded doc on a non-dispatching path.
4. **Verify the spec is Ready or Active** (REQ-C1.1, superseding the bootstrap
   "non-Active" refusal — REQ-F1.4, REQ-J1.2, D-33; D-1). Read the
   `**Status:**` line in `requirements.md`. `Ready` (signed off, executable, no
   work started) and `Active` (work in flight) are both dispatchable; refuse
   Draft, Done, Retired, and Superseded. When the status is **Draft**, halt and
   prompt `/spec-kickoff`; for a terminal (Retired/Superseded) or Done spec, say
   plainly it has nothing to orchestrate. There is no bypass flag, and this skill
   **never** invokes `/spec-kickoff` itself (REQ-J1.3) — it names the command for
   the human to run. A `Ready` spec is dispatched on the same terms as an Active
   one: the execution freshness gate (the locked-window step below) still
   applies, so a Ready spec is executable only if its content anchor is
   execution-valid (REQ-C1.3); the Ready-or-Active gate and the freshness gate
   compose, neither replaces the other.
5. **Run the validator** (REQ-K1.7). `scripts/spec-validate.sh specs/<spec>`.
   On a dispatch step, a missing or non-executable validator **fails closed**
   and halts (REQ-A2.1's block-execution guarantee outranks degradation here);
   a Ready or Active bundle's findings are errors — surface and halt (Ready is
   signed-off live content, errors-block alongside Active, REQ-B1.2). On
   `--bookkeeping` the missing validator degrades with a message.
6. **Verify the kickoff brief** (D-36). `specs/<spec>/kickoff-brief.md` must
   exist and carry a final sign-off record with its anchor line. Absent or
   partial (the anchor-written-last ordering makes a killed kickoff
   indistinguishable from absent-anchor, by design): halt and prompt
   `/spec-kickoff`.
7. **Run the reconcile sweep** (REQ-F1.1). Before selecting new work, rebuild
   the picture from disk and reconcile stale In-progress entries — see the
   **Reconcile sweep** section. This recovers from a killed tower and is why a
   crashed step loses nothing.

## Selection (REQ-F1.2)

Pick the next ready unit with `scripts/orchestrate-select.sh specs/<spec>`. It
implements the critical-path-first rule deterministically: a **ready** task is
one in `## Forward plan` whose every dependency sits in `## Completed` (a task
that is In progress, Awaiting input, or terminal is not a candidate); among
ready tasks it returns the head of the effort-weighted longest dependent chain
(the unit unblocking the most downstream work), FIFO on ties. Section
membership is the canonical state, so the selector agrees with the content
anchor (the per-block Status annotation is advisory and not consulted).

- Exit 0 with an id → that is the unit (subject to bundling below).
- Exit 1 (no ready unit) → there is nothing to dispatch this step. In
  `--watch`, stop the loop; in a single step, report it and exit cleanly.
- Exit 2 (missing/taskless tasks.md) → fail closed; halt with the message.

**Selection-policy note (guard-infrastructure-first).** Critical-path-first is
blind to tasks that *gate other tasks' verification* but carry no dependency
edge from them (the 2026-06-11 field-trial miss: CI-guard tasks dispatched
after the tasks they protect). When the spec's prose or a task's `Done when:`
marks a unit as guard/CI infrastructure that everything else should merge
under, prefer it over the raw critical-path head and say so in the step
report. This is a judgment overlay on the script's ordering, not a silent
override.

**Cohesion-first bundling (REQ-F1.7, D-9).** Consider bundling the selected
unit with the next consecutive ready task(s) **only** when together they form
one coherent, revertable, single-purpose deliverable (same module/concern,
shared dependencies). Combined size is a guardrail against bloat, not the
primary signal. Non-cohesive ready tasks ship as separate units/PRs. A bundle
takes a single `planwright/<spec>/task-<id>-<id>` branch (D-36).

## Worktree create / reuse (REQ-F1.8, D-37, D-44)

Create the unit's worktree through Claude Code's **native** mechanism
(`claude --worktree` / `EnterWorktree` / the Agent tool's worktree isolation)
— planwright **never** shells out to `git worktree`. Placement is always
`<repo>/.claude/worktrees/<branch-suffix>`, so the worktree is attachable via
`claude --worktree <name>` regardless of which backend launches the work; the
placement convention is the contract, the launch mechanism incidental. Reuse
the current worktree when it is clean, after a one-line confirm (**attended
only**; unattended mode always creates a fresh worktree). Print the re-open
command after create-or-reuse.

**Dispatch-time environment hardening** (2026-06-12 field trial): when the
backend spawns a process (tmux pane, subagent), launch it through the
umask-pinning wrapper, pre-trust the worktree's config paths (so a fresh
worktree needs no per-worktree `mise trust`), and verify the SSH-agent
indirection is alive before any signed state-move commit. A recovered tmux
server once spawned panes under a wrong umask and broke every scratch dir; a
stale forwarded agent socket once broke commit signing across every worker.

## The state move (the locked window) — REQ-F1.3, REQ-F1.9, D-10, D-41

This is the only serialized part of a step. Do it in this order, holding the
per-spec lock across the freshness gate **and** the `tasks.md` update so the
two are atomic against a concurrent tower or the `tasks-pr-sync` hook:

1. **Acquire the lock.** `scripts/orchestrate-lock.sh acquire specs/<spec>`.
   Exit 1 (another live holder) is a **clean no-op**: skip this step, another
   tower or the hook holds it; `--bookkeeping` reconciles anything dropped.
   The lock path and mkdir protocol are shared with `tasks-pr-sync.sh` (risk
   row 18) so they exclude each other.
2. **Run the execution freshness gate** (REQ-F1.9, REQ-F1.10, D-45), **inside
   the lock, immediately before the update**. This stops dispatch against spec
   content that changed since the brief was last signed:
   - Read the brief's **most recent anchor entry** and the four spec files
     **from the primary checkout's main view** (a worker compares its
     worktree's spec against main's brief; divergence in either direction
     halts).
   - **Parse and validate the entry**: execution-valid only if it parses, uses
     a **sanctioned command form** (`scripts/spec-anchor.sh <spec-dir>`, or the
     interim whole-file form the meta-spec still sanctions), was written by a
     **sanctioned writer** (a `/spec-kickoff` sign-off for meaning-class, or
     the marked `Class: expression-only` ritual), and — for meaning-class —
     carries a dispositioned `Lens-pass:` reference.
   - **Recompute** with the exact command the entry records and compare.
     **Match** → proceed. **Mismatch** (any anchored content changed, committed
     or not) → halt, remedy: a `/spec-kickoff` delta re-walkthrough. **No entry
     / unparseable / non-sanctioned command / non-sanctioned writer** → halt,
     remedy: complete or repair the sign-off record per REQ-F1.10. Every halt
     is to Awaiting input naming its remedy. No bypass flag.
3. **Move the unit to In progress.** Relocate each task block to
   `## In progress` and write the dispatch metadata annotations:
   `- **Status:** implementing`, `- **Last activity:** <today>`, and a
   `- **Dispatch:**` line recording the backend, the dispatch timestamp, and
   the worker handle/window name (REQ-F1.1). These annotations and the section
   move are **excluded from the content anchor** (`scripts/spec-anchor.sh`
   strips placement and Status/Dispatch annotations), so the move never trips
   the gate that just ran — which is why this skill writes **no** anchor entry
   for a state move (the canonical extraction superseded the interim
   whole-file re-anchor ritual; observations 2026-06-11/06-12).
4. **Auto-commit the move** (D-41) when `commit_on_state_move` is true (read
   via `scripts/config-get.sh commit_on_state_move`; local override wins,
   absent/malformed falls back to the default with a one-line warning). Use a
   fixed conventional message (e.g. `chore(orchestrate): dispatch task <id>`).
   Commit only — **never push** (push, sign-off, merge stay human).
5. **Release the lock** before dispatching:
   `scripts/orchestrate-lock.sh release specs/<spec>`. The lock is held only
   across this move, never across execution (D-10), so it never serializes the
   workers.

## Dispatch (REQ-F1.8, D-38)

Dispatch the unit's `/execute-task <ids>` into its worktree via the configured
backend (`scripts/config-get.sh dispatch_backend`, overridable with
`--backend`). Concurrency is capped by `max_parallel_units` (default 3, via
config-get): if that many units are already In progress for this spec, do not
dispatch another — report the cap and exit. Division of labor (2026-06-12
field trial): **the tower owns** `tasks.md` state moves, dispatch, and
merged-window cleanup; **the worker owns** its branch's commits and conflict
resolution. The tower relays clearly-attributed instructions to a worker but
never answers a worker's permission prompts and never types into a worker's
input line.

- **subagent** (default). A background worker with isolated context and a
  native worktree per unit; completion notifies the tower; the worker's
  questions funnel to the tower's single prompt queue. The shipped
  worker-settings profile (`config/worker-settings.json`) pre-approves the
  routine `/execute-task` toolset — and denies the merge/force-push/amend
  guardrails — so routine units complete without permission prompts; a human
  merges it into the worker's settings (planwright never edits settings.json,
  REQ-I1.2).
- **tmux** (opt-in). An interactive worker in a named window via
  `claude --worktree`. Detect stuck/finished/errored workers with
  **capture-pane only** — **never** send-keys impersonation (an unauthorized
  screen-scrape with no audit trail; the worker-settings profile is the
  sanctioned way to remove routine prompts). Relay attributed messages via
  tmux `load-buffer`/`paste-buffer` (send-keys mangles quoted payloads).
- **print**. Prepare the unit, print the exact launch command, and exit —
  zero-dependency manual dispatch. The human pastes the command; no process
  exists until they do (which the orphan predicate accounts for).
- **in-session**. Run `/execute-task` in this session, no separate worker.

**Unattended mode** (headless: cron/launchd/CI, or `--unattended`). Skip every
confirm, always create fresh worktrees, and route **every** would-be prompt to
an `## Awaiting input` entry rather than blocking on it. This is the
scheduled-autopilot path; a human drains the Awaiting-input queue later.

## --watch

Loop the full step (pre-flight → reconcile → select → state move → dispatch)
until selection reports no ready unit or a halt fires. Event-driven under the
subagent backend (wake on a worker-completion event), a polling metronome
under tmux.
Each iteration is independent and atomic; the loop holds no state between
iterations beyond what is on disk. A halt in any iteration ends the loop and
surfaces the reason.

## Reconcile sweep (REQ-F1.1, the tightened predicate)

Rebuild from `tasks.md`, `gh`, and the process/window list, then for each
`## In progress` entry:

1. **Reconcile PR state first.** A PR in any state for the unit's branch takes
   precedence: **merged → move to Completed** (with the merged annotation);
   **open → leave In progress**. Only when no PR resolves the unit do you
   consider orphaning.
2. **Orphan only when all hold** (else leave it alone):
   - the entry is **older than the grace threshold** (default: the stale-lock
     threshold, D-10);
   - the backend's **liveness is observable from this session** (subagent /
     tmux / in-session — a worker dispatched by *another* tower is not yours to
     judge; **print-backend units are exempt**: no process exists until the
     human pastes the command, so they age out only via the threshold **plus a
     human confirm**);
   - there is **positive evidence of death** — the recorded worker
     handle/window is **gone**, not merely unobserved. A dead tmux socket or a
     truncated process listing is *lost observability*, not observed death
     (2026-06-12 field trial: that exact confusion nearly orphaned live
     workers). Distinguish the two before orphaning; when you cannot, do not
     orphan.
3. **An orphan moves to `## Awaiting input`** with an orphan note — never left
   In progress silently (which would stall dependents invisibly) and **never
   auto-re-dispatched** (re-dispatch is a human call after they see the note).

## --bookkeeping (REQ-H1.4, D-31)

The out-of-session drain pass. Dispatches nothing; it:

1. **Reconciles merged PRs** into `tasks.md` (the same merged → Completed move
   the `tasks-pr-sync` hook performs in-session, for events the hook dropped on
   a busy lock).
2. **Evaluates open gates** with `scripts/drain-gates.sh specs/` — the shared
   evaluator `/drain` also uses. **Nothing is auto-resolved or auto-dropped**
   (REQ-H1.4): a satisfied gate is **re-surfaced** for a human to act on, not
   closed. Read `accumulator-taxonomy` before interpreting the lanes.
3. **Surfaces observation staleness**: report the observations log's unmined
   count and oldest-entry age (seed pressure for the next `/spec-draft`).

On `--bookkeeping`, missing prerequisites degrade with a message (it is not a
dispatch path); it still never merges and never pushes.

## Halt → Awaiting input (REQ-F1.5)

Halt to Awaiting input on ambiguity, a missing dependency, a worker test
failure surfaced back, a hard-disqualifier, or contract drift — non-exhaustive;
the pre-flight refusals (not Ready or Active, missing validator, freshness gate)
are defined at their own steps. Each halt writes the unit to `## Awaiting input`
with the reason (the pause protocol's dispatched arm); attended, present it and
wait. In unattended mode every would-be prompt becomes an Awaiting-input entry.

## Stop conditions (mandatory human handoff)

| Condition | Trigger |
| --- | --- |
| Spec not Ready or Active | Pre-flight step 4 found a status outside {Ready, Active} (Draft, Done, Retired, Superseded). Prompt `/spec-kickoff` for Draft; never auto-chain. |
| Missing/erroring validator | Pre-flight step 5 on a dispatch path: absent/non-executable, or a Ready/Active bundle's errors (fail closed). |
| No / partial kickoff brief | Pre-flight step 6 found no brief or a brief without its anchor line. |
| Freshness-gate halt | The locked-window gate: anchor mismatch, or an absent / unparseable / non-sanctioned / wrong-writer entry. |
| Taskless / unreadable tasks.md | Selection exit 2. |
| Lock contention | `acquire` exit 1: clean no-op, skip the step (bookkeeping reconciles). |
| Cohesion ambiguity | Bundling admits multiple valid groupings; surface and ask. |
| Worker halt relayed | A dispatched worker halted to Awaiting input; the tower records it, does not re-dispatch. |
| `gh` unreachable | A reconcile/PR read needs `gh` and it is unauthenticated; record Awaiting input, continue local work (REQ-K1.6, K1.7). |

## Invariants

These hold at every step:

- **Never** act on a spec whose status is neither Ready nor Active (REQ-C1.1,
  superseding the bootstrap non-Active refusal REQ-F1.4, REQ-J1.2, D-33);
  **never** bypass the execution freshness gate (REQ-F1.9), which composes with
  the Ready-or-Active gate and applies to a Ready spec exactly as to an Active
  one (REQ-C1.3). No bypass flag exists for either.
- **Never** auto-chain into `/spec-kickoff` (REQ-J1.3) — name the command, do
  not run it.
- **Never** merge a PR or mark one ready for review, and **never** create a
  non-draft PR (REQ-J1.1, REQ-F1.6) — `/execute-task` opens drafts; the
  draft→ready flip and the merge are the human's.
- **Never** push, force-push, amend, squash, or rebase; state moves are local
  commits only (REQ-J1.4, D-41).
- **Never** create a worktree by shelling out to `git worktree`; use the
  native mechanism and the `.claude/worktrees/` placement (D-37).
- **Never** answer a worker's permission prompt or type into its input line;
  detection is capture-pane only, relay is buffer-paste only (D-38).
- **Never** auto-resolve or auto-drop a gate in `--bookkeeping` (REQ-H1.4) —
  re-surface only.
- **Never** orphan an In-progress unit without PR-state-first reconciliation,
  the grace threshold, an observable backend, and positive evidence of death
  (REQ-F1.1).
- **Never** write an anchor entry: this skill is a freshness-gate reader, not a
  sanctioned anchor writer (REQ-F1.10). Its state moves are anchor-excluded by
  construction.
- **Never** hold the per-spec lock across execution; only across the
  freshness-gate-plus-update window (D-10).

## Observations

`/orchestrate` only runs on a Ready or Active planwright spec, so `specs/` and the
observations log necessarily exist. When something outside the current step's
scope surfaces — a selection-policy gap, a dispatch-backend rough edge, a
config-model wrinkle, a drift in a shared script — append one line to
`specs/_observations/opportunities.md`, format
`- <YYYY-MM-DD> [<repo>] <observation>`, and commit the append within the step
that produced it so the tree returns to clean. Do not act on observations
during the step; they are seed material for `/spec-draft`, the log's canonical
reader.

## Maintenance

After the run completes (or halts), compare these instructions against the
resolved doctrine docs (REQ-B3.2, D-42) — especially `spec-format` (anchor
command forms, sign-off record format), `accumulator-taxonomy` (gate grammar
and drain semantics), and `gate-wiring`. If a concept this skill names has
changed meaning, gained or lost a step, or moved between docs, append a drift
observation to `specs/_observations/opportunities.md` (format above, prefixed
`skill-drift(orchestrate):`), commit it as its own chore commit, and tell the
user what drifted. Do not edit this skill or the doctrine docs to resolve the
drift; the observation log's reader owns folding drift into spec amendments.
