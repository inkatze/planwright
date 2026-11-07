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
    -u PLANWRIGHT_TOWER_ID -u PLANWRIGHT_TOWER_SESSION_ID -u PLANWRIGHT_TOWER_PID \
    PATH="$tmp/bin:$PATH" PLANWRIGHT_ROOT="$core" PLANWRIGHT_REPO_ROOT="${ML_REPO_ROOT-$repo}" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" PLANWRIGHT_LOCAL_CONFIG="$tmp/absent.yml" \
    CLAUDE_DIR="$tmp/claude" HOME="$fixhome" PLANWRIGHT_FLEET_STATE_DIR="$fleet" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT=off \
    TMUX_PANE="${ML_TMUX_PANE:-}" \
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
      # Each Bash call is a fresh shell, so an exported context is lost by the
      # next call; the brief asks for the one-command prefix form instead.
      # shellcheck disable=SC2016 # literal backticks delimit the script names
      grep -qF 'literal assignments in front of each' "$composed_brief" \
        && grep -qF '`step-run.sh` and `resolve-steps.sh` call' "$composed_brief" \
        && ok "[$kind] the cadence carries the step context as a same-command prefix" \
        || fail "[$kind] the cadence lacks the same-command step-context prefix: $(cat "$composed_brief")"
      grep -qi -e 'export the step context' -e 'export PLANWRIGHT_STEP_' "$composed_brief" \
        && fail "[$kind] the cadence still asks for an exported step context: $(cat "$composed_brief")" \
        || ok "[$kind] the cadence asks for no exported step context"
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

# No item handed back names a pane, window or attach hint.
ml launch --program alpha --kind ad-hoc --scope pane-check --brief "$tmp/brief.md" --backend tmux
case $OUT in
  *attach* | *observe* | *capture-pane* | *'@'[0-9]*) fail "the launch report names a pane or window: $OUT" ;;
  *) ok "the launch report names no pane, window or attach hint" ;;
esac
pane_name=$(field name)
pane_handle=$(awk -F "$TAB" '$1 == "handle" { print $2; exit }' "$fleet/mission-control/sessions/$pane_name")
grep -q 'PLANWRIGHT_MC_TOKEN=' "$tmp/tmux/argv-$pane_handle" && fail "a tmux ad-hoc session was handed a mission-control token" \
  || ok "a tmux session of another kind holds no mission-control token"
ml launch --program alpha --kind mission-control --scope tmux-token --brief "$tmp/brief.md" --backend tmux
[ "$RC" = 0 ] || fail "the tmux mission-control launch exited $RC: $ERR"
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

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mission-control-launch tests passed"
