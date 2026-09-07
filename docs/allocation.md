# Model allocation: which model runs a unit, and why

Every time planwright launches work — a fleet dispatch, a single-spec
`/orchestrate` dispatch, one of `/execute-task`'s per-step sessions, an
`/offload` — it resolves a **tier** for that launch. A tier is a joint point:
one model alias and one reasoning effort, chosen together.

This guide is the operator's view of that policy. It answers six questions
without sending you to the source:

- how to enable adaptation and set a starting tier;
- how the ladder steps, and how several events stack at one boundary;
- how to cap how far a unit may travel;
- how to read a clamp or a degraded-mode decision off the ledger;
- what happens to a worker's petition once it has been weighed;
- how the legacy `fleet_*` knobs relate to the general `allocation_*` family.

Per-knob detail lives in the [options reference](options-reference.md); the
four-layer config model is in [Customizing with overlays](overlays.md); the
budget machinery this policy consumes — the usage signal, the restriction
ladder, the per-tier caps — is in [Fleet operation](fleet.md).

Commands below are written `scripts/<name>.sh`, relative to a planwright
checkout or the installed plugin root.

## The shipped posture: the mechanism is dark

**Configure nothing and nothing changes.** This is worth stating plainly,
because the machinery described below is elaborate and none of it is running
on a default install:

- the nine fleet-keyed selection knobs ship `unset`, which leaves the legacy
  `fleet_*` table in charge and reproduces today's dispatch exactly;
- every non-fleet surface ships the `inherit` sentinel, so the resolver is
  consulted, applies nothing, and the launch keeps its ambient model;
- every per-step knob ships `inherit`, so each step runs at its unit's tier;
- `allocation_adaptation` ships `off`, so no tier ever moves.

No unit runs on a different model, at a different effort, or at a different
cost than it did before this capability landed. The only observable difference
is telemetry: new ledger rows, and a sparse mirror of governance events into
the shared audit trail. Turning any of it on is a deliberate, reversible
overlay edit.

Two parts of the mechanism are **complete but not yet wired to a caller**, and
are called out again where they are described: the per-step tiers (nothing
passes a step type at a launch yet) and the feedback evaluation (nothing
invokes it at a unit's terminal state yet).

## The knob family, and how `fleet_*` fits

Selection is a table with three columns — **model**, **effort**, and
**command** — resolved per **selection key**. There are six keys:

| Selection key | The work it prices |
| --- | --- |
| `execution` | the `/execute-task` workhorse — judgment-heavy unit execution |
| `bookkeeping` | the `--bookkeeping` sweep: drain plus PR reconcile |
| `drain` | the read-only gate pass |
| `orchestrate_dispatch` | a single-spec `/orchestrate` dispatch |
| `execute_step` | one of `/execute-task`'s per-step sessions, under `per-step` `dispatch_isolation` |
| `offload` | an `/offload` dispatch |

The first three are the **fleet task types**; the last three are the non-fleet
surfaces. Only a fleet dispatch consumes the command column, because only a
fleet dispatch turns a selection into a slash-command invocation.

Each column resolves in a strict three-step precedence:

1. `allocation_<column>_<key>` — the general, surface-agnostic knob.
2. `fleet_<column>_<key>` — the legacy knob, consulted **only** at the three
   fleet task types, and **only** when step 1 resolved to `unset`.
3. the shipped default.

The chain short-circuits at step 1: once a general knob resolves to anything
other than `unset`, the legacy knob is never read.

That is what makes the `fleet_*` family a **deprecated fallback** rather than a
dead one. Core ships all nine general fleet-keyed knobs as `unset` precisely so
the legacy family stays in charge, which is why an overlay written years ago
against `fleet_model_execution` keeps working untouched and needs no migration.
The legacy family is documented, never removed. Setting the general knob is how
you take over; leaving it `unset` is how you defer.

The two sentinels are the whole opt-in story:

| Sentinel | Where it ships | What it means |
| --- | --- | --- |
| `unset` | the nine `allocation_*` fleet-keyed knobs | "not set here" — arm the `fleet_*` fallback |
| `inherit` | the three non-fleet surfaces, and every per-step knob | consult the resolver, apply nothing, keep the ambient value |

`inherit` is legal only where a launch has something to inherit *from*. At a
fleet task type it is refused as out-of-enum, because fleet dispatch launches a
fresh session with no ambient tier to keep.

Legal values are fixed enums: models are the stable Claude Code aliases
(`haiku`, `sonnet`, `opus`, `fable` — aliases, not dated model ids, so the enum
survives model releases), efforts are `low`, `medium`, `high`, and commands are
the closed dispatch-entry set `execute-task`, `orchestrate`, `drain`. That
command enum is exactly the set of non-nestable entry points, which is how the
review-sequence-disjointness invariant holds at every overlay layer: a
`review_sequence` skill can never also be a dispatch command.

## Turning it on

Two independent decisions: what tier a unit **starts** at, and whether that
tier is allowed to **move**.

Both are overlay edits. The two layers you will most likely use, of the four the
[overlay model](overlays.md) defines:

| Layer | File | Scope |
| --- | --- | --- |
| repo-tracked | `<repo>/.claude/planwright.yml` | the team, committed |
| machine-local | `<repo>/.claude/planwright.local.yml` | this machine, gitignored |

Keys are **flat**, one `key: value` per line. Nesting them under a map is not a
different spelling of the same thing — the parser will not see them at all. A
value outside a knob's enum is malformed, and the by-layer policy in
[Customizing with overlays](overlays.md) applies: a repo-tracked layer
hard-fails, while an adopter or machine-local layer warns loudly and degrades
rather than failing the run.

### Setting a starting tier

A unit's starting tier is whatever its selection key resolves to:

```yaml
# Take over the fleet execution tier from the legacy knob.
allocation_model_execution: opus
allocation_effort_execution: high

# Give a non-fleet surface a tier, instead of inheriting the ambient one.
allocation_model_offload: haiku
allocation_effort_offload: low
```

The starting tiers you get out of the box. At the three fleet task types these
values arrive through the *legacy* `fleet_*` knobs, since the general ones ship
`unset`:

| Selection key | Model | Effort |
| --- | --- | --- |
| `execution` | `opus` | `high` |
| `bookkeeping` | `sonnet` | `medium` |
| `drain` | `sonnet` | `low` |
| `orchestrate_dispatch`, `execute_step`, `offload` | `inherit` | `inherit` |

### Enabling adaptation

```yaml
allocation_adaptation: "on"
```

Quote the value. planwright's own config reader is line-based and takes it
either way, so an unquoted `on` resolves identically today — but `on` and `off`
are YAML 1.1 booleans, so a strict YAML linter flags them and another reader
could change their type. The shipped config quotes them for exactly that
reason. Do the same for any knob whose value is `on` or `off`,
`allocation_petition` included.

With it on, the engine derives the unit's current tier from that unit's own
ledger and may move it one rung per triggering incident at each launch
boundary. With it `off` — the shipped value — the answer is byte-identical to
static selection, and a trigger event is inert.

A **launch boundary** is any point where planwright starts a session or agent
for a unit: its first launch, a step relaunch, or a retry. Tiers move only
there, which is why there is no mid-run oscillation to worry about.

One prerequisite is easy to miss: **an inheriting key has no ladder.** A
selection key whose starting tier is `inherit` has no position to move from, so
adaptation does nothing there. To adapt a non-fleet surface you must give it a
concrete tier first.

### Which knob won

When a value is not what you expected, ask rather than reasoning about layers.
`scripts/config-get.sh --explain <knob>` prints `<layer><TAB><value>` — the
layer that supplied it and what it said:

```text
$ scripts/config-get.sh --explain allocation_adaptation
core    off        # <- a literal TAB separates the two
```

That is the provenance surface; the allocation resolvers themselves take no
`--explain`.

Two precedences are at work, and they compose in one direction only. The
**family** precedence above runs first and across all layers at once: the
resolver reads `allocation_<column>_<key>` through the whole four-layer stack,
and only if the answer is `unset` everywhere does it look at
`fleet_<column>_<key>`. The **layer** precedence (last layer wins) settles which
value a single knob resolves to *within* that lookup. So a general knob set in
any layer beats a legacy knob set in any layer, including a more specific one:
`allocation_model_execution` in an adopter layer still outranks
`fleet_model_execution` set machine-locally.

The four adaptation knobs and their shipped defaults:

| Knob | Default | What it does |
| --- | --- | --- |
| `allocation_adaptation` | `off` | the master switch; `off` means no tier ever moves |
| `allocation_adjustment_cap` | `2` | net applied steps a unit may travel, in each direction |
| `allocation_petition` | `on` | which petition directions are weighed; subordinate to the master knob |
| `allocation_feedback_threshold` | `2` | applied escalations that make a unit worth reporting |

`allocation_petition` takes `on`, `off`, `escalate-only`, or `de-escalate-only`.
It ships `on` and still changes nothing, because it is subordinate: with the
master knob `off` there is no ladder position to move, so the petition channel
is never read.

### Per-step tiers

Separate knobs price one *step* of a unit rather than the whole unit, one pair
per step class. **These are not gated by `allocation_adaptation`**: a step tier
is static configuration that moves no ladder and reads no signal, so it applies
with the master knob `off` exactly as with it `on`. It appears in this section
because it is the other way to influence what a launch runs on, not because it
needs adaptation.

```yaml
allocation_model_step_implementation: inherit
allocation_effort_step_implementation: inherit
allocation_model_step_polish: inherit
allocation_effort_step_polish: inherit
allocation_model_step_self_review: inherit
allocation_effort_step_self_review: inherit
```

The key space is open: a review skill added later needs no row, because its
knob is absent from every layer and resolves to `inherit`. The knob name is the
skill name with `-` written as `_`.

Application is **one-directional**. A step tier applies only when it is
*strictly cheaper* than the unit's current tier, and then only for that step's
launch, scope-marked in the ledger. An equal or more expensive one is ignored
with a ledger row, so a step can lower its own launch and can never move the
unit's own ladder position. The two columns compose: leave one `inherit` and it
is filled in from the unit's tier before the comparison. And because a step
tier needs a unit tier to be cheaper *than*, a configured step tier at a key
that itself `inherit`s is refused with a ledger row — give the surface a tier
first.

"Cheaper" here is the cost comparator described below, which is model-major. So
a step tier of `sonnet`/`high` is strictly cheaper than a unit tier of
`opus`/`low` and does apply — *raising* that one launch's effort while lowering
its model. One-directional constrains the cost, not each dimension separately.

**Not yet reachable.** No launch point passes a step type today, so setting one
of these changes nothing at all until a caller does. The knobs, the resolver,
and the one-directional rule are complete and tested; the wiring is not there.

## The ladder: how a tier moves

### The step rule

Escalation raises **effort first**, then the **model**:

- while effort is below `high`, raise effort one level and keep the model;
- once effort is `high`, raise the model one alias and **keep effort `high`**.

De-escalation has two cases, and the difference matters:

- **Reversing.** If the unit has an escalation that has not yet been reversed,
  a de-escalation **pops it** — restoring exactly the tier that escalation
  climbed from. Climb twice and come down twice and you are precisely back
  where you started, not merely two steps lower by some other route.
- **Below the start.** With nothing left to reverse, de-escalation mirrors the
  step rule: lower effort until `low`, then lower the model one alias keeping
  effort `low`.

That distinction is why "net zero" really does mean "back at the starting
tier": the downward move is a pop of the escalation stack, not an independent
walk down a different path.

So the escalation path, from the bottom of the ladder to the top, is:

```text
haiku/low -> haiku/medium -> haiku/high -> sonnet/high -> opus/high -> fable/high
```

Both ends are **hard stops**. A further escalation at `fable`/`high` is a no-op
with a ledger row, and so is a further de-escalation at `haiku`/`low`; neither
one errors, and neither one wraps.

### Two orderings, deliberately different

Two separate things are called "the ladder" in casual speech, and they are not
the same ordering. Keeping them apart is what makes a ledger row readable.

**The movement path** is the successor rule above — effort first, then model.
It is the route a tier travels.

**The cost comparator** is what answers "is this tier cheaper than that one".
It is **model-major, effort-minor**: every `opus` point outranks every `sonnet`
point regardless of effort. The one-directional per-step test uses it directly,
and so does the feedback loop's "ended above where it started" check. The
clamps work from the same two underlying orders without the joint comparator —
the downshift ceiling caps each dimension independently, and a per-tier cap
walks the model order alone.

The underlying orders are `haiku < sonnet < opus < fable` for models and
`low < medium < high` for effort. The comparator sorts by model first and uses
effort only to break ties within one model; the movement path does not.

The consequence: the successor path deliberately **skips** cost-order points.
From `sonnet/high` the next rung is `opus/high` — never `opus/low`, even though
`opus/low` sits between them in cost order. The path is not a walk up the cost
ordering, and reading a ledger with the wrong one in mind is the likeliest way
to misread a row.

### Starting tier determines headroom

Because the model ladder is only four aliases deep and escalation pins effort
to `high` after the first model jump, a high starting tier leaves very little
room to climb:

| Starting tier | Rungs before the hard stop |
| --- | --- |
| `haiku`/`low` | 5 |
| `sonnet`/`medium` | 3 |
| `opus`/`high` (the shipped `execution` tier) | 1 |
| `fable`/`high` | 0 |

A unit started at `opus`/`high` has exactly **one** rung left before the top.
This is the non-obvious consequence of configuring a high starting tier: you
buy capability up front and spend the adaptation headroom to get it. If you
want a unit to be able to climb in response to trouble, start it lower.

### Events, and how they stack

A tier moves only on **work-shaped** events, reported at a launch boundary. The
closed allowlist:

| Event class | Direction | What it means |
| --- | --- | --- |
| `step-failure` | up | a step failed |
| `retry` | up | a step is being retried |
| `flailing` | up | the stuck-detector classified the worker as making no progress |
| `non-convergence` | up | a review sequence did not converge |
| `petition-escalate` | up | a worker asked for a more capable tier |
| `petition-de-escalate` | down | a worker asked for a cheaper tier |

Infrastructure trouble — an audit write error, a config hard-fail, a backend
launch error — is **refused**, not counted. No model tier fixes a broken
launcher, and counting it would burn the unit's adjustment budget on mechanism
trouble.

Every event carries an idempotency identity of **unit, step, attempt, and
incident class**, and the incident classes collapse like this:

- `step-failure` and `retry` share the incident `step-failure`;
- `flailing` is its own incident;
- `non-convergence` is its own incident;
- all three petition event classes — `petition-escalate`,
  `petition-de-escalate`, and the bare `petition` class used for a petition
  that was consumed without being weighed — share the incident `petition`.

**At one launch boundary, each distinct incident contributes at most one
rung**, and each applied rung appends its own ledger row. So a failure and the
retry it caused move the tier one rung and write one adjustment row, while a
failure plus a flailing classification are independent incidents and move it
two rungs with two adjustment rows. Every boundary then appends its own
`launch` row on top of whatever adjustment rows it wrote, so the boundary in
that second case leaves three rows in total.

Because all three petition classes share the single incident `petition`, at
most one petition-derived rung lands per boundary however many petition records
that boundary produces.

**A later attempt is a fresh identity.** Because `attempt` is part of the key,
a step that fails, is retried, and fails again reports its second failure under
a new attempt number — a new identity, which moves the tier again. The collapse
rule prevents double-counting one incident *within* a boundary; it does not
freeze a unit that keeps failing across boundaries. A crash replay, by
contrast, re-derives from the same rows and does not double-count.

Six further event classes appear in the ledger but move nothing — `launch`,
`inherit`, `degraded`, `petition`, `feedback`, and `step-tier`. They are
records, not triggers; derivation walks past them.

## Capping how far a unit may travel

```yaml
allocation_adjustment_cap: 2
```

The cap bounds a **net count of applied ladder steps**, in each direction: at
most this many net up-steps, and this many net down-steps. It counts steps
taken, not distance travelled — a distinction that matters only once a unit has
gone *below* its starting tier, since down-steps there mirror rather than
reverse. It is a *net* figure, so **reversals refund**: a unit that escalates
twice and is then talked back down once has spent one step of its upward
budget, not three.

The cap, not the ladder, is what usually limits a unit in practice. The
headroom table above counts rungs to the hard stop; a unit at the default cap
of `2` stops two applied steps from where it started, whichever comes first.

- `0` freezes a unit at its starting tier while leaving the ledger and every
  record intact — the audit without the movement.
- The **ladder ends are hard stops regardless of the cap**. A generous cap
  cannot lift a unit past `fable`/`high`.
- A petition spends the same budget as any other trigger. It buys no exemption.

An escalation the cap refuses is recorded with the outcome `denied` and
`reason=adjustment-cap`, so an exhausted budget is visible rather than silent.
A unit that keeps failing and cannot escalate gets no new stuck state: the
existing crash-loop backoff and disable thresholds govern, and the ledger is
what explains *why* escalation was unavailable when that reaches a human.

## Reading the ledger

The ledger is how you answer "why did this unit run on that model". It is an
append-only store, one file per unit:

```text
<fleet-home>/allocation/<unit>.tsv
```

`<fleet-home>` is planwright's cross-spec state directory — the same home the
fleet's own state lives under. It is derived, not a config knob; only the
`PLANWRIGHT_FLEET_STATE_DIR` environment variable overrides it. Rather than
reconstruct the path, ask:
`scripts/allocation-ledger.sh home` prints `<fleet-home>/allocation`, and
`path <unit>` prints one unit's file; listing that directory is how you find
which units have ledgers at all.

A **unit id** is the identity the dispatching surface uses for the unit. For a
spec task — which is what fleet dispatch and `/orchestrate` launch — it looks
like `<spec>:task-<n>`, for example `model-allocation:task-7`.

| Command | What it gives you |
| --- | --- |
| `allocation-ledger.sh rows <unit>` | the unit's full history, one row per record, no header |
| `allocation-ledger.sh derive <unit> <start-model> <start-effort>` | six TAB-separated fields: the model and effort those rows imply, net displacement, unreversed-escalation stack depth, rows scanned, and applied-escalation count |
| `allocation-ledger.sh last-tier <unit>` | the tier the unit's last real launch used |
| `allocation-ledger.sh health <unit>` | exit `0` healthy, `3` unhealthy, with the offending row named |
| `allocation-ledger.sh stats [<unit>]` | units, rows, bytes, and derivation cost |
| `allocation-ledger.sh home` / `path <unit>` | where the store, or one unit's file, lives |

To ask what a unit *would* resolve to right now, rather than what it did:

```sh
scripts/allocation-adapt.sh resolve <unit> --key <selection-key> \
  [--step <step>] [--attempt <n>] [--event <class>]...
```

It prints TAB-separated `key<TAB>value` lines: `admit` (`yes` or `withheld`),
`model` and `effort` (the resolved tier, `inherit` at an inheriting surface, or
`-` when the unit was withheld), `command`,
`concurrency`, `rung`, `reserved`, `adaptation`, `proposed_model` and
`proposed_effort`, `net`, `step_scope`, `degraded`, and `petition`.

**On growth, honestly.** The store is append-only and there is no compaction
today: a unit's file grows by one row per launch plus one per adjustment, and
it is retained after the unit finishes. Per-unit files keep each scan bounded
by that unit's own history rather than the fleet's, so this is a disk-space
question rather than a latency one, and `stats` is how you watch both — it
reports units, rows, bytes, and derivation cost, and the same numbers surface
through `fleet-stats.sh render`.

Derivation is **memoryless**: it replays the rows against the *configured*
starting tier you pass in, which you read off the selection key's knobs (or the
shipped table above). The tier is never stored as a current value, so the same
rows plus the same config always yield the same answer — and changing the
configured starting tier moves the whole replay with it.

### The row schema

One TAB-separated row per record, fifteen fields, in this order:

| # | Field | What it holds |
| --- | --- | --- |
| 1 | `seq` | per-unit sequence number, from 1, strictly increasing |
| 2 | `ts` | epoch seconds, stamped when the row was committed |
| 3 | `unit` | the unit this ledger belongs to |
| 4 | `step` | the step identity, or `-` |
| 5 | `attempt` | the attempt number, or `0` for a row belonging to no attempt |
| 6 | `event` | the event class |
| 7 | `prop_model` | proposed model — what the ladder wanted, before any clamp |
| 8 | `prop_effort` | proposed effort, likewise |
| 9 | `clamp_model` | the proposal after the budget contracts bound it, or `-` |
| 10 | `clamp_effort` | likewise |
| 11 | `res_model` | the model this row settled on, or `-` if it settled on none |
| 12 | `res_effort` | likewise for effort |
| 13 | `scope` | `unit` (the unit's own history) or `step` (this launch only) |
| 14 | `outcome` | what the row did — see below |
| 15 | `inputs` | a bounded `key=value;...` list explaining the decision |

The three tier pairs are the heart of it. **Proposed** is what the policy
wanted, **clamped** is what the budget allowed, and **resolved** is what the
row settled on. Only a `launch` row fills all three, and there `resolved` is
what actually ran. On an adjustment row the clamp columns are `-` and
`resolved` is the tier the ladder moved *to* — not a launch, which is why the
launch row that follows repeats it. A row that settled on nothing at all — a
denial, a withheld unit — carries `-` in the resolved columns.

`step` (field 4) is the caller's **step identity**, a free-form label for which
step of the unit this was, such as `impl`. It is not the **step type** that
keys the per-step knobs (`implementation`, `polish`, `self-review`); the two
are different vocabularies and a row carries only the former.

A few tokens appear in both the `event` and the `outcome` column with different
meanings — `inherit` and `degraded` most notably. `event` says what kind of
record this is; `outcome` says how it resolved. A `launch` event can carry a
`degraded` outcome, which is exactly what a degraded launch looks like.

The `outcome` column takes one of nine values:

| Outcome | Meaning |
| --- | --- |
| `resolved` | a routine launch-boundary resolution — the normal launch row |
| `applied` | a ladder rung actually moved — or, on a `step`-scoped `step-tier` row, a cheaper step tier took effect for one launch |
| `withheld` | the restriction rung refused to admit the unit at all; no tier was resolved |
| `denied` | an escalation, or a de-escalation, was refused; `inputs` names why — `reason=signal-unavailable`, `reason=clamp-input`, or `reason=adjustment-cap` |
| `ignored` | something was consumed and deliberately not acted on |
| `no-op` | nothing to do — typically the ladder top or floor |
| `inherit` | the launch kept its ambient value |
| `degraded` | the launch happened with an untrustworthy read |
| `recorded` | the once-per-unit terminal-state feedback mark |

### A worked history

This is a real history, re-columned for reading, for an `execution` unit whose operator
configured a starting tier of `sonnet`/`low`, with `allocation_adaptation` on
and `allocation_adjustment_cap` at its default of `2`. Fields are
TAB-separated; the timestamps are elided as `...` and the rows are wrapped
here, but every column is present, in schema order.

```text
1 ... planwright:task-12 impl 1 launch       sonnet low    sonnet low    sonnet low    unit resolved key=execution;rung=normal;clamps=none;signal=20;adaptation=on;step=none
2 ... planwright:task-12 impl 2 step-failure sonnet medium -      -      sonnet medium unit applied  trigger=step-failure;dir=up;net=1
3 ... planwright:task-12 impl 2 launch       sonnet medium sonnet medium sonnet medium unit resolved key=execution;rung=normal;clamps=none;signal=20;adaptation=on;step=none
4 ... planwright:task-12 impl 3 step-failure sonnet high   -      -      sonnet high   unit applied  trigger=step-failure;dir=up;net=2
5 ... planwright:task-12 impl 3 flailing     sonnet high   -      -      -      -      unit denied   trigger=flailing;reason=adjustment-cap
6 ... planwright:task-12 impl 3 launch       sonnet high   sonnet high   sonnet high   unit resolved key=execution;rung=normal;clamps=none;signal=20;adaptation=on;step=none
```

Read it as a story. Row 1: the unit launched at its starting tier, nothing
bound. Row 2: attempt 2's step failure moved it one rung, to `sonnet`/`medium`
(`net=1`), and row 3 is the launch that used it. Row 4: attempt 3 failed again
— a new attempt, so a new identity, so another rung — to `sonnet`/`high`
(`net=2`). Row 5: a `flailing` event at the same boundary was an independent
incident and would have stacked, but the adjustment cap of `2` was now spent,
so it was `denied` with `reason=adjustment-cap` and both resolved columns `-`.
Row 6 launched at `sonnet`/`high` regardless.

Note the ordering within a boundary: adjustment rows first, then the `launch`
row that used their result. Attempt 3 wrote three rows — two adjustments and
one launch.

### Reading a clamp

**A clamp is not an outcome, and it is not a de-escalation.** This is the
single most common misreading. A clamped launch still carries the outcome
`resolved`; the clamp is recorded in the `inputs` column, under the `clamps=`
key. Here is a real row for an `execution` unit an operator started at
`fable`/`high`, launched with the weekly usage window at 58%:

```text
1 ... planwright:task-13 impl 1 launch fable high opus high opus high unit resolved key=execution;rung=normal;clamps=cap;signal=58;adaptation=on;step=none
```

It **proposed** `fable`/`high`, a per-tier budget cap **clamped** it to
`opus`/`high`, and that is what **resolved**. So the answer to "why did this run
on opus when I configured fable" is in one row: `clamps=cap` at `signal=58`.
The `fable` cap threshold is `55` and the `opus` cap threshold is `70`, so at 58
`fable` was withdrawn and `opus` was the nearest surviving cheaper model, with
effort preserved.

That row also shows that a cap can bind while the rung is still `normal`. The
two read different things: the restriction rung compares **each** usage window
against its own threshold, while `signal=` and the caps use the **more
restrictive** of the two. Here the `fable` cap (55) sits below the weekly
downshift threshold (60), so a weekly reading of 58 withdrew `fable` while both
windows were still under their rung thresholds. `rung=normal` beside a binding
cap is not a contradiction.

The members `clamps=` can carry:

| Token | What bound |
| --- | --- |
| `none` | nothing bound |
| `defer-all` | the rung withheld the unit entirely |
| `defer-heavy` | the rung withheld a unit in the heavy band (`opus`, `fable`) |
| `downshift` | the downshift ceiling cut the model, the effort, or both |
| `cap` | a per-tier budget cap stepped the model to the nearest surviving cheaper one, effort preserved |
| `reserved-exempt` | the unit was dispatched reserved, and the clamps passed it through |

The vocabulary those tokens come from belongs to the budget machinery this
policy consumes unchanged, documented in [Fleet operation](fleet.md):

- the **restriction rung** is the account-wide throttle position, climbing
  `normal` → `downshift` → `reduce-concurrency` → `defer-heavy` → `defer-all`;
  it appears as `rung=`;
- the **usage signal** (`signal=`) is the percentage of the account's usage
  window consumed, so higher is more constrained; `unavailable` means it could
  not be read;
- the **per-tier caps** (`fleet_cap_fable`, `fleet_cap_opus`,
  `fleet_cap_sonnet`, `fleet_cap_haiku`) each withdraw one model once usage
  reaches their threshold — the more expensive the tier, the lower the
  threshold. They are **inactive while the signal is unavailable**: with no
  reading there is nothing to compare against, so no cap binds;
- the **downshift ceiling** (`fleet_downshift_model`, `fleet_downshift_effort`)
  caps model and effort independently from the `downshift` rung upward;
- a **reserved** unit is one dispatched `--reserved`, the operator's "keep the
  capable tier for the genuinely hardest unit"; it is exempt from `downshift`,
  `defer-heavy`, and the caps, but still yields at `defer-all` and at the
  reactive throttle wall. It is a preference honored up to the fleet-critical
  rung, not an inviolable floor.

Crucially, a clamp leaves the unit's **own ladder position untouched**. The
next boundary proposes from where the ladder actually is, not from where the
clamp pushed the last launch. That is why a clamped proposal is never recorded
as a de-escalation. Exactly one thing moves a unit's own ladder position down:
a de-escalate petition. A cheaper per-step tier lowers one launch without
touching that position, which is why its row is `step`-scoped.

A **withheld** unit is not a failure. The restriction rung declined to admit it
at all, so no tier was resolved and the dispatch returns to the existing defer
path to be attempted again at a later boundary, when the rung has eased.

### The `inputs` keys

`inputs` is the column that explains the row. Which keys appear depends on what
kind of row it is:

| Key | On which rows | What it holds |
| --- | --- | --- |
| `key=` | launch, inherit, step-tier | the selection key that priced the unit |
| `rung=` | launch, inherit | the restriction rung in force |
| `clamps=` | launch | which clamps bound, comma-separated, or `none` |
| `signal=` | launch | the usage reading, or `unavailable` |
| `adaptation=` | launch | `on`, `off`, or `suspended` |
| `step=` | launch | the per-step outcome for this launch: `none`, `inherit`, `applied`, or `ignored` |
| `step-type=` | step-tier | the step class named at this launch (`implementation`, `polish`, …) |
| `unit=` | step-tier | the unit's tier at that moment, as `<model>/<effort>` — what the step tier was compared against |
| `trigger=` | adjustment | the event class that caused the adjustment |
| `dir=` | adjustment | `up` or `down` |
| `net=` | adjustment | the unit's net applied-step count after this row |
| `reason=` | denied, ignored, no-op | why it did not apply — `adjustment-cap`, `signal-unavailable`, `clamp-input`, `ladder-top`, `ladder-floor`, `orphaned-claim`, `policy-<value>`, `inherit-surface`, or a petition refusal detail |
| `direction=` | ignored petition | the direction the filtered petition asked for |
| `backend=` | inherit | the dispatching backend |
| `cap=` | inherit | that backend's advertised `tier_control`, or `error` |
| `inherit=` | inherit | `full` or `partial` |
| `dim=` | inherit | which dimensions were inherited: `model`, `effort`, `model,effort`, or `none` |
| `cause=` | inherit | `capability` or `probe-error` |

Note that `cap` means two different things depending on where you read it:
`clamps=cap` is a per-tier **budget** cap that bound, while `cap=` on an
inherit row is the backend's advertised **capability**. Same three letters,
different columns, unrelated meanings.

### Reading a degraded-mode decision

There are two degradations, and they behave differently:

- **`ledger`** — the unit's ledger cannot be trusted: unreadable, a torn or
  short row, an out-of-enum field, a non-monotone sequence.
- **`clamp-input`** — a clamp input could not be read. Most importantly, an
  unreadable **rung** fails closed to `downshift`, so the row you read shows
  `rung=downshift` for a rung that was never actually measured. A step tier
  that cannot be compared degrades the same way.

A degraded launch is never blocked and never silent. It shows up on three
surfaces:

1. **The ledger row.** The `launch` row's `outcome` is `degraded`, and its
   `inputs` says which state the engine was in:

   ```text
   2 ... planwright:task-13 impl 2 launch opus high opus high opus high unit degraded key=execution;rung=normal;clamps=none;signal=58;adaptation=suspended;step=none
   ```

   Note that the `event` is still `launch` — it is the `outcome` that says
   `degraded`. Do not expect `adaptation=suspended` on every degraded row: it
   reads `suspended` only when the ledger is what degraded and adaptation was
   on. A degraded row may equally carry `adaptation=on` (an unreadable clamp
   input) or `adaptation=off` (adaptation off over an unhealthy ledger).

2. **The resolver's own output.** `allocation-adapt.sh resolve` prints a
   `degraded` field valued `no`, `ledger`, or `clamp-input`, alongside an
   `adaptation` field valued `on`, `off`, or `suspended`.
3. **A surfaced message**, on stderr and through the attention path that feeds
   your decision queue:

   ```text
   allocation-adapt: unit '<unit>' is launching DEGRADED — <detail>
   ```

What degraded mode *does* depends on which degradation fired:

- **`ledger`, adaptation on.** The unit launches at its **last recorded
  tier** — or at the configured starting tier when no launch row is readable —
  and all adjustments are **suspended**.
- **`ledger`, adaptation off.** The proposal is the configured starting tier,
  as it always is with the master knob off. The ill health is still reported;
  it simply has no ladder position to preserve.
- **`clamp-input`.** The unit launches at its **derived** tier and adaptation
  stays `on`. Only escalation is denied; a de-escalate petition still moves the
  ladder down.

In every case it is a launch that still happens, with the reason on the record.

Do not hand-edit or delete a ledger to clear a degradation. `health <unit>`
names the offending row:

```text
allocation-ledger: ledger '<path>' is unhealthy — row 2: 1 fields, want 15
```

The store is append-only and a unit whose ledger is unhealthy still launches,
so the safe move is to read the named row first. If it is genuinely corrupt,
retire the whole file rather than editing rows in place: move
`<fleet-home>/allocation/<unit>.tsv` aside. The next launch then finds no rows,
which puts the unit back at its configured starting tier with its history
preserved beside it for inspection.

The table above is the read path. `allocation-ledger.sh` also has `append`,
`lock`, and `unlock` verbs, which are how the engine writes rows under the
per-unit lock; they are not an operator surface, and `append` in particular is
what the "do not hand-edit" warning is about.

**An unavailable usage signal is not a degradation.** It is a known state, not
a broken read: while the signal is unavailable, escalation above the starting
tier is `denied` and a unit already above its starting tier **holds** — no
claw-back — with adaptation still `on`. A unit currently *below* its starting
tier may still climb back up to it; only the steps above the start are denied.
Only a clamp input that could not be read at all produces `degraded` with
`clamp-input`.

Governance events additionally mirror one row each into the shared fleet audit
trail under the mechanism name `allocation`, so a fleet-wide view keeps a
single surface: a withheld unit, a binding clamp, an escalation or
de-escalation, a denial, either ladder-end no-op, an inheritance, a degraded
read, and a petition that was policy-filtered or reconciled from an orphaned
claim. Routine resolutions stay in the per-unit ledger.

### Two row shapes that are not launches

A reader treating columns 7–12 as launch tiers must exclude both of these:

- a **`feedback`** row is the terminal-state mark, written after the unit's
  last launch; its tier columns *describe* the two tiers its observation names,
  and its outcome is `recorded`;
- a **`step-tier`** row records what one launch decided about a per-step tier;
  it is always `step`-scoped, and it carries `applied` the way an escalation
  does.

An outcome test alone will not separate them — use the `event` column. A
`feedback` row is `unit`-scoped just like a launch, so only the `step-tier` row
is additionally distinguished by `scope`.

## The worker petition

Every trigger above is a symptom of a unit going *badly*. The petition is the
one channel that says the opposite, and the only signal in the allocation path
a worker authors. A worker writes one at a step boundary, at a pinned path
inside its own worktree:

```text
<worktree>/.claude/allocation-petition
```

```sh
scripts/allocation-petition.sh write --worktree "$PWD" \
  --direction de-escalate --unit <spec>:task-<n> --step <step> --attempt <n> \
  --reason 'the remaining steps are mechanical'
```

The grammar is pinned and closed: exactly five lines — `direction` (`escalate`
or `de-escalate`), `unit`, `step`, `attempt`, `reason` — with the whole file
capped at 1 KiB and parsed under `LC_ALL=C`. The reason is one line of
printable ASCII, at most 200 bytes. Anything else is out of grammar, and
`write` **refuses** out-of-grammar input rather than publishing an artifact the
reader would only throw away.

**When to write one.** Petition to *escalate* when the work ahead is
categorically harder than the unit's shape suggested. Petition to
*de-escalate* when what remains is transcription or a rote sweep. Do not
petition because a step failed: that is already a trigger event, and a petition
spent on it burns budget the failure would have spent anyway.

### What happens after it is weighed

**Weighing consumes it.** Consumption starts by atomically renaming the
artifact out of the pinned path — the claim — and only then validating it, so
two boundaries racing the same unit cannot both weigh one petition. That rename
is what empties the pinned path; once the ledger row has landed, the claimed
file beside it is removed too. One petition moves the tier at most one rung,
ever; signaling again costs the worker a fresh write.

The claimed file is removed *after* the row, not before, so a crash in that
narrow window leaves an **orphaned claim** beside the pinned path. Nothing is
owed of you: the next boundary sweeps it and records it as
`reason=orphaned-claim`, which is how a crash between claim and audit becomes
ignored-with-a-record rather than a silent loss.

An invalid petition is consumed too. Leaving one in place would have it
re-parsed and re-audited at every later boundary — unbounded ledger spam from a
single hostile write. So every one of these is consumed and lands an `ignored`
ledger row carrying the reason:

| Situation | Recorded as |
| --- | --- |
| valid, weighed, moved the tier | `applied` on a `petition-escalate` / `petition-de-escalate` row |
| refused by screening | `ignored`, `reason=<detail>` — one of `grammar`, `empty`, `oversize`, `control-bytes`, `torn`, `symlink`, `not-regular` |
| written for a different unit | `ignored`, `reason=stale-unit` |
| written for a different step | `ignored`, `reason=stale-step` |
| filtered by `allocation_petition` | `ignored`, `reason=policy-<value>` |
| an orphaned claim from a crashed boundary | `ignored`, `reason=orphaned-claim` |

Note what staleness *is*: a petition goes stale on the wrong **unit** or the
wrong **step**. The attempt number is deliberately not part of that binding, so
a petition written under attempt 1 is still weighable at attempt 2 of the same
step.

The worker's `reason` prose never enters the ledger. It is sanitized and
written to stderr only, so no worker-authored free text reaches a committed
artifact.

**A petition is a hint, never an authority.** It takes the same single ladder
step as any other trigger, spends the same `allocation_adjustment_cap` budget,
and meets the same clamps, so it can never buy a tier the restriction rung or a
per-tier cap would refuse.

### Rungs with no worktree have no petition channel

The channel is a file in the worker's own worktree. Work that runs in the
operator's own session has no worktree to write into, so it has **no petition
channel** at all. That is a documented degradation, not an error: those units
still adapt on the work-shaped events, they simply cannot volunteer the signal.

## The feedback loop

When a unit reaches a terminal state — completion **or** crash-loop disable —
its history can be replayed to ask whether its starting tier was wrong:

```sh
scripts/allocation-feedback.sh evaluate <unit> --key <selection-key> \
  --terminal <completed|disabled> --scope planwright
```

`--scope` is the observation scope the fragment is filed under, the same scope
vocabulary the observations accumulator uses (`planwright` for the framework
itself, `repo` for the consuming repo).

Two conditions fire it, as an OR:

- the unit's derived final **ladder position** ended above its configured
  starting tier; or
- its count of **applied escalations** reached `allocation_feedback_threshold`
  (default `2`).

The second is the churn case the first cannot see. A unit that climbed twice
and was talked back down twice ends exactly where it started, and because a
reversal refunds the adjustment cap it does not register as budget spent
either — the applied-escalation count is the only trace it leaves.

When it fires, one observation fragment is recorded through the shared
recording helper (`scripts/obs-record.sh`), naming the spec, task, terminal
state, both tiers, the escalation count and the threshold. It carries no
worker-authored free prose. That fragment is mined by `/spec-draft`'s seed
pass, which is how chronic under-estimation reaches the next round of authoring
rather than recurring silently.

Emission is **once per unit**, marked by a `feedback` / `recorded` row in that
unit's own ledger, so a re-evaluation after a crash or a sweep does not
re-record. A recording-helper failure leaves no mark, surfaces non-zero, and
keeps the unit retryable.

**On reachability, honestly.** Two things bound how often you will see a
fragment today. First, with `allocation_adaptation` `off` — the shipped
value — nothing escalates, so neither condition is ever reached. Second,
planwright does not yet invoke this evaluation automatically at unit completion
or crash-loop disable; the terminal-state owner runs it. The mechanism is
complete and tested, and it is not yet wired to a caller.

## Why the escalation path is fixed

There is no knob for the ladder's shape. The escalation path is pinned by rule:
effort first, then the model, one rung at a time, both ends hard stops. You can
choose where a unit *starts*, how far it may *travel*, and whether it may move
at all — but not the route.

That is deliberate. A configurable ladder (`allocation_ladder`, an ordered list
whose shipped default would equal the pinned path) is **deferred**, not
forgotten, and it is gated on evidence: it lands when escalation observations
show a task class that genuinely needs a different path shape, not before. The
reasoning is the same evidence-first pattern the rest of planwright uses for
graduating a preference into core — a knob whose default equals the current
behavior adds a configuration surface, a validation grammar, and a way to get
it wrong, in exchange for flexibility nobody has yet demonstrated needing.

The feedback loop above is precisely the evidence channel that would open that
gate. This is also why a one-step-at-a-time ladder was chosen over multi-rung
jumps on severe events: one-step moves keep the ledger explanatory and the cost
surface predictable, and a severe event that recurs simply climbs again.

## Where each launch point reads the policy

Choosing a tier and applying it are two different jobs. The resolver only
chooses; **applying** it at launch belongs to the dispatching backend, per its
advertised `tier_control` capability — and that capability is **per
dimension**:

| Backend | `tier_control` | What it applies |
| --- | --- | --- |
| `tmux` | `both` | model and effort |
| `stream-json-persistent` | `both` | model and effort |
| `headless-oneshot` | `both` | model and effort |
| `print` | `both` | model and effort |
| `subagent` | `model` | model only; effort is inherited |
| `in-session` | `none` | neither; both are inherited |

`dispatch_backend` ships the semantic value `full-session`, which resolves to
the richest session-grade rung the host advertises — so on a default install
your dispatches get whichever concrete backend that selects, and its row above
is the one that applies. On a host advertising no *eligible* session-grade rung
it degrades to `subagent`, then `in-session`: precisely the two rows above that
cannot carry a full tier, so the tier you configured is the thing that quietly
stops being applied. A backend you plug in yourself advertises its own
`tier_control`, and one that does not say it can set a dimension is taken as
`none`.

A backend that can set the model but not the effort applies the model and
inherits the ambient effort, with the **partial** inheritance marked in the
ledger row. A backend that can set neither inherits both, marked likewise. A
capability probe that errors is treated as no capability — inherit, and
audited.

Inheritance is never silent. Every one of these writes an `inherit` row whose
`inputs` carries `backend=`, `cap=`, `inherit=`, `dim=`, and `cause=` — the
keys tabulated above. `cause=capability` covers any advertised capability that
does not reach the dimension, including the uncovered half of a `model`-only
backend; `cause=probe-error` means the probe itself broke. The two are
distinguished because a broken probe is operator-actionable and an advertised
`none` is not.

**The in-session rung's inheritance is its pinned degradation.** Work running
in the operator's own session — the in-session work-placement rung — inherits
the session's model and effort, and cannot do otherwise: there is no launch
parameter to carry a tier into a session that is already running. It advertises
`tier_control: none` for exactly that reason. This is a documented, audited
degradation of that rung, not a gap to be fixed; selection applies where
planwright *launches* work, and mid-session model switching is not something
the platform supports. It is also why that rung has no petition channel: it has
no worktree either.
