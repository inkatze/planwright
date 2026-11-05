# Review desk — Tasks

**Status:** Draft
**Last reviewed:** 2026-11-05
**Format-version:** 2
**Execution:** derived — see the status render

Tasks in dependency order, which is presentation; the `Dependencies:`
lines carry the graph. Task 8 (review formats) waits on the operator's
format details and Task 14 (reminders) on their reminder policy;
everything else can run without them, and the desk runs end to end in
shadow before Task 8 lands.

## Tasks

### Task 1 — The forge snapshot carries review-requested pull requests

- **Deliverables:** The forge snapshot adapter's tracked set grows to the
  open pull requests in the program's repositories that request the
  operator's account, directly or through a team, with the fields the desk
  reads: review requests and their teams, the forge review decision, the
  account's latest review and whether it was dismissed, automated
  reviewers' threads and review bodies, head and base, and the patch id;
  for the operator's own pull requests too, the requested reviewers with
  their code-owner flag, the latest review per reviewer and the merge
  state;
  the reviews-at-a-glance script reads its waiting list from the same
  snapshot rather than a second search; tests against recorded forge
  fixtures.
- **Done when:** The adapter's tests show a review-requested pull request
  (direct and team) in the snapshot with every listed field, an unchanged
  patch id across a restack fixture and a changed one across a new-commit
  fixture; the reviews view's tests pass reading the snapshot; no new
  forge poller exists outside the adapter.
- **Dependencies:** none
- **Citations:** D-3, D-4 · REQ-A1.3, REQ-B1.2, REQ-B1.4, REQ-C1.5
- **Estimated effort:** 2 days

### Task 2 — One automated-finding classifier, with body findings

- **Deliverables:** A shared classifier of automated-reviewer findings
  (thread findings as the readiness walk reads them today, plus body
  findings) and whether each is answered; per-reviewer configuration for a
  body-finding pattern and an answered marker beside the existing finding
  pattern, documented in the options reference; the readiness walk moved
  onto the classifier, counting configured body findings and naming in
  plain words a body it could not read; tests.
- **Done when:** Tests show a configured body finding blocking readiness
  until a reply carries the answered marker; an unconfigured bot body at
  the head producing the plain-words gap in the verdict without blocking;
  every existing readiness test passing unchanged; the classifier callable
  by another script with the same output.
- **Dependencies:** none
- **Citations:** D-13 · REQ-H1.1, REQ-H1.2, REQ-H1.3, REQ-H1.4,
  REQ-B1.5
- **Estimated effort:** 2 days

### Task 3 — The desk queue store and its transitions

- **Deliverables:** A queue script owning one record per tracked pull
  request under the duty's files in the program home: the seven states,
  the transition table D-5 states, an append-only transition log with
  time, cause and head, refusal of any other transition, writes under the
  knowledge-base lock, done records kept with their settling reason, and a
  shadow mode that logs would-have transitions; tests.
- **Done when:** Tests drive every allowed transition and see each
  disallowed one refused; concurrent writers under the lock leave a
  consistent record; no record is ever removed; shadow mode writes only
  would-have entries; the store's path resolves inside the program home and
  never inside a checkout.
- **Dependencies:** none
- **Citations:** D-5, D-14 · REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4,
  REQ-A1.2
- **Estimated effort:** 2 days

### Task 4 — Scope rules and holds

- **Deliverables:** The `review-scope` catalog (core seed carrying the
  D-4 default, overlay layers through the catalog resolver, the entry
  grammar in its header, a validator); one sentence in the options
  reference's conventions saying set-valued preferences are single-line
  space-separated values or catalog entries; an evaluator that, given
  a snapshot record, returns review, skip (with reason) or hold (with the
  unanswered findings, through Task 2's classifier); restack detection by
  patch id; tests.
- **Done when:** Tests show the default reviewing a direct and a team
  request, skipping the operator's own pull request, a draft and one the
  forge reports approved, holding one with an unanswered automated finding
  and releasing it when answered, and treating a restack as no change;
  each rule's override flips its case; an overlay entry for one
  repository changes only that repository; the catalog validator refuses
  a malformed entry and keeps the lower layer's.
- **Dependencies:** 1, 2
- **Citations:** D-4 · REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5,
  REQ-A1.7
- **Estimated effort:** 1 day

### Task 5 — The desk watcher and its duty entry

- **Deliverables:** The `review-desk` entry in the core duty catalog
  (triggers, watcher with cadence and cost class, wake, rules, item kinds,
  owned files, lifecycle `shadow`); the watcher script that reads the
  snapshot, applies Task 4, advances Task 3's records (entering, holding,
  releasing, settling on close, merge, withdrawal or approval by others,
  moving to re-review on a changed patch) and emits one reviewer trigger
  per record needing a review; launch admission, budget and the
  `mission_control_review_quiet_hours` knob honoured, a held-back launch
  waiting rather than dropped; tests over fixture snapshots.
- **Done when:** The duty validator accepts the entry and a disabled or
  `off` desk arms nothing; fixture runs show one trigger per new patch and
  none for an unchanged patch or a record already reviewing; quiet hours
  and a refused admission defer the trigger and the next run emits it;
  shadow mode raises no item; a closed pull request settles its record.
- **Dependencies:** 3, 4
- **Citations:** D-3, D-5, D-12 · REQ-A1.1, REQ-A1.2, REQ-A1.3,
  REQ-A1.4, REQ-A1.5, REQ-A1.6, REQ-B1.6, REQ-G1.1, REQ-G1.6
- **Estimated effort:** 2 days

### Task 6 — Read-only review export from the forge

- **Deliverables:** An export script that writes a pull request's
  metadata, the diff from its comparison point (the last reviewed head
  when an ancestor of the head, else the base) and the changed files'
  contents at the head into a fresh private temporary directory, from the
  forge API only; path validation and containment after canonicalization,
  no symlinks, no executable bits, sanitized names; removal on exit; tests
  including hostile path fixtures and a security pass per the write-time
  triggers.
- **Done when:** Tests show a full export and a delta export from fixture
  API responses; traversal, absolute, symlink and control-byte paths are
  refused cleanly; no git network command and no write outside the
  temporary directory occurs (asserted by the test harness); the directory
  is gone after exit.
- **Dependencies:** none
- **Citations:** D-6, D-11 · REQ-D1.1, REQ-D1.2, REQ-D1.6
- **Estimated effort:** 1 day

### Task 7 — The reviewer session and the structured review

- **Deliverables:** The reviewer launch: a read-only reviewer permission
  profile the launcher delivers (no forge writes, no git network, reads
  confined to the export and the install); the reviewer brief, which
  treats the export as untrusted data and may read the operator's own
  earlier reviews in that repository from the forge; the
  `mission_control_review_step` knob resolving the review step through
  the steps catalog, with the shipped default reviewer step; the
  structured-review contract (head, verdict, findings with severity,
  location, evidence and suggested comment, security-blocker flag) and its
  validator; the watcher's trigger wired to launch, and the result moving
  the record on (valid result held for rendering, invalid or failed back
  to new or re-review with the reason); tests.
- **Done when:** Tests show the profile denying a forge write and a git
  fetch; the contract validator refusing a result missing any field; a
  fixture run from trigger to a valid structured review recorded against
  the record, in shadow; an operator-supplied step entry replacing the
  default through an overlay; a planted instruction in a fixture diff
  reported as content in the review, under the behavioral-eval harness on
  demand.
- **Dependencies:** 5, 6
- **Citations:** D-7, D-14 · REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-D1.5,
  REQ-D1.7, REQ-A1.3
- **Estimated effort:** 3 days

### Task 8 — Review format profiles, renderer and check

- **Deliverables:** The `review-formats` catalog merged through the four
  overlay layers, each profile carrying the selectors it applies to; the
  resolver choosing a profile by reviewer and repository, most specific
  first, shipped default last; the deterministic renderer from the
  structured review to review text, with the reviewer session supplying
  only the wording a template cannot; the draft check against the
  profile's mechanical rules; the shipped default profile; refusal of an
  unparseable profile with the lower layer kept in force; tests. The
  profile fields, their grammar and the default values are the
  operator's (see Awaiting input).
- **Done when:** Tests show resolution at every specificity and the
  fallback to the default; a repository profile overriding a reviewer's
  for that repository only; the renderer's output passing the check for
  every fixture review under every fixture profile; a draft violating a
  mechanical rule refused; a malformed overlay profile refused with its
  name while the lower layer's profile renders.
- **Dependencies:** 7
- **Citations:** D-8 · REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-E1.4, REQ-E1.5,
  REQ-E1.6, REQ-E1.7, REQ-A1.7
- **Estimated effort:** 2 days

### Task 9 — Batched delivery, the exact-text yes, and the post

- **Deliverables:** The desk's operator-item kinds in the queue: the
  batch item (one line per pull request, full text one request away) and
  the security heads-up through the notification seam; yes records
  binding digest, pull request, verdict and head, a batch yes covering
  only the drafts shown in full; edits producing a new draft and a
  declined draft settling its record; the post script, run only from a
  yes, that re-checks open state, head and reviews from the forge, posts
  exactly the approved text under the operator's account, verifies the
  posted digest and appends an undo entry; tests.
- **Done when:** Gherkin fixtures show a batch yes posting only the
  drafts whose text was shown; an edited draft refused under the old yes;
  a moved head lapsing the yes and re-reviewing; a new review since the
  draft returning it to the operator; a closed pull request settling; a
  security blocker producing the heads-up and no post; a successful post
  leaving a matching digest and an undo entry; nothing posts in shadow.
- **Dependencies:** 8
- **Citations:** D-9, D-10 · REQ-F1.1, REQ-F1.2, REQ-F1.3, REQ-F1.4,
  REQ-F1.5, REQ-F1.6, REQ-F1.7
- **Estimated effort:** 2 days

### Task 10 — After the post

- **Deliverables:** Re-review on a changed patch through the same path;
  dismissed-approval handling (the `mission_control_review_reapprove`
  standing exception, off by default, restoring an empty approval when the
  re-review keeps the verdict, else a one-line item); a changed verdict
  delivered as a new draft; author replies on the operator's review
  threads as items with a drafted answer; promises in posted texts
  extracted into the follow-up ledger with owner and trigger, and a due
  follow-up starting its act; tests.
- **Done when:** Fixtures show a new commit moving a submitted record to
  re-review with a delta review; a dismissal with the exception off
  raising an item and with it on posting an empty approval with an undo
  entry; a changed verdict raising a draft; an author reply raising an
  item that posts only on a yes; a promise producing a ledger row whose
  trigger later starts the act; a merge settling the record.
- **Dependencies:** 9
- **Citations:** D-11 · REQ-G1.1, REQ-G1.2, REQ-G1.3, REQ-G1.4, REQ-G1.5,
  REQ-G1.6, REQ-D1.6
- **Estimated effort:** 2 days

### Task 11 — The desk state in the reviews view

- **Deliverables:** The panel's reviews-at-a-glance view showing each
  waiting pull request's desk state from the queue store, with the text
  panel fallback carrying the same column; tests through the panel's test
  harness.
- **Done when:** The view's tests show every state rendering, a pull
  request with no record showing none, and no extra forge read during a
  redraw.
- **Dependencies:** 3
- **Citations:** D-5 · REQ-C1.5
- **Estimated effort:** half day

### Task 12 — Presented as working, and documented

- **Deliverables:** The operator guide's review-desk section (what it
  does, shadow and promotion, scope, quiet hours, formats, the yes); every
  desk knob's options-reference row; the first run and the guide
  presenting the desk as available only once its entry is armed; an end
  to end shadow run over a fixture program from snapshot to would-have
  draft.
- **Done when:** The knob and duty checks pass; the guide names every
  knob the desk reads; the fixture run produces would-have records for a
  new, a held, a restacked and an approved pull request with the expected
  outcome each; a desk with no armed entry is presented as not yet
  available.
- **Dependencies:** 5, 7, 9, 10, 11, 13
- **Citations:** D-1, D-12, D-15 · REQ-A1.1, REQ-A1.2, REQ-A1.7
- **Estimated effort:** 1 day

### Task 13 — What a merge waits on from people

- **Deliverables:** A derivation over the snapshot giving each tracked
  open pull request its waiting reason (a required approval not yet given,
  changes requested, a code-owner review outstanding, another required
  human review, or nothing), whom it waits on and since when; the merge
  recommendation, prepared packet and status replacing any ready-to-merge
  presentation with that plain statement (with the guided-level lesson);
  the reviews view's waiting column; the batch line saying when a pull
  request waits only on the operator; tests.
- **Done when:** Fixtures for each reason produce it with the right
  person and age; a pull request with a pending required approval is
  never presented as ready to merge by the recommendation, packet or
  status, at every guidance level; the reviews view shows the reason and
  wait; a pull request waiting only on the operator is named so in the
  batch line.
- **Dependencies:** 1, 11
- **Citations:** D-16 · REQ-I1.1, REQ-I1.2, REQ-I1.3, REQ-I1.4
- **Estimated effort:** 1 day

### Task 14 — Moving a pull request that waits on someone

- **Deliverables:** For the operator's own pull request waiting on
  someone else, the offered acts as drafts going out only on the
  operator's yes (requesting a reviewer through the sanctioned request
  path, a reminder to the person it waits on), under the policy the
  operator sets (see Awaiting input); tests.
- **Done when:** Fixtures show an offer raised under the operator's
  policy, a reminder posted only after a yes on its exact text and
  recipient, and no offer where the policy says none.
- **Dependencies:** 13, 9
- **Citations:** D-16 · REQ-I1.5
- **Estimated effort:** 1 day

## Awaiting input

- **Task 8** The review format's details are the operator's, and they said
  they would send them: what fields a format profile has and how each is
  written (structure, tone, severity labels, length, what to include or
  leave out); the shipped default profile's values; whether a "reviewer"
  is the account that posts, a reviewer persona the operator names, or
  both; whether findings post as line comments, in the review body, or as
  a per-profile choice; and which format rules the draft check enforces
  mechanically. Answer, then amend D-8 and REQ-E1.4 before this task
  dispatches.
- **Task 14** When one of the operator's own pull requests is waiting on
  someone's approval, should mission control offer to send that person a
  reminder (always drafted for the operator's yes), and if so after how
  long and to whom; or only show that it is waiting? And should a pull
  request that waits only on the operator's own review move ahead of
  other reviews in their queue? Answer, then amend D-16 and REQ-I1.5
  before this task dispatches.

## Deferred

(none yet)

## Out of scope

(none yet)
