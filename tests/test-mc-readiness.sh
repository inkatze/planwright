#!/bin/bash
# Tests for scripts/mc-readiness.sh — the readiness walk over primary
# evidence at the current head, the evidence the session records, the
# collector over the forge and the step records, and the watcher
# (mission-control REQ-D1.8, REQ-I1.7; D-25, D-26).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-readiness.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
# Fixture git calls must reach the fixture repositories, never one an
# inherited selector (a git hook's GIT_DIR, say) points at.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
# shellcheck source=tests/lib/hermetic-env.sh
. "$here/lib/hermetic-env.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-readiness.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
# A run stopped while a directory is mode-restricted must still clean up.
trap 'chmod -R u+rwX "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
trap 'exit 143' HUP INT TERM

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
{
  printf 'ready_flip_policy: unit-owner\n'
  grep '^steps_' "$repo_root/config/defaults.yml"
} | write_core_defaults
# The configured cadence the audit resolves: the core steps catalog, with a
# stand-in for the polish skill its default convergence names.
cp "$repo_root/config/steps.yaml" "$core/config/steps.yaml"
mkdir -p "$core/skills/polish"
printf -- '---\nname: polish\ndescription: fixture stand-in\n---\n' >"$core/skills/polish/SKILL.md"
mchome="$tmp/mchome"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_home: $mchome
program_alpha_sources: {code-state: forge:snapshot}
EOF
mkdir -p "$mchome"
printf '# format: 1\nready\tprogram\t*\tsteps\tpolish\nready\tlabel\tui\tevidence\tscreenshot\nready\tprogram\t*\tbody\t## Summary\n' >"$mchome/gates.tsv"

H=1111111111111111111111111111111111111111
complete() {
  cat <<EOF
# format: 1
head	$H
repo	acme/web
label	ui
path	src/app.c
check	build	SUCCESS
check	lint	NEUTRAL
thread	t1	resolved
finding	cubic-dev-ai[bot]	t2	answered
step	polish	applied	$H
cadence	audited	$H
evidence	screenshot	shots/home.png	$H	ok
guard	ready-guard	pass	-
bodyline	## Summary
bodyline	Adds the thing.
EOF
}
walk_with() { # walk_with <label> <sed expression or -> [extra line]
  complete >"$tmp/ev"
  [ "$2" = - ] || sed -i.bak "$2" "$tmp/ev"
  [ -z "${3:-}" ] || printf '%s\n' "$3" >>"$tmp/ev"
  mc_run mc-readiness.sh walk --program alpha --evidence "$tmp/ev"
}

# ---------------------------------------------------------------------------
# REQ-D1.8: a complete fixture passes; each gap is refused, named.
# ---------------------------------------------------------------------------
walk_with complete -
expect_rc "REQ-D1.8: a complete fixture is ready" 0
expect_eq "REQ-D1.8: the verdict names the head" "ready${tab}$H"

walk_with "missing step" '/^step/d'
expect_rc "REQ-D1.8: a missing step is refused" 4
expect_out "REQ-D1.8: named" "fail${tab}step${tab}polish is not recorded passed or applied at 111111111111"
walk_with "step at another head" "s/^step\tpolish\tapplied\t$H/step\tpolish\tapplied\t2222222222222222222222222222222222222222/"
expect_rc "a step recorded at another head is refused" 4
walk_with "failed step" 's/^step\tpolish\tapplied/step\tpolish\tfailed/'
expect_rc "a failed step is refused" 4

walk_with "unaudited cadence" '/^cadence/d'
expect_rc "a walk whose cadence was never audited is refused" 4
expect_out "named" "fail${tab}cadence${tab}the configured cadence was not audited at 111111111111"
walk_with "cadence gap" '-' "cadence${tab}gap${tab}convergence${tab}missing${tab}polish"
expect_rc "a configured step with no record is refused, whatever the gate data names" 4
expect_out "named with its point" "fail${tab}cadence${tab}convergence: polish is missing"
# The cadence gap binds whatever the gate-condition data names: none, or
# another step.
: >"$tmp/no-conditions"
mc_run mc-readiness.sh walk --evidence "$tmp/ev" --conditions "$tmp/no-conditions"
expect_rc "with no gate-condition data the cadence gap is still refused" 4
expect_out "and named" "fail${tab}cadence${tab}convergence: polish is missing"
printf 'ready\tsteps\tother-step\n' >"$tmp/other-conditions"
mc_run mc-readiness.sh walk --evidence "$tmp/ev" --conditions "$tmp/other-conditions"
expect_out "with gate data naming another step the cadence gap is still named" "fail${tab}cadence${tab}convergence: polish is missing"
walk_with "cadence unauditable" '/^cadence/d' "cadence${tab}unaudited${tab}no worktree holds the branch"
expect_rc "a cadence that could not be audited is refused" 4
expect_out "with the reason" "fail${tab}cadence${tab}not audited: no worktree holds the branch"
walk_with "cadence failed step" '-' "cadence${tab}gap${tab}convergence${tab}failed${tab}polish:halted"
expect_out "a failed step reads with its outcome" "fail${tab}cadence${tab}convergence: polish recorded halted"
walk_with "cadence unaudited step" '-' "cadence${tab}gap${tab}convergence${tab}unaudited${tab}polish"
expect_rc "a cadence with a record the step-record truth check refuses is refused" 4
expect_out "and reads as not audited, not done" "fail${tab}cadence${tab}not audited: convergence: polish fails the step-record truth check"
walk_with "cadence stale" '-' "cadence${tab}gap${tab}post-pr${tab}stale${tab}2222222222222222222222222222222222222222"
expect_out "a stale point names where it completed" "fail${tab}cadence${tab}post-pr: completed only at 222222222222"
walk_with "cadence mismatch" '-' "cadence${tab}gap${tab}convergence${tab}mismatch${tab}head:polish"
expect_out "a mismatched record names what it contradicts" \
  "fail${tab}cadence${tab}convergence: a record does not match its branch (head:polish)"
walk_with "cadence incomplete" '-' "cadence${tab}gap${tab}pre-ci${tab}incomplete${tab}-"
expect_out "an incomplete point says so" "fail${tab}cadence${tab}pre-ci: no completion record"
walk_with "cadence fault" '-' "cadence${tab}gap${tab}convergence${tab}fault${tab}000003:convergence:001 polish: start 2026-11-04T10:00:13Z is off"
expect_out "a record the session events contradict reads as its detail" \
  "fail${tab}cadence${tab}convergence: 000003:convergence:001 polish: start 2026-11-04T10:00:13Z is off"
expect_no_out "and is not relabelled with its kind" "is off is fault"
walk_with "cadence audited elsewhere" "s/^cadence\taudited\t$H/cadence\taudited\t2222222222222222222222222222222222222222/"
expect_rc "a cadence audited at another head is refused" 4

walk_with "red check" '-' "check${tab}e2e${tab}FAILURE"
printf 'rollup\tSUCCESS\n' >>"$tmp/ev"
mc_run mc-readiness.sh walk --program alpha --evidence "$tmp/ev"
expect_rc "REQ-D1.8: a red individual check under a green rollup is refused" 4
expect_out "REQ-D1.8: the check named" "fail${tab}check${tab}e2e is FAILURE"
walk_with "pending check" '-' "check${tab}deploy${tab}PENDING"
expect_rc "a pending check is refused" 4
walk_with "no checks" '/^check/d'
expect_rc "no check context at all is refused" 4

# macOS CI runs only once a pull request is ready (or carries the ci-macos
# label), so a draft head's macOS jobs are skipped or absent. Where the
# repository's CI has those jobs the evidence says so (`require macos`), and
# the walk then wants both green at the head: a skip is no pass.
mac_green="check${tab}macos-suite (shard 1/4)${tab}SUCCESS
check${tab}macos-suite (shard 2/4)${tab}SUCCESS
check${tab}macos-smoke${tab}SUCCESS"
walk_with "macos green" '-' "require${tab}macos
$mac_green"
expect_rc "macOS required and both macOS jobs green: ready" 0
walk_with "macos stale skip" '-' "require${tab}macos
check${tab}macos-suite (shard \${{ matrix.shard }}/\${{ strategy.job-total }})${tab}SKIPPED
$mac_green"
expect_rc "a stale skipped shard of a job whose shards later ran green is not a block" 0
walk_with "macos skipped" '-' "require${tab}macos
check${tab}macos-suite${tab}SKIPPED
check${tab}macos-smoke${tab}SKIPPED"
expect_rc "macOS required and its jobs skipped (a draft run): not ready" 4
expect_out "the skip is named with the label that starts it" "fail${tab}macos${tab}macos-suite was skipped at 111111111111; add the ci-macos label (or mark the pull request ready) so CI runs it"
walk_with "macos never ran" '-' "require${tab}macos"
expect_rc "macOS required and no macOS job at the head: not ready" 4
expect_out "never ran is named" "fail${tab}macos${tab}macos-suite never ran at 111111111111; add the ci-macos label (or mark the pull request ready) so CI runs it"
walk_with "macos smoke missing" '-' "require${tab}macos
check${tab}macos-suite${tab}SUCCESS"
expect_out "one macOS job missing is named on its own" "fail${tab}macos${tab}macos-smoke never ran at 111111111111"
walk_with "macos failed" '-' "require${tab}macos
check${tab}macos-suite (shard 1/4)${tab}FAILURE
check${tab}macos-smoke${tab}SUCCESS"
expect_rc "macOS required and a macOS shard failed: not ready" 4
expect_out "the failure is named" "fail${tab}check${tab}macos-suite (shard 1/4) is FAILURE"
walk_with "macos shard pending" '-' "require${tab}macos
check${tab}macos-suite (shard 1/4)${tab}SUCCESS
check${tab}macos-suite (shard 2/4)${tab}PENDING
check${tab}macos-smoke${tab}SUCCESS"
expect_rc "a macOS shard still pending: not ready" 4
expect_out "the pending shard is named" "fail${tab}check${tab}macos-suite (shard 2/4) is PENDING"
walk_with "bypass" '-' "bypass${tab}window-lock${tab}FAILURE"
expect_rc "everything finished but a base-state check: ready" 0
expect_out "the check the operator bypasses is named" "bypass${tab}window-lock${tab}FAILURE"
walk_with "no bypass" -
expect_out "an all-green head names no bypass" "ready${tab}$H"
expect_no_out "an all-green head names no bypass check" "bypass"
walk_with "macos neutral" '-' "require${tab}macos
check${tab}macos-suite${tab}NEUTRAL
check${tab}macos-smoke${tab}SUCCESS"
expect_rc "a neutral macOS job is no green" 4
walk_with "macos not required" '-' "check${tab}macos-suite${tab}SKIPPED"
expect_rc "without the requirement a skipped macos-named job still passes (a repository with no such CI)" 0

# A spec-only pull request (every path under the spec root) is held for its
# bundles' kickoff sign-off instead of the code cadence and the gate-data
# steps; checks, threads, findings, guards, evidence and body still bind.
spec_only() { # spec_only <sed expression or -> [extra line]
  complete | sed "/^step/d; /^cadence/d; /^label/d; /^evidence/d; s|^path\t.*|path\tspecs/demo/design.md|" >"$tmp/ev"
  printf 'scope\tspec-only\t%s\nsignoff\tdemo\tsigned\t-\n' "$H" >>"$tmp/ev"
  [ "$1" = - ] || sed -i.bak "$1" "$tmp/ev"
  [ -z "${2:-}" ] || printf '%s\n' "$2" >>"$tmp/ev"
  mc_run mc-readiness.sh walk --program alpha --evidence "$tmp/ev"
}
spec_only -
expect_rc "a signed-off spec-only pull request needs no code cadence step" 0
spec_only - "cadence${tab}gap${tab}convergence${tab}missing${tab}polish"
expect_rc "an audit gap does not hold a spec-only pull request" 0
spec_only - "require${tab}macos
check${tab}macos-suite${tab}SKIPPED
check${tab}macos-smoke${tab}SKIPPED"
expect_rc "skipped macOS jobs do not hold a spec-only pull request (no code to run them on)" 0
spec_only - "cadence${tab}unaudited${tab}no worktree holds the branch"
expect_rc "nor does a cadence that could not be audited" 0
spec_only 's/^signoff.*/signoff\tdemo\tunsigned\tits status is Draft/'
expect_rc "an unsigned bundle holds a spec-only pull request" 4
expect_out "named with why" "fail${tab}signoff${tab}demo: its status is Draft"
spec_only - "check${tab}title${tab}FAILURE"
expect_rc "a red check still holds a spec-only pull request" 4
spec_only - "thread${tab}t9${tab}open"
expect_rc "an open thread still holds a spec-only pull request" 4
spec_only 's/answered$/unanswered/'
expect_rc "an unanswered finding still holds a spec-only pull request" 4
spec_only 's/^guard.*/guard\tready-guard\tfail\tconflicts with its base/'
expect_rc "a failed guard still holds a spec-only pull request" 4
spec_only '/^bodyline\t## Summary/d'
expect_rc "a required body text still binds a spec-only pull request" 4
spec_only "s/^scope\tspec-only\t$H/scope\tspec-only\t2222222222222222222222222222222222222222/"
expect_rc "a spec-only scope read at another head exempts nothing" 4
expect_out "the cadence binds again" "fail${tab}cadence${tab}the configured cadence was not audited at 111111111111"
expect_out "and so do the gate-data steps" "fail${tab}step${tab}polish is not recorded"

walk_with "open thread" '-' "thread${tab}t9${tab}open"
expect_rc "REQ-D1.8: an open thread is refused" 4
expect_out "named" "fail${tab}thread${tab}t9 is open"

walk_with "unanswered finding" 's/answered$/unanswered/'
expect_rc "REQ-D1.8: an unanswered finding is refused" 4
expect_out "named with its reviewer" "fail${tab}finding${tab}cubic-dev-ai[bot] t2 is unanswered"

walk_with "screenshot error" 's/home.png\t\(.*\)\tok$/home.png\t\1\terror/'
expect_rc "REQ-D1.8: a screenshot judged error is refused" 4
expect_out "named" "fail${tab}screenshot${tab}shots/home.png judged error"
walk_with "screenshot missing judgment" 's/home.png\t\(.*\)\tok$/home.png\t\1\tmissing/'
expect_rc "REQ-D1.8: a screenshot whose judgment is missing is refused" 4
walk_with "screenshot extra, no judgment" '-' "evidence${tab}screenshot${tab}shots/other.png${tab}$H"
expect_rc "a screenshot recorded with no judgment field is refused" 4
expect_out "named as missing" "shots/other.png judged missing"
walk_with "no screenshot" '/^evidence/d'
expect_rc "REQ-I1.7: the label's required screenshot is missing" 4
expect_out "named" "fail${tab}evidence${tab}screenshot is not recorded ok"

walk_with "body" '/^bodyline\t## Summary/d'
expect_rc "a required body text missing is refused" 4
expect_out "named" 'the body lacks "## Summary"'
walk_with "guard" 's/^guard.*/guard\tready-guard\tfail\tbehind its base/'
expect_rc "a failed ready-flip guard is refused" 4
expect_out "named" "fail${tab}guard${tab}ready-guard: behind its base"

printf '# format: 1\nreport\tworker says ready\n' >"$tmp/ev"
mc_run mc-readiness.sh walk --program alpha --evidence "$tmp/ev"
expect_rc "REQ-D1.8: a session report alone never passes" 4
expect_out "REQ-D1.8: said so" "a session report alone never passes"

complete | sed '1d' >"$tmp/ev"
mc_run mc-readiness.sh walk --program alpha --evidence "$tmp/ev"
expect_rc "an evidence file with no format line is refused" 4

# Without the label, no screenshot is required.
walk_with "no label" '/^label/d; /^evidence/d'
expect_rc "REQ-I1.7: an unlabelled pull request needs no screenshot" 0
walk_with "stale screenshot" '/^label/d; /^evidence/d' "evidence${tab}screenshot${tab}x.png${tab}2222222222222222222222222222222222222222${tab}ok"
expect_rc "a screenshot judged ok at another head is refused, required or not" 4
expect_out "named" "x.png was judged at another head"

# ---------------------------------------------------------------------------
# The bot review (PR-Agent) runs once, on the run the ready flip fires: a draft
# is flipped with none, merge-ready needs a successful run on the final head.
# ---------------------------------------------------------------------------
nl=$(printf '\n_')
nl=${nl%_}
rowsof() { # rowsof <row>...: each row's commas are tabs, one row per line
  out_rows=''
  for r in "$@"; do out_rows="$out_rows${out_rows:+$nl}$(printf '%s' "$r" | tr ',' '\t')"; done
  printf '%s' "$out_rows"
}
walk_with "draft, no bot review" - "$(rowsof state,draft require,pr-agent)"
expect_rc "a draft with no PR-Agent run can still be flipped" 0
walk_with "draft, failed bot review" - "$(rowsof state,draft require,pr-agent check,PR-Agent,FAILURE)"
expect_rc "a draft's stale failed PR-Agent run does not hold the flip" 0
walk_with "draft, pending bot review" - "$(rowsof state,draft require,pr-agent check,PR-Agent,PENDING)"
expect_rc "a draft's pending PR-Agent run does not hold the flip either" 0
walk_with "draft, failed ci" - "$(rowsof state,draft require,pr-agent check,lint,FAILURE)"
expect_rc "a draft's failed ordinary check still holds the flip" 4

walk_with "ready, no bot review" - "$(rowsof state,ready require,pr-agent)"
expect_rc "merge-ready needs a PR-Agent run on the head: none is refused" 4
expect_out "named with the head" "fail${tab}bot-review${tab}no PR-Agent run at 111111111111"
walk_with "ready, failed bot review" - "$(rowsof state,ready require,pr-agent check,PR-Agent,FAILURE)"
expect_rc "a head whose only PR-Agent run failed is refused" 4
expect_out "named" "fail${tab}check${tab}PR-Agent is FAILURE"
walk_with "ready, passed bot review" - "$(rowsof state,ready require,pr-agent check,PR-Agent,SUCCESS)"
expect_rc "a successful PR-Agent run on the head passes" 0
walk_with "ready, unanswered bot finding" - "$(rowsof state,ready require,pr-agent check,PR-Agent,SUCCESS 'finding,github-actions[bot],t9,unanswered')"
expect_rc "an unsettled PR-Agent finding is refused" 4
walk_with "ready, label opt-out" - "$(rowsof state,ready require,pr-agent check,PR-Agent,SKIPPED)"
expect_rc "a skipped PR-Agent job (the skip-pr-agent label, a dependabot head) is the opt-out" 0
walk_with "ready, repository without PR-Agent" - "state${tab}ready"
expect_rc "a repository with no PR-Agent workflow needs no run" 0
walk_with "old evidence" -
expect_rc "evidence with no draft state keeps the old rules" 0

# The flip's own runs, told from a too-early flip: #1091's flip was at
# 2026-11-18T00:42:21Z and its pending ci and PR-Agent runs were created at
# 00:42:23Z.
FLIP_T=2026-11-18T00:42:21Z
flip_rows() { # flip_rows <ci created> <pr-agent created>
  rowsof state,ready "flip,$FLIP_T" require,pr-agent check,ci,IN_PROGRESS check,PR-Agent,PENDING "born,ci,$1" "born,PR-Agent,$2"
}
walk_with "flip-fired runs" - "$(flip_rows 2026-11-18T00:42:23Z 2026-11-18T00:42:23Z)"
expect_rc "runs the flip fired still hold merge-ready until they finish" 4
expect_out "ci is named as the flip's own run" "fail${tab}check${tab}ci is IN_PROGRESS (run created 2026-11-18T00:42:23Z, after the flip at $FLIP_T"
expect_out "PR-Agent is named as the flip's own run" "fail${tab}check${tab}PR-Agent is PENDING (run created 2026-11-18T00:42:23Z, after the flip at $FLIP_T"
case $OUT in *too-early*) fail "a flip's own runs read as a too-early flip" ;; *) ok "a flip's own runs are no too-early flip" ;; esac
walk_with "run at the flip second" - "$(flip_rows $FLIP_T $FLIP_T)"
expect_out "a run created in the flip's own second is the flip's" "ci is IN_PROGRESS (run created $FLIP_T, after the flip"
walk_with "too-early flip" - "$(flip_rows 2026-11-18T00:40:10Z 2026-11-18T00:42:23Z)"
expect_rc "a run that predates the flip and still runs holds it" 4
expect_out "named a too-early flip" "fail${tab}flip${tab}ci was still running at the flip (run created 2026-11-18T00:40:10Z, before the flip at $FLIP_T): a too-early flip"
expect_out "the flip's own PR-Agent run is not blamed on it" "PR-Agent is PENDING (run created 2026-11-18T00:42:23Z, after the flip"
walk_with "unknown run time" - "$(rowsof state,ready "flip,$FLIP_T" check,ci,QUEUED)"
expect_out "a run with no known creation time reads as plainly pending" "fail${tab}check${tab}ci is QUEUED"
walk_with "no flip time" - "$(rowsof state,ready check,ci,QUEUED born,ci,2026-11-18T00:42:23Z)"
expect_out "a run with no flip time to compare reads as plainly pending" "fail${tab}check${tab}ci is QUEUED"
walk_with "draft with times" - "$(rowsof state,draft "flip,$FLIP_T" check,ci,QUEUED born,ci,2026-11-18T00:40:00Z)"
expect_out "a draft's pending check is never a too-early flip" "fail${tab}check${tab}ci is QUEUED"

{ complete; flip_rows 2026-11-18T00:40:10Z 2026-11-18T00:42:23Z; echo; } >"$tmp/ev"
mc_run mc-readiness.sh unfinished --evidence "$tmp/ev"
expect_rc "unfinished: a flip's runs are unfinished" 4
expect_out "unfinished: the too-early run is named so" "fail${tab}flip${tab}ci was still running at the flip"
expect_out "unfinished: the flip's own run is named so" "fail${tab}check${tab}PR-Agent is PENDING (run created 2026-11-18T00:42:23Z, after the flip"
{ complete; rowsof state,draft check,PR-Agent,PENDING; echo; } >"$tmp/ev"
mc_run mc-readiness.sh unfinished --evidence "$tmp/ev"
expect_rc "unfinished: a draft's PR-Agent run is none of its business" 0

# ---------------------------------------------------------------------------
# record: evidence the session opened and judged.
# ---------------------------------------------------------------------------
mc_run mc-readiness.sh record --program alpha --repo acme/web --pr 7 --head "$H" --kind screenshot --ref shots/home.png --judgment ok
expect_rc "a judgment is recorded" 0
expect_out "echoed" "recorded${tab}acme/web#7${tab}screenshot${tab}ok"
if [ "$(head -n 1 "$mchome/kb/readiness-check/evidence.tsv")" = "# format: 1" ]; then ok "the store carries its format"; else fail "the store lacks its format line"; fi
mc_run mc-readiness.sh record --program alpha --repo acme/web --pr 7 --head "$H" --kind screenshot --ref x --judgment fine
expect_rc "an unknown judgment is a usage error" 2
mc_run mc-readiness.sh record --program alpha --repo acme/web --pr 7 --head abc --kind smoke --ref x --judgment ok
expect_rc "a short head is a usage error" 2

# ---------------------------------------------------------------------------
# collect: the forge read, the step records and the guard, at the head. The
# gh stub runs the script's own jq programs over fixture JSON.
# ---------------------------------------------------------------------------
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
esac
exit 1
EOF
chmod +x "$tmp/bin/gh"
printf '%s\n' "$head" >"$tmp/headnow"
# The worktree is a worker's: its own git configuration must run nothing
# while its step records are read.
printf '#!/bin/sh\nprintf ran >"%s/fsmonitor-ran"\n' "$tmp" >"$tmp/bin/fsmon"
chmod +x "$tmp/bin/fsmon"
git -C "$repo" config core.fsmonitor "$tmp/bin/fsmon"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --worktree "$repo" --out "$tmp/collected"
expect_rc "collect" 0
if [ ! -e "$tmp/fsmonitor-ran" ]; then ok "the worktree's fsmonitor never runs during collect"; else fail "collect ran the worktree's fsmonitor"; fi
git -C "$repo" ls-files >/dev/null 2>&1
if [ -e "$tmp/fsmonitor-ran" ]; then ok "and the fixture's fsmonitor does run for a plain git read"; else fail "the fsmonitor fixture never fires, so the check above proves nothing"; fi
git -C "$repo" config --unset core.fsmonitor
c=$(cat "$tmp/collected" 2>/dev/null)
has() { case $c in *"$2"*) ok "$1" ;; *) fail "$1: the collection lacks '$2'" ;; esac }
hasnt() { case $c in *"$2"*) fail "$1: the collection carries '$2'" ;; *) ok "$1" ;; esac }
has "the evidence carries its format" "# format: 1"
has "REQ-D1.8: the head is the forge's" "head${tab}$head"
has "REQ-D1.8: each check context is read on its own" "check${tab}build${tab}SUCCESS"
has "an empty conclusion reads its state" "check${tab}deploy${tab}PENDING"
n_wl=$(printf '%s\n' "$c" | grep -c "^check${tab}window-lock${tab}FAILURE$")
if [ "$n_wl" -eq 1 ]; then ok "only the release-window lock is left out: a window-lock from another workflow still counts"; else fail "expected one window-lock context, got $n_wl"; fi
has "the red release-window lock is named for the operator to bypass" "bypass${tab}window-lock${tab}FAILURE"
n_by=$(printf '%s\n' "$c" | grep -c "^bypass${tab}")
if [ "$n_by" -eq 1 ]; then ok "only the left-out base-state check is named for bypass"; else fail "expected one bypass line, got $n_by"; fi
has "only the latest run of a check counts" "check${tab}title${tab}SUCCESS"
n_title=$(printf '%s\n' "$c" | grep -c "^check${tab}title${tab}")
if [ "$n_title" -eq 2 ]; then ok "one line per check context: the same name in another workflow is its own context"; else fail "expected two title contexts, got $n_title"; fi
if printf '%s\n' "$c" | grep -q "^check${tab}title${tab}FAILURE$"; then
  # The other workflow's own failure is the only FAILURE title line allowed.
  if [ "$(printf '%s\n' "$c" | grep -c "^check${tab}title${tab}FAILURE$")" -eq 1 ]; then
    ok "a superseded run is dropped, another workflow's run kept"
  else
    fail "a superseded title run was collected"
  fi
else
  fail "another workflow's title context was dropped"
fi
has "a queued re-run, its start the zero time gh reports, is the latest" "check${tab}rerun${tab}PENDING"
hasnt "and the run it supersedes is dropped" "check${tab}rerun${tab}SUCCESS"
has "the body is read line by line" "bodyline${tab}Adds the thing."
has "labels are read" "label${tab}ui"
has "paths are read" "path${tab}src/app.c"
has "a resolved bot thread is an answered finding" "finding${tab}cubic-dev-ai${tab}t1${tab}answered"
has "a bot thread the author alone replied to is unanswered" "finding${tab}cubic-dev-ai${tab}t2${tab}unanswered"
has "a bot thread another person replied to is answered" "finding${tab}copilot[bot]${tab}t3${tab}answered"
hasnt "a person's thread is no finding" "finding${tab}alice"
has "a person's open thread is collected" "thread${tab}t4${tab}open"
has "a reply with no author is no answer" "finding${tab}cubic-dev-ai${tab}t5${tab}unanswered"
hasnt "the head stood still, so no head guard fails" "guard${tab}head"
has "REQ-D1.8: the recorded cadence step is collected" "step${tab}polish${tab}applied${tab}$head"
has "the configured cadence is audited at the head" "cadence${tab}audited${tab}$head"
hasnt "and the recorded cadence leaves no gap" "cadence${tab}gap"
has "a corrected judgment at the head stands" "evidence${tab}screenshot${tab}shots/home.png${tab}$head${tab}ok"
hasnt "the judgment it replaced does not" "shots/home.png${tab}$head${tab}error"
hasnt "evidence at another head is left out" "shots/stale.png"
hasnt "evidence of another pull request is left out" "shots/other-pr.png"
has "D-25: the ready-flip guard is composed" "guard${tab}ready-guard${tab}"
hasnt "and it ran, its own verdict collected" "the guard did not run"
has "the repository is named for the conditions" "repo${tab}acme/web"
has "the draft state is read" "state${tab}ready"
has "the ready flip time is read" "flip${tab}2026-11-18T00:42:21Z"
has "a check carries its workflow run's creation time" "born${tab}build${tab}2026-11-18T00:42:23Z"
has "a queued check, whose own start is the zero time, still does" "born${tab}rerun${tab}2026-11-18T00:42:24Z"
hasnt "the run reference is only a join key" "runref"
if grep -q 'pr ready' "$tmp/gh.calls" 2>/dev/null; then fail "a flip was attempted"; else ok "nothing flips a pull request"; fi
hasnt "a worktree whose CI has no macOS jobs states no macOS requirement" "require${tab}macos"
mkdir -p "$repo/.github/workflows"
printf 'jobs:\n  macos-suite:\n    needs: plan\n  macos-smoke:\n    needs: plan\n' >"$repo/.github/workflows/ci.yml"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --worktree "$repo" --out "$tmp/collected-mac"
expect_rc "collect over a worktree whose CI has the macOS jobs" 0
c=$(cat "$tmp/collected-mac" 2>/dev/null)
has "a worktree whose CI has the macOS jobs requires them green" "require${tab}macos"
rm -f "$repo/.github/workflows/ci.yml"
hasnt "a worktree whose CI has no PR-Agent workflow states no bot-review requirement" "require${tab}pr-agent"
printf 'jobs:\n  review:\n    env:\n      PR_AGENT_IMAGE: pragent/pr-agent@sha256:0\n' >"$repo/.github/workflows/pr-agent.yml"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --worktree "$repo" --out "$tmp/collected-pa"
expect_rc "collect over a worktree that runs PR-Agent" 0
c=$(cat "$tmp/collected-pa" 2>/dev/null)
has "a repository running PR-Agent requires its run on a ready pull request" "require${tab}pr-agent"
rm -f "$repo/.github/workflows/pr-agent.yml"
c=$(cat "$tmp/collected" 2>/dev/null)
# The stub cannot satisfy the guard's own reads, so it fails closed, and the
# walk over the collection refuses on it.
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh check --program alpha --repo acme/web --pr 7 --worktree "$repo"
expect_rc "check refuses while the guard does" 4
expect_out "the guard named" "fail${tab}guard${tab}ready-guard"
expect_out "and the pending check" "fail${tab}check${tab}deploy is PENDING"
# A head that moves while the evidence is collected fails the walk.
printf '%s\n' 4444444444444444444444444444444444444444 >"$tmp/headnow"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)
has "a head moved during collection fails" "guard${tab}head${tab}fail${tab}the head moved to 4444444444444444444444444444444444444444"
: >"$tmp/headnow"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)
has "a head that cannot be re-read fails as such" "guard${tab}head${tab}fail${tab}the head could not be re-read after the guard"
printf '%s\n' "$head" >"$tmp/headnow"

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

# A spec-only pull request: every changed path under the program's spec root,
# each touched bundle's sign-off read at the head from the repository's
# objects, and no cadence audit run (no worktree is needed).
mkdir -p "$repo/specs/_observations/entries"
sed -i.bak "s|^program_alpha_spec_root: .*|program_alpha_spec_root: $repo/specs|" "$tracked"
bundle() { # bundle <name> <status> <brief: signed|none|stale>: write a bundle, its brief anchoring it
  mkdir -p "$repo/specs/$1"
  printf '# %s\n\n**Status:** %s\n**Format-version:** 2\n\nBody.\n' "$1" "$2" >"$repo/specs/$1/requirements.md"
  printf '# Design\n\nx\n' >"$repo/specs/$1/design.md"
  printf '# Tasks\n\n**Format-version:** 2\n' >"$repo/specs/$1/tasks.md"
  printf '# Test spec\n\ny\n' >"$repo/specs/$1/test-spec.md"
  rm -f "$repo/specs/$1/kickoff-brief.md"
  # shellcheck disable=SC2016 # the brief's backticks are literal
  [ "$3" = none ] || printf '# Brief\n\nAnchor: `%s` — computed as\n`scripts/spec-anchor.sh specs/%s`\n' \
    "$(/bin/sh "$repo_root/scripts/spec-anchor.sh" "$repo/specs/$1")" "$1" >"$repo/specs/$1/kickoff-brief.md"
  [ "$3" != stale ] || printf 'An edit after the sign-off.\n' >>"$repo/specs/$1/design.md"
}
commit_specs() { # commit_specs: commit the spec root, print the head
  printf '%s\n' '- 2026-11-05 [planwright] an entry' >"$repo/specs/_observations/entries/e.md"
  git -C "$repo" add -A specs >/dev/null
  git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m specs
  git -C "$repo" rev-parse HEAD
}
spec_pr() { # spec_pr <head> <path[|change type]>...: collect over the forge's view of a spec pull request
  sp_h=$1
  shift
  sp_files=''
  for sp_p in "$@"; do
    case $sp_p in
      *'|'*) sp_files="$sp_files{\"path\": \"${sp_p%|*}\", \"changeType\": \"${sp_p##*|}\"}," ;;
      *) sp_files="$sp_files{\"path\": \"$sp_p\", \"changeType\": \"MODIFIED\"}," ;;
    esac
  done
  printf '{"headRefOid": "%s", "headRefName": "planwright/demo/spec", "baseRefName": "main", "labels": [], "files": [%s],
 "body": "## Summary", "statusCheckRollup": [{"name": "build", "conclusion": "SUCCESS"}]}\n' "$sp_h" "${sp_files%,}" >"$tmp/pr.json"
  printf '%s\n' "$sp_h" >"$tmp/headnow"
  rm -f "$tmp/collected"
  PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
  expect_rc "collect over $*" 0
  c=$(cat "$tmp/collected" 2>/dev/null)
}
cp "$tmp/pr.json" "$tmp/pr.saved.json"
bundle demo Ready signed
sh_ready=$(commit_specs)
spec_pr "$sh_ready" specs/demo/requirements.md specs/demo/design.md specs/_observations/entries/e.md
has "every path under the spec root is a spec-only scope at the head" "scope${tab}spec-only${tab}$sh_ready"
has "the touched bundle's sign-off is read at the head, its anchor recomputed" "signoff${tab}demo${tab}signed${tab}-"
if [ "$(printf '%s\n' "$c" | grep -c "^signoff${tab}")" -eq 1 ]; then ok "one sign-off line per bundle, however many of its files changed"; else fail "the bundle's sign-off is not read exactly once"; fi
hasnt "an observation entry is no bundle" "signoff${tab}_observations"
hasnt "no cadence audit is run or required" "cadence${tab}"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh check --program alpha --repo acme/web --pr 7
expect_no_out "the walk holds it for no cadence" "fail${tab}cadence"
expect_no_out "nor for a gate-data step" "fail${tab}step"
expect_out "while the guard still binds" "fail${tab}guard${tab}ready-guard"
printf '# Specs\n' >"$repo/specs/README.md"
sh_ready=$(commit_specs)
spec_pr "$sh_ready" specs/_observations/entries/e.md specs/README.md
has "an observation and root-file pull request is spec-only" "scope${tab}spec-only${tab}$sh_ready"
hasnt "and touches no bundle to sign off" "signoff${tab}"
mv "$tmp/collected" "$tmp/ev"
mc_run mc-readiness.sh walk --evidence "$tmp/ev" --conditions "$tmp/no-conditions"
expect_no_out "its walk asks for no cadence" "fail${tab}cadence"
expect_no_out "nor for a sign-off" "fail${tab}signoff"
spec_pr "$sh_ready" 'specs/demo/requirements.md|COPIED'
hasnt "a copy into the spec root is no spec-only scope" "scope${tab}"
spec_pr "$sh_ready" 'specs/demo/requirements.md|-'
hasnt "a path with no change type is no spec-only scope" "scope${tab}"
spec_pr "$sh_ready" specs/demo/run.sh
hasnt "a file that is not prose is no spec-only scope" "scope${tab}"
spec_pr "$sh_ready" specs/demo/requirements.md src/app.c
hasnt "a code path beside the bundle is no spec-only scope" "scope${tab}"
has "and its cadence is audited as for any pull request" "cadence${tab}unaudited${tab}"
spec_pr "$sh_ready" specsx/demo/requirements.md
hasnt "a sibling of the spec root sharing its prefix is outside it" "scope${tab}"
spec_pr "$sh_ready" specs/../src/app.c
hasnt "a path climbing out of the spec root is outside it" "scope${tab}"
spec_pr "$sh_ready" specs//demo/requirements.md
hasnt "a path with an empty component is outside it" "scope${tab}"
spec_pr "$sh_ready" 'specs/demo/moved.md|RENAMED'
hasnt "a rename into the spec root, its source unnamed, is no spec-only scope" "scope${tab}"
bundle demo Active signed
bundle other Draft signed
sh_two=$(commit_specs)
spec_pr "$sh_two" specs/demo/design.md specs/other/design.md
has "an Active bundle is signed off" "signoff${tab}demo${tab}signed${tab}-"
has "a Draft bundle beside it is not" "signoff${tab}other${tab}unsigned${tab}its status at the head is Draft"
mv "$tmp/collected" "$tmp/ev"
mc_run mc-readiness.sh walk --program alpha --evidence "$tmp/ev"
expect_out "the walk holds the pull request for the unsigned bundle" "fail${tab}signoff${tab}other: its status at the head is Draft"
bundle demo Ready none
sh_nobrief=$(commit_specs)
spec_pr "$sh_nobrief" specs/demo/requirements.md
has "a Ready bundle with no kickoff brief is not signed off" "signoff${tab}demo${tab}unsigned${tab}it has no kickoff brief at the head"
bundle demo Ready signed
# shellcheck disable=SC2016 # the brief's backticks are literal
(cd "$repo/specs/demo" && printf '# Brief\n\nAnchor: `%s` — computed as\n`git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin`\n' \
  "$(git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin)" >kickoff-brief.md)
sh_interim=$(commit_specs)
spec_pr "$sh_interim" specs/demo/requirements.md
has "a brief anchored by the interim whole-file form is signed off" "signoff${tab}demo${tab}signed${tab}-"
anchor_form() { # anchor_form <recorded command>: a signed bundle whose brief records that command
  bundle demo Ready signed
  # shellcheck disable=SC2016 # the brief's backticks are literal
  printf '# Brief\n\nAnchor: `%s` — computed as\n`%s`\n' \
    "$(/bin/sh "$repo_root/scripts/spec-anchor.sh" "$repo/specs/demo")" "$1" >"$repo/specs/demo/kickoff-brief.md"
}
anchor_form 'spec-anchor.sh specs/demo'
spec_pr "$(commit_specs)" specs/demo/requirements.md
has "a brief anchored by the logical form is signed off" "signoff${tab}demo${tab}signed${tab}-"
anchor_form 'scripts/spec-anchor.sh specs/demo'
spec_pr "$(commit_specs)" specs/demo/requirements.md
has "a brief anchored by the canonical form is signed off" "signoff${tab}demo${tab}signed${tab}-"
anchor_form 'spec-anchor.sh specs/demo'
printf 'An edit after the sign-off.\n' >>"$repo/specs/demo/design.md"
spec_pr "$(commit_specs)" specs/demo/design.md
has "a logical-form brief over edited content is not signed off" "signoff${tab}demo${tab}unsigned${tab}its content at the head is not what the kickoff signed off"
anchor_form 'spec-anchor.sh specs/elsewhere'
spec_pr "$(commit_specs)" specs/demo/requirements.md
has "a logical form naming another directory is not recomputed" "signoff${tab}demo${tab}unsigned${tab}its kickoff brief's anchor uses a form this check does not recompute"
anchor_form 'sh ./spec-anchor.sh specs/demo'
spec_pr "$(commit_specs)" specs/demo/requirements.md
has "a script form with a prefix is not recomputed" "signoff${tab}demo${tab}unsigned${tab}its kickoff brief's anchor uses a form this check does not recompute"
# shellcheck disable=SC2016 # the brief's backticks are literal
printf 'Anchor: `%s` — computed as\n`sha1sum specs/demo/*`\n' 0123456789abcdef0123456789abcdef01234567 >>"$repo/specs/demo/kickoff-brief.md"
sh_otherform=$(commit_specs)
spec_pr "$sh_otherform" specs/demo/requirements.md
has "a brief anchored by a form the check does not recompute is not signed off" "signoff${tab}demo${tab}unsigned${tab}its kickoff brief's anchor uses a form this check does not recompute"
spec_pr "$sh_ready" 'specs/demo/requirements.md|CHANGED'
hasnt "a type change under the spec root is no spec-only scope" "scope${tab}"
bundle demo Ready stale
sh_stale=$(commit_specs)
spec_pr "$sh_stale" specs/demo/design.md
has "a bundle edited after its sign-off is not signed off" "signoff${tab}demo${tab}unsigned${tab}its content at the head is not what the kickoff signed off"
bundle demo Ready signed
printf '# demo\n\nBody.\n' >"$repo/specs/demo/requirements.md"
spec_pr "$(commit_specs)" specs/demo/requirements.md
has "a requirements.md with no status is not signed off" "signoff${tab}demo${tab}unsigned${tab}its requirements.md status cannot be read at the head"
bundle demo Ready signed
printf '# Brief\n\nAnchor: not a hash\n' >"$repo/specs/demo/kickoff-brief.md"
spec_pr "$(commit_specs)" specs/demo/kickoff-brief.md
has "a half-written newest anchor entry is not signed off" "signoff${tab}demo${tab}unsigned${tab}its kickoff brief's latest anchor entry does not parse"
bundle demo Ready signed
printf '# Brief\n\nNo sign-off yet.\n' >"$repo/specs/demo/kickoff-brief.md"
spec_pr "$(commit_specs)" specs/demo/kickoff-brief.md
has "a brief recording no anchor is not signed off" "signoff${tab}demo${tab}unsigned${tab}its kickoff brief records no anchor"
bundle demo Ready signed
rm "$repo/specs/demo/design.md"
spec_pr "$(commit_specs)" specs/demo/design.md
has "a bundle whose anchor cannot be recomputed at the head is not signed off" "signoff${tab}demo${tab}unsigned${tab}its anchor cannot be recomputed at the head"
spec_pr 5555555555555555555555555555555555555555 specs/demo/requirements.md
has "a head the repository does not hold is a spec-only scope" "scope${tab}spec-only${tab}5555555555555555555555555555555555555555"
has "held by one unsigned sign-off naming the fetch" "signoff${tab}*${tab}unsigned${tab}the head is not in"
spec_pr "$sh_ready" 'specs/Bad Name/requirements.md'
has "a bundle directory outside the spec identifier grammar is refused" "signoff${tab}Bad Name${tab}unsigned${tab}not a spec identifier"
# ---------------------------------------------------------------------------
# REQ-D1.13: a pull request that is not spec-only is checked for spec drift,
# and its edited bundles' sign-offs are read as a spec-only one's are.
# ---------------------------------------------------------------------------
bundle demo Ready signed
cat >"$repo/specs/demo/tasks.md" <<'EOF'
# Tasks

**Format-version:** 2

## Tasks

### Task 1 — One

- **Deliverables:** `app/run.sh`, and prose app/prose.sh.
- **Done when:** ok.
- **Dependencies:** none
- **Citations:** D-1
- **Estimated effort:** 1 day
EOF
resign() { # resign: re-sign the demo bundle at its current content
  # shellcheck disable=SC2016 # the brief's backticks are literal
  printf '# Brief\n\nAnchor: `%s` — computed as\n`scripts/spec-anchor.sh specs/demo`\n' \
    "$(/bin/sh "$repo_root/scripts/spec-anchor.sh" "$repo/specs/demo")" >"$repo/specs/demo/kickoff-brief.md"
}
resign
mkdir -p "$repo/app" "$repo/src"
printf 'run\n' >"$repo/app/run.sh"
printf 'prose\n' >"$repo/app/prose.sh"
dr_commit() { # dr_commit <message>: commit the spec and code paths (never the fixture config), print the head
  git -C "$repo" add specs app src >/dev/null
  git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "$1"
  git -C "$repo" rev-parse HEAD
}
printf 'other\n' >"$repo/src/other.c"
dr_base=$(dr_commit "base with code and a signed spec")
git -C "$repo" update-ref refs/remotes/origin/main "$dr_base"
dr_pr() { # dr_pr <head> <body> <base branch> <path>...: collect and check over the forge's view
  dr_h=$1 dr_body=$2 dr_bb=$3
  shift 3
  jq -n --arg h "$dr_h" --arg body "$dr_body" --arg bb "$dr_bb" --args '
    {headRefOid: $h, headRefName: "feature", baseRefName: $bb, labels: [], body: $body,
     files: ($ARGS.positional | map({path: ., changeType: "MODIFIED"})),
     statusCheckRollup: [{name: "build", conclusion: "SUCCESS"}]}' "$@" >"$tmp/pr.json"
  printf '%s\n' "$dr_h" >"$tmp/headnow"
  rm -f "$tmp/collected"
  PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
  c=$(cat "$tmp/collected" 2>/dev/null)
  PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh check --program alpha --repo acme/web --pr 7
}
printf 'changed\n' >>"$repo/app/run.sh"
dr_a=$(dr_commit "feat: change the listed file")
dr_pr "$dr_a" "## Summary" main app/run.sh
has "REQ-D1.13: a changed listed deliverable with no spec edit is collected as drift" "drift${tab}app/run.sh${tab}demo/1"
expect_rc "the walk refuses it" 4
expect_out "naming the file and the task" "fail${tab}drift${tab}app/run.sh is a deliverable of demo/1"
dr_pr "$dr_a" "Not covered: app/run.sh — a comment fix" main app/run.sh
has "the collection ran at the head" "head${tab}$dr_a"
hasnt "a Not covered line naming the file clears the drift row" "drift${tab}"
expect_no_out "and the walk raises no drift failure" "fail${tab}drift"
dr_pr "$dr_a" "Not covered: src/other.c — a comment fix" main app/run.sh
has "a Not covered line naming another path does not excuse it" "drift${tab}app/run.sh${tab}demo/1"
dr_pr "$dr_a" "## Summary" nosuchbase app/run.sh
has "REQ-D1.13: a drift check that cannot run is a row with its reason" "drift${tab}*${tab}the base refs/remotes/origin/nosuchbase is not a commit"
expect_out "and the walk refuses with it" "fail${tab}drift${tab}the spec-drift check could not run: the base refs/remotes/origin/nosuchbase is not a commit"
dr_pr "$dr_a" "## Summary" "" app/run.sh
has "a pull request naming no base branch cannot be checked" "drift${tab}*${tab}the pull request names no base branch"
git -C "$repo" reset -q --hard "$dr_base"
printf 'prose change\n' >>"$repo/app/prose.sh"
printf 'x\n' >>"$repo/src/other.c"
dr_u=$(dr_commit "feat: unlisted")
dr_pr "$dr_u" "## Summary" main src/other.c app/prose.sh
has "the collection ran at the head" "head${tab}$dr_u"
hasnt "a change touching no listed deliverable (prose path included) passes untouched" "drift${tab}"
hasnt "and edits no bundle, so reads no sign-off" "signoff${tab}"
expect_no_out "the walk raises no drift or sign-off failure" "fail${tab}drift"
dr_pr "$dr_base" "## Summary" main src/other.c specs/gone/design.md
has "the collection ran at the head" "head${tab}$dr_base"
hasnt "a bundle absent at the head (removed or moved) has no sign-off to read" "signoff${tab}gone"

# A spec edit with its anchor re-signed covers the change; a stale anchor does not.
git -C "$repo" reset -q --hard "$dr_base"
printf 'changed\n' >>"$repo/app/run.sh"
printf 'An amendment.\n' >>"$repo/specs/demo/design.md"
dr_stale=$(dr_commit "feat: the file and an unsigned spec edit")
dr_pr "$dr_stale" "## Summary" main app/run.sh specs/demo/design.md
has "the collection ran at the head" "head${tab}$dr_stale"
hasnt "a changed anchored spec covers the file" "drift${tab}"
has "REQ-D1.13: but its edit is read against the sign-off, which no longer matches" "signoff${tab}demo${tab}unsigned${tab}its content at the head is not what the kickoff signed off"
expect_out "the walk refuses the unsigned edit on a code pull request" "fail${tab}signoff${tab}demo: its content at the head is not what the kickoff signed off"
resign
dr_signed=$(dr_commit "feat: the file and the re-signed spec edit")
dr_pr "$dr_signed" "## Summary" main app/run.sh specs/demo/design.md specs/demo/kickoff-brief.md
hasnt "a re-signed spec edit leaves no drift row" "drift${tab}"
has "and its sign-off is read as signed" "signoff${tab}demo${tab}signed${tab}-"
expect_no_out "the walk raises no drift or sign-off failure for it" "fail${tab}drift"
expect_no_out "nor a sign-off one" "fail${tab}signoff"

# A status annotation alone is no spec edit.
git -C "$repo" reset -q --hard "$dr_base"
printf 'changed\n' >>"$repo/app/run.sh"
sed 's/\*\*Status:\*\* Ready/**Status:** Active/' "$repo/specs/demo/requirements.md" >"$tmp/req" && cat "$tmp/req" >"$repo/specs/demo/requirements.md"
dr_status=$(dr_commit "feat: the file and a status flip")
dr_pr "$dr_status" "## Summary" main app/run.sh specs/demo/requirements.md
has "REQ-D1.13: a status annotation alone does not cover the file" "drift${tab}app/run.sh${tab}demo/1"
git -C "$repo" reset -q --hard "$dr_base"
walk_with "drift row" '-' "drift${tab}app/run.sh${tab}demo/1"
expect_rc "a drift row refuses the walk" 4
walk_with "unsigned edit" '-' "signoff${tab}demo${tab}unsigned${tab}its status at the head is Draft"
expect_out "an unsigned sign-off row binds a pull request that is not spec-only" "fail${tab}signoff${tab}demo: its status at the head is Draft"

sed -i.bak "s|^program_alpha_spec_root: .*|program_alpha_spec_root: $repo|" "$tracked"
spec_pr "$sh_ready" specs/demo/requirements.md
hasnt "a spec root that is the repository root exempts nothing" "scope${tab}"
mv "$tmp/pr.saved.json" "$tmp/pr.json"
printf '%s\n' "$head" >"$tmp/headnow"

# A list that comes back at its cap may have been cut, and is refused.
sed 's/"hasNextPage": false/"hasNextPage": true/' "$tmp/threads.json" >"$tmp/t.json" && mv "$tmp/t.json" "$tmp/threads.json"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)
has "more threads than one read returns is marked" "truncated${tab}review threads"
walk_with "truncated" '-' "truncated${tab}files"
expect_rc "a truncated read is refused" 4
expect_out "named" "fail${tab}truncated${tab}the files read hit its cap"

# ---------------------------------------------------------------------------
# watch: one readiness-due event per new head of a green draft, landed in the
# event store.
# ---------------------------------------------------------------------------
snapdir="$fleet/mission-control/alpha/snapshots"
mkdir -p "$snapdir"
now=$(date +%s)
snap() { # snap <head of #7>
  printf 'format\t1\nsource\tforge\ntaken\t%s\n' "$now"
  printf 'pr\tacme/web\t7\t%s\ttrue\tMERGEABLE\tNONE\t0\tSUCCESS\t0\t0\tp1\n' "$1"
  printf 'pr\tacme/web\t8\t%s\ttrue\tMERGEABLE\tNONE\t2\tSUCCESS\t0\t0\tp2\n' "$H"
  printf 'pr\tacme/web\t9\t%s\tfalse\tMERGEABLE\tNONE\t0\tSUCCESS\t0\t0\tp3\n' "$H"
  printf 'pr\tacme/web\t10\t%s\ttrue\tMERGEABLE\tNONE\t0\tFAILURE\t0\t0\tp4\n' "$H"
}
snap "$H" >"$snapdir/forge"
OUT=$(mc_env env PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-readiness.sh" 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "the watcher runs with no arguments under the runner" 0
expect_eq "only the green draft with no open thread is due" "announced${tab}readiness-due${tab}acme:web:7"
mc_run mc-event.sh list --program alpha
expect_out "the event lands in the store, within the subject grammar" "readiness-due${tab}acme:web:7${tab}acme/web#7 head 111111111111"
mc_run mc-readiness.sh watch --program alpha
expect_rc "a second pass" 0
expect_eq "an announced head is not announced again" ""
snap "$head" >"$snapdir/forge"
mc_run mc-readiness.sh watch --program alpha
expect_eq "a new head is announced again" "announced${tab}readiness-due${tab}acme:web:7"

# A refused event leaves its head unannounced, so the next run raises it.
snap 3333333333333333333333333333333333333333 >"$snapdir/forge"
events_dir="$fleet/attention/mission-control/alpha/events"
chmod 500 "$events_dir"
if hermetic_access_denied w "$events_dir"; then
  mc_run mc-readiness.sh watch --program alpha
  chmod 700 "$events_dir"
  expect_rc "a refused event fails the run" 1
  mc_run mc-readiness.sh watch --program alpha
  expect_rc "the next run" 0
  expect_eq "raises it again, now stored" "announced${tab}readiness-due${tab}acme:web:7"
else
  chmod 700 "$events_dir"
  echo "skip: the refused event case (the mode does not deny writing here)"
fi

# Between one and two cadences old a snapshot still counts (a budget rung
# doubles the refresh); past twice its cadence it announces nothing.
printf 'format\t1\nsource\tforge\ntaken\t%s\npr\tacme/web\t12\t%s\ttrue\tMERGEABLE\tNONE\t0\tSUCCESS\t0\t0\tp6\n' $((now - 450)) "$H" >"$snapdir/forge"
mc_run mc-readiness.sh watch --program alpha
expect_out "a snapshot one and a half cadences old still announces" "announced${tab}readiness-due${tab}acme:web:12"
printf 'format\t1\nsource\tforge\ntaken\t%s\npr\tacme/web\t13\t%s\ttrue\tMERGEABLE\tNONE\t0\tSUCCESS\t0\t0\tp7\n' $((now - 660)) "$H" >"$snapdir/forge"
mc_run mc-readiness.sh watch --program alpha
expect_eq "one a minute past twice its cadence does not" ""

# A stale snapshot announces nothing.
printf 'format\t1\nsource\tforge\ntaken\t%s\npr\tacme/web\t11\t%s\ttrue\tMERGEABLE\tNONE\t0\tSUCCESS\t0\t0\tp5\n' $((now - 86400)) "$H" >"$snapdir/forge"
mc_run mc-readiness.sh watch --program alpha
expect_rc "a stale snapshot" 0
expect_eq "announces nothing" ""
printf 'format\t1\nsource\tforge\ntaken\tsoon\n' >"$snapdir/forge"
mc_run mc-readiness.sh watch --program alpha
expect_rc "a snapshot that cannot be read fails the watcher" 1
rm -f "$snapdir/forge"
mc_run mc-readiness.sh watch --program alpha
expect_rc "with none taken yet it waits quietly" 0
expect_eq "raising nothing" ""

sed -i.bak 's/^program_alpha_sources: .*/program_alpha_sources: {work-items: specs:record}/' "$tracked"
mc_run mc-readiness.sh watch --program alpha
expect_rc "a program with no code-state snapshot raises nothing, quietly" 0
expect_eq "nothing" ""

# ---------------------------------------------------------------------------
# CI holds only the flip. A ready flip is refused while a check is pending or
# red; a channel post or notice needs only that no check is red, and a red
# check names itself for log diagnosis.
# ---------------------------------------------------------------------------
walk_with "flip with a pending check" 's/^check\tlint\tNEUTRAL/check\tlint\tPENDING/'
expect_rc "a ready flip is refused while a check is pending" 4
expect_out "named as pending" "fail${tab}check${tab}lint is PENDING"
walk_with "flip with a red check" 's/^check\tlint\tNEUTRAL/check\tlint\tFAILURE/'
expect_rc "a ready flip is refused while a check is red" 4
complete | sed 's/^check\tlint\tNEUTRAL/check\tlint\tPENDING/' >"$tmp/ev"
mc_run mc-readiness.sh not-red --evidence "$tmp/ev"
expect_rc "a notice passes while a check is still pending" 0
expect_eq "a notice passes with the head" "not-red${tab}$H"
complete | sed 's/^check\tlint\tNEUTRAL/check\tlint\tFAILURE/' >"$tmp/ev"
mc_run mc-readiness.sh not-red --evidence "$tmp/ev"
expect_rc "a notice is refused while a check is red" 4
expect_out "a red check is named" "fail${tab}check${tab}lint is FAILURE"
expect_out "and routed to log diagnosis" "diagnose${tab}lint"
complete | sed 's/^check\tlint\tNEUTRAL/check\tlint\tSOMETHING_NEW/' >"$tmp/ev"
mc_run mc-readiness.sh not-red --evidence "$tmp/ev"
expect_rc "a notice is refused for a check state it does not know" 4
printf 'not an evidence file\n' >"$tmp/ev"
mc_run mc-readiness.sh not-red --evidence "$tmp/ev"
expect_rc "a notice is refused for a file without the format line" 4
expect_eq "and says so once" "red${tab}-
fail${tab}format${tab}the evidence file lacks \"# format: 1\""
complete >"$tmp/ev"
mc_run mc-readiness.sh not-red --evidence "$tmp/ev"
expect_rc "a notice passes with every check green" 0

# ---------------------------------------------------------------------------
# A ready pull request must have no unfinished check. The unfinished verdict
# names each check still queued, pending or in progress at the head; a finished
# head passes whatever its colour (a red window-lock is the operator's to
# bypass).
# ---------------------------------------------------------------------------
complete | sed 's/^check\tlint\tNEUTRAL/check\tlint\tPENDING/' >"$tmp/ev"
mc_run mc-readiness.sh unfinished --evidence "$tmp/ev"
expect_rc "a pending check is unfinished" 4
expect_out "the head is reported" "unfinished${tab}$H"
expect_out "the pending check is named" "fail${tab}check${tab}lint is PENDING"
complete | sed 's/^check\tlint\tNEUTRAL/check\tlint\tQUEUED/' >"$tmp/ev"
mc_run mc-readiness.sh unfinished --evidence "$tmp/ev"
expect_rc "a queued check is unfinished" 4
expect_out "the queued check is named" "fail${tab}check${tab}lint is QUEUED"
complete | sed 's/^check\tlint\tNEUTRAL/check\tlint\tIN_PROGRESS/' >"$tmp/ev"
mc_run mc-readiness.sh unfinished --evidence "$tmp/ev"
expect_rc "an in-progress check is unfinished" 4
expect_out "the in-progress check is named" "fail${tab}check${tab}lint is IN_PROGRESS"
complete | sed 's/^check\tlint\tNEUTRAL/check\tlint\tFAILURE/' >"$tmp/ev"
mc_run mc-readiness.sh unfinished --evidence "$tmp/ev"
expect_rc "a finished red check is no unfinished check" 0
expect_eq "a finished head is reported finished" "finished${tab}$H"
complete | sed 's/^check\tlint\tNEUTRAL/check\tlint\tPENDING\ncheck\tbuild\tQUEUED/' >"$tmp/ev"
mc_run mc-readiness.sh unfinished --evidence "$tmp/ev"
expect_rc "two unfinished checks hold" 4
expect_out "the first is named" "fail${tab}check${tab}lint is PENDING"
expect_out "and the second" "fail${tab}check${tab}build is QUEUED"
complete | sed 's/^check\tlint\tNEUTRAL/check\tplanwright\/pre-ready-flip\tPENDING/' >"$tmp/ev"
mc_run mc-readiness.sh unfinished --evidence "$tmp/ev"
expect_rc "the flip's own pending status is no unfinished check" 0
complete >"$tmp/ev"
mc_run mc-readiness.sh unfinished --evidence "$tmp/ev"
expect_rc "a head with every check finished passes" 0
printf 'not an evidence file\n' >"$tmp/ev"
mc_run mc-readiness.sh unfinished --evidence "$tmp/ev"
expect_rc "an evidence file without the format line is refused" 4
expect_out "and says why" "fail${tab}format${tab}the evidence file lacks \"# format: 1\""

if [ "$failures" -ne 0 ]; then
  echo "test-mc-readiness: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-readiness: all passed"
