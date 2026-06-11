# Observations log

- 2026-06-10 [planwright] Repo ships no doc-grounding tooling (no markdownlint/vale/link checker), so `/polish` on spec-only diffs can never produce Auto-applicable findings; Task 2 (quality guards & CI) could include doc linters to unlock autonomous draining on spec bundles.
- 2026-06-10 [planwright] The hand-drawn ASCII dependency graph in `tasks.md` drifted from the `Dependencies:` lines on first authoring; consider generating the graph from `Dependencies:` lines (or treating the lines as sole source of truth and dropping the drawing).
- 2026-06-10 [planwright] The critical-path claim in `tasks.md`/the brief was computed by hand and was wrong (corrected 2026-06-10); a tiny script (deps + efforts → longest chain) would make critical-path-first selection (REQ-F1.2) verifiable instead of asserted.
- 2026-06-11 [planwright] Task 3 and Task 4 branches both populate `doctrine/`; the doctrine README index (Task 3 branch) will need a `spec-format.md` entry once both merge.
- 2026-06-11 [planwright] `scripts/spec-anchor.sh` (canonical anchor form) now ships; the kickoff brief's anchor entries still use the interim whole-file form. `/spec-kickoff` (Task 9) and the emulated orchestrate state-move re-anchors can switch to the canonical form, ending the forced re-anchor on every tasks.md state move.
