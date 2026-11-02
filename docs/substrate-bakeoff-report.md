# Substrate bake-off report

The bake-off harness, `scripts/substrate-bakeoff.sh` (`mise run substrate:bakeoff`),
measures every candidate in a bake-off directory against the same differential
fixtures and writes one report row per candidate. This page is the report's
contract: the input layout the harness reads, every field it writes, the
validation the report must pass, and the form a verdict uses to cite it.

One command produces the report and its rendered view:

```sh
scripts/substrate-bakeoff.sh run --bakeoff <dir> --out-dir <dir>
```

`run` also takes `--run-id <id>` (default: the UTC start time and the process
id) and `--platform <name>` (default: the operating system, `alpine` on
Alpine, and the machine architecture). `validate <report.tsv>` checks a
committed report against this page; `render <report.tsv>` prints its view. The
committed stub bake-off at `tests/fixtures/substrate-bakeoff/stub/` holds one
full candidate and one comparison point; the shell suite runs it on every CI
platform.

## Candidate classes

- A **full candidate** implements every representative primitive the bake-off's
  fixture set holds and is measured on every field below.
- A **comparison point** implements no primitive. It runs only the harness's
  trivial program and carries only the shared and comparison fields; every
  primitive field stays `-`.

## Input layout

```text
<bakeoff>/
  bakeoff.conf                 tier, runs, timeout_s, review_runs, call_site
  fixtures/<primitive>/<case>/ the production differential set
    args                       optional, one argument per line, no empty line
    stdin                      optional
    files/                     optional, copied into the working directory
    expected-stdout            required
    expected-status            required, a whole number
  candidates/<id>/candidate.conf
  implementation-time.tsv
  review-findings.tsv
```

Configuration files are `key=value` lines (`#` starts a comment). They are
parsed, never sourced, and a repeated key fails the run closed.

`bakeoff.conf` keys, all required:

- `tier`: `hook`, `skill-called`, `library` or `dev-check`.
- `runs`: the fixed run count for every latency measurement.
- `timeout_s`: the per-execution timeout in seconds; an execution past it is
  killed with its process group and recorded as a failure.
- `review_runs`: the fixed number of convergence runs the review-findings log
  holds per full candidate.
- `call_site`: the `<primitive>/<case>` fixture that latency, spawn count and
  offline replay are measured on.

`candidate.conf` keys:

- `class`: `full` or `comparison`.
- `invoke.<primitive>` (full) or `invoke.trivial` (comparison): the invocation,
  blank-separated words; a word naming a file in the candidate directory runs
  as that file's absolute path. A full candidate needs one per primitive in the
  fixture set, so a candidate that cannot execute every production fixture is
  refused; a comparison point declaring a primitive is refused.
- `sources` (full): the candidate's own source files, sized in bytes.
- `artifact` (comparison): the file whose size is the binary size.
- `dependencies`: `spawned` (a shell candidate: its distinct spawned commands)
  or a tab-separated listing file with one row per runtime dependency: name,
  licence, last release date, and the standard-library alternative considered.
- `delivery.marketplace`, `delivery.writer`: a script that installs the
  candidate through that delivery mode and exits zero when the installed copy
  runs.
- `build` (optional): a script run once before measuring; its failure makes the
  platform result `fail`.

Every path is relative to the candidate directory and may not climb out of it.
Any other key is refused, so a misspelt optional key cannot pass for an
absent one.

### Log formats

`implementation-time.tsv`: one row per full candidate, tab-separated:
candidate id, dispatch time, and the time of its first green differential run,
both `YYYY-MM-DDTHH:MM:SSZ`. The harness turns the pair into wall-clock
minutes.

`review-findings.tsv`: one row per full candidate per convergence run,
tab-separated: candidate id, the run's index from one to `review_runs`, and
the count of findings that run raised. Findings are normalised as the mean per
run per KiB of the candidate's sources.

## Report fields

The report is a TSV file: a header naming every field, then one row per
candidate. `-` marks a field the row's class does not carry. The schema is
add-only: a new field is appended to the end, and no field is renamed, removed
or moved, so a signed verdict's citation never breaks. `validate` rejects a
header whose leading fields differ from the list below.

Run fields, identical on every row of one report:

| Field | Meaning |
| --- | --- |
| `schema` | always `substrate-bakeoff` |
| `run_id` | the run identifier |
| `platform` | the platform this run measured |
| `tier` | the tier from `bakeoff.conf` |
| `runs` | the fixed run count per latency measurement |
| `timeout_s` | the per-execution timeout in seconds |
| `fixture_set_count` | how many fixtures the production differential set holds |

Shared fields, required for both classes:

| Field | Meaning |
| --- | --- |
| `candidate` | the candidate directory's name |
| `class` | `full` or `comparison` |
| `platform_result` | `pass` when the build succeeded and every invocation launched |
| `delivery_marketplace`, `delivery_writer` | `pass` or `fail` per delivery mode |
| `dependency_count` | transitive runtime dependencies; for shell, the distinct external commands invoked |
| `dependency_listing` | `name,licence,last_release,alternative` entries joined by `;`, or `none` |

Primitive fields, required for a full candidate (the baseline columns and
`hook_budget` excepted, below) and `-` on a comparison point:

| Field | Meaning |
| --- | --- |
| `literal_path` | `yes` when every invocation is one word naming an executable file, a literal path a static allowlist can match |
| `offline_replay` | `yes` when the call site, replayed from its recorded inputs with an empty home, proxies pointed at a closed port, offline toolchain settings and the common toolchains shadowed, reproduces its first output and status |
| `tests_passed`, `tests_failed` | fixture results; a fixture red for shell still counts in the denominator |
| `fixtures_executed` | fixtures the run executed; it must equal `fixture_set_count` |
| `fixture_results` | `<primitive>/<case>:pass` or `:fail` per fixture, joined by `,`; a failure is recorded, never refused |
| `latency_median_ms`, `latency_spread_ms` | the call site over `runs` executions: median and interquartile range (nearest rank), fork to reap |
| `spawns_per_invocation` | external commands the call site started through `PATH` |
| `distinct_commands` | distinct external commands across every fixture |
| `source_bytes` | bytes of the candidate's own sources |
| `implementation_minutes` | dispatch to the first green differential run, from the log |
| `review_runs`, `review_findings` | convergence runs logged and their findings in total |
| `review_findings_per_kib` | findings per run per KiB of source |
| `review_qualification` | `unqualified` for a single convergence run, `qualified` otherwise |
| `porting_rate_min_per_kib` | `implementation_minutes` per KiB of source: the porting rate a verdict's migration effort extrapolates from |
| `baseline_run_id`, `baseline_latency_median_ms`, `baseline_latency_spread_ms` | the shell candidate's latency from this same run; `-` unless the bake-off has a full candidate named `shell`, and required on every full row of a hook-tier report |
| `hook_budget` | `within` when the candidate's median is at most the shell median plus the shell spread, else `over`; present exactly when the baseline columns are |
| `latency_status_mismatches` | timed executions of the call site whose exit status differed from the fixture's expected one; a latency is only as good as this field is low |

Comparison fields, required for a comparison point:

| Field | Meaning |
| --- | --- |
| `trivial_result` | `pass` when the trivial program, given the argument `world`, prints `hello world` and a newline and exits zero |
| `cold_start_median_ms`, `cold_start_spread_ms` | the trivial program over `runs` executions |
| `binary_size_bytes` | the artifact's size |
| `cold_start_status_mismatches` | timed executions of the trivial program that did not exit zero |

### How a candidate runs

Every fixture execution, timed repetition and offline replay runs in a fresh
working directory holding a copy of the fixture's `files/`, with a fresh home
(also its `TMPDIR`) and no environment from the caller beyond `PATH` and the C
locale, in its own process group. The group is killed once the execution is
reaped, and on a timeout or a signal to the harness, so nothing a candidate
leaves running in that group outlives it; a process that moves to a session
or group of its own (`setsid`) is out of the harness's reach. The `build` and
delivery scripts keep the caller's environment, since building and installing
may need it, but get a fresh home too, so an install never lands in the
operator's own.

Spawns are counted by a logging shim for every command on `PATH`, so a command
started by absolute path, the candidate's own executable included, is not
counted. The interpreter a `#!/usr/bin/env` line looks up through `PATH` is.

`run` refuses (exit status one) a candidate whose configuration or logs break
the rules above, and fails closed (exit status five) on an input it cannot
read or parse, including a repeated key and an `expected-status` that is not
an exit status written without leading zeros.

### Validation

`validate`, and `run` before it writes anything, reject a report when:

- a field this page lists is missing, renamed or out of order, or a row's
  field count differs from the header's;
- the schema name is not `substrate-bakeoff`, or the tier is not one of the
  four;
- a row lacks a field its class requires, the implementation-time and
  review-findings fields included;
- a numeric field holds anything but a number, or a `pass`/`fail`,
  `yes`/`no` or `within`/`over` field holds anything else;
- a comparison point carries a primitive field;
- a full candidate's run did not execute every production differential fixture
  (`fixtures_executed` or `fixture_results` short of `fixture_set_count`), a
  `fixture_results` entry is malformed or repeats a fixture, its passing
  entries differ from `tests_passed`, or `tests_passed` and `tests_failed`
  do not add up to `fixture_set_count`;
- `runs`, `timeout_s`, `fixture_set_count` or a full row's `review_runs` is
  not a whole number of at least one;
- `review_qualification` does not match `review_runs`;
- the rows do not share one run's fields, or a candidate appears twice;
- the tier is `hook` and the shell row is absent, or a full row's shell latency
  columns or `hook_budget` are empty, carry another run's id, or differ from
  the shell row.

It exits one with each reason printed, zero when the report is valid, and five
when the report cannot be read. `render` validates first and prints no view of
an invalid report.

### Rendered view

`view.md` leads with the decision-relevant fields, one table row per candidate
(full candidates, then comparison points), followed by every field of every
row under its candidate's heading. Values are escaped for Markdown, so a
listing cannot inject markup into the view.

## Citing a report in a verdict

Two guards under `mise run check` read the bundle's verdict decisions:
`check:verdict-figures` (`scripts/check-verdict-figures.sh`) and
`check:verdict-effort` (`scripts/check-verdict-effort.sh`). Both pass when the
bundle holds no verdict.

A **verdict** is a `### D-` decision in `design.md` carrying a `**Report:**`,
`**Measurement:**`, `**Measurements:**` or `**Cost-benefit:**` line. Its
`**Report:**` line names each committed report it cites as a backticked
repository-relative path, its own bake-off's dated snapshot first and an
inherited bake-off's after it.

Its **rationale** is the `**Chosen because:**` span and every
`**Measurement:**` or `**Measurements:**` span. A span runs from its label
through the list or paragraph under it, ending at a heading, a new paragraph
at the left margin, or another bold label no deeper than its own. Nothing
inside a column-zero code fence counts. Every figure in the rationale cites
its field right after it, with an optional unit between, spaced or glued on
(`<n>` stands for the figure here, since this page holds no figures of its
own):

```markdown
**Chosen because:** a median of <n> ms (`go.latency_median_ms`) against …
```

`check:verdict-figures` fails on a figure with no citation, a citation naming
no candidate row or field of the reports the verdict names, a field without a
value, or a figure that differs from the value (compared as numbers, so a
trailing zero after the decimal point does not matter). Identifiers, dates,
paths and task, section, step or wave numerals are references, not figures, as
in `check:number-copy`; a figure with a unit glued on (`ms`, `s`, `min`, `h`,
`x`, or a byte unit) is still a figure. The
`**Cost-benefit:**` line's figures come from the cost baseline and the effort
extrapolation, not a bake-off report, so this guard leaves them to
`check:number-copy` and `check:verdict-effort`.

The **migration effort** is the `**Migration effort:**` span, usually an item
under the cost-benefit line. `check:verdict-effort` fails on a verdict without
one, and on one that neither cites a porting rate nor carries the absence
token of a verdict the screen settled, `` `porting-rate: absent` `` with its
backticks:

```markdown
- **Migration effort:** the tier's shell source at <n> min/KiB
  (`go.porting_rate_min_per_kib`), extrapolated to …
```

The cited candidate must be a full candidate of a report on the verdict's
`**Report:**` line, and a figure carrying the citation must equal its logged
rate.
