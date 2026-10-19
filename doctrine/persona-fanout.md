# Persona Fan-out

How `/inception` runs its discipline-persona table: a few independent seats
read the venture's frame in parallel, one persona-free writer merges them
blind, one persona-free challenge pass tests the merge, and the human reads the
result at a gate in the main conversation. This doc is the procedure;
`scripts/inception-fanout.sh` carries every mechanical step (its header lists
the subcommands, the run directory's files, and the exit codes), the card
format is [discipline-cards.md](discipline-cards.md), and the frame's content
is [inception-format.md](inception-format.md) (*The frame*).

Citations: inception REQ-P1.3, REQ-P1.4, REQ-P1.5, REQ-P1.6, REQ-P1.7,
REQ-P1.8, REQ-P1.9, REQ-B1.5 · inception D-2, D-3, D-4, D-6, D-7, D-17, D-18.

## The topology

Seats run independently over the same frame, read-only, with no channel
between them on any rung; a single synthesis writer merges them; exactly one
challenge pass follows; the synthesis amends once; there is no debate loop
(D-2). In RAPID terms the seats are I, the synthesis writer R, the challenger a
risk-scoped A, and the human D. The synthesis, challenge, and amendment steps
are persona-free: their prompts carry plain task instructions and no card role
line, because persona framing aids generative coverage and degrades
discriminative judgment.

The synthesis writer works blind. Seat artifacts reach it anonymized and in
shuffled order, keyed by labels (`Input A`, `Input B`); seat ids, card ids,
models, and phrases where a seat names its own discipline or pole are
redacted. The frame it reads withholds the staffing table's card ids. The
seat-to-label map stays in the orchestrator's run directory and is never put
into a prompt, and no prompt names that directory: a session that delivers by
file (below) writes into its own empty drop directory outside the run. Seat,
synthesis, and challenge text reaches a later prompt as a marked data block,
its headings demoted and any fence it leaves open closed, so it cannot pass
for the prompt's own instructions. Attribution is re-attached only
into the human-facing table, after the amendment. The challenge pass sees the
frame and the synthesis, never a seat's own output.

## Staffing honesty

The staffing table (Phase 3 of the elicitation) marks each touched discipline
`agent-persona` (its third cell the card id), `named-human`, or `unstaffed`.
Run `inception-fanout.sh staff` after every staffing change: it files each
unstaffed discipline, and each persona row whose card does not resolve, as a
coverage-risk assumption. Pass `--no-stake <discipline>` only for a discipline
the operator judges carries no stake for this venture; say so in the turn.
With no persona row at all and any discipline unstaffed, the run is
deliberately zero-seat: `staff` files one collapsed "personas waived
(zero-seat)" entry instead, and no fan-out runs. Choosing zero-seat at Gate 1
means restaging the persona rows first, then running `staff` again. A
collapse whose discipline list no longer holds is superseded by its
replacement; a waiver that persona seats now contradict is reported `stale`
for the operator to close.

## The run

The fan-out closes Phase 4, so the frame carries the reframed problem; a
later reframe runs it again. The orchestrator is the `/inception` session.
Make each run directory with your own `mktemp -d`, outside the venture, and
reuse its literal path in every call.

1. **Frame.** `frame` compiles `exports/frame.md` from the bundle. The frame
   is the only specification the seats share (D-18); its success metric and
   kill criteria may still read pending until Phase 5.
2. **Seats.** `triage` recommends a count in the three-to-five band from the
   bundle's open one-way doors and weakly evidenced blocking assumptions;
   without that signal the default is three. Draw the seats from the staffed
   cards, pulling a benched card only when its pull-in triggers match the
   frame. Two seats may share a card at opposite stance poles
   (`<card>:<pole>`), and seats should vary model (`@<model>`) where the
   launch lets them, model-family diversity being the strongest decorrelation
   lever. `roster` fixes the seats, snapshots the frame into the run, and
   prints the Gate 1 disclosure; it refuses a rung this procedure has no
   launch arm for.
3. **Gate 1, in the main conversation.** Show the frame's problem statement
   and constraints, the seats (card, pole, model), the backend, the session
   count, the cost line, every `unstaffed` discipline, every `card-review`
   line, and every `degraded` line (the run keeps them in its `degraded`
   file for the handoff). Ask one structured choice: run the fan-out, change
   the frame, change the staffing, or run zero-seat. Nothing spawns before
   the operator chooses to run. A changed frame or roster takes a new run
   directory and is shown again.
4. **Dispatch the seats** through the backend capability contract (D-7), one
   brief per seat from `brief`, on the rung disclosed at Gate 1:
   - **`subagent`**: one read-only agent per seat, all launched in one message
     so they run in parallel, each with its roster model when `roster` said
     `per-seat-model yes`. Each agent is told to read only its brief file and
     the bundle files the brief's input subscription names. Save each final
     answer as `<seat-id>.md` in the run directory.
   - **`tmux`**: write each `brief --deliver-file` to a brief file and launch
     it with `scripts/offload-dispatch.sh dispatch tmux <brief-file>`; each
     seat writes its artifact into its drop directory under a `.partial` name
     and renames it when done. Wait in-turn, running
     `collect --run <dir> <seat-id>.md` for each seat every 15 seconds
     against an explicit timeout until none exits 4 (pending), then close the
     seat windows. A `stray` line means the session wrote a file it was not
     asked for: tell the operator.
   - **`print`**: the same briefs, through
     `scripts/offload-dispatch.sh dispatch print <brief-file>`; hand the
     operator the printed launch commands, and resume when `collect` finds
     every artifact.
   - **`in-session`**: run the seats one after another in this session, each
     from its brief alone. This only approximates independence, and `roster`
     reports it.

   Relay runs orchestrator-to-seat only. A seat never prompts the human: a seat
   that asks anyway gets one reply, to put the call in its final section.
5. **Check each artifact** with `check-seat`. Each ends with a
   `## Decisions I cannot make` table of six columns, the card template's four
   plus **Trigger** and **Powers**; `anonymize` and `gate2` also hold each
   row's powers to the ones the seat's card gives for that trigger. A failing
   seat is re-run once with the findings appended to its brief; if it fails
   again, stop the fan-out and offer the operator a re-run or a zero-seat
   finish.
6. **Synthesize.** `anonymize` writes the label map and the blind input.
   Launch one fresh persona-free session from `synthesis-brief` (on the same
   rung; `--deliver-file` where the session hands nothing back, then
   `collect`), save its answer as `synthesis.md`, and run `check-synthesis --run`. A failing
   synthesis is re-asked once with `synthesis-brief --retry`, which sets the
   failed answer aside and appends it with its findings; a second failure
   stops the fan-out for the operator.
7. **Challenge once.** A second fresh persona-free session from
   `challenge-brief`; save or `collect` `challenge.md`. `challenge-brief` refuses a second
   challenge.
8. **Amend once.** The synthesis writer (resumed, or a fresh session) answers
   the challenge from `amend-brief`; save or `collect` `amended.md` and re-check it. A
   failing amendment is re-asked once with `amend-brief --retry`; there is no
   second amendment.
9. **Attribute.** `attribute` writes `table.md`: the amended synthesis with each
   table label followed by its seat.
10. **Gate 2, in the main conversation.** Present `table.md` for a silent read
    first. Then run `gate2`. Each `choice` line is an escalated item: put it to
    the operator as a structured forced choice whose options are the human
    powers it names (disregard, override, reverse, halt), never as a
    disclaimer. Each `fork` line is a tension or open question from the table:
    put it as a structured choice too, using the staffed cards' blind spots
    and conflict and deference rules to say whose turf it falls on. A `halt`
    stops here. Then one outcome choice:
    - **proceed**: draft the seats' proposed assumption and decision entries
      for the operator to confirm, then write the confirmed ones; record the run
      (below) and add a sources-register entry for it.
    - **park**: record the run and write nothing to the registers yet.
    - **kill**: discard this fan-out's output; nothing is recorded or filed.
      Killing the venture is the gate's, never this one's.
    - **re-run-seat**: make a new run directory, `roster` the same seats in the
      same order, `carry` every other seat's artifact over from this run, re-run
      the named seat, and repeat from step 5.
    - **pull-bench**: make a new run directory and repeat from step 2 with the
      benched card's seat added.
11. **Record.** `record` copies the final table, the challenge, the roster, the
    frame, the degradations, and each seat artifact into `fanout/<date>-<n>/`
    in the venture, never the label map, and does so once per run; then save
    the venture as every phase does.

An exit the steps above do not act on follows the helper's header: 2 is an
environment problem, relayed and stopping the step; 3 is the validator's
refusal of the bundle; 4 is a delivery still pending; 5 means a write-once run file already exists, so the
step needs a new run directory.

## Reading the table

Convergence marks are a weak, inflation-prone signal: inputs that read one frame
share its errors. Each claim carries its claim type (extractive or
interpretive), a `<k> of <n>` count, and its n − k outliers by name, and is
never presented as a probability. A grounded claim outranks a heavily
converged one (REQ-P1.9). The synthesis brief passes the staffed cards'
anti-patterns, unattributed, for the writer to discount on sight. Anything a
seat produced enters the assumption register at no better than the `synthetic`
evidence grade, citing the run's sources-register entry, and a `synthetic`
grade never counts toward a desirability `Graduate`
([evidence-quality.md](evidence-quality.md)).

## Degradations

`roster` reports, and the handoff repeats from the run's `degraded` file: seats
that run one after another in one session, seats left for the operator to
launch by hand, seats on one model, a seat launch that cannot set a per-seat
model or effort, and seats mixing an inherited model with named ones. Report
also an unstaffed senior discipline, and a stance pole or bench pull that was
wanted but has no card to run.
