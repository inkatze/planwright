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
than the file tools (`Grep`, `Glob`) are declared outside the
model by name in the test.

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
  accepts, and `git -* rebase*`), granted by `unpushed_rewrite`, and the same
  acts on the worker's own pushed commits, granted by `draft_rewrite` from the
  launch record alone.

The hard-reset and force-push denies stay whole in every profile. The one
route past them is `scripts/worker-branch-sync.sh`, which runs its leased
push, its reset to the branch's own remote branch, and its fast-forward inside
its own process, below every hook: no Bash rule sees those git commands, so
none is narrowed for it, and a raw `git push --force*` or `+` refspec stays
denied at every tier. The worker reaches the helper through the worker command
guard's approval of installed planwright scripts; the policy guard admits only
the helper's literal grammar (for the push, `push
--force-with-lease=<branch>:<sha> --force-if-includes`), and the helper
re-reads the worktree's launch record and re-checks the rest at run time (the
worktree-sync and draft-branch rewrite rows of `doctrine/human-gates.md`).

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
own-branch arm refuses, by name or by worktree containment, the profile refuses
to the file tools with `Edit(...)` denies, and the one read the guard refuses
gets a `Read(...)` deny:

- **Execution-bearing paths** (worker-permission-ergonomics REQ-F1.6): `.git`
  wherever it sits (the worktree's `.git` entry and the common git directory,
  default hooks included), the repo-tracked hooks directories `githooks/` and
  `.githooks/`, the worktree's `.claude/`, and the mise, lefthook, direnv, and
  tool-version config names the guard refuses (`scripts/worker-command-guard.sh`,
  `ob_excluded_name` and `ob_excluded_mise_child`, owns the list; a launch given
  `--mise-task-edit` opens four of those names inside its worktree, and one
  given `--lefthook-edit` opens `lefthook`, `lefthook.*` and `lefthook/`; see
  "The mise task-file opt-in" and "The lefthook config opt-in" below). An adopter
  whose `core.hooksPath` names another directory adds an `Edit(<dir>/**)` deny
  of its own.
- **User-level and system git config:** `~/.gitconfig`, its `~/.gitconfig*`
  siblings, and everything inside a `~/.gitconfig*` directory (a bare name does
  not cover what lies below it, MA-3). A name like that is closed before it
  exists, so a worker cannot create an `includeIf` target under it. The system
  config is an `etc/gitconfig` at any depth, which covers `/etc/gitconfig` and
  prefixed installs such as `/usr/local/etc` and `/opt/homebrew/etc`. Git reads
  these for every session on the machine, so a filter, diff, textconv,
  fsmonitor, pager or gpg-program driver written there fires in all of them.
  The guard refuses these writes by worktree containment, not by name. The XDG
  `~/.config/git/` is already under the `.config` rule. The `~/` rules are
  home-anchored, so a `.gitconfig` inside a worktree stays editable; the
  `etc/gitconfig` rule is not, and also refuses a repository's own tracked
  `etc/gitconfig`.

  The profile cannot name host-specific targets. These stay residuals, closed
  only by an adopter-added `Edit(<path>)` deny in their own settings (the
  mechanism `core.hooksPath` uses; no shipped mechanism generates them): an
  `include.path` or `includeIf` target the rules do not name (a gitconfig in a
  dotfiles checkout, the target of a symlinked `~/.gitconfig`), an
  `XDG_CONFIG_HOME` outside `~/.config`, another account's home, an alternate
  spelling of the home directory (a symlinked or bind-mounted home), and a
  recased spelling on a case-insensitive filesystem (MA-2).
  `GIT_CONFIG_GLOBAL` or `GIT_CONFIG_SYSTEM` in a process environment is out of
  the file tools' reach. Other execution-bearing user files (`~/.ssh/config`,
  `init.templateDir` targets, gpg configuration, shell rc files) stay open too:
  the profile denies named paths over open file tools.
- **The guard's trust inputs** (REQ-G1.8): the launcher's session records
  (`session-records/*.record` under any fleet home), the stream-json
  launcher's per-worker state folders (`streamjson/<worker>/`), which a
  recover and a relaunch read the worker's profile, scope, directory and
  opt-ins back from, and the overlay config
  files the policy resolves through (`planwright.yml` and
  `planwright.local.yml`, wherever they sit).
- **Other processes' environments** (REQ-E1.6): `/proc/<pid>/environ` and
  `/proc/<pid>/task/<tid>/environ`. The Read tool cannot read the worker's own
  `/proc/self/environ` either, and the command guard defers `/proc/self/environ`,
  bare `env` and bare `printenv`.
- **What these rules do not cover:** the other secret locations the command
  guard defers (the home's credential files, `/etc/shadow`, `/dev/fd`). The
  file tools and the static `ls` and `stat` allow rules never reach the guard,
  so those reads run unprompted; Read denies for them, and dropping those two
  static rules so the guard decides, are a recorded follow-up.

Every rule except the worktree's `.claude/` and the home-anchored git config
rules is anchored at the filesystem root (`//`), never at the settings file,
whose directory is the plugin's `config/` (M10). Root-anchoring matters because
mise and direnv read the config of every directory above the one they run in: a
worktree under its primary checkout picks up the
primary's `mise.toml` and `mise.local.toml`, and a rule relative to the
worktree would leave those open. The worktree's own `.claude/` is the
exception, matched relative to the working directory on purpose: a worktree
usually sits under its primary checkout's `.claude/worktrees/`, and a
root-anchored `.claude` rule would refuse every file the worker edits. The two
`~/` git config rules are home-anchored because the files they name sit at the
home directory's top level. The root-anchored directory rules cost the same kind
of over-refusal: a worktree checked out beneath a directory named `.config`,
`.mise`, `mise-tasks`, `.mise-tasks`, `mise/conf.d`, `mise/tasks`, one of
mise's own directories below, a hooks directory, or a lefthook directory (a
dotfiles checkout under `~/.config`, say) is refused every file-tool write, so
such a repository is checked out elsewhere for workers.

The mise rules follow the paths mise documents loading, not every path with a
`mise` component: its project and global config names and `conf.d`
directories ([configuration](https://mise.jdx.dev/configuration.html)), the
`.miserc*.toml` files that rename what it searches for and move its ceiling,
the default file-task directories, which it renders as it loads them
([task discovery](https://mise.jdx.dev/tasks/task-discovery.html)), the
lockfiles that carry download URLs and checksums
([mise.lock](https://mise.jdx.dev/dev-tools/mise-lock.html)), and the
default data, state, cache, system-data, and temporary directories, which
hold the tools and shims it runs and the record of which config it trusts
([directories](https://mise.jdx.dev/directories.html)). The temporary
directory sits under `/tmp` or the system `TMPDIR` (a worker's scratch root,
on macOS under `/private/tmp` or `/var/folders`), and the file-tool rules
refuse every `mise/` below those trees, wider than mise's own, as a fail-safe.
A `mise/` directory anywhere else is refused only its `config*.toml`,
`miserc*.toml`, `conf.d/`, and `tasks/` entries, beside the names refused at
every depth (`mise.toml`, `mise.lock`, `.miserc.toml`, and the rest), so a
source file such as `roles/files/mise/offload.toml` stays writable. The guard
also refuses a shell write that names a `mise` directory itself, since moving
a directory onto that name would make its `config.toml` loaded config, and,
in the scratch root, anything under the root's own `mise/`. These rules
cannot follow an `override_config_filenames` value, a `MISE_*` or `XDG_*`
variable, or a `PLANWRIGHT_FLEET_SCRATCH_BASE` outside the temporary trees
that moves or renames what mise reads, an idiomatic version file such as
`.nvmrc` once a tool enables it, or a file the repo's own config points at
(an `_.source` script, an included task file), which mise runs by location,
however it was last written.

The guard matches these names case-insensitively; the globs are
case-sensitive (MA-2), so on a case-insensitive filesystem a recased
spelling reaches the file tools. For mise that covers a recased entry of a
`mise/` directory (`mise/Config.toml`) as much as a recased `Mise.toml`.
Writes the guard refuses outside the worktree beyond the paths listed above are
not mirrored here, so the file tools still reach them, which includes an
installed planwright root when it is not under `~/.claude`.

Claude Code already protects `.git`, `.claude`, `.envrc`, and the YAML
lefthook config files (MB-8), and the overlays under `~/.claude` with them, but
protection means a prompt, which stalls a headless worker, and its list is
version-specific. A deny refuses outright and holds across versions, so
those paths keep their rules. The mise config, task directories, and
lockfiles, the hooks directories, the
local and non-YAML lefthook config, the session records, and repo-side
overlays are not protected at all.

### Code a worker runs unprompted

The Write tool reaches `scripts/` and `tests/`, so where a script sits proves
nothing about who wrote it. The command guard approves a repository script
(a `.sh` under `scripts/` or `tests/`), a `bats` file, and a script under a
planwright root that is a git checkout only when a commit holds it with the
same bytes (`scripts/worker-command-guard.sh`, `committed_blob`), and so is a
declared command step whose location lies in a git checkout, the repository
or another (`declared_location_ok`); an install copy, which is no checkout of
its own, is trusted by location. Inside the worktree the session record
names, that commit is the base: the merge base of HEAD and the record's
`pr_base` remote-tracking ref (`trusted_rev`), since the worker can commit
there and the guard never sees what a script runs. `pr_base` is the unit
branch remote's default branch as the launcher recorded it, not a stacked
PR's base, so a script only a stacked base holds prompts. Elsewhere the
commit is the checkout's HEAD. A script a worker wrote or edited prompts,
committed or not, whichever spelling reaches it (`sh`, `bash`, a direct path,
a symlinked folder, a `..` walk, inside `fish -c` or a loop, behind
`timeout`), and so does `bats` on a folder; one the base gained counts once
the worker merges the base. A record with no `pr_base`, a `pr_base` with no
remote-tracking ref, or a base with no commit in common trusts no file in the
worktree, and a repository nested in the worktree trusts none either. The
launcher writes `pr_base` only for a task or flight branch, so a kickoff,
spec-branch or primary-checkout session prompts on every repository script,
`bats` file and linter config in its worktree. A test suite the worker adds
prompts on every run for the life of its PR, through the compute router too
(`compute-route.sh --test tests/test-x.sh -- bash tests/test-x.sh`): mission
control vets each run, and `mise run` and a declared check command stay the
unprompted routes. The check reads the file as it is before the command
runs, so a command that relies on it and also makes a write the own-branch
arm admits defers as a whole (`cp f scripts/ok.sh && sh scripts/ok.sh`, and
equally `touch build/x && bash tests/ok.sh`); staging and committing change
no worktree file and do not count, so `git commit -m x && bash tests/ok.sh`
keeps its approval. So a worker cannot write a
script and run it unprompted to reach a path its file tools are refused: the
local and primary-checkout hook config, the fleet state folder's opt-in
record, the session records.

What still runs code a worker wrote without a prompt:

- **A script it committed, in a session with no record.** Without a session
  record the guard cannot tell the worktree or its base, so it holds a
  repository script to HEAD, which the profile's static `git commit` allow
  lets the worker move. A launcher whose record write fails launches the
  worker this way. A record that is set but names no usable worktree (a
  missing or relative record path, a repeated or non-canonical
  `worktree_root`, a record inside the worktree) trusts nothing instead,
  wherever the file lies: the static allows still let the worker commit, and
  the guard cannot place where. The one exception is the guard's own
  planwright root, held to HEAD, since it holds the guard itself.
- **A write that lands while a trusted script runs.** The guard checks a
  script's bytes before the command runs, and a shell reads a script as it
  goes, so a write running in the background (an own-branch write the worker
  started earlier with `run_in_background`, or a file-tool edit) can append
  to a base-held script while it runs.
- **The repository's tasks, hooks and check commands.** `mise run <task>`,
  `lefthook run <hook>` and a check command the repository declares in
  `worker_check_commands` run config the path denies protect, and whatever
  that config or a check command's `<path>` names, the test files a worker
  wrote among them: the gate has to run what the worker wrote. A file a
  declaration names in its literal words (`scripts/check.sh <word>`, `bash
  check.sh`) is held to the commit of the checkout it lies in, the PR base
  inside the worktree, like a declared step's location (a file in no
  checkout keeps the declaration's trust, and a symlink defers). A bare first
  word is exempt, since the shell looks it up on PATH. The check cannot tell
  a script from a runner argument, so a word such as `make test`'s `test`
  prompts while a file of that name sits in the working directory and not in
  the base. A declaration whose `<path>` is the
  script it runs (`bash <path>`) admits any file in the worktree, committed or
  not, so it is the repository's own choice to make.
- **What a trusted script reaches.** The guard checks the script it runs,
  not a path it is handed, a sibling it sources or calls, or a test file it
  globs, any of which a worker may have written or edited. A declared step
  run through `scripts/step-run.sh` is held by the runner itself to the same
  commit the guard uses (see the next section).
- **An install copy outside `~/.claude`.** Under `~/.claude` a file-tool write
  prompts (MB-8); elsewhere the file tools reach an install copy, which is
  trusted by location (see the residual above).

## Options and config files that redirect an approved command

A static allow rule never reaches the command guard's argument screens, so
the profile names no verb an option or a loaded config file can turn into a
write to any path or a run of code the worker chose (pass G of
`tests/test-permission-matcher.sh`). The guard decides these, approving the
plain forms:

- **git's log and diff family** (`git show`, `git diff`, `git log` and the
  rest, `git stash list`, `git stash show` and `git reflog show` among them,
  which hand their options to it) writes its output to the path `--output`
  names, a path the file tools refuse included (a worker's fleet state
  folder, its opt-in record). The guard defers `--output` in every spelling
  git accepts, and `git format-patch` whole.
- **`mise run`**, and `mise tasks run`, which is the same command: `--shell`
  runs the task through any command, `--cd` runs a task another directory's
  config defines, `--env` loads a `mise.<env>.toml`, and `--tool` puts a tool
  on the task's PATH. The guard defers each, alone or in a short-flag cluster,
  anywhere on the line.
- **`markdownlint-cli2` and `markdownlint`** read a config from the working
  directory and from the folder of each file they lint (probed on
  markdownlint-cli2 0.19.0), and a config can run code: a `.cjs` or `.mjs`
  one is a module, and an options file (`.markdownlint-cli2.jsonc`, `.yaml`
  or `.yml`, or `package.json`) can name custom-rule, markdown-it plugin and
  formatter modules. The guard approves a run only on named files inside the
  repository, reached through no linked folder, with no option but
  `--no-globs` (and markdownlint's `-q`). Every folder those files sit in,
  the working directory, and every folder above them must hold no module
  config, committed or not, since a committed one may import a file the
  worker wrote, and only options and settings files that their checkout's
  trusted commit holds unchanged (the `committed_blob` check: the base inside
  the recorded worktree), no options file naming a module
  key or holding a backslash, through which an escape could spell one. An
  explicit `--config` naming a committed file would not do instead: each
  folder's own config still loads beside it. A glob or folder operand defers,
  and so, without `--no-globs`, does an options file in the working directory,
  since either reaches folders the guard does not walk. The check reads the
  folders before the command runs, so a lint beside anything the own-branch
  arm admits (a write, or a git act such as `git add`) defers. What still
  passes: a settings file the worker committed in a checkout outside the
  recorded worktree, or in a session with no record, which is held to HEAD;
  and a trusted settings file's `extends` reads the file it names, which a
  parse error prints part of, so one naming another readable file shows that
  file's start.
- **A declared command step** run through `scripts/step-run.sh` runs its
  location, and a session-hosted step's line is printed, only as the command
  guard's trusted commit for that checkout holds it (`trusted_commit`: the
  base in the worktree a worker session record names, nothing in a repository
  nested in it or under a record naming no usable worktree, HEAD elsewhere);
  otherwise, or when git cannot answer for that checkout, the step is
  recorded `failed`, so in a session with no base a declared step located in
  its worktree always fails. A location with no `.git`
  entry above it, an installed tool, keeps the declaration's trust. The
  guard's own approval of a declared line typed in the session is a separate
  check.

A check command the repository declares (`worker_check_commands`) is held to
the same screens when it runs one of these loaders, as its first word or the
word after a runner prefix's `--` (`mise exec -- markdownlint-cli2 <path>`),
matched by the word's last path component and case-insensitively: a declared
`markdownlint-cli2` or `markdownlint` is approved only where the undeclared
command would be, and so is a declared `mise` whose next word is an option,
`run`, `tasks`, or the `r`, `task` and `t` spellings, which the undeclared
screen does not know and so defers. Any other `markdownlint` name, such as the
`markdownlint-cli2-fix` binary older releases ship, defers as the undeclared
one does. The declaration vouches for the words it spells, not
for the config those folders hold, so a declared lint beside a worker-written
or uncommitted config defers, and so does a declared `--cd`, `--env` or
`--tool` on `mise run`, and a file its literal words name is held to the
commit its checkout is held to (the base inside the recorded worktree), as
"Code a worker runs unprompted" states. Other ways a declaration reaches the
same config are not screened for it: a runner or wrapper with no `--` before
the linter (`npx markdownlint-cli2`, `env` or `timeout` before it, `node`
running its bin script), a package script that runs one, and
`mise exec`, `mise watch` or a task named straight after `mise`, which load
the mise config the file-tool rules protect. A declared command step's line
is matched exactly and run by `scripts/step-run.sh`, outside the guard, so it
too runs whatever config its folders hold.

## The mise task-file opt-in

The shipped profile denies the file tools every mise task-file name
(`mise.toml`, `.mise.toml`, `mise-tasks/`, `.mise-tasks/`) at any depth, and a
path rule cannot be narrowed to "inside this worktree". A worker whose unit
must edit the repository's own task files is therefore launched with
`--mise-task-edit` (`scripts/fleet-streamjson.sh launch`, or
`scripts/mission-control-launch.sh launch --mise-task-edit` on the stream-json
rung; worker profile only, off by default). The opt-in is a launch argument and
nothing else: it is recorded as `mise_task_edit=1` in the session record the
launcher writes outside the worktree (`scripts/worker-session-record.sh`) and
in the launch's opt-in record for a recover (below), and is never read from
live config, the checkout or the environment. A fresh launch without the flag drops it; a
recover or relaunch keeps what its launch recorded.

An opted-in launch gets three things, and a launch without the flag gets
neither (it passes the shipped profile itself, byte for byte):

- **A generated profile** (`scripts/worker-settings-generate.sh`): the four
  broad task-file denies are replaced by literal denies of the same four names
  in every ancestor folder of the worktree, the root included, and in the
  primary checkout's top folder when the worktree lies outside it (a primary
  whose git directory is not `<checkout>/.git` cannot be named, which refuses
  the launch). Every other rule is the
  shipped one, in order: mise's local files (`mise.local.toml`,
  `mise.*.toml`, `.mise.*.toml`), `mise/config*.toml`, `conf.d` and miserc
  files, the trust, data, state and cache folders, the temporary `mise/`
  folders, and the lockfiles. A worktree path holding a character a path rule
  would read as a pattern (`* ? [ ] \ ( )`), a single quote, a control character, or a
  component ending in a space refuses the launch.
- **A file-tool hook** (`scripts/worker-mise-edit-guard.sh`, added to the
  generated profile's `PreToolUse` list for `Edit|Write|MultiEdit|NotebookEdit`,
  with the worktree as its argument): a deny rule cannot be narrowed to "inside
  this worktree" and beats every allow, so the hook refuses any task-file path
  that lies outside the worktree, whatever the spelling: another worktree or
  repository, a `..` escape, or a symlinked directory or file that resolves
  out. A hook that cannot read its input (no `jq`, a payload that is not JSON,
  a field holding the payload's own separator byte) refuses every file-tool
  call, task path or not. The generator itself refuses the launch when the
  hook script beside it is missing or not executable, since the broad denies
  it replaced would then leave the names open outside the ancestors. The
  worker runs the copy under its own plugin root, which its dispatch
  environment may point at another install, so the launch preflight proves
  that copy refuses an opted-in name outside the worktree (`docs/fleet.md`).
- **The guard's own-branch arm** admits writes to those four names inside the
  worktree (`ob_excluded_name`, third argument of `ob_excluded_rel`, and the
  recursive-act screen `ob_tree_clean`), only when the record carries exactly
  one `mise_task_edit=1`. The scratch zone, anything outside the worktree, and
  every other excluded name stay closed.

The generated profile and the launch's opt-in record sit in the worker's fleet
state folder (`streamjson/<worker>/`). The record holds every opt-in the launch
was given (`mise_task_edit=1`, `lefthook_edit=1`, `spec_branch=<branch>`), one
line each, in one
file named `planwright-opt-in.<blob id>`, the git blob id of its own content
(`scripts/fleet-streamjson.sh`, `OPT_IN_PREFIX`). A fresh launch whose set
changes removes the old `session` first, then every earlier record, and
renames the new one in last, so a launch that fails part way leaves either the
earlier set with its session or no session at all, never a session beside a
set its launch did not ask for. A recover or relaunch reads only an entry
spelled exactly that way whose content, read once, still hashes to its name,
and refuses (exit 7; a recover reports it as a failed resume) on more than one
record, a mismatch, a line outside the grammar, or a `mise-task-edit`,
`lefthook-edit` or `spec-branch` marker of the layout the record replaced, which a worker could
write and so is never read: launch such a worker fresh. That is what holds on
a case-insensitive filesystem (default APFS, the Mac offload host's
included), where the profile's case-sensitive denies do not:

- **Created through a recased folder above it** (`StreamJson/<w>/...`): the
  name lands exactly, so the deny names it at any depth
  (`Edit(//**/planwright-opt-in.*)`), never under a folder a recasing escapes.
- **Created under a recased name of its own** (`Planwright-Opt-In.<id>`): the
  deny misses it, and the read, which matches the directory entry exactly
  (`find -name`, never a path open), never sees it.
- **Rewritten in place through a recased name**: the content no longer hashes
  to the name, which refuses the recover rather than honour it.

`worker-settings.json` is regenerated from the shipped profile by every launch,
recover and relaunch of an opted-in worker before it is read, so a rewrite of it
is never used. The state folder's other files, which a recover and a relaunch
read back too (`profile`, `scope`, `cwd`, the tier fields), have only the deny
of the whole folder (`Edit(//**/streamjson/**)`), and the session records only
their `session-records/*.record` deny: a recased spelling of a folder or name
passes both on a case-insensitive filesystem (MA-2). A script the worker
writes no longer runs unprompted to reach them ("Code a worker runs
unprompted"), but the routes that section lists still do, so neither layer
is a boundary against a worker set on opting itself in.

Residual risk: the hook compares the mise names case-sensitively and works from the
payload's own spelling and the filesystem, so it is a fail-closed second layer
rather than a proof; the worker's scratch root holds no task files the hook
admits. The ancestor folder names are matched case-sensitively (MA-2), where
the broad rule they replace matched any casing of the folders above the file.
`tests/test-permission-matcher.sh` (pass I) runs the generated rules through
the model: the worktree's task files open, each local file, trust, cache and
lockfile row and each ancestor's task files, the primary checkout's included,
stay denied, and each literal ancestor deny is the only rule blocking at least
one row. `tests/test-worker-command-guard-mise-tasks.sh` pins the guard half,
`tests/test-worker-settings-generate.sh` the generator, and
`tests/test-fleet-streamjson.sh` the launcher (c9m, with c9o for the record's
single write and c9q for its exact-entry read).

## The lefthook config opt-in

The shipped profile also denies the file tools the lefthook config at any depth
(`lefthook.<ext>`, `lefthook/`, the local and dotted variants), so a worker whose
unit is fixing a slow or wrong pre-commit hook cannot edit the repository's own
hook config. `--lefthook-edit` opens exactly the tracked config names inside the
worker's own worktree and nothing else. It has the mise opt-in's shape in every
respect: a launch argument of `scripts/fleet-streamjson.sh launch` and
`scripts/mission-control-launch.sh launch` (worker profile, stream-json rung,
refused anywhere else, off by default), recorded as `lefthook_edit=1` in the
session record and as `lefthook_edit=1` in the launch's opt-in record,
never read from live config, the checkout or the environment, dropped by a fresh
launch without the flag and kept by a recover or relaunch. The two opt-ins are
independent: each opens only its own names, and a launch may carry both. A
change to the opt-in reaches a worker only by relaunch.

What an opted-in launch gets:

- **A generated profile** (`scripts/worker-settings-generate.sh --lefthook-edit`):
  the two broad denies `lefthook/**` and `lefthook.*` are replaced by literal
  denies of the same two names in every ancestor folder of the worktree and in the
  primary checkout, exactly as for the mise names. Every other rule is the
  shipped one, in order.
- **The same file-tool hook** (`scripts/worker-mise-edit-guard.sh`, told to judge
  the lefthook names by a `lefthook` argument after the worktree, or `mise
  lefthook` for a launch with both opt-ins): a lefthook name outside the
  worktree, by spelling or by where it resolves, is refused. It matches the names
  in any letter case.
- **The guard's own-branch arm** admits writes to `lefthook`, `lefthook.*` and
  anything under a `lefthook/` directory inside the worktree (`ob_excluded_name`
  reading the `l` letter of the record's opt-ins, and the recursive-act screen
  `ob_tree_clean`), only when the record carries exactly one `lefthook_edit=1`.

Still closed under the opt-in: `lefthook-local.*` and the `.lefthook`,
`.lefthook.*`, `.lefthook-local` and `.lefthook-local.*` variants, `.githooks/`
and `githooks/` (denied to the file tools by name), whichever directory
`core.hooksPath` names (excluded from the arm by what git reports, so it follows
the setting; the file tools know only the two names above, so a hooks path named
otherwise is an adopter's own `Edit` deny, as under "What the path rules close"),
`.git`, `.claude`, the mise names unless `--mise-task-edit` is also given, the scratch
zone, and every write outside the worktree, the primary checkout's lefthook
config included. The local variant stays closed because it is the gitignored,
per-machine override: a change there never lands in the pull request, so review
could not see it, where the tracked config shows up in the diff. The dotted
variants and the dotted script directories are further lookup names beyond what
fixing the tracked hook config needs; a repository that keeps its config under
one of them needs its own opt-in.

Residual risk, and the reason the opt-in is a sign-off item: a lefthook job is a
shell command, and it runs outside the command guard. The worker's own commits
fire it through git, and the guard approves `lefthook run <job>` as repository
code (`guard_lefthook` refuses a config override, any flag before the
subcommand, and every subcommand but `run`), so a
worker that edits a job and then runs it executes that command in its own
session at once, before anyone reviews the diff, with the session's privileges.
Every "stays closed" line above governs the worker's file tools and the guard's
own arm; a job it writes is not held to them. The opt-in therefore lets the
worker change what runs on its own commits, for the worktree it was launched in.
What bounds it is the operator's launch-time choice for one named worker whose
unit is the hook fix, and the tracked file landing in the pull request diff,
where review sees what will run for every later contributor.

None of this is a sandbox, for an opted-in worker or any other. The guard no
longer approves a repository script the worker wrote or edited, committed or
not ("Code a worker runs unprompted"), but a lefthook job is exactly the
route that section leaves open: a job the worker writes runs on its next commit
or `lefthook run`, and through it the worker can write any path the file-tool
denies close, the opt-in record, another worktree's lefthook config and the
primary checkout's included. What the path rules and the opt-in govern is a
worker's ordinary file-tool and shell edits, not one working around them; the
mise opt-in has the same exposure through the tasks it opens. The hook matches
the lefthook names in any ASCII letter case, where the mise names are matched
case-sensitively; both leave non-ASCII case-folding on a case-insensitive
filesystem unhandled, and the per-launch profile's ancestor names are
case-sensitive for both.
`tests/test-permission-matcher.sh` (pass J) runs the generated rules through the
model, `tests/test-worker-command-guard-lefthook.sh` pins the guard half,
`tests/test-worker-settings-generate.sh` the generator, and
`tests/test-fleet-streamjson.sh` (c9l) and
`tests/test-mission-control-launch-tmux.sh` the launchers.

## The spec-branch launch record

A spec PR that falls behind `main` needs its branch
(`planwright/<spec>/<name>`, an amendment branch for one) brought into a
worktree to sync or walk it, and the policy guard otherwise refuses both
halves: a worker's flight branch merges only the PR base or its own remote
branch, and a worktree holding the spec branch is not the session's own unit
branch. A launch given `--spec-branch planwright/<spec>/<name>` (a
worker-profile session on the stream-json rung only; the launcher checks with
`gh` that the branch is the head of an open pull request, and refuses
otherwise) writes that one branch into the session record as `spec_branch`
(`scripts/worker-session-record.sh`), which a recover rewrites from the
launch's own state. The guard reads it only from that record, outside the
worktree, never from the command text, the checkout, config or the
environment. A record that is a symlink, is not this user's own regular file,
sits inside the worktree, names the field twice, or names anything outside
`planwright/<spec>/<name>` (a task or flight branch, a branch in the protected
set) names no branch. Only the worker tier reads it. Two acts open, and
nothing else:

- **Bring the branch in.** On the session's own flight branch,
  `git merge --ff-only origin/<spec branch>` (also spelled
  `refs/remotes/origin/<spec branch>`) is admitted as the single source. A
  merge without `--ff-only`, a `--no-ff` one, a second source, a pull, a bare
  local name, a SHA, a tag, or any other branch (another spec branch, another
  worker's flight branch) keeps today's refusal, and so does a local branch or
  tag of the same name at another commit. Merging `origin/main` afterwards is
  the ordinary base merge, and the push of the result to the spec branch is an
  ordinary push by explicit refspec (`git push origin HEAD:refs/heads/<spec
  branch>`) that the guard never refused: the spec branch is outside the
  protected set, and the profile's force and `+` denies still refuse a force.
- **Sync it with its base.** In a linked worktree that is the session's
  project directory with the named spec branch checked out, `git merge
  origin/main` (the PR base alone, by name and by what git resolves it to) is
  admitted, and so is `git merge --ff-only origin/<spec branch>`, the branch's
  own remote-tracking ref as the single source, which brings a reused worktree
  up to its PR head first. A merge of that ref without `--ff-only`, a local
  name, a tag, or a local branch or tag of the ref's name at another commit
  keeps the refusal, as do any other source, a pull, a spec branch the record
  does not name, and every other act on that branch (commit, amend, rebase,
  reset); the merge caches nothing, so a later act in the same command does
  not inherit the branch as a unit branch. `worker_base_merge: deny` refuses
  it as it does for a unit branch. A refusal on this path (a pull there, another
  source, or the spec branch merged into a task or flight branch without
  `--ff-only`) names the route: `git switch <spec branch>` in the worker's own
  worktree when it is elsewhere, then the fast-forward to the PR head, then
  the base merge.

No force, reset or rebase is admitted by either act.

A kickoff session needs no record for the second act: its launch scope
(`PLANWRIGHT_WORKER_SCOPE`, set by the launcher, which no command can change
for the hook) names its spec branches. `kickoff-<spec>` names
`planwright/<spec>/spec`, `planwright/<spec>/spec-rework` and
`planwright/<spec>/amendment-<n>`; an amendment kickoff's
`kickoff-<spec>-a<n>` names `planwright/<spec>/amendment-<n>` alone, and is
refused when another spec's kickoff could share that scope, as for its push.
Checked out in the session's own linked worktree, such a branch takes the same
base merge and fast-forward to its PR head under the same rules. `planwright/<spec>/spec` sits in the
protected floor, which governs pushes and is reached only through the kickoff
push helper, which reads no protected set for it, so its kickoff's local merge
there skips the protected set as that push does, `protected_branches`
additions included; every other branch still reads the set. Whichever names the branch, the merge
must be plain: an option outside the message, output, signing, hook and
fast-forward ones (a squash, a strategy or strategy option, unrelated
histories, `--no-commit`, `--autostash`), an abbreviated option or an expanded
one refuses.

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
