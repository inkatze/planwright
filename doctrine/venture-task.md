# The Venture-Task Contract

A venture's validation plan is run one `T-<n>` task at a time, under a
contract lighter than a spec unit's: the deliverable is a findings document
committed to the venture repository, with no pull request, no CI gauntlet,
and no polish loop (inception D-13 records why). What the contract keeps is the
discipline that makes the evidence worth having: a done-when per kind, human
acceptance, and register updates that land with their findings or not at all.

[inception-format.md](inception-format.md) owns the `plan.md` task fields,
the status tokens, and the evidence grades; this doc owns how a task is run
and how its findings reach the registers.
`scripts/venture-task.sh` is the mechanical half: every step below names its
subcommand.

Citations: inception REQ-D1.1, REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-D1.5,
REQ-D1.6, REQ-D1.7, REQ-J1.3 · inception D-7, D-13.

## Kinds

Each kind fixes what is delivered, who performs it, and what acceptance looks
at. `venture-task.sh contract` prints the same table in machine form.

| Kind | Deliverable | Performed by | Acceptance looks at |
| --- | --- | --- | --- |
| `spike` | findings from a throwaway build, code under `spikes/T-<n>/` | the agent | the measured result against the linked thresholds |
| `research` | findings from sources, each claim citing one | the agent | every claim traced to a cited source |
| `analysis` | findings from data or a model, method stated | the agent | the method, then the result against the linked thresholds |
| `demand-signal` | prepared materials, then the observed signal | a human | the signal as a human observed it, graded on the ladder |
| `alignment` | prepared materials, then the recorded outcome of the conversation | a human, with the named stakeholder | the stakeholder's recorded position |

An alignment task's stakeholder is the person in the Decides cell of the
stakeholder-map row its `Target:` names; a target that names no row, or a row
with no Decides name, refuses the task.

**No autonomous external interaction.** For `demand-signal` and `alignment`
the agent prepares materials (a landing-page draft, an interview guide, an
agenda) in the findings document and stops; a human performs the
interaction, and the document is delivered only once it records who ran it
and what they observed. The agent never sends a message, posts, publishes, books a meeting,
or otherwise contacts a person outside the session, on any rung. Nothing in
`venture-task.sh` reaches the network, and `venture-task.sh worker-settings`
prints a permission deny-list for the common outward channels, which a
dispatcher passes to a worker launch that takes a settings file. That list is
a floor, not the boundary: the ban holds whether or not a channel is listed.

## The findings document

One file per task, `findings/T-<n>.md` beside the bundle, cited from the
registers as `T-<n> findings`:

```markdown
# T-<n> findings

**Task:** T-<n>
**Kind:** <the task's kind>
**Performed-by:** <the human who ran it>      (demand-signal and alignment)
**Stakeholder:** <the target's Decides name>  (alignment)

## Findings

<what was done and what was observed>

## Register updates

- A-<n>: <open | testing | validated | invalidated> — <grade, or none>
- DEC-<n>: <open | decided | deferred> — <outcome, one line>
```

`## Register updates` carries exactly one line for each id in the task's
`Tests:` field and no other id. An assumption line sets the entry's `Status:`
and, when it names a grade, sets `Evidence:` to `<grade> — T-<n> findings`;
`validated` and `invalidated` need a real grade. A decision line sets
`Status:` and `Outcome:`. Values are single lines of plain text. The agent
never writes `Performed-by:` itself: it is the human's report of who did the
work.

Spike code lives in `spikes/T-<n>/`, which carries a `DISPOSABLE.md` marker
(`venture-task.sh spike-init`). Findings graduate into the registers; spike
code never does: nothing graduated may reference `spikes/`, and
`venture-task.sh spikes` flags a spike directory without its marker and any
reference to `spikes/` from the seed paths it is given.

## Running a task

1. **Resolve.** `venture-task.sh show <venture> T-<n>` gates the bundle's
   format version, then prints the task's kind, status, linked ids, and, for
   an alignment task, its stakeholder. A `delivered` task goes to acceptance;
   an `accepted` or `dropped` task has nothing to run.
2. **Work to the done-when, within the cap.** Research, build, or prepare per
   the kind; write the findings document. A task that exhausts its `Cap:`
   without resolving stops there and says so: that is the detectable "Hold
   because tests got expensive" state, never a reason to keep spending.
3. **Deliver.** `venture-task.sh deliver <venture> T-<n>` checks the findings
   document against the task, sets the task to `delivered`, and commits the
   findings (with the spike directory, for a spike) as one PR-less commit. It
   changes no register entry.
4. **Accept or reject.** Present the findings and the proposed register
   updates to the operator, then wait. Only on an explicit yes, run
   `venture-task.sh accept --by <name> <venture> T-<n>`: it applies the
   updates, sets the task to `accepted`, appends the acceptance record to the
   findings document, and commits all of it as one change, or changes
   nothing. On a no, `venture-task.sh reject --by <name> --reason <text>
   [--drop] <venture> T-<n>` records the rejection and returns the task to
   `running` (or `dropped`) with the registers untouched.

`venture-task.sh check <venture> [<commit>]` is the structural shadow of step
4: a commit that accepts a task without its findings or without an update to
each linked entry, a commit that cites `T-<n> findings` in an assumption
without accepting `T-<n>`, and a commit that adds findings for a task it
leaves `planned` are each a finding.

On a remote-backed venture the operator may ask for pull-request review
instead: deliver on a branch and open the pull request; once the review
approves, the operator's accept commit lands on that branch, and the merge
brings findings and register updates in together.

## Dispatch

A venture task runs through the same machinery as any other unit, with no
orchestration of its own. Inline, for a light venture, the session runs the
steps above itself. Dispatched, `venture-task.sh brief <venture> T-<n>`
prints the petition (an `/execute-task` invocation naming the task and the
venture's absolute path), which goes through the backend seam like any
other: `offload-dispatch.sh` on the tmux and print rungs, the harness's agent
tool and `offload-dispatch.sh report` on the subagent rung. A dispatched
worker works through step 3 and stops: acceptance and rejection need the
operator, so they happen in the operator's session, never in the worker's.
Venture task state lives in `plan.md` and the registers, never in the spec
pipeline's `tasks.md` derivation.
