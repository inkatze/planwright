# Worker Permission Ergonomics — Test Spec

**Status:** Ready
**Last reviewed:** 2026-07-18
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: the hook's behavior is verified almost entirely by `[test]`
(the adversarial suite `tests/test-worker-command-guard.sh`, run under
`mise run test` in CI), backed by `[design-level]` for the tool-grounded
quality guards and `[manual]` for the end-to-end dispatch confirmation that no
prompt-flood occurs under the wired profile. The security-critical target is
ZERO false-allows; the suite is the primary evidence.

## REQ-A — The auto-approve hook

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
auto-approved by the hook (it defers, leaving the `deny` rule to fire). Plus the
deny-precedence **collision** fixture (REQ-B1.6): a command matching BOTH the
known-safe set AND a rule in the actual `config/worker-settings.json` `deny`
block, asserted not auto-approved — the case that actually exercises precedence,
derived from the real `deny` block so a future overlapping deny entry is caught.
`[design-level]`: Claude Code's documented `deny`→`ask`→`allow` precedence means
a hook `allow` cannot un-block a denied command; the wiring test (REQ-C1.1)
asserts the `deny` block is byte-for-byte unchanged.

### REQ-A1.4 — Every-segment-safe compound analysis [test]

Fixtures cover compound commands split on `;`, `&&`, `||`, `|`, `&`, and
newlines: a compound where all segments are safe allows; one where any segment
is unsafe defers (regression: `echo ok; rm -rf x` MUST defer). Ambiguity
fixtures — unbalanced quotes, `$(…)`/backtick/`<(…)`/`>(…)` substitution, a
non-`/dev/null` write-redirect, an unknown verb — all defer. Redirect fixtures:
`>&file`, `>|`, `&>`, `>>`, and a leading redirect (`>f cat x`) all defer;
**positive** fd-dup fixtures (`cat x >/dev/null 2>&1`, `cmd >&2`, `cmd 2>&-`) must
still ALLOW (the fd-dup carve-out does not over-defer the `>/dev/null 2>&1`
idiom — regression guard).

### REQ-A1.5 — The enumerated known-safe set [test]

Fixtures exercise each known-safe class from the enumerated allowlist (not a
category match): direct `scripts/*.sh` and `tests/*.sh` (and via `bash`/`sh
<path>`, never `-c`); enumerated read-only coreutils/builtins (with
`find -delete`/`-exec`, `sed -i`, and `sed` `w`/`s///w` file-write commands all
deferring); enumerated read-only `git` subcommands with flag guards
(`git status`/`log`/`diff` allow, `git branch -m` and `git config k v` defer);
lint/test runners (`shellcheck`, `markdownlint(-cli2)`, `yamllint`, `bats`,
`mise run`/`tasks`); read-only `gh`; control structures with verified
bodies/conditions; and `fish -c "<safe-inner>"` allowing while
`fish -c "<unsafe-inner>"` defers, including a nested-but-within-depth buried
unsafe (`fish -c "fish -c '<unsafe>'"` defers by recursive analysis, not only by
hitting the depth cap). Guard-completeness fixtures: `find -execdir`/`-ok`/
`-fprint*` and `sed W` defer; `git branch -D`/`git remote add`/`git remote
set-url`/`git tag -d`/`git stash drop`/`git stash pop` defer while the positive
list-forms (`git branch`, `git stash list`) allow.

### REQ-A1.6 — The explicit defer set [test]

Fixtures assert defer for `rm`, `curl … | sh`, `sudo`, `bash -c`/`sh -c`,
in-place edits, non-`/dev/null` write-redirects, command substitution, mutating
`git`/`gh` subcommands, `kill`/`pkill`, command-runner verbs that wrap an
arbitrary sub-command (`env rm …`, `xargs rm`, `timeout 5 rm …`, `nohup`,
`nice`, `setsid`, `stdbuf`, `chroot`), writer coreutils (`tee`, `dd`, `cp`, `mv`,
`install`, `truncate`, `ln`, `touch`), and text-tool write-escapes (`sed 'w
file'`, `awk 'print > "file"'`, and the severest, `awk 'system("rm -rf x")'`).

### REQ-A1.7 — Bash-only [test]

Fixtures with `tool_name` other than `Bash` (e.g. `Read`, `Write`, `Edit`)
defer unconditionally.

### REQ-A1.8 — Safe-invocation rule: unknown flag/arg defers [test]

Fixtures assert defer for un-enumerated flags/args on otherwise-allowlisted
verbs: `sort -o FILE`, `uniq in out`, `markdownlint --fix`, `date -s`, `file -C`,
`find -okdir`/`-fls`, and any `git` carrying a pre-subcommand global option
(`git -c core.pager=… log`, `git -c alias.x='!cmd' x`, `git -C /elsewhere log`,
`git --exec-path=… …`). A recognized-safe invocation of the same verb (`sort
input`, `git log`) allows — the guard is per-invocation, not per-verb.

### REQ-A1.9 — Grammar-conservative deferral [test]

Fixtures assert defer for: inline env-assignment prefixes (`BASH_ENV=x bash
ok.sh`, `LD_PRELOAD=x cat f`, `GIT_PAGER='!cmd' git log`); a path-prefixed verb
(`/tmp/evil/cat f`, `./cat f`) that is not the enumerated repo-script case; fish
bare-paren substitution inside `fish -c` (`fish -c "echo (rm -rf x)"`); subshell
/ brace grouping (`(rm -rf x)`, `{ rm -rf x; }`); bundled/long `-c` (`bash -ec
'rm'`, `fish --command 'rm'`); and a redirect-tokenization case proving `>|`/`&>`
are not mis-split into a spurious safe segment (`echo x >| stat` defers).

### REQ-A1.10 — Script/test/bats path containment [test]

Fixtures assert that an enumerated `scripts/*.sh`/`tests/*.sh`/`bats <file>`
invocation whose (expanded) path resolves OUTSIDE the repository defers
(`bash ../../../tmp/evil/scripts/x.sh`, `bats /tmp/evil.bats`), while an
in-repository path allows — the containment check backing the trust boundary.

## REQ-B — Implementation, robustness, and security

### REQ-B1.1 — Portable POSIX/bash, pure-shell analysis [test + design-level]

`[test]`: the suite runs the hook under `/bin/bash` (the repo's bash 3.2 floor
via `run-tests.sh`), and an **inert-data side-effect probe** — a fixture whose
command would create an observable side effect if the analyzer expanded or
evaluated it (e.g. `$(touch MARKER)` / a backtick that writes `MARKER`) —
asserts the marker file is never created (analysis never executes the command).
`[design-level]`: `shellcheck`/`shfmt` in CI plus review confirm no
python/fish/mise/tmux dependency and that analysis is pure shell.

### REQ-B1.2 — jq extraction with degrade-to-defer [test]

A fixture invoking the hook with `jq` forced absent (PATH-stripped) asserts
defer-all; a normal fixture asserts correct extraction of `tool_name` and a
command containing quotes/escapes.

### REQ-B1.3 — Fail-safe on malformed input [test]

Malformed/empty stdin, non-JSON input, missing fields, and `fish -c` nested
past the bounded recursion depth all defer without error.

### REQ-B1.4 — No untrusted echo; fixed reason [test + design-level]

`[test]`: the emitted `permissionDecisionReason` is the fixed string; a fixture
whose command carries a distinctive **marker token** asserts the marker is absent
from the reason (the no-reflection check exercises a real reflection path, not
just a benign command). `[design-level]`: review confirms no raw command content
is written to stderr/stdout in a terminal-driving way.

### REQ-B1.5 — Held to the framework-script security bar [design-level]

The script lives under `scripts/`, is covered by `mise run lint` (shellcheck +
shfmt) and the secret scan, and is small enough to read before trusting — the
security-posture framework-script bar, verified by its presence in those gates.

### REQ-B1.6 — Adversarial suite: zero false-allows, deny never approved [test]

The suite itself is the verification: ≥30 adversarial cases (the prototype set
plus surfaced regressions), a positive assertion of zero false-allows across
the corpus, and an assertion that no deny-listed command is ever auto-approved.
The corpus MUST include the kickoff-surfaced false-allow vectors:
command-runner wrappers (`env`/`xargs`/`timeout`/`nohup`/`nice`/`setsid` of an
`rm`), writer coreutils (`tee`/`dd`/`cp`/`mv`/`install`/`truncate`/`ln`/
`touch`), and text-tool write-escapes (`sed 'w file'`, `awk 'print > "f"'`), each
asserted to defer. Runs under `mise run test` / CI.

### REQ-B1.7 — Fail-closed emission contract [test]

Fixtures assert: the defer path emits empty stdout and exits 0; an internal
error / signal path never emits a partial `allow` and never exits 2 (a fixture
forcing an error asserts exit 0 + empty stdout, not the CC block signal); a
present-but-empty (`""`) and a non-string `tool_input.command` both defer; an
invoked-but-cannot-start script path defers. `[test]` where a failure can be
induced under the suite; the no-hang / bounded-runtime guarantee is exercised
with a large/pathological input asserting prompt termination.

## REQ-C — Wiring and delivery

### REQ-C1.1 — Wired into worker-settings via ${CLAUDE_PLUGIN_ROOT} [test + manual]

`[test]`: a JSON-shape assertion confirms `config/worker-settings.json` carries
a `PreToolUse` (Bash) hook referencing the script via `${CLAUDE_PLUGIN_ROOT}`,
`defaultMode` is `default`, and the `deny` block is unchanged from baseline.
`[manual]`: a dispatched worker under the wired profile runs a full task without
a prompt-flood. This confirmation MUST be re-run against the shipped pure-shell
hook (Task 1); the PR #232 evidence covered the python prototype, not the port,
so it does not transfer.

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

## REQ-D — Root-cause: literal script-path invocation

### REQ-D1.1 — Literal script-path invocation in the dispatching skills [test + manual]

`[test]`: a grep-based assertion over `/execute-task`, `/orchestrate`, and
`/spec-kickoff` confirms plugin-script call sites use a resolved literal path
and no `"$VAR/scripts/x.sh"` invocation shape remains at those sites.
`[manual]`: a dispatched worker confirms such invocations are now
statically analyzable (offered a persistent-allow, or matched by a literal-path
allow entry) even with the hook disabled.
