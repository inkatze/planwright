# Grade the refusal of a non-Ready/non-Active (Draft) spec (D-12):
#   * no dispatch record — neither a marker nor a task branch was created;
#   * the refusal is surfaced and explains why (Draft / not Ready-or-Active /
#     spec-kickoff), rather than a silent no-op.
(.marker_written == false)
and (.branch_created == false)
and (.result | test("draft|not ready|ready or active|spec-kickoff|refus"; "i"))
