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
# The owner's alarm threshold is read from the environment; the windows below
# assume its default.
unset PLANWRIGHT_STREAMJSON_PENDING_AGE

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

# Stubs: ps lists $tmp/ps.out for the session lookup's own flags and is the
# real ps otherwise (bounded-run.sh reads the real table); tmux answers
# list-panes from $tmp/panes and capture-pane -t <pane> from $tmp/pane-<pane>.
real_ps=$(command -v ps)
uid=$(id -u)
mkdir -p "$tmp/bin"
cat >"$tmp/bin/ps" <<EOF
#!/bin/sh
case "\$*" in
  '-ww -A -o pid= -o ppid= -o uid= -o args=') cat "$tmp/ps.out" 2>/dev/null ;;
  *) exec "$real_ps" "\$@" ;;
esac
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
# req <worker> <id> <received> [<state> [<re-opened>]]: one journal row of a
# live worker (its pidfile present).
req() {
  mkdir -p "$fleet/streamjson/$1"
  printf '1\n' >"$fleet/streamjson/$1/worker.pid"
  printf '%s\tpermission\t%s\t%s%s\n' "$2" "$3" "${4:-pending}" "${5:+	$5}" >>"$fleet/streamjson/$1/journal"
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
expect_out "the request is raised to the hub" "escalated${tab}hub${tab}mc-alpha-worker-aaaaaaaaaa"
ev=$(hub_events)
if [ "$(count_of "$ev" "mission-control-escalated${tab}mc-alpha-worker-aaaaaaaaaa")" = 1 ]; then
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
expect_out "the request is raised to the operator" "escalated${tab}operator${tab}mc-alpha-worker-aaaaaaaaaa"
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
expect_out "without a hub the operator is pushed at the first level" "escalated${tab}operator${tab}mc-alpha-worker-aaaaaaaaaa"
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
expect_out "the hub's own overdue request goes to the operator" "escalated${tab}operator${tab}mc-hub-worker-cccccccccc"

# The escalation hub knob: none sends the first level to the operator.
write_programs "mission_control_escalation_hub: none"
req mc-alpha-worker-aaaaaaaaaa r5-0005 "$T0"
esc scan --program alpha --now $((T0 + 1900))
expect_out "hub none: the operator at the first level" "escalated${tab}operator${tab}mc-alpha-worker-aaaaaaaaaa"
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
────────────────────────────────
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
d_print=$(awk -F '\t' '$1 == "dialog" { print $4 }' "$fleet/mission-control/alpha/escalate/self")
if hub_events | grep -F "note --program hub --shape answer --subject 'alpha dialog $d_print'" | grep -q -F -- "--decided-in hub"; then
  ok "the hub is told the exact note and relay to run"
else
  fail "the dialog escalation's instructions: '$(hub_events)'"
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
if [ "$(id -u)" != 0 ]; then
  esc scan --program alpha --now $((T0 + 3100)) --pane "$tmp/dialog.txt"
  expect_out "the reopened dialog held a window goes to the hub" "escalated${tab}hub${tab}alpha"
  raised=$(count_of "$(hub_events)" "mission-control-escalated${tab}alpha${tab}")
  chmod 000 "$fleet/mission-control/alpha/escalate/self"
  esc scan --program alpha --now $((T0 + 3200)) --pane "$tmp/dialog.txt"
  expect_rc "an unreadable dialog record fails the pass" 1
  expect_err "and says so" "cannot read the dialog record"
  [ ! -r "$fleet/mission-control/alpha/escalate/self" ] || fail "an unreadable dialog record was replaced"
  chmod 644 "$fleet/mission-control/alpha/escalate/self"
  esc scan --program alpha --now $((T0 + 3300)) --pane "$tmp/dialog.txt"
  if [ "$(count_of "$(hub_events)" "mission-control-escalated${tab}alpha${tab}")" = "$raised" ]; then
    ok "a dialog record unreadable for a pass is not raised again once it reads"
  else
    fail "after an unreadable record: hub events '$(hub_events)'"
  fi
fi
rm -f "$fleet/mission-control/alpha/escalate/self"
sed 1d "$tmp/dialog.txt" >"$tmp/norule.txt"
esc scan --program alpha --now $((T0 + 2300)) --pane "$tmp/norule.txt"
esc scan --program alpha --now $((T0 + 3200)) --pane "$tmp/norule.txt"
expect_out "a dialog with no opening rule held one window goes to the hub" "escalated${tab}hub${tab}alpha"
last=$(hub_events | tail -n 1)
case $last in
  *mc-pane-answer.sh*) fail "the unbindable dialog's escalation names the relay: '$last'" ;;
  *"answers it at its pane"*) ok "the hub is told to have a dialog the relay cannot bind answered at its pane" ;;
  *) fail "the unbindable dialog's escalation: '$last'" ;;
esac
rm -f "$fleet/mission-control/alpha/escalate/self"

# ---------------------------------------------------------------------------
# Discovery: the session is the claude process whose prompt is
# /planwright:mission-control <program>, its pane the tmux pane above it.
# ---------------------------------------------------------------------------
rm -f "$fleet/mission-control/alpha/escalate/self"
sed "s/ UID / $uid /" >"$tmp/ps.out" <<'EOF'
    1     0     0 /sbin/init
  400     1 UID fish -c claude --name alpha-mission-control /planwright:mission-control alpha
  500   400 UID claude --name alpha-mission-control /planwright:mission-control alpha
  600     1 UID claude --name beta-mission-control /planwright:mission-control beta
  700     1 UID claude --name x /planwright:mission-control alphabet
EOF
printf '%%7\t400\n%%8\t600\n' >"$tmp/panes"
cp "$tmp/dialog.txt" "$tmp/pane-%7"
cp "$tmp/idle.txt" "$tmp/pane-%8"
esc scan --program alpha --now $((T0 + 3000))
expect_rc "a discovering scan" 0
expect_out "the program's pane is found and read" "self${tab}dialog${tab}0${tab}owner${tab}%7"
esc scan --program beta --now $((T0 + 3000))
expect_out "another program's session is its own" "self${tab}clear${tab}0${tab}owner${tab}%8"
printf '  900     1 %s node /planwright:mission-control gamma\n' "$uid" >"$tmp/ps.out"
esc scan --program alpha --now $((T0 + 3000))
expect_out "no session found reads absent" "self${tab}absent"
expect_no_out "an absent session raises nothing" "escalated"
sed "s/ UID / $uid /" >"$tmp/ps.out" <<'EOF'
  500   400 UID claude /planwright:mission-control alpha
  501   400 UID claude /planwright:mission-control alpha
EOF
esc scan --program alpha --now $((T0 + 3000))
expect_out "two sessions under one name read ambiguous" "self${tab}ambiguous"
printf '  500   400 %s claude /planwright:mission-control alpha\n  501   400 4242424 claude /planwright:mission-control alpha\n' "$uid" >"$tmp/ps.out"
esc scan --program alpha --now $((T0 + 3000))
expect_out "another account's process neither stands in nor makes it ambiguous" "self${tab}dialog${tab}0${tab}owner${tab}%7"
# No session found keeps the hold and what it raised: the dialog seen again
# holds on, and is not raised twice.
esc scan --program alpha --now $((T0 + 4000))
expect_out "the dialog held a window is raised to the hub" "escalated${tab}hub${tab}alpha"
cp "$tmp/ps.out" "$tmp/ps.saved"
: >"$tmp/ps.out"
esc scan --program alpha --now $((T0 + 4100))
expect_out "a pass that finds no session" "self${tab}absent"
if [ -s "$fleet/mission-control/alpha/escalate/self" ] && grep -q "^self${tab}$((T0 + 3000))${tab}500${tab}.*${tab}hub$" "$fleet/mission-control/alpha/escalate/sent"; then
  ok "keeps the dialog's record and its hub escalation"
else
  fail "after an absent pass: self '$(cat "$fleet/mission-control/alpha/escalate/self" 2>/dev/null)', sent '$(cat "$fleet/mission-control/alpha/escalate/sent" 2>/dev/null)'"
fi
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$fleet/mission-control/alpha/escalate/self"
  esc scan --program alpha --now $((T0 + 4150))
  chmod 644 "$fleet/mission-control/alpha/escalate/self"
  expect_rc "an absent pass over an unreadable dialog record fails" 1
  if grep -q "^self${tab}$((T0 + 3000))${tab}500${tab}.*${tab}hub$" "$fleet/mission-control/alpha/escalate/sent"; then
    ok "and keeps the hub escalation it cannot match to a record"
  else
    fail "an unreadable record dropped what it raised: '$(cat "$fleet/mission-control/alpha/escalate/sent" 2>/dev/null)'"
  fi
fi
cp "$tmp/ps.saved" "$tmp/ps.out"
esc scan --program alpha --now $((T0 + 4200))
expect_out "the dialog seen again holds on" "self${tab}dialog${tab}1200${tab}hub${tab}%7"
expect_no_out "and is not raised again" "escalated${tab}hub"
# A session whose pane cannot be read fails the pass and keeps the hold.
: >"$tmp/panes"
esc scan --program alpha --now $((T0 + 4300))
expect_rc "an unreadable pane fails the pass" 1
expect_out "and reads unreadable" "self${tab}unreadable"
if [ -s "$fleet/mission-control/alpha/escalate/self" ]; then ok "the hold survives an unreadable pane"; else fail "an unreadable pane dropped the hold"; fi
printf '%%7\t400\n%%8\t600\n' >"$tmp/panes"

# ---------------------------------------------------------------------------
# What reads as an open dialog: text below the signature that only an open
# input box or a running turn shows means the dialog is not open.
# ---------------------------------------------------------------------------
rm -f "$fleet/mission-control/alpha/escalate/self"
{
  cat "$tmp/dialog.txt"
  printf '\n⏺ That was the worker'"'"'s prompt; answered.\n\n╭────────╮\n│ > \n╰────────╯\n  ? for shortcuts\n'
} >"$tmp/scrollback.txt"
esc scan --program alpha --now $((T0 + 100)) --pane "$tmp/scrollback.txt"
expect_out "a dialog quoted above an idle input box reads clear" "self${tab}clear"
{
  cat "$tmp/dialog.txt"
  printf '\n✻ Working… (12s · esc to interrupt)\n'
} >"$tmp/busy.txt"
esc scan --program alpha --now $((T0 + 100)) --pane "$tmp/busy.txt"
expect_out "a dialog above a running turn reads clear" "self${tab}clear"
printf ' Resume which session?\n ❯ 1. alpha-mission-control\n   2. beta-mission-control\n\n Enter to select · ↑/↓ to navigate · Esc to cancel\n' >"$tmp/menu.txt"
esc scan --program alpha --now $((T0 + 100)) --pane "$tmp/menu.txt"
expect_out "a select menu with no permission wording is a dialog" "self${tab}dialog${tab}0${tab}owner"
rm -f "$fleet/mission-control/alpha/escalate/self"
{
  printf '────────────────\n'
  cat "$tmp/menu.txt"
} >"$tmp/menu-rule.txt"
esc scan --program alpha --now $((T0 + 100)) --pane "$tmp/menu-rule.txt"
esc scan --program alpha --now $((T0 + 1000)) --pane "$tmp/menu-rule.txt"
expect_out "a menu held one window goes to the hub" "escalated${tab}hub${tab}alpha"
last=$(hub_events | tail -n 1)
case $last in
  *mc-pane-answer.sh*) fail "a menu the relay offers no option escalates with the relay: '$last'" ;;
  *"offers this dialog no option"*) ok "the hub is told to have a menu with no relayable option answered at its pane" ;;
  *) fail "the menu's escalation: '$last'" ;;
esac
rm -f "$fleet/mission-control/alpha/escalate/self"
{
  cat "$tmp/dialog.txt"
  printf '\n> \n'
} >"$tmp/input.txt"
esc scan --program alpha --now $((T0 + 100)) --pane "$tmp/input.txt"
expect_out "a dialog above a live input line, trailing space and all, reads clear" "self${tab}clear"
cat >"$tmp/automode.txt" <<'EOF'
 Bash command
 │ /plugin/scripts/fleet-streamjson.sh answer mc-alpha-worker-aaaaaaaaaa r1 --allow
 │ Auto mode needs your confirmation for this command.
 │ 4 consecutive actions were blocked. Please review the transcript before continuing.
 │ Latest blocked action: [Auto-Mode Bypass]

 Do you want to proceed?
 ❯ 1. Yes
   2. Yes, and don't ask again for: /plugin/scripts/fleet-streamjson.sh answer *
   3. No

 Esc to cancel · Tab to amend
───────────────────────────────────────── alpha-mission-control ─
EOF
esc scan --program alpha --now $((T0 + 100)) --pane "$tmp/automode.txt"
expect_out "auto mode's confirmation reads as its own kind" "self${tab}auto-mode${tab}0${tab}owner"
: >"$fleet/attention/toasts"
esc scan --program alpha --now $((T0 + 1000)) --pane "$tmp/automode.txt"
expect_out "auto mode's confirmation held one window goes to the hub" "escalated${tab}hub${tab}alpha"
if hub_events | grep -F "mission-control-escalated${tab}alpha${tab}" | grep -q "Remote Control does not show"; then
  ok "the hub hears that auto mode's prompt is hidden from Remote Control"
else
  fail "auto-mode hub event: '$(hub_events)'"
fi
# Another dialog in its place starts a fresh hold.
sed 's/4 consecutive/5 consecutive/; s/answer \*$/steer */' "$tmp/automode.txt" >"$tmp/automode2.txt"
esc scan --program alpha --now $((T0 + 1060)) --pane "$tmp/automode2.txt"
expect_out "a different dialog in its place starts a fresh hold" "self${tab}auto-mode${tab}0${tab}owner"
# Moving the selection cursor is the same dialog.
sed 's/^ ❯ 1\. Yes$/   1. Yes/; s/^   3\. No$/ ❯ 3. No/' "$tmp/automode2.txt" >"$tmp/automode3.txt"
esc scan --program alpha --now $((T0 + 1120)) --pane "$tmp/automode3.txt"
expect_out "a moved cursor keeps the hold" "self${tab}auto-mode${tab}60${tab}owner"
# A different session showing a dialog starts a fresh hold.
rm -f "$fleet/mission-control/alpha/escalate/self"
printf '  500   400 %s claude /planwright:mission-control alpha\n' "$uid" >"$tmp/ps.out"
esc scan --program alpha --now $((T0 + 3000))
printf '  510   400 %s claude /planwright:mission-control alpha\n' "$uid" >"$tmp/ps.out"
esc scan --program alpha --now $((T0 + 4000))
expect_out "a new session's dialog starts a fresh hold" "self${tab}dialog${tab}0${tab}owner${tab}%7"
# A future first sight is not trusted.
IFS="$tab" read -r _ _ f_sess f_print f_kind <"$fleet/mission-control/alpha/escalate/self"
printf 'dialog\t%s\t%s\t%s\t%s\n' $((T0 + 99999)) "$f_sess" "$f_print" "$f_kind" >"$fleet/mission-control/alpha/escalate/self"
esc scan --program alpha --now $((T0 + 4100))
expect_out "a first sight in the future restarts the hold" "self${tab}dialog${tab}0${tab}owner"
rm -f "$fleet/mission-control/alpha/escalate/self"
: >"$tmp/ps.out"

# ---------------------------------------------------------------------------
# A source this pass could not read keeps what it raised.
# ---------------------------------------------------------------------------
rm -rf "$fleet/streamjson/mc-alpha-worker-aaaaaaaaaa" "$fleet/mission-control/alpha/escalate/sent"
: >"$fleet/attention/toasts"
req mc-alpha-worker-aaaaaaaaaa r7-0007 "$T0"
esc scan --program alpha --now $((T0 + 2800))
before=$(count_of "$(hub_events)" "r7-0007")
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$reg/mc-alpha-worker-aaaaaaaaaa"
  esc scan --program alpha --now $((T0 + 2860))
  expect_rc "an unreadable launcher list fails the pass" 1
  expect_err "and says so" "launcher's list cannot be read"
  expect_out "the dialog half still runs" "self${tab}"
  chmod 600 "$reg/mc-alpha-worker-aaaaaaaaaa"
  esc scan --program alpha --now $((T0 + 2920))
  if [ "$(count_of "$(toasts)" "r7-0007")" = 1 ]; then
    ok "after an unread list nothing is raised twice"
  else
    fail "after an unread list: toasts '$(toasts)'"
  fi
  chmod 000 "$fleet/streamjson/mc-alpha-worker-aaaaaaaaaa/journal"
  esc scan --program alpha --now $((T0 + 2980))
  expect_rc "an unreadable journal fails the pass" 1
  chmod 600 "$fleet/streamjson/mc-alpha-worker-aaaaaaaaaa/journal"
  esc scan --program alpha --now $((T0 + 3040))
  if [ "$(count_of "$(toasts)" "r7-0007")" = 1 ] && [ "$(count_of "$(hub_events)" "r7-0007")" = "$before" ]; then
    ok "after an unread journal nothing is raised twice"
  else
    fail "after an unread journal: toasts '$(toasts)'"
  fi
fi
wd="$fleet/streamjson/mc-alpha-worker-aaaaaaaaaa"
mv "$wd" "$wd.real"
ln -s "$tmp/nowhere" "$wd"
esc scan --program alpha --now $((T0 + 3050))
expect_rc "a dangling link for the worker directory fails the pass" 1
expect_err "and is refused" "not a plain directory"
rm -f "$wd"
mv "$wd.real" "$wd"
mv "$wd/journal" "$wd/journal.real"
ln -s "$tmp/nowhere" "$wd/journal"
esc scan --program alpha --now $((T0 + 3060))
expect_rc "a dangling link for the journal fails the pass" 1
rm -f "$wd/journal"
mv "$wd/journal.real" "$wd/journal"
esc scan --program alpha --now $((T0 + 3070))
if [ "$(count_of "$(toasts)" "r7-0007")" = 1 ] && [ "$(count_of "$(hub_events)" "r7-0007")" = "$before" ]; then
  ok "after dangling links nothing is raised twice"
else
  fail "after dangling links: toasts '$(toasts)', hub '$(hub_events)'"
fi

# A dead worker (no pidfile) is the keeper's to settle, never raised.
rm -f "$fleet/streamjson/mc-alpha-worker-aaaaaaaaaa/worker.pid"
esc scan --program alpha --now $((T0 + 3100))
expect_no_out "a dead worker's request is not raised" "r7-0007"
rm -rf "$fleet/streamjson/mc-alpha-worker-aaaaaaaaaa"

# A re-opened request ages from its latest receipt.
req mc-alpha-worker-aaaaaaaaaa r8-0008 "$T0" pending $((T0 + 9000))
esc scan --program alpha --now $((T0 + 9060))
expect_out "a re-opened request ages from its re-opening" "request${tab}mc-alpha-worker-aaaaaaaaaa${tab}r8-0008${tab}60${tab}owner"

# The owner's threshold is honoured, and a malformed one degrades as the
# owner degrades it.
OUT=$(mc_env env PLANWRIGHT_STREAMJSON_PENDING_AGE=60 /bin/bash "$repo_root/scripts/mc-escalate.sh" scan --program alpha --now $((T0 + 9060 + 960)) 2>"$tmp/stderr")
expect_out "the owner's threshold sets the first level" "r8-0008${tab}1020${tab}hub"
OUT=$(mc_env env PLANWRIGHT_STREAMJSON_PENDING_AGE=0 /bin/bash "$repo_root/scripts/mc-escalate.sh" scan --program alpha --now $((T0 + 9120)) 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "a malformed threshold does not stop the pass" 0
expect_err "it is warned and defaulted" "using 900s"
rm -rf "$fleet/streamjson/mc-alpha-worker-aaaaaaaaaa" "$fleet/mission-control/alpha/escalate/sent"

# ---------------------------------------------------------------------------
# The hub: a stale holder is no hub, and a hub that refuses the event hands
# the first level to the operator.
# ---------------------------------------------------------------------------
printf 'format\t1\nsession\tmc-hub-gone-00000000aa\nkind\tregistry\nsince\t1\ngeneration\t1\n' >"$fleet/mission-control/hub/holder"
: >"$fleet/attention/toasts"
req mc-alpha-worker-aaaaaaaaaa r9-0009 "$T0"
esc scan --program alpha --now $((T0 + 1900))
expect_out "a stale hub holder sends the first level to the operator" "escalated${tab}operator${tab}mc-alpha-worker-aaaaaaaaaa"
expect_no_out "and not to the hub" "escalated${tab}hub"
holder hub
rm -f "$fleet/mission-control/alpha/escalate/sent"
: >"$fleet/attention/toasts"
hub_ev="$fleet/attention/mission-control/hub/events"
mkdir -p "$hub_ev"
if [ "$(id -u)" != 0 ]; then
  chmod 555 "$hub_ev"
  esc scan --program alpha --now $((T0 + 1900))
  expect_rc "a refused hub event fails the pass" 1
  expect_err "the refusal is named" "refused the escalation"
  expect_out "the operator hears it at the first level instead" "escalated${tab}operator${tab}mc-alpha-worker-aaaaaaaaaa${tab}editor-toast"
  chmod 755 "$hub_ev"
fi
rm -rf "$fleet/streamjson/mc-alpha-worker-aaaaaaaaaa" "$fleet/mission-control/alpha/escalate/sent"

# A record that cannot be written raises nothing, so nothing is raised twice.
req mc-alpha-worker-aaaaaaaaaa r10-0010 "$T0"
: >"$fleet/attention/toasts"
: >"$fleet/mission-control/alpha/escalate/sent"
if [ "$(id -u)" != 0 ]; then
  chmod 444 "$fleet/mission-control/alpha/escalate/sent"
  esc scan --program alpha --now $((T0 + 2800))
  expect_rc "an unwritable record fails the pass" 1
  expect_err "and says so" "nothing is raised this pass"
  expect_no_out "and raises nothing" "escalated"
  chmod 644 "$fleet/mission-control/alpha/escalate/sent"
fi
rm -f "$fleet/mission-control/alpha/escalate/sent"
# A linked record is refused.
ln -s "$tmp/elsewhere" "$fleet/mission-control/alpha/escalate/sent"
esc scan --program alpha --now $((T0 + 2800))
expect_rc "a linked record is refused" 1
if [ ! -e "$tmp/elsewhere" ]; then ok "and nothing is written through it"; else fail "the link target was written"; fi
rm -f "$fleet/mission-control/alpha/escalate/sent"
# One pass at a time.
ln -s "$$-1-1" "$fleet/mission-control/alpha/escalate/pass.lock"
esc scan --program alpha --now $((T0 + 2800))
expect_rc "a second pass beside a live one" 0
expect_out "says busy" "busy"
expect_no_out "and raises nothing" "escalated"
rm -f "$fleet/mission-control/alpha/escalate/pass.lock"
rm -rf "$fleet/streamjson/mc-alpha-worker-aaaaaaaaaa"

# The operator line names the channel, so channel none is visibly no push.
write_programs "mission_control_escalation_hub: none"
sed -i.bak 's/^notification_channel: editor-toast$/notification_channel: none/' "$tracked"
req mc-alpha-worker-aaaaaaaaaa r11-0011 "$T0"
esc scan --program alpha --now $((T0 + 1900))
expect_out "the operator line names channel none" "escalated${tab}operator${tab}mc-alpha-worker-aaaaaaaaaa${tab}none"
write_programs
rm -rf "$fleet/streamjson/mc-alpha-worker-aaaaaaaaaa"

# ---------------------------------------------------------------------------
# The watcher form: no arguments, the program from the runner's environment.
# ---------------------------------------------------------------------------
: >"$tmp/ps.out"
req mc-alpha-worker-aaaaaaaaaa r12-0012 "$T0"
OUT=$(mc_env env PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-escalate.sh" 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "the watcher form runs a scan" 0
expect_out "the watcher form scans the runner's program" "request${tab}mc-alpha-worker-aaaaaaaaaa${tab}r12-0012"

esc scan --program nosuch
expect_rc "an unconfigured program" 3
esc bogus --program alpha
expect_rc "an unknown verb" 2
esc scan --program alpha --pane "$tmp/no-such-pane"
expect_rc "an unreadable pane file" 2

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mc-escalate tests passed"
