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
   kickoff brief. Sign-off flips the spec Draft → Active. This is a human
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

`mise run check` runs the shell test suites (bash 3.2 floor), shellcheck, shfmt,
markdownlint, yamllint, the plugin-manifest validation, the doctrine
link-check, conventional-commit lint, the options-reference drift check, the
ledger structural-corruption guard over `tasks.md` snapshots, the
spec validator over `specs/`, and a secret scan. GitHub Actions runs the same
gate on every pull request. This is dev tooling only — planwright's **runtime**
scripts stay plain portable bash with no mise dependency.

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
Append one line to `specs/_observations/opportunities.md`
(`- <YYYY-MM-DD> [<repo>] <observation>`) and commit it within the same change.
Do not act on it in the current task; it is seed material for `/spec-draft`, the
log's canonical reader.

## Reporting issues

Open a GitHub issue describing the behavior, the expected behavior, and a
reproduction. For a doctrine or contract question, point at the relevant REQ /
D-ID in `specs/bootstrap/` so the discussion is anchored.
