#!/bin/bash
# Tests for scripts/mc-context.sh — a context reading for every
# mission-control session, taken from the tail of the transcript its registry
# row names: the percent of the window the last assistant message used, the
# window from the transcript, the context/<name> file or the knob, a host
# percent winning with its source named, the literal `unknown` where nothing
# can be read, and the runner's record that `mc-handover.sh due` reads.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-context.sh
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

if ! command -v jq >/dev/null 2>&1; then
  echo "test-mc-context: skipped (jq is not on PATH)"
  exit 0
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-context.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'chmod -R u+rwx "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
mchome="$tmp/mchome"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_home: $mchome
EOF

# 2026-11-01T12:00:00Z
NOW=1793534400

reg="$fleet/mission-control/sessions"
rt="$fleet/mission-control/alpha"
sj="$fleet/streamjson"
tr="$tmp/transcripts"
mkdir -p "$reg" "$rt" "$sj" "$tr" "$fleet/mission-control/context"

# row <name> <backend> [<transcript>|-] [<kind>]
row() {
  {
    printf 'format\t1\nname\t%s\nstate\tlaunched\ntoken\tt-%s\nprogram\talpha\nkind\t%s\nbackend\t%s\nlaunched\t%s\n' \
      "$1" "$1" "${4:-mission-control}" "$2" "$NOW"
    [ "${3:--}" = - ] || printf 'transcript\t%s\n' "$3"
  } >"$reg/$1"
}
# msg <id> <input> <cache read> <cache creation>: one assistant frame.
msg() {
  printf '{"type":"assistant","message":{"id":"%s","usage":{"input_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s,"output_tokens":5}}}\n' "$1" "$2" "$3" "$4"
}
win() { printf '{"type":"result","modelUsage":{"claude-opus-5-5":{"contextWindow":%s}}}\n' "$1"; }

# --- The reading from a transcript --------------------------------------
# Earlier messages are higher than the last; the last streams as three
# frames and the final frame is the one counted: (10000 + 60000 + 10000)
# of 200000 is 40%.
{
  msg a1 1000 150000 0
  msg m9 1 1 1
  msg m9 5000 20000 5000
  msg m9 10000 60000 10000
  win 200000
} >"$tr/one.jsonl"
row mc-alpha-mission-control-0000000001 tmux "$tr/one.jsonl"
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000001 --now "$NOW"
expect_rc "a read" 0
expect_eq "the last frame of the last message over the transcript's window" "context${tab}mc-alpha-mission-control-0000000001${tab}40${tab}transcript"

# --- The window order: transcript, the context/<name> file, the knob ------
{
  msg b1 20000 20000 0
} >"$tr/nowin.jsonl"
row mc-alpha-mission-control-0000000002 tmux "$tr/nowin.jsonl"
printf 'format\t1\nwindow\t100000\n' >"$fleet/mission-control/context/mc-alpha-mission-control-0000000002"
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000002 --now "$NOW"
expect_eq "no window in the transcript: the context file's" "context${tab}mc-alpha-mission-control-0000000002${tab}40${tab}transcript"

rm -f "$fleet/mission-control/context/mc-alpha-mission-control-0000000002"
printf 'mission_control_context_window: 80000\n' >>"$tracked"
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000002 --now "$NOW"
expect_eq "neither: the knob's" "context${tab}mc-alpha-mission-control-0000000002${tab}50${tab}transcript"
sed '/^mission_control_context_window/d' "$tracked" >"$tmp/tracked.new" && cat "$tmp/tracked.new" >"$tracked"

# --- The same reading on every backend ------------------------------------
mkdir -p "$sj/mc-alpha-mission-control-0000000003"
{
  msg c1 1000 1000 0
  msg c2 10000 60000 10000
  win 200000
} >"$sj/mc-alpha-mission-control-0000000003/events.jsonl"
row mc-alpha-mission-control-0000000003 stream-json -
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000003 --now "$NOW"
expect_eq "a stream-json session reads its capture, no path in the row" "context${tab}mc-alpha-mission-control-0000000003${tab}40${tab}transcript"

{
  msg d1 10000 60000 10000
  win 200000
} >"$tr/attended.jsonl"
row mc-alpha-mission-control-0000000004 attended "$tr/attended.jsonl"
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000004 --now "$NOW"
expect_eq "an attended session reads the same" "context${tab}mc-alpha-mission-control-0000000004${tab}40${tab}transcript"

# --- A host percent wins, and the source says so -------------------------
printf 'format\t1\nwritten\t%s\npercent\t55\nthreshold\t70\npid\t-\n' "$((NOW - 10))" >"$rt/context"
printf 'format\t1\nsession\tmc-alpha-mission-control-0000000001\nsince\t%s\ngeneration\t1\nkind\tregistry\n' "$NOW" >"$rt/holder"
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000001 --now "$NOW"
expect_eq "a fresh host percent wins over the differing transcript" "context${tab}mc-alpha-mission-control-0000000001${tab}55${tab}host"
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000003 --now "$NOW"
expect_eq "the host's percent belongs to the holder alone" "context${tab}mc-alpha-mission-control-0000000003${tab}40${tab}transcript"
printf 'format\t1\nwritten\t%s\npercent\t55\nthreshold\t70\npid\t-\n' "$((NOW - 4000))" >"$rt/context"
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000001 --now "$NOW"
expect_eq "a stale host percent is not used" "context${tab}mc-alpha-mission-control-0000000001${tab}40${tab}transcript"
rm -f "$rt/context" "$rt/holder"

# --- unknown, never 0 -----------------------------------------------------
row mc-alpha-mission-control-0000000005 tmux "$tmp/absent.jsonl"
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000005 --now "$NOW"
expect_eq "a missing transcript reads unknown" "context${tab}mc-alpha-mission-control-0000000005${tab}unknown${tab}-"
row mc-alpha-mission-control-0000000006 tmux -
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000006 --now "$NOW"
expect_eq "a tmux row that names no transcript reads unknown" "context${tab}mc-alpha-mission-control-0000000006${tab}unknown${tab}-"
printf '%s\n' 'not json' '{"type":"assistant","message":"x"}' >"$tr/bad.jsonl"
row mc-alpha-mission-control-0000000007 tmux "$tr/bad.jsonl"
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000007 --now "$NOW"
expect_eq "a transcript with no usable usage reads unknown" "context${tab}mc-alpha-mission-control-0000000007${tab}unknown${tab}-"
msg e1 1000 0 0 >"$tr/nowin2.jsonl"
row mc-alpha-mission-control-0000000008 tmux "$tr/nowin2.jsonl"
printf 'format\t1\nwindow\tmany\n' >"$fleet/mission-control/context/mc-alpha-mission-control-0000000008"
printf 'mission_control_context_window: lots\n' >>"$tracked"
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000008 --now "$NOW"
expect_eq "an unknown window reads unknown" "context${tab}mc-alpha-mission-control-0000000008${tab}unknown${tab}-"
sed '/^mission_control_context_window/d' "$tracked" >"$tmp/tracked.new" && cat "$tmp/tracked.new" >"$tracked"
ln -s "$tr/one.jsonl" "$tr/link.jsonl"
row mc-alpha-mission-control-0000000009 tmux "$tr/link.jsonl"
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000009 --now "$NOW"
expect_eq "a transcript that is a link reads unknown" "context${tab}mc-alpha-mission-control-0000000009${tab}unknown${tab}-"

# --- A path argument is refused; only the row's file, only its tail -------
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000001 "$tr/one.jsonl"
expect_rc "a transcript path as an argument" 2
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000001 --transcript "$tr/one.jsonl"
expect_rc "a --transcript flag" 2
mc_run mc-context.sh read --program alpha --session '../x' --now "$NOW"
expect_rc "a session name outside the grammar" 2
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000099 --now "$NOW"
expect_eq "a session with no row reads unknown" "context${tab}mc-alpha-mission-control-0000000099${tab}unknown${tab}-"

# A high message at the head, a megabyte of filler, a low message at the
# end: the tail holds only the low one.
{
  msg h1 190000 0 0
  win 400000
  i=0
  while [ "$i" -lt 12000 ]; do
    printf '{"type":"user","message":{"content":"%0100d"}}\n' "$i"
    i=$((i + 1))
  done
  msg h2 20000 0 0
} >"$tr/big.jsonl"
row mc-alpha-mission-control-0000000010 tmux "$tr/big.jsonl"
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000010 --now "$NOW"
expect_eq "only the tail is read (the head's window is out of it)" "context${tab}mc-alpha-mission-control-0000000010${tab}10${tab}transcript"

# --- Hostile text is data -------------------------------------------------
sentinel="$tmp/sentinel"
{
  # shellcheck disable=SC2016 # the sentinel commands must stay literal
  printf '{"type":"assistant","message":{"id":"$(touch %s)","model":"`touch %s`;touch %s","usage":{"input_tokens":10000,"cache_read_input_tokens":"$(touch %s)","cache_creation_input_tokens":0}}}\n' "$sentinel" "$sentinel" "$sentinel" "$sentinel"
  printf '{"type":"assistant","message":{"id":"\\u001b]0;x\\u0007\\u0000z","usage":{"input_tokens":20000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n'
  win 200000
} >"$tr/hostile.jsonl"
row mc-alpha-mission-control-0000000011 tmux "$tr/hostile.jsonl"
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000011 --now "$NOW"
expect_eq "hostile fields are read as data" "context${tab}mc-alpha-mission-control-0000000011${tab}10${tab}transcript"
if [ ! -e "$sentinel" ]; then ok "no sentinel was left"; else fail "a transcript field was executed"; fi
case $OUT in *"$(printf '\033')"*) fail "a control sequence reached the output" ;; *) ok "no control sequence in the output" ;; esac

# --- The runner's record, and due ------------------------------------------
rm -f "$reg"/*
row mc-alpha-mission-control-0000000001 tmux "$tr/one.jsonl"
row mc-alpha-mission-control-0000000002 tmux "$tmp/absent.jsonl"
row mc-alpha-worker-0000000003 tmux - worker
mc_run mc-context.sh record --program alpha --now "$NOW"
expect_rc "a record pass over two sessions" 0
expect_out "the readable one" "context${tab}mc-alpha-mission-control-0000000001${tab}40${tab}transcript"
expect_out "the unreadable one" "context${tab}mc-alpha-mission-control-0000000002${tab}unknown${tab}-"
expect_no_out "a worker is no mission-control session" "mc-alpha-worker-0000000003"
mc_run mc-context.sh recorded --program alpha --session mc-alpha-mission-control-0000000001 --now "$NOW"
expect_eq "the record is read back" "40"
mc_run mc-context.sh recorded --program alpha --session mc-alpha-mission-control-0000000002 --now "$NOW"
expect_eq "the unknown is recorded as unknown, not 0" "unknown"
mc_run mc-context.sh recorded --program alpha --session mc-alpha-mission-control-0000000001 --now $((NOW + 100000))
expect_eq "a record long past is unknown" "unknown"
mc_run mc-context.sh recorded --program alpha --session mc-alpha-mission-control-0000000077 --now "$NOW"
expect_eq "a session never recorded is unknown" "unknown"

# due: a recorded 41 against the trigger set to 40; unknown falls to wakes.
printf 'mission_control_handover_context: 40\nmission_control_handover_wakes: 3\n' >>"$tracked"
msg f1 82000 0 0 >"$tr/f41.jsonl"
row mc-alpha-mission-control-0000000001 tmux "$tr/f41.jsonl"
mc_run mc-context.sh record --program alpha --now "$NOW"
expect_out "the runner records 41" "context${tab}mc-alpha-mission-control-0000000001${tab}41${tab}transcript"
mc_run mc-handover.sh due --program alpha --session mc-alpha-mission-control-0000000001 --context - --wakes 0 --compactions 0 --now "$NOW"
expect_eq "what the runner recorded, 41 against 40, is due" "due${tab}context at 41%"
printf 'format\t1\nwritten\t%s\npercent\t39\nsource\ttranscript\n' "$NOW" >"$rt/readings/mc-alpha-mission-control-0000000001"
mc_run mc-handover.sh due --program alpha --session mc-alpha-mission-control-0000000001 --context - --wakes 9 --compactions 0 --now "$NOW"
expect_eq "a recorded 39 is not due, whatever the wakes" "not-due"
mc_run mc-handover.sh due --program alpha --session mc-alpha-mission-control-0000000002 --context - --wakes 3 --compactions 0 --now "$NOW"
expect_eq "an unknown reading falls back to the wake count" "due${tab}3 wakes"
mc_run mc-handover.sh due --program alpha --session mc-alpha-mission-control-0000000002 --context - --wakes 2 --compactions 0 --now "$NOW"
expect_eq "and not before the ceiling" "not-due"

# --- The attended session, pruning, and hostile numbers ---------------------
printf 'format\t1\nwritten\t%s\npercent\t55\nthreshold\t70\npid\t-\n' "$((NOW - 10))" >"$rt/context"
printf 'format\t1\nsession\top-x\nsince\t%s\ngeneration\t1\nkind\tattended\n' "$NOW" >"$rt/holder"
mc_run mc-context.sh read --program alpha --now "$NOW"
expect_eq "an attended session reads the host's percent" "context${tab}-${tab}55${tab}host"
mc_run mc-context.sh record --program alpha --now "$NOW"
expect_out "the runner records the attended session too" "context${tab}attended${tab}55${tab}host"
mc_run mc-context.sh recorded --program alpha --session attended --now "$NOW"
expect_eq "and its record is read back" "55"
rm -f "$rt/context" "$rt/holder" "$reg/mc-alpha-mission-control-0000000002"
mc_run mc-context.sh record --program alpha --now "$NOW"
if [ ! -e "$rt/readings/mc-alpha-mission-control-0000000002" ] && [ ! -e "$rt/readings/attended" ]; then
  ok "a record of a session no longer registered is dropped"
else
  fail "a stale record was kept"
fi
mc_run mc-context.sh read --program alpha --now "$NOW"
expect_eq "with no host percent an attended session reads unknown" "context${tab}-${tab}unknown${tab}-"

# A last frame that counts no input is no reading; the real one before it is.
{
  msg z1 82000 0 0
  msg z2 0 0 0
} >"$tr/zero.jsonl"
row mc-alpha-mission-control-0000000012 tmux "$tr/zero.jsonl"
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000012 --now "$NOW"
expect_eq "a synthetic zero-usage last frame does not hide the real one" "context${tab}mc-alpha-mission-control-0000000012${tab}41${tab}transcript"
# Negative and absurd token counts are read as zero, never as a percent.
printf '{"type":"assistant","message":{"id":"n1","usage":{"input_tokens":150000,"cache_read_input_tokens":-60000}}}\n' >"$tr/neg.jsonl"
row mc-alpha-mission-control-0000000013 tmux "$tr/neg.jsonl"
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000013 --now "$NOW"
expect_eq "a negative count does not lower the reading" "context${tab}mc-alpha-mission-control-0000000013${tab}75${tab}transcript"
printf '{"type":"assistant","message":{"id":"n2","usage":{"input_tokens":93000000000000000}}}\n' >"$tr/huge.jsonl"
row mc-alpha-mission-control-0000000014 tmux "$tr/huge.jsonl"
mc_run mc-context.sh read --program alpha --session mc-alpha-mission-control-0000000014 --now "$NOW"
expect_eq "an absurd count reads unknown, not a wrapped percent" "context${tab}mc-alpha-mission-control-0000000014${tab}unknown${tab}-"

# --- The panel's text form --------------------------------------------------
printf 'format\t1\nwritten\t%s\npercent\t41\nsource\ttranscript\n' "$NOW" >"$rt/readings/mc-alpha-mission-control-0000000001"
printf 'format\t1\nwritten\t%s\npercent\tunknown\nsource\t-\n' "$NOW" >"$rt/readings/mc-alpha-mission-control-0000000002"
mc_run mc-panel.sh text --program alpha --now "$NOW"
expect_out "the text panel prints the reading and its source" "context: mc-alpha-mission-control-0000000001 41% (transcript)"
expect_out "and unknown for a session with no transcript" "context: mc-alpha-mission-control-0000000002 unknown"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-context: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-context: all passed"
