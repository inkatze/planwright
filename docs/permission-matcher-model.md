# The permission-matcher model

planwright's worker deny list (`config/worker-settings.json`) is a set of Claude
Code `Bash(...)` glob rules. Glob rules are easy to write and easy to break
silently: a `:*` that lands mid-pattern never fires, a rule anchored at
end-of-string is evaded by one trailing flag, and a rule nobody asserts can be
deleted with a green suite. To make those failures mechanical rather than a
matter of careful reading, `tests/test-permission-matcher.sh` (and, for the
worker profile's `gh pr ready` entries, `tests/test-merge-currency-matrix.sh`)
asserts a fixture
table of real `git push` / `git commit` invocations against a **documented
re-implementation** of Claude Code's matcher, kept in
`tests/lib/permission-matcher.sh`.

This document is that re-implementation's contract: what it models, the version
it models, the sources it was built from, and — the part that matters most when
Claude Code changes — the boundaries and assumptions it does **not** settle.
guard-coverage D-4 makes this doc the single place a matcher divergence surfaces.

**The model is not the matcher.** The test verifies config-vs-model equivalence.
Real-matcher fidelity is a manual re-verify, carried as risk row 1 of
`specs/guard-coverage/kickoff-brief.md`.

## Modeled behavior version

| | |
| --- | --- |
| Claude Code CLI | **2.1.220** (`claude --version`, 2026-07-29) |
| Documentation snapshot | **2026-07-29** |
| Reference git | **2.55.0** (the differential checks in "Verified against real git") |

Re-verify on a Claude Code upgrade. The matcher is an undocumented-in-detail
implementation of a documented contract; treat every rule below as a snapshot.

### Sources consulted

- <https://code.claude.com/docs/en/permissions> — "Configure permissions": rule
  evaluation order, Bash rule wildcard semantics, the word-boundary form, the
  `:*` suffix equivalence, compound-command separators, wrapper stripping,
  leading-environment-assignment handling, and the standing warning that Bash
  patterns constraining arguments are fragile.
- <https://code.claude.com/docs/en/settings> — settings precedence, and the
  contrast that permission rules *merge* across scopes rather than override.
- `git commit -h`, `git push -h`, `git --help`, `git config` behavior on git
  2.55.0 — the argv spellings the fixture table has to cover.

## Modeled rules

Each rule is numbered so the test and the library can cite it.

**M1 — rule shape.** A command rule is written `Bash(<pattern>)`. Any other
rule shape (a bare tool name, `Read(...)`, `Edit(...)`) never matches a Bash
command and is ignored by the command matcher.

**M2 — whole-command glob.** `<pattern>` is matched against the **entire**
command string, anchored at both ends. `Bash(npm run build)` matches the exact
command `npm run build` and not `npm run build --watch`.

**M3 — wildcards anywhere.** `*` matches any sequence of characters, including
spaces, and may appear at the beginning, middle, or end. One wildcard can span
several arguments: `Bash(git * main)` matches `git checkout main`,
`git log --oneline main`, `git push origin main`, and `git merge main`.

**M4 — the word-boundary form.** When a pattern ends with a space followed by
`*`, that trailing wildcard enforces a word boundary: the prefix must be
followed by a space **or end-of-string**. `Bash(ls *)` matches `ls` and
`ls -la` but not `lsof`. Without the space there is no boundary constraint:
`Bash(ls*)` matches `lsof` too.

**M5 — the `:*` suffix.** A trailing `:*` is an equivalent spelling of a
trailing space-then-`*`, so `Bash(ls:*)` and `Bash(ls *)` match the same
commands. `:*` is
recognized **only** at the end of a pattern; anywhere else the colon is a
literal character, so `Bash(git:* push)` does not match `git push`.

**M6 — compound commands.** The command is split into subcommands on `&&`,
`||`, `;`, `|`, `|&`, `&`, and newlines, and a rule must match each subcommand
independently. A compound command is **denied** when any subcommand matches a
deny rule, and **allowed** only when every subcommand matches an allow rule.

**M7 — leading environment assignments.** A deny or ask rule matches *past* any
leading `VAR=value` assignment: `Bash(rm *)` in deny still matches
`FOO=bar rm -rf tmp/`. An allow rule strips only a built-in known-safe set,
which this model does not enumerate — see MB-2.

**M8 — evaluation order.** Rules are evaluated deny, then ask, then allow. The
first match in that order wins and specificity never reorders it, so a broad
deny cannot carry allowlist exceptions. When no rule matches, the call falls
through to the permission prompt; the model reports that outcome as `prompt`,
which in a headless worker means a stall, not a pass.

## Modeling boundaries

These are behaviors the real matcher has that the model deliberately does not
implement. Each entry states the **direction of the resulting error**. Two
directions matter, and they are not symmetric:

- *Under-predicting deny on a command the real matcher denies* is conservatism:
  the model under-claims protection, an expected-deny fixture row fails loudly,
  and no reader is told they are covered when they are not. MB-1 through MB-6 are
  all this kind.
- *Reporting allow for a command that really executes something dangerous* is a
  hole, not conservatism. **MB-7 is the only entry of this kind**, and it is
  flagged as such rather than filed alongside the others.

**MB-1 — wrapper stripping.** Claude Code strips a fixed set of leading
wrappers (`timeout`, `time`, `nice`, `nohup`, `stdbuf`, the `command` and
`builtin` builtins, zsh's `noglob`, and bare flagless `xargs`) before matching,
so `Bash(npm test *)` also matches `timeout 30 npm test`. The model does not
strip them. Direction: the model may report `prompt`/`allow` where the real
matcher, after stripping, reports `deny`. No fixture row uses a wrapped
spelling, so no expected-deny row depends on this.

**MB-2 — known-safe environment assignments for allow rules.** M7 is modeled for
deny and ask only. Allow matching runs against the unstripped command, so a
command with any leading assignment reports `prompt` rather than `allow`.
Direction: under-predicts allow.

**MB-3 — quoting.** Both the compound split (M6) and the pattern match (M2) are
quoting-unaware, as the real matcher's *patterns* are — the documentation's own
warning is that Bash patterns constraining arguments are fragile. A separator
inside a quoted argument (`git commit -m "a; b"`) splits in the model where the
real, shell-aware matcher would not. No fixture row uses that shape. The
converse — a *flag name* appearing inside a quoted commit message and being
matched as if it were a flag — is real behavior in both, and the fixture table
records it as the `overblock` class.

**MB-4 — built-in read-only commands.** Claude Code runs an unconfigurable set
of read-only commands (`ls`, `cat`, `git status`, ...) without a prompt
regardless of the allow list. The model knows nothing about that set. Direction:
under-predicts allow. Irrelevant to this guard: no `git push` or `git commit`
form is read-only.

**MB-5 — the PreToolUse auto-approve hook.** `config/worker-settings.json` also
wires `scripts/worker-command-guard.sh`, which can auto-approve additional
known-safe shapes. The model covers permission **rules** only, so a `prompt`
outcome in the fixture table means "no rule matched", not necessarily "the
worker stalls". The hook can never turn a `deny` into anything else (M8, and the
hook is allow-only by construction), so this boundary cannot mask a missing
deny.

**MB-6 — tool-name globs, non-Bash tools, and settings precedence.** Out of
scope. The fixture table asserts one settings fragment in isolation.

**MB-7 — command and process substitution.** M6 splits on the operators the
documentation enumerates. It does **not** reach into `$(...)`, backticks, or
`<(...)`, so a command nested inside one is invisible to the model:
`git status "$(git push origin main)"` reports `allow`, because the outer
read-only command matches an allow rule and the nested push matches nothing.
Direction: this is the one boundary that errs toward **allow on a command that
really executes**, so it is the boundary to treat as a hole rather than as
conservatism. Two things are unknown and neither can be settled from the
documentation: whether the real matcher extracts substitutions (its separator
list does not mention them, but it is shell-aware and may), and whether it
instead classifies such a command as unparseable and prompts. The fixture table
carries the case as a `residual` row recording the model's outcome and this
uncertainty. What does stop it today is the enforcement layer, not the glob
layer: `githooks/pre-push` rejects a `refs/heads/main` update however the push
was spelled. Re-check against the real matcher on a Claude Code upgrade; the
worker-settings `_about` prose formerly asserted subshell coverage flatly, which
this entry corrects.

## Unsettled assumptions

Unlike the boundaries above, these are places where the documentation does not
state the answer and the model has had to pick one. They are the first things to
re-check when a Claude Code upgrade changes fixture outcomes.

**MA-1 — `*` matches the empty string.** The documentation says a wildcard
"matches any sequence of characters including spaces" but never says whether the
empty sequence counts. The model treats `*` as zero-or-more, which is the
gitignore and shell-glob convention and is what the shipped deny list was
evidently written against: `Bash(git push * --force*)` exists precisely to catch
`git push origin --force`, where the trailing `*` must match nothing.

If a future matcher required one-or-more, every deny rule whose **trailing**
wildcard has nothing to consume would stop firing — the `* --force*`,
`* -f*`, `* --mirror*`, `* --all*`, `* --undo*`, `* --amend*`, and `* -n*`
family, for flags that appear at the very end of a command. The fixture rows
that would flip are the flag-after-argument rows (for example
`git push origin --force`, `git commit -m "wip" --amend`,
`git commit -m "wip" -n`, `gh pr ready 123 --undo`). Note the shape of the
exposure: the *leading-position* spelling of each of those flags is covered by a
separate `:*` boundary rule that does not depend on MA-1, so a wrong MA-1
narrows coverage rather than removing it.

MA-1 is the reason the deny list keeps redundant rules. Where a `:*`
boundary rule and a bare-`*` rule cover the same command by different
mechanisms, both are kept, and the redundancy is declared with its reason in the
test's `REDUNDANT_BY_DESIGN` table rather than left to be discovered.

**MA-2 — case sensitivity.** The documentation states that PowerShell rule
matching is case-insensitive and says nothing about Bash, which implies
case-sensitive. The model matches case-sensitively, and git config keys are
case-insensitive (verified below), so an arbitrary casing such as
`Core.HooksPath` slips past a literal `core.hooksPath` glob. The deny list
carries the canonical and all-lowercase spellings, and the global-option-prefix
rules (see "How the deny list is shaped") close the casing gap for every
invariant-bearing subcommand regardless of spelling, because they key on the
leading `git -` rather than on the config key. What remains is the **persistent**
form: `git config Core.HooksPath /dev/null` starts with `git config`, so no
global-option rule sees it, and the case-sensitive config globs miss the casing.
No glob and no hook reaches that one; it is an accepted residual, carried as a
`residual` fixture row. If Bash matching turns out to be case-insensitive, the
residual closes on its own and the lowercase rules become redundant.

## Verified against real git

The fixture table's argv spellings are not guesses. Checked against git 2.55.0
on 2026-07-29:

- **`core.hooksPath` config keys are case-insensitive.** Setting
  `core.hooksPath` and reading `core.hookspath` or `CORE.HOOKSPATH` returns the
  same value. This is what makes MA-2 a real residual rather than a theoretical
  one.
- **`git --config-env=<name>=<envvar>` is real** and resolves config from the
  environment (`git --config-env=core.hooksPath=NOPE` fails with
  `missing environment variable 'NOPE' for configuration 'core.hooksPath'`), so
  it is a genuine hooksPath-injection spelling and is denied categorically.
- **`--hooks-path` does not exist** on `git commit`, `git push`, or
  `git config` in git 2.55 (`error: unknown option`). The categorical
  `Bash(git * --hooks-path*)` deny that guard-coverage Task 1 calls for is
  therefore forward-compatibility only; the fixture row records it as such
  rather than implying git accepts the flag today.
- **`-n` is `--no-verify` for `git commit`** but `--dry-run` for `git push`.
  The `-n` denies are scoped to `git commit` for exactly that reason: a
  `git push -n` deny would block harmless dry runs.
- **`--fixup` accepts both `--fixup <commit>` and `--fixup=<commit>`**, and the
  `amend:` / `reword:` prefixes produce `amend!` subjects. `--squash` likewise
  accepts the `=` form. The `=` spellings are why the deny list needs
  `Bash(git commit --fixup*)` and `Bash(git commit --squash*)` alongside the
  `:*` boundary rules — a `:*` rule requires a space and misses `=`.
- **`--force-with-lease[=<refname>:<expect>]` and `--force-if-includes`** are
  both real, which is why `Bash(git push --force*)` is carried in addition to the
  two `:*` force rules.

## How the deny list is shaped

Two idioms, chosen deliberately, and the distinction matters:

- **Flags use the bare-`*` form** (`Bash(git push * --force*)`). A flag name is
  a closed token, so the only over-block risk is the flag name appearing inside
  a quoted argument — a fail-safe cost the fixture table records as `overblock`
  rows.
- **Ref destinations use the boundary form** (`Bash(git push * main *)`). Branch
  names commonly *extend* `main` (`main-fix`, `maintenance`), and the boundary
  form is what keeps them pushable. `Bash(git push * main*)` would deny them.
  Fixture rows pin both directions.

And one rule shape that exists for a reason worth stating, because it is not
obvious from reading the rule:

- **Global-option prefixes get their own family** (`Bash(git -* push*)`,
  and the same for `commit`, `merge`, `rebase`, `reset`, `filter-branch`,
  `filter-repo`). Every other rule anchors on `git push` or `git commit` at the
  start of the command, so *any* git global option in front of the subcommand
  slipped past all of them: `git -C . push --force origin topic` and
  `git -c a=b rebase -i HEAD~2` matched nothing. git has a long and growing list
  of global options (`-C`, `-c`, `--git-dir`, `--work-tree`, `--namespace`,
  `--exec-path`, `--no-pager`, `--bare`, `--literal-pathspecs`, …), so
  enumerating them would be a treadmill. Keying on the leading `git -` covers
  the whole class in one rule per subcommand, and it cannot be triggered by
  message content, because the pattern is anchored at position 0 and a normal
  `git commit -m "…"` does not start with `git -`. Accepted cost: a *read-only*
  global-option-prefixed command that happens to contain a later space-prefixed `push` or
  `commit` token (`git -C /other log -- commit.md`) is denied. Fail-safe, rare,
  and recorded rather than narrowed.

A caveat on the deny list as a whole: it is **best-effort defense-in-depth**, and
`doctrine`-level enforcement of the never-push-main and never-amend invariants is
the `githooks/` backstop (guard-coverage D-2), not these globs. Where the fixture
table records a `residual`, that is the layer doing the work.

## Changing any of this

1. Change the deny list and the fixture table in the same commit. The test's
   dead-rule pass fails on a rule no row exercises, and its mutation pass fails
   on a rule that no row depends on, so neither an untested rule nor a
   deletable one can ship.
2. If a change is driven by new Claude Code behavior, update the **modeled
   behavior version** and the affected M/MB/MA entry here first. The library and
   the test both cite this doc; a model change with no doc change is the drift
   D-4 exists to prevent.
3. Widening the **allow** list is a permissions widening, not a guard change.
   It needs human sign-off and does not belong in a deny-glob commit.
