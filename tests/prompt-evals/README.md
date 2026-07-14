# Kept prompt-evals

> **Standing status (2026-07-14):** the suite is **guarded-inoperative** —
> headless CLI slash-path skill injection is unavailable, so every cell
> correctly aborts INVALID (exit 3) at the skill-injection sentinel instead
> of grading a bare model. See `results/comparison.md` for the full record
> and the `behavioral-pilot-injection-design` follow-up observation for the
> path to reactivation.

The behavioral backstop for the instruction-hygiene size guard (prompt-hygiene
Task 4; `doctrine/instruction-hygiene.md`, REQ-C1.4/C1.6/D1.3, D-6/D-7/D-8/D-12).
The size guard is the cheap always-on proxy; this fixture suite is the
ground-truth check that catches the case where an instruction file passes the
word budget yet still degrades behavior. It runs **on demand**, never in CI (see
"Never in CI" below).

## Layout

```text
tests/prompt-evals/
  README.md                 this file
  fixtures/<id>/            one directory per fixture
    fixture.conf            id, skill, k, budget caps (KEY=VALUE, data only)
    prompt.txt              the literal slash-command prompt, passed as the -p argument
    setup.sh                seeds the hermetic work tree (optional)
    probe.sh                emits observable side effects as JSON (optional)
    assert.jq              grades the outcome; true = pass
  results/                  scrubbed, committed baseline artifacts + pilot record
```

## Running it

```sh
mise run eval:skill                              # the whole suite, pass^3
scripts/prompt-eval.sh --suite tests/prompt-evals/fixtures
scripts/prompt-eval.sh tests/prompt-evals/fixtures/orchestrate-print-ready
```

Record the pre-diet baseline (bind it to the pre-diet commit so the paired
post-diet comparison in Task 5 is honest):

```sh
scripts/prompt-eval.sh --suite tests/prompt-evals/fixtures \
  --record tests/prompt-evals/results \
  --expect-plugin-commit "$(git rev-parse HEAD)"
```

Record a post-diet run beside it (same fixtures, dieted plugin) and pair the
two by fixture identifier:

```sh
scripts/prompt-eval.sh --suite tests/prompt-evals/fixtures \
  --record tests/prompt-evals/results/post-diet \
  --expect-plugin-commit "$(git rev-parse HEAD)"
```

`results/*.json` is the committed pre-diet baseline (Task 4, bound to the
pre-diet commit recorded in that run's PR; post-hoc bare-model INVALID — see
the standing status above). Task 5's post-diet re-run was deferred with the
pilot: `results/post-diet/` does not exist yet. Once the injection follow-up
reactivates the suite, the post-diet run on the identical fixtures will land
in `results/post-diet/*.json` and pair by fixture identifier. The paired
comparison record and the pilot verdict live in `results/comparison.md`
(REQ-D1.3).

The runner needs a Claude Code CLI on `PATH` and, because it runs `--bare`, an
`ANTHROPIC_API_KEY` (OAuth and keychain are never read in `--bare` mode). Each
run costs tokens; the caps below bound that.

## Fixture format

Each fixture drives one skill headlessly and grades observable outcomes.

- **`fixture.conf`** — `KEY=value` lines, read as data (never sourced):
  `id` (stable identifier; defaults to the directory name), `skill` (names the
  skill under eval and drives the runner's skill-injection validity check),
  `k` (pass^k runs; default 3), `max_budget_usd` and `max_turns` (per-run
  caps).
- **`prompt.txt`** — the prompt, passed to `claude -p` **as the prompt
  argument** (the runner never pipes it on stdin: the CLI slash-expands only
  the prompt string, and a stdin-piped command reaches the model as literal
  text). It MUST be the literal slash-command invocation, one line (e.g.
  `/planwright:orchestrate specs/demo --backend print --unattended`): headless
  `-p` exposes no Skill tool, so only CLI expansion of a leading slash command
  puts the SKILL.md in context — a prose prompt ("Run /orchestrate on …")
  silently grades a bare model improvising over the repo, which is exactly how
  the original Task 4 baseline was invalidated.
- **`setup.sh <work-tree>`** — seeds the disposable work tree before each run
  (e.g. a spec bundle for `/orchestrate` to act on). `PROMPT_EVAL_PLUGIN_DIR`
  points at the planwright plugin so setup can call its scripts (e.g.
  `spec-anchor.sh` to sign a gate-valid brief). A non-zero exit aborts the
  fixture fail-closed.
- **`probe.sh <work-tree>`** — after the run, prints a JSON object of extra
  fields (filesystem side effects such as a dispatch marker or a created
  branch). The runner merges it into the outcome `assert.jq` sees.
- **`assert.jq`** — a jq program over the merged outcome; a truthy result is a
  pass. The outcome carries `is_error`, `subtype`, `result` (the model's final
  text), `num_turns`, `plugin_loaded`, `cost_usd`, plus any `probe.sh` fields.
  The program **must yield a boolean verdict**: truthy passes, `false`/`null`
  is a graded fail. Producing *no output* (e.g. a bare `select(...)` that
  filters everything away on a non-match) is treated as a broken assert and
  aborts fail-closed, **not** as a graded fail — so end the chain with an
  explicit boolean (`... != null`, `... | test(...)`, `any(...)`, `contains(...)`)
  rather than a `select` whose only signal is presence-or-absence of output.

## Runner contract (`scripts/prompt-eval.sh`)

- **Hermetic.** `claude -p --bare --plugin-dir <plugin>`; the plugin is pinned,
  hooks are skipped, and each run gets a uniquely-named disposable work tree,
  pruned before and torn down after (isolation & re-runnability, R8). The
  prune-first reaps *every* tree for the fixture id, so a single runner
  invocation per fixture is assumed; two concurrent runs of the same fixture are
  a known, unsupported limitation (the second's prune would reap the first's
  in-flight tree).
- **Plugin-load verification.** A run that never loaded the planwright plugin
  (checked from the `system/init` event) is **INVALID**, not a graded failure.
- **Skill-injection verification.** Plugin registration alone is insufficient:
  when `fixture.conf` names a `skill`, the run's transcript must carry that
  SKILL.md's full H1 line (the `# /…` heading only the injected body can
  contribute; the bare skill name is a substring of the prompt itself and
  proves nothing) or the run is **INVALID** (exit 3), not a graded failure.
- **Failure diagnosis seam.** `PROMPT_EVAL_KEEP_FAILED=1` preserves a failing
  or invalid run's transcript and work tree under the work base's `kept.*`
  (machine-local scratch; never recorded, never committed) — by default
  teardown leaves an assertion failure with nothing to inspect.
- **Injection seam.** `PROMPT_EVAL_NO_BARE=1` drops `--bare`: `--bare` was
  observed to suppress slash-command expansion entirely, so real skill
  injection needs a non-bare session. The trade is hermeticity — without
  `--bare` the operator's user settings, hooks, and CLAUDE.md load (the run
  measures skill + ambient config), and auth may fall to OAuth (verify the
  reported cost is non-zero or the budget caps cannot bind). The sentinel
  check remains the proof of injection either way.
- **pass^k gating.** All `k` runs must pass (default `k=3`); the loop
  early-exits on the first failing run. Before/after diet comparisons pair on
  the fixture identifier.
- **Bounded cost (R11).** Per-run `--max-budget-usd` / `--max-turns`, plus an
  optional suite-level `--suite-budget-usd` ceiling that aborts fail-closed.
- **Fail-closed dispositions (R12).** Budget-cap-hit counts as a failing run; a
  missing result line or an unparseable cost aborts fail-closed; a teardown or
  prune failure aborts fail-closed. Nothing is silently treated as a pass.
- **Artifact hygiene (REQ-C1.6).** A recorded result carries only the fixture
  identifier, the graded outcome, and cost — built by allowlist and re-verified
  to contain no machine-local path, username, or session id.

## Never in CI (D-8)

Evals cost tokens, gate nondeterministically, and need an API key that has no
place in a public repo's CI. The suite is **not** part of `mise run check` and
never runs in GitHub CI. `scripts/check-no-ci-evals.sh` (which *is* part of
`mise run check`) fails if any `eval:` task is wired into a workflow file, so the
invariant is enforced structurally, not by mere absence from the aggregate.
