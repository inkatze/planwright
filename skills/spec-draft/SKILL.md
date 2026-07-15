---
name: spec-draft
description: >
  Interactively elicit a four-file spec bundle (requirements.md, design.md,
  tasks.md, test-spec.md) at Status Draft on the spec's own branch, mining
  seed sources (pending notes, the observations log, transcripts) and citing
  them. Runs fold-detection against existing specs on every invocation and
  surfaces an extend recommendation instead of spinning a duplicate bundle.
  Commits the completed bundle (commit_on_draft opt-out); never pushes, never
  flips a spec to Ready.
argument-hint: "<feature-name> [--extend <spec>]"
---

# /spec-draft

The authoring entry point of the planwright pipeline (REQ-B1.1): a Socratic,
interactive elicitation that turns an idea plus its seed material into a
compliant four-file bundle at `specs/<spec>/`, Status Draft, committed on the
spec branch. Drafting ends where comprehension begins: `/spec-kickoff` walks
the Draft to sign-off and flips it Ready. This skill never pushes, never
opens a PR, and never flips a status to Ready — sign-off is a reserved human
control it has no business near.

## Doctrine

Resolve and read the run-start rule docs via the rule-doc
resolution convention (`scripts/resolve-rule-doc.sh <doc-name>` or the
documented `PLANWRIGHT_ROOT`/`CLAUDE_PLUGIN_ROOT` chain): `spec-format` (the
meta-spec the bundle must conform to — its conventions govern every file this
skill writes), `interaction-style` (governs every exchange in the flow),
`research-rigor` (REQ-D1.5 wires its triggers into drafting),
`security-posture` (artifact data-hygiene for everything committed), and
`proportionality`. Three more are read point-of-use, at the step that applies
them: the design phase reads `engineering-decisions` (governs design-phase
recommendations) and `customization-boundary` (the capability-vs-style
scoping call the design phase applies when a candidate feature looks like a
packaged preference — see Design step 3); the altitude gate reads
`autopilot-reflex` (D-11 wires its altitude gate into drafting the same way
research-rigor is wired — the seed-claim and mid-flow trigger classes, the
phase re-anchor, and the trigger-scoped altitude record; the trigger
summaries the earlier steps need are stated inline at Seed gathering and the
phase-end re-anchor, so only the full law defers; this skill cites
`doctrine/autopilot-reflex.md` rather than restating it). Their definitions
govern wherever this skill names a concept. If one of those does not
resolve — at run start or at its point of use — halt with a clear message naming
the missing doc and the chain consulted (REQ-K1.7: a clear message is the
graceful arm; proceeding without doctrine is the opaque failure). Also
resolve `decision-domains` (the design phase walks its catalog) — this one
degrades instead of halting: if absent, the design phase notes the missing
catalog in one line and proceeds (the builder/catalog wiring is a hook
point, not a dependency).

Doctrine manifest (the reading model above in machine-parseable form, per
`doctrine/instruction-hygiene.md`; `run-start` loads before work begins,
`point-of-use` loads at the named step or branch):

Doctrine: run-start spec-format
Doctrine: run-start interaction-style
Doctrine: run-start research-rigor
Doctrine: run-start security-posture
Doctrine: run-start proportionality
Doctrine: point-of-use engineering-decisions (the design phase)
Doctrine: point-of-use customization-boundary (the design-phase capability-vs-style call)
Doctrine: point-of-use autopilot-reflex (the altitude gate, Design step 3)
Doctrine: point-of-use decision-domains (the design-phase catalog walk)

## Pre-flight

1. **Parse arguments.** `$ARGUMENTS` carries the proposed feature name —
   free-form idea text by design (the name is a hint, D-22) — and optionally
   `--extend <spec>` (jump straight to extend mode on an existing bundle).
   The feature name is not used directly: the skill derives the **spec
   identifier** (`<spec>`) from it, and that derived identifier is what
   appears in paths, branch names, and commands. Validate the derived
   identifier (and any identifier a seed or `--extend` proposes) against the
   anchored, full-string pattern `^[a-z0-9][a-z0-9-]*$`, maximum length 64
   (REQ-A1.8) **before** any such use. When the feature name is not already
   a conforming identifier, propose a conforming kebab-case variant and ask;
   nothing non-conforming is ever interpolated. No name given: elicit the
   idea first (seed gathering below) and propose a name from it. When
   `--extend <spec>` is present, additionally
   verify the target: `specs/<spec>/requirements.md` must exist and its
   Status must be non-terminal. A nonexistent target gets a clear message
   listing the specs that do exist; a Retired or Superseded target is
   refused per the extend-mode terminal rule, up front rather than after
   elicitation starts.
2. **Detect the git state.** Not a git repository: degrade per REQ-K1.7 —
   say so up front, elicit and write the bundle in place, and skip every
   branch/worktree/commit step below, surfacing at the end what was skipped
   and why. No remote configured: irrelevant here (this skill never pushes);
   note it only so the human knows `/spec-kickoff`'s push step will degrade.
3. **Read the config.** `commit_on_draft` from `config/defaults.yml`
   overridden by `<repo>/.claude/planwright.local.yml` (local wins). Default
   `true`; an absent, unreadable, or malformed config file falls back to the
   default with a one-line warning surfaced immediately at this step — before
   any fallback-driven action (such as the auto-commit) can fire — and
   repeated in the handoff (REQ-K1.7).
4. **Resolve the working location** (D-44, graceful in every starting state).
   The spec branch is `planwright/<spec>/spec` (the reserved namespace the
   `tasks-pr-sync` hook no-ops on); the spec worktree is
   `<repo>/.claude/worktrees/<spec>-spec` (D-37 placement; the directory name
   disambiguates the literal branch suffix `spec`, which would collide across
   specs, while staying attachable via `claude --worktree <spec>-spec`).
   - **Already in the spec's own worktree:** proceed. Dirty or diverged
     state: surface it and ask before touching anything — never auto-stash,
     auto-commit, or clean.
   - **In the main checkout or an unrelated worktree:** if the spec worktree
     exists, do not work here — print the re-open command
     (`claude --worktree <spec>-spec`) and stop. If the branch exists but the
     worktree was pruned, recreate the worktree from the branch (native
     mechanics below). If neither exists, create them: worktree via Claude
     Code's native mechanism (`claude --worktree` / EnterWorktree — never raw
     `git worktree`, D-37), then `git switch -c planwright/<spec>/spec`
     inside it, branched from the current main view.
   - Worktree/branch resolution happens after the name is final — which for
     a fresh idea may be after seed gathering and fold-detection have run
     (both are read-only against the existing checkout).

## Seed gathering (REQ-B1.2, REQ-B1.4)

Collect the framing inputs before asking the human a single elicitation
question; seeds answer questions the human would otherwise repeat.

1. **The invocation itself** — whatever idea, links, or files came with the
   prompt.
2. **Pending notes** — files under `specs/_pending/`. Read them; ask which
   apply if more than one plausibly does.
3. **The observations accumulator** — the live fragments under
   `specs/_observations/entries/` plus the frozen legacy
   `opportunities.md`'s unconsumed lines, read as **one candidate set** and
   mined as a first-class seed source (D-23; this skill is its canonical
   reader, REQ-H1.6; `mise run obs:log` renders the chronological view). An
   `entries/` fragment already bearing a `Consumed-by:` line is consumed,
   not a candidate — complete its archive move (below) rather than
   re-mining it, and skip-and-warn any grammar-invalid file rather than
   silently dropping it. Read every candidate; select the ones relevant to
   the feature being drafted; present the selection to the human (selector
   with the relevant set pre-marked) so nothing is consumed silently.
4. **Transcripts and documents** the human offers.

An absent `specs/_pending/`, fragment directory, legacy log, or `specs/`
directory entirely (a first-run repo) is not an error: note what was absent
and proceed with the seeds that exist.

Every identifier a seed proposes (a spec name, a path segment) is
re-validated against REQ-A1.8 at consumption, before any interpolation —
accumulator contents are unscreened input. Record every seed actually used:
each becomes a `## Sources` entry in `requirements.md`, and the REQs and
D-IDs it framed cite it (the meta-spec's citation kinds; `drafting-session
decision (<date>)` covers choices made live in the session that mint no
D-ID).

**Pin altitude seed claims (REQ-H1.1).** While gathering seeds, extract every
explicit statement about the deliverable's *nature* — the seed-claim trigger
class `doctrine/autopilot-reflex.md` names ("that's a doctrine gap", "this is
a first-class concern", "we keep doing X manually"). Each is an altitude
assertion the elicitation must reconcile against, not a throwaway phrase, and
it is easy to under-weight in the rush toward mechanism. Record each pinned
claim as a `## Sources` entry in `requirements.md` so the altitude signal is
**bundle-local** — the
REQ-H1.3 kickoff check reads it from the bundle, never from drafting-session
memory. A pinned claim is one of the two altitude trigger classes; when a
trigger fires, the firing rule in Elicitation resolves the altitude before the
design phase.

**Archive-on-consume.** When the bundle is written, consume each mined
entry through the shared helper `scripts/obs-consume.sh` (resolved under
the planwright root) — never by hand-composing paths or annotations. A
fragment is consumed by UID: `scripts/obs-consume.sh --uid <uid> --spec
<spec>` writes the `Consumed-by: specs/<spec> (<date>)` line inside the
fragment and moves it from `entries/` to `archive/` with its filename
preserved (annotate first, move second; idempotent on re-run, and it
completes a crashed half-consume found still in `entries/`). A frozen
legacy line is consumed in place: `scripts/obs-consume.sh --legacy --line
'<exact line>' --spec <spec>` annotates the line where it sits. Surface a
non-zero helper exit — an unknown UID, an ambiguous duplicate-UID match
(named, never silently picked), a refused argument — rather than papering
over it. Unconsumed entries stay byte-for-byte; consumption moves content
verbatim (write-time hygiene screened it when it was recorded, and the
move implies no re-screen — REQ-D1.2). Cite a consumed fragment as
`obs:<uid>` in the bundle's `## Sources` entry (the UID survives the
archive move, so the citation never dangles). The consume commits ride the
spec branch and land on main with the spec PR, keeping them one revert
from undone. The accumulator-taxonomy doctrine is the canonical home of
this drain ritual; this section applies it, not defines it.

## Fold-detection (REQ-B1.3, D-21, D-22)

Runs on **every** invocation, regardless of the feature name — the name is a
hint, not a command. Skipped only when `--extend` already named the target.

1. Scan every existing spec under `specs/` (any non-terminal status: Draft,
   Active, Done). Read each bundle's `requirements.md` Goal and Scope
   sections — bounded input by design; full-bundle reads don't scale and the
   overlap signal lives in goal/scope. A malformed bundle (missing
   `requirements.md`, unparseable header) is skipped with a notice naming
   it; the scan never halts the session over someone else's broken bundle
   (REQ-K1.7 — the validator owns reporting it).
2. Judge semantic overlap between the new idea and each scanned spec: same
   problem domain, same external interface, same decision space.
3. On overlap, check D-21's spin-new triggers: the new idea introduces a new
   external interface; is independently ownable; forces decisions orthogonal
   to the bundle's domain; or would push the bundle past "one feature a
   reader holds in their head".
4. **Overlap and no trigger fires:** surface an extend recommendation —
   a selector naming the overlapping spec, why it overlaps, with **extend as
   the recommended option** and spin-new as the alternative. The human
   decides. Never auto-fold; never silently obey the name over a clear
   overlap.
5. No overlap, or a trigger fires: proceed as a new bundle, noting in one
   line what was scanned and why nothing folded.

### Extend mode

Entered via `--extend <spec>` or the human accepting the recommendation.
Operates on the existing bundle per the meta-spec's stable-ID discipline:

- **Append, never renumber.** New REQs and D-IDs continue the existing ID
  space; dotted task ids insert between existing tasks.
- **Supersede what changes meaning.** A changed requirement or decision mints
  a new ID adjacent to the old, old marked `Superseded-by`; bodies of
  superseded records are never edited (D-20).
- **Grow `test-spec.md`** with entries for every new REQ; **re-sync
  `tasks.md`** (new task blocks in Forward plan, dependency lines updated);
  **append a dated Changelog entry** describing the extension.
- **Reopen cycle (REQ-A3.1):** extending a Done bundle flips its Status
  Done→Draft (all four headers); the scoped kickoff of the delta flips it
  back to Active. Extending an Active bundle leaves it Active — the delta is Draft
  content inside an Active bundle, and `/spec-kickoff`'s delta re-walkthrough
  is the sign-off path; say so in the handoff. Retired and Superseded are
  terminal: refuse, suggesting a new bundle citing the old as a Source.
- Extension work happens on the spec's own branch/worktree, same as a fresh
  draft.

## Elicitation

Six phases, each governed by the interaction-style rules: show the progress
indicator (`[<phase> <n>/6]`), work in small bites, present decisions as
selectors with a recommendation, end each phase with the running summary of
everything decided so far — and, per the phase re-anchor
(`doctrine/autopilot-reflex.md`, REQ-H1.2), that summary **restates the
claimed altitude and flags any drift** between the claim and what the
elicitation is currently producing ("the seed claimed doctrine; the last phase
produced only mechanism tasks"). The restatement is cheap; its absence is how
a session that opened at one altitude silently slides to another. The meta-spec
(`spec-format`) defines every structural convention referenced here; follow it
exactly so the bundle passes the validator the first time.

1. **Goal & scope.** The problem, the one-paragraph goal, in-scope /
   out-of-scope lists. Elicit what the feature must *not* do — out-of-scope
   entries prevent more drift than REQs do.
2. **Requirements.** Thematic REQ groups (`## REQ-<Group> — <theme>`), each
   requirement a single SHALL/MUST bullet with a stable ID and a citation.
   Derive candidate REQs from the seeds and goal, present per group for
   correction; the human supplies judgment, not formatting.
3. **Design.** **Altitude gate first (REQ-H1.1).** Resolve and read
   `autopilot-reflex` now (its point-of-use read). Before designing any
   mechanism, check whether an altitude trigger has fired — a pinned seed
   claim (seed gathering above) or a mid-flow signal surfaced during
   elicitation (a recurring capability-vs-style call, an "is this even core?"
   hesitation, a mechanism acquiring rules that read like doctrine): the two
   trigger classes `doctrine/autopilot-reflex.md` defines. If one has fired,
   resolve the deliverable's altitude **now**, and record the call as an early
   **altitude D-ID** cited from the bundle's goal (the trigger-scoped altitude
   record the doctrine requires — a conversational resolution with no artifact
   can be pencil-whipped, so the D-ID is what the REQ-H1.3 kickoff check
   verifies). Designing first and retrofitting the altitude is how a doctrine
   deliverable ends up specced as a one-repo script. No trigger fired: no
   record is required (per `proportionality`, the ceremony is scoped to the
   specs that exhibited the risk) — proceed. Then resolve and read
   `engineering-decisions` (its point-of-use read; it governs this phase's
   recommendations) and record, for each load-bearing choice, a D-ID with all
   three fields
   (Decision / Alternatives considered / Chosen because). This phase fires
   Research Rigor triggers (new dependency, unfamiliar domain,
   security-touching pattern, version-sensitive API, mature-project
   comparison): research before recommending, cite what was consulted.
   **Capability-vs-style call:** when a choice is whether a preference belongs
   in core or in an adopter/team overlay, resolve, read, and apply
   `customization-boundary` (its point-of-use read) — does
   the general *capability* land in core as an opt-in, default-preserving config
   knob, while the specific *value/style* stays in an overlay? Default tilt is
   overlay when in doubt; a preference graduates to a core knob only with
   drain-loop evidence that it generalizes.
   **Builder hook point:** walk the decision-domains catalog for domains the
   feature touches; flag any the spec touches but does not decide, and
   escalate stake-bearing decisions (authn/z, data modeling, security
   posture, integration surface) as explicit design decisions — never
   auto-default them. Walk the catalog's prose seed (`doctrine/decision-domains.md`,
   the normative full text) **and** any adopter/team/machine-local additions via
   the merged path `scripts/resolve-catalog.sh decision-domains`, so overlay
   domains apply too rather than a single-layer read (REQ-D1.1). When the
   planwright builder skill exists it plugs in here (stack detection, guard
   recommendations); until then the catalog walk is the manual form and a
   missing catalog doc degrades to a one-line notice. Hook point and catalog
   scan, not a dependency: drafting works without the builder.
4. **Tasks.** Decompose into task blocks with the five definition fields
   (Deliverables / Done when / Dependencies / Citations / Estimated effort);
   IDs stable from birth. `Done when:` conditions an agent can evaluate.
   All blocks start in `## Forward plan`; the other five state sections are
   written with `(none yet)` placeholders. Dependency edges are load-bearing
   (orchestration selection reads them): ask about ordering the human knows
   and the text doesn't show — in particular, tasks whose deliverables gate
   other tasks' verification (CI, guards, validators) should carry explicit
   edges from the tasks they protect, or they dispatch too late.
5. **Test-spec.** Every REQ pinned to at least one verification path, tagged
   `[test]` / `[manual]` / `[design-level]` / `[Gherkin]` (mixed:
   `[test + manual]`). Prefer `[test]` where automation is honest; say which
   CI runs it.
6. **Review & validate.** Assemble all four files (shared header block,
   `**Status:** Draft`, `**Last reviewed:** <date>`, `**Format-version:** 1`),
   present the bundle for a final read-through with the cumulative summary.
   Run `scripts/spec-validate.sh specs/<spec>` when present and executable
   (findings are warnings on Draft: surface them, fix structural ones,
   let the human defer judgment ones); validator absent: note it and
   continue — authoring is a graceful-degradation path (REQ-K1.7), and
   `/spec-kickoff` enforces before anything executes.

**Data hygiene throughout (REQ-D1.6):** no secrets, credentials, internal
hostnames, or sensitive operational detail in any committed artifact — spec
files, Sources entries, archived observations. Seeds may contain them;
committed prose neutralizes them.

## Completion

1. **Write the bundle** at `specs/<spec>/` in the spec worktree (plus the
   `_observations` consumption writes — fragment moves into `archive/` and
   any frozen-legacy in-place annotations — when entries were consumed).
2. **Neutralize machine-local references (REQ-D1.1, REQ-D1.2, D-4).** Before
   committing, rewrite every `[[name]]` memory-link token in would-be-committed
   spec prose into plain prose plus a `## Sources` pointer. A `[[name]]` link
   resolves only against the authoring session's private memory store, never
   for a reader of the committed bundle, so state the fact in prose and cite the
   source: a recorded observation carries a fragment UID and is cited as
   `obs:<uid>` (the Observation citation kind — see Archive-on-consume above),
   while any other machine-local reference — including an unconsumed frozen
   legacy line, which has no UID — becomes a `## Sources` entry naming the
   source. When the prose must *mention* the token syntax itself (a spec
   about this rule does), wrap the mention in an inline code span (`` `[[name]]` ``)
   so it reads as documentation, not a live link. This is mechanically
   backstopped: `check:memory-links` (`scripts/check-memory-links.sh`, under
   `mise run check`) flags any bare `[[name]]` token in a committed spec file
   (`requirements.md`, `design.md`, `tasks.md`, `test-spec.md`), so a draft that
   skips this step fails CI rather than shipping an unresolvable reference.
3. **Commit** (D-41) when `commit_on_draft` is true: one commit on
   `planwright/<spec>/spec` containing the four files and the
   `_observations` consumption writes, message `feat(spec): draft specs/<spec> bundle`
   (extend mode: `feat(spec): extend specs/<spec> — <summary>`). New commits
   only — never force-push, amend, squash, or rebase (REQ-J1.4). Opt-out
   set: leave the work uncommitted and say so explicitly.
4. **Hand off.** Report: the bundle path and branch, validator outcome,
   seeds consumed (and archived), fold-detection outcome, and the next step —
   `/spec-kickoff specs/<spec>` for the walkthrough and sign-off. Push, PR,
   and the Active flip all belong to kickoff and the human. This skill stops
   here.
   - As an **optional independent step**, also recommend that the human run
     `/spec-walkthrough specs/<spec>` themselves for an unaided, plain-language
     read of the freshly drafted bundle before sign-off — the unaided
     complement to `/spec-kickoff`'s guided dialogue (REQ-F1.1, REQ-F1.2,
     D-11). Surface it as a suggestion only, never a step this skill performs:
     the human chooses whether to take the independent pass.

## Maintenance

After the run completes (or halts), compare these instructions against the
resolved doctrine docs listed above (REQ-B3.2, D-42) — especially
`spec-format` (file conventions, citation kinds, status lifecycle) and
`interaction-style`. If a concept this skill names has changed meaning,
gained or lost a step, or moved between docs, record a one-line drift
observation through the shared helper (`scripts/obs-record.sh --slug
skill-drift --scope <repo> --text 'skill-drift(spec-draft): <what>'` — the
entry text keeps the `skill-drift(...)` prefix) and commit the fragment as
its own chore commit, per REQ-B3.2 / D-42; surface a non-zero helper exit
rather than silently dropping the observation, and tell the user what
drifted. In repositories without `specs/`, surface the drift to the user
instead of recording it. Do not edit this skill or the doctrine docs to
resolve the drift; the accumulator's canonical reader (`/spec-draft`) owns
folding drift into spec amendments.
