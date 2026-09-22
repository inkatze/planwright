# Custom spec location — Tasks

**Status:** Draft
**Last reviewed:** 2026-09-22
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order. The compatibility fixture and the literal-path
guard (Task 4) deliberately gate every migration task after them, so no
caller migrates without the check that proves the default is unchanged.

## Tasks

### Task 1 — The resolver: install and repo kinds

- **Deliverables:** `scripts/resolve-root.sh` with the `install` kind (the
  documented core chain, content-checked arms, warning on a skipped arm) and
  the `repo` kind (`--primary` via the common git directory,
  `--checkout` via the toplevel, `PLANWRIGHT_REPO_ROOT` honoured first,
  non-zero outside a repository), `--explain` for both; the `PLANWRIGHT_ROOT`
  pin in the tracked `mise.toml` `[env]` table; unit tests covering each
  arm, a worktree, a non-repo directory, and a content-less arm.
- **Done when:** the tests pass; `resolve-root.sh repo --primary` run from a
  task worktree prints the primary checkout; `resolve-root.sh install` run
  from a worktree of this checkout prints that checkout; a chain arm pointed
  at an empty directory is skipped with a warning and never printed.
- **Dependencies:** none
- **Citations:** D-2, D-8, D-9, D-10 · REQ-B1.1, REQ-B1.4, REQ-C1.1,
  REQ-C1.2, REQ-C1.3
- **Estimated effort:** 1 day

### Task 2 — The spec kind: option, marker, posture

- **Deliverables:** the `spec` kind of `scripts/resolve-root.sh`: the
  `spec_root` option through `config-get` typed `path`, value grammar and
  canonicalization, the by-layer malformed policy, the marker requirement
  and `--init`, posture classification, the checkout-local and
  `--canonical` views, `--explain`; `spec_root` in `config/defaults.yml` with
  its options-reference row; unit tests for every value form, the missing
  marker, each posture, and both views.
- **Done when:** with the option unset the resolver prints `<checkout>/specs`
  from the primary checkout and `<worktree>/specs` from a worktree; a
  configured directory without the marker is refused non-zero; a relative
  value escaping the checkout is refused; the three postures classify
  correctly on fixtures; the options-reference check passes.
- **Dependencies:** 1
- **Citations:** D-3, D-4, D-5, D-6, D-7 · REQ-A1.1, REQ-A1.2, REQ-A1.3,
  REQ-A1.4, REQ-A1.5, REQ-A1.8, REQ-A1.9, REQ-E1.1, REQ-H1.3
- **Estimated effort:** 1.5 days

### Task 3 — Converge the config, doctrine, catalog, and guard chains

- **Deliverables:** `resolve-overlay-root.sh`, `config-get.sh`,
  `resolve-rule-doc.sh`, `resolve-catalog.sh`, `resolve-config-knob.sh`, the
  anchor chain consumer, and both command guards call the Task 1 helper for
  the install root and the primary root; the repo-side overlay layers resolve
  against the primary checkout; a drift test asserting the two guards trust
  the same arm set.
- **Done when:** a session in a task worktree resolves the primary checkout's
  `planwright.local.yml` values (the config-overlay observations'
  reproduction passes); the guard drift test passes; the golden fixture
  (Task 4) passes with the worktree correction asserted as the one change;
  no script under `scripts/` other than the resolver runs the chain inline
  (grep-verified in the test).
- **Dependencies:** 1, 4
- **Citations:** D-8, D-9 · REQ-B1.2, REQ-C1.1
- **Estimated effort:** 1 day

### Task 4 — Compatibility fixture and the literal-path guard

- **Deliverables:** a golden fixture test that runs each script the later
  tasks migrate against a fixture repository with every new option unset and
  asserts the printed paths and messages are unchanged (recorded before the
  migration, replayed after); `scripts/check-spec-literals.sh` flagging a
  literal `specs/` composed in `scripts/` or `hooks/` code outside the
  resolver, wired into `mise run check` with an allowlist for the resolver
  and comment lines.
- **Done when:** the golden test passes against the pre-migration scripts;
  the guard flags a planted literal and passes on the resolver; both run
  under `mise run check`.
- **Dependencies:** 2
- **Citations:** D-3, D-19 · REQ-G1.1, REQ-H1.1
- **Estimated effort:** 1 day

### Task 5 — Migrate the script callers

- **Deliverables:** every script that composes `specs/` or infers the
  checkout from the root's parent migrated onto the resolver: the
  `tasks-pr-sync` hook, the fleet dispatchers and sweep, the fetch script,
  the tower watchdog, the orchestrate lock, anchor freshness, the ledger,
  memory-links, and walkthrough checks, the status-lifecycle migration
  default, worktree placement resolved against the primary root, and any
  other site the literal-path guard (Task 4) flags; the parent-named-`specs`
  assertions removed; tests updated to run against a
  relocated fixture root in each posture.
- **Done when:** the golden fixture (Task 4) still passes with the option
  unset; the literal-path guard passes; the same suite passes with
  `spec_root` pointing at an in-repo subdirectory, an out-of-repo holder,
  and a plain directory; the worktree-placement observation's reproduction
  passes.
- **Dependencies:** 2, 4
- **Citations:** D-2, D-8 · REQ-A1.6, REQ-A1.7, REQ-B1.3, REQ-E1.6,
  REQ-G1.2
- **Estimated effort:** 2 days

### Task 6 — Spec addressing on every seam

- **Deliverables:** the bare identifier accepted as canonical and
  `specs/<id>` as an alias on every script flag and skill argument that takes
  a spec (the orchestrate, execute-task, kickoff, walkthrough, resume, and
  drain skills; the fetch, select, state, status, graph, lock, and dispatch
  scripts), with the alias mapped before any path use; the dispatch scope
  grammar aligned; tests for both forms on each seam.
- **Done when:** every seam accepts both forms and rejects any other; branch,
  worktree, lock, trailer, and `Consumed-by:` forms are byte-identical to
  before (asserted by the golden fixture); the scope-grammar observation's
  reproduction passes.
- **Dependencies:** 2, 4
- **Citations:** D-11 · REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-H1.2
- **Estimated effort:** 1 day

### Task 7 — Authoring skills across the posture ladder

- **Deliverables:** `/spec-draft`, `/spec-kickoff`, `/spec-walkthrough`, and
  `/drain` read the root and posture from the resolver; in `separate-repo`
  the spec branch, worktree, commits, push, and PR target the holder; in
  `plain` every git step is skipped and named in the handoff; `/spec-draft`
  offers the marker init on a marker-less target; the skills' instruction
  budgets stay within their guards.
- **Done when:** a scripted authoring run against a fixture holder lands the
  bundle on `planwright/<id>/spec` in the holder with no write to the work
  repository; the same run against a plain directory writes four files, makes
  no git call in the store, and lists the skipped steps; the instruction
  budget check passes.
- **Dependencies:** 5, 6
- **Citations:** D-12, D-13, D-16 · REQ-E1.2, REQ-E1.3, REQ-E1.8
- **Estimated effort:** 1.5 days

### Task 8 — Execution skills, the gate, and the worker write zone

- **Deliverables:** `/orchestrate`, `/execute-task`, and `/resume` read the
  bundle through the resolver's canonical view; the freshness gate reads the
  holder's main view in `separate-repo` and the directory in `plain`; the
  worker permission guard's containment set gains the resolved root when it
  lies outside the work repository; tests for dispatch and the gate in each
  posture.
- **Done when:** a dispatch from a work repository whose root is a fixture
  holder derives state from the work repository's branches and reads the
  bundle from the holder; the gate halts on an anchor mismatch in each
  posture and passes on a match; a worker write inside the external root is
  allowed and a write beside it is still denied.
- **Dependencies:** 5, 6
- **Citations:** D-13, D-14, D-15 · REQ-E1.4, REQ-E1.5, REQ-E1.7
- **Estimated effort:** 2 days

### Task 9 — Observations: store follows the root, named targets

- **Deliverables:** the record, consume, render, carry, and store-guard
  scripts default to `<resolved root>/_observations`; the
  `observation_targets` option with its options-reference row;
  `obs-record --target <alias>` with alias validation, target validation, the
  hygiene screen that refuses rather than rewrites, and a test suite covering
  a same-machine cross-root write, a refused unhygienic fragment, an unknown
  alias, and carry in a fixture holder; the two skill-drift observations'
  hardcoded targets replaced.
- **Done when:** the tests pass; a fragment recorded with `--target` lands
  as a UID-named file in the target root's `entries/` and `check:obs` passes
  there; a fragment carrying a source path is refused with a message naming
  the screen; the option ships empty.
- **Dependencies:** 2, 4
- **Citations:** D-17, D-18 · REQ-F1.1, REQ-F1.2, REQ-F1.3, REQ-F1.4,
  REQ-F1.5, REQ-H1.3
- **Estimated effort:** 1.5 days

### Task 10 — Doctrine and documentation

- **Deliverables:** the `storage-classes` amendment (class-3 home, the
  posture ladder, the marker as class-1); the `spec-format` wording
  (`<root>/<spec>/`, `specs/` default) as a dated versioning entry with no
  bump; the overlays guide, conventions, getting-started, and a new
  `docs/spec-location.md` covering the option, the marker, the postures, the
  holder layout, and named targets; the doctrine index and link checks.
- **Done when:** the doctrine-index, doc-link, and instruction-budget checks
  pass; every rule this spec changes has exactly one normative home named in
  the docs; the getting-started page shows the default and one relocated
  example.
- **Dependencies:** 7, 8, 9
- **Citations:** D-1, D-20 · REQ-G1.3, REQ-G1.4
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

- **The reverse registry.** A machine-local registry mapping a root back to
  its work-repository checkout, rebuilt by scanning known checkouts, keyed on
  the marker. Confidence: high.
  **Gate:** a session that starts in a holder repository needs to dispatch
  execution (surfaced free-text condition).
  Citations: D-21.

## Out of scope

- SaaS stores (Notion, Google Drive) as the spec store.
- Execution without a git work repository.
- Public-adopter observation fan-in through issues.
- Any change to sign-off, merge, or the never-auto-merge invariants.
