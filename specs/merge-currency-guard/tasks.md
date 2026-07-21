# Merge Currency Guard — Tasks

**Status:** Draft
**Last reviewed:** 2026-07-20
**Format-version:** 2
**Execution:** derived — see the status render

Four tasks. Task 1 (the invariant statement plus its guard-catalog
registration and the altitude record) is foundational: the guard and the
loop-sync both cite it, so it dispatches first. Task 2 (the `ready-guard`
hook) is guard infrastructure that protects the ready-flip on every unit, so
per the guard-infrastructure-first selection rule it outranks the critical
path once Task 1 lands. Task 3 (the in-loop `main`-sync) is independent of
Task 2 and can run in parallel after Task 1. Task 4 (the adversarial + sync
test suite) gates both mechanisms and dispatches last.

## Tasks

### Task 1 — Ready-currency invariant, catalog registration, and altitude record

- **Deliverables:** the hard-invariant statement (REQ-A1.1) recorded where
  planwright's ready-flip contract lives and cited by the guard and loop-sync;
  a `config/guard-catalog.yaml` entry registering `ready-guard` (a `security`/`ci`
  category guard) so the builder surface and adopters discover it as a core
  guard; the D-1 altitude record and the D-9 capability-vs-policy boundary
  written into `design.md` (already drafted here, verified consistent at
  execution); no guard code and no skill edits in this task.
- **Done when:** the invariant statement exists and is cross-referenced from the
  guard and sync deliverables; the guard-catalog entry parses under the
  catalog's constrained reader and `scripts/spec-validate.sh` / `mise run check`
  pass over the bundle; the altitude record (D-1) and the flipper-agnostic
  boundary (D-9) are present and internally consistent; no executable behavior
  is introduced.
- **Dependencies:** none
- **Citations:** REQ-A1.1 · REQ-A1.2 · REQ-A1.3 · REQ-A1.4 · D-1 · D-9 ·
  obs:921b93c9
- **Estimated effort:** 0.5 day

### Task 2 — `ready-guard.sh` deny-emitting PreToolUse hook and wiring

- **Deliverables:** `scripts/ready-guard.sh`, a deterministic, deny-emitting
  PreToolUse hook implementing the D-3 predicate (`mergeStateStatus == CLEAN`
  AND `git merge-base --is-ancestor origin/main HEAD`), fail-closed on any doubt
  (D-5), treating the payload as inert data (REQ-C1.5), with no LLM in the
  decision path; coverage of both surfaces (D-8) — a Bash matcher for
  `gh pr ready` (excluding `--undo`) and an MCP matcher for
  `mcp__github__update_pull_request` draft→ready transitions; the
  `hooks/hooks.json` PreToolUse wiring (Bash + MCP matchers, REQ-C1.7); a clear,
  actionable denial message naming what could not be confirmed (REQ-K1.1).
- **Done when:** the guard emits `deny` for `BEHIND`/`DIRTY`/`BLOCKED`/`UNKNOWN`
  and for missing-`gh`/missing-`jq`/malformed payloads, and emits nothing
  (defer) for a `CLEAN` + `is-ancestor` head, for `gh pr ready --undo`, and for
  a non-transitioning `update_pull_request` call; both surfaces are wired in
  `hooks/hooks.json`; a negative assertion confirms no model/API call in the
  decision path (REQ-D1.4); `mise run check` passes.
- **Dependencies:** 1
- **Citations:** REQ-C1.1 · REQ-C1.2 · REQ-C1.3 · REQ-C1.5 · REQ-C1.6 ·
  REQ-C1.7 · REQ-C1.8 · REQ-K1.1 · D-2 · D-3 · D-5 · D-7 · D-8
- **Estimated effort:** 2.5 days

### Task 3 — Convergence-loop `main`-sync (`converge-sync-main.sh` + `/execute-task` wiring)

- **Deliverables:** `scripts/converge-sync-main.sh` running `git fetch origin
  main` then `git merge FETCH_HEAD` (never `git pull`, never rebase — REQ-B1.2),
  exiting non-zero on an unresolvable conflict for the caller to halt on; a
  single-line invocation added at the top of each `review_sequence` convergence
  iteration in `skills/execute-task/SKILL.md`, with the conflict→`Awaiting
  input` halt reusing the existing stop-condition protocol (REQ-B1.3) and an
  explicit note that `/execute-task` still opens only a draft PR and never flips
  ready (REQ-B1.4); the edit kept to a single line so the instruction body stays
  within its instruction-headroom budget (REQ-B1.5).
- **Done when:** the script fast-forwards/merges a clean `origin/main` advance
  and exits non-zero on a conflicting one; the `/execute-task` body invokes it
  once per convergence iteration and its word count stays under the
  instruction-headroom ceiling (verified by `scripts/check-instructions.sh`);
  negative assertions confirm no `git pull` and no rebase in the script
  (REQ-D1.4); `mise run check` passes.
- **Dependencies:** 1
- **Citations:** REQ-B1.1 · REQ-B1.2 · REQ-B1.3 · REQ-B1.4 · REQ-B1.5 · D-4
- **Estimated effort:** 1 day

### Task 4 — Adversarial, precedence, and sync test suite

- **Deliverables:** a fixture-driven adversarial suite for `ready-guard.sh`
  covering the full D-3 decision matrix across both surfaces (REQ-D1.1); a test
  asserting the deny-over-allow OUTCOME against a payload the
  `config/worker-settings.json` `gh pr ready` allow entry would pass (REQ-D1.2,
  D-6); tests for `converge-sync-main.sh` covering clean merge, conflict exit,
  and the no-`pull`/no-rebase negative assertions (REQ-D1.3); the negative
  no-LLM assertions for both scripts (REQ-D1.4).
- **Done when:** the suite is green in the project CI; every matrix branch
  (current+`CLEAN`→defer, `BEHIND`/`DIRTY`/`BLOCKED`/`UNKNOWN`→deny, `--undo`→defer,
  missing-`gh`/`jq`/malformed→deny) is asserted on both surfaces; the
  precedence-outcome test passes with the allow entry present; the sync tests
  pass; `mise run check` passes.
- **Dependencies:** 2, 3
- **Citations:** REQ-D1.1 · REQ-D1.2 · REQ-D1.3 · REQ-D1.4 · REQ-C1.4 · D-6 ·
  obs:4dda9fe1
- **Estimated effort:** 1.5 days

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
