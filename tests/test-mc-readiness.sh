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

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-readiness.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

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
walk_with "cadence stale" '-' "cadence${tab}gap${tab}post-pr${tab}stale${tab}2222222222222222222222222222222222222222"
expect_out "a stale point names where it completed" "fail${tab}cadence${tab}post-pr: completed only at 222222222222"
walk_with "cadence incomplete" '-' "cadence${tab}gap${tab}pre-ci${tab}incomplete${tab}-"
expect_out "an incomplete point says so" "fail${tab}cadence${tab}pre-ci: no completion record"
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
git -C "$repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m one
head=$(git -C "$repo" rev-parse HEAD)
rec() { mc_run mc-readiness.sh record --program alpha --repo "$1" --pr "$2" --head "$3" --kind screenshot --ref "$4" --judgment "$5"; }
rec acme/web 7 "$head" shots/home.png error
rec acme/web 7 "$head" shots/home.png ok
rec acme/web 7 "$H" shots/stale.png ok
rec acme/web 8 "$head" shots/other-pr.png ok
(cd "$repo" && PLANWRIGHT_ROOT="$core" /bin/bash "$repo_root/scripts/step-record.sh" new-run >/dev/null \
  && /bin/bash "$repo_root/scripts/step-record.sh" write --run 000001 --point convergence --step polish --kind skill \
    --target polish --hosting isolated --backend none --head "$head" --end-head "$head" \
    --start 2026-10-28T00:00:00Z --end 2026-10-28T00:01:00Z --outcome applied >/dev/null \
  && /bin/bash "$repo_root/scripts/step-record.sh" write --completion --run 000001 --point convergence --head "$head" >/dev/null) \
  || fail "the fixture step record"
mkdir -p "$tmp/bin"
cat >"$tmp/pr.json" <<EOF
{"headRefOid": "$head", "labels": [{"name": "ui"}], "files": [{"path": "src/app.c"}],
 "body": "## Summary\nAdds the thing.",
 "statusCheckRollup": [{"name": "build", "conclusion": "SUCCESS"},
   {"__typename": "CheckRun", "name": "title", "workflowName": "pr-title", "conclusion": "FAILURE", "startedAt": "2026-11-05T19:34:09Z"},
   {"__typename": "CheckRun", "name": "title", "workflowName": "pr-title", "conclusion": "SUCCESS", "startedAt": "2026-11-05T19:51:51Z"},
   {"__typename": "CheckRun", "name": "title", "workflowName": "pr-title", "conclusion": "FAILURE", "startedAt": "2026-11-05T19:50:18Z"},
   {"__typename": "CheckRun", "name": "title", "workflowName": "other-lint", "conclusion": "FAILURE", "startedAt": "2026-11-05T19:00:00Z"},
   {"__typename": "CheckRun", "name": "rerun", "workflowName": "ci", "conclusion": "SUCCESS", "startedAt": "2026-11-05T19:00:00Z"},
   {"__typename": "CheckRun", "name": "rerun", "workflowName": "ci", "status": "QUEUED", "conclusion": "", "startedAt": "0001-01-01T00:00:00Z"},
   {"context": "deploy", "state": "PENDING", "conclusion": ""}]}
EOF
cat >"$tmp/threads.json" <<'EOF'
{"data": {"repository": {"pullRequest": {"author": {"login": "me"},
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
if grep -q 'pr ready' "$tmp/gh.calls" 2>/dev/null; then fail "a flip was attempted"; else ok "nothing flips a pull request"; fi
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
# A worktree that moved past the forge's head speaks for another head.
git -C "$tmp/feature-wt" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m unpushed
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)
has "a worktree head that differs from the forge's is unaudited, naming both" "cadence${tab}unaudited${tab}the worktree $tmp/feature-wt is at"
git -C "$tmp/feature-wt" checkout -q --detach "$head" && git -C "$tmp/feature-wt" checkout -q -B feature
# The audit itself failing is unaudited, with the resolver's reason.
chmod 000 "$core/config/steps.yaml"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
chmod 644 "$core/config/steps.yaml"
c=$(cat "$tmp/collected" 2>/dev/null)
has "an audit that cannot resolve the cadence is unaudited, naming why" "cadence${tab}unaudited${tab}the audit in $tmp/feature-wt failed: step-run: the configured cadence did not resolve"
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
bundle demo Ready stale
sh_stale=$(commit_specs)
spec_pr "$sh_stale" specs/demo/design.md
has "a bundle edited after its sign-off is not signed off" "signoff${tab}demo${tab}unsigned${tab}its content at the head is not what the kickoff signed off"
spec_pr 5555555555555555555555555555555555555555 specs/demo/requirements.md
has "a head the repository does not hold is a spec-only scope" "scope${tab}spec-only${tab}5555555555555555555555555555555555555555"
has "held by one unsigned sign-off naming the fetch" "signoff${tab}*${tab}unsigned${tab}the head is not in"
spec_pr "$sh_ready" 'specs/Bad Name/requirements.md'
has "a bundle directory outside the spec identifier grammar is refused" "signoff${tab}Bad Name${tab}unsigned${tab}not a spec identifier"
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
mc_run mc-readiness.sh watch --program alpha
chmod 700 "$events_dir"
expect_rc "a refused event fails the run" 1
mc_run mc-readiness.sh watch --program alpha
expect_rc "the next run" 0
expect_eq "raises it again, now stored" "announced${tab}readiness-due${tab}acme:web:7"

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

sed -i.bak 's/^program_alpha_sources: .*/program_alpha_sources: {work-items: specs:record}/' "$tracked"
mc_run mc-readiness.sh watch --program alpha
expect_rc "a program with no code-state snapshot raises nothing, quietly" 0
expect_eq "nothing" ""

if [ "$failures" -ne 0 ]; then
  echo "test-mc-readiness: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-readiness: all passed"
