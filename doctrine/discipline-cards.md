# Discipline Cards

A discipline card is a task-framing, not an identity. It tells one persona
seat what to ask, which methods to run in which order, what evidence to
consult before speaking, what to hand back, and where its authority stops.
`/inception` compiles a card plus the venture's frame into a seat brief; the
card carries no backstory, no credentials, and no seniority styling, because
identity personas show no objective-accuracy benefit and authority styling
raises uncritical human acceptance (inception D-3). This doc is the card
format's normative home; `scripts/card-lint.sh` is its mechanical shadow, and
the authoring method lives in [card-authoring.md](card-authoring.md).

Citations: inception REQ-P1.1, REQ-P1.2, REQ-P1.5, REQ-P1.9, REQ-P1.10,
REQ-C1.7 · inception D-3, D-4, D-6, D-7, D-17, D-18.

## Where cards live

A card is one markdown file named `<card-id>.md`. The catalog that lists them
is the `discipline-cards` data catalog, merged across planwright's four overlay
layers by `scripts/resolve-catalog.sh` (append/union, supersede-by-id), so a
team or company card is overlay content and never a core edit (REQ-P1.10). The
card file sits beside its layer's catalog:

| Layer | Catalog entry | Card file |
| --- | --- | --- |
| core | `config/discipline-cards.yaml` | `cards/<card-id>.md` under the install root |
| adopter | `<adopter-root>/catalogs/discipline-cards.yaml` | `<adopter-root>/cards/<card-id>.md` |
| repo-tracked | `<repo>/.claude/catalogs/discipline-cards.yaml` | `<repo>/.claude/cards/<card-id>.md` |
| machine-local | `<repo>/.claude/catalogs.local/discipline-cards.yaml` | `<repo>/.claude/cards.local/<card-id>.md` |

The layer that supplies a catalog entry supplies its card: an overlay that
supersedes a core entry by id ships its own card file, and
`scripts/resolve-card.sh` resolves an id to exactly one file, confined under
that layer's root. A layer that lists an id but holds no usable card file
for it (absent, unreadable, or resolving outside the layer root) fails that
lookup in every layer. This deliberately departs from the catalog merge's
by-layer policy, under which an adopter or machine-local fault degrades to the
lower layer: falling back to the lower layer's card would staff the seat with a
card other than the one the merged catalog names. A catalog entry carries `id` (the card id, in the anchored
identifier charset `^[a-z0-9][a-z0-9-]*$`, at most 64 characters) and
`discipline` (the display name the staffing table shows). Everything else
lives in the card, so the two never disagree.

## Format

A card opens with an H1 title, `# <Discipline> — discipline card`, and a header
block of bolded key lines. The title is the card's name and `## Role` its
description; the card carries no separate description field. The keys:

| Key | Value | Required |
| --- | --- | --- |
| `Card-format:` | the format major, `1` | yes |
| `Card-id:` | the card id; equals the file name's stem and the catalog id | yes |
| `Reviewed:` | `<YYYY-MM-DD>`, the date the card's sources were last re-verified | yes |
| `Rot-rate:` | `slow`, `medium`, or `fast` (see *Staleness*) | yes |
| `Default-tier:` | `agent-senior`, `structure-only`, or `human-authority` | yes |
| `RAPID:` | the seat's letters from `R`, `A`, `P`, `I`, comma-separated | yes |
| `Bench:` | `no` for a default-staffable seat, `yes` for an on-call one | yes |
| `Stance-axis:` | `none`, or `<pole>-<pole>` (for example `optimist-skeptic`) | no |
| `Model-override:` | `none`, or a model or `model/effort` token the backend may honour | no |

`D` never appears in `RAPID:`: the human always holds the decision
(REQ-P1.10). The stance axis is orthogonal to the discipline: two seats running
the same card at opposite poles decorrelate without inventing a second
identity. A model override is a request, honoured only where the backend
advertises per-seat model choice (inception D-7).

The key set is closed the way the section set below is: a key outside the
table, or a key given twice, is a lint finding, and a second `Card-format:`
line refuses the card. Only blank lines separate the header block from
`## Role`.

The body is a closed set of H2 sections, written in this order:

1. **`## Role`.** One operational sentence, ending in a period: what the
   seat does for this venture, phrased as work, never as who the seat is.
2. **`## Mandate`.** Three to seven numbered first questions, each ending in
   `?`. No silent pruning: a card that needs an eighth question splits or
   benches, it does not drop one. Every question is **frame-anchored**: it
   names the frame or the venture explicitly (`this venture`, `the venture's`,
   or `the frame`), so it can only be answered against this venture's frame
   and never generically. "Who is the target customer?" is generic; "Which
   segment named in the frame feels the problem sharply enough to change
   behavior?" is not.
3. **`## Frameworks`.** A numbered list, the order being the working sequence
   the seat runs them in. Each item names the framework and its primary
   source and carries a `Misuse:` caveat: how practitioners commonly misapply
   it, from the author's own warning where one exists.
4. **`## Grounding`.** Bullets naming the concrete knowledge-sources the seat
   must consult (bundle registers, the sources register, named external
   material) before it may claim anything, plus at least one
   `**Refuse without:**` bullet: the evidence absent which the seat declines
   the question and says what would let it answer.
5. **`## Input subscription`.** What the seat reads beyond the frame: named
   bundle files or register slices. A seat consumes the frame plus this
   subscription and nothing else (inception D-18).
6. **`## Artifact template`.** A fenced markdown template of the seat's
   output, whose final section is `Decisions I cannot make` (decision, tier and
   reason, owning role, evidence needed; REQ-P1.5), followed outside the fence
   by a `**Done when:**` line stating when the artifact is complete.
7. **`## Capability boundary`.** Three bullets: `**Per-activity exceptions:**`
   with one sub-bullet per activity, each `<tier>: <activity>`;
   `**One-way doors:**` stating `human-authority` (one-way-door decisions are
   always the human's regardless of tier, REQ-P1.2) and naming this
   discipline's one-way doors; `**Out of scope:**`, the negative line naming
   what this seat must not opine on.
8. **`## Escalation contract`.** One bullet per trigger class in the taxonomy
   below, each `**<trigger>** (powers: <power>[, <power>]): <when it fires in
   this discipline>`.
9. **`## Register rules`.** What the seat may propose into the venture's
   registers and in what form. Seats are read-only: they propose assumption
   and decision entries in their artifact; the orchestrator and the human
   write the registers.
10. **`## Anti-patterns`.** Failure shapes of this discipline's output the
    synthesis writer should discount on sight.
11. **`## Blind spots`.** What this discipline characteristically misses, so
    the synthesis knows which other seat covers it.
12. **`## Conflict and deference`.** Whose view prevails on whose turf when
    this seat and another disagree.
13. **`## Independence`.** The own-discipline independence note: this seat
    cannot validate its own discipline's claims; name who or what can.
14. **`## Pull-in triggers`.** Required when `Bench: yes`, and only then: the
    frame conditions that pull the benched seat into a run.
15. **`## Sources`.** The primary sources the card was distilled from, each
    with the date it was re-verified, so staleness review has a list to walk.

A section outside this set is a lint finding: identity content arrives most
often as an extra section (`## Backstory`, `## About`), and a closed set is
what keeps it out. For the same reason the title is the card's only H1 and
every section heading is an ATX H2 (`## <name>`): a later H1 or a setext heading
is a finding too. The setext check is the plain one: a `---` or `===` line
directly under any non-blank line that is not a list item, table row, heading,
or quote reads as an underline, so a thematic break after an indented
continuation line is flagged; put a blank line before it. An optional key or section joins its set in the same change
as the linter that accepts it, within the current major (see *Versioning*).

## Capability tiers

The three tiers (inception D-4) classify what the seat's output may do, per
activity rather than per discipline, because the capability frontier is
jagged within a discipline:

- **`agent-senior`** — the seat's output may stand as a recommendation the
  human can accept without redoing the work.
- **`structure-only`** — the seat frames options, evidence, and tradeoffs in
  hypothesis grammar; it does not recommend a pick.
- **`human-authority`** — the seat prepares a briefing and lists the call
  under `Decisions I cannot make`; only a named human decides.

The card's `Default-tier:` applies to every activity its exceptions do not
name. One-way doors sit at `human-authority` whatever the default.

## Escalation trigger taxonomy

Escalation triggers are typed, never prose (REQ-P1.5). Every card declares all
four classes, saying how each fires in its discipline; a class that rarely
fires still gets its line, so the absence of an escalation is never an
omission.

| Trigger | Fires when |
| --- | --- |
| `irreversibility` | The call is a one-way door, or its consequences are costly to undo. |
| `missing-domain-authority` | The call needs a credential, licence, or mandate no agent holds. |
| `confidence-floor` | The evidence under the call sits below the grade the call needs ([evidence-quality.md](evidence-quality.md)). |
| `contract-policy-change` | The call would change a commitment to someone outside the venture team: a price, a term, a published policy. |

Each trigger names the receiving human's powers over the escalated item, from
four:

| Power | The human may |
| --- | --- |
| `disregard` | set the seat's output aside without acting on it |
| `override` | replace the seat's recommendation with their own call |
| `reverse` | undo a consequence already applied on the seat's output |
| `halt` | stop the run |

At Gate 2 every escalated item reaches the human as a structured forced choice
naming those powers, never as a disclaimer (inception D-6).

## Anti-authority styling

Cards and seat outputs carry no identity. A card never says who the seat is
("You are a…", "as a senior…"), never claims experience or credentials ("years
of experience", "PhD", "award-winning"), and never borrows prestige
("world-class", "renowned", "seasoned", "veteran"). Confidence is expressed
only as convergence across seats or as cited evidence, never as the seat's
self-assessment (REQ-P1.9). The linter flags the identity phrases it can
recognize; the authoring recipe's styling pass covers the rest.

## Staleness

`Reviewed:` dates the last re-verification of the card's primary sources;
`Rot-rate:` says how fast its knowledge decays:

- **`fast`** — law, regulation, platform behavior, model capabilities, or
  vendor claims; re-verify before each venture that relies on the card.
- **`medium`** — market and tooling practice; re-verify yearly.
- **`slow`** — durable method whose primary sources change rarely; re-verify
  when a source publishes a new edition.

The portfolio view surfaces cards past their rate as catalog-health notes
(inception D-17); a stale card is worse than an honest unstaffed flag.

## Versioning

`Card-format:` is gated the way the inception bundle's `Format-version:` is
(inception REQ-C1.7): a reader that does not support the declared major fails
closed rather than guessing, and evolution within a major is additive: new
optional keys and sections may join, while renaming, repurposing, or making
required anything a shipped card lacks takes a new major. The linter refuses
an unsupported or missing `Card-format:` before checking anything else.
