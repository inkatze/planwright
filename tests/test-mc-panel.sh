#!/bin/bash
# Tests for scripts/mc-panel.sh, the panel mod's data seam and the text form
# it falls back to, and for scripts/mc-wake.sh compose, the wake the mod
# submits (mission-control REQ-E1.3, REQ-F1.1, REQ-F1.2, REQ-H1.4, REQ-L1.4,
# REQ-L1.5, REQ-M1.8; D-6, D-29).
#
# The mod's own drawing, wake and tick are covered by the plugin tests beside
# it (hooks/mission-control/*.test.tsx, scripts/check-panel-mod.sh); this
# suite proves the digest they draw from reads the real stores.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-panel.sh
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

[ -f "$repo_root/scripts/mc-panel.sh" ] || {
  echo "FAIL: scripts/mc-panel.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"
# shellcheck source=tests/lib/mc-snapshot-fixture.sh
. "$here/lib/mc-snapshot-fixture.sh"

record() { # record <label> <type> [<field>...]: stdout holds that record
  rc_label=$1
  shift
  rc_want=$(printf '%s\t' "$@")
  rc_want=${rc_want%"$tab"}
  if printf '%s\n' "$OUT" | grep -qxF -- "$rc_want"; then
    ok "$rc_label"
  else
    fail "$rc_label: no line '$rc_want'"
    printf '%s\n' "----- stdout -----" "$OUT" "----- stderr -----" "$ERR" "------------------" >&2
  fi
}

# ---------------------------------------------------------------------------
# compose: the wake the mod submits, its events never-sent first.
# ---------------------------------------------------------------------------
setup
mc_run mc-wake.sh compose --program alpha mc-alpha
expect_rc "compose with nothing pending" 0
expect_eq "REQ-E1.3: compose with nothing pending says idle" "idle"
mc_run mc-event.sh emit --program alpha --now 2000 pr-ready pr-7 "seven is ready"
e1=$OUT
mc_run mc-event.sh emit --program alpha --now 2001 unit-parked task-3 "parked on a fork"
e2=$OUT
mc_run mc-event.sh mark --program alpha --target mc-alpha staged "$e1"
mc_run mc-wake.sh compose --program alpha mc-alpha
expect_rc "compose with two pending" 0
first=$(printf '%s\n' "$OUT" | head -n 1)
if [ "$first" = "wake${tab}2${tab}$e2 $e1" ]; then
  ok "REQ-E1.3: compose names the count and the ids, a never-sent event first"
else
  fail "REQ-E1.3: compose's first line is '$first'"
fi
expect_out "the wake names each event's kind and subject" "- unit-parked task-3"
expect_out "the wake says how to read the events" "list --program alpha $e2 $e1"
expect_no_out "the wake carries no free text" "parked on a fork"
expect_no_out "a submitted wake asks for no acknowledgement" "acknowledge"
mc_run mc-event.sh mark --program alpha --target mc-alpha submitted "$e1" "$e2"
mc_run mc-wake.sh compose --program alpha mc-alpha
expect_eq "REQ-E1.3: submitted events leave the wake" "idle"
mc_run mc-wake.sh compose --program alpha 'bad;target'
expect_rc "compose refuses a target outside the grammar" 2

# ---------------------------------------------------------------------------
# digest: every store the panel draws, each source with its mode and age.
# ---------------------------------------------------------------------------
setup
mc_run mc-snapshot.sh refresh --program alpha --now 1000
mc_run mc-budget.sh report --program alpha --now 1000 --load 10
# Above any pid_max, so no process can hold it.
dead_pid=2147483646
mc_run fleet-state.sh register w-one mission-control:alpha --backend stream-json --death-handle "process $$"
mc_run fleet-state.sh register w-dead flight:fix --backend stream-json --death-handle "process $dead_pid"
mc_run fleet-state.sh register w-idle flight:done --backend stream-json --death-handle "process $$"
mc_run fleet-state.sh register w-stuck flight:hung --backend stream-json --death-handle "process $$"
mc_run fleet-state.sh register w-done flight:landed --backend stream-json --death-handle "process $$"
mc_run fleet-state.sh register w-win flight:named-window --backend tmux --death-handle "tmux-window other w7"
mc_run fleet-state.sh register w-idname flight:id-like-name --backend tmux --death-handle "tmux-window named @9"
mc_run fleet-state.sh register w-print flight:once --backend print --death-handle none
mc_run fleet-state.sh register w-tmux flight:tmux --backend tmux --death-handle "tmux-window mc @5"
mc_run fleet-state.sh register w-tmux-gone flight:tmux-old --backend tmux --death-handle "tmux-window mc @9"
mc_run fleet-state.sh register w-gone mission-control:alpha --backend tmux --death-handle "tmux-window mc 4"
mc_run fleet-state.sh retire w-gone mission-control:alpha --backend tmux --death-handle "tmux-window mc 4"
mc_run mc-event.sh emit --program alpha --now 1000 pr-ready pr-7
# A live session whose observed name is `closed` (nine fields), and one
# known only by a legacy three-field record.
printf '900\tw-named\tflight:docs\t-\tstream-json\t-\tprocess %s\tclosed\t-\n900\tw-legacy\tflight:old\n' "$$" >>"$fleet/registry"
# Hand-appended rows: an empty scope, and pid 1, which is never a worker.
printf '900\tw-empty\t\t-\tstream-json\t-\tprocess %s\n900\tw-init\tflight:init\t-\tstream-json\t-\tprocess 1\n' "$$" >>"$fleet/registry"
# w-one is parked on a question, w-idle went idle with its process still
# up, w-stuck stopped responding. The dead w-dead's stale awaiting row
# still counts in the operator queue, its own reader, but never puts w-dead
# in flight.
mkdir -p "$fleet/attention"
{
  printf 'w-one\tmission-control:alpha\tawaiting-input\t1000\n'
  printf 'w-dead\tflight:fix\tawaiting-input\t900\n'
  printf 'w-idle\tflight:done\tidle\t900\n'
  printf 'w-stuck\tflight:hung\thung\t900\n'
  printf 'w-done\tflight:landed\tdone\t900\n'
} >"$fleet/attention/state"
# The tmux server lists window @5, its session since renamed, and not @9.
# The other two stand for a server that does not answer and one not running.
mkdir -p "$tmp/bin" "$tmp/bin-down" "$tmp/bin-none"
printf '#!/bin/sh\ncase "$*" in *list-windows*) printf "renamed\\t@5\\tw5\\nother\\t@7\\tw7\\nnamed\\t@3\\t@9\\n" ;; *) exit 1 ;; esac\n' >"$tmp/bin/tmux"
printf '#!/bin/sh\necho "server exited unexpectedly" >&2\nexit 1\n' >"$tmp/bin-down/tmux"
printf '#!/bin/sh\necho "no server running on /tmp/tmux-0/default" >&2\nexit 1\n' >"$tmp/bin-none/tmux"
chmod +x "$tmp/bin/tmux" "$tmp/bin-down/tmux" "$tmp/bin-none/tmux"
host_path=$PATH
PATH="$tmp/bin:$host_path"
home=$fixhome/.config/planwright/mission-control/alpha
mkdir -p "$home/kb"
printf '<!-- format: 1 -->\n- %s: an entry\n' "\`a.md\`" >"$home/kb/index.md"
TZ=UTC touch -t 197001010015.00 "$home/kb/index.md"
{
  printf '# format: 1\n'
  printf 'decisions-197001-1\t1970-01-01T00:10:00Z\tflip pr-7\tready-flip\tpr-7\tgreen\tnone\t-\n'
  printf 'decisions-197001-2\t1970-01-01T00:11:00Z\tmerge order\tretarget\tpr-9\tbase merged\tnone\t-\n'
} >"$home/kb/decisions-1970-01.log"
{
  printf '# format: 1\n'
  printf 'decisions-197002-1\t1970-02-01T00:10:00Z\tpark task-3\tpark\ttask-3\tfork\tnone\t-\n'
  printf 'decisions-197002-2\t1970-02-01T00:15:00Z\trelaunch w-one\trelaunch\tw-one\tstalled\tnone\tsession-keeper\n'
} >"$home/kb/decisions-1970-02.log"
runtime=$fleet/mission-control/alpha
printf 'format\t1\ntaken\t900\ninterruptions_per_hour\t2.5\nsettled_share\t80\n' >"$runtime/measures"
# A watcher record whose loop is gone, its last run at 600 on a 5m cadence.
mkdir -p "$runtime/watchers"
printf '999999\t500\talpha-duty\tscripts/alpha-watch.sh\t5m\tlow\n' >"$runtime/watchers/alpha-duty.alpha-watch.rec"
printf '600\t0\t0\n' >"$runtime/watchers/alpha-duty.alpha-watch.last"

mc_run mc-panel.sh digest --program alpha --target mc-alpha --knobs --now 1030
expect_rc "the digest" 0
record "the digest opens with its format" format 1
record "the digest names its program" program alpha
record "the digest is stamped" taken 1030
record "REQ-F1.1: a live session parked on a question is in flight, waiting" flight w-one mission-control:alpha stream-json waiting
expect_no_out "a retired session is not in flight" "w-gone"
record "a live session named closed stays in flight" flight w-named flight:docs stream-json working
record "a live tmux window is in flight, found by its id in a renamed session" flight w-tmux flight:tmux tmux working
record "a live session that stopped responding is in flight, stuck" flight w-stuck flight:hung stream-json stuck
expect_no_out "a session gone idle is not in flight" "w-idle"
expect_no_out "a session whose work is done is not in flight" "w-done"
record "a tmux window named in its session is in flight" flight w-win flight:named-window tmux working
record "a window whose name looks like an id is found by name" flight w-idname flight:id-like-name tmux working
record "an empty field keeps the columns" flight w-empty - stream-json working
expect_no_out "pid 1 is never a live worker" "w-init"
expect_no_out "a session whose process is gone is not in flight" "w-dead"
expect_no_out "a tmux window the server does not list is not in flight" "w-tmux-gone"
expect_no_out "a record with no process to watch is not in flight" "w-print"
expect_no_out "a legacy three-field record is not in flight" "w-legacy"
record "the rest are finished, not cleaned up" finished 7
expect_no_out "a tmux server that answers is readable" "tmux windows"
record "REQ-F1.1: what waits on the operator" waiting 2
record "REQ-E1.3: the target's pending events" pending 1
got=$(printf '%s\n' "$OUT" | awk -F '\t' '$1 == "decision" { printf "%s|", $2 }')
if [ "$got" = "1970-02-01T00:15:00Z|1970-02-01T00:10:00Z|1970-01-01T00:11:00Z|" ]; then
  ok "REQ-F1.1: the three newest decisions, newest first, across segments"
else
  fail "REQ-F1.1: decisions read '$got'"
fi
record "a decision carries its subject and act" decision 1970-02-01T00:15:00Z "relaunch w-one" relaunch
record "REQ-L1.4: the budget rung" rung normal "every dimension under the throttle threshold"
expect_out "REQ-L1.4: headroom per dimension" "headroom${tab}polls_per_hour${tab}"
record "REQ-L1.4: a watcher's expiry, a next run already passed" watcher alpha-duty alpha-watch.sh stopped -130
record "REQ-H1.4: the forge source with its mode and age" source code-state forge snapshot 30
record "REQ-H1.4: a record source carries no age" source decisions specs record -
record "REQ-H1.4: a class with no source is cited" source designs - cited -
record "REQ-F1.1: knowledge-base freshness, the index's age" kb 130
record "REQ-M1.8: interruptions per hour, with their age" measure interruptions_per_hour 2.5 130
record "REQ-M1.8: the settled share" measure settled_share 80 130
record "REQ-L1.5: the context threshold knob" knob handover-context 70
record "REQ-L1.5: the wake ceiling knob" knob handover-wakes 150
record "REQ-L1.5: the compaction ceiling knob" knob handover-compactions 2
record "the redraw cadence knob, in seconds" knob refresh 10
record "the tick cadence knob, in seconds" knob tick 300
record "the reviews TTL knob, in seconds" knob reviews-ttl 300
record "D-29: the handover verb is installed" handover available
record "REQ-F1.2: the text line" line "mission control alpha: 7 in flight, 2 waiting, 1 pending, rung normal, tracker snapshot 30s old"
mc_run mc-panel.sh digest --program alpha --now 1030
expect_no_out "knobs only with --knobs" "knob${tab}"

# The text form alone, as a session without the mod reads it.
mc_run mc-panel.sh line --program alpha --target mc-alpha --now 1030
expect_rc "the line" 0
expect_eq "REQ-F1.2: the line form, one line" "mission control alpha: 7 in flight, 2 waiting, 1 pending, rung normal, tracker snapshot 30s old"
PATH="$tmp/bin-down:$host_path"
mc_run mc-panel.sh digest --program alpha --now 1030
record "a tmux server that does not answer is unreadable" unreadable "tmux windows"
expect_no_out "and none of its windows is in flight" "w-tmux"
record "nor counted finished" finished 6
expect_out "and the count says it may be more" "4+ in flight"
mc_run mc-panel.sh text --program alpha
expect_out "the text panel says the count may be more" "in flight: 4 or more (tmux does not answer)"
PATH="$tmp/bin-none:$host_path"
mc_run mc-panel.sh digest --program alpha --now 1030
expect_no_out "a tmux server not running is no fault" "tmux windows"
record "and its windows are finished" finished 10
PATH="$tmp/bin:$host_path"
mv "$fleet/attention/state" "$fleet/attention/state.real"
ln -s "$fleet/attention/state.real" "$fleet/attention/state"
mc_run mc-panel.sh digest --program alpha --now 1030
record "a symlinked attention store is unreadable" unreadable "attention store"
expect_out "and the count, counting idle sessions it cannot tell apart, says it may be fewer" "up to 9 in flight"
mc_run mc-panel.sh text --program alpha
expect_out "the text panel says the count may be fewer" "in flight: up to 9 (the attention store cannot be read)"
PATH="$tmp/bin-down:$host_path"
mc_run mc-panel.sh digest --program alpha --now 1030
expect_out "with the tmux server not answering as well, the count is unknown" "alpha: ? in flight"
mc_run mc-panel.sh text --program alpha
expect_out "and the text panel says so" "in flight: unknown (neither tmux nor the attention store can be read)"
PATH="$tmp/bin:$host_path"
rm -f "$fleet/attention/state"
mv "$fleet/attention/state.real" "$fleet/attention/state"
# With every tmux row's work ended, a server that does not answer leaves
# nothing unknown: no fault, and an exact count the panel draws the same.
cp "$fleet/attention/state" "$tmp/attention.saved"
for w in w-win w-idname w-tmux w-tmux-gone; do printf '%s\tflight:x\tdone\t900\n' "$w" >>"$fleet/attention/state"; done
PATH="$tmp/bin-down:$host_path"
mc_run mc-panel.sh digest --program alpha --now 1030
expect_no_out "a silent tmux server no row depends on is no fault" "tmux windows"
expect_out "and the count is exact" "alpha: 4 in flight"
PATH="$tmp/bin:$host_path"
cp "$tmp/attention.saved" "$fleet/attention/state"

# Worker permission prompts are mission control's to answer: they leave the
# operator's waiting count and are said apart, in plain words. The fixture
# already holds two rows awaiting the operator; one more question joins them.
mc_run fleet-attention.sh permission w-perm mission-control:alpha 'git status'
mc_run fleet-attention.sh decide w-req mission-control:alpha "permission request tool Bash req aaaa1111 - answer via fleet-streamjson.sh answer" deny 'allow|deny'
mc_run fleet-attention.sh decide w-ask mission-control:alpha 'Ship it?' yes 'yes|no'
mc_run mc-panel.sh digest --program alpha --target mc-alpha --now 1030
record "the operator's waiting count leaves out worker permission prompts" waiting 3
record "the approvals mission control is handling are counted apart" approvals 2
mc_run mc-panel.sh line --program alpha --target mc-alpha --now 1030
expect_eq "the line form says the approvals apart from what waits on the operator" "mission control alpha: 7 in flight, 3 waiting, 1 pending, 2 approvals mission control is handling, rung normal, tracker snapshot 30s old"
mc_run mc-panel.sh text --program alpha --target mc-alpha
expect_out "the text panel says what waits on the operator" "waiting on you: 3"
expect_out "the text panel says the approvals apart" "approvals mission control is handling: 2"
mc_run fleet-attention.sh clear w-req
mc_run mc-panel.sh line --program alpha --target mc-alpha --now 1030
expect_out "one approval is said in the singular" ", 1 approval mission control is handling,"
# A queue that cannot be read is said so, with no split and no clause, while
# an approval is still pending in it.
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$fleet/attention/state"
  mc_run mc-panel.sh digest --program alpha --target mc-alpha --now 1030
  chmod 600 "$fleet/attention/state"
  record "an unreadable queue is named" unreadable "operator queue"
  expect_no_out "and no approvals are counted from it" "approvals${tab}"
  expect_no_out "nor said in the line" "mission control is handling"
fi
for w in w-perm w-ask; do mc_run fleet-attention.sh clear "$w"; done

# A store that cannot be read is said, never drawn as empty.
printf 'format\t9\n' >"$runtime/measures"
mc_run mc-panel.sh digest --program alpha --now 1030
record "a measures file of an unknown format is refused, named" measure - unreadable -
expect_no_out "no pending count without a target" "pending${tab}"
rm -f "$runtime/measures"
mc_run mc-panel.sh digest --program alpha --now 1030
record "REQ-M1.8: no measures yet" measure - none -

# Stored text never reaches a terminal raw.
printf 'decisions-197002-3\t1970-01-01T00:20:00Z\tbad \033[2Jsubject\tact\tx\ty\tnone\t-\n' >>"$home/kb/decisions-1970-02.log"
mc_run mc-panel.sh digest --program alpha --now 1030
case $OUT in
  *"$(printf '\033')"*) fail "a control byte reached the digest" ;;
  *) ok "control bytes are dropped from stored text" ;;
esac

# A segment of an unknown format, or a symlinked knowledge base, is
# unreadable, never drawn.
printf '# format: 9\n' >"$home/kb/decisions-1970-03.log"
mc_run mc-panel.sh digest --program alpha --now 1030
record "a segment of an unknown format is unreadable" unreadable "decisions log"
expect_no_out "and none of its decisions are drawn" "decision${tab}"
rm -f "$home/kb/decisions-1970-03.log"
mv "$home/kb" "$home/kb.real"
ln -s "$home/kb.real" "$home/kb"
mc_run mc-panel.sh digest --program alpha --now 1030
record "a symlinked knowledge base is unreadable" unreadable "decisions log"
record "and its freshness is unreadable, not unwritten" unreadable "knowledge base"
rm -f "$home/kb"
mc_run mc-panel.sh digest --program alpha --now 1030
record "no index yet reads as not written" kb -
mv "$home/kb.real" "$home/kb"

# A handover ceiling of 0 would fire at once: refused like any invalid value.
printf 'mission_control_handover_compactions: 0\n' >>"$tracked"
mc_run mc-panel.sh digest --program alpha --knobs --now 1030
record "a zero compaction ceiling is refused" unreadable "knob mission_control_handover_compactions"
setup_tracked=$(grep -v '^mission_control_handover_compactions' "$tracked")
printf '%s\n' "$setup_tracked" >"$tracked"

# REQ-L1.8: the holder record's kind tells a launched holder, which hands
# over, from the operator's own session, which compacts.
mc_run mc-panel.sh digest --program alpha --now 1030
record "REQ-L1.8: no holder record reads as none" holder -
printf 'format\t1\nsession\tmc-alpha-attended-1\nkind\tattended\nsince\t900\ngeneration\t1\n' >"$runtime/holder"
mc_run mc-panel.sh digest --program alpha --now 1030
record "REQ-L1.8: the operator's own session is an attended holder" holder attended
printf 'format\t1\nsession\tmc-alpha-gen-1\nkind\tregistry\nsince\t900\ngeneration\t2\n' >"$runtime/holder"
mc_run mc-panel.sh digest --program alpha --now 1030
record "REQ-L1.8: a launched session is a registry holder" holder registry
printf 'format\t1\nsession\tmc-alpha-gen-1\nkind\tbogus\nsince\t900\ngeneration\t2\n' >"$runtime/holder"
mc_run mc-panel.sh digest --program alpha --now 1030
record "a holder record naming an unknown kind is unreadable" unreadable "holder record"
printf 'format\t1\nsession\tmc-alpha-gen-1\nkind\tregistry\nsince\tsoon\ngeneration\t2\n' >"$runtime/holder"
mc_run mc-panel.sh digest --program alpha --now 1030
record "a holder record outside its grammar is unreadable, never launched" holder -
printf 'format\t1\nsession\tmc-alpha-gen-1\nkind\tattended\nkind\tregistry\nsince\t900\ngeneration\t2\n' >"$runtime/holder"
mc_run mc-panel.sh digest --program alpha --now 1030
record "the first kind line is the one read, as the handover script reads it" holder attended
printf 'format\t1\nsession\tmc-alpha-gen-1\textra\nkind\tregistry\nsince\t900\ngeneration\t2\n' >"$runtime/holder"
mc_run mc-panel.sh digest --program alpha --now 1030
record "a field with a trailing column is outside the grammar" holder -
printf 'format\t9\nkind\tregistry\n' >"$runtime/holder"
mc_run mc-panel.sh digest --program alpha --now 1030
record "a holder record of an unknown format is unreadable" unreadable "holder record"
record "and its kind is unknown, never launched" holder -
rm -f "$runtime/holder"

mc_run mc-panel.sh digest --program beta
expect_rc "an unconfigured program" 3
mc_run mc-panel.sh digest --program alpha --target 'bad;t'
expect_rc "a target outside the grammar" 2

# ---------------------------------------------------------------------------
# presence: the producer marker the operator queue reads.
# ---------------------------------------------------------------------------
mc_run mc-panel.sh presence --program alpha --prompt --now 4000
expect_rc "a prompt event is recorded" 0
pres=$runtime/presence
if [ "$(cat "$pres" 2>/dev/null)" = "$(printf 'format\t1\nproducer\tmission-control-panel\nwritten\t4000\nlast-prompt\t4000')" ]; then
  ok "REQ-F1.4 input: the prompt event lands in the presence marker"
else
  fail "unexpected presence marker: $(cat "$pres" 2>/dev/null)"
fi
mc_run mc-panel.sh presence --program alpha --refresh --now 4100
case $(cat "$pres") in
  *"written${tab}4100"*"last-prompt${tab}4000"*) ok "a refresh keeps the last prompt and restamps the producer" ;;
  *) fail "the refresh lost the prompt time: $(cat "$pres")" ;;
esac
rm -f "$pres"
mc_run mc-panel.sh presence --program alpha --refresh --now 4200
case $(cat "$pres") in
  *"last-prompt${tab}-"*) ok "a refresh before any prompt records none" ;;
  *) fail "unexpected first refresh: $(cat "$pres")" ;;
esac
mc_run mc-panel.sh presence --program alpha --now 4200
expect_rc "presence needs --prompt or --refresh" 2
mc_run mc-panel.sh presence --program alpha --refresh --target mc-alpha --now 4300
if [ "$(cat "$runtime/leases/mc-alpha" 2>/dev/null)" = 4300 ]; then
  ok "a target's lease is restamped with the marker"
else
  fail "the lease reads '$(cat "$runtime/leases/mc-alpha" 2>/dev/null)'"
fi

mv "$runtime/leases" "$runtime/leases.real"
ln -s "$runtime/leases.real" "$runtime/leases"
mc_run mc-panel.sh presence --program alpha --refresh --target mc-alpha --now 4400
expect_rc "a symlinked lease directory is refused" 1
if [ "$(cat "$runtime/leases.real/mc-alpha")" = 4300 ]; then ok "and nothing is written through it"; else fail "a lease was written through the symlink"; fi
rm -f "$runtime/leases"
mv "$runtime/leases.real" "$runtime/leases"

# A store that is a symlink is unreadable, never unwritten.
mv "$runtime/budget" "$runtime/budget.saved"
ln -s "$tmp/nowhere" "$runtime/budget"
ln -s "$tmp/nowhere" "$runtime/measures"
mc_run mc-panel.sh digest --program alpha --now 1030
record "a symlinked budget is unreadable" unreadable budget
record "symlinked measures are unreadable" measure - unreadable -
rm -f "$runtime/budget" "$runtime/measures"
mv "$runtime/budget.saved" "$runtime/budget"
printf 'format\t1\ntaken\t900\n' >"$runtime/measures"
mc_run mc-panel.sh digest --program alpha --now 1030
record "measures with no rows read as none" measure - none -
rm -f "$runtime/measures"

# ---------------------------------------------------------------------------
# install: the planwright copy the program's session runs, compared with the
# one recorded, raising one event per change with the changelog between.
# ---------------------------------------------------------------------------
fake_root() { # fake_root <dir> <version>: a planwright copy carrying the changelog below
  mkdir -p "$1/.claude-plugin"
  printf '{\n  "name": "planwright",\n  "version": "%s"\n}\n' "$2" >"$1/.claude-plugin/plugin.json"
  cat >"$1/CHANGELOG.md" <<'EOF'
# Changelog

## [0.66.0](https://example.test/compare/v0.65.0...v0.66.0) (2026-11-05)


### Features

* **fleet:** read usage from the status-line mirror ([#836](https://example.test/issues/836)) ([7d97218](https://example.test/commit/7d97218))


### Bug Fixes

* **mission-control:** make the panel reopenable with /mc-panel ([#828](https://example.test/issues/828)) ([db7e669](https://example.test/commit/db7e669))
* plain entry without a scope ([#900](https://example.test/issues/900)) ([abc1234](https://example.test/commit/abc1234))

## [0.65.0](https://example.test/compare/v0.64.0...v0.65.0) (2026-11-04)


### Features

* **mission-control:** show reviews at a glance in the panel ([#809](https://example.test/issues/809)) ([6862c17](https://example.test/commit/6862c17))

## [0.64.0](https://example.test/compare/v0.63.0...v0.64.0) (2026-11-03)


### Features

* **skills:** add the mission-control skill ([#796](https://example.test/issues/796)) ([a2d0ba0](https://example.test/commit/a2d0ba0))
EOF
}
events_of() { # events_of <kind>: the program's events of that kind
  mc_run mc-event.sh list --program alpha
  printf '%s\n' "$OUT" | awk -F '\t' -v k="$1" '$3 == k'
}
old_root=$tmp/cache/planwright/0.65.0
new_root=$tmp/cache/planwright/0.66.0
fake_root "$old_root" 0.65.0
fake_root "$new_root" 0.66.0
rm -f "$runtime/install"

mc_run mc-panel.sh install --program alpha --root "$old_root" --now 5000
expect_rc "the first install check" 0
expect_eq "the first check records the copy and says so" "install${tab}first${tab}0.65.0${tab}$old_root"
got=$(events_of planwright-recorded)
case $got in
  *"planwright 0.65.0 is at $old_root"*) ok "the first check raises one recorded event naming the root" ;;
  *) fail "the first check's event reads '$got'" ;;
esac

mc_run mc-panel.sh install --program alpha --root "$old_root" --now 5010
expect_eq "the same copy again is the same" "install${tab}same${tab}0.65.0${tab}$old_root"
if [ "$(events_of planwright-recorded | wc -l | tr -d ' ')" = 1 ] && [ -z "$(events_of planwright-updated)" ]; then
  ok "the same copy raises nothing more"
else
  fail "the same copy raised an event"
fi

mc_run mc-panel.sh install --program alpha --root "$new_root" --now 5020
expect_rc "an updated copy" 0
expect_eq "an update names both versions" "install${tab}changed${tab}0.66.0${tab}$new_root${tab}0.65.0"
got=$(events_of planwright-updated)
case $got in
  *"planwright updated to 0.66.0 from 0.65.0, now at $new_root"*) ok "the update event names both versions and the new root" ;;
  *) fail "the update event reads '$got'" ;;
esac
case $got in
  *"mission-control: make the panel reopenable with /mc-panel (#828)"*"plain entry without a scope (#900)"*) ok "the update event carries the changelog entries between the two" ;;
  *) fail "the update event lacks the entries: '$got'" ;;
esac
case $got in
  *"(#809)"*) fail "the update event carries an entry of the version it came from" ;;
  *) ok "the entries stop at the version it came from" ;;
esac
case $got in
  *"https://"*) fail "the update event carries link targets" ;;
  *) ok "the entries are plain text, no link targets" ;;
esac
mc_run mc-panel.sh install --program alpha --root "$new_root" --now 5030
expect_eq "a reload into the same copy is the same" "install${tab}same${tab}0.66.0${tab}$new_root"
if [ "$(events_of planwright-updated | wc -l | tr -d ' ')" = 1 ]; then
  ok "one change is announced once"
else
  fail "a change was announced more than once"
fi

mc_run mc-panel.sh install --program alpha --root "$old_root" --now 5040
expect_eq "a downgrade is a change too" "install${tab}changed${tab}0.65.0${tab}$old_root${tab}0.66.0"
case $(events_of planwright-updated | tail -n 1) in
  *"planwright changed to 0.65.0 from 0.66.0 (an older version), now at $old_root"*) ok "a downgrade says it is older" ;;
  *) fail "the downgrade event reads '$(events_of planwright-updated | tail -n 1)'" ;;
esac
case $(events_of planwright-updated | tail -n 1) in
  *"Changes:"*) fail "a downgrade lists the newer version's entries" ;;
  *) ok "a downgrade lists no entries of the version it left" ;;
esac

moved=$tmp/elsewhere/0.65.0
fake_root "$moved" 0.65.0
mc_run mc-panel.sh install --program alpha --root "$moved" --now 5050
expect_eq "a copy moved at one version is a change" "install${tab}changed${tab}0.65.0${tab}$moved${tab}0.65.0"
case $(events_of planwright-updated | tail -n 1) in
  *"planwright 0.65.0 moved to $moved from $old_root"*) ok "a move names both roots" ;;
  *) fail "the move event reads '$(events_of planwright-updated | tail -n 1)'" ;;
esac

# A refused emit records nothing, so the change is raised on the next check;
# a record that cannot be written stores no event. Root writes through any
# mode, so these run unprivileged only.
mc_run mc-panel.sh install --program alpha --root "$moved" --now 5060
store=$fleet/attention/mission-control/alpha
if [ "$(id -u)" -ne 0 ]; then
  chmod 500 "$store/events"
  mc_run mc-panel.sh install --program alpha --root "$new_root" --now 5070
  chmod 700 "$store/events"
  expect_rc "a refused event fails the check" 1
  expect_err "naming the event" "event could not be stored"
  set +f
  # shellcheck disable=SC2086 # the glob is the point
  set -- $runtime/install.*
  set -f
  if [ -e "$1" ]; then fail "a refused event left a temporary record: $1"; else ok "and leaves no temporary record"; fi
  before=$(events_of planwright-updated | wc -l | tr -d ' ')
  chmod 500 "$runtime"
  mc_run mc-panel.sh install --program alpha --root "$new_root" --now 5075
  chmod 700 "$runtime"
  expect_rc "a record that cannot be written fails the check" 1
  expect_err "naming the record" "cannot write the install record"
  if [ "$(events_of planwright-updated | wc -l | tr -d ' ')" = "$before" ]; then
    ok "and stores no event, so a retry cannot flood the store"
  else
    fail "an unwritable record still stored an event"
  fi
else
  echo "skip: the refused-write cases (root writes through any mode)"
fi
mc_run mc-panel.sh install --program alpha --root "$new_root" --now 5080
expect_eq "and the change is raised on the next one" "install${tab}changed${tab}0.66.0${tab}$new_root${tab}0.65.0"

# A record this script did not write is replaced as if absent, never trusted
# and never a lasting failure.
mkdir -p "$tmp/outside"
for shape in bad-format no-version bad-root symlink dirlink control; do
  rm -f "$runtime/install"
  case $shape in
    bad-format) printf 'format\t9\nroot\t%s\nversion\t0.65.0\n' "$old_root" >"$runtime/install" ;;
    no-version) printf 'format\t1\nroot\t%s\n' "$old_root" >"$runtime/install" ;;
    bad-root) printf 'format\t1\nroot\trelative\nversion\t0.65.0\n' >"$runtime/install" ;;
    symlink) ln -s "$tmp/nowhere" "$runtime/install" ;;
    dirlink) ln -s "$tmp/outside" "$runtime/install" ;;
    control) printf 'format\t1\nroot\t%s\nversion\t0.65.0\033]0;x\007\n' "$old_root" >"$runtime/install" ;;
  esac
  mc_run mc-panel.sh install --program alpha --root "$new_root" --now 5085
  expect_eq "a $shape record is replaced as a first record" "install${tab}first${tab}0.66.0${tab}$new_root"
  expect_err "with a warning naming it" "unreadable and is replaced"
  if [ "$shape" = symlink ] || [ "$shape" = dirlink ]; then
    if [ -L "$runtime/install" ]; then
      fail "the record is still a symlink"
    else
      ok "the replaced symlink is now a record of its own"
    fi
  fi
done
mc_run mc-panel.sh install --program alpha --root "$new_root" --now 5086
expect_eq "and the replaced record reads back" "install${tab}same${tab}0.66.0${tab}$new_root"
if [ -z "$(ls -A "$tmp/outside")" ]; then ok "nothing was written through a linked record"; else fail "a record was written through the link"; fi
rm -f "$runtime/install"
mkdir "$runtime/install"
mc_run mc-panel.sh install --program alpha --root "$new_root" --now 5087
expect_rc "a directory where the record goes fails" 1
expect_err "naming it" "the install record is a directory"
rmdir "$runtime/install"
mc_run mc-panel.sh install --program alpha --root "$new_root" --now 5088

mkdir -p "$tmp/noversion"
mc_run mc-panel.sh install --program alpha --root "$tmp/noversion" --now 5090
expect_rc "a copy with no readable version fails" 1
expect_err "naming why" "no version"
mc_run mc-panel.sh install --program alpha --root "$tmp/nowhere" --now 5090
expect_rc "a root that is no directory fails" 1

# A long changelog is cut to the event store's cap, never refused.
long_root=$tmp/cache/planwright/0.70.0
fake_root "$long_root" 0.70.0
{
  printf '# Changelog\n\n## [0.70.0](https://example.test) (2026-12-01)\n\n### Features\n\n'
  i=0
  while [ "$i" -lt 40 ]; do
    printf '* **area-%s:** a long entry describing change number %s in detail ([#%s](https://example.test))\n' "$i" "$i" "$i"
    i=$((i + 1))
  done
  sed -n '/^## \[0.66.0\]/,$p' "$new_root/CHANGELOG.md"
} >"$long_root/CHANGELOG.md"
mc_run mc-panel.sh install --program alpha --root "$long_root" --now 5100
expect_rc "a long changelog" 0
got=$(events_of planwright-updated | tail -n 1 | cut -f5)
if [ "${#got}" -le 512 ] && [ "${#got}" -gt 400 ]; then
  ok "a long changelog is cut to the store's cap"
else
  fail "the long event is ${#got} bytes"
fi
case $got in
  *...) ok "a cut text says it was cut" ;;
  *) fail "the cut text does not end in ...: '$got'" ;;
esac

# A copy without a changelog still announces the update, with no entries.
bare_root=$tmp/cache/planwright/0.71.0
fake_root "$bare_root" 0.71.0
rm -f "$bare_root/CHANGELOG.md"
mc_run mc-panel.sh install --program alpha --root "$bare_root" --now 5110
expect_rc "an update to a copy with no changelog" 0
case $(events_of planwright-updated | tail -n 1) in
  *"planwright updated to 0.71.0 from 0.70.0, now at $bare_root") ok "names the update without entries" ;;
  *) fail "the changelog-less event reads '$(events_of planwright-updated | tail -n 1)'" ;;
esac
mc_run mc-panel.sh changes --from 0.70.0 --root "$bare_root"
expect_rc "changes with no changelog fails, never reads as no change" 1

# changes: the full list the event's text was cut from.
mc_run mc-panel.sh changes --from 0.64.0 --root "$new_root"
expect_rc "changes since an older version" 0
expect_eq "every entry after the version, newest first, one per line" "$(printf 'change\t0.66.0\tFeatures\tfleet: read usage from the status-line mirror (#836)\nchange\t0.66.0\tBug Fixes\tmission-control: make the panel reopenable with /mc-panel (#828)\nchange\t0.66.0\tBug Fixes\tplain entry without a scope (#900)\nchange\t0.65.0\tFeatures\tmission-control: show reviews at a glance in the panel (#809)')"
mc_run mc-panel.sh changes --from 0.66.0 --root "$new_root"
expect_eq "nothing after the current version" ""
mc_run mc-panel.sh changes --from 0.64.0 --root "$old_root"
expect_eq "entries newer than the copy itself are never listed" "$(printf 'change\t0.65.0\tFeatures\tmission-control: show reviews at a glance in the panel (#809)')"
odd_root=$tmp/cache/planwright/odd
fake_root "$odd_root" 0.66.0
cat >"$odd_root/CHANGELOG.md" <<'EOF'
## [Unreleased]

### Features

* unreleased entry

## [0.66.0](https://example.test/compare/v0.65.0...v0.66.0) (2026-11-05)

### Features

* released entry

## [0.66.0-rc.1](https://example.test/compare/v0.65.0...v0.66.0-rc.1) (2026-11-04)

### Features

* pre-release entry

## [0.65.0](https://example.test/compare/v0.64.0...v0.65.0) (2026-11-03)

### Features

* older entry
EOF
mc_run mc-panel.sh changes --from 0.65.0 --root "$odd_root"
expect_eq "a header outside the version grammar ends the section before it" "$(printf 'change\t0.66.0\tFeatures\treleased entry')"
mc_run mc-panel.sh changes --from 'x;y' --root "$new_root"
expect_rc "a version outside the grammar" 2
for bad in "changes --root $new_root" "changes --from 0.64.0 --program alpha" "install --program alpha --from 0.64.0" \
  "install --program alpha --knobs" "install --program alpha --root relative/dir" "digest --program alpha --root $new_root" \
  "changes --from 1.2.3.4 --root $new_root"; do
  # shellcheck disable=SC2086 # each case is a word list on purpose
  mc_run mc-panel.sh $bad
  expect_rc "usage refused: $bad" 2
done
mc_run mc-panel.sh install --program nosuch --root "$tmp/nowhere"
expect_rc "an unconfigured program is named before the root is read" 3

# ---------------------------------------------------------------------------
# The panel with no setup: the activation record, its acknowledgment, the
# text fallback, and the entry reading the launch environment (REQ-F1.16,
# REQ-F1.2, REQ-A1.7; D-37).
# ---------------------------------------------------------------------------
# run_with <VAR=value>... -- <script> [args...]: mc_run with the session's
# environment set; stdin passes through.
run_with() {
  rw_env=""
  while [ "$1" != -- ]; do
    rw_env="$rw_env $1"
    shift
  done
  shift
  rw_script=$1
  shift
  # shellcheck disable=SC2086 # the VAR=value words split on purpose
  OUT=$(mc_env env $rw_env /bin/bash "$repo_root/scripts/$rw_script" "$@" 2>"$tmp/stderr")
  RC=$?
  ERR=$(cat "$tmp/stderr")
}
field() { awk -F '\t' -v k="$2" '$1 == k { print $2; exit }' "$1" 2>/dev/null; }

setup
sid_a=11111111-2222-3333-4444-555555555555
sid_b=22222222-2222-3333-4444-555555555555
sid_c=33333333-2222-3333-4444-555555555555
sid_d=44444444-2222-3333-4444-555555555555
act=$fleet/mission-control/_panel/active
live_pid=$$
sleep 0 &
dead_pid=$!
wait "$dead_pid"

# The session-start hook records which session this process carries.
OUT=$(printf '{"session_id":"%s","hook_event_name":"SessionStart","source":"startup"}' "$sid_a" \
  | mc_env env CLAUDE_PID="$live_pid" /bin/bash "$repo_root/scripts/mc-panel.sh" session-hook 2>"$tmp/stderr")
RC=$?
expect_rc "the session-start hook exits 0" 0
expect_eq "REQ-F1.16: the session-start hook prints nothing" ""
OUT=$(printf 'not json' | mc_env env CLAUDE_PID="$live_pid" /bin/bash "$repo_root/scripts/mc-panel.sh" session-hook 2>&1)
RC=$?
expect_rc "a hook input with no session id still exits 0" 0
expect_eq "and says nothing" ""

# A session with no mission-control environment: the record verb alone.
run_with CLAUDE_PID="$live_pid" -- mc-panel.sh activate --program alpha --now 5000
expect_rc "REQ-F1.16: the record verb writes the activation record" 0
record "REQ-F1.16: it names the session the hook captured" activation "$sid_a"
if [ "$(field "$act/$sid_a" format)" = 1 ] && [ "$(field "$act/$sid_a" program)" = alpha ] \
  && [ "$(field "$act/$sid_a" session)" = "$sid_a" ] && [ "$(field "$act/$sid_a" pid)" = "$live_pid" ] \
  && [ "$(field "$act/$sid_a" written)" = 5000 ]; then
  ok "REQ-F1.16: the record carries program, session, pid, written time and format"
else
  fail "the activation record reads '$(cat "$act/$sid_a" 2>/dev/null)'"
fi
mc_run mc-panel.sh where
expect_eq "where names the directory the mod watches" "$act"
mc_run mc-panel.sh lookup --session "$sid_a"
expect_rc "REQ-F1.16: the mod's lookup finds its own session's record" 0
record "REQ-F1.16: the lookup names the program" program alpha
record "the wake target defaults to the program" target alpha
mc_run mc-panel.sh lookup --session "$sid_b"
expect_rc "REQ-F1.16: a session with another id finds no record, so does not activate" 1
printf 'format\t2\nprogram\talpha\nsession\t%s\n' "$sid_b" >"$act/$sid_b"
mc_run mc-panel.sh lookup --session "$sid_b"
expect_rc "REQ-F1.16: a record with an unknown format does not activate" 1
rm -f "$act/$sid_b"
printf 'format\t1\nprogram\talpha\nsession\t%s\n' "$sid_a" >"$act/$sid_b"
mc_run mc-panel.sh lookup --session "$sid_b"
expect_rc "a record naming another session does not activate" 1
rm -f "$act/$sid_b"
mc_run mc-panel.sh lookup --session 'bad/../id'
expect_rc "a session id outside the grammar is a usage error" 2
run_with -- mc-panel.sh activate --program alpha
expect_rc "with no session to name, the record verb says so" 4

# The acknowledgment, and the fallback verb reading it.
mc_run mc-panel.sh ack --session "$sid_a" --now 5001
expect_rc "the mod writes its acknowledgment" 0
if [ "$(field "$act/$sid_a.ack" session)" = "$sid_a" ]; then
  ok "REQ-F1.16: the acknowledgment is written beside the record"
else
  fail "no acknowledgment beside the record"
fi
# A claude CLI at or above the floor, so the host's own never decides.
mkdir -p "$tmp/newclaude"
printf '#!/bin/sh\necho "99.0.0 (Claude Code)"\n' >"$tmp/newclaude/claude"
chmod +x "$tmp/newclaude/claude"
run_with CLAUDE_PID="$live_pid" PATH="$tmp/newclaude:$PATH" -- mc-panel.sh await --program alpha --wait 0
expect_rc "await with an acknowledgment" 0
expect_eq "REQ-F1.16: an acknowledged panel is the mod's" "panel${tab}mod"
run_with CLAUDE_PID="$live_pid" -- mc-panel.sh activate --program alpha --now 5002
if [ -f "$act/$sid_a.ack" ]; then
  ok "rewriting the same program keeps the live mod's acknowledgment"
else
  fail "a record rewritten unchanged dropped the acknowledgment"
fi
mc_run mc-panel.sh ack --session "$sid_a"
mc_run mc-panel.sh activate --program alpha --session "$sid_a" --pid 1 --now 5002
if [ ! -e "$act/$sid_a.ack" ]; then
  ok "a record from another process drops an acknowledgment a crashed one left"
else
  fail "an acknowledgment survived a change of process"
fi
run_with CLAUDE_PID="$live_pid" -- mc-panel.sh activate --program alpha --now 5002
mc_run mc-panel.sh ack --session "$sid_a"
# No session-start record names sid_c, so its process cannot be told.
mc_run mc-panel.sh activate --program alpha --session "$sid_c" --now 5002
mc_run mc-panel.sh ack --session "$sid_c"
mc_run mc-panel.sh activate --program alpha --session "$sid_c" --now 5002
if [ "$(field "$act/$sid_c" pid)" = - ] && [ ! -e "$act/$sid_c.ack" ]; then
  ok "a record whose process cannot be told never keeps an acknowledgment"
else
  fail "an acknowledgment survived a pid-less rewrite"
fi
rm -f "$act/$sid_c"
run_with CLAUDE_PID="$live_pid" -- mc-panel.sh activate --program alpha --target mc-other --now 5003
if [ ! -e "$act/$sid_a.ack" ]; then ok "a record naming another target waits for a new acknowledgment"; else fail "the old acknowledgment survived a changed record"; fi
run_with CLAUDE_PID="$live_pid" -- mc-panel.sh activate --program alpha --now 5004
cp "$act/$sid_a" "$act/$sid_b"
mc_run mc-panel.sh ack --session "$sid_b"
expect_rc "an acknowledgment beside a record naming another session is refused" 1
rm -f "$act/$sid_b"

# No acknowledgment: the text form, with its in-flight and waiting lines.
mc_run fleet-state.sh register w-one mission-control:alpha --backend stream-json --death-handle "process $live_pid"
run_with CLAUDE_PID="$live_pid" PATH="$tmp/newclaude:$PATH" -- mc-panel.sh await --program alpha --wait 1
expect_rc "await with no acknowledgment" 0
expect_out "REQ-F1.16: no acknowledgment within the wait reports the text form" "panel${tab}text${tab}no acknowledgment within 1s"
expect_out "REQ-F1.2: the text panel carries the in-flight line" "in flight: 1"
expect_out "the text panel names each flight" "w-one"
expect_out "REQ-F1.2: the text panel carries the waiting line" "waiting on you:"
mc_run mc-panel.sh text --program alpha
expect_rc "the text verb" 0
expect_out "REQ-F1.2: the text output carries the in-flight line" "in flight: 1"
expect_out "REQ-F1.2: the text output carries the waiting line" "waiting on you:"
[ ! -e "$runtime/budget" ] || mv "$runtime/budget" "$runtime/budget.saved"
ln -s "$tmp/nowhere" "$runtime/budget"
mc_run mc-panel.sh text --program alpha
expect_out "an unreadable budget is said as unknown, with why" "rung: unknown (the budget cannot be read)"
rm -f "$runtime/budget"
[ ! -e "$runtime/budget.saved" ] || mv "$runtime/budget.saved" "$runtime/budget"
mkdir -p "$tmp/oldclaude"
printf '#!/bin/sh\necho "2.0.0 (Claude Code)"\n' >"$tmp/oldclaude/claude"
chmod +x "$tmp/oldclaude/claude"
run_with CLAUDE_PID="$live_pid" PATH="$tmp/oldclaude:$PATH" -- mc-panel.sh await --program alpha --wait 5
expect_out "REQ-F1.16: a host below the mods floor is told at once" "panel${tab}text${tab}below the mods floor"
mc_run mc-panel.sh floor
if printf '%s\n' "$OUT" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then ok "the floor verb prints the mods floor"; else fail "the floor verb printed '$OUT'"; fi

# A handover successor's bring-up writes its own record.
run_with CLAUDE_CODE_SESSION_ID="$sid_c" -- mc-panel.sh activate --program alpha --now 5100
record "REQ-F1.16: a successor's bring-up writes its own record" activation "$sid_c"
if [ -f "$act/$sid_c" ] && [ "$(field "$act/$sid_a" session)" = "$sid_a" ]; then
  ok "the predecessor's record is its own, untouched"
else
  fail "the successor's record replaced or missed one"
fi
mc_run mc-panel.sh ack --session "$sid_c"
run_with CLAUDE_CODE_SESSION_ID="$sid_c" -- mc-panel.sh retire
expect_rc "retiring the session" 0
if [ ! -e "$act/$sid_c" ] && [ ! -e "$act/$sid_c.ack" ]; then
  ok "REQ-F1.16: retirement removes the session's record and acknowledgment"
else
  fail "retirement left '$(ls "$act")'"
fi

# The pid a record carries is a live process whose session-start record
# names the session, never an inherited CLAUDE_PID naming another.
printf 'format\t1\nsession\t%s\nwritten\t1\n' "$sid_d" >"$fleet/mission-control/_panel/sessions/$dead_pid"
run_with CLAUDE_PID="$live_pid" -- mc-panel.sh activate --program alpha --session "$sid_d" --now 5150
if [ "$(field "$act/$sid_d" pid)" = - ]; then
  ok "an inherited CLAUDE_PID and a dead process both stay out of the record"
else
  fail "the record carries pid '$(field "$act/$sid_d" pid)'"
fi
rm -f "$fleet/mission-control/_panel/sessions/$dead_pid" "$act/$sid_d"

# The keeper removes a record whose session has no live process.
mc_run mc-panel.sh activate --program alpha --session "$sid_d" --pid "$dead_pid" --now 5200
mc_run mc-panel.sh ack --session "$sid_d"
mc_run mc-keeper.sh watch --program alpha
if [ ! -e "$act/$sid_d" ] && [ ! -e "$act/$sid_d.ack" ]; then
  ok "REQ-F1.16: the keeper removes a record whose session is dead"
else
  fail "the keeper left the dead session's record"
fi
if [ -f "$act/$sid_a" ]; then ok "and keeps a live session's"; else fail "the keeper removed a live session's record"; fi
mc_run mc-panel.sh activate --program alpha --session "$sid_d" --now 5300
mc_run mc-panel.sh prune
if [ "$(field "$act/$sid_d" pid)" = - ] && [ -f "$act/$sid_d" ]; then
  ok "a record with no process to test is kept"
else
  fail "a pid-less record was pruned or carries a pid"
fi
rm -f "$act/$sid_d"
mkfifo "$act/$sid_b"
mc_run mc-panel.sh prune
expect_rc "prune passes over a FIFO named like a record without reading it" 0
rm -f "$act/$sid_b"
fifo="$fleet/mission-control/_panel/sessions/$dead_pid"
mkfifo "$fifo"
(mc_run mc-panel.sh activate --program alpha --session "$sid_d" --now 5400) &
bg=$!
n=0
while kill -0 "$bg" 2>/dev/null && [ "$n" -lt 50 ]; do
  sleep 0.1
  n=$((n + 1))
done
if kill -0 "$bg" 2>/dev/null; then
  fail "activate blocked reading a FIFO named like a session-start record"
  : >"$fifo"
else
  ok "activate passes over a FIFO named like a session-start record without reading it"
fi
wait "$bg"
rm -f "$fifo" "$act/$sid_d" "$act/$sid_d.ack"
chmod 0777 "$act"
mc_run mc-panel.sh lookup --session "$sid_a"
expect_rc "a world-writable activation directory is refused" 1
chmod 0700 "$act"
mv "$fleet/mission-control" "$tmp/mc-real"
ln -s "$tmp/mc-real" "$fleet/mission-control"
mc_run mc-panel.sh lookup --session "$sid_a"
expect_rc "a symlinked mission-control directory is refused" 1
rm -f "$fleet/mission-control"
mv "$tmp/mc-real" "$fleet/mission-control"
if [ "$(jq -r '[.hooks.SessionStart[] | select(has("matcher") | not) | .hooks[].command | select(endswith("scripts/mc-panel.sh session-hook"))] | length' "$repo_root/hooks/hooks.json")" = 1 ]; then
  ok "REQ-F1.16: hooks.json runs the session-start capture on every session start"
else
  fail "hooks.json does not register mc-panel.sh session-hook on every SessionStart"
fi

# The entry reads a program the launch environment names (REQ-A1.7).
cat >>"$tracked" <<EOF
program_beta_repositories: [$repo]
program_beta_spec_root: $repo
EOF
sed 's/^mission_control_programs: \[alpha\]$/mission_control_programs: [alpha, beta]/' "$tracked" >"$tmp/tracked.new"
mv "$tmp/tracked.new" "$tracked"
mc_run mc-config.sh entry
expect_out "two programs with nothing named ask which" "ask${tab}beta"
run_with PLANWRIGHT_MC_PROGRAM=beta -- mc-config.sh entry
expect_eq "REQ-A1.7: the program the launch environment names resumes without asking" "resume${tab}beta"
run_with CLAUDE_PID="$live_pid" -- mc-config.sh entry
expect_eq "REQ-A1.7: a session already activated resumes its own program" "resume${tab}alpha"
run_with PLANWRIGHT_MC_PROGRAM=gamma -- mc-config.sh entry
expect_out "a variable naming no configured program falls back to asking" "ask${tab}alpha"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-panel: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-panel: all passed"
