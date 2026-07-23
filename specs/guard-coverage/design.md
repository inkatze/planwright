# Guard Coverage — Design

**Status:** Ready
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
`githooks/` directory (distinct from the pre-existing `hooks/`, which
holds the Claude Code plugin manifest `hooks.json` — an unrelated hook
system), wired via `git config core.hooksPath githooks`. Hook set:
`pre-push` rejects any push updating `refs/heads/main` by inspecting the
refspecs git passes on stdin (spelling-independent); `pre-rebase` rejects
rebase outright; `prepare-commit-msg` aborts when the source argument is
`commit` with a `HEAD`-equal SHA — a best-effort amend catcher, not a
clean signal: git gives client hooks no reliable amend flag, so this
also fires on the (rare, benign-to-block) `git commit -c HEAD`/`-C HEAD`
message-reuse forms, while `--amend -m`/`-F` arrives as source `message`
and slips past it entirely. The honest consequence: hook amend-detection
is an accident-catcher; the deny globs (worker) and `pre-push` (main
history) are the real amend/never-push-main guards. `commit-msg` rejects
`squash!`/`fixup!`/`amend!` subjects and screens the message against
D-5's hashed seed list (screening delivered
as Task 3's extension). Hook files are extensionless portable shell and
join `lint:shell`/`lint:fmt`/the D-12 check by shebang enumeration.
Hooks are the enforcement layer against accidental invocation and bind
humans too (with the accuracy note, per `githooks(5)`: `--no-verify`
skips `pre-push` and `commit-msg` but does **not** suppress
`prepare-commit-msg`, so a deliberate amend is unblocked by the
`--amend -m`/`-F` family or by temporarily unsetting `core.hooksPath`;
`git rebase --no-verify` bypasses `pre-rebase`);
per-commit hook latency across fleet commit volume is an accepted cost.
**Untrusted-checkout caveat (accepted residual, surfaced at kickoff):**
because `core.hooksPath` points at the tracked `githooks/`, checking out
an untrusted fork-PR branch that has modified a hook and then running any
covered git command executes that branch's hook code locally — an
arbitrary-code-execution vector inherent to tracked hooks. The mitigation
is the same caution running an untrusted checkout's tests already
requires (treat fork checkouts as untrusted; the hooks are small and
diff-reviewed); reviewers who need to be sure unset `core.hooksPath`
before operating on an untrusted branch. Recorded as risk-register
row 9. The worker-settings deny globs are demoted to best-effort
defense-in-depth, extended to cover the hook-bypass spellings
(`--no-verify`, `git -c`/`git config` `hooksPath` forms, crossed with
the push and amend families) so the glob layer backstops deliberate
worker bypass. Human-selected 2026-07-17.
*(Amended at kickoff walkthrough 2026-07-17: commit-msg seed screening
and hook-bypass glob extension added; human-binding made explicit.)*
*(Amended at kickoff lens pass 2026-07-17: `githooks/` dir replaces the
colliding `hooks/`; amend-detection boundary stated honestly
(`--amend -m/-F` glob-covered, `amend!` subjects added); linter
coverage of extensionless hooks; latency cost accepted.)*

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

### D-3: Hook wiring via a dedicated wire step, with absence detection  (N)

**Decision:** `core.hooksPath` is set by a dedicated idempotent wire
step (a `scripts/`-side helper the developer runs once per clone, plus
an explicit CI workflow step) — not by `install.sh`, which is the
`~/.claude` writer and by its own invariant never edits a clone's git
config, and not by a "worktree-creation flow", which is Claude Code's
native mechanism and offers no interposition point. The wire step and
the detection check are **separate**: the check only detects and never
auto-wires (auto-wiring from the check path would make the fail-loud
branch unreachable, since the check would always see a freshly-wired
clone), so an unwired clone stays a loud finding until the human or CI
runs the wire step. `core.hooksPath` is
clone-global: one wiring covers every worktree of the clone (and
affects them all — the blast radius is documented), so the hooks no-op
cleanly on a checkout whose branch lacks the `githooks/` files. The
detection check asserts `core.hooksPath` points at the tracked
`githooks/` dir *and* that all four hook files are present and
executable (git silently skips non-executable hooks — half-wired must
not pass). Its CI behavior is pinned decidable: CI wires explicitly
then verifies; the local check fails loudly on an unwired or
half-wired clone. Human-facing docs (CONTRIBUTING, getting-started)
are updated by the shipping task.
*(Amended at kickoff lens pass 2026-07-17: the named install.sh /
worktree-creation seam does not exist — re-homed to a dedicated wire
step; half-wired detection and the clone-global blast radius added.)*

**Alternatives considered:**
- Manual setup documented in README only. Rejected because: the
  autopilot reflex forbids relocating a memory burden onto the human;
  an unwired clone must be detected, not remembered.
- A repo-managed `.git/hooks` copy step. Rejected because: copies drift;
  `core.hooksPath` points at the tracked source of truth.
- Wiring through `install.sh`. Rejected because: install.sh is the
  `~/.claude` plugin writer and never touches a clone's git config
  (its own stated invariant); grafting git-config writes onto it
  breaks its ownership rule.

**Chosen because:** a dedicated, idempotent wire step is the only seam
that actually exists on every clone shape (dev clone, worker clone,
native worktree), and it makes the backstop's absence a tool-grounded
finding.

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
tracked text (text files only; the binary-exclusion rule is documented
with the normalization rules), normalizes candidate tokens identically —
emitting boundary-split and embedded-form candidates (identifier inside
a URL, `mailto:`, slug) so casual reformatting is still caught, with
in-scope and out-of-scope reintroduction shapes recorded here — hashes
in a single-process batched pass (one `perl -MDigest::SHA` pass — perl
with Digest::SHA is present on all target platforms — or equivalent, not
a fork-per-token, which `sha256sum`/`shasum` would otherwise force since
they digest a whole stream), and compares; it runs in the `check` aggregate everywhere,
including fork-PR CI, and fails closed on a missing, malformed, or
zero-hash seed file with a committed minimum-real-seed count as the
non-vacuity floor. Its content pass overlaps `scan:secrets`' tree read;
the overlap is accepted (different match classes). The plaintext
identifiers are provisioned by the human out-of-band at execution time
through a non-logging stdin path and never enter the repo. Recorded
caveat: the purged identifiers are low-entropy names, so their hashes
are offline-guessable by a determined party; the guard's threat model
is accidental re-introduction, not adversarial secrecy, and that
residual risk is accepted. Human-selected 2026-07-17.
*(Amended at kickoff lens pass 2026-07-17: fail-closed posture,
non-vacuity floor, embedded-form normalization, batched hashing,
binary scoping, and provisioning hygiene added.)*

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
`pull_request`, but only ever with a read-only token and zero stored
secrets. The REQ-C1.1 audit verifies the full reachable surface
(permissions, secret references, cache poisoning, artifact writes,
privileged `workflow_run` chains) against this premise; REQ-C1.2's
check mechanically pins it (no `pull_request_target` anywhere;
read-only *effective* per-job permissions on `pull_request`-reachable
jobs; no stored-secret reference — `secrets.*` excluding the workflow's
own `secrets.GITHUB_TOKEN`, governed by the read-only permissions
assertion — and no `secrets: inherit` reachable from `pull_request`,
including through reusable-workflow calls; write-holding `workflow_run`
workflows keep their base-branch filter and consume no PR artifacts).
Accepted residual: cache and artifact posture are audited once by
REQ-C1.1, not continuously pinned — the current workflows use no cache
or artifact actions, and cache-semantics assertions are brittle;
revisit if one lands. A falsifying audit finding reopens this decision
rather than being absorbed. Isolated-runner redesign is out of scope
unless the audit demands it. Human-selected 2026-07-17.
*(Amended at kickoff lens pass 2026-07-17: stored-secrets sharpening
(`GITHUB_TOKEN` exempt), `workflow_run`/effective-permissions/
`secrets: inherit` scope, and the cache/artifact audit-only residual
recorded.)*

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
closure pass: parse `mise.toml` task-graph edges (`depends`,
`depends_post`, `wait_for`), take the root set of tasks invoked from
workflow files, and fail if the closure reaches any `eval:`-namespace
task; task run bodies are scanned with the workflow pass's
invocation-form matching, and a run-body `mise run <task>` invocation
feeds the closure as a graph edge (second-order
run-body→depends→eval chains are caught). Parse boundary: `mise.toml`
only — file-based task definitions (`tasks/`, `.mise/tasks/`) are
outside the parse and recorded here as the accepted boundary. The
closure fails closed when `mise.toml` is present but unparseable or
parses to zero tasks, and when workflow parsing yields zero roots
while workflows exist. One guard, one registration, three passes
(workflow-text scan retained; graph closure and run-body scan added).
*(Amended at kickoff walkthrough 2026-07-17: edge kinds broadened,
run-body pass added.)*
*(Amended at kickoff lens pass 2026-07-17: run-body invocations feed
the closure; parse boundary and fail-closed posture recorded.)*

**Alternatives considered:**
- A separate `check:no-transitive-evals` script. Rejected because: two
  guards for one invariant splits the registration surface REQ-H1.2
  exists to keep coherent, and the failure story is the same invariant.

**Chosen because:** the depends-chain vector (obs:9de09feb) is a blind
spot of the existing guard, so the fix belongs in that guard's scope.

### D-8: Hard-fail committed budgets for test wall-clock  (N)

**Decision:** `check:test-time` enforces a committed per-file budget and
a suite-total budget — the `check:instructions` discipline applied to
time (explicit numbers, budget bumps are conscious, reviewed edits in
the PR that slows things; measured ≥ budget trips, matching that
guard's convention). The gate consumes a persisted sub-second timing
report emitted by the test runner during the single suite run and never
re-invokes the suite (a re-run would double CI wall-clock against
ci.yml's 15-minute cap); it fails closed on a missing report or a
discovered file with no timing entry. In CI — the reference runner the
budgets are measured on — exceeding either budget fails
`mise run check` outright; locally the gate warns loudly without
failing, since dev machines differ in core count and contention from
the calibration context. Budgets are measured and enforced in the same
scheduling context; the 30–50% headroom covers runner noise only, with
aggregate-contention effects noted (the `check` aggregate's added
concurrent guards lengthen suite wall-clock independent of test
changes). Initial values are set at execution from the measured
post-split, post-fixture baseline and recorded in the task's PR; the
budget config is a separate committed file, not `config/defaults.yml`
top-level keys (which would trip the options-reference tether).
Human-selected 2026-07-17.
*(Amended at kickoff lens pass 2026-07-17: report-driven wiring, no
suite re-run, fail-closed on missing entries, boundary operator, CI
hard-fail / local loud-warn split, measurement context, and budget-file
location pinned.)*

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
fixture is redundant) to fit the per-file split target before
`check:test-time` budgets are set, preserving coverage (assertion count
not reduced; suite passes before and after). Terminology: the *split
target* is the per-file ceiling Task 6 splits down to, proposed in its
PR from split feasibility and accepted at review; the *budget* is the
committed gate value Task 7 derives from the measured baseline plus
headroom. Task 7 depends on Task 6 and on every fixture-adding guard
task (1–5, 9, 10) so budgets are set against the full post-split,
post-fixture baseline, not the pathological current one — a budget set
before sibling guard fixtures land would turn their merges into
tripwires.
*(Amended at kickoff lens pass 2026-07-17: split-target vs budget
terms defined; Task 7 re-ordered after all fixture-adding tasks.)*

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
prose table and asserts both `caps_for()` in
`scripts/orchestrate-backends.sh` and `docs/fleet.md`'s
backend-capability table (a third restatement of the same data) match
it under a specified normalization contract (`n/a`↔`na`, "(default)"
and backticks stripped, fixed field order) so the test is green on
today's agreeing surfaces and fires only on real divergence; and
`check-options-reference` is widened to cover `docs/fleet.md`'s
knobs-table defaults against `config/defaults.yml`. Each tether fails
closed when either side parses to zero rows (the reformatted-to-empty
silent-no-op the options-reference zero-key guard already prevents) and
when a referenced file is missing.
*(Amended at kickoff lens pass 2026-07-17: `docs/fleet.md` backend
table folded into the capability tether; normalization contract and
zero-row fail-closed guards added.)*

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
`scripts/`, `tests/`, or `githooks/` that uses `cd` inside a command
substitution (`$(cd ...)` or backtick form) without a top-level
`unset CDPATH`. Enumeration is by shebang, not `*.sh` extension, so the
extensionless `githooks/` hook files (the reason the scope was widened)
are actually covered.
*(Amended at kickoff walkthrough 2026-07-17: `hooks/` added to scope.)*
*(Amended at kickoff lens pass 2026-07-17: scope dir corrected to
`githooks/`; shebang enumeration so extensionless hooks are covered.)*
The check's doc records the companion convention from the 2026-06-17
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
entries alongside it. Each entry declares its `category` and
core-vs-breadth placement; where the existing category enum has no fit
(test-time budget, house pattern), the entry ships with the
`doctrine/guard-catalog.md` §"Guard categories" amendment that adds the
category, and `tests/test-builder-guards.sh`'s dogfood assertion is
kept green (a repo-bespoke guard the builder is not expected to
reproduce is placed so the assertion does not demand it). The
pinned-action-freshness entry states its degraded-network posture (a
loud unknown, never a silent "fresh"). Repo-local values (budget
numbers, seed hashes) stay out of the catalog. Every shipped guard is
registered in the `check` aggregate, the guard catalog / dogfooding
list, and the docs (`docs/CONTRIBUTING.md` §"The quality gate") per
REQ-H1.2, and the registration invariant is itself held by a standing
check.
*(Amended at kickoff lens pass 2026-07-17: category/core-vs-breadth
declaration and category-enum amendment obligation, degraded-network
posture, and the doc/dogfooding registration surfaces added.)*

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

## Changelog

- 2026-07-22 (Task 2 execution, expression-only): corrected D-2's
  factual side-note on bypass mechanics against `githooks(5)` for the
  installed git (2.55): `--no-verify` does not suppress
  `prepare-commit-msg` (the amend accident-catcher's deliberate bypass
  is the `--amend -m`/`-F` family or temporarily unsetting
  `core.hooksPath`), and `git rebase --no-verify` does exist and
  bypasses `pre-rebase`. No decision changed: the hooks remain the
  accident-catching enforcement layer with deliberate human bypasses;
  only the description of which flag bypasses which hook was wrong.
