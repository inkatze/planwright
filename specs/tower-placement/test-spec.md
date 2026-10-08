# Tower placement — Test Spec

**Status:** Draft
**Last reviewed:** 2026-10-07
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

`doctrine/fleet-coordination-floor.md` carries the floor and cites
REQ-A1.2; the doctrine-index check passes.

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
repo-mutating ask is held and a question is answered.

### REQ-B1.3 — Isolation warning [manual]

A tower launched with `--worktree` warns once at bring-up, names the
supported launch, and keeps answering.

### REQ-B1.4 — Posture check accepts plugin enforcement [manual]

A tower launched without the profile, with the plugin hook wired, meets
the floor; with the hook removed it falls back to read-only; both reports
name every layer read.

### REQ-B1.5 — Heartbeat-class reads [design-level]

The skills' bring-up steps read once and on request; no step loops.

## REQ-C — Plugin-wired enforcement

### REQ-C1.1 — Floor in marked sessions [test]

Every tower deny entry is refused in a marked session whose payload
carries no profile.

### REQ-C1.2 — Marking never widens [test]

A self-marked ordinary session gains no allow; `tower-command-guard.sh` is
absent from the plugin hooks file.

### REQ-C1.3 — Marking from the prompt start and bring-up [test]

The prompt hook marks on a leading `/tower` or `/orchestrate` command and
not on a tag later in the prompt; the activate verb marks.

### REQ-C1.4 — Fail closed [test]

A missing, corrupt, unsearchable, or tampered store; an oversized payload;
a signal before the verdict; and a command naming the store each deny in a
marked or unknown session.

### REQ-C1.5 — Top-level id and timeouts [test]

A payload with a nested `session_id` in tool input reads the top-level id;
a check asserts every plugin hook entry carries a timeout below the
harness default.

### REQ-C1.6 — Unmarked sessions untouched [test]

An unmarked session defers on every fixture command, and a trace shows no
process forked before the prefilter decides.

### REQ-C1.7 — Profile launch still works [test]

The existing tower-settings hook-wiring tests pass unchanged.

### REQ-C1.8 — Resume residual [manual + design-level]

The docs state the residual; a manual resume under another fleet home
shows bring-up re-marking the session.

## REQ-D — The deny floor

### REQ-D1.1 — Branch-moving and stash-writing denied [test]

Each act D-10 defines is refused at the tower tier; read-only stash
inspection is allowed.

### REQ-D1.2 — Every parseable spelling [test]

Each tower act is refused through global options, long-option prefixes,
ref forms, and repo aliases.

### REQ-D1.3 — Deny-to-act map [test]

The map check passes on the shipped profile and fails on a fixture with an
unmapped entry.

### REQ-D1.4 — Tightening only [test]

The pre-bundle deny list is a subset of the shipped one; a new branch
named `docs/main` is not denied.

### REQ-D1.5 — `_about` accuracy [test]

A check asserts the profile's `_about` no longer claims expanded commands.

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

## REQ-G — Invariants

### REQ-G1.1 — Merge and ready stay reserved [test]

The existing never-merge and never-ready guard tests pass, and the new
plugin path refuses both in a marked session.

### REQ-G1.2 — Workers unchanged [test]

The worker guard and dispatch test suites pass unchanged.

### REQ-G1.3 — New commits only [test]

The standing history-rewrite guards and CI checks pass.

### REQ-G1.4 — Security-zone pause [design-level]

Tasks 3 and 4's PRs carry the allow/deny delta and record the hard pause.
