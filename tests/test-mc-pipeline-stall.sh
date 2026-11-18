#!/bin/bash
# Tests for scripts/mc-pipeline-stall.sh — the stalled-pipeline alarm: a
# program with open draft pull requests and no ready flip inside
# mission_control_stalled_pipeline_window raises a pipeline-stalled failure
# naming why each draft is held, again every window while it lasts.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-pipeline-stall.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-pipeline-stall.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT
trap 'exit 143' HUP INT TERM

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
mchome="$tmp/mchome"
mkdir -p "$mchome"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_home: $mchome
program_alpha_sources: {code-state: forge:snapshot}
EOF

# The script under test runs from a copy whose readiness check, usage hold
# and host bound read their answers from files in $tmp.
pw="$tmp/pw"
mkdir -p "$pw"
cp -R "$repo_root/scripts" "$pw/scripts"
cat >"$pw/scripts/mc-readiness.sh" <<EOF
#!/bin/bash
verb=\$1
shift
n="" out="" ev=""
while [ \$# -gt 0 ]; do
  case \$1 in --pr) n=\$2 ;; --out) out=\$2 ;; --evidence) ev=\$2 ;; esac
  shift
done
case \$verb in
  collect)
    [ ! -f "$tmp/broken.\$n" ] || { printf 'gh: not logged in\n' >&2; exit 1; }
    { printf '# format: 1\nhead\tabc\n'; cat "$tmp/evidence.\$n"; printf 'stubpr\t%s\n' "\$n"; } >"\$out"
    ;;
  walk)
    n=\$(awk -F '\t' '\$1 == "stubpr" { print \$2 }' "\$ev")
    if [ -s "$tmp/walk.\$n" ]; then printf 'not-ready\tabc\n'; cat "$tmp/walk.\$n"; exit 4; fi
    printf 'ready\tabc\n'
    ;;
esac
EOF
cat >"$pw/scripts/mc-usage.sh" <<EOF
#!/bin/bash
if [ -f "$tmp/usage-held" ]; then printf 'held\t5h\t97\t1\n'; exit 0; fi
printf 'clear\n'
exit 1
EOF
cat >"$pw/scripts/mission-control-launch.sh" <<EOF
#!/bin/bash
cat "$tmp/bound"
EOF
printf 'bound\t8\t2\t0\n' >"$tmp/bound"

snapdir="$fleet/mission-control/alpha/snapshots"
mkdir -p "$snapdir"
runtime="$fleet/mission-control/alpha"
H=1111111111111111111111111111111111111111
T=1800000000
HOUR=3600
row() { # row <n> <draft> <mergeable> <checks>
  printf 'pr\tacme/web\t%s\t%s\t%s\t%s\tNONE\t0\t%s\t0\t0\tp%s\n' "$1" "$H" "$2" "$3" "$4" "$1"
}
snapshot() { # snapshot <taken> then rows on stdin
  printf 'format\t1\nsource\tforge\ntaken\t%s\n' "$1"
  cat
}
put() { snapshot "$1" >"$snapdir/forge"; }
run() { # run <now>
  OUT=$(mc_env /bin/bash "$pw/scripts/mc-pipeline-stall.sh" watch --program alpha --now "$1" 2>"$tmp/stderr")
  RC=$?
  ERR=$(cat "$tmp/stderr")
}
stalled_events() {
  mc_run_events | awk -F '\t' '$3 == "pipeline-stalled"' | wc -l | tr -d ' '
}
mc_run_events() { mc_env /bin/bash "$repo_root/scripts/mc-event.sh" list --program alpha 2>/dev/null; }

# Evidence the stub collects for each draft.
printf 'check\tbuild\tFAILURE\ncheck\tlint\tSUCCESS\n' >"$tmp/evidence.7"
printf 'fail\tcheck\tbuild is FAILURE\n' >"$tmp/walk.7"
: >"$tmp/evidence.8"
printf 'fail\tcheck\tno individual check was read\n' >"$tmp/walk.8"
printf 'check\tbuild\tSUCCESS\n' >"$tmp/evidence.9"
printf 'fail\tguard\tready-guard refuses: a thread is open\n' >"$tmp/walk.9"
printf 'check\tbuild\tSUCCESS\n' >"$tmp/evidence.10"
printf 'check\tbuild\tSUCCESS\n' >"$tmp/evidence.11"
: >"$tmp/walk.10"
: >"$tmp/walk.11"

drafts() {
  row 7 true MERGEABLE FAILURE
  row 8 true MERGEABLE NONE
  row 9 true MERGEABLE SUCCESS
  row 10 true CONFLICTING SUCCESS
  row 11 true MERGEABLE SUCCESS
}

# --- a first sight of drafts starts the clock and raises nothing ------------
drafts | put "$T"
run "$T"
expect_rc "the first pass" 0
expect_eq "starts the window, raising nothing" ""
if [ "$(stalled_events)" = 0 ]; then ok "no event inside the window"; else fail "raised inside the window"; fi

drafts | put $((T + 2 * HOUR - 60))
run $((T + 2 * HOUR - 60))
expect_eq "a minute inside the default 2h window still raises nothing" ""

# --- past the window: one event, a reason per draft -------------------------
drafts | put $((T + 2 * HOUR))
run $((T + 2 * HOUR))
expect_rc "past the window" 0
expect_out "an event is announced" "raised${tab}pipeline-stalled"
ev=$(mc_run_events)
case $ev in *"pipeline-stalled${tab}pipeline-stalled${tab}"*) ok "the event is the stalled kind, in the subject grammar" ;; *) fail "no pipeline-stalled event: $ev" ;; esac
for want in "5 drafts" "red check build (1): acme/web#7" "no CI on its head (1): acme/web#8" "flip-gate refusal ready-guard (1): acme/web#9" "merge conflict (1): acme/web#10" "awaiting a flip (1): acme/web#11"; do
  case $ev in *"$want"*) ok "names: $want" ;; *) fail "the event lacks '$want': $ev" ;; esac
done

# --- repeats once per window, not on every pass -----------------------------
run $((T + 2 * HOUR + 600))
expect_eq "a pass inside the repeat window raises nothing" ""
drafts | put $((T + 4 * HOUR))
run $((T + 4 * HOUR))
expect_out "a window later it raises again" "raised${tab}pipeline-stalled"
if [ "$(stalled_events)" = 2 ]; then ok "two events in all"; else fail "expected two events, got $(stalled_events)"; fi

# --- launch holds ----------------------------------------------------------
: >"$tmp/usage-held"
drafts | put $((T + 6 * HOUR))
run $((T + 6 * HOUR))
ev=$(mc_run_events)
case $ev in *"launch hold (usage) (1): acme/web#11"*) ok "a usage hold is the reason of a draft that is otherwise clear" ;; *) fail "no usage hold reason: $ev" ;; esac
rm -f "$tmp/usage-held"
printf 'bound\t2\t2\t0\n' >"$tmp/bound"
drafts | put $((T + 8 * HOUR))
run $((T + 8 * HOUR))
ev=$(mc_run_events)
case $ev in *"launch hold (host bound) (1): acme/web#11"*) ok "the host bound at its limit is a launch hold" ;; *) fail "no host bound reason: $ev" ;; esac
printf 'bound\t8\t2\t0\n' >"$tmp/bound"

# --- thirty drafts still name every reason inside the event's byte cap ------
for n in $(seq 100 129); do
  printf 'check\tbuild\tFAILURE\n' >"$tmp/evidence.$n"
  printf 'fail\tcheck\tbuild is FAILURE\n' >"$tmp/walk.$n"
done
{
  for n in $(seq 100 129); do row "$n" true MERGEABLE FAILURE; done
  row 7 true MERGEABLE FAILURE
  row 8 true MERGEABLE NONE
  row 10 true CONFLICTING SUCCESS
} | put $((T + 8 * HOUR + 2 * HOUR))
run $((T + 10 * HOUR))
ev=$(mc_run_events | tail -n 1)
case $ev in *"33 drafts"*"red check build (31):"*"no CI on its head (1)"*"merge conflict (1)"*) ok "a long list keeps the count and every reason" ;; *) fail "long list lost a reason: $ev" ;; esac
if [ "$(printf '%s' "$ev" | awk -F '\t' '{ print length($5) }')" -le 500 ]; then ok "and the text stays within the byte cap"; else fail "text over the cap: $ev"; fi

# --- a recent flip resets the window ----------------------------------------
{
  row 7 false MERGEABLE SUCCESS
  row 8 true MERGEABLE NONE
} | put $((T + 9 * HOUR))
run $((T + 9 * HOUR))
expect_eq "a draft gone ready resets the clock and raises nothing" ""
{
  row 7 false MERGEABLE SUCCESS
  row 8 true MERGEABLE NONE
} | put $((T + 9 * HOUR + 2 * HOUR - 60))
run $((T + 9 * HOUR + 2 * HOUR - 60))
expect_eq "still inside the window since the flip" ""
{
  row 7 false MERGEABLE SUCCESS
  row 8 true MERGEABLE NONE
} | put $((T + 11 * HOUR))
run $((T + 11 * HOUR))
expect_out "a window after the flip it raises" "raised${tab}pipeline-stalled"

# --- no drafts, nothing to alarm; a sight of drafts later starts afresh ------
{ row 7 false MERGEABLE SUCCESS; } | put $((T + 12 * HOUR))
run $((T + 12 * HOUR))
expect_eq "no open draft raises nothing" ""
drafts | put $((T + 20 * HOUR))
run $((T + 20 * HOUR))
expect_eq "drafts back after a quiet stretch start a fresh window" ""

# --- the knob is honored ----------------------------------------------------
echo 'mission_control_stalled_pipeline_window: 30m' >>"$tracked"
drafts | put $((T + 20 * HOUR + 1800))
run $((T + 20 * HOUR + 1800))
expect_out "a 30m window raises after 30m" "raised${tab}pipeline-stalled"
sed -i.bak 's/^mission_control_stalled_pipeline_window:.*/mission_control_stalled_pipeline_window: 6h/' "$tracked"
rm -f "$runtime"/pipeline-stall* "$tmp/stalled.keep"
drafts | put $((T + 30 * HOUR))
run $((T + 30 * HOUR))
drafts | put $((T + 35 * HOUR))
run $((T + 35 * HOUR))
expect_eq "a 6h window is not up after 5h" ""
sed -i.bak 's/^mission_control_stalled_pipeline_window:.*/mission_control_stalled_pipeline_window: soon/' "$tracked"
run $((T + 36 * HOUR))
expect_rc "a malformed repo-tracked window fails the pass" 1
sed -i.bak '/^mission_control_stalled_pipeline_window:/d' "$tracked"

# --- unreadable evidence still names the draft ------------------------------
rm -f "$runtime"/pipeline-stall*
: >"$tmp/broken.7"
drafts | put $((T + 40 * HOUR))
run $((T + 40 * HOUR))
drafts | put $((T + 42 * HOUR))
run $((T + 42 * HOUR))
ev=$(mc_run_events)
case $ev in *"evidence unread (1): acme/web#7"*) ok "a draft whose evidence cannot be collected is named as unread" ;; *) fail "unread draft not named: $ev" ;; esac

# --- a stale or absent snapshot raises nothing ------------------------------
rm -f "$runtime"/pipeline-stall* "$snapdir/forge"
run $((T + 50 * HOUR))
expect_rc "with no snapshot taken" 0
expect_eq "it waits quietly" ""

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
