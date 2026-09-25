# Custom spec location — Tasks

**Status:** Ready
**Last reviewed:** 2026-09-22
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order. The compatibility fixture and the literal-path
guard (Task 4) deliberately gate every migration task after them, so no
caller migrates without the check that proves the default is unchanged.
Tasks 3, 5, and 6 are serialized because they edit the same scripts (the
anchor-freshness check; the dispatch fetch, lock, and dispatcher scripts),
not because either needs the other's result. The doctrine amendments
(Task 6.5) land before the posture-dependent skills (Tasks 7 and 8) so no
supported configuration ships while the doctrine still calls it wrong.

## Tasks

### Task 1 — The resolver: install and repo kinds

- **Deliverables:** `scripts/resolve-root.sh` with the `install` kind (the
  documented core chain, content-checked arms, warning on a skipped arm) and
  the `repo` kind (`--primary` via the common git directory, honouring a
  `PLANWRIGHT_REPO_ROOT` that names an existing git toplevel and refusing
  one that does not; `--checkout` via the toplevel, unaffected by the
  variable; non-zero outside a repository or in a bare repository with no
  primary working tree), `--explain` for both kinds; the `PLANWRIGHT_ROOT`
  pin in the tracked `mise.toml` `[env]` table as a config-root expansion;
  unit tests covering each arm, a worktree, a non-repo directory, a bare
  repository, a content-less arm, and the pin with a decoy
  `CLAUDE_PLUGIN_ROOT` set and the pin explicitly controlled.
- **Done when:** the tests pass; `resolve-root.sh repo --primary` run from a
  task worktree prints the primary checkout; `resolve-root.sh install` run
  from a worktree of this checkout, with a decoy `CLAUDE_PLUGIN_ROOT` set,
  prints that worktree; a chain arm pointed at an empty directory is skipped
  with a warning and never printed; a `PLANWRIGHT_REPO_ROOT` naming a
  non-repository is refused.
- **Dependencies:** none
- **Citations:** D-2, D-8, D-9, D-10 · REQ-A1.8, REQ-B1.1, REQ-B1.4,
  REQ-C1.1, REQ-C1.2, REQ-C1.3
- **Estimated effort:** 1 day

### Task 2 — The spec kind: option, marker, posture

- **Deliverables:** the `spec` kind of `scripts/resolve-root.sh`: the
  `spec_root` option through `config-get`, the `path` type added to
  `scripts/resolve-config-knob.sh`, value grammar and canonicalization, the
  bad-value rule (empty is unset and falls through; a non-printable byte
  follows the by-layer policy; a well-formed value naming a missing path, a
  non-directory, or an escaping relative path is refused in every layer
  with the supplying layer named and never falls back), the marker
  `planwright-spec-root.yml` requirement and `--init` (validates the value,
  bypasses the marker check for its target, writes the marker and, in a git
  repository, the ignore rules for the local-only entries; never creates
  the directory), posture classification by repository identity with
  `--posture`, the checkout-local and `--primary` views with re-basing of
  relative and in-repo absolute values, `--explain`; the `spec_root`
  options-reference row with the key absent from `config/defaults.yml`;
  unit tests for every value form and edge form (`~` alone, `~user`,
  padded whitespace), the missing marker, each posture including another
  worktree of the same repository and a gitignored in-repo root, and both
  views.
- **Done when:** with the option unset the resolver prints
  `<primary checkout>/specs` from the primary checkout and
  `<worktree>/specs` from a worktree; an empty machine-local value over a
  repo-tracked value falls through to the default; a configured directory
  without the marker, a missing directory, and an escaping relative value
  are each refused non-zero from every layer with the layer named; the same
  directory after `--init` resolves; the three postures classify correctly
  on fixtures; `--posture` and `--explain` carry the posture while the
  default output is the bare path; the options-reference check passes with
  the key absent.
- **Dependencies:** 1
- **Citations:** D-3, D-4, D-5, D-6, D-7 · REQ-A1.1, REQ-A1.2, REQ-A1.3,
  REQ-A1.4, REQ-A1.5, REQ-A1.8, REQ-A1.9, REQ-E1.1, REQ-H1.3
- **Estimated effort:** 1.5 days

### Task 3 — Converge the config, doctrine, catalog, and guard chains

- **Deliverables:** every script that runs the core root chain inline today
  (the overlay-root, config-get, rule-doc, and review-sequence resolvers,
  the inception scaffold, the anchor-freshness check) calls the Task 1
  helper for the install root; the scripts that delegate to one of those
  (the catalog and config-knob resolvers) are verified to run no chain of
  their own; both command guards obtain the chain from the helper and keep
  their own trust policy (the worker's installed-roots arm, the tower's
  distinct set); the repo-side overlay layers resolve against the primary
  checkout; a drift test asserting both guards derive the chain from the
  helper and that each guard's policy set is unchanged; the consumer
  locates the helper by self-location before asking it for the install
  root; the chain's prose definition consolidated on `spec-format` with the
  helper header and `plugin-script-invocation` pointing at it.
- **Done when:** a session in a task worktree resolves the primary checkout's
  `planwright.local.yml` values (the config-overlay observations'
  reproduction passes); the guard drift test passes; the golden fixture
  (Task 4) passes with this task's expected-change set (the worktree config
  correction, the writer-mode arm and skipped-arm warning gained by the
  shorter chains) declared; no script under `scripts/` other than the
  resolver runs the chain inline (grep-verified in the test).
- **Dependencies:** 1, 4
- **Citations:** D-8, D-9 · REQ-B1.2, REQ-C1.1, REQ-C1.3
- **Estimated effort:** 1 day

### Task 4 — Compatibility fixture and the literal-path guard

- **Deliverables:** a golden fixture test that records, from both the
  primary checkout and a worktree of a fixture repository with every new
  option unset, each script the later tasks migrate (printed paths and
  messages) plus the content anchor of every in-repo bundle, and replays
  the recording after each migration task against that task's declared
  expected-change set, failing on any difference outside it and on any
  named correction absent from every set; `scripts/check-spec-literals.sh`
  flagging a non-comment `specs/` used as a path in `scripts/`,
  `githooks/`, the `mise.toml` task bodies, `lefthook.yml`, `.gitignore`,
  and the CI workflows outside the resolver, wired into `mise run check`,
  with a by-line allowlist admitting the resolver, the namespace-literal
  sites D-11 keeps (the `Consumed-by: specs/<id>` writer and the alias
  mapper), and the static globs D-19 names.
- **Done when:** the golden test passes against the pre-migration scripts
  with an empty expected-change set; the guard flags a planted literal in
  each scanned location and passes on the resolver, on comment lines, and
  on the allowlisted sites; both run under `mise run check`.
- **Dependencies:** 2
- **Citations:** D-3, D-19 · REQ-G1.1, REQ-H1.1, REQ-H1.2
- **Estimated effort:** 1 day

### Task 5 — Migrate the script callers

- **Deliverables:** every script and build-config task that composes
  `specs/` as a path, infers the checkout from the root's parent, or derives
  the work repository from the spec directory's own toplevel, migrated onto
  the resolver (illustratively: the `tasks-pr-sync` hook; the fleet
  dispatchers, sweep, and fence; the fetch script; the tower watchdog; the
  orchestrate lock, state, and meta-select scripts and the status render
  through them; anchor freshness; the ledger, memory-links, and walkthrough
  scripts; the status-lifecycle migration default; worktree placement
  resolved against the owning repository's primary root; the `mise.toml`
  spec-check task bodies; and every other site the literal-path guard
  (Task 4) flags); the parent-named-`specs` assertions and the
  parent-derived checkouts removed; the scoped lint relaxation travelling
  with the root; tests updated to run a targeted relocated-root subset in
  each posture within the suite time budget.
- **Done when:** the golden fixture (Task 4) passes with this task's
  expected-change set (the worktree-placement correction) declared; the
  literal-path guard passes; the relocated-root subset passes with
  `spec_root` pointing at an in-repo subdirectory, an out-of-repo holder,
  and a plain directory, including the status render and meta-select
  against a holder; the worktree-placement observation's reproduction
  passes.
- **Dependencies:** 2, 3, 4
- **Citations:** D-2, D-8, D-19 · REQ-A1.6, REQ-A1.7, REQ-B1.3, REQ-E1.4,
  REQ-E1.6, REQ-G1.2
- **Estimated effort:** 2 days

### Task 6 — Spec addressing on the identity seams

- **Deliverables:** the bare identifier accepted as canonical and
  `specs/<id>` as an alias, a trailing slash tolerated, on every skill
  argument and identity seam that names a spec (illustratively the
  orchestrate, execute-task, kickoff, walkthrough, resume, and drain
  skills; the fetch, dispatch, consume, trailer, lock-name, and marker-name
  seams), with the alias mapped before any path use; the directory-taking
  scripts left as they are; the dispatch scope grammar's callers passing the
  bare identifier, with usage and error text naming the shape; tests for
  every accepted form and one rejected path form on each seam.
- **Done when:** every identity seam accepts the canonical form and the
  alias (with and without its trailing slash) and rejects a bundle-file
  path; branch, worktree, lock, trailer, and `Consumed-by:` forms are
  byte-identical to before (asserted by the golden fixture); the
  scope-grammar observation's reproduction passes.
- **Dependencies:** 2, 4, 5
- **Citations:** D-11 · REQ-D1.1, REQ-D1.2, REQ-D1.3
- **Estimated effort:** 1 day

### Task 6.5 — Doctrine amendments

- **Deliverables:** every doctrine doc that states the spec home or the
  accumulator home normatively amended: `storage-classes` (the class-3 home
  as a location the human owns, the "committed" attribute scoped to the git
  postures, the posture ladder, the marker as class-1, the class-2 interim
  note re-anchored on this bundle); `spec-format` (every `specs/` site
  reworded to `<root>/<spec>/` with `specs/` the default, the
  reserved-children list coordinated with `tower-front-door`'s `_flights/`
  and `format-grammar`'s queued amendment, the execution-validity read
  surface and reference frame stated per posture, all as one dated
  versioning entry with no bump); `accumulator-taxonomy`;
  `orchestration-modes`; the `plugin-script-invocation` example; the
  doctrine index rows.
- **Done when:** the doctrine-index and doc-link checks pass; a grep of
  `doctrine/` for `specs/` returns only the sites that state the default or
  the namespace; the `spec-format` versioning entry names every changed
  passage; the sibling specs' owners are named in the entry.
- **Dependencies:** 2
- **Citations:** D-1, D-14, D-20 · REQ-E1.5, REQ-G1.4
- **Estimated effort:** 1 day

### Task 7 — Authoring skills across the posture ladder

- **Deliverables:** `/spec-draft`, `/spec-kickoff`, `/spec-walkthrough`, and
  `/drain` read the root and posture from the resolver; in `separate-repo`
  the spec branch, worktree, commits, push, and PR target the holder; in
  `plain` no spec branch or worktree is created anywhere, every git step is
  skipped and named in the handoff, and the handoff names the absence of
  guards; `/spec-draft` offers the marker init on a marker-less target; the
  posture mechanics cited from the spec-location guide at point of use so
  the skills' instruction budgets stay within their guards; the two
  `[Gherkin]` scenarios (REQ-E1.2, REQ-E1.3) written for the on-demand
  behavioral-eval harness.
- **Done when:** the instruction budget check passes; the two scenarios run
  green under the on-demand harness (never in `mise run check`) and are
  inventoried by `/drain`'s manual sweep; a manual read of the plain-store
  handoff finds every skipped step and the guard absence named.
- **Dependencies:** 5, 6, 6.5
- **Citations:** D-12, D-13, D-16 · REQ-E1.2, REQ-E1.3, REQ-E1.8
- **Estimated effort:** 1.5 days

### Task 8 — Execution skills, the gate, and the worker write zone

- **Deliverables:** `/orchestrate`, `/execute-task`, and `/resume` read the
  bundle through the resolver's primary view; the freshness gate reads the
  default branch's committed view in the git postures and the directory in
  `plain`; the dispatcher computes the resolved root once and hands it to
  the worker permission guard through the worker settings, and the guard's
  containment set gains it when it lies outside the work repository; a
  halting execution skill's Awaiting-input and Deferred writes in
  `separate-repo` and `plain` left as uncommitted files in the store's
  primary view working tree and named in the handoff; tests for dispatch
  and the gate in each posture, including a holder whose default branch is
  not named `main`; the halt-write scenario written for the on-demand
  harness.
- **Done when:** a dispatch from a work repository whose root is a fixture
  holder derives state from the work repository's branches and reads the
  bundle from the holder; the gate halts on an anchor mismatch in each
  posture and passes on a match, including against a non-`main` default
  branch; a worker write inside the external root is allowed and a write
  beside it is still denied without the guard resolving config per call;
  the halt scenario leaves the note uncommitted with no new commit or branch
  in the holder under the on-demand harness.
- **Dependencies:** 5, 6, 6.5
- **Citations:** D-13, D-14, D-15 · REQ-E1.4, REQ-E1.5, REQ-E1.7, REQ-E1.9
- **Estimated effort:** 2 days

### Task 9 — Observations: store follows the root, named targets

- **Deliverables:** every observation script (record, consume, render, carry,
  store guard) defaults to `<resolved root>/_observations` under the
  checkout-local view, carry a stated no-op in `plain`; the
  `observation_targets` option with its options-reference row;
  `obs-record --target <alias>` with alias validation, target validation by
  shape, the three-pattern hygiene screen that refuses rather than rewrites,
  and a test suite covering a same-machine cross-root write, a refused
  fragment for each pattern class, an accepted fragment naming a
  repo-relative file, an unknown alias, a marker-less target, carry in a
  fixture holder, and a routing test asserting no remote write; every skill
  step that runs a command against the accumulator (illustratively the
  orchestrate crash-record line and the observation steps of the other
  skills) obtaining the path from the resolver instead of a literal.
- **Done when:** the tests pass; a fragment recorded with `--target` lands
  as a UID-named file in the target root's `entries/` and `check:obs` passes
  there; a fragment carrying an absolute path, a `~` path, or a hostname is
  refused with a message naming the screen while one naming a repo-relative
  file is written; the option ships empty; a grep of `skills/` finds no
  command line composing `specs/_observations`.
- **Dependencies:** 2, 4
- **Citations:** D-17, D-18 · REQ-A1.5, REQ-F1.1, REQ-F1.2, REQ-F1.3,
  REQ-F1.4, REQ-F1.5, REQ-H1.3
- **Estimated effort:** 1.5 days

### Task 10 — Documentation

- **Deliverables:** every doc that states the spec home normatively updated
  (illustratively the options rows, the overlays guide, conventions,
  getting-started, the README index and layout block) and a new
  `docs/spec-location.md` covering the option, the marker, the postures,
  the holder layout, the named targets and the screen's patterns, the
  holder guard recipe, and the note that a holder halt note is the
  operator's commit; the link checks.
- **Done when:** the doc-link check passes; the README index lists the new
  guide; a grep of `docs/` and `README.md` for `specs/` returns only sites
  that state the default or the namespace; the getting-started page shows
  the default and one relocated example.
- **Dependencies:** 7, 8, 9
- **Citations:** D-16, D-20 · REQ-G1.3
- **Estimated effort:** 1 day

## Awaiting input

- **Task 1** — push and draft PR pending: the branch `planwright/custom-spec-location/task-1` is implemented, converged (polish and panel review), and committed locally, but `git push` failed because the SSH agent refused to sign ("communication with agent failed"; a follow-up agent probe hung, likely on an unanswered approval prompt). Unlock or approve the agent, then push the branch and open the draft PR; the assembled PR body is in the handoff.

## Deferred

- **The reverse registry.** A machine-local registry mapping a root back to
  its work-repository checkout, rebuilt by scanning known checkouts, keyed on
  the marker. Confidence: high.
  **Gate:** a session that starts in a holder repository needs to dispatch
  execution.
  Citations: D-21.
- **Uncommitted store files in the drain sweep.** A `/drain` inventory of
  files a halting skill left uncommitted in a holder or plain store, so a
  forgotten halt note surfaces without the operator remembering the
  handoff. Confidence: medium.
  **Gate:** a holder halt note goes unnoticed past the handoff that named
  it.
  Citations: kickoff §8 K20 (2026-09-22) · REQ-E1.9.
- **Observation target classification.** Legacy L79's sub-problem (1):
  redefining the fragment tag to name the target or owner rather than the
  provenance, a doctrine change riding an `accumulator-taxonomy` amendment.
  Confidence: medium.
  **Gate:** an observation's target is misread as its provenance during a
  drain.
  Citations: legacy L79 (Sources) · kickoff §8 K20 (2026-09-22).

## Out of scope

- SaaS stores (Notion, Google Drive) as the spec store.
- Execution without a git work repository.
- Public-adopter observation fan-in through issues.
- Any change to sign-off, merge, or the never-auto-merge invariants.
