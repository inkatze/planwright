# Custom spec location — Design

**Status:** Draft
**Last reviewed:** 2026-09-22
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new decision, minted in this bundle's drafting session
(2026-09-21 to 2026-09-22). Foreign IDs are namespace-qualified.

## Decision log

### D-1: Altitude — a capability seam plus a doctrine amendment  (N)

**Decision:** The deliverable sits at capability altitude with one doctrine
amendment beneath it. The capability is three resolvable roots (install,
primary checkout, spec) exposed as a seam every consumer reads through; the
mechanism is one resolver script plus the migrated callers; the doctrine
amendment widens `storage-classes`' class-3 home from "a git repository the
human owns" to "a location the human owns", with the git posture ladder
recorded there. The values (where a given operator's specs live, which
targets they route observations to) are overlay content and never land in
core.

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
one operator's value. The doctrine amendment is the part the seed claims
assert and a kickoff lens pass can verify.

### D-2: One resolver script, three root kinds  (N)

**Decision:** A single POSIX-sh script, `scripts/resolve-root.sh <kind>`,
with kinds `install`, `repo`, and `spec`, replaces every inline root
derivation. `repo` takes `--primary` (the worktree owning the common git
directory) or `--checkout` (the current toplevel); `spec` takes
`--canonical` (D-7) and `--explain` (REQ-A1.8). Every script that composes
`specs/` or calls `git rev-parse --show-toplevel` to find the repository is
migrated onto it, and the three scripts that assert the spec root's parent is
named `specs` drop the assertion, since a root outside the repository has no
such parent.

**Alternatives considered:**
- Three separate scripts. Rejected because: the kinds share the containment
  primitive, the explain output, and the by-layer policy; three copies is how
  the current divergence arose.
- A sourced shell library. Rejected because: the repo's convention for
  cross-script reuse is invocation by resolved path (`plugin-script-invocation`),
  and a sourced library cannot be called from a skill's Bash step.

**Chosen because:** one script is the smallest surface that makes the
literal-`specs/` guard (D-19) enforceable: the guard allowlists exactly one
file.

### D-3: The `spec_root` option and its value grammar  (N)

**Decision:** `spec_root` is a config option read through `config-get`
across the four layers, last-layer-wins, typed `path` in the shared knob
resolver. A value is absolute, `~/`-prefixed (expanded against `HOME`), or
relative to the primary checkout root. The value is canonicalized before use;
a relative value may not escape the primary checkout. Unset yields
`<checkout>/specs` with today's behaviour byte for byte. Malformed values
follow the customization-overlay by-layer policy.

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

**Chosen because:** the `version_file` knob is the precedent for a
path-valued option, and its recorded wart (canonicalized against the working
directory, contained against the toplevel) is exactly what anchoring relative
values to the primary checkout avoids.

### D-4: The root marker  (N)

**Decision:** A non-default root carries `planwright-root.yml`, a flat file
with `project: <id>` (the identifier grammar) and `layout: 1`. The resolver
refuses a configured root without it. The default root needs none, so
existing repositories are untouched. The resolver's `--init` flag, given a
directory, writes the marker; `/spec-draft` offers the init when the pointer
targets a directory without one.

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

**Chosen because:** git's own pointer shape (a gitfile pointing at a real
repository, never at a bare directory) shows the pointed-to end carrying its
identity; the marker is that identity, and it is class-1 config: human
authored, committed where the root is committed, readable without planwright.

### D-5: The reserved children follow the root  (N)

**Decision:** `_observations/` and `_pending/` are direct children of the
resolved root, wherever it is. One option relocates the whole spec home. In a
holder, each project's root has its own accumulator.

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

**Decision:** The resolver classifies the store by comparing the git
toplevel containing the canonical root with the primary checkout root:
`same-repo` when they are equal, `separate-repo` when the root has a
different toplevel, `plain` when it has none. The posture is printed beside
the root and in `--explain`, and every posture-dependent skill step reads it
rather than probing git itself.

**Alternatives considered:**
- Each skill probing `git rev-parse` in the root. Rejected because: that is
  the inline-copy pattern this spec removes.
- A declared posture in the marker. Rejected because: it would drift from the
  filesystem truth the resolver can observe directly.

**Chosen because:** three rungs are the whole space the requirements name,
and a derived classification cannot go stale.

### D-7: Two views of the root  (N)

**Decision:** By default the resolver returns the checkout-local root: in
`same-repo`, `<current toplevel>/specs` (or the configured relative path
under it), which is what every script sees today from inside a task
worktree. `--canonical` returns the primary checkout's root, the read surface
the freshness gate and the derivation engine use. An absolute value that lies
inside the primary checkout is re-based onto the current checkout for the
default view, so an in-repo root behaves the same whether it was written
relative or absolute. In `separate-repo` both views are the holder's
checkout; in `plain` they coincide. Config values
always resolve from the primary checkout, whichever view is asked for.

**Alternatives considered:**
- Always the primary checkout's root. Rejected because: an in-flight bundle
  amendment rides the task PR, so a worker must write its own worktree's copy;
  returning the primary's copy would make it edit the wrong tree.
- Always the current checkout's root. Rejected because: that is the bug the
  config-overlay observations record, and the gate's frame is normatively the
  primary main view.

**Chosen because:** the two consumers genuinely want different trees, and
naming the view at the call site is what keeps the compatibility requirement
(REQ-A1.1) honest.

### D-8: The primary checkout helper  (N)

**Decision:** `resolve-root.sh repo --primary` returns the directory owning
`git rev-parse --git-common-dir`, honouring `PLANWRIGHT_REPO_ROOT` first;
`--checkout` returns `git rev-parse --show-toplevel`. Outside a repository
both exit non-zero with a message. The overlay resolver's repo-side layers,
the worktree placement helper, and every inline `--show-toplevel` call that
meant "the repository" migrate to `--primary`.

**Alternatives considered:**
- Keep `--show-toplevel` and special-case the overlay resolver. Rejected
  because: the placement bug and the config bug share the cause, and the
  fleet scripts carry a dozen more copies.

**Chosen because:** `--git-common-dir` is the one worktree-aware call the
sync hook already uses; the helper makes it the rule instead of the
exception.

### D-9: The install-root helper  (N)

**Decision:** `resolve-root.sh install` owns the core root chain in the
documented order (`PLANWRIGHT_ROOT`, `CLAUDE_PLUGIN_ROOT`, the writer-mode
directory, self-location beside the script). An arm whose directory lacks
both `doctrine/` and `scripts/` is skipped with a warning. The rule-doc,
overlay-root, catalog, and knob resolvers, the anchor chain consumer, and
both command guards call it.

**Alternatives considered:**
- Leave each consumer's chain and add a drift test. Rejected because: the
  two guards already diverge, and a drift test would only report what a
  shared helper prevents.

**Chosen because:** the chain is documented once in `spec-format` and
`resolve-rule-doc.sh`; one implementation is the mechanical form of that
single definition.

### D-10: Self-hosting pins `PLANWRIGHT_ROOT`  (N)

**Decision:** The chain order stays as documented. A planwright checkout
pins `PLANWRIGHT_ROOT` to its own root through the tracked `mise.toml`
`[env]` table, so every session, test, and worktree of the checkout resolves
the tree under test rather than the installed plugin. A worktree inherits the
pin through mise's ancestor-directory loading, the same mechanism the
machine-local env layer already relies on.

**Alternatives considered:**
- Reorder the chain to try self-location first. Rejected because: an
  adopter overriding the root with `PLANWRIGHT_ROOT` on purpose would be
  silently outranked by whichever copy the script ran from.
- Detecting "am I a planwright checkout" in the helper. Rejected because: it
  is a heuristic where an explicit pin is available.

**Chosen because:** three observations record the same misresolution, and
one of them proposes exactly this pin.

### D-11: Spec addressing  (N)

**Decision:** The bare identifier is the canonical spec argument on every
seam; `specs/<id>` is accepted as an alias and mapped to the same identifier
before any path use. Branch names, worktree names, lock paths, commit
trailers, and the `Consumed-by: specs/<id>` line keep their forms: in each of
them `specs/` is a logical namespace, not a directory. The dispatch scope
grammar takes the identifier.

**Alternatives considered:**
- Accept any path to a bundle directory. Rejected because: it adds a
  rootless-bundle posture every writer must handle, and no seed wants it.
- Keep `specs/<id>` as the only form. Rejected because: the prefix would
  name a directory that no longer exists at that path.

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

**Decision:** In `plain`, the authoring skills write files and skip every
branch, commit, push, and PR step, listing each skipped step in the handoff.
Observation consume moves fragments on disk with no commit. No state file is
introduced. The execution skills derive task state from the work repository
in every posture; the store's posture never blocks a dispatch, and the
Awaiting-input writes a halting skill makes land in the store as files.

**Alternatives considered:**
- A store-local state file for the git-less case. Rejected because: it
  reopens the parallel-state-file design bootstrap rejected and contradicts
  the derived-never-stored invariant of format-version 2.
- Refusing execution when the store is `plain`. Rejected because: nothing in
  execution needs the store to have git.

**Chosen because:** the request was a git-less store, not git-less
execution, and the seeds show the sweep against a non-git tree already works
and is faster.

### D-14: The freshness gate's read surface per posture  (N)

**Decision:** The gate reads the bundle from the canonical root: the
holder's main view in `separate-repo`, the directory itself in `plain`. The
sanctioned anchor command forms are unchanged; the resolution-aware logical
form covers the holder and plain cases because it resolves the tool, not the
bundle. The reference-frame tolerance (Status-line value substitution)
applies unchanged in `same-repo` and `separate-repo`; in `plain` there is no
committed view to frame against, so the gate compares against the files as
they are.

**Alternatives considered:**
- Copying the bundle into the work repository at dispatch. Rejected
  because: a second copy is a second source of truth.

**Chosen because:** the anchor is a hash over file content and never cared
which repository held the files.

### D-15: The worker write zone includes the root  (N)

**Decision:** The worker permission guard's containment set gains the
resolved spec root when it lies outside the work repository, so a worker can
write an Awaiting-input entry or an observation fragment in a holder or a
plain store. The set is exactly the work repository plus the resolved root;
nothing else widens.

**Alternatives considered:**
- Route all store writes through the tower. Rejected because: it serialises
  every fragment write on the operator session.

**Chosen because:** the guard already canonicalizes and contains; adding one
root is a set change, not a policy change.

### D-16: Guards in a holder  (N)

**Decision:** A holder repository gets planwright's spec guards (validator,
store guard, anchor freshness, memory links) by running `/builder` there,
which is recommended in the docs and never forced. A plain store runs no
guards; the authoring handoff says so.

**Alternatives considered:**
- Running the holder's checks from the work repository's CI. Rejected
  because: the work repository's CI has no reason to check out a second
  repository.

**Chosen because:** `/builder` is the seam that wires guards into any
repository, and the holder is a repository.

### D-17: The observation store follows the root  (N)

**Decision:** The observation scripts default their store to
`<resolved root>/_observations`, with `--obs-dir` kept as the explicit
override. Fragment identity, the duplicate-UID refusal, and the carry
mechanism operate per accumulator and work in the holder posture, the carry
branch living in the holder.

**Alternatives considered:**
- A store option separate from `spec_root`. Rejected under D-5.

**Chosen because:** the scripts already take the store as a directory; only
the default moves.

### D-18: Named observation targets  (N)

**Decision:** An `observation_targets` config option maps aliases (the
identifier grammar) to roots as a flat inline map riding one config key, the
shape `dispatch_backend_per_spec` already uses, set in the machine-local or
adopter layer since the values are paths on one machine. `obs-record --target <alias>` writes
the fragment into the named root's accumulator after checking the alias, that
the target is a marker-bearing root or the default root of a git checkout,
and that the fragment carries no path, hostname, or private-repository
identifier; a fragment that fails the hygiene screen is refused, not
rewritten. Nothing is ever sent to a public surface without a human act.

**Alternatives considered:**
- A machine-local inbox every `/spec-draft` mines (legacy L79's shape).
  Rejected because: it is a second accumulator with its own reader and drain
  ritual, and it exists only to defer a write the target root can take
  directly on the same machine.
- Public-adopter fan-in through issues. Rejected because: it is a different
  trust boundary (repositories the operator cannot read) and stays out of
  scope.

**Chosen because:** one operator's fleet on one machine is the case the
legacy line records, and a direct write to a validated root is the smallest
mechanism that serves it.

### D-19: The literal-`specs/` guard and CI wiring  (N)

**Decision:** A CI check flags a literal `specs/` composed in `scripts/` or
`hooks/` code outside the resolver (comment lines and the resolver itself
exempt; skills and docs are prose and may use the alias). The spec checks
`mise run check` runs read the resolved root; the `lefthook` glob keeps its
literal because a pre-commit hook in a work repository only ever sees that
repository's files.

**Alternatives considered:**
- Trusting review to catch new literals. Rejected because: the migration
  touches a few dozen sites, and the pattern re-grows silently.

**Chosen because:** the repo's own doctrine prefers a comparator script over
an instruction an LLM follows.

### D-20: Doctrine and docs amendments  (N)

**Decision:** `storage-classes` states the class-3 home as a location the
human owns, records the posture ladder (`same-repo` recommended,
`separate-repo` for shared holders, `plain` supported with its skipped steps
named), and classifies the marker as class-1 config. `spec-format` describes
a spec as `<root>/<spec>/` with `specs/` as the default, in a dated
versioning entry with no version bump. The options reference, the overlays
guide, conventions, getting-started, and a new spec-location guide document
the option, the marker, the postures, and the named targets.

**Alternatives considered:**
- Leaving `spec-format` at `specs/<spec>/` and documenting the knob
  elsewhere. Rejected because: the meta-spec is the definition a reader
  authors from.

**Chosen because:** every rule this spec changes has one normative home, and
each is named here so no straggler survives.

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
  keeps machine paths out of tracked layers.
- *Data storage and modelling*: a new store home shape (the marker, the
  relocatable root); escalated and decided in D-4 and D-5 rather than
  defaulted.
- *API surface*: the spec argument on every seam changes (D-11) and a new
  CLI flag appears (`--target`); existing forms stay accepted, so the change
  is additive.
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

**Security posture.** Path handling is the write-time trigger: every root
value is canonicalized and validated before use, relative values are
contained in the primary checkout, marker fields are validated against the
identifier grammar, and a cross-root fragment write is hygiene-screened and
refused on failure (D-3, D-4, D-18).
