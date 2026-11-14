#!/bin/bash
# Tests for scripts/mc-goals.sh — program goals and their done-when checks:
# a goal is done only when its confirmed check passes, merged work alone is
# never a pass, the check command is stored data run as written, and the
# store lives in the program home under one lock (mission-control REQ-N1.1,
# REQ-N1.2, REQ-N1.3, REQ-N1.4).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-goals.sh
# shellcheck disable=SC2015 # `A && ok || fail` reads as a check, ok never fails
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$repo_root/scripts/mc-goals.sh" ] || {
  echo "FAIL: scripts/mc-goals.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-goals.XXXXXX") || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"
# shellcheck source=tests/lib/mc-autonomy-fixture.sh
. "$here/lib/mc-autonomy-fixture.sh"

tab=$(printf '\t')
store="$home/goals.tsv"
repo_status0=$(git -C "$repo" status --porcelain)
# 2026-11-10T12:00:00Z
now=1794312000
day=86400

# A fake forge: `gh pr view <n> --repo <slug> --json state,title --jq ...`
# answers from $tmp/forge/pr-<n> (STATE<TAB>title), so no test reaches a real
# forge.
mkdir -p "$tmp/bin" "$tmp/forge"
cat >"$tmp/bin/gh" <<'EOF'
#!/bin/sh
[ "$1" = pr ] && [ "$2" = view ] || exit 2
f="$FAKE_FORGE/pr-$3"
[ -f "$f" ] || exit 1
cat "$f"
EOF
chmod +x "$tmp/bin/gh"
forge() { printf '%s\t%s\n' "$2" "$3" >"$tmp/forge/pr-$1"; } # forge <n> <STATE> <title>

goals() { # goals <verb> [args...]: run with the fake forge on PATH
  OUT=$(PATH="$tmp/bin:$PATH" FAKE_FORGE="$tmp/forge" mc_env /bin/bash "$repo_root/scripts/mc-goals.sh" "$@" --program alpha 2>"$tmp/stderr")
  RC=$?
  ERR=$(cat "$tmp/stderr")
}
status_of() { # status_of <id>: the list status column
  goals list
  printf '%s\n' "$OUT" | awk -F '\t' -v id="$1" '$1 == id { print $2 }'
}
item_count() { # item_count <pattern>: open follow-ups whose text matches
  awk -F '\t' -v p="$1" '!/^#/ && $5 == "open" && index($0, p) { n++ } END { print n + 0 }' "$kb/followups.tsv"
}
event_count() { # event_count <kind>
  mc_run mc-event.sh list --program alpha
  printf '%s\n' "$OUT" | awk -F '\t' -v k="$1" '$3 == k { n++ } END { print n + 0 }'
}
expect_status() { # expect_status <label> <id> <want>
  got=$(status_of "$2")
  if [ "$got" = "$3" ]; then ok "$1"; else fail "$1: status of $2 is '$got', wanted '$3'"; fi
}
goals_duty() { # goals_duty <args...>: the watcher as the runner starts it
  OUT=$(PATH="$tmp/bin:$PATH" FAKE_FORGE="$tmp/forge" mc_env env PLANWRIGHT_MC_DUTY=goal-check /bin/bash "$repo_root/scripts/mc-goals.sh" "$@" --program alpha 2>"$tmp/stderr")
  RC=$?
  ERR=$(cat "$tmp/stderr")
}
expect_items() { # expect_items <label> <id> <want>
  got=$(item_count "$2")
  if [ "$got" = "$3" ]; then ok "$1"; else fail "$1: $2 has $got open items, wanted $3"; fi
}

# ---------------------------------------------------------------------------
# REQ-N1.1: an unconfirmed check lists as unconfirmed and never as done;
# confirming records the operator's correction verbatim.
# ---------------------------------------------------------------------------
goals set --outcome "The Mac runs the current planwright" --statement "mac planwright version is current" \
  --command "true" --work "pr:inkatze/planwright#101"
expect_rc "set a goal with a drafted check" 0
g1=$OUT
case $g1 in g-[0-9]*) ok "set prints the goal id" ;; *) fail "set prints a goal id, got '$g1'" ;; esac
expect_status "REQ-N1.1: a goal with an unconfirmed check lists as unconfirmed" "$g1" unconfirmed
goals run "$g1"
expect_rc "REQ-N1.1: an unconfirmed check is never run" 1
expect_status "REQ-N1.1: refusing to run leaves it unconfirmed, never done" "$g1" unconfirmed

goals confirm "$g1" --command "test -d /"
expect_rc "REQ-N1.1: the operator corrects the command and confirms" 0
goals show "$g1"
expect_out "REQ-N1.1: the corrected command is shown verbatim" "test -d /"
expect_no_out "REQ-N1.1: the drafted command is replaced" "${tab}true${tab}"
[ "$(status_of "$g1")" != unconfirmed ] && ok "REQ-N1.1: a confirmed goal is no longer unconfirmed" || fail "REQ-N1.1: still unconfirmed after confirm"

# ---------------------------------------------------------------------------
# REQ-N1.2: a passing command marks the goal done with its evidence.
# ---------------------------------------------------------------------------
goals run "$g1"
expect_rc "REQ-N1.2: a confirmed command that exits 0 runs" 0
expect_out "REQ-N1.2: it reports passing" "passing${tab}$g1"
expect_status "REQ-N1.2: a passing confirmed check marks the goal done" "$g1" "done"
goals show "$g1"
expect_out "REQ-N1.2: the goal carries the evidence of the run" "exit 0"

# ---------------------------------------------------------------------------
# REQ-N1.2: merged work whose check fails, times out or has not run is
# merged but not done, naming the failure, with one routed-fix item.
# ---------------------------------------------------------------------------
forge 201 MERGED "ship the runner registration"
goals set --outcome "Runner registered" --statement "runner registers" --command "exit 3" --work "pr:inkatze/planwright#201"
g2=$OUT
goals confirm "$g2"
expect_rc "confirm with no correction keeps the drafted check" 0
expect_status "a confirmed check that has not run, work not yet seen merged, is open" "$g2" open
goals watch --now "$now"
expect_rc "the watcher pass runs the check of the merged goal" 0
expect_out "the watcher reports the failing check" "checked${tab}$g2${tab}failing"
expect_status "REQ-N1.2: merged work with a failing check is merged but not done" "$g2" merged-not-done
goals show "$g2"
expect_out "REQ-N1.2: the failure is named" "exit 3"
n=$(item_count "$g2")
[ "$n" = 1 ] && ok "REQ-N1.2: one routed-fix item for the failing goal" || fail "REQ-N1.2: expected 1 routed-fix item, got $n"
goals watch --now $((now + 60))
n=$(item_count "$g2")
[ "$n" = 1 ] && ok "REQ-N1.2: a later pass does not route the same failure again" || fail "REQ-N1.2: expected still 1 item, got $n"
goals confirm "$g2" --command "exit 5"
goals watch --now $((now + 7200))
expect_items "REQ-N1.2: a corrected check that fails again routes its own fix" "$g2" 2

forge 202 MERGED "slow check work"
goals set --outcome "Slow" --statement "slow check" --command "sleep 5" --work "pr:inkatze/planwright#202"
g3=$OUT
goals confirm "$g3"
goals watch --now "$now" --timeout 1
expect_out "REQ-N1.2: a timed-out check reports failing" "checked${tab}$g3${tab}failing"
goals show "$g3"
expect_out "REQ-N1.2: the timeout is named" "timed out"
expect_status "REQ-N1.2: a timed-out check on merged work is merged but not done" "$g3" merged-not-done
expect_items "REQ-N1.2: the timed-out check routes one fix" "$g3" 1

# A merge of work no goal tracks runs no check.
forge 999 MERGED "unrelated work"
before=$(item_count "mission-control")
goals watch --now "$now"
after=$(item_count "mission-control")
[ "$before" = "$after" ] && ok "REQ-N1.2: a merge of untracked work runs no check and routes nothing" || fail "REQ-N1.2: untracked merge changed the items ($before -> $after)"

# Tracked work still open: the check is not run.
forge 203 OPEN "still open"
goals set --outcome "Waiting" --statement "w" --command "true" --work "pr:inkatze/planwright#203"
g4=$OUT
goals confirm "$g4"
goals watch --now "$now"
expect_status "REQ-N1.2: tracked work not merged never reports done" "$g4" open

# Merged pull requests never count as a pass: merged + passing check -> done.
forge 203 MERGED "now merged"
goals watch --now "$now"
expect_status "REQ-N1.2: the merge triggers the check, and a pass makes it done" "$g4" "done"

# ---------------------------------------------------------------------------
# REQ-N1.3: daily and bring-up re-check; a failing re-check reopens with one
# line, a passing one writes nothing; a session check is not re-run.
# ---------------------------------------------------------------------------
sentinel_ok="$tmp/recheck-ok"
goals set --outcome "Stays true" --statement "flag file exists" --command "test -e $sentinel_ok" --work "pr:inkatze/planwright#203"
g5=$OUT
: >"$sentinel_ok"
goals confirm "$g5"
goals run "$g5" --now "$now"
expect_status "a done goal with a command check" "$g5" "done"
ev0=$(event_count goal-reopened)
it0=$(item_count "$g5")
goals watch --now $((now + 100))
ev1=$(event_count goal-reopened)
[ "$ev0" = "$ev1" ] && ok "REQ-N1.3: nothing is re-checked inside the day" || fail "REQ-N1.3: re-checked inside the day"
goals watch --now $((now + day + 100))
ev1=$(event_count goal-reopened)
it1=$(item_count "$g5")
[ "$ev0" = "$ev1" ] && [ "$it0" = "$it1" ] && ok "REQ-N1.3: a passing daily re-check writes no event and no item" || fail "REQ-N1.3: a passing re-check wrote something"
expect_status "REQ-N1.3: still done after a passing re-check" "$g5" "done"
rm -f "$sentinel_ok"
goals watch --now $((now + 3 * day)) --bring-up
ev1=$(event_count goal-reopened)
[ "$ev1" = $((ev0 + 1)) ] && ok "REQ-N1.3: a failing re-check reopens the goal with one operator line" || fail "REQ-N1.3: expected one goal-reopened event, got $((ev1 - ev0))"
expect_status "REQ-N1.3: the failing re-check reopens the goal" "$g5" merged-not-done
goals watch --now $((now + 3 * day + 60)) --bring-up
ev2=$(event_count goal-reopened)
[ "$ev2" = "$ev1" ] && ok "REQ-N1.3: the reopened goal raises its line once" || fail "REQ-N1.3: a second line was raised"
n=$(item_count "$g5")
[ "$n" = 1 ] && ok "REQ-N1.3: the reopening routes one fix" || fail "REQ-N1.3: expected 1 routed fix, got $n"

# The bring-up pass re-checks a done command goal inside the day.
: >"$sentinel_ok"
goals run "$g5" --now $((now + 4 * day))
expect_status "the goal is done again after the fix" "$g5" "done"
rm -f "$sentinel_ok"
goals watch --now $((now + 4 * day + 10)) --bring-up
expect_status "REQ-N1.3: bring-up re-checks even inside the day" "$g5" merged-not-done

# Session-based check: no command; done only on reported evidence.
forge 301 MERGED "session goal work"
goals set --outcome "Host runs the new version" --statement "look at the host" --work "pr:inkatze/planwright#301"
g6=$OUT
goals confirm "$g6"
expect_rc "a goal with no command confirms" 0
goals watch --now "$now"
expect_status "REQ-N1.2: a session goal with merged work and no evidence is merged but not done" "$g6" merged-not-done
launches=$(event_count goal-verify-due)
[ "$launches" = 1 ] && ok "REQ-N1.2: one verification request is raised for the session goal" || fail "REQ-N1.2: expected 1 goal-verify-due, got $launches"
goals watch --now $((now + 60))
launches=$(event_count goal-verify-due)
[ "$launches" = 1 ] && ok "REQ-N1.2: the session verification is not requested again" || fail "REQ-N1.2: re-requested ($launches)"
goals verify "$g6"
expect_rc "verify prepares the read-only verification launch" 0
expect_out "verify names the read-only session kind and goal scope" "launch${tab}reviewer${tab}goal-$g6"
brief=$(printf '%s\n' "$OUT" | awk -F '\t' '$1 == "launch" { print $4; exit }')
[ -f "$brief" ] && ok "verify wrote the brief" || fail "verify wrote no brief at '$brief'"
case $(cat "$brief" 2>/dev/null) in
  *"look at the host"*"read-only"* | *"read-only"*"look at the host"*) ok "the brief carries the check statement and the read-only rule" ;;
  *) fail "the brief lacks the statement or the read-only rule" ;;
esac
goals evidence "$g6" --holds no --text "host still on 0.70"
expect_status "REQ-N1.2: evidence that the outcome does not hold leaves it not done" "$g6" merged-not-done
expect_items "REQ-N1.2: evidence that the outcome does not hold routes one fix" "$g6" 1
goals run "$g6"
expect_rc "run refuses a goal whose check has no command" 1
goals evidence "$g6" --holds yes --text "host reports 0.75.2"
expect_status "REQ-N1.2: evidence that the outcome holds makes it done" "$g6" "done"
goals watch --now $((now + 10 * day)) --bring-up
expect_status "REQ-N1.3: a done session goal is not re-run on its own" "$g6" "done"
launches=$(event_count goal-verify-due)
[ "$launches" = 1 ] && ok "REQ-N1.3: no verification is requested for a done session goal" || fail "REQ-N1.3: re-requested a done session goal"

# attach and landed: a flight ref is tracked, and merged only when recorded.
goals set --outcome "Flight work" --statement "f" --command "true" --work "flight:mc-example-1"
g8=$OUT
goals confirm "$g8"
goals landed "$g8" --work "flight:other"
expect_rc "landed refuses a ref the goal does not track" 1
goals attach "$g8" --work "pr:inkatze/planwright#403"
expect_rc "attach tracks more work" 0
goals landed "$g8" --work "pr:inkatze/planwright#403"
expect_rc "landed refuses a pull request ref, which the forge answers" 1
goals landed "$g8" --work "flight:mc-example-1"
expect_rc "landed records the flight as merged" 0
expect_status "a goal tracking an unmerged pull request is still open" "$g8" open

# The runner starts the watcher bare: the first run after it is armed is the
# bring-up, once.
sentinel8="$tmp/bringup-ok"
: >"$sentinel8"
goals set --outcome "Bring-up" --statement "b" --command "test -e $sentinel8" --work "pr:inkatze/planwright#203"
g9=$OUT
goals confirm "$g9"
goals run "$g9" --now "$now"
rm -f "$sentinel8"
mkdir -p "$fleet/mission-control/alpha/watchers"
printf '1234\t%s\tgoal-check\tscripts/mc-goals.sh\t15m\tlow\n' "$now" >"$fleet/mission-control/alpha/watchers/goal-check.rec"
ev0=$(event_count goal-reopened)
goals_duty watch --now $((now + 10))
ev1=$(event_count goal-reopened)
[ "$ev1" = $((ev0 + 1)) ] && ok "REQ-N1.3: a bare watcher run after it is armed re-checks at bring-up" || fail "REQ-N1.3: no bring-up re-check from the bare watcher run"
: >"$sentinel8"
goals run "$g9" --now $((now + 20))
rm -f "$sentinel8"
goals_duty watch --now $((now + 30))
expect_status "REQ-N1.3: the next bare run inside the day is not a bring-up" "$g9" "done"

# ---------------------------------------------------------------------------
# REQ-N1.4: a hostile pull request title leaves no sentinel; the executed
# command equals the stored one byte for byte; the store is in the program
# home; concurrent writes serialize; a bad format is refused.
# ---------------------------------------------------------------------------
sentinel="$tmp/pwned"
forge 401 MERGED "\$(touch $sentinel) \`touch $sentinel\`"
copy="$tmp/executed-copy"
cmd="cp \"\$0\" '$copy'; exit 4"
goals set --outcome "Hostile title" --statement "h" --command "$cmd" --work "pr:inkatze/planwright#401"
g7=$OUT
goals confirm "$g7"
goals watch --now "$now"
[ ! -e "$sentinel" ] && ok "REQ-N1.4: a title with a command substitution leaves no sentinel" || fail "REQ-N1.4: the sentinel exists"
if [ -f "$copy" ] && [ "$(
  cat "$copy"
  printf x
)" = "$cmd"x ]; then
  ok "REQ-N1.4: the executed command equals the stored one byte for byte"
else
  fail "REQ-N1.4: the executed command differs from the stored one"
fi
n=$(item_count "$g7")
[ "$n" = 1 ] && ok "REQ-N1.4: the item was written" || fail "REQ-N1.4: expected the item, got $n"
goals show "$g7"
expect_out "REQ-N1.4: the evidence was written" "exit 4"

[ -f "$store" ] && ok "REQ-N1.4: the store sits under the program home" || fail "REQ-N1.4: no store at $store"
[ "$(sed -n 1p "$store")" = "# format: 1" ] && ok "REQ-N1.4: the store opens with its format line" || fail "REQ-N1.4: the store lacks a format line"
if [ "$(git -C "$repo" status --porcelain)" != "$repo_status0" ]; then
  fail "REQ-N1.4: a repository file changed: $(git -C "$repo" status --porcelain)"
else
  ok "REQ-N1.4: nothing is written in a repository"
fi

# A loaded host holds the lock longer than the shipped wait.
printf 'mission_control_kb_lock_wait: 120\n' >>"$tracked"
before=$(grep -c '^g-' "$store")
for i in 1 2 3 4 5 6; do
  (goals_out=$(PATH="$tmp/bin:$PATH" FAKE_FORGE="$tmp/forge" mc_env /bin/bash "$repo_root/scripts/mc-goals.sh" set --program alpha --outcome "parallel $i" --statement "p" 2>"$tmp/par-err-$i") && printf '%s\n' "$goals_out" >>"$tmp/par-ids") &
done
wait
after=$(grep -c '^g-' "$store")
ids=$(sort -u "$tmp/par-ids" | wc -l | tr -d ' ')
if [ "$((after - before))" = 6 ] && [ "$ids" = 6 ]; then
  ok "REQ-N1.4: concurrent writes serialize under the lock (six distinct goals)"
else
  fail "REQ-N1.4: concurrent writes lost or collided (rows +$((after - before)), ids $ids): $(cat "$tmp"/par-err-* 2>/dev/null | head -3)"
fi

cp "$store" "$tmp/store.good"
sed '1d' "$tmp/store.good" >"$store"
goals list
expect_rc "REQ-N1.4: a store with no format is refused" 1
expect_no_out "REQ-N1.4: nothing is reported done from it" "done"
goals watch --now "$now"
expect_rc "REQ-N1.4: the watcher refuses it too" 1
sed '1s/.*/# format: 99/' "$tmp/store.good" >"$store"
goals list
expect_rc "REQ-N1.4: a store with an unknown format is refused" 1
expect_no_out "REQ-N1.4: nothing is reported done from an unknown format" "done"
cp "$tmp/store.good" "$store"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
