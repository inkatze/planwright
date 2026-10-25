# Inception — Kickoff Brief

## 1. Header

- **Spec path:** `specs/inception`
- **Spec commit at walkthrough start:** `c551736` (feat(spec): draft specs/inception bundle)
- **Walkthrough date(s):** 2026-07-10 —
- **Mode:** first activation (Status Draft, no prior brief)
- **Validator outcome (pre-flight):** `spec-validate.sh specs/inception` — 0 errors, 0 warnings
- **Config:** `commit_on_kickoff: true`, `mark_spec_pr_ready_on_kickoff: true` (defaults; no local
  overrides)
- **Rule docs resolved:** spec-format, discovery-rigor, validation-rigor, security-posture,
  decision-domains, interaction-style — all from this worktree's `doctrine/`
- **Working location:** spec worktree `.claude/worktrees/inception-spec`, branch
  `planwright/inception/spec` (9 commits behind `origin/main` at walkthrough start; untracked
  `research/` directory is deliberate operator-side material per the spec's Sources)
- **Pre-walkthrough research:** operator requested a state-of-the-art re-check before the walk;
  three commissioned sweeps (tooling landscape and D-1 adversarial check; persona-panel patterns;
  validation/collaboration seams) recorded operator-side under `research/sota-*.md`, findings
  folded into the walkthrough sections below as F1–F16.

## 2. Goal & glossary

**Restatement (confirmed by the operator):** `/inception` is the pipeline stage for ideas that do
not yet have a home. It takes a fuzzy, product-level, multi-discipline idea and produces a
durable, validated orientation — not a spec: the inception bundle (brief, discipline/stakeholder
map, assumption register, decision backlog, validation plan) inside a venture git repo the skill
creates and wraps so non-engineers can operate it. Its distinctive core is the discipline-persona
table: small, parallel, evidence-grounded seats compiled from task-framing cards, synthesized
once, challenged once, with structural honesty about which calls only a human can make.
Validation work runs deliberately light (PR-less, human-accepted, register-linked). A four-outcome
human gate governs progress; graduation emits a seed package to `/spec-draft` — never a spec,
never auto-chained. Rules out: inventing the pitch, deciding human-authority calls, non-git
truth, symmetric sync, identity personas. Assumes: single operator, Claude Code primitives only,
operator holds the decision on everything irreversible.

**Implicit terms surfaced:** venture, track, seat/bench, frame, operator vs stakeholder vs gate
decider, minimum core, rung. All but two are defined by the D-IDs; the two ambiguities were
resolved:

1. **Altitude boundary (home-repo ideas).** Resolution: operator's choice — the out-of-scope
   line means "not a replacement", not a ban; a home-repo idea may opt into a venture; routing
   heuristics stay recommend-only both directions. Applied as a Scope clarification in
   `requirements.md`.
2. **Track identity.** "Track" was load-bearing (Goal, REQ-E, REQ-F1.1, REQ-F1.3) but
   structurally undefined. Resolution: REQ-C1.11 added — optional track labels on assumptions,
   decisions, and plan tasks; single-track ventures need none; gate records may carry per-track
   outcomes; partial graduation keys on labels; grammar lives in the inception-format doctrine.
   Test-spec entry added.

Signed off: 2026-07-10

## 3. Requirements walkthrough

**Scope:** all 11 REQ groups (A–J, P) restated; the 2026-07-10 SOTA re-check adopt/adapt findings
folded per the operator's clustered dispositions (all "Apply all", 2026-07-13). Consolidated REQ
edits applied in place.

**Per-group outcomes:**

- Groups A, B, D, E, F, H, J — confirmed as drafted; no requirements-text change beyond the probe
  edits below.
- Group C — register fields sharpened: REQ-C1.3 (believe/verify/measure/right-if skeleton,
  evidence-ladder grade, fail-condition thresholds, synthetic-grade + Graduate exclusion),
  REQ-C1.4 (MADR deciders + consequences, merge-as-ratification), REQ-C1.5 (time/cost cap +
  single-limiting-constraint tie-break), REQ-C1.7 (reader version-gating fail-closed +
  additive-within-major evolution).
- Group I — REQ-I1.4 now names the evidence ladder, fail-condition thresholds, and the synthetic
  grade the register cites; REQ-I1.3 (non-code lenses) and the seam-reuse domain unchanged.
- Group P — persona cluster folded: REQ-P1.1 (frame-specific mandate, ordered frameworks, named
  knowledge-sources, blind spots, conflict/deference, stance axis), P1.2 (out-of-scope line), P1.3
  (anonymize + shuffle before synthesis), P1.4 (persona-free synthesis + challenge), P1.5 (typed
  triggers + typed human powers + per-seat independence), P1.6 (stake-scored triage + per-seat
  model default), P1.8 (zero-seat collapse), P1.9 (convergence demotion).

**Probe resolutions (operator calls, 2026-07-13):**

1. Kill-date blindness (REQ-C1.6 / E1.3 / J1.7): accepted v1 limitation; the no-arg portfolio
   surfaces tripped/approaching dates on invocation (no daemon in v1). → risk R1.
2. Zero-seat vs unstaffed auto-file (REQ-B1.5 ↔ P1.8): collapse to a single "personas waived
   (zero-seat); N unstaffed" row. → REQ-P1.8 edit.
3. Export staleness on the local rung (REQ-G1.1 ↔ A1.9): scaffold a pre-commit export-regen step
   on every rung. → REQ-A1.9 / G1.1 edits, D-9. → risk R2.
4. Ephemeral home (REQ-A1.4 / A1.5 / H1.1): proceed session-only-warned per the ladder floor,
   never a silent refusal. → REQ-A1.5 clarifying clause.

Signed off: 2026-07-13

## 4. Design walkthrough

Every D-ID accounted for; all confirmed with rationale intact except the following amended (SOTA
adopt/adapt, operator "Apply all"):

- **D-1** — claim tightened: Product Forge and GLIDR AI named as nearest misses; the uncomposed
  claim scoped to an evidence-graded register + decision backlog + thresholded validation plan at
  venture scope, git-native. Additive-within-major evolution + reader version-gating added.
- **D-2** — Ringelmann scaling-law citation (arXiv:2606.02646); anonymize + order-shuffle before
  synthesis/challenge; persona-free synthesis + challenge; convergence marks demoted to a weak,
  claim-type-annotated, outlier-named signal; Forward-log known-tension note (one-amendment cap vs
  multi-round critic gains; confidence-gated escalation is the evidenced later shape).
- **D-3** — card schema gains frame-specific mandate, ordered framework sequence, named
  knowledge-sources, out-of-scope line, blind spots, conflict/deference rules, optional stance axis.
- **D-4 / D-6** — out-of-scope negative line; typed escalation-trigger taxonomy; typed human powers
  (disregard/override/reverse/halt) at Gate 2; per-seat independence.
- **D-7** — stake/reversibility-scored seat-count triage (SHOULD, where the signal is cheap);
  per-seat model override where the backend advertises it, lost decorrelation reported (softened
  from SHALL/by-default in the sign-off lens pass, per the scope finding).
- **D-20** (new) — records the product/doctrine altitude (upstream of `/spec-draft`,
  doctrine-first decomposition), cited from the Goal; the altitude-record insurance from the lens
  pass.
- **D-8** — atomic registry writes (write-temp-then-rename); scan-rebuild remains recovery (R7).
- **D-9** — regeneration wired as a scaffolded pre-commit step on every rung.
- **D-10** — Notion unresolved-only harvest + no resolve-API (repo triage ledger is the only
  record) + pinned API version + Markdown Content API; Google Docs re-ranked (drive.file, no CASA —
  strong v2, still deferred); Outline added to deferred; Coda double-justified.
- **D-11** — Cowork protocol imported from venture root `CLAUDE.md` (filename-contract hedge);
  egress-blocked push/pull degrades gracefully; advisory + D-12 validator is the enforcement.
- **D-14** — gate records are structured machine-readable entries
  (outcome/date/decider/evidence/thresholds/rationale), not prose.
- **D-15** — seed stays format-clean enough to also emit a Spec Kit `/specify` input (interop
  constraint, no v1 work).

No design decision contradicts a walked requirement (verified in the sign-off lens pass).

Signed off: 2026-07-13

## 5. Verification approach

Coverage mix unchanged (fixture `[test]` + `[manual]` dogfood + `[design-level]` + `[Gherkin]`); no
dead paths introduced. New fixtures/assertions added across REQ-A1.6 (atomic-write concurrency),
A1.9 (pre-commit regen every rung), C1.3 (ladder grade + synthetic exclusion), C1.4 (MADR fields),
C1.5 (caps + constraint tie-break), C1.7 (unsupported-version fail-closed), E1.1 (synthetic blocks
desirability Graduate), E1.5 (machine-readable gate record), P1.1 (new card fields +
frame-specific-question lint), P1.2 (out-of-scope line), P1.3 (anonymized/shuffled synthesis
input), P1.4 (persona-free steps), P1.5 (typed triggers + human powers), P1.8 (zero-seat collapse),
P1.9 (claim-type-annotated convergence). Ownership: `[test]` under `mise run check` CI; `[manual]`
swept by the continuous dogfood (Task 17) + Cowork validation (Task 14).

Signed off: 2026-07-13

## 6. Task graph

Dependency graph unchanged (the `Dependencies:` lines are authoritative). Critical path
Task 1 → 2 → 7 → {9, 10, 11}; walking-skeleton arc (1 → 2 → 7 → 8 + Task 12 stub) ships first;
guard infra (1, 2, 3) leads; Task 17 dogfood runs continuously. No SOTA edit adds a task; all
extend existing deliverables (Task 1 grammar + version rules, Task 2 fixtures + pre-commit scaffold,
Task 3 evidence doctrine, Tasks 4/5 card fields, Task 8 atomic writes, Task 9 fan-out mechanics,
Task 11 gate record, Task 12 pre-commit regen, Task 13 Notion, Task 14 Cowork; Deferred gains
Outline). New coupling (not a new dependency): Task 2's hygiene scaffold emits a pre-commit hook
that invokes the renderer (Task 2 ships the stub, Task 12 replaces it). Deliberate non-edges
(parallel cards, independent seats) preserved.

Signed off: 2026-07-13

## 7. Risk register

**Decision-domains gap check:** walked all 11 catalog domains (`resolve-catalog.sh
decision-domains`). Decided/covered: data-storage (D-5/D-8), caching (n/a — regen-on-commit),
queues-async (D-7), api-surface (D-10/D-15/C1.7), auth (G1.7/A1.9/security-posture), secrets-config
(A1.3/I1.6/G1.7), observability (D-8/J1.8), dependency-adoption (D-9/D-10 + the seam-reuse domain
the spec adds), versioning-scheme (C1.7). Two touched-but-undecided domains were decided this
session: concurrency (R7) and deploy-migration (R8).

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| R1 | Kill-date blindness (no daemon) | Portfolio surfaces tripped/approaching dates on invocation; accepted v1 limitation |
| R2 | Export staleness on out-of-session edits | Pre-commit export-regen scaffold + CI where remote; residual on rungs lacking the hook |
| R3 | Convergence-mark over-trust (correlated errors) | Claim-type annotation, outlier naming, never-as-probability; grounding outranks vote count (D-2/P1.9) |
| R4 | Synthetic/persona-panel evidence over-trust | Named low grade, excluded from a desirability Graduate threshold (C1.3/E1.1/I1.4) |
| R5 | IP / AI-arch card + platform-claim staleness | Rot metadata + build-time re-verification (design cross-cutting) |
| R6 | Multi-agent cost blowup | Gate 1 discloses seats × backend × cost; small default + bench; stake-scored triage (P1.6) |
| R7 | Concurrent-session registry write race | Atomic write-temp-then-rename prevents torn writes; a rare lost-update self-heals via the ventures_root scan-rebuild (REQ-A1.6/D-8) — resolved this session |
| R8 | Inception-format version skew (bundles outlive plugin) | Reader version-gating fail-closed + additive-within-major evolution; migration transform deferred to first breaking bump (REQ-C1.7) — resolved this session |

Open questions: none — all resolved to decisions or accepted risks.

Signed off: 2026-07-13

### Execution research — Task 4 (2026-10-11)

Appended by `/execute-task`; no row above is changed.

| # | Finding | Tradeoff / handling |
| --- | --- | --- |
| R9 | The product-strategy card's "worked example" is operator-side research material not reachable from a worker; the card was re-authored from primary sources re-verified on 2026-10-11 (Christensen et al. HBR 2016, Dunford 2019, Moore 3rd ed. 2014, Rumelt 2011/2022, Cagan SVPG 2017, Bland & Osterwalder 2020, Amplitude 2019, NN/g 2024 on synthetic users) | Dunford and Rumelt were confirmed only through publisher and secondary material; the card's `## Sources` says so per entry, and the operator can diff it against the worked example at review |
| R10 | Card storage minted a home: `cards/<id>.md` in core, `cards/` / `cards.local/` beside each overlay layer's `catalogs/`. A card is class 1 (framework config) in `doctrine/storage-classes.md`'s terms, layered on the overlay chain, so no class is new; the nearest existing homes within class 1: `doctrine/` (rule docs, whole-doc shadow, index bijection; a card is data, not a rule) and `config/` catalogs (the constrained reader takes single-line scalars only; a card is a multi-section document) | The `discipline-cards` catalog stays the merge seam (append/union, supersede-by-id) and carries only id and display name; `scripts/resolve-card.sh` maps an id to the supplying layer's card with charset validation and canonicalize-then-contain, so an overlay card symlinked out of its layer root is refused |
| R11 | The linter's frame-anchor check (a mandate question must name the frame or the venture) and its identity-phrase list are lexical floors, not quality judgments | Stated as deliberate non-enforcement in the linter header and as the recipe's review and styling steps; a generic question rephrased to mention the frame passes the lint and is the recipe reviewer's to catch |

### Execution findings: Task 12 (2026-10-12)

| # | Finding | Disposition |
| --- | --- | --- |
| T12-F1 | Research and security (untrusted bundle text into HTML). The OWASP XSS Prevention Cheat Sheet (current) asks for entity-encoding `&`, `<`, `>`, `"` and `'` in element bodies and quoted attributes, and says no encoding makes a `<script>`, `<style>`, comment, or tag/attribute-name context safe. Depth: OWASP plus the in-repo precedent (`spec-assemble.sh`); the change is low-stake and one revert from undone. | The renderer prints bundle text only into element bodies; attribute values and class names come from closed sets, and no page carries a script. The two inline forms it renders (code spans, bold) add fixed tags around text that is already escaped. The escaper moved to `scripts/html-escape.sh`, which `spec-assemble.sh` now shares. `fleet-dashboard.sh` keeps its byte-equivalent copy, because its tests sandbox a fixed subset of scripts; consolidating it is left to whoever next touches that renderer. |
| T12-F2 | Decision (config / data-storage, low stake, reversible; D-9 leaves the knob's home open). The auto-republish knob and the record of a confirmed first publish could live in a tracked file or a machine-local one. | Machine-local `.planwright-publish.local`, gitignored by the scaffold and read as data, never sourced. A tracked knob could be flipped by any commit, a stakeholder's web-UI edit included (the REQ-G1.5 channel), and that would switch on off-machine publishing that nobody confirmed (REQ-G1.9). Consequence: the knob is per machine as well as per venture, so a second machine starts at off and offers the first publish again. |
| T12-F3 | REQ-G1.3 asks for audience-selectable modes, but only the dashboard was regenerated on commit, so a committed pitch page would go stale. | With no `--mode`, the renderer writes both pages, and the scaffolded pre-commit step screens and stages each one. It acts only on a page the render actually produced, so a venture hook running an older planwright, which writes only the dashboard, does not refuse every commit. |
| T12-F4 | The publish helper decides and never publishes. The Artifact publish itself belongs to the `/inception` skill, which does not exist yet, so REQ-G1.9's `[manual]` dogfood cannot run until it does. | The contract the skill must follow is in the helper's header: run `offer`, ask the operator whenever the answer is `offer`, then run `record --confirmed` after a confirmed publish. The owners are the skill tasks and the Task 17 dogfood. |
| T12-F5 | Portability. An awk `match()` inside a called function resets `RSTART`/`RLENGTH`, and under mawk a loop that advanced on the reset values hung. | The match position is now copied before the nested call. The output was verified byte-identical under mawk and busybox awk. BSD awk was not available locally; CI is the remaining check. |
| T12-F6 | Convergence review (2026-10-13) found five issues in hard-disqualifier zones, held for operator direction. (1) Escaping hid quoted credentials from the screen. (2) Publish state in the work tree could be planted by a commit, and concurrent writes could lose an update. (3) Symlinked `exports/` or bundle files were followed. (4) The page was screened, then a different page could be staged or published. (5) Publish bookkeeping gaps. | The operator ruled to apply all five. Fixes: (1) the bundle files are screened together with the pages; (2) the state moved to the clone's git directory (`.git/planwright-publish.local`, which supersedes T12-F2's gitignored work-tree file) behind a mkdir lock; (3) symlinks are refused; (4) pages are rendered to private files and the screened bytes are what is staged or offered; (5) a recorded artifact id is kept, a republish needs an id, and an unreadable state is refused. Each fix is its own sign-off commit with a test that failed before the fix. |
| T12-F7 | cubic review on PR #670 (2026-10-13). The operator ruled on the cubic findings held in zones and on the CI suite-time budget, which every run passes on tests but whose suite total swings with the runner (540–800s against 780s, on identical test code). | C1, C2, C4, C6 and C8 were applied as ruled. F1 took option (a): `exports/` is re-checked for a symbolic link immediately before each final write, which narrows the window without closing it. The budget is handled outside this PR: PR #674 raises `suite_total_seconds`, and #670 leaves the budget unchanged and re-runs CI once #674 merges. The publish test was cut from 16.3s to 11.0s on CI through a read-only `status` subcommand. |

### Execution research — Task 7 (2026-10-11)

| # | Risk | Mitigation / early signal |
| --- | --- | --- |
| R12 | Ephemeral-environment detection rests on a platform claim: Claude Code's env-var reference documents `CLAUDE_CODE_REMOTE` as set to `true` in a cloud session (source: code.claude.com/docs/en/env-vars, read 2026-10-11). Other ephemeral hosts (Cowork, third-party sandboxes) set nothing the helper reads. | The helper reads the documented variable and takes `PLANWRIGHT_INCEPTION_EPHEMERAL=1\|0` as the operator's override either way; Task 14's detection and build-time re-verification own the wider host set (R5). Early signal: a dogfood run on a cloud session that reports the local arm as durable. |

### Execution research — Task 5 (2026-10-18)

Appended by `/execute-task`; no row above is changed.

| # | Finding | Tradeoff / handling |
| --- | --- | --- |
| R13 | As with R9, the per-discipline research distillations are operator-side material a worker cannot reach. The six cards were authored from primary sources re-verified on 2026-10-18 by web search and, where reachable, the source page itself. Research depth, declared per `proportionality`: each named source checked for title, author, venue, year, current edition and link, plus a spot-check of the specific claim each misuse caveat rests on; full texts of books and paywalled articles were not read. | Each card's `## Sources` says per entry when a source was confirmed only through publisher listings or secondary material (Ramanujam & Tacke, Mohammed, Goold & Campbell, Rogers & Blenko, Nygard among them). The operator can diff the cards against the distillations at review. |
| R14 | Choices the spec leaves open, all low-stake and one header edit from undone: card ids `pricing-packaging`, `domain-knowledge-engineering`, `org-design`, `intellectual-property`, `ai-agent-architecture`, `software-engineering`; domain and knowledge engineering defaulted `structure-only` (D-4 places the other six; correctness there belongs to a named domain authority, as the `knowledge-engineering` decision domain says); rot `fast` for IP and AI architecture (the task's high-rot flag), `medium` for pricing and software engineering, `slow` for domain and org design; RAPID `R, I` for the two `agent-senior` cards and `I` elsewhere; only the IP card benched, with pull-in triggers, since its default tier makes it a briefing seat a frame calls on when it touches licences, names or generated assets. | The test pins only what the spec decides (the seven ids shipping, D-4's six tiers, fast rot on IP and AI architecture). The rest is reviewable in each card's header. |
| R15 | Fast-rot facts current at authoring: *Thaler v. Perlmutter* certiorari was denied on 2026-03-02; the Copyright Office's Part 3 training report is still a pre-publication version; MCP's 2026-07-28 revision replaced the stateful session handshake; OWASP's LLM Top 10 and NIST AI 600-1 have no newer edition. | The IP and AI architecture cards cite these with their dates and carry `Rot-rate: fast`, so the format doc's staleness rule (re-verify before each venture that relies on the card) applies; the portfolio view (Task 8) is where staleness surfaces. |

### Execution findings: Task 9 (2026-10-18)

| # | Finding | Disposition |
| --- | --- | --- |
| T9-F1 | Decision (dependency adoption, low stake, reversible). REQ-P1.6 asks seats to vary model where the backend advertises it. The harness agent launch takes a model per seat, but `scripts/offload-dispatch.sh`, the shipped tmux and print launch, applies the one configured `offload` tier to every launch, so seats on those rungs cannot differ even though the backend could carry a model. | The roster honours per-seat models on the `subagent` rung only and reports the lost decorrelation as a degradation everywhere else. A per-launch model request on the dispatch primitive is recorded as an observation rather than added here, since it touches the model-allocation audit trail. |
| T9-F2 | Decision (data storage, low stake, reversible). A recorded fan-out needs a home in the venture so its output can be cited at the `synthetic` grade. | `fanout/<date>-<n>/` beside the bundle, which the format already admits as non-bundle content: the final table, the challenge, the roster, and each seat artifact. The orchestrator's label map is never recorded, and the run directory lives outside the venture until then. |
| T9-F3 | REQ-P1.7 names a Gate 2 `kill` outcome without saying what it kills. | Read as discarding that fan-out's output with nothing recorded or filed; ending the venture stays the gate's (D-14). |
| T9-F4 | Dry runs on 2026-10-18 against the inception fixture venture. Subagent rung: three seats on one card at three models, per seat 31k to 42k tokens, synthesis 48k, challenge 31k, amendment 54k; the record validates clean and Gate 2 yields 18 typed choices. Tmux rung: three seats delivering to files; the first synthesis failed the table check (prose inside the Outliers cell) and passed once re-asked with its findings. | The Gate 1 cost figures are calibrated to these runs. Real seat output also showed a tier written as `human-authority.` with a full stop, which the artifact check now accepts. The gates themselves were not put to an operator in these unattended runs; the skill text places both in the main conversation, and the Task 17 dogfood covers the attended half. |
| T9-F5 | Security pass (untrusted input: seat and bundle text flowing into prompts, files, and the terminal; path handling). | C0 controls, DEL, and the UTF-8 encodings of the C1 controls are stripped from seat and bundle text, before redaction where it is redacted; raw 0x80-0x9F bytes are kept, being the continuation bytes of ordinary UTF-8 text. Tabs inside parsed fields are refused or replaced. Every write target is a fixed file in the run directory or the venture, never a caller-chosen path. Symbolic links at the venture's bundle files and output directories, and at the run files the steps read, are refused; identifiers are charset-checked before use. The residuals held for the operator are T9-F7. |
| T9-F6 | Convergence review (2026-10-18, nine lenses). It found, among others: a failed write that still reported success (the write ran in a pipeline subshell), the register's mode changed to 0600, run state that a partial failure or a re-run outcome left stuck, a seat check that a leading code fence could slip past, synthesis outlier counts left unchecked, a zero-seat waiver left standing after staffing changed, and seat powers not tied to the card's escalation contract. | All applied on the branch, each with a test covering it; two are behaviour choices left for operator sign-off (PS-1, the blind frame withholding card ids and redaction keeping a bare discipline name; PS-2, the placement below). The frame is now snapshotted into the run at the roster; re-run-seat and pull-bench start a new run (`carry` copies the kept seats); the synthesis and the amendment each get one `--retry`; the challenge runs once; Gate 2 also lists the table's tensions and open questions; the fan-out moved to the close of Phase 4, so the frame carries the reframed problem (PS-2, pending sign-off). The coverage-risk ergonomics the 2026-07-22 observation asked Task 9 to confirm: the standard A-entry form holds, its short names and the supersession rule doing what a dedicated variant would. |
| T9-F7 | Held for the operator. Four convergence findings fall in hard-disqualifier zones (sandbox boundaries and secrets), and one is contract drift. | (1) A session that delivers by file writes into the run directory, so it is told the path of the directory holding the label map and its sibling seats' artifacts. (2) Embedded seat, synthesis, and challenge text can imitate the prompt's own headings. (3) `record` copies a run file through a symbolic link into the committed venture. (4) The frame snapshot reads `exports/frame.md` through a symbolic link into every prompt. (5) D-7 says tmux seats get a per-seat model and effort; the shipped tmux launch applies one tier to every launch, and the subagent seat launch sets its model with no allocation-ledger row. Recommended fixes and options are in the PR. |
| T9-F8 | Operator direction, 2026-10-18, on T9-F7. | (1) to (4) applied, each with a test that failed first: a file-delivering session writes into its own empty drop directory outside the run and `collect` moves the document in; embedded text sits in a marked data block, every heading demoted, a setext underline escaped, a fence it leaves open closed, and a forged block end neutralized; `record` refuses a linked run file and copies with `cp -P`; `frame` and `roster` refuse a linked `exports/frame.md`. (5) takes option (c): ship with the per-seat-model loss reported at Gate 1, the launcher change left to its own work (the T9-F1 observation). |
| T9-F9 | Convergence review, iteration 2 (2026-10-19, nine lenses), over the whole branch with the T9-F8 fixes. It found that the open-fence repair misread fences longer than three characters or carrying an info string, that a retry prompt carried the failed answer's text outside its data block, that a failing seat could no longer be re-run once delivery went through a drop, and that a requested model was recorded on rungs that cannot set one. | All applied, each with a test. Embedded documents now escape every fence line and every `<` instead of tracking fences, and the frame and a retry's findings are data blocks too; `brief --retry` re-runs a failing seat once; `collect` answers an already-collected document with exit 0; a drop is recorded only once its prompt is out; the synthesis is asked for once; `attribute` waits for the amendment once a challenge ran; `carry` refuses runs over different frames; an interrupted `record` is finished rather than repeated, under the bundle lock; a rung that cannot set a per-seat model records none; the in-session rung reports that its synthesis is not blind. The record set T9-F2 names now also holds the frame and the degradations. |
| T9-F10 | Tmux-rung dry run repeated on 2026-10-19 against the shipped delivery path, since T9-F4's ran before drops replaced writes into the run. Three seats, then the synthesis, challenge, and amendment, each launched through `scripts/offload-dispatch.sh dispatch tmux` from a brief file outside the run, each delivering into its own drop and moved in by `collect`. | Every brief named no run path; all three seats and each persona-free answer passed their checks first time; every drop directory was retired after collection; Gate 2 yielded 19 typed choices and 19 forks; the record validates clean. Convergence closed after nine review iterations: T9-F6 is the first and T9-F9 the second; iterations 3 to 9 each reviewed only the previous round's fixes, found progressively smaller defects in them (all applied with tests), and the ninth found none. Their record is in the PR's audit block. |

### Execution research — Task 14 (2026-10-25)

Research depth, declared per `proportionality`: official documentation first (Claude Code's env-var, memory and cloud-session pages; Cowork's architecture overview on the Claude help centre; Notion's Markdown content guide), each read on 2026-10-25; community posts only as leads. No Cowork install was reachable, so nothing here is observed Cowork behaviour.

| # | Finding | Disposition |
| --- | --- | --- |
| T14-R1 | Cowork documents no environment variable a session can read: the env-var reference lists `CLAUDE_CODE_REMOTE` for cloud sessions and nothing for Cowork, and the architecture overview names device-level admin keys only. Detecting Cowork from a heuristic (a mount path, a VM marker) would rest on undocumented internals. | Detection reads only documented signals plus the operator's `PLANWRIGHT_INCEPTION_HOST=cowork\|cloud\|local`; an unrecognized value is warned about and ignored. The platform-claims register (PC-2) carries the gap with a short re-verify window, and the Cowork validation record asks the first real run to look for a signal. |
| T14-R2 | Cowork runs cloud sessions by default in a sandbox destroyed at session end, local sessions in a Linux VM over connected folders, and filters egress through an allowlist (Enterprise defaulting to none). | A Cowork host defaults to ephemeral (its local arm session-only) unless `PLANWRIGHT_INCEPTION_EPHEMERAL=0` says the folder is a connected one; the egress limit is a `caveat` line at detect, create and handoff, and the sync protocol tells Cowork's agent to keep a blocked push as a local commit and say so. |
| T14-R3 | Claude Code's memory docs define `@path` imports in `CLAUDE.md`, relative to the importing file, and name Cowork sessions among those loading memory files; which other instructions file Cowork reads in a folder is undocumented. | The protocol ships as `sync-protocol.md` with a `CLAUDE.md` importing it (D-11's hedge). An operator's existing `CLAUDE.md` gains the import line once and is never replaced, `--force` included; a linked one is refused and said. |
| T14-R4 | Decision (low stake, reversible): a protected change Cowork's agent proposes instead of making needs a home. | `proposals/` beside the bundle, a dated file per proposal, committed like any edit; the validator does not read it, so it cannot break the bundle. |
| T14-R5 | Decision (low stake, reversible): "build-time re-verification" for the fast-rotting claims. A gate that fails on a date would turn every branch red on a calendar. | `docs/platform-claims.md` records each claim with source and dates; `scripts/check-platform-claims.sh` fails the gate only on a malformed register and lists due claims, and its `--strict` form, a step in the release checklist, fails on a due claim. |
| T14-R6 | The Done-when's real-Cowork validation run could not be performed by the unattended worker (Linux host, no Claude desktop app). | Logged as blocked in `docs/inception-cowork-validation.md`, with the procedure the operator runs; the task's manual half stays open until that entry records a run. |

## 8. Sign-off

**Mode / scope:** first activation, resumed at §3; full-bundle walkthrough; the consolidated
SOTA-fold (~60 edits) applied in place, then a full-bundle sign-off lens pass with its findings
applied (~40 further edits).

**Lens review pass.** Parallel Discovery-Rigor fan-out — five read-only lens sub-agents (cross-file
consistency, coverage completeness, claims/data-hygiene, failure-modes/structure, altitude/scope) —
plus an independent gemini panel pass (different model family). The gemini pass caught three
logical contradictions the native fan-out missed: anonymized-synthesis attribution (impossible for
a blind writer to re-attach), persona-free-challenger-vs-"declares-standing", and "desirability"
not being one of the four risk tags. All three were resolved (orchestrator-held seat↔label map;
independence moved to the card; desirability = value + usability risk).

Lens-coverage table:

| Lens | Findings | Disposition |
| --- | --- | --- |
| Correctness / logic / edge cases | 1 | Applied — atomic-write lost-update reworded to accept scan-rebuild recovery |
| Security / data-hygiene | 0 | Clean — no secrets, hostnames, or sensitive detail introduced |
| Error handling / failure modes | 4 | Applied — regen stage-and-warn; model-degrade → REQ-H1.5; version-gate exit; Cowork advisory clarified |
| Performance | n/a | Multi-agent cost via Gate-1 disclosure + bench; no new hot path |
| Concurrency / state | 1 | Applied — registry lost-update (same root as correctness) |
| Naming / readability / structure | 1 | Applied — D-2 "Forward log" block folded inline |
| Documentation | 2 | Applied — Sources kickoff-brief entry; redundant Task-1 citation dropped |
| Tests / verification | 4 | Applied — P1.5 independence → card-lint, C1.7 additive check, P1.6 sharpened, stance-axis parse |
| Cross-file consistency | 6 | Applied — REQ-E1.5, D-12 gating, REQ-A1.9 → D-9 cite, C1.7 reader scope, D-13 caps, Task-3 cite |
| Claims / evidence honesty | 6 | 5 applied (Ringelmann / Savoia / NIST / Notion / Coda hedges); 1 pre-existing (medical stat) left out of scope |
| Scope / altitude (kickoff) | 6 | Applied — P1.6 softened to SHOULD; Task 3 & 13 effort bumped; altitude D-20 added; Task-17 sequencing noted |

**Altitude check (REQ-H1.3):** bundle-locally, the pinned seed claim ("work one level of abstraction
higher") is a product/pipeline-scope signal, borderline against the autopilot-reflex doctrine axis;
read as correctly untriggered, but the lens pass added D-20 (altitude record, cited from the Goal)
as cheap insurance, and the decomposition already leads doctrine-first.

**Findings dispositioned:** every confirmed finding applied as a spec edit except Cl3
(medical-warning statistic) and F5 (secret-screen on-hit), both pre-existing and left out of scope,
and F6 (Cowork stale-pull) accepted as a v1 minor. No inconsistency halt; no carried open question.

**Validator:** `spec-validate.sh specs/inception` — 0 errors / 0 warnings (re-run post-flip under
errors-block). **markdownlint (`lint:md`):** MD013 is off for specs; markdownlint-cli2 is not
installed locally, so structural markdown lint is deferred to GitHub CI on the head SHA
(degradation noted, per REQ-K1.7).

Class: meaning
Lens-pass: recorded above (this section), findings dispositioned 2026-07-13.
Anchor: `e31b1a646b42273cfc09c9b373be2d1c8bbe9d6b` — computed as
`scripts/spec-anchor.sh specs/inception`

Signed off: 2026-07-13 — first activation; Draft→Ready flip on all four spec files.

## 9. Amendment log

### 2026-07-13 — Delta re-sign-off (panel-pairing iteration 1)

Pre-merge correction of the Ready bundle (REQ-D1.4), four edits from an independent
`/panel-pairing` gemini pass, all operator-approved this session:

- **G15** (expression) — Task 2/12 stub-renderer ownership made explicit ("Task 2 ships a
  dashboard-fields-only stub renderer … Task 12 replaces it").
- **F1** (traceability) — Task 8 gains the REQ-J1.4 citation + a per-venture in-session status-view
  deliverable (REQ-J1.4 was orphaned from all task citations).
- **F2** (traceability) — Task 11 gains the REQ-J1.6 citation + graduation-never-auto-chains
  wording (REQ-J1.6 was orphaned).
- **G8** (meaning) — REQ-A1.6 pins the registry rebuild to fire automatically on read-time
  detection of a torn / missing / unparseable registry (operator chose auto-on-read over manual /
  accept-as-is), completing the R7 self-heal decision.

Class: meaning (G8 adds behavior; F1/F2/G15 are traceability / expression).
Lens-pass: independent `/panel-pairing` gemini pass (iteration 1) — 7 findings dropped as not-real
(validated false positives / hallucinations), 6 clarity nits skipped by operator, 4 applied;
validation green (spec-validate 0/0, lint:md, check:links 227 resolve, check:ledger PASS).
Anchor: `139c46769786e15661b7bcc6f4b8ff57586897ba` — computed as
`scripts/spec-anchor.sh specs/inception`

Signed off: 2026-07-13 — delta re-sign-off; no status change (stays Ready).

### 2026-07-15 — Expression-only self-re-anchor (format-version 2 migration)

Machine-written entry per REQ-F1.10's expression-only lane, recorded by
`scripts/migrate-format-version.sh` (invariant-tasks D-10, REQ-D1.2).

**Trigger:** the one-shot v1→v2 migration converted this bundle to
format-version 2: placement sections collapsed into `## Tasks`, state
annotation bullets stripped, any parked task blocks converted to reference
bullets, the stored header restricted to the human-gated set, the
`**Execution:**` pointer line added, and `Format-version:` bumped on all
four files. Task definition lines are byte-for-byte unchanged (the
canonical `tasks.md` extraction digest was verified equal before
writing), so no requirement, design decision, task definition, or test
semantics changed — the required re-anchor rides the migration as
expression-only (REQ-A3.3, REQ-D1.2).

**Cites the changelog line:** the 2026-07-15 `## Changelog` entry in
`requirements.md` ("Migrated to format-version 2").

Class: expression-only
Anchor: `7cecf3402f55ce07c90bcafaf646a3c1ba4182f9` — computed as
`scripts/spec-anchor.sh specs/inception`

### Re-anchor — anchor-scope exclusion sweep (2026-08-24)

Machine-written entry per the meta-spec's expression-only lane
(`doctrine/spec-format.md`, *Writers*), recorded by the coordinated sweep
that lands with the hash-scope change (anchor-integrity D-3, REQ-A1.4).

**Why the anchor moved:** the hash scope changed, not this bundle's
content. The per-file digests for `requirements.md`, `design.md`, and
`test-spec.md` now drop the header-block `**Status:**` line, so every
bundle carrying one recomputes to a new value. Verified by isolation:
recomputing under the amended semantics over this bundle as it stood at the
prior entry's commit (`1c7d620`) yields the same hash recorded below, so no
anchored byte has changed since that entry was written.

**Cites the changelog line:** the 2026-07-26 `## Changelog` entry in
`doctrine/spec-format.md` ("Anchor-scope exclusion"), the doctrine half of
the change this entry re-anchors against.

Class: expression-only
Anchor: `46942b430955ebb3ce122764f7d61e1fc3e63aa4` — computed as
`scripts/spec-anchor.sh specs/inception`

### Execution findings: Task 10 (2026-10-18)

Appended by `/execute-task`; no row above is changed.

| # | Finding | Disposition |
| --- | --- | --- |
| T10-F1 | Decision (data-storage, low stake, reversible). The format names `T-<n> findings` as the citation but leaves the findings document's home open. | `findings/T-<n>.md` beside the bundle: outside the five-file membership, so the validator ignores it, and one file per task keeps the per-commit check a path test. Owned by `doctrine/venture-task.md`. |
| T10-F2 | The Done-when asks for findings plus register update in one change, while a dispatched worker's output has to survive until the operator reviews it. Leaving findings uncommitted would let any other save sweep them into an unrelated commit. | Two commits: delivery commits the findings with the task at `delivered` and touches no register; acceptance commits the register updates, the task flip, and the acceptance record appended to the findings, together or not at all. `venture-task.sh check` flags an acceptance without its findings or its updates, a register citing unaccepted findings, and findings committed for a task left planned. This reads REQ-D1.3's "completing a task" and the Done-when's "one change" as the acceptance commit, which carries the findings file (its acceptance record), the register updates, and the task's completion; the earlier delivery commit is not a completion. Open for the operator to confirm at PR review: if the requirement means the findings' first landing too, it needs a `/spec-kickoff` delta, not a code change here. |
| T10-F3 | `skills/execute-task/SKILL.md` sat one word above its declared-exception margin, so the venture-task route had to be funded in-file. | The hook (a manifest line and one sentence) was paid for by deduplicating two citations the Invariants section already carries. The new point-of-use doc drops the `/execute-task` closure below its restoration target (floor intact); recorded as a declared exception in `config/instruction-budget-exemptions.txt`. |
| T10-F4 | The external-interaction ban's settings half: `venture-task.sh worker-settings` prints a deny-list for the common outward channels, but no backend launch in the seam takes a settings file today. | The doctrine states the deny-list as a floor and the ban as holding regardless; wiring a settings pass-through into the launch path is recorded as an observation, not done here. |
