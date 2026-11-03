# Bake-off A: the adopter-runtime pair

The bake-off for the library and skill-called tiers, which share one
constraint profile (universal-binary D-5). Every full candidate implements
the same two representative primitives against the same production
differential fixtures; the comparison points run only the harness's trivial
program. The candidate screen is [docs/substrate-screen.md](../../../../docs/substrate-screen.md),
and the harness and its report schema are
[docs/substrate-bakeoff-report.md](../../../../docs/substrate-bakeoff-report.md).

## Running it

The toolchains are not part of planwright's pinned development tools; the
bake-off names its own, and every build runs with a fresh home, so the
toolchain locations come from the environment:

```sh
mise exec go@1.27.3 zig@0.17.0 bun@1.4.4 -- \
  env RUSTUP_HOME="$HOME/.rustup" CARGO_HOME="$HOME/.cargo" \
  scripts/substrate-bakeoff.sh run --bakeoff tests/fixtures/substrate-bakeoff/bakeoff-a --out-dir <dir>
```

Rust is `rustc` 1.97.1 from rustup, used without Cargo: no candidate uses a
package, so no manifest or lockfile exists. Compiled output lands in each
candidate's `out/`, which is ignored and never committed.

Each committed report sits under
`docs/substrate/bakeoff-a/<date>-<platform>/` with its rendered view. A
platform the matrix names but no report covers is not measured yet; a report
only ever describes the platform and run it names. The inputs live here, under
`tests/`, so that a local run's build output never lands in `docs/`.

## The primitives

Both contracts are written once, in the shell candidate's
[lib/proto.sh](candidates/shell/lib/proto.sh), and the Go and Rust sources
reimplement them.

- **`lock`**, the advisory lock of `scripts/lock-lib.sh`: `try-for <path>
  <pid>` (one attempt on another process's behalf, printing each dead owner
  it broke and then the owner field read back off the new link), `owner`,
  `alive` and `release`. The on-disk shape is lock-lib's: the lock is a
  symlink whose target is the owner token, and a dead owner is broken through
  a claim link and a rename, never an unlink of the live path.
- **`deps`**, the `Dependencies:` line parse of the shared spec grammar in
  `scripts/spec-parse.sh`: a `TASK` record per conforming task heading and a
  `TASKDEP` record per dependency token, with column-0 fences skipped and an
  unclosed fence failing closed. The screen record says why this parser was
  chosen.

The shell candidate loads the production libraries rather than copying them,
so it is measured on the code the tree runs. Its prototype library is used by
these two entry points and by nothing else in the tree.

## The fixtures

`fixtures/lock/` and `fixtures/deps/` are the production differential set.
The `deps` expectations were checked against `scripts/spec-model.sh`, the
production reader, before any candidate ran (stdout; the exit statuses
follow `scripts/spec-parse.sh`'s fail-closed fence rule, which `spec-model.sh`
does not apply, so `unclosed-fence` expects 3 where it exits 0);
`real-bundle` is universal-binary's own `tasks.md` at the time of recording.
Lock state is seeded through each fixture's `links` file, so the repository
tracks no symlink. A live owner is pid 1 with a mint time far in the future,
and a dead one a pid larger than any the matrix assigns.

Only stdout and the exit status are compared; stderr is not.

## The logs

- `implementation-time.tsv`: per full candidate, the moment its
  implementation started (standing in for the schema's dispatch time, since
  one worker wrote all three in turn) and the moment it first passed every
  fixture under a differential run, both read from the clock as they
  happened. The
  fixtures were written before any of them and are not in any candidate's
  time. One automated worker wrote the candidates in turn (shell, Go, Rust),
  so the later two inherit the contract the first settled; the times measure
  that worker's porting rate, not a person's (risk R5).
- `review-findings.tsv`: per full candidate, the findings the convergence
  pass raised against that candidate's own sources, one row per convergence
  run.

## Known limits of the prototypes

- Outside Linux, or on a Linux host whose procfs is unreadable, the
  compiled lock prototypes skip the recycled-pid check (they read process
  start times from procfs only) and fall back to the pid alone, which
  `lock-lib.sh` also does wherever it cannot read a start time. The shell
  candidate asks `ps` instead. No fixture distinguishes the two.
- The compiled prototypes mint tokens with an empty uptime field wherever
  `/proc/uptime` is unreadable, where the shell candidate reads pid 1's
  elapsed time instead.
- Latencies are fork-to-reap times on whatever host ran the report, under
  that host's load at the time; compare candidates within one report, not
  across reports.
