# Substrate candidate screen

The screen every substrate candidate passes before a bake-off prototype is
written (universal-binary REQ-C1.1, REQ-C1.2, design D-6). It records each
admitted candidate with its class, and each excluded candidate with every
constraint that excluded it. A bake-off report may hold only candidates this
page admits.

## The constraints

- **The hard constraint** (REQ-B1.1): installing and running planwright
  needs nothing beyond a POSIX shell, `git` and `gh`. On an
  adopter tier that rules out any interpreter or runtime the adopter would
  have to install, so a candidate there is either shell or a self-contained
  executable.
- **The tier's constraint profile**: the dated profiles under
  [docs/substrate/](substrate/) hold each tier's audience, latency budget
  and auditability weight. The adopter-runtime pair (the library and
  skill-called tiers) shares one profile and one bake-off (D-5).
- **The platform matrix** (D-13): glibc Linux, macOS, and musl Linux with
  dash and busybox. A compiled candidate must be able to build an executable
  for every one of them on the project's CI runners, natively or by
  cross-compiling; the bake-off itself runs its toolchains on demand.
- **The licence screen** (REQ-C1.2): a candidate whose runtime dependencies
  carry a licence incompatible with planwright's outbound MIT licence is
  screened out. "Runtime dependencies" means everything that ships inside
  the delivered artifact: for a compiled candidate, its language runtime and
  standard library as well as any package.

## Admitted

| Candidate | Class | Tiers | Licence of what ships | Notes |
| --- | --- | --- | --- | --- |
| Hardened shell | full | adopter tiers | none ships beyond the scripts (MIT) | The symlink lock of `scripts/lock-lib.sh`, the printf discipline, and a prototype shared-library seam with batched reads (D-6). |
| Go | full | adopter tiers | Go runtime and standard library, BSD-3-Clause: compatible | Static executables on both Linux platforms; on macOS they link only the system library. The linker signs Apple-silicon binaries from a Linux runner. |
| Rust | full | adopter tiers | Rust standard library, MIT or Apache-2.0; on glibc Linux the statically linked glibc, LGPL-2.1-or-later: compatible, with an obligation there | Static on Linux with the C runtime linked in; cross-compiling to macOS needs an Apple SDK that community images do not carry (risk R7). |
| Zig | comparison point | adopter tiers | Zig standard library, MIT: compatible | Pre-1.0, no regular-expression library in its standard library, and its I/O surface keeps moving: the trivial program needed the new `std.process.Init` entry point and `std.Io.File` writer, neither of which the previous API spelled that way. |
| Bun-compiled TypeScript | comparison point | adopter tiers | Bun runtime (MIT) and JavaScriptCore (LGPL-2.1-or-later), both embedded: compatible, with an obligation | Covers the whole matrix from one Linux runner; the executable embeds the runtime, so its size sits against the marketplace archive ceiling. |
| Python | full | dev-check only | not shipped to adopters | Listed per REQ-C1.1, since a pinned toolchain already exists on the dev-check tier; excluded from adopter tiers below. Its dev-check screen is under [Dev-check tier](#dev-check-tier). |
| Node | full | dev-check only | not shipped to adopters | As Python. |

A comparison point is measured on the harness's trivial program only, never
implements a primitive, and cannot be selected by a verdict without first
being promoted to a full candidate through a further bake-off (REQ-C1.1).

**The Bun licence obligation.** JavaScriptCore is LGPL-2.1-or-later and is
statically embedded in every Bun-compiled executable. planwright's own code
stays MIT inside such an executable and the engine stays LGPL, a combination
the LGPL permits, so the screen admits Bun; but anyone distributing such an
executable owes LGPL compliance for the embedded engine (its notice, and the
means for a recipient to relink against a modified engine). The obligation
does not bind a comparison point, which ships nothing. Promoting Bun to a
full candidate would have to settle how a release meets it, before any
verdict could select it.

**The Rust glibc obligation.** On glibc Linux the Rust build links the C
runtime in statically, so the executable embeds glibc, LGPL-2.1-or-later,
and carries the same kind of obligation as Bun's engine. It binds a release
of Rust executables for glibc Linux; building those against musl instead,
whose licence is MIT, would remove it. A verdict selecting Rust would have
to settle which, and Go, which needs no C runtime on Linux, carries none.

## Excluded

Each exclusion names every constraint that excluded the candidate. The
survey exclusions carry the official statements the bundle's Sources cite
under the distribution survey; they are not re-sourced here.

| Candidate | Excluded from | Constraints that excluded it |
| --- | --- | --- |
| Python (any packaging route) | adopter tiers | Hard constraint: an interpreter on the adopter's machine (bootstrap D-34). Matrix: every packaging route either pins the libc of its build host or extracts a runtime per run. |
| Node (interpreted) | adopter tiers | Hard constraint: an interpreter on the adopter's machine (bootstrap D-34). |
| Node single executable applications | adopter tiers | Matrix: Alpine is untested upstream, and cross-compiling forfeits the startup optimisations. |
| Deno compile | adopter tiers | Matrix: no musl target. |
| .NET Native AOT | adopter tiers | Matrix: no cross-OS compilation. |
| GraalVM native image | adopter tiers | Matrix: no cross-OS compilation. |
| Kotlin/Native | adopter tiers | Matrix: no cross-OS compilation. |
| Swift | adopter tiers | Matrix: no cross-OS compilation. |
| Crystal | adopter tiers | Matrix: a link or build step on the target. |
| OCaml | adopter tiers | Matrix: a link or build step on the target. |
| Nim | adopter tiers | Matrix: its cross tooling is alpha and wraps Zig. |
| Haskell | adopter tiers | Matrix: the survey found no share among the surveyed tools, and a bespoke build image for each target. |
| Cosmopolitan | adopter tiers | Hard constraint and delivery: the executable rewrites its own header on disk at first run, which a checksum-pinned, read-only delivery cannot allow. |

No candidate was excluded on licence grounds.

## Bake-off A decisions

The choices the bake-off's task left to its executor, recorded here so the
report can be read without the task open.

- **The parser.** The pain matrix names no copy count directly, so the
  count is read off its items carrying both the duplicated-primitive and
  parser-fragility classes: a family's copy count is the number of scripts
  such an item names. The spec-grammar family holds the highest, two items
  each naming three copies (the scope grammar, and the `Dependencies:`
  line parse); the config readers hold one item naming two. The tie inside
  the family goes to the `Dependencies:` line parse, because its consumers
  include the derivation engine, where a wrong edge changes what
  dispatches.
- **Screened out by fixtures.** A full candidate that fails more than a
  fifth of the production differential fixtures is marked screened-out
  in this record rather than measured. "More than a fifth" is exact: five times the
  failures exceeds the fixture count, with no rounding.
- **Outcome.** Every full candidate passed every fixture on each platform
  with a committed report, so none is screened out there; a platform with
  no committed report is not measured yet. The bake-off's inputs and how to run
  it are in
  [its README](../tests/fixtures/substrate-bakeoff/bakeoff-a/README.md);
  each committed report and its view sit under `docs/substrate/bakeoff-a/`.

## Bake-off B decisions

The hook tier's bake-off, under the same rules.

- **Candidates.** The full candidates this page admits for adopter tiers:
  hardened shell, Go and Rust. The comparison points are not re-measured,
  since the trivial program does not depend on the tier.
- **The primitives.** The command guard's tokenizer, and the ready guard's
  predicate from the GitHub answers to the decision, its network calls
  replaced by recorded answers. The ready guard's own Bash-surface parse is
  left out: it is a second, smaller tokenizer of the same kind.
- **The call site.** The tokenizer on a typical worker command, because the
  command guard tokenizes every Bash call while the predicate runs only on a
  flip.
- **The vector enumeration.** One row per false-allow vector an observation
  in the bundle's parser-fragility Sources names, in
  [vectors.tsv](../tests/fixtures/substrate-bakeoff/bakeoff-b/vectors.tsv):
  vector id, observation UID, tokenizer case, and the vector. Observations
  in that list that name no command-guard false-allow (a fail-open screen
  elsewhere, an unchecked exit status, a guard that over-defers, a lint
  check's quoting blind spot) have no row.
- **Outcome.** Every full candidate passed every fixture on each platform
  with a committed report, so none is screened out there. The inputs and how
  to run it are in
  [its README](../tests/fixtures/substrate-bakeoff/bakeoff-b/README.md); each
  committed report and its view sit under `docs/substrate/bakeoff-b/`.

## Dev-check tier

The dev-check screen (REQ-C1.2, REQ-C1.3, D-5): every candidate above,
Python and Node included, screened against the dev-check profile in
[the constraint profiles](substrate/constraint-profiles-2026-10-18.md#dev-check),
then the breadth rule applied to the result.

### What the dev-check profile changes

The hard constraint binds adopter tiers only, and a dev-check script ships
in neither delivery mode: it runs from the repository checkout, on a
maintainer's machine or a CI runner. Three of the adopter-tier screen's
reasons therefore fall away here: an interpreter on the adopter's machine,
an embedded runtime's size against the marketplace archive, and a licence
obligation on a shipped executable. What remains is the profile itself: a
toolchain permitted, no per-call latency budget, the check aggregate's
wall-clock as the cost that matters, a guard that fails closed, and reach
across the maintainer hosts and the CI matrix's platforms.

Python and Node are already present wherever the tier runs, though neither
is pinned in its own right: `mise.toml` pins `markdownlint-cli2` through
mise's npm backend and `yamllint` through its pipx backend, so every host
that runs the check aggregate carries both runtimes, and the CI workflow
installs Node and pipx on the Alpine job for the same reason. Go and Rust
would each add a pinned toolchain to `mise.toml`, a cost the screen notes
but which the profile permits.

### Screen outcome

| Candidate | Class | Dev-check screen | Reason |
| --- | --- | --- | --- |
| Hardened shell | full | passes | The tier's current substrate; nothing in the profile excludes it. |
| Go | full | passes | A toolchain is permitted; it builds natively on every maintainer host and CI platform, so the Rust cross-compilation risk has no analogue here. |
| Rust | full | passes | As Go: built natively where it runs, so the Apple SDK risk (R7) does not bind, and nothing ships, so the glibc obligation does not bind. |
| Python | full | passes | The interpreter is already present for `yamllint`; the hard constraint binds adopter tiers only (REQ-B1.1), and D-6 opens interpreted runtimes to dev-only tiers. |
| Node | full | passes | The runtime is already present for `markdownlint-cli2`; as Python. |
| Zig | comparison point | passes, as a comparison point only | Nothing in the profile excludes it, but a comparison point cannot be selected without a further bake-off promoting it (REQ-C1.1). |
| Bun-compiled TypeScript | comparison point | passes, as a comparison point only | Its executable size and embedded-engine obligation bind only a shipped artifact; as Zig, it is not selectable. |
| Deno compile | not classed | screened out | Its exclusion, no musl target, still binds: the dev-check profile reaches the CI matrix's platforms, Alpine included. |
| Every other candidate in the Excluded table | not classed | not screened out, not admitted | Each was excluded from adopter tiers on hard-constraint, matrix, or delivery grounds that a tool built where it runs and shipped nowhere does not face, or (Haskell) for want of any share among the surveyed tools, which is no dev-check constraint either; Python's packaging routes and Node's single executables are moot beside the Python and Node rows. None enters this tier's set unclassed (REQ-C1.1), and classing one would be the dev-check bake-off's own screen: admitting any only adds survivors, so the outcome below holds either way. |

No admitted candidate is screened out of the dev-check tier, so five full candidates
survive it and the tier cannot be settled by the screen record, which
REQ-C1.3 allows only when exactly one survives.

### Breadth-rule decision

The hard axes of REQ-C1.3, dev-check against each other tier as the
profiles record them:

| Axis | Dev-check | Library and skill-called | Hook |
| --- | --- | --- | --- |
| Audience | dev-only | adopter runtime | adopter runtime |
| Per-call latency budget | none | none of its own (a library inherits its caller's) | no regression against shell |
| Auditability weight | low | medium | high |

- **Decided tiers.** The library and skill-called pair's bake-off has a
  committed report for glibc Linux only; its macOS and musl reports are
  outstanding (the bake-off's entry under `## Awaiting input`), and this
  page counts a platform with no committed report as not measured yet. The
  hook tier's bake-off, which comes before this screen in task order, is
  in the same state: its glibc Linux report is committed and its macOS and
  musl reports are outstanding. Neither tier is
  therefore fully decided, and the comparison below does not depend on
  it: against the pair dev-check differs on two hard axes, against hook
  on all three, and with no tier decided at all the rule's "differs from
  every tier already decided" holds trivially, leaving no nearest tier to
  inherit from.
- **Profile comparison.** Dev-check is closest to the pair on the latency
  axis, where neither carries a per-call budget of its own, and differs
  on audience and auditability weight. It therefore differs on a hard axis
  from every tier that is or will be decided before it, and REQ-C1.3's
  inheritance branch, which needs no such difference, does not apply.
- **Defect classes.** The pair's bake-off exercised the lock
  primitive and the `Dependencies:` line parse: lock-concurrency,
  parser-fragility and duplicated-primitive. The dev-check row of
  [the pain matrix](substrate/pain-matrix-2026-10-18.md) is led instead by
  instruction-headroom and lint-gap, classes no bake-off has exercised, a
  second and independent ground for a bake-off of its own.
- **Outcome.** Neither inheritance nor screen settlement is available, so
  the rule's remaining branch holds: a case for a dev-check bake-off.

### Recommendation to the verdict amendment

Mint no dev-check verdict in the verdict amendment until the operator has
answered the case below, which is escalated under `## Awaiting input` in
the bundle's `tasks.md`.

**The case for a dev-check bake-off.** Both grounds above hold, so the
breadth rule gives the tier a bake-off of its own. The representative
primitive is the instruction guard's manifest parse and charged closure in
`scripts/check-instructions.sh`: reading a skill's doctrine manifest,
resolving each named document, and charging the start load and the
reachable closure against their budgets. That script is the dev-check
script the matrix names most often, and its items there fall mostly on the
tier's leading class, instruction-headroom, and on perf-spawn-cost (the
guard's share of the check aggregate's wall-clock). The manifest grammar
also makes it a parser, though the matrix attributes the tier's
parser-fragility items to other scripts. The bake-off would measure the
five surviving full candidates on it under the existing harness; Zig and Bun stay comparison
points. The harness already accepts `dev-check` as a tier, but it requires
a `delivery.marketplace` and a `delivery.writer` script from every
candidate, and REQ-C1.4 measures delivery through both modes, while a
dev-check script ships through neither; the bake-off's task would have to
settle what that measurement means for this tier before it runs.

**What the operator decides.** Whether the dev-check tier takes that
bake-off, a new task added to the bundle through the amendment ritual, or
is settled another way, such as inheriting the pair's verdict, once it is
decided, despite the audience and auditability differences. The breadth rule as
written does not provide that second route, so it too would need a
meaning-class amendment.
