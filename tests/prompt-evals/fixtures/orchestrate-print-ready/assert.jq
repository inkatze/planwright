# Grade the print-backend dispatch of the one Ready unit (D-12):
#   * correct unit selected + launch command printed — the result names the
#     /execute-task launch for the demo spec;
#   * dispatch marker written — the Task 1 marker landed at the path contract;
#   * the run did not error.
# The marker is the deterministic signal; the text check confirms the launch
# command surfaced. "task 1" / "task-1" tolerates either phrasing.
(.is_error == false)
and (.marker_written == true)
and (.result | test("execute-task"; "i"))
and (.result | test("task[ -]?1|demo"; "i"))
