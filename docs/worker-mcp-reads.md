# Read-only MCP tools in worker sessions

`config/worker-settings.json` ships no MCP tool in its allow list, so a worker's
MCP reads (an issue tracker, a docs server) prompt by default. A headless worker
cannot answer a prompt, so an adopter who relies on a read-only MCP server
approves its reads once, in the worker's settings.

## Adopting a read

Add one allow entry per tool, spelled with the exact tool name:

```json
{ "permissions": { "allow": ["mcp__github__get_pull_request", "mcp__github__list_issues"] } }
```

Rules:

- **Exact names only.** No `*` in an `mcp__` allow entry, and no
  `mcp__<server>` entry that approves a whole server: a name pattern cannot tell
  a read from a write, and servers add tools between versions.
  `tests/test-worker-settings-hook-wiring.sh` fails on a wildcard in the shipped
  fragment.
- **Reads only.** Check the tool's description on the server before adding it;
  a tool named `get_*` or `list_*` may still write.
- **The floor stays first.** The shipped deny block names the GitHub MCP write
  tools (`merge_pull_request`, `push_files`, `create_or_update_file`,
  `delete_file`, `update_pull_request`), and Claude Code evaluates deny before
  allow, so an allow entry never un-blocks them.

Entries live in the adopter's own worker settings or a machine-local overlay,
never in the shipped fragment, so each adopter chooses which servers to trust.
