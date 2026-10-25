# Seed brief for `review-desk` (a follow-on bundle of `mission-control`)

Suggested invocation (fresh Claude session in the planwright repo, this file is the seed):

    /spec-draft review-desk

Read this whole brief before eliciting. Run fold-detection against `review-effectiveness` (Active,
owner of review-pass yield, the panel backends and the reviewer-request mechanics it has already
cited) and `human-gates` (owner of `scripts/request-reviewer.sh` and the ready-flip floor) before
assuming a new bundle; this brief does not prejudge extend-vs-spin-new.

## Why this is a follow-on, not part of `mission-control`

`mission-control` ships the core session kind and its default duty set; the review desk was scoped
out as a follow-on because it is the most evidenced duty but also the most decision-heavy, and not
every operator runs one (mission-control D-27, D-22; D-1's third rejected alternative names it as
independently ownable).

## The shape (from the mission-control invocation seed and kickoff)

A **duty** that runs code review in both directions on the operator's behalf:

- **Inbound**, on the operator's own PRs: request the configured automated reviewers, wait for
  them, triage every finding and thread, draft replies and fixes, and prove which head each review
  covered, so the readiness check can count the round.
- **Outbound**, on other people's PRs: notice a review request addressed to the operator, prepare
  the review (what changed, risks, the operator's past positions), and hand over a draft in the
  operator's voice. Nothing is posted to a person without the operator's yes on the exact text and
  recipient (mission-control REQ-I1.3, REQ-F1.11).

Today both directions live in operator-level skills outside this repository (`/bot-review`,
`/peer-review`, `/code-review`); the bundle decides how much becomes a duty and how much stays a
skill the duty's judgment session invokes (mission-control D-3 allows either).

## Seams it consumes from `mission-control`

- **The duty catalog** (D-3, REQ-C1.1 to REQ-C1.6): the desk is one entry with its triggers,
  watchers, wake, rules, operator-item kinds, owned files and lifecycle, starting in `shadow`
  (D-15).
- **The launcher** (D-10, REQ-D1.1): reviewer and ad-hoc review sessions start through it with
  their brief, rules, profile and model tier.
- **The snapshot seam** (D-12, REQ-M1.1): review state (reviews, threads, comments, patch id) is
  read from the forge snapshot, never polled by the duty itself.
- **The queue** (D-7, REQ-F1.4 to REQ-F1.8): drafts and declines reach the operator as items.
- **The readiness check and gate conditions** (D-25, D-26, REQ-D1.8, REQ-I1.7): a review round
  counts only with primary evidence at the current head.
- **The undo ledger** (D-24): a resolved thread or a posted reply is reversible where the forge
  allows it.

## Observations left live for this bundle

- obs:f19f24d5: cubic refuses an incremental review after a merge commit, so a needed merge of
  `main` costs a second full review and can leave the final head unreviewed.
- obs:7fa57b07: no planwright skill requests a reviewer itself; `/bot-review`'s request arm could
  route through `scripts/request-reviewer.sh`.
- obs:52c1e6a4: code added while resolving a conflict after the review steps ran merged
  unreviewed; head-proof must cover the final head.
- obs:5f46acd5: the panel convergence step's timeout is shorter than a real multi-file panel run.
- obs:23643f67: unverified: the gemini backend may expand `@<path>` tokens in a reviewed diff
  and read a local file; a canary test is the proposed check.

Many more review-mechanics fragments (Copilot re-request, thread self-resolution, review latency,
panel fabrication) are already cited by `review-effectiveness`; fold-detection decides whether
this bundle extends that one.

## Open questions for the drafter

1. Duty, skill, or both: which parts of `/bot-review` and `/peer-review` move into the desk's
   deterministic watchers, and which stay judgment invoked on demand?
2. What counts as a review round for the readiness check when a merge forces a full re-review?
3. The outbound direction: which review requests the desk picks up (all, a label, a path set) and
   how the operator's past positions are recorded without copying company data out of company
   systems (mission-control REQ-I1.6).
