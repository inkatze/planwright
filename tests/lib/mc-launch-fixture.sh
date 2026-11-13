# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # variables the sourcing tests read; $here and $repo_root come from them
unset CDPATH
# Shared fixture for the mission-control launch tests (sourced at top level by
# tests/test-mission-control-launch*.sh): the failure counters, the scratch tree
# and its cleanup, the CLI and tmux shims, the ml runner and its wait helpers.

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
ok() { printf 'ok: %s\n' "$1"; }
TAB=$(printf '\t')

for t in jq git; do
  command -v "$t" >/dev/null 2>&1 || {
    printf 'FAIL: %s is required to run this suite\n' "$t" >&2
    exit 1
  }
done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/mc-launch.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
fleet="$tmp/fleet"
cleanup() {
  # Close any supervisor a failed case left running, through the rung's own
  # stop, before the scratch tree goes.
  for fl in "$tmp/fleet" "$tmp/fleet-cap" "$tmp/fleet-wait"; do
    for d in "$fl"/streamjson/*/; do
      [ -d "$d" ] || continue
      env PLANWRIGHT_FLEET_STATE_DIR="$fl" /bin/sh "$repo_root/scripts/fleet-streamjson.sh" \
        stop "$(basename "$d")" --grace 1 >/dev/null 2>&1 || :
    done
  done
  rm -rf "$tmp"
}
trap cleanup EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"
# shellcheck source=tests/lib/emitter-lint.sh
. "$here/lib/emitter-lint.sh"
reset_mc_fixture
cp "$repo_root/config/defaults.yml" "$core/config/defaults.yml"
for p in worker tower mission-control; do
  cp "$repo_root/config/$p-settings.json" "$core/config/"
done
mkdir -p "$repo/specs/demo" "$fleet"
printf '%s\n' '# demo' >"$repo/specs/demo/requirements.md"
# A repository-changing kind gets a worktree off the default branch, so the
# fixture repository has one, with the launch worktrees ignored.
printf '%s\n' '.claude/worktrees/' >"$repo/.gitignore"
git -C "$repo" symbolic-ref HEAD refs/heads/main
git -C "$repo" add .gitignore specs
git -C "$repo" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false \
  commit -q -m init || fail "fixture: the initial commit failed"
home="$tmp/mc-home/alpha"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo/specs
program_alpha_home: $home
fleet_host_max_live_workers: off
EOF
mc_run mc-rules.sh add alpha --text "Never hand the operator a pane" --subject panes --source "operator, fixture" --date 2026-10-26
[ "$RC" = 0 ] || fail "fixture: the program rule was not added: $ERR"
mc_run mc-rules.sh add alpha --text "Docs need review" --subject docs --source "operator, fixture" --date 2026-10-26 --scope repo:repo
[ "$RC" = 0 ] || fail "fixture: the repository rule was not added: $ERR"

# The stream-json CLI shim: records argv and the first stdin line, then exits.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
pwd -P >"$SHIM_RECORD_DIR/cwd"
printf '%s\n' "$*" >"$SHIM_RECORD_DIR/argv.tmp" && mv "$SHIM_RECORD_DIR/argv.tmp" "$SHIM_RECORD_DIR/argv"
printf '%s\n' "${PLANWRIGHT_MC_TOKEN:-}" >"$SHIM_RECORD_DIR/mctoken"
printf '%s\n' "${PLANWRIGHT_TOWER_ID-<unset>}" >"$SHIM_RECORD_DIR/towerid"
printf '%s\n' "${TMUX-<unset>}" >"$SHIM_RECORD_DIR/tmuxvar"
printf '%s\n' "${TMUX_PANE-<unset>}" >"$SHIM_RECORD_DIR/tmuxpane"
printf '%s\n' "${PLANWRIGHT_LOCAL_CONFIG-<unset>}" >"$SHIM_RECORD_DIR/localcfg"
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
    # TMUX_BAD_ID: the window exists, but the id printed for it is unusable.
    if [ "${TMUX_BAD_ID:-0}" = 1 ]; then
      echo 'not a window id'
    else
      echo "@$n"
    fi
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
  has-session)
    # The worktree primitive's liveness probe: the stub runs no sessions.
    echo "can't find session: $3" >&2
    exit 1
    ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/claude" "$tmp/bin/tmux"
mkdir -p "$tmp/tmux"

# ml <args...> — run the launcher against the fixture. Sets RC, OUT, ERR.
ml() {
  OUT=$(cd "${ML_CD:-$repo}" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_SKILLS_ROOT \
    -u PLANWRIGHT_CONFIG_DEFAULTS -u PLANWRIGHT_REPO_ROOT_CHECKED -u PLANWRIGHT_CONFIG_STRICT_OVERLAYS \
    -u XDG_CONFIG_HOME -u TMUX -u TMUX_PANE -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    -u PLANWRIGHT_TOWER_ID -u PLANWRIGHT_TOWER_SESSION_ID -u PLANWRIGHT_TOWER_PID -u PLANWRIGHT_MC_TOKEN -u CLAUDE_CONFIG_DIR \
    PATH="$tmp/bin:$PATH" PLANWRIGHT_ROOT="$core" PLANWRIGHT_REPO_ROOT="${ML_REPO_ROOT-$repo}" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" PLANWRIGHT_LOCAL_CONFIG="$tmp/absent.yml" \
    CLAUDE_DIR="$tmp/claude" HOME="$fixhome" PLANWRIGHT_FLEET_STATE_DIR="$fleet" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT=off \
    TMUX_PANE="${ML_TMUX_PANE:-}" ${ML_TMUX:+TMUX="$ML_TMUX"} ${ML_MC_TOKEN:+PLANWRIGHT_MC_TOKEN="$ML_MC_TOKEN"} \
    SHIM_RECORD_DIR="${SHIM_RECORD_DIR:-$tmp}" TMUX_STUB="$tmp/tmux" TMUX_KILL_FAIL="${TMUX_KILL_FAIL:-0}" \
    TMUX_LIST_FAIL="${TMUX_LIST_FAIL:-0}" TMUX_LOCK_DIR="${TMUX_LOCK_DIR:-}" TMUX_NO_SERVER="${TMUX_NO_SERVER:-0}" TMUX_BAD_ID="${TMUX_BAD_ID:-0}" \
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
# reg_owner <handle> — the owner column of the handle's last fleet record,
# once one is written (bounded).
reg_owner() {
  n=0
  while [ "$n" -lt 100 ]; do
    ro=$(env PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-state.sh" registry 2>/dev/null \
      | awk -F '\t' -v w="$1" '$2 == w { o = $4 } END { print o }')
    [ -z "$ro" ] || break
    sleep 0.1
    n=$((n + 1))
  done
  printf '%s\n' "$ro"
}
# wait_done <name> — until the stream-json supervisor recorded the run's end.
wait_done() {
  n=0
  while [ ! -s "$fleet/streamjson/$1/result" ] && [ "$n" -lt 100 ]; do
    sleep 0.1
    n=$((n + 1))
  done
}

# wait_cwd_free <dir> — until no process runs with <dir> as its working
# directory (bounded at 60s, the load-tolerant wait for an exit). Where procfs
# is absent there is no portable scan, so it returns at once.
wait_cwd_free() {
  [ -d /proc/self ] || return 0
  wc_end=$(($(date +%s) + 60))
  while [ "$(date +%s)" -lt "$wc_end" ]; do
    held=$(find /proc -mindepth 2 -maxdepth 2 -name cwd \( -lname "$1" -o -lname "$1/*" \) 2>/dev/null | head -n 1)
    [ -n "$held" ] || return 0
    sleep 0.1
  done
  fail "a process still held $1 after 60s: $held"
}

printf '%s\n' "# Fixture brief" "" "Review the open pull requests." >"$tmp/brief.md"

# The posture the launcher checks before every launch (REQ-G1.5).
write_mc_posture_pass
posture_layer="$fixhome/.claude/settings.json"
cp "$posture_layer" "$tmp/posture-pass.json"
