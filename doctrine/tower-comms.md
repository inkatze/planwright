# Tower Conversation

How a tower session talks to the operator. Which item is delivered, when, in
what order, and what closes it is the queue script's job; this doc holds only
what no script can enforce: the words. It binds tower sessions (`/orchestrate`
in its single-spec, meta, and fleet forms, and `/tower` once it ships); other
attended skills adopt it only through the bundle's gated deferral.

Citations: tower-comms REQ-C1.3, REQ-C1.8, REQ-D1.1, REQ-D1.2, REQ-D1.3,
REQ-E1.6, REQ-E1.7, REQ-I1.1, REQ-I1.2, REQ-I1.4 · tower-comms D-10, D-13,
D-16.

## The register

Write for a developer who knows planwright's basics. Tower, worker, spec, task,
PR, branch, and worktree need no explanation. Everything below that level (a
store name, a script name, a spec identifier, a doctrine term) is either left
out or explained in plain words the first time it appears.

Name things by what the operator can see: a PR by its number and title, a
branch by its name, a task by its title, a worker by the job it is doing. A
label that only marks a position in a file (a requirement or decision
identifier, a task number) is not said.

The test for a word is taken from the listener's side: if answering "what is
that?" would need the operator to open a file, it is not a word to say to
them. When the operator asks what a name means, the name is the defect. Drop
it rather than explaining around it.

The scorecard counts jargon in delivered text against a word list that ships
beside the queue script for that count. That list is the inventory of words
to avoid; this doc does not restate it.

## The first turn after silence

After a stretch with no operator turn, the first attended turn says where
things stand, in plain words. It does not report what the tower did; that
record stays in the log and is available on request. Compose the picture from
the catch-up list, and show the list itself only when the operator asks for it.

## One item, answerable alone

Write a delivered item so the operator can answer it from that message alone,
with the shortest context that makes it answerable. Deeper context is given
one layer at a time, on request: give one layer, then wait for the reply
before giving the next.

## Questions and work

Answer an operator's question inside the turn. A question the tower can
answer is not an ask. When the answer needs work, capture only that work as a
request.

## Rules with no subject

When a standing decision names no worker, PR, or branch, whether to mention it
beside an open item is the tower's judgment.
