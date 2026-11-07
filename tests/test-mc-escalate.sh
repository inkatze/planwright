#!/bin/bash
# Tests for scripts/mc-escalate.sh — the session-keeper's escalation watcher:
# a worker request its program's mission control left pending past the
# owner's alarm, and a mission control held on its own open dialog, are
# raised one level up, to the hub mission control's events first and then to
# the operator through the notification seam, with no model in the path.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-escalate.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-escalate.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
write_programs() { # write_programs [<extra line>...]
  {
    printf 'mission_control_programs: [alpha, beta, hub]\n'
    for p in alpha beta hub; do
      printf 'program_%s_repositories: [%s]\n' "$p" "$repo"
      printf 'program_%s_spec_root: %s/specs\n' "$p" "$repo"
      printf 'program_%s_home: %s/mchome-%s\n' "$p" "$tmp" "$p"
    done
    printf 'notification_channel: editor-toast\n'
    for l in "$@"; do printf '%s\n' "$l"; done
  } >"$tracked"
}
write_programs

# Stubs: ps lists $tmp/ps.out, tmux answers list-panes from $tmp/panes and
# capture-pane -t <pane> from $tmp/pane-<pane>.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/ps" <<EOF
#!/bin/sh
cat "$tmp/ps.out" 2>/dev/null
EOF
cat >"$tmp/bin/tmux" <<EOF
#!/bin/sh
case "\$1" in
  list-panes) cat "$tmp/panes" 2>/dev/null ;;
  capture-pane)
    t=''
    while [ \$# -gt 0 ]; do [ "\$1" = -t ] && t=\$2; shift; done
    cat "$tmp/pane-\$t" 2>/dev/null || exit 1
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/ps" "$tmp/bin/tmux"
PATH="$tmp/bin:$PATH"
export PATH
: >"$tmp/ps.out"
: >"$tmp/panes"

reg="$fleet/mission-control/sessions"
mkdir -p "$reg"
# row <name> <program>: a launched stream-json registry row, as the launcher
# writes it.
row() {
  printf 'format\t1\nname\t%s\nstate\tlaunched\ntoken\tt\npid\t1\nprogram\t%s\nowner\tmission-control:%s\nkind\tworker\nscope\ts\nbackend\tstream-json\nhandle\t%s\nprofile\tworker\ntier\t-\nbrief\t-\nlaunched\t0\n' \
    "$1" "$2" "$2" "$1" >"$reg/$1"
}
# req <worker> <id> <received> [<state>]: one journal row of the worker.
req() {
  mkdir -p "$fleet/streamjson/$1"
  printf '%s\tpermission\t%s\t%s\n' "$2" "$3" "${4:-pending}" >>"$fleet/streamjson/$1/journal"
}
holder() { # holder <program>: a session holds the program's name
  mkdir -p "$fleet/mission-control/$1"
  printf 'format\t1\nsession\tmc-%s-attended-0000aaaa\nkind\tattended\nsince\t1\ngeneration\t1\n' "$1" >"$fleet/mission-control/$1/holder"
}
toasts() { cat "$fleet/attention/toasts" 2>/dev/null; }
hub_events() { mc_env /bin/bash "$repo_root/scripts/mc-event.sh" list --program hub 2>/dev/null; }
count_of() { printf '%s\n' "$1" | grep -c -F -- "$2"; }

esc() { mc_run mc-escalate.sh "$@"; }

T0=1800000000
row mc-alpha-worker-aaaaaaaaaa alpha
row mc-beta-worker-bbbbbbbbbb beta
holder hub
req mc-alpha-worker-aaaaaaaaaa r1-0001 "$T0"
req mc-beta-worker-bbbbbbbbbb r2-0002 "$T0"

# ---------------------------------------------------------------------------
# Under the owner's alarm plus the window, the request stays the owner's.
# ---------------------------------------------------------------------------
esc scan --program alpha --now $((T0 + 1000))
expect_rc "a scan inside the window" 0
expect_out "the request is reported at the owner level" "request${tab}mc-alpha-worker-aaaaaaaaaa${tab}r1-0001${tab}1000${tab}owner"
expect_no_out "another program's worker is not this program's to escalate" "mc-beta-worker"
if [ -z "$(hub_events)" ] && [ -z "$(toasts)" ]; then
  ok "nothing is escalated inside the window"
else
  fail "inside the window: hub events '$(hub_events)', toasts '$(toasts)'"
fi

# ---------------------------------------------------------------------------
# Past the alarm plus one window: the hub mission control hears it, once.
# ---------------------------------------------------------------------------
esc scan --program alpha --now $((T0 + 1900))
expect_rc "a scan past one window" 0
expect_out "the request is raised to the hub" "escalated${tab}hub${tab}alpha:mc-alpha-worker-aaaaaaaaaa"
ev=$(hub_events)
if [ "$(count_of "$ev" "mission-control-escalated${tab}alpha:mc-alpha-worker-aaaaaaaaaa")" = 1 ]; then
  ok "the hub's store holds one escalation event for the request"
else
  fail "hub events after one window: '$ev'"
fi
if [ -z "$(toasts)" ]; then ok "the operator is not pushed while the hub holds it"; else fail "a push before the second window: $(toasts)"; fi
esc scan --program alpha --now $((T0 + 2000))
ev=$(hub_events)
if [ "$(count_of "$ev" "mission-control-escalated")" = 1 ]; then
  ok "a later scan does not raise the same request twice"
else
  fail "hub events after a repeat scan: '$ev'"
fi

# ---------------------------------------------------------------------------
# Past two windows: the operator is pushed, once.
# ---------------------------------------------------------------------------
esc scan --program alpha --now $((T0 + 2800))
expect_rc "a scan past two windows" 0
expect_out "the request is raised to the operator" "escalated${tab}operator${tab}alpha:mc-alpha-worker-aaaaaaaaaa"
if [ "$(count_of "$(toasts)" "mc-alpha-worker-aaaaaaaaaa")" = 1 ]; then
  ok "the operator gets one push naming the worker"
else
  fail "toasts after two windows: '$(toasts)'"
fi
esc scan --program alpha --now $((T0 + 2900))
if [ "$(count_of "$(toasts)" "mc-alpha-worker-aaaaaaaaaa")" = 1 ] && [ "$(count_of "$(hub_events)" "mission-control-escalated")" = 1 ]; then
  ok "a later scan pushes nothing again"
else
  fail "after a repeat scan: toasts '$(toasts)', hub '$(hub_events)'"
fi

# ---------------------------------------------------------------------------
# An answered request leaves the escalation record, so a new one is raised
# afresh.
# ---------------------------------------------------------------------------
printf 'r1-0001\tpermission\t%s\tanswered\t%s\n' "$T0" $((T0 + 2950)) >"$fleet/streamjson/mc-alpha-worker-aaaaaaaaaa/journal"
esc scan --program alpha --now $((T0 + 3000))
expect_no_out "an answered request is not reported" "r1-0001"
if ! grep -q 'r1-0001' "$fleet/mission-control/alpha/escalate/sent" 2>/dev/null; then
  ok "the answered request's escalation record is pruned"
else
  fail "the sent record still holds the answered request: $(cat "$fleet/mission-control/alpha/escalate/sent")"
fi

# ---------------------------------------------------------------------------
# With no hub holding its name, the first level goes straight to the operator.
# ---------------------------------------------------------------------------
rm -f "$fleet/mission-control/hub/holder"
: >"$fleet/attention/toasts"
req mc-alpha-worker-aaaaaaaaaa r3-0003 "$T0"
esc scan --program alpha --now $((T0 + 1900))
expect_out "without a hub the operator is pushed at the first level" "escalated${tab}operator${tab}alpha:mc-alpha-worker-aaaaaaaaaa"
if [ "$(count_of "$(hub_events)" "r3-0003")" = 0 ] && [ "$(count_of "$(toasts)" "r3-0003")" = 1 ]; then
  ok "no hub event, one push"
else
  fail "no-hub run: hub '$(hub_events)', toasts '$(toasts)'"
fi
holder hub

# The hub never escalates to itself.
row mc-hub-worker-cccccccccc hub
req mc-hub-worker-cccccccccc r4-0004 "$T0"
esc scan --program hub --now $((T0 + 1900))
expect_out "the hub's own overdue request goes to the operator" "escalated${tab}operator${tab}hub:mc-hub-worker-cccccccccc"

# The escalation hub knob: none sends the first level to the operator.
write_programs "mission_control_escalation_hub: none"
req mc-alpha-worker-aaaaaaaaaa r5-0005 "$T0"
esc scan --program alpha --now $((T0 + 1900))
expect_out "hub none: the operator at the first level" "escalated${tab}operator${tab}alpha:mc-alpha-worker-aaaaaaaaaa"
write_programs "mission_control_escalation_hub: Not A Program"
esc scan --program alpha --now $((T0 + 1900))
expect_rc "a malformed repo-tracked hub knob fails the pass" 1
write_programs

# The window knob moves both levels.
write_programs "mission_control_escalation_window: 1m"
req mc-alpha-worker-aaaaaaaaaa r6-0006 "$T0"
esc scan --program alpha --now $((T0 + 970))
expect_out "a one-minute window raises at the alarm plus a minute" "request${tab}mc-alpha-worker-aaaaaaaaaa${tab}r6-0006${tab}970${tab}hub"
write_programs

# ---------------------------------------------------------------------------
# The mission control's own dialog: held past one window, the hub; past two,
# the operator; cleared, forgotten.
# ---------------------------------------------------------------------------
rm -rf "$fleet/streamjson/mc-alpha-worker-aaaaaaaaaa"
cat >"$tmp/dialog.txt" <<'EOF'
 Bash command

   fleet-streamjson.sh answer mc-alpha-worker-aaaaaaaaaa r1 --allow

 Do you want to proceed?
 ❯ 1. Yes
   2. No, and tell Claude what to do differently (esc)
EOF
printf '  ⏵⏵ accept edits on (shift+tab to cycle)\n> \n' >"$tmp/idle.txt"
esc scan --program alpha --now $((T0 + 100)) --pane "$tmp/dialog.txt"
expect_out "an open dialog is seen at the owner level" "self${tab}dialog${tab}0${tab}owner"
esc scan --program alpha --now $((T0 + 1000)) --pane "$tmp/dialog.txt"
expect_out "held one window, the dialog goes to the hub" "escalated${tab}hub${tab}alpha"
if [ "$(count_of "$(hub_events)" "mission-control-escalated${tab}alpha${tab}")" = 1 ]; then
  ok "the hub's store holds the dialog escalation, subject the program"
else
  fail "hub events for the dialog: '$(hub_events)'"
fi
: >"$fleet/attention/toasts"
esc scan --program alpha --now $((T0 + 1900)) --pane "$tmp/dialog.txt"
expect_out "held two windows, the dialog goes to the operator" "escalated${tab}operator${tab}alpha"
if [ "$(count_of "$(toasts)" "own dialog")" = 1 ]; then ok "one push names the open dialog"; else fail "dialog toasts: '$(toasts)'"; fi
esc scan --program alpha --now $((T0 + 2000)) --pane "$tmp/idle.txt"
expect_out "a cleared dialog reads clear" "self${tab}clear"
if [ ! -e "$fleet/mission-control/alpha/escalate/self" ]; then ok "the dialog's first-seen record is removed"; else fail "the self record survived a clear"; fi
esc scan --program alpha --now $((T0 + 2100)) --pane "$tmp/dialog.txt"
expect_out "a dialog reopened later starts a fresh hold" "self${tab}dialog${tab}0${tab}owner"

# ---------------------------------------------------------------------------
# Discovery: the session is the claude process whose prompt is
# /planwright:mission-control <program>, its pane the tmux pane above it.
# ---------------------------------------------------------------------------
rm -f "$fleet/mission-control/alpha/escalate/self"
cat >"$tmp/ps.out" <<'EOF'
    1     0 /sbin/init
  400     1 fish -c claude --name alpha-mission-control /planwright:mission-control alpha
  500   400 claude --name alpha-mission-control /planwright:mission-control alpha
  600     1 claude --name beta-mission-control /planwright:mission-control beta
  700     1 claude --name x /planwright:mission-control alphabet
EOF
printf '%%7\t400\n%%8\t600\n' >"$tmp/panes"
cp "$tmp/dialog.txt" "$tmp/pane-%7"
cp "$tmp/idle.txt" "$tmp/pane-%8"
esc scan --program alpha --now $((T0 + 3000))
expect_rc "a discovering scan" 0
expect_out "the program's pane is found and read" "self${tab}dialog${tab}0${tab}owner${tab}%7"
esc scan --program beta --now $((T0 + 3000))
expect_out "another program's session is its own" "self${tab}clear${tab}0${tab}owner${tab}%8"
printf '  900     1 node /planwright:mission-control gamma\n' >"$tmp/ps.out"
esc scan --program alpha --now $((T0 + 3000))
expect_out "no session found reads absent" "self${tab}absent"
expect_no_out "an absent session raises nothing" "escalated"
cat >"$tmp/ps.out" <<'EOF'
  500   400 claude /planwright:mission-control alpha
  501   400 claude /planwright:mission-control alpha
EOF
esc scan --program alpha --now $((T0 + 3000))
expect_out "two sessions under one name read ambiguous" "self${tab}ambiguous"

# ---------------------------------------------------------------------------
# The watcher form: no arguments, the program from the runner's environment.
# ---------------------------------------------------------------------------
: >"$tmp/ps.out"
OUT=$(mc_env env PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-escalate.sh" 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "the watcher form runs a scan" 0
expect_out "the watcher form reads the program from the runner" "self${tab}absent"

esc scan --program nosuch
expect_rc "an unconfigured program" 3
esc bogus --program alpha
expect_rc "an unknown verb" 2

# The shipped catalog arms it under session-keeper and wakes on its event.
if grep -A8 'id: session-keeper' "$repo_root/config/duties.yaml" | grep -q 'scripts/mc-escalate.sh@' \
  && grep -A8 'id: session-keeper' "$repo_root/config/duties.yaml" | grep -q 'mission-control-escalated'; then
  ok "session-keeper arms the escalation watcher and triggers on its event"
else
  fail "config/duties.yaml: session-keeper lacks the escalation watcher or trigger"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mc-escalate tests passed"
