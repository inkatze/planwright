# Fleet Hardening — Test Spec

**Status:** Draft
**Last reviewed:** 2026-10-04
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: predominantly `[test]`, since every mechanism is deterministic script logic
(REQ-E1.3) and straightforwardly fixture-testable, including negative assertions (no `capture-pane`
on the push path, no `send-keys` in the decision channel, no `allow` for a deny-listed command, no
local-`main` advance after a fetch). `[manual]` is reserved for the platform-contract confirmations
that depend on the running Claude Code version (whether the `Notification` hook fires for a real
fork-park; on a real tmux dispatch, that the detached launch returns, leaves the operator's client
in place, and starts a worker whose own environment carries the pin and identity, and that the
worker's `SessionStart` hook fires). `[design-level]` covers
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
never where a fresh hook push exists. A fifth asserts a pane with no positive at-prompt anchor (a
blank / loading screen, no busy marker either) classifies NOT idle — the direct test of the
positive-anchor requirement, so a starting-up worker is never misread as idle-at-fork.

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

`[test]`: a fixture asserts the dispatch primitive's resulting branch name matches the bootstrap D-36 grammar
`planwright/<spec>/task-<id>` with no post-launch `git branch -m` step — created by the single scoped
`git worktree add -b` call (D-7), with the mangled `worktree-<suffix>` name provably not the output,
`<base>` pinned to the freshly-fetched `origin/main`, and `<spec>`/`<id>`/`<suffix>` validated against
the D-36 grammar before interpolation (a metacharacter/`..`-bearing value is rejected — no shell
execution, no path escape). A guard over the bundle's dispatch/tower sources asserts the dispatch
primitive is the only bundle path that shells out to `git worktree`. Collision/orphan fixtures assert
a *live* concurrent/repeat dispatch aborts as already-in-flight (via `git worktree add -b`'s atomic
non-zero exit), while a *stale* orphan (dead branch/worktree, empty leftover `<suffix>` dir, or partial
create) is GC-adopted/rolled back so the dispatch proceeds; the create exit-code gates the attach. The
client-switch mitigation is asserted by fixture (designed: detached launch or capture-and-restore), the
tower deny floor is asserted to deny the dangerous `git worktree` forms, and a negative assertion
confirms no model/API call in the branch-naming path (REQ-E1.3). `[manual]`: confirm on a real dispatch
from inside a tmux client that the dispatch returns its report, the operator's client stays on its own
session, and the worker runs in the placed worktree on the D-36 branch (the detached launch, D-10;
this replaced the former `--tmux=classic` confirmation at the 2026-10-04 extension, since no tmux-rung
worker launches with that shape any more).

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
`push_files` / `create_or_update_file` / `delete_file` on the default branch). Assert the allow-set never matches
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

For each of the nine mechanisms this bundle ships (attention push, fallback detector, decision
channel, launch pin, glob check, tower guard, freshness gate, observation carry, dispatch branch
naming), a negative assertion confirms no model/API call occurs in its decision path.

### REQ-E1.4 — No auto-merge / autonomous-ready beyond the kickoff exception [test + design-level]

`[design-level]`: review confirms no task introduces auto-merge or autonomous PR-ready-marking.
`[test]`: the tower-guard deny block (REQ-C1.2) asserts `gh pr merge` and the never-ready guardrails
are denied, giving the floor a mechanical anchor.

## REQ-F — tmux launch behavior

### REQ-F1.1 — The launch returns once the worker has started [test + manual]

`[test]`: on the Task 11 harness, a dispatch whose stub worker keeps running returns within the
fixture's bound with its report printed and the checkout's flight lock released (a second flight
dispatch from the same checkout proceeds), and its exit status reflects the launch outcome, not
the worker's. The bounded case from the parked flight's candidate commit, which hangs on the old
launch, is kept as the regression. `[manual]`: Task 12's real-dispatch confirmation.

### REQ-F1.2 — No tmux client is moved [test + manual]

`[test]`: the stub tmux records every subcommand it receives; across task and flight dispatches
no `switch-client`, `attach-session`, or other client-moving call appears, and the session is
created with `-d`. `[manual]`: Task 12's real dispatch leaves the operator's client on its session.

### REQ-F1.3 — The worker starts in the placed worktree [test]

The stubbed session's start directory equals the physical placed worktree, and neither `--worktree`
nor `--tmux` appears in the worker argv. A regression fixture with the placed branch checked out
elsewhere asserts no second worktree and no `worktree-<suffix>` branch appear after the launch.

### REQ-F1.4 — The pin reaches the worker under a bare server environment [test]

With the stub server's environment lacking every pinned value, the worker process's environment
carries `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false` and the resolved planwright root; a stub
launch that applies the wrapper outside the session fails the fixture (REQ-H1.2's harness property
is what makes this assertion able to fail).

### REQ-F1.5 — The worker carries its registry identity [test + manual]

`[test]`: for a task dispatch and a flight dispatch, the worker's environment carries
`PLANWRIGHT_WORKER_HANDLE` and `PLANWRIGHT_WORKER_SCOPE` equal to the registry record's handle and
scope; the wrapper refuses a malformed or half-supplied identity with exit 2 and launches nothing;
a liveness hook run with that environment records a transition for the handle.
`[manual]`: on Task 12's real dispatch, the worker's process environment shows both variables and
its fleet-status row is distinguishable from an unlaunched unit.

## REQ-G — tmux launch safety

### REQ-G1.1 — Format-expanded values hold to the charset [test]

Fixtures feed a worktree path and a session-name input each carrying `#`, `#(…)`, a space, and a
control byte; each is refused with a message naming the charset, the stub tmux receives no call at
all, and no probe file a `#(…)` would create exists. A charset-conforming path launches. The
liveness probes are asserted to run the same check before their `has-session` calls.

### REQ-G1.2 — Physical path; a missing start directory is refused [test]

A worktree reached through a symlinked ancestor is launched with its physical path; a start
directory removed between create and launch is refused before `new-session`, and the stub tmux
receives no session creation.

### REQ-G1.3 — Every live launch passes the path-escape guard [test]

A live standalone `attach` is refused with a usage error and no tmux call, while `attach --dry-run`
still prints its plan; the dispatch arm's guard fixtures (symlinked `.claude`, symlinked
`.claude/worktrees`, symlinked leaf, a worktree resolving outside the primary checkout's worktree
root) each refuse with no tmux call.

### REQ-G1.4 — Repo-qualified names; collisions before side effects; rollback [test]

The computed session name is `<base>-<hash6>_<suffix'>` with every byte inside the session-name charset, a
dotted task id written with `_`, and two checkouts sharing a basename producing different names. A
live session already holding the name aborts the dispatch as already-in-flight before the
worktree, branch, marker, or registry record exists (each asserted absent). A stub that makes
`new-session` fail as a duplicate after the side effects leaves the just-created worktree and
branch removed, the marker cleared, and a superseding terminal registry record written.

### REQ-G1.5 — Fail-closed CLI resolution and startup confirmation [test + manual]

`[test]`: a `claude` resolving to a relative path, a missing file, or a non-executable file is
refused with exit 127 before any durable side effect. Task 13's outcome fixtures: a confirming
stub worker reports started (exit 0); a session that exits before confirming reports
failed-at-startup with its documented status; a session that stays up unconfirmed past the
shortened cap reports started-unconfirmed with its documented status and the handles, and
each shipped caller of the primitive treats it as placed; a store row stamped before the dispatch start is not a
confirmation. `[manual]`: on a real dispatch, the worker's `SessionStart` arm fires and the
dispatch reports started.

### REQ-G1.6 — The death handle comes from session creation [test]

The registered death handle equals the session name and window id the stub's `-P -F` output
printed, and a decoy pane whose working directory is the worktree (created after the dispatch
start) does not change it. A negative assertion confirms no pane-working-directory lookup remains
in the launch path.

### REQ-G1.7 — Liveness across the upgrade window [test]

Liveness fixtures treat a session under the new name and one under the prior launcher's
`<repo-basename>_worktree-<suffix'>` spelling as live, and a source assertion confirms no probe for
the bare `worktree-<suffix>` name remains. Retiring the prior-launcher probe is the gated deferral
in `tasks.md`.

## REQ-H — tmux launch verification and docs

### REQ-H1.1 — Launch fixtures are bounded [test]

The Task 11 harness self-test: a deliberately blocking launch stub fails within the bound with a
non-hang diagnosis, and every launch fixture in the touched test files runs through the bounded
runner (a source assertion over those files).

### REQ-H1.2 — Stub server environment differs from the dispatcher's [test]

The harness self-test: a stub session's command sees a variable set only in the stub server's
environment and does not see one set only in the dispatcher's.

### REQ-H1.3 — Every refusal arm has a fixture that can fail [test + design-level]

`[test]`: the refusal and failure fixtures listed under REQ-G1.1 through REQ-G1.6 exist and pass.
`[design-level]`: review confirms each was run once against the code with its arm removed and
failed, as the PR description records.

### REQ-H1.4 — Canonical compares; race-free, self-reaping stubs [test]

Launch fixtures pass when run under a symlinked temporary directory; after the suite, no process
a stub started is still running (asserted by the harness); stub logs and pid files are written per
invocation and atomically, so concurrent stub calls cannot interleave them.

### REQ-H1.5 — No doc presents the old launch as the rung's [test]

The Task 14 check under `mise run check` fails on a fixture doc presenting
`claude --worktree <suffix> --tmux=classic` as the tmux rung's launch, passes on a doc labeling it
an operator hand-launch, and passes on the repository.

### REQ-H1.6 — The seam exemption covers only the tower relaunch [test]

A fixture copy of `fleet-tower-watchdog.sh` gains a second tmux worker launch; the seam discovery
reports it as missing from the manifest while the tower relaunch stays exempt, and the
unreached-exemption guard still passes on the real file.
