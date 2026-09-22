# Custom spec location — Design

**Status:** Ready
**Last reviewed:** 2026-09-22
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new decision, minted in this bundle's drafting session
(2026-09-21 to 2026-09-22). Foreign IDs are namespace-qualified. Terms
(work repository, holder, store, posture, the two views) are defined in
`requirements.md` under Goal.

## Decision log

### D-1: Altitude — a capability seam plus doctrine amendments  (N)

**Decision:** The deliverable sits at capability altitude with the doctrine
amendments it needs beneath it. The capability is three resolvable roots
(install, primary checkout, spec) exposed as a seam every consumer reads
through; the mechanism is one resolver script plus the migrated callers; the
doctrine amendments (REQ-G1.4) widen `storage-classes`' class-3 home from
"a git repository the human owns" to "a location the human owns", scope its
"committed" attribute to the git postures, record the posture ladder there,
and bring every other doctrine site that states the spec or accumulator
home into agreement, in one task that lands before any posture-dependent
skill. The values (where a given operator's specs live, which targets they
route observations to) are overlay content and never land in core.

**Alternatives considered:**
- Mechanism only: add a `spec_root` knob and thread it through the callers.
  Rejected because: the seed's two altitude claims (a multi-project holder,
  a git-less store) contradict the current doctrine text, so a mechanism
  without the amendment would ship a supported configuration the doctrine
  calls wrong.
- Doctrine only: amend `storage-classes` and leave the callers as they are.
  Rejected because: the doctrine would then describe a capability nothing
  implements, and the observation set shows the callers already disagree on
  the root today.

**Chosen because:** the `customization-boundary` split runs through the
feature: the ability to relocate is general (any adopter with a monorepo, a
docs repository, or a spec holder wants it), while every concrete location is
one operator's value. On the boundary's evidence criterion, the root
resolution half rests on the fifteen recorded observations under Sources;
the relocation half rests on the single invocation, accepted into core
because the knob ships dark (criterion 5) and the cost of a wrong core call
is bounded to an option nobody sets. The doctrine amendments are the part
the seed claims assert and a kickoff lens pass can verify.

### D-2: One resolver script, three root kinds  (N)

**Decision:** A single POSIX-sh script, `scripts/resolve-root.sh <kind>`,
with kinds `install`, `repo`, and `spec`, replaces every inline root
derivation. `repo` takes `--primary` (the worktree owning the common git
directory) or `--checkout` (the current toplevel); `spec` takes `--primary`
(the primary view, D-7), `--posture` (D-6), and `--init` (D-4); every kind
takes `--explain` (REQ-A1.8). Every script that composes `specs/` as a path
or calls `git rev-parse --show-toplevel` to find the repository is migrated
onto it, and every script that asserts the spec root's parent is named
`specs`, or infers the checkout from that parent, drops it, since a root
outside the repository has no such parent.

**Alternatives considered:**
- Three separate scripts. Rejected because: the kinds share the containment
  primitive, the explain output, and the by-layer policy; three copies is how
  the current divergence arose.
- A sourced shell library. Rejected because: the guards and the skills'
  Bash steps need the chain as a command they can invoke by resolved path,
  and a sourced library cannot be called that way. The script layer's
  existing sourced libraries (`spec-parse.sh`, `lock-lib.sh`,
  `echo-safety.sh`) stay sourced where they are; this decision adds a
  command, not a convention.

**Chosen because:** one script keeps the literal-`specs/` guard (D-19)
enforceable with a minimal, line-scoped allowlist.

### D-3: The `spec_root` option and its value grammar  (N)

**Decision:** `spec_root` is a config option read through `config-get`
across the four layers, last-layer-wins, typed `path` in the shared knob
resolver (a type this spec adds; the resolver's type set is closed today). A
value is absolute, `~/`-prefixed (expanded against `HOME`), or relative to
the primary checkout root, whitespace-trimmed. An empty value means unset in
that layer and falls through. The winning value is canonicalized before use;
a relative value may not escape the primary checkout. A well-formed value
that points at a nonexistent path, a non-directory, or an escaping relative
path is refused in every layer and never falls back to the default; only
malformed text (a non-printable byte) follows the customization-overlay
by-layer policy. Unset everywhere yields `<checkout>/specs` with today's
behaviour byte for byte.

**Alternatives considered:**
- A pointer file in the work repo (the adr-tools `.adr-dir` shape).
  Rejected because: planwright already has a four-layer config mechanism
  with provenance and a malformed-value policy; a second file format for one
  key would bypass it, and the machine-local layer already gives the
  per-machine path the pointer file was for.
- An environment variable only. Rejected because: a team-shared location
  needs a tracked home, and an env var is neither diffable nor reviewable.
- A relative-only value. Rejected because: the holder and plain cases are
  outside the repository by definition.
- The overlay by-layer policy for every bad value (a machine-local typo
  warns and falls back to `specs/`). Rejected because: a wrong root reached
  by fallback is the fail-open shape D-4 exists to stop; the operator asked
  for one place and would silently get another.
- Refuse an empty value too. Rejected because: an empty value in a higher
  layer is how a machine-local file cancels a repo-tracked value, and there
  is no other way to do that.

**Chosen because:** no existing option takes an absolute or out-of-repo
path (the release `version_file` knob is repo-relative and resolved by its
own library, whose recorded wart, canonicalized against the working directory
while contained against the toplevel, is exactly what anchoring relative
values to the primary checkout avoids), so `spec_root` is the first and
carries its own rule rather than a precedent.

### D-4: The root marker  (N)

**Decision:** A non-default root carries `planwright-spec-root.yml`, a flat
file with `project: <id>` (the identifier grammar) and `layout: 1`. The name
says which root it marks, since "planwright root" already names the install
root (`PLANWRIGHT_ROOT`) and the repo root (`PLANWRIGHT_REPO_ROOT`). The
resolver refuses a configured root without it, in every layer. The default
root, decided by resolved path (REQ-A1.4), needs none, so existing
repositories are untouched. The resolver's `--init` flag, given an existing
directory, validates the value, bypasses the marker check for that one
target (writing the marker is its purpose), writes the marker, and, where
the directory lies in a git repository, writes the ignore rules for the
local-only entries (REQ-A1.5); it does not create the directory.
`/spec-draft` offers the init when the pointer targets a directory without a
marker.

**Alternatives considered:**
- No marker, accept any directory. Rejected because: a typo in the pointer
  then resolves to an empty root at exit 0, the fail-open shape this repo's
  observations record repeatedly (an empty catalog, a fail-open
  protected-docs list, vacuous absence checks).
- A repository path or remote in the marker. Rejected because: it goes stale
  when the work repository moves, and the mapping is the work repository's
  property, not the root's (the operator's own reasoning during elicitation).
- Reusing the work repo's own `.claude/planwright.yml` as the marker.
  Rejected because: the holder is not the work repo, and a plain directory
  has no `.claude/`.
- An identity namespace segment instead of a marker, the adopter overlay
  root's shape. Rejected because: a plain directory chosen by the operator
  has no namespace to carry the segment, and the marker doubles as the
  identity a later registry keys on.

**Chosen because:** git's own pointer shape (a gitfile pointing at a real
repository, never at a bare directory) shows the pointed-to end carrying its
identity; the marker is that identity, and it is class-1 config: human
authored, committed where the root is committed, readable without planwright.

### D-5: The reserved children follow the root  (N)

**Decision:** `_observations/`, `_pending/`, and any other reserved
accumulator the meta-spec defines are direct children of the resolved root
under its checkout-local view, wherever it is, so a fragment recorded from a
task worktree rides that worktree's branch as it does today. One option
relocates the whole spec home. In a holder, each project's root has its own
accumulator.

**Alternatives considered:**
- A second option for the accumulator. Rejected because: two pointers can
  disagree, and nothing in the seeds wants bundles and observations apart.
- The accumulator always stays under the work repository's `specs/`.
  Rejected because: a plain store would then still need a git work repo for
  its observations, and the `observation-recording` substrate assumes the
  store and the bundles share a root.

**Chosen because:** the reserved-name grammar and every accumulator script
already take the store as a directory; only the default changes.

### D-6: Posture classification  (N)

**Decision:** The resolver classifies the store by repository identity: the
common git directory of the repository containing the root's primary view
is compared with the work repository's; `same-repo` when equal (another
worktree of the same repository is the same repository), `separate-repo`
when different, `plain` when the root lies in no repository. An in-repo
root that git ignores is `same-repo`; the authoring commit step is where
that surfaces. The posture is printed by `--posture` and in `--explain`,
never on the default stdout, which every caller captures as a bare path;
every posture-dependent skill step reads it rather than probing git itself.

**Alternatives considered:**
- Each skill probing `git rev-parse` in the root. Rejected because: that is
  the inline-copy pattern this spec removes.
- A declared posture in the marker. Rejected because: it would drift from the
  filesystem truth the resolver can observe directly.
- Comparing toplevels. Rejected because: a second worktree of the same
  repository has a different toplevel and is not a different repository.

**Chosen because:** three rungs are the whole space the requirements name,
and a derived classification cannot go stale.

### D-7: Two views of the root  (N)

**Decision:** By default the resolver returns the checkout-local root: in
`same-repo`, `<current toplevel>/specs` (or the configured path under it),
which is what every script sees today from inside a task worktree.
`--primary` returns the primary view, the read surface the freshness gate
and the derivation engine use. A relative value, or an absolute value that
lies inside the primary checkout, is re-based onto the current checkout for
the checkout-local view, so an in-repo root behaves the same whether it was
written relative or absolute. In `separate-repo` both views are the holder's
primary checkout; in `plain` they coincide. Config values always resolve
from the primary checkout, whichever view is asked for. The flag was
`--canonical` in the draft and is renamed so "canonical" keeps its single
sense of path normalization.

**Alternatives considered:**
- Always the primary checkout's root. Rejected because: an in-flight bundle
  amendment rides the task PR, so a worker must write its own worktree's copy;
  returning the primary's copy would make it edit the wrong tree.
- Always the current checkout's root. Rejected because: that is the bug the
  config-overlay observations record, and the gate's frame is normatively the
  primary view.

**Chosen because:** the two consumers genuinely want different trees, and
naming the view at the call site is what keeps the compatibility requirement
(REQ-A1.1) honest.

### D-8: The primary checkout helper  (N)

**Decision:** `resolve-root.sh repo --primary` returns the directory owning
`git rev-parse --git-common-dir`, honouring `PLANWRIGHT_REPO_ROOT` first when
it names an existing git toplevel and refusing it otherwise; `--checkout`
returns `git rev-parse --show-toplevel` and the variable never affects it.
Outside a repository, or in a bare repository with no primary working tree,
both exit non-zero with a message naming the case. The overlay resolver's
repo-side layers, the worktree placement helper, and every remaining inline
`--show-toplevel` call that meant "the repository" migrate to `--primary`.
Today the variable substitutes for `--show-toplevel` wherever the overlay
chain asks for "the repo"; its narrowing to the primary root is a named
correction (REQ-A1.1).

**Alternatives considered:**
- Keep `--show-toplevel` and special-case the overlay resolver. Rejected
  because: the placement bug and the config bug share the cause, and the
  fleet scripts carry further copies of it.

**Chosen because:** `--git-common-dir` is the one worktree-aware call the
sync hook already uses, bare-repo case included; the helper makes it the
rule instead of the exception.

### D-9: The install-root helper  (N)

**Decision:** `resolve-root.sh install` owns the core root chain in the
documented order (`PLANWRIGHT_ROOT`, `CLAUDE_PLUGIN_ROOT`, the writer-mode
directory, self-location beside the script). An arm whose directory lacks
both `doctrine/` and `scripts/` is skipped with a warning. Every script that
runs the chain inline today (the rule-doc, overlay-root, review-sequence,
and config-get resolvers, the inception scaffold, the anchor-freshness check)
calls it, and so does every command guard: a guard obtains the chain from
the helper and composes its own trust set on top, the worker guard adding
the installed-roots arm it relies on and the tower guard keeping the
distinct, tighter set fleet-hardening REQ-C1.2 requires. The drift test
asserts both guards derive the chain from the helper, not that their sets
are equal. Consumers running a shorter chain today gain the documented arms,
a named correction (REQ-A1.1). The chain's prose definition consolidates on
`spec-format`, with the helper's header and `plugin-script-invocation`
pointing at it rather than restating it.

**Alternatives considered:**
- Leave each consumer's chain and add a drift test. Rejected because: the
  guards already diverge, and a drift test would only report what a
  shared helper prevents.
- Make both guards trust exactly the same set. Rejected because: it either
  drops the worker's installed-roots arm, reintroducing the stall
  obs:0aaad2ef records, or widens the tower set that fleet-hardening keeps
  deliberately distinct.

**Chosen because:** the chain is one definition; one implementation is its
mechanical form, and trust policy is the guards' own concern.

### D-10: Self-hosting pins `PLANWRIGHT_ROOT`  (N)

**Decision:** The chain order stays as documented. A planwright checkout
pins `PLANWRIGHT_ROOT` to its own root through the tracked `mise.toml`
`[env]` table as a config-root expansion, so every checkout of the tree
resolves itself rather than the installed plugin. Each worktree carries its
own tracked copy of `mise.toml`, so nearest-config-wins makes a worktree
resolve the worktree, which is the tree under test. The pin is a tracked
value naming the tree the operator already checked out, so it widens no
guard's trust beyond the checkout itself; an operator who wants a different
root sets the variable in the environment, which mise does not override.

**Alternatives considered:**
- Reorder the chain to try self-location first. Rejected because: an
  adopter overriding the root with `PLANWRIGHT_ROOT` on purpose would be
  silently outranked by whichever copy the script ran from.
- Detecting "am I a planwright checkout" in the helper. Rejected because: it
  is a heuristic where an explicit pin is available.
- The pin in the untracked machine-local `mise.local.toml`. Rejected
  because: self-hosting would then not be automatic for a fresh clone or a
  CI run, which is where the misresolution was observed.

**Chosen because:** three observations record the same misresolution, and
one of them proposes exactly this pin.

### D-11: Spec addressing  (N)

**Decision:** The bare identifier is the canonical spec argument on every
skill argument and identity seam; `specs/<id>` is accepted as an alias and
mapped to the same identifier before any path use, a trailing slash
tolerated. Scripts that operate on a bundle directory keep taking the
directory the resolver produces and gain no alias handling, so the change
is additive on the seams it touches and absent elsewhere. Branch names,
worktree names, lock paths, commit trailers, and the `Consumed-by: specs/<id>`
line keep their forms: in each of them `specs/` is a logical namespace, not
a directory. The dispatch scope grammar keeps its field grammar and takes
the identifier; callers pass that form.

**Alternatives considered:**
- Accept any path to a bundle directory on the identity seams. Rejected
  because: it adds a rootless-bundle posture every writer must handle, and
  no seed wants it.
- Keep `specs/<id>` as the only form. Rejected because: the prefix would
  name a directory that no longer exists at that path.
- Make every bundle script accept the identifier and resolve the directory
  itself. Rejected because: it is a much larger migration, it changes every
  path-driven test, and a script that operates on a directory has no reason
  to know about identities.

**Chosen because:** the identifier is what every grammar already validates;
the alias costs one substitution and keeps every existing script and habit
working.

### D-12: Authoring in the `separate-repo` posture  (N)

**Decision:** When the root lies in a holder repository, `/spec-draft`
creates the spec branch and the spec worktree in the holder (worktree at
`<holder>/.claude/worktrees/<id>-spec`, branch `planwright/<id>/spec`), commits
the bundle and the consume writes there, and `/spec-kickoff` pushes and opens
the spec PR against the holder. Task branches, task PRs, and the commit
trailers stay in the work repository, because that is where the code changes.

**Alternatives considered:**
- Commit the bundle in the work repository as a pointer or submodule.
  Rejected because: the bundle then exists twice, and the derivation reads
  one of them.

**Chosen because:** the spec branch namespace, the sync hook's no-op rule,
and the worktree convention all key on the identifier, so they transfer to
the holder unchanged.

### D-13: The `plain` posture and execution independence  (N)

**Decision:** In `plain`, the authoring skills write files, create no spec
branch or worktree anywhere, and skip every commit, push, and PR step,
listing each skipped step in the handoff. Observation consume moves fragments
on disk with no commit, and carry is a no-op that says so. No state file is
introduced. The execution skills derive task state from the work repository
in every posture; the store's posture never blocks a dispatch, and the
Awaiting-input writes a halting skill makes land in the store as files.
*(Amended at kickoff 2026-09-22: the uncommitted-file shape applies in
`separate-repo` as well as `plain`, since a holder has no task branch to
carry the write; a halting execution skill never commits, branches, or
pushes in the holder, and the handoff names the file.)*

**Alternatives considered:**
- A store-local state file for the git-less case. Rejected because: it
  reopens the parallel-state-file design bootstrap rejected and contradicts
  the derived-never-stored invariant of format-version 2.
- Refusing execution when the store is `plain`. Rejected because: nothing in
  execution needs the store to have git.

**Chosen because:** the request was a git-less store, not git-less
execution, and the seeds show the sweep against a non-git tree already works
and is faster (obs:e144633c).

### D-14: The freshness gate's read surface per posture  (N)

**Decision:** The gate reads the bundle from the primary view: the default
branch's committed view of the primary checkout in `same-repo` (while a
worker writes its own worktree's copy), the holder's default branch's
committed view in `separate-repo`, the directory itself in `plain`. The
default branch is the remote HEAD where a remote exists, else the local
HEAD's branch, never assumed to be called `main`; an uncommitted edit in a
holder's working tree is outside the read surface, as it is today in the
work repository. The sanctioned anchor command forms are unchanged; the
resolution-aware logical form covers the holder and plain cases because it
resolves the tool, not the bundle. The reference-frame tolerance
(Status-line value substitution) applies unchanged in `same-repo` and
`separate-repo`; in `plain` there is no committed view to frame against, so
the gate compares against the files as they are. The normative home of the
read surface, `spec-format`'s execution-validity and reference-frame prose,
is amended by the doctrine task.

**Alternatives considered:**
- Copying the bundle into the work repository at dispatch. Rejected
  because: a second copy is a second source of truth.

**Chosen because:** the anchor is a hash over file content and never cared
which repository held the files.

### D-15: The worker write zone includes the root  (N)

**Decision:** The worker permission guard's containment set gains the
resolved spec root when it lies in a different repository from the work
repository or in none, so a worker can write an Awaiting-input entry or an
observation fragment in a holder or a plain store. The set is exactly the
work repository plus the resolved root; nothing else widens. The guard's
per-call check stays a git-free, config-free walk-up: the dispatcher
computes the root once at dispatch and hands it to the guard through the
worker settings the guard already reads, so no config resolution runs on
the hot path.

**Alternatives considered:**
- Route all store writes through the tower. Rejected because: it serialises
  every fragment write on the operator session.
- The guard resolving `spec_root` itself per call. Rejected because: a
  four-layer config resolution on every Bash tool call is the cost the
  guard's walk-up was designed to avoid.

**Chosen because:** the guard already canonicalizes and contains; adding one
root handed in at dispatch is a set change, not a policy change.

### D-16: Guards in a holder  (N)

**Decision:** A holder repository gets planwright's spec guards (validator,
store guard, anchor freshness, memory links) through a recipe the
spec-location guide documents: the `mise` task set the holder copies and
wires into its own check. `/builder` does not carry them, because they are
project-bespoke extensions outside the guard catalog, which carries only the
universal categories. A plain store runs no guards; the authoring handoff
says so.

**Alternatives considered:**
- Running the holder's checks from the work repository's CI. Rejected
  because: the work repository's CI has no reason to check out a second
  repository.
- Adding the spec guards to the guard catalog so `/builder` wires them.
  Rejected because: the catalog is the universal core by its own doctrine,
  and the spec guards apply only to a repository that holds planwright
  bundles.

**Chosen because:** a holder is a repository, and a documented recipe is the
smallest mechanism that wires repository-specific guards into it.

### D-17: The observation store follows the root  (N)

**Decision:** The observation scripts default their store to
`<resolved root>/_observations` under the checkout-local view, with
`--obs-dir` kept as the explicit override. Fragment identity, the
duplicate-UID refusal, and the carry mechanism operate per accumulator and
work in the holder posture, the carry branch living in the holder; in
`plain` carry is a no-op that says so.

**Alternatives considered:**
- A store option separate from `spec_root`. Rejected under D-5.

**Chosen because:** the scripts already take the store as a directory; only
the default moves.

### D-18: Named observation targets  (N)

**Decision:** An `observation_targets` config option maps aliases (the
identifier grammar) to roots as a flat inline map riding one config key, the
shape `dispatch_backend_per_spec` already uses; the machine-local or adopter
layer is the recommended home since the values are paths on one machine,
and the repo-tracked layer is not refused, since a `~/`-prefixed value is
legitimately trackable. `obs-record --target <alias>` writes the fragment
into the named root's accumulator after checking the alias, that the target
is by shape a marker-bearing root or the default root of a git checkout,
and that the fragment passes the hygiene screen: three fixed pattern
classes (an absolute path, a `~`-prefixed path, a dotted hostname ending in
a public suffix or in `.local` or `.internal`), listed in the spec-location
guide. The screen runs on every `--target` write; a fragment that fails it
is refused, not rewritten, and nothing is written. Whether a repository name
is private is the consumer's read at consumption. Nothing is ever sent to a
public surface without a human act. This is the same-machine delivery of
the cross-repo routing the `observation-routing` draft parked
(observation-recording D-9); the draft's fan-in inbox is folded here as the
rejected alternative below.

**Alternatives considered:**
- A machine-local inbox every `/spec-draft` mines (legacy L79's shape).
  Rejected because: it is a second accumulator with its own reader and drain
  ritual, and it exists only to defer a write the target root can take
  directly on the same machine.
- Public-adopter fan-in through issues. Rejected because: it is a different
  trust boundary (repositories the operator cannot read) and stays out of
  scope.
- A screen that refuses any path-shaped token. Rejected because: nearly every
  useful fragment names a file, so the screen would refuse the fragments it
  exists to route.

**Chosen because:** one operator's fleet on one machine is the case the
legacy line records, and a direct write to a validated root is the smallest
mechanism that serves it.

### D-19: The literal-`specs/` guard and CI wiring  (N)

**Decision:** A CI check flags every non-comment occurrence of the literal
`specs/` used as a path in `scripts/`, `githooks/`, the `mise.toml` task
bodies, `lefthook.yml`, `.gitignore`, and the CI workflows, outside the
resolver. The allowlist is by line, never by file, and admits three classes:
the resolver itself, the namespace literals D-11 keeps (the `Consumed-by`
writer, the alias mapper), and a static glob whose limitation is stated
here. Skills and docs are prose and may use the alias, but every skill step
that runs a command against the accumulator obtains the path from the
resolver. The spec checks `mise run check` runs obtain the root from the
resolver in their task bodies, and the scoped lint relaxation travels with
the root. The `lefthook` pre-commit glob keeps its literal as the stated
static-glob exception: a pre-commit hook sees only its own repository's
files, and for an in-repo relocated root the glob matches nothing staged, so
the pre-commit mirror stops firing while CI still runs the same check on
every PR; that limitation is accepted and documented.

**Alternatives considered:**
- Trusting review to catch new literals. Rejected because: the migration
  touches every site the guard flags, and the pattern re-grows silently.
- Scoping the guard to `scripts/` and `hooks/`. Rejected because: `hooks/`
  holds no code, and the literals that actually block a relocated root sit
  in the build configuration.

**Chosen because:** the repo's own doctrine prefers a comparator script over
an instruction an LLM follows.

### D-20: Doctrine and docs amendments  (N)

**Decision:** Every doctrine doc that states the spec home or the
accumulator home normatively is amended in one task before any
posture-dependent skill ships (REQ-G1.4): `storage-classes` states the
class-3 home as a location the human owns, scopes its "committed" attribute
to the git postures, records the posture ladder (`same-repo` recommended,
`separate-repo` for shared holders, `plain` supported with its skipped steps
named), classifies the marker as class-1 config, and re-anchors its class-2
interim note on this bundle; `spec-format` describes a spec as
`<root>/<spec>/` with `specs/` as the default at every site that states it,
its reserved-children list coordinated with the sibling specs that extend
(`tower-front-door`'s `_flights/`) or amend (`format-grammar`) the same
passage, and its execution-validity read surface stated per posture, all in
a dated versioning entry with no version bump; `accumulator-taxonomy`,
`orchestration-modes`, and the `plugin-script-invocation` example follow.
Every doc that states the spec home normatively (the options reference, the
overlays guide, conventions, getting-started, the README index and layout,
and a new spec-location guide) documents the option, the marker, the
postures, the named targets, and the holder guard recipe, in the docs task.

**Alternatives considered:**
- Leaving `spec-format` at `specs/<spec>/` and documenting the knob
  elsewhere. Rejected because: the meta-spec is the definition a reader
  authors from.
- Landing the doctrine amendments with the docs, last. Rejected because: the
  mechanism would ship for a while under doctrine that contradicts it, the
  state D-1 rejected.

**Chosen because:** every rule this spec changes has one normative home, and
the rule is stated as "every site" so no straggler survives a count.

### D-21: The reverse registry is deferred  (N)

**Decision:** A machine-local registry mapping roots back to work-repository
checkouts (class-2 runtime state, rebuilt by scanning known checkouts) is not
built. It is recorded as a gated Deferred entry keyed on a session that
starts in a holder needing to dispatch.

**Alternatives considered:**
- Building it now beside the marker. Rejected because: no session today
  starts in a holder and dispatches, so the registry would have no reader.

**Chosen because:** `proportionality` scopes ceremony to the risk exhibited,
and the marker is the identity a later registry keys on, so deferring it
costs nothing structural.

## Cross-cutting concerns

**Decision-domains walk.** Domains the feature touches and where each is
decided:

- *Secrets and configuration*: two new options (`spec_root`,
  `observation_targets`), both documented in the options reference and
  shipped dark (D-3, D-18, REQ-H1.3). Paths are not secrets; `~/` expansion
  keeps machine paths out of tracked layers. The tracked install-root pin
  names the checkout itself (D-10).
- *Data storage and modelling*: a new store home shape (the marker, the
  relocatable root); escalated and decided in D-4 and D-5 rather than
  defaulted.
- *API surface*: the spec argument on the identity seams changes (D-11) and
  new CLI flags appear (`--target`, `--posture`, `--primary`, `--init`);
  existing forms stay accepted, so the change is additive.
- *Authorization*: the worker permission zone widens by exactly one root,
  handed in at dispatch (D-15).
- *Concurrency*: two work repositories writing fragments into one holder
  land in separate per-project accumulators (D-5); a named-target write
  lands a UID-named file, the conflict-free shape `observation-recording`
  chose.
- *Deploy and migration*: none; every default is preserved and no existing
  file is rewritten (REQ-H1.2).
- *Observability*: `--explain` on every root kind (REQ-A1.8) and a warning
  on every skipped chain arm (REQ-C1.3).
- *Dependency adoption*: none.
- *Versioning*: the marker carries `layout: 1` so a later root layout can be
  told apart.
- *Existing-seam reuse*: the marker is the one minted mechanism; D-4 records
  why the overlay config seam and the adopter root's namespace segment do
  not fit. `observation_targets` reuses the config-knob seam.

**Security posture.** Path handling is the write-time trigger: every root
value is canonicalized and validated before use, relative values are
contained in the primary checkout, marker fields are validated against the
identifier grammar, a cross-root fragment write is hygiene-screened and
refused on failure (D-3, D-4, D-18), and the guard's trust chain is shared
while each guard keeps its own policy (D-9).
