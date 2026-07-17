# Anchor integrity — Requirements

**Status:** Ready
**Last reviewed:** 2026-07-17
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

The content anchor is the execution freshness gate's ground truth: a
recorded hash proving the bundle a worker executes is the bundle the human
signed off. Today that ground truth is compromised on both sides of the
contract. On the write side, the v1 anchor whole-file hashes
`requirements.md`, `design.md`, and `test-spec.md`, so the header
`**Status:**` line rides into the hash — an exclusion planwright's own
sync-hook caveat records as not yet performed — and every lifecycle Status
write (the stored
Draft→Ready flip, the derived Ready→Active flip) stales a v1 bundle's
anchor mid-execution; this fired live on invariant-tasks Task 3, and PR #187
committed the flip with no re-anchor. On the process side, the skills that
legally edit a signed bundle have no sanctioned re-anchor path and no
stale-anchor detection, so the ritual gets skipped (it recurred on
customization-overlay and output-hygiene, once shipping a stale anchor
inside a squash), and no commit-time or CI guard catches the drift before
the next dispatch false-halts. This spec closes both sides: it makes
lifecycle Status writes genuinely anchor-invariant for v1 bundles, gives
every bundle-editing skill a sanctioned re-anchor pathway, adds a mechanical
anchor-freshness guard, hardens authoring guidance against
enumerated-claim rot, and makes the recorded anchor command recomputable in
adopter repos. The deliverable is mixed-altitude by decision D-1: policy as
doctrine amendments, enforcement as mechanism.

## Scope

### In scope

- Excluding the header-block `**Status:**` line from the per-file digests
  of `requirements.md`, `design.md`, and `test-spec.md` (the digest the
  meta-spec's version-1 body defines, inherited by every later format
  version), bounded to the header block, with the anchor tool's
  self-description corrected.
- A coordinated classify-and-route re-anchor sweep over every briefed
  non-Draft, non-terminal in-repo bundle whose latest anchor fails to
  recompute under the amended semantics, plus the documented adopter
  remedy.
- Stating the committed-main reference frame for the v1 gate arm in the
  meta-spec's execution-validity prose.
- Re-anchor pathways for planwright-shipped act-on-findings skills:
  stale-anchor pre-flight detection, the expression-only self-re-anchor
  ritual (dated Changelog entry plus marked anchor entry), and
  meaning-class refusal with routing to `/spec-kickoff`; a terminal
  re-anchor step in `/spec-kickoff` for post-sign-off edits.
- A mechanical anchor-freshness guard: a normative CI check under
  `mise run check` plus a best-effort lefthook pre-commit mirror.
- Authoring guidance preferring decided-rule statements over enumerated
  counts in anchored prose, with an enumeration cross-check at draft and
  kickoff.
- A resolution-path-aware sanctioned anchor-command form recomputable in
  plugin-consuming adopter repos.

### Out of scope

- Extraction-parser internals, fence-awareness, and the shared extraction
  library: `specs/format-grammar` owns them; this spec owns what is hashed
  and when re-anchors happen, and depends on that work rather than
  duplicating it.
- Changes to format-version 2 semantics, or migrating v1 bundles to v2:
  `specs/invariant-tasks` owns the v2 format; v1 bundles stay valid
  indefinitely per the meta-spec, and this spec fixes v1 in place.
- Redesigning the derived Ready↔Active flip or the single-writer reconcile:
  `specs/kickoff-lifecycle` and `specs/orchestration-concurrency` own them;
  this spec only makes the anchor invariant to them.
- Widening meaning-class anchor writership beyond `/spec-kickoff`.
- Gate evaluation semantics beyond the committed-main frame statement.

## REQ-A — Anchor scope (what is hashed)

- **REQ-A1.1** The content anchor's per-file digest for
  `requirements.md`, `design.md`, and `test-spec.md` — defined once in the
  meta-spec's version-1 body and inherited unchanged by every later format
  version, so the exclusion is universal and the tool parses no
  format-version — SHALL exclude the header-block `**Status:**` line, so
  that neither the stored Draft→Ready flip nor the derived Ready↔Active
  flip (nor its header mirrors) changes a bundle's anchor.
  *(Cites: D-2, obs:d8b9eaca, opportunities.md line 188 (Sources).)*
- **REQ-A1.2** The exclusion SHALL be bounded to the header block as the
  meta-spec defines it: a `**Status:**` line appearing in body prose or
  inside a fence remains anchored content. The exclusion SHALL be anchored
  to the single leading header block; a malformed, duplicated, or
  unterminated header block fails closed (non-zero exit, no anchor
  printed) rather than silently hashing the whole file.
  *(Cites: D-2, format-grammar header-block scope (Sources).)*
- **REQ-A1.3** The anchor tool's self-description SHALL match its
  implementation in both directions: no exclusion is documented that the
  code does not perform, and none is performed that the documentation
  does not state.
  *(Cites: D-2, opportunities.md line 188 (Sources).)*
- **REQ-A1.4** The hash-scope change SHALL land with a paired re-anchor
  sweep covering every in-repo briefed, non-Draft, non-terminal bundle
  whose latest recorded anchor fails to recompute under the amended
  semantics — anchors already stale before the change included, and
  entries recorded with the interim whole-file form included (converted
  to a current sanctioned form, since interim hashes still carry the
  Status line). The sweep SHALL classify each bundle's anchored-content
  delta since its recorded entry, diffing from the commit that introduced
  the entry's anchor line (located from the brief's history): a
  lifecycle-only delta (one confined to sanctioned header Status writes
  and other anchor-excluded content) or an expression-only delta receives
  the machine `Class: expression-only` entry; a meaning-class delta — and
  any delta the classifier cannot resolve, which SHALL default to
  meaning-class — routes that bundle to the re-review ritual its status
  admits (`/spec-kickoff` delta re-walkthrough for Ready or Active; the
  meta-spec reopen cycle for Done), with the bundle parked and its gate
  left failing closed rather than blocking the sweep from landing.
  Parking is visible and carved out: the sweep writes a live
  `anchor re-review pending` bullet into the parked bundle's `tasks.md`
  `## Awaiting input` section; the REQ-D guard and the landing proof
  treat a bundle carrying that marker as known-parked (a notice, not an
  error); the dispatch freshness gate still fails closed on it; and the
  re-review's sign-off removes the bullet.
  Classifications and the landing proof SHALL be re-verified at the sweep
  PR's merge SHA, and a re-run's entries SHALL cite the delta that
  actually moved each anchor rather than unconditionally citing the
  hash-scope amendment — so no unreviewed meaning edit is laundered and
  no freshness gate trips on an unamended bundle.
  *(Cites: D-3, format-grammar REQ-C1.4 (Sources), kickoff §7 risk 1
  (2026-07-17).)*
- **REQ-A1.5** Adopter documentation and the freshness gate's halt
  guidance for pre-change anchors SHALL name the one-time self-re-anchor
  remedy for adopter bundles (any format version) anchored under the
  pre-change scope or with the interim whole-file form, carrying the same
  classification rule as the in-repo sweep: a delta that is not
  lifecycle-only or expression-only routes to the applicable re-review
  ritual instead of the machine entry. The two named homes are the
  adopter docs under `docs/` (exact file decided at execution, cited back
  here) and the meta-spec's execution-validity halt prose.
  *(Cites: D-3, obs:d8b9eaca.)*

## REQ-B — Gate reference frame

- **REQ-B1.1** The meta-spec's execution-validity prose SHALL state the
  committed-main reference frame for the v1 gate arm: both reads are
  taken against a single pinned commit of the main view; when the
  recompute's only divergence from that pinned view within anchored
  content is confined to header `**Status:**` lines carrying sanctioned
  status values, across any subset of the four files (the shape the
  single-writer derived mirror produces — the gate accepts the shape, as
  it cannot attribute a divergence to a writer), the gate compares
  against the pinned committed view; any other divergence halts as
  today.
  *(Cites: D-4, obs:3b56f0e3.)*

## REQ-C — Re-anchor pathways (who re-anchors, when)

- **REQ-C1.1** Every planwright-shipped skill that would edit a signed
  (Ready or Active) spec bundle SHALL run a stale-anchor pre-flight before
  any edit: recompute the anchor with the brief's most recent recorded
  command; a mismatch, an absent or unparseable entry, or a recompute
  failure each surface and block the edit rather than editing on top of
  it.
  *(Cites: D-5, opportunities.md lines 60 and 61 (Sources).)*
- **REQ-C1.2** A planwright-shipped act-on-findings skill applying an
  expression-only edit to a signed bundle SHALL complete the sanctioned
  ritual in the same change: the dated Changelog entry plus the marked
  `Class: expression-only` self-re-anchor entry citing it, with the edit
  and both ritual writes landing in one commit.
  *(Cites: D-5, opportunities.md lines 60, 61, and 64 (Sources).)*
- **REQ-C1.3** A planwright-shipped act-on-findings skill SHALL refuse to
  apply a meaning-class edit to a signed bundle and SHALL route it to
  `/spec-kickoff`; meaning-class anchor writership stays with
  `/spec-kickoff` alone.
  *(Cites: D-5.)*
- **REQ-C1.4** `/spec-kickoff` SHALL recompute and re-record the anchor as
  the final pre-push step of any flow in which anchored content was edited
  after the sign-off record was written, so no stale anchor ships in the
  spec PR or its squash. The terminal recompute covers expression-only
  edits; a meaning-class post-sign-off edit re-enters the sign-off flow
  (delta walk plus lens pass) before any record is written. A failing
  terminal recompute halts the push (degrade per bootstrap
  REQ-K1.6/K1.7), never shipping the prior anchor as if fresh.
  *(Cites: D-5, opportunities.md line 175 (Sources).)*

## REQ-D — Mechanical guards

- **REQ-D1.1** A check wired into `mise run check` SHALL assert, for every
  non-Draft bundle with a kickoff brief, that the brief's most recent
  anchor entry parses, uses a sanctioned command form, and recomputes equal
  against the checked tree; a failure is a merge-gating error, except that
  a bundle whose `tasks.md` `## Awaiting input` section carries a live
  `anchor re-review pending` marker (REQ-A1.4's park) is reported as a
  known-parked notice instead.
  *(Cites: D-6, opportunities.md line 63 (Sources).)*
- **REQ-D1.2** The same guard SHALL flag an edit to anchored content, since
  the baseline ref (the existing check convention: default `origin/main`,
  explicit `--baseline` override), that lacks a dated Changelog entry in
  the edited bundle, covering the out-of-flow edit class. Edits are
  detected via the canonical anchored-content extraction: a change
  confined to excluded content (header Status lines, `tasks.md` state
  annotations or block placement) never flags. When the default baseline
  ref does not resolve, the pairing check degrades to a skip with a
  notice; an explicit `--baseline` that cannot be used stays fatal (the
  validator's convention).
  *(Cites: D-6, opportunities.md lines 63 and 64 (Sources).)*
- **REQ-D1.3** A lefthook pre-commit mirror of the same guard script SHALL
  run best-effort in this repo; the CI form is normative and the mirror is
  convenience.
  *(Cites: D-6.)*
- **REQ-D1.4** The guard SHALL skip, with a notice rather than a failure,
  Draft bundles and bundles in a terminal state (Retired, Superseded). A
  non-Draft, non-terminal bundle without a kickoff brief is an error
  naming the repair remedy (complete or repair the sign-off record per
  the meta-spec's execution-validity rules), never a silent skip — brief
  removal must not disable the anchor check.
  *(Cites: D-6, kickoff sign-off lens pass (2026-07-17).)*
- **REQ-D1.5** The guard and every skill pre-flight SHALL treat a
  recorded anchor command as data: validate it against the sanctioned
  grammar, then recompute by invoking the resolved tool with a parsed,
  containment-checked `<spec-dir>` argument — never by evaluating the
  recorded string. Diagnostics echo parsed content only through the
  canonical sanitizer, and a `--baseline` value is rev-parse-validated
  before subprocess use, per the framework-script security doctrine.
  *(Cites: D-6, kickoff sign-off lens pass (2026-07-17).)*

## REQ-E — Authoring guidance

- **REQ-E1.1** The meta-spec's authoring guidance SHALL direct anchored
  deliverable prose to state decided rules rather than enumerated counts or
  corpus claims whose truth depends on surfaces outside the bundle;
  unavoidable enumerations follow the cite-don't-copy convention or carry
  their own cross-check.
  *(Cites: D-8, opportunities.md lines 78 and 174 (Sources).)*
- **REQ-E1.2** `/spec-draft` and `/spec-kickoff` SHALL cross-check
  enumerations and corpus claims in the bundle against the surfaces they
  enumerate, at drafting and at sign-off respectively.
  *(Cites: D-8, opportunities.md line 78 (Sources).)*

## REQ-F — Portability

- **REQ-F1.1** The sanctioned anchor-command forms SHALL include a
  resolution-path-aware logical form — `spec-anchor.sh <spec-dir>` resolved
  through the documented core root chain — recomputable in plugin-consuming
  adopter repos with no `scripts/` directory; gate consumers SHALL accept
  it, and existing repo-relative entries remain sanctioned. Gate consumers
  SHALL resolve the tool from the checked tree's canonical script where
  present, using the chain only where absent; a sanctioned form that
  resolves to nothing in the current environment halts the gate as
  absent-anchor-class (fail closed), with the halt guidance naming the
  chain.
  *(Cites: D-7, opportunities.md line 47 (Sources).)*

## Changelog

- 2026-07-17 — Initial draft elicited via `/spec-draft`. Fold-detection
  chose a new bundle over extending bootstrap, kickoff-lifecycle, or
  invariant-tasks (all three cited as Sources). Eleven observation seeds
  consumed. Fork decisions from the drafting session are recorded in
  `design.md`'s decision log (their origin notes name the session).
- 2026-07-17 — First-activation kickoff walkthrough edits: universality
  of the Status-line exclusion, terminal-state guard skip, the widened
  classify-and-route sweep scope, execution-safety and degradation
  requirements (REQ-D1.5; REQ-D1.2/D1.4 refinements), gate-frame
  pinning, ritual failure-ordering rules, and alignment fixes from the
  sign-off lens pass (including correcting the seed's "tool contradicts
  its own header" reading). Kickoff fork decisions are recorded in the
  design log and the kickoff brief; this changelog cites rather than
  enumerates them (D-8).

## Sources

- **The drafting mission (2026-07-17 `/spec-draft` invocation)** — scope
  framing across the five concern areas, the confirmed fix shapes, and the
  fold candidates. Pinned altitude claim: the anchor system has "confirmed
  gaps on both the write side (what gets hashed) and the process side (who
  re-anchors, when)" — a framework-contract claim, resolved at D-1.
- **obs:d8b9eaca** — the freshness-gate Status-flip prediction fired live
  during invariant-tasks Task 3 dispatch (2026-07-15); PR #187 then
  committed the Ready→Active flip with no re-anchor, making the mismatch
  durable on main.
- **obs:3b56f0e3** — the committed-main frame resolution used during the
  invariant-tasks Task 2 dispatch, where the gate doctrine's "committed or
  not" and its "what /orchestrate and a merge see" framing diverged for a
  v1 bundle mid-reconcile.
- **opportunities.md line 47 (2026-06-12)** — anchor-command portability:
  the repo-relative form is not recomputable in plugin-consuming adopter
  repos.
- **opportunities.md line 60 (2026-06-16)** — re-anchor gap in the
  panel-family and `/self-review` act-on-findings skills, surfaced on
  customization-overlay.
- **opportunities.md line 61 (2026-06-16)** — the same gap confirmed in the
  copilot-family skills. Pinned altitude claim: the gap is "systemic across
  EVERY skill that edits a spec bundle post-activation" — resolved at D-1.
- **opportunities.md line 63 (2026-06-16)** — the commit-time/CI
  anchor-drift guard candidate, surfaced by out-of-flow commit d04bcb4.
- **opportunities.md line 64 (2026-06-16)** — the same out-of-flow edit
  class also skips the mandatory dated Changelog entry.
- **opportunities.md line 78 (2026-06-17)** — frozen-corpus enumerations
  should be cross-checked at draft/kickoff against the surfaces they
  freeze.
- **opportunities.md line 174 (2026-07-09)** — enumerated-count deliverable
  rot: output-hygiene Task 5's "sole real violation" premise went stale
  when sibling layers grew.
- **opportunities.md line 175 (2026-07-09)** — a stale anchor shipped
  inside PR #129's squash; post-sign-off edits need a terminal re-anchor.
- **opportunities.md line 113 (2026-06-28)** — this repo ships no separate
  pre-commit framework (no `lefthook.yml`, no git-hook installer); the
  REQ-D1.3 mirror is net-new hook infrastructure this spec introduces.
- **opportunities.md line 188 (2026-07-09)** — the anchor tool whole-file
  hashes three of the four files, so the `**Status:**` line rides into the
  anchor. (The seed's "contradicting the tool's own header" reading was
  corrected at kickoff: the header's exclusion claim is tasks.md-scoped
  and accurate; the sync-hook caveat records the header-Status exclusion
  as not yet done.)
- **specs/bootstrap** (Done) — owner of `scripts/spec-anchor.sh` and the
  original freshness-gate design this spec amends.
- **specs/kickoff-lifecycle** (Done) — owner of the sign-off/anchor ritual
  and the derived Ready↔Active flip the anchor must be invariant to.
- **specs/invariant-tasks** (Ready) — owner of format-version 2, which
  removes the stored flip for migrated bundles; this spec closes the v1
  remainder.
- **specs/format-grammar** (Ready) — owner of the shared extraction
  library, fence-awareness, and the header-block scope definition; its
  REQ-C1.4 establishes the paired re-anchor-sweep discipline this spec's
  hash-scope change rides.
- **2026-07-16 accumulator triage** — a ten-agent verification pass against
  v0.14.1 confirming every seed above valid (d8b9eaca and line 175 partial:
  reactive arms exist, named remainders open); session-local verdict
  ledger, not committed.
