# Plugin-script invocation

**How the dispatching skills call planwright's own scripts.** The three
dispatching skills — `/execute-task`, `/orchestrate`, `/spec-kickoff` — invoke
plugin scripts (`scripts/<name>.sh`) many times per run. This doc fixes the one
invocation shape they use, so a dispatched worker does not flood on a permission
prompt for every such call.

Citations: REQ-D1.1, D-7; obs:344dd129.

## The convention

Resolve the plugin/planwright root **once per invocation** to a **literal
absolute path**, then invoke every `scripts/<name>.sh` the skill names by that
resolved literal absolute path. Never invoke through an unexpanded
`$VAR/scripts/<name>.sh` shape.

Resolve the root, in order (a simplified view of the core chain
`scripts/resolve-rule-doc.sh` uses; its writer-delivery arm,
`$CLAUDE_DIR` or `~/.claude/planwright`, is elided here):

1. `$PLANWRIGHT_ROOT` — explicit override (tests, adopters);
2. else `$CLAUDE_PLUGIN_ROOT` — plugin delivery, set by Claude Code;
3. else the skill's own install directory (self-location).

Take the resolved value once, then substitute it literally at each call site:

```sh
# Resolve once. This one-liner shows steps 1-2 only: when neither var is set it
# expands to empty, and you fall back to step 3 (the skill's own install dir),
# which is not a clean one-liner and is elided here:
root="${PLANWRIGHT_ROOT:-$CLAUDE_PLUGIN_ROOT}"     # e.g. /abs/planwright
# Then call by the literal absolute path (what a worker's command actually is):
/abs/planwright/scripts/spec-validate.sh specs/<spec>
```

## Why the literal shape matters

Claude Code's static allowlist matches the **literal command token, never its
expansion**, and offers no persistent-allow for a shape it flags "cannot be
statically analyzed." A `$VAR/scripts/<name>.sh` invocation is exactly such a
shape: opaque to the allowlist, so a dispatched worker is prompted for every
call. A fully-resolved literal absolute path is statically analyzable — Claude
Code can offer a persistent-allow, and an adopter's literal-path allow entry can
match it.

This is the root-cause fix beneath the auto-approve `PreToolUse` hook wired into
`config/worker-settings.json`: the hook inspects the *expanded* command and
allows the known-safe set, but on its degraded path (when `jq` is absent it
defers everything) only the literal invocation shape stays approvable. The two
are complementary — the hook is the primary path, literal-path invocation is
defense-in-depth independent of it.

## The adopter allow entry

The literal-path **allow entry** in a worker's Claude Code settings is
install-location-specific (the plugin cache path is per-home), so it stays
adopter-documented rather than shipped in `config/worker-settings.json`. The
skill-side literal-path invocation above is the portable, durable change; the
allow entry is the adopter's optional opt-in layered on top. It is documented
for adopters in `docs/overlays.md` (§ "The worker literal-path allow entry").
