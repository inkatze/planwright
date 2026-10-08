# The tower posture: the front-door delta

The `/tower` front door runs under the same permission profile as an
orchestrating tower, `config/tower-settings.json`. This document is the delta
that extends that profile for the front door's own routine commands, written
for the human sign-off a permission change needs. The extension adds guard
shapes and deny entries only: the profile's `allow` list, its hooks,
`defaultMode`, and every deny entry it carried before are unchanged.

**Sign-off.** The delta lands as sign-off commits on its pull request, and the
pending-sign-off checklist in the PR body lists them. Approving the PR by the
approval act [human-gates](../doctrine/human-gates.md) names signs the delta
off; the draft-to-ready flip does not. Reject one item before that by the
recipe its checklist entry prints.

## The front door's routine command shapes

Each row is a command shape the `/tower` skill (`skills/tower/SKILL.md`) or
the `/offload` flight path it drives runs as routine work, with the guard's
verdict before and after this delta. A deferred command falls to Claude Code's
normal permission flow (a prompt, or the auto-mode classifier), which is the
stall the extension removes.

| Shape | Where the skill runs it | Before | After |
| --- | --- | --- | --- |
| `jq '<filter>' <settings file>` | bring-up's posture check, one projection per settings layer | defer | allow |
| `mktemp` | a flight petition's ask and grounds temp files | defer | allow |
| `rm [-f] [--] <temp directory>/tmp.<suffix> …` | removing those files once the dispatch returns | defer | allow |
| `<planwright root>/scripts/<name>.sh …` | the flight sweep, dispatch, attention queue, catch-up, spec status, rule-doc resolution | allow | allow (unchanged) |
| `git branch --list …`, `git cat-file -e …` | bring-up's fallback flight reads | allow | allow (unchanged) |
| `gh pr list …`, `gh pr view …` | a flight's landing, status | allow | allow (unchanged) |
| `test -x <hook path>` | checking the command guard's hook path resolves | allow | allow (unchanged) |

## The allow delta

All of it lives in `scripts/tower-command-guard.sh`, the allow-only hook; no
static `allow` entry is added.

- **`jq` with an inline filter.** The screen is the worker guard's, carried
  over byte-identical (the tower guard's suite diffs the two copies). jq has no
  exec or file-write primitive. Its input files and `--rawfile` /
  `--slurpfile` values are not limited to settings layers: any file the
  session can read qualifies, as it already does for `cat` and `head` under
  this guard and for the profile's `Read` allow. What defers: a filter reading the environment
  (`env`, `$ENV`, and jq 1.6's `$ ENV` with a space or comment between), a
  filter loading module text (`include`, `import`), a filter from a file
  (`-f`), a module search path (`-L`), every run while `~/.jq` exists (a file
  there is read into every filter, a directory is on the module path), every
  run while `HOME` is unset, empty, or relative (jq 1.6 then falls back to
  the password entry's home), any unrecognized flag, an output redirect to a
  file (`/dev/null` aside), and a filter the guard cannot read literally (an
  unexpanded variable). A tilde,
  glob, or unexpanded variable in any operand defers too (a `for` variable
  over literal words is checked as its value), so a settings layer passes
  only when named by a literal path, absolute or relative (the user layer
  by its absolute path, never `~`). The worker guard carries the same
  screen and takes the same fixes.
- **Bare `mktemp`.** It creates one fresh, empty file in the system temp
  directory: `TMPDIR` for GNU mktemp, and on macOS the per-user temp
  directory, whatever `TMPDIR` says. A template, `-p`, `-t`, `-d`, and
  `-u` all defer, and so does mktemp once a `while` or `until` loop has
  opened in the command, since those loops have no pass cap. Any input
  redirect defers too: zsh, the shell the Bash tool runs on macOS, reads
  `<->` or `<1-99>` as a numeric glob over digit-named files, where the
  guard would see two redirects.
- **`rm` of mktemp-named temp files.** Every operand, which may name a file
  that does not exist yet, must be an absolute path with no `.` or `..`
  component, whose name has mktemp's default shape (`tmp.` and at least six
  letters or digits), whose directory is exactly `TMPDIR`, the macOS per-user
  temp directory, or `/tmp` both as written (in the spelling the hook's
  environment gives, or its resolved form) and as resolved physically (never
  a directory below them, never reached through another symlink; a relative
  `TMPDIR` names none), and that is not a symlink, a directory, or
  another non-regular file. `-f` and `--` are the only flags, and only before
  the first operand (BSD rm reads a later one as a file name). A recursive or
  directory removal, `-i` or `-v`, a relative, tilde, glob, unexpanded-variable, or
  dot-component operand, a directory whose resolved path holds a line break,
  and any operand outside those directories defer, and one bad operand defers
  the whole command. Like mktemp, removal defers once a `while` or `until`
  loop has opened, and with any input redirect. A quoted or
  backslash-escaped operand defers too, as does one taking its value from a
  quoted `for` head word: the guard reads double-quoted backslashes
  differently from the shell, so such an operand could name another path to
  `rm`.

## Fixes that only defer more

These change no allow above. Each makes a command both guards approved
before defer, in code the two guards share:

- **zsh's special names as variables.** `path` and `cdpath` (tied to PATH
  and CDPATH), `NULLCMD` and `READNULLCMD` (what a lone redirect runs), and
  `module_path` and `MODULE_PATH` (where zsh loads a module from) defer as
  `for` loop variables, and in the worker guard also as `read` and tracked
  assignment names.
- **zsh's parameter forms.** `$~NAME`, `$=NAME`, `$^NAME` and `$+NAME`, and a
  subscript or modifier after an unbraced name (`$f[2,4]`, `$f:e`), read as
  unresolved, so a verb whose verdict rests on the value defers: zsh expands
  them where bash leaves text. `$~NAME` defers wherever it appears, an
  argument-independent verb's operand included: zsh reads its value as a glob
  pattern, and a glob qualifier in that value can run a command.
- **A NUL byte in the command.** The hook's command substitution drops it, so
  the guard would screen other text than the shell runs.
- **A named-fd redirect.** A `{name}` brace word written directly before a
  redirect operator is not an operand: bash and zsh open a descriptor and
  assign its number to that shell variable, so what runs after it sees a value
  the guard never checked.
- **A non-ASCII byte after a `$` or its name.** zsh in a UTF-8 locale reads a
  non-ASCII letter as part of a variable name, where the guards end the name
  before it and keep the byte as text, so the shell expands a different name
  from the one the guard resolved; such a byte, directly after the `$` or
  after the name it opens, defers.
- **Characters a non-default zsh option would expand.** With extended
  globbing or brace character classes on, zsh expands an unquoted caret,
  mid-word tilde or hash, or brace where the guards read literal text. A
  program word holding one, in the jq, awk, sed and (in the worker guard) yq
  screens, defers; the same characters in any other word, a git revision
  suffix included, and inside quotes keep their verdicts.

## The deny delta

Seven entries are appended after the existing floor, which stays byte-identical
and in order:

- `mcp__*__merge_pull_request`, `mcp__*__update_pull_request`,
  `mcp__*__push_files`, `mcp__*__create_or_update_file`, and
  `mcp__*__delete_file`: the GitHub write tools the floor already denied by
  their `mcp__github__` names, now denied on every MCP server. Claude Code
  matches a deny rule's tool-name glob against the full tool name (deny and
  ask rules accept a wildcard anywhere in it, as of Claude Code 2.1.293), so a
  second GitHub server (a claude.ai connector, an enterprise server) can no
  longer reopen the merge, ready-flip, or default-branch-write floor.
- `mcp__*__update_pull_request_branch`: the host-side PR branch update, which
  merges the base into the PR branch. The floor denies `git merge` to the
  tower; this denies the same act through an MCP tool, on every server.
- `mcp__*__create_pull_request`: PR creation, which can open a PR that is not
  a draft, the same end state as the ready flip the floor denies. The tower
  opens no PR itself (a flight's worker does, under its own profile), so the
  tool is denied wholesale on every server.

The `gh api` spellings of the merge and the ready flip are the policy guard's
(`scripts/policy-guard.sh`, wired with the `tower` tier), not this profile's.

## Residuals

- **Same-named tools elsewhere.** A glob also denies a tool that shares one of
  these names on a server that is not GitHub (a drive's `delete_file`, for
  one). The tower needs none of them; the worker profile is not changed.
- **The worker profile** still denies the merge and the three write tools by
  their `mcp__github__` names only. Its ready flip and base merge are not in
  its deny block at all: a policy knob can grant either act to a worker, and
  a profile deny would refuse what the policy permits. Widening the worker
  profile is a worker-posture change, outside this delta, and covers only the
  tools no knob governs.
- **Repository-level writes.** The tower profile does not deny the
  repository-level MCP write tools, such as repository deletion
  (`delete_repository`), ruleset creation (`create_repository_ruleset`), and
  workflow dispatch (`actions_run_trigger`), on any server. They sit outside
  the floor's merge, ready-flip, and default-branch-write acts; the tower
  recorded them as a residual rather than widening the deny block further.
- **An older Claude Code** that does not support tool-name globs in deny rules
  matches nothing with them; the literal `mcp__github__` entries still hold.
- **A `TMPDIR` the hook does not share.** The guard reads `TMPDIR` from its own
  environment. Where the session's shell sees another one and mktemp writes
  there, the removal defers to the permission prompt; it is never allowed by
  mistake.
- **A directory swapped after the check.** The guard checks the operand's
  directory when the hook runs, and refuses a written path through a symlink
  the temp-directory list does not name, so another local account's symlink
  in `/tmp` is no route; a same-user process that replaces a temp directory
  with a symlink before `rm` runs could still point the removal elsewhere, and whatever
  entry has the name when `rm` runs goes, a name absent at the check
  included. Only non-directory entries with mktemp-shaped names can be
  unlinked, never followed and never a directory.
- **Whose temp file it is.** The guard cannot tell a file the tower created
  from another same-user process's: any mktemp-named regular file directly in
  `TMPDIR`, the macOS per-user temp directory, or `/tmp` is removable without
  a prompt, another session's live temp file included. The tower took this
  as a residual rather than requiring a tower-owned name prefix or a
  per-session directory. The sticky bit on `/tmp` still protects other users'
  files. On a case-insensitive filesystem (the macOS default) the name check
  reads the operand as typed, so an entry whose name differs from a mktemp
  name only in letter case, such as `TMP.Readme12`, is removable too.
- **Settings merged before this delta.** A tower whose settings merged an
  earlier copy of the profile lacks the appended deny entries, so bring-up's
  posture check finds them missing and holds back repo-mutating routes and
  relays until the operator merges them or acknowledges running without
  them.

## How it is verified

- `tests/test-tower-command-guard.sh` asserts every new allow shape above and
  its deferring neighbours, the zero-false-allow bar, the deny-precedence
  outcome for the floor's spellings, and that the shared `jq` screen's code
  matches the worker guard's (full-line comments aside).
- `tests/test-tower-command-guard.sh` and `tests/test-worker-command-guard.sh`
  each assert the fixes that only defer more, in their own guard, and the
  tower suite's parity rows check that both guards give those commands the
  same verdict.
- `tests/test-tower-settings-hook-wiring.sh` pins the pre-extension floor as
  the deny block's exact prefix, pins the extension as the exact remainder,
  and checks the globs against other servers' tool names, read-only tools
  included, using a shell glob as the stand-in for Claude Code's matcher.
- `tests/test-reserved-control-spellings.sh` keeps the history-rewrite denies
  (force-push, amend, squash, fixup, rebase) and the merge and ready-flip
  denies holding under the tower guard and the tower profile.
