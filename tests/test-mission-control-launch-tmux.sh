#!/bin/bash
# Tests for scripts/mission-control-launch.sh: a stream-json session does not
# inherit the launcher's tmux context, the tmux rung's windows, tokens and
# Remote Control, the per-call and knob backends, names, refusals and the
# posture check (mission-control REQ-M1.7, REQ-G1.5, REQ-B1.4).
#
# Split from tests/test-mission-control-launch.sh so each file fits the
# per-file test-time budget; the shared fixture is
# tests/lib/mc-launch-fixture.sh.
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
# A headless mission control has no mod to claim a wake target, so the launch
# records one under its session name: the runner's wake finds it in the
# registry and prints no unreachable line; retiring it takes the target away.
wk_targets="$fleet/mission-control/alpha/wake-targets"
wk_pass() { # wk_pass <now>
  env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA PLANWRIGHT_ROOT="$core" PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" PLANWRIGHT_LOCAL_CONFIG="$tmp/absent.yml" HOME="$fixhome" \
    PLANWRIGHT_FLEET_STATE_DIR="$fleet" /bin/bash "$repo_root/scripts/mc-wake.sh" tick --program alpha --now "$1" 2>&1
}
[ -f "$wk_targets" ] && grep -qxF "$rc_stream${TAB}no-mod" "$wk_targets" && ok "a stream-json mission-control launch records its session as a wake target" \
  || fail "no wake target for $rc_stream (targets file '$wk_targets')"
mc_run mc-event.sh emit --program alpha pr-ready pr-7 "seven is ready"
wk_out=$(wk_pass 4000000000)
case $wk_out in
  *unreachable*"$rc_stream"*) fail "the runner's wake reports the headless mission control unreachable: $wk_out" ;;
  *"$rc_stream"*) ok "the runner's wake reports no unreachable line for a launched headless mission control" ;;
  *) fail "the runner's wake never named the headless mission control: $wk_out" ;;
esac
printf '%s\tno-mod\n' ghost-unregistered >>"$wk_targets"
wk_out=$(wk_pass 4000000400)
case $wk_out in
  *"unreachable${TAB}ghost-unregistered${TAB}not in the fleet registry"*) ok "an unregistered target still reports unreachable" ;;
  *) fail "an unregistered target did not report unreachable: $wk_out" ;;
esac
ml retire "$rc_stream"
grep -qxF "$rc_stream${TAB}no-mod" "$wk_targets" && fail "retiring the headless mission control left its wake target" \
  || ok "retiring a headless mission control removes its wake target"
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
rec="$tmp/rec-name-worker"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind worker --scope spec:alpha-worker --brief "$tmp/brief.md"
[ "$RC" = 0 ] || fail "fixture: the worker whose name is held did not launch: $ERR"
wait_done "$(field name)"
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

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mission-control-launch tests passed"
