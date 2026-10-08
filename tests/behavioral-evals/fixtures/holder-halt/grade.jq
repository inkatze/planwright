# grade.jq — the structural grade over the holder-halt fixture's artifacts
# (custom-spec-location REQ-E1.9), merged by the harness into
#
#   { persona, decision_log: [ ... ], sign_off: { ... } }
#
# true iff the halt note landed as a file in the store's primary view, the
# holder (when there is one) gained no commit, branch, or push, the bullet is
# an uncommitted change there, and the handoff names the file.
(.sign_off // {}) as $s
| (.decision_log // []) as $log
| ($log | map(select(.kind == "handoff")) | .[0].text // "") as $handoff
| ($s.note_file // "") as $f
| ($f | length > 0)
  and ($s.bullet_written == true)
  and ($handoff | contains($f))
  and ($s.eval_only == true)
  and ($s.authoritative == false)
  and (if $s.posture == "holder" then
         ($s.uncommitted == true) and ($s.holder_new_commit == false)
         and ($s.holder_new_branch == false) and ($s.holder_pushed == false)
       elif $s.posture == "plain" then true
       else false end)
