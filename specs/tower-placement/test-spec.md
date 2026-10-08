# Tower placement — Test Spec

**Status:** Ready
**Last reviewed:** 2026-10-08
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: `[test]` for the classifier, the knob, the guard, the hooks,
and dispatch, as shell test files run by `mise run check` and the repo CI;
`[manual]` for bring-up behavior in live sessions, since worktree isolation
and settings layers exist only in a real Claude Code session;
`[design-level]` for doctrine and docs, where the artifact's existence and
coverage is the verification.

## REQ-A — Placement

### REQ-A1.1 — Own tree, never `--worktree` [manual + design-level]

The docs carry both launch forms (Task 7); a manual run launches a tower
from a plain linked worktree and from a clone, and removes a landed
flight's worktree and reads the primary checkout with no refusal.

### REQ-A1.2 — The placement floor [design-level]

`doctrine/fleet-coordination-floor.md` carries the floor, names each
sanctioned-script exception, and cites REQ-A1.2 (verified at PR review);
the doctrine-index check passes.

### REQ-A1.3 — One knob [test]

Knob tests resolve `warn` by default, each value at each layer, and a
malformed value per the existing by-layer policy.

## REQ-B — Bring-up

### REQ-B1.1 — Deterministic classification [test]

Classifier tests over a main tree, a linked worktree, a separate clone, a
bare repository, and a path outside any repository.

### REQ-B1.2 — Response per knob [manual]

A manual run of each skill in a main tree under `warn`, `refuse`, and
`allow`, and in a linked worktree, records the response; under `refuse`, a
`/tower` repo-mutating ask is held and a question is answered, an
acknowledgement lifts the hold, and `/orchestrate` holds dispatch, relay,
and the bookkeeping push while a status read completes; an unattended
`/orchestrate` parks in Awaiting input.

### REQ-B1.3 — Isolation warning [manual]

A tower launched with `--worktree` warns once at bring-up, names the
supported launch, and keeps answering.

### REQ-B1.4 — Posture check accepts plugin enforcement [manual]

Each skill launched without the profile, with the plugin hook wired,
meets the floor; with the hook removed, and with the hook wired to a path
that does not resolve, `/tower` falls back to read-only and `/orchestrate`
holds its outward acts; every report names each layer read.

### REQ-B1.5 — Bring-up reads, never polled [design-level]

The skills' bring-up steps read once and on request; no step loops.

## REQ-C — Plugin-wired enforcement

### REQ-C1.1 — Floor in marked sessions [test]

Every tower deny entry is refused in a marked session whose payload
carries no profile, each GitHub MCP tool in the deny list
(`mcp__github__update_pull_request_branch` included) denied by name.

### REQ-C1.2 — Marking never widens [test]

A self-marked ordinary session gains no allow; `tower-command-guard.sh` is
absent from the plugin hooks file.

### REQ-C1.3 — Marking from the prompt start and bring-up [test]

The prompt hook marks on a leading `/tower` or `/orchestrate` command,
bare or plugin-namespaced, and not on a tag later in the prompt; the
activation handshake marks and is refused with the "active" message.

### REQ-C1.4 — Fail closed [test]

In a marked session, a corrupt or tampered mark, an unsearchable store,
an oversized payload, a signal before the verdict, and a command naming
the store each deny; a missing store and an unreadable session id each
defer. A symlinked store, mark, or fleet home, a group- or
world-writable mark, and a non-UUID id each fail the store check, and a
prune never follows a planted link.

### REQ-C1.5 — Top-level id and timeouts [test]

A payload with a nested `session_id` in tool input reads the top-level id;
a check asserts each hook entry this bundle adds carries a timeout longer
than the policy guard's whole-call deadline plus margin.

### REQ-C1.6 — Unmarked sessions untouched [test]

An unmarked session defers on every fixture command; logging stubs on
`PATH` record no external command before the prefilter decides, and a
static check finds no command substitution, pipeline, or subshell in the
prefilter.

### REQ-C1.7 — Profile launch still works [test]

The existing tower-settings hook-wiring tests pass, with only their pinned
`_about` phrases updated for REQ-D1.5.

Superseded by REQ-C1.13 (2026-10-08): this path passed while every hook
was dead, because the hook-wiring test pinned the broken spelling.

### REQ-C1.13 — Profile hooks execute [test + manual]

An execution test runs each tower-profile hook command through a shell
with a fixture payload and `CLAUDE_PLUGIN_ROOT` exported, and finds each
reaching its script; the tower-settings hook-wiring tests pass, with their
spelling pins and `_about` phrases updated. A manual launch through the
supported launcher shows a tmux read auto-approved by the command guard
and a reserved act refused by the policy guard; the opt-in live CLI probe
(`PLANWRIGHT_LIVE_CLI_PROBE=1`) re-measures the spelling by hand.

### REQ-C1.8 — Resume residual [manual + design-level]

The docs state the residual; a manual run resumes a tower under another
fleet home, invokes `/tower` (or the on-request posture check), and finds
the session marked in the new fleet home.

### REQ-C1.9 — Bounded mark store [test + manual]

A mark write removes a mark older than the pruning age and keeps a
refreshed one; a handshake moves the session's own mark's age; no
non-hook process writes a mark. A manual on-request posture check refreshes
the live session's mark.

### REQ-C1.10 — Quoted, unbraced spelling [test]

The widened static check in `tests/test-settings-fragment-hook-expansion.sh`
finds every tower-profile hook command in the quoted, unbraced form.

### REQ-C1.11 — Check over every profile [test]

The check passes on the shipped profiles and fails on fixture profiles
with the braced token in a non-first hook entry and with an unquoted root;
it selects profiles by their `hooks` key, not by name.

### REQ-C1.12 — Policy hooks refuse an unresolved root [test]

With `CLAUDE_PLUGIN_ROOT` unset, and set to a directory without the guard,
each policy-guard hook exits 2 with a reason naming the guard, and the
command guard's hook exits neither 0 nor 2.

## REQ-D — The deny floor

### REQ-D1.1 — Branch-moving and stash-writing denied [test]

Each act REQ-D1.1 lists is refused at the tower tier, against the
tower's own checkout too; `stash list`, `stash show`, a plain commit,
plain branch creation and deletion, and `git worktree add -b <new>` are
allowed.

### REQ-D1.2 — Every parseable spelling [test]

Each tower act is refused through global options, long-option prefixes,
ref forms, and repo aliases.

### REQ-D1.3 — Deny-to-act map [test]

The map check passes on the shipped profile and fails on a fixture with an
unmapped entry.

### REQ-D1.4 — Tightening only [test]

The pre-bundle deny list, frozen as a committed fixture, is a subset of
the shipped one; `git worktree add <path> -b docs/main` and
`git push origin docs/main` are not denied.

### REQ-D1.5 — `_about` accuracy [test]

A test asserts the profile's `_about` says the command arrives as written,
no longer claims expanded commands, and drops the statements REQ-D1.5
names.

### REQ-D1.6 — `_about` names the spelling [test]

A test asserts the profile's `_about` states the quoted, unbraced spelling,
the launcher's export, and the policy hooks' refusal, and no longer says
it references the script exactly as `hooks/hooks.json` does.

## REQ-E — Dispatch from a tower's own tree

### REQ-E1.1 — No nested worktrees [test]

Dispatch from a linked-worktree tower places the unit worktree under the
primary `.claude/worktrees/`.

### REQ-E1.2 — Primary excluded, NUL-safe [test]

A flight branch checked out in the primary checkout is neither counted nor
retired; a newline-bearing worktree path cannot forge a line.

## REQ-F — Docs

### REQ-F1.1 — Supported launch documented [design-level]

`docs/fleet.md` carries both forms and the reason against `--worktree`.

### REQ-F1.2 — Per-tower-checkouts reconciled [design-level]

The guide's worktree section says one tower in a linked worktree is
supported and several want clones.

### REQ-F1.3 — Knob documented [test + design-level]

The options-reference check finds `tower_placement`, and its row explains
`allow`.

### REQ-F1.4 — Stale prose corrected [design-level]

No doc or script header claims the floor loads only with the profile.

### REQ-F1.5 — Upgrade note [design-level]

`docs/fleet.md` carries the restart-after-install note and the no-switch
recovery path.

### REQ-F1.6 — Launch needs the root exported [design-level]

The tower-profile paragraph of `docs/fleet.md` states the export, the
refusal without it, and relaunch to pick up a changed profile.

## REQ-G — Invariants

### REQ-G1.1 — Merge and ready stay reserved [test]

The existing never-merge and never-ready guard tests pass, and the new
plugin path refuses both in a marked session.

### REQ-G1.2 — Workers unchanged [test]

The worker-tier expectations of the policy-guard and reserved-control
suites, `tests/test-worker-command-guard.sh`, and
`tests/test-worker-settings-hook-wiring.sh` pass with no edit to their
worker-tier expectations; the worker launch path in the dispatch suites is
unchanged.

### REQ-G1.3 — New commits only [design-level]

Verified at each PR's review: no force-push or history rewrite on the PR
timeline.

### REQ-G1.4 — Security-zone pause [design-level]

Tasks 3 and 4's PRs carry the allow/deny delta and record the hard pause.
