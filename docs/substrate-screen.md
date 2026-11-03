# Substrate candidate screen

The screen every substrate candidate passes before a bake-off prototype is
written (universal-binary REQ-C1.1, REQ-C1.2, design D-6). It records each
admitted candidate with its class, and each excluded candidate with every
constraint that excluded it. A bake-off report may hold only candidates this
page admits.

## The constraints

- **The hard constraint** (REQ-B1.1): installing and running planwright
  needs nothing beyond a POSIX shell, `git` and the bootstrap tools. On an
  adopter tier that rules out any interpreter or runtime the adopter would
  have to install, so a candidate there is either shell or a self-contained
  executable.
- **The tier's constraint profile**: the dated profiles under
  [docs/substrate/](substrate/) hold each tier's audience, latency budget
  and auditability weight. The adopter-runtime pair (the library and
  skill-called tiers) shares one profile and one bake-off (D-5).
- **The platform matrix** (D-13): glibc Linux, macOS, and musl Linux with
  dash and busybox. A compiled candidate must build an executable for every
  one of them from the project's CI.
- **The licence screen** (REQ-C1.2): a candidate whose runtime dependencies
  carry a licence incompatible with planwright's outbound MIT licence is
  screened out. "Runtime dependencies" means everything that ships inside
  the delivered artifact: for a compiled candidate, its language runtime and
  standard library as well as any package.

## Admitted

| Candidate | Class | Tiers | Licence of what ships | Notes |
| --- | --- | --- | --- | --- |
| Hardened shell | full | adopter tiers | none ships beyond the scripts (MIT) | The Task 1 lock, the Task 1.1 printf discipline, and a prototype shared-library seam with batched reads (D-6). |
| Go | full | adopter tiers | Go runtime and standard library, BSD-3-Clause: compatible | Static executables for every matrix platform; the linker signs Apple-silicon binaries from a Linux runner. |
| Rust | full | adopter tiers | Rust standard library, MIT or Apache-2.0: compatible | Static on Linux with the C runtime linked in; cross-compiling to macOS needs an Apple SDK that community images do not carry (risk R7). |
| Zig | comparison point | adopter tiers | Zig standard library, MIT: compatible | Pre-1.0, no regular-expression library in its standard library, and its I/O surface keeps moving: the trivial program needed the new `std.process.Init` entry point and `std.Io.File` writer, neither of which the previous API spelled that way. |
| Bun-compiled TypeScript | comparison point | adopter tiers | Bun runtime (MIT) and JavaScriptCore (LGPL-2.1-or-later), both embedded: compatible, with an obligation | Covers the whole matrix from one Linux runner; the executable embeds the runtime, so its size sits against the marketplace archive ceiling. |
| Python | full | dev-check only | not shipped to adopters | A pinned toolchain already exists on the dev-check tier (REQ-C1.1); excluded from adopter tiers below. Its dev-check screen belongs to Task 8. |
| Node | full | dev-check only | not shipped to adopters | As Python. |

A comparison point is measured on the harness's trivial program only, never
implements a primitive, and cannot be selected by a verdict without first
being promoted to a full candidate through a further bake-off (REQ-C1.1).

**The Bun licence obligation.** JavaScriptCore is LGPL-2.1-or-later and is
statically embedded in every Bun-compiled executable. Distributing it under
MIT is permitted, so the screen admits Bun; but anyone distributing such an
executable owes LGPL compliance for the embedded engine (its notice, and the
means for a recipient to relink against a modified engine). The obligation
does not bind a comparison point, which ships nothing. Promoting Bun to a
full candidate would have to settle how a release meets it, before any
verdict could select it.

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

The choices Task 6 left to its executor, recorded here so the report can be
read without the task open.

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
  rather than measured. "More than a fifth" is exact: five times the
  failures exceeds the fixture count, with no rounding.
- **Outcome.** Every full candidate passed every fixture on the platforms
  measured, so none is screened out. The bake-off's inputs and how to run
  it are in
  [its README](../tests/fixtures/substrate-bakeoff/bakeoff-a/README.md);
  each committed report and its view sit under `docs/substrate/bakeoff-a/`.
