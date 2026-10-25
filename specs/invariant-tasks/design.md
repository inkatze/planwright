# Invariant Tasks — Design

**Status:** Ready
**Last reviewed:** 2026-10-25
**Format-version:** 2
**Execution:** derived — see the status render

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

### D-3: Parked state is reference bullets, not relocated blocks  (N)

**Decision:** Parking a task writes a reference bullet — the task id plus
the human payload — under the relevant human-payload section, while the
task block itself stays in `## Tasks`, untouched: `## Awaiting input` (the
question; also written by a halting skill, including `/orchestrate`'s
dead-worker orphan reconcile), `## Deferred` (the gate), `## Out of scope`
(the exclusion rationale). A live reference bullet is authoritative in the
derivation (REQ-B1.4): its task derives as awaiting-input / deferred /
out-of-scope regardless of git evidence. Unparking removes the bullet.
A task is parked in at most one section at a time (the validator enforces
cross-section exclusivity, REQ-C1.5). "Parked" is defined here, in the
broad sense: a task named by any live reference bullet. *(Amended at kickoff sign-off 2026-07-14: generalized
from Awaiting-input-only to all three human-payload sections — the drafted
form left deferred and excluded tasks unrepresentable in v2, and migration
would have silently un-parked v1 blocks relocated into those sections.)*

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
remaining, Done when every task in the Done universe derives Completed and
no live Awaiting-input bullet remains — an open question blocks Done, while
tasks parked by a Deferred or Out-of-scope reference bullet are excluded
from the Done universe rather than blocking it (open Deferred gates do not
block Done, per the meta-spec lifecycle); Deferred and Out-of-scope bullets
that name no task are not tasks and never count (the existing derivation
rules, consumed unchanged). After sign-off the stored value rests
at Ready; the reopen cycle becomes Ready→Draft; Retired/Superseded stay
stored terminal declarations. Derivation is computed only for stored-Ready
bundles: Draft, Retired, and Superseded render their stored state with no
execution claim, and a zero-task bundle never derives Done (REQ-B1.6).
*(Amended at kickoff 2026-07-14: the Done clause restated to match the
consumed derivation rules — the drafted "all non-parked tasks" wording
would have let an open Awaiting-input question derive Done. Amended again
at kickoff sign-off 2026-07-14: stored-status gating and the zero-task
rule added — ungated derivation could assert Active/Done over a reopened
Draft or a terminal bundle, and an empty bundle would derive a vacuous
Done.)*

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
`Format-version:` — `**Execution:** derived — see the status render`.
That exact text is fixed vocabulary defined by the meta-spec (never
per-bundle prose, not customizable), so it never churns; it exists so a reader browsing the committed
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
queue, which already consumes the live derivation). Machine consumers read
the derivation engine directly (the selector, gate evaluator, and fleet
queue already do); the render's text is a human-facing view with no
stability promise — a machine-readable mode would be an additive follow-up,
not part of this bundle. The render also owns the bundle-status
determination itself: that logic lives today in the sync writer's awk
(keyed on section membership) and is ported into the render, re-sourced
from reference bullets — "consumed unchanged" refers to the
evidence-precedence rules, not to the code's current home. *(Amended at
kickoff 2026-07-14: machine-surface clarification added. Amended again at
kickoff sign-off 2026-07-14: the ported-derivation scope made explicit;
Task 3 owns the port.)*

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
switch needed. A missing or unparseable `Format-version:` fails closed:
version-keyed writers write nothing and the validator errors (REQ-C1.8);
no script falls open to the v1 write path. *(Amended at kickoff sign-off
2026-07-14: the fail-closed rule added — failing open would write v1 state
into a v2 bundle.)*

### D-8: Selector and gate evaluator re-source from derivation plus committed parked state  (N)

**Decision:** For v2 bundles, unit selection computes candidacy as:
dependencies met and not completed/in-progress (both from the derivation
engine) and not parked (no live reference bullet naming the task in any
human-payload section, D-3). Gate
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
status-lifecycle migration) converts a v1 bundle to v2: collapse the
placement sections into `## Tasks` sorted by task id, strip state
annotation bullets, convert any relocated parked blocks (in any
human-payload section) to reference bullets, restrict
the header value, add the pointer line, and bump `Format-version:` to 2.
Task definition lines are preserved byte-for-byte, so the canonical
`tasks.md` extraction — and therefore that file's contribution to the
anchor — is unchanged; the header edits still change the manifest, and that
re-anchor rides the migration as an expression-only entry (signed bundles
only; a Draft has no brief to re-anchor). Applied to planwright's own live
(Draft/Ready/Active) bundles; Done and terminal bundles are never
rewritten. The migration is idempotent (an already-v2 bundle is a clean
no-op), per-bundle atomic, and re-runnable after a partial run; parked task
blocks found under any human-payload section — not only Awaiting input —
convert to reference bullets. The per-bundle unit includes a signed
bundle's expression-only re-anchor entry plus the dated changelog line the
entry cites (the meta-spec's execution-validity condition): idempotency
keys on all of these artifacts, so a re-run completes a missing re-anchor
or changelog line rather than no-oping past a file that already reads v2. *(Amended at kickoff 2026-07-14: Draft
bundles included in the migration population. Amended again at kickoff
sign-off 2026-07-14: idempotency, atomicity, and re-runnability pinned;
parked-block conversion generalized per the D-3 amendment.)*

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
surface. The same scoping covers the annotation's second normative home:
the meta-spec's own 2026-07-10 versioning entry in
`doctrine/spec-format.md` promoted the annotation to normative there too,
so Task 1's v2 definition scopes that entry to v1 bundles and Task 8's
supersession record names both homes. *(Amended at kickoff sign-off
2026-07-14: the second normative home named.)*

### D-12: No replacement cache — per-invocation derivation accepted  (N)

**Decision:** The committed snapshot this bundle removes was, per
orchestration-concurrency's own kickoff record, the read-model cache; no
replacement cache is introduced. Every consumer derives per invocation
(local git scans plus one `gh pr list` call): the session-driven consumers
are low-frequency — the human render on demand, drain passes, one selection
per dispatch step — and the one standing consumer, the fleet decision
queue, already polls the live derivation across specs today; its aggregate
cadence is exactly what the revisit signals below watch. Within one
orchestrate step, reusing a single derivation
result across selection, gating, and any render is encouraged but
non-normative. No latency bound is pinned; the kickoff brief's risk
register carries the revisit signals (render latency complaints, gh
secondary-rate-limit hits).

**Alternatives considered:**
- A within-step or on-disk derivation cache. Rejected because: a cache is
  the committed-snapshot liability in a new coat (a refresh owner,
  staleness, invalidation); observed consumer frequencies do not justify
  it.
- Pinning a latency budget in Done-when clauses. Rejected because: no
  baseline exists yet; a number would be invented, not measured.

**Chosen because:** the honest completion of the graduation is naming the
cost and accepting it deliberately, with recorded signals that reopen the
decision if reality disagrees.

### D-13: Per-task repositories land as format-version 3  (N, extension 2026-10-25)

**Decision:** Format-version 3 is version 2 plus one optional task
definition field, `- **Repository:** <alias>`, placed after `Citations:`
and before `Estimated effort:`. A block without it belongs to the bundle's
work repository, so a version 3 bundle that never uses the field means
exactly what its version 2 form meant. The canonical extraction keeps the
field line as definition content in version 3, and since no existing block
carries it, the extraction of every bundle without the field is
byte-identical to version 2. Every version-keyed script gives version 3 its
version 2 behavior plus the field; an undefined version stays fail-closed
(D-7). A bundle declares version 3 only when a task needs the field; no
migration is offered or needed. *(Choice made unattended; open question 1
in `requirements.md`.)*

**Alternatives considered:**
- An additive field inside version 2. Rejected because: version 2 defines a
  block as its five fields "and nothing else", so the field would be a
  silent format change, the exact case D-1 rejected; and an install that
  predates it would drop the unknown bullet from the extraction and derive
  and dispatch every task from the launch repository rather than refuse.
- A bundle-level `Repositories:` header. Rejected because: the repository
  is a property of a task, and a header list cannot say which task lives
  where.
- One bundle per repository. Rejected because: the cross-repository
  dependency edges are the point (obs:74a7f907), and the grammar has no
  cross-bundle edge.

**Chosen because:** the version declaration is the format's own seam
(D-1, D-7): an install that knows version 3 reads the field, and one that
does not refuses the bundle at its declaration, which is the fail-closed
shape the derivation needs when the alternative is dispatching into the
wrong repository.

### D-14: The field holds an alias, resolved by the work-repository registry  (N, extension 2026-10-25)

**Decision:** The `Repository:` value is one alias in the identifier
grammar (`^[a-z0-9][a-z0-9-]*$`, at most 64 characters). It resolves to a
local checkout only through `custom-spec-location`'s machine-local
work-repository registry, which maps a spec root's project to the aliases
of the repositories registered against it; this bundle consumes that map
and does not define it. A task names exactly one repository: work that
spans repositories splits into tasks joined by dependency edges, which
D-15 makes cross-repository. A task whose code lives in the holder itself
names the holder's alias like any other repository; a task that touches no
repository stays outside execution. *(Choices made unattended; open
questions 2 and 3 in `requirements.md`.)*

**Alternatives considered:**
- A checkout path. Rejected because: it is machine-specific, wrong on every
  other machine, and leaks a home-directory layout into a committed file.
- A remote URL or `owner/name`. Rejected because: a remote names where
  pull requests land, not the local checkout worktrees are placed in; two
  checkouts of one remote would be indistinguishable; and a self-hosted
  remote puts a host name in committed prose.
- A multi-repository unit form (a block naming two or three repositories).
  Rejected because: a unit's branch, worktree, pull request, and trailer
  all live in one repository; a multi-repository unit needs a coordinated
  multi-PR lifecycle no part of the pipeline has, while splitting costs one
  dependency edge.

**Chosen because:** the alias keeps the bundle portable across machines
and free of local layout, and putting the alias-to-checkout map in the
registry gives one machine-local answer to "where is that repository" for
both the derivation here and holder dispatch there.

### D-15: Derivation per task, joined across repositories  (N, extension 2026-10-25)

**Decision:** The derivation engine resolves each task's repository (the
field's alias through the registry, or the bundle's work repository),
groups tasks by resolved repository, derives each group from that
repository's own evidence (its branches, its pull requests, its commit
trailers), and joins the results; the dispatch markers keep their one
per-bundle home, so every session reading the bundle sees the same
in-flight units whichever repository they dispatched into. Dependency
satisfaction reads the dependency's derived state wherever it lives, which
is what "the repository it landed in" means. A task whose alias does not
resolve derives `unresolved`, a distinct state that is never selected,
never satisfies a dependency, never satisfies a gate atom, and blocks
derived Done. A transient fetch failure in any one resolved repository
fails selection closed for the bundle (REQ-B1.5 applied per repository).
D-12's no-cache decision stands; the derivation's cost grows by one
pull-request query per distinct repository, and D-12's revisit signals
cover it. *(Bundle-wide fail-closed chosen unattended; open question 4 in
`requirements.md`.)*

**Alternatives considered:**
- Deriving from the union of all repositories' evidence for every task.
  Rejected because: a task branch name is the same in every repository
  (`planwright/<spec>/task-<id>`), so a stray branch in the wrong
  repository would count as evidence; scoping a task's evidence to its own
  repository removes the ambiguity.
- Treating an unresolved alias as "not started". Rejected because: it
  would make the task selectable and dispatch it into whatever repository
  the fallback picks, the failure this extension exists to stop.
- Per-repository fail-closed on a transient failure. Rejected for now
  because: the bundle's dependency graph crosses repositories, so a unit in
  a healthy repository may depend on one in the failing repository; the
  bundle-wide rule needs no reasoning about which edges cross.

**Chosen because:** it keeps orchestration-concurrency's evidence chain
unchanged within each repository and adds only the join, so a bundle
whose tasks all live in one repository derives exactly as before.

## Cross-cutting concerns

- **Security posture.** Three new untrusted-content surfaces are
  introduced and bound by REQ-C1.9: the reference bullet (a
  derivation-authoritative parse of a task id plus free text), the
  migration's consumption of whole v1 bundles as input, and the render as
  a new terminal-output surface echoing evidence-derived strings (branch
  names, PR metadata, remote error text). Bullet task ids are validated
  against the task-id grammar before any use; the migration validates
  identifiers, containment-checks paths, and refuses hostile input with a
  clean, sanitized error; the render and the new validator/guard error
  paths sanitize all echoed untrusted content (`sanitize_printable`); the
  v2 format definition carries the artifact data-hygiene note for bullet
  free text. *(Corrected at kickoff sign-off 2026-07-14: the drafted "no
  new parsing surfaces" claim under-declared the bullet surface. Amended
  at self-review 2026-07-14: the render counted as an output surface and
  the sanitize scope broadened beyond spec-file content.)*
- **Research grounding.** Peer comparison run at drafting (Sources): the
  closest spec-driven peer (GitHub spec-kit) tracks status as manual
  checkboxes with staleness complaints on record; git-native trackers
  (git-bug, git-task) store state conflict-free rather than deriving it.
  The derive-don't-store pattern extends the prior art
  orchestration-concurrency D-1 already vetted (Kubernetes level-triggered
  reconciliation, event-sourcing read models, git reachability; Terraform's
  mutable state file as the antipattern). No new dependency is adopted.
- **Extension security posture (2026-10-25).** The `Repository:` value is
  a new untrusted parse surface: it is validated against the identifier
  grammar before any use and never interpolated into a path or command
  before validation; the registry, not the bundle, supplies the checkout
  path, and the registry's own read-time validation is
  `custom-spec-location`'s. The render and validator echo the alias
  through `sanitize_printable`. A derivation that runs `gh` in a second
  repository uses that repository's own remote; no credential is added.
- **Extension decision-domains walk (2026-10-25).** Data modelling: a new
  format field, decided in D-13 and D-14. Versioning: format-version 3,
  D-13. Integration surface: the registry seam consumed from
  `custom-spec-location` (its `--repository` lookup), D-14. Concurrency:
  per-repository evidence with the dispatch markers kept in their one
  per-bundle home, D-15. Observability: the render's per-task alias and the `unresolved`
  state, REQ-F1.4 and REQ-F1.5. No new dependency.
- **This bundle is authored at format-version 1** — v2 does not exist until
  Task 1 ships. It is expected to be among the live bundles migrated by
  Task 6.
