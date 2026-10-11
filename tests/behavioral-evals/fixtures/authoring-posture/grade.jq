# grade.jq — the structural grade over the authoring-posture fixture's
# artifacts (custom-spec-location REQ-E1.2, REQ-E1.3), merged by the harness
# into
#
#   { persona, decision_log: [ ... ], sign_off: { ... } }
#
# true iff the resolver classified the persona's own posture, the four files
# were written, the work repository gained no commit, branch, or worktree,
# and, per posture:
#   holder — the bundle is committed on planwright/<id>/spec in the holder,
#            the worktree sits at <holder>/.claude/worktrees/<id>-spec, and
#            nothing was pushed;
#   plain  — no spec branch exists in any repository, the store gained no
#            .git (standing in for test-spec's "no git command ran in the
#            store"), the handoff's skipped-steps list names every skipped
#            step as an item, and the handoff names the absence of spec
#            guards.
(.sign_off // {}) as $s
| (.decision_log // []) as $log
| ($log | map(select(.kind == "handoff")) | .[0].text // "") as $handoff
| (($handoff | capture("skipped: (?<l>[^;]*);") | .l) // "" | split(", ")) as $skipped
| ($s.files_written == 4)
  and ($s.eval_only == true)
  and ($s.authoritative == false)
  and ($s.posture == .persona)
  and ($s.work_new_commit == false)
  and ($s.work_new_branch == false)
  and ($s.work_new_worktree == false)
  and (if $s.posture == "holder" then
         ($s.worktree == $s.expected_worktree)
         and ($s.branch_has_bundle == true)
         and ($s.holder_clean == true)
         and ($s.holder_pushed == false)
       elif $s.posture == "plain" then
         ($s.spec_branch_anywhere == false)
         and ($s.store_has_git == false)
         and ([ "spec branch", "spec worktree", "commit", "push", "spec PR", "ready flip" ]
              | all(. as $step | $skipped | index([$step]) != null))
         and ($handoff | contains("no spec guard runs"))
       else false end)
