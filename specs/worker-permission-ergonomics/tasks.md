# Worker Permission Ergonomics — Tasks

**Status:** Draft
**Last reviewed:** 2026-10-05
**Format-version:** 2
**Execution:** derived — see the status render

Tasks 1 to 3 delivered the hook, its wiring, and literal-path invocation.
Tasks 4 onward are the 2026-10-05 extension. Task 4 closes a live false-allow
and sits on the critical path; the real-prompt corpus (Task 5) lands before
the guard tasks it verifies, so each of them turns its own corpus rows from
pending to enforced. The dependency graph is the `Dependencies:` fields
below; `scripts/spec-graph.sh` renders it on demand.

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

### Task 4 — Close the unexpanded-operand false-allow in both guards

- **Deliverables:** `scripts/worker-command-guard.sh` and
  `scripts/tower-command-guard.sh` defer any word carrying an unresolved or
  opaque `$` expansion wherever the verb's approval depends on that word
  (screened operands, verb positions, containment-checked paths), and model a
  `for` variable by re-verifying the loop body once per plain-literal head
  word under a bounded count; adversarial fixtures in both guards' suites for
  the recorded bypasses (`for d in "<flags>"; do find . $d; done`, the `$_`
  form, a loop variable reaching `cat`/`sed`/`awk`/`bash` operands and
  containment checks, a glob in a verb path, a symlinked cache root).
- **Done when:** every recorded bypass shape defers in both guards, each
  fixture first shown failing (allowing) against the pre-change guard; the
  shapes the guards approve today with a plain-literal loop head
  (`for f in a b; do grep -n x $f; done`) still approve; both suites and
  `shellcheck`/`shfmt -d` are clean under `mise run test`.
- **Dependencies:** none
- **Citations:** D-11 · REQ-E1.1
- **Estimated effort:** 1–2 days

### Task 5 — Real-prompt regression corpus and harness

- **Deliverables:** a sanitized corpus file drawn from real worker prompts
  (command shapes only: no hostnames, user paths, tokens, or repository
  names), each row tagged with its class and its expected verdict under each
  policy value (`read-only`, `own-branch`, `scratch`, combinations); a harness
  in the guard's test suite that runs every row through the hook with the
  policy and session identity injected, treating rows of a class whose task
  has not landed as pending, and failing when a pending row's class is marked
  shipped; floor rows and uncovered rows enforced from the start.
- **Done when:** the corpus holds at least one row for every shape REQ-E
  and REQ-F name, every floor act REQ-F1.5 names, and every uncovered class
  REQ-A1.13 names; floor rows (merge, ready flip, force-push, amend, rebase, push to
  another ref, writes outside worktree and scratch, `gh` writes) defer under
  every policy value, uncovered rows (interpreters, self-written script
  execution) defer, a secret-scan and the purged-identifier guard pass over
  the corpus file, and the harness runs under `mise run test`.
- **Dependencies:** 4
- **Citations:** D-20 · REQ-H1.3, REQ-A1.11
- **Estimated effort:** 1–2 days

### Task 6 — Run-order analysis: cd, plain assignments, transparent prefixes, timing verbs

- **Deliverables:** the worker guard walks segments in run order carrying the
  working directory and plain-literal variable values; approves a leading
  `cd <literal>` that canonicalizes inside the session's own worktree and
  analyses later segments against it; resolves `NAME=<plain literal>` for any
  literal with unquoted word splitting reproduced; treats `time` and
  `timeout <duration>` as transparent prefixes; adds the wait and inspection
  verbs of REQ-E1.5 under the safe-invocation rule; fixtures for each,
  including `cd` out of the worktree, `cd` with a non-literal operand, and an
  assignment whose value carries a glob or quote, all deferring.
- **Done when:** the corpus rows of these classes are enforced and pass;
  REQ-A1.12's run-order clause and REQ-A1.13's prefix clause are exercised by
  fixtures; the fleet guide and the worker launch text state that a worker
  issues `git` without a `cd`; the suite and lints pass.
- **Dependencies:** 5
- **Citations:** D-19 · REQ-A1.12, REQ-A1.13, REQ-E1.2, REQ-E1.4, REQ-E1.5
- **Estimated effort:** 2 days

### Task 7 — Admit argument-independent command substitution

- **Deliverables:** the worker guard admits `$(…)` under REQ-E1.3: inner text a
  single simple command or pipeline passing the read-only analysis; no
  nesting, backtick, or parenthesis inside a quote; output (directly or via a
  variable assigned from it, tracked as opaque) reaching only operands of the
  enumerated argument-independent verbs or such an assignment; an adversarial
  fixture set for unquoted word splitting, glob expansion of the output, a
  tainted variable reaching a screened verb, nesting, quoting tricks, and a
  substitution in a verb position.
- **Done when:** the corpus's substitution rows that meet the rule approve
  and every other substitution row defers; every adversarial fixture is
  first shown allowing against a deliberately over-broad variant of the
  change and deferring against the real one; the suite and lints pass.
- **Dependencies:** 6
- **Citations:** D-11 · REQ-A1.12, REQ-E1.3
- **Estimated effort:** 2–3 days

### Task 8 — Plugin scripts resolve the values workers fetched by substitution

- **Deliverables:** `scripts/step-record.sh` defaults `--head` to the current
  `HEAD` when it is omitted; a sweep of the plugin scripts a worker or
  orchestrator calls with an argument fed by substitution in the replay, each
  given the same self-resolving default; their tests.
- **Done when:** `step-record.sh write` without `--head` records the current
  `HEAD`, the existing explicit form is unchanged, each swept script has a
  test for its default, and `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-11 · REQ-H1.1
- **Estimated effort:** half day

### Task 9 — The self-approval policy, the floor, and the own-branch arm

- **Deliverables:** a self-approval policy knob in `config/defaults.yml`
  (default `read-only`) documented in the options reference and resolved
  through the overlay layers; the worker guard reading it and the session's
  unit identity (worktree root, unit branch) with every failure falling back
  to `read-only`; a floor check evaluated before any arm; the `own-branch` arm
  per REQ-F1.3, composed with human-gates' `worker_base_merge` and leaving the
  policy guard in place; fixtures for each arm member, the floor under every
  value, an unresolvable identity, and the deny-outcome assertion against the
  real `deny` block.
- **Done when:** the corpus's own-branch rows approve only under a policy
  containing `own-branch`; floor rows defer under every value; a malformed or
  unreadable knob behaves as `read-only`; no fixture shows the hook emitting
  `allow` for a deny-matched command; the suite and lints pass.
- **Dependencies:** 5
- **Citations:** D-12, D-13 · REQ-F1.1, REQ-F1.2, REQ-F1.3, REQ-F1.5,
  REQ-B1.8, REQ-A1.11
- **Estimated effort:** 3 days

### Task 10 — The per-worker scratch root and the scratch arm

- **Deliverables:** the worker launchers create a per-worker scratch root
  owned by the worker, export it as `TMPDIR`, and record it where the guard
  resolves it; the guard's `scratch` arm approves writes whose every target
  canonicalizes inside that root and never approves executing or sourcing
  from it; launcher and guard tests.
- **Done when:** a launched worker's `TMPDIR` is its own scratch root; the
  corpus's scratch-write rows approve only under a policy containing
  `scratch`; writes to `/tmp` outside the root, a symlink escaping it, and
  `bash <root>/x.sh` defer; the suite and lints pass.
- **Dependencies:** 9
- **Citations:** D-14 · REQ-F1.4, REQ-G1.2
- **Estimated effort:** 1–2 days

### Task 11 — The audit log of allow decisions

- **Deliverables:** the worker guard appends one line per emitted `allow` to a
  worker-local append-only log under the fleet state home (time, session,
  approving arm or category, command hash, never the command text), with a
  retention bound and a failure path that leaves the decision unchanged; the
  options and fleet docs describe it.
- **Done when:** an approved fixture produces exactly one log line carrying no
  command text; an unwritable log leaves the `allow` intact and well-formed;
  the retention bound is enforced by a test; the suite and lints pass.
- **Dependencies:** 9
- **Citations:** D-21 · REQ-H1.4, REQ-B1.8
- **Estimated effort:** 1 day

### Task 12 — Profile: static read-only allow set, `-u` push, `_about`, matcher model

- **Deliverables:** `config/worker-settings.json` gains the REQ-G1.1 static
  read-only allow rules and `git push -u origin`, its `deny` block unchanged;
  `_about` rewritten to describe every approval category, each policy arm,
  and the floor; the permission-matcher model doc, its re-implementation, and
  the fixture table updated to the documented nested-command behaviour, with
  a row per nesting form.
- **Done when:** the permission-matcher test passes with a fixture row for
  every new allow rule and every nesting form; `awk`, `find`, `xargs`, and
  bare `sed` have no allow rule; the `deny` block is byte-identical; the
  settings-fragment and hook-contract checks pass.
- **Dependencies:** 9, 10
- **Citations:** D-10, D-15 · REQ-G1.1, REQ-G1.6, REQ-G1.7, REQ-H1.2
- **Estimated effort:** 1 day

### Task 13 — Relaunch under the current profile

- **Deliverables:** a stream-json supervisor verb that relaunches a worker by
  resuming its persisted session with the currently installed worker profile
  passed explicitly; the fleet guide's statement that permissions and the
  policy's launch-time inputs load at session start and reach a running
  worker only by relaunch.
- **Done when:** a test shows the relaunch argv carries the installed
  profile's path and the persisted session id, and refuses a worker with no
  persisted session; the guide text is present; `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-16 · REQ-G1.3
- **Estimated effort:** 1 day

### Task 14 — State what unattended means in doctrine

- **Deliverables:** the inter-orchestrator-coordination doctrine's
  permission-prompt section states that unattended mode parks every prompt
  outside the configured self-approval policy for the operator, that no
  tower or supervisor answers one on its judgment, and that the policy is the
  only self-approval surface; the doctrine index row updated.
- **Done when:** the doctrine text is present, the instruction-budget and
  doctrine-index checks pass, and `mise run check` passes.
- **Dependencies:** 9
- **Citations:** D-9, D-12 · REQ-G1.4, REQ-F1.2
- **Estimated effort:** half day

### Task 15 — Meta-tower direct dispatch

- **Deliverables:** `/orchestrate --meta`/`--fleet` performs the selected
  spec's single-spec step (per-spec lock, freshness gate, dispatch record,
  worker launch) in the meta-tower's own session; the orchestration-modes
  doctrine's meta step amended to match; tests over the meta step's selection
  and lock handoff.
- **Done when:** a meta step launches a worker with no subordinate tower
  session, the per-spec lock is taken and released around the single-spec
  step, a concurrent single-spec tower is still excluded by that lock, and
  `mise run check` passes.
- **Dependencies:** none
- **Citations:** D-17 · REQ-G1.5
- **Estimated effort:** 2 days

## Awaiting input

(none yet)

## Deferred

- **Standing-decision matching over split segments.** tower-comms' standing
  decisions match a literal prefix of the whole command; matching them per
  split segment is deferred, since a standing-decision settle today closes the
  queue item without answering the worker's live prompt. Confidence: high.
  **Gate:** the tower-comms settle route delivers the recorded answer to the
  worker's live permission prompt (obs:fd1824a4 resolved). (Free-text: the
  condition is another bundle's fix landing, which no `GATE(when:)` atom
  names.) Citations: D-18; tower-comms REQ-E1.5.

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
- **Tower-side answering of worker prompts.** No tower, supervisor, or relay
  answers a worker's permission prompt on the strength of the policy or its
  own judgment. Citations: D-12; REQ-F1.2.
- **Executing self-written scripts.** A script the worker wrote, in scratch or
  anywhere else, is never approved: it is arbitrary execution. Citations:
  D-14; REQ-F1.4.
- **Claude Code's own safety gates.** The `cd`-before-`git` gate and the
  sensitive-path prompt are outside any hook's reach. Citations: D-19.
