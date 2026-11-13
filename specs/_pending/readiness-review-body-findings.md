# Seed: review-body findings in the readiness walk

Captured 2026-10-28 from the automated review of mission-control Task 10
(pull request #755). A seed for a later `/spec-draft`, most likely an
extension of `mission-control` or a part of the `review-desk` follow-on
(`specs/_pending/review-desk.md`); fold-detection decides.

## The gap

The readiness-check walk (`scripts/mc-readiness.sh`) reads an automated
reviewer's findings from review threads only: a thread a bot opened is a
finding, answered once resolved or replied to by a person other than the
pull request's author. A finding a bot writes only into a review body has
no thread, so the walk never sees it, and a pull request can walk `ready`
with such a finding unanswered. REQ-D1.8 names automated reviewer findings
as primary evidence.

## Why it was not closed in Task 10

Failing closed on every review body would block every pull request, since a
reviewer such as cubic always posts a summary body. Telling a summary from a
finding, and an answered body finding from an open one, needs a marker no
reviewer shares today.

## Directions to weigh

- An answered marker a reply carries for a body finding (the bot-review
  skill's acknowledgment marker is one shape), read by the walk per
  reviewer.
- Per-reviewer configuration of what in a body counts as a finding, beside
  the reviewer's existing finding-key pattern.
- Leaving body findings to the review desk duty, with the walk naming the
  gap in its verdict instead of passing silently.
