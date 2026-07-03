# Context-Budget Monitoring & Disposable-Tower Auto-Heal (`continue-as-new`)

A long-running orchestration tower faces a failure its worker sessions do not: it
runs step after step in **one** session, and that session's context window fills.
Left unmanaged, the tower degrades silently — it starts forgetting the early
picture, then compacts lossily, then makes worse selections from a blurred view.
This doctrine gives the tower one defence: **monitor its own context budget**, and
before the budget runs out **auto-heal** by handing off to a fresh tower that
rebuilds the whole picture from durable state. The pattern is Temporal's
**`continue-as-new`**: a fresh execution that carries only essential state, so
history stays bounded. Auto-heal is simply *the disposable tower planwright
already relies on, triggered by a context-budget signal instead of by a human*.

Citations: orchestration-fleet REQ-C1.1 (monitor the budget, surface the
near-limit), orchestration-fleet REQ-C1.2 (auto-heal handover), orchestration-fleet
REQ-C1.4 (the handover preserves the sibling state-safety contract),
orchestration-fleet REQ-A1.2 (the never-auto-merge floor holds across the
handover) · orchestration-fleet D-4 (extends bootstrap D-7 disposable towers; the
handover launch relates to bootstrap D-38 dispatch). The unattended fresh tower
operates under the
[Autonomous-Safe-Decision Policy](autonomous-safe-decision.md).

## The budget signal: a completed-step-count proxy

The honest constraint first: **Claude Code exposes no supported way for a session
to read its own context-window usage.** There is no environment variable, no hook
input field, and no CLI query for "tokens used" or "budget remaining"; `/context`
is interactive-only and not machine-readable. The session transcript
(`~/.claude/projects/<project>/<session-id>.jsonl`) *does* carry per-message token
usage, but its schema is documented as internal and version-unstable — so parsing
it is a **rejected antipattern**: it would break on any Claude Code release, and a
monitor that silently breaks is exactly the silent degradation this doctrine
exists to prevent.

What a tower *does* reliably have is a count of the **orchestration steps** it has
completed since it started — one increment per orchestration step (each `--watch`
loop iteration, dispatch or not), wholly under its own control and identical on
every backend. So the budget signal is a
**completed-step-count proxy**: the tower hands off after a configured number of
steps. It is not a token measurement; it is a bounded, portable, deterministic
stand-in for one. Because the handover is cheap and lossless (below), the proxy
does not need to be precise — only conservative.

- **The knob.** `context_budget_threshold` (config, four-layer overlay) is the
  step budget: a positive integer of at most 15 digits (an overflow guard that
  only rejects typos far larger than any real budget), or `off` to disable
  auto-heal (the historical single-tower behavior). Its default is deliberately
  conservative — handing off
  *early* wastes only a cheap rebuild, while handing off *late* risks the silent
  degradation REQ-C1.1 forbids, so the safe default is the low one. Resolved
  through `scripts/resolve-context-budget-threshold.sh`.
- **The monitor.** `scripts/context-budget-monitor.sh <steps-completed>` compares
  the tower's step count against the resolved threshold and prints `near-limit`,
  `ok`, or `disabled`. The tower consults it each step; `near-limit` is the
  auto-heal trigger. This is the surfaced near-limit condition REQ-C1.1 requires.
- **The corroborating native hard-floor (optional).** Claude Code's documented
  `PreCompact` hook fires when auto-compaction is about to run — that *is* Claude
  Code's own "budget exhausted" event, and it is the one native, stable signal.
  Its limits: it fires *at* the threshold rather than before it, and a tower whose
  step budget is well-tuned reaches `near-limit` first. A tower operator who wants
  a belt-and-suspenders floor may register a `PreCompact` (matcher `auto`) hook in
  **their own** worker settings that writes a hand-off marker their own tower
  wake-loop can treat as an immediate hand-off signal (this monitor evaluates the
  step-count threshold only; marker-reading is the operator's wiring, not shipped
  here). planwright does **not** register this hook in its
  plugin `hooks/hooks.json`: a global hook would fire for every adopter's every
  session, not just towers, and bound blast radius matters more than catching the
  rare case where the step budget is mis-tuned high.

## Why rebuild-from-disk, not summarize-in-place

The rejected alternative is a long-lived tower that compacts or summarizes its own
context to keep going. It is rejected for two reasons. It reintroduces the fragile
long-running-state model bootstrap D-7 deliberately avoids; and summarization
loses fidelity silently, whereas **rebuild-from-disk is lossless because the disk
is the source of truth.** The tower already holds no authoritative state in memory
— every picture it acts on is derived from `tasks.md`, `gh`, the branch/marker
state, and the worker list. So a fresh tower reconstructs the *same* picture the
retiring one held, with none of the accumulated context. The resilience property
falls out of the design planwright already has (the sibling's level-triggered
reconcile, orchestration-concurrency D-1): the fresh tower's rebuild is the exact
routine any restart runs.

## The handover (`continue-as-new`)

When the monitor reports `near-limit`, the retiring tower performs the handover.
Its **only** job is to start the replacement and stop; it passes **no in-memory
state**.

1. **Finish or leave the current step atomically.** Every step is
   crash-safe on its own (bootstrap D-8), so the tower either completes the
   in-flight step or leaves it exactly as a crash would — the reconcile handles
   both. It does not start a new dispatch once it has decided to hand off.
2. **Start the fresh tower.** Launch a new top-level session (headless
   `claude -p "<wake prompt>"` is the documented path; `--output-format json`
   returns its session id) seeded with the tower's **standing instructions / wake
   prompt**. That prompt **is** the handover document — there is no second
   artifact to keep in sync (REQ-C1.2; the operational-protocol seed found the
   wake prompt already *is* the handover). The fresh tower's first act is the
   reconcile sweep, which rebuilds the picture from disk.
3. **Confirm the fresh tower is alive before retiring (R12).** The retiring tower
   does **not** stop until it has positive evidence the replacement is running
   (the session id came back, the process is live). If the launch fails, it does
   **not** retire into a zero-tower gap: it escalates to `tasks.md` `## Awaiting
   input` and stays up (or stops loudly) so a human restarts. Never retire the old
   tower on faith that the new one started.
4. **Retire.** Once the replacement is confirmed live, the retiring tower stops.
   The fresh tower now owns the work, with a full context window.

**The dead-window (R7).** If the retiring tower dies *after* deciding to hand over
but *before* the fresh tower starts, no state is lost: nothing authoritative lived
in the retiring tower, and the level-triggered reconcile re-derives the whole
picture on the next tower start (the next `--watch` invocation, a human, or a
supervising meta-tower). The window is survivable by construction because the
recovery routine is the same routine as normal operation.

**The snapshot test.** The handover is correct exactly when a fresh tower can
resume from durable state *alone* — the "could a fresh tower resume from this
alone?" check (REQ-C1.2). If any handover would require passing in-memory context
the fresh tower cannot reconstruct from `tasks.md` + `gh` + the branch/marker +
worker list, that is a design bug in the handover, not a reason to pass state.

## State-safety across the handover (REQ-C1.4)

Auto-heal must not become a path that corrupts the derived-projection contract the
sibling `orchestration-concurrency` owns. Two rules hold, for both the retiring and
the fresh tower:

- **`tasks.md` placement only through the level-triggered reconcile.** Neither
  tower writes dispatch or progress state into `tasks.md` by any path that bypasses
  the sibling's reconcile. The handover moves no task between sections; the fresh
  tower's reconcile derives placement from evidence (branches, markers, merged PRs)
  exactly as any step does.
- **The per-spec advisory lock guards every state move.** A fresh tower acquires
  the sibling's per-spec advisory lock before any state move, the same as a
  first-run tower. The handover does not inherit or transfer a held lock; the
  retiring tower releases whatever it holds as it stops, and the fresh tower
  acquires cleanly. Two towers briefly coexisting (old not yet retired, new
  reconciling) is safe precisely because the lock and the derived projection make
  concurrent readers race-free.

## The floor holds: never auto-merge

The handover changes which session is orchestrating; it changes nothing about what
a tower may do. The fresh tower inherits every invariant — never auto-merge, never
force-push, never mark a PR ready — and operates under the same
[Autonomous-Safe-Decision Policy](autonomous-safe-decision.md) as any unattended
tower (orchestration-fleet REQ-A1.2). Auto-heal is a resilience mechanism beneath
the autonomy ceiling, never a loophole through it: no number of handovers promotes
a draft PR to merged.
