# Universal-binary verdict draft: the library and skill-called tiers

**Status: draft, not signed.** This page proposes the verdict decisions
universal-binary Task 9 asks for, for the two tiers bake-off A covers. A
verdict is a meaning-class amendment to a signed bundle (D-8), which only
the operator's amendment kickoff (`/spec-kickoff`) can add and sign, so
nothing here is in the bundle: `design.md`, `requirements.md` and
`tasks.md` are untouched, and no decision below has any standing until
that kickoff adopts, changes or rejects it.

The recommended pick is **Rust** for both tiers, with Go as the close
alternative; the decisions below carry both, and staying in shell, at equal
weight.

## What the draft rests on

- Bake-off A's two committed reports, each with its rendered view:
  [glibc Linux](substrate/bakeoff-a/2026-11-03-linux-x86_64/view.md) and
  [macOS on Apple silicon](substrate/bakeoff-a/2026-11-15-darwin-arm64/view.md).
  The macOS run used the toolchain pins the bake-off's
  [README](../tests/fixtures/substrate-bakeoff/bakeoff-a/README.md) names,
  installed through the offload Mac's own mise, built natively there, and
  ran niced on a shared host while its owner was idle.
- The [cost baseline](substrate/cost-baseline-2026-10-18.md), the
  [pain matrix](substrate/pain-matrix-2026-10-18.md) and the
  [constraint profiles](substrate/constraint-profiles-2026-10-18.md).
- The tiers' shell source sizes, read from `mise run substrate:partition`
  at `e5465b3832f154d77025355658a60564e9472d56`: every script of the tier
  without the no-live-caller flag, sized in bytes.

**musl is unmeasured.** The matrix names three platforms (D-13) and this
draft has reports for two. This host has no Docker to run the Alpine
image, and the on-demand CI job Task 6 recommended was declined in favour
of running on the offload Mac, which covers macOS only. Task 6's done-when
asks for a report on every matrix platform, so the kickoff either accepts
these verdicts without a musl report (and says so in the amendment) or
holds them for one. The gap weighs more on Rust than on Go: Rust's
glibc-Linux build links glibc statically, an LGPL obligation the musl
target avoids, and that target is exactly what is unmeasured.

## Open items for the operator's kickoff

1. **The pick.** Rust, as drafted, or Go. The figures and the reasons for
   each are in D-19.
2. **musl.** Accept the verdicts without a musl report, or hold them for
   one (above).
3. **The dev-check question** (Task 9's Awaiting-input entry), below. The
   recommendation recorded there is the hub's, not the operator's answer.
4. **The hook tier.** No hook verdict is drafted here: bake-off B has only
   its glibc Linux report, and its macOS run has not been done.
5. **A guard gap the draft ran into.** A citation names a candidate and a
   field, not a report, and both verdict guards resolve it to the first
   report on the `**Report:**` line that carries that candidate. Every
   bake-off A and B report has the same three full candidates, so a
   verdict can cite figures from one report only: the macOS report's
   figures, and an inherited bake-off's, cannot be cited at all. D-19's
   rationale therefore cites the Linux report and describes the macOS one
   in words.

The rest of Task 9 (the bootstrap supersession annotation and its guard,
the security-posture restatement, the method page and the verification
checklist) is not drafted here.

## The dev-check tier: the hub's recommendation, pending the operator's answer

Task 8's screen record makes the case for a dev-check bake-off of its own
and escalates it to the operator. The hub's recommendation, recorded here
as the hub's and not as the operator's answer, is **no separate dev-check
bake-off**: the tier keeps its consolidation path, Task 14's branch that
moves its hand-rolled parsers and table readers onto shared helpers and
its workflow-embedded shell into `scripts/`. The tier is dev-only, has low
auditability weight and permits a toolchain, and the classes that lead its
pain-matrix row (instruction-headroom and lint-gap) are not ones a change
of substrate removes. The breadth rule as written (REQ-C1.3) gives no
route other than a bake-off once the screen leaves more than one survivor,
so taking this recommendation is itself a meaning-class amendment for the
kickoff to sign. No dev-check verdict is drafted.

## How to check the decisions below

The verdict guards read a bundle's `design.md`, so they run on this draft
by staging the page as one:

```sh
d=$(mktemp -d) && cp docs/universal-binary-verdict-draft.md "$d/design.md" &&
  scripts/check-verdict-figures.sh --bundle "$d" &&
  scripts/check-verdict-effort.sh --bundle "$d"
```

## Draft decisions

<!-- design.md's decision shape, kept verbatim so the kickoff can move it
     in unchanged: a label's list follows it with no blank line. -->
<!-- markdownlint-disable MD032 -->

### D-19: The library tier's verdict is Rust  (N)

**Decision:** The library tier moves from shell to Rust behind its frozen
entry points (D-10), built per platform from source in the repository and
shipped through the delivery pipeline of Task 10.

**Report:** `docs/substrate/bakeoff-a/2026-11-03-linux-x86_64/report.tsv`,
`docs/substrate/bakeoff-a/2026-11-15-darwin-arm64/report.tsv`

**Alternatives considered:**
- Go. Rejected because: it measured close to Rust on everything but
  latency, where it was slower on both platforms, and the library tier
  answers to a hook's budget at every call site a hook reaches. Its
  advantages are real (smaller sources, one runtime dependency, and a
  linker that cross-compiles and ad-hoc signs for Apple silicon from a
  Linux runner, D-6) and are why it is the close alternative rather than a
  clear loser.
- Stay in shell, hardened and restructured. Rejected because: the
  restructured shell candidate still forks external commands on every call
  and was the slowest full candidate on both platforms, and the classes
  that only a substrate change removes stay open (the cost-benefit line
  costs this option at equal weight).
- Zig or Bun-compiled TypeScript. Rejected because: they are comparison
  points, measured on the trivial program only and never selectable
  without a further bake-off (REQ-C1.1).

**Chosen because:** every full candidate passed every production fixture
on both platforms, so the choice turns on the other fields. On the Linux
report Rust's call-site median was 3.918 ms (`rust.latency_median_ms`)
against 8.195 ms (`go.latency_median_ms`) for Go and 11.669 ms
(`shell.latency_median_ms`) for the restructured shell, which spawned 4
(`shell.spawns_per_invocation`) external commands per call where Rust
spawned 0 (`rust.spawns_per_invocation`) and Go 0
(`go.spawns_per_invocation`). The macOS report orders the three the same
way, and there the shell candidate's call site forks more commands than on
Linux, because the BSD `ps` lacks the `etimes` field and the lock library
asks a second time for `etime`. Go
wrote less code, 12992 bytes (`go.source_bytes`) against 17534 bytes
(`rust.source_bytes`), with 1 (`go.dependency_count`) runtime dependency
against 2 (`rust.dependency_count`), and ported faster, 0.151 min/KiB
(`go.porting_rate_min_per_kib`) against 0.178 min/KiB
(`rust.porting_rate_min_per_kib`), with a similar review load, 0.394
(`go.review_findings_per_kib`) against 0.409
(`rust.review_findings_per_kib`) findings per KiB; but those two logs come
from a single convergence run each (unqualified) and the gaps are small,
while bake-off B's qualified logs, two convergence runs each, favour Rust
on both. The latency gap is the one large, repeated difference, and it is
the one that reaches hooks.

**Cost-benefit:**
- **Migration effort:** the tier's shell source, 1629.1 KiB, at Rust's
  0.178 min/KiB (`rust.porting_rate_min_per_kib`): about 290 minutes of
  worker time; at Go's 0.151 min/KiB (`go.porting_rate_min_per_kib`),
  about 246. The rates are one automated worker's, measured per KiB of the
  candidate's own source, which ran larger than the shell it ported, so
  the extrapolation REQ-G1.3 prescribes understates both; the delivery
  pipeline (Task 10) is extra and has no logged rate.
- **Ongoing cost delta:** the baseline splits neither fix-typed commits
  nor observations by tier, so the projection is a ceiling. The library
  row of the pain matrix holds 33 of its 125 class cells in the classes a
  compiled substrate removes (echo-sanitization, perf-spawn-cost, and the
  shell-tool side of portability). If the tier carried the whole layer's
  fix-typed rate of 20 a month (September and October), removing those
  cells would take it to about 14.7; observation inflow for the tier falls
  by at most about 8 a month (the 33 cells over the four mined months).
- **Eliminated versus relocated:** eliminated: echo-sanitization (no shell
  `echo`), perf-spawn-cost at every ported call site, and the BSD-versus-GNU
  and bash-version side of portability. Relocated: platform divergence
  moves into the program (the prototypes read procfs on Linux only and fall
  back to the pid elsewhere) and into the build (a native macOS build and
  signing step for Rust); lock-concurrency and parser-fragility move into
  typed code over the same filesystem and grammar; lint-gap moves to the
  Rust lint stack under the check aggregate; plugin-delivery grows
  (fetched artifacts, attestation, execute bits); auditability moves to
  the D-16 criteria. Instruction-headroom is untouched.
- **Restructured-shell share of the gain:** unmeasured. The shell
  candidate is already the restructured form and no unrestructured
  candidate was run, so the bake-off cannot split the latency gain between
  substrate and architecture. Duplicated-primitive, the library row's
  largest class, is closed by consolidation (Task 13's kind of work) under
  either verdict, so it is counted to architecture and not to Rust.
- **Stay in shell, at equal weight:** restructuring the tier at the shell
  rate, 1.071 min/KiB (`shell.porting_rate_min_per_kib`), is about 1745
  minutes, inflated because the shell prototype was written first and
  carried the contract's design (risk R5), and Task 13's consolidation
  covers less than the whole tier. Nothing is eliminated:
  echo-sanitization is held by the printf lint, perf-spawn-cost is reduced
  by batching but every call still forks, and portability stays live, as
  the macOS run's extra forks show. Delivery and auditability stay as they
  are.
- **Break-even:** the compiled verdict pays while the classes it can grow,
  plugin-delivery and auditability, grow by less than the eliminated
  classes shrink. On the baseline's observation-inflow table, those two
  columns together carried 74 observations over June to September (about
  18.5 a month) and the eliminated classes 59 (about 14.75 a month), so
  the threshold is a combined plugin-delivery and auditability inflow
  under about 33.25 a month after the compiled delivery ships. Above it,
  staying in shell is the cheaper option.

### D-20: The skill-called tier inherits the library tier's verdict  (N)

**Decision:** The skill-called tier inherits D-19's verdict (Rust) under
the breadth rule (D-5, REQ-C1.3), with the profile comparison below, and
moves behind its frozen entry points like the library tier.

**Report:** `docs/substrate/bakeoff-a/2026-11-03-linux-x86_64/report.tsv`,
`docs/substrate/bakeoff-a/2026-11-15-darwin-arm64/report.tsv`

**Alternatives considered:**
- A bake-off of its own. Rejected because: its profile matches the
  library tier's on every hard axis, and bake-off A was built for the pair
  (D-5).
- Stay in shell. Rejected because: as for D-19, whose cost-benefit line
  this one follows.

**Chosen because:** the constraint profiles give skill-called and library
the same hard axes: adopter-runtime audience, no per-call latency budget
of its own, and medium auditability weight. Bake-off A measured the pair
on two primitives from that shared profile, and its Rust candidate passed
every fixture on both platforms with a call-site median of 3.918 ms
(`rust.latency_median_ms`) and 0 (`rust.spawns_per_invocation`) spawns per
call on Linux. Two skill-called entry points carry the shell-mutation flag
(`inception-validate.sh`, `resolve-steps.sh`); per risk R4 they stay in
shell until the flag is cleared, and the verdict covers the rest of the
tier.

**Cost-benefit:**
- **Migration effort:** the tier's shell source, 3013.3 KiB, at Rust's
  0.178 min/KiB (`rust.porting_rate_min_per_kib`): about 536 minutes of
  worker time; at Go's 0.151 min/KiB (`go.porting_rate_min_per_kib`),
  about 455. The same understatement as D-19 applies, and the two flagged
  entry points are excluded in practice.
- **Ongoing cost delta:** a ceiling, as in D-19: 31 of the skill-called
  row's 192 class cells fall in the eliminated classes, so if the tier
  carried the layer's whole fix-typed rate of 20 a month it would fall to
  about 16.8, and its observation inflow by at most about 7.75 a month.
- **Eliminated versus relocated:** as D-19. The tier's leading class,
  instruction-headroom, is untouched by any substrate.
- **Restructured-shell share of the gain:** unmeasured, as in D-19.
- **Stay in shell, at equal weight:** at the shell rate, 1.071 min/KiB
  (`shell.porting_rate_min_per_kib`), about 3227 minutes, with the same
  caveats and the same open classes as D-19.
- **Break-even:** D-19's threshold, shared, since the baseline does not
  split inflow by tier.
