#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh's gh api classification
# (REQ-G1.7, REQ-G1.8): the classified acts deny at both tiers with no read, a
# protected-ref write reads only the protected set, a request the guard
# cannot read denies before any read, a readable request outside the acts
# defers, and a session with no tier profile defers on every one. The shared
# fixture lines pin the same spellings across every copy in
# tests/test-reserved-control-spellings.sh; this suite owns the read-count and
# message assertions.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"

echo "# gh api: the classified acts deny with no read"
q() { printf "gh api graphql -f query='mutation{%s(input:{pullRequestId:\"PR_x\"}){clientMutationId}}'" "$1"; }
CLASSIFIED=(
  "$(q markPullRequestReadyForReview)" "$(q convertPullRequestToDraft)" "$(q mergePullRequest)"
  "$(q enablePullRequestAutoMerge)" "$(q enqueuePullRequest)" "$(q mergeBranch)" "$(q updatePullRequestBranch)"
  'gh api -X PUT repos/acme/widgets/pulls/42/merge' 'gh api --method PUT repos/acme/widgets/pulls/42/merge'
  'gh api -XPUT repos/acme/widgets/pulls/42/merge' 'gh api --method=PUT /repos/acme/widgets/pulls/42/merge'
  'gh api -X put https://api.github.com/repos/acme/widgets/pulls/42/merge'
  'gh api -X PUT https://ghe.example/api/v3/repos/acme/widgets/pulls/42/merge?x=1#y'
  'gh api -iXPUT repos/{owner}/{repo}/pulls/42/merge' 'gh api -X=PUT repos/acme/widgets/pulls/42/merge'
  'gh api -X GET -X PUT repos/acme/widgets/pulls/42/merge'
  'gh api repos/acme/widgets/merges -f base=feature -f head=main'
  'gh api -X PUT repos/acme/widgets/pulls/42/update-branch' 'gh api repos/acme/widgets/merge-upstream -f branch=x'
  'gh api -X PATCH repos/acme/widgets/git/refs/heads/feature -f sha=abc -F force=true'
  "gh api graphql -f query='mutation{updateRefs(input:{repositoryId:\"R\",refUpdates:[]}){clientMutationId}}'"
  "gh api graphql -f query='mutation{updateRef(input:{refId:\"R\",oid:\"a\",force:true}){clientMutationId}}'"
  "gh api graphql -f query='mutation M{a:mergePullRequest(input:{pullRequestId:\"x\"}){clientMutationId}}'"
  "gh api graphql -f query='mutation{merge''PullRequest(input:{pullRequestId:\"x\"}){clientMutationId}}'"
  "gh api graphql -f query='# mergePullRequest
query{viewer{login}}'"
  'gh api -X GET search/issues -f q=mergePullRequest'
  "gh api graphql -f query='query{viewer{login}}' -f note='mergePullRequest'"
)
for tier in worker tower; do
  for cmd in "${CLASSIFIED[@]}"; do
    pg "$tier" "$cmd"
    expect deny "[$tier] $cmd"
    reads none "[$tier] no read: $cmd"
  done
done
pg worker "$(q markPullRequestReadyForReview)"
reason_has 'gh pr ready <number>' "the gh api flip deny names gh pr ready as the remedy"
pg worker 'gh api -X PUT repos/acme/widgets/pulls/42/update-branch'
reason_has 'converge-sync-main' "the gh api base-merge deny names the sync helper as the remedy"

echo "# gh api: protected-ref writes read only the protected set"
set_knobs 'protected_branches:'
for tier in worker tower; do
  for cmd in 'gh api -X PATCH repos/acme/widgets/git/refs/heads/main -f sha=abc' \
    'gh api -X DELETE repos/acme/widgets/git/refs/heads/planwright/demo/spec' \
    'gh api repos/acme/widgets/git/refs -f ref=refs/heads/master -f sha=abc' \
    'gh api -X PUT repos/acme/widgets/contents/README.md -f message=m -f content=eA== -f branch=main' \
    'gh api -X POST repos/acme/widgets/branches/main/rename -f new_name=old' \
    'gh api -X POST repos/acme/widgets/branches/feature/rename -f new_name=main' \
    'gh api -X POST repos/acme/widgets/branches/feature/rename -f new_name=planwright/demo/spec' \
    "gh api graphql -f query='mutation{createCommitOnBranch(input:{branch:{repositoryNameWithOwner:\"acme/widgets\",branchName:\"main\"},message:{headline:\"x\"},expectedHeadOid:\"abc\"}){commit{oid}}}'"; do
    pg "$tier" "$cmd"
    expect deny "[$tier] $cmd"
    reads protected_branches "[$tier] reads only protected_branches: $cmd"
  done
  for cmd in 'gh api -X PATCH repos/acme/widgets/git/refs/heads/feature -f sha=abc' \
    'gh api -X PATCH repos/acme/widgets/git/refs/heads/feature -f sha=abc -F force=false' \
    'gh api -X PUT repos/acme/widgets/contents/README.md -f message=m -f content=eA== -f branch=feature' \
    'gh api -X POST repos/acme/widgets/branches/feature/rename -f new_name=feature2'; do
    pg "$tier" "$cmd"
    expect defer "[$tier] $cmd"
    reads protected_branches "[$tier] reads only protected_branches: $cmd"
  done
  pg "$tier" 'gh api -X PUT repos/acme/widgets/contents/README.md -f message=m -f content=eA=='
  expect deny "[$tier] a contents write naming no branch writes the default branch and denies"
  reads none "[$tier] the default-branch contents write denies with no read"
done
set_knobs 'protected_branches: release/*'
pg worker 'gh api -X PATCH repos/acme/widgets/git/refs/heads/release/1 -f sha=abc'
expect deny "[worker] a ref write to an overlay-protected branch denies"
set_knobs 'protected_branches: main,master'
pg worker 'gh api -X PATCH repos/acme/widgets/git/refs/heads/feature -f sha=abc'
expect deny "[worker] a malformed protected_branches denies the ref write"
STUB_FAIL_KNOB=protected_branches pg worker 'gh api -X PATCH repos/acme/widgets/git/refs/heads/feature -f sha=abc'
expect deny "[worker] an unreadable protected set denies the ref write"
set_knobs 'protected_branches:'

echo "# gh api: an unreadable request denies before any read"
UNREADABLE=(
  'gh api graphql -F query=@flip.graphql' 'gh api graphql -F query=@-'
  "gh api graphql -F x=@file -f query='query{viewer{login}}'" 'gh api graphql --field query=@q.graphql'
  'gh api graphql --field=query=@q.graphql' 'gh api graphql -Fquery=@q.graphql'
  'gh api graphql --input body.json' 'gh api graphql --input=- < body.json' 'gh api -X GET --input body.json repos/acme/widgets'
  'gh api "$EP" -f body=x' 'gh api $EP -f body=x' 'gh api graphql -f query="$Q"' 'gh api graphql -f query=$Q'
  'gh api graphql -f query="$(cat q.graphql)"' 'gh api graphql -f query=`cat q.graphql`'
  "gh api graphql -f query=\$'mutation{x}'"
  "gh api graphql -f query='query{repository(owner:\"{owner}\",name:\"{repo}\"){ref(qualifiedName:\"{branch}\"){name}}}'"
  'gh api --frobnicate repos/acme/widgets/pulls/42' 'gh api -Z repos/acme/widgets' 'gh api -X "$M" repos/acme/widgets/pulls'
  'gh api --paginate=maybe repos/acme/widgets' 'gh api -X'
  "bash -c 'gh api graphql -f query=x'" 'env gh api graphql -f query=x' '/usr/bin/gh api repos/acme/widgets'
  'xargs gh api < list' 'command -p gh api graphql -f query=x' 'timeout 9 gh api repos/acme/widgets'
  'gh api repos/acme/widgets/pulls && gh api -X PUT repos/acme/widgets/pulls/42/merge'
  'gh api repos/acme/widgets/pulls; gh api graphql -F query=@q.graphql'
  '(gh api repos/acme/widgets/pulls)' '{ gh api repos/acme/widgets/pulls; }'
  'gh api -X PATCH repos/acme/widgets/git/refs/heads/{branch} -f sha=abc'
  'gh api -X PUT repos/acme/widgets/contents/a -f message=m -f content=x -f branch="$B"'
  'gh api -X PUT repos/acme/widgets/contents/a -f message=m -f content=x -F branch={branch}'
  'gh api -X PATCH repos/acme/widgets/git/refs/heads/x -f sha=a -F force="$F"'
  'gh api -X POST repos/acme/widgets/../widgets/pulls' 'gh api -X POST repos/acme/widgets/pulls/42%2Fmerge'
  'gh api -X POST repos/acme//widgets/pulls'
  'gh api -H "X-HTTP-Method-Override: PUT" repos/acme/widgets/pulls/42/merge'
  'gh api' 'gh api repos/a repos/b -f x=y'
  "gh api graphql -f query='mutation{createCommitOnBranch(input:{branch:{id:\"B_x\"}}){commit{oid}}}'"
  "gh api graphql -f query='mutation(\$b:String!){createCommitOnBranch(input:{branch:{branchName:\$b}}){commit{oid}}}' -f b=main"
  "gh api graphql -f query='mutation(\$b:String!){createCommitOnBranch(input:{branch:{repositoryNameWithOwner:\"o/r\",branchName:\$b}}){commit{oid}}} # branchName: \"mine\"' -f b=main"
  "gh api graphql -f query='mutation{createCommitOnBranch(input:{branch:{branchName:\"mine\"}}){commit{oid}}} # x' -f b=main"
  'gh api -X POST repos/acme/widgets/branches/{branch}/rename -f new_name=x'
  'gh api -X POST repos/acme/widgets/branches/feature/rename -f new_name="$B"'
  'gh api -X POST repos/acme/widgets/branches/feature/rename -f new_name={branch}'
  'gh api -X POST repos/acme/widgets/branches/feature/rename'
)
for tier in worker tower; do
  for cmd in "${UNREADABLE[@]}"; do
    pg "$tier" "$cmd"
    expect deny "[$tier] $cmd"
    reads none "[$tier] no read: $cmd"
  done
done
pg worker 'gh api graphql -F query=@flip.graphql'
reason_has 'literal text' "the unreadable deny names the literal form as its remedy"
pg worker 'gh api --frobnicate repos/acme/widgets/pulls/42'
reason_has 'gh 2.96.0' "the unknown-flag deny names the gh grammar it was taken from"

echo "# gh api: a readable request outside the acts defers"
OTHER_ACTS=(
  "gh api graphql -f query='mutation{resolveReviewThread(input:{threadId:\"PRRT_x\"}){thread{isResolved}}}'"
  "gh api -X POST repos/acme/widgets/pulls/42/requested_reviewers -f 'reviewers[]=octocat'"
  "gh api graphql -f query='mutation(\$b:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:\"PRRT_x\",body:\$b}){comment{id}}}' -f b=\"\$BODY\""
  'gh api repos/{owner}/{repo}/pulls/42/comments' 'gh api "$EP"' 'gh api --help -f query=x'
  'gh api -X GET repos/acme/widgets/pulls/42/merge' 'gh api repos/acme/widgets/git/refs/heads/main'
  'gh api -X DELETE repos/acme/widgets/git/refs/tags/v1' 'gh api --paginate --jq .[].id repos/acme/widgets/pulls'
  'gh api -H "Accept: application/vnd.github+json" repos/acme/widgets/pulls/42'
  'gh --repo acme/widgets api repos/acme/widgets/pulls'
)
for tier in worker tower; do
  for cmd in "${OTHER_ACTS[@]}"; do
    pg "$tier" "$cmd"
    expect defer "[$tier] $cmd"
    reads none "[$tier] no read: $cmd"
  done
done

echo "# gh api: no tier profile defers on every gh api line"
for cmd in "${CLASSIFIED[@]}" "${UNREADABLE[@]}" "${OTHER_ACTS[@]}"; do
  pg '' "$cmd"
  expect defer "no tier: $cmd"
  reads none "no tier, no read: $cmd"
done

no_gh_calls
finish
