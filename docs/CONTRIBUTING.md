# Contributing to planwright

planwright is [MIT-licensed](../LICENSE) and built **through its own pipeline**:
it is the founding spec (`specs/bootstrap/`) executing itself. Contributions
follow the same discipline the framework applies to its own work. This doc is
the contribution model.

## License and inbound terms

By contributing you agree your contributions are licensed under the project's
[MIT license](../LICENSE) (inbound = outbound). Keep changes free of secrets,
credentials, internal hostnames, or sensitive operational detail — committed
artifacts (specs, briefs, the observations log, PR bodies) are held to the same
data-hygiene bar, and CI runs a secret scan.

## Two sizes of change

**Small, self-contained fixes** (a typo, a broken link, a shellcheck nit, a doc
clarification): open a pull request directly. Keep it scoped, make CI green, and
write a conventional-commit title.

**Anything that changes behavior, doctrine, or contracts** goes through the
spec-driven pipeline rather than a freehand PR, because planwright's accuracy is
bounded by spec quality:

1. **`/spec-draft <feature>`** — elicit the four-file bundle (`requirements.md`,
   `design.md`, `tasks.md`, `test-spec.md`) at Status `Draft`. Run fold
   detection first; extend an existing spec instead of spinning a duplicate.
2. **`/spec-kickoff <spec>`** — walk it to mutual understanding and sign off the
   kickoff brief. Sign-off flips the spec Draft → Ready (executable, not yet
   started); the first dispatch derives Ready → Active. This is a human
   control; there is no bypass.
3. **`/orchestrate` + `/execute-task`** — the framework advances tasks
   test-first, runs full CI, converges via `/polish`, and opens **draft** PRs.
4. **Review and merge** — a human reviews the draft PR, flips it to ready, and
   merges. planwright never auto-merges.

If you are unsure which size your change is, draft a spec — the cost is low and
the comprehension pass usually pays for itself.

## Where things live

| Layer | Home | What goes here |
| --- | --- | --- |
| Doctrine (rules) | [`doctrine/`](../doctrine/) | The rigor docs, finding categorization, engineering doctrine, the spec-format meta-spec. **General** rules only. |
| Skills | `skills/<name>/SKILL.md` | The pipeline skills. Procedure, not doctrine — skills cite doctrine, they do not restate it. |
| Scripts | [`scripts/`](../scripts/) | Portable bash entry points (validator, resolver, hooks, checks). Bash 3.2 + BSD tooling, **no fish/mise/tmux/Ansible** (REQ-K1.5). |
| Config | [`config/defaults.yml`](../config/defaults.yml) | Tracked defaults. Every option must have an [options-reference](options-reference.md) entry or CI fails. |
| Tests | `tests/*.sh` | One shell test suite per script, run under `/bin/bash`. |
| Specs | `specs/<feature>/` | The four-file bundles, including planwright's own. |

**Do not encode project- or team-specific style into core `doctrine/`.** That
is what the customization-overlay seam is for (see
[getting-started.md §4](getting-started.md)); baking local preferences into core
makes it less general for everyone and pollutes the upstream observation stream.

## The quality gate

Everything must pass the same gate CI enforces:

```bash
mise install        # once, to pin the toolchain
mise run check      # the full local equivalent of the CI gate
```

`mise run check` runs, in one pass:

- the shell test suites (bash 3.2 floor);
- shellcheck, shfmt, markdownlint, yamllint, and the plugin-manifest validation;
- conventional-commit lint and a secret scan;
- the doctrine link-check and the doctrine-index bijection check;
- the options-reference drift check, which also tethers `docs/fleet.md`'s knob
  defaults to `config/defaults.yml`;
- the ledger structural-corruption + duplicate-Status guard over `tasks.md`
  snapshots;
- the spec validator over `specs/`, the anchor-freshness guard over every
  signed bundle, the hook-backstop wiring check, and the purged-identifier
  guard (see below).

GitHub Actions runs the same gate on every pull request. This is dev tooling
only — planwright's **runtime** scripts stay plain portable bash with no mise
dependency.

### Purged identifiers

A handful of identifiers were removed from this history deliberately, and
`check:purged-identifiers` keeps them out — of the tracked tree, of commit
messages at write time via `githooks/commit-msg`, and of a PR's whole commit
range via a CI step for the clones that hook never runs in. It compares
SHA-256 over normalized text, so nothing readable is committed and a match
reports its location without echoing what it matched. The normalization rules,
the shapes it does and does not catch, and the stdin-only provisioning path
are in [purged-identifier-guard.md](purged-identifier-guard.md).

### Test timing, measured out of gate

`mise run test` runs the suite N files at a time, so its per-file numbers
measure contention rather than each file's own cost. When you need the honest
per-file figure — sizing a `check:test-time` budget, or deciding whether a file
has grown into a straggler — use the instrument instead:

```bash
scripts/measure-test-time.sh              # whole suite, serial, best of 3
scripts/measure-test-time.sh --repeats 1  # one pass, when you just want a ranking
```

It runs each `tests/*.sh` file on its own and reports the **minimum** of N runs
(the noise floor: jitter and neighbour load only push a sample up) alongside
that file's emitted verdict count. Ranked slowest-first, with suite totals.

It is an instrument, **not** a gate: never add it to `mise run check`. A serial
best-of-N pass over the whole suite far exceeds the gate's 15-minute budget, and
re-measuring inside a saturated job would perturb the numbers being measured.
On CI it runs as the separate opt-in `test-timing` workflow — add the
`measure-test-time` label to a PR, or dispatch it from the Actions tab. Only the
labelling re-triggers it: pushing further commits to an already-labelled PR does
not re-measure, so remove and re-add the label when you want a number for the
new head.

### The git hook backstop

The hard history invariants (never push `main`, never amend, squash, fixup,
or rebase) are enforced repo-side by the tracked hooks in
[`githooks/`](../githooks/). Wire them once per clone:

```bash
scripts/wire-githooks.sh   # sets core.hooksPath=githooks for the whole clone
```

`core.hooksPath` is clone-global: one wiring covers every worktree of the
clone, and the hooks no-op cleanly on a checkout whose branch predates them.
`mise run check` includes `check:githooks`, which fails loudly on an unwired
or half-wired clone but never wires anything itself; CI wires explicitly and
then verifies. The hooks bind humans too, not just agent sessions, and are
accident-catchers with an honestly stated boundary, not tamper-proofing:
`--amend` combined with `-m`/`-F` carries no client-hook signal and is
covered by the worker deny globs instead. The deliberate, human-only
bypasses, per `githooks(5)`: `--no-verify` skips the `pre-push` and
`commit-msg` hooks but does not suppress `prepare-commit-msg` (a deliberate
amend — rare, and never on planwright branches — means `--amend -m`/`-F` or
temporarily unsetting `core.hooksPath`), and `git rebase --no-verify`
bypasses `pre-rebase`. One caution inherited from tracked hooks: on an
untrusted fork checkout, unset `core.hooksPath` before running covered git
commands, since the checkout's own hook files would execute locally.

### The anchor-freshness mirror at commit time

`scripts/check-anchor-freshness.sh` is the standing guard over spec content
anchors: for every signed (non-Draft, non-terminal) bundle it re-computes the
anchor its kickoff brief records, and it flags an edit to anchored content that
carries no dated `## Changelog` entry. `mise run check` runs it whole-corpus,
and that CI run is the normative gate.

The same script also runs as a `pre-commit` mirror, so you hear about drift
while committing rather than one push later. It is wired through the tracked
hooks above rather than through `lefthook install`, which would overwrite them:
[`githooks/pre-commit`](../githooks/pre-commit) dispatches to `lefthook run
pre-commit`, and [`lefthook.yml`](../lefthook.yml) scopes the job to commits
that stage `specs/**` — a commit touching no spec pays no guard latency. So
there is **no separate install step**: `scripts/wire-githooks.sh` plus
`mise install` (which pins lefthook) is the whole setup, and the mirror is
best-effort — without lefthook on `PATH` the hook is a clean no-op and your
commit proceeds.

The mirror reads your **working tree**, not the staged index. So it can pass at
commit time and still fail in CI if you stage an anchored edit but leave its
`## Changelog` entry unstaged — CI judges the committed tree. Commit spec
bundles whole and the two agree; `mise run check` is the answer either way.

If the guard reports an anchor mismatch on a bundle you edited, the remedy
depends on the edit: an expression-only one takes the dated `## Changelog`
entry plus a marked `Class: expression-only` self-re-anchor entry in the same
commit; a meaning-class one goes back through `/spec-kickoff`. An entry
recorded before the 2026-07-26 header-`**Status:**` exclusion (or with the
interim whole-file form) mismatches over content nobody edited and takes the
one-time self-re-anchor described in `doctrine/spec-format.md`.

### Commit and PR conventions

- **Conventional commits** (`type(scope): subject`) — enforced on commits ahead
  of `origin/main` and on the PR title.
- **New commits only.** Never force-push, amend, squash, or rebase a planwright
  branch (REQ-J1.4); history is append-only.
- **Branch naming** follows `planwright/<spec>/task-<ids>` so the
  `tasks-pr-sync` hook can map a PR to its task. See
  [conventions.md](conventions.md).
- **Test-first** for behavior changes: write the failing test, confirm it fails
  for the right reason, then implement to green.

## Seeding ideas you are not acting on

Found something out of scope while working — complexity growth, an outdated
pattern, a newly available dependency feature, an uncatalogued decision domain?
Record it as its own observation fragment through the shared helper:
`scripts/obs-record.sh --slug <topic> --scope <repo> --text '<observation>'`
composes the one-line entry form for you and writes one fragment under
`specs/_observations/entries/` (created on demand). Commit the fragment within
the same change, and surface a non-zero helper exit rather than dropping the
observation. Do not act on it in the current task; it is seed material for
`/spec-draft`, the accumulator's canonical reader. Render the chronological
view any time with `mise run obs:log`.

## Reporting issues

Open a GitHub issue describing the behavior, the expected behavior, and a
reproduction. For a doctrine or contract question, point at the relevant REQ /
D-ID in `specs/bootstrap/` so the discussion is anchored.
