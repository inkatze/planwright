# Seed: tower-comms contract text behind two operator rulings

Captured 2026-10-30 while tower-comms Task 11 applied the operator's rulings on
its parked review findings. The code follows the rulings; the signed spec text
was left as it is, so a `/spec-kickoff` delta re-walkthrough decides whether
the text moves to match.

## Who may add a decided-by-mission-control item

REQ-A1.14 and D-20 admit the item from a caller whose launcher-registry row
records the `mission-control` session kind. The name that selects the row is
the caller's own claim, so the operator ruled that the row's token decides it:
the launcher exports the token into a mission-control session as
`PLANWRIGHT_MC_TOKEN` (both rungs, no other kind), and `add` refuses a
mismatched or absent token, a row whose session is no longer running, a row
others can write, and a widened registry directory. The REQ and the decision
say neither the token nor the liveness check.

## A question's identifier

D-3's identity rule keyed a question by its row alone (one awaiting-input row
is one question, however often it re-forks). With D-20 keeping a
settled-by-default item's identifier, the worker's next question on that row
collided with the default still awaiting review. The operator ruled that a
question's identifier carries the row instance it was born with; `add` still
keeps one open question per row across re-forks, and the rebuild accepts an
identifier derived from the born instance, or from none for a question born
before the change. The design text still reads as the row-only key.

## The review content pointer

REQ-A1.10 puts both reviewable kinds' content in the ledger without saying
how a record reaches it. A settled-by-default item now carries its ledger key
(`review.<id>.<window end>`) in its grounds field, and its content pointer
renders as `ledger:<key>` until a revocation points it back at the row.
