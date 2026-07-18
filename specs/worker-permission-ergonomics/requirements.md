# Worker Permission Ergonomics — Requirements

**Status:** Draft
**Last reviewed:** 2026-07-18
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

Dispatched planwright workers (`/orchestrate` → `/execute-task`) flood on
permission prompts. fleet-autonomy's dispatch guard forbids launching workers
under Claude Code's `auto`/`bypassPermissions` modes — an LLM classifier in the
approval path violates the D-18 deterministic-mechanics floor (fleet-autonomy
REQ-E1.4/D-19) — so workers run `defaultMode: default` under the static
`config/worker-settings.json` allowlist. That allowlist silences plain commands
but not the command shapes `/execute-task` actually issues: plugin-script
invocations through an unexpanded shell variable
(`"$PLANWRIGHT_ROOT/scripts/x.sh"`), `for`/`while` loops, and other expansions
that Claude Code flags "cannot be statically analyzed" and offers **no
persistent-allow** for. The result is near-continuous manual approval that both
floods the tower context and strains the never-type-into-worker-input posture.

This spec closes the flood with a **deterministic PreToolUse hook** that
auto-approves an enumerated set of known-safe command shapes and defers
everything else to the normal permission flow, keeping every existing
guardrail intact: no LLM in the approval path (honors fleet-autonomy D-18), the
worker-settings `deny` block enforced verbatim (a hook "allow" can never
override Claude Code's `deny`→`ask`→`allow` precedence), and human sign-off on
the permissions artifact. It complements the hook with the root-cause cleanup —
having the dispatching skills invoke plugin scripts by resolved literal path —
so the most common worker command shape is statically approvable even when the
hook degrades. The deliverable is a **mechanism** instantiating fleet-autonomy's
existing D-18 doctrine floor, not a new doctrine gap (D-1).

## Scope

### In scope

- A deterministic `PreToolUse` hook (portable POSIX/bash shell) that
  auto-approves a conservative, enumerated set of known-safe Bash command
  shapes issued by a dispatched worker, and defers everything else.
- The enumerated known-safe set and the every-segment-must-be-safe compound
  analysis, including recursive analysis of `fish -c "<inner>"`.
- Wiring the hook into `config/worker-settings.json` (the existing
  human-reviewed worker-permissions channel), keeping `defaultMode: default`
  and the `deny` block verbatim, scoped to worker sessions only.
- The root-cause cleanup: `/execute-task`, `/orchestrate`, and `/spec-kickoff`
  resolve the plugin/planwright root once and invoke plugin scripts by resolved
  literal absolute path.
- An adversarial test suite asserting zero false-allows and that the `deny`
  precedence holds.

### Out of scope

- Claude Code's `auto` / `bypassPermissions` permission modes (rejected by
  fleet-autonomy D-19; this hook is the LLM-free alternative that reaches the
  same no-flood goal).
- The `fleet-state-home-unresolved` observation (fleet-throttle / tower-marker
  failing under a marketplace install): a fleet-governance robustness gap
  orthogonal to worker permissions, left to fleet-autonomy or its own bundle
  (considered and scoped out; see Sources, left unconsumed).
- Coverage of any tool other than Bash (the hook considers only Bash; every
  other tool defers).
- An operator-configurable allowlist config knob (deferred pending drain-loop
  evidence; see `tasks.md` Deferred — the customization-boundary call in D-8).

## REQ-A — The auto-approve hook

- **REQ-A1.1** A deterministic `PreToolUse` hook SHALL auto-approve a
  conservative, enumerated set of known-safe Bash command shapes issued by a
  dispatched worker and SHALL defer every other command to the normal
  permission flow; no LLM SHALL be invoked in the decision path.
  *(Cites: D-1, D-2; fleet-autonomy REQ-G1.2/D-18 (Sources).)*
- **REQ-A1.2** The hook SHALL emit only an `allow` decision or defer
  (no decision); it SHALL NEVER emit a `deny` or `ask` decision. Approval is
  upgrade-only; blocking remains the job of `permissions.deny`/`ask`.
  *(Cites: D-3.)*
- **REQ-A1.3** The hook's `allow` SHALL NOT be capable of overriding
  `permissions.deny` or `ask`; the worker-settings `deny` block (planwright's
  hard invariants) SHALL remain enforced verbatim, since Claude Code evaluates
  `deny`→`ask`→`allow` regardless of hook output.
  *(Cites: D-3; fleet-autonomy REQ-E1.4/D-19 (Sources); the grounded permission facts (Sources).)*
- **REQ-A1.4** A command SHALL be auto-approved only if EVERY segment of a
  compound command (quote-aware split on `;`, `&&`, `||`, `|`, `&`, and
  newlines) is independently known-safe. Any ambiguity SHALL defer: unbalanced
  quotes, command or process substitution (`$(…)`, backticks, `<(…)`, `>(…)`),
  a write-redirect to any target other than `/dev/null`, or an unrecognized
  verb.
  *(Cites: D-3.)*
- **REQ-A1.5** The known-safe set SHALL comprise exactly: plugin/repo
  `scripts/*.sh` and `tests/*.sh` executed directly or via `bash`/`sh <path>`
  (never `-c`); read-only shell builtins and coreutils (with `find` excluding
  `-delete`/`-exec`/`-execdir`/`-ok`/`-fprint*` and `sed` excluding `-i`);
  read-only `git` subcommands; the lint/test runners `shellcheck`,
  `markdownlint`/`markdownlint-cli2`, `yamllint`, `bats`, and `mise
  run`/`tasks`; read-only `gh` (`pr view`/`list`/`status`/`diff`/`checks`,
  `auth status`, `repo view`); and shell control structures (`for`/`while`/
  `if`/`case`) whose conditions and bodies are themselves verified, including
  `fish -c "<inner>"` where `<inner>` recursively passes the same analysis
  within a bounded recursion depth.
  *(Cites: D-3; the validated prototype (Sources).)*
- **REQ-A1.6** Everything not in the known-safe set SHALL defer, explicitly
  including `rm`, `curl … | sh`, `sudo`, `bash -c`/`sh -c`, in-place edits,
  write-redirects to a non-`/dev/null` target, command substitution, mutating
  `git`/`gh` subcommands, and process kills (`kill`/`pkill`) — surfaced to the
  human via the normal prompt.
  *(Cites: D-3.)*
- **REQ-A1.7** The hook SHALL consider only the Bash tool; for every other tool
  it SHALL defer.
  *(Cites: D-2.)*

## REQ-B — Implementation, robustness, and security

- **REQ-B1.1** The hook SHALL be implemented in portable POSIX/bash shell with
  no dependency on python, fish, mise, tmux, or Ansible; the security-critical
  command-analysis logic SHALL be pure shell.
  *(Cites: D-4; bootstrap REQ-K1.5 (Sources).)*
- **REQ-B1.2** Extraction of `tool_name` and `tool_input.command` from the hook
  stdin payload SHALL use `jq`; when `jq` is absent the hook SHALL degrade to
  deferring every command (auto-approving nothing), never to a hand-rolled JSON
  parse and never to a false-allow.
  *(Cites: D-4; the `tasks-pr-sync.sh` jq-with-degradation precedent (Sources).)*
- **REQ-B1.3** The hook SHALL fail safe (defer) on any malformed input,
  unreadable stdin, internal error, or `fish -c` nesting past its bounded
  recursion depth.
  *(Cites: D-3, D-4.)*
- **REQ-B1.4** The hook SHALL NOT echo untrusted command content to a
  terminal-driving stream; its `permissionDecisionReason` SHALL be a fixed
  string rather than a reflection of the analyzed command.
  *(Cites: security-posture echo discipline (Sources).)*
- **REQ-B1.5** The hook script SHALL be held to planwright's framework-script
  security bar and gated by the self-hosting quality guards (shellcheck, shfmt,
  secret scan) that cover every shipped script.
  *(Cites: security-posture framework-script security (Sources).)*
- **REQ-B1.6** The hook SHALL ship with an adversarial test suite exercising at
  least the validated prototype's ~30 cases plus the regressions it surfaced
  (for example `echo ok; rm -rf x` MUST defer), asserting ZERO false-allows and
  that a `deny`-listed command is never auto-approved; the suite SHALL run under
  the repo's `mise run test` / CI.
  *(Cites: D-3; the validated prototype and its 30-case suite (Sources); security-posture (Sources).)*

## REQ-C — Wiring and delivery

- **REQ-C1.1** The hook SHALL be wired into `config/worker-settings.json` as a
  `PreToolUse` (Bash) hook, referencing the plugin script through the same
  `${CLAUDE_PLUGIN_ROOT}` mechanism the plugin's `hooks/hooks.json` uses so it
  resolves under a marketplace install; `defaultMode: default` and the `deny`
  block SHALL be kept verbatim.
  *(Cites: D-5, D-6.)*
- **REQ-C1.2** The auto-approve hook SHALL apply only to dispatched worker
  sessions (via `config/worker-settings.json`), never to the tower session or a
  human's interactive session; it SHALL NOT be added to the plugin-global
  `hooks/hooks.json`.
  *(Cites: D-5.)*
- **REQ-C1.3** `config/worker-settings.json` SHALL remain a human-reviewed,
  human-installed permissions artifact requiring human sign-off before use, and
  its manual merge/reference delivery SHALL be preserved (planwright never edits
  a user's `settings.json`); the fragment's `_about` documentation SHALL be
  updated to describe the hook, its no-LLM/allow-only/deny-precedence
  properties, and the human-sign-off posture.
  *(Cites: D-6; fleet-autonomy REQ-E1.4/D-19 (Sources); bootstrap REQ-I1.2 (Sources).)*

## REQ-D — Root-cause: literal script-path invocation

- **REQ-D1.1** `/execute-task`, `/orchestrate`, and `/spec-kickoff` SHALL
  resolve the plugin/planwright root once per invocation and call plugin
  scripts by resolved literal absolute path rather than through an unexpanded
  shell variable, so those invocations are statically analyzable by Claude Code
  (persistent-allow-able, and matchable by a literal-path allow entry) — closing
  the flood at its root for the `jq`-absent degradation path and independent of
  the hook.
  *(Cites: D-7; obs:344dd129.)*

## Changelog

- 2026-07-18 — Bundle drafted at Status Draft via `/spec-draft`, building on
  fleet-autonomy (Ready) as a new spec rather than an amendment. Four
  drafting-session decisions shaped scope: include the literal-path root-cause
  cleanup (REQ-D); scope `fleet-state-home-unresolved` out and leave it
  unconsumed; use `jq` with degrade-to-defer for JSON extraction (D-4);
  reconcile with fleet-autonomy REQ-E1.4/D-19 in place by citation rather than
  cross-bundle supersession (D-6).

## Sources

- **The worker-permission-ergonomics seed brief** — the invocation's framing
  document: the problem statement, the grounded permission facts, the validated
  prototype pointer, and the shipped-hook constraints (POSIX sh; new spec, not
  a fleet-autonomy amendment).
- **The validated prototype** — `worker-pre-tool-use.py` (python3, reference
  only) plus `worker-settings-hook.json` and a 30-case adversarial test suite,
  validated 2026-07-18 by carrying a full instruction-headroom Task-1 run
  (edit + verify + CI + polish + push + PR #232) with zero false-allows across
  ~30 adversarial cases and the live run; a quote-aware operator splitter fixed
  a real false-allow (`echo ok; rm -rf x`).
- **The grounded permission facts** (claude-code-guide, Claude Code docs
  v2.1.x): `permissions.deny` is enforced in every mode; `auto` mode is a
  server-hosted LLM classifier; a `PreToolUse` hook returning
  `permissionDecision: allow` skips the prompt, sees the full expanded command
  string, is deterministic, and cannot override `deny`/`ask`.
- **fleet-autonomy REQ-E1.4, D-18, D-19** — the no-LLM-daemon-mechanics floor
  (D-18/REQ-G1.2), the `auto`-mode rejection (D-19/REQ-E1.4), and the
  static-allowlist-as-permission-channel posture this spec reconciles with in
  place (D-6). The deterministic, same-channel, human-reviewed hook honors
  D-19's actual intent (no LLM in the approval path) and is not the `auto` mode
  REQ-E1.4 ruled out.
- **fleet-autonomy `tasks-pr-sync.sh`** — the shipped `#!/bin/sh` PostToolUse
  hook that already extracts hook-stdin JSON with `jq` and no-ops cleanly when
  `jq` is absent: the precedent for D-4's jq-with-degradation choice.
- **bootstrap REQ-K1.5** — planwright's validator, hooks, and scripts run on a
  portable POSIX/bash runtime with no dependency on fish, mise, tmux, or
  Ansible.
- **bootstrap REQ-I1.2** — planwright never edits a user's `settings.json`; the
  worker-settings profile is merged or referenced by the human.
- **security-posture** — framework-script security bar (never execute untrusted
  input, echo discipline, stay auditable, gated by the quality guards).
- **customization-boundary** — the capability-vs-style rule applied in D-8:
  the fixed conservative allowlist is core policy; an operator-configurable
  extension knob stays deferred until drain-loop evidence shows it generalizes.
- **obs:cf529bca** — `tmux-worker-prompt-flood`: the core problem observation
  (consumed by this bundle).
- **obs:344dd129** — `execute-task-literal-script-paths`: the root-cause
  literal-path observation framing REQ-D (consumed by this bundle).
- **`fleet-state-home-unresolved`** (observation, uid b085ac53) — considered as
  a seed and scoped out as orthogonal fleet-governance robustness; left
  **unconsumed** so it stays live for a future fleet-autonomy fix.
