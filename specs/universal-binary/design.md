# Universal Binary — Design

**Status:** Ready
**Last reviewed:** 2026-09-09
**Format-version:** 2
**Execution:** derived — see the status render

Origin tags: `N` = new decision minted in this bundle's drafting session
(2026-09-07 and 2026-09-08).

## Decision log

### D-1: Altitude — an evidence method at capability altitude, not a binary  (N)

**Decision:** The deliverable is a substrate-selection method: partition
the script layer into tiers, attribute the recorded evidence, derive
constraint profiles, screen candidates against the hard constraint, bake
off survivors on a representative primitive per tier, mint one verdict per
tier from measurements and a cost-benefit line, and migrate only behind
gates. The method sits at capability altitude; the per-tier verdicts are
planwright's own values; a compiled binary is one candidate mechanism the
method measures. This decision supersedes bootstrap D-34, whose choice of
portable shell was made for a layer a fraction of today's size, and keeps
its core value as the one hard constraint: no adopter toolchain.

**Alternatives considered:**
- Commit to a compiled binary now and plan the port of the whole layer.
  Rejected because: no recorded observation asks for a language change,
  no official-marketplace plugin ships a compiled binary, and the one
  compiled reimplementation of a primitive on the drafting host (a
  coreutils `mkdir`) is the primitive that broke — a verdict by fiat would
  carry none of the evidence the bundle exists to produce.
- Stay in shell and fix the classes, closing the language question.
  Rejected because: it answers the question by the opposite fiat; the
  hardened-shell candidate is measured in the bake-off instead, at equal
  weight, so a shell verdict, if it comes, comes with numbers.
- A research spike with no migration tasks. Rejected because: the operator
  chose decide-then-migrate; the migration tasks exist from birth, parked
  behind the verdicts, so the plan is written once.

**Chosen because:** the altitude trigger fired at seed gathering (the
invocation claimed the layer had outgrown its substrate and asked for other
solutions), and the doctrine requires the altitude resolved before any
mechanism is designed; the evidence is class-shaped, which argues for a
per-tier method rather than a wholesale answer.

### D-2: New bundle, not an extension  (N)

**Decision:** This is a new bundle. Fold-detection scanned every
non-terminal bundle; the nearest neighbours are format-grammar (the shared
parse library) and guard-coverage (lint guards), both in-shell
consolidation inside their own domains.

**Alternatives considered:**
- Extend format-grammar. Rejected because: the substrate decision forces
  choices (delivery, toolchains, a CI matrix, a cost model) orthogonal to a
  parse-grammar bundle's domain, and is independently ownable.
- Extend guard-coverage. Rejected because: the same reasoning; a guard
  bundle owns which invariants are checked, not what the checkers are
  written in.

**Chosen because:** the spin-new triggers fire on orthogonal decision
space and independent ownership.

### D-3: The tier partition is derived from the call graph, never hand-listed  (N)

**Decision:** A shipped script assigns each script one tier — hook,
skill-called, library, dev-check, tests-only — by who invokes it, plus a
coupling profile of the external processes it drives, and flags scripts
with no live caller. It runs on demand as a repository task.

**Alternatives considered:**
- A hand-maintained tier list in the bundle. Rejected because: it goes
  stale silently the day a script is added, inside anchored content a
  reader is entitled to trust (the decided-rules-over-enumerations rule).
- Tiering by directory layout (moving scripts into per-tier folders).
  Rejected because: it changes every literal path skills and allowlists
  name, which REQ-E1.2 freezes.

**Chosen because:** the partition already runs as a one-off in the
drafting session; shipping it makes the first step of the method
reproducible and keeps the enumeration out of the bundle.
*(Amended at kickoff 2026-09-09: liveness is transitive from an entry
point, a Markdown mention outside a skill body is not a caller, a script
matching two tier definitions takes the first in the listed order, the
coupling profile carries a shell-mutation flag, and the tests-only tier is
dissolved by the flag; REQ-A1.1 and REQ-A1.3 carry the wording.)*

### D-4: The pain matrix and cost baseline are dated snapshots, cited not copied  (N)

**Decision:** Observation attribution and the maintenance-cost baseline
are produced by scripts and committed as dated snapshots under `docs/`,
regenerable; the bundle and the verdicts cite them.

**Alternatives considered:**
- Inline the matrix in the bundle's design. Rejected because: anchored
  prose would freeze figures that change with every recorded observation.
- Do not commit the snapshot at all; regenerate at every read. Rejected
  because: a verdict's rationale must point at the exact input it was
  minted from, and a regenerated matrix drifts under the verdict.

**Chosen because:** cite-don't-copy is the format's own convention for
enumerations the bundle cannot avoid.
*(Amended at kickoff 2026-09-09: the snapshot set widens to each tier's
bake-off report, the screen record, and the constraint profiles; the
Sources and Changelog sections and a verdict's measurement and
cost-benefit lines are exempt from the number-copy guard; the snapshots
are work product committed under `docs/`, not runtime state, in the
storage-classes doctrine's terms; a report schema only ever adds fields.)*

### D-5: Bake-off breadth follows an inheritance rule  (N)

**Decision:** A tier gets its own bake-off only when its constraint profile
differs on a hard axis — audience, per-call latency budget, auditability
weight — from every tier already decided, or when its pain-matrix row
carries a defect class no earlier bake-off exercised. Otherwise it inherits
the nearest decided verdict, with the profile comparison recorded. Applied
to the drafting partition: library and skill-called share a profile
(adopter runtime, no per-call budget), so one bake-off pairing the lock
with a parser covers both; hooks differ on latency and auditability and get
their own; dev-check differs on audience and, with a toolchain permitted
there, may be settled by the screen alone.

**Alternatives considered:**
- One bake-off per tier unconditionally. Rejected because: it spends
  prototype effort on tiers whose profile is identical to one already
  measured.
- One bake-off on the deepest-pain primitive, extrapolated everywhere.
  Rejected because: the hook tier's latency and auditability axes cannot be
  inferred from a library-tier measurement.

**Chosen because:** the operator asked for a way to tell the better
direction rather than a picked breadth, and an explicit inheritance rule is
that way: it is checkable against the profiles, and the record shows why a
tier was or was not measured.
*(Amended at kickoff 2026-09-09: the rule applies to the tiers other than
tests-only; a tier whose screen leaves one surviving candidate may be
settled by the screen record; "decided" means bake-off report or screen
record complete, in task order, and "nearest" means most hard axes
matched, ties to the earlier-decided tier; REQ-C1.3 carries the wording.)*

### D-6: Candidate set — hardened shell, Go, Rust; research-admitted additions through the screen  (N)

**Decision:** The adopter-tier candidate set is shell in its hardened and
restructured form (the Task 1 lock, the Task 1.1 printf discipline, a
shared library, and batched reads in place of per-key spawns, so the
substrate effect is measured apart from the architecture effect), Go, and
Rust. The distribution survey (Sources) admitted two more through the
hard-constraint screen: Zig, as a comparison point only, because it clears
the cross-compilation and static-linking gates with the smallest binaries
and fastest measured cold start in the survey but is pre-1.0, has no
regular-expression library in its standard library, and rewrote its I/O
surface in its latest release; and Bun-compiled TypeScript, qualified,
because it is the only tool covering the whole platform matrix from one
Linux runner and is owned by the plugin host's vendor, but the one
published measurement shows a compiled script starting slower than the
same script under the runtime, and its embedded runtime is large against
the marketplace's archive ceiling. The survey excluded on the record, each
with an official statement: .NET Native AOT, GraalVM, Kotlin/Native, and
Swift (no cross-OS compilation); Crystal and OCaml (a link or build step on
the target); Nim (alpha cross tooling wrapping Zig); Haskell (no share, and
seven bespoke build images); Cosmopolitan (rewrites its own header on disk
on first run); Deno (no musl target); Node single executables (Alpine
untested, cross-compiling forfeits startup optimisations); every Python
packaging route (build host pins the libc, or per-run extraction). Dev-only
tiers may additionally consider interpreted runtimes because a pinned
toolchain already exists there. A candidate screened out is recorded with
the constraint that excluded it; the survey's exclusions are the first
entries of that record.

**Alternatives considered:**
- Include Bun-compiled TypeScript unconditionally as the plugin ecosystem's
  idiom. Rejected because: the operator bounded the compiled set to Go and
  Rust pending the survey; the executable embeds its runtime and its own
  documentation calls the result too big, so it enters only if the survey
  and the screen admit it.
- One compiled language picked by research alone. Rejected because: it
  would make the language a judgment recorded without a measurement, which
  is the shape the method replaces.
- Python or Node as interpreted adopter-tier candidates. Rejected because:
  the hard constraint excludes an interpreter on the adopter machine, the
  reason bootstrap D-34 already gave.

**Chosen because:** Go and Rust both produce small static binaries for
every platform in the matrix and split the mature projects (asdf and gh on
one side, mise and the reimplemented coreutils on the other), so neither
can be excluded by reading; they differ on one axis the bake-off must
record: Go's linker ad-hoc signs Apple-silicon binaries from a Linux
runner, while Rust needs a signing step and, for cross-compilation to
macOS, an Apple SDK whose licence keeps it off community build images.
The survey found the common third options and excluded most of them on
official statements, so the screen record starts full rather than empty.
*(Amended at kickoff 2026-09-09: Zig and Bun-compiled TypeScript are
comparison points per REQ-C1.1 — measured on a trivial program, never
implementing a primitive, never selectable without a further bake-off.)*

### D-7: The measurement contract  (N)

**Decision:** Every bake-off measures, per candidate: correctness under the
existing tests including red ones; call-site latency over repeated runs;
the number of external processes spawned per invocation; source size;
transitive dependency count; pass or fail per matrix platform; delivery
through both modes; whether the invocation stays a literal path a static
allowlist can match; implementation time; and the review findings the
convergence pass raised. A shipped harness produces every figure from one
command, and a verdict cites nothing the harness did not produce. The
spawn count is first-class because the survey's precedents converge on it
as the real cost of a shell hot path: the interpreter's own start is in the
same sub-millisecond band as a static binary, and each forked external
costs about as much as the whole binary would.

**Alternatives considered:**
- Latency and correctness only. Rejected because: dependency weight,
  allowlist shape, delivery, and review load are the axes the observations
  and the hard constraint actually turn on.
- Numbers gathered by hand and pasted into the verdict. Rejected because:
  a pasted number cannot be re-run, and the cost-benefit line depends on
  re-running it against the baseline.

**Chosen because:** the operator asked that the answer be methodological;
a fixed contract with a reproducing harness is what makes two verdicts
comparable and one verdict re-checkable.
*(Amended at kickoff 2026-09-09: the contract applies per full candidate;
comparison points are measured on the trivial-program subset only; the
contract gains a dependency listing with licence and maintenance status,
an offline-replayability field, and a normalised review-findings count
over a fixed number of convergence runs; REQ-C1.4 carries the wording.)*

### D-8: A verdict is minted by amendment with a scoped re-sign-off  (N)

**Decision:** Each tier verdict is a new design decision added to this
bundle by the meaning-class amendment ritual, with the human's scoped
re-sign-off; no skill mints a verdict on its own authority, and the
migration tasks depend on the amendment.

**Alternatives considered:**
- Pre-mint placeholder decisions per tier to be filled in. Rejected
  because: a stable ID with no content is a record that can be
  pencil-whipped, and the format forbids editing a decision's body.
- Let the executing worker record the verdict in the PR body only.
  Rejected because: the verdict is the judgment call the autopilot reflex
  names as an irreducible human gate; automation carries the measurements
  to its edge and stops.

**Chosen because:** the verdict is where opinion could re-enter; routing
it through sign-off keeps the method honest.

### D-9: Compiled artifacts ship as attested release assets fetched once into the plugin data directory  (N)

**Decision:** If a verdict selects a compiled artifact, CI cross-compiles
it per matrix platform from the tagged source, ad-hoc signs the macOS
binaries (Apple silicon refuses an unsigned native executable before it
reaches `main`), attaches the binaries to an immutable release with a
provenance attestation generated by the current attest action, and pins
their checksums in the repository tree. A shim under `scripts/` fetches
the matching artifact on first use into the plugin data directory, hashes
it through a portable chain (`sha256sum`, then `shasum -a 256`, then
`openssl dgst`) and fails closed when no hasher exists rather than skipping
verification, verifies the checksum before setting the execute bit
(the marketplace copy is reported to strip execute bits, so the shim never
assumes one), checks the artifact's version against the installed manifest
at every invocation, and fails closed with a message naming the shell
fallback on a missing, mismatched, or unverifiable artifact. The pinned
checksum is the load-bearing verification; the attestation is a second
layer for adopters who choose to verify it, because the CLI's attestation
verification may require authentication. The shim honours a mirror URL and
an offline switch through the plugin's user-config seam, and a session-start
hook may prefetch. The plugin never carries a top-level `bin/`. The writer
delivers the shim and the fetch path, or the verdict records writer mode as
unsupported for that tier.

**Alternatives considered:**
- Commit prebuilt binaries under `scripts/` so the marketplace copy and the
  writer deliver them offline. Rejected because: repository history grows
  by every binary of every release and the blobs are unreviewable in a PR;
  the operator chose the fetch path with that cost in view.
- Commit for the plugin and fetch for the writer. Rejected because: two
  delivery mechanisms to keep consistent, with every drawback of each.
- Build from source at first use. Rejected because: it requires a toolchain
  on the adopter machine, the hard constraint.
- Decide after a verdict. Rejected because: a compiled verdict would then
  stall on a design question that has one mature-project answer.

**Chosen because:** release assets with checksums and provenance are the
pattern mise, rustup, and gh converge on, and the committed-stub-plus-pinned
-checksum shape is the one the Gradle wrapper has proven for a decade; the
plugin data directory is the seam the platform documents for installed
dependencies and caches, and its stable path keeps the macOS first-execution
assessment from re-firing on every plugin update, which a binary under the
versioned plugin root would suffer; the fail-closed fallback keeps an
offline first run from becoming a silent degradation, where the survey found
most flagship installers verify nothing at all.
*(Amended at kickoff 2026-09-09: the fetch keys the cached artifact by
plugin version, operating system, and architecture, downloads to a
temporary path and renames atomically only after verification, removes
an unverifiable file and artifacts of superseded versions, and serializes
concurrent first uses through the D-11 lock; a fetch or verification
failure exits with one code reserved across every shim, with the message
on stderr, and the entry point never falls back to shell by itself; the
version check is exact and CI builds assets on every release, a version
with no asset failing closed; the mirror address, offline switch, and
shell selector are named options with safe defaults in the configuration
defaults file and options-reference rows, the offline switch suppressing
the fetch and selecting shell; the `SessionStart` prefetch is a Task 10
deliverable with a bounded timeout that never blocks session start; the
data directory is `CLAUDE_PLUGIN_DATA` in plugin mode and the writer's
per-plugin state home in writer mode, per the storage-classes doctrine,
which records that home as interim; the asset build hangs off the
existing release-please release rather than a parallel tagging path; each
release carries a NOTICE file generated from the dependency list; and the
shipped asset and docs page use a release name checked for trademark
collision.)*

### D-10: Migration is a strangler behind frozen entry points  (N)

**Decision:** Every entry point a skill, a hook registration, or a tracked
git hook names keeps its path, arguments, stdout contract, and exit codes.
A migrated entry point becomes a shim that delegates to the new
implementation; differential tests over recorded fixtures prove parity
before the shell implementation is removed; the shell implementation stays
selectable until parity is recorded, and the differential suite keeps
exercising it in CI for as long as it exists, because an escape hatch that
CI does not run rots into decoration (git's builtin-rebase switch was a
fiction within one release, and its scripted stash fallback failed a test
unnoticed for four); removal is a human-directed step.

**Alternatives considered:**
- A single dispatcher binary skills invoke directly. Rejected because: it
  edits skill prose, which the operator placed out of scope, and changes
  the literal paths adopter allowlists carry.
- Cut over a tier at once with no shell fallback. Rejected because: the
  deploy-and-migration domain treats a rollout that cannot be rolled back
  atomically as a hard-disqualifier zone; the irreversible step must be
  human-directed.

**Chosen because:** the shim keeps the invocation shape allowlists match,
keeps the writer's copy contract, and makes each tier's cutover a revert
away from undone.
*(Amended at kickoff 2026-09-09: the selector is a key in the
operator-owned machine-local configuration layer, out of reach of any
agent-writable path, and stays honoured for as long as the shell
implementation exists; parity means at least the entry-point fixture plus
one fixture per documented exit code in a committed parity file; no
removal is proposed until the operator names the tier, the question is
re-put at the first release after parity, and the differential suite's
cost is a line in the cost-benefit record until then; REQ-E1.3 carries
the wording.)*

### D-11: The lock baseline uses an atomic-create primitive with an owner token  (N)

**Decision:** Before any bake-off, every advisory lock in the script layer
adopts one shared primitive: acquisition by an atomic create (a symbolic
link whose target carries the owner token, or a noclobber open), release
that verifies ownership, a stale break that cannot double-grant, signal-safe
release installed before the critical section, and reentrancy by token.
`mkdir` is retired as the acquisition primitive. The registry race test
turns green.

**Alternatives considered:**
- `flock`. Rejected because: it is absent on macOS, inside the matrix.
- Keep `mkdir` and add an owner token. Rejected because: the reimplemented
  coreutils `mkdir` on the drafting host returns success to several
  concurrent creators, so the primitive itself is unsound there, and the
  observations measured interleavings with the shape even where it is
  atomic.
- Leave the lock to the bake-off's shell prototype. Rejected because: a
  verdict measured against a known-broken baseline cannot be honest, and
  the fleet keeps losing registrations meanwhile.

**Chosen because:** the observations measured zero interleavings under
the atomic-create shape, and the concurrency domain asks for the stack's
idiomatic primitive rather than a hand-rolled one; this is the closest a
portable shell floor offers.
*(Amended at kickoff 2026-09-09: a lock is stale when the owner token's
process is absent, never by age; a nested acquire under the same token
succeeds and the lock is held until the outermost release.)*

### D-12: The echo baseline is a printf discipline with a lint guard  (N)

**Decision:** Before any bake-off, every site that echoes untrusted or
sanitized text moves to `printf '%s'`, and a lint guard under the check
aggregate rejects a new `echo` of sanitized or untrusted text, so the
class cannot recur in whatever shell survives.

**Alternatives considered:**
- Widen the sanitizer to strip backslashes. Rejected because: the
  observations found the sanitizer is not the defect; the platform `sh`'s
  `echo` is, and the sanitizer already mangles UTF-8 at its edges.
- Hold the sweep for a shell verdict. Rejected because: the live
  escape-injection class stays open meanwhile, and the shell candidate
  would be measured with a defect the fix for which is mechanical.

**Chosen because:** the recurrence is proven — the class was consolidated
once and re-found — so only a guard closes it; the operator chose the
baseline placement on the same reasoning as D-11.

### D-13: The platform matrix is glibc, macOS, and musl with dash and busybox  (N)

**Decision:** CI gains a macOS job (system `bash` 3.2, BSD awk and sed)
and an Alpine job (musl, `dash` as `/bin/sh`, busybox tools, run as a
stock Alpine container on the Linux runner, since the host offers no
Alpine runner) beside the existing Ubuntu job. The existing shell suite
is repaired on both new platforms first, as its own task, after the lock
and echo baselines that turn its known reds green, and a platform joins
the pull-request workflow only once the suite passes there; from that day
every job on every platform is blocking, with no informational mode and
no promotion switch. The Alpine job runs the shell suite, the harness,
and the install smoke check; steps needing a tool with no musl build stay
on Ubuntu and are named in the workflow, so nothing on Alpine can skip
silently. When a platform goes red for a runner or image reason rather
than a planwright defect, the revert is a PR removing that job, merged on
the remaining green platforms, recorded as an observation, and the job
re-joins under the repair rule. The macOS job exercises a fetched
artifact's first execution, quarantine attribute set, so the platform's
assessment of a downloaded executable is a test, not a manual step.
Windows through Git Bash is not required and is recorded as a Deferred
opportunity.

**Alternatives considered:**
- Keep Ubuntu only and trust the claimed floor. Rejected because: the
  observations record awk exit-code divergence, a missing `setsid`, a
  first-execution stall, and dash echo behaviour that Ubuntu never
  exercises; two entries also retracted macOS attributions that a matrix
  would have settled in minutes.
- Run the existing suite informationally on the new platforms until it is
  green, then promote it to blocking. Rejected because: a promotion switch
  needs an owner and can undo itself or be forgotten, and an advisory job
  is decoration nobody reads; the operator chose to pay the repair cost up
  front, at kickoff, so that no switch exists. The cost accepted is that
  the amount of repair is unknown until the first run on each platform.
- Add Windows. Rejected because: no planwright document promises it, and
  the operator did not select it; the compiled path may make it cheap
  later, which the Deferred bullet records.

**Chosen because:** these are the platforms the plugin host documents,
minus the one nobody has asked for, and they cover every portability
finding the accumulator holds; repairing first keeps every job blocking
and honest from its first day.
*(Amended at kickoff 2026-09-09: repair-first replaces
informational-until-green.)*

### D-14: The hook latency budget is no regression against shell on the same runner  (N)

**Decision:** The hook tier's budget is stated relatively: a candidate may
not be slower than the shell implementation measured in the same harness
run on the same runner. No absolute figure is written.

**Alternatives considered:**
- An absolute budget in milliseconds. Rejected because: a number owned by
  the bundle rots as runners change, and the per-call cost that matters is
  relative to what adopters pay today.

**Chosen because:** the harness already measures both in one run, so the
relative form costs nothing and stays true; and the survey's only clean
cross-language spawn table puts a non-interactive shell start and a static
compiled binary in the same sub-millisecond band, so the budget a hook can
win or lose is set by what it forks, not by what it is written in. The hook
registration's native condition field is the zero-cost fast path in front
of any hook process, whichever substrate wins.

### D-15: The cost-benefit model  (N)

**Decision:** A shipped script computes the maintenance-cost baseline from
git history and the accumulator: fix-typed commit rate on the script
layer, observation inflow by defect class, the check aggregate's
wall-clock, and handoffs caused by load-sensitive test failures. Each
verdict carries a cost-benefit line: migration effort extrapolated from the
porting rate the bake-off logged, ongoing cost delta against the baseline,
the defect classes the substrate structurally eliminates versus merely
relocates, how much of any measured gain the restructured-shell candidate
also captured (so the verdict attributes the gain to substrate or to
architecture, the split the survey's precedents turn on: a naive compiled
port of pre-commit bought a sixth of its eventual speed-up, the rest came
from architecture), and the same figures for the stay-in-shell option at
equal weight; it states a break-even condition or that none exists.

**Alternatives considered:**
- A one-off narrative cost-benefit essay. Rejected because: it is opinion
  with numbers attached, cannot be re-run, and the operator asked for the
  analysis to be part of the method.
- Effort estimated by judgment per tier. Rejected because: the bake-off
  produces a measured porting rate for free, and the review findings per
  candidate test the hypothesis that a typed substrate lowers review load
  on code the fleet's workers write.
- Cost the rewrite alone and treat stay-in-shell as free. Rejected
  because: the survey's precedents show the costs a rewrite adds (a
  version-manager's seven patch releases in eight weeks and a permanently
  lost capability; a package manager that measured its compiled port slower
  on the operation users wait for and archived it) and the costs shell keeps
  paying (an enforced portability rulebook, an injection class no lint
  closes), so both columns are real and only measurement orders them.

**Chosen because:** the operator asked for the cost-benefit of doing this
at all; costing the do-nothing option at equal weight is the balance rule
the interaction doctrine already imposes, applied to a design record.

### D-16: The auditability criteria go to doctrine; the method stays in the spec  (N)

**Decision:** The security-posture line that scripts are plain portable
shell small enough to read, gated by the self-hosting quality guards, is
restated as substrate-neutral criteria — source in the repository,
reproducible build, pinned checksum, invocation by a resolved literal
absolute path, and lint plus secret scan for the substrate under the
check aggregate — before any non-shell verdict is minted. The
substrate-selection method itself is recorded here, not in a doctrine
document; when a second bundle applies the method end to end, the
operator decides at that bundle's kickoff whether it moves to doctrine.

**Alternatives considered:**
- Leave the doctrine line as is and amend only if a compiled verdict
  lands. Rejected because: the line would then be false at the moment the
  verdict is signed, and a doctrine amendment after the fact is exactly
  the drift the re-sign-off's normative-token check exists to catch.
- Ship the method as a doctrine document now. Rejected because: the
  customization boundary's default tilt keeps an unproven generalization
  out of core; one instance is not evidence.

**Chosen because:** the criteria are a rule and rules live in doctrine;
the method is a procedure this bundle owns.

### D-17: Prototypes are promotable  (N)

**Decision:** Bake-off prototypes run under the production differential
fixtures from the start, so a winning prototype becomes the migration's
seed rather than a throwaway.

**Alternatives considered:**
- Throwaway prototypes measured on ad-hoc inputs. Rejected because: the
  parity fixtures would be written twice, and the measured implementation
  time would not predict migration effort.

**Chosen because:** the cost model of D-15 depends on the porting rate
being the real one.

### D-18: Verdict-conditional tasks are parked with free-text gates  (N)

**Decision:** The delivery and migration tasks exist from birth in the
task ledger and are parked under Deferred with free-text gates naming the
verdict that unparks them, because the gate grammar has no atom for "a
verdict selects a compiled artifact" and a human judges the verdict anyway.

**Alternatives considered:**
- Omit the tasks and extend the bundle after the verdicts. Rejected
  because: the operator chose decide-then-migrate; writing the plan once
  keeps the dependency edges load-bearing from the start.
- Encode the condition as a task-completion gate on the verdict task.
  Rejected because: the verdict task completing does not say which way it
  went; a structured gate would unpark a migration the verdict refused.

**Chosen because:** free-text gates are the grammar's own escape for a
condition it cannot say, surfaced to a human rather than evaluated.

## Cross-cutting concerns

**Decision-domains walk.** API surface: the script entry points are public
contract (skills and adopter allowlists name them literally), frozen by
D-10. Concurrency: D-11 replaces a hand-rolled primitive with the closest
idiomatic one the floor allows and records the crash-mid-critical-section
story. Deploy and migration: every tier cutover escalates its rollout, and
removal is human-directed (D-10). Dependency adoption: the CI toolchains
are dev-only and recorded on the checklist; the bake-off scores transitive
dependency count so a runtime dependency tree is a measured cost (D-7).
Versioning: a compiled artifact carries the plugin's SemVer version and is
checked at invocation (D-9). Existing-seam reuse: fetched artifacts use the
machine-local state home the platform documents, named per the
storage-classes doctrine; no new state home is minted (D-9), and the new
guards are placed against the catalog seam below.

**Research triggers.** New dependency (compiler toolchains in CI, release
tooling), unfamiliar domain (binary distribution for a plugin), a
security-touching pattern (fetching and verifying executables), and
version-sensitive API use (the plugin cache layout and its environment
variables) all fired; the Sources record what was consulted, and the
kickoff brief's risk register carries the distribution survey's tradeoffs.
Three survey findings are risks the register must carry from the start:
the marketplace copy is reported to strip execute bits (which also bears on
today's hook registrations, since they invoke scripts by path); the CLI's
attestation verification may require authentication, so it cannot be the
bootstrap's only check; and every precedent surveyed kept a shell layer,
with the one capability a binary cannot recover being mutation of the
calling shell — planwright has no such entry point today, and the
partition must confirm that before any tier moves.

**The tier boundary precedent.** Where a tier leaves shell, the boundary
the survey found tested in a mature mixed system is the package manager
whose shell tier is exactly what must run before or without its engine
(version, environment, exec, self-update, bootstrap) behind a single
override switch; the profiles of Task 3 say for each surviving tier which
side of that line it falls on (a REQ-B1.2 field).

**Guards and the catalog seam.** Every guard this bundle adds (the lock
lint, the echo lint, the entry-point guard, the number-copy guard, the two
verdict guards, the supersession guard, the placement guard, the
single-implementation guard) ships as `scripts/check-<name>.sh` wired as
`check:<name>` in the check aggregate, per the guard-wiring guard. They are
project-specific invariants, not universal mechanical guards, so they live
as check tasks rather than guard-catalog entries; the catalog seam is named
here and declined for that reason. The compiled-asset build hangs off the
existing release-please release rather than a parallel tagging path.

**Data hygiene.** The pain matrix, the cost baseline, and the bake-off
report are committed artifacts: they carry script names, UIDs, and figures,
never hostnames, paths outside the repository, or credentials.
