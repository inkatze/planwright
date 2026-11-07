# Observation backlog triage, 2026-11

A proposal for the operator: where each of the 862 unconsumed observation fragments under
`specs/_observations/entries/` belongs, and which small changes would consume them. Nothing has been
moved or marked consumed; consuming a bundle stays the job of the change that lands it.

## The short version

- **122 are already covered** by a change on main: they can be consumed now, citing the commit
  listed below.
- **76 are duplicates** of another fragment, and **16 are stale** (the thing they describe is gone
  or was superseded).
- **648 are still open.** They fall into 149 bundles, each sized for one pull request (a spec task,
  an amendment or a small flight).

The five bundles that would consume the most open fragments:

1. **Stale doc, comment and manifest claims sweep** (21 open; a spec-less flight, `flight`): One
   sweep correcting the listed stale claims across docs, doctrine, comments, skill text and plugin
   manifests, citing sources instead of restated chains.
2. **Custom-steps amendment: open points, stale Deferred entries, wording** (20 open; custom steps,
   `specs/custom-steps/`): One custom-steps amendment pinning preamble layout, resume and re-fire
   ordering, pool and full-suite record fields, reserved-control refusal at resolve time, halted-arm
   scenarios, resolved-location wording, and closing stale Deferred entries and check:echo-safety
   names.
3. **Move remaining private grammar copies onto spec-parse** (16 open; format grammar and parser
   unification, `specs/format-grammar/`): Re-point the remaining private task, header, status and
   anchor-entry parsers onto spec-parse, add fence-aware rewriter and verbatim-emit helpers, fail
   closed on NUL screens, and fix the Task 2 consumer list and REQ-E1.3 clause.
4. **Load-sensitive test assertions and races** (16 open; test throughput,
   `specs/test-throughput/`): Replace wall-clock ceilings with polls or clock seams, add diagnostics
   to load-failing assertions, cap parked-shim waits, and investigate the lost-write and step-record
   races.
5. **Config and knob read spawn cost** (12 open; universal binary (portability and spawn cost),
   `specs/universal-binary/`): Add a batched multi-key config read with per-process overlay-root
   memoization and adopt it in the multi-knob callers (guards, resolve-steps, tower-queue,
   mc-program, registry lookup, resolve-root).

A bulk consume of the covered and stale fragments, plus the duplicates whose surviving fragment is
already closed, would clear 153 fragments without any code change. The other 61 duplicates repeat a
fragment that is still open, so they are consumed with that fragment's bundle.

## How this was made

Six readers each took a contiguous date range of fragments, read every one, picked its owner by
subject, and checked the current tree and `git log` on main for a landed fix. A fragment counts as
covered only where a named commit is on main and the current tree shows the fix; anything less
stayed open. A consolidation pass then merged the readers' bundle names, found duplicates across
date ranges by reading both fragments, and re-checked ten covered rows against their commits (all
ten held).

Limits worth knowing before acting on it:

- Owner choices between neighbouring specs (for example human gates against worker permission
  ergonomics for guard fragments) are judgment calls; the bundle tables name the owner picked.
- Several fragments are partly fixed. They stay open, and their change names only what is left.
- Duplicates are same-substance only, never same-area. Some broad bundles still hold fragments that
  are related but separate asks.
- Fragments owned by a spec whose status is Done need an amendment to that spec rather than a new
  task.
- `flight` means a small spec-less fix; `new-spec` means no current spec owns the subject.

## Bundles

Ordered by how many open fragments each would consume. Each lists its owner, the smallest change
that consumes every open fragment in it, and the fragments (closed ones in the bundle are listed in
the sections further down).

### B1. Stale doc, comment and manifest claims sweep

- Bundle id: `flight-doc-accuracy-sweep`
- Owner: a spec-less flight (`flight`)
- Open fragments: 21
- Smallest change: One sweep correcting the listed stale claims across docs, doctrine, comments,
  skill text and plugin manifests, citing sources instead of restated chains.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-16-parallel-test-runner-07deea2a` | Fail-fast runner opportunity is implemented by run-tests.sh; old entry should be marked resolved | Mark the 2026-06-18 fail-fast runner opportunity resolved by scripts/run-tests.sh |
| `2026-07-17-req-id-cross-bundle-citations-225257e9` | options-reference rows cite REQ-E1.4 by-layer policy without naming customization-overlay | Qualify the options-reference REQ-E1.4 citations with customization-overlay |
| `2026-07-20-fenced-vs-wrapped-inline-code-spans-148dc028` | Wrapped inline-code command spans draw recurring bot false positives; convert or keep dismissing | Convert wrapped multi-line inline command spans to fenced blocks repo-wide |
| `2026-07-20-unqualified-xspec-cites-fh-fa167d02` | Bare fleet-autonomy REQ citations remain in fleet scripts; convention plus validator warning wanted | Adopt a bundle-qualify convention for foreign REQ-IDs with a spec-validate warning |
| `2026-09-03-guard-enumeration-drift-244fe935` | CONTRIBUTING and ci.yml comment omit guards; mise-root coupling in ci.yml has no note. | Reconcile both guard lists with check's depends and add the mise-root coupling note. |
| `2026-09-13-orchestrate-skill-lock-prose-0c785f8f` | orchestrate SKILL.md misdescribes lock exit 1 and documents the detached acquire with no owner pid | Correct step 1 prose and pass --owner-pid in the documented acquire |
| `2026-09-22-config-model-no-lists-08213768` | Flat config has no list encoding; set-valued knobs must be space-separated | Add one sentence on set-valued knobs to the options-reference conventions |
| `2026-09-22-deferred-gate-evaluated-at-drain-ab235eb8` | Gates say evaluated at drain while the drain surfaces free-text gates and never evaluates them | Sweep the corpus to (free-text condition, surfaced at drain) |
| `2026-09-22-unit-glossary-widening-4ae3073b` | Glossary Unit is task or bundle; custom-steps widens it to spec and flight | Widen the Unit glossary entry in doctrine/spec-format.md |
| `2026-09-23-lease-interval-comment-simplified-cc5e2bfb` | defaults.yml tower_lease_interval comment says it only catches a dead tower; it also voids hand-overs | Correct the tower_lease_interval comment in config/defaults.yml |
| `2026-09-24-accumulator-wording-925c8ebc` | Comments say underscore-prefixed dirs are accumulators; _flights is a record dir now | Reword the listed comments and skill lines to name record directories too |
| `2026-09-24-plugin-script-invocation-consumer-count-0063be32` | plugin-script-invocation.md still says the three dispatching skills though more skills carry the pointer | Replace the count with the skills carrying the pointer; derive the test list from the pointer |
| `2026-09-25-custom-steps-tower-forward-declared-ff53f7b2` | doctrine/custom-steps.md still says tower is forward-declared though skills/tower has landed | Drop the forward-declared sentence from doctrine/custom-steps.md |
| `2026-09-28-isolation-stale-config-get-claim-81a9f77d` | resolve-dispatch-isolation.sh justifies its walk by a config-get limit that --layers removed | Update the comment, or move the walk onto config-get --layers |
| `2026-09-28-secret-screen-callers-5489e2e8` | docs/recurring-failure-classes.md calls inception-secret-screen.sh dead though two scripts call it | Correct the dead-script claim in docs/recurring-failure-classes.md |
| `2026-09-29-chain-restatements-bbf73358` | Skills and docs restate partial core root chains that will drift from spec-format | Point the restatements at spec-format The core root chain and resolve-root.sh install |
| `2026-10-06-tower-skill-brief-grace-wording-8030ea8a` | tower SKILL.md names the retired stale-lock threshold as the brief cleanup bound | Reword to the fixed brief grace in flight-dispatch.sh |
| `2026-10-19-flight-sweep-header-e4f08698` | flight-sweep.sh header uses future tense for the shipped /resume tower mode | Reword the flight-sweep.sh header to present tense |
| `2026-10-25-eval-fallback-publish-flag-d3baa9bf` | README says PLANWRIGHT_PUBLISH_DISABLED blocks publishing, but live tower flights still push | Reword the behavioral-eval README Security section to say flights still publish |
| `2026-10-26-flight-rules-d13-citation-f773e633` | flight-rules.md cites D-13 in its body but not in its Citations line or README row | Add D-13 to flight-rules.md Citations and its doctrine/README.md row |
| `2026-11-04-manifest-description-positioning-7a636352` | plugin.json and marketplace.json still use the autopilot/software-factory wording | Rewrite the manifest descriptions to match the new README positioning once the repo description settles |

### B2. Custom-steps amendment: open points, stale Deferred entries, wording

- Bundle id: `cs-spec-amendment`
- Owner: custom steps (`specs/custom-steps/`)
- Open fragments: 20
- Smallest change: One custom-steps amendment pinning preamble layout, resume and re-fire ordering,
  pool and full-suite record fields, reserved-control refusal at resolve time, halted-arm scenarios,
  resolved-location wording, and closing stale Deferred entries and check:echo-safety names.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-24-check-mode-attended-synopsis-d1fce56b` | Resolver synopsis allows --attended with --check; operator ruled --check takes --unattended only | Align the tasks.md synopsis and the REQ-C1.4 test entry |
| `2026-09-24-convergence-continue-pr-stop-588f099a` | Undecided whether no-PR-over-broken-branch survives continue posture for halted or failed steps | Decide the two arms in the next custom-steps amendment |
| `2026-09-24-custom-steps-doc-open-points-60f1e9b9` | custom-steps.md leaves many record, exit and fixture questions to later tasks or amendment | Resolve each listed point in its owning task or the next amendment |
| `2026-09-24-preamble-slash-invocation-3a3a9593` | Preamble placement for headless and in-session skill steps is unpinned; headless prompt may not parse as a skill call | Pin preamble layout for headless and in-session skill steps in doctrine/custom-steps.md |
| `2026-09-24-step-script-usage-headers-8cc8c963` | custom-steps doctrine delegates details to script usage headers no task deliverable names | Name the resolve-steps.sh and step-record.sh usage headers and what they pin in the task deliverables |
| `2026-09-24-step-subprocess-guard-gap-9a4dd2c8` | Isolated command steps run unseen by hooks, so human gates bind them by declaration only | Have resolve-steps.sh refuse command lines naming human gates at the guarded points |
| `2026-09-24-step-tables-test-gaps-35e89205` | No test-spec scenario covers the halted convergence arms or post-pr table re-emission for non-pushing steps | Add the halted-arm and non-pushing post-pr scenarios to custom-steps test-spec |
| `2026-09-24-stopped-waiting-concurrent-edits-ec41922e` | An abandoned timed-out step session can keep editing the worktree under on-failure continue | Record the concurrent-edit risk in the next custom-steps amendment and decide a mitigation |
| `2026-09-26-session-line-runs-location-b947acf7` | Spec text still says the declared target runs, while doctrine now runs the resolved absolute location | Amend the listed REQs, decisions, test-spec and tasks to name the resolved location |
| `2026-10-06-echo-safety-task-renamed-ed7ccf68` | custom-steps tasks and human-gates test-spec still name check:echo-safety | Rename to check:echo-discipline at each bundle next delta walk |
| `2026-10-06-flip-evidence-hook-gate-7d1c91ee` | Deferred flip-evidence hook may be un-gated now that ready-flip.sh exists | Evaluate the gate at the next /drain and promote or keep the deferral |
| `2026-10-07-pool-holder-worktree-in-park-95cabcd5` | Full-suite park entry names pool holders by worktree, with no committed form for a sibling worktree | Render a holder's worktree by name in the park entry and state it in the rule doc |
| `2026-10-07-refire-reuse-ordering-open-points-931bad4e` | Three reuse/re-fire ordering details left open in REQ-I1.1, I1.8, I1.9 | Record in the custom-steps spec the orderings Task 14 implemented for each open point |
| `2026-10-07-resume-continuation-open-points-59356c25` | Several resume details (chained skip records, prefix matching, unknown run id) left open | Record in the custom-steps spec the resume choices Task 14 implemented |
| `2026-10-07-steps-upgrade-before-config-undocumented-745dac47` | Upgrade-plugin-before-config rule is called documented but no doc states it | Add one sentence to docs/overlays.md section 8 stating the upgrade-first rule |
| `2026-10-10-custom-steps-flight-deferral-addressed-080b28d6` | tower-front-door Tasks 14-18 address custom-steps Deferred flight-steps entry; close it | Retire the Command and prompt steps on a flight Deferred entry in custom-steps tasks.md |
| `2026-10-17-custom-steps-stale-deferred-e2420dea` | custom-steps Deferred still lists dropping review_sequence, already done in #541 | Retire the review_sequence Deferred entry in custom-steps tasks.md |
| `2026-10-18-custom-steps-test-spec-transitional-0f23ebf1` | custom-steps test-spec REQ-F1.2 still expects the removed review_sequence line | Kickoff delta rewriting test-spec REQ-F1.2 for the post-transition config |
| `2026-10-18-full-suite-unpooled-cause-unrecorded-63fdc8ff` | full-suite record has no field for the unpooled cause; failed take writes no record | Add a warning field to step-record write --full-suite and record failed takes |
| `2026-10-18-refire-rows-first-run-gap-cf01e13e` | Re-fire lists from the chain's first run miss runs interrupted before the list resolved | Take re-fire lists from the earliest chain run that resolved them |

### B3. Move remaining private grammar copies onto spec-parse

- Bundle id: `fg-spec-parse-lib`
- Owner: format grammar and parser unification (`specs/format-grammar/`)
- Open fragments: 16
- Smallest change: Re-point the remaining private task, header, status and anchor-entry parsers onto
  spec-parse, add fence-aware rewriter and verbatim-emit helpers, fail closed on NUL screens, and
  fix the Task 2 consumer list and REQ-E1.3 clause.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-22-restructure-tasks-grammar-copies-319e3472` | migrate-format-version restructure_tasks keeps private grammar copies | Re-point restructure_tasks onto the grammar lib via a Task 8 scope extension |
| `2026-07-24-spec-graph-no-version-parse-40249bf9` | format-grammar Task 2 lists spec-graph.sh as a version-parse consumer; it has none | Expression-only amendment dropping spec-graph.sh from the consumer list |
| `2026-07-24-status-parse-stragglers-6d0f2cd0` | Two Status readers keep private parses outside the REQ-B1.3 set | Re-point both onto spec_parse_header_value or state the exemption |
| `2026-07-26-format-grammar-e13-preempted-a0bfb440` | REQ-E1.3 changelog/re-anchor clause conflicts with convention for Deferred gate edits | Amend REQ-E1.3 and test-spec to drop the changelog/re-anchor clause |
| `2026-07-26-orchestrate-select-nul-screen-fail-open-fbc28fbc` | orchestrate-select inline NUL screen fails open on spawn failure | Mirror the lib's checked-assignment NUL screen inline or expose it publicly |
| `2026-08-24-check-ledger-fence-blind-509a6760` | check-ledger.sh is not fence-aware, so a fenced v1 example fails it as a duplicate task. | Prepend spec_parse_awk_fence to check-ledger.sh awk passes and add a fenced fixture. |
| `2026-08-24-header-block-fence-interaction-46449c71` | A fence above header lines truncates the header block; doctrine never says which rule wins. | Add one sentence in spec-format Header-block extent naming the fence-truncates-block outcome. |
| `2026-08-25-anchor-guard-sweep-overlap-b254d263` | Three brief anchor-entry parsers exist; the shared half should live in spec-parse. | Point anchor-sweep.sh at spec_parse_latest_anchor_entry, retiring its private latest_anchor_entry. |
| `2026-08-25-changelog-scan-fence-blind-5f6d0739` | check-anchor-freshness changelog scan is not fence-aware, so fenced changelog bullets satisfy pairing. | Route changelog_entries through the shared fence lexer. |
| `2026-08-25-line80-reader-stragglers-b492ac85` | Seven scripts still carry private task-heading or dependency grammar copies. | Re-point the straggler readers onto spec-parse.sh and drop their corpus-sweep exemptions. |
| `2026-08-25-spec-model-header-straggler-e306034b` | spec-model.sh reads Status with an unscoped private probe that can match body prose. | Re-point spec-model.sh first_header onto spec_parse_header_value. |
| `2026-08-26-inception-last-reviewed-key-e57b5a39` | Header-key grammar admits no space, so Last reviewed needs a local reader. | Widen the spec-parse header-key grammar to allow internal spaces. |
| `2026-09-12-execution-validity-marks-unparsed-fd49438a` | No script parses execution-validity marks on a brief entry; writer-class condition is prose only | Add a writer-class check to check-anchor-freshness.sh |
| `2026-10-08-spec-parse-rewriter-form-71a53be3` | spec-parse.sh documents fence lexer only for parsers; rewriters have no sanctioned form | Document halt-note.sh's storage-rule rewriter pattern in the spec-parse.sh header |
| `2026-10-18-spec-parse-fenced-slice-96b681b4` | No sanctioned helper emits a task block verbatim with fenced lines | Add a spec-parse.sh function that emits one task block whole |
| `2026-10-19-function-scoped-fence-exemptions-5a654cca` | Corpus guard fence exemptions are per file, so exempt files escape the sweep wholesale | Scope FENCE_EXEMPT to named functions with per-function stale checks |

### B4. Load-sensitive test assertions and races

- Bundle id: `tt-load-sensitive-tests`
- Owner: test throughput (`specs/test-throughput/`)
- Open fragments: 16
- Smallest change: Replace wall-clock ceilings with polls or clock seams, add diagnostics to
  load-failing assertions, cap parked-shim waits, and investigate the lost-write and step-record
  races.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-12-spec-graph-parallel-flake-222ec0d0` | test-spec-graph graphviz-layout assertion flakes under parallel check, passes alone | Make the graphviz probe in test-spec-graph.sh load-robust or retried |
| `2026-07-22-local-test-flake-tower-watchdog-784e573a` | tower-watchdog alive-reset assertion flaked once under full-suite load | Make the alive-reset scenario poll instead of assert a timing window |
| `2026-09-06-registration-e8-fixed-sleep-race-885870b4` | Registration e8 sleeps a fixed 0.05s before TERM, failing when the trap is not yet armed. | Poll for the child's lock or a readiness marker before signalling, replacing the fixed sleep. |
| `2026-09-09-throttle-reengage-load-sensitive-2211c931` | Throttle re-engage assertion fails under load and prints nothing about what it observed | Make the re-engage failure print what each attempt observed |
| `2026-10-01-step-record-completion-race-flake-947df862` | test-step-record completion and concurrent-writer cases fail intermittently; possible real race | Investigate step-record claim and link under load and fix the race |
| `2026-10-01-stop-grace-c20-load-sensitive-42271cfc` | fleet-stop c20 grace assertion fails under load and once alone; wall-clock or a real delay floor | Make c20 measure the recorded grace, not wall-clock, or find the stop delay floor |
| `2026-10-02-sweep-temps-hup-race-under-load-19f0a58a` | test-fleet-sweep-temps HUP case failed under the pooled suite, same shape as the lock-lib HUP flake | Investigate the HUP case race and add it to the known-flake list or fix it |
| `2026-10-04-fleet-stop-sj-c20-flaps-under-load-20f62ecc` | fleet-stop-sj c20 and tower-queue lock tests failed under load; a lost write looks like a real race | Investigate the two-writer lock lost write and the hold-loop wait under load |
| `2026-10-04-queue-log-lock-noclock-load-sensitive-20d69dc2` | Clockless queue-log lock wait stretches under load until the outer timeout fires | Measure the clockless path iterations under load and bound it or widen the test timeout |
| `2026-10-05-flaky-crash-sweep-case-ca9655b2` | test-flight-lifecycle section 6 failed once in ten runs; suspect pid reuse or sweep timeout | Investigate if it recurs; harden the dead-pid fixture against pid reuse |
| `2026-10-06-statusline-render-ceiling-load-flake-9da4c4a8` | Statusline render 2s ceiling with whole-second clock fails under parallel load | Measure with a sub-second clock or relax the ceiling for load |
| `2026-10-11-fleet-sweep-temps-signal-hang-581c7096` | test-fleet-sweep-temps hung on a parked shim when the INT leg misfired; no wall-clock cap | Release parked shims on a misfired leg and give the file a wall-clock cap |
| `2026-10-18-queue-store-lock-lost-writer-7d62ca9f` | tower-queue-store-lock two-writer case lost records under load; writers discard stderr | Capture each writer's stderr and exit status in test-tower-queue-store-lock.sh |
| `2026-10-18-venture-z16-flake-5b8f73fd` | test-inception-venture Z16 flaked in CI: gitleaks exited 0 on a key fixture | Investigate the gitleaks screen path in Z16 for version or load sensitivity |
| `2026-10-19-load-flaky-latency-windows-45ef46c3` | Many tests assert wall-clock ceilings that fail under heavy host load; two others need diagnosis | Replace wall-clock ceilings with load-independent signals (counted attempts, injected clock) in the listed tests |
| `2026-10-19-meta-select-19d-host-failure-167fcf09` | test-orchestrate-meta-select case 19d failed on clean main on a loaded host; not investigated | Reproduce 19d under load and fix the echo-discipline leak or the host-sensitive assertion |

### B5. Config and knob read spawn cost

- Bundle id: `ub-config-read-cost`
- Owner: universal binary (portability and spawn cost) (`specs/universal-binary/`)
- Open fragments: 12
- Smallest change: Add a batched multi-key config read with per-process overlay-root memoization and
  adopt it in the multi-knob callers (guards, resolve-steps, tower-queue, mc-program, registry
  lookup, resolve-root).

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-12-config-get-batch-multi-knob-00ffbb2c` | config-get reads one key per spawn; multi-knob guards pay a fork per knob | Add a batched multi-key config-get read and use it in check-instructions.sh |
| `2026-07-16-daemon-gate-resolution-cost-44adcf07` | Daemon gate check costs several spawns; sweeps should resolve once, stats pass --since | Resolve the daemon switch once per sweep and bound audit queries with --since |
| `2026-09-12-config-read-cost-on-hot-paths-7f14ddc3` | Each resolve-config-knob read costs ~0.3s; multi-knob verbs pay seconds and work around it | Add a multi-key read to config-get.sh or a cached merged view |
| `2026-09-15-tower-queue-log-hot-path-cost-2b1327e0` | log resolves four knobs per call and coalesce copies the whole log twice per pass | Memo knobs per fleet home on config mtimes; rename the coalesce temp directly |
| `2026-09-21-fixture-step-knob-cost-e536a772` | Tower-loop fixture step re-resolves the same knobs across settle, next and catchup | Run settle, catchup and next in one process or cache knobs per process |
| `2026-09-24-resolve-steps-spawn-cost-66cad29f` | resolve-steps.sh spawns about ninety processes per call by re-resolving overlay roots per read | Share a once-per-process overlay-root read or a batched multi-key read across config readers |
| `2026-09-26-resolve-catalog-combined-view-d88b29b7` | resolve-steps rebuilds entries from three resolve-catalog channels including a stderr scrape | Add a combined machine-readable resolve-catalog view with fields, layer and drop marker per entry |
| `2026-09-28-policy-knob-read-cost-3712fe34` | One resolve-policy-knob.sh call costs about 0.4s, mostly config-get overlay-root spawns | Use a multi-key config-get read or cached overlay-root resolution in the policy guard |
| `2026-09-28-spec-root-resolve-cost-daf252ea` | resolve-root.sh spec runs a five-script config chain per call | Resolve the spec root once per run and pass it to callers |
| `2026-10-02-resolve-steps-flight-dispatch-cost-dc62fddd` | flight-dispatch.sh and resolve-steps.sh are the slowest scripts under test | Apply the shared overlay-root read or batched-key mode to both |
| `2026-10-25-mc-program-home-read-cost-fe8f2648` | mc-program.sh get home costs 0.57s per call via three config reads | Read the program home in one config pass in mc-program.sh get |
| `2026-10-30-registry-lookup-cost-4f67e12e` | work-repo-registry lookup costs 0.8s per alias, paid per alias each orchestrate run | Add a batched multi-alias lookup that revalidates the registry once per call |

### B6. Instruction budget guard arithmetic and exception edges

- Bundle id: `ih-budget-guard-edges`
- Owner: instruction-budget headroom (`specs/instruction-headroom/`)
- Open fragments: 10
- Smallest change: Validate raise entries and knob values, define floor zero, soften
  dormant-exception staleness, enforce raise reservations, surface the uncapped load, fail CI on
  unlabeled exception edits, and update D-11's grammar.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-17-budget-exemption-diff-guard-56d4b375` | No-silent-breach clauses are review-only; want CI to fail on unlabeled budget/exemption edits | Add a diff-scoped CI check failing on budget knob or exemptions edits without a label |
| `2026-07-19-declared-exception-dormant-stale-c70484d6` | Dormant-but-valid declared exceptions are flagged stale when their warning did not fire | Soften staleness to unflag entries whose surface is floor-breached or forward-declared |
| `2026-07-19-floor-zero-noop-headroom-design-q-3e8a5d60` | A floor knob of 0 silently disables headroom checks for that class | Decide floor=0 semantics and document or reject it in getknob |
| `2026-07-19-knob-value-leading-zero-octal-97dc8742` | Leading-zero knob values are read as octal in headroom arithmetic | Reject or strip leading zeros in check-instructions.sh getknob |
| `2026-07-19-raise-staleness-value-mismatch-705d0d11` | An extra raise\| entry with a mismatched value beside a correct one goes unflagged | Flag raise\| entries whose value differs from the effective value as stale |
| `2026-07-19-raise-value-non-integer-parse-8fdca68f` | Non-integer raise\| values surface as silent raise instead of malformed entry | Validate raise\| value as an integer at parse |
| `2026-09-09-capped-charge-hides-real-load-4fbf9ceb` | Capped charge of spec-format hides 5749 words; guard green on charged figure, real load over threshold | Decide in a headroom amendment how the guard reports uncapped real load |
| `2026-09-09-headroom-grammar-gained-a-margin-cf2be99f` | instruction-headroom design D-11 shows the old declared-exception grammar without the margin field | Amend D-11 to the margin= grammar and ratchet rules, then re-anchor |
| `2026-09-12-budget-raise-layer-split-c1787387` | Raise rationale ships in core config while its knob lives in a repo overlay; adopters read it stale | Scope raise entries to the layer holding the knob, or give rationales an overlay layer |
| `2026-09-21-closure-raise-slack-unreserved-9f70803a` | A closure raise reserves slack nothing enforces; other changes spend it | Let a raise entry name the surface whose reserved margin it protects |

### B7. spec-draft worktree, extend mode and selection fixes

- Bundle id: `sr-spec-draft-skill-fixes`
- Owner: skill rigor (`specs/skill-rigor/`)
- Open fragments: 10
- Smallest change: Add enter-by-path worktree arms, forward-merge stale spec branches, document the
  extend-mode anchor park and Ready derivation, see unmerged Draft branches, bucket large
  selections, and screen vendor names.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-24-skill-drift-8aaa8edf` | Spec-draft has no degradation arm when launched inside an unrelated worktree where EnterWorktree refuses. | Add a spec-draft arm: in a launch-time worktree, print the hand-launch command and stop. |
| `2026-09-09-spec-draft-fold-blind-to-branch-bundles-ab65bbcb` | spec-draft fold-detection cannot see Draft bundles on unmerged spec branches | List planwright/*/spec branches lacking a checkout bundle and read their Goal and Scope |
| `2026-09-24-spec-draft-hygiene-a5c24588` | spec-draft committed vendor and product names the operator wants kept out of artifacts | Run a machine-local product-name screen in spec-draft before its commit |
| `2026-10-01-spec-kickoff-worktree-from-worktree-134aa8ef` | spec-kickoff pre-flight has no fallback when already isolated in another worktree | Name the fallback arm for an already-isolated session in spec-kickoff pre-flight step 5 |
| `2026-10-06-skill-drift-5558be0b` | spec-draft extend on a signed bundle trips the anchor-freshness hook; the park is undocumented | State the anchor re-review park and its v2 form in spec-draft extend mode |
| `2026-10-06-skill-drift-d115ed2f` | Recreated spec branch is stale after squash-merge; extend must forward-merge main first | Tell spec-draft pre-flight to forward-merge origin/main taking main content before editing |
| `2026-10-07-skill-drift-72159735` | spec-draft extend mode names no rule for a stored-Ready bundle deriving Ready | State the stored-Ready reopen write in spec-draft extend mode and spec-format |
| `2026-10-18-supersede-pointer-done-bundle-anchor-f00cb97c` | A supersede pointer into a v2 Done bundle cannot land without a reopen | Sanctioned v2 park or frozen-record carve-out for supersede pointers in Done bundles |
| `2026-10-22-skill-drift-8af6765c` | spec-draft says present mined observations as one selector, which cannot carry a large selection | Teach spec-draft to bucket large selections by theme with the full list in a file |
| `2026-11-05-skill-drift-66c6d22e` | spec-draft extend says Active status stays untouched, but the hook forces reopening Ready to Draft | Reconcile spec-draft extend-mode text with check-anchor-freshness behaviour |

### B8. check-instructions measurement blind spots

- Bundle id: `ih-check-instructions-audit`
- Owner: instruction-budget headroom (`specs/instruction-headroom/`)
- Open fragments: 9
- Smallest change: Add informational columns for non-doctrine reads, frontmatter, directive density
  and restatement, fix the section gate side, generate --help from the header, and position /doctor
  in guard-catalog.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-27-ctxeng-constraint-density-79a5adbc` | check-instructions measures volume only; add informational directive-density column | Add an informational directive-density column to check-instructions --audit |
| `2026-07-27-ctxeng-doctor-crosscheck-2fef2d70` | guard-catalog does not position claude /doctor against check-instructions | Add a guard-catalog sentence relating /doctor to check-instructions; run /doctor once |
| `2026-07-27-ctxeng-restatement-detector-ff8f7659` | No measure of skills restating the doctrine they cite | Add an advisory n-gram restatement detector to check-instructions --audit |
| `2026-07-27-ctxeng-section-scoped-gate-97e811db` | Section-scoped resolver gate names the wrong side; run-start is the pressure | Widen the prompt-hygiene deferral gate to the run-start case and re-rate it |
| `2026-07-27-ctxeng-skill-description-surface-34cae1db` | Skill frontmatter descriptions are an unbudgeted always-on surface | Add a warn-only catalog aggregate budget and a description authoring rule |
| `2026-07-27-ctxeng-unmeasured-read-surface-06c9b767` | Closure budget ignores non-doctrine runtime reads like docs/fleet.md | Add a manifest class for non-doctrine reads with per-surface dispositions |
| `2026-07-29-orchestrate-closure-floor-binds-4bd26e05` | Floor-breach is warn-only; capped spec-format charge shifts squeeze to small docs | Decide whether floor-breach blocks and revisit the spec-format capped charge |
| `2026-08-18-instruction-headroom-zero-slack-fb7cd43e` | Surfaces with single-digit slack force exceptions for any conforming addition | Flag sub-100-word slack surfaces as a named signal in --audit |
| `2026-10-19-help-range-drift-f44855a0` | check-instructions.sh prints --help from a pinned sed line range that drifts on header edits | Switch check-instructions.sh --help to the self-terminating comment-header form its siblings use |

### B9. Headroom relief for skills at their floors

- Bundle id: `ih-skill-relief`
- Owner: instruction-budget headroom (`specs/instruction-headroom/`)
- Open fragments: 9
- Smallest change: Relocate sections of execute-task, spec-kickoff, tower and builder into doctrine
  or re-derive their thresholds with recorded rationale, and split the coordination-floor doc.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-25-execute-task-headroom-fd0d5252` | execute-task SKILL.md sits in the below-target band with no headroom for the next addition. | Schedule the execute-task diet or a recorded budget re-derivation. |
| `2026-08-25-floor-doc-headroom-fc5bc12e` | fleet-coordination-floor.md is over the doctrine warn threshold and still growing. | Split the floor doc or raise the doctrine warn knob with a recorded rationale. |
| `2026-08-26-closure-headroom-operator-dialogue-eb4d0437` | Reachable-closure headroom is nearly gone; each addition re-breaches unless budgets change. | Decide closure relief: raise the closure error knob with rationale or schedule a diet task. |
| `2026-09-03-instruction-headroom-spec-kickoff-0fb9193a` | spec-kickoff SKILL.md sits on its per-file floor with zero slack. | Relocate a section to doctrine or raise the per-file threshold with rationale. |
| `2026-09-03-kickoff-headroom-exhausted-a3abf3ba` | Trimming no longer works on spec-kickoff; relocation to doctrine is the remaining lever. | Same relief decision; record relocation as the ladder's next rung. |
| `2026-09-05-orchestrate-skill-headroom-14d6ef9f` | orchestrate and execute-task SKILL.md sit at their floors; every addition needs an unrelated trim. | Raise their per-file threshold or lift a section into doctrine. |
| `2026-09-21-prose-lane-budget-wall-7c02f52b` | Three diets fell short funding categorization law on ratchet-pinned run-start aggregates | Choose headroom relief or a point-of-use split of finding-categorization.md |
| `2026-09-24-guard-catalog-start-load-b3d6d8f7` | Every new guard-catalog entry costs builder run-start budget already at its granted margin | Move guard-catalog off the builder run-start manifest to point-of-use, or fund headroom for catalog growth |
| `2026-10-26-tower-start-load-headroom-d2d09c79` | Tower start-load margin fell to about 620 words, below the 1000 restoration target | Trim or relieve the tower skill's run-start docs to restore the margin |

### B10. Release scripts follow-ups and stale version derivation

- Bundle id: `rh-followups`
- Owner: release hardening (`specs/release-hardening/`)
- Open fragments: 9
- Smallest change: Derive the release version from fetched origin/main, fail closed on config-get
  exit 4, anchor the test regex, test release-arm retry branches, settle changelog and
  trust-material rules, and document mise aliases.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-19-release-mise-alias-docs-876b6b55` | getting-started documents raw release scripts, not the mise release aliases | Cross-reference mise run release and release-arm in docs/getting-started.md |
| `2026-07-19-release-pending-version-file-toctou-10e670d2` | version_file read reopens by path, a TOCTOU accepted as limitation | None unless the threat model grows; keep as recorded limitation |
| `2026-07-19-release-publish-config-swallow-parity-017ad88e` | rl_resolve_version_file still collapses config-get exit 4 into the default path | Fail closed on config-get exit 4 in release-lib.sh rl_resolve_version_file |
| `2026-07-19-release-publish-stale-local-main-04b578da` | release-publish derives version from stale local main and refuses on idempotency | Derive the version from fetched origin/main or ff local main as a pre-step |
| `2026-07-19-release-test-run-guard-anchor-749d937c` | test-release-mise-task release run-extractor regex unanchored unlike its sibling | Anchor the [tasks.release] run= awk pattern in tests/test-release-mise-task.sh |
| `2026-07-19-resume-signer-trust-cross-machine-a9f6ce22` | Cross-machine resume refuses valid signed tags lacking local trust material | Narrow the cross-machine resume claim or downgrade auto to warn without trust material |
| `2026-07-19-rl-ci-state-arm-firetime-tests-d2ffdc78` | release-arm fire-loop too-many and query-error retry branches are untested | Add fixture-driven fire-loop tests for release-arm.sh verdict branches |
| `2026-08-26-rh-entry-owner-decision-82311952` | Owner decision: a changelog entry means a bullet; released bullets under unreleased heading fail. | Implement Task 10 with the bullet reading and clarify REQ-H1.2 wording at the next delta. |
| `2026-09-02-release-fetch-redundant-under-depth0-52453de0` | The explicit tag fetch may be redundant under fetch-depth 0. | Verify against the pinned checkout, then use fetch-depth 1 plus fetch-tags in both workflows. |

### B11. Venture secret screen and hook coverage

- Bundle id: `in-venture-screening`
- Owner: inception (`specs/inception/`)
- Open fragments: 8
- Smallest change: Widen venture screen patterns and diff filters, close push evasions (replace
  objects, tags, submodules, insteadOf), run venture-task check in pre-commit, lint powers per
  trigger, fix guard wording, and chase the Z16 leak.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-28-secret-screen-builtin-coverage-a8cd8bdb` | inception-secret-screen.sh built-in patterns miss fine-grained GitHub tokens, JWTs and credentialed URLs | Add the missing credential shapes to the built-in pattern set with tests |
| `2026-10-12-card-lint-trigger-power-check-45840ae6` | card-lint checks powers against one allowlist, not per trigger | Decide allowed powers per trigger in discipline-cards doctrine, then check them in card-lint |
| `2026-10-12-inception-staged-screen-renames-d2580ac5` | Venture secret screen uses --diff-filter=ACM, skipping renamed-and-edited files | Use --diff-filter=ACMR in inception-secret-screen.sh |
| `2026-10-13-inception-push-check-hostile-config-727458d1` | Venture push ignores insteadOf rewrites, title shell-quoting and raw gitleaks output | Compare push URLs with get-url --push, pass title via file, sanitize gitleaks output |
| `2026-10-13-inception-push-screen-residual-gaps-3c6bfdf9` | Replace objects, followTags, submodules, gitleaks allow files and HEAD moves evade the screen | Push one screened SHA with GIT_NO_REPLACE_OBJECTS, --no-follow-tags, no submodule recursion |
| `2026-10-18-venture-hook-task-check-41beebf8` | Venture pre-commit hook skips venture-task.sh check | Add a warn-level staged venture-task.sh check to inception-scaffold.sh's hook |
| `2026-10-25-venture-guard-merge-base-wording-485e2037` | venture-guard text says merge base but it compares base.sha or event.before | Reword inception-scaffold.sh comment and hygiene-wiring.md to name the actual baseline |
| `2026-10-31-secret-screen-archive-names-c12cc37a` | Archive-name copy covers file args only; directory args and --staged arm unverified | Apply the fixed-name copy to files under directory arguments and verify the staged arm |

### B12. Mechanical spec-authoring checks for drafts

- Bundle id: `newspec-spec-authoring-checks`
- Owner: a new spec: spec-authoring checks (`new-spec`)
- Open fragments: 8
- Smallest change: New spec adding validator checks for REQ and D-ID task coverage, test targets,
  cross-task artifact dependencies and false cites-claims, plus spec-draft heading and API-research
  steps.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-17-draft-test-spec-guard-blindness-d95cb0da` | spec-draft claimed no skill-prose harness exists despite shipped grep guard suites | Tell spec-draft test-spec elicitation to consult existing tests/ guard suites |
| `2026-07-18-spec-draft-testspec-h2-groups-8fb8f199` | spec-draft emitted test-spec REQ entries without ## REQ-group headings, tripping MD001 | Have spec-draft group test-spec entries under ## REQ-&lt;group&gt; headings |
| `2026-07-19-spec-validate-req-task-coverage-f6601f8f` | spec-validate does not check every REQ and D-ID is cited by a task | Add a REQ/D-ID-to-task coverage check, warn at Draft, error at Ready |
| `2026-07-19-task-donewhen-sibling-artifact-09bd365d` | Done-when referencing a sibling task's artifact without a dependency edge | Have spec-draft add the dependency or make the check existence-conditional |
| `2026-07-22-external-api-semantics-upfront-research-01b3a1eb` | External-API-dependent specs need an upfront API-semantics research step in spec-draft | Add an API-semantics probe step to spec-draft for external-API mechanisms |
| `2026-07-24-spec-crossref-claims-unverified-59087817` | False intra-bundle cites-claims pass every guard | Check every ID in Citations fields exists and named cross-references are present |
| `2026-07-27-ctxeng-testspec-executable-3a13f926` | [test] test-spec entries never checked to name an existing target | Let [test] entries carry a resolvable path and have spec-validate check it |
| `2026-07-27-ctxeng-validator-normative-home-5a0e8427` | spec-format and spec-validate header restate the invariant list twice | Make the validator the single source; doc keeps names and unchecked-gap notes |

### B13. Shared portable helpers for platform fallbacks

- Bundle id: `ub-portability-helpers`
- Owner: universal binary (portability and spawn cost) (`specs/universal-binary/`)
- Open fragments: 8
- Smallest change: Consolidate pid liveness, procfs, timeout, duration, UTC date and mktemp
  fallbacks into tested shared helpers with a ps shim test, and restore exec bits after marketplace
  copies.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-03-liveness-primitive-duplicated-8410794f` | Bare kill -0 copies misread EPERM-live pids as dead beside the positive-evidence seam. | Route fleet-liveness.sh and fleet-dispatch-headless.sh liveness through the pid_live/death-evidence seam. |
| `2026-09-08-marketplace-copy-strips-exec-bit-a826597a` | Marketplace copy may strip exec bits, silently breaking hooks invoked by path | Reproduce on a fresh install; if real, invoke hook scripts through sh explicitly |
| `2026-10-07-duration-seconds-converters-4b066908` | Four private awk copies convert knob durations to seconds with differing rounding | Add a seconds output mode to resolve-config-knob.sh duration type and drop the four copies |
| `2026-10-11-utc-iso-date-r-reads-a-file-7107ff66` | utc_iso tries date -r first; GNU reads a file's mtime when an epoch-named file exists | Try date -u -d @epoch first in all three utc_iso copies |
| `2026-10-19-busybox-procfs-snapshot-cost-2081ef7f` | busybox fleet-stop snapshot forks tr per process, about 1.4s per snapshot | Read procfs cmdline only for rows busybox ps truncated |
| `2026-10-19-portability-fallback-duplication-d18ca2ab` | Platform fallbacks (pid liveness, procfs reads, timeout pair) are copied across many scripts | Fold the copies into one sourced liveness/bounded-run helper under universal-binary Task 13 |
| `2026-10-19-procfs-fallbacks-untested-on-glibc-87b4dbcd` | busybox procfs fallbacks run only on Alpine; a ps shim test would cover them on any host | Add a busybox-shaped ps shim test exercising the procfs fallbacks on every host |
| `2026-10-25-smoke-allowlist-mktemp-44ab5e8b` | mktemp is not POSIX, yet every script needs it; smoke allowlist added it outside the floor | Re-sign-off universal-binary floor naming mktemp explicitly in REQ-B1.1 |

### B14. Dispatch exclusion across worktrees and hosts

- Bundle id: `coc-cross-worktree-exclusion`
- Owner: concurrent orchestrator coordination (`specs/concurrent-orchestrator-coordination/`)
- Open fragments: 7
- Smallest change: Wire fleet-fence claims into /orchestrate dispatch with a renewing sweep, take
  the parallel cap inside the lock, probe pushed bundle branches, and surface meta-select per-spec
  stderr with a distinct all-held exit.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-15-fleet-tier-degradation-visibility-09e7b4f0` | meta-select hides per-spec selector stderr; all-held fleet exit collides with nothing-ready | Forward selector warnings per spec and give an all-held fleet its own exit code |
| `2026-08-26-orchestrate-fence-wiring-unbudgeted-a2962703` | fleet-fence.sh ships but /orchestrate never claims a fence at dispatch for lack of words. | Wire fence claim at dispatch and the selection guard into orchestrate, funded by a trim. |
| `2026-08-27-fence-sweep-cadence-window-one-shot-77d57078` | The fence sweep's cadence window is one-shot, not renewing as REQ-C1.3 implies. | Amend REQ-C1.3 to the bound delivered, or add a private renewing cadence stamp. |
| `2026-10-04-cross-machine-dispatch-window-2e314614` | Two hosts can run the same task until the worker pushes; locks and markers are host-local | Claim the task on origin (fence ref) at dispatch time |
| `2026-10-04-orchestrate-lock-checkout-local-7424d6d2` | Per-spec lock is checkout-local, so two worktrees can both select the same unit | Move the per-spec lock beside the shared-git-dir marker home |
| `2026-10-04-remote-bundle-branch-blind-44a4309b` | orchestrate-state probes only single-task remote branches, missing pushed cohesion bundle branches | Probe origin bundle branches task-a-b and credit their member tasks |
| `2026-11-05-meta-step-parallel-cap-ed918287` | meta-step checks max_parallel_units outside the lock, so racing towers exceed the cap | Count In-progress units inside the per-spec lock in orchestrate-meta-step.sh |

### B15. Purged-identifier and shell-text guard cost

- Bundle id: `gc-check-cost`
- Owner: guard coverage (`specs/guard-coverage/`)
- Open fragments: 7
- Smallest change: Index purged seeds by first word with cross-line phrase matching, reject
  low-entropy seeds, fix the missing-seed remedy text, and share one tokenizer pass across
  shell-text guards.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-24-purged-guard-cost-37e8db32` | Purged-identifier tree scan costs about 15s, heaviest check member; a first-word hash set would cut it. | Add a committed first-word hash set so multi-word candidates expand only at seedable positions. |
| `2026-08-28-purged-guard-low-entropy-false-positive-bb99645c` | Low-entropy seed terms flood the purged-identifier guard with false positives, bricking check. | Refuse or warn at seed time on a candidate already matching tracked content, naming the count. |
| `2026-09-01-purged-screen-remedy-4e9669df` | Missing-seed failure points at re-seeding when the real remedy is bringing the branch current. | Make the commit-msg setup-failure remedy detect branch-behind and say bring the branch current. |
| `2026-09-06-awk-guard-cost-13b74212` | check:echo-safety awk tokenizer is now the costliest non-test guard. | Record the cost; share one tokenizer pass before adding a second tokenizing guard. |
| `2026-10-06-echo-discipline-guard-cost-156e3730` | check:echo-discipline costs 1.7x the old check | Share one tokenizer pass across shell-text guards if check time is needed back |
| `2026-10-18-purge-scan-window-cost-72304961` | Multi-word seeds raised purge scan from 37s to 111s | Length-bucketed seed candidates in the purge scan if it becomes the slowest guard |
| `2026-10-18-purge-seed-misses-wrapped-phrases-3e0b1d64` | Purge scan builds candidates per line, missing phrases wrapped across lines | Build multi-word candidates across line breaks within a paragraph |

### B16. Sign-off trailers, checklist and legacy ids

- Bundle id: `hg-sign-off-record`
- Owner: human gates (policy guard and sign-off) (`specs/human-gates/`)
- Open fragments: 7
- Smallest change: One sign-off generator shared by checklist and step-record, drop the unrecorded
  Route reason, bound trailer screens, dedupe re-listed trailers, and give polish a ledger home for
  untrailered edits.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-24-trailer-length-bound-a118ede3` | orchestrate-state.sh screens Planwright-Task spec segment without the 64-char bound the trailer helper enforces | Add the 64-character bound to orchestrate-state.sh trailer spec-segment screen |
| `2026-09-28-sign-off-route-reason-writer-29b27caf` | The checklist renders a Route reason no committer records, so every entry reads not recorded | Have self-review stamp a Route reason line in the sign-off commit body |
| `2026-10-01-sign-off-checklist-two-generators-2dc85dbb` | sign-off-checklist.sh and step-record.sh regenerate render legacy entries differently, duplicating logic | Render the PR section from sign-off-checklist.sh list output and drop the step-record copy |
| `2026-10-07-sign-off-id-legacy-collision-1fa24fe0` | Convergence step used legacy legacy sign-off subject marker suffix while PR body numbered PS ids, colliding | Make convergence steps stamp via planwright-commit-trailers.sh --sign-off, or flag new legacy subjects |
| `2026-10-08-sign-off-checklist-squash-ancestry-89426779` | Branch cut from a squash-merged task branch re-lists already-approved sign-off trailers | sign-off-checklist.sh skips trailers whose patch is already on the base |
| `2026-10-11-checklist-omits-legacy-marker-b1f24036` | step-record regenerate --checklist-only omitted a legacy-marker commit | Include legacy-marker commits as PS-legacy items in the --checklist-only render |
| `2026-10-18-polish-untrailered-signoff-729ee951` | Polish has no ledger home for a sign-off edit landed untrailered in a fix batch | Give polish a sanctioned record for a late sign-off trailer without split and re-land |

### B17. Tests inherit worker environment and shared state

- Bundle id: `tt-test-env-isolation`
- Owner: test throughput (`specs/test-throughput/`)
- Open fragments: 7
- Smallest change: Have the runner scrub worker identity, pool and tmux variables, pin umask, use
  unique smoke handles, harden the mktemp-cd form, and complete fixture knobs.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-15-tests-inherit-tower-identity-env-17046253` | Workers export PLANWRIGHT_TOWER_ID and tests assume it unset; each test neutralises it alone | Neutralise tower identity env suite-wide in scripts/run-tests.sh |
| `2026-09-28-test-mktemp-cwd-cd5efa67` | One-step mktemp plus cd scratch form can make the repo root the scratch dir under bash 3.2 | Sweep tests to check mktemp before the cd |
| `2026-10-03-test-umask-sensitivity-27562cd7` | Under umask 0002 about ten fleet and tower tests fail as fixtures inherit the umask | Pin umask 022 in the affected fixtures or the test runner |
| `2026-10-06-smoke-live-stale-journal-71a6d363` | smoke --live reuses the fixed smoke-probe handle, so an old journal row fails every later run | Use a per-run handle in smoke-worker-dispatch.sh --live |
| `2026-10-08-tmux-test-isolation-7411f2a4` | A test using TMUX_TMPDIR alone killed the real tmux server; tests need -S or env -u TMUX | Add a lint over tests/ refusing tmux starts without -S or env -u TMUX plus private TMUX_TMPDIR |
| `2026-10-25-step-run-test-inherits-pool-hold-5c7abaa4` | test-step-run fails when PLANWRIGHT_STEP_POOL_HOLD is inherited from full-suite-run | Unset PLANWRIGHT_STEP_POOL_HOLD in test-step-run.sh with the other inherited step context |
| `2026-11-01-presence-test-lacks-batch-max-32950e98` | test-tower-queue-presence fixture lacks tower_batch_max, printing unset-knob warnings | Add tower_batch_max to the presence test's core-defaults fixture |

### B18. Command guard tokenizer fidelity and cost

- Bundle id: `wpe-guard-tokenizer-fidelity`
- Owner: the worker-permission-ergonomics amendment seed
  (`specs/_pending/worker-permission-ergonomics-amendment.md`)
- Open fragments: 7
- Smallest change: Model double-quote backslashes and zsh globs in one tokenizer, check the compgen
  substitution, cap while and until loops, count only keyword do/done, and remove quadratic walks
  and per-call forks.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-02-guard-hook-spawn-cost-ee336bb5` | Permission guard hooks fork tens of thousands of processes per test file, paid per tool call too | Reduce per-call spawn count in worker-command-guard, policy-guard and ready-guard |
| `2026-10-05-guard-dq-backslash-dropped-addd719a` | Command guards drop every backslash inside double quotes unlike bash, so analysed words differ | Keep the backslash except before the bash-special characters in the guard tokenizers |
| `2026-10-07-guard-env-names-fork-failure-4298486c` | HOOK_ENV_NAMES compgen substitution unchecked; a fork failure empties it and assign_name_ok fails open | Check the compgen substitution status in both guards and refuse every name when it fails |
| `2026-10-07-guard-tokenizer-zsh-model-8d46a461` | Shared tokenizer models bash but macOS Bash tool runs zsh; numeric globs and quoting differ, two copies | Model zsh numeric globs and double-quote backslashes in one shared tokenizer for both guards |
| `2026-10-07-guard-while-loop-cap-daa706a4` | Guards cap for-loop passes but not while/until loops; future writer shapes need the same check | Add a while/until-open check shared by writer shapes in both guards |
| `2026-10-19-guard-scan-budget-load-margin-bb4cc293` | Worker guard scan-budget rows flake on Alpine; tokenize walks chars quadratically | Split the command into a char array once in tokenize |
| `2026-10-19-loop-fits-do-argument-d83f8220` | loop_fits counts unquoted do/done words, so an argument spelled do over-charges a loop (fails closed) | Make loop_fits count do/done only in command-word position |

### B19. Anchor freshness false halts and re-anchor sweep gaps

- Bundle id: `ai-reanchor-sweep`
- Owner: anchor integrity (freshness gate and anchors) (`specs/anchor-integrity/`)
- Open fragments: 6
- Smallest change: Teach the freshness gate to self-re-anchor after out-of-order merges, an
  anchor-computer change or a pre-change anchor, route kickoff accordingly, and give the re-anchor
  sweep a repair step for bundles signed off while it is open.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-17-anchor-parallel-merge-drift-02efe968` | Out-of-order task-PR merges stale the file-last anchor entry and halt the next dispatch | Let the gate accept any execution-valid anchor entry or auto-append a current-main anchor on merge |
| `2026-07-18-spec-correction-needs-reanchor-bb414857` | Spec-correction merged without re-anchor strands the next dispatch at the freshness gate | Trigger a re-anchor step for anchored spec corrections, or classify expression-only edits |
| `2026-08-24-anchor-drift-done-bundles-1ea469f5` | Ten Done bundles' anchors no longer recompute; they now sit parked awaiting re-review classification. | Decide by rule: exempt Done bundles from recompute, or classify and re-anchor the parked ones. |
| `2026-08-24-freshness-gate-hash-scope-blind-spot-98f27101` | Freshness gate false-halts when the branch changed the anchor computer, prescribing a needless re-walk. | Have the gate report a computer-version divergence distinctly from a content divergence. |
| `2026-08-24-sweep-race-late-bundle-fa2ad31a` | A re-anchor sweep PR misses bundles signed off while it is open; CI reds with no repair step named. | Name the top-up pass (merge base, sweep only new bundles, re-prove) in the sweep procedure. |
| `2026-08-25-kickoff-prechange-anchor-afaf925b` | spec-kickoff routes every freshness mismatch to a delta re-walk, even a pre-change anchor. | Add the pre-change-anchor self-re-anchor case to spec-kickoff step 2, funded by a trim. |

### B20. Reconcile liveness and registry trust

- Bundle id: `flc-reconcile`
- Owner: fleet lifecycle closure (`specs/fleet-lifecycle-closure/`)
- Open fragments: 6
- Smallest change: Make reconcile and mc-reclaim ask the rung and launcher registry for liveness
  (unknown reads live), share one registry-reconcile helper, test that a forged record kills
  nothing, and check rung rows in the coordination floor.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-25-rung-coverage-check-34ae9280` | Nothing checks every backend rung has a row in the fleet coordination floor cross table. | Add a guard comparing rung columns of the two doctrine tables. |
| `2026-09-02-registry-record-is-an-untrusted-hint-43d7f787` | Registry records are unauthenticated hints; no test proves a forged one kills nothing. | Add an adversarial case: a forged registry record must not be sufficient to kill anything. |
| `2026-10-07-death-handle-verdict-duplication-26c231e3` | Attention and registry reconcile scripts duplicate registry read, latest() and death-handle verdict mapping | Move latest() and death-handle mapping into one sourced helper used by both reconcile scripts |
| `2026-11-05-launcher-worktree-liveness-093b1e8d` | Reconcile and mc-reclaim can remove a live mission-control-launched worktree after 15 minutes | Consult launcher registry rows before reconcile or reclaim removes a worktree |
| `2026-11-05-script-rung-redispatch-liveness-3bf031b9` | Reconcile can remove a running stream-json or headless worker's worktree after its marker ages | Ask the rung for liveness in the reconcile and read unknown as live |
| `2026-11-05-session-status-shell-reads-exited-5610ccff` | A live session with status shell was read as exited; a second worker collided in its worktree | Refuse launches into a worktree whose owning session is live by process evidence |

### B21. Small fleet-state and flight-dispatch defects

- Bundle id: `flight-fleet-script-fixes`
- Owner: a spec-less flight (`flight`)
- Open fragments: 6
- Smallest change: Reject leading-dash fields and unreadable registries in fleet-state, install
  dispatch traps up front, pass the overlay to dispatched workers, remove crash counters on retire,
  and review the unreviewed relaunch arm.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-02-fleet-state-field-leading-dash-58dce446` | fleet-state.sh valid_field accepts a leading-dash value, an option-injection token for consumers. | Add a leading-dash refusal arm to valid_field. |
| `2026-09-28-flight-dispatch-late-signal-traps-ef940689` | flight-dispatch.sh installs INT/TERM/HUP traps only partway through cmd_dispatch | Install the signal traps at the top of cmd_dispatch before convergence resolution |
| `2026-09-29-fleet-registry-read-1a7a5b8f` | fleet-state.sh registry exits 0 when the registry file exists but cannot be read | Exit nonzero when the registry exists but cat fails |
| `2026-10-01-flight-home-disagrees-abe9ffce` | Dispatch declared PR home but the worker resolved file home since its env missed the adopter overlay | Hand the worker the dispatch-resolved home, or make the landing check use the same resolution |
| `2026-10-05-flight-crash-state-leak-e9ed5fd1` | Retiring a flight leaves its liveness crash counter file behind | Remove liveness/crash/tmux-flight-id on flight retire |
| `2026-10-05-flight-relaunch-unreviewed-52c1e6a4` | PR 579 merged a relaunch arm and test added during conflict resolution, never reviewed | Run a dedicated review of the dispatch --relaunch arm and its test |

### B22. Guard test fixtures inherit environment and stale payloads

- Bundle id: `gc-guard-test-fixtures`
- Owner: guard coverage (`specs/guard-coverage/`)
- Open fragments: 6
- Smallest change: Scrub GIT_* and mise trust variables in check and hook fixtures, make step-record
  ignore inherited GIT_DIR, refresh hook payloads, and give fixture roots a doctrine directory.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-15-hook-fixtures-predate-envelope-growth-f8ed63da` | Older hook payload fixtures predate agent_type and other envelope keys from newer CLIs | Re-derive the remaining fixtures and move agent_type into the shared-envelope exclusion |
| `2026-10-03-guard-test-core-root-17c5b8bc` | Guard test fixture core dir lacks doctrine/ so resolve-root skips it and the catalog reads elsewhere | Add a doctrine/ dir to the fixture core or assert the resolved core root |
| `2026-10-05-hook-run-fixtures-inherit-git-env-d34a2f02` | Hook-run test fixtures inherit GIT_DIR and GIT_INDEX_FILE and act on the real repository | Require hook-run suites to clear the git environment, enforced by a guard or check |
| `2026-10-11-mise-trust-bypass-in-guards-741191b4` | check-guard-wiring sets MISE_TRUSTED_CONFIG_PATHS, running untrusted tree code while listing tasks | Drop the trust bypass in check-guard-wiring.sh and trust fixtures in its tests |
| `2026-10-11-pathspec-env-guard-bc6e58ee` | check-script-modes.sh inherits GIT_LITERAL_PATHSPECS, refusing with a misleading message | Clear the GIT_*_PATHSPECS variables in check-script-modes.sh before ls-files |
| `2026-10-12-step-record-preexisting-git-env-4cea925c` | Older step-record.sh calls plain git -C, honouring inherited GIT_DIR and failing open | Route the older step-record.sh git calls through git_wt and check ls-files failures |

### B23. Policy guard shell-semantics bypass classes

- Bundle id: `hg-policy-guard-shell-semantics`
- Owner: human gates (policy guard and sign-off) (`specs/human-gates/`)
- Open fragments: 6
- Smallest change: Add a word-level act screen, resolve cd like bash only when unconditional, treat
  HOME/XDG and .git/config writes like GIT_* variables, refuse env-prefixed policy helpers, and
  match abbreviated git options.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-11-policy-env-override-1406dc79` | Policy-reading helpers honour env overrides a worker command prefix can set | Have helpers locate policy layers themselves or the guard refuse env-prefixed calls |
| `2026-10-26-tower-guard-grep-open-abbrev-edfc0ca9` | tower-command-guard approves git grep --open=prog since it matches only the full option spelling | Match any unambiguous prefix of --open-files-in-pager in tower-command-guard.sh |
| `2026-11-04-tower-raw-fallback-bypass-classes-66e65bab` | Policy guard raw fallback keeps yielding tower bypass classes (wrappers, substitutions, aliases) | Add a word-level screen refusing any git, gh or git-* word followed by an act word |
| `2026-11-06-policy-guard-cd-resolution-191e83d1` | policy-guard resolves cd physically, ignores CDPATH and symlink-mutating segments | Resolve cd like bash, treat bare relative cd as unreadable, refuse git acts after fs-mutating segments |
| `2026-11-06-policy-guard-conditional-cd-adaaf1db` | policy-guard follows a cd even when it runs conditionally | Follow a cd only when unconditional; otherwise mark the directory unreadable |
| `2026-11-06-policy-guard-config-redirection-bbbc0268` | HOME or XDG_CONFIG_HOME, or writes to .git/config, change git config after the guard read it | Treat HOME/XDG_CONFIG_HOME assignments and .git config writes like GIT_* variables in act_gate |

### B24. Observation carry dedupe and branch lifecycle

- Bundle id: `or-obs-carry-correctness`
- Owner: observation recording (`specs/observation-recording/`)
- Open fragments: 6
- Smallest change: Carry fragments from every branch commit, dedupe by UID and content across
  entries and archive, re-dedupe or close stale chore branches, and stop hard-wrapping the PR body.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-28-carry-pr-body-hard-wrapped-2237ec28` | observation-carry.sh hard-wraps the PR body, rendering a narrow column on GitHub | Emit each body paragraph as one line in observation-carry.sh |
| `2026-09-12-squash-merge-strands-tail-commits-3cacc290` | Squash merge strands later branch commits; carry reads only HEAD, so off-HEAD fragments are lost | Have the carry walk every local branch for fragments absent from main |
| `2026-09-13-carry-branch-outlives-its-content-5f9bbb65` | Carry chore branch outlives its content; never re-deduped, closed, or checked against archive/ | Refuse to reuse an empty-delta chore branch and dedupe against archive/ |
| `2026-09-20-carry-dedupe-drops-revisions-silently-c4a0b7e2` | Carry dedupes by path, so a revised fragment is silently not carried | Dedupe on blob identity; carry a changed blob as a new commit |
| `2026-09-24-observation-carry-ignores-archive-4faa7410` | observation-carry dedupes only against main entries/, so archived fragments get re-carried and fail check-obs | Dedupe carried fragments by UID across origin/main entries/ and archive/ |
| `2026-10-31-obs-duplicates-across-branches-9822997b` | Duplicate refusal reads only the local store, so two branches can land the same observation | Add a content-duplicate pass over the merged store to check-obs.sh |

### B25. spec-format text: versioning, exemplar, supersede rules

- Bundle id: `pending-spec-format-v3-text`
- Owner: the spec-format upgrade seed brief (`specs/_pending/spec-format-upgrade.md`)
- Open fragments: 6
- Smallest change: In the spec-format upgrade, relocate versioning, collapse grammar narration to an
  exemplar, settle amend-in-place and self-citation rules, fix invariant-tasks D-13, and stop
  v1-v2-only branching.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-27-ctxeng-specformat-exemplar-d43920a7` | spec-format.md could collapse grammar narration to an exemplar bundle plus validator | Ship a guard-pinned exemplar bundle and collapse the per-file grammar sections |
| `2026-09-09-meta-spec-versioning-charged-to-all-164e9b67` | spec-format's 1712-word versioning section is loaded by every consumer though no skill consults it | Move the versioning section to a maintenance doc no skill loads |
| `2026-09-28-amendment-supersede-vs-in-place-5f275034` | spec-format says post-merge meaning changes supersede, yet precedent amends in place in-flight | State in spec-format when an in-flight post-merge meaning change may amend in place |
| `2026-10-11-doctrine-amendment-citations-b0050848` | No rule says whether an amending spec cites itself in a doctrine Citations line | State the amending-spec citation rule in spec-format and align the citations |
| `2026-10-30-invariant-tasks-d13-upgrade-wording-279d04e7` | invariant-tasks D-13 says a v2 upgrade is only the version bump, contradicting its own Repository rule | Reword D-13 when the spec-format-upgrade seed becomes a spec |
| `2026-10-30-v3-skill-arms-fa79b107` | orchestrate, drain, spec-kickoff and selection-contract still branch v1 vs v2 only | Add format-version 3 arms to orchestrate, drain and spec-kickoff skills and selection-contract candidacy |

### B26. Finding categorization and unit-sizing doctrine

- Bundle id: `re-doctrine-amendment`
- Owner: review effectiveness (`specs/review-effectiveness/`)
- Open fragments: 6
- Smallest change: Amend categorization doctrine for coverage pins, test-only zone fixes and
  security hardening, add unit-sizing guidance, and drop the moot Deferred lens-list entry.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-26-coverage-pin-has-no-bucket-49ad55ea` | A coverage-pin test cannot fail first, so it fits no Agent-resolvable bucket cleanly. | Add a predicate clause admitting coverage pins to Agent-resolvable. |
| `2026-08-26-zone-screen-fix-location-7f0b4274` | Zone screen is ambiguous for a test-only fix to a finding about zone code. | State in gate-wiring that the fix location governs the zone screen. |
| `2026-09-02-hard-pause-zones-vs-hardening-c06b2908` | Unclear whether security-motivated hardening outside listed zones forces a hard pause. | State in finding-categorization that zones are read literally, not by intent. |
| `2026-09-13-shared-run-start-doc-growth-15240f38` | A bundle amending a shared run-start doc can be unlandable; size growth against dependent margins | Add a drafting-time check sizing doctrine growth against every dependent aggregate margin |
| `2026-09-14-big-diff-relocates-defects-a0add2f0` | 59-file unit relocated defects across passes; split primitive introduction from caller migration | Apply REQ-A1.7 large-change flag and the task-sizing lesson in doctrine |
| `2026-10-21-lens-list-mirror-moot-6fb74b0c` | The Deferred lens-list mirror entry is moot since operator instructions resolve doctrine at run time | Close the review-effectiveness Deferred mirror entry at its gate drain as moot |

### B27. Tower-queue and flight-record secret redaction

- Bundle id: `tc-redaction`
- Owner: tower comms (`specs/tower-comms/`)
- Open fragments: 6
- Smallest change: Redact whole key blocks of every header type with case-insensitive assignments
  mirroring the secret screen, handle list-item and continuation shapes, and validate rebuilt roots
  and parks.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-15-private-key-redaction-stops-at-header-79cc3210` | tower-queue redact() replaces only the private-key header, so the key body reaches events.log | Redact through the END line or drop the value; add JWT and bearer shapes |
| `2026-09-16-tower-queue-rebuild-park-recheck-a7a7cc84` | rebuild restores an attention item's root and park from the born line unchecked | Re-run containment on the attention item's park and root at rebuild |
| `2026-10-11-flight-record-list-prefixed-key-c025b6ff` | flight-record redact mishandles private-key blocks pasted as markdown list items | Strip the opening line's list prefix from later lines before matching key block ends |
| `2026-10-11-flight-record-ssh2-continuation-end-74b26a30` | SSH2 header continuation can put END marker on a continuation line, ending the block early | Inside an SSH2 block, never end on a line following a backslash-continued line |
| `2026-10-11-tower-queue-redact-assignment-case-88a344d2` | tower-queue redact assignment rule matches lowercase keywords only | Make the queue mirror's assignment and key rules case-insensitive like the screen |
| `2026-10-11-tower-queue-redact-key-headers-8bfca004` | tower-queue redact matches only the old PEM header, not PGP/SSH2/PuTTY ones | Copy the widened key-header alternation and block span into tower-queue.sh redact |

### B28. Tower-queue spawn and lock cost

- Bundle id: `tc-tower-queue-perf`
- Owner: tower comms (`specs/tower-comms/`)
- Open fragments: 6
- Smallest change: Batch event-log appends under one lock, skip the lock when idle, resolve knobs
  once per verb, and move rebuild forks out of the critical section.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-15-tower-queue-idle-lock-d394ee29` | next takes the exclusive fleet lock on every pass even when idle | Add a lock-free pre-pass that skips the lock when nothing is due |
| `2026-09-15-tower-queue-log-batch-61e551d2` | Every owed event-log line is a fresh process with its own lock cycle; rebuilds starve the hook | Add a batch mode to the log verb: many lines, one lock hold |
| `2026-09-16-tower-queue-log-field-screen-cost-062ee866` | log screens every field with forks (~60ms per line) | Use a fork-free field screen with a cheap pre-filter |
| `2026-09-16-tower-queue-rebuild-in-lock-forks-2ed2c876` | rebuild runs per-item forks under the fleet lock, exceeding the 2s wait at a few hundred rows | Mint ids inside the awk pass or in one batch |
| `2026-09-16-tower-queue-verify-forks-per-pass-980f2be4` | Queue verbs fork ls per path and repeat verification under the lock; unused knobs resolved | One ls over operands, one locked verification, resolve knobs where read |
| `2026-10-02-tower-queue-spawn-cost-dcdd1bca` | tower-queue.sh re-resolves config knobs and overlay roots per verb, dominating its tests | Resolve tower-queue config once per invocation |

### B29. Lock primitive residuals and token discipline

- Bundle id: `ub-lock-primitive`
- Owner: universal binary (portability and spawn cost) (`specs/universal-binary/`)
- Open fragments: 6
- Smallest change: Parse lock and marker fields as decimal, require tokens on unlock across
  consumers, add a fenced ledger write, and measure on-disk lock state in bake-off fixtures.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-14-ledger-append-fencing-51fe1178` | Ledger append re-verifies ownership but cannot close the window; needs a fenced write | Carry the lock token as a fence in each row and reject mismatched rows |
| `2026-10-04-marker-octal-timestamp-5c409b78` | A marker with a leading zero is read as octal and aborts derivation or liveness probing | Reject 0-prefixed marker contents as malformed in orchestrate-state and is_live |
| `2026-10-09-fleet-lock-release-rc-a3d7081f` | tower-queue.sh keeps the fleet-lock token only on unlock exit 2, unlike other consumers | Keep the token for every unlock status but 0 and 1 in tower-queue.sh release_lock |
| `2026-10-09-fleet-lock-tokenless-guard-2ad93ace` | Nothing stops scripts calling token-less fleet-state.sh unlock | Extend check-lock-primitive.sh to flag token-less unlock calls outside the escape hatch |
| `2026-11-02-bakeoff-fixture-post-state-090bc4d1` | Bake-off fixtures compare stdout and exit only, so on-disk lock state is unmeasured | Add an optional expected-tree field to the bake-off fixture format |
| `2026-11-02-lock-lib-mint-field-arith-e9e8af52` | lock-lib reads mint field raw into arithmetic (octal, wrap), readlink lacks --, slug locale-dependent | Pass the mint field through _pw_lock_dec, add -- to readlink, force LC_ALL=C in slug |

### B30. Fleet script spawn cost and fixed polls

- Bundle id: `ub-perf-fleet-scripts`
- Owner: universal binary (portability and spawn cost) (`specs/universal-binary/`)
- Open fragments: 6
- Smallest change: Cut git and ps spawns in resolve-root and lock probes, make streamjson and
  liveness poll intervals configurable, and reduce fleet-script exec counts.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-25-resolve-root-git-process-count-215d69a9` | resolve-root.sh repo --primary spawns seven or eight git processes per call | Collapse the rev-parse queries into one multi-flag call and the config reads into one |
| `2026-09-30-lock-lib-acquire-cost-8e2196a3` | pw_lock_try probe forces an uptime refresh and ps forks, costing the test pool up to 0.6s per file | Add a cheap free-path acquire verb with no forced uptime refresh |
| `2026-10-02-fleet-script-spawn-cost-8880747e` | Fleet and flight scripts each dominate a slow test file by spawn cost | Cut per-call child processes in the named fleet and flight scripts |
| `2026-10-02-macos-exec-cost-multiplier-eba0d568` | macOS exec costs 15ms in fleet sessions via opendirectoryd, serializing execs host-wide | Feed these measurements into the universal-binary macOS bake-off method |
| `2026-10-02-streamjson-fixed-poll-tick-953df56d` | fleet-streamjson.sh waits on fixed unconfigurable poll intervals the suite inherits | Make the supervisor base tick and wait polls configurable or event-driven |
| `2026-10-19-oracle-grace-ladder-fixed-28cc00af` | fleet-liveness oracle TERM-then-KILL grace is two fixed 2s polls with no knob, slowing tests | Add a knob for the oracle kill grace and set it short in test-fleet-liveness |

### B31. Worker scratch isolation and hook staging

- Bundle id: `wpe-scratch-isolation`
- Owner: worker permission ergonomics (`specs/worker-permission-ergonomics/`)
- Open fragments: 6
- Smallest change: Give each worker and lens agent a private scratch root, stage hook files outside
  it, prove hook and shell TMPDIR agree, refuse symlinkable trailing-slash writes, and forbid
  destructive negative verification.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-03-negative-verify-risks-uncommitted-d7a51043` | Workers overwrite uncommitted files to prove a guard fails, risking loss of the only copy. | Tell workers to read old content via git show or a scratch copy, never overwrite the tree. |
| `2026-10-11-workers-glob-shared-tmp-f4607cf0` | Workers located temp files by globbing /tmp/tmp.*, hitting other workers' dirs | Forbid locating temp paths by glob in the worker brief; reuse the literal mktemp path |
| `2026-10-25-lens-agent-tmp-cleanup-f98747c0` | A lens sub-agent deleted other agents' /tmp dirs by pattern on a shared host | Give each lens agent its own scratch root and forbid removals outside it in the brief |
| `2026-10-25-scratch-tmpdir-live-check-3e72b3a5` | Nothing proves the hook's TMPDIR equals the Bash shell's TMPDIR in a live CLI | Run a manual live-worker check and record it as a manual test-spec entry |
| `2026-10-25-worker-hooks-tmpdir-fec044a7` | Hooks stage files in TMPDIR, the worker's writable scratch root, so a parallel call can tamper | Stage hook temp files under a private base outside the scratch root in the three hooks |
| `2026-10-25-write-arm-trailing-slash-43877005` | Write arms approve trailing-slash targets whose last part may become a symlink out of the zone | Reject trailing-slash write targets in the own-branch and scratch arms |

### B32. Anchor-integrity spec and spec-format wording drift

- Bundle id: `ai-spec-text-amendment`
- Owner: anchor integrity (freshness gate and anchors) (`specs/anchor-integrity/`)
- Open fragments: 5
- Smallest change: Expression-only amendment: carry the anchored-content narrowing into REQ-C1.1,
  D-5 and test-spec, settle the working-tree and checked-out-brief rules in spec-format, name the
  specs/&lt;id&gt; anchor form, drop transcribed figures.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-26-anchored-figures-outside-bundles-362f4de7` | Exemption records transcribe stale word-count figures; decided-rule rule stops at bundles | Extend decided-rule guidance to config justification records, cite the tool |
| `2026-08-27-spec-implementation-divergence-fb37c4bf` | The anchored-content narrowing never reached REQ-C1.1, D-5 or test-spec, which still say any edit. | Kickoff delta re-walk amending REQ-C1.1, D-5 and test-spec to anchored content. |
| `2026-10-07-gate-uncommitted-edit-read-b350a709` | spec-format sentences disagree on whether an uncommitted working-tree edit halts the gate | Amend spec-format Execution validity so the working-tree sentences match the fetched-ref gate |
| `2026-10-07-gate-view-local-main-drift-74e3b833` | Doctrine says the gate tracks checked-out brief, opposite of the fetch-before-gate rule | Replace the doctrine sentence with a pointer to spec-format Read surface per posture |
| `2026-10-11-anchor-namespace-arg-d4c517d9` | spec-format omits that the recorded spec-anchor argument is the specs/&lt;id&gt; namespace form | Add the namespace-form rule to spec-format Read surface per posture |

### B33. Custom-spec-location wording: &lt;root&gt;, remote writes, explain default

- Bundle id: `csl-spec-wording`
- Owner: custom spec location (`specs/custom-spec-location/`)
- Open fragments: 5
- Smallest change: Rename the install-root placeholder distinctly from &lt;root&gt;, amend REQ-F1.4
  for observation-carry, let resolve-root --explain report a default root, and settle the all-digit
  spec id argument grammar.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-07-execute-task-numeric-spec-id-d4e402af` | /execute-task 5 6 is ambiguous when a spec id is all digits | State in execute-task that a token on the task-id grammar is always a task id |
| `2026-10-07-root-placeholder-collision-38fc2599` | &lt;root&gt; names spec root in spec-format but install root in drain skill and docs/fleet.md | Rename install-root sites in drain SKILL and docs/fleet.md to a distinct placeholder |
| `2026-10-07-root-placeholder-script-comments-85803d53` | Three script comments also use &lt;root&gt;/scripts for the install root | Rename the placeholder in fleet-dispatch-env, fleet-streamjson and worker-command-guard comments |
| `2026-10-25-obs-remote-write-wording-5e5827ab` | REQ-F1.4 says no observation script writes remotely, but observation-carry pushes and opens a PR | Reword REQ-F1.4 to scope it to the routed --target write |
| `2026-10-29-default-root-flag-0af72772` | resolve-root --explain cannot say a layer-set spec_root is the default root | Add a default-ness field to resolve-root.sh spec --explain and use it in work-repo-registry |

### B34. Dependencies grammar and validator delta baseline

- Bundle id: `fg-dependency-grammar`
- Owner: format grammar and parser unification (`specs/format-grammar/`)
- Open fragments: 5
- Smallest change: Make spec-validate warn on non-id Dependencies tokens and REQ citation gaps, use
  a correct delta baseline for new bundles, and fix the legacy Task N lines in live bundles.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-21-release-hardening-malformed-deps-5ec1f447` | release-hardening tasks use legacy Task N dependency syntax flagged malformed | Normalize release-hardening dependency lines to the current dep grammar |
| `2026-08-18-inception-task17-malformed-deps-30c1ce7c` | inception Task 17 Dependencies line is prose, flagged malformed | Rewrite inception Task 17 dependencies in the dep-id grammar |
| `2026-09-09-dependencies-task-prefix-accepted-d7a0c5be` | spec-validate accepts Task-prefixed Dependencies tokens that orchestrate-state flags as malformed | Make spec-validate warn on a Dependencies token that is not a task id or none |
| `2026-09-09-spec-validate-baseline-short-circuit-fd394e79` | spec-validate baseline defaults to origin/main, so a new bundle skips every delta-sensitive rule | Fall back to the bundle-introducing commit when origin/main lacks the bundle |
| `2026-09-22-spec-validate-task-pins-eadbda66` | spec-validate misses a test-spec entry pinned to a task whose Citations omit that REQ | Add a task-pin cross-check to spec-validate.sh |

### B35. spec-validate correctness and its documented invariants

- Bundle id: `fg-validator-fixes`
- Owner: format grammar and parser unification (`specs/format-grammar/`)
- Open fragments: 5
- Smallest change: Fix CRLF and header-only handling, compare IDs against the merge base, and sync
  spec-format's invariant list and the skills' error-versus-warning wording with the validator.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-18-validator-blind-to-bodyless-header-a74b7e47` | Validator does not flag a header-only file the anchor now refuses, lagging its own format definition. | Add a spec-validate.sh finding for a header block running to end of file with no body. |
| `2026-08-25-exec-pointer-crlf-264e1881` | The Execution pointer check in spec-validate.sh breaks on CRLF checkouts. | Strip trailing CR before the exec_canon grep -xF comparison. |
| `2026-08-25-spec-validate-baseline-tip-79638b29` | spec-validate compares IDs against the origin/main tip, so stale branches get spurious renumber errors. | Resolve the baseline through git merge-base &lt;ref&gt; HEAD before reading blobs. |
| `2026-09-03-skill-drift-bdab2aa9` | Skills say all findings are errors; validator now emits warn-only heuristics at every status. | Reword the three skills to say errors halt, warnings surface. |
| `2026-09-03-spec-format-validator-list-lags-f3ec7760` | spec-format's validator invariants list is far behind what spec-validate.sh enforces. | Replace the doctrine list with a pointer to the script header's enforced set. |

### B36. External panel backend quirks and timeouts

- Bundle id: `flight-panel-backend-robustness`
- Owner: a spec-less flight (`flight`)
- Open fragments: 5
- Smallest change: Teach panel-review to chunk large diffs, neutralise @path tokens, treat empty
  exit-0 responses and unverifiable citations as failures, and give external steps a longer
  stoppable timeout.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-22-backend-cli-silent-prompt-drop-03653377` | External CLI returns exit 0 with empty response for some prompts | Treat an empty response as a failed panel leg and fall back to per-file prompts |
| `2026-08-26-backend-payload-ceiling-361dd7e5` | External panel backend fails around 150KB diffs; chunking recovers but the skill never says so. | Name a size threshold and the per-file chunking fallback in the backend invocation notes. |
| `2026-08-28-panel-backend-at-sigil-mangling-fbf43658` | External backend expands bare @tokens as file includes, fabricating findings on Perl/shell diffs. | Prepend an @-sigil-is-code instruction or escape @tokens for that backend. |
| `2026-09-21-panel-backend-fabricates-citations-4f7c2e91` | Panel backend fabricated a citation to material absent from its prompt | Record the prompt inventory with findings; drop citations to absent material |
| `2026-10-11-panel-step-timeout-5f46acd5` | External-backend panel step 1800s timeout too short; subagent-rung steps cannot be stopped | Raise the machine-local panel step timeout and document the subagent-rung stop limit |

### B37. Lint and link checks miss tests and config files

- Bundle id: `gc-lint-scope-gaps`
- Owner: guard coverage (`specs/guard-coverage/`)
- Open fragments: 5
- Smallest change: Widen lint:md, yamllint, script-modes and doc-links to tests/, .github and the
  repo overlay, and add a guard resolving backticked cross-spec paths and emitted files.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-24-split-stales-cross-spec-test-refs-e347c573` | Test-file split staled backticked cross-spec references; no guard resolves them | Add a tether resolving backticked tests/ and scripts/ paths in spec prose |
| `2026-08-26-link-check-github-md-11f65c68` | check-doc-links skips .github/*.md, leaving SECURITY.md links unguarded. | Add .github/*.md to check-doc-links.sh file set. |
| `2026-09-12-fixture-readmes-unlinted-22e17f16` | lint:md glob omits tests/**, so fixture READMEs go unlinted | Add tests/**/*.md to the lint:md glob |
| `2026-09-12-planwright-yml-unlinted-3a7a7756` | yamllint skips .claude/planwright.yml, the repo overlay every guard reads | Add .claude/planwright.yml to the lint:yaml target list |
| `2026-10-05-test-shebang-modes-e2c3f9c2` | check:script-modes covers scripts/ only; about 40 tests/ shebang files sit at 100644 | Widen check-script-modes to tests/ and fix the modes |

### B38. Knob docs agreement with defaults and fixtures

- Bundle id: `gc-options-reference-integrity`
- Owner: guard coverage (`specs/guard-coverage/`)
- Open fragments: 5
- Smallest change: Check options-reference and docs/fleet.md knob rows against defaults.yml by name,
  both directions, values included, with test and checker reading one table.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-27-ctxeng-knob-semantics-doubled-addc8dee` | Knob semantics written twice (defaults.yml and options-reference) with no agreement check | Extend check-options-reference.sh to compare a normative one-liner per knob |
| `2026-08-26-fleet-knobs-table-contract-c22b0254` | Multi-knob rows in the fleet knobs table pair names and defaults by position, unchecked on reorder. | Split multi-knob rows into one row per knob. |
| `2026-09-02-config-fixture-guard-direction-0fa6e03b` | Config fixture guards check only fixture-to-defaults, never the reverse or values. | Add the reverse-direction and value checks, and a guard in test-allocation-clamps.sh. |
| `2026-09-05-alloc-step-knobs-fleet-doc-31f2eac3` | Per-step tier knobs inherit the launch-surface family description in the knobs table. | Split the allocation family row or name the step axis separately. |
| `2026-09-23-options-tether-knob-table-scope-3c4e591c` | Test and checker select different Knob-headed tables in docs/fleet.md | Share one table-selection rule between the checker and its test |

### B39. Currency check restatements and refusal remedies

- Bundle id: `hg-currency-and-remedy-text`
- Owner: human gates (policy guard and sign-off) (`specs/human-gates/`)
- Open fragments: 5
- Smallest change: Reword the human-gates and custom-steps surfaces that restate the always-refuse
  currency check, and make base-merge and behind-base refusals name a remedy the policy guard
  accepts.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-01-mcg-gh-api-residual-b14af9aa` | merge-currency-guard still calls the gh api ready mutation an accepted residual with no onward pointer | Add a pointer to human-gates REQ-G1.7/G1.8 at the next merge-currency-guard amendment |
| `2026-10-11-base-sync-remedy-wording-03051cea` | Base-merge denies tell the tower to use a helper that refuses it; header and REQ-E1.2 wording wrong | Fix the tower remedy text and header, and reword REQ-E1.2/D-7 resolve recipe |
| `2026-10-12-mcg-currency-knob-more-restatements-f02cd82a` | More human-gates surfaces restate the always-refuse currency check ready_guard_behind_base relaxed | Reword human-gates REQ-C1.2, design and doctrine to cite merge-currency-guard REQ-A1.5/C1.11 |
| `2026-10-12-mcg-currency-knob-sibling-restatements-2b0ceaef` | human-gates D-9 and custom-steps doctrine still describe always-refuse currency check | Amend human-gates D-9 and doctrine/custom-steps.md to cite the ready_guard_behind_base policy |
| `2026-11-06-ready-guard-fetch-head-remedy-43bff019` | ready-guard's behind-base remedy names a FETCH_HEAD merge the policy guard refuses | Change the remedy to git fetch origin main && git merge origin/main or converge-sync-main.sh |

### B40. Policy guard merge-source detection errors

- Bundle id: `hg-policy-guard-merge-detection`
- Owner: human gates (policy guard and sign-off) (`specs/human-gates/`)
- Open fragments: 5
- Smallest change: Resolve merge sources exactly (own branch, FETCH_HEAD staleness, tag shadowing),
  screen converge-sync-main by tier and ownership, and stop matching plain loops as merges.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-31-policy-guard-merge-false-positive-b154e005` | policy-guard denied a plain test for-loop with the merge-helper message | Reproduce and fix the merge_policy matcher keying on loop or file-name substrings |
| `2026-11-05-own-branch-merge-not-self-approved-9c9c567f` | worker-command-guard self-approves only the PR base, so merging origin/&lt;own-branch&gt; prompts | Extend the merge arm to origin/&lt;REC_UNIT&gt; with the same shadow check |
| `2026-11-05-policy-guard-fetch-head-merge-f573a971` | fetch other branch then merge FETCH_HEAD passes when FETCH_HEAD was stale base | Refuse a FETCH_HEAD merge source after any fetch in the same command |
| `2026-11-06-converge-sync-no-tier-screen-de7f3222` | converge-sync-main has no tier screen and skips ownership outside the repo | Classify the script call as a base-merge act in the guard and refuse callers outside the repo |
| `2026-11-06-policy-guard-fetch-tag-shadow-05757c02` | A fetched tag refs/tags/origin/&lt;name&gt; shadows the remote ref the guard resolved | After any fetch in the command, admit only fully spelled refs/remotes/ merge sources |

### B41. Reserved-control spellings and retired phrasings

- Bundle id: `hg-reserved-control-spellings`
- Owner: human gates (policy guard and sign-off) (`specs/human-gates/`)
- Open fragments: 5
- Smallest change: Close the remaining reserved-control spellings (git config env, -C, quoted
  pushes, MCP globs on any server) and finish the retired-phrase sweep on guard surfaces and
  tower-queue.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-28-reserved-control-open-vectors-5d886bf9` | Several reserved-control spellings remain open: env-injected git config, git -C, quoted pushes, MCP undo | Close the listed spellings in the policy guard and add fixture verdicts and githooks cross-copy rows |
| `2026-10-07-spellings-mcp-glob-model-05ec412b` | test-reserved-control-spellings uses exact MCP name equality, blind to mcp__*__ deny globs | Match MCP deny entries as globs in test-reserved-control-spellings.sh like the wiring test |
| `2026-10-07-worker-profile-mcp-globs-b3778c06` | Worker profile denies GitHub MCP merge/write tools only under mcp__github__, not other servers | Add mcp__*__ deny globs for the no-knob merge and branch-write tools in worker-settings.json |
| `2026-10-18-human-gates-zone-restatements-421e62ef` | tower-queue.sh still uses retired human gates vocabulary | Message-only follow-up renaming the phrase in tower-queue.sh and its test pins |
| `2026-10-18-policy-guard-retired-phrase-a8031a3e` | Guard surfaces (policy-guard, githooks, worker _about) still carry retired phrasings | Message-only pause-protocol follow-up rewording the listed texts |

### B42. Diet fidelity and safety-floor doctrine

- Bundle id: `ih-diet-fidelity-doctrine`
- Owner: instruction-budget headroom (`specs/instruction-headroom/`)
- Open fragments: 5
- Smallest change: Amend instruction-hygiene doctrine: fidelity covers examples, keep grammar
  examples first, add a style-to-principle rung, settle the safety-floor reading, cite the
  context-engineering source.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-20-diet-example-fidelity-972182f6` | Diets degraded REQ-citing examples; fidelity rule should cover examples too | Add a diet rule that REQ-citing examples stay faithful or are removed whole |
| `2026-07-27-ctxeng-grammar-vs-judgment-examples-cba0413b` | Diet guidance should keep grammar examples and cut worked judgment examples first | State the grammar-versus-judgment example test in the diet guidance |
| `2026-07-27-ctxeng-principle-ladder-rung-222e4477` | Restoration ladder has no rung converting style rules into principles | Add a principle-conversion rung with an explicit hard-invariant exclusion set |
| `2026-07-27-ctxeng-source-set-a345a39b` | Add the Claude-5 context-engineering post as a scoped fifth source | Add a fifth cited source bullet to instruction-hygiene.md Why section |
| `2026-09-21-safety-floor-two-readings-d20e8988` | instruction-hygiene safety floor has operational and structural readings; doc does not say which wins | Add a sentence to instruction-hygiene.md naming which reading governs |

### B43. Kickoff resume mode and spec worktree handling

- Bundle id: `kl-kickoff-skill-gaps`
- Owner: kickoff lifecycle (`specs/kickoff-lifecycle/`)
- Open fragments: 5
- Smallest change: Add a resumed-first-activation mode and experiment evidence class, test
  spec-branch landedness, recognise the spec worktree by branch, fix the D-3 citation, and re-lens
  mid-walk D-ID mints.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-07-skill-drift-b1bb6557` | spec-kickoff lacks a resumed-first-activation mode after a halt and an experiment evidence class | Add a resumed-first-activation arm and an experiment evidence class to kickoff-verification |
| `2026-09-18-kickoff-stale-spec-branch-99a03c33` | Kickoff step 5 reuses a merged leftover spec branch with no landedness test | Test landedness with merge-base --is-ancestor against the merged PR head first |
| `2026-09-22-kickoff-brief-template-cite-5b082de8` | Brief template cites D-3 ambiguously (bootstrap D-3); spec-draft and kickoff disagree on worktree name | Cite bootstrap D-3 in the kickoff skill and align the spec worktree naming |
| `2026-09-22-kickoff-worktree-name-212172f2` | Kickoff step 5 treats a worktree holding the spec branch but not named &lt;spec&gt;-spec as unrelated | Accept any worktree whose checked-out branch is the spec branch |
| `2026-09-22-skill-drift-9715b9de` | spec-draft reads commit_on_draft two-layer, and lacks an arm for a clean user-made worktree | Read commit_on_draft via config-get.sh; add the clean-worktree arm to D-44 |

### B44. Allocation script spawn cost and duplicate lock helpers

- Bundle id: `ma-allocation-scripts-refactor`
- Owner: model allocation (`specs/model-allocation/`)
- Open fragments: 5
- Smallest change: Memoize knob and store-dir resolution through the allocation chain, short-circuit
  inherit, and share one unit-lock helper between adapt and feedback.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-25-selection-resolver-call-amplification-3eb2b603` | The allocation-to-fleet fallback doubles knob-resolver calls per dispatch; memoization coverage unexamined. | Measure fallback-chain resolver calls and memoize them within the selection boundary. |
| `2026-09-02-allocation-ledger-store-forks-22426548` | allocation-ledger store_dir forks fleet-state.sh root on every call with no memoization. | Memoize the resolved store dir in a variable at first use. |
| `2026-09-02-allocation-lock-helper-duplication-1f87d05e` | Unit-lock helpers are duplicated in allocation-adapt.sh and allocation-feedback.sh. | Extract take/release_unit_lock and surface_degradation into one sourced helper. |
| `2026-09-05-alloc-launch-spawn-cost-4f021236` | A launch costs about 55-75 spawns just to print inherit. | Memoize store_dir, hoist config reads above the lock, short-circuit inherit earlier. |
| `2026-10-02-allocation-adapt-chain-cost-89ef0502` | allocation-adapt.sh chain dominates four slow test files with tens of thousands of forks | Memoize store_dir and hoist config reads in the allocation chain |

### B45. Model-allocation text and health accuracy

- Bundle id: `ma-text-accuracy`
- Owner: model allocation (`specs/model-allocation/`)
- Open fragments: 5
- Smallest change: Fix the test-spec non-zero wording, script header claims, mixed inherit labels
  and health on an unresolvable store, and dedupe the fleet and allocation doc narratives.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-26-spec-surfaced-nonzero-wording-951fd86f` | Test-spec says surfaced non-zero while REQ and D-6 forbid a blocked launch. | Expression-only edit to the REQ-F1.1 test-spec sentence. |
| `2026-09-02-alloc-replay-fork-claim-cfd66cfe` | alloc_replay header claims no fork per row, but applied rows fork up to three substitutions. | Correct the alloc_replay header comment to state the per-applied-row forks. |
| `2026-09-02-allocation-health-store-failure-a28c67e0` | health returns healthy when the ledger store cannot be resolved at all. | Resolve ledger_path into a variable first and propagate its exit before check_health. |
| `2026-09-05-adapt-mixed-config-inherit-label-1ea322e4` | Mixed config rows are labelled inherit=full when only one dimension inherited. | Label partial versus full from the per-dimension outcome. |
| `2026-09-07-fleet-allocation-doc-duplication-3f5de74f` | docs/fleet.md and docs/allocation.md carry duplicated petition and feedback narratives that already diverge | Collapse the fleet.md copy to a pointer at docs/allocation.md |

### B46. Step tiers and per-launch options reaching the backend

- Bundle id: `ma-tier-plumbing`
- Owner: model allocation (`specs/model-allocation/`)
- Open fragments: 5
- Smallest change: Pass step type and tier per launch through offload-dispatch to the backend, with
  a settings file argument, one tier_of_model, and roster-additive caps.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-07-allocation-step-type-callsite-f17e821b` | No launch point passes --step-type to allocation-adapt.sh, so the per-step tier knobs are unreachable | Pass --step-type from each per-step launch point that runs a model step |
| `2026-09-07-roster-consolidation-residuals-59c3ad96` | tier_of_model still spelled in two scripts and per-model cap knobs make adopting a model non-additive | Derive tier_of_model from the ladder rank in one place; generalize per-tier caps |
| `2026-10-05-step-tiers-cannot-raise-or-apply-e9ae3805` | Step tiers never reach the launch, can only lower, refuse under inherit, and have no per-point knob | Amend model-allocation D-8 to allow raise, wire --step-type, add per-point tiers |
| `2026-10-18-offload-per-launch-model-a330d4cc` | offload-dispatch applies one tier to every launch; fan-out cannot vary models | Add a per-launch model request to offload-dispatch audited via the allocation ledger |
| `2026-10-18-worker-settings-passthrough-9a16099f` | No backend launch takes a settings file, so venture worker deny-list is contract-only | Add an optional settings-file argument to offload-dispatch dispatch |

### B47. Drafting and release launch kinds with spec-branch push

- Bundle id: `mc-launch-kinds`
- Owner: mission control (`specs/mission-control/`)
- Open fragments: 5
- Smallest change: Ship drafting and release launch kinds whose profiles plain-push only their named
  branch, launch kickoff relays in the spec worktree, and cover the kickoff profile cases in Task
  19.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-11-04-spec-kickoff-push-vs-policy-guard-04bcb01a` | spec-kickoff pushes the spec branch but the policy guard refuses agent writes to spec branches | Admit a kickoff-scoped push of the own spec branch, or hand the push to the operator up front |
| `2026-11-05-kickoff-relay-spec-worktree-594f74ed` | Kickoff relay launches in a fresh flight worktree, so spec-kickoff stops on the spec worktree | Make the kickoff launch kind target planwright/&lt;spec&gt;/spec and reuse its spec worktree |
| `2026-11-05-mc-drafting-launch-kind-416f7a6a` | Ship a drafting launch kind allowed to plain-push only its named spec branch | Add the drafting launch kind, guard admission and cross-copy cases |
| `2026-11-05-mc-release-launch-kind-5ab3b6b5` | Ship a release launch kind that arms release-arm or publishes after merge | Add the release launch kind, profile, record and guard admission |
| `2026-11-05-mc-task19-kickoff-cases-bf49d263` | Task 19 Done-when omits kickoff profile cases human-gates REQ-G1.9/G1.10 require | Delta re-walk adding the missing cases to mission-control Task 19 citing the human-gates REQs |

### B48. Mission-control handover, ticks and durable prompts

- Bundle id: `mc-session-lifecycle`
- Owner: mission control (`specs/mission-control/`)
- Open fragments: 5
- Smallest change: Make attended handover self-succeed at natural breaks, drop dead handover verbs,
  gate the failsafe tick through the change gate, and keep prompt templates off /tmp.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-01-tmp-cleanup-eats-tower-scratch-53a1587a` | macOS /tmp cleanup deleted long-running tower prompt templates; workers skipped a missing file | Keep dispatch prompts in a durable home and halt a worker on a missing named file |
| `2026-11-06-mc-attended-self-succession-32bde2c6` | Operator wants attended mission-control sessions to self-succeed in a new tmux pane | Amend REQ-L1.8, D-42 and REQ-A1.1 and add a tmux self-succession task |
| `2026-11-06-mc-failsafe-tick-change-gated-1f599c9d` | A model-side hourly timer woke mission control at ~1M tokens per tick, bypassing the change gate | Forbid self-scheduled wakes in the skill and have the tick re-run the runner step |
| `2026-11-06-mc-handover-attended-verbs-b632d19a` | mc-handover.sh path and offer verbs still raise attended handover items nobody calls | Retire path and offer with their tests, or make offer refuse an attended holder |
| `2026-11-06-mc-handover-context-threshold-3b1fad05` | Operator wants handover at natural breaks or about 40 percent context | Lower handover_context default to 40 and amend REQ-L1.5/D-29 with a break rule |

### B49. Ready-guard hook cost, bounds and flip-point checks

- Bundle id: `mcg-ready-guard-fixes`
- Owner: merge currency guard (ready-guard) (`specs/merge-currency-guard/`)
- Open fragments: 5
- Smallest change: Pre-screen before jq, bound hooks with a group kill, read commands without
  dropping NUL, hold flip-point names once, and exclude flip-point nodes before pagination checks.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-29-ready-guard-per-bash-jq-cost-ec12d9b8` | ready-guard spawns jq on every Bash call; raw pre-screen would short-circuit | Run raw_evidences_ready_flip before any jq call, with a mutation sweep |
| `2026-10-05-flip-point-context-list-620ebb37` | Flip-point context names are held twice and derived a third time, pinned by source-text tests | Move the context list into one shared constant every script sources |
| `2026-10-05-flip-point-page-budget-7fad13ee` | rl_ci_state checks hasNextPage before excluding flip-point nodes, so 100 checks turns green to too-many | Exclude flip-point contexts before judging the page budget, or page further |
| `2026-10-07-hook-command-nul-byte-85f0b73d` | policy-guard, ready-guard and other hooks read the command via substitution, dropping NUL bytes | Defer or refuse commands holding a NUL byte in policy-guard.sh and ready-guard.sh |
| `2026-10-11-ready-guard-hook-time-bound-2497969c` | ready-guard hooks have no timeout; uutils -k misses grandchildren, so a killed hook fails open | Set hook timeouts in hooks.json and bound gh calls so the worst case stays under them |

### B50. Bot-review drain proof, polling and request path

- Bundle id: `re-bot-review-fixes`
- Owner: review effectiveness (`specs/review-effectiveness/`)
- Open fragments: 5
- Smallest change: Prove a drain from the bot review body and timeline rather than thread counts,
  poll on the observed latency, handle merge-commit full reviews, and request through
  request-reviewer.sh.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-09-bot-rereview-login-silent-noop-8b24690f` | Bot re-review works via timeline check; bot findings can hide in review body with zero threads | Read the review body for suppressed findings before treating zero threads as clean |
| `2026-09-17-bot-resolves-its-own-threads-51b53aa5` | Bot can resolve its own threads, so zero unresolved is not proof of a drained review | Track resolved thread ids per run and report any the run did not resolve |
| `2026-09-17-bot-review-latency-overstated-67aafd6a` | Bot review lands in 4-5 minutes; a flat 30s poll over a 20-minute window wastes time | Poll with short-then-backoff intervals, keeping the 20-minute absence floor |
| `2026-10-06-bot-incremental-refused-after-merge-f19f24d5` | Bot refuses incremental review after a merge commit, forcing a second full review | Document merging main before the bot first review when a sibling PR will land |
| `2026-10-18-bot-review-request-redraft-7fa57b07` | /bot-review's request arm could route through scripts/request-reviewer.sh | Point /bot-review's request arm at scripts/request-reviewer.sh with the quoted bot login |

### B51. Host-wide coordination of suites and gates

- Bundle id: `tt-host-load-coordination`
- Owner: test throughput (`specs/test-throughput/`)
- Open fragments: 5
- Smallest change: One host scheduler: a single lock order with full-suite-run owning the host lock,
  load-aware admission (a heavy-admit caller), bounded mutation fan-out, setsid detaching, pause and
  resume state, and refusing whole-filesystem scans.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-05-workers-uncoordinated-test-runs-6ee76cba` | Workers on one host start suites uncoordinated and contend for CPU | Add a host-wide scheduler or semaphore for heavy runs across workers |
| `2026-10-11-polish-mutation-fanout-load-fe2744fa` | Polish workers fanned mutation runs to 19 parallel full suites, tripping others' gates | Cap parallel suite runs in polish or mutation-testing guidance via a host-load knob |
| `2026-10-18-gate-under-nohup-hangs-signal-tests-5d41e92b` | Gate under nohup makes HUP-asserting suites hang; detached gates need setsid | State setsid as the detach launcher in docs/overlays.md and worker briefs |
| `2026-10-19-gate-pool-wait-expiry-4d47cc6b` | Full-suite pool wait expired under a saturated wave; pool and flock queue the host twice | Make full-suite-run.sh own the host lock and size step_pool_wait to the queue |
| `2026-10-25-gate-lock-order-inversion-ac484ef0` | Workers take the host flock and pool slot in opposite orders, stalling both for 60m | Make full-suite-run.sh own the host lock in one documented order |

### B52. Untrusted values printed raw in refusals and warnings

- Bundle id: `ub-output-sanitize`
- Owner: universal binary (portability and spawn cost) (`specs/universal-binary/`)
- Open fragments: 5
- Smallest change: Route refusal and warning output through echo-safety, reject control bytes in
  catalog ids, and keep trailing newlines in canonicalized symlink targets.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-24-catalog-warning-raw-ids-621a3631` | resolve-catalog prints ids raw in warnings and builder-guards passes stderr through | Sanitize ids in resolve-catalog.sh warn() |
| `2026-10-07-refusal-paths-raw-control-bytes-79fd17ed` | Many refusal paths (orchestrate-lock and others) print raw untrusted values with control bytes | Sanitize untrusted interpolations in the listed refusal messages and add a guard for the shape |
| `2026-10-11-catalog-id-control-chars-af2f6670` | resolve-catalog.sh accepts quoted ids with tabs or control bytes, breaking --explain output | Refuse control characters in catalog ids at the merge in resolve-catalog.sh |
| `2026-10-11-overlay-contain-unsanitized-path-bba0abad` | resolve-overlay-root --contain prints the candidate path unsanitized; dash echo expands escapes | Pass the escapes-overlay-root message paths through sanitize_printable in the helper |
| `2026-10-12-overlay-contain-readlink-newline-4230dcfa` | canon_path strips trailing newlines from symlink targets, canonicalizing to another path | Read readlink output with a sentinel suffix in canon_path to keep trailing newlines |

### B53. Shared parsers for external config and tables

- Bundle id: `ub-shared-parsers`
- Owner: universal binary (portability and spawn cost) (`specs/universal-binary/`)
- Open fragments: 5
- Smallest change: Provide shared fail-closed readers for markdown tables, TOML, inline maps and
  defaults.yml, and move the hand-rolled guard parsers onto them.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-18-adhoc-config-parsers-2ade3c44` | Repo accumulating hand-rolled external-config parsers with duplicated boundaries | Extract a shared strict block-mapping reader when the next parser lands |
| `2026-08-26-markdown-table-parsers-16c6a439` | Five guards hand-roll markdown table parsing; a shared fail-closed helper is wanted. | Extract a header-driven table-reading helper and move the guards onto it. |
| `2026-09-03-mise-toml-parser-seam-7fabca6d` | check-no-ci-evals embeds a TOML reader with no reusable seam; Task 11 re-implemented one. | Extract one sourced mise.toml reader used by both guards. |
| `2026-09-28-options-check-flat-reader-61161b12` | check-options-reference.sh keeps its own defaults.yml awk reader that diverges from config-get | Read defaults through config-get in check-options-reference.sh |
| `2026-10-17-inline-map-parser-89a9d2e7` | Two inline {key: value} parsers disagree on quotes | Share one inline-map parser with a per-option value validator |

### B54. Guard reads of other processes' environ

- Bundle id: `wpe-recursive-readers`
- Owner: worker permission ergonomics (`specs/worker-permission-ergonomics/`)
- Open fragments: 5
- Smallest change: Refuse recursive readers rooted at / or /proc and symlinks resolving into
  /proc/&lt;pid&gt;/environ.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-10-environ-recursive-readers-74aadeae` | Recursive readers on /proc or / still read other processes' environ files | Defer recursive readers whose operand canonicalizes to /, /proc or below |
| `2026-10-11-environ-renamed-symlink-9eabaa16` | A pre-existing renamed symlink to /proc/&lt;pid&gt;/environ still reads through the guard | Spec amendment to canonicalize literal operands of file-opening verbs |
| `2026-11-05-no-filesystem-root-search-guard-3548c59c` | Nothing stops workers from running find or bfs over / or $HOME | Refuse root- or home-wide find/bfs in the worker command guard |
| `2026-11-05-no-host-load-scheduling-01033adb` | mc-budget admit heavy has no caller; heavy suites start regardless of load | Have detached-run and step-run take mc-budget admit heavy before full and hook suites |
| `2026-11-05-no-priority-pause-resume-327ffa59` | No recorded pause state or priority-ordered resume for workers | Add a recorded pause state and priority-ordered resume to mission control |

### B55. Catalog resolution: empty output, id parity, dash, malformed seed

- Bundle id: `co-catalog-seed-handling`
- Owner: customization overlay and config resolution (`specs/customization-overlay/`)
- Open fragments: 4
- Smallest change: Make resolve-catalog run under bash explicitly, fail loudly on a
  present-but-malformed or unparsed core seed, and check prose and yaml catalogs share ids rather
  than counts.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-22-resolve-catalog-decision-domains-empty-a672bb2e` | resolve-catalog decision-domains printed empty despite the core seed being present | Emit the core seed with no overlays, or document prose-seed-primary in kickoff |
| `2026-08-18-catalog-prose-yaml-id-drift-a0875377` | Prose and yaml catalogs share no ids; only count parity is checked | Annotate prose entries with stable ids and assert set equality |
| `2026-09-12-malformed-core-seed-degradation-7427255e` | format-grammar REQ-F1.3 says nothing about a present-but-malformed core seed in the kickoff gap check | State what the gap check does when resolve-catalog hard-fails on the core seed |
| `2026-09-28-resolve-catalog-dash-43966801` | resolve-catalog.sh (a bash script) fails under dash and printed only a header in a kickoff gap check | Make the kickoff gap check invoke resolve-catalog.sh with bash and find why it printed only the header |

### B56. One degradation policy across config readers and knob resolvers

- Bundle id: `co-knob-resolver-family`
- Owner: customization overlay and config resolution (`specs/customization-overlay/`)
- Open fragments: 4
- Smallest change: Delegate the per-knob resolvers to resolve-config-knob, align config-get and
  resolvers on one malformed-value policy, read defaults from the script's own root first, and warn
  on spaced keys in --fallback.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-16-knob-resolver-dedup-6ae6195c` | Per-knob resolvers hand-roll the same policy; could delegate to resolve-config-knob.sh | Re-point the per-knob resolvers onto resolve-config-knob.sh |
| `2026-07-23-resolver-degrade-target-divergence-c344dae6` | config-get degrades to next layer, resolvers to core default; inconsistent | Harmonize degrade targets or document the file-level vs value-level distinction |
| `2026-09-26-config-get-root-precedence-fe78aa96` | config-get reads defaults from PLANWRIGHT_ROOT before its own script root, so a branch key reads absent | Prefer the calling script own root for core defaults in config-get.sh |
| `2026-10-07-resolver-spaced-colon-silent-b93f496c` | resolve-config-knob --fallback silently ignores a 'key : v' line instead of warning | Warn on a spaced-colon or duplicate key under --fallback as under --degrade |

### B57. Stream-json alarm-scan field guards and ended workers

- Bundle id: `eb-streamjson-alarm-scan`
- Owner: execution backends (`specs/execution-backends/`)
- Open fragments: 4
- Smallest change: Guard every alarm-scan field, harden the capture dir and UTF-8 truncation, and
  stop re-raising receipts for normally ended workers.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-23-streamjson-alarm-scan-field-guards-ed0c7477` | alarm-scan guards a_id but not sibling a_kind/a_age fields | Validate a_kind and a_age in alarm-scan |
| `2026-07-23-streamjson-capture-confidentiality-e4477129` | Capture dir best-effort chmod, unanchored event match, symlink-following writes | Fail-closed 0700 capture dir, 600 files, parsed type match |
| `2026-07-23-streamjson-deny-message-utf8-split-c50cc98d` | Deny message head -c 512 can split a UTF-8 character | Trim back to a UTF-8 character boundary after the byte bound |
| `2026-11-05-streamjson-ended-worker-pending-b41664cf` | alarm-scan keeps re-raising pending receipts of a normally ended stream-json worker | Treat no pidfiles plus a result file as death in alarm-scan, with live-pid fixtures first |

### B58. Stream-json status and envelope state correctness

- Bundle id: `eb-streamjson-state-correctness`
- Owner: execution backends (`specs/execution-backends/`)
- Open fragments: 4
- Smallest change: Write envelopes atomically, read status under the lock, test the result subtype,
  and make recover default to the recorded launch cwd.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-04-status-never-tests-result-subtype-cb4b817b` | cmd_status never tests the result subtype, disagreeing with the stuck detector's contract. | Render ended for any non-success result subtype in cmd_status. |
| `2026-09-30-streamjson-envelope-write-not-atomic-e42d9722` | handle_line writes req-id.json with a truncating printf, unchecked, so readers can see partial envelopes | Write the envelope temp-then-rename and check the write |
| `2026-10-06-streamjson-recover-drops-cwd-61f61198` | recover without --cwd relaunches in the caller directory, not the recorded launch cwd | Default recover to the cwd the launch recorded in the worker dir |
| `2026-10-11-streamjson-status-transient-double-count-8c6d9073` | status_awaiting reads journal and spools without the lock, double-counting a request | Read journal and spool files under the journal lock in status_awaiting |

### B59. Fleet-autonomy expression amendment

- Bundle id: `fa-spec-amendment`
- Owner: fleet autonomy (`specs/fleet-autonomy/`)
- Open fragments: 4
- Smallest change: Expression-only amendment: retire the WorktreeCreate hook mechanism in REQ-B1.2,
  reconcile Task 2 logging with risk-31, cite WPE D-6 from D-19, and name context-budget-peer in
  autoheal doctrine.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-17-context-budget-doctrine-gap-06086c51` | Autoheal doctrine omits the shipped context-budget-peer.sh corroborating signal | Add a one-line budget-signal mention of context-budget-peer.sh to context-budget-autoheal.md |
| `2026-07-17-task2-donewhen-risk31-wording-0df49a3c` | Task 2 Done-when says every classification logs, contradicting signed risk-31 decision | Expression-only amendment aligning Task 2 Done-when with risk row 31 |
| `2026-07-18-fa-sole-mechanism-fwd-citation-bddb4918` | fleet-autonomy D-19 sole-mechanism claim lacks forward citation to WPE D-6 | Add a forward citation from fleet-autonomy REQ-E1.4/D-19 to worker-permission-ergonomics D-6 |
| `2026-08-26-fleet-autonomy-b1-2-create-half-drift-bed09898` | fleet-autonomy REQ-B1.2 names a WorktreeCreate hook mechanism that can no longer be used. | Amend REQ-B1.2 and D-7: dispatch-seam writer for creation, hook for removal. |

### B60. Fleet home resolution and directory mode checks

- Bundle id: `fh-fleet-home`
- Owner: fleet hardening (`specs/fleet-hardening/`)
- Open fragments: 4
- Smallest change: Resolve a fleet home under marketplace installs, share one resolve-and-check
  helper across flight scripts that checks ancestors and accepts ACL-marked owner-only modes, and
  pin the mode at creation.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-17-fleet-state-home-unresolved-b085ac53` | No fleet home resolves under a marketplace install, silently disabling throttle and tower marker | Resolve the fleet home from the plugin cache path or document the required env |
| `2026-09-20-mode-glob-rejects-acl-homes-5b1c9e77` | Owner-only mode globs reject a POSIX ACL plus, with a misleading chmod hint | Accept or diagnose the ACL suffix in all six globs and fix the message |
| `2026-10-25-fleet-home-ancestor-privacy-cd693357` | Brief privacy checks skip the fleet home's ancestors, so a writable parent allows a home swap | Check every ancestor of the fleet home for sticky or owner-only writes in valid_brief and fleet-task-brief |
| `2026-10-25-flight-fleet-home-resolvers-dfe038b4` | Three flight scripts resolve and check the fleet home differently | Add one fleet-home resolver to flight-common.sh and use it in all three scripts |

### B61. Fleet sweep and cleanup edge cases

- Bundle id: `flc-sweep-hardening`
- Owner: fleet lifecycle closure (`specs/fleet-lifecycle-closure/`)
- Open fragments: 4
- Smallest change: Test cleanup and sweep exit paths, validate worktree-track paths, handle an
  unborn HEAD, and source rehearsal scratch patterns from one list.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-17-fleet-inspect-tree-unborn-head-f63eb20c` | fleet-sweep inspect_tree reports uninspectable on an unborn HEAD | Treat an unborn HEAD as zero unpushed in fleet-sweep.sh inspect_tree |
| `2026-07-17-fleet-scan-valid-path-gap-e9daedb7` | worktree-track scan writes git worktree paths without valid_path check | Run valid_path on scan-sourced paths before writing the registry |
| `2026-07-17-fleet-task4-test-coverage-gaps-58d07579` | Untested exit paths in fleet-cleanup, fleet-sweep and fleet-worktree-track | Add the listed exit-path cases to the three fleet suites |
| `2026-10-11-rehearsal-scratch-list-drift-f46c4eea` | rehearsal-lifecycle held_classes hand-copies scratch patterns and lacks .deferred.* | Source fleet-streamjson.sh scratch_patterns in both tests instead of copies |

### B62. Checks and tests that can pass vacuously

- Bundle id: `gc-check-vacuity`
- Owner: guard coverage (`specs/guard-coverage/`)
- Open fragments: 4
- Smallest change: Add row floors and canaries to the corpus guard harness, lint $? helpers against
  substitutions, narrow the watchdog exemption, and make number-copy and verdict-figures read one
  span.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-14-guard-test-vacuous-pass-e9f5cc37` | Corpus guard harness can pass vacuously: no row floor, no canary, no expectation validation | Validate the expectation column; row floor (acf81860) and canary (57700049) landed |
| `2026-09-25-verdict-status-substitution-dd0bcf40` | A test helper judging $? is defeated by a command substitution in its arguments | Add a lint over tests for status-reading helpers called with $( in their arguments |
| `2026-10-05-watchdog-adversarial-exemption-549528e1` | test-fleet-adversarial exempts fleet-tower-watchdog.sh wholesale from its no-LLM audit | Narrow the exemption to the tower relaunch claude command |
| `2026-11-01-verdict-span-number-copy-815143aa` | check:number-copy and check:verdict-figures read different verdict spans, so one passes and one fails | Decide in universal-binary Task 9 or an amendment to align the two spans |

### B63. Workflow shell lint, pipefail and privileged checkout

- Bundle id: `gc-workflow-guards`
- Owner: guard coverage (`specs/guard-coverage/`)
- Open fragments: 4
- Smallest change: Lint workflow run blocks with pipefail, check what privileged workflow_run jobs
  check out and their origin, type-check the panel mod in CI, and re-run title lint on edits.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-26-workflow-run-step-lint-gap-27a7cb3f` | run: steps piping without pipefail pass silently; test-timing.yml tee defeats exit | Add a check that piped run: steps set pipefail, and fix test-timing.yml |
| `2026-09-02-posture-guard-checkout-blind-637088a8` | Posture guard does not check what a privileged workflow_run job checks out. | Add an assertion: privileged workflow_run checkout ref/repository never resolves a head_ or workflow_run field. |
| `2026-09-02-workflow-shell-unlinted-2865c193` | Shell in workflow run blocks is unlinted; the release guard's tri-state lives there. | Move the guard body into a scripts/ file or add actionlint to check. |
| `2026-10-26-panel-mod-no-ci-typecheck-6d91e632` | CI never type-checks the panel mod's TypeScript; declarations are not CI-reachable | Vendor a CI-reachable copy of the declarations and add a typecheck-ts CI step |

### B64. Human-gates amendment: base merges, pause arm, defaults

- Bundle id: `hg-spec-amendment`
- Owner: human gates (policy guard and sign-off) (`specs/human-gates/`)
- Open fragments: 4
- Smallest change: Amend D-7, REQ-E1.1 and REQ-A1.6 to the built checks, decide where the dispatched
  pause arm records, and revisit default ergonomics per operator level.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-11-zone-pause-vs-signed-tasks-c7a1d483` | Dispatched pause arm writes tasks.md but convergence steps may not edit signed bundles | Give dispatched zone findings a sanctioned home (audit record or PR body) in gate-wiring |
| `2026-11-05-human-gates-a16-test-spec-stale-4103c556` | human-gates test-spec REQ-A1.6 still says merge-base check, now a fixed-string check | Reword the REQ-A1.6 test-spec entry with its self-re-anchor at the next amendment |
| `2026-11-05-human-gates-defaults-ergonomics-c2ecd55c` | Operator wants the human-gates defaults' ergonomics revisited for every operator level | Run /spec-draft --extend human-gates reviewing the gate defaults |
| `2026-11-06-human-gates-d7-own-branch-source-fec1bc42` | human-gates D-7 and REQ-E1.1 still say only the PR base may be merged | Amend D-7, REQ-E1.1 and its test-spec entry through /spec-kickoff |

### B65. Allocation ledger shape and feedback coverage

- Bundle id: `ma-ledger-and-feedback`
- Owner: model allocation (`specs/model-allocation/`)
- Open fragments: 4
- Smallest change: Produce the ledger unit key at one place, drop the step-launch no-op row, report
  top-tier units, and run feedback before fence gc can exit.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-02-allocation-top-tier-blind-270651d6` | Feedback loop is silent for units started at the ladder top that never escalate. | Decide via REQ-F1.2 amendment or REQ-F1.3 stats whether top-start units get a condition. |
| `2026-09-05-alloc-ledger-write-amplification-236d827e` | A step launch appends a second no-op ledger row, doubling growth and scans. | Decide whether an inheritance no-op earns a row, or add ledger compaction. |
| `2026-09-06-allocation-ledger-unit-key-159e7fab` | Ledger unit key shape is asserted at one end and produced by nothing; bundles may mismatch. | Define the unit-key grammar once and test fence and launch writers agree, bundles included. |
| `2026-09-06-gc-no-origin-skips-feedback-f233faa3` | fleet-fence gc exits 5 with no origin before the completion feedback report runs. | Hoist report_terminal_feedback above the origin precondition for gc. |

### B66. Mission-control proposals inventory and binding

- Bundle id: `mc-proposals`
- Owner: mission control (`specs/mission-control/`)
- Open fragments: 4
- Smallest change: Add program-block rows and the repeated-denial shape, record proposal changes as
  structured values apply can bind to, and add eval arms for denials and proposals.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-11-02-mc-inventory-program-block-190f117b` | The mechanism inventory has no program block rows, so no program-block proposal can be raised | Add program_&lt;name&gt;_&lt;field&gt; rows to mc-kb.sh inventory-refresh |
| `2026-11-02-mc-proposal-value-8e998e2c` | Proposals record their change as free text, so apply cannot bind to the accepted value | Store a structured accepted value in proposals.tsv and make mc-config apply check it |
| `2026-11-04-mc-denial-repeat-spec-drift-1e56525f` | REQ-B1.5 and D-14 list repeat shapes without the repeated-guard-denial shape now built | Amend REQ-B1.5 and D-14 to name the repeated guard denial shape |
| `2026-11-04-mc-eval-denial-proposal-arm-736f17d6` | The mission-control eval stand-in has no arm for denial noting and the proposals scan | Add a denial-proposal arm and grade check to the mission-control eval fixture |

### B67. Execute the resolved path; report plugin version skew

- Bundle id: `newspec-resolved-path-and-version`
- Owner: a new spec: resolved-path execution and version skew (`new-spec`)
- Open fragments: 4
- Smallest change: New spec making every surface execute the resolved absolute path it prints,
  resolving the repo's own doctrine when self-hosting, and reporting tower-worker or kickoff
  anchor-computer version skew.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-18-plugin-version-skew-d4d2236e` | Tower and dispatched worker can run different plugin versions with no surface reporting the skew. | Emit flight-common's root-skew pair on the /orchestrate dispatch path too, not only flight dispatch. |
| `2026-08-25-skill-drift-614d4db7` | Workers in this repo resolve the installed plugin's stale doctrine, not the repo's own. | Resolve doctrine repo-first in resolve-rule-doc.sh when the host repository is planwright. |
| `2026-08-25-skill-drift-dd8e3d7e` | A kickoff from the plugin cache computes a different anchor than main's script. | Same repo-first resolution for the anchor script when self-hosting. |
| `2026-09-26-what-prints-is-what-runs-2b27a26c` | Operator wants every surface to execute exactly the resolved absolute path it printed | Draft a spec for a shared resolve-and-exec helper plus a bare-name execution guard |

### B68. Kickoff dialogue log home, schema and rubric

- Bundle id: `od-kickoff-log-and-rubric`
- Owner: operator dialogue (`specs/operator-dialogue/`)
- Open fragments: 4
- Smallest change: Define the kickoff decision log home and one schema shared by doc, fixture and
  graders, dedupe the self-verdict blocklist, and pin the delta re-walk heading shape.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-21-rubric-blocklist-dup-78a76eac` | Self-verdict blocklist triplicated across grade.jq and two rubric scripts | Move the blocklist to one shared source consumed by all three |
| `2026-09-12-eval-log-schema-divergence-aadfa08b` | Documented dialogue log schema and the shipped kickoff eval fixture and graders use different schemas | Reconcile the fixture and graders with kickoff-dialogue's schema, or state the divergence |
| `2026-10-08-kickoff-log-home-4d4ba9c7` | Kickoff decision/transcript log has no defined home outside the eval harness | Define a gitignored local path for the attended kickoff log the brief can cite |
| `2026-10-10-kickoff-delta-entry-headings-2f0438af` | spec-format pins no delta re-walkthrough entry heading shape; mirroring collides with MD024 | Pin a delta-entry heading shape in spec-format |

### B69. Observation script input and read checks

- Bundle id: `or-obs-tooling-hardening`
- Owner: observation recording (`specs/observation-recording/`)
- Open fragments: 4
- Smallest change: Give obs-consume a flight identity, widen the --target screen, reject control
  bytes in --obs-dir, and fail check-obs on unreadable stores.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-11-flight-obs-consume-arm-b1d4c9d4` | obs-consume.sh has no flight identity, so flights consume under an unrelated spec | Add a flight arm to obs-consume.sh with Consumed-by naming the flight id or PR |
| `2026-10-18-obs-dir-control-bytes-dd7362b5` | obs scripts accept --obs-dir with tab or control bytes and print paths raw | Refuse control bytes in --obs-dir across obs-record, check-obs, obs-render, obs-consume |
| `2026-10-18-screen-widening-7ebaf626` | obs-record --target screen passes IPv4, host:port, private suffixes and drive paths | D-18 kickoff delta widening the --target hygiene screen classes |
| `2026-10-19-check-obs-vacuous-dir-6d79f3f5` | check-obs.sh passes when entries or archive exists but is unreadable | Exit 2 in check-obs.sh scan_dir when a store directory is unreadable or unsearchable |

### B70. Prompt and behavioral eval harness fixes

- Bundle id: `ph-eval-harness`
- Owner: prompt hygiene (eval harness) (`specs/prompt-hygiene/`)
- Open fragments: 4
- Smallest change: Design deliberate headless skill injection, decode JSON before sentinel matching,
  scope the launch-pin guard out of eval sites, and share one tmux stub that catches later crashes.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-14-behavioral-pilot-injection-design-df835e81` | Behavioral pilot deferred: headless skill injection unavailable, needs a deliberate injection design | Design runner-side SKILL.md injection or SDK driver, then rerun the orchestrate pilot |
| `2026-07-14-eval-sentinel-json-escaping-ecc9d77c` | Sentinel grep -F over raw JSONL misses H1s with JSON-escaped characters | JSON-escape the H1 sentinel before grepping, or match via jq |
| `2026-07-22-launch-pin-scope-prompt-eval-bare-683025b7` | prompt-eval passes --bare; launch-pin guard must scope out eval harness sites | Exempt the prompt-eval harness site explicitly in the launch-pin guard |
| `2026-09-29-stub-crash-detection-e0adb3f6` | Behavioral-eval tmux stub misses skill crashes after the first anchor; inline stub copy diverged | Record the skill exit status in the stub and dedupe the inline copy onto the shared stub |

### B71. Drafting-time lens pass and new spec lens checks

- Bundle id: `re-drafting-time-lens`
- Owner: review effectiveness (`specs/review-effectiveness/`)
- Open fragments: 4
- Smallest change: Give spec-draft a reduced spec-lens pass before commit, with lens lines for
  ordering implied by selection, self-contradicting enumerations and detection derived from glosses.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-26-spec-mechanism-vs-incident-artifact-11bd17fe` | A REQ's detection mechanism was derived from a gloss and cannot detect its cited incident. | Add a kickoff lens item: verify a detection REQ against the cited incident's real artifact. |
| `2026-09-02-drafting-time-lens-gap-8dcf0f7c` | Kickoff lens pass found ~35 root causes in a bundle validate passed; spec-draft runs a light pass only. | Add a reduced drafting-time lens set or validator checks for orphan REQs and unnamed knobs. |
| `2026-09-18-bounded-selection-ordering-0299c9fa` | A bounded selection rule implies an ordering the spec must state | Add a spec-lens check: bounded selections state their ordering or say it is free |
| `2026-09-18-requirement-self-enumeration-7c83417d` | A requirement contradicted its own enumeration; a lens check would catch it | Add a spec-lens check: read each requirement against its own enumeration |

### B72. Where review audits and research datasets live

- Bundle id: `re-review-artifact-storage`
- Owner: review effectiveness (`specs/review-effectiveness/`)
- Open fragments: 4
- Smallest change: Write polish audits to an ignored scratch home workers may write, keep cited
  research datasets in a durable location, and let workers run corpus refresh and replay.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-11-polish-audit-run-files-74395a99` | Numbered polish-audit-N.md files are not gitignored and trip the dirty-tree pre-flight | Ignore .claude/polish-audit*.md in .gitignore |
| `2026-10-11-research-datasets-not-kept-2e04639d` | A cited research seed kept datasets only in a lost scratchpad | Require research notes to commit datasets or the regenerating commands beside the note |
| `2026-10-31-corpus-refresh-worker-run-9b382af6` | Corpus refresh and baseline replay are operator-only, forcing a second dispatch | Amend review-effectiveness to let a worker run refresh and replay when product list and spend grant exist |
| `2026-11-04-polish-audit-path-denied-82b9bba0` | polish writes its audit to worktree .claude/, which fleet workers are denied | Name a scratch-root audit path for dispatched runs in polish and self-review, read by /resume |

### B73. Guard review rigor lessons and swallowed-signal check

- Bundle id: `re-review-lessons`
- Owner: review effectiveness (`specs/review-effectiveness/`)
- Open fragments: 4
- Smallest change: Record the guard-lexer and fuzz-potency lessons in review doctrine and add
  check:swallowed plus a lens line for detached success signals.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-14-vacuous-fuzz-proves-nothing-af6048cb` | A random-token fuzz with zero exec-capable inputs proved nothing; measure input potency | Land REQ-A1.4 doctrine: measure how many sweep inputs could fail |
| `2026-09-14-worker-guard-awk-lexer-bypass-3ed95276` | Hand-written awk lexer in worker guard had four bypasses its own suite missed | Land REQ-B1.9 guard-review rule; prefer narrow allowlists over partial lexers |
| `2026-09-14-worker-guard-blessed-screen-blindspots-15a7fdcb` | Blessed-screen replacement still had two exec holes from reading the deciding char in strings | Land REQ-B1.3 sibling sweep; screens must skip strings and continuations |
| `2026-09-18-success-signal-detached-b7d3e2a1` | Seven success signals were detached from what they claimed; propose check:swallowed and a lens line | Land REQ-C1.4 checklist line; extend shell rules beyond pipe-status to swallowed forms |

### B74. Merges racing the release PR

- Bundle id: `rh-release-merge-race`
- Owner: release hardening (`specs/release-hardening/`)
- Open fragments: 4
- Smallest change: Re-arm proposals after a merge lands during or after the release PR, and stop a
  following merge from cancelling the release commit CI.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-02-release-guard-toctou-6f4900e9` | Release PR merging after the guard step lets release-please regenerate the bogus bootstrap proposal. | Re-check the window after the proposal step and fail the job if it opened mid-run. |
| `2026-09-02-release-please-pending-run-cancel-10244b4d` | Concurrency group queue depth is one; a middle merge loses its proposal with no re-arm lever. | Add a workflow_dispatch trigger and correct the queue comment. |
| `2026-09-02-release-skip-can-drop-work-c2afd203` | Window guard can drop a feat commit merged just before the release PR; nothing re-triggers. | Same post-proposal re-check plus a workflow_dispatch recovery trigger. |
| `2026-09-28-release-ci-cancelled-by-next-merge-33b7c53d` | A merge right after the release PR cancels the release commit CI run, locking the window | Key the main CI concurrency group per SHA, or have release-publish detect and rerun a cancelled run |

### B75. Untagged-window guard in workflow and template

- Bundle id: `rh-untagged-window`
- Owner: release hardening (`specs/release-hardening/`)
- Open fragments: 4
- Smallest change: Distinguish no tags from unreadable tags, put the window guard in the template,
  and align the spec with the workflow skipping only the proposal step.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-30-release-please-bootstrap-race-fd6c2f4f` | release-please bootstraps a bogus release PR in the untagged window | Add stale-changelog-entry sanity check; investigate dropping bootstrap-sha (window gate already landed) |
| `2026-09-02-release-guard-skips-step-not-job-571fa0d3` | Spec says the guard skips the job; the workflow skips only the proposal step. | Amend REQ-H1.1, D-13 and Task 9 to the step-level skip, or gate the job. |
| `2026-09-02-release-tagless-skip-forever-81c99b98` | No-tags and unreadable-tags both map to window open, suppressing proposals silently forever. | Distinguish a git tag -l failure as exit 2 in rl_latest_release_tag and the window check. |
| `2026-09-02-release-template-guard-gap-5ba1bbde` | The release-please template lacks the untagged-window guard the live workflow has. | Port the window guard into templates/release-please with the bring-your-own-core note. |

### B76. Tower-queue harness, subject and reply hook fixes

- Bundle id: `tc-tower-queue-fixes`
- Owner: tower comms (`specs/tower-comms/`)
- Open fragments: 4
- Smallest change: Share one test harness and field maps, keep --subject on a fresh store, and make
  the reply hook honour agent_type, sanitize stored text and skip the lock wait.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-15-hook-lock-wait-on-prompt-latency-a0f0b88b` | Reply hook waits up to 2s for the fleet lock inside prompt submit, buying nothing | Lower the hook-side lock wait or detach the log write |
| `2026-09-15-hook-prompt-source-and-c1-render-9bb22f14` | Reply hook ignores agent_type; stored prompt text keeps C1 so readers must sanitize | Read agent_type in the hook and sanitize stored text on output |
| `2026-09-16-tower-queue-harness-duplication-82f8272b` | Four tower-queue tests copy one harness; tower-queue.sh duplicates is_uuid, field maps and enums | Move the harness to tests/lib and dedupe the helpers in tower-queue.sh |
| `2026-10-30-tower-queue-add-subject-before-rebuild-dfb0fd0a` | add --subject on a fresh store drops the subject because the rebuild registers the item first | Apply --subject to an item the rebuild just registered instead of reporting already queued |

### B77. Fixture process reaping and sandbox safety

- Bundle id: `tt-test-fixture-reaping`
- Owner: test throughput (`specs/test-throughput/`)
- Open fragments: 4
- Smallest change: Make the reaper survive the spawner, guard EXIT traps in background children,
  move ps sweeps onto fixture-procs, and release inherited gate-lock fds.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-14-streamjson-leak-survives-teardown-fix-47e24470` | Supervisor leak recurs when a suite run is killed; reaper dies with the spawner | Add a sweep reaping processes whose fixture sandbox root no longer exists |
| `2026-10-04-bash-exit-trap-runs-in-forked-child-f2e85ede` | A TERMed fresh background child runs the parent EXIT trap and can delete the suite sandbox | Sweep tests for EXIT-trap cleanup beside kill of a fresh child, or guard trap helpers by pid |
| `2026-10-05-fleet-stop-sj-orphan-holds-gate-lock-b11f14ac` | A failing fleet-stop-sj run left fixtures holding the host gate lock fd for 40+ minutes | Kill the fixture process group on failure and close the lock fd before tests (flock -o) |
| `2026-10-05-test-reap-duplication-226cedca` | Five test files carry their own scratch-path ps sweep instead of tests/lib/fixture-procs.sh | Move the five cleanup copies onto tests/lib/fixture-procs.sh |

### B78. Test pool directory screen and reclaim hang

- Bundle id: `tt-test-pool`
- Owner: test throughput (`specs/test-throughput/`)
- Open fragments: 4
- Smallest change: Share one pool-directory screen refusing group or world writable dirs and
  honouring ACLs, and fix the reclaim hang on dead tickets.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-30-test-pool-loose-mode-5b9a8301` | Test pool accepts a user-owned but group- or world-writable pool directory | Refuse or tighten a loose-mode pool directory in D-3 |
| `2026-10-04-run-tests-pool-reclaim-hang-6ed98940` | test-run-tests-pool reclaim case hangs with waiters spinning on dead tickets on this host | Debug why pooled waiters never reclaim dead tickets that a fresh process reclaims at once |
| `2026-10-07-pool-dir-screen-duplicated-14f02669` | step-pool.sh and run-tests.sh carry copies of the pool-directory screen that already diverge | Extract one sourced pool-directory screen used by step-pool.sh and run-tests.sh |
| `2026-10-07-test-pool-acl-write-35f87a8a` | run-tests.sh pool screen ignores macOS ACLs that step-pool.sh refuses | Shared pool screen refuses ACL-carrying directories for run-tests.sh too |

### B79. awk dialect differences swept and documented

- Bundle id: `ub-awk-portability`
- Owner: universal binary (portability and spawn cost) (`specs/universal-binary/`)
- Open fragments: 4
- Smallest change: Sweep scripts for busybox dynamic ERE, exit status and mawk longest-match
  differences, and document the awk ENVIRON rule.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-03-awk-exit-2-not-portable-3f14b24d` | busybox awk exits 1 on unreadable files, so case-on-$? error channels collapse. | Sweep case-$? awk/helper sites to test readability separately, as journal_close now does. |
| `2026-09-24-macos-ci-gap-5de6ed09` | CI was ubuntu-only; macOS/Alpine suites landed (e4c36561 #688) but no doc states the awk ENVIRON rule | State the awk portability rule (pass multi-line values via ENVIRON, never -v) in a doctrine or docs page |
| `2026-10-25-busybox-awk-unbalanced-ere-c6c412bb` | busybox awk accepts unbalanced dynamic EREs silently; retired-phrasings fixed, other scripts unswept | Sweep scripts/ for awk dynamic regexes relying on awk to refuse malformed patterns |
| `2026-10-31-awk-greedy-alternation-b6e5b1b2` | mawk does not take longest match for ^.*(alt) with a bracket class; other scripts unswept | Sweep scripts/ awk for the ^.*(alt) idiom and cut one leftmost match at a time |

### B80. Adopt bounded-run for deadlines and timeout gaps

- Bundle id: `ub-bounded-run`
- Owner: universal binary (portability and spawn cost) (`specs/universal-binary/`)
- Open fragments: 4
- Smallest change: Fix bounded-run residuals, use it for per-file deadlines on every platform and in
  flight-sweep and check-hook-contracts, and fit the deadline under the CI shard timeout.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-19-bounded-run-residuals-a6aa0e60` | bounded-run.sh residuals: subreaper orphans escape KILL, stray sleeps, untested fallbacks | Use a process group on setsid-capable hosts and add host-independent fixtures |
| `2026-10-19-guards-need-timeout-binary-48f1c5a9` | flight-sweep and check-hook-contracts still need timeout; macOS has none, so their reads run unbounded | Route flight-sweep.sh and check-hook-contracts.sh through scripts/bounded-run.sh when no timeout binary exists |
| `2026-11-01-test-deadline-platform-gaps-9e55a84a` | Per-file deadline absent on macOS and partial on busybox; bounded-run would fix it | Amend D-21 and REQ-D1.4 to use bounded-run.sh where no timeout exists |
| `2026-11-01-test-deadline-vs-ci-job-timeout-366c0097` | Per-file deadline 900s exceeds the 15-minute CI shard timeout, so hangs lose their FAIL | Lower the deadline default toward per_file_seconds or lengthen the shard job timeout |

### B81. Static allow rules that launder writes

- Bundle id: `wpe-static-allow-rules`
- Owner: the worker-permission-ergonomics amendment seed
  (`specs/_pending/worker-permission-ergonomics-amendment.md`)
- Open fragments: 4
- Smallest change: Narrow static git allows to exclude --output, --no-index, branch -D/-f, push
  --receive-pack/--exec/--delete, and stop auto-approving argv-running scripts.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-05-worker-profile-static-git-write-forms-199450d4` | Static worker allow rules for git diff/log/show/branch admit --output writes and branch -D/-f | Narrow the static git rules or route them through the worker guard |
| `2026-10-08-worker-guard-argv-blind-script-trust-c4ffd0df` | Worker guard auto-approves any scripts/*.sh, so argv-running scripts launder denied commands | Defer argv-running scripts or screen words after --, and distrust scripts the branch created |
| `2026-10-10-worker-profile-static-git-diff-no-index-a961874c` | Static git diff rule admits --no-index, printing any readable file past the guard | Narrow or deny git diff --no-index in the worker profile static rules |
| `2026-11-01-worker-profile-push-exec-forms-5408541c` | Static git push allows admit --receive-pack/--exec and --delete; nothing refuses them | Refuse push --receive-pack, --exec and deletion forms in policy-guard and the deny floor |

### B82. docs/overlays.md accuracy and confinement rule

- Bundle id: `co-overlays-doc`
- Owner: customization overlay and config resolution (`specs/customization-overlay/`)
- Open fragments: 3
- Smallest change: Correct the malformed-value degradation sentence, document overlay path
  confinement, and retarget REQ-C1.3 from review_sequence to the convergence list.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-07-malformed-degrade-target-54457c6f` | overlays.md says malformed values degrade to the next lower layer; resolve-config-knob.sh says core default | Reconcile docs/overlays.md degrade table with resolve-config-knob.sh behaviour |
| `2026-09-24-customization-overlay-runnable-instance-2f71ba54` | REQ-C1.3 names review_sequence as the runnable instance; boundary doc names the convergence list | Retarget REQ-C1.3 to the convergence point's list |
| `2026-09-24-overlays-doc-path-confinement-9a4e5e83` | docs/overlays.md omits overlay path confinement; rule lives only in guard-catalog doctrine and a script header | Add the path-confinement rule to docs/overlays.md section 4 beside the by-layer table |

### B83. Read the dispatch base once from the remote default branch

- Bundle id: `coc-dispatch-base-resolution`
- Owner: concurrent orchestrator coordination (`specs/concurrent-orchestrator-coordination/`)
- Open fragments: 3
- Smallest change: Resolve the base commit once per dispatch from the remote HEAD branch and pass
  that SHA to the freshness gate, worktree creation, merge detection and dispatch-fetch.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-06-dispatch-gate-base-drift-9d490aa5` | Freshness gate and worktree base read origin/main at different moments | Have dispatch-fetch print the SHA, read the brief at it, pass it as --base |
| `2026-10-07-default-branch-outside-gate-201a1004` | Merge detection and tmux worktree base still read origin/main by name, not the remote HEAD branch | Route orchestrate-state.sh and fleet-dispatch-worktree.sh through dispatch-fetch.sh default_ref |
| `2026-10-07-fetch-anchor-ref-reads-e9fafa61` | dispatch-fetch.sh reads each bundle file by ref name, so a concurrent fetch can mix commits | Resolve the ref to a commit SHA once in anchor_at_ref and git show every file at it |

### B84. Backend ladder: session-grade adapters and hidden CLI flags

- Bundle id: `eb-backend-ladder-design`
- Owner: execution backends (`specs/execution-backends/`)
- Open fragments: 3
- Smallest change: Decide in an execution-backends amendment whether session-grade adapters and the
  --bg flag join the ladder, and record the hidden --permission-prompt-tool dependency.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-23-full-session-pluggable-ladder-c83d930d` | Should full-session selection include pluggable session-grade adapters | Decide in an amendment whether full-session walks pluggable adapters |
| `2026-07-23-headless-bg-flag-b48fa0a1` | CLI --bg flag could make headless one-shots first-class claude agents rows | Research --bg result capture once the flag stabilizes |
| `2026-07-23-streamjson-prompt-tool-flag-hidden-b4f695d6` | --permission-prompt-tool hidden from CLI help; supervisor depends on it | Add a launch-time capability probe for the flag in fleet-streamjson.sh |

### B85. Drain manual lane and malformed gates

- Bundle id: `fg-drain-gates`
- Owner: format grammar and parser unification (`specs/format-grammar/`)
- Open fragments: 3
- Smallest change: Carry the drain manual-verification section into --bookkeeping and
  accumulator-taxonomy, and fix the malformed GATE() lines at the next model-allocation kickoff.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-26-drain-manual-lane-bookkeeping-82b59dca` | /orchestrate --bookkeeping drops the drain manual-verification section /drain shows. | Add the manual inventory to the bookkeeping pass list in orchestration-modes. |
| `2026-08-26-taxonomy-manual-lane-undocumented-a678d2a5` | accumulator-taxonomy does not describe the drain report's manual verification section. | Describe the manual verification section in accumulator-taxonomy. |
| `2026-09-11-malformed-gates-cost-an-anchor-11f61a8f` | Two model-allocation gates are malformed GATE() prose; fixing costs a re-anchor, so fold into next kickoff | Drop the GATE() wrapper on both entries at the next model-allocation re-walkthrough |

### B86. spec-model record parsing gaps

- Bundle id: `fg-spec-model-parse`
- Owner: format grammar and parser unification (`specs/format-grammar/`)
- Open fragments: 3
- Smallest change: Emit one TEST record per cited REQ, keep wrapped Citations continuations, and
  anchor record labels so prose lines are not read as labels.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-25-test-spec-multi-req-heading-a682c3fc` | spec-model emits one TEST record per heading (first REQ only); the validator counts every REQ. | Decide record shape, then use spec_parse_req_tokens in spec-model parse_test_spec. |
| `2026-09-22-spec-model-citations-continuation-8131215d` | spec-model.sh drops wrapped Citations continuation lines, losing ids for onepager and scope | Accumulate the Citations bullet across continuation lines in spec-model.sh |
| `2026-11-03-brief-prose-class-label-da1f33ac` | A prose line starting Class: was read as a second record label, making the entry unparseable | Have spec-validate.sh run the --record parse and error on duplicate labels |

### B87. Stop paths that force-break live journal holders

- Bundle id: `flc-stop-paths`
- Owner: fleet lifecycle closure (`specs/fleet-lifecycle-closure/`)
- Open fragments: 3
- Smallest change: Stop force-clearing a held journal lock on stop and close, and record the repo
  root a headless stop needs, with a distinct exit for an unresolvable share.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-10-journal-lock-soundness-residuals-d45387c2` | Journal lock residuals; still live: stop force-breaks a live journal holder, and a wedged attention call | Make close/release_locks coordinate with a live journal holder instead of force-breaking |
| `2026-09-14-streamjson-close-quiesce-bf59017f` | stream-json close force-clears the journal lock while a third-party writer may hold it | Refuse close while a journal holder is live, or wait a bounded budget then force |
| `2026-09-24-headless-stop-from-registry-0692779d` | Headless stop needs a repo root the registry record lacks; unresolvable shares exit 2 with no-such-worker | Accept a validated --state-dir on headless stop and give unresolvable its own exit code |

### B88. Pre-commit markdown lint parity and merge commits

- Bundle id: `flight-precommit-hooks`
- Owner: a spec-less flight (`flight`)
- Open fragments: 3
- Smallest change: Run markdownlint including MD013 on staged files in pre-commit, and limit adopter
  hook linting to files changed by the commit on merge commits.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-19-spec-draft-lint-gap-eca7625e` | /spec-draft committed a bundle with a markdownlint error caught only at kickoff. | Add a staged-path markdownlint job to lefthook pre-commit, which also covers spec-draft commits. |
| `2026-08-26-precommit-markdown-lint-4683c7a9` | MD013 is enforced only by check/CI, not pre-commit, so prose edits red CI. | Add a staged-path markdownlint job to lefthook pre-commit. |
| `2026-11-05-precommit-hooks-on-merge-main-82612b46` | Adopter pre-commit hooks lint all of main on a merge-of-main commit and fail | Document a hook pattern that lints only the branch's own diff on merge commits |

### B89. Fleet-messaging expression amendment

- Bundle id: `fm-spec-amendment`
- Owner: fleet messaging (`specs/fleet-messaging/`)
- Open fragments: 3
- Smallest change: Narrow the tmux identity row now owned by fleet-hardening and refresh the stale
  floor and rejected-alternative sentences.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-04-fleet-messaging-tmux-identity-owner-2fa9088c` | fleet-messaging tmux identity row is now owned by fleet-hardening and should narrow | Narrow fleet-messaging tmux row at its next delta walk to consume the fleet-hardening export |
| `2026-10-11-floor-doc-inbox-class-prose-59393a5f` | Two fleet-coordination-floor sentences went stale after the inbox-socket class was added | Spec amendment allowing the two sentences to be updated, then fix them |
| `2026-10-26-ci-cli-above-messaging-floor-b4bf7986` | CI CLI moved above the messaging floor, so a rejected-alternative argument's version half is stale | Drop the CI-below-floor reasoning from fleet-messaging design.md and test-spec.md |

### B90. Doctrine index, manifest and paraphrase drift guards

- Bundle id: `gc-doctrine-guards`
- Owner: guard coverage (`specs/guard-coverage/`)
- Open fragments: 3
- Smallest change: Extend check-doctrine-index to the citations column, add builder to
  doctrine-manifest surfaces, and flag skill paraphrases of renamed doctrine terms.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-27-doctrine-reword-skill-straggler-8fa65f3f` | Nothing catches a skill paraphrase drifting when its doctrine term changes. | Add a convention or guard: skills name doctrine terms rather than paraphrasing triggers. |
| `2026-09-02-doctrine-index-citation-drift-587d7d7b` | check-doctrine-index checks only row-file bijection, never the citations column. | Diff each index row's citation cell against its doc's Citations line. |
| `2026-09-23-doctrine-manifest-builder-768ee83e` | check:doctrine-manifest DEFAULT_SURFACES omits builder, which cites interaction-style | Add builder to DEFAULT_SURFACES in check-doctrine-manifest.sh |

### B91. Githooks rewrite policy, boundaries and path drift

- Bundle id: `hg-githooks-wiring`
- Owner: human gates (policy guard and sign-off) (`specs/human-gates/`)
- Open fragments: 3
- Smallest change: Make pre-rebase and prepare-commit-msg honour unpushed_rewrite, cover cherry-pick
  and am in commit-msg checks, and re-wire relative hooksPath after worktree creation.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-22-commit-msg-hook-layer-boundary-2076522e` | commit-msg hook does not fire on cherry-pick or git am | Ship applypatch-msg hook and document the cherry-pick boundary |
| `2026-10-01-githooks-ignore-unpushed-rewrite-527c973e` | githooks pre-rebase and prepare-commit-msg refuse every rewrite regardless of unpushed_rewrite | Have the backstop read the knob, or document it as the stricter layer |
| `2026-10-25-claude-code-rewrites-hookspath-587db6e6` | Claude Code rewrites relative core.hooksPath to absolute when it creates worktrees; native worktrees still drift | Report upstream and re-wire githooks at session start in skill-opened worktrees |

### B92. Orchestrate skill at zero headroom

- Bundle id: `ih-orchestrate-diet`
- Owner: instruction-budget headroom (`specs/instruction-headroom/`)
- Open fragments: 3
- Smallest change: Factor the shared freshness-gate prose out of orchestrate and execute-task into
  doctrine to restore orchestrate headroom.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-19-skill-headroom-ceiling-6ee8bb6f` | execute-task and orchestrate at per-file ceiling; shared freshness-gate prose could factor out | Factor the shared freshness-gate prose into a doctrine section both skills cite |
| `2026-07-23-orchestrate-skill-budget-headless-ff91ed4e` | No room in orchestrate for a headless-oneshot backend pointer | Restore a one-line per-backend pointer when the orchestrate diet lands |
| `2026-07-23-orchestrate-skill-budget-zero-headroom-5acc5668` | orchestrate SKILL.md at zero headroom; deferred diet now blocks work | Diet orchestrate SKILL.md to its 2x target, relocating mechanics to point-of-use doctrine |

### B93. Section-granular doctrine manifests and shared includes

- Bundle id: `ih-section-manifests`
- Owner: instruction-budget headroom (`specs/instruction-headroom/`)
- Open fragments: 3
- Smallest change: Charge doctrine by section through section-granular manifests, add a shared skill
  include, and make trims manifest-aware so last-copy rules are caught.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-18-cross-skill-convention-budget-collision-bae4922f` | No shared skill include; cross-skill rules charge every at-ceiling skill | Add a shared-convention include for skills or an at-ceiling headroom policy |
| `2026-09-09-doc-granular-manifests-root-cause-ebc0399c` | Whole-file doctrine manifests cause both budget symptoms; section-granular manifests would fix orchestrate | Scope section-granular manifests in a headroom amendment |
| `2026-09-13-trim-dropped-fifteen-rules-f03a7e23` | A pure-dedupe trim dropped fifteen last-copy rules; only a manifest-aware lens caught it | Check each trim deletion against per-skill manifest closures before taking it |

### B94. Inception helper consolidation and bundle lock

- Bundle id: `in-helpers`
- Owner: inception (`specs/inception/`)
- Open fragments: 3
- Smallest change: Move inception's resolver, date pin, classifiers, writers and lock path into one
  sourced helper that takes the bundle lock and handles a .git file.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-18-inception-awk-date-helpers-f1b5ddb1` | Inception scripts carry separate awk date and kill-criteria classifiers | Ship one sourced awk snippet for date_ok, days and kill-criteria classification |
| `2026-10-25-inception-bundle-lock-coverage-c42731fb` | Several inception writers and the registry rewrite skip the bundle lock; lock path wrong when .git is a file | Take the bundle lock in venture-task, mark-phase and registry rewrite; resolve lock via git-dir |
| `2026-10-25-inception-shared-helper-lib-c5c81122` | Inception helpers each copy resolver, date pin, writers and lock path, already diverging | Extract a sourced inception helper lib and switch the three helpers to it |

### B95. Inception text: coverage risks, evidence tokens, fan-out gate

- Bundle id: `in-skill-text`
- Owner: inception (`specs/inception/`)
- Open fragments: 3
- Smallest change: Settle the coverage-risk entry form, adopt the pinned evidence tokens in
  doctrine, and list Gate 2 escalations once instead of per seat.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-22-inception-coverage-risk-form-2c2ab68e` | Coverage risks reuse A-entry form; Task 9 should confirm or add a variant | Confirm the coverage-risk entry form in the persona fan-out task |
| `2026-07-22-inception-ladder-coupling-b9844e2a` | Evidence-ladder tokens pinned; evidence-quality doctrine must adopt them exactly | Check the evidence-quality doctrine uses the five ladder tokens and none convention |
| `2026-10-18-fanout-gate2-volume-67ac44df` | Fan-out Gate 2 lists escalations per seat, repeating the same calls | Group Gate 2 escalations by decision in inception-fanout.sh gate2 once dogfood confirms |

### B96. Inception inputs nothing consumes

- Bundle id: `in-unconsumed-inputs`
- Owner: inception (`specs/inception/`)
- Open fragments: 3
- Smallest change: Route inception observations through obs-record --target and retire the local
  drop, and add a reader for the venture proposals directory.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-19-inception-drop-consumption-ffaa611c` | The inception observation drop has no consume step, so every draft re-mines the same entries | Add a drop-consume verb, or retire the drop by routing to obs-record --target (see 0e8630db) |
| `2026-10-19-inception-drop-obs-targets-0e8630db` | Ruling: route inception observations through obs-record --target and retire the machine-local drop | Spec delta to inception routing observations through obs-record --target; retire drop/drop-read |
| `2026-10-25-inception-proposals-reader-d49dd7ff` | Nothing reads the venture proposals/ directory, so outside-agent proposals land silently | List proposals/ in /inception resume and handoff, and in the layout table |

### B97. Mission control with a layer rendered by another tool

- Bundle id: `mc-adopter-layer-handover`
- Owner: mission control (`specs/mission-control/`)
- Open fragments: 3
- Smallest change: Allow first run and revert hand-over when another tool renders the adopter layer,
  logging a hand-over outcome, and keep program names out of public key names.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-11-04-mc-revert-managed-layer-3ce1702c` | A revert handed over to another tool's layer is logged as failed with no hand-over outcome | Add a handed-over outcome to mc-kb.sh revert and accept it via --outcome |
| `2026-11-05-mc-first-run-rendered-layer-deadlock-aa515ef9` | First run deadlocks when another tool renders the adopter layer; no launch without a program | Amend mission-control with a bootstrap launch, or print a paste-ready hand-off brief on exit 4 |
| `2026-11-05-mc-program-name-in-key-names-2d2b7c45` | Program names embedded in key names leak through public templates | Add a slot-keyed program config form where program names live only in values |

### B98. Mission-control merge and flip powers

- Bundle id: `mc-guard-tier-powers`
- Owner: mission control (`specs/mission-control/`)
- Open fragments: 3
- Smallest change: Amend never-merge for a kill-switched class merge helper, narrow the guard tier's
  flip scope, and report each waiting class PR once per head.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-26-mc-flip-scope-narrower-279d8ddd` | Mission-control guard tier may flip any PR in its repo under unit-owner policy | Restrict the mission-control flip to planwright task or flight branch heads, or launcher-registry PRs |
| `2026-11-05-mc-class-merge-caller-d0274d5c` | Amend never-merge to let mission control call the class merge helper under a kill switch | Amend REQ-I1.1 and add a task wiring the class merge caller, kill switch and release watcher |
| `2026-11-05-mc-class-wait-reports-a845aa5b` | Report each class PR waiting on approval once per head and re-evaluate on sweep | Add the once-per-head waiting report to the class-merge caller task |

### B99. Mission-control scripts shared library and budget

- Bundle id: `mc-scripts-shared-lib`
- Owner: mission control (`specs/mission-control/`)
- Open fragments: 3
- Smallest change: Share one program-home and lease reader across mc scripts, count unreadable load
  as pressure, and add a soft spend dimension to mc-budget.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-26-mc-host-load-unread-is-idle-f8cb8d43` | mc-budget counts an unreadable host load as 0 instead of pressure | Read unreadable load as at-limit with a warning, behind a testable load-source seam |
| `2026-10-27-mc-lib-shared-helpers-ea11bd32` | mc scripts each carry their own program-home resolver and lease reader | Move the program-home resolver and lease reader into mc-lib.sh |
| `2026-11-05-mc-budget-dollar-dimension-af17332a` | Operator asks for a soft monthly dollar cap; mc-budget has no spend dimension | Amend mission-control with a spend budget dimension and a pluggable usage source |

### B100. Shared fixture-backed shell lexer for command guards

- Bundle id: `newspec-command-guard-lib`
- Owner: a new spec: shared command-guard lexer (`new-spec`)
- Open fragments: 3
- Smallest change: New spec for one fixture-backed shell lexer shared by tower and worker command
  guards, replacing duplicate tokenizer engines and their comparison quirks.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-19-command-guard-engine-dup-30159d5c` | tower and worker command guards duplicate a security-critical tokenizer engine | Extract a shared scripts/command-guard-lib.sh sourced by both guards |
| `2026-07-28-awk-redirect-vs-relational-screen-026930ca` | Command-guard awk screen over-defers relational &gt; comparisons | Add a small awk lexer in the shared command-guard library |
| `2026-10-31-guard-lexer-review-yield-47e8a423` | Hand-rolled shell lexers in guards take many review rounds; share one fixture-backed lexer | Extract one shared fixture-backed shell lexer for check-test-vacuity, echo-discipline and cdpath |

### B101. Lighter, more didactic drafting and kickoff

- Bundle id: `od-drafting-kickoff-weight`
- Owner: operator dialogue (`specs/operator-dialogue/`)
- Open fragments: 3
- Smallest change: Amend drafting and kickoff to teach to the frontier (drop probe Socratically),
  probe instrument capability in drafting, and lighten the walk.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-04-skill-drift-6591d9b1` | spec-kickoff still says probe Socratically, contradicting teach-to-the-frontier doctrine. | Replace the auditor-mode verbs with the interaction-style frontier wording; fix missing eval fixtures cite. |
| `2026-11-04-drafting-kickoff-too-heavy-c52287be` | Operator: spec drafting and kickoff are too heavy, not didactic enough; recurring complaint | Triage into an operator-dialogue amendment lightening spec-draft and spec-kickoff turns |
| `2026-11-04-kickoff-lens-found-drafting-gaps-8f63a493` | Kickoff lenses found 31 gaps in a measurement spec; drafting never probed instrument capability | Add a spec-draft step probing what each named instrument measures and what state runs touch |

### B102. Fetch hang guards and ssh BatchMode residuals

- Bundle id: `pending-fetch-hang-guards`
- Owner: the currency-posture seed brief (`specs/_pending/currency-posture-and-drifts.md`)
- Open fragments: 3
- Smallest change: Set GIT_TERMINAL_PROMPT=0 and BatchMode on fetches without breaking agent
  approvals, honour GIT_SSH and non-OpenSSH commands, and give the note line its own failure shape.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-24-converge-sync-batchmode-agent-c0d18822` | Forced BatchMode fetch fails when the ssh agent needs an interactive approval | Detect agent-approval failure and say so, or allow an opt-out of BatchMode |
| `2026-09-24-converge-sync-ssh-command-gaps-1fa02012` | ssh-command residuals: GIT_SSH ignored, non-OpenSSH commands, note line shares failure shape | Give the note line a distinct shape; consult GIT_SSH or refuse non-OpenSSH commands |
| `2026-09-24-main-currency-no-prompt-guard-dc685bf3` | main-currency.sh lacks GIT_TERMINAL_PROMPT=0 and ssh BatchMode, so a tower fetch can block on a prompt | Set GIT_TERMINAL_PROMPT=0 and BatchMode=yes in main-currency.sh as converge-sync-main.sh does |

### B103. Lens fan-out reporting, clustering and hermetic probes

- Bundle id: `re-lens-fanout-mechanics`
- Owner: review effectiveness (`specs/review-effectiveness/`)
- Open fragments: 3
- Smallest change: Give lens agents a writable report channel, add a cluster-by-root-cause step, and
  run read-only probes in a throwaway copy.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-25-kickoff-lens-dedup-19ec8cd4` | Kickoff lens fan-out yields heavy cross-lens duplicates with no cluster-by-root-cause step. | Add a cluster-by-root-cause merge step and clustered disposition shape to discovery-rigor. |
| `2026-09-22-lens-fanout-report-channel-c10c0a24` | Read-only lens agents could not write report files; 130 raw findings needed clustering | Name the hand-back as report channel; add a root-cause clustering step (REQ-B1.4) |
| `2026-10-07-lens-probe-side-effects-9f2fb326` | Read-only lens probes ran seam scripts that wrote into the checkout under review | Lens brief names the hermetic route: fixture repo in scratch, state-dir env, no origin |

### B104. Awaiting-input notes v2 bundles cannot hold

- Bundle id: `sr-awaiting-input-v2`
- Owner: skill rigor (`specs/skill-rigor/`)
- Open fragments: 3
- Smallest change: Change kickoff, polish and self-review park arms to write task-reference bullets
  in v2 bundles and clear zone-finding parks on merge.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-26-skill-drift-5756e0af` | Parking a zone finding to Awaiting input leaves a stale bullet after merge | Exempt zone findings already on a pending-sign-off PR from parking |
| `2026-09-03-skills-awaiting-input-note-wording-84f076ea` | spec-kickoff, polish, self-review record a note in Awaiting input the validator rejects. | Name the Task-reference-bullet form in the three skills, as execute-task does. |
| `2026-09-24-skill-drift-88953874` | spec-kickoff degradation arms write an Awaiting input note that a v2 bundle cannot hold | Give v2 a conformant home for bundle-level parks and update spec-kickoff and interaction-style |

### B105. Skill text drift: dispatch gates, degrade arms, research log

- Bundle id: `sr-skill-text-drift`
- Owner: skill rigor (`specs/skill-rigor/`)
- Open fragments: 3
- Smallest change: Read bundle-level dispatch gates, add a no-sub-agent degrade arm to self-review,
  move execute-task research to a trailing log, and name every halt class.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-26-execute-task-blind-to-dispatch-gate-5893ec60` | No skill reads a bundle-level dispatch gate written in tasks.md intro prose. | Make it a structured tasks.md field read by the selector, or surface it in execute-task pre-flight. |
| `2026-08-26-skill-drift-7da1eedb` | Self-review has no documented degrade arm for hosts forbidding sub-agent dispatch. | Add a degrade line: inline walk plus self-critique, declared in the pass summary. |
| `2026-09-03-skill-drift-9124476b` | Skill puts research in the signed risk register; briefs use a trailing research log. | Point the skill at the trailing Execution research log section. |

### B106. Tower-front-door expression amendment

- Bundle id: `tfd-spec-amendment`
- Owner: tower front door (`specs/tower-front-door/`)
- Open fragments: 3
- Smallest change: Give flight-boundary and re-route rules D-IDs and REQs, and fix collision-free
  and ready-flip wording to match the build.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-02-specless-rules-without-d-ids-64a37594` | Flight-boundary rules come from a REQ with no D-ID; mid-flight re-route rule has no REQ. | Mint a D-ID for the flight-boundary family and land the re-route rule as a REQ. |
| `2026-09-24-flight-collision-wording-a75f5e38` | D-11 calls flight ids collision-free by construction; docs credit uid plus create-or-fail | Reword D-11 at the next tower-front-door delta walkthrough |
| `2026-10-07-tower-front-door-spec-wording-f22a2e4c` | REQ-G1.4 ready-flip deny and D-14 allow-only wording disagree with the build | Kickoff delta rewording REQ-G1.4 test-spec and D-14/Task 10 deliverables |

### B107. Tower-placement deliverables and posture check currency

- Bundle id: `tp-placement-currency`
- Owner: tower placement (`specs/tower-placement/`)
- Open fragments: 3
- Smallest change: Drop the consumed observation citation, adopt fleet-hardening D-18's handshake,
  and make the posture step detect dead braced-root hooks.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-08-tower-about-two-specs-759826d8` | tower-placement Task 4 cites an observation tower-front-door already consumed for the _about edit | Re-derive tower-placement Task 4/8 _about and deny-list deliverables against main and name the owner |
| `2026-10-08-tower-posture-step-dead-hooks-a2230ae8` | Tower posture step judged dead braced-root hooks as wired and skips the policy guard | Resolve hook paths as a --settings session would and cover the policy guard in the step |
| `2026-10-10-tower-placement-handshake-superseded-c29675e0` | tower-placement D-8 single handshake spelling superseded by fleet-hardening D-18 | Add a supersede pointer from tower-placement D-8 to fleet-hardening D-18 |

### B108. Quadratic awk scans on hostile input

- Bundle id: `ub-awk-quadratic`
- Owner: universal binary (portability and spawn cost) (`specs/universal-binary/`)
- Open fragments: 3
- Smallest change: Cap or linearise json_input_object, frame_check and the shebang rule scan.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-28-frame-check-memory-e032ecc5` | frame_check gsub over the whole launch frame costs about 124x the frame in memory under mawk | Cap launch prompt size or replace the whole-line gsub with a cheaper frame check |
| `2026-10-19-streamjson-json-input-quadratic-4880ede2` | fleet-streamjson json_input_object walks envelopes char by char with no cap, quadratic on busybox awk | Rewrite json_input_object the linear way json_top_string was, or cap envelope size |
| `2026-10-31-script-invocation-sh-rule-quadratic-e6e8462b` | check-script-invocation shebang rule is quadratic in word length; crafted prose stalls CI | Rewrite the /sh/ awk block to scan each line linearly |

### B109. bash 3.2 and dash construct lints

- Bundle id: `ub-bash32-lints`
- Owner: universal binary (portability and spawn cost) (`specs/universal-binary/`)
- Open fragments: 3
- Smallest change: Lint command exec with redirection, bash-4-only builtins and non-ASCII quoted
  heredocs under dash.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-19-bash32-command-exec-unwind-2851a1cd` | bash 3.2 corrupts unwind after command exec N&lt;file in a function | Lint command exec with a redirection in check-bash32.sh |
| `2026-10-19-dash-quoted-heredoc-multibyte-07ad50fe` | dash leaks multibyte markers into non-ASCII quoted heredocs; four scripts still affected | Convert non-ASCII quoted heredocs in the four named scripts to printf or unquoted heredocs |
| `2026-10-25-bash32-mapfile-unguarded-b680f07c` | A mapfile call broke the guard on bash 3.2; parse check cannot see bash-4-only builtins | Extend check-bash32.sh to flag mapfile, readarray, declare -A, case-mod expansions and coproc |

### B110. Shared git and CI failure classifiers

- Bundle id: `ub-failure-classifiers`
- Owner: universal binary (portability and spawn cost) (`specs/universal-binary/`)
- Open fragments: 3
- Smallest change: Ship a tested classify-git-failure helper that tells corrupt refs from absent
  ones, and classify signal-killed CI runners as retryable.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-25-git-failure-classification-0cc0726d` | Scripts hand-roll git stderr classification; a tested classify-git-failure.sh would centralize it. | Add scripts/classify-git-failure.sh beside classify-ci-failure.sh and move main-currency.sh onto it. |
| `2026-09-12-classify-ci-failure-signal-kill-8cf058ce` | classify-ci-failure.sh treats a signal-killed runner ("no exit status") as logic, never retried | Add a runner-killed signature routed to the bounded-retry arm |
| `2026-09-24-ref-probe-corrupt-loose-ref-8cdc142a` | show-ref exit 1 cannot tell a corrupt loose ref from an absent one in flight-id resolve_bases | Stat the loose ref file under the common dir before trusting show-ref exit 1 |

### B111. Sanitizers mangle UTF-8 as C1 controls

- Bundle id: `ub-sanitizer-utf8`
- Owner: universal binary (portability and spawn cost) (`specs/universal-binary/`)
- Open fragments: 3
- Smallest change: Strip C1 as C2 80-9F sequences in sanitize_printable, replace inline C0 strippers
  with echo-safety, pad by display width, and validate session-file sids.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-23-status-view-sid-join-spoof-404d3b7b` | Worker session file can claim another sid and hide or misattribute it | Flag a sid claimed by more than one worker or cross-check cwd |
| `2026-09-18-spec-status-render-mojibake-40dc14ab` | spec-status renders an em dash as U+FFFD; sanitize_printable strips raw 0x80-0x9F | Detect C1 as the two-byte UTF-8 sequence in echo-safety.sh sanitize_printable |
| `2026-09-25-inline-sanitizer-drift-446e3f52` | Inline C0-only strippers multiply outside echo-safety.sh while the sanctioned-copy list names only two | Add a UTF-8-safe C1 strip to echo-safety.sh and move inline copies onto it |

### B112. Worker profile file-tool deny gaps

- Bundle id: `wpe-profile-denies`
- Owner: worker permission ergonomics (`specs/worker-permission-ergonomics/`)
- Open fragments: 3
- Smallest change: Deny worker Write and Edit on the allow-audit log and on guard scripts and
  defaults in the install root, and stop restating deny globs in _about.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-27-ctxeng-settings-about-prose-b75dc6d2` | worker/tower settings _about restate each deny glob in prose | Trim the per-glob walkthrough from _about into docs/overlays.md, keep posture text |
| `2026-11-01-worker-file-tools-reach-guard-scripts-a0347364` | Worker Edit/Write can modify its own guard scripts and defaults in a dev install root | Add Edit denies for the install root's scripts/ and config/ in worker-settings.json |
| `2026-11-03-worker-allow-audit-log-file-tools-ff4e3890` | Worker Write/Edit can truncate or forge the allow-audit log; no deny rule covers it | Add Edit(//**/allow-audit/*.log) deny to worker-settings.json with a path fixture row |

### B113. Protected-doc list fails open on new docs

- Bundle id: `co-protected-docs-default`
- Owner: customization overlay and config resolution (`specs/customization-overlay/`)
- Open fragments: 2
- Smallest change: Derive the protected-doc set from a declared marker or directory so new or split
  docs (custom-steps.md included) are protected by default.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-21-protected-docs-fails-open-8d2f1a63` | Protected-doc list is hardcoded and fails open; new or split docs are shadowable | Fail when a doctrine doc is in neither list; then invert the default |
| `2026-09-24-custom-steps-doc-unprotected-4871f107` | custom-steps.md carries human gates but is not in the protected doc set | Add custom-steps to PROTECTED_DOCS and the D-11 list |

### B114. Step-record screen placeholder and macOS digest dependency

- Bundle id: `cs-script-hardening`
- Owner: custom steps (`specs/custom-steps/`)
- Open fragments: 2
- Smallest change: Give step-record a distinct marker when the secret screen cannot run, and use a
  non-interpreter sha256 path on macOS.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-29-step-record-screen-shim-a4e118cb` | When the secret screen cannot run, every field shows the same withheld placeholder as a match | Use a distinct placeholder when the screen could not run |
| `2026-10-25-step-record-sha256-perl-5588599b` | step-record sha256 falls back to perl-based shasum on macOS, an interpreter dependency | Compute args-digest with git hash-object instead of sha256 tools |

### B115. Adapter capability probe and headless signal dispositions

- Bundle id: `eb-launch-hardening`
- Owner: execution backends (`specs/execution-backends/`)
- Open fragments: 2
- Smallest change: Bound adapter_caps output and time, and launch headless workers without inherited
  ignored HUP/INT/QUIT dispositions.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-22-adapter-invocation-hardening-9adfb18a` | adapter_caps slurps unbounded adapter output with no timeout | Add a timeout and bounded capture around adapter advertise calls |
| `2026-11-02-headless-runner-ignores-sigint-8fb47aec` | Headless workers start with SIGHUP/INT/QUIT ignored via nohup without job control | Launch the headless runner the detached-run.sh way (set -m, HUP-catching runner) |

### B116. Convergence steps composed with non-tmux backends

- Bundle id: `eb-step-backend-composition`
- Owner: execution backends (`specs/execution-backends/`)
- Open fragments: 2
- Smallest change: Add resume and stop capabilities to caps_for and a hosting seam so isolated
  convergence steps run isolated on stream-json workers.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-24-backend-resume-stop-caps-9d227d02` | custom-steps rules branch on resume and stop capabilities caps_for does not carry | Add resume and stop fields to caps_for and the capability contract |
| `2026-10-11-isolated-steps-degrade-on-stream-json-7f7e0c9f` | Isolated convergence steps degrade to in-session on stream-json workers; no hosting seam | Let offload-dispatch host per-step isolated runs for stream-json workers |

### B117. Tower watchdog exit and marker-store trust

- Bundle id: `fa-fleet-tower-hardening`
- Owner: fleet autonomy (`specs/fleet-autonomy/`)
- Open fragments: 2
- Smallest change: Make a trailing audit-write failure non-fatal after a committed action and keep
  the tower marker store out of worker reach.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-17-tower-marker-authenticity-b47b3043` | Worker-writable tower marker store could plant a marker nudging a resume command | Add an authenticity or ownership check on tower marker rows |
| `2026-07-17-tower-watchdog-audit-write-exit-95776321` | Watchdog exits 2 on trailing audit-write failure after the action committed | Decide and implement audit-write failure as warning plus outcome, not exit 2 |

### B118. Changelog entry forms the guards disagree on

- Bundle id: `fg-changelog-grammar`
- Owner: format grammar and parser unification (`specs/format-grammar/`)
- Open fragments: 2
- Smallest change: Accept one canonical dated changelog form in all guards and let the dead-path
  check honour expression-only edits already recorded there.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-03-bold-date-changelog-entries-dd7591f9` | Bold-dated changelog entries are ignored by guards keyed on the plain dated form. | Pin the plain form in spec-format and touch the bold fleet-lifecycle-closure entries. |
| `2026-09-03-dead-path-check-on-expression-edits-3e0a9b05` | Dead-path check warns on expression-only edits already recorded in a dated Changelog. | Silence the warning when a dated Changelog entry since baseline names the REQ id. |

### B119. Parked tasks invisible to selector and dependents

- Bundle id: `fg-parked-task-visibility`
- Owner: format grammar and parser unification (`specs/format-grammar/`)
- Open fragments: 2
- Smallest change: Have the selector read task references anywhere in Awaiting input bullets and
  warn when a dependency points at a merged but parked task.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-20-parked-in-prose-invisible-to-selector-0302098b` | A task parked only in another bullet's prose is invisible to the selector | Require one Awaiting-input bullet per parked task, validated by spec-validate |
| `2026-10-10-parked-merged-task-dependency-627fc204` | A dependency on a merged but parked task blocks nothing; no tool warns the author | Warn in spec-draft/kickoff on an edge to a task with merged trailer evidence |

### B120. Fleet-hardening expression amendment

- Bundle id: `fh-spec-amendment`
- Owner: fleet hardening (`specs/fleet-hardening/`)
- Open fragments: 2
- Smallest change: Expression-only amendment fixing the mechanism count and naming the REQ-H1.1
  source assertion in a task's Done-when.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-20-fleet-hardening-mechanism-count-8-vs-9-aada9500` | fleet-hardening design says eight mechanisms, test-spec says nine | Expression-only amendment updating design.md mechanism count to nine |
| `2026-10-04-req-h1-1-source-assertion-owner-203caacf` | REQ-H1.1 source assertion fits Task 12 but neither Task 11 nor 12 Done-when names it | Name the bounded-runner source assertion in fleet-hardening Task 12 Done-when |

### B121. Registry and stream-json state retention

- Bundle id: `flc-state-retention`
- Owner: fleet lifecycle closure (`specs/fleet-lifecycle-closure/`)
- Open fragments: 2
- Smallest change: Add a retention knob and prune sweep for retired registry rows and stream-json
  worker state.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-02-registry-retention-and-write-cost-75369b47` | Registry appends forever with O(N) copy-rename per write; retired rows exist but nothing prunes. | Add a prune of retired registry records under the fleet lock. |
| `2026-09-07-streamjson-state-has-no-retention-4dd41794` | Fleet streamjson state grows without bound; no retention, knob or sweep for worker transcripts | Add a retention policy and sweep for ended stream-json worker directories |

### B122. cdpath and glob allow-rule scan gaps

- Bundle id: `gc-guard-scan-gaps`
- Owner: guard coverage (`specs/guard-coverage/`)
- Open fragments: 2
- Smallest change: Parse JSON in the glob allow-rule scan and check cdpath order and quoting.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-19-glob-scan-json-format-assumption-025baab3` | Glob allow-rule scan assumes pretty-printed JSON; minified config fails open | Extract permission arrays with jq, keeping the line scan as fallback |
| `2026-09-03-cdpath-guard-residual-limits-f7a90c3d` | check:cdpath checks presence not order, and ignores quoting, causing misses and false positives. | Move check-cdpath onto the shell-rule-lib tokenizer for quote and order awareness. |

### B123. Secret scan walks refs outside the branch under test

- Bundle id: `gc-secret-scan-ref-scope`
- Owner: guard coverage (`specs/guard-coverage/`)
- Open fragments: 2
- Smallest change: Scope local and CI gitleaks runs to the base..HEAD range of the branch under
  test.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-12-gitleaks-scans-sibling-refs-c02198e1` | gitleaks walks every ref in the shared store, so a sibling branch's fixture reddens every worktree | Scope the branch check to origin/main..HEAD; keep the all-refs scan for repo sweeps |
| `2026-09-28-secret-scan-walks-all-refs-5124bd8b` | scan:secrets scans every fetched ref, so one PR fixture turned main and every PR red | Scope the CI gitleaks scan to the commits under test, not all refs |

### B124. Guard-coverage expression amendment

- Bundle id: `gc-spec-amendment`
- Owner: guard coverage (`specs/guard-coverage/`)
- Open fragments: 2
- Smallest change: Expression-only amendment reconciling REQ-A1.3 with D-3 and stating the
  head_repository posture assertion.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-22-req-a13-wire-phrase-ambiguity-365fbbd0` | REQ-A1.3 wire-step wording conflicts with D-3 check-never-wires | Expression-only amendment rewording REQ-A1.3 per D-3 |
| `2026-09-06-guard-assertion-4-originating-repository-e27d4051` | Assertion 4 now requires head_repository, but the guard-coverage bundle still states the old two parts. | Kickoff delta re-walk updating REQ-C1.2, D-6, test-spec and Task 4 text. |

### B125. Dependency bot setup and auto-merge class

- Bundle id: `hg-dependency-bot`
- Owner: human gates (policy guard and sign-off) (`specs/human-gates/`)
- Open fragments: 2
- Smallest change: Configure Renovate on manifests and lockfiles and add a dependency merge class
  with its own caller, predicates and lockfile zone.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-28-dependency-bot-class-merge-5ef997a5` | Auto-merging dependency-bot PRs needs its own caller, predicates and a lockfile zone decision | Amend human-gates with a dependency-bot policy class, caller and predicate set |
| `2026-11-05-renovate-dependency-bot-f291c49d` | Set up Renovate limited to manifests and lockfiles for the dependency merge class | Add a Renovate config limited to mise.toml pins after the operator approves access |

### B126. Holder repositories: aliases and multi-repo derivation

- Bundle id: `it-holders`
- Owner: invariant tasks (`specs/invariant-tasks/`)
- Open fragments: 2
- Smallest change: Amend spec-format and invariant-tasks so holders are invalid Repository values,
  and derive dispatch evidence across every work repo on a holder.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-11-02-per-session-derivation-split-a18bd8ae` | With several work repos on one holder, sessions derive only their own evidence and can double-dispatch | Derive repository-less task evidence across every registered work repo before dispatch |
| `2026-11-03-holder-alias-decision-51d04d91` | Ruling: keep the holder-alias refusal; amend spec-format and invariant-tasks so holders are invalid Repository values | Run the /spec-kickoff delta amending invariant-tasks design.md and spec-format.md |

### B127. Sanctioned status flips and zero-diff task completion

- Bundle id: `kl-state-transition-helpers`
- Owner: kickoff lifecycle (`specs/kickoff-lifecycle/`)
- Open fragments: 2
- Smallest change: Ship a deterministic set-status script and a completion path for tasks fully
  delivered at kickoff.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-19-execute-task-zero-diff-design-task-f3376f78` | No sanctioned completion path for a task fully delivered at kickoff; forced empty commit | Sanction an already-satisfied completion path, or have spec-draft fold altitude tasks |
| `2026-07-20-spec-status-flip-helper-a88f696a` | Status flips are ad-hoc edits; a deterministic set-status script would remove a footgun | Add scripts/spec-set-status.sh validating the transition and rewriting all four headers |

### B128. Convergence main-sync scope and post-PR reconvergence

- Bundle id: `mcg-convergence-sync`
- Owner: merge currency guard (ready-guard) (`specs/merge-currency-guard/`)
- Open fragments: 2
- Smallest change: Give execute-task a path back to convergence when a post-PR step lands code, with
  a relatedness-plus-recency main-sync predicate and file-scope partitioning.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-22-pr-splitting-and-sync-frugality-36916a48` | Operator wants file-scope unit partitioning and a relatedness-plus-recency predicate on the main sync | Add a relatedness-plus-recency skip to the D-4 top-of-iteration sync |
| `2026-10-26-execute-task-post-pr-reconvergence-5ce6a787` | Ready-flip parks when a post-pr step lands code; execute-task names no path back | Add a re-convergence path in execute-task: rerun convergence and post-pr on the new head |

### B129. Observation-recording expression amendment

- Bundle id: `or-spec-amendment`
- Owner: observation recording (`specs/observation-recording/`)
- Open fragments: 2
- Smallest change: Add docs/ to the REQ-E1.3 test-spec scope and name script writers in
  accumulator-taxonomy.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-11-test-spec-req-e13-scope-34edff2a` | REQ-E1.3 test-spec grep scope omits docs/ while requirement and shipped test cover it | Expression-only amendment adding docs/ to the REQ-E1.3 test-spec verification scope |
| `2026-09-02-obs-accumulator-script-writers-d0328192` | accumulator-taxonomy names only skill writers; a script now records fragments too. | Amend the write-side text to cover script writers and their scope/failure duties. |

### B130. Noisy sidedness and comment-budget check output

- Bundle id: `pd-noisy-prose-checks`
- Owner: prose disposition (`specs/prose-disposition/`)
- Open fragments: 2
- Smallest change: Drain or exempt the sidedness findings and print one comment-budget summary
  instead of a WARN per file.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-22-interaction-style-flags-itself-fdcd0fa9` | check-sidedness flags interaction-style's own line and many skill lines (24 findings now) | Declare a destination side on the flagged emit mandates, starting with interaction-style |
| `2026-10-25-comment-budget-warn-volume-13220d40` | check:comment-budget prints one WARN per file (167), flooding every gate log | Decide a summary-only aggregate mode via a REQ-F1.1 amendment, or fold warn files into cleanup |

### B131. Skills name the artifact-class lens selection

- Bundle id: `sr-lens-artifact-class`
- Owner: skill rigor (`specs/skill-rigor/`)
- Open fragments: 2
- Smallest change: Name artifact-lenses class selection in self-review, spec-kickoff and
  kickoff-verification so spec bundles get the spec lens set.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-25-skill-drift-3672d83d` | /self-review never names the artifact-class lens selection step discovery-rigor requires. | Add artifact-class lens-set selection to self-review, polish and execute-task discovery steps. |
| `2026-09-01-skill-drift-b165f3de` | Kickoff sign-off fan-out still says one sub-agent per canonical code lens. | Name artifact-class lens selection in spec-kickoff and kickoff-verification. |

### B132. Tower scorecard counting accuracy

- Bundle id: `tc-scorecard`
- Owner: tower comms (`specs/tower-comms/`)
- Open fragments: 2
- Smallest change: Count one delivery per turn, stop blocked-wait accrual when a question settles,
  and cross-check items without --item.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-21-consumed-98c25bd6-6671f508` | Consumed 98c25bd6; nothing forces the loop to pass --item, so a scorecard cross-check is needed | Add a scorecard cross-check for itemless delivered lines inside an itemed turn |
| `2026-11-01-scorecard-blocked-wait-ignores-settles-b9c919c3` | Scorecard blocked wait keeps accruing after a question settles by evidence or default | End a blocked wait at the first settled or default window line; recompute fixtures |

### B133. Tower-comms expression amendment

- Bundle id: `tc-spec-wording`
- Owner: tower comms (`specs/tower-comms/`)
- Open fragments: 2
- Smallest change: Expression-only amendment fixing the Task 7 versus Task 8 manifest owner and
  stating pair lease and stamp behaviour.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-12-tower-comms-manifest-ownership-d30ce8aa` | tower-comms test-spec REQ-I1.1 says Task 7 owns manifest wiring that tasks.md gives Task 8 | Tighten the REQ-I1.1 ownership sentence at the next amendment |
| `2026-09-18-pair-partner-lease-unstated-f7e62045` | tower-comms never states that a pair leases and stamps both items | Amend REQ-B1.3 and Task 4 to state the partner lease behaviour |

### B134. Configurable branch prefix and launch namespaces

- Bundle id: `tfd-branch-namespace`
- Owner: tower front door (`specs/tower-front-door/`)
- Open fragments: 2
- Smallest change: Make the branch prefix configurable and give mission-control launches their own
  namespace so the tower sweep stops listing them as flights.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-01-configurable-branch-prefix-3640d42d` | Operator wants a configurable branch prefix in place of the fixed planwright/ segment | Add a branch-prefix knob read by every branch-name parser, via a tower-front-door amendment |
| `2026-11-05-launcher-flight-namespace-01c12030` | Mission-control launches use planwright/flight/ branches, so the tower sweep lists them as flights | Have flight-sweep.sh skip worktrees a mission-control registry row names |

### B135. Gate false-red rate measured with load

- Bundle id: `tt-gate-signal`
- Owner: test throughput (`specs/test-throughput/`)
- Open fragments: 2
- Smallest change: Instrument real gate runs with load columns to measure the false-red rate before
  fixing individual cases.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-07-full-gate-fails-one-run-in-four-66ae088f` | Full gate fails about one run in four on unrelated suites; instrument the real gate, not single cases | Capture concurrent suites, fleet-home state and host load when a suite fails inside the gate |
| `2026-09-09-gate-load-is-a-machine-property-14bf37c8` | Gate load sensitivity is a host property during fleet runs; flake rates without load columns are noise | Record claude process count, load average and free memory with each gate verdict |

### B136. Suite time budget and oversized test files

- Bundle id: `tt-suite-time-budget`
- Owner: test throughput (`specs/test-throughput/`)
- Open fragments: 2
- Smallest change: Add a section selector or split test-flight-dispatch and test-resolve-steps under
  the per-file budget.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-02-flight-dispatch-test-sections-fbfcd856` | test-flight-dispatch.sh is one 18-minute file with no section selector | Add a section selector or split test-flight-dispatch.sh into smaller files |
| `2026-10-05-resolve-steps-test-time-2c393630` | test-resolve-steps.sh nears the 120s per-file budget locally | Check its CI per-file time and split it behind a shared tests/lib harness if needed |

### B137. Orchestration readers re-derive state per question

- Bundle id: `ub-perf-orchestration-readers`
- Owner: universal binary (portability and spawn cost) (`specs/universal-binary/`)
- Open fragments: 2
- Smallest change: Derive orchestration and spec-status state in one pass per invocation instead of
  a child process per question.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-15-spec-status-single-pass-render-a597583f` | spec-status.sh forks per record; single-awk-pass fix recorded if D-12 revisit fires | None until D-12 revisit signals fire; then single awk pass in spec-status.sh |
| `2026-10-02-orchestration-reader-spawn-cost-3e069cd6` | Orchestration and spec readers re-derive state through child processes per question | Cut per-question spawns in orchestrate-select, tasks-pr-sync, spec-validate and siblings |

### B138. Worker-permission-ergonomics expression amendment

- Bundle id: `wpe-spec-wording`
- Owner: worker permission ergonomics (`specs/worker-permission-ergonomics/`)
- Open fragments: 2
- Smallest change: Correct REQ-A1.12 and D-24 on failing substitution assignments and add the
  spec-root write zone to REQ-F1.5.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-12-substitution-assignment-can-fail-5005a275` | REQ-A1.12 and D-24 wrongly say a substitution assignment cannot fail | Kickoff delta amending REQ-A1.12, D-24 and the A1.12 test-spec entry |
| `2026-10-19-floor-vs-spec-zone-dc162d4f` | REQ-F1.5 floor text omits the spec-root write zone the guard keeps | Reconcile REQ-F1.5 with custom-spec-location D-15's spec-root zone explicitly |

### B139. Never-shell-git-worktree rule names its sanctioned exceptions

- Bundle id: `bootstrap-worktree-rule`
- Owner: bootstrap (`specs/bootstrap/`)
- Open fragments: 1
- Smallest change: Amend bootstrap D-37 and the orchestrate skill wording to list the sanctioned git
  worktree exceptions instead of an absolute ban.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-20-d37-slashed-branch-shell-exception-7ad46e46` | bootstrap D-37 never-shell-git-worktree is aspirational; sanctioned exceptions exist | Amend bootstrap D-37 to sanction git worktree add for slashed-branch placement |

### B140. Self-review still hard-codes the specs/ path

- Bundle id: `csl-hardcoded-spec-root`
- Owner: custom spec location (`specs/custom-spec-location/`)
- Open fragments: 1
- Smallest change: Route self-review's kickoff-brief path through the resolved spec root as polish
  already does.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-07-skill-drift-827c8a03` | polish and self-review hard-code specs/ paths; polish fixed, self-review still names specs/&lt;spec&gt;/kickoff-brief.md | Change self-review brief detection to &lt;root&gt;/&lt;spec&gt;/kickoff-brief.md |

### B141. Dotfiles CI mas-install timeouts read as failures

- Bundle id: `flight-dotfiles-ci-mas`
- Owner: a spec-less flight (`flight`)
- Open fragments: 1
- Smallest change: In the dotfiles repo, bound or skip mas installs in the osx and upgrade jobs and
  classify the timeout as flaky.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-03-dotfiles-mas-jobs-time-out-70d056ba` | Dotfiles osx/upgrade jobs time out on mas installs and read as failed, not flaky. | Raise timeout or pre-install/drop mas in the dotfiles test matrix. |

### B142. Mission-control sessions messaging across machines

- Bundle id: `fm-cross-machine-messaging`
- Owner: fleet messaging (`specs/fleet-messaging/`)
- Open fragments: 1
- Smallest change: Add a cross-machine transport or relay to fleet messaging so sessions on
  different hosts can reach each other.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-11-05-mc-cross-machine-relay-57770415` | Mission-control sessions on different machines cannot message each other | Document a cross-machine relay recipe or add a shared inbox both sessions poll |

### B143. Repository CLAUDE.md for agents working on planwright

- Bundle id: `ih-repo-claude-md`
- Owner: instruction-budget headroom (`specs/instruction-headroom/`)
- Open fragments: 1
- Smallest change: Add a short repo CLAUDE.md pointing agents at the gate, conventions and doctrine,
  charged against the budget.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-27-ctxeng-no-repo-claude-md-ab878b9e` | planwright has no repo CLAUDE.md for agents working on it | Enroll a budget class, then add a short pointers-and-gotchas root CLAUDE.md |

### B144. Panel presence marker read by the queue

- Bundle id: `mc-panel`
- Owner: mission control (`specs/mission-control/`)
- Open fragments: 1
- Smallest change: Have the tower-queue presence verb read the marker mc-panel writes, keeping one
  presence source.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-26-mc-presence-marker-edge-14399ba2` | mc-panel writes its own presence marker; the queue's presence verb does not read it | Have mc-panel.sh write through tower-queue.sh presence so the queue has one source |

### B145. Superpowers and planwright interop positioning

- Bundle id: `newspec-superpowers-interop`
- Owner: a new spec: superpowers interop (`new-spec`)
- Open fragments: 1
- Smallest change: New spec or doc positioning superpowers and planwright as layers, with an interop
  recipe and a fair comparison page.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-27-superpowers-interop-a8d7dfb2` | Position superpowers and planwright as layers; interop recipe and a fair comparison page. | Draft a seed for an interop overlay recipe and comparison page. |

### B146. Revisit the spec walkthrough artifact

- Bundle id: `pending-walkthrough-revisit`
- Owner: the walkthrough-revisit seed brief (`specs/_pending/walkthrough-revisit.md`)
- Open fragments: 1
- Smallest change: Spec the walkthrough revisit: retire or rework the HTML artifact toward
  interactive kickoff comprehension.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-08-27-spec-walkthrough-artifact-e09d8fc5` | Operator found the walkthrough HTML artifact unhelpful and prefers interactive kickoff comprehension. | Fold into the walkthrough-revisit seed when it is drafted. |

### B147. Workers lack the operator's login environment

- Bundle id: `pending-worker-login-shell-env`
- Owner: the environment-broker seed brief (`specs/_pending/environment-broker.md`)
- Open fragments: 1
- Smallest change: Carry the operator's fish and mise environment into workers through the
  environment broker.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-09-24-worker-login-shell-env-ada69b21` | Workers run bash and miss the operator fish plus mise environment; fish -c wrappers are refused | Capture the login-shell PATH at dispatch and export it through fleet-dispatch-env.sh |

### B148. Quota-hold push reservation leak

- Bundle id: `qh-quota-handling`
- Owner: quota handling (`specs/quota-handling/`)
- Open fragments: 1
- Smallest change: Set PUSH_TOKEN before moving the push reservation in quota-hold.sh so a TERM
  cannot leak it.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-10-19-quota-hold-reservation-race-55d41af8` | quota-hold.sh moves the push reservation before setting PUSH_TOKEN; a TERM between leaks it | Set PUSH_DIR and PUSH_TOKEN before the mv in quota-hold.sh's reservation step |

### B149. macOS Gatekeeper first-exec stalls in tests

- Bundle id: `tt-macos-portability`
- Owner: test throughput (`specs/test-throughput/`)
- Open fragments: 1
- Smallest change: Warm or hard-link fresh shim executables in tests and keep macOS local timings
  out of budget baselines.

| Fragment | What it says | Its own smallest change |
| --- | --- | --- |
| `2026-07-19-dispatch-fetch-review-harness-flake-7f432dea` | Fresh PATH-shim executables stall on macOS Gatekeeper under parallel tests | Pre-warm shims once or document macOS parallel runs as non-authoritative |

## Already covered (122)

Each can be consumed now against its owning spec (`scripts/obs-consume.sh --uid <uid> --spec
<spec>`, the consumer being a spec identifier); the commit is the evidence that it landed. A row
owned by `flight` has no spec to name, so its consumer is the operator's choice.

| Fragment | Owner | Landed in | What it said |
| --- | --- | --- | --- |
| `2026-07-13-eval-skill-injection-gap-dc2883b2` | kept prompt-eval harness (`specs/prompt-hygiene/`) | 78f31bfb feat(orchestrate): diet /orchestrate + eval-harness hardening; pilot deferred (Task 5) (#169) | headless -p had no Skill tool; fixed with slash prompts plus SKILL.md H1 sentinel |
| `2026-07-17-kickoff-mid-walk-edit-relens-830c511b` | spec-kickoff walkthrough (`specs/kickoff-lifecycle/`) | f2ec9d07 feat(spec-kickoff): mid-walk lens + post-lens stale-reference sweep (task 7) (#286) | Kickoff should re-lens a mid-walk D-ID mint at the point it is made |
| `2026-07-20-freshness-gate-anchor-wording-247c430b` | orchestrate fetch-before-gate prose (`specs/fleet-hardening/`) | 8fc3140f feat(spec-location): run execution against a spec root outside the work repository (#616) | fetch-before-gate prose claimed an origin/main anchor even on offline exit 3 |
| `2026-07-22-fleet-home-default-umask-9c5071dd` | fleet home resolution (`specs/fleet-hardening/`) | e8b1bbf7 feat(tower-comms): ship the event log and the scorecard (task 1) (#451) | fleet-state created the fleet home with default umask |
| `2026-07-23-streamjson-deny-message-escaping-b11b9175` | stream-json supervisor (`specs/execution-backends/`) | d01dd9b8 fix(backends): control-char escaping and stat portability in the stream-json supervisor (#317) | Deny message escaped only backslash and quote, not tab/CR/C0 |
| `2026-07-23-streamjson-test-load-flake-23017942` | test suite throughput and load robustness (`specs/test-throughput/`) | e8595616 test: poll for events instead of asserting timing windows (#709) | streamjson c11 large-prompt case flaked under load |
| `2026-07-24-gate-multi-atom-parse-097e7cea` | drain gate grammar (`specs/format-grammar/`) | e2964bd1 chore(specs): convert three unparseable GATE(when:) gates to free-text (#321) | Three GATE(when:) gates malformed from prose clauses and OR joiner |
| `2026-07-24-gate-status-lifecycle-7cc5a87e` | drain gate grammar (`specs/format-grammar/`) | ff1f67b8 feat(drain): reconcile the gate evaluator with the six-status lifecycle (task 4) (#367) | drain-gates.sh did not recognize Ready status |
| `2026-07-24-straggler-triage-measured-wrong-platform-ce2f762f` | test wall-clock budgets (`specs/guard-coverage/`) | c75f006d feat(guards): gate the test suite's wall-clock against committed budgets (#403) | Straggler triage ranked from local runs; budgets must use reference runner |
| `2026-07-24-suite-stragglers-beyond-triage-f4306a0a` | test wall-clock budgets (`specs/guard-coverage/`) | c75f006d feat(guards): gate the test suite's wall-clock against committed budgets (#403) | Triage missed fleet-liveness and tasks-pr-sync stragglers |
| `2026-07-24-throttle-elapse-test-load-flake-ef2549c2` | test suite throughput and load robustness (`specs/test-throughput/`) | b5723f27 feat(guards): refuse sanitized text reaching a command that expands escapes (#414) | Throttle case 33 elapse re-engage flakes under load; reproduced A/B |
| `2026-07-26-streamjson-c12-flake-under-load-e4401869` | test suite throughput and load robustness (`specs/test-throughput/`) | e8595616 test: poll for events instead of asserting timing windows (#709) | streamjson c12 queue-clear assertion flakes under concurrent suites |
| `2026-07-27-ctxeng-review-skill-frontload-d2abb33d` | instruction budget guard and headroom (`specs/instruction-headroom/`) | 5d6057e3 feat(instruction-budget): diet the review skills and charge their nested chain (#702) | self-review and polish front-load methodology doctrine; reclassify to point-of-use |
| `2026-08-18-skill-drift-a19fc34c` | orchestrate skill worktree-creation guidance (`specs/skill-rigor/`) | b90590d3 fix(orchestrate): dispatch through the resolved backend, never a silent tmux worker (#853) | Orchestrate skill forbade git worktree absolutely and never named the sanctioned --no-attach create path. |
| `2026-08-18-workflow-run-fork-branch-131af768` | the release-please workflow trigger posture (`specs/release-hardening/`) | 0f9fd714 fix(ci): fire the release proposal only for runs this repo produced (#415) | Fork PR from a branch named main can fire the privileged release-please workflow_run job. |
| `2026-08-18-worktreecreate-root-cause-correction-2036d463` | worktree lifecycle hooks (`specs/fleet-lifecycle-closure/`) | c3433855 feat(hooks): pin every hook payload and stop registering the one that refuses (#368) | Real cause: planwright's WorktreeCreate hook read a nonexistent field and silently refused creation. |
| `2026-08-24-skill-drift-fbc582f6` | freshness-gate remedies in execute-task and orchestrate (`specs/anchor-integrity/`) | 73dd75fd feat(guard): stand up the anchor-freshness guard and its pre-commit mirror (anchor-integrity task 4) (#354) | Gate skills omitted the pre-change-anchor self-re-anchor remedy the doctrine added. |
| `2026-08-24-streamjson-flake-under-load-b3b53a4c` | load-flaky fleet test suites (`specs/test-throughput/`) | 85af215d fix(fleet): write the queue row under the lock that guards what it reflects (#438) | test-fleet-streamjson c12 queue-drain assertion flakes under parallel load. |
| `2026-08-25-fleet-audit-lost-update-flake-84cab312` | the fleet lock primitive (`specs/universal-binary/`) | c52b8023 feat(locks): adopt the lock holders onto the shared lock primitive (#603) | fleet-audit concurrent writers lose an update under load, suggesting the append path is not exclusive. |
| `2026-08-26-ci-runs-under-live-worker-identity-54d48a47` | test isolation from the live fleet home (`specs/test-throughput/`) | 9ea089a8 fix(tests): keep fleet test suites out of the operator's real fleet registry (#608) | Checks run inside a worker inherit live worker identity and the real fleet state root. |
| `2026-08-26-generated-artifacts-unlinted-8c6fdca5` | linting of generated artifacts (`specs/guard-coverage/`) | 345b4487 feat(guards): add the shell rule set and emitter output linting (#778) | Files scripts emit are linted by nothing; two real defects slipped through. |
| `2026-08-26-mcg-loop-owner-decision-d7e936d7` | the convergence loop's main sync (`specs/merge-currency-guard/`) | 3d757f36 feat(execute-task): keep the converging branch current with main (#359) | Owner decision: execute-task gains the convergence loop with a top-of-pass main sync. |
| `2026-08-26-worktreecreate-contract-supersession-46886617` | worktree lifecycle hooks (`specs/fleet-lifecycle-closure/`) | c3433855 feat(hooks): pin every hook payload and stop registering the one that refuses (#368) | Corrected WorktreeCreate contract: no hook registered, creation tracked at the dispatch seam. |
| `2026-08-27-flaky-suites-under-parallel-load-38dcb4ee` | load-flaky fleet test suites (`specs/test-throughput/`) | e8595616 test: poll for events instead of asserting timing windows (#709) | Different fleet suites flake under parallel load; red check becomes ambiguous. |
| `2026-08-27-flaky-throttle-elapse-under-load-7343b529` | load-flaky fleet test suites (`specs/test-throughput/`) | b5723f27 feat(guards): refuse sanitized text reaching a command that expands escapes (#414) | test-fleet-throttle case 33 races its 3-second anchor under load. |
| `2026-08-27-fleet-timing-flakes-under-load-f2e5836e` | the fleet lock primitive (`specs/universal-binary/`) | c52b8023 feat(locks): adopt the lock holders onto the shared lock primitive (#603) | Different fleet timing and lost-append assertions fail across full runs; fix belongs in append paths. |
| `2026-08-28-check-instructions-red-on-main-4a3e2947` | instruction-budget relief (`specs/instruction-headroom/`) | 7407973e fix(instructions): diet the polish start-load back past its restoration target (#375) | check-instructions test failed on main from a below-target polish start-load. |
| `2026-08-28-fleet-streamjson-parallel-flake-9a7f68da` | load-flaky fleet test suites (`specs/test-throughput/`) | 85af215d fix(fleet): write the queue row under the lock that guards what it reflects (#438) | test-fleet-streamjson c5 queue-clear flaked once under parallel load. |
| `2026-08-28-purged-guard-maxwords-floor-fd55ba86` | purged-identifier guard floors (`specs/guard-coverage/`) | 02b1ddfa feat(guard): screen the tree and commits for purged identifiers (guard-coverage task 3) (#373) | A hand-lowered max-words narrows the scan silently with no floor. |
| `2026-08-31-allocation-adapt-sigterm-flaky-ab0d3fe9` | load-flaky test suites (`specs/test-throughput/`) | 18efdf74 fix(test): pin the SIGTERM case by holding the engine in the locked append (#376) | test-allocation-adapt 13k SIGTERM case is machine-speed flaky on a fixed sleep. |
| `2026-09-02-allocation-feedback-callsite-7c8e69ca` | the escalation feedback loop's call sites (`specs/model-allocation/`) | 3877751a fix(allocation): run the escalation feedback loop at a unit's terminal states (#413) | allocation-feedback.sh had no terminal-state call sites owned by any task. |
| `2026-09-02-release-please-trigger-not-authz-0934616b` | the release-please workflow trigger posture (`specs/release-hardening/`) | 0f9fd714 fix(ci): fire the release proposal only for runs this repo produced (#415) | Fork-main PR runs can fire and time the privileged release job off a red main. |
| `2026-09-03-stop-leaves-registry-record-daba5f5c` | registry records after stop (`specs/fleet-lifecycle-closure/`) | a8854674 feat(fleet): dispatch-record reconcile and multi-tower adversarial suite (#550) | A stopped worker leaves its registry record standing with nothing to reconcile it. |
| `2026-09-04-fleet-home-mode-gate-c0d053ae` | fleet home creation mode (`specs/fleet-lifecycle-closure/`) | e8b1bbf7 feat(tower-comms): ship the event log and the scorecard (task 1) (#451) | Fleet home created with a bare mkdir -p and no mode pin. |
| `2026-09-04-lock-family-token-crossing-5a664389` | the fleet lock primitive (`specs/universal-binary/`) | 623a1d0b feat(locks): release the fleet lock by owner token in its remaining consumers (#635) | External fleet-lock consumers release without a token, deleting a successor's lock. |
| `2026-09-04-stale-break-claim-limits-131c97b3` | the fleet lock primitive (`specs/universal-binary/`) | 69c8371a feat(locks): one atomic-create advisory lock for the script layer (#458) | Rename-aside stale break can still double-grant when a breaker is descheduled. |
| `2026-09-06-allocation-roster-and-fable-policy-fea82b1c` | the model roster and escalation-only top (`specs/model-allocation/`) | d50aef0c feat(allocation): state the model roster once and keep the top escalation-only (#422) | Fable must be escalation-only and the roster collapsed to one append-only definition. |
| `2026-09-06-consumer-lock-ownership-window-0dab2001` | the fleet lock primitive (`specs/universal-binary/`) | 623a1d0b feat(locks): release the fleet lock by owner token in its remaining consumers (#635) | Seven external lock consumers can leak the lock in the acquire window for lack of a token. |
| `2026-09-06-echo-safety-helper-gap-c9c109b6` | the echo discipline (`specs/universal-binary/`) | 3877751a fix(allocation): run the escalation feedback loop at a unit's terminal states (#413) | fleet-fence.sh err() echoes sanitized text through a helper the guard cannot see. |
| `2026-09-06-feedback-loop-still-unreached-639cea17` | the escalation feedback loop's call sites (`specs/model-allocation/`) | 3877751a fix(allocation): run the escalation feedback loop at a unit's terminal states (#413) | Feedback loop subcommands were wired but nothing invoked them end to end. |
| `2026-09-06-suite-load-sensitivity-ea3d8a3e` | load-flaky fleet test suites (`specs/test-throughput/`) | e8595616 test: poll for events instead of asserting timing windows (#709) | Sweep the suite for wall-clock windows under about 5s rather than fixing one at a time. |
| `2026-09-06-vacuous-absence-checks-elsewhere-6108e668` | vacuous absence checks in tests (`specs/test-throughput/`) | cc8c467d fix(test): stop the sanitizer stderr check passing without reading anything (#416) | case $(cat ...) leak checks in two suites pass when the read fails. |
| `2026-09-07-attention-unlock-silenced-c1ed7ea1` | the shared lock primitive and its consumers (`specs/universal-binary/`) | 623a1d0b feat(locks): release the fleet lock by owner token in its remaining consumers (#635) | fleet-attention.sh unlock discards status and stderr, hiding the unlock diagnostic once it ships |
| `2026-09-07-ci-title-lint-cannot-rerun-849e162e` | the CI pull-request title lint (`flight`) | 6f38a80a fix(ci): lint the PR title on a trigger that can re-check a correction (#420) | PR title lint never re-runs on title edits because ci.yml lacks the edited trigger |
| `2026-09-07-orchestrate-closure-headroom-spent-37c2711e` | instruction-budget headroom (`specs/instruction-headroom/`) | e3d4ef84 feat(doctrine): add the messaging-transport doctrine and its knobs (#648) | orchestrate closure had seven words of slack, so any reachable doc change reddened the gate |
| `2026-09-07-overlays-explain-overbroad-a5079b6a` | the overlay layering docs (`specs/customization-overlay/`) | 821fb2f8 feat(resolve-root): add the spec kind with a configurable spec root (#521) | overlays.md claims every resolver has --explain, but resolve-config-knob.sh had none |
| `2026-09-07-registration-fixture-leaks-supervisor-4a4796d0` | test fixture process hygiene (`specs/test-throughput/`) | a527b86e fix(test): close the supervisor the registration fixture leaked every run (#423) | test-fleet-registration c3 leaked one stream-json supervisor per run through a glob that never matched |
| `2026-09-07-streamjson-queue-clear-unproven-e25c7458` | stream-json queue test reliability (`specs/test-throughput/`) | 85af215d fix(fleet): write the queue row under the lock that guards what it reflects (#438) | streamjson c12 queue-clear failure: proposed lock-ordering mechanism did not reproduce; instrument the real run |
| `2026-09-09-every-budget-exception-sits-at-its-floor-8905e6b9` | instruction-budget headroom (`specs/instruction-headroom/`) | e7501d7d feat(guards): hold a budget exception to the margin it was granted at (#439) | Every declared exception sits at its floor; a margin ratchet is a regression floor, not a fix |
| `2026-09-12-parallel-units-ignore-suite-cost-0c4456bb` | machine-wide test concurrency (`specs/test-throughput/`) | 75c941a0 feat(test-runner): share one machine-wide ticket pool across test runs (#537) | Parallel-unit cap counts workers not suite load; overloaded host produced wrong verdicts and parks |
| `2026-09-13-detached-hold-token-handoff-bf2a4835` | the shared lock primitive (`specs/universal-binary/`) | c52b8023 feat(locks): adopt the lock holders onto the shared lock primitive (#603) | Detached hold taken via command substitution can leave a token nobody holds |
| `2026-09-13-lock-consumer-token-adoption-39b354f3` | the shared lock primitive and its consumers (`specs/universal-binary/`) | 623a1d0b feat(locks): release the fleet lock by owner token in its remaining consumers (#635) | Seven fleet lock consumers still release token-less |
| `2026-09-13-streamjson-test-leaks-supervisors-147b0473` | test fixture process hygiene (`specs/test-throughput/`) | 14b94d3e test(fleet-streamjson): stop the c30 resume from leaking a worker tree (#591) | test-fleet-streamjson.sh leaks supervisors; teardown should reap by sandbox root |
| `2026-09-15-prose-and-queue-deliveries-double-count-98c25bd6` | the tower scorecard (`specs/tower-comms/`) | ada82fd2 feat(tower-comms): route the tower loop's turns through the operator queue (#486) | Prose and queue delivered lines double-count one turn in the scorecard |
| `2026-09-16-stuck-detector-test-tower-env-8204bebe` | test environment isolation (`specs/tower-comms/`) | 687163db feat(tower-comms): log replies, ticks and delivered turns from the tower (task 2) (#468) | test-fleet-stuck-detector fails when PLANWRIGHT_TOWER_ID is exported |
| `2026-09-17-queue-field-guard-rejects-utf8-98a155ab` | tower-queue field guard (`specs/tower-comms/`) | f9af67c3 fix(tower-queue): stop the field guard refusing multi-byte text (#472) | tower-queue field guard rejects UTF-8 continuation bytes as C1 controls |
| `2026-09-17-streamjson-suite-leaks-supervisors-c22c2e08` | test fixture process hygiene (`specs/test-throughput/`) | 14b94d3e test(fleet-streamjson): stop the c30 resume from leaking a worker tree (#591) | streamjson suite leaves orphaned supervisors on deleted sandboxes |
| `2026-09-18-doctrine-channel-enum-0be87fd1` | notification channel doctrine (`specs/tower-comms/`) | 549b0405 docs(tower-comms): reconcile the fleet guide and doctrine with the operator queue (#491) | attention-notification-capability.md lists five channels, missing push |
| `2026-09-20-lock-lib-hup-assertion-racy-b7c4e19a` | timing-bound test hardening (`specs/test-throughput/`) | e8595616 test: poll for events instead of asserting timing windows (#709) | test-lock-lib HUP arm is racy: bounded holder can exit 0 before the signal |
| `2026-09-21-wallclock-bounds-fail-under-gate-load-3e81c4d7` | timing-bound test hardening (`specs/test-throughput/`) | e8595616 test: poll for events instead of asserting timing windows (#709) | tower-queue store-lock test pinned a 200ms bound that fails under gate load |
| `2026-09-24-bash32-heredoc-cmdsub-fec5ebfe` | macOS shell portability (`specs/test-throughput/`) | 90e3b4be fix(scripts): make check-no-ci-evals and tower-queue parse under bash 3.2 (#556) | check-no-ci-evals and tower-queue do not parse under macOS bash 3.2 |
| `2026-09-24-bsd-awk-multiline-v-8c364933` | macOS shell portability (`specs/test-throughput/`) | 8e4197c8 fix(scripts): pass multi-line awk values through ENVIRON (#508) | BSD awk rejects newlines in -v values, so spec-validate exits 2 on macOS |
| `2026-09-24-check-no-ci-evals-bash32-ec9904c6` | macOS shell portability (`specs/test-throughput/`) | 90e3b4be fix(scripts): make check-no-ci-evals and tower-queue parse under bash 3.2 (#556) | check-no-ci-evals.sh does not parse under macOS /bin/sh bash 3.2 |
| `2026-09-24-converge-sync-drops-core-sshcommand-fdfd29d7` | the convergence sync fetch (`specs/merge-currency-guard/`) | 1016c135 fix(execute-task): keep the repo's core.sshCommand in the convergence sync fetch (#498) | converge-sync-main exports GIT_SSH_COMMAND over core.sshCommand, losing the configured key |
| `2026-09-24-custom-steps-doc-budget-d6406add` | custom-steps instruction budget (`specs/custom-steps/`) | ad501ac7 feat(execute-task): wire the unit points into /execute-task (#535) | custom-steps.md exceeds the execute-task closure margin; Task 5 needs a diet or raise |
| `2026-09-24-fleet-ci-oversubscription-cc9a73d6` | machine-wide test concurrency (`specs/test-throughput/`) | 75c941a0 feat(test-runner): share one machine-wide ticket pool across test runs (#537) | run-tests.sh -P 15 per worktree oversubscribes the host when workers run CI together |
| `2026-09-25-macos-ci-job-deferred-9d86f51b` | test throughput macOS portability part (`specs/test-throughput/`) | a3ac1fc3 ci: run the awk-sensitive suites on a macOS runner (#614) | Operator decision to fold the macos-awk CI job into test-throughput once bash 3.2 parses |
| `2026-09-25-steps-convergence-unbacked-f319addb` | custom steps (step runner and preamble) (`specs/custom-steps/`) | c63a548a feat(custom-steps): the steps catalog, the point keys, and the resolver (#509) | steps_convergence named in doctrine but absent from defaults, options reference and resolver |
| `2026-09-28-busybox-awk-launch-b326d16a` | test throughput portability part (`specs/test-throughput/`) | e4c36561 ci: get the existing shell suite green on macOS and Alpine (#688) | fleet-streamjson launch fails under busybox awk and no test ran a second awk |
| `2026-09-28-ci-check-aborts-on-first-failure-18a57807` | CI gate layout (`specs/test-throughput/`) | cd9fe5fe ci: split the test suite across three parallel jobs behind one check status (#713) | One mise run check CI job stopped all siblings on the first red guard |
| `2026-09-28-csl-req-a1-3-empty-cancel-9c6abde5` | custom spec location (`specs/custom-spec-location/`) | 5572ecce docs(spec): custom-spec-location amendment, empty spec_root cancels lower layers (#519) | REQ-A1.3 wording said empty falls through; operator ruled empty cancels |
| `2026-09-28-fleet-dispatch-worktree-symlinked-tmpdir-f334f13e` | test throughput portability part (`specs/test-throughput/`) | 14e3ebca test: guard the dispatch and graph tests against a symlinked TMPDIR and a real dot (#783) | test-fleet-dispatch-worktree c24 fails on macOS where TMPDIR resolves via /private/var |
| `2026-09-28-policy-guard-knob-trust-4d2311ea` | human gates policy guard (`specs/human-gates/`) | af2690c9 feat(guards): add the policy guard and the profile floor (#549) | Policy guard must not trust worker-controlled env overrides or worktree config, and must normalize ref shorthand |
| `2026-09-28-tower-queue-bash32-parse-297401ec` | test throughput bash 3.2 parse part (`specs/test-throughput/`) | 90e3b4be fix(scripts): make check-no-ci-evals and tower-queue parse under bash 3.2 (#556) | tower-queue.sh and check-no-ci-evals.sh do not parse under macOS bash 3.2 |
| `2026-09-28-tower-queue-quoted-verbs-7a24c24d` | human gates human gates (`specs/human-gates/`) | 60a5ca19 test(guards): shared reserved-control spelling fixture and the guard gaps it found (#529) | Tower queue verb screens ran before quote removal so quoted spellings slipped through; fixed same PR |
| `2026-09-29-sign-off-trailer-writer-0019638a` | sign-off trailers (`specs/human-gates/`) | dca8ae44 feat(sign-off): record sign-offs in trailers and rebuild the checklist from them (#530) | planwright-commit-trailers.sh emitted only Planwright-Task, not the Sign-Off trailer |
| `2026-09-29-skill-drift-0ef6fc5e` | execute-task convergence wiring (`specs/custom-steps/`) | ad501ac7 feat(execute-task): wire the unit points into /execute-task (#535) | execute-task still resolved the retired review_sequence via a deleted script |
| `2026-09-29-skill-drift-ee18d97c` | execute-task convergence wiring (`specs/custom-steps/`) | ad501ac7 feat(execute-task): wire the unit points into /execute-task (#535) | execute-task convergence section still names review_sequence and its retired resolver |
| `2026-10-01-flight-record-path-767ac037` | custom spec location (`specs/custom-spec-location/`) | dee2dea6 feat(spec-location): migrate the script callers onto the resolved spec root (#548) | flight-dispatch and flight-id hardcoded specs/_flights while the sweep used the resolved spec home |
| `2026-10-01-resolve-steps-task-id-glob-cc3852c6` | custom steps resolver (`specs/custom-steps/`) | c63a548a feat(custom-steps): the steps catalog, the point keys, and the resolver (#509) | PLANWRIGHT_STEP_TASK_IDS split unquoted lets a glob expand before validation |
| `2026-10-01-skill-drift-b0d66c81` | sign-off ritual in skills (`specs/skill-rigor/`) | fffadbe1 feat(skills): sign-off prose in the gate-wired skills (#552) | self-review still named the legacy pending-sign-off subject marker |
| `2026-10-02-bash32-permission-matcher-parse-ebb22bdf` | test throughput bash 3.2 parse part (`specs/test-throughput/`) | 8b38f4a7 fix(tests): make the permission-matcher test parse under bash 3.2 (#567) | test-permission-matcher.sh regressed to fail bash -n under bash 3.2 |
| `2026-10-02-guard-multipoint-resolve-089f3a5d` | custom steps resolver (`specs/custom-steps/`) | 783c2ac6 fix(custom-steps): resolve every point in one pass so the guard fits its deadline (#561) | Worker guard resolving seven points blows its 2s deadline; operator chose a multi-point explain mode |
| `2026-10-02-skill-drift-7c3576ba` | sign-off ritual in skills (`specs/skill-rigor/`) | fffadbe1 feat(skills): sign-off prose in the gate-wired skills (#552) | self-review still named the pending-sign-off bracket marker as the convention |
| `2026-10-02-uutils-mkdir-not-exclusive-3563404f` | shared lock primitive (`specs/universal-binary/`) | c52b8023 feat(locks): adopt the lock holders onto the shared lock primitive (#603) | uutils mkdir is not exclusive, so mkdir-based locks are unreliable on the Linux host |
| `2026-10-03-selector-remote-branch-blind-8ff5cafc` | orchestrate state derivation (`specs/concurrent-orchestrator-coordination/`) | a29b4f1c fix(orchestrate-state): hold a task whose remote branch carries unmerged work (#569) | orchestrate-state read only local task branches and redispatched a task with unmerged remote work |
| `2026-10-04-tmux-command-word-semicolon-d1a812ef` | fleet hardening detached tmux launch (`specs/fleet-hardening/`) | 7fd70ee4 feat(dispatch): launch the tmux worker detached, with its safety arms (#581) | tmux splits argv on words ending in a semicolon, truncating or refusing a launch |
| `2026-10-05-orchestrate-tmux-step3-marker-09fc8006` | orchestrate tmux rung dispatch (`specs/orchestration-fleet/`) | b90590d3 fix(orchestrate): dispatch through the resolved backend, never a silent tmux worker (#853) | orchestrate skill did not say how the tmux rung dispatch composes with steps 3-4 |
| `2026-10-05-seam-discovery-wrapped-launch-a2a3589a` | fleet hardening seam discovery (`specs/fleet-hardening/`) | 2120b87d feat(check): describe the detached tmux launch and guard against the old shape (#589) | Seam discovery matched one physical line, missing backslash-wrapped launches |
| `2026-10-05-streamjson-test-leak-recurs-on-main-44b2795b` | test suite process hygiene (`specs/test-throughput/`) | 14b94d3e test(fleet-streamjson): stop the c30 resume from leaking a worker tree (#591) | test-fleet-streamjson c30 leaks a supervisor, stub and tick tree; suite must reap by sandbox |
| `2026-10-05-tests-leak-into-real-fleet-registry-eebce870` | test suite hygiene (`specs/test-throughput/`) | 9ea089a8 fix(tests): keep fleet test suites out of the operator's real fleet registry (#608) | Tests registered workers into the operator real fleet registry |
| `2026-10-06-f16-mise-config-spellings-5b775475` | worker guard own-branch arm (`specs/worker-permission-ergonomics/`) | 3f103743 feat(worker-guard): self-approval policy, deny-block floor, and the own-branch arm (#691) | REQ-F1.6 lists only some mise config spellings; guard built to it would approve the others |
| `2026-10-06-lock-lib-eperm-path-match-b680d757` | shared lock primitive (`specs/universal-binary/`) | f0d17a05 fix(lock-lib): read a dead lock owner as dead whatever the caller path contains (#597) | lock-lib EPERM match read the script path, so a path with permission never broke stale locks |
| `2026-10-06-quota-handling-amendment-fold-57592829` | quota handling (`specs/quota-handling/`) | 6cbcbbc5 docs(spec): custom-steps amendment 2, expensive checks and quota-handling's amendment (#595) | quota-handling needs a delta to fold in the custom-steps amendment |
| `2026-10-06-run-tests-pool-hang-recurs-69089148` | test runner deadlines (`specs/test-throughput/`) | 30ed5b3c feat(run-tests): end a test file that runs past a per-file deadline (#790) | run-tests-pool hang recurred holding the gate lock; run-tests had no per-test deadline |
| `2026-10-07-full-suite-pool-malformed-value-29a39689` | custom steps pools and full-suite wiring (`specs/custom-steps/`) | 68025a88 feat(execute-task): hold a full_suite_pool slot for every full-suite attempt (#630) | full_suite_pool malformed-value policy was unstated; options row should gain it once wired |
| `2026-10-07-lock-primitive-check-red-on-main-cf833cb4` | the shared lock primitive (`specs/universal-binary/`) | c52b8023 feat(locks): adopt the lock holders onto the shared lock primitive (#603) | check-lock-primitive.sh red on main at a rehearsal-lifecycle mkdir without -p |
| `2026-10-07-ready-guard-tmpdir-slash-f96a686e` | macOS test portability (`specs/test-throughput/`) | e4c36561 ci: get the existing shell suite green on macOS and Alpine (#688) | test-ready-guard fails cd-tracking cases when TMPDIR ends in a slash |
| `2026-10-07-suites-fail-in-worker-env-4b6bad4d` | macOS test portability (`specs/test-throughput/`) | e4c36561 ci: get the existing shell suite green on macOS and Alpine (#688) | Six suites fail on macOS worker sessions from /private/var paths and GNU-only stat -c |
| `2026-10-07-tower-loop-relay-suite-spins-858a9540` | macOS test portability (`specs/test-throughput/`) | e4c36561 ci: get the existing shell suite green on macOS and Alpine (#688) | test-tower-loop-relay hangs on macOS, tower-loop-comms step spinning forever |
| `2026-10-07-worker-yq-screen-gap-1e8250fa` | command guard screens (worker and tower) (`specs/_pending/worker-permission-ergonomics-amendment.md`) | 2a519861 fix(guards): defer more shell expansion and quoting forms (#618) | Worker yq screen lacked jq module and env fixes under Python yq |
| `2026-10-08-test-time-sut-bound-c1f863da` | the CI test-time budget (`specs/test-throughput/`) | cd9fe5fe ci: split the test suite across three parallel jobs behind one check status (#713) | Suite time bound by per-call script cost; needs cheaper scripts or longest-first scheduling |
| `2026-10-09-runner-tests-inherit-report-path-39bb4a8c` | test isolation from the host environment (`specs/test-throughput/`) | c1f873fb test(test-throughput): fix the slow tests' own waits and fixture launches (#705) | Runner tests fail when PLANWRIGHT_TEST_TIMING_REPORT is inherited |
| `2026-10-11-fleet-stop-hold-loop-load-race-5b913f84` | load-sensitive test races (`specs/test-throughput/`) | efa8fae7 test(fleet-stop): wait on a hold marker instead of a transient child in c20 and c43 (#646) | fleet-stop table c20/c43 fail under host load polling a transient child |
| `2026-10-11-fleet-streamjson-c38f-race-b1b91520` | load-sensitive test races (`specs/test-throughput/`) | eef5d8ce test(fleet-streamjson): wait for the set-aside receipt removal in c38f (#649) | test-fleet-streamjson c38f asserts the set-aside file gone before the drain removes it |
| `2026-10-19-busybox-awk-gsub-backslash-566706c9` | portability lints (`specs/universal-binary/`) | e4c36561 ci: get the existing shell suite green on macOS and Alpine (#688) | busybox awk collapses doubled backslash in gsub replacement; use & form |
| `2026-10-19-busybox-awk-quadratic-substr-9d2da3c4` | portability lints (`specs/universal-binary/`) | e4c36561 ci: get the existing shell suite green on macOS and Alpine (#688) | busybox awk per-character substr walks are quadratic; json_top_string rewritten |
| `2026-10-19-busybox-grep-empty-pattern-file-213c4221` | portability lints (`specs/universal-binary/`) | e4c36561 ci: get the existing shell suite green on macOS and Alpine (#688) | busybox grep empty -f file matches all lines; observation-carry fixed |
| `2026-10-19-busybox-timeout-exit-143-b259f9c3` | portability lints (`specs/universal-binary/`) | e4c36561 ci: get the existing shell suite green on macOS and Alpine (#688) | busybox timeout exits 143 not 124; guards now accept both |
| `2026-10-19-excluded-paths-list-9fe89c1e` | the worker permission profile (`specs/worker-permission-ergonomics/`) | 4387acb3 feat(worker-profile): static read-only allow set, first-push rule, and file-tool path denies (#808) | Task 12 Write/Edit denies should mirror the guard's full excluded-name list |
| `2026-10-19-macos-find-silent-nontraversable-7623575f` | the universal binary portability floor (`specs/universal-binary/`) | e4c36561 ci: get the existing shell suite green on macOS and Alpine (#688) | macOS find silently skips mode-400 dirs; spec-store-worktree link scan now checks read-and-enter |
| `2026-10-19-macos-symlinked-tmpdir-fixtures-2101cf5e` | the universal binary portability floor (`specs/universal-binary/`) | 14e3ebca test: guard the dispatch and graph tests against a symlinked TMPDIR and a real dot (#783) | macOS symlinked TMPDIR and case-insensitive FS broke fixtures; fixtures now canonicalize scratch dirs |
| `2026-10-19-multicall-argv0-fixtures-5bffae41` | the universal binary portability floor (`specs/universal-binary/`) | e4c36561 ci: get the existing shell suite green on macOS and Alpine (#688) | busybox applets dispatch on argv0, so exec -a fixtures fail; cleanup-process test now uses bash |
| `2026-10-19-musl-iconv-drops-invalid-utf8-1a1e731f` | the universal binary portability floor (`specs/universal-binary/`) | e4c36561 ci: get the existing shell suite green on macOS and Alpine (#688) | musl iconv drops invalid bytes silently; fleet-messaging now compares the round trip with cmp |
| `2026-10-19-platform-ci-environment-gaps-a4497507` | the universal binary platform CI jobs (`specs/universal-binary/`) | e4c36561 ci: get the existing shell suite green on macOS and Alpine (#688) | Alpine/macOS CI needs container init, full history, PLANWRIGHT_ROOT, pinned toolchain; macOS 3x slower |
| `2026-10-20-substrate-baseline-check-step-4c8462fa` | the substrate baseline capture (`specs/universal-binary/`) | 329eebe0 ci: re-derive the suite time budget, fix the wall-clock capture, and rebalance the test shards (#714) | substrate-baseline wall-clock capture read a CI step that the job split removed |
| `2026-10-25-test-env-plugin-root-leak-18087d21` | fleet dispatch tests (`specs/execution-backends/`) | 14e3ebca test: guard the dispatch and graph tests against a symlinked TMPDIR and a real dot (#783) | test-fleet-dispatch-worktree c29 inherits CLAUDE_PLUGIN_ROOT and PLANWRIGHT_ROOT; test now unsets them |
| `2026-10-26-mc-pane-rule-skill-prose-f3bc9c7a` | the mission-control skill (`specs/mission-control/`) | a2d0ba03 feat(skills): add the mission-control skill (#796) | The never-hand-a-pane relay prose had to land with the Task 11 skill |
| `2026-10-30-selection-contract-v3-exit3-e4efb4d4` | per-task repositories (`specs/invariant-tasks/`) | 2a749470 feat(orchestrate-state): derive each task from its own repository (#770) | selection-contract described exit 3 as a v2 hold only; v3 per-repo withholding unstated |
| `2026-11-04-mc-launch-skips-cadence-a724c17f` | mission control readiness (`specs/mission-control/`) | 0485f4a8 feat(mission-control): catch a skipped verification cadence at readiness (#834) | Ad-hoc launches skipped the verification cadence; step-run audit now catches it at readiness |
| `2026-11-04-mc-panel-inflight-counts-dead-rows-083b73d4` | the mission-control panel (`specs/mission-control/`) | aaa02bb6 fix(mission-control): live in-flight count, no self-handover prompt, /mc-panel toggles (#848) | Panel showed 372 in flight because it counted dead registry rows |
| `2026-11-05-shared-scratch-root-emptied-c7ff1358` | mission control launcher (`specs/mission-control/`) | 99048d08 fix(mission-control): notice planwright updates and warn when a script runs from an older copy (#847) | Retiring a primary-checkout session emptied the shared scratch root; fixed in #841, staleness warning added |

## Duplicates (76)

Each says what the surviving fragment says; consume it alongside the survivor.

| Fragment | Owner | Same as | What it said |
| --- | --- | --- | --- |
| `2026-07-19-check-instructions-configget-forks-e1c0f637` | process-spawn cost in the script layer (`specs/universal-binary/`) | `2026-07-12-config-get-batch-multi-knob-00ffbb2c` | check-instructions forks config-get per knob; batched read would cut test time |
| `2026-07-20-flaky-fleet-throttle-test-7ae1f0aa` | test suite throughput and load robustness (`specs/test-throughput/`) | `2026-07-24-throttle-elapse-test-load-flake-ef2549c2` | test-fleet-throttle elapse re-engage assertion flakes under parallel load |
| `2026-07-20-fleet-throttle-elapse-flake-04ddae50` | test suite throughput and load robustness (`specs/test-throughput/`) | `2026-07-24-throttle-elapse-test-load-flake-ef2549c2` | Throttle elapse assertion flakes under concurrent CPU load |
| `2026-07-20-orchestrate-below-target-after-271-039d2ebb` | instruction budget guard and headroom (`specs/instruction-headroom/`) | `2026-07-23-orchestrate-skill-budget-zero-headroom-5acc5668` | orchestrate fell below 2x target after #271; diet deferred via declared exception |
| `2026-07-20-orchestrate-skill-budget-pressure-081b8ba9` | instruction budget guard and headroom (`specs/instruction-headroom/`) | `2026-07-23-orchestrate-skill-budget-zero-headroom-5acc5668` | orchestrate SKILL.md chronically at budget; wants a real diet |
| `2026-07-20-test-flakiness-7c08a503` | test suite throughput and load robustness (`specs/test-throughput/`) | `2026-07-24-throttle-elapse-test-load-flake-ef2549c2` | Throttle case 33 flakes under 12-way parallel check |
| `2026-07-21-test-throttle-parallel-flake-84d7342c` | test suite throughput and load robustness (`specs/test-throughput/`) | `2026-07-24-throttle-elapse-test-load-flake-ef2549c2` | Throttle anchor-elapse check flakes under parallel harness |
| `2026-07-22-fleet-throttle-elapse-flake-92dbe04f` | test suite throughput and load robustness (`specs/test-throughput/`) | `2026-07-24-throttle-elapse-test-load-flake-ef2549c2` | Throttle elapse assertion failed once under heavy load |
| `2026-07-22-gatekeeper-first-exec-stall-6bd8df61` | test suite throughput and load robustness (`specs/test-throughput/`) | `2026-07-19-dispatch-fetch-review-harness-flake-7f432dea` | macOS Gatekeeper stalls first exec of fresh script inodes, polluting local timings |
| `2026-07-24-check-instructions-invocation-constant-a56e8d33` | process-spawn cost in the script layer (`specs/universal-binary/`) | `2026-07-12-config-get-batch-multi-knob-00ffbb2c` | check-instructions costs ~3.5s per invocation; batched config-get is the lever |
| `2026-07-24-fleet-throttle-elapse-flake-c6c1276b` | test suite throughput and load robustness (`specs/test-throughput/`) | `2026-07-24-throttle-elapse-test-load-flake-ef2549c2` | Throttle elapse flake reproduced on pristine v0.31.0 under load |
| `2026-08-18-worktreecreate-rootcause-correction-16facd5b` | worktree lifecycle hooks (`specs/fleet-lifecycle-closure/`) | `2026-08-18-worktreecreate-root-cause-correction-2036d463` | Same correction: WorktreeCreate hook was a no-op creator, not a 2.1.234 regression. |
| `2026-08-24-worker-settings-plugin-skew-217cc262` | the tower's dispatch surface and its root-skew report (`specs/tower-front-door/`) | `2026-08-18-plugin-version-skew-d4d2236e` | Worker settings resolve the newest plugin cache while the tower runs an older one. |
| `2026-08-26-skill-drift-38f3809f` | review skills' lens-set selection by artifact class (`specs/skill-rigor/`) | `2026-08-25-skill-drift-3672d83d` | Self-review prose walks the code lens set unconditionally, ignoring artifact-class selection. |
| `2026-08-27-streamjson-c12-flaky-1da6c428` | load-flaky fleet test suites (`specs/test-throughput/`) | `2026-08-24-streamjson-flake-under-load-b3b53a4c` | test-fleet-streamjson c12 intermittently flaky under load. |
| `2026-08-27-streamjson-c12-queue-race-c57faff7` | load-flaky fleet test suites (`specs/test-throughput/`) | `2026-08-24-streamjson-flake-under-load-b3b53a4c` | c12 queue-count assertion not synchronous with worker end. |
| `2026-09-02-fleet-throttle-elapse-flake-afa582b8` | load-flaky fleet test suites (`specs/test-throughput/`) | `2026-08-27-flaky-throttle-elapse-under-load-7343b529` | Throttle case 33 fails on main from a wall-clock 3s anchor. |
| `2026-09-02-fleet-throttle-elapse-reanchor-flake-a88ea2a7` | load-flaky fleet test suites (`specs/test-throughput/`) | `2026-08-27-flaky-throttle-elapse-under-load-7343b529` | Throttle case 33 flakes under 12-way load as the anchor elapses. |
| `2026-09-03-contributing-gate-list-stale-211ed22f` | guard enumerations in docs and CI comments (`specs/guard-coverage/`) | `2026-09-03-guard-enumeration-drift-244fe935` | CONTRIBUTING's quality-gate list omits several guards. |
| `2026-09-03-fleet-registration-e8-flake-286d53ee` | load-flaky fleet test suites (`specs/test-throughput/`) | `2026-09-06-registration-e8-fixed-sleep-race-885870b4` | test-fleet-registration e8 fails once under the parallel runner. |
| `2026-09-03-fleet-registration-signal-flake-3d37d244` | load-flaky fleet test suites (`specs/test-throughput/`) | `2026-09-06-registration-e8-fixed-sleep-race-885870b4` | e8 signal-versus-lock timing race under load. |
| `2026-09-05-fleet-register-signal-lock-race-1b8489c5` | load-flaky fleet test suites (`specs/test-throughput/`) | `2026-09-06-registration-e8-fixed-sleep-race-885870b4` | e8 failed once in a full run; not reproducible under CPU load. |
| `2026-09-05-fleet-state-register-term-window-8aa86f22` | load-flaky fleet test suites (`specs/test-throughput/`) | `2026-09-06-registration-e8-fixed-sleep-race-885870b4` | e8 fixed 0.05s sleep races the child's trap arming under load. |
| `2026-09-09-kickoff-lens-yield-on-fresh-draft-9c3cf221` | spec-draft self-critique (`specs/skill-rigor/`) | `2026-09-02-drafting-time-lens-gap-8dcf0f7c` | Kickoff lens pass found ~130 drafting stragglers on a bundle spec-draft reported clean |
| `2026-09-09-skill-drift-0c6b70d0` | the spec-kickoff sign-off lens step (`flight`) | `2026-09-01-skill-drift-b165f3de` | spec-kickoff and kickoff-verification name the code lens table, not artifact-lenses' spec set |
| `2026-09-09-spec-validate-accepts-task-form-deps-caaecaa3` | the spec validator and parse grammar (`specs/format-grammar/`) | `2026-09-09-dependencies-task-prefix-accepted-d7a0c5be` | spec-validate accepts Task-prefixed Dependencies the derivation engine rejects |
| `2026-09-12-scan-secrets-walks-all-refs-d41a85eb` | the secret scan (`specs/guard-coverage/`) | `2026-09-12-gitleaks-scans-sibling-refs-c02198e1` | gitleaks scans all refs so a sibling worktree branch fails every co-located gate |
| `2026-09-12-secret-scan-crosses-worktrees-68489f8e` | the secret scan (`specs/guard-coverage/`) | `2026-09-12-gitleaks-scans-sibling-refs-c02198e1` | Secret scan crosses worktrees; branch-scoped run was clean |
| `2026-09-12-tower-comms-restates-interaction-style-9a749a17` | tower doctrine precedence (`specs/mission-control/`) | `2026-09-24-tower-loads-comms-and-interaction-style-6dd8a4ea` (already archived) | tower-comms.md restates interaction-style rules without citing it |
| `2026-09-17-tower-log-fork-amplification-83013a04` | tower-queue event log cost (`specs/tower-comms/`) | `2026-09-15-tower-queue-log-batch-61e551d2` | Each owed log line re-execs the script; a batch log form would collapse N lock trips |
| `2026-09-18-push-log-roundtrips-50ed8b31` | tower-queue event log cost (`specs/tower-comms/`) | `2026-09-15-tower-queue-log-batch-61e551d2` | Away push pays one log re-exec per item; 200 items take 50-65s |
| `2026-09-22-skill-drift-81947486` | the spec-kickoff sign-off lens step (`flight`) | `2026-09-01-skill-drift-b165f3de` | spec-kickoff names the code lens table, not artifact-lenses' spec set |
| `2026-09-22-skill-drift-c230d859` | the spec-kickoff sign-off lens step (`flight`) | `2026-09-01-skill-drift-b165f3de` | spec-kickoff still names only the code lens table |
| `2026-09-24-doctrine-task-budget-cost-4034976f` | doctrine growth sizing at drafting (`specs/review-effectiveness/`) | `2026-09-13-shared-run-start-doc-growth-15240f38` | Doctrine-amendment task reached execution without a word-cost and funding decision |
| `2026-09-24-skill-drift-4e6c5a33` | skill rigor (skill text drifts) (`specs/skill-rigor/`) | `2026-08-24-skill-drift-8aaa8edf` | spec-draft names only EnterWorktree, which refuses inside an existing worktree session; no enter-by-path arm |
| `2026-09-28-fleet-stop-grace-wait-under-load-98f8245c` | test flakes under load (`specs/test-throughput/`) | `2026-10-01-stop-grace-c20-load-sensitive-42271cfc` | fleet-stop c20 grace wait takes 8s regardless of --grace under load |
| `2026-09-28-release-publish-stale-checkout-3055e69a` | release hardening (`specs/release-hardening/`) | `2026-07-19-release-publish-stale-local-main-04b578da` | release-publish from a stale worktree resolved an old version and silently no-oped |
| `2026-09-28-status-render-task-prefixed-deps-28717640` | parser unification (`specs/format-grammar/`) | `2026-09-09-dependencies-task-prefix-accepted-d7a0c5be` | Status render flags Task N dependency lines malformed while the validator passed them |
| `2026-09-29-echo-safety-utf8-d00e4fe7` | universal binary echo-sanitization class (`specs/universal-binary/`) | `2026-09-18-spec-status-render-mojibake-40dc14ab` | sanitize_printable strips 0x80-0x9F bytes, mangling UTF-8 text; strip C2 80-9F sequences instead |
| `2026-09-29-resolve-primary-git-calls-7a1a56a1` | universal binary perf-spawn-cost class (`specs/universal-binary/`) | `2026-09-25-resolve-root-git-process-count-215d69a9` | resolve-root.sh repo --primary runs about eight git processes on every config read |
| `2026-09-29-verdict-status-shadowing-2e395852` | test suite hygiene guards (`specs/test-throughput/`) | `2026-09-25-verdict-status-substitution-dd0bcf40` | verdict helper in test-step-record.sh defeated by a command substitution in its arguments |
| `2026-10-02-skill-drift-9817e6ef` | currency posture seed item 4 (bundle-level pending flip home) (`specs/_pending/currency-posture-and-drifts.md`) | `2026-09-24-skill-drift-88953874` | spec-kickoff ready-flip refusal arm parks in Awaiting input, which v2 cannot hold |
| `2026-10-02-step-record-concurrent-claim-race-abf3dd06` | custom steps step records (`specs/custom-steps/`) | `2026-10-01-step-record-completion-race-flake-947df862` | test-step-record concurrent-claim cases fail intermittently under load |
| `2026-10-05-queue-lock-wallclock-efe30a67` | test flakes under load (`specs/test-throughput/`) | `2026-09-21-wallclock-bounds-fail-under-gate-load-3e81c4d7` | tower-queue store-lock 2s wall-clock bound failed under load again |
| `2026-10-05-skill-drift-44024827` | currency posture seed item 4 (bundle-level pending flip home) (`specs/_pending/currency-posture-and-drifts.md`) | `2026-09-24-skill-drift-88953874` | spec-kickoff park of a refused spec-PR flip has no valid v2 Awaiting input form |
| `2026-10-06-skill-drift-7cef7116` | skill rigor (kickoff lens pass) (`specs/skill-rigor/`) | `2026-09-01-skill-drift-b165f3de` | Kickoff lens fan-out says one agent per canonical lens without the spec-class lens selection |
| `2026-10-07-backend-at-path-expansion-23643f67` | the operator-level panel-review skill's external backend (outside this repo) (`flight`) | `2026-08-28-panel-backend-at-sigil-mangling-fbf43658` | External backend CLI expands @path tokens in prompts, so a reviewed diff could make it read and upload local files |
| `2026-10-07-guard-double-quote-backslash-e85c7612` | command guard screens (worker and tower) (`specs/_pending/worker-permission-ergonomics-amendment.md`) | `2026-10-05-guard-dq-backslash-dropped-addd719a` | Guards drop every double-quoted backslash; model bash rules so rm screen can accept quoted operands |
| `2026-10-07-sign-off-legacy-label-collision-9979a3b1` | the pending-sign-off checklist and trailers (`specs/human-gates/`) | `2026-10-07-sign-off-id-legacy-collision-1fa24fe0` | Legacy-suffix sign-off commit and numbered PR-body id collide in the checklist |
| `2026-10-07-test-pool-permissive-dir-92e7ff20` | test-slot pool and step pool directory screens (`specs/test-throughput/`) | `2026-09-30-test-pool-loose-mode-5b9a8301` | run-tests.sh accepts group/world-writable pool directory that step-pool.sh refuses |
| `2026-10-08-gate-read-surface-doctrine-05ef7517` | orchestration-concurrency doctrine fetch-before-derive paragraph (`flight`) | `2026-10-07-gate-view-local-main-drift-74e3b833` | Doctrine still says gate tracks checked-out brief, not the remote tip |
| `2026-10-08-inline-sanitizer-c1-range-f7eed13f` | echo safety in script refusal messages (`specs/universal-binary/`) | `2026-09-25-inline-sanitizer-drift-446e3f52` | Three say() helpers strip only C0 and DEL; no guard checks inline sanitizer copies |
| `2026-10-08-skill-drift-b78c25aa` | spec-kickoff ready-flip refusal arm (`specs/kickoff-lifecycle/`) | `2026-09-24-skill-drift-88953874` | Kickoff ready-flip refusal parks in Awaiting input, which v2 forbids |
| `2026-10-09-v2-delta-anchor-park-gap-2db6972c` | spec-draft extend mode and reopen rules (`specs/kickoff-lifecycle/`) | `2026-10-06-skill-drift-5558be0b` | Extending a v2 Ready/Active bundle cannot commit: anchor hook needs a park v2 refuses |
| `2026-10-10-skill-drift-50ecac6f` | spec-draft extend mode and reopen rules (`specs/kickoff-lifecycle/`) | `2026-10-06-skill-drift-5558be0b` | Extending an Active bundle fails anchor hook; extensions flipped Ready to Draft |
| `2026-10-10-skill-drift-d034cecf` | spec-kickoff ready-flip refusal arm (`specs/kickoff-lifecycle/`) | `2026-09-24-skill-drift-88953874` | Pending spec-PR ready-flip park fails validation in v2 Awaiting input |
| `2026-10-10-skill-drift-fb30640a` | spec-draft extend mode and reopen rules (`specs/kickoff-lifecycle/`) | `2026-10-06-skill-drift-5558be0b` | v2 Active extension can only commit by reopening to Draft |
| `2026-10-11-streamjson-c38f-load-race-405de32c` | load-sensitive test races (`specs/test-throughput/`) | `2026-10-11-fleet-streamjson-c38f-race-b1b91520` | c38f recurring load race: journal row before spool removal, no wait |
| `2026-10-11-tower-queue-redact-key-block-adc80d27` | the tower queue log redaction mirror (`specs/tower-comms/`) | `2026-09-15-private-key-redaction-stops-at-header-79cc3210` | tower-queue redact replaces only the key BEGIN marker, keeping the body |
| `2026-10-18-pre-rebase-hook-vs-unpushed-rewrite-ddf5cc81` | githooks backstop vs unpushed_rewrite policy (`specs/human-gates/`) | `2026-10-01-githooks-ignore-unpushed-rewrite-527c973e` | pre-rebase hook rejects all rebases while unpushed_rewrite policy allows them |
| `2026-10-18-tests-mktemp-cd-empty-2af31f42` | test scratch-dir setup (`specs/test-throughput/`) | `2026-09-28-test-mktemp-cwd-cd5efa67` | About 20 tests cd into mktemp output unchecked; bash 3.2 trap may delete caller dir |
| `2026-10-19-bsd-awk-v-newline-afea9ae6` | portability lints (`specs/universal-binary/`) | `2026-09-24-bsd-awk-multiline-v-8c364933` | BSD awk rejects newlines in -v values; any multi-line -v has the defect |
| `2026-10-19-busybox-ps-no-pid-query-29c5ebab` | portability fallback consolidation (`specs/universal-binary/`) | `2026-10-19-portability-fallback-duplication-d18ca2ab` | busybox ps lacks -p and columns; each script carries its own fallback copy |
| `2026-10-25-fleet-stop-grace-timing-under-load-64ca0c18` | test throughput and load-robust tests (`specs/test-throughput/`) | `2026-10-19-load-flaky-latency-windows-45ef46c3` | test-fleet-stop-hl c20 grace comparison collapses under load |
| `2026-10-25-gate-pool-hold-leaks-into-tests-58cdc472` | the step pool runner (`specs/custom-steps/`) | `2026-10-25-step-run-test-inherits-pool-hold-5c7abaa4` | PLANWRIGHT_STEP_POOL_HOLD leaks into the suite and breaks test-step-run.sh |
| `2026-10-25-gate-secret-scan-all-refs-3b81d2da` | the local gate secret scan (`flight`) | `2026-09-12-gitleaks-scans-sibling-refs-c02198e1` | Local gitleaks scans every local ref, so another worker's branch fails your gate |
| `2026-10-25-gate-wallclock-asserts-under-load-004599ef` | test throughput and load-robust tests (`specs/test-throughput/`) | `2026-10-19-load-flaky-latency-windows-45ef46c3` | fleet-stop-sj c20 and guard-steps slow-resolver fail under 15 concurrent gates |
| `2026-10-25-macos-venture-screen-flake-ec77c122` | inception venture secret screen (`specs/inception/`) | `2026-10-18-venture-z16-flake-5b8f73fd` | test-inception-venture Z16 once let an RSA key through the push screen on macOS |
| `2026-10-25-skill-drift-73c5936b` | the spec-draft skill text (`flight`) | `2026-10-06-skill-drift-5558be0b` | spec-draft extend mode omits the anchor re-review park the pre-commit guard requires |
| `2026-10-29-tower-queue-pass-log-cost-e2e498e3` | the tower queue (`specs/tower-comms/`) | `2026-09-15-tower-queue-log-batch-61e551d2` | tower-queue pass_logs re-execs the script per log line, 0.4s per item |
| `2026-10-31-flaky-resolver-deadline-rows-a3b27053` | test throughput and load-robust tests (`specs/test-throughput/`) | `2026-10-19-load-flaky-latency-windows-45ef46c3` | worker-command-guard-steps deadline rows failed under macOS load |
| `2026-11-01-worker-audit-log-profile-deny-2e9cd1a7` | the worker permission profile (`specs/worker-permission-ergonomics/`) | `2026-11-03-worker-allow-audit-log-file-tools-ff4e3890` | Worker file tools can forge the allow-audit log; profile has no deny for it |
| `2026-11-02-holder-alias-dispatch-contradiction-92a85ebd` | per-task repositories (`specs/invariant-tasks/`) | `2026-11-03-holder-alias-decision-51d04d91` | spec-format says tasks may name a holder alias; resolve-work-repo refuses it |
| `2026-11-04-spec-draft-stale-spec-branch-456d02e8` | the spec-draft skill text (`flight`) | `2026-10-06-skill-drift-d115ed2f` | spec-draft recreates its worktree from a stale squash-merged spec branch |
| `2026-11-05-converge-sync-cd-ownership-812fc108` | the policy guard's merge rules (`specs/human-gates/`) | `2026-11-06-converge-sync-no-tier-screen-de7f3222` | converge-sync-main after cd merges main into another unit's branch |
| `2026-11-06-polish-audit-path-unwritable-34e406e0` | the polish handoff record path (`flight`) | `2026-11-04-polish-audit-path-denied-82b9bba0` | polish audit path under worktree .claude/ is denied to dispatched workers |

## Stale (16)

Nothing is left to change for these; each can be consumed with the reason given.

| Fragment | Owner | Superseded by | What it said |
| --- | --- | --- | --- |
| `2026-07-14-global-gitignore-shadows-obs-25b0768e` | observation recording (`specs/observation-recording/`) | Machine-local: the global ~/.gitignore entry is gone; git check-ignore no longer matches new fragments | Global gitignore entry shadowed specs/_observations so new fragments needed git add -f |
| `2026-07-17-orchestrate-closure-budget-ceiling-d41793eb` | instruction budget guard and headroom (`specs/instruction-headroom/`) | closure_error raised (raise\| line in config/instruction-budget-exemptions.txt); figures superseded per 2026-07-29-orchestrate-closure-floor-binds-4bd26e05.md | orchestrate closure at 19999/20000, any addition breaches |
| `2026-07-17-orchestrate-closure-budget-headroom-160f6a6d` | instruction budget guard and headroom (`specs/instruction-headroom/`) | closure_error raised (raise\| line in config/instruction-budget-exemptions.txt); figures superseded per 2026-07-29-orchestrate-closure-floor-binds-4bd26e05.md | orchestrate closure at 19998/20000 after Task 3 marker wiring |
| `2026-07-17-orchestrate-closure-ceiling-63ce4e19` | instruction budget guard and headroom (`specs/instruction-headroom/`) | closure_error raised (raise\| line in config/instruction-budget-exemptions.txt); figures superseded per 2026-07-29-orchestrate-closure-floor-binds-4bd26e05.md | orchestrate closure 19999/20000 forced Task 2 to drop dispatch-env line |
| `2026-07-20-stopconds-fetch-park-path-7003944a` | orchestrate fetch-before-gate prose (`specs/fleet-hardening/`) | ada82fd2 rewrote the Freshness-gate halt row to a pointer (skills/orchestrate/SKILL.md stop-conditions table) | Stop-conditions row omitted the fetch-failure park path |
| `2026-07-23-status-view-render-byte-padding-e449e570` | fleet status view (`specs/execution-backends/`) | Reviewed on PR #315 and deliberately left as-is (sanitizer trade documented in echo-safety.sh) | fleet-status byte padding misaligns and sanitizer mangles some non-ASCII names |
| `2026-07-26-reconcile-note-removal-unowned-473ef7c5` | decided rules over transcribed figures (`specs/anchor-integrity/`) | 21f7341e docs(spec-format): normative parse grammar and taxonomy delta (format-grammar task 5) (#333) landed the extent and the note is gone | Inline reconcile note in spec-format had no owner for deletion |
| `2026-07-26-skill-drift-b7c25788` | skill contract drift (`specs/skill-rigor/`) | Skills now defer to spec-format's sanctioned-form list instead of enumerating halt classes (skills/execute-task/SKILL.md pre-flight step 7) | execute-task and orchestrate enumerate three halt classes, missing the fourth |
| `2026-08-18-worktreecreate-regression-2-1-234-562be3ae` | worktree lifecycle hooks (`specs/fleet-lifecycle-closure/`) | superseded by its own corrections 2036d463/16facd5b and fixed by c3433855 (no WorktreeCreate hook registered) | EnterWorktree failing fleet-wide after CLI 2.1.234, attributed to a harness regression. |
| `2026-09-07-legacy-lock-break-loses-exclusion-909fc5a1` | the shared lock primitive (`specs/universal-binary/`) | 69c8371a feat(locks): one atomic-create advisory lock for the script layer (#458); try_acquire gone, legacy clear is pw_lock_clear_legacy in scripts/lock-lib.sh | fleet-state.sh try_acquire legacy directory break could grant one lock twice under a widened race |
| `2026-09-09-budget-diet-not-reachable-by-dedup-00cf954e` | instruction-budget headroom (`specs/instruction-headroom/`) | recorded as measured-unreachable rung 1 in the raise entry, config/instruction-budget-exemptions.txt (4c37bdc8) | Budget diet unreachable by dedup: two clearest trims recovered 38 words, reverted |
| `2026-09-14-fixed-startup-budget-flakes-under-load-f240fe9c` | fixed-time test waits (`specs/test-throughput/`) | case c20 removed from tests/test-fleet-streamjson.sh (697b3c2b); event waits poll via poll_until (e8595616) | streamjson c20 fixed ten-second wait loses to a busy host |
| `2026-09-20-carry-reports-stranded-while-carrying-9d3f21c4` | the observation carry (`specs/observation-recording/`) | observation-carry.sh output contract (since 5db7badb) defines stranded as the count carried on created/updated; the report misread it | Carry printed stranded 1 on a successful carry, read as a phantom strand |
| `2026-09-21-kickoff-headroom-nearly-spent-7120c520` | operator-dialogue repair lane budget (`specs/operator-dialogue/`) | lane landed: a315418e docs(operator-dialogue): Task 13 acceptance join (#494) | spec-kickoff had 15 words body slack before operator-dialogue Tasks 10 and 11 |
| `2026-09-24-worktree-suffix-echo-9e77fa3f` | fleet-dispatch-worktree warnings (`flight`) | warn() in fleet-dispatch-worktree.sh sanitizes every message (since e079116a), so the raw echo does not occur | Invalid worktree suffix and spec id warnings reach stderr unsanitized |
| `2026-10-07-test-suite-total-budget-headroom-70fb08de` | the CI test-time budget (`specs/test-throughput/`) | suite_total_seconds replaced by per-shard budgets in config/test-time-budget.yml (329eebe0, #714) | Suite total near 91 percent of suite_total_seconds; next growth likely trips it |

## Every fragment by owner

The full routing, one row per fragment, grouped by owner. Status is covered, duplicate, stale or
open; the bundle column names the bundle above that would consume it.

### `specs/test-throughput/` (104)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-12-spec-graph-parallel-flake-222ec0d0` | open | `tt-load-sensitive-tests` |
| `2026-07-19-dispatch-fetch-review-harness-flake-7f432dea` | open | `tt-macos-portability` |
| `2026-07-20-flaky-fleet-throttle-test-7ae1f0aa` | duplicate | `tt-load-sensitive-tests` |
| `2026-07-20-fleet-throttle-elapse-flake-04ddae50` | duplicate | `tt-load-sensitive-tests` |
| `2026-07-20-test-flakiness-7c08a503` | duplicate | `tt-load-sensitive-tests` |
| `2026-07-21-test-throttle-parallel-flake-84d7342c` | duplicate | `tt-load-sensitive-tests` |
| `2026-07-22-fleet-throttle-elapse-flake-92dbe04f` | duplicate | `tt-load-sensitive-tests` |
| `2026-07-22-gatekeeper-first-exec-stall-6bd8df61` | duplicate | `tt-macos-portability` |
| `2026-07-22-local-test-flake-tower-watchdog-784e573a` | open | `tt-load-sensitive-tests` |
| `2026-07-23-streamjson-test-load-flake-23017942` | covered | `tt-load-sensitive-tests` |
| `2026-07-24-fleet-throttle-elapse-flake-c6c1276b` | duplicate | `tt-load-sensitive-tests` |
| `2026-07-24-throttle-elapse-test-load-flake-ef2549c2` | covered | `tt-load-sensitive-tests` |
| `2026-07-26-streamjson-c12-flake-under-load-e4401869` | covered | `tt-load-sensitive-tests` |
| `2026-08-24-streamjson-flake-under-load-b3b53a4c` | covered | `tt-load-sensitive-tests` |
| `2026-08-26-ci-runs-under-live-worker-identity-54d48a47` | covered | `tt-test-env-isolation` |
| `2026-08-27-flaky-suites-under-parallel-load-38dcb4ee` | covered | `tt-load-sensitive-tests` |
| `2026-08-27-flaky-throttle-elapse-under-load-7343b529` | covered | `tt-load-sensitive-tests` |
| `2026-08-27-streamjson-c12-flaky-1da6c428` | duplicate | `tt-load-sensitive-tests` |
| `2026-08-27-streamjson-c12-queue-race-c57faff7` | duplicate | `tt-load-sensitive-tests` |
| `2026-08-28-fleet-streamjson-parallel-flake-9a7f68da` | covered | `tt-load-sensitive-tests` |
| `2026-08-31-allocation-adapt-sigterm-flaky-ab0d3fe9` | covered | `tt-load-sensitive-tests` |
| `2026-09-02-fleet-throttle-elapse-flake-afa582b8` | duplicate | `tt-load-sensitive-tests` |
| `2026-09-02-fleet-throttle-elapse-reanchor-flake-a88ea2a7` | duplicate | `tt-load-sensitive-tests` |
| `2026-09-03-fleet-registration-e8-flake-286d53ee` | duplicate | `tt-load-sensitive-tests` |
| `2026-09-03-fleet-registration-signal-flake-3d37d244` | duplicate | `tt-load-sensitive-tests` |
| `2026-09-05-fleet-register-signal-lock-race-1b8489c5` | duplicate | `tt-load-sensitive-tests` |
| `2026-09-05-fleet-state-register-term-window-8aa86f22` | duplicate | `tt-load-sensitive-tests` |
| `2026-09-06-registration-e8-fixed-sleep-race-885870b4` | open | `tt-load-sensitive-tests` |
| `2026-09-06-suite-load-sensitivity-ea3d8a3e` | covered | `tt-load-sensitive-tests` |
| `2026-09-06-vacuous-absence-checks-elsewhere-6108e668` | covered | `gc-check-vacuity` |
| `2026-09-07-full-gate-fails-one-run-in-four-66ae088f` | open | `tt-gate-signal` |
| `2026-09-07-registration-fixture-leaks-supervisor-4a4796d0` | covered | `tt-test-fixture-reaping` |
| `2026-09-07-streamjson-queue-clear-unproven-e25c7458` | covered | `tt-load-sensitive-tests` |
| `2026-09-09-gate-load-is-a-machine-property-14bf37c8` | open | `tt-gate-signal` |
| `2026-09-09-throttle-reengage-load-sensitive-2211c931` | open | `tt-load-sensitive-tests` |
| `2026-09-12-parallel-units-ignore-suite-cost-0c4456bb` | covered | `tt-host-load-coordination` |
| `2026-09-13-streamjson-test-leaks-supervisors-147b0473` | covered | `tt-test-fixture-reaping` |
| `2026-09-14-fixed-startup-budget-flakes-under-load-f240fe9c` | stale | `tt-load-sensitive-tests` |
| `2026-09-14-streamjson-leak-survives-teardown-fix-47e24470` | open | `tt-test-fixture-reaping` |
| `2026-09-17-streamjson-suite-leaks-supervisors-c22c2e08` | covered | `tt-test-fixture-reaping` |
| `2026-09-20-lock-lib-hup-assertion-racy-b7c4e19a` | covered | `tt-load-sensitive-tests` |
| `2026-09-21-wallclock-bounds-fail-under-gate-load-3e81c4d7` | covered | `tt-load-sensitive-tests` |
| `2026-09-24-bash32-heredoc-cmdsub-fec5ebfe` | covered | `tt-macos-portability` |
| `2026-09-24-bsd-awk-multiline-v-8c364933` | covered | `tt-macos-portability` |
| `2026-09-24-check-no-ci-evals-bash32-ec9904c6` | covered | `tt-macos-portability` |
| `2026-09-24-fleet-ci-oversubscription-cc9a73d6` | covered | `tt-host-load-coordination` |
| `2026-09-24-macos-ci-gap-5de6ed09` | open | `ub-awk-portability` |
| `2026-09-25-macos-ci-job-deferred-9d86f51b` | covered | `ub-awk-portability` |
| `2026-09-25-verdict-status-substitution-dd0bcf40` | open | `gc-check-vacuity` |
| `2026-09-28-busybox-awk-launch-b326d16a` | covered | `ub-awk-portability` |
| `2026-09-28-ci-check-aborts-on-first-failure-18a57807` | covered | `tt-gate-signal` |
| `2026-09-28-fleet-dispatch-worktree-symlinked-tmpdir-f334f13e` | covered | `tt-macos-portability` |
| `2026-09-28-fleet-stop-grace-wait-under-load-98f8245c` | duplicate | `tt-load-sensitive-tests` |
| `2026-09-28-secret-scan-walks-all-refs-5124bd8b` | open | `gc-secret-scan-ref-scope` |
| `2026-09-28-test-mktemp-cwd-cd5efa67` | open | `tt-test-env-isolation` |
| `2026-09-28-tower-queue-bash32-parse-297401ec` | covered | `tt-macos-portability` |
| `2026-09-29-stub-crash-detection-e0adb3f6` | open | `ph-eval-harness` |
| `2026-09-29-verdict-status-shadowing-2e395852` | duplicate | `gc-check-vacuity` |
| `2026-09-30-test-pool-loose-mode-5b9a8301` | open | `tt-test-pool` |
| `2026-10-01-stop-grace-c20-load-sensitive-42271cfc` | open | `tt-load-sensitive-tests` |
| `2026-10-02-bash32-permission-matcher-parse-ebb22bdf` | covered | `tt-macos-portability` |
| `2026-10-02-flight-dispatch-test-sections-fbfcd856` | open | `tt-suite-time-budget` |
| `2026-10-02-sweep-temps-hup-race-under-load-19f0a58a` | open | `tt-load-sensitive-tests` |
| `2026-10-03-test-umask-sensitivity-27562cd7` | open | `tt-test-env-isolation` |
| `2026-10-04-bash-exit-trap-runs-in-forked-child-f2e85ede` | open | `tt-test-fixture-reaping` |
| `2026-10-04-fleet-stop-sj-c20-flaps-under-load-20f62ecc` | open | `tt-load-sensitive-tests` |
| `2026-10-04-queue-log-lock-noclock-load-sensitive-20d69dc2` | open | `tt-load-sensitive-tests` |
| `2026-10-04-run-tests-pool-reclaim-hang-6ed98940` | open | `tt-test-pool` |
| `2026-10-05-flaky-crash-sweep-case-ca9655b2` | open | `tt-load-sensitive-tests` |
| `2026-10-05-fleet-stop-sj-orphan-holds-gate-lock-b11f14ac` | open | `tt-test-fixture-reaping` |
| `2026-10-05-queue-lock-wallclock-efe30a67` | duplicate | `tt-load-sensitive-tests` |
| `2026-10-05-resolve-steps-test-time-2c393630` | open | `tt-suite-time-budget` |
| `2026-10-05-streamjson-test-leak-recurs-on-main-44b2795b` | covered | `tt-test-fixture-reaping` |
| `2026-10-05-test-reap-duplication-226cedca` | open | `tt-test-fixture-reaping` |
| `2026-10-05-tests-leak-into-real-fleet-registry-eebce870` | covered | `tt-test-env-isolation` |
| `2026-10-05-workers-uncoordinated-test-runs-6ee76cba` | open | `tt-host-load-coordination` |
| `2026-10-06-run-tests-pool-hang-recurs-69089148` | covered | `tt-test-pool` |
| `2026-10-06-statusline-render-ceiling-load-flake-9da4c4a8` | open | `tt-load-sensitive-tests` |
| `2026-10-07-pool-dir-screen-duplicated-14f02669` | open | `tt-test-pool` |
| `2026-10-07-ready-guard-tmpdir-slash-f96a686e` | covered | `tt-macos-portability` |
| `2026-10-07-suites-fail-in-worker-env-4b6bad4d` | covered | `tt-macos-portability` |
| `2026-10-07-test-pool-acl-write-35f87a8a` | open | `tt-test-pool` |
| `2026-10-07-test-pool-permissive-dir-92e7ff20` | duplicate | `tt-test-pool` |
| `2026-10-07-test-suite-total-budget-headroom-70fb08de` | stale | `tt-suite-time-budget` |
| `2026-10-07-tower-loop-relay-suite-spins-858a9540` | covered | `tt-macos-portability` |
| `2026-10-08-test-time-sut-bound-c1f863da` | covered | `tt-suite-time-budget` |
| `2026-10-08-tmux-test-isolation-7411f2a4` | open | `tt-test-env-isolation` |
| `2026-10-09-runner-tests-inherit-report-path-39bb4a8c` | covered | `tt-test-env-isolation` |
| `2026-10-11-fleet-stop-hold-loop-load-race-5b913f84` | covered | `tt-load-sensitive-tests` |
| `2026-10-11-fleet-streamjson-c38f-race-b1b91520` | covered | `tt-load-sensitive-tests` |
| `2026-10-11-fleet-sweep-temps-signal-hang-581c7096` | open | `tt-load-sensitive-tests` |
| `2026-10-11-polish-mutation-fanout-load-fe2744fa` | open | `tt-host-load-coordination` |
| `2026-10-11-streamjson-c38f-load-race-405de32c` | duplicate | `tt-load-sensitive-tests` |
| `2026-10-18-gate-under-nohup-hangs-signal-tests-5d41e92b` | open | `tt-host-load-coordination` |
| `2026-10-18-queue-store-lock-lost-writer-7d62ca9f` | open | `tt-load-sensitive-tests` |
| `2026-10-18-tests-mktemp-cd-empty-2af31f42` | duplicate | `tt-test-env-isolation` |
| `2026-10-19-load-flaky-latency-windows-45ef46c3` | open | `tt-load-sensitive-tests` |
| `2026-10-19-meta-select-19d-host-failure-167fcf09` | open | `tt-load-sensitive-tests` |
| `2026-10-25-fleet-stop-grace-timing-under-load-64ca0c18` | duplicate | `tt-load-sensitive-tests` |
| `2026-10-25-gate-lock-order-inversion-ac484ef0` | open | `tt-host-load-coordination` |
| `2026-10-25-gate-wallclock-asserts-under-load-004599ef` | duplicate | `tt-load-sensitive-tests` |
| `2026-10-31-flaky-resolver-deadline-rows-a3b27053` | duplicate | `tt-load-sensitive-tests` |
| `2026-11-01-test-deadline-platform-gaps-9e55a84a` | open | `ub-bounded-run` |
| `2026-11-01-test-deadline-vs-ci-job-timeout-366c0097` | open | `ub-bounded-run` |

### `flight` (82)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-16-parallel-test-runner-07deea2a` | open | `flight-doc-accuracy-sweep` |
| `2026-07-17-req-id-cross-bundle-citations-225257e9` | open | `flight-doc-accuracy-sweep` |
| `2026-07-20-fenced-vs-wrapped-inline-code-spans-148dc028` | open | `flight-doc-accuracy-sweep` |
| `2026-07-20-unqualified-xspec-cites-fh-fa167d02` | open | `flight-doc-accuracy-sweep` |
| `2026-07-22-backend-cli-silent-prompt-drop-03653377` | open | `flight-panel-backend-robustness` |
| `2026-08-19-spec-draft-lint-gap-eca7625e` | open | `flight-precommit-hooks` |
| `2026-08-26-backend-payload-ceiling-361dd7e5` | open | `flight-panel-backend-robustness` |
| `2026-08-26-precommit-markdown-lint-4683c7a9` | open | `flight-precommit-hooks` |
| `2026-08-28-panel-backend-at-sigil-mangling-fbf43658` | open | `flight-panel-backend-robustness` |
| `2026-09-02-fleet-state-field-leading-dash-58dce446` | open | `flight-fleet-script-fixes` |
| `2026-09-03-dotfiles-mas-jobs-time-out-70d056ba` | open | `flight-dotfiles-ci-mas` |
| `2026-09-03-negative-verify-risks-uncommitted-d7a51043` | open | `wpe-scratch-isolation` |
| `2026-09-07-ci-title-lint-cannot-rerun-849e162e` | covered | `gc-workflow-guards` |
| `2026-09-09-skill-drift-0c6b70d0` | duplicate | `sr-lens-artifact-class` |
| `2026-09-09-spec-draft-fold-blind-to-branch-bundles-ab65bbcb` | open | `sr-spec-draft-skill-fixes` |
| `2026-09-12-classify-ci-failure-signal-kill-8cf058ce` | open | `ub-failure-classifiers` |
| `2026-09-13-orchestrate-skill-lock-prose-0c785f8f` | open | `flight-doc-accuracy-sweep` |
| `2026-09-14-guard-test-vacuous-pass-e9f5cc37` | open | `gc-check-vacuity` |
| `2026-09-15-hook-fixtures-predate-envelope-growth-f8ed63da` | open | `gc-guard-test-fixtures` |
| `2026-09-15-tests-inherit-tower-identity-env-17046253` | open | `tt-test-env-isolation` |
| `2026-09-18-bounded-selection-ordering-0299c9fa` | open | `re-drafting-time-lens` |
| `2026-09-18-requirement-self-enumeration-7c83417d` | open | `re-drafting-time-lens` |
| `2026-09-18-spec-status-render-mojibake-40dc14ab` | open | `ub-sanitizer-utf8` |
| `2026-09-22-config-model-no-lists-08213768` | open | `flight-doc-accuracy-sweep` |
| `2026-09-22-deferred-gate-evaluated-at-drain-ab235eb8` | open | `flight-doc-accuracy-sweep` |
| `2026-09-22-skill-drift-81947486` | duplicate | `sr-lens-artifact-class` |
| `2026-09-22-skill-drift-c230d859` | duplicate | `sr-lens-artifact-class` |
| `2026-09-22-unit-glossary-widening-4ae3073b` | open | `flight-doc-accuracy-sweep` |
| `2026-09-23-doctrine-manifest-builder-768ee83e` | open | `gc-doctrine-guards` |
| `2026-09-23-lease-interval-comment-simplified-cc5e2bfb` | open | `flight-doc-accuracy-sweep` |
| `2026-09-24-accumulator-wording-925c8ebc` | open | `flight-doc-accuracy-sweep` |
| `2026-09-24-catalog-warning-raw-ids-621a3631` | open | `ub-output-sanitize` |
| `2026-09-24-plugin-script-invocation-consumer-count-0063be32` | open | `flight-doc-accuracy-sweep` |
| `2026-09-24-ref-probe-corrupt-loose-ref-8cdc142a` | open | `ub-failure-classifiers` |
| `2026-09-24-trailer-length-bound-a118ede3` | open | `hg-sign-off-record` |
| `2026-09-24-worktree-suffix-echo-9e77fa3f` | stale | `ub-output-sanitize` |
| `2026-09-25-custom-steps-tower-forward-declared-ff53f7b2` | open | `flight-doc-accuracy-sweep` |
| `2026-09-28-flight-dispatch-late-signal-traps-ef940689` | open | `flight-fleet-script-fixes` |
| `2026-09-28-isolation-stale-config-get-claim-81a9f77d` | open | `flight-doc-accuracy-sweep` |
| `2026-09-28-resolve-catalog-dash-43966801` | open | `co-catalog-seed-handling` |
| `2026-09-28-secret-screen-callers-5489e2e8` | open | `flight-doc-accuracy-sweep` |
| `2026-09-29-chain-restatements-bbf73358` | open | `flight-doc-accuracy-sweep` |
| `2026-09-29-fleet-registry-read-1a7a5b8f` | open | `flight-fleet-script-fixes` |
| `2026-09-30-streamjson-envelope-write-not-atomic-e42d9722` | open | `eb-streamjson-state-correctness` |
| `2026-10-03-guard-test-core-root-17c5b8bc` | open | `gc-guard-test-fixtures` |
| `2026-10-04-marker-octal-timestamp-5c409b78` | open | `ub-lock-primitive` |
| `2026-10-05-flight-crash-state-leak-e9ed5fd1` | open | `flight-fleet-script-fixes` |
| `2026-10-05-flight-relaunch-unreviewed-52c1e6a4` | open | `flight-fleet-script-fixes` |
| `2026-10-05-flip-point-context-list-620ebb37` | open | `mcg-ready-guard-fixes` |
| `2026-10-05-test-shebang-modes-e2c3f9c2` | open | `gc-lint-scope-gaps` |
| `2026-10-05-watchdog-adversarial-exemption-549528e1` | open | `gc-check-vacuity` |
| `2026-10-06-smoke-live-stale-journal-71a6d363` | open | `tt-test-env-isolation` |
| `2026-10-06-streamjson-recover-drops-cwd-61f61198` | open | `eb-streamjson-state-correctness` |
| `2026-10-06-tower-skill-brief-grace-wording-8030ea8a` | open | `flight-doc-accuracy-sweep` |
| `2026-10-07-backend-at-path-expansion-23643f67` | duplicate | `flight-panel-backend-robustness` |
| `2026-10-07-gate-view-local-main-drift-74e3b833` | open | `ai-spec-text-amendment` |
| `2026-10-08-gate-read-surface-doctrine-05ef7517` | duplicate | `ai-spec-text-amendment` |
| `2026-10-11-research-datasets-not-kept-2e04639d` | open | `re-review-artifact-storage` |
| `2026-10-18-bot-review-request-redraft-7fa57b07` | open | `re-bot-review-fixes` |
| `2026-10-19-flight-sweep-header-e4f08698` | open | `flight-doc-accuracy-sweep` |
| `2026-10-19-help-range-drift-f44855a0` | open | `ih-check-instructions-audit` |
| `2026-10-22-skill-drift-8af6765c` | open | `sr-spec-draft-skill-fixes` |
| `2026-10-25-claude-code-rewrites-hookspath-587db6e6` | open | `hg-githooks-wiring` |
| `2026-10-25-eval-fallback-publish-flag-d3baa9bf` | open | `flight-doc-accuracy-sweep` |
| `2026-10-25-flight-fleet-home-resolvers-dfe038b4` | open | `fh-fleet-home` |
| `2026-10-25-gate-secret-scan-all-refs-3b81d2da` | duplicate | `gc-secret-scan-ref-scope` |
| `2026-10-25-lens-agent-tmp-cleanup-f98747c0` | open | `wpe-scratch-isolation` |
| `2026-10-25-skill-drift-73c5936b` | duplicate | `sr-spec-draft-skill-fixes` |
| `2026-10-26-execute-task-post-pr-reconvergence-5ce6a787` | open | `mcg-convergence-sync` |
| `2026-10-26-flight-rules-d13-citation-f773e633` | open | `flight-doc-accuracy-sweep` |
| `2026-10-26-panel-mod-no-ci-typecheck-6d91e632` | open | `gc-workflow-guards` |
| `2026-10-31-awk-greedy-alternation-b6e5b1b2` | open | `ub-awk-portability` |
| `2026-10-31-script-invocation-sh-rule-quadratic-e6e8462b` | open | `ub-awk-quadratic` |
| `2026-11-01-presence-test-lacks-batch-max-32950e98` | open | `tt-test-env-isolation` |
| `2026-11-02-lock-lib-mint-field-arith-e9e8af52` | open | `ub-lock-primitive` |
| `2026-11-04-manifest-description-positioning-7a636352` | open | `flight-doc-accuracy-sweep` |
| `2026-11-04-polish-audit-path-denied-82b9bba0` | open | `re-review-artifact-storage` |
| `2026-11-04-spec-draft-stale-spec-branch-456d02e8` | duplicate | `sr-spec-draft-skill-fixes` |
| `2026-11-05-precommit-hooks-on-merge-main-82612b46` | open | `flight-precommit-hooks` |
| `2026-11-05-renovate-dependency-bot-f291c49d` | open | `hg-dependency-bot` |
| `2026-11-05-skill-drift-66c6d22e` | open | `sr-spec-draft-skill-fixes` |
| `2026-11-06-polish-audit-path-unwritable-34e406e0` | duplicate | `re-review-artifact-storage` |

### `specs/universal-binary/` (76)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-12-config-get-batch-multi-knob-00ffbb2c` | open | `ub-config-read-cost` |
| `2026-07-19-check-instructions-configget-forks-e1c0f637` | duplicate | `ub-config-read-cost` |
| `2026-07-24-check-instructions-invocation-constant-a56e8d33` | duplicate | `ub-config-read-cost` |
| `2026-08-18-adhoc-config-parsers-2ade3c44` | open | `ub-shared-parsers` |
| `2026-08-25-fleet-audit-lost-update-flake-84cab312` | covered | `ub-lock-primitive` |
| `2026-08-25-git-failure-classification-0cc0726d` | open | `ub-failure-classifiers` |
| `2026-08-26-markdown-table-parsers-16c6a439` | open | `ub-shared-parsers` |
| `2026-08-27-fleet-timing-flakes-under-load-f2e5836e` | covered | `ub-lock-primitive` |
| `2026-09-03-awk-exit-2-not-portable-3f14b24d` | open | `ub-awk-portability` |
| `2026-09-03-mise-toml-parser-seam-7fabca6d` | open | `ub-shared-parsers` |
| `2026-09-04-lock-family-token-crossing-5a664389` | covered | `ub-lock-primitive` |
| `2026-09-04-stale-break-claim-limits-131c97b3` | covered | `ub-lock-primitive` |
| `2026-09-06-consumer-lock-ownership-window-0dab2001` | covered | `ub-lock-primitive` |
| `2026-09-06-echo-safety-helper-gap-c9c109b6` | covered | `ub-output-sanitize` |
| `2026-09-07-attention-unlock-silenced-c1ed7ea1` | covered | `ub-lock-primitive` |
| `2026-09-07-legacy-lock-break-loses-exclusion-909fc5a1` | stale | `ub-lock-primitive` |
| `2026-09-08-marketplace-copy-strips-exec-bit-a826597a` | open | `ub-portability-helpers` |
| `2026-09-12-config-read-cost-on-hot-paths-7f14ddc3` | open | `ub-config-read-cost` |
| `2026-09-13-detached-hold-token-handoff-bf2a4835` | covered | `ub-lock-primitive` |
| `2026-09-13-lock-consumer-token-adoption-39b354f3` | covered | `ub-lock-primitive` |
| `2026-09-14-ledger-append-fencing-51fe1178` | open | `ub-lock-primitive` |
| `2026-09-24-resolve-steps-spawn-cost-66cad29f` | open | `ub-config-read-cost` |
| `2026-09-25-inline-sanitizer-drift-446e3f52` | open | `ub-sanitizer-utf8` |
| `2026-09-25-resolve-root-git-process-count-215d69a9` | open | `ub-perf-fleet-scripts` |
| `2026-09-26-resolve-catalog-combined-view-d88b29b7` | open | `ub-config-read-cost` |
| `2026-09-28-frame-check-memory-e032ecc5` | open | `ub-awk-quadratic` |
| `2026-09-28-policy-knob-read-cost-3712fe34` | open | `ub-config-read-cost` |
| `2026-09-28-spec-root-resolve-cost-daf252ea` | open | `ub-config-read-cost` |
| `2026-09-29-echo-safety-utf8-d00e4fe7` | duplicate | `ub-sanitizer-utf8` |
| `2026-09-29-resolve-primary-git-calls-7a1a56a1` | duplicate | `ub-perf-fleet-scripts` |
| `2026-09-30-lock-lib-acquire-cost-8e2196a3` | open | `ub-perf-fleet-scripts` |
| `2026-10-02-allocation-adapt-chain-cost-89ef0502` | open | `ma-allocation-scripts-refactor` |
| `2026-10-02-fleet-script-spawn-cost-8880747e` | open | `ub-perf-fleet-scripts` |
| `2026-10-02-guard-hook-spawn-cost-ee336bb5` | open | `wpe-guard-tokenizer-fidelity` |
| `2026-10-02-macos-exec-cost-multiplier-eba0d568` | open | `ub-perf-fleet-scripts` |
| `2026-10-02-orchestration-reader-spawn-cost-3e069cd6` | open | `ub-perf-orchestration-readers` |
| `2026-10-02-resolve-steps-flight-dispatch-cost-dc62fddd` | open | `ub-config-read-cost` |
| `2026-10-02-streamjson-fixed-poll-tick-953df56d` | open | `ub-perf-fleet-scripts` |
| `2026-10-02-tower-queue-spawn-cost-dcdd1bca` | open | `tc-tower-queue-perf` |
| `2026-10-02-uutils-mkdir-not-exclusive-3563404f` | covered | `ub-lock-primitive` |
| `2026-10-06-echo-discipline-guard-cost-156e3730` | open | `gc-check-cost` |
| `2026-10-06-lock-lib-eperm-path-match-b680d757` | covered | `ub-lock-primitive` |
| `2026-10-07-duration-seconds-converters-4b066908` | open | `ub-portability-helpers` |
| `2026-10-07-lock-primitive-check-red-on-main-cf833cb4` | covered | `ub-lock-primitive` |
| `2026-10-07-refusal-paths-raw-control-bytes-79fd17ed` | open | `ub-output-sanitize` |
| `2026-10-08-inline-sanitizer-c1-range-f7eed13f` | duplicate | `ub-output-sanitize` |
| `2026-10-09-fleet-lock-release-rc-a3d7081f` | open | `ub-lock-primitive` |
| `2026-10-09-fleet-lock-tokenless-guard-2ad93ace` | open | `ub-lock-primitive` |
| `2026-10-11-utc-iso-date-r-reads-a-file-7107ff66` | open | `ub-portability-helpers` |
| `2026-10-19-bash32-command-exec-unwind-2851a1cd` | open | `ub-bash32-lints` |
| `2026-10-19-bounded-run-residuals-a6aa0e60` | open | `ub-bounded-run` |
| `2026-10-19-bsd-awk-v-newline-afea9ae6` | duplicate | `ub-bash32-lints` |
| `2026-10-19-busybox-awk-gsub-backslash-566706c9` | covered | `ub-bash32-lints` |
| `2026-10-19-busybox-awk-quadratic-substr-9d2da3c4` | covered | `ub-bash32-lints` |
| `2026-10-19-busybox-grep-empty-pattern-file-213c4221` | covered | `ub-bash32-lints` |
| `2026-10-19-busybox-procfs-snapshot-cost-2081ef7f` | open | `ub-portability-helpers` |
| `2026-10-19-busybox-ps-no-pid-query-29c5ebab` | duplicate | `ub-portability-helpers` |
| `2026-10-19-busybox-timeout-exit-143-b259f9c3` | covered | `ub-bash32-lints` |
| `2026-10-19-dash-quoted-heredoc-multibyte-07ad50fe` | open | `ub-bash32-lints` |
| `2026-10-19-guards-need-timeout-binary-48f1c5a9` | open | `ub-bounded-run` |
| `2026-10-19-macos-find-silent-nontraversable-7623575f` | covered | `tt-macos-portability` |
| `2026-10-19-macos-symlinked-tmpdir-fixtures-2101cf5e` | covered | `tt-macos-portability` |
| `2026-10-19-multicall-argv0-fixtures-5bffae41` | covered | `tt-macos-portability` |
| `2026-10-19-musl-iconv-drops-invalid-utf8-1a1e731f` | covered | `tt-macos-portability` |
| `2026-10-19-oracle-grace-ladder-fixed-28cc00af` | open | `ub-perf-fleet-scripts` |
| `2026-10-19-platform-ci-environment-gaps-a4497507` | covered | `tt-macos-portability` |
| `2026-10-19-portability-fallback-duplication-d18ca2ab` | open | `ub-portability-helpers` |
| `2026-10-19-procfs-fallbacks-untested-on-glibc-87b4dbcd` | open | `ub-portability-helpers` |
| `2026-10-19-streamjson-json-input-quadratic-4880ede2` | open | `ub-awk-quadratic` |
| `2026-10-20-substrate-baseline-check-step-4c8462fa` | covered | `tt-gate-signal` |
| `2026-10-25-bash32-mapfile-unguarded-b680f07c` | open | `ub-bash32-lints` |
| `2026-10-25-busybox-awk-unbalanced-ere-c6c412bb` | open | `ub-awk-portability` |
| `2026-10-25-smoke-allowlist-mktemp-44ab5e8b` | open | `ub-portability-helpers` |
| `2026-10-25-step-record-sha256-perl-5588599b` | open | `cs-script-hardening` |
| `2026-11-01-verdict-span-number-copy-815143aa` | open | `gc-check-vacuity` |
| `2026-11-02-bakeoff-fixture-post-state-090bc4d1` | open | `ub-lock-primitive` |

### `specs/instruction-headroom/` (51)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-17-budget-exemption-diff-guard-56d4b375` | open | `ih-budget-guard-edges` |
| `2026-07-17-orchestrate-closure-budget-ceiling-d41793eb` | stale | `ih-orchestrate-diet` |
| `2026-07-17-orchestrate-closure-budget-headroom-160f6a6d` | stale | `ih-orchestrate-diet` |
| `2026-07-17-orchestrate-closure-ceiling-63ce4e19` | stale | `ih-orchestrate-diet` |
| `2026-07-18-cross-skill-convention-budget-collision-bae4922f` | open | `ih-section-manifests` |
| `2026-07-19-declared-exception-dormant-stale-c70484d6` | open | `ih-budget-guard-edges` |
| `2026-07-19-floor-zero-noop-headroom-design-q-3e8a5d60` | open | `ih-budget-guard-edges` |
| `2026-07-19-knob-value-leading-zero-octal-97dc8742` | open | `ih-budget-guard-edges` |
| `2026-07-19-raise-staleness-value-mismatch-705d0d11` | open | `ih-budget-guard-edges` |
| `2026-07-19-raise-value-non-integer-parse-8fdca68f` | open | `ih-budget-guard-edges` |
| `2026-07-19-skill-headroom-ceiling-6ee8bb6f` | open | `ih-orchestrate-diet` |
| `2026-07-20-diet-example-fidelity-972182f6` | open | `ih-diet-fidelity-doctrine` |
| `2026-07-20-orchestrate-below-target-after-271-039d2ebb` | duplicate | `ih-orchestrate-diet` |
| `2026-07-20-orchestrate-skill-budget-pressure-081b8ba9` | duplicate | `ih-orchestrate-diet` |
| `2026-07-23-orchestrate-skill-budget-headless-ff91ed4e` | open | `ih-orchestrate-diet` |
| `2026-07-23-orchestrate-skill-budget-zero-headroom-5acc5668` | open | `ih-orchestrate-diet` |
| `2026-07-27-ctxeng-constraint-density-79a5adbc` | open | `ih-check-instructions-audit` |
| `2026-07-27-ctxeng-doctor-crosscheck-2fef2d70` | open | `ih-check-instructions-audit` |
| `2026-07-27-ctxeng-grammar-vs-judgment-examples-cba0413b` | open | `ih-diet-fidelity-doctrine` |
| `2026-07-27-ctxeng-no-repo-claude-md-ab878b9e` | open | `ih-repo-claude-md` |
| `2026-07-27-ctxeng-principle-ladder-rung-222e4477` | open | `ih-diet-fidelity-doctrine` |
| `2026-07-27-ctxeng-restatement-detector-ff8f7659` | open | `ih-check-instructions-audit` |
| `2026-07-27-ctxeng-review-skill-frontload-d2abb33d` | covered | `ih-skill-relief` |
| `2026-07-27-ctxeng-section-scoped-gate-97e811db` | open | `ih-check-instructions-audit` |
| `2026-07-27-ctxeng-skill-description-surface-34cae1db` | open | `ih-check-instructions-audit` |
| `2026-07-27-ctxeng-source-set-a345a39b` | open | `ih-diet-fidelity-doctrine` |
| `2026-07-27-ctxeng-specformat-exemplar-d43920a7` | open | `pending-spec-format-v3-text` |
| `2026-07-27-ctxeng-unmeasured-read-surface-06c9b767` | open | `ih-check-instructions-audit` |
| `2026-07-29-orchestrate-closure-floor-binds-4bd26e05` | open | `ih-check-instructions-audit` |
| `2026-08-18-instruction-headroom-zero-slack-fb7cd43e` | open | `ih-check-instructions-audit` |
| `2026-08-25-execute-task-headroom-fd0d5252` | open | `ih-skill-relief` |
| `2026-08-25-floor-doc-headroom-fc5bc12e` | open | `ih-skill-relief` |
| `2026-08-26-closure-headroom-operator-dialogue-eb4d0437` | open | `ih-skill-relief` |
| `2026-08-28-check-instructions-red-on-main-4a3e2947` | covered | `ih-skill-relief` |
| `2026-09-03-instruction-headroom-spec-kickoff-0fb9193a` | open | `ih-skill-relief` |
| `2026-09-03-kickoff-headroom-exhausted-a3abf3ba` | open | `ih-skill-relief` |
| `2026-09-05-orchestrate-skill-headroom-14d6ef9f` | open | `ih-skill-relief` |
| `2026-09-07-orchestrate-closure-headroom-spent-37c2711e` | covered | `ih-orchestrate-diet` |
| `2026-09-09-budget-diet-not-reachable-by-dedup-00cf954e` | stale | `ih-orchestrate-diet` |
| `2026-09-09-capped-charge-hides-real-load-4fbf9ceb` | open | `ih-budget-guard-edges` |
| `2026-09-09-doc-granular-manifests-root-cause-ebc0399c` | open | `ih-section-manifests` |
| `2026-09-09-every-budget-exception-sits-at-its-floor-8905e6b9` | covered | `ih-orchestrate-diet` |
| `2026-09-09-headroom-grammar-gained-a-margin-cf2be99f` | open | `ih-budget-guard-edges` |
| `2026-09-09-meta-spec-versioning-charged-to-all-164e9b67` | open | `pending-spec-format-v3-text` |
| `2026-09-12-budget-raise-layer-split-c1787387` | open | `ih-budget-guard-edges` |
| `2026-09-13-trim-dropped-fifteen-rules-f03a7e23` | open | `ih-section-manifests` |
| `2026-09-21-closure-raise-slack-unreserved-9f70803a` | open | `ih-budget-guard-edges` |
| `2026-09-21-safety-floor-two-readings-d20e8988` | open | `ih-diet-fidelity-doctrine` |
| `2026-09-24-guard-catalog-start-load-b3d6d8f7` | open | `ih-skill-relief` |
| `2026-10-11-doctrine-amendment-citations-b0050848` | open | `pending-spec-format-v3-text` |
| `2026-10-26-tower-start-load-headroom-d2d09c79` | open | `ih-skill-relief` |

### `specs/format-grammar/` (39)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-21-release-hardening-malformed-deps-5ec1f447` | open | `fg-dependency-grammar` |
| `2026-07-22-restructure-tasks-grammar-copies-319e3472` | open | `fg-spec-parse-lib` |
| `2026-07-24-gate-multi-atom-parse-097e7cea` | covered | `fg-drain-gates` |
| `2026-07-24-gate-status-lifecycle-7cc5a87e` | covered | `fg-drain-gates` |
| `2026-07-24-spec-graph-no-version-parse-40249bf9` | open | `fg-spec-parse-lib` |
| `2026-07-24-status-parse-stragglers-6d0f2cd0` | open | `fg-spec-parse-lib` |
| `2026-07-26-format-grammar-e13-preempted-a0bfb440` | open | `fg-spec-parse-lib` |
| `2026-07-26-orchestrate-select-nul-screen-fail-open-fbc28fbc` | open | `fg-spec-parse-lib` |
| `2026-08-18-inception-task17-malformed-deps-30c1ce7c` | open | `fg-dependency-grammar` |
| `2026-08-18-validator-blind-to-bodyless-header-a74b7e47` | open | `fg-validator-fixes` |
| `2026-08-24-check-ledger-fence-blind-509a6760` | open | `fg-spec-parse-lib` |
| `2026-08-24-header-block-fence-interaction-46449c71` | open | `fg-spec-parse-lib` |
| `2026-08-25-anchor-guard-sweep-overlap-b254d263` | open | `fg-spec-parse-lib` |
| `2026-08-25-changelog-scan-fence-blind-5f6d0739` | open | `fg-spec-parse-lib` |
| `2026-08-25-exec-pointer-crlf-264e1881` | open | `fg-validator-fixes` |
| `2026-08-25-line80-reader-stragglers-b492ac85` | open | `fg-spec-parse-lib` |
| `2026-08-25-spec-model-header-straggler-e306034b` | open | `fg-spec-parse-lib` |
| `2026-08-25-spec-validate-baseline-tip-79638b29` | open | `fg-validator-fixes` |
| `2026-08-25-test-spec-multi-req-heading-a682c3fc` | open | `fg-spec-model-parse` |
| `2026-08-26-drain-manual-lane-bookkeeping-82b59dca` | open | `fg-drain-gates` |
| `2026-08-26-inception-last-reviewed-key-e57b5a39` | open | `fg-spec-parse-lib` |
| `2026-08-26-taxonomy-manual-lane-undocumented-a678d2a5` | open | `fg-drain-gates` |
| `2026-09-03-bold-date-changelog-entries-dd7591f9` | open | `fg-changelog-grammar` |
| `2026-09-03-dead-path-check-on-expression-edits-3e0a9b05` | open | `fg-changelog-grammar` |
| `2026-09-03-spec-format-validator-list-lags-f3ec7760` | open | `fg-validator-fixes` |
| `2026-09-09-dependencies-task-prefix-accepted-d7a0c5be` | open | `fg-dependency-grammar` |
| `2026-09-09-spec-validate-accepts-task-form-deps-caaecaa3` | duplicate | `fg-dependency-grammar` |
| `2026-09-09-spec-validate-baseline-short-circuit-fd394e79` | open | `fg-dependency-grammar` |
| `2026-09-12-malformed-core-seed-degradation-7427255e` | open | `co-catalog-seed-handling` |
| `2026-09-20-parked-in-prose-invisible-to-selector-0302098b` | open | `fg-parked-task-visibility` |
| `2026-09-22-spec-model-citations-continuation-8131215d` | open | `fg-spec-model-parse` |
| `2026-09-22-spec-validate-task-pins-eadbda66` | open | `fg-dependency-grammar` |
| `2026-09-28-amendment-supersede-vs-in-place-5f275034` | open | `pending-spec-format-v3-text` |
| `2026-09-28-options-check-flat-reader-61161b12` | open | `ub-shared-parsers` |
| `2026-09-28-status-render-task-prefixed-deps-28717640` | duplicate | `fg-dependency-grammar` |
| `2026-10-08-spec-parse-rewriter-form-71a53be3` | open | `fg-spec-parse-lib` |
| `2026-10-18-spec-parse-fenced-slice-96b681b4` | open | `fg-spec-parse-lib` |
| `2026-10-19-function-scoped-fence-exemptions-5a654cca` | open | `fg-spec-parse-lib` |
| `2026-11-03-brief-prose-class-label-da1f33ac` | open | `fg-spec-model-parse` |

### `specs/custom-steps/` (36)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-09-24-backend-resume-stop-caps-9d227d02` | open | `eb-step-backend-composition` |
| `2026-09-24-check-mode-attended-synopsis-d1fce56b` | open | `cs-spec-amendment` |
| `2026-09-24-convergence-continue-pr-stop-588f099a` | open | `cs-spec-amendment` |
| `2026-09-24-custom-steps-doc-budget-d6406add` | covered | `ih-orchestrate-diet` |
| `2026-09-24-custom-steps-doc-open-points-60f1e9b9` | open | `cs-spec-amendment` |
| `2026-09-24-preamble-slash-invocation-3a3a9593` | open | `cs-spec-amendment` |
| `2026-09-24-step-script-usage-headers-8cc8c963` | open | `cs-spec-amendment` |
| `2026-09-24-step-subprocess-guard-gap-9a4dd2c8` | open | `cs-spec-amendment` |
| `2026-09-24-step-tables-test-gaps-35e89205` | open | `cs-spec-amendment` |
| `2026-09-24-stopped-waiting-concurrent-edits-ec41922e` | open | `cs-spec-amendment` |
| `2026-09-25-steps-convergence-unbacked-f319addb` | covered | `cs-spec-amendment` |
| `2026-09-26-session-line-runs-location-b947acf7` | open | `cs-spec-amendment` |
| `2026-09-29-skill-drift-0ef6fc5e` | covered | `cs-spec-amendment` |
| `2026-09-29-skill-drift-ee18d97c` | covered | `cs-spec-amendment` |
| `2026-09-29-step-record-screen-shim-a4e118cb` | open | `cs-script-hardening` |
| `2026-10-01-resolve-steps-task-id-glob-cc3852c6` | covered | `cs-script-hardening` |
| `2026-10-01-step-record-completion-race-flake-947df862` | open | `tt-load-sensitive-tests` |
| `2026-10-02-guard-multipoint-resolve-089f3a5d` | covered | `cs-script-hardening` |
| `2026-10-02-step-record-concurrent-claim-race-abf3dd06` | duplicate | `tt-load-sensitive-tests` |
| `2026-10-06-echo-safety-task-renamed-ed7ccf68` | open | `cs-spec-amendment` |
| `2026-10-06-flip-evidence-hook-gate-7d1c91ee` | open | `cs-spec-amendment` |
| `2026-10-07-full-suite-pool-malformed-value-29a39689` | covered | `cs-spec-amendment` |
| `2026-10-07-pool-holder-worktree-in-park-95cabcd5` | open | `cs-spec-amendment` |
| `2026-10-07-refire-reuse-ordering-open-points-931bad4e` | open | `cs-spec-amendment` |
| `2026-10-07-resume-continuation-open-points-59356c25` | open | `cs-spec-amendment` |
| `2026-10-07-steps-upgrade-before-config-undocumented-745dac47` | open | `cs-spec-amendment` |
| `2026-10-10-custom-steps-flight-deferral-addressed-080b28d6` | open | `cs-spec-amendment` |
| `2026-10-11-panel-step-timeout-5f46acd5` | open | `flight-panel-backend-robustness` |
| `2026-10-12-step-record-preexisting-git-env-4cea925c` | open | `gc-guard-test-fixtures` |
| `2026-10-17-custom-steps-stale-deferred-e2420dea` | open | `cs-spec-amendment` |
| `2026-10-18-custom-steps-test-spec-transitional-0f23ebf1` | open | `cs-spec-amendment` |
| `2026-10-18-full-suite-unpooled-cause-unrecorded-63fdc8ff` | open | `cs-spec-amendment` |
| `2026-10-18-refire-rows-first-run-gap-cf01e13e` | open | `cs-spec-amendment` |
| `2026-10-19-gate-pool-wait-expiry-4d47cc6b` | open | `tt-host-load-coordination` |
| `2026-10-25-gate-pool-hold-leaks-into-tests-58cdc472` | duplicate | `tt-test-env-isolation` |
| `2026-10-25-step-run-test-inherits-pool-hold-5c7abaa4` | open | `tt-test-env-isolation` |

### `specs/guard-coverage/` (35)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-19-glob-scan-json-format-assumption-025baab3` | open | `gc-guard-scan-gaps` |
| `2026-07-22-commit-msg-hook-layer-boundary-2076522e` | open | `hg-githooks-wiring` |
| `2026-07-22-req-a13-wire-phrase-ambiguity-365fbbd0` | open | `gc-spec-amendment` |
| `2026-07-24-split-stales-cross-spec-test-refs-e347c573` | open | `gc-lint-scope-gaps` |
| `2026-07-24-straggler-triage-measured-wrong-platform-ce2f762f` | covered | `tt-suite-time-budget` |
| `2026-07-24-suite-stragglers-beyond-triage-f4306a0a` | covered | `tt-suite-time-budget` |
| `2026-07-26-workflow-run-step-lint-gap-27a7cb3f` | open | `gc-workflow-guards` |
| `2026-07-27-ctxeng-knob-semantics-doubled-addc8dee` | open | `gc-options-reference-integrity` |
| `2026-08-24-purged-guard-cost-37e8db32` | open | `gc-check-cost` |
| `2026-08-26-generated-artifacts-unlinted-8c6fdca5` | covered | `gc-lint-scope-gaps` |
| `2026-08-26-link-check-github-md-11f65c68` | open | `gc-lint-scope-gaps` |
| `2026-08-28-purged-guard-low-entropy-false-positive-bb99645c` | open | `gc-check-cost` |
| `2026-08-28-purged-guard-maxwords-floor-fd55ba86` | covered | `gc-check-cost` |
| `2026-09-01-purged-screen-remedy-4e9669df` | open | `gc-check-cost` |
| `2026-09-02-doctrine-index-citation-drift-587d7d7b` | open | `gc-doctrine-guards` |
| `2026-09-02-posture-guard-checkout-blind-637088a8` | open | `gc-workflow-guards` |
| `2026-09-02-workflow-shell-unlinted-2865c193` | open | `gc-workflow-guards` |
| `2026-09-03-cdpath-guard-residual-limits-f7a90c3d` | open | `gc-guard-scan-gaps` |
| `2026-09-03-contributing-gate-list-stale-211ed22f` | duplicate | `flight-doc-accuracy-sweep` |
| `2026-09-03-guard-enumeration-drift-244fe935` | open | `flight-doc-accuracy-sweep` |
| `2026-09-06-awk-guard-cost-13b74212` | open | `gc-check-cost` |
| `2026-09-06-guard-assertion-4-originating-repository-e27d4051` | open | `gc-spec-amendment` |
| `2026-09-12-fixture-readmes-unlinted-22e17f16` | open | `gc-lint-scope-gaps` |
| `2026-09-12-gitleaks-scans-sibling-refs-c02198e1` | open | `gc-secret-scan-ref-scope` |
| `2026-09-12-planwright-yml-unlinted-3a7a7756` | open | `gc-lint-scope-gaps` |
| `2026-09-12-scan-secrets-walks-all-refs-d41a85eb` | duplicate | `gc-secret-scan-ref-scope` |
| `2026-09-12-secret-scan-crosses-worktrees-68489f8e` | duplicate | `gc-secret-scan-ref-scope` |
| `2026-09-23-options-tether-knob-table-scope-3c4e591c` | open | `gc-options-reference-integrity` |
| `2026-10-05-hook-run-fixtures-inherit-git-env-d34a2f02` | open | `gc-guard-test-fixtures` |
| `2026-10-07-spellings-mcp-glob-model-05ec412b` | open | `hg-reserved-control-spellings` |
| `2026-10-11-mise-trust-bypass-in-guards-741191b4` | open | `gc-guard-test-fixtures` |
| `2026-10-11-pathspec-env-guard-bc6e58ee` | open | `gc-guard-test-fixtures` |
| `2026-10-18-purge-scan-window-cost-72304961` | open | `gc-check-cost` |
| `2026-10-18-purge-seed-misses-wrapped-phrases-3e0b1d64` | open | `gc-check-cost` |
| `2026-10-31-guard-lexer-review-yield-47e8a423` | open | `newspec-command-guard-lib` |

### `specs/human-gates/` (33)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-09-28-dependency-bot-class-merge-5ef997a5` | open | `hg-dependency-bot` |
| `2026-09-28-policy-guard-knob-trust-4d2311ea` | covered | `hg-policy-guard-shell-semantics` |
| `2026-09-28-reserved-control-open-vectors-5d886bf9` | open | `hg-reserved-control-spellings` |
| `2026-09-28-tower-queue-quoted-verbs-7a24c24d` | covered | `hg-reserved-control-spellings` |
| `2026-09-29-sign-off-trailer-writer-0019638a` | covered | `hg-sign-off-record` |
| `2026-10-01-githooks-ignore-unpushed-rewrite-527c973e` | open | `hg-githooks-wiring` |
| `2026-10-01-sign-off-checklist-two-generators-2dc85dbb` | open | `hg-sign-off-record` |
| `2026-10-07-hook-command-nul-byte-85f0b73d` | open | `mcg-ready-guard-fixes` |
| `2026-10-07-sign-off-id-legacy-collision-1fa24fe0` | open | `hg-sign-off-record` |
| `2026-10-07-sign-off-legacy-label-collision-9979a3b1` | duplicate | `hg-sign-off-record` |
| `2026-10-08-sign-off-checklist-squash-ancestry-89426779` | open | `hg-sign-off-record` |
| `2026-10-11-base-sync-remedy-wording-03051cea` | open | `hg-currency-and-remedy-text` |
| `2026-10-11-checklist-omits-legacy-marker-b1f24036` | open | `hg-sign-off-record` |
| `2026-10-11-policy-env-override-1406dc79` | open | `hg-policy-guard-shell-semantics` |
| `2026-10-11-zone-pause-vs-signed-tasks-c7a1d483` | open | `hg-spec-amendment` |
| `2026-10-12-mcg-currency-knob-more-restatements-f02cd82a` | open | `hg-currency-and-remedy-text` |
| `2026-10-12-mcg-currency-knob-sibling-restatements-2b0ceaef` | open | `hg-currency-and-remedy-text` |
| `2026-10-18-human-gates-zone-restatements-421e62ef` | open | `hg-reserved-control-spellings` |
| `2026-10-18-policy-guard-retired-phrase-a8031a3e` | open | `hg-reserved-control-spellings` |
| `2026-10-18-polish-untrailered-signoff-729ee951` | open | `hg-sign-off-record` |
| `2026-10-18-pre-rebase-hook-vs-unpushed-rewrite-ddf5cc81` | duplicate | `hg-githooks-wiring` |
| `2026-10-31-policy-guard-merge-false-positive-b154e005` | open | `hg-policy-guard-merge-detection` |
| `2026-11-04-spec-kickoff-push-vs-policy-guard-04bcb01a` | open | `mc-launch-kinds` |
| `2026-11-05-converge-sync-cd-ownership-812fc108` | duplicate | `hg-policy-guard-merge-detection` |
| `2026-11-05-human-gates-a16-test-spec-stale-4103c556` | open | `hg-spec-amendment` |
| `2026-11-05-human-gates-defaults-ergonomics-c2ecd55c` | open | `hg-spec-amendment` |
| `2026-11-05-policy-guard-fetch-head-merge-f573a971` | open | `hg-policy-guard-merge-detection` |
| `2026-11-06-converge-sync-no-tier-screen-de7f3222` | open | `hg-policy-guard-merge-detection` |
| `2026-11-06-human-gates-d7-own-branch-source-fec1bc42` | open | `hg-spec-amendment` |
| `2026-11-06-policy-guard-cd-resolution-191e83d1` | open | `hg-policy-guard-shell-semantics` |
| `2026-11-06-policy-guard-conditional-cd-adaaf1db` | open | `hg-policy-guard-shell-semantics` |
| `2026-11-06-policy-guard-config-redirection-bbbc0268` | open | `hg-policy-guard-shell-semantics` |
| `2026-11-06-policy-guard-fetch-tag-shadow-05757c02` | open | `hg-policy-guard-merge-detection` |

### `specs/mission-control/` (32)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-09-12-tower-comms-restates-interaction-style-9a749a17` | duplicate | `mc-panel` |
| `2026-10-01-tmp-cleanup-eats-tower-scratch-53a1587a` | open | `mc-session-lifecycle` |
| `2026-10-25-mc-program-home-read-cost-fe8f2648` | open | `ub-config-read-cost` |
| `2026-10-26-mc-flip-scope-narrower-279d8ddd` | open | `mc-guard-tier-powers` |
| `2026-10-26-mc-host-load-unread-is-idle-f8cb8d43` | open | `mc-scripts-shared-lib` |
| `2026-10-26-mc-pane-rule-skill-prose-f3bc9c7a` | covered | `mc-session-lifecycle` |
| `2026-10-27-mc-lib-shared-helpers-ea11bd32` | open | `mc-scripts-shared-lib` |
| `2026-11-02-mc-inventory-program-block-190f117b` | open | `mc-proposals` |
| `2026-11-02-mc-proposal-value-8e998e2c` | open | `mc-proposals` |
| `2026-11-04-mc-denial-repeat-spec-drift-1e56525f` | open | `mc-proposals` |
| `2026-11-04-mc-eval-denial-proposal-arm-736f17d6` | open | `mc-proposals` |
| `2026-11-04-mc-launch-skips-cadence-a724c17f` | covered | `mc-launch-kinds` |
| `2026-11-04-mc-panel-inflight-counts-dead-rows-083b73d4` | covered | `mc-panel` |
| `2026-11-04-mc-revert-managed-layer-3ce1702c` | open | `mc-adopter-layer-handover` |
| `2026-11-05-kickoff-relay-spec-worktree-594f74ed` | open | `mc-launch-kinds` |
| `2026-11-05-launcher-flight-namespace-01c12030` | open | `tfd-branch-namespace` |
| `2026-11-05-mc-budget-dollar-dimension-af17332a` | open | `mc-scripts-shared-lib` |
| `2026-11-05-mc-class-merge-caller-d0274d5c` | open | `mc-guard-tier-powers` |
| `2026-11-05-mc-class-wait-reports-a845aa5b` | open | `mc-guard-tier-powers` |
| `2026-11-05-mc-drafting-launch-kind-416f7a6a` | open | `mc-launch-kinds` |
| `2026-11-05-mc-first-run-rendered-layer-deadlock-aa515ef9` | open | `mc-adopter-layer-handover` |
| `2026-11-05-mc-program-name-in-key-names-2d2b7c45` | open | `mc-adopter-layer-handover` |
| `2026-11-05-mc-release-launch-kind-5ab3b6b5` | open | `mc-launch-kinds` |
| `2026-11-05-mc-task19-kickoff-cases-bf49d263` | open | `mc-launch-kinds` |
| `2026-11-05-no-host-load-scheduling-01033adb` | open | `wpe-recursive-readers` |
| `2026-11-05-no-priority-pause-resume-327ffa59` | open | `wpe-recursive-readers` |
| `2026-11-05-session-status-shell-reads-exited-5610ccff` | open | `flc-reconcile` |
| `2026-11-05-shared-scratch-root-emptied-c7ff1358` | covered | `mc-session-lifecycle` |
| `2026-11-06-mc-attended-self-succession-32bde2c6` | open | `mc-session-lifecycle` |
| `2026-11-06-mc-failsafe-tick-change-gated-1f599c9d` | open | `mc-session-lifecycle` |
| `2026-11-06-mc-handover-attended-verbs-b632d19a` | open | `mc-session-lifecycle` |
| `2026-11-06-mc-handover-context-threshold-3b1fad05` | open | `mc-session-lifecycle` |

### `specs/tower-comms/` (29)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-09-12-tower-comms-manifest-ownership-d30ce8aa` | open | `tc-spec-wording` |
| `2026-09-15-hook-lock-wait-on-prompt-latency-a0f0b88b` | open | `tc-tower-queue-fixes` |
| `2026-09-15-hook-prompt-source-and-c1-render-9bb22f14` | open | `tc-tower-queue-fixes` |
| `2026-09-15-private-key-redaction-stops-at-header-79cc3210` | open | `tc-redaction` |
| `2026-09-15-prose-and-queue-deliveries-double-count-98c25bd6` | covered | `tc-scorecard` |
| `2026-09-15-tower-queue-idle-lock-d394ee29` | open | `tc-tower-queue-perf` |
| `2026-09-15-tower-queue-log-batch-61e551d2` | open | `tc-tower-queue-perf` |
| `2026-09-15-tower-queue-log-hot-path-cost-2b1327e0` | open | `ub-config-read-cost` |
| `2026-09-16-stuck-detector-test-tower-env-8204bebe` | covered | `tt-test-env-isolation` |
| `2026-09-16-tower-queue-harness-duplication-82f8272b` | open | `tc-tower-queue-fixes` |
| `2026-09-16-tower-queue-log-field-screen-cost-062ee866` | open | `tc-tower-queue-perf` |
| `2026-09-16-tower-queue-rebuild-in-lock-forks-2ed2c876` | open | `tc-tower-queue-perf` |
| `2026-09-16-tower-queue-rebuild-park-recheck-a7a7cc84` | open | `tc-redaction` |
| `2026-09-16-tower-queue-verify-forks-per-pass-980f2be4` | open | `tc-tower-queue-perf` |
| `2026-09-17-queue-field-guard-rejects-utf8-98a155ab` | covered | `ub-sanitizer-utf8` |
| `2026-09-17-tower-log-fork-amplification-83013a04` | duplicate | `tc-tower-queue-perf` |
| `2026-09-18-doctrine-channel-enum-0be87fd1` | covered | `tc-spec-wording` |
| `2026-09-18-pair-partner-lease-unstated-f7e62045` | open | `tc-spec-wording` |
| `2026-09-18-push-log-roundtrips-50ed8b31` | duplicate | `tc-tower-queue-perf` |
| `2026-09-20-mode-glob-rejects-acl-homes-5b1c9e77` | open | `fh-fleet-home` |
| `2026-09-21-consumed-98c25bd6-6671f508` | open | `tc-scorecard` |
| `2026-09-21-fixture-step-knob-cost-e536a772` | open | `ub-config-read-cost` |
| `2026-10-11-tower-queue-redact-assignment-case-88a344d2` | open | `tc-redaction` |
| `2026-10-11-tower-queue-redact-key-block-adc80d27` | duplicate | `tc-redaction` |
| `2026-10-11-tower-queue-redact-key-headers-8bfca004` | open | `tc-redaction` |
| `2026-10-26-mc-presence-marker-edge-14399ba2` | open | `mc-panel` |
| `2026-10-29-tower-queue-pass-log-cost-e2e498e3` | duplicate | `ub-config-read-cost` |
| `2026-10-30-tower-queue-add-subject-before-rebuild-dfb0fd0a` | open | `tc-tower-queue-fixes` |
| `2026-11-01-scorecard-blocked-wait-ignores-settles-b9c919c3` | open | `tc-scorecard` |

### `specs/model-allocation/` (24)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-08-25-selection-resolver-call-amplification-3eb2b603` | open | `ma-allocation-scripts-refactor` |
| `2026-08-26-fleet-knobs-table-contract-c22b0254` | open | `gc-options-reference-integrity` |
| `2026-08-26-spec-surfaced-nonzero-wording-951fd86f` | open | `ma-text-accuracy` |
| `2026-09-02-alloc-replay-fork-claim-cfd66cfe` | open | `ma-text-accuracy` |
| `2026-09-02-allocation-feedback-callsite-7c8e69ca` | covered | `ma-ledger-and-feedback` |
| `2026-09-02-allocation-health-store-failure-a28c67e0` | open | `ma-text-accuracy` |
| `2026-09-02-allocation-ledger-store-forks-22426548` | open | `ma-allocation-scripts-refactor` |
| `2026-09-02-allocation-lock-helper-duplication-1f87d05e` | open | `ma-allocation-scripts-refactor` |
| `2026-09-02-allocation-top-tier-blind-270651d6` | open | `ma-ledger-and-feedback` |
| `2026-09-02-config-fixture-guard-direction-0fa6e03b` | open | `gc-options-reference-integrity` |
| `2026-09-05-adapt-mixed-config-inherit-label-1ea322e4` | open | `ma-text-accuracy` |
| `2026-09-05-alloc-launch-spawn-cost-4f021236` | open | `ma-allocation-scripts-refactor` |
| `2026-09-05-alloc-ledger-write-amplification-236d827e` | open | `ma-ledger-and-feedback` |
| `2026-09-05-alloc-step-knobs-fleet-doc-31f2eac3` | open | `gc-options-reference-integrity` |
| `2026-09-06-allocation-ledger-unit-key-159e7fab` | open | `ma-ledger-and-feedback` |
| `2026-09-06-allocation-roster-and-fable-policy-fea82b1c` | covered | `ma-tier-plumbing` |
| `2026-09-06-feedback-loop-still-unreached-639cea17` | covered | `ma-ledger-and-feedback` |
| `2026-09-06-gc-no-origin-skips-feedback-f233faa3` | open | `ma-ledger-and-feedback` |
| `2026-09-07-allocation-step-type-callsite-f17e821b` | open | `ma-tier-plumbing` |
| `2026-09-07-fleet-allocation-doc-duplication-3f5de74f` | open | `ma-text-accuracy` |
| `2026-09-07-roster-consolidation-residuals-59c3ad96` | open | `ma-tier-plumbing` |
| `2026-09-11-malformed-gates-cost-an-anchor-11f61a8f` | open | `fg-drain-gates` |
| `2026-10-05-step-tiers-cannot-raise-or-apply-e9ae3805` | open | `ma-tier-plumbing` |
| `2026-10-18-offload-per-launch-model-a330d4cc` | open | `ma-tier-plumbing` |

### `specs/skill-rigor/` (24)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-26-skill-drift-5756e0af` | open | `sr-awaiting-input-v2` |
| `2026-07-26-skill-drift-b7c25788` | stale | `sr-skill-text-drift` |
| `2026-08-18-skill-drift-a19fc34c` | covered | `bootstrap-worktree-rule` |
| `2026-08-24-skill-drift-8aaa8edf` | open | `sr-spec-draft-skill-fixes` |
| `2026-08-25-skill-drift-3672d83d` | open | `sr-lens-artifact-class` |
| `2026-08-26-execute-task-blind-to-dispatch-gate-5893ec60` | open | `sr-skill-text-drift` |
| `2026-08-26-skill-drift-38f3809f` | duplicate | `sr-lens-artifact-class` |
| `2026-08-26-skill-drift-7da1eedb` | open | `sr-skill-text-drift` |
| `2026-08-27-doctrine-reword-skill-straggler-8fa65f3f` | open | `gc-doctrine-guards` |
| `2026-09-01-skill-drift-b165f3de` | open | `sr-lens-artifact-class` |
| `2026-09-03-skill-drift-9124476b` | open | `sr-skill-text-drift` |
| `2026-09-03-skill-drift-bdab2aa9` | open | `fg-validator-fixes` |
| `2026-09-03-skills-awaiting-input-note-wording-84f076ea` | open | `sr-awaiting-input-v2` |
| `2026-09-09-kickoff-lens-yield-on-fresh-draft-9c3cf221` | duplicate | `re-drafting-time-lens` |
| `2026-09-24-skill-drift-4e6c5a33` | duplicate | `sr-spec-draft-skill-fixes` |
| `2026-09-24-spec-draft-hygiene-a5c24588` | open | `sr-spec-draft-skill-fixes` |
| `2026-09-28-sign-off-route-reason-writer-29b27caf` | open | `hg-sign-off-record` |
| `2026-10-01-skill-drift-b0d66c81` | covered | `hg-sign-off-record` |
| `2026-10-01-spec-kickoff-worktree-from-worktree-134aa8ef` | open | `sr-spec-draft-skill-fixes` |
| `2026-10-02-skill-drift-7c3576ba` | covered | `hg-sign-off-record` |
| `2026-10-06-skill-drift-5558be0b` | open | `sr-spec-draft-skill-fixes` |
| `2026-10-06-skill-drift-7cef7116` | duplicate | `sr-lens-artifact-class` |
| `2026-10-06-skill-drift-d115ed2f` | open | `sr-spec-draft-skill-fixes` |
| `2026-11-04-kickoff-lens-found-drafting-gaps-8f63a493` | open | `od-drafting-kickoff-weight` |

### `specs/fleet-lifecycle-closure/` (22)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-17-fleet-inspect-tree-unborn-head-f63eb20c` | open | `flc-sweep-hardening` |
| `2026-07-17-fleet-scan-valid-path-gap-e9daedb7` | open | `flc-sweep-hardening` |
| `2026-07-17-fleet-task4-test-coverage-gaps-58d07579` | open | `flc-sweep-hardening` |
| `2026-08-18-worktreecreate-regression-2-1-234-562be3ae` | stale | `fa-spec-amendment` |
| `2026-08-18-worktreecreate-root-cause-correction-2036d463` | covered | `fa-spec-amendment` |
| `2026-08-18-worktreecreate-rootcause-correction-16facd5b` | duplicate | `fa-spec-amendment` |
| `2026-08-25-rung-coverage-check-34ae9280` | open | `flc-reconcile` |
| `2026-08-26-worktreecreate-contract-supersession-46886617` | covered | `fa-spec-amendment` |
| `2026-09-02-registry-record-is-an-untrusted-hint-43d7f787` | open | `flc-reconcile` |
| `2026-09-02-registry-retention-and-write-cost-75369b47` | open | `flc-state-retention` |
| `2026-09-03-liveness-primitive-duplicated-8410794f` | open | `ub-portability-helpers` |
| `2026-09-03-stop-leaves-registry-record-daba5f5c` | covered | `flc-state-retention` |
| `2026-09-04-fleet-home-mode-gate-c0d053ae` | covered | `fh-fleet-home` |
| `2026-09-04-status-never-tests-result-subtype-cb4b817b` | open | `eb-streamjson-state-correctness` |
| `2026-09-07-streamjson-state-has-no-retention-4dd41794` | open | `flc-state-retention` |
| `2026-09-10-journal-lock-soundness-residuals-d45387c2` | open | `flc-stop-paths` |
| `2026-09-14-streamjson-close-quiesce-bf59017f` | open | `flc-stop-paths` |
| `2026-09-24-headless-stop-from-registry-0692779d` | open | `flc-stop-paths` |
| `2026-10-07-death-handle-verdict-duplication-26c231e3` | open | `flc-reconcile` |
| `2026-10-11-rehearsal-scratch-list-drift-f46c4eea` | open | `flc-sweep-hardening` |
| `2026-11-05-launcher-worktree-liveness-093b1e8d` | open | `flc-reconcile` |
| `2026-11-05-script-rung-redispatch-liveness-3bf031b9` | open | `flc-reconcile` |

### `specs/inception/` (21)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-22-inception-coverage-risk-form-2c2ab68e` | open | `in-skill-text` |
| `2026-07-22-inception-ladder-coupling-b9844e2a` | open | `in-skill-text` |
| `2026-08-18-catalog-prose-yaml-id-drift-a0875377` | open | `co-catalog-seed-handling` |
| `2026-09-28-secret-screen-builtin-coverage-a8cd8bdb` | open | `in-venture-screening` |
| `2026-10-11-catalog-id-control-chars-af2f6670` | open | `ub-output-sanitize` |
| `2026-10-12-card-lint-trigger-power-check-45840ae6` | open | `in-venture-screening` |
| `2026-10-12-inception-staged-screen-renames-d2580ac5` | open | `in-venture-screening` |
| `2026-10-13-inception-push-check-hostile-config-727458d1` | open | `in-venture-screening` |
| `2026-10-13-inception-push-screen-residual-gaps-3c6bfdf9` | open | `in-venture-screening` |
| `2026-10-18-fanout-gate2-volume-67ac44df` | open | `in-skill-text` |
| `2026-10-18-inception-awk-date-helpers-f1b5ddb1` | open | `in-helpers` |
| `2026-10-18-venture-hook-task-check-41beebf8` | open | `in-venture-screening` |
| `2026-10-18-venture-z16-flake-5b8f73fd` | open | `tt-load-sensitive-tests` |
| `2026-10-19-inception-drop-consumption-ffaa611c` | open | `in-unconsumed-inputs` |
| `2026-10-19-inception-drop-obs-targets-0e8630db` | open | `in-unconsumed-inputs` |
| `2026-10-25-inception-bundle-lock-coverage-c42731fb` | open | `in-helpers` |
| `2026-10-25-inception-proposals-reader-d49dd7ff` | open | `in-unconsumed-inputs` |
| `2026-10-25-inception-shared-helper-lib-c5c81122` | open | `in-helpers` |
| `2026-10-25-macos-venture-screen-flake-ec77c122` | duplicate | `in-venture-screening` |
| `2026-10-25-venture-guard-merge-base-wording-485e2037` | open | `in-venture-screening` |
| `2026-10-31-secret-screen-archive-names-c12cc37a` | open | `in-venture-screening` |

### `specs/release-hardening/` (21)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-19-release-mise-alias-docs-876b6b55` | open | `rh-followups` |
| `2026-07-19-release-pending-version-file-toctou-10e670d2` | open | `rh-followups` |
| `2026-07-19-release-publish-config-swallow-parity-017ad88e` | open | `rh-followups` |
| `2026-07-19-release-publish-stale-local-main-04b578da` | open | `rh-followups` |
| `2026-07-19-release-test-run-guard-anchor-749d937c` | open | `rh-followups` |
| `2026-07-19-resume-signer-trust-cross-machine-a9f6ce22` | open | `rh-followups` |
| `2026-07-19-rl-ci-state-arm-firetime-tests-d2ffdc78` | open | `rh-followups` |
| `2026-07-30-release-please-bootstrap-race-fd6c2f4f` | open | `rh-untagged-window` |
| `2026-08-18-workflow-run-fork-branch-131af768` | covered | `gc-workflow-guards` |
| `2026-08-26-rh-entry-owner-decision-82311952` | open | `rh-followups` |
| `2026-09-02-release-fetch-redundant-under-depth0-52453de0` | open | `rh-followups` |
| `2026-09-02-release-guard-skips-step-not-job-571fa0d3` | open | `rh-untagged-window` |
| `2026-09-02-release-guard-toctou-6f4900e9` | open | `rh-release-merge-race` |
| `2026-09-02-release-please-pending-run-cancel-10244b4d` | open | `rh-release-merge-race` |
| `2026-09-02-release-please-trigger-not-authz-0934616b` | covered | `gc-workflow-guards` |
| `2026-09-02-release-skip-can-drop-work-c2afd203` | open | `rh-release-merge-race` |
| `2026-09-02-release-tagless-skip-forever-81c99b98` | open | `rh-untagged-window` |
| `2026-09-02-release-template-guard-gap-5ba1bbde` | open | `rh-untagged-window` |
| `2026-09-28-release-ci-cancelled-by-next-merge-33b7c53d` | open | `rh-release-merge-race` |
| `2026-09-28-release-publish-stale-checkout-3055e69a` | duplicate | `rh-followups` |
| `2026-10-05-flip-point-page-budget-7fad13ee` | open | `mcg-ready-guard-fixes` |

### `specs/review-effectiveness/` (21)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-08-25-kickoff-lens-dedup-19ec8cd4` | open | `re-lens-fanout-mechanics` |
| `2026-08-26-coverage-pin-has-no-bucket-49ad55ea` | open | `re-doctrine-amendment` |
| `2026-08-26-spec-mechanism-vs-incident-artifact-11bd17fe` | open | `re-drafting-time-lens` |
| `2026-08-26-zone-screen-fix-location-7f0b4274` | open | `re-doctrine-amendment` |
| `2026-09-02-drafting-time-lens-gap-8dcf0f7c` | open | `re-drafting-time-lens` |
| `2026-09-02-hard-pause-zones-vs-hardening-c06b2908` | open | `re-doctrine-amendment` |
| `2026-09-13-shared-run-start-doc-growth-15240f38` | open | `re-doctrine-amendment` |
| `2026-09-14-big-diff-relocates-defects-a0add2f0` | open | `re-doctrine-amendment` |
| `2026-09-14-vacuous-fuzz-proves-nothing-af6048cb` | open | `re-review-lessons` |
| `2026-09-14-worker-guard-awk-lexer-bypass-3ed95276` | open | `re-review-lessons` |
| `2026-09-14-worker-guard-blessed-screen-blindspots-15a7fdcb` | open | `re-review-lessons` |
| `2026-09-17-bot-resolves-its-own-threads-51b53aa5` | open | `re-bot-review-fixes` |
| `2026-09-17-bot-review-latency-overstated-67aafd6a` | open | `re-bot-review-fixes` |
| `2026-09-18-success-signal-detached-b7d3e2a1` | open | `re-review-lessons` |
| `2026-09-21-panel-backend-fabricates-citations-4f7c2e91` | open | `flight-panel-backend-robustness` |
| `2026-09-22-lens-fanout-report-channel-c10c0a24` | open | `re-lens-fanout-mechanics` |
| `2026-09-24-doctrine-task-budget-cost-4034976f` | duplicate | `re-doctrine-amendment` |
| `2026-10-07-lens-probe-side-effects-9f2fb326` | open | `re-lens-fanout-mechanics` |
| `2026-10-11-polish-audit-run-files-74395a99` | open | `re-review-artifact-storage` |
| `2026-10-21-lens-list-mirror-moot-6fb74b0c` | open | `re-doctrine-amendment` |
| `2026-10-31-corpus-refresh-worker-run-9b382af6` | open | `re-review-artifact-storage` |

### `specs/worker-permission-ergonomics/` (20)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-27-ctxeng-settings-about-prose-b75dc6d2` | open | `wpe-profile-denies` |
| `2026-10-05-guard-dq-backslash-dropped-addd719a` | open | `wpe-guard-tokenizer-fidelity` |
| `2026-10-06-f16-mise-config-spellings-5b775475` | covered | `wpe-spec-wording` |
| `2026-10-07-worker-profile-mcp-globs-b3778c06` | open | `hg-reserved-control-spellings` |
| `2026-10-10-environ-recursive-readers-74aadeae` | open | `wpe-recursive-readers` |
| `2026-10-10-worker-profile-static-git-diff-no-index-a961874c` | open | `wpe-static-allow-rules` |
| `2026-10-11-environ-renamed-symlink-9eabaa16` | open | `wpe-recursive-readers` |
| `2026-10-12-substitution-assignment-can-fail-5005a275` | open | `wpe-spec-wording` |
| `2026-10-19-excluded-paths-list-9fe89c1e` | covered | `wpe-profile-denies` |
| `2026-10-19-floor-vs-spec-zone-dc162d4f` | open | `wpe-spec-wording` |
| `2026-10-19-loop-fits-do-argument-d83f8220` | open | `wpe-guard-tokenizer-fidelity` |
| `2026-10-25-scratch-tmpdir-live-check-3e72b3a5` | open | `wpe-scratch-isolation` |
| `2026-10-25-worker-hooks-tmpdir-fec044a7` | open | `wpe-scratch-isolation` |
| `2026-10-25-write-arm-trailing-slash-43877005` | open | `wpe-scratch-isolation` |
| `2026-11-01-worker-audit-log-profile-deny-2e9cd1a7` | duplicate | `wpe-profile-denies` |
| `2026-11-01-worker-file-tools-reach-guard-scripts-a0347364` | open | `wpe-profile-denies` |
| `2026-11-01-worker-profile-push-exec-forms-5408541c` | open | `wpe-static-allow-rules` |
| `2026-11-03-worker-allow-audit-log-file-tools-ff4e3890` | open | `wpe-profile-denies` |
| `2026-11-05-no-filesystem-root-search-guard-3548c59c` | open | `wpe-recursive-readers` |
| `2026-11-05-own-branch-merge-not-self-approved-9c9c567f` | open | `hg-policy-guard-merge-detection` |

### `specs/kickoff-lifecycle/` (17)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-17-kickoff-mid-walk-edit-relens-830c511b` | covered | `kl-kickoff-skill-gaps` |
| `2026-07-20-spec-status-flip-helper-a88f696a` | open | `kl-state-transition-helpers` |
| `2026-09-07-skill-drift-b1bb6557` | open | `kl-kickoff-skill-gaps` |
| `2026-09-18-kickoff-stale-spec-branch-99a03c33` | open | `kl-kickoff-skill-gaps` |
| `2026-09-22-kickoff-brief-template-cite-5b082de8` | open | `kl-kickoff-skill-gaps` |
| `2026-09-22-kickoff-worktree-name-212172f2` | open | `kl-kickoff-skill-gaps` |
| `2026-09-22-skill-drift-9715b9de` | open | `kl-kickoff-skill-gaps` |
| `2026-10-07-skill-drift-72159735` | open | `sr-spec-draft-skill-fixes` |
| `2026-10-08-kickoff-log-home-4d4ba9c7` | open | `od-kickoff-log-and-rubric` |
| `2026-10-08-skill-drift-b78c25aa` | duplicate | `sr-awaiting-input-v2` |
| `2026-10-09-v2-delta-anchor-park-gap-2db6972c` | duplicate | `sr-spec-draft-skill-fixes` |
| `2026-10-10-kickoff-delta-entry-headings-2f0438af` | open | `od-kickoff-log-and-rubric` |
| `2026-10-10-parked-merged-task-dependency-627fc204` | open | `fg-parked-task-visibility` |
| `2026-10-10-skill-drift-50ecac6f` | duplicate | `sr-spec-draft-skill-fixes` |
| `2026-10-10-skill-drift-d034cecf` | duplicate | `sr-awaiting-input-v2` |
| `2026-10-10-skill-drift-fb30640a` | duplicate | `sr-spec-draft-skill-fixes` |
| `2026-10-18-supersede-pointer-done-bundle-anchor-f00cb97c` | open | `sr-spec-draft-skill-fixes` |

### `specs/execution-backends/` (16)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-22-adapter-invocation-hardening-9adfb18a` | open | `eb-launch-hardening` |
| `2026-07-22-launch-pin-scope-prompt-eval-bare-683025b7` | open | `ph-eval-harness` |
| `2026-07-23-full-session-pluggable-ladder-c83d930d` | open | `eb-backend-ladder-design` |
| `2026-07-23-headless-bg-flag-b48fa0a1` | open | `eb-backend-ladder-design` |
| `2026-07-23-status-view-render-byte-padding-e449e570` | stale | `ub-sanitizer-utf8` |
| `2026-07-23-status-view-sid-join-spoof-404d3b7b` | open | `ub-sanitizer-utf8` |
| `2026-07-23-streamjson-alarm-scan-field-guards-ed0c7477` | open | `eb-streamjson-alarm-scan` |
| `2026-07-23-streamjson-capture-confidentiality-e4477129` | open | `eb-streamjson-alarm-scan` |
| `2026-07-23-streamjson-deny-message-escaping-b11b9175` | covered | `eb-streamjson-alarm-scan` |
| `2026-07-23-streamjson-deny-message-utf8-split-c50cc98d` | open | `eb-streamjson-alarm-scan` |
| `2026-07-23-streamjson-prompt-tool-flag-hidden-b4f695d6` | open | `eb-backend-ladder-design` |
| `2026-10-11-isolated-steps-degrade-on-stream-json-7f7e0c9f` | open | `eb-step-backend-composition` |
| `2026-10-18-worker-settings-passthrough-9a16099f` | open | `ma-tier-plumbing` |
| `2026-10-25-test-env-plugin-root-leak-18087d21` | covered | `tt-test-env-isolation` |
| `2026-11-02-headless-runner-ignores-sigint-8fb47aec` | open | `eb-launch-hardening` |
| `2026-11-05-streamjson-ended-worker-pending-b41664cf` | open | `eb-streamjson-alarm-scan` |

### `specs/customization-overlay/` (14)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-22-resolve-catalog-decision-domains-empty-a672bb2e` | open | `co-catalog-seed-handling` |
| `2026-08-25-skill-drift-614d4db7` | open | `newspec-resolved-path-and-version` |
| `2026-08-25-skill-drift-dd8e3d7e` | open | `newspec-resolved-path-and-version` |
| `2026-09-07-malformed-degrade-target-54457c6f` | open | `co-overlays-doc` |
| `2026-09-07-overlays-explain-overbroad-a5079b6a` | covered | `co-overlays-doc` |
| `2026-09-21-protected-docs-fails-open-8d2f1a63` | open | `co-protected-docs-default` |
| `2026-09-24-custom-steps-doc-unprotected-4871f107` | open | `co-protected-docs-default` |
| `2026-09-24-customization-overlay-runnable-instance-2f71ba54` | open | `co-overlays-doc` |
| `2026-09-24-overlays-doc-path-confinement-9a4e5e83` | open | `co-overlays-doc` |
| `2026-09-26-config-get-root-precedence-fe78aa96` | open | `co-knob-resolver-family` |
| `2026-10-07-resolver-spaced-colon-silent-b93f496c` | open | `co-knob-resolver-family` |
| `2026-10-11-overlay-contain-unsanitized-path-bba0abad` | open | `ub-output-sanitize` |
| `2026-10-12-overlay-contain-readlink-newline-4230dcfa` | open | `ub-output-sanitize` |
| `2026-10-17-inline-map-parser-89a9d2e7` | open | `ub-shared-parsers` |

### `specs/fleet-hardening/` (14)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-15-fleet-tier-degradation-visibility-09e7b4f0` | open | `coc-cross-worktree-exclusion` |
| `2026-07-17-fleet-state-home-unresolved-b085ac53` | open | `fh-fleet-home` |
| `2026-07-20-fleet-hardening-mechanism-count-8-vs-9-aada9500` | open | `fh-spec-amendment` |
| `2026-07-20-freshness-gate-anchor-wording-247c430b` | covered | `fh-spec-amendment` |
| `2026-07-20-stopconds-fetch-park-path-7003944a` | stale | `fh-spec-amendment` |
| `2026-07-22-fleet-home-default-umask-9c5071dd` | covered | `fh-fleet-home` |
| `2026-07-28-carry-pr-body-hard-wrapped-2237ec28` | open | `or-obs-carry-correctness` |
| `2026-10-04-req-h1-1-source-assertion-owner-203caacf` | open | `fh-spec-amendment` |
| `2026-10-04-tmux-command-word-semicolon-d1a812ef` | covered | `fh-spec-amendment` |
| `2026-10-05-seam-discovery-wrapped-launch-a2a3589a` | covered | `fh-spec-amendment` |
| `2026-10-07-fetch-anchor-ref-reads-e9fafa61` | open | `coc-dispatch-base-resolution` |
| `2026-10-11-streamjson-status-transient-double-count-8c6d9073` | open | `eb-streamjson-state-correctness` |
| `2026-10-25-fleet-home-ancestor-privacy-cd693357` | open | `fh-fleet-home` |
| `2026-10-26-tower-guard-grep-open-abbrev-edfc0ca9` | open | `hg-policy-guard-shell-semantics` |

### `specs/anchor-integrity/` (13)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-17-anchor-parallel-merge-drift-02efe968` | open | `ai-reanchor-sweep` |
| `2026-07-18-spec-correction-needs-reanchor-bb414857` | open | `ai-reanchor-sweep` |
| `2026-07-26-anchored-figures-outside-bundles-362f4de7` | open | `ai-spec-text-amendment` |
| `2026-07-26-reconcile-note-removal-unowned-473ef7c5` | stale | `ai-spec-text-amendment` |
| `2026-08-24-anchor-drift-done-bundles-1ea469f5` | open | `ai-reanchor-sweep` |
| `2026-08-24-freshness-gate-hash-scope-blind-spot-98f27101` | open | `ai-reanchor-sweep` |
| `2026-08-24-skill-drift-fbc582f6` | covered | `ai-reanchor-sweep` |
| `2026-08-24-sweep-race-late-bundle-fa2ad31a` | open | `ai-reanchor-sweep` |
| `2026-08-25-kickoff-prechange-anchor-afaf925b` | open | `ai-reanchor-sweep` |
| `2026-08-27-spec-implementation-divergence-fb37c4bf` | open | `ai-spec-text-amendment` |
| `2026-09-12-execution-validity-marks-unparsed-fd49438a` | open | `fg-spec-parse-lib` |
| `2026-10-07-gate-uncommitted-edit-read-b350a709` | open | `ai-spec-text-amendment` |
| `2026-10-11-anchor-namespace-arg-d4c517d9` | open | `ai-spec-text-amendment` |

### `new-spec` (12)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-17-draft-test-spec-guard-blindness-d95cb0da` | open | `newspec-spec-authoring-checks` |
| `2026-07-18-spec-draft-testspec-h2-groups-8fb8f199` | open | `newspec-spec-authoring-checks` |
| `2026-07-19-command-guard-engine-dup-30159d5c` | open | `newspec-command-guard-lib` |
| `2026-07-19-spec-validate-req-task-coverage-f6601f8f` | open | `newspec-spec-authoring-checks` |
| `2026-07-19-task-donewhen-sibling-artifact-09bd365d` | open | `newspec-spec-authoring-checks` |
| `2026-07-22-external-api-semantics-upfront-research-01b3a1eb` | open | `newspec-spec-authoring-checks` |
| `2026-07-24-spec-crossref-claims-unverified-59087817` | open | `newspec-spec-authoring-checks` |
| `2026-07-27-ctxeng-testspec-executable-3a13f926` | open | `newspec-spec-authoring-checks` |
| `2026-07-27-ctxeng-validator-normative-home-5a0e8427` | open | `newspec-spec-authoring-checks` |
| `2026-07-28-awk-redirect-vs-relational-screen-026930ca` | open | `newspec-command-guard-lib` |
| `2026-08-27-superpowers-interop-a8d7dfb2` | open | `newspec-superpowers-interop` |
| `2026-09-26-what-prints-is-what-runs-2b27a26c` | open | `newspec-resolved-path-and-version` |

### `specs/custom-spec-location/` (12)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-09-28-csl-req-a1-3-empty-cancel-9c6abde5` | covered | `csl-spec-wording` |
| `2026-10-01-flight-record-path-767ac037` | covered | `csl-hardcoded-spec-root` |
| `2026-10-07-default-branch-outside-gate-201a1004` | open | `coc-dispatch-base-resolution` |
| `2026-10-07-execute-task-numeric-spec-id-d4e402af` | open | `csl-spec-wording` |
| `2026-10-07-root-placeholder-collision-38fc2599` | open | `csl-spec-wording` |
| `2026-10-07-root-placeholder-script-comments-85803d53` | open | `csl-spec-wording` |
| `2026-10-07-skill-drift-827c8a03` | open | `csl-hardcoded-spec-root` |
| `2026-10-18-screen-widening-7ebaf626` | open | `or-obs-tooling-hardening` |
| `2026-10-25-obs-remote-write-wording-5e5827ab` | open | `csl-spec-wording` |
| `2026-10-29-default-root-flag-0af72772` | open | `csl-spec-wording` |
| `2026-10-30-registry-lookup-cost-4f67e12e` | open | `ub-config-read-cost` |
| `2026-11-02-per-session-derivation-split-a18bd8ae` | open | `it-holders` |

### `specs/observation-recording/` (12)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-11-test-spec-req-e13-scope-34edff2a` | open | `or-spec-amendment` |
| `2026-07-14-global-gitignore-shadows-obs-25b0768e` | stale | `or-obs-tooling-hardening` |
| `2026-09-02-obs-accumulator-script-writers-d0328192` | open | `or-spec-amendment` |
| `2026-09-12-squash-merge-strands-tail-commits-3cacc290` | open | `or-obs-carry-correctness` |
| `2026-09-13-carry-branch-outlives-its-content-5f9bbb65` | open | `or-obs-carry-correctness` |
| `2026-09-20-carry-dedupe-drops-revisions-silently-c4a0b7e2` | open | `or-obs-carry-correctness` |
| `2026-09-20-carry-reports-stranded-while-carrying-9d3f21c4` | stale | `or-obs-carry-correctness` |
| `2026-09-24-observation-carry-ignores-archive-4faa7410` | open | `or-obs-carry-correctness` |
| `2026-10-11-flight-obs-consume-arm-b1d4c9d4` | open | `or-obs-tooling-hardening` |
| `2026-10-18-obs-dir-control-bytes-dd7362b5` | open | `or-obs-tooling-hardening` |
| `2026-10-19-check-obs-vacuous-dir-6d79f3f5` | open | `or-obs-tooling-hardening` |
| `2026-10-31-obs-duplicates-across-branches-9822997b` | open | `or-obs-carry-correctness` |

### `specs/_pending/worker-permission-ergonomics-amendment.md` (9)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-10-05-worker-profile-static-git-write-forms-199450d4` | open | `wpe-static-allow-rules` |
| `2026-10-07-guard-double-quote-backslash-e85c7612` | duplicate | `wpe-guard-tokenizer-fidelity` |
| `2026-10-07-guard-env-names-fork-failure-4298486c` | open | `wpe-guard-tokenizer-fidelity` |
| `2026-10-07-guard-tokenizer-zsh-model-8d46a461` | open | `wpe-guard-tokenizer-fidelity` |
| `2026-10-07-guard-while-loop-cap-daa706a4` | open | `wpe-guard-tokenizer-fidelity` |
| `2026-10-07-worker-yq-screen-gap-1e8250fa` | covered | `wpe-static-allow-rules` |
| `2026-10-08-worker-guard-argv-blind-script-trust-c4ffd0df` | open | `wpe-static-allow-rules` |
| `2026-10-11-workers-glob-shared-tmp-f4607cf0` | open | `wpe-scratch-isolation` |
| `2026-10-19-guard-scan-budget-load-margin-bb4cc293` | open | `wpe-guard-tokenizer-fidelity` |

### `specs/fleet-autonomy/` (9)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-16-daemon-gate-resolution-cost-44adcf07` | open | `ub-config-read-cost` |
| `2026-07-16-knob-resolver-dedup-6ae6195c` | open | `co-knob-resolver-family` |
| `2026-07-17-context-budget-doctrine-gap-06086c51` | open | `fa-spec-amendment` |
| `2026-07-17-task2-donewhen-risk31-wording-0df49a3c` | open | `fa-spec-amendment` |
| `2026-07-17-tower-marker-authenticity-b47b3043` | open | `fa-fleet-tower-hardening` |
| `2026-07-17-tower-watchdog-audit-write-exit-95776321` | open | `fa-fleet-tower-hardening` |
| `2026-07-18-fa-sole-mechanism-fwd-citation-bddb4918` | open | `fa-spec-amendment` |
| `2026-07-23-resolver-degrade-target-divergence-c344dae6` | open | `co-knob-resolver-family` |
| `2026-08-26-fleet-autonomy-b1-2-create-half-drift-bed09898` | open | `fa-spec-amendment` |

### `specs/merge-currency-guard/` (9)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-29-ready-guard-per-bash-jq-cost-ec12d9b8` | open | `mcg-ready-guard-fixes` |
| `2026-08-26-mcg-loop-owner-decision-d7e936d7` | covered | `mcg-convergence-sync` |
| `2026-09-22-pr-splitting-and-sync-frugality-36916a48` | open | `mcg-convergence-sync` |
| `2026-09-24-converge-sync-batchmode-agent-c0d18822` | open | `pending-fetch-hang-guards` |
| `2026-09-24-converge-sync-drops-core-sshcommand-fdfd29d7` | covered | `pending-fetch-hang-guards` |
| `2026-09-24-converge-sync-ssh-command-gaps-1fa02012` | open | `pending-fetch-hang-guards` |
| `2026-10-01-mcg-gh-api-residual-b14af9aa` | open | `hg-currency-and-remedy-text` |
| `2026-10-11-ready-guard-hook-time-bound-2497969c` | open | `mcg-ready-guard-fixes` |
| `2026-11-06-ready-guard-fetch-head-remedy-43bff019` | open | `hg-currency-and-remedy-text` |

### `specs/tower-front-door/` (9)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-08-18-plugin-version-skew-d4d2236e` | open | `newspec-resolved-path-and-version` |
| `2026-08-24-worker-settings-plugin-skew-217cc262` | duplicate | `newspec-resolved-path-and-version` |
| `2026-09-02-specless-rules-without-d-ids-64a37594` | open | `tfd-spec-amendment` |
| `2026-09-24-flight-collision-wording-a75f5e38` | open | `tfd-spec-amendment` |
| `2026-10-01-configurable-branch-prefix-3640d42d` | open | `tfd-branch-namespace` |
| `2026-10-01-flight-home-disagrees-abe9ffce` | open | `flight-fleet-script-fixes` |
| `2026-10-07-tower-front-door-spec-wording-f22a2e4c` | open | `tfd-spec-amendment` |
| `2026-10-11-flight-record-list-prefixed-key-c025b6ff` | open | `tc-redaction` |
| `2026-10-11-flight-record-ssh2-continuation-end-74b26a30` | open | `tc-redaction` |

### `specs/concurrent-orchestrator-coordination/` (8)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-08-26-orchestrate-fence-wiring-unbudgeted-a2962703` | open | `coc-cross-worktree-exclusion` |
| `2026-08-27-fence-sweep-cadence-window-one-shot-77d57078` | open | `coc-cross-worktree-exclusion` |
| `2026-10-03-selector-remote-branch-blind-8ff5cafc` | covered | `coc-cross-worktree-exclusion` |
| `2026-10-04-cross-machine-dispatch-window-2e314614` | open | `coc-cross-worktree-exclusion` |
| `2026-10-04-orchestrate-lock-checkout-local-7424d6d2` | open | `coc-cross-worktree-exclusion` |
| `2026-10-04-remote-bundle-branch-blind-44a4309b` | open | `coc-cross-worktree-exclusion` |
| `2026-10-06-dispatch-gate-base-drift-9d490aa5` | open | `coc-dispatch-base-resolution` |
| `2026-11-05-meta-step-parallel-cap-ed918287` | open | `coc-cross-worktree-exclusion` |

### `specs/invariant-tasks/` (6)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-15-spec-status-single-pass-render-a597583f` | open | `ub-perf-orchestration-readers` |
| `2026-07-19-execute-task-zero-diff-design-task-f3376f78` | open | `kl-state-transition-helpers` |
| `2026-10-30-selection-contract-v3-exit3-e4efb4d4` | covered | `pending-spec-format-v3-text` |
| `2026-10-30-v3-skill-arms-fa79b107` | open | `pending-spec-format-v3-text` |
| `2026-11-02-holder-alias-dispatch-contradiction-92a85ebd` | duplicate | `it-holders` |
| `2026-11-03-holder-alias-decision-51d04d91` | open | `it-holders` |

### `specs/operator-dialogue/` (6)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-21-rubric-blocklist-dup-78a76eac` | open | `od-kickoff-log-and-rubric` |
| `2026-09-04-skill-drift-6591d9b1` | open | `od-drafting-kickoff-weight` |
| `2026-09-12-eval-log-schema-divergence-aadfa08b` | open | `od-kickoff-log-and-rubric` |
| `2026-09-21-kickoff-headroom-nearly-spent-7120c520` | stale | `ih-orchestrate-diet` |
| `2026-09-22-interaction-style-flags-itself-fdcd0fa9` | open | `pd-noisy-prose-checks` |
| `2026-11-04-drafting-kickoff-too-heavy-c52287be` | open | `od-drafting-kickoff-weight` |

### `specs/_pending/currency-posture-and-drifts.md` (4)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-09-24-main-currency-no-prompt-guard-dc685bf3` | open | `pending-fetch-hang-guards` |
| `2026-09-24-skill-drift-88953874` | open | `sr-awaiting-input-v2` |
| `2026-10-02-skill-drift-9817e6ef` | duplicate | `sr-awaiting-input-v2` |
| `2026-10-05-skill-drift-44024827` | duplicate | `sr-awaiting-input-v2` |

### `specs/fleet-messaging/` (4)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-10-04-fleet-messaging-tmux-identity-owner-2fa9088c` | open | `fm-spec-amendment` |
| `2026-10-11-floor-doc-inbox-class-prose-59393a5f` | open | `fm-spec-amendment` |
| `2026-10-26-ci-cli-above-messaging-floor-b4bf7986` | open | `fm-spec-amendment` |
| `2026-11-05-mc-cross-machine-relay-57770415` | open | `fm-cross-machine-messaging` |

### `specs/prompt-hygiene/` (3)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-13-eval-skill-injection-gap-dc2883b2` | covered | `ph-eval-harness` |
| `2026-07-14-behavioral-pilot-injection-design-df835e81` | open | `ph-eval-harness` |
| `2026-07-14-eval-sentinel-json-escaping-ecc9d77c` | open | `ph-eval-harness` |

### `specs/tower-placement/` (3)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-10-08-tower-about-two-specs-759826d8` | open | `tp-placement-currency` |
| `2026-10-08-tower-posture-step-dead-hooks-a2230ae8` | open | `tp-placement-currency` |
| `2026-10-10-tower-placement-handshake-superseded-c29675e0` | open | `tp-placement-currency` |

### `specs/prose-disposition/` (2)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-09-21-prose-lane-budget-wall-7c02f52b` | open | `ih-skill-relief` |
| `2026-10-25-comment-budget-warn-volume-13220d40` | open | `pd-noisy-prose-checks` |

### `specs/quota-handling/` (2)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-10-06-quota-handling-amendment-fold-57592829` | covered | `qh-quota-handling` |
| `2026-10-19-quota-hold-reservation-race-55d41af8` | open | `qh-quota-handling` |

### `specs/_pending/environment-broker.md` (1)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-09-24-worker-login-shell-env-ada69b21` | open | `pending-worker-login-shell-env` |

### `specs/_pending/fleet-hardening-amendment.md` (1)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-11-04-tower-raw-fallback-bypass-classes-66e65bab` | open | `hg-policy-guard-shell-semantics` |

### `specs/_pending/readiness-review-body-findings.md` (1)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-09-09-bot-rereview-login-silent-noop-8b24690f` | open | `re-bot-review-fixes` |

### `specs/_pending/review-gauntlet.md` (1)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-10-06-bot-incremental-refused-after-merge-f19f24d5` | open | `re-bot-review-fixes` |

### `specs/_pending/spec-format-upgrade.md` (1)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-10-30-invariant-tasks-d13-upgrade-wording-279d04e7` | open | `pending-spec-format-v3-text` |

### `specs/_pending/walkthrough-revisit.md` (1)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-08-27-spec-walkthrough-artifact-e09d8fc5` | open | `pending-walkthrough-revisit` |

### `specs/bootstrap/` (1)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-07-20-d37-slashed-branch-shell-exception-7ad46e46` | open | `bootstrap-worktree-rule` |

### `specs/orchestration-fleet/` (1)

| Fragment | Status | Bundle |
| --- | --- | --- |
| `2026-10-05-orchestrate-tmux-step3-marker-09fc8006` | covered | `eb-step-backend-composition` |
