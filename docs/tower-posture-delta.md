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
| `rm [-f] [--] <TMPDIR or /tmp>/tmp.<suffix> …` | removing those files once the dispatch returns | defer | allow |
| `<planwright root>/scripts/<name>.sh …` | the flight sweep, dispatch, attention queue, catch-up, spec status, rule-doc resolution | allow | allow (unchanged) |
| `git branch --list …`, `git cat-file -e …` | bring-up's fallback flight reads | allow | allow (unchanged) |
| `gh pr list …`, `gh pr view …` | a flight's landing, status | allow | allow (unchanged) |
| `test -x <hook path>` | checking the command guard's hook path resolves | allow | allow (unchanged) |

## The allow delta

All of it lives in `scripts/tower-command-guard.sh`, the allow-only hook; no
static `allow` entry is added.

- **`jq` with an inline filter.** The screen is the worker guard's, carried
  over byte-identical (the tower guard's suite diffs the two copies). jq has no
  exec or file-write primitive. What defers: a filter reading the environment
  (`env`, `$ENV`), a filter from a file (`-f`), a module search path (`-L`),
  any unrecognized flag, an output redirect, and a filter the guard cannot
  read literally (an unexpanded variable).
- **Bare `mktemp`.** It creates one fresh, empty file in the system temp
  directory: `TMPDIR` for GNU mktemp, and on macOS the per-user temp
  directory, which `TMPDIR` normally names. A template, `-p`, `-t`, `-d`, and
  `-u` all defer.
- **`rm` of mktemp-named temp files.** Every operand must be an absolute
  path whose name has mktemp's default shape (`tmp.` and at least six letters
  or digits), whose directory canonicalizes to exactly `TMPDIR` or `/tmp`
  (never a directory below them), and that is not a symlink, a directory, or
  another non-regular file. `-f` and `--` are the only flags. A recursive or
  directory removal, `-i` or `-v`, a relative, tilde, glob, or variable
  operand, and any operand outside those two directories defer, and one bad
  operand defers the whole command.

## The deny delta

Six entries are appended after the existing floor, which stays byte-identical
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
- **An older Claude Code** that does not support tool-name globs in deny rules
  matches nothing with them; the literal `mcp__github__` entries still hold.
- **A `TMPDIR` the hook does not share.** The guard reads `TMPDIR` from its own
  environment. Where the session's shell sees another one, or where mktemp
  writes elsewhere (macOS prefers its per-user temp directory to `TMPDIR`),
  the removal defers to the permission prompt; it is never allowed by
  mistake.
- **Whose temp file it is.** The guard cannot tell a file the tower created
  from another same-user process's: any mktemp-named regular file directly in
  `TMPDIR` or `/tmp` is removable without a prompt, another session's live
  temp file included. The sticky bit on `/tmp` still protects other users'
  files.
- **Settings merged before this delta.** A tower whose settings merged an
  earlier copy of the profile lacks the appended deny entries, so bring-up's
  posture check finds them missing and holds back repo-mutating routes and
  relays until the operator merges them.

## How it is verified

- `tests/test-tower-command-guard.sh` asserts every new allow shape above and
  its deferring neighbours, the zero-false-allow bar, the deny-precedence
  outcome for the floor's spellings, and that the shared `jq` screen's code
  matches the worker guard's (full-line comments aside).
- `tests/test-tower-settings-hook-wiring.sh` pins the pre-extension floor as
  the deny block's exact prefix, pins the extension as the exact remainder,
  and checks the globs against other servers' tool names, read-only tools
  included, using a shell glob as the stand-in for Claude Code's matcher.
- `tests/test-reserved-control-spellings.sh` keeps the history-rewrite denies
  (force-push, amend, squash, fixup, rebase) and the merge and ready-flip
  denies holding under the tower guard and the tower profile.
