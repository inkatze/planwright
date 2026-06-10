# Opportunities

- 2026-06-10 [planwright] Repo ships no doc-grounding tooling (no markdownlint/vale/link checker), so `/polish` on spec-only diffs can never produce Auto-applicable findings; Task 2 (quality guards & CI) could include doc linters to unlock autonomous draining on spec bundles.
- 2026-06-10 [planwright] The hand-drawn ASCII dependency graph in `tasks.md` drifted from the `Dependencies:` lines on first authoring; consider generating the graph from `Dependencies:` lines (or treating the lines as sole source of truth and dropping the drawing).
- 2026-06-10 [planwright] The critical-path claim in `tasks.md`/the brief was computed by hand and is wrong; a tiny script (deps + efforts → longest chain) would make critical-path-first selection (REQ-F1.2) verifiable instead of asserted.
