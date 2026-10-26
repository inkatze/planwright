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
# The event store: grammar, listing, marks, pruning.
# ---------------------------------------------------------------------------
setup
mc_run mc-event.sh emit --program alpha pr-ready pr-7 "seven is ready"
expect_rc "an event is recorded" 0
id1=$OUT
case $id1 in e[0-9]*.*) ok "the id carries its second" ;; *) fail "unexpected event id '$id1'" ;; esac
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
mc_run mc-event.sh emit --program alpha pr-ready pr-7 "$(printf 'a\233[2Jb')"
expect_rc "text carrying a C1 byte is refused" 2
mc_run mc-event.sh emit --program alpha -- --program pr-7
expect_rc "after --, an option-shaped kind is a kind, refused by its grammar" 2
mc_run mc-event.sh emit --program alpha pr-ready pr-8
id2=$OUT
mc_run mc-event.sh list --program alpha --target tw
expect_out "a listed event carries its fields and the target's mark" "$id1$tab"
expect_out "an unsent event's mark is -" "seven is ready$tab-"
mc_run mc-event.sh mark --program alpha --target tw submitted "$id1" "$id2"
expect_rc "several events are marked in one call" 0
mc_run mc-event.sh mark --program alpha --target tw staged "$id1"
mc_run mc-event.sh list --program alpha --target tw --pending
expect_eq "submitted events are no longer pending, and staging does not undo it" ""
mc_run mc-event.sh mark --program alpha --target tw staged e1.abcd
expect_rc "marking an event that does not exist" 3

setup
mc_run mc-event.sh emit --program alpha --now 1000 pr-ready pr-old
old=$OUT
mc_run mc-event.sh mark --program alpha --target tw submitted "$old"
mc_run mc-event.sh emit --program alpha --now 900000 pr-ready pr-new
mc_run mc-event.sh prune --program alpha --now 900000
expect_eq "events past the retention are pruned" "pruned${tab}1"
mc_run mc-event.sh list --program alpha
expect_no_out "the pruned event is gone" "pr-old"
expect_out "a recent one stays" "pr-new"
if [ -e "$fleet/attention/mission-control/alpha/marks/tw/$old" ]; then
  fail "a pruned event's mark was left behind"
else
  ok "its marks go with it"
fi

# ---------------------------------------------------------------------------
# REQ-E1.3: through the stream-json relay a wake is submitted to a session
# without the mod.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/bin" "$tmp/rec"
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
(exec sleep 120) &
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
  if poll_until --what "the wake turn" -- grep -q 'pr-ready pr-9' "$tmp/rec/stdin"; then
    ok "REQ-E1.3: the event reaches the mod-less session as a user turn"
  else
    fail "REQ-E1.3: the wake never reached the session"
  fi
  if grep 'pr-ready pr-9' "$tmp/rec/stdin" | grep -q '"type":"user"'; then
    ok "REQ-E1.3: the wake is a submitted user turn"
  else
    fail "REQ-E1.3: the wake is not a user turn"
  fi
  if grep -q 'nine is ready' "$tmp/rec/stdin"; then
    fail "an event's free text was submitted as part of the turn"
  else
    ok "an event's free text stays in the store, never in the turn"
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
# could not deliver, or staged and never acknowledged, is found by the tick
# within one cadence.
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
    if [ ! -f "$d/paste-drops" ]; then
      cat "$d/buffer" >>"$d/pane"
      printf '\n' >>"$d/pane"
    fi
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

tmux_target() { # tmux_target: a fresh program with the tmux session tw
  setup
  rm -f "$tmp/tmux/paste-drops" "$tmp/tmux/pasted"
  mc_run fleet-state.sh register tw mission-control:alpha --backend tmux --death-handle "tmux-window mc 3"
  expect_rc "a tmux session in the fleet registry" 0
  mc_run mc-wake.sh target add --program alpha tw
  : >"$tmp/tmux/log"
}

tmux_target
printf '%s\n' "$dialog_pane" >"$tmp/tmux/pane"
mc_run mc-event.sh emit --program alpha pr-ready pr-11 "eleven is ready"
e11=$OUT
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
msg=$(sed -n 's/.*read \(.*\)$/\1/p' "$tmp/tmux/pasted")
case $msg in
  "$fleet/mission-control/alpha/wake/tw."*) ok "D-6: the staged line points at a wake file of its own" ;;
  *) fail "D-6: the staged line is not a pointer: $(cat "$tmp/tmux/pasted")" ;;
esac
if grep -q 'pr-ready pr-11' "$msg" && grep -q '1 event(s) pending' "$msg"; then
  ok "the wake file counts and names the events"
else
  fail "the wake file lacks the event or the count"
fi
if grep -q "mark --program alpha --target tw submitted $e11" "$msg"; then
  ok "a staged wake says how to acknowledge it"
else
  fail "the staged wake carries no acknowledgement"
fi
if grep -q 'eleven is ready' "$msg"; then
  fail "an event's free text reached the wake file"
else
  ok "an event's free text stays out of the wake"
fi
mc_run mc-event.sh list --program alpha --target tw
expect_out "a staged event is marked staged" "eleven is ready${tab}staged"
mc_run mc-wake.sh tick --program alpha --now 10060
expect_out "REQ-E1.3: no second tick inside the cadence" "not-due${tab}240"
mc_run mc-wake.sh relay --program alpha
expect_out "the relay does not stage an event twice" "idle${tab}tw"
# The human submitted the staged line without the session acknowledging:
# the next tick stages it again.
printf '%s\n' "$idle_pane" >"$tmp/tmux/pane"
mc_run mc-wake.sh tick --program alpha --now 10300
expect_out "REQ-E1.3: the tick re-stages a staged event nobody acknowledged" "staged${tab}tw${tab}1"
mc_run mc-event.sh mark --program alpha --target tw submitted "$e11"
printf '%s\n' "$idle_pane" >"$tmp/tmux/pane"
mc_run mc-wake.sh tick --program alpha --now 10600
expect_out "an acknowledged event is not sent again" "idle${tab}tw"

mc_run mc-event.sh emit --program alpha pr-ready pr-12 "twelve is ready"
printf '%s\n' "$idle_pane" >"$tmp/tmux/pane"
mc_run mc-wake.sh relay --program alpha
expect_out "REQ-E1.3: a new event is staged by the push relay itself" "staged${tab}tw${tab}1"

# A paste whose tag never shows is marked staged, never pasted again by the
# relay.
tmux_target
touch "$tmp/tmux/paste-drops"
printf '%s\n' "$idle_pane" >"$tmp/tmux/pane"
mc_run mc-event.sh emit --program alpha pr-ready pr-14
mc_run mc-wake.sh relay --program alpha
expect_out "an unconfirmed paste is reported as such" "unconfirmed${tab}tw${tab}1"
: >"$tmp/tmux/log"
mc_run mc-wake.sh relay --program alpha
expect_out "and not pasted again by the relay" "idle${tab}tw"

# A long backlog lists twenty and counts the rest.
tmux_target
printf '%s\n' "$idle_pane" >"$tmp/tmux/pane"
n=0
while [ "$n" -lt 23 ]; do
  mc_run mc-event.sh emit --program alpha pr-ready "pr-$n"
  n=$((n + 1))
done
mc_run mc-wake.sh relay --program alpha
expect_out "a backlog goes in one wake" "staged${tab}tw${tab}23"
msg=$(sed -n 's/.*read \(.*\)$/\1/p' "$tmp/tmux/pasted")
if grep -q -- '- and 3 more' "$msg" && [ "$(grep -c '^- pr-ready' "$msg")" -eq 20 ]; then
  ok "the wake lists twenty and counts the rest"
else
  fail "the wake does not cap its list: $(cat "$msg")"
fi

tmux_target
mc_run mc-wake.sh tick --program alpha --now 10000
expect_out "REQ-E1.3: a tick with nothing pending sends nothing" "idle${tab}tw"
if grep -q load-buffer "$tmp/tmux/log"; then
  fail "an idle tick touched the pane"
else
  ok "an idle tick touches no pane"
fi
printf '99999999999\n' >"$fleet/mission-control/alpha/last-tick"
mc_run mc-wake.sh tick --program alpha --now 20000
expect_out "a tick stamp from the future never holds the failsafe off" "tick"
PATH=$saved_path

# ---------------------------------------------------------------------------
# A session with the mod is left to the mod; unreachable targets are named;
# the daemon pause sends nothing.
# ---------------------------------------------------------------------------
setup
mc_run mc-wake.sh target add --program alpha modded --mod
mc_run mc-wake.sh target add --program alpha ghost
mc_run mc-wake.sh target add --program alpha gone
mc_run mc-wake.sh target add --program alpha printer
mc_run mc-wake.sh target add --program alpha windowless
mc_run fleet-state.sh register gone mission-control:alpha --backend tmux --death-handle "tmux-window mc 4"
mc_run fleet-state.sh retire gone mission-control:alpha --backend tmux --death-handle "tmux-window mc 4"
mc_run fleet-state.sh register printer mission-control:alpha --backend print --death-handle none
mc_run fleet-state.sh register windowless mission-control:alpha --backend tmux --death-handle "process 4242"
mc_run mc-event.sh emit --program alpha pr-ready pr-13
mc_run mc-wake.sh relay --program alpha
expect_out "D-6: a session with the mod is woken by the mod" "mod${tab}modded"
expect_out "a target the fleet registry lacks is unreachable" "unreachable${tab}ghost${tab}not in the fleet registry"
expect_out "a retired worker is unreachable" "unreachable${tab}gone${tab}retired"
expect_out "a backend with no session relay is unreachable" "unreachable${tab}printer${tab}backend print has no session relay"
expect_out "a tmux record with no window is unreachable" "unreachable${tab}windowless${tab}no valid tmux window recorded"
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
