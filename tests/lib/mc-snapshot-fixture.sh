# shellcheck shell=bash
# shellcheck disable=SC2034 # tab, head1 and head2 are read by the sourcing test
# Shared fixture for the snapshot seam tests, sourced after
# tests/lib/mission-control-fixture.sh: a gh shim on PATH that logs each call
# and runs the forge adapter's own jq program over a fixture GraphQL page,
# the shipped forge adapter reached from the fixture core root, a second
# source's fixture adapter, and setup [polls-per-hour] for program alpha.
# After sourcing: gh_calls <pattern>, tracker_reads, head1, head2, tab.

: "${tmp:?}" "${core:?}" "${repo:?}" "${tracked:?}" "${repo_root:?}" "${fleet:?source mission-control-fixture.sh first}"

tab=$(printf '\t')
head1=1111111111111111111111111111111111111111
head2=2222222222222222222222222222222222222222

# The gh shim: logs every call; serves the repository name, a GraphQL page
# as JSON run through the adapter's own --jq program (by jq, which gh embeds),
# and a diff. GH_REMAINING sets the reported rate-limit headroom; GH_LIMITED
# makes every call a rate-limit refusal; GH_DIFF_FAIL makes diff reads fail.
command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to run the forge adapter's jq program" >&2
  exit 1
}
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$1 $2" >>"$GH_LOG"
if [ -n "${GH_LIMITED:-}" ]; then
  echo "API rate limit exceeded for user" >&2
  exit 1
fi
case "$1 $2" in
  "repo view") echo "acme/widgets" ;;
  "api graphql")
    expr=""
    while [ $# -gt 0 ]; do
      [ "$1" = --jq ] && expr=$2
      shift
    done
    sed -e "s/@HEAD@/$GH_HEAD/g" -e "s/@REMAINING@/${GH_REMAINING:-4000}/" "$GH_PAGE" | jq -r "$expr"
    ;;
  "pr diff")
    if [ -n "${GH_DIFF_FAIL:-}" ]; then
      echo "HTTP 406: the diff exceeded the maximum number of lines" >&2
      exit 1
    fi
    printf 'diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+%s\n' "$3"
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
# The reset 1970-04-15T04:00:00Z is epoch 9000000. #7 is the viewer's, with
# two of its three threads open; #9 is another author's draft with no
# decision and no checks.
cat >"$tmp/page.json" <<'EOF'
{"data": {"rateLimit": {"remaining": @REMAINING@, "resetAt": "1970-04-15T04:00:00Z"},
 "viewer": {"login": "me"},
 "repository": {"pullRequests": {"nodes": [
  {"number": 7, "headRefOid": "@HEAD@", "isDraft": false, "mergeable": "MERGEABLE",
   "reviewDecision": "APPROVED", "author": {"login": "me"},
   "reviewThreads": {"nodes": [{"isResolved": false}, {"isResolved": true}, {"isResolved": false}]},
   "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "SUCCESS"}}}]},
   "reviews": {"totalCount": 3}, "comments": {"totalCount": 4}},
  {"number": 9, "headRefOid": "@HEAD@", "isDraft": true, "mergeable": "UNKNOWN",
   "reviewDecision": null, "author": {"login": "other"},
   "reviewThreads": {"nodes": []},
   "commits": {"nodes": [{"commit": {"statusCheckRollup": null}}]},
   "reviews": {"totalCount": 0}, "comments": {"totalCount": 1}}]}}}}
EOF
GH_LOG="$tmp/gh.log"
GH_PAGE="$tmp/page.json"
GH_HEAD=$head1
export GH_LOG GH_PAGE GH_HEAD
PATH="$tmp/bin:$PATH"
export PATH

gh_calls() { if [ -f "$GH_LOG" ]; then grep -c "$1" "$GH_LOG"; else echo 0; fi; }

# The shipped forge adapter, reached from the fixture core root.
mkdir -p "$core/scripts"
cat >"$core/scripts/mc-adapter-forge.sh" <<EOF
#!/bin/sh
exec /bin/bash '$repo_root/scripts/mc-adapter-forge.sh' "\$@"
EOF
# A second source's fixture adapter, resolved from the program's repository:
# counts its reads; TRACKER_RL prints a rate-limit line; TRACKER_EXIT sets
# its exit.
mkdir -p "$repo/scripts"
cat >"$repo/scripts/tracker-adapter.sh" <<'EOF'
#!/bin/sh
printf 'read\n' >>"$TRACKER_LOG"
out=""
while [ $# -gt 0 ]; do
  [ "$1" = --out ] && out=$2
  shift
done
printf 'item\tT-1\topen\n' >"$out"
[ -z "${TRACKER_RL:-}" ] || printf 'ratelimit\t%s\n' "$TRACKER_RL"
exit "${TRACKER_EXIT:-0}"
EOF
TRACKER_LOG="$tmp/tracker.log"
export TRACKER_LOG
tracker_reads() { if [ -f "$TRACKER_LOG" ]; then wc -l <"$TRACKER_LOG" | tr -d ' '; else echo 0; fi; }

# setup [budget]: program alpha mapping code-state to the forge and work-items
# to the fixture tracker, the tracker's adapter registered by overlay.
setup() {
  reset_mc_fixture
  rm -rf "$fleet" "$GH_LOG" "$TRACKER_LOG"
  cat >"$repo/.claude/catalogs/snapshot-adapters.yaml" <<'EOF'
adapters:
  - id: tracker
    summary: "A fixture tracker"
    script: scripts/tracker-adapter.sh
    cadence: 10m
EOF
  cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_sources: {code-state: forge:snapshot, work-items: tracker:snapshot, decisions: specs:record}
program_alpha_budget: {polls_per_hour: ${1:-100}, host_load: 1000000}
EOF
}
