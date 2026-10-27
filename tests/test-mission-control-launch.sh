#!/bin/bash
# Tests for scripts/mission-control-launch.sh — the one launcher for every
# session kind and its retire verb (mission-control REQ-D1.1, REQ-D1.5,
# REQ-B1.4, REQ-G1.1, REQ-M1.7, REQ-A1.4).
#
# Every kind launches from a fixture on the stream-json rung (a CLI shim
# records its argv and its first stdin line), one on the tmux rung (a tmux
# stub keeps a window table), and each launch's brief, rules, profile, tier
# and name are read back from what the launched session received.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).

# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)
LAUNCH="$repo_root/scripts/mission-control-launch.sh"

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }
TAB=$(printf '\t')

for t in jq git; do
  command -v "$t" >/dev/null 2>&1 || {
    echo "FAIL: $t is required to run this suite" >&2
    exit 1
  }
done

tmp=$(mktemp -d) || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
fleet="$tmp/fleet"
cleanup() {
  # Close any supervisor a failed case left running, through the rung's own
  # stop, before the scratch tree goes.
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
reset_mc_fixture
cp "$repo_root/config/defaults.yml" "$core/config/defaults.yml"
for p in worker tower mission-control; do
  cp "$repo_root/config/$p-settings.json" "$core/config/"
done
mkdir -p "$repo/specs" "$fleet"
home="$tmp/mc-home/alpha"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo/specs
program_alpha_home: $home
EOF
mc_run mc-rules.sh add alpha --text "Never hand the operator a pane" --subject panes --source "operator, fixture" --date 2026-10-26
[ "$RC" = 0 ] || fail "fixture: the program rule was not added: $ERR"
mc_run mc-rules.sh add alpha --text "Docs need review" --subject docs --source "operator, fixture" --date 2026-10-26 --scope repo:repo
[ "$RC" = 0 ] || fail "fixture: the repository rule was not added: $ERR"

# The stream-json CLI shim: records argv and the first stdin line, then exits.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
printf '%s\n' "$*" >"$SHIM_RECORD_DIR/argv.tmp" && mv "$SHIM_RECORD_DIR/argv.tmp" "$SHIM_RECORD_DIR/argv"
IFS= read -r line || line=''
printf '%s\n' "$line" >"$SHIM_RECORD_DIR/stdin"
exit 0
SHIM
# The tmux stub: a window table under $TMUX_STUB (one file per window id,
# holding its name), argv recorded per call. TMUX_LIST_FAIL makes listing
# fail, as an unreachable server does.
cat >"$tmp/bin/tmux" <<'STUB'
#!/bin/sh
all="$*"
printf '%s\n' "$all" >>"$TMUX_STUB/calls"
case $1 in
  new-window)
    n=$(($(cat "$TMUX_STUB/next" 2>/dev/null || echo 1)))
    echo $((n + 1)) >"$TMUX_STUB/next"
    shift
    printf '%s\n' "$@" >"$TMUX_STUB/argv-@$n"
    wname=''
    while [ "$#" -gt 0 ]; do
      [ "$1" = -n ] && wname=$2
      shift
    done
    printf '%s\n' "$wname" >"$TMUX_STUB/@$n"
    # TMUX_LOCK_DIR: the directory a launch writes its row into turns
    # read-only once the window exists.
    [ -z "${TMUX_LOCK_DIR:-}" ] || chmod 500 "$TMUX_LOCK_DIR"
    echo "@$n"
    ;;
  list-windows)
    [ "${TMUX_LIST_FAIL:-0}" = 1 ] && exit 1
    if [ "${TMUX_NO_SERVER:-0}" = 1 ]; then
      echo "no server running on /tmp/tmux-stub/default" >&2
      exit 1
    fi
    case $all in
      *'#{window_id} #{window_name}'*) ;;
      *)
        for w in "$TMUX_STUB"/@*; do
          [ -f "$w" ] && printf '%s\n' "${w##*/}"
        done
        exit 0
        ;;
    esac
    for w in "$TMUX_STUB"/@*; do
      [ -f "$w" ] || continue
      printf '%s %s\n' "${w##*/}" "$(cat "$w")"
    done
    ;;
  display-message)
    t=''
    while [ "$#" -gt 0 ]; do
      [ "$1" = -t ] && t=$2
      shift
    done
    [ -e "$TMUX_STUB/$t" ] || exit 1
    case $all in *session_name*) echo stub ;; *) echo "$t" ;; esac
    ;;
  kill-window)
    [ "${TMUX_KILL_FAIL:-0}" = 1 ] && exit 1
    rm -f "$TMUX_STUB/$3"
    ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/claude" "$tmp/bin/tmux"
mkdir -p "$tmp/tmux"

# ml <args...> — run the launcher against the fixture. Sets RC, OUT, ERR.
ml() {
  OUT=$(cd "$repo" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_SKILLS_ROOT \
    -u PLANWRIGHT_CONFIG_DEFAULTS -u PLANWRIGHT_REPO_ROOT_CHECKED -u PLANWRIGHT_CONFIG_STRICT_OVERLAYS \
    -u XDG_CONFIG_HOME -u TMUX -u TMUX_PANE -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    -u PLANWRIGHT_TOWER_ID -u PLANWRIGHT_TOWER_SESSION_ID -u PLANWRIGHT_TOWER_PID \
    PATH="$tmp/bin:$PATH" PLANWRIGHT_ROOT="$core" PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" PLANWRIGHT_LOCAL_CONFIG="$tmp/absent.yml" \
    CLAUDE_DIR="$tmp/claude" HOME="$fixhome" PLANWRIGHT_FLEET_STATE_DIR="$fleet" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT=off \
    TMUX_PANE="${ML_TMUX_PANE:-}" \
    SHIM_RECORD_DIR="${SHIM_RECORD_DIR:-$tmp}" TMUX_STUB="$tmp/tmux" TMUX_KILL_FAIL="${TMUX_KILL_FAIL:-0}" \
    TMUX_LIST_FAIL="${TMUX_LIST_FAIL:-0}" TMUX_LOCK_DIR="${TMUX_LOCK_DIR:-}" TMUX_NO_SERVER="${TMUX_NO_SERVER:-0}" \
    /bin/sh "$LAUNCH" "$@" 2>"$tmp/stderr")
  RC=$?
  ERR=$(cat "$tmp/stderr")
}
field() { printf '%s\n' "$OUT" | awk -F '\t' -v k="$1" '$1 == "launch" && $2 == k { print $3 }'; }
# wait_for <file> — until the detached session has written it (bounded).
wait_for() {
  n=0
  while [ ! -s "$1" ] && [ "$n" -lt 100 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  [ -s "$1" ]
}
# wait_done <name> — until the stream-json supervisor recorded the run's end.
wait_done() {
  n=0
  while [ ! -s "$fleet/streamjson/$1/result" ] && [ "$n" -lt 100 ]; do
    sleep 0.1
    n=$((n + 1))
  done
}

printf '%s\n' "# Fixture brief" "" "Review the open pull requests." >"$tmp/brief.md"

# ---------------------------------------------------------------------------
# REQ-D1.1, REQ-G1.1, REQ-M1.7, REQ-B1.4: every kind launches with its brief,
# rules, profile, tier and name, and registers a row with owner and kind.
# ---------------------------------------------------------------------------
# A distinct tier at each selection key, so each kind's argv shows which key
# it resolved at.
cat >>"$tracked" <<'EOF'
allocation_model_orchestrate_dispatch: haiku
allocation_effort_orchestrate_dispatch: low
allocation_model_execute_step: sonnet
allocation_effort_execute_step: high
allocation_model_offload: opus
allocation_effort_offload: low
EOF
for kind in tower orchestrator worker reviewer ad-hoc mission-control; do
  case $kind in
    tower | orchestrator) prof=tower ;;
    mission-control) prof=mission-control ;;
    *) prof=worker ;;
  esac
  case $kind in
    tower | mission-control) want_tier='--model haiku --effort low' ;;
    orchestrator) want_tier='--model sonnet --effort medium' ;;
    worker) want_tier='--model opus --effort high' ;;
    reviewer) want_tier='--model sonnet --effort high' ;;
    ad-hoc) want_tier='--model opus --effort low' ;;
  esac
  rec="$tmp/rec-$kind"
  mkdir -p "$rec"
  SHIM_RECORD_DIR=$rec ml launch --program alpha --kind "$kind" --scope "spec:alpha-$kind" --brief "$tmp/brief.md"
  if [ "$RC" != 0 ]; then
    fail "[$kind] the launch exited $RC: $ERR"
    continue
  fi
  name=$(field name)
  if ! wait_for "$rec/stdin"; then
    fail "[$kind] the launched session never received its first message"
    continue
  fi
  argv=$(cat "$rec/argv")
  case " $argv " in
    *" --settings $core/config/$prof-settings.json "*) ok "[$kind] the session runs under the $prof profile" ;;
    *) fail "[$kind] the session's argv lacks --settings $prof-settings.json: $argv" ;;
  esac
  case " $argv " in
    *" --name $name "*) ok "[$kind] the session is named $name" ;;
    *) fail "[$kind] the session's argv does not carry its name: $argv" ;;
  esac
  if grep -qF 'Review the open pull requests.' "$rec/stdin" && grep -qF 'Never hand the operator a pane' "$rec/stdin"; then
    ok "[$kind] the first message carries the brief and the program rules"
  else
    fail "[$kind] the first message lacks the brief or the rules: $(cut -c1-300 "$rec/stdin")"
  fi
  grep -qF 'Docs need review' "$rec/stdin" && fail "[$kind] a repository-scoped rule reached a launch that did not ask for it"
  row="$fleet/mission-control/sessions/$name"
  if [ -f "$row" ] && grep -qx "owner${TAB}mission-control:alpha" "$row" && grep -qx "kind$TAB$kind" "$row" \
    && grep -qx "scope${TAB}spec:alpha-$kind" "$row"; then
    ok "[$kind] the registry row names owner, kind and scope"
  else
    fail "[$kind] the registry row is missing or incomplete: $(cat "$row" 2>/dev/null)"
  fi
  case " $argv " in
    *" $want_tier "*) ok "[$kind] the session runs at its key's tier ($want_tier)" ;;
    *) fail "[$kind] the session's argv lacks its key's tier '$want_tier': $argv" ;;
  esac
  first=$(head -n 1 "$fleet/mission-control/launch/$name/brief.md")
  [ "$first" = '# Fixture brief' ] && ok "[$kind] the composed brief opens with the brief itself" \
    || fail "[$kind] the composed brief opens with '$first'"
  wait_done "$name"
done
ml list
[ "$(printf '%s\n' "$OUT" | grep -c .)" = 6 ] && ok "list shows the six launched sessions" \
  || fail "list does not show six sessions: $OUT"

# --rules adds an in-scope rule to the brief.
rec="$tmp/rec-rules"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind reviewer --scope rules-case --brief "$tmp/brief.md" --rules repo:repo
[ "$RC" = 0 ] || fail "the --rules launch exited $RC: $ERR"
wait_for "$rec/stdin" && grep -qF 'Docs need review' "$rec/stdin" \
  && ok "a --rules scope adds its rules to the brief" || fail "the --rules scope's rule did not reach the session"
wait_done "$(field name)"

# No item handed back names a pane, window or attach hint.
ml launch --program alpha --kind ad-hoc --scope pane-check --brief "$tmp/brief.md" --backend tmux
case $OUT in
  *attach* | *observe* | *capture-pane* | *'@'[0-9]*) fail "the launch report names a pane or window: $OUT" ;;
  *) ok "the launch report names no pane, window or attach hint" ;;
esac
pane_name=$(field name)

# ---------------------------------------------------------------------------
# REQ-M1.7: the same inputs yield the same name; a held name refuses.
# ---------------------------------------------------------------------------
ml name --program alpha --kind worker --scope spec:alpha-worker
n1=$OUT
ml name --program alpha --kind worker --scope spec:alpha-worker
[ "$n1" = "$OUT" ] && [ -n "$n1" ] && ok "the same inputs yield the same name ($n1)" || fail "the name is not deterministic: '$n1' then '$OUT'"
[ -f "$fleet/mission-control/sessions/$n1" ] && ok "the launch registered the name the name verb derives" \
  || fail "the name verb's $n1 is not the launched worker's"
ml name --program alpha --kind worker --scope spec:alpha-other
[ "$OUT" != "$n1" ] && ok "another scope yields another name" || fail "two scopes share the name $n1"
ml name --program alpha --kind reviewer --scope spec:alpha-worker
[ "$OUT" != "$n1" ] && ok "another kind yields another name" || fail "two kinds share the name $n1"
ml launch --program alpha --kind worker --scope spec:alpha-worker --brief "$tmp/brief.md"
[ "$RC" = 3 ] && ok "a second launch of a held name is refused (exit 3)" || fail "a held name launched again (exit $RC)"

# ---------------------------------------------------------------------------
# Refusals: no profile, no tier, no program, a bad input.
# ---------------------------------------------------------------------------
mv "$core/config/tower-settings.json" "$tmp/tower-settings.json"
ml launch --program alpha --kind orchestrator --scope no-profile --brief "$tmp/brief.md"
[ "$RC" = 4 ] && ok "a launch without its profile is refused (exit 4)" || fail "a profile-less launch exited $RC"
case $ERR in *profile*) ok "the refusal names the profile" ;; *) fail "the profile refusal does not say why: $ERR" ;; esac
ml name --program alpha --kind orchestrator --scope no-profile
[ ! -e "$fleet/mission-control/sessions/$OUT" ] && ok "the refused launch left no registry row" || fail "the refused launch left a row"
mv "$tmp/tower-settings.json" "$core/config/tower-settings.json"

cp "$tracked" "$tmp/tracked.bak"
printf 'allocation_model_execution: nonsense\n' >>"$tracked"
ml launch --program alpha --kind worker --scope no-tier --brief "$tmp/brief.md"
[ "$RC" = 4 ] && ok "a launch with no resolvable tier is refused (exit 4)" || fail "a tier-less launch exited $RC: $ERR"
case $ERR in *tier*) ok "the refusal names the tier" ;; *) fail "the tier refusal does not say why: $ERR" ;; esac
ml name --program alpha --kind worker --scope no-tier
if [ ! -e "$fleet/mission-control/sessions/$OUT" ] && [ ! -e "$fleet/mission-control/launch/$OUT" ]; then
  ok "the tier refusal left no registry row and no launch directory"
else
  fail "the tier refusal left state behind"
fi
ml launch --program alpha --kind worker --scope no-tier-tmux --brief "$tmp/brief.md" --backend tmux
[ "$RC" = 4 ] && ok "the tmux rung refuses a launch with no resolvable tier too (exit 4)" || fail "the tmux rung's tier-less launch exited $RC: $ERR"
cp "$tmp/tracked.bak" "$tracked"

# The allocation seam's own refusals keep their reasons.
mkdir -p "$tmp/s3"
cp -R "$repo_root/scripts" "$tmp/s3/scripts"
for code in 3 5; do
  printf '#!/bin/sh\nexit %s\n' "$code" >"$tmp/s3/scripts/allocation-apply.sh"
  LAUNCH="$tmp/s3/scripts/mission-control-launch.sh" ml launch --program alpha --kind worker --scope "seam-$code" --brief "$tmp/brief.md"
  case $code in
    3) want='admission gate' ;;
    5) want='broken install' ;;
  esac
  case $ERR in
    *"$want"*) [ "$RC" = 4 ] && ok "allocation exit $code is refused naming the $want (exit 4)" || fail "allocation exit $code exited $RC" ;;
    *) fail "allocation exit $code: the refusal does not name the $want: $ERR" ;;
  esac
done

ml launch --program beta --kind worker --scope x --brief "$tmp/brief.md"
[ "$RC" = 4 ] && ok "a program that is not configured is refused (exit 4)" || fail "an unconfigured program exited $RC"
for bad in '--kind janitor' '--scope a/b' '--scope -x' '--program Alpha' '--backend print' '--rules program'; do
  set -- --program alpha --kind worker --scope bad-input --brief "$tmp/brief.md"
  # shellcheck disable=SC2086 # the option and its value, split on purpose
  ml launch "$@" $bad
  [ "$RC" = 2 ] && ok "refused: $bad (exit 2)" || fail "accepted or misclassified: $bad (exit $RC)"
done
ml launch --program alpha --kind worker --scope empty-brief --brief "$tmp/absent.md"
[ "$RC" = 2 ] && ok "a missing brief is refused (exit 2)" || fail "a missing brief exited $RC"

# ---------------------------------------------------------------------------
# REQ-D1.5: retire leaves no row and no pane; a partial release says so.
# ---------------------------------------------------------------------------
worker_name=$n1
env PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-attention.sh" heartbeat "$worker_name" spec:alpha-worker working \
  || fail "fixture: the attention row was not seeded"
env PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-attention.sh" render 2>/dev/null | grep -q "$worker_name" \
  || fail "fixture: the seeded attention row does not render"
ml retire "$worker_name"
if [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^retire	$worker_name	released	"; then
  ok "retire releases a finished stream-json session"
else
  fail "retire of a finished session: exit $RC, $OUT $ERR"
fi
[ ! -e "$fleet/mission-control/sessions/$worker_name" ] && [ ! -e "$fleet/mission-control/launch/$worker_name" ] \
  && ok "the retired session has no registry row and no launch directory" || fail "retire left the row or the launch directory"
[ ! -e "$fleet/dispatch-markers/$worker_name" ] && ok "the fleet registry marker is retired" || fail "the fleet registry marker remains"
last=$(env PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-state.sh" registry 2>/dev/null \
  | awk -F '\t' -v w="$worker_name" '$2 == w { l = $0 } END { print l }')
case $last in *"	closed") ok "the fleet registry record is closed" ;; *) fail "the fleet registry record is not closed: $last" ;; esac
ml list
case $OUT in *"$worker_name"*) fail "list still shows the retired session" ;; *) ok "list no longer shows the retired session" ;; esac
if env PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-attention.sh" render 2>/dev/null | grep -q "$worker_name"; then
  fail "the retired session's attention row survived"
else
  ok "the retired session has no attention row"
fi
ml retire "$worker_name"
[ "$RC" = 3 ] && ok "retiring a name with no row exits 3" || fail "a second retire exited $RC"

win=$(awk -F '\t' '$1 == "handle" { print $2 }' "$fleet/mission-control/sessions/$pane_name")
[ -e "$tmp/tmux/$win" ] && ok "the tmux session has a live window ($win) before retire" || fail "the tmux launch left no window"
argv_t=$(cat "$tmp/tmux/argv-$win" 2>/dev/null)
case $argv_t in
  *fleet-dispatch-env.sh*--root*--inbound*--identity*"$pane_name"*--settings*"$repo_root/config/worker-settings.json"*--name*"$pane_name"*) ok "the tmux window runs the session under its profile and name" ;;
  *) fail "the tmux window's argv lacks the profile or name: $argv_t" ;;
esac
if printf '%s\n' "$argv_t" | grep -A2 -x -- '--identity' | tr '\n' ' ' | grep -q "$pane_name pane-check"; then
  ok "the tmux session's worker identity carries its scope"
else
  fail "the tmux session's identity lacks its scope: $argv_t"
fi
grep -qF 'Never hand the operator a pane' "$fleet/mission-control/launch/$pane_name/brief.md" \
  && ok "the tmux session's brief carries the rules" || fail "the tmux session's brief lacks the rules"
TMUX_KILL_FAIL=1 ml retire "$pane_name"
if [ "$RC" = 1 ] && printf '%s\n' "$OUT" | grep -q "^retire	$pane_name	partial	released=-	held=pane,registry,attention,row$"; then
  ok "a window that will not close is reported partial, holding its fleet record and attention row (exit 1)"
else
  fail "a failed pane close was not reported partial: exit $RC, $OUT"
fi
[ -f "$fleet/mission-control/sessions/$pane_name" ] && ok "a partial release keeps the row for a retry" || fail "a partial release dropped the row"
: >"$tmp/tmux/calls"
TMUX_LIST_FAIL=1 ml retire "$pane_name"
if [ "$RC" = 1 ] && printf '%s\n' "$OUT" | grep -q 'held=pane' && ! grep -q '^kill-window' "$tmp/tmux/calls"; then
  ok "a tmux server that cannot be listed holds the pane rather than reading it as gone"
else
  fail "an unlistable tmux server was read as released: exit $RC, $OUT"
fi
ML_TMUX_PANE=$win ml retire "$pane_name"
[ "$RC" = 3 ] && ok "retire refuses from inside the session's own window (exit 3)" || fail "a self-window retire exited $RC"
ml retire "$pane_name"
[ "$RC" = 0 ] && ok "a retry completes the release" || fail "the retry exited $RC: $OUT"
[ ! -e "$tmp/tmux/$win" ] && ok "the retired session has no pane" || fail "the pane survived retire"
[ ! -e "$fleet/mission-control/sessions/$pane_name" ] && ok "the retired tmux session has no row" || fail "the tmux row survived retire"

# A row whose window id is live under another name (renamed, or reused by
# another server): neither killed nor read as gone.
reuse_row="$fleet/mission-control/sessions/mc-alpha-ad-hoc-1111111111"
printf 'other-session\n' >"$tmp/tmux/@99"
printf 'format\t1\nname\tmc-alpha-ad-hoc-1111111111\nstate\tlaunched\nbackend\ttmux\nhandle\t@99\n' >"$reuse_row"
: >"$tmp/tmux/calls"
ml retire mc-alpha-ad-hoc-1111111111
if [ "$RC" = 1 ] && [ -e "$tmp/tmux/@99" ] && ! grep -q '^kill-window' "$tmp/tmux/calls" \
  && printf '%s\n' "$OUT" | grep -q 'held=pane'; then
  ok "a window id live under another name is held and not killed"
else
  fail "a window id under another name: exit $RC, $OUT"
fi
rm -f "$tmp/tmux/@99"
TMUX_NO_SERVER=1 ml retire mc-alpha-ad-hoc-1111111111
[ "$RC" = 0 ] && [ ! -e "$reuse_row" ] && ok "with no tmux server the window is gone and retire completes" \
  || fail "a retire with no tmux server: exit $RC, $OUT"

# A tmux reservation that never recorded its window: retire closes the window
# by name and retires the marker under its id.
nh_name=mc-alpha-ad-hoc-4444444444
printf '%s\n' "$nh_name" >"$tmp/tmux/@77"
mkdir -p "$fleet/dispatch-markers"
printf 'format\t1\nname\t%s\nstate\tlaunching\ntoken\tx\nbackend\ttmux\nhandle\t-\n' "$nh_name" >"$fleet/mission-control/sessions/$nh_name"
env PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-register.sh" --handle @77 --backend tmux \
  --scope offload --death-handle 'tmux-window stub @77' >/dev/null 2>&1
[ -f "$fleet/dispatch-markers/@77" ] || fail "fixture: no marker for @77"
ml retire "$nh_name"
if [ "$RC" = 0 ] && [ ! -e "$tmp/tmux/@77" ] && [ ! -e "$fleet/dispatch-markers/@77" ]; then
  ok "a reservation with no window id closes its window by name and retires its marker"
else
  fail "a no-handle tmux reservation: exit $RC, $OUT, marker $(ls "$fleet/dispatch-markers" 2>/dev/null)"
fi

# A launch that died after its reservation: retire finishes it; a launch
# still in flight is refused.
dead_row="$fleet/mission-control/sessions/mc-alpha-worker-2222222222"
sh -c 'exit 0' &
dead_pid=$!
wait "$dead_pid"
printf 'format\t1\nname\tmc-alpha-worker-2222222222\nstate\tlaunching\ntoken\tx\npid\t%s\nbackend\tstream-json\nhandle\tmc-alpha-worker-2222222222\n' "$dead_pid" >"$dead_row"
ml retire mc-alpha-worker-2222222222
[ "$RC" = 0 ] && [ ! -e "$dead_row" ] && ok "retire clears the reservation of a launch that died" \
  || fail "a dead launch's reservation was not cleared: exit $RC, $OUT $ERR"
# A launch in flight holds its name's lock, whatever its row says.
printf 'format\t1\nname\tmc-alpha-worker-2222222222\nstate\tlaunching\ntoken\tx\npid\t1\nbackend\tstream-json\nhandle\tmc-alpha-worker-2222222222\n' >"$dead_row"
mkdir -p "$fleet/mission-control/locks"
ln -s "$$-$(date +%s)-1" "$fleet/mission-control/locks/mc-alpha-worker-2222222222"
ml retire mc-alpha-worker-2222222222
[ "$RC" = 3 ] && [ -e "$dead_row" ] && ok "retire refuses a launch still in flight (exit 3)" \
  || fail "an in-flight launch was retired: exit $RC, $OUT"
rm -f "$fleet/mission-control/locks/mc-alpha-worker-2222222222" "$dead_row"
ml name --program alpha --kind reviewer --scope locked-launch
mkdir -p "$fleet/mission-control/locks"
ln -s "$$-$(date +%s)-1" "$fleet/mission-control/locks/$OUT"
ll_name=$OUT
ml launch --program alpha --kind reviewer --scope locked-launch --brief "$tmp/brief.md"
[ "$RC" = 3 ] && [ ! -e "$fleet/mission-control/sessions/$ll_name" ] \
  && ok "a launch whose name lock is held is refused (exit 3)" || fail "a locked launch exited $RC: $ERR"
rm -f "$fleet/mission-control/locks/$ll_name"

# A launch or retire of a name whose lock another live process holds.
mkdir -p "$fleet/mission-control/locks"
ln -s "$$-$(date +%s)-1" "$fleet/mission-control/locks/mc-alpha-reviewer-3333333333"
printf 'format\t1\nname\tmc-alpha-reviewer-3333333333\nstate\tlaunched\nbackend\tstream-json\nhandle\tmc-alpha-reviewer-3333333333\n' \
  >"$fleet/mission-control/sessions/mc-alpha-reviewer-3333333333"
ml retire mc-alpha-reviewer-3333333333
[ "$RC" = 3 ] && ok "a retire whose name lock is held is refused (exit 3)" || fail "a locked retire exited $RC: $ERR"
rm -f "$fleet/mission-control/locks/mc-alpha-reviewer-3333333333" "$fleet/mission-control/sessions/mc-alpha-reviewer-3333333333"

# A stream-json rung that refuses after the reservation leaves no row and no
# launch directory, and closes what it may have started.
ml name --program alpha --kind reviewer --scope rung-fails
rf_name=$OUT
sleep 30 &
rf_pid=$!
mkdir -p "$fleet/streamjson/$rf_name"
printf '%s\n' "$rf_pid" >"$fleet/streamjson/$rf_name/supervisor.pid"
ml launch --program alpha --kind reviewer --scope rung-fails --brief "$tmp/brief.md"
if [ "$RC" = 1 ] && [ ! -e "$fleet/mission-control/sessions/$rf_name" ] && [ ! -e "$fleet/mission-control/launch/$rf_name" ]; then
  ok "a rung that does not start leaves no row and no launch directory (exit 1)"
else
  fail "a failed rung start left state: exit $RC, $ERR"
fi
if kill -0 "$rf_pid" 2>/dev/null; then
  ok "a session the rung already held under the name is left running"
  kill "$rf_pid" 2>/dev/null
else
  fail "the failed launch stopped a session it never started"
fi
wait "$rf_pid" 2>/dev/null
rm -rf "${fleet:?}/streamjson/$rf_name"
# A rung that fails for another reason (here its dispatch wrapper is
# missing, exit 8) has nothing running, so the name is released.
mkdir -p "$tmp/s8"
cp -R "$repo_root/scripts" "$tmp/s8/scripts"
rm -f "$tmp/s8/scripts/fleet-dispatch-env.sh"
LAUNCH="$tmp/s8/scripts/mission-control-launch.sh" ml launch --program alpha --kind reviewer --scope rung-fails-2 --brief "$tmp/brief.md"
rf2_rc=$RC
ml name --program alpha --kind reviewer --scope rung-fails-2
if [ "$rf2_rc" = 1 ] && [ ! -e "$fleet/mission-control/sessions/$OUT" ] && [ ! -e "$fleet/mission-control/launch/$OUT" ]; then
  ok "a rung that fails to start a session leaves no row once nothing runs (exit 1)"
else
  fail "a failed rung start: exit $rf2_rc, row $(cat "$fleet/mission-control/sessions/$OUT" 2>/dev/null)"
fi

# A leftover launch directory with no row is cleared by the next launch.
ml name --program alpha --kind reviewer --scope leftover
lo_name=$OUT
mkdir -p "$fleet/mission-control/launch/$lo_name"
: >"$fleet/mission-control/launch/$lo_name/stale"
rec="$tmp/rec-leftover"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind reviewer --scope leftover --brief "$tmp/brief.md"
[ "$RC" = 0 ] && [ ! -e "$fleet/mission-control/launch/$lo_name/stale" ] \
  && ok "a launch clears a leftover launch directory of its name" || fail "a leftover launch directory wedged the name: exit $RC, $ERR"
wait_for "$rec/stdin" >/dev/null
wait_done "$lo_name"

# A launch directory that cannot be removed holds the row.
mkdir -p "$fleet/mission-control/launch/$lo_name/locked"
: >"$fleet/mission-control/launch/$lo_name/locked/f"
chmod 500 "$fleet/mission-control/launch/$lo_name/locked"
if [ -w "$fleet/mission-control/launch/$lo_name/locked" ]; then
  ok "skip: mode 500 does not stop this user removing files"
else
  ml retire "$lo_name"
  if [ "$RC" = 1 ] && printf '%s\n' "$OUT" | grep -q 'held=row' && [ -e "$fleet/mission-control/sessions/$lo_name" ]; then
    ok "a launch directory that will not go holds the row (exit 1)"
  else
    fail "an unremovable launch directory was reported released: exit $RC, $OUT"
  fi
fi
chmod 700 "$fleet/mission-control/launch/$lo_name/locked"
ml retire "$lo_name"
[ "$RC" = 0 ] && ok "the retry releases it" || fail "the retry after the launch directory exited $RC: $OUT"

# A fleet marker that does not match its record is not counted released.
ml name --program alpha --kind orchestrator --scope spec:alpha-orchestrator
orch=$OUT
if [ -f "$fleet/dispatch-markers/$orch" ]; then
  awk -F '\t' 'BEGIN { OFS = "\t" } { $2 = "spec:tampered"; print }' "$fleet/dispatch-markers/$orch" >"$tmp/marker"
  cat "$tmp/marker" >"$fleet/dispatch-markers/$orch"
  ml retire "$orch"
  if [ "$RC" = 1 ] && printf '%s\n' "$OUT" | grep -q 'held=registry'; then
    ok "a marker the fleet registry would not retire holds the registry class"
  else
    fail "a mismatched marker was counted released: exit $RC, $OUT"
  fi
else
  fail "fixture: the orchestrator session has no fleet marker"
fi

# A session that started but whose row could not be written is stopped.
ml name --program alpha --kind ad-hoc --scope row-fails
rw_name=$OUT
before=$(cat "$tmp/tmux/next" 2>/dev/null)
TMUX_LOCK_DIR="$fleet/mission-control/sessions" ml launch --program alpha --kind ad-hoc --scope row-fails \
  --brief "$tmp/brief.md" --backend tmux
chmod 700 "$fleet/mission-control/sessions"
said_stopped=0
case $ERR in *"was stopped"*) said_stopped=1 ;; esac
if [ "$RC" = 1 ] && [ ! -e "$tmp/tmux/@$before" ] && [ "$said_stopped" = 1 ]; then
  ok "a session whose row cannot be written is stopped (exit 1)"
else
  fail "a started session with no row was left running: exit $RC, $ERR"
fi
[ ! -e "$fleet/dispatch-markers/@$before" ] && ok "the stopped session's fleet marker is retired" \
  || fail "the stopped session's fleet marker was left behind"
rm -f "$fleet/mission-control/sessions/$rw_name"

# A row whose window id is not @ and digits never reaches tmux.
bad_row="$fleet/mission-control/sessions/mc-alpha-ad-hoc-0000000000"
printf 'format\t1\nname\tmc-alpha-ad-hoc-0000000000\nbackend\ttmux\nhandle\t@1;x\n' >"$bad_row"
: >"$tmp/tmux/calls"
ml retire mc-alpha-ad-hoc-0000000000
if [ "$RC" = 2 ] && [ ! -s "$tmp/tmux/calls" ]; then
  ok "a row naming a malformed window id is refused before any tmux call"
else
  fail "a malformed window id reached retire: exit $RC, calls: $(cat "$tmp/tmux/calls")"
fi
rm -f "$bad_row"

# A row in a format the launcher does not know is refused, naming the field.
ml name --program alpha --kind tower --scope spec:alpha-tower
tower_row="$fleet/mission-control/sessions/$OUT"
sed 's/^format	1$/format	9/' "$tower_row" >"$tmp/row9" && cat "$tmp/row9" >"$tower_row"
ml retire "$OUT"
[ "$RC" = 2 ] && case $ERR in *format*) true ;; *) false ;; esac \
  && ok "a row with an unknown format is refused, naming the field" || fail "an unknown-format row was not refused: $RC $ERR"
ml kinds
want_kinds=$(printf '%s\t%s\t%s\n' tower tower orchestrate_dispatch orchestrator tower bookkeeping worker worker execution \
  reviewer worker execute_step ad-hoc worker offload mission-control mission-control orchestrate_dispatch)
[ "$OUT" = "$want_kinds" ] && ok "kinds prints each kind's profile and key" || fail "kinds: $OUT"
ml list
if [ "$RC" = 0 ] && case $ERR in *"format field is not"*) true ;; *) false ;; esac \
  && printf '%s\n' "$OUT" | grep -q '^mc-alpha-orchestrator'; then
  ok "list warns on an unknown-format row and still lists the rest"
else
  fail "list with an unknown-format row: exit $RC, out $OUT, err $ERR"
fi
chmod 000 "$fleet/mission-control/sessions"
if [ -r "$fleet/mission-control/sessions" ]; then
  ok "skip: mode 000 does not stop this user reading the registry"
else
  ml list
  [ "$RC" = 2 ] && ok "list on an unreadable registry fails (exit 2)" || fail "list on an unreadable registry exited $RC: $OUT"
fi
chmod 700 "$fleet/mission-control/sessions"
if empty_out=$(env PLANWRIGHT_FLEET_STATE_DIR="$tmp/empty-fleet" /bin/sh "$LAUNCH" list 2>&1) && [ -z "$empty_out" ]; then
  ok "list with no registry prints nothing"
else
  fail "list with no registry: $empty_out"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mission-control-launch tests passed"
