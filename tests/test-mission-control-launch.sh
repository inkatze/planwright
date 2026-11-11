#!/bin/bash
# Tests for scripts/mission-control-launch.sh — the one launcher for every
# session kind and its retire verb (mission-control REQ-D1.1, REQ-D1.5,
# REQ-B1.4, REQ-G1.1, REQ-M1.7, REQ-A1.4, REQ-D1.16).
#
# Every kind launches from a fixture on the stream-json rung (a CLI shim
# records its argv and its first stdin line), one on the tmux rung (a tmux
# stub keeps a window table), and each launch's brief, rules, profile, tier
# and name are read back from what the launched session received.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).

# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
set -u
# The usage gate reads the status-line mirror when present; a fixture never
# reads the host's real one.
export PLANWRIGHT_USAGE_MIRROR=""
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

tmp=$(mktemp -d "${TMPDIR:-/tmp}/mc-launch.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
fleet="$tmp/fleet"
cleanup() {
  # Close any supervisor a failed case left running, through the rung's own
  # stop, before the scratch tree goes.
  for fl in "$tmp/fleet" "$tmp/fleet-cap"; do
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
  # A mission-control session starts in auto mode, so a routine command does
  # not stall a successor on a prompt no other session may answer; every other
  # kind keeps prompting.
  # The profile is the mode source: the argv never names a mode.
  mode=$(jq -r '.permissions.defaultMode' "$core/config/$prof-settings.json")
  case $kind:$mode in
    mission-control:auto) ok "[$kind] the session starts in auto mode" ;;
    mission-control:*) fail "[$kind] the session starts in mode '$mode', not auto" ;;
    *:auto) fail "[$kind] a $kind session starts in auto mode" ;;
    *) ok "[$kind] the session starts in mode '$mode', not auto" ;;
  esac
  case " $argv " in
    *" --permission-mode"*) fail "[$kind] the argv names a permission mode, overriding the profile: $argv" ;;
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
  ro=$(reg_owner "$name")
  [ "$ro" = mission-control:alpha ] && ok "[$kind] the fleet registry attributes the session to mission-control:alpha" \
    || fail "[$kind] the fleet registry record's owner is '$ro', not mission-control:alpha"
  [ "$(cat "$rec/towerid" 2>/dev/null)" = '<unset>' ] && ok "[$kind] the session does not inherit the owner as its own tower identity" \
    || fail "[$kind] the session inherited PLANWRIGHT_TOWER_ID '$(cat "$rec/towerid" 2>/dev/null)'"
  case " $argv " in
    *" $want_tier "*) ok "[$kind] the session runs at its key's tier ($want_tier)" ;;
    *) fail "[$kind] the session's argv lacks its key's tier '$want_tier': $argv" ;;
  esac
  case $kind in
    tower | mission-control) want_key=orchestrate_dispatch ;;
    orchestrator) want_key=bookkeeping ;;
    worker) want_key=execution ;;
    reviewer) want_key=execute_step ;;
    ad-hoc) want_key=offload ;;
  esac
  if [ "$(cat "$fleet/streamjson/$name/tier_key" 2>/dev/null)" = "$want_key" ] \
    && [ "$(cat "$fleet/streamjson/$name/tier_unit" 2>/dev/null)" = "mission-control:$name" ]; then
    ok "[$kind] the launch records its tier key and unit for a relaunch"
  else
    fail "[$kind] the launch did not record tier key $want_key and unit mission-control:$name"
  fi
  # Only a mission-control session holds its row's token, which is what
  # binds a decided-by-mission-control item to the row (tower-comms REQ-A1.14).
  row_token=$(awk -F "$TAB" '$1 == "token" { print $2; exit }' "$row")
  got_token=$(cat "$rec/mctoken" 2>/dev/null)
  if [ "$kind" = mission-control ]; then
    [ -n "$row_token" ] && [ "$got_token" = "$row_token" ] && ok "[$kind] the session holds its registry row's token" \
      || fail "[$kind] the session's PLANWRIGHT_MC_TOKEN '$got_token' is not its row's '$row_token'"
    # REQ-G1.5: with no settings layer of its own, the launched session's
    # posture passes on the profile the row the launch wrote records.
    mkdir -p "$tmp/empty-home"
    p_out=$(cd "$repo" && env -u CLAUDE_CONFIG_DIR -u CLAUDE_PLUGIN_DATA HOME="$tmp/empty-home" CLAUDE_PLUGIN_ROOT="$repo_root" \
      PLANWRIGHT_FLEET_STATE_DIR="$fleet" PLANWRIGHT_MC_TOKEN="$got_token" \
      /bin/bash "$repo_root/scripts/mc-posture.sh" check --managed "$tmp/no-managed.json" 2>&1)
    [ "$p_out" = "posture${TAB}pass" ] && ok "[$kind] the launched session's posture passes on the profile its row records" \
      || fail "[$kind] the launched session's posture does not pass on its row's profile: $p_out"
  else
    [ -z "$got_token" ] && ok "[$kind] the session holds no mission-control token" \
      || fail "[$kind] a $kind session was handed a mission-control token"
  fi
  first=$(head -n 1 "$fleet/mission-control/launch/$name/brief.md")
  [ "$first" = '# Fixture brief' ] && ok "[$kind] the composed brief opens with the brief itself" \
    || fail "[$kind] the composed brief opens with '$first'"
  # A kind that changes a repository carries the configured cadence and its
  # audit whatever its hand-written brief says; the others do not.
  composed_brief="$fleet/mission-control/launch/$name/brief.md"
  case $kind in
    worker | reviewer | ad-hoc)
      grep -qx '## Verification cadence' "$composed_brief" && grep -qF 'step-run.sh audit --through post-pr' "$composed_brief" \
        && grep -qF 'step-run.sh audit --through pre-pr' "$composed_brief" \
        && grep -qF "mission-control:$name" "$composed_brief" \
        && ok "[$kind] the composed brief carries the cadence, its audit and its tier unit" \
        || fail "[$kind] the composed brief lacks the cadence section: $(cat "$composed_brief")"
      # Every path the section names is a file of this install.
      missing_paths=''
      # shellcheck disable=SC2016 # literal backticks delimit the paths
      for cp in $(grep -o '`/[^` ]*/[^` ]*' "$composed_brief" | tr -d '`'); do
        [ -e "$cp" ] || missing_paths="$missing_paths $cp"
      done
      [ -z "$missing_paths" ] && ok "[$kind] every path the cadence names exists" \
        || fail "[$kind] the cadence names paths that do not exist:$missing_paths"
      if lint_emitted markdown mission-control-launch.sh "$composed_brief"; then
        ok "[$kind] the brief with its cadence lints clean as markdown"
      else
        fail "[$kind] the brief with its cadence fails the markdown lint: $composed_brief"
      fi
      ;;
    *)
      grep -q 'Verification cadence' "$composed_brief" && fail "[$kind] a session that changes no repository was handed the cadence" \
        || ok "[$kind] no cadence section for a kind that changes no repository"
      ;;
  esac
  wait_done "$name"
done
ml list
[ "$(printf '%s\n' "$OUT" | grep -c .)" = 6 ] && ok "list shows the six launched sessions" \
  || fail "list does not show six sessions: $OUT"

# A brief that runs a skill command leaves the cadence to that skill.
printf '%s\n' '/planwright:execute-task specs/alpha 3' >"$tmp/skill-brief.md"
rec="$tmp/rec-skill"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind worker --scope skill-brief --brief "$tmp/skill-brief.md"
[ "$RC" = 0 ] || fail "the skill-command launch exited $RC: $ERR"
skill_brief="$fleet/mission-control/launch/$(field name)/brief.md"
if [ "$(head -n 1 "$skill_brief")" = '/planwright:execute-task specs/alpha 3' ] && ! grep -q 'Verification cadence' "$skill_brief"; then
  ok "a skill-command brief opens with its command and gets no second cadence"
else
  fail "the skill-command brief was changed: $(cat "$skill_brief")"
fi
wait_done "$(field name)"
# The section sends the session to /execute-task's *Points* heading, which
# must still exist there.
# shellcheck disable=SC2016 # the heading's literal backticks
grep -qx '## Points (`custom-steps`, D-3)' "$repo_root/skills/execute-task/SKILL.md" \
  && ok "the Points heading the cadence names exists in /execute-task" \
  || fail "/execute-task no longer carries the Points heading the launcher's cadence names"
# A brief that opens with a path, not a command, still gets the cadence.
printf '%s\n' '/tmp/notes.md: apply the notes' >"$tmp/path-brief.md"
rec="$tmp/rec-path"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind ad-hoc --scope path-brief --brief "$tmp/path-brief.md"
[ "$RC" = 0 ] || fail "the path-brief launch exited $RC: $ERR"
grep -qx '## Verification cadence' "$fleet/mission-control/launch/$(field name)/brief.md" \
  && ok "a brief opening with a path is no skill command, so it gets the cadence" \
  || fail "a path-led brief was taken for a skill command"
wait_done "$(field name)"

# --rules adds an in-scope rule to the brief.
rec="$tmp/rec-rules"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind reviewer --scope rules-case --brief "$tmp/brief.md" --rules repo:repo
[ "$RC" = 0 ] || fail "the --rules launch exited $RC: $ERR"
wait_for "$rec/stdin" && grep -qF 'Docs need review' "$rec/stdin" \
  && ok "a --rules scope adds its rules to the brief" || fail "the --rules scope's rule did not reach the session"
rules_brief="$fleet/mission-control/launch/$(field name)/brief.md"
if lint_emitted markdown mission-control-launch.sh "$rules_brief"; then
  ok "the composed brief with program and scope rules lints clean as markdown"
else
  fail "the composed brief fails the markdown lint: $rules_brief"
fi
wait_done "$(field name)"

# A stream-json worker has no pane: it must not inherit the launcher's tmux
# context, or its per-step sessions read it as an opt-in to tmux windows.
for kind in worker ad-hoc reviewer; do
  rec="$tmp/rec-tmuxenv-$kind"
  mkdir -p "$rec"
  SHIM_RECORD_DIR=$rec ML_TMUX=/tmp/tmux-fixture/default,1,0 ML_TMUX_PANE=%9 \
    ml launch --program alpha --kind "$kind" --scope "tmuxenv-$kind" --brief "$tmp/brief.md"
  if [ "$RC" != 0 ] || ! wait_for "$rec/tmuxpane"; then
    fail "[$kind] the launch under a tmux context did not start: $ERR"
    continue
  fi
  [ "$(cat "$rec/tmuxvar")" = '<unset>' ] && [ "$(cat "$rec/tmuxpane")" = '<unset>' ] \
    && ok "[$kind] a stream-json session does not inherit TMUX or TMUX_PANE" \
    || fail "[$kind] a stream-json session inherited TMUX='$(cat "$rec/tmuxvar")' TMUX_PANE='$(cat "$rec/tmuxpane")'"
  wait_done "$(field name)"
done

# An attended --backend tmux launch is unchanged by that: the window is still
# created.
: >"$tmp/tmux/calls"
ML_TMUX=/tmp/tmux-fixture/default,1,0 ML_TMUX_PANE=%9 \
  ml launch --program alpha --kind ad-hoc --scope tmuxenv-tmux --brief "$tmp/brief.md" --backend tmux
if [ "$RC" = 0 ] && grep -q '^new-window' "$tmp/tmux/calls"; then
  ok "a --backend tmux launch still opens its tmux window"
else
  fail "a --backend tmux launch under a tmux context exited $RC without a window: $ERR"
fi
wait_done "$(field name)"

# No item handed back names a pane, window or attach hint.
ml launch --program alpha --kind ad-hoc --scope pane-check --brief "$tmp/brief.md" --backend tmux
case $OUT in
  *attach* | *observe* | *capture-pane* | *'@'[0-9]*) fail "the launch report names a pane or window: $OUT" ;;
  *) ok "the launch report names no pane, window or attach hint" ;;
esac
# A per-call rung away from the knob launches all the same, warned naming it.
[ "$RC" = 0 ] || fail "the tmux launch against the stream-json knob exited $RC: $ERR"
case $ERR in
  *warning*'--backend tmux'*mission_control_launch_backend*stream-json*) ok "a per-call --backend away from the knob warns, naming the knob" ;;
  *) fail "a per-call --backend away from the knob did not warn naming it: $ERR" ;;
esac
pane_name=$(field name)
pane_handle=$(awk -F "$TAB" '$1 == "handle" { print $2; exit }' "$fleet/mission-control/sessions/$pane_name")
grep -q 'PLANWRIGHT_MC_TOKEN=' "$tmp/tmux/argv-$pane_handle" && fail "a tmux ad-hoc session was handed a mission-control token" \
  || ok "a tmux session of another kind holds no mission-control token"
ml launch --program alpha --kind mission-control --scope tmux-token --brief "$tmp/brief.md" --backend tmux
[ "$RC" = 0 ] || fail "the tmux mission-control launch exited $RC: $ERR"
mt_warns=$(printf '%s\n' "$ERR" | grep -c 'overrides mission_control_launch_backend')
[ "$mt_warns" = 1 ] && ok "a mission-control launch warns of a per-call --backend once, though it resolves the rung for its posture check too" \
  || fail "a mission-control launch's --backend override warned $mt_warns times: $ERR"
mt_name=$(field name)
mt_row="$fleet/mission-control/sessions/$mt_name"
mt_handle=$(awk -F "$TAB" '$1 == "handle" { print $2; exit }' "$mt_row")
mt_token=$(awk -F "$TAB" '$1 == "token" { print $2; exit }' "$mt_row")
grep -qxF "PLANWRIGHT_MC_TOKEN=$mt_token" "$tmp/tmux/argv-$mt_handle" && ok "a tmux mission-control session is launched holding its row's token" \
  || fail "the tmux mission-control window's argv does not carry its row's token: $(tr '\n' ' ' <"$tmp/tmux/argv-$mt_handle" 2>/dev/null)"
# The pane the operator attaches to starts in auto mode, from its profile.
mt_settings=$(awk 'p { print; exit } $0 == "--settings" { p = 1 }' "$tmp/tmux/argv-$mt_handle" 2>/dev/null)
if [ -n "$mt_settings" ] && [ "$(jq -r '.permissions.defaultMode' "$mt_settings" 2>/dev/null)" = auto ]; then
  ok "a tmux mission-control session starts in auto mode"
else
  fail "the tmux mission-control window does not start in auto mode (settings '$mt_settings')"
fi
grep -q '^--permission-mode' "$tmp/tmux/argv-$mt_handle" && fail "the tmux mission-control argv names a permission mode, overriding its profile"
# Remote Control: a tmux mission-control window takes --remote-control <name>
# only when asked, the name validated; every other kind and rung refuses it.
rc_argv_has() { awk -v v="$2" 'prev == "--remote-control" && $0 == v { ok = 1 } { prev = $0 } END { exit !ok }' "$1"; }
ml launch --program alpha --kind mission-control --scope rc-named --brief "$tmp/brief.md" --backend tmux --remote-control mc-rc-named
[ "$RC" = 0 ] || fail "the tmux mission-control launch with --remote-control exited $RC: $ERR"
rc_named=$(field name)
rc_named_handle=$(awk -F "$TAB" '$1 == "handle" { print $2; exit }' "$fleet/mission-control/sessions/$rc_named")
rc_argv_has "$tmp/tmux/argv-$rc_named_handle" mc-rc-named && ok "a tmux mission-control window with --remote-control starts Remote Control under the name" \
  || fail "the window's argv lacks --remote-control mc-rc-named: $(tr '\n' ' ' <"$tmp/tmux/argv-$rc_named_handle" 2>/dev/null)"
ml launch --program alpha --kind mission-control --scope rc-plain --brief "$tmp/brief.md" --backend tmux
[ "$RC" = 0 ] || fail "the tmux mission-control launch without --remote-control exited $RC: $ERR"
rc_plain=$(field name)
rc_plain_handle=$(awk -F "$TAB" '$1 == "handle" { print $2; exit }' "$fleet/mission-control/sessions/$rc_plain")
grep -qx -- '--remote-control' "$tmp/tmux/argv-$rc_plain_handle" && fail "a launch that asked for no Remote Control starts one" \
  || ok "a tmux mission-control launch without --remote-control starts none"
ml launch --program alpha --kind mission-control --scope rc-hostile --brief "$tmp/brief.md" --backend tmux --remote-control 'mc;rm'
[ "$RC" = 2 ] && ! grep -q 'rc-hostile' "$tmp/tmux/calls" && ok "a --remote-control name outside the session-name grammar is refused before a window opens" \
  || fail "a hostile --remote-control name: exit $RC, calls: $(cat "$tmp/tmux/calls")"
ml launch --program alpha --kind ad-hoc --scope rc-kind --brief "$tmp/brief.md" --backend tmux --remote-control mc-rc-kind
[ "$RC" = 2 ] && ok "--remote-control is refused for a kind other than mission-control" \
  || fail "--remote-control on an ad-hoc launch: exit $RC: $ERR"
rm -f "$tmp/argv"
ml launch --program alpha --kind mission-control --scope rc-stream --brief "$tmp/brief.md" --backend stream-json --remote-control mc-rc-stream
[ "$RC" = 0 ] && case $ERR in *'--remote-control'*'stream-json'*) ok "the stream-json rung warns that it starts a successor without Remote Control" ;; *) fail "no stream-json warning: $ERR" ;; esac \
  || fail "a stream-json launch with --remote-control: exit $RC: $ERR"
wait_for "$tmp/argv" && ! grep -q -- '--remote-control' "$tmp/argv" && ok "the stream-json session is started without --remote-control" \
  || fail "the stream-json session's argv: $(cat "$tmp/argv" 2>/dev/null)"
rc_stream=$(field name)
wait_done "$rc_stream"
ml retire "$rc_stream"
ml launch --program alpha --kind ad-hoc --scope same-rung --brief "$tmp/brief.md" --backend stream-json
[ "$RC" = 0 ] || fail "the stream-json launch under the stream-json knob exited $RC: $ERR"
case $ERR in
  *mission_control_launch_backend*) fail "a --backend matching the knob warned: $ERR" ;;
  *) ok "a --backend matching the knob launches without a warning" ;;
esac
wait_done "$(field name)"
if [ -e "$adopter/planwright.yml" ]; then
  fail "fixture: the adopter layer already exists, so the layer-set knob cases are skipped"
else
  printf '%s\n' 'mission_control_launch_backend: tmux' >"$adopter/planwright.yml"
  ml launch --program alpha --kind ad-hoc --scope knob-tmux --brief "$tmp/brief.md" --backend tmux
  rm -f "$adopter/planwright.yml"
  if [ "$RC" = 0 ]; then
    case $ERR in
      *mission_control_launch_backend*) fail "a --backend matching the knob a layer sets warned: $ERR" ;;
      *) ok "the warning reads the knob a layer sets, not the shipped rung" ;;
    esac
    ml retire "$(field name)"
    [ "$RC" = 0 ] || fail "retiring the knob-tmux session exited $RC: $OUT $ERR"
  else
    fail "the tmux launch under a tmux knob exited $RC: $ERR"
  fi
  printf '%s\n' 'mission_control_launch_backend: tmux' >"$adopter/planwright.yml"
  ml launch --program alpha --kind ad-hoc --scope knob-tmux-noflag --brief "$tmp/brief.md"
  rm -f "$adopter/planwright.yml"
  if [ "$RC" = 0 ]; then
    noflag_name=$(field name)
    noflag_backend=$(awk -F "$TAB" '$1 == "backend" { print $2; exit }' "$fleet/mission-control/sessions/$noflag_name")
    [ "$noflag_backend" = tmux ] && ok "a launch naming no rung starts on the rung a layer's knob sets" \
      || fail "a launch naming no rung under a tmux knob registered backend '$noflag_backend'"
    case $ERR in
      *mission_control_launch_backend*) fail "a launch naming no rung warned: $ERR" ;;
      *) ok "a launch naming no rung does not warn" ;;
    esac
    ml retire "$noflag_name"
    [ "$RC" = 0 ] || fail "retiring the knob-tmux-noflag session exited $RC: $OUT $ERR"
  else
    fail "a launch naming no rung under a tmux knob exited $RC: $ERR"
  fi
fi
cp "$tracked" "$tmp/tracked.saved"
printf '%s\n' 'mission_control_launch_backend: bogus' >>"$tracked"
ml launch --program alpha --kind ad-hoc --scope knob-bogus --brief "$tmp/brief.md" --backend tmux
bogus_rc=$RC bogus_err=$ERR bogus_name=$(field name)
ml launch --program alpha --kind ad-hoc --scope knob-bogus-noflag --brief "$tmp/brief.md"
cp "$tmp/tracked.saved" "$tracked"
if [ "$bogus_rc" = 0 ]; then
  case $bogus_err in
    *warning*'--backend tmux'*mission_control_launch_backend*'could not be resolved'*) ok "a --backend launch the knob cannot be checked against warns so" ;;
    *) fail "a --backend launch with an unresolvable knob did not warn: $bogus_err" ;;
  esac
else
  fail "a --backend launch with an unresolvable knob exited $bogus_rc: $bogus_err"
fi
case $RC:$ERR in
  4:*'cannot resolve mission_control_launch_backend'*) ok "a launch naming no rung still refuses an unresolvable knob" ;;
  *) fail "a launch naming no rung under an unresolvable knob was not refused with exit 4: $RC $ERR" ;;
esac
if [ -n "$bogus_name" ]; then
  ml retire "$bogus_name"
  [ "$RC" = 0 ] || fail "retiring the knob-bogus session exited $RC: $OUT $ERR"
fi

# A stream-json launch resolves its tier in the directory the session runs in,
# as the tmux rung and a relaunch do, not in the launcher's own directory.
other="$tmp/other-repo"
mkdir -p "$other/.claude"
git -C "$other" init -q
printf '%s\n' 'allocation_model_orchestrate_dispatch: opus' 'allocation_effort_orchestrate_dispatch: high' >"$other/.claude/planwright.yml"
rec="$tmp/rec-cwd-tier"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ML_REPO_ROOT='' ml launch --program alpha --kind tower --scope cwd-tier --brief "$tmp/brief.md" --cwd "$other"
if [ "$RC" != 0 ]; then
  fail "the launch into another repository exited $RC: $ERR"
elif ! wait_for "$rec/stdin"; then
  fail "the launch into another repository never reached its session"
else
  case " $(cat "$rec/argv") " in
    *" --model opus --effort high "*) ok "a stream-json launch resolves its tier in the session's directory" ;;
    *) fail "the launch tier was not resolved in --cwd: $(cat "$rec/argv")" ;;
  esac
fi
wait_done "$(field name)"

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
# REQ-G1.5: a failing posture check refuses the launch before anything starts.
jq '.permissions.deny |= .[1:]' "$tmp/posture-pass.json" >"$posture_layer"
ml launch --program alpha --kind worker --scope posture-floor --brief "$tmp/brief.md"
[ "$RC" = 4 ] && ok "a launch without the shipped deny floor is refused (exit 4)" || fail "a floor-less launch exited $RC: $ERR"
case $ERR in *"posture check failed: the shipped deny floor is not in force"*) ok "the refusal gives the posture reason" ;; *) fail "the floor refusal does not say why: $ERR" ;; esac
ml name --program alpha --kind worker --scope posture-floor
[ ! -e "$fleet/mission-control/sessions/$OUT" ] && ok "the posture refusal left no registry row" || fail "the posture refusal left a row"
jq 'del(.hooks)' "$tmp/posture-pass.json" >"$posture_layer"
ml launch --program alpha --kind worker --scope posture-hooks --brief "$tmp/brief.md"
[ "$RC" = 4 ] && ok "a launch whose guard hooks are not wired is refused (exit 4)" || fail "a hook-less launch exited $RC: $ERR"
case $ERR in *"posture check failed: the guard hook"*"is not wired"*) ok "the refusal names the unwired hook" ;; *) fail "the hook refusal does not say why: $ERR" ;; esac
cp "$tmp/posture-pass.json" "$posture_layer"
rec="$tmp/rec-posture"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind worker --scope posture-floor --brief "$tmp/brief.md"
[ "$RC" = 0 ] && ok "once the posture passes, the same launch goes through" || fail "the launch after a passing posture exited $RC: $ERR"
wait_done "$(field name)"
# A posture check that could not run (any exit but pass or fail) refuses too.
mkdir -p "$tmp/sp"
cp -R "$repo_root/scripts" "$tmp/sp/scripts"
printf '#!/bin/bash\necho "mc-posture: jq is required" >&2\nexit 2\n' >"$tmp/sp/scripts/mc-posture.sh"
LAUNCH="$tmp/sp/scripts/mission-control-launch.sh" ml launch --program alpha --kind worker --scope posture-norun --brief "$tmp/brief.md"
[ "$RC" = 4 ] && ok "a launch whose posture check did not run is refused (exit 4)" || fail "a launch whose posture check did not run exited $RC: $ERR"
case $ERR in *"posture check did not run: mc-posture: jq is required"*) ok "the refusal says the check did not run, with its message" ;; *) fail "the did-not-run refusal does not say why: $ERR" ;; esac
LAUNCH="$tmp/sp/scripts/mission-control-launch.sh" ml name --program alpha --kind worker --scope posture-norun
[ ! -e "$fleet/mission-control/sessions/$OUT" ] && ok "the did-not-run refusal left no registry row" || fail "the did-not-run refusal left a row"
rm -rf "$tmp/sp"

# REQ-G1.5: a mission-control launch is held to the posture the session it
# starts runs under (its profile, the inherited user and managed layers, and
# its own directory's project layer), so an operator's shell that carries no
# mission-control settings can start one; every other kind is held to the
# caller's own posture.
printf '{}\n' >"$posture_layer"
rec="$tmp/rec-self-start"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind mission-control --scope self-start --brief "$tmp/brief.md"
[ "$RC" = 0 ] && ok "a mission-control launch from a caller without the posture passes on the session's own profile" \
  || fail "a mission-control launch from a caller without the posture exited $RC: $ERR"
wait_done "$(field name)"
ml launch --program alpha --kind worker --scope caller-posture --brief "$tmp/brief.md"
[ "$RC" = 4 ] && ok "a launch of another kind is still held to the caller's own posture" \
  || fail "a worker launch from a caller without the posture exited $RC: $ERR"
ML_MC_TOKEN=not-a-row-token ml launch --program alpha --kind mission-control --scope token-caller --brief "$tmp/brief.md"
[ "$RC" = 4 ] && ok "a mission-control caller whose own posture fails launches no successor" \
  || fail "a mission-control caller failing its own posture launched a mission control (exit $RC): $ERR"
cp "$tmp/posture-pass.json" "$posture_layer"
mkdir -p "$tmp/mc-cwd/.claude"
printf '%s\n' '{"disableAllHooks": true}' >"$tmp/mc-cwd/.claude/settings.local.json"
ml launch --program alpha --kind mission-control --scope hooks-off --brief "$tmp/brief.md" --cwd "$tmp/mc-cwd"
[ "$RC" = 4 ] && ok "a mission-control launch into a directory whose settings turn every hook off is refused" \
  || fail "a mission-control launch into a hooks-off directory exited $RC: $ERR"
case $ERR in *"posture check failed: every hook is turned off"*) ok "the refusal gives the session's posture reason" ;; *) fail "the session posture refusal does not say why: $ERR" ;; esac
# The documented attended start: no brief, so the session opens on the skill.
printf '{}\n' >"$posture_layer"
ml launch --program alpha --kind mission-control --scope attended --backend tmux
[ "$RC" = 0 ] && ok "an attended mission control starts with no brief of its own" \
  || fail "the attended mission-control start exited $RC: $ERR"
first=$(head -n 1 "$fleet/mission-control/launch/$(field name)/brief.md" 2>/dev/null)
[ "$first" = '/planwright:mission-control alpha' ] && ok "a mission control launched with no brief opens on the skill for its program" \
  || fail "a brief-less mission control opens with '$first'"
ml launch --program alpha --kind worker --scope no-brief
[ "$RC" = 2 ] && ok "another kind still needs its brief" || fail "a brief-less worker launch exited $RC: $ERR"
cp "$tmp/posture-pass.json" "$posture_layer"

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
mkdir -p "$tmp/s3/config" && cp "$repo_root/config/mission-control-settings.json" "$tmp/s3/config/"
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
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^retire	$worker_name	released	released=process,registry,attention	held=-$" \
  && ok "a second retire closes the row-less worker idempotently" || fail "a second retire: exit $RC, $OUT $ERR"

# A worker an older planwright or /orchestrate launched straight on the
# stream-json rung has no row: retire closes it by its handle all the same,
# a dead one included, and its stale attention row goes with it.
old="$fleet/streamjson/cp-task-1"
mkdir -p "$old"
printf '999999999\n' >"$old/supervisor.pid"
printf '999999999\n' >"$old/worker.pid"
printf 'aaaa1111-bbbb-cccc-dddd-eeee00000001\tpermission\t1000\tpending\n' >"$old/journal"
env PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-attention.sh" decide cp-task-1 cp:task-1 \
  "OVERDUE permission request tool Bash req aaaa1111 - answer via fleet-streamjson.sh answer" deny "allow|deny" high \
  || fail "fixture: the stale attention row was not seeded"
ml retire cp-task-1
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^retire	cp-task-1	released	released=process,registry,attention	held=-$" \
  && ok "retire closes a worker launched without the launcher" || fail "retire of a row-less worker: exit $RC, $OUT $ERR"
if env PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/sh "$repo_root/scripts/fleet-attention.sh" queue 2>/dev/null | grep -q cp-task-1; then
  fail "the row-less worker's attention row survived its retire"
else
  ok "and its stale attention row is gone"
fi
grep -q "	undeliverable	" "$old/journal" && ok "and its pending receipt is closed" || fail "the receipt stayed: $(cat "$old/journal")"
busy="$fleet/streamjson/orch-busy"
mkdir -p "$busy"
ln -s "$$-$(date +%s)-1" "$busy/recover.lock"
ml retire orch-busy
[ "$RC" = 3 ] && case $ERR in *"recover.lock is held"*) true ;; *) false ;; esac \
  && ok "retire refuses a row-less worker whose recover is in flight, naming the lock" || fail "retire over a held recover lock: exit $RC, $OUT $ERR"
[ -L "$busy/recover.lock" ] && ok "and leaves the recover's lock alone" || fail "the in-flight recover's lock was broken"
rm -rf "$busy"
ml retire nosuch-worker
[ "$RC" = 3 ] && ok "a name with neither a row nor a stream-json worker exits 3" || fail "retire of an unknown name exited $RC"
case $ERR in *"fleet-dispatch-headless.sh stop nosuch-worker"*"tmux kill-window"*) ok "and names the stops that apply" ;; *) fail "the refusal names no stop: $ERR" ;; esac
ml retire mc-alpha-worker-9999999999
[ "$RC" = 3 ] && ok "a launcher name with no row and no worker exits 3" || fail "retire of an unknown launcher name exited $RC"
ml retire "../x"
[ "$RC" = 2 ] && ok "a name outside the handle grammar is refused (exit 2)" || fail "a traversal name exited $RC"

win=$(awk -F '\t' '$1 == "handle" { print $2 }' "$fleet/mission-control/sessions/$pane_name")
[ -e "$tmp/tmux/$win" ] && ok "the tmux session has a live window ($win) before retire" || fail "the tmux launch left no window"
ro=$(reg_owner "$win")
[ "$ro" = mission-control:alpha ] && ok "the fleet registry attributes the tmux session to mission-control:alpha" \
  || fail "the tmux session's fleet record owner is '$ro', not mission-control:alpha"
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
mkdir -p "$tmp/s8/config" && cp "$repo_root/config/mission-control-settings.json" "$tmp/s8/config/"
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

# A window the rung created but could not name is closed by name before the
# reservation is released.
bad_before=$(cat "$tmp/tmux/next" 2>/dev/null)
TMUX_BAD_ID=1 ml launch --program alpha --kind ad-hoc --scope bad-window --brief "$tmp/brief.md" --backend tmux
bad_rc=$RC
ml name --program alpha --kind ad-hoc --scope bad-window
if [ "$bad_rc" = 1 ] && [ ! -e "$tmp/tmux/@$bad_before" ] && [ ! -e "$fleet/mission-control/sessions/$OUT" ]; then
  ok "a window the rung could not name is closed and the name released (exit 1)"
else
  fail "a window with an unusable id: exit $bad_rc, window $(ls "$tmp/tmux/@$bad_before" 2>&1), row $(cat "$fleet/mission-control/sessions/$OUT" 2>/dev/null)"
fi

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

# ---------------------------------------------------------------------------
# REQ-D1.10: a repository-changing kind starts in its own worktree, never in
# a primary checkout; the other kinds start where they are launched.
# ---------------------------------------------------------------------------
gitc() { git -C "$repo" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false "$@"; }
# no_session <scope> <kind> — no row and no supervisor exist for the launch.
no_session() {
  ns_name=$(cd "$repo" && /bin/sh "$LAUNCH" name --program alpha --kind "$2" --scope "$1")
  [ ! -e "$fleet/mission-control/sessions/$ns_name" ] && [ ! -d "$fleet/streamjson/$ns_name" ]
}
# launched_in <rec> — the directory the launched session ran in.
launched_in() {
  wait_for "$1/cwd" && cat "$1/cwd"
}

before_head=$(git -C "$repo" rev-parse HEAD)
before_branch=$(git -C "$repo" symbolic-ref HEAD)
before_status=$(git -C "$repo" status --porcelain)
rec="$tmp/rec-wt-new"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind worker --scope wt-new --brief "$tmp/brief.md"
if [ "$RC" != 0 ]; then
  fail "a worker launch with no directory exited $RC: $ERR"
else
  wt=$(launched_in "$rec")
  case $wt in
    "$repo/.claude/worktrees/"?*)
      wt_ref=$(git -C "$wt" symbolic-ref HEAD 2>/dev/null)
      if [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" = "$before_head" ] \
        && [ "${wt_ref#refs/heads/planwright/flight/}" != "$wt_ref" ]; then
        ok "a worker launch with no directory starts in a new worktree off the default branch"
      else
        fail "the new worktree $wt is not a fresh branch off main: $(git -C "$wt" log --oneline -1 2>&1)"
      fi
      ;;
    *) fail "a worker launch with no directory started in '$wt', not a new worktree" ;;
  esac
  wait_done "$(field name)"
fi
[ "$(git -C "$repo" rev-parse HEAD)" = "$before_head" ] && [ "$(git -C "$repo" symbolic-ref HEAD)" = "$before_branch" ] \
  && [ "$(git -C "$repo" status --porcelain)" = "$before_status" ] \
  && ok "the primary checkout's HEAD, branch and status are unchanged" \
  || fail "the launch changed the primary checkout: $(git -C "$repo" status --porcelain)"

# The same inputs relaunched after a retire find the worktree on the branch
# they started, with no live session there, and reuse it.
first_wt=$(cat "$rec/cwd" 2>/dev/null)
# The result file lands while the supervisor is still winding down in the
# worktree; the launcher refuses a worktree a process still holds, so the
# relaunch waits for the first run's processes to leave it.
wait_cwd_free "$first_wt"
ml retire "$(field name)"
rec="$tmp/rec-wt-again"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind worker --scope wt-new --brief "$tmp/brief.md"
[ "$RC" = 0 ] && [ "$(launched_in "$rec")" = "$first_wt" ] \
  && ok "a relaunch reuses the worktree holding its branch when no live session runs there" \
  || fail "the relaunch exited $RC in '$(cat "$rec/cwd" 2>/dev/null)', not $first_wt: $ERR"
wait_done "$(field name)"

# A unit whose branch exists starts on that branch, with its work.
work=$(gitc commit-tree -p main -m 'unit work' "$(git -C "$repo" rev-parse 'main^{tree}')")
gitc branch planwright/demo/task-1 "$work"
rec="$tmp/rec-task-a"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind worker --scope demo:task-1 --brief "$tmp/brief.md"
task_wt=''
if [ "$RC" != 0 ]; then
  fail "a launch for a unit with an existing branch exited $RC: $ERR"
else
  task_wt=$(launched_in "$rec")
  task_name=$(field name)
  [ "$(git -C "$task_wt" rev-parse HEAD 2>/dev/null)" = "$work" ] \
    && [ "$(git -C "$task_wt" symbolic-ref HEAD 2>/dev/null)" = refs/heads/planwright/demo/task-1 ] \
    && ok "a launch for a unit whose branch exists starts on that branch" \
    || fail "the unit launch in '$task_wt' is not on planwright/demo/task-1 at its work"
  wait_done "$task_name"
fi
# marker_present <id> — a dispatch marker for demo task <id> is on disk.
marker_present() {
  mp_dirs=$(mc_env /bin/sh "$repo_root/scripts/orchestrate-marker-home.sh" read "$repo/specs/demo" 2>/dev/null)
  for mp_d in $mp_dirs; do
    [ -f "$mp_d/$1" ] && return 0
  done
  return 1
}
marker_present 1 && ok "a task placement records the unit's dispatch marker" \
  || fail "the task placement left no dispatch marker for demo task 1"
[ "$(field cwd)" = "$task_wt" ] && ok "the launch report names the worktree" \
  || fail "the launch report's cwd is '$(field cwd)', not $task_wt"

# The worktree holding the branch has a live session (its row is not
# retired): a second launch for the unit is refused, naming it.
rec="$tmp/rec-task-b"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind reviewer --scope demo:task-1 --brief "$tmp/brief.md"
if [ "$RC" = 3 ] && case $ERR in *"${task_name:-unset}"*) true ;; *) false ;; esac && no_session demo:task-1 reviewer; then
  ok "a worktree holding the branch with a live session refuses the launch, naming the session"
else
  fail "a launch into a worktree with a live session: exit $RC, $ERR"
fi

# A live process in the worktree counts as a live session too.
ml retire "${task_name:-unset}"
marker_present 1 && fail "retiring the unit's session left its dispatch marker" \
  || ok "retiring a task session clears its dispatch marker"
if [ -n "$task_wt" ] && [ -d /proc/self ]; then
  (cd "$task_wt" && exec sleep 60) &
  sleeper=$!
  n=0
  until [ "$(readlink "/proc/$sleeper/cwd" 2>/dev/null)" = "$task_wt" ] || [ "$n" -ge 50 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  SHIM_RECORD_DIR=$rec ml launch --program alpha --kind reviewer --scope demo:task-1 --brief "$tmp/brief.md"
  [ "$RC" = 3 ] && case $ERR in *"process "*"runs in $task_wt"*) true ;; *) false ;; esac && no_session demo:task-1 reviewer \
    && ok "a process running in the worktree holds it as a live session" \
    || fail "a launch beside a live process in the worktree: exit $RC, $ERR"
  kill "$sleeper" 2>/dev/null
  wait "$sleeper" 2>/dev/null
else
  ok "skip: no /proc to place a live process in the worktree"
fi
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind reviewer --scope demo:task-1 --brief "$tmp/brief.md"
[ "$RC" = 0 ] && [ "$(launched_in "$rec")" = "$task_wt" ] \
  && ok "a worktree holding the branch with no live session is reused" \
  || fail "the reuse launch exited $RC in '$(cat "$rec/cwd" 2>/dev/null)': $ERR"
wait_done "$(field name)"
marker_present 1 && ok "a reused task worktree is marked in flight again" \
  || fail "the reuse launch left no dispatch marker for demo task 1"

# Naming the primary checkout, and a worktree that cannot be created, are
# refused with no session started and no row.
ml launch --program alpha --kind worker --scope primary --brief "$tmp/brief.md" --cwd "$repo"
[ "$RC" = 4 ] && case $ERR in *"other than a primary checkout"*) true ;; *) false ;; esac && no_session primary worker \
  && ok "a launch naming the primary checkout is refused (exit $RC) with no session or row" \
  || fail "a launch into the primary checkout: exit $RC"
ml launch --program alpha --kind worker --scope nosuch:task-1 --brief "$tmp/brief.md"
[ "$RC" = 4 ] && case $ERR in *"could not be created"*) true ;; *) false ;; esac && no_session nosuch:task-1 worker \
  && ok "a launch whose worktree cannot be created is refused (exit $RC) with no session or row" \
  || fail "a launch with no creatable worktree: exit $RC"
mkdir -p "$tmp/plain-dir/sub"
if git -C "$tmp/plain-dir" rev-parse >/dev/null 2>&1; then
  ok "skip: the scratch directory sits inside a git checkout"
else
  ml launch --program alpha --kind worker --scope not-a-repo --repo "$tmp/plain-dir" --brief "$tmp/brief.md"
  [ "$RC" = 4 ] && case $ERR in *"in no repository"*) true ;; *) false ;; esac && no_session not-a-repo worker \
    && ok "a launch whose repository is not a git checkout is refused (exit 4)" \
    || fail "a launch outside a repository: exit $RC, $ERR"
  ml launch --program alpha --kind worker --scope plain-cwd --cwd "$tmp/plain-dir" --brief "$tmp/brief.md"
  [ "$RC" = 4 ] && case $ERR in *"other than a primary checkout"*) true ;; *) false ;; esac && no_session plain-cwd worker && ok "a named directory that is no worktree is refused (exit 4)" \
    || fail "a launch naming a plain directory: exit $RC"
fi
ml launch --program alpha --kind worker --scope primary-sub --cwd "$repo/specs" --brief "$tmp/brief.md"
[ "$RC" = 4 ] && case $ERR in *"other than a primary checkout"*) true ;; *) false ;; esac && no_session primary-sub worker && ok "a directory inside the primary checkout is refused (exit 4)" \
  || fail "a launch naming a primary subdirectory: exit $RC"

# Another worktree no live session uses is accepted as named.
gitc worktree add -q -b spare "$tmp/spare" main
rec="$tmp/rec-spare"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind ad-hoc --scope spare --brief "$tmp/brief.md" --cwd "$tmp/spare"
[ "$RC" = 0 ] && [ "$(launched_in "$rec")" = "$tmp/spare" ] \
  && ok "a launch naming another unused worktree starts there" \
  || fail "a launch naming an unused worktree exited $RC in '$(cat "$rec/cwd" 2>/dev/null)': $ERR"
wait_done "$(field name)"
ml launch --program alpha --kind reviewer --scope spare-2 --brief "$tmp/brief.md" --cwd "$tmp/spare"
spare_name=$(cd "$repo" && /bin/sh "$LAUNCH" name --program alpha --kind ad-hoc --scope spare)
[ "$RC" = 3 ] && case $ERR in *"session $spare_name"*) true ;; *) false ;; esac && no_session spare-2 reviewer \
  && ok "a named worktree a live session uses is refused, naming it" \
  || fail "a named worktree in use: exit $RC, $ERR"

# A tower starts in the caller's directory, with no worktree.
rec="$tmp/rec-tower-here"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind tower --scope tower-here --brief "$tmp/brief.md"
[ "$RC" = 0 ] && [ "$(launched_in "$rec")" = "$repo" ] && ok "a tower kind starts in the caller's directory" \
  || fail "the tower launch exited $RC in '$(cat "$rec/cwd" 2>/dev/null)': $ERR"
tower_brief=$(field brief)
wait_done "$(field name)"
ml launch --program alpha --kind tower --scope tower-repo --repo "$repo" --brief "$tmp/brief.md"
[ "$RC" = 2 ] && ok "a kind that starts where it is launched refuses --repo" || fail "a tower with --repo: exit $RC"

# A unit with no branch yet gets one off the default branch, and a worker
# scoped <spec>:task-<id> runs on that unit's branch.
rec="$tmp/rec-task-new"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind worker --scope demo:task-2 --brief "$tmp/brief.md"
if [ "$RC" = 0 ]; then
  tn_wt=$(launched_in "$rec")
  [ "$(git -C "$tn_wt" symbolic-ref HEAD 2>/dev/null)" = refs/heads/planwright/demo/task-2 ] \
    && [ "$(git -C "$tn_wt" rev-parse HEAD)" = "$(git -C "$repo" rev-parse main)" ] \
    && ok "a unit's scope with no branch yet starts a new unit branch off the default branch" \
    || fail "the demo:task-2 launch in '$tn_wt' is not a fresh planwright/demo/task-2"
  # shellcheck disable=SC2016 # literal backticks around the ids
  grep -qF 'PLANWRIGHT_STEP_UNIT_KIND=task' "$(field brief)" && grep -qF 'spec id `demo`, task id `2`' "$(field brief)" \
    && ok "a unit launch's cadence names its task unit" || fail "a unit launch's cadence is not the task unit's"
  wait_done "$(field name)"
else
  fail "the demo:task-2 launch exited $RC: $ERR"
fi

# The tmux rung starts a repository-changing kind in its worktree too.
ml launch --program alpha --kind worker --scope tmux-wt --brief "$tmp/brief.md" --backend tmux
if [ "$RC" = 0 ]; then
  tw_dir=$(field cwd)
  tw_handle=$(awk -F '\t' '$1 == "handle" { print $2 }' "$fleet/mission-control/sessions/$(field name)")
  case $tw_dir in
    "$repo/.claude/worktrees/"?*)
      [ "$(awk 'p { print; exit } $0 == "-c" { p = 1 }' "$tmp/tmux/argv-$tw_handle")" = "$tw_dir" ] \
        && ok "a tmux launch of a repository-changing kind starts in its worktree" \
        || fail "the tmux window was not started in $tw_dir: $(tr '\n' ' ' <"$tmp/tmux/argv-$tw_handle" 2>/dev/null)"
      ;;
    *) fail "the tmux worker launch reported '$tw_dir', not a worktree" ;;
  esac
else
  fail "the tmux worker launch exited $RC: $ERR"
fi

# A primary checkout on another branch: a new worktree still starts off the
# default branch, and the primary keeps its branch.
gitc checkout -q -b side
gitc commit -q --allow-empty -m side
rec="$tmp/rec-off-side"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind ad-hoc --scope off-side --brief "$tmp/brief.md"
[ "$RC" = 0 ] && [ "$(git -C "$(launched_in "$rec")" rev-parse HEAD)" = "$(git -C "$repo" rev-parse main)" ] \
  && [ "$(git -C "$repo" symbolic-ref HEAD)" = refs/heads/side ] \
  && ok "a new worktree starts off the default branch whatever the primary has checked out" \
  || fail "the launch beside a primary on another branch: exit $RC, HEAD $(git -C "$(cat "$rec/cwd" 2>/dev/null)" log --oneline -1 2>&1)"
wait_done "$(field name)"
gitc checkout -q main

# A unit whose branch the primary checkout itself has checked out is refused
# rather than started in the primary, with no session and no marker.
gitc checkout -q -b planwright/demo/task-3 main
ml launch --program alpha --kind worker --scope demo:task-3 --brief "$tmp/brief.md"
[ "$RC" = 4 ] && case $ERR in *"checked out in the primary checkout"*) true ;; *) false ;; esac \
  && no_session demo:task-3 worker && ! marker_present 3 \
  && ok "a unit whose branch the primary checkout holds is refused (exit 4) with no session or marker" \
  || fail "a launch for a unit checked out in the primary: exit $RC, $ERR"
gitc checkout -q main

# Usage refusals, each with no row: "<kind>|<scope>|<extra args>|<message>".
for case_ in "worker|usage-a|--repo relative/dir|absolute path" "tower|usage-b|--repo $repo|no --repo" \
  "worker|usage-c|--repo $repo --cwd $tmp/spare|neither --repo" "worker|demo:task-7|--cwd $tmp/spare|neither --repo nor a task scope" \
  "worker|demo:task-1.2.3||a task scope is" "worker|Demo:task-1||a task scope is" "ad-hoc|demo:task-x||a task scope is"; do
  IFS='|' read -r u_kind u_scope u_extra u_msg <<EOF
$case_
EOF
  # shellcheck disable=SC2086 # the extra arguments are a word list
  ml launch --program alpha --kind "$u_kind" --scope "$u_scope" $u_extra --brief "$tmp/brief.md"
  if [ "$RC" = 2 ] && case $ERR in *"$u_msg"*) true ;; *) false ;; esac && no_session "$u_scope" "$u_kind"; then
    ok "usage refusal: $u_kind $u_scope $u_extra (exit 2)"
  else
    fail "usage case '$case_' exited $RC: $ERR"
  fi
done

# A refusal after a task placement clears the marker the placement wrote.
cp "$tracked" "$tmp/tracked-marker.bak"
printf 'allocation_model_execution: nonsense\n' >>"$tracked"
ml launch --program alpha --kind worker --scope demo:task-5 --brief "$tmp/brief.md"
[ "$RC" = 4 ] && ! marker_present 5 && no_session demo:task-5 worker \
  && ok "a launch refused after its task placement leaves no dispatch marker" \
  || fail "the post-placement refusal: exit $RC, marker $(marker_present 5 && echo present || echo absent)"
cp "$tmp/tracked-marker.bak" "$tracked"

# The launcher's caller may work inside the worktree it names.
gitc worktree add -q -b inside "$tmp/inside" main
rec="$tmp/rec-inside"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ML_CD="$tmp/inside" ml launch --program alpha --kind ad-hoc --scope inside --cwd "$tmp/inside" --brief "$tmp/brief.md"
[ "$RC" = 0 ] && [ "$(launched_in "$rec")" = "$tmp/inside" ] \
  && ok "a caller working inside the named worktree is not a live session there" \
  || fail "a launch from inside its worktree exited $RC: $ERR"
wait_done "$(field name)"

# ---------------------------------------------------------------------------
# REQ-D1.11: a repository-changing brief carries the cadence; a skill command
# carries its own.
# ---------------------------------------------------------------------------
ml name --program alpha --kind worker --scope wt-new
wt_brief="$fleet/mission-control/launch/$OUT/brief.md"
if grep -qx '## Verification cadence' "$wt_brief" && grep -qF 'scripts/step-run.sh audit --through post-pr' "$wt_brief" \
  && grep -qF "*Points*" "$wt_brief"; then
  ok "a repository-changing brief carries the cadence section with the audit command"
else
  fail "the worker brief lacks the cadence section: $(cat "$wt_brief" 2>/dev/null)"
fi
[ -f "$tower_brief" ] && grep -qx '## Verification cadence' "$tower_brief" && fail "a tower brief carries the cadence section" \
  || ok "a kind that changes no repository gets no cadence section"
printf '%s\n' '/planwright:execute-task 1 demo' >"$tmp/unit-skill-brief.md"
ml retire "$(cd "$repo" && /bin/sh "$LAUNCH" name --program alpha --kind reviewer --scope demo:task-1)"
rec="$tmp/rec-unit-skill"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind reviewer --scope demo:task-1 --brief "$tmp/unit-skill-brief.md"
if [ "$RC" = 0 ]; then
  grep -qx '## Verification cadence' "$(field brief)" && fail "a brief that is a skill command carries the cadence section" \
    || ok "a brief that is a skill command carries no cadence section"
  wait_done "$(field name)"
else
  fail "the skill-command launch exited $RC: $ERR"
fi

# The skill's kickoff relay leaves the directory to the launcher.
relay=$(awk '/^- `relay` —/ { on = 1 } on && /^- `manual`/ { exit } on { print }' "$repo_root/skills/mission-control/SKILL.md")
if [ -n "$relay" ] && printf '%s\n' "$relay" | grep -qF -- '--repo' && ! printf '%s\n' "$relay" | grep -qw -- 'cwd'; then
  ok "the skill's kickoff relay passes the repository, not a start directory"
else
  fail "the kickoff relay names a directory: $relay"
fi

# ---------------------------------------------------------------------------
# REQ-L1.7: a host-wide bound on live sessions across every program's rows in
# the shared registry (fleet_host_max_live_workers), mission-control sessions
# excluded, the operator-asked override kept, a remote host's rows never ours.
# ---------------------------------------------------------------------------
fleet="$tmp/fleet-cap"
mkdir -p "$fleet/mission-control/sessions"
capreg="$fleet/mission-control/sessions"
# seed_row <name> <program> <kind> — a registered session of another program.
seed_row() {
  printf '%s\n' "format${TAB}1" "name${TAB}$1" "state${TAB}launched" "token${TAB}seed-$1" "pid${TAB}1" \
    "program${TAB}$2" "owner${TAB}mission-control:$2" "kind${TAB}$3" "scope${TAB}seed" "backend${TAB}stream-json" \
    "handle${TAB}$1" "profile${TAB}worker" "tier${TAB}-" "brief${TAB}-" "cwd${TAB}-" "task${TAB}-" "primary${TAB}-" \
    "marker${TAB}-" "launched${TAB}1" >"$capreg/$1"
}
seed_row mc-beta-worker-0000000001 beta worker
seed_row mc-gamma-reviewer-0000000002 gamma reviewer
seed_row mc-beta-mission-control-0000000003 beta mission-control
set_cap() { printf 'fleet_host_max_live_workers: %s\n' "$1" >"$tmp/absent.yml"; }
ml_cap() { ml "$@"; }
cap_launch() { # <scope> [extra launch args...]
  cl_scope=$1
  shift
  rec="$tmp/rec-cap-$cl_scope"
  mkdir -p "$rec"
  SHIM_RECORD_DIR=$rec ml_cap launch --program alpha --kind worker --scope "spec:cap-$cl_scope" --brief "$tmp/brief.md" "$@"
}

set_cap 2
cap_launch full
cap_name=$(cd "$repo" && /bin/sh "$LAUNCH" name --program alpha --kind worker --scope spec:cap-full)
if [ "$RC" = 4 ] && [ ! -e "$capreg/$cap_name" ]; then
  ok "a launch past the host-wide bound is refused (exit 4) and leaves no row"
else
  fail "a launch past the host bound exited $RC with row present=$([ -e "$capreg/$cap_name" ] && echo yes || echo no): $ERR"
fi
case $ERR in
  *"beta 1"*"gamma 1"* | *"gamma 1"*"beta 1"*) ok "the refusal names each program and how many it holds" ;;
  *) fail "the refusal does not name the programs and counts: $ERR" ;;
esac
case $ERR in
  *fleet_host_max_live_workers*"--operator-asked"*) ok "the refusal names the knob and the operator-asked path" ;;
  *) fail "the refusal does not name the knob and the override: $ERR" ;;
esac
[ ! -e "$fleet/mission-control/launch/$cap_name" ] && ok "a refused launch leaves no launch directory" \
  || fail "a refused launch left its launch directory"

set_cap 3
cap_launch room
if [ "$RC" = 0 ]; then
  ok "a mission-control row is not counted against the bound"
  wait_done "$(field name)"
else
  fail "two live workers and a mission-control row refused a launch under a bound of 3: $ERR"
fi

# Three live workers now; the bound of 3 holds the next one, and an
# operator-asked launch goes past it with the bypass recorded first.
cap_launch held
[ "$RC" = 4 ] && ok "the bound counts the launched session too" || fail "a fourth worker under a bound of 3 exited $RC: $ERR"
cap_launch asked --operator-asked
if [ "$RC" = 0 ]; then
  ok "an operator-asked launch goes past the host-wide bound"
  wait_done "$(field name)"
  asked_name=$(field name)
  ml_out=$(cd "$repo" && env PLANWRIGHT_FLEET_STATE_DIR="$fleet" PLANWRIGHT_ROOT="$core" PLANWRIGHT_REPO_ROOT="$repo" HOME="$fixhome" \
    /bin/bash "$repo_root/scripts/mc-event.sh" list --program alpha 2>/dev/null)
  case $ml_out in
    *"${TAB}host-cap-bypass${TAB}$asked_name${TAB}"*) ok "the bypass is recorded as a host-cap-bypass event" ;;
    *) fail "no host-cap-bypass event for $asked_name: $ml_out" ;;
  esac
else
  fail "the operator-asked launch past the host bound exited $RC: $ERR"
fi

# A mission-control launch is never held by the bound.
SHIM_RECORD_DIR="$tmp/rec-cap-mc" ml_cap launch --program alpha --kind mission-control --scope cap-mc --brief "$tmp/brief.md"
[ "$RC" = 0 ] && ok "a mission-control launch is not held by the host-wide bound" || fail "a mission-control launch under the bound exited $RC: $ERR"
wait_done "$(field name)"

# A reservation made after this launch is not counted against it, so two
# concurrent launches near the bound admit the first rather than refusing both.
seed_row mc-delta-worker-0000000009 delta worker
sed "s/^launched${TAB}.*/launched${TAB}99999999999/" "$capreg/mc-delta-worker-0000000009" >"$capreg/mc-delta-worker-0000000009.tmp.sed" \
  && mv "$capreg/mc-delta-worker-0000000009.tmp.sed" "$capreg/mc-delta-worker-0000000009"
set_cap 5
cap_launch before-later
[ "$RC" = 0 ] && ok "a later reservation is not counted against an earlier launch" || fail "a later reservation held an earlier launch: $ERR"
wait_done "$(field name)"
rm -f "$capreg/mc-delta-worker-0000000009"

# An operator-asked launch with room records no bypass.
set_cap off
cap_launch asked-room --operator-asked
room_name=$(field name)
wait_done "$room_name"
ml_out=$(cd "$repo" && env PLANWRIGHT_FLEET_STATE_DIR="$fleet" PLANWRIGHT_ROOT="$core" PLANWRIGHT_REPO_ROOT="$repo" HOME="$fixhome" \
  /bin/bash "$repo_root/scripts/mc-event.sh" list --program alpha 2>/dev/null)
case $ml_out in
  *"${TAB}host-cap-bypass${TAB}$room_name${TAB}"*) fail "an operator-asked launch with room recorded a bypass" ;;
  *) ok "an operator-asked launch with room records no bypass" ;;
esac

# off: no bound.
set_cap off
cap_launch unlimited
[ "$RC" = 0 ] && ok "off lifts the host-wide bound" || fail "off still held a launch: $ERR"
wait_done "$(field name)"

# The shipped default bound holds with no machine-local setting: the registry
# holds the default six by now.
rm -f "$tmp/absent.yml"
sed "/^fleet_host_max_live_workers:/d" "$tracked" >"$tracked.sed" && mv "$tracked.sed" "$tracked"
cap_launch default-held
[ "$RC" = 4 ] && ok "the shipped default bound holds a launch at six sessions" || fail "the shipped default let a launch through (exit $RC)"

# A malformed value is a refusal, never an unbounded launch.
set_cap lots
cap_launch malformed
[ "$RC" -ne 0 ] && ok "a malformed bound refuses the launch" || fail "a malformed bound let a launch through"

# ---------------------------------------------------------------------------
# A session that is only waiting (on the operator, on CI, on a ready flip)
# stops counting toward the host-wide bound, its state recorded on its row,
# and the count says how many slots work holds versus waits. A bound held by
# working sessions still refuses.
# ---------------------------------------------------------------------------
fleet="$tmp/fleet-wait"
mkdir -p "$fleet/mission-control/sessions"
capreg="$fleet/mission-control/sessions"
set_cap 2
seed_row mc-beta-worker-0000000011 beta worker
seed_row mc-gamma-worker-0000000012 gamma worker
w1=mc-beta-worker-0000000011
w2=mc-gamma-worker-0000000012

cap_launch work-full
if [ "$RC" = 4 ]; then
  ok "a bound held by two working sessions refuses a launch"
else
  fail "two working sessions under a bound of 2 exited $RC: $ERR"
fi
case $ERR in
  *"2 working"*"0 waiting"*) ok "the refusal says how many slots work holds and how many waits hold" ;;
  *) fail "the refusal does not split working from waiting: $ERR" ;;
esac

ml wait "$w1" --on operator
[ "$RC" = 0 ] && ok "a worker is marked waiting on the operator" || fail "wait exited $RC: $ERR"
case $(cat "$capreg/$w1") in
  *"waiting${TAB}operator"*) ok "the wait is recorded on the registry row" ;;
  *) fail "the row records no wait: $(cat "$capreg/$w1")" ;;
esac
cap_launch one-waiting
if [ "$RC" = 0 ]; then
  ok "a waiting worker does not hold a slot: a bound of 2 with one working, one waiting admits a launch"
  leak1=$(field name)
  wait_done "$leak1"
else
  fail "a waiting worker still held the bound: $ERR"
fi

ml wait "$w2" --on ci
[ "$RC" = 0 ] && ok "a worker is marked waiting on CI" || fail "wait --on ci exited $RC: $ERR"
cap_launch all-waiting
if [ "$RC" = 0 ]; then
  ok "a full bound of waiting workers no longer refuses a launch"
  leak2=$(field name)
  wait_done "$leak2"
else
  fail "a bound full of waiting workers refused a launch: $ERR"
fi

ml bound
case $OUT in
  *"bound${TAB}2${TAB}"*) ok "bound reports the limit" ;;
  *) fail "bound does not report the limit: $OUT" ;;
esac
bound_row=$(printf '%s\n' "$OUT" | awk -F '\t' '$1 == "bound" { print $3 "/" $4 }')
case $bound_row in
  2/2) ok "bound reports working and waiting slots (the two launched sessions work, the two seeds wait)" ;;
  *) fail "bound reports working/waiting as '$bound_row': $OUT" ;;
esac

ml wait "$w1" --on ready-flip
[ "$RC" = 0 ] && ok "marking a waiting worker again updates its reason" || fail "a second wait exited $RC: $ERR"
case $(cat "$capreg/$w1") in
  *"waiting${TAB}ready-flip"*) ok "the second reason replaces the first" ;;
  *) fail "the reason was not replaced: $(cat "$capreg/$w1")" ;;
esac
[ "$(grep -c "^waiting${TAB}" "$capreg/$w1")" = 1 ] && ok "a row holds one waiting field" || fail "a row holds several waiting fields"

ml unwait "$w1"
[ "$RC" = 0 ] && ok "unwait returns a worker to the count" || fail "unwait exited $RC: $ERR"
grep -q "^waiting${TAB}" "$capreg/$w1" && fail "unwait left the waiting field" || ok "unwait clears the waiting field"
ml retire "$leak1"
ml retire "$leak2"
ml bound
case $OUT in
  *"bound${TAB}2${TAB}1${TAB}1"*) ok "with the launched sessions retired one seed works and one waits" ;;
  *) fail "bound after the retires: $OUT" ;;
esac
ml wait "$w1" --on ready-flip
ml bound
case $OUT in
  *"bound${TAB}2${TAB}0${TAB}2"*) ok "both seeds waiting leaves no working slot" ;;
  *) fail "bound with both seeds waiting: $OUT" ;;
esac
ml unwait "$w2"
cap_launch half-resumed
if [ "$RC" = 0 ]; then
  ok "one resumed worker leaves room under a bound of 2"
  leak3=$(field name)
  wait_done "$leak3"
  ml retire "$leak3"
else
  fail "one resumed worker held a bound of 2: $ERR"
fi
ml unwait "$w1"
ml wait "$w1" --on ci --extra
[ "$RC" = 2 ] && ok "wait refuses extra arguments" || fail "wait with an extra argument exited $RC"
ml unwait "$w1"
cap_launch work-again
[ "$RC" = 4 ] && ok "a bound held again by two resumed workers refuses a launch" || fail "resumed workers did not hold the bound (exit $RC): $ERR"
seed_row mc-beta-worker-0000000014 beta worker
sed "s/^state${TAB}.*/state${TAB}launching/" "$capreg/mc-beta-worker-0000000014" >"$capreg/mc-beta-worker-0000000014.tmp.sed" \
  && mv "$capreg/mc-beta-worker-0000000014.tmp.sed" "$capreg/mc-beta-worker-0000000014"
ml wait mc-beta-worker-0000000014 --on ci
[ "$RC" = 4 ] && ok "a session whose launch is not complete is never marked waiting" || fail "a launching row was marked waiting (exit $RC)"

ml wait mc-nobody-worker-0000000099 --on ci
[ "$RC" = 3 ] && ok "wait on an unregistered session exits 3" || fail "wait on an unknown session exited $RC: $ERR"
ml wait "$w1" --on lunch
[ "$RC" = 2 ] && ok "wait refuses an unknown reason" || fail "wait accepted an unknown reason (exit $RC)"
ml wait "$w1"
[ "$RC" = 2 ] && ok "wait requires a reason" || fail "wait with no reason exited $RC"
seed_row mc-beta-mission-control-0000000013 beta mission-control
ml wait mc-beta-mission-control-0000000013 --on operator
[ "$RC" = 4 ] && ok "a mission-control session is never marked waiting" || fail "a mission-control row was marked waiting (exit $RC)"
ml unwait mc-beta-mission-control-0000000013
[ "$RC" = 4 ] && ok "a mission-control session is never unwaited either" || fail "unwait on a mission-control row exited $RC"
ml bound extra
[ "$RC" = 2 ] && ok "bound takes no arguments" || fail "bound with an argument exited $RC"
ml unwait mc-nobody-worker-0000000099
[ "$RC" = 3 ] && ok "unwait on an unregistered session exits 3" || fail "unwait on an unknown session exited $RC"
fleet="$tmp/fleet"

# A session on another host (fleet-remote.sh) lives in that host's registry,
# so the near side never reads this host's rows for it.
if grep -q 'mission-control/sessions\|fleet_host_max_live_workers' "$repo_root/scripts/fleet-remote.sh"; then
  fail "fleet-remote.sh consults this host's registry or bound"
else
  ok "a remote launch is counted on its own host, never against this host's bound"
fi

# ---------------------------------------------------------------------------
# REQ-D1.16: a live session moves between programs; routing follows the row.
# ---------------------------------------------------------------------------
set_cap off
grep -v '^mission_control_programs:' "$tracked" >"$tracked.new" && mv "$tracked.new" "$tracked"
cat >>"$tracked" <<EOF
mission_control_programs: [alpha, beta]
program_beta_repositories: [$repo]
program_beta_spec_root: $repo/specs
program_beta_home: $tmp/mc-home/beta
EOF
REG="$fleet/mission-control/sessions"
rp_field() { awk -F '\t' -v k="$2" '$1 == k { print $2; exit }' "$1"; }
rp_row() { # rp_row <name> <program> <kind> <state> — a registry row with pid, cwd and task fields
  mkdir -p "$REG"
  printf 'format\t1\nname\t%s\nstate\t%s\ntoken\ttok-%s\npid\t4242\nprogram\t%s\nowner\tmission-control:%s\nkind\t%s\nscope\tfold-1\nbackend\tstream-json\nhandle\t%s\nprofile\tp.json\ntier\topus\nbrief\t/b.md\ncwd\t/wt/one\ntask\t-\nprimary\t-\nmarker\t-\nlaunched\t100\n' \
    "$1" "$4" "$1" "$2" "$2" "$3" "$1" >"$REG/$1"
}
rp_decide() { # rp_decide <program> <act> <target> — log a decision, print its id
  mc_run mc-kb.sh append decisions --program "$1" --subject "operator order" --act "$2" --target "$3" --grounds "operator: fold it" --no-reversal
  printf '%s\n' "$OUT" | tail -n 1
}
rp_events() { mc_run mc-event.sh list --program "$1"; }
rp_pend() { # rp_pend <worker> <epoch> — a pending request under live pids
  mkdir -p "$fleet/streamjson/$1"
  printf 'cccc3333-bbbb-cccc-dddd-eeee00000001\tpermission\t%s\tpending\n' "$2" >"$fleet/streamjson/$1/journal"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/supervisor.pid"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/worker.pid"
  printf 'spec:fold-1\n' >"$fleet/streamjson/$1/scope"
}
rp_watch() { # rp_watch <program> <now>
  OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM="$1" PLANWRIGHT_STREAMJSON_PENDING_AGE=900 \
    /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now "$2" 2>/dev/null)
}

fold_name=mc-alpha-worker-1000000001
rp_row "$fold_name" alpha worker launched
rp_row mc-alpha-tower-1000000002 alpha tower launched
rp_row mc-alpha-mission-control-1000000003 alpha mission-control launched
rp_row mc-alpha-worker-1000000004 alpha worker launching
cp "$repo_root/config/duties.yaml" "$core/config/duties.yaml"
for p in alpha beta; do
  mc_run mc-kb.sh init --program "$p"
  [ "$RC" = 0 ] || fail "fixture: kb init for $p: $ERR"
done
fold_id=$(rp_decide beta fold-in-order alpha)
yes_id=$(rp_decide beta reparent-yes "$fold_name")
[ -n "$fold_id" ] && [ -n "$yes_id" ] || fail "fixture: the decisions were not logged ($fold_id / $yes_id)"
before=$(cat "$REG/$fold_name")

ml reparent
[ "$RC" = 2 ] && ok "reparent with no arguments is a usage error" || fail "bare reparent exited $RC"
ml reparent "$fold_name" --program beta
[ "$RC" = 2 ] && ok "a move with no --authority is refused (exit 2)" || fail "a move without authority exited $RC"
[ "$(cat "$REG/$fold_name")" = "$before" ] && ok "and the row is unchanged" || fail "the no-authority refusal changed the row"
ml reparent "$fold_name" --program beta --authority decisions-209901-1
[ "$RC" = 4 ] && ok "an authority naming no decision is refused (exit 4)" || fail "an unknown authority exited $RC"
ml reparent mc-alpha-worker-9999999999 --program beta --authority "$fold_id"
[ "$RC" = 3 ] && ok "an unknown session is refused (exit 3)" || fail "an unknown session exited $RC"
ml reparent "$fold_name" --program nosuch --authority "$fold_id"
[ "$RC" = 4 ] && ok "an unknown program is refused (exit 4)" || fail "an unknown program exited $RC"
ml reparent "$fold_name" --program alpha --authority "$fold_id"
[ "$RC" = 4 ] && ok "the same program is refused (exit 4)" || fail "the same program exited $RC"
ml reparent mc-alpha-mission-control-1000000003 --program beta --authority "$fold_id"
[ "$RC" = 4 ] && ok "a mission-control session is refused (exit 4)" || fail "a mission-control session exited $RC"
ml reparent mc-alpha-worker-1000000004 --program beta --authority "$fold_id"
[ "$RC" = 4 ] && ok "a launch still in flight is refused (exit 4)" || fail "a launching row exited $RC"
ml reparent mc-alpha-tower-1000000002 --program beta --authority "$yes_id"
[ "$RC" = 4 ] && ok "a yes for one session does not move another (exit 4)" || fail "a yes covered another session: exit $RC"
[ "$(cat "$REG/$fold_name")" = "$before" ] && ok "none of the refusals changed the row" || fail "a refusal changed the row"

# A registry the launcher cannot rewrite changes nothing.
if [ "$(id -u)" != 0 ]; then
  chmod 500 "$REG"
  ml reparent "$fold_name" --program beta --authority "$fold_id"
  chmod 700 "$REG"
  if [ "$RC" = 2 ] && [ "$(cat "$REG/$fold_name")" = "$before" ]; then
    ok "a row that cannot be rewritten refuses and changes nothing (exit 2)"
  else
    fail "an unwritable registry: exit $RC"
  fi
fi

# The move itself, authorised by the fold-in order.
ml reparent "$fold_name" --program beta --authority "$fold_id"
[ "$RC" = 0 ] && ok "a fold-in order moves a live session" || fail "the move exited $RC: $ERR"
case $OUT in
  "reparent${TAB}$fold_name${TAB}moved${TAB}alpha${TAB}beta"*) ok "the verb says what moved, from and to" ;;
  *) fail "the move's output: $OUT" ;;
esac
if [ "$(rp_field "$REG/$fold_name" program)" = beta ] && [ "$(rp_field "$REG/$fold_name" owner)" = mission-control:beta ]; then
  ok "the row's program and owner are the destination's"
else
  fail "the row after the move: $(cat "$REG/$fold_name")"
fi
grep -v -e "^program${TAB}" -e "^owner${TAB}" "$REG/$fold_name" >"$tmp/after.rows"
printf '%s\n' "$before" | grep -v -e "^program${TAB}" -e "^owner${TAB}" >"$tmp/before.rows"
cmp -s "$tmp/before.rows" "$tmp/after.rows" && ok "pid, cwd, branch and every other field are untouched" || fail "a field beyond program and owner changed"
ml list
case $OUT in *"$fold_name${TAB}beta${TAB}worker"*) ok "the destination's list shows the session" ;; *) fail "list after the move: $OUT" ;; esac
case $OUT in *"$fold_name${TAB}alpha"*) fail "the source's list still shows it" ;; *) ok "and the source's list does not" ;; esac
for p in alpha beta; do
  rp_events "$p"
  case $OUT in
    *"session-reparented${TAB}$fold_name${TAB}"*) ok "the move is an event in $p's log" ;;
    *) fail "no session-reparented event for $p: $OUT" ;;
  esac
done
mc_run mc-kb.sh query undo --program beta --subject "$fold_name"
case $OUT in
  *reparent*"$fold_name"*alpha*) ok "an undo entry names the source in the destination's log" ;;
  *) fail "the undo entry: $OUT" ;;
esac
undo_id=$(printf '%s\n' "$OUT" | awk -F '\t' '$4 == "reparent" { print $1; exit }')

# A prompt raised after the move reaches beta's events and not alpha's.
rp_pend "$fold_name" 9000
rp_watch alpha 9010
case $OUT in *"pending-prompt${TAB}$fold_name"*) fail "the source announced the moved session's prompt" ;; *) ok "the source program does not announce a prompt raised after the move" ;; esac
rp_watch beta 9010
case $OUT in *"announced${TAB}pending-prompt${TAB}$fold_name"*) ok "the destination announces it" ;; *) fail "the destination missed the prompt: $OUT" ;; esac
rp_events beta
case $OUT in *"pending-prompt${TAB}$fold_name"*) ok "the prompt is in the destination's events" ;; *) fail "not in beta's events: $OUT" ;; esac
rp_events alpha
case $OUT in *"pending-prompt${TAB}$fold_name"*) fail "the prompt is in the source's events" ;; *) ok "and not in the source's" ;; esac
rm -rf "$fleet/streamjson/$fold_name"

# One order covers every live session of the folded program.
ml reparent mc-alpha-tower-1000000002 --program beta --authority "$fold_id"
[ "$RC" = 0 ] && ok "one fold-in order covers a second session of the folded program" || fail "the second session exited $RC: $ERR"

# A yes covers its own session only.
w5=mc-alpha-worker-1000000005
rp_row "$w5" alpha worker launched
w5_before=$(cat "$REG/$w5")
ml reparent "$w5" --program beta --authority "$yes_id"
[ "$RC" = 4 ] && ok "a yes naming another session does not cover this one" || fail "a yes for another session exited $RC"

# An order for another program, a record only in the source's log, a malformed
# id and --undo with --authority each refuse and leave the row alone.
other_id=$(rp_decide beta fold-in-order other)
ml reparent "$w5" --program beta --authority "$other_id"
[ "$RC" = 4 ] && ok "a fold-in order for another program does not cover this one" || fail "an order for another program exited $RC"
# Ids count per program's log, so log past the destination's last id to get one beta's log lacks.
for pad_n in 1 2 3; do rp_decide alpha reparent-yes "pad-$pad_n" >"$tmp/pad.$pad_n"; done
src_id=$(rp_decide alpha fold-in-order alpha)
mc_run mc-kb.sh entries decisions --program beta
case $OUT in *"$src_id"*) fail "fixture: $src_id is also an id in beta's log" ;; esac
ml reparent "$w5" --program beta --authority "$src_id"
[ "$RC" = 4 ] && ok "an order recorded only in the source's log does not authorise a move into beta" || fail "a source-log order exited $RC"
ml reparent "$w5" --program beta --authority 'Bad_Id'
[ "$RC" = 2 ] && ok "a malformed authority id is refused (exit 2)" || fail "a malformed authority exited $RC"
ml reparent "$w5" --program beta --undo --authority "$fold_id"
[ "$RC" = 2 ] && ok "--undo together with --authority is refused (exit 2)" || fail "--undo with --authority exited $RC"
ml reparent "$w5" --program beta --undo
[ "$RC" = 4 ] && ok "--undo with no recorded move is refused (exit 4)" || fail "an undo with no move exited $RC"
[ "$(cat "$REG/$w5")" = "$w5_before" ] && ok "none of those changed the row" || fail "a refusal changed $w5"

yes5=$(rp_decide beta reparent-yes "$w5")
ml reparent "$w5" --program beta --authority "$yes5"
[ "$RC" = 0 ] && ok "a yes naming the session moves it" || fail "a yes for its own session exited $RC: $ERR"
ml reparent "$w5" --program alpha --undo
if [ "$RC" = 0 ] && [ "$(rp_field "$REG/$w5" program)" = alpha ]; then
  ok "a hand-run undo restores the source with no authority"
else
  fail "the hand-run undo: exit $RC, $ERR"
fi
mc_run mc-kb.sh query undo --program alpha --subject "$w5"
case $OUT in *reparent*) fail "the reversal logged an undo entry of its own: $OUT" ;; *) ok "a reversal logs no undo entry, so it cannot be reversed back" ;; esac
ml reparent "$w5" --program beta --undo
[ "$RC" = 4 ] && ok "no move out of beta is recorded in alpha, so the session cannot be undone back to beta" || fail "an undo back to beta exited $RC"

# Reversal through the undo entry needs no authority and restores the source.
mc_run mc-kb.sh revert --program beta "$undo_id"
if [ "$RC" = 0 ] && [ "$(rp_field "$REG/$fold_name" program)" = alpha ] && [ "$(rp_field "$REG/$fold_name" owner)" = mission-control:alpha ]; then
  ok "the undo entry's reversal restores the source with no authority"
else
  fail "the reversal: exit $RC, $ERR; row: $(cat "$REG/$fold_name")"
fi
ml reparent "$fold_name" --program alpha --undo
[ "$RC" = 4 ] && ok "the undo of a move is refused once the session is back in the source" || fail "a replayed undo exited $RC"

# Retirement works from the destination: a real launched session.
SHIM_RECORD_DIR="$tmp/rec-rp" ml launch --program alpha --kind tower --scope fold-live --brief "$tmp/brief.md" --cwd "$repo"
[ "$RC" = 0 ] || fail "fixture: the live launch exited $RC: $ERR"
live=$(field name)
wait_done "$live"
live_id=$(rp_decide beta reparent-yes "$live")
ml reparent "$live" --program beta --authority "$live_id"
[ "$RC" = 0 ] && ok "a launched session moves" || fail "moving a launched session exited $RC: $ERR"
ml retire "$live"
if [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^retire${TAB}$live${TAB}released"; then
  ok "retire works from the destination"
else
  fail "retire after the move: exit $RC, $OUT $ERR"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mission-control-launch tests passed"
