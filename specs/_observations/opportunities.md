# Observations log

- 2026-06-10 [planwright] Repo ships no doc-grounding tooling (no markdownlint/vale/link checker), so `/polish` on spec-only diffs can never produce Auto-applicable findings; Task 2 (quality guards & CI) could include doc linters to unlock autonomous draining on spec bundles.
- 2026-06-10 [planwright] The hand-drawn ASCII dependency graph in `tasks.md` drifted from the `Dependencies:` lines on first authoring; consider generating the graph from `Dependencies:` lines (or treating the lines as sole source of truth and dropping the drawing).
- 2026-06-10 [planwright] The critical-path claim in `tasks.md`/the brief was computed by hand and was wrong (corrected 2026-06-10); a tiny script (deps + efforts → longest chain) would make critical-path-first selection (REQ-F1.2) verifiable instead of asserted.
- 2026-06-11 [planwright] REQ-D1.1 does not define fan-out partial-failure handling (a lens sub-agent that dies or returns nothing leaves a silent coverage hole the lens-coverage table cannot show); candidate spec amendment surfaced while migrating Discovery Rigor (T3).
- 2026-06-11 [planwright] REQ-D1.2's non-convergence rule ("drop or downgrade") has no decision tree (2-of-3 vs 1-of-3 pass agreement); skills will improvise differently; candidate spec amendment surfaced while migrating Validation Rigor (T3).
- 2026-06-11 [planwright] REQ-C1.7's resolution ladder is silent on partial answers, contradictions between rungs (brief vs research), and unevaluable rungs; candidate spec amendment surfaced while migrating Finding Categorization (T3).
