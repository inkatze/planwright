# Fleet lifecycle closure — Test spec

**Status:** Draft
**Last reviewed:** 2026-08-18
**Format-version:** 2
**Execution:** derived — see the status render

Coverage mix: this bundle is overwhelmingly shell mechanism over structured
signals, so most requirements verify as `[test]` in the project's shell suite.
The doctrine group verifies `[design-level]` — a floor's verification is that
it is recorded and cited, not that it executes. Three requirements depend on a
host capability or a live session that CI cannot reproduce (messaging
delivery, an attributed steer consumed by a busy worker, a real permission
prompt), and those carry `[manual]` alongside their automated half.

Every destructive verb additionally appears in the Task 11 adversarial matrix,
whose completeness is mechanically enforced by an expected-cell manifest;
entries below name the matrix where it is the verification of record.

## REQ-A — The lifecycle-closure contract

### REQ-A1.1 — Three parts per phase [design-level]

The floor is recorded in `doctrine/fleet-coordination-floor.md` and cited by
this bundle's REQ-A group. Verification is the artifact plus its coverage: for
each lifecycle phase the bundle touches, the doctrine names its open, its
close, and its detector, and each names the mechanism that provides it. A
phase listed with fewer than three is the failure the review looks for.

### REQ-A1.2 — Deterministic mechanics only [test + design-level]

Negative assertion across every script this bundle ships: no model or API
invocation appears in any liveness, cleanup, throttle, or kill decision path
(the existing no-LLM assertion pattern). Design-level half: the doctrine
statement forbids elapsed silence as evidence, and the detector entries below
carry the executable form.

### REQ-A1.3 — Partial closes report as partial [test]

Fixture: a stop whose attention-record release is made to fail while the
process release succeeds. Asserts a partial result with a distinct exit and a
message naming the class that could not be released, and specifically that the
call does not report success.

### REQ-A1.4 — The contract lives in doctrine [design-level]

`scripts/check-doctrine-manifest.sh` and the doc-link check pass with the new
floor in place, and the floor is reachable from the skills that cite it. The
verification is existence and citation, not behaviour.

### REQ-A1.5 — Every separate-worker backend declares all three [design-level]

A per-backend table in the doctrine names each rung's open, close, and
detector, including the trivial and deferred cases: `subagent` and
`in-session` state why the close is trivial, `print` states which parts it
defers and to whom. The review assertion is that no rung is absent from the
table and none is silently exempt — an omission is what this requirement
exists to make visible when a backend is added.

## REQ-B — Deterministic close

### REQ-B1.1 — Symmetric `stop` on both rungs [test]

One behavioural fixture table, parameterised by rung, run against both
`fleet-streamjson.sh` and `fleet-dispatch-headless.sh`. Both must pass every
cell; a cell passing on one rung and not the other is the asymmetry this
requirement exists to prevent.

### REQ-B1.2 — Children die with the supervisor [test]

Fixture: a supervisor with a child process tree. Asserts SIGTERM is sent
first, that a child ignoring SIGTERM is SIGKILLed after the bounded grace, and
that no process referencing the worker's state directory survives the call.

### REQ-B1.3 — State-dir matching, never a bare name [test]

Adversarial fixture: an operator `claude` session whose command line
resembles a worker's, running concurrently with a real worker. Asserts the
stop terminates the worker and leaves the operator session untouched. A source
audit asserts no bare-name or command-pattern match exists in the kill path.

### REQ-B1.4 — The release set, and what is never touched [test]

Asserts the five runtime classes are released, and — on every path including
refusals and partial releases — that the worktree, the branch, and the unit's
fence are byte-identical before and after. This is the assertion that keeps
D-2 and D-3 honest, so it runs on every cell of the Task 11 matrix rather than
once.

### REQ-B1.5 — `process` as a cleanup class [test]

Asserts the new subcommand reclaims a leaked process; refuses on an unknown
liveness verdict, a live-peer fence, and a self-target, each with its own exit
code and message; is paused by `fleet_daemon_pause`; and writes its audit
record.

### REQ-B1.6 — Closed from both ends [test]

Two fixtures: a unit completing normally, where the tower's close fires; and a
unit whose tower disappears mid-flight, where the periodic sweep performs the
close instead. Together they cover the path-dependence that made the leak
invisible.

### REQ-B1.7 — Idempotent close [test]

A second `stop` against an already-stopped worker returns the distinct
already-closed result with exit 0, sends no signal, and writes no second audit
record.

## REQ-C — The stuck-detector

### REQ-C1.1 — Four states, four signals [test]

One fixture per state, each establishing its state from its own signal. The
governing negative assertion: a fixture presenting only an unchanging surface
produces no state classification at all, rather than defaulting to any of the
four. This is the executable form of "every stuck state looks like silence".

### REQ-C1.2 — Blocked is detected positively [test + manual]

Automated: a captured permission-prompt fixture classifies
`waiting-on-a-human`, and a long-running-tool fixture with identical surface
stability classifies `working`. Manual: a real dispatched worker deferred at a
real prompt is confirmed to classify correctly against the running CLI, since
the prompt's rendered shape is a platform surface CI cannot pin.

### REQ-C1.3 — `finished-but-unreaped` exists [test]

Fixture: a worker whose session has ended while its process persists.
Asserts the state is produced and is distinguishable from both `working` and
`dead`.

### REQ-C1.4 — Self-reported completion is not sufficient [test]

Fixtures mirroring obs:cc13d432: a worker reporting `completed
result=success` with (a) an uncommitted tree and (b) commits absent from the
remote-tracking ref. Neither classifies finished. A negative assertion
confirms the detector performs no per-worker forge query, so the check stays
cheap and works offline.

### REQ-C1.5 — `dead` requires positive evidence [test]

Asserts `dead` only on a positive `fleet-death-evidence.sh` verdict, and that
unknown, errored, and lost-observability verdicts each classify not-dead.

### REQ-C1.6 — Owner attribution on every state [test]

Asserts each of the four states renders with each of the three attributions,
resolved from the presence surface — twelve cells — and that an unreadable
presence surface degrades attribution to unknown rather than to
this-tower's.

### REQ-C1.7 — Work-progress alongside liveness [test]

Asserts the detector reports a unit phase derived from the event stream for a
worker mid-unit, and degrades to liveness-only, visibly, where the event
stream is unavailable.

### REQ-C1.8 — Script-consumable output [test]

The output parses with the project's shell tooling under a pinned grammar;
a malformed store line degrades to a reported anomaly rather than a torn
parse. Paired with the REQ-A1.2 no-LLM negative assertion.

## REQ-D — Multi-tower safety

### REQ-D1.1 — Presence and fence consulted, no second mechanism [test + design-level]

Source audit: no new presence, registry, or exclusion store is introduced;
every destructive path calls the existing surfaces. Executable half: a
destructive verb invoked with the presence surface unreadable refuses rather
than proceeding.

### REQ-D1.2 — A live peer's worker is never terminated [test]

Task 11 matrix, run across both rungs and the cleanup class: a worker whose
unit is fenced by a live peer is refused under every evidence combination,
including positive death evidence for the worker's own session.

### REQ-D1.3 — Reaping is not reclaiming [test]

The REQ-B1.4 untouched-assertion, applied specifically to the dead-owner reap
path: fence ref, branch tip, and worktree contents are unchanged, and the
strand is still surfaced to the operator sink after the process is gone.

### REQ-D1.4 — Positive evidence on both tower and session [test]

The full evidence matrix: tower {dead, alive, unknown, errored} × session
{ended, running, unknown}. Only dead × ended reaps; every other cell refuses.
Completeness enforced by the expected-cell manifest.

### REQ-D1.5 — Owner token on the record [test]

Two dispatches under distinct tower identities produce records whose owner
tokens differ; a record with a malformed or absent owner token is refused at
write and classified unknown-owner at read.

### REQ-D1.6 — Concurrent sweeps are safe [test]

N concurrent sweeps against one fleet state: asserts exactly one termination
per candidate (no double-reap) and no candidate skipped by all sweepers (no
lost sweep), repeated under induced lock contention.

### REQ-D1.7 — Presence stays off the correctness path [design-level]

Review assertion, paired with the REQ-D1.1 source audit: no dispatch,
exclusion, or reclaim decision reads presence as authority; presence appears
only in attribution and refusal paths.

### REQ-D1.8 — `print` units register but are never reaped [test]

Asserts a `print`-backend dispatch produces a registry record, and that every
reap path refuses that record with a distinct print-exempt reason rather than
attempting a termination or classifying it dead.

### REQ-D1.9 — Clearing liveness does not clear a strand [test]

Fixture: a worker with both an attention record and a surfaced strand entry.
After a reap, asserts the attention record is cleared and the strand sink
entry is still present and unmodified — the two surfaces are independent, and
conflating them would let a reap silently erase the operator's reclaim
decision.

## REQ-E — Enumeration and inventory

### REQ-E1.1 — Every seam registers [test]

One fixture per dispatch seam asserting a registry record appears at dispatch.
A seam added without registration fails the seam-coverage manifest, so the
requirement does not silently decay as seams are added.

### REQ-E1.2 — Records are self-sufficient [test]

Asserts a close verb can act from the record alone, with the dispatching
process gone: the record carries handle, owner token, state directory,
backend, and death handle.

### REQ-E1.3 — The worktree scan runs periodically [test]

Asserts the scan executes as part of a sweep cycle and reconciles a registry
gap created by a suppressed creation hook.

### REQ-E1.4 — Registration degrades gracefully [test]

A simulated registry-write failure leaves the dispatch successful, emits a
visible warning, and self-heals on the next scan.

## REQ-F — Periodic sweep

### REQ-F1.1 — Scheduled, not threshold-triggered [test]

Asserts a sweep fires on schedule with zero leaked resources present, and that
no threshold precondition gates it. A source audit confirms the threshold
trigger is removed as the trigger of record rather than merely supplemented.

### REQ-F1.2 — An audit record per termination [test]

Asserts every autonomous termination writes a record naming worker, owner,
evidence class, and released set, and that a failed audit write does not
silently accompany a successful kill.

### REQ-F1.3 — Kill-switch gating [test]

`fleet_daemon_pause` pauses the sweep; no second pause mechanism exists
(source audit).

### REQ-F1.4 — Declined actions are reported [test]

A sweep declining every candidate reports each refusal and its reason;
asserts the output is distinguishable from a sweep that found nothing, which
is the confusion obs:1fc61ad9 and obs:49b457dc record.

### REQ-F1.5 — Trap-owned temps [test]

A SIGTERM delivered mid-sweep at each `mktemp`-beside-target site leaves no
artifact behind; asserted per site rather than once.

## REQ-G — Steer

### REQ-G1.1 — The `steer` subcommand [test + manual]

Automated: the subcommand emits a correctly attributed frame and refuses an
invalid handle. Manual: a live busy worker consumes the steer and continues
without restarting — the capability's evaluable definition, which needs a real
session.

### REQ-G1.2 — Newline framing asserted before the write [test]

Fixtures for an unterminated frame and for invalid JSON: both are refused
before any byte reaches the fifo. A concatenation fixture reproduces the
obs:33c821b8 failure shape and asserts it can no longer occur.

### REQ-G1.3 — Supervisor-native steer is primary [design-level]

The contract and the skill prose name the script-native path as primary and
messaging as fallback; verification is that the documents say so consistently
and no caller prefers messaging where the fifo is live.

### REQ-G1.4 — Messaging as a probed transport [test + manual]

Automated: the probe reports availability correctly, including on a host with
the feature disabled by environment. Manual: an attributed message is
delivered to a busy `headless-oneshot` worker and to a yielded stream-json
worker, since delivery depends on a live session and a server-side flag.

### REQ-G1.5 — Absence degrades visibly [test]

With the probe negative, the surface reports the printed-table behaviour with
a visible note; asserts the degradation is never silent.

### REQ-G1.6 — Classified as optimization, never correctness [design-level]

The contract section carries the classification, and a source audit confirms
no correctness path (fence, marker, ledger, dispatch decision) reads messaging.

### REQ-G1.7 — `--name` pinning at both launch sites [test]

Launch-arg fixtures: the pinned form derived from the validated handle is
admitted at both sites; a free-form or injected `--name` is refused. Asserts
the allowlist widened to exactly one shape.

### REQ-G1.8 — The recorded bound [design-level]

The contract states that messaging can neither answer a permission prompt nor
reach a blocked session, and that it therefore cannot discharge the
deterministic-attention floor. Verified as recorded prose, cross-checked
against the REQ-C1.2 detector entry which carries the mechanism that does.

### REQ-G1.9 — Message text is data [test]

A message containing shell metacharacters and control bytes is delivered
verbatim, never evaluated, and is sanitized before any echo.

### REQ-G1.10 — No off-machine messaging without approval [test]

Asserts the setting is present in the shipped worker profile and that the
profile parses.

## REQ-H — Lifecycle-open correctness

### REQ-H1.1 — Payload fixtures per hook event [test]

One fixture per registered event pinning its actual stdin key set, including
the `WorktreeCreate` (`name`) versus `WorktreeRemove` (`worktree_path`)
asymmetry. A fixture fails if the key set diverges from the running CLI's
schema, which is the check that would have caught obs:f51f6b6e.

### REQ-H1.2 — Decision-control hooks satisfy their contract [test]

A deliberately broken hook that exits 0 without producing its event's required
output is flagged by the check. Asserts the check also flags a hook registered
as decision-control where planwright only wants observation.

### REQ-H1.3 — Refusals are visible [test + manual]

Automated: a refusing hook's reason is emitted on a channel the harness
surfaces, not only stderr. Manual: an operator exercising the refusal sees the
reason without hand-probing the hook — the gap that made obs:f51f6b6e take a
binary inspection to diagnose.

### REQ-H1.4 — The corrected contract is recorded [design-level]

The doctrine and docs state the corrected `WorktreeCreate` contract, and
obs:a6f5511b is marked superseded in the observation trail with the correction
naming it.

## REQ-J — Carried floors

### REQ-J1.1 — Never auto-merge [test + design-level]

The existing never-merge guard surface covers this bundle's scripts; a source
audit confirms no path in this bundle merges, or marks a PR ready.

### REQ-J1.2 — No history rewriting [test]

Source audit across this bundle's scripts: no force-push, amend, squash, or
rebase path exists.

### REQ-J1.3 — Tower non-authoring boundary [design-level]

Review assertion: every verb this bundle adds is dispatch, monitor, or
reconcile; none authors repo, config, or content.

### REQ-J1.4 — No LLM in mechanics [test]

The negative assertion of REQ-A1.2 and REQ-K1.5, run over every script this
bundle ships.

## REQ-K — Cross-cutting quality

### REQ-K1.1 — Clear refusals [test]

Every refusal path across the new verbs emits a distinct exit code and an
actionable, echo-safe message naming what could not be established;
enforced by a per-path expected-message table.

### REQ-K1.2 — Artifact hygiene [test]

The repo secret scan covers this bundle's artifacts; review confirms no
internal hostname or sensitive operational detail in committed prose.

### REQ-K1.3 — Echo discipline [test]

Control-byte fixtures through every new output path assert sanitization via
the canonical sanitizer.

### REQ-K1.4 — Validated identifiers [test]

Hostile-input fixtures — traversal tokens, leading dashes, shell
metacharacters, over-length tokens, embedded control bytes — are refused at
every handle and path entry point before use.

### REQ-K1.5 — No-LLM negative assertions [test]

Shared with REQ-A1.2 and REQ-J1.4; listed here so the cross-cutting group has
its own coverage row.

### REQ-K1.6 — Knobs documented and layered [test]

Every knob introduced resolves through the four overlay layers and has a row
in `docs/options-reference.md`; `scripts/check-options-reference.sh` enforces
it.

### REQ-K1.7 — Graceful degradation [test]

Absence fixtures for each dependency — no tmux, no remote, no `gh`, no
messaging, no presence surface — assert a surfaced degradation and a
non-failing run.
