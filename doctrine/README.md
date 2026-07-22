# planwright Doctrine

These documents are planwright's framework doctrine: the rules its skills apply
at runtime. They are owned by planwright, not by any adopter's personal
configuration (REQ-D1.4). Skills reference them via the stable rule-doc
resolution path defined below (REQ-I1.1, D-24).

| Doc | Covers | Primary citations |
| --- | --- | --- |
| [finding-categorization.md](finding-categorization.md) | The four finding buckets, their predicates, and the act-then-review autonomy gate | REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.6, REQ-C1.7 · D-4, D-5, D-6 |
| [gate-wiring.md](gate-wiring.md) | The gate's operational wiring: routing order, commit discipline, checklist and audit formats, ladder procedure, pause protocol | REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.6, REQ-C1.7 · D-4, D-5, D-6 |
| [kickoff-verification.md](kickoff-verification.md) | The `/spec-kickoff` lens and verification mechanics lifted out of the skill body: the mid-walk delta-scoped lens, the post-lens stale-reference sweep, the sign-off lens-review scope/fan-out and altitude check, and the terminal ready-flip CI gate (head-SHA rollup query, positive-green condition, bounded wait, head re-pin, refusal arm) | skill-rigor REQ-B1.1, skill-rigor REQ-B1.4, skill-rigor REQ-B1.5, skill-rigor REQ-A3.3, skill-rigor REQ-H1.3 · skill-rigor D-3, skill-rigor D-5, skill-rigor D-6, skill-rigor D-45 |
| [autonomous-safe-decision.md](autonomous-safe-decision.md) | The unattended orchestration tower's autonomy policy as a mapping onto the finding-categorization buckets and hard-pause zones (no parallel taxonomy); the never-auto-merge floor and escalation to the decision queue | orchestration-fleet REQ-A1.3, orchestration-fleet REQ-D1.4 · orchestration-fleet D-8, orchestration-fleet D-13 |
| [selection-contract.md](selection-contract.md) | The `/orchestrate` selection mechanics lifted out of the skill body: version-keyed ready-task candidacy (v1 `## Forward plan` placement vs format-version-2 derivational, the unparseable-version refusal) and the selector's exit contract (the exit-3 format-version-2 transient evidence hold as a clean report-and-end) | skill-rigor REQ-A1.3, skill-rigor REQ-A1.4, skill-rigor REQ-E1.1 · skill-rigor D-9, skill-rigor D-10 |
| [discovery-rigor.md](discovery-rigor.md) | Making the finding list complete: lens checklist, coverage table, tool-grounded discovery, fan-out, self-critique | REQ-D1.1 |
| [validation-rigor.md](validation-rigor.md) | Confirming findings are real (three passes plus adversarial bi-directional re-validation) and solutions are right (including the altitude check and surface-relative whole-system reproduction) | REQ-D1.2, REQ-D1.8, REQ-D1.9 |
| [refactor-instinct.md](refactor-instinct.md) | Small continuous refactors; low bar in implementation mode, high bar in review mode | REQ-D1.3 |
| [research-rigor.md](research-rigor.md) | When and how to research: triggers, source hierarchy, recency discipline, antipattern check, risk-register recording | REQ-D1.5 |
| [security-posture.md](security-posture.md) | Write-time security triggers, artifact data-hygiene, framework-script security | REQ-D1.6 |
| [proportionality.md](proportionality.md) | Rigor scales with stake and reversibility; scoping must be declared | REQ-D1.7 |
| [composability.md](composability.md) | Composability by default, in adopter code and in planwright itself | REQ-D2.1 |
| [engineering-decisions.md](engineering-decisions.md) | The engineering decision process: idioms first, tooling deference (toolchain pinned, defaults owned), the ecosystem-research move, the no-flattening escalation rule, the dependency-adoption checklist, priority balancing | REQ-G1.1, REQ-G1.3, REQ-G1.6 · D-15, D-16 |
| [customization-boundary.md](customization-boundary.md) | The capability-vs-style boundary: when a preference belongs in core (as an opt-in config knob) vs an overlay; decision-time criteria, the default tilt to overlay, two worked examples | customization-overlay REQ-C1.1, customization-overlay REQ-C1.2, customization-overlay REQ-C1.3 · customization-overlay D-10 |
| [autopilot-reflex.md](autopilot-reflex.md) | The six-step reflex for closing recurring-manual-ceremony gaps; altitude triggers, the phase re-anchor, the trigger-scoped altitude-D-ID rule | autopilot-reflex REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5 · autopilot-reflex D-1, D-2, D-11 |
| [release-tagging.md](release-tagging.md) | The release-tagging policy (autopilot-reflex instantiation A): the five policy points (detection automated, approval = human merge, publish human-gated + signed per policy, window locked, merge/publish never autonomous) and the capability/mechanism/value altitude split | autopilot-reflex REQ-B1.1, REQ-B1.2 · autopilot-reflex D-2, D-3, D-5, D-7, D-13 |
| [decision-domains.md](decision-domains.md) | The decision-domains catalog: entry format (trigger + considerations + disposition), lifecycle wiring, growth mechanics, the eleven seed domains | REQ-G1.8, REQ-G1.4 · D-39, D-16 |
| [guard-catalog.md](guard-catalog.md) | The builder's core guard catalog: guard categories, entry format, breadth dimensions, the extension model, the dogfood contract | REQ-G1.2, REQ-G1.5, REQ-G1.7 · D-15, D-16, D-32 |
| [instruction-hygiene.md](instruction-hygiene.md) | The instruction-layer authoring law: flow in skills / law in rule docs, the doctrine-manifest grammar, the loading convention and its safety floor, the word budgets, the test-and-measure principle, and the kept prompt-eval convention | prompt-hygiene REQ-C1.1, prompt-hygiene REQ-C1.2, prompt-hygiene REQ-C1.3, prompt-hygiene REQ-C1.4, prompt-hygiene REQ-C1.6 · prompt-hygiene D-1, prompt-hygiene D-2, prompt-hygiene D-3, prompt-hygiene D-5, prompt-hygiene D-6, prompt-hygiene D-7, prompt-hygiene D-8, prompt-hygiene D-9, prompt-hygiene D-10, prompt-hygiene D-11 |
| [accumulator-taxonomy.md](accumulator-taxonomy.md) | The three accumulator classes and their drain rituals, the `GATE(when:)` convention and its closed grammar (normative home), the shared drain pass behind `/drain` and `--bookkeeping` | REQ-H1.1, REQ-H1.2, REQ-H1.3, REQ-H1.4, REQ-H1.5 · D-17, D-18, D-31 |
| [spec-format.md](spec-format.md) | The versioned four-file spec format meta-spec: per-file fields, ID and citation conventions, status lifecycle, amendment ritual, kickoff-brief structure, sign-off records and content anchors, glossary | REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-A1.6, REQ-A1.7, REQ-A1.8, REQ-B2.2 · D-1, D-20, D-25, D-40, D-45 |
| [inception-format.md](inception-format.md) | The normative inception bundle format (the four-file format's venture-scope sibling): file set and per-file grammars, ID and track-label grammars, venture lifecycle and kill criteria, assumption / decision / plan-task field forms with the evidence-grade tokens, the frame template, the minimum core, gate-record forms, and the format-version rules | inception REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4, REQ-C1.5, REQ-C1.6, REQ-C1.7, REQ-C1.8, REQ-C1.9, REQ-C1.10, REQ-C1.11, REQ-E1.1, REQ-E1.2, REQ-E1.5, REQ-I1.1, REQ-I1.4 · inception D-1, D-13, D-14, D-18 |
| [interaction-style.md](interaction-style.md) | How skills conduct every attended human moment (comprehension, approval, handoff, report): the three disciplines (teach to the frontier, interview to completeness, present without steering) and the session mechanics (progress indicator, progressive disclosure, selectors with recommendations, running summary, small bites) | REQ-B3.1 · operator-dialogue REQ-A1.1, REQ-A1.2, REQ-B1.3, REQ-C1.1, REQ-C1.3, REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-D1.5 · operator-dialogue D-1, D-3, D-4, D-5, D-6, D-12 |
| [kickoff-dialogue.md](kickoff-dialogue.md) | How `/spec-kickoff` instantiates `interaction-style`'s three disciplines in-band across its walkthrough and sign-off: comprehend-first (with adaptive-level calibration: teach the frontier, fade the scaffolding via a lightweight per-concept estimate), backward-chaining completeness, present without steering, plus the shared-understanding approval summary that replaces the verdict-demand, the plain-language gate framing, and the structured decision/transcript log the behavioral eval grades | operator-dialogue REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5, REQ-C1.1, REQ-C1.2, REQ-C1.4, REQ-C1.5, REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-F1.1, REQ-F1.2, REQ-F1.3, REQ-G1.3, REQ-G1.6, REQ-H1.3 · operator-dialogue D-2, D-3, D-4, D-5, D-6, D-9, D-10 |
| [backend-capability-contract.md](backend-capability-contract.md) | The dispatch-backend capability contract and advertisement: the five named capabilities, the advertised capability set, orchestrator adaptation, and the existing backends mapped to it | orchestration-fleet REQ-B1.1, REQ-B1.2, REQ-B1.3 · orchestration-fleet D-2 |
| [context-budget-autoheal.md](context-budget-autoheal.md) | The long-running tower's context-budget monitor (the completed-step-count proxy signal and its knob) and the disposable-tower auto-heal handover (`continue-as-new`): rebuild-from-disk, the wake prompt as handover document, state-safety across the handover, and the never-auto-merge floor | orchestration-fleet REQ-C1.1, REQ-C1.2, REQ-C1.4, REQ-A1.2 · orchestration-fleet D-4 |
| [attention-notification-capability.md](attention-notification-capability.md) | The substrate-agnostic attention/notification capability lifted into core: heartbeat/awareness state under the cross-spec home, the portable status renderer, the alarm-rationalized decision queue, the overlay-valued notification seam, and deferral to a backend's own attention surface | orchestration-fleet REQ-E1.3, REQ-E1.4, REQ-A1.5, REQ-A1.6 · orchestration-fleet D-13 |
| [fleet-coordination-floor.md](fleet-coordination-floor.md) | The four fleet floors: the tower non-authoring boundary (dispatch/monitor/reconcile only; repo/config/content edits route to workers; decision-reversals surface as forks), the no-LLM-daemon-mechanics invariant (every daemon, hook, or cron mechanism is deterministic script logic on structured signals; LLM invocation stays reserved for tower and worker task work), the assume-multiplicity floor (a tower keeps tabs on peer towers and coordinates division rather than assuming solitude), and the deterministic-attention floor (a merge-ready PR reaches the operator by deterministic push, LLM-poll the fallback; mechanism owned by the planned merge-currency-guard spec) | fleet-autonomy REQ-G1.1, REQ-G1.2 · fleet-autonomy D-17, D-18 · concurrent-orchestrator-coordination REQ-A1.1, REQ-D1.3, REQ-D1.6 · concurrent-orchestrator-coordination D-1, D-6 |
| [orchestration-concurrency.md](orchestration-concurrency.md) | `/orchestrate`'s dispatch-record and reconciliation law: progress state as a derived projection, the locked window and the per-spec lock's scope, branch-first fail-safety, marker semantics, and the reconcile sweep's fetch-first refresh, PR-state-first rule, and orphan predicate | orchestration-concurrency REQ-A1.1, REQ-A1.2 · orchestration-concurrency D-1, D-3, D-10 |
| [orchestration-modes.md](orchestration-modes.md) | `/orchestrate`'s rare mode branches, read at point of use: the degradation ladder and runtime failover (degrade capability, never safety), the meta-tower (`--meta`: fleet lock, live-count bound, subordinate independence), and the fleet entry (`--fleet`: two-seam presentation, detached multiplexer plumbing, the attention surface) | orchestration-fleet REQ-B1.5, REQ-B1.6, REQ-D1.1, REQ-D1.2, REQ-D1.5, REQ-E1.1, REQ-E1.2, REQ-E1.5 · orchestration-fleet D-3, D-6, D-9, D-12, D-13 |
| [inter-orchestrator-coordination.md](inter-orchestrator-coordination.md) | The coordination protocol between towers and workers: the division of labor (tower owns reconcile/dispatch/cleanup, worker owns its branch's conflict resolution) and the "directly" boundary; the attributed, non-impersonating relay against a live worker (buffer-paste steer, capture-pane observe, never send-keys, never answer a permission prompt); the relay security bounds (handles validated, output as data) enforced by `scripts/orchestrate-relay.sh` | orchestration-fleet REQ-D1.2, REQ-D1.3, REQ-B1.7, REQ-A1.6 · orchestration-fleet D-7 |
| [plugin-script-invocation.md](plugin-script-invocation.md) | How the dispatching skills invoke planwright's own scripts: resolve the root once per invocation, call by resolved literal absolute path (never an unexpanded `$VAR/scripts` shape), and the adopter literal-path allow entry | worker-permission-ergonomics REQ-D1.1 · worker-permission-ergonomics D-7 |

## Resolution convention

Skills, hooks, and scripts resolve a rule doc by basename through one stable
path that works in both delivery modes, with no mode detection:

```text
${PLANWRIGHT_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_DIR:-$HOME/.claude}/planwright}}/doctrine/<doc>.md
```

- **Plugin delivery (primary, D-24):** Claude Code sets `CLAUDE_PLUGIN_ROOT`
  to the plugin's install directory; docs resolve plugin-relative.
- **Writer delivery (fallback):** `scripts/install.sh` copies this directory
  to `<claude-dir>/planwright/doctrine/` (`<claude-dir>` is `$CLAUDE_DIR` when
  set, else `~/.claude`); the fallback arm of the chain finds it there.
- **Override:** `PLANWRIGHT_ROOT` pins an explicit root (tests, adopters
  embedding planwright elsewhere). It wins over both.
- **Self-location (final fallback):** when no env root resolves, the resolver
  locates the core doctrine relative to its own path (`<script-dir>/../doctrine/`),
  since the doctrine ships beside the script. This covers the common
  plugin-subshell case where Claude Code does not export `CLAUDE_PLUGIN_ROOT`
  into a skill's Bash. Additive and lowest-precedence, so it never overrides
  an env root.

The writer arm requires `CLAUDE_DIR` or `HOME`; when neither is set
(minimal containers), the resolver skips that arm, and the self-location
fallback still resolves the shipped core doctrine.

`scripts/resolve-rule-doc.sh <doc-name>` implements the chain (validating the
name against the `^[a-z0-9][a-z0-9-]*$` identifier discipline before any path
is formed) and prints the resolved path; prefer it over hand-building paths.

Doc names are kebab-case basenames without the `.md` suffix, e.g.
`discovery-rigor`, `finding-categorization`.

## How the docs relate

[Discovery Rigor](discovery-rigor.md) produces the finding list.
[Validation Rigor](validation-rigor.md) confirms each finding and each fix.
[Finding Categorization](finding-categorization.md) routes confirmed findings
through the autonomy gate that decides what the agent applies versus what
waits for the human; [Gate Wiring](gate-wiring.md) is that gate's operational
procedure (how dispositions are applied, committed, recorded, and surfaced).
The [Autonomous-Safe-Decision Policy](autonomous-safe-decision.md) reads that
same gate at the orchestration tier, defining what an unattended tower may
decide versus what it must escalate to the human.
[Research Rigor](research-rigor.md) and the
[Security Posture](security-posture.md) fire on their triggers at any point in
that flow. [Refactor Instinct](refactor-instinct.md) and
[Composability](composability.md) shape the code being written.
[Engineering Decisions](engineering-decisions.md) governs the choices made
while writing it, and the [Decision-Domains Catalog](decision-domains.md)
supplies the triggers that route load-bearing choices to the human instead
of a default. The [Core Guard Catalog](guard-catalog.md) is the mechanical
counterpart: the universal quality guards the builder applies to a detected
stack, with the same no-flattening rule keeping it from auto-defaulting a
load-bearing decision. What any of these defer instead of deciding lands in an
accumulator, and the [Accumulator Taxonomy](accumulator-taxonomy.md)
guarantees it re-surfaces (no write-only deferral).
[Proportionality](proportionality.md) governs how strictly
all of the above scale with what is at stake. The
[Autopilot Reflex](autopilot-reflex.md) is the thought process for closing a
recurring-manual-ceremony gap — automate up to the irreducible human gates,
never through them — and supplies the altitude discipline (triggers,
re-anchor, the trigger-scoped altitude D-ID) the authoring skills apply while
producing specs. The instruction layer carrying
all of it is itself governed: [Instruction Hygiene](instruction-hygiene.md)
is the authoring law for skills and these docs — what loads when, within what
budget, verified how — and it is itself a catalogued breadth dimension
(`instruction-hygiene` in the [Core Guard Catalog](guard-catalog.md#instruction-hygiene)),
so the builder can recommend the same size guard and kept-eval convention to an
adopter whose repo authors an instruction layer. Upstream of execution,
[Interaction Style](interaction-style.md) governs every attended human moment
across the pipeline — beginning with the interactive authoring sessions that
produce the specs everything above executes against — and the
[Customization Boundary](customization-boundary.md) governs a scoping call made
in those sessions: whether a candidate preference belongs in core (as an opt-in
config knob) or in an adopter/team overlay.

## Adopter extension

Adopters supply project-specific tooling and rigor through their own project
configuration (project memory files, the tool-discovery hook's detected
toolchain, project config for thresholds and toggles), never by editing these
docs (REQ-D2.2). The docs define the framework's invariant behavior; the
project supplies the ground the behavior runs on.
