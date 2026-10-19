# Comment Hygiene

A source comment is read by every agent and reviewer who opens the file, on
every open, whether or not it still matches the code beside it. This doc is
the authoring law for that surface: what a comment is for, where provenance
lives instead, how existing comment text is dispositioned, and the
comment-block budget a guard enforces. Instruction files the harness injects
are a different surface with their own law, in
[instruction-hygiene.md](instruction-hygiene.md).

This doc is the normative home of the comment-block budget guard,
`scripts/check-comment-budget.sh`, whose header cites it. No skill loads it:
it sits in no skill's doctrine manifest, because the reviewing skills reach
the defect class through the Documentation lens in
[discovery-rigor.md](discovery-rigor.md), and the guard enforces the budget
mechanically.

Citations: prose-disposition REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.4,
REQ-E1.5 · prose-disposition D-7, D-8, D-9, D-14.

## What a comment is for

A comment earns its place only when the code cannot carry the information.
Four reasons admit one:

- **A non-obvious why.** The reason this code is shaped the way it is: a
  workaround, an ordering constraint, a rejected alternative a reader would
  otherwise reach for.
- **A constraint invisible at that spot.** Something true elsewhere that this
  line depends on, such as a caller's guarantee or a platform quirk. It is a
  why whose cause lives out of view.
- **A contract a caller depends on.** The file's own usage, flags, inputs,
  outputs, and exit codes.
- **A warning against a plausible wrong edit.** The change a careful reader
  would make that breaks something, named beside the code it would break.

Three things never earn one:

- **Restatement.** Saying what the code already says. A reader who can read
  the line gains nothing, and the comment drifts the first time the line
  changes without it.
- **Narration.** Describing the file's structure ("first we parse, then we
  validate"). The structure is visible; narration is restatement at a larger
  scale.
- **Provenance.** Spec, requirement, decision, and task identifiers, PR
  links, and review history. They record how the code came to be, not what
  a reader needs to change it safely, and they belong in the commit message
  and the spec files (below).

Prefer many small comments, each beside the code it explains, over one large
block at the top of the file. A why separated from its code is the drift this
rule exists to stop.

## Where the link lives instead

Removing provenance from source does not remove the link between a script
and the spec that owns it. The link lives in two places:

- **The commit's task trailer.** Every commit an execution skill authors
  carries `Planwright-Task:`, whose grammar
  [spec-format.md](spec-format.md) defines.
- **The owning bundle's task deliverables.** A bundle names the files it
  delivers in its `tasks.md`, and its `design.md` names the scripts its
  decisions shape.

**The link test.** A script is linked when its basename appears in any
bundle's `tasks.md` or `design.md`, or when any commit touching it carries a
`Planwright-Task:` trailer. Run the test fresh each time it is needed (per
script family during a cleanup, over the whole surface at its closeout); the
unlinked set is recomputed, never carried as a list.

**The deliverables-gap rule.** A script reachable through neither half is a
deliverables gap in its owning bundle. Close it there, as an expression-only
amendment naming the script in the bundle's deliverables, never by adding a
citation to the script. The owning bundle is the one the script's first
`Planwright-Task:` trailer names; absent any trailer, it is the bundle whose
decisions the script implements, chosen and stated with its reason in the PR
that closes the gap.

## The disposition taxonomy

Existing comment text is dispositioned by why it survives a restatement
pass. Each of the five reasons implies one destination:

| Reason it survives | Destination |
| --- | --- |
| **The why of this code** | Stays, moved beside the code it explains. |
| **An own-surface contract** | Stays as the file's bounded usage section. |
| **A cross-file protocol** | Moves to the doctrine doc or design page that owns it, with a one-line pointer left behind. |
| **Restatement or history** | Deleted. |
| **A warning against a wrong edit** | Stays beside the code it guards. |

The taxonomy maps onto the admitted reasons above. The why and the warning
are admitted reasons, and a constraint invisible at that spot is a why. An
own-surface contract is the admitted caller-contract reason. A cross-file
protocol (a store's precedence order, a last-write-wins rule, a fence's
semantics) is not admitted in a comment beyond its one-line pointer, because
its normative home is wherever every file that obeys it can cite. Restatement
and history are the prohibitions; history is provenance under another name.

Where the protocol's normative home already is a spec bundle, the pointer
names the bundle; a bundle is not the default destination, since each edit
to a signed-off bundle's contract is an amendment.

## The comment-block budget

**The unit** is the largest contiguous comment block in a file. A comment
line is optional leading whitespace followed by `#`, the shebang excluded; a
code line is a non-blank line that is not a comment line; a blank line or a
code line ends the block. Measuring the largest block, not total volume or a
comment-to-code ratio, keeps many small comments beside their code from
counting against a file: the block is what costs a reader attention before
the first line of code.

**Thresholds** are in lines and boundary-inclusive: a block whose length
equals a threshold trips it. Two knobs set them, `comment_block_warn` and
`comment_block_error`, core configuration in `config/defaults.yml` tunable
through the overlay chain like any other knob, and documented in the options
reference. A warning leaves the guard's exit status zero; an unsuppressed
error fails it. A missing or non-numeric knob aborts the guard rather than
falling back.

**Two suppression forms** exist, both in `config/comment-budget-exemptions.txt`
and both requiring a recorded reason; an entry without one, or a malformed
entry, is an error.

- **`exempt`** is permanent, for an own-surface section the taxonomy offers
  no split and no other home, or for a file where the heredoc limit below
  misfires.
- **`pending-cleanup`** is transitional: it names the cleanup task whose
  family owns the file and is removed by that task's PR at the latest. Once
  the cleanup closes out, every remaining `pending-cleanup` entry is an
  error, whatever its file now measures.

Before closeout, an entry of either form whose file no longer trips any
threshold draws a named cleanup warning, never an error. The guard's usage text holds the
exact entry grammar and the surface it measures.

**The known limit.** The guard reads lines, not a parse tree, so a heredoc
body line beginning with `#` counts as a comment line. The limit is named
rather than hidden: a file it misfires on takes an `exempt` entry saying so.

**The guard keeps its own budget.** The guard's largest comment block stays
under the warn threshold it enforces. Its usage text, printed from code, is
not a comment block; the argument for the rule lives here, not in the
guard's header.
