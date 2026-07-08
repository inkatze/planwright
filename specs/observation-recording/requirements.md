# Observation Recording — Requirements

**Status:** Draft
**Last reviewed:** 2026-07-08
**Format-version:** 1

## Goal

Replace the shared-file observations log with a conflict-free, fragment-based
recording substrate modeled on reno (OpenStack): every recording skill drops a
per-entry fragment file with a stable filename UID under
`specs/_observations/entries/`; consumption and archival become per-file moves
keyed on that UID; the human-readable chronological log becomes a derived view
rendered on demand, never committed. This preserves the class-3 accumulator
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
  D-1 / Tasks 1–2 out of that bundle is a separate follow-up per the seed;
  this bundle records the supersession and the coordination gate only).
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
  whole filename is validated against the anchored composite grammar.
  *(Cites: D-2.)*
- **REQ-A1.3** Fragment creation SHALL fail on an existing filename (never
  overwrite) and retry with a freshly minted UID.
  *(Cites: D-2, research: Changesets' unchecked-overwrite gap (Sources).)*
- **REQ-A1.4** Fragment content SHALL open with the established one-line
  entry form (`- <date> [<scope>] <text>`, trailing provenance sentence
  included), so existing entry-prose conventions carry over; metadata lines
  (for example `Consumed-by:`) MAY follow the entry line.
  *(Cites: D-3, output-hygiene D-1 (Sources).)*
- **REQ-A1.5** The filename UID SHALL be the entry's durable identity:
  consumption, archival, and citations (`obs:<uid>`) key on it, and it SHALL
  survive slug rename, content edit, and the archive move.
  *(Cites: D-2, D-3.)*
- **REQ-A1.6** A single shared recording helper SHALL mint, validate, and
  write fragments; recording skills SHALL invoke it rather than composing
  fragment paths themselves.
  *(Cites: D-6.)*

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
- **REQ-B1.3** The chronological log SHALL be a derived, on-demand render — a
  pure function of the fragments (plus the frozen legacy file while it holds
  unconsumed entries). No skill, hook, or CI step SHALL commit a compiled
  view of the fragments.
  *(Cites: D-1, D-4, drafting-session decision (2026-07-08).)*

## REQ-C — Readers, drain, and the class-3 contract

- **REQ-C1.1** The observations accumulator SHALL restate the class-3
  contract for the fragment layout: durable home = `entries/` + `archive/`
  (+ the frozen legacy file until drained); canonical reader = `/spec-draft`;
  drain ritual = the drain pass's surfacing; archive ritual = the REQ-B1.2
  move. The accumulator-taxonomy doctrine SHALL be amended to carry this as
  the canonical definition.
  *(Cites: D-8, accumulator-taxonomy REQ-H1.1/H1.2 (Sources).)*
- **REQ-C1.2** `/spec-draft` mining SHALL read the live fragments and the
  frozen legacy file's unconsumed entries as one candidate set; consuming a
  fragment appends a `Consumed-by: specs/<spec> (<date>)` line inside it and
  moves it per REQ-B1.2 (annotate first, move second, idempotent on re-run);
  consuming a legacy entry annotates the frozen file in place.
  *(Cites: D-3, D-5.)*
- **REQ-C1.3** The drain pass SHALL derive the unmined count and
  oldest-entry age from the fragment directory plus the frozen legacy file's
  unconsumed lines, naming both surfaces in the report while the legacy file
  still holds unconsumed entries.
  *(Cites: D-4, accumulator-taxonomy REQ-H1.4 (Sources).)*
- **REQ-C1.4** A render command SHALL emit the chronological view of live
  entries (optionally including archived ones) ordered by date then UID,
  byte-deterministic for a given fragment set.
  *(Cites: D-4, drafting-session decision (2026-07-08).)*

## REQ-D — Security, hygiene, and guards

- **REQ-D1.1** Every filename component SHALL be validated against its
  anchored grammar (under `LC_ALL=C`) before any path use; composed paths
  SHALL be containment-checked after canonicalization; hostile input SHALL
  produce a clean refusal, never a path.
  *(Cites: D-7, orchestration-concurrency REQ-F1.1 (Sources).)*
- **REQ-D1.2** Fragment content SHALL pass the artifact data-hygiene rule at
  write time (no secrets, credentials, internal hostnames, or sensitive
  operational detail); consumption moves content verbatim and implies no
  re-screen.
  *(Cites: D-7, bootstrap REQ-D1.6 (Sources).)*
- **REQ-D1.3** Render, drain, and mining SHALL treat fragment names and
  content as data only: never evaluated or expanded, non-printable bytes
  stripped before echo, per the framework-script security rules.
  *(Cites: D-7.)*
- **REQ-D1.4** A CI guard SHALL validate fragment-name grammar and
  one-entry-per-file shape for `entries/` and `archive/`, failing on seeded
  violations.
  *(Cites: D-6.)*

## REQ-E — Migration and cross-spec coordination

- **REQ-E1.1** A one-time migration SHALL (a) remove each live-log line
  provably consumed per `archive.md`'s `consumed-by` records (the resurrected
  duplicates, each removal individually cited in the migration PR), then
  (b) freeze `opportunities.md` and `archive.md` with header notes naming the
  fragment substrate. Legacy entries SHALL NOT be bulk-converted into
  fragments.
  *(Cites: D-5, drafting-session decision (2026-07-08).)*
- **REQ-E1.2** The recording-contract flip (skills stop appending) and the
  legacy freeze SHALL land as one unit, leaving no window in which some
  writers append to the frozen log while others drop fragments.
  *(Cites: D-5.)*
- **REQ-E1.3** The accumulator-taxonomy doctrine, the spec-format glossary's
  "Observations log" entry, and every recording or reading skill
  (`/spec-draft`, `/spec-kickoff`, `/execute-task`, `/self-review`,
  `/polish`, `/drain`, `/orchestrate`) SHALL be reconciled to the fragment
  contract; no shipped text may instruct writing the shared log.
  *(Cites: D-8.)*
- **REQ-E1.4** This spec supersedes the observations-recording design in
  output-hygiene (its REQ-B, D-1, Tasks 1–2). Output-hygiene Tasks 1–2 SHALL
  NOT be dispatched, and the carve-out amendment on output-hygiene SHALL be
  tracked as an explicit coordination gate (Deferred entry in `tasks.md`).
  *(Cites: D-9, the seed brief (Sources).)*

## Changelog

- 2026-07-08 — Initial draft elicited via `/spec-draft` from the
  observation-recording seed brief and the 2026-07-07 research synthesis.
  Drafting-session decisions: retire both compiled files (pure render
  model), `<date>-<slug>-<8hex>` UID grammar, dedup-then-freeze migration,
  Sources limited to the F1–F5 findings plus brief §8–§9.

## Sources

- **The seed brief** — `specs/_pending/observation-recording.md`
  (2026-07-07, carve-out charter from output-hygiene; problem statement,
  failure history, constraints, and the five open questions).
- **The research synthesis** — fable session 2026-07-07,
  primary-source-verified survey of release-please, Changesets, towncrier,
  scriv, semantic-release, git-cliff, knope, auto, and reno. Key verified
  facts relied on here: GitHub's server-side merge ignores `merge=union`
  (community discussion #9288; kubernetes/kubernetes#70576); no tool prunes
  a committed compiled file across concurrent contributors; reno's
  filename-UID model is the only prior art with conflict-free edit/delete of
  old entries (reno design docs + scanner source); Changesets writes
  fragments with no existence check. The synthesis document itself is a
  session artifact; its citations above are the durable references.
- **output-hygiene kickoff brief §8 and §9** — the sign-off lens pass and
  the two delta re-walkthroughs recording the three failed D-1 designs
  (§9 currently lives on branch `planwright/output-hygiene/spec`).
- **The F1–F5 panel findings** — four `spec-finding(output-hygiene D-1 …)`
  entries of 2026-07-07 on branch `chore/log-oh-findings` (commit 7ac4c2c);
  archive-on-consume for these entries is deferred to the migration task
  since they are not yet on `main`.
- **accumulator-taxonomy doctrine** — the class-3 contract this spec
  restates for the fragment layout.
- **orchestration-concurrency REQ-F1.1** — the validate/contain/refuse
  security pattern REQ-D1.1 mirrors.
- **Repo ground truth (2026-07-08)** — the live log holds 166 entries of
  which 10 are resurrected duplicates of already-archived entries (verified
  against `archive.md`'s consumed-by records): the union-resurrection
  failure observed in production, evidence for D-1 and D-5.
- **Drafting-session decisions (2026-07-08)** — the four selector outcomes
  recorded in the Changelog entry above.
