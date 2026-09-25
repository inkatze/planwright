# Core Guard Catalog

Every project carries a layer of decisions nobody should spend judgment
on: which formatter runs, which linter, whether secrets get scanned before
they land, whether CI gates the merge. These are the *mechanical* quality
guards — the ones a tool enforces and contributors stop arguing about. The
builder's job is to detect a project's stack, recommend the guards that
stack warrants, and apply them, so the project gets the floor a principal
engineer would set up without a human re-deciding it each time.

This doc is the normative home of the catalog: the guard categories, the
breadth dimensions, the extension model, and the line between what the
builder applies on its own and what it must escalate. The machine view is
[`config/guard-catalog.yaml`](../config/guard-catalog.yaml), read by
`scripts/builder-guards.sh` (the builder's testable detection core); the
builder skill (`skills/builder/SKILL.md`) drives that script and layers
judgment on top.

Citations: REQ-G1.2, REQ-G1.5, REQ-G1.7 · D-15, D-16, D-32 · human-gates REQ-D1.6.

## Guard categories

The core catalog is universal and mechanical: each category is a class of
guard that transfers across stacks, with the concrete tool resolved per
detected stack. Each bullet carries the machine id an entry's `category`
field takes; `tests/test-guard-catalog-schema.sh` holds the yaml to this list.

- **Formatter** (`formatter`). Deterministic code style, enforced not
  debated (`shfmt`, `ruff format`, `prettier`, `gofmt`, `rustfmt`).
- **Linter** (`linter`). Static correctness and style checks, including the
  prose and data-format linters that widen tool-grounding beyond code
  (`shellcheck`, `ruff`, `eslint`, `markdownlint`, `yamllint`, JSON
  validation).
- **Type-checker** (`type-checker`). Where the language has one (`mypy`,
  `tsc`); correctly absent on dynamically- or weakly-typed stacks, which is
  itself a signal that detection is real rather than a fixed checklist.
- **Test runner** (`test-runner`). The stack's test entry point (a shell
  test loop, `pytest`, the `package.json` test script).
- **Security / secret scan** (`security`). Secret detection over the
  history before it leaks (`gitleaks`); the entry point for dependency,
  vulnerability, and supply-chain scanning as the catalog grows.
- **Commit hook** (`commit-hook`). Commit-message discipline and pre-commit
  gating (conventional-commit linting).
- **CI gate** (`ci`). The aggregate check that runs every guard on every
  change, so the guards are enforced rather than merely available (a GitHub
  Actions workflow for v1's GitHub target).
- **Budget** (`budget`). A measured quantity gated against a committed
  ceiling that only a reviewed edit raises (test-suite wall-clock, an
  instruction layer's word count); the ceiling is repo config, never a
  catalog value.
- **House pattern** (`house-pattern`). A repo convention no general linter
  carries, held by a dedicated check instead of review memory (`unset
  CDPATH` before a `cd` in command substitution).

## Entry format

The catalog is data, not code (REQ-G1.5): the builder reads it, never the
other way round, so adding a guard is adding an entry — no edit to the
consuming script. Each entry is one mapping with scalar fields:

- **`id`** — stable kebab-case identifier.
- **`category`** — one of the categories above (or `breadth`).
- **`tool`** — the concrete tool the guard recommends.
- **`detect`** — space-separated detection signals: a glob matched by file
  name, a `dir/glob` matched by relative path, or the literal `git` (matches
  inside a git work tree). The guard fires when *any* signal matches. The
  literal `manual` never auto-fires (used by advisory breadth entries).
- **`core`** — `true` for the universal core catalog; absent or `false` for
  advisory breadth dimensions.

### Supported format

`scripts/builder-guards.sh` reads the catalog with a constrained awk reader —
it never sources or evaluates the file (REQ-H1.3) — recognizing only the
shape planwright's own catalog uses: list items at two-space indentation (the
`- id:` line), fields at four; scalars unquoted or double-quoted (a
single-quoted scalar or an inline `# ...` comment is kept verbatim in the
value). An entry outside this shape is silently skipped, so the reader warns
on stderr when a `guards:` or `breadth:` section is present but no entries
parsed (REQ-G1.5); a section-less catalog legitimately yields zero guards.
Broader YAML tolerance is an intentional non-goal.

## Breadth dimensions

The catalog reaches past the mechanical core into dimensions that matter but
resist a single drop-in tool: **documentation** coverage, **internationalization**,
**accessibility**, and **architecture** guidance. These are first-class
catalog entries so the builder can surface them as dimensions to weigh, and
so they grow over time (REQ-G1.5) — but they are advisory: the builder names
the dimension and the consideration rather than auto-applying a tool, and an
entry earns a concrete tool and `core: true` only when the dimension has
matured and the project opts in. Breadth entries never participate in the
mechanical dogfood set.

### Release tagging

A versioned artifact with no release automation is a recurring ceremony gap
(the [autopilot-reflex](autopilot-reflex.md) reflex): the version bump and the
signed tag fire only when a human remembers them. The `release-tagging` breadth
entry lets the builder recommend closing that gap. Like every breadth entry
it is advisory-only and carries `detect: manual`, so it never auto-fires from
a file glob and stays out of the `--core` mechanical set (REQ-G1.1, D-13). It
has two facets:

- **Detection facet.** The signal that the guard is worth recommending: the
  repo ships a **versioned artifact** (a `plugin.json`, `package.json`,
  `Cargo.toml`, `pyproject.toml`, or similar with a version field) **and has no
  release automation** (no release-PR workflow, no tag-publishing step). When
  the builder sees a versioned artifact whose releases are still cut by hand, it
  recommends the release-tagging machinery — it does not apply it.
- **Scaffold facet.** What the recommendation offers once accepted, all
  **opt-in** and resolved by the builder — never landed in an adopter repo
  without consent (REQ-G1.3, the [customization-boundary](customization-boundary.md)
  rule):
  - the **release-PR mechanism template** — `templates/release-please/`, a
    release-please PR-only workflow that maintains the proposal PR and never
    tags;
  - the **untagged-window lock template** — `templates/release-window/`, the
    required check that locks the window between the release-PR merge and the
    signed tag;
  - the **publish-script wiring** — planwright core's
    [`scripts/release-publish.sh`](../scripts/release-publish.sh), the
    signer-agnostic step that cuts the signed annotated tag on the observed
    release-merge commit.

The policy the scaffold realizes — detection and proposal automated,
approval is the human merge, publish human-gated and signed, the window
locked, merge and publish never crossed on the machine's own judgment — is
[release-tagging.md](release-tagging.md);
this entry is the builder-facing consent surface that doc's mechanism row
(capability in core, mechanism as opt-in template, value as config) points at.

### Instruction hygiene

A repo that authors an LLM instruction layer — agent skills, doctrine docs,
prompts — has a runtime artifact that degrades as it grows, yet no mechanical
guard watches its size. The `instruction-hygiene` breadth entry lets the builder
recommend closing that gap to an adopter whose repo ships such a layer. Like
every breadth entry it is advisory-only, its `detect: manual` trigger being the
builder's judgment that a repo authors instructions rather than a file glob.
What it recommends has two parts, both defined in
[instruction-hygiene.md](instruction-hygiene.md):

- **The size guard** — `scripts/check-instructions.sh`, the per-file /
  mandatory-at-start / reachable-closure word budgets, doctrine-manifest
  resolution, and injected-context measurement, wired into the project's `check`
  aggregate. Its two suppression forms (a permanent per-file exemption and a
  transitional `pending-diet` allowance) and the `--closeout` direction that
  forbids a lingering allowance once a retrofit completes are the adopter's
  equivalents of planwright's own prompt-hygiene remediation.
- **The kept prompt-eval convention** — the behavioral backstop for the size
  proxy: a fixture suite kept in the repo, run on demand (never in CI), gated
  pass^k, catching the case where a file passes the budget yet still degrades
  behavior.

A project-bespoke guard the way planwright's own spec validator and link-check
are (see [Dogfooding](#dogfooding)).

### Emit sidedness

The `emit-sidedness` entry recommends a prose heuristic flagging emit
mandates that name no destination side, turn or artifact, per
[interaction-style.md](interaction-style.md) (planwright's is
`scripts/check-sidedness.sh`). It runs in `check` reporting-only, never
gating: its heuristic has false positives, and a gate firing on them teaches
dodging.

### Pinned-action freshness

`pinned-action-freshness` (category `security`, breadth) recommends a check
that surfaces CI action SHA pins fallen behind their upstream tag. Signal
only: it reports, a human moves the pin, since a silent bump is itself a
supply-chain event. Degraded network is a loud unknown: an upstream it
cannot reach yields "could not decide", never "fresh".

### Test-time budget

`test-time-budget` (category `budget`, breadth) recommends per-file and
suite-total wall-clock ceilings over the test runner's timing report,
hard-failing on the reference runner and warning elsewhere, failing closed
on a missing report or an unlisted test file. planwright's instance is
`check:test-time` over `config/test-time-budget.yml`.

### CDPATH house pattern

`cdpath-house-pattern` (category `house-pattern`, breadth) recommends a
check that flags a `$(cd ...)` in any shell file with no top-level `unset
CDPATH`, enumerating by shebang or suffix and failing closed on zero files:
the convention holds only while a check holds it, since a harness that
unsets `CDPATH` masks the regression. planwright's is `check:cdpath`.

## Extension

Two growth paths, both without editing the consuming script (the
extensibility contract, REQ-G1.5):

- **Core catalog.** A guard or breadth dimension is added by writing an
  entry in the format above. Recurring observations from execution (a stack
  the catalog under-serves, a guard a mature project in the ecosystem runs
  that the catalog lacks) are the evidence an entry has earned its place, the
  same drain-loop growth the [decision-domains catalog](decision-domains.md)
  uses.
- **Adopter / project catalog.** A project with guards this seed list does
  not cover points the builder at its own catalog via the
  `PLANWRIGHT_GUARD_CATALOG` environment variable (or `--catalog <path>`),
  in the identical format. This is also the channel the decision-domains
  catalog's adopter-extension note defers to: project-specific decision and
  guard data live in project config, leaving planwright's shipped doctrine
  docs unedited (REQ-D2.2, REQ-I1.4).

### Overlay merge contract (supersede-by-id)

With no explicit `PLANWRIGHT_GUARD_CATALOG` / `--catalog` override,
[`scripts/builder-guards.sh`](../scripts/builder-guards.sh) reads the default
catalog through [`scripts/resolve-catalog.sh`](../scripts/resolve-catalog.sh)
(REQ-B1.3, D-5), which unions the shipped seed
([`config/guard-catalog.yaml`](../config/guard-catalog.yaml)) with the
adopter, repo-tracked, and machine-local overlay catalogs, lowest precedence
to highest (D-4). An overlay entry whose `id` is new is appended; one carrying
the target `id` plus `supersede: true` replaces that entry in place, the
marker stripped — the only way to override an existing entry. A supersede of
a non-existent target, an unreadable or entry-less overlay, and an overlay
file escaping its layer root (never read; D-8, REQ-E1.5) are malformed for
their layer (D-7, REQ-E1.4): repo-tracked hard-fails, adopter or
machine-local warns and degrades, and an absent layer degrades silently
(REQ-A1.4).
`resolve-catalog.sh guard-catalog --explain` names each entry's supplying
layer (D-9, REQ-B1.6); `docs/overlays.md` holds the layer model. An explicit
override bypasses the merge: the named catalog is used verbatim.

## Stake escalation: the builder does not flatten

The catalog is for decisions a tool can own; the no-flattening rule of
[engineering-decisions.md](engineering-decisions.md) governs the rest, with
the [decision-domains catalog](decision-domains.md) supplying the triggers. A
catalogued domain the spec or kickoff brief has not decided is never stamped
with a default: the builder escalates it as design / Needs human judgment
into a `GATE(when: …)` deferral entry (see
[finding-categorization.md](finding-categorization.md) and
[gate-wiring.md](gate-wiring.md)). Mechanical guards apply; load-bearing
decisions escalate. The builder advises and weighs
([proportionality.md](proportionality.md)), recording any departure from a
recommended guard with its reasoning, never silently.

## Dogfooding

planwright's own repository meets the quality bar its doctrine prescribes
(REQ-G1.7, D-32): the builder, run against planwright itself, reproduces the
core guard set Task 2 wired into `mise.toml` and `.github/workflows/ci.yml`
— formatter (`shfmt`), shell / prose / YAML / JSON linters, the shell test
runner, the secret scan (`gitleaks`), conventional-commit linting, and the
GitHub Actions CI gate — and recommends no type-checker, because the
shell-and-docs stack has none. `tests/test-builder-guards.sh` asserts this
reproduction on every CI run, grounded in planwright's actual wiring rather
than a hard-coded list, so removing a guard from the repo breaks the dogfood.

The dogfood reproduces the *universal core*. planwright also runs
project-bespoke guards, including the spec validator, the doctrine link, index,
options-reference and backend-capability tethers, the permission-matcher
fixture, the git-hook backstop and its wiring check, the purged-identifier,
workflow-posture and CI-eval-exclusion guards, the test-time budget, the
CDPATH and echo-safety house patterns, and the task-registration check that
keeps every `check:`/`lint:`/`scan:` task inside `check` — which are project
instances, not the universal core the builder reproduces for every adopter
(pinned-action freshness is catalogued but not yet run here).
Scoping the dogfood to the core (declared here per the proportionality rule)
keeps the guarantee honest: the builder reproduces what is universal, and the
project's own extensions stay the project's.
