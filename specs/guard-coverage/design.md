# Guard Coverage — Design

**Status:** Draft
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new decision minted in this bundle. Human-selected
decisions record the selection date; the four security-posture forks
(D-2, D-5, D-6, D-8) were resolved by explicit human selection on
2026-07-17, per the decision-domains security-posture escalation rule
(never auto-defaulted).

## Decision log

### D-1: Altitude split of the guard-coverage deliverable  (N)

**Decision:** The deliverable is split across the altitude ladder and each
piece stays at its altitude: *doctrine* — the Performance-lens amendment
naming test/CI ergonomics an explicit target in
`doctrine/discovery-rigor.md` (REQ-E1.3); *capability* — guard-catalog
entries for the guard classes that generalize across adopter repos
(pinned-action freshness, test-time budget, CDPATH house pattern);
*mechanism* — the concrete checks, hooks, and tests shipped in this repo;
*local value* — the budget numbers and the hashed purged-identifier seed
list, which never enter core.

**Alternatives considered:**
- Mechanism-only spec (ship `check:test-time`, skip the doctrine
  amendment). Rejected because: the pinned altitude claim (Sources) is
  precisely that diff-scoped lenses structurally miss whole-system rot; a
  tool without the lens amendment leaves the next boiling-frog class
  (e.g. CI latency) invisible again.
- Promote the budget numbers or seed list into the core catalog. Rejected
  because: they are one repo's values; the customization-boundary default
  tilt keeps values local while mechanisms generalize.

**Chosen because:** the autopilot-reflex altitude gate fired on a seed
claim, and right-altitude placement (step 5) keeps doctrine from being
buried in a script and mechanism from rotting inside doctrine.

### D-2: Native tracked hooks dir as the invariant enforcement layer  (N)

**Decision:** The hook backstop ships as portable-shell hooks in a tracked
`hooks/` directory, wired via `git config core.hooksPath`. Hook set:
`pre-push` rejects any push updating `refs/heads/main` by inspecting the
refspecs git passes on stdin (spelling-independent); `pre-rebase` rejects
rebase outright; `prepare-commit-msg` aborts when invoked with the amend
signature; `commit-msg` rejects `squash!`/`fixup!` subjects. Hooks are
the enforcement layer; the worker-settings deny globs are demoted to
best-effort defense-in-depth. Human-selected 2026-07-17.

**Alternatives considered:**
- Adopt lefthook as hooks manager. Rejected because: a new supply-chain
  adoption running on every adopter machine (dependency-adoption
  checklist escalates it) for a job four small auditable scripts do;
  planwright's framework-script posture is plain portable shell.
- Matcher tests only, no hooks. Rejected because: leaves the
  flag-position amend evasion open at enforcement level; the 2026-06-23
  observation already concluded more deny globs cannot close it (a
  leading wildcard false-positives on commit messages containing the
  flag text).

**Chosen because:** git-native, zero new dependencies, auditable, and
worktrees inherit the repo-local `core.hooksPath` automatically.

### D-3: Hook wiring through the existing install path, with absence detection  (N)

**Decision:** `core.hooksPath` is set by the existing install/worktree
setup path (`install.sh` and the worktree-creation flow), and a check
task detects an unwired clone (hooksPath unset or not pointing at the
tracked `hooks/` dir). The check's CI behavior (wire-then-verify, or a
scoped skip with a loud reason) is an implementation detail with the
Done-when condition that it can never silently pass on an unwired
developer or worker clone.

**Alternatives considered:**
- Manual setup documented in README only. Rejected because: the
  autopilot reflex forbids relocating a memory burden onto the human;
  an unwired clone must be detected, not remembered.
- A repo-managed `.git/hooks` copy step. Rejected because: copies drift;
  `core.hooksPath` points at the tracked source of truth.

**Chosen because:** reuses the sanctioned install seam and makes the
backstop's absence a tool-grounded finding.

### D-4: Documented matcher re-implementation as the test oracle  (N)

**Decision:** REQ-A1.1's fixture test asserts deny/allow outcomes against
a small, documented re-implementation of Claude Code's permission
matcher semantics (literal-substring globs, deny-before-allow,
per-subcommand compound parsing). The helper documents which Claude Code
behavior version it models; implementation verifies the modeled semantics
against current Claude Code documentation (research-rigor
version-sensitive trigger) and records the sources consulted in the
kickoff brief risk register.

**Alternatives considered:**
- Drive the real Claude Code binary per fixture. Rejected because: no
  supported headless interface exercises permission evaluation in
  isolation; CI would gain a heavyweight, version-drifting dependency.
- No oracle, assert against hand-written expectations only. Rejected
  because: expectations without a documented matcher model re-encode the
  exact manual reasoning the 2026-06-22 observation flagged as the risk.

**Chosen because:** a documented model makes matcher assumptions
explicit and testable; when Claude Code's matcher changes, the model doc
is the single place the divergence surfaces.

### D-5: Hashed seed list, human-provisioned plaintext  (N)

**Decision:** The purged-identifier check carries SHA-256 hashes of
normalized identifiers in a committed seed file. The checker tokenizes
tracked text, normalizes candidate tokens identically, hashes, and
compares; it runs in the `check` aggregate everywhere, including fork-PR
CI. The plaintext identifiers are provisioned by the human out-of-band at
execution time and never enter the repo. Recorded caveat: the purged
identifiers are low-entropy names, so their hashes are offline-guessable
by a determined party; the guard's threat model is accidental
re-introduction, not adversarial secrecy, and that residual risk is
accepted. Human-selected 2026-07-17.

**Alternatives considered:**
- Machine-local plaintext seed, check skips in CI. Rejected because: the
  guard would be absent exactly where the seed observations demand it
  fire (CI), letting a re-leak merge and be caught late.
- Hybrid hashed-CI plus machine-local plaintext overlay. Rejected
  because: two code paths to test and keep honest, for marginal matching
  gain over normalization-plus-hashing.

**Chosen because:** full CI enforcement with nothing readable committed;
the accepted-risk caveat is recorded here rather than discovered later.

### D-6: Fork-PR posture — safe-by-construction, affirmed and pinned  (N)

**Decision:** The working posture: PR-authored code may execute under
`pull_request`, but only ever with a read-only token and zero secrets.
The REQ-C1.1 audit verifies the full reachable surface (permissions,
secret references, cache poisoning, artifact writes) against this
premise; REQ-C1.2's check mechanically pins it (no `pull_request_target`
anywhere, explicit read-only permissions on `pull_request` workflows, no
`secrets.*` reachable from them). A falsifying audit finding reopens
this decision rather than being absorbed. Isolated-runner redesign is
out of scope unless the audit demands it. Human-selected 2026-07-17.

**Alternatives considered:**
- Isolated-runner direction (lint-only on forks, full check on push).
  Rejected because: heavier CI machinery and degraded fork-contributor
  feedback, not evidenced as needed by the 2026-07-16 triage.
- Defer the posture entirely to the audit task. Rejected because: it
  guarantees a mid-execution Awaiting-input stall on a decision framable
  now; the audit still holds falsification power.

**Chosen because:** matches the current, verified CI configuration
(top-level `contents: read`, no secrets) and converts the posture from
implicit to mechanically pinned.

### D-7: Transitive eval detection inside the existing guard  (N)

**Decision:** `scripts/check-no-ci-evals.sh` gains a mise task-graph
closure pass: parse `mise.toml` task `depends` edges, take the root set
of tasks invoked from workflow files, and fail if the closure reaches any
`eval:`-namespace task. One guard, one registration, two passes
(workflow-text scan retained, graph closure added).

**Alternatives considered:**
- A separate `check:no-transitive-evals` script. Rejected because: two
  guards for one invariant splits the registration surface REQ-H1.2
  exists to keep coherent, and the failure story is the same invariant.

**Chosen because:** the depends-chain vector (obs:9de09feb) is a blind
spot of the existing guard, so the fix belongs in that guard's scope.

### D-8: Hard-fail committed budgets for test wall-clock  (N)

**Decision:** `check:test-time` enforces a committed per-file budget and
a suite-total budget; exceeding either fails `mise run check` outright —
the `check:instructions` discipline applied to time (explicit numbers,
budget bumps are conscious, reviewed edits in the PR that slows things).
Initial values are set at execution from the measured post-split
baseline plus 30–50% headroom (runner-noise margin) and recorded in the
task's PR. Human-selected 2026-07-17.

**Alternatives considered:**
- Warn-then-fail grace band. Rejected because: the warn band is where
  boiling-frog regressions live — the exact failure mode obs:cf6a2bd2
  documents.
- Total-only budget. Rejected because: a new straggler can hide inside
  total headroom; the current 9–10 minute file grew under precisely this
  blindness.

**Chosen because:** the repo already proved the pattern with
`check:instructions`; symmetry makes the gate legible.

### D-9: Split stragglers before budgeting  (N)

**Decision:** The three straggler files are split (or slimmed where a
fixture is redundant) to fit the per-file budget before `check:test-time`
budgets are set, preserving coverage (assertion count not reduced; suite
passes before and after). Task 7 depends on Task 6 so budgets are set
against the post-split baseline, not the pathological current one.

**Alternatives considered:**
- Budget first with generous limits, split later. Rejected because:
  budgets sized to today's stragglers ratify the pathology and never
  tighten (nobody revisits a green gate).

**Chosen because:** obs:78f60119 shows the wall-clock floor is the
stragglers, not parallelism; the budget should encode the healthy
baseline.

### D-10: Drift-tether mechanisms  (N)

**Decision:** Three tethers, each in the `check` aggregate:
`check:doctrine-index` asserts every `doctrine/*.md` (minus README) has
an index row in `doctrine/README.md` (mirror of
`check-options-reference`); a test parses the backend-capability-contract
prose table and asserts `caps_for()` in
`scripts/orchestrate-backends.sh` matches it (the doc table is the
source of truth); `check-options-reference` is widened to cover
`docs/fleet.md`'s knobs-table defaults against `config/defaults.yml`.

**Alternatives considered:**
- Drop the literal defaults from `docs/fleet.md` and point at the
  options reference. Rejected because: inline values are what makes the
  fleet doc readable standalone; a mechanical tether satisfies
  output-hygiene's cite-or-regenerate rule equally well.
- A single machine-readable capability-advertisement source that both
  the contract doc and `caps_for()` derive from. Rejected because: a
  generation step for a four-row table is heavier than a drift test;
  revisit if the backend set grows.

**Chosen because:** all three reuse existing, proven check shapes in
this repo, keeping each tether small and auditable.

### D-11: Templates join lint:md with a scoped config if needed  (N)

**Decision:** `templates/**/*.md` is added to the `lint:md` glob. If
template placeholder syntax trips markdownlint rules, a scoped
`.markdownlint.jsonc` inside `templates/` relaxes exactly those rules
(the `specs/.markdownlint.jsonc` precedent), never the global config.

**Alternatives considered:**
- Leave templates excluded. Rejected because: obs:3b28dbe4 records the
  drift risk; adopter-facing templates deserve at least the lint floor.

**Chosen because:** smallest change that closes the gap, with a
sanctioned precedent for the exception mechanism.

### D-12: CDPATH house-pattern check  (N)

**Decision:** A `lint:shell`-adjacent check flags any script under
`scripts/` or `tests/` that uses `cd` inside a command substitution
(`$(cd ...)` or backtick form) without a top-level `unset CDPATH`. The
check's doc records the companion convention from the 2026-06-17
observation: a script resolving paths via cd-substitution should get one
regression test running under `CDPATH=.` rather than relying on the
harness-wide unset.

**Alternatives considered:**
- Shellcheck custom rule / wrapper only. Rejected because: shellcheck
  has no CDPATH rule; a wrapper would still need the same grep logic
  with more moving parts.
- Convention plus review vigilance (status quo). Rejected because:
  `spec-walkthrough.sh` already shipped through `/polish` convergence
  missing the unset — vigilance demonstrably failed.

**Chosen because:** the pattern is mechanically detectable, and the
harness's own global unset actively masks regressions (the observation's
key finding), so only a dedicated check makes the gap visible.

### D-13: Catalog entries for the generalizable guard classes  (N)

**Decision:** The core guard catalog (`doctrine/guard-catalog.md` +
`config/guard-catalog.yaml`) gains a pinned-action-freshness entry
(signal-only: surface stale action SHA pins; never auto-bump), and the
guard classes this spec ships that generalize across adopter repos
(test-time budget, CDPATH house pattern) are registered as catalog
entries alongside it. Repo-local values (budget numbers, seed hashes)
stay out of the catalog. Every shipped guard is registered in the
`check` aggregate and docs per REQ-H1.2.

**Alternatives considered:**
- Pinned-action freshness as a repo-local check only. Rejected because:
  the 2026-06-11 observation explicitly frames it as a catalog-entry
  candidate for the builder's dependency-adoption dimension; any
  SHA-pinning adopter has the same freshness gap.
- Auto-bumping pins (Dependabot-style). Rejected because: out of scope
  by human decision; a silent pin bump is itself a supply-chain event
  that deserves human review.

**Chosen because:** capability-vs-style: the mechanisms generalize (core
catalog), the values are local (this repo's config).
