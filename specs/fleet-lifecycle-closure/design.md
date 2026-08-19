# Fleet lifecycle closure — Design

**Status:** Ready
**Last reviewed:** 2026-08-19
**Format-version:** 2
**Execution:** derived — see the status render

Origin-tag legend: `N` new in this bundle; `C` carried from a named source;
`O` resolved from a recorded observation; `B` decided in the drafting brief,
the elicitation session that produced this bundle, or the kickoff walkthrough
that signed it off.

## Decision log

### D-1: Altitude — a doctrine floor first, capability and mechanism beneath  (B, altitude trigger)

**Decision:** The primary deliverable is a **doctrine floor**: every worker
lifecycle phase — one **resource class** a worker acquires, each acquired and
released independently — has a deterministic open, a deterministic close, and
a script-readable stuck-detector, recorded in
`doctrine/fleet-coordination-floor.md` alongside the four floors it already
carries. The verbs (`stop`, `reap`, `steer`), the detector, and the sweep are
the capability and mechanism layers beneath it, and each is justified by the
floor rather than by its own local bug report.

The altitude trigger fired at seed gathering: the drafting brief carries
claims of exactly the shape `autopilot-reflex` names — "fix the lifecycle,
not the symptoms", "every phase of a worker's life needs three deterministic
things", and, generalising from a single monitor failure, "a stuck-detector
must enumerate the stuck states positively, because every stuck state looks
like silence". Those are altitude assertions about the deliverable's nature,
not incident reports, so the altitude was resolved before any mechanism was
designed.

**Alternatives considered:**
- Ship the verbs and the detector as mechanism only, citing the observations
  directly. Rejected because: the same gap would recur on the next rung
  added. A backend that arrives without a close verb would violate nothing,
  because nothing would say it must have one. The floor is what makes the
  omission a defect rather than a missing feature.
- Record the contract as prose in the script headers of the scripts that
  implement it. Rejected because: doctrine buried in a script is invisible to
  the next author, and `autopilot-reflex` step 5 names exactly this
  demotion — "a mechanism written into doctrine rots, and doctrine buried in
  a script is invisible".
- Spin a separate doctrine-only bundle and a separate mechanism bundle.
  Rejected because: the floor is unfalsifiable without at least one
  instantiation proving the three parts are buildable, which is the same
  reason `autopilot-reflex` paired its doctrine with two instantiations.

**Chosen because:** the recurring failure is not any one missing verb, it is
that nothing in planwright ever said a lifecycle phase owes an operator a
close and a detector. Naming the floor is what generalises to the next rung;
the verbs prove it is satisfiable.

### D-2: Reaping is not reclaiming  (C, concurrent-orchestrator-coordination)

**Decision:** A reap releases the **OS process and its runtime resources**.
It never releases, moves, or resolves the **unit of work**: the per-unit
`origin` fence, the branch, and the worktree are untouched, and a strand is
still surfaced to the operator for the reserved reclaim decision. The two
concerns are separated by name in the doctrine so a future reader cannot
collapse them.

This resolves an apparent conflict rather than creating an exception.
`concurrent-orchestrator-coordination` lists "Automatic reclaim of a dead
tower's in-flight unit" as explicitly out of scope — a hard-crashed tower's
fenced-but-unfinished unit is surfaced, "never auto-probed and
auto-reclaimed". Read carelessly, that forbids the periodic reaping this
bundle requires. Read precisely, it governs *work*, and says nothing about a
leaked process holding a file descriptor and a model budget.

**Alternatives considered:**
- Treat every autonomous termination as a reclaim and route it to the
  operator queue. Rejected because: the leak class that actually cost ~95
  hours is unattended and overnight (obs:b63a8778), so a queue item nobody is
  awake to answer closes nothing.
- Let the reaper also resolve the fence when it kills a process. Rejected
  because: that is precisely the auto-reclaim
  `concurrent-orchestrator-coordination` rejected after four kickoff runs,
  and it would let a transient evidence error free a unit for double
  dispatch.
- Leave the tension unstated and let each implementer resolve it. Rejected
  because: an unstated boundary between two destructive-adjacent verbs is how
  the next author silently widens one into the other.

**Chosen because:** the fence governs *who may work a unit*; the reaper
governs *what processes exist*. Keeping them disjoint closes the resource
leak without reopening a decision that was deliberately closed, and it gives
the reaper a rule simple enough to audit: if the act would change what a
future dispatch sees, it is not a reap.

### D-3: A close releases runtime resources, never the worktree  (B, elicitation 2026-08-18)

**Decision:** `stop` releases the worker process tree, the tmux window,
locks the worker holds, its scratch temp, and its attention record. It never
removes the worktree or the branch. Worktree reclamation stays with
`fleet-cleanup.sh worktree` and its positive-evidence checks.

**Alternatives considered:**
- Have `stop` reclaim the worktree too, on positive proof the work is safe
  (clean and pushed, merged-PR head equality, or ancestor of `origin/main`).
  Rejected because: uncommitted work lives in a worktree and the evidence
  checks have recorded gaps and a widened TOCTOU window (obs:ce589542,
  obs:6e4d884f, obs:463cdde4). A worker killed by a malformed relay frame was
  holding five commits *plus three uncommitted files* mid-debug
  (obs:33c821b8); a close that reclaimed worktrees would have destroyed them.
- Have `stop` terminate the process and merely report every other resource
  still held. Rejected because: windows, temp files, and attention records go
  on accumulating (obs:f133752c, obs:16170b3f), which defers the leak rather
  than closing it — and "close" would not mean closed.

**Chosen because:** every resource in the release set is reproducible; the
worktree is the only one holding work that cannot be recovered. Splitting on
recoverability gives two verbs with one job each, and makes the dangerous act
the one that already demands proof.

### D-4: The detector enumerates states positively, on two axes  (O, obs:50eac4ac)

**Decision:** The detector positively enumerates four states — `working`,
`waiting-on-a-human`, `finished-but-unreaped`, `dead` — each established by
its own signal, and crosses them with an owner-attribution axis: this
tower's, a live peer's, or a dead-or-unknown owner's. Absence of change is
never evidence for any state.

**Alternatives considered:**
- Infer stuck-ness from elapsed time or an unchanging surface. Rejected
  because: a monitor sampling the last pane line reported eleven identical
  heartbeats for a frozen worker (obs:50eac4ac) — the signal was stable
  because the worker was stuck. Every stuck state looks like silence, so
  silence cannot discriminate among them.
- Keep the existing three-way idle/hung/ended classification and add a
  threshold. Rejected because: it has no state for alive-but-finished, which
  is the blind spot that let completed workers sit unread and leaked
  processes accumulate (obs:b63a8778), and a threshold either false-alarms on
  slow work or misses a real block (obs:4c25e743, 55 minutes unnoticed).
- Enumerate the four states without the attribution axis. Rejected because:
  under concurrent towers the same signal means opposite things depending on
  ownership — a peer's healthy worker and a leak are indistinguishable
  without it, and the reaper would have no safe input.

**Chosen because:** a detector's job is to discriminate, and discrimination
requires a distinct positive signal per state. The attribution axis is what
makes the detector's output safe to act on when the fleet is more than one
tower wide.

### D-5: Sweep periodically, never on a threshold  (O, obs:b63a8778)

**Decision:** The sweep runs on a schedule. Threshold-triggered sweeping is
removed as the trigger of record, and every autonomous termination writes a
`fleet-audit` record naming the evidence class that justified it.

**Alternatives considered:**
- Sweep when a leaked-resource count crosses a threshold. Rejected because:
  the observation is explicit that waiting until the count is alarming is
  what produced the 95 hours; a threshold makes the alarm the trigger, so the
  damage is a precondition for the response.
- Sweep only at tower start and shutdown. Rejected because: the leaking case
  is a tower that died or moved on, so the sweep would run exactly when the
  actor responsible for running it is gone.

**Chosen because:** a periodic sweep's cost is bounded and predictable, and
it is the only trigger that still fires when the tower that created the mess
no longer exists.

### D-6: Supervisor-native steer is primary; messaging is the secondary transport  (B, research report)

**Decision:** `fleet-streamjson.sh` gains a `steer` subcommand writing an
attributed, newline-terminated frame into the worker's input fifo, and that
is the primary steer path for the rung. Cross-session messaging is adopted as
a secondary, availability-probed transport: the wake path for a yielded
worker, and — for `headless-oneshot` — the only steer that exists at all.

**Alternatives considered:**
- Messaging alone, with no supervisor subcommand. Rejected because: delivery
  is best-effort with silent-refuse, expiry, per-sender throttling, and
  identical-repeat dedup, and the send is a model tool call no script can
  emit or audit. Where a deterministic option exists, the thesis of this
  bundle requires taking it.
- The supervisor subcommand alone, with messaging rejected outright.
  Rejected because: it leaves `headless-oneshot` permanently steer-less, and
  leaves the yielded-worker wake (obs:cc13d432, four stranded yields in one
  unit) with no remedy, when a zero-infrastructure one exists in the platform
  planwright already requires.
- Keep hand-writing frames into the fifo, as the recovering tower did.
  Rejected because: that practice killed two live mid-unit workers when one
  frame lacked a trailing newline (obs:33c821b8). The absence of a sanctioned
  command is *why* towers hand-write; shipping the command is the fix.

**Chosen because:** the two are complementary rather than competing. The
script-native path is auditable and delivery-guaranteed while the channel
lives; messaging covers the case the channel cannot reach (an idle worker
that must be woken) and the rung that has no channel at all.

### D-7: No tower-to-tower messaging arm  (B, elicitation 2026-08-18)

**Decision:** Messaging is scoped to tower-to-worker steer. No messaging arm
is added for peer-tower coordination, and
`concurrent-orchestrator-coordination` REQ-D1.1 is **not** amended.

The research report recommended a tower-to-tower arm on the grounds that
"two headless or split-host towers have no relay at all today". That is
accurate and narrower than it reads: `orchestrate-relay.sh`'s tmux arm
delivers through server-global named buffers specifically so peer towers can
reach each other, and `inter-orchestrator-coordination` states that the same
attributed buffer-paste mechanism "serves both tower-to-worker relay and
tower-to-tower coordination between peer towers sharing a checkout". Towers
run under tmux, so the gap is hypothetical on the substrate in use.

**Alternatives considered:**
- Adopt the arm as the report recommends, amending REQ-D1.1 to admit a
  messaging arm of the single relay seam. Rejected because: it amends a
  standing decision to close a gap that does not bite on the substrate towers
  actually run on, and it moves part of the never-impersonate discipline out
  of the one audited script into harness behaviour plus doctrine prose.
- Defer the question with no record. Rejected because: the report is
  persuasive and durable, so a later reader would re-derive its
  recommendation and re-open the amendment. The rejection needs its reason
  attached.

**Chosen because:** the sanctioned relay already covers the real case. A
second channel would be justified only by a substrate planwright does not
currently run on, and REQ-D1.1 exists precisely to stop a second relay from
being added on a hypothetical.

### D-8: Messaging is a probed transport, not a backend row  (C, research report)

**Decision:** Messaging gets no row in the backend capability table and no
advertised-boolean change. The contract gains a **steer transports** section:
a host may advertise a messaging transport, probed deterministically, which
upgrades the *effective* steer of the two non-interactive session-grade rungs
when present and degrades visibly to the printed table when absent. It is
classified a latency and capability optimization, never a source of
correctness.

**Alternatives considered:**
- Give messaging a backend row. Rejected because: a backend hosts a worker,
  and messaging spawns nothing, owns no lifecycle, and provides neither
  observe-in-flight nor death evidence. Every column would be a category
  error.
- Flip `can_steer_inflight` to true for `headless-oneshot`. Rejected
  because: advertisement is a static property of the backend *type*, while
  messaging availability is a host and session property — version, OS,
  provider, and four common environment variables each remove it silently. A
  static `true` would lie on any host where the feature is off.

**Chosen because:** the transport framing is the only one that stays honest
on a host without the feature, and it preserves the observe/steer split the
contract deliberately refuses to fold — messaging is steer without observe,
which is the split's clearest existence proof.

### D-9: One new bundle plus two scoped amendments  (B, fold-detection 2026-08-18)

**Decision:** The lifecycle work lands as this new bundle. Two pieces route
to the bundles that already own them, as scoped amendments seeded from
`specs/_pending/`: the worker command-guard screens and worker-settings
profile delivery to `worker-permission-ergonomics`, and the deterministic
PR-ready attention record to `merge-currency-guard`.

Fold-detection scanned every bundle. Six overlap, and two ownership claims
are written down rather than inferred: `fleet-coordination-floor`'s
scope-boundary section names `merge-currency-guard` as the owner of the
deterministic PR-ready push, and obs:814c6ba9 states the guard fix "needs a
spec amendment" to `worker-permission-ergonomics`. The remainder — a close
verb, a process reaper, a stuck-state vocabulary — has no owner at all.

**Alternatives considered:**
- One bundle owning everything, citing the others as Sources. Rejected
  because: it writes into territory doctrine and an observation assign to
  other owners, which is what the scope-boundary section exists to prevent.
- Amendments only, no new bundle: split across `execution-backends`,
  `fleet-autonomy`, `worker-permission-ergonomics`, and
  `merge-currency-guard`. Rejected because: it reopens two derived-Done
  bundles, and the cross-cutting open/close/detect contract gets no single
  home, so it would be restated four times and drift — the exact failure the
  doctrine docs exist to prevent.
- Fold into `execution-backends`, which owns both rungs' scripts. Rejected
  because: its scope is the contract, the selection knob, `/offload`, and the
  status view; adding a lifecycle layer would push it past one feature a
  reader holds in their head, which is a D-21 spin-new trigger.

**Chosen because:** it puts each piece with its rightful owner while giving
the unowned contract a home, and it reopens exactly one Done bundle instead
of two.

### D-10: Lock defects scoped to those that wedge a lifecycle verb  (B, elicitation 2026-08-18)

**Decision:** Two recorded stream-json lock defects come along: the
`recover.lock` stale-break gap, which wedges the `recover` verb permanently
after one SIGKILL (obs:81ba2dce), and the missing launch initiator lock,
which lets two concurrent launches orphan a supervisor (obs:917e384e).
Everything else in the recorded set is cited as residue for a hardening
bundle.

**Alternatives considered:**
- Take the whole recorded set in one pass over the supervisor's concurrency
  surface. Rejected because: it widens the bundle from lifecycle closure into
  general supervisor hardening, and the D-21 "one feature a reader holds in
  their head" test fails.
- Take none, and build the new verbs on the locks as they stand. Rejected
  because: a close verb built on a lock with a known permanent-wedge path
  inherits the wedge, and a verb that can wedge is not a deterministic close
  — it would contradict REQ-A1.1 in the same bundle that states it.

**Chosen because:** the selection rule is principled and checkable rather
than a judgement call about severity: does the defect disable or corrupt a
lifecycle verb this bundle defines? If yes it is in scope, because the
bundle's own contract depends on it; if no, it is hardening.

### D-11: The `WorktreeCreate` contract is corrected, and hooks get payload fixtures  (O, obs:f51f6b6e)

**Decision:** The recorded `WorktreeCreate` contract is corrected: the event
supplies a worktree **name**, and a registered hook is the *creator*,
expected to produce the worktree and report its path. Every hook planwright
registers gains a payload-shape fixture pinned to its event's actual input
schema, and a decision-control hook is verified to satisfy its event's output
contract. The minimal unblocking fix ships out of band as a chore PR; the
durable hardening is a task here.

The defect was hit live while drafting this bundle: `EnterWorktree` refused
twice, because `fleet-worktree-track.sh hook-create` extracts
`.worktree_path` from an event that carries `name`. Only `WorktreeRemove`
carries `worktree_path`. The hook found nothing, warned to discarded stderr,
and exited 0, so the harness failed creation for a reason no operator could
see — and because a registered `WorktreeCreate` hook replaces native git
worktree creation, this broke worktree creation on every installed machine.
Confirmed identical across CLI 2.1.226, 2.1.233, and 2.1.234, so it is not a
platform regression.

**Alternatives considered:**
- Fix the hook and stop there. Rejected because: the same class recurs on the
  next schema change, and the fixture is what converts a silent fleet-wide
  outage into a failing test.
- Unregister the hook permanently and abandon worktree tracking. Rejected
  because: the registry is a prerequisite for the reaper's inventory
  (REQ-E1.1); tracking is wanted, the *decision-control* registration is what
  was wrong.
- Treat obs:a6f5511b as still authoritative. Rejected because: it records the
  contract as "echo the stdin `worktree_path` unchanged", which is what
  shipped, and is the direct cause. It is superseded, not merely supplemented.

**Chosen because:** the failure is this bundle's own thesis firing on
planwright — a lifecycle open with no deterministic contract and no legible
signal when it refused — so the bundle would be incoherent if it left the
open uncorrected while specifying the close.

### D-12: The dispatch record gains an owner token  (O, obs:10407a5e)

**Decision:** Registry and dispatch records carry an owner token identifying
the dispatching tower, and the registry gains a live writer at every dispatch
seam.

**Alternatives considered:**
- Keep the ownerless timestamp marker and infer ownership from the presence
  surface alone. Rejected because: the marker "carries no owner token", so
  the primitive alone cannot serialize two concurrent dispatches of the same
  task (obs:10407a5e), and inference from a separate surface is exactly the
  indirection that makes a reaper's safety argument unverifiable.
- Have the reaper act only on workers it launched in this session. Rejected
  because: it cannot reach an abandoned worker whose tower is gone, which is
  the leaking class.

**Chosen because:** a destructive verb needs attributable ownership as an
input, and reading it from the record is direct where deriving it is
inferential. It also removes a known dispatch race as a side effect.

### D-13: The floor is proven by a deliberate-wedge rehearsal, not by fixtures alone  (B, kickoff 2026-08-18)

**Decision:** The bundle adds a repeatable, opt-in end-to-end rehearsal: a real
worker dispatched against a throwaway spec bundle, deliberately wedged at a
permission prompt, then asserted to classify `waiting-on-a-human`, to close on
`stop`, and to leave every resource class empty afterwards.

**Alternatives considered:**
- Rely on the fixture suite and the three `[manual]` entries. Rejected
  because: the bundle's own Goal argues the leak is invisible *because* the
  common path looks tidy, and a fixture exercises the path its author
  imagined. A suite that never wedges a real worker cannot falsify the
  bundle's central claim.
- Use this bundle's own Task 1 as a one-shot live canary. Rejected as the
  verification of record because: it runs the clean path, so it proves
  dispatch works and nothing about wedging, and being one-shot it catches no
  later regression. It remains available as an informal first dispatch.
- Gate ordinary CI on the rehearsal. Rejected because: it consumes a live
  session and model budget per run, which would make every unrelated PR pay
  for it and would couple CI to a platform surface CI cannot pin.

**Chosen because:** the floor claims a worker can always be detected and
closed. The only evidence that discharges that claim is a worker that was
actually stuck and was actually closed. Making the rehearsal repeatable turns
a one-time demonstration into a regression gate, and making it opt-in keeps
its cost off every unrelated change.

### D-14: The sweep ships observing-only, promoted by an explicit knob  (B, kickoff 2026-08-18)

**Decision:** The periodic sweep ships in an observing-only mode: it selects
candidates and writes the full audit record it would have written, and kills
nothing. Autonomous termination is enabled per machine by an explicit,
reversible knob. Both modes are exercised by the D-13 rehearsal.

The kickoff gap check against `decision-domains` surfaced this: the bundle
touches the `deploy-migration` domain — a scheduled autonomous process-killer
is a fleet-wide behaviour change that cannot roll back atomically, and a reap
already performed cannot be undone by pausing future ones — while deciding
only the pause switch and the schedule knob, never the rollout itself.

**Alternatives considered:**
- Ship terminating from the first run, relying on the existing kill-switch as
  the undo. Rejected because: the first autonomous kill would land on real
  workers with no accumulated evidence that the four-state detector classifies
  correctly outside its fixtures, and the kill-switch stops only future reaps.
  The bundle's own history is a platform surface diverging silently from its
  recorded contract (D-11); the detector reads platform surfaces too.
- Scope live termination to the evidence classes the rehearsal has exercised.
  Rejected because: it couples the reaper's destructive scope to test coverage,
  so a coverage regression silently narrows or widens what may be killed, and
  the expected-cell manifest becomes load-bearing for safety rather than for
  completeness.

**Chosen because:** the dry-run's audit trail is exactly the evidence the
promotion decision needs, and it is collected on real fleets rather than
fixtures. The cost — a second path that could rot unexercised — is answered by
REQ-F1.7 rather than accepted, so the mode that ships is the mode that is
tested.
