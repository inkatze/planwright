# Universal-binary verdict draft: the library and skill-called tiers

**Status: draft, not signed.** The universal-binary spec decides, tier by
tier, whether planwright's shell scripts stay shell or move to a compiled
language. A tier's answer is its *verdict*. This page drafts the verdicts
for the two tiers bake-off A measured: the **library** tier (scripts other
scripts source or call) and the **skill-called** tier (scripts a skill runs
by path). A verdict is a meaning-class amendment to the signed spec (its
D-8), which only the operator's amendment kickoff (`/spec-kickoff`) can add
and sign. Nothing here is in the spec: its `design.md`, `requirements.md`
and `tasks.md` are untouched, and no decision below stands until that
kickoff adopts, changes or rejects it.

**Recommended pick, by this draft's author: Go** for both tiers, with Rust
as the close alternative. D-19 below weighs Rust and staying in shell
alongside Go.

**Decide at the kickoff:** the pick, whether to accept the verdicts without
a musl report, and the dev-check question; the full list is under *Open
items*.

## Open items for the operator's kickoff

1. **The pick.** Go, as drafted, or Rust. Rust was faster on both
   platforms; Go wrote less code, has fewer runtime dependencies, ported
   faster, and its delivery path is the one the spec already assumes
   (D-19 has the figures). The hook tier's bake-off B favours Rust more
   strongly, so if one compiled language should serve every adopter tier,
   that is the real trade-off to settle.
2. **musl.** Accept the verdicts without a musl report, or hold them for
   one (see *What the draft rests on*).
3. **The dev-check question.** The spec's recorded recommendation is to add
   a dev-check bake-off; the hub (mission control) recommends the opposite.
   Both are below. Neither is the operator's answer.
4. **The skill-called tier's second bake-off ground.** The breadth rule
   (REQ-C1.3) also grants a tier its own bake-off when its pain-matrix row
   carries a defect class no earlier bake-off exercised. The skill-called
   row leads with instruction-headroom and carries plugin-delivery and
   test-flakiness high, none of which bake-off A exercised. D-5 paired the
   two tiers at kickoff; whether that pairing still holds against the
   second ground is the kickoff's call (D-20 assumes it does).
5. **A stale Awaiting-input entry.** `tasks.md`'s Task 6 entry still says
   the macOS and musl reports need a CI job; macOS is now measured. The
   spec is signed, so the entry waits for this amendment.
6. **The hook tier.** No hook verdict is drafted: bake-off B has only its
   glibc Linux report.

The rest of Task 9 (the bootstrap supersession annotation and its guard,
the security-posture restatement, the method page and the verification
checklist) is not drafted here, and neither is a dev-check verdict, which
Task 14 needs whichever way the dev-check question goes.

## What the draft rests on

- Bake-off A's committed reports, each with its rendered view:
  [glibc Linux](substrate/bakeoff-a/2026-11-03-linux-x86_64/view.md) and
  [macOS on Apple silicon](substrate/bakeoff-a/2026-11-15-darwin-arm64/view.md).
  The macOS run used the toolchain pins the bake-off's
  [README](../tests/fixtures/substrate-bakeoff/bakeoff-a/README.md) names
  (Go, Zig and Bun through mise, rustc through rustup), installed in the
  offload Mac's own account, built natively there, and ran niced on that
  shared host.
- The [cost baseline](substrate/cost-baseline-2026-10-18.md), the
  [pain matrix](substrate/pain-matrix-2026-10-18.md) and the
  [constraint profiles](substrate/constraint-profiles-2026-10-18.md).
- The tiers' shell source sizes: the paths `mise run substrate:partition`
  puts in the tier at `e5465b3832f154d77025355658a60564e9472d56`, less those
  with the no-live-caller flag (scripts nothing live reaches), their bytes
  summed with `wc -c`.

**musl is unmeasured.** The platform matrix (D-13) includes musl, and this
draft has no musl report. This host has no Docker to run the Alpine image,
and the operator chose the offload Mac over the on-demand CI job Task 6
recommended (relayed by mission control, 2026-11-15; the Mac covers macOS
only). Task 6's done-when asks for a report on every matrix platform, so the
kickoff either accepts these verdicts without a musl report, and says so in
the amendment, or holds them for one. The gap weighs more on Rust: its
glibc-Linux build links glibc statically, an LGPL obligation the musl target
avoids, and that target is what is unmeasured. Go's build uses no C library
on Linux.

## The dev-check tier

**The recorded recommendation.** Task 8's screen record
([docs/substrate-screen.md](substrate-screen.md), *Recommendation to the
verdict amendment*) and the Task 9 Awaiting-input entry in `tasks.md`
recommend adding a dev-check bake-off on the instruction guard's manifest
parse, because the breadth rule leaves no other route.

**The hub's recommendation, pending the operator's answer.** Mission
control recommends the reverse: **no separate dev-check bake-off**, the
tier keeping its consolidation path, Task 14's branch that moves its
hand-rolled parsers and table readers onto shared helpers and its
workflow-embedded shell into `scripts/`. The tier is dev-only, has low
auditability weight and permits a toolchain, and the classes that lead its
pain-matrix row (instruction-headroom and lint-gap) are not ones a change of
substrate removes. The breadth rule as written gives no route other than a
bake-off once the screen leaves more than one survivor, so taking this
recommendation is itself a meaning-class amendment, and it still needs a
dev-check verdict decision for Task 14 to quote, which is not drafted here.

## Draft decisions

<!-- design.md's decision shape, kept verbatim so the kickoff can move it
     in unchanged: a label's list follows it with no blank line, indented
     under it so the number-copy guard's exemption covers the list. -->
<!-- markdownlint-disable MD007 MD032 -->

### D-19: The library tier's verdict is Go  (N)

**Decision:** The library tier moves from shell to Go behind its frozen
entry points (D-10), built in CI from source in the repository and shipped
through the delivery pipeline of D-9 and Task 10, in both delivery modes.
A library is sourced into its caller, not executed, and some of its verbs
keep state in the calling shell (the lock library's exit trap and its
record of the locks this shell holds), so its sourced functions stay as a
thin shell layer that keeps that state and hands the work to the binary.
Clearing the partition's shell-mutation flag on `config-get.sh` is a
precondition of moving it (risk R4, Task 11).

**Report:** `docs/substrate/bakeoff-a/2026-11-03-linux-x86_64/report.tsv`,
`docs/substrate/bakeoff-a/2026-11-15-darwin-arm64/report.tsv`

**Alternatives considered:**
- Rust. Rejected because: it was faster than Go on both reports, by a wide
  margin on Linux and a narrow one on macOS, but this tier has no per-call
  budget of its own and Go stays within the hook budget wherever a hook
  reaches it. Against that, Rust wrote more source and ported slower per
  KiB in this bake-off, links glibc statically on glibc Linux unless built
  for the unmeasured musl target, and under D-9's CI cross-compile its macOS
  artifact needs the Apple SDK risk R7 names, which this run did not
  exercise because it built natively. Bake-off B, the hook tier's own,
  favours Rust more strongly; that belongs to the hook verdict.
- Stay in shell, hardened and restructured. Rejected because: the
  restructured shell candidate still forks external commands on every call
  and was the slowest full candidate on both platforms, and the classes only
  a substrate change removes stay open (the cost-benefit line costs this
  option at equal weight).
- Zig or Bun-compiled TypeScript. Rejected because: they are comparison
  points, measured on the trivial program only and never selectable
  without a further bake-off (REQ-C1.1).

**Measurements:** from the Linux report, every full candidate passed
51 (`go.tests_passed`) of 51 (`go.fixture_set_count`) fixtures, and:
  - call-site median: Go 8.195 ms (`go.latency_median_ms`),
    Rust 3.918 ms (`rust.latency_median_ms`),
    shell 11.669 ms (`shell.latency_median_ms`);
    hook budget: Go `within`, Rust `within`;
  - spawns per call: Go 0 (`go.spawns_per_invocation`),
    Rust 0 (`rust.spawns_per_invocation`),
    shell 4 (`shell.spawns_per_invocation`);
  - source: Go 12992 bytes (`go.source_bytes`),
    Rust 17534 bytes (`rust.source_bytes`);
    runtime dependencies: Go 1 (`go.dependency_count`),
    Rust 2 (`rust.dependency_count`);
  - porting rate: Go 0.151 min/KiB (`go.porting_rate_min_per_kib`),
    Rust 0.178 min/KiB (`rust.porting_rate_min_per_kib`);
    review findings per KiB: Go 0.394 (`go.review_findings_per_kib`),
    Rust 0.409 (`rust.review_findings_per_kib`), one convergence run
    each, so both unqualified.
  - The macOS report is described in words, since a citation resolves to
    the first report named: every candidate again passed every fixture,
    the order of the medians is the same with the Go-to-Rust gap much
    narrower, both compiled candidates are within the hook budget, and the
    shell call site forks twice as often as on Linux, because the BSD `ps`
    lacks the `etimes` field and the lock library asks a second time for
    `etime`.

**Chosen because:** both compiled candidates passed every fixture on both
platforms, forked nothing at the measured call site and met the hook
budget, while the restructured shell forked on every call and was slowest
on both. That call site is the prototype invoked directly; the shipped
shape adds the shell layer above, a version check per call (D-9), and a
spawn where a caller used to run a sourced function, none of which was
timed. Between
the two, Go wrote less source, carries fewer runtime dependencies, ported
faster per KiB with a review load close to Rust's, and its delivery path
(cross-compiling and ad-hoc signing for Apple silicon from a Linux runner,
D-6) is the one D-9 assumes. Rust's lead is latency, which this tier does
not budget for and which Go never lets breach the hook budget; the two
platforms the matrix still leaves unmeasured for this verdict, musl and the
cross-compiled macOS artifact, both weigh against Rust more than Go.

**Cost-benefit:**
  - **Migration effort:** the tier's shell source, 1629.1 KiB, at Go's
    0.151 min/KiB (`go.porting_rate_min_per_kib`): about 246 minutes; at
    Rust's 0.178 min/KiB (`rust.porting_rate_min_per_kib`), about 290. The
    rates are the fleet's automated workers' (risk R5), measured per KiB of
    the candidate's own source, which ran larger than the shell it ported,
    so the extrapolation REQ-G1.3 prescribes understates both. The delivery
    pipeline (Task 10) is extra and has no logged rate.
  - **Ongoing cost delta:** the baseline splits neither fix-typed commits
    nor observations by tier, and only its mined set carries classes, so
    every projection here is a bound. The library row of the pain matrix
    holds at most 33 class cells in the classes a compiled substrate
    removes (echo-sanitization, perf-spawn-cost, and portability, the whole
    column counted though only its shell-tool side goes), so at most 33 of
    its 116 mined items go. The tier's mined inflow, 116 items over the
    four mined months, would fall to no less than about 20.75 a month. If
    the tier carried the layer's whole fix-typed rate of 20 a month
    (September and October) and fixes fell in the same share, that rate
    would fall to no less than about 14.3 a month.
  - **Eliminated versus relocated:** eliminated: echo-sanitization (no shell
    `echo`), perf-spawn-cost inside every ported call (the call itself
    becomes one spawn where a caller ran a sourced function), and the
    BSD-versus-GNU and bash-version side of portability. Relocated: platform
    divergence moves into the program (the prototypes read procfs on Linux
    only and fall back to the pid elsewhere) and into the build;
    lock-concurrency and parser-fragility move into typed code over the same
    filesystem and grammar; lint-gap moves to Go's lint stack under the
    check aggregate; plugin-delivery grows (fetched artifacts, attestation,
    execute bits); auditability moves to the D-16 criteria.
    Instruction-headroom is untouched.
  - **Restructured-shell share of the gain:** unmeasured. The shell
    candidate is already the restructured form and no unrestructured
    candidate was run, so the bake-off cannot split the gain between
    substrate and architecture. Duplicated-primitive, the library row's
    largest class, is closed by consolidation either way (Task 13 for a
    shell verdict, the port itself for a compiled one), so it is counted to
    architecture and not to Go.
  - **Differential suite:** unmeasured. The suite REQ-E1.3 keeps running
    against the shell implementation in CI does not exist yet (Task 11
    builds it); its cost joins the check aggregate's wall-clock in the
    baseline and is this line's figure once it runs.
  - **Stay in shell, at equal weight:** restructuring the tier at the shell
    rate, 1.071 min/KiB (`shell.porting_rate_min_per_kib`), is about 1745
    minutes. That rate is inflated: the shell prototype was written first
    and settled the contract the other two inherited (the bake-off README),
    and Task 13's consolidation covers less than the whole tier. Nothing is
    eliminated: echo-sanitization is held by the printf lint, perf-spawn-cost
    is reduced by batching but every call still forks, and portability stays
    live, as the macOS run's extra forks show. Delivery and auditability
    stay as they are.
  - **Break-even:** the compiled verdict can only pay while the classes it
    can grow, plugin-delivery and auditability, grow by less than the
    eliminated classes shrink. On the baseline's observation-inflow table,
    layer-wide because it has no tier split, those two columns held 74
    class cells over June to September (about 18.5 a month) and the
    eliminated classes at most 59 (about 14.75 a month). The threshold is a
    combined plugin-delivery and auditability inflow of at most about 33.25
    a month after the compiled delivery ships; above it, staying in shell
    is the cheaper option. The true threshold is lower, since 59 is a
    ceiling, and the one-off migration effort is not netted in.

### D-20: The skill-called tier inherits the library tier's verdict  (N)

**Decision:** The skill-called tier inherits D-19's verdict (Go) under the
breadth rule (D-5, REQ-C1.3), with the profile comparison below, and moves
behind its frozen entry points like the library tier. Clearing the
shell-mutation flag on `inception-validate.sh`, `mc-rules.sh` and
`resolve-steps.sh` is a precondition of moving the tier (risk R4, Task 11).

**Report:** `docs/substrate/bakeoff-a/2026-11-03-linux-x86_64/report.tsv`,
`docs/substrate/bakeoff-a/2026-11-15-darwin-arm64/report.tsv`

**Alternatives considered:**
- A bake-off of its own. Rejected because: its profile matches the library
  tier's on every hard axis, and bake-off A was built for the pair (D-5).
  The classes leading its pain-matrix row that bake-off A did not exercise,
  instruction-headroom above all, are ones no substrate removes, so a
  bake-off of its own would measure them no better.
- Stay in shell. Rejected because: as for D-19, whose cost-benefit line
  this one follows.

**Measurements:** D-19's, inherited from the same reports; on the Linux
report Go passed 51 (`go.tests_passed`) of 51 (`go.fixture_set_count`)
fixtures with a call-site median of 8.195 ms (`go.latency_median_ms`) and
0 (`go.spawns_per_invocation`) spawns per call, at a porting rate of
0.151 min/KiB (`go.porting_rate_min_per_kib`).

**Chosen because:** the constraint profiles give skill-called and library
the same hard axes: adopter-runtime audience, no per-call latency budget of
its own, and medium auditability weight. Bake-off A measured the pair on two
primitives from that shared profile, and D-19's reasons carry over
unchanged.

**Cost-benefit:**
  - **Migration effort:** the tier's shell source, 3013.3 KiB, at Go's
    0.151 min/KiB (`go.porting_rate_min_per_kib`): about 455 minutes; at
    Rust's 0.178 min/KiB (`rust.porting_rate_min_per_kib`), about 536. The
    figure includes the three flagged entry points; the same understatement
    as D-19 applies.
  - **Ongoing cost delta:** a bound, as in D-19: at most 31 of the
    skill-called row's class cells fall in the eliminated classes, so at
    most 31 of its 182 mined items go. Its mined inflow, 182 items over the
    four mined months, would fall to no less than about 37.75 a month, and
    the layer's fix-typed rate of 20 a month, on D-19's assumptions, to no
    less than about 16.6.
  - **Eliminated versus relocated:** as D-19. The tier's leading class,
    instruction-headroom, is untouched by any substrate.
  - **Restructured-shell share of the gain:** unmeasured, as in D-19.
  - **Differential suite:** unmeasured, as in D-19.
  - **Stay in shell, at equal weight:** at the shell rate,
    1.071 min/KiB (`shell.porting_rate_min_per_kib`), about 3227 minutes, with the same
    caveats and the same open classes as D-19.
  - **Break-even:** D-19's threshold, shared, since the baseline does not
    split inflow by tier.

<!-- markdownlint-enable MD007 MD032 -->

## Notes for reviewers

**Why the macOS figures are not cited.** A citation names a candidate and a
field, not a report, and both verdict guards resolve it to the first report
on the `**Report:**` line that carries that candidate. Every bake-off A and
B report has the same full candidates, so a verdict can cite figures from
one report only: the macOS report's figures, and an inherited bake-off's,
cannot be cited at all. D-19's measurements therefore cite the Linux report
and describe the macOS one in words.

**How to check the draft decisions.** The verdict guards and the
number-copy guard read a bundle, so they run on this draft by staging the
spec bundle with the draft decisions appended to its `design.md`:

```sh
d=$(mktemp -d) && cp specs/universal-binary/*.md "$d/" &&
  sed -n '/^### D-19:/,/^<!-- markdownlint-enable/p' \
    docs/universal-binary-verdict-draft.md >>"$d/design.md" &&
  scripts/check-verdict-figures.sh --bundle "$d" &&
  scripts/check-verdict-effort.sh --bundle "$d" &&
  scripts/check-number-copy.sh --bundle "$d"
rm -rf "$d"
```

The guards check cited figures and the porting-rate citation only; the
derived cost-benefit arithmetic (sizes, minutes, cell shares, the
break-even) is checked by hand against the sources the page names.
