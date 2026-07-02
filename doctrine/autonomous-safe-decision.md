# Autonomous-Safe-Decision Policy

An unattended orchestration tower needs one rule for every judgment it faces:
may I take this call myself, or must a human take it? This policy answers that
question, but it introduces **no new decision taxonomy**. It is a *mapping onto*
the gate planwright already ships — the four buckets and hard pauses of
[Finding Categorization](finding-categorization.md), wired by
[Gate Wiring](gate-wiring.md). "May decide unattended" is that gate's
act-then-review half read at the orchestration tier; "must escalate" is that
gate's hard-pause half. There is no fleet-only category, and no tier at which
the gate loosens (REQ-A1.3).

Citations: REQ-A1.3, REQ-D1.4 · REQ-A1.2 (never-auto-merge floor),
REQ-B1.7 (harness permission gate), REQ-E1.3 (decision queue) ·
orchestration-fleet D-8 (extends bootstrap D-5), D-13.

## The floor: never auto-merge

Everything below describes what a tower **may** do without a human at the
prompt. None of it includes merging. The merge is the human's reserved control
at every tier — the single-tower run, the meta-tower, every rung of the
degradation ladder — and no amount of clean autonomous convergence promotes a
draft PR to merged (REQ-A1.2). An unattended fleet run's terminal state is
draft-PR-ready, never merged. The autonomy this policy grants is a ceiling that
sits well below merge; never-auto-merge is the floor beneath the whole mapping,
not one clause within it.

## May decide unattended

An unattended tower may take, without pausing for a human, exactly the
dispositions the act-then-review gate already sanctions, plus the routine
operational hygiene a worker-settings profile pre-approves. Each item names the
gate concept it maps to; nothing here is a new permission.

### The act-then-review buckets

- **Auto-applicable** — apply the fix and record the audit row. The tower takes
  this call for the same reason a gate-wired review skill does: a tool cited a
  named rule, the fix is mechanical, and nothing user-observable changes (the
  [Finding Categorization](finding-categorization.md) Auto-applicable
  predicate).
- **Agent-resolvable** — resolve the finding and record the evidence row: a
  failing-then-passing regression test, a passing project CI, and a
  brief-alignment citation. The tower may land this autonomously because the
  proof, not the tower's judgment, is what backs it (the Agent-resolvable
  predicate).
- **Needs sign-off** — apply the single recommended fix **on the branch** in its
  own commit and add a pending-sign-off checklist entry. The tower's autonomous
  act is the *application*, deferred for the human's *judgment* to PR review,
  where they approve by leaving the commit or reject with one revert. The tower
  never blocks mid-loop waiting for this approval (the Needs-sign-off bucket and
  the pending-sign-off checklist in [Gate Wiring](gate-wiring.md)).

These three are the "may decide unattended" set the policy grants. A finding
whose predicate is uncertain routes *downward* exactly as the categorization
doctrine directs — never upward into more autonomy.

### Routine operational hygiene

Beyond the buckets, a tower may take routine operational hygiene that a
worker-settings profile has pre-approved:

- **Scoped cleanups of merged workers** — reclaiming a worker window or
  worktree once its PR has merged and the session is idle, a bounded and
  reversible housekeeping act.
- **Answering routine worker questions to the tower** — continue-prompts and
  hygiene confirmations a running worker addresses *to the tower*, where the
  worker-settings profile pre-approves the answer.

**The two senses of "prompt" do not overlap.** A routine worker *question to the
tower* (may answer) is not a worker's *harness tool-permission prompt* (the
authorization gate), which a tower **never** answers at any tier (REQ-B1.7,
bootstrap D-7). The autonomy this section grants is over the tower's own
operational surface; it never reaches into a worker's harness authorization
gate.

## Must escalate / pause

The tower must hand the call to a human — it may not decide it unattended —
whenever a finding or action falls in one of the gate's two hard-pause
categories. These are the same hard pauses [Finding Categorization](finding-categorization.md)
defines; the tower inherits them unchanged.

### Hard-disqualifier zones

A finding, or any file its fix would touch, in a hard-disqualifier zone forces a
pause regardless of which bucket it would otherwise land in. The zones are the
categorization doctrine's list, carried verbatim:

- **Security-sensitive code** — authentication, authorization, secrets, crypto,
  permission boundaries, SQL or shell construction, sandbox boundaries (with the
  write-time triggers in [Security Posture](security-posture.md)).
- **Migrations or destructive operations** — schema changes, backfills, deletes,
  anything irreversible.
- **CI configuration, lockfiles, and secrets files.**

In a zone the tower records the recommended fix and does **not** apply it; the
disposition is the human's.

### Irreducible Needs-human-judgment forks

A fork the tower cannot resolve from first principles must escalate — but only
after it has climbed the resolution ladder ([Gate Wiring](gate-wiring.md)):
brief-or-spec citation, then research, then project convention. A rung that
answers re-routes the fork to the disposition the answer implies. Only forks
still irreducible after all three rungs escalate:

- **Design forks** — multiple valid approaches whose choice depends on product
  or priority calls the tower cannot derive.
- **Spec drift** — an implementation need that contradicts an accepted decision,
  alters a REQ's meaning, or adds a REQ/D-ID (meaning-class contract drift):
  the tower never edits the contract from execution; it surfaces the conflicting
  reading and routes the human to a `/spec-kickoff` delta re-walkthrough.
- **Sign-off-class decisions the human reserves** — calls the human has kept for
  themselves regardless of how clear the fix looks.

An irreducible fork that blocks further progress on the unit hard-pauses
immediately; one that does not block flows to loop end and queues there. Either
way it becomes a human decision, never an autonomous default.

## How escalations surface: the decision queue

Every escalation this policy names routes to the **decision queue** — one
ordered, alarm-rationalized queue of actionable items across all active specs,
the substrate-agnostic attention surface lifted into core (D-13, REQ-E1.3). Each
queued item is a structured choice with bespoke options (the actual decision
branches, never timing labels), so human load is bounded by the queue depth, not
the worker count.

In the dispatched or unattended arm, the queue's durable backing is the pause
protocol's halt destination: the tower records the unit to the spec's `tasks.md`
`## Awaiting input` section with the finding, the trigger, and the recommended
fix or the concrete alternatives, then ends the step
([Gate Wiring](gate-wiring.md) pause protocol). Work already applied in the loop
stays on the branch as committed — a pause never resets, stashes, or rewrites a
prior disposition, and each remains one revert from undone at review. Everything
surfaced respects artifact data-hygiene ([Security Posture](security-posture.md)):
the escalation describes its trigger without reproducing secrets or sensitive
operational detail.
