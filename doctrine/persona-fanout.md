# Persona Fan-out

How `/inception` runs its discipline-persona table: a few independent seats
read the venture's frame in parallel, one persona-free writer merges them
blind, one persona-free challenge pass tests the merge, and the human reads the
result at a gate in the main conversation. This doc is the procedure;
`scripts/inception-fanout.sh` carries every mechanical step (its header lists
the subcommands and the run directory's files), the card format is
[discipline-cards.md](discipline-cards.md), and the frame's content is
[inception-format.md](inception-format.md) (*The frame*).

Citations: inception REQ-P1.3, REQ-P1.4, REQ-P1.5, REQ-P1.6, REQ-P1.7,
REQ-P1.8, REQ-P1.9, REQ-B1.3, REQ-B1.5 · inception D-2, D-4, D-6, D-7, D-18.

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
shuffled order, keyed by labels (`Input A`, `Input B`), and the seat-to-label
map stays in the orchestrator's run directory, which no persona-free session
is given. Attribution is re-attached only into the human-facing table, after
the amendment. The challenge pass sees the frame and the synthesis, never a
seat's own output.

## Staffing honesty

The staffing table (Phase 3 of the elicitation) marks each touched discipline
`agent-persona` (naming the card), `named-human`, or `unstaffed`. Run
`inception-fanout.sh staff` after every staffing change: it files each
unstaffed discipline, and each persona row whose card does not resolve, as a
coverage-risk assumption. Pass `--no-stake <discipline>` only for a discipline
the operator judges carries no stake for this venture; say so in the turn. A
deliberate zero-seat run (no persona row at all) files one collapsed
"personas waived (zero-seat)" entry instead, and no fan-out runs.

## The run

The orchestrator is the `/inception` session. Make the run directory with your
own `mktemp -d`, outside the venture, and reuse its literal path in every call.

1. **Frame.** `frame` compiles `exports/frame.md` from the bundle. The frame
   is the only specification the seats share (D-18).
2. **Seats.** `triage` recommends a count in the three-to-five band from the
   bundle's open one-way doors and weakly evidenced blocking assumptions;
   without that signal the default is three. Draw the seats from the staffed
   cards, pulling a benched card only when its pull-in triggers match the
   frame. Two seats may share a card at opposite stance poles
   (`<card>:<pole>`), and seats should vary model (`@<model>`) where the rung
   lets them, model-family diversity being the strongest decorrelation lever.
   `roster` fixes the seats and prints the Gate 1 disclosure.
3. **Gate 1, in the main conversation.** Show the frame's problem statement and
   constraints, the seats (card, pole, model), the backend, the session count,
   the cost line, every `unstaffed` discipline, and every `degraded` line
   (each is also a handoff degradation). Ask one structured choice: run the
   fan-out, change the frame, change the staffing, or run zero-seat. Nothing
   spawns before the operator chooses to run. A changed frame or roster is
   regenerated (a new run directory for a new roster) and shown again.
4. **Dispatch the seats** through the backend capability contract (D-7), one
   brief per seat from `brief`, on the rung disclosed at Gate 1:
   - **`subagent`**: one read-only agent per seat, all launched in one message
     so they run in parallel, each with its roster model when `roster` said
     `per-seat-model yes`. Each agent is told to read only its brief file and
     the bundle files the brief's input subscription names. Save each final
     answer as `<seat-id>.md` in the run directory.
   - **`tmux`**: write each `brief --deliver-file` to a brief file and launch
     it with `scripts/offload-dispatch.sh dispatch tmux <brief-file>`; each
     seat writes its artifact to its run file. Wait in-turn, with an explicit
     timeout, until every artifact exists, then close the seat windows.
   - **`in-session`**: run the seats one after another in this session, each
     from its brief alone. This only approximates independence; report it as a
     degradation.
   - **`print`**: write the briefs with `--deliver-file` and hand the operator
     the launch commands; the run resumes when the artifacts exist.

   Relay runs orchestrator-to-seat only. A seat never prompts the human: a seat
   that asks anyway gets one reply, to put the call in its final section.
5. **Check each artifact** with `check-seat`. A failing seat is re-run once with
   the findings appended to its brief; if it fails again, stop the fan-out and
   offer the operator a re-run or a zero-seat finish.
6. **Synthesize.** `anonymize` writes the blind input and the label map.
   Launch one fresh persona-free session from `synthesis-brief` (on the same
   rung; `--deliver-file` where the session hands nothing back), save its answer
   as `synthesis.md`, and run `check-synthesis --run`. A failing synthesis goes
   back to its writer once with the findings.
7. **Challenge once.** A second fresh persona-free session from
   `challenge-brief`; save `challenge.md`.
8. **Amend once.** The synthesis writer (resumed, or a fresh session) answers
   the challenge from `amend-brief`; save `amended.md` and re-check it.
   `amend-brief` refuses a second amendment.
9. **Attribute.** `attribute` writes `table.md`: the amended synthesis with each
   table label followed by its seat.
10. **Gate 2, in the main conversation.** Present `table.md` for a silent read
    first. Then run `gate2` and put each escalated item to the operator as a
    structured forced choice whose options are the human powers it names
    (disregard, override, reverse, halt), never as a disclaimer. A `halt`
    stops here. Then one outcome choice:
    - **proceed**: draft the seats' proposed assumption and decision entries
      for the operator to confirm, then write the confirmed ones; record the run
      (below) and add a sources-register entry for it.
    - **park**: record the run and write nothing to the registers yet.
    - **kill**: discard this fan-out's output; nothing is recorded or filed.
      Killing the venture is the gate's, never this one's.
    - **re-run-seat**: re-run one named seat, then repeat from step 5.
    - **pull-bench**: add a benched card's seat, then repeat from step 2.
11. **Record.** `record` copies the final table, the challenge, the roster, and
    each seat artifact into `fanout/<date>-<n>/` in the venture, never the
    label map, then save the venture as every phase does.

## Reading the table

Convergence marks are a weak, inflation-prone signal: inputs that read one frame
share its errors. Each claim carries its claim type (extractive or
interpretive), a `<k> of <n>` count, and its outliers by name, and is never
presented as a probability. A grounded claim outranks a heavily converged one
(REQ-P1.9). Anything a seat produced enters the assumption register at no
better than the `synthetic` evidence grade, citing the run's sources-register
entry, and a `synthetic` grade never counts toward a desirability `Graduate`
([evidence-quality.md](evidence-quality.md)).

## Degradations

Report each at Gate 1 and again at handoff: a rung below `subagent` (seats not
independent sessions), seats on one model, a seat launch that cannot set a
per-seat model, an unstaffed senior discipline, and a stance pole or bench
pull that was wanted but has no card to run.
