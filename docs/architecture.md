# Architecture: the pipeline under the tower

`/tower` is planwright's front door: you ask in plain language, and it routes
each change onto one of two flight rules, **visual flight** (specless work,
where the audit record carries the trust) or **instrument flight** (the spec
pipeline). The names are the aviation analogy: visual rules when conditions
are clear enough to fly by what you can see, instrument rules when you file a
plan and trust the gauges. This guide is the machinery underneath: the commands
the tower and its workers run, both flight rules end to end, and how to drive
the pipeline by hand when you want to. None of it is required knowledge for
using the tower; the routing rule itself is
[the flight-rules doctrine](../doctrine/flight-rules.md).

## The controls you keep

The same controls hold on both flight rules, whether the tower drives the work
or you run the commands below yourself:

- **Merge.** Every PR opens as a draft, and authorizing its merge is yours on
  visual flight and instrument flight alike. That approval act is also what
  signs off every pending-sign-off item a PR carries.
- **The draft→ready flip.** It moves a finished draft in front of reviewers and
  approves nothing. The tower never performs it; whether a unit's own
  `/execute-task` run may flip a converged PR is the `ready_flip_policy`
  policy, and `human` reserves the flip to you. The one other flip is the
  spec PR's: `/spec-kickoff` marks it ready after a clean sign-off, under the
  `mark_spec_pr_ready_on_kickoff` policy.
- **Sign-off, on instrument flight.** A spec executes only after you walk it at
  `/spec-kickoff` and sign the brief; no bypass flag exists. Visual flight
  invents no shadow sign-off: a worker's hard pauses and its PR's
  pending-sign-off checklist are not one.

Pushed history stays append-only outside the force-push and secret-purge rows
of the human-gates list. The one statement of what stays human, what is a policy, and which
skill owns which act is [the human-gates doctrine](../doctrine/human-gates.md);
this section restates it and changes nothing.

## Instrument flight, end to end

```text
   /spec-draft  →  /spec-kickoff  →  /orchestrate  →  /execute-task  →  review & merge
                        ▲                                                      ▲
                    sign-off                                                 merge
                  (no spec runs                                     (the approval act
                   unsigned)                                          stays yours)

   └──── you author ────┘   └──── planwright runs the middle ────┘   └─── you decide ───┘
```

1. **`/spec-draft <feature>`** — elicit the four-file spec bundle
   (`requirements.md`, `design.md`, `tasks.md`, `test-spec.md`) at Status
   `Draft` on the spec's own branch. The tower dispatches it with your ask as
   the seed when it files instrument flight; you can also run it directly.
2. **`/spec-kickoff <spec-path>`** — walk the spec to mutual understanding,
   producing the signed-off **kickoff brief** (the durable contract every
   downstream skill executes from). On your sign-off it flips Draft → Ready
   (signed off and executable, nothing started); the first dispatch derives
   Ready → Active. The tower offers it and never starts it.
3. **`/orchestrate <spec-path>`** — pick the next ready task, create or reuse
   its worktree, and dispatch execution. Stateless: one step per invocation
   (`--watch` loops it); run it in several sessions for intra-spec
   parallelism. After sign-off the tower relays `/orchestrate specs/<spec>
   --watch` only on your explicit go, and never supervises it.
4. **`/execute-task <ids>`** — the execution workhorse, run inside the
   worktree `/orchestrate` prepared: test-first, full CI with adaptive retry,
   convergence through the configured `steps_convergence` list (default
   `/polish --nested`), then a **draft PR** referencing the brief, task IDs,
   REQs, tests, and the pending-sign-off checklist.
5. **Review and merge** — review the draft PR and merge it.

`/spec-walkthrough <spec-path>` renders a bundle (or a chosen slice) into a
plain-language, read-only comprehension artifact: an independent cold read
before sign-off, re-orientation mid-execution, or onboarding to a finished
bundle. `/drain` evaluates deferred gate conditions across specs. Both are
read-only. Progress is derived from git and GitHub evidence, not kept in a
mutable ledger; see [Orchestration state](orchestration-state.md).

## Visual flight, underneath

A visual flight is one unit of repository-changing work with no spec bundle.
The tower hands `/offload` a flight petition (the ask, the grounds line it
stated, a slug, and the record's home), and `/offload` picks the smallest
sufficient execution rung and places the flight through
`scripts/flight-dispatch.sh`: it checks live flights against
`max_parallel_units`, mints the flight id, writes the worker brief, and places
an isolated worktree on a `planwright/flight/<flight-id>` branch
([Conventions](conventions.md#flight-branches-tower-front-door-d-11)). The
worker loads full doctrine, converges through the same `steps_convergence`
list a task does, renders its audit record, and lands it: in the draft PR body
when every push destination is covered by `flight_pr_hosts` and `gh` is
authenticated, otherwise as a committed record at
`_flights/<flight-id>.md` under the spec root (`specs/_flights/` by default)
on the flight's own branch. The shared flight
sweep reconstructs what is in flight from that durable evidence, which is how
the tower answers status after a restart.

## The other machinery commands

- **`/offload <petition>`** — place one free-form petition on the smallest
  sufficient execution rung the host advertises, and report the worker's
  handle with an observe or attach hint. It is the only place backend
  selection adapts to the work; a read-only ask that outgrows the tower's
  inline bound goes through it without becoming a flight.
- **`/resume`** — load context for a fresh session landing in an in-flight
  worktree: the kickoff brief, the task state, the branch's log, the open PR,
  and any handover brief, then ask before continuing. Read-only over the
  in-flight work.

## Running the pipeline by hand

Every command above is a slash command you can type in an attached Claude Code
session; the tower is a convenience over them, not a gate in front of them.
Driving them yourself keeps every control in the list above: a hand-run
`/orchestrate` still refuses a spec that is not Ready or Active, and a
hand-run `/execute-task` still opens only drafts.

In the planwright repo itself the history invariants are also backstopped
repo-side by tracked git hooks (`githooks/`, wired once per clone via
`scripts/wire-githooks.sh`; `mise run check` fails loudly on an unwired
clone). They are accident-catchers with an honestly stated boundary
(`--amend -m`/`-F` carries no client-hook signal, so the tower profile's deny
globs refuse it and, for a worker, the policy guard's `unpushed_rewrite` check
decides it), they bind humans too, and the
deliberate bypasses are `--no-verify` for the push and commit-msg hooks and
`git rebase --no-verify` for `pre-rebase` (`prepare-commit-msg` is not
suppressed by `--no-verify`). See
[CONTRIBUTING](CONTRIBUTING.md#the-git-hook-backstop) for details.

## Fleet operation

`/orchestrate --fleet` runs several signed specs at once: it autodetects the
execution backends on your host, supervises every Ready or Active spec with one
isolated worker per task under a fleet-wide concurrency bound, and renders a
single attention surface, a decision queue plus per-worker heartbeats. The
tower's permission profile, the backend seam, and what an unattended fleet
decides without you are in [Fleet operation](fleet.md).
