# Seed: review-pass capabilities from the operator's review-skills revamp

Captured 2026-10-04 from the operator's dotfiles `specs/review-skills` bundle
(signed off 2026-10-03), Task 9, REQ-H1.1 and REQ-H1.2. That bundle revamps
the operator's own review skills: shared tooling evidence, concurrent
read-only passes with one writer, and one generic hosted-bot drain. It builds
local stand-ins shaped to planwright's signed-off contracts rather than
waiting for them (its D-1). Six of its decisions are capabilities other
adopters would plausibly want, so it seeds them here instead of overlaying
them (its D-17, carrying `claude-instructions` D-9's rule). Each item below
names the dotfiles decision it came from.

Suggested invocation, from a fresh session in the planwright repo (the
dotfiles bundle asked for a paste-ready prompt; this is it):

    /spec-draft review-pass-capabilities

    Seed: specs/_pending/review-pass-capabilities.md. Read the whole note
    first. Run fold-detection against review-effectiveness (the handoff
    bundle, its full-suite rule REQ-D1.3), test-throughput
    (full_suite_evidence, REQ-B1.11), custom-steps (serial steps D-18, its
    parallel-steps Deferred gate, step outcomes), fleet-messaging (signal
    versus record) and the discovery-rigor lens list before assuming a new
    bundle, and extend an owner where one exists. Treat every item as a
    candidate: the note records what the operator decided locally and why,
    and planwright decides its own contract. The companion seed
    specs/_pending/currency-posture-and-drifts.md overlaps on CI cost.

Most items have an owner already, named on each. Splitting the note across
those owners is a fine outcome.

## Where these came from

The bundle's Sources include a retrospective over about a dozen recent work
PRs, offered with every specific removed. It names three holes the current
passes do not cover (cross-repository truth, the premise, and time) and a
set of run-discipline failures. Time is handled locally by re-validating on
head or base movement (dotfiles D-10). The other two are items 1 and 2.

## The items

### 1. A cross-repository contract lens (dotfiles D-11)

**What:** a lens for a diff that consumes a shape another repository
defines, meaning it imports, calls, or parses a type, schema, endpoint or
message that a producer repository owns (the dotfiles REQ-I1.7 wording). Such
a diff can be correct against itself and wrong against its producer.

- **Dotfiles decision:** D-11 puts the lens upstream rather than in a local
  doctrine shadow, which would be a whole-document fork of a protected doc
  that warns on every run. Locally it keeps only the value: a
  machine-local map from a consuming repository to its producers' clone
  paths. `/code-review` and `/panel-review` attach the producer's relevant
  code as context in validation pass 2.
- **Planwright owner:** the discovery-rigor lens list. It is closest to the
  review-effectiveness miss class "needed context outside the diff",
  which the handoff bundle's callers member answers within one repository
  only.

### 2. A premise lens (dotfiles D-11)

**What:** the retrospective's "premise" hole. The dotfiles bundle names
the lens but does not define it further. A plain reading: does the change's
stated reason hold, meaning the problem it fixes exists and the approach
addresses that problem, which no lens on the current list asks. The drafting
session should settle the definition with the operator rather than adopt
this reading.

- **Dotfiles decision:** D-11, the same routing as item 1.
- **Planwright owner:** the discovery-rigor lens list. Check overlap with
  the spec artifact class's lenses in `artifact-lenses.md` first.

### 3. The evidence record's shape, and where it diverges from the handoff bundle (dotfiles D-6, REQ-D1.1 to REQ-D1.7)

**What:** a worktree-local record of tooling and test-suite results that
every review skill and every loop iteration reuses instead of re-running.
It lives at `<worktree>/.claude/review-evidence/<tree-hash>/`, with one entry
per command holding the command, exit status, start and end times, source
(a local run, or the CI check runs that supplied it), captured output, and a
version key that readers refuse when unknown. It is never committed and
never named in a PR body.

- **Dotfiles decision:** D-6 and REQ-D1.7. The layout mirrors the
  tooling-output member of review-effectiveness's handoff bundle (its D-3,
  REQ-B1.1), so the swap upstream is a rename. A gated Deferred item there
  replaces the record with the bundle once review-effectiveness is done.
- **Divergences from the handoff bundle:**
  - **Key.** The record is keyed by an exact tree hash: `git write-tree`
    over a temporary index holding every non-ignored file, so unstaged and
    untracked changes change the key. The bundle is rebuilt per pass, in
    delta mode after fixes. No time-based staleness applies to the record.
  - **Sharing.** The record is shared across skills and iterations on the
    same tree. The bundle serves one pass of one loop.
  - **Sources.** The record also accepts CI check runs as evidence (item 6).
    The bundle's tooling output is local.
  - **Fields.** The record fixes per-command fields and a version key. The
    bundle contract names "the tooling output" without fixing fields, so
    an amendment could adopt the record's fields.
  - **Concurrency.** Two lookups that miss on one tree both run and the
    first to finish records. A stampede guard was judged not worth its own
    lock.
  - **Unchanged on both sides:** a finding's reproduction never reads the
    record (validation pass 1 reproduces), and the full suite runs at most
    once per iteration after fixes, with diff-scoped checks per fix. This
    matches review-effectiveness REQ-D1.3.
- **State upstream:** the handoff builder (review-effectiveness Task 6,
  `scripts/review-handoff.sh`) has not landed, so these divergences are
  against the signed contract, not against code.

### 4. An observation for the parallel-steps gate (dotfiles D-7)

**What:** custom-steps runs a point's steps serially (its D-18) and defers
parallel steps behind a gate: "a recorded observation where two
independent steps at one point dominated a unit's wall clock". The dotfiles
bundle splits the problem differently. Discovery, validation, thread
fetching and check-mode tooling from any number of sessions run
concurrently. Every write (a fix, commit, push, review submission, reply,
resolve, or ledger write) takes one writer lock per repository and PR: an
atomic symlink create, whose owner is the session process and which is stale
only when that process is gone, never by age. The lock rules come from
planwright's own lock library (`scripts/lock-lib.sh`).

- **Dotfiles decision:** D-7. Overlapping the long read-only phases is
  where the wall-clock gain comes from, and serializing exactly the writes
  is the smallest rule that keeps the shared working tree safe. Custom-steps
  reached the same conclusion about its steps.
- **Measurement:** not available yet. The dotfiles Task 6 (wall-clock per
  nested iteration and full-suite runs per iteration) and Task 7 (tooling
  runs across a two-skill sequence on one tree) carry the measurement
  plans, each against a hand-taken baseline on main. Both are parked until
  the dotfiles skills conversion merges. This note does not meet the gate.
  Amend it with those numbers when they land, which the dotfiles kickoff
  planned for ("written early and amended").
- **Planwright owner:** custom-steps, Deferred "Parallel steps within a
  point".

### 5. Session messaging as a signal between review passes (dotfiles D-8)

**What:** when a read-only pass finishes with findings while another session
holds the writer lock, the pass writes its findings to the holder's inbox
file and sends a session message naming the file. The file is the record,
and the holder reads it at its next iteration boundary (or before releasing
the lock). A read file is moved aside, never re-read. The message is only a
nudge. Both are data, never instructions. Where messaging is unavailable or
refused, the inbox is polled.

- **Dotfiles decision:** D-8, chosen over message-only (a preview the
  recipient may not expand, with no durability mid-tool-call) and
  file-only (polling is the memory burden autopilot-reflex names).
- **Planwright owner:** fleet-messaging already makes this split for fleet
  signals (its D-2: the doorbell carries a pointer, the store row is
  authoritative, a lost signal costs latency, never correctness). The
  candidate is extending it from worker-to-tower traffic to review passes.
  It matters only if item 4 lets passes overlap.

### 6. A structured result for external review steps (dotfiles D-12, D-17)

**What:** the dotfiles bundle registers its own review skills as planwright
skill steps through an adopter catalog (`panel-review` at `convergence`,
`bot-review` at `post-pr`; D-12). The custom-steps runner classifies a
skill step's outcome from the handoff its session returns, with the record
carrying the excerpt the classification rests on. A skill outside
planwright has no contract telling it what that handoff must contain. The
candidate is a small structured result an external review step can emit:
the outcome, counts per bucket, the head it reviewed, and where its audit
record lives. Classification and the flip-point evidence would then not
depend on reading prose.

- **Dotfiles decision:** D-17 lists it among the seeded items. D-12 is
  what makes external review steps real.
- **Planwright owner:** custom-steps (*Outcomes, posture, and timeout*;
  *Records*).
- **Overlap:** `currency-posture-and-drifts.md` item 8, which records that
  external skills can now be named as steps at all.

### 7. CI as full-suite evidence, and the divergence from planwright's bar (dotfiles D-6, REQ-D1.3)

**What the dotfiles bundle does:** a pushed head whose check runs include at
least one success and no failure counts as full-suite evidence for that
head's tree hash, and the review loop uses it per iteration. Skipped and
neutral runs are ignored, as planwright's CI judge ignores them. A run not
yet concluded, or one cancelled or timed out, is no evidence yet. A head
with no check run, or only ignored ones, is no evidence.

**Planwright's bar:** test-throughput D-5 accepts a green PR CI run as
full-suite evidence only for the branch's final pushed head under
`full_suite_evidence: remote-ci`. Its REQ-B1.11 bars the review loop from
using PR CI as its per-iteration suite until review-effectiveness REQ-D1.3
is amended through that bundle's own delta sign-off.

- **Dotfiles decision:** REQ-D1.3 and D-6 diverge by recorded operator
  decision at kickoff (2026-10-03). They seed the divergence here so the
  upstream amendment decides once.
- **Measurements:** the dotfiles side has none yet. Its Task 7 plan counts
  full-suite runs per nested iteration and tooling runs per two-skill
  sequence, against a hand-counted baseline on main. Both are parked as in
  item 4. The planwright-side cost of one local full suite, measured while
  landing this note, is in this note's PR verification record.
- **Overlap:** `currency-posture-and-drifts.md` items 1 and 2. A ready
  guard that forces a sync, and a merge on every convergence pass, each
  multiply the CI cycles this item tries to reuse.

## Data hygiene

No vendor mechanics (login patterns, marker syntax, comment commands, check
names), organization names or repository names appear here, per dotfiles
REQ-H1.2 and `security-posture` *Artifact data-hygiene*. The hosted
reviewer the dotfiles bundle defaults to is deliberately unnamed.

## References

- dotfiles `specs/review-skills`: D-1, D-6, D-7, D-8, D-10, D-11, D-12,
  D-17; REQ-D1.1 to REQ-D1.7, REQ-I1.7, REQ-H1.1, REQ-H1.2; Tasks 6, 7, 9.
- `specs/review-effectiveness/` D-3, REQ-B1.1, REQ-D1.3, Task 6.
- `specs/test-throughput/` D-5, REQ-B1.11.
- `specs/custom-steps/` D-18 and its Deferred parallel-steps gate;
  `doctrine/custom-steps.md`.
- `specs/fleet-messaging/` D-2.
- `doctrine/discovery-rigor.md` (the lens list),
  `doctrine/artifact-lenses.md`.
- `specs/_pending/currency-posture-and-drifts.md`, the companion seed from
  the same operator's instruction audit.
