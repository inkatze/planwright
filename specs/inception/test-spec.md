# Inception — Test Spec

**Status:** Ready
**Last reviewed:** 2026-07-13
**Format-version:** 1

Coverage mix: `[test]` entries run under `mise run check` / `mise run test` via the shell-test
harness and fixture suites (Tasks 2, 8, 9–13); `[manual]` entries are exercised through the
continuous dogfood task (Task 17) and the Cowork validation (Task 14); `[design-level]` entries
are doctrine or skill text whose existence and coverage is the verification; `[Gherkin]` entries
are scripted state/trigger/outcome scenarios inside the dogfood runs.

## REQ-A — Venture identity & home

### REQ-A1.1 — identifier derivation and validation [test]

Fixture suite: valid ids, invalid charset, overlength, non-conforming names yielding proposed
variants. Anchored-pattern check with `LC_ALL=C`.

### REQ-A1.2 — one venture per repo [design-level + manual]

The inception-format doctrine states the repo granularity; dogfood confirms graduated specs can
live in the venture repo.

### REQ-A1.3 — ventures_root resolution [test]

Config-layer fixtures: default `~/ventures`, local override wins, malformed value degrades with
warning.

### REQ-A1.4 — ask-once home selection [manual + Gherkin]

Scripted scenario: fresh idea, no repo; exactly one home question; local-only arm pushes nothing
off-machine.

### REQ-A1.5 — ephemeral-environment arm [test]

Env-stub fixtures: ephemeral detection presents local-only as session-only/unavailable.

### REQ-A1.6 — venture registry [test]

Registry helper round-trip: create, read, update status, attention flags. Rebuild fixture: a
`ventures_root` scan recovers fixture ventures with identifiers re-validated; hostile directory
names rejected. Concurrency fixture: interleaved writes leave the registry parseable (atomic
write-temp-then-rename); a simulated clobbered or corrupt registry is recovered by the
`ventures_root` scan-rebuild.

### REQ-A1.7 — cross-venture overlap scan [manual + test]

Dogfood: a second overlapping idea surfaces the extend-vs-new selector; no silent fold. Collision
fixture: creation targeting an existing unregistered directory offers adopt-vs-rename and never
overwrites.

### REQ-A1.8 — identifier re-validation at consumption [test]

Fixtures: hostile registry and seed identifiers (traversal, charset) rejected at consumption.

### REQ-A1.9 — hygiene scaffold [test]

Scaffold helper emits `.gitignore` and screening wiring; remote-rung fixture includes the
secret-scan guard; local-only rung omits CI pieces but keeps the pre-commit export-regeneration
step.

## REQ-B — The elicitation flow

### REQ-B1.1 — interaction-style compliance [design-level]

The skill text shows the indicator, selectors, summaries, and small-bite phasing, citing the
interaction-style doctrine.

### REQ-B1.2 — seed intake [manual]

Dogfood: a pitch document seeds the run; questions already answered by the seed are not re-asked.

### REQ-B1.3 — discipline-catalog walk [manual + design-level]

Skill text names the walk; dogfood shows touched-but-undecided decisions landing in the map.

### REQ-B1.4 — reframing checkpoint [design-level + manual]

The phase list contains the checkpoint between evidence gathering and brief finalization; dogfood
exercises it.

### REQ-B1.5 — proportionality [manual]

Dogfood on a small venture: skipped areas carry one-line reasons; zero-seat run is possible.

### REQ-B1.6 — visibility-relative hygiene [design-level + manual]

The rule is stated in the skill and inception-format doctrine; dogfood stores a sensitive seed in
a private venture repo and confirms neutralization on anything crossing to planwright artifacts,
and confirms operator confirmation precedes any verbatim storage.

### REQ-B1.7 — resume [Gherkin]

Scenario: elicitation interrupted mid-phase; re-invocation resumes at the recorded position;
later re-entry updates registers and re-runs the gate.

## REQ-C — The inception bundle format

### REQ-C1.1 — bundle file set [test]

Validator fixture: complete bundle passes; each missing file is a finding.

### REQ-C1.2 — brief fields [test + manual]

Validator checks section presence (prompts may be skipped-with-reason); dogfood judges field
usefulness.

### REQ-C1.3 — assumption entry fields [test]

Fixtures: full entry passes; missing threshold, missing evidence grade, missing four-risk tag,
duplicate A-ID each fail; the evidence grade resolves against the named ladder; a synthetic-grade
entry cannot satisfy a Graduate threshold on a value- or usability-tagged (desirability) assumption.

### REQ-C1.4 — decision entry fields [test]

Fixtures: alternatives, owner, deciders, status enum, consequences, feed-forward note enforced
(MADR fields); duplicate IDs rejected.

### REQ-C1.5 — plan task fields and ordering [test]

Fixtures: kind enum, done-when presence, time/cost cap presence, T-ID grammar; ordering rule
verified against a fixture register (lowest-confidence blocking first, single-limiting-constraint
tie-break).

### REQ-C1.6 — lifecycle, kill criteria, decider [test]

Fixtures: status enum incl. Abandoned/On-hold; kill criteria as state-plus-date pairs; decider
present and resolvable against the stakeholder map.

### REQ-C1.7 — stable IDs and format version [test]

Fixtures: ID reuse rejected; supersession pointer accepted; format-version header required; a
bundle with an unsupported `Format-version:` fails closed with a plain-language message (never
silently parsed); a design-level check confirms the inception-format doctrine states the
additive-within-major evolution rule.

### REQ-C1.8 — minimum core [test]

Fixtures: bundle missing any core element fails the gate-readiness check; skipped optional
prompts with reasons pass.

### REQ-C1.9 — sources register [test]

Validator fixture: register present; entries parse.

### REQ-C1.10 — stakeholder map [test]

Fixture: decides/aligned/informed roles parse; gate decider and alignment targets resolve to map
entries.

### REQ-C1.11 — optional track labels [test]

Fixtures: labels parse on all three registers; an unlabeled single-track bundle passes; a
partial-graduation fixture keys on labels; a gate record with per-track outcomes parses.

## REQ-D — Validation task execution

### REQ-D1.1 — venture-task contract [Gherkin]

Scenario: dispatched spike lands a findings commit with no PR; optional PR path available on a
remote-backed fixture.

### REQ-D1.2 — kind-keyed deliverables [test]

Contract table fixtures: each kind maps to its deliverable and acceptance shape; alignment
requires a named stakeholder from the map.

### REQ-D1.3 — atomic register updates [test]

Fixture: task completion commit contains both findings and register flip; a findings-only commit
fails the check.

### REQ-D1.4 — human acceptance [manual]

Dogfood: register updates land only after explicit acceptance.

### REQ-D1.5 — disposable spikes [test]

Fixture: spike outputs under `spikes/`; validator flags spike code referenced from graduated seed
packages.

### REQ-D1.6 — standard dispatch [test + manual]

Backend-contract probe dispatches a fixture venture task on the subagent rung; dogfood runs one
inline.

### REQ-D1.7 — no autonomous external interaction [design-level]

The contract doctrine states the ban; the venture worker settings deny outward channels; no
automated path exists to contact external humans.

## REQ-E — Gates

### REQ-E1.1 — minimum-core evaluation [test]

Gate fixtures: unresolved blocking assumption blocks; waived-with-reason passes; missing metric
or kill criteria blocks; a value- or usability-tagged (desirability) assumption resting only on
synthetic-grade evidence blocks a Graduate outcome.

### REQ-E1.2 — four outcomes [test]

Fixtures: each outcome recordable with rationale and decider; anything else rejected.

### REQ-E1.3 — kill-criteria checking [test]

Stubbed-date fixtures: tripped criterion surfaces the prompt; nothing auto-kills.

### REQ-E1.4 — completeness check [test]

Fixtures: unmapped blocking assumption fails; orphan task fails; complete mapping passes.

### REQ-E1.5 — gate records [test]

Fixture: dated machine-readable record with outcome, decider, evidence cited, thresholds
evaluated, and rationale parses; missing fields flagged.

### REQ-E1.6 — kill/abandon archival [Gherkin]

Scenario: Kill outcome → archive with post-mortem note, registry updated, observation recorded.

## REQ-F — Handoff

### REQ-F1.1 — seed package shape [test]

Fixture: graduated seed carries brief extract, decided forks with alternatives, graded evidence,
open questions, citations.

### REQ-F1.2 — human-chosen destination [manual]

Dogfood: destination selector offered; the skill never invokes `/spec-draft` itself.

### REQ-F1.3 — partial graduation [Gherkin]

Scenario: one track graduates; sibling tracks and the venture stay live.

### REQ-F1.4 — feedback routing back [manual]

Dogfood: a hole found during spec drafting lands as a venture register entry.

## REQ-G — Exports & stakeholder surfaces

### REQ-G1.1 — deterministic renderer with refresh owner [test]

Byte-identical output on repeated runs over a fixture bundle; escaping fixtures (hostile markdown
in registers); regenerate-on-commit wiring verified in a fixture repo.

### REQ-G1.2 — status dashboard [test]

Dashboard section reflects fixture registers: gate readiness, blocking counts, kill dates, open
forks.

### REQ-G1.3 — render modes [test]

Both modes render from one fixture bundle; mode selection honored.

### REQ-G1.4 — offered publish, opt-in auto-republish [manual + test]

Scripted run shows publish as offer-only; knob fixtures: default off, first publish always
confirmed.

### REQ-G1.5 — GitHub path guarded [test]

Stakeholder-commit fixtures: ID mangling, gate-record edits, structure breaks each fail the CI
validator; a clean prose edit passes.

### REQ-G1.6 — one-way-per-cycle seam with triage [test + design-level]

Harvest fixtures produce a triage list; no code path applies an item without an accepted triage
record; the seam contract doc states the cycle.

### REQ-G1.7 — Notion reference adapter [test + manual]

Parser fixtures on canned comment payloads; one full manual cycle against a sandbox workspace
with attributed commits citing comments.

### REQ-G1.8 — Cowork sync-protocol file [test]

Scaffold emits the file; content names the ritual and the untouchable elements.

### REQ-G1.9 — off-machine confirmation [manual]

Dogfood: every export/publish to an off-machine destination asks first; visibility boundary
respected.

## REQ-H — Degradation & environments

### REQ-H1.1 — truth-store ladder [test]

Env stubs (no git, no remote, ephemeral) select the right rung; degraded capabilities named in
output.

### REQ-H1.2 — wrapped vs expert mode [manual]

Dogfood in both modes over one repo: non-engineer path shows no git vocabulary; expert path is
standard git.

### REQ-H1.3 — local-only and remote-later [Gherkin]

Scenario: local-only venture gains a remote later; nothing re-initializes, history preserved.

### REQ-H1.4 — Cowork capability detection [manual]

Task 14's validation run on a real Cowork install; outcome recorded either way.

### REQ-H1.5 — degradation reporting [test]

Output assertions: every degraded run names the degradation at pre-flight and in the handoff.

### REQ-H1.6 — registry-absent degrade [test]

Stub: missing plugin-data dir skips the overlap scan with a notice; run proceeds; an overlap scan
that errors mid-run (corrupt brief, timeout stub) likewise degrades to a notice and proceeds.

## REQ-I — Doctrine & catalog extensions

### REQ-I1.1 — inception-format doctrine [design-level]

The doc exists, indexed, link-checked; validator and renderer cite it as their grammar source.

### REQ-I1.2 — decision-domains additions [test + design-level]

The domains resolve through `resolve-catalog` (overlay fixture with a company discipline merges);
the seam-reuse domain names the core seams.

### REQ-I1.3 — discipline-appropriate lenses [design-level]

The lens-selection rule exists and states artifact-class selection; cited by the rigor doctrine.

### REQ-I1.4 — evidence-quality doctrine [design-level]

The doc defines falsifiability format, thresholds, and grades; `assumptions.md` fixtures cite its
vocabulary (covered by REQ-C1.3 tests).

### REQ-I1.5 — storage-classes rule [design-level]

The rule exists and assigns homes to the three classes; this spec's own layout conforms.

### REQ-I1.6 — capability-vs-style classification [design-level]

Every new knob's options-reference row states its classification; `check-options-reference`
enforces row presence.

## REQ-J — Pipeline & skill integration

### REQ-J1.1 — venture-seed consumption [test + manual]

A graduated fixture seed surfaces in a `/spec-draft` seed-gathering probe with citations
preserved; dogfood performs one real handoff.

### REQ-J1.2 — altitude routing [manual]

A pitch-shaped fixture input triggers the recommendation; declining proceeds as a normal draft.

### REQ-J1.3 — standard dispatch machinery [test]

Covered jointly with REQ-D1.6 (this entry carries the integration assertion: no parallel
orchestration code paths exist).

### REQ-J1.4 — status view [test + manual]

Status renders fixture ventures (gate readiness, blockers, kill dates); dogfood uses it live.

### REQ-J1.5 — bidirectional lineage [test]

Fixture: graduation writes both directions; either missing is a finding.

### REQ-J1.6 — never auto-chain [design-level]

Skill text and worker settings; no code path invokes downstream skills.

### REQ-J1.7 — portfolio listing [test]

No-arg view over a fixture registry: attention flags and catalog-health notes render.

### REQ-J1.8 — telemetry and feedback drop [test]

Write-read round-trip; planwright-side reader neutralizes before anything committed; the interim
re-anchor pointer is present in the doctrine text.

## REQ-P — The discipline-persona layer

### REQ-P1.1 — cards as task-framings [test]

Card lint over all shipped cards: schema fields present; forbidden fields (backstory,
credentials) absent; mandate size within bounds; blind-spots, conflict/deference rules, ordered
framework sequence, named knowledge-sources, the own-discipline independence note, and an optional
stance-axis field present/parse; a generic mandate question (answerable about any product) is
flagged.

### REQ-P1.2 — tier placements [test]

Card lint: default tier and per-activity exceptions present; the out-of-scope line present;
one-way-door items listed as human-authority.

### REQ-P1.3 — independent seats, single synthesis [design-level + manual]

Topology stated in the skill with citations; the fan-out dry runs (Task 9) confirm no inter-seat
channel exists and the synthesis table is mandatory; the synthesis writer's input is confirmed
anonymized and order-shuffled (the orchestrator, not the writer, holds the seat↔label map), with
attribution re-attached only in the final table.

### REQ-P1.4 — single challenge pass [Gherkin]

Scenario: challenge runs once post-synthesis, sees synthesis and frame only; synthesis amends at
most once; the challenge and synthesis steps run persona-free (no card role line in their prompts).

### REQ-P1.5 — escalation sections and forced choices [test + manual]

Template check: every seat artifact ends with the section; escalation triggers are typed (the
four-class taxonomy) and each names the receiving human's power; dogfood confirms human-authority
items arrive as structured gate choices.

### REQ-P1.6 — seat economics [manual]

Gate 1 discloses seats, backend, and estimated cost before spawn; defaults observed in dogfood.

### REQ-P1.7 — main-thread gates [design-level + manual]

Skill text places both gates in the main conversation; fan-out runs confirm seats never prompt
the human.

### REQ-P1.8 — staffing honesty [test]

Fixture: an unstaffed discipline (including no-card-exists) auto-files a register risk; a
zero-seat run collapses to a single "personas waived; N unstaffed" row rather than one per
discipline.

### REQ-P1.9 — convergence-based confidence [manual]

Fan-out outputs reviewed for hypothesis/briefing grammar and convergence marks; no verbalized
self-confidence; convergence marks are annotated by claim type and name outlier seats, never
presented as a probability.

### REQ-P1.10 — overlay-extensible cards [test]

Overlay fixture: a team card resolves through the catalog merge; core cards unaffected.

### REQ-P1.11 — catalog growth epistemics [design-level]

The recipe doctrine exists; parked candidates named in `tasks.md` Deferred with telemetry gates;
the commissioned card (Task 6) carries its demand citation.
