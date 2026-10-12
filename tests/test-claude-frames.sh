#!/bin/bash
# Tests for scripts/claude-frames.sh, the `claude-frames` evidence kind
# (quota-handling REQ-E1.3, REQ-E1.4, REQ-E1.5, REQ-B1.4), and the account-wide
# label it carries into scripts/fleet-stats.sh render and a claude hold's push.
#
# Covered:
#   - persist keeps a worker's newest rate-limit frame, per window, and refuses
#     a line that is not one, a window out of range, and a planted symlink;
#   - a window reading whose reset has passed is ignored (a dead worker's),
#     and each window independently takes the furthest-future reset;
#   - clearance is granted only when every governed window has a reading
#     received after the hold began and below its lowest-rung descend
#     threshold, and refused when either window is above it or lacks a
#     post-hold reading, or when only a stated reset time has passed;
#   - a fleet with no frame (a subagent-only or headless fleet) and frames
#     whose readings are all stale report unmeasured, never cleared;
#   - forged frame files (a future receipt, a torn line, a link) are skipped;
#   - the usage gate's cached signal is unchanged by any frame;
#   - the read, fleet-stats.sh render, and a claude hold's push each carry the
#     account-wide label.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-claude-frames.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH
PLANWRIGHT_SECRET_SCREEN_TOOL=none
export PLANWRIGHT_SECRET_SCREEN_TOOL

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
CF="$repo_root/scripts/claude-frames.sh"
QH="$repo_root/scripts/quota-hold.sh"
FSTATS="$repo_root/scripts/fleet-stats.sh"
GATE="$repo_root/scripts/fleet-usage-gate.sh"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
pass() {
  echo "ok: $1"
}

[ -x "$CF" ] || fail "scripts/claude-frames.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# shellcheck source=tests/lib/fleet-home.sh
. "$here/lib/fleet-home.sh"

core_cfg="$tmp/core-defaults.yml"
repo="$tmp/repo"
adopter_root="$tmp/adopter"
mkdir -p "$repo/.claude" "$adopter_root"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$repo"
cat >"$core_cfg" <<'EOF'
notification_channel: push
quota_ledger_retention_days: 90
fleet_usage_read_cadence_seconds: 300
fleet_usage_signal_ttl_seconds: 900
fleet_usage_session_downshift: 50
fleet_usage_weekly_downshift: 60
EOF
local_cfg="$tmp/local.yml"
: >"$local_cfg"

home=""
new_home() {
  home="$tmp/home-$1"
  fleet_home_pin "$home" || fail "cannot pin the fleet home for $1"
}

cfenv() {
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    "$@"
}
cf() { cfenv /bin/sh "$CF" "$@"; }

NOW=1800000000
HOUR=3600

# frame <session-util> <session-reset> <weekly-util> <weekly-reset>: one
# rate_limit_event line in the shape the CLI emits, the overage window
# included so a key-prefix match would read the wrong window.
frame() {
  printf '{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":%s,"rateLimitType":"five_hour","unifiedWindows":{"five_hour":{"utilization":%s,"resetsAt":%s},"seven_day":{"utilization":%s,"resetsAt":%s},"seven_day_overage_included":{"utilization":0.99,"resetsAt":%s}}},"uuid":"u","session_id":"s"}\n' \
    "$2" "$1" "$2" "$3" "$4" "$4"
}

# put <worker> <received> <frame args...>: persist a frame for a worker.
put() {
  p_w=$1
  p_t=$2
  shift 2
  mkdir -p "$home/fleet/streamjson/$p_w"
  frame "$@" | cf persist --dir "$home/fleet/streamjson/$p_w" --now "$p_t" \
    || fail "persist for $p_w exited non-zero"
}

win() { printf '%s\n' "$1" | awk -F "$TAB" -v w="$2" '$1 == "window" && $2 == w'; }
verdict() { printf '%s\n' "$1" | awk -F "$TAB" '$1 == "verdict" { print $2 }'; }

# --- 1. persist -------------------------------------------------------------
new_home persist
w="$home/fleet/streamjson/w1"
mkdir -p "$w"
frame 0.31 $((NOW + HOUR)) 0.53 $((NOW + 5 * 86400)) | cf persist --dir "$w" --now "$NOW" \
  || fail "persist: a well-formed frame was refused"
[ "$(cat "$w/ratelimit")" = "frame${TAB}${NOW}${TAB}0.31${TAB}$((NOW + HOUR))${TAB}0.53${TAB}$((NOW + 5 * 86400))${TAB}end" ] \
  || fail "persist: the stored frame is not the five-hour and seven-day readings: $(cat "$w/ratelimit")"
frame 0.4 $((NOW + HOUR)) 0.6 $((NOW + 5 * 86400)) | cf persist --dir "$w" --now $((NOW + 60)) \
  || fail "persist: a newer frame was refused"
grep -q "^frame${TAB}$((NOW + 60))${TAB}0.4${TAB}" "$w/ratelimit" || fail "persist: the newer frame did not replace the older"
[ "$(wc -l <"$w/ratelimit" | tr -d ' ')" = 1 ] || fail "persist: the store keeps more than the newest frame"
pass "persist keeps the newest frame's session and weekly readings"

before=$(cat "$w/ratelimit")
for bad in '{"type":"result","subtype":"success"}' \
  '{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}' \
  "$(frame 1.5 $((NOW + HOUR)) -0.1 $((NOW + HOUR)))" \
  "$(frame 1e3 $((NOW + HOUR)) 0.2 1234567890123456)" \
  "$(frame 0.2 abc 0.2 '"x"')"; do
  rc=0
  printf '%s\n' "$bad" | cf persist --dir "$w" --now $((NOW + 120)) 2>/dev/null || rc=$?
  [ "$rc" = 1 ] || fail "persist: an unusable line exited $rc, not 1: $bad"
  [ "$(cat "$w/ratelimit")" = "$before" ] || fail "persist: an unusable line replaced the stored frame: $bad"
done
# One window in range and one out keeps the good one only.
frame 0.2 $((NOW + HOUR)) 7 $((NOW + HOUR)) | cf persist --dir "$w" --now $((NOW + 180)) \
  || fail "persist: a frame with one usable window was refused"
[ "$(cat "$w/ratelimit")" = "frame${TAB}$((NOW + 180))${TAB}0.2${TAB}$((NOW + HOUR))${TAB}-${TAB}-${TAB}end" ] \
  || fail "persist: the out-of-range window was not dropped: $(cat "$w/ratelimit")"
pass "persist refuses lines that carry no usable reading and drops a window out of range"

ln -s "$tmp/elsewhere" "$home/fleet/streamjson/w2" 2>/dev/null || :
mkdir -p "$home/fleet/streamjson/w3"
ln -s "$tmp/planted" "$home/fleet/streamjson/w3/ratelimit"
rc=0
frame 0.1 $((NOW + HOUR)) 0.1 $((NOW + HOUR)) | cf persist --dir "$home/fleet/streamjson/w3" --now "$NOW" 2>/dev/null || rc=$?
[ "$rc" = 6 ] || fail "persist: a symlinked frame file was not refused (exit $rc)"
[ ! -e "$tmp/planted" ] || fail "persist: wrote through a planted symlink"
rc=0
frame 0.1 $((NOW + HOUR)) 0.1 $((NOW + HOUR)) | cf persist --dir "$home/fleet/streamjson/w2" --now "$NOW" 2>/dev/null || rc=$?
[ "$rc" = 6 ] || fail "persist: a symlinked worker directory was not refused (exit $rc)"
rc=0
cf persist --dir "$home/fleet/streamjson/w1" --now nope </dev/null 2>/dev/null || rc=$?
[ "$rc" = 2 ] || fail "persist: a malformed --now exited $rc, not 2"
pass "persist refuses a planted symlink and a malformed argument"

# --- 2. Staleness and the furthest-future reading ---------------------------
new_home stale
# A dead worker's reading from the previous session window: its session reset
# has passed, so it is ignored even though it is the only low one.
put dead $((NOW - 7200)) 0.05 $((NOW - 60)) 0.10 $((NOW + 3 * 86400))
put live $((NOW - 600)) 0.70 $((NOW + HOUR)) 0.20 $((NOW + 2 * 86400))
out=$(cf read --now "$NOW") || fail "read exited non-zero"
win "$out" session | grep -q "^window${TAB}session${TAB}70${TAB}$((NOW + HOUR))${TAB}$((NOW - 600))${TAB}50${TAB}above$" \
  || fail "staleness: the past-reset session reading was not ignored: $out"
# The weekly window takes the dead worker's reading: its reset is further out.
win "$out" weekly | grep -q "^window${TAB}weekly${TAB}10${TAB}$((NOW + 3 * 86400))${TAB}$((NOW - 7200))${TAB}60${TAB}below$" \
  || fail "furthest-future: the weekly window did not take the furthest reset: $out"
pass "a past-reset reading is ignored, and each window takes its furthest-future reset"

# A reset further out than the throttle's ceiling is not a reading.
new_home ceiling
put far $((NOW - 60)) 0.10 $((NOW + 30 * 86400)) 0.10 $((NOW + 30 * 86400))
out=$(cf read --now "$NOW") || fail "read (ceiling) exited non-zero"
[ "$(verdict "$out")" = unmeasured ] || fail "ceiling: a beyond-ceiling reading was used: $out"
pass "a reset beyond the throttle's ceiling is no reading"

# --- 3. Clearance -----------------------------------------------------------
SINCE=$((NOW - 1800))
new_home clear
put a $((NOW - 3600)) 0.90 $((NOW + HOUR)) 0.90 $((NOW + 2 * 86400))
put b $((NOW - 60)) 0.10 $((NOW + HOUR)) 0.20 $((NOW + 2 * 86400))
rc=0
out=$(cf clearance --since "$SINCE" --now "$NOW") || rc=$?
[ "$rc" = 0 ] || fail "clearance: two post-hold readings below threshold exited $rc: $out"
[ "$(verdict "$out")" = cleared ] || fail "clearance: verdict is not cleared: $out"
pass "clearance granted when both windows have post-hold readings below threshold"

new_home weekly-high
put a $((NOW - 60)) 0.10 $((NOW + HOUR)) 0.65 $((NOW + 2 * 86400))
rc=0
out=$(cf clearance --since "$SINCE" --now "$NOW") || rc=$?
[ "$rc" = 1 ] || fail "clearance: a weekly window above threshold exited $rc, not 1"
[ "$(verdict "$out")" = held ] || fail "clearance: verdict with the weekly window high is not held: $out"
win "$out" weekly | grep -q "${TAB}above$" || fail "clearance: the weekly window is not reported above: $out"
pass "clearance refused when the session is low but the weekly is not"

new_home session-prehold
# The session reading with the furthest reset arrived before the hold; only
# the weekly window has a post-hold reading.
put early $((NOW - 3600)) 0.10 $((NOW + 2 * HOUR)) 0.10 $((NOW + 86400))
put late $((NOW - 60)) - - 0.10 $((NOW + 2 * 86400))
rc=0
out=$(cf clearance --since "$SINCE" --now "$NOW") || rc=$?
[ "$rc" = 1 ] || fail "clearance: a session window without a post-hold reading exited $rc, not 1: $out"
win "$out" session | grep -q "${TAB}pre-hold$" || fail "clearance: the session window is not reported pre-hold: $out"
win "$out" weekly | grep -q "${TAB}below$" || fail "clearance: the weekly window is not reported below: $out"
pass "clearance refused when only the weekly window has a post-hold reading"

new_home reset-only
# The hold's stated reset has passed and every reading predates the hold.
put old $((NOW - 7200)) 0.01 $((NOW + HOUR)) 0.01 $((NOW + 86400))
rc=0
out=$(cf clearance --since "$SINCE" --now "$NOW") || rc=$?
[ "$rc" = 1 ] || fail "clearance: readings from before the hold cleared it (exit $rc): $out"
pass "clearance refused on pre-hold readings alone, however low"

# A threshold the operator set: the session window's descend threshold is its
# downshift rung.
new_home knob
put a $((NOW - 60)) 0.35 $((NOW + HOUR)) 0.10 $((NOW + 86400))
printf 'fleet_usage_session_downshift: 30\n' >"$local_cfg"
rc=0
out=$(cf clearance --since "$SINCE" --now "$NOW") || rc=$?
: >"$local_cfg"
[ "$rc" = 1 ] || fail "knob: a session reading above the configured downshift threshold cleared"
win "$out" session | grep -q "${TAB}35${TAB}.*${TAB}30${TAB}above$" || fail "knob: the configured threshold was not used: $out"
pass "each window's threshold is its configured downshift rung"

# A reading exactly at its threshold is not below it, including the two-decimal
# fractions whose product with 100 rounds just under the integer.
new_home boundary
put a $((NOW - 60)) 0.57 $((NOW + HOUR)) 0.29 $((NOW + 86400))
printf 'fleet_usage_session_downshift: 57\nfleet_usage_weekly_downshift: 29\n' >"$local_cfg"
rc=0
out=$(cf clearance --since "$SINCE" --now "$NOW") || rc=$?
: >"$local_cfg"
[ "$rc" = 1 ] || fail "boundary: readings exactly at their thresholds cleared: $out"
win "$out" session | grep -q "${TAB}57${TAB}above$" || fail "boundary: the session reading at 57 is not above 57: $out"
win "$out" weekly | grep -q "${TAB}29${TAB}above$" || fail "boundary: the weekly reading at 29 is not above 29: $out"
pass "a reading exactly at its threshold is above it"

# A threshold set the usage gate refuses as malformed (out of range, or not
# strictly ascending up its ladder) never clears a hold either.
new_home malformed
put a $((NOW - 60)) 0.80 $((NOW + HOUR)) 0.10 $((NOW + 86400))
for bad in 'fleet_usage_session_downshift: 90' 'fleet_usage_weekly_downshift: 150' \
  'fleet_usage_weekly_defer_all: 80'; do
  printf '%s\n' "$bad" >"$local_cfg"
  rc=0
  out=$(cf clearance --since "$SINCE" --now "$NOW" 2>/dev/null) || rc=$?
  : >"$local_cfg"
  [ "$rc" = 4 ] || fail "malformed: '$bad' exited $rc, not 4: $out"
done
pass "a threshold set the usage gate refuses is refused"

# Two workers storing a frame in the same second see the same reset; the
# higher reading wins whichever directory find lists first, so the tie can
# never grant clearance. Both creation orders, since listing order follows it.
for order in "hi lo" "lo hi"; do
  new_home "tie-${order% *}"
  for who in $order; do
    case $who in
      hi) put hi $((NOW - 60)) 0.51 $((NOW + HOUR)) 0.10 $((NOW + 86400)) ;;
      lo) put lo $((NOW - 60)) 0.49 $((NOW + HOUR)) 0.10 $((NOW + 86400)) ;;
    esac
  done
  rc=0
  out=$(cf clearance --since "$SINCE" --now "$NOW") || rc=$?
  [ "$rc" = 1 ] || fail "tie ($order): the lower of two same-second readings cleared: $out"
  win "$out" session | grep -q "^window${TAB}session${TAB}51${TAB}" || fail "tie ($order): the higher reading did not win: $out"
done
pass "a same-second, same-reset tie takes the higher reading"

# --- 4. Unmeasured ----------------------------------------------------------
new_home subagent-only
# A fleet whose workers run on frameless backends leaves no frame file.
mkdir -p "$home/fleet/streamjson" "$home/fleet/headless/h1"
rc=0
out=$(cf clearance --since "$SINCE" --now "$NOW") || rc=$?
[ "$rc" = 1 ] || fail "unmeasured: a frameless fleet cleared (exit $rc)"
[ "$(verdict "$out")" = unmeasured ] || fail "unmeasured: a frameless fleet is not reported unmeasured: $out"
win "$out" session | grep -q "${TAB}unmeasured$" || fail "unmeasured: the session window is not unmeasured: $out"
out=$(cf read --now "$NOW") || fail "read over a frameless fleet exited non-zero"
[ "$(verdict "$out")" = unmeasured ] || fail "unmeasured: read over a frameless fleet is not unmeasured: $out"
pass "a fleet with no frame reports unmeasured, never headroom"

new_home all-stale
put a $((NOW - 9000)) 0.01 $((NOW - 10)) 0.01 $((NOW - 10))
out=$(cf read --now "$NOW") || fail "read (all stale) exited non-zero"
[ "$(verdict "$out")" = unmeasured ] || fail "unmeasured: a fleet whose readings are all past reset is not unmeasured: $out"
pass "a fleet with no live frame reports unmeasured"

# --- 5. Forged frame files --------------------------------------------------
new_home forged
mkdir -p "$home/fleet/streamjson/f1" "$home/fleet/streamjson/f2" "$home/fleet/streamjson/f3" "$home/fleet/streamjson/f4"
# A receipt in the future would read as post-hold whatever the hold.
printf 'frame\t%s\t0.01\t%s\t0.01\t%s\tend\n' $((NOW + 600)) $((NOW + HOUR)) $((NOW + 86400)) >"$home/fleet/streamjson/f1/ratelimit"
# A torn line, and one with an embedded field out of grammar.
printf 'frame\t%s\t0.01\t%s\n' $((NOW - 60)) $((NOW + HOUR)) >"$home/fleet/streamjson/f2/ratelimit"
printf 'frame\t%s\t0.01x\t%s\t0.01\t%s\tend\n' $((NOW - 60)) $((NOW + HOUR)) $((NOW + 86400)) >"$home/fleet/streamjson/f3/ratelimit"
printf 'frame\t%s\t0.01\t%s\t0.01\t%s\tend\n' $((NOW - 60)) $((NOW + HOUR)) $((NOW + 86400)) >"$tmp/linked"
ln -s "$tmp/linked" "$home/fleet/streamjson/f4/ratelimit"
rc=0
out=$(cf clearance --since "$SINCE" --now "$NOW") || rc=$?
[ "$rc" = 1 ] || fail "forged: a forged frame file cleared the hold: $out"
[ "$(verdict "$out")" = unmeasured ] || fail "forged: forged frame files were read as readings: $out"
pass "forged, torn, and linked frame files are skipped"

# --- 6. The usage gate is untouched -----------------------------------------
new_home gate
put a $((NOW - 60)) 0.10 $((NOW + HOUR)) 0.10 $((NOW + 86400))
cf read --now "$NOW" >/dev/null || fail "read (gate) exited non-zero"
cf clearance --since "$SINCE" --now "$NOW" >/dev/null || :
[ ! -e "$home/fleet/usage" ] || fail "gate: a frame read wrote the usage gate's signal cache"
sig=$(cfenv /bin/sh "$GATE" signal) || fail "gate: the usage gate's signal read failed"
[ "$sig" = "session${TAB}unavailable
weekly${TAB}unavailable" ] || fail "gate: the usage gate's signal changed after a frame: $sig"
pass "frames leave the usage gate's signal unchanged"

# --- 7. The account-wide label ----------------------------------------------
new_home label
put a $((NOW - 60)) 0.10 $((NOW + HOUR)) 0.10 $((NOW + 86400))
out=$(cf read --now "$NOW") || fail "read (label) exited non-zero"
printf '%s\n' "$out" | grep -q "^scope${TAB}account-wide${TAB}" || fail "label: the read carries no account-wide scope: $out"
label=$(cf label) || fail "label verb exited non-zero"
case $label in
  *account-wide*) ;;
  *) fail "label: the label does not say account-wide: $label" ;;
esac

# The render reads the real clock, so this fixture is stamped relative to it.
new_home render
real=$(date +%s)
put a $((real - 60)) 0.31 $((real + HOUR)) 0.53 $((real + 86400))
render=$(cfenv /bin/sh "$FSTATS" render 2>/dev/null) || fail "fleet-stats render exited non-zero"
line=$(printf '%s\n' "$render" | grep '^  Claude usage:') || fail "render: no Claude usage line: $render"
case $line in
  *account-wide*"session 31%"*"weekly 53%"*) ;;
  *) fail "render: the Claude usage line lacks its label or readings: $line" ;;
esac
case $line in
  *"fleet's"* | *"fleet used"* | *"workers used"*) fail "render: the reading is attributed to the fleet: $line" ;;
esac
new_home render-empty
render=$(cfenv /bin/sh "$FSTATS" render 2>/dev/null) || fail "fleet-stats render (empty) exited non-zero"
printf '%s\n' "$render" | grep -q '^  Claude usage:   account-wide; unmeasured' \
  || fail "render: a frameless fleet does not render unmeasured with its label: $render"
pass "the read and fleet-stats.sh render carry the account-wide label"

new_home push
cfenv /bin/sh "$QH" hold --vendor claude --unit spec-a:task-1 --step worker \
  --reason "rate limited" --now "$NOW" >/dev/null 2>&1 || fail "push: the claude hold failed"
marker=$(cat "$home/fleet/attention/push"/* 2>/dev/null) || fail "push: no attention event was pushed"
case $marker in
  *account-wide*) ;;
  *) fail "push: the claude hold's push carries no account-wide label: $marker" ;;
esac
cfenv /bin/sh "$QH" hold --vendor sample-cli --unit spec-a:task-1 --step panel \
  --reason "quota" --now "$NOW" >/dev/null 2>&1 || fail "push: the sample-cli hold failed"
for m in "$home/fleet/attention/push"/*; do
  case $(cat "$m") in
    *sample-cli*account-wide*) fail "push: a non-claude hold carries the claude label" ;;
  esac
done
pass "a claude hold's push carries the account-wide label"
