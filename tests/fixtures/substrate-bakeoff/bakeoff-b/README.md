# Bake-off B: the hook tier

The bake-off for the hook tier, whose budget is no regression against shell
on the same runner (universal-binary D-14). Every full candidate the screen
admitted for adopter tiers implements the same two representative primitives
against the same production differential fixtures; there are no comparison
points here. The candidate screen is
[docs/substrate-screen.md](../../../../docs/substrate-screen.md), and the
harness and its report schema are
[docs/substrate-bakeoff-report.md](../../../../docs/substrate-bakeoff-report.md).

## Running it

The toolchains are bake-off A's, and every build runs with a fresh home, so
the toolchain locations come from the environment. Put `rustc` on `PATH`
before `mise exec`, which adds Go in front of it:

```sh
PATH="$HOME/.cargo/bin:$PATH" mise exec go@1.27.3 -- \
  env RUSTUP_HOME="$HOME/.rustup" CARGO_HOME="$HOME/.cargo" \
  scripts/substrate-bakeoff.sh run --bakeoff tests/fixtures/substrate-bakeoff/bakeoff-b --out-dir <dir>
```

Compiled output lands in each candidate's `out/`, which is ignored and never
committed. Each committed report sits under
`docs/substrate/bakeoff-b/<date>-<platform>/` with its rendered view; a
platform the matrix names but no report covers is not measured yet.

The report's baseline columns and `hook_budget` carry the REQ-B1.5 rule: each
candidate's median against the shell row's median plus its spread, from the
same run.

## The primitives

Both contracts are written once, in the shell candidate's
[lib/proto.sh](candidates/shell/lib/proto.sh), and the Go and Rust sources
reimplement them.

- **`tokenize`**, the tokenizer of `scripts/worker-command-guard.sh`: the
  command on stdin, one output line per token with every provenance flag the
  production tokenizer records, then one per command substitution. A
  command it refuses prints nothing and exits 3.
- **`ready`**, the predicate of `scripts/ready-guard.sh` (its
  `evaluate_predicate` path): the GitHub answers as files in the working
  directory, and the hook's own decision object out, or nothing when the
  flip may proceed.

The shell candidate loads the production functions rather than copying them,
so it is measured on the code the hooks run. Neither hook can be sourced,
since each runs its main on load, so the seam lifts the named functions out
of the file in one awk pass and evaluates them. For `ready` it replaces only
the seams the fixtures stand in for: `gh` reads the answer files, the timeout
wrapper runs its command directly, the re-query does not sleep, and the
`ready_guard_behind_base` policy is an argument.

## The fixtures

`fixtures/tokenize/` and `fixtures/ready/` are the production differential
set. Their inputs were written before any candidate; their expectations were
then recorded from the shell candidate, which is the production code, and
each was read by hand against the contract before Go or Rust ran. Only stdout
and the exit status are compared.

The `vec-` tokenizer cases are the false-allow vectors the bundle's
parser-fragility observations name. [vectors.tsv](vectors.tsv) maps each to
its observation UID; `tests/test-substrate-bakeoff-b.sh` fails when a listed
case is missing, when a `vec-` case is not listed, or when a UID is not in
the bundle's parser-fragility Sources. A tokenizer cannot itself allow
anything, so each case pins the token stream that lets the guard's screens
see the vector: the glued output flag, the quote position of a `git -c` or
`VAR=` value, the bare parenthesis fish substitutes, the `>&` target, the
path and tilde, the unchanged case of a config key, the substitution inside
double quotes, and nothing at all for a command it cannot parse.

## The logs

- `implementation-time.tsv`: per full candidate, the moment its
  implementation started and the moment it first passed every fixture under
  a differential run, both read from the clock as they happened. One
  automated worker wrote the candidates in turn (shell, Go, Rust). The
  shell candidate's time and source size cover only its seam, since the
  primitives themselves are production code, so its porting rate measures
  wiring, not porting.
- `review-findings.tsv`: per full candidate, the findings the convergence
  pass raised against that candidate's own sources, one row per convergence
  run.

## Known limits of the prototypes

- The shell latency is bash starting, one awk pass over the hook file, and
  the extracted functions running. The production hook instead parses its
  whole file and reads the payload through jq first; neither cost is in any
  candidate's figure.
- jq behaviours the compiled `ready` ports do not reproduce, none of them in
  the fixtures: a `view` answer holding more than one JSON value (jq answers
  per value; the ports refuse the answer as unreadable), a non-integer
  number's printed form, and the replacement of invalid UTF-8 in the
  decision text. The Rust JSON reader refuses nesting deeper than its
  `MAX_DEPTH`.
- Latencies are fork-to-reap times on whatever host ran the report, under
  that host's load at the time; compare candidates within one report, not
  across reports.
