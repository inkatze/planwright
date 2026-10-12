# Card Authoring

How a discipline card gets written: a research-grounded distillation of what a
senior practitioner of the discipline does first, cast in the card format
[discipline-cards.md](discipline-cards.md) defines. A card is only as good as
its research; card quality dominates what a persona seat produces, and an
unresearched card is worse than an honest unstaffed flag (inception D-17). The
recipe is written to be followed cold, by someone holding nothing but this doc,
the format doc, and the sources they gather.

Citations: inception REQ-P1.1, REQ-P1.2, REQ-P1.11 · inception D-3, D-4, D-17.

## Before writing: demand and placement

A new card needs a reason to exist. In core, that is demand evidence: a
discipline that venture runs keep recording as unstaffed (the catalog
telemetry), or a commission backed by a recorded observation. A discipline
with neither is a **parked candidate**, named in the spec's deferred list with
the telemetry gate that would unpark it, and not built. A company- or
team-specific discipline is overlay content: it goes in an adopter or
repo-tracked overlay (*Where cards live* in the format doc), never in core.

## The method

Work the steps in order. Each produces a part of the card, and each names
what to record so the card's `## Sources` section and `Reviewed:` date are
honest.

1. **Gather primary sources.** For the discipline's methods, prefer, in
   order: the method's author in their own book, paper, or site; peer-reviewed
   or official material; practitioner write-ups by people who run the method
   for a living; critiques of it. Re-verify every source at authoring time
   rather than from memory: title, author, venue, year, current edition, and a
   stable link. A claim you could reach only through a secondary summary is
   cited as such. Record each in `## Sources` with its re-verification date.
2. **Distill the first questions.** Ask what a senior practitioner asks first
   when handed a fuzzy idea in this discipline, before any method runs. Keep
   three to seven, each answerable only against the venture's frame, so each
   names the frame or the venture (`this venture`, `the venture's`, or
   `the frame`). When more than
   seven survive, the discipline is two cards or one card and a bench card;
   never silently drop a question. Write these as `## Mandate`.
3. **Order the frameworks into a working sequence.** Pick the few methods
   that answer the mandate, and order them the way a practitioner runs them,
   each consuming what the one before produced. For each, write its misuse
   caveat, from the author's own warning wherever the author gives one. Write
   these as `## Frameworks`.
4. **Name the grounding and the refusals.** List the evidence the seat must
   consult before it speaks: the venture's registers, the sources register,
   named external material. Then write the refuse-without gates: the evidence
   absent which the seat declines and asks, rather than reasoning in a vacuum.
   Grade expectations follow [evidence-quality.md](evidence-quality.md); a seat
   never treats its own or another seat's output as evidence above the
   `synthetic` grade. Write these as `## Grounding` and
   `## Input subscription`.
5. **Draft the artifact template.** The seat's output, fenced, ending with the
   `Decisions I cannot make` section, and a done-when line a reader can check.
6. **Place the tiers.** Choose the default tier, then walk the discipline's
   activities and place each one whose answer differs: the capability frontier
   is jagged inside a discipline, so a single label is never the whole
   boundary. One-way doors are `human-authority` whatever the default. Name
   the out-of-scope line: what this seat must not opine on, usually the
   neighbouring discipline's turf. Write these as `## Capability boundary`.
7. **Type the escalations.** For each of the four trigger classes, say how it
   fires in this discipline and which powers the human holds over it. Write
   these as `## Escalation contract`.
8. **Map the edges.** Write the register rules (what the seat proposes and in
   what form), the anti-patterns the synthesis writer should discount, the
   discipline's blind spots and which other seat covers each, the conflict and
   deference rules on shared turf, and the independence note naming who or
   what can validate this discipline's claims, since the seat cannot.
9. **Set the metadata.** `Rot-rate:` from how fast the sources decay (the
   format doc's *Staleness*); `RAPID:` letters, never `D`; `Bench:` and, for a
   bench card, its pull-in triggers; a stance axis only where two opposed
   readings of the same evidence are both useful.
10. **Run the styling pass.** Read the card for identity, the whole of it
    including the template. Remove every line that says who the seat is,
    claims experience or credentials, borrows prestige, or expresses the seat's
    own confidence; rewrite each as the work it describes. The format doc's
    *Anti-authority styling* is the rule; the linter only catches the common
    phrases.
11. **Lint and register.** Run `scripts/card-lint.sh` on the card until it is
    clean, then add the card's entry to its layer's `discipline-cards` catalog
    and confirm `scripts/resolve-card.sh <card-id>` returns the file. A core
    card resolves against the install root, so in a planwright checkout run
    the check with `PLANWRIGHT_ROOT` pointing at that checkout, or an
    installed plugin answers instead and reports the card as not listed.

## Keeping a card current

Re-verification is the same as step 1, on the schedule `Rot-rate:` sets: walk
`## Sources`, re-check each against its current edition, update what moved,
and advance `Reviewed:`. A source that changed its method changes the card in
the same edit. A card that cannot be re-verified is stale, and the portfolio
view says so.
