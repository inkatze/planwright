# Review desk — Requirements

**Status:** Draft
**Last reviewed:** 2026-11-05
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

An operator asked to review other people's pull requests spends the day
noticing requests, reading diffs, drafting comments and coming back when
the author pushes again. The review desk is a mission-control duty that
does that work on the operator's behalf, all day, without a standing
session: a deterministic watcher reads the forge snapshot mission control
already keeps, and when a pull request in scope is new or its patch has
changed it starts one short-lived reviewer session for that pull request.
The reviewer reads the change through the forge only, never fetching it
into a checkout, and returns a structured review; the desk renders it in
the format the operator configured for that reviewer and repository and
batches finished reviews for the operator one line each, with an
immediate heads-up when a review found a security blocker. Nothing is
posted until the operator says yes to the exact text, and the desk
re-checks the pull request right before it posts. After a post it keeps
going: a new commit triggers a re-review, a dismissed approval is restored
or brought back to the operator, and promises made in replies become
tracked follow-ups.

The review format is configuration, not prose: each reviewer, and each
repository where a team's convention differs, can set the structure, tone,
severity labels, length and what a review includes or leaves out, with a
shipped default that works with no setup. The operator is sending the
format details separately; until then the format's fields and default
values are open questions (D-8), and every other part of the desk proceeds
without them.

The desk also closes one gap on the operator's own pull requests: the
readiness walk today never sees a finding an automated reviewer wrote only
into a review body, so it can call a pull request ready over an unanswered
finding (REQ-H). And for every pull request it tracks, the operator's own
included, the desk shows what its merge still waits on from people (a
required approval, a requested change, a code-owner review) and from whom,
so a pull request waiting on a person is never presented as ready to merge
(REQ-I).

The altitude call is D-1: a mission-control duty built on mission
control's seams (the duty catalog, the launcher, the snapshot, the queue,
the follow-up and undo ledgers), plus one new configuration seam for review
formats with the capability in core and the values in overlays. No new
doctrine: posting a review is a message to a person, already a human gate.

## Scope

### In scope

- The review desk as a mission-control duty: its catalog entry, watcher,
  wake, rules, operator-item kinds, owned files and lifecycle, starting in
  shadow.
- Scope rules as configuration: which pull requests the desk reviews,
  which it skips (already approved by others, restacks with an unchanged
  patch) and which it holds (unanswered automated-reviewer findings).
- The per-pull-request queue and its states: new, held, reviewing,
  awaiting-operator, submitted, re-review, done.
- One on-demand reviewer session per pull request per changed patch,
  admitted against the host and the budget, respecting quiet hours.
- Read-only review material taken from the forge API into a private
  export, treated as untrusted data.
- A pluggable review step with a shipped default reviewer, returning a
  structured review.
- Review formats: per-reviewer and per-repository format profiles as
  configuration with a shipped default, a renderer and a draft check. The
  format fields and default values are open (D-8).
- Batched delivery to the operator, the exact-text yes, the pre-post
  re-check and the post itself, with an undo entry.
- After the post: re-review on a changed patch, dismissed-approval
  handling, promises in replies as follow-ups, and closing a record.
- The queue's states shown in the panel's existing reviews-at-a-glance
  view.
- Automated-reviewer findings written only in a review body, read by the
  readiness walk and by the desk's hold.
- What each tracked pull request's merge waits on from people (a required
  approval, changes requested, a code-owner review), shown at the desk and
  never presented as ready to merge.

### Out of scope

- Posting anything to a person without the operator's yes on its exact
  text and recipient, including a "review started" notice to the author;
  standing exceptions exist only as named configuration (mission-control
  REQ-I1.3).
- Fetching a pull request's head, branch or refs into any checkout,
  worktree or local repository, and executing anything from a pull
  request (its tests, tooling, scripts or configuration).
- The inbound review cadence on the operator's own pull requests
  (requesting automated reviewers, triaging their threads, the convergence
  and post-PR steps): it stays with the execution cadence and the
  operator-level review skills; this bundle adds only the body-finding
  read (REQ-H).
- Counting a review round across a head change: review evidence stays
  bound to the current head, as the readiness floor states (D-2).
- Editing the operator's own review commands that live outside this
  repository; an operator plugs one in through the review step (D-7).
- Merging, and approving on a timer or by default; the one standing
  exception (restoring a dismissed approval, D-11) is off unless the
  operator enables it.
- The format details themselves (fields, default values, the exact
  default layout) until the operator supplies them (D-8).
- Copying company data (pull request content, drafts, the operator's past
  positions) into any committed file.

## REQ-A — The desk duty

- **REQ-A1.1** The review desk SHALL be one entry in mission control's
  duty catalog, naming its triggers, watcher, wake, rules, operator-item
  kinds, owned files and lifecycle, and SHALL arm nothing and cost nothing
  while disabled or `off`.
  *(Cites: D-1, D-3; mission-control REQ-C1.1, REQ-C1.4 (Sources).)*
- **REQ-A1.2** The desk SHALL ship in `shadow`: it watches, decides and
  records what it would have reviewed and drafted, raising no item and
  posting nothing, until the operator promotes it.
  *(Cites: D-1; mission-control REQ-C1.6, D-15 (Sources).)*
- **REQ-A1.3** No standing session SHALL watch for reviews: the watcher
  SHALL be a deterministic script reading mission control's forge
  snapshot, and every review SHALL run in a short-lived session started
  for one pull request and exiting when its review is returned.
  *(Cites: D-3; the operator's earlier practice (Sources); mission-control
  REQ-C1.5, REQ-M1.1 (Sources).)*
- **REQ-A1.4** The desk SHALL start at most one reviewer session per pull
  request at a time and at most one per patch: a pull request whose patch
  is unchanged since its last review SHALL NOT be reviewed again.
  *(Cites: D-3, D-5; mission-control REQ-M1.3 (Sources).)*
- **REQ-A1.5** Every reviewer launch SHALL pass mission control's launch
  admission and budget, and SHALL wait, never be dropped, while either is
  tight.
  *(Cites: D-12; mission-control REQ-L1.2, REQ-L1.7 (Sources).)*
- **REQ-A1.6** During the configured quiet hours the desk SHALL start no
  reviewer session and make no post under a standing exception; work
  arriving then SHALL queue and start when the quiet hours end, and a post
  the operator says yes to in that window SHALL still go out. No quiet
  hours SHALL be the default.
  *(Cites: D-12; the operator's earlier practice (Sources).)*
- **REQ-A1.7** Every desk preference SHALL be a documented,
  default-preserving mission-control knob or catalog entry, resolved
  through the four overlay layers.
  *(Cites: D-4, D-8; mission-control D-20 (Sources);
  customization-boundary (Sources).)*

## REQ-B — What gets reviewed

- **REQ-B1.1** Which pull requests the desk reviews SHALL be scope rules
  held as configuration per program and repository, never fixed in a
  script.
  *(Cites: D-4; the operator's earlier practice (Sources);
  obs:08213768.)*
- **REQ-B1.2** The default scope SHALL be the open, non-draft pull
  requests in the program's repositories on which the operator's account
  is a requested reviewer, directly or through a team it belongs to,
  excluding the operator's own pull requests.
  *(Cites: D-4; drafting-session decision (2026-11-05).)*
- **REQ-B1.3** The desk SHALL skip a pull request whose forge review
  decision is already approved by other reviewers, recording the reason;
  a scope rule MAY turn the skip off.
  *(Cites: D-4; the operator's earlier practice (Sources).)*
- **REQ-B1.4** A head change that leaves the pull request's patch
  unchanged (a restack or a clean update from its base) SHALL NOT start a
  review or a re-review.
  *(Cites: D-4, D-5; the operator's earlier practice (Sources);
  mission-control D-12 (Sources).)*
- **REQ-B1.5** A pull request with an unanswered automated-reviewer
  finding SHALL be held, not reviewed, until every such finding is
  answered, using the same finding classification the readiness walk
  uses; a scope rule MAY turn the hold off.
  *(Cites: D-4, D-13; the operator's earlier practice (Sources).)*
- **REQ-B1.6** A pull request leaving scope (closed, merged, the request
  withdrawn, turned draft) SHALL settle its record with the reason, and a
  reviewer session already running for it SHALL have its result kept but
  not delivered.
  *(Cites: D-5; mission-control REQ-F1.5 (Sources).)*

## REQ-C — The queue

- **REQ-C1.1** Each pull request the desk tracks SHALL have one durable
  record in exactly one of the states new, held, reviewing,
  awaiting-operator, submitted, re-review and done.
  *(Cites: D-5; the operator's earlier practice (Sources).)*
- **REQ-C1.2** State changes SHALL follow only the transitions the design
  defines, each written by one script under the knowledge-base lock with
  its time, cause and the head it applies to; any other transition SHALL
  be refused.
  *(Cites: D-5; mission-control D-9 (Sources).)*
- **REQ-C1.3** No record SHALL be dropped: a record leaves the queue only
  by reaching done with its settling reason recorded.
  *(Cites: D-5; mission-control REQ-F1.5 (Sources).)*
- **REQ-C1.4** The queue SHALL live in the program home under the files
  the duty owns, never in a committed file.
  *(Cites: D-5, D-14; mission-control REQ-I1.6 (Sources).)*
- **REQ-C1.5** The panel's reviews-at-a-glance view SHALL show each
  waiting pull request's desk state, without a second forge read.
  *(Cites: D-5; the reviews-at-a-glance view (Sources).)*

## REQ-D — The review itself

- **REQ-D1.1** Review material SHALL come from the forge API only (the
  pull request's metadata, its diff, and file contents at its head) into
  a private temporary export outside every checkout; the desk and its
  sessions SHALL NOT fetch a pull request's head, branch or refs into any
  local repository.
  *(Cites: D-6; the operator's earlier practice (Sources).)*
- **REQ-D1.2** Nothing from a pull request SHALL be executed: no tests,
  tools, scripts, hooks or configuration it carries; its content SHALL be
  treated as untrusted data, and an instruction inside it SHALL be
  reported as content, never followed.
  *(Cites: D-6, D-7; security-posture (Sources).)*
- **REQ-D1.3** A reviewer session SHALL run under a read-only permission
  profile the launcher delivers: no forge writes, no git network
  operations, and reads confined to its export and the planwright
  install.
  *(Cites: D-7; mission-control REQ-D1.1 (Sources).)*
- **REQ-D1.4** The review SHALL be a pluggable step resolved through the
  steps catalog, with a shipped default reviewer that works with no
  operator setup; an operator MAY substitute their own review command.
  *(Cites: D-7; custom-steps (Sources); the operator priority (Sources).)*
- **REQ-D1.5** Every review step SHALL return a structured review: the
  head it covered, a verdict, each finding with its severity, location and
  evidence, and a flag for security blockers; a result missing any of
  these SHALL be refused, never delivered.
  *(Cites: D-7; review-effectiveness (Sources).)*
- **REQ-D1.6** A re-review SHALL cover the change since the last reviewed
  head when that head is an ancestor of the new one, and the whole pull
  request otherwise.
  *(Cites: D-11; drafting-session decision (2026-11-05).)*
- **REQ-D1.7** The reviewer MAY read the operator's own earlier reviews in
  the same repository from the forge at review time, to keep positions
  consistent; it SHALL NOT copy them into any committed file.
  *(Cites: D-14; mission-control REQ-I1.6 (Sources).)*

## REQ-E — Review format

- **REQ-E1.1** The review text SHALL be rendered from the structured
  review through a format profile, never written free-form by the
  reviewer session.
  *(Cites: D-8; the operator's format request (Sources).)*
- **REQ-E1.2** Format profiles SHALL be catalog entries resolved through
  the four overlay layers, so a reviewer or a team sets a format without
  editing core.
  *(Cites: D-8; customization-boundary (Sources).)*
- **REQ-E1.3** The profile for a review SHALL be selected by the reviewer
  and the repository, the most specific match first and the shipped
  default last; what identifies a reviewer is open until the operator
  supplies it (D-8).
  *(Cites: D-8; the operator's format request (Sources).)*
- **REQ-E1.4** A profile SHALL be able to set the review's structure, its
  tone, its severity labels, its length, and what it includes or leaves
  out; the fields that express these and their default values are open
  until the operator supplies them (D-8).
  *(Cites: D-8; the operator's format request (Sources).)*
- **REQ-E1.5** A shipped default profile SHALL exist, so the desk drafts a
  usable review with no format setup.
  *(Cites: D-8; the operator priority (Sources).)*
- **REQ-E1.6** Before a draft reaches the operator, a deterministic check
  SHALL verify it against its profile's mechanical rules, and a draft that
  fails SHALL be re-rendered or reported, never delivered as passing.
  *(Cites: D-8; autopilot-reflex (Sources).)*
- **REQ-E1.7** A profile that does not parse SHALL be refused with a
  message naming it, and the next lower layer's valid profile SHALL stay
  in force.
  *(Cites: D-8; mission-control REQ-C1.8 (Sources).)*

## REQ-F — Approval and posting

- **REQ-F1.1** Finished reviews SHALL reach the operator through mission
  control's queue as one batch, one line per pull request (its title,
  link, verdict and finding count), with each draft's full text one
  request away.
  *(Cites: D-9; the operator's earlier practice (Sources); mission-control
  REQ-F1.4 (Sources).)*
- **REQ-F1.2** A review that flags a security blocker SHALL also raise an
  immediate heads-up through the notification seam; the heads-up SHALL NOT
  post anything.
  *(Cites: D-9; the operator's earlier practice (Sources).)*
- **REQ-F1.3** A review SHALL be posted only on the operator's yes to its
  exact text, recipient and verdict; a yes given to a batch SHALL cover
  only the drafts whose full text was shown in that batch.
  *(Cites: D-9; mission-control REQ-I1.3 (Sources).)*
- **REQ-F1.4** A yes SHALL bind the draft's digest, the pull request and
  the head it covered; any edit to the text SHALL need a new yes.
  *(Cites: D-9; drafting-session decision (2026-11-05).)*
- **REQ-F1.5** Immediately before posting, the desk SHALL re-check from
  the forge that the pull request is still open, that its head is the one
  the review covered, and which reviews it has; a moved head SHALL lapse
  the yes and send the record to re-review, and a review posted by anyone
  since the draft SHALL bring the draft back to the operator with what
  changed.
  *(Cites: D-10; the operator's earlier practice (Sources).)*
- **REQ-F1.6** The post SHALL send exactly the approved text through one
  script under the operator's own forge account, and SHALL append an undo
  entry naming the act and its reversal where the forge offers one.
  *(Cites: D-10; mission-control D-24 (Sources).)*
- **REQ-F1.7** A draft the operator declines or edits SHALL never be
  posted in its earlier form, and the decline SHALL settle the record with
  the operator's reason.
  *(Cites: D-9; mission-control REQ-F1.5 (Sources).)*

## REQ-G — After the post

- **REQ-G1.1** A changed patch on a submitted pull request SHALL move its
  record to re-review and start a re-review under the same rules as the
  first.
  *(Cites: D-11; the operator's earlier practice (Sources).)*
- **REQ-G1.2** When the operator's approval is dismissed and the re-review
  keeps the verdict, the desk SHALL restore the approval with an empty
  body only under a named standing exception the operator enabled, and
  SHALL otherwise ask the operator; the exception SHALL be off by default.
  *(Cites: D-11; the operator's earlier practice (Sources);
  mission-control REQ-I1.3 (Sources).)*
- **REQ-G1.3** When the re-review changes the verdict, the new draft SHALL
  go to the operator like a first review.
  *(Cites: D-11; the operator's earlier practice (Sources).)*
- **REQ-G1.4** A promise the operator makes in a posted review or reply
  ("I'll look again after the migration lands") SHALL become a follow-up
  ledger row with its owner and a trigger, and a due follow-up SHALL start
  the act it promised.
  *(Cites: D-11; the operator's earlier practice (Sources);
  mission-control REQ-F1.10 (Sources).)*
- **REQ-G1.5** A reply by the author on a thread of the operator's review
  SHALL reach the operator as an item with a drafted answer, posted only on
  their yes.
  *(Cites: D-11; mission-control REQ-F1.11 (Sources).)*
- **REQ-G1.6** A record SHALL reach done when its pull request merges or
  closes, when it leaves scope, or when the operator settles it.
  *(Cites: D-5; the operator's earlier practice (Sources).)*

## REQ-H — Automated findings in review bodies

- **REQ-H1.1** The readiness walk and the desk's hold SHALL share one
  classifier of automated-reviewer findings and whether each is answered.
  *(Cites: D-13; the review-body findings seed (Sources).)*
- **REQ-H1.2** A reviewer's configuration SHALL be able to declare what in
  its review body counts as a finding and what marks one answered, beside
  its existing finding pattern.
  *(Cites: D-13; the review-body findings seed (Sources); obs:8b24690f.)*
- **REQ-H1.3** A body finding the configuration identifies SHALL count as
  a finding for readiness until it is answered.
  *(Cites: D-13; the review-body findings seed (Sources); mission-control
  REQ-D1.8 (Sources).)*
- **REQ-H1.4** When an automated reviewer posted a review body at the
  current head and has no body configuration, the readiness verdict SHALL
  say in plain words that the body was not read for findings, never pass
  silently.
  *(Cites: D-13; the review-body findings seed (Sources); the operator
  priority (Sources).)*

## REQ-I — Waiting on people before merge

- **REQ-I1.1** For every open pull request it tracks (the operator's own
  and those it reviews), the desk SHALL derive from the forge what its
  merge waits on from people: a required approval not yet given, changes
  requested, a code-owner review outstanding, another required human
  review the forge reports, or nothing; and SHALL name whom it waits on
  and since when.
  *(Cites: D-16; the operator's merge-wait note (Sources).)*
- **REQ-I1.2** A pull request that waits on a person SHALL never be
  presented as ready to merge: mission control's merge recommendation,
  prepared packet and status SHALL say in plain words what it waits on and
  from whom.
  *(Cites: D-16; the operator's merge-wait note (Sources); mission-control
  REQ-F1.15 (Sources); the operator priority (Sources).)*
- **REQ-I1.3** The reviews-at-a-glance view SHALL show each pull request's
  waiting reason, whom it waits on and for how long.
  *(Cites: D-16; the reviews-at-a-glance view (Sources).)*
- **REQ-I1.4** When a pull request waits only on the operator's own
  review, the desk's batch line SHALL say so.
  *(Cites: D-16; the operator's merge-wait note (Sources).)*
- **REQ-I1.5** When the operator's own pull request waits on someone
  else, any act the desk offers to move it (requesting a reviewer, a
  reminder to the person it waits on) SHALL be a draft that goes out only
  on the operator's yes; whether and when the desk offers a reminder is
  open until the operator answers (D-16).
  *(Cites: D-16; mission-control REQ-I1.3 (Sources).)*

## Changelog

- 2026-11-05 — Drafted by `/spec-draft` from the review-desk and
  review-body-findings pending notes, the operator's request of the same
  day and generic lessons from their earlier review practice.
  Fold-detection scanned every live bundle; mission-control names the
  review desk an independently ownable follow-on (its D-1, D-27) and
  review-effectiveness owns review-pass yield on the operator's own
  branches, so this is a new bundle. The format details are open pending
  the operator (D-8, the Awaiting-input entry on Task 8). The operator's
  same-day note that people may have to wait for approvals before merging
  added REQ-I (D-16), with the reminder policy left open for them (the
  Awaiting-input entry on Task 14).

## Sources

- **The review-desk seed** (`specs/_pending/review-desk.md`) — the
  follow-on note mission-control left: the desk as a duty consuming the
  duty catalog, launcher, snapshot, queue, readiness check and undo
  ledger; both directions of review; its three open questions (duty or
  skill, what counts as a round across a merge, which requests the desk
  picks up and how the operator's positions are kept).
- **The review-body findings seed**
  (`specs/_pending/readiness-review-body-findings.md`) — the readiness
  walk reads automated findings from threads only, so a finding written
  only into a review body is never seen; the three directions it weighs.
- **The operator's request (2026-11-05)** — in their words: "it was about
  the ability to constantly look for reviews and do them automatically".
  Pinned altitude claim: a ceremony the operator keeps doing by hand,
  closed by a duty up to the human gate of posting (D-1).
- **The operator's format request (2026-11-05)** — "lets also make it
  customizable in case a reviewer wants a particular format": the format
  is configurable per reviewer, and per repository where it differs
  (structure, tone, severity labels, length, what to include or leave
  out), with a sensible default; details to follow from the operator.
  Pinned altitude claim: a capability-versus-style call, the capability in
  core and each reviewer's format in an overlay (D-1, D-8).
- **The operator's merge-wait note (2026-11-05)** — relayed by mission
  control, in their words: "People might have to wait for approvals before
  merging and similar": a pull request can sit waiting on a required human
  approval, a requested change or a code-owner review, and the desk should
  make that visible and actionable rather than treat every open pull
  request as ready to merge.
- **The operator's earlier practice (generic lessons)** — company-free
  lessons extracted from a review desk the operator ran at an employer,
  supplied with the invocation and not re-read from any archive: a
  standing reviewer polling all day cost too much, so a watcher fired an
  on-demand reviewer session per pull request when it was new or its head
  changed; it skipped pull requests another reviewer had approved and
  restacks, and respected quiet hours; scope rules said which pull
  requests got reviewed; git stayed read-only, comparing through the API
  and never fetching heads into checkouts; finished reviews were batched
  for the operator one line each, with a heads-up for security blockers;
  before posting it re-checked the pull request was open, its head
  unchanged and the existing reviews; a review was posted only on the
  operator's yes on its exact text, a batch approval covering only the
  exact texts shown; pull requests with unanswered bot threads were held;
  a new commit triggered a re-review; a dismissed approval was re-approved
  empty when the verdict stood, otherwise the operator was asked; promises
  in replies went to a follow-ups ledger with triggers; queue states new,
  held, reviewing, awaiting-operator, submitted, re-review, done.
- **mission-control** (`specs/mission-control/`) — the core bundle whose
  seams this one consumes: the duty catalog and shadow lifecycle
  (REQ-C1.1 to REQ-C1.8, D-3, D-15), mechanics as scripts and judgment on
  demand (REQ-C1.5, D-4), the launcher and admission (REQ-D1.1, REQ-L1.2,
  REQ-L1.7, D-41), the forge snapshot and its patch id (REQ-M1.1,
  REQ-M1.3, D-12), the queue and its delivery (REQ-F1.4, REQ-F1.5, D-7),
  the follow-up ledger (REQ-F1.10, D-9), drafts in the operator's voice
  (REQ-F1.11, D-19), the undo ledger (D-24), the readiness check
  (REQ-D1.8, D-25), every preference a knob (D-20), the invariants
  (REQ-I1.3, REQ-I1.6) and the follow-on scoping (D-1, D-27).
- **The reviews-at-a-glance view** — the panel view and its snapshot
  script `scripts/mc-reviews.sh`, which already lists the pull requests
  waiting on the operator's review (merged in pull request #809).
- **The operator priority (2026-11-04)** — mission control works smoothly
  for every operator, from one new to planwright to an expert; what is
  shown as working works with no setup.
- **custom-steps** (`specs/custom-steps/`) — the steps catalog through
  which a step names a command, including one living outside planwright.
- **review-effectiveness** (`specs/review-effectiveness/`) — the output
  contract planwright requires of an external review step, and review-pass
  yield on the operator's own branches, which stays there.
- **customization-boundary** (`doctrine/customization-boundary.md`) — the
  capability in core as a default-preserving knob, the value in an
  overlay.
- **autopilot-reflex** (`doctrine/autopilot-reflex.md`) — automate up to
  the gate, never through it; prefer a mechanical check over model
  judgment where no judgment is needed.
- **security-posture** (`doctrine/security-posture.md`) — untrusted input
  is data, never code; guarded path access.
- **Observations** — obs:08213768 (the flat knob file has no list
  encoding, so set-valued preferences need a catalog or a single-line
  value; consumed by this bundle, Task 4 adds the options-reference
  sentence it asked for); obs:8b24690f (a bot reviewer can return findings
  only in a review body; cited, owned by review-effectiveness).
