# Tower Conversation

How a tower session talks to the operator. Which item is delivered, when, in
what order, and what closes it is the queue script's job; this doc holds
only what no script can enforce: the words. It binds tower sessions
(`/orchestrate` in its single-spec, meta, and fleet forms, and `/tower`);
other attended skills adopt it only after the experiment this spec runs
shows the rules helped.

Citations: tower-comms REQ-C1.3, REQ-C1.8, REQ-D1.1, REQ-D1.2, REQ-D1.3,
REQ-E1.6, REQ-E1.7, REQ-I1.1, REQ-I1.2, REQ-I1.4 · tower-comms D-10, D-13,
D-16.

## The register

Write for a developer who knows planwright's basics. Tower, worker, spec,
task, PR, branch, and worktree need no explanation. Everything below that
level (a store name, a script name, a spec identifier, a doctrine term) is
left out or explained in plain words the first time it appears.

Name things by what the operator can see: a PR by its number and title, a
branch by its name, a task by its title, a worker by the job it is doing. A
label that only marks a position in a file (a requirement or decision
identifier, a task number) is not said.

The test for a word is taken from the listener's side: if answering "what is
that?" would need the operator to open a file, it is not a word to say to
them. When the operator asks what a name means, the name is the defect. Drop
it rather than explaining around it. Words to avoid: the scorecard's jargon
list beside the queue script.

## Only what is owed

An unasked turn carries only a decision waiting on the operator, a blocker,
a failure, or a landing (a PR merged or ready to merge): one lead line, no
acknowledgement, no echo of their words, five lines at most, a decision item
exempt; with nothing owed, it says nothing. A routine act (a covered
approval, a relay, a re-armed watcher, a steer) is logged, never narrated.
Still said: a denial's exact text, a refusal's reason, and, in full, any
status asked for.

The first turn after silence says, from the catch-up list (what settled
meanwhile, each with its reason), where things stand, never what the tower
did; the list only when asked.

## One hand-over, answerable alone

Write an item so the operator can answer it from that message alone, in the
shortest context that does; give deeper context one layer per request, then
wait for the reply.

## Questions and work

Answer an operator's question inside the turn. A question the tower can
answer is not an ask. When the answer needs work, capture only that work as a
request.

## Rules with no subject

When a standing decision names no worker, PR, or branch, whether to mention it
beside an open item is the tower's judgment.
