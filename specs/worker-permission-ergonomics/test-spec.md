# Worker Permission Ergonomics — Test Spec

**Status:** Draft
**Last reviewed:** 2026-07-18
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: the hook's behavior is verified almost entirely by `[test]`
(the adversarial suite `tests/test-worker-command-guard.sh`, run under
`mise run test` in CI), backed by `[design-level]` for the tool-grounded
quality guards and `[manual]` for the end-to-end dispatch confirmation that no
prompt-flood occurs under the wired profile. The security-critical target is
ZERO false-allows; the suite is the primary evidence.

### REQ-A1.1 — Auto-approve known-safe shapes, no LLM in path [test + design-level]

Suite fixtures assert `permissionDecision: allow` for representative known-safe
commands and defer for the rest. `[design-level]`: the hook is pure shell + `jq`
with no network or model call — reviewable by reading the script; no LLM
invocation exists in the decision path.

### REQ-A1.2 — Allow-only, never deny/ask [test]

Suite asserts the hook's stdout is either a well-formed `allow` decision or
empty (defer, exit 0); no fixture ever produces a `deny` or `ask` decision.

### REQ-A1.3 — Allow cannot override deny/ask; deny block verbatim [test + design-level]

`[test]`: a fixture with a deny-listed command (e.g. `git push --force`) is not
auto-approved by the hook (it defers, leaving the `deny` rule to fire).
`[design-level]`: Claude Code's documented `deny`→`ask`→`allow` precedence means
a hook `allow` cannot un-block a denied command; the wiring test (REQ-C1.1)
asserts the `deny` block is byte-for-byte unchanged.

### REQ-A1.4 — Every-segment-safe compound analysis [test]

Fixtures cover compound commands split on `;`, `&&`, `||`, `|`, `&`, and
newlines: a compound where all segments are safe allows; one where any segment
is unsafe defers (regression: `echo ok; rm -rf x` MUST defer). Ambiguity
fixtures — unbalanced quotes, `$(…)`/backtick/`<(…)`/`>(…)` substitution, a
non-`/dev/null` write-redirect, an unknown verb — all defer.

### REQ-A1.5 — The enumerated known-safe set [test]

Fixtures exercise each known-safe class: direct `scripts/*.sh` and `tests/*.sh`
(and via `bash`/`sh <path>`, never `-c`); read-only coreutils/builtins (with
`find -delete`/`-exec` and `sed -i` deferring); read-only `git` subcommands;
lint/test runners (`shellcheck`, `markdownlint(-cli2)`, `yamllint`, `bats`,
`mise run`/`tasks`); read-only `gh`; control structures with verified
bodies/conditions; and `fish -c "<safe-inner>"` allowing while
`fish -c "<unsafe-inner>"` defers.

### REQ-A1.6 — The explicit defer set [test]

Fixtures assert defer for `rm`, `curl … | sh`, `sudo`, `bash -c`/`sh -c`,
in-place edits, non-`/dev/null` write-redirects, command substitution, mutating
`git`/`gh` subcommands, and `kill`/`pkill`.

### REQ-A1.7 — Bash-only [test]

Fixtures with `tool_name` other than `Bash` (e.g. `Read`, `Write`, `Edit`)
defer unconditionally.

### REQ-B1.1 — Portable POSIX/bash, pure-shell analysis [test + design-level]

`[test]`: the suite runs the hook under `/bin/bash` (the repo's bash 3.2 floor
via `run-tests.sh`). `[design-level]`: `shellcheck`/`shfmt` in CI plus review
confirm no python/fish/mise/tmux dependency and that analysis is pure shell.

### REQ-B1.2 — jq extraction with degrade-to-defer [test]

A fixture invoking the hook with `jq` forced absent (PATH-stripped) asserts
defer-all; a normal fixture asserts correct extraction of `tool_name` and a
command containing quotes/escapes.

### REQ-B1.3 — Fail-safe on malformed input [test]

Malformed/empty stdin, non-JSON input, missing fields, and `fish -c` nested
past the bounded recursion depth all defer without error.

### REQ-B1.4 — No untrusted echo; fixed reason [test + design-level]

`[test]`: the emitted `permissionDecisionReason` is the fixed string and does
not contain the analyzed command's bytes. `[design-level]`: review confirms no
raw command content is written to stderr/stdout in a terminal-driving way.

### REQ-B1.5 — Held to the framework-script security bar [design-level]

The script lives under `scripts/`, is covered by `mise run lint` (shellcheck +
shfmt) and the secret scan, and is small enough to read before trusting — the
security-posture framework-script bar, verified by its presence in those gates.

### REQ-B1.6 — Adversarial suite: zero false-allows, deny never approved [test]

The suite itself is the verification: ≥30 adversarial cases (the prototype set
plus surfaced regressions), a positive assertion of zero false-allows across
the corpus, and an assertion that no deny-listed command is ever auto-approved.
Runs under `mise run test` / CI.

### REQ-C1.1 — Wired into worker-settings via ${CLAUDE_PLUGIN_ROOT} [test + manual]

`[test]`: a JSON-shape assertion confirms `config/worker-settings.json` carries
a `PreToolUse` (Bash) hook referencing the script via `${CLAUDE_PLUGIN_ROOT}`,
`defaultMode` is `default`, and the `deny` block is unchanged from baseline.
`[manual]`: a dispatched worker under the wired profile runs a full task without
a prompt-flood (the end-to-end confirmation the prototype demonstrated on
PR #232).

### REQ-C1.2 — Worker-scoped only [test + design-level]

`[test]`: an assertion that the auto-approve hook appears in
`config/worker-settings.json` and NOT in the plugin-global `hooks/hooks.json`.
`[design-level]`: review confirms the tower and human interactive sessions do
not load this hook.

### REQ-C1.3 — Human-reviewed delivery; _about updated [design-level]

Review confirms the `_about` field documents the hook and the human-sign-off
posture, that delivery remains manual merge/reference (no `settings.json`
auto-edit by any skill), and that the fragment still reads as a
human-review-before-use artifact.

### REQ-D1.1 — Literal script-path invocation in the dispatching skills [test + manual]

`[test]`: a grep-based assertion over `/execute-task`, `/orchestrate`, and
`/spec-kickoff` confirms plugin-script call sites use a resolved literal path
and no `"$VAR/scripts/x.sh"` invocation shape remains at those sites.
`[manual]`: a dispatched worker confirms such invocations are now
statically analyzable (offered a persistent-allow, or matched by a literal-path
allow entry) even with the hook disabled.
