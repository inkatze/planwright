# Guard Coverage — Requirements

**Status:** Draft
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

planwright's hard invariants (never merge, never force-push, never amend,
squash, or rebase) and its CI honesty guarantees (evals never run in CI,
purged identifiers stay purged, docs do not silently drift from the
artifacts they restate) are protected by a guard surface that a 2026-07-16
full-accumulator triage confirmed has nine holes: best-effort permission
denies with no tests and no repo-side backstop, a secret scanner blind to
purged identifiers, an unaudited fork-PR execution path, a non-transitive
CI-eval exclusion, no test/CI wall-clock budget, untethered doc
restatements, unlinted templates, unrefreshed action pins, and an
unenforced house pattern. guard-coverage closes each hole with a
mechanical, tool-grounded guard or a recorded audit decision, wired into
`mise run check`, repo-side git hooks, or the core guard catalog, so
regressions in the invariant-protection layer are caught by tooling rather
than reviewer vigilance. The deliverable's altitude split — which pieces
are doctrine, capability, mechanism, and local value — is recorded in D-1
(cites the pinned altitude claim in Sources).

## Scope

### In scope

- Permission-deny hardening: fixture-driven matcher tests for
  `config/worker-settings.json` deny globs (extended to cover hook-bypass
  spellings) plus a repo-side git hook backstop (`githooks/`: `pre-push`,
  `pre-rebase`, `prepare-commit-msg`, `commit-msg`) enforcing
  never-amend/squash/fixup and never-push-main independent of flag
  position or refspec spelling, with the hooks' detection boundary
  stated honestly.
- A seeded purged-identifier check that fails CI when a known-purged
  work-repo or personal identifier reappears in the tracked tree, plus
  write-time and CI-side screening of commit messages against the same
  hashed seed list.
- The fork-PR CI isolation audit mandated by bootstrap REQ-J1.5, a
  recorded isolation decision, and only audit-driven hardening.
- Making the CI-eval exclusion transitive over `mise.toml` task-graph
  edges (`depends`, `depends_post`, `wait_for`) and task run-body
  invocations.
- A test/CI wall-clock budget gate (`check:test-time`), splitting or
  slimming the three straggler test files, and a doctrine amendment naming
  test/CI ergonomics an explicit Performance-lens target.
- Drift tethers: `doctrine/README.md` index completeness, the
  backend-capability-contract prose table vs the shipped `caps_for()`
  registry, and `docs/fleet.md`'s knobs-table defaults vs
  `config/defaults.yml`.
- `templates/**/*.md` joining `lint:md`.
- A pinned-action-freshness guard-catalog entry.
- A house-pattern check flagging `$(cd ...)` scripts lacking
  `unset CDPATH`.

### Out of scope

- Patching or reimplementing Claude Code's permission matcher.
- Promoting deny globs to a security boundary: the hooks are the
  enforcement layer against accidental invocation; globs stay
  best-effort defense-in-depth. Neither layer is a hard boundary against
  a determined bypass (`--no-verify`, `git -c core.hooksPath`); true
  server-side enforcement (branch protection) is out of scope here.
- An isolated-runner CI redesign, unless the fork-PR audit concludes it is
  required (the audit decides; this spec does not presuppose it).
- Automated action-pin bumping (freshness signal only, no update bot).
- Running evals in CI under any guard or flag.
- Suite-wide performance work beyond the named stragglers and the budget
  gate.
- Applying the new guards to adopter repos (the catalog describes; the
  builder applies).
- Reopening the bootstrap, prompt-hygiene, or output-hygiene bundles
  (their artifacts are extended via this spec, cited as Sources).
- Screening non-git-content surfaces for purged identifiers — PR titles
  and PR bodies (GitHub metadata, not committed content) and branch
  names (ephemeral and charset-validated). The purged-identifier guard
  covers the tracked tree and commit messages, the durable public
  vectors; the rest is an accepted residual.

## REQ-A — Worker permission-deny hardening

- **REQ-A1.1** A fixture-driven matcher test SHALL assert expected
  deny/allow outcomes of `config/worker-settings.json`'s rules for a table
  of `git push` and `git commit` invocations — force forms, `+refspec`,
  every `main` destination spelling (including flags placed after
  `main`), flag-after-arg amend/squash/fixup forms including the
  `--amend -m`/`--amend -F` family and `--fixup=amend:`/`--fixup=reword:`,
  hook-bypass forms (`--no-verify` in any position; `git -c` prefix and
  `git config` spellings of `core.hooksPath`, crossed with the push and
  amend forms), and legitimate feature-branch operations — against a
  documented re-implementation of Claude Code's literal-substring
  matcher, so a deny-list edit that re-opens a known evasion fails CI.
  The table SHALL mark which rows are load-bearing regression guards
  (expected-deny) versus honest documentation of a current allow, and
  the test SHALL fail if the parsed deny-rule set is empty or the config
  is unparseable.
  *(Cites: D-4, push-deny matcher note (Sources), commit-flag evasion
  note (Sources), kickoff lens pass (2026-07-17).)*
- **REQ-A1.2** Repo-side git hook backstops SHALL reject any push updating
  `refs/heads/main` and every amend/squash/fixup/rebase intent that
  carries a client-hook signal, regardless of flag spelling or position;
  the honest detection boundary SHALL be stated where it exists (an
  `--amend` combined with `-m`/`-F` reaches `prepare-commit-msg` with
  source `message` and no reliable amend signal, so that family is
  covered by the deny globs, not the hooks). The hooks are the
  enforcement layer against accidental invocation for the
  never-amend/squash/rebase and never-push-main invariants; the deny
  globs remain best-effort defense-in-depth, extended to cover the
  hook-bypass spellings (`--no-verify`, `git -c`/`git config`
  `hooksPath` forms) so a worker cannot bypass the hook layer with a
  spelling the glob layer never sees.
  *(Cites: D-2, commit-flag evasion note (Sources), push-deny matcher
  note (Sources), bootstrap REQ-J1.4, kickoff §3 REQ-A (2026-07-17),
  kickoff lens pass (2026-07-17).)*
- **REQ-A1.3** The hook backstop SHALL have a wiring path that covers
  worker clones and worktrees (a dedicated idempotent wire step — not
  `install.sh`, which is the `~/.claude` writer and never edits a
  clone's git config — invoked from the local check path and an explicit
  CI step; `core.hooksPath` is clone-global, shared by all worktrees,
  and the hooks SHALL no-op cleanly on a checkout where the hook files
  are absent). An unwired or half-wired clone SHALL be detectable by a
  check that asserts `core.hooksPath` points at the tracked `githooks/`
  dir and that all four hook files are present and executable, with its
  CI behavior a decidable predicate, never a silent skip.
  *(Cites: D-3, drafting-session decision (2026-07-17), kickoff lens
  pass (2026-07-17).)*

## REQ-B — Purged-identifier guard

- **REQ-B1.1** A seeded check in the `check` aggregate SHALL fail when a
  known-purged work-repo or personal identifier reappears anywhere in the
  tracked tree; the `commit-msg` hook backstop SHALL additionally screen
  commit messages against the same hashed seed list at write time, and a
  CI-side scan over the PR commit-message range SHALL back the hook so
  the permanent-history vector is closed for unwired clones and fork PRs
  too. The documented normalization SHALL emit boundary-split and
  embedded-form candidates (an identifier inside a URL, `mailto:`, or
  slug), with the in-scope and out-of-scope reintroduction shapes
  recorded in D-5.
  *(Cites: D-5, purged-identifier note (Sources), kickoff §3 REQ-B
  (2026-07-17), kickoff lens pass (2026-07-17).)*
- **REQ-B1.2** The committed seed file SHALL NOT contain the purged
  identifiers in plaintext; the check carries them only in a
  non-reversible committed form, with the plaintext provisioned by the
  human out-of-band through a non-logging path (read from stdin, never
  argv, echoed, or logged). The check SHALL enforce a committed
  minimum-real-seed count so it cannot run green with an empty or
  test-only seed file.
  *(Cites: D-5, kickoff lens pass (2026-07-17).)*

## REQ-C — Fork-PR CI isolation

- **REQ-C1.1** The fork-PR isolation audit mandated by bootstrap REQ-J1.5
  SHALL be performed over the `pull_request` execution path (permissions,
  secret references, cache poisoning, artifact writes) and its isolation
  decision recorded against D-6, with a falsifying finding reopening D-6
  rather than being absorbed silently.
  *(Cites: D-6, fork-PR isolation note (Sources), bootstrap REQ-J1.5.)*
- **REQ-C1.2** A mechanical check SHALL pin the audited posture: no
  workflow uses `pull_request_target`; every job reachable from
  `pull_request` has read-only *effective* permissions (job-level
  overrides computed, not top-level only); no stored-secret reference
  (`secrets.*` excluding the workflow's own `secrets.GITHUB_TOKEN`,
  whose privileges are governed by the read-only permissions assertion)
  and no `secrets: inherit` is reachable from a `pull_request` trigger,
  including through reusable-workflow `uses:` calls; and any
  `workflow_run` workflow holding write permissions or secrets retains
  its base-branch filter and consumes no PR-produced artifacts. A
  workflow edit breaking any of these SHALL fail CI, and a workflow
  file the check cannot parse SHALL fail rather than pass. Cache and
  artifact posture are examined by the REQ-C1.1 audit but carry no
  standing check — an accepted residual recorded in D-6.
  *(Cites: D-6, kickoff §3 REQ-C (2026-07-17), kickoff lens pass
  (2026-07-17).)*

## REQ-D — CI-eval exclusion transitivity

- **REQ-D1.1** The CI-eval exclusion SHALL be transitive: the guard fails
  when any CI-invoked mise task reaches an `eval:`-namespace task through
  any `mise.toml` task-graph edge (`depends`, `depends_post`,
  `wait_for`) or through task run-body invocations (a run-body
  `mise run <task>` feeds the closure as an edge, so second-order
  run-body→depends→eval chains are caught), not only when an eval
  invocation appears in workflow-file text. The parse boundary
  (`mise.toml` only; file-based task definitions excluded) SHALL be
  documented in D-7.
  *(Cites: D-7, obs:9de09feb, prompt-hygiene REQ-C1.6, kickoff §3 REQ-D
  (2026-07-17), kickoff lens pass (2026-07-17).)*

## REQ-E — Test/CI wall-clock budget

- **REQ-E1.1** A `check:test-time` gate SHALL enforce a committed
  wall-clock budget over the test suite — a per-file budget and a
  suite-total budget — from a persisted sub-second timing report the
  runner emits during the single suite run (the gate never re-invokes
  the suite). A budget is exceeded when the measured time is greater
  than or equal to the committed value. In CI (the reference runner the
  budgets are measured on) exceeding either budget fails
  `mise run check`; locally the gate warns loudly without failing.
  Budgets are measured and enforced in the same scheduling context, with
  headroom covering runner noise only.
  *(Cites: D-8, obs:cf6a2bd2, kickoff lens pass (2026-07-17).)*
- **REQ-E1.2** The three straggler test files (`test-check-instructions.sh`,
  `test-orchestrate-select.sh`, `test-obs-consume.sh`) SHALL be split or
  slimmed to fit the per-file split target (distinct from Task 7's
  enforced budget) without reducing coverage.
  *(Cites: D-9, obs:78f60119.)*
- **REQ-E1.3** The Discovery-Rigor Performance lens SHALL name test/CI
  ergonomics (suite wall-clock, CI latency) an explicit lens target, so
  reviewers apply the whole-system framing rather than a diff-scoped
  one; the mechanical catch itself is delivered by REQ-E1.1's gate.
  *(Cites: D-1, obs:cf6a2bd2, kickoff lens pass (2026-07-17).)*

## REQ-F — Drift tethers

- **REQ-F1.1** A check SHALL assert that `doctrine/*.md` (excluding
  `README.md`) and the `doctrine/README.md` index rows are in
  bijection — every doc has a row and every row maps to an existing doc,
  so a stale row for a deleted or renamed doc fails too, not only a
  missing row.
  *(Cites: D-10, doctrine-index note (Sources), kickoff lens pass
  (2026-07-17).)*
- **REQ-F1.2** A test (run via the suite within the `check` aggregate)
  SHALL assert that the backend-capability-contract prose table, the
  `caps_for()` registry in `scripts/orchestrate-backends.sh`, and
  `docs/fleet.md`'s backend-capability table agree, under a specified
  normalization contract (`n/a`↔`na`, annotations and backticks
  stripped) so the test is green on today's agreeing surfaces and fires
  only on real divergence.
  *(Cites: D-10, backend-caps drift note (Sources), kickoff lens pass
  (2026-07-17).)*
- **REQ-F1.3** A check SHALL tether `docs/fleet.md`'s knobs-table default
  values to `config/defaults.yml`, failing on divergence.
  *(Cites: D-10, fleet-knobs note (Sources).)*

## REQ-G — Lint scope and house patterns

- **REQ-G1.1** `templates/**/*.md` SHALL be covered by `lint:md`.
  *(Cites: D-11, obs:3b28dbe4.)*
- **REQ-G1.2** A check SHALL flag any script that uses `cd` inside a
  command substitution without a top-level `unset CDPATH`.
  *(Cites: D-12, CDPATH note (Sources).)*

## REQ-H — Guard catalog and guard robustness

- **REQ-H1.1** The core guard catalog SHALL gain a
  pinned-action-freshness entry that surfaces stale CI action SHA pins as
  a signal, with no automated bumping and a stated degraded-network
  posture (a loud unknown, never a silent "fresh"); each new catalog
  entry SHALL declare its category and core-vs-breadth placement,
  amending the catalog's category enum where none fits.
  *(Cites: D-13, pinned-action note (Sources), kickoff lens pass
  (2026-07-17).)*
- **REQ-H1.2** Every guard this spec ships SHALL be registered where the
  repo's guard inventory lives — the `check` aggregate, the guard catalog,
  or the docs, as applicable — so no guard is discoverable only by reading
  CI logs; the registration invariant SHALL be held by a standing
  mechanical check (every `check:`/`lint:`/`scan:` task wired into the
  `check` aggregate), with the one-time Task 11 sweep as its bootstrap.
  *(Cites: D-13, drafting-session decision (2026-07-17), kickoff lens
  pass (2026-07-17).)*
- **REQ-H1.3** Every guard this spec ships SHALL fail closed on missing,
  unparseable, or zero-entity input — a seed file with zero hashes, a
  workflow or `mise.toml` that cannot be parsed, a timing report missing
  an entry for a discovered test file, a reference table parsing to zero
  rows, a fixture whose setup fails — exiting non-zero rather than
  passing vacuously, and each guard's fixtures SHALL include the
  vacuous-input case.
  *(Cites: kickoff lens pass (2026-07-17).)*

## Changelog

- 2026-07-17 — Initial Draft elicited via `/spec-draft`: nine
  triage-confirmed guard gaps consolidated into one umbrella bundle.
  Fold-detection recommended a new spec over extending the Done
  bootstrap, prompt-hygiene, or output-hygiene bundles; the human
  confirmed. Four security-posture design forks (hook mechanism, seed
  representation, fork-PR posture, budget enforcement) resolved by
  explicit human selection.
- 2026-07-17 — Kickoff walkthrough and lens-pass amendments
  (meaning-class, human-dispositioned; brief §3 and §8): hook-bypass
  deny coverage (`--no-verify`, `git -c`/`git config` `hooksPath`
  forms, `--amend -m` family); commit-message seed screening at write
  time plus a CI-side range scan; stored-secrets sharpening
  (`GITHUB_TOKEN` exempt) and `workflow_run`/effective-permissions/
  `secrets: inherit` hardening with a cache/artifact audit-only
  residual; eval closure over all task-graph edge kinds and run-body
  invocations; hook layer re-homed to `githooks/` with a real wiring
  seam and half-wired detection; new REQ-H1.3 fail-closed posture and a
  standing registration check; `check:test-time` report-driven wiring,
  CI-hard-fail/local-warn split, and Task 7 re-ordered after all
  fixture-adding tasks; F1.2 tether extended to `docs/fleet.md`;
  doc-surface updates assigned; terminology aligned (seed file,
  split target vs budget).

## Sources

- **The invocation brief (2026-07-17).** The `/spec-draft` invocation
  enumerating the nine confirmed holes, the seed UIDs and legacy lines,
  and the fold-detection and security-escalation constraints.
- **The 2026-07-16 accumulator triage.** A ten-agent verification pass
  against v0.14.1 confirming every scope item valid (fork-PR isolation
  partial: safe posture exists, audit and isolation decision remain). The
  verdict ledger is a machine-local session record; its conclusions are
  restated here rather than referenced by path.
- **Pinned altitude claim.** obs:cf6a2bd2 asserts a doctrine gap, not
  only a missing tool: diff-scoped review lenses structurally cannot see
  whole-system wall-clock rot, so the Performance lens itself must name
  test/CI ergonomics a target. Resolved in D-1; carried by REQ-E1.3.
- **obs:cf6a2bd2** — pipeline perf-budget gap (2026-07-16): no test/CI
  wall-clock budget gate; boiling-frog suite slowness.
- **obs:78f60119** — suite stragglers (2026-07-16): parallel suite
  floored by three slow files; splitting beats more parallelism.
- **obs:3b28dbe4** — templates lint gap (2026-07-12): `lint:md` glob
  excludes `templates/**/*.md`.
- **obs:9de09feb** — CI-exclusion depends-chain vector (2026-07-12):
  `check:no-ci-evals` scans workflow text only; a transitive
  `mise.toml` depends chain is invisible.
- **Pinned-action note (2026-06-11, legacy observations).** CI action SHA
  pins have no freshness path; catalog-entry candidate.
- **Fork-PR isolation note (2026-06-11, legacy observations).** The
  REQ-J1.5 public-release re-audit of the `pull_request` execution path
  was mandated and remains outstanding.
- **CDPATH note (2026-06-17, legacy observations).** `unset CDPATH` is
  enforced only by convention; the test harness's own unset masks
  regressions.
- **Push-deny matcher note (2026-06-22, legacy observations).** The
  `git push` deny globs rest on untested manual reasoning about the
  literal-substring matcher; a real main-push evasion shipped past every
  structural check.
- **Purged-identifier note (2026-06-22, legacy observations).** gitleaks
  cannot flag re-introduced purged identifiers; a real re-leak was caught
  only by manual review.
- **Commit-flag evasion note (2026-06-23, legacy observations).** The
  amend/squash/fixup denies are flag-position-immediate;
  `git commit -a --amend` evades all three; the recommended robust fix is
  a git hook, not more globs.
- **Doctrine-index note (2026-07-02, legacy observations).** No check
  asserts every doctrine doc has a `doctrine/README.md` index row; a doc
  shipped unregistered.
- **Backend-caps drift note (2026-07-02, legacy observations).** The
  capability-contract prose table and `caps_for()` are stated twice with
  no drift guard.
- **Fleet-knobs note (2026-07-04, legacy observations).** `docs/fleet.md`
  restates six config defaults with no mechanical tether.
- **bootstrap bundle** (`specs/bootstrap/`, Done). Origin owner of
  `config/worker-settings.json`, the never-amend/squash/rebase invariant
  (bootstrap REQ-J1.4), the public-release gate (bootstrap REQ-J1.5), and
  the extensible core guard catalog this spec appends to.
- **prompt-hygiene bundle** (`specs/prompt-hygiene/`, Done). Owner of the
  `check:no-ci-evals` guard (prompt-hygiene REQ-C1.6) this spec widens.
- **output-hygiene bundle** (`specs/output-hygiene/`, Done). Owner of the
  derived-content-hygiene guard pattern the drift tethers instantiate.
