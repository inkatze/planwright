---
name: inception
description: >-
  Orient a fuzzy, product-level idea that has no home repo yet: create a
  private or local-only venture repository under ventures_root, then run a
  phased Socratic elicitation that writes the inception bundle (brief,
  discipline and stakeholder map, assumption register, decision backlog,
  validation plan) and resumes where it left off. Upstream of /spec-draft;
  never invokes a downstream skill, never pushes off-machine without the
  operator's choice.
argument-hint: "[<idea or seed path> | <venture-id>]"
---

# /inception

The pipeline stage upstream of `/spec-draft` (inception D-20): it takes an idea
that arrives before any repository exists, often several latent specs and
several disciplines wide, and gives it a durable, validated orientation, the
**inception bundle**, inside a venture repository this skill creates and wraps.
It never writes a spec, never invents the pitch, never decides a call only a
human may make (price commitments, legal or tax readings, org decisions about
people, one-way doors), and never auto-invokes `/spec-draft`, `/spec-kickoff`,
or `/orchestrate`: graduation, like sign-off and merge, is a human act.

## Doctrine

Resolve every rule doc through `scripts/resolve-rule-doc.sh <doc-name>` under
the resolved planwright root (`PLANWRIGHT_ROOT` → `CLAUDE_PLUGIN_ROOT` →
`<claude-dir>/planwright`); their definitions govern wherever this skill
names a concept. `inception-format` is the normative bundle format every write
below conforms to; `interaction-style` governs every attended turn. At their
named steps: seed intake reads `security-posture` (artifact data-hygiene and
the echo rule for seed text), the discipline walk reads `decision-domains`
(the catalog it walks), the core phase reads `evidence-quality` (the
falsifiable skeleton, thresholds, and the evidence ladder), and every skipped
prompt applies `proportionality`. A doc that does not resolve halts the run
naming the doc and the chain consulted; `decision-domains` degrades instead,
noted in one line, the walk proceeding on the disciplines the seed names.

Doctrine manifest (machine-parseable, per `doctrine/instruction-hygiene.md`;
`run-start` loads before work begins, `point-of-use` at the named step):

Doctrine: run-start inception-format
Doctrine: run-start interaction-style
Doctrine: point-of-use security-posture (Phase 1, seed intake)
Doctrine: point-of-use decision-domains (Phase 3, the discipline walk)
Doctrine: point-of-use evidence-quality (Phase 5, the minimum core)
Doctrine: point-of-use proportionality (every skipped prompt)

**The helper.** Everything mechanical runs through
`scripts/inception-venture.sh`, called by its resolved literal absolute path,
one plain command per call (`doctrine/plugin-script-invocation.md`). Output a
caller parses is `key<TAB>value` lines; a `degraded` line names a missing
capability in plain words. Its header lists the exit codes: an exit this skill
does not name below is relayed in plain words and stops that step. Never
compose venture paths, git commands, or remote creation by hand where a
subcommand exists.

## Modes (inception D-19)

One skill, dispatched on the argument plus what is on disk:

- **New idea**: free text, a pitch, or a seed path naming no existing
  venture. Pre-flight, then the elicitation from Phase 1.
- **Resume**: a venture identifier or a venture directory holding a bundle.
  Pre-flight's resume arm, then the elicitation from the recorded position.
- **No argument, status, gate, export or publish**: not in this release.
  Say so in one line, name what is available (a new idea, or a venture to
  resume), and stop. Never improvise a gate record, a registry, or an export
  the later layers own.

## Pre-flight

Every degradation found here is emitted at the operator in plain words before
the first question, and repeated in the handoff (REQ-H1.5).

1. **Detect the environment.** Run `inception-venture.sh detect`. It names
   whether git works, whether the session is ephemeral (a cloud session, or
   the operator's `PLANWRIGHT_INCEPTION_EPHEMERAL` override), whether the
   private-remote home is available, and what the local arm amounts to:
   `durable` (a git repository), `plain` (a folder with no history), or
   `session-only` (lost when the session ends). The ladder (REQ-H1.1) never
   loses the bundle: it degrades capability and says which.
2. **Resolve the ventures root.** `inception-venture.sh root` reads
   `ventures_root` through the config layers (default `~/ventures`). A warning
   it prints is a degradation; any non-zero exit halts, naming the option
   (exit 4 is a malformed team-shared value).
3. **Overlap scan.** The venture registry has not shipped, so the
   cross-venture overlap scan is skipped: say so in one line as a degradation
   and proceed (REQ-H1.6). Never block creation on it.

**New-idea arm.**

1. **Name the venture.** Read the idea and seeds enough to propose a short
   title, then run `inception-venture.sh id "<title>"`. `ok` means the name
   is already an identifier; `propose` offers the kebab-case variant for the
   operator to confirm or replace; exit 2 means nothing usable could be
   derived, so ask for a name. Every identifier the operator types, and
   every one a seed or an extend target proposes, passes
   `inception-venture.sh check-id` before any use (REQ-A1.8).
2. **Ask once where the venture lives** (REQ-A1.4). One self-contained
   selector, asked exactly once per venture and never re-asked:
   - **Private remote repository**: offered only when `detect` says
     `remote available`; the option names the repository (`<id>`, private)
     and says that saves are shared to it once the minimum core is recorded.
   - **Local-only repository**: nothing leaves this machine. On an
     ephemeral environment the option is labelled session-only and says the
     work is lost when the session ends (REQ-A1.5); with no git it is a plain
     folder without history.
   - **No durable home for now**: the session home, in a scratch directory
     (your own `mktemp -d`, passed as `--root`), reported and warned as
     session-only.

   No option is pre-selected. Choosing the private remote is the operator's
   explicit confirmation for creating that repository and for saves reaching
   it (REQ-G1.9); nothing goes off-machine on any other arm.
3. **Ask how saving should look** (REQ-H1.2), once, unless the operator has
   already shown which they want: **handled for you** (plain-language
   "saved" reports, no git vocabulary in any turn) or **standard git**
   (expert mode: the save subcommand's `--expert` output, and the operator
   may use git directly). Both work on the same repository.
4. **Create.** `inception-venture.sh create --home <local|remote|session> --root
   <root> <id>`. Exit 5 means a directory already holds that name: if it
   holds a bundle, offer to resume it; otherwise offer another name. Never
   overwrite, never adopt silently. Exit 6 means the chosen home is not
   available after all: re-present the home question with that arm marked
   unavailable (this is the same one question, not a second); exit 7 means
   the private repository could not be created, so the same applies. The output
   names the rung (`git`, `plain`, `session`); creation scaffolds the hygiene
   guards scaled to it (REQ-A1.9): a `.gitignore`, the pre-commit secret
   screen, bundle validation and export regeneration, and on the remote rung
   the CI guard.
5. **Write the skeleton and save it.** `inception-venture.sh bundle-init
   --title "<title>" <venture-dir>`, then `inception-venture.sh save
   <venture-dir> "Start the <title> venture"` (add `--push` on the remote
   home; `--expert` in expert mode). Unfilled content carries the
   `_Pending: not yet elicited._` marker until its phase replaces it. The
   marker and the `Elicitation: <phase> phase complete.` Changelog lines are
   this skill's own convention, not part of `inception-format`: the
   validator does not read them, so a leftover marker is caught by the
   handoff's `pending` count, never by validation.
   Every save reads its exit the same way: 1 means the venture's guard
   stopped it (a credential, say), so relay why and resolve it with the
   operator before going on; 2 names an environment gap such as no git name
   and email; 7, or a refusal saying `not shared`, means saved here but not
   shared, said plainly.

**Resume arm** (REQ-B1.7).

1. **Gate the version, find the position.** An identifier argument passes
   `check-id`, then names `<root>/<id>` under the resolved ventures root.
   `inception-venture.sh resume-point <venture-dir>`. Exit 2 is an
   environment problem, an incomplete bundle (the missing file named) among
   them: relay the message and stop. Exit 3 is the validator's fail-closed
   refusal (REQ-C1.7): relay its plain-language message and stop, never
   parsing around it; only for an unsupported format-version say this
   planwright cannot read that bundle safely, since an unclosed code fence
   or an unparseable header is the operator's to repair. Otherwise `next`
   is the first phase, in order, with no completion line, and `done` the one
   before it.
2. **Confirm settled ground, one line per completed phase**, from the
   bundle itself, never a replay; then continue at `next`. When `next` is
   `complete`, the operator is re-entering a finished elicitation: offer to
   update a register (an assumption's status or evidence, a decision, a plan
   task) and continue with that phase's procedure; the gate itself is not in
   this release.

## The elicitation

Seven phases, each one or more small exchanges. Every turn opens with the
progress indicator (`[Inception 3/7 — disciplines]`, plus the step within the
phase when it runs long) and follows the turn projection: decisions and
questions first, at most one decision cluster per turn. Mine the seeds before
asking anything they already answer (REQ-B1.2), and carry the clerical weight:
draft candidate wording, IDs, and table rows for the operator to judge, never
to type. Everything elicited is written to the bundle in the operator's terms,
in the format `inception-format` defines.

**Closing every phase.** Replace that phase's pending markers, run the
validator over the bundle (`scripts/inception-validate.sh <venture-dir>`;
findings in later phases' sections are expected until the end), record the
phase with `inception-venture.sh mark-phase <venture-dir> <phase>`, save with
a plain one-line message, and give the running summary: decisions taken this
phase with one-line rationale, what remains open, and any open captures. A
changed earlier answer reopens the phases that depended on it, never leaving
a stale answer standing.

**Proportionality** (REQ-B1.5). Only the minimum core is mandatory. A prompt
area that does not apply is skipped with an explicit one-line reason, written
as `_Skipped: <reason>._` in the bundle and said in the turn, never skipped
silently. A small venture may stay small: zero persona seats is a valid run.

### Phase 1 — `seed`: seed intake

Take seed material in any form: pitch documents, transcripts, ticket exports,
freeform notes. Read each once and extract what it answers. For each source,
classify its sensitivity against the venture repository's visibility
(REQ-B1.6): judge conservatively, state the judgment, and ask the operator
once per source whether it may be stored verbatim. Confirmed: store it under
the venture repo and cite its location. Otherwise neutralize it (summarize
without names, identifiers, or confidential figures) and record the source as
`held out: <reason>`. Every source becomes a sources-register entry in
`brief.md`. Anything flowing back into planwright's own artifacts, such as an
observation, is always neutralized, whatever the repository's visibility.

### Phase 2 — `opportunity`: the opportunity

The four `## Opportunity` fields: the framing with its evidence, who hurts as
a job in a circumstance, no-gos with a rough sketch, and the actor → behavior
change → goal chain. Then the prompt sections, each answered or skipped with
a reason: appetite, existing alternatives (the landscape), business viability
(market, pricing, channels), and strategy fit (adjacent initiatives,
inherited constraints).

### Phase 3 — `disciplines`: the discipline walk

Walk the decision-domains catalog (`scripts/resolve-catalog.sh
decision-domains`, which unions the overlays), and for each domain the venture
touches, record a discipline-map row naming what it touches. Every decision
the venture touches but has not taken becomes an open `DEC-<n>` entry,
door-classified, cited from that row (REQ-B1.3). Present the walk in small
clusters; a domain the venture does not touch is passed with one line.

Then the staffing table: each touched discipline is `named-human` (a person
the operator names) or `unstaffed`. Persona seats are not in this release, so
this run is zero-seat: file the single coverage-risk assumption the format
defines for a zero-seat run, counting the unstaffed disciplines. Then the
stakeholder map: one row per decision area, exactly one person who decides,
plus who is aligned and informed.

### Phase 4 — `reframe`: the reframing checkpoint

Between the evidence and the brief's final form (REQ-B1.4), restate the
problem in one or two sentences as the bundle now holds it, then offer
reframings the evidence supports (a different who-hurts, a narrower or wider
job, a different chain), at equal weight beside keeping the framing as it
stands. A chosen reframe rewrites the affected opportunity fields and reopens
whatever depended on them.

### Phase 5 — `core`: the minimum core

The gate-enforced floor (REQ-C1.8), each item drafted by the skill for the
operator to judge:

- **The success metric**, named and observable.
- **Kill criteria**: the gate decider (a person who decides in the
  stakeholder map) and at least one state-plus-date pair.
- **Blocking assumptions**: every belief the venture cannot responsibly
  graduate without, as `A-<n>` entries in the falsifiable skeleton
  (believe / verify / measure / right if), with a risk-if-wrong, one of the
  four risk tags, and `Blocking: yes`. Thresholds are fixed before any test
  runs, as fail conditions; evidence carries a grade from the ladder, or
  `none` while open. Persona or other simulated output is never more than the
  `synthetic` grade.
- **Open forks**: every load-bearing decision not yet taken is an open
  `DEC-<n>`, one-way doors marked, so a human makes them.

### Phase 6 — `registers`: the validation plan

One `T-<n>` task per blocking assumption or fork worth testing: its kind
(spike, research, analysis, demand-signal, alignment), what it tests, an
evaluable done-when, and a pre-committed time or cost cap. Order them as the
format derives (blocking first, least evidence first, the limiting
constraint breaking ties). Demand-signal and alignment tasks are prepared for
a human to carry out; the agent never contacts external people. Link each
assumption's `Tasks:` field to the tasks testing it.

### Phase 7 — `finalize`

Bump `Last reviewed:` on every file edited, run the validator, and resolve
each finding with the operator or record why it stands. The venture's status
stays `Exploring`. Save (on the remote home with `--push`).

## Handoff

Run `inception-venture.sh handoff <venture-dir>` and emit at the operator, in
plain words: where the venture lives and on which home and rung, whether the
bundle is clean (`pending` means markers remain; `findings` means the
validator still reports some; `incomplete` means a file is missing;
`refused` means the validator would not read it; `unchecked` means the
check could not run here), where the elicitation stands, and every
`degraded` line again. Then the human's next moves, as information rather
than a verdict: run the validation tasks, resume with
`/inception <venture-id>`, or, once a track is ready, take it to
`/spec-draft` themselves. Never invoke a downstream skill.

## Invariants

- Never invoke `/spec-draft`, `/spec-kickoff`, or `/orchestrate`, and never
  merge (REQ-J1.6).
- Never push, create a remote repository, or publish anything off-machine
  without the operator's explicit choice of the private-remote home or a
  later confirmed move to one (`inception-venture.sh add-remote`, which
  keeps the repository and its history, REQ-H1.3).
- Never overwrite an existing directory or bundle file; never use an
  identifier that has not passed `check-id`.
- Never read or write a bundle whose format-version the validator refuses.
- Never decide a human-authority call; record it as an open decision with its
  one-way door marked.
- Never store seed material verbatim without the operator's per-source
  confirmation, and never let it reach planwright's own artifacts
  un-neutralized.
- Every degradation is reported at pre-flight and repeated at handoff.
