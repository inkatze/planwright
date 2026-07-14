# Invariant Tasks — Design

**Status:** Draft
**Last reviewed:** 2026-07-14
**Format-version:** 1

Origin tags: `N` = new decision; `C, <namespace> <id>` = carried from a prior
bundle, namespace-qualified.

## Decision log

### D-1: Altitude — a format-capability graduation, not new doctrine or a local script  (N)

**Decision:** The deliverable sits at the format-capability altitude. The
governing principle ("state is a derived projection of evidence") already
exists in doctrine via orchestration-concurrency D-1; this bundle does not
mint a new impulse. What changes is the format capability: the spec format
graduates to format-version 2 in `doctrine/spec-format.md`, and the mechanism
changes are confined to the core scripts that implement the format. The
opt-in seam is the `Format-version:` declaration itself — no overlay knob,
because the spec format is core's own domain and no adopter style rides it
(capability-vs-style check applied and clean). This is the altitude record
the fired seed-claim trigger requires, cited from the Goal.

**Alternatives considered:**
- A new standalone doctrine doc ("invariant ledgers"). Rejected because: the
  principle already lives in the meta-spec and orchestration-concurrency's
  decision log; a second doctrine home would duplicate and drift.
- A repo-local mechanism change without a format version bump. Rejected
  because: the committed `tasks.md` shape is a published format adopters
  author against; changing it silently is exactly the breaking change the
  meta-spec's versioning exists to prevent.
- An overlay-gated behavior (adopters opt in via config). Rejected because:
  a spec's format must be readable from the bundle alone; keying it off an
  overlay value would make one bundle mean two things on two machines.

**Chosen because:** the format-version declaration is the one seam that is
bundle-local, self-describing, and already versioned; placing the change
there keeps doctrine, capability, and mechanism each at their own altitude.

### D-2: v2 `tasks.md` shape — one task list plus the human-payload sections  (N)

**Decision:** A v2 `tasks.md` contains, after the header block and optional
intro prose: `## Tasks` (all task blocks, in dependency order, never moving),
`## Awaiting input`, `## Deferred`, and `## Out of scope`. The placement
sections (`## Forward plan`, `## In progress`, `## Completed`) and the state
annotation bullets (`Status`, `Last activity`, `Dispatch`) do not exist in
v2. Task blocks keep the five definition fields, stable IDs, and the
dependency-edge contract unchanged (REQ-A1.4).

**Alternatives considered:**
- Keep the six v1 sections but freeze placement (blocks never move).
  Rejected because: sections that no longer carry meaning actively mislead a
  reader — an unmoving `## In progress` heading asserts state the file no
  longer tracks.
- Drop the human-payload sections too, moving parked state to fragment files
  (the "all three layers" option). Rejected because: Awaiting-input
  questions, deferral gates, and exclusions are human-authored payload that
  cannot be derived from git evidence; trading a committed section for a new
  substrate adds machinery without removing state.

**Chosen because:** it removes exactly the derivable layer and nothing else;
the surviving sections each hold content only a human (or a halting skill)
can author.

### D-3: Awaiting-input entries are reference bullets, not relocated blocks  (N)

**Decision:** Parking a task for human input writes a bullet under
`## Awaiting input` — the task id plus the question — while the task block
itself stays in `## Tasks`, untouched. The bullet is authoritative in the
derivation (REQ-B1.4): a task with a live Awaiting-input bullet derives as
awaiting-input regardless of git evidence. Unparking removes the bullet.

**Alternatives considered:**
- Relocate the block into `## Awaiting input` (the v1 shape). Rejected
  because: moving a block is a committed state change, which REQ-A1.2
  forbids; it would reintroduce the churn this bundle exists to remove for
  the one state a human touches most.
- Record parked state only in runtime markers (uncommitted). Rejected
  because: the question payload must survive the session and travel with
  the PR; runtime state is host-local and disposable by design.

**Chosen because:** the block stays invariant, the human payload stays
durable and committed, and the derivation gets a single authoritative
override signal.

### D-4: Stored `Status:` restricted to human-gated states  (N (completes kickoff-lifecycle's deferral))

**Decision:** The v2 stored header carries only Draft, Ready, Retired, or
Superseded — the states a human declares. Active and Done are derived: a
bundle is Active iff any task derives In-progress or Completed with work
remaining, Done when all non-parked tasks derive Completed (the existing
derivation rules, consumed unchanged). After sign-off the stored value rests
at Ready; the reopen cycle becomes Ready→Draft; Retired/Superseded stay
stored terminal declarations.

**Alternatives considered:**
- Keep the reconcile-written Ready/Active/Done header (v1 behavior).
  Rejected because: it is the last remaining derived write into committed
  spec files, it churns the content anchor on every flip, and
  kickoff-lifecycle already named full derivation as the intended
  graduation.
- Derive everything including Draft/Ready. Rejected because: sign-off and
  retirement are human declarations with no git-evidence proxy; deriving
  them would invent evidence where only a recorded decision exists.

**Chosen because:** it stores exactly the human decisions and derives
exactly the execution facts — the same split the rest of the design applies.

### D-5: The v2 header carries a static derived-execution pointer line  (N)

**Decision:** The v2 header block includes one constant line after
`Format-version:`, e.g. `**Execution:** derived — see the status render`.
The text is fixed vocabulary defined by the meta-spec (never per-bundle
prose), so it never churns; it exists so a reader browsing the committed
file — where a finished spec reads `Status: Ready` — is pointed at the
render instead of concluding the spec never started.

**Alternatives considered:**
- Freeze at Ready and document the convention only in the meta-spec.
  Rejected because: the file is read far from the meta-spec (GitHub, code
  review); a reader should not need the convention memorized to avoid being
  misled.
- A human-stamped Done value (like Retired). Rejected because: it
  reintroduces a manual ceremony that fires only when a human remembers it —
  the exact shape the autopilot reflex exists to remove — and it can go
  stale against derived reality.

**Chosen because:** one constant line buys reader orientation at zero churn
cost.

### D-6: CLI render only — no committed or remote-mirrored status artifact  (N)

**Decision:** The derived status view is produced on demand by the render
(the derivation engine surfaced as a command) and is never committed, never
pushed to a PR body, pinned issue, or generated file. GitHub shows
definitions; execution state is read locally (or via the fleet decision
queue, which already consumes the live derivation).

**Alternatives considered:**
- A PR-surface mirror (rendered status block refreshed into the spec PR
  body or a pinned issue). Rejected because: it reintroduces a derived
  artifact with a refresh owner, drift potential, and remote dependency —
  the pattern this bundle retires — for a surface the fleet decision queue
  already covers.
- A committed snapshot artifact (generated status file). Rejected because:
  it is the current design with the file renamed; every liability carries
  over.

**Chosen because:** the purest form of the model — nothing derived is ever
written down, so nothing derived can drift; and the operational evidence
(Sources) shows the committed mirror was already being bypassed or disabled
where it mattered.

### D-7: Version-keyed machinery — `Format-version:` selects behavior  (N)

**Decision:** Every script and hook that touches the committed state layer
reads the bundle's declared `Format-version:` and branches: v1 bundles get
today's behavior unchanged (sync writer reconciles, ledger guard checks
coherence, validator applies v1 rules); v2 bundles get the invariant-ledger
behavior (writer no-ops, guard checks structure only, validator enforces the
v2 invariants). Wholesale retirement of the v1 arms is deferred behind a
gate (see `tasks.md` Deferred).

**Alternatives considered:**
- Retire the v1 machinery in the same release. Rejected because: the
  meta-spec promises bundles keep working under their declared version;
  adopters with live v1 Active bundles would lose their reconcile the day
  they upgrade the plugin.
- A global config knob selecting the model repo-wide. Rejected because: the
  format is bundle-local (D-1); one repo can legitimately hold live v1 and
  v2 bundles during migration.

**Chosen because:** the declaration is already in every bundle's header,
already validated, and already the meta-spec's versioning contract — no new
switch needed.

### D-8: Selector and gate evaluator re-source from derivation plus committed parked state  (N)

**Decision:** For v2 bundles, unit selection computes candidacy as:
dependencies met and not completed/in-progress (both from the derivation
engine) and not parked (no Awaiting-input bullet, not listed in Deferred or
Out of scope — read from the committed human-payload sections). Gate
evaluation resolves task-completion atoms through the derivation engine
instead of `## Completed` membership.

**Alternatives considered:**
- Keep a minimal committed placement signal just for the selector. Rejected
  because: it preserves the writer, the hook, and the churn for one
  consumer that the derivation engine already serves everywhere else.
- Drop the parked filters. Rejected because: parked-ness is a human
  decision with no git-evidence proxy; ignoring it would dispatch tasks a
  human explicitly held.

**Chosen because:** the survey showed these are the only two readers of
committed placement; re-sourcing them completes the read side at the exact
two points it was incomplete.

### D-9: The content anchor is untouched; churn-freedom falls out by construction  (N)

**Decision:** No change to anchor mechanics: the canonical `tasks.md`
extraction and the four-file manifest hash stay as spec-format v1 defines
them, and the `Status:` header remains inside the anchored content. Under
v2, state changes touch no committed spec file (REQ-A1.2, D-4), so the
anchor is stable across all orchestration acts (REQ-C1.6); the only header
writes that remain (Draft→Ready, Retired, Superseded, reopen) are human-gated
events that coincide with sign-off or amendment rituals, which re-anchor
anyway.

**Alternatives considered:**
- Exclude the `Status:` header line from the anchor. Rejected because: with
  derived flips gone, the remaining flips *should* re-anchor (they are
  meaning-bearing lifecycle acts); excluding the line would let a terminal
  flip slip past the freshness gate.
- Simplify the extraction to whole-file hashing for v2. Rejected because:
  Awaiting-input bullets and Deferred entries still legitimately change
  between sign-offs; whole-file hashing would revive the forced
  expression-only re-anchor for parked-state edits.

**Chosen because:** the churn problem dissolves upstream (no derived
writes), so the anchor needs no compensating change — and unchanged anchor
mechanics keep v1 and v2 bundles verifiable by the same gate.

### D-10: Migration — one-shot script, byte-stable definitions, live bundles only  (N)

**Decision:** A one-shot migration script (in the mold of the existing
status-lifecycle migration) converts a v1 bundle to v2: collapse the state
sections into `## Tasks` sorted by task id, strip state annotation bullets,
convert any relocated Awaiting-input blocks to reference bullets, restrict
the header value, add the pointer line, and bump `Format-version:` to 2.
Task definition lines are preserved byte-for-byte, so the canonical
`tasks.md` extraction — and therefore that file's contribution to the
anchor — is unchanged; the header edits still change the manifest, and that
re-anchor rides the migration as an expression-only entry. Applied to
planwright's own live (Ready/Active) bundles; Done and terminal bundles are
never rewritten.

**Alternatives considered:**
- Migrate every bundle including Done/terminal. Rejected because: finished
  records gain nothing (no machinery acts on them) and rewriting them
  contradicts the coexistence model that lets old bundles rest.
- Manual migration guidance without a script. Rejected because: the
  transform is mechanical and error-prone by hand (annotation stripping,
  id-sorted collapse); a script is testable against fixtures.

**Chosen because:** smallest honest migration: mechanical, verifiable
(extraction digest unchanged), scoped to bundles that still move.

### D-11: Completion-annotation contract superseded for v2  (N (supersedes the v2 arm of output-hygiene's completion-annotation contract))

**Decision:** output-hygiene's normative completion annotation
(`Completed · PR #<n> merged <YYYY-MM-DD>`, stamped by the reconcile) has no
home in a v2 bundle: completion is derived render content, produced by the
derivation engine at read time. The supersession is recorded per the ritual
(this D-ID plus a dated changelog entry here; output-hygiene's contract
remains normative for v1 bundles and is not edited retroactively).

**Alternatives considered:**
- Keep stamping completion annotations into v2 bundles as the one surviving
  derived write. Rejected because: one exception re-admits the writer, the
  hook trigger, and the churn — and the annotation's content (PR number,
  merge date) is exactly what the derivation engine already emits.

**Chosen because:** the annotation existed to make completion readable in a
file that no longer claims to show state; the render is its successor
surface.

## Cross-cutting concerns

- **Security posture.** No new parsing surfaces: the render and the
  version-keying read the same validated headers and task-id grammar the
  existing scripts read. The migration script handles committed spec files
  as untrusted input per framework-script rules (validated identifiers,
  containment-checked paths, sanitized echo).
- **Research grounding.** Peer comparison run at drafting (Sources): the
  closest spec-driven peer (GitHub spec-kit) tracks status as manual
  checkboxes with staleness complaints on record; git-native trackers
  (git-bug, git-task) store state conflict-free rather than deriving it.
  The derive-don't-store pattern extends the prior art
  orchestration-concurrency D-1 already vetted (Kubernetes level-triggered
  reconciliation, event-sourcing read models, git reachability; Terraform's
  mutable state file as the antipattern). No new dependency is adopted.
- **This bundle is authored at format-version 1** — v2 does not exist until
  Task 1 ships. It is expected to be among the live bundles migrated by
  Task 6.
