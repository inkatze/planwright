# Review backtest and review metrics

The review backtest is a committed set of defects that external reviewers
found and that were then fixed, after planwright's own review passes had
declared the branch clean. A change to how a review pass thinks (a lens, the
reviewer-basics gate, how a pass reads its input) replays the rows in the
classes it targets and may not land while any of them catches fewer rows than
the baseline did. The cost metric measures what a convergence run spends and
how often a converged PR still draws a fixed finding.

Everything here except the corpus screen spends model tokens or reads the
operator's own GitHub history, transcripts, or fleet events. Those entry
points are `eval:` tasks, which `check:no-ci-evals` keeps out of CI; their
mechanics are tested offline in `tests/test-review-backtest*.sh` and
`tests/test-review-cost.sh`.

## The corpus

`tests/fixtures/review-backtest/v<N>/corpus.tsv`, one row per fixed external
finding. A corpus version is a `v<N>` directory, and a version never changes
once written: every recall comparison is made within one version.

| Column | Meaning |
| --- | --- |
| `id` | `r` and at least four digits, unique within the version |
| `pr` | the pull request number |
| `commit` | the pre-fix commit: the commit the review thread was opened on |
| `path`, `line` | where the thread pointed, in that commit |
| `category` | what kind of defect it was |
| `reason` | the miss reason, which is the row's class |
| `replayable` | `yes` when the commit is in the PR head ref's history and shares history with `main` |
| `label_source` | `model`, `ledger`, `declined-log`, or `fallback` |
| `gist` | one paraphrased line saying what was wrong |
| `dismissal` | for a `declined` row, the paraphrased reason it was declined; else `-` |

The classes, categories, and label sources are defined once, in
`scripts/review-backtest-lib.sh`. The miss reasons are the miss-ledger
grammar's reason tokens.

**Hygiene.** The corpus holds only this public repository's data. A gist or
dismissal is always a paraphrase: never reviewer text, a login, a URL, or a
home path. The refresh drops a paraphrase that repeats its comment's wording
or names any login the PR history holds, since only it holds both.
`scripts/review-corpus-screen.sh` refuses a row that breaks the schema or
those rules, and with `--names <file>` also a row naming a listed product.
The product-name list is machine-local, at
`$CLAUDE_PLUGIN_DATA/review-backtest/product-names.txt`, one name per line,
and never committed; CI, which has no list, runs the rest of the screen
through the test suite.

## Rebuilding the corpus

```sh
mise run eval:backtest-refresh
```

`scripts/review-backtest-refresh.sh` fetches the merged PRs and their review
threads with `gh api graphql`, keeps each thread opened by someone other than
the PR's author and answered by the author with a fix reply (two threads on
one line of one commit become one row, and a thread on the base side of the
diff is skipped), fetches every PR's head ref to set the replayable flag, and writes the next `v<N>`,
numbered past every version directory, an empty one left by an interrupted
refresh included.
A PR whose reviews, threads, or comments overflow one fetch page is counted
in a warning, since its extra findings are missing.
Labels come from a `review-miss` ledger fragment for the same PR and path
(read from the observation entries and archive), else from the same row in
the previous version, else from the annotator's
match against the PR body's declined log, else reason `other` (reported as
the fallback count). `--label-reasons` has the annotator assign the class
instead of `other`; that is how a version is bootstrapped where no ledger
exists yet. The annotator (`scripts/review-backtest-annotate.sh` by default,
or any executable given with `--annotate-cmd`) writes the paraphrases; a
paraphrase that repeats the comment's wording is dropped, and every written
row passes the screen with the product-name list required.

The refresh refuses to run without the product-name list, and refuses a
history carrying a PR number that is not a positive integer.
`--dump-history <file>` saves the fetched history, raw review text and logins
included, so keep that file outside the repository; `--fetch-only` stops
there, writing no corpus.

## Environment

- `PLANWRIGHT_BACKTEST_CLAUDE`: the `claude` binary the default reviewer and
  annotator run (default `claude`).
- `PLANWRIGHT_BACKTEST_MODEL`: the annotator's model (default: the CLI's).
- `PLANWRIGHT_BACKTEST_MAX_TURNS`: the default reviewer's turn cap.
- `PLANWRIGHT_BACKTEST_RETRY_WAIT`: seconds before a failed reviewer's retry.

## Replaying it

```sh
mise run eval:backtest --corpus tests/fixtures/review-backtest/v1 \
  --model <model id> --classes runtime-tracing,outside-diff \
  --baseline tests/fixtures/review-backtest/v1/baseline.tsv
```

`scripts/review-backtest.sh` samples each targeted class at random under a
recorded seed, capped per class (`--cap`, its default in the script's header), after excluding
unreplayable rows; it refuses a sample with no replayable row overall or in a
targeted class. Each row is one review pass, no fixes and no loop, run by
the reviewer command in a fresh clone at the row's pre-fix commit, with no
remote to push to and a redirected home and state home for the commands it
runs, when the reviewer is one that runs commands. The default reviewer runs
none: it reads the change from a diff file beside the clone with read-only
file tools in restricted mode. A reviewer that exits non-zero is retried once,
after `PLANWRIGHT_BACKTEST_RETRY_WAIT` seconds (30 by default). A `declined` row's dismissal is seeded
into the coordinator's ledger the pass receives. A row is caught when any
finding cites its file within 10 lines of its line.

With `--baseline`, the run reuses the baseline's seed and cap, refuses a
baseline recorded on another model or corpus version, and exits 1 when a
targeted class catches fewer rows than the baseline did. A failed gate is not
re-run with a new seed without the operator.

The default reviewer, `scripts/review-backtest-reviewer.sh`, is today's pass:
`/self-review`'s discovery step, lenses walked inline, read from the
planwright checkout running the replay. `--model` takes the full model id, never an
alias, since a baseline is only comparable on the model it ran on. A changed reviewer is replayed by
pointing `--reviewer` at an executable that prints `<path><TAB><line>` per
finding. `--out` writes the result, which can serve as the next baseline
unless it holds error rows: a row whose setup or reviewer failed is recorded
but left out of its class's counts, and the run exits 4.

## The metrics and the baselines

```sh
mise run eval:review-cost --prs-from <first PR> --merged-after <its merge date>
```

`scripts/review-cost.sh` reports tokens per convergence run and its share of
the unit (from the transcripts and fleet events), and the post-convergence
finding rate over bot-reviewed PRs, median fixed findings, and median review
rounds (from the PR history and the miss ledger, its archived fragments
included). It counts the bot's fixed findings and rounds, the population the
baselines measured, plus any recorded miss. It compares the rate and the token
median against `tests/fixtures/review-backtest/baselines.tsv`, the research seed's
measurements recorded as decided values (the finding rate re-measured over
the seed's PR range under this metric's fixed-finding definition), and gives a verdict only over a
window of at least 15 bot-reviewed PRs.
`--prs-from` and `--prs-to` bound the PRs by number; `--merged-after` bounds
the PRs by merge date and the convergence runs by start date, so a closeout
passes it for both halves of the bar to read one window.
