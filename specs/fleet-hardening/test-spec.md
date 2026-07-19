# Fleet Hardening — Test Spec

**Status:** Ready
**Last reviewed:** 2026-07-19
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: predominantly `[test]`, since every mechanism is deterministic script logic
(REQ-E1.3) and straightforwardly fixture-testable, including negative assertions (no `capture-pane`
on the push path, no `send-keys` in the decision channel, no `allow` for a deny-listed command, no
local-`main` advance after a fetch). `[manual]` is reserved for the platform-contract confirmations
that depend on the running Claude Code version (whether the `Notification` hook fires for a real
fork-park; the tmux client-switch behavior of the native launch primitive). `[design-level]` covers
the checks whose signal is a design judgment rather than a mechanism's output — the doctrine statement
(REQ-E1.1) and the review-confirmed halves of REQ-E1.2 / REQ-E1.4.

## REQ-A — Attention & decision signals

### REQ-A1.1 — Fork-park pushes `awaiting-human` via `Notification` [test + manual]

`[test]`: a fixture worker firing a `Notification` hook stub asserts the attention store gains an
`awaiting-human` row carrying a reason and a timestamp within one event cycle, and asserts no
`capture-pane` is invoked on that path; a payload-gating fixture asserts a permission-park /
idle-nudge `Notification` does not push a false `awaiting-human`; a resume fixture asserts the row is
cleared / superseded on resume (the exit edge). **Manual ownership:** kickoff pins the doc-level
fires-for-fork-park fact; **Task 2 execution** runs the end-to-end `[manual]` confirmation — against
the running Claude Code version, park a real worker at an `AskUserQuestion` fork and confirm the
`Notification` hook fires and the record is pushed (the version-sensitive platform-contract
confirmation D-2 flags).

### REQ-A1.2 — Tower learns by event watch, not pane poll [test]

A fixture asserts the tower-side watch reacts to a store-row change as an event (the watch callback
fires on the write), and asserts the fork-park signal path issues no `capture-pane` / pane-grep of
the worker.

### REQ-A1.3 — Fallback detector: footer-only, positive-anchor, debounced [test]

Three fixtures: (a) a pane with busy words in scrollback ABOVE an idle footer classifies idle (no
scrollback false-match); (b) a main-idle / background-busy pane (footer `Waiting for N background
agent`, no `esc to interrupt`) classifies busy; (c) a single-frame flap is suppressed by the
two-frame debounce. A fourth asserts the detector runs only as the reconcile backstop — where no hook
is registered, or where a registered hook has not pushed within the bounded reconcile interval —
never where a fresh hook push exists.

### REQ-A1.4 — Decision record carries the full labeled option set [test]

A fixture fork asserts the written decision record contains every option's label and the worker's
recommendation, and that a reader selecting by label resolves to the correct option even when the
option order is the reverse of a sibling prompt (the 2026-07-19 Skip/Apply reorder case).

### REQ-A1.5 — Answer delivered by label, never `send-keys` [test]

A fixture asserts the answer is delivered through the attributed buffer-paste / structured-marker
path selected by label, and a negative assertion greps the channel implementation for any `send-keys`
menu-navigation path and asserts there is none.

## REQ-B — Dispatch hardening

### REQ-B1.1 — Ghost-text pin applied by the launch primitive [test]

A launched-worker fixture asserts `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` is present on the
worker process environment, set by the dispatch primitive's own construction (asserted without any
SKILL-prose step in the path).

### REQ-B1.2 — Pinned launch shape is auto-approved (no flood, no bare fallback) [test]

A fixture feeds the wrapped launch command through the `worker-command-guard` decision path and
asserts it is auto-approved (no permission prompt), so the pin-carrying launch never falls back to a
bare launch; a regression fixture reconstructs the 2026-07-19 bare-launch shape and asserts it is no
longer the path taken.

### REQ-B1.3 — Glob-footgun check [test]

The check flags a `Bash(<path>/:*)` directory-scoped rule and passes a `Bash(<path>/*)` rule; a
guard-against-false-positive fixture asserts the legitimate command globs (`Bash(git status:*)`,
`Bash(mise run:*)`, etc.) are NOT flagged. Runs under `mise run check`. `[design-level]`: review
confirms the `Bash(<dir>/*)`-not-`:*` rule is documented in the adopter allow-rule guidance and
cross-referenced from the ghost-text (D-5) and tower-guard (D-8) docs (the documentation half of D-6,
otherwise unverified).

### REQ-B1.4 — tmux dispatch yields a D-36 branch with no rename [test + manual]

`[test]`: a fixture asserts the dispatch primitive's resulting branch name matches the D-36 grammar
`planwright/<spec>/task-<id>` with no post-launch `git branch -m` step in the path. `[manual]`:
confirm on a real dispatch that `--tmux=classic` is used (not plain `--tmux`) and that the
client-switch caveat is mitigated so a watching tower is not disrupted.

## REQ-C — Tower self-governance

### REQ-C1.1 — Tower profile wires a deterministic guard over the tower safe set [test]

A fixture asserts the tower-settings profile wires the tower command-guard as a PreToolUse hook and
that a representative tower orchestration command (a tmux relay, a `claude --worktree` launch, a
planwright script by literal path) is deterministically allowed by the guard.

### REQ-C1.2 — Distinct safe set; dangerous ops denied regardless of guard [test]

Assert the tower safe set differs from the worker safe set (a tower-only command allowed here is not
in the worker set, and vice versa); assert the guard is allow-only (never emits deny/ask); assert
every dangerous op is denied by the profile deny block regardless of guard output, across all
surfaces: the shell ops (merge, force-push in every spelling `--force`/`-f`/`--force-with-lease`/
`+`-refspec, amend, squash, rebase, `gh pr merge`, never-ready guardrails), default-branch writes and
local-`main` mutation (`git push …:main`, `reset --hard`, `branch -f`, `update-ref`), and the
equivalent GitHub MCP tools (`mcp__github__merge_pull_request`, `update_pull_request` draft→ready,
`push_files` / `create_or_update_file` on the default branch). Assert the allow-set never matches
`claude --worktree … --dangerously-skip-permissions` / `--permission-mode` nor `tmux send-keys` /
`kill-session`; assert the sanctioned kickoff spec-PR ready-flip is distinguished from the denied
task-PR / tower ready-marking.

### REQ-C1.3 — Adversarial suite: zero false-allows, outcome-asserted [test]

An adversarial suite over the tower safe set asserts zero false-allows, including flag-appended
escalation probes (a `claude --worktree` command with `--dangerously-skip-permissions` /
`--permission-mode` appended is not allowed); asserts the guard fails closed on error / absence; and
asserts the *outcome* (the guard never emits `allow` for any deny-listed command) rather than relying
on documented Claude Code allow-vs-deny precedence (obs:4dda9fe1). The allow-before-classifier
evaluation order is recorded as a `[design-level]` / platform-contract note, not a guard-output
assertion. No LLM is invoked in the guard decision path (negative assertion).

## REQ-D — Freshness & propagation

### REQ-D1.1 — Freshness gate fetches and gates against `origin/main`, local `main` untouched [test]

A fixture with local `main` behind `origin/main` asserts the gate fetches `origin`, evaluates
currency and re-points `anchor-integrity`'s existing content-anchor check against `origin/main` (it
sees the newer anchor; this bundle re-points the ref, it does not implement anchor-hash comparison),
and that local `main` is byte-for-byte unchanged after the gate. A `no-remote` fixture asserts
structural graceful degradation; a distinct transient-fetch-failure fixture (present remote, fetch
errors) asserts the gate does not silently proceed against a stale ref (it retries, then blocks or
flags), separate from the `no-remote` path.

### REQ-D1.2 — Merge detection uses fetched `origin/main` [test]

A fixture where a task PR merged on `origin` but whose merge trailer has not reached local `main`
asserts the task is detected merged (not re-dispatched) after the fetch-based detection. A `no-remote`
/ transient-fetch fixture asserts merge detection degrades gracefully (does not falsely mark a task
merged or unmerged) when the fetch is unavailable.

### REQ-D1.3 — Tower observations reach `main` via a sanctioned path [test]

A fixture tower branch carrying committed observations, run through the bookkeeping path, asserts a
chore PR (or equivalent sanctioned carry) is produced landing them toward `main`; a no-observation
run asserts a clean no-op; assert the path never merges the PR and never advances shared local
`main`.

## REQ-E — Carried floors & control-plane doctrine

### REQ-E1.1 — Control-plane doctrine statement present and cited [design-level]

`[design-level]`: the doctrine statement exists in the design log (D-1, its durable home a future
tower-builder reads), extends `fleet-autonomy` D-10/D-18, and is cited by REQ-E1.1 and from the Goal
(in `requirements.md`) as the D-1 altitude record. Verified by review against the autopilot-reflex
altitude-gate expectation, not by a runtime test.

### REQ-E1.2 — No redefinition of `fleet-autonomy`'s shipped surface [test + design-level]

`[design-level]`: review confirms no task redefines the shipped attention store, classifier, or
wired hooks. `[test]`: owned by Tasks 2 and 4 (which extend the store) — the existing `fleet-autonomy`
suite continues to pass unchanged, AND a positive assertion confirms the specific shipped surfaces
(the attention-store schema, the five-state classifier, the five wired hooks) remain present and
behaviorally identical, so the regression is not a vacuous green from an untouched suite.

### REQ-E1.3 — No LLM in any control-plane decision path [test]

For each mechanism this bundle ships (attention push, fallback detector, decision channel, launch
pin, glob check, tower guard, freshness gate, observation carry), a negative assertion confirms no
model/API call occurs in its decision path.

### REQ-E1.4 — No auto-merge / autonomous-ready beyond the kickoff exception [test + design-level]

`[design-level]`: review confirms no task introduces auto-merge or autonomous PR-ready-marking.
`[test]`: the tower-guard deny block (REQ-C1.2) asserts `gh pr merge` and the never-ready guardrails
are denied, giving the floor a mechanical anchor.
