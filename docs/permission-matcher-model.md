# The permission-matcher model

planwright's worker profile (`config/worker-settings.json`) is a set of Claude
Code `Bash(...)` glob rules plus `Read(...)` and `Edit(...)` path rules. Glob
rules are easy to write and easy to break
silently: a `:*` that lands mid-pattern never fires, a rule anchored at
end-of-string is evaded by one trailing flag, and a rule nobody asserts can be
deleted with a green suite. To make those failures mechanical rather than a
matter of careful reading, `tests/test-permission-matcher.sh` (and, for the
worker profile's `gh pr ready` entries, `tests/test-merge-currency-matrix.sh`)
asserts a fixture
table of real commands, and a second table of file-tool calls, against a
**documented re-implementation** of Claude Code's matcher, kept in
`tests/lib/permission-matcher.sh`. Every deny rule and every allow rule needs a
row that exercises it.

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
| Claude Code CLI | **2.1.314** (`claude --version`, 2026-11-01) |
| Documentation snapshot | **2026-11-01** |
| Reference git | **2.55.0** (the differential checks in "Verified against real git") |

Re-verify on a Claude Code upgrade. The matcher is an undocumented-in-detail
implementation of a documented contract; treat every rule below as a snapshot.

### Sources consulted

- <https://code.claude.com/docs/en/permissions> — "Configure permissions": rule
  evaluation order, Bash rule wildcard semantics, the word-boundary form, the
  `:*` suffix equivalence, compound-command separators, deny and ask rules
  reaching nested commands, wrapper stripping,
  leading-environment-assignment handling, the `Read`/`Edit` path pattern
  syntax, `Write(path)` rules never matching, and the standing warning that
  Bash patterns constraining arguments are fragile.
- <https://code.claude.com/docs/en/permission-modes> — "Protected paths": the
  paths whose writes no allow rule pre-approves.
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
"Subcommand" includes the nested ones M9 reaches.

**M7 — leading environment assignments.** A deny or ask rule matches *past* any
leading `VAR=value` assignment: `Bash(rm *)` in deny still matches
`FOO=bar rm -rf tmp/`. An allow rule strips only a built-in known-safe set,
which this model does not enumerate — see MB-2.

**M8 — evaluation order.** Rules are evaluated deny, then ask, then allow. The
first match in that order wins and specificity never reorders it, so a broad
deny cannot carry allowlist exceptions. When no rule matches, the call falls
through to the permission prompt; the model reports that outcome as `prompt`,
which in a headless worker means a stall, not a pass.

**M9 — nested commands.** The documentation states that deny and ask rules
"apply when any subcommand matches them, including a command nested inside a
subshell, a command substitution, or a control-flow body such as a `for`
loop". The model therefore reaches, recursively: a subshell `( … )`, a brace
group `{ …; }`, a command substitution `$( … )` or backticks, a process
substitution `<( … )` or `>( … )`, a function body, and the bodies and
conditions of `for`, `while`, `until`, and `if`/`elif`/`else`. A `for` or
`case` head, or a closing word followed by a redirect (`done < <(…)`), runs
no command of its own, but a substitution in its words does. Grouping is
read with quoting: nothing groups inside single quotes, and inside double
quotes only `$(` and backticks open a nested command. Separators inside
quotes, parentheses, or backticks do not split the outer command; the nested
text is split on its own. A subcommand that carries a substitution is
matched with it in place, then each nested command is matched as well, so
allow still needs every one of them. `$(( … ))` reads as a substitution
holding a group, which can only add a subcommand to check. Past a fixed
nesting depth, or when a quote, parenthesis, or backtick never closes, the
model stops reading structure and reports a subcommand no allow rule
matches, so a command it never inspected cannot come out allowed.

Deny and ask rules are also swept over the command's *atoms*: the text split
on every separator and every parenthesis and backtick, quotes ignored, each
with its control-flow words dropped. A nested command the structured reading
misses still surfaces as an atom, so it is denied however it is quoted or
grouped. The cost is the `overblock` kind: a deny-matching command written
inside a quoted argument is denied too.

**M10 — path rules.** `Read(<pattern>)` and `Edit(<pattern>)` rules use
gitignore syntax. `//p` is absolute, `~/p` is under the home directory, `/p`
is relative to the settings source (for a `--settings` file, the file's own
directory, which is why the worker profile never uses that anchor), and `p`
or `./p` is relative to the working directory. A bare name with no slash
matches at any depth under its anchor; so does a single directory segment
followed by `/**`, in deny and ask rules only. `*` stays inside one path
segment and `**` spans directories. A Read deny also blocks the edit tools on
the same path. A bare `Read`, `Edit`, `Write`, or `NotebookEdit` entry
governs that tool on every path: in deny it removes the tool, in allow it
admits every call; a bare `Edit` deny or ask covers the other edit tools as
an `Edit(...)` rule does.

**M11 — `Write(path)` rules never match.** Claude Code checks file
permissions against `Edit(path)` and `Read(path)` rules only; a `Write(...)`
or `NotebookEdit(...)` path rule is accepted and never matches. `Edit` rules
apply to every built-in tool that edits files, the Write tool included, so a
path the Write tool must not reach takes an `Edit(...)` deny.

## Modeling boundaries

These are behaviors the real matcher has that the model deliberately does not
implement. Each entry states the **direction of the resulting error**. Two
directions matter, and they are not symmetric:

- *Under-predicting deny on a command the real matcher denies*, or allow on one
  it allows, is conservatism: the model under-claims protection or coverage,
  an expected row fails loudly, and no reader is told they are covered when
  they are not.
- *Reporting allow for a command that really executes something dangerous* is a
  hole, not conservatism. No entry below is this kind.

**MB-1 — wrapper stripping.** Claude Code strips a fixed set of leading
wrappers (`timeout`, `time`, `nice`, `nohup`, `stdbuf`, the `command` and
`builtin` builtins, and zsh's `noglob`) before matching,
so `Bash(npm test *)` also matches `timeout 30 npm test`. The model does not
strip them. Direction: the model may report `prompt`/`allow` where the real
matcher, after stripping, reports `deny`. No fixture row uses a wrapped
spelling, so no expected-deny row depends on this.

**MB-2 — known-safe environment assignments for allow rules.** M7 is modeled for
deny and ask only. Allow matching runs against the unstripped command, so a
command with any leading assignment reports `prompt` rather than `allow`.
Direction: under-predicts allow.

**MB-3 — quoting.** The compound split (M6) reads quotes and backslash
escapes, so a separator inside a quoted argument (`git commit -m "a; b"`)
does not split, as in the shell-aware real matcher. The pattern match (M2) is
quoting-unaware, as the real matcher's *patterns* are — the documentation's
own warning is that Bash patterns constraining arguments are fragile. So a
*flag name* inside a quoted commit message is matched as if it were a flag,
which is real behavior in both, and the fixture table records it as the
`overblock` class; M9's atom sweep adds the same cost for a command written
inside a quoted argument. Direction: over-predicts deny only.

**MB-4 — built-in read-only commands.** Claude Code runs an unconfigurable set
of read-only commands (`ls`, `cat`, `git status`, ...) without a prompt
regardless of the allow list. The model knows nothing about that set. Direction:
under-predicts allow: a `prompt` row for a verb in that set (`cat`) may
run unprompted for real, so such a row records that no profile rule names the
verb, not that the call stalls.

**MB-5 — the PreToolUse auto-approve hook.** `config/worker-settings.json` also
wires `scripts/worker-command-guard.sh`, which can auto-approve additional
known-safe shapes. The model covers permission **rules** only, so a `prompt`
outcome in the fixture table means "no rule matched", not necessarily "the
worker stalls". The hook can never turn a `deny` into anything else (M8, and the
hook is allow-only by construction), so this boundary cannot mask a missing
deny.

**MB-6 — tool-name globs, other tools, and settings precedence.** Out of
scope. The fixture tables assert one settings fragment in isolation, and the
file-tool path rules (M10) are the only non-Bash rules modeled. The tower
profile's `mcp__*__` deny entries rely on deny-rule tool-name globs, which
this model does not cover; `tests/test-tower-settings-hook-wiring.sh` checks
them against a shell-glob stand-in instead. Bare tool-name allow entries other
than the file tools (`Grep`, `Glob`) are declared outside the model by name in
the test.

**MB-7 — `case` statements.** The structured reading does not parse a
`case` statement's arms; it reports a subcommand no allow rule matches in
their place. Deny and ask still reach a command in an arm through the atom
sweep (M9). Direction: under-predicts allow.

**MB-8 — protected paths and symlinks.** Claude Code never auto-approves a
write to a protected path (`.git`, `.claude`, `.envrc`, `lefthook.yml`,
`lefthook.yaml`, `.lefthook.yml`, `.lefthook.yaml`, the `--settings` file,
and others the permission-modes page lists) in the default mode, whatever the
allow list says, and it checks a deny rule against both the requested path
and the file a symlink resolves to. The model sees neither: it reports
`allow` where the real tool prompts, and judges only the path as given,
without collapsing `//`, `/./`, or `/../` segments. Direction: under-claims
protection. "What the
path rules close" below says why the worker profile denies protected paths
anyway.

**MB-9 — redirect targets and recognized file commands.** Claude Code checks
an output redirect's target against the Edit rules, an input redirect's
against the Read rules, and applies Read and Edit denies to the file
commands it recognizes (`cat`, `head`, `tail`, `sed`, `tee`). The model
matches Bash rules against the command text only. Direction: under-predicts
deny (`ls > mise.toml` and `cat /proc/1/environ` report `allow` or `prompt`
where the real matcher denies).

**MB-10 — shell lexing the model does not reproduce.** ANSI-C quoting
(`$'…'`), here-documents, comments, line continuations, and the escapes a
backtick substitution undoes (`` \` ``, `\$`) can each move where a quote or
a command begins. The model does not lex them: a command using any of them is
never reported allowed, and its deny sweep also reads the text with line
continuations joined. Direction: under-predicts allow.

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
`* -f*`, `* --mirror*`, `* --all*`, `* --undo*`, and `* -n*`
family, for flags that appear at the very end of a command. The fixture rows
that would flip are the flag-after-argument rows (for example
`git push origin --force`, `git commit -m "wip" -n`,
`gh pr ready 123 --undo`). Note the shape of the
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
residual closes on its own and the lowercase rules become redundant. The
documentation is as silent on path rules, and the model matches those
case-sensitively too.

**MA-3 — a bare name does not cover what lies below it.** In gitignore a
pattern that matches a directory also excludes its contents; the permission
documentation shows bare names only on files (`Read(.env)`). The model
matches a bare name against the path itself, never its descendants, so the
profile spells every directory it closes with an explicit `/**` rule beside
or instead of the bare name. If Claude Code does extend a bare name to a
directory's contents, those `/**` rules become redundant, not wrong.

**MA-4 — word spacing is matched as written.** The documentation does not say
whether a pattern's single space matches a tab or a run of spaces, or whether
a redirect glued to a word (`main>/dev/null`) is read apart from it. The model
matches the subject text literally, so each of those spellings slips past a
deny glob whose words are space-separated. The fixture table carries them as
`residual` rows naming the layer that still refuses them. If the real matcher
reads parsed words, those rows flip to `deny` and close on their own.

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
  accepts the `=` form. The `=` spellings are why the tower profile needs
  `Bash(git commit --fixup*)` and `Bash(git commit --squash*)` alongside the
  `:*` boundary rules — a `:*` rule requires a space and misses `=`.
- **git takes any unique prefix of a long option** (gitcli(7)): `git commit
  --am` amends, `--sq=<c>` squashes, `--fix=<c>` fixes up, `git push --mi`
  mirrors, `--al` pushes every branch, and `--no-veri` skips the hooks
  (measured on git 2.53). Each flag deny is therefore also carried at that
  shortest prefix; the full-spelling rules stay as the explicit spellings. The
  policy guard reads the same prefixes for the acts it decides.
  `--branches` is git's alias of `--all`, and the matching refspec
  (`git push origin :`) pushes every branch the remote shares, so both are
  denied beside `--all`.
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
  and the same for `commit`, `reset`, `filter-branch`, `filter-repo`). Every
  other rule anchors on `git push` or `git commit` at the
  start of the command, so *any* git global option in front of the subcommand
  slipped past all of them: `git -C . push --force origin topic` matched
  nothing. git has a long and growing list
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
the clone-level enforcement of the never-push-main and never-amend invariants is
the `githooks/` backstop (guard-coverage D-2), not these globs. That backstop
still refuses every amend and rebase in a clone that wires it, whatever
`unpushed_rewrite` resolves to. Where the fixture table records a `residual`,
another layer is doing the work.

## What the worker profile leaves to the policy guard

A profile is read once at launch and its deny wins over every allow, so a
profile deny can never follow a policy knob: it would refuse an act the
resolved policy permits (human-gates D-9). The worker profile therefore holds
only what no value can lift (the PR merge and the re-draft, force-push, writes
to main, `master`, or a spec branch, the hard reset and the history filters,
the hook bypasses, and the MCP names), and the acts
a value can grant a worker left the deny list with human-gates Task 6:

- the base merge (`git merge`, `git pull`, and their `git -*` global-option
  spellings), granted by `worker_base_merge`;
- the never-pushed rewrites (amend, squash, fixup, rebase, at every prefix git
  accepts, and `git -* rebase*`), granted by `unpushed_rewrite`.

`scripts/policy-guard.sh`, wired into the same profile with the `worker` tier,
is the deny-emitting layer for those acts: it reads the knob, the session's
unit branch, the merge source, and (for a rewrite) the refreshed upstream, and
refuses what the value or the facts forbid. The fixture rows for those
spellings are `residual` rows: the glob layer leaves them to the guard. A
policy-permitted spelling that the allow list does not name reaches the
permission prompt; widening the allow list to admit it is a separate,
signed-off change. `Bash(git -* commit*)` stays, since it also refuses the
global-option spellings of the commit hook bypasses; the plain `git commit`
spelling of an amend is the one the guard decides. That leaves one admitted
gap, kept on purpose to fail closed: `git -C <dir> commit --amend` (and any
other global-option spelling of an amend) stays denied under every
`unpushed_rewrite` value, so a worker granted the rewrite amends with plain
`git commit --amend`. The tower profile keeps
its merge, pull, rebase, and amend-family denies, since no value grants the
tower a merge or a rewrite; the global-option spellings it never carried are
refused there by the policy guard, which is wired into the tower profile too.

## What the path rules close

The worker profile allows the `Read`, `Edit`, and `Write` tools everywhere, and
those calls never reach the worker command guard. So the paths the guard's
own-branch arm refuses by name, the profile refuses to the file tools with
`Edit(...)` denies, and the one read the guard refuses gets a `Read(...)`
deny:

- **Execution-bearing paths** (worker-permission-ergonomics REQ-F1.6): `.git`
  wherever it sits (the worktree's `.git` entry and the common git directory,
  default hooks included), the repo-tracked hooks directories `githooks/` and
  `.githooks/`, the worktree's `.claude/`, and the mise, lefthook, direnv, and
  tool-version config names the guard refuses (`scripts/worker-command-guard.sh`,
  `ob_excluded_name`, owns the list). An adopter whose `core.hooksPath` names
  another directory adds an `Edit(<dir>/**)` deny of its own.
- **The guard's trust inputs** (REQ-G1.8): the launcher's session records
  (`session-records/*.record` under any fleet home) and the overlay config
  files the policy resolves through (`planwright.yml` and
  `planwright.local.yml`, wherever they sit).
- **Other processes' environments** (REQ-E1.6): `/proc/<pid>/environ` and
  `/proc/<pid>/task/<tid>/environ`. The Read tool cannot read the worker's own
  `/proc/self/environ` either; `env` and `printenv` still print it.

Every rule but one is anchored at the filesystem root (`//`), never at the
settings file, whose directory is the plugin's `config/` (M10). Root-anchoring
matters because mise and direnv read the config of every directory above the
one they run in: a worktree under its primary checkout picks up the
primary's `mise.toml` and `mise.local.toml`, and a rule relative to the
worktree would leave those open. The worktree's own `.claude/` is the
exception, matched relative to the working directory on purpose: a worktree
usually sits under its primary checkout's `.claude/worktrees/`, and a
root-anchored `.claude` rule would refuse every file the worker edits. The
same holds for the root-anchored directory rules: a worktree checked out
beneath a directory named `.config`, `mise`, `.mise`, a hooks directory, or a
lefthook directory (a dotfiles checkout under `~/.config`, say) is refused
every file-tool write, so such a repository is checked out elsewhere for
workers.

The guard matches these names case-insensitively; the globs are
case-sensitive (MA-2), so on a case-insensitive filesystem a recased
spelling reaches the file tools. Writes the guard refuses elsewhere outside
the worktree are not mirrored here: the file tools still reach them, which
includes an installed planwright root when it is not under `~/.claude`.

Claude Code already protects `.git`, `.claude`, `.envrc`, and the YAML
lefthook config files (MB-8), and the overlays under `~/.claude` with them, but
protection means a prompt, which stalls a headless worker, and its list is
version-specific. A deny refuses outright and holds across versions, so
those paths keep their rules. The mise config, the hooks directories, the
local and non-YAML lefthook config, the session records, and repo-side
overlays are not protected at all.

## Changing any of this

1. Change the deny list and the fixture table in the same commit. The test's
   dead-rule pass fails on a rule no row exercises, and its mutation pass fails
   on a rule that no row depends on, so neither an untested rule nor a
   deletable one can ship. Each path rule must be the only rule blocking at
   least one row of the path fixture table, which covers both checks.
2. If a change is driven by new Claude Code behavior, update the **modeled
   behavior version** and the affected M/MB/MA entry here first. The library and
   the test both cite this doc; a model change with no doc change is the drift
   D-4 exists to prevent.
3. Widening the **allow** list is a permissions widening, not a guard change.
   It needs human sign-off and does not belong in a deny-glob commit. Each
   new allow rule needs a fixture row showing what it admits (the allow
   coverage pass fails otherwise), and the static set names no verb that
   prints an arbitrary path's content and no verb or `git` subcommand with a
   file-writing or program-running form (worker-permission-ergonomics
   REQ-G1.1). The test asserts the named exclusions and refuses any `git`
   subcommand outside the list it has been reviewed for, so a new one gets
   its write and execution forms checked there first.
