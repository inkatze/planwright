# shellcheck shell=bash
# shellcheck disable=SC2034,SC2329 # head and prev are read by the sourcing test
# Collect fixture for the mc-readiness tests, sourced after
# tests/lib/mc-readiness-fixture.sh: two fixture commits, the judgments
# recorded against them, a polish step record, the forge JSON, and a gh stub
# that runs the script's own jq programs over it. After sourcing: head, prev,
# has and hasnt (over the collection in c).

: "${tab:?source tests/lib/mc-readiness-fixture.sh first}" "${tmp:?}" "${repo:?}" "${core:?}" "${repo_root:?}"

c=''
# The polish fixtures below are applied, so the head they began on must be a
# real ancestor of the one they ended on.
git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m zero
prev=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m one
head=$(git -C "$repo" rev-parse HEAD)
rec() { mc_run mc-readiness.sh record --program alpha --repo "$1" --pr "$2" --head "$3" --kind screenshot --ref "$4" --judgment "$5"; }
rec acme/web 7 "$head" shots/home.png error
rec acme/web 7 "$head" shots/home.png ok
rec acme/web 7 "$H" shots/stale.png ok
rec acme/web 8 "$head" shots/other-pr.png ok
(cd "$repo" && PLANWRIGHT_ROOT="$core" /bin/bash "$repo_root/scripts/step-record.sh" new-run >/dev/null \
  && /bin/bash "$repo_root/scripts/step-record.sh" write --run 000001 --point convergence --step polish --kind skill \
    --target polish --hosting isolated --backend none --head "$prev" --end-head "$head" \
    --start 2026-10-28T00:00:07Z --end 2026-10-28T00:01:19Z --outcome applied >/dev/null \
  && /bin/bash "$repo_root/scripts/step-record.sh" write --completion --run 000001 --point convergence --head "$head" >/dev/null) \
  || fail "the fixture step record"
mkdir -p "$tmp/bin"
cat >"$tmp/pr.json" <<EOF
{"headRefOid": "$head", "labels": [{"name": "ui"}], "files": [{"path": "src/app.c"}],
 "body": "## Summary\nAdds the thing.",
 "isDraft": false,
 "statusCheckRollup": [{"name": "build", "conclusion": "SUCCESS", "detailsUrl": "https://github.com/acme/web/actions/runs/111/job/1"},
   {"__typename": "CheckRun", "name": "title", "workflowName": "pr-title", "conclusion": "FAILURE", "startedAt": "2026-11-05T19:34:09Z"},
   {"__typename": "CheckRun", "name": "title", "workflowName": "pr-title", "conclusion": "SUCCESS", "startedAt": "2026-11-05T19:51:51Z"},
   {"__typename": "CheckRun", "name": "title", "workflowName": "pr-title", "conclusion": "FAILURE", "startedAt": "2026-11-05T19:50:18Z"},
   {"__typename": "CheckRun", "name": "title", "workflowName": "other-lint", "conclusion": "FAILURE", "startedAt": "2026-11-05T19:00:00Z"},
   {"__typename": "CheckRun", "name": "rerun", "workflowName": "ci", "conclusion": "SUCCESS", "startedAt": "2026-11-05T19:00:00Z"},
   {"__typename": "CheckRun", "name": "rerun", "workflowName": "ci", "status": "QUEUED", "conclusion": "", "startedAt": "0001-01-01T00:00:00Z", "detailsUrl": "https://github.com/acme/web/actions/runs/222/job/9"},
   {"__typename": "CheckRun", "name": "window-lock", "workflowName": "release-window", "conclusion": "FAILURE", "startedAt": "2026-11-05T19:00:00Z"},
   {"__typename": "CheckRun", "name": "window-lock", "workflowName": "pr-checks", "conclusion": "FAILURE", "startedAt": "2026-11-05T19:00:00Z"},
   {"context": "deploy", "state": "PENDING", "conclusion": ""}]}
EOF
cat >"$tmp/threads.json" <<'EOF'
{"data": {"repository": {"pullRequest": {"author": {"login": "me"},
  "timelineItems": {"nodes": [{"createdAt": "2026-11-18T00:42:21Z"}]},
  "reviewThreads": {"pageInfo": {"hasNextPage": false}, "nodes": [
    {"id": "t1", "isResolved": true, "comments": {"nodes": [{"author": {"__typename": "Bot", "login": "cubic-dev-ai"}}]}},
    {"id": "t2", "isResolved": false, "comments": {"nodes": [{"author": {"__typename": "Bot", "login": "cubic-dev-ai"}},
      {"author": {"__typename": "User", "login": "me"}}]}},
    {"id": "t3", "isResolved": false, "comments": {"nodes": [{"author": {"__typename": "User", "login": "copilot[bot]"}},
      {"author": {"__typename": "User", "login": "alice"}}]}},
    {"id": "t4", "isResolved": false, "comments": {"nodes": [{"author": {"__typename": "User", "login": "alice"}}]}},
    {"id": "t5", "isResolved": false, "comments": {"nodes": [{"author": {"__typename": "Bot", "login": "cubic-dev-ai"}},
      {"author": null}]}}
  ]}}}}}
EOF
cat >"$tmp/runs.json" <<'EOF'
{"workflow_runs": [{"id": 111, "created_at": "2026-11-18T00:42:23Z"}, {"id": 222, "created_at": "2026-11-18T00:42:24Z"}, {"id": 333, "created_at": "2026-11-18T00:00:00Z"}]}
EOF
# The PR-Agent run markers on the pull request: the workflow's at the head and
# at another head, a person's, and two that are no marker.
cat >"$tmp/comments.json" <<EOF
[{"user": {"login": "github-actions[bot]", "type": "Bot"}, "updated_at": "2026-11-18T01:00:00Z",
  "body": "<!-- pr-agent-run: id=4475.3 head=$head status=success -->\nPR-Agent run 4475 reviewed it: success."},
 {"user": {"login": "github-actions[bot]", "type": "Bot"}, "updated_at": "2026-11-18T01:01:00Z",
  "body": "<!-- pr-agent-run: id=4476.1 head=$head status=success -->"},
 {"user": {"login": "github-actions[bot]", "type": "Bot"}, "updated_at": "2026-11-18T00:30:00Z",
  "body": "<!-- pr-agent-run: id=5.1 head=$H status=success -->"},
 {"user": {"login": "alice", "type": "User"}, "updated_at": "2026-11-18T01:02:00Z",
  "body": "<!-- pr-agent-run: id=9.1 head=$head status=success -->"},
 {"user": {"login": "github-actions[bot]", "type": "Bot"}, "updated_at": "2026-11-18T01:03:00Z",
  "body": "Quoting <!-- pr-agent-run: id=6.1 head=$head status=success -->"},
 {"user": {"login": "github-actions[bot]", "type": "Bot"}, "updated_at": "2026-11-18T01:04:00Z",
  "body": "<!-- pr-agent-run: id=x.1 head=$head status=success -->"}]
EOF
printf '%s\n' '{"name": "PR-Agent", "run_started_at": "2026-11-18T00:50:00Z", "status": "completed", "conclusion": "success"}' >"$tmp/attempt-4475-3.json"
printf '%s\n' '{"name": "PR-Agent", "run_started_at": "2026-11-18T00:55:00Z", "status": "in_progress", "conclusion": null}' >"$tmp/attempt-4476-1.json"
# Readable, so a read the collector must not make would show.
for a in 5-1 9-1; do
  printf '%s\n' '{"name": "PR-Agent", "run_started_at": "2026-11-18T00:56:00Z", "status": "completed", "conclusion": "success"}' >"$tmp/attempt-$a.json"
done
cat >"$tmp/bin/gh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/gh.calls"
jqp=""
prev=""
for a in "\$@"; do
  [ "\$prev" = --jq ] && jqp=\$a
  prev=\$a
done
case "\$1 \$2" in
  "pr view") case "\$*" in
    *statusCheckRollup*) exec jq -r "\$jqp" "$tmp/pr.json" ;;
    *headRefOid*) cat "$tmp/headnow"; exit 0 ;;
  esac ;;
  "api graphql") exec jq -r "\$jqp" "$tmp/threads.json" ;;
  "api repos/acme/web/actions/runs?"*) exec jq -r "\$jqp" "$tmp/runs.json" ;;
  "api repos/acme/web/actions/runs/"*/attempts/*)
    a=\${2#repos/acme/web/actions/runs/}
    f="$tmp/attempt-\${a%%/*}-\${a##*/}.json"
    [ -f "\$f" ] && exec jq -r "\$jqp" "\$f" ;;
  "api --paginate") case "\$3" in
    "repos/acme/web/pulls/7/files?"*) [ -f "$tmp/files.json" ] && exec jq -r "\$jqp" "$tmp/files.json" ;;
    "repos/acme/web/issues/7/comments?"*) [ -f "$tmp/comments.json" ] && exec jq -r "\$jqp" "$tmp/comments.json" ;;
  esac ;;
esac
exit 1
EOF
chmod +x "$tmp/bin/gh"
printf '%s\n' "$head" >"$tmp/headnow"
has() { case $c in *"$2"*) ok "$1" ;; *) fail "$1: the collection lacks '$2'" ;; esac }
hasnt() { case $c in *"$2"*) fail "$1: the collection carries '$2'" ;; *) ok "$1" ;; esac }
