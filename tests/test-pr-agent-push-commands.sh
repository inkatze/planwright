#!/bin/bash
# Tests for scripts/pr-agent-push-commands.sh, which picks the review PR-Agent
# runs on a push: incremental, or full when a merge commit is among the
# commits an incremental review would take in. A gh stub serves fixture
# comment and commit lists; no GitHub API is ever called.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REAL="$here/../scripts/pr-agent-push-commands.sh"
WORKFLOW="$here/../.github/workflows/pr-agent.yml"
failures=0

[ -x "$REAL" ] || {
  echo "FAIL: scripts/pr-agent-push-commands.sh missing or not executable" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to run the script's jq programs" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"
mkdir -p "$stub" "$tmp/scripts"
SCRIPT="$tmp/scripts/pr-agent-push-commands.sh"
cp "$REAL" "$here/../scripts/bounded-run.sh" "$tmp/scripts/"

# The gh stub serves $T/comments.json for the PR's comment list and
# $T/commits.json for its commit list, running the script's own --jq program;
# FAIL_COMMENTS or FAIL_COMMITS makes that read fail as an API error does.
# A fixture that is a list of lists is a paginated response: like gh, the stub
# runs the program once per page with --paginate, and serves the first page
# alone without it.
cat >"$stub/gh" <<'EOF'
#!/bin/sh
[ "$1" = api ] || exit 64
shift
path="" filter="" paginate=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --paginate) paginate=1; shift ;;
    --jq) filter=$2; shift 2 ;;
    -*) exit 64 ;;
    *) path=$1; shift ;;
  esac
done
printf '%s\n' "$path" >>"$T/gh.log"
case "$path" in
  repos/o/r/issues/7/comments*)
    [ "${FAIL_COMMENTS:-0}" = 1 ] && { printf '{"message": "Server Error"}\n'; exit 1; }
    file=$T/comments.json
    ;;
  repos/o/r/pulls/7/commits*)
    [ "${FAIL_COMMITS:-0}" = 1 ] && { printf '{"message": "Server Error"}\n'; exit 1; }
    file=$T/commits.json
    ;;
  *) exit 65 ;;
esac
[ "$(jq -r 'if length > 0 and (.[0] | type) == "array" then "pages" else "one" end' "$file")" = pages ] \
  || exec jq -r "$filter" "$file"
pages=$(jq length "$file")
[ "$paginate" = 1 ] || pages=1
i=0
while [ "$i" -lt "$pages" ]; do
  jq -c ".[$i]" "$file" | jq -r "$filter" || exit 1
  i=$((i + 1))
done
EOF
chmod +x "$stub/gh"

ok() { printf 'ok   %s\n' "$1"; }
failed() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}
# annotated <name> <title>: pass when the last run printed that annotation.
annotated() {
  if grep -q "^$2" <<<"$OUT"; then ok "$1"; else failed "$1: no '$2' annotation in: $OUT"; fi
}

# comment <id> <login> <created_at> <body>: one issue comment as JSON.
comment() {
  jq -cn --argjson id "$1" --arg login "$2" --arg at "$3" --arg body "$4" \
    '{id: $id, user: {login: $login}, created_at: $at, updated_at: $at, body: $body}'
}
# commit <parents> <committer date>: one PR commit as JSON.
commit() {
  jq -cn --argjson n "$1" --arg at "$2" \
    '{sha: "x", parents: [range($n) | {sha: "p"}], commit: {committer: {date: $at}, message: "m"}}'
}
# list <json line>...: a JSON array of the given objects.
list() { printf '%s\n' "$@" | jq -s .; }

FULL_REVIEW='## PR Reviewer Guide
<!-- pr-agent:review:full -->'
INC_REVIEW='## Incremental PR Reviewer Guide
<!-- pr-agent:review:incremental -->'
BOT='github-actions[bot]'

# run_case <name> <want: full|incremental> [<env assignment>...]: run the
# script against $T's fixtures and check the commands it wrote.
run_case() {
  local name=$1 want=$2 got rc=0
  shift 2
  : >"$T/output"
  OUT=$(env "$@" T="$T" PATH="$stub:$PATH" GITHUB_REPOSITORY=o/r "$SCRIPT" --pr 7 --output "$T/output" 2>&1) || rc=$?
  got=$(sed -n 's/^commands=//p' "$T/output")
  case "$want" in
    full) want='["/review"]' ;;
    incremental) want='["/review -i"]' ;;
  esac
  if [ "$rc" != 0 ]; then
    failed "$name: exit $rc: $OUT"
  elif [ "$got" != "$want" ] || [ "$(grep -c . "$T/output")" != 1 ]; then
    failed "$name: wrote [$(cat "$T/output")], want commands=$want"
  else
    return 0
  fi
  return 1
}

# new_case: a fresh fixture directory, with the full review persistent comment
# PR-Agent created at 2026-11-14T06:43:23Z (edited in place since, which does
# not move its created_at) and no commits yet.
new_case() {
  T=$(mktemp -d "$tmp/case.XXXXXX")
  list "$(comment 1 "$BOT" 2026-11-14T06:43:23Z "$FULL_REVIEW")" >"$T/comments.json"
  list >"$T/commits.json"
}

name="an ordinary push after the last review keeps the incremental review"
new_case
list "$(commit 1 2026-11-14T06:32:36Z)" "$(commit 1 2026-11-16T10:39:45Z)" "$(commit 1 2026-11-16T10:49:37Z)" >"$T/commits.json"
run_case "$name" incremental && ok "$name"

name="a merge commit at the head gets a full review"
new_case
list "$(commit 1 2026-11-14T06:32:36Z)" "$(commit 2 2026-11-16T10:04:51Z)" >"$T/commits.json"
run_case "$name" full && annotated "$name" '::notice title=PR-Agent full review::'

# The shape that timed out live: a merge from main, then two ordinary commits,
# all newer than the review, so the head itself is no merge.
name="a merge below the head but inside the incremental range gets a full review"
new_case
list "$(commit 1 2026-11-14T06:32:36Z)" "$(commit 2 2026-11-16T10:04:51Z)" \
  "$(commit 1 2026-11-16T10:39:45Z)" "$(commit 1 2026-11-16T10:49:37Z)" >"$T/commits.json"
run_case "$name" full && ok "$name"

name="a merge older than the last review stays out of the range"
new_case
list "$(commit 2 2026-11-14T06:00:00Z)" "$(commit 1 2026-11-14T06:32:36Z)" "$(commit 1 2026-11-16T10:49:37Z)" >"$T/commits.json"
run_case "$name" incremental && ok "$name"

# PR-Agent walks back from the head and stops at the first commit no newer
# than the review, so a newer-dated merge below that commit is out of range.
name="the range ends at the first commit no newer than the review, as PR-Agent's does"
new_case
list "$(commit 2 2026-11-16T09:00:00Z)" "$(commit 1 2026-11-14T06:32:36Z)" "$(commit 1 2026-11-16T10:49:37Z)" >"$T/commits.json"
run_case "$name" incremental && ok "$name"

name="a commit dated exactly at the review is not newer than it"
new_case
list "$(commit 2 2026-11-14T06:43:23Z)" "$(commit 1 2026-11-16T10:49:37Z)" >"$T/commits.json"
run_case "$name" incremental && ok "$name"

name="the newest review comment, an incremental one, anchors the range"
new_case
list "$(comment 1 "$BOT" 2026-11-14T06:43:23Z "$FULL_REVIEW")" \
  "$(comment 2 "$BOT" 2026-11-16T10:10:00Z "$INC_REVIEW")" >"$T/comments.json"
list "$(commit 2 2026-11-16T10:04:51Z)" "$(commit 1 2026-11-16T10:49:37Z)" >"$T/commits.json"
run_case "$name" incremental && ok "$name"

name="other comments, a human's carrying the marker included, never anchor the range"
new_case
list "$(comment 1 "$BOT" 2026-11-14T06:43:23Z "$FULL_REVIEW")" \
  "$(comment 2 "$BOT" 2026-11-16T10:30:00Z '<!-- pr-agent-run: id=1.1 head=x status=success -->')" \
  "$(comment 3 someone 2026-11-16T10:30:00Z "quoting $INC_REVIEW")" >"$T/comments.json"
list "$(commit 2 2026-11-16T10:04:51Z)" "$(commit 1 2026-11-16T10:49:37Z)" >"$T/commits.json"
run_case "$name" full && ok "$name"

# PR-Agent anchors on a marker only as a whole line among a comment's first
# five, in either stored form, or on a legacy header the comment starts with.
name="a review comment anchors by any form PR-Agent matches, and only those"
legacy_ok=1
for body in '## PR Reviewer Guide 🔍
no marker' '## Incremental PR Reviewer Guide
no marker' '## Guide
  <!-- pr-agent:review:incremental -->  ' '## Guide
[pr-agent:review:full]: https://github.com/The-PR-Agent/pr-agent'; do
  new_case
  list "$(comment 1 "$BOT" 2026-11-14T06:43:23Z "$FULL_REVIEW")" \
    "$(comment 2 "$BOT" 2026-11-16T10:10:00Z "$body")" >"$T/comments.json"
  list "$(commit 2 2026-11-16T10:04:51Z)" "$(commit 1 2026-11-16T10:49:37Z)" >"$T/commits.json"
  run_case "$name: [$body]" incremental || legacy_ok=0
done
for body in 'a
b
c
d
e
<!-- pr-agent:review:incremental -->' 'see <!-- pr-agent:review:incremental --> here' '<!-- pr-agent:review:fullish -->'; do
  new_case
  list "$(comment 1 "$BOT" 2026-11-14T06:43:23Z "$FULL_REVIEW")" \
    "$(comment 2 "$BOT" 2026-11-16T10:10:00Z "$body")" >"$T/comments.json"
  list "$(commit 2 2026-11-16T10:04:51Z)" "$(commit 1 2026-11-16T10:49:37Z)" >"$T/commits.json"
  run_case "$name: not [$body]" full || legacy_ok=0
done
[ "$legacy_ok" = 1 ] && ok "$name"

name="with no review yet the push keeps the incremental command (PR-Agent reviews in full itself)"
new_case
list "$(comment 2 someone 2026-11-14T06:43:23Z hello)" >"$T/comments.json"
list "$(commit 2 2026-11-16T10:04:51Z)" >"$T/commits.json"
if run_case "$name" incremental; then
  if grep -q 'pulls/7/commits' "$T/gh.log"; then failed "$name: read the commits anyway"; else ok "$name"; fi
fi

name="a failed comment read falls back to the full review, with a warning"
new_case
run_case "$name" full FAIL_COMMENTS=1 && annotated "$name" '::warning title=PR-Agent full review::'

name="a failed commit read falls back to the full review, with a warning"
new_case
list "$(commit 1 2026-11-16T10:49:37Z)" >"$T/commits.json"
run_case "$name" full FAIL_COMMITS=1 && annotated "$name" '::warning title=PR-Agent full review::'

name="a commit with no committer date is placed by its author date, as PR-Agent places it"
new_case
list "$(commit 2 2026-11-14T06:00:00Z)" \
  '{"parents": [{"sha": "p"}], "commit": {"committer": null, "author": {"date": "2026-11-16T10:49:37Z"}}}' >"$T/commits.json"
run_case "$name" incremental && ok "$name"

name="a commit list in a shape the script cannot read falls back to the full review"
new_case
printf '[{"parents": [], "commit": {"committer": {"date": "16 Nov 2026"}}}]\n' >"$T/commits.json"
run_case "$name" full && annotated "$name" '::warning title=PR-Agent full review::'

name="an empty commit list beside a review falls back to the full review"
new_case
run_case "$name" full && annotated "$name" '::warning title=PR-Agent full review::'

name="a comment list in a shape the script cannot read falls back to the full review"
new_case
list "$(comment 1 "$BOT" yesterday "$FULL_REVIEW")" >"$T/comments.json"
run_case "$name" full && annotated "$name" '::warning title=PR-Agent full review::'

name="the newest review comment is found across comment pages"
new_case
printf '[%s,%s]\n' "$(list "$(comment 1 "$BOT" 2026-11-14T06:43:23Z "$FULL_REVIEW")")" \
  "$(list "$(comment 2 "$BOT" 2026-11-16T10:10:00Z "$INC_REVIEW")")" >"$T/comments.json"
list "$(commit 2 2026-11-16T10:04:51Z)" "$(commit 1 2026-11-16T10:49:37Z)" >"$T/commits.json"
run_case "$name" incremental && ok "$name"

name="a merge on a later commit page is in range"
new_case
printf '[%s,%s]\n' "$(list "$(commit 1 2026-11-14T06:00:00Z)" "$(commit 1 2026-11-16T10:30:00Z)")" \
  "$(list "$(commit 2 2026-11-16T10:40:00Z)" "$(commit 1 2026-11-16T10:49:37Z)")" >"$T/commits.json"
run_case "$name" full && ok "$name"

name="the choice is appended to the output file, never over it"
new_case
list "$(commit 1 2026-11-16T10:49:37Z)" >"$T/commits.json"
printf 'earlier=1\n' >"$T/output"
RC=0
env T="$T" PATH="$stub:$PATH" GITHUB_REPOSITORY=o/r "$SCRIPT" --pr 7 --output "$T/output" >/dev/null 2>&1 || RC=$?
if [ "$RC" = 0 ] && [ "$(cat "$T/output")" = 'earlier=1
commands=["/review -i"]' ]; then ok "$name"; else failed "$name: exit $RC, wrote [$(cat "$T/output")]"; fi

name="an unwritable output file exits 1"
new_case
RC=0
OUT=$(env T="$T" PATH="$stub:$PATH" GITHUB_REPOSITORY=o/r "$SCRIPT" --pr 7 --output "$T/no-such-dir/out" 2>&1) || RC=$?
if [ "$RC" = 1 ]; then ok "$name"; else failed "$name: exit $RC, want 1: $OUT"; fi

for usage in "--output x" "--pr 7" "--pr 0 --output x" "--pr x7 --output x" "--pr 07 --output x" "--pr 1234567890 --output x" "--pr 7 --output x --bogus"; do
  name="usage error: $usage"
  RC=0
  # shellcheck disable=SC2086 # the case's words split on purpose
  OUT=$(cd "$tmp" && env PATH="$stub:$PATH" GITHUB_REPOSITORY=o/r "$SCRIPT" $usage 2>&1) || RC=$?
  if [ "$RC" = 2 ] && [ ! -e "$tmp/x" ]; then ok "$name"; else failed "$name: exit $RC, want 2, and no output: $OUT"; fi
done

name="usage error: no GITHUB_REPOSITORY"
RC=0
OUT=$(env -u GITHUB_REPOSITORY PATH="$stub:$PATH" "$SCRIPT" --pr 7 --output "$tmp/out" 2>&1) || RC=$?
if [ "$RC" = 2 ]; then ok "$name"; else failed "$name: exit $RC, want 2: $OUT"; fi

# The workflow runs the chooser on a push only, after the checkout that brings
# it, and the Review step takes its choice with the incremental command as the
# default for every other event.
name="the workflow wires the push chooser into the Review step"
step() { awk -v s="      - name: $1" '/^      - name: / { on = ($0 == s) } on' "$WORKFLOW"; }
push=$(step "Choose the push review")
review=$(step "Review")
missing=""
# shellcheck disable=SC2016 # the workflow's literal text
for want in '        id: push' "        if: env.HAS_KEY == 'true' && github.event.action == 'synchronize'" \
  'scripts/pr-agent-push-commands.sh --pr "$PR" --output "$GITHUB_OUTPUT"' \
  'GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}' 'PR: ${{ github.event.pull_request.number }}' '        timeout-minutes: '; do
  case "$push" in *"$want"*) ;; *) missing="$missing [push step: $want]" ;; esac
done
# shellcheck disable=SC2016 # the workflow's literal text
case "$review" in
  *"GITHUB_ACTION_CONFIG__PUSH_COMMANDS: \${{ steps.push.outputs.commands || '[\"/review -i\"]' }}"*) ;;
  *) missing="$missing [Review step: PUSH_COMMANDS from the push step]" ;;
esac
order=$(sed -n 's/^      - name: //p' "$WORKFLOW" | grep -nx -e 'Check out the review wrapper' -e 'Choose the push review' -e 'Review' | cut -d: -f2 | tr '\n' ,)
[ "$order" = "Check out the review wrapper,Choose the push review,Review," ] || missing="$missing [step order: $order]"
if [ -z "$missing" ]; then ok "$name"; else failed "$name: missing$missing"; fi

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all pr-agent-push-commands tests passed"
