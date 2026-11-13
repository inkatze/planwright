#!/bin/bash
# Tests for scripts/mission-control-launch.sh — the one launcher for every
# session kind and its retire verb (mission-control REQ-D1.1, REQ-B1.4,
# REQ-G1.1, REQ-M1.7, REQ-A1.4; the split files below carry the rest).
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

# ---------------------------------------------------------------------------
# REQ-D1.12: adopt registers a live session the launcher did not start, on
# positive liveness evidence, and retire treats an operator's own session
# as the operator's to end.
# ---------------------------------------------------------------------------
sleep 600 &
adopt_live=$!
sleep 600 &
adopt_live2=$!
sh -c 'exit 0' &
adopt_dead=$!
wait "$adopt_dead"
areg="$fleet/mission-control/sessions"
mksj() { # mksj <worker> <pid>: a stream-json state directory holding the pid
  mkdir -p "$fleet/streamjson/$1"
  printf '%s\n' "$2" >"$fleet/streamjson/$1/worker.pid"
}
reg_count() {
  rc_n=0
  for rc_f in "$areg"/mc-*; do
    [ -e "$rc_f" ] && rc_n=$((rc_n + 1))
  done
  printf '%s\n' "$rc_n"
}
row_field() { awk -F '\t' -v k="$2" '$1 == k { print substr($0, length(k) + 2); exit }' "$areg/$1"; }
adopt_events() { (mc_env /bin/bash "$repo_root/scripts/mc-event.sh" list --program alpha 2>/dev/null); }
adopted_name() { printf '%s\n' "$OUT" | awk -F '\t' '$1 == "adopt" { print $2 }'; }

mksj w-dead "$adopt_dead"
before=$(reg_count)
ml adopt --program alpha --handle stream-json:w-dead --kind worker --scope adopt-dead
[ "$RC" = 4 ] && [ "$(reg_count)" = "$before" ] && ok "adopting a dead pid is refused with nothing registered" \
  || fail "adopting a dead pid exited $RC or registered a row: $ERR"
case $ERR in *"not running"*) ok "the dead-pid refusal says the process is not running" ;; *) fail "the dead-pid refusal does not say why: $ERR" ;; esac

ml adopt --program alpha --handle stream-json:w-nope --kind worker --scope adopt-nope
[ "$RC" = 4 ] && [ "$(reg_count)" = "$before" ] && ok "adopting an unknown stream-json handle is refused with nothing registered" \
  || fail "adopting an unknown handle exited $RC: $ERR"
ml adopt --program alpha --handle tmux:@77 --kind worker --scope adopt-nowin
[ "$RC" = 4 ] && [ "$(reg_count)" = "$before" ] && ok "adopting an unknown tmux window is refused with nothing registered" \
  || fail "adopting an unknown window exited $RC: $ERR"
mkdir -p "$fleet/streamjson/w-nopid"
ml adopt --program alpha --handle stream-json:w-nopid --kind worker --scope adopt-nopid
[ "$RC" = 4 ] && [ "$(reg_count)" = "$before" ] && ok "a session with no resolvable pid is refused" \
  || fail "adopting a session with no pid exited $RC: $ERR"
ml adopt --program alpha --handle stream-json:w-dead --kind mission-control --scope adopt-mc
[ "$RC" = 4 ] && ok "a mission-control session is never adopted" || fail "adopting a mission control exited $RC"
ml adopt --program alpha --handle 'nonsense' --kind worker --scope adopt-bad
[ "$RC" = 2 ] && ok "a handle that is not <backend>:<id> is a usage error" || fail "a malformed handle exited $RC"
ml adopt --program alpha --handle stream-json:w-dead --kind worker
[ "$RC" = 2 ] && ok "adopt without a scope is a usage error" || fail "adopt without a scope exited $RC"

mksj w-ok "$adopt_live"
ml adopt --program alpha --handle stream-json:w-ok --kind worker --scope adopt-ok
if [ "$RC" != 0 ]; then
  fail "adopting a live stream-json worker exited $RC: $ERR"
else
  ok "adopting a live stream-json worker registers it"
  aname=$(adopted_name)
  case $OUT in
    "adopt	$aname	adopted	stream-json	w-ok"*) ok "the adopt line names the session, the rung and the handle" ;;
    *) fail "unexpected adopt line: $OUT" ;;
  esac
  [ "$(row_field "$aname" origin)" = adopted ] && ok "an adopted row carries the adopted origin" || fail "the row's origin is '$(row_field "$aname" origin)'"
  [ "$(row_field "$aname" owner)" = mission-control:alpha ] && ok "an adopted row's owner defaults to the program's mission control" || fail "the row's owner is '$(row_field "$aname" owner)'"
  [ "$(row_field "$aname" kind)" = worker ] && [ "$(row_field "$aname" scope)" = adopt-ok ] && ok "an adopted row carries its kind and scope" || fail "the row's kind or scope is wrong"
  [ "$(row_field "$aname" backend)" = stream-json ] && [ "$(row_field "$aname" handle)" = w-ok ] && ok "an adopted row carries its backend and handle" || fail "the row's backend or handle is wrong"
  [ "$(row_field "$aname" process)" = "$adopt_live" ] && ok "an adopted row records the session's process" || fail "the row's process is '$(row_field "$aname" process)'"
  [ "$(row_field "$aname" state)" = launched ] && [ "$(row_field "$aname" format)" = 1 ] && ok "an adopted row is a complete, launched row" || fail "the row is not complete"
  ml list
  case $OUT in *"$aname	alpha	worker	adopt-ok	stream-json"*) ok "the program's list shows the adopted session" ;; *) fail "list lacks the adopted session: $OUT" ;; esac

  before=$(reg_count)
  ml adopt --program alpha --handle stream-json:w-ok --kind reviewer --scope adopt-again
  [ "$RC" = 3 ] && [ "$(reg_count)" = "$before" ] && ok "adopting a session another supervisor holds is refused" || fail "re-adopting exited $RC: $ERR"
  case $ERR in *"$aname"*"mission-control:alpha"*) ok "the refusal names the holder and its owner" ;; *) fail "the refusal does not name the holder: $ERR" ;; esac
fi

mksj w-tw "$adopt_live2"
ml adopt --program alpha --handle stream-json:w-tw --kind worker --scope adopt-tw --owner tower
[ "$RC" = 0 ] && ok "an adoption names its owner" || fail "adopting with an owner exited $RC: $ERR"
tw_name=$(adopted_name)
[ "$(row_field "$tw_name" owner)" = tower ] && ok "the row holds the owner given" || fail "the owner given was not kept"
ml adopt --program alpha --handle stream-json:w-tw --kind worker --scope adopt-tw2
case $ERR in *tower*) ok "a session a tower holds is refused, naming the tower" ;; *) fail "a session held by a tower was adopted or refused unnamed (exit $RC): $ERR" ;; esac

# tmux: a window that keeps its owner's name, its pane's process the evidence.
mkdir -p "$tmp/tmux/pid"
printf 'owner-window\n' >"$tmp/tmux/@41"
printf '%s\n' "$adopt_live" >"$tmp/tmux/pid/@41"
ml adopt --program alpha --handle tmux:@41 --kind ad-hoc --scope adopt-tmux
if [ "$RC" = 0 ]; then
  tname=$(adopted_name)
  [ "$(row_field "$tname" backend)" = tmux ] && [ "$(row_field "$tname" handle)" = @41 ] && [ "$(row_field "$tname" origin)" = adopted ] \
    && ok "an adopted tmux session is registered under its window" || fail "the tmux row is wrong"
  [ "$(row_field "$tname" process)" = "$adopt_live" ] && ok "the tmux row records its pane's process" || fail "the tmux row's process is '$(row_field "$tname" process)'"
  ml retire "$tname"
  if [ "$RC" = 0 ] && [ ! -e "$tmp/tmux/@41" ] && [ ! -e "$areg/$tname" ]; then
    ok "an adopted tmux session retires by its window, whatever it is called"
  else
    fail "the adopted tmux retire exited $RC, window left: $([ -e "$tmp/tmux/@41" ] && echo yes || echo no): $OUT $ERR"
  fi
else
  fail "adopting a live tmux session exited $RC: $ERR"
fi
printf 'dead-window\n' >"$tmp/tmux/@42"
printf '%s\n' "$adopt_dead" >"$tmp/tmux/pid/@42"
before=$(reg_count)
ml adopt --program alpha --handle tmux:@42 --kind ad-hoc --scope adopt-tmux-dead
[ "$RC" = 4 ] && [ "$(reg_count)" = "$before" ] && ok "a tmux window whose process has exited is not adopted" || fail "adopting a dead tmux pane exited $RC"
rm -f "$tmp/tmux/@42"

# An operator's own session is the operator's to end.
mksj w-op "$adopt_live"
ml adopt --program alpha --handle stream-json:w-op --kind ad-hoc --scope adopt-op --owner operator
op_name=$(adopted_name)
[ "$RC" = 0 ] || fail "adopting an operator's session exited $RC: $ERR"
ml retire "$op_name"
[ "$RC" = 4 ] && [ -e "$areg/$op_name" ] && ok "retiring an operator-owned adopted session is refused and the row stays" \
  || fail "the operator-owned retire exited $RC (row present: $([ -e "$areg/$op_name" ] && echo yes || echo no))"
case $OUT in *"needs-confirmation"*) ok "the retire reports it needs the operator's confirmation" ;; *) fail "the retire output does not say so: $OUT" ;; esac
kill -0 "$adopt_live" 2>/dev/null && ok "the operator's session was not stopped" || fail "the operator-owned session was stopped"
adopt_events | awk -F '\t' -v s="$op_name" '$3 == "retire-needs-confirmation" && $4 == s { f = 1 } END { exit !f }' \
  && ok "a confirmation item is raised for the retirement" || {
  fail "no retire-needs-confirmation event for $op_name"
  adopt_events >&2
}
awk -F '\t' '$1 == "retire-needs-confirmation" && $2 == "decision" { f = 1 } END { exit !f }' "$repo_root/config/mc-event-classes.tsv" \
  && ok "the confirmation item is owed to the operator" || fail "retire-needs-confirmation is not classed as a decision"

kill "$adopt_live" "$adopt_live2" 2>/dev/null
wait "$adopt_live" "$adopt_live2" 2>/dev/null

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mission-control-launch tests passed"
