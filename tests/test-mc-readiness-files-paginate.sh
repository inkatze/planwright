#!/bin/bash
# Tests for scripts/mc-readiness.sh collect: a pull request's changed files
# are read past the first page, and an incomplete list is still refused.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-readiness-files-paginate.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

# shellcheck source=tests/lib/mc-readiness-fixture.sh
. "$here/lib/mc-readiness-fixture.sh"
# shellcheck source=tests/lib/mc-readiness-collect-fixture.sh
. "$here/lib/mc-readiness-collect-fixture.sh"

: >"$tmp/no-cond"
cp "$tmp/pr.json" "$tmp/pr.json.base"
# nodes <from> <to>: the file nodes cards/card-<from>.md to cards/card-<to>.md.
nodes() { jq -n --argjson a "$1" --argjson b "$2" '[range($a; $b + 1) | {path: ("cards/card-\(.).md"), changeType: "MODIFIED"}]'; }
# forge <first-page files> <changedFiles or -> : the pull request view, which
# carries at most the first page of files, and the total the forge counts.
forge() {
  jq --argjson f "$1" --arg t "$2" '.files = $f | if $t == "-" then del(.changedFiles) else .changedFiles = ($t | tonumber) end' \
    "$tmp/pr.json.base" >"$tmp/pr.json"
}
# page <n> <from> <to> <hasNextPage>: one page of the files connection.
page() {
  nodes "$2" "$3" | jq --argjson more "$4" '{data: {repository: {pullRequest: {files: {pageInfo: {hasNextPage: $more, endCursor: "c"}, nodes: .}}}}}' >"$tmp/files-page-$1.json"
}
collect() { # collect <label>: collect into c, then walk it with no conditions
  : >"$tmp/gh.calls"
  PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --worktree "$repo" --out "$tmp/collected"
  expect_rc "collect $1" 0
  c=$(cat "$tmp/collected" 2>/dev/null)
  mc_run mc-readiness.sh walk --evidence "$tmp/collected" --conditions "$tmp/no-cond"
}
paths() { printf '%s\n' "$c" | grep -c "^path${tab}"; }

# 134 changed files: the view holds the first 100, the walk reads both pages.
forge "$(nodes 1 100)" 134
page 1 1 100 true
page 2 101 134 false
collect "over 134 changed files"
hasnt "a list read whole past its first page is not truncated" "truncated${tab}files"
expect_no_out "and the walk does not refuse it as truncated" "fail${tab}truncated"
if [ "$(paths)" -eq 134 ]; then ok "every changed file is collected"; else fail "expected 134 paths, got $(paths)"; fi
has "a file past the first page is collected" "path${tab}cards/card-134.md${tab}MODIFIED"
n_dup=$(printf '%s\n' "$c" | grep -c "^path${tab}cards/card-1.md${tab}")
if [ "$n_dup" -eq 1 ]; then ok "the first page is not collected twice"; else fail "expected one cards/card-1.md path, got $n_dup"; fi
if grep -q -- '^api graphql --paginate ' "$tmp/gh.calls"; then ok "the file list is walked page by page when the view holds fewer than the forge counts"; else fail "the file list was not walked page by page"; fi

# The walk fails part way: what it printed before failing never stands.
mv "$tmp/files-page-2.json" "$tmp/files-page-2.fail"
collect "when the file walk fails part way"
has "a walk that fails part way is truncated" "truncated${tab}files"
expect_out "and the walk refuses it" "fail${tab}truncated${tab}the files read"
if [ "$(paths)" -eq 100 ]; then ok "the failed walk's partial pages are not collected"; else fail "expected the view's 100 paths, got $(paths)"; fi
rm -f "$tmp/files-page-2.fail"

# The walk succeeds but comes back short of the forge's count.
page 2 101 134 false
forge "$(nodes 1 100)" 140
collect "when the walk comes back short"
has "a walked list shorter than the forge's count is truncated" "truncated${tab}files"
expect_out "and the walk refuses it" "fail${tab}truncated${tab}the files read"
if [ "$(paths)" -eq 100 ]; then ok "and the view's paths stand"; else fail "expected the view's 100 paths, got $(paths)"; fi

# Every path printed, then a failure: the exit status alone refuses it.
forge "$(nodes 1 100)" 134
: >"$tmp/files-page-3.fail"
collect "when the walk fails after its last page printed"
has "a walk that printed every path but failed is truncated" "truncated${tab}files"
rm -f "$tmp/files-page-3.fail"

# Paths are counted once: a repeat cannot pad the count up to the forge's.
page 2 100 133 false
collect "when a page repeats a path"
has "a repeated path does not count twice toward the forge's count" "truncated${tab}files"
page 2 100 134 false
collect "when pages overlap"
hasnt "overlapping pages that hold every path once are whole" "truncated${tab}files"
if [ "$(paths)" -eq 134 ]; then ok "and each path is collected once"; else fail "expected 134 paths, got $(paths)"; fi

# A rename past the first page still gets its source from the REST list.
jq '.data.repository.pullRequest.files.nodes[-1].changeType = "RENAMED"' "$tmp/files-page-2.json" >"$tmp/page.json" && mv "$tmp/page.json" "$tmp/files-page-2.json"
printf '%s\n' '[{"filename": "cards/card-134.md", "status": "renamed", "previous_filename": "old/card-134.md"}]' >"$tmp/files.json"
collect "when a walked file is a rename"
has "a walked rename carries its source" "path${tab}cards/card-134.md${tab}RENAMED${tab}old/card-134.md"
rm -f "$tmp/files.json"

# More paths than the forge counts is no whole list either.
forge "$(nodes 1 100)" 130
collect "when the walk returns more than the forge counts"
has "a walk past the forge's count is truncated" "truncated${tab}files"

# No count from the forge: the list cannot be known whole.
forge "$(nodes 1 100)" -
collect "when the forge gives no count"
has "a list the forge gives no count for is truncated" "truncated${tab}files"
expect_out "and the walk refuses it" "fail${tab}truncated${tab}the files read"
if grep -q 'files(first' "$tmp/gh.calls"; then fail "a list with no count to meet was walked"; else ok "a list with no count to meet is not walked"; fi

# Exactly 100 changed files: the view is whole, no walk is needed.
forge "$(nodes 1 100)" 100
collect "over exactly 100 changed files"
hasnt "a full first page the forge's count matches is not truncated" "truncated${tab}files"
if grep -q 'files(first' "$tmp/gh.calls"; then fail "a whole view had its file list walked"; else ok "a whole view is not walked again"; fi

if [ "$failures" -ne 0 ]; then
  echo "test-mc-readiness-files-paginate: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-readiness-files-paginate: all passed"
