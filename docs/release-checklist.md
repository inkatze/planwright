# Public-release readiness checklist

planwright starts **private** (D-27, REQ-J1.5). The private→public flip is a
deliberate human decision, gated on conditions that must be **verified, not
remembered**. This checklist is the gate. It enumerates every condition,
says how each is verified, and pairs with an executable verifier
([`scripts/release-checklist.sh`](../scripts/release-checklist.sh)) for the
parts a machine can confirm.

The checklist **verifies; it never performs.** In particular, the `reference/`
history purge is a human-reserved action (REQ-J1.4): the checklist confirms it
happened, it does not carry it out.

## Scope

Two groups of conditions block public release:

1. **The three REQ-J1.5 gate conditions** — (a), (b), (c) below.
2. **Every release-blocking gated Deferred entry** — currently the `reference/`
   history purge. This scope (gates *plus* release-blocking Deferred entries)
   was fixed at brief Amendment 6 so future Deferred entries carrying a
   "before any public release" gate cannot silently re-open the same hole.

Run the verifier from a clean checkout:

```bash
scripts/release-checklist.sh                       # report current state
scripts/release-checklist.sh --confirm-workrepo-run  # attest condition (c)
```

It exits `0` only when every mechanical gate passes and condition (c) is
attested; otherwise it prints a per-gate `PASS` / `BLOCK` / `MANUAL` table and
exits non-zero. It is intentionally **not** part of `mise run check` (it
correctly fails pre-release); its unit test is.

## The gates

### (a) CLAUDE.md rules inlined into planwright's own doctrine

- [ ] The framework intelligence that began as the author's dotfiles
      `CLAUDE.md` rules lives as standalone doctrine docs under
      [`doctrine/`](../doctrine/) (the rigor docs, finding categorization,
      engineering doctrine), not as an external dependency.

**Verified by:** the script confirms the load-bearing rule docs exist and are
non-empty. **Why it gates release:** the skills are hollow until the
intelligence they cite is inlined and resolvable in both delivery modes.

### (b) The four-file format meta-spec exists

- [ ] [`doctrine/spec-format.md`](../doctrine/spec-format.md) — the meta-spec
      defining the status lifecycle, the kickoff-brief structure, the
      amendment ritual, sign-off records, and content anchors — exists.

**Verified by:** the script confirms the meta-spec file is present and
non-empty. **Why it gates release:** without the meta-spec, an adopter has no
defined contract to draft specs against.

### (c) One clean end-to-end run on a real multi-contributor work repo

- [ ] At least one full pipeline run (draft → kickoff → orchestrate → execute →
      polish → draft PR) has completed on a real multi-contributor work repo,
      with a findings document covering gate behavior, kickoff-brief
      effectiveness, dispatch-backend behavior, and the completed
      manual-verification sweep (every `[manual]` / `[Gherkin]` test-spec
      entry exercised or its gap named).

**Verified by:** a **human attestation** — this cannot be detected from the
planwright repo itself. Confirm the run and its findings doc exist, then pass
`--confirm-workrepo-run` (or set `RELEASE_WORKREPO_RUN_CONFIRMED=1`). **Why it
gates release:** a clean run on a real repo is what proves planwright is usable
by someone who is not its author. See bootstrap Task 18 (Deferred — organically
satisfied by the work fork's first real run).

## Release-blocking gated Deferred entries

### The `reference/` history purge (human-reserved, REQ-J1.4)

- [ ] `reference/` is absent from the working tree.
- [ ] `reference/` is absent from **all git history** — verified by a history
      rewrite, not a plain `git rm`.

`reference/` holds transient migration sources (the dotfiles `CLAUDE.md`, the
pair-flow spec) that may contain personal or work data which must not persist
in a public history. The purge is a deliberate human history rewrite
(e.g. `git filter-repo`) and also covers spec-file blobs in pre-neutralization
commits (work-repo identifiers scrubbed from file content survive in earlier
commits).

**Verified by:** the script checks both the working tree and
`git log --all -- reference`. A delete commit leaves the blobs reachable in
history and still **BLOCKS** — the gate has teeth beyond a tree check. **The
checklist never performs the purge** (REQ-J1.4): a human runs the rewrite, the
checklist confirms it.

## Final flip

When the verifier reports `READY FOR PUBLIC RELEASE`:

- [ ] Flip the repository visibility private → public (human action).
- [ ] Bump the plugin manifest `version` for the public release (the version
      stays `0.x` while private; the release process owns the bump).

Both are human actions; planwright never performs them. Nothing in this
checklist auto-merges, force-pushes, or rewrites history.
