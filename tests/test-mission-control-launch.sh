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
# The tmux, name, refusal and posture cases, the retire cases, the worktree
# and cadence cases and the host-bound and reparent cases live in
# tests/test-mission-control-launch-tmux.sh,
# tests/test-mission-control-launch-retire.sh,
# tests/test-mission-control-launch-worktrees.sh and
# tests/test-mission-control-launch-host.sh so each file fits the per-file
# test-time budget; the shared fixture is tests/lib/mc-launch-fixture.sh.
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
# shellcheck source=tests/lib/mc-launch-fixture.sh
. "$here/lib/mc-launch-fixture.sh"

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

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mission-control-launch tests passed"
