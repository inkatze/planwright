#!/bin/bash
# Tests for scripts/mc-config.sh doctor — the bring-up audit and the drift
# scan (mission-control REQ-A1.9). Split from tests/test-mc-config.sh so
# each file fits the per-file test-time budget.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-config-doctor.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$repo_root/scripts/mc-config.sh" ] || {
  echo "FAIL: scripts/mc-config.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-config-doctor.XXXXXX") || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
trap 'chmod -R u+rwX "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
cfg() { mc_run mc-config.sh "$@"; }
layer="$adopter/planwright.yml"
sum() { if [ -e "$1" ]; then cksum <"$1"; else echo absent; fi; }
reset_mc_fixture
mkdir -p "$repo/specs"

# ---------------------------------------------------------------------------
# The bring-up audit: doctor names every shipped default a layer overrides
# and every inherited mechanism it can see, and writes nothing.
# ---------------------------------------------------------------------------
reset_mc_fixture
# The scratch path may itself name planwright or claude, so the program-path
# match is proven on a repository and a home whose paths name neither.
neutral_home=/mcdoc-neutral-home/alpha
neutral_repo=/mcdoc-neutral-repo/alpha
printf 'mission_control_programs: [alpha]\nprogram_alpha_repositories: [%s, %s]\nprogram_alpha_spec_root: %s/specs\nprogram_alpha_home: %s\n' "$repo" "$neutral_repo" "$repo" "$neutral_home" >"$tracked"
mkdir -p "$tmp/cronbin"
cat >"$tmp/cronbin/crontab" <<'EOF'
#!/bin/sh
[ "$1" = -l ] || exit 2
[ -f "$CRON_FIXTURE" ] || { echo "no crontab for fixture" >&2; exit 1; }
cat "$CRON_FIXTURE"
EOF
chmod +x "$tmp/cronbin/crontab"
saved_path=$PATH
PATH="$tmp/cronbin:$PATH"
CRON_FIXTURE="$tmp/crontab.txt"
export PATH CRON_FIXTURE

cfg doctor --program alpha
expect_rc "doctor runs on a program on the shipped defaults" 0
expect_eq "a program on the shipped defaults with no crontab is clean" "clean"

sessions="$fleet/mission-control/sessions"
mkdir -p "$sessions"
root_cache="$tmp/claude/plugins/cache/mkt/planwright"
mkdir -p "$root_cache/0.62.0" "$root_cache/9.9.9"
jq -n --arg p "$root_cache/9.9.9" '{version: 2, plugins: {"planwright@planwright": [{scope: "user", installPath: $p, version: "9.9.9"}]}}' \
  >"$tmp/claude/plugins/installed_plugins.json"
session_row() { # session_row <name> <program> <backend> [<root>]: a launch registry row; no root is a row from before the field
  printf 'format\t1\nname\t%s\nprogram\t%s\nkind\tworker\nscope\tx\nbackend\t%s\nlaunched\t1\n' "$1" "$2" "$3" >"$sessions/$1"
  [ -z "${4:-}" ] || printf 'root\t%s\n' "$4" >>"$sessions/$1"
}
session_row mc-alpha-worker-1111111111 alpha tmux "$root_cache/9.9.9"
session_row mc-alpha-worker-2222222222 alpha stream-json "$root_cache/9.9.9"
session_row mc-beta-worker-3333333333 beta tmux "$root_cache/0.62.0"
session_row mc-alpha-worker-4444444444 alpha ''
session_row mc-alpha-worker-5555555555 alpha stream-json "$root_cache/0.62.0"
session_row mc-alpha-worker-6666666666 alpha stream-json
# Shell forms no redaction could model, and schedules short, named or with
# an unknown keyword, each a crontab line, then " ==> "
# and the command word and match the report must read as (a blank standing
# for the tab): never an argument, and a word past the plain characters cut
# where they end.
shapes="$tmp/cron-shapes.txt"
cat >"$shapes" <<'SHAPES'
30 * * * * T=`echo lk-j lk-k` planwright ==> T=<redacted> planwright
31 * * * * T=${X:-lk-l lk-m} planwright ==> T=<redacted> planwright
32 * * * * TOKEN="$(cat "/x lk-n") lk-o" planwright ==> TOKEN=<redacted> planwright
33 * * * * T=$'a\'b lk-p' planwright ==> T=<redacted> planwright
34 * * * * sh -c 'TOKEN='\''lk-q lk-r'\'' planwright' ==> sh planwright
1PLANWRIGHT_TOKEN=lk-s lk-t ==> 1PLANWRIGHT_TOKEN=<redacted> PLANWRIGHT
@PLANWRIGHT_TOKEN=lk-u lk-v ==> <redacted> PLANWRIGHT
35 * * * * \TOKEN=lk-w planwright ==> <redacted> planwright
36 * * * * env "TOKEN"=lk-x TOKEN"="lk-y planwright ==> env planwright
37 * * * * T+=lk-z A[0]=lk-0 planwright ==> T+=<redacted> planwright
0=lk-01 claude ==> 0=<redacted> claude
*=lk-02 planwright ==> <redacted> planwright
39 * * * * T=$(case a in a) echo lk-05 lk-06;; esac) planwright ==> T=<redacted> planwright
  planwright_secret=lk-07 lk-08 ==> planwright_secret=<redacted> planwright
@reboot T=lk-09 /opt/planwright/r ==> T=<redacted> planwright
-*/5 * * * * T=lk-10 /opt/planwright/dash ==> T=<redacted> planwright
41 * * * * [ "$a" = "$b" ] && planwright ==> <redacted> planwright
42 * * * * echo "$(grep "it's" /f)" 'TOKEN=lk-20 lk-21' planwright ==> echo planwright
43 * * * * echo "`echo "'"`" 'K=lk-22 lk-23' planwright ==> echo planwright
44 * * * * bash -c $'echo it\'s; TOKEN=lk-24 lk-25\' planwright' ==> bash planwright
45 * * * * T=$[1 + lk-26] planwright ==> T=<redacted> planwright
46 * * * * planwright # don't 'TOKEN=lk-27 lk-28' ==> planwright planwright
47 * * * * planwright %it's 'TOKEN=lk-29 lk-2a' ==> planwright planwright
48 * * * * T=lk-2b%lk-2c lk-2d planwright ==> T=<redacted> planwright
"PLANWRIGHT_TOKEN=lk-2e"=lk-2f ==> <redacted> PLANWRIGHT
'claude=lk-2g lk-2h'=lk-2i ==> <redacted> claude
0 0 * * curl lk-c1 https://x/planwright ==> <redacted> planwright
0 0 mysql -u root -plk-c2 planwright ==> <redacted> planwright
@bogus lk-c3 planwright ==> <redacted> planwright
0 0 * may lk-c4 planwright ==> <redacted> planwright
*/5 * * * planwright ==> <redacted> planwright
0 0 1 Jan,mar Mon-fri /opt/planwright/named ==> /opt/planwright/named planwright
@weekly /opt/planwright/wk ==> /opt/planwright/wk planwright
0~30 */2 * * * /opt/planwright/rand ==> /opt/planwright/rand planwright
SHAPES
{
  printf '# a comment naming planwright\n'
  printf '*/5 * * * * /opt/hub/w.sh planwright sweep\n'
  printf '0 3 * * * /usr/bin/backup\n'
  printf '*/10 * * * * cd %s && ./sweep.sh\n' "$repo"
  printf '%s\n' "*/15 * * * * PLANWRIGHT_TOKEN=s3cr3t API_KEY='x y' NOTE=\"a b\" /opt/hub/claude-run.sh --key=k3y"
  printf '%s\n' '1 * * * * T="lk-1 lk-2"lk-3 /opt/planwright/a'
  printf '%s\n' '2 * * * * T=lk-4"lk-5 lk-6" /opt/planwright/b'
  printf '%s\n' '3 * * * * T=lk-7\ lk-8 /opt/planwright/c'
  printf '%s\n' '4 * * * * T="lk-9\" lk-a" /opt/planwright/d'
  # shellcheck disable=SC2016 # a literal crontab line, never expanded
  printf '%s\n' '5 * * * * T=$(cat /run/lk-b x) /opt/planwright/e'
  printf '%s\n' "6 * * * * curl -d 'token=lk-c lk-d' /opt/planwright/f"
  printf '%s\n' '7 * * * * /opt/planwright/g T="lk-e lk-f'
  printf '%s\n' 'planwright_token = lk-g lk-h'
  printf '8 * * * * TOKEN\001=lk-i /opt/planwright/h\n'
  printf '9\t*\t*\t*\t*\t/opt/planwright/i\n'
  printf '%s\n' '10 * * * * /opt/hub/Claude-Sweep.sh' '11 * * * * PLANWRIGHT_ROOT=/opt/pw /opt/pw/tick.sh'
  printf '*/20 * * * * %s/tick.sh\n' "$neutral_home"
  printf '*/12 * * * * cd %s && ./x.sh\n' "$neutral_repo"
  printf '%s\n' '*/25 * * * * /MCDOC-NEUTRAL-HOME/alpha/x.sh'
  printf '38 * * * * T=abc\\\033"lk-03 lk-04" /opt/planwright/a\n'
  printf '%s\n' "50 * * * * curl -H 'Authorization: Bearer lk-b1' https://bot:lk-b2@api.example/planwright --token lk-b3 -o /dev/null%lk-b4"
  printf '%s\n' '51 * * * * https://bot:lk-b5@api.example/claude' '52 * * * * /opt/planwright/x%lk-b6' '53 * * * * --token=lk-b7 planwright'
  printf '*/30 * * * * /opt/planwright/both %s/y\n' "$neutral_repo"
  sed 's/ ==> .*//' "$shapes"
} >"$CRON_FIXTURE"
printf 'mission_control_launch_backend: stream-json\nmission_control_stall_window: 30m\nmission_control_tick_cadence: 5m\n' >"$layer"
printf 'program_alpha_duties: [inbox, readiness-check]\n' >>"$tracked"
before=$(sum "$layer")
tracked_before=$(sum "$tracked")
cfg doctor --program alpha
expect_rc "doctor reports findings as data" 0
expect_out "a layer's value away from the shipped one is named with its layer" "override${tab}mission_control_stall_window${tab}adopter${tab}30m${tab}10m"
expect_no_out "a layer restating the shipped value is no override" "mission_control_tick_cadence"
expect_no_out "a layer restating the shipped backend is no override" "override${tab}mission_control_launch_backend"
expect_no_out "the program list is setup, not an override" "mission_control_programs"
expect_out "a shipped default duty the program leaves off is named" "duty-off${tab}session-keeper"
expect_no_out "an enabled duty is not named" "duty-off${tab}inbox"
expect_out "a session launched on another rung than the knob is named" "launch-backend${tab}mc-alpha-worker-1111111111${tab}tmux${tab}stream-json"
expect_no_out "a session on the knob's rung is not named" "mc-alpha-worker-2222222222"
expect_no_out "another program's session is not named" "mc-beta-worker-3333333333"
expect_out "a session recorded on an older plugin root is flagged stale with both versions" "stale-root${tab}mc-alpha-worker-5555555555${tab}0.62.0${tab}9.9.9"
expect_no_out "a session on the installed plugin root is not flagged" "stale-root${tab}mc-alpha-worker-2222222222"
expect_no_out "another program's stale session is not flagged" "stale-root${tab}mc-beta-worker-3333333333"
expect_out "a row with no recorded root is unknown, never current" "unknown${tab}launches${tab}mc-alpha-worker-6666666666 plugin root: no plugin root recorded at launch"
expect_no_out "a session on the installed root is not unknown either" "mc-alpha-worker-2222222222 plugin root"
expect_out "a session whose row names no rung is an unknown launches check" "unknown${tab}launches${tab}mc-alpha-worker-4444444444 names no rung"
expect_no_out "a session whose row names no rung is not read as another rung" "launch-backend${tab}mc-alpha-worker-4444444444"
cron_line() { # cron_line <label> <word> <match>: one report line reads exactly so
  if printf '%s\n' "$OUT" | grep -qxF -- "cron${tab}$2${tab}$3"; then
    ok "$1: $2 $3"
  else
    fail "$1: no report line reads exactly: cron<TAB>$2<TAB>$3"
  fi
}
cron_line "a cron line naming planwright is named by its command word" /opt/hub/w.sh planwright
cron_line "a cron line in a program repository is named by that path" cd "$repo"
cron_line "a cron line naming only the program home is named" "$neutral_home/tick.sh" "$neutral_home"
cron_line "a cron line naming only a program repository is named" cd "$neutral_repo"
expect_no_out "a program path matches only as spelled" "/MCDOC-NEUTRAL-HOME"
cron_line "a leading assignment is the word, its value blanked" 'PLANWRIGHT_TOKEN=<redacted>' PLANWRIGHT
cron_line "a credential the line carries in its arguments is never printed" curl planwright
cron_line "a command word holding a URL password is cut before it" 'https<redacted>' claude
cron_line "a command word running into cron's % is cut there" '/opt/planwright/x<redacted>' planwright
cron_line "a --token word is cut at its =" '--token=<redacted>' planwright
cron_line "a program path wins over a product name on the same line" /opt/planwright/both "$neutral_repo"
# Every report line in the crontab's order, so a line misread, dropped or
# doubled fails even where another line prints the same text.
cron_want=$(
  printf 'cron\t%s\t%s\n' /opt/hub/w.sh planwright cd "$repo" 'PLANWRIGHT_TOKEN=<redacted>' PLANWRIGHT \
    'T=<redacted>' planwright 'T=<redacted>' planwright 'T=<redacted>' planwright \
    'T=<redacted>' planwright 'T=<redacted>' planwright curl planwright \
    /opt/planwright/g planwright planwright_token planwright 'TOKEN=<redacted>' planwright \
    /opt/planwright/i planwright /opt/hub/Claude-Sweep.sh Claude 'PLANWRIGHT_ROOT=<redacted>' PLANWRIGHT \
    "$neutral_home/tick.sh" "$neutral_home" cd "$neutral_repo" 'T=<redacted>' planwright \
    curl planwright 'https<redacted>' claude '/opt/planwright/x<redacted>' planwright \
    '--token=<redacted>' planwright /opt/planwright/both "$neutral_repo"
  sed "s/^.* ==> //; s/ /$tab/; s/^/cron$tab/" "$shapes"
)
cron_got=$(printf '%s\n' "$OUT" | grep "^cron$tab")
if [ "$cron_got" = "$cron_want" ]; then
  ok "each reported cron line reads as its own expected word and match, in order"
else
  fail "the cron report lines differ from the expected ones, in order:"
  printf '%s\n' "$cron_want" >"$tmp/cron-want.txt"
  printf '%s\n' "$cron_got" | diff "$tmp/cron-want.txt" - >&2
fi
for secret in s3cr3t "x y" "a b" k3y lk- Bearer Authorization 'bot:' ./sweep.sh; do
  expect_no_out "a cron line's arguments never reach the report: $secret" "$secret"
done
cron_line "a cron line naming Claude in another case is named as spelled" /opt/hub/Claude-Sweep.sh Claude
cron_line "a cron line naming PLANWRIGHT in capitals is named" 'PLANWRIGHT_ROOT=<redacted>' PLANWRIGHT
expect_no_out "an unrelated cron line is not named" "backup"
expect_no_out "a cron comment is not named" "a comment"
expect_no_out "findings leave out the clean line" "clean"
if [ "$(sum "$layer")" = "$before" ] && [ "$(sum "$tracked")" = "$tracked_before" ]; then
  ok "doctor writes no layer"
else
  fail "doctor changed a layer"
fi

printf 'mission_control_launch_backend: tmux\n' >"$layer"
: >"$CRON_FIXTURE"
cfg doctor --program alpha
expect_out "a layer moving the backend knob is named" "override${tab}mission_control_launch_backend${tab}adopter${tab}tmux${tab}stream-json"
expect_out "launches are judged against the knob in force" "launch-backend${tab}mc-alpha-worker-2222222222${tab}stream-json${tab}tmux"

if [ "$(id -u)" != 0 ]; then
  chmod 000 "$sessions"
  cfg doctor --program alpha
  chmod 700 "$sessions"
  expect_rc "doctor with an unreadable registry still reports" 0
  expect_out "an unreadable registry is an unknown launches check" "unknown${tab}launches${tab}the launch registry could not be read"
  expect_out "the other checks still report beside an unreadable registry" "override${tab}mission_control_launch_backend${tab}adopter${tab}tmux${tab}stream-json"
fi

tracked_good=$(cat "$tracked")
printf '%s\n' "$tracked_good" | sed 's|^program_alpha_repositories: .*|program_alpha_repositories: relative/repo|' >"$tracked"
printf '*/5 * * * * /opt/hub/w.sh planwright sweep\n*/20 * * * * %s/tick.sh\n' "$neutral_home" >"$CRON_FIXTURE"
cfg doctor --program alpha
expect_out "an unreadable repository list is an unknown cron check" "unknown${tab}cron${tab}"
cron_line "the cron scan still names a line naming planwright" /opt/hub/w.sh planwright
expect_no_out "a path the program could not report is not matched" "$neutral_home/tick.sh"
printf '%s\n' "$tracked_good" >"$tracked"
: >"$CRON_FIXTURE"

printf '%s\n' "$tracked_good" | sed 's|^program_alpha_duties: .*|program_alpha_duties: [inbox, inbox]|' >"$tracked"
cfg doctor --program alpha
printf '%s\n' "$tracked_good" >"$tracked"
expect_rc "doctor with an unreadable duty list still reports" 0
expect_out "an unreadable duty list is an unknown duties check, never clean" "unknown${tab}duties${tab}the enabled or default duties could not be read"
expect_no_out "an unreadable duty list names no duty off" "duty-off${tab}"

printf '%s\n' '- not flat' 'mission_control_stall_window: 30m' >"$layer"
printf '%s\n' 'mission_control_tick_cadence: 7m' >>"$tracked"
cfg doctor --program alpha
printf '%s\n' "$tracked_good" >"$tracked"
expect_rc "doctor with a malformed adopter layer still reports" 0
expect_out "a malformed adopter layer is an unknown overrides check, never clean" "unknown${tab}overrides${tab}a layer is malformed"
expect_no_out "a skipped layer's value is not reported as in force" "override${tab}mission_control_stall_window"
expect_out "the readable layers' overrides still follow a malformed adopter layer" "override${tab}mission_control_tick_cadence${tab}repo-tracked${tab}7m${tab}5m"
rm -f "$layer"

printf '%s\n' 'mission_control_stall_window: 30m' >"$layer"
printf '%s\n' 'mission_control_stall_window: 10m' >>"$tracked"
cfg doctor --program alpha
expect_no_out "a higher layer restoring the shipped value leaves no override" "override${tab}mission_control_stall_window"
printf '%s\n' "$tracked_good" 'mission_control_stall_window: 20m' >"$tracked"
cfg doctor --program alpha
expect_out "the override names the layer in force and its value" "override${tab}mission_control_stall_window${tab}repo-tracked${tab}20m${tab}10m"
printf '%s\n' "$tracked_good" >"$tracked"
rm -f "$layer"

printf '%s\n' 'mission_control_kb_index_budget: 0150' >"$layer"
cfg doctor --program alpha
rm -f "$layer"
expect_out "a value equal to the shipped one only as a number is an override" "override${tab}mission_control_kb_index_budget${tab}adopter${tab}0150${tab}150"

printf '%s\n' 'mission_control_default_duties: [inbox, readiness-check]' >"$layer"
printf '%s\n' "$tracked_good" | sed 's|^program_alpha_duties: .*|program_alpha_duties: [inbox]|' >"$tracked"
cfg doctor --program alpha
printf '%s\n' "$tracked_good" >"$tracked"
rm -f "$layer"
expect_out "a default duty is judged against the default list the layers resolve" "duty-off${tab}readiness-check"
expect_no_out "a shipped default duty a layer drops from the list is not named" "duty-off${tab}session-keeper"

printf '%s\n' 'mission_control_launch_backend: bogus' >>"$tracked"
cfg doctor --program alpha
printf '%s\n' "$tracked_good" >"$tracked"
expect_out "a launch backend knob that cannot be resolved is an unknown launches check" "unknown${tab}launches${tab}mission_control_launch_backend could not be resolved"
expect_no_out "no session is judged against a knob that cannot be resolved" "launch-backend${tab}"

printf '%s\n' 'mission_control_tick_cadence: 7m' 'mission_control_tick_cadence: 7m' >>"$tracked"
cfg doctor --program alpha
expect_rc "doctor with a knob set twice in the repo-tracked layer still reports" 0
expect_out "a knob set twice is an unknown overrides check" "unknown${tab}overrides${tab}a layer is malformed, unreadable, or sets a knob twice"
expect_out "the overrides a plain read finds still follow it" "override${tab}mission_control_tick_cadence${tab}repo-tracked${tab}7m${tab}5m"
OUT=$(mc_env env PLANWRIGHT_CONFIG_STRICT_OVERLAYS=1 /bin/bash "$repo_root/scripts/mc-config.sh" doctor --program alpha 2>"$tmp/stderr")
RC=$?
printf '%s\n' "$tracked_good" >"$tracked"
expect_rc "doctor run with strict overlays already set still reports" 0
expect_out "the plain read clears an inherited strict setting" "override${tab}mission_control_tick_cadence${tab}repo-tracked${tab}7m${tab}5m"

grep -v '^mission_control_stall_window:' "$core/config/defaults.yml" >"$tmp/defaults.trimmed"
mv "$tmp/defaults.trimmed" "$core/config/defaults.yml"
printf '%s\n' 'mission_control_stall_window: 30m' >"$layer"
cfg doctor --program alpha
write_core_defaults </dev/null
rm -f "$layer"
expect_out "a knob set with no shipped value read is an unknown overrides check, never clean" "unknown${tab}overrides${tab}mission_control_stall_window is set in adopter"
expect_no_out "a knob with no shipped value read is not compared" "override${tab}mission_control_stall_window"

# ---------------------------------------------------------------------------
# Doctor drift: a standing rule that names a number for a knob it governs,
# and a dated, interim or temporary override in a local layer.
# ---------------------------------------------------------------------------
reset_mc_fixture
drift_home="$tmp/drift-home"
mlocal="$tmp/absent.yml"
printf 'mission_control_programs: [drift]\nprogram_drift_repositories: [%s]\nprogram_drift_spec_root: %s/specs\nprogram_drift_home: %s\n' "$repo" "$repo" "$drift_home" >"$tracked"
rm -f "$mlocal"
cfg doctor --program drift
expect_eq "REQ-A1.9: drift: no rules and no local layer is clean" "clean"

mc_run mc-rules.sh add drift --text "Mission control hands over to a fresh successor every time its context passes 40%." --subject handover --source "operator, fixture" --date 2026-01-01
mc_run mc-rules.sh add drift --text "Keep mission_control_stall_window at 10m." --subject stall --source "operator, fixture" --date 2026-01-01
mc_run mc-rules.sh add drift --text "Hand over the program notes at the end of each week, with 3 sections." --subject notes --source "operator, fixture" --date 2026-01-01
cfg doctor --program drift
expect_rc "REQ-A1.9: drift: doctor with rules reports findings as data" 0
expect_out "REQ-A1.9: drift: a rule naming 40% for the handover knob, left at the shipped 70, is a finding with rule, knob and effective value" "rule-knob${tab}r-1${tab}mission_control_handover_context${tab}40${tab}70${tab}core"
expect_out "REQ-A1.9: drift: the finding says it in plain words" "says 40 but mission_control_handover_context is 70"
expect_no_out "REQ-A1.9: drift: a rule naming the knob's own shipped value is no finding" "rule-knob${tab}r-2"
expect_no_out "REQ-A1.9: drift: a rule that merely says hand over, with no context or percent, is no finding" "rule-knob${tab}r-3"
printf 'mission_control_handover_context: 40\n' >"$adopter/planwright.yml"
cfg doctor --program drift
expect_no_out "REQ-A1.9: drift: once the knob matches the rule the finding is gone" "rule-knob${tab}r-1"
printf 'mission_control_handover_context: 55\n' >"$adopter/planwright.yml"
cfg doctor --program drift
expect_out "REQ-A1.9: drift: a knob moved to another value is named with its layer" "rule-knob${tab}r-1${tab}mission_control_handover_context${tab}40${tab}55${tab}adopter"
expect_out "REQ-A1.9: drift: a rule-knob finding names the file that sets the knob, not only the layer" "(set in adopter, file $adopter/planwright.yml)"
rm -f "$adopter/planwright.yml"
mc_run mc-rules.sh add drift --text "Set mission_control_stall_window to 30m." --subject stall --source "operator, fixture" --date 2026-01-01
cfg doctor --program drift
expect_out "REQ-A1.9: drift: a rule naming a knob and a value that differ is a finding" "rule-knob${tab}r-4${tab}mission_control_stall_window${tab}30m${tab}10m${tab}core"

mc_run mc-rules.sh add drift --text "Set mission_control_stall_window to 10." --subject stall --source "operator, fixture" --date 2026-01-01
mc_run mc-rules.sh add drift --text "Set mission_control_stall_window to 15." --subject stall --source "operator, fixture" --date 2026-01-01
cfg doctor --program drift
expect_no_out "REQ-A1.9: drift: a rule naming no unit that matches the knob's number is no finding" "rule-knob${tab}r-5"
expect_out "REQ-A1.9: drift: a rule naming no unit is compared with the knob's number alone" "rule-knob${tab}r-6${tab}mission_control_stall_window${tab}15${tab}10m${tab}core"

mc_run mc-rules.sh add drift --text "Set max_parallel_units to 8." --subject fleet --source "operator, fixture" --date 2026-01-01
mc_run mc-rules.sh add drift --text "Set fleet_max_parallel_units to 8." --subject fleet --source "operator, fixture" --date 2026-01-01
mc_run mc-rules.sh add drift --text "Set dispatch_backend_per_spec to 8." --subject fleet --source "operator, fixture" --date 2026-01-01
printf 'fleet_max_parallel_units: 3\nmax_parallel_units: 3\n' >"$adopter/planwright.yml"
cfg doctor --program drift
expect_out "REQ-A1.9: drift: a rule naming a knob whose value cannot be read is reported as unknown, never dropped as agreeing" "unknown${tab}rules${tab}rule r-9 names dispatch_backend_per_spec but its value could not be read"
expect_out "REQ-A1.9: drift: a rule naming the full knob name is a finding on that knob" "rule-knob${tab}r-8${tab}fleet_max_parallel_units${tab}8${tab}3${tab}adopter"
expect_no_out "REQ-A1.9: drift: a knob name inside a longer name is not matched as the shorter knob" "rule-knob${tab}r-8${tab}max_parallel_units"
rm -f "$adopter/planwright.yml"

bs_dir="$tmp/back\\ntab\\tslash"
mkdir -p "$bs_dir"
bs_file="$bs_dir/planwright.yml"
printf '# interim: until the runner is rebuilt\nmission_control_stall_window: 20m\n' >"$bs_file"
OUT=$(mc_env env PLANWRIGHT_ADOPTER_OVERLAY="$bs_dir" /bin/bash "$repo_root/scripts/mc-config.sh" doctor --program drift 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_out "REQ-A1.9: drift: a layer path with backslashes is named as it is spelled" "temporary${tab}$bs_file${tab}mission_control_stall_window"
rm -rf "$bs_dir"

cat >"$mlocal" <<'EOT'
# a dated bump, drop it later
fleet_max_parallel_units: 10 # until 2020-11-01
mission_control_tick_cadence: 5m
# interim value while the runner is rebuilt
mission_control_stall_window: 20m
# temporary: reviewed on 2999-01-01
mission_control_repeat_window: 2h
# ordinary note about cadence
mission_control_panel_refresh: 30s
mission_control_event_retention: 14d # keep 14 days
# dropped until 2020-02-02: mission_control_audit_idle_after
EOT
local_before=$(sum "$mlocal")
cfg doctor --program drift
expect_rc "REQ-A1.9: drift: doctor over a local layer with dated overrides reports" 0
expect_out "REQ-A1.9: drift: a trailing comment with a past date is a finding naming file, knob, comment and effective value" "temporary${tab}$mlocal${tab}fleet_max_parallel_units${tab}past date 2020-11-01${tab}a dated bump, drop it later; until 2020-11-01${tab}10"
expect_out "REQ-A1.9: drift: a comment above the knob saying interim is a finding" "temporary${tab}$mlocal${tab}mission_control_stall_window${tab}marker interim${tab}interim value while the runner is rebuilt${tab}20m"
expect_out "REQ-A1.9: drift: a comment naming a knob that was dropped until a past date is a finding" "temporary${tab}$mlocal${tab}mission_control_audit_idle_after${tab}past date 2020-02-02"
expect_no_out "REQ-A1.9: drift: a temporary note whose date is still ahead is no finding" "temporary${tab}$mlocal${tab}mission_control_repeat_window"
expect_no_out "REQ-A1.9: drift: an ordinary value with an ordinary comment is no finding" "temporary${tab}$mlocal${tab}mission_control_panel_refresh"
expect_no_out "REQ-A1.9: drift: an ordinary trailing comment is no finding" "temporary${tab}$mlocal${tab}mission_control_event_retention"
expect_no_out "REQ-A1.9: drift: an uncommented value is no finding" "temporary${tab}$mlocal${tab}mission_control_tick_cadence"
expect_out "REQ-A1.9: drift: the finding explains itself" "review it; doctor never edits the file"
if [ "$(sum "$mlocal")" = "$local_before" ]; then ok "REQ-A1.9: drift: doctor leaves the local layer as it was"; else fail "drift: doctor changed the local layer"; fi
printf 'mission_control_stall_window: 20m # TEMPORARY, see ticket\n' >"$mlocal"
cfg doctor --program drift
expect_out "REQ-A1.9: drift: a marker word matches in any case" "marker temporary"
printf '# until the runner is rebuilt\nmission_control_stall_window: 20m\nmission_control_tick_cadence: 5m # until 2999-01-01\n' >"$mlocal"
cfg doctor --program drift
expect_out "REQ-A1.9: drift: the bare word until with no date is a finding" "temporary${tab}$mlocal${tab}mission_control_stall_window${tab}marker until"
expect_no_out "REQ-A1.9: drift: until with a date still ahead is no finding" "temporary${tab}$mlocal${tab}mission_control_tick_cadence"
# A scan whose awk fails must read as unknown, never as a clean layer or rule set.
mkdir -p "$tmp/awkshim"
cat >"$tmp/awkshim/awk" <<'SHIM'
#!/bin/sh
case $* in *'function after'* | *flush_standalone*) exit 2 ;; esac
for a in /usr/bin/awk /bin/awk; do [ -x "$a" ] && exec "$a" "$@"; done
exit 127
SHIM
chmod +x "$tmp/awkshim/awk"
OUT=$(mc_env env PATH="$tmp/awkshim:$PATH" /bin/bash "$repo_root/scripts/mc-config.sh" doctor --program drift 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_out "REQ-A1.9: drift: a failing temporary scan is an unknown temporary check, never clean" "unknown${tab}temporary${tab}"
expect_out "REQ-A1.9: drift: a failing rule scan is an unknown rules check, never clean" "unknown${tab}rules${tab}"
rm -rf "$tmp/awkshim"
printf 'mission_control_stall_window: 20m # untilted and intermittent\nmission_control_tick_cadence: 5m # retemporary\n' >"$mlocal"
cfg doctor --program drift
expect_no_out "REQ-A1.9: drift: a marker word inside another word is no finding" "temporary${tab}$mlocal"
printf '# adopter note: until 2020-03-03\nmission_control_stall_window: 20m\n' >"$adopter/planwright.yml"
rm -f "$mlocal"
cfg doctor --program drift
expect_out "REQ-A1.9: drift: the adopter layer file is scanned too" "temporary${tab}$adopter/planwright.yml${tab}mission_control_stall_window"
rm -f "$adopter/planwright.yml" "$mlocal"
printf 'mission_control_stall_window: 20m # interim\n' >"$mlocal"
chmod 000 "$mlocal"
cfg doctor --program drift
chmod 644 "$mlocal"
rm -f "$mlocal"
if [ "$(id -u)" -eq 0 ]; then ok "REQ-A1.9: drift: root reads any file, so the unreadable-layer case is skipped"; else
  expect_out "drift: an unreadable local layer is an unknown temporary check" "unknown${tab}temporary${tab}$mlocal cannot be read"
  expect_no_out "drift: an unknown temporary check is printed as itself, never reshaped as a temporary finding" "temporary${tab}unknown"
fi
tracked_save=$(cat "$tracked")
printf '# temporary until 2020-04-04\nmission_control_stall_window: 20m\n' >>"$tracked"
cfg doctor --program drift
expect_no_out "REQ-A1.9: drift: the team-shared repo-tracked layer is not scanned" "temporary${tab}"
printf '%s\n' "$tracked_save" >"$tracked"

cfg doctor --program gamma
expect_rc "doctor on a program that is not configured" 3
cfg doctor
expect_rc "doctor without a program is a usage error" 2
PATH=$saved_path
export PATH
rm -rf "$sessions"
rm -f "$layer"

[ "$failures" -eq 0 ] || {
  printf '%s\n' "$failures failure(s)" >&2
  exit 1
}
echo "all mc-config doctor tests passed"
