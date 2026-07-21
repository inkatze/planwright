# grade.jq — the structural (invariant) grade over the greeter fixture's durable
# artifacts (operator-dialogue Task 5; REQ-G1.3). It reads the artifacts the run
# WROTE — never a scraped pane — merged by the harness into one object:
#
#   { persona: "<name>",
#     decision_log: [ {turn, question, answer, depth?}, ... ],
#     sign_off: { subject, decision, depth, eval_only, authoritative } }
#
# It yields a single boolean: true iff the run produced a well-formed, complete,
# eval-only sign-off and a non-empty decision log. Experiential quality (was the
# teaching pitched well?) is NOT graded here — that is the independent grader's
# and the human's job (REQ-G1.4, REQ-H1.3). This is only the mechanical floor.
#
# jq is a pure data transform: the artifact values are inspected, never executed.
(.sign_off // {}) as $s
| (.decision_log // []) as $log
| ($log | length) > 0
  and ($s.eval_only == true)
  and ($s.authoritative == false)
  and (($s.subject // "") | length > 0)
  and (($s.decision // "") | length > 0)
