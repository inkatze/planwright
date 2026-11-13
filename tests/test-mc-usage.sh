#!/bin/bash
# Tests for scripts/mc-usage.sh — the usage-window duty: above the hold
# threshold launches are held and the next units queue; at the window's
# reset the queue drains, sessions stopped on a limit are resumed with a
# handover, and the first wake reports only landings, decisions and failures.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-usage.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }
tab=$(printf '\t')

for t in jq git; do
  command -v "$t" >/dev/null 2>&1 || {
    echo "FAIL: $t is required to run this suite" >&2
    exit 1
  }
done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/mc-usage.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
fleet="$tmp/fleet"
cleanup() {
  for d in "$fleet"/streamjson/*/; do
    [ -d "$d" ] || continue
    env PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-streamjson.sh" \
      stop "$(basename "$d")" --grace 1 >/dev/null 2>&1 || :
  done
  rm -rf "$tmp"
}
trap cleanup EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

# The status-line mirror the windows are read from, pinned to the scratch
# tree so a real one on the host never leaks in.
mirror="$tmp/rate-limits.json"
export PLANWRIGHT_USAGE_MIRROR="$mirror"

# The launcher needs the shipped defaults and profiles; the shim stands in
# for claude. A resumed session stays up reading its stdin, so a handover
# steered into it is recorded.
reset_mc_fixture
write_mc_posture_pass
cp "$repo_root/config/defaults.yml" "$core/config/defaults.yml"
for p in worker tower mission-control; do
  cp "$repo_root/config/$p-settings.json" "$core/config/"
done
mkdir -p "$tmp/bin" "$tmp/shim" "$fleet"
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
printf '%s\n' "$*" >>"$SHIM_DIR/argv"
printf '%s\n' '{"type":"system","subtype":"init","session_id":"0b6f0c1e-1111-4222-8333-444455556666"}'
case " $* " in
  *" --resume "*)
    while IFS= read -r line; do printf '%s\n' "$line" >>"$SHIM_DIR/resumed-stdin"; done
    ;;
  *)
    IFS= read -r line || line=''
    printf '%s\n' "$line" >>"$SHIM_DIR/first-stdin"
    ;;
esac
exit 0
SHIM
chmod +x "$tmp/bin/claude"
export PATH="$tmp/bin:$PATH" SHIM_DIR="$tmp/shim"
write_tracked() { # write_tracked [<extra line>]
  cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_home: $tmp/mc-home/alpha
program_alpha_duties: [alpha-duty]
program_alpha_budget: {host_load: 1000000}
EOF
  [ -z "${1:-}" ] || printf '%s\n' "$1" >>"$tracked"
}
write_tracked

now=$(date +%s)
reset_at=$((now + 3600))
week_at=$((now + 86400))
# write_mirror <session pct> <weekly pct>: the mirror, its mtime pinned to
# the fixture's clock.
write_mirror() {
  printf '{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}}\n' \
    "$1" "$reset_at" "$2" "$week_at" >"$mirror"
  TZ=UTC touch -t "$(date -u -d "@$now" +%Y%m%d%H%M.%S 2>/dev/null || date -u -r "$now" +%Y%m%d%H%M.%S)" "$mirror"
}
watch() { mc_run mc-usage.sh watch --program alpha --now "$1"; }

# poll_for <file> <needle>: wait up to ten seconds for a detached worker to
# write what the case checks.
poll_for() {
  pf_i=0
  while [ "$pf_i" -lt 100 ]; do
    grep -q -- "$2" "$1" 2>/dev/null && return 0
    sleep 0.1
    pf_i=$((pf_i + 1))
  done
  return 1
}

# ---------------------------------------------------------------------------
# Below the threshold nothing is held.
# ---------------------------------------------------------------------------
write_mirror 40 60
watch "$now"
expect_rc "a watch below the threshold" 0
expect_no_out "below the threshold no hold event" "usage-held"
mc_run mc-usage.sh held --program alpha
expect_rc "held reads clear below the threshold" 1
expect_eq "held prints clear" "clear"

# A hold that cannot be read is held, never clear: `held` exits 1 on a
# failure as on clear, so its callers read clear only from the word itself.
holdf="$fleet/mission-control/alpha/usage/hold"
mkdir -p "$holdf"
mc_run mc-budget.sh rung --program alpha --now "$now" --load 0
expect_eq "an unreadable usage hold is the hold-dispatch rung" "hold-dispatch"
printf '%s\n' "a fixture brief" >"$tmp/brief.md"
mc_run mission-control-launch.sh launch --program alpha --kind tower --scope unreadable-one --brief "$tmp/brief.md" --backend stream-json
expect_rc "the launcher refuses a launch when the usage hold cannot be read" 4
expect_err "the refusal says the hold cannot be read" "usage hold cannot be read"

# A launch past the hold the operator asked for is refused when its bypass
# cannot be recorded.
evdir="$fleet/attention/mission-control/alpha/events"
mkdir -p "$evdir"
chmod 555 "$evdir"
if [ -w "$evdir" ]; then
  ok "skipped: the event store stays writable to this user"
else
  mc_run mission-control-launch.sh launch --program alpha --kind tower --scope unrecorded-one --brief "$tmp/brief.md" --backend stream-json --operator-asked
  expect_rc "an operator-asked launch is refused when its bypass cannot be recorded" 4
  expect_err "the refusal says the bypass could not be recorded" "bypass could not be recorded"
  [ ! -s "$tmp/shim/argv" ] || fail "an unrecorded bypass started a session"
fi
chmod 755 "$evdir"
rmdir "$holdf"

# ---------------------------------------------------------------------------
# Above the threshold (the shipped 90): the hold, its one event, the budget
# rung and the launcher's refusal.
# ---------------------------------------------------------------------------
write_mirror 40 92
watch "$now"
expect_rc "a watch above the threshold" 0
expect_out "entering the hold emits one usage-held event" "event${tab}usage-held${tab}weekly${tab}"
mc_run mc-usage.sh held --program alpha
expect_rc "held reads held" 0
expect_out "held names the window, its reading and its reset" "held${tab}weekly${tab}92${tab}$week_at"
mc_run mc-usage.sh held --program alpha --now "$((week_at + 1))"
expect_rc "a hold whose every reset has passed reads clear, so no stopped watcher holds launches past it" 1
mc_run mc-usage.sh drain --program alpha --now "$now"
expect_rc "a drain is refused while the hold lasts" 1
mc_run mc-usage.sh drain --program alpha --now "$((week_at + 1))"
expect_rc "a drain is not refused by a hold whose every reset has passed" 0
watch "$((now + 60))"
expect_rc "a watch inside the hold" 0
expect_no_out "a hold already announced is not announced again" "usage-held"
expect_no_out "a hold with no run-to-100 rule raises no rule-conflict event" "usage-hold-rule-conflict"
mc_run mc-rules.sh add alpha --text "Hold launches when a usage window reaches 90%." --subject usage --source "operator, fixture" --date 2026-01-01
watch "$((now + 61))"
expect_no_out "a rule that sets a hold and says no run-to-100 stays routine" "usage-hold-rule-conflict"
mc_run mc-rules.sh add alpha --text "Run to 100% usage with no 90% or 95% stops: launch every ready unit." --subject usage-stops --source "operator, fixture" --date 2026-01-01
watch "$((now + 62))"
expect_out "a hold under a run-to-100 rule raises the failure event, naming the rule and the knob" "event${tab}usage-hold-rule-conflict${tab}r-2${tab}"
expect_out "the event says the hold contradicts the rule" "mission_control_usage_hold"
watch "$((now + 63))"
expect_out "the event is raised again on the next tick, not once" "event${tab}usage-hold-rule-conflict${tab}r-2${tab}"
if awk -F '\t' '$1 == "usage-hold-rule-conflict" && $2 == "failure" { f = 1 } END { exit !f }' "$repo_root/config/mc-event-classes.tsv"; then
  ok "the rule-conflict event is classed failure"
else
  fail "usage-hold-rule-conflict is not classed failure in config/mc-event-classes.tsv"
fi
long_rule="Run to 100% usage with no stops: $(printf 'padding %.0s' $(seq 1 90))"
mc_run mc-rules.sh add alpha --text "$long_rule" --subject usage-long --source "operator, fixture" --date 2026-01-01
watch "$((now + 65))"
expect_out "a long rule still raises the event, its text cut to fit the event limit" "event${tab}usage-hold-rule-conflict${tab}r-3${tab}"
mc_run mc-rules.sh supersede alpha r-3 --withdraw --source "operator, fixture" --date 2026-01-02
mc_run mc-rules.sh add alpha --text "The piano stops are tuned, and overrun to 100% is rare." --subject unrelated --source "operator, fixture" --date 2026-01-01
watch "$((now + 66))"
expect_no_out "a rule that merely contains the words inside other words is no conflict" "event${tab}usage-hold-rule-conflict${tab}r-4"
mc_run mc-rules.sh supersede alpha r-4 --withdraw --source "operator, fixture" --date 2026-01-02
mc_run mc-rules.sh supersede alpha r-2 --withdraw --source "operator, fixture" --date 2026-01-02
mc_run mc-rules.sh supersede alpha r-1 --withdraw --source "operator, fixture" --date 2026-01-02
watch "$((now + 64))"
expect_no_out "once the rule is withdrawn the event stops" "usage-hold-rule-conflict"

# A frame received before the hold began is no fresh reading: with the
# mirror stale, an older, lower frame for the same window never ends it.
mkdir -p "$fleet/streamjson/mc-alpha-frames"
printf 'frame\t%s\t-\t-\t0.5\t%s\tend\n' "$((now - 3600))" "$week_at" >"$fleet/streamjson/mc-alpha-frames/ratelimit"
touch -t 202001010000 "$mirror"
watch "$((now + 120))"
expect_rc "a watch with only a pre-hold frame" 0
expect_no_out "a frame from before the hold does not end it" "usage-reset"
mc_run mc-usage.sh held --program alpha --now "$((now + 120))"
expect_rc "the hold stands on a pre-hold frame" 0
rm -rf "$fleet/streamjson/mc-alpha-frames"
write_mirror 40 92

mc_run mc-budget.sh rung --program alpha --now "$now" --load 0
expect_eq "the usage hold is the hold-dispatch rung" "hold-dispatch"
mc_run mc-budget.sh admit --program alpha session --now "$now" --load 0
expect_rc "admit refuses a session under the usage hold" 1
expect_out "admit names the usage window" "weekly usage window at 92%"

printf '%s\n' "a fixture brief" >"$tmp/brief.md"
mc_run mission-control-launch.sh launch --program alpha --kind tower --scope held-one --brief "$tmp/brief.md" --backend stream-json
expect_rc "the launcher refuses a launch under the usage hold" 4
expect_err "the refusal names the queue to use" "mc-usage.sh enqueue"
[ ! -s "$tmp/shim/argv" ] || fail "a held launch started a session"

# ---------------------------------------------------------------------------
# The queue: durable, its brief copied, its trigger the usage-reset event.
# ---------------------------------------------------------------------------
printf '%s\n' "the next unit's brief" >"$tmp/next.md"
mc_run mc-usage.sh enqueue --program alpha --kind tower --scope next-one --brief "$tmp/next.md" --backend stream-json
expect_rc "enqueue a launch" 0
expect_out "enqueue prints the entry" "queued${tab}"
qid=$(printf '%s\n' "$OUT" | awk -F '\t' '$1 == "queued" { print $2 }')
rm -f "$tmp/next.md"
mc_run mc-usage.sh list --program alpha
expect_out "the entry waits on usage-reset" "entry${tab}${qid}${tab}launch${tab}usage-reset${tab}next-one"
mc_run mc-usage.sh enqueue --program alpha --kind tower --scope bad --brief "$tmp/absent.md"
expect_rc "enqueue refuses a brief that is not there" 2
mc_run mc-usage.sh enqueue --program alpha --kind nope --scope x --brief "$tmp/brief.md"
expect_rc "enqueue refuses an unknown kind" 2
mc_run mc-usage.sh enqueue --program alpha --resume mc-alpha-nobody-1
expect_rc "enqueue refuses to resume a session the program never launched" 2

# Work the operator asked for still starts; it becomes the session that
# stops on the limit below.
mc_run mission-control-launch.sh launch --program alpha --kind tower --scope limited-one --brief "$tmp/brief.md" --backend stream-json --operator-asked
expect_rc "an operator-asked launch starts under the hold" 0
limited=$(printf '%s\n' "$OUT" | awk -F '\t' '$1 == "launch" && $2 == "name" { print $3 }')
[ -n "$limited" ] || fail "the operator-asked launch printed no name"
poll_for "$tmp/shim/first-stdin" "a fixture brief" || fail "the operator-asked session never read its brief"
mc_run mc-event.sh list --program alpha
expect_out "a launch past the hold is recorded as a usage-bypass event" "${tab}usage-bypass${tab}${limited}${tab}"
sjdir="$fleet/streamjson/$limited"
pf_i=0
while [ "$pf_i" -lt 100 ] && { [ -e "$sjdir/supervisor.pid" ] || [ -e "$sjdir/worker.pid" ]; }; do
  sleep 0.1
  pf_i=$((pf_i + 1))
done
[ -s "$sjdir/session" ] || fail "the fixture session recorded no session id"
# The run died on the limit, as the supervisor records a rate-limit death.
printf 'result\tsuccess\t%s\ttrue\tlimited=claude\n' "$now" >"$sjdir/result"
mc_run fleet-streamjson.sh status "$limited"
expect_out "the fixture session reads limited" "status $limited limited "
head -c 70000 /dev/zero | tr '\0' a >"$tmp/big.md"
mc_run mc-usage.sh enqueue --program alpha --resume "$limited" --brief "$tmp/big.md"
expect_rc "enqueue refuses a resume brief over the steer cap" 2

# A claude quota hold whose stated reset passes with the window.
mc_run quota-hold.sh hold --vendor claude --unit "alpha:$limited" --step worker --reason "fixture limit" --reset "$reset_at" --now "$now"
case $RC in 0 | 3) ok "a fixture claude quota hold" ;; *) fail "the fixture quota hold failed ($RC): $ERR" ;; esac

# Events during the hold, which the reset's report draws from.
mc_run mc-event.sh emit --program alpha --now "$((now + 10))" -- session-landed mc-alpha-worker-a "acme/app#7 MERGED, retired"
mc_run mc-event.sh emit --program alpha --now "$((now + 11))" -- alpha-item pr-9 "approve the release"
mc_run mc-event.sh emit --program alpha --now "$((now + 12))" -- stall-dead mc-alpha-worker-b "worker: pid gone"
mc_run mc-event.sh emit --program alpha --now "$((now + 13))" -- pending-prompt mc-alpha-worker-c "a routine prompt"

# ---------------------------------------------------------------------------
# The reset: the window's own epoch and the quota's stated reset pass with
# the mirror gone stale. A stated reset is no evidence the limit cleared, so
# the longest-held stopped session is resumed alone as the probe and the
# rest wait for the reading it brings.
# ---------------------------------------------------------------------------
after=$((week_at + 1))
touch -t 202001010000 "$mirror"
watch "$after"
expect_rc "the watch at the reset" 0
expect_out "the stated reset probes the stopped session alone" "probe${tab}${limited}"
expect_no_out "a stated reset passing does not release the claude quota hold" "released-quota"
expect_no_out "the queue waits on the probe" "launched${tab}"
expect_no_out "a probe is no reset" "usage-reset"
poll_for "$tmp/shim/resumed-stdin" "stated reset passed" || fail "the probe session got no handover"
grep -q -- "--resume 0b6f0c1e-1111-4222-8333-444455556666" "$tmp/shim/argv" \
  || fail "the stopped session was not resumed from its own session"
# The runner's watcher loop leads its own process group and stops with it,
# so a session the drain starts or recovers must not join that group.
# BusyBox ps takes no -p, so the check runs only where ps can name a group.
if command -v setsid >/dev/null 2>&1 && [ -n "$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')" ]; then
  sup=$(head -n 1 "$sjdir/supervisor.pid" 2>/dev/null)
  sup_pg=$(ps -o pgid= -p "${sup:-0}" 2>/dev/null | tr -d ' ')
  our_pg=$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')
  if [ -z "$sup_pg" ] || [ "$sup_pg" = "$our_pg" ]; then
    fail "the recovered session runs in the watcher's process group (supervisor ${sup:-none}, group ${sup_pg:-none})"
  else
    ok "a recovered session is detached from the watcher's process group"
  fi
fi
mc_run quota-hold.sh status --vendor claude
expect_out "the quota store stays held through the probe" "vendor${tab}claude${tab}held"
mc_run mc-usage.sh held --program alpha --now "$after"
expect_rc "launches stay held while the quota hold lasts, its stated reset passed" 0
expect_out "held names the quota" "held${tab}quota${tab}"
watch "$((after + 60))"
expect_rc "a watch during the probe" 0
expect_no_out "one stated reset is probed once" "probe${tab}"

# The probe's reading, received after the hold began and under each window's
# lowest threshold, is the evidence: the hold is released and the queue drains.
mkdir -p "$fleet/streamjson/mc-alpha-frames"
printf 'frame\t%s\t0.1\t%s\t0.1\t%s\tend\n' "$((after + 90))" "$((after + 3600))" "$((after + 86400))" >"$fleet/streamjson/mc-alpha-frames/ratelimit"
watch "$((after + 120))"
expect_rc "the watch on the probe's reading" 0
expect_out "the reading releases the claude quota hold" "released-quota${tab}claude"
expect_out "the release emits usage-reset" "event${tab}usage-reset${tab}quota${tab}"
expect_out "the queued unit launches" "launched${tab}${qid}${tab}"
expect_no_out "the probe session, running again, is not resumed twice" "resumed${tab}${limited}"
rm -rf "$fleet/streamjson/mc-alpha-frames"
mc_run mc-usage.sh held --program alpha
expect_rc "held reads clear after the reset" 1
mc_run mc-usage.sh list --program alpha
expect_no_out "the drained entry has left the queue" "$qid"
mc_run mission-control-launch.sh list
expect_out "the queued unit is a registered session" "${tab}next-one${tab}"
poll_for "$tmp/shim/first-stdin" "the next unit's brief" || fail "the queued session never read the brief queued for it"
mc_run quota-hold.sh status --vendor claude
expect_out "the quota store reads clear" "vendor${tab}claude${tab}clear"
mc_run mc-budget.sh rung --program alpha --now "$((after + 120))" --load 0
expect_eq "the rung is normal again" "normal"
watch "$((after + 180))"
expect_rc "a watch after the reset" 0
expect_no_out "the reset is announced once" "usage-reset"

# ---------------------------------------------------------------------------
# The first wake after the reset reports only landings, decisions and
# failures.
# ---------------------------------------------------------------------------
mc_run mc-usage.sh report --program alpha
expect_rc "report" 0
expect_out "a landing is reported" "landed${tab}mc-alpha-worker-a${tab}acme/app#7 MERGED, retired"
expect_out "a decision is reported" "decision${tab}pr-9${tab}approve the release"
expect_out "a failure is reported" "failed${tab}mc-alpha-worker-b${tab}"
expect_out "a launch past the hold is reported" "bypass${tab}${limited}${tab}"
expect_no_out "a routine event is not reported" "mc-alpha-worker-c"
expect_no_out "a routine launch is not reported" "next-one"
if printf '%s\n' "$OUT" | awk -F '\t' 'NF && $1 != "landed" && $1 != "decision" && $1 != "failed" && $1 != "kept" && $1 != "bypass" { bad = 1 } END { exit !bad }'; then
  fail "report printed a line that is not a landing, decision, failure, kept entry or bypass: $OUT"
else
  ok "report prints landings, decisions, failures, kept entries and bypasses only"
fi

mc_run mc-event.sh emit --program alpha -- usage-reset weekly "the weekly usage window reset"
mc_run mc-wake.sh compose --program alpha mc-alpha-hub
expect_out "the wake carries the reset" "usage-reset weekly"
expect_out "the wake points the hub at the report" "mc-usage.sh' report --program alpha"

# A claude quota hold whose stated reset passed before any watch saw it,
# with no stopped session to probe, is not released on the clock: the watch
# says once that it waits, and a fresh reading releases it.
mc_run quota-hold.sh hold --vendor claude --unit "alpha:late-one" --step worker --reason "fixture limit" --reset "$((after + 200))" --now "$((after + 100))"
case $RC in 0 | 3) ok "a second fixture claude quota hold" ;; *) fail "the second fixture quota hold failed ($RC): $ERR" ;; esac
watch "$((after + 300))"
expect_rc "the watch past an unseen quota reset" 0
expect_no_out "a stated reset alone releases nothing" "released-quota"
expect_out "with nothing to probe the watch says it waits" "event${tab}usage-probe${tab}quota${tab}"
expect_out "the wait names the operator's resume" "quota-hold.sh resume --vendor claude"
watch "$((after + 360))"
expect_no_out "the wait is said once per stated reset" "usage-probe"
mkdir -p "$fleet/streamjson/mc-alpha-frames"
printf 'frame\t%s\t0.1\t%s\t0.1\t%s\tend\n' "$((after + 370))" "$((after + 3600))" "$((after + 86400))" >"$fleet/streamjson/mc-alpha-frames/ratelimit"
watch "$((after + 400))"
expect_out "a reading from after the hold began releases it" "released-quota${tab}claude"
expect_out "its reset is announced" "event${tab}usage-reset${tab}quota${tab}"
rm -rf "$fleet/streamjson/mc-alpha-frames"
mc_run quota-hold.sh status --vendor claude
expect_out "the quota store reads clear again" "vendor${tab}claude${tab}clear"

# A quota hold with no stated reset ends only on readings taken after it
# began: frames from before it are no evidence, a later one is.
mc_run quota-hold.sh hold --vendor claude --unit "alpha:unstated-one" --step worker --reason "fixture limit" --now "$((after + 500))"
case $RC in 0 | 3) ok "a fixture quota hold with no stated reset" ;; *) fail "the reset-less fixture quota hold failed ($RC): $ERR" ;; esac
mkdir -p "$fleet/streamjson/mc-alpha-frames"
printf 'frame\t%s\t0.1\t%s\t0.1\t%s\tend\n' "$((after + 400))" "$((after + 3600))" "$((after + 86400))" >"$fleet/streamjson/mc-alpha-frames/ratelimit"
watch "$((after + 600))"
expect_rc "a watch with only frames from before the quota hold" 0
expect_no_out "frames from before a quota hold do not release it" "released-quota"
printf 'frame\t%s\t0.1\t%s\t0.1\t%s\tend\n' "$((after + 700))" "$((after + 3600))" "$((after + 86400))" >"$fleet/streamjson/mc-alpha-frames/ratelimit"
watch "$((after + 800))"
expect_out "a frame from after the quota hold, under the threshold, releases it" "released-quota${tab}claude"
rm -rf "$fleet/streamjson/mc-alpha-frames"

# A drain outside a reset keeps a resume it could not make, uncounted.
mc_run mc-usage.sh enqueue --program alpha --resume "$limited"
expect_rc "enqueue a resume" 0
rid=$(printf '%s\n' "$OUT" | awk -F '\t' '$1 == "queued" { print $2 }')
mkdir -p "$fleet/mission-control/alpha/usage/queue/$rid/handover"
mc_run mc-usage.sh drain --program alpha --now "$((after + 900))"
expect_rc "a drain with no hold" 0
expect_out "a resume whose handover cannot be written is kept" "kept${tab}${rid}${tab}"
expect_no_out "a drain outside a reset fails nothing it keeps" "failed${tab}${rid}"
mc_run mc-usage.sh list --program alpha
expect_out "the kept resume stays queued" "entry${tab}${rid}${tab}"

# Only reset drains count an attempt: a launch the budget does not admit is
# kept uncounted and named in the reset's report, and a resume refused at
# three reset drains is reported failed and dropped.
mc_run mc-budget.sh record --program alpha sessions 99
mc_run mc-usage.sh enqueue --program alpha --kind tower --scope budget-one --brief "$tmp/brief.md" --backend stream-json
bid=$(printf '%s\n' "$OUT" | awk -F '\t' '$1 == "queued" { print $2 }')
reset_cycle() { # hold on the weekly window, then pass its reset
  write_mirror 40 92
  watch "$now"
  touch -t 202001010000 "$mirror"
  watch "$((week_at + 1))"
}
reset_cycle
expect_out "the reset drain runs" "event${tab}usage-reset${tab}weekly${tab}"
expect_out "a launch the budget refuses is kept" "kept${tab}${bid}${tab}"
expect_out "a failed resume is kept at its first reset" "kept${tab}${rid}${tab}"
mc_run mc-usage.sh report --program alpha
expect_out "the reset's report names the launch the budget kept" "kept${tab}${bid}${tab}"
reset_cycle
reset_cycle
expect_out "a resume refused at three reset drains is reported failed" "failed${tab}${rid}${tab}"
expect_out "a budget refusal is never counted" "kept${tab}${bid}${tab}"
mc_run mc-usage.sh list --program alpha
expect_no_out "the failed resume has left the queue" "$rid"
expect_out "the launch the budget kept stays queued" "entry${tab}${bid}${tab}"
mc_run mc-usage.sh report --program alpha
expect_out "the reset's report names the failed resume" "failed${tab}${rid}${tab}"
mc_run mc-budget.sh record --program alpha sessions 0
mc_run mc-usage.sh drop --program alpha "$bid"

# ---------------------------------------------------------------------------
# A hold that exists but does not parse keeps launches held.
# ---------------------------------------------------------------------------
printf 'window\tweekly\n' >"$fleet/mission-control/alpha/usage/hold"
mc_run mc-usage.sh held --program alpha
if [ "$RC" -ne 0 ] && [ "$OUT" != clear ]; then
  ok "a malformed hold never reads clear"
else
  fail "a malformed hold read as '$OUT' (exit $RC)"
fi
mc_run mc-budget.sh rung --program alpha --now "$after" --load 0
expect_eq "a malformed hold is the hold-dispatch rung" "hold-dispatch"
rm -f "$fleet/mission-control/alpha/usage/hold"

# ---------------------------------------------------------------------------
# The threshold knob.
# ---------------------------------------------------------------------------
write_tracked "mission_control_usage_hold: 95"
write_mirror 40 92
watch "$now"
expect_rc "a watch under a 95 threshold" 0
expect_no_out "92% is under a 95 threshold" "usage-held"
write_tracked "mission_control_usage_hold: nope"
watch "$now"
expect_rc "an invalid repo-tracked threshold fails the watch" 1
expect_err "the failure names the threshold knob" "mission_control_usage_hold"

# ---------------------------------------------------------------------------
# The duty ships live in the default set.
# ---------------------------------------------------------------------------
grep -q '^  - id: usage-window$' "$repo_root/config/duties.yaml" || fail "config/duties.yaml has no usage-window duty"
grep -q '^mission_control_default_duties:.*usage-window' "$repo_root/config/defaults.yml" \
  || fail "usage-window is not in the default duties"
grep -q '^mission_control_usage_hold: 90$' "$repo_root/config/defaults.yml" \
  || fail "the shipped hold threshold is not 90"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "ALL mc-usage tests passed"
