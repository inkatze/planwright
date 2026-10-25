# Seed brief for `spec-currency` (a follow-on bundle of `mission-control`)

Suggested invocation (fresh Claude session in the planwright repo, this file is the seed):

    /spec-draft spec-currency

Read this whole brief before eliciting. Run fold-detection against `anchor-integrity` (anchor
recompute and drift; the `spec-format` doctrine holds the freshness rules), `kickoff-lifecycle` (owner of delta re-walkthroughs) and
`prose-disposition` (owner of spec-versus-implementation divergence) before assuming a new
bundle; this brief does not prejudge extend-vs-spin-new.

## Why this is a follow-on, not part of `mission-control`

The invocation seed's pinned claim is that "specs are a consolidation of decisions from many
sources, kept current, never the authority". `mission-control` ships the core that holds those
decisions (the rule store, the decisions log, the state-source map) but scoped the duty that keeps
specs current against outside sources out as a follow-on: it is independently ownable and forces
decisions orthogonal to the core (mission-control D-1, D-22, D-27).

## The shape (from the mission-control invocation seed and kickoff)

A **duty** that notices when a decision made outside a spec (in a chat thread, a meeting, a ticket,
a document, a tower session, an operator aside) bears on a Ready or Active bundle, and prepares the
consolidation: which REQ or D-ID it touches, whether the change is expression-only or
meaning-class, and the amendment or delta re-walkthrough it calls for. It never edits a spec itself
(mission-control REQ-A1.3, D-23) and never signs off (REQ-I1.5); a meaning-class change reaches the
operator as a prepared item, an expression-only one as a launched, relayed session's proposal.

A second, inward half: noticing a signed-off bundle whose anchor no longer recomputes, or whose
text describes behaviour the code no longer has, and queueing the re-anchor or amendment.

## Seams it consumes from `mission-control`

- **The duty catalog** (D-3, REQ-C1.1 to REQ-C1.6), starting in `shadow` (D-15).
- **The source map** (REQ-H1.4, D-8): the `decisions` fact class names where decisions live and in
  which mode; a `cited` source is only links and the operator's statements, never polled. Reading
  a tracker or document store depends on the `state-source-adapters` follow-on.
- **The rule store and decisions log** (D-5, D-9, REQ-B1.1, REQ-B1.2): an operator-stated decision
  entered directly, with its `subject`, is the duty's input.
- **The launcher** (D-10): a relayed kickoff or amendment session starts through it (REQ-I1.5).
- **The queue** (D-7, REQ-F1.7, REQ-F1.14): consolidation items carry their context and a prepared
  packet.

## Observations left live for this bundle

- obs:fea82b1c: two operator allocation decisions never reached a spec, one of them existing only
  as a comment in a gitignored machine-local overlay (also cited by `tower-comms` and
  `universal-binary`; still live).
- obs:1ea469f5: Done bundles whose kickoff anchors no longer recompute after post-sign-off edits;
  nothing flags the drift.
- obs:2e04639d: a research seed a spec cites as its source of record kept its datasets only in a
  scratchpad that was gone when the first task needed them.

No live fragment yet records a decision taken in an external system (chat, meeting, ticket) that
failed to reach a spec; that evidence is the mission-control hub record (its Sources), neutralized.

## Open questions for the drafter

1. Which external sources the duty reads in its first version, given `cited` sources are never
   polled until an adapter exists.
2. How a detected decision is matched to a REQ or D-ID, and what the duty does when the match is
   ambiguous (decide-or-queue, mission-control D-13).
3. Whether the inward half (stale anchors, code-versus-spec drift) belongs here or with
   `prose-disposition` and the anchor sweep.
