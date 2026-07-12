# Observation Recording — Requirements

**Status:** Done
**Last reviewed:** 2026-07-08
**Format-version:** 1

## Goal

Replace the shared-file observations log with a conflict-free, fragment-based
recording substrate modeled on reno (OpenStack): every recording skill drops a
per-entry fragment file with a stable filename UID under
`specs/_observations/entries/`; consumption and archival become per-file moves
keyed on that UID; the human-readable chronological view becomes a derived
render produced on demand, never committed. This preserves the class-3 accumulator
contract (durable home, canonical reader `/spec-draft`, drain surfacing,
archive-on-consume) under full fleet concurrency on a PR-only, squash-merge,
never-auto-merge `main` — the regime under which three prior designs for the
same problem were found unsound (union-of-appends resurrects deletions;
fragment-identity idempotency was unspecified; a single-writer reconcile
cannot atomically write a protected main). The carve-out exists because no
merge-time rule can reconcile a shared file that concurrent PRs both append
to and prune; the fragment model dissolves the shared file instead.

## Scope

### In scope

- The fragment substrate: `specs/_observations/entries/` (live) and
  `specs/_observations/archive/` (consumed), one observation per file.
- The fragment filename grammar and UID identity scheme, including its
  security validation (charset, containment, collision handling).
- The recording contract: every recording skill writes fragments through one
  shared helper; none appends to a shared committed log.
- Consumption/archival mechanics keyed on the filename UID.
- The derived chronological view (render command) and the drain pass's
  observation surfacing over the fragment directory.
- One-time migration of the existing `opportunities.md`/`archive.md`:
  dedup of resurrected duplicates, then freeze; legacy entries drain in place.
- Doctrine and skill-text reconciliation (accumulator-taxonomy as the
  canonical home of the fragment drain ritual; spec-format glossary; every
  recording/reading skill).
- A CI guard for fragment-name grammar and file shape.

### Out of scope

- Re-solving output-hygiene's other four concerns (PR-body contract, marker
  canonicalization, committed-reference integrity, derived-content hygiene).
- Performing the output-hygiene carve-out amendment itself (scoping REQ-B /
  D-1 / Tasks 1–2 out of that bundle is a separate follow-up per the seed
  brief; this bundle records the supersession and the coordination gate
  only).
- Multi-repo observation routing, fan-in inboxes, and upstream channels — the
  `observation-routing` draft's domain; that draft re-anchors on this
  substrate when revived.
- The reconcile-PR pattern (bot-opened, human-merged consolidation PR):
  research-validated but unnecessary under the reno model; separately
  relevant to `autopilot-reflex`'s release work.
- Adopting towncrier, Changesets, release-please, reno, or any external
  changelog tool — the pattern is borrowed, not the dependency.
- Bulk conversion of legacy log entries into fragments.

## REQ-A — Fragment recording substrate

- **REQ-A1.1** Every new observation SHALL be recorded as its own fragment
  file under `specs/_observations/entries/`; no recording skill SHALL append
  observations to a shared committed log file.
  *(Cites: D-1, the F1–F5 findings (Sources), the research synthesis (Sources).)*
- **REQ-A1.2** Fragment filenames SHALL match
  `<date>-<slug>-<uid>.md`: `<date>` a calendar date `YYYY-MM-DD`, `<slug>` a
  cosmetic kebab-case token (`[a-z0-9]+(-[a-z0-9]+)*`, ≤ 40 chars), `<uid>`
  exactly 8 lowercase hex characters minted from a system entropy source. The
  whole filename is validated against the anchored composite grammar, and
  `<date>` additionally as a real calendar date (shape alone cannot reject
  `2026-02-30`).
  *(Cites: D-2, kickoff lens pass (2026-07-08).)*
- **REQ-A1.3** Fragment creation SHALL enforce UID uniqueness across
  `entries/` and `archive/` (the collision check keys on the UID —
  `*-<uid>.md` in both directories) and SHALL fail on an existing filename
  (never overwrite); either collision retries with a freshly minted UID.
  Retries are bounded (a small fixed cap); retry exhaustion — like an
  unavailable entropy source — is a clean refusal. The uniqueness check sees
  one working tree; cross-branch collisions are caught post-merge by the
  REQ-D1.4 guard's duplicate-UID detection.
  *(Cites: D-2, research: Changesets' unchecked-overwrite gap (Sources),
  kickoff walkthrough (2026-07-08).)*
- **REQ-A1.4** Fragment content SHALL open with the established one-line
  entry form (`- <date> [<scope>] <text>`, trailing provenance sentence
  included), so existing entry-prose conventions carry over; beyond the
  entry line, only recognized metadata lines (currently `Consumed-by:`) and
  blank lines are valid content — free prose rides inside the entry line,
  keeping one-entry-per-file mechanically checkable. Entry text containing
  newlines or control characters is refused at write time.
  *(Cites: D-3, the live log's entry convention (Repo ground truth,
  Sources), kickoff walkthrough (2026-07-08).)*
- **REQ-A1.5** The filename UID SHALL be the entry's durable identity:
  consumption, archival, and citations (`obs:<uid>`) key on it, and it SHALL
  survive slug rename, content edit, and the archive move.
  *(Cites: D-2, D-3.)*
- **REQ-A1.6** A single shared recording helper SHALL mint, validate, and
  write fragments, creating `entries/` on demand (`mkdir -p`; git cannot
  commit an empty directory and a placeholder file would fail the
  REQ-D1.4 grammar, so the directories are never committed empty);
  recording skills SHALL invoke it rather than composing
  fragment paths themselves. The write publishes atomically *and
  exclusively* (temp file, then a publish that fails on an existing
  destination — hard-link-then-unlink or equivalent `O_EXCL` semantics; a
  plain rename silently replaces its target and cannot honor REQ-A1.3's
  never-overwrite guard), so no reader ever sees a torn fragment and a
  racing writer cannot clobber one. On a non-zero
  helper exit the invoking skill SHALL surface the failure rather than
  silently dropping the observation.
  *(Cites: D-6, kickoff lens pass (2026-07-08).)*

## REQ-B — Conflict-freedom invariants

- **REQ-B1.1** Concurrent branches that each record observations SHALL merge
  without conflict on any shared file: fragment additions are distinct
  filenames by construction.
  *(Cites: D-1.)*
- **REQ-B1.2** Archive-on-consume SHALL be a per-fragment, single-file
  operation — move `entries/<file>` to `archive/<file>` with the filename
  (and UID) preserved — conflict-free with concurrent additions; consumption
  SHALL never be keyed on entry text.
  *(Cites: D-3.)*
- **REQ-B1.3** The chronological view SHALL be a derived, on-demand render —
  a pure function of the fragments (plus the frozen legacy file while it
  holds unconsumed entries). No skill, hook, or CI step SHALL commit a
  compiled view of the fragments; the REQ-D1.4 guard's unexpected-file check
  is the standing enforcement.
  *(Cites: D-1, D-4, drafting-session decision (2026-07-08).)*

## REQ-C — Readers, drain, and the class-3 contract

- **REQ-C1.1** The observations accumulator SHALL restate the class-3
  contract (class, durable home, reader, drain ritual — the doctrine's
  classification rule) for the fragment layout: durable home = `entries/` +
  `archive/` (+ the frozen legacy file until drained); canonical reader =
  `/spec-draft`; drain ritual = the drain pass's surfacing — plus
  archive-on-consume (the REQ-B1.2 move) as this accumulator's *specific*
  ritual, not a universal class-3 attribute (output-hygiene REQ-B1.2
  deliberately declined that promotion; this spec preserves it). The
  accumulator-taxonomy doctrine SHALL be amended to carry this as the
  canonical definition.
  *(Cites: D-8, accumulator-taxonomy REQ-H1.1/H1.2 (Sources), kickoff lens
  pass (2026-07-08).)*
- **REQ-C1.2** `/spec-draft` mining SHALL read the live fragments and the
  frozen legacy file's unconsumed entries as one candidate set; consuming a
  fragment appends a `Consumed-by: specs/<spec> (<date>)` line inside it and
  moves it per REQ-B1.2 (annotate first, move second, idempotent on re-run);
  consuming a legacy entry annotates the frozen file in place. The annotate
  step is conditional (skipped when a same-spec `Consumed-by:` line already
  exists) and written atomically, so a re-run neither duplicates nor tears
  the annotation; an `entries/` fragment already bearing a `Consumed-by:`
  line is *consumed* to every reader — mining completes its move rather
  than re-mining it. Consume resolves its UID against `entries/` *and*
  `archive/`: a fragment already archived with a same-spec annotation is
  a clean no-op (a completed consume); a UID matching no file is a clean
  non-zero refusal; a UID matching more than one file (the post-merge
  duplicate window, D-2) is a refusal naming every match — never a
  silent pick. Legacy consumption is keyed on line content, an
  accepted brittleness on a shrinking file (D-5): the line is located by
  fixed-string match (never content-as-pattern, REQ-D1.3), exactly one
  line is annotated — the first unannotated exact match — and textually
  identical unconsumed lines are each independently consumable.
  *(Cites: D-3, D-5, kickoff lens pass (2026-07-08).)*
- **REQ-C1.3** The drain pass SHALL derive the unmined count and
  oldest-entry age from the fragment directory plus the frozen legacy file's
  unconsumed lines (entry-form lines — `- <date> [<scope>] …` — without a
  consumed-by annotation; the freeze header and non-entry prose are never
  counted), naming both surfaces in the report while the legacy file
  still holds unconsumed entries. An `entries/` fragment bearing a
  `Consumed-by:` line is excluded from the unmined count and surfaced as a
  stuck consume. A grammar- or shape-invalid file is excluded from the
  count and named (D-4's deterministic skip-and-warn binds drain and
  mining as much as render — an invalid fragment is never a silently
  lost observation). With zero unmined entries the report states the zero
  count and omits the age line; all globs are null-safe.
  *(Cites: D-4, accumulator-taxonomy REQ-H1.4 (Sources), kickoff lens pass
  (2026-07-08).)*
- **REQ-C1.4** A render command SHALL emit the chronological view of live
  entries (optionally including archived ones) in a defined total order —
  by date, with same-date legacy lines (in file order) before same-date
  fragments (by UID); chronological to day granularity — byte-deterministic
  for a given fragment set and legacy-file state. *Live* means in
  `entries/` without a `Consumed-by:` line.
  *(Cites: D-4, drafting-session decision (2026-07-08), kickoff lens pass
  (2026-07-08).)*

## REQ-D — Security, hygiene, and guards

- **REQ-D1.1** Every filename component SHALL be validated against its
  anchored grammar (under `LC_ALL=C`) before any path use; composed paths
  SHALL be containment-checked after canonicalization; hostile input SHALL
  produce a clean refusal, never a path. This binds every surface that
  composes fragment paths — consume as much as record: the consume UID and
  spec identifier are validated before use (the spec id against the
  established spec-identifier grammar — `^[a-z0-9][a-z0-9-]*$`, at most
  64 characters, the spec-format doctrine's identifier discipline
  (bootstrap REQ-A1.8) — before it is written into the
  `Consumed-by:` line),
  and annotate/move operate only on regular files, never through symlinks.
  *(Cites: D-7, orchestration-concurrency REQ-F1.1 (Sources), kickoff lens
  pass (2026-07-08).)*
- **REQ-D1.2** Fragment content SHALL pass the artifact data-hygiene rule at
  write time (no secrets, credentials, internal hostnames, or sensitive
  operational detail); consumption moves content verbatim and implies no
  re-screen.
  *(Cites: D-7, bootstrap REQ-D1.6 (Sources).)*
- **REQ-D1.3** Render, drain, and mining SHALL treat fragment names and
  content — and the frozen legacy file's lines they interleave — as data
  only: never evaluated or expanded, non-printable bytes stripped before
  echo, per the framework-script security rules.
  *(Cites: D-7, kickoff lens pass (2026-07-08).)*
- **REQ-D1.4** A CI guard, running under `LC_ALL=C`, SHALL validate
  fragment-name grammar (including calendar-date validity),
  one-entry-per-file shape, and UID uniqueness across `entries/` and
  `archive/`, and SHALL fail on unexpected files under
  `specs/_observations/` (anything beyond the two directories and the
  frozen legacy files — the standing block on committed compiled views),
  failing on seeded violations. The guard SHALL be null-safe over absent
  directories (they are created on demand — REQ-A1.6 — and may not exist
  yet in a given tree).
  *(Cites: D-6, kickoff lens pass (2026-07-08).)*

## REQ-E — Migration and cross-spec coordination

- **REQ-E1.1** A one-time migration SHALL (a) remove each live-log line
  provably consumed per `archive.md`'s `consumed-by` records (the resurrected
  duplicates, each removal individually cited in the migration PR), then
  (b) freeze `opportunities.md` and `archive.md` with header notes naming the
  fragment substrate. Legacy entries SHALL NOT be bulk-converted into
  fragments. The removal set SHALL be recomputed against the branch's
  current state immediately before merge (appends continue until the flip
  lands); a candidate line textually identical to a consumed record but
  plausibly a legitimate re-occurrence SHALL be kept, not removed.
  *(Cites: D-5, drafting-session decision (2026-07-08), kickoff lens pass
  (2026-07-08).)*
- **REQ-E1.2** The recording-contract flip (skills stop appending) and the
  legacy freeze SHALL land as one unit, leaving no window in which some
  *shipped* writer appends to the frozen log while another drops
  fragments. In-flight branches checked out from pre-migration `main`
  carry the old skill text until they merge `main`; that residual is
  accepted and monitored (the risk register's post-freeze append
  regression row), outside this requirement's guarantee.
  *(Cites: D-5, kickoff brief §7 risk 3.)*
- **REQ-E1.3** The accumulator-taxonomy doctrine, the spec-format
  glossary's "Observations log" entry *and* its "Citation syntax and kinds"
  table (which SHALL gain the `obs:<uid>` kind), `doctrine/decision-domains.md`,
  `docs/CONTRIBUTING.md`, and every recording or reading skill — all ten
  shipped skills carry at least the drift-log write (`/spec-draft`,
  `/spec-kickoff`, `/execute-task`, `/self-review`, `/polish`, `/drain`,
  `/orchestrate`, `/builder`, `/resume`, `/spec-walkthrough`) — SHALL be
  reconciled to the fragment contract. The drift-log channel routes through
  the shared recording helper, keeping its `skill-drift(...)` entry form
  and its no-`specs/` fallback. No shipped text may instruct writing the
  shared log; the verification grep spans `skills/`, `doctrine/`, and
  `docs/`.
  *(Cites: D-8, kickoff lens pass (2026-07-08).)*
- **REQ-E1.4** This spec supersedes the observations-recording design in
  output-hygiene (its REQ-B, D-1, Tasks 1–2). Output-hygiene Tasks 1–2 SHALL
  NOT be dispatched, and the carve-out amendment on output-hygiene SHALL be
  tracked as an explicit coordination gate: a Deferred entry in `tasks.md`
  whose free-text gate names the amendment's landing, so the drain pass
  surfaces the hold for its entire window (this spec's status cannot
  express it — the hold outlives the spec's active phase).
  *(Cites: D-9, the seed brief (Sources), kickoff lens pass (2026-07-08).)*

## Changelog

- 2026-07-08 — Kickoff sign-off lens-pass edits (42 findings dispositioned;
  see the kickoff brief §8): calendar-date validity, bounded retry +
  entropy refusal, atomic writes, conditional/atomic annotate, the
  half-consumed reader rule, consume-surface validate/contain/refuse
  (spec-id validation, regular-file check), guard widened (`LC_ALL=C`,
  duplicate-UID detection, unexpected-file check), render total order and
  empty-state semantics, reconciliation scope widened to all ten skills +
  `decision-domains.md` + `docs/CONTRIBUTING.md` + the citation-kinds
  table, class-3 arity corrected, migration re-validation + keep-when-in-
  doubt, coordination gate reworded to free text, citation fixes
  (bootstrap Sources entry added; REQ-A1.4 recited), terminology
  de-overloaded (derived render = "chronological view").
- 2026-07-08 — Kickoff walkthrough edits: REQ-A1.3 collision check widened
  to UID uniqueness across `entries/` + `archive/` (keeps the
  `obs:<uid>` → exactly-one-file guarantee structural); REQ-A1.4 fragment
  body restricted to the entry line plus recognized metadata lines and
  blanks (free prose stays inside the entry line).
- 2026-07-08 — Initial draft elicited via `/spec-draft` from the
  observation-recording seed brief and the 2026-07-07 research synthesis.
  Drafting-session decisions: retire both compiled files (pure render
  model), `<date>-<slug>-<8hex>` UID grammar, dedup-then-freeze migration,
  Sources limited to the F1–F5 findings plus brief §8–§9.

## Sources

- **The seed brief** — `specs/_pending/observation-recording.md`
  (2026-07-07, carve-out charter from output-hygiene; problem statement,
  failure history, constraints, and the five open questions).
- **The research synthesis** —
  `specs/_pending/observation-recording-research.md` (fable session
  2026-07-07), primary-source-verified survey of release-please,
  Changesets, towncrier, scriv, semantic-release, git-cliff, knope,
  auto, and reno. Key verified
  facts relied on here: GitHub's server-side merge ignores `merge=union`
  (community discussion #9288; kubernetes/kubernetes#70576); no tool prunes
  a committed compiled file across concurrent contributors; reno's
  filename-UID model is the only prior art with conflict-free edit/delete of
  old entries (reno design docs + scanner source); Changesets writes
  fragments with no existence check. The synthesis document is a session
  artifact committed for durable citation (the kickoff resolution, brief
  §2); the primary-source citations above are the durable references.
- **output-hygiene kickoff brief §8 and §9** — the sign-off lens pass and
  the two delta re-walkthroughs recording the three failed D-1 designs
  (§9 currently lives on branch `planwright/output-hygiene/spec`).
- **The F1–F5 panel findings** — four log entries of 2026-07-07 covering
  the five findings F1–F5 (F3 and F5 share one
  `spec-findings(output-hygiene, minor, F3+F5)` entry) on branch
  `chore/log-oh-findings` (commit 7ac4c2c); their consumption (in-place
  annotation — the legacy arm, they are log lines, not fragments) is
  deferred to the migration task since they are not yet on
  `main`.
- **accumulator-taxonomy doctrine** — the class-3 contract this spec
  restates for the fragment layout.
- **orchestration-concurrency REQ-F1.1** — the validate/contain/refuse
  security pattern REQ-D1.1 mirrors.
- **bootstrap REQ-D1.6** — the artifact data-hygiene rule (no secrets,
  credentials, internal hostnames, or sensitive operational detail in
  committed artifacts) that REQ-D1.2 applies at fragment write time.
- **Repo ground truth (2026-07-08)** — the live log holds 166 entries of
  which 10 are resurrected duplicates of already-archived entries (verified
  against `archive.md`'s consumed-by records): the union-resurrection
  failure observed in production, evidence for D-1 and D-5.
- **Drafting-session decisions (2026-07-08)** — the four selector outcomes
  recorded in the Changelog entry above.
