# Seed brief for `observation-recording` (carved out of `output-hygiene`)

Suggested invocation (fresh Claude session in the planwright repo, this file is the seed):

    /spec-draft observation-recording

…and **ultrathink**. Read this whole brief plus the two references at the bottom before eliciting.

## Why this spec exists (the carve-out)

`output-hygiene` (Ready, merged PR #124) originally bundled five concerns. Four are clean and
stay in output-hygiene: the human-first PR-body contract, pending-sign-off marker
canonicalization, committed-reference integrity, and derived-content hygiene (its Tasks 3/4/5/6/8).
The fifth — **conflict-free observations recording** (its REQ-B, D-1, Tasks 1/2) — turned out to
be a genuine design tar pit: it was reworked **three times** and an independent review found each
version unsound. It is being **carved into this dedicated spec** to get a proper, research-grounded
design. (A separate follow-up will scope REQ-B / D-1 / Tasks 1-2 OUT of output-hygiene; do not
re-solve output-hygiene's other four concerns here.)

## The problem

planwright accumulates cross-cutting "observation" entries (improvement notes surfaced by skills)
into a shared log `specs/_observations/opportunities.md`, with a class-3 accumulator contract:
durable home, canonical reader (`/spec-draft`), a drain ritual (drain-pass surfacing of unmined
count + oldest age), and **archive-on-consume** (when `/spec-draft` mines an observation into a
new bundle, it moves that entry OUT of `opportunities.md` into `archive.md`).

Today this collides badly under concurrency:
- **Many writers, many branches:** every recording skill (`/execute-task`, `/self-review`,
  `/spec-kickoff`, `/spec-draft`) **appends a line** to `opportunities.md` on its own feature
  branch, and `/spec-draft` also **deletes** consumed entries. Concurrent branches conflict on the
  shared file at merge (we hit this live on PR #124).
- **GitHub ignores `.gitattributes merge=union`** on PR merges (verified: community discussion
  #9288; kubernetes removed their union driver, PR #70576). No merge-driver escape hatch.
- `main` is **PR-only, squash-merge, and never-auto-merge** (a human merges every PR). No direct
  pushes.

## What was already tried and found unsound (do not repeat)

1. **Fragment queue + single default-branch consolidation, `union-of-appends` on conflict.**
   Panel review found: the log is **not append-only** (archive/trim deletes), so union
   **resurrects archived deletions**.
2. **Fragment-identity idempotency + union.** Underspecified: entries carried no id, so union
   can't dedup; and idempotency-at-merge presupposes concurrent writers.
3. **Single-writer-total (the reconcile owns every mutation).** Panel review found two deep gaps:
   (a) the reconcile can't atomically write a PR-only / never-auto-merge `main`; (b) archival by
   exact-text-match is brittle — entries need a stable identity.

The recurring crux: **no merge-time rule reconciles a shared file that many PRs both APPEND to and
later PRUNE (archive) concurrently.**

## The chosen design direction (research-validated) — build the spec around this

Two independent research passes (fable session + a research agent, both primary-source-verified;
full synthesis at `/tmp/obs-research-synthesis.md`) reached the same verdict:

- **No prior art prunes an accumulating shared file.** release-please, Changesets, towncrier,
  scriv, semantic-release are all **append-forever** on the compiled file; deletion happens only
  at the **fragment** level. Every project that faced planwright's exact add+prune need
  **eliminated the accumulating file** (GitLab is the case study: built fragment+archive, hit the
  friction, abandoned it).
- **The answer is the reno (OpenStack) model:**
  - Observations live as **per-entry fragment files** in a directory, each with a **stable UID in
    the filename** (reno uses 16-hex; planwright can use a run/nonce-derived token). Concurrent
    PRs add distinctly-named files → **never conflict**.
  - **`opportunities.md` is NOT a committed accumulating file — it is a *rendered view*** (a drain
    / render command regenerates it on demand from the fragment directory; a pure function of the
    fragments). Humans read the rendered view; `/spec-draft` mines the fragment directory; the
    drain pass reads it.
  - **Archive-on-consume = move/delete the consumed fragment file** (to an archive dir) — a
    per-file operation, **conflict-free**. Identity for consumption/archival = the **filename UID**
    (never brittle exact-text matching).
  - Every recording skill **drops a fragment** (never writes a shared log).

This **dissolves** all the prior failures at once: no shared-file conflict (fragments), no
reconcile-PR-to-a-protected-main (nothing compiled is committed), no prune conflict (delete a
file), no identity problem (filename UID). And it is **less machinery** than any prior attempt —
a directory of fragments + a render command + move-on-consume. It also aligns with planwright's
own "derived projection, regenerate from truth" philosophy (`opportunities.md` becomes a derived
view, like tasks.md placement).

**The one tradeoff to state in the design:** `opportunities.md` stops being a file you `cat` — it
becomes a rendered view. For planwright this is minor (the log is mostly machine-read by
`/spec-draft`; humans use the drain). reno and GitLab both accept exactly this.

## Constraints / non-goals

- **Claude Code primitives only** (no towncrier/changesets/release-please dependency — borrow the
  *pattern*, not the tool). The reconcile-PR pattern was validated by the research but is **not
  needed** for the reno model and is out of scope here (it's separately relevant to
  `autopilot-reflex`'s release-please work).
- Preserve the class-3 accumulator contract (durable home, canonical reader, drain, archive) —
  restated for the new fragment-directory layout.
- Migration: there's an existing `specs/_observations/opportunities.md` + `archive.md` with real
  entries (one-line bullets, no ids). The spec must say how existing entries migrate to fragments
  (or whether the old file is retired/kept frozen).
- Security/data-hygiene: fragment filenames are derived from run identifiers — validate against the
  charset before path use, containment-check, clean refusal (mirror orchestration-concurrency
  REQ-F1.1); no secrets in fragment content (write-time screening).

## Open questions for the drafter to resolve (with the human)

1. **Is `opportunities.md` retired entirely, or kept as a committed rendered snapshot** refreshed
   by a render step? (reno retires it; a committed snapshot is a convenience but reintroduces a
   written file — decide the tradeoff.)
2. **Fragment UID scheme** — reuse output-hygiene's `<date>-<taskid>-<run-nonce>` grammar, or
   reno-style random hex? Needs to be stable (survives for archival reference) and collision-free.
3. **Drain + `/spec-draft` mining semantics** over a fragment directory (they currently read one
   file): count/oldest-age from the dir; mining reads all fragments; archive moves a fragment.
4. **Migration of the existing log** (~150 live entries).
5. **Does the human ever need a single chronological file**, or is the on-demand render enough?

## References (read these)

- `/tmp/obs-research-synthesis.md` — the fable research session's primary-source synthesis
  (platform facts, per-tool table, the reno precedent, the reconcile-PR verdict, what naive
  designs get wrong).
- `specs/output-hygiene/kickoff-brief.md` §8 and §9 — the panel findings F1–F5 and the three
  failed D-1 design rounds, in detail.
- `specs/_observations/opportunities.md` — the four `spec-finding(output-hygiene D-1 …)` entries
  (2026-07-07) logging F1/F2/F4/F3/F5, plus the live entries that need migrating.
