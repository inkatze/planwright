#!/bin/bash
# Tests for scripts/mc-event.sh and scripts/mc-wake.sh — a program's events
# in the attention store, the daemon-side wake relay for sessions without the
# mod, and the failsafe tick behind it (mission-control REQ-E1.3, REQ-M1.2;
# D-6).
#
# The stream-json path runs a real supervised worker over a shim CLI that
# records its stdin; the tmux path runs the real buffer-paste relay over a
# fake tmux on PATH.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-wake.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
# shellcheck source=tests/lib/poll-until.sh
. "$here/lib/poll-until.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$repo_root/scripts/mc-wake.sh" ] || {
  echo "FAIL: scripts/mc-wake.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

sj_pid=""
cleanup() {
  [ -z "$sj_pid" ] || kill "$sj_pid" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT

tab=$(printf '\t')

setup() {
  reset_mc_fixture
  rm -rf "$fleet"
  cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_sources: {work-items: specs:record}
EOF
}

# ---------------------------------------------------------------------------
# The event store: grammar, listing, marks.
# ---------------------------------------------------------------------------
setup
mc_run mc-event.sh emit --program alpha pr-ready pr-7 "seven is ready"
expect_rc "an event is recorded" 0
id1=$OUT
case $id1 in e[0-9]*.*) ok "the id is time-ordered" ;; *) fail "unexpected event id '$id1'" ;; esac
if [ -f "$fleet/attention/mission-control/alpha/events/$id1" ]; then
  ok "REQ-E1.3: the event lands in the attention store"
else
  fail "REQ-E1.3: the event is not under the attention store"
fi
mc_run mc-event.sh emit --program alpha "Bad Kind" pr-7
expect_rc "a kind outside the grammar is refused" 2
mc_run mc-event.sh emit --program alpha pr-ready 'pr;7'
expect_rc "a subject outside the grammar is refused" 2
mc_run mc-event.sh emit --program alpha pr-ready pr-7 "$(printf 'line\033[2Jtwo')"
expect_rc "text carrying a control byte is refused" 2
mc_run mc-event.sh list --program alpha --target tw
expect_out "a listed event carries its fields and the target's mark" "$id1$tab"
expect_out "an unsent event's mark is -" "seven is ready$tab-"
mc_run mc-event.sh mark --program alpha --target tw "$id1" submitted
mc_run mc-event.sh mark --program alpha --target tw "$id1" staged
mc_run mc-event.sh list --program alpha --target tw --pending
expect_eq "a submitted event is no longer pending, and staging does not undo it" ""

# ---------------------------------------------------------------------------
# REQ-E1.3: through the stream-json relay a wake is submitted to a session
# without the mod.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/bin" "$tmp/rec"
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
(sleep 120 && kill "$$" 2>/dev/null) &
wd=$!
trap 'kill "$wd" 2>/dev/null' EXIT
while IFS= read -r line; do
  printf '%s\n' "$line" >>"$SHIM_RECORD_DIR/stdin"
done
SHIM
chmod +x "$tmp/bin/claude"
setup
printf 'begin\n' >"$tmp/prompt"
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u PLANWRIGHT_ROOT \
  -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT -u PLANWRIGHT_LOCAL_CONFIG \
  -u PLANWRIGHT_CONFIG_DEFAULTS -u PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT \
  HOME="$fixhome" PLANWRIGHT_FLEET_STATE_DIR="$fleet" PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" \
  SHIM_RECORD_DIR="$tmp/rec" \
  /bin/sh "$repo_root/scripts/fleet-streamjson.sh" launch sjw mission-control:alpha \
  --prompt-file "$tmp/prompt" --foreground >"$tmp/sj.out" 2>&1 &
sj_pid=$!
sj() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u PLANWRIGHT_ROOT \
    -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT -u PLANWRIGHT_LOCAL_CONFIG \
    HOME="$fixhome" PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-streamjson.sh" "$@"
}
if poll_until --what "the worker's first turn" -- grep -q '"type":"user"' "$tmp/rec/stdin"; then
  ok "a fixture stream-json worker is live"
  mc_run mc-wake.sh target add --program alpha sjw
  expect_rc "a wake target is registered" 0
  mc_run mc-event.sh emit --program alpha pr-ready pr-9 "nine is ready"
  ev=$OUT
  mc_run mc-wake.sh relay --program alpha
  expect_out "REQ-E1.3: the relay submits the wake" "submitted${tab}sjw${tab}1"
  if poll_until --what "the wake turn" -- grep -q 'nine is ready' "$tmp/rec/stdin"; then
    ok "REQ-E1.3: the event reaches the mod-less session as a user turn"
  else
    fail "REQ-E1.3: the wake never reached the session"
  fi
  if grep 'nine is ready' "$tmp/rec/stdin" | grep -q '"type":"user"'; then
    ok "REQ-E1.3: the wake is a submitted user turn"
  else
    fail "REQ-E1.3: the wake is not a user turn"
  fi
  mc_run mc-event.sh list --program alpha --target sjw
  expect_out "the event is marked submitted" "$ev$tab"
  expect_out "with the submitted mark" "nine is ready${tab}submitted"
  mc_run mc-wake.sh tick --program alpha --now 5000
  expect_out "REQ-E1.3: a tick with nothing unsubmitted sends nothing" "idle${tab}sjw"
else
  fail "the fixture stream-json worker never started: $(cat "$tmp/sj.out")"
fi
sj stop sjw >/dev/null 2>&1
poll_until --what "the supervisor's exit" -- pid_gone "$sj_pid" || kill "$sj_pid" 2>/dev/null
poll_until --what "the worker's exit" -- pid_gone "$sj_pid" || fail "the fixture worker outlived its kill"
sj_pid=""

# ---------------------------------------------------------------------------
# REQ-E1.3, D-6: through the tmux relay a wake is only staged; one the relay
# could not deliver is found by the tick within one cadence.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/fakebin" "$tmp/tmux"
cat >"$tmp/fakebin/tmux" <<'EOF'
#!/bin/sh
d=$FAKE_TMUX_DIR
printf '%s\n' "$*" >>"$d/log"
case "$1" in
  capture-pane) cat "$d/pane" ;;
  load-buffer) cat >"$d/buffer" ;;
  paste-buffer)
    cat "$d/buffer" >>"$d/pane"
    printf '\n' >>"$d/pane"
    cp "$d/buffer" "$d/pasted"
    ;;
  *) : ;;
esac
EOF
chmod +x "$tmp/fakebin/tmux"
idle_pane='● Done.

────────────────────────────────────────
❯
────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle)'
dialog_pane='Do you want to proceed?
❯ 1. Yes
  2. No

Esc to cancel'

FAKE_TMUX_DIR="$tmp/tmux"
PLANWRIGHT_RELAY_CONFIRM_TRIES=2
PLANWRIGHT_RELAY_CONFIRM_SLEEP=0
export FAKE_TMUX_DIR PLANWRIGHT_RELAY_CONFIRM_TRIES PLANWRIGHT_RELAY_CONFIRM_SLEEP
saved_path=$PATH
PATH="$tmp/fakebin:$PATH"

setup
mc_run fleet-state.sh register tw mission-control:alpha --backend tmux --death-handle "tmux-window mc 3"
expect_rc "a tmux session in the fleet registry" 0
mc_run mc-wake.sh target add --program alpha tw
printf '%s\n' "$dialog_pane" >"$tmp/tmux/pane"
: >"$tmp/tmux/log"
mc_run mc-event.sh emit --program alpha pr-ready pr-11 "eleven is ready"
mc_run mc-wake.sh relay --program alpha
expect_out "D-6: the relay will not paste over an open dialog" "refused${tab}tw${tab}3"
if grep -q paste-buffer "$tmp/tmux/log"; then
  fail "D-6: something was pasted over the dialog"
else
  ok "D-6: nothing was pasted"
fi
printf '%s\n' "$idle_pane" >"$tmp/tmux/pane"
mc_run mc-wake.sh tick --program alpha --now 10000
expect_out "REQ-E1.3: the tick fires once its cadence has passed" "tick"
expect_out "REQ-E1.3: the tick finds the undelivered event and stages it" "staged${tab}tw${tab}1"
if grep -q "read $fleet/mission-control/alpha/wake/tw.msg" "$tmp/tmux/pasted"; then
  ok "D-6: the staged line points at the wake file"
else
  fail "D-6: the staged line is not a pointer: $(cat "$tmp/tmux/pasted")"
fi
if grep -q 'eleven is ready' "$fleet/mission-control/alpha/wake/tw.msg"; then
  ok "the wake file names the event"
else
  fail "the wake file lacks the event"
fi
if grep -q '1 event(s) pending' "$fleet/mission-control/alpha/wake/tw.msg"; then
  ok "the wake file counts the events"
else
  fail "the wake file lacks the count"
fi
mc_run mc-event.sh list --program alpha --target tw
expect_out "a staged event is marked staged" "eleven is ready${tab}staged"
mc_run mc-wake.sh tick --program alpha --now 10060
expect_out "REQ-E1.3: no second tick inside the cadence" "not-due${tab}240"
mc_run mc-wake.sh relay --program alpha
expect_out "the relay does not stage an event twice" "idle${tab}tw"

mc_run mc-event.sh emit --program alpha pr-ready pr-12 "twelve is ready"
printf '%s\n' "$idle_pane" >"$tmp/tmux/pane"
mc_run mc-wake.sh relay --program alpha
expect_out "REQ-E1.3: a new event is staged by the push relay itself" "staged${tab}tw${tab}1"

setup
mc_run mc-wake.sh target add --program alpha tw
mc_run fleet-state.sh register tw mission-control:alpha --backend tmux --death-handle "tmux-window mc 3"
: >"$tmp/tmux/log"
mc_run mc-wake.sh tick --program alpha --now 10000
expect_out "REQ-E1.3: a tick with nothing pending sends nothing" "idle${tab}tw"
if grep -q load-buffer "$tmp/tmux/log"; then
  fail "an idle tick touched the pane"
else
  ok "an idle tick touches no pane"
fi
PATH=$saved_path

# ---------------------------------------------------------------------------
# A session with the mod is left to the mod; an unregistered one is reported;
# the daemon pause sends nothing.
# ---------------------------------------------------------------------------
setup
mc_run mc-wake.sh target add --program alpha modded --mod
mc_run mc-wake.sh target add --program alpha ghost
mc_run mc-event.sh emit --program alpha pr-ready pr-13
mc_run mc-wake.sh relay --program alpha
expect_out "D-6: a session with the mod is woken by the mod" "mod${tab}modded"
expect_out "a target the fleet registry lacks is unreachable" "unreachable${tab}ghost${tab}not in the fleet registry"
mc_run mc-wake.sh target list --program alpha
expect_out "target list" "modded${tab}mod"
mc_run mc-wake.sh target remove --program alpha ghost
mc_run mc-wake.sh target list --program alpha
expect_no_out "target remove" "ghost"
mc_run mc-wake.sh target add --program alpha 'bad;handle'
expect_rc "a handle outside the grammar is refused" 2
printf '%s\n' "fleet_daemon_pause: true" >>"$tracked"
mc_run mc-wake.sh relay --program alpha
expect_eq "the relay honours the daemon pause" "paused"
mc_run mc-wake.sh tick --program alpha --now 99999
expect_eq "the tick honours the daemon pause" "paused"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-wake: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-wake: all passed"
