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
watch "$((now + 60))"
expect_rc "a watch inside the hold" 0
expect_no_out "a hold already announced is not announced again" "usage-held"

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
# The reset: the window's own epoch passes with the mirror gone stale.
# ---------------------------------------------------------------------------
after=$((week_at + 1))
touch -t 202001010000 "$mirror"
watch "$after"
expect_rc "the watch at the reset" 0
expect_out "the reset emits usage-reset" "event${tab}usage-reset${tab}weekly${tab}"
expect_out "the queued unit launches" "launched${tab}${qid}${tab}"
expect_out "the session stopped on the limit is resumed" "resumed${tab}${limited}"
expect_out "the claude quota hold is released" "released-quota${tab}claude"
mc_run mc-usage.sh held --program alpha
expect_rc "held reads clear after the reset" 1
mc_run mc-usage.sh list --program alpha
expect_no_out "the drained entry has left the queue" "$qid"
mc_run mission-control-launch.sh list
expect_out "the queued unit is a registered session" "${tab}next-one${tab}"
poll_for "$tmp/shim/first-stdin" "the next unit's brief" || fail "the queued session never read the brief queued for it"
poll_for "$tmp/shim/resumed-stdin" "usage window" || fail "the resumed session got no handover"
grep -q -- "--resume 0b6f0c1e-1111-4222-8333-444455556666" "$tmp/shim/argv" \
  || fail "the stopped session was not resumed from its own session"
# The runner's watcher loop leads its own process group and stops with it,
# so a session the drain starts or recovers must not join that group.
if command -v setsid >/dev/null 2>&1; then
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
expect_out "the quota store reads clear" "vendor${tab}claude${tab}clear"
mc_run mc-budget.sh rung --program alpha --now "$after" --load 0
expect_eq "the rung is normal again" "normal"
watch "$((after + 60))"
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
expect_no_out "a routine event is not reported" "mc-alpha-worker-c"
expect_no_out "a routine launch is not reported" "next-one"
if printf '%s\n' "$OUT" | awk -F '\t' 'NF && $1 != "landed" && $1 != "decision" && $1 != "failed" { bad = 1 } END { exit !bad }'; then
  fail "report printed a line that is not a landing, decision or failure: $OUT"
else
  ok "report prints landings, decisions and failures only"
fi

mc_run mc-event.sh emit --program alpha -- usage-reset weekly "the weekly usage window reset"
mc_run mc-wake.sh compose --program alpha mc-alpha-hub
expect_out "the wake carries the reset" "usage-reset weekly"
expect_out "the wake points the hub at the report" "mc-usage.sh' report --program alpha"

# A claude quota hold whose stated reset passed before any watch saw it is
# still released, and its reset announced, with no usage hold behind it.
mc_run quota-hold.sh hold --vendor claude --unit "alpha:late-one" --step worker --reason "fixture limit" --reset "$((after + 200))" --now "$((after + 100))"
case $RC in 0 | 3) ok "a second fixture claude quota hold" ;; *) fail "the second fixture quota hold failed ($RC): $ERR" ;; esac
watch "$((after + 300))"
expect_rc "the watch past an unseen quota reset" 0
expect_out "a quota hold first seen after its reset is released" "released-quota${tab}claude"
expect_out "its reset is announced" "event${tab}usage-reset${tab}quota${tab}"
mc_run quota-hold.sh status --vendor claude
expect_out "the quota store reads clear again" "vendor${tab}claude${tab}clear"

# A drain records a resume it could not prepare as failed, never as nothing.
mc_run mc-usage.sh enqueue --program alpha --resume "$limited"
expect_rc "enqueue a resume" 0
rid=$(printf '%s\n' "$OUT" | awk -F '\t' '$1 == "queued" { print $2 }')
mkdir -p "$fleet/mission-control/alpha/usage/queue/$rid/handover"
mc_run mc-usage.sh drain --program alpha --now "$((after + 400))"
expect_rc "a drain with no hold" 0
expect_out "a resume whose handover cannot be written is reported failed" "failed${tab}${rid}${tab}"

# ---------------------------------------------------------------------------
# The threshold knob.
# ---------------------------------------------------------------------------
write_tracked "mission_control_usage_hold: 95"
write_mirror 40 92
watch "$now"
expect_no_out "92% is under a 95 threshold" "usage-held"
write_tracked "mission_control_usage_hold: nope"
watch "$now"
expect_rc "an invalid repo-tracked threshold fails the watch" 1

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
