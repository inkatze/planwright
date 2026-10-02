# Grade the attended /polish run:
#   * the fix landed with a Planwright-Sign-Off trailer and no retired subject
#     suffix, applied without a question, since a headless run that asked
#     would have committed nothing;
#   * the documented exit status is restored;
#   * the handoff prints the trailered commit's SHA and the trailer-aware log
#     command.
(.is_error == false)
and (.signoff_ids >= 1)
and (.suffixed_commits == 0)
and (.exit_fixed == true)
and (.signoff_sha7 != "")
and ((.result // "") | test("trailers:key=Planwright-Sign-Off"))
and (.signoff_sha7 as $s | (.result // "") | contains($s))
