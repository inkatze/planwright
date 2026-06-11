# Discovery Rigor

Validation Rigor confirms a finding is real. Discovery Rigor makes sure the
finding *list itself* is complete on the first pass. The failure mode it
prevents: a review surfaces a few items, the skill runs again later, and the
second pass returns valid findings that were not caused by the first pass's
fixes. Those findings could have been reported the first time; they were
silently pruned.

Any review workflow that generates findings (rather than only validating
pre-existing ones) applies this on its discovery pass.

Citations: REQ-D1.1.

## Lens checklist, no silent pruning

Walk every lens below, in order, before producing the finding list.
Severity-based self-pruning ("a bug was already found, the documentation nit
is not worth mentioning") is the exact failure mode to avoid: report findings
at every severity in the same pass.

1. Correctness, logic, edge cases (null, empty, max size, off-by-one,
   error paths)
2. Security (injection, auth, data exposure, secret handling, untrusted
   input)
3. Error handling and failure modes (what happens when this fails partway)
4. Performance (allocation, IO, complexity, hot paths)
5. Concurrency / state (race conditions, idempotency, ordering, retries)
6. Naming, readability, structure (only flag when the change under review
   worsens it; see [Refactor Instinct](refactor-instinct.md))
7. Documentation (docstrings, READMEs, specs, ADRs, config docs, doctrine
   and project-memory sections)
8. Tests / verification (coverage of new behavior, missing failing-case
   tests, brittle assertions)
9. Cross-file consistency (did the change break a documented invariant or a
   sibling pattern)

## Lens-coverage table (canonical output)

After walking the lenses, emit this table, one row per lens, before any
per-finding output. Empty lenses must show `none` with a one-line reason;
this is what makes silent pruning visible.

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness, logic, edge cases | `<count or "none">` | `<one-line summary or reason for none>` |
| Security | ... | ... |
| Error handling and failure modes | ... | ... |
| Performance | ... | ... |
| Concurrency / state | ... | ... |
| Naming, readability, structure | ... | ... |
| Documentation | ... | ... |
| Tests / verification | ... | ... |
| Cross-file consistency | ... | ... |

A lens may be marked `n/a` instead of `none` when it is genuinely
inapplicable to the change (the concurrency lens on a documentation-only
diff). `n/a` requires a one-line reason in the Notes column. Skipping a row
is not allowed.

## Tool-grounded discovery first

Before relying on judgment, run what the project ships: linters, formatters,
type checkers, static analyzers, complexity and duplication meters, dead-code
detectors, security scanners. Discover them through the project's CI
workflows, git-hook configuration, language-specific config files, and the
summary that planwright's SessionStart tool-discovery hook injects when
present.
Tool output is grounded; vibes are not. Cite the rule when flagging.

## Parallel lens fan-out (preferred for non-trivial diffs)

A single agent walking all lenses still self-prunes within its context
window. For diffs beyond a few hunks, spawn parallel read-only sub-agents
instead, one per lens, each with a narrow brief: find issues in this diff for
one lens only; be exhaustive within the lens; severity-pruning is forbidden;
if there are no findings, return `none` with a one-line reason. Pass the
shared tooling output to every sub-agent. The coordinator merges, dedupes (a
finding hitting two lenses gets one row with both lens labels), then runs the
self-critique pass. Skills that perform discovery specify when to fan out
versus run inline.

## Self-critique pass before reporting

After the lens walk (or fan-out merge) produces a finding list, do one more
pass: assume the list is incomplete, re-scan the diff specifically for what
feels under-represented, and add what turns up. This pass is mandatory. Its
cost is small; its payoff is that nobody has to re-run the skill to drain
second-pass findings.

## Proportionality

Rigor scales with stake and reversibility (see
[proportionality.md](proportionality.md)). A skill that scopes any part of
this doctrine (for example, running inline instead of fanning out on a
trivial diff) declares the scoping explicitly; silent scoping is
non-conforming.

Skills cite this document the same way they cite Validation Rigor. The
canonical lens list lives here so individual skills do not drift.
