# Accumulator Taxonomy & the Drain Discipline

An accumulator is any surface that collects deferred work or decisions. The
invariant this document enforces is **no write-only deferral** (REQ-H1.2):
every surface that can defer a decision or work has a durable home, a named
reader or owner, and a re-surfacing gate or drain ritual. A deferral that
nobody is guaranteed to read again is not a deferral; it is a silent drop
with extra steps. This document names the accumulator classes and their
drain rituals, defines the `GATE(when:)` convention and its closed grammar
(this is the normative home for the productions), and specifies the drain
pass that `/drain` and `/orchestrate --bookkeeping` share.

Citations: REQ-H1.1, REQ-H1.2, REQ-H1.3, REQ-H1.4, REQ-H1.5 · D-17, D-18,
D-31.

## The three classes

Every staging or accumulator surface is classified into one of three classes
(REQ-H1.1, D-18). The class determines the drain ritual; the ritual is what
makes the no-write-only-deferral invariant enforceable instead of
aspirational.

1. **Self-draining live state.** Drains automatically as part of the
   mechanism that wrote it; no reader has to remember anything. Examples:
   the per-spec advisory lock (released when the state move completes,
   stale-broken at the D-10 threshold); a worktree's handover brief
   (consumed by `/resume` at the next session start). Ritual: the mechanism
   itself. A failure to drain here is a bug in the mechanism, not a process
   gap.

2. **State-machine durable state.** Drained by named skill or hook
   transitions between defined states. Examples: `tasks.md` sections (task
   blocks move Forward plan → In progress → Completed via `/orchestrate`
   and the PR-sync hook); the pending-sign-off checklist in a draft PR body
   (drained by the human at PR review); Awaiting-input entries (drained when
   the human supplies the input and the task re-dispatches). Ritual: the
   transition that owns each move, with the bookkeeping pass reconciling
   moves that happened out of session.

3. **Manually- or condition-drained seed accumulators.** Collect material
   until a canonical reader consumes it or a gate re-surfaces it; nothing
   drains them as a side effect, which is exactly why each one must name its
   reader and its re-surfacing ritual. Examples: the observations log
   (`specs/_observations/opportunities.md`; canonical reader `/spec-draft`,
   REQ-H1.6, with the drain pass surfacing its unmined count and age);
   `_pending/notes.md` (local-only, gitignored; owner: the human who wrote
   it); `tasks.md` Deferred entries (re-surfaced by their `GATE(when:)`
   conditions through the drain pass). Ritual: the `GATE(when:)` convention
   plus the drain pass, and the canonical reader for seed material.

**Classification rule for new surfaces.** Before introducing a surface that
can hold deferred work or decisions, name its class, its durable home, its
reader or owner, and its drain ritual. A surface for which any of those four
cannot be named is a write-only deferral and must not be introduced
(REQ-H1.2).

## The `GATE(when:)` convention

A deferral is recorded as a structured `GATE(when: …)` entry inline in the
relevant file, on the Deferred entry it gates (REQ-H1.3; the entry format
and its location in `tasks.md` are fixed by the
[spec format meta-spec](spec-format.md)). Condition gates are preferred over
date gates: a condition states what must become true, a date only guesses
when that might happen.

### Grammar (normative)

Gate conditions use a closed declarative grammar. These productions are the
normative definition; the evaluator parses by pattern match against them and
nothing else.

```text
gate        = "GATE(when: " condition ")"
condition   = atom *( " and " atom )
atom        = task-atom / status-atom / date-atom

task-atom   = "task " task-id " completed"    ; a task in the same bundle,
task-id     = 1*DIGIT ["." 1*DIGIT]           ; by its stable id

status-atom = "spec " spec-id " " status      ; a bundle's status,
spec-id     = lowercase / digit, then         ; identifier per REQ-A1.8
              lowercase / digit / "-", max 64
status      = "draft" / "active" / "done" / "retired" / "superseded"

date-atom   = "after " full-date              ; full-date = YYYY-MM-DD
```

`and` of atoms is the only combinator. There is no `or`, no negation, no
grouping, and no other atom form. The grammar ends at the closing
parenthesis: apart from a final period, trailing content after it is
malformed, not ignored. Whitespace around the condition is insignificant
(the space after `when:` is conventional, not load-bearing). A date atom is
*reached* on or after the named day, inclusive. A condition that cannot be
said in this grammar is written as a **free-text gate** instead: plain
prose after `**Gate:**`, surfaced verbatim and never evaluated (the same
posture as date gates — the machine reports it; a human judges it). One
gate per deferral entry.

### Lanes and evaluation semantics

The evaluator sorts every gate into exactly one lane:

- **Condition gate** — a structured gate whose atoms are all task or status
  atoms. Evaluated: when every atom is true the gate is **satisfied** and
  the item re-surfaces; otherwise it is **pending**, reported with its unmet
  atoms.
- **Date gate** — a structured gate containing at least one date atom (alone
  or `and`-ed with condition atoms). Date gates **only surface, never
  hard-fail** (REQ-H1.3): when every atom is reached or true the item is
  **surfaced** as a reminder needing human attention; otherwise it is
  **dormant**. A reached date is never reported as satisfied — a date
  proves nothing about the world — and never as an error. (The hard-fail
  anti-pattern is the expiring TODO that breaks the build on a guessed
  date.)
- **Free-text gate** — gate text not in the structured form. Surfaced
  verbatim, never evaluated.
- **Malformed gate** — a structured gate that fails the grammar:
  unterminated, an empty condition, trailing content after the closing
  parenthesis, an unrecognized atom or combinator, a calendar-invalid
  date, or a reference to a task id or spec that does not exist (a
  condition that can never come true is a write-only deferral in
  disguise). A `**Gate:**` line outside any deferral bullet is malformed
  too — never silently dropped. Malformed gates are **drain-report-level
  errors**: reported as errors (every defective atom named), never
  evaluated, never silently skipped — and the pass completes; nothing
  blocks (REQ-H1.3).

### Confidence levels

A Deferred entry that records a decision carries
`Confidence: <high|medium|low>` (REQ-H1.5; entry format in the meta-spec).
The token is matched as a whole word in the entry text before the gate
marker — `Confidence: lowest` or a mention inside gate text never counts.
The drain report orders items within each lane of each spec's section by
confidence — low, then medium, then high, then unspecified — so
low-confidence deferrals resurface first: the less sure the deferral was,
the sooner a human should look at it again. (A consumer merging lanes
across specs re-sorts by the report's `[confidence]` tag.)

### Data-only handling

Gate content is untrusted data (REQ-H1.3). The evaluator parses by pattern
match against the closed grammar and treats gate text as data only: never
passed to `eval`, a subshell, or arithmetic expansion; never used as a
pattern, format string, or unquoted argument (`--` discipline); control
characters stripped when echoed — C0 (minus newline), DEL, and the C1
range 0x80-0x9F
(8-bit CSI), accepting that a multibyte character using C1 continuation
bytes degrades rather than reaching the terminal as a control sequence. A
hostile gate is at worst malformed or
free-text — surfaced inert, never executed. The
[security posture](security-posture.md) doctrine's framework-script rules
apply to the evaluator itself.

## The drain pass

One evaluator, two entry points (REQ-H1.4, D-17, D-31):
`scripts/drain-gates.sh` is invoked on demand by `/drain` and as part of the
scheduled `/orchestrate --bookkeeping` sweep. Both produce the same report;
neither may bypass the evaluator with its own parsing.

The pass:

- **Sweeps every spec bundle** under the specs root, whatever its status —
  gates outlive Done (a Done bundle's Deferred entries still re-surface).
  Underscore-prefixed accumulator directories are not bundles and are not
  swept for gates.
- **Never auto-resolves and never auto-drops** (REQ-H1.4). The sweep is
  read-only: re-surfacing means reporting. Acting on a surfaced item —
  un-deferring the work, recording the decision, re-gating with a new
  condition, or removing the entry — is an edit a human makes or sanctions.
  The bookkeeping pass may move a re-surfaced item to Awaiting input or
  flag it in its report, never to In progress (D-17).
- **Surfaces the observations log's state** (REQ-H1.4, surface only): the
  unmined entry count and the oldest entry's age. Mining the log remains
  its canonical reader's job (`/spec-draft`, REQ-H1.6).
- **Completes regardless of malformed gates**: a malformed entry is report
  content tallied under the `malformed:` summary field (the separate
  `errors:` field counts unreadable, NUL-carrying, or mid-sweep-changed
  files). The evaluator exits non-zero when it cannot run (unusable specs
  root, usage error) or cannot complete the sweep.

Report lines are keyed by lane (`SATISFIED`, `SURFACED`, `PENDING`,
`DORMANT`, `FREE-TEXT`, `MALFORMED`) with the entry's file and first line,
the entry title, and its confidence, so both a human and a calling skill
can act on the report without re-parsing gates. A complete report always
ends with the `== summary ==` section; a sweep that cannot complete exits
non-zero instead of emitting a partial report, so a report missing its
summary is a bug, not a result. The evaluator evaluates each swept file
from a single read, bracketed by digest checks that flag a file whose
content differs between the start and end of the parse as a report-level
error rather than trusting possibly torn rows (a rewrite restoring
identical bytes within the window is below the check's resolution; the
writer-side lock is the orchestration layer's concern, not the read-only
evaluator's). Spec-status atoms evaluate against a snapshot taken at sweep
start.
