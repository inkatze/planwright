# Worker Permission Ergonomics — Tasks

**Status:** Ready
**Last reviewed:** 2026-07-18
**Format-version:** 2
**Execution:** derived — see the status render

Three task blocks. Tasks 1 and 3 have no dependencies and can run in parallel;
Task 2 (wiring) depends on Task 1 (the hook must exist before it is wired).
The dependency graph is the `Dependencies:` fields below; `scripts/spec-graph.sh`
renders it on demand.

## Tasks

### Task 1 — Implement and test the auto-approve hook

- **Deliverables:** `scripts/worker-command-guard.sh` — a portable POSIX/bash
  `PreToolUse` hook that reads the hook payload from stdin, extracts
  `tool_name` and `tool_input.command` via `jq` (deferring all when `jq` is
  absent), and returns `permissionDecision: allow` only for known-safe Bash
  command shapes, deferring everything else. Ports the validated prototype's
  analysis (quote-aware segment splitter, every-segment-safe rule, verb
  classifier, `fish -c` recursion with bounded depth, redirect handling) into
  pure shell, and implements the kickoff-hardened analysis: per-invocation
  safe-flag/arg guards with unknown-flag-defers (REQ-A1.8), grammar-conservative
  deferral of env-assignment prefixes / path-prefixed verbs / fish bare-paren /
  subshell-grouping / multi-char redirect tokenization (REQ-A1.9), script/test/
  bats path canonicalization + containment (REQ-A1.10), and the fail-closed
  emission contract (REQ-B1.7). Plus `tests/test-worker-command-guard.sh`, the
  adversarial suite.
- **Done when:** the hook returns allow/defer per the REQ-A1.5 known-safe set
  and REQ-A1.6 defer set, honoring the REQ-A1.8 safe-invocation rule,
  REQ-A1.9 grammar-conservative deferral, REQ-A1.10 path containment, and the
  REQ-B1.7 fail-closed emission contract (defer path emits empty stdout + exit 0,
  never exit 2, never a partial allow, never hangs); `jq`-absent, non-Bash,
  malformed-stdin, empty/non-string-command, and deep-`fish -c`-nesting inputs
  all defer; the adversarial suite (≥30 cases including the kickoff-surfaced
  vectors and the deny-collision case, test-first) is green with ZERO
  false-allows and asserts a deny-listed command is never auto-approved;
  `shellcheck` and `shfmt -d` are clean; the suite runs under `mise run test`.
- **Dependencies:** none
- **Citations:** D-2, D-3, D-4 · REQ-A1.1, REQ-A1.2, REQ-A1.4, REQ-A1.5,
  REQ-A1.6, REQ-A1.7, REQ-A1.8, REQ-A1.9, REQ-A1.10, REQ-B1.1, REQ-B1.2,
  REQ-B1.3, REQ-B1.4, REQ-B1.5, REQ-B1.6, REQ-B1.7
- **Estimated effort:** 3–4 days (grew from 2 at kickoff: the hardened analysis
  in REQ-A1.8/A1.9/A1.10/B1.7)

### Task 2 — Wire the hook into the worker-settings profile

- **Deliverables:** `config/worker-settings.json` updated with a `PreToolUse`
  (Bash) hook entry referencing `scripts/worker-command-guard.sh` via
  `${CLAUDE_PLUGIN_ROOT}`, keeping `defaultMode: default` and the `deny` block
  byte-for-byte unchanged; the `_about` field updated to document the hook (its
  no-LLM, allow-only, deny-precedence properties), the human-sign-off posture,
  and the optional adopter-specific literal-path allow entry. The `_about` text
  SHALL also warn adopters not to merge the auto-approve hook stanza into a
  general (tower/human) `settings.json`, since worker-scoping is enforced only by
  where the hook is wired (REQ-C1.2; brief §7 R7). Task 2 is the sole editor of
  `config/worker-settings.json` `_about` (Task 3 does not touch it).
- **Done when:** the fragment carries the hook and validates as Claude Code
  settings JSON (`lint:json` / schema check clean); the `deny` block is
  unchanged from the pre-edit version; `_about` documents the hook and posture;
  a hook-JSON-shape assertion in the test suite confirms the hook is present in
  `worker-settings.json` and absent from the plugin-global `hooks/hooks.json`.
- **Dependencies:** 1
- **Citations:** D-5, D-6 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-A1.3
- **Estimated effort:** half day

### Task 3 — Resolve plugin scripts by literal path in the dispatching skills

- **Deliverables:** `/execute-task`, `/orchestrate`, and `/spec-kickoff` updated
  to resolve the plugin/planwright root once per invocation and invoke plugin
  scripts by resolved literal absolute path rather than through an unexpanded
  shell variable; the optional install-location-specific literal-path allow
  entry documented for adopters in the options/overlay docs. (The
  `worker-settings.json` `_about` mention of the allow entry is owned by Task 2,
  which owns the `_about` rewrite; Task 3 does not edit `worker-settings.json`.)
- **Done when:** the three skills' plugin-script invocations use a resolved
  literal path (no `"$VAR/scripts/x.sh"` invocation shape remains in the
  changed call sites); the change is documented; existing skill behavior is
  otherwise unchanged and the repo's `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-7 · REQ-D1.1
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

- **Operator-configurable allowlist knob.** The known-safe allowlist ships as a
  fixed conservative core policy (D-8); exposing an operator-configurable
  extension/override knob is deferred. Confidence: high.
  **Gate:** GATE(when: recurring drain-loop observations show multiple contexts
  need to extend the worker allowlist, per the customization-boundary
  graduation rule). Citations: D-8; `doctrine/customization-boundary.md`.

- **Runtime audit log of hook allow decisions.** The auto-approve hook is a
  silent permissions-upgrade emitting only a fixed reason string (REQ-B1.4), so
  a novel field false-allow leaves no runtime trace (the observability
  decision-domain gap surfaced at kickoff). A file-based audit log of allow
  decisions is deferred: the conservative allow-only design, the deny-precedence
  guarantee (a hook allow can never un-block a denied command), and the
  adversarial suite are the shipped controls. Confidence: medium.
  **Gate:** GATE(when: first field evidence of a hook false-allow, OR recurring
  drain-loop demand for runtime auditability of auto-approve decisions).
  Citations: kickoff §7 (2026-07-18); REQ-B1.4;
  `doctrine/decision-domains.md` (observability).

## Out of scope

- **`auto` / `bypassPermissions` permission modes.** Rejected by fleet-autonomy
  D-19; this hook is the LLM-free path to the same no-flood goal. Citations:
  D-2; fleet-autonomy REQ-E1.4/D-19.
- **`fleet-state-home-unresolved`.** fleet-throttle / tower-marker failing to
  resolve a cross-spec fleet home under a marketplace install — a
  fleet-governance robustness gap orthogonal to worker permissions. Left to
  fleet-autonomy or its own bundle; the observation is left unconsumed.
  Citations: obs:b085ac53 (unconsumed).
- **Non-Bash tool coverage.** The hook considers only the Bash tool; every
  other tool defers to the normal flow. Citations: REQ-A1.7.
