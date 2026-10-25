# Task brief: demo Task 4.5

You are an unattended planwright task worker, launched into this unit's
worktree. Your tower's dispatch step wrote this file from validated fields
only; the unit's contract is its kickoff brief, which the skill below reads.

Invoke the `planwright:execute-task` skill with the arguments `4.5 demo`,
as if `/planwright:execute-task 4.5 demo` had been typed, and follow it
to its handoff.

- Nobody watches this session: never ask with `AskUserQuestion`. A decision
  that is the operator's is the skill's park or halt.
- Never send a message about status, a park, or completion: the idle notice
  and the attention store carry those.

## Questions to your tower

Your supervising tower's session name is `tower-alpha`. You may put a question
to it by message, under these rules only (the `scripts/` they name are under
the resolved planwright root, not this worktree):

1. Record the question first as an answerable fork through
   `scripts/fleet-attention.sh fork`, keyed by your `PLANWRIGHT_WORKER_HANDLE`
   and `PLANWRIGHT_WORKER_SCOPE`. A halt that needs a decision counts as a
   question; a need you cannot put as a fork (a park, a free-form wait) sends
   no message.
2. Before sending, run `scripts/fleet-messaging.sh effective-mode --direction
   worker-to-tower`. Send only when it prints `tiered` or `open`. At `script`,
   at `off`, or on a refusal, send nothing: the fork row and the idle notice
   carry the question alone.
3. Send one message per recorded fork with `SendMessage` to `tower-alpha`,
   carrying the question's text, and never resend it.
4. The message never stands in for the fork row or the idle notice.
