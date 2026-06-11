# planwright doctrine

This directory holds planwright's externalized rule docs: the framework
doctrine that skills reference at runtime instead of inlining (REQ-D1.4,
REQ-I1.1). The doctrine docs themselves (Discovery Rigor, Validation Rigor,
Refactor Instinct, Research Rigor, Security posture, Finding Categorization,
the composability principle, engineering doctrine) land with the intelligence
migration and doctrine tasks; this file pins the resolution convention they
ship under.

## Resolution convention

Skills, hooks, and scripts resolve a rule doc by basename through one stable
path that works in both delivery modes, with no mode detection:

```text
${PLANWRIGHT_ROOT:-${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/planwright}}/doctrine/<doc>.md
```

- **Plugin delivery (primary, D-24):** Claude Code sets `CLAUDE_PLUGIN_ROOT`
  to the plugin's install directory; docs resolve plugin-relative.
- **Writer delivery (fallback):** `scripts/install.sh` copies this directory
  to `<claude-dir>/planwright/doctrine/` (`<claude-dir>` is `$CLAUDE_DIR` when
  set, else `~/.claude`); the fallback arm of the chain finds it there.
- **Override:** `PLANWRIGHT_ROOT` pins an explicit root (tests, adopters
  embedding planwright elsewhere). It wins over both.

`scripts/resolve-rule-doc.sh <doc-name>` implements the chain (validating the
name against the `^[a-z0-9][a-z0-9-]*$` identifier discipline before any path
is formed) and prints the resolved path; prefer it over hand-building paths.

Doc names are kebab-case basenames without the `.md` suffix, e.g.
`discovery-rigor`, `finding-categorization`.

## Adopter extensions

Adopters supply project-specific tooling and rigor without editing these core
docs (REQ-D2.2): project-level conventions live in the adopting repo (its
`CLAUDE.md`, config, and local override), not here. Core docs change only
through planwright's own spec flow.
