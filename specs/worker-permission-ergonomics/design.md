# Worker Permission Ergonomics — Design

**Status:** Draft
**Last reviewed:** 2026-10-05
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

**Superseded-by: D-10** (2026-10-05) — its rationale rested on the hook
seeing the fully-expanded command, which was never true: Claude Code hands a
hook the raw command string. The hook choice stands; the premise does not.

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

**Superseded-by: D-12** (2026-10-05) — the drain evidence this decision
waited for arrived (four observations from live fleets and the operator's
direct delegation), so the configurability graduates as the self-approval
policy; a free-form per-verb allowlist extension still does not.

### D-9: Altitude of the 2026-10-05 extension — policy plus mechanism, one doctrine clarification (N)

**Decision:** The extension sits at two rungs of the altitude ladder, with one
doctrine sentence. The **capability** is a worker-side self-approval policy:
a core config knob whose arms the guard evaluates. The **mechanism** is the
guard's added grammar and the launcher's scratch root. The operator's chosen
arms are a **local value** in an overlay. The **doctrine** gains one
clarification, placed where the existing rule already lives (the
inter-orchestrator-coordination doctrine's "never answer a worker's
permission prompt on the tower's judgment" section): unattended means
out-of-policy prompts park for the operator, and the configured policy is the
only self-approval surface.

**Alternatives considered:**
- Mechanism only, no doctrine sentence. Rejected because: the seed pinned two
  altitude claims ("Wasn't this supposed to be unattended?"; "define the
  self-approval surface as one configurable standing policy instead of a live
  delegation to the tower"), and the live run showed the gap: the operator
  had to delegate to a tower outside any written rule. Without the doctrine
  statement the next session repeats that delegation.
- A new doctrine document for unattended operation. Rejected because: the
  governing rule already exists in inter-orchestrator-coordination; a second
  document would split one rule across two homes.

**Chosen because:** each piece lands where autopilot-reflex step 5 places it.
The policy is a seam adopters set, the guard fills it, and the one sentence of
doctrine states the contract the seam serves. Cites the pinned seed claims
(Sources) and `doctrine/autopilot-reflex.md`.

### D-10: The hook decides from the raw command string (supersedes D-2's rationale) (N)

**Decision:** The deterministic PreToolUse hook stays the approval mechanism
(D-2's choice), on a corrected premise: Claude Code hands the hook the
command exactly as written, with `$VAR` references and assignments
unexpanded. Every expansion the guard approves, it resolves itself from text
the same command supplies, and anything it cannot resolve defers. Assertions
about platform behaviour are pinned by observation, not taken from prose:
the deny outcome is asserted against the real deny block (REQ-A1.11), and the
matcher's behaviour inside a command substitution is observed and recorded
(REQ-H1.2).

**Alternatives considered:**
- Keep D-2 unchanged. Rejected because: the stated premise is false
  (measured on CLI 2.1.270 through a `--settings` hook), and a stale premise in
  a security decision is exactly what the observation behind the live
  false-allow traced the defect to.
- Replace the hook (for example with a static allowlist only). Rejected
  because: D-2's other reasons still hold; the static matcher refuses every
  `Contains simple_expansion` shape and offers no persistent allow for them.

**Chosen because:** it keeps the working mechanism and fixes the reasoning the
guard's grammar is built on. Cites obs:9c1cf997, obs:4dda9fe1, obs:aed9ca33.

### D-11: Command substitution — fix it at the source, admit only the argument-independent form (N)

**Decision:** Two layers. **Source:** plugin scripts resolve the values
workers fetched by substitution (`step-record.sh --head` defaults to the
current `HEAD`), so the commonest shapes disappear. **Guard:** a `$(…)` is
admitted only when its inner text independently passes the read-only
analysis, it has no nesting, no backtick and no parenthesis inside a quote,
and its output (directly or through a variable assigned from it) reaches only
argument-independent positions: operands of verbs whose approval ignores
operand values (the trusted repo and plugin scripts, `echo`, `printf`,
`test`, `[`). Under that condition the unknown text is equivalent to some
literal the guard would already approve, so the substitution cannot smuggle
anything an argument screen exists to stop. The same reasoning closes the
live hole: any unresolved or opaque `$` reaching a screened operand defers,
and a `for` variable is checked once per literal head word.

**Alternatives considered:**
- Always defer substitution and rely on the skills-emit-plain-commands flight.
  Rejected because: the replay shows workers improvise the shape (a launch
  prompt saying "no `$()`" did not stop the 80-minute stall), and it was about a
  fifth of the residual prompts.
- Admit substitution wherever the inner command is read-only. Rejected
  because: the outer verb's argument screens would then judge text they never
  see; the `find . $(echo -exec id \;)` class is exactly that.
- Defer and send the worker a reason so it rewrites the call. Rejected
  because: it needs a hook decision other than allow, which REQ-A1.2 forbids,
  and depends on unverified hook behaviour; it stays available as later
  research.

**Chosen because:** the source fix shrinks the need, and the guard rule is
argued sound, not just tested, which matters after the awk lexer lesson (a
partial parser in an allow-only screen produced four working false-allows in
an hour). The parser surface is kept deliberately small. Cites obs:9255e1d1,
obs:3ed95276 (lesson), the live-run prompt replay (Sources).

### D-12: One configurable self-approval policy, read-only by default (supersedes D-8) (N)

**Decision:** The worker's self-approval surface is one config knob resolved
through the overlay layers, its value a set of arms: `read-only` (what the
guard approves today), `own-branch` (writes confined to the worker's unit
branch and worktree), and `scratch` (writes under the worker's scratch root).
Core ships `read-only` alone. An operator enables the other arms in an
overlay. Any value the guard cannot read resolves to `read-only` alone. The
guard is the only evaluator.

**Alternatives considered:**
- All three arms on by default. Rejected because: customization-boundary
  requires a core capability to land opt-in with a behaviour-preserving
  default; an upgrade must not silently widen what every adopter's workers
  write unasked.
- A live delegation to the tower (the operator's 2026-10-03 stopgap).
  Rejected because: doctrine forbids the tower answering a permission prompt
  on its judgment, the harness classifier refused a tower-side filter as a
  bypass, and a live delegation is not a written rule anyone can audit.
- Separate knobs per arm. Rejected because: the seed asks for "one
  configurable standing policy", and one set-valued knob reads as one policy
  with a single fail-closed fallback.

**Chosen because:** the general capability (self-approval by arm) lands in
core, the operator's value lands in an overlay, and the default reproduces
today. Cites `doctrine/customization-boundary.md`, obs:1f1141ec,
obs:82bab6e3, the operator's live-run delegation (Sources).

### D-13: The floor is checked first and composes with the existing guards (N)

**Decision:** Before any arm is evaluated, the guard refuses to approve the
floor: PR merge, the ready flip and its undo, force-push, amend, rebase,
squash, branch reset, a push to any ref but the session's own unit branch, a
write outside the worktree and scratch root, every `gh` write, and anything
the deny block or the policy guard refuses. The `own-branch` arm's base merge
additionally requires human-gates' `worker_base_merge` to allow it; the
policy guard keeps running beside the command guard and stays the
deny-emitting layer. The `own-branch` arm deliberately does not grant
human-gates' `unpushed_rewrite`: an amend or rebase still reaches the operator
even where that policy permits it.

**Alternatives considered:**
- Let the arm grant whatever the human-gates policy permits. Rejected because:
  the operator's delegation named force-push, amend and rebase as the floor;
  the policy guard permitting an act means it is not refused, not that it may
  run unasked.
- Encode the floor only in the deny block. Rejected because: deny globs are
  best-effort against exotic spellings (the profile's own `_about` says so);
  the guard classifying the same acts gives a second, independent refusal to
  approve.

**Chosen because:** an allow-only guard that refuses the floor before
consulting the policy cannot be configured into approving it, and the
existing deny-emitting layers stay authoritative. Cites the operator's
live-run delegation (Sources), human-gates Task 10 (Sources).

### D-14: A launcher-created scratch root, writes only (N)

**Decision:** The worker launcher creates one scratch directory per worker,
owned by the worker, exports it as `TMPDIR`, and records it where the guard
resolves the session's scratch root. The `scratch` arm approves writes whose
targets canonicalize inside it, never executing or sourcing anything there.

**Alternatives considered:**
- Trust any path under `/tmp` or the system temp root. Rejected because: other
  sessions and users write there; "created by this worker" cannot be decided
  from a path under a shared root.
- Trust directories the worker made with `mktemp` earlier in the session.
  Rejected because: the guard is stateless per call and would need a
  side-store of minted paths, a new writable trust input.
- Approve executing scratch scripts. Rejected because: running self-written
  code is arbitrary execution; it would make every command approvable by
  writing it to a file first (140 of the replayed prompts were exactly that
  shape, which is why the rule must be stated).

**Chosen because:** a root the launcher creates is decidable from the path
alone and needs no state. Cites obs:1f1141ec, obs:65c35236.

### D-15: The profile ships the static read-only allow set and the `-u` push spelling (N)

**Decision:** `config/worker-settings.json` gains static allow rules for the
read-only verbs the operator's user-scope stopgap carried (read-only `git`
subcommands, `grep`, `sed -n`, `cat`, `head`, `tail`, `wc`, `ls`, `jq`, `cut`,
`sort`, `uniq`, `diff`, `stat`), excluding `awk`, `find`, `xargs` and bare
`sed`, plus `git push -u origin`. Each rule passes the permission-matcher
fixture table.

**Alternatives considered:**
- Leave the static layer alone; the hook covers these. Rejected because: the
  hook degrades to deferring everything without `jq`, and Claude Code's own
  matcher splits compounds per subcommand, so the static rules approve some
  shapes the hook defers.
- Recommend user-scope rules in the docs. Rejected because: user scope widens
  the operator's interactive and tower sessions too, the blast radius D-5
  rejected for the hook.

**Chosen because:** it moves the stopgap to the profile it belongs to. Cites
the dotfiles stopgap (Sources), obs:33812f90.

### D-16: Profile changes reach a worker only by relaunch; the supervisor offers one (N)

**Decision:** The fleet guide states that permissions and the policy's
launch-time inputs load at session start. The stream-json supervisor gains a
relaunch that resumes the worker's persisted session under the currently
installed profile, passing that profile explicitly: the Claude Code sessions
documentation states a resumed session does not restore `--settings`, so an
implicit resume would come back with no worker profile at all.

**Alternatives considered:**
- Document only. Rejected because: a fleet mid-run has no way to apply a
  shipped permission fix short of killing workers and losing their context.
- Hot-reload settings. Rejected because: the harness offers no such mechanism.

**Chosen because:** it turns "the fix never reaches running workers" into one
supervisor command. Cites the live-run report (Sources).

### D-17: The meta-tower runs the single-spec step itself (N)

**Decision:** Under `--meta`/`--fleet`, the meta-tower performs the chosen
spec's single-spec step (per-spec lock, freshness gate, dispatch record,
worker launch) in its own session under its own tower profile. The
subordinate tower session is removed. The orchestration-modes doctrine's meta
step is amended to match.

**Alternatives considered:**
- Keep the subordinate session and pin the tower profile when the launch role
  is a tower. Rejected because: it keeps a whole session per dispatch whose
  only job is one deterministic step, and adds a launch-role input the
  structural settings pin must trust.
- Leave it. Rejected because: the subordinate's bookkeeping prompts the
  operator before any worker starts (four prompts in the live run).

**Chosen because:** work-placement's smallest-sufficient-rung and
tower-frugality axioms: a session is not the smallest rung for one
deterministic step. The per-spec lock still serializes the step, so the
division of labour the meta-tower doctrine protects is kept by the lock, not
by a session boundary. Cites the work-placement doctrine (Sources),
orchestration-fleet D-6 (Sources).

### D-18: Standing-decision segment matching is deferred behind settle delivery (N)

**Decision:** tower-comms' literal-prefix matcher is left unchanged. Matching a
standing decision over split segments is deferred until a standing-decision
settle actually answers the worker's live prompt.

**Alternatives considered:**
- Supersede tower-comms REQ-E1.5 here. Rejected because: a settle today closes
  the queue item without unblocking the worker (obs:fd1824a4), so a wider
  matcher closes more items while workers stay blocked, and the edit would
  move tower-comms' anchor mid-execution.
- Reconcile by citation in place. Rejected because: the two match rules would
  differ in meaning, the drift citation-in-place avoids only when meanings
  agree.

**Chosen because:** with the worker-side policy, in-policy commands never
reach the tower, and the remaining value depends on a fix another bundle
owns. Recorded as a gated deferral.

### D-19: Segments are analysed in run order; `cd`, plain assignments, and timing verbs are modelled (N)

**Decision:** The analyzer walks the segments in order, carrying the state a
segment establishes. A leading `cd` to a plain literal inside the session's
own worktree sets the working directory for what follows; any other `cd`
defers. A `NAME=<plain literal>` assignment makes later `$NAME` that literal,
for any value. `time` and `timeout <duration>` are transparent prefixes. The
read-only set gains the wait and inspection verbs the replay surfaced.

**Alternatives considered:**
- Approve `cd` anywhere. Rejected because: later segments' containment checks
  would be judged against the wrong directory, and a `cd` out of the worktree
  is the first step of every write-outside-worktree shape.
- Restrict assignment resolution to trusted-root paths (today's rule).
  Rejected because: workers assign ordinary literals (`f=roles/...; grep $f`)
  and the substitution is exactly what the shell does with a plain literal.

**Chosen because:** these shapes were the largest single class in the replay
(a leading `cd` alone was about a quarter of the prompts), and each is
resolvable from the command text alone. Cites obs:885bc3c9, obs:01629047,
obs:23a619c0, the live-run prompt replay (Sources).

**Known residual:** Claude Code prompts on its own when a `cd` changes
directory before a `git` call (a safety gate against running another
directory's git hooks), and a hook `allow` does not suppress it. Approving
`cd` therefore helps non-`git` chains only; for `cd <worktree> && git …` the
fix is upstream: a worker already runs in its worktree, so the guide and the
launch text say to issue `git` without a `cd`. The same holds for Claude
Code's sensitive-path prompt on reads under the harness's own plugin
directories. Cites research: Claude Code permissions doc (Sources).

### D-21: A minimal hashed audit log of allow decisions (N)

**Decision:** Each `allow` the hook emits appends one line to a worker-local,
append-only log under the fleet state home: time, session, the arm or
category that approved it, and a hash of the command. The command text is
never written. A log write that fails leaves the decision unchanged, and the
log has a retention bound. This lifts the bundle's deferred runtime audit log.

**Alternatives considered:**
- Log the full command text. Rejected because: commands carry what workers
  type, tokens included, and the log would need the attention store's
  redaction rules; a hash lets a reviewer confirm a suspected command against
  the transcript without the log becoming a second secret store.
- Keep the log deferred. Rejected because: the deferral's own gate fired (a
  real false-allow, obs:9255e1d1), and this delta starts approving writes.

**Chosen because:** an approval now leaves a trace naming which arm granted
it, at the smallest data-hygiene cost. Cites obs:9255e1d1,
`doctrine/decision-domains.md` (observability).

### D-20: A sanitized corpus of real prompts is the acceptance test (N)

**Decision:** A sanitized corpus drawn from real worker prompts joins the
adversarial suite: every in-policy row approves under its arm, every floor
row defers under every policy value, and every uncovered row defers. Rows
are reduced to command shape: no hostnames, user paths, tokens or repository
names.

**Alternatives considered:**
- Hand-written fixtures only. Rejected because: the bundle's first delivery
  passed its hand-written corpus and still approved almost nothing workers
  actually issued.

**Chosen because:** it measures the delta against the traffic it exists to
serve, and floor rows make every policy value prove it cannot approve the
reserved acts. Cites the live-run prompt replay (Sources).

## Cross-cutting concerns

- **Security boundary.** This is a permissions mechanism (security-posture:
  subprocess/shell construction, authorization, untrusted-input triggers). The
  hook parses Claude Code's hook payload and decides a trust upgrade, so its
  correctness bar is "zero false-allows", enforced by the adversarial suite
  (REQ-B1.6) and validated against the deny-precedence guarantee (REQ-A1.3).
- **Write approvals are new territory (2026-10-05).** Until this extension the
  hook approved read-only and trusted-repo shapes only. The `own-branch` and
  `scratch` arms approve writes, so the write-time security triggers (path
  handling, authorization, untrusted input) all fire for the delta's tasks:
  every write target is canonicalized and containment-checked before any
  arm approves it, and the floor is evaluated first.
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
