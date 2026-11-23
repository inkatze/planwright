#!/bin/bash
# Tests for scripts/mc-readiness.sh: the collector's audit of the cadence in the
# worktree holding the pull request's branch (mission-control REQ-D1.8).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-readiness-cadence.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
# Fixture git calls must reach the fixture repositories, never one an
# inherited selector (a git hook's GIT_DIR, say) points at.
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

PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)

# With no --worktree the cadence is audited in the program repository's
# worktree holding the pull request's branch; one that ran no point is caught.
has "no worktree holds a branch the read did not name, so the cadence is unaudited" "cadence${tab}unaudited${tab}"
git -C "$repo" remote add origin https://github.com/Acme/web.git
git -C "$repo" worktree add -q -b feature "$tmp/feature-wt" 2>/dev/null || fail "fixture: the feature worktree"
sed 's/"headRefOid"/"headRefName": "feature", "headRefOid"/' "$tmp/pr.json" >"$tmp/p.json" && mv "$tmp/p.json" "$tmp/pr.json"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)
has "the branch's worktree is found and audited" "cadence${tab}audited${tab}$head"
has "its skipped convergence is named" "cadence${tab}gap${tab}convergence${tab}missing${tab}polish"
# A named base the worktree does not hold leaves the cadence unaudited.
cp "$tmp/pr.json" "$tmp/pr.nobase.json"
sed 's/"headRefOid"/"baseRefName": "main", "headRefOid"/' "$tmp/pr.json" >"$tmp/p.json" && mv "$tmp/p.json" "$tmp/pr.json"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)
has "a base the worktree lacks is unaudited, naming it" "cadence${tab}unaudited${tab}the worktree $tmp/feature-wt does not hold the base origin/main"
git -C "$repo" update-ref refs/remotes/origin/main "$head"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)
has "and once held, the cadence is audited against it" "cadence${tab}audited${tab}$head"
git -C "$repo" update-ref -d refs/remotes/origin/main
mv "$tmp/pr.nobase.json" "$tmp/pr.json"
# The same repository listed twice still names one worktree.
sed -i.bak "s|^program_alpha_repositories: .*|program_alpha_repositories: [$repo, $repo]|" "$tracked"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
sed -i.bak "s|^program_alpha_repositories: .*|program_alpha_repositories: [$repo]|" "$tracked"
c=$(cat "$tmp/collected" 2>/dev/null)
has "a repository listed twice still finds its one worktree" "cadence${tab}audited${tab}$head"
has "and its missing completion" "cadence${tab}gap${tab}convergence${tab}incomplete"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh check --program alpha --repo acme/web --pr 7
expect_out "check refuses the skipped cadence" "fail${tab}cadence${tab}convergence: polish is missing"
# A worktree off to the side of the forge's head (here, on a sibling of it)
# cannot speak for it.
git -C "$tmp/feature-wt" checkout -q --orphan side && git -C "$tmp/feature-wt" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m sibling \
  && git -C "$tmp/feature-wt" checkout -q -B feature side
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)
has "a worktree head that differs from the forge's and is not ahead of it is unaudited, naming both" "cadence${tab}unaudited${tab}the worktree $tmp/feature-wt is at"
has "and says to retry once the session using it is done" "retry once it has pushed or finished"
git -C "$tmp/feature-wt" checkout -q --detach "$head" && git -C "$tmp/feature-wt" checkout -q -B feature
# A worktree one commit ahead of the forge's head (a session mid-change) still
# holds the head: the audit judges the records against the pull request's head.
(cd "$tmp/feature-wt" && PLANWRIGHT_ROOT="$core" /bin/bash "$repo_root/scripts/step-record.sh" new-run >/dev/null \
  && /bin/bash "$repo_root/scripts/step-record.sh" write --run 000001 --point convergence --step polish --kind skill \
    --target polish --hosting isolated --backend none --head "$prev" --end-head "$head" \
    --start 2026-10-28T00:00:07Z --end 2026-10-28T00:01:19Z --outcome applied >/dev/null \
  && /bin/bash "$repo_root/scripts/step-record.sh" write --completion --run 000001 --point convergence --head "$head" >/dev/null) \
  || fail "the fixture step record in the feature worktree"
git -C "$tmp/feature-wt" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m unpushed
# A configured pre-ci step with no record at the head is a gap beside the covered convergence.
cp "$tracked" "$tmp/tracked.keep"
printf 'steps_pre_ci: [polish]\n' >>"$tracked"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
expect_rc "a worktree ahead of the forge's head still collects" 0
c=$(cat "$tmp/collected" 2>/dev/null)
has "a worktree ahead of the forge's head is audited at the forge's head" "cadence${tab}audited${tab}$head"
hasnt "and is not refused for being ahead" "cadence${tab}unaudited"
hasnt "its records at the forge's head count" "cadence${tab}gap${tab}convergence"
has "and the covered point is carried for the packet" "cadence${tab}covered${tab}convergence"
hasnt "while the gap point is not carried as covered" "cadence${tab}covered${tab}pre-ci"
has "while a point its records do not complete is still a gap" "cadence${tab}gap${tab}pre-ci"
has "and the step records the worktree holds at the forge's head are collected" "step${tab}polish${tab}applied${tab}$head"
# A worktree ahead with the head's records incomplete still fails readiness.
git -C "$tmp/feature-wt" checkout -q --detach "$head" && git -C "$tmp/feature-wt" checkout -q -B feature
rm -rf "$tmp/feature-wt/.claude/steps"
git -C "$tmp/feature-wt" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m unpushed
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)
has "an ahead worktree whose records do not cover the head still has the gap" "cadence${tab}gap${tab}convergence${tab}incomplete"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh check --program alpha --repo acme/web --pr 7 --worktree "$tmp/feature-wt"
expect_rc "and readiness refuses it" 4
expect_out "naming the missing completion" "fail${tab}cadence${tab}convergence: no completion record"
mv "$tmp/tracked.keep" "$tracked"
git -C "$tmp/feature-wt" checkout -q --detach "$head" && git -C "$tmp/feature-wt" checkout -q -B feature
# A post-pr completion a reused worktree holds from another unit, on a head
# outside this pull request's history, is no completion here: a draft is told
# to flip, a ready pull request still refuses. One on an earlier head of the
# pull request itself stays stale, as before.
cp "$tracked" "$tmp/tracked.keep"
printf 'steps_post_pr: [polish]\n' >>"$tracked"
rm -rf "$tmp/feature-wt/.claude/steps"
if ! { git -C "$tmp/feature-wt" checkout -q -b other-unit "$prev" \
  && git -C "$tmp/feature-wt" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m other-unit \
  && git -C "$tmp/feature-wt" checkout -q feature; }; then
  fail "fixture: the other unit's commit"
fi
other_unit=$(git -C "$tmp/feature-wt" rev-parse other-unit)
post_pr_at() { # post_pr_at <head>: a new run whose post-pr completed at the head
  (cd "$tmp/feature-wt" && ppr=$(PLANWRIGHT_ROOT="$core" /bin/bash "$repo_root/scripts/step-record.sh" new-run) \
    && /bin/bash "$repo_root/scripts/step-record.sh" write --run "$ppr" --point post-pr --step polish --kind skill \
      --target polish --hosting isolated --backend none --head "$1" --end-head "$1" \
      --start 2026-10-28T00:00:07Z --end 2026-10-28T00:01:19Z --outcome passed >/dev/null \
    && /bin/bash "$repo_root/scripts/step-record.sh" write --completion --run "$ppr" --point post-pr --head "$1" >/dev/null) \
    || fail "fixture: the post-pr completion at $1"
}
printf '# format: 1\n' >"$tmp/no-conditions"
walk_collected() { # walk_collected <row>...: the walk over the collection's head and post-pr rows and the rows given
  {
    printf '# format: 1\ncheck\tbuild\tSUCCESS\n'
    grep -E "^(head|cadence${tab}audited|cadence${tab}gap${tab}post-pr)${tab}" "$tmp/collected"
    for r in "$@"; do printf '%s\n' "$r" | tr ',' '\t'; done
  } >"$tmp/ev.walk"
  mc_run mc-readiness.sh walk --conditions "$tmp/no-conditions" --evidence "$tmp/ev.walk"
}
post_pr_at "$other_unit"
(cd "$tmp/feature-wt" && /bin/bash "$repo_root/scripts/step-record.sh" write --completion --run 000001 --point convergence --head "$other_unit" >/dev/null) \
  || fail "fixture: the other unit's convergence completion"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)
has "another unit's post-pr completion off this history is collected as foreign" "cadence${tab}gap${tab}post-pr${tab}foreign${tab}$other_unit"
hasnt "not as stale" "cadence${tab}gap${tab}post-pr${tab}stale"
has "another point's stale gap is left as it was" "cadence${tab}gap${tab}convergence${tab}stale${tab}$other_unit"
walk_collected "state,draft" "require,pr-agent"
expect_rc "a draft holding it is not merge-ready" 4
case $OUT in "flip-for-review${tab}$head"*) ok "a draft holding only another unit's post-pr is told to flip" ;; *) fail "a draft holding another unit's post-pr reads: $OUT" ;; esac
walk_collected "state,ready" "flip,2026-11-18T00:42:21Z" "require,pr-agent" "check,PR-Agent,SUCCESS" "born,PR-Agent,2026-11-18T00:42:23Z"
expect_rc "a ready pull request holding it is not merge-ready" 4
other_unit_short=$(printf '%.12s' "$other_unit")
expect_out "it names the post-pr gap" "fail${tab}cadence${tab}post-pr: completed only outside the history of this pull request, newest at $other_unit_short"
# A shallow repository cuts the history the check walks, so it never says foreign.
shallow="$repo/.git/shallow"
printf '%s\n' "$head" >"$shallow"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
rm -f "$shallow"
c=$(cat "$tmp/collected" 2>/dev/null)
has "in a shallow repository the same completion stays stale" "cadence${tab}gap${tab}post-pr${tab}stale${tab}$other_unit"
hasnt "never foreign" "cadence${tab}gap${tab}post-pr${tab}foreign"
post_pr_at "$prev"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)
has "a later post-pr completion on an earlier head of the pull request is stale" "cadence${tab}gap${tab}post-pr${tab}stale${tab}$prev"
walk_collected "state,draft" "require,pr-agent"
expect_out "a draft holding it is refused, as before" "fail${tab}cadence${tab}post-pr: completed only at ${prev%"${prev#????????????}"}"
post_pr_at "$other_unit"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)
has "a newer foreign completion does not hide the pull request's own stale one" "cadence${tab}gap${tab}post-pr${tab}stale${tab}$other_unit"
hasnt "so the point is not foreign" "cadence${tab}gap${tab}post-pr${tab}foreign"
# An own completion whose record file lacks its final newline is still read,
# as the audit reads it, so a later foreign completion does not hide it.
rm -rf "$tmp/feature-wt/.claude/steps"
post_pr_at "$prev"
own_done="$tmp/feature-wt/.claude/steps/000001/002-done-post-pr.rec"
# The command substitution drops the final newline; a plain copy would not.
if [ -f "$own_done" ] && printf '%s' "$(cat "$own_done")" >"$own_done.new" && mv "$own_done.new" "$own_done" \
  && [ -n "$(tail -c 1 "$own_done")" ]; then
  post_pr_at "$other_unit"
  PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
  c=$(cat "$tmp/collected" 2>/dev/null)
  has "an own completion in a record with no final newline keeps the point stale" "cadence${tab}gap${tab}post-pr${tab}stale${tab}$other_unit"
  hasnt "never foreign" "cadence${tab}gap${tab}post-pr${tab}foreign"
else
  fail "fixture: the own completion record without its final newline"
fi
# A completion git cannot place keeps the point stale.
rm -rf "$tmp/feature-wt/.claude/steps"
post_pr_at "$H"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)
has "a post-pr completion on a commit the worktree lacks stays stale" "cadence${tab}gap${tab}post-pr${tab}stale${tab}$H"
hasnt "never foreign" "cadence${tab}gap${tab}post-pr${tab}foreign"
# A completion ahead of the head (a session whose work is not pushed yet) is
# the pull request's own.
rm -rf "$tmp/feature-wt/.claude/steps"
git -C "$tmp/feature-wt" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m unpushed
unpushed=$(git -C "$tmp/feature-wt" rev-parse HEAD)
post_pr_at "$unpushed"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)
has "a post-pr completion ahead of the forge's head stays stale" "cadence${tab}gap${tab}post-pr${tab}stale${tab}$unpushed"
hasnt "never foreign" "cadence${tab}gap${tab}post-pr${tab}foreign"
git -C "$tmp/feature-wt" checkout -q --detach "$head" && git -C "$tmp/feature-wt" checkout -q -B feature
# With the base named: a completion it already holds predates the pull
# request's branch point; one on the pull request's own commits does not.
rm -rf "$tmp/feature-wt/.claude/steps"
post_pr_at "$prev"
cp "$tmp/pr.json" "$tmp/pr.nobase.json"
sed 's/"headRefOid"/"baseRefName": "main", "headRefOid"/' "$tmp/pr.json" >"$tmp/p.json" && mv "$tmp/p.json" "$tmp/pr.json"
git -C "$repo" update-ref refs/remotes/origin/main "$prev"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)
has "a post-pr completion at or before the branch point is foreign" "cadence${tab}gap${tab}post-pr${tab}foreign${tab}$prev"
if ! { git -C "$tmp/feature-wt" checkout -q --orphan other-base \
  && git -C "$tmp/feature-wt" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m other-base \
  && git -C "$repo" update-ref refs/remotes/origin/main "$(git -C "$tmp/feature-wt" rev-parse HEAD)" \
  && git -C "$tmp/feature-wt" checkout -q feature; }; then
  fail "fixture: a base that lacks the pull request's commits"
fi
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)
has "a post-pr completion on the pull request's own commit, which the base lacks, stays stale" "cadence${tab}gap${tab}post-pr${tab}stale${tab}$prev"
hasnt "never foreign" "cadence${tab}gap${tab}post-pr${tab}foreign"
git -C "$repo" update-ref -d refs/remotes/origin/main
mv "$tmp/pr.nobase.json" "$tmp/pr.json"
mv "$tmp/tracked.keep" "$tracked"
rm -rf "$tmp/feature-wt/.claude/steps"
# The audit itself failing is unaudited, with the resolver's reason.
chmod 000 "$core/config/steps.yaml"
if hermetic_access_denied r "$core/config/steps.yaml"; then
  PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
  chmod 644 "$core/config/steps.yaml"
  c=$(cat "$tmp/collected" 2>/dev/null)
  has "an audit that cannot resolve the cadence is unaudited, naming why" "cadence${tab}unaudited${tab}the audit in $tmp/feature-wt failed: step-run: the configured cadence did not resolve"
else
  chmod 644 "$core/config/steps.yaml"
  echo "skip: the unresolvable cadence case (the mode does not deny reading here)"
fi
# Another repository's worktree on the same branch name is never audited.
git -C "$repo" remote set-url origin https://github.com/acme/api.git
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)
has "a worktree of a repository whose origin is not the PR's is passed over" "cadence${tab}unaudited${tab}no worktree of acme/web has branch feature"
git -C "$repo" remote set-url origin git@github.com:acme/web.git
# A worktree deleted without a prune is listed prunable: unaudited, no crash.
rm -rf "$tmp/feature-wt"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
expect_rc "a prunable worktree does not fail the collect" 0
c=$(cat "$tmp/collected" 2>/dev/null)
has "and the named branch with no live worktree is unaudited" "cadence${tab}unaudited${tab}no worktree of acme/web has branch feature checked out"
git -C "$repo" worktree prune

if [ "$failures" -ne 0 ]; then
  echo "test-mc-readiness-cadence: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-readiness-cadence: all passed"
