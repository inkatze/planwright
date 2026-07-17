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
  `config/worker-settings.json` deny globs plus a repo-side
  pre-commit/pre-push git hook backstop enforcing never-amend/squash/fixup
  and never-push-main independent of flag position or refspec spelling.
- A seeded purged-identifier check that fails CI when a known-purged
  work-repo or personal identifier reappears in the tracked tree.
- The fork-PR CI isolation audit mandated by bootstrap REQ-J1.5, a
  recorded isolation decision, and only audit-driven hardening.
- Making the CI-eval exclusion transitive over `mise.toml` `depends`
  chains.
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
- Promoting deny globs to a security boundary: the hooks become the
  enforcement layer; globs stay best-effort defense-in-depth.
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

## REQ-A — Worker permission-deny hardening

- **REQ-A1.1** A fixture-driven matcher test SHALL assert expected
  deny/allow outcomes of `config/worker-settings.json`'s rules for a table
  of `git push` and `git commit` invocations — force forms, `+refspec`,
  every `main` destination spelling, flag-after-arg amend/squash/fixup
  forms, and legitimate feature-branch operations — against a documented
  re-implementation of Claude Code's literal-substring matcher, so a
  deny-list edit that re-opens a known evasion fails CI.
  *(Cites: D-4, push-deny matcher note (Sources), commit-flag evasion
  note (Sources).)*
- **REQ-A1.2** Repo-side git hook backstops SHALL reject any push updating
  `refs/heads/main` and any amend/squash/fixup/rebase intent regardless of
  flag spelling or position; the hooks are the enforcement layer for the
  never-amend/squash/rebase and never-push-main invariants, and the deny
  globs remain best-effort defense-in-depth.
  *(Cites: D-2, commit-flag evasion note (Sources), push-deny matcher
  note (Sources), bootstrap REQ-J1.4.)*
- **REQ-A1.3** The hook backstop SHALL have an installation path that
  covers worker clones and worktrees, and an unwired clone SHALL be
  detectable by a check.
  *(Cites: D-3, drafting-session decision (2026-07-17).)*

## REQ-B — Purged-identifier guard

- **REQ-B1.1** A seeded check in the `check` aggregate SHALL fail when a
  known-purged work-repo or personal identifier reappears anywhere in the
  tracked tree.
  *(Cites: D-5, purged-identifier note (Sources).)*
- **REQ-B1.2** The committed seed list SHALL NOT contain the purged
  identifiers in plaintext; the check carries them only in a
  non-reversible committed form, with the plaintext provisioned by the
  human out-of-band.
  *(Cites: D-5.)*

## REQ-C — Fork-PR CI isolation

- **REQ-C1.1** The fork-PR isolation audit mandated by bootstrap REQ-J1.5
  SHALL be performed over the `pull_request` execution path (permissions,
  secret references, cache poisoning, artifact writes) and its isolation
  decision recorded against D-6, with a falsifying finding reopening D-6
  rather than being absorbed silently.
  *(Cites: D-6, fork-PR isolation note (Sources), bootstrap REQ-J1.5.)*
- **REQ-C1.2** A mechanical check SHALL pin the audited posture: no
  workflow uses `pull_request_target`, every workflow reachable from
  `pull_request` declares read-only permissions, and no `secrets.*`
  reference is reachable from a `pull_request` trigger; a workflow edit
  breaking any of these SHALL fail CI.
  *(Cites: D-6.)*

## REQ-D — CI-eval exclusion transitivity

- **REQ-D1.1** The CI-eval exclusion SHALL be transitive: the guard fails
  when any CI-invoked mise task reaches an `eval:`-namespace task through
  any `mise.toml` `depends` chain, not only when an eval invocation
  appears in workflow-file text.
  *(Cites: D-7, obs:9de09feb, prompt-hygiene REQ-C1.6.)*

## REQ-E — Test/CI wall-clock budget

- **REQ-E1.1** A `check:test-time` gate SHALL enforce a committed
  wall-clock budget over the test suite — a per-file budget and a
  suite-total budget — failing `mise run check` when either is exceeded.
  *(Cites: D-8, obs:cf6a2bd2.)*
- **REQ-E1.2** The three straggler test files (`test-check-instructions.sh`,
  `test-orchestrate-select.sh`, `test-obs-consume.sh`) SHALL be split or
  slimmed to fit the per-file budget without reducing coverage.
  *(Cites: D-9, obs:78f60119.)*
- **REQ-E1.3** The Discovery-Rigor Performance lens SHALL name test/CI
  ergonomics (suite wall-clock, CI latency) an explicit lens target, so
  wall-clock regressions become tool-grounded findings rather than
  diff-scoped blind spots.
  *(Cites: D-1, obs:cf6a2bd2.)*

## REQ-F — Drift tethers

- **REQ-F1.1** A check SHALL assert that every `doctrine/*.md` (excluding
  `README.md`) has an index row in `doctrine/README.md`.
  *(Cites: D-10, doctrine-index note (Sources).)*
- **REQ-F1.2** A check SHALL assert that the backend-capability-contract
  prose table and the `caps_for()` registry in
  `scripts/orchestrate-backends.sh` agree.
  *(Cites: D-10, backend-caps drift note (Sources).)*
- **REQ-F1.3** A check SHALL tether `docs/fleet.md`'s knobs-table default
  values to `config/defaults.yml`, failing on divergence.
  *(Cites: D-10, fleet-knobs note (Sources).)*

## REQ-G — Lint scope and house patterns

- **REQ-G1.1** `templates/**/*.md` SHALL be covered by `lint:md`.
  *(Cites: D-11, obs:3b28dbe4.)*
- **REQ-G1.2** A check SHALL flag any script that uses `cd` inside a
  command substitution without a top-level `unset CDPATH`.
  *(Cites: D-12, CDPATH note (Sources).)*

## REQ-H — Guard catalog

- **REQ-H1.1** The core guard catalog SHALL gain a
  pinned-action-freshness entry that surfaces stale CI action SHA pins as
  a signal, with no automated bumping.
  *(Cites: D-13, pinned-action note (Sources).)*
- **REQ-H1.2** Every guard this spec ships SHALL be registered where the
  repo's guard inventory lives — the `check` aggregate, the guard catalog,
  or the docs, as applicable — so no guard is discoverable only by reading
  CI logs.
  *(Cites: D-13, drafting-session decision (2026-07-17).)*

## Changelog

- 2026-07-17 — Initial Draft elicited via `/spec-draft`: nine
  triage-confirmed guard gaps consolidated into one umbrella bundle.
  Fold-detection recommended a new spec over extending the Done
  bootstrap, prompt-hygiene, or output-hygiene bundles; the human
  confirmed. Four security-posture design forks (hook mechanism, seed
  representation, fork-PR posture, budget enforcement) resolved by
  explicit human selection.

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
