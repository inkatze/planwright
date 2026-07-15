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

Citations: REQ-G1.2, REQ-G1.5, REQ-G1.7 · D-15, D-16, D-32.

## Guard categories

The core catalog is universal and mechanical: each category is a class of
guard that transfers across stacks, with the concrete tool resolved per
detected stack.

- **Formatter.** Deterministic code style, enforced not debated (`shfmt`,
  `ruff format`, `prettier`, `gofmt`, `rustfmt`).
- **Linter.** Static correctness and style checks, including the
  prose and data-format linters that widen tool-grounding beyond code
  (`shellcheck`, `ruff`, `eslint`, `markdownlint`, `yamllint`, JSON
  validation).
- **Type-checker.** Where the language has one (`mypy`, `tsc`); correctly
  absent on dynamically- or weakly-typed stacks, which is itself a signal
  that detection is real rather than a fixed checklist.
- **Test runner.** The stack's test entry point (a shell test loop, `pytest`,
  the `package.json` test script).
- **Security / secret scan.** Secret detection over the history before it
  leaks (`gitleaks`); the entry point for dependency and vulnerability
  scanning as the catalog grows.
- **Commit hook.** Commit-message discipline and pre-commit gating
  (conventional-commit linting).
- **CI gate.** The aggregate check that runs every guard on every change, so
  the guards are enforced rather than merely available (a GitHub Actions
  workflow for v1's GitHub target).

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

### Supported format (the reader is constrained, not a full YAML parser)

`scripts/builder-guards.sh` reads the catalog with a deliberately minimal awk
reader — it never sources or evaluates the file (the data-not-code discipline,
REQ-H1.3). It recognizes the exact shape planwright's own catalog uses, and
only that shape:

- **Indentation is fixed:** list items at two-space indentation (the `- id:`
  line), their fields at four spaces (`category:`, `tool:`, and so on).
  Reflowed indentation is not parsed.
- **Scalars are unquoted or double-quoted.** Single-quoted scalars (`'*.sh'`)
  and inline `# ...` comments after a value are not stripped, so they would be
  kept verbatim in the value and detection would not match.

An entry written outside this shape is silently skipped. To keep that from
becoming an invisible failure for adopter extensions (REQ-G1.5), the reader
warns on stderr when a `guards:` or `breadth:` section is present but no
entries parsed — the signal that the format, not the content, is the problem.
A section-less catalog legitimately yields zero guards and is not flagged.
Broader YAML tolerance is an intentional non-goal: extend the catalog by
following the shape above.

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
entry lets the builder recommend closing that gap. It is **advisory-only** —
surfaced through the builder's existing consent flow, never auto-applied, and
absent from the `--core` mechanical set (REQ-G1.1, D-13). It has two facets:

- **Detection facet.** The signal that the guard is worth recommending: the
  repo ships a **versioned artifact** (a `plugin.json`, `package.json`,
  `Cargo.toml`, `pyproject.toml`, or similar with a version field) **and has no
  release automation** (no release-PR workflow, no tag-publishing step). When
  the builder sees a versioned artifact whose releases are still cut by hand, it
  recommends the release-tagging machinery — it does not apply it. (The machine
  view carries `detect: manual`: like every breadth entry the guard never
  auto-fires from a file glob; the detection heuristic here is the builder's
  judgment prompt, not a mechanical trigger.)
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

The policy the scaffold realizes — detection and proposal automated, approval
is the human merge, publish is human-gated and signed, the window is locked, and
merge and publish are never autonomous — is [release-tagging.md](release-tagging.md);
this entry is the builder-facing consent surface that doc's mechanism row
(capability in core, mechanism as opt-in template, value as config) points at.

### Instruction hygiene

A repo that authors an LLM instruction layer — agent skills, doctrine docs,
prompts — has a runtime artifact that degrades as it grows, yet no mechanical
guard watches its size. The `instruction-hygiene` breadth entry lets the builder
recommend closing that gap to an adopter whose repo ships such a layer. Like
every breadth dimension it is **advisory-only**: surfaced through the builder's
consent flow, never auto-applied, `detect: manual` (it never fires from a file
glob — the trigger is the builder's judgment that a repo authors instructions,
not a mechanical signal), and absent from the `--core` mechanical set. What it
recommends has two parts, both defined in
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

This is a project-bespoke guard the way planwright's own spec validator and
link-check are (see [Dogfooding](#dogfooding)): catalogued so the builder can
carry it to an adopter that authors instructions, advisory so it is never
stamped onto a repo that does not.

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

The guard catalog is one of the two growable catalogs the
customization-overlay mechanism resolves through
[`scripts/resolve-catalog.sh`](../scripts/resolve-catalog.sh) (REQ-B1.3, D-5);
this is the merge contract bootstrap Task 16 consumes rather than re-deciding.
When the builder reads the default catalog (no explicit
`PLANWRIGHT_GUARD_CATALOG` / `--catalog` override),
[`scripts/builder-guards.sh`](../scripts/builder-guards.sh) reads it through
that resolver, which unions the shipped seed
([`config/guard-catalog.yaml`](../config/guard-catalog.yaml)) with the adopter,
repo-tracked, and machine-local overlay catalogs — `catalogs/guard-catalog.yaml`
under the adopter and repo-tracked roots, `catalogs.local/guard-catalog.yaml`
for the machine-local layer — lowest precedence to highest (D-4). The contract:

- **Append/union.** An overlay entry whose `id` is new is added to the seed.
- **Supersede-by-id.** To replace a seed (or lower-layer) entry, an overlay
  entry carries the target `id` plus the marker `supersede: true`; it replaces
  that entry in place, and the marker is stripped from the merged output. This
  is the only way to override an existing entry — the merge is additive
  otherwise.
- **Supersede of a non-existent target** is an error handled under the
  malformed-by-layer policy (D-7, REQ-E1.4): a repo-tracked (team-shared)
  overlay **hard-fails** (nonzero exit), so a broken shared catalog never
  silently mis-merges; an adopter or machine-local overlay warns and skips the
  offending entry (degrade). A malformed overlay (unreadable, or present but
  parsing to zero entries) follows the same split; an absent layer degrades
  silently (REQ-A1.4).
- **Path confinement.** Each present overlay file is canonicalized and
  containment-checked under its layer root before any read (D-8, REQ-E1.5): an
  overlay file that escapes its root — e.g. a repo-tracked catalog symlinked
  outside `.claude/` — is malformed for its layer (the same by-layer split) and
  is never read.
- **Provenance.** `resolve-catalog.sh guard-catalog --explain` names the layer
  that supplied each merged entry (D-9, REQ-B1.6).

An explicit `PLANWRIGHT_GUARD_CATALOG` / `--catalog` override still wins and
bypasses the merge: the catalog the operator names is used verbatim.

## Stake escalation: the builder does not flatten

The catalog is for decisions a tool can own. The builder's harder job is
recognizing the decisions that *look* mechanical but are not, and refusing
to auto-default them. "Add auth", "pick the datastore", "set the cache TTL"
arrive next to "add a linter" and read like the same kind of checkbox, but
the choices underneath are architecture-defining and often business
differentiators.

This is the no-flattening rule of
[engineering-decisions.md](engineering-decisions.md), and the
[decision-domains catalog](decision-domains.md) supplies the triggers. When
the builder is about to cross a catalogued decision domain the spec or
kickoff brief has not decided, it does not stamp a default: it escalates the
decision as design / Needs human judgment and routes it into the deferral
mechanism as a `GATE(when: …)` entry (see
[finding-categorization.md](finding-categorization.md) for the bucket
boundaries and [gate-wiring.md](gate-wiring.md) for the gate mechanics).
Mechanical guards apply; load-bearing decisions escalate. Getting that line
right is what separates a builder from an "add a linter" scaffolder.

This advises and weighs rather than rigidly enforcing
([proportionality.md](proportionality.md)): rigor scales with stake and
reversibility, and any departure from a recommended guard is recorded with
its reasoning where the next reader will find it, never taken silently.

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
project-bespoke guards — the spec validator, the doctrine link-check, the
options-reference drift check — which are project extensions of the catalog,
not universal categories the builder carries to every adopter. Scoping the
dogfood to the core (declared here per the proportionality rule) keeps the
guarantee honest: the builder reproduces what is universal, and the project's
own extensions stay the project's.
