# Hook payload fixtures

One fixture per hook event planwright registers, plus `WorktreeCreate.json` for
the event it deliberately does **not** register. Each file is a complete, real
stdin payload: pipe it straight into a handler.

These exist because the recorded `WorktreeCreate` contract was wrong and nothing
caught it. `hook-create` read `worktree_path` from an event that carries `name`,
found nothing, and echoed nothing — and because a registered `WorktreeCreate`
hook *replaces* native worktree creation, that silence broke worktree creation
on every installed machine. The published docs did not carry the create schema,
so the shape was back-filled from `WorktreeRemove`, which genuinely differs.
A fixture turns that class of divergence into a failing test.

## Where the key sets come from

Not from the docs. The docs omitted `WorktreeCreate`'s input schema entirely,
and where they do describe an event they have drifted from the shipped payload
(they name `tool_output` where `PostToolUse` sends `tool_response`, and
`session_start_reason` where `SessionStart` sends `source`). The key sets here
are read out of the CLI's own payload construction sites, verified identical
across every version on disk at the time of writing (2.1.226, 2.1.237, 2.1.239,
2.1.241):

```sh
# `claude` on PATH is usually a symlink; resolve it with a bounded plain
# `readlink` loop rather than `readlink -f`/`realpath`, neither of which exists
# on the macOS half of the support bar (the reason scripts/release-lib.sh
# resolves symlinks the same way).
claude_bin=$(command -v claude)
n=0
while [ -L "$claude_bin" ] && [ "$n" -lt 16 ]; do
  link=$(readlink -- "$claude_bin")
  case $link in
    /*) claude_bin=$link ;;
    *) claude_bin=$(dirname -- "$claude_bin")/$link ;;
  esac
  n=$((n + 1))
done
LC_ALL=C grep -a -o 'hook_event_name:"<Event>"[^;]\{0,180\}' "$claude_bin"
```

`tests/test-check-hook-contracts.sh` pins each event's own keys exactly. When
the CLI changes shape, that test fails: re-derive with the command above, update
the fixture, and update the handler that reads the changed key.

## The asymmetry that caused the outage

`WorktreeCreate` carries `name` — a bare worktree name, because the hook is the
*creator* and is expected to produce the worktree and report where it put it.
`WorktreeRemove` carries `worktree_path`, an absolute path, because the worktree
already exists. The two are not variants of one shape.

`WorktreeCreate.json` is kept even though planwright no longer registers the
event, precisely so re-registering it is caught: `check-hook-contracts.sh`
refuses any registration on an event whose silence *refuses* the operation
unless the handler is declared as that operation's implementer.
