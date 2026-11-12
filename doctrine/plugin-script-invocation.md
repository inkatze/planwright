# Plugin-script invocation

**How the dispatching skills call planwright's own scripts.** The three
dispatching skills — `/execute-task`, `/orchestrate`, `/spec-kickoff` — invoke
plugin scripts (`scripts/<name>.sh`) many times per run. This doc fixes the one
invocation shape they use, so a dispatched worker does not flood on a permission
prompt for every such call. Its sections *Invoke by the shebang*, *One plain
command per Bash call* and *Test and lint runs go through the router* cover
every command any skill issues inside a dispatched worker or a tower session,
`/polish` and `/self-review` included.

Citations: REQ-D1.1, D-7; obs:344dd129, obs:885bc3c9 · custom-spec-location
REQ-G1.4.

## The convention

Resolve the plugin/planwright root **once per invocation** to a **literal
absolute path**, then invoke every `scripts/<name>.sh` the skill names by that
resolved literal absolute path. Never invoke through an unexpanded
`$VAR/scripts/<name>.sh` shape.

Resolve the root through the core root chain, defined in `spec-format`
(*The core root chain*): `scripts/resolve-root.sh install`, invoked by its path
in the copy the skill was loaded from, prints it.

A root from an earlier invocation is never reused: after an upgrade or a
plugin reload the plugin cache keeps older copies beside the installed one,
and a remembered path still runs. A session that outlives an invocation (a
standing one, or one resumed after a compaction) resolves again by running
`scripts/resolve-root.sh install` from the installed copy: the first root
`scripts/resolve-installed-roots.sh --current` prints, from any copy, or
any copy when it prints none. The root resolver warns when it runs from, or
answers with, a cached copy the record no longer names (a pin the session
inherited included); the session then runs its scripts and docs from that
first `--current` root instead. Mission control's scripts warn the same way.

Take the resolved value once, then substitute it literally at each call site:

```sh
# Resolve once:
/abs/copy/scripts/resolve-root.sh install    # prints the root, e.g. /abs/planwright
# Then call by the literal absolute path (what a worker's command actually is),
# a bundle argument being its directory under the spec root, <root> below
# (resolve-root.sh spec; specs/<spec> under the default), not the install root:
/abs/planwright/scripts/spec-validate.sh <root>/<spec>
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
`config/worker-settings.json`: the hook reads the command as written (a `$VAR`
arrives unexpanded, measured on CLI 2.1.270; it resolves only a same-command
assignment of a plain literal) and allows the known-safe set, but on its degraded
path (when `jq` is absent it defers everything) only the literal invocation shape
stays approvable. The two
are complementary — the hook is the primary path, literal-path invocation is
defense-in-depth independent of it.

## One plain command per Bash call

A literal path is not enough when the line around it is compound. The hook
approves a compound line only when it can clear every segment and defers most
compound forms, and a standing decision the operator records matches only a
literal command prefix followed by plain arguments. So a line such as
`P=/abs/planwright; cd <worktree>; $P/scripts/x.sh; echo rc=$?` reaches the operator
as a prompt even when every command in it is routine. Issue **one plain
command per Bash call** instead:

- **No `cd`.** A dispatched worker's shell starts in its own worktree, so
  `git` and scripts run there as written, with no `cd` and no `git -C`. Name
  any other directory as an argument (`git -C <dir>`, a script's
  `--checkout <dir>`).
- **No variable assignments.** Substitute every resolved value literally, the
  way the root is substituted above. A value one command prints (a config
  value, a SHA) is read from that call's result and written literally into the
  next call, never captured with `$(...)`. The one prefix kept is the step
  context: literal `PLANWRIGHT_STEP_*` assignments in front of the script
  call they serve, never exported, since each call is a fresh shell.
- **No staged scripts.** Never write a sequence into a file to run it as one
  call; issue its commands one by one.
- **No chains.** No `;`, `&&`, or `||` between commands: each command is its
  own call, issued after the previous call's result has been read.
- **No display pipes.** Never pipe into `sed`, `awk`, `head`, `tail`, `grep`,
  or `cut` to trim output for reading. Read the output whole, narrow it with
  the command's own flags (`git show <rev>:<path>`, `git log -n <k>`,
  `--format`), or use the file-reading tool. Text a command reads on stdin
  comes from a file written with the file-writing tool (`< <file>`), never
  from an `echo` or `printf` pipe. A pipe that carries data one command cannot
  produce alone, such as the commit-trailer composition, is the one kept form.
- **No loops or background jobs.** No `for`, `while` or `until`, and no `&`
  or `nohup`: a loop or a detached job is a compound line the guard defers.
  Issue each iteration as its own call, and wait on a job in the foreground.
- **Files are written with the Write tool.** Never with a heredoc, `printf`,
  `echo` or `tee` redirect; read them with the Read tool or one plain
  `grep`, `sed -n`, `head` or `cat` call on the file.
- **Exit status from the result.** The tool result already reports the exit
  code; never append `echo rc=$?` or a similar probe.

A stream-json, tmux or headless launch appends these rules to the session's system prompt
(`config/launch-shell-rules.txt`, which changes with this section), so a
session keeps them after compaction drops its brief.

A declared command step's `--line` rendering is not an exception to strip: it
runs exactly as the resolver prints it, its quoted `PLANWRIGHT_STEP_*`
assignment prefix included, since that prefix carries the step's context and
is the form the guard approves ([custom-steps](custom-steps.md)).

## Test and lint runs go through the router

Start every test or lint run, and a lefthook run, with the router:
`<root>/scripts/compute-route.sh -- <command>` (for example
`<root>/scripts/compute-route.sh -- bash tests/test-x.sh`), after any
`timeout <secs>` or `nice -n <n>` prefix. With `fleet_compute_host` set it
runs there; otherwise, or when the host is unreachable, busy or the tree has
uncommitted changes, it runs here as written. The guard approves the form
only when the command after `--` is one it approves on its own; a kind flag
or a router run any other way prompts.

## Invoke by the shebang

A script's shebang names its interpreter, so run it by its path, or through
exactly the interpreter that shebang names. Never run a script whose shebang
names bash through `sh`: where `/bin/sh` is dash, the script fails on its first
bashism with an error that names the script rather than the invocation.
`check:script-invocation` flags such a line in any skill or doctrine doc.

Citations: test-throughput REQ-E1.2 · test-throughput D-12.

## The adopter allow entry

The literal-path **allow entry** in a worker's Claude Code settings is
install-location-specific (the plugin cache path is per-home), so it stays
adopter-documented rather than shipped in `config/worker-settings.json`. The
skill-side literal-path invocation above is the portable, durable change; the
allow entry is the adopter's optional opt-in layered on top. It is documented
for adopters in `docs/overlays.md` (§ "The worker literal-path allow entry").
