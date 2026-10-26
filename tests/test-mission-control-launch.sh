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
# The tmux stub: a window table under $TMUX_STUB, argv recorded per call.
cat >"$tmp/bin/tmux" <<'STUB'
#!/bin/sh
all="$*"
printf '%s\n' "$all" >>"$TMUX_STUB/calls"
case $1 in
  new-window)
    n=$(($(cat "$TMUX_STUB/next" 2>/dev/null || echo 1)))
    echo $((n + 1)) >"$TMUX_STUB/next"
    shift
    : >"$TMUX_STUB/@$n"
    printf '%s\n' "$@" >"$TMUX_STUB/argv-@$n"
    echo "@$n"
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
    SHIM_RECORD_DIR="${SHIM_RECORD_DIR:-$tmp}" TMUX_STUB="$tmp/tmux" TMUX_KILL_FAIL="${TMUX_KILL_FAIL:-0}" \
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
for kind in tower orchestrator worker reviewer ad-hoc mission-control; do
  case $kind in
    tower | orchestrator) prof=tower ;;
    mission-control) prof=mission-control ;;
    *) prof=worker ;;
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
  case $(field tier) in
    */*) ok "[$kind] the tier was resolved through the allocation seam ($(field tier))" ;;
    *) fail "[$kind] the report carries no resolved tier" ;;
  esac
  wait_done "$name"
done

# The execution key's shipped tier reaches the worker's argv.
case " $(cat "$tmp/rec-worker/argv") " in
  *" --model opus --effort high "*) ok "the worker kind runs at the execution key's tier" ;;
  *) fail "the worker's argv lacks the execution tier: $(cat "$tmp/rec-worker/argv")" ;;
esac
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

ml launch --program beta --kind worker --scope x --brief "$tmp/brief.md"
[ "$RC" = 4 ] && ok "a program that is not configured is refused (exit 4)" || fail "an unconfigured program exited $RC"
for bad in '--kind janitor' '--scope a/b' '--program Alpha' '--backend print' '--rules program'; do
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
ml retire "$worker_name"
[ "$RC" = 3 ] && ok "retiring a name with no row exits 3" || fail "a second retire exited $RC"

win=$(awk -F '\t' '$1 == "handle" { print $2 }' "$fleet/mission-control/sessions/$pane_name")
[ -e "$tmp/tmux/$win" ] && ok "the tmux session has a live window ($win) before retire" || fail "the tmux launch left no window"
argv_t=$(cat "$tmp/tmux/argv-$win" 2>/dev/null)
case $argv_t in
  *fleet-dispatch-env.sh*--settings*"$core/config/worker-settings.json"*--name*"$pane_name"*) ok "the tmux window runs the session under its profile and name" ;;
  *) fail "the tmux window's argv lacks the profile or name: $argv_t" ;;
esac
grep -qF 'Never hand the operator a pane' "$fleet/mission-control/launch/$pane_name/brief.md" \
  && ok "the tmux session's brief carries the rules" || fail "the tmux session's brief lacks the rules"
TMUX_KILL_FAIL=1 ml retire "$pane_name"
if [ "$RC" = 1 ] && printf '%s\n' "$OUT" | grep -q "^retire	$pane_name	partial	.*held=.*pane"; then
  ok "a window that will not close is reported as a partial release (exit 1)"
else
  fail "a failed pane close was not reported partial: exit $RC, $OUT"
fi
[ -f "$fleet/mission-control/sessions/$pane_name" ] && ok "a partial release keeps the row for a retry" || fail "a partial release dropped the row"
ml retire "$pane_name"
[ "$RC" = 0 ] && ok "a retry completes the release" || fail "the retry exited $RC: $OUT"
[ ! -e "$tmp/tmux/$win" ] && ok "the retired session has no pane" || fail "the pane survived retire"
[ ! -e "$fleet/mission-control/sessions/$pane_name" ] && ok "the retired tmux session has no row" || fail "the tmux row survived retire"

# A row in a format the launcher does not know is refused, naming the field.
ml name --program alpha --kind tower --scope spec:alpha-tower
tower_row="$fleet/mission-control/sessions/$OUT"
sed 's/^format	1$/format	9/' "$tower_row" >"$tmp/row9" && cat "$tmp/row9" >"$tower_row"
ml retire "$OUT"
[ "$RC" = 2 ] && case $ERR in *format*) true ;; *) false ;; esac \
  && ok "a row with an unknown format is refused, naming the field" || fail "an unknown-format row was not refused: $RC $ERR"
ml kinds
[ "$(printf '%s\n' "$OUT" | grep -c .)" = 6 ] && ok "kinds lists the six session kinds" || fail "kinds: $OUT"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mission-control-launch tests passed"
