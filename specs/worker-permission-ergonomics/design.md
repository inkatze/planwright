# Worker Permission Ergonomics — Design

**Status:** Ready
**Last reviewed:** 2026-07-18
**Format-version:** 2
**Execution:** derived — see the status render

Origin-tag legend: `N` = new to this bundle; `C, <namespace> <id>` = carried
from another bundle's decision, the foreign id namespace-qualified.

## Decision log

### D-1: Altitude — a mechanism under fleet-autonomy's D-18 floor (N)

**Decision:** This deliverable sits at the **mechanism** altitude: a concrete
tool (a deterministic `PreToolUse` hook plus its wiring) that instantiates
fleet-autonomy's already-established D-18 doctrine floor ("no LLM in the
approval path"). It is not a new doctrine gap. The one altitude question that
surfaced during drafting — whether the known-safe allowlist should be a
core-owned fixed policy or an operator-configurable knob — is a
capability-vs-style call, resolved in D-8, not an altitude promotion of the
whole deliverable.

**Alternatives considered:**
- Treat the safe-shape allowlist as new doctrine (an "impulse/rule about how to
  think"). Rejected because: the governing principle — deterministic mechanics,
  no model in the approval path — already exists as fleet-autonomy D-18. The
  allowlist is a mechanical classification table, not a rule about how to think;
  promoting it to doctrine would bury a concrete mechanism in the doctrine
  layer (the rot autopilot-reflex step 5 warns against).
- Skip the altitude record entirely. Rejected because: a weak mid-flow
  altitude signal did fire (the recurring capability-vs-style call on allowlist
  configurability), so per autopilot-reflex the altitude call is recorded as an
  early D-ID cited from the goal, cheaply, rather than pencil-whipped in
  conversation.

**Chosen because:** placing the deliverable at mechanism (with the doctrine it
serves named as fleet-autonomy D-18, and the one capability-vs-style sub-call
isolated in D-8) is the honest altitude and keeps each piece where a reader can
find it. Cites `doctrine/autopilot-reflex.md` (the six steps and the altitude
triggers) rather than restating it.

### D-2: A deterministic PreToolUse auto-approve hook, not a fatter allowlist or `auto` mode (N)

**Decision:** Close the flood with a deterministic `PreToolUse` hook that
inspects the full (post-expansion) command string and returns
`permissionDecision: allow` for known-safe shapes, deferring everything else.
The hook considers only the Bash tool.

**Alternatives considered:**
- Launch workers in `auto` mode. Rejected because: `auto` is a server-hosted
  LLM classifier — a model in the single most security-sensitive decision a
  worker makes — directly violating fleet-autonomy D-18/D-19, and it is
  mechanically unshippable through the project-scoped worker-settings channel
  (`defaultMode: auto` is honored only from a user's own `~/.claude`).
- Ship a fatter static allowlist only. Rejected because: Claude Code matches
  allow rules against the literal `$VAR` token, never its expansion, and offers
  no persistent-allow for expansion-flagged or loop commands — so a static
  allowlist cannot silence the exact shapes that flood, no matter how fat.
- Do nothing / require hands-on tmux prompt-answering. Rejected because: it
  floods the tower context and forces the operator to type into worker input,
  straining the never-type-into-worker-input posture.

**Chosen because:** a `PreToolUse` hook sees the fully-expanded command
(handling the `$VAR`-path and loop shapes the static allowlist cannot),
is deterministic script logic (D-18-clean, no model), returns allow-only, and
cannot override `deny`/`ask` — the flood closes with every guardrail intact.

### D-3: Allow-only, defer-everything-else, every-segment-safe (N)

**Decision:** The hook only ever upgrades a command to `allow` or defers; it
never emits `deny`/`ask`. A compound command is approved only if every segment
(quote-aware split on `;`, `&&`, `||`, `|`, `&`, newlines) is independently
known-safe; any ambiguity (unbalanced quotes, command/process substitution, a
non-`/dev/null` write-redirect, an unrecognized verb) defers. The known-safe
set is a conservative allowlist, not a denylist.

**Alternatives considered:**
- A denylist (approve everything except a blocked set). Rejected because: an
  unbounded default-allow surface is the wrong safety posture for a permissions
  mechanism; a new dangerous verb defaults to approved.
- Give the hook a `deny` capability. Rejected because: blocking already lives in
  `permissions.deny` (which the hook's allow cannot override anyway); a hook
  that both allows and denies would duplicate and could contradict the deny
  block. Approval is upgrade-only; denial stays in one place.

**Chosen because:** allow-only + conservative-enumeration + every-segment-safe
is the posture with zero false-allows: the validated prototype demonstrated it
across ~30 adversarial cases and a live run, and the one false-allow found
(`echo ok; rm -rf x`) was a splitter bug the every-segment rule is designed to
catch once fixed.

### D-4: `jq` for JSON field extraction, with graceful degradation; analysis in pure shell (N)

**Decision:** The shipped hook is portable POSIX/bash. It extracts `tool_name`
and `tool_input.command` from the hook-stdin JSON with `jq`; when `jq` is
absent it degrades to deferring every command. All command-analysis logic
downstream of extraction is pure shell.

**Alternatives considered:**
- Python (the prototype's language). Rejected because: not on planwright's
  portable runtime bar (bootstrap REQ-K1.5); the prototype used it for
  iteration speed only.
- Hand-rolled POSIX sh / awk JSON parsing. Rejected because: the command field
  holds arbitrary shell with arbitrary JSON escaping; hand-parsing it in a
  security boundary risks a false-allow on a crafted command — hand-rolled JSON
  parsing for a trust decision is an antipattern.

**Chosen because:** `jq` parses the two fields correctly, and its absence
degrades safely to today's behavior (defer → normal prompt), never to a
false-allow — the same jq-with-degradation pattern the shipped `tasks-pr-sync.sh`
hook already uses. Only the two-field extraction depends on `jq`; the
security-critical analysis stays in auditable pure shell.

### D-5: Worker-scoped wiring via `worker-settings.json`, not the plugin-global hooks (N)

**Decision:** Wire the hook into `config/worker-settings.json` as a
`PreToolUse` (Bash) hook, referenced through `${CLAUDE_PLUGIN_ROOT}` (the same
mechanism `hooks/hooks.json` uses), keeping `defaultMode: default` and the
`deny` block verbatim. Do not add it to the plugin-global `hooks/hooks.json`.

**Alternatives considered:**
- Add the hook to the plugin-global `hooks/hooks.json`. Rejected because: that
  file governs every session running the plugin — the tower and any human's
  interactive session included — so it would silently auto-approve commands far
  outside the dispatched-worker blast radius this mechanism is scoped to.
- A separate, new settings file for the hook. Rejected because:
  `worker-settings.json` is the established, human-reviewed worker-permissions
  channel; a second file fragments the review surface for no benefit.

**Chosen because:** `worker-settings.json` already scopes exactly to dispatched
workers and is already the human-reviewed permissions artifact; wiring the hook
there keeps blast radius and review surface where they belong, and
`${CLAUDE_PLUGIN_ROOT}` resolves the script path under a marketplace install.

### D-6: Reconcile with fleet-autonomy REQ-E1.4/D-19 in place, by citation (N)

**Decision:** fleet-autonomy REQ-E1.4/D-19 states the static allowlist "SHALL
remain the sole permission-approval mechanism for dispatched workers." This
spec adds the deterministic hook as a second approval component but reconciles
in place: the hook is deterministic (honors D-18), human-reviewed, and shipped
through the same `worker-settings.json` channel, so it honors D-19's actual
intent (no LLM in the approval path) and is not the `auto` mode REQ-E1.4 ruled
out. fleet-autonomy REQ-E1.4/D-19 is cited as a Source; no cross-bundle
supersede is written.

**Alternatives considered:**
- Cross-bundle supersede REQ-E1.4 (reword to "sole model-based approval
  mechanism"). Rejected because: it reopens a signed-off Ready sibling spec
  (Ready→Draft under the reopen cycle) and demands its own re-kickoff — heavy
  process for a tension that the intent reading already resolves.
- Ignore the tension. Rejected because: leaving an apparent contradiction
  between two live bundles unaddressed is exactly the drift the citation
  discipline exists to prevent.

**Chosen because:** the letter of "sole" was aimed at excluding the `auto`
classifier; a deterministic, same-channel, human-reviewed hook is categorically
not that. Citation-in-place records the reconciliation where the next reader
finds it without reopening a bundle about to execute.

### D-7: Root-cause literal-path invocation as complementary defense-in-depth (N)

**Decision:** `/execute-task`, `/orchestrate`, and `/spec-kickoff` resolve the
plugin/planwright root once and invoke plugin scripts by resolved literal
absolute path rather than through an unexpanded shell variable. The literal-path
**allow entry** in a worker's settings is install-location-specific and stays
adopter-documented, not hardcoded into the shipped `config/worker-settings.json`.

**Alternatives considered:**
- Rely on the hook alone. Rejected because: when `jq` is absent the hook defers
  everything, and a `$VAR`-path script invocation is *never* persistent-allow-
  able under the static allowlist — so the most common worker command shape
  keeps flooding on the degraded path. Literal-path invocation makes it
  statically approvable independent of the hook.
- Hardcode a literal-path allow entry into the shipped `worker-settings.json`.
  Rejected because: the plugin cache path is per-install (per-home); a hardcoded
  path is non-portable. The portable, durable change is the skill-side
  literal-path invocation; the allow entry is adopter-specific and documented.

**Chosen because:** literal-path invocation is both the root-cause fix the
observation identified and a defense-in-depth layer beneath the hook: it closes
the flood for the `jq`-absent degradation path and is simply the more correct
way to invoke a plugin script. Cites obs:344dd129.

### D-8: Fixed conservative core allowlist; no operator-configurable knob yet (N)

**Decision:** The known-safe allowlist is a fixed, conservative policy owned by
core, not exposed as an operator-configurable config knob. An operator who
needs a different set shadows the hook script through the overlay mechanism.

**Alternatives considered:**
- Ship a config knob to extend/override the allowlist. Rejected because: this
  is security-sensitive, and per the customization-boundary default tilt an
  unproven preference stays in an overlay until drain-loop evidence shows it
  generalizes. A configurable allowlist is a widened attack surface adopters
  could misconfigure, with no evidence yet that multiple contexts want it.

**Chosen because:** the capability-vs-style boundary here favors a fixed core
policy: the general *capability* (a deterministic pre-approval hook) lands in
core, but the *specific safe set* is a conservative default, not a knob, until
recurring drain-loop observations earn the graduation. The deferral is recorded
in `tasks.md` with a drain-evidence gate. Cites `doctrine/customization-boundary.md`.

## Cross-cutting concerns

- **Security boundary.** This is a permissions mechanism (security-posture:
  subprocess/shell construction, authorization, untrusted-input triggers). The
  hook parses Claude Code's hook payload and decides a trust upgrade, so its
  correctness bar is "zero false-allows", enforced by the adversarial suite
  (REQ-B1.6) and validated against the deny-precedence guarantee (REQ-A1.3).
- **Never-worse-than-status-quo.** Every degradation path (jq absent, malformed
  input, unknown shape, internal error) defers, which reproduces today's
  behavior (a normal permission prompt) — never a new approval the operator did
  not already get.
- **Research/verification note (for the risk register at kickoff):** whether
  Claude Code allow-globs can portably match a per-install plugin script path
  is version-sensitive and is why D-7 keeps the literal-path allow entry
  adopter-documented rather than shipped; and whether `${CLAUDE_PLUGIN_ROOT}`
  expands in a `--settings`-referenced worker fragment should be confirmed
  end-to-end during execution (the plugin's own `hooks.json` relies on the same
  expansion, which is the working precedent).
