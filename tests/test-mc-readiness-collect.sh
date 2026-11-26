#!/bin/bash
# Tests for scripts/mc-readiness.sh: the collector over the forge and the step
# records, and the watcher (mission-control REQ-D1.8; D-25, D-26).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-readiness-collect.sh
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

# ---------------------------------------------------------------------------
# collect: the forge read, the step records and the guard, at the head. The
# gh stub runs the script's own jq programs over fixture JSON.
# ---------------------------------------------------------------------------

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
has "the PR-Agent workflow's run marker is read" "botmark${tab}github-actions[bot]${tab}4475.3${tab}$head${tab}success${tab}2026-11-18T01:00:00Z"
has "a person's run marker is read, for the walk to refuse" "botmark${tab}alice${tab}9.1${tab}$head${tab}success"
has "a marker at another head is read" "botmark${tab}github-actions[bot]${tab}5.1${tab}$H${tab}success"
hasnt "a comment that only quotes a marker is none" "${tab}6.1${tab}"
hasnt "a marker whose run id does not parse is none" "${tab}x.1${tab}"
has "the run attempt a workflow marker at the head names is read" "botattempt${tab}4475.3${tab}PR-Agent${tab}2026-11-18T00:50:00Z${tab}SUCCESS"
has "an attempt still running reads its status" "botattempt${tab}4476.1${tab}PR-Agent${tab}2026-11-18T00:55:00Z${tab}IN_PROGRESS"
hasnt "a person's marker never leads to an attempt read" "botattempt${tab}9.1"
if grep -q 'actions/runs/9/attempts' "$tmp/gh.calls"; then fail "a person's marker led to an attempt read"; else ok "and no such read is made"; fi
hasnt "a marker at another head leads to no attempt read" "botattempt${tab}5.1"
if grep -q 'pulls/7/files' "$tmp/gh.calls"; then fail "a pull request with no rename had its REST file list read"; else ok "the REST file list is read only for a rename or copy"; fi
# The collector parses the marker line the PR-Agent workflow writes, which the
# fixture comments above copy; a change to the workflow's line must reach both.
# shellcheck disable=SC2016 # the workflow's literal shell text
if grep -qF 'marker="<!-- pr-agent-run: id=$GITHUB_RUN_ID.$GITHUB_RUN_ATTEMPT head=$HEAD_SHA status=$STATUS -->"' "$repo_root/.github/workflows/pr-agent.yml"; then
  ok "the PR-Agent workflow writes the marker line the collector parses"
else
  fail "the PR-Agent workflow's marker line changed: update collect's marker read and this fixture"
fi
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
: >"$tmp/no-cond"
mc_run mc-readiness.sh walk --evidence "$tmp/collected-pa" --conditions "$tmp/no-cond"
expect_no_out "a collected re-run marker at the head meets the bot-review condition" "fail${tab}bot-review"
mv "$tmp/comments.json" "$tmp/comments.json.keep"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --worktree "$repo" --out "$tmp/collected-nomark"
expect_rc "collect when the comments cannot be read" 0
c=$(cat "$tmp/collected-nomark" 2>/dev/null)
hasnt "a failed comment read leaves no marker" "botmark${tab}"
mc_run mc-readiness.sh walk --evidence "$tmp/collected-nomark" --conditions "$tmp/no-cond"
expect_out "and the walk refuses the bot review" "fail${tab}bot-review${tab}no PR-Agent run at"
mv "$tmp/comments.json.keep" "$tmp/comments.json"
mv "$tmp/attempt-4475-3.json" "$tmp/attempt-4475-3.json.keep"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --worktree "$repo" --out "$tmp/collected-noatt"
expect_rc "collect when one run attempt cannot be read" 0
c=$(cat "$tmp/collected-noatt" 2>/dev/null)
hasnt "a failed attempt read leaves no attempt row" "botattempt${tab}4475.3"
has "and the other attempts are still read" "botattempt${tab}4476.1${tab}PR-Agent"
has "and its marker is still collected" "botmark${tab}github-actions[bot]${tab}4475.3${tab}"
mv "$tmp/attempt-4475-3.json.keep" "$tmp/attempt-4475-3.json"
printf '# jobs:\n#   image: pragent/pr-agent@sha256:0\njobs: {}\n' >"$repo/.github/workflows/pr-agent.yml"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --worktree "$repo" --out "$tmp/collected-pa"
c=$(cat "$tmp/collected-pa" 2>/dev/null)
hasnt "a workflow naming the PR-Agent image only in a comment states no bot-review requirement" "require${tab}pr-agent"
rm -f "$repo/.github/workflows/pr-agent.yml"
# The payload the ready-flip guard is asked about names the pull request and the
# repository as two separate arguments of one format.
if grep -qF "}}' \"\$3\" \"\$2\" >\"\$cl_tmp/payload\"" "$repo_root/scripts/mc-readiness.sh"; then ok "the guard payload takes the pull request and the repository as separate arguments"; else fail "the guard payload's printf arguments are malformed"; fi
# A draft: its state is read, and the workflow-run read, which only a ready
# pull request is judged by, is skipped.
cp "$tmp/pr.json" "$tmp/pr.json.keep"
sed -i.bak 's/"isDraft": false/"isDraft": true/' "$tmp/pr.json"
: >"$tmp/gh.calls"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --worktree "$repo" --out "$tmp/collected-draft"
expect_rc "collect over a draft" 0
c=$(cat "$tmp/collected-draft" 2>/dev/null)
has "a draft is read as a draft" "state${tab}draft"
hasnt "a draft has no run creation time read" "born${tab}"
if grep -q '^api repos/acme/web/actions/runs' "$tmp/gh.calls"; then fail "a draft's workflow runs were read"; else ok "a draft's workflow-run read is skipped"; fi
hasnt "a draft has no run marker read" "botmark${tab}"
if grep -q 'issues/7/comments' "$tmp/gh.calls"; then fail "a draft's comments were read"; else ok "a draft's comment read is skipped"; fi
cp "$tmp/pr.json.keep" "$tmp/pr.json"
# A failed run read leaves no creation time, and no failure.
mv "$tmp/runs.json" "$tmp/runs.json.keep"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --worktree "$repo" --out "$tmp/collected-noruns"
expect_rc "collect when the workflow runs cannot be read" 0
c=$(cat "$tmp/collected-noruns" 2>/dev/null)
hasnt "a failed run read leaves no creation time" "born${tab}"
has "and the checks are still read" "check${tab}build${tab}SUCCESS"
mv "$tmp/runs.json.keep" "$tmp/runs.json"
# A pull request opened ready has no ready_for_review event, so no flip time.
cp "$tmp/threads.json" "$tmp/threads.json.keep"
sed -i.bak '/"timelineItems"/d' "$tmp/threads.json"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --worktree "$repo" --out "$tmp/collected-noflip"
expect_rc "collect over a pull request never flipped" 0
c=$(cat "$tmp/collected-noflip" 2>/dev/null)
hasnt "a pull request with no ready event has no flip time" "flip${tab}"
cp "$tmp/threads.json.keep" "$tmp/threads.json"
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

# A list that comes back at its cap may have been cut, and is refused.
sed 's/"hasNextPage": false/"hasNextPage": true/' "$tmp/threads.json" >"$tmp/t.json" && mv "$tmp/t.json" "$tmp/threads.json"
PATH="$tmp/bin:$PATH" mc_run mc-readiness.sh collect --program alpha --repo acme/web --pr 7 --out "$tmp/collected"
c=$(cat "$tmp/collected" 2>/dev/null)
has "more threads than one read returns is marked" "truncated${tab}review threads"
walk_with "truncated" '-' "truncated${tab}files"
expect_rc "a truncated read is refused" 4
expect_out "named" "fail${tab}truncated${tab}the files read came back incomplete"
walk_with "truncated checks" '-' "truncated${tab}checks"
expect_out "a capped list is named by its cap" "fail${tab}truncated${tab}the checks read hit its cap"

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

if [ "$failures" -ne 0 ]; then
  echo "test-mc-readiness-collect: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-readiness-collect: all passed"
