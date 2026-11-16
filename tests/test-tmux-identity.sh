#!/bin/bash
# Tests for scripts/tmux-identity-lib.sh and the sites that pin a recorded
# tmux id to the server that issued it and the name its window was given:
# the death predicate, the registry reconcile's sweep, the launcher's retire
# and the pane listing mission control reads. A restarted tmux server
# numbers its windows from @0 again, so a bare recorded id can name another
# window, mission control's own included.
#
# Every case runs against a real tmux server on a private socket, never the
# operator's: each call, the test's and the scripts', goes through a wrapper
# that pins the socket and unsets TMUX. The scripts run the way a detached
# caller runs them (the runner, a headless worker, a reconcile pass): an
# empty environment, LC_ALL=C and no TMUX, where tmux 3.6 prints a tab in a
# format as `_`.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2015,SC2016 # ok only prints, so a fail arm never follows a passing check; single-quoted $ text is format text the scripts spell, or a child script's own positionals
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)
# shellcheck source=tests/lib/hermetic-env.sh
. "$here/lib/hermetic-env.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }
TAB=$(printf '\t')

# No tmux format in the scripts, hooks or test helpers separates fields with
# a tab. This one needs no tmux.
tab_formats=$(grep -rnE '#\{[a-z_]+\}' "$repo_root/scripts" "$repo_root/hooks" "$repo_root/tests/lib" 2>&1 \
  | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' \
  | grep -E "#\{[a-z_]+\}(${TAB}|\\\\t|\\\$TAB|\\\$\{TAB\}|\\\$tab|\\\$\{tab\})|(${TAB}|\\\\t|\\\$TAB|\\\$\{TAB\}|\\\$tab|\\\$\{tab\})#\{")
[ -z "$tab_formats" ] && ok "no tmux format separates its fields with a tab" \
  || fail "tmux formats with a tab between fields (tmux prints it as _ under LC_ALL=C): $tab_formats"

if ! host_tmux=$(command -v tmux 2>/dev/null); then
  echo "skip: tmux not installed, the fixture-server cases did not run"
  [ "$failures" -eq 0 ] || exit 1
  exit 0
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/tmux-identity.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
# A short parent keeps the socket path under the Unix socket length limit.
iso=$(mktemp -d /tmp/pwtid.XXXXXX) || exit 1
sock="$iso/s"
host_sock=${TMUX:-}
host_sock=${host_sock%%,*}
[ "$sock" != "$host_sock" ] || {
  echo "FAIL: the fixture socket is the host's tmux socket" >&2
  exit 1
}
mkdir -p "$tmp/bin" "$tmp/home"
cat >"$tmp/bin/tmux" <<EOF
#!/bin/sh
exec env -u TMUX -u TMUX_PANE '$host_tmux' -S '$sock' "\$@"
EOF
chmod +x "$tmp/bin/tmux"
T="$tmp/bin/tmux"
trap '"$T" kill-server >/dev/null 2>&1 || :; rm -rf "$tmp" "$iso"' EXIT
unset TMUX TMUX_PANE

fleet_home_pin "$tmp/fleet" || {
  echo "FAIL: could not pin the fleet home" >&2
  exit 1
}

# E <cmd...>: run as a detached caller does: nothing in the environment but
# the fixture's PATH and fleet home, LC_ALL=C, no TMUX.
E() {
  env -i PATH="$tmp/bin:/usr/bin:/bin" HOME="$tmp/home" LC_ALL=C TMPDIR="$tmp" \
    PLANWRIGHT_FLEET_STATE_DIR="$PLANWRIGHT_FLEET_STATE_DIR" CLAUDE_PLUGIN_DATA="$CLAUDE_PLUGIN_DATA" \
    CLAUDE_DIR="$CLAUDE_DIR" "$@"
}
FDE="$repo_root/scripts/fleet-death-evidence.sh"
LIB="$repo_root/scripts/tmux-identity-lib.sh"
verdict() { E /bin/sh "$FDE" "$@" 2>/dev/null; }
alive() { "$T" list-windows -a -F '#{window_id}' | grep -qx -- "$1"; }

"$T" -f /dev/null new-session -d -s hub -n hub-window -x 80 -y 20 'sleep 600' \
  || {
    echo "FAIL: could not start the fixture tmux server" >&2
    exit 1
  }
[ "$("$T" display-message -p '#{socket_path}')" = "$sock" ] || {
  echo "FAIL: the fixture tmux did not resolve to its own socket" >&2
  exit 1
}
hub=$("$T" display-message -p -t hub:hub-window '#{window_id}')
work=$("$T" new-window -d -P -F '#{window_id}' -t hub: -n work-1 'sleep 600')
srv=$("$T" display-message -p '#{pid}.#{start_time}')
old_srv="${srv%%.*}.$((${srv#*.} - 1000))"
case $srv in *.*) ;; *) fail "fixture: no server identity: $srv" ;; esac

lc_tab=$(E tmux list-windows -t hub -F "#{window_id}${TAB}#{window_name}" | head -n 1)
case $lc_tab in
  *"$TAB"*) echo "note: this tmux keeps a tab in a format under LC_ALL=C" ;;
  *) echo "note: this tmux prints an id and name joined by a tab as '$lc_tab' under LC_ALL=C" ;;
esac

# --- The death predicate, unpinned: the id and name listing parses under
# LC_ALL=C, so a live window reads alive by id and by name.
[ "$(verdict tmux-window hub "$hub")" = alive ] && ok "a live window reads alive by its id" \
  || fail "the live hub window $hub did not read alive: $(verdict tmux-window hub "$hub")"
[ "$(verdict tmux-window hub work-1)" = alive ] && ok "a live window reads alive by its name" \
  || fail "work-1 did not read alive by name"
[ "$(verdict tmux-window renamed-away "$work")" = alive ] && ok "an id is still looked up across the server (a renamed session)" \
  || fail "the cross-session id lookup broke"
[ "$(verdict tmux-window --in-session gone-session "$hub")" = dead ] \
  && ok "--in-session: an unpinned id in another session reads dead" || fail "--in-session read $hub in another session as live"
[ "$(verdict tmux-window --in-session hub "$hub")" = alive ] && ok "--in-session: the id in its own session reads alive" \
  || fail "--in-session missed the id in its own session"

# --- Pinned: alive only while the server, the id and the name all hold.
[ "$(verdict tmux-window hub "$work" "$srv" work-1)" = alive ] && ok "a pinned window whose server, id and name hold reads alive" \
  || fail "the pinned live window did not read alive"
[ "$(verdict tmux-window hub "$hub" "$old_srv" work-old)" = dead ] \
  && ok "a pinned id an earlier server issued reads dead, though the id is live now" \
  || fail "a pin from an earlier server read live"
[ "$(verdict tmux-window hub "$hub" "$srv" work-1)" = dead ] && ok "a pinned id now carrying another name reads dead" \
  || fail "a renamed pinned window read live"
[ "$(verdict tmux-window hub @99 "$srv" work-1)" = dead ] && ok "a pinned id the server never issued reads dead" \
  || fail "an absent pinned id read live"
rc=0
E /bin/sh "$FDE" tmux-window hub "$work" "$srv" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] && ok "a pin missing its name is refused" || fail "a three-token tmux-window handle exited $rc"
rc=0
E /bin/sh "$FDE" tmux-window hub "$work" not-a-server work-1 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] && ok "a malformed server pin is refused" || fail "a malformed pin exited $rc"

# --- tmux_pin_close: a mismatch is never a target.
pin_close() { E /bin/sh -c '. "$1"; shift; tmux_pin_close "$@"; rc=$?; printf "%s\n" "$TP_WHY"; exit $rc' sh "$LIB" "$@"; }
rc=0
why=$(pin_close window "$hub" "$old_srv" hub-window) || rc=$?
[ "$rc" = 1 ] && alive "$hub" && ok "closing an id pinned to an earlier server kills nothing: $why" \
  || fail "the earlier-server close: rc $rc, hub alive: $(alive "$hub" && echo yes || echo no)"
rc=0
why=$(pin_close window "$hub" "$srv" work-1) || rc=$?
[ "$rc" = 1 ] && alive "$hub" && ok "closing an id whose window has another name kills nothing" \
  || fail "the renamed close: rc $rc"
rc=0
why=$(pin_close window "$hub" - -) || rc=$?
[ "$rc" = 1 ] && alive "$hub" && ok "an id recorded without its server is never closed by id" || fail "the unpinned close: rc $rc"
closeme=$("$T" new-window -d -P -F '#{window_id}' -t hub: -n close-me 'sleep 600')
rc=0
pin_close window "$closeme" "$srv" close-me >/dev/null || rc=$?
[ "$rc" = 0 ] && ! alive "$closeme" && alive "$hub" && ok "a window whose pin holds is closed, and nothing else" \
  || fail "the matching close: rc $rc"
rc=0
pin_close window "$closeme" "$srv" close-me >/dev/null || rc=$?
[ "$rc" = 3 ] && ok "a window already gone is reported gone" || fail "closing a gone window: rc $rc"
pwin=$("$T" new-window -d -P -F '#{window_id}' -t hub: -n pane-host 'sleep 600')
pane=$("$T" display-message -p -t "$pwin" '#{pane_id}')
rc=0
pin_close pane "$pane" "$old_srv" pane-host >/dev/null || rc=$?
[ "$rc" = 1 ] && "$T" display-message -p -t "$pane" '#{pane_id}' | grep -qx -- "$pane" \
  && ok "a pane pinned to an earlier server is left" || fail "the earlier-server pane close: rc $rc"
rc=0
pin_close pane "$pane" "$srv" pane-host >/dev/null || rc=$?
[ "$rc" = 0 ] && ! alive "$pwin" && ok "a pane whose pin holds is closed" || fail "the matching pane close: rc $rc"

# --- The pane listing mission control reads parses under LC_ALL=C.
pane_pid=$("$T" display-message -p -t "$work" '#{pane_pid}')
work_pane=$("$T" display-message -p -t "$work" '#{pane_id}')
got=$(E /bin/bash -c '
  prog=t script_dir=$1
  . "$1/echo-safety.sh"; . "$1/mc-lib.sh"; . "$1/fleet-pane-vocabulary.sh"; . "$1/mc-session-pane.sh"
  panes=$(tmux list-panes -a -F "#{pane_id} #{pane_pid}")
  msp_pane_of "$2" "$2 1" "$panes"' sh "$repo_root/scripts" "$pane_pid" 2>&1)
[ "$got" = "$work_pane" ] && ok "the pane listing finds a session's pane by its pid" \
  || fail "msp_pane_of read '$got', not $work_pane"

# --- Every fixed format, as its script spells it, read from the fixture
# server under LC_ALL=C: the id, the server and the name come back whole,
# a window name with a space included.
fidelity() { # <label> <script> <format as the script spells it> <output> <expected>
  if ! grep -qF -- "$3" "$repo_root/scripts/$2"; then
    fail "$1: scripts/$2 no longer uses the format this case checks: $3"
  elif [ "$4" = "$5" ]; then
    ok "$1 reads under LC_ALL=C as '$5'"
  else
    fail "$1: '$4', not '$5'"
  fi
}
spaced=$("$T" new-window -d -P -F '#{window_id}' -t hub: -n 'my work' 'sleep 600')
spaced_pid=$("$T" display-message -p -t "$spaced" '#{pane_pid}')
fidelity "the panel's window listing" mc-panel.sh "'#{window_id} #{pid}.#{start_time} #{session_name}:#{window_name}'" \
  "$(E tmux list-windows -a -F '#{window_id} #{pid}.#{start_time} #{session_name}:#{window_name}' | grep "^$spaced ")" \
  "$spaced $srv hub:my work"
fidelity "the stall probe" mc-stall.sh '"#{pane_pid} $TMUX_SERVER_FORMAT/#{window_id}/#{window_name}"' \
  "$(E tmux display-message -p -t "$spaced" '#{pane_pid} #{pid}.#{start_time}/#{window_id}/#{window_name}')" \
  "$spaced_pid $srv/$spaced/my work"
fidelity "the cleanup's self lookup" fleet-cleanup.sh '"#{window_id} #{window_index} #{session_name}:#{window_name}"' \
  "$(E tmux display-message -p -t "$spaced" '#{window_id} #{window_index} #{session_name}:#{window_name}')" \
  "$spaced $("$T" display-message -p -t "$spaced" '#{window_index}') hub:my work"
fidelity "the launcher's by-name listing" mission-control-launch.sh '"$TMUX_SERVER_FORMAT #{window_id} #{window_name}"' \
  "$(E tmux list-windows -a -F '#{pid}.#{start_time} #{window_id} #{window_name}' | grep " $spaced ")" \
  "$srv $spaced my work"
fidelity "the death predicate's listing" fleet-death-evidence.sh "'#{window_id} #{window_name}'" \
  "$(E tmux list-windows -a -F '#{window_id} #{window_name}' | grep "^$spaced ")" "$spaced my work"
fidelity "the pane listing (mc-pane-answer)" mc-pane-answer.sh "'#{pane_id} #{pane_pid}'" \
  "$(E tmux list-panes -a -F '#{pane_id} #{pane_pid}' | grep " $spaced_pid\$")" \
  "$("$T" display-message -p -t "$spaced" '#{pane_id}') $spaced_pid"
fidelity "the pane listing (mc-escalate)" mc-escalate.sh "'#{pane_id} #{pane_pid}'" \
  "$(E tmux list-panes -a -F '#{pane_id} #{pane_pid}' | grep " $spaced_pid\$")" \
  "$("$T" display-message -p -t "$spaced" '#{pane_id}') $spaced_pid"
od_out=$(E tmux new-window -d -P -F '#{window_id} #{pid}.#{start_time} #{window_name}' -t hub: -n od-win 'sleep 600')
fidelity "the offload rung's creation line" offload-dispatch.sh '"#{window_id} $TMUX_SERVER_FORMAT #{window_name}"' \
  "${od_out#@* }" "$srv od-win"
fdw_out=$(E tmux new-session -d -s fdw-sess -P -F '#{window_id} #{pid}.#{start_time} #{session_name}:#{window_name}' -n fdw-sess 'sleep 600')
fidelity "the worktree seam's creation line" fleet-dispatch-worktree.sh '"#{window_id} $TMUX_SERVER_FORMAT #{session_name}:#{window_name}"' \
  "${fdw_out#@* }" "$srv fdw-sess:fdw-sess"
[ "$(E tmux show-window-options -t fdw-sess: automatic-rename)" = "automatic-rename off" ] \
  && ok "a window named at creation keeps its name: automatic-rename is off" || fail "automatic-rename stays on for a named window"

# --- The launcher's retire, against registry rows written as a launch
# writes them.
FH=$(E /bin/sh "$repo_root/scripts/fleet-state.sh" root) || fail "fixture: no fleet home"
reg="$FH/mission-control/sessions"
mkdir -p "$reg"
launch_row() { # <name> <handle> <server or -> (omitted: a row written before the pin)
  {
    printf 'format\t1\nname\t%s\nstate\tlaunched\ntoken\tt-%s\npid\t1\nprogram\talpha\n' "$1" "$1"
    printf 'owner\tmission-control:alpha\nkind\tworker\nscope\ts\nbackend\ttmux\nhandle\t%s\n' "$2"
    [ "$#" -lt 3 ] || printf 'server\t%s\n' "$3"
    printf 'profile\tworker\ntier\t-\nreserved\t-\nbrief\t-\ncwd\t-\ntask\t-\nprimary\t-\nmarker\t-\nlaunched\t0\n'
  } >"$reg/$1"
}
ml() {
  RC=0
  OUT=$(E /bin/sh "$repo_root/scripts/mission-control-launch.sh" "$@" 2>"$tmp/ml.err") || RC=$?
  ERR=$(cat "$tmp/ml.err")
}
launch_row mc-alpha-worker-stale "$hub" "$old_srv"
ml retire mc-alpha-worker-stale
[ "$RC" = 0 ] && alive "$hub" && [ ! -e "$reg/mc-alpha-worker-stale" ] \
  && ok "retiring a row whose id an earlier server issued kills nothing (the reused id survives) and releases the row" \
  || fail "the stale retire: rc $RC, $OUT, $ERR"
case $ERR in *"not closing $hub"*) ok "and says so in one plain line" ;; *) fail "the stale retire said nothing: $ERR" ;; esac
launch_row mc-alpha-worker-legacy "$hub"
ml retire mc-alpha-worker-legacy
[ "$RC" = 0 ] && alive "$hub" && [ ! -e "$reg/mc-alpha-worker-legacy" ] && ok "a row recorded without its server is never killed by its id, and its row is released" \
  || fail "the legacy retire: rc $RC, $OUT, $ERR"
case $ERR in *"not closing $hub by id"*) ok "and says it closes only windows carrying the session's name" ;; *) fail "the legacy retire said nothing: $ERR" ;; esac
mine=$("$T" new-window -d -P -F '#{window_id}' -t hub: -n mc-alpha-worker-live 'sleep 600')
launch_row mc-alpha-worker-live "$mine" "$srv"
ml retire mc-alpha-worker-live
[ "$RC" = 0 ] && ! alive "$mine" && alive "$hub" && ok "a row whose server, id and name hold is still closed by retire" \
  || fail "the live retire: rc $RC, $OUT, $ERR"
byname=$("$T" new-window -d -P -F '#{window_id}' -t hub: -n mc-alpha-worker-byname 'sleep 600')
launch_row mc-alpha-worker-byname "$hub"
ml retire mc-alpha-worker-byname
[ "$RC" = 0 ] && ! alive "$byname" && alive "$hub" \
  && ok "a row recorded without its server closes the window carrying its name, never the recorded id" \
  || fail "the by-name retire: rc $RC, $OUT, $ERR"

# --- The sweep: the registry reconcile drops markers whose pin names an
# earlier server, or whose unpinned id is not in its recorded session, and
# keeps a marker whose pin holds. It kills nothing.
register() { E /bin/sh "$repo_root/scripts/fleet-register.sh" --handle "$1" --backend tmux --death-handle "$2" >/dev/null 2>&1; }
keep=$("$T" new-window -d -P -F '#{window_id}' -t hub: -n keep-me 'sleep 600')
register stale-pinned "tmux-window hub $hub $old_srv hub-window" || fail "fixture: stale-pinned not registered"
register live-pinned "tmux-window hub $keep $srv keep-me" || fail "fixture: live-pinned not registered"
register legacy-reused "tmux-window gone-session $hub" || fail "fixture: legacy-reused not registered"
register legacy-old "tmux-window hub $hub" || fail "fixture: legacy-old not registered"
register legacy-live "tmux-window hub $keep" || fail "fixture: legacy-live not registered"
# legacy-old was registered before the server started: its registry row
# carries an epoch from then.
awk -F '\t' -v OFS='\t' '$2 == "legacy-old" { $1 = 1000 } { print }' "$FH/registry" >"$tmp/registry" \
  && cat "$tmp/registry" >"$FH/registry"
sweep=$(E /bin/sh "$repo_root/scripts/fleet-registry-reconcile.sh" 2>&1)
md="$FH/dispatch-markers"
printf '%s\n' "$sweep" | grep -qx "retire${TAB}stale-pinned${TAB}tmux-server-changed" && [ ! -e "$md/stale-pinned" ] \
  && ok "the sweep drops a marker pinned to an earlier server, and logs it" || fail "stale-pinned: $sweep"
printf '%s\n' "$sweep" | grep -qx "retire${TAB}legacy-reused${TAB}tmux-window-dead" && [ ! -e "$md/legacy-reused" ] \
  && ok "the sweep drops an unpinned marker whose id is live only in another session" || fail "legacy-reused: $sweep"
printf '%s\n' "$sweep" | grep -qx "retire${TAB}legacy-old${TAB}tmux-server-changed" && [ ! -e "$md/legacy-old" ] \
  && ok "the sweep drops an unpinned marker registered before the server started" || fail "legacy-old: $sweep"
[ -e "$md/live-pinned" ] && ! printf '%s\n' "$sweep" | grep -q "live-pinned" \
  && ok "the sweep keeps a marker whose pin holds" || fail "live-pinned: $sweep"
[ -e "$md/legacy-live" ] && ! printf '%s\n' "$sweep" | grep -q "legacy-live" \
  && ok "the sweep keeps an unpinned marker live in its own session, registered since the server started" \
  || fail "legacy-live: $sweep"
alive "$hub" && alive "$keep" && ok "the sweep killed no window" || fail "a window died in the sweep"
grep -q 'tmux-server-changed' "$FH/audit/"* 2>/dev/null && ok "each drop is in the audit trail" \
  || fail "no audit record of the drops under $FH/audit"

[ "$failures" -eq 0 ] || exit 1
echo "all tmux identity checks passed"
