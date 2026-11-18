#!/bin/bash
# Tests for scripts/mc-readiness.sh: the readiness walk over primary evidence
# at the current head, the evidence the session records, and the checks that
# hold a ready flip or a notice (mission-control REQ-D1.8, REQ-I1.7).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-readiness-walk.sh
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
expect_out "and names the verb that corrects a wrong start or end" "step-record.sh supersede corrects it"
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
expect_out "named by its thread" "fail${tab}finding${tab}github-actions[bot] t9 is unanswered"
walk_with "ready, label opt-out" - "$(rowsof state,ready require,pr-agent check,PR-Agent,SKIPPED)"
expect_rc "a skipped PR-Agent job (the skip-pr-agent label, a dependabot head) is the opt-out" 0
walk_with "ready, repository without PR-Agent" - "state${tab}ready"
expect_rc "a repository with no PR-Agent workflow needs no run" 0
walk_with "old evidence" - "require${tab}pr-agent"
expect_rc "evidence with no draft state reads as ready: a required run missing is refused" 4
expect_out "named" "fail${tab}bot-review${tab}no PR-Agent run at 111111111111"
walk_with "old evidence, run present" - "$(rowsof require,pr-agent check,PR-Agent,SUCCESS)"
expect_rc "and a successful run passes it" 0
walk_with "ready, check refusal leads" - "$(rowsof state,ready require,pr-agent check,PR-Agent,FAILURE 'thread,t8,open')"
case $OUT in
  *"fail${tab}check${tab}PR-Agent is FAILURE"*"fail${tab}thread${tab}t8 is open"*) ok "a check refusal is listed before a thread's, as a stall reason takes the first" ;;
  *) fail "the check refusal does not lead: $OUT" ;;
esac

# The flip's own runs, told from a too-early flip, with the timings of a real
# flip: it was at 00:42:21Z and its pending ci and PR-Agent runs were created
# at 00:42:23Z.
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

{
  complete
  flip_rows 2026-11-18T00:40:10Z 2026-11-18T00:42:23Z
  echo
} >"$tmp/ev"
mc_run mc-readiness.sh unfinished --evidence "$tmp/ev"
expect_rc "unfinished: a flip's runs are unfinished" 4
expect_out "unfinished: the too-early run is named so" "fail${tab}flip${tab}ci was still running at the flip"
expect_out "unfinished: the flip's own run is named so" "fail${tab}check${tab}PR-Agent is PENDING (run created 2026-11-18T00:42:23Z, after the flip"
{
  complete
  rowsof state,draft check,PR-Agent,PENDING
  echo
} >"$tmp/ev"
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
  echo "test-mc-readiness-walk: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-readiness-walk: all passed"
